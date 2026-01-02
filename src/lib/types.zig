const std = @import("std");

pub const String = extern struct {
    ptr: [*]const u8,
    len: usize,

    pub fn init(zig: anytype) String {
        return switch (@TypeOf(zig)) {
            []u8, []const u8 => .{
                .ptr = zig.ptr,
                .len = zig.len,
            },
            else => @compileError("Unsupported type for String.init"),
        };
    }
};

const testing = std.testing;

test "String init from const byte slice" {
    const bytes: []const u8 = "hello";
    const str = String.init(bytes);
    
    try testing.expectEqual(@as(usize, 5), str.len);
    try testing.expectEqual(bytes.ptr, str.ptr);
}

test "String init from mutable byte slice" {
    var buffer = [_]u8{ 'h', 'e', 'l', 'l', 'o' };
    const bytes: []u8 = &buffer;
    const str = String.init(bytes);
    
    try testing.expectEqual(@as(usize, 5), str.len);
    try testing.expectEqual(bytes.ptr, str.ptr);
}

test "String init with empty slice" {
    const empty: []const u8 = "";
    const str = String.init(empty);
    
    try testing.expectEqual(@as(usize, 0), str.len);
}

test "String fields accessible" {
    const bytes: []const u8 = "test";
    const str = String.init(bytes);
    
    // Verify we can access ptr and len
    try testing.expectEqual(bytes.ptr, str.ptr);
    try testing.expectEqual(@as(usize, 4), str.len);
}

test "String with unicode content" {
    const bytes: []const u8 = "hello 世界";
    const str = String.init(bytes);
    
    try testing.expectEqual(@as(usize, 12), str.len); // UTF-8 encoded length
}

test "passing" {
    try testing.expect(true);
}
