const std = @import("std");
const testing = std.testing;
const BitmapAllocator = @import("bitmap_allocator.zig").BitmapAllocator;

test "BitmapAllocator.init" {
    const allocator = std.testing.allocator;
    var bitmap = try BitmapAllocator.init(allocator, 1024);
    defer bitmap.deinit();
    
    try testing.expect(bitmap.total_size == 1024);
    try testing.expect(bitmap.used == 0);
}

test "BitmapAllocator.allocate_single" {
    const allocator = std.testing.allocator;
    var bitmap = try BitmapAllocator.init(allocator, 64);
    defer bitmap.deinit();
    
    const ptr = try bitmap.allocate(8);
    try testing.expect(ptr != null);
    try testing.expect(bitmap.used == 8);
}

test "BitmapAllocator.allocate_multiple" {
    const allocator = std.testing.allocator;
    var bitmap = try BitmapAllocator.init(allocator, 128);
    defer bitmap.deinit();
    
    const ptr1 = try bitmap.allocate(16);
    const ptr2 = try bitmap.allocate(32);
    const ptr3 = try bitmap.allocate(8);
    
    try testing.expect(ptr1 != null);
    try testing.expect(ptr2 != null);
    try testing.expect(ptr3 != null);
    try testing.expect(bitmap.used == 56);
}

test "BitmapAllocator.allocate_zero" {
    const allocator = std.testing.allocator;
    var bitmap = try BitmapAllocator.init(allocator, 64);
    defer bitmap.deinit();
    
    try testing.expectError(error.InvalidSize, bitmap.allocate(0));
}

test "BitmapAllocator.allocate_oversize" {
    const allocator = std.testing.allocator;
    var bitmap = try BitmapAllocator.init(allocator, 64);
    defer bitmap.deinit();
    
    try testing.expectError(error.OutOfMemory, bitmap.allocate(128));
}

test "BitmapAllocator.deallocate" {
    const allocator = std.testing.allocator;
    var bitmap = try BitmapAllocator.init(allocator, 64);
    defer bitmap.deinit();
    
    const ptr = try bitmap.allocate(16);
    bitmap.deallocate(ptr, 16);
    try testing.expect(bitmap.used == 0);
}

test "BitmapAllocator.fragmentation" {
    const allocator = std.testing.allocator;
    var bitmap = try BitmapAllocator.init(allocator, 128);
    defer bitmap.deinit();
    
    const ptr1 = try bitmap.allocate(32);
    const ptr2 = try bitmap.allocate(32);
    const ptr3 = try bitmap.allocate(32);
    
    bitmap.deallocate(ptr2, 32);
    
    const ptr4 = try bitmap.allocate(16);
    try testing.expect(ptr4 == ptr2);
}

test "BitmapAllocator.alignment" {
    const allocator = std.testing.allocator;
    var bitmap = try BitmapAllocator.init(allocator, 64);
    defer bitmap.deinit();
    
    const ptr = try bitmap.allocateAligned(16, 8);
    try testing.expect(@ptrToInt(ptr) % 8 == 0);
}

test "BitmapAllocator.grow" {
    const allocator = std.testing.allocator;
    var bitmap = try BitmapAllocator.init(allocator, 64);
    defer bitmap.deinit();
    
    try bitmap.grow(128);
    try testing.expect(bitmap.total_size == 128);
}

test "BitmapAllocator.reset" {
    const allocator = std.testing.allocator;
    var bitmap = try BitmapAllocator.init(allocator, 64);
    defer bitmap.deinit();
    
    _ = try bitmap.allocate(32);
    bitmap.reset();
    try testing.expect(bitmap.used == 0);
}

const DCS = @import("dcs.zig").DCS;

test "DCS.parse_simple" {
    const input = "\x1bP1;2;3abc\x1b\\";
    var dcs = DCS{};
    try dcs.parse(input);
    
    try testing.expect(dcs.params.len == 3);
    try testing.expect(dcs.params[0] == 1);
    try testing.expect(dcs.params[1] == 2);
    try testing.expect(dcs.params[2] == 3);
    try testing.expect(std.mem.eql(u8, dcs.data, "abc"));
}

