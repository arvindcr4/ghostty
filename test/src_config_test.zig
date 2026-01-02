// src/config/ai_test.zig
const std = @import("std");
const testing = std.testing;
const ai = @import("ai.zig");

test "AIConfig.init with default values" {
    const config = ai.AIConfig.init();
    try testing.expectEqual(false, config.enabled);
    try testing.expectEqual(@as(u8, 0), config.model);
    try testing.expectEqual(@as(f32, 0.5), config.temperature);
    try testing.expectEqual(@as(usize, 100), config.max_tokens);
}

test "AIConfig.parse valid configuration" {
    const allocator = testing.allocator;
    const config_str = "enabled=true\nmodel=1\ntemperature=0.7\nmax_tokens=150";
    
    var config = try ai.AIConfig.parse(allocator, config_str);
    defer config.deinit(allocator);
    
    try testing.expectEqual(true, config.enabled);
    try testing.expectEqual(@as(u8, 1), config.model);
    try testing.expectEqual(@as(f32, 0.7), config.temperature);
    try testing.expectEqual(@as(usize, 150), config.max_tokens);
}

test "AIConfig.parse invalid temperature" {
    const allocator = testing.allocator;
    const config_str = "enabled=true\ntemperature=2.5";
    
    const config = ai.AIConfig.parse(allocator, config_str);
    try testing.expectError(error.InvalidTemperature, config);
}

test "AIConfig.parse invalid model" {
    const allocator = testing.allocator;
    const config_str = "enabled=true\nmodel=10";
    
    const config = ai.AIConfig.parse(allocator, config_str);
    try testing.expectError(error.InvalidModel, config);
}

test "AIConfig.parse empty configuration" {
    const allocator = testing.allocator;
    const config_str = "";
    
    var config = try ai.AIConfig.parse(allocator, config_str);
    defer config.deinit(allocator);
    
    try testing.expectEqual(false, config.enabled);
    try testing.expectEqual(@as(u8, 0), config.model);
}

test "AIConfig.validate with valid config" {
    var config = ai.AIConfig.init();
    config.enabled = true;
    config.model = 1;
    config.temperature = 0.8;
    config.max_tokens = 200;
    
    try config.validate();
}

test "AIConfig.validate with invalid temperature" {
    var config = ai.AIConfig.init();
    config.temperature = 2.0;
    
    try testing.expectError(error.InvalidTemperature, config.validate());
}

test "AIConfig.validate with invalid max_tokens" {
    var config = ai.AIConfig.init();
    config.max_tokens = 0;
    
    try testing.expectError(error.InvalidMaxTokens, config.validate());
}

test "AIConfig.toString formatting" {
    const allocator = testing.allocator;
    var config = ai.AIConfig.init();
    config.enabled = true;
    config.model = 2;
    config.temperature = 0.9;
    config.max_tokens = 300;
    
    const result = try config.toString(allocator);
    defer allocator.free(result);
    
    try testing.expectStringContains(result, "enabled=true");
    try testing.expectStringContains(result, "model=2");
    try testing.expectStringContains(result, "temperature=0.9");
    try testing.expectStringContains(result, "max_tokens=300");
}

test "AIConfig.merge configurations" {
    const allocator = testing.allocator;
    var base = ai.AIConfig.init();
    base.enabled = true;
    base.model = 1;
    
    var override = ai.AIConfig.init();
    override.model = 2;
    override.temperature = 0.8;
    
    const merged = try base.merge(allocator, override);
    defer merged.deinit(allocator);
    
    try testing.expectEqual(true, merged.enabled);
    try testing.expectEqual(@as(u8, 2), merged.model);
    try testing.expectEqual(@as(f32, 0.8), merged.temperature);
}

// src/config/string_test.zig
const std = @import("std");
const testing = std.testing;
const string = @import("string.zig");

test "StringUtil.trim whitespace" {
    try testing.expectEqualStrings("hello", string.trim("  hello  "));
    try testing.expectEqualStrings("world", string.trim("\tworld\n"));
    try testing.expectEqualStrings("test", string.trim("test"));
    try testing.expectEqualStrings("", string.trim("   "));
}

test "StringUtil.split on delimiter" {
    const allocator = testing.allocator;
    const parts = try string.split(allocator, "a,b,c", ',');
    defer allocator.free(parts);
    
    try testing.expectEqual(@as(usize, 3), parts.len);
    try testing.expectEqualStrings("a", parts[0]);
    try testing.expectEqualStrings("b", parts[1]);
    try testing.expectEqualStrings("c", parts[2]);
}

