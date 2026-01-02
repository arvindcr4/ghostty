const std = @import("std");
const testing = std.testing;
const mem = std.mem;
const fmt = std.fmt;

// Mock parser structures and functions for Ghostty
const AnsiParser = struct {
    buffer: [4096]u8,
    pos: usize,
    
    pub fn init() AnsiParser {
        return AnsiParser{
            .buffer = std.mem.zeroes([4096]u8),
            .pos = 0,
        };
    }
    
    pub fn parse(self: *AnsiParser, data: []const u8) void {
        for (data) |byte| {
            if (self.pos < self.buffer.len) {
                self.buffer[self.pos] = byte;
                self.pos += 1;
            }
            
            // Simulate ANSI escape sequence detection
            if (byte == 0x1B) {
                _ = self.handleEscapeSequence();
            }
        }
    }
    
    fn handleEscapeSequence(self: *AnsiParser) usize {
        _ = self;
        return 0;
    }
};

const ConfigParser = struct {
    allocator: mem.Allocator,
    keys: std.StringHashMap([]const u8),
    
    pub fn init(allocator: mem.Allocator) ConfigParser {
        return ConfigParser{
            .allocator = allocator,
            .keys = std.StringHashMap([]const u8).init(allocator),
        };
    }
    
    pub fn deinit(self: *ConfigParser) void {
        var it = self.keys.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.*);
        }
        self.keys.deinit();
    }
    
    pub fn parse(self: *ConfigParser, data: []const u8) !void {
        var lines = mem.tokenizeScalar(u8, data, '\n');
        while (lines.next()) |line| {
            if (line.len == 0) continue;
            
            var parts = mem.tokenizeScalar(u8, line, '=');
            const key = parts.next() orelse continue;
            const value = parts.next() orelse "";
            
            const key_copy = try self.allocator.dupe(u8, mem.trim(u8, key, " \t"));
            const value_copy = try self.allocator.dupe(u8, mem.trim(u8, value, " \t"));
            
            try self.keys.put(key_copy, value_copy);
        }
    }
};

const OscParser = struct {
    buffer: [1024]u8,
    pos: usize,
    
    pub fn init() OscParser {
        return OscParser{
            .buffer = std.mem.zeroes([1024]u8),
            .pos = 0,
        };
    }
    
    pub fn parse(self: *OscParser, data: []const u8) void {
        for (data) |byte| {
            if (self.pos < self.buffer.len) {
                self.buffer[self.pos] = byte;
                self.pos += 1;
            }
            
            // Simulate OSC sequence detection (ESC ] ... BEL/ST)
            if (byte == 0x1B) {
                _ = self.handleOscSequence();
            }
        }
    }
    
    fn handleOscSequence(self: *OscParser) usize {
        _ = self;
        return 0;
    }
};

const CsiParser = struct {
    params: [16]u32,
    param_count: usize,
    
    pub fn init() CsiParser {
        return CsiParser{
            .params = std.mem.zeroes([16]u32),
            .param_count = 0,
        };
    }
    
    pub fn parse(self: *CsiParser, data: []const u8) void {
        var i: usize = 0;
        while (i < data.len) {
            if (data[i] == 0x1B and i + 1 < data.len and data[i + 1] == '[') {
                i += 2;
                var param: u32 = 0;
                var has_param = false;
                
                while (i < data.len) {
                    const byte = data[i];
                    i += 1;
                    
                    if (byte >= '0' and byte <= '9') {
                        param = param * 10 + (byte - '0');
                        has_param = true;
                    } else if (byte == ';') {
                        if (self.param_count < self.params.len) {
                            self.params[self.param_count] = if (has_param) param else 0;
                            self.param_count += 1;
                        }
                        param = 0;
                        has_param = false;
                    } else {
                        if (has_param and self.param_count < self.params.len) {
                            self.params[self.param_count] = param;
                            self.param_count += 1;
                        }
                        break;
                    }
                }
            } else {
                i += 1;
            }
        }
    }
};

