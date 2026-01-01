//! Output Filters UI
//! Provides Warp-like filtering for command outputs

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
const persistence = @import("ai_persistence.zig");

const log = std.log.scoped(.gtk_ghostty_output_filters);

pub const OutputFiltersDialog = extern struct {
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
        filters_list: ?*gtk.ListView = null,
        filters_store: ?*gio.ListStore = null,
        add_btn: ?*gtk.Button = null,
        pub var offset: c_int = 0;
    };

    pub const FilterItem = extern struct {
        parent_instance: gobject.Object,
        name: [:0]const u8,
        pattern: [:0]const u8,
        filter_type: FilterType,
        enabled: bool = true,

        pub const Parent = gobject.Object;

        pub const FilterType = enum {
            contains,
            regex,
            starts_with,
            ends_with,
            equals,
            not_contains,
        };

        pub const ItemClass = extern struct {
            parent_class: gobject.Object.Class,
            var parent: *gobject.Object.Class = undefined;

            fn init(class: *ItemClass) callconv(.c) void {
                gobject.Object.virtual_methods.dispose.implement(class, &FilterItem.dispose);
            }

            fn dispose(self: *FilterItem) callconv(.c) void {
                const alloc = Application.default().allocator();
                if (self.name.len > 0) {
                    alloc.free(self.name);
                    self.name = "";
                }
                if (self.pattern.len > 0) {
                    alloc.free(self.pattern);
                    self.pattern = "";
                }
                gobject.Object.virtual_methods.dispose.call(ItemClass.parent, self);
            }
        };

        pub const getGObjectType = gobject.ext.defineClass(FilterItem, .{
            .name = "GhosttyFilterItem",
            .classInit = &ItemClass.init,
            .parent_class = &ItemClass.parent,
        });

        pub fn new(alloc: Allocator, name: []const u8, pattern: []const u8, filter_type: FilterType) !*FilterItem {
            const self = gobject.ext.newInstance(FilterItem, .{});
            self.filter_type = filter_type;
            self.enabled = true;
            self.name = "";
            self.pattern = "";
            errdefer self.unref();

            self.name = try alloc.dupeZ(u8, name);
            self.pattern = try alloc.dupeZ(u8, pattern);
            return self;
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

            if (priv.filters_store) |store| {
                store.removeAll();
            }

            gobject.Object.virtual_methods.dispose.call(Class.parent, self.as(Parent));
        }

        pub const as = C.Class.as;
    };

    pub const getGObjectType = gobject.ext.defineClass(Self, .{
        .name = "GhosttyOutputFiltersDialog",
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
        self.as(adw.PreferencesWindow).setTitle("Output Filters");

        // Create filters store
        const store = gio.ListStore.new(FilterItem.getGObjectType());
        priv.filters_store = store;

        // Create add button
        const add_btn = gtk.Button.new();
        add_btn.setIconName("list-add-symbolic");
        add_btn.setTooltipText("Add Filter");
        _ = add_btn.connectClicked(&onAddFilter, self);
        priv.add_btn = add_btn;

        // Create list view
        const factory = gtk.SignalListItemFactory.new();
        factory.connectSetup(&setupFilterItem, null);
        factory.connectBind(&bindFilterItem, null);

        const selection = gtk.SingleSelection.new(store.as(gio.ListModel));
        const list_view = gtk.ListView.new(selection.as(gtk.SelectionModel), factory);
        list_view.setSingleClickActivate(true);
        _ = list_view.connectActivate(&onFilterActivated, self);
        priv.filters_list = list_view;

        // Create scrolled window
        const scrolled = gtk.ScrolledWindow.new();
        scrolled.setChild(list_view.as(gtk.Widget));
        scrolled.setVexpand(true);

        // Create header bar
        const header = adw.HeaderBar.new();
        header.setTitleWidget(gtk.Label.new("Output Filters"));
        header.packEnd(add_btn.as(gtk.Widget));

        // Create main page
        const page = adw.PreferencesPage.new();
        page.setIconName("view-filter-symbolic");
        page.setTitle("Filters");

        const group = adw.PreferencesGroup.new();
        group.setTitle("Output Filters");
        group.setDescription("Filter command outputs by pattern");
        group.add(scrolled.as(gtk.Widget));

        page.add(group.as(gtk.Widget));
        self.as(adw.PreferencesWindow).add(page.as(gtk.Widget));

        // Load filters
        loadFilters(self);
    }

    fn setupFilterItem(_: *gtk.SignalListItemFactory, item: *gtk.ListItem, _: ?*anyopaque) callconv(.c) void {
        const box = gtk.Box.new(gtk.Orientation.horizontal, 12);
        box.setMarginStart(12);
        box.setMarginEnd(12);
        box.setMarginTop(6);
        box.setMarginBottom(6);

        const toggle = gtk.Switch.new();
        toggle.setValign(gtk.Align.center);

        const info_box = gtk.Box.new(gtk.Orientation.vertical, 4);
        info_box.setHexpand(true);
        info_box.setHalign(gtk.Align.start);

        const name_label = gtk.Label.new("");
        name_label.setXalign(0);
        name_label.addCssClass("title-4");

        const pattern_label = gtk.Label.new("");
        pattern_label.setXalign(0);
        pattern_label.addCssClass("monospace");
        pattern_label.addCssClass("dim-label");
        pattern_label.setSelectable(true);

        info_box.append(name_label.as(gtk.Widget));
        info_box.append(pattern_label.as(gtk.Widget));

        const action_box = gtk.Box.new(gtk.Orientation.horizontal, 4);
        const edit_btn = gtk.Button.new();
        edit_btn.setIconName("document-edit-symbolic");
        edit_btn.setTooltipText("Edit");
        edit_btn.addCssClass("circular");
        edit_btn.addCssClass("flat");

        const delete_btn = gtk.Button.new();
        delete_btn.setIconName("user-trash-symbolic");
        delete_btn.setTooltipText("Delete");
        delete_btn.addCssClass("circular");
        delete_btn.addCssClass("flat");
        delete_btn.addCssClass("destructive-action");

        action_box.append(edit_btn.as(gtk.Widget));
        action_box.append(delete_btn.as(gtk.Widget));

        box.append(toggle.as(gtk.Widget));
        box.append(info_box.as(gtk.Widget));
        box.append(action_box.as(gtk.Widget));

        item.setChild(box.as(gtk.Widget));

        // Connect signal handlers once during setup to prevent leaks on rebind
        _ = toggle.connectNotify("active", &Self.onToggleFilterListItemHandler, item);
        _ = edit_btn.connectClicked(&Self.onEditFilterListItem, item);
        _ = delete_btn.connectClicked(&Self.onDeleteFilterListItem, item);
    }

    fn bindFilterItem(_: *gtk.SignalListItemFactory, item: *gtk.ListItem, _: ?*anyopaque) callconv(.c) void {
        const entry = item.getItem() orelse return;
        const filter_item = @as(*FilterItem, @ptrCast(@alignCast(entry)));
        const box = item.getChild() orelse return;
        const box_widget = box.as(gtk.Box);

        if (box_widget.getFirstChild()) |toggle| {
            toggle.as(gtk.Switch).setActive(filter_item.enabled);
            if (toggle.getNextSibling()) |info_box| {
                if (info_box.as(gtk.Box).getFirstChild()) |name| {
                    name.as(gtk.Label).setText(filter_item.name);
                    if (name.getNextSibling()) |pattern| {
                        pattern.as(gtk.Label).setText(filter_item.pattern);
                    }
                }
            }
        }
    }

    fn onToggleFilterListItemHandler(obj: *gobject.Object, _: glib.ParamSpec, list_item: *gtk.ListItem) callconv(.c) void {
        const entry = list_item.getItem() orelse return;
        const filter_item = @as(*FilterItem, @ptrCast(@alignCast(entry)));
        const toggle = @as(*gtk.Switch, @ptrCast(@alignCast(obj)));
        filter_item.enabled = toggle.getActive();
        // Find parent dialog and save
        if (list_item.getChild()) |child| {
            if (child.as(gtk.Widget).getRoot()) |root| {
                if (root.as(gtk.Window).getTransientFor()) |transient| {
                    var current: ?*gtk.Widget = transient.as(gtk.Widget);
                    while (current) |widget| {
                        if (widget.getType() == Self.getGObjectType()) {
                            const self = @as(*Self, @ptrCast(@alignCast(widget)));
                            self.saveFilters();
                            break;
                        }
                        current = widget.getParent();
                    }
                }
            }
        }
    }

    fn onEditFilterListItem(button: *gtk.Button, list_item: *gtk.ListItem) callconv(.c) void {
        const entry = list_item.getItem() orelse return;
        const filter_item = @as(*FilterItem, @ptrCast(@alignCast(entry)));
        onEditFilter(button, filter_item);
    }

    fn onDeleteFilterListItem(button: *gtk.Button, list_item: *gtk.ListItem) callconv(.c) void {
        const entry = list_item.getItem() orelse return;
        const filter_item = @as(*FilterItem, @ptrCast(@alignCast(entry)));
        onDeleteFilter(button, filter_item);
    }

    fn onFilterActivated(_: *gtk.ListView, position: u32, self: *Self) callconv(.c) void {
        const priv = getPriv(self);
        if (priv.filters_store) |store| {
            if (store.getItem(position)) |item| {
                const filter_item: *FilterItem = @ptrCast(@alignCast(item));
                // TODO: Show edit dialog
                log.info("Filter activated: {s}", .{filter_item.name});
            }
        }
    }

    fn onEditFilter(_: *gtk.Button, filter_item: *FilterItem) callconv(.c) void {
        // TODO: Show edit dialog
        log.info("Edit filter: {s}", .{filter_item.name});
    }

    fn onDeleteFilter(_: *gtk.Button, filter_item: *FilterItem) callconv(.c) void {
        // Find parent dialog and remove from store
        // Get the list item's parent to find the dialog
        if (filter_item.as(gobject.Object).getParent()) |parent| {
            var current: ?*gtk.Widget = parent.as(gtk.Widget);
            while (current) |widget| {
                if (widget.getType() == Self.getGObjectType()) {
                    const self = @as(*Self, @ptrCast(@alignCast(widget)));
                    const priv = getPriv(self);
                    if (priv.filters_store) |store| {
                        const n = store.getNItems();
                        var i: u32 = 0;
                        while (i < n) : (i += 1) {
                            if (store.getItem(i)) |item| {
                                if (item == filter_item.as(gobject.Object)) {
                                    // Remove from store - GObject dispose handles cleanup
                                    store.remove(i);
                                    self.saveFilters();
                                    break;
                                }
                            }
                        }
                    }
                    break;
                }
                current = widget.getParent();
            }
        }
    }

    fn onAddFilter(_: *gtk.Button, _: *Self) callconv(.c) void {
        // TODO: Show dialog to add new filter
        log.info("Add filter clicked", .{});
    }

    fn loadFilters(self: *Self) void {
        const alloc = Application.default().allocator();
        const filepath = persistence.getDataFilePath(alloc, "output_filters.json") catch |err| {
            log.err("Failed to get filters file path: {}", .{err});
            return;
        };
        defer alloc.free(filepath);

        const FiltersData = struct {
            filters: []const struct {
                name: []const u8,
                pattern: []const u8,
                filter_type: []const u8,
                enabled: bool = true,
            } = &.{},
        };

        const data = persistence.loadJson(FiltersData, alloc, filepath) catch |err| {
            log.err("Failed to load filters: {}", .{err});
            return;
        };
        defer alloc.free(data.filters);

        for (data.filters) |f| {
            const filter_type = if (std.mem.eql(u8, f.filter_type, "regex"))
                FilterItem.FilterType.regex
            else if (std.mem.eql(u8, f.filter_type, "starts_with"))
                FilterItem.FilterType.starts_with
            else if (std.mem.eql(u8, f.filter_type, "ends_with"))
                FilterItem.FilterType.ends_with
            else if (std.mem.eql(u8, f.filter_type, "equals"))
                FilterItem.FilterType.equals
            else if (std.mem.eql(u8, f.filter_type, "not_contains"))
                FilterItem.FilterType.not_contains
            else
                FilterItem.FilterType.contains;

            self.addFilter(f.name, f.pattern, filter_type) catch continue;
        }
    }

    fn saveFilters(self: *Self) void {
        const priv = getPriv(self);
        const alloc = Application.default().allocator();

        const filepath = persistence.getDataFilePath(alloc, "output_filters.json") catch |err| {
            log.err("Failed to get filters file path: {}", .{err});
            return;
        };
        defer alloc.free(filepath);

        const FiltersData = struct {
            filters: []const struct {
                name: []const u8,
                pattern: []const u8,
                filter_type: []const u8,
                enabled: bool,
            },
        };

        if (priv.filters_store) |store| {
            const n = store.getNItems();
            var filters_list = std.ArrayList(struct {
                name: []const u8,
                pattern: []const u8,
                filter_type: []const u8,
                enabled: bool,
            }).init(alloc);
            defer filters_list.deinit();

            var i: u32 = 0;
            while (i < n) : (i += 1) {
                if (store.getItem(i)) |item| {
                    const filter_item: *FilterItem = @ptrCast(@alignCast(item));
                    const filter_type_str = switch (filter_item.filter_type) {
                        .contains => "contains",
                        .regex => "regex",
                        .starts_with => "starts_with",
                        .ends_with => "ends_with",
                        .equals => "equals",
                        .not_contains => "not_contains",
                    };
                    filters_list.append(.{
                        .name = filter_item.name,
                        .pattern = filter_item.pattern,
                        .filter_type = filter_type_str,
                        .enabled = filter_item.enabled,
                    }) catch continue;
                }
            }

            const data = FiltersData{ .filters = filters_list.toOwnedSlice() catch |err| {
                log.err("Failed to convert filters list: {}", .{err});
                return;
            } };
            defer alloc.free(data.filters);

            persistence.saveJson(alloc, filepath, data) catch |err| {
                log.err("Failed to save filters: {}", .{err});
            };
        }
    }

    pub fn addFilter(self: *Self, name: []const u8, pattern: []const u8, filter_type: FilterItem.FilterType) !void {
        const priv = getPriv(self);
        const alloc = Application.default().allocator();

        const filter = try FilterItem.new(alloc, name, pattern, filter_type);
        if (priv.filters_store) |store| {
            store.append(filter.as(gobject.Object));
        }
        saveFilters(self);
    }

    pub fn show(self: *Self, parent: *Window) void {
        self.as(adw.PreferencesWindow).setTransientFor(parent.as(gtk.Window));
        self.as(adw.PreferencesWindow).present();
    }
};
