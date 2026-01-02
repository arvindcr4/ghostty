// src/terminfo/main_test.zig
const std = @import("std");
const testing = std.testing;
const terminfo = @import("main.zig");
const Source = @import("Source.zig");
const Ghostty = @import("ghostty.zig");

test "terminfo database loading" {
    const allocator = testing.allocator;
    
    var db = try terminfo.Database.init(allocator);
    defer db.deinit();
    
    // Test loading default database
    try db.loadDefault();
    try testing.expect(db.isLoaded());
    
    // Test loading from path
    var db2 = try terminfo.Database.init(allocator);
    defer db2.deinit();
    try db2.loadFromPath("/usr/share/terminfo");
    try testing.expect(db2.isLoaded());
}

test "terminal capability lookup" {
    const allocator = testing.allocator;
    
    var db = try terminfo.Database.init(allocator);
    defer db.deinit();
    try db.loadDefault();
    
    // Test boolean capabilities
    const has_colors = try db.getBoolean("colors");
    try testing.expect(has_colors);
    
    const has_bell = try db.getBoolean("bel");
    try testing.expect(has_bell);
    
    // Test numeric capabilities
    const max_colors = try db.getNumber("colors");
    try testing.expect(max_colors > 0);
    
    const columns = try db.getNumber("cols");
    try testing.expect(columns > 0);
    
    // Test string capabilities
    const clear_screen = try db.getString("clear");
    try testing.expect(clear_screen.len > 0);
    
    const cursor_address = try db.getString("cup");
    try testing.expect(cursor_address.len > 0);
}

test "terminal type detection" {
    const allocator = testing.allocator;
    
    var db = try terminfo.Database.init(allocator);
    defer db.deinit();
    try db.loadDefault();
    
    // Test known terminal types
    const term_types = [_][]const u8{ "xterm-256color", "screen", "tmux", "ghostty" };
    
    for (term_types) |term_type| {
        const entry = try db.getEntry(term_type);
        try testing.expect(entry != null);
        try testing.expectEqualStrings(term_type, entry.?.name);
    }
    
    // Test unknown terminal type
    const unknown_entry = try db.getEntry("unknown-terminal");
    try testing.expect(unknown_entry == null);
}

test "capability string validation" {
    const allocator = testing.allocator;
    
    var db = try terminfo.Database.init(allocator);
    defer db.deinit();
    try db.loadDefault();
    
    // Test parameterized capabilities
    const cursor_address = try db.getString("cup");
    try testing.expect(std.mem.indexOf(u8, cursor_address, "%p1") != null);
    try testing.expect(std.mem.indexOf(u8, cursor_address, "%p2") != null);
    
    // Test escape sequences
    const clear_screen = try db.getString("clear");
    try testing.expect(clear_screen[0] == '\x1b');
    
    // Test color capabilities
    const set_foreground = try db.getString("setaf");
    if (set_foreground.len > 0) {
        try testing.expect(std.mem.indexOf(u8, set_foreground, "%p1") != null);
    }
}

test "fallback handling" {
    const allocator = testing.allocator;
    
    var db = try terminfo.Database.init(allocator);
    defer db.deinit();
    try db.loadDefault();
    
    // Test fallback to similar terminal types
    const entry = try db.getEntryWithFallback("xterm-truecolor");
    try testing.expect(entry != null);
    
    // Should fallback to xterm-256color or similar
    try testing.expect(std.mem.startsWith(u8, entry.?.name, "xterm"));
}

test "terminfo entry properties" {
    const allocator = testing.allocator;
    
    var db = try terminfo.Database.init(allocator);
    defer db.deinit();
    try db.loadDefault();
    
    const entry = try db.getEntry("xterm-256color");
    try testing.expect(entry != null);
    
    // Test entry metadata
    try testing.expect(entry.?.aliases.len > 0);
    try testing.expect(entry.?.description.len > 0);
    try testing.expect(entry.?.boolean_count > 0);
    try testing.expect(entry.?.numeric_count > 0);
    try testing.expect(entry.?.string_count > 0);
}

