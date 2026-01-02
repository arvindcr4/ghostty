//! Unit tests for AI Suggestions module
//! Tests command suggestion service, history management, and typo correction

const std = @import("std");
const testing = std.testing;
const Allocator = std.mem.Allocator;

const suggestions = @import("../../src/ai/suggestions.zig");
const ai = @import("../../src/ai/main.zig");

test "RichCommandEntry initialization and deinit" {
    const alloc = testing.allocator;

    var entry = suggestions.RichCommandEntry{
        .command = try alloc.dupe(u8, "git status"),
        .exit_code = 0,
        .directory = try alloc.dupe(u8, "/home/user/project"),
        .git_branch = try alloc.dupe(u8, "main"),
        .timestamp = 1234567890,
        .duration = 150,
    };
    defer entry.deinit(alloc);

    try testing.expectEqualStrings(entry.command, "git status");
    try testing.expectEqual(entry.exit_code.?, 0);
    try testing.expectEqualStrings(entry.directory.?, "/home/user/project");
    try testing.expectEqualStrings(entry.git_branch.?, "main");
    try testing.expectEqual(entry.timestamp, 1234567890);
    try testing.expectEqual(entry.duration.?, 150);
}

test "RichCommandEntry deinit with null fields" {
    const alloc = testing.allocator;

    var entry = suggestions.RichCommandEntry{
        .command = try alloc.dupe(u8, "echo hello"),
        .exit_code = null,
        .directory = null,
        .git_branch = null,
        .timestamp = 1234567890,
        .duration = null,
    };
    entry.deinit(alloc);
}

test "Suggestion Source enum values" {
    try testing.expectEqual(@as(suggestions.Suggestion.Source, .history), suggestions.Suggestion.Source.history);
    try testing.expectEqual(@as(suggestions.Suggestion.Source, .ai), suggestions.Suggestion.Source.ai);
    try testing.expectEqual(@as(suggestions.Suggestion.Source, .workflow), suggestions.Suggestion.Source.workflow);
    try testing.expectEqual(@as(suggestions.Suggestion.Source, .correction), suggestions.Suggestion.Source.correction);
}

test "Suggestion initialization and deinit" {
    const alloc = testing.allocator;

    var suggestion = suggestions.Suggestion{
        .command = try alloc.dupe(u8, "git push"),
        .description = try alloc.dupe(u8, "Push commits to remote"),
        .confidence = 0.8,
        .source = .history,
    };
    defer suggestion.deinit(alloc);

    try testing.expectEqualStrings(suggestion.command, "git push");
    try testing.expectEqualStrings(suggestion.description, "Push commits to remote");
    try testing.expectEqual(suggestion.confidence, 0.8);
    try testing.expectEqual(suggestion.source, .history);
}

test "SuggestionService initialization without AI client" {
    const alloc = testing.allocator;

    const config = ai.Assistant.Config{
        .enabled = false,
        .provider = null,
        .api_key = "",
        .endpoint = "",
        .model = "",
    };

    var service = try suggestions.SuggestionService.init(alloc, config);
    defer service.deinit();

    try testing.expect(service.client == null);
    try testing.expectEqual(service.max_history, 50);
    try testing.expectEqual(service.history.items.len, 0);
}

test "SuggestionService initialization with AI client" {
    const alloc = testing.allocator;

    const config = ai.Assistant.Config{
        .enabled = true,
        .provider = .openai,
        .api_key = "test-key",
        .endpoint = "https://api.example.com",
        .model = "gpt-4",
    };

    var service = try suggestions.SuggestionService.init(alloc, config);
    defer service.deinit();

    try testing.expect(service.client != null);
    try testing.expectEqual(service.client.?.provider, .openai);
}

test "SuggestionService recordCommand" {
    const alloc = testing.allocator;

    const config = ai.Assistant.Config{
        .enabled = false,
        .provider = null,
        .api_key = "",
        .endpoint = "",
        .model = "",
    };

    var service = try suggestions.SuggestionService.init(alloc, config);
    defer service.deinit();

    try service.recordCommand("git status");
    try service.recordCommand("git add .");

    try testing.expectEqual(service.history.items.len, 2);
    try testing.expectEqualStrings(service.history.items[0].command, "git status");
    try testing.expectEqualStrings(service.history.items[1].command, "git add .");
}

test "SuggestionService recordCommand skips empty" {
    const alloc = testing.allocator;

    const config = ai.Assistant.Config{
        .enabled = false,
        .provider = null,
        .api_key = "",
        .endpoint = "",
        .model = "",
    };

    var service = try suggestions.SuggestionService.init(alloc, config);
    defer service.deinit();

    try service.recordCommand("git status");
    try service.recordCommand("");
    try service.recordCommand("git add .");

    try testing.expectEqual(service.history.items.len, 2);
}

test "SuggestionService recordCommand skips duplicates" {
    const alloc = testing.allocator;

    const config = ai.Assistant.Config{
        .enabled = false,
        .provider = null,
        .api_key = "",
        .endpoint = "",
        .model = "",
    };

    var service = try suggestions.SuggestionService.init(alloc, config);
    defer service.deinit();

    try service.recordCommand("git status");
    try service.recordCommand("git status");
    try service.recordCommand("git add .");

    try testing.expectEqual(service.history.items.len, 2);
}

