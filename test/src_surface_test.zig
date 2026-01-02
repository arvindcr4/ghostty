// test/Surface.zig
const std = @import("std");
const testing = std.testing;
const Surface = @import("../src/Surface.zig");
const Cell = @import("../src/lib/types.zig").Cell;
const Position = @import("../src/lib/types.zig").Position;
const Size = @import("../src/lib/types.zig").Size;

test "Surface.init" {
    const allocator = testing.allocator;
    const size = Size{ .width = 80, .height = 24 };
    var surface = try Surface.init(allocator, size);
    defer surface.deinit();
    
    try testing.expectEqual(size, surface.size);
    try testing.expect(surface.grid != null);
    try testing.expectEqual(@as(usize, 80 * 24), surface.grid.?.len);
}

test "Surface.clear" {
    const allocator = testing.allocator;
    const size = Size{ .width = 10, .height = 5 };
    var surface = try Surface.init(allocator, size);
    defer surface.deinit();
    
    // Set some cells
    try surface.setCell(Position{ .x = 0, .y = 0 }, Cell{ .ch = 'A' });
    try surface.setCell(Position{ .x = 5, .y = 3 }, Cell{ .ch = 'B' });
    
    surface.clear();
    
    // Verify all cells are cleared
    for (0..size.height) |y| {
        for (0..size.width) |x| {
            const cell = surface.getCell(Position{ .x = @intCast(x), .y = @intCast(y) });
            try testing.expectEqual(@as(u21, 0), cell.ch);
        }
    }
}

test "Surface.setCell and getCell" {
    const allocator = testing.allocator;
    const size = Size{ .width = 10, .height = 5 };
    var surface = try Surface.init(allocator, size);
    defer surface.deinit();
    
    const pos = Position{ .x = 5, .y = 3 };
    const cell = Cell{ .ch = 'X', .fg = .{ .rgb = 0xFF0000 }, .bg = .{ .rgb = 0x00FF00 } };
    
    try surface.setCell(pos, cell);
    const retrieved = surface.getCell(pos);
    
    try testing.expectEqual(cell.ch, retrieved.ch);
    try testing.expectEqual(cell.fg.rgb, retrieved.fg.rgb);
    try testing.expectEqual(cell.bg.rgb, retrieved.bg.rgb);
}

test "Surface.scrollUp" {
    const allocator = testing.allocator;
    const size = Size{ .width = 5, .height = 3 };
    var surface = try Surface.init(allocator, size);
    defer surface.deinit();
    
    // Fill with distinct content
    for (0..size.height) |y| {
        for (0..size.width) |x| {
            const ch = @intCast(u21, 'A' + y * size.width + x);
            try surface.setCell(Position{ .x = @intCast(x), .y = @intCast(y) }, Cell{ .ch = ch });
        }
    }
    
    surface.scrollUp(1);
    
    // Verify scroll
    try testing.expectEqual(@as(u21, 'F'), surface.getCell(Position{ .x = 0, .y = 0 }).ch);
    try testing.expectEqual(@as(u21, 'G'), surface.getCell(Position{ .x = 1, .y = 0 }).ch);
    
    // Bottom line should be empty
    for (0..size.width) |x| {
        const cell = surface.getCell(Position{ .x = @intCast(x), .y = 2 });
        try testing.expectEqual(@as(u21, 0), cell.ch);
    }
}

test "Surface.scrollDown" {
    const allocator = testing.allocator;
    const size = Size{ .width = 5, .height = 3 };
    var surface = try Surface.init(allocator, size);
    defer surface.deinit();
    
    // Fill with distinct content
    for (0..size.height) |y| {
        for (0..size.width) |x| {
            const ch = @intCast(u21, 'A' + y * size.width + x);
            try surface.setCell(Position{ .x = @intCast(x), .y = @intCast(y) }, Cell{ .ch = ch });
        }
    }
    
    surface.scrollDown(1);
    
    // Top line should be empty
    for (0..size.width) |x| {
        const cell = surface.getCell(Position{ .x = @intCast(x), .y = 0 });
        try testing.expectEqual(@as(u21, 0), cell.ch);
    }
    
    // Verify content shifted down
    try testing.expectEqual(@as(u21, 'A'), surface.getCell(Position{ .x = 0, .y = 1 }).ch);
}

