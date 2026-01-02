const std = @import("std");
const testing = std.testing;
const Inspector = @import("src/inspector/Inspector.zig").Inspector;
const Cell = @import("src/inspector/cell.zig").Cell;
const Cursor = @import("src/inspector/cursor.zig").Cursor;
const Key = @import("src/inspector/key.zig").Key;
const Page = @import("src/inspector/page.zig").Page;
const Termio = @import("src/inspector/termio.zig").Termio;
const Units = @import("src/inspector/units.zig").Units;

test "Inspector initialization" {
    const allocator = testing.allocator;
    var inspector = try Inspector.init(allocator);
    defer inspector.deinit();
    
    try testing.expect(inspector.isInitialized());
    try testing.expectEqual(@as(usize, 0), inspector.getCellCount());
}

test "Inspector main functionality" {
    const allocator = testing.allocator;
    var inspector = try Inspector.init(allocator);
    defer inspector.deinit();
    
    try inspector.startInspection();
    try testing.expect(inspector.isInspecting());
    
    try inspector.stopInspection();
    try testing.expect(!inspector.isInspecting());
}

test "Cell inspection" {
    var cell = Cell.init();
    cell.setContent('A');
    cell.setAttributes(.{ .bold = true });
    
    try testing.expectEqual('A', cell.getContent());
    try testing.expect(cell.getAttributes().bold);
    
    cell.clear();
    try testing.expectEqual(' ', cell.getContent());
    try testing.expect(!cell.getAttributes().bold);
}

test "Cell attributes" {
    var cell = Cell.init();
    const attrs = Cell.Attributes{
        .bold = true,
        .italic = false,
        .underline = true,
        .foreground = .{ .r = 255, .g = 0, .b = 0 },
        .background = .{ .r = 0, .g = 255, .b = 0 },
    };
    
    cell.setAttributes(attrs);
    const retrieved = cell.getAttributes();
    
    try testing.expect(attrs.bold == retrieved.bold);
    try testing.expect(attrs.italic == retrieved.italic);
    try testing.expect(attrs.underline == retrieved.underline);
    try testing.expectEqual(attrs.foreground, retrieved.foreground);
    try testing.expectEqual(attrs.background, retrieved.background);
}

test "Cursor position tracking" {
    var cursor = Cursor.init();
    
    cursor.setPosition(10, 5);
    try testing.expectEqual(@as(usize, 10), cursor.col);
    try testing.expectEqual(@as(usize, 5), cursor.row);
    
    cursor.move(1, 0);
    try testing.expectEqual(@as(usize, 11), cursor.col);
    try testing.expectEqual(@as(usize, 5), cursor.row);
    
    cursor.move(0, 1);
    try testing.expectEqual(@as(usize, 11), cursor.col);
    try testing.expectEqual(@as(usize, 6), cursor.row);
}

test "Cursor visibility" {
    var cursor = Cursor.init();
    try testing.expect(cursor.isVisible());
    
    cursor.hide();
    try testing.expect(!cursor.isVisible());
    
    cursor.show();
    try testing.expect(cursor.isVisible());
}

test "Cursor shape" {
    var cursor = Cursor.init();
    cursor.setShape(.block);
    try testing.expectEqual(Cursor.Shape.block, cursor.getShape());
    
    cursor.setShape(.underline);
    try testing.expectEqual(Cursor.Shape.underline, cursor.getShape());
    
    cursor.setShape(.bar);
    try testing.expectEqual(Cursor.Shape.bar, cursor.getShape());
}

test "Key event inspection" {
    var key = Key.init();
    key.setCode('a');
    key.setModifiers(.{ .ctrl = true });
    
    try testing.expectEqual('a', key.getCode());
    try testing.expect(key.getModifiers().ctrl);
    try testing.expect(!key.getModifiers().alt);
    try testing.expect(!key.getModifiers().shift);
}

test "Key special keys" {
    var key = Key.init();
    key.setSpecial(.enter);
    
    try testing.expect(key.isSpecial());
    try testing.expectEqual(Key.Special.enter, key.getSpecial());
    
    key.setSpecial(.escape);
    try testing.expectEqual(Key.Special.escape, key.getSpecial());
}

test "Key sequences" {
    var key = Key.init();
    const sequence = "^[OP";
    try key.setSequence(sequence);
    
    const retrieved = key.getSequence();
    try testing.expectEqualStrings(sequence, retrieved);
}

test "Page buffer inspection" {
    const allocator = testing.allocator;
    var page = try Page.init(allocator, 80, 24);
    defer page.deinit();
    
    try testing.expectEqual(@as(usize, 80), page.getWidth());
    try testing.expectEqual(@as(usize, 24), page.getHeight());
    
    const cell = page.getCell(10, 5);
    try testing.expect(cell != null);
    try testing.expectEqual(' ', cell.?.getContent());
}

