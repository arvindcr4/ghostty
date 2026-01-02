test "src/terminal/ansi.zig" {
    const std = @import("std");
    const testing = std.testing;
    const ansi = @import("src/terminal/ansi.zig");

    // Test ANSI escape sequence parsing
    {
        const sequence = "\x1b[31mHello\x1b[0m";
        var parser = ansi.Parser.init();
        try parser.parse(sequence);
        try testing.expect(parser.hasColor());
        try testing.expectEqual(ansi.Color.red, parser.getColor());
    }

    // Test malformed sequences
    {
        const malformed = "\x1b[31";
        var parser = ansi.Parser.init();
        try testing.expectError(error.InvalidSequence, parser.parse(malformed));
    }

    // Test empty sequence
    {
        const empty = "";
        var parser = ansi.Parser.init();
        try parser.parse(empty);
        try testing.expect(!parser.hasColor());
    }

    // Test very long sequence
    {
        var long_seq: [1024]u8 = undefined;
        std.mem.set(u8, &long_seq, 'A');
        long_seq[0] = '\x1b';
        long_seq[1] = '[';
        long_seq[2] = '3';
        long_seq[3] = '1';
        long_seq[4] = 'm';
        
        var parser = ansi.Parser.init();
        try parser.parse(long_seq[0..5]);
        try testing.expect(parser.hasColor());
    }

    // Test multiple sequences
    {
        const multi = "\x1b[31m\x1b[1m\x1b[4mBold\x1b[24m\x1b[22m\x1b[39m";
        var parser = ansi.Parser.init();
        try parser.parse(multi);
        try testing.expect(parser.hasColor());
        try testing.expect(parser.hasAttribute(ansi.Attribute.bold));
        try testing.expect(parser.hasAttribute(ansi.Attribute.underline));
    }

    // Test sequence generation
    {
        var buf: [32]u8 = undefined;
        const seq = try ansi.generateColor(buf[0..], ansi.Color.green);
        try testing.expectEqualStrings("\x1b[32m", seq);
    }

    // Test reset sequence
    {
        var buf: [8]u8 = undefined;
        const seq = try ansi.generateReset(buf[0..]);
        try testing.expectEqualStrings("\x1b[0m", seq);
    }

    // Test attribute sequences
    {
        var buf: [16]u8 = undefined;
        const seq = try ansi.generateAttribute(buf[0..], ansi.Attribute.bold);
        try testing.expectEqualStrings("\x1b[1m", seq);
    }

    // Test combined sequences
    {
        var buf: [32]u8 = undefined;
        const seq = try ansi.generateCombined(buf[0..], .{ .color = ansi.Color.blue, .attr = ansi.Attribute.italic });
        try testing.expectEqualStrings("\x1b[34;3m", seq);
    }
}

test "src/terminal/color.zig" {
    const std = @import("std");
    const testing = std.testing;
    const color = @import("src/terminal/color.zig");

    // Test RGB color parsing
    {
        const rgb_str = "rgb:ff/00/ff";
        const parsed = try color.parseRgb(rgb_str);
        try testing.expectEqual(@as(u8, 255), parsed.r);
        try testing.expectEqual(@as(u8, 0), parsed.g);
        try testing.expectEqual(@as(u8, 255), parsed.b);
    }

    // Test hex color parsing
    {
        const hex_str = "#ff00ff";
        const parsed = try color.parseHex(hex_str);
        try testing.expectEqual(@as(u8, 255), parsed.r);
        try testing.expectEqual(@as(u8, 0), parsed.g);
        try testing.expectEqual(@as(u8, 255), parsed.b);
    }

    // Test 256-color index
    {
        const col = color.Color{ .index256 = 128 };
        try testing.expectEqual(@as(u8, 128), col.toIndex256());
    }

    // Test 16-color conversion
    {
        const col = color.Color{ .named = color.NamedColor.red };
        try testing.expectEqual(color.NamedColor.red, col.toNamed());
    }

    // Test RGB to 256 conversion
    {
        const rgb = color.Rgb{ .r = 255, .g = 0, .b = 0 };
        const index = color.rgbTo256(rgb);
        try testing.expect(index < 256);
    }

    // Test RGB to 16 conversion
    {
        const rgb = color.Rgb{ .r = 255, .g = 0, .b = 0 };
        const named = color.rgbToNamed(rgb);
        try testing.expectEqual(color.NamedColor.red, named);
    }

    // Test color formatting
    {
        var buf: [32]u8 = undefined;
        const col = color.Color{ .rgb = .{ .r = 128, .g = 64, .b = 192 } };
        const formatted = try col.format(buf[0..]);
        try testing.expect(formatted.len > 0);
    }

    // Test invalid color parsing
    {
        const invalid = "notacolor";
        try testing.expectError(error.InvalidColor, color.parseRgb(invalid));
    }

    // Test boundary values
    {
        const rgb_min = color.Rgb{ .r = 0, .g = 0, .b = 0 };
        const rgb_max = color.Rgb{ .r = 255, .g = 255, .b = 255 };
        
        try testing.expectEqual(@as(u8, 0), rgb_min.r);
        try testing.expectEqual(@as(u8, 255), rgb_max.r);
    }

    // Test color equality
    {
        const col1 = color.Color{ .rgb = .{ .r = 100, .g = 100, .b = 100 } };
        const col2 = color.Color{ .rgb = .{ .r = 100, .g = 100, .b = 100 } };
        const col3 = color.Color{ .rgb = .{ .r = 101, .g = 100, .b = 100 } };
        
        try testing.expect(col1.equal(col2));
        try testing.expect(!col1.equal(col3));
    }

    // Test color brightness
    {
        const dark = color.Rgb{ .r = 10, .g = 10, .b = 10 };
        const light = color.Rgb{ .r = 245, .g = 245, .b = 245 };
        
        try testing.expect(dark.brightness() < light.brightness());
    }
}

