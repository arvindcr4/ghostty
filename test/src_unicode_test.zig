const std = @import("std");
const testing = std.testing;
const unicode = @import("unicode");

const Grapheme = unicode.Grapheme;
const Props = unicode.Props;
const Lut = unicode.Lut;
const PropsTable = unicode.PropsTable;

test "unicode.main.init" {
    const unicode_system = try unicode.init(testing.allocator);
    defer unicode_system.deinit();
    try testing.expect(unicode_system != null);
}

test "unicode.main.version" {
    const version = unicode.version();
    try testing.expect(version.major > 0);
    try testing.expect(version.minor >= 0);
    try testing.expect(version.patch >= 0);
}

test "grapheme.basic_ascii" {
    const str = "hello";
    var iter = Grapheme.Iterator.init(str);
    
    var count: usize = 0;
    while (iter.next()) |_| {
        count += 1;
    }
    try testing.expect(count == 5);
}

test "grapheme.combining_characters" {
    const str = "e\u{0301}"; // e + combining acute accent
    var iter = Grapheme.Iterator.init(str);
    
    var count: usize = 0;
    while (iter.next()) |_| {
        count += 1;
    }
    try testing.expect(count == 1);
}

test "grapheme.emoji_sequence" {
    const str = "\u{1F469}\u{200D}\u{1F469}\u{200D}\u{1F467}\u{200D}\u{1F467}"; // family emoji
    var iter = Grapheme.Iterator.init(str);
    
    var count: usize = 0;
    while (iter.next()) |_| {
        count += 1;
    }
    try testing.expect(count == 1);
}

test "grapheme.hangul_syllable" {
    const str = "\u{AC00}"; // Hangul syllable GA
    var iter = Grapheme.Iterator.init(str);
    
    var count: usize = 0;
    while (iter.next()) |_| {
        count += 1;
    }
    try testing.expect(count == 1);
}

test "grapheme.crlf_sequence" {
    const str = "a\r\nb";
    var iter = Grapheme.Iterator.init(str);
    
    var graphemes = std.ArrayList([]const u8).init(testing.allocator);
    defer graphemes.deinit();
    
    while (iter.next()) |g| {
        try graphemes.append(g);
    }
    
    try testing.expect(graphemes.items.len == 3);
    try testing.expect(std.mem.eql(u8, graphemes.items[0], "a"));
    try testing.expect(std.mem.eql(u8, graphemes.items[1], "\r\n"));
    try testing.expect(std.mem.eql(u8, graphemes.items[2], "b"));
}

test "grapheme.regional_indicators" {
    const str = "\u{1F1FA}\u{1F1F8}"; // US flag
    var iter = Grapheme.Iterator.init(str);
    
    var count: usize = 0;
    while (iter.next()) |_| {
        count += 1;
    }
    try testing.expect(count == 1);
}

test "grapheme.zwj_sequence" {
    const str = "\u{1F468}\u{200D}\u{1F393}"; // man student
    var iter = Grapheme.Iterator.init(str);
    
    var count: usize = 0;
    while (iter.next()) |_| {
        count += 1;
    }
    try testing.expect(count == 1);
}

test "props.is_letter" {
    try testing.expect(Props.isLetter('A'));
    try testing.expect(Props.isLetter('z'));
    try testing.expect(Props.isLetter('\u{03B1}')); // Greek alpha
    try testing.expect(Props.isLetter('\u{4E00}')); // CJK ideograph
    try testing.expect(!Props.isLetter('1'));
    try testing.expect(!Props.isLetter('!'));
}

test "props.is_number" {
    try testing.expect(Props.isNumber('0'));
    try testing.expect(Props.isNumber('9'));
    try testing.expect(Props.isNumber('\u{0660}')); // Arabic-Indic digit zero
    try testing.expect(Props.isNumber('\u{2155}')); // fraction one fifth
    try testing.expect(!Props.isNumber('A'));
    try testing.expect(!Props.isNumber('!'));
}

