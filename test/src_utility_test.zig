const std = @import("std");
const testing = std.testing;
const fastmem = @import("src/fastmem.zig");
const file_type = @import("src/file_type.zig");
const quirks = @import("src/quirks.zig");
const lib_vt = @import("src/lib_vt.zig");
const helpgen = @import("src/helpgen.zig");
const build_config = @import("src/build_config.zig");

// Tests for fastmem.zig
test "fastmem.memcpy - basic copy" {
    const src = "Hello, World!";
    var dest: [13]u8 = undefined;
    
    fastmem.memcpy(dest[0..], src);
    try testing.expectEqualStrings(src, &dest);
}

test "fastmem.memcpy - zero length" {
    const src = "test";
    var dest: [4]u8 = undefined;
    
    fastmem.memcpy(dest[0..0], src[0..0]);
    // Should not crash
}

test "fastmem.memcpy - large buffer" {
    const allocator = testing.allocator;
    const size = 1024 * 1024; // 1MB
    var src = try allocator.alloc(u8, size);
    defer allocator.free(src);
    var dest = try allocator.alloc(u8, size);
    defer allocator.free(dest);
    
    // Fill source with pattern
    for (src, 0..) |*byte, i| {
        byte.* = @intCast(i % 256);
    }
    
    fastmem.memcpy(dest, src);
    try testing.expectEqualSlices(u8, src, dest);
}

test "fastmem.memset - basic set" {
    var buf: [10]u8 = undefined;
    const value: u8 = 0xAB;
    
    fastmem.memset(buf[0..], value);
    for (buf) |byte| {
        try testing.expectEqual(value, byte);
    }
}

test "fastmem.memcmp - equal buffers" {
    const buf1 = "Test string";
    const buf2 = "Test string";
    
    const result = fastmem.memcmp(buf1, buf2);
    try testing.expectEqual(@as(i32, 0), result);
}

test "fastmem.memcmp - different buffers" {
    const buf1 = "Test string A";
    const buf2 = "Test string B";
    
    const result = fastmem.memcmp(buf1, buf2);
    try testing.expect(result < 0);
}

test "fastmem.memmove - overlapping regions" {
    var buf: [20]u8 = "Hello, World!______";
    const src = buf[7..13]; // "World!"
    const dest = buf[0..6];
    
    fastmem.memmove(dest, src);
    try testing.expectEqualStrings("World!", dest);
}

// Tests for file_type.zig
test "file_type.detectFromExtension - common types" {
    try testing.expectEqual(file_type.Type.Text, file_type.detectFromExtension(".txt"));
    try testing.expectEqual(file_type.Type.Binary, file_type.detectFromExtension(".exe"));
    try testing.expectEqual(file_type.Type.Image, file_type.detectFromExtension(".png"));
    try testing.expectEqual(file_type.Type.Image, file_type.detectFromExtension(".jpg"));
    try testing.expectEqual(file_type.Type.Archive, file_type.detectFromExtension(".zip"));
    try testing.expectEqual(file_type.Type.Archive, file_type.detectFromExtension(".tar"));
}

test "file_type.detectFromExtension - case insensitive" {
    try testing.expectEqual(file_type.Type.Text, file_type.detectFromExtension(".TXT"));
    try testing.expectEqual(file_type.Type.Image, file_type.detectFromExtension(".JpG"));
    try testing.expectEqual(file_type.Type.Archive, file_type.detectFromExtension(".ZIP"));
}

test "file_type.detectFromExtension - unknown extension" {
    try testing.expectEqual(file_type.Type.Unknown, file_type.detectFromExtension(".xyz"));
    try testing.expectEqual(file_type.Type.Unknown, file_type.detectFromExtension(""));
}

test "file_type.detectFromContent - text file" {
    const content = "This is a plain text file with ASCII characters.";
    try testing.expectEqual(file_type.Type.Text, file_type.detectFromContent(content));
}

test "file_type.detectFromContent - binary file" {
    const content = "\x00\x01\x02\x03\xFF\xFE\xFD";
    try testing.expectEqual(file_type.Type.Binary, file_type.detectFromContent(content));
}

test "file_type.detectFromContent - PNG signature" {
    const content = "\x89PNG\r\n\x1a\n";
    try testing.expectEqual(file_type.Type.Image, file_type.detectFromContent(content));
}