test "src/terminal/cursor.zig" {
    const std = @import("std");
    const testing = std.testing;
    const cursor = @import("src/terminal/cursor.zig");

    // Test cursor initialization
    {
        var cur = cursor.Cursor.init(80, 24);
        try testing.expectEqual(@as(u16, 0), cur.x);
        try testing.expectEqual(@as(u16, 0), cur.y);
        try testing.expectEqual(@as(u16, 80), cur.width);
        try testing.expectEqual(@as(u16, 24), cur.height);
    }

    // Test cursor movement
    {
        var cur = cursor.Cursor.init(80, 24);
        try cur.move(10, 5);
        try testing.expectEqual(@as(u16, 10), cur.x);
        try testing.expectEqual(@as(u16, 5), cur.y);
    }

    // Test cursor up
    {
        var cur = cursor.Cursor.init(80, 24);
        cur.x = 10;
        cur.y = 10;
        try cur.up(3);
        try testing.expectEqual(@as(u16, 10), cur.x);
        try testing.expectEqual(@as(u16, 7), cur.y);
    }

    // Test cursor down
    {
        var cur = cursor.Cursor.init(80, 24);
        cur.x = 10;
        cur.y = 5;
        try cur.down(3);
        try testing.expectEqual(@as(u16, 10), cur.x);
        try testing.expectEqual(@as(u16, 8), cur.y);
    }

    // Test cursor left
    {
        var cur = cursor.Cursor.init(80, 24);
        cur.x = 10;
        cur.y = 5;
        try cur.left(3);
        try testing.expectEqual(@as(u16, 7), cur.x);
        try testing.expectEqual(@as(u16, 5), cur.y);
    }

    // Test cursor right
    {
        var cur = cursor.Cursor.init(80, 24);
        cur.x = 5;
        cur.y = 5;
        try cur.right(3);
        try testing.expectEqual(@as(u16, 8), cur.x);
        try testing.expectEqual(@as(u16, 5), cur.y);
    }

    // Test boundary conditions
    {
        var cur = cursor.Cursor.init(80, 24);
        
        // Test left boundary
        cur.x = 0;
        try cur.left(1);
        try testing.expectEqual(@as(u16, 0), cur.x);
        
        // Test right boundary
        cur.x = 79;
        try cur.right(1);
        try testing.expectEqual(@as(u16, 79), cur.x);
        
        // Test top boundary
        cur.y = 0;
        try cur.up(1);
        try testing.expectEqual(@as(u16, 0), cur.y);
        
        // Test bottom boundary
        cur.y = 23;
        try cur.down(1);
        try testing.expectEqual(@as(u16, 23), cur.y);
    }

    // Test cursor save/restore
    {
        var cur = cursor.Cursor.init(80, 24);
        try cur.move(15, 10);
        cur.save();
        try cur.move(5, 5);
        cur.restore();
        try testing.expectEqual(@as(u16, 15), cur.x);
        try testing.expectEqual(@as(u16, 10), cur.y);
    }

    // Test cursor home
    {
        var cur = cursor.Cursor.init(80, 24);
        try cur.move(50, 15);
        cur.home();
        try testing.expectEqual(@as(u16, 0), cur.x);
        try testing.expectEqual(@as(u16, 0), cur.y);
    }

    // Test cursor position validation
    {
        var cur = cursor.Cursor.init(80, 24);
        try testing.expect(cur.isValidPosition(40, 12));
        try testing.expect(!cur.isValidPosition(80, 12));
        try testing.expect(!cur.isValidPosition(40, 24));
        try testing.expect(!cur.isValidPosition(100, 100));
    }

    // Test cursor sequence generation
    {
        var buf: [32]u8 = undefined;
        const seq = try cursor.generateMoveSequence(buf[0..], 10, 5);
        try testing.expectEqualStrings("\x1b[10;5H", seq);
    }

    // Test cursor visibility
    {
        var cur = cursor.Cursor.init(80, 24);
        try testing.expect(cur.isVisible());
        cur.hide();
        try testing.expect(!cur.isVisible());
        cur.show();
        try testing.expect(cur.isVisible());
    }
}

