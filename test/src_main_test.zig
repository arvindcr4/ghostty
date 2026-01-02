// src/App.zig tests
const std = @import("std");
const testing = std.testing;
const App = @import("App.zig");

test "App initialization" {
    const allocator = testing.allocator;
    var app = try App.init(allocator);
    defer app.deinit();
    
    try testing.expect(app.state == .initialized);
    try testing.expect(app.allocator == allocator);
}

test "App run loop" {
    const allocator = testing.allocator;
    var app = try App.init(allocator);
    defer app.deinit();
    
    // Mock the main loop
    var iterations: u32 = 0;
    const max_iterations = 10;
    
    while (iterations < max_iterations) {
        const should_continue = app.tick();
        if (!should_continue) break;
        iterations += 1;
    }
    
    try testing.expect(iteritions > 0);
}

test "App shutdown" {
    const allocator = testing.allocator;
    var app = try App.init(allocator);
    
    app.shutdown();
    try testing.expect(app.state == .shutdown);
}

test "App error handling" {
    const allocator = testing.allocator;
    
    // Test with invalid allocator
    var app = App.init(undefined) catch |err| {
        try testing.expect(err == error.InvalidAllocator);
        return;
    };
    _ = app;
}

// src/Command.zig tests
const Command = @import("Command.zig");

test "Command parsing" {
    const allocator = testing.allocator;
    
    const input = "ls -la /home";
    var cmd = try Command.parse(allocator, input);
    defer cmd.deinit();
    
    try testing.expectEqualStrings("ls", cmd.name);
    try testing.expect(cmd.args.len == 2);
    try testing.expectEqualStrings("-la", cmd.args[0]);
    try testing.expectEqualStrings("/home", cmd.args[1]);
}

test "Command execution" {
    const allocator = testing.allocator;
    
    var cmd = Command{
        .name = "echo",
        .args = &[_][]const u8{"hello"},
        .allocator = allocator,
    };
    
    const result = try cmd.execute();
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);
    
    try testing.expectEqualStrings("hello\n", result.stdout);
    try testing.expect(result.exit_code == 0);
}

test "Command validation" {
    const allocator = testing.allocator;
    
    // Valid command
    var cmd1 = Command{
        .name = "ls",
        .args = &[_][]const u8{},
        .allocator = allocator,
    };
    try testing.expect(cmd1.validate());
    
    // Invalid command
    var cmd2 = Command{
        .name = "",
        .args = &[_][]const u8{},
        .allocator = allocator,
    };
    try testing.expect(!cmd2.validate());
}

// src/config.zig tests
const Config = @import("config.zig");

test "Config loading" {
    const allocator = testing.allocator;
    
    const config_data = 
        \\font_size = 14
        \\theme = "dark"
        \\shell = "/bin/bash"
    ;
    
    var config = try Config.loadFromString(allocator, config_data);
    defer config.deinit();
    
    try testing.expect(config.font_size == 14);
    try testing.expectEqualStrings("dark", config.theme);
    try testing.expectEqualStrings("/bin/bash", config.shell);
}

test "Config validation" {
    const allocator = testing.allocator;
    
    var config = Config.initDefault(allocator);
    defer config.deinit();
    
    try testing.expect(config.validate());
    
    // Test invalid font size
    config.font_size = -1;
    try testing.expect(!config.validate());
}

test "Config merging" {
    const allocator = testing.allocator;
    
    var base = Config.initDefault(allocator);
    defer base.deinit();
    
    var override = Config.initDefault(allocator);
    defer override.deinit();
    override.font_size = 18;
    
    try base.merge(override);
    try testing.expect(base.font_size == 18);
}

// src/pty.zig tests
const Pty = @import("pty.zig");

test "Pty creation" {
    const allocator = testing.allocator;
    
    var pty = try Pty.init(allocator, 80, 24);
    defer pty.deinit();
    
    try testing.expect(pty.width == 80);
    try testing.expect(pty.height == 24);
    try testing.expect(pty.fd >= 0);
}

test "Pty resize" {
    const allocator = testing.allocator;
    
    var pty = try Pty.init(allocator, 80, 24);
    defer pty.deinit();
    
    try pty.resize(100, 30);
    try testing.expect(pty.width == 100);
    try testing.expect(pty.height == 30);
}