test "DCS.parse_no_params" {
    const input = "\x1bPdata\x1b\\";
    var dcs = DCS{};
    try dcs.parse(input);
    
    try testing.expect(dcs.params.len == 0);
    try testing.expect(std.mem.eql(u8, dcs.data, "data"));
}

test "DCS.parse_empty_data" {
    const input = "\x1bP1;2\x1b\\";
    var dcs = DCS{};
    try dcs.parse(input);
    
    try testing.expect(dcs.params.len == 2);
    try testing.expect(dcs.data.len == 0);
}

test "DCS.parse_intermediate" {
    const input = "\x1bP+1;2data\x1b\\";
    var dcs = DCS{};
    try dcs.parse(input);
    
    try testing.expect(dcs.intermediate == '+');
    try testing.expect(dcs.params.len == 2);
}

test "DCS.parse_invalid_sequence" {
    const input = "invalid";
    var dcs = DCS{};
    try testing.expectError(error.InvalidSequence, dcs.parse(input));
}

test "DCS.parse_incomplete" {
    const input = "\x1bP1;2data";
    var dcs = DCS{};
    try testing.expectError(error.IncompleteSequence, dcs.parse(input));
}

test "DCS.parse_large_params" {
    const input = "\x1bP999999;999999data\x1b\\";
    var dcs = DCS{};
    try dcs.parse(input);
    
    try testing.expect(dcs.params[0] == 999999);
    try testing.expect(dcs.params[1] == 999999);
}

test "DCS.parse_binary_data" {
    const input = "\x1bP1;\x00\xff\x1b\\";
    var dcs = DCS{};
    try dcs.parse(input);
    
    try testing.expect(dcs.params.len == 1);
    try testing.expect(dcs.data.len == 2);
    try testing.expect(dcs.data[0] == 0x00);
    try testing.expect(dcs.data[1] == 0xff);
}

test "DCS.format" {
    var dcs = DCS{};
    dcs.params = try std.testing.allocator.alloc(usize, 2);
    defer std.testing.allocator.free(dcs.params);
    dcs.params[0] = 1;
    dcs.params[1] = 2;
    dcs.data = "test";
    
    const result = try dcs.format(std.testing.allocator);
    defer std.testing.allocator.free(result);
    
    try testing.expect(std.mem.eql(u8, result, "\x1bP1;2test\x1b\\"));
}

const DeviceStatus = @import("device_status.zig").DeviceStatus;

test "DeviceStatus.report_cursor_position" {
    var status = DeviceStatus{};
    status.cursor_x = 10;
    status.cursor_y = 5;
    
    const report = try status.reportCursorPosition(std.testing.allocator);
    defer std.testing.allocator.free(report);
    
    try testing.expect(std.mem.eql(u8, report, "\x1b[5;10R"));
}

test "DeviceStatus.report_device_attributes" {
    var status = DeviceStatus{};
    status.device_attrs = .{ .vt100 = true, .vt220 = true };
    
    const report = try status.reportDeviceAttributes(std.testing.allocator);
    defer std.testing.allocator.free(report);
    
    try testing.expect(std.mem.startsWith(u8, report, "\x1b[?"));
    try testing.expect(std.mem.endsWith(u8, report, "c"));
}

test "DeviceStatus.report_terminal_id" {
    var status = DeviceStatus{};
    status.vendor_id = "GHOST";
    status.model_id = "TY";
    
    const report = try status.reportTerminalId(std.testing.allocator);
    defer std.testing.allocator.free(report);
    
    try testing.expect(std.mem.contains(u8, report, "GHOST"));
    try testing.expect(std.mem.contains(u8, report, "TY"));
}

test "DeviceStatus.report_memory_status" {
    var status = DeviceStatus{};
    status.memory_used = 1024;
    status.memory_total = 4096;
    
    const report = try status.reportMemoryStatus(std.testing.allocator);
    defer std.testing.allocator.free(report);
    
    try testing.expect(std.mem.contains(u8, report, "1024"));
    try testing.expect(std.mem.contains(u8, report, "4096"));
}

test "DeviceStatus.update_cursor_position" {
    var status = DeviceStatus{};
    status.updateCursorPosition(15, 8);
    
    try testing.expect(status.cursor_x == 15);
    try testing.expect(status.cursor_y == 8);
}

test "DeviceStatus.set_origin_mode" {
    var status = DeviceStatus{};
    status.setOriginMode(true);
    
    try testing.expect(status.origin_mode == true);
}

