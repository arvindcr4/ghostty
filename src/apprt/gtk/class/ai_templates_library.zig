//! Command Templates Library UI
//! Provides Warp-like command templates library for browsing and using command templates

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

const log = std.log.scoped(.gtk_ghostty_templates_library);

pub const TemplatesLibraryDialog = extern struct {
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
        templates_list: ?*gtk.ListView = null,
        templates_store: ?*gio.ListStore = null,
        category_filter: ?*gtk.DropDown = null,
        search_entry: ?*gtk.SearchEntry = null,
        pub var offset: c_int = 0;
    };

    pub const TemplateItem = extern struct {
        parent_instance: gobject.Object,
        name: [:0]const u8,
        command: [:0]const u8,
        description: [:0]const u8,
        category: [:0]const u8,
        tags: []const [:0]const u8 = &.{},
        variables: []const Variable = &.{},

        pub const Parent = gobject.Object;

        pub const Variable = struct {
            name: [:0]const u8,
            description: [:0]const u8,
            default_value: ?[:0]const u8 = null,
        };

        pub const ItemClass = extern struct {
            parent_class: gobject.Object.Class,
            var parent: *gobject.Object.Class = undefined;

            fn init(class: *ItemClass) callconv(.c) void {
                gobject.Object.virtual_methods.dispose.implement(class, &TemplateItem.dispose);
            }

            fn dispose(self: *TemplateItem) callconv(.c) void {
                const alloc = Application.default().allocator();
                alloc.free(self.name);
                alloc.free(self.command);
                alloc.free(self.description);
                alloc.free(self.category);
                for (self.tags) |tag| alloc.free(tag);
                if (self.tags.len > 0) {
                    alloc.free(self.tags.ptr);
                }
                for (self.variables) |var_| {
                    alloc.free(var_.name);
                    alloc.free(var_.description);
                    if (var_.default_value) |val| alloc.free(val);
                }
                if (self.variables.len > 0) {
                    alloc.free(self.variables.ptr);
                }
                gobject.Object.virtual_methods.dispose.call(ItemClass.parent, self);
            }
        };

        pub const getGObjectType = gobject.ext.defineClass(TemplateItem, .{
            .name = "GhosttyTemplateItem",
            .classInit = &ItemClass.init,
            .parent_class = &ItemClass.parent,
        });

        pub fn new(alloc: Allocator, name: []const u8, command: []const u8, description: []const u8, category: []const u8) !*TemplateItem {
            const self = gobject.ext.newInstance(TemplateItem, .{});
            self.name = try alloc.dupeZ(u8, name);
            errdefer alloc.free(self.name);
            self.command = try alloc.dupeZ(u8, command);
            errdefer alloc.free(self.command);
            self.description = try alloc.dupeZ(u8, description);
            errdefer alloc.free(self.description);
            self.category = try alloc.dupeZ(u8, category);
            errdefer alloc.free(self.category);
            return self;
        }

        pub fn deinit(self: *TemplateItem, alloc: Allocator) void {
            alloc.free(self.name);
            alloc.free(self.command);
            alloc.free(self.description);
            alloc.free(self.category);
            for (self.tags) |tag| alloc.free(tag);
            if (self.tags.len > 0) {
                alloc.free(self.tags.ptr);
            }
            for (self.variables) |var_| {
                alloc.free(var_.name);
                alloc.free(var_.description);
                if (var_.default_value) |val| alloc.free(val);
            }
            if (self.variables.len > 0) {
                alloc.free(self.variables.ptr);
            }
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
            const alloc = Application.default().allocator();

            // Clean up all template items in the store to prevent memory leaks.
            // We must: (1) deinit internal allocations, (2) clear store to release refs.
            // This prevents double-free when GObject finalizes the store.
            if (priv.templates_store) |store| {
                const n = store.getNItems();
                var i: u32 = 0;
                while (i < n) : (i += 1) {
                    if (store.getItem(i)) |item| {
                        const template_item: *TemplateItem = @ptrCast(@alignCast(item));
                        template_item.deinit(alloc);
                    }
                }
                // Clear store to release references before parent dispose
                store.removeAll();
            }

            gobject.Object.virtual_methods.dispose.call(Class.parent, self.as(Parent));
        }

        pub const as = C.Class.as;
    };

    pub const getGObjectType = gobject.ext.defineClass(Self, .{
        .name = "GhosttyTemplatesLibraryDialog",
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
        self.as(adw.PreferencesWindow).setTitle("Command Templates");

        // Create templates store
        const store = gio.ListStore.new(TemplateItem.getGObjectType());
        priv.templates_store = store;

        // Create search entry
        const search_entry = gtk.SearchEntry.new();
        search_entry.setPlaceholderText("Search templates...");
        _ = search_entry.connectTextChanged(&onSearchChanged, self);
        priv.search_entry = search_entry;

        // Create category filter
        const category_store = gio.ListStore.new(gobject.Object.getGObjectType());
        const category_filter = gtk.DropDown.new(category_store.as(gobject.Object), null);
        _ = category_filter.connectNotify("selected", &onCategoryChanged, self);
        priv.category_filter = category_filter;

        // Create list view
        const factory = gtk.SignalListItemFactory.new();
        factory.connectSetup(&setupTemplateItem, null);
        factory.connectBind(&bindTemplateItem, null);

        const selection = gtk.SingleSelection.new(store.as(gobject.Object));
        const list_view = gtk.ListView.new(selection.as(gtk.SelectionModel), factory);
        list_view.setSingleClickActivate(true);
        _ = list_view.connectActivate(&onTemplateActivated, self);
        priv.templates_list = list_view;

        // Create scrolled window
        const scrolled = gtk.ScrolledWindow.new();
        scrolled.setChild(list_view.as(gtk.Widget));
        scrolled.setVexpand(true);

        // Create header bar
        const header = adw.HeaderBar.new();
        header.setTitleWidget(gtk.Label.new("Command Templates"));
        header.packStart(search_entry.as(gtk.Widget));
        header.packStart(category_filter.as(gtk.Widget));

        // Create main page
        const page = adw.PreferencesPage.new();
        page.setIconName("text-x-generic-symbolic");
        page.setTitle("Templates");

        const group = adw.PreferencesGroup.new();
        group.setTitle("Command Templates");
        group.setDescription("Browse and use pre-built command templates");
        group.add(scrolled.as(gtk.Widget));

        page.add(group.as(gtk.Widget));
        self.as(adw.PreferencesWindow).add(page.as(gtk.Widget));

        // Load templates
        loadTemplates(self);
    }

    fn setupTemplateItem(_: *gtk.SignalListItemFactory, item: *gtk.ListItem, _: ?*anyopaque) callconv(.c) void {
        const box = gtk.Box.new(gtk.Orientation.horizontal, 12);
        box.setMarginStart(12);
        box.setMarginEnd(12);
        box.setMarginTop(6);
        box.setMarginBottom(6);

        const icon = gtk.Image.new();
        icon.setIconName("text-x-generic-symbolic");
        icon.setIconSize(gtk.IconSize.large);

        const info_box = gtk.Box.new(gtk.Orientation.vertical, 4);
        info_box.setHexpand(true);
        info_box.setHalign(gtk.Align.start);

        const name_label = gtk.Label.new("");
        name_label.setXalign(0);
        name_label.addCssClass("title-4");

        const command_label = gtk.Label.new("");
        command_label.setXalign(0);
        command_label.addCssClass("monospace");
        command_label.setSelectable(true);

        const desc_label = gtk.Label.new("");
        desc_label.setXalign(0);
        desc_label.addCssClass("dim-label");
        desc_label.setWrap(true);

        const category_label = gtk.Label.new("");
        category_label.setXalign(0);
        category_label.addCssClass("caption");
        category_label.addCssClass("dim-label");

        info_box.append(name_label.as(gtk.Widget));
        info_box.append(command_label.as(gtk.Widget));
        info_box.append(desc_label.as(gtk.Widget));
        info_box.append(category_label.as(gtk.Widget));

        const use_btn = gtk.Button.new();
        use_btn.setIconName("media-playback-start-symbolic");
        use_btn.setTooltipText("Use Template");
        use_btn.addCssClass("circular");
        use_btn.addCssClass("flat");
        use_btn.addCssClass("suggested-action");

        box.append(icon.as(gtk.Widget));
        box.append(info_box.as(gtk.Widget));
        box.append(use_btn.as(gtk.Widget));

        item.setChild(box.as(gtk.Widget));
    }

    fn bindTemplateItem(_: *gtk.SignalListItemFactory, item: *gtk.ListItem, _: ?*anyopaque) callconv(.c) void {
        const entry = item.getItem() orelse return;
        const template_item = @as(*TemplateItem, @ptrCast(entry));
        const box = item.getChild() orelse return;
        const box_widget = box.as(gtk.Box);

        if (box_widget.getFirstChild()) |icon| {
            if (icon.getNextSibling()) |info_box| {
                if (info_box.as(gtk.Box).getFirstChild()) |name| {
                    name.as(gtk.Label).setText(template_item.name);
                    if (name.getNextSibling()) |command| {
                        command.as(gtk.Label).setText(template_item.command);
                        if (command.getNextSibling()) |desc| {
                            desc.as(gtk.Label).setText(template_item.description);
                            if (desc.getNextSibling()) |category| {
                                var cat_buf: [128]u8 = undefined;
                                const cat_text = std.fmt.bufPrintZ(&cat_buf, "Category: {s}", .{template_item.category}) catch "Template";
                                category.as(gtk.Label).setText(cat_text);
                            }
                        }
                    }
                }
                if (info_box.getNextSibling()) |use_btn| {
                    _ = use_btn.as(gtk.Button).connectClicked(&onUseTemplate, template_item);
                }
            }
        }
    }

    fn onSearchChanged(entry: *gtk.SearchEntry, self: *Self) callconv(.c) void {
        _ = entry;
        _ = self;
        // TODO: Implement search filtering
    }

    fn onCategoryChanged(_: *gobject.Object, _: glib.ParamSpec, self: *Self) callconv(.c) void {
        _ = self;
        // TODO: Implement category filtering
    }

    fn onTemplateActivated(_: *gtk.ListView, position: u32, self: *Self) callconv(.c) void {
        const priv = getPriv(self);
        if (priv.templates_store) |store| {
            if (store.getItem(position)) |item| {
                const template_item: *TemplateItem = @ptrCast(@alignCast(item));
                // TODO: Show template editor dialog
                log.info("Template activated: {s}", .{template_item.name});
            }
        }
    }

    fn onUseTemplate(_: *gtk.Button, template_item: *TemplateItem) callconv(.c) void {
        // TODO: Show variable input dialog and execute template
        log.info("Use template: {s}", .{template_item.command});
    }

    fn loadTemplates(self: *Self) void {
        const priv = getPriv(self);
        const alloc = Application.default().allocator();
        // TODO: Load templates from persistent storage or built-in templates
        log.info("Loading templates...", .{});

        // Add some example templates
        const git_status = TemplateItem.new(alloc, "Git Status", "git status", "Check git repository status", "Git") catch return;
        if (priv.templates_store) |store| {
            store.append(git_status.as(gobject.Object));
        }

        const docker_ps = TemplateItem.new(alloc, "Docker Containers", "docker ps -a", "List all Docker containers", "Docker") catch return;
        if (priv.templates_store) |store| {
            store.append(docker_ps.as(gobject.Object));
        }
    }

    pub fn show(self: *Self, parent: *Window) void {
        self.as(adw.PreferencesWindow).setTransientFor(parent.as(gtk.Window));
        self.as(adw.PreferencesWindow).present();
    }
};