test "terminfo capability enumeration" {
    const allocator = testing.allocator;
    
    var db = try terminfo.Database.init(allocator);
    defer db.deinit();
    try db.loadDefault();
    
    // Test enumerating all capabilities
    var bool_iter = db.iterBoolean();
    var bool_count: usize = 0;
    while (bool_iter.next()) |cap| {
        bool_count += 1;
        try testing.expect(cap.name.len > 0);
    }
    try testing.expect(bool_count > 0);
    
    var num_iter = db.iterNumeric();
    var num_count: usize = 0;
    while (num_iter.next()) |cap| {
        num_count += 1;
        try testing.expect(cap.name.len > 0);
    }
    try testing.expect(num_count > 0);
    
    var str_iter = db.iterString();
    var str_count: usize = 0;
    while (str_iter.next()) |cap| {
        str_count += 1;
        try testing.expect(cap.name.len > 0);
    }
    try testing.expect(str_count > 0);
}

test "terminfo error handling" {
    const allocator = testing.allocator;
    
    // Test invalid database path
    var db = try terminfo.Database.init(allocator);
    defer db.deinit();
    
    try testing.expectError(error.FileNotFound, db.loadFromPath("/nonexistent/path"));
    
    // Test invalid capability names
    try db.loadDefault();
    try testing.expectError(error.CapabilityNotFound, db.getBoolean("invalid-cap"));
    try testing.expectError(error.CapabilityNotFound, db.getNumber("invalid-cap"));
    try testing.expectError(error.CapabilityNotFound, db.getString("invalid-cap"));
}

test "terminfo memory management" {
    const allocator = testing.allocator;
    
    // Test multiple database instances
    var databases: [10]terminfo.Database = undefined;
    for (&databases) |*db| {
        db.* = try terminfo.Database.init(allocator);
        try db.loadDefault();
    }
    
    for (&databases) |*db| {
        db.deinit();
    }
}

test "terminfo thread safety" {
    const allocator = testing.allocator;
    
    var db = try terminfo.Database.init(allocator);
    defer db.deinit();
    try db.loadDefault();
    
    // Test concurrent access
    const Thread = std.Thread;
    var threads: [4]Thread = undefined;
    
    for (&threads) |*thread| {
        thread.* = try Thread.spawn(.{}, struct {
            db: *terminfo.Database,
            fn run(ctx: @This()) !void {
                _ = try ctx.db.getBoolean("colors");
                _ = try ctx.db.getNumber("cols");
                _ = try ctx.db.getString("clear");
            }
        }{ .db = &db }.run, .{});
    }
    
    for (&threads) |thread| {
        thread.join();
    }
}

// src/terminfo/ghostty_test.zig
const std = @import("std");
const testing = std.testing;
const Ghostty = @import("ghostty.zig");
const terminfo = @import("main.zig");

test "ghostty terminfo initialization" {
    const allocator = testing.allocator;
    
    var ghostty = try Ghostty.init(allocator);
    defer ghostty.deinit();
    
    try testing.expect(ghostty.isInitialized());
    try testing.expectEqualStrings("ghostty", ghostty.name());
}

test "ghostty specific capabilities" {
    const allocator = testing.allocator;
    
    var ghostty = try Ghostty.init(allocator);
    defer ghostty.deinit();
    
    // Test Ghostty-specific boolean capabilities
    const has_rgb = try ghostty.getBoolean("RGB");
    try testing.expect(has_rgb);
    
    const has_truecolor = try ghostty.getBoolean("Tc");
    try testing.expect(has_truecolor);
    
    // Test Ghostty-specific numeric capabilities
    const max_colors = try ghostty.getNumber("colors");
    try testing.expect(max_colors >= 16777216); // True color support
    
    // Test Ghostty-specific string capabilities
    const set_underline = try ghostty.getString("Smulx");
    try testing.expect(set_underline.len > 0);
    
    const set_rgb_foreground = try ghostty.getString("setaf");
    try testing.expect(set_rgb_foreground.len > 0);
}