test "Surface.insertLine" {
    const allocator = testing.allocator;
    const size = Size{ .width = 5, .height = 4 };
    var surface = try Surface.init(allocator, size);
    defer surface.deinit();
    
    // Fill with content
    for (0..size.height) |y| {
        for (0..size.width) |x| {
            const ch = @intCast(u21, 'A' + y);
            try surface.setCell(Position{ .x = @intCast(x), .y = @intCast(y) }, Cell{ .ch = ch });
        }
    }
    
    try surface.insertLine(1);
    
    // Line 1 should be empty
    for (0..size.width) |x| {
        const cell = surface.getCell(Position{ .x = @intCast(x), .y = 1 });
        try testing.expectEqual(@as(u21, 0), cell.ch);
    }
    
    // Content should be shifted down
    try testing.expectEqual(@as(u21, 'B'), surface.getCell(Position{ .x = 0, .y = 2 }).ch);
    try testing.expectEqual(@as(u21, 'C'), surface.getCell(Position{ .x = 0, .y = 3 }).ch);
}

test "Surface.deleteLine" {
    const allocator = testing.allocator;
    const size = Size{ .width = 5, .height = 4 };
    var surface = try Surface.init(allocator, size);
    defer surface.deinit();
    
    // Fill with content
    for (0..size.height) |y| {
        for (0..size.width) |x| {
            const ch = @intCast(u21, 'A' + y);
            try surface.setCell(Position{ .x = @intCast(x), .y = @intCast(y) }, Cell{ .ch = ch });
        }
    }
    
    try surface.deleteLine(1);
    
    // Line 1 should have content from line 2
    try testing.expectEqual(@as(u21, 'C'), surface.getCell(Position{ .x = 0, .y = 1 }).ch);
    
    // Bottom line should be empty
    for (0..size.width) |x| {
        const cell = surface.getCell(Position{ .x = @intCast(x), .y = 3 });
        try testing.expectEqual(@as(u21, 0), cell.ch);
    }
}

test "Surface.resize" {
    const allocator = testing.allocator;
    const size = Size{ .width = 5, .height = 3 };
    var surface = try Surface.init(allocator, size);
    defer surface.deinit();
    
    // Set some content
    try surface.setCell(Position{ .x = 2, .y = 1 }, Cell{ .ch = 'X' });
    
    const new_size = Size{ .width = 8, .height = 5 };
    try surface.resize(new_size);
    
    try testing.expectEqual(new_size, surface.size);
    try testing.expectEqual(@as(usize, 8 * 5), surface.grid.?.len);
    
    // Content should be preserved
    try testing.expectEqual(@as(u21, 'X'), surface.getCell(Position{ .x = 2, .y = 1 }).ch);
}

test "Surface.fillRegion" {
    const allocator = testing.allocator;
    const size = Size{ .width = 10, .height = 5 };
    var surface = try Surface.init(allocator, size);
    defer surface.deinit();
    
    const region = struct {
        x: usize = 2,
        y: usize = 1,
        width: usize = 5,
        height: usize = 2,
    };
    
    const fill_cell = Cell{ .ch = '#', .fg = .{ .rgb = 0xFF0000 } };
    
    try surface.fillRegion(region.x, region.y, region.width, region.height, fill_cell);
    
    // Check filled region
    for (region.y..region.y + region.height) |y| {
        for (region.x..region.x + region.width) |x| {
            const cell = surface.getCell(Position{ .x = @intCast(x), .y = @intCast(y) });
            try testing.expectEqual(fill_cell.ch, cell.ch);
            try testing.expectEqual(fill_cell.fg.rgb, cell.fg.rgb);
        }
    }
    
    // Check outside region
    try testing.expectEqual(@as(u21, 0), surface.getCell(Position{ .x = 0, .y = 0 }).ch);
    try testing.expectEqual(@as(u21, 0), surface.getCell(Position{ .x = 9, .y = 4 }).ch);
}

test "Surface.performance_bulkOperations" {
    const allocator = testing.allocator;
    const size = Size{ .width = 200, .height = 100 };
    var surface = try Surface.init(allocator, size);
    defer surface.deinit();
    
    const start_time = std.time.nanoTimestamp();
    
    // Bulk fill
    const fill_cell = Cell{ .ch = 'X' };
    try surface.fillRegion(0, 0, size.width, size.height, fill_cell);
    
    // Bulk read
    var sum: usize = 0;
    for (0..size.height) |y| {
        for (0..size.width) |x| {
            const cell = surface.getCell(Position{ .x = @intCast(x), .y = @intCast(y) });
            sum += @as(usize, cell.ch);
        }
    }
    
    const end_time = std.time.nanoTimestamp();
    const duration = end_time - start_time;
    
    // Should complete in reasonable time (less than 100ms for 20k cells)
    try testing.expect(duration < 100_000_000);
    try testing.expect(sum > 0);
}

// test/surface_mouse.zig
const std = @import("std");
const testing = std.testing;
const SurfaceMouse = @import("../src/surface_mouse.zig");
const Surface = @import("../src/Surface.zig");
const MouseEvent = @import("../src/lib/types.zig").MouseEvent;
const Position = @import("../src/lib/types.zig").Position;

