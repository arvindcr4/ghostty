//! Command History Timeline UI
//! Provides Warp-like visual timeline of command history

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

const log = std.log.scoped(.gtk_ghostty_history_timeline);

pub const HistoryTimelineDialog = extern struct {
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
        timeline_list: ?*gtk.ListView = null,
        timeline_store: ?*gio.ListStore = null,
        filter_entry: ?*gtk.SearchEntry = null,
        date_filter: ?*gtk.DropDown = null,

        pub var offset: c_int = 0;
    };

    pub const TimelineItem = extern struct {
        parent_instance: gobject.Object,
        command: [:0]const u8,
        output: ?[:0]const u8 = null,
        timestamp: i64,
        duration_ms: u64,
        success: bool,

        pub const Parent = gobject.Object;
        pub const getGObjectType = gobject.ext.defineClass(TimelineItem, .{
            .name = "GhosttyTimelineItem",
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

        pub fn new(alloc: Allocator, command: []const u8, timestamp: i64, duration_ms: u64, success: bool) !*TimelineItem {
            const self = gobject.ext.newInstance(TimelineItem, .{});
            self.command = try alloc.dupeZ(u8, command);
            errdefer alloc.free(self.command);
            self.timestamp = timestamp;
            self.duration_ms = duration_ms;
            self.success = success;
            return self;
        }

        pub fn deinit(self: *TimelineItem, alloc: Allocator) void {
            alloc.free(self.command);
            if (self.output) |out| alloc.free(out);
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
        .name = "GhosttyHistoryTimelineDialog",
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

        self.as(adw.Window).setTitle("Command History Timeline");
        self.as(adw.Window).setDefaultSize(800, 600);

        const box = gtk.Box.new(gtk.Orientation.vertical, 12);
        box.setMarginStart(12);
        box.setMarginEnd(12);
        box.setMarginTop(12);
        box.setMarginBottom(12);

        // Filters
        const filter_box = gtk.Box.new(gtk.Orientation.horizontal, 8);
        const filter_entry = gtk.SearchEntry.new();
        filter_entry.setPlaceholderText("Filter commands...");
        filter_entry.setHexpand(@intFromBool(true));
        priv.filter_entry = filter_entry;
        filter_box.append(filter_entry.as(gtk.Widget));

        const date_filter = gtk.DropDown.new(null, null);
        priv.date_filter = date_filter;
        filter_box.append(date_filter.as(gtk.Widget));
        box.append(filter_box.as(gtk.Widget));

        // Timeline list
        const scrolled = gtk.ScrolledWindow.new();
        scrolled.setVexpand(@intFromBool(true));
        scrolled.setPolicy(gtk.PolicyType.never, gtk.PolicyType.automatic);

        const timeline_store = gio.ListStore.new(TimelineItem.getGObjectType());
        priv.timeline_store = timeline_store;

        const selection = gtk.SingleSelection.new(timeline_store.as(gio.ListModel));
        const factory = gtk.SignalListItemFactory.new();
        _ = factory.connectSetup(*anyopaque, &setupTimelineItem, null, .{});
        _ = factory.connectBind(*anyopaque, &bindTimelineItem, null, .{});

        const timeline_list = gtk.ListView.new(selection.as(gtk.SelectionModel), factory.as(gtk.ListItemFactory));
        priv.timeline_list = timeline_list;
        scrolled.setChild(timeline_list.as(gtk.Widget));
        box.append(scrolled.as(gtk.Widget));

        self.as(adw.Window).setContent(box.as(gtk.Widget));
    }

    fn setupTimelineItem(_: *gtk.SignalListItemFactory, item: *gtk.ListItem, _: ?*anyopaque) callconv(.c) void {
        const box = gtk.Box.new(gtk.Orientation.horizontal, 12);
        box.setMarginStart(8);
        box.setMarginEnd(8);
        box.setMarginTop(4);
        box.setMarginBottom(4);

        // Timeline indicator
        const indicator = gtk.Box.new(gtk.Orientation.vertical, 0);
        indicator.setMinContentWidth(4);
        indicator.setHexpand(@intFromBool(false));
        box.append(indicator.as(gtk.Widget));

        // Content
        const content_box = gtk.Box.new(gtk.Orientation.vertical, 4);
        content_box.setHexpand(@intFromBool(true));

        const time_label = gtk.Label.new("");
        time_label.setXalign(0);
        time_label.getStyleContext().addClass("dim-label");
        content_box.append(time_label.as(gtk.Widget));

        const command_label = gtk.Label.new("");
        command_label.setXalign(0);
        command_label.getStyleContext().addClass("monospace");
        content_box.append(command_label.as(gtk.Widget));

        const meta_label = gtk.Label.new("");
        meta_label.setXalign(0);
        meta_label.getStyleContext().addClass("dim-label");
        content_box.append(meta_label.as(gtk.Widget));

        box.append(content_box.as(gtk.Widget));
        item.setChild(box.as(gtk.Widget));
    }

    fn bindTimelineItem(_: *gtk.SignalListItemFactory, item: *gtk.ListItem, _: ?*anyopaque) callconv(.c) void {
        const entry = item.getItem() orelse return;
        const timeline_item = @as(*TimelineItem, @ptrCast(entry));
        const box = item.getChild() orelse return;
        const box_widget = box.as(gtk.Box);

        // Set indicator color based on success
        if (box_widget.getFirstChild()) |indicator| {
            const ctx = indicator.as(gtk.Box).getStyleContext();
            if (timeline_item.success) {
                ctx.addClass("success");
            } else {
                ctx.addClass("error");
            }
            if (indicator.getNextSibling()) |content_box| {
                if (content_box.as(gtk.Box).getFirstChild()) |time| {
                    var time_buf: [64]u8 = undefined;
                    const time_str = formatTimestamp(time_buf[0..], timeline_item.timestamp);
                    time.as(gtk.Label).setText(time_str);
                    if (time.getNextSibling()) |command| {
                        command.as(gtk.Label).setText(timeline_item.command);
                        if (command.getNextSibling()) |meta| {
                            const meta_text = std.fmt.allocPrintZ(Application.default().allocator(), "{d}ms", .{timeline_item.duration_ms}) catch return;
                            defer Application.default().allocator().free(meta_text);
                            meta.as(gtk.Label).setText(meta_text);
                        }
                    }
                }
            }
        }
    }

    fn formatTimestamp(buf: []u8, timestamp: i64) [:0]const u8 {
        // Simple timestamp formatting
        _ = timestamp;
        return std.fmt.bufPrintZ(buf, "Today", .{}) catch "Unknown";
    }

    fn dispose(self: *Self) callconv(.c) void {
        const priv = getPriv(self);
        const alloc = Application.default().allocator();

        // Clean up all timeline items
        if (priv.timeline_store) |store| {
            const n = store.getNItems();
            var i: u32 = 0;
            while (i < n) : (i += 1) {
                if (store.getItem(i)) |item| {
                    const timeline_item: *TimelineItem = @ptrCast(@alignCast(item));
                    timeline_item.deinit(alloc);
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
