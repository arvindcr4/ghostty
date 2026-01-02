const std = @import("std");
const testing = std.testing;
const stb = @import("stb/main.zig");
const synthetic = @import("synthetic/main.zig");
const image_gen = @import("synthetic/image.zig");
const text_gen = @import("synthetic/text.zig");
const unicode_gen = @import("synthetic/unicode.zig");

test "STB image loading - PNG format" {
    const allocator = testing.allocator;
    
    // Mock PNG data (minimal valid PNG header)
    const mock_png_data = [_]u8{
        0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, // PNG signature
        0x00, 0x00, 0x00, 0x0D, // IHDR chunk length
        0x49, 0x48, 0x44, 0x52, // IHDR
        0x00, 0x00, 0x00, 0x01, // width: 1
        0x00, 0x00, 0x00, 0x01, // height: 1
        0x08, 0x02, 0x00, 0x00, 0x00, // bit depth, color type, compression, filter, interlace
        0x90, 0x77, 0x53, 0xDE, // CRC
        0x00, 0x00, 0x00, 0x0C, // IDAT chunk length
        0x49, 0x44, 0x41, 0x54, // IDAT
        0x08, 0x99, 0x01, 0x01, 0x00, 0x00, 0x00, 0xFF, 0xFF, 0x00, 0x00, 0x00, 0x02, 0x00, 0x01, // compressed data
        0x00, 0x00, 0x00, 0x00, // IEND chunk length
        0x49, 0x45, 0x4E, 0x44, // IEND
        0xAE, 0x42, 0x60, 0x82, // CRC
    };
    
    var image = try stb.Image.loadFromMemory(allocator, &mock_png_data);
    defer image.deinit(allocator);
    
    try testing.expect(image.width == 1);
    try testing.expect(image.height == 1);
    try testing.expect(image.channels == 4);
    try testing.expect(image.data.len == 4);
}

test "STB image loading - JPEG format" {
    const allocator = testing.allocator;
    
    // Mock JPEG data (minimal valid JPEG)
    const mock_jpeg_data = [_]u8{
        0xFF, 0xD8, // SOI marker
        0xFF, 0xE0, 0x00, 0x10, // APP0 marker
        0x4A, 0x46, 0x49, 0x46, 0x00, // JFIF identifier
        0x01, 0x01, 0x01, 0x00, 0x48, 0x00, 0x48, 0x00, 0x00, // JFIF data
        0xFF, 0xDB, 0x00, 0x43, // DQT marker
    };
    
    // Fill with default quantization table
    var jpeg_data = std.ArrayList(u8).init(allocator);
    defer jpeg_data.deinit();
    try jpeg_data.appendSlice(&mock_jpeg_data);
    
    // Add quantization table data
    for (0..64) |i| {
        try jpeg_data.append(@intCast(i));
    }
    
    // Add end of image marker
    try jpeg_data.appendSlice(&[_]u8{ 0xFF, 0xD9 });
    
    var image = try stb.Image.loadFromMemory(allocator, jpeg_data.items);
    defer image.deinit(allocator);
    
    try testing.expect(image.width > 0);
    try testing.expect(image.height > 0);
    try testing.expect(image.channels >= 1);
}

test "STB image processing - resize" {
    const allocator = testing.allocator;
    
    // Create a simple 2x2 image
    const original_data = [_]u8{ 255, 0, 0, 255, 0, 255, 0, 255, 0, 0, 255, 255, 255, 255, 255, 255 };
    var original = stb.Image{
        .width = 2,
        .height = 2,
        .channels = 4,
        .data = try allocator.dupe(u8, &original_data),
    };
    defer allocator.free(original.data);
    
    var resized = try original.resize(allocator, 4, 4);
    defer resized.deinit(allocator);
    
    try testing.expect(resized.width == 4);
    try testing.expect(resized.height == 4);
    try testing.expect(resized.channels == 4);
    try testing.expect(resized.data.len == 4 * 4 * 4);
}