test "SurfaceMouse.init" {
    const allocator = testing.allocator;
    const size = struct { width: u16 = 80, height: u16 = 24 };
    var surface = try Surface.init(allocator, .{ .width = size.width, .height = size.height });
    defer surface.deinit();
    
    var mouse_handler = SurfaceMouse.init(&surface);
    try testing.expect(mouse_handler.surface == &surface);
    try testing.expectEqual(@as(u16, 0), mouse_handler.last_x);
    try testing.expectEqual(@as(u16, 0), mouse_handler.last_y);
}

test "SurfaceMouse.handleClick" {
    const allocator = testing.allocator;
    var surface = try Surface.init(allocator, .{ .width = 10, .height = 5 });
    defer surface.deinit();
    
    var mouse_handler = SurfaceMouse.init(&surface);
    
    const event = MouseEvent{
        .x = 5,
        .y = 3,
        .button = .left,
        .action = .press,
        .modifiers = .{},
    };
    
    const handled = mouse_handler.handleClick(event);
    try testing.expect(handled);
    try testing.expectEqual(@as(u16, 5), mouse_handler.last_x);
    try testing.expectEqual(@as(u16, 3), mouse_handler.last_y);
}

test "SurfaceMouse.handleDrag" {
    const allocator = testing.allocator;
    var surface = try Surface.init(allocator, .{ .width = 10, .height = 5 });
    defer surface.deinit();
    
    var mouse_handler = SurfaceMouse.init(&surface);
    
    // Start drag
    const press_event = MouseEvent{
        .x = 2,
        .y = 2,
        .button = .left,
        .action = .press,
        .modifiers = .{},
    };
    _ = mouse_handler.handleClick(press_event);
    
    // Drag to new position
    const drag_event = MouseEvent{
        .x = 5,
        .y = 4,
        .button = .left,
        .action = .drag,
        .modifiers = .{},
    };
    
    const handled = mouse_handler.handleDrag(drag_event);
    try testing.expect(handled);
    try testing.expectEqual(@as(u16, 5), mouse_handler.last_x);
    try testing.expectEqual(@as(u16, 4), mouse_handler.last_y);
}

test "SurfaceMouse.getSelection" {
    const allocator = testing.allocator;
    var surface = try Surface.init(allocator, .{ .width = 10, .height = 5 });
    defer surface.deinit();
    
    var mouse_handler = SurfaceMouse.init(&surface);
    
    // Select from (1,1) to (5,3)
    const start = MouseEvent{
        .x = 1,
        .y = 1,
        .button = .left,
        .action = .press,
        .modifiers = .{},
    };
    const end = MouseEvent{
        .x = 5,
        .y = 3,
        .button = .left,
        .action = .release,
        .modifiers = .{},
    };
    
    _ = mouse_handler.handleClick(start);
    _ = mouse_handler.handleClick(end);
    
    const selection = mouse_handler.getSelection();
    try testing.expectEqual(@as(u16, 1), selection.start.x);
    try testing.expectEqual(@as(u16, 1), selection.start.y);
    try testing.expectEqual(@as(u16, 5), selection.end.x);
    try testing.expectEqual(@as(u16, 3), selection.end.y);
}

test "SurfaceMouse.doubleClick" {
    const allocator = testing.allocator;
    var surface = try Surface.init(allocator, .{ .width = 10, .height = 5 });
    defer surface.deinit();
    
    var mouse_handler = SurfaceMouse.init(&surface);
    
    const event = MouseEvent{
        .x = 3,
        .y = 2,
        .button = .left,
        .action = .press,
        .modifiers = .{},
    };
    
    // First click
    _ = mouse_handler.handleClick(event);
    
    // Simulate time passing (in real implementation, this would be actual time)
    mouse_handler.last_click_time = std.time.nanoTimestamp() - 100_000_000; // 100ms ago
    
    // Second click
    const handled = mouse_handler.handleClick(event);
    try testing.expect(handled);
    try testing.expect(mouse_handler.is_double_click);
}

test "SurfaceMouse.rightClickMenu" {
    const allocator = testing.allocator;
    var surface = try Surface.init(allocator, .{ .width = 10, .height = 5 });
    defer surface.deinit();
    
    var mouse_handler = SurfaceMouse.init(&surface);
    
    const event = MouseEvent{
        .x = 5,
        .y = 3,
        .button = .right,
        .action = .press,
        .modifiers = .{},
    };
    
    const handled = mouse_handler.handleClick(event);
    try testing.expect(handled);
    try testing.expect(mouse_handler.show_menu);
    try testing.expectEqual(@as(u16, 5), mouse_handler.menu_x);
    try testing.expectEqual(@as(u16, 3), mouse_handler.menu_y);
}

