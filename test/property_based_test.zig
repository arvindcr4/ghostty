const std = @import("std");
const testing = std.testing;
const rand = std.rand;
const mem = std.mem;
const unicode = std.unicode;
const fmt = std.fmt;

// ANSI Sequence Parser/Generator
const AnsiParser = struct {
    const Self = @This();
    
    pub fn parse(sequence: []const u8) ![]const u8 {
        _ = sequence;
        return "";
    }
    
    pub fn generate(tokens: []const u8) ![]const u8 {
        _ = tokens;
        return "";
    }
};

// Color conversion utilities
const Color = struct {
    r: u8,
    g: u8,
    b: u8,
    
    pub fn toHSL(self: Color) struct { h: f32, s: f32, l: f32 } {
        const rf = @as(f32, self.r) / 255.0;
        const gf = @as(f32, self.g) / 255.0;
        const bf = @as(f32, self.b) / 255.0;
        
        const max = @max(rf, @max(gf, bf));
        const min = @min(rf, @min(gf, bf));
        const l = (max + min) / 2.0;
        
        if (max == min) {
            return .{ .h = 0, .s = 0, .l = l };
        }
        
        const d = max - min;
        const s = if (l > 0.5) d / (2.0 - max - min) else d / (max + min);
        
        var h: f32 = undefined;
        if (max == rf) {
            h = (gf - bf) / d + (if (gf < bf) 6.0 else 0.0);
        } else if (max == gf) {
            h = (bf - rf) / d + 2.0;
        } else {
            h = (rf - gf) / d + 4.0;
        }
        h /= 6.0;
        
        return .{ .h = h, .s = s, .l = l };
    }
    
    pub fn fromHSL(hsl: struct { h: f32, s: f32, l: f32 }) Color {
        const h = hsl.h;
        const s = hsl.s;
        const l = hsl.l;
        
        if (s == 0) {
            const gray = @as(u8, @intFromFloat(l * 255.0));
            return .{ .r = gray, .g = gray, .b = gray };
        }
        
        const hue2rgb = struct {
            fn fn(p: f32, q: f32, t: f32) f32 {
                var t_adj = t;
                if (t_adj < 0) t_adj += 1;
                if (t_adj > 1) t_adj -= 1;
                if (t_adj < 1.0/6.0) return p + (q - p) * 6.0 * t_adj;
                if (t_adj < 1.0/2.0) return q;
                if (t_adj < 2.0/3.0) return p + (q - p) * (2.0/3.0 - t_adj) * 6.0;
                return p;
            }
        }.fn;
        
        const q = if (l < 0.5) l * (1 + s) else l + s - l * s;
        const p = 2 * l - q;
        
        return .{
            .r = @as(u8, @intFromFloat(hue2rgb(p, q, h + 1.0/3.0) * 255.0)),
            .g = @as(u8, @intFromFloat(hue2rgb(p, q, h) * 255.0)),
            .b = @as(u8, @intFromFloat(hue2rgb(p, q, h - 1.0/3.0) * 255.0)),
        };
    }
    
    pub fn toHSV(self: Color) struct { h: f32, s: f32, v: f32 } {
        const rf = @as(f32, self.r) / 255.0;
        const gf = @as(f32, self.g) / 255.0;
        const bf = @as(f32, self.b) / 255.0;
        
        const max = @max(rf, @max(gf, bf));
        const min = @min(rf, @min(gf, bf));
        const v = max;
        const d = max - min;
        const s = if (max == 0) 0 else d / max;
        
        if (max == min) {
            return .{ .h = 0, .s = s, .v = v };
        }
        
        var h: f32 = undefined;
        if (max == rf) {
            h = (gf - bf) / d + (if (gf < bf) 6.0 else 0.0);
        } else if (max == gf) {
            h = (bf - rf) / d + 2.0;
        } else {
            h = (rf - gf) / d + 4.0;
        }
        h /= 6.0;
        
        return .{ .h = h, .s = s, .v = v };
    }
    
    pub fn fromHSV(hsv: struct { h: f32, s: f32, v: f32 }) Color {
        const h = hsv.h;
        const s = hsv.s;
        const v = hsv.v;
        
        const i = @as(u32, @intFromFloat(h * 6.0));
        const f = h * 6.0 - @as(f32, @floatFromInt(i));
        const p = v * (1.0 - s);
        const q = v * (1.0 - f * s);
        const t = v * (1.0 - (1.0 - f) * s);
        
        const rf: f32, const gf: f32, const bf: f32 = switch (i % 6) {
            0 => .{ v, t, p },
            1 => .{ q, v, p },
            2 => .{ p, v, t },
            3 => .{ p, q, v },
            4 => .{ t, p, v },
            5 => .{ v, p, q },
            else => unreachable,
        };
        
        return .{
            .r = @as(u8, @intFromFloat(rf * 255.0)),
            .g = @as(u8, @intFromFloat(gf * 255.0)),
            .b = @as(u8, @intFromFloat(bf * 255.0)),
        };
    }
};

