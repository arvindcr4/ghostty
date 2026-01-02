const std = @import("std");
const testing = std.testing;
const mem = std.mem;
const ArrayList = std.ArrayList;

// Import the modules to test
const cli = @import("cli.zig");
const Command = @import("Command.zig");
const input = @import("input.zig");
const global = @import("global.zig");
const apprt = @import("apprt.zig");

// Mock allocator for tests
const test_allocator = testing.allocator;

// Test CLI argument parsing
test "cli.parseArgs - basic arguments" {
    const args = [_][]const u8{ "ghostty", "--config", "/path/to/config", "--profile", "default" };
    
    var result = try cli.parseArgs(test_allocator, &args);
    defer result.deinit();
    
    try testing.expectEqualStrings("/path/to/config", result.config_path);
    try testing.expectEqualStrings("default", result.profile);
    try testing.expect(!result.debug);
    try testing.expect(!result.verbose);
}

test "cli.parseArgs - with debug flag" {
    const args = [_][]const u8{ "ghostty", "--debug", "--verbose" };
    
    var result = try cli.parseArgs(test_allocator, &args);
    defer result.deinit();
    
    try testing.expect(result.debug);
    try testing.expect(result.verbose);
}

test "cli.parseArgs - invalid argument" {
    const args = [_][]const u8{ "ghostty", "--invalid-flag" };
    
    const result = cli.parseArgs(test_allocator, &args);
    try testing.expectError(error.InvalidArgument, result);
}

test "cli.parseArgs - help flag" {
    const args = [_][]const u8{ "ghostty", "--help" };
    
    var result = try cli.parseArgs(test_allocator, &args);
    defer result.deinit();
    
    try testing.expect(result.show_help);
}

// Test Command processing
test "Command.parse - simple command" {
    const cmd_str = "new-tab";
    var cmd = try Command.parse(test_allocator, cmd_str);
    defer cmd.deinit();
    
    try testing.expectEqual(Command.Type.new_tab, cmd.type);
    try testing.expectEqual(@as(usize, 0), cmd.args.items.len);
}

test "Command.parse - command with arguments" {
    const cmd_str = "set-font-size 14";
    var cmd = try Command.parse(test_allocator, cmd_str);
    defer cmd.deinit();
    
    try testing.expectEqual(Command.Type.set_font_size, cmd.type);
    try testing.expectEqual(@as(usize, 1), cmd.args.items.len);
    try testing.expectEqualStrings("14", cmd.args.items[0]);
}

test "Command.parse - quoted arguments" {
    const cmd_str = "set-title \"My Terminal\"";
    var cmd = try Command.parse(test_allocator, cmd_str);
    defer cmd.deinit();
    
    try testing.expectEqual(Command.Type.set_title, cmd.type);
    try testing.expectEqual(@as(usize, 1), cmd.args.items.len);
    try testing.expectEqualStrings("My Terminal", cmd.args.items[0]);
}

test "Command.parse - invalid command" {
    const cmd_str = "invalid-command";
    const result = Command.parse(test_allocator, cmd_str);
    try testing.expectError(error.UnknownCommand, result);
}

test "Command.execute - new tab command" {
    var cmd = Command{
        .type = Command.Type.new_tab,
        .args = ArrayList([]const u8).init(test_allocator),
    };
    defer cmd.args.deinit();
    
    const result = try cmd.execute();
    try testing.expect(result.success);
}

test "Command.execute - set font size with validation" {
    var cmd = Command{
        .type = Command.Type.set_font_size,
        .args = ArrayList([]const u8).init(test_allocator),
    };
    defer cmd.args.deinit();
    
    try cmd.args.append("16");
    
    const result = try cmd.execute();
    try testing.expect(result.success);
}

test "Command.execute - invalid font size" {
    var cmd = Command{
        .type = Command.Type.set_font_size,
        .args = ArrayList([]const u8).init(test_allocator),
    };
    defer cmd.args.deinit();
    
    try cmd.args.append("invalid");
    
    const result = cmd.execute();
    try testing.expectError(error.InvalidArgument, result);
}

// Test Input handling
test "input.KeyEvent - basic key press" {
    const event = input.KeyEvent{
        .key = .a,
        .mods = .{},
        .action = .press,
    };
    
    try testing.expectEqual(input.Key.a, event.key);
    try testing.expectEqual(input.Modifier{}, event.mods);
    try testing.expectEqual(input.Action.press, event.action);
}

test "input.KeyEvent - key with modifiers" {
    const event = input.KeyEvent{
        .key = .c,
        .mods = .{ .ctrl = true, .shift = true },
        .action = .press,
    };
    
    try testing.expect(event.mods.ctrl);
    try testing.expect(event.mods.shift);
    try testing.expect(!event.mods.alt);
}

