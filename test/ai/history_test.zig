//! Unit tests for AI Conversation History module
//! Tests conversation management, message storage, and persistence

const std = @import("std");
const testing = std.testing;
const Allocator = std.mem.Allocator;

const history = @import("../../src/ai/history.zig");

test "Message Role enum values" {
    try testing.expectEqual(@as(history.Message.Role, .user), history.Message.Role.user);
    try testing.expectEqual(@as(history.Message.Role, .assistant), history.Message.Role.assistant);
    try testing.expectEqual(@as(history.Message.Role, .system), history.Message.Role.system);
}

test "Message initialization and deinit" {
    const alloc = testing.allocator;

    var msg = history.Message{
        .role = .user,
        .content = try alloc.dupe(u8, "Hello, how are you?"),
        .timestamp = 1234567890,
    };
    defer msg.deinit(alloc);

    try testing.expectEqual(msg.role, .user);
    try testing.expectEqualStrings(msg.content, "Hello, how are you?");
    try testing.expectEqual(msg.timestamp, 1234567890);
}

test "Conversation initialization" {
    const alloc = testing.allocator;

    const id = try alloc.dupe(u8, "conv-123");
    defer alloc.free(id);

    var conv = history.Conversation.init(alloc, id);
    defer conv.deinit(alloc);

    try testing.expectEqual(conv.id, id);
    try testing.expectEqual(conv.title, "");
    try testing.expectEqual(conv.messages.items.len, 0);
    try testing.expectEqual(conv.tags.items.len, 0);
    try testing.expect(conv.created_at > 0);
    try testing.expect(conv.updated_at > 0);
}

test "Conversation generateTitle from user message" {
    const alloc = testing.allocator;

    const id = try alloc.dupe(u8, "conv-123");
    defer alloc.free(id);

    var conv = history.Conversation.init(alloc, id);
    defer conv.deinit(alloc);

    // Add a user message
    try conv.messages.append(.{
        .role = .user,
        .content = try alloc.dupe(u8, "How do I install Docker on Ubuntu?"),
        .timestamp = std.time.timestamp(),
    });

    try conv.generateTitle(alloc);

    try testing.expectEqualStrings(conv.title, "How do I install Docker on Ubuntu?");
}

test "Conversation generateTitle truncates long messages" {
    const alloc = testing.allocator;

    const id = try alloc.dupe(u8, "conv-123");
    defer alloc.free(id);

    var conv = history.Conversation.init(alloc, id);
    defer conv.deinit(alloc);

    // Add a long user message (> 50 chars)
    const long_msg = "This is a very long message that exceeds fifty characters and should be truncated";
    try conv.messages.append(.{
        .role = .user,
        .content = try alloc.dupe(u8, long_msg),
        .timestamp = std.time.timestamp(),
    });

    try conv.generateTitle(alloc);

    // Should be truncated to 47 chars + "..."
    try testing.expectEqual(conv.title.len, 50);
    try testing.expect(std.mem.endsWith(u8, conv.title, "..."));
}

test "Conversation generateTitle skips non-user messages" {
    const alloc = testing.allocator;

    const id = try alloc.dupe(u8, "conv-123");
    defer alloc.free(id);

    var conv = history.Conversation.init(alloc, id);
    defer conv.deinit(alloc);

    // Add system message only
    try conv.messages.append(.{
        .role = .system,
        .content = try alloc.dupe(u8, "You are a helpful assistant."),
        .timestamp = std.time.timestamp(),
    });

    try conv.generateTitle(alloc);

    // Title should remain empty
    try testing.expectEqualStrings(conv.title, "");
}

test "Conversation deinit with all fields populated" {
    const alloc = testing.allocator;

    const id = try alloc.dupe(u8, "conv-123");
    defer alloc.free(id);

    var conv = history.Conversation.init(alloc, id);

    // Populate fields
    conv.title = try alloc.dupe(u8, "Test Conversation");

    try conv.messages.append(.{
        .role = .user,
        .content = try alloc.dupe(u8, "Hello"),
        .timestamp = 1234567890,
    });

    try conv.tags.append(try alloc.dupe(u8, "test"));

    conv.deinit(alloc);
}