test "DeviceStatus.get_screen_size" {
    var status = DeviceStatus{};
    status.screen_width = 80;
    status.screen_height = 24;
    
    const size = status.getScreenSize();
    try testing.expect(size.width == 80);
    try testing.expect(size.height == 24);
}

test "DeviceStatus.report_graphics_mode" {
    var status = DeviceStatus{};
    status.graphics_mode = .{ .sixel = true, .regis = false };
    
    const report = try status.reportGraphicsMode(std.testing.allocator);
    defer std.testing.allocator.free(report);
    
    try testing.expect(std.mem.contains(u8, report, "sixel"));
}

const Formatter = @import("formatter.zig").Formatter;

test "Formatter.format_text" {
    var formatter = Formatter{};
    const input = "Hello, World!";
    const result = try formatter.formatText(std.testing.allocator, input, .{});
    defer std.testing.allocator.free(result);
    
    try testing.expect(std.mem.eql(u8, result, input));
}

test "Formatter.format_with_color" {
    var formatter = Formatter{};
    const input = "Colored text";
    const options = .{ .foreground = .{ .rgb = .{ 255, 0, 0 } } };
    
    const result = try formatter.formatText(std.testing.allocator, input, options);
    defer std.testing.allocator.free(result);
    
    try testing.expect(std.mem.startsWith(u8, result, "\x1b[38;2;255;0;0m"));
    try testing.expect(std.mem.endsWith(u8, result, "\x1b[0m"));
}

test "Formatter.format_with_background" {
    var formatter = Formatter{};
    const input = "Background";
    const options = .{ .background = .{ .rgb = .{ 0, 255, 0 } } };
    
    const result = try formatter.formatText(std.testing.allocator, input, options);
    defer std.testing.allocator.free(result);
    
    try testing.expect(std.mem.startsWith(u8, result, "\x1b[48;2;0;255;0m"));
}

test "Formatter.format_bold" {
    var formatter = Formatter{};
    const input = "Bold text";
    const options = .{ .bold = true };
    
    const result = try formatter.formatText(std.testing.allocator, input, options);
    defer std.testing.allocator.free(result);
    
    try testing.expect(std.mem.contains(u8, result, "\x1b[1m"));
}

test "Formatter.format_italic" {
    var formatter = Formatter{};
    const input = "Italic text";
    const options = .{ .italic = true };
    
    const result = try formatter.formatText(std.testing.allocator, input, options);
    defer std.testing.allocator.free(result);
    
    try testing.expect(std.mem.contains(u8, result, "\x1b[3m"));
}

test "Formatter.format_underline" {
    var formatter = Formatter{};
    const input = "Underlined";
    const options = .{ .underline = true };
    
    const result = try formatter.formatText(std.testing.allocator, input, options);
    defer std.testing.allocator.free(result);
    
    try testing.expect(std.mem.contains(u8, result, "\x1b[4m"));
}

test "Formatter.format_multiple_attributes" {
    var formatter = Formatter{};
    const input = "Multi";
    const options = .{ 
        .bold = true, 
        .italic = true, 
        .foreground = .{ .rgb = .{ 255, 255, 255 } }
    };
    
    const result = try formatter.formatText(std.testing.allocator, input, options);
    defer std.testing.allocator.free(result);
    
    try testing.expect(std.mem.contains(u8, result, "\x1b[1m"));
    try testing.expect(std.mem.contains(u8, result, "\x1b[3m"));
    try testing.expect(std.mem.contains(u8, result, "\x1b[38;2;255;255;255m"));
}

test "Formatter.format_empty_string" {
    var formatter = Formatter{};
    const input = "";
    const result = try formatter.formatText(std.testing.allocator, input, .{});
    defer std.testing.allocator.free(result);
    
    try testing.expect(result.len == 0);
}

test "Formatter.format_unicode" {
    var formatter = Formatter{};
    const input = "🚀 Unicode";
    const result = try formatter.formatText(std.testing.allocator, input, .{});
    defer std.testing.allocator.free(result);
    
    try testing.expect(std.mem.eql(u8, result, input));
}

const HashMap = @import("hash_map.zig").HashMap;

test "HashMap.init" {
    const allocator = std.testing.allocator;
    var map = HashMap.init(allocator);
    defer map.deinit();
    
    try testing.expect(map.count() == 0);
}

