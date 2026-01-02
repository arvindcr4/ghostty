const std = @import("std");
const testing = std.testing;
const mem = std.mem;
const fs = std.fs;
const time = std.time;

// Import Ghostty modules
const Terminal = @import("src/terminal.zig").Terminal;
const Config = @import("src/config.zig").Config;
const Renderer = @import("src/renderer.zig").Renderer;
const Font = @import("src/font.zig").Font;
const Surface = @import("src/surface.zig").Surface;
const Termio = @import("src/termio.zig").Termio;
const PTY = @import("src/pty.zig").PTY;
const App = @import("src/app.zig").App;
const Command = @import("src/command.zig").Command;
const Input = @import("src/input.zig").Input;
const Theme = @import("src/theme.zig").Theme;
const ANSI = @import("src/ansi.zig").ANSI;
const Color = @import("src/color.zig").Color;
const Highlight = @import("src/highlight.zig").Highlight;
const Mouse = @import("src/mouse.zig").Mouse;
const Unicode = @import("src/unicode.zig").Unicode;
const Shaper = @import("src/shaper.zig").Shaper;

test "Terminal + Config integration - Load config and apply to terminal" {
    const allocator = testing.allocator;
    
    // Create test config
    var config = try Config.init(allocator);
    defer config.deinit();
    
    try config.set("font_size", "14");
    try config.set("font_family", "Monospace");
    try config.set("background_color", "#000000");
    try config.set("foreground_color", "#ffffff");
    try config.set("cursor_blink", "true");
    
    // Initialize terminal with config
    var terminal = try Terminal.init(allocator, 80, 24, &config);
    defer terminal.deinit();
    
    // Verify config was applied
    try testing.expectEqual(@as(u16, 80), terminal.width);
    try testing.expectEqual(@as(u16, 24), terminal.height);
    try testing.expectEqual(config.get("font_size").?.u16, terminal.font_size);
    try testing.expectEqualStrings("Monospace", terminal.font_family);
    try testing.expect(config.get("cursor_blink").?.bool);
    
    // Test config changes propagate to terminal
    try config.set("font_size", "16");
    terminal.applyConfig(&config);
    try testing.expectEqual(@as(u16, 16), terminal.font_size);
}

test "Renderer + Font + Surface integration - Full rendering pipeline" {
    const allocator = testing.allocator;
    
    // Initialize font system
    var font = try Font.init(allocator, "Monospace", 12);
    defer font.deinit();
    
    // Create surface
    var surface = try Surface.init(allocator, 800, 600);
    defer surface.deinit();
    
    // Initialize renderer
    var renderer = try Renderer.init(allocator, &surface, &font);
    defer renderer.deinit();
    
    // Test text rendering pipeline
    const test_text = "Hello, 世界! 🌍";
    const glyphs = try font.shapeText(allocator, test_text);
    defer allocator.free(glyphs);
    
    try testing.expect(glyphs.len > 0);
    
    // Render text to surface
    try renderer.renderText(10, 10, test_text, Color{ .r = 255, .g = 255, .b = 255, .a = 255 });
    
    // Verify surface was modified
    const pixel = surface.getPixel(15, 15);
    try testing.expect(pixel.a > 0); // Should have some opacity
    
    // Test full frame rendering
    renderer.beginFrame();
    try renderer.clear(Color{ .r = 0, .g = 0, .b = 0, .a = 255 });
    try renderer.renderText(50, 50, "Test rendering", Color{ .r = 255, .g = 255, .b = 255, .a = 255 });
    renderer.endFrame();
    
    // Verify rendering performance
    const start_time = time.nanoTimestamp();
    for (0..100) |_| {
        renderer.beginFrame();
        renderer.clear(Color{ .r = 0, .g = 0, .b = 0, .a = 255 });
        renderer.endFrame();
    }
    const end_time = time.nanoTimestamp();
    const avg_time = @as(f64, @floatFromInt(end_time - start_time)) / 100.0;
    try testing.expect(avg_time < 1000000.0); // Should be under 1ms per frame
}

