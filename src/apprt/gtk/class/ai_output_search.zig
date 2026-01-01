//! Command Output Search UI
//! Provides Warp-like search functionality within command outputs

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

const log = std.log.scoped(.gtk_ghostty_output_search);

pub const OutputSearchDialog = extern struct {
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
        search_entry: ?*gtk.SearchEntry = null,
        output_text: ?*gtk.TextView = null,
        results_list: ?*gtk.ListView = null,
        results_store: ?*gio.ListStore = null,
        match_count_label: ?*gtk.Label = null,
        case_sensitive_toggle: ?*gtk.ToggleButton = null,
        regex_toggle: ?*gtk.ToggleButton = null,
        next_btn: ?*gtk.Button = null,
        prev_btn: ?*gtk.Button = null,
        current_match_index: u32 = 0,
        pub var offset: c_int = 0;
    };

    pub const SearchResultItem = extern struct {
        parent_instance: gobject.Object,
        line_number: u32,
        line_content: [:0]const u8,
        match_start: u32,
        match_end: u32,

        pub const Parent = gobject.Object;

        pub const ItemClass = extern struct {
            parent_class: gobject.Object.Class,
            var parent: *gobject.Object.Class = undefined;

            fn init(class: *ItemClass) callconv(.c) void {
                gobject.Object.virtual_methods.dispose.implement(class, &SearchResultItem.dispose);
            }

            fn dispose(self: *SearchResultItem) callconv(.c) void {
                const alloc = Application.default().allocator();
                if (self.line_content.len > 0) {
                    alloc.free(self.line_content);
                    self.line_content = "";
                }
                gobject.Object.virtual_methods.dispose.call(ItemClass.parent, self);
            }
        };

        pub const getGObjectType = gobject.ext.defineClass(SearchResultItem, .{
            .name = "GhosttySearchResultItem",
            .classInit = &ItemClass.init,
            .parent_class = &ItemClass.parent,
        });

        pub fn new(alloc: Allocator, line_number: u32, line_content: []const u8, match_start: u32, match_end: u32) !*SearchResultItem {
            const self = gobject.ext.newInstance(SearchResultItem, .{});
            self.line_number = line_number;
            self.match_start = match_start;
            self.match_end = match_end;
            self.line_content = "";
            errdefer self.unref();

            self.line_content = try alloc.dupeZ(u8, line_content);
            return self;
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

            if (priv.results_store) |store| {
                store.removeAll();
            }

            gobject.Object.virtual_methods.dispose.call(Class.parent, self.as(Parent));
        }

        pub const as = C.Class.as;
    };

    pub const getGObjectType = gobject.ext.defineClass(Self, .{
        .name = "GhosttyOutputSearchDialog",
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
        self.as(adw.Window).setTitle("Output Search");
        self.as(adw.Window).setDefaultSize(800, 500);

        // Create results store
        const store = gio.ListStore.new(SearchResultItem.getGObjectType());
        priv.results_store = store;

        // Create main box
        const main_box = gtk.Box.new(gtk.Orientation.vertical, 12);
        main_box.setMarginStart(12);
        main_box.setMarginEnd(12);
        main_box.setMarginTop(12);
        main_box.setMarginBottom(12);

        // Create search toolbar
        const search_box = gtk.Box.new(gtk.Orientation.horizontal, 12);

        const search_entry = gtk.SearchEntry.new();
        search_entry.setPlaceholderText("Search in output...");
        search_entry.setHexpand(true);
        _ = search_entry.connectSearchChanged(&onSearchChanged, self);
        _ = search_entry.connectNextMatch(&onNextMatch, self);
        _ = search_entry.connectPreviousMatch(&onPreviousMatch, self);
        priv.search_entry = search_entry;

        const case_sensitive_toggle = gtk.ToggleButton.new();
        case_sensitive_toggle.setIconName("format-text-symbolic");
        case_sensitive_toggle.setTooltipText("Case Sensitive");
        case_sensitive_toggle.addCssClass("flat");
        _ = case_sensitive_toggle.connectToggled(&onCaseSensitiveToggled, self);
        priv.case_sensitive_toggle = case_sensitive_toggle;

        const regex_toggle = gtk.ToggleButton.new();
        regex_toggle.setIconName("code-symbolic");
        regex_toggle.setTooltipText("Regular Expression");
        regex_toggle.addCssClass("flat");
        _ = regex_toggle.connectToggled(&onRegexToggled, self);
        priv.regex_toggle = regex_toggle;

        const next_btn = gtk.Button.new();
        next_btn.setIconName("go-down-symbolic");
        next_btn.setTooltipText("Next Match");
        next_btn.addCssClass("flat");
        _ = next_btn.connectClicked(&onNextMatch, self);
        priv.next_btn = next_btn;

        const prev_btn = gtk.Button.new();
        prev_btn.setIconName("go-up-symbolic");
        prev_btn.setTooltipText("Previous Match");
        prev_btn.addCssClass("flat");
        _ = prev_btn.connectClicked(&onPreviousMatch, self);
        priv.prev_btn = prev_btn;

        const match_count_label = gtk.Label.new("0 matches");
        match_count_label.addCssClass("dim-label");
        priv.match_count_label = match_count_label;

        search_box.append(search_entry.as(gtk.Widget));
        search_box.append(case_sensitive_toggle.as(gtk.Widget));
        search_box.append(regex_toggle.as(gtk.Widget));
        search_box.append(prev_btn.as(gtk.Widget));
        search_box.append(next_btn.as(gtk.Widget));
        search_box.append(match_count_label.as(gtk.Widget));

        // Create paned for output and results
        const paned = gtk.Paned.new(gtk.Orientation.horizontal);

        // Output view
        const output_scrolled = gtk.ScrolledWindow.new();
        const output_text = gtk.TextView.new();
        output_text.setEditable(false);
        output_text.setMonospace(true);
        output_text.setWrapMode(gtk.WrapMode.word);
        output_scrolled.setChild(output_text.as(gtk.Widget));
        output_scrolled.setVexpand(true);
        output_scrolled.setHexpand(true);
        priv.output_text = output_text;

        // Results list
        const results_scrolled = gtk.ScrolledWindow.new();
        const factory = gtk.SignalListItemFactory.new();
        factory.connectSetup(&setupResultItem, null);
        factory.connectBind(&bindResultItem, null);

        const selection = gtk.SingleSelection.new(store.as(gio.ListModel));
        const results_list = gtk.ListView.new(selection.as(gtk.SelectionModel), factory);
        results_list.setSingleClickActivate(true);
        _ = results_list.connectActivate(&onResultActivated, self);
        priv.results_list = results_list;

        results_scrolled.setChild(results_list.as(gtk.Widget));
        results_scrolled.setVexpand(true);
        results_scrolled.setHexpand(false);
        results_scrolled.setMinContentWidth(300);

        paned.setStartChild(output_scrolled.as(gtk.Widget));
        paned.setEndChild(results_scrolled.as(gtk.Widget));
        paned.setResizeStartChild(true);
        paned.setResizeEndChild(false);
        paned.setShrinkStartChild(false);
        paned.setShrinkEndChild(false);

        main_box.append(search_box.as(gtk.Widget));
        main_box.append(paned.as(gtk.Widget));

        self.as(adw.Window).setContent(main_box.as(gtk.Widget));
    }

    fn setupResultItem(_: *gtk.SignalListItemFactory, item: *gtk.ListItem, _: ?*anyopaque) callconv(.c) void {
        const box = gtk.Box.new(gtk.Orientation.horizontal, 12);
        box.setMarginStart(12);
        box.setMarginEnd(12);
        box.setMarginTop(4);
        box.setMarginBottom(4);

        const line_label = gtk.Label.new("");
        line_label.addCssClass("monospace");
        line_label.addCssClass("dim-label");
        line_label.setHalign(gtk.Align.end);
        line_label.setMinWidthChars(4);

        const content_label = gtk.Label.new("");
        content_label.setXalign(0);
        content_label.setSelectable(true);
        content_label.setWrap(true);
        content_label.setHexpand(true);

        box.append(line_label.as(gtk.Widget));
        box.append(content_label.as(gtk.Widget));

        item.setChild(box.as(gtk.Widget));
    }

    fn bindResultItem(_: *gtk.SignalListItemFactory, item: *gtk.ListItem, _: ?*anyopaque) callconv(.c) void {
        const entry = item.getItem() orelse return;
        const result_item = @as(*SearchResultItem, @ptrCast(@alignCast(entry)));
        const box = item.getChild() orelse return;
        const box_widget = box.as(gtk.Box);

        if (box_widget.getFirstChild()) |line_label| {
            var line_buf: [32]u8 = undefined;
            const line_text = std.fmt.bufPrintZ(&line_buf, "{d}", .{result_item.line_number}) catch "0";
            line_label.as(gtk.Label).setText(line_text);
            if (line_label.getNextSibling()) |content_label| {
                content_label.as(gtk.Label).setText(result_item.line_content);
            }
        }
    }

    fn onSearchChanged(entry: *gtk.SearchEntry, self: *Self) callconv(.c) void {
        const priv = getPriv(self);
        const query = entry.getText();
        if (priv.output_text) |output| {
            performSearch(self, query, output);
        }
    }

    fn onCaseSensitiveToggled(toggle: *gtk.ToggleButton, self: *Self) callconv(.c) void {
        _ = toggle;
        const priv = getPriv(self);
        if (priv.search_entry) |entry| {
            if (priv.output_text) |output| {
                performSearch(self, entry.getText(), output);
            }
        }
    }

    fn onRegexToggled(toggle: *gtk.ToggleButton, self: *Self) callconv(.c) void {
        _ = toggle;
        const priv = getPriv(self);
        if (priv.search_entry) |entry| {
            if (priv.output_text) |output| {
                performSearch(self, entry.getText(), output);
            }
        }
    }

    fn onNextMatch(_: *gtk.Button, self: *Self) callconv(.c) void {
        const priv = getPriv(self);
        if (priv.results_store) |store| {
            const n = store.getNItems();
            if (n == 0) return;
            priv.current_match_index = (priv.current_match_index + 1) % n;
            if (store.getItem(priv.current_match_index)) |item| {
                const result_item: *SearchResultItem = @ptrCast(@alignCast(item));
                scrollToLine(self, result_item.line_number);
            }
        }
    }

    fn onPreviousMatch(_: *gtk.Button, self: *Self) callconv(.c) void {
        const priv = getPriv(self);
        if (priv.results_store) |store| {
            const n = store.getNItems();
            if (n == 0) return;
            priv.current_match_index = if (priv.current_match_index == 0) n - 1 else priv.current_match_index - 1;
            if (store.getItem(priv.current_match_index)) |item| {
                const result_item: *SearchResultItem = @ptrCast(@alignCast(item));
                scrollToLine(self, result_item.line_number);
            }
        }
    }

    fn scrollToLine(self: *Self, line_number: u32) void {
        const priv = getPriv(self);
        if (priv.output_text) |output| {
            const buffer = output.getBuffer();
            const iter = buffer.getIterAtLine(@intCast(line_number - 1));
            buffer.selectRange(iter, iter);
            output.scrollToIter(iter, 0.0, false, 0.0, 0.0);
        }
    }

    fn onResultActivated(_: *gtk.ListView, position: u32, self: *Self) callconv(.c) void {
        const priv = getPriv(self);
        if (priv.results_store) |store| {
            if (store.getItem(position)) |item| {
                const result_item: *SearchResultItem = @ptrCast(@alignCast(item));
                priv.current_match_index = position;
                scrollToLine(self, result_item.line_number);
            }
        }
    }

    fn performSearch(self: *Self, query: []const u8, output: *gtk.TextView) void {
        const priv = getPriv(self);
        const alloc = Application.default().allocator();

        // Clear existing results
        if (priv.results_store) |store| {
            store.removeAll();
        }

        if (query.len == 0) {
            if (priv.match_count_label) |label| {
                label.setText("0 matches");
            }
            return;
        }

        // Get output text
        const buffer = output.getBuffer();
        const start_iter = buffer.getStartIter();
        const end_iter = buffer.getEndIter();
        const text = buffer.getText(start_iter, end_iter, false);
        defer glib.free(text);

        if (text.len == 0) {
            if (priv.match_count_label) |label| {
                label.setText("0 matches");
            }
            return;
        }

        // Perform search
        const case_sensitive = if (priv.case_sensitive_toggle) |toggle| toggle.getActive() else false;
        const use_regex = if (priv.regex_toggle) |toggle| toggle.getActive() else false;

        var match_count: u32 = 0;
        var line_number: u32 = 1;
        var line_start: usize = 0;

        var i: usize = 0;
        while (i < text.len) : (i += 1) {
            if (text[i] == '\n') {
                const line = text[line_start..i];
                if (line.len > 0) {
                    const match_start = if (use_regex) blk: {
                        // Simple regex matching - just check if query appears
                        break :blk std.mem.indexOf(u8, line, query);
                    } else blk: {
                        if (case_sensitive) {
                            break :blk std.mem.indexOf(u8, line, query);
                        } else {
                            // Case-insensitive search
                            var j: usize = 0;
                            while (j + query.len <= line.len) : (j += 1) {
                                const slice = line[j .. j + query.len];
                                if (std.ascii.eqlIgnoreCase(slice, query)) {
                                    break :blk j;
                                }
                            }
                            break :blk null;
                        }
                    };

                    if (match_start) |start| {
                        const match_end = start + query.len;
                        const result_item = SearchResultItem.new(alloc, line_number, line, @intCast(start), @intCast(match_end)) catch continue;
                        if (priv.results_store) |store| {
                            store.append(result_item.as(gobject.Object));
                        }
                        match_count += 1;
                    }
                }
                line_number += 1;
                line_start = i + 1;
            }
        }

        // Handle last line if no newline at end
        if (line_start < text.len) {
            const line = text[line_start..];
            if (line.len > 0) {
                const match_start = if (case_sensitive)
                    std.mem.indexOf(u8, line, query)
                else blk: {
                    var j: usize = 0;
                    while (j + query.len <= line.len) : (j += 1) {
                        const slice = line[j .. j + query.len];
                        if (std.ascii.eqlIgnoreCase(slice, query)) {
                            break :blk j;
                        }
                    }
                    break :blk null;
                };

                if (match_start) |start| {
                    const match_end = start + query.len;
                    const result_item = SearchResultItem.new(alloc, line_number, line, @intCast(start), @intCast(match_end)) catch {};
                    if (priv.results_store) |store| {
                        store.append(result_item.as(gobject.Object));
                    }
                    match_count += 1;
                }
            }
        }

        // Update match count label
        if (priv.match_count_label) |label| {
            var count_buf: [64]u8 = undefined;
            const suffix: []const u8 = if (match_count == 1) "" else "es";
            const count_text = std.fmt.bufPrintZ(&count_buf, "{d} match{s}", .{ match_count, suffix }) catch "0 matches";
            label.setText(count_text);
        }
    }

    pub fn setOutput(self: *Self, text: []const u8) void {
        const priv = getPriv(self);
        if (priv.output_text) |output| {
            const buffer = output.getBuffer();
            // Pass actual length instead of -1 to avoid relying on null-termination
            buffer.setText(text.ptr, @intCast(text.len));
        }
    }

    pub fn show(self: *Self, parent: *Window) void {
        self.as(adw.Window).setTransientFor(parent.as(gtk.Window));
        self.as(adw.Window).present();
    }
};
