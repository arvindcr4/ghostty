// test/benchmark/Benchmark.zig
const std = @import("std");
const testing = std.testing;
const time = std.time;
const Benchmark = @import("../src/benchmark/Benchmark.zig");

test "Benchmark.measurement_accuracy" {
    const allocator = testing.allocator;
    
    // Test that benchmark measurements are reasonable
    var bench = try Benchmark.init(allocator, "test_benchmark");
    defer bench.deinit();
    
    // Simple operation that should take some time
    const start_time = time.nanoTimestamp();
    
    try bench.measure("simple_operation", struct {
        fn operation() void {
            var sum: u64 = 0;
            for (0..1000) |i| {
                sum += i;
            }
            std.testing.expect(sum == 499500) catch unreachable;
        }
    }.operation);
    
    const end_time = time.nanoTimestamp();
    const elapsed = @as(u64, @intCast(end_time - start_time));
    
    // Benchmark should report reasonable timing
    const result = bench.getResult("simple_operation");
    try testing.expect(result != null);
    try testing.expect(result.?.duration_ns > 0);
    try testing.expect(result.?.duration_ns <= elapsed * 2); // Allow some overhead
}

test "Benchmark.multiple_measurements" {
    const allocator = testing.allocator;
    
    var bench = try Benchmark.init(allocator, "multi_test");
    defer bench.deinit();
    
    try bench.measure("operation_a", struct {
        fn operation() void {
            var i: u32 = 0;
            while (i < 100) : (i += 1) {
                _ = @sqrt(@as(f64, @floatFromInt(i)));
            }
        }
    }.operation);
    
    try bench.measure("operation_b", struct {
        fn operation() void {
            var i: u32 = 0;
            while (i < 200) : (i += 1) {
                _ = @sin(@as(f64, @floatFromInt(i)));
            }
        }
    }.operation);
    
    const result_a = bench.getResult("operation_a");
    const result_b = bench.getResult("operation_b");
    
    try testing.expect(result_a != null);
    try testing.expect(result_b != null);
    try testing.expect(result_a.?.duration_ns > 0);
    try testing.expect(result_b.?.duration_ns > 0);
}

test "Benchmark.iteration_count" {
    const allocator = testing.allocator;
    
    var bench = try Benchmark.init(allocator, "iteration_test");
    defer bench.deinit();
    
    var call_count: u32 = 0;
    
    try bench.measureWithIterations("counted_op", 10, struct {
        fn operation(counter: *u32) void {
            counter.* += 1;
        }
    }.operation, .{&call_count});
    
    try testing.expect(call_count == 10);
    
    const result = bench.getResult("counted_op");
    try testing.expect(result != null);
    try testing.expect(result.?.iterations == 10);
}

test "Benchmark.performance_regression" {
    const allocator = testing.allocator;
    
    var bench = try Benchmark.init(allocator, "regression_test");
    defer bench.deinit();
    
    // Test operation with known performance characteristics
    try bench.measure("fast_operation", struct {
        fn operation() void {
            var sum: u64 = 0;
            for (0..100) |i| {
                sum += i;
            }
            _ = sum;
        }
    }.operation);
    
    const result = bench.getResult("fast_operation");
    try testing.expect(result != null);
    
    // Should complete within reasonable time (less than 1ms for simple operation)
    try testing.expect(result.?.duration_ns < 1_000_000);
}

// test/benchmark/CodepointWidth.zig
const std = @import("std");
const testing = std.testing;
const CodepointWidth = @import("../src/benchmark/CodepointWidth.zig");

test "CodepointWidth.ascii_characters" {
    // Test ASCII characters (width 1)
    for (32..127) |cp| {
        const width = CodepointWidth.getWidth(cp);
        try testing.expect(width == 1);
    }
}

test "CodepointWidth.emoji_width" {
    // Test common emoji (width 2)
    const emoji = [_]u32{
        0x1F600, // 😀
        0x1F603, // 😃
        0x1F60A, // 😊
        0x2764,  // ❤️
        0x1F44D, // 👍
    };
    
    for (emoji) |cp| {
        const width = CodepointWidth.getWidth(cp);
        try testing.expect(width == 2);
    }
}