test "ghostty feature detection" {
    const allocator = testing.allocator;
    
    var ghostty = try Ghostty.init(allocator);
    defer ghostty.deinit();
    
    // Test feature detection
    try testing.expect(ghostty.hasFeature("truecolor"));
    try testing.expect(ghostty.hasFeature("rgb"));
    try testing.expect(ghostty.hasFeature("underline_styles"));
    try testing.expect(ghostty.hasFeature("bracketed_paste"));
    
    // Test non-existent features
    try testing.expect(!ghostty.hasFeature("nonexistent_feature"));
}

test "ghostty capability resolution" {
    const allocator = testing.allocator;
    
    var ghostty = try Ghostty.init(allocator);
    defer ghostty.deinit();
    
    // Test capability resolution with fallbacks
    const clear = try ghostty.resolveCapability("clear");
    try testing.expect(clear.len > 0);
    
    const cursor_addr = try ghostty.resolveCapability("cup");
    try testing.expect(std.mem.indexOf(u8, cursor_addr, "%") != null);
    
    // Test parameter substitution
    const params = [_]i32{ 10, 20 };
    const result = try ghostty.formatCapability("cup", &params);
    try testing.expect(result.len > 0);
}

test "ghostty color capabilities" {
    const allocator = testing.allocator;
    
    var ghostty = try Ghostty.init(allocator);
    defer ghostty.deinit();
    
    // Test RGB color setting
    const rgb_fg = try ghostty.setRgbForeground(255, 128, 64);
    try testing.expect(rgb_fg.len > 0);
    
    const rgb_bg = try ghostty.setRgbBackground(64, 128, 255);
    try testing.expect(rgb_bg.len > 0);
    
    // Test indexed color setting
    const indexed_fg = try ghostty.setIndexedForeground(42);
    try testing.expect(indexed_fg.len > 0);
    
    const indexed_bg = try ghostty.setIndexedBackground(84);
    try testing.expect(indexed_bg.len > 0);
}

test "ghostty cursor capabilities" {
    const allocator = testing.allocator;
    
    var ghostty = try Ghostty.init(allocator);
    defer ghostty.deinit();
    
    // Test cursor movement
    const cursor_up = try ghostty.cursorUp(5);
    try testing.expect(cursor_up.len > 0);
    
    const cursor_down = try ghostty.cursorDown(3);
    try testing.expect(cursor_down.len > 0);
    
    const cursor_left = try ghostty.cursorLeft(2);
    try testing.expect(cursor_left.len > 0);
    
    const cursor_right = try ghostty.cursorRight(4);
    try testing.expect(cursor_right.len > 0);
    
    // Test cursor positioning
    const cursor_pos = try ghostty.setCursorPosition(10, 20);
    try testing.expect(cursor_pos.len > 0);
}

test "ghostty formatting capabilities" {
    const allocator = testing.allocator;
    
    var ghostty = try Ghostty.init(allocator);
    defer ghostty.deinit();
    
    // Test text formatting
    const bold = try ghostty.setBold(true);
    try testing.expect(bold.len > 0);
    
    const italic = try ghostty.setItalic(true);
    try testing.expect(italic.len > 0);
    
    const underline = try ghostty.setUnderline(true);
    try testing.expect(underline.len > 0);
    
    const reset = try ghostty.resetAttributes();
    try testing.expect(reset.len > 0);
    
    // Test underline styles
    const underline_double = try ghostty.setUnderlineStyle(.double);
    try testing.expect(underline_double.len > 0);
    
    const underline_curly = try ghostty.setUnderlineStyle(.curly);
    try testing.expect(underline_curly.len > 0);
}

test "ghostty terminal size" {
    const allocator = testing.allocator;
    
    var ghostty = try Ghostty.init(allocator);
    defer ghostty.deinit();
    
    // Test terminal size capabilities
    const cols = try ghostty.getColumns();
    try testing.expect(cols > 0);
    
    const lines = try ghostty.getLines();
    try testing.expect(lines > 0);
    
    // Test size change notification
    try ghostty.enableSizeChangeNotification();
    try testing.expect(ghostty.isSizeChangeNotificationEnabled());
}