test "file_type.detectFromContent - ZIP signature" {
    const content = "PK\x03\x04";
    try testing.expectEqual(file_type.Type.Archive, file_type.detectFromContent(content));
}

test "file_type.isTextFile - text detection" {
    try testing.expect(file_type.isTextFile("Hello, world!"));
    try testing.expect(file_type.isTextFile("Line 1\nLine 2\nLine 3"));
    try testing.expect(!file_type.isTextFile("\x00\x01\x02"));
}

// Tests for quirks.zig
test "quirks.QuirkManager - initialization" {
    var manager = quirks.QuirkManager.init();
    try testing.expect(!manager.isEnabled(quirks.Quirk.BrokenColors));
    try testing.expect(!manager.isEnabled(quirks.Quirk.NoUnicode));
}

test "quirks.QuirkManager - enable/disable quirks" {
    var manager = quirks.QuirkManager.init();
    
    manager.enable(quirks.Quirk.BrokenColors);
    try testing.expect(manager.isEnabled(quirks.Quirk.BrokenColors));
    
    manager.disable(quirks.Quirk.BrokenColors);
    try testing.expect(!manager.isEnabled(quirks.Quirk.BrokenColors));
}

test "quirks.QuirkManager - toggle quirk" {
    var manager = quirks.QuirkManager.init();
    
    manager.toggle(quirks.Quirk.NoUnicode);
    try testing.expect(manager.isEnabled(quirks.Quirk.NoUnicode));
    
    manager.toggle(quirks.Quirk.NoUnicode);
    try testing.expect(!manager.isEnabled(quirks.Quirk.NoUnicode));
}

test "quirks.QuirkManager - set from string" {
    var manager = quirks.QuirkManager.init();
    
    try manager.setFromString("broken_colors,no_unicode");
    try testing.expect(manager.isEnabled(quirks.Quirk.BrokenColors));
    try testing.expect(manager.isEnabled(quirks.Quirk.NoUnicode));
    try testing.expect(!manager.isEnabled(quirks.Quirk.SlowScroll));
}

test "quirks.QuirkManager - invalid quirk string" {
    var manager = quirks.QuirkManager.init();
    
    try testing.expectError(error.InvalidQuirk, manager.setFromString("invalid_quirk"));
}

test "quirks.QuirkManager - get active quirks list" {
    var manager = quirks.QuirkManager.init();
    
    manager.enable(quirks.Quirk.BrokenColors);
    manager.enable(quirks.Quirk.NoUnicode);
    
    const active = manager.getActiveQuirks();
    try testing.expect(active.len == 2);
    try testing.expect(std.mem.indexOf(u8, active, "broken_colors") != null);
    try testing.expect(std.mem.indexOf(u8, active, "no_unicode") != null);
}

// Tests for lib_vt.zig
test "lib_vt.parseSequence - cursor movement" {
    const seq = "\x1B[10;20H";
    const result = try lib_vt.parseSequence(seq);
    
    try testing.expectEqual(lib_vt.SequenceType.CursorPosition, result.type);
    try testing.expectEqual(@as(u32, 10), result.params.row);
    try testing.expectEqual(@as(u32, 20), result.params.col);
}

test "lib_vt.parseSequence - color change" {
    const seq = "\x1B[38;2;255;0;128m";
    const result = try lib_vt.parseSequence(seq);
    
    try testing.expectEqual(lib_vt.SequenceType.SetColor, result.type);
    try testing.expectEqual(@as(u32, 38), result.params.color_type);
    try testing.expectEqual(@as(u32, 255), result.params.r);
    try testing.expectEqual(@as(u32, 0), result.params.g);
    try testing.expectEqual(@as(u32, 128), result.params.b);
}

test "lib_vt.parseSequence - invalid sequence" {
    const seq = "\x1B[invalid";
    try testing.expectError(error.InvalidSequence, lib_vt.parseSequence(seq));
}

test "lib_vt.generateSequence - move cursor" {
    var buf: [32]u8 = undefined;
    const len = lib_vt.generateCursorPosition(&buf, 10, 20);
    
    try testing.expectEqualStrings("\x1B[10;20H", buf[0..len]);
}