test "CodepointWidth.cjk_characters" {
    // Test CJK characters (width 2)
    const cjk = [_]u32{
        0x4E00, // 一
        0x4E8C, // 二
        0x4E09, // 三
        0x4E5D, // 九
        0x4E03, // 七
    };
    
    for (cjk) |cp| {
        const width = CodepointWidth.getWidth(cp);
        try testing.expect(width == 2);
    }
}

test "CodepointWidth.control_characters" {
    // Test control characters (width 0)
    const control = [_]u32{
        0x00, // NULL
        0x07, // BEL
        0x08, // BS
        0x09, // HT
        0x0A, // LF
        0x0D, // CR
    };
    
    for (control) |cp| {
        const width = CodepointWidth.getWidth(cp);
        try testing.expect(width == 0);
    }
}

test "CodepointWidth.combining_characters" {
    // Test combining characters (width 0)
    const combining = [_]u32{
        0x0300, // Combining grave accent
        0x0301, // Combining acute accent
        0x0302, // Combining circumflex
        0x0303, // Combining tilde
        0x0304, // Combining macron
    };
    
    for (combining) |cp| {
        const width = CodepointWidth.getWidth(cp);
        try testing.expect(width == 0);
    }
}

test "CodepointWidth.performance" {
    const start_time = std.time.nanoTimestamp();
    
    // Test performance with many lookups
    var sum: u32 = 0;
    for (0..10000) |i| {
        sum += CodepointWidth.getWidth(@as(u32, @intCast(i % 0x10000)));
    }
    
    const end_time = std.time.nanoTimestamp();
    const elapsed = @as(u64, @intCast(end_time - start_time));
    
    // Should complete quickly (less than 10ms for 10k lookups)
    try testing.expect(elapsed < 10_000_000);
    _ = sum; // Use sum to prevent optimization
}

// test/benchmark/GraphemeBreak.zig
const std = @import("std");
const testing = std.testing;
const GraphemeBreak = @import("../src/benchmark/GraphemeBreak.zig");

test "GraphemeBreak.ascii_single" {
    // Each ASCII character should be its own grapheme
    const str = "Hello, World!";
    var iter = GraphemeBreak.Iterator.init(str);
    
    var count: usize = 0;
    while (iter.next()) |cluster| {
        count += 1;
        try testing.expect(cluster.len == 1);
    }
    
    try testing.expect(count == str.len);
}

test "GraphemeBreak.emoji_sequences" {
    // Test emoji with skin tone modifiers
    const str = "👍🏻👍🏼👍🏽👍🏾👍🏿";
    var iter = GraphemeBreak.Iterator.init(str);
    
    var count: usize = 0;
    while (iter.next()) |cluster| {
        count += 1;
        // Each emoji with skin tone should be one grapheme
        try testing.expect(cluster.len > 0);
    }
    
    try testing.expect(count == 5);
}

test "GraphemeBreak.combining_marks" {
    // Test characters with combining marks
    const str = "e\u{0301}e\u{0300}e\u{0302}"; // e with various accents
    var iter = GraphemeBreak.Iterator.init(str);
    
    var count: usize = 0;
    while (iter.next()) |cluster| {
        count += 1;
        // Each base + combining should be one grapheme
        try testing.expect(cluster.len == 2);
    }
    
    try testing.expect(count == 3);
}

test "GraphemeBreak.hangul_syllables" {
    // Test Hangul syllable composition
    const str = "한글";
    var iter = GraphemeBreak.Iterator.init(str);
    
    var count: usize = 0;
    while (iter.next()) |cluster| {
        count += 1;
    }
    
    try testing.expect(count == 2);
}

test "GraphemeBreak.regional_indicators" {
    // Test regional indicator pairs (flags)
    const str = "🇺���🇨🇦🇲🇽";
    var iter = GraphemeBreak.Iterator.init(str);
    
    var count: usize = 0;
    while (iter.next()) |cluster| {
        count += 1;
        // Each flag is two regional indicators
        try testing.expect(cluster.len == 8); // 4 bytes per emoji
    }
    
    try testing.expect(count == 3);
}