test "SuggestionService recordCommandRich with metadata" {
    const alloc = testing.allocator;

    const config = ai.Assistant.Config{
        .enabled = false,
        .provider = null,
        .api_key = "",
        .endpoint = "",
        .model = "",
    };

    var service = try suggestions.SuggestionService.init(alloc, config);
    defer service.deinit();

    try service.recordCommandRich("git status", 0, "/home/user/project", "main", 150);

    try testing.expectEqual(service.history.items.len, 1);
    const entry = service.history.items[0];
    try testing.expectEqualStrings(entry.command, "git status");
    try testing.expectEqual(entry.exit_code.?, 0);
    try testing.expectEqualStrings(entry.directory.?, "/home/user/project");
    try testing.expectEqualStrings(entry.git_branch.?, "main");
    try testing.expectEqual(entry.duration.?, 150);
}

test "SuggestionService history trimming" {
    const alloc = testing.allocator;

    const config = ai.Assistant.Config{
        .enabled = false,
        .provider = null,
        .api_key = "",
        .endpoint = "",
        .model = "",
    };

    var service = try suggestions.SuggestionService.init(alloc, config);
    defer service.deinit();

    // Add more commands than max_history
    var i: usize = 0;
    while (i < 60) : (i += 1) {
        const cmd = try std.fmt.allocPrint(alloc, "command_{d}", .{i});
        defer alloc.free(cmd);
        try service.recordCommand(cmd);
    }

    // Should be trimmed to max_history (50)
    try testing.expectEqual(service.history.items.len, 50);
}

test "SuggestionService getSuggestions - history patterns" {
    const alloc = testing.allocator;

    const config = ai.Assistant.Config{
        .enabled = false,
        .provider = null,
        .api_key = "",
        .endpoint = "",
        .model = "",
    };

    var service = try suggestions.SuggestionService.init(alloc, config);
    defer service.deinit();

    // Add commands that trigger a pattern
    try service.recordCommand("git add .");
    try service.recordCommand("git status");

    const result_suggestions = try service.getSuggestions(null);
    defer {
        for (result_suggestions.items) |*s| s.deinit(alloc);
        result_suggestions.deinit();
    }

    // Should suggest "git commit" after "git add"
    try testing.expect(result_suggestions.items.len > 0);
    const found = blk: {
        for (result_suggestions.items) |sugg| {
            if (std.mem.indexOf(u8, sugg.command, "git commit") != null) {
                break :blk true;
            }
        }
        break :blk false;
    };
    try testing.expect(found, "Should suggest git commit after git add");
}

test "SuggestionService getCorrection - common typos" {
    const alloc = testing.allocator;

    const config = ai.Assistant.Config{
        .enabled = false,
        .provider = null,
        .api_key = "",
        .endpoint = "",
        .model = "",
    };

    var service = try suggestions.SuggestionService.init(alloc, config);
    defer service.deinit();

    // Test common typos
    const test_cases = [_]struct { typo: []const u8, expected: []const u8 }{
        .{ .typo = "gti status", .expected = "git status" },
        .{ .typo = "got status", .expected = "git status" },
        .{ .typo = "npx install", .expected = "npm install" },
        .{ .typo = "pyton script.py", .expected = "python script.py" },
        .{ .typo = "suod command", .expected = "sudo command" },
        .{ .typo = "gerp pattern", .expected = "grep pattern" },
        .{ .typo = "sl -la", .expected = "ls -la" },
        .{ .typo = "cd..", .expected = "cd .." },
    };

    for (test_cases) |tc| {
        const result = try service.getCorrection(tc.typo);
        try testing.expect(result != null, "Should correct '{s}'", .{tc.typo});
        if (result) |corr| {
            defer corr.deinit(alloc);
            try testing.expectEqualStrings(corr.command, tc.expected, "Typo '{s}' should become '{s}'", .{ tc.typo, tc.expected });
            try testing.expectEqual(corr.source, .correction);
            try testing.expect(corr.confidence >= 0.8);
        }
    }
}

test "SuggestionService getCorrection - no correction needed" {
    const alloc = testing.allocator;

    const config = ai.Assistant.Config{
        .enabled = false,
        .provider = null,
        .api_key = "",
        .endpoint = "",
        .model = "",
    };

    var service = try suggestions.SuggestionService.init(alloc, config);
    defer service.deinit();

    // Valid command should return null
    const result = try service.getCorrection("git status");
    try testing.expect(result == null);
}

test "SuggestionService workflow patterns - git" {
    const alloc = testing.allocator;

    const config = ai.Assistant.Config{
        .enabled = false,
        .provider = null,
        .api_key = "",
        .endpoint = "",
        .model = "",
    };

    var service = try suggestions.SuggestionService.init(alloc, config);
    defer service.deinit();

    // Git workflow: add -> commit -> push
    try service.recordCommand("git add file.txt");
    const suggestions1 = try service.getSuggestions(null);
    defer {
        for (suggestions1.items) |*s| s.deinit(alloc);
        suggestions1.deinit();
    }
    try testing.expect(suggestions1.items.len > 0);

    // Should suggest commit
    try testing.expect(std.mem.indexOf(u8, suggestions1.items[0].command, "commit") != null);
}

test "SuggestionService workflow patterns - build tools" {
    const alloc = testing.allocator;

    const config = ai.Assistant.Config{
        .enabled = false,
        .provider = null,
        .api_key = "",
        .endpoint = "",
        .model = "",
    };

    var service = try suggestions.SuggestionService.init(alloc, config);
    defer service.deinit();

    // Build workflow
    const workflows = [_][]const u8{
        "npm install",
        "npm run build",
        "zig build",
        "cargo build",
        "docker build",
    };

    for (workflows) |cmd| {
        try service.recordCommand(cmd);
        const suggs = try service.getSuggestions(null);
        defer {
            for (suggs.items) |*s| s.deinit(alloc);
            suggs.deinit();
        }
        // Each should trigger a suggestion
        try testing.expect(suggs.items.len > 0);
    }
}