test "lib_vt.generateSequence - set color RGB" {
    var buf: [32]u8 = undefined;
    const len = lib_vt.generateColorRGB(&buf, 255, 128, 0);
    
    try testing.expectEqualStrings("\x1B[38;2;255;128;0m", buf[0..len]);
}

test "lib_vt.stripSequences - remove VT codes" {
    const input = "Hello\x1B[31mWorld\x1B[0m!";
    const expected = "HelloWorld!";
    
    var buf: [128]u8 = undefined;
    const len = lib_vt.stripSequences(&buf, input);
    
    try testing.expectEqualStrings(expected, buf[0..len]);
}

test "lib_vt.hasSequences - detect VT codes" {
    try testing.expect(lib_vt.hasSequences("Hello\x1B[31mWorld"));
    try testing.expect(!lib_vt.hasSequences("Hello World"));
}

test "lib_vt.calculateVisibleLength - with VT codes" {
    const text = "A\x1B[31mB\x1B[0mC";
    const len = lib_vt.calculateVisibleLength(text);
    try testing.expectEqual(@as(usize, 3), len);
}

// Tests for helpgen.zig
test "helpgen.generateCommandHelp - basic command" {
    const cmd = helpgen.Command{
        .name = "test",
        .description = "Test command",
        .usage = "test [options]",
        .options = &[_]helpgen.Option{
            .{ .name = "verbose", .short = 'v', .description = "Verbose output" },
            .{ .name = "help", .short = 'h', .description = "Show help" },
        },
    };
    
    var buf: [512]u8 = undefined;
    const len = helpgen.generateCommandHelp(&buf, cmd);
    const output = buf[0..len];
    
    try testing.expect(std.mem.indexOf(u8, output, "test") != null);
    try testing.expect(std.mem.indexOf(u8, output, "Test command") != null);
    try testing.expect(std.mem.indexOf(u8, output, "-v, --verbose") != null);
    try testing.expect(std.mem.indexOf(u8, output, "Verbose output") != null);
}

test "helpgen.generateCommandHelp - command with no options" {
    const cmd = helpgen.Command{
        .name = "simple",
        .description = "Simple command",
        .usage = "simple",
        .options = &[_]helpgen.Option{},
    };
    
    var buf: [256]u8 = undefined;
    const len = helpgen.generateCommandHelp(&buf, cmd);
    const output = buf[0..len];
    
    try testing.expect(std.mem.indexOf(u8, output, "simple") != null);
    try testing.expect(std.mem.indexOf(u8, output, "Simple command") != null);
    try testing.expect(std.mem.indexOf(u8, output, "Options:") == null);
}

test "helpgen.formatOption - with short and long" {
    const opt = helpgen.Option{
        .name = "output",
        .short = 'o',
        .description = "Output file",
        .value = "FILE",
    };
    
    var buf: [128]u8 = undefined;
    const len = helpgen.formatOption(&buf, opt);
    const output = buf[0..len];
    
    try testing.expect(std.mem.indexOf(u8, output, "-o, --output") != null);
    try testing.expect(std.mem.indexOf(u8, output, "FILE") != null);
    try testing.expect(std.mem.indexOf(u8, output, "Output file") != null);
}

test "helpgen.formatOption - long only" {
    const opt = helpgen.Option{
        .name = "daemon",
        .description = "Run as daemon",
    };
    
    var buf: [128]u8 = undefined;
    const len = helpgen.formatOption(&buf, opt);
    const output = buf[0..len];
    
    try testing.expect(std.mem.indexOf(u8, output, "--daemon") != null);
    try testing.expect(std.mem.indexOf(u8, output, "Run as daemon") != null);
}

test "helpgen.wrapText - basic wrapping" {
    const text = "This is a long line that should be wrapped at a reasonable width.";
    var buf: [256]u8 = undefined;
    const len = helpgen.wrapText(&buf, text, 20);
    const output = buf[0..len];
    
    try testing.expect(std.mem.indexOf(u8, output, "\n") != null);
    try testing.expect(output.len < text.len + 10); // Should have newlines
}