test "props.is_punctuation" {
    try testing.expect(Props.isPunctuation('.'));
    try testing.expect(Props.isPunctuation(','));
    try testing.expect(Props.isPunctuation('\u{060C}')); // Arabic comma
    try testing.expect(Props.isPunctuation('\u{3002}')); // CJK full stop
    try testing.expect(!Props.isPunctuation('A'));
    try testing.expect(!Props.isPunctuation('1'));
}

test "props.is_symbol" {
    try testing.expect(Props.isSymbol('$'));
    try testing.expect(Props.isSymbol('@'));
    try testing.expect(Props.isSymbol('\u{263A}')); // Smiley face
    try testing.expect(Props.isSymbol('\u{1F600}')); // Grinning face emoji
    try testing.expect(!Props.isSymbol('A'));
    try testing.expect(!Props.isSymbol('1'));
}

test "props.is_whitespace" {
    try testing.expect(Props.isWhitespace(' '));
    try testing.expect(Props.isWhitespace('\t'));
    try testing.expect(Props.isWhitespace('\n'));
    try testing.expect(Props.isWhitespace('\r'));
    try testing.expect(Props.isWhitespace('\u{00A0}')); // Non-breaking space
    try testing.expect(!Props.isWhitespace('A'));
    try testing.expect(!Props.isWhitespace('1'));
}

test "props.is_control" {
    try testing.expect(Props.isControl('\x00'));
    try testing.expect(Props.isControl('\x1F'));
    try testing.expect(Props.isControl('\x7F'));
    try testing.expect(!Props.isControl('A'));
    try testing.expect(!Props.isControl(' '));
}

test "props.script_detection" {
    try testing.expect(Props.getScript('A') == .Latin);
    try testing.expect(Props.getScript('\u{03B1}') == .Greek);
    try testing.expect(Props.getScript('\u{0410}') == .Cyrillic);
    try testing.expect(Props.getScript('\u{4E00}') == .Han);
    try testing.expect(Props.getScript('\u{0905}') == .Devanagari);
    try testing.expect(Props.getScript('\u{05D0}') == .Hebrew);
    try testing.expect(Props.getScript('\u{0627}') == .Arabic);
}

test "props.general_category" {
    try testing.expect(Props.getGeneralCategory('A') == .UppercaseLetter);
    try testing.expect(Props.getGeneralCategory('a') == .LowercaseLetter);
    try testing.expect(Props.getGeneralCategory('0') == .DecimalNumber);
    try testing.expect(Props.getGeneralCategory(' ') == .SpaceSeparator);
    try testing.expect(Props.getGeneralCategory('\n') == .Control);
}

test "props.emoji_properties" {
    try testing.expect(Props.isEmoji('\u{1F600}')); // Grinning face
    try testing.expect(Props.isEmoji('\u{2764}')); // Heart
    try testing.expect(Props.isEmoji('\u{00A9}')); // Copyright
    try testing.expect(!Props.isEmoji('A'));
    try testing.expect(!Props.isEmoji('1'));
}

test "lut.basic_lookup" {
    const lut = try Lut.init(testing.allocator);
    defer lut.deinit();
    
    const value = lut.get('A');
    try testing.expect(value != null);
}

test "lut.range_lookup" {
    const lut = try Lut.init(testing.allocator);
    defer lut.deinit();
    
    // Test lookup in different ranges
    const latin = lut.get('A');
    const greek = lut.get('\u{03B1}');
    const cjk = lut.get('\u{4E00}');
    const emoji = lut.get('\u{1F600}');
    
    try testing.expect(latin != null);
    try testing.expect(greek != null);
    try testing.expect(cjk != null);
    try testing.expect(emoji != null);
}

test "lut.performance" {
    const lut = try Lut.init(testing.allocator);
    defer lut.deinit();
    
    const start_time = std.time.nanoTimestamp();
    
    var i: u32 = 0;
    while (i < 10000) : (i += 1) {
        _ = lut.get(@intCast(i % 0x110000));
    }
    
    const end_time = std.time.nanoTimestamp();
    const duration = end_time - start_time;
    
    // Should complete in reasonable time (adjust threshold as needed)
    try testing.expect(duration < 100000000); // 100ms
}

