//! Environment Variables Manager UI
//! Provides Warp-like UI for managing environment variables

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

const log = std.log.scoped(.gtk_ghostty_env_manager);

pub const EnvManagerDialog = extern struct {
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
        env_list: ?*gtk.ListView = null,
        env_store: ?*gio.ListStore = null,
        search_entry: ?*gtk.SearchEntry = null,
        add_btn: ?*gtk.Button = null,
        scope_dropdown: ?*gtk.DropDown = null,
        pub var offset: c_int = 0;
    };

    pub const EnvItem = extern struct {
        parent_instance: gobject.Object,
        name: [:0]const u8,
        value: [:0]const u8,
        scope: EnvScope,
        enabled: bool = true,

        pub const Parent = gobject.Object;

        pub const EnvScope = enum {
            session,
            user,
            system,
            project,
        };

        pub const ItemClass = extern struct {
            parent_class: gobject.Object.Class,
            var parent: *gobject.Object.Class = undefined;

            fn init(class: *ItemClass) callconv(.c) void {
                gobject.Object.virtual_methods.dispose.implement(class, &EnvItem.dispose);
            }

            fn dispose(self: *EnvItem) callconv(.c) void {
                const alloc = Application.default().allocator();
                if (self.name.len > 0) {
                    alloc.free(self.name);
                    self.name = "";
                }
                if (self.value.len > 0) {
                    alloc.free(self.value);
                    self.value = "";
                }
                gobject.Object.virtual_methods.dispose.call(ItemClass.parent, self);
            }
        };

        pub const getGObjectType = gobject.ext.defineClass(EnvItem, .{
            .name = "GhosttyEnvItem",
            .classInit = &ItemClass.init,
            .parent_class = &ItemClass.parent,
        });

        pub fn new(alloc: Allocator, name: []const u8, value: []const u8, scope: EnvScope) !*EnvItem {
            const self = gobject.ext.newInstance(EnvItem, .{});
            self.scope = scope;
            self.enabled = true;
            self.name = "";
            self.value = "";
            errdefer self.unref();

            self.name = try alloc.dupeZ(u8, name);
            self.value = try alloc.dupeZ(u8, value);
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

            if (priv.env_store) |store| {
                store.removeAll();
            }

            gobject.Object.virtual_methods.dispose.call(Class.parent, self.as(Parent));
        }

        pub const as = C.Class.as;
    };

    pub const getGObjectType = gobject.ext.defineClass(Self, .{
        .name = "GhosttyEnvManagerDialog",
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
        self.as(adw.PreferencesWindow).setTitle("Environment Variables");

        // Create env store
        const store = gio.ListStore.new(EnvItem.getGObjectType());
        priv.env_store = store;

        // Create search entry
        const search_entry = gtk.SearchEntry.new();
        search_entry.setPlaceholderText("Search variables...");
        _ = search_entry.connectSearchChanged(&onSearchChanged, self);
        priv.search_entry = search_entry;

        // Create scope dropdown
        const scope_store = gio.ListStore.new(gobject.Object.getGObjectType());
        const scope_dropdown = gtk.DropDown.new(scope_store.as(gio.ListModel), null);
        scope_dropdown.setTooltipText("Filter by scope");
        _ = scope_dropdown.connectNotify("selected", &onScopeChanged, self);
        priv.scope_dropdown = scope_dropdown;

        // Create add button
        const add_btn = gtk.Button.new();
        add_btn.setIconName("list-add-symbolic");
        add_btn.setTooltipText("Add Variable");
        _ = add_btn.connectClicked(&onAddEnv, self);
        priv.add_btn = add_btn;

        // Create list view
        const factory = gtk.SignalListItemFactory.new();
        factory.connectSetup(&setupEnvItem, null);
        factory.connectBind(&bindEnvItem, null);

        const selection = gtk.SingleSelection.new(store.as(gio.ListModel));
        const list_view = gtk.ListView.new(selection.as(gtk.SelectionModel), factory);
        list_view.setSingleClickActivate(true);
        _ = list_view.connectActivate(&onEnvActivated, self);
        priv.env_list = list_view;

        // Create scrolled window
        const scrolled = gtk.ScrolledWindow.new();
        scrolled.setChild(list_view.as(gtk.Widget));
        scrolled.setVexpand(true);

        // Create header bar
        const header = adw.HeaderBar.new();
        header.setTitleWidget(gtk.Label.new("Environment Variables"));
        header.packStart(search_entry.as(gtk.Widget));
        header.packStart(scope_dropdown.as(gtk.Widget));
        header.packEnd(add_btn.as(gtk.Widget));

        // Create main page
        const page = adw.PreferencesPage.new();
        page.setIconName("environment-symbolic");
        page.setTitle("Environment");

        const group = adw.PreferencesGroup.new();
        group.setTitle("Environment Variables");
        group.setDescription("Manage environment variables for your terminal sessions");
        group.add(scrolled.as(gtk.Widget));

        page.add(group.as(gtk.Widget));
        self.as(adw.PreferencesWindow).add(page.as(gtk.Widget));

        // Load environment variables
        loadEnvVars(self);
    }

    fn setupEnvItem(_: *gtk.SignalListItemFactory, item: *gtk.ListItem, _: ?*anyopaque) callconv(.c) void {
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

        const value_label = gtk.Label.new("");
        value_label.setXalign(0);
        value_label.addCssClass("monospace");
        value_label.addCssClass("dim-label");
        value_label.setSelectable(true);
        value_label.setEllipsize(gtk.EllipsizeMode.end);

        const scope_label = gtk.Label.new("");
        scope_label.setXalign(0);
        scope_label.addCssClass("caption");
        scope_label.addCssClass("dim-label");

        info_box.append(name_label.as(gtk.Widget));
        info_box.append(value_label.as(gtk.Widget));
        info_box.append(scope_label.as(gtk.Widget));

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
        _ = toggle.connectNotify("active", &Self.onToggleEnvListItemHandler, item);
        _ = edit_btn.connectClicked(&Self.onEditEnvListItem, item);
        _ = delete_btn.connectClicked(&Self.onDeleteEnvListItem, item);
    }

    fn bindEnvItem(_: *gtk.SignalListItemFactory, item: *gtk.ListItem, _: ?*anyopaque) callconv(.c) void {
        const entry = item.getItem() orelse return;
        const env_item = @as(*EnvItem, @ptrCast(@alignCast(entry)));
        const box = item.getChild() orelse return;
        const box_widget = box.as(gtk.Box);

        if (box_widget.getFirstChild()) |toggle| {
            toggle.as(gtk.Switch).setActive(env_item.enabled);
            if (toggle.getNextSibling()) |info_box| {
                if (info_box.as(gtk.Box).getFirstChild()) |name| {
                    name.as(gtk.Label).setText(env_item.name);
                    if (name.getNextSibling()) |value| {
                        value.as(gtk.Label).setText(env_item.value);
                        if (value.getNextSibling()) |scope| {
                            const scope_text = switch (env_item.scope) {
                                .session => "Session",
                                .user => "User",
                                .system => "System",
                                .project => "Project",
                            };
                            scope.as(gtk.Label).setText(scope_text);
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

    fn onScopeChanged(_: *gobject.Object, _: glib.ParamSpec, self: *Self) callconv(.c) void {
        _ = self;
        // TODO: Implement scope filtering
    }

    fn onEditEnvListItem(button: *gtk.Button, list_item: *gtk.ListItem) callconv(.c) void {
        const entry = list_item.getItem() orelse return;
        const env_item = @as(*EnvItem, @ptrCast(@alignCast(entry)));
        onEditEnv(button, env_item);
    }

    fn onToggleEnvListItemHandler(obj: *gobject.Object, _: glib.ParamSpec, list_item: *gtk.ListItem) callconv(.c) void {
        const entry = list_item.getItem() orelse return;
        const env_item = @as(*EnvItem, @ptrCast(@alignCast(entry)));
        const toggle = @as(*gtk.Switch, @ptrCast(@alignCast(obj)));
        env_item.enabled = toggle.getActive();
        // Find parent dialog and save
        if (list_item.getChild()) |child| {
            if (child.as(gtk.Widget).getRoot()) |root| {
                if (root.as(gtk.Window).getTransientFor()) |transient| {
                    var current: ?*gtk.Widget = transient.as(gtk.Widget);
                    while (current) |widget| {
                        if (widget.getType() == Self.getGObjectType()) {
                            const self = @as(*Self, @ptrCast(@alignCast(widget)));
                            self.saveEnvVars();
                            break;
                        }
                        current = widget.getParent();
                    }
                }
            }
        }
    }

    fn onDeleteEnvListItem(button: *gtk.Button, list_item: *gtk.ListItem) callconv(.c) void {
        const entry = list_item.getItem() orelse return;
        const env_item = @as(*EnvItem, @ptrCast(@alignCast(entry)));
        onDeleteEnv(button, env_item);
    }

    fn onEnvActivated(_: *gtk.ListView, position: u32, self: *Self) callconv(.c) void {
        const priv = getPriv(self);
        if (priv.env_store) |store| {
            if (store.getItem(position)) |item| {
                const env_item: *EnvItem = @ptrCast(@alignCast(item));
                // TODO: Show edit dialog
                log.info("Env var activated: {s}", .{env_item.name});
            }
        }
    }

    fn onEditEnv(_: *gtk.Button, env_item: *EnvItem) callconv(.c) void {
        // TODO: Show edit dialog
        log.info("Edit env var: {s}", .{env_item.name});
    }

    fn onDeleteEnv(_: *gtk.Button, env_item: *EnvItem) callconv(.c) void {
        // Find parent dialog and remove from store
        if (env_item.as(gobject.Object).getParent()) |parent| {
            var current: ?*gtk.Widget = parent.as(gtk.Widget);
            while (current) |widget| {
                if (widget.getType() == Self.getGObjectType()) {
                    const self = @as(*Self, @ptrCast(@alignCast(widget)));
                    const priv = getPriv(self);
                    if (priv.env_store) |store| {
                        const n = store.getNItems();
                        var i: u32 = 0;
                        while (i < n) : (i += 1) {
                            if (store.getItem(i)) |item| {
                                if (item == env_item.as(gobject.Object)) {
                                    // Remove from store - GObject dispose handles cleanup
                                    store.remove(i);
                                    self.saveEnvVars();
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

    fn onAddEnv(_: *gtk.Button, _: *Self) callconv(.c) void {
        // TODO: Show dialog to add new env var
        log.info("Add env var clicked", .{});
    }

    fn loadEnvVars(self: *Self) void {
        const alloc = Application.default().allocator();
        const filepath = persistence.getDataFilePath(alloc, "env_vars.json") catch |err| {
            log.err("Failed to get env vars file path: {}", .{err});
            // Load example variables as fallback
            const priv = getPriv(self);
            const path = EnvItem.new(alloc, "PATH", "/usr/bin:/usr/local/bin", .system) catch return;
            if (priv.env_store) |store| {
                store.append(path.as(gobject.Object));
            }
            const home = EnvItem.new(alloc, "HOME", "/home/user", .user) catch return;
            if (priv.env_store) |store| {
                store.append(home.as(gobject.Object));
            }
            return;
        };
        defer alloc.free(filepath);

        const EnvVarsData = struct {
            env_vars: []const struct {
                name: []const u8,
                value: []const u8,
                scope: []const u8,
                enabled: bool = true,
            } = &.{},
        };

        const data = persistence.loadJson(EnvVarsData, alloc, filepath) catch |err| {
            log.err("Failed to load env vars: {}", .{err});
            // Load example variables as fallback
            const priv = getPriv(self);
            const path = EnvItem.new(alloc, "PATH", "/usr/bin:/usr/local/bin", .system) catch return;
            if (priv.env_store) |store| {
                store.append(path.as(gobject.Object));
            }
            const home = EnvItem.new(alloc, "HOME", "/home/user", .user) catch return;
            if (priv.env_store) |store| {
                store.append(home.as(gobject.Object));
            }
            return;
        };
        defer alloc.free(data.env_vars);

        for (data.env_vars) |ev| {
            const scope = if (std.mem.eql(u8, ev.scope, "session"))
                EnvItem.EnvScope.session
            else if (std.mem.eql(u8, ev.scope, "user"))
                EnvItem.EnvScope.user
            else if (std.mem.eql(u8, ev.scope, "system"))
                EnvItem.EnvScope.system
            else
                EnvItem.EnvScope.project;

            self.addEnvVar(ev.name, ev.value, scope) catch continue;
        }
    }

    fn saveEnvVars(self: *Self) void {
        const priv = getPriv(self);
        const alloc = Application.default().allocator();

        const filepath = persistence.getDataFilePath(alloc, "env_vars.json") catch |err| {
            log.err("Failed to get env vars file path: {}", .{err});
            return;
        };
        defer alloc.free(filepath);

        const EnvVarsData = struct {
            env_vars: []const struct {
                name: []const u8,
                value: []const u8,
                scope: []const u8,
                enabled: bool,
            },
        };

        if (priv.env_store) |store| {
            const n = store.getNItems();
            var env_vars_list = std.ArrayList(struct {
                name: []const u8,
                value: []const u8,
                scope: []const u8,
                enabled: bool,
            }).init(alloc);
            defer env_vars_list.deinit();

            var i: u32 = 0;
            while (i < n) : (i += 1) {
                if (store.getItem(i)) |item| {
                    const env_item: *EnvItem = @ptrCast(@alignCast(item));
                    const scope_str = switch (env_item.scope) {
                        .session => "session",
                        .user => "user",
                        .system => "system",
                        .project => "project",
                    };
                    env_vars_list.append(.{
                        .name = env_item.name,
                        .value = env_item.value,
                        .scope = scope_str,
                        .enabled = env_item.enabled,
                    }) catch continue;
                }
            }

            const data = EnvVarsData{ .env_vars = env_vars_list.toOwnedSlice() catch |err| {
                log.err("Failed to convert env vars list: {}", .{err});
                return;
            } };
            defer alloc.free(data.env_vars);

            persistence.saveJson(alloc, filepath, data) catch |err| {
                log.err("Failed to save env vars: {}", .{err});
            };
        }
    }

    pub fn addEnvVar(self: *Self, name: []const u8, value: []const u8, scope: EnvItem.EnvScope) !void {
        const priv = getPriv(self);
        const alloc = Application.default().allocator();

        const env_item = try EnvItem.new(alloc, name, value, scope);
        if (priv.env_store) |store| {
            store.append(env_item.as(gobject.Object));
        }
        saveEnvVars(self);
    }

    pub fn show(self: *Self, parent: *Window) void {
        self.as(adw.PreferencesWindow).setTransientFor(parent.as(gtk.Window));
        self.as(adw.PreferencesWindow).present();
    }
};