test "Page content manipulation" {
    const allocator = testing.allocator;
    var page = try Page.init(allocator, 10, 5);
    defer page.deinit();
    
    try page.setContent(2, 1, 'X');
    const cell = page.getCell(2, 1);
    try testing.expect(cell != null);
    try testing.expectEqual('X', cell.?.getContent());
    
    page.clear();
    const cleared_cell = page.getCell(2, 1);
    try testing.expect(cleared_cell != null);
    try testing.expectEqual(' ', cleared_cell.?.getContent());
}

test "Page scrolling" {
    const allocator = testing.allocator;
    var page = try Page.init(allocator, 10, 5);
    defer page.deinit();
    
    for (0..5) |row| {
        for (0..10) |col| {
            try page.setContent(col, row, @intCast('0' + row));
        }
    }
    
    page.scroll(1);
    const top_row = page.getCell(0, 0);
    try testing.expectEqual('1', top_row.?.getContent());
    
    page.scroll(-1);
    const restored_row = page.getCell(0, 0);
    try testing.expectEqual('0', restored_row.?.getContent());
}

test "Termio state inspection" {
    var termio = Termio.init();
    
    termio.setSize(80, 24);
    const size = termio.getSize();
    try testing.expectEqual(@as(usize, 80), size.cols);
    try testing.expectEqual(@as(usize, 24), size.rows);
}

test "Termio mode tracking" {
    var termio = Termio.init();
    
    termio.setMode(.canonical, true);
    try testing.expect(termio.getMode(.canonical));
    
    termio.setMode(.echo, false);
    try testing.expect(!termio.getMode(.echo));
}

test "Termio color support" {
    var termio = Termio.init();
    
    termio.setColorSupport(.true_color);
    try testing.expectEqual(Termio.ColorSupport.true_color, termio.getColorSupport());
    
    termio.setColorSupport(.ansi_256);
    try testing.expectEqual(Termio.ColorSupport.ansi_256, termio.getColorSupport());
}

test "Units conversion" {
    try testing.expectEqual(@as(f32, 1.0), Units.pxToPt(1.0, 96.0));
    try testing.expectEqual(@as(f32, 96.0), Units.ptToPx(1.0, 96.0));
    try testing.expectEqual(@as(f32, 0.75), Units.pxToEm(12.0, 16.0));
    try testing.expectEqual(@as(f32, 21.333336), Units.emToPx(1.3333336, 16.0));
}

test "Units character dimensions" {
    const char_width = Units.charWidth(10);
    const char_height = Units.charHeight(20);
    
    try testing.expect(char_width > 0);
    try testing.expect(char_height > 0);
    try testing.expect(char_height > char_width);
}

test "Inspector cell inspection integration" {
    const allocator = testing.allocator;
    var inspector = try Inspector.init(allocator);
    defer inspector.deinit();
    
    try inspector.startInspection();
    
    const cell = inspector.getCellAt(5, 3);
    try testing.expect(cell != null);
    try testing.expectEqual(' ', cell.?.getContent());
    
    try inspector.setCellContent(5, 3, 'T');
    const updated_cell = inspector.getCellAt(5, 3);
    try testing.expectEqual('T', updated_cell.?.getContent());
    
    try inspector.stopInspection();
}

test "Inspector cursor inspection integration" {
    const allocator = testing.allocator;
    var inspector = try Inspector.init(allocator);
    defer inspector.deinit();
    
    try inspector.startInspection();
    
    try inspector.setCursorPosition(10, 5);
    const cursor = inspector.getCursor();
    try testing.expectEqual(@as(usize, 10), cursor.col);
    try testing.expectEqual(@as(usize, 5), cursor.row);
    
    try inspector.moveCursor(1, 1);
    const moved_cursor = inspector.getCursor();
    try testing.expectEqual(@as(usize, 11), moved_cursor.col);
    try testing.expectEqual(@as(usize, 6), moved_cursor.row);
    
    try inspector.stopInspection();
}

test "Inspector key event capture" {
    const allocator = testing.allocator;
    var inspector = try Inspector.init(allocator);
    defer inspector.deinit();
    
    try inspector.startInspection();
    
    var key = Key.init();
    key.setCode('x');
    key.setModifiers(.{ .ctrl = true });
    
    try inspector.captureKeyEvent(key);
    const captured = inspector.getLastKeyEvent();
    try testing.expect(captured != null);
    try testing.expectEqual('x', captured.?.getCode());
    try testing.expect(captured.?.getModifiers().ctrl);
    
    try inspector.stopInspection();
}