// Tests for build_config.zig
test "build_config.parse - basic config" {
    const config_str =
        \\version = "1.0.0"
        \\debug = true
        \\optimize = "Debug"
    ;
    
    var config = try build_config.parse(config_str);
    defer config.deinit();
    
    try testing.expectEqualStrings("1.0.0", config.version);
    try testing.expect(config.debug);
    try testing.expectEqual(build_config.OptimizeMode.Debug, config.optimize);
}

test "build_config.parse - with features" {
    const config_str =
        \\version = "2.0.0"
        \\features = ["feature1", "feature2"]
        \\target = "x86_64-linux"
    ;
    
    var config = try build_config.parse(config_str);
    defer config.deinit();
    
    try testing.expectEqualStrings("2.0.0", config.version);
    try testing.expect(config.features.len == 2);
    try testing.expect(std.mem.indexOf(u8, config.features, "feature1") != null);
    try testing.expect(std.mem.indexOf(u8, config.features, "feature2") != null);
    try testing.expectEqualStrings("x86_64-linux", config.target);
}

test "build_config.parse - invalid syntax" {
    const config_str = "invalid = syntax here";
    try testing.expectError(error.ParseError, build_config.parse(config_str));
}

test "build_config.validate - valid config" {
    var config = build_config.Config.init();
    config.version = "1.0.0";
    config.optimize = build_config.OptimizeMode.ReleaseFast;
    
    try config.validate();
}

test "build_config.validate - missing version" {
    var config = build_config.Config.init();
    config.optimize = build_config.OptimizeMode.Debug;
    
    try testing.expectError(error.MissingVersion, config.validate());
}

test "build_config.validate - invalid version format" {
    var config = build_config.Config.init();
    config.version = "not.a.version";
    config.optimize = build_config.OptimizeMode.Debug;
    
    try testing.expectError(error.InvalidVersion, config.validate());
}

test "build_config.merge - override values" {
    const base_str =
        \\version = "1.0.0"
        \\debug = false
    ;
    const override_str =
        \\debug = true
        \\optimize = "ReleaseSafe"
    ;
    
    var base = try build_config.parse(base_str);
    defer base.deinit();
    var override = try build_config.parse(override_str);
    defer override.deinit();
    
    try build_config.merge(&base, override);
    
    try testing.expectEqualStrings("1.0.0", base.version);
    try testing.expect(base.debug);
    try testing.expectEqual(build_config.OptimizeMode.ReleaseSafe, base.optimize);
}

test "build_config.toString - serialization" {
    var config = build_config.Config.init();
    config.version = "1.2.3";
    config.debug = true;
    config.optimize = build_config.OptimizeMode.Debug;
    config.target = "aarch64-macos";
    
    var buf: [512]u8 = undefined;
    const len = config.toString(&buf);
    const output = buf[0..len];
    
    try testing.expect(std.mem.indexOf(u8, output, "version = \"1.2.3\"") != null);
    try testing.expect(std.mem.indexOf(u8, output, "debug = true") != null);
    try testing.expect(std.mem.indexOf(u8, output, "optimize = \"Debug\"") != null);
    try testing.expect(std.mem.indexOf(u8, output, "target = \"aarch64-macos\"") != null);
}

test "build_config.getFeature - check feature existence" {
    const config_str =
        \\features = ["gpu", "networking", "audio"]
    ;
    
    var config = try build_config.parse(config_str);
    defer config.deinit();
    
    try testing.expect(config.hasFeature("gpu"));
    try testing.expect(config.hasFeature("networking"));
    try testing.expect(config.hasFeature("audio"));
    try testing.expect(!config.hasFeature("video"));
}

test "build_config.addFeature - dynamic feature addition" {
    var config = build_config.Config.init();
    config.version = "1.0.0";
    
    try config.addFeature("new_feature");
    try testing.expect(config.hasFeature("new_feature"));
    
    try config.addFeature("another_feature");
    try testing.expect(config.features.len == 2);
}

test "build_config.removeFeature - dynamic feature removal" {
    const config_str =
        \\features = ["feature1", "feature2", "feature3"]
    ;
    
    var config = try build_config.parse(config_str);
    defer config.deinit();
    
    try config.removeFeature("feature2");
    try testing.expect(!config.hasFeature("feature2"));
    try testing.expect(config.hasFeature("feature1"));
    try testing.expect(config.hasFeature("feature3"));
    try testing.expect(config.features.len == 2);
}