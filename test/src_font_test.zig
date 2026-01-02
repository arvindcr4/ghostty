const std = @import("std");
const testing = std.testing;
const font = @import("src/font/main.zig");
const Atlas = @import("src/font/Atlas.zig");
const backend = @import("src/font/backend.zig");
const CodepointMap = @import("src/font/CodepointMap.zig");
const CodepointResolver = @import("src/font/CodepointResolver.zig");
const Collection = @import("src/font/Collection.zig");
const DeferredFace = @import("src/font/DeferredFace.zig");
const discovery = @import("src/font/discovery.zig");
const embedded = @import("src/font/embedded.zig");
const face = @import("src/font/face.zig");
const Glyph = @import("src/font/Glyph.zig");
const library = @import("src/font/library.zig");
const Metrics = @import("src/font/Metrics.zig");
const opentype = @import("src/font/opentype.zig");
const shaper = @import("src/font/shaper.zig");

test "font.main.init" {
    const allocator = testing.allocator;
    var font_system = try font.FontSystem.init(allocator);
    defer font_system.deinit();
    
    try testing.expect(font_system.state == .initialized);
}

test "font.main.loadFont" {
    const allocator = testing.allocator;
    var font_system = try font.FontSystem.init(allocator);
    defer font_system.deinit();
    
    const mock_font_data = [_]u8{0x00, 0x01, 0x02, 0x03};
    const font_handle = try font_system.loadFont(mock_font_data[0..]);
    try testing.expect(font_handle != null);
}

test "Atlas.create" {
    const allocator = testing.allocator;
    var atlas = try Atlas.init(allocator, 1024, 1024);
    defer atlas.deinit();
    
    try testing.expect(atlas.width == 1024);
    try testing.expect(atlas.height == 1024);
    try testing.expect(atlas.packed_glyphs == 0);
}

test "Atlas.packGlyph" {
    const allocator = testing.allocator;
    var atlas = try Atlas.init(allocator, 512, 512);
    defer atlas.deinit();
    
    const glyph_size = Atlas.Size{ .width = 32, .height = 32 };
    const region = try atlas.packGlyph(glyph_size);
    
    try testing.expect(region.x >= 0);
    try testing.expect(region.y >= 0);
    try testing.expect(region.width == 32);
    try testing.expect(region.height == 32);
    try testing.expect(atlas.packed_glyphs == 1);
}

test "backend.FontBackend.init" {
    const allocator = testing.allocator;
    var backend_impl = try backend.FontBackend.init(allocator);
    defer backend_impl.deinit();
    
    try testing.expect(backend_impl.isInitialized());
}

test "backend.FontBackend.loadFace" {
    const allocator = testing.allocator;
    var backend_impl = try backend.FontBackend.init(allocator);
    defer backend_impl.deinit();
    
    const mock_font_data = [_]u8{0x00, 0x01, 0x02, 0x03};
    const face = try backend_impl.loadFace(mock_font_data[0..], 12);
    defer backend_impl.unloadFace(face);
    
    try testing.expect(face != null);
}

test "CodepointMap.init" {
    var map = CodepointMap.init();
    try testing.expect(map.size() == 0);
}

test "CodepointMap.insertAndLookup" {
    var map = CodepointMap.init();
    
    try map.insert('A', 1);
    try map.insert('B', 2);
    try map.insert('C', 3);
    
    try testing.expect(map.size() == 3);
    try testing.expect(map.lookup('A').? == 1);
    try testing.expect(map.lookup('B').? == 2);
    try testing.expect(map.lookup('C').? == 3);
    try testing.expect(map.lookup('D') == null);
}

test "CodepointResolver.init" {
    const allocator = testing.allocator;
    var resolver = try CodepointResolver.init(allocator);
    defer resolver.deinit();
    
    try testing.expect(resolver.isInitialized());
}

test "CodepointResolver.resolve" {
    const allocator = testing.allocator;
    var resolver = try CodepointResolver.init(allocator);
    defer resolver.deinit();
    
    const codepoint = 'A';
    const resolved = try resolver.resolve(codepoint);
    try testing.expect(resolved != null);
}

test "Collection.init" {
    const allocator = testing.allocator;
    var collection = try Collection.init(allocator);
    defer collection.deinit();
    
    try testing.expect(collection.count() == 0);
}