test "SurfaceMouse.scrollWheel" {
    const allocator = testing.allocator;
    var surface = try Surface.init(allocator, .{ .width = 10, .height = 5 });
    defer surface.deinit();
    
    var mouse_handler = SurfaceMouse.init(&surface);
    
    const scroll_event = MouseEvent{
        .x = 5,
        .y = 3,
        .button = .wheel_up,
        .action = .press,
        .modifiers = .{},
    };
    
    const handled = mouse_handler.handleScroll(scroll_event);
    try testing.expect(handled);
    try testing.expectEqual(@as(i8, 1), mouse_handler.scroll_delta);
}

// test/renderer.zig
const std = @import("std");
const testing = std.testing;
const Renderer = @import("../src/renderer.zig");
const Surface = @import("../src/Surface.zig");
const Cell = @import("../src/lib/types.zig").Cell;
const Color = @import("../src/lib/types.zig").Color;
const Size = @import("../src/lib/types.zig").Size;

test "Renderer.init" {
    const allocator = testing.allocator;
    var surface = try Surface.init(allocator, .{ .width = 80, .height = 24 });
    defer surface.deinit();
    
    var renderer = try Renderer.init(allocator, &surface);
    defer renderer.deinit();
    
    try testing.expect(renderer.surface == &surface);
    try testing.expect(renderer.font != null);
    try testing.expect(renderer.atlas != null);
}

test "Renderer.renderCell" {
    const allocator = testing.allocator;
    var surface = try Surface.init(allocator, .{ .width = 10, .height = 5 });
    defer surface.deinit();
    
    var renderer = try Renderer.init(allocator, &surface);
    defer renderer.deinit();
    
    const cell = Cell{
        .ch = 'A',
        .fg = .{ .rgb = 0xFF0000 },
        .bg = .{ .rgb = 0x000000 },
        .bold = false,
        .italic = false,
        .underline = false,
    };
    
    try surface.setCell(.{ .x = 5, .y = 3 }, cell);
    
    const render_result = try renderer.renderCell(5, 3);
    try testing.expect(render_result.success);
    try testing.expectEqual(cell.ch, render_result.glyph);
    try testing.expectEqual(cell.fg.rgb, render_result.fg_color);
}

test "Renderer.renderLine" {
    const allocator = testing.allocator;
    var surface = try Surface.init(allocator, .{ .width = 10, .height = 5 });
    defer surface.deinit();
    
    var renderer = try Renderer.init(allocator, &surface);
    defer renderer.deinit();
    
    // Fill line with content
    for (0..10) |x| {
        const cell = Cell{ .ch = @intCast(u21, 'A' + x) };
        try surface.setCell(.{ .x = @intCast(x), .y = 2 }, cell);
    }
    
    const render_result = try renderer.renderLine(2);
    try testing.expect(render_result.success);
    try testing.expectEqual(@as(usize, 10), render_result.cell_count);
}

test "Renderer.renderFull" {
    const allocator = testing.allocator;
    var surface = try Surface.init(allocator, .{ .width = 5, .height = 3 });
    defer surface.deinit();
    
    var renderer = try Renderer.init(allocator, &surface);
    defer renderer.deinit();
    
    // Fill surface with content
    for (0..3) |y| {
        for (0..5) |x| {
            const cell = Cell{ .ch = @intCast(u21, 'A' + y * 5 + x) };
            try surface.setCell(.{ .x = @intCast(x), .y = @intCast(y) }, cell);
        }
    }
    
    const render_result = try renderer.renderFull();
    try testing.expect(render_result.success);
    try testing.expectEqual(@as(usize, 15), render_result.total_cells);
    try testing.expectEqual(@as(usize, 3), render_result.lines_rendered);
}

test "Renderer.cursorRendering" {
    const allocator = testing.allocator;
    var surface = try Surface.init(allocator, .{ .width = 10, .height = 5 });
    defer surface.deinit();
    
    var renderer = try Renderer.init(allocator, &surface);
    defer renderer.deinit();
    
    renderer.setCursorPosition(.{ .x = 4, .y = 2 });
    renderer.setCursorStyle(.block);
    
    const cursor_result = renderer.renderCursor();
    try testing.expect(cursor_result.visible);
    try testing.expectEqual(@as(u16, 4), cursor_result.x);
    try testing.expectEqual(@as(u16, 2), cursor_result.y);
    try testing.expectEqual(.block, cursor_result.style);
}

test "Renderer.colorConversion" {
    const allocator = testing.allocator;
    var surface = try Surface.init(allocator, .{ .width = 10, .height = 5 });
    defer surface.deinit();
    
    var renderer = try Renderer.init(allocator, &surface);
    defer renderer.deinit();
    
    // Test RGB color conversion
    const rgb_color = Color{ .rgb = 0x80FF40 };
    const converted = renderer.convertColor(rgb_color);
    try testing.expectEqual(@as(f32, 0.5), converted.r);
    try testing.expectEqual(@as(f32, 1.0), converted.g);
    try testing.expectEqual(@as(f32, 0.25), converted.b);
}