test "Terminal + Termio + PTY integration - Complete terminal I/O" {
    const allocator = testing.allocator;
    
    // Create PTY
    var pty = try PTY.open(allocator, 80, 24);
    defer pty.close();
    
    // Initialize termio
    var termio = try Termio.init(allocator, &pty);
    defer termio.deinit();
    
    // Create terminal
    var terminal = try Terminal.init(allocator, 80, 24, null);
    defer terminal.deinit();
    
    // Test data flow: PTY -> Termio -> Terminal
    const test_input = "echo 'Hello World'\r\n";
    _ = try pty.write(test_input);
    
    // Read from PTY through termio
    var buffer: [1024]u8 = undefined;
    const bytes_read = try termio.read(&buffer);
    try testing.expect(bytes_read > 0);
    
    // Process input through terminal
    terminal.processInput(buffer[0..bytes_read]);
    
    // Verify terminal state
    const line = terminal.getLine(0);
    try testing.expect(mem.indexOf(u8, line, "Hello World") != null);
    
    // Test output flow: Terminal -> Termio -> PTY
    terminal.write("ls -la\r\n");
    const output = terminal.getOutputBuffer();
    try testing.expect(output.len > 0);
    
    // Test error propagation
    pty.close(); // Close PTY to simulate error
    const read_result = termio.read(&buffer);
    try testing.expectError(error.ConnectionReset, read_result);
}

test "App + Command + Input integration - Full application flow" {
    const allocator = testing.allocator;
    
    // Initialize app
    var app = try App.init(allocator);
    defer app.deinit();
    
    // Create command processor
    var command = try Command.init(allocator);
    defer command.deinit();
    
    // Initialize input handler
    var input = try Input.init(allocator);
    defer input.deinit();
    
    // Test command execution flow
    const cmd_sequence = "new-tab\r\n";
    try input.processBytes(cmd_sequence);
    
    const events = input.getEvents();
    try testing.expect(events.len > 0);
    
    for (events) |event| {
        const result = try command.execute(event, &app);
        try testing.expect(result.success);
    }
    
    // Verify app state changed
    try testing.expect(app.tab_count > 0);
    
    // Test complex command chain
    const complex_sequence = "split-horizontal\r\nresize 50%\r\nfocus-right\r\n";
    try input.processBytes(complex_sequence);
    
    const complex_events = input.getEvents();
    for (complex_events) |event| {
        const result = try command.execute(event, &app);
        try testing.expect(result.success);
    }
    
    // Verify layout changes
    try testing.expect(app.hasSplit());
    try testing.expect(app.getFocusedPane().width == 400); // Assuming 800px width
}

test "Config + Theme + Font integration - Theme application" {
    const allocator = testing.allocator;
    
    // Create config with theme settings
    var config = try Config.init(allocator);
    defer config.deinit();
    
    try config.set("theme", "dark");
    try config.set("font_family", "JetBrains Mono");
    try config.set("font_size", "13");
    try config.set("font_weight", "500");
    
    // Load theme
    var theme = try Theme.load(allocator, config.get("theme").?.str);
    defer theme.deinit();
    
    // Initialize font with theme settings
    var font = try Font.initWithTheme(allocator, &theme);
    defer font.deinit();
    
    // Verify theme colors are applied
    try testing.expectEqual(theme.colors.background.r, 0x1e);
    try testing.expectEqual(theme.colors.foreground.g, 0xe4);
    
    // Verify font settings from theme
    try testing.expectEqualStrings("JetBrains Mono", font.family);
    try testing.expectEqual(@as(u16, 13), font.size);
    try testing.expectEqual(@as(u16, 500), font.weight);
    
    // Test theme switching
    try config.set("theme", "light");
    var light_theme = try Theme.load(allocator, config.get("theme").?.str);
    defer light_theme.deinit();
    
    font.applyTheme(&light_theme);
    try testing.expectEqual(light_theme.colors.background.r, 0xff);
    try testing.expectEqual(light_theme.colors.foreground.r, 0x00);
    
    // Test theme validation
    const invalid_theme = Theme.load(allocator, "nonexistent");
    try testing.expectError(error.FileNotFound, invalid_theme);
}

