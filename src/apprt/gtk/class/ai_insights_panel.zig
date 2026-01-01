//! AI Insights Panel
//! Provides Warp-like sidebar with AI-generated insights and suggestions

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

const log = std.log.scoped(.gtk_ghostty_insights_panel);

pub const InsightsPanel = extern struct {
    const C = Common(Self, Private);
    pub const as = C.as;
    pub const ref = C.ref;
    pub const unref = C.unref;
    pub const refSink = C.refSink;
    const getPriv = C.getPriv;
    const Self = @This();

    parent_instance: Parent,
    pub const Parent = adw.NavigationView;

    const Private = struct {
        insights_list: ?*gtk.ListView = null,
        insights_store: ?*gio.ListStore = null,
        refresh_btn: ?*gtk.Button = null,

        pub var offset: c_int = 0;
    };

    pub const InsightItem = extern struct {
        parent_instance: gobject.Object,
        title: [:0]const u8,
        description: [:0]const u8,
        category: InsightCategory,
        priority: InsightPriority,

        pub const Parent = gobject.Object;
        pub const InsightCategory = enum {
            performance,
            security,
            optimization,
            suggestion,
            warning,
        };

        pub const InsightPriority = enum {
            low,
            medium,
            high,
        };

        pub const getGObjectType = gobject.ext.defineClass(InsightItem, .{
            .name = "GhosttyInsightItem",
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

        pub fn new(alloc: Allocator, title: []const u8, description: []const u8, category: InsightCategory, priority: InsightPriority) !*InsightItem {
            const self = gobject.ext.newInstance(InsightItem, .{});
            self.title = try alloc.dupeZ(u8, title);
            errdefer alloc.free(self.title);
            self.description = try alloc.dupeZ(u8, description);
            errdefer alloc.free(self.description);
            self.category = category;
            self.priority = priority;
            return self;
        }

        pub fn deinit(self: *InsightItem, alloc: Allocator) void {
            alloc.free(self.title);
            alloc.free(self.description);
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
        .name = "GhosttyInsightsPanel",
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

        const page = adw.NavigationPage.new();
        page.setTitle("AI Insights");

        const box = gtk.Box.new(gtk.Orientation.vertical, 12);
        box.setMarginStart(12);
        box.setMarginEnd(12);
        box.setMarginTop(12);
        box.setMarginBottom(12);

        // Header with refresh button
        const header = gtk.Box.new(gtk.Orientation.horizontal, 8);
        const refresh_btn = gtk.Button.new();
        refresh_btn.setLabel("Refresh");
        refresh_btn.setIconName("view-refresh-symbolic");
        refresh_btn.setHalign(gtk.Align.end);
        priv.refresh_btn = refresh_btn;
        _ = refresh_btn.connectClicked(&refreshInsights, self);
        header.append(refresh_btn.as(gtk.Widget));
        box.append(header.as(gtk.Widget));

        // Insights list
        const scrolled = gtk.ScrolledWindow.new();
        scrolled.setVexpand(@intFromBool(true));
        scrolled.setPolicy(gtk.PolicyType.never, gtk.PolicyType.automatic);

        const insights_store = gio.ListStore.new(InsightItem.getGObjectType());
        priv.insights_store = insights_store;

        const selection = gtk.NoSelection.new(insights_store.as(gio.ListModel));
        const factory = gtk.SignalListItemFactory.new();
        _ = factory.connectSetup(*anyopaque, &setupInsightItem, null, .{});
        _ = factory.connectBind(*anyopaque, &bindInsightItem, null, .{});

        const insights_list = gtk.ListView.new(selection.as(gtk.SelectionModel), factory.as(gtk.ListItemFactory));
        priv.insights_list = insights_list;
        scrolled.setChild(insights_list.as(gtk.Widget));
        box.append(scrolled.as(gtk.Widget));

        page.setChild(box.as(gtk.Widget));
        self.as(adw.NavigationView).push(page.as(adw.NavigationPage));
    }

    fn setupInsightItem(_: *gtk.SignalListItemFactory, item: *gtk.ListItem, _: ?*anyopaque) callconv(.c) void {
        const box = gtk.Box.new(gtk.Orientation.vertical, 4);
        box.setMarginStart(8);
        box.setMarginEnd(8);
        box.setMarginTop(4);
        box.setMarginBottom(4);

        const header_box = gtk.Box.new(gtk.Orientation.horizontal, 8);
        const title_label = gtk.Label.new("");
        title_label.setXalign(0);
        title_label.getStyleContext().addClass("heading");
        title_label.setHexpand(@intFromBool(true));
        header_box.append(title_label.as(gtk.Widget));

        const priority_label = gtk.Label.new("");
        priority_label.setHalign(gtk.Align.end);
        header_box.append(priority_label.as(gtk.Widget));
        box.append(header_box.as(gtk.Widget));

        const desc_label = gtk.Label.new("");
        desc_label.setXalign(0);
        desc_label.setWrap(@intFromBool(true));
        box.append(desc_label.as(gtk.Widget));

        item.setChild(box.as(gtk.Widget));
    }

    fn bindInsightItem(_: *gtk.SignalListItemFactory, item: *gtk.ListItem, _: ?*anyopaque) callconv(.c) void {
        const entry = item.getItem() orelse return;
        const insight_item = @as(*InsightItem, @ptrCast(entry));
        const box = item.getChild() orelse return;
        const box_widget = box.as(gtk.Box);

        if (box_widget.getFirstChild()) |header_box| {
            if (header_box.as(gtk.Box).getFirstChild()) |title| {
                title.as(gtk.Label).setText(insight_item.title);
                if (title.getNextSibling()) |priority| {
                    const priority_text = switch (insight_item.priority) {
                        .low => "Low",
                        .medium => "Medium",
                        .high => "High",
                    };
                    priority.as(gtk.Label).setText(priority_text);
                }
            }
            if (header_box.getNextSibling()) |desc| {
                desc.as(gtk.Label).setText(insight_item.description);
            }
        }
    }

    fn refreshInsights(button: *gtk.Button, self: *Self) callconv(.c) void {
        _ = button;
        _ = self;
        // TODO: Implement actual insight refresh
        log.info("Refreshing AI insights...", .{});
    }

    fn dispose(self: *Self) callconv(.c) void {
        const priv = getPriv(self);
        const alloc = Application.default().allocator();

        // Clean up all insight items
        if (priv.insights_store) |store| {
            const n = store.getNItems();
            var i: u32 = 0;
            while (i < n) : (i += 1) {
                if (store.getItem(i)) |item| {
                    const insight_item: *InsightItem = @ptrCast(@alignCast(item));
                    insight_item.deinit(alloc);
                }
            }
        }

        gobject.Object.virtual_methods.dispose.call(Class.parent, self.as(Parent));
    }

    pub fn addInsight(self: *Self, title: []const u8, description: []const u8, category: InsightItem.InsightCategory, priority: InsightItem.InsightPriority) void {
        const priv = getPriv(self);
        const alloc = Application.default().allocator();

        const insight = InsightItem.new(alloc, title, description, category, priority) catch {
            log.err("Failed to create insight item", .{});
            return;
        };

        if (priv.insights_store) |store| {
            store.append(insight.as(gobject.Object));
        }
    }

    pub fn show(self: *Self, _: *Window) void {
        self.as(gtk.Widget).setVisible(@intFromBool(true));
    }
};