test "Renderer.fontMetrics" {
    const allocator = testing.allocator;
    var surface = try Surface.init(allocator, .{ .width = 10, .height = 5 });
    defer surface.deinit();
    
    var renderer = try Renderer.init(allocator, &surface);
    defer renderer.deinit();
    
    const metrics = renderer.getFontMetrics();
    try testing.expect(metrics.width > 0);
    try testing.expect(metrics.height > 0);
    try testing.expect(metrics.ascent > 0);
    try testing.expect(metrics.descent >= 0);
}

test "Renderer.performance_renderFull" {
    const allocator = testing.allocator;
    var surface = try Surface.init(allocator, .{ .width = 200, .height = 100 });
    defer surface.deinit();
    
    var renderer = try Renderer.init(allocator, &surface);
    defer renderer.deinit();
    
    // Fill with content
    for (0..100) |y| {
        for (0..200) |x| {
            const cell = Cell{ .ch = @intCast(u21, 'A' + (x + y) % 26) };
            try surface.setCell(.{ .x = @intCast(x), .y = @intCast(y) }, cell);
        }
    }
    
    const start_time = std.time.nanoTimestamp();
    const result = try renderer.renderFull();
    const end_time = std.time.nanoTimestamp();
    
    const duration = end_time - start_time;
    
    try testing.expect(result.success);
    try testing.expect(duration < 50_000_000); // Should render 20k cells in < 50ms
    try testing.expectEqual(@as(usize, 20000), result.total_cells);
}

// test/math.zig (extended tests)
const std = @import("std");
const testing = std.testing;
const math = @import("../src/math.zig");

test "Math.clampExtended" {
    try testing.expectEqual(@as(i32, 5), math.clamp(i32, 5, 0, 10));
    try testing.expectEqual(@as(i32, 0), math.clamp(i32, -5, 0, 10));
    try testing.expectEqual(@as(i32, 10), math.clamp(i32, 15, 0, 10));
    try testing.expectEqual(@as(f32, 5.5), math.clamp(f32, 5.5, 0.0, 10.0));
}

test "Math.lerp" {
    try testing.expectEqual(@as(f32, 5.0), math.lerp(0.0, 10.0, 0.5));
    try testing.expectEqual(@as(f32, 0.0), math.lerp(0.0, 10.0, 0.0));
    try testing.expectEqual(@as(f32, 10.0), math.lerp(0.0, 10.0, 1.0));
    try testing.expectEqual(@as(f32, 7.5), math.lerp(5.0, 10.0, 0.5));
}

test "Math.smoothstep" {
    try testing.expectEqual(@as(f32, 0.0), math.smoothstep(0.0, 1.0, 0.0));
    try testing.expectEqual(@as(f32, 1.0), math.smoothstep(0.0, 1.0, 1.0));
    try testing.expectEqual(@as(f32, 0.5), math.smoothstep(0.0, 1.0, 0.5));
    
    // Edge cases
    try testing.expectEqual(@as(f32, 0.0), math.smoothstep(0.0, 1.0, -0.5));
    try testing.expectEqual(@as(f32, 1.0), math.smoothstep(0.0, 1.0, 1.5));
}

test "Math.wrap" {
    try testing.expectEqual(@as(i32, 2), math.wrap(i32, 7, 0, 5));
    try testing.expectEqual(@as(i32, 3), math.wrap(i32, -2, 0, 5));
    try testing.expectEqual(@as(i32, 0), math.wrap(i32, 5, 0, 5));
    try testing.expectEqual(@as(u32, 2), math.wrap(u32, 7, 0, 5));
}

test "Math.sign" {
    try testing.expectEqual(@as(i32, 1), math.sign(5));
    try testing.expectEqual(@as(i32, -1), math.sign(-5));
    try testing.expectEqual(@as(i32, 0), math.sign(0));
    try testing.expectEqual(@as(i32, 1), math.sign(0.1));
    try testing.expectEqual(@as(i32, -1), math.sign(-0.1));
}

test "Math.fract" {
    try testing.expectEqual(@as(f32, 0.5), math.fract(3.5));
    try testing.expectEqual(@as(f32, 0.0), math.fract(5.0));
    try testing.expectEqual(@as(f32, 0.75), math.fract(-2.25));
}

test "Math.degreesToRadians" {
    try testing.expectApproxEqAbs(@as(f32, 0.0), math.degreesToRadians(0.0), 0.001);
    try testing.expectApproxEqAbs(@as(f32, std.math.pi / 2.0), math.degreesToRadians(90.0), 0.001);
    try testing.expectApproxEqAbs(@as(f32, std.math.pi), math.degreesToRadians(180.0), 0.001);
    try testing.expectApproxEqAbs(@as(f32, 2.0 * std.math.pi), math.degreesToRadians(360.0), 0.001);
}