test "HashMap.put_get" {
    const allocator = std.testing.allocator;
    var map = HashMap.init(allocator);
    defer map.deinit();
    
    try map.put("key", "value");
    const value = map.get("key");
    
    try testing.expect(value != null);
    try testing.expect(std.mem.eql(u8, value.?, "value"));
}

test "HashMap.put_overwrite" {
    const allocator = std.testing.allocator;
    var map = HashMap.init(allocator);
    defer map.deinit();
    
    try map.put("key", "value1");
    try map.put("key", "value2");
    const value = map.get("key");
    
    try testing.expect(std.mem.eql(u8, value.?, "value2"));
}

test "HashMap.remove" {
    const allocator = std.testing.allocator;
    var map = HashMap.init(allocator);
    defer map.deinit();
    
    try map.put("key", "value");
    map.remove("key");
    
    const value = map.get("key");
    try testing.expect(value == null);
}

test "HashMap_iterator" {
    const allocator = std.testing.allocator;
    var map = HashMap.init(allocator);
    defer map.deinit();
    
    try map.put("a", "1");
    try map.put("b", "2");
    try map.put("c", "3");
    
    var count: usize = 0;
    var iterator = map.iterator();
    while (iterator.next()) |entry| {
        count += 1;
    }
    
    try testing.expect(count == 3);
}

test "HashMap_resize" {
    const allocator = std.testing.allocator;
    var map = HashMap.init(allocator);
    defer map.deinit();
    
    for (0..100) |i| {
        const key = try std.fmt.allocPrint(allocator, "key{d}", .{i});
        defer allocator.free(key);
        try map.put(key, "value");
    }
    
    try testing.expect(map.count() == 100);
}

test "HashMap_collision_handling" {
    const allocator = std.testing.allocator;
    var map = HashMap.init(allocator);
    defer map.deinit();
    
    // Force collisions with similar keys
    try map.put("aaaa", "value1");
    try map.put("aaab", "value2");
    try map.put("aaac", "value3");
    
    try testing.expect(map.count() == 3);
    try testing.expect(std.mem.eql(u8, map.get("aaaa").?, "value1"));
    try testing.expect(std.mem.eql(u8, map.get("aaab").?, "value2"));
    try testing.expect(std.mem.eql(u8, map.get("aaac").?, "value3"));
}

test "HashMap_clear" {
    const allocator = std.testing.allocator;
    var map = HashMap.init(allocator);
    defer map.deinit();
    
    try map.put("key1", "value1");
    try map.put("key2", "value2");
    
    map.clear();
    try testing.expect(map.count() == 0);
}

test "HashMap_capacity" {
    const allocator = std.testing.allocator;
    var map = HashMap.init(allocator);
    defer map.deinit();
    
    const initial_capacity = map.capacity();
    
    try map.put("key", "value");
    const new_capacity = map.capacity();
    
    try testing.expect(new_capacity >= initial_capacity);
}

const Kitty = @import("kitty.zig").Kitty;

test "Kitty.parse_graphics_command" {
    const input = "\x1b_Ga=T,f=32,s=10,v=10;AAAA\x1b\\";
    var kitty = Kitty{};
    
    const cmd = try kitty.parseGraphicsCommand(input);
    defer cmd.deinit();
    
    try testing.expect(cmd.action == .transmit);
    try testing.expect(cmd.format == .png);
    try testing.expect(cmd.width == 10);
    try testing.expect(cmd.height == 10);
}

test "Kitty.parse_keyboard_protocol" {
    const input = "\x1b[?u";
    var kitty = Kitty{};
    
    const proto = try kitty.parseKeyboardProtocol(input);
    try testing.expect(proto.enabled == true);
}

test "Kitty.parse_color_scheme" {
    const input = "\x1b]11;rgb:ff/ff/ff\x1b\\";
    var kitty = Kitty{};
    
    const color = try kitty.parseColorScheme(input);
    try testing.expect(color.r == 255);
    try testing.expect(color.g == 255);
    try testing.expect(color.b == 255);
}