test "ghostty bracketed paste" {
    const allocator = testing.allocator;
    
    var ghostty = try Ghostty.init(allocator);
    defer ghostty.deinit();
    
    // Test bracketed paste mode
    const enable_bracketed = try ghostty.enableBracketedPaste();
    try testing.expect(enable_bracketed.len > 0);
    
    const disable_bracketed = try ghostty.disableBracketedPaste();
    try testing.expect(disable_bracketed.len > 0);
    
    // Test bracketed paste sequences
    try testing.expect(std.mem.startsWith(u8, enable_bracketed, "\x1b[?2004h"));
    try testing.expect(std.mem.startsWith(u8, disable_bracketed, "\x1b[?2004l"));
}

test "ghostty extended capabilities" {
    const allocator = testing.allocator;
    
    var ghostty = try Ghostty.init(allocator);
    defer ghostty.deinit();
    
    // Test extended capabilities
    const kitty_keyboard = try ghostty.enableKittyKeyboard();
    try testing.expect(kitty_keyboard.len > 0);
    
    const focus_events = try ghostty.enableFocusEvents();
    try testing.expect(focus_events.len > 0);
    
    const mouse_events = try ghostty.enableMouseEvents();
    try testing.expect(mouse_events.len > 0);
}

test "ghostty capability caching" {
    const allocator = testing.allocator;
    
    var ghostty = try Ghostty.init(allocator);
    defer ghostty.deinit();
    
    // Test capability caching
    const cap1 = try ghostty.getCachedCapability("clear");
    const cap2 = try ghostty.getCachedCapability("clear");
    try testing.expectEqualStrings(cap1, cap2);
    
    // Test cache invalidation
    ghostty.invalidateCache();
    const cap3 = try ghostty.getCachedCapability("clear");
    try testing.expectEqualStrings(cap1, cap3);
}

test "ghostty error handling" {
    const allocator = testing.allocator;
    
    var ghostty = try Ghostty.init(allocator);
    defer ghostty.deinit();
    
    // Test invalid capability names
    try testing.expectError(error.CapabilityNotFound, ghostty.getBoolean("invalid"));
    try testing.expectError(error.CapabilityNotFound, ghostty.getNumber("invalid"));
    try testing.expectError(error.CapabilityNotFound, ghostty.getString("invalid"));
    
    // Test invalid parameters
    try testing.expectError(error.InvalidParameter, ghostty.setRgbForeground(-1, 0, 0));
    try testing.expectError(error.InvalidParameter, ghostty.setRgbForeground(0, -1, 0));
    try testing.expectError(error.InvalidParameter, ghostty.setRgbForeground(0, 0, -1));
    try testing.expectError(error.InvalidParameter, ghostty.setRgbForeground(256, 0, 0));
}

// src/terminfo/Source_test.zig
const std = @import("std");
const testing = std.testing;
const Source = @import("Source.zig");