test "input.MouseEvent - mouse click" {
    const event = input.MouseEvent{
        .button = .left,
        .x = 100,
        .y = 200,
        .mods = .{},
        .action = .press,
    };
    
    try testing.expectEqual(input.MouseButton.left, event.button);
    try testing.expectEqual(@as(u32, 100), event.x);
    try testing.expectEqual(@as(u32, 200), event.y);
}

test "input.EventQueue - enqueue and dequeue" {
    var queue = input.EventQueue.init(test_allocator);
    defer queue.deinit();
    
    const key_event = input.KeyEvent{
        .key = .enter,
        .mods = .{},
        .action = .press,
    };
    
    try queue.enqueue(.{ .key = key_event });
    
    const dequeued = try queue.dequeue();
    switch (dequeued) {
        .key => |k| {
            try testing.expectEqual(input.Key.enter, k.key);
        },
        else => unreachable,
    }
}

test "input.EventQueue - empty queue" {
    var queue = input.EventQueue.init(test_allocator);
    defer queue.deinit();
    
    const result = queue.dequeue();
    try testing.expectError(error.Empty, result);
}

test "input.EventFilter - filter by modifier" {
    var filter = input.EventFilter.init();
    filter.required_modifiers.ctrl = true;
    
    const event_with_ctrl = input.KeyEvent{
        .key = .c,
        .mods = .{ .ctrl = true },
        .action = .press,
    };
    
    const event_without_ctrl = input.KeyEvent{
        .key = .c,
        .mods = .{},
        .action = .press,
    };
    
    try testing.expect(filter.matches(.{ .key = event_with_ctrl }));
    try testing.expect(!filter.matches(.{ .key = event_without_ctrl }));
}

// Test Global state management
test "global.State - initialization" {
    var state = try global.State.init(test_allocator);
    defer state.deinit();
    
    try testing.expectEqual(@as(u32, 0), state.tab_count);
    try testing.expectEqual(@as(u32, 0), state.window_count);
    try testing.expect(state.config != null);
}

test "global.State - add tab" {
    var state = try global.State.init(test_allocator);
    defer state.deinit();
    
    try state.addTab();
    try testing.expectEqual(@as(u32, 1), state.tab_count);
    
    try state.addTab();
    try testing.expectEqual(@as(u32, 2), state.tab_count);
}

test "global.State - remove tab" {
    var state = try global.State.init(test_allocator);
    defer state.deinit();
    
    try state.addTab();
    try state.addTab();
    
    try state.removeTab(0);
    try testing.expectEqual(@as(u32, 1), state.tab_count);
}

test "global.State - remove non-existent tab" {
    var state = try global.State.init(test_allocator);
    defer state.deinit();
    
    const result = state.removeTab(0);
    try testing.expectError(error.InvalidTab, result);
}

test "global.State - configuration" {
    var state = try global.State.init(test_allocator);
    defer state.deinit();
    
    try state.setConfig("font_size", "14");
    const value = try state.getConfig("font_size");
    try testing.expectEqualStrings("14", value);
}

test "global.State - get non-existent config" {
    var state = try global.State.init(test_allocator);
    defer state.deinit();
    
    const result = state.getConfig("non_existent");
    try testing.expectError(error.ConfigNotFound, result);
}

// Test Application Runtime
test "apprt.Runtime - initialization" {
    var runtime = try apprt.Runtime.init(test_allocator);
    defer runtime.deinit();
    
    try testing.expect(runtime.isRunning());
    try testing.expect(runtime.event_loop != null);
}

test "apprt.Runtime - start and stop" {
    var runtime = try apprt.Runtime.init(test_allocator);
    defer runtime.deinit();
    
    try runtime.start();
    try testing.expect(runtime.isRunning());
    
    runtime.stop();
    try testing.expect(!runtime.isRunning());
}

test "apprt.Runtime - event dispatch" {
    var runtime = try apprt.Runtime.init(test_allocator);
    defer runtime.deinit();
    
    var handler_called = false;
    
    const test_handler = struct {
        fn handle(event: anytype) void {
            _ = event;
            handler_called = true;
        }
    }.handle;
    
    try runtime.registerEventHandler(.key_press, test_handler);
    
    const key_event = input.KeyEvent{
        .key = .space,
        .mods = .{},
        .action = .press,
    };
    
    try runtime.dispatchEvent(.{ .key = key_event });
    try testing.expect(handler_called);
}