test "src/terminal/csi.zig" {
    const std = @import("std");
    const testing = std.testing;
    const csi = @import("src/terminal/csi.zig");

    // Test CSI sequence parsing
    {
        const sequence = "\x1b[31;44m";
        var parser = csi.Parser.init();
        const result = try parser.parse(sequence);
        try testing.expectEqual(csi.Command.SGR, result.command);
        try testing.expectEqual(@as(u32, 31), result.params[0]);
        try testing.expectEqual(@as(u32, 44), result.params[1]);
    }

    // Test CSI without parameters
    {
        const sequence = "\x1b[m";
        var parser = csi.Parser.init();
        const result = try parser.parse(sequence);
        try testing.expectEqual(csi.Command.SGR, result.command);
        try testing.expectEqual(@as(usize, 0), result.param_count);
    }

    // Test CSI with single parameter
    {
        const sequence = "\x1b[2J";
        var parser = csi.Parser.init();
        const result = try parser.parse(sequence);
        try testing.expectEqual(csi.Command.ED, result.command);
        try testing.expectEqual(@as(u32, 2), result.params[0]);
    }

    // Test cursor position CSI
    {
        const sequence = "\x1b[10;20H";
        var parser = csi.Parser.init();
        const result = try parser.parse(sequence);
        try testing.expectEqual(csi.Command.CUP, result.command);
        try testing.expectEqual(@as(u32, 10), result.params[0]);
        try testing.expectEqual(@as(u32, 20), result.params[1]);
    }

    // Test malformed CSI sequences
    {
        const malformed = "\x1b[31;44";
        var parser = csi.Parser.init();
        try testing.expectError(error.InvalidSequence, parser.parse(malformed));
    }

    // Test empty CSI
    {
        const empty = "\x1b[";
        var parser = csi.Parser.init();
        try testing.expectError(error.InvalidSequence, parser.parse(empty));
    }

    // Test very long CSI sequence
    {
        var long_seq: [256]u8 = undefined;
        long_seq[0] = '\x1b';
        long_seq[1] = '[';
        var i: usize = 2;
        while (i < 100) : (i += 1) {
            long_seq[i] = '1';
            long_seq[i + 1] = ';';
            i += 1;
        }
        long_seq[i] = 'm';
        
        var parser = csi.Parser.init();
        const result = try parser.parse(long_seq[0..i + 1]);
        try testing.expectEqual(csi.Command.SGR, result.command);
    }

    // Test private mode CSI
    {
        const sequence = "\x1b[?1049h";
        var parser = csi.Parser.init();
        const result = try parser.parse(sequence);
        try testing.expectEqual(csi.Command.DECSET, result.command);
        try testing.expectEqual(@as(u32, 1049), result.params[0]);
        try testing.expect(result.private);
    }

    // Test CSI command validation
    {
        try testing.expect(csi.isValidCommand('m'));
        try testing.expect(csi.isValidCommand('H'));
        try testing.expect(csi.isValidCommand('J'));
        try testing.expect(!csi.isValidCommand('z'));
    }

    // Test CSI sequence generation
    {
        var buf: [32]u8 = undefined;
        const seq = try csi.generateSequence(buf[0..], csi.Command.SGR, &[_]u32{ 31, 44 });
        try testing.expectEqualStrings("\x1b[31;44m", seq);
    }

    // Test parameter parsing edge cases
    {
        const sequence = "\x1b[;m";
        var parser = csi.Parser.init();
        const result = try parser.parse(sequence);
        try testing.expectEqual(csi.Command.SGR, result.command);
        try testing.expectEqual(@as(u32, 0), result.params[0]);
    }

    // Test multiple same parameters
    {
        const sequence = "\x1b[1;1;1m";
        var parser = csi.Parser.init();
        const result = try parser.parse(sequence);
        try testing.expectEqual(@as(usize, 3), result.param_count);
        try testing.expectEqual(@as(u32, 1), result.params[0]);
        try testing.expectEqual(@as(u32, 1), result.params[1]);
        try testing.expectEqual(@as(u32, 1), result.params[2]);
    }
}

