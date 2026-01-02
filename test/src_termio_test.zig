const std = @import("std");
const testing = std.testing;
const Termio = @import("src/termio/Termio.zig");
const Exec = @import("src/termio/Exec.zig");
const Backend = @import("src/termio/backend.zig");
const Mailbox = @import("src/termio/mailbox.zig");
const Message = @import("src/termio/message.zig");
const Options = @import("src/termio/Options.zig");
const ShellIntegration = @import("src/termio/shell_integration.zig");
const StreamHandler = @import("src/termio/stream_handler.zig");
const Thread = @import("src/termio/Thread.zig");

test "Termio initialization and cleanup" {
    const allocator = testing.allocator;
    
    var termio = try Termio.init(allocator);
    defer termio.deinit();
    
    try testing.expect(termio.isInitialized());
    try testing.expect(!termio.isClosed());
}

test "Termio read/write operations" {
    const allocator = testing.allocator;
    
    var termio = try Termio.init(allocator);
    defer termio.deinit();
    
    const test_data = "Hello, Terminal!";
    var buffer: [256]u8 = undefined;
    
    const bytes_written = try termio.write(test_data);
    try testing.expect(bytes_written == test_data.len);
    
    const bytes_read = try termio.read(buffer[0..]);
    try testing.expect(bytes_read > 0);
    try testing.expect(std.mem.eql(u8, buffer[0..bytes_read], test_data));
}

test "Termio terminal size handling" {
    const allocator = testing.allocator;
    
    var termio = try Termio.init(allocator);
    defer termio.deinit();
    
    const size = try termio.getTerminalSize();
    try testing.expect(size.cols > 0);
    try testing.expect(size.rows > 0);
    
    try termio.setTerminalSize(80, 24);
    const new_size = try termio.getTerminalSize();
    try testing.expect(new_size.cols == 80);
    try testing.expect(new_size.rows == 24);
}

test "Exec command execution" {
    const allocator = testing.allocator;
    
    var exec = try Exec.init(allocator);
    defer exec.deinit();
    
    const result = try exec.execute(&[_][]const u8{ "echo", "test" });
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);
    
    try testing.expect(result.exit_code == 0);
    try testing.expect(std.mem.eql(u8, result.stdout, "test\n"));
}

test "Exec environment handling" {
    const allocator = testing.allocator;
    
    var exec = try Exec.init(allocator);
    defer exec.deinit();
    
    try exec.setEnvVar("TEST_VAR", "test_value");
    const value = try exec.getEnvVar("TEST_VAR");
    defer allocator.free(value);
    
    try testing.expect(std.mem.eql(u8, value, "test_value"));
}

test "Exec timeout handling" {
    const allocator = testing.allocator;
    
    var exec = try Exec.init(allocator);
    defer exec.deinit();
    
    exec.setTimeout(100);
    const result = exec.executeWithTimeout(&[_][]const u8{ "sleep", "1" }) catch |err| {
        try testing.expect(err == error.Timeout);
        return;
    };
    _ = result;
    try testing.expect(false);
}

test "Backend interface implementation" {
    const allocator = testing.allocator;
    
    var backend = try Backend.create(allocator, .posix);
    defer backend.destroy();
    
    try testing.expect(backend.isValid());
    try testing.expect(backend.getType() == .posix);
    
    const fd = try backend.open("/dev/null", .{ .read = true, .write = true });
    try testing.expect(fd >= 0);
    try backend.close(fd);
}

test "Backend switching" {
    const allocator = testing.allocator;
    
    var backend = try Backend.create(allocator, .posix);
    defer backend.destroy();
    
    try backend.switchTo(.windows);
    try testing.expect(backend.getType() == .windows);
    
    try backend.switchTo(.posix);
    try testing.expect(backend.getType() == .posix);
}

test "Mailbox message sending and receiving" {
    const allocator = testing.allocator;
    
    var mailbox = try Mailbox.init(allocator, 10);
    defer mailbox.deinit();
    
    const message = Message{ .type = .text, .data = "test message" };
    try mailbox.send(message);
    
    const received = try mailbox.receive();
    try testing.expect(received.type == .text);
    try testing.expect(std.mem.eql(u8, received.data, "test message"));
}

test "Mailbox capacity limits" {
    const allocator = testing.allocator;
    
    var mailbox = try Mailbox.init(allocator, 2);
    defer mailbox.deinit();
    
    const message = Message{ .type = .text, .data = "test" };
    try mailbox.send(message);
    try mailbox.send(message);
    
    const result = mailbox.send(message);
    try testing.expectError(error.MailboxFull, result);
}