test "StringUtil.split with empty parts" {
    const allocator = testing.allocator;
    const parts = try string.split(allocator, "a,,c", ',');
    defer allocator.free(parts);
    
    try testing.expectEqual(@as(usize, 3), parts.len);
    try testing.expectEqualStrings("a", parts[0]);
    try testing.expectEqualStrings("", parts[1]);
    try testing.expectEqualStrings("c", parts[2]);
}

test "StringUtil.join with delimiter" {
    const allocator = testing.allocator;
    const parts = [_][]const u8{ "one", "two", "three" };
    
    const result = try string.join(allocator, &parts, '-');
    defer allocator.free(result);
    
    try testing.expectEqualStrings("one-two-three", result);
}

test "StringUtil.escape special characters" {
    const allocator = testing.allocator;
    const input = "hello\nworld\t\"test\"";
    
    const escaped = try string.escape(allocator, input);
    defer allocator.free(escaped);
    
    try testing.expectEqualStrings("hello\\nworld\\t\\\"test\\\"", escaped);
}

test "StringUtil.unescape special characters" {
    const allocator = testing.allocator;
    const input = "hello\\nworld\\t\\\"test\\\"";
    
    const unescaped = try string.unescape(allocator, input);
    defer allocator.free(unescaped);
    
    try testing.expectEqualStrings("hello\nworld\t\"test\"", unescaped);
}

test "StringUtil.isNumeric validation" {
    try testing.expect(true, string.isNumeric("123"));
    try testing.expect(true, string.isNumeric("0"));
    try testing.expect(false, string.isNumeric("12a"));
    try testing.expect(false, string.isNumeric(""));
    try testing.expect(false, string.isNumeric("-123"));
}

test "StringUtil.toInt conversion" {
    try testing.expectEqual(@as(i32, 42), try string.toInt("42"));
    try testing.expectEqual(@as(i32, 0), try string.toInt("0"));
    try testing.expectEqual(@as(i32, -100), try string.toInt("-100"));
    
    try testing.expectError(error.InvalidNumber, string.toInt("abc"));
    try testing.expectError(error.Overflow, string.toInt("999999999999999999"));
}

test "StringUtil.toFloat conversion" {
    try testing.expectEqual(@as(f64, 3.14), try string.toFloat("3.14"));
    try testing.expectEqual(@as(f64, 0.0), try string.toFloat("0.0"));
    try testing.expectEqual(@as(f64, -2.5), try string.toFloat("-2.5"));
    
    try testing.expectError(error.InvalidNumber, string.toFloat("abc"));
}

test "StringUtil.startsWith prefix check" {
    try testing.expect(true, string.startsWith("hello world", "hello"));
    try testing.expect(true, string.startsWith("test", ""));
    try testing.expect(false, string.startsWith("hello", "world"));
    try testing.expect(false, string.startsWith("", "test"));
}

test "StringUtil.endsWith suffix check" {
    try testing.expect(true, string.endsWith("hello world", "world"));
    try testing.expect(true, string.endsWith("test", ""));
    try testing.expect(false, string.endsWith("hello", "world"));
    try testing.expect(false, string.endsWith("", "test"));
}

test "StringUtil.contains substring check" {
    try testing.expect(true, string.contains("hello world", "lo wo"));
    try testing.expect(true, string.contains("test", ""));
    try testing.expect(false, string.contains("hello", "world"));
    try testing.expect(false, string.contains("", "test"));
}

test "StringUtil.replace all occurrences" {
    const allocator = testing.allocator;
    const input = "hello world hello";
    
    const result = try string.replace(allocator, input, "hello", "hi");
    defer allocator.free(result);
    
    try testing.expectEqualStrings("hi world hi", result);
}

test "StringUtil.toUpper conversion" {
    const allocator = testing.allocator;
    const input = "Hello World";
    
    const result = try string.toUpper(allocator, input);
    defer allocator.free(result);
    
    try testing.expectEqualStrings("HELLO WORLD", result);
}

test "StringUtil.toLower conversion" {
    const allocator = testing.allocator;
    const input = "Hello World";
    
    const result = try string.toLower(allocator, input);
    defer allocator.free(result);
    
    try testing.expectEqualStrings("hello world", result);
}

