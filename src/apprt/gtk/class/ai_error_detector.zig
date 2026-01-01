//! AI Error Detector
//! Automatically detects errors in terminal output and suggests AI-powered fixes

const std = @import("std");
const Allocator = std.mem.Allocator;

const gtk = @import("gtk");
const glib = @import("glib");
const gobject = @import("gobject");

const Common = @import("../class.zig").Common;
const Application = @import("application.zig").Application;
const Surface = @import("surface.zig").Surface;

const AiCommandSearch = @import("ai_command_search.zig").AiCommandSearch;

const log = std.log.scoped(.ai_error_detector);

/// Common error patterns that indicate something went wrong
const ErrorPattern = struct {
    pattern: []const u8,
    description: []const u8,
    severity: enum { info, warning, err, critical },
};

/// List of error patterns to detect
const error_patterns = [_]ErrorPattern{
    .{ .pattern = "error:", .description = "Command failed", .severity = .err },
    .{ .pattern = "Error:", .description = "Error detected", .severity = .err },
    .{ .pattern = "failed", .description = "Operation failed", .severity = .err },
    .{ .pattern = "Failed", .description = "Operation failed", .severity = .err },
    .{ .pattern = "command not found", .description = "Command not found", .severity = .err },
    .{ .pattern = "No such file or directory", .description = "File not found", .severity = .err },
    .{ .pattern = "Permission denied", .description = "Permission error", .severity = .err },
    .{ .pattern = " Segmentation fault", .description = "Segmentation fault", .severity = .critical },
    .{ .pattern = "core dumped", .description = "Core dumped", .severity = .critical },
    .{ .pattern = "warning:", .description = "Warning", .severity = .warning },
    .{ .pattern = "Warning:", .description = "Warning", .severity = .warning },
    .{ .pattern = "deprecated", .description = "Deprecated feature", .severity = .info },
};

pub const AIErrorDetector = extern struct {
    const C = Common(Self, Private);
    pub const as = C.as;
    pub const ref = C.ref;
    pub const unref = C.unref;
    pub const refSink = C.refSink;
    const getPriv = C.getPriv;
    const Self = @This();
    pub const Parent = gtk.Box;

    parent_instance: Parent,

    const Private = struct {
        surface: ?*Surface = null,
        error_suggestion_widget: ?*gtk.Popover = null,
        last_error_text: ?[]const u8 = null,
        error_count: u32 = 0,

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
            const alloc = Application.default().allocator();

            if (priv.last_error_text) |text| {
                alloc.free(text);
            }
            if (priv.error_suggestion_widget) |widget| {
                widget.unref();
            }

            gobject.Object.virtual_methods.dispose.call(Class.parent, self.as(Parent));
        }

        pub const as = C.Class.as;
    };

    pub const getGObjectType = gobject.ext.defineClass(Self, .{
        .name = "GhosttyAIErrorDetector",
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

        return self.ref();
    }

    fn init(self: *Self) callconv(.c) void {
        const priv = getPriv(self);

        // Create error suggestion popover
        const popover = gtk.Popover.new();
        priv.error_suggestion_widget = popover;

        // Set up popover content
        const box = gtk.Box.new(gtk.Orientation.vertical, 8);
        box.setMarginStart(12);
        box.setMarginEnd(12);
        box.setMarginTop(12);
        box.setMarginBottom(12);

        const title = gtk.Label.new("AI Suggestion");
        title.getStyleContext().addClass("heading");
        box.append(title.as(gtk.Widget));

        const message = gtk.Label.new("An error was detected. Click 'Get AI Help' for suggestions.");
        message.setWrap(true);
        box.append(message.as(gtk.Widget));

        const button_box = gtk.Box.new(gtk.Orientation.horizontal, 8);
        button_box.setHalign(gtk.Align.end);

        const help_btn = gtk.Button.newWithLabel("Get AI Help");
        _ = help_btn.connectClicked(&showAIHelp, self);
        button_box.append(help_btn.as(gtk.Widget));

        const dismiss_btn = gtk.Button.newWithLabel("Dismiss");
        _ = dismiss_btn.connectClicked(&dismissError, self);
        button_box.append(dismiss_btn.as(gtk.Widget));

        box.append(button_box.as(gtk.Widget));

        popover.setChild(box.as(gtk.Widget));
        popover.setVisible(false);

        log.info("AI Error Detector initialized", .{});
    }

    /// Check if new output contains errors and trigger AI suggestions if needed
    pub fn checkForErrors(self: *Self, output: []const u8) void {
        const priv = getPriv(self);

        // Check output against error patterns
        for (error_patterns) |pattern| {
            if (std.mem.indexOf(u8, output, pattern.pattern)) |_| {
                // Error detected!
                priv.error_count += 1;

                log.debug("Detected error pattern: {s} (count: {})", .{ pattern.pattern, priv.error_count });

                // Don't show suggestions for every single error line
                if (priv.error_count % 5 == 0) {
                    // Show AI suggestion popup
                    _ = glib.idleAdd(struct {
                        fn callback(detector: *Self, pattern_info: ErrorPattern) callconv(.c) c_int {
                            const priv_cb = getPriv(detector);
                            if (priv_cb.error_suggestion_widget) |popover| {
                                // Update popover content
                                const child = popover.getChild() orelse return 0;
                                const box = child.as(gtk.Box);

                                // Find the message label (second child)
                                if (box.getFirstChild()) |title| {
                                    if (title.getNextSibling()) |message| {
                                        const message_text = std.fmt.allocPrintZ(
                                            Application.default().allocator(),
                                            "Detected: {s}\n\nClick 'Get AI Help' for suggested fixes.",
                                            .{pattern_info.description},
                                        ) catch return 0;
                                        defer Application.default().allocator().free(message_text);

                                        message.as(gtk.Label).setText(message_text);
                                    }
                                }

                                // Position and show popover
                                if (priv_cb.surface) |surface| {
                                    const surface_widget = surface.as(gtk.Widget);
                                    popover.setRelativeTo(surface_widget);
                                    popover.setVisible(true);
                                }
                            }
                            return 0;
                        }
                    }.callback, self, pattern);
                }

                break;
            }
        }
    }

    fn showAIHelp(button: *gtk.Button, self: *Self) callconv(.c) void {
        _ = button;
        const priv = getPriv(self);

        // Hide error popup
        if (priv.error_suggestion_widget) |popover| {
            popover.setVisible(false);
        }

        // Open AI command search with error context
        if (priv.surface) |_| {
            log.info("Opening AI command search for error help", .{});

            // TODO: Pass error context to AI command search
            // This would involve:
            // 1. Getting the recent error output
            // 2. Opening the AI command search dialog
            // 3. Pre-populating with error context
        }
    }

    fn dismissError(button: *gtk.Button, self: *Self) callconv(.c) void {
        _ = button;
        const priv = getPriv(self);

        // Hide error popup
        if (priv.error_suggestion_widget) |popover| {
            popover.setVisible(false);
        }

        // Optionally reset error count after a period of no errors
        _ = glib.timeoutAdd(10000, struct {
            fn callback(detector: *Self) callconv(.c) c_int {
                const priv_cb = getPriv(detector);
                priv_cb.error_count = 0;
                return 0; // G_SOURCE_REMOVE
            }
        }.callback, self);
    }

    pub fn show(self: *Self) void {
        self.as(gtk.Widget).show();
    }

    pub fn hide(self: *Self) void {
        self.as(gtk.Widget).hide();
    }
};