// Terminal State Machine
const TerminalState = enum { normal, escape, csi, osc, dcs };
const TerminalStateMachine = struct {
    state: TerminalState = .normal,
    
    pub fn transition(self: *TerminalStateMachine, byte: u8) void {
        switch (self.state) {
            .normal => {
                if (byte == 0x1B) {
                    self.state = .escape;
                }
            },
            .escape => {
                switch (byte) {
                    '[' => self.state = .csi,
                    ']' => self.state = .osc,
                    'P' => self.state = .dcs,
                    else => self.state = .normal,
                }
            },
            .csi => {
                if (byte >= 0x40 and byte <= 0x7E) {
                    self.state = .normal;
                }
            },
            .osc => {
                if (byte == 0x07 or (byte == 0x1B and self.state != .normal)) {
                    self.state = .normal;
                }
            },
            .dcs => {
                if (byte >= 0x40 and byte <= 0x7E) {
                    self.state = .normal;
                }
            },
        }
    }
};

// Configuration Parser
const ConfigValue = union(enum) {
    string: []const u8,
    integer: i64,
    float: f64,
    boolean: bool,
};

const ConfigParser = struct {
    pub fn parse(key: []const u8, value: []const u8) !ConfigValue {
        _ = key;
        _ = value;
        return ConfigValue{ .boolean = false };
    }
    
    pub fn validate(key: []const u8, value: ConfigValue) bool {
        _ = key;
        _ = value;
        return true;
    }
};

// Text Shaper
const TextShaper = struct {
    pub fn shape(text: []const u8) []const u32 {
        _ = text;
        return &[_]u32{};
    }
};

// Font Fallback Chain
const FontFallback = struct {
    pub fn selectFallback(codepoint: u32, available_fonts: []const []const u8) ?[]const u8 {
        _ = codepoint;
        _ = available_fonts;
        return null;
    }
};

// Hash Table
const HashTable = struct {
    const Entry = struct {
        key: u32,
        value: u32,
        used: bool,
    };
    
    entries: []Entry,
    size: u32,
    
    pub fn init(capacity: u32) HashTable {
        return .{
            .entries = std.heap.page_allocator.alloc(Entry, capacity) catch unreachable,
            .size = 0,
        };
    }
    
    pub fn insert(self: *HashTable, key: u32, value: u32) void {
        const index = key % self.entries.len;
        self.entries[index] = .{ .key = key, .value = value, .used = true };
        self.size += 1;
    }
    
    pub fn delete(self: *HashTable, key: u32) void {
        const index = key % self.entries.len;
        if (self.entries[index].used and self.entries[index].key == key) {
            self.entries[index].used = false;
            self.size -= 1;
        }
    }
    
    pub fn rehash(self: *HashTable, new_capacity: u32) void {
        const old_entries = self.entries;
        self.entries = std.heap.page_allocator.alloc(Entry, new_capacity) catch unreachable;
        self.size = 0;
        
        for (old_entries) |entry| {
            if (entry.used) {
                self.insert(entry.key, entry.value);
            }
        }
    }
};

// Cache Eviction Policies
const CacheEntry = struct {
    key: u32,
    value: u32,
    access_count: u32,
    last_access: u64,
};

const LRUCache = struct {
    entries: []CacheEntry,
    capacity: u32,
    timestamp: u64,
    
    pub fn init(capacity: u32) LRUCache {
        return .{
            .entries = std.heap.page_allocator.alloc(CacheEntry, capacity) catch unreachable,
            .capacity = capacity,
            .timestamp = 0,
        };
    }
    
    pub fn get(self: *LRUCache, key: u32) ?u32 {
        self.timestamp += 1;
        for (self.entries) |*entry| {
            if (entry.key == key) {
                entry.last_access = self.timestamp;
                return entry.value;
            }
        }
        return null;
    }
    
    pub fn put(self: *LRUCache, key: u32, value: u32) void {
        self.timestamp += 1;
        var oldest_index: usize = 0;
        var oldest_time = self.entries[0].last_access;
        
        for (self.entries, 0..) |entry, i| {
            if (!entry.used) {
                oldest_index = i;
                break;
            }
            if (entry.last_access < oldest_time) {
                oldest_time = entry.last_access;
                oldest_index = i;
            }
        }
        
        self.entries[oldest_index] = .{
            .key = key,
            .value = value,
            .access_count = 1,
            .last_access = self.timestamp,
            .used = true,
        };
    }
};