test "Pty process spawn" {
    const allocator = testing.allocator;
    
    var pty = try Pty.init(allocator, 80, 24);
    defer pty.deinit();
    
    const args = [_][]const u8{"/bin/echo", "test"};
    try pty.spawnProcess(&args);
    
    try testing.expect(pty.pid > 0);
}

test "Pty read/write" {
    const allocator = testing.allocator;
    
    var pty = try Pty.init(allocator, 80, 24);
    defer pty.deinit();
    
    const test_data = "Hello, World!";
    _ = try pty.write(test_data);
    
    var buffer: [1024]u8 = undefined;
    const bytes_read = try pty.read(&buffer);
    
    try testing.expect(bytes_read > 0);
}

// src/renderer.zig tests
const Renderer = @import("renderer.zig");

test "Renderer initialization" {
    const allocator = testing.allocator;
    
    var renderer = try Renderer.init(allocator, 800, 600);
    defer renderer.deinit();
    
    try testing.expect(renderer.width == 800);
    try testing.expect(renderer.height == 600);
}

test "Renderer cell rendering" {
    const allocator = testing.allocator;
    
    var renderer = try Renderer.init(allocator, 80, 24);
    defer renderer.deinit();
    
    const cell = Renderer.Cell{
        .char = 'A',
        .fg = .{ .r = 255, .g = 255, .b = 255 },
        .bg = .{ .r = 0, .g = 0, .b = 0 },
    };
    
    try renderer.drawCell(0, 0, cell);
    const drawn_cell = renderer.getCell(0, 0);
    try testing.expect(drawn_cell.char == 'A');
}

test "Renderer screen clear" {
    const allocator = testing.allocator;
    
    var renderer = try Renderer.init(allocator, 80, 24);
    defer renderer.deinit();
    
    // Draw some content
    const cell = Renderer.Cell{ .char = 'X' };
    try renderer.drawCell(10, 10, cell);
    
    // Clear screen
    renderer.clear();
    
    // Verify screen is clear
    const cleared_cell = renderer.getCell(10, 10);
    try testing.expect(cleared_cell.char == ' ');
}

test "Renderer scroll" {
    const allocator = testing.allocator;
    
    var renderer = try Renderer.init(allocator, 80, 24);
    defer renderer.deinit();
    
    // Fill first line
    for (0..80) |i| {
        const cell = Renderer.Cell{ .char = @intCast(i % 26 + 'A') };
        try renderer.drawCell(i, 0, cell);
    }
    
    // Scroll up
    renderer.scroll(1);
    
    // Verify content moved
    const cell = renderer.getCell(0, 0);
    try testing.expect(cell.char == ' ');
}

// src/input.zig tests
const Input = @import("input.zig");

test "Input key processing" {
    const allocator = testing.allocator;
    
    var input = try Input.init(allocator);
    defer input.deinit();
    
    const key_event = Input.KeyEvent{
        .code = .A,
        .mods = .{ .ctrl = true },
        .pressed = true,
    };
    
    const sequence = try input.processKey(key_event);
    defer allocator.free(sequence);
    
    try testing.expect(sequence.len > 0);
}

test "Input mouse processing" {
    const allocator = testing.allocator;
    
    var input = try Input.init(allocator);
    defer input.deinit();
    
    const mouse_event = Input.MouseEvent{
        .x = 10,
        .y = 5,
        .button = .left,
        .pressed = true,
        .mods = .{},
    };
    
    const sequence = try input.processMouse(mouse_event);
    defer allocator.free(sequence);
    
    try testing.expect(sequence.len > 0);
}

test "Input paste handling" {
    const allocator = testing.allocator;
    
    var input = try Input.init(allocator);
    defer input.deinit();
    
    const text = "Hello, World!";
    const sequence = try input.pasteText(text);
    defer allocator.free(sequence);
    
    try testing.expect(sequence.len > 0);
}

test "Input mode switching" {
    const allocator = testing.allocator;
    
    var input = try Input.init(allocator);
    defer input.deinit();
    
    try testing.expect(input.mode == .normal);
    
    input.setMode(.application);
    try testing.expect(input.mode == .application);
    
    input.setMode(.normal);
    try testing.expect(input.mode == .normal);
}

// src/global.zig tests
const Global = @import("global.zig");

test "Global state initialization" {
    const allocator = testing.allocator;
    
    Global.init(allocator);
    defer Global.deinit();
    
    try testing.expect(Global.isInitialized());
}