test "source file parsing" {
    const allocator = testing.allocator;
    
    const test_data =
        \\ghostty|Ghostty Terminal,
        \\    am, bel=^G, bold=\E[1m, clear=\E[H\E[J,
        \\    colors#16777216, cols#80, it#8, lines#24,
        \\    setaf=\E[38;5;%p1%dm, setab=\E[48;5;%p1%dm,
        \\    cup=\E[%i%p1%d;%p2%dH,
        ;
    
    var source = try Source.parse(allocator, test_data);
    defer source.deinit();
    
    try testing.expectEqualStrings("ghostty", source.name);
    try testing.expectEqualStrings("Ghostty Terminal", source.description);
    try testing.expect(source.aliases.len > 0);
}

test "source boolean capabilities" {
    const allocator = testing.allocator;
    
    const test_data =
        \\test|Test Terminal,
        \\    am, bel, bce, blink, bold,
        ;
    
    var source = try Source.parse(allocator, test_data);
    defer source.deinit();
    
    try testing.expect(source.getBoolean("am"));
    try testing.expect(source.getBoolean("bel"));
    try testing.expect(source.getBoolean("bce"));
    try testing.expect(source.getBoolean("blink"));
    try testing.expect(source.getBoolean("bold"));
    
    try testing.expect(!source.getBoolean("nonexistent"));
}

test "source numeric capabilities" {
    const allocator = testing.allocator;
    
    const test_data =
        \\test|Test Terminal,
        \\    colors#256, cols#80, it#8, lines#24, pairs#32767,
        ;
    
    var source = try Source.parse(allocator, test_data);
    defer source.deinit();
    
    try testing.expectEqual(@i32(256), source.getNumber("colors"));
    try testing.expectEqual(@i32(80), source.getNumber("cols"));
    try testing.expectEqual(@i32(8), source.getNumber("it"));
    try testing.expectEqual(@i32(24), source.getNumber("lines"));
    try testing.expectEqual(@i32(32767), source.getNumber("pairs"));
    
    try testing.expectEqual(@i32(-1), source.getNumber("nonexistent"));
}

test "source string capabilities" {
    const allocator = testing.allocator;
    
    const test_data =
        \\test|Test Terminal,
        \\    bel=^G, bold=\E[1m, clear=\E[H\E[J,
        \\    cup=\E[%i%p1%d;%p2%dH, el=\E[K,
        ;
    
    var source = try Source.parse(allocator, test_data);
    defer source.deinit();
    
    try testing.expectEqualStrings("\x07", source.getString("bel"));
    try testing.expectEqualStrings("\x1b[1m", source.getString("bold"));
    try testing.expectEqualStrings("\x1b[H\x1b[J", source.getString("clear"));
    try testing.expectEqualStrings("\x1b[%i%p1%d;%p2%dH", source.getString("cup"));
    try testing.expectEqualStrings("\x1b[K", source.getString("el"));
    
    try testing.expectEqualStrings("", source.getString("nonexistent"));
}

test "source escape sequence parsing" {
    const allocator = testing.allocator;
    
    const test_data =
        \\test|Test Terminal,
        \\    ctrl_a=^A, ctrl_z=^Z, esc=\E, backspace=^H,
        \\    newline=\n, return=\r, tab=\t,
        ;
    
    var source = try Source.parse(allocator, test_data);
    defer source.deinit();
    
    try testing.expectEqualStrings("\x01", source.getString("ctrl_a"));
    try testing.expectEqualStrings("\x1a", source.getString("ctrl_z"));
    try testing.expectEqualStrings("\x1b", source.getString("esc"));
    try testing.expectEqualStrings("\x08", source.getString("backspace"));
    try testing.expectEqualStrings("\n", source.getString("newline"));
    try testing.expectEqualStrings("\r", source.getString("return"));
    try testing.expectEqualStrings("\t", source.getString("tab"));
}

test "source parameterized capabilities" {
    const allocator = testing.allocator;
    
    const test_data =
        \\test|Test Terminal,
        \\    cup=\E[%i%p1%d;%p2%dH,
        \\    setaf=\E[38;5;%p1%dm,
        \\    sgr=%?%p9%t\E(0%e\E(B%;\E[0%?%p6%t;1%;%?%p2%t;4%;%?%p4%t;5%;%?%p1%p3%|%t;7%;m,
        ;
    
    var source = try Source.parse(allocator, test_data);
    defer source.deinit();
    
    const cup = source.getString("cup");
    try testing.expect(std.mem.indexOf(u8, cup, "%p1") != null);
    try testing.expect(std.mem.indexOf(u8, cup, "%p2") != null);
    try testing.expect(std.mem.indexOf(u8, cup, "%i") != null);
    
    const setaf = source.getString("setaf");
    try testing.expect(std.mem.indexOf(u8, setaf, "%p1") != null);
    
    const sgr = source.getString("sgr");
    try testing.expect(std.mem.indexOf(u8, sgr, "%?") != null);
    try testing.expect(std.mem.indexOf(u8, sgr, "%t") != null);
    try testing.expect(std.mem.indexOf(u8, sgr, "%e") != null);
    try testing.expect(std.mem.indexOf(u8, sgr, "%;") != null);
}

test "source use capability" {
    const allocator = testing.allocator;
    
    const test_data =
        \\base|Base Terminal,
        \\    am, bel=^G, colors#8,
        \\
        \\derived|Derived Terminal|base,
        \\    bold=\E[1m, cols#80,
        ;
    
    var source = try Source.parse(allocator, test_data);
    defer source.deinit();
    
    // Derived should inherit from base
    try testing.expect(source.getBoolean("am"));
    try testing.expectEqualStrings("\x07", source.getString("bel"));
    try testing.expectEqual(@i32(8), source.getNumber("colors"));
    
    // And have its own capabilities
    try testing.expectEqualStrings("\x1b[1m", source.getString("bold"));
    try testing.expectEqual(@i32(80), source.getNumber("cols"));
}

test "source comments and whitespace" {
    const allocator = testing.allocator;
    
    const test_data =
        \\# This is a comment
        \\test|Test Terminal|with spaces,
        \\    # Another comment
        \\    am,    bel=^G,    # Inline comment
        \\    bold=\E[1m,
        \\
        \\    # More comments
        \\    clear=\E[H\E[J,
        ;
    
    var source = try Source.parse(allocator, test_data);
    defer source.deinit();
    
    try testing.expectEqualStrings("test", source.name);
    try testing.expectEqualStrings("Test Terminal|with spaces", source.description);
    try testing.expect(source.getBoolean("am"));
    try testing.expectEqualStrings("\x07", source.getString("bel"));
    try testing.expectEqualStrings("\x1b[1m", source.getString("bold"));
    try testing.expectEqualStrings("\x1b[H\x1b[J", source.getString("clear"));
}

test "source multi-line capabilities" {
    const allocator = testing.allocator;
    
    const test_data =
        \\test|Test Terminal,
        \\    sgr1=\E[0%?%p1%t;1%;\
        \\        %?%p2%t;4%;\
        \\        %?%p3%t;5%;\
        \\        %?%p4%t;7%;\
        \\        %?%p6%t;8%;\
        \\        m,
        ;
    
    var source = try Source.parse(allocator, test_data);
    defer source.deinit();
    
    const sgr1 = source.getString("sgr1");
    try testing.expect(sgr1.len > 0);
    try testing.expect(std.mem.indexOf(u8, sgr1, "\x1b[0") != null);
    try testing.expect(std.mem.indexOf(u8, sgr1, "m") != null);
}

test "source capability validation" {
    const allocator = testing.allocator;
    
    const test_data =
        \\test|Test Terminal,
        \\    am, bel=^G, colors#256,
        \\    cup=\E[%i%p1%d;%p2%dH,
        ;
    
    var source = try Source.parse(allocator, test_data);
    defer source.deinit();
    
    // Test validation
    try testing.expect(source.validate());
    
    // Test invalid source
    const invalid_data = "invalid|Invalid,";
    var invalid_source = Source.parse(allocator, invalid_data) catch |err| {
        try testing.expect(err == error.ParseError);
        return;
    };
    defer invalid_source.deinit();
    try testing.expect(!invalid_source.validate());
}

test "source capability enumeration" {
    const allocator = testing.allocator;
    
    const test_data =
        \\test|Test Terminal,
        \\    am, bel, bold, bce,
        \\    colors#256, cols#80, it#8,
        \\    bel=^G, bold=\E[1m, clear=\E[H\E[J,
        ;
    
    var source = try Source.parse(allocator, test_data);
    defer source.deinit();
    
    // Test boolean enumeration
    var bool_count: usize = 0;
    var bool_iter = source.iterBoolean();
    while (bool_iter.next()) |cap| {
        bool_count += 1;
        try testing.expect(cap.name.len > 0);
    }
    try testing.expect(bool_count == 4);
    
    // Test numeric enumeration
    var num_count: usize = 0;
    var num_iter = source.iterNumeric();
    while (num_iter.next()) |cap| {
        num_count += 1;
        try testing.expect(cap.name.len > 0);
        try testing.expect(cap.value >= 0);
    }
    try testing.expect(num_count == 3);
    
    // Test string enumeration
    var str_count: usize = 0;
    var str_iter = source.iterString();
    while (str_iter.next()) |cap| {
        str_count += 1;
        try testing.expect(cap.name.len > 0);
        try testing.expect(cap.value.len > 0);
    }
    try testing.expect(str_count == 3);
}

test "source error handling" {
    const allocator = testing.allocator;
    
    // Test empty source
    try testing.expectError(error.ParseError, Source.parse(allocator, ""));
    
    // Test malformed header
    try testing.expectError(error.ParseError, Source.parse(allocator, "invalid"));
    
    // Test malformed capability
    try testing.expectError(error.ParseError, Source.parse(allocator, "test|Test, invalid"));
    
    // Test malformed numeric
    try testing.expectError(error.ParseError, Source.parse(allocator, "test|Test, colors#abc"));
    
    // Test unterminated string
    try testing.expectError(error.ParseError, Source.parse(allocator, "test|Test, bel=\x1b"));
}

test "source memory management" {
    const allocator = testing.allocator;
    
    const test_data =
        \\test|Test Terminal,
        \\    am, bel=^G, colors#256, bold=\E[1m,
        ;
    
    var source = try Source.parse(allocator, test_data);
    defer source.deinit();
    
    // Test copying source
    var copy = try source.copy(allocator);
    defer copy.deinit();
    
    try testing.expectEqualStrings(source.name, copy.name);
    try testing.expectEqualStrings(source.description, copy.description);
    
    // Test cloning with modifications
    var clone = try source.clone(allocator);
    defer clone.deinit();
    
    try clone.setString("test_cap", "\x1b[TEST");
    try testing.expectEqualStrings("\x1b[TEST", clone.getString("test_cap"));
}

test "source capability formatting" {
    const allocator = testing.allocator;
    
    const test_data =
        \\test|Test Terminal,
        \\    cup=\E[%i%p1%d;%p2%dH,
        \\    setaf=\E[38;5;%p1%dm,
        ;
    
    var source = try Source.parse(allocator, test_data);
    defer source.deinit();
    
    // Test parameter formatting
    const params = [_]i32{ 10, 20 };
    const formatted = try source.formatCapability("cup", &params);
    try testing.expect(formatted.len > 0);
    try testing.expect(std.mem.indexOf(u8, formatted, "10") != null);
    try testing.expect(std.mem.indexOf(u8, formatted, "20") != null);
    
    // Test single parameter
    const color_params = [_]i32{42};
    const color_formatted = try source.formatCapability("setaf", &color_params);
    try testing.expect(color_formatted.len > 0);
    try testing.expect(std.mem.indexOf(u8, color_formatted, "42") != null);
}

test "source capability merging" {
    const allocator = testing.allocator;
    
    const base_data =
        \\base|Base Terminal,
        \\    am, bel=^G, colors#8,
        ;
    
    const override_data =
        \\override|Override Terminal,
        \\    bold=\E[1m, colors#256,
        ;
    
    var base = try Source.parse(allocator, base_data);
    defer base.deinit();
    
    var override = try Source.parse(allocator, override_data);
    defer override.deinit();
    
    // Test merging
    var merged = try Source.merge(allocator, &base, &override);
    defer merged.deinit();
    
    try testing.expect(merged.getBoolean("am"));
    try testing.expectEqualStrings("\x07", merged.getString("bel"));
    try testing.expectEqual(@i32(256), merged.getNumber("colors")); // Overridden
    try testing.expectEqualStrings("\x1b[1m", merged.getString("bold"));
}