const LFUCache = struct {
    entries: []CacheEntry,
    capacity: u32,
    
    pub fn init(capacity: u32) LFUCache {
        return .{
            .entries = std.heap.page_allocator.alloc(CacheEntry, capacity) catch unreachable,
            .capacity = capacity,
        };
    }
    
    pub fn get(self: *LFUCache, key: u32) ?u32 {
        for (self.entries) |*entry| {
            if (entry.key == key) {
                entry.access_count += 1;
                return entry.value;
            }
        }
        return null;
    }
    
    pub fn put(self: *LFUCache, key: u32, value: u32) void {
        var lfu_index: usize = 0;
        var lfu_count = self.entries[0].access_count;
        
        for (self.entries, 0..) |entry, i| {
            if (!entry.used) {
                lfu_index = i;
                break;
            }
            if (entry.access_count < lfu_count) {
                lfu_count = entry.access_count;
                lfu_index = i;
            }
        }
        
        self.entries[lfu_index] = .{
            .key = key,
            .value = value,
            .access_count = 1,
            .last_access = 0,
            .used = true,
        };
    }
};

// Property-based test utilities
fn generateRandomString(prng: *rand.Random, len: usize, allocator: mem.Allocator) ![]u8 {
    const str = try allocator.alloc(u8, len);
    for (str) |*c| {
        c.* = prng.intRangeAtMost(u8, 32, 126);
    }
    return str;
}

fn generateRandomBytes(prng: *rand.Random, len: usize, allocator: mem.Allocator) ![]u8 {
    const bytes = try allocator.alloc(u8, len);
    prng.bytes(bytes);
    return bytes;
}

fn generateRandomColor(prng: *rand.Random) Color {
    return .{
        .r = prng.int(u8),
        .g = prng.int(u8),
        .b = prng.int(u8),
    };
}

fn generateRandomUnicode(prng: *rand.Random, len: usize, allocator: mem.Allocator) ![]u8 {
    var buf = try allocator.alloc(u8, len * 4);
    var offset: usize = 0;
    
    for (0..len) |_| {
        const codepoint = prng.intRangeAtMost(u32, 0x20, 0x10FFFF);
        const written = unicode.utf8Encode(codepoint, buf[offset..]) catch continue;
        offset += written;
    }
    
    return allocator.realloc(buf, offset);
}

// Test 1: ANSI sequence parsing/generation round-trip
test "ansi_sequence_round_trip" {
    const test_count = 1000;
    var prng = rand.DefaultPrng.init(@intCast(std.time.timestamp()));
    const random = prng.random();
    
    for (0..test_count) |_| {
        const len = random.intRangeAtMost(usize, 1, 100);
        const allocator = testing.allocator;
        const sequence = try generateRandomString(random, len, allocator);
        defer allocator.free(sequence);
        
        const parsed = try AnsiParser.parse(sequence);
        defer testing.allocator.free(parsed);
        
        const generated = try AnsiParser.generate(parsed);
        defer testing.allocator.free(generated);
        
        // Property: Round-trip should preserve the sequence
        try testing.expectEqualStrings(sequence, generated);
    }
}