test "Kitty.format_graphics_query" {
    var kitty = Kitty{};
    const query = try kitty.formatGraphicsQuery(std.testing.allocator, .{ .width = 100, .height = 100 });
    defer std.testing.allocator.free(query);
    
    try testing.expect(std.mem.startsWith(u8, query, "\x1b_Gi=1,s=100,v=100"));
    try testing.expect(std.mem.endsWith(u8, query, "\x1b\\"));
}

test "Kitty.parse_notification" {
    const input = "\x1b]99;i=1;d=0;name=title\x1b\\";
    var kitty = Kitty{};
    
    const notif = try kitty.parseNotification(input);
    try testing.expect(notif.id == 1);
    try testing.expect(std.mem.eql(u8, notif.name, "title"));
}

test "Kitty.handle_clipboard" {
    var kitty = Kitty{};
    const data = "clipboard data";
    
    const result = try kitty.handleClipboard(std.testing.allocator, data);
    defer std.testing.allocator.free(result);
    
    try testing.expect(std.mem.contains(u8, result, "\x1b]52"));
}

test "Kitty.parse_window_title" {
    const input = "\x1b]2;New Title\x1b\\";
    var kitty = Kitty{};
    
    const title = try kitty.parseWindowTitle(input);
    try testing.expect(std.mem.eql(u8, title, "New Title"));
}

test "Kitty.format_focus_event" {
    var kitty = Kitty{};
    const event = try kitty.formatFocusEvent(std.testing.allocator, true);
    defer std.testing.allocator.free(event);
    
    try testing.expect(std.mem.eql(u8, event, "\x1b[I"));
}

test "Kitty.parse_hyperlink" {
    const input = "\x1b]8;;http://example.com\x1b\\Link\x1b]8;;\x1b\\";
    var kitty = Kitty{};
    
    const link = try kitty.parseHyperlink(input);
    try testing.expect(std.mem.eql(u8, link.url, "http://example.com"));
    try testing.expect(std.mem.eql(u8, link.text, "Link"));
}

const Terminal = @import("main.zig").Terminal;

test "Terminal.init" {
    const allocator = std.testing.allocator;
    var term = try Terminal.init(allocator, 80, 24);
    defer term.deinit();
    
    try testing.expect(term.width == 80);
    try testing.expect(term.height == 24);
}

test "Terminal.write_text" {
    const allocator = std.testing.allocator;
    var term = try Terminal.init(allocator, 80, 24);
    defer term.deinit();
    
    try term.write("Hello");
    const cursor = term.getCursor();
    try testing.expect(cursor.x == 5);
}

test "Terminal.write_newline" {
    const allocator = std.testing.allocator;
    var term = try Terminal.init(allocator, 80, 24);
    defer term.deinit();
    
    try term.write("Hello\nWorld");
    const cursor = term.getCursor();
    try testing.expect(cursor.y == 1);
    try testing.expect(cursor.x == 5);
}

test "Terminal.scroll_up" {
    const allocator = std.testing.allocator;
    var term = try Terminal.init(allocator, 80, 24);
    defer term.deinit();
    
    // Fill screen
    for (0..24) |_| {
        try term.write("Line\n");
    }
    
    try term.scrollUp(1);
    const cursor = term.getCursor();
    try testing.expect(cursor.y == 23);
}

test "Terminal.clear_screen" {
    const allocator = std.testing.allocator;
    var term = try Terminal.init(allocator, 80, 24);
    defer term.deinit();
    
    try term.write("Test");
    term.clearScreen();
    
    const cursor = term.getCursor();
    try testing.expect(cursor.x == 0);
    try testing.expect(cursor.y == 0);
}

test "Terminal.move_cursor" {
    const allocator = std.testing.allocator;
    var term = try Terminal.init(allocator, 80, 24);
    defer term.deinit();
    
    try term.moveCursor(10, 5);
    const cursor = term.getCursor();
    try testing.expect(cursor.x == 10);
    try testing.expect(cursor.y == 5);
}

test "Terminal.save_restore_cursor" {
    const allocator = std.testing.allocator;
    var term = try Terminal.init(allocator, 80, 24);
    defer term.deinit();
    
    try term.moveCursor(10, 5);
    term.saveCursor();
    
    try term.moveCursor(0, 0);
    term.restoreCursor();
    
    const cursor = term.getCursor();
    try testing.expect(cursor.x == 10);
    try testing.expect(cursor.y == 5);
}