test "src/terminal/charsets.zig" {
    const std = @import("std");
    const testing = std.testing;
    const charsets = @import("src/terminal/charsets.zig");

    // Test charset initialization
    {
        var cs = charsets.CharsetManager.init();
        try testing.expectEqual(charsets.Charset.ASCII, cs.getCurrent());
    }

    // Test charset switching
    {
        var cs = charsets.CharsetManager.init();
        try cs.setCharset(charsets.Charset.Latin1);
        try testing.expectEqual(charsets.Charset.Latin1, cs.getCurrent());
    }

    // Test G0/G1 charset selection
    {
        var cs = charsets.CharsetManager.init();
        try cs.setG0(charsets.Charset.Latin1);
        try cs.setG1(charsets.Charset.VT100);
        try cs.selectG0();
        try testing.expectEqual(charsets.Charset.Latin1, cs.getCurrent());
        try cs.selectG1();
        try testing.expectEqual(charsets.Charset.VT100, cs.getCurrent());
    }

    // Test character mapping
    {
        var cs = charsets.CharsetManager.init();
        try cs.setCharset(charsets.Charset.Latin1);
        const mapped = cs.mapChar(0xA0); // Non-breaking space in Latin1
        try testing.expect(mapped != 0);
    }

    // Test invalid charset
    {
        var cs = charsets.CharsetManager.init();
        try testing.expectError(error.InvalidCharset, cs.setCharset(@enumFromInt(255)));
    }

    // Test charset sequence parsing
    {
        const sequence = "\x1b(B"; // Select G0 - ASCII
        var parser = charsets.Parser.init();
        const result = try parser.parse(sequence);
        try testing.expectEqual(charsets.Charset.ASCII, result.charset);
        try testing.expectEqual(charsets.Designation.G0, result.designation);
    }

    // Test UTF-8 handling
    {
        var cs = charsets.CharsetManager.init();
        const utf8_str = "Hello 世界";
        var iter = std.unicode.Utf8Iterator.init(utf8_str);
        while (iter.nextCodepoint()) |cp| {
            const mapped = cs.mapChar(cp);
            _ = mapped; // Just ensure it doesn't crash
        } else |err| {
            try testing.expect(err == error.InvalidUtf8);
        }
    }

    // Test charset reset
    {
        var cs = charsets.CharsetManager.init();
        try cs.setCharset(charsets.Charset.Latin1);
        cs.reset();
        try testing.expectEqual(charsets.Charset.ASCII, cs.getCurrent());
    }

    // Test special characters
    {
        var cs = charsets.CharsetManager.init();
        try cs.setCharset(charsets.Charset.VT100);
        const box_chars = [_]u8{ 0x71, 0x6A, 0x6B, 0x6C }; // Box drawing characters
        for (box_chars) |c| {
            const mapped = cs.mapChar(c);
            try testing.expect(mapped != 0);
        }
    }

    // Test charset state saving
    {
        var cs = charsets.CharsetManager.init();
        try cs.setCharset(charsets.Charset.Latin1);
        cs.saveState();
        try cs.setCharset(charsets.Charset.VT100);
        cs.restoreState();
        try testing.expectEqual(charsets.Charset.Latin1, cs.getCurrent());
    }

    // Test malformed charset sequence
    {
        const malformed = "\x1b(Z";
        var parser = charsets.Parser.init();
        try testing.expectError(error.InvalidSequence, parser.parse(malformed));
    }

    // Test charset detection
    {
        const ascii = "Hello";
        const latin1 = "Café";
        const detected_ascii = charsets.detectCharset(ascii);
        const detected_latin1 = charsets.detectCharset(latin1);
        try testing.expectEqual(charsets.Charset.ASCII, detected_ascii);
        try testing.expect(detected_latin1 != charsets.Charset.ASCII);
    }
}

