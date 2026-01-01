//! Inline Command Explanations Tooltip
//! Provides Warp-like hover tooltips with AI explanations

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

const log = std.log.scoped(.gtk_ghostty_inline_explanations);

pub const InlineExplanationTooltip = extern struct {
    const C = Common(Self, Private);
    pub const as = C.as;
    pub const ref = C.ref;
    pub const unref = C.unref;
    pub const refSink = C.refSink;
    const getPriv = C.getPriv;
    const Self = @This();

    parent_instance: Parent,
    pub const Parent = gtk.Popover;

    const Private = struct {
        title_label: ?*gtk.Label = null,
        explanation_text: ?*gtk.TextView = null,
        examples_list: ?*gtk.ListView = null,
        examples_store: ?*gio.ListStore = null,
        current_command: ?[]const u8 = null,

        pub var offset: c_int = 0;
    };

    pub const ExampleItem = extern struct {
        parent_instance: gobject.Object,
        command: [:0]const u8,
        description: [:0]const u8,

        pub const Parent = gobject.Object;
        pub const getGObjectType = gobject.ext.defineClass(ExampleItem, .{
            .name = "GhosttyExampleItem",
            .classInit = &ItemClass.init,
            .parent_class = &ItemClass.parent,
        });

        pub const ItemClass = extern struct {
            parent_class: gobject.Object.Class,
            var parent: *gobject.Object.Class = undefined;

            fn init(class: *ItemClass) callconv(.c) void {
                gobject.Object.virtual_methods.dispose.implement(class, &ExampleItem.dispose);
                gobject.Object.virtual_methods.finalize.implement(class, &ExampleItem.finalize);
            }

            fn dispose(self: *ExampleItem) callconv(.c) void {
                const alloc = Application.default().allocator();
                if (self.command.len > 0) {
                    alloc.free(self.command);
                    self.command = "";
                }
                if (self.description.len > 0) {
                    alloc.free(self.description);
                    self.description = "";
                }
                gobject.Object.virtual_methods.dispose.call(ItemClass.parent, self);
            }

            fn finalize(self: *ExampleItem) callconv(.c) void {
                gobject.Object.virtual_methods.finalize.call(ItemClass.parent, self);
            }
        };

        pub fn new(alloc: Allocator, command: []const u8, description: []const u8) !*ExampleItem {
            const self = gobject.ext.newInstance(ExampleItem, .{});
            self.command = try alloc.dupeZ(u8, command);
            errdefer alloc.free(self.command);
            self.description = try alloc.dupeZ(u8, description);
            errdefer alloc.free(self.description);
            return self;
        }

        pub fn deinit(self: *ExampleItem, alloc: Allocator) void {
            alloc.free(self.command);
            alloc.free(self.description);
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
        .name = "GhosttyInlineExplanationTooltip",
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

        self.as(gtk.Popover).setHasArrow(@intFromBool(true));
        self.as(gtk.Popover).setAutohide(@intFromBool(true));
        self.as(gtk.Popover).setPosition(gtk.PositionType.top);

        const box = gtk.Box.new(gtk.Orientation.vertical, 8);
        box.setMarginStart(12);
        box.setMarginEnd(12);
        box.setMarginTop(12);
        box.setMarginBottom(12);
        // Set minimum width (gtk.Box doesn't have setMinContentWidth, use setSizeRequest)
        box.as(gtk.Widget).setSizeRequest(400, -1);

        // Title
        const title_label = gtk.Label.new("");
        title_label.setXalign(0);
        title_label.getStyleContext().addClass("heading");
        priv.title_label = title_label;
        box.append(title_label.as(gtk.Widget));

        // Explanation text
        const explanation_scrolled = gtk.ScrolledWindow.new();
        explanation_scrolled.setMaxContentHeight(200);
        explanation_scrolled.setPolicy(gtk.PolicyType.never, gtk.PolicyType.automatic);

        const explanation_buffer = gtk.TextBuffer.new(null);
        const explanation_view = gtk.TextView.newWithBuffer(explanation_buffer);
        explanation_view.setEditable(@intFromBool(false));
        explanation_view.setWrapMode(gtk.WrapMode.word);
        priv.explanation_text = explanation_view;
        explanation_scrolled.setChild(explanation_view.as(gtk.Widget));
        box.append(explanation_scrolled.as(gtk.Widget));

        // Examples section
        const examples_label = gtk.Label.new("Examples");
        examples_label.setXalign(0);
        examples_label.getStyleContext().addClass("heading");
        box.append(examples_label.as(gtk.Widget));

        const examples_scrolled = gtk.ScrolledWindow.new();
        examples_scrolled.setMaxContentHeight(150);
        examples_scrolled.setPolicy(gtk.PolicyType.never, gtk.PolicyType.automatic);

        const examples_store = gio.ListStore.new(ExampleItem.getGObjectType());
        priv.examples_store = examples_store;

        const selection = gtk.NoSelection.new(examples_store.as(gio.ListModel));
        const factory = gtk.SignalListItemFactory.new();
        _ = factory.connectSetup(*anyopaque, &setupExampleItem, null, .{});
        _ = factory.connectBind(*anyopaque, &bindExampleItem, null, .{});

        const examples_list = gtk.ListView.new(selection.as(gtk.SelectionModel), factory.as(gtk.ListItemFactory));
        priv.examples_list = examples_list;
        examples_scrolled.setChild(examples_list.as(gtk.Widget));
        box.append(examples_scrolled.as(gtk.Widget));

        self.as(gtk.Popover).setChild(box.as(gtk.Widget));
    }

    fn setupExampleItem(_: *gtk.SignalListItemFactory, item: *gtk.ListItem, _: ?*anyopaque) callconv(.c) void {
        const box = gtk.Box.new(gtk.Orientation.vertical, 4);
        box.setMarginStart(8);
        box.setMarginEnd(8);
        box.setMarginTop(4);
        box.setMarginBottom(4);

        const command_label = gtk.Label.new("");
        command_label.setXalign(0);
        command_label.getStyleContext().addClass("monospace");
        box.append(command_label.as(gtk.Widget));

        const desc_label = gtk.Label.new("");
        desc_label.setXalign(0);
        desc_label.setWrap(@intFromBool(true));
        desc_label.getStyleContext().addClass("dim-label");
        box.append(desc_label.as(gtk.Widget));

        item.setChild(box.as(gtk.Widget));
    }

    fn bindExampleItem(_: *gtk.SignalListItemFactory, item: *gtk.ListItem, _: ?*anyopaque) callconv(.c) void {
        const entry = item.getItem() orelse return;
        const example_item = @as(*ExampleItem, @ptrCast(entry));
        const box = item.getChild() orelse return;
        const box_widget = box.as(gtk.Box);

        if (box_widget.getFirstChild()) |command| {
            command.as(gtk.Label).setText(example_item.command);
            if (command.getNextSibling()) |desc| {
                desc.as(gtk.Label).setText(example_item.description);
            }
        }
    }

    fn dispose(self: *Self) callconv(.c) void {
        const priv = getPriv(self);
        const alloc = Application.default().allocator();

        // Clean up command string
        if (priv.current_command) |cmd| {
            alloc.free(cmd);
            priv.current_command = null;
        }

        // Clean up all example items - just removeAll, GObject dispose handles item cleanup
        if (priv.examples_store) |store| {
            store.removeAll();
        }

        gobject.Object.virtual_methods.dispose.call(Class.parent, self.as(Parent));
    }

    pub fn setExplanation(self: *Self, command: []const u8, explanation: []const u8, examples: []const struct { command: []const u8, description: []const u8 }) void {
        const priv = getPriv(self);
        const alloc = Application.default().allocator();

        // Update command
        if (priv.current_command) |old_cmd| {
            alloc.free(old_cmd);
        }
        priv.current_command = alloc.dupe(u8, command) catch null;

        // Update title
        if (priv.title_label) |title| {
            const command_z = alloc.dupeZ(u8, command) catch return;
            defer alloc.free(command_z);
            title.setText(command_z);
        }

        // Update explanation
        if (priv.explanation_text) |view| {
            const buffer = view.getBuffer();
            const explanation_z = alloc.dupeZ(u8, explanation) catch return;
            defer alloc.free(explanation_z);
            buffer.setText(explanation_z, -1);
        }

        // Clear and update examples
        if (priv.examples_store) |store| {
            const n = store.getNItems();
            var i: u32 = 0;
            while (i < n) : (i += 1) {
                if (store.getItem(i)) |item| {
                    const example_item: *ExampleItem = @ptrCast(@alignCast(item));
                    example_item.deinit(alloc);
                }
            }
            store.removeAll();

            for (examples) |ex| {
                const item = ExampleItem.new(alloc, ex.command, ex.description) catch continue;
                store.append(item.as(gobject.Object));
            }
        }
    }

    pub fn showAt(self: *Self, widget: *gtk.Widget, x: f64, y: f64) void {
        self.as(gtk.Popover).setPointingTo(&gtk.Rectangle{ .x = @intFromFloat(x), .y = @intFromFloat(y), .width = 1, .height = 1 });
        self.as(gtk.Popover).setParent(widget);
        self.as(gtk.Popover).popup();
    }

    pub fn hide(self: *Self) void {
        self.as(gtk.Popover).popdown();
    }
};
