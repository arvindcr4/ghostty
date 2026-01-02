//! Command History Search UI
//! Provides Warp-like advanced search through command history

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

const log = std.log.scoped(.gtk_ghostty_command_history_search);

pub const CommandHistorySearchDialog = extern struct {
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
        date_filter: ?*gtk.DropDown = null,
        command_filter: ?*gtk.DropDown = null,
        regex_toggle: ?*gtk.ToggleButton = null,
        case_sensitive_toggle: ?*gtk.ToggleButton = null,
        pub var offset: c_int = 0;
    };

    pub const HistorySearchItem = extern struct {
        parent_instance: gobject.Object,
        command: [:0]const u8,
        timestamp: i64,
        cwd: [:0]const u8,
        exit_code: i32,
        duration_ms: u64,
        output_preview: ?[:0]const u8 = null,

        pub const Parent = gobject.Object;

        pub const ItemClass = extern struct {
            parent_class: gobject.Object.Class,
            var parent: *gobject.Object.Class = undefined;

            fn init(class: *ItemClass) callconv(.c) void {
                gobject.Object.virtual_methods.dispose.implement(class, &HistorySearchItem.dispose);
            }

            fn dispose(self: *HistorySearchItem) callconv(.c) void {
                const alloc = Application.default().allocator();
                alloc.free(self.command);
                alloc.free(self.cwd);
                if (self.output_preview) |preview| alloc.free(preview);
                gobject.Object.virtual_methods.dispose.call(ItemClass.parent, self);
            }
        };

        pub const getGObjectType = gobject.ext.defineClass(HistorySearchItem, .{
            .name = "GhosttyHistorySearchItem",
            .classInit = &ItemClass.init,
            .parent_class = &ItemClass.parent,
        });

        pub fn new(alloc: Allocator, command: []const u8, timestamp: i64, cwd: []const u8, exit_code: i32, duration_ms: u64) !*HistorySearchItem {
            const self = gobject.ext.newInstance(HistorySearchItem, .{});
            self.command = try alloc.dupeZ(u8, command);
            errdefer alloc.free(self.command);
            self.timestamp = timestamp;
            self.cwd = try alloc.dupeZ(u8, cwd);
            errdefer alloc.free(self.cwd);
            self.exit_code = exit_code;
            self.duration_ms = duration_ms;
            return self;
        }

        pub fn deinit(self: *HistorySearchItem, alloc: Allocator) void {
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
        .name = "GhosttyCommandHistorySearchDialog",
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
        self.as(adw.Window).setTitle("Command History Search");
        self.as(adw.Window).setDefaultSize(900, 600);

        // Create history store
        const store = gio.ListStore.new(HistorySearchItem.getGObjectType());
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
        search_entry.setPlaceholderText("Search command history...");
        search_entry.setHexpand(true);
        _ = search_entry.connectSearchChanged(&onSearchChanged, self);
        priv.search_entry = search_entry;

        const date_store = gio.ListStore.new(gobject.Object.getGObjectType());
        const date_filter = gtk.DropDown.new(date_store.as(gio.ListModel), null);
        date_filter.setTooltipText("Filter by date");
        _ = date_filter.connectNotify("selected", &onDateFilterChanged, self);
        priv.date_filter = date_filter;

        const command_store = gio.ListStore.new(gobject.Object.getGObjectType());
        const command_filter = gtk.DropDown.new(command_store.as(gio.ListModel), null);
        command_filter.setTooltipText("Filter by command type");
        _ = command_filter.connectNotify("selected", &onCommandFilterChanged, self);
        priv.command_filter = command_filter;

        const regex_toggle = gtk.ToggleButton.new();
        regex_toggle.setLabel("Regex");
        regex_toggle.setTooltipText("Enable regex search");
        _ = regex_toggle.connectToggled(&onRegexToggled, self);
        priv.regex_toggle = regex_toggle;

        const case_sensitive_toggle = gtk.ToggleButton.new();
        case_sensitive_toggle.setLabel("Case Sensitive");
        case_sensitive_toggle.setTooltipText("Case sensitive search");
        _ = case_sensitive_toggle.connectToggled(&onCaseSensitiveToggled, self);
        priv.case_sensitive_toggle = case_sensitive_toggle;

        toolbar.append(search_entry.as(gtk.Widget));
        toolbar.append(date_filter.as(gtk.Widget));
        toolbar.append(command_filter.as(gtk.Widget));
        toolbar.append(regex_toggle.as(gtk.Widget));
        toolbar.append(case_sensitive_toggle.as(gtk.Widget));

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

        info_box.append(command_label.as(gtk.Widget));
        info_box.append(meta_label.as(gtk.Widget));

        const action_box = gtk.Box.new(gtk.Orientation.horizontal, 4);
        const replay_btn = gtk.Button.new();
        replay_btn.setIconName("media-playback-start-symbolic");
        replay_btn.setTooltipText("Replay Command");
        replay_btn.addCssClass("circular");
        replay_btn.addCssClass("flat");

        action_box.append(replay_btn.as(gtk.Widget));

        box.append(status_indicator.as(gtk.Widget));
        box.append(info_box.as(gtk.Widget));
        box.append(action_box.as(gtk.Widget));

        item.setChild(box.as(gtk.Widget));

        // Connect signal handler once during setup
        _ = replay_btn.connectClicked(&onReplayHistoryListItem, item);
    }

    fn bindHistoryItem(_: *gtk.SignalListItemFactory, item: *gtk.ListItem, _: ?*anyopaque) callconv(.c) void {
        const entry = item.getItem() orelse return;
        const history_item = @as(*HistorySearchItem, @ptrCast(@alignCast(entry)));
        const box = item.getChild() orelse return;
        const box_widget = box.as(gtk.Box);

        if (box_widget.getFirstChild()) |indicator| {
            const success = history_item.exit_code == 0;
            indicator.as(gtk.Box).addCssClass(if (success) "success-indicator" else "error-indicator");
            indicator.as(gtk.Box).removeCssClass(if (success) "error-indicator" else "success-indicator");

            if (indicator.getNextSibling()) |info_box| {
                if (info_box.as(gtk.Box).getFirstChild()) |command| {
                    command.as(gtk.Label).setText(history_item.command);
                    if (command.getNextSibling()) |meta| {
                        var meta_buf: [256]u8 = undefined;
                        const meta_text = std.fmt.bufPrintZ(&meta_buf, "{s} • {s} • {d}ms", .{ history_item.cwd, formatTimestamp(history_item.timestamp), history_item.duration_ms }) catch "History item";
                        meta.as(gtk.Label).setText(meta_text);
                    }
                }
            }
        }
    }

    fn formatTimestamp(timestamp: i64) [:0]const u8 {
        const now = std.time.timestamp();
        const diff = now - timestamp;
        var buf: [64]u8 = undefined;
        if (diff < 3600) {
            const minutes = diff / 60;
            return std.fmt.bufPrintZ(&buf, "{d}m ago", .{minutes}) catch "Recently";
        } else if (diff < 86400) {
            const hours = diff / 3600;
            return std.fmt.bufPrintZ(&buf, "{d}h ago", .{hours}) catch "Today";
        } else {
            const days = diff / 86400;
            return std.fmt.bufPrintZ(&buf, "{d}d ago", .{days}) catch "Earlier";
        }
    }

    fn onSearchChanged(entry: *gtk.SearchEntry, self: *Self) callconv(.c) void {
        _ = entry;
        _ = self;
        // TODO: Implement search filtering
    }

    fn onDateFilterChanged(_: *gobject.Object, _: glib.ParamSpec, self: *Self) callconv(.c) void {
        _ = self;
        // TODO: Implement date filtering
    }

    fn onCommandFilterChanged(_: *gobject.Object, _: glib.ParamSpec, self: *Self) callconv(.c) void {
        _ = self;
        // TODO: Implement command type filtering
    }

    fn onRegexToggled(_: *gtk.ToggleButton, self: *Self) callconv(.c) void {
        _ = self;
        // TODO: Update search mode
    }

    fn onCaseSensitiveToggled(_: *gtk.ToggleButton, self: *Self) callconv(.c) void {
        _ = self;
        // TODO: Update search mode
    }

    fn onHistoryActivated(_: *gtk.ListView, position: u32, self: *Self) callconv(.c) void {
        const priv = getPriv(self);
        if (priv.history_store) |store| {
            if (store.getItem(position)) |item| {
                const history_item: *HistorySearchItem = @ptrCast(@alignCast(item));
                // TODO: Show history details
                log.info("History activated: {s}", .{history_item.command});
            }
        }
    }

    fn onReplayHistoryListItem(_: *gtk.Button, list_item: *gtk.ListItem) callconv(.c) void {
        const entry = list_item.getItem() orelse return;
        const history_item = @as(*HistorySearchItem, @ptrCast(@alignCast(entry)));
        // TODO: Replay command
        log.info("Replay command: {s}", .{history_item.command});
    }

    fn loadHistory(_: *Self) void {
        // TODO: Load command history
        log.info("Loading command history...", .{});
    }

    pub fn show(self: *Self, parent: *Window) void {
        self.as(adw.Window).setTransientFor(parent.as(gtk.Window));
        self.as(adw.Window).present();
    }
};