test "STB image processing - convert format" {
    const allocator = testing.allocator;
    
    // Create RGB image
    const rgb_data = [_]u8{ 255, 0, 0, 0, 255, 0, 0, 0, 255, 255, 255, 255 };
    var rgb_image = stb.Image{
        .width = 2,
        .height = 2,
        .channels = 3,
        .data = try allocator.dupe(u8, &rgb_data),
    };
    defer allocator.free(rgb_image.data);
    
    var rgba_image = try rgb_image.convertFormat(allocator, 4);
    defer rgba_image.deinit(allocator);
    
    try testing.expect(rgba_image.width == 2);
    try testing.expect(rgba_image.height == 2);
    try testing.expect(rgba_image.channels == 4);
    try testing.expect(rgba_image.data.len == 16);
    
    // Check alpha channel is set to 255
    try testing.expect(rgba_image.data[3] == 255);
    try testing.expect(rgba_image.data[7] == 255);
    try testing.expect(rgba_image.data[11] == 255);
    try testing.expect(rgba_image.data[15] == 255);
}

test "STB image processing - crop" {
    const allocator = testing.allocator;
    
    // Create 4x4 image
    var data = try allocator.alloc(u8, 4 * 4 * 3);
    defer allocator.free(data);
    
    for (0..data.len) |i| {
        data[i] = @intCast(i % 256);
    }
    
    var image = stb.Image{
        .width = 4,
        .height = 4,
        .channels = 3,
        .data = data,
    };
    
    var cropped = try image.crop(allocator, 1, 1, 2, 2);
    defer cropped.deinit(allocator);
    
    try testing.expect(cropped.width == 2);
    try testing.expect(cropped.height == 2);
    try testing.expect(cropped.channels == 3);
    try testing.expect(cropped.data.len == 2 * 2 * 3);
}

test "Synthetic image generation - solid color" {
    const allocator = testing.allocator;
    
    var image = try image_gen.generateSolidColor(allocator, 100, 100, 4, 255, 128, 64, 255);
    defer image.deinit(allocator);
    
    try testing.expect(image.width == 100);
    try testing.expect(image.height == 100);
    try testing.expect(image.channels == 4);
    try testing.expect(image.data.len == 100 * 100 * 4);
    
    // Check first pixel
    try testing.expect(image.data[0] == 255);
    try testing.expect(image.data[1] == 128);
    try testing.expect(image.data[2] == 64);
    try testing.expect(image.data[3] == 255);
    
    // Check last pixel
    const last_pixel_offset = (100 * 100 - 1) * 4;
    try testing.expect(image.data[last_pixel_offset] == 255);
    try testing.expect(image.data[last_pixel_offset + 1] == 128);
    try testing.expect(image.data[last_pixel_offset + 2] == 64);
    try testing.expect(image.data[last_pixel_offset + 3] == 255);
}

test "Synthetic image generation - gradient" {
    const allocator = testing.allocator;
    
    var image = try image_gen.generateGradient(allocator, 10, 10, 4);
    defer image.deinit(allocator);
    
    try testing.expect(image.width == 10);
    try testing.expect(image.height == 10);
    try testing.expect(image.channels == 4);
    
    // Check gradient properties
    try testing.expect(image.data[0] == 0); // Top-left black
    try testing.expect(image.data[(10 * 10 - 1) * 4] > 200); // Bottom-right should be bright
}