const TerminalCommandParser = struct {
    buffer: [512]u8,
    pos: usize,
    
    pub fn init() TerminalCommandParser {
        return TerminalCommandParser{
            .buffer = std.mem.zeroes([512]u8),
            .pos = 0,
        };
    }
    
    pub fn parse(self: *TerminalCommandParser, data: []const u8) void {
        for (data) |byte| {
            if (self.pos < self.buffer.len) {
                self.buffer[self.pos] = byte;
                self.pos += 1;
            }
            
            // Simulate command processing
            if (byte == '\r' or byte == '\n') {
                _ = self.processCommand();
                self.pos = 0;
            }
        }
    }
    
    fn processCommand(self: *TerminalCommandParser) usize {
        _ = self;
        return 0;
    }
};

const KeyBindingParser = struct {
    allocator: mem.Allocator,
    bindings: std.StringHashMap([]const u8),
    
    pub fn init(allocator: mem.Allocator) KeyBindingParser {
        return KeyBindingParser{
            .allocator = allocator,
            .bindings = std.StringHashMap([]const u8).init(allocator),
        };
    }
    
    pub fn deinit(self: *KeyBindingParser) void {
        var it = self.bindings.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.*);
        }
        self.bindings.deinit();
    }
    
    pub fn parse(self: *KeyBindingParser, data: []const u8) !void {
        var lines = mem.tokenizeScalar(u8, data, '\n');
        while (lines.next()) |line| {
            if (line.len == 0) continue;
            
            var parts = mem.tokenizeScalar(u8, line, ' ');
            const key = parts.next() orelse continue;
            const action = parts.next() orelse "";
            
            const key_copy = try self.allocator.dupe(u8, key);
            const action_copy = try self.allocator.dupe(u8, action);
            
            try self.bindings.put(key_copy, action_copy);
        }
    }
};

const ThemeParser = struct {
    allocator: mem.Allocator,
    colors: std.StringHashMap([3]u8),
    
    pub fn init(allocator: mem.Allocator) ThemeParser {
        return ThemeParser{
            .allocator = allocator,
            .colors = std.StringHashMap([3]u8).init(allocator),
        };
    }
    
    pub fn deinit(self: *ThemeParser) void {
        var it = self.colors.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
        }
        self.colors.deinit();
    }
    
    pub fn parse(self: *ThemeParser, data: []const u8) !void {
        var lines = mem.tokenizeScalar(u8, data, '\n');
        while (lines.next()) |line| {
            if (line.len == 0) continue;
            
            var parts = mem.tokenizeScalar(u8, line, ':');
            const name = parts.next() orelse continue;
            const color_hex = parts.next() orelse continue;
            
            var color: [3]u8 = undefined;
            if (fmt.hexToBytes(color[0..], color_hex[0..6])) |_| {
                const name_copy = try self.allocator.dupe(u8, mem.trim(u8, name, " \t"));
                try self.colors.put(name_copy, color);
            } else |_| {
                // Invalid hex, skip
            }
        }
    }
};

const FontParser = struct {
    buffer: [2048]u8,
    pos: usize,
    
    pub fn init() FontParser {
        return FontParser{
            .buffer = std.mem.zeroes([2048]u8),
            .pos = 0,
        };
    }
    
    pub fn parse(self: *FontParser, data: []const u8) void {
        for (data) |byte| {
            if (self.pos < self.buffer.len) {
                self.buffer[self.pos] = byte;
                self.pos += 1;
            }
            
            // Simulate font data processing
            if (byte == 0x00) {
                _ = self.processFontChunk();
            }
        }
    }
    
    fn processFontChunk(self: *FontParser) usize {
        _ = self;
        return 0;
    }
};