test "lut.binary_search" {
    const lut = try Lut.init(testing.allocator);
    defer lut.deinit();
    
    // Test binary search on sorted ranges
    const test_points = [_]u32{ 0x41, 0x03B1, 0x4E00, 0x1F600 };
    
    for (test_points) |cp| {
        const result = lut.binarySearch(cp);
        try testing.expect(result != null);
    }
}

test "props_table.lookup_ascii" {
    const table = try PropsTable.init(testing.allocator);
    defer table.deinit();
    
    const props = table.get('A');
    try testing.expect(props.category == .UppercaseLetter);
    try testing.expect(props.script == .Latin);
}

test "props_table.lookup_multilingual" {
    const table = try PropsTable.init(testing.allocator);
    defer table.deinit();
    
    const test_cases = [_]struct {
        cp: u32,
        expected_category: Props.GeneralCategory,
        expected_script: Props.Script,
    }{
        .{ .cp = 'A', .expected_category = .UppercaseLetter, .expected_script = .Latin },
        .{ .cp = '\u{03B1}', .expected_category = .LowercaseLetter, .expected_script = .Greek },
        .{ .cp = '\u{4E00}', .expected_category = .OtherLetter, .expected_script = .Han },
        .{ .cp = '\u{0905}', .expected_category = .OtherLetter, .expected_script = .Devanagari },
        .{ .cp = '\u{0627}', .expected_category = .OtherLetter, .expected_script = .Arabic },
    };
    
    for (test_cases) |tc| {
        const props = table.get(tc.cp);
        try testing.expect(props.category == tc.expected_category);
        try testing.expect(props.script == tc.expected_script);
    }
}

test "props_table.emoji_properties" {
    const table = try PropsTable.init(testing.allocator);
    defer table.deinit();
    
    const emoji_props = table.get('\u{1F600}');
    try testing.expect(emoji_props.is_emoji);
    try testing.expect(emoji_props.category == .OtherSymbol);
}

test "props_table.range_coverage" {
    const table = try PropsTable.init(testing.allocator);
    defer table.deinit();
    
    // Test coverage across Unicode planes
    const test_ranges = [_]struct { start: u32, end: u32 }{
        .{ .start = 0x0000, .end = 0x007F }, // Basic Latin
        .{ .start = 0x0080, .end = 0x00FF }, // Latin-1 Supplement
        .{ .start = 0x0370, .end = 0x03FF }, // Greek and Coptic
        .{ .start = 0x0400, .end = 0x04FF }, // Cyrillic
        .{ .start = 0x4E00, .end = 0x4FFF }, // CJK Unified Ideographs
        .{ .start = 0x1F600, .end = 0x1F64F }, // Emoticons
    };
    
    for (test_ranges) |range| {
        var cp = range.start;
        while (cp <= range.end) : (cp += 1) {
            const props = table.get(cp);
            _ = props; // Just ensure no crash
        }
    }
}

test "string.segmentation_grapheme" {
    const str = "Hello, \u{4E16}\u{754C}! \u{1F600}";
    var segments = std.ArrayList([]const u8).init(testing.allocator);
    defer segments.deinit();
    
    var iter = Grapheme.Iterator.init(str);
    while (iter.next()) |g| {
        try segments.append(g);
    }
    
    try testing.expect(segments.items.len == 10);
    try testing.expect(std.mem.eql(u8, segments.items[0], "H"));
    try testing.expect(std.mem.eql(u8, segments.items[1], "e"));
    try testing.expect(std.mem.eql(u8, segments.items[2], "l"));
    try testing.expect(std.mem.eql(u8, segments.items[3], "l"));
    try testing.expect(std.mem.eql(u8, segments.items[4], "o"));
    try testing.expect(std.mem.eql(u8, segments.items[5], ","));
    try testing.expect(std.mem.eql(u8, segments.items[6], " "));
    try testing.expect(std.mem.eql(u8, segments.items[7], "\u{4E16}"));
    try testing.expect(std.mem.eql(u8, segments.items[8], "\u{754C}"));
    try testing.expect(std.mem.eql(u8, segments.items[9], "! \u{1F600}"));
}