test "Terminal.set_tab" {
    const allocator = std.testing.allocator;
    var term = try Terminal.init(allocator, 80, 24);
    defer term.deinit();
    
    term.setTab();
    try testing.expect(term.isTabStop(8));
}

test "Terminal.clear_tab" {
    const allocator = std.testing.allocator;
    var term = try Terminal.init(allocator, 80, 24);
    defer term.deinit();
    
    term.setTab();
    term.clearTab(8);
    try testing.expect(!term.isTabStop(8));
}

test "Terminal.resize" {
    const allocator = std.testing.allocator;
    var term = try Terminal.init(allocator, 80, 24);
    defer term.deinit();
    
    try term.resize(100, 30);
    try testing.expect(term.width == 100);
    try testing.expect(term.height == 30);
}

const MouseShape = @import("mouse_shape.zig").MouseShape;

test "MouseShape.set_default" {
    var shape = MouseShape{};
    shape.setDefault();
    
    try testing.expect(shape.shape == .default);
}

test "MouseShape.set_pointer" {
    var shape = MouseShape{};
    shape.setPointer();
    
    try testing.expect(shape.shape == .pointer);
}

test "MouseShape.set_crosshair" {
    var shape = MouseShape{};
    shape.setCrosshair();
    
    try testing.expect(shape.shape == .crosshair);
}

test "MouseShape.set_text" {
    var shape = MouseShape{};
    shape.setText();
    
    try testing.expect(shape.shape == .text);
}

test "MouseShape.set_wait" {
    var shape = MouseShape{};
    shape.setWait();
    
    try testing.expect(shape.shape == .wait);
}

test "MouseShape.set_help" {
    var shape = MouseShape{};
    shape.setHelp();
    
    try testing.expect(shape.shape == .help);
}

test "MouseShape.set_progress" {
    var shape = MouseShape{};
    shape.setProgress();
    
    try testing.expect(shape.shape == .progress);
}

test "MouseShape.set_not_allowed" {
    var shape = MouseShape{};
    shape.setNotAllowed();
    
    try testing.expect(shape.shape == .not_allowed);
}

test "MouseShape.set_custom" {
    var shape = MouseShape{};
    shape.setCustom("custom_shape");
    
    try testing.expect(shape.shape == .custom);
    try testing.expect(std.mem.eql(u8, shape.custom_name, "custom_shape"));
}

test "MouseShape.format_sequence" {
    var shape = MouseShape{};
    shape.setPointer();
    
    const seq = try shape.formatSequence(std.testing.allocator);
    defer std.testing.allocator.free(seq);
    
    try testing.expect(std.mem.startsWith(u8, seq, "\x1b]22;"));
}

test "MouseShape.parse_sequence" {
    const input = "\x1b]22;pointer\x1b\\";
    var shape = MouseShape{};
    
    try shape.parseSequence(input);
    try testing.expect(shape.shape == .pointer);
}

test "MouseShape.reset" {
    var shape = MouseShape{};
    shape.setPointer();
    shape.reset();
    
    try testing.expect(shape.shape == .default);
}

const Page = @import("page.zig").Page;

test "Page.init" {
    const allocator = std.testing.allocator;
    var page = try Page.init(allocator, 80, 24);
    defer page.deinit();
    
    try testing.expect(page.width == 80);
    try testing.expect(page.height == 24);
    try testing.expect(page.lines.len == 24);
}

test "Page.write_char" {
    const allocator = std.testing.allocator;
    var page = try Page.init(allocator, 80, 24);
    defer page.deinit();
    
    try page.writeChar('A', 0, 0);
    const cell = page.getCell(0, 0);
    
    try testing.expect(cell.char == 'A');
}

test "Page.write_string" {
    const allocator = std.testing.allocator;
    var page = try Page.init(allocator, 80, 24);
    defer page.deinit();
    
    try page.writeString("Hello", 0, 0);
    
    try testing.expect(page.getCell(0, 0).char == 'H');
    try testing.expect(page.getCell(1, 0).char == 'e');
    try testing.expect(page.getCell(2, 0).char == 'l');
    try testing.expect(page.getCell(3, 0).char == 'l');
    try testing.expect(page.getCell(4, 0).char == 'o');
}