test "src/terminal/highlight.zig" {
    const std = @import("std");
    const testing = std.testing;
    const highlight = @import("src/terminal/highlight.zig");

    // Test highlight initialization
    {
        var hl = highlight.Highlighter.init();
        try testing.expectEqual(@as(usize, 0), hl.getHighlightCount());
    }

    // Test adding highlight
    {
        var hl = highlight.Highlighter.init();
        try hl.addHighlight(5, 10, highlight.Style{ .fg = .{ .named = .red } });
        try testing.expectEqual(@as(usize, 1), hl.getHighlightCount());
    }

    // Test removing highlight
    {
        var hl = highlight.Highlighter.init();
        const id = try hl.addHighlight(5, 10, highlight.Style{ .fg = .{ .named = .red } });
        try hl.removeHighlight(id);
        try testing.expectEqual(@as(usize, 0), hl.getHighlightCount());
    }

    // Test highlight overlap
    {
        var hl = highlight.Highlighter.init();
        _ = try hl.addHighlight(5, 10, highlight.Style{ .fg = .{ .named = .red } });
        _ = try hl.addHighlight(8, 15, highlight.Style{ .fg = .{ .named = .blue } });
        
        const highlights = hl.getHighlightsAt(9);
        try testing.expectEqual(@as(usize, 2), highlights.len);
    }

    // Test highlight style
    {
        var style = highlight.Style{ 
            .fg = .{ .named = .green },
            .bg = .{ .named = .black },
            .bold = true,
            .italic = true,
            .underline = true
        };
        
        try testing.expect(style.fg != null);
        try testing.expect(style.bg != null);
        try testing.expect(style.bold);
        try testing.expect(style.italic);
        try testing.expect(style.underline);
    }

    // Test highlight merging
    {
        var style1 = highlight.Style{ .fg = .{ .named = .red }, .bold = true };
        var style2 = highlight.Style{ .bg = .{ .named = .blue }, .italic = true };
        const merged = highlight.mergeStyles(style1, style2);
        
        try testing.expect(merged.fg != null);
        try testing.expect(merged.bg != null);
        try testing.expect(merged.bold);
        try testing.expect(merged.italic);
    }

    // Test highlight boundaries
    {
        var hl = highlight.Highlighter.init();
        try hl.addHighlight(0, 5, highlight.Style{ .fg = .{ .named = .red } });
        try hl.addHighlight(95, 100, highlight.Style{ .fg = .{ .named = .blue } });
        
        const highlights_start = hl.getHighlightsAt(2);
        const highlights_end = hl.getHighlightsAt(97);
        const highlights_middle = hl.getHighlightsAt(50);
        
        try testing.expectEqual(@as(usize, 1), highlights_start.len);
        try testing.expectEqual(@as(usize, 1), highlights_end.len);
        try testing.expectEqual(@as(usize, 0), highlights_middle.len);
    }

    // Test highlight clearing
    {
        var hl = highlight.Highlighter.init();
        _ = try hl.addHighlight(5, 10, highlight.Style{ .fg = .{ .named = .red } });
        _ = try hl.addHighlight(15, 20, highlight.Style{ .fg = .{ .named = .blue } });
        hl.clearAll();
        try testing.expectEqual(@as(usize, 0), hl.getHighlightCount());
    }

    // Test highlight persistence
    {
        var hl = highlight.Highlighter.init();
        const id = try hl.addHighlight(5, 10, highlight.Style{ .fg = .{ .named = .red } });
        const style = hl.getHighlightStyle(id);
        try testing.expect(style != null);
        try testing.expect(style.?.fg != null);
    }

    // Test invalid highlight range
    {
        var hl = highlight.Highlighter.init();
        try testing.expectError(error.InvalidRange, hl.addHighlight(10, 5, highlight.Style{}));
    }

    // Test highlight serialization
    {
        var hl = highlight.Highlighter.init();
        _ = try hl.addHighlight(5, 10, highlight.Style{ .fg = .{ .named = .red } });
        
        var buf: [256]u8 = undefined;
        const serialized = try hl.serialize(buf[0..]);
        try testing.expect(serialized.len > 0);
    }

    // Test highlight deserialization
    {
        var hl1 = highlight.Highlighter.init();
        _ = try hl1.addHighlight(5, 10, highlight.Style{ .fg = .{ .named = .red } });
        
        var buf: [256]u8 = undefined;
        const serialized = try hl1.serialize(buf[0..]);
        
        var hl2 = highlight.Highlighter.init();
        try hl2.deserialize(serialized);
        try testing.expectEqual(@as(usize, 1), hl2.getHighlightCount());
    }
}