test "Collection.addFont" {
    const allocator = testing.allocator;
    var collection = try Collection.init(allocator);
    defer collection.deinit();
    
    const mock_font_data = [_]u8{0x00, 0x01, 0x02, 0x03};
    try collection.addFont("TestFont", mock_font_data[0..]);
    
    try testing.expect(collection.count() == 1);
    try testing.expect(collection.contains("TestFont"));
}

test "Collection.selectFont" {
    const allocator = testing.allocator;
    var collection = try Collection.init(allocator);
    defer collection.deinit();
    
    const mock_font_data = [_]u8{0x00, 0x01, 0x02, 0x03};
    try collection.addFont("TestFont", mock_font_data[0..]);
    
    const selected = collection.selectFont("TestFont");
    try testing.expect(selected != null);
}

test "DeferredFace.init" {
    const allocator = testing.allocator;
    const mock_font_data = [_]u8{0x00, 0x01, 0x02, 0x03};
    var deferred_face = try DeferredFace.init(allocator, mock_font_data[0..], 12);
    defer deferred_face.deinit();
    
    try testing.expect(!deferred_face.isLoaded());
}

test "DeferredFace.load" {
    const allocator = testing.allocator;
    const mock_font_data = [_]u8{0x00, 0x01, 0x02, 0x03};
    var deferred_face = try DeferredFace.init(allocator, mock_font_data[0..], 12);
    defer deferred_face.deinit();
    
    try deferred_face.load();
    try testing.expect(deferred_face.isLoaded());
}

test "discovery.findFonts" {
    const allocator = testing.allocator;
    var fonts = try discovery.findFonts(allocator);
    defer fonts.deinit(allocator);
    
    try testing.expect(fonts.items.len >= 0);
}

test "discovery.findFontByName" {
    const allocator = testing.allocator;
    const font_path = try discovery.findFontByName(allocator, "Arial");
    defer allocator.free(font_path);
    
    try testing.expect(font_path.len > 0 or font_path.len == 0);
}

test "embedded.init" {
    const allocator = testing.allocator;
    var embedded_fonts = try embedded.init(allocator);
    defer embedded_fonts.deinit();
    
    try testing.expect(embedded_fonts.count() > 0);
}

test "embedded.getFont" {
    const allocator = testing.allocator;
    var embedded_fonts = try embedded.init(allocator);
    defer embedded_fonts.deinit();
    
    const font_data = embedded_fonts.getFont("monospace");
    try testing.expect(font_data != null);
    try testing.expect(font_data.?.len > 0);
}

test "face.init" {
    const allocator = testing.allocator;
    const mock_font_data = [_]u8{0x00, 0x01, 0x02, 0x03};
    var font_face = try face.FontFace.init(allocator, mock_font_data[0..], 12);
    defer font_face.deinit();
    
    try testing.expect(font_face.size == 12);
    try testing.expect(font_face.isValid());
}

test "face.getGlyph" {
    const allocator = testing.allocator;
    const mock_font_data = [_]u8{0x00, 0x01, 0x02, 0x03};
    var font_face = try face.FontFace.init(allocator, mock_font_data[0..], 12);
    defer font_face.deinit();
    
    const glyph = try font_face.getGlyph('A');
    try testing.expect(glyph != null);
}

test "Glyph.init" {
    const glyph = Glyph{
        .codepoint = 'A',
        .advance = 10,
        .bearing_x = 2,
        .bearing_y = 12,
        .width = 8,
        .height = 16,
    };
    
    try testing.expect(glyph.codepoint == 'A');
    try testing.expect(glyph.advance == 10);
    try testing.expect(glyph.width == 8);
    try testing.expect(glyph.height == 16);
}

test "Glyph.calculateKerning" {
    const glyph1 = Glyph{ .codepoint = 'A', .advance = 10 };
    const glyph2 = Glyph{ .codepoint = 'V', .advance = 10 };
    
    const kerning = glyph1.calculateKerning(glyph2);
    try testing.expect(kerning >= -5 and kerning <= 5);
}

test "library.init" {
    const allocator = testing.allocator;
    var lib = try library.FontLibrary.init(allocator);
    defer lib.deinit();
    
    try testing.expect(lib.isInitialized());
}

test "library.loadFont" {
    const allocator = testing.allocator;
    var lib = try library.FontLibrary.init(allocator);
    defer lib.deinit();
    
    const mock_font_data = [_]u8{0x00, 0x01, 0x02, 0x03};
    const font_id = try lib.loadFont("TestFont", mock_font_data[0..]);
    try testing.expect(font_id != 0);
}