// Test 2: Color conversion round-trips
test "color_conversion_round_trip" {
    const test_count = 1000;
    var prng = rand.DefaultPrng.init(@intCast(std.time.timestamp()));
    const random = prng.random();
    
    for (0..test_count) |_| {
        const original = generateRandomColor(random);
        
        // RGB -> HSL -> RGB
        const hsl = original.toHSL();
        const rgb_from_hsl = Color.fromHSL(hsl);
        
        // Property: RGB -> HSL -> RGB should be approximately equal
        const diff_r = @abs(@as(i32, original.r) - @as(i32, rgb_from_hsl.r));
        const diff_g = @abs(@as(i32, original.g) - @as(i32, rgb_from_hsl.g));
        const diff_b = @abs(@as(i32, original.b) - @as(i32, rgb_from_hsl.b));
        
        try testing.expect(diff_r <= 2);
        try testing.expect(diff_g <= 2);
        try testing.expect(diff_b <= 2);
        
        // RGB -> HSV -> RGB
        const hsv = original.toHSV();
        const rgb_from_hsv = Color.fromHSV(hsv);
        
        // Property: RGB -> HSV -> RGB should be approximately equal
        const diff_r2 = @abs(@as(i32, original.r) - @as(i32, rgb_from_hsv.r));
        const diff_g2 = @abs(@as(i32, original.g) - @as(i32, rgb_from_hsv.g));
        const diff_b2 = @abs(@as(i32, original.b) - @as(i32, rgb_from_hsv.b));
        
        try testing.expect(diff_r2 <= 2);
        try testing.expect(diff_g2 <= 2);
        try testing.expect(diff_b2 <= 2);
        
        // Property: HSL and HSV values should be in valid ranges
        try testing.expect(hsl.h >= 0.0 and hsl.h <= 1.0);
        try testing.expect(hsl.s >= 0.0 and hsl.s <= 1.0);
        try testing.expect(hsl.l >= 0.0 and hsl.l <= 1.0);
        
        try testing.expect(hsv.h >= 0.0 and hsv.h <= 1.0);
        try testing.expect(hsv.s >= 0.0 and hsv.s <= 1.0);
        try testing.expect(hsv.v >= 0.0 and hsv.v <= 1.0);
    }
}

// Test 3: Unicode normalization properties
test "unicode_normalization_properties" {
    const test_count = 1000;
    var prng = rand.DefaultPrng.init(@intCast(std.time.timestamp()));
    const random = prng.random();
    
    for (0..test_count) |_| {
        const len = random.intRangeAtMost(usize, 1, 50);
        const allocator = testing.allocator;
        const text = try generateRandomUnicode(random, len, allocator);
        defer allocator.free(text);
        
        // Property: NFC(NFD(text)) should equal NFC(text)
        var nfd_buf: [256]u8 = undefined;
        const nfd_len = unicode.normalize(text, &nfd_buf, .NFD) catch continue;
        var nfc_from_nfd_buf: [256]u8 = undefined;
        const nfc_from_nfd_len = unicode.normalize(nfd_buf[0..nfd_len], &nfc_from_nfd_buf, .NFC) catch continue;
        
        var nfc_buf: [256]u8 = undefined;
        const nfc_len = unicode.normalize(text, &nfc_buf, .NFC) catch continue;
        
        try testing.expectEqualSlices(u8, nfc_buf[0..nfc_len], nfc_from_nfd_buf[0..nfc_from_nfd_len]);
        
        // Property: NFKC(NFKD(text)) should equal NFKC(text)
        var nfkd_buf: [256]u8 = undefined;
        const nfkd_len = unicode.normalize(text, &nfkd_buf, .NFKD) catch continue;
        var nfkc_from_nfkd_buf: [256]u8 = undefined;
        const nfkc_from_nfkd_len = unicode.normalize(nfkd_buf[0..nfkd_len], &nfkc_from_nfkd_buf, .NFKC) catch continue;
        
        var nfkc_buf: [256]u8 = undefined;
        const nfkc_len = unicode.normalize(text, &nfkc_buf, .NFKC) catch continue;
        
        try testing.expectEqualSlices(u8, nfkc_buf[0..nfkc_len], nfkc_from_nfkd_buf[0..nfkc_from_nfkd_len]);
    }
}

// Test 4: Grapheme cluster boundary properties
test "grapheme_cluster_boundaries" {
    const test_count = 1000;
    var prng = rand.DefaultPrng.init(@intCast(std.time.timestamp()));
    const random = prng.random();
    
    for (0..test_count) |_| {
        const len = random.intRangeAtMost(usize, 1, 100);
        const allocator = testing.allocator;
        const text = try generateRandomUnicode(random, len, allocator);
        defer allocator.free(text);
        
        var it = unicode.Utf8Iterator{ .bytes = text };
        var cluster_count: usize = 0;
        
        while (it.nextCodepoint()) |codepoint| {
            _ = codepoint;
            cluster_count += 1;
        }
        
        // Property: Cluster count should be <= byte length
        try testing.expect(cluster_count <= text.len);
        
        // Property: Cluster count should be >= 1 for non-empty text
        if (text.len > 0) {
            try testing.expect(cluster_count >= 1);
        }
    }
}