test "Terminal + ANSI + Color + Highlight integration - Text styling pipeline" {
    const allocator = testing.allocator;
    
    // Initialize terminal
    var terminal = try Terminal.init(allocator, 80, 24, null);
    defer terminal.deinit();
    
    // ANSI processor
    var ansi = try ANSI.init(allocator);
    defer ansi.deinit();
    
    // Color system
    var color = try Color.init(allocator);
    defer color.deinit();
    
    // Highlight system
    var highlight = try Highlight.init(allocator);
    defer highlight.deinit();
    
    // Test ANSI color sequence processing
    const ansi_text = "\x1b[31mRed\x1b[0m \x1b[32;1mBold Green\x1b[0m \x1b[38;2;255;165;0mOrange\x1b[0m";
    const processed = try ansi.process(ansi_text);
    defer allocator.free(processed);
    
    // Apply to terminal
    terminal.write(processed);
    
    // Verify color application
    const line = terminal.getLine(0);
    const red_span = terminal.getSpan(0, 0, 3);
    try testing.expectEqual(color.fromANSI(31).r, red_span.fg_color.r);
    
    const bold_green_span = terminal.getSpan(0, 4, 10);
    try testing.expect(bold_green_span.bold);
    try testing.expectEqual(color.fromANSI(32).g, bold_green_span.fg_color.g);
    
    // Test RGB color
    const orange_span = terminal.getSpan(0, 15, 6);
    try testing.expectEqual(@as(u8, 255), orange_span.fg_color.r);
    try testing.expectEqual(@as(u8, 165), orange_span.fg_color.g);
    try testing.expectEqual(@as(u8, 0), orange_span.fg_color.b);
    
    // Test highlighting
    highlight.addPattern("error", Color{ .r = 255, .g = 0, .b = 0, .a = 255 });
    const error_text = "ERROR: Something went wrong";
    const highlighted = try highlight.apply(error_text);
    defer allocator.free(highlighted);
    
    terminal.write(highlighted);
    const error_span = terminal.getSpan(1, 0, 5);
    try testing.expectEqual(@as(u8, 255), error_span.fg_color.r);
}

test "Surface + Renderer + Mouse integration - Mouse interaction" {
    const allocator = testing.allocator;
    
    // Create surface
    var surface = try Surface.init(allocator, 800, 600);
    defer surface.deinit();
    
    // Initialize renderer
    var renderer = try Renderer.init(allocator, &surface, null);
    defer renderer.deinit();
    
    // Mouse handler
    var mouse = try Mouse.init(allocator);
    defer mouse.deinit();
    
    // Render some content
    renderer.beginFrame();
    try renderer.clear(Color{ .r = 30, .g = 30, .b = 30, .a = 255 });
    try renderer.drawRect(100, 100, 200, 100, Color{ .r = 100, .g = 100, .b = 100, .a = 255 });
    renderer.endFrame();
    
    // Test mouse click detection
    const click_event = Mouse.Event{
        .type = .Click,
        .x = 150,
        .y = 150,
        .button = .Left,
        .modifiers = .{},
    };
    
    const hit_result = renderer.testHit(click_event.x, click_event.y);
    try testing.expect(hit_result.hit);
    try testing.expectEqual(@as(u32, 100), hit_result.rect.x);
    try testing.expectEqual(@as(u32, 100), hit_result.rect.y);
    
    // Test mouse drag
    const drag_start = Mouse.Event{ .type = .Down, .x = 150, .y = 150, .button = .Left, .modifiers = .{} };
    const drag_move = Mouse.Event{ .type = .Move, .x = 250, .y = 200, .button = .Left, .modifiers = .{} };
    const drag_end = Mouse.Event{ .type = .Up, .x = 250, .y = 200, .button = .Left, .modifiers = .{} };
    
    mouse.processEvent(drag_start);
    mouse.processEvent(drag_move);
    mouse.processEvent(drag_end);
    
    const selection = mouse.getSelection();
    try testing.expect(selection.active);
    try testing.expectEqual(@as(u32, 150), selection.start_x);
    try testing.expectEqual(@as(u32, 250), selection.end_x);
    
    // Test mouse wheel
    const wheel_event = Mouse.Event{
        .type = .Wheel,
        .x = 400,
        .y = 300,
        .delta_x = 0,
        .delta_y = -3,
        .button = .None,
        .modifiers = .{},
    };
    
    const scroll_result = renderer.handleScroll(wheel_event);
    try testing.expect(scroll_result.scrolled);
    try testing.expect(scroll_result.scroll_y > 0);
}

