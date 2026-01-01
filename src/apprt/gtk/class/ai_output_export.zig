//! Output Export Dialog UI
//! Provides Warp-like dialog for exporting command outputs to various formats

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

const log = std.log.scoped(.gtk_ghostty_output_export);

pub const OutputExportDialog = extern struct {
    const C = Common(Self, Private);
    pub const as = C.as;
    pub const ref = C.ref;
    pub const unref = C.unref;
    pub const refSink = C.refSink;
    const getPriv = C.getPriv;
    const Self = @This();

    parent_instance: Parent,
    pub const Parent = adw.MessageDialog;

    const Private = struct {
        format_dropdown: ?*gtk.DropDown = null,
        include_timestamp_toggle: ?*gtk.ToggleButton = null,
        include_command_toggle: ?*gtk.ToggleButton = null,
        file_chooser: ?*gtk.FileChooserNative = null,
        pub var offset: c_int = 0;
    };

    pub const ExportFormat = enum {
        text,
        json,
        csv,
        html,
        markdown,
        pdf,
    };

    pub const Class = extern struct {
        parent_class: Parent.Class,
        var parent: *Parent.Class = undefined;

        fn init(class: *Class) callconv(.c) void {
            gobject.Object.virtual_methods.dispose.implement(class, &dispose);
        }

        fn dispose(self: *Self) callconv(.c) void {
            const priv = getPriv(self);
            if (priv.file_chooser) |chooser| {
                chooser.unref();
                priv.file_chooser = null;
            }
            gobject.Object.virtual_methods.dispose.call(Class.parent, self.as(Parent));
        }

        pub const as = C.Class.as;
    };

    pub const getGObjectType = gobject.ext.defineClass(Self, .{
        .name = "GhosttyOutputExportDialog",
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
        self.as(adw.MessageDialog).setHeading("Export Output");
        self.as(adw.MessageDialog).setBody("Choose export format and options");

        // Create content area
        const content_area = self.as(adw.MessageDialog).getChild();
        const content_box = content_area.as(gtk.Box);

        const form_box = gtk.Box.new(gtk.Orientation.vertical, 12);
        form_box.setMarginStart(12);
        form_box.setMarginEnd(12);
        form_box.setMarginTop(12);
        form_box.setMarginBottom(12);

        // Format selection
        const format_row = gtk.Box.new(gtk.Orientation.horizontal, 12);
        const format_label = gtk.Label.new("Format:");
        format_label.setHalign(gtk.Align.start);
        format_label.setMinContentWidth(100);

        const format_store = gio.ListStore.new(gobject.Object.getGObjectType());
        const format_dropdown = gtk.DropDown.new(format_store.as(gio.ListModel), null);
        format_dropdown.setHexpand(true);
        priv.format_dropdown = format_dropdown;

        format_row.append(format_label.as(gtk.Widget));
        format_row.append(format_dropdown.as(gtk.Widget));

        // Options
        const include_timestamp_toggle = gtk.ToggleButton.new();
        include_timestamp_toggle.setLabel("Include Timestamp");
        include_timestamp_toggle.setActive(true);
        priv.include_timestamp_toggle = include_timestamp_toggle;

        const include_command_toggle = gtk.ToggleButton.new();
        include_command_toggle.setLabel("Include Command");
        include_command_toggle.setActive(true);
        priv.include_command_toggle = include_command_toggle;

        form_box.append(format_row.as(gtk.Widget));
        form_box.append(include_timestamp_toggle.as(gtk.Widget));
        form_box.append(include_command_toggle.as(gtk.Widget));

        content_box.append(form_box.as(gtk.Widget));

        // Add responses
        self.as(adw.MessageDialog).addResponse("cancel", "Cancel");
        self.as(adw.MessageDialog).addResponse("export", "Export");
        self.as(adw.MessageDialog).setDefaultResponse("export");
        self.as(adw.MessageDialog).setCloseResponse("cancel");

        _ = self.as(adw.MessageDialog).connectResponse(&onExportResponse, self);
    }

    fn onExportResponse(dialog: *adw.MessageDialog, response: [:0]const u8, self: *Self) callconv(.c) void {
        if (!std.mem.eql(u8, response, "export")) {
            dialog.close();
            return;
        }

        const priv = getPriv(self);
        // Show file chooser
        const file_chooser = gtk.FileChooserNative.new("Export Output", null, gtk.FileChooserAction.save, null, null);
        file_chooser.setModal(true);
        priv.file_chooser = file_chooser;

        _ = file_chooser.connectResponse(&onFileChooserResponse, self);
        file_chooser.show();
    }

    fn onFileChooserResponse(chooser: *gtk.FileChooserNative, response: c_int, self: *Self) callconv(.c) void {
        const priv = getPriv(self);
        if (response == gtk.ResponseType.accept) {
            if (chooser.getFile()) |file| {
                defer file.unref();
                // TODO: Export output to file
                log.info("Export to file", .{});
            }
        }
        chooser.unref();
        priv.file_chooser = null;
    }

    pub fn setOutput(self: *Self, output: []const u8) void {
        _ = self;
        _ = output;
        // TODO: Store output for export
    }

    pub fn show(self: *Self, parent: *Window) void {
        self.as(adw.MessageDialog).setTransientFor(parent.as(gtk.Window));
        self.as(adw.MessageDialog).present();
    }
};
