//! Output Comparison Tool UI
//! Provides Warp-like UI for comparing outputs from different commands

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

const log = std.log.scoped(.gtk_ghostty_output_comparison);

pub const OutputComparisonDialog = extern struct {
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
        left_view: ?*gtk.TextView = null,
        right_view: ?*gtk.TextView = null,
        left_command_entry: ?*gtk.Entry = null,
        right_command_entry: ?*gtk.Entry = null,
        compare_btn: ?*gtk.Button = null,
        diff_view: ?*gtk.TextView = null,
        pub var offset: c_int = 0;
    };

    pub const Class = extern struct {
        parent_class: Parent.Class,
        var parent: *Parent.Class = undefined;

        fn init(class: *Class) callconv(.c) void {
            gobject.Object.virtual_methods.dispose.implement(class, &dispose);
        }

        fn dispose(self: *Self) callconv(.c) void {
            gobject.Object.virtual_methods.dispose.call(Class.parent, self.as(Parent));
        }

        pub const as = C.Class.as;
    };

    pub const getGObjectType = gobject.ext.defineClass(Self, .{
        .name = "GhosttyOutputComparisonDialog",
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
        self.as(adw.Window).setTitle("Output Comparison");
        self.as(adw.Window).setDefaultSize(1200, 700);

        // Create main paned
        const main_paned = gtk.Paned.new(gtk.Orientation.horizontal);

        // Left side
        const left_box = gtk.Box.new(gtk.Orientation.vertical, 8);
        left_box.setMarginStart(12);
        left_box.setMarginEnd(12);
        left_box.setMarginTop(12);
        left_box.setMarginBottom(12);

        const left_label = gtk.Label.new("Command 1");
        left_label.setXalign(0);
        left_label.addCssClass("title-5");

        const left_command_entry = gtk.Entry.new();
        left_command_entry.setPlaceholderText("Enter command or select from history");
        priv.left_command_entry = left_command_entry;

        const left_scrolled = gtk.ScrolledWindow.new();
        const left_view = gtk.TextView.new();
        left_view.setEditable(false);
        left_view.setMonospace(true);
        left_scrolled.setChild(left_view.as(gtk.Widget));
        left_scrolled.setVexpand(true);
        priv.left_view = left_view;

        left_box.append(left_label.as(gtk.Widget));
        left_box.append(left_command_entry.as(gtk.Widget));
        left_box.append(left_scrolled.as(gtk.Widget));

        // Right side
        const right_box = gtk.Box.new(gtk.Orientation.vertical, 8);
        right_box.setMarginStart(12);
        right_box.setMarginEnd(12);
        right_box.setMarginTop(12);
        right_box.setMarginBottom(12);

        const right_label = gtk.Label.new("Command 2");
        right_label.setXalign(0);
        right_label.addCssClass("title-5");

        const right_command_entry = gtk.Entry.new();
        right_command_entry.setPlaceholderText("Enter command or select from history");
        priv.right_command_entry = right_command_entry;

        const right_scrolled = gtk.ScrolledWindow.new();
        const right_view = gtk.TextView.new();
        right_view.setEditable(false);
        right_view.setMonospace(true);
        right_scrolled.setChild(right_view.as(gtk.Widget));
        right_scrolled.setVexpand(true);
        priv.right_view = right_view;

        right_box.append(right_label.as(gtk.Widget));
        right_box.append(right_command_entry.as(gtk.Widget));
        right_box.append(right_scrolled.as(gtk.Widget));

        // Comparison view
        const diff_box = gtk.Box.new(gtk.Orientation.vertical, 8);
        diff_box.setMarginStart(12);
        diff_box.setMarginEnd(12);
        diff_box.setMarginTop(12);
        diff_box.setMarginBottom(12);

        const diff_label = gtk.Label.new("Differences");
        diff_label.setXalign(0);
        diff_label.addCssClass("title-5");

        const diff_scrolled = gtk.ScrolledWindow.new();
        const diff_view = gtk.TextView.new();
        diff_view.setEditable(false);
        diff_view.setMonospace(true);
        diff_scrolled.setChild(diff_view.as(gtk.Widget));
        diff_scrolled.setVexpand(true);
        priv.diff_view = diff_view;

        const compare_btn = gtk.Button.new();
        compare_btn.setIconName("system-search-symbolic");
        compare_btn.setLabel("Compare");
        compare_btn.addCssClass("suggested-action");
        _ = compare_btn.connectClicked(&onCompare, self);
        priv.compare_btn = compare_btn;

        diff_box.append(diff_label.as(gtk.Widget));
        diff_box.append(compare_btn.as(gtk.Widget));
        diff_box.append(diff_scrolled.as(gtk.Widget));

        // Create vertical paned for comparison view
        const vertical_paned = gtk.Paned.new(gtk.Orientation.vertical);
        vertical_paned.setStartChild(left_box.as(gtk.Widget));
        vertical_paned.setEndChild(right_box.as(gtk.Widget));

        main_paned.setStartChild(vertical_paned.as(gtk.Widget));
        main_paned.setEndChild(diff_box.as(gtk.Widget));
        main_paned.setResizeEndChild(true);

        self.as(adw.Window).setContent(main_paned.as(gtk.Widget));
    }

    fn onCompare(_: *gtk.Button, self: *Self) callconv(.c) void {
        const priv = getPriv(self);
        // TODO: Compare outputs and show differences
        if (priv.left_view) |left| {
            if (priv.right_view) |right| {
                if (priv.diff_view) |diff| {
                    const left_buffer = left.getBuffer();
                    const right_buffer = right.getBuffer();
                    const diff_buffer = diff.getBuffer();

                    var start_iter: gtk.TextIter = undefined;
                    var end_iter: gtk.TextIter = undefined;
                    left_buffer.getStartIter(&start_iter);
                    left_buffer.getEndIter(&end_iter);
                    _ = left_buffer.getText(&start_iter, &end_iter, false);

                    right_buffer.getStartIter(&start_iter);
                    right_buffer.getEndIter(&end_iter);
                    _ = right_buffer.getText(&start_iter, &end_iter, false);

                    // TODO: Compute diff
                    diff_buffer.setText("Differences will be shown here", -1);
                    log.info("Comparing outputs", .{});
                }
            }
        }
    }

    pub fn setLeftOutput(self: *Self, output: []const u8) void {
        const priv = getPriv(self);
        if (priv.left_view) |view| {
            const buffer = view.getBuffer();
            buffer.setText(output, @intCast(output.len));
        }
    }

    pub fn setRightOutput(self: *Self, output: []const u8) void {
        const priv = getPriv(self);
        if (priv.right_view) |view| {
            const buffer = view.getBuffer();
            buffer.setText(output, @intCast(output.len));
        }
    }

    pub fn show(self: *Self, parent: *Window) void {
        self.as(adw.Window).setTransientFor(parent.as(gtk.Window));
        self.as(adw.Window).present();
    }
};