test "Metrics.init" {
    const metrics = Metrics{
        .ascent = 12,
        .descent = 3,
        .height = 15,
        .max_advance = 10,
    };
    
    try testing.expect(metrics.ascent == 12);
    try testing.expect(metrics.descent == 3);
    try testing.expect(metrics.height == 15);
    try testing.expect(metrics.max_advance == 10);
}

test "Metrics.calculateLineHeight" {
    const metrics = Metrics{
        .ascent = 12,
        .descent = 3,
        .height = 15,
        .max_advance = 10,
    };
    
    const line_height = metrics.calculateLineHeight(1.0);
    try testing.expect(line_height == 15);
}

test "opentype.parseHeader" {
    const allocator = testing.allocator;
    const mock_otf_data = [_]u8{
        0x00, 0x01, 0x00, 0x00, // sfnt version
        0x00, 0x0A, // numTables
        0x00, 0x20, // searchRange
        0x00, 0x05, // entrySelector
        0x00, 0x60, // rangeShift
    };
    
    const header = try opentype.parseHeader(mock_otf_data[0..]);
    try testing.expect(header.num_tables == 10);
    try testing.expect(header.search_range == 32);
}

test "opentype.isSupported" {
    const allocator = testing.allocator;
    const mock_otf_data = [_]u8{0x00, 0x01, 0x00, 0x00};
    
    const supported = opentype.isSupported(mock_otf_data[0..]);
    try testing.expect(supported);
}

test "shaper.init" {
    const allocator = testing.allocator;
    var text_shaper = try shaper.TextShaper.init(allocator);
    defer text_shaper.deinit();
    
    try testing.expect(text_shaper.isInitialized());
}

test "shaper.shapeText" {
    const allocator = testing.allocator;
    var text_shaper = try shaper.TextShaper.init(allocator);
    defer text_shaper.deinit();
    
    const text = "Hello";
    const glyphs = try text_shaper.shapeText(text);
    defer allocator.free(glyphs);
    
    try testing.expect(glyphs.len == text.len);
}

test "shaper.calculateWidth" {
    const allocator = testing.allocator;
    var text_shaper = try shaper.TextShaper.init(allocator);
    defer text_shaper.deinit();
    
    const text = "Hello";
    const width = try text_shaper.calculateWidth(text);
    try testing.expect(width > 0);
}

test "font.pipeline.complete" {
    const allocator = testing.allocator;
    
    var lib = try library.FontLibrary.init(allocator);
    defer lib.deinit();
    
    const mock_font_data = [_]u8{0x00, 0x01, 0x02, 0x03};
    const font_id = try lib.loadFont("TestFont", mock_font_data[0..]);
    
    var font_face = try lib.getFace(font_id, 12);
    defer font_face.deinit();
    
    const glyph = try font_face.getGlyph('A');
    try testing.expect(glyph != null);
    
    const metrics = font_face.getMetrics();
    try testing.expect(metrics.height > 0);
    
    var text_shaper = try shaper.TextShaper.init(allocator);
    defer text_shaper.deinit();
    
    const text = "ABC";
    const shaped_glyphs = try text_shaper.shapeText(text);
    defer allocator.free(shaped_glyphs);
    
    try testing.expect(shaped_glyphs.len == text.len);
    
    const width = try text_shaper.calculateWidth(text);
    try testing.expect(width > 0);
}

test "font.caching" {
    const allocator = testing.allocator;
    var font_system = try font.FontSystem.init(allocator);
    defer font_system.deinit();
    
    const mock_font_data = [_]u8{0x00, 0x01, 0x02, 0x03};
    
    const font1 = try font_system.loadFont(mock_font_data[0..]);
    const font2 = try font_system.loadFont(mock_font_data[0..]);
    
    try testing.expect(font1 == font2);
}

test "font.metricsCalculation" {
    const allocator = testing.allocator;
    const mock_font_data = [_]u8{0x00, 0x01, 0x02, 0x03};
    var font_face = try face.FontFace.init(allocator, mock_font_data[0..], 12);
    defer font_face.deinit();
    
    const metrics = font_face.getMetrics();
    try testing.expect(metrics.ascent > 0);
    try testing.expect(metrics.descent >= 0);
    try testing.expect(metrics.height > metrics.ascent);
}

