//! Output Annotations UI
//! Provides Warp-like ability to add comments/notes to command outputs

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

const log = std.log.scoped(.gtk_ghostty_output_annotations);

pub const OutputAnnotationsDialog = extern struct {
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
        annotations_list: ?*gtk.ListView = null,
        annotations_store: ?*gio.ListStore = null,
        add_btn: ?*gtk.Button = null,
        pub var offset: c_int = 0;
    };

    pub const AnnotationItem = extern struct {
        parent_instance: gobject.Object,
        command: [:0]const u8,
        line_number: u32,
        note: [:0]const u8,
        timestamp: i64,
        author: ?[:0]const u8 = null,

        pub const Parent = gobject.Object;

        pub const ItemClass = extern struct {
            parent_class: gobject.Object.Class,
            var parent: *gobject.Object.Class = undefined;

            fn init(class: *ItemClass) callconv(.c) void {
                gobject.Object.virtual_methods.dispose.implement(class, &AnnotationItem.dispose);
            }

            fn dispose(self: *AnnotationItem) callconv(.c) void {
                const alloc = Application.default().allocator();
                alloc.free(self.command);
                alloc.free(self.note);
                if (self.author) |auth| alloc.free(auth);
                gobject.Object.virtual_methods.dispose.call(ItemClass.parent, self);
            }
        };

        pub const getGObjectType = gobject.ext.defineClass(AnnotationItem, .{
            .name = "GhosttyAnnotationItem",
            .classInit = &ItemClass.init,
            .parent_class = &ItemClass.parent,
        });

        pub fn new(alloc: Allocator, command: []const u8, line_number: u32, note: []const u8, author: ?[]const u8) !*AnnotationItem {
            const self = gobject.ext.newInstance(AnnotationItem, .{});
            self.command = try alloc.dupeZ(u8, command);
            errdefer alloc.free(self.command);
            self.line_number = line_number;
            self.note = try alloc.dupeZ(u8, note);
            errdefer alloc.free(self.note);
            self.timestamp = std.time.timestamp();
            if (author) |auth| {
                self.author = try alloc.dupeZ(u8, auth);
                errdefer alloc.free(self.author.?);
            }
            return self;
        }

        pub fn deinit(self: *AnnotationItem, alloc: Allocator) void {
            alloc.free(self.command);
            alloc.free(self.note);
            if (self.author) |auth| alloc.free(auth);
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
            if (priv.annotations_store) |store| {
                store.removeAll();
            }
            gobject.Object.virtual_methods.dispose.call(Class.parent, self.as(Parent));
        }

        pub const as = C.Class.as;
    };

    pub const getGObjectType = gobject.ext.defineClass(Self, .{
        .name = "GhosttyOutputAnnotationsDialog",
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
        self.as(adw.PreferencesWindow).setTitle("Output Annotations");

        // Create annotations store
        const store = gio.ListStore.new(AnnotationItem.getGObjectType());
        priv.annotations_store = store;

        // Create add button
        const add_btn = gtk.Button.new();
        add_btn.setIconName("list-add-symbolic");
        add_btn.setTooltipText("Add Annotation");
        _ = add_btn.connectClicked(&onAddAnnotation, self);
        priv.add_btn = add_btn;

        // Create list view
        const factory = gtk.SignalListItemFactory.new();
        factory.connectSetup(&setupAnnotationItem, null);
        factory.connectBind(&bindAnnotationItem, null);

        const selection = gtk.SingleSelection.new(store.as(gio.ListModel));
        const list_view = gtk.ListView.new(selection.as(gtk.SelectionModel), factory);
        list_view.setSingleClickActivate(true);
        _ = list_view.connectActivate(&onAnnotationActivated, self);
        priv.annotations_list = list_view;

        // Create scrolled window
        const scrolled = gtk.ScrolledWindow.new();
        scrolled.setChild(list_view.as(gtk.Widget));
        scrolled.setVexpand(true);

        // Create header bar
        const header = adw.HeaderBar.new();
        header.setTitleWidget(gtk.Label.new("Output Annotations"));
        header.packEnd(add_btn.as(gtk.Widget));

        // Create main page
        const page = adw.PreferencesPage.new();
        page.setIconName("note-symbolic");
        page.setTitle("Annotations");

        const group = adw.PreferencesGroup.new();
        group.setTitle("Command Output Annotations");
        group.setDescription("Add notes and comments to command outputs");
        group.add(scrolled.as(gtk.Widget));

        page.add(group.as(gtk.Widget));
        self.as(adw.PreferencesWindow).add(page.as(gtk.Widget));

        // Load annotations
        loadAnnotations(self);
    }

    fn setupAnnotationItem(_: *gtk.SignalListItemFactory, item: *gtk.ListItem, _: ?*anyopaque) callconv(.c) void {
        const box = gtk.Box.new(gtk.Orientation.horizontal, 12);
        box.setMarginStart(12);
        box.setMarginEnd(12);
        box.setMarginTop(6);
        box.setMarginBottom(6);

        const icon = gtk.Image.new();
        icon.setIconName("note-symbolic");
        icon.setIconSize(gtk.IconSize.large);

        const info_box = gtk.Box.new(gtk.Orientation.vertical, 4);
        info_box.setHexpand(true);
        info_box.setHalign(gtk.Align.start);

        const command_label = gtk.Label.new("");
        command_label.setXalign(0);
        command_label.addCssClass("monospace");
        command_label.addCssClass("title-5");
        command_label.setSelectable(true);

        const note_label = gtk.Label.new("");
        note_label.setXalign(0);
        note_label.setWrap(true);

        const meta_label = gtk.Label.new("");
        meta_label.setXalign(0);
        meta_label.addCssClass("caption");
        meta_label.addCssClass("dim-label");

        info_box.append(command_label.as(gtk.Widget));
        info_box.append(note_label.as(gtk.Widget));
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

        box.append(icon.as(gtk.Widget));
        box.append(info_box.as(gtk.Widget));
        box.append(action_box.as(gtk.Widget));

        item.setChild(box.as(gtk.Widget));

        // Connect signal handlers once during setup
        _ = edit_btn.connectClicked(&onEditAnnotationListItem, item);
        _ = delete_btn.connectClicked(&onDeleteAnnotationListItem, item);
    }

    fn bindAnnotationItem(_: *gtk.SignalListItemFactory, item: *gtk.ListItem, _: ?*anyopaque) callconv(.c) void {
        const entry = item.getItem() orelse return;
        const annotation_item = @as(*AnnotationItem, @ptrCast(@alignCast(entry)));
        const box = item.getChild() orelse return;
        const box_widget = box.as(gtk.Box);

        if (box_widget.getFirstChild()) |icon| {
            if (icon.getNextSibling()) |info_box| {
                if (info_box.as(gtk.Box).getFirstChild()) |command| {
                    command.as(gtk.Label).setText(annotation_item.command);
                    if (command.getNextSibling()) |note| {
                        note.as(gtk.Label).setText(annotation_item.note);
                        if (note.getNextSibling()) |meta| {
                            var meta_buf: [256]u8 = undefined;
                            const meta_text = if (annotation_item.author) |auth|
                                std.fmt.bufPrintZ(&meta_buf, "Line {d} • {s}", .{ annotation_item.line_number, auth }) catch "Annotation"
                            else
                                std.fmt.bufPrintZ(&meta_buf, "Line {d}", .{annotation_item.line_number}) catch "Annotation";
                            meta.as(gtk.Label).setText(meta_text);
                        }
                    }
                }
            }
        }
    }

    fn onAddAnnotation(_: *gtk.Button, self: *Self) callconv(.c) void {
        _ = self;
        // TODO: Show dialog to add annotation
        log.info("Add annotation clicked", .{});
    }

    fn onAnnotationActivated(_: *gtk.ListView, position: u32, self: *Self) callconv(.c) void {
        const priv = getPriv(self);
        if (priv.annotations_store) |store| {
            if (store.getItem(position)) |item| {
                const annotation_item: *AnnotationItem = @ptrCast(@alignCast(item));
                // TODO: Show annotation details
                log.info("Annotation activated: {s}", .{annotation_item.command});
            }
        }
    }

    fn onEditAnnotationListItem(_: *gtk.Button, list_item: *gtk.ListItem) callconv(.c) void {
        const entry = list_item.getItem() orelse return;
        const annotation_item = @as(*AnnotationItem, @ptrCast(@alignCast(entry)));
        // TODO: Show edit dialog
        log.info("Edit annotation: {s}", .{annotation_item.command});
    }

    fn onDeleteAnnotationListItem(_: *gtk.Button, list_item: *gtk.ListItem) callconv(.c) void {
        const entry = list_item.getItem() orelse return;
        const annotation_item = @as(*AnnotationItem, @ptrCast(@alignCast(entry)));
        // TODO: Remove from store
        log.info("Delete annotation: {s}", .{annotation_item.command});
    }

    fn loadAnnotations(_: *Self) void {
        // TODO: Load annotations from storage
        log.info("Loading annotations...", .{});
    }

    pub fn addAnnotation(self: *Self, command: []const u8, line_number: u32, note: []const u8, author: ?[]const u8) !void {
        const priv = getPriv(self);
        const alloc = Application.default().allocator();

        const annotation = try AnnotationItem.new(alloc, command, line_number, note, author);
        if (priv.annotations_store) |store| {
            store.append(annotation.as(gobject.Object));
        }
    }

    pub fn show(self: *Self, parent: *Window) void {
        self.as(adw.PreferencesWindow).setTransientFor(parent.as(gtk.Window));
        self.as(adw.PreferencesWindow).present();
    }
};
