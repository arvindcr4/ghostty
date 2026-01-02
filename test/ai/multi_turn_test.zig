//! Unit tests for Multi-turn Conversations module
//! Tests conversation turns, context building, and history management

const std = @import("std");
const testing = std.testing;
const Allocator = std.mem.Allocator;

const multi_turn = @import("../../src/ai/multi_turn.zig");

test "ConversationTurn Role enum values" {
    try testing.expectEqual(@as(multi_turn.ConversationTurn.Role, .user), multi_turn.ConversationTurn.Role.user);
    try testing.expectEqual(@as(multi_turn.ConversationTurn.Role, .assistant), multi_turn.ConversationTurn.Role.assistant);
    try testing.expectEqual(@as(multi_turn.ConversationTurn.Role, .system), multi_turn.ConversationTurn.Role.system);
}

test "ConversationTurn initialization and deinit" {
    const alloc = testing.allocator;

    var turn = multi_turn.ConversationTurn{
        .role = .user,
        .content = try alloc.dupe(u8, "Hello, how are you?"),
        .timestamp = 1234567890,
        .context_snapshot = try alloc.dupe(u8, "current directory: /home/user"),
    };
    defer turn.deinit(alloc);

    try testing.expectEqual(turn.role, .user);
    try testing.expectEqualStrings(turn.content, "Hello, how are you?");
    try testing.expectEqual(turn.timestamp, 1234567890);
    try testing.expect(turn.context_snapshot != null);
}

test "ConversationTurn with null context_snapshot" {
    const alloc = testing.allocator;

    var turn = multi_turn.ConversationTurn{
        .role = .assistant,
        .content = try alloc.dupe(u8, "I'm doing well, thank you!"),
        .timestamp = 1234567891,
        .context_snapshot = null,
    };
    defer turn.deinit(alloc);

    try testing.expectEqual(turn.role, .assistant);
    try testing.expect(turn.context_snapshot == null);
}

test "MultiTurnConversation initialization" {
    const alloc = testing.allocator;

    var conv = multi_turn.MultiTurnConversation.init(alloc, 10, 1000);
    defer conv.deinit();

    try testing.expectEqual(conv.max_turns, 10);
    try testing.expectEqual(conv.context_window, 1000);
    try testing.expectEqual(conv.turns.items.len, 0);
}

test "MultiTurnConversation addTurn" {
    const alloc = testing.allocator;

    var conv = multi_turn.MultiTurnConversation.init(alloc, 10, 1000);
    defer conv.deinit();

    try conv.addTurn(.user, "Hello", null);
    try conv.addTurn(.assistant, "Hi there!", null);

    try testing.expectEqual(conv.turns.items.len, 2);
    try testing.expectEqual(conv.turns.items[0].role, .user);
    try testing.expectEqual(conv.turns.items[1].role, .assistant);
}

test "MultiTurnConversation addTurn with context" {
    const alloc = testing.allocator;

    var conv = multi_turn.MultiTurnConversation.init(alloc, 10, 1000);
    defer conv.deinit();

    const context = "Current directory: /home/user/project";
    try conv.addTurn(.user, "What files are here?", context);

    try testing.expectEqual(conv.turns.items.len, 1);
    try testing.expect(conv.turns.items[0].context_snapshot != null);
    try testing.expectEqualStrings(conv.turns.items[0].context_snapshot.?, context);
}

test "MultiTurnConversation max_turns limit" {
    const alloc = testing.allocator;

    var conv = multi_turn.MultiTurnConversation.init(alloc, 3, 1000);
    defer conv.deinit();

    try conv.addTurn(.user, "Message 1", null);
    try conv.addTurn(.assistant, "Response 1", null);
    try conv.addTurn(.user, "Message 2", null);
    try conv.addTurn(.assistant, "Response 2", null);

    // Should only keep last 3 turns
    try testing.expectEqual(conv.turns.items.len, 3);
    try testing.expectEqualStrings(conv.turns.items[0].content, "Response 1");
    try testing.expectEqualStrings(conv.turns.items[1].content, "Message 2");
    try testing.expectEqualStrings(conv.turns.items[2].content, "Response 2");
}

test "MultiTurnConversation buildContext" {
    const alloc = testing.allocator;

    var conv = multi_turn.MultiTurnConversation.init(alloc, 10, 10000);
    defer conv.deinit();

    try conv.addTurn(.user, "What is Docker?", null);
    try conv.addTurn(.assistant, "Docker is a container platform.", null);
    try conv.addTurn(.user, "How do I install it?", null);

    const context = try conv.buildContext();
    defer alloc.free(context);

    try testing.expect(context.len > 0);
    try testing.expect(std.mem.indexOf(u8, context, "user") != null);
    try testing.expect(std.mem.indexOf(u8, context, "assistant") != null);
    try testing.expect(std.mem.indexOf(u8, context, "Docker") != null);
}