test "src/terminal/hyperlink.zig" {
    const std = @import("std");
    const testing = std.testing;
    const hyperlink = @import("src/terminal/hyperlink.zig");

    // Test hyperlink initialization
    {
        var hl = hyperlink.HyperlinkManager.init();
        try testing.expectEqual(@as(usize, 0), hl.getHyperlinkCount());
    }

    // Test adding hyperlink
    {
        var hl = hyperlink.HyperlinkManager.init();
        const link = hyperlink.Hyperlink{
            .uri = "https://example.com",
            .params = "id=mylink",
        };
        const id = try hl.addHyperlink(link);
        try testing.expect(id != 0);
        try testing.expectEqual(@as(usize, 1), hl.getHyperlinkCount());
    }

    // Test hyperlink parsing
    {
        const sequence = "\x1b]8;;https://example.com\x1b\\Click me\x1b]8;;\x1b\\";
        var parser = hyperlink.Parser.init();
        const result = try parser.parse(sequence);
        try testing.expectEqualStrings("https://example.com", result.link.uri);
        try testing.expectEqualStrings("Click me", result.text);
    }

    // Test hyperlink with parameters
    {
        const sequence = "\x1b]8;id=mylink;https://example.com\x1b\\Link\x1b]8;;\x1b\\";
        var parser = hyperlink.Parser.init();
        const result = try parser.parse(sequence);
        try testing.expectEqualStrings("https://example.com", result.link.uri);
        try testing.expectEqualStrings("id=mylink", result.link.params);
    }

    // Test malformed hyperlink
    {
        const malformed = "\x1b]8;https://example.com\x1b\\";
        var parser = hyperlink.Parser.init();
        try testing.expectError(error.InvalidSequence, parser.parse(malformed));
    }

    // Test empty hyperlink URI
    {
        const sequence = "\x1b]8;;\x1b\\Text\x1b]8;;\x1b\\";
        var parser = hyperlink.Parser.init();
        const result = try parser.parse(sequence);
        try testing.expectEqual(@as(usize, 0), result.link.uri.len);
    }

    // Test very long hyperlink
    {
        var long_uri: [512]u8 = undefined;
        std.mem.set(u8, &long_uri, 'a');
        long_uri[0] = 'h';
        long_uri[1] = 't';
        long_uri[2] = 't';
        long_uri[3] = 'p';
        long_uri[4] = ':';
        long_uri[5] = '/';
        long_uri[6] = '/';
        
        var sequence: [600]u8 = undefined;
        var offset: usize = 0;
        std.mem.copy(u8, sequence[offset..], "\x1b]8;;");
        offset += 6;
        std.mem.copy(u8, sequence[offset..], &long_uri);
        offset += long_uri.len;
        std.mem.copy(u8, sequence[offset..], "\x1b\\Link\x1b]8;;\x1b\\");
        
        var parser = hyperlink.Parser.init();
        const result = try parser.parse(sequence[0..offset + 13]);
        try testing.expect(result.link.uri.len > 500);
    }

    // Test hyperlink generation
    {
        var buf: [256]u8 = undefined;
        const link = hyperlink.Hyperlink{
            .uri = "https://example.com",
            .params = "id=test",
        };
        const start_seq = try hyperlink.generateStart(buf[0..], link);
        try testing.expect(std.mem.startsWith(u8, start_seq, "\x1b]8;"));
        try testing.expect(std.mem.endsWith(u8, start_seq, "\x1b\\"));
        
        const end_seq = try hyperlink.generateEnd(buf[0..]);
        try testing.expectEqualStrings("\x1b]8;;\x1b\\", end_seq);
    }

    // Test hyperlink validation
    {
        const valid = hyperlink.Hyperlink{ .uri = "https://example.com" };
        const invalid = hyperlink.Hyperlink{ .uri = "not-a-url" };
        
        try testing.expect(hyperlink.isValid(valid));
        try testing.expect(!hyperlink.isValid(invalid));
    }

    // Test hyperlink lookup
    {
        var hl = hyperlink.HyperlinkManager.init();
        const link = hyperlink.Hyperlink{
            .uri = "https://example.com",
            .params = "id=test",
        };
        const id = try hl.addHyperlink(link);
        const found = hl.getHyperlink(id);
        try testing.expect(found != null);
        try testing.expectEqualStrings(link.uri, found.?.uri);
    }

    // Test hyperlink removal
    {
        var hl = hyperlink.HyperlinkManager.init();
        const link = hyperlink.Hyperlink{ .uri = "https://example.com" };
        const id = try hl.addHyperlink(link);
        try hl.removeHyperlink(id);
        const found = hl.getHyperlink(id);
        try testing.expect(found == null);
    }

    // Test special characters in URI
    {
        const sequence = "\x1b]8;;https://example.com/path?query=value&param=test\x1b\\Link\x1b]8;;\x1b\\";
        var parser = hyperlink.Parser.init();
        const result = try parser.parse(sequence);
        try testing.expect(std.mem.indexOf(u8, result.link.uri, "?query=value") != null);
    }
}

