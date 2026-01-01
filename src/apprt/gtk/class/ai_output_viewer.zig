//! Command Output Viewer UI
//! Provides Warp-like enhanced command output viewer with syntax highlighting and line numbers

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

const log = std.log.scoped(.gtk_ghostty_output_viewer);

pub const OutputViewerDialog = extern struct {
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
        output_text: ?*gtk.TextView = null,
        line_numbers: ?*gtk.TextView = null,
        syntax_type_dropdown: ?*gtk.DropDown = null,
        wrap_toggle: ?*gtk.ToggleButton = null,
        line_numbers_toggle: ?*gtk.ToggleButton = null,
        copy_btn: ?*gtk.Button = null,
        export_btn: ?*gtk.Button = null,
        pub var offset: c_int = 0;
    };

    pub const SyntaxType = enum {
        plain,
        json,
        xml,
        yaml,
        toml,
        markdown,
        bash,
        python,
        javascript,
        html,
        css,
        sql,
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
        .name = "GhosttyOutputViewerDialog",
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
        self.as(adw.Window).setTitle("Output Viewer");
        self.as(adw.Window).setDefaultSize(900, 600);

        // Create main box
        const main_box = gtk.Box.new(gtk.Orientation.vertical, 12);
        main_box.setMarginStart(12);
        main_box.setMarginEnd(12);
        main_box.setMarginTop(12);
        main_box.setMarginBottom(12);

        // Create header bar
        const header = adw.HeaderBar.new();
        header.setTitleWidget(gtk.Label.new("Output Viewer"));

        // Create toolbar
        const toolbar = gtk.Box.new(gtk.Orientation.horizontal, 12);

        const syntax_label = gtk.Label.new("Syntax:");
        syntax_label.setHalign(gtk.Align.start);

        const syntax_store = gio.ListStore.new(gobject.Object.getGObjectType());
        // TODO: Populate with syntax types
        const syntax_dropdown = gtk.DropDown.new(syntax_store.as(gio.ListModel), null);
        syntax_dropdown.setHexpand(false);
        _ = syntax_dropdown.connectNotify("selected", &onSyntaxChanged, self);
        priv.syntax_type_dropdown = syntax_dropdown;

        const wrap_toggle = gtk.ToggleButton.new();
        wrap_toggle.setIconName("text-wrap-symbolic");
        wrap_toggle.setTooltipText("Wrap Text");
        wrap_toggle.setActive(true);
        _ = wrap_toggle.connectToggled(&onWrapToggled, self);
        priv.wrap_toggle = wrap_toggle;

        const line_numbers_toggle = gtk.ToggleButton.new();
        line_numbers_toggle.setIconName("view-list-symbolic");
        line_numbers_toggle.setTooltipText("Show Line Numbers");
        line_numbers_toggle.setActive(true);
        _ = line_numbers_toggle.connectToggled(&onLineNumbersToggled, self);
        priv.line_numbers_toggle = line_numbers_toggle;

        const copy_btn = gtk.Button.new();
        copy_btn.setIconName("edit-copy-symbolic");
        copy_btn.setTooltipText("Copy to Clipboard");
        copy_btn.addCssClass("flat");
        _ = copy_btn.connectClicked(&onCopyClicked, self);
        priv.copy_btn = copy_btn;

        const export_btn = gtk.Button.new();
        export_btn.setIconName("document-save-symbolic");
        export_btn.setTooltipText("Export Output");
        export_btn.addCssClass("flat");
        _ = export_btn.connectClicked(&onExportClicked, self);
        priv.export_btn = export_btn;

        toolbar.append(syntax_label.as(gtk.Widget));
        toolbar.append(syntax_dropdown.as(gtk.Widget));
        toolbar.append(wrap_toggle.as(gtk.Widget));
        toolbar.append(line_numbers_toggle.as(gtk.Widget));
        toolbar.append(copy_btn.as(gtk.Widget));
        toolbar.append(export_btn.as(gtk.Widget));

        // Create paned for line numbers and content
        const paned = gtk.Paned.new(gtk.Orientation.horizontal);

        // Line numbers view
        const line_numbers_scrolled = gtk.ScrolledWindow.new();
        const line_numbers_text = gtk.TextView.new();
        line_numbers_text.setEditable(false);
        line_numbers_text.setMonospace(true);
        line_numbers_text.addCssClass("line-numbers");
        line_numbers_scrolled.setChild(line_numbers_text.as(gtk.Widget));
        line_numbers_scrolled.setVexpand(true);
        line_numbers_scrolled.setHexpand(false);
        line_numbers_scrolled.setMinContentWidth(60);
        priv.line_numbers = line_numbers_text;

        // Output content view
        const output_scrolled = gtk.ScrolledWindow.new();
        const output_text = gtk.TextView.new();
        output_text.setEditable(false);
        output_text.setMonospace(true);
        output_text.setWrapMode(gtk.WrapMode.word);
        output_scrolled.setChild(output_text.as(gtk.Widget));
        output_scrolled.setVexpand(true);
        output_scrolled.setHexpand(true);
        priv.output_text = output_text;

        // Sync scrolling
        _ = output_scrolled.getVadjustment().connectValueChanged(&onOutputScrolled, self);

        paned.setStartChild(line_numbers_scrolled.as(gtk.Widget));
        paned.setEndChild(output_scrolled.as(gtk.Widget));
        paned.setResizeStartChild(false);
        paned.setResizeEndChild(true);
        paned.setShrinkStartChild(false);
        paned.setShrinkEndChild(false);

        main_box.append(toolbar.as(gtk.Widget));
        main_box.append(paned.as(gtk.Widget));

        self.as(adw.Window).setTitlebar(header.as(gtk.Widget));
        self.as(adw.Window).setContent(main_box.as(gtk.Widget));
    }

    fn onSyntaxChanged(_: *gobject.Object, _: glib.ParamSpec, self: *Self) callconv(.c) void {
        _ = self;
        // TODO: Apply syntax highlighting
        log.info("Syntax type changed", .{});
    }

    fn onWrapToggled(toggle: *gtk.ToggleButton, self: *Self) callconv(.c) void {
        const priv = getPriv(self);
        if (priv.output_text) |output| {
            if (toggle.getActive()) {
                output.setWrapMode(gtk.WrapMode.word);
            } else {
                output.setWrapMode(gtk.WrapMode.none);
            }
        }
    }

    fn onLineNumbersToggled(toggle: *gtk.ToggleButton, self: *Self) callconv(.c) void {
        const priv = getPriv(self);
        if (priv.line_numbers) |line_nums| {
            line_nums.as(gtk.Widget).setVisible(toggle.getActive());
            if (toggle.getActive()) {
                updateLineNumbers(self);
            }
        }
    }

    fn onOutputScrolled(adj: *gtk.Adjustment, self: *Self) callconv(.c) void {
        const priv = getPriv(self);
        // Sync line numbers scroll position
        if (priv.line_numbers) |line_nums| {
            if (line_nums.as(gtk.Widget).getParent()) |parent| {
                if (parent.as(gtk.ScrolledWindow).getVadjustment()) |line_adj| {
                    line_adj.setValue(adj.getValue());
                }
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

            const clipboard = self.as(adw.Window).as(gtk.Widget).getClipboard();
            clipboard.setText(text);
            log.info("Copied to clipboard", .{});
        }
    }

    fn onExportClicked(_: *gtk.Button, self: *Self) callconv(.c) void {
        _ = self;
        // TODO: Show export dialog
        log.info("Export output", .{});
    }

    fn updateLineNumbers(self: *Self) void {
        const priv = getPriv(self);
        if (priv.output_text) |output| {
            const buffer = output.getBuffer();
            const line_count = buffer.getLineCount();

            if (priv.line_numbers) |line_nums| {
                const line_buffer = line_nums.getBuffer();
                const alloc = Application.default().allocator();
                var line_text = std.ArrayList(u8).init(alloc);
                defer line_text.deinit();

                var i: i32 = 1;
                while (i <= line_count) : (i += 1) {
                    const line_str = std.fmt.allocPrint(alloc, "{d}\n", .{i}) catch continue;
                    defer alloc.free(line_str);
                    line_text.appendSlice(line_str) catch break;
                }

                if (line_text.items.len > 0) {
                    const text = alloc.dupeZ(u8, line_text.items) catch return;
                    defer alloc.free(text);
                    // Pass actual length for consistency with setOutput pattern
                    line_buffer.setText(text, @intCast(text.len));
                } else {
                    line_buffer.setText("", 0);
                }
            }
        }
    }

    pub fn setOutput(self: *Self, text: []const u8) void {
        const priv = getPriv(self);
        if (priv.output_text) |output| {
            const buffer = output.getBuffer();
            // Pass actual length instead of -1 to avoid relying on null-termination
            buffer.setText(text.ptr, @intCast(text.len));
            updateLineNumbers(self);
        }
    }

    pub fn show(self: *Self, parent: *Window) void {
        self.as(adw.Window).setTransientFor(parent.as(gtk.Window));
        self.as(adw.Window).present();
    }
};