test "Math.radiansToDegrees" {
    try testing.expectApproxEqAbs(@as(f32, 0.0), math.radiansToDegrees(0.0), 0.001);
    try testing.expectApproxEqAbs(@as(f32, 90.0), math.radiansToDegrees(std.math.pi / 2.0), 0.001);
    try testing.expectApproxEqAbs(@as(f32, 180.0), math.radiansToDegrees(std.math.pi), 0.001);
    try testing.expectApproxEqAbs(@as(f32, 360.0), math.radiansToDegrees(2.0 * std.math.pi), 0.001);
}

test "Math.isPowerOfTwo" {
    try testing.expect(math.isPowerOfTwo(1));
    try testing.expect(math.isPowerOfTwo(2));
    try testing.expect(math.isPowerOfTwo(4));
    try testing.expect(math.isPowerOfTwo(8));
    try testing.expect(math.isPowerOfTwo(16));
    try testing.expect(!math.isPowerOfTwo(0));
    try testing.expect(!math.isPowerOfTwo(3));
    try testing.expect(!math.isPowerOfTwo(5));
    try testing.expect(!math.isPowerOfTwo(12));
}

test "Math.nextPowerOfTwo" {
    try testing.expectEqual(@as(u32, 1), math.nextPowerOfTwo(u32, 1));
    try testing.expectEqual(@as(u32, 2), math.nextPowerOfTwo(u32, 2));
    try testing.expectEqual(@as(u32, 4), math.nextPowerOfTwo(u32, 3));
    try testing.expectEqual(@as(u32, 8), math.nextPowerOfTwo(u32, 5));
    try testing.expectEqual(@as(u32, 16), math.nextPowerOfTwo(u32, 9));
}

test "Math.performance_vectorOperations" {
    const iterations = 100000;
    const start_time = std.time.nanoTimestamp();
    
    var sum: f32 = 0.0;
    var i: usize = 0;
    while (i < iterations) : (i += 1) {
        sum += math.lerp(0.0, 100.0, @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(iterations)));
        sum += math.clamp(f32, @as(f32, @floatFromInt(i)) - 50.0, 0.0, 100.0);
        sum += math.fract(@as(f32, @floatFromInt(i)) * 0.123);
    }
    
    const end_time = std.time.nanoTimestamp();
    const duration = end_time - start_time;
    
    try testing.expect(sum > 0);
    try testing.expect(duration < 10_000_000); // Should complete in < 10ms
}

// test/lib/struct.zig (extended tests)
const std = @import("std");
const testing = std.testing;
const struct_utils = @import("../src/lib/struct.zig");

const TestStruct = struct {
    a: u32,
    b: f64,
    c: bool,
    
    pub fn init(a_val: u32, b_val: f64, c_val: bool) @This() {
        return .{ .a = a_val, .b = b_val, .c = c_val };
    }
};

test "StructUtils.clone" {
    const original = TestStruct.init(42, 3.14, true);
    const cloned = struct_utils.clone(TestStruct, original);
    
    try testing.expectEqual(original.a, cloned.a);
    try testing.expectEqual(original.b, cloned.b);
    try testing.expectEqual(original.c, cloned.c);
    
    // Ensure it's a copy
    cloned.a = 100;
    try testing.expectEqual(@as(u32, 42), original.a);
    try testing.expectEqual(@as(u32, 100), cloned.a);
}

test "StructUtils.equals" {
    const s1 = TestStruct.init(42, 3.14, true);
    const s2 = TestStruct.init(42, 3.14, true);
    const s3 = TestStruct.init(43, 3.14, true);
    
    try testing.expect(struct_utils.equals(TestStruct, s1, s2));
    try testing.expect(!struct_utils.equals(TestStruct, s1, s3));
}

test "StructUtils.zero" {
    const zeroed = struct_utils.zero(TestStruct);
    
    try testing.expectEqual(@as(u32, 0), zeroed.a);
    try testing.expectEqual(@as(f64, 0.0), zeroed.b);
    try testing.expectEqual(false, zeroed.c);
}

test "StructUtils.copy" {
    const source = TestStruct.init(100, 2.71, false);
    var dest = TestStruct.init(0, 0.0, true);
    
    struct_utils.copy(TestStruct, &dest, &source);
    
    try testing.expectEqual(source.a, dest.a);
    try testing.expectEqual(source.b, dest.b);
    try testing.expectEqual(source.c, dest.c);
}

test "StructUtils.swap" {
    var s1 = TestStruct.init(1, 1.0, true);
    var s2 = TestStruct.init(2, 2.0, false);
    
    struct_utils.swap(TestStruct, &s1, &s2);
    
    try testing.expectEqual(@as(u32, 2), s1.a);
    try testing.expectEqual(@as(f64, 2.0), s1.b);
    try testing.expectEqual(false, s1.c);
    
    try testing.expectEqual(@as(u32, 1), s2.a);
    try testing.expectEqual(@as(f64, 1.0), s2.b);
    try testing.expectEqual(true, s2.c);
}