test "src/terminal/modes.zig" {
    const std = @import("std");
    const testing = std.testing;
    const modes = @import("src/terminal/modes.zig");

    // Test mode manager initialization
    {
        var mm = modes.ModeManager.init();
        try testing.expect(!mm.isSet(modes.Mode.ApplicationCursorKeys));
        try testing.expect(!mm.isSet(modes.Mode.BracketedPaste));
    }

    // Test setting modes
    {
        var mm = modes.ModeManager.init();
        try mm.set(modes.Mode.ApplicationCursorKeys);
        try testing.expect(mm.isSet(modes.Mode.ApplicationCursorKeys));
    }

    // Test clearing modes
    {
        var mm = modes.ModeManager.init();
        try mm.set(modes.Mode.ApplicationCursorKeys);
        try mm.clear(modes.Mode.ApplicationCursorKeys);
        try testing.expect(!mm.isSet(modes.Mode.ApplicationCursorKeys));
    }

    // Test toggling modes
    {
        var mm = modes.ModeManager.init();
        mm.toggle(modes.Mode.ApplicationCursorKeys);
        try testing.expect(mm.isSet(modes.Mode.ApplicationCursorKeys));
        mm.toggle(modes.Mode.ApplicationCursorKeys);
        try testing.expect(!mm.isSet(modes.Mode.ApplicationCursorKeys));
    }

    // Test multiple modes
    {
        var mm = modes.ModeManager.init();
        try mm.set(modes.Mode.ApplicationCursorKeys);
        try mm.set(modes.Mode.BracketedPaste);
        try mm.set(modes.Mode.MouseTracking);
        
        try testing.expect(mm.isSet(modes.Mode.ApplicationCursorKeys));
        try testing.expect(mm.isSet(modes.Mode.BracketedPaste));
        try testing.expect(mm.isSet(modes.Mode.MouseTracking));
    }

    // Test mode persistence
    {
        var mm = modes.ModeManager.init();
        try mm.set(modes.Mode.ApplicationCursorKeys);
        mm.saveState();
        try mm.clear(modes.Mode.ApplicationCursorKeys);
        try testing.expect(!mm.isSet(modes.Mode.ApplicationCursorKeys));
        mm.restoreState();
        try testing.expect(mm.isSet(modes.Mode.ApplicationCursorKeys));
    }

    // Test mode queries
    {
        var mm = modes.ModeManager.init();
        try mm.set(modes.Mode.ApplicationCursorKeys);
        
        var buf: [64]u8 = undefined;
        const response = try mm.queryMode(buf[0..], modes.Mode.ApplicationCursorKeys);
        try testing.expect(response.len > 0);
    }

    // Test private modes
    {
        var mm = modes.ModeManager.init();
        try mm.setPrivate(modes.PrivateMode.AlternateScreen);
        try testing.expect(mm.isPrivateSet(modes.PrivateMode.AlternateScreen));
    }

    // Test mode combinations
    {
        var mm = modes.ModeManager.init();
        const mode_list = [_]modes.Mode{ 
            modes.Mode.ApplicationCursorKeys,
            modes.Mode.BracketedPaste,
            modes.Mode.MouseTracking
        };
        try mm.setMultiple(&mode_list);
        
        for (mode_list) |mode| {
            try testing.expect(mm.isSet(mode));
        }
    }

    // Test invalid mode
    {
        var mm = modes.ModeManager.init();
        try testing.expectError(error.InvalidMode, mm.set(@enumFromInt(255)));
    }

    // Test mode reset
    {
        var mm = modes.ModeManager.init();
        try mm.set(modes.Mode.ApplicationCursorKeys);
        try mm.set(modes.Mode.BracketedPaste);
        mm.resetAll();
        try testing.expect(!mm.isSet(modes.Mode.ApplicationCursorKeys));
        try testing.expect(!mm.isSet(modes.Mode.BracketedPaste));
    }

    // Test mode serialization
    {
        var mm = modes.ModeManager.init();
        try mm.set(modes.Mode.ApplicationCursorKeys);
        try mm.set(modes.Mode.BracketedPaste);
        
        var buf: [32]u8 = undefined;
        const serialized = try mm.serialize(buf[0..]);
        try testing.expect(serialized.len > 0);
    }

    // Test mode deserialization
    {
        var mm1 = modes.ModeManager.init();
        try mm1.set(modes.Mode.ApplicationCursorKeys);
        
        var buf: [32]u8 = undefined;
        const serialized = try mm1.serialize(buf[0..]);
        
        var mm2 = modes.ModeManager.init();
        try mm2.deserialize(serialized);
        try testing.expect(mm2.isSet(modes.Mode.ApplicationCursorKeys));
    }

    // Test mode dependencies
    {
        var mm = modes.ModeManager.init();
        try mm.set(modes.Mode.MouseTracking);
        // Mouse tracking should automatically enable certain related modes
        try testing.expect(mm.isSet(modes.Mode.MouseTracking));
    }

    // Test mode conflicts
    {
        var mm = modes.ModeManager.init();
        try mm.set(modes.Mode.ApplicationCursorKeys);
        // Setting conflicting mode should clear the other
        try mm.set(modes.Mode.NormalCursorKeys);
        try testing.expect(mm.isSet(modes.Mode.NormalCursorKeys));
        try testing.expect(!mm.isSet(modes.Mode.ApplicationCursorKeys));
    }
}