test "string.segmentation_words" {
    const str = "Hello world! \u{4F60}\u{597D}\u{4E16}\u{754C}";
    var words = std.ArrayList([]const u8).init(testing.allocator);
    defer words.deinit();
    
    var iter = unicode.WordIterator.init(str);
    while (iter.next()) |w| {
        try words.append(w);
    }
    
    try testing.expect(words.items.len == 3);
    try testing.expect(std.mem.eql(u8, words.items[0], "Hello"));
    try testing.expect(std.mem.eql(u8, words.items[1], "world"));
    try testing.expect(std.mem.eql(u8, words.items[2], "\u{4F60}\u{597D}\u{4E16}\u{754C}"));
}

test "string.segmentation_sentences" {
    const str = "Hello world. How are you? I'm fine!";
    var sentences = std.ArrayList([]const u8).init(testing.allocator);
    defer sentences.deinit();
    
    var iter = unicode.SentenceIterator.init(str);
    while (iter.next()) |s| {
        try sentences.append(s);
    }
    
    try testing.expect(sentences.items.len == 3);
    try testing.expect(std.mem.eql(u8, sentences.items[0], "Hello world. "));
    try testing.expect(std.mem.eql(u8, sentences.items[1], "How are you? "));
    try testing.expect(std.mem.eql(u8, sentences.items[2], "I'm fine!"));
}

test "string.grapheme_count" {
    const str = "cafe\u{0301}"; // cafe with combining acute
    const count = unicode.countGraphemes(str);
    try testing.expect(count == 4);
}

test "string.grapheme_slice" {
    const str = "Hello \u{4F60}\u{597D}";
    const slice = unicode.sliceGraphemes(str, 0, 3);
    try testing.expect(std.mem.eql(u8, slice, "Hel"));
    
    const slice2 = unicode.sliceGraphemes(str, 6, 8);
    try testing.expect(std.mem.eql(u8, slice2, "\u{4F60}\u{597D}"));
}

test "normalization.nfc" {
    const input = "e\u{0301}"; // e + combining acute
    const normalized = unicode.normalize(input, .NFC);
    try testing.expect(std.mem.eql(u8, normalized, "\u{00E9}")); // é
}

test "normalization.nfd" {
    const input = "\u{00E9}"; // é
    const normalized = unicode.normalize(input, .NFD);
    try testing.expect(std.mem.eql(u8, normalized, "e\u{0301}")); // e + combining acute
}

test "normalization.nfkc" {
    const input = "\u{FB01}"; // fi ligature
    const normalized = unicode.normalize(input, .NFKC);
    try testing.expect(std.mem.eql(u8, normalized, "fi"));
}

test "normalization.nfkd" {
    const input = "\u{00B2}"; // Superscript two
    const normalized = unicode.normalize(input, .NFKD);
    try testing.expect(std.mem.eql(u8, normalized, "2"));
}

test "script_detection.mixed" {
    const str = "A\u{03B1}\u{4E00}\u{0627}";
    const scripts = try unicode.detectScripts(testing.allocator, str);
    defer testing.allocator.free(scripts);
    
    try testing.expect(scripts.len == 4);
    try testing.expect(scripts[0] == .Latin);
    try testing.expect(scripts[1] == .Greek);
    try testing.expect(scripts[2] == .Han);
    try testing.expect(scripts[3] == .Arabic);
}

test "script_detection.common" {
    const str = "123!@#";
    const scripts = try unicode.detectScripts(testing.allocator, str);
    defer testing.allocator.free(scripts);
    
    try testing.expect(scripts.len == 3);
    for (scripts) |script| {
        try testing.expect(script == .Common);
    }
}

