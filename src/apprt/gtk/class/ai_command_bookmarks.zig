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
const persistence = @import("ai_persistence.zig");

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
                    alloc.free(self.tags);
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

        pub fn addTag(self: *BookmarkItem, alloc: Allocator, tag: []const u8) !void {
            // Allocate the new tag string first (separate to handle errdefer)
            const new_tag = try alloc.dupeZ(u8, tag);
            errdefer alloc.free(new_tag);

            // Allocate new array - use alloc.alloc instead of realloc to avoid
            // undefined behavior when self.tags is empty (&.{})
            const new_tags = try alloc.alloc([:0]const u8, self.tags.len + 1);

            // Copy existing tags
            @memcpy(new_tags[0..self.tags.len], self.tags);

            // Add new tag at the end
            new_tags[self.tags.len] = new_tag;

            // Free old array if it was allocated (not the empty slice sentinel)
            if (self.tags.len > 0) {
                alloc.free(self.tags);
            }

            self.tags = new_tags;
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

            // Clean up all bookmark items - just removeAll, GObject dispose handles item cleanup
            if (priv.bookmarks_store) |store| {
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
        return self.refSink();
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

        const selection = gtk.SingleSelection.new(store.as(gio.ListModel));
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

        // Connect signal handlers once during setup to prevent leaks on rebind
        _ = use_btn.connectClicked(&onUseBookmarkListItem, item);
        _ = delete_btn.connectClicked(&onDeleteBookmarkListItem, item);
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
            }
        }
    }

    fn onSearchChanged(entry: *gtk.SearchEntry, self: *Self) callconv(.c) void {
        const priv = getPriv(self);
        const query = entry.getText();
        if (priv.bookmarks_store) |store| {
            const n = store.getNItems();
            var i: u32 = 0;
            while (i < n) : (i += 1) {
                if (store.getItem(i)) |item| {
                    const bookmark_item: *BookmarkItem = @ptrCast(@alignCast(item));
                    const matches = if (query.len == 0) true else blk: {
                        const name_match = std.mem.indexOf(u8, bookmark_item.name, query) != null;
                        const cmd_match = std.mem.indexOf(u8, bookmark_item.command, query) != null;
                        const desc_match = if (bookmark_item.description) |desc|
                            std.mem.indexOf(u8, desc, query) != null
                        else
                            false;
                        const cat_match = if (bookmark_item.category) |cat|
                            std.mem.indexOf(u8, cat, query) != null
                        else
                            false;
                        break :blk name_match or cmd_match or desc_match or cat_match;
                    };
                    // TODO: Use FilterListModel for proper filtering
                    _ = matches;
                }
            }
        }
    }

    fn onAddBookmark(_: *gtk.Button, self: *Self) callconv(.c) void {
        const parent = self.as(adw.PreferencesWindow).getTransientFor() orelse return;

        const dialog = adw.MessageDialog.new(parent.as(gtk.Window), "Add Bookmark", null);
        dialog.setBody("Enter bookmark details");
        dialog.addResponse("cancel", "Cancel");
        dialog.addResponse("add", "Add");
        dialog.setDefaultResponse("add");
        dialog.setCloseResponse("cancel");

        const content_area = dialog.getChild();
        const content_box = content_area.as(gtk.Box);

        const name_entry = gtk.Entry.new();
        name_entry.setPlaceholderText("Bookmark name");
        name_entry.setHexpand(true);

        const command_entry = gtk.Entry.new();
        command_entry.setPlaceholderText("Command");
        command_entry.setHexpand(true);

        const desc_entry = gtk.Entry.new();
        desc_entry.setPlaceholderText("Description (optional)");
        desc_entry.setHexpand(true);

        const cat_entry = gtk.Entry.new();
        cat_entry.setPlaceholderText("Category (optional)");
        cat_entry.setHexpand(true);

        const form_box = gtk.Box.new(gtk.Orientation.vertical, 12);
        form_box.append(gtk.Label.new("Name:").as(gtk.Widget));
        form_box.append(name_entry.as(gtk.Widget));
        form_box.append(gtk.Label.new("Command:").as(gtk.Widget));
        form_box.append(command_entry.as(gtk.Widget));
        form_box.append(gtk.Label.new("Description:").as(gtk.Widget));
        form_box.append(desc_entry.as(gtk.Widget));
        form_box.append(gtk.Label.new("Category:").as(gtk.Widget));
        form_box.append(cat_entry.as(gtk.Widget));

        content_box.append(form_box.as(gtk.Widget));

        _ = dialog.connectResponse(&onAddBookmarkResponse, .{ .self = self, .name_entry = name_entry, .command_entry = command_entry, .desc_entry = desc_entry, .cat_entry = cat_entry });
        dialog.present();
    }

    fn onAddBookmarkResponse(dialog: *adw.MessageDialog, response: [:0]const u8, data: struct { self: *Self, name_entry: *gtk.Entry, command_entry: *gtk.Entry, desc_entry: *gtk.Entry, cat_entry: *gtk.Entry }) callconv(.c) void {
        if (!std.mem.eql(u8, response, "add")) {
            dialog.close();
            return;
        }

        const name = data.name_entry.getText();
        const command = data.command_entry.getText();
        if (name.len == 0 or command.len == 0) {
            dialog.close();
            return;
        }

        const desc = data.desc_entry.getText();
        const cat = data.cat_entry.getText();

        const desc_opt = if (desc.len > 0) desc else null;
        const cat_opt = if (cat.len > 0) cat else null;

        data.self.addBookmark(name, command, desc_opt, cat_opt) catch |err| {
            log.err("Failed to add bookmark: {}", .{err});
        };

        dialog.close();
    }

    fn onBookmarkActivated(_: *gtk.ListView, position: u32, self: *Self) callconv(.c) void {
        if (getPriv(self).bookmarks_store) |store| {
            if (store.getItem(position)) |item| {
                const bookmark_item: *BookmarkItem = @ptrCast(@alignCast(item));
                bookmark_item.incrementUse();
                const clipboard = self.as(adw.PreferencesWindow).as(gtk.Widget).getClipboard();
                clipboard.setText(bookmark_item.command);
                log.info("Copied to clipboard: {s}", .{bookmark_item.command});
            }
        }
    }

    fn onUseBookmarkListItem(_: *gtk.Button, list_item: *gtk.ListItem) callconv(.c) void {
        const entry = list_item.getItem() orelse return;
        const bookmark_item = @as(*BookmarkItem, @ptrCast(@alignCast(entry)));
        bookmark_item.incrementUse();
        // Get parent dialog from list item's widget tree
        if (list_item.getChild()) |child| {
            if (child.as(gtk.Widget).getRoot()) |root| {
                if (root.as(gtk.Window).getTransientFor()) |transient| {
                    const clipboard = transient.as(gtk.Widget).getClipboard();
                    clipboard.setText(bookmark_item.command);
                    log.info("Copied to clipboard: {s}", .{bookmark_item.command});
                }
            }
        }
    }

    fn onDeleteBookmarkListItem(_: *gtk.Button, list_item: *gtk.ListItem) callconv(.c) void {
        const entry = list_item.getItem() orelse return;
        const bookmark_item = @as(*BookmarkItem, @ptrCast(@alignCast(entry)));
        // Find the dialog that owns this item
        if (list_item.getChild()) |child| {
            if (child.as(gtk.Widget).getRoot()) |root| {
                if (root.as(gtk.Window).getTransientFor()) |transient| {
                    // Find the dialog
                    var current: ?*gtk.Widget = transient.as(gtk.Widget);
                    while (current) |widget| {
                        if (widget.getType() == Self.getGObjectType()) {
                            const self = @as(*Self, @ptrCast(@alignCast(widget)));
                            const priv = getPriv(self);
                            if (priv.bookmarks_store) |store| {
                                const n = store.getNItems();
                                var i: u32 = 0;
                                while (i < n) : (i += 1) {
                                    if (store.getItem(i)) |item| {
                                        if (item == bookmark_item.as(gobject.Object)) {
                                            // Remove from store - GObject dispose handles cleanup
                                            store.remove(i);
                                            self.saveBookmarks();
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
        }
    }

    fn loadBookmarks(self: *Self) void {
        const alloc = Application.default().allocator();
        const filepath = persistence.getDataFilePath(alloc, "bookmarks.json") catch |err| {
            log.err("Failed to get bookmarks file path: {}", .{err});
            // Load example bookmarks as fallback
            self.addBookmark("Git Status", "git status", "Check git repository status", "Git") catch {};
            self.addBookmark("Docker PS", "docker ps -a", "List all Docker containers", "Docker") catch {};
            return;
        };
        defer alloc.free(filepath);

        const BookmarksData = struct {
            bookmarks: []const struct {
                name: []const u8,
                command: []const u8,
                description: ?[]const u8 = null,
                category: ?[]const u8 = null,
                use_count: u32 = 0,
                created_at: i64 = 0,
            } = &.{},
        };

        const data = persistence.loadJson(BookmarksData, alloc, filepath) catch |err| {
            log.err("Failed to load bookmarks: {}", .{err});
            // Load example bookmarks as fallback
            self.addBookmark("Git Status", "git status", "Check git repository status", "Git") catch {};
            self.addBookmark("Docker PS", "docker ps -a", "List all Docker containers", "Docker") catch {};
            return;
        };
        defer alloc.free(data.bookmarks);

        for (data.bookmarks) |bm| {
            self.addBookmark(bm.name, bm.command, bm.description, bm.category) catch continue;
        }
    }

    fn saveBookmarks(self: *Self) void {
        const priv = getPriv(self);
        const alloc = Application.default().allocator();

        const filepath = persistence.getDataFilePath(alloc, "bookmarks.json") catch |err| {
            log.err("Failed to get bookmarks file path: {}", .{err});
            return;
        };
        defer alloc.free(filepath);

        const BookmarksData = struct {
            bookmarks: []const struct {
                name: []const u8,
                command: []const u8,
                description: ?[]const u8,
                category: ?[]const u8,
                use_count: u32,
                created_at: i64,
            },
        };

        if (priv.bookmarks_store) |store| {
            const n = store.getNItems();
            var bookmarks_list = std.ArrayList(struct {
                name: []const u8,
                command: []const u8,
                description: ?[]const u8,
                category: ?[]const u8,
                use_count: u32,
                created_at: i64,
            }).init(alloc);
            defer bookmarks_list.deinit();

            var i: u32 = 0;
            while (i < n) : (i += 1) {
                if (store.getItem(i)) |item| {
                    const bookmark_item: *BookmarkItem = @ptrCast(@alignCast(item));
                    bookmarks_list.append(.{
                        .name = bookmark_item.name,
                        .command = bookmark_item.command,
                        .description = bookmark_item.description,
                        .category = bookmark_item.category,
                        .use_count = bookmark_item.use_count,
                        .created_at = bookmark_item.created_at,
                    }) catch continue;
                }
            }

            const data = BookmarksData{ .bookmarks = bookmarks_list.toOwnedSlice() catch |err| {
                log.err("Failed to convert bookmarks list: {}", .{err});
                return;
            } };
            defer alloc.free(data.bookmarks);

            persistence.saveJson(alloc, filepath, data) catch |err| {
                log.err("Failed to save bookmarks: {}", .{err});
            };
        }
    }

    pub fn addBookmark(self: *Self, name: []const u8, command: []const u8, description: ?[]const u8, category: ?[]const u8) !void {
        const priv = getPriv(self);
        const alloc = Application.default().allocator();

        const bookmark = try BookmarkItem.new(alloc, name, command, description, category);
        if (priv.bookmarks_store) |store| {
            store.append(bookmark.as(gobject.Object));
        }
        saveBookmarks(self);
    }

    pub fn show(self: *Self, parent: *Window) void {
        self.as(adw.PreferencesWindow).setTransientFor(parent.as(gtk.Window));
        self.as(adw.PreferencesWindow).present();
    }
};