test "Inspector page buffer inspection" {
    const allocator = testing.allocator;
    var inspector = try Inspector.init(allocator);
    defer inspector.deinit();
    
    try inspector.startInspection();
    
    const page = inspector.getPage();
    try testing.expect(page != null);
    try testing.expect(page.?.getWidth() > 0);
    try testing.expect(page.?.getHeight() > 0);
    
    try inspector.setPageContent(0, 0, 'H');
    try inspector.setPageContent(1, 0, 'e');
    try inspector.setPageContent(2, 0, 'l');
    try inspector.setPageContent(3, 0, 'l');
    try inspector.setPageContent(4, 0, 'o');
    
    const hello_cell = page.?.getCell(0, 0);
    try testing.expectEqual('H', hello_cell.?.getContent());
    
    try inspector.stopInspection();
}

test "Inspector termio state inspection" {
    const allocator = testing.allocator;
    var inspector = try Inspector.init(allocator);
    defer inspector.deinit();
    
    try inspector.startInspection();
    
    const termio = inspector.getTermio();
    try testing.expect(termio != null);
    
    const size = termio.?.getSize();
    try testing.expect(size.cols > 0);
    try testing.expect(size.rows > 0);
    
    try inspector.setTermioMode(.canonical, true);
    try testing.expect(termio.?.getMode(.canonical));
    
    try inspector.stopInspection();
}

test "Inspector comprehensive state validation" {
    const allocator = testing.allocator;
    var inspector = try Inspector.init(allocator);
    defer inspector.deinit();
    
    try inspector.startInspection();
    
    try inspector.setPageContent(0, 0, 'T');
    try inspector.setPageContent(1, 0, 'e');
    try inspector.setPageContent(2, 0, 's');
    try inspector.setPageContent(3, 0, 't');
    
    try inspector.setCursorPosition(4, 0);
    
    var key = Key.init();
    key.setCode('\r');
    try inspector.captureKeyEvent(key);
    
    const state = inspector.getState();
    try testing.expect(state != null);
    try testing.expectEqual(@as(usize, 4), state.?.cursor.col);
    try testing.expectEqual(@as(usize, 0), state.?.cursor.row);
    try testing.expectEqual('\r', state.?.last_key.getCode());
    
    const first_cell = state.?.page.getCell(0, 0);
    try testing.expect(first_cell != null);
    try testing.expectEqual('T', first_cell.?.getContent());
    
    try inspector.stopInspection();
}

test "Inspector debugging features" {
    const allocator = testing.allocator;
    var inspector = try Inspector.init(allocator);
    defer inspector.deinit();
    
    try inspector.startInspection();
    
    try inspector.setPageContent(0, 0, 'D');
    try inspector.setPageContent(1, 0, 'e');
    try inspector.setPageContent(2, 0, 'b');
    try inspector.setPageContent(3, 0, 'u');
    try inspector.setPageContent(4, 0, 'g');
    
    const debug_info = inspector.getDebugInfo();
    try testing.expect(debug_info != null);
    try testing.expect(debug_info.?.cell_count > 0);
    try testing.expect(debug_info.?.page_width > 0);
    try testing.expect(debug_info.?.page_height > 0);
    
    const cell_dump = inspector.dumpCells(0, 0, 5, 1);
    try testing.expect(cell_dump.len > 0);
    try testing.expect(std.mem.indexOf(u8, cell_dump, "Debug") != null);
    
    try inspector.stopInspection();
}

test "Inspector error handling" {
    const allocator = testing.allocator;
    var inspector = try Inspector.init(allocator);
    defer inspector.deinit();
    
    try inspector.startInspection();
    
    const invalid_cell = inspector.getCellAt(1000, 1000);
    try testing.expect(invalid_cell == null);
    
    try testing.expectError(error.OutOfBounds, inspector.setCellContent(1000, 1000, 'X'));
    
    try inspector.stopInspection();
}

test "Inspector performance validation" {
    const allocator = testing.allocator;
    var inspector = try Inspector.init(allocator);
    defer inspector.deinit();
    
    try inspector.startInspection();
    
    const start_time = std.time.nanoTimestamp();
    
    for (0..100) |i| {
        try inspector.setCellContent(i % 80, i / 80, @intCast('A' + (i % 26)));
    }
    
    const end_time = std.time.nanoTimestamp();
    const duration = @as(f64, @floatFromInt(end_time - start_time)) / 1_000_000.0;
    
    try testing.expect(duration < 10.0);
    
    try inspector.stopInspection();
}