test "Mailbox concurrent access" {
    const allocator = testing.allocator;
    
    var mailbox = try Mailbox.init(allocator, 100);
    defer mailbox.deinit();
    
    const thread = try std.Thread.spawn(.{}, struct {
        mailbox: *Mailbox,
        fn run(ctx: @This()) !void {
            for (0..50) |i| {
                const msg = Message{ .type = .text, .data = std.fmt.allocPrint(testing.allocator, "msg{d}", .{i}) catch return };
                ctx.mailbox.send(msg) catch return;
            }
        }
    }.run, .{&mailbox});
    defer thread.join();
    
    for (0..50) |_| {
        const msg = try mailbox.receive();
        defer allocator.free(msg.data);
        try testing.expect(msg.type == .text);
    }
}

test "Message serialization" {
    const allocator = testing.allocator;
    
    const original = Message{
        .type = .command,
        .data = "ls -la",
        .timestamp = std.time.timestamp(),
    };
    
    const serialized = try original.serialize(allocator);
    defer allocator.free(serialized);
    
    const deserialized = try Message.deserialize(serialized);
    try testing.expect(deserialized.type == original.type);
    try testing.expect(std.mem.eql(u8, deserialized.data, original.data));
    try testing.expect(deserialized.timestamp == original.timestamp);
}

test "Message validation" {
    const valid_msg = Message{ .type = .text, .data = "valid" };
    try testing.expect(valid_msg.isValid());
    
    const invalid_msg = Message{ .type = .text, .data = "" };
    try testing.expect(!invalid_msg.isValid());
}

test "Message types" {
    const text_msg = Message{ .type = .text, .data = "hello" };
    const cmd_msg = Message{ .type = .command, .data = "echo test" };
    const ctrl_msg = Message{ .type = .control, .data = "resize" };
    
    try testing.expect(text_msg.isText());
    try testing.expect(cmd_msg.isCommand());
    try testing.expect(ctrl_msg.isControl());
}

test "Options default values" {
    const allocator = testing.allocator;
    
    var options = try Options.init(allocator);
    defer options.deinit();
    
    try testing.expect(options.getFontSize() == 12);
    try testing.expect(options.getTheme() == .dark);
    try testing.expect(options.getScrollbackLines() == 10000);
}

test "Options parsing" {
    const allocator = testing.allocator;
    
    var options = try Options.init(allocator);
    defer options.deinit();
    
    try options.parse("--font-size=14 --theme=light --scrollback=5000");
    
    try testing.expect(options.getFontSize() == 14);
    try testing.expect(options.getTheme() == .light);
    try testing.expect(options.getScrollbackLines() == 5000);
}

test "Options validation" {
    const allocator = testing.allocator;
    
    var options = try Options.init(allocator);
    defer options.deinit();
    
    const result = options.parse("--font-size=0");
    try testing.expectError(error.InvalidValue, result);
}

test "ShellIntegration detection" {
    const allocator = testing.allocator;
    
    var shell = try ShellIntegration.init(allocator);
    defer shell.deinit();
    
    const detected = try shell.detectShell();
    try testing.expect(detected == .bash or detected == .zsh or detected == .fish);
}

test "ShellIntegration command injection" {
    const allocator = testing.allocator;
    
    var shell = try ShellIntegration.init(allocator);
    defer shell.deinit();
    
    const prompt_cmd = try shell.getPromptCommand();
    defer allocator.free(prompt_cmd);
    
    try testing.expect(prompt_cmd.len > 0);
    try testing.expect(std.mem.indexOf(u8, prompt_cmd, "PS1") != null);
}

test "ShellIntegration escape sequences" {
    const allocator = testing.allocator;
    
    var shell = try ShellIntegration.init(allocator);
    defer shell.deinit();
    
    const escape_seq = try shell.getEscapeSequence(.title, "Test Title");
    defer allocator.free(escape_seq);
    
    try testing.expect(std.mem.startsWith(u8, escape_seq, "\x1b]"));
    try testing.expect(std.mem.endsWith(u8, escape_seq, "\x07"));
}

test "StreamHandler basic operations" {
    const allocator = testing.allocator;
    
    var handler = try StreamHandler.init(allocator);
    defer handler.deinit();
    
    const input = "Hello\nWorld\n";
    try handler.write(input);
    
    var buffer: [256]u8 = undefined;
    const line1 = try handler.readLine(buffer[0..]);
    try testing.expect(std.mem.eql(u8, line1, "Hello"));
    
    const line2 = try handler.readLine(buffer[0..]);
    try testing.expect(std.mem.eql(u8, line2, "World"));
}

test "StreamHandler buffering" {
    const allocator = testing.allocator;
    
    var handler = try StreamHandler.init(allocator);
    defer handler.deinit();
    
    handler.setBufferSize(1024);
    try testing.expect(handler.getBufferSize() == 1024);
    
    const large_data = try allocator.alloc(u8, 2048);
    defer allocator.free(large_data);
    std.mem.set(u8, large_data, 'A');
    
    try handler.write(large_data);
    try testing.expect(handler.getBufferedBytes() == 2048);
}