// src/config/key_test.zig
const std = @import("std");
const testing = std.testing;
const key = @import("key.zig");

test "Key.parse single key" {
    const parsed = try key.parse("a");
    try testing.expectEqual(key.KeyType{ .character = 'a' }, parsed);
}

test "Key.parse control key" {
    const parsed = try key.parse("Ctrl+a");
    try testing.expectEqual(key.KeyType{ .control = 'a' }, parsed);
}

test "Key.parse function key" {
    const parsed = try key.parse("F1");
    try testing.expectEqual(key.KeyType{ .function = 1 }, parsed);
}

test "Key.parse special key" {
    const parsed = try key.parse("Enter");
    try testing.expectEqual(key.KeyType.special.enter, parsed);
}

test "Key.parse modifier combination" {
    const parsed = try key.parse("Ctrl+Shift+Tab");
    try testing.expectEqual(key.KeyType{ 
        .modified = .{ 
            .key = .special.tab,
            .ctrl = true,
            .shift = true,
            .alt = false,
            .meta = false 
        } 
    }, parsed);
}

test "Key.parse invalid format" {
    try testing.expectError(error.InvalidKeyFormat, key.parse(""));
    try testing.expectError(error.InvalidKeyFormat, key.parse("Ctrl+"));
    try testing.expectError(error.UnknownKey, key.parse("InvalidKey"));
}

test "Key.toString formatting" {
    const allocator = testing.allocator;
    const k = key.KeyType{ .control = 'c' };
    
    const result = try k.toString(allocator);
    defer allocator.free(result);
    
    try testing.expectEqualStrings("Ctrl+c", result);
}

test "Key.equals comparison" {
    const k1 = key.KeyType{ .character = 'x' };
    const k2 = key.KeyType{ .character = 'x' };
    const k3 = key.KeyType{ .character = 'y' };
    
    try testing.expect(k1.equals(k2));
    try testing.expect(!k1.equals(k3));
}

test "KeySequence.parse multiple keys" {
    const allocator = testing.allocator;
    const sequence_str = "Ctrl+a,b,F3";
    
    var sequence = try key.KeySequence.parse(allocator, sequence_str);
    defer sequence.deinit(allocator);
    
    try testing.expectEqual(@as(usize, 3), sequence.keys.len);
    try testing.expectEqual(key.KeyType{ .control = 'a' }, sequence.keys[0]);
    try testing.expectEqual(key.KeyType{ .character = 'b' }, sequence.keys[1]);
    try testing.expectEqual(key.KeyType{ .function = 3 }, sequence.keys[2]);
}

test "KeySequence.toString formatting" {
    const allocator = testing.allocator;
    var sequence = key.KeySequence.init(allocator);
    defer sequence.deinit(allocator);
    
    try sequence.append(key.KeyType{ .control = 'c' });
    try sequence.append(key.KeyType{ .character = 'v' });
    
    const result = try sequence.toString();
    defer allocator.free(result);
    
    try testing.expectEqualStrings("Ctrl+c,v", result);
}

test "KeyBinding.create and validate" {
    const allocator = testing.allocator;
    const key_seq = "Ctrl+Shift+P";
    const command = "command_palette";
    
    var binding = try key.KeyBinding.create(allocator, key_seq, command);
    defer binding.deinit(allocator);
    
    try testing.expectEqualStrings(command, binding.command);
    try testing.expectEqual(@as(usize, 1), binding.sequence.keys.len);
}

test "KeyBindingMap.add and lookup" {
    const allocator = testing.allocator;
    var map = key.KeyBindingMap.init(allocator);
    defer map.deinit();
    
    try map.add("Ctrl+S", "save");
    try map.add("Ctrl+Shift+S", "save_as");
    
    const cmd1 = map.lookup(key.KeyType{ .control = 's' });
    try testing.expect(cmd1 != null);
    try testing.expectEqualStrings("save", cmd1.?);
    
    const cmd2 = map.lookup(key.KeyType{ 
        .modified = .{ 
            .key = .{ .character = 's' },
            .ctrl = true,
            .shift = true,
            .alt = false,
            .meta = false 
        } 
    });
    try testing.expect(cmd2 != null);
    try testing.expectEqualStrings("save_as", cmd2.?);
}

// src/config/theme_test.zig
const std = @import("std");
const testing = std.testing;
const theme = @import("theme.zig");

