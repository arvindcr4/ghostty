//! Workflow Builder UI
//! Provides Warp-like visual workflow creation and editing

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

const log = std.log.scoped(.gtk_ghostty_workflow_builder);

pub const WorkflowBuilderDialog = extern struct {
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
        workflow_name_entry: ?*gtk.Entry = null,
        steps_list: ?*gtk.ListView = null,
        steps_store: ?*gio.ListStore = null,
        add_step_btn: ?*gtk.Button = null,
        save_btn: ?*gtk.Button = null,
        run_btn: ?*gtk.Button = null,
        pub var offset: c_int = 0;
    };

    pub const WorkflowStepItem = extern struct {
        parent_instance: gobject.Object,
        order: u32,
        command: [:0]const u8,
        description: ?[:0]const u8 = null,
        condition: ?[:0]const u8 = null,

        pub const Parent = gobject.Object;

        pub const ItemClass = extern struct {
            parent_class: gobject.Object.Class,
            var parent: *gobject.Object.Class = undefined;

            fn init(class: *ItemClass) callconv(.c) void {
                gobject.Object.virtual_methods.dispose.implement(class, &WorkflowStepItem.dispose);
            }

            fn dispose(self: *WorkflowStepItem) callconv(.c) void {
                const alloc = Application.default().allocator();
                alloc.free(self.command);
                if (self.description) |desc| alloc.free(desc);
                if (self.condition) |cond| alloc.free(cond);
                gobject.Object.virtual_methods.dispose.call(ItemClass.parent, self);
            }
        };

        pub const getGObjectType = gobject.ext.defineClass(WorkflowStepItem, .{
            .name = "GhosttyWorkflowStepItem",
            .classInit = &ItemClass.init,
            .parent_class = &ItemClass.parent,
        });

        pub fn new(alloc: Allocator, order: u32, command: []const u8, description: ?[]const u8, condition: ?[]const u8) !*WorkflowStepItem {
            const self = gobject.ext.newInstance(WorkflowStepItem, .{});
            self.order = order;
            self.command = try alloc.dupeZ(u8, command);
            errdefer alloc.free(self.command);
            if (description) |desc| {
                self.description = try alloc.dupeZ(u8, desc);
                errdefer alloc.free(self.description.?);
            }
            if (condition) |cond| {
                self.condition = try alloc.dupeZ(u8, cond);
                errdefer alloc.free(self.condition.?);
            }
            return self;
        }

        pub fn deinit(self: *WorkflowStepItem, alloc: Allocator) void {
            alloc.free(self.command);
            if (self.description) |desc| alloc.free(desc);
            if (self.condition) |cond| alloc.free(cond);
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
            if (priv.steps_store) |store| {
                store.removeAll();
            }
            gobject.Object.virtual_methods.dispose.call(Class.parent, self.as(Parent));
        }

        pub const as = C.Class.as;
    };

    pub const getGObjectType = gobject.ext.defineClass(Self, .{
        .name = "GhosttyWorkflowBuilderDialog",
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
        self.as(adw.Window).setTitle("Workflow Builder");
        self.as(adw.Window).setDefaultSize(800, 600);

        // Create steps store
        const store = gio.ListStore.new(WorkflowStepItem.getGObjectType());
        priv.steps_store = store;

        // Create main box
        const main_box = gtk.Box.new(gtk.Orientation.vertical, 12);
        main_box.setMarginStart(12);
        main_box.setMarginEnd(12);
        main_box.setMarginTop(12);
        main_box.setMarginBottom(12);

        // Create header bar
        const header = adw.HeaderBar.new();
        header.setTitleWidget(gtk.Label.new("Workflow Builder"));

        // Create toolbar
        const toolbar = gtk.Box.new(gtk.Orientation.horizontal, 12);

        const name_label = gtk.Label.new("Name:");
        name_label.setHalign(gtk.Align.start);

        const name_entry = gtk.Entry.new();
        name_entry.setPlaceholderText("Workflow name");
        name_entry.setHexpand(true);
        priv.workflow_name_entry = name_entry;

        const add_step_btn = gtk.Button.new();
        add_step_btn.setIconName("list-add-symbolic");
        add_step_btn.setLabel("Add Step");
        _ = add_step_btn.connectClicked(&onAddStep, self);
        priv.add_step_btn = add_step_btn;

        const save_btn = gtk.Button.new();
        save_btn.setIconName("document-save-symbolic");
        save_btn.setLabel("Save");
        save_btn.addCssClass("suggested-action");
        _ = save_btn.connectClicked(&onSave, self);
        priv.save_btn = save_btn;

        const run_btn = gtk.Button.new();
        run_btn.setIconName("media-playback-start-symbolic");
        run_btn.setLabel("Run");
        _ = run_btn.connectClicked(&onRun, self);
        priv.run_btn = run_btn;

        toolbar.append(name_label.as(gtk.Widget));
        toolbar.append(name_entry.as(gtk.Widget));
        toolbar.append(add_step_btn.as(gtk.Widget));
        toolbar.append(save_btn.as(gtk.Widget));
        toolbar.append(run_btn.as(gtk.Widget));

        // Create list view
        const factory = gtk.SignalListItemFactory.new();
        factory.connectSetup(&setupStepItem, null);
        factory.connectBind(&bindStepItem, null);

        const selection = gtk.SingleSelection.new(store.as(gio.ListModel));
        const list_view = gtk.ListView.new(selection.as(gtk.SelectionModel), factory);
        list_view.setSingleClickActivate(true);
        _ = list_view.connectActivate(&onStepActivated, self);
        priv.steps_list = list_view;

        // Create scrolled window
        const scrolled = gtk.ScrolledWindow.new();
        scrolled.setChild(list_view.as(gtk.Widget));
        scrolled.setVexpand(true);

        main_box.append(toolbar.as(gtk.Widget));
        main_box.append(scrolled.as(gtk.Widget));

        self.as(adw.Window).setTitlebar(header.as(gtk.Widget));
        self.as(adw.Window).setContent(main_box.as(gtk.Widget));
    }

    fn setupStepItem(_: *gtk.SignalListItemFactory, item: *gtk.ListItem, _: ?*anyopaque) callconv(.c) void {
        const box = gtk.Box.new(gtk.Orientation.horizontal, 12);
        box.setMarginStart(12);
        box.setMarginEnd(12);
        box.setMarginTop(6);
        box.setMarginBottom(6);

        const order_label = gtk.Label.new("");
        order_label.addCssClass("title-3");
        order_label.setMinContentWidth(40);
        order_label.setHalign(gtk.Align.center);

        const info_box = gtk.Box.new(gtk.Orientation.vertical, 4);
        info_box.setHexpand(true);
        info_box.setHalign(gtk.Align.start);

        const command_label = gtk.Label.new("");
        command_label.setXalign(0);
        command_label.addCssClass("monospace");
        command_label.addCssClass("title-5");
        command_label.setSelectable(true);

        const desc_label = gtk.Label.new("");
        desc_label.setXalign(0);
        desc_label.addCssClass("dim-label");
        desc_label.setWrap(true);

        info_box.append(command_label.as(gtk.Widget));
        info_box.append(desc_label.as(gtk.Widget));

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

        action_box.append(up_btn.as(gtk.Widget));
        action_box.append(down_btn.as(gtk.Widget));
        action_box.append(edit_btn.as(gtk.Widget));
        action_box.append(delete_btn.as(gtk.Widget));

        box.append(order_label.as(gtk.Widget));
        box.append(info_box.as(gtk.Widget));
        box.append(action_box.as(gtk.Widget));

        item.setChild(box.as(gtk.Widget));

        // Connect signal handlers once during setup
        _ = up_btn.connectClicked(&onMoveUpListItem, item);
        _ = down_btn.connectClicked(&onMoveDownListItem, item);
        _ = edit_btn.connectClicked(&onEditStepListItem, item);
        _ = delete_btn.connectClicked(&onDeleteStepListItem, item);
    }

    fn bindStepItem(_: *gtk.SignalListItemFactory, item: *gtk.ListItem, _: ?*anyopaque) callconv(.c) void {
        const entry = item.getItem() orelse return;
        const step_item = @as(*WorkflowStepItem, @ptrCast(@alignCast(entry)));
        const box = item.getChild() orelse return;
        const box_widget = box.as(gtk.Box);

        if (box_widget.getFirstChild()) |order| {
            var order_buf: [16]u8 = undefined;
            const order_text = std.fmt.bufPrintZ(&order_buf, "{d}", .{step_item.order}) catch "0";
            order.as(gtk.Label).setText(order_text);
            if (order.getNextSibling()) |info_box| {
                if (info_box.as(gtk.Box).getFirstChild()) |command| {
                    command.as(gtk.Label).setText(step_item.command);
                    if (command.getNextSibling()) |desc| {
                        const desc_text = if (step_item.description) |d| d else "No description";
                        desc.as(gtk.Label).setText(desc_text);
                    }
                }
            }
        }
    }

    fn onAddStep(_: *gtk.Button, self: *Self) callconv(.c) void {
        _ = self;
        // TODO: Show dialog to add step
        log.info("Add step clicked", .{});
    }

    fn onSave(_: *gtk.Button, self: *Self) callconv(.c) void {
        _ = self;
        // TODO: Save workflow
        log.info("Save workflow", .{});
    }

    fn onRun(_: *gtk.Button, self: *Self) callconv(.c) void {
        _ = self;
        // TODO: Run workflow
        log.info("Run workflow", .{});
    }

    fn onStepActivated(_: *gtk.ListView, position: u32, self: *Self) callconv(.c) void {
        const priv = getPriv(self);
        if (priv.steps_store) |store| {
            if (store.getItem(position)) |item| {
                const step_item: *WorkflowStepItem = @ptrCast(@alignCast(item));
                // TODO: Show step editor
                log.info("Step activated: {s}", .{step_item.command});
            }
        }
    }

    fn onMoveUpListItem(_: *gtk.Button, list_item: *gtk.ListItem) callconv(.c) void {
        _ = list_item;
        // TODO: Move step up
        log.info("Move step up", .{});
    }

    fn onMoveDownListItem(_: *gtk.Button, list_item: *gtk.ListItem) callconv(.c) void {
        _ = list_item;
        // TODO: Move step down
        log.info("Move step down", .{});
    }

    fn onEditStepListItem(_: *gtk.Button, list_item: *gtk.ListItem) callconv(.c) void {
        const entry = list_item.getItem() orelse return;
        const step_item = @as(*WorkflowStepItem, @ptrCast(@alignCast(entry)));
        // TODO: Show edit dialog
        log.info("Edit step: {s}", .{step_item.command});
    }

    fn onDeleteStepListItem(_: *gtk.Button, list_item: *gtk.ListItem) callconv(.c) void {
        const entry = list_item.getItem() orelse return;
        const step_item = @as(*WorkflowStepItem, @ptrCast(@alignCast(entry)));
        // TODO: Remove from store
        log.info("Delete step: {s}", .{step_item.command});
    }

    pub fn show(self: *Self, parent: *Window) void {
        self.as(adw.Window).setTransientFor(parent.as(gtk.Window));
        self.as(adw.Window).present();
    }
};
