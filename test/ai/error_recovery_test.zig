//! Unit tests for Error Recovery module
//! Tests error handling strategies and recovery mechanisms

const std = @import("std");
const testing = std.testing;
const Allocator = std.mem.Allocator;

const error_recovery = @import("../../src/ai/error_recovery.zig");

test "RecoveryStrategy StrategyType enum values" {
    try testing.expectEqual(@as(error_recovery.RecoveryStrategy.StrategyType, .retry), error_recovery.RecoveryStrategy.StrategyType.retry);
    try testing.expectEqual(@as(error_recovery.RecoveryStrategy.StrategyType, .fallback), error_recovery.RecoveryStrategy.StrategyType.fallback);
    try testing.expectEqual(@as(error_recovery.RecoveryStrategy.StrategyType, .skip), error_recovery.RecoveryStrategy.StrategyType.skip);
    try testing.expectEqual(@as(error_recovery.RecoveryStrategy.StrategyType, .abort), error_recovery.RecoveryStrategy.StrategyType.abort);
}

test "RecoveryStrategy initialization and deinit" {
    const alloc = testing.allocator;

    var strategy = error_recovery.RecoveryStrategy{
        .strategy_type = .retry,
        .max_retries = 3,
        .retry_delay_ms = 1000,
        .fallback_action = try alloc.dupe(u8, "Use backup provider"),
    };
    defer strategy.deinit(alloc);

    try testing.expectEqual(strategy.strategy_type, .retry);
    try testing.expectEqual(strategy.max_retries, 3);
    try testing.expectEqual(strategy.retry_delay_ms, 1000);
    try testing.expect(strategy.fallback_action != null);
}

test "RecoveryStrategy with null fallback_action deinit" {
    const alloc = testing.allocator;

    var strategy = error_recovery.RecoveryStrategy{
        .strategy_type = .abort,
        .max_retries = 0,
        .retry_delay_ms = 0,
        .fallback_action = null,
    };
    defer strategy.deinit(alloc);

    try testing.expect(strategy.fallback_action == null);
}

test "ErrorRecoveryManager initialization" {
    const alloc = testing.allocator;

    var manager = error_recovery.ErrorRecoveryManager.init(alloc);
    defer manager.deinit();

    try testing.expect(manager.enabled == true);
    try testing.expect(manager.strategies.items.len > 0);
}

test "ErrorRecoveryManager registers default strategies" {
    const alloc = testing.allocator;

    var manager = error_recovery.ErrorRecoveryManager.init(alloc);
    defer manager.deinit();

    try testing.expect(manager.strategies.items.len >= 2);
    try testing.expectEqual(manager.strategies.items[0].strategy_type, .retry);
    try testing.expectEqual(manager.strategies.items[1].strategy_type, .fallback);
}

test "ErrorRecoveryManager handleError with retry strategy" {
    const alloc = testing.allocator;

    var manager = error_recovery.ErrorRecoveryManager.init(alloc);
    defer manager.deinit();

    const action = try manager.handleError(.network_error, 0);

    try testing.expectEqual(action.action, .retry);
    try testing.expect(action.delay_ms > 0);
}

test "ErrorRecoveryManager handleError exceeds max retries" {
    const alloc = testing.allocator;

    var manager = error_recovery.ErrorRecoveryManager.init(alloc);
    defer manager.deinit();

    const action = try manager.handleError(.network_error, 10);

    try testing.expect(action.action == .fallback or action.action == .abort);
}

test "ErrorRecoveryManager handleError when disabled" {
    const alloc = testing.allocator;

    var manager = error_recovery.ErrorRecoveryManager.init(alloc);
    defer manager.deinit();

    manager.enabled = false;

    const action = try manager.handleError(.network_error, 0);

    try testing.expectEqual(action.action, .abort);
    try testing.expectEqualStrings(action.message, "Error recovery disabled");
}

test "ErrorRecoveryManager handleError with fallback action" {
    const alloc = testing.allocator;

    var manager = error_recovery.ErrorRecoveryManager.init(alloc);
    defer manager.deinit();

    const action = try manager.handleError(.api_error, 5);

    if (action.action == .fallback) {
        try testing.expect(action.message.len > 0);
    }
}

