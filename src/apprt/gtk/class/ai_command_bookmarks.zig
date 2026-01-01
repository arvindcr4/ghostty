//! Command Bookmarks UI
//! Provides Warp-like command bookmarks for saving and managing frequently used commands

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

const log = std.log.scoped(.gtk_ghostty_command_bookmarks);

pub const CommandBookmarksDialog = extern struct {
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
        bookmarks_list: ?*gtk.ListView = null,
        bookmarks_store: ?*gio.ListStore = null,
        search_entry: ?*gtk.SearchEntry = null,
        add_btn: ?*gtk.Button = null,
        pub var offset: c_int = 0;
    };

    pub const BookmarkItem = extern struct {
        parent_instance: gobject.Object,
        name: [:0]const u8,
        command: [:0]const u8,
        description: ?[:0]const u8 = null,
        category: ?[:0]const u8 = null,
        tags: []const [:0]const u8 = &.{},
        created_at: i64,
        last_used: ?i64 = null,
        use_count: u32 = 0,

        pub const Parent = gobject.Object;

        pub const ItemClass = extern struct {
            parent_class: gobject.Object.Class,
            var parent: *gobject.Object.Class = undefined;

            fn init(class: *ItemClass) callconv(.c) void {
                gobject.Object.virtual_methods.dispose.implement(class, &BookmarkItem.dispose);
            }

            fn dispose(self: *BookmarkItem) callconv(.c) void {
                const alloc = Application.default().allocator();
                alloc.free(self.name);
                alloc.free(self.command);
                if (self.description) |desc| alloc.free(desc);
                if (self.category) |cat| alloc.free(cat);
                for (self.tags) |tag| alloc.free(tag);
                if (self.tags.len > 0) {
                    alloc.free(self.tags.ptr);
                }
                gobject.Object.virtual_methods.dispose.call(ItemClass.parent, self);
            }
        };

        pub const getGObjectType = gobject.ext.defineClass(BookmarkItem, .{
            .name = "GhosttyBookmarkItem",
            .classInit = &ItemClass.init,
            .parent_class = &ItemClass.parent,
        });

        pub fn new(alloc: Allocator, name: []const u8, command: []const u8, description: ?[]const u8, category: ?[]const u8) !*BookmarkItem {
            const self = gobject.ext.newInstance(BookmarkItem, .{});
            self.name = try alloc.dupeZ(u8, name);
            errdefer alloc.free(self.name);
            self.command = try alloc.dupeZ(u8, command);
            errdefer alloc.free(self.command);
            if (description) |desc| {
                self.description = try alloc.dupeZ(u8, desc);
                errdefer alloc.free(self.description.?);
            }
            if (category) |cat| {
                self.category = try alloc.dupeZ(u8, cat);
                errdefer alloc.free(self.category.?);
            }
            self.created_at = std.time.timestamp();
            return self;
        }

        pub fn deinit(self: *BookmarkItem, alloc: Allocator) void {
            alloc.free(self.name);
            alloc.free(self.command);
            if (self.description) |desc| alloc.free(desc);
            if (self.category) |cat| alloc.free(cat);
            for (self.tags) |tag| alloc.free(tag);
            if (self.tags.len > 0) {
                alloc.free(self.tags.ptr);
            }
        }

        pub fn addTag(self: *BookmarkItem, alloc: Allocator, tag: []const u8) !void {
            const new_tags = try alloc.realloc(self.tags.ptr, self.tags.len + 1);
            new_tags[self.tags.len] = try alloc.dupeZ(u8, tag);
            self.tags = new_tags[0..self.tags.len + 1];
        }

        pub fn incrementUse(self: *BookmarkItem) void {
            self.use_count += 1;
            self.last_used = std.time.timestamp();
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

            // Clean up all bookmark items in the store to prevent memory leaks.
            // We must: (1) deinit internal allocations, (2) clear store to release refs.
            // This prevents double-free when GObject finalizes the store.
            if (priv.bookmarks_store) |store| {
                const n = store.getNItems();
                var i: u32 = 0;
                while (i < n) : (i += 1) {
                    if (store.getItem(i)) |item| {
                        const bookmark_item: *BookmarkItem = @ptrCast(@alignCast(item));
                        bookmark_item.deinit(alloc);
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
        .name = "GhosttyCommandBookmarksDialog",
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
        self.as(adw.PreferencesWindow).setTitle("Command Bookmarks");

        // Create bookmarks store
        const store = gio.ListStore.new(BookmarkItem.getGObjectType());
        priv.bookmarks_store = store;

        // Create search entry
        const search_entry = gtk.SearchEntry.new();
        search_entry.setPlaceholderText("Search bookmarks...");
        _ = search_entry.connectTextChanged(&onSearchChanged, self);
        priv.search_entry = search_entry;

        // Create add button
        const add_btn = gtk.Button.new();
        add_btn.setIconName("list-add-symbolic");
        add_btn.setTooltipText("Add Bookmark");
        _ = add_btn.connectClicked(&onAddBookmark, self);
        priv.add_btn = add_btn;

        // Create list view
        const factory = gtk.SignalListItemFactory.new();
        factory.connectSetup(&setupBookmarkItem, null);
        factory.connectBind(&bindBookmarkItem, null);

        const selection = gtk.SingleSelection.new(store.as(gobject.Object));
        const list_view = gtk.ListView.new(selection.as(gtk.SelectionModel), factory);
        list_view.setSingleClickActivate(true);
        _ = list_view.connectActivate(&onBookmarkActivated, self);
        priv.bookmarks_list = list_view;

        // Create scrolled window
        const scrolled = gtk.ScrolledWindow.new();
        scrolled.setChild(list_view.as(gtk.Widget));
        scrolled.setVexpand(true);

        // Create header bar
        const header = adw.HeaderBar.new();
        header.setTitleWidget(gtk.Label.new("Command Bookmarks"));
        header.packStart(search_entry.as(gtk.Widget));
        header.packEnd(add_btn.as(gtk.Widget));

        // Create main page
        const page = adw.PreferencesPage.new();
        page.setIconName("bookmark-symbolic");
        page.setTitle("Bookmarks");

        const group = adw.PreferencesGroup.new();
        group.setTitle("Saved Commands");
        group.setDescription("Manage your frequently used commands");
        group.add(scrolled.as(gtk.Widget));

        page.add(group.as(gtk.Widget));
        self.as(adw.PreferencesWindow).add(page.as(gtk.Widget));

        // Load saved bookmarks
        loadBookmarks(self);
    }

    fn setupBookmarkItem(_: *gtk.SignalListItemFactory, item: *gtk.ListItem, _: ?*anyopaque) callconv(.c) void {
        const box = gtk.Box.new(gtk.Orientation.horizontal, 12);
        box.setMarginStart(12);
        box.setMarginEnd(12);
        box.setMarginTop(6);
        box.setMarginBottom(6);

        const icon = gtk.Image.new();
        icon.setIconName("bookmark-symbolic");
        icon.setIconSize(gtk.IconSize.large);

        const info_box = gtk.Box.new(gtk.Orientation.vertical, 4);
        info_box.setHexpand(true);
        info_box.setHalign(gtk.Align.start);

        const name_label = gtk.Label.new("");
        name_label.setXalign(0);
        name_label.addCssClass("title-4");

        const command_label = gtk.Label.new("");
        command_label.setXalign(0);
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
        const use_btn = gtk.Button.new();
        use_btn.setIconName("media-playback-start-symbolic");
        use_btn.setTooltipText("Use Command");
        use_btn.addCssClass("circular");
        use_btn.addCssClass("flat");

        const delete_btn = gtk.Button.new();
        delete_btn.setIconName("user-trash-symbolic");
        delete_btn.setTooltipText("Delete");
        delete_btn.addCssClass("circular");
        delete_btn.addCssClass("flat");
        delete_btn.addCssClass("destructive-action");

        action_box.append(use_btn.as(gtk.Widget));
        action_box.append(delete_btn.as(gtk.Widget));

        box.append(icon.as(gtk.Widget));
        box.append(info_box.as(gtk.Widget));
        box.append(action_box.as(gtk.Widget));

        item.setChild(box.as(gtk.Widget));
    }

    fn bindBookmarkItem(_: *gtk.SignalListItemFactory, item: *gtk.ListItem, _: ?*anyopaque) callconv(.c) void {
        const entry = item.getItem() orelse return;
        const bookmark_item = @as(*BookmarkItem, @ptrCast(entry));
        const box = item.getChild() orelse return;
        const box_widget = box.as(gtk.Box);

        if (box_widget.getFirstChild()) |icon| {
            if (icon.getNextSibling()) |info_box| {
                if (info_box.as(gtk.Box).getFirstChild()) |name| {
                    name.as(gtk.Label).setText(bookmark_item.name);
                    if (name.getNextSibling()) |command| {
                        command.as(gtk.Label).setText(bookmark_item.command);
                        if (command.getNextSibling()) |meta| {
                            var meta_buf: [256]u8 = undefined;
                            const meta_text = if (bookmark_item.category) |cat|
                                std.fmt.bufPrintZ(&meta_buf, "{s} • Used {d} times", .{ cat, bookmark_item.use_count }) catch "Bookmark"
                            else
                                std.fmt.bufPrintZ(&meta_buf, "Used {d} times", .{bookmark_item.use_count}) catch "Bookmark";
                            meta.as(gtk.Label).setText(meta_text);
                        }
                    }
                }
                if (info_box.getNextSibling()) |action_box| {
                    if (action_box.as(gtk.Box).getFirstChild()) |use_btn| {
                        _ = use_btn.as(gtk.Button).connectClicked(&onUseBookmark, bookmark_item);
                        if (use_btn.getNextSibling()) |delete_btn| {
                            _ = delete_btn.as(gtk.Button).connectClicked(&onDeleteBookmark, bookmark_item);
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

    fn onAddBookmark(_: *gtk.Button, _: *Self) callconv(.c) void {
        // TODO: Show dialog to add new bookmark
        log.info("Add bookmark clicked", .{});
    }

    fn onBookmarkActivated(_: *gtk.ListView, position: u32, self: *Self) callconv(.c) void {
        const priv = getPriv(self);
        if (priv.bookmarks_store) |store| {
            if (store.getItem(position)) |item| {
                const bookmark_item: *BookmarkItem = @ptrCast(@alignCast(item));
                bookmark_item.incrementUse();
                // TODO: Execute command or copy to clipboard
                log.info("Bookmark activated: {s}", .{bookmark_item.command});
            }
        }
    }

    fn onUseBookmark(_: *gtk.Button, bookmark_item: *BookmarkItem) callconv(.c) void {
        bookmark_item.incrementUse();
        // TODO: Execute command or copy to clipboard
        log.info("Use bookmark: {s}", .{bookmark_item.command});
    }

    fn onDeleteBookmark(_: *gtk.Button, bookmark_item: *BookmarkItem) callconv(.c) void {
        // TODO: Remove from store and save
        log.info("Delete bookmark: {s}", .{bookmark_item.name});
    }

    fn loadBookmarks(_: *Self) void {
        // TODO: Load bookmarks from persistent storage
        log.info("Loading bookmarks...", .{});
    }

    pub fn addBookmark(self: *Self, name: []const u8, command: []const u8, description: ?[]const u8, category: ?[]const u8) !void {
        const priv = getPriv(self);
        const alloc = Application.default().allocator();

        const bookmark = try BookmarkItem.new(alloc, name, command, description, category);
        if (priv.bookmarks_store) |store| {
            store.append(bookmark.as(gobject.Object));
        }
        // TODO: Save to persistent storage
    }

    pub fn show(self: *Self, parent: *Window) void {
        self.as(adw.PreferencesWindow).setTransientFor(parent.as(gtk.Window));
        self.as(adw.PreferencesWindow).present();
    }
};