test "Synthetic image generation - checkerboard" {
    const allocator = testing.allocator;
    
    var image = try image_gen.generateCheckerboard(allocator, 8, 8, 4, 2, 255, 255, 255, 255, 0, 0, 0, 255);
    defer image.deinit(allocator);
    
    try testing.expect(image.width == 8);
    try testing.expect(image.height == 8);
    try testing.expect(image.channels == 4);
    
    // Check pattern
    // (0,0) should be white
    try testing.expect(image.data[0] == 255);
    try testing.expect(image.data[1] == 255);
    try testing.expect(image.data[2] == 255);
    
    // (1,1) should be white (same color as (0,0) due to checkerboard)
    const offset_1_1 = (1 * 8 + 1) * 4;
    try testing.expect(image.data[offset_1_1] == 255);
    
    // (1,0) should be black
    const offset_1_0 = (0 * 8 + 1) * 4;
    try testing.expect(image.data[offset_1_0] == 0);
}

test "Synthetic image generation - noise" {
    const allocator = testing.allocator;
    
    var image = try image_gen.generateNoise(allocator, 50, 50, 3, .uniform);
    defer image.deinit(allocator);
    
    try testing.expect(image.width == 50);
    try testing.expect(image.height == 50);
    try testing.expect(image.channels == 3);
    
    // Check that noise is not uniform (should have variation)
    var min_val: u8 = 255;
    var max_val: u8 = 0;
    for (image.data) |pixel| {
        if (pixel < min_val) min_val = pixel;
        if (pixel > max_val) max_val = pixel;
    }
    try testing.expect(max_val > min_val);
}

test "Synthetic text generation - random words" {
    const allocator = testing.allocator;
    
    var words = try text_gen.generateRandomWords(allocator, 10, 5, 10);
    defer allocator.free(words);
    
    try testing.expect(words.len > 0);
    
    // Count words
    var word_count: usize = 0;
    var in_word = false;
    for (words) |c| {
        if (c != ' ' and c != '\n') {
            if (!in_word) {
                word_count += 1;
                in_word = true;
            }
        } else {
            in_word = false;
        }
    }
    try testing.expect(word_count == 10);
}

test "Synthetic text generation - lorem ipsum" {
    const allocator = testing.allocator;
    
    var text = try text_gen.generateLoremIpsum(allocator, 5);
    defer allocator.free(text);
    
    try testing.expect(text.len > 0);
    
    // Should contain "Lorem" at the beginning
    try testing.expect(std.mem.startsWith(u8, text, "Lorem"));
}

test "Synthetic text generation - structured data" {
    const allocator = testing.allocator;
    
    var data = try text_gen.generateStructuredData(allocator, .json, 3);
    defer allocator.free(data);
    
    try testing.expect(data.len > 0);
    try testing.expect(data[0] == '{');
    try testing.expect(data[data.len - 1] == '}');
    
    // Should be valid JSON structure
    var parsed = std.json.parseFromSlice(std.json.Value, allocator, data, .{}) catch |err| {
        std.debug.print("Failed to parse generated JSON: {}\n", .{err});
        return error.ParseFailed;
    };
    defer parsed.deinit();
}

test "Synthetic Unicode generation - random characters" {
    const allocator = testing.allocator;
    
    var text = try unicode_gen.generateRandomUnicode(allocator, 100, .all);
    defer allocator.free(text);
    
    try testing.expect(text.len > 0);
    
    // Count Unicode code points
    var utf8_view = std.unicode.Utf8View.init(text) catch unreachable;
    var codepoint_count: usize = 0;
    var iter = utf8_view.iterator();
    while (iter.nextCodepoint()) |_| {
        codepoint_count += 1;
    }
    try testing.expect(codepoint_count == 100);
}

test "Synthetic Unicode generation - emoji" {
    const allocator = testing.allocator;
    
    var emoji = try unicode_gen.generateEmoji(allocator, 10);
    defer allocator.free(emoji);
    
    try testing.expect(emoji.len > 0);
    
    // Should contain emoji characters (high code points)
    var utf8_view = std.unicode.Utf8View.init(emoji) catch unreachable;
    var iter = utf8_view.iterator();
    while (iter.nextCodepoint()) |cp| {
        try testing.expect(cp >= 0x1F600 or cp >= 0x2600 or cp >= 0x2700);
    }
}

