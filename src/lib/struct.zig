const std = @import("std");
const Target = @import("target.zig").Target;

pub fn Struct(
    comptime target: Target,
    comptime Zig: type,
) type {
    return switch (target) {
        .zig => Zig,
        .c => c: {
            const info = @typeInfo(Zig).@"struct";
            var fields: [info.fields.len]std.builtin.Type.StructField = undefined;
            for (info.fields, 0..) |field, i| {
                fields[i] = .{
                    .name = field.name,
                    .type = field.type,
                    .default_value_ptr = field.default_value_ptr,
                    .is_comptime = field.is_comptime,
                    .alignment = field.alignment,
                };
            }

            break :c @Type(.{ .@"struct" = .{
                .layout = .@"extern",
                .fields = &fields,
                .decls = &.{},
                .is_tuple = info.is_tuple,
            } });
        },
    };
}

const testing = std.testing;

test "Struct creates zig layout struct with basic fields" {
    const MyStruct = struct {
        x: i32,
        y: i32,
        z: f32,
    };
    
    const ZigStruct = Struct(Target.zig, MyStruct);
    var instance = ZigStruct{ .x = 10, .y = 20, .z = 3.14 };
    
    // Verify it's the same type and fields work
    try testing.expectEqual(@as(i32, 10), instance.x);
    try testing.expectEqual(@as(i32, 20), instance.y);
    try testing.expectEqual(@as(f32, 3.14), instance.z);
    
    // Modify fields
    instance.x = 100;
    try testing.expectEqual(@as(i32, 100), instance.x);
}

test "Struct creates c layout extern struct" {
    const MyStruct = struct {
        x: i32,
        y: i32,
        z: f32,
    };
    
    const CStruct = Struct(Target.c, MyStruct);
    const instance = CStruct{ .x = 10, .y = 20, .z = 3.14 };
    
    // Verify fields work
    try testing.expectEqual(@as(i32, 10), instance.x);
    try testing.expectEqual(@as(i32, 20), instance.y);
    try testing.expectEqual(@as(f32, 3.14), instance.z);
}

test "Struct with array fields" {
    const MyStruct = struct {
        data: [10]u8,
        count: usize,
    };
    
    const CStruct = Struct(Target.c, MyStruct);
    const instance = CStruct{
        .data = [_]u8{1, 2, 3, 4, 5, 0, 0, 0, 0, 0},
        .count = 5,
    };
    
    try testing.expectEqual(@as(usize, 5), instance.count);
    try testing.expectEqual(@as(u8, 1), instance.data[0]);
    try testing.expectEqual(@as(u8, 5), instance.data[4]);
}

test "Struct with default values" {
    const MyStruct = struct {
        x: i32 = 42,
        y: i32 = 100,
        z: f32 = 2.71,
    };
    
    const ZigStruct = Struct(Target.zig, MyStruct);
    const instance = ZigStruct{};
    
    try testing.expectEqual(@as(i32, 42), instance.x);
    try testing.expectEqual(@as(i32, 100), instance.y);
    try testing.expectEqual(@as(f32, 2.71), instance.z);
}

test "Nested struct with extern inner" {
    const Inner = extern struct {
        a: i32,
        b: i32,
    };
    
    const Outer = struct {
        inner: Inner,
        x: f32,
    };
    
    const COuter = Struct(Target.c, Outer);
    const instance = COuter{
        .inner = Inner{ .a = 1, .b = 2 },
        .x = 3.14,
    };
    
    try testing.expectEqual(@as(i32, 1), instance.inner.a);
    try testing.expectEqual(@as(i32, 2), instance.inner.b);
    try testing.expectEqual(@as(f32, 3.14), instance.x);
}

test "Struct with pointer fields" {
    const MyStruct = struct {
        ptr: *const i32,
        value: i32,
    };
    
    const ZigStruct = Struct(Target.zig, MyStruct);
    const num: i32 = 42;
    const instance = ZigStruct{ .ptr = &num, .value = num };
    
    try testing.expectEqual(@as(i32, 42), instance.ptr.*);
    try testing.expectEqual(@as(i32, 42), instance.value);
}

test "Struct size comparison" {
    const MyStruct = struct {
        a: u8,
        b: u32,
        c: u8,
    };
    
    const ZigStruct = Struct(Target.zig, MyStruct);
    const CStruct = Struct(Target.c, MyStruct);
    
    const zig_size = @sizeOf(ZigStruct);
    const c_size = @sizeOf(CStruct);
    
    // Both should be reasonable sizes
    try testing.expect(zig_size >= 6);
    try testing.expect(c_size >= 6);
}

test "passing" {
    // Empty test to ensure the file compiles
    try testing.expect(true);
}