test "ErrorRecoveryManager setEnabled" {
    const alloc = testing.allocator;

    var manager = error_recovery.ErrorRecoveryManager.init(alloc);
    defer manager.deinit();

    manager.enabled = false;
    try testing.expect(manager.enabled == false);

    manager.enabled = true;
    try testing.expect(manager.enabled == true);
}

test "ErrorRecoveryManager RecoveryAction Action enum" {
    try testing.expectEqual(@as(error_recovery.ErrorRecoveryManager.RecoveryAction.Action, .retry), error_recovery.ErrorRecoveryManager.RecoveryAction.Action.retry);
    try testing.expectEqual(@as(error_recovery.ErrorRecoveryManager.RecoveryAction.Action, .fallback), error_recovery.ErrorRecoveryManager.RecoveryAction.Action.fallback);
    try testing.expectEqual(@as(error_recovery.ErrorRecoveryManager.RecoveryAction.Action, .skip), error_recovery.ErrorRecoveryManager.RecoveryAction.Action.skip);
    try testing.expectEqual(@as(error_recovery.ErrorRecoveryManager.RecoveryAction.Action, .abort), error_recovery.ErrorRecoveryManager.RecoveryAction.Action.abort);
}

test "ErrorRecoveryManager ErrorType enum values" {
    try testing.expectEqual(@as(error_recovery.ErrorRecoveryManager.ErrorType, .network_error), error_recovery.ErrorRecoveryManager.ErrorType.network_error);
    try testing.expectEqual(@as(error_recovery.ErrorRecoveryManager.ErrorType, .api_error), error_recovery.ErrorRecoveryManager.ErrorType.api_error);
    try testing.expectEqual(@as(error_recovery.ErrorRecoveryManager.ErrorType, .timeout_error), error_recovery.ErrorRecoveryManager.ErrorType.timeout_error);
    try testing.expectEqual(@as(error_recovery.ErrorRecoveryManager.ErrorType, .parse_error), error_recovery.ErrorRecoveryManager.ErrorType.parse_error);
    try testing.expectEqual(@as(error_recovery.ErrorRecoveryManager.ErrorType, .unknown_error), error_recovery.ErrorRecoveryManager.ErrorType.unknown_error);
}

test "ErrorRecoveryManager handleError with different error types" {
    const alloc = testing.allocator;

    var manager = error_recovery.ErrorRecoveryManager.init(alloc);
    defer manager.deinit();

    const error_types = [_]error_recovery.ErrorRecoveryManager.ErrorType{
        .network_error,
        .api_error,
        .timeout_error,
        .parse_error,
        .unknown_error,
    };

    for (error_types) |err_type| {
        const action = try manager.handleError(err_type, 0);
        try testing.expect(action.action != .abort);
    }
}

test "ErrorRecoveryManager deinit cleans up strategies" {
    const alloc = testing.allocator;

    var manager = error_recovery.ErrorRecoveryManager.init(alloc);

    // deinit should clean up all strategies and their fallback_action strings
    manager.deinit();
}

test "RecoveryAction with delay_ms" {
    const alloc = testing.allocator;

    var manager = error_recovery.ErrorRecoveryManager.init(alloc);
    defer manager.deinit();

    const action = try manager.handleError(.network_error, 0);

    if (action.action == .retry) {
        try testing.expect(action.delay_ms > 0);
    }
}

test "RecoveryStrategy with different types" {
    const alloc = testing.allocator;

    const strategies = [_]error_recovery.RecoveryStrategy.StrategyType{
        .retry,
        .fallback,
        .skip,
        .abort,
    };

    for (strategies) |strategy_type| {
        var strategy = error_recovery.RecoveryStrategy{
            .strategy_type = strategy_type,
            .max_retries = 1,
            .retry_delay_ms = 100,
            .fallback_action = null,
        };
        defer strategy.deinit(alloc);

        try testing.expectEqual(strategy.strategy_type, strategy_type);
    }
}
