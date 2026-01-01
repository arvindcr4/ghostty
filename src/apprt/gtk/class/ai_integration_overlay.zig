//! AI Integration Overlay
//! Provides AI command search (# prefix), inline suggestions, and error detection

const std = @import("std");
const Allocator = std.mem.Allocator;

const adw = @import("adw");
const gtk = @import("gtk");
const gdk = @import("gdk");
const glib = @import("glib");
const gio = @import("gio");
const gobject = @import("gobject");

const Common = @import("../class.zig").Common;
const Application = @import("application.zig").Application;
const Window = @import("window.zig").Window;
const Surface = @import("surface.zig").Surface;

const AiCommandSearch = @import("ai_command_search.zig").AiCommandSearch;
const InlineSuggestions = @import("ai_inline_suggestions.zig").InlineSuggestions;
const AIErrorDetector = @import("ai_error_detector.zig").AIErrorDetector;

const log = std.log.scoped(.ai_integration_overlay);

pub const AIIntegrationOverlay = extern struct {
    const C = Common(Self, Private);
    pub const as = C.as;
    pub const ref = C.ref;
    pub const unref = C.unref;
    pub const refSink = C.refSink;
    const getPriv = C.getPriv;
    const Self = @This();

    parent_instance: Parent,
    pub const Parent = gtk.Overlay;

    const Private = struct {
        surface: ?*Surface = null,
        command_search: ?*AiCommandSearch = null,
        inline_suggestions: ?*InlineSuggestions = null,
        error_detector: ?*AIErrorDetector = null,

        /// Current command line text being edited
        current_line: std.ArrayList(u8) = std.ArrayList(u8).init(std.heap.page_allocator),

        /// Position where suggestions should appear
        suggestion_pos: gtk.Widget.Anchor = gtk.Widget.Anchor{},

        /// Debounce timer for inline suggestions
        suggestion_timer: ?*glib.Source = null,

        pub var offset: c_int = 0;
    };

    pub const Class = extern struct {
        parent_class: Parent.Class,
        var parent: *Parent.Class = undefined;

        fn init(class: *Class) callconv(.c) void {
            gobject.Object.virtual_methods.dispose.implement(class, &dispose);
        }

        fn dispose(self: *Self) callconv(.c) void {
            const priv = getPriv(self);

            // Clean up timers
            if (priv.suggestion_timer) |timer| {
                glib.sourceDestroy(timer);
            }

            // Clean up arrays
            priv.current_line.deinit();

            gobject.Object.virtual_methods.dispose.call(Class.parent, self.as(Parent));
        }

        pub const as = C.Class.as;
    };

    pub const getGObjectType = gobject.ext.defineClass(Self, .{
        .name = "GhosttyAIIntegrationOverlay",
        .instanceInit = &init,
        .classInit = &Class.init,
        .parent_class = &Class.parent,
        .private = .{ .Type = Private, .offset = &Private.offset },
    });

    pub fn new(surface: *Surface) *Self {
        const self = gobject.ext.newInstance(Self, .{});
        _ = self.refSink();

        const priv = getPriv(self);
        priv.surface = surface;

        // Initialize error detector (requires surface, so done in new() not init())
        priv.error_detector = AIErrorDetector.new(surface);

        // Add overlay as child of surface
        const surface_widget = surface.as(gtk.Widget);
        surface_widget.insertAfter(self.as(gtk.Widget), null);

        return self.ref();
    }

    fn init(self: *Self) callconv(.c) void {
        const priv = getPriv(self);

        // Initialize command search widget
        const command_search = AiCommandSearch.new() catch {
            log.err("Failed to create AI command search widget", .{});
            return;
        };
        priv.command_search = command_search;
        command_search.setVisible(false);
        self.as(gtk.Overlay).addOverlay(command_search.as(gtk.Widget));

        // Initialize inline suggestions widget
        const inline_suggestions = InlineSuggestions.new() catch {
            log.err("Failed to create inline suggestions widget", .{});
            return;
        };
        priv.inline_suggestions = inline_suggestions;
        inline_suggestions.setVisible(false);
        self.as(gtk.Overlay).addOverlay(inline_suggestions.as(gtk.Widget));

        log.info("AI Integration Overlay initialized", .{});
    }

    /// Process a key press event and determine if AI features should be triggered
    pub fn processKeyPress(
        self: *Self,
        keyval: c_uint,
        _: c_uint, // keycode - reserved for future use
        _: gdk.ModifierType, // mods - reserved for future use
    ) bool {
        const priv = getPriv(self);

        // Get current character from key event
        const key_name = gdk.keyvalName(keyval) orelse return false;

        // Check for # prefix (AI command search)
        if (key_name.len > 0 and key_name[0] == '#') {
            // User typed #, show command search
            if (priv.command_search) |_| {
                _ = glib.idleAdd(struct {
                    fn callback(overlay: *Self) callconv(.c) c_int {
                        const priv_cb = getPriv(overlay);
                        if (priv_cb.command_search) |search_cb| {
                            search_cb.setVisible(true);
                            search_cb.focusSearch();
                        }
                        return 0;
                    }
                }.callback, self);
            }
            return false; // Allow # to be processed normally
        }

        // Check for alphanumeric characters (potential command)
        if (key_name.len == 1) {
            const c = key_name[0];
            if ((c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z') or (c >= '0' and c <= '9') or
                c == '-' or c == '_' or c == '.') {
                // Append to current line
                priv.current_line.append(c) catch {
                    log.warn("Failed to append to current line", .{});
                };

                // Trigger inline suggestions after debounce
                if (priv.suggestion_timer) |timer| {
                    glib.sourceDestroy(timer);
                }

                priv.suggestion_timer = glib.timeoutAdd(300, struct {
                    fn callback(overlay: *Self) callconv(.c) c_int {
                        _ = getPriv(overlay);
                        overlay.updateInlineSuggestions();
                        return 0; // G_SOURCE_REMOVE
                    }
                }.callback, self);
            }
        }

        // Handle backspace
        if (key_name.len > 0 and std.mem.eql(u8, key_name, "BackSpace")) {
            if (priv.current_line.items.len > 0) {
                _ = priv.current_line.pop();
                if (priv.current_line.items.len == 0) {
                    // Line is empty, hide suggestions
                    if (priv.inline_suggestions) |suggestions| {
                        suggestions.setVisible(false);
                    }
                } else {
                    // Update suggestions
                    if (priv.suggestion_timer) |timer| {
                        glib.sourceDestroy(timer);
                    }
                    priv.suggestion_timer = glib.timeoutAdd(300, struct {
                        fn callback(overlay: *Self) callconv(.c) c_int {
                            _ = getPriv(overlay);
                            overlay.updateInlineSuggestions();
                            return 0; // G_SOURCE_REMOVE
                        }
                    }.callback, self);
                }
            }
        }

        // Handle Enter (commit current line)
        if (key_name.len > 0 and std.mem.eql(u8, key_name, "Return")) {
            priv.current_line.clearRetainingCapacity();
            if (priv.inline_suggestions) |suggestions| {
                suggestions.setVisible(false);
            }
        }

        return false;
    }

    /// Update inline suggestions based on current line
    fn updateInlineSuggestions(self: *Self) void {
        const priv = getPriv(self);

        if (priv.current_line.items.len < 3) {
            // Too short for suggestions
            if (priv.inline_suggestions) |suggestions| {
                suggestions.setVisible(false);
            }
            return;
        }

        const query = priv.current_line.items;

        log.debug("Requesting inline suggestions for: {s}", .{query});

        // TODO: Integrate with AI to get suggestions
        // For now, show placeholder suggestions

        if (priv.inline_suggestions) |suggestions| {
            suggestions.setVisible(true);
            // For now, show some example suggestions based on the query
            // In a real implementation, this would call the AI service
            log.debug("Showing inline suggestions for query: {s}", .{query});

            // TODO: Integrate with AI to get real suggestions
            // suggestions.updateSuggestions(query);
        }
    }

    /// Show AI suggestions for detected errors in terminal output
    pub fn showErrorSuggestions(self: *Self, error_text: []const u8) void {
        const priv = getPriv(self);

        log.debug("Detected error, showing AI suggestions: {s}", .{error_text});

        // Delegate to error detector
        if (priv.error_detector) |detector| {
            detector.checkForErrors(error_text);
        }
    }

    /// Public method to check terminal output for errors
    pub fn checkTerminalOutput(self: *Self, output: []const u8) void {
        const priv = getPriv(self);

        // Delegate to error detector
        if (priv.error_detector) |detector| {
            detector.checkForErrors(output);
        }
    }

    pub fn show(self: *Self) void {
        self.as(gtk.Widget).show();
    }

    pub fn hide(self: *Self) void {
        self.as(gtk.Widget).hide();

        const priv = getPriv(self);
        if (priv.command_search) |search| {
            search.setVisible(false);
        }
        if (priv.inline_suggestions) |suggestions| {
            suggestions.setVisible(false);
        }
    }
};