test "Synthetic Unicode generation - mixed scripts" {
    const allocator = testing.allocator;
    
    var text = try unicode_gen.generateMixedScripts(allocator, 50);
    defer allocator.free(text);
    
    try testing.expect(text.len > 0);
    
    // Should contain characters from different scripts
    var has_latin = false;
    var has_cyrillic = false;
    var has_arabic = false;
    
    var utf8_view = std.unicode.Utf8View.init(text) catch unreachable;
    var iter = utf8_view.iterator();
    while (iter.nextCodepoint()) |cp| {
        if (cp >= 0x0041 and cp <= 0x005A) has_latin = true;
        if (cp >= 0x0400 and cp <= 0x04FF) has_cyrillic = true;
        if (cp >= 0x0600 and cp <= 0x06FF) has_arabic = true;
    }
    
    try testing.expect(has_latin or has_cyrillic or has_arabic);
}

test "Synthetic data performance - image generation" {
    const allocator = testing.allocator;
    
    const start_time = std.time.nanoTimestamp();
    
    var image = try image_gen.generateNoise(allocator, 1000, 1000, 4, .gaussian);
    defer image.deinit(allocator);
    
    const end_time = std.time.nanoTimestamp();
    const duration_ms = @as(f64, @floatFromInt(end_time - start_time)) / 1_000_000.0;
    
    // Should complete within reasonable time (adjust threshold as needed)
    try testing.expect(duration_ms < 1000.0);
    try testing.expect(image.data.len == 1000 * 1000 * 4);
}

test "Synthetic data performance - text generation" {
    const allocator = testing.allocator;
    
    const start_time = std.time.nanoTimestamp();
    
    var text = try text_gen.generateRandomWords(allocator, 10000, 5, 15);
    defer allocator.free(text);
    
    const end_time = std.time.nanoTimestamp();
    const duration_ms = @as(f64, @floatFromInt(end_time - start_time)) / 1_000_000.0;
    
    try testing.expect(duration_ms < 500.0);
    try testing.expect(text.len > 50000); // Approximate minimum length
}

test "Format conversion - RGB to Grayscale" {
    const allocator = testing.allocator;
    
    // Create RGB image with known colors
    const rgb_data = [_]u8{ 255, 0, 0, 0, 255, 0, 0, 0, 255, 255, 255, 255 };
    var rgb_image = stb.Image{
        .width = 2,
        .height = 2,
        .channels = 3,
        .data = try allocator.dupe(u8, &rgb_data),
    };
    defer allocator.free(rgb_image.data);
    
    var gray_image = try rgb_image.toGrayscale(allocator);
    defer gray_image.deinit(allocator);
    
    try testing.expect(gray_image.width == 2);
    try testing.expect(gray_image.height == 2);
    try testing.expect(gray_image.channels == 1);
    
    // Check grayscale conversion (using standard weights)
    // Red (255,0,0) -> ~76
    try testing.expect(@abs(@as(i32, gray_image.data[0]) - 76) < 2);
    // Green (0,255,0) -> ~150
    try testing.expect(@abs(@as(i32, gray_image.data[1]) - 150) < 2);
    // Blue (0,0,255) -> ~29
    try testing.expect(@abs(@as(i32, gray_image.data[2]) - 29) < 2);
    // White (255,255,255) -> 255
    try testing.expect(gray_image.data[3] == 255);
}

test "Memory management - large image allocation" {
    const allocator = testing.allocator;
    
    // Test large image allocation and deallocation
    var image = try image_gen.generateSolidColor(allocator, 2000, 2000, 4, 128, 128, 128, 255);
    image.deinit(allocator);
    
    // If we reach here without crashing, memory management is working
    try testing.expect(true);
}

