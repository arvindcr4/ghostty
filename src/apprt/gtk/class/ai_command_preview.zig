//! Command Execution Preview
//! Provides Warp-like preview dialog before executing commands

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

const log = std.log.scoped(.gtk_ghostty_command_preview);

pub const CommandPreviewDialog = extern struct {
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
        command_text: ?*gtk.TextView = null,
        preview_text: ?*gtk.TextView = null,
        warnings_list: ?*gtk.ListView = null,
        warnings_store: ?*gio.ListStore = null,

        pub var offset: c_int = 0;
    };

    pub const WarningItem = extern struct {
        parent_instance: gobject.Object,
        message: [:0]const u8,
        severity: WarningSeverity,

        pub const Parent = gobject.Object;
        pub const WarningSeverity = enum {
            info,
            warning,
            err,
        };

        pub const getGObjectType = gobject.ext.defineClass(WarningItem, .{
            .name = "GhosttyWarningItem",
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

        pub fn new(alloc: Allocator, message: []const u8, severity: WarningSeverity) !*WarningItem {
            const self = gobject.ext.newInstance(WarningItem, .{});
            self.message = try alloc.dupeZ(u8, message);
            errdefer alloc.free(self.message);
            self.severity = severity;
            return self;
        }

        pub fn deinit(self: *WarningItem, alloc: Allocator) void {
            alloc.free(self.message);
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
        .name = "GhosttyCommandPreviewDialog",
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

        self.as(adw.MessageDialog).setHeading("Command Preview");
        self.as(adw.MessageDialog).setBody("Review the command before execution");
        self.as(adw.MessageDialog).setCloseResponse("cancel");
        self.as(adw.MessageDialog).setModal(@intFromBool(true));

        // Create custom content area
        const content_area = self.as(adw.MessageDialog).getChild() orelse return;
        const content_box = content_area.as(gtk.Box);
        const box = gtk.Box.new(gtk.Orientation.vertical, 12);
        box.setMarginStart(12);
        box.setMarginEnd(12);
        box.setMarginTop(12);
        box.setMarginBottom(12);

        // Command display
        const command_label = gtk.Label.new("Command:");
        command_label.setXalign(0);
        box.append(command_label.as(gtk.Widget));

        const command_scrolled = gtk.ScrolledWindow.new();
        command_scrolled.setMinContentHeight(80);
        command_scrolled.setPolicy(gtk.PolicyType.automatic, gtk.PolicyType.automatic);

        const command_buffer = gtk.TextBuffer.new(null);
        const command_view = gtk.TextView.newWithBuffer(command_buffer);
        command_view.setEditable(@intFromBool(false));
        command_view.setMonospace(@intFromBool(true));
        priv.command_text = command_view;
        command_scrolled.setChild(command_view.as(gtk.Widget));
        box.append(command_scrolled.as(gtk.Widget));

        // Preview/Expected output
        const preview_label = gtk.Label.new("Expected Output Preview:");
        preview_label.setXalign(0);
        preview_label.getStyleContext().addClass("heading");
        box.append(preview_label.as(gtk.Widget));

        const preview_scrolled = gtk.ScrolledWindow.new();
        preview_scrolled.setMinContentHeight(150);
        preview_scrolled.setPolicy(gtk.PolicyType.automatic, gtk.PolicyType.automatic);

        const preview_buffer = gtk.TextBuffer.new(null);
        const preview_view = gtk.TextView.newWithBuffer(preview_buffer);
        preview_view.setEditable(@intFromBool(false));
        preview_view.setMonospace(@intFromBool(true));
        priv.preview_text = preview_view;
        preview_scrolled.setChild(preview_view.as(gtk.Widget));
        box.append(preview_scrolled.as(gtk.Widget));

        // Warnings
        const warnings_label = gtk.Label.new("Warnings:");
        warnings_label.setXalign(0);
        warnings_label.getStyleContext().addClass("heading");
        box.append(warnings_label.as(gtk.Widget));

        const warnings_scrolled = gtk.ScrolledWindow.new();
        warnings_scrolled.setMaxContentHeight(100);
        warnings_scrolled.setPolicy(gtk.PolicyType.never, gtk.PolicyType.automatic);

        const warnings_store = gio.ListStore.new(WarningItem.getGObjectType());
        priv.warnings_store = warnings_store;

        const selection = gtk.NoSelection.new(warnings_store.as(gio.ListModel));
        const factory = gtk.SignalListItemFactory.new();
        _ = factory.connectSetup(*anyopaque, &setupWarningItem, null, .{});
        _ = factory.connectBind(*anyopaque, &bindWarningItem, null, .{});

        const warnings_list = gtk.ListView.new(selection.as(gtk.SelectionModel), factory.as(gtk.ListItemFactory));
        priv.warnings_list = warnings_list;
        warnings_scrolled.setChild(warnings_list.as(gtk.Widget));
        box.append(warnings_scrolled.as(gtk.Widget));

        content_box.append(box.as(gtk.Widget));

        self.as(adw.MessageDialog).addResponse("execute", "Execute");
        self.as(adw.MessageDialog).addResponse("cancel", "Cancel");
        self.as(adw.MessageDialog).setDefaultResponse("execute");
    }

    fn setupWarningItem(_: *gtk.SignalListItemFactory, item: *gtk.ListItem, _: ?*anyopaque) callconv(.c) void {
        const label = gtk.Label.new("");
        label.setXalign(0);
        label.setWrap(@intFromBool(true));
        item.setChild(label.as(gtk.Widget));
    }

    fn bindWarningItem(_: *gtk.SignalListItemFactory, item: *gtk.ListItem, _: ?*anyopaque) callconv(.c) void {
        const entry = item.getItem() orelse return;
        const warning_item = @as(*WarningItem, @ptrCast(entry));
        const label = item.getChild() orelse return;
        label.as(gtk.Label).setText(warning_item.message);
    }

    fn dispose(self: *Self) callconv(.c) void {
        const priv = getPriv(self);
        const alloc = Application.default().allocator();

        // Clean up all warning items
        if (priv.warnings_store) |store| {
            const n = store.getNItems();
            var i: u32 = 0;
            while (i < n) : (i += 1) {
                if (store.getItem(i)) |item| {
                    const warning_item: *WarningItem = @ptrCast(@alignCast(item));
                    warning_item.deinit(alloc);
                }
            }
        }

        gobject.Object.virtual_methods.dispose.call(Class.parent, self.as(Parent));
    }

    pub fn setCommand(self: *Self, command: []const u8) void {
        const priv = getPriv(self);
        if (priv.command_text) |view| {
            const buffer = view.getBuffer();
            const command_z = std.fmt.allocPrintZ(Application.default().allocator(), "{s}", .{command}) catch return;
            defer Application.default().allocator().free(command_z);
            buffer.setText(command_z, -1);
        }
    }

    pub fn setPreview(self: *Self, preview: []const u8) void {
        const priv = getPriv(self);
        if (priv.preview_text) |view| {
            const buffer = view.getBuffer();
            const preview_z = std.fmt.allocPrintZ(Application.default().allocator(), "{s}", .{preview}) catch return;
            defer Application.default().allocator().free(preview_z);
            buffer.setText(preview_z, -1);
        }
    }

    pub fn addWarning(self: *Self, message: []const u8, severity: WarningItem.WarningSeverity) void {
        const priv = getPriv(self);
        const alloc = Application.default().allocator();

        const warning = WarningItem.new(alloc, message, severity) catch {
            log.err("Failed to create warning item", .{});
            return;
        };

        if (priv.warnings_store) |store| {
            store.append(warning.as(gobject.Object));
        }
    }

    pub fn show(self: *Self, parent: *Window) void {
        self.as(adw.MessageDialog).setTransientFor(parent.as(gtk.Window));
        self.as(adw.MessageDialog).present();
    }
};