test "GraphemeBreak.performance" {
    const test_str = "The quick brown fox jumps over the lazy dog. 🦊🐕 1234567890";
    const start_time = std.time.nanoTimestamp();
    
    var iter = GraphemeBreak.Iterator.init(test_str);
    var count: usize = 0;
    while (iter.next()) |_| {
        count += 1;
    }
    
    const end_time = std.time.nanoTimestamp();
    const elapsed = @as(u64, @intCast(end_time - start_time));
    
    try testing.expect(count > 0);
    // Should complete quickly (less than 1ms for short string)
    try testing.expect(elapsed < 1_000_000);
}

// test/benchmark/IsSymbol.zig
const std = @import("std");
const testing = std.testing;
const IsSymbol = @import("../src/benchmark/IsSymbol.zig");

test "IsSymbol.mathematical_symbols" {
    const math_symbols = [_]u32{
        '+', '-', '*', '/', '=', '<', '>', '≠', '≤', '≥',
        '∑', '∏', '∫', '√', '∞', 'π', '±', '×', '÷',
    };
    
    for (math_symbols) |cp| {
        try testing.expect(IsSymbol.isSymbol(cp));
    }
}

test "IsSymbol.currency_symbols" {
    const currency_symbols = [_]u32{
        '$', '¢', '£', '¤', '¥', '€', '₹', '₽', '₩',
    };
    
    for (currency_symbols) |cp| {
        try testing.expect(IsSymbol.isSymbol(cp));
    }
}

test "IsSymbol.punctuation" {
    const punctuation = [_]u32{
        '!', '?', '.', ',', ';', ':', '"', '\'', '(', ')',
        '[', ']', '{', '}', '@', '#', '%', '&', '|', '\\',
    };
    
    for (punctuation) |cp| {
        try testing.expect(IsSymbol.isSymbol(cp));
    }
}

test "IsSymbol.emoji" {
    const emoji = [_]u32{
        0x1F600, // 😀
        0x1F603, // 😃
        0x1F44D, // 👍
        0x2764,  // ❤️
        0x1F525, // 🔥
    };
    
    for (emoji) |cp| {
        try testing.expect(IsSymbol.isSymbol(cp));
    }
}

test "IsSymbol.non_symbols" {
    const non_symbols = [_]u32{
        'a', 'b', 'c', '1', '2', '3', 'A', 'B', 'C',
        ' ', '\t', '\n', '\r',
        0x4E00, // CJK character
        0x0627, // Arabic letter
    };
    
    for (non_symbols) |cp| {
        try testing.expect(!IsSymbol.isSymbol(cp));
    }
}

test "IsSymbol.performance" {
    const start_time = std.time.nanoTimestamp();
    
    var symbol_count: u32 = 0;
    for (0..10000) |i| {
        const cp = @as(u32, @intCast(i % 0x10000));
        if (IsSymbol.isSymbol(cp)) {
            symbol_count += 1;
        }
    }
    
    const end_time = std.time.nanoTimestamp();
    const elapsed = @as(u64, @intCast(end_time - start_time));
    
    try testing.expect(symbol_count > 0);
    // Should complete quickly (less than 5ms for 10k checks)
    try testing.expect(elapsed < 5_000_000);
}

// test/benchmark/OscParser.zig
const std = @import("std");
const testing = std.testing;
const OscParser = @import("../src/benchmark/OscParser.zig");

test "OscParser.set_title" {
    const input = "\x1b]0;My Title\x07";
    var parser = OscParser.init();
    
    try parser.parse(input);
    
    const result = parser.getCommand();
    try testing.expect(result.cmd == .set_title);
    try testing.expect(std.mem.eql(u8, result.data, "My Title"));
}

test "OscParser.set_color" {
    const input = "\x1b]4;10;rgb:ff/ff/ff\x07";
    var parser = OscParser.init();
    
    try parser.parse(input);
    
    const result = parser.getCommand();
    try testing.expect(result.cmd == .set_color);
    try testing.expect(result.color_index == 10);
    try testing.expect(std.mem.eql(u8, result.data, "rgb:ff/ff/ff"));
}

test "OscParser.set_foreground_color" {
    const input = "\x1b]10;#ffffff\x07";
    var parser = OscParser.init();
    
    try parser.parse(input);
    
    const result = parser.getCommand();
    try testing.expect(result.cmd == .set_foreground_color);
    try testing.expect(std.mem.eql(u8, result.data, "#ffffff"));
}

