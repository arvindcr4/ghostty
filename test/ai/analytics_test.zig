//! Unit tests for Analytics module
//! Tests event tracking, statistics, and analytics management

const std = @import("std");
const testing = std.testing;
const Allocator = std.mem.Allocator;

const analytics = @import("../../src/ai/analytics.zig");

test "AnalyticsEvent EventType enum values" {
    try testing.expectEqual(@as(analytics.AnalyticsEvent.EventType, .ai_request), analytics.AnalyticsEvent.EventType.ai_request);
    try testing.expectEqual(@as(analytics.AnalyticsEvent.EventType, .command_executed), analytics.AnalyticsEvent.EventType.command_executed);
    try testing.expectEqual(@as(analytics.AnalyticsEvent.EventType, .workflow_run), analytics.AnalyticsEvent.EventType.workflow_run);
    try testing.expectEqual(@as(analytics.AnalyticsEvent.EventType, .suggestion_accepted), analytics.AnalyticsEvent.EventType.suggestion_accepted);
    try testing.expectEqual(@as(analytics.AnalyticsEvent.EventType, .correction_applied), analytics.AnalyticsEvent.EventType.correction_applied);
    try testing.expectEqual(@as(analytics.AnalyticsEvent.EventType, .error_occurred), analytics.AnalyticsEvent.EventType.error_occurred);
}

test "AnalyticsEvent deinit" {
    const alloc = testing.allocator;

    var metadata = std.StringHashMap([]const u8).init(alloc);
    try metadata.put(try alloc.dupe(u8, "command"), try alloc.dupe(u8, "git status"));

    var event = analytics.AnalyticsEvent{
        .event_type = .command_executed,
        .timestamp = 1234567890,
        .metadata = metadata,
    };
    event.deinit(alloc);
}

test "AnalyticsEvent deinit with empty metadata" {
    const alloc = testing.allocator;

    var event = analytics.AnalyticsEvent{
        .event_type = .ai_request,
        .timestamp = 1234567890,
        .metadata = std.StringHashMap([]const u8).init(alloc),
    };
    event.deinit(alloc);
}

test "AnalyticsManager initialization" {
    const alloc = testing.allocator;

    var manager = analytics.AnalyticsManager.init(alloc, 100);
    defer manager.deinit();

    try testing.expectEqual(manager.max_events, 100);
    try testing.expect(manager.enabled == true);
    try testing.expectEqual(manager.events.items.len, 0);
}

test "AnalyticsManager recordEvent" {
    const alloc = testing.allocator;

    var manager = analytics.AnalyticsManager.init(alloc, 100);
    defer manager.deinit();

    try manager.recordEvent(.ai_request, null);

    try testing.expectEqual(manager.events.items.len, 1);
    try testing.expectEqual(manager.events.items[0].event_type, .ai_request);
    try testing.expect(manager.events.items[0].timestamp > 0);
}

test "AnalyticsManager recordEvent with metadata" {
    const alloc = testing.allocator;

    var manager = analytics.AnalyticsManager.init(alloc, 100);
    defer manager.deinit();

    var metadata = std.StringHashMap([]const u8).init(alloc);
    try metadata.put(try alloc.dupe(u8, "command"), try alloc.dupe(u8, "docker ps"));

    try manager.recordEvent(.command_executed, metadata);

    try testing.expectEqual(manager.events.items.len, 1);
    try testing.expectEqual(manager.events.items[0].event_type, .command_executed);
    try testing.expect(manager.events.items[0].metadata.count() == 1);
}

test "AnalyticsManager max_events limit" {
    const alloc = testing.allocator;

    var manager = analytics.AnalyticsManager.init(alloc, 3);
    defer manager.deinit();

    try manager.recordEvent(.ai_request, null);
    try manager.recordEvent(.command_executed, null);
    try manager.recordEvent(.workflow_run, null);
    try manager.recordEvent(.suggestion_accepted, null);

    // Should only keep last 3 events
    try testing.expectEqual(manager.events.items.len, 3);
    try testing.expectEqual(manager.events.items[0].event_type, .command_executed);
    try testing.expectEqual(manager.events.items[2].event_type, .suggestion_accepted);
}

test "AnalyticsManager setEnabled" {
    const alloc = testing.allocator;

    var manager = analytics.AnalyticsManager.init(alloc, 100);
    defer manager.deinit();

    try testing.expect(manager.enabled == true);

    manager.setEnabled(false);
    try testing.expect(manager.enabled == false);

    manager.setEnabled(true);
    try testing.expect(manager.enabled == true);
}