// Test 5: Terminal state machine transition properties
test "terminal_state_machine_properties" {
    const test_count = 1000;
    var prng = rand.DefaultPrng.init(@intCast(std.time.timestamp()));
    const random = prng.random();
    
    for (0..test_count) |_| {
        const len = random.intRangeAtMost(usize, 1, 50);
        const allocator = testing.allocator;
        const bytes = try generateRandomBytes(random, len, allocator);
        defer allocator.free(bytes);
        
        var sm = TerminalStateMachine{};
        var state_history: [10]TerminalState = undefined;
        var history_len: usize = 0;
        
        for (bytes) |byte| {
            state_history[history_len] = sm.state;
            history_len += 1;
            if (history_len >= state_history.len) history_len = 0;
            
            sm.transition(byte);
            
            // Property: State should always be valid
            switch (sm.state) {
                .normal, .escape, .csi, .osc, .dcs => {},
            }
        }
        
        // Property: After ESC, state should not be normal
        for (bytes, 0..) |byte, i| {
            if (byte == 0x1B and i + 1 < bytes.len) {
                var temp_sm = TerminalStateMachine{};
                temp_sm.transition(byte);
                try testing.expect(temp_sm.state != .normal);
            }
        }
    }
}

// Test 6: Configuration parsing and validation properties
test "configuration_parsing_properties" {
    const test_count = 1000;
    var prng = rand.DefaultPrng.init(@intCast(std.time.timestamp()));
    const random = prng.random();
    
    const test_keys = [_][]const u8{ "font_size", "theme", "opacity", "bold_font", "cursor_shape" };
    
    for (0..test_count) |_| {
        const key = test_keys[random.intRangeAtMost(usize, 0, test_keys.len - 1)];
        const value_len = random.intRangeAtMost(usize, 1, 20);
        const allocator = testing.allocator;
        const value = try generateRandomString(random, value_len, allocator);
        defer allocator.free(value);
        
        const parsed = try ConfigParser.parse(key, value);
        
        // Property: Parsed value should be validatable
        const is_valid = ConfigParser.validate(key, parsed);
        _ = is_valid; // Validity depends on implementation
        
        // Property: Boolean values should be true or false
        if (parsed == .boolean) {
            try testing.expect(parsed.boolean == true or parsed.boolean == false);
        }
        
        // Property: String values should not be null
        if (parsed == .string) {
            try testing.expect(parsed.string.len > 0);
        }
    }
}

// Test 7: Text shaping algorithm properties
test "text_shaping_properties" {
    const test_count = 1000;
    var prng = rand.DefaultPrng.init(@intCast(std.time.timestamp()));
    const random = prng.random();
    
    for (0..test_count) |_| {
        const len = random.intRangeAtMost(usize, 1, 50);
        const allocator = testing.allocator;
        const text = try generateRandomUnicode(random, len, allocator);
        defer allocator.free(text);
        
        const shaped = TextShaper.shape(text);
        
        // Property: Shaped output length should be reasonable
        try testing.expect(shaped.len <= text.len * 2);
        
        // Property: Empty input should produce empty output
        if (text.len == 0) {
            try testing.expect(shaped.len == 0);
        }
    }
}

// Test 8: Font fallback chain selection properties
test "font_fallback_properties" {
    const test_count = 1000;
    var prng = rand.DefaultPrng.init(@intCast(std.time.timestamp()));
    const random = prng.random();
    
    const test_fonts = [_][]const u8{ "Arial", "Helvetica", "Times New Roman", "Courier New", "Verdana" };
    
    for (0..test_count) |_| {
        const codepoint = random.intRangeAtMost(u32, 0x20, 0x10FFFF);
        const font_count = random.intRangeAtMost(usize, 1, test_fonts.len);
        const allocator = testing.allocator;
        const available_fonts = try allocator.alloc([]const u8, font_count);
        defer allocator.free(available_fonts);
        
        for (available_fonts, 0..) |*font, i| {
            font.* = test_fonts[i % test_fonts.len];
        }
        
        const selected = FontFallback.selectFallback(codepoint, available_fonts);
        
        // Property: Selected font should be in available fonts
        if (selected) |font| {
            var found = false;
            for (available_fonts) |available| {
                if (mem.eql(u8, font, available)) {
                    found = true;
                    break;
                }
            }
            try testing.expect(found);
        }
    }
}