test "OscParser.set_background_color" {
    const input = "\x1b]11;#000000\x07";
    var parser = OscParser.init();
    
    try parser.parse(input);
    
    const result = parser.getCommand();
    try testing.expect(result.cmd == .set_background_color);
    try testing.expect(std.mem.eql(u8, result.data, "#000000"));
}

test "OscParser.hyperlink" {
    const input = "\x1b]8;;http://example.com\x07Click me\x1b]8;;\x07";
    var parser = OscParser.init();
    
    try parser.parse(input);
    
    const result = parser.getCommand();
    try testing.expect(result.cmd == .hyperlink);
    try testing.expect(std.mem.eql(u8, result.data, "http://example.com"));
}

test "OscParser.multiple_commands" {
    const input = "\x1b]0;Title\x07\x1b]10;#ff0000\x07";
    var parser = OscParser.init();
    
    var count: usize = 0;
    var pos: usize = 0;
    while (pos < input.len) {
        const cmd_len = try parser.parse(input[pos..]);
        if (cmd_len > 0) {
            count += 1;
            pos += cmd_len;
        } else {
            break;
        }
    }
    
    try testing.expect(count == 2);
}

test "OscParser.performance" {
    const input = "\x1b]0;Performance Test Title\x07";
    var parser = OscParser.init();
    
    const start_time = std.time.nanoTimestamp();
    
    for (0..1000) |_| {
        parser.reset();
        _ = try parser.parse(input);
    }
    
    const end_time = std.time.nanoTimestamp();
    const elapsed = @as(u64, @intCast(end_time - start_time));
    
    // Should complete quickly (less than 10ms for 1000 parses)
    try testing.expect(elapsed < 10_000_000);
}

// test/benchmark/ScreenClone.zig
const std = @import("std");
const testing = std.testing;
const ScreenClone = @import("../src/benchmark/ScreenClone.zig");
const Screen = @import("../src/Screen.zig");

test "ScreenClone.basic_clone" {
    const allocator = testing.allocator;
    
    var original = try Screen.init(allocator, 80, 24);
    defer original.deinit();
    
    // Write some content
    try original.writeString("Hello, World!");
    original.setCursor(10, 5);
    try original.writeString("Test");
    
    var cloned = try ScreenClone.clone(original);
    defer cloned.deinit();
    
    try testing.expect(cloned.width == original.width);
    try testing.expect(cloned.height == original.height);
    
    // Verify content is the same
    const original_content = try original.getRange(0, 0, 80, 24);
    const cloned_content = try cloned.getRange(0, 0, 80, 24);
    defer allocator.free(original_content);
    defer allocator.free(cloned_content);
    
    try testing.expect(std.mem.eql(u8, original_content, cloned_content));
}

test "ScreenClone.large_screen" {
    const allocator = testing.allocator;
    
    var original = try Screen.init(allocator, 200, 100);
    defer original.deinit();
    
    // Fill with pattern
    for (0..100) |y| {
        for (0..200) |x| {
            const ch = @as(u8, @intCast((x + y) % 256));
            try original.writeChar(x, y, ch);
        }
    }
    
    const start_time = std.time.nanoTimestamp();
    
    var cloned = try ScreenClone.clone(original);
    defer cloned.deinit();
    
    const end_time = std.time.nanoTimestamp();
    const elapsed = @as(u64, @intCast(end_time - start_time));
    
    // Verify clone is correct
    try testing.expect(cloned.width == 200);
    try testing.expect(cloned.height == 100);
    
    // Should complete in reasonable time (less than 100ms for 20k chars)
    try testing.expect(elapsed < 100_000_000);
}

test "ScreenClone.with_attributes" {
    const allocator = testing.allocator;
    
    var original = try Screen.init(allocator, 80, 24);
    defer original.deinit();
    
    // Write with different attributes
    original.setAttribute(.{ .bold = true });
    try original.writeString("Bold");
    original.setAttribute(.{ .italic = true });
    try original.writeString("Italic");
    original.setAttribute(.{ .foreground = .red });
    try original.writeString("Red");
    
    var cloned = try ScreenClone.clone(original);
    defer cloned.deinit();
    
    // Verify attributes are preserved
    const attrs = try cloned.getAttributes(0, 0, 10);
    defer allocator.free(attrs);
    
    try testing.expect(attrs[0].bold);
    try testing.expect(attrs[4].italic);
    try testing.expect(attrs[11].foreground == .red);
}