const UnicodeProcessor = struct {
    buffer: [1024]u8,
    pos: usize,
    
    pub fn init() UnicodeProcessor {
        return UnicodeProcessor{
            .buffer = std.mem.zeroes([1024]u8),
            .pos = 0,
        };
    }
    
    pub fn process(self: *UnicodeProcessor, data: []const u8) void {
        var i: usize = 0;
        while (i < data.len) {
            const byte_len = self.getUtf8CharLength(data[i]);
            if (i + byte_len <= data.len) {
                if (self.pos + byte_len <= self.buffer.len) {
                    mem.copy(u8, self.buffer[self.pos..self.pos + byte_len], data[i..i + byte_len]);
                    self.pos += byte_len;
                }
                i += byte_len;
            } else {
                i += 1;
            }
        }
    }
    
    fn getUtf8CharLength(self: *UnicodeProcessor, first_byte: u8) usize {
        _ = self;
        if (first_byte < 0x80) return 1;
        if (first_byte < 0xE0) return 2;
        if (first_byte < 0xF0) return 3;
        return 4;
    }
};

const InputEventHandler = struct {
    events: [256]u8,
    count: usize,
    
    pub fn init() InputEventHandler {
        return InputEventHandler{
            .events = std.mem.zeroes([256]u8),
            .count = 0,
        };
    }
    
    pub fn handle(self: *InputEventHandler, data: []const u8) void {
        for (data) |byte| {
            if (self.count < self.events.len) {
                self.events[self.count] = byte;
                self.count += 1;
            }
            
            // Simulate input event processing
            _ = self.processEvent(byte);
        }
    }
    
    fn processEvent(self: *InputEventHandler, event: u8) usize {
        _ = self;
        _ = event;
        return 0;
    }
};

// Fuzz test functions
test "fuzz_ansi_escape_sequence_parsing" {
    const allocator = testing.allocator;
    var prng = std.rand.DefaultPrng.init(@intCast(std.time.timestamp()));
    const random = prng.random();
    
    for (0..1000) |_| {
        var parser = AnsiParser.init();
        const data_len = random.intRangeAtMost(usize, 0, 1024);
        const data = try allocator.alloc(u8, data_len);
        defer allocator.free(data);
        
        random.bytes(data);
        
        // Inject some escape sequences
        if (data_len > 0 and random.boolean()) {
            data[random.intRangeLessThan(usize, 0, data_len)] = 0x1B;
        }
        
        parser.parse(data);
        
        // Verify no buffer overflow
        try testing.expect(parser.pos <= parser.buffer.len);
    }
}

test "fuzz_configuration_file_parsing" {
    const allocator = testing.allocator;
    var prng = std.rand.DefaultPrng.init(@intCast(std.time.timestamp()));
    const random = prng.random();
    
    for (0..1000) |_| {
        var parser = ConfigParser.init(allocator);
        defer parser.deinit();
        
        const data_len = random.intRangeAtMost(usize, 0, 2048);
        const data = try allocator.alloc(u8, data_len);
        defer allocator.free(data);
        
        random.bytes(data);
        
        // Replace some bytes with config-like characters
        for (data) |*byte| {
            if (random.float(f32) < 0.1) {
                byte.* = random.intRangeAtMost(u8, '=', '\n');
            }
        }
        
        parser.parse(data) catch |err| {
            // Should not crash, only return parse errors
            try testing.expect(err == error.OutOfMemory);
        };
    }
}

test "fuzz_osc_sequence_parsing" {
    const allocator = testing.allocator;
    var prng = std.rand.DefaultPrng.init(@intCast(std.time.timestamp()));
    const random = prng.random();
    
    for (0..1000) |_| {
        var parser = OscParser.init();
        const data_len = random.intRangeAtMost(usize, 0, 1024);
        const data = try allocator.alloc(u8, data_len);
        defer allocator.free(data);
        
        random.bytes(data);
        
        // Inject OSC-like sequences
        if (data_len > 2) {
            const pos = random.intRangeLessThan(usize, 0, data_len - 2);
            data[pos] = 0x1B;
            data[pos + 1] = ']';
        }
        
        parser.parse(data);
        
        try testing.expect(parser.pos <= parser.buffer.len);
    }
}