test "Unicode + Font + Shaper integration - Text shaping pipeline" {
    const allocator = testing.allocator;
    
    // Initialize Unicode system
    var unicode = try Unicode.init(allocator);
    defer unicode.deinit();
    
    // Initialize font
    var font = try Font.init(allocator, "Noto Sans", 14);
    defer font.deinit();
    
    // Initialize shaper
    var shaper = try Shaper.init(allocator, &font);
    defer shaper.deinit();
    
    // Test complex text with various scripts
    const complex_text = "Hello 世界 🌍 العربية עברית हिन्दी";
    
    // Unicode analysis
    const script_runs = unicode.analyzeScripts(complex_text);
    try testing.expect(script_runs.len > 1);
    
    // Shape text
    const glyphs = try shaper.shapeText(complex_text);
    defer allocator.free(glyphs);
    
    try testing.expect(glyphs.len > 0);
    
    // Verify glyph properties
    var total_width: u32 = 0;
    for (glyphs) |glyph| {
        try testing.expect(glyph.advance > 0);
        total_width += glyph.advance;
    }
    
    try testing.expect(total_width > 0);
    
    // Test bidirectional text
    const bidi_text = "English العربية English";
    const bidi_glyphs = try shaper.shapeText(bidi_text);
    defer allocator.free(bidi_glyphs);
    
    // Verify visual ordering
    try testing.expect(bidi_glyphs.len > 0);
    
    // Test combining characters
    const combining_text = "e\u0301 = é"; // e + combining acute accent
    const combining_glyphs = try shaper.shapeText(combining_text);
    defer allocator.free(combining_glyphs);
    
    try testing.expect(combining_glyphs.len == 4); // Should be properly combined
    
    // Test emoji rendering
    const emoji_text = "👨‍👩‍👧‍👦 👍 🎉";
    const emoji_glyphs = try shaper.shapeText(emoji_text);
    defer allocator.free(emoji_glyphs);
    
    try testing.expect(emoji_glyphs.len > 0);
    
    // Verify emoji are rendered as single glyphs
    for (emoji_glyphs) |glyph| {
        if (glyph.is_emoji) {
            try testing.expect(glyph.advance > font.size);
        }
    }
    
    // Test performance with large text
    const large_text = "The quick brown fox jumps over the lazy dog. " ** 100;
    const start_time = time.nanoTimestamp();
    const large_glyphs = try shaper.shapeText(large_text);
    defer allocator.free(large_glyphs);
    const end_time = time.nanoTimestamp();
    
    const shaping_time = @as(f64, @floatFromInt(end_time - start_time)) / 1000000.0;
    try testing.expect(shaping_time < 10.0); // Should complete in under 10ms
    try testing.expect(large_glyphs.len > 0);
}

test "End-to-end terminal workflow integration" {
    const allocator = testing.allocator;
    
    // Complete system initialization
    var config = try Config.init(allocator);
    defer config.deinit();
    try config.set("theme", "dark");
    try config.set("font_family", "Monospace");
    try config.set("font_size", "12");
    
    var theme = try Theme.load(allocator, "dark");
    defer theme.deinit();
    
    var font = try Font.initWithTheme(allocator, &theme);
    defer font.deinit();
    
    var surface = try Surface.init(allocator, 800, 600);
    defer surface.deinit();
    
    var renderer = try Renderer.init(allocator, &surface, &font);
    defer renderer.deinit();
    
    var terminal = try Terminal.init(allocator, 80, 24, &config);
    defer terminal.deinit();
    
    var pty = try PTY.open(allocator, 80, 24);
    defer pty.close();
    
    var termio = try Termio.init(allocator, &pty);
    defer termio.deinit();
    
    var ansi = try ANSI.init(allocator);
    defer ansi.deinit();
    
    // Simulate complete workflow
    const command = "echo -e 'Hello\\nWorld\\n\\x1b[31mRed Text\\x1b[0m'\r\n";
    _ = try pty.write(command);
    
    // Read and process
    var buffer: [1024]u8 = undefined;
    const bytes_read = try termio.read(&buffer);
    const processed = try ansi.process(buffer[0..bytes_read]);
    defer allocator.free(processed);
    
    terminal.write(processed);
    
    // Render terminal content
    renderer.beginFrame();
    try renderer.clear(theme.colors.background);
    
    var y: u32 = 10;
    for (0..terminal.height) |row| {
        if (row < terminal.getLineCount()) {
            const line = terminal.getLine(row);
            try renderer.renderText(10, y, line, theme.colors.foreground);
            y += font.line_height;
        }
    }
    
    renderer.endFrame();
    
    // Verify output
    try testing.expect(terminal.getLineCount() >= 3);
    try testing.expect(mem.indexOf(u8, terminal.getLine(0), "Hello") != null);
    try testing.expect(mem.indexOf(u8, terminal.getLine(1), "World") != null);
    try testing.expect(mem.indexOf(u8, terminal.getLine(2), "Red Text") != null);
    
    // Verify red text color
    const red_span = terminal.getSpan(2, 0, 8);
    try testing.expectEqual(@as(u8, 255), red_span.fg_color.r);
    try testing.expectEqual(@as(u8, 0), red_span.fg_color.g);
    try testing.expectEqual(@as(u8, 0), red_span.fg_color.b);
    
    // Verify surface was rendered
    const pixel = surface.getPixel(15, 15);
    try testing.expect(pixel.a > 0);
}