//! AI-powered Natural Language Search
//! Provides Warp-like natural language search through command history

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

const log = std.log.scoped(.gtk_ghostty_natural_search);

pub const NaturalSearchDialog = extern struct {
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
        search_entry: ?*gtk.SearchEntry = null,
        results_list: ?*gtk.ListView = null,
        results_store: ?*gio.ListStore = null,
        search_btn: ?*gtk.Button = null,

        pub var offset: c_int = 0;
    };

    pub const SearchResultItem = extern struct {
        parent_instance: gobject.Object,
        command: [:0]const u8,
        context: [:0]const u8,
        relevance_score: f32,
        timestamp: i64,

        pub const Parent = gobject.Object;
        pub const getGObjectType = gobject.ext.defineClass(SearchResultItem, .{
            .name = "GhosttySearchResultItem",
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

        pub fn new(alloc: Allocator, command: []const u8, context: []const u8, relevance_score: f32, timestamp: i64) !*SearchResultItem {
            const self = gobject.ext.newInstance(SearchResultItem, .{});
            self.command = try alloc.dupeZ(u8, command);
            errdefer alloc.free(self.command);
            self.context = try alloc.dupeZ(u8, context);
            errdefer alloc.free(self.context);
            self.relevance_score = relevance_score;
            self.timestamp = timestamp;
            return self;
        }

        pub fn deinit(self: *SearchResultItem, alloc: Allocator) void {
            alloc.free(self.command);
            alloc.free(self.context);
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
        .name = "GhosttyNaturalSearchDialog",
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

        self.as(adw.Window).setTitle("Natural Language Search");
        self.as(adw.Window).setDefaultSize(700, 500);

        const box = gtk.Box.new(gtk.Orientation.vertical, 12);
        box.setMarginStart(12);
        box.setMarginEnd(12);
        box.setMarginTop(12);
        box.setMarginBottom(12);

        // Search bar
        const search_box = gtk.Box.new(gtk.Orientation.horizontal, 8);
        const search_entry = gtk.SearchEntry.new();
        search_entry.setPlaceholderText("Search commands using natural language...");
        search_entry.setHexpand(@intFromBool(true));
        priv.search_entry = search_entry;
        search_box.append(search_entry.as(gtk.Widget));

        const search_btn = gtk.Button.new();
        search_btn.setLabel("Search");
        search_btn.setIconName("system-search-symbolic");
        priv.search_btn = search_btn;
        _ = search_btn.connectClicked(&performSearch, self);
        search_box.append(search_btn.as(gtk.Widget));
        box.append(search_box.as(gtk.Widget));

        // Results list
        const scrolled = gtk.ScrolledWindow.new();
        scrolled.setVexpand(@intFromBool(true));
        scrolled.setPolicy(gtk.PolicyType.never, gtk.PolicyType.automatic);

        const results_store = gio.ListStore.new(SearchResultItem.getGObjectType());
        priv.results_store = results_store;

        const selection = gtk.SingleSelection.new(results_store.as(gio.ListModel));
        const factory = gtk.SignalListItemFactory.new();
        _ = factory.connectSetup(*anyopaque, &setupResultItem, null, .{});
        _ = factory.connectBind(*anyopaque, &bindResultItem, null, .{});

        const results_list = gtk.ListView.new(selection.as(gtk.SelectionModel), factory.as(gtk.ListItemFactory));
        priv.results_list = results_list;
        scrolled.setChild(results_list.as(gtk.Widget));
        box.append(scrolled.as(gtk.Widget));

        self.as(adw.Window).setContent(box.as(gtk.Widget));

        // Connect Enter key
        _ = search_entry.connectActivate(&performSearch, self);
    }

    fn setupResultItem(_: *gtk.SignalListItemFactory, item: *gtk.ListItem, _: ?*anyopaque) callconv(.c) void {
        const box = gtk.Box.new(gtk.Orientation.vertical, 4);
        box.setMarginStart(8);
        box.setMarginEnd(8);
        box.setMarginTop(4);
        box.setMarginBottom(4);

        const command_label = gtk.Label.new("");
        command_label.setXalign(0);
        command_label.getStyleContext().addClass("monospace");
        command_label.getStyleContext().addClass("heading");
        box.append(command_label.as(gtk.Widget));

        const context_label = gtk.Label.new("");
        context_label.setXalign(0);
        context_label.setWrap(@intFromBool(true));
        context_label.getStyleContext().addClass("dim-label");
        box.append(context_label.as(gtk.Widget));

        const score_label = gtk.Label.new("");
        score_label.setXalign(0);
        score_label.getStyleContext().addClass("dim-label");
        box.append(score_label.as(gtk.Widget));

        item.setChild(box.as(gtk.Widget));
    }

    fn bindResultItem(_: *gtk.SignalListItemFactory, item: *gtk.ListItem, _: ?*anyopaque) callconv(.c) void {
        const entry = item.getItem() orelse return;
        const result_item = @as(*SearchResultItem, @ptrCast(entry));
        const box = item.getChild() orelse return;
        const box_widget = box.as(gtk.Box);

        if (box_widget.getFirstChild()) |command| {
            command.as(gtk.Label).setText(result_item.command);
            if (command.getNextSibling()) |context| {
                context.as(gtk.Label).setText(result_item.context);
                if (context.getNextSibling()) |score| {
                    const score_text = std.fmt.allocPrintZ(Application.default().allocator(), "Relevance: {d:.1}%", .{result_item.relevance_score * 100.0}) catch return;
                    defer Application.default().allocator().free(score_text);
                    score.as(gtk.Label).setText(score_text);
                }
            }
        }
    }

    fn performSearch(button_or_entry: *gtk.Widget, self: *Self) callconv(.c) void {
        _ = button_or_entry;
        const priv = getPriv(self);
        const alloc = Application.default().allocator();

        if (priv.search_entry) |entry| {
            const query = entry.getText() orelse return;
            if (query.len == 0) return;

            // Clear existing results
            if (priv.results_store) |store| {
                const n = store.getNItems();
                var i: u32 = 0;
                while (i < n) : (i += 1) {
                    if (store.getItem(i)) |item| {
                        const result_item: *SearchResultItem = @ptrCast(@alignCast(item));
                        result_item.deinit(alloc);
                    }
                }
                store.removeAll();
            }

            // TODO: Implement actual AI-powered search
            log.info("Performing natural language search: {s}", .{query});

            // Example results
            if (priv.results_store) |store| {
                const result1 = SearchResultItem.new(alloc, "git status", "Check git repository status", 0.95, std.time.timestamp()) catch return;
                store.append(result1.as(gobject.Object));

                const result2 = SearchResultItem.new(alloc, "ls -la", "List all files with details", 0.85, std.time.timestamp()) catch return;
                store.append(result2.as(gobject.Object));
            }
        }
    }

    fn dispose(self: *Self) callconv(.c) void {
        const priv = getPriv(self);
        const alloc = Application.default().allocator();

        // Clean up all result items
        if (priv.results_store) |store| {
            const n = store.getNItems();
            var i: u32 = 0;
            while (i < n) : (i += 1) {
                if (store.getItem(i)) |item| {
                    const result_item: *SearchResultItem = @ptrCast(@alignCast(item));
                    result_item.deinit(alloc);
                }
            }
        }

        gobject.Object.virtual_methods.dispose.call(Class.parent, self.as(Parent));
    }

    pub fn show(self: *Self, parent: *Window) void {
        self.as(adw.Window).setTransientFor(parent.as(gtk.Window));
        self.as(adw.Window).present();
    }
};