test "Color.parse hex color" {
    const color = try theme.Color.parse("#ff0000");
    try testing.expectEqual(theme.Color{ .rgb = .{ .r = 255, .g = 0, .b = 0 } }, color);
}

test "Color.parse short hex color" {
    const color = try theme.Color.parse("#f00");
    try testing.expectEqual(theme.Color{ .rgb = .{ .r = 255, .g = 0, .b = 0 } }, color);
}

test "Color.parse named color" {
    const color = try theme.Color.parse("red");
    try testing.expectEqual(theme.Color{ .rgb = .{ .r = 255, .g = 0, .b = 0 } }, color);
}

test "Color.parse rgb format" {
    const color = try theme.Color.parse("rgb(128, 64, 192)");
    try testing.expectEqual(theme.Color{ .rgb = .{ .r = 128, .g = 64, .b = 192 } }, color);
}

test "Color.parse invalid format" {
    try testing.expectError(error.InvalidColorFormat, theme.Color.parse("invalid"));
    try testing.expectError(error.InvalidColorFormat, theme.Color.parse("#gggggg"));
    try testing.expectError(error.InvalidColorFormat, theme.Color.parse("rgb(256, 0, 0)"));
}

test "Color.toString hex formatting" {
    const allocator = testing.allocator;
    const color = theme.Color{ .rgb = .{ .r = 255, .g = 128, .b = 64 } };
    
    const result = try color.toString(allocator);
    defer allocator.free(result);
    
    try testing.expectEqualStrings("#ff8040", result);
}

test "ColorPalette.init with defaults" {
    const palette = theme.ColorPalette.init();
    try testing.expectEqual(theme.Color{ .rgb = .{ .r = 0, .g = 0, .b = 0 } }, palette.background);
    try testing.expectEqual(theme.Color{ .rgb = .{ .r = 255, .g = 255, .b = 255 } }, palette.foreground);
}

test "ColorPalette.set and get colors" {
    var palette = theme.ColorPalette.init();
    const new_bg = theme.Color{ .rgb = .{ .r = 20, .g = 20, .b = 30 } };
    
    palette.setBackground(new_bg);
    try testing.expectEqual(new_bg, palette.getBackground());
    
    palette.setAnsiColor(1, theme.Color{ .rgb = .{ .r = 255, .g = 0, .b = 0 } });
    try testing.expectEqual(theme.Color{ .rgb = .{ .r = 255, .g = 0, .b = 0 } }, palette.getAnsiColor(1));
}

test "Theme.parse basic theme" {
    const allocator = testing.allocator;
    const theme_str = 
        \\name="Dark Theme"
        \\background=#000000
        \\foreground=#ffffff
        \\cursor=#00ff00
        \\ansi_0=#000000
        \\ansi_1=#ff0000
    ;
    
    var parsed_theme = try theme.Theme.parse(allocator, theme_str);
    defer parsed_theme.deinit(allocator);
    
    try testing.expectEqualStrings("Dark Theme", parsed_theme.name);
    try testing.expectEqual(theme.Color{ .rgb = .{ .r = 0, .g = 0, .b = 0 } }, parsed_theme.palette.background);
    try testing.expectEqual(theme.Color{ .rgb = .{ .r = 255, .g = 0, .b = 0 } }, parsed_theme.palette.getAnsiColor(1));
}

test "Theme.parse missing required fields" {
    const allocator = testing.allocator;
    const theme_str = "name=Incomplete";
    
    const parsed = theme.Theme.parse(allocator, theme_str);
    try testing.expectError(error.MissingRequiredField, parsed);
}

test "Theme.validate complete theme" {
    const allocator = testing.allocator;
    var t = theme.Theme.init(allocator);
    defer t.deinit(allocator);
    
    t.name = "Test";
    t.palette.background = theme.Color{ .rgb = .{ .r = 0, .g = 0, .b = 0 } };
    t.palette.foreground = theme.Color{ .rgb = .{ .r = 255, .g = 255, .b = 255 } };
    
    try t.validate();
}

test "Theme.validate incomplete theme" {
    const allocator = testing.allocator;
    var t = theme.Theme.init(allocator);
    defer t.deinit(allocator);
    
    try testing.expectError(error.MissingName, t.validate());
}