test "StreamHandler async operations" {
    const allocator = testing.allocator;
    
    var handler = try StreamHandler.init(allocator);
    defer handler.deinit();
    
    const thread = try std.Thread.spawn(.{}, struct {
        handler: *StreamHandler,
        fn run(ctx: @This()) !void {
            std.time.sleep(100 * std.time.ns_per_ms);
            try ctx.handler.write("async data");
        }
    }.run, .{&handler});
    defer thread.join();
    
    var buffer: [256]u8 = undefined;
    const data = try handler.readAsync(buffer[0..], 200);
    try testing.expect(std.mem.eql(u8, data, "async data"));
}

test "Thread creation and execution" {
    const allocator = testing.allocator;
    
    var thread = try Thread.init(allocator);
    defer thread.deinit();
    
    var counter: u32 = 0;
    
    try thread.spawn(.{}, struct {
        counter: *u32,
        fn run(ctx: @This()) void {
            _ = @atomicRmw(u32, ctx.counter, .Add, 1, .monotonic);
        }
    }.run, .{&counter});
    
    try thread.join();
    try testing.expect(counter == 1);
}

test "Thread synchronization" {
    const allocator = testing.allocator;
    
    var thread = try Thread.init(allocator);
    defer thread.deinit();
    
    var mutex = std.Thread.Mutex{};
    var condition = std.Thread.Condition{};
    var ready: bool = false;
    
    try thread.spawn(.{}, struct {
        mutex: *std.Thread.Mutex,
        condition: *std.Thread.Condition,
        ready: *bool,
        fn run(ctx: @This()) void {
            ctx.mutex.lock();
            ctx.ready.* = true;
            ctx.condition.signal();
            ctx.mutex.unlock();
        }
    }.run, .{ &mutex, &condition, &ready });
    
    mutex.lock();
    while (!ready) {
        condition.wait(&mutex);
    }
    mutex.unlock();
    
    try thread.join();
    try testing.expect(ready);
}

test "Thread pool operations" {
    const allocator = testing.allocator;
    
    var pool = try Thread.createPool(allocator, 4);
    defer pool.destroy();
    
    var sum: u64 = 0;
    const tasks = [_]u64{ 1, 2, 3, 4, 5, 6, 7, 8 };
    
    for (tasks) |value| {
        try pool.spawn(.{}, struct {
            sum: *u64,
            value: u64,
            fn run(ctx: @This()) void {
                _ = @atomicRmw(u64, ctx.sum, .Add, ctx.value, .monotonic);
            }
        }.run, .{ &sum, value });
    }
    
    try pool.wait();
    try testing.expect(sum == 36);
}

test "Thread cancellation" {
    const allocator = testing.allocator;
    
    var thread = try Thread.init(allocator);
    defer thread.deinit();
    
    try thread.spawn(.{}, struct {
        fn run() void {
            std.time.sleep(1000 * std.time.ns_per_ms);
        }
    }.run, .{});
    
    std.time.sleep(100 * std.time.ns_per_ms);
    try thread.cancel();
    
    const result = thread.join();
    try testing.expectError(error.ThreadCancelled, result);
}

test "Integrated terminal workflow" {
    const allocator = testing.allocator;
    
    var termio = try Termio.init(allocator);
    defer termio.deinit();
    
    var exec = try Exec.init(allocator);
    defer exec.deinit();
    
    var mailbox = try Mailbox.init(allocator, 10);
    defer mailbox.deinit();
    
    var handler = try StreamHandler.init(allocator);
    defer handler.deinit();
    
    const command = "echo 'Terminal Test'";
    const result = try exec.execute(&[_][]const u8{ "sh", "-c", command });
    defer allocator.free(result.stdout);
    
    try handler.write(result.stdout);
    
    var buffer: [256]u8 = undefined;
    const output = try handler.read(buffer[0..]);
    
    const message = Message{ .type = .text, .data = output };
    try mailbox.send(message);
    
    const received = try mailbox.receive();
    try testing.expect(std.mem.eql(u8, received.data, "Terminal Test\n"));
}

test "Error handling across modules" {
    const allocator = testing.allocator;
    
    var termio = try Termio.init(allocator);
    defer termio.deinit();
    
    var exec = try Exec.init(allocator);
    defer exec.deinit();
    
    const result = exec.execute(&[_][]const u8{ "nonexistent_command" });
    try testing.expectError(error.CommandNotFound, result);
    
    const invalid_fd: i32 = -1;
    const read_result = termio.readFd(invalid_fd, undefined);
    try testing.expectError(error.InvalidFileDescriptor, read_result);
}

test "Memory management verification" {
    const allocator = testing.allocator;
    
    var mailbox = try Mailbox.init(allocator, 100);
    defer mailbox.deinit();
    
    for (0..1000) |i| {
        const msg_data = try std.fmt.allocPrint(allocator, "message_{d}", .{i});
        const message = Message{ .type = .text, .data = msg_data };
        try mailbox.send(message);
        
        const received = try mailbox.receive();
        allocator.free(received.data);
    }
    
    try testing.expect(mailbox.isEmpty());
}