test "AnalyticsManager disabled does not record events" {
    const alloc = testing.allocator;

    var manager = analytics.AnalyticsManager.init(alloc, 100);
    defer manager.deinit();

    manager.setEnabled(false);

    try manager.recordEvent(.ai_request, null);

    try testing.expectEqual(manager.events.items.len, 0);
}

test "AnalyticsManager getStats with no events" {
    const alloc = testing.allocator;

    var manager = analytics.AnalyticsManager.init(alloc, 100);
    defer manager.deinit();

    const stats = manager.getStats();

    try testing.expectEqual(stats.total_requests, 0);
    try testing.expectEqual(stats.total_commands, 0);
    try testing.expectEqual(stats.total_workflows, 0);
    try testing.expectEqual(stats.error_rate, 0.0);
    try testing.expect(stats.most_used_feature == null);
}

test "AnalyticsManager getStats with events" {
    const alloc = testing.allocator;

    var manager = analytics.AnalyticsManager.init(alloc, 100);
    defer manager.deinit();

    try manager.recordEvent(.ai_request, null);
    try manager.recordEvent(.ai_request, null);
    try manager.recordEvent(.command_executed, null);
    try manager.recordEvent(.workflow_run, null);
    try manager.recordEvent(.error_occurred, null);

    const stats = manager.getStats();

    try testing.expectEqual(stats.total_requests, 2);
    try testing.expectEqual(stats.total_commands, 1);
    try testing.expectEqual(stats.total_workflows, 1);
    try testing.expect(stats.error_rate > 0);
    try testing.expect(stats.most_used_feature != null);
}

test "AnalyticsManager getStats most_used_feature" {
    const alloc = testing.allocator;

    var manager = analytics.AnalyticsManager.init(alloc, 100);
    defer manager.deinit();

    try manager.recordEvent(.ai_request, null);
    try manager.recordEvent(.ai_request, null);
    try manager.recordEvent(.ai_request, null);
    try manager.recordEvent(.command_executed, null);

    const stats = manager.getStats();

    try testing.expectEqual(stats.most_used_feature.?, .ai_request);
}

test "AnalyticsManager getStats error_rate calculation" {
    const alloc = testing.allocator;

    var manager = analytics.AnalyticsManager.init(alloc, 100);
    defer manager.deinit();

    try manager.recordEvent(.ai_request, null);
    try manager.recordEvent(.command_executed, null);
    try manager.recordEvent(.error_occurred, null);
    try manager.recordEvent(.error_occurred, null);

    const stats = manager.getStats();

    // 2 errors out of 4 events = 0.5
    try testing.expectApproxEq(stats.error_rate, 0.5, 0.01);
}

test "AnalyticsManager multiple event types" {
    const alloc = testing.allocator;

    var manager = analytics.AnalyticsManager.init(alloc, 100);
    defer manager.deinit();

    try manager.recordEvent(.ai_request, null);
    try manager.recordEvent(.suggestion_accepted, null);
    try manager.recordEvent(.correction_applied, null);
    try manager.recordEvent(.workflow_run, null);

    try testing.expectEqual(manager.events.items.len, 4);
    try testing.expectEqual(manager.events.items[0].event_type, .ai_request);
    try testing.expectEqual(manager.events.items[1].event_type, .suggestion_accepted);
    try testing.expectEqual(manager.events.items[2].event_type, .correction_applied);
    try testing.expectEqual(manager.events.items[3].event_type, .workflow_run);
}

test "AnalyticsManager deinit cleans up all events" {
    const alloc = testing.allocator;

    var manager = analytics.AnalyticsManager.init(alloc, 100);

    var metadata = std.StringHashMap([]const u8).init(alloc);
    try metadata.put(try alloc.dupe(u8, "key"), try alloc.dupe(u8, "value"));

    try manager.recordEvent(.ai_request, metadata);
    try manager.recordEvent(.command_executed, null);

    // deinit should clean up all events and their metadata
    manager.deinit();
}

test "AnalyticsManager event timestamps are set" {
    const alloc = testing.allocator;

    var manager = analytics.AnalyticsManager.init(alloc, 100);
    defer manager.deinit();

    const before = std.time.timestamp();
    try manager.recordEvent(.ai_request, null);
    const after = std.time.timestamp();

    try testing.expect(manager.events.items[0].timestamp >= before);
    try testing.expect(manager.events.items[0].timestamp <= after);
}

test "AnalyticsManager getStats with tie for most_used" {
    const alloc = testing.allocator;

    var manager = analytics.AnalyticsManager.init(alloc, 100);
    defer manager.deinit();

    try manager.recordEvent(.ai_request, null);
    try manager.recordEvent(.command_executed, null);

    const stats = manager.getStats();

    // Either could be returned in case of tie
    try testing.expect(stats.most_used_feature != null);
}