test "ScreenClone.performance_regression" {
    const allocator = testing.allocator;
    
    var original = try Screen.init(allocator, 80, 24);
    defer original.deinit();
    
    // Fill screen
    for (0..24) |y| {
        original.setCursor(0, y);
        try original.writeString("This is a test line for performance benchmarking. ");
    }
    
    const iterations = 100;
    const start_time = std.time.nanoTimestamp();
    
    for (0..iterations) |_| {
        var cloned = try ScreenClone.clone(original);
        cloned.deinit();
    }
    
    const end_time = std.time.nanoTimestamp();
    const elapsed = @as(u64, @intCast(end_time - start_time));
    const avg_time = elapsed / iterations;
    
    // Average clone time should be small (less than 1ms)
    try testing.expect(avg_time < 1_000_000);
}

// test/benchmark/TerminalParser.zig
const std = @import("std");
const testing = std.testing;
const TerminalParser = @import("../src/benchmark/TerminalParser.zig");

test "TerminalParser.plain_text" {
    const input = "Hello, World!";
    var parser = TerminalParser.init();
    
    try parser.parse(input);
    
    const output = parser.getOutput();
    try testing.expect(std.mem.eql(u8, output, input));
}

test "TerminalParser.ansi_colors" {
    const input = "\x1b[31mRed\x1b[0m \x1b[32mGreen\x1b[0m \x1b[34mBlue\x1b[0m";
    var parser = TerminalParser.init();
    
    try parser.parse(input);
    
    const output = parser.getOutput();
    try testing.expect(std.mem.indexOf(u8, output, "Red") != null);
    try testing.expect(std.mem.indexOf(u8, output, "Green") != null);
    try testing.expect(std.mem.indexOf(u8, output, "Blue") != null);
}

test "TerminalParser.cursor_movement" {
    const input = "ABC\x1b[3D\x1b[2CDE";
    var parser = TerminalParser.init();
    
    try parser.parse(input);
    
    const output = parser.getOutput();
    // Should result in "ADE" (move back 3, forward 2, write DE)
    try testing.expect(std.mem.eql(u8, output, "ADE"));
}

test "TerminalParser.clear_screen" {
    const input = "Hello\x1b[2JWorld";
    var parser = TerminalParser.init();
    
    try parser.parse(input);
    
    const output = parser.getOutput();
    // Should only contain "World" after clear
    try testing.expect(std.mem.eql(u8, output, "World"));
}

test "TerminalParser.complex_sequence" {
    const input = "\x1b[1;31mBold Red\x1b[0m\n\x1b[4;32mUnderlined Green\x1b[0m";
    var parser = TerminalParser.init();
    
    try parser.parse(input);
    
    const output = parser.getOutput();
    try testing.expect(std.mem.indexOf(u8, output, "Bold Red") != null);
    try testing.expect(std.mem.indexOf(u8, output, "Underlined Green") != null);
    try testing.expect(std.mem.indexOf(u8, output, "\n") != null);
}

test "TerminalParser.performance" {
    const allocator = testing.allocator;
    
    // Generate complex input
    var input = std.ArrayList(u8).init(allocator);
    defer input.deinit();
    
    for (0..1000) |i| {
        try input.appendSlice("Line ");
        try std.fmt.formatInt(i, 10, .lower, .{}, input.writer()) catch unreachable;
        try input.appendSlice(" with \x1b[31mred\x1b[0m and \x1b[32mgreen\x1b[0m text\n");
    }
    
    var parser = TerminalParser.init();
    
    const start_time = std.time.nanoTimestamp();
    
    try parser.parse(input.items);
    
    const end_time = std.time.nanoTimestamp();
    const elapsed = @as(u64, @intCast(end_time - start_time));
    
    const output = parser.getOutput();
    try testing.expect(output.len > 0);
    
    // Should complete in reasonable time (less than 50ms for ~50k chars)
    try testing.expect(elapsed < 50_000_000);
}

// test/benchmark/TerminalStream.zig
const std = @import("std");
const testing = std.testing;
const TerminalStream = @import("../src/benchmark/TerminalStream.zig");