test "apprt.Runtime - window management" {
    var runtime = try apprt.Runtime.init(test_allocator);
    defer runtime.deinit();
    
    const window_id = try runtime.createWindow();
    try testing.expect(window_id >= 0);
    
    const window = runtime.getWindow(window_id);
    try testing.expect(window != null);
    
    try runtime.destroyWindow(window_id);
    const window_after = runtime.getWindow(window_id);
    try testing.expect(window_after == null);
}

test "apprt.Runtime - invalid window access" {
    var runtime = try apprt.Runtime.init(test_allocator);
    defer runtime.deinit();
    
    const window = runtime.getWindow(999);
    try testing.expect(window == null);
}

// Test key binding resolution
test "input.KeyBindings - add and resolve binding" {
    var bindings = input.KeyBindings.init(test_allocator);
    defer bindings.deinit();
    
    const key_seq = [_]input.Key{ .ctrl, .c };
    const command = "copy";
    
    try bindings.add(&key_seq, command);
    
    const resolved = try bindings.resolve(&key_seq);
    try testing.expectEqualStrings(command, resolved);
}

test "input.KeyBindings - resolve non-existent binding" {
    var bindings = input.KeyBindings.init(test_allocator);
    defer bindings.deinit();
    
    const key_seq = [_]input.Key{ .ctrl, .x };
    
    const result = bindings.resolve(&key_seq);
    try testing.expectError(error.BindingNotFound, result);
}

test "input.KeyBindings - override binding" {
    var bindings = input.KeyBindings.init(test_allocator);
    defer bindings.deinit();
    
    const key_seq = [_]input.Key{ .ctrl, .v };
    
    try bindings.add(&key_seq, "paste-old");
    try bindings.add(&key_seq, "paste-new");
    
    const resolved = try bindings.resolve(&key_seq);
    try testing.expectEqualStrings("paste-new", resolved);
}

// Test edge cases for command parsing
test "Command.parse - empty command" {
    const cmd_str = "";
    const result = Command.parse(test_allocator, cmd_str);
    try testing.expectError(error.EmptyCommand, result);
}

test "Command.parse - command with too many arguments" {
    const cmd_str = "set-font-size 14 16 18";
    var cmd = try Command.parse(test_allocator, cmd_str);
    defer cmd.deinit();
    
    try testing.expectEqual(@as(usize, 3), cmd.args.items.len);
}

test "Command.parse - malformed quotes" {
    const cmd_str = "set-title \"unclosed quote";
    const result = Command.parse(test_allocator, cmd_str);
    try testing.expectError(error.MalformedCommand, result);
}

// Test input event filtering
test "input.EventFilter - complex filter" {
    var filter = input.EventFilter.init();
    filter.required_modifiers.ctrl = true;
    filter.required_modifiers.shift = true;
    filter.allowed_keys = &[_]input.Key{ .c, .v, .x };
    
    const valid_event = input.KeyEvent{
        .key = .c,
        .mods = .{ .ctrl = true, .shift = true },
        .action = .press,
    };
    
    const invalid_mod_event = input.KeyEvent{
        .key = .c,
        .mods = .{ .ctrl = true },
        .action = .press,
    };
    
    const invalid_key_event = input.KeyEvent{
        .key = .z,
        .mods = .{ .ctrl = true, .shift = true },
        .action = .press,
    };
    
    try testing.expect(filter.matches(.{ .key = valid_event }));
    try testing.expect(!filter.matches(.{ .key = invalid_mod_event }));
    try testing.expect(!filter.matches(.{ .key = invalid_key_event }));
}

// Test error handling in various scenarios
test "error handling - invalid CLI arguments combination" {
    const args = [_][]const u8{ "ghostty", "--config", "--profile" };
    const result = cli.parseArgs(test_allocator, &args);
    try testing.expectError(error.MissingArgument, result);
}

test "error handling - command execution with insufficient args" {
    var cmd = Command{
        .type = Command.Type.set_font_size,
        .args = ArrayList([]const u8).init(test_allocator),
    };
    defer cmd.args.deinit();
    
    const result = cmd.execute();
    try testing.expectError(error.InsufficientArguments, result);
}

test "error handling - global state with invalid operations" {
    var state = try global.State.init(test_allocator);
    defer state.deinit();
    
    // Try to remove more tabs than exist
    try state.addTab();
    try state.removeTab(0);
    
    const result = state.removeTab(0);
    try testing.expectError(error.InvalidTab, result);
}

test "error handling - runtime with invalid event type" {
    var runtime = try apprt.Runtime.init(test_allocator);
    defer runtime.deinit();
    
    const result = runtime.registerEventHandler(.invalid_event, null);
    try testing.expectError(error.InvalidEventType, result);
}