test "ThemeManager.load and retrieve themes" {
    const allocator = testing.allocator;
    var manager = theme.ThemeManager.init(allocator);
    defer manager.deinit();
    
    const theme_data = 
        \\name="Test Theme"
        \\background=#123456
        \\foreground=#abcdef
    ;
    
    try manager.loadFromString("test", theme_data);
    
    const loaded = manager.getTheme("test");
    try testing.expect(loaded != null);
    try testing.expectEqualStrings("Test Theme", loaded.?.name);
}

test "ThemeManager.listThemes" {
    const allocator = testing.allocator;
    var manager = theme.ThemeManager.init(allocator);
    defer manager.deinit();
    
    try manager.loadFromString("dark", "name=Dark\nbackground=#000000");
    try manager.loadFromString("light", "name=Light\nbackground=#ffffff");
    
    const list = try manager.listThemes();
    defer allocator.free(list);
    
    try testing.expectEqual(@as(usize, 2), list.len);
    try testing.expect(std.mem.eql(u8, list[0], "dark") or std.mem.eql(u8, list[0], "light"));
}

// src/config/url_test.zig
const std = @import("std");
const testing = std.testing;
const url = @import("url.zig");

test "URL.parse valid HTTP URL" {
    const parsed = try url.URL.parse("http://example.com");
    try testing.expectEqual(url.Scheme.http, parsed.scheme);
    try testing.expectEqualStrings("example.com", parsed.host);
    try testing.expectEqual(@as(u16, 80), parsed.port);
}

test "URL.parse HTTPS with port" {
    const parsed = try url.URL.parse("https://example.com:8443");
    try testing.expectEqual(url.Scheme.https, parsed.scheme);
    try testing.expectEqualStrings("example.com", parsed.host);
    try testing.expectEqual(@as(u16, 8443), parsed.port);
}

test "URL.parse with path and query" {
    const parsed = try url.URL.parse("https://example.com/path/to/file?param=value");
    try testing.expectEqualStrings("/path/to/file", parsed.path);
    try testing.expectEqualStrings("param=value", parsed.query);
}

test "URL.parse invalid scheme" {
    try testing.expectError(error.InvalidScheme, url.URL.parse("ftp://example.com"));
    try testing.expectError(error.InvalidScheme, url.URL.parse("not-a-url"));
}

test "URL.parse invalid host" {
    try testing.expectError(error.InvalidHost, url.URL.parse("https://"));
    try testing.expectError(error.InvalidHost, url.URL.parse("https://"));
}

test "URL.parse invalid port" {
    try testing.expectError(error.InvalidPort, url.URL.parse("https://example.com:99999"));
    try testing.expectError(error.InvalidPort, url.URL.parse("https://example.com:abc"));
}

test "URL.toString formatting" {
    const allocator = testing.allocator;
    var u = url.URL{
        .scheme = .https,
        .host = "example.com",
        .port = 443,
        .path = "/api",
        .query = "key=value",
    };
    
    const result = try u.toString(allocator);
    defer allocator.free(result);
    
    try testing.expectEqualStrings("https://example.com:443/api?key=value", result);
}

test "URLDetector.find URLs in text" {
    const allocator = testing.allocator;
    const text = "Visit https://example.com and http://test.org for more info";
    
    var detector = url.URLDetector.init(allocator);
    defer detector.deinit();
    
    const urls = try detector.find(text);
    defer allocator.free(urls);
    
    try testing.expectEqual(@as(usize, 2), urls.len);
    try testing.expectEqualStrings("https://example.com", urls[0]);
    try testing.expectEqualStrings("http://test.org", urls[1]);
}

test "URLDetector.find no URLs" {
    const allocator = testing.allocator;
    const text = "This text has no URLs";
    
    var detector = url.URLDetector.init(allocator);
    defer detector.deinit();
    
    const urls = try detector.find(text);
    defer allocator.free(urls);
    
    try testing.expectEqual(@as(usize, 0), urls.len);
}

test "URLDetector.find malformed URLs" {
    const allocator = testing.allocator;
    const text = "Check http:// and https://example.com:99999";
    
    var detector = url.URLDetector.init(allocator);
    defer detector.deinit();
    
    const urls = try detector.find(text);
    defer allocator.free(urls);
    
    try testing.expectEqual(@as(usize, 0), urls.len);
}

