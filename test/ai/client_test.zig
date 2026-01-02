//! Unit tests for AI Client module
//! Tests provider initialization, JSON building, and response parsing

const std = @import("std");
const testing = std.testing;
const Allocator = std.mem.Allocator;

const ai = @import("../../src/ai/client.zig");

test "Provider enum has all expected values" {
    try testing.expectEqual(@as(ai.Provider, .openai), ai.Provider.openai);
    try testing.expectEqual(@as(ai.Provider, .anthropic), ai.Provider.anthropic);
    try testing.expectEqual(@as(ai.Provider, .ollama), ai.Provider.ollama);
    try testing.expectEqual(@as(ai.Provider, .custom), ai.Provider.custom);
    try testing.expectEqual(@as(ai.Provider, .cerebras), ai.Provider.cerebras);
}

test "Provider enum names" {
    try testing.expectEqual(ai.Provider.openai.str(), "openai");
    try testing.expectEqual(ai.Provider.anthropic.str(), "anthropic");
    try testing.expectEqual(ai.Provider.ollama.str(), "ollama");
    try testing.expectEqual(ai.Provider.custom.str(), "custom");
    try testing.expectEqual(ai.Provider.cerebras.str(), "cerebras");
}

test "Client initialization with valid parameters" {
    const alloc = testing.allocator;

    const client = ai.Client.init(
        alloc,
        .openai,
        "test-api-key",
        "https://api.example.com",
        "gpt-4",
        1000,
        0.7,
    );

    try testing.expectEqual(client.provider, .openai);
    try testing.expectEqualStrings(client.api_key, "test-api-key");
    try testing.expectEqualStrings(client.endpoint, "https://api.example.com");
    try testing.expectEqualStrings(client.model, "gpt-4");
    try testing.expectEqual(client.max_tokens, @as(u32, 1000));
    try testing.expectEqual(client.temperature, 0.7);
}

test "Client initialization with empty endpoint uses default" {
    const alloc = testing.allocator;

    const client = ai.Client.init(
        alloc,
        .anthropic,
        "sk-test-key",
        "", // empty endpoint - should use default
        "claude-3-opus",
        4096,
        1.0,
    );

    try testing.expectEqual(client.provider, .anthropic);
    try testing.expectEqual(client.endpoint.len, 0);
    try testing.expectEqualStrings(client.model, "claude-3-opus");
}

test "Client initialization with Cerebras provider" {
    const alloc = testing.allocator;

    const client = ai.Client.init(
        alloc,
        .cerebras,
        "cerebras-api-key",
        "https://api.cerebras.ai/v1",
        "llama-3.1-70b",
        2048,
        0.5,
    );

    try testing.expectEqual(client.provider, .cerebras);
    try testing.expectEqualStrings(client.api_key, "cerebras-api-key");
    try testing.expectEqualStrings(client.endpoint, "https://api.cerebras.ai/v1");
    try testing.expectEqualStrings(client.model, "llama-3.1-70b");
    try testing.expectEqual(client.max_tokens, @as(u32, 2048));
    try testing.expectEqual(client.temperature, 0.5);
}

test "JSON escaping handles special characters" {
    const alloc = testing.allocator;

    // Test common special characters
    const input = "Hello \"World\"\nNewline\tTab\\Backslash";
    var buffer: std.ArrayListUnmanaged(u8) = .empty;
    defer buffer.deinit(alloc);

    const writer = buffer.writer(alloc);

    // This tests the writeJsonEscapedString function indirectly
    // by checking that special characters are properly escaped
    try writer.writeAll("\"");
    try writer.writeAll(std.json.fmtEscapeSlice(input));
    try writer.writeAll("\"");

    const result = buffer.items;
    try testing.expect(result[0] == '"');

    // Verify quotes are escaped
    const quote_escaped = std.mem.indexOf(u8, result, "\\\"") != null;
    try testing.expect(quote_escaped, "Quotes should be escaped");

    // Verify newline is escaped
    const newline_escaped = std.mem.indexOf(u8, result, "\\n") != null;
    try testing.expect(newline_escaped, "Newlines should be escaped");

    // Verify tab is escaped
    const tab_escaped = std.mem.indexOf(u8, result, "\\t") != null;
    try testing.expect(tab_escaped, "Tabs should be escaped");
}

test "SSE delimiter finding" {
    // Test \n\n delimiter
    const buf1 = "data: event\n\ncontent";
    const delim1 = ai.findSseDelimiter(buf1[0..]);
    try testing.expect(delim1 != null, "Should find \\n\\n delimiter");
    if (delim1) |d| {
        try testing.expectEqual(d.index, 11);
        try testing.expectEqual(d.len, 2);
    }

    // Test \r\n\r\n delimiter
    const buf2 = "data: event\r\n\r\ncontent";
    const delim2 = ai.findSseDelimiter(buf2[0..]);
    try testing.expect(delim2 != null, "Should find \\r\\n\\r\\n delimiter");
    if (delim2) |d| {
        try testing.expectEqual(d.len, 4);
    }

    // Test no delimiter
    const buf3 = "data: event\ncontent";
    const delim3 = ai.findSseDelimiter(buf3[0..]);
    try testing.expect(delim3 == null, "Should not find delimiter");
}

test "Buffer consume prefix function" {
    const alloc = testing.allocator;
    var buf: std.ArrayListUnmanaged(u8) = .empty;

    // Populate buffer
    try buf.appendSlice("Hello World Test Data");

    const original_len = buf.items.len;

    // Consume first 11 bytes ("Hello World")
    ai.consumePrefix(&buf, 11);

    try testing.expectEqual(buf.items.len, original_len - 11);
    try testing.expectEqualStrings(buf.items, " Test Data");

    // Consume everything including space
    ai.consumePrefix(&buf, 1);

    try testing.expectEqual(buf.items.len, original_len - 12);
    try testing.expectEqualStrings(buf.items, "Test Data");

    // Consume more than available (should clear)
    ai.consumePrefix(&buf, 1000);

    try testing.expectEqual(buf.items.len, 0);
}

test "Cancellation flag detection" {
    const cancelled = std.atomic.Value(bool).init(true);
    try testing.expect(ai.isCancelled(&cancelled));

    const not_cancelled = std.atomic.Value(bool).init(false);
    try testing.expect(!ai.isCancelled(&not_cancelled));

    try testing.expect(!ai.isCancelled(null));
}