test "fuzz_csi_sequence_parsing" {
    const allocator = testing.allocator;
    var prng = std.rand.DefaultPrng.init(@intCast(std.time.timestamp()));
    const random = prng.random();
    
    for (0..1000) |_| {
        var parser = CsiParser.init();
        const data_len = random.intRangeAtMost(usize, 0, 1024);
        const data = try allocator.alloc(u8, data_len);
        defer allocator.free(data);
        
        random.bytes(data);
        
        // Inject CSI-like sequences
        if (data_len > 2) {
            const pos = random.intRangeLessThan(usize, 0, data_len - 2);
            data[pos] = 0x1B;
            data[pos + 1] = '[';
        }
        
        parser.parse(data);
        
        try testing.expect(parser.param_count <= parser.params.len);
    }
}

test "fuzz_terminal_command_parsing" {
    const allocator = testing.allocator;
    var prng = std.rand.DefaultPrng.init(@intCast(std.time.timestamp()));
    const random = prng.random();
    
    for (0..1000) |_| {
        var parser = TerminalCommandParser.init();
        const data_len = random.intRangeAtMost(usize, 0, 512);
        const data = try allocator.alloc(u8, data_len);
        defer allocator.free(data);
        
        random.bytes(data);
        
        // Inject newlines
        for (data) |*byte| {
            if (random.float(f32) < 0.05) {
                byte.* = '\n';
            }
        }
        
        parser.parse(data);
        
        try testing.expect(parser.pos <= parser.buffer.len);
    }
}

test "fuzz_key_binding_parsing" {
    const allocator = testing.allocator;
    var prng = std.rand.DefaultPrng.init(@intCast(std.time.timestamp()));
    const random = prng.random();
    
    for (0..1000) |_| {
        var parser = KeyBindingParser.init(allocator);
        defer parser.deinit();
        
        const data_len = random.intRangeAtMost(usize, 0, 1024);
        const data = try allocator.alloc(u8, data_len);
        defer allocator.free(data);
        
        random.bytes(data);
        
        // Replace some bytes with printable characters
        for (data) |*byte| {
            if (random.float(f32) < 0.2) {
                byte.* = random.intRangeAtMost(u8, ' ', '~');
            }
        }
        
        parser.parse(data) catch |err| {
            try testing.expect(err == error.OutOfMemory);
        };
    }
}

test "fuzz_theme_file_parsing" {
    const allocator = testing.allocator;
    var prng = std.rand.DefaultPrng.init(@intCast(std.time.timestamp()));
    const random = prng.random();
    
    for (0..1000) |_| {
        var parser = ThemeParser.init(allocator);
        defer parser.deinit();
        
        const data_len = random.intRangeAtMost(usize, 0, 1024);
        const data = try allocator.alloc(u8, data_len);
        defer allocator.free(data);
        
        random.bytes(data);
        
        // Inject some hex-like patterns
        for (data) |*byte| {
            if (random.float(f32) < 0.1) {
                byte.* = random.intRangeAtMost(u8, '0', 'f');
            }
        }
        
        parser.parse(data) catch |err| {
            try testing.expect(err == error.OutOfMemory);
        };
    }
}

test "fuzz_font_file_parsing" {
    const allocator = testing.allocator;
    var prng = std.rand.DefaultPrng.init(@intCast(std.time.timestamp()));
    const random = prng.random();
    
    for (0..1000) |_| {
        var parser = FontParser.init();
        const data_len = random.intRangeAtMost(usize, 0, 2048);
        const data = try allocator.alloc(u8, data_len);
        defer allocator.free(data);
        
        random.bytes(data);
        
        // Inject null bytes to simulate font chunks
        for (data) |*byte| {
            if (random.float(f32) < 0.05) {
                byte.* = 0x00;
            }
        }
        
        parser.parse(data);
        
        try testing.expect(parser.pos <= parser.buffer.len);
    }
}

