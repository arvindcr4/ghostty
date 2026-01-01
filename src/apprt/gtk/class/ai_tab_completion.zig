//! AI-powered Tab Completion Overlay
//! Provides Warp-like intelligent tab completion suggestions

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

const log = std.log.scoped(.gtk_ghostty_tab_completion);

pub const TabCompletionOverlay = extern struct {
    const C = Common(Self, Private);
    pub const as = C.as;
    pub const ref = C.ref;
    pub const unref = C.unref;
    pub const refSink = C.refSink;
    const getPriv = C.getPriv;
    const Self = @This();

    parent_instance: Parent,
    pub const Parent = gtk.Popover;

    const Private = struct {
        completions_list: ?*gtk.ListView = null,
        completions_store: ?*gio.ListStore = null,
        current_query: ?[]const u8 = null,
        selected_index: u32 = 0,

        pub var offset: c_int = 0;
    };

    pub const CompletionItem = extern struct {
        parent_instance: gobject.Object,
        text: [:0]const u8,
        description: [:0]const u8,
        icon_name: ?[:0]const u8 = null,
        confidence: f32 = 0.0,

        pub const Parent = gobject.Object;
        pub const getGObjectType = gobject.ext.defineClass(CompletionItem, .{
            .name = "GhosttyCompletionItem",
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

        pub fn new(alloc: Allocator, text: []const u8, description: []const u8, icon_name: ?[]const u8, confidence: f32) !*CompletionItem {
            const self = gobject.ext.newInstance(CompletionItem, .{});
            self.text = try alloc.dupeZ(u8, text);
            errdefer alloc.free(self.text);
            self.description = try alloc.dupeZ(u8, description);
            errdefer alloc.free(self.description);
            if (icon_name) |icon| {
                self.icon_name = try alloc.dupeZ(u8, icon);
                errdefer alloc.free(self.icon_name);
            }
            self.confidence = confidence;
            return self;
        }

        pub fn deinit(self: *CompletionItem, alloc: Allocator) void {
            alloc.free(self.text);
            alloc.free(self.description);
            if (self.icon_name) |icon| alloc.free(icon);
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
        .name = "GhosttyTabCompletionOverlay",
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

        self.as(gtk.Popover).setHasArrow(@intFromBool(true));
        self.as(gtk.Popover).setAutohide(@intFromBool(true));

        const box = gtk.Box.new(gtk.Orientation.vertical, 0);
        box.setMarginStart(4);
        box.setMarginEnd(4);
        box.setMarginTop(4);
        box.setMarginBottom(4);

        const scrolled = gtk.ScrolledWindow.new();
        scrolled.setMaxContentHeight(300);
        scrolled.setPolicy(gtk.PolicyType.never, gtk.PolicyType.automatic);

        const completions_store = gio.ListStore.new(CompletionItem.getGObjectType());
        priv.completions_store = completions_store;

        const selection = gtk.SingleSelection.new(completions_store.as(gio.ListModel));
        const factory = gtk.SignalListItemFactory.new();
        _ = factory.connectSetup(*anyopaque, &setupCompletionItem, null, .{});
        _ = factory.connectBind(*anyopaque, &bindCompletionItem, null, .{});

        const completions_list = gtk.ListView.new(selection.as(gtk.SelectionModel), factory.as(gtk.ListItemFactory));
        priv.completions_list = completions_list;
        scrolled.setChild(completions_list.as(gtk.Widget));
        box.append(scrolled.as(gtk.Widget));

        self.as(gtk.Popover).setChild(box.as(gtk.Widget));
    }

    fn setupCompletionItem(_: *gtk.SignalListItemFactory, item: *gtk.ListItem, _: ?*anyopaque) callconv(.c) void {
        const box = gtk.Box.new(gtk.Orientation.horizontal, 8);
        box.setMarginStart(8);
        box.setMarginEnd(8);
        box.setMarginTop(4);
        box.setMarginBottom(4);

        const icon = gtk.Image.new();
        box.append(icon.as(gtk.Widget));

        const info_box = gtk.Box.new(gtk.Orientation.vertical, 2);
        info_box.setHexpand(@intFromBool(true));

        const text_label = gtk.Label.new("");
        text_label.setXalign(0);
        text_label.getStyleContext().addClass("monospace");
        info_box.append(text_label.as(gtk.Widget));

        const desc_label = gtk.Label.new("");
        desc_label.setXalign(0);
        desc_label.getStyleContext().addClass("dim-label");
        info_box.append(desc_label.as(gtk.Widget));

        box.append(info_box.as(gtk.Widget));
        item.setChild(box.as(gtk.Widget));
    }

    fn bindCompletionItem(_: *gtk.SignalListItemFactory, item: *gtk.ListItem, _: ?*anyopaque) callconv(.c) void {
        const entry = item.getItem() orelse return;
        const completion_item = @as(*CompletionItem, @ptrCast(entry));
        const box = item.getChild() orelse return;
        const box_widget = box.as(gtk.Box);

        if (box_widget.getFirstChild()) |icon_widget| {
            if (completion_item.icon_name) |icon_name| {
                icon_widget.as(gtk.Image).setFromIconName(icon_name);
            }
            if (icon_widget.getNextSibling()) |info_box| {
                if (info_box.as(gtk.Box).getFirstChild()) |text| {
                    text.as(gtk.Label).setText(completion_item.text);
                    if (text.getNextSibling()) |desc| {
                        desc.as(gtk.Label).setText(completion_item.description);
                    }
                }
            }
        }
    }

    fn dispose(self: *Self) callconv(.c) void {
        const priv = getPriv(self);
        const alloc = Application.default().allocator();

        // Clean up query string
        if (priv.current_query) |query| {
            alloc.free(query);
            priv.current_query = null;
        }

        // Clean up all completion items
        if (priv.completions_store) |store| {
            const n = store.getNItems();
            var i: u32 = 0;
            while (i < n) : (i += 1) {
                if (store.getItem(i)) |item| {
                    const completion_item: *CompletionItem = @ptrCast(@alignCast(item));
                    completion_item.deinit(alloc);
                }
            }
        }

        gobject.Object.virtual_methods.dispose.call(Class.parent, self.as(Parent));
    }

    pub fn updateCompletions(self: *Self, query: []const u8, completions: []const struct { text: []const u8, description: []const u8, icon_name: ?[]const u8, confidence: f32 }) void {
        const priv = getPriv(self);
        const alloc = Application.default().allocator();

        // Clear existing completions
        if (priv.completions_store) |store| {
            const n = store.getNItems();
            var i: u32 = 0;
            while (i < n) : (i += 1) {
                if (store.getItem(i)) |item| {
                    const completion_item: *CompletionItem = @ptrCast(@alignCast(item));
                    completion_item.deinit(alloc);
                }
            }
            store.removeAll();
        }

        // Update query
        if (priv.current_query) |old_query| {
            alloc.free(old_query);
        }
        priv.current_query = alloc.dupe(u8, query) catch null;

        // Add new completions
        if (priv.completions_store) |store| {
            for (completions) |comp| {
                const item = CompletionItem.new(alloc, comp.text, comp.description, comp.icon_name, comp.confidence) catch continue;
                store.append(item.as(gobject.Object));
            }
        }

        // Show/hide based on whether we have completions
        self.as(gtk.Popover).setVisible(@intFromBool(completions.len > 0));
    }

    pub fn getSelectedCompletion(self: *Self) ?[]const u8 {
        const priv = getPriv(self);
        if (priv.completions_store) |store| {
            if (priv.selected_index < store.getNItems()) {
                if (store.getItem(priv.selected_index)) |item| {
                    const completion_item: *CompletionItem = @ptrCast(@alignCast(item));
                    return completion_item.text;
                }
            }
        }
        return null;
    }

    pub fn selectNext(self: *Self) void {
        const priv = getPriv(self);
        if (priv.completions_store) |store| {
            const count = store.getNItems();
            if (count > 0) {
                priv.selected_index = (priv.selected_index + 1) % count;
            }
        }
    }

    pub fn selectPrevious(self: *Self) void {
        const priv = getPriv(self);
        if (priv.completions_store) |store| {
            const count = store.getNItems();
            if (count > 0) {
                priv.selected_index = if (priv.selected_index == 0) count - 1 else priv.selected_index - 1;
            }
        }
    }

    pub fn clear(self: *Self) void {
        const priv = getPriv(self);
        const alloc = Application.default().allocator();
        if (priv.completions_store) |store| {
            // Free all items before removing
            const n = store.getNItems();
            var i: u32 = 0;
            while (i < n) : (i += 1) {
                if (store.getItem(i)) |item| {
                    const completion_item: *CompletionItem = @ptrCast(@alignCast(item));
                    completion_item.deinit(alloc);
                }
            }
            store.removeAll();
        }
        priv.selected_index = 0;
        self.as(gtk.Popover).setVisible(@intFromBool(false));
    }
};
