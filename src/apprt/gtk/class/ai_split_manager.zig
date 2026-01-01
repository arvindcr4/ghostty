//! Terminal Split Manager UI
//! Provides Warp-like UI for managing split terminal panes

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

const log = std.log.scoped(.gtk_ghostty_split_manager);

pub const SplitManagerDialog = extern struct {
    const C = Common(Self, Private);
    pub const as = C.as;
    pub const ref = C.ref;
    pub const unref = C.unref;
    pub const refSink = C.refSink;
    const getPriv = C.getPriv;
    const Self = @This();

    parent_instance: Parent,
    pub const Parent = adw.PreferencesWindow;

    const Private = struct {
        splits_list: ?*gtk.ListView = null,
        splits_store: ?*gio.ListStore = null,
        add_split_btn: ?*gtk.Button = null,
        pub var offset: c_int = 0;
    };

    pub const SplitItem = extern struct {
        parent_instance: gobject.Object,
        id: [:0]const u8,
        title: [:0]const u8,
        cwd: [:0]const u8,
        orientation: SplitOrientation,
        position: u32,

        pub const Parent = gobject.Object;

        pub const SplitOrientation = enum {
            horizontal,
            vertical,
        };

        pub const ItemClass = extern struct {
            parent_class: gobject.Object.Class,
            var parent: *gobject.Object.Class = undefined;

            fn init(class: *ItemClass) callconv(.c) void {
                gobject.Object.virtual_methods.dispose.implement(class, &SplitItem.dispose);
            }

            fn dispose(self: *SplitItem) callconv(.c) void {
                const alloc = Application.default().allocator();
                alloc.free(self.id);
                alloc.free(self.title);
                alloc.free(self.cwd);
                gobject.Object.virtual_methods.dispose.call(ItemClass.parent, self);
            }
        };

        pub const getGObjectType = gobject.ext.defineClass(SplitItem, .{
            .name = "GhosttySplitItem",
            .classInit = &ItemClass.init,
            .parent_class = &ItemClass.parent,
        });

        pub fn new(alloc: Allocator, id: []const u8, title: []const u8, cwd: []const u8, orientation: SplitOrientation, position: u32) !*SplitItem {
            const self = gobject.ext.newInstance(SplitItem, .{});
            self.id = try alloc.dupeZ(u8, id);
            errdefer alloc.free(self.id);
            self.title = try alloc.dupeZ(u8, title);
            errdefer alloc.free(self.title);
            self.cwd = try alloc.dupeZ(u8, cwd);
            errdefer alloc.free(self.cwd);
            self.orientation = orientation;
            self.position = position;
            return self;
        }

        pub fn deinit(self: *SplitItem, alloc: Allocator) void {
            alloc.free(self.id);
            alloc.free(self.title);
            alloc.free(self.cwd);
        }
    };

    pub const Class = extern struct {
        parent_class: Parent.Class,
        var parent: *Parent.Class = undefined;

        fn init(class: *Class) callconv(.c) void {
            gobject.Object.virtual_methods.dispose.implement(class, &dispose);
        }

        fn dispose(self: *Self) callconv(.c) void {
            const priv = getPriv(self);
            if (priv.splits_store) |store| {
                store.removeAll();
            }
            gobject.Object.virtual_methods.dispose.call(Class.parent, self.as(Parent));
        }

        pub const as = C.Class.as;
    };

    pub const getGObjectType = gobject.ext.defineClass(Self, .{
        .name = "GhosttySplitManagerDialog",
        .instanceInit = &init,
        .classInit = &Class.init,
        .parent_class = &Class.parent,
        .private = .{ .Type = Private, .offset = &Private.offset },
    });

    pub fn new() *Self {
        const self = gobject.ext.newInstance(Self, .{});
        return self.refSink();
    }

    fn init(self: *Self) callconv(.c) void {
        const priv = getPriv(self);
        self.as(adw.PreferencesWindow).setTitle("Split Manager");

        // Create splits store
        const store = gio.ListStore.new(SplitItem.getGObjectType());
        priv.splits_store = store;

        // Create add button
        const add_btn = gtk.Button.new();
        add_btn.setIconName("list-add-symbolic");
        add_btn.setTooltipText("Add Split");
        _ = add_btn.connectClicked(&onAddSplit, self);
        priv.add_split_btn = add_btn;

        // Create list view
        const factory = gtk.SignalListItemFactory.new();
        factory.connectSetup(&setupSplitItem, null);
        factory.connectBind(&bindSplitItem, null);

        const selection = gtk.SingleSelection.new(store.as(gio.ListModel));
        const list_view = gtk.ListView.new(selection.as(gtk.SelectionModel), factory);
        list_view.setSingleClickActivate(true);
        _ = list_view.connectActivate(&onSplitActivated, self);
        priv.splits_list = list_view;

        // Create scrolled window
        const scrolled = gtk.ScrolledWindow.new();
        scrolled.setChild(list_view.as(gtk.Widget));
        scrolled.setVexpand(true);

        // Create header bar
        const header = adw.HeaderBar.new();
        header.setTitleWidget(gtk.Label.new("Split Manager"));
        header.packEnd(add_btn.as(gtk.Widget));

        // Create main page
        const page = adw.PreferencesPage.new();
        page.setIconName("view-split-symbolic");
        page.setTitle("Splits");

        const group = adw.PreferencesGroup.new();
        group.setTitle("Terminal Splits");
        group.setDescription("Manage split terminal panes");
        group.add(scrolled.as(gtk.Widget));

        page.add(group.as(gtk.Widget));
        self.as(adw.PreferencesWindow).add(page.as(gtk.Widget));

        // Load splits
        loadSplits(self);
    }

    fn setupSplitItem(_: *gtk.SignalListItemFactory, item: *gtk.ListItem, _: ?*anyopaque) callconv(.c) void {
        const box = gtk.Box.new(gtk.Orientation.horizontal, 12);
        box.setMarginStart(12);
        box.setMarginEnd(12);
        box.setMarginTop(6);
        box.setMarginBottom(6);

        const icon = gtk.Image.new();
        icon.setIconName("view-split-symbolic");
        icon.setIconSize(gtk.IconSize.large);

        const info_box = gtk.Box.new(gtk.Orientation.vertical, 4);
        info_box.setHexpand(true);
        info_box.setHalign(gtk.Align.start);

        const title_label = gtk.Label.new("");
        title_label.setXalign(0);
        title_label.addCssClass("title-4");

        const cwd_label = gtk.Label.new("");
        cwd_label.setXalign(0);
        cwd_label.addCssClass("dim-label");
        cwd_label.setEllipsize(gtk.EllipsizeMode.start);

        const meta_label = gtk.Label.new("");
        meta_label.setXalign(0);
        meta_label.addCssClass("caption");
        meta_label.addCssClass("dim-label");

        info_box.append(title_label.as(gtk.Widget));
        info_box.append(cwd_label.as(gtk.Widget));
        info_box.append(meta_label.as(gtk.Widget));

        const action_box = gtk.Box.new(gtk.Orientation.horizontal, 4);
        const focus_btn = gtk.Button.new();
        focus_btn.setIconName("go-jump-symbolic");
        focus_btn.setTooltipText("Focus");
        focus_btn.addCssClass("circular");
        focus_btn.addCssClass("flat");

        const close_btn = gtk.Button.new();
        close_btn.setIconName("window-close-symbolic");
        close_btn.setTooltipText("Close");
        close_btn.addCssClass("circular");
        close_btn.addCssClass("flat");
        close_btn.addCssClass("destructive-action");

        action_box.append(focus_btn.as(gtk.Widget));
        action_box.append(close_btn.as(gtk.Widget));

        box.append(icon.as(gtk.Widget));
        box.append(info_box.as(gtk.Widget));
        box.append(action_box.as(gtk.Widget));

        item.setChild(box.as(gtk.Widget));

        // Connect signal handlers once during setup
        _ = focus_btn.connectClicked(&onFocusSplitListItem, item);
        _ = close_btn.connectClicked(&onCloseSplitListItem, item);
    }

    fn bindSplitItem(_: *gtk.SignalListItemFactory, item: *gtk.ListItem, _: ?*anyopaque) callconv(.c) void {
        const entry = item.getItem() orelse return;
        const split_item = @as(*SplitItem, @ptrCast(@alignCast(entry)));
        const box = item.getChild() orelse return;
        const box_widget = box.as(gtk.Box);

        if (box_widget.getFirstChild()) |icon| {
            if (icon.getNextSibling()) |info_box| {
                if (info_box.as(gtk.Box).getFirstChild()) |title| {
                    title.as(gtk.Label).setText(split_item.title);
                    if (title.getNextSibling()) |cwd| {
                        cwd.as(gtk.Label).setText(split_item.cwd);
                        if (cwd.getNextSibling()) |meta| {
                            const orientation_str = switch (split_item.orientation) {
                                .horizontal => "Horizontal",
                                .vertical => "Vertical",
                            };
                            var meta_buf: [128]u8 = undefined;
                            const meta_text = std.fmt.bufPrintZ(&meta_buf, "{s} • Position: {d}", .{ orientation_str, split_item.position }) catch "Split";
                            meta.as(gtk.Label).setText(meta_text);
                        }
                    }
                }
            }
        }
    }

    fn onAddSplit(_: *gtk.Button, self: *Self) callconv(.c) void {
        _ = self;
        // TODO: Show dialog to add new split
        log.info("Add split clicked", .{});
    }

    fn onSplitActivated(_: *gtk.ListView, position: u32, self: *Self) callconv(.c) void {
        const priv = getPriv(self);
        if (priv.splits_store) |store| {
            if (store.getItem(position)) |item| {
                const split_item: *SplitItem = @ptrCast(@alignCast(item));
                // TODO: Focus split
                log.info("Split activated: {s}", .{split_item.id});
            }
        }
    }

    fn onFocusSplitListItem(_: *gtk.Button, list_item: *gtk.ListItem) callconv(.c) void {
        const entry = list_item.getItem() orelse return;
        const split_item = @as(*SplitItem, @ptrCast(@alignCast(entry)));
        // TODO: Focus split
        log.info("Focus split: {s}", .{split_item.id});
    }

    fn onCloseSplitListItem(_: *gtk.Button, list_item: *gtk.ListItem) callconv(.c) void {
        const entry = list_item.getItem() orelse return;
        const split_item = @as(*SplitItem, @ptrCast(@alignCast(entry)));
        // TODO: Close split
        log.info("Close split: {s}", .{split_item.id});
    }

    fn loadSplits(_: *Self) void {
        // TODO: Load splits from terminal state
        log.info("Loading splits...", .{});
    }

    pub fn show(self: *Self, parent: *Window) void {
        self.as(adw.PreferencesWindow).setTransientFor(parent.as(gtk.Window));
        self.as(adw.PreferencesWindow).present();
    }
};