test "TerminalStream.basic_write" {
    const allocator = testing.allocator;
    
    var stream = try TerminalStream.init(allocator, 80, 24);
    defer stream.deinit();
    
    try stream.write("Hello, World!");
    
    const content = try stream.getScreenContent();
    defer allocator.free(content);
    
    try testing.expect(std.mem.startsWith(u8, content, "Hello, World!"));
}

test "TerminalStream.line_wrapping" {
    const allocator = testing.allocator;
    
    var stream = try TerminalStream.init(allocator, 10, 24);
    defer stream.deinit();
    
    try stream.write("This is a very long line that should wrap");
    
    const content = try stream.getScreenContent();
    defer allocator.free(content);
    
    // Should contain wrapped content
    try testing.expect(std.mem.indexOf(u8, content, "This is a") != null);
    try testing.expect(std.mem.indexOf(u8, content, "very long") != null);
}

test "TerminalStream.backspace" {
    const allocator = testing.allocator;
    
    var stream = try TerminalStream.init(allocator, 80, 24);
    defer stream.deinit();
    
    try stream.write("Hello\x08\x08World");
    
    const content = try stream.getScreenContent();
    defer allocator.free(content);
    
    // Should result in "HelWorld"
    try testing.expect(std.mem.indexOf(u8, content, "HelWorld") != null);
}

test "TerminalStream.carriage_return" {
    const allocator = testing.allocator;
    
    var stream = try TerminalStream.init(allocator, 80, 24);
    defer stream.deinit();
    
    try stream.write("Hello\rWorld");
    
    const content = try stream.getScreenContent();
    defer allocator.free(content);
    
    // Should result in "World"
    try testing.expect(std.mem.startsWith(u8, content, "World"));
}

test "TerminalStream.tab_handling" {
    const allocator = testing.allocator;
    
    var stream = try TerminalStream.init(allocator, 80, 24);
    defer stream.deinit();
    
    try stream.write("A\tB\tC");
    
    const content = try stream.getScreenContent();
    defer allocator.free(content);
    
    // Should expand tabs to spaces
    try testing.expect(content.len > 5); // Tabs should be expanded
}

test "TerminalStream.ansi_sequences" {
    const allocator = testing.allocator;
    
    var stream = try TerminalStream.init(allocator, 80, 24);
    defer stream.deinit();
    
    try stream.write("\x1b[31mRed Text\x1b[0m Normal Text");
    
    const content = try stream.getScreenContent();
    defer allocator.free(content);
    
    // Should contain text without ANSI codes
    try testing.expect(std.mem.indexOf(u8, content, "Red Text") != null);
    try testing.expect(std.mem.indexOf(u8, content, "Normal Text") != null);
    // Should not contain ANSI escape sequences
    try testing.expect(std.mem.indexOf(u8, content, "\x1b[31m") == null);
}

test "TerminalStream.performance" {
    const allocator = testing.allocator;
    
    var stream = try TerminalStream.init(allocator, 80, 24);
    defer stream.deinit();
    
    const test_data = "The quick brown fox jumps over the lazy dog. ";
    const iterations = 1000;
    
    const start_time = std.time.nanoTimestamp();
    
    for (0..iterations) |_| {
        try stream.write(test_data);
    }
    
    const end_time = std.time.nanoTimestamp();
    const elapsed = @as(u64, @intCast(end_time - start_time));
    
    const content = try stream.getScreenContent();
    defer allocator.free(content);
    
    try testing.expect(content.len > 0);
    
    // Should complete quickly (less than 100ms for 43k chars)
    try testing.expect(elapsed < 100_000_000);
}

test "TerminalStream.scroll_behavior" {
    const allocator = testing.allocator;
    
    var stream = try TerminalStream.init(allocator, 80, 5);
    defer stream.deinit();
    
    // Write more lines than screen height
    for (0..10) |i| {
        try std.fmt.format(stream.writer(), "Line {}\n", .{i});
    }
    
    const content = try stream.getScreenContent();
    defer allocator.free(content);
    
    // Should contain last 5 lines
    try testing.expect(std.mem.indexOf(u8, content, "Line 5") != null);
    try testing.expect(std.mem.indexOf(u8, content, "Line 9") != null);
    try testing.expect(std.mem.indexOf(u8, content, "Line 0") == null);
}