test "fuzz_unicode_string_processing" {
    const allocator = testing.allocator;
    var prng = std.rand.DefaultPrng.init(@intCast(std.time.timestamp()));
    const random = prng.random();
    
    for (0..1000) |_| {
        var processor = UnicodeProcessor.init();
        const data_len = random.intRangeAtMost(usize, 0, 1024);
        const data = try allocator.alloc(u8, data_len);
        defer allocator.free(data);
        
        random.bytes(data);
        
        // Inject some valid UTF-8 sequences
        if (data_len > 3) {
            const pos = random.intRangeLessThan(usize, 0, data_len - 3);
            data[pos] = 0xE2;
            data[pos + 1] = 0x98;
            data[pos + 2] = 0x83;
        }
        
        processor.process(data);
        
        try testing.expect(processor.pos <= processor.buffer.len);
    }
}

test "fuzz_input_event_handling" {
    const allocator = testing.allocator;
    var prng = std.rand.DefaultPrng.init(@intCast(std.time.timestamp()));
    const random = prng.random();
    
    for (0..1000) |_| {
        var handler = InputEventHandler.init();
        const data_len = random.intRangeAtMost(usize, 0, 512);
        const data = try allocator.alloc(u8, data_len);
        defer allocator.free(data);
        
        random.bytes(data);
        
        handler.handle(data);
        
        try testing.expect(handler.count <= handler.events.len);
    }
}

test "fuzz_edge_case_discovery" {
    const allocator = testing.allocator;
    var prng = std.rand.DefaultPrng.init(@intCast(std.time.timestamp()));
    const random = prng.random();
    
    // Test with various edge cases
    const edge_cases = [_][]const u8{
        "\x00",                    // Null byte
        "\x1B",                    // ESC
        "\x1B[",                   // Incomplete CSI
        "\x1B]",                   // Incomplete OSC
        "\x1B[999999999999999",    // Very large parameter
        "\xFF\xFF\xFF\xFF",        // Invalid UTF-8
        "\x1B[0;0;0;0;0;0;0;0;0",  // Many parameters
        "",                        // Empty string
        "================================================================", // Long line
        "\x1B[0m\x1B[1m\x1B[2m",   // Multiple sequences
    };
    
    for (edge_cases) |edge_case| {
        // Test ANSI parser
        var ansi_parser = AnsiParser.init();
        ansi_parser.parse(edge_case);
        try testing.expect(ansi_parser.pos <= ansi_parser.buffer.len);
        
        // Test OSC parser
        var osc_parser = OscParser.init();
        osc_parser.parse(edge_case);
        try testing.expect(osc_parser.pos <= osc_parser.buffer.len);
        
        // Test CSI parser
        var csi_parser = CsiParser.init();
        csi_parser.parse(edge_case);
        try testing.expect(csi_parser.param_count <= csi_parser.params.len);
        
        // Test Unicode processor
        var unicode_processor = UnicodeProcessor.init();
        unicode_processor.process(edge_case);
        try testing.expect(unicode_processor.pos <= unicode_processor.buffer.len);
        
        // Test input handler
        var input_handler = InputEventHandler.init();
        input_handler.handle(edge_case);
        try testing.expect(input_handler.count <= input_handler.events.len);
    }
    
    // Test with random large data
    for (0..100) |_| {
        const data_len = random.intRangeAtMost(usize, 4096, 16384);
        const data = try allocator.alloc(u8, data_len);
        defer allocator.free(data);
        
        random.bytes(data);
        
        // Test all parsers with large random data
        var ansi_parser = AnsiParser.init();
        ansi_parser.parse(data);
        try testing.expect(ansi_parser.pos <= ansi_parser.buffer.len);
        
        var osc_parser = OscParser.init();
        osc_parser.parse(data);
        try testing.expect(osc_parser.pos <= osc_parser.buffer.len);
        
        var csi_parser = CsiParser.init();
        csi_parser.parse(data);
        try testing.expect(csi_parser.param_count <= csi_parser.params.len);
        
        var unicode_processor = UnicodeProcessor.init();
        unicode_processor.process(data);
        try testing.expect(unicode_processor.pos <= unicode_processor.buffer.len);
        
        var input_handler = InputEventHandler.init();
        input_handler.handle(data);
        try testing.expect(input_handler.count <= input_handler.events.len);
    }
}