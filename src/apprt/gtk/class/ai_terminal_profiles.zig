//! Terminal Profiles Manager UI
//! Provides Warp-like UI for managing terminal profiles/configurations

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

const log = std.log.scoped(.gtk_ghostty_terminal_profiles);

pub const TerminalProfilesDialog = extern struct {
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
        profiles_list: ?*gtk.ListView = null,
        profiles_store: ?*gio.ListStore = null,
        new_profile_btn: ?*gtk.Button = null,
        search_entry: ?*gtk.SearchEntry = null,
        pub var offset: c_int = 0;
    };

    pub const ProfileItem = extern struct {
        parent_instance: gobject.Object,
        id: [:0]const u8,
        name: [:0]const u8,
        description: ?[:0]const u8 = null,
        shell: [:0]const u8,
        theme: ?[:0]const u8 = null,
        font: ?[:0]const u8 = null,
        is_default: bool = false,

        pub const Parent = gobject.Object;

        pub const ItemClass = extern struct {
            parent_class: gobject.Object.Class,
            var parent: *gobject.Object.Class = undefined;

            fn init(class: *ItemClass) callconv(.c) void {
                gobject.Object.virtual_methods.dispose.implement(class, &ProfileItem.dispose);
            }

            fn dispose(self: *ProfileItem) callconv(.c) void {
                const alloc = Application.default().allocator();
                alloc.free(self.id);
                alloc.free(self.name);
                if (self.description) |desc| alloc.free(desc);
                alloc.free(self.shell);
                if (self.theme) |th| alloc.free(th);
                if (self.font) |f| alloc.free(f);
                gobject.Object.virtual_methods.dispose.call(ItemClass.parent, self);
            }
        };

        pub const getGObjectType = gobject.ext.defineClass(ProfileItem, .{
            .name = "GhosttyProfileItem",
            .classInit = &ItemClass.init,
            .parent_class = &ItemClass.parent,
        });

        pub fn new(alloc: Allocator, id: []const u8, name: []const u8, shell: []const u8) !*ProfileItem {
            const self = gobject.ext.newInstance(ProfileItem, .{});
            self.id = try alloc.dupeZ(u8, id);
            errdefer alloc.free(self.id);
            self.name = try alloc.dupeZ(u8, name);
            errdefer alloc.free(self.name);
            self.shell = try alloc.dupeZ(u8, shell);
            errdefer alloc.free(self.shell);
            return self;
        }

        pub fn deinit(self: *ProfileItem, alloc: Allocator) void {
            alloc.free(self.id);
            alloc.free(self.name);
            if (self.description) |desc| alloc.free(desc);
            alloc.free(self.shell);
            if (self.theme) |th| alloc.free(th);
            if (self.font) |f| alloc.free(f);
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
            if (priv.profiles_store) |store| {
                store.removeAll();
            }
            gobject.Object.virtual_methods.dispose.call(Class.parent, self.as(Parent));
        }

        pub const as = C.Class.as;
    };

    pub const getGObjectType = gobject.ext.defineClass(Self, .{
        .name = "GhosttyTerminalProfilesDialog",
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
        self.as(adw.PreferencesWindow).setTitle("Terminal Profiles");

        // Create profiles store
        const store = gio.ListStore.new(ProfileItem.getGObjectType());
        priv.profiles_store = store;

        // Create search entry
        const search_entry = gtk.SearchEntry.new();
        search_entry.setPlaceholderText("Search profiles...");
        _ = search_entry.connectSearchChanged(&onSearchChanged, self);
        priv.search_entry = search_entry;

        // Create new profile button
        const new_profile_btn = gtk.Button.new();
        new_profile_btn.setIconName("list-add-symbolic");
        new_profile_btn.setLabel("New Profile");
        new_profile_btn.setTooltipText("Create New Profile");
        new_profile_btn.addCssClass("suggested-action");
        _ = new_profile_btn.connectClicked(&onNewProfile, self);
        priv.new_profile_btn = new_profile_btn;

        // Create list view
        const factory = gtk.SignalListItemFactory.new();
        factory.connectSetup(&setupProfileItem, null);
        factory.connectBind(&bindProfileItem, null);

        const selection = gtk.SingleSelection.new(store.as(gio.ListModel));
        const list_view = gtk.ListView.new(selection.as(gtk.SelectionModel), factory);
        list_view.setSingleClickActivate(true);
        _ = list_view.connectActivate(&onProfileActivated, self);
        priv.profiles_list = list_view;

        // Create scrolled window
        const scrolled = gtk.ScrolledWindow.new();
        scrolled.setChild(list_view.as(gtk.Widget));
        scrolled.setVexpand(true);

        // Create header bar
        const header = adw.HeaderBar.new();
        header.setTitleWidget(gtk.Label.new("Terminal Profiles"));
        header.packStart(search_entry.as(gtk.Widget));
        header.packEnd(new_profile_btn.as(gtk.Widget));

        // Create main page
        const page = adw.PreferencesPage.new();
        page.setIconName("preferences-system-symbolic");
        page.setTitle("Profiles");

        const group = adw.PreferencesGroup.new();
        group.setTitle("Terminal Profiles");
        group.setDescription("Manage terminal profiles and configurations");
        group.add(scrolled.as(gtk.Widget));

        page.add(group.as(gtk.Widget));
        self.as(adw.PreferencesWindow).add(page.as(gtk.Widget));

        // Load profiles
        loadProfiles(self);
    }

    fn setupProfileItem(_: *gtk.SignalListItemFactory, item: *gtk.ListItem, _: ?*anyopaque) callconv(.c) void {
        const box = gtk.Box.new(gtk.Orientation.horizontal, 12);
        box.setMarginStart(12);
        box.setMarginEnd(12);
        box.setMarginTop(6);
        box.setMarginBottom(6);

        const icon = gtk.Image.new();
        icon.setIconName("terminal-symbolic");
        icon.setIconSize(gtk.IconSize.large);

        const info_box = gtk.Box.new(gtk.Orientation.vertical, 4);
        info_box.setHexpand(true);
        info_box.setHalign(gtk.Align.start);

        const name_label = gtk.Label.new("");
        name_label.setXalign(0);
        name_label.addCssClass("title-4");

        const desc_label = gtk.Label.new("");
        desc_label.setXalign(0);
        desc_label.addCssClass("dim-label");
        desc_label.setWrap(true);

        const meta_label = gtk.Label.new("");
        meta_label.setXalign(0);
        meta_label.addCssClass("caption");
        meta_label.addCssClass("dim-label");

        info_box.append(name_label.as(gtk.Widget));
        info_box.append(desc_label.as(gtk.Widget));
        info_box.append(meta_label.as(gtk.Widget));

        const action_box = gtk.Box.new(gtk.Orientation.horizontal, 4);
        const edit_btn = gtk.Button.new();
        edit_btn.setIconName("document-edit-symbolic");
        edit_btn.setTooltipText("Edit");
        edit_btn.addCssClass("circular");
        edit_btn.addCssClass("flat");

        const duplicate_btn = gtk.Button.new();
        duplicate_btn.setIconName("edit-copy-symbolic");
        duplicate_btn.setTooltipText("Duplicate");
        duplicate_btn.addCssClass("circular");
        duplicate_btn.addCssClass("flat");

        const delete_btn = gtk.Button.new();
        delete_btn.setIconName("user-trash-symbolic");
        delete_btn.setTooltipText("Delete");
        delete_btn.addCssClass("circular");
        delete_btn.addCssClass("flat");
        delete_btn.addCssClass("destructive-action");

        action_box.append(edit_btn.as(gtk.Widget));
        action_box.append(duplicate_btn.as(gtk.Widget));
        action_box.append(delete_btn.as(gtk.Widget));

        box.append(icon.as(gtk.Widget));
        box.append(info_box.as(gtk.Widget));
        box.append(action_box.as(gtk.Widget));

        item.setChild(box.as(gtk.Widget));

        // Connect signal handlers once during setup
        _ = edit_btn.connectClicked(&onEditProfileListItem, item);
        _ = duplicate_btn.connectClicked(&onDuplicateProfileListItem, item);
        _ = delete_btn.connectClicked(&onDeleteProfileListItem, item);
    }

    fn bindProfileItem(_: *gtk.SignalListItemFactory, item: *gtk.ListItem, _: ?*anyopaque) callconv(.c) void {
        const entry = item.getItem() orelse return;
        const profile_item = @as(*ProfileItem, @ptrCast(@alignCast(entry)));
        const box = item.getChild() orelse return;
        const box_widget = box.as(gtk.Box);

        if (box_widget.getFirstChild()) |icon| {
            if (icon.getNextSibling()) |info_box| {
                if (info_box.as(gtk.Box).getFirstChild()) |name| {
                    name.as(gtk.Label).setText(profile_item.name);
                    if (name.getNextSibling()) |desc| {
                        const desc_text = if (profile_item.description) |d| d else "No description";
                        desc.as(gtk.Label).setText(desc_text);
                        if (desc.getNextSibling()) |meta| {
                            var meta_buf: [256]u8 = undefined;
                            const meta_text = std.fmt.bufPrintZ(&meta_buf, "{s} • {s}", .{ profile_item.shell, if (profile_item.is_default) "Default" else "Profile" }) catch "Profile";
                            meta.as(gtk.Label).setText(meta_text);
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

    fn onNewProfile(_: *gtk.Button, self: *Self) callconv(.c) void {
        _ = self;
        // TODO: Show dialog to create new profile
        log.info("New profile clicked", .{});
    }

    fn onProfileActivated(_: *gtk.ListView, position: u32, self: *Self) callconv(.c) void {
        const priv = getPriv(self);
        if (priv.profiles_store) |store| {
            if (store.getItem(position)) |item| {
                const profile_item: *ProfileItem = @ptrCast(@alignCast(item));
                // TODO: Show profile editor
                log.info("Profile activated: {s}", .{profile_item.name});
            }
        }
    }

    fn onEditProfileListItem(_: *gtk.Button, list_item: *gtk.ListItem) callconv(.c) void {
        const entry = list_item.getItem() orelse return;
        const profile_item = @as(*ProfileItem, @ptrCast(@alignCast(entry)));
        // TODO: Show edit dialog
        log.info("Edit profile: {s}", .{profile_item.name});
    }

    fn onDuplicateProfileListItem(_: *gtk.Button, list_item: *gtk.ListItem) callconv(.c) void {
        const entry = list_item.getItem() orelse return;
        const profile_item = @as(*ProfileItem, @ptrCast(@alignCast(entry)));
        // TODO: Duplicate profile
        log.info("Duplicate profile: {s}", .{profile_item.name});
    }

    fn onDeleteProfileListItem(_: *gtk.Button, list_item: *gtk.ListItem) callconv(.c) void {
        const entry = list_item.getItem() orelse return;
        const profile_item = @as(*ProfileItem, @ptrCast(@alignCast(entry)));
        // TODO: Delete profile
        log.info("Delete profile: {s}", .{profile_item.name});
    }

    fn loadProfiles(_: *Self) void {
        // TODO: Load profiles from configuration
        log.info("Loading profiles...", .{});
    }

    pub fn show(self: *Self, parent: *Window) void {
        self.as(adw.PreferencesWindow).setTransientFor(parent.as(gtk.Window));
        self.as(adw.PreferencesWindow).present();
    }
};