test "src/terminal/osc.zig" {
    const std = @import("std");
    const testing = std.testing;
    const osc = @import("src/terminal/osc.zig");

    // Test OSC sequence parsing
    {
        const sequence = "\x1b]0;Terminal Title\x07";
        var parser = osc.Parser.init();
        const result = try parser.parse(sequence);
        try testing.expectEqual(osc.Command.SetWindowTitle, result.command);
        try testing.expectEqualStrings("Terminal Title", result.params);
    }

    // Test OSC with BEL terminator
    {
        const sequence = "\x1b]8;;https://example.com\x07";
        var parser = osc.Parser.init();
        const result = try parser.parse(sequence);
        try testing.expectEqual(osc.Command.SetHyperlink, result.command);
        try testing.expectEqualStrings("https://example.com", result.params);
    }

    // Test OSC with ST terminator
    {
        const sequence = "\x1b]0;Title\x1b\\";
        var parser = osc.Parser.init();
        const result = try parser.parse(sequence);
        try testing.expectEqual(osc.Command.SetWindowTitle, result.command);
        try testing.expectEqualStrings("Title", result.params);
    }

    // Test OSC with multiple parameters
    {
        const sequence = "\x1b]4;10;rgb:ff/00/00\x07";
        var parser = osc.Parser.init();
        const result = try parser.parse(sequence);
        try testing.expectEqual(osc.Command.SetColor, result.command);
        try testing.expect(std.mem.indexOf(u8, result.params, "10") != null);
        try testing.expect(std.mem.indexOf(u8, result.params, "rgb:ff/00/00") != null);
    }

    // Test malformed OSC sequence
    {
        const malformed = "\x1b]0;Title";
        var parser = osc.Parser.init();
        try testing.expectError(error.InvalidSequence, parser.parse(malformed));
    }

    // Test empty OSC parameters
    {
        const sequence = "\x1b]0;\x07";
        var parser = osc.Parser.init();
        const result = try parser.parse(sequence);
        try testing.expectEqual(osc.Command.SetWindowTitle, result.command);
        try testing.expectEqual(@as(usize, 0), result.params.len);
    }

    // Test very long OSC sequence
    {
        var long_title: [512]u8 = undefined;
        std.mem.set(u8, &long_title, 'A');
        
        var sequence: [520]u8 = undefined;
        std.mem.copy(u8, sequence[0..], "\x1b]0;");
        std.mem.copy(u8, sequence[4..], &long_title);
        sequence[4 + long_title.len] = '\x07';
        
        var parser = osc.Parser.init();
        const result = try parser.parse(sequence[0..5 + long_title.len]);
        try testing.expectEqual(osc.Command.SetWindowTitle, result.command);
        try testing.expect(result.params.len > 500);
    }

    // Test OSC command validation
    {
        try testing.expect(osc.isValidCommand(0));
        try testing.expect(osc.isValidCommand(8));
        try testing.expect(osc.isValidCommand(52));
        try testing.expect(!osc.isValidCommand(999));
    }

    // Test OSC sequence generation
    {
        var buf: [256]u8 = undefined;
        const seq = try osc.generateSequence(buf[0..], osc.Command.SetWindowTitle, "Test Title");
        try testing.expect(std.mem.startsWith(u8, seq, "\x1b]0;"));
        try testing.expect(std.mem.endsWith(u8, seq, "\x07"));
    }

    // Test color setting OSC
    {
        const sequence = "\x1b]4;10;#ff0000\x07";
        var parser = osc.Parser.init();
        const result = try parser.parse(sequence);
        try testing.expectEqual(osc.Command.SetColor, result.params.len > 0);
    }

    // Test clipboard OSC
    {
        const sequence = "\x1b]52;c;SGVsbG8gV29ybGQ=\x07";
        var parser = osc.Parser.init();
        const result = try parser.parse(sequence);
        try testing.expectEqual(osc.Command.SetClipboard, result.command);
        try testing.expect(result.params.len > 0);
    }

    // Test notification OSC
    {
        const sequence = "\x1b]777;notify;Title;Message\x07";
        var parser = osc.Parser.init();
        const result = try parser.parse(sequence);
        try testing.expectEqual(osc.Command.Notify, result.command);
        try testing.expect(std.mem.indexOf(u8, result.params, "Title") != null);
        try testing.expect(std.mem.indexOf(u8, result.params, "Message") != null);
    }

    // Test OSC with special characters
    {
        const sequence = "\x1b]0;Title with \x1b and \\ characters\x07";
        var parser = osc.Parser.init();
        const result = try parser.parse(sequence);
        try testing.expectEqual(osc.Command.SetWindowTitle, result.command);
        try testing.expect(result.params.len > 0);
    }

    // Test OSC parameter parsing
    {
        const sequence = "\x1b]8;id=test;https://example.com\x07";
        var parser = osc.Parser.init();
        const result = try parser.parse(sequence);
        var params = osc.parseParams(result.params);
        try testing.expect(params.len > 0);
        try testing.expect(std.mem.indexOf(u8, params[0], "id=test") != null);
    }

    // Test OSC terminator detection
    {
        try testing.expect(osc.isValidTerminator('\x07'));
        try testing.expect(osc.isValidTerminator('\x1b'));
        try testing.expect(!osc.isValidTerminator('A'));
    }

    // Test OSC command ranges
    {
        try testing.expect(osc.isWindowCommand(0));
        try testing.expect(osc.isColorCommand(4));
        try testing.expect(osc.isClipboardCommand(52));
        try testing.expect(!osc.isWindowCommand(999));
    }
}