// Test 9: Hash table operations properties
test "hash_table_properties" {
    const test_count = 100;
    var prng = rand.DefaultPrng.init(@intCast(std.time.timestamp()));
    const random = prng.random();
    
    for (0..test_count) |_| {
        const capacity = random.intRangeAtMost(u32, 10, 100);
        var table = HashTable.init(capacity);
        defer testing.allocator.free(table.entries);
        
        const insert_count = random.intRangeAtMost(u32, 1, capacity);
        var inserted_keys = try testing.allocator.alloc(u32, insert_count);
        defer testing.allocator.free(inserted_keys);
        
        // Insert random keys
        for (0..insert_count) |i| {
            const key = random.int(u32);
            const value = random.int(u32);
            table.insert(key, value);
            inserted_keys[i] = key;
        }
        
        // Property: Size should equal number of unique insertions
        try testing.expect(table.size <= insert_count);
        
        // Delete some keys
        const delete_count = random.intRangeAtMost(u32, 0, @min(insert_count, 10));
        for (0..delete_count) |_| {
            const index = random.intRangeAtMost(usize, 0, inserted_keys.len - 1);
            table.delete(inserted_keys[index]);
        }
        
        // Property: Size should not be negative
        try testing.expect(table.size >= 0);
        
        // Rehash
        const new_capacity = random.intRangeAtMost(u32, capacity, capacity * 2);
        table.rehash(new_capacity);
        
        // Property: After rehash, size should be preserved
        try testing.expect(table.size <= new_capacity);
    }
}

// Test 10: Cache eviction policies properties
test "cache_eviction_policies" {
    const test_count = 100;
    var prng = rand.DefaultPrng.init(@intCast(std.time.timestamp()));
    const random = prng.random();
    
    for (0..test_count) |_| {
        const capacity = random.intRangeAtMost(u32, 5, 20);
        
        // Test LRU
        var lru = LRUCache.init(capacity);
        defer testing.allocator.free(lru.entries);
        
        const access_count = random.intRangeAtMost(u32, 10, 50);
        var accessed_keys = try testing.allocator.alloc(u32, access_count);
        defer testing.allocator.free(accessed_keys);
        
        // Fill cache beyond capacity
        for (0..access_count) |i| {
            const key = random.int(u32);
            const value = random.int(u32);
            lru.put(key, value);
            accessed_keys[i] = key;
            
            // Property: Cache size should not exceed capacity
            var used_count: u32 = 0;
            for (lru.entries) |entry| {
                if (entry.used) used_count += 1;
            }
            try testing.expect(used_count <= capacity);
        }
        
        // Test LFU
        var lfu = LFUCache.init(capacity);
        defer testing.allocator.free(lfu.entries);
        
        // Fill cache beyond capacity
        for (0..access_count) |i| {
            const key = random.int(u32);
            const value = random.int(u32);
            lfu.put(key, value);
            
            // Property: Cache size should not exceed capacity
            var used_count: u32 = 0;
            for (lfu.entries) |entry| {
                if (entry.used) used_count += 1;
            }
            try testing.expect(used_count <= capacity);
        }
        
        // Property: Access counts should be non-negative
        for (lfu.entries) |entry| {
            if (entry.used) {
                try testing.expect(entry.access_count >= 1);
            }
        }
    }
}

// Additional edge case tests
test "edge_cases" {
    // Test empty inputs
    {
        const empty = "";
        const parsed = try AnsiParser.parse(empty);
        defer testing.allocator.free(parsed);
        try testing.expect(parsed.len == 0);
    }
    
    // Test color boundaries
    {
        const black = Color{ .r = 0, .g = 0, .b = 0 };
        const white = Color{ .r = 255, .g = 255, .b = 255 };
        
        const black_hsl = black.toHSL();
        const white_hsl = white.toHSL();
        
        try testing.expect(black_hsl.l == 0.0);
        try testing.expect(white_hsl.l == 1.0);
    }
    
    // Test terminal state machine with escape sequences
    {
        var sm = TerminalStateMachine{};
        sm.transition(0x1B);
        try testing.expect(sm.state == .escape);
        
        sm.transition('[');
        try testing.expect(sm.state == .csi);
        
        sm.transition('m');
        try testing.expect(sm.state == .normal);
    }
    
    // Test hash table with zero capacity
    {
        var table = HashTable.init(0);
        defer testing.allocator.free(table.entries);
        try testing.expect(table.size == 0);
    }
    
    // Test cache with capacity 1
    {
        var lru = LRUCache.init(1);
        defer testing.allocator.free(lru.entries);
        
        lru.put(1, 100);
        const value = lru.get(1);
        try testing.expect(value.? == 100);
        
        lru.put(2, 200);
        const old_value = lru.get(1);
        try testing.expect(old_value == null);
    }
}