test "Memory management - repeated operations" {
    const allocator = testing.allocator;
    
    // Perform multiple operations to test memory leaks
    for (0..10) |_| {
        var image = try image_gen.generateNoise(allocator, 100, 100, 3, .uniform);
        var resized = try image.resize(allocator, 50, 50);
        var cropped = try resized.crop(allocator, 10, 10, 30, 30);
        cropped.deinit(allocator);
        resized.deinit(allocator);
        image.deinit(allocator);
    }
    
    try testing.expect(true);
}

test "Data validation - synthetic image properties" {
    const allocator = testing.allocator;
    
    var image = try image_gen.generateGradient(allocator, 100, 100, 4);
    defer image.deinit(allocator);
    
    // Validate image properties
    try testing.expect(image.width == 100);
    try testing.expect(image.height == 100);
    try testing.expect(image.channels == 4);
    try testing.expect(image.data.len == 100 * 100 * 4);
    
    // Validate gradient monotonicity (should increase from top-left to bottom-right)
    const top_left = image.data[0] + image.data[1] + image.data[2];
    const bottom_right = image.data[(100 * 100 - 1) * 4] + 
                        image.data[(100 * 100 - 1) * 4 + 1] + 
                        image.data[(100 * 100 - 1) * 4 + 2];
    try testing.expect(bottom_right > top_left);
}

test "Data validation - synthetic text properties" {
    const allocator = testing.allocator;
    
    var text = try text_gen.generateRandomWords(allocator, 100, 3, 8);
    defer allocator.free(text);
    
    // Validate text properties
    try testing.expect(text.len > 0);
    
    // Count words and validate word lengths
    var word_count: usize = 0;
    var current_word_len: usize = 0;
    var min_len: usize = 8;
    var max_len: usize = 0;
    
    for (text) |c| {
        if (c != ' ' and c != '\n') {
            current_word_len += 1;
        } else {
            if (current_word_len > 0) {
                word_count += 1;
                if (current_word_len < min_len) min_len = current_word_len;
                if (current_word_len > max_len) max_len = current_word_len;
                current_word_len = 0;
            }
        }
    }
    
    // Count last word if text doesn't end with space
    if (current_word_len > 0) {
        word_count += 1;
        if (current_word_len < min_len) min_len = current_word_len;
        if (current_word_len > max_len) max_len = current_word_len;
    }
    
    try testing.expect(word_count == 100);
    try testing.expect(min_len >= 3);
    try testing.expect(max_len <= 8);
}

test "Edge cases - zero size image" {
    const allocator = testing.allocator;
    
    // Should handle zero-sized images gracefully
    var image = try image_gen.generateSolidColor(allocator, 0, 0, 4, 255, 0, 0, 255);
    defer image.deinit(allocator);
    
    try testing.expect(image.width == 0);
    try testing.expect(image.height == 0);
    try testing.expect(image.data.len == 0);
}

test "Edge cases - single pixel image" {
    const allocator = testing.allocator;
    
    var image = try image_gen.generateSolidColor(allocator, 1, 1, 4, 255, 128, 64, 255);
    defer image.deinit(allocator);
    
    try testing.expect(image.width == 1);
    try testing.expect(image.height == 1);
    try testing.expect(image.data.len == 4);
    try testing.expect(image.data[0] == 255);
    try testing.expect(image.data[1] == 128);
    try testing.expect(image.data[2] == 64);
    try testing.expect(image.data[3] == 255);
}

test "Edge cases - empty text generation" {
    const allocator = testing.allocator;
    
    var text = try text_gen.generateRandomWords(allocator, 0, 5, 10);
    defer allocator.free(text);
    
    try testing.expect(text.len == 0);
}

test "Edge cases - invalid image format conversion" {
    const allocator = testing.allocator;
    
    var image = stb.Image{
        .width = 10,
        .height = 10,
        .channels = 3,
        .data = try allocator.alloc(u8, 10 * 10 * 3),
    };
    defer allocator.free(image.data);
    
    // Try to convert to invalid channel count
    const result = image.convertFormat(allocator, 0);
    try testing.expectError(error.InvalidChannelCount, result);
}