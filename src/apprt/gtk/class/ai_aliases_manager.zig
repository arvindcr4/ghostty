//! Command Aliases Manager UI
//! Provides Warp-like UI for managing shell aliases

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

const log = std.log.scoped(.gtk_ghostty_aliases_manager);

pub const AliasesManagerDialog = extern struct {
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
        aliases_list: ?*gtk.ListView = null,
        aliases_store: ?*gio.ListStore = null,
        search_entry: ?*gtk.SearchEntry = null,
        add_btn: ?*gtk.Button = null,
        shell_dropdown: ?*gtk.DropDown = null,
        pub var offset: c_int = 0;
    };

    pub const AliasItem = extern struct {
        parent_instance: gobject.Object,
        name: [:0]const u8,
        command: [:0]const u8,
        shell: [:0]const u8,
        description: ?[:0]const u8 = null,
        enabled: bool = true,

        pub const Parent = gobject.Object;

        pub const ItemClass = extern struct {
            parent_class: gobject.Object.Class,
            var parent: *gobject.Object.Class = undefined;

            fn init(class: *ItemClass) callconv(.c) void {
                gobject.Object.virtual_methods.dispose.implement(class, &AliasItem.dispose);
            }

            fn dispose(self: *AliasItem) callconv(.c) void {
                const alloc = Application.default().allocator();
                alloc.free(self.name);
                alloc.free(self.command);
                alloc.free(self.shell);
                if (self.description) |desc| alloc.free(desc);
                gobject.Object.virtual_methods.dispose.call(ItemClass.parent, self);
            }
        };

        pub const getGObjectType = gobject.ext.defineClass(AliasItem, .{
            .name = "GhosttyAliasItem",
            .classInit = &ItemClass.init,
            .parent_class = &ItemClass.parent,
        });

        pub fn new(alloc: Allocator, name: []const u8, command: []const u8, shell: []const u8, description: ?[]const u8) !*AliasItem {
            const self = gobject.ext.newInstance(AliasItem, .{});
            self.name = try alloc.dupeZ(u8, name);
            errdefer alloc.free(self.name);
            self.command = try alloc.dupeZ(u8, command);
            errdefer alloc.free(self.command);
            self.shell = try alloc.dupeZ(u8, shell);
            errdefer alloc.free(self.shell);
            if (description) |desc| {
                self.description = try alloc.dupeZ(u8, desc);
                errdefer alloc.free(self.description.?);
            }
            return self;
        }

        pub fn deinit(self: *AliasItem, alloc: Allocator) void {
            alloc.free(self.name);
            alloc.free(self.command);
            alloc.free(self.shell);
            if (self.description) |desc| alloc.free(desc);
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

            // Clean up all alias items - just removeAll, GObject dispose handles item cleanup
            if (priv.aliases_store) |store| {
                store.removeAll();
            }

            gobject.Object.virtual_methods.dispose.call(Class.parent, self.as(Parent));
        }

        pub const as = C.Class.as;
    };

    pub const getGObjectType = gobject.ext.defineClass(Self, .{
        .name = "GhosttyAliasesManagerDialog",
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
        self.as(adw.PreferencesWindow).setTitle("Command Aliases");

        // Create aliases store
        const store = gio.ListStore.new(AliasItem.getGObjectType());
        priv.aliases_store = store;

        // Create search entry
        const search_entry = gtk.SearchEntry.new();
        search_entry.setPlaceholderText("Search aliases...");
        _ = search_entry.connectTextChanged(&onSearchChanged, self);
        priv.search_entry = search_entry;

        // Create shell dropdown
        const shell_store = gio.ListStore.new(gobject.Object.getGObjectType());
        const shell_dropdown = gtk.DropDown.new(shell_store.as(gio.ListModel), null);
        shell_dropdown.setTooltipText("Filter by shell");
        _ = shell_dropdown.connectNotify("selected", &onShellChanged, self);
        priv.shell_dropdown = shell_dropdown;

        // Create add button
        const add_btn = gtk.Button.new();
        add_btn.setIconName("list-add-symbolic");
        add_btn.setTooltipText("Add Alias");
        _ = add_btn.connectClicked(&onAddAlias, self);
        priv.add_btn = add_btn;

        // Create list view
        const factory = gtk.SignalListItemFactory.new();
        factory.connectSetup(&setupAliasItem, null);
        factory.connectBind(&bindAliasItem, null);

        const selection = gtk.SingleSelection.new(store.as(gio.ListModel));
        const list_view = gtk.ListView.new(selection.as(gtk.SelectionModel), factory);
        list_view.setSingleClickActivate(true);
        _ = list_view.connectActivate(&onAliasActivated, self);
        priv.aliases_list = list_view;

        // Create scrolled window
        const scrolled = gtk.ScrolledWindow.new();
        scrolled.setChild(list_view.as(gtk.Widget));
        scrolled.setVexpand(true);

        // Create header bar
        const header = adw.HeaderBar.new();
        header.setTitleWidget(gtk.Label.new("Command Aliases"));
        header.packStart(search_entry.as(gtk.Widget));
        header.packStart(shell_dropdown.as(gtk.Widget));
        header.packEnd(add_btn.as(gtk.Widget));

        // Create main page
        const page = adw.PreferencesPage.new();
        page.setIconName("terminal-symbolic");
        page.setTitle("Aliases");

        const group = adw.PreferencesGroup.new();
        group.setTitle("Shell Aliases");
        group.setDescription("Manage command aliases for your shell");
        group.add(scrolled.as(gtk.Widget));

        page.add(group.as(gtk.Widget));
        self.as(adw.PreferencesWindow).add(page.as(gtk.Widget));

        // Load aliases
        loadAliases(self);
    }

    fn setupAliasItem(_: *gtk.SignalListItemFactory, item: *gtk.ListItem, _: ?*anyopaque) callconv(.c) void {
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

        const command_label = gtk.Label.new("");
        command_label.setXalign(0);
        command_label.addCssClass("monospace");
        command_label.addCssClass("dim-label");
        command_label.setSelectable(true);

        const meta_label = gtk.Label.new("");
        meta_label.setXalign(0);
        meta_label.addCssClass("caption");
        meta_label.addCssClass("dim-label");

        info_box.append(name_label.as(gtk.Widget));
        info_box.append(command_label.as(gtk.Widget));
        info_box.append(meta_label.as(gtk.Widget));

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
        _ = toggle.connectNotify("active", &onToggleAliasListItem, item);
        _ = edit_btn.connectClicked(&onEditAliasListItem, item);
        _ = delete_btn.connectClicked(&onDeleteAliasListItem, item);
    }

    fn bindAliasItem(_: *gtk.SignalListItemFactory, item: *gtk.ListItem, _: ?*anyopaque) callconv(.c) void {
        const entry = item.getItem() orelse return;
        const alias_item = @as(*AliasItem, @ptrCast(entry));
        const box = item.getChild() orelse return;
        const box_widget = box.as(gtk.Box);

        if (box_widget.getFirstChild()) |toggle| {
            toggle.as(gtk.Switch).setActive(alias_item.enabled);
            if (toggle.getNextSibling()) |info_box| {
                if (info_box.as(gtk.Box).getFirstChild()) |name| {
                    name.as(gtk.Label).setText(alias_item.name);
                    if (name.getNextSibling()) |command| {
                        command.as(gtk.Label).setText(alias_item.command);
                        if (command.getNextSibling()) |meta| {
                            var meta_buf: [256]u8 = undefined;
                            const meta_text = if (alias_item.description) |desc|
                                std.fmt.bufPrintZ(&meta_buf, "{s} • {s}", .{ alias_item.shell, desc }) catch alias_item.shell
                            else
                                alias_item.shell;
                            meta.as(gtk.Label).setText(meta_text);
                        }
                    }
                }
            }
        }
    }

    fn onToggleAliasListItem(_: *gobject.Object, _: glib.ParamSpec, list_item: *gtk.ListItem) callconv(.c) void {
        const entry = list_item.getItem() orelse return;
        const alias_item = @as(*AliasItem, @ptrCast(@alignCast(entry)));
        // Get toggle state from widget
        const box = list_item.getChild() orelse return;
        if (box.as(gtk.Box).getFirstChild()) |toggle| {
            alias_item.enabled = toggle.as(gtk.Switch).getActive();
        }
        // TODO: Save aliases when toggle changes
        log.info("Alias toggled: {s} enabled={}", .{ alias_item.name, alias_item.enabled });
    }

    fn onEditAliasListItem(_: *gtk.Button, list_item: *gtk.ListItem) callconv(.c) void {
        const entry = list_item.getItem() orelse return;
        const alias_item = @as(*AliasItem, @ptrCast(@alignCast(entry)));
        onEditAlias(null, alias_item);
    }

    fn onDeleteAliasListItem(_: *gtk.Button, list_item: *gtk.ListItem) callconv(.c) void {
        const entry = list_item.getItem() orelse return;
        const alias_item = @as(*AliasItem, @ptrCast(@alignCast(entry)));
        onDeleteAliasFromItem(alias_item);
    }

    fn onSearchChanged(entry: *gtk.SearchEntry, self: *Self) callconv(.c) void {
        _ = entry;
        _ = self;
        // TODO: Implement search filtering
    }

    fn onShellChanged(_: *gobject.Object, _: glib.ParamSpec, self: *Self) callconv(.c) void {
        _ = self;
        // TODO: Implement shell filtering
    }

    fn onAliasActivated(_: *gtk.ListView, position: u32, self: *Self) callconv(.c) void {
        const priv = getPriv(self);
        if (priv.aliases_store) |store| {
            if (store.getItem(position)) |item| {
                const alias_item: *AliasItem = @ptrCast(@alignCast(item));
                // TODO: Show edit dialog
                log.info("Alias activated: {s}", .{alias_item.name});
            }
        }
    }

    fn onEditAlias(_: ?*gtk.Button, alias_item: *AliasItem) callconv(.c) void {
        // TODO: Show edit dialog
        log.info("Edit alias: {s}", .{alias_item.name});
    }

    fn onDeleteAliasFromItem(alias_item: *AliasItem) void {
        // TODO: Find parent dialog and remove from store
        // For now just log the intent - proper implementation needs dialog reference
        log.info("Delete alias: {s}", .{alias_item.name});
    }

    fn onAddAlias(_: *gtk.Button, _: *Self) callconv(.c) void {
        // TODO: Show dialog to add new alias
        log.info("Add alias clicked", .{});
    }

    fn loadAliases(self: *Self) void {
        const alloc = Application.default().allocator();
        const filepath = persistence.getDataFilePath(alloc, "aliases.json") catch |err| {
            log.err("Failed to get aliases file path: {}", .{err});
            // Load example aliases as fallback
            const priv = getPriv(self);
            const ll = AliasItem.new(alloc, "ll", "ls -la", "bash", "List all files") catch return;
            if (priv.aliases_store) |store| {
                store.append(ll.as(gobject.Object));
            }
            const gst = AliasItem.new(alloc, "gst", "git status", "bash", "Git status") catch return;
            if (priv.aliases_store) |store| {
                store.append(gst.as(gobject.Object));
            }
            return;
        };
        defer alloc.free(filepath);

        const AliasesData = struct {
            aliases: []const struct {
                name: []const u8,
                command: []const u8,
                shell: []const u8,
                description: ?[]const u8 = null,
                enabled: bool = true,
            } = &.{},
        };

        const data = persistence.loadJson(AliasesData, alloc, filepath) catch |err| {
            log.err("Failed to load aliases: {}", .{err});
            // Load example aliases as fallback
            const priv = getPriv(self);
            const ll = AliasItem.new(alloc, "ll", "ls -la", "bash", "List all files") catch return;
            if (priv.aliases_store) |store| {
                store.append(ll.as(gobject.Object));
            }
            const gst = AliasItem.new(alloc, "gst", "git status", "bash", "Git status") catch return;
            if (priv.aliases_store) |store| {
                store.append(gst.as(gobject.Object));
            }
            return;
        };
        defer alloc.free(data.aliases);

        for (data.aliases) |alias| {
            self.addAlias(alias.name, alias.command, alias.shell, alias.description) catch continue;
        }
    }

    fn saveAliases(self: *Self) void {
        const priv = getPriv(self);
        const alloc = Application.default().allocator();

        const filepath = persistence.getDataFilePath(alloc, "aliases.json") catch |err| {
            log.err("Failed to get aliases file path: {}", .{err});
            return;
        };
        defer alloc.free(filepath);

        const AliasesData = struct {
            aliases: []const struct {
                name: []const u8,
                command: []const u8,
                shell: []const u8,
                description: ?[]const u8,
                enabled: bool,
            },
        };

        if (priv.aliases_store) |store| {
            const n = store.getNItems();
            var aliases_list = std.ArrayList(struct {
                name: []const u8,
                command: []const u8,
                shell: []const u8,
                description: ?[]const u8,
                enabled: bool,
            }).init(alloc);
            defer aliases_list.deinit();

            var i: u32 = 0;
            while (i < n) : (i += 1) {
                if (store.getItem(i)) |item| {
                    const alias_item: *AliasItem = @ptrCast(@alignCast(item));
                    aliases_list.append(.{
                        .name = alias_item.name,
                        .command = alias_item.command,
                        .shell = alias_item.shell,
                        .description = alias_item.description,
                        .enabled = alias_item.enabled,
                    }) catch continue;
                }
            }

            const data = AliasesData{ .aliases = aliases_list.toOwnedSlice() catch |err| {
                log.err("Failed to convert aliases list: {}", .{err});
                return;
            } };
            defer alloc.free(data.aliases);

            persistence.saveJson(alloc, filepath, data) catch |err| {
                log.err("Failed to save aliases: {}", .{err});
            };
        }
    }

    pub fn addAlias(self: *Self, name: []const u8, command: []const u8, shell: []const u8, description: ?[]const u8) !void {
        const priv = getPriv(self);
        const alloc = Application.default().allocator();

        const alias = try AliasItem.new(alloc, name, command, shell, description);
        if (priv.aliases_store) |store| {
            store.append(alias.as(gobject.Object));
        }
        saveAliases(self);
    }

    pub fn show(self: *Self, parent: *Window) void {
        self.as(adw.PreferencesWindow).setTransientFor(parent.as(gtk.Window));
        self.as(adw.PreferencesWindow).present();
    }
};