test "Page.clear_line" {
    const allocator = std.testing.allocator;
    var page = try Page.init(allocator, 80, 24);
    defer page.deinit();
    
    try page.writeString("Test", 0, 0);
    page.clearLine(0);
    
    for (0..80) |x| {
        try testing.expect(page.getCell(x, 0).char == ' ');
    }
}

test "Page.clear_area" {
    const allocator = std.testing.allocator;
    var page = try Page.init(allocator, 80, 24);
    defer page.deinit();
    
    try page.writeString("Test", 0, 0);
    page.clearArea(0, 0, 4, 1);
    
    for (0..4) |x| {
        try testing.expect(page.getCell(x, 0).char == ' ');
    }
}

test "Page.scroll_up" {
    const allocator = std.testing.allocator;
    var page = try Page.init(allocator, 80, 24);
    defer page.deinit();
    
    try page.writeString("Line1", 0, 0);
    try page.writeString("Line2", 0, 1);
    
    page.scrollUp(1);
    
    try testing.expect(page.getCell(0, 0).char == 'L');
    try testing.expect(page.getCell(0, 1).char == 'i');
    try testing.expect(page.getCell(0, 2).char == 'n');
    try testing.expect(page.getCell(0, 3).char == 'e');
    try testing.expect(page.getCell(0, 4).char == '2');
}

test "Page.scroll_down" {
    const allocator = std.testing.allocator;
    var page = try Page.init(allocator, 80, 24);
    defer page.deinit();
    
    try page.writeString("Line1", 0, 0);
    try page.writeString("Line2", 0, 1);
    
    page.scrollDown(1);
    
    try testing.expect(page.getCell(0, 0).char == ' ');
    try testing.expect(page.getCell(0, 1).char == 'L');
    try testing.expect(page.getCell(0, 2).char == 'i');
    try testing.expect(page.getCell(0, 3).char == 'n');
    try testing.expect(page.getCell(0, 4).char == 'e');
    try testing.expect(page.getCell(0, 5).char == '1');
}

test "Page.insert_line" {
    const allocator = std.testing.allocator;
    var page = try Page.init(allocator, 80, 24);
    defer page.deinit();
    
    try page.writeString("Line1", 0, 0);
    try page.writeString("Line2", 0, 1);
    
    page.insertLine(1);
    
    try testing.expect(page.getCell(0, 0).char == 'L');
    try testing.expect(page.getCell(0, 1).char == ' ');
    try testing.expect(page.getCell(0, 2).char == 'L');
}

test "Page.delete_line" {
    const allocator = std.testing.allocator;
    var page = try Page.init(allocator, 80, 24);
    defer page.deinit();
    
    try page.writeString("Line1", 0, 0);
    try page.writeString("Line2", 0, 1);
    try page.writeString("Line3", 0, 2);
    
    page.deleteLine(1);
    
    try testing.expect(page.getCell(0, 0).char == 'L');
    try testing.expect(page.getCell(0, 1).char == 'L');
    try testing.expect(page.getCell(0, 2).char == ' ');
}

test "Page.resize" {
    const allocator = std.testing.allocator;
    var page = try Page.init(allocator, 80, 24);
    defer page.deinit();
    
    try page.resize(100, 30);
    
    try testing.expect(page.width == 100);
    try testing.expect(page.height == 30);
    try testing.expect(page.lines.len == 30);
}

test "Page.copy_area" {
    const allocator = std.testing.allocator;
    var page = try Page.init(allocator, 80, 24);
    defer page.deinit();
    
    try page.writeString("Source", 0, 0);
    page.copyArea(0, 0, 6, 1, 10, 0);
    
    try testing.expect(page.getCell(10, 0).char == 'S');
    try testing.expect(page.getCell(11, 0).char == 'o');
    try testing.expect(page.getCell(12, 0).char == 'u');
    try testing.expect(page.getCell(13, 0).char == 'r');
    try testing.expect(page.getCell(14, 0).char == 'c');
    try testing.expect(page.getCell(15, 0).char == 'e');
}

test "Page.fill_area" {
    const allocator = std.testing.allocator;
    var page = try Page.init(allocator, 80, 24);
    defer page.deinit();
    
    page.fillArea('X', 0, 0, 5, 2);
    
    for (0..5) |x| {
        for (0..2) |y| {
            try testing.expect(page.getCell(x, y).char == 'X');
        }
    }
}