test "script_detection.inherited" {
    const str = "e\u{0301}\u{0327}"; // e + combining acute + combining cedilla
    const scripts = try unicode.detectScripts(testing.allocator, str);
    defer testing.allocator.free(scripts);
    
    try testing.expect(scripts.len == 3);
    try testing.expect(scripts[0] == .Latin);
    try testing.expect(scripts[1] == .Inherited);
    try testing.expect(scripts[2] == .Inherited);
}

test "edge_cases.surrogate_pairs" {
    const str = "\u{D83D}\u{DE00}"; // Smiley face as surrogate pair
    var iter = Grapheme.Iterator.init(str);
    
    var count: usize = 0;
    while (iter.next()) |_| {
        count += 1;
    }
    try testing.expect(count == 1);
}

test "edge_cases.invalid_utf8" {
    const str = "\xFF\xFE"; // Invalid UTF-8
    var iter = Grapheme.Iterator.init(str);
    
    // Should handle gracefully
    var count: usize = 0;
    while (iter.next()) |_| {
        count += 1;
    }
    try testing.expect(count == 2); // Each invalid byte becomes a grapheme
}

test "edge_cases.empty_string" {
    const str = "";
    var iter = Grapheme.Iterator.init(str);
    
    var count: usize = 0;
    while (iter.next()) |_| {
        count += 1;
    }
    try testing.expect(count == 0);
}

test "edge_cases.max_codepoint" {
    const cp = 0x10FFFF; // Maximum valid Unicode code point
    const props = Props.getGeneralCategory(cp);
    try testing.expect(props != .Unassigned);
}

test "performance.large_string" {
    const str = "Hello, world! \u{4F60}\u{597D}\u{4E16}\u{754C} \u{1F600}\u{1F603}\u{1F604}";
    const repeated = 1000;
    
    const large_str = try testing.allocator.alloc(u8, str.len * repeated);
    defer testing.allocator.free(large_str);
    
    var i: usize = 0;
    while (i < repeated) : (i += 1) {
        std.mem.copy(u8, large_str[i * str.len .. (i + 1) * str.len], str);
    }
    
    const start_time = std.time.nanoTimestamp();
    
    var iter = Grapheme.Iterator.init(large_str);
    var count: usize = 0;
    while (iter.next()) |_| {
        count += 1;
    }
    
    const end_time = std.time.nanoTimestamp();
    const duration = end_time - start_time;
    
    try testing.expect(count > 0);
    try testing.expect(duration < 50000000); // 50ms
}

test "integration.complex_text" {
    const str = "Na\u{0308}ve \u{4F60}\u{597D} caf\u{00E9} \u{1F469}\u{200D}\u{1F469}\u{200D}\u{1F467}\u{200D}\u{1F467}";
    
    // Test grapheme segmentation
    var iter = Grapheme.Iterator.init(str);
    var graphemes = std.ArrayList([]const u8).init(testing.allocator);
    defer graphemes.deinit();
    
    while (iter.next()) |g| {
        try graphemes.append(g);
    }
    
    try testing.expect(graphemes.items.len == 12);
    
    // Test script detection
    const scripts = try unicode.detectScripts(testing.allocator, str);
    defer testing.allocator.free(scripts);
    
    try testing.expect(scripts.len == 12);
    try testing.expect(scripts[0] == .Latin);
    try testing.expect(scripts[1] == .Inherited);
    try testing.expect(scripts[2] == .Latin);
    try testing.expect(scripts[3] == .Latin);
    try testing.expect(scripts[4] == .Han);
    try testing.expect(scripts[5] == .Han);
    try testing.expect(scripts[6] == .Latin);
    try testing.expect(scripts[7] == .Latin);
    try testing.expect(scripts[8] == .Latin);
    try testing.expect(scripts[9] == .Latin);
    try testing.expect(scripts[10] == .Common); // Emoji
    try testing.expect(scripts[11] == .Common); // Emoji
    
    // Test normalization
    const normalized = unicode.normalize(str, .NFC);
    try testing.expect(normalized.len > 0);
}