test "URLValidator.validate URL" {
    try testing.expect(url.URLValidator.isValid("https://example.com"));
    try testing.expect(url.URLValidator.isValid("http://localhost:8080"));
    try testing.expect(url.URLValidator.isValid("https://sub.domain.co.uk/path"));
    
    try testing.expect(!url.URLValidator.isValid("not-a-url"));
    try testing.expect(!url.URLValidator.isValid("ftp://example.com"));
    try testing.expect(!url.URLValidator.isValid("https://"));
}

test "URLHandler.launch browser" {
    const allocator = testing.allocator;
    var handler = url.URLHandler.init(allocator);
    defer handler.deinit();
    
    // Mock test - in real implementation would launch browser
    const test_url = "https://example.com";
    const result = try handler.open(test_url);
    try testing.expect(result.success);
}

test "URLHandler.handle invalid URL" {
    const allocator = testing.allocator;
    var handler = url.URLHandler.init(allocator);
    defer handler.deinit();
    
    const invalid_url = "not-a-url";
    const result = handler.open(invalid_url);
    try testing.expectError(error.InvalidURL, result);
}

// src/config/command_test.zig
const std = @import("std");
const testing = std.testing;
const command = @import("command.zig");

test "Command.parse simple command" {
    const parsed = try command.Command.parse("echo hello");
    try testing.expectEqualStrings("echo", parsed.name);
    try testing.expectEqual(@as(usize, 1), parsed.args.len);
    try testing.expectEqualStrings("hello", parsed.args[0]);
}

test "Command.parse command with multiple args" {
    const parsed = try command.Command.parse("git commit -m 'message here'");
    try testing.expectEqualStrings("git", parsed.name);
    try testing.expectEqual(@as(usize, 3), parsed.args.len);
    try testing.expectEqualStrings("commit", parsed.args[0]);
    try testing.expectEqualStrings("-m", parsed.args[1]);
    try testing.expectEqualStrings("message here", parsed.args[2]);
}

test "Command.parse quoted arguments" {
    const parsed = try command.Command.parse("ls -la \"My Documents\"");
    try testing.expectEqualStrings("ls", parsed.name);
    try testing.expectEqual(@as(usize, 2), parsed.args.len);
    try testing.expectEqualStrings("-la", parsed.args[0]);
    try testing.expectEqualStrings("My Documents", parsed.args[1]);
}

test "Command.parse escaped quotes" {
    const parsed = try command.Command.parse("echo \"He said \\\"Hello\\\"\"");
    try testing.expectEqual(@as(usize, 1), parsed.args.len);
    try testing.expectEqualStrings("He said \"Hello\"", parsed.args[0]);
}

test "Command.parse empty command" {
    try testing.expectError(error.EmptyCommand, command.Command.parse(""));
    try testing.expectError(error.EmptyCommand, command.Command.parse("   "));
}

test "Command.parse unclosed quote" {
    try testing.expectError(error.UnclosedQuote, command.Command.parse("echo \"hello"));
}

test "Command.toString formatting" {
    const allocator = testing.allocator;
    var cmd = command.Command{
        .name = "test",
        .args = try allocator.alloc([]const u8, 2),
    };
    cmd.args[0] = "arg1";
    cmd.args[1] = "arg with spaces";
    
    const result = try cmd.toString(allocator);
    defer allocator.free(result);
    
    try testing.expectEqualStrings("test arg1 \"arg with spaces\"", result);
}

test "Command.validate valid command" {
    const allocator = testing.allocator;
    var cmd = command.Command{
        .name = "ls",
        .args = try allocator.alloc([]const u8, 1),
    };
    cmd.args[0] = "-la";
    defer allocator.free(cmd.args);
    
    try cmd.validate();
}

test "Command.validate empty name" {
    const allocator = testing.allocator;
    var cmd = command.Command{
        .name = "",
        .args = try allocator.alloc([]const u8, 0),
    };
    defer allocator.free(cmd.args);
    
    try testing.expectError(error.EmptyCommandName, cmd.validate());
}

test "CommandRegistry.register and lookup" {
    const allocator = testing.allocator;
    var registry = command.CommandRegistry.init(allocator);
    defer registry.deinit();
    
    try registry.register("test_cmd", command.CommandHandler{
        .execute = struct {
            fn exec(args: [][]const u8) !void {
                _ = args;
            }
        }.exec,
    });
    
    const handler = registry.getHandler("test_cmd");
    try testing.expect(handler != null);
}

test "CommandRegistry.register duplicate" {
    const allocator = testing.allocator;
    var registry = command.CommandRegistry.init(allocator);
    defer registry.deinit();
    
    try registry.register("duplicate", command.CommandHandler{
        .execute = struct {
            fn exec(args: [][]const u8) !void {
                _ = args;
            }
        }.exec,
    });
    
    const result = registry.register("duplicate", command.CommandHandler{
        .execute = struct {
            fn exec(args: [][]const u8) !void {
                _ = args;
            }
        }.exec,
    });
    try testing.expectError(error.CommandAlreadyExists, result);
}

test "CommandExecutor.execute simple command" {
    const allocator = testing.allocator;
    var executor = command.CommandExecutor.init(allocator);
    defer executor.deinit();
    
    const result = try executor.execute("echo test");
    try testing.expectEqualStrings("test", result.stdout);
}

test "CommandExecutor.execute with error" {
    const allocator = testing.allocator;
    var executor = command.CommandExecutor.init(allocator);
    defer executor.deinit();
    
    const result = executor.execute("nonexistent_command_12345");
    try testing.expectError(error.CommandNotFound, result);
}

test "CommandParser.parse pipeline" {
    const allocator = testing.allocator;
    const pipeline_str = "cat file.txt | grep 'pattern' | wc -l";
    
    var pipeline = try command.CommandParser.parsePipeline(allocator, pipeline_str);
    defer pipeline.deinit(allocator);
    
    try testing.expectEqual(@as(usize, 3), pipeline.commands.len);
    try testing.expectEqualStrings("cat", pipeline.commands[0].name);
    try testing.expectEqualStrings("grep", pipeline.commands[1].name);
    try testing.expectEqualStrings("wc", pipeline.commands[2].name);
}

// src/config/conditional_test.zig
const std = @import("std");
const testing = std.testing;
const conditional = @import("conditional.zig");

test "Condition.parse simple condition" {
    const parsed = try conditional.Condition.parse("platform == linux");
    try testing.expectEqual(conditional.ConditionType.platform, parsed.type);
    try testing.expectEqual(conditional.Operator.equal, parsed.operator);
    try testing.expectEqualStrings("linux", parsed.value);
}

test "Condition.parse with not operator" {
    const parsed = try conditional.Condition.parse("not platform == windows");
    try testing.expectEqual(true, parsed.negated);
    try testing.expectEqual(conditional.ConditionType.platform, parsed.type);
}

test "Condition.parse complex condition" {
    const parsed = try conditional.Condition.parse("version >= 1.2.3");
    try testing.expectEqual(conditional.ConditionType.version, parsed.type);
    try testing.expectEqual(conditional.Operator.greater_equal, parsed.operator);
    try testing.expectEqualStrings("1.2.3", parsed.value);
}

test "Condition.parse invalid condition" {
    try testing.expectError(error.InvalidCondition, conditional.Condition.parse(""));
    try testing.expectError(error.InvalidCondition, conditional.Condition.parse("invalid"));
    try testing.expectError(error.UnknownConditionType, conditional.Condition.parse("unknown == value"));
}

test "Condition.evaluate platform condition" {
    const allocator = testing.allocator;
    var context = conditional.EvaluationContext.init(allocator);
    defer context.deinit();
    
    context.platform = "linux";
    
    const condition = try conditional.Condition.parse("platform == linux");
    const result = try condition.evaluate(&context);
    try testing.expectEqual(true, result);
    
    const condition2 = try conditional.Condition.parse("platform == windows");
    const result2 = try condition2.evaluate(&context);
    try testing.expectEqual(false, result2);
}

test "Condition.evaluate version condition" {
    const allocator = testing.allocator;
    var context = conditional.EvaluationContext.init(allocator);
    defer context.deinit();
    
    context.version = "1.2.3";
    
    const condition = try conditional.Condition.parse("version >= 1.2.0");
    const result = try condition.evaluate(&context);
    try testing.expectEqual(true, result);
    
    const condition2 = try conditional.Condition.parse("version > 2.0.0");
    const result2 = try condition2.evaluate(&context);
    try testing.expectEqual(false, result2);
}

test "Condition.evaluate negated condition" {
    const allocator = testing.allocator;
    var context = conditional.EvaluationContext.init(allocator);
    defer context.deinit();
    
    context.platform = "linux";
    
    const condition = try conditional.Condition.parse("not platform == windows");
    const result = try condition.evaluate(&context);
    try testing.expectEqual(true, result);
}