test "StructUtils.hash" {
    const s1 = TestStruct.init(42, 3.14, true);
    const s2 = TestStruct.init(42, 3.14, true);
    const s3 = TestStruct.init(43, 3.14, true);
    
    const hash1 = struct_utils.hash(TestStruct, s1);
    const hash2 = struct_utils.hash(TestStruct, s2);
    const hash3 = struct_utils.hash(TestStruct, s3);
    
    try testing.expectEqual(hash1, hash2);
    try testing.expect(hash1 != hash3);
}

test "StructUtils.toString" {
    const s = TestStruct.init(42, 3.14, true);
    const str = try struct_utils.toString(TestStruct, testing.allocator, s);
    defer testing.allocator.free(str);
    
    try testing.expect(std.mem.indexOf(u8, str, "42") != null);
    try testing.expect(std.mem.indexOf(u8, str, "3.14") != null);
    try testing.expect(std.mem.indexOf(u8, str, "true") != null);
}

test "StructUtils.fromBytes" {
    const s = TestStruct.init(0xDEADBEEF, 2.71828, true);
    
    const bytes = std.mem.asBytes(&s);
    const restored = struct_utils.fromBytes(TestStruct, bytes);
    
    try testing.expectEqual(s.a, restored.a);
    try testing.expectEqual(s.b, restored.b);
    try testing.expectEqual(s.c, restored.c);
}

test "StructUtils.performance_operations" {
    const iterations = 100000;
    const original = TestStruct.init(42, 3.14, true);
    
    const start_time = std.time.nanoTimestamp();
    
    var i: usize = 0;
    while (i < iterations) : (i += 1) {
        var cloned = struct_utils.clone(TestStruct, original);
        cloned.a = @intCast(i);
        _ = struct_utils.hash(TestStruct, cloned);
    }
    
    const end_time = std.time.nanoTimestamp();
    const duration = end_time - start_time;
    
    try testing.expect(duration < 50_000_000); // Should complete in < 50ms
}

// test/lib/types.zig (extended tests)
const std = @import("std");
const testing = std.testing;
const types = @import("../src/lib/types.zig");

test "Types.Position_operations" {
    const pos1 = types.Position{ .x = 10, .y = 20 };
    const pos2 = types.Position{ .x = 5, .y = 15 };
    
    const sum = pos1.add(pos2);
    try testing.expectEqual(@as(u16, 15), sum.x);
    try testing.expectEqual(@as(u16, 35), sum.y);
    
    const diff = pos1.sub(pos2);
    try testing.expectEqual(@as(i16, 5), diff.x);
    try testing.expectEqual(@as(i16, 5), diff.y);
    
    try testing.expect(pos1.equals(types.Position{ .x = 10, .y = 20 }));
    try testing.expect(!pos1.equals(pos2));
}

test "Types.Size_operations" {
    const size1 = types.Size{ .width = 100, .height = 50 };
    const size2 = types.Size{ .width = 25, .height = 25 };
    
    const area = size1.area();
    try testing.expectEqual(@as(u32, 5000), area);
    
    try testing.expect(size1.contains(types.Position{ .x = 50, .y = 25 }));
    try testing.expect(!size1.contains(types.Position{ .x = 100, .y = 50 }));
    
    const scaled = size1.scale(2.0);
    try testing.expectEqual(@as(u16, 200), scaled.width);
    try testing.expectEqual(@as(u16, 100), scaled.height);
}

test "Types.Color_conversions" {
    const rgb = types.Color{ .rgb = 0x80FF40 };
    const rgba = rgb.toRGBA();
    try testing.expectEqual(@as(u8, 0x80), rgba.r);
    try testing.expectEqual(@as(u8, 0xFF), rgba.g);
    try testing.expectEqual(@as(u8, 0x40), rgba.b);
    try testing.expectEqual(@as(u8, 0xFF), rgba.a);
    
    const hsl = rgb.toHSL();
    try testing.expect(hsl.h >= 0.0 and hsl.h <= 360.0);
    try testing.expect(hsl.s >= 0.0 and hsl.s <= 1.0);
    try testing.expect(hsl.l >= 0.0 and hsl.l <= 1.0);
    
    const from_hsl = types.Color.fromHSL(hsl);
    try testing.expectApproxEqAbs(@as(f32, 0.5), @as(f32, from_hsl.r) / 255.0, 0.1);
    try testing.expectApproxEqAbs(@as(f32, 1.0), @as(f32, from_hsl.g) / 255.0, 0.1);
    try testing.expectApproxEqAbs(@as(f32, 0.25), @as(f32, from_hsl.b) / 255.0, 0.1);
}