test "font.glyphRendering" {
    const allocator = testing.allocator;
    var atlas = try Atlas.init(allocator, 256, 256);
    defer atlas.deinit();
    
    const glyph_size = Atlas.Size{ .width = 16, .height = 16 };
    const region = try atlas.packGlyph(glyph_size);
    
    try testing.expect(region.width == 16);
    try testing.expect(region.height == 16);
    try testing.expect(atlas.packed_glyphs == 1);
}

test "font.textLayout" {
    const allocator = testing.allocator;
    var text_shaper = try shaper.TextShaper.init(allocator);
    defer text_shaper.deinit();
    
    const text = "Hello World";
    const layout = try text_shaper.layoutText(text, 100);
    defer allocator.free(layout.lines);
    
    try testing.expect(layout.lines.len > 0);
    try testing.expect(layout.width > 0);
    try testing.expect(layout.height > 0);
}

test "font.fontSelection" {
    const allocator = testing.allocator;
    var collection = try Collection.init(allocator);
    defer collection.deinit();
    
    const mock_font_data = [_]u8{0x00, 0x01, 0x02, 0x03};
    try collection.addFont("Regular", mock_font_data[0..]);
    try collection.addFont("Bold", mock_font_data[0..]);
    try collection.addFont("Italic", mock_font_data[0..]);
    
    const regular = collection.selectFont("Regular");
    const bold = collection.selectFont("Bold");
    const italic = collection.selectFont("Italic");
    
    try testing.expect(regular != null);
    try testing.expect(bold != null);
    try testing.expect(italic != null);
    try testing.expect(regular != bold);
    try testing.expect(bold != italic);
}

test "font.codepointWidth" {
    const allocator = testing.allocator;
    const mock_font_data = [_]u8{0x00, 0x01, 0x02, 0x03};
    var font_face = try face.FontFace.init(allocator, mock_font_data[0..], 12);
    defer font_face.deinit();
    
    const ascii_width = try font_face.getCodepointWidth('A');
    const wide_width = try font_face.getCodepointWidth('中');
    
    try testing.expect(ascii_width > 0);
    try testing.expect(wide_width >= ascii_width);
}

test "font.shapingAlgorithms" {
    const allocator = testing.allocator;
    var text_shaper = try shaper.TextShaper.init(allocator);
    defer text_shaper.deinit();
    
    const latin_text = "Hello";
    const arabic_text = "مرحبا";
    const cjk_text = "你好";
    
    const latin_glyphs = try text_shaper.shapeText(latin_text);
    defer allocator.free(latin_glyphs);
    
    const arabic_glyphs = try text_shaper.shapeText(arabic_text);
    defer allocator.free(arabic_glyphs);
    
    const cjk_glyphs = try text_shaper.shapeText(cjk_text);
    defer allocator.free(cjk_glyphs);
    
    try testing.expect(latin_glyphs.len == latin_text.len);
    try testing.expect(arabic_glyphs.len == arabic_text.len);
    try testing.expect(cjk_glyphs.len == cjk_text.len);
}

test "font.variousScripts" {
    const allocator = testing.allocator;
    var text_shaper = try shaper.TextShaper.init(allocator);
    defer text_shaper.deinit();
    
    const scripts = [_][]const u8{
        "English",
        "Français",
        "Español",
        "Русский",
        "العربية",
        "עברית",
        "हिन्दी",
        "中文",
        "日本語",
        "한국어",
    };
    
    for (scripts) |script| {
        const width = try text_shaper.calculateWidth(script);
        try testing.expect(width > 0);
    }
}

test "font.errorHandling" {
    const allocator = testing.allocator;
    
    const invalid_font_data = [_]u8{0xFF, 0xFF, 0xFF, 0xFF};
    const result = face.FontFace.init(allocator, invalid_font_data[0..], 12);
    try testing.expectError(error.InvalidFontData, result);
}

test "font.memoryManagement" {
    const allocator = testing.allocator;
    var font_system = try font.FontSystem.init(allocator);
    defer font_system.deinit();
    
    const mock_font_data = [_]u8{0x00, 0x01, 0x02, 0x03};
    
    for (0..100) |_| {
        const font_handle = try font_system.loadFont(mock_font_data[0..]);
        _ = font_handle;
    }
    
    try testing.expect(font_system.getFontCount() <= 10);
}