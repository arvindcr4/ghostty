//! Command Execution History UI
//! Provides Warp-like command execution history with replay functionality

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

const log = std.log.scoped(.gtk_ghostty_execution_history);

pub const ExecutionHistoryDialog = extern struct {
    const C = Common(Self, Private);
    pub const as = C.as;
    pub const ref = C.ref;
    pub const unref = C.unref;
    pub const refSink = C.refSink;
    const getPriv = C.getPriv;
    const Self = @This();

    parent_instance: Parent,
    pub const Parent = adw.Window;

    const Private = struct {
        history_list: ?*gtk.ListView = null,
        history_store: ?*gio.ListStore = null,
        search_entry: ?*gtk.SearchEntry = null,
        filter_dropdown: ?*gtk.DropDown = null,
        replay_btn: ?*gtk.Button = null,
        pub var offset: c_int = 0;
    };

    pub const HistoryItem = extern struct {
        parent_instance: gobject.Object,
        command: [:0]const u8,
        timestamp: i64,
        duration_ms: u64,
        exit_code: i32,
        cwd: [:0]const u8,
        output_preview: ?[:0]const u8 = null,

        pub const Parent = gobject.Object;

        pub const ItemClass = extern struct {
            parent_class: gobject.Object.Class,
            var parent: *gobject.Object.Class = undefined;

            fn init(class: *ItemClass) callconv(.c) void {
                gobject.Object.virtual_methods.dispose.implement(class, &HistoryItem.dispose);
            }

            fn dispose(self: *HistoryItem) callconv(.c) void {
                const alloc = Application.default().allocator();
                alloc.free(self.command);
                alloc.free(self.cwd);
                if (self.output_preview) |preview| alloc.free(preview);
                gobject.Object.virtual_methods.dispose.call(ItemClass.parent, self);
            }
        };

        pub const getGObjectType = gobject.ext.defineClass(HistoryItem, .{
            .name = "GhosttyHistoryItem",
            .classInit = &ItemClass.init,
            .parent_class = &ItemClass.parent,
        });

        pub fn new(alloc: Allocator, command: []const u8, timestamp: i64, duration_ms: u64, exit_code: i32, cwd: []const u8) !*HistoryItem {
            const self = gobject.ext.newInstance(HistoryItem, .{});
            self.command = try alloc.dupeZ(u8, command);
            errdefer alloc.free(self.command);
            self.timestamp = timestamp;
            self.duration_ms = duration_ms;
            self.exit_code = exit_code;
            self.cwd = try alloc.dupeZ(u8, cwd);
            errdefer alloc.free(self.cwd);
            return self;
        }

        pub fn deinit(self: *HistoryItem, alloc: Allocator) void {
            alloc.free(self.command);
            alloc.free(self.cwd);
            if (self.output_preview) |preview| alloc.free(preview);
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
            if (priv.history_store) |store| {
                store.removeAll();
            }
            gobject.Object.virtual_methods.dispose.call(Class.parent, self.as(Parent));
        }

        pub const as = C.Class.as;
    };

    pub const getGObjectType = gobject.ext.defineClass(Self, .{
        .name = "GhosttyExecutionHistoryDialog",
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
        self.as(adw.Window).setTitle("Execution History");
        self.as(adw.Window).setDefaultSize(900, 600);

        // Create history store
        const store = gio.ListStore.new(HistoryItem.getGObjectType());
        priv.history_store = store;

        // Create main box
        const main_box = gtk.Box.new(gtk.Orientation.vertical, 12);
        main_box.setMarginStart(12);
        main_box.setMarginEnd(12);
        main_box.setMarginTop(12);
        main_box.setMarginBottom(12);

        // Create toolbar
        const toolbar = gtk.Box.new(gtk.Orientation.horizontal, 12);

        const search_entry = gtk.SearchEntry.new();
        search_entry.setPlaceholderText("Search commands...");
        search_entry.setHexpand(true);
        _ = search_entry.connectSearchChanged(&onSearchChanged, self);
        priv.search_entry = search_entry;

        const filter_store = gio.ListStore.new(gobject.Object.getGObjectType());
        const filter_dropdown = gtk.DropDown.new(filter_store.as(gio.ListModel), null);
        filter_dropdown.setTooltipText("Filter by status");
        _ = filter_dropdown.connectNotify("selected", &onFilterChanged, self);
        priv.filter_dropdown = filter_dropdown;

        const replay_btn = gtk.Button.new();
        replay_btn.setIconName("media-playback-start-symbolic");
        replay_btn.setLabel("Replay");
        replay_btn.setTooltipText("Replay Selected Command");
        replay_btn.addCssClass("suggested-action");
        _ = replay_btn.connectClicked(&onReplayClicked, self);
        priv.replay_btn = replay_btn;

        toolbar.append(search_entry.as(gtk.Widget));
        toolbar.append(filter_dropdown.as(gtk.Widget));
        toolbar.append(replay_btn.as(gtk.Widget));

        // Create list view
        const factory = gtk.SignalListItemFactory.new();
        factory.connectSetup(&setupHistoryItem, null);
        factory.connectBind(&bindHistoryItem, null);

        const selection = gtk.SingleSelection.new(store.as(gio.ListModel));
        const list_view = gtk.ListView.new(selection.as(gtk.SelectionModel), factory);
        list_view.setSingleClickActivate(true);
        _ = list_view.connectActivate(&onHistoryActivated, self);
        priv.history_list = list_view;

        // Create scrolled window
        const scrolled = gtk.ScrolledWindow.new();
        scrolled.setChild(list_view.as(gtk.Widget));
        scrolled.setVexpand(true);

        main_box.append(toolbar.as(gtk.Widget));
        main_box.append(scrolled.as(gtk.Widget));

        self.as(adw.Window).setContent(main_box.as(gtk.Widget));

        // Load history
        loadHistory(self);
    }

    fn setupHistoryItem(_: *gtk.SignalListItemFactory, item: *gtk.ListItem, _: ?*anyopaque) callconv(.c) void {
        const box = gtk.Box.new(gtk.Orientation.horizontal, 12);
        box.setMarginStart(12);
        box.setMarginEnd(12);
        box.setMarginTop(6);
        box.setMarginBottom(6);

        const status_indicator = gtk.Box.new(gtk.Orientation.vertical, 0);
        status_indicator.setMinContentWidth(4);
        status_indicator.addCssClass("status-indicator");

        const info_box = gtk.Box.new(gtk.Orientation.vertical, 4);
        info_box.setHexpand(true);
        info_box.setHalign(gtk.Align.start);

        const command_label = gtk.Label.new("");
        command_label.setXalign(0);
        command_label.addCssClass("monospace");
        command_label.addCssClass("title-5");
        command_label.setSelectable(true);

        const meta_label = gtk.Label.new("");
        meta_label.setXalign(0);
        meta_label.addCssClass("caption");
        meta_label.addCssClass("dim-label");

        const cwd_label = gtk.Label.new("");
        cwd_label.setXalign(0);
        cwd_label.addCssClass("caption");
        cwd_label.addCssClass("dim-label");
        cwd_label.setEllipsize(gtk.EllipsizeMode.start);

        info_box.append(command_label.as(gtk.Widget));
        info_box.append(meta_label.as(gtk.Widget));
        info_box.append(cwd_label.as(gtk.Widget));

        box.append(status_indicator.as(gtk.Widget));
        box.append(info_box.as(gtk.Widget));

        item.setChild(box.as(gtk.Widget));
    }

    fn bindHistoryItem(_: *gtk.SignalListItemFactory, item: *gtk.ListItem, _: ?*anyopaque) callconv(.c) void {
        const entry = item.getItem() orelse return;
        const history_item = @as(*HistoryItem, @ptrCast(@alignCast(entry)));
        const box = item.getChild() orelse return;
        const box_widget = box.as(gtk.Box);

        if (box_widget.getFirstChild()) |indicator| {
            // Set indicator color based on exit code
            const success = history_item.exit_code == 0;
            indicator.as(gtk.Box).addCssClass(if (success) "success-indicator" else "error-indicator");
            indicator.as(gtk.Box).removeCssClass(if (success) "error-indicator" else "success-indicator");

            if (indicator.getNextSibling()) |info_box| {
                if (info_box.as(gtk.Box).getFirstChild()) |command| {
                    command.as(gtk.Label).setText(history_item.command);
                    if (command.getNextSibling()) |meta| {
                        var meta_buf: [256]u8 = undefined;
                        const duration_str = if (history_item.duration_ms < 1000)
                            std.fmt.bufPrintZ(&meta_buf, "Exit: {d} • {d}ms", .{ history_item.exit_code, history_item.duration_ms }) catch "Command"
                        else
                            std.fmt.bufPrintZ(&meta_buf, "Exit: {d} • {d:.2}s", .{ history_item.exit_code, @as(f64, @floatFromInt(history_item.duration_ms)) / 1000.0 }) catch "Command";
                        meta.as(gtk.Label).setText(duration_str);
                        if (meta.getNextSibling()) |cwd| {
                            cwd.as(gtk.Label).setText(history_item.cwd);
                        }
                    }
                }
            }
        }
    }

    fn onSearchChanged(entry: *gtk.SearchEntry, self: *Self) callconv(.c) void {
        _ = entry;
        _ = self;
        // TODO: Implement search filtering
    }

    fn onFilterChanged(_: *gobject.Object, _: glib.ParamSpec, self: *Self) callconv(.c) void {
        _ = self;
        // TODO: Implement filter
    }

    fn onReplayClicked(_: *gtk.Button, self: *Self) callconv(.c) void {
        const priv = getPriv(self);
        if (priv.history_list) |list_view| {
            if (list_view.getModel()) |model| {
                if (model.as(gtk.SingleSelection).getSelected()) |position| {
                    if (priv.history_store) |store| {
                        if (store.getItem(position)) |item| {
                            const history_item: *HistoryItem = @ptrCast(@alignCast(item));
                            // TODO: Replay command
                            log.info("Replay command: {s}", .{history_item.command});
                        }
                    }
                }
            }
        }
    }

    fn onHistoryActivated(_: *gtk.ListView, position: u32, self: *Self) callconv(.c) void {
        const priv = getPriv(self);
        if (priv.history_store) |store| {
            if (store.getItem(position)) |item| {
                const history_item: *HistoryItem = @ptrCast(@alignCast(item));
                // TODO: Show command details/output
                log.info("History activated: {s}", .{history_item.command});
            }
        }
    }

    fn loadHistory(_: *Self) void {
        // TODO: Load execution history from terminal
        log.info("Loading execution history...", .{});
    }

    pub fn show(self: *Self, parent: *Window) void {
        self.as(adw.Window).setTransientFor(parent.as(gtk.Window));
        self.as(adw.Window).present();
    }
};
