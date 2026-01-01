//! Output Formatting UI
//! Provides Warp-like output formatting/beautification for command outputs

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

const log = std.log.scoped(.gtk_ghostty_output_formatting);

pub const OutputFormattingDialog = extern struct {
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
        input_text: ?*gtk.TextView = null,
        output_text: ?*gtk.TextView = null,
        format_dropdown: ?*gtk.DropDown = null,
        format_btn: ?*gtk.Button = null,
        copy_btn: ?*gtk.Button = null,
        pub var offset: c_int = 0;
    };

    pub const FormatType = enum {
        json,
        xml,
        yaml,
        toml,
        csv,
        sql,
        html,
        css,
        javascript,
        python,
        bash,
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
        .name = "GhosttyOutputFormattingDialog",
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
        self.as(adw.Window).setTitle("Output Formatting");
        self.as(adw.Window).setDefaultSize(900, 600);

        // Create main box
        const main_box = gtk.Box.new(gtk.Orientation.vertical, 12);
        main_box.setMarginStart(12);
        main_box.setMarginEnd(12);
        main_box.setMarginTop(12);
        main_box.setMarginBottom(12);

        // Create header bar
        const header = adw.HeaderBar.new();
        header.setTitleWidget(gtk.Label.new("Format Output"));

        // Create format selection
        const format_box = gtk.Box.new(gtk.Orientation.horizontal, 12);
        const format_label = gtk.Label.new("Format:");
        format_label.setHalign(gtk.Align.start);

        const format_store = gio.ListStore.new(gobject.Object.getGObjectType());
        // TODO: Populate with format types
        const format_dropdown = gtk.DropDown.new(format_store.as(gobject.Object), null);
        format_dropdown.setHexpand(true);
        priv.format_dropdown = format_dropdown;

        const format_btn = gtk.Button.new();
        format_btn.setLabel("Format");
        format_btn.addCssClass("suggested-action");
        _ = format_btn.connectClicked(&onFormatClicked, self);
        priv.format_btn = format_btn;

        format_box.append(format_label.as(gtk.Widget));
        format_box.append(format_dropdown.as(gtk.Widget));
        format_box.append(format_btn.as(gtk.Widget));

        // Create paned for input/output
        const paned = gtk.Paned.new(gtk.Orientation.horizontal);

        // Input section
        const input_box = gtk.Box.new(gtk.Orientation.vertical, 6);
        const input_label = gtk.Label.new("Input");
        input_label.setHalign(gtk.Align.start);
        input_label.addCssClass("title-5");

        const input_scrolled = gtk.ScrolledWindow.new();
        const input_text = gtk.TextView.new();
        input_text.setWrapMode(gtk.WrapMode.word);
        input_text.setMonospace(true);
        input_scrolled.setChild(input_text.as(gtk.Widget));
        input_scrolled.setVexpand(true);
        priv.input_text = input_text;

        input_box.append(input_label.as(gtk.Widget));
        input_box.append(input_scrolled.as(gtk.Widget));

        // Output section
        const output_box = gtk.Box.new(gtk.Orientation.vertical, 6);
        const output_header = gtk.Box.new(gtk.Orientation.horizontal, 6);
        const output_label = gtk.Label.new("Formatted Output");
        output_label.setHalign(gtk.Align.start);
        output_label.addCssClass("title-5");

        const copy_btn = gtk.Button.new();
        copy_btn.setIconName("edit-copy-symbolic");
        copy_btn.setTooltipText("Copy to Clipboard");
        copy_btn.addCssClass("flat");
        _ = copy_btn.connectClicked(&onCopyClicked, self);
        priv.copy_btn = copy_btn;

        output_header.append(output_label.as(gtk.Widget));
        output_header.append(copy_btn.as(gtk.Widget));

        const output_scrolled = gtk.ScrolledWindow.new();
        const output_text = gtk.TextView.new();
        output_text.setWrapMode(gtk.WrapMode.word);
        output_text.setMonospace(true);
        output_text.setEditable(false);
        output_scrolled.setChild(output_text.as(gtk.Widget));
        output_scrolled.setVexpand(true);
        priv.output_text = output_text;

        output_box.append(output_header.as(gtk.Widget));
        output_box.append(output_scrolled.as(gtk.Widget));

        paned.setStartChild(input_box.as(gtk.Widget));
        paned.setEndChild(output_box.as(gtk.Widget));
        paned.setResizeStartChild(true);
        paned.setResizeEndChild(true);
        paned.setShrinkStartChild(false);
        paned.setShrinkEndChild(false);

        main_box.append(format_box.as(gtk.Widget));
        main_box.append(paned.as(gtk.Widget));

        self.as(adw.Window).setTitlebar(header.as(gtk.Widget));
        self.as(adw.Window).setContent(main_box.as(gtk.Widget));
    }

    fn onFormatClicked(_: *gtk.Button, self: *Self) callconv(.c) void {
        const priv = getPriv(self);
        if (priv.input_text) |input| {
            const buffer = input.getBuffer();
            const start_iter = buffer.getStartIter();
            const end_iter = buffer.getEndIter();
            const text = buffer.getText(start_iter, end_iter, false);
            defer glib.free(text);

            // TODO: Detect format type and format accordingly
            const formatted = formatOutput(text, FormatType.json) catch |err| {
                log.err("Failed to format output: {}", .{err});
                return;
            };
            defer glib.free(formatted);

            if (priv.output_text) |output| {
                const out_buffer = output.getBuffer();
                out_buffer.setText(formatted, -1);
            }
        }
    }

    fn onCopyClicked(_: *gtk.Button, self: *Self) callconv(.c) void {
        const priv = getPriv(self);
        if (priv.output_text) |output| {
            const buffer = output.getBuffer();
            const start_iter = buffer.getStartIter();
            const end_iter = buffer.getEndIter();
            const text = buffer.getText(start_iter, end_iter, false);
            defer glib.free(text);

            // TODO: Copy to clipboard
            log.info("Copy to clipboard: {s}", .{text});
        }
    }

    fn formatOutput(text: []const u8, format_type: FormatType) ![:0]u8 {
        _ = format_type;
        // TODO: Implement actual formatting logic
        // For now, just return the text as-is
        // Use glib.strdup to allocate with GLib allocator, since caller uses glib.free()
        const result = glib.strdup(text) orelse return error.OutOfMemory;
        return result;
    }

    pub fn setInput(self: *Self, text: []const u8) void {
        const priv = getPriv(self);
        if (priv.input_text) |input| {
            const buffer = input.getBuffer();
            buffer.setText(text, -1);
        }
    }

    pub fn show(self: *Self, parent: *Window) void {
        self.as(adw.Window).setTransientFor(parent.as(gtk.Window));
        self.as(adw.Window).present();
    }
};