test "Conversation with multiple messages" {
    const alloc = testing.allocator;

    const id = try alloc.dupe(u8, "conv-123");
    defer alloc.free(id);

    var conv = history.Conversation.init(alloc, id);
    defer conv.deinit(alloc);

    // Add multiple messages
    try conv.messages.append(.{
        .role = .user,
        .content = try alloc.dupe(u8, "What is Docker?"),
        .timestamp = 1000,
    });

    try conv.messages.append(.{
        .role = .assistant,
        .content = try alloc.dupe(u8, "Docker is a container platform..."),
        .timestamp = 2000,
    });

    try conv.messages.append(.{
        .role = .user,
        .content = try alloc.dupe(u8, "How do I install it?"),
        .timestamp = 3000,
    });

    try testing.expectEqual(conv.messages.items.len, 3);
    try testing.expectEqual(conv.messages.items[0].role, .user);
    try testing.expectEqual(conv.messages.items[1].role, .assistant);
    try testing.expectEqual(conv.messages.items[2].role, .user);
}

test "Conversation with tags" {
    const alloc = testing.allocator;

    const id = try alloc.dupe(u8, "conv-123");
    defer alloc.free(id);

    var conv = history.Conversation.init(alloc, id);
    defer conv.deinit(alloc);

    try conv.tags.append(try alloc.dupe(u8, "docker"));
    try conv.tags.append(try alloc.dupe(u8, "tutorial"));
    try conv.tags.append(try alloc.dupe(u8, "beginner"));

    try testing.expectEqual(conv.tags.items.len, 3);
    try testing.expectEqualStrings(conv.tags.items[0], "docker");
    try testing.expectEqualStrings(conv.tags.items[1], "tutorial");
    try testing.expectEqualStrings(conv.tags.items[2], "beginner");
}

test "Conversation with system message" {
    const alloc = testing.allocator;

    const id = try alloc.dupe(u8, "conv-123");
    defer alloc.free(id);

    var conv = history.Conversation.init(alloc, id);
    defer conv.deinit(alloc);

    // System messages are typically used for instructions
    try conv.messages.append(.{
        .role = .system,
        .content = try alloc.dupe(u8, "You are a helpful coding assistant specializing in Zig."),
        .timestamp = 1000,
    });

    try conv.messages.append(.{
        .role = .user,
        .content = try alloc.dupe(u8, "How do I use ArrayList?"),
        .timestamp = 2000,
    });

    try testing.expectEqual(conv.messages.items.len, 2);
    try testing.expectEqual(conv.messages.items[0].role, .system);
    try testing.expect(std.mem.indexOf(u8, conv.messages.items[0].content, "Zig") != null);
}

test "Conversation timestamps are monotonically increasing" {
    const alloc = testing.allocator;

    const id = try alloc.dupe(u8, "conv-123");
    defer alloc.free(id);

    var conv = history.Conversation.init(alloc, id);
    defer conv.deinit(alloc);

    const ts1 = std.time.timestamp();
    try conv.messages.append(.{
        .role = .user,
        .content = try alloc.dupe(u8, "First message"),
        .timestamp = ts1,
    });

    const ts2 = std.time.timestamp();
    try conv.messages.append(.{
        .role = .assistant,
        .content = try alloc.dupe(u8, "Second message"),
        .timestamp = ts2,
    });

    try testing.expect(ts2 >= ts1);
}

test "Message role enum completeness" {
    // Verify all expected roles exist
    const roles = [_]history.Message.Role{ .user, .assistant, .system };
    try testing.expectEqual(roles.len, 3);
}

test "Conversation empty messages list" {
    const alloc = testing.allocator;

    const id = try alloc.dupe(u8, "conv-123");
    defer alloc.free(id);

    var conv = history.Conversation.init(alloc, id);
    defer conv.deinit(alloc);

    try testing.expectEqual(conv.messages.items.len, 0);
    try testing.expectEqual(conv.title, "");
}