test "MultiTurnConversation buildContext respects context_window" {
    const alloc = testing.allocator;

    // Small context window (100 chars)
    var conv = multi_turn.MultiTurnConversation.init(alloc, 10, 100);
    defer conv.deinit();

    try conv.addTurn(.user, "This is a very long first message that should exceed the context window when combined with other messages", null);
    try conv.addTurn(.assistant, "This is the second message", null);
    try conv.addTurn(.user, "This is the third message", null);

    const context = try conv.buildContext();
    defer alloc.free(context);

    // Context should be limited
    try testing.expect(context.len < 200);
}

test "MultiTurnConversation getRecentTurns" {
    const alloc = testing.allocator;

    var conv = multi_turn.MultiTurnConversation.init(alloc, 10, 1000);
    defer conv.deinit();

    try conv.addTurn(.user, "Message 1", null);
    try conv.addTurn(.assistant, "Response 1", null);
    try conv.addTurn(.user, "Message 2", null);
    try conv.addTurn(.assistant, "Response 2", null);

    const recent = conv.getRecentTurns(2);
    try testing.expectEqual(recent.len, 2);
    try testing.expectEqualStrings(recent[0].content, "Message 2");
    try testing.expectEqualStrings(recent[1].content, "Response 2");
}

test "MultiTurnConversation getRecentTurns more than available" {
    const alloc = testing.allocator;

    var conv = multi_turn.MultiTurnConversation.init(alloc, 10, 1000);
    defer conv.deinit();

    try conv.addTurn(.user, "Message 1", null);
    try conv.addTurn(.assistant, "Response 1", null);

    const recent = conv.getRecentTurns(5);
    try testing.expectEqual(recent.len, 2);
}

test "MultiTurnConversation getRecentTurns empty" {
    const alloc = testing.allocator;

    var conv = multi_turn.MultiTurnConversation.init(alloc, 10, 1000);
    defer conv.deinit();

    const recent = conv.getRecentTurns(5);
    try testing.expectEqual(recent.len, 0);
}

test "MultiTurnConversation clear" {
    const alloc = testing.allocator;

    var conv = multi_turn.MultiTurnConversation.init(alloc, 10, 1000);
    defer conv.deinit();

    try conv.addTurn(.user, "Message 1", null);
    try conv.addTurn(.assistant, "Response 1", null);
    try conv.addTurn(.user, "Message 2", null);

    try testing.expectEqual(conv.turns.items.len, 3);

    conv.clear();

    try testing.expectEqual(conv.turns.items.len, 0);
}

test "MultiTurnConversation deinit cleans up all turns" {
    const alloc = testing.allocator;

    var conv = multi_turn.MultiTurnConversation.init(alloc, 10, 1000);

    try conv.addTurn(.user, "Message 1", "context 1");
    try conv.addTurn(.assistant, "Response 1", "context 2");
    try conv.addTurn(.user, "Message 2", "context 3");

    // deinit should clean up all turns and their content/context
    conv.deinit();
}

test "MultiTurnConversation system messages" {
    const alloc = testing.allocator;

    var conv = multi_turn.MultiTurnConversation.init(alloc, 10, 1000);
    defer conv.deinit();

    try conv.addTurn(.system, "You are a helpful assistant.", null);
    try conv.addTurn(.user, "Hello", null);
    try conv.addTurn(.assistant, "Hi!", null);

    try testing.expectEqual(conv.turns.items.len, 3);
    try testing.expectEqual(conv.turns.items[0].role, .system);

    const context = try conv.buildContext();
    defer alloc.free(context);
    try testing.expect(std.mem.indexOf(u8, context, "system") != null);
}

test "MultiTurnConversation timestamps are monotonically increasing" {
    const alloc = testing.allocator;

    var conv = multi_turn.MultiTurnConversation.init(alloc, 10, 1000);
    defer conv.deinit();

    try conv.addTurn(.user, "First", null);
    const ts1 = conv.turns.items[0].timestamp;

    try conv.addTurn(.assistant, "Second", null);
    const ts2 = conv.turns.items[1].timestamp;

    try testing.expect(ts2 >= ts1);
}

test "MultiTurnConversation role tagName mapping" {
    const alloc = testing.allocator;

    var conv = multi_turn.MultiTurnConversation.init(alloc, 10, 1000);
    defer conv.deinit();

    try conv.addTurn(.user, "User message", null);
    try conv.addTurn(.assistant, "Assistant message", null);
    try conv.addTurn(.system, "System message", null);

    const context = try conv.buildContext();
    defer alloc.free(context);

    try testing.expect(std.mem.indexOf(u8, context, "user") != null);
    try testing.expect(std.mem.indexOf(u8, context, "assistant") != null);
    try testing.expect(std.mem.indexOf(u8, context, "system") != null);
}
