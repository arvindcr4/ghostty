//! Command Builder UI
//! Provides Warp-like visual command construction tool

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

const log = std.log.scoped(.gtk_ghostty_command_builder);

pub const CommandBuilderDialog = extern struct {
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
        command_preview: ?*gtk.TextView = null,
        components_list: ?*gtk.ListView = null,
        components_store: ?*gio.ListStore = null,
        add_component_btn: ?*gtk.Button = null,
        execute_btn: ?*gtk.Button = null,
        pub var offset: c_int = 0;
    };

    pub const ComponentItem = extern struct {
        parent_instance: gobject.Object,
        type: [:0]const u8, // "command", "flag", "argument", "pipe", "redirect"
        value: [:0]const u8,
        description: ?[:0]const u8 = null,

        pub const Parent = gobject.Object;

        pub const ItemClass = extern struct {
            parent_class: gobject.Object.Class,
            var parent: *gobject.Object.Class = undefined;

            fn init(class: *ItemClass) callconv(.c) void {
                gobject.Object.virtual_methods.dispose.implement(class, &ComponentItem.dispose);
            }

            fn dispose(self: *ComponentItem) callconv(.c) void {
                const alloc = Application.default().allocator();
                alloc.free(self.type);
                alloc.free(self.value);
                if (self.description) |desc| alloc.free(desc);
                gobject.Object.virtual_methods.dispose.call(ItemClass.parent, self);
            }
        };

        pub const getGObjectType = gobject.ext.defineClass(ComponentItem, .{
            .name = "GhosttyComponentItem",
            .classInit = &ItemClass.init,
            .parent_class = &ItemClass.parent,
        });

        pub fn new(alloc: Allocator, component_type: []const u8, value: []const u8) !*ComponentItem {
            const self = gobject.ext.newInstance(ComponentItem, .{});
            self.type = try alloc.dupeZ(u8, component_type);
            errdefer alloc.free(self.type);
            self.value = try alloc.dupeZ(u8, value);
            errdefer alloc.free(self.value);
            return self;
        }

        pub fn deinit(self: *ComponentItem, alloc: Allocator) void {
            alloc.free(self.type);
            alloc.free(self.value);
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
            if (priv.components_store) |store| {
                store.removeAll();
            }
            gobject.Object.virtual_methods.dispose.call(Class.parent, self.as(Parent));
        }

        pub const as = C.Class.as;
    };

    pub const getGObjectType = gobject.ext.defineClass(Self, .{
        .name = "GhosttyCommandBuilderDialog",
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
        self.as(adw.Window).setTitle("Command Builder");
        self.as(adw.Window).setDefaultSize(900, 600);

        // Create components store
        const store = gio.ListStore.new(ComponentItem.getGObjectType());
        priv.components_store = store;

        // Create main box
        const main_box = gtk.Box.new(gtk.Orientation.vertical, 12);
        main_box.setMarginStart(12);
        main_box.setMarginEnd(12);
        main_box.setMarginTop(12);
        main_box.setMarginBottom(12);

        // Create preview section
        const preview_label = gtk.Label.new("Command Preview");
        preview_label.setXalign(0);
        preview_label.addCssClass("title-5");

        const preview_scrolled = gtk.ScrolledWindow.new();
        const command_preview = gtk.TextView.new();
        command_preview.setEditable(false);
        command_preview.setMonospace(true);
        command_preview.addCssClass("command-preview");
        preview_scrolled.setChild(command_preview.as(gtk.Widget));
        preview_scrolled.setMinContentHeight(80);
        priv.command_preview = command_preview;

        // Create components section
        const components_label = gtk.Label.new("Components");
        components_label.setXalign(0);
        components_label.addCssClass("title-5");

        const toolbar = gtk.Box.new(gtk.Orientation.horizontal, 12);

        const add_component_btn = gtk.Button.new();
        add_component_btn.setIconName("list-add-symbolic");
        add_component_btn.setLabel("Add Component");
        _ = add_component_btn.connectClicked(&onAddComponent, self);
        priv.add_component_btn = add_component_btn;

        const execute_btn = gtk.Button.new();
        execute_btn.setIconName("media-playback-start-symbolic");
        execute_btn.setLabel("Execute");
        execute_btn.addCssClass("suggested-action");
        _ = execute_btn.connectClicked(&onExecute, self);
        priv.execute_btn = execute_btn;

        toolbar.append(add_component_btn.as(gtk.Widget));
        toolbar.append(execute_btn.as(gtk.Widget));

        // Create list view
        const factory = gtk.SignalListItemFactory.new();
        factory.connectSetup(&setupComponentItem, null);
        factory.connectBind(&bindComponentItem, null);

        const selection = gtk.SingleSelection.new(store.as(gio.ListModel));
        const list_view = gtk.ListView.new(selection.as(gtk.SelectionModel), factory);
        list_view.setSingleClickActivate(true);
        _ = list_view.connectActivate(&onComponentActivated, self);
        priv.components_list = list_view;

        // Create scrolled window
        const scrolled = gtk.ScrolledWindow.new();
        scrolled.setChild(list_view.as(gtk.Widget));
        scrolled.setVexpand(true);

        main_box.append(preview_label.as(gtk.Widget));
        main_box.append(preview_scrolled.as(gtk.Widget));
        main_box.append(components_label.as(gtk.Widget));
        main_box.append(toolbar.as(gtk.Widget));
        main_box.append(scrolled.as(gtk.Widget));

        self.as(adw.Window).setContent(main_box.as(gtk.Widget));

        // Update preview when components change
        _ = store.connectItemsChanged(&onComponentsChanged, self);
    }

    fn setupComponentItem(_: *gtk.SignalListItemFactory, item: *gtk.ListItem, _: ?*anyopaque) callconv(.c) void {
        const box = gtk.Box.new(gtk.Orientation.horizontal, 12);
        box.setMarginStart(12);
        box.setMarginEnd(12);
        box.setMarginTop(6);
        box.setMarginBottom(6);

        const type_label = gtk.Label.new("");
        type_label.setMinContentWidth(80);
        type_label.addCssClass("caption");
        type_label.addCssClass("dim-label");

        const value_label = gtk.Label.new("");
        value_label.setXalign(0);
        value_label.addCssClass("monospace");
        value_label.addCssClass("title-5");
        value_label.setHexpand(true);
        value_label.setSelectable(true);

        const action_box = gtk.Box.new(gtk.Orientation.horizontal, 4);
        const up_btn = gtk.Button.new();
        up_btn.setIconName("go-up-symbolic");
        up_btn.setTooltipText("Move Up");
        up_btn.addCssClass("circular");
        up_btn.addCssClass("flat");

        const down_btn = gtk.Button.new();
        down_btn.setIconName("go-down-symbolic");
        down_btn.setTooltipText("Move Down");
        down_btn.addCssClass("circular");
        down_btn.addCssClass("flat");

        const delete_btn = gtk.Button.new();
        delete_btn.setIconName("user-trash-symbolic");
        delete_btn.setTooltipText("Delete");
        delete_btn.addCssClass("circular");
        delete_btn.addCssClass("flat");
        delete_btn.addCssClass("destructive-action");

        action_box.append(up_btn.as(gtk.Widget));
        action_box.append(down_btn.as(gtk.Widget));
        action_box.append(delete_btn.as(gtk.Widget));

        box.append(type_label.as(gtk.Widget));
        box.append(value_label.as(gtk.Widget));
        box.append(action_box.as(gtk.Widget));

        item.setChild(box.as(gtk.Widget));

        // Connect signal handlers once during setup
        _ = up_btn.connectClicked(&onMoveUpListItem, item);
        _ = down_btn.connectClicked(&onMoveDownListItem, item);
        _ = delete_btn.connectClicked(&onDeleteComponentListItem, item);
    }

    fn bindComponentItem(_: *gtk.SignalListItemFactory, item: *gtk.ListItem, _: ?*anyopaque) callconv(.c) void {
        const entry = item.getItem() orelse return;
        const component_item = @as(*ComponentItem, @ptrCast(@alignCast(entry)));
        const box = item.getChild() orelse return;
        const box_widget = box.as(gtk.Box);

        if (box_widget.getFirstChild()) |type_label| {
            type_label.as(gtk.Label).setText(component_item.type);
            if (type_label.getNextSibling()) |value| {
                value.as(gtk.Label).setText(component_item.value);
            }
        }
    }

    fn onAddComponent(_: *gtk.Button, self: *Self) callconv(.c) void {
        _ = self;
        // TODO: Show dialog to add component
        log.info("Add component clicked", .{});
    }

    fn onExecute(_: *gtk.Button, self: *Self) callconv(.c) void {
        const priv = getPriv(self);
        // TODO: Build command from components and execute
        if (priv.command_preview) |preview| {
            const buffer = preview.getBuffer();
            var start_iter: gtk.TextIter = undefined;
            var end_iter: gtk.TextIter = undefined;
            buffer.getStartIter(&start_iter);
            buffer.getEndIter(&end_iter);
            const command = buffer.getText(&start_iter, &end_iter, false);
            log.info("Execute command: {s}", .{command});
        }
    }

    fn onComponentActivated(_: *gtk.ListView, position: u32, self: *Self) callconv(.c) void {
        const priv = getPriv(self);
        if (priv.components_store) |store| {
            if (store.getItem(position)) |item| {
                const component_item: *ComponentItem = @ptrCast(@alignCast(item));
                // TODO: Show component editor
                log.info("Component activated: {s}", .{component_item.value});
            }
        }
    }

    fn onMoveUpListItem(_: *gtk.Button, list_item: *gtk.ListItem) callconv(.c) void {
        _ = list_item;
        // TODO: Move component up
        log.info("Move component up", .{});
    }

    fn onMoveDownListItem(_: *gtk.Button, list_item: *gtk.ListItem) callconv(.c) void {
        _ = list_item;
        // TODO: Move component down
        log.info("Move component down", .{});
    }

    fn onDeleteComponentListItem(_: *gtk.Button, list_item: *gtk.ListItem) callconv(.c) void {
        const entry = list_item.getItem() orelse return;
        const component_item = @as(*ComponentItem, @ptrCast(@alignCast(entry)));
        // TODO: Remove from store
        log.info("Delete component: {s}", .{component_item.value});
    }

    fn onComponentsChanged(_: *gio.ListStore, position: u32, removed: u32, added: u32, self: *Self) callconv(.c) void {
        _ = position;
        _ = removed;
        _ = added;
        const priv = getPriv(self);
        // Update command preview
        if (priv.command_preview) |preview| {
            if (priv.components_store) |store| {
                const buffer = preview.getBuffer();
                var command_buf = std.ArrayList(u8).init(Application.default().allocator());
                defer command_buf.deinit();

                var i: u32 = 0;
                while (i < store.getNItems()) : (i += 1) {
                    if (store.getItem(i)) |item| {
                        const component_item: *ComponentItem = @ptrCast(@alignCast(item));
                        if (i > 0) {
                            command_buf.append(' ') catch {};
                        }
                        command_buf.appendSlice(component_item.value) catch {};
                    }
                }

                buffer.setText(command_buf.items.ptr, @intCast(command_buf.items.len));
            }
        }
    }

    pub fn show(self: *Self, parent: *Window) void {
        self.as(adw.Window).setTransientFor(parent.as(gtk.Window));
        self.as(adw.Window).present();
    }
};