test "ConditionalConfig.parse with conditions" {
    const allocator = testing.allocator;
    const config_str = 
        \\if platform == linux {
        \\    font = "Ubuntu Mono"
        \\    font_size = 12
        \\}
        \\if platform == windows {
        \\    font = "Consolas"
        \\    font_size = 14
        \\}
    ;
    
    var config = try conditional.ConditionalConfig.parse(allocator, config_str);
    defer config.deinit(allocator);
    
    try testing.expectEqual(@as(usize, 2), config.blocks.len);
    try testing.expectEqual(conditional.ConditionType.platform, config.blocks[0].condition.type);
}

test "ConditionalConfig.parse nested conditions" {
    const allocator = testing.allocator;
    const config_str = 
        \\if platform == linux {
        \\    if version >= 1.0 {
        \\        theme = "dark"
        \\    }
        \\}
    ;
    
    var config = try conditional.ConditionalConfig.parse(allocator, config_str);
    defer config.deinit(allocator);
    
    try testing.expectEqual(@as(usize, 1), config.blocks.len);
    try testing.expectEqual(@as(usize, 1), config.blocks[0].nested_blocks.len);
}

test "ConditionalConfig.evaluate matching conditions" {
    const allocator = testing.allocator;
    var config = conditional.ConditionalConfig.init(allocator);
    defer config.deinit(allocator);
    
    var context = conditional.EvaluationContext.init(allocator);
    defer context.deinit();
    context.platform = "linux";
    
    const condition = try conditional.Condition.parse("platform == linux");
    var block = conditional.ConfigBlock{
        .condition = condition,
        .settings = std.StringHashMap([]const u8).init(allocator),
    };
    try block.settings.put("font", "Ubuntu Mono");
    
    try config.addBlock(block);
    
    const result = try config.evaluate(&context);
    try testing.expectEqual(@as(usize, 1), result.settings.count());
    const font = result.settings.get("font");
    try testing.expect(font != null);
    try testing.expectEqualStrings("Ubuntu Mono", font.?);
}

test "ConditionalConfig.evaluate no matching conditions" {
    const allocator = testing.allocator;
    var config = conditional.ConditionalConfig.init(allocator);
    defer config.deinit(allocator);
    
    var context = conditional.EvaluationContext.init(allocator);
    defer context.deinit();
    context.platform = "macos";
    
    const condition = try conditional.Condition.parse("platform == linux");
    var block = conditional.ConfigBlock{
        .condition = condition,
        .settings = std.StringHashMap([]const u8).init(allocator),
    };
    try block.settings.put("font", "Ubuntu Mono");
    
    try config.addBlock(block);
    
    const result = try config.evaluate(&context);
    try testing.expectEqual(@as(usize, 0), result.settings.count());
}

test "ConditionalConfig.parse invalid syntax" {
    const allocator = testing.allocator;
    const config_str = "if platform == linux { font = \"Ubuntu Mono\"";
    
    const result = conditional.ConditionalConfig.parse(allocator, config_str);
    try testing.expectError(error.UnclosedBlock, result);
}

test "VersionComparator.compare versions" {
    try testing.expectEqual(std.math.Order.eq, conditional.VersionComparator.compare("1.0.0", "1.0.0"));
    try testing.expectEqual(std.math.Order.gt, conditional.VersionComparator.compare("1.2.0", "1.1.9"));
    try testing.expectEqual(std.math.Order.lt, conditional.VersionComparator.compare("2.0.0", "2.1.0"));
    try testing.expectEqual(std.math.Order.gt, conditional.VersionComparator.compare("1.0.0", "1.0"));
    try testing.expectEqual(std.math.Order.eq, conditional.VersionComparator.compare("1.0", "1.0.0"));
}

test "VersionComparator.parse version" {
    const parsed = try conditional.VersionComparator.parse("1.2.3");
    try testing.expectEqual(@as(u32, 1), parsed.major);
    try testing.expectEqual(@as(u32, 2), parsed.minor);
    try testing.expectEqual(@as(u32, 3), parsed.patch);
}

test "VersionComparator.parse invalid version" {
    try testing.expectError(error.InvalidVersion, conditional.VersionComparator.parse("not.a.version"));
    try testing.expectError(error.InvalidVersion, conditional.VersionComparator.parse("1.2."));
    try testing.expectError(error.InvalidVersion, conditional.VersionComparator.parse(""));
}