//! Smart Suggestions Panel UI
//! Provides Warp-like AI-powered command suggestions based on context

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

const log = std.log.scoped(.gtk_ghostty_smart_suggestions);

pub const SmartSuggestionsPanel = extern struct {
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
        suggestions_list: ?*gtk.ListView = null,
        suggestions_store: ?*gio.ListStore = null,
        refresh_btn: ?*gtk.Button = null,
        context_label: ?*gtk.Label = null,
        pub var offset: c_int = 0;
    };

    pub const SuggestionItem = extern struct {
        parent_instance: gobject.Object,
        command: [:0]const u8,
        description: [:0]const u8,
        confidence: f32,
        category: [:0]const u8,
        context_match: ?[:0]const u8 = null,

        pub const Parent = gobject.Object;

        pub const ItemClass = extern struct {
            parent_class: gobject.Object.Class,
            var parent: *gobject.Object.Class = undefined;

            fn init(class: *ItemClass) callconv(.c) void {
                gobject.Object.virtual_methods.dispose.implement(class, &SuggestionItem.dispose);
            }

            fn dispose(self: *SuggestionItem) callconv(.c) void {
                const alloc = Application.default().allocator();
                alloc.free(self.command);
                alloc.free(self.description);
                alloc.free(self.category);
                if (self.context_match) |match| alloc.free(match);
                gobject.Object.virtual_methods.dispose.call(ItemClass.parent, self);
            }
        };

        pub const getGObjectType = gobject.ext.defineClass(SuggestionItem, .{
            .name = "GhosttySuggestionItem",
            .classInit = &ItemClass.init,
            .parent_class = &ItemClass.parent,
        });

        pub fn new(alloc: Allocator, command: []const u8, description: []const u8, confidence: f32, category: []const u8) !*SuggestionItem {
            const self = gobject.ext.newInstance(SuggestionItem, .{});
            self.command = try alloc.dupeZ(u8, command);
            errdefer alloc.free(self.command);
            self.description = try alloc.dupeZ(u8, description);
            errdefer alloc.free(self.description);
            self.confidence = confidence;
            self.category = try alloc.dupeZ(u8, category);
            errdefer alloc.free(self.category);
            return self;
        }

        pub fn deinit(self: *SuggestionItem, alloc: Allocator) void {
            alloc.free(self.command);
            alloc.free(self.description);
            alloc.free(self.category);
            if (self.context_match) |match| alloc.free(match);
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
            if (priv.suggestions_store) |store| {
                store.removeAll();
            }
            gobject.Object.virtual_methods.dispose.call(Class.parent, self.as(Parent));
        }

        pub const as = C.Class.as;
    };

    pub const getGObjectType = gobject.ext.defineClass(Self, .{
        .name = "GhosttySmartSuggestionsPanel",
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
        self.as(adw.NavigationView).setTitle("Smart Suggestions");

        // Create suggestions store
        const store = gio.ListStore.new(SuggestionItem.getGObjectType());
        priv.suggestions_store = store;

        // Create main box
        const main_box = gtk.Box.new(gtk.Orientation.vertical, 12);
        main_box.setMarginStart(12);
        main_box.setMarginEnd(12);
        main_box.setMarginTop(12);
        main_box.setMarginBottom(12);

        // Create toolbar
        const toolbar = gtk.Box.new(gtk.Orientation.horizontal, 12);

        const context_label = gtk.Label.new("Context: Current directory");
        context_label.setXalign(0);
        context_label.addCssClass("dim-label");
        priv.context_label = context_label;

        const refresh_btn = gtk.Button.new();
        refresh_btn.setIconName("view-refresh-symbolic");
        refresh_btn.setTooltipText("Refresh Suggestions");
        _ = refresh_btn.connectClicked(&onRefresh, self);
        priv.refresh_btn = refresh_btn;

        toolbar.append(context_label.as(gtk.Widget));
        toolbar.append(refresh_btn.as(gtk.Widget));

        // Create list view
        const factory = gtk.SignalListItemFactory.new();
        factory.connectSetup(&setupSuggestionItem, null);
        factory.connectBind(&bindSuggestionItem, null);

        const selection = gtk.SingleSelection.new(store.as(gio.ListModel));
        const list_view = gtk.ListView.new(selection.as(gtk.SelectionModel), factory);
        list_view.setSingleClickActivate(true);
        _ = list_view.connectActivate(&onSuggestionActivated, self);
        priv.suggestions_list = list_view;

        // Create scrolled window
        const scrolled = gtk.ScrolledWindow.new();
        scrolled.setChild(list_view.as(gtk.Widget));
        scrolled.setVexpand(true);

        main_box.append(toolbar.as(gtk.Widget));
        main_box.append(scrolled.as(gtk.Widget));

        const page = adw.NavigationPage.new("Smart Suggestions", main_box.as(gtk.Widget));
        self.as(adw.NavigationView).push(page);

        // Load suggestions
        loadSuggestions(self);
    }

    fn setupSuggestionItem(_: *gtk.SignalListItemFactory, item: *gtk.ListItem, _: ?*anyopaque) callconv(.c) void {
        const card = gtk.Box.new(gtk.Orientation.vertical, 8);
        card.setMarginStart(12);
        card.setMarginEnd(12);
        card.setMarginTop(6);
        card.setMarginBottom(6);
        card.addCssClass("suggestion-card");

        const header_box = gtk.Box.new(gtk.Orientation.horizontal, 12);

        const confidence_bar = gtk.ProgressBar.new();
        confidence_bar.setMinContentWidth(60);
        confidence_bar.setShowText(false);

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

        const category_label = gtk.Label.new("");
        category_label.setXalign(0);
        category_label.addCssClass("caption");
        category_label.addCssClass("dim-label");

        info_box.append(command_label.as(gtk.Widget));
        info_box.append(desc_label.as(gtk.Widget));
        info_box.append(category_label.as(gtk.Widget));

        header_box.append(confidence_bar.as(gtk.Widget));
        header_box.append(info_box.as(gtk.Widget));

        const action_box = gtk.Box.new(gtk.Orientation.horizontal, 4);
        const use_btn = gtk.Button.new();
        use_btn.setLabel("Use");
        use_btn.addCssClass("suggested-action");
        use_btn.addCssClass("flat");

        action_box.append(use_btn.as(gtk.Widget));

        card.append(header_box.as(gtk.Widget));
        card.append(action_box.as(gtk.Widget));

        item.setChild(card.as(gtk.Widget));

        // Connect signal handler once during setup
        _ = use_btn.connectClicked(&onUseSuggestionListItem, item);
    }

    fn bindSuggestionItem(_: *gtk.SignalListItemFactory, item: *gtk.ListItem, _: ?*anyopaque) callconv(.c) void {
        const entry = item.getItem() orelse return;
        const suggestion_item = @as(*SuggestionItem, @ptrCast(@alignCast(entry)));
        const card = item.getChild() orelse return;
        const card_widget = card.as(gtk.Box);

        if (card_widget.getFirstChild()) |header_box| {
            if (header_box.as(gtk.Box).getFirstChild()) |confidence_bar| {
                confidence_bar.as(gtk.ProgressBar).setFraction(suggestion_item.confidence);
                if (confidence_bar.getNextSibling()) |info_box| {
                    if (info_box.as(gtk.Box).getFirstChild()) |command| {
                        command.as(gtk.Label).setText(suggestion_item.command);
                        if (command.getNextSibling()) |desc| {
                            desc.as(gtk.Label).setText(suggestion_item.description);
                            if (desc.getNextSibling()) |category| {
                                category.as(gtk.Label).setText(suggestion_item.category);
                            }
                        }
                    }
                }
            }
        }
    }

    fn onRefresh(_: *gtk.Button, self: *Self) callconv(.c) void {
        _ = self;
        // TODO: Refresh suggestions based on current context
        log.info("Refresh suggestions", .{});
    }

    fn onSuggestionActivated(_: *gtk.ListView, position: u32, self: *Self) callconv(.c) void {
        const priv = getPriv(self);
        if (priv.suggestions_store) |store| {
            if (store.getItem(position)) |item| {
                const suggestion_item: *SuggestionItem = @ptrCast(@alignCast(item));
                // TODO: Use suggestion
                log.info("Suggestion activated: {s}", .{suggestion_item.command});
            }
        }
    }

    fn onUseSuggestionListItem(_: *gtk.Button, list_item: *gtk.ListItem) callconv(.c) void {
        const entry = list_item.getItem() orelse return;
        const suggestion_item = @as(*SuggestionItem, @ptrCast(@alignCast(entry)));
        // TODO: Insert command into terminal
        log.info("Use suggestion: {s}", .{suggestion_item.command});
    }

    fn loadSuggestions(_: *Self) void {
        // TODO: Load AI-powered suggestions based on context
        log.info("Loading smart suggestions...", .{});
    }

    pub fn show(self: *Self, parent: *Window) void {
        self.as(adw.NavigationView).setTransientFor(parent.as(gtk.Window));
        self.as(adw.NavigationView).present();
    }
};