test "Global state access" {
    const allocator = testing.allocator;
    
    Global.init(allocator);
    defer Global.deinit();
    
    const state = Global.getState();
    try testing.expect(state != null);
}

test "Global state update" {
    const allocator = testing.allocator;
    
    Global.init(allocator);
    defer Global.deinit();
    
    var state = Global.getState().?;
    state.last_activity = std.time.timestamp();
    
    Global.updateState(state);
    const updated = Global.getState().?;
    try testing.expect(updated.last_activity == state.last_activity);
}

test "Global state thread safety" {
    const allocator = testing.allocator;
    
    Global.init(allocator);
    defer Global.deinit();
    
    // Test concurrent access
    const Thread = std.Thread;
    var threads: [4]Thread = undefined;
    
    for (&threads) |*thread| {
        thread.* = try std.Thread.spawn({}, struct {
            fn run(_: void) void {
                const state = Global.getState().?;
                _ = state;
            }
        }.run, .{});
    }
    
    for (threads) |thread| {
        thread.join();
    }
}

// src/quirks.zig tests
const Quirks = @import("quirks.zig");

test "Quirks detection" {
    const allocator = testing.allocator;
    
    var quirks = try Quirks.init(allocator);
    defer quirks.deinit();
    
    const shell = "/bin/bash";
    quirks.detectForShell(shell);
    
    try testing.expect(quirks.hasQuirk(.bash_newline));
}

test "Quirks application" {
    const allocator = testing.allocator;
    
    var quirks = try Quirks.init(allocator);
    defer quirks.deinit();
    
    // Enable a quirk
    quirks.enableQuirk(.xterm_color);
    
    const input = "\x1b[31mRed\x1b[0m";
    const processed = quirks.applyQuirks(input);
    
    try testing.expect(processed.len > 0);
}

test "Quirks configuration" {
    const allocator = testing.allocator;
    
    var quirks = try Quirks.init(allocator);
    defer quirks.deinit();
    
    const config = 
        \\quirks = ["xterm_color", "bash_newline"]
    ;
    
    try quirks.loadConfig(config);
    
    try testing.expect(quirks.hasQuirk(.xterm_color));
    try testing.expect(quirks.hasQuirk(.bash_newline));
}

test "Quirks terminal specific" {
    const allocator = testing.allocator;
    
    var quirks = try Quirks.init(allocator);
    defer quirks.deinit();
    
    const term = "xterm-256color";
    quirks.detectForTerminal(term);
    
    try testing.expect(quirks.hasQuirk(.xterm_color));
    try testing.expect(quirks.hasQuirk(.xterm_256color));
}

// Integration tests
test "App and Config integration" {
    const allocator = testing.allocator;
    
    const config_data = 
        \\font_size = 12
        \\theme = "light"
    ;
    
    var config = try Config.loadFromString(allocator, config_data);
    defer config.deinit();
    
    var app = try App.initWithConfig(allocator, config);
    defer app.deinit();
    
    try testing.expect(app.config.font_size == 12);
    try testing.expectEqualStrings("light", app.config.theme);
}

test "Pty and Input integration" {
    const allocator = testing.allocator;
    
    var pty = try Pty.init(allocator, 80, 24);
    defer pty.deinit();
    
    var input = try Input.init(allocator);
    defer input.deinit();
    
    const key_event = Input.KeyEvent{
        .code = .Enter,
        .mods = .{},
        .pressed = true,
    };
    
    const sequence = try input.processKey(key_event);
    _ = try pty.write(sequence);
    
    var buffer: [1024]u8 = undefined;
    const bytes_read = try pty.read(&buffer);
    
    try testing.expect(bytes_read > 0);
}

test "Renderer and Quirks integration" {
    const allocator = testing.allocator;
    
    var renderer = try Renderer.init(allocator, 80, 24);
    defer renderer.deinit();
    
    var quirks = try Quirks.init(allocator);
    defer quirks.deinit();
    
    quirks.enableQuirk(.xterm_color);
    
    const cell = Renderer.Cell{
        .char = 'A',
        .fg = .{ .r = 255, .g = 0, .b = 0 },
        .bg = .{ .r = 0, .g = 0, .b = 0 },
    };
    
    try renderer.drawCell(0, 0, cell);
    const output = renderer.renderWithQuirks(quirks);
    
    try testing.expect(output.len > 0);
}