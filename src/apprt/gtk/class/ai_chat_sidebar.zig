//! AI Chat Sidebar
//! Provides Warp-like persistent AI chat sidebar with conversation history

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

const log = std.log.scoped(.gtk_ghostty_chat_sidebar);

pub const ChatSidebar = extern struct {
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
        chat_list: ?*gtk.ListView = null,
        chat_store: ?*gio.ListStore = null,
        input_entry: ?*gtk.Entry = null,
        send_btn: ?*gtk.Button = null,
        new_chat_btn: ?*gtk.Button = null,

        pub var offset: c_int = 0;
    };

    pub const ChatMessage = extern struct {
        parent_instance: gobject.Object,
        role: MessageRole,
        content: [:0]const u8,
        timestamp: i64,

        pub const Parent = gobject.Object;
        pub const MessageRole = enum {
            user,
            assistant,
            system,
        };

        pub const ItemClass = extern struct {
            parent_class: gobject.Object.Class,
            var parent: *gobject.Object.Class = undefined;

            fn init(class: *ItemClass) callconv(.c) void {
                gobject.Object.virtual_methods.dispose.implement(class, &ChatMessage.dispose);
            }

            fn dispose(self: *ChatMessage) callconv(.c) void {
                const alloc = Application.default().allocator();
                alloc.free(self.content);
                gobject.Object.virtual_methods.dispose.call(ItemClass.parent, self);
            }
        };

        pub const getGObjectType = gobject.ext.defineClass(ChatMessage, .{
            .name = "GhosttyChatMessage",
            .classInit = &ItemClass.init,
            .parent_class = &ItemClass.parent,
        });

        pub fn new(alloc: Allocator, role: MessageRole, content: []const u8) !*ChatMessage {
            const self = gobject.ext.newInstance(ChatMessage, .{});
            self.role = role;
            self.content = try alloc.dupeZ(u8, content);
            errdefer alloc.free(self.content);
            self.timestamp = std.time.timestamp();
            return self;
        }

        pub fn deinit(self: *ChatMessage, alloc: Allocator) void {
            alloc.free(self.content);
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
        .name = "GhosttyChatSidebar",
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

        const page = adw.NavigationPage.new();
        page.setTitle("AI Chat");

        const box = gtk.Box.new(gtk.Orientation.vertical, 12);
        box.setMarginStart(12);
        box.setMarginEnd(12);
        box.setMarginTop(12);
        box.setMarginBottom(12);

        // Header with new chat button
        const header = gtk.Box.new(gtk.Orientation.horizontal, 8);
        const new_chat_btn = gtk.Button.new();
        new_chat_btn.setLabel("New Chat");
        new_chat_btn.setIconName("document-new-symbolic");
        priv.new_chat_btn = new_chat_btn;
        _ = new_chat_btn.connectClicked(&newChat, self);
        header.append(new_chat_btn.as(gtk.Widget));
        box.append(header.as(gtk.Widget));

        // Chat messages list
        const scrolled = gtk.ScrolledWindow.new();
        scrolled.setVexpand(@intFromBool(true));
        scrolled.setPolicy(gtk.PolicyType.never, gtk.PolicyType.automatic);

        const chat_store = gio.ListStore.new(ChatMessage.getGObjectType());
        priv.chat_store = chat_store;

        const selection = gtk.NoSelection.new(chat_store.as(gio.ListModel));
        const factory = gtk.SignalListItemFactory.new();
        _ = factory.connectSetup(*anyopaque, &setupChatMessage, null, .{});
        _ = factory.connectBind(*anyopaque, &bindChatMessage, null, .{});

        const chat_list = gtk.ListView.new(selection.as(gtk.SelectionModel), factory.as(gtk.ListItemFactory));
        priv.chat_list = chat_list;
        scrolled.setChild(chat_list.as(gtk.Widget));
        box.append(scrolled.as(gtk.Widget));

        // Input area
        const input_box = gtk.Box.new(gtk.Orientation.horizontal, 8);
        const input_entry = gtk.Entry.new();
        input_entry.setPlaceholderText("Type your message...");
        input_entry.setHexpand(@intFromBool(true));
        priv.input_entry = input_entry;
        input_box.append(input_entry.as(gtk.Widget));

        const send_btn = gtk.Button.new();
        send_btn.setLabel("Send");
        send_btn.setIconName("send-to-symbolic");
        priv.send_btn = send_btn;
        _ = send_btn.connectClicked(&sendMessage, self);
        input_box.append(send_btn.as(gtk.Widget));
        box.append(input_box.as(gtk.Widget));

        page.setChild(box.as(gtk.Widget));
        self.as(adw.NavigationView).push(page.as(adw.NavigationPage));
    }

    fn setupChatMessage(_: *gtk.SignalListItemFactory, item: *gtk.ListItem, _: ?*anyopaque) callconv(.c) void {
        const box = gtk.Box.new(gtk.Orientation.vertical, 4);
        box.setMarginStart(8);
        box.setMarginEnd(8);
        box.setMarginTop(4);
        box.setMarginBottom(4);

        const role_label = gtk.Label.new("");
        role_label.setXalign(0);
        role_label.getStyleContext().addClass("dim-label");
        box.append(role_label.as(gtk.Widget));

        const content_label = gtk.Label.new("");
        content_label.setXalign(0);
        content_label.setWrap(@intFromBool(true));
        box.append(content_label.as(gtk.Widget));

        item.setChild(box.as(gtk.Widget));
    }

    fn bindChatMessage(_: *gtk.SignalListItemFactory, item: *gtk.ListItem, _: ?*anyopaque) callconv(.c) void {
        const entry = item.getItem() orelse return;
        const message = @as(*ChatMessage, @ptrCast(entry));
        const box = item.getChild() orelse return;
        const box_widget = box.as(gtk.Box);

        if (box_widget.getFirstChild()) |role| {
            const role_text = switch (message.role) {
                .user => "You",
                .assistant => "Assistant",
                .system => "System",
            };
            role.as(gtk.Label).setText(role_text);
            if (role.getNextSibling()) |content| {
                content.as(gtk.Label).setText(message.content);
            }
        }
    }

    fn newChat(button: *gtk.Button, self: *Self) callconv(.c) void {
        _ = button;
        const priv = getPriv(self);

        // Clear chat history - just removeAll, GObject dispose handles item cleanup
        if (priv.chat_store) |store| {
            store.removeAll();
        }
    }

    fn sendMessage(button: *gtk.Button, self: *Self) callconv(.c) void {
        _ = button;
        const priv = getPriv(self);
        const alloc = Application.default().allocator();

        if (priv.input_entry) |entry| {
            const text = entry.getText() orelse return;
            if (text.len == 0) return;

            // Add user message
            const user_msg = ChatMessage.new(alloc, .user, text) catch return;
            if (priv.chat_store) |store| {
                store.append(user_msg.as(gobject.Object));
            }

            // Clear input
            entry.setText("");

            // TODO: Send to AI and add assistant response
            log.info("Sending message: {s}", .{text});
        }
    }

    fn dispose(self: *Self) callconv(.c) void {
        const priv = getPriv(self);

        // Clean up all chat messages - just removeAll, GObject dispose handles item cleanup
        if (priv.chat_store) |store| {
            store.removeAll();
        }

        gobject.Object.virtual_methods.dispose.call(Class.parent, self.as(Parent));
    }

    pub fn addMessage(self: *Self, role: ChatMessage.MessageRole, content: []const u8) void {
        const priv = getPriv(self);
        const alloc = Application.default().allocator();

        const message = ChatMessage.new(alloc, role, content) catch {
            log.err("Failed to create chat message", .{});
            return;
        };

        if (priv.chat_store) |store| {
            store.append(message.as(gobject.Object));
        }
    }

    pub fn show(self: *Self, _: *Window) void {
        self.as(gtk.Widget).setVisible(@intFromBool(true));
    }
};
