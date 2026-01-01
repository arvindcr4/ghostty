//! Error Recovery Suggestions UI
//! Provides Warp-like error recovery with AI-suggested fixes

const std = @import("std");
const Allocator = std.mem.Allocator;

const adw = @import("adw");
const gio = @import("gio");
const glib = @import("glib");
const gobject = @import("gobject");
const gtk = @import("gtk");

const Common = @import("../class.zig").Common;
const Application = @import("application.zig").Application;
const Window = @import("window.zig").Window;

const log = std.log.scoped(.gtk_ghostty_error_recovery);

pub const ErrorRecoveryDialog = extern struct {
    const C = Common(Self, Private);
    pub const as = C.as;
    pub const ref = C.ref;
    pub const unref = C.unref;
    pub const refSink = C.refSink;
    const getPriv = C.getPriv;
    const Self = @This();

    parent_instance: Parent,
    pub const Parent = adw.MessageDialog;

    const Private = struct {
        error_text: ?*gtk.TextView = null,
        fixes_list: ?*gtk.ListView = null,
        fixes_store: ?*gio.ListStore = null,

        pub var offset: c_int = 0;
    };

    pub const FixItem = extern struct {
        parent_instance: gobject.Object,
        description: [:0]const u8,
        command: [:0]const u8,
        confidence: f32,

        pub const Parent = gobject.Object;
        pub const getGObjectType = gobject.ext.defineClass(FixItem, .{
            .name = "GhosttyFixItem",
            .classInit = &ItemClass.init,
            .parent_class = &ItemClass.parent,
        });

        pub const ItemClass = extern struct {
            parent_class: gobject.Object.Class,
            var parent: *gobject.Object.Class = undefined;

            fn init(class: *ItemClass) callconv(.c) void {
                _ = class;
            }
        };

        pub fn new(alloc: Allocator, description: []const u8, command: []const u8, confidence: f32) !*FixItem {
            const self = gobject.ext.newInstance(FixItem, .{});
            self.description = try alloc.dupeZ(u8, description);
            errdefer alloc.free(self.description);
            self.command = try alloc.dupeZ(u8, command);
            errdefer alloc.free(self.command);
            self.confidence = confidence;
            return self;
        }

        pub fn deinit(self: *FixItem, alloc: Allocator) void {
            alloc.free(self.description);
            alloc.free(self.command);
        }
    };

    pub const Class = extern struct {
        parent_class: Parent.Class,
        var parent: *Parent.Class = undefined;

        fn init(class: *Class) callconv(.c) void {
            gobject.Object.virtual_methods.dispose.implement(class, &dispose);
        }

        pub const as = C.Class.as;
    };

    pub const getGObjectType = gobject.ext.defineClass(Self, .{
        .name = "GhosttyErrorRecoveryDialog",
        .instanceInit = &init,
        .classInit = &Class.init,
        .parent_class = &Class.parent,
        .private = .{ .Type = Private, .offset = &Private.offset },
    });

    pub fn new() *Self {
        const self = gobject.ext.newInstance(Self, .{});
        _ = self.refSink();
        return self.ref();
    }

    fn init(self: *Self) callconv(.c) void {
        const priv = getPriv(self);

        self.as(adw.MessageDialog).setHeading("Error Recovery");
        self.as(adw.MessageDialog).setBody("AI-suggested fixes for the error");
        self.as(adw.MessageDialog).setCloseResponse("close");
        self.as(adw.MessageDialog).setModal(@intFromBool(true));

        // Create custom content area
        const content_area = self.as(adw.MessageDialog).getChild() orelse return;
        const content_box = content_area.as(gtk.Box);
        const box = gtk.Box.new(gtk.Orientation.vertical, 12);
        box.setMarginStart(12);
        box.setMarginEnd(12);
        box.setMarginTop(12);
        box.setMarginBottom(12);

        // Error text
        const error_label = gtk.Label.new("Error Output:");
        error_label.setXalign(0);
        box.append(error_label.as(gtk.Widget));

        const error_scrolled = gtk.ScrolledWindow.new();
        error_scrolled.setMinContentHeight(100);
        error_scrolled.setPolicy(gtk.PolicyType.automatic, gtk.PolicyType.automatic);

        const error_buffer = gtk.TextBuffer.new(null);
        const error_view = gtk.TextView.newWithBuffer(error_buffer);
        error_view.setEditable(@intFromBool(false));
        error_view.setMonospace(@intFromBool(true));
        priv.error_text = error_view;
        error_scrolled.setChild(error_view.as(gtk.Widget));
        box.append(error_scrolled.as(gtk.Widget));

        // Fixes list
        const fixes_label = gtk.Label.new("Suggested Fixes:");
        fixes_label.setXalign(0);
        fixes_label.getStyleContext().addClass("heading");
        box.append(fixes_label.as(gtk.Widget));

        const fixes_scrolled = gtk.ScrolledWindow.new();
        fixes_scrolled.setMinContentHeight(200);
        fixes_scrolled.setPolicy(gtk.PolicyType.never, gtk.PolicyType.automatic);

        const fixes_store = gio.ListStore.new(FixItem.getGObjectType());
        priv.fixes_store = fixes_store;

        const selection = gtk.SingleSelection.new(fixes_store.as(gio.ListModel));
        const factory = gtk.SignalListItemFactory.new();
        _ = factory.connectSetup(*anyopaque, &setupFixItem, null, .{});
        _ = factory.connectBind(*anyopaque, &bindFixItem, null, .{});

        const fixes_list = gtk.ListView.new(selection.as(gtk.SelectionModel), factory.as(gtk.ListItemFactory));
        priv.fixes_list = fixes_list;
        fixes_scrolled.setChild(fixes_list.as(gtk.Widget));
        box.append(fixes_scrolled.as(gtk.Widget));

        content_box.append(box.as(gtk.Widget));

        self.addResponse("close", "Close");
        self.setDefaultResponse("close");
    }

    fn setupFixItem(_: *gtk.SignalListItemFactory, item: *gtk.ListItem, _: ?*anyopaque) callconv(.c) void {
        const box = gtk.Box.new(gtk.Orientation.vertical, 8);
        box.setMarginStart(8);
        box.setMarginEnd(8);
        box.setMarginTop(4);
        box.setMarginBottom(4);

        const desc_label = gtk.Label.new("");
        desc_label.setXalign(0);
        desc_label.setWrap(@intFromBool(true));
        box.append(desc_label.as(gtk.Widget));

        const command_label = gtk.Label.new("");
        command_label.setXalign(0);
        command_label.getStyleContext().addClass("monospace");
        box.append(command_label.as(gtk.Widget));

        const apply_btn = gtk.Button.new();
        apply_btn.setLabel("Apply Fix");
        apply_btn.setIconName("system-run-symbolic");
        box.append(apply_btn.as(gtk.Widget));

        item.setChild(box.as(gtk.Widget));
    }

    fn bindFixItem(_: *gtk.SignalListItemFactory, item: *gtk.ListItem, _: ?*anyopaque) callconv(.c) void {
        const entry = item.getItem() orelse return;
        const fix_item = @as(*FixItem, @ptrCast(entry));
        const box = item.getChild() orelse return;
        const box_widget = box.as(gtk.Box);

        if (box_widget.getFirstChild()) |desc| {
            desc.as(gtk.Label).setText(fix_item.description);
            if (desc.getNextSibling()) |command| {
                command.as(gtk.Label).setText(fix_item.command);
                if (command.getNextSibling()) |apply_btn| {
                    // Connect button click handler
                    _ = apply_btn.as(gtk.Button).connectClicked(&applyFix, fix_item);
                }
            }
        }
    }

    fn applyFix(_: *gtk.Button, fix_item: *FixItem) callconv(.c) void {
        log.info("Applying fix: {s}", .{fix_item.command});
        // TODO: Execute the fix command in the terminal
        // For now, just log that we would apply the fix
    }

    fn dispose(self: *Self) callconv(.c) void {
        const priv = getPriv(self);
        const alloc = Application.default().allocator();

        // Clean up all fix items
        if (priv.fixes_store) |store| {
            const n = store.getNItems();
            var i: u32 = 0;
            while (i < n) : (i += 1) {
                if (store.getItem(i)) |item| {
                    const fix_item: *FixItem = @ptrCast(@alignCast(item));
                    fix_item.deinit(alloc);
                }
            }
        }

        gobject.Object.virtual_methods.dispose.call(Class.parent, self.as(Parent));
    }

    pub fn setError(self: *Self, error_text: []const u8) void {
        const priv = getPriv(self);
        if (priv.error_text) |view| {
            const buffer = view.getBuffer();
            const error_z = std.fmt.allocPrintZ(Application.default().allocator(), "{s}", .{error_text}) catch return;
            defer Application.default().allocator().free(error_z);
            buffer.setText(error_z, -1);
        }
    }

    pub fn addFix(self: *Self, description: []const u8, command: []const u8, confidence: f32) void {
        const priv = getPriv(self);
        const alloc = Application.default().allocator();

        const fix = FixItem.new(alloc, description, command, confidence) catch {
            log.err("Failed to create fix item", .{});
            return;
        };

        if (priv.fixes_store) |store| {
            store.append(fix.as(gobject.Object));
        }
    }

    pub fn show(self: *Self, parent: *Window) void {
        self.as(adw.MessageDialog).setTransientFor(parent.as(gtk.Window));
        self.as(adw.MessageDialog).present();
    }
};