test "Types.Cell_attributes" {
    var cell = types.Cell{
        .ch = 'A',
        .fg = .{ .rgb = 0xFF0000 },
        .bg = .{ .rgb = 0x00FF00 },
        .bold = false,
        .italic = false,
        .underline = false,
    };
    
    cell.setBold(true);
    try testing.expect(cell.bold);
    
    cell.setItalic(true);
    try testing.expect(cell.italic);
    
    cell.setUnderline(.single);
    try testing.expectEqual(types.UnderlineStyle.single, cell.underline);
    
    cell.setUnderline(.double);
    try testing.expectEqual(types.UnderlineStyle.double, cell.underline);
    
    cell.clearAttributes();
    try testing.expect(!cell.bold);
    try testing.expect(!cell.italic);
    try testing.expectEqual(types.UnderlineStyle.none, cell.underline);
}

test "Types.MouseEvent_validation" {
    const event = types.MouseEvent{
        .x = 100,
        .y = 50,
        .button = .left,
        .action = .press,
        .modifiers = .{ .shift = true, .ctrl = false },
    };
    
    try testing.expect(event.isValid());
    try testing.expect(event.hasModifier(.shift));
    try testing.expect(!event.hasModifier(.ctrl));
    
    const invalid_event = types.MouseEvent{
        .x = 1000,
        .y = 1000,
        .button = .left,
        .action = .press,
        .modifiers = .{},
    };
    
    try testing.expect(!invalid_event.isValid());
}

test "Types.KeyEvent_handling" {
    const key_event = types.KeyEvent{
        .key = .{ .code = .a },
        .action = .press,
        .modifiers = .{ .ctrl = true },
    };
    
    try testing.expect(key_event.isPress());
    try testing.expect(!key_event.isRelease());
    try testing.expect(key_event.hasModifier(.ctrl));
    try testing.expectEqual(types.KeyCode.a, key_event.key.code);
    
    const special_key = types.KeyEvent{
        .key = .{ .special = .enter },
        .action = .press,
        .modifiers = .{},
    };
    
    try testing.expect(special_key.isSpecial());
    try testing.expectEqual(types.SpecialKey.enter, special_key.key.special);
}

test "Types.Rect_operations" {
    const rect = types.Rect{
        .x = 10,
        .y = 20,
        .width = 100,
        .height = 50,
    };
    
    try testing.expect(rect.contains(types.Position{ .x = 50, .y = 30 }));
    try testing.expect(!rect.contains(types.Position{ .x = 5, .y = 30 }));
    try testing.expect(!rect.contains(types.Position{ .x = 110, .y = 30 }));
    
    const expanded = rect.expand(10);
    try testing.expectEqual(@as(i16, 0), expanded.x);
    try testing.expectEqual(@as(i16, 10), expanded.y);
    try testing.expectEqual(@as(u16, 120), expanded.width);
    try testing.expectEqual(@as(u16, 70), expanded.height);
    
    const intersected = rect.intersect(types.Rect{
        .x = 50,
        .y = 30,
        .width = 100,
        .height = 50,
    });
    
    try testing.expectEqual(@as(i16, 50), intersected.x);
    try testing.expectEqual(@as(i16, 30), intersected.y);
    try testing.expectEqual(@as(u16, 60), intersected.width);
    try testing.expectEqual(@as(u16, 40), intersected.height);
}

test "Types.performance_colorConversions" {
    const iterations = 100000;
    const rgb = types.Color{ .rgb = 0x80FF40 };
    
    const start_time = std.time.nanoTimestamp();
    
    var i: usize = 0;
    while (i < iterations) : (i += 1) {
        const rgba = rgb.toRGBA();
        const hsl = rgb.toHSL();
        const back = types.Color.fromHSL(hsl);
        _ = rgba;
        _ = back;
    }
    
    const end_time = std.time.nanoTimestamp();
    const duration = end_time - start_time;
    
    try testing.expect(duration < 100_000_000); // Should complete in < 100ms
}

test "Types.performance_positionOperations" {
    const iterations = 100000;
    const pos1 = types.Position{ .x = 100, .y = 200 };
    const pos2 = types.Position{ .x = 50, .y = 75 };
    
    const start_time = std.time.nanoTimestamp();
    
    var i: usize = 0;
    while (i < iterations) : (i += 1) {
        const sum = pos1.add(pos2);
        const diff = pos1.sub(pos2);
        const equal = pos1.equals(pos2);
        _ = sum;
        _ = diff;
        _ = equal;
    }
    
    const end_time = std.time.nanoTimestamp();
    const duration = end_time - start_time;
    
    try testing.expect(duration < 10_000_000); // Should complete in < 10ms
}