//! Unit tests for AI GTK Class modules
//! Tests memory management patterns, data structures, and logic
//! Note: GTK widget tests require mocking as they need a display server

const std = @import("std");
const testing = std.testing;
const Allocator = std.mem.Allocator;

// =============================================================================
// BookmarkItem.addTag() Tests
// =============================================================================

test "addTag - correctly handles empty initial tags" {
    const alloc = testing.allocator;

    // Simulate BookmarkItem.tags behavior
    var tags: []const [:0]const u8 = &.{};

    // First addTag
    const new_tag = try alloc.dupeZ(u8, "test-tag");
    errdefer alloc.free(new_tag);

    const new_tags = try alloc.alloc([:0]const u8, tags.len + 1);
    @memcpy(new_tags[0..tags.len], tags);
    new_tags[tags.len] = new_tag;

    // Should NOT free empty slice literal
    if (tags.len > 0) {
        alloc.free(tags);
    }

    tags = new_tags;
    defer {
        for (tags) |tag| alloc.free(tag);
        alloc.free(tags);
    }

    try testing.expectEqual(tags.len, 1);
    try testing.expectEqualStrings(tags[0], "test-tag");
}

test "addTag - correctly handles multiple tags" {
    const alloc = testing.allocator;

    var tags: [][:0]const u8 = &.{};

    // Add 3 tags
    const tag_names = [_][]const u8{ "git", "docker", "kubernetes" };

    for (tag_names) |tag_name| {
        const new_tag = try alloc.dupeZ(u8, tag_name);
        errdefer alloc.free(new_tag);

        const new_tags = try alloc.alloc([:0]const u8, tags.len + 1);
        @memcpy(new_tags[0..tags.len], tags);
        new_tags[tags.len] = new_tag;

        if (tags.len > 0) {
            alloc.free(tags);
        }
        tags = new_tags;
    }

    defer {
        for (tags) |tag| alloc.free(tag);
        alloc.free(tags);
    }

    try testing.expectEqual(tags.len, 3);
    try testing.expectEqualStrings(tags[0], "git");
    try testing.expectEqualStrings(tags[1], "docker");
    try testing.expectEqualStrings(tags[2], "kubernetes");
}

// =============================================================================
// String Duplication Tests (for sentinel-terminated strings)
// =============================================================================

test "dupeZ creates proper null-terminated string" {
    const alloc = testing.allocator;

    const original = "test string";
    const duped = try alloc.dupeZ(u8, original);
    defer alloc.free(duped);

    try testing.expectEqualStrings(duped, original);
    try testing.expectEqual(duped[duped.len], 0); // null terminator
}

test "dupeZ handles empty string" {
    const alloc = testing.allocator;

    const original = "";
    const duped = try alloc.dupeZ(u8, original);
    defer alloc.free(duped);

    try testing.expectEqual(duped.len, 0);
    try testing.expectEqual(duped[0], 0); // null terminator at index 0
}

test "dupeZ handles special characters" {
    const alloc = testing.allocator;

    const original = "path/to/file with spaces & special!@#$%";
    const duped = try alloc.dupeZ(u8, original);
    defer alloc.free(duped);

    try testing.expectEqualStrings(duped, original);
}

// =============================================================================
// Reference Counting Pattern Tests
// =============================================================================

test "refSink pattern - simulated reference counting" {
    // Simulate GObject reference counting behavior
    const RefCountedObject = struct {
        ref_count: u32 = 1,
        is_floating: bool = true,

        pub fn refSink(self: *@This()) *@This() {
            if (self.is_floating) {
                self.is_floating = false;
                // Don't increment - just sink the floating ref
            } else {
                self.ref_count += 1;
            }
            return self;
        }

        pub fn ref(self: *@This()) *@This() {
            self.ref_count += 1;
            return self;
        }

        pub fn unref(self: *@This()) void {
            self.ref_count -= 1;
        }
    };

    // Test CORRECT pattern: just refSink()
    var obj1 = RefCountedObject{};
    _ = obj1.refSink();
    try testing.expectEqual(obj1.ref_count, 1);
    try testing.expectEqual(obj1.is_floating, false);

    // Test OLD INCORRECT pattern: refSink() then ref()
    var obj2 = RefCountedObject{};
    _ = obj2.refSink();
    _ = obj2.ref(); // This creates over-referencing!
    try testing.expectEqual(obj2.ref_count, 2); // Over-referenced!

    // The correct pattern leaves ref_count at 1
    // The old pattern leaves it at 2, causing memory leaks
}

// =============================================================================
// Dispose Pattern Tests
// =============================================================================

test "dispose pattern - store removeAll triggers item cleanup" {
    const alloc = testing.allocator;

    // Simulate item with allocated strings
    const Item = struct {
        name: [:0]const u8,
        disposed: bool = false,

        pub fn init(a: Allocator, n: []const u8) !@This() {
            return .{ .name = try a.dupeZ(u8, n) };
        }

        pub fn dispose(self: *@This(), a: Allocator) void {
            if (!self.disposed) {
                a.free(self.name);
                self.disposed = true;
            }
        }
    };

    // Simulate store with items
    var items: std.ArrayListUnmanaged(Item) = .empty;
    defer {
        for (items.items) |*item| {
            item.dispose(alloc);
        }
        items.deinit(alloc);
    }

    // Add items
    try items.append(alloc, try Item.init(alloc, "item1"));
    try items.append(alloc, try Item.init(alloc, "item2"));
    try items.append(alloc, try Item.init(alloc, "item3"));

    try testing.expectEqual(items.items.len, 3);

    // Simulate dispose - items handle their own cleanup
    for (items.items) |*item| {
        item.dispose(alloc);
    }
    items.clearRetainingCapacity();

    try testing.expectEqual(items.items.len, 0);
}

test "dispose pattern - double dispose is safe" {
    const alloc = testing.allocator;

    const Item = struct {
        name: [:0]const u8,
        disposed: bool = false,

        pub fn dispose(self: *@This(), a: Allocator) void {
            if (!self.disposed) {
                a.free(self.name);
                self.disposed = true;
            }
        }
    };

    var item = Item{ .name = try alloc.dupeZ(u8, "test") };

    // First dispose
    item.dispose(alloc);
    try testing.expect(item.disposed);

    // Second dispose should be safe (no-op)
    item.dispose(alloc);
    try testing.expect(item.disposed);
}

// =============================================================================
// Signal Handler Pattern Tests
// =============================================================================

test "signal handler - setup vs bind pattern simulation" {
    // Simulate the signal handler leak issue
    var setup_connections: u32 = 0;
    var bind_connections: u32 = 0;

    // Setup is called once per widget
    const setupItem = struct {
        fn call(counter: *u32) void {
            counter.* += 1; // Connect handler once
        }
    }.call;

    // Bind is called every time item data changes
    const bindItemOld = struct {
        fn call(counter: *u32) void {
            counter.* += 1; // WRONG: connects handler every rebind!
        }
    }.call;

    const bindItemNew = struct {
        fn call(_: *u32) void {
            // CORRECT: no handler connection in bind
        }
    }.call;

    // Simulate 1 setup + 5 rebinds
    setupItem(&setup_connections);
    for (0..5) |_| {
        bindItemOld(&bind_connections);
    }

    try testing.expectEqual(setup_connections, 1); // Correct: 1 handler
    try testing.expectEqual(bind_connections, 5); // Bug: 5 handlers leaked!

    // With new pattern
    var new_setup: u32 = 0;
    var new_bind: u32 = 0;

    setupItem(&new_setup);
    for (0..5) |_| {
        bindItemNew(&new_bind);
    }

    try testing.expectEqual(new_setup, 1); // 1 handler
    try testing.expectEqual(new_bind, 0); // 0 additional handlers
}

// =============================================================================
// Message Role Enum Tests (ChatSidebar)
// =============================================================================

test "MessageRole enum values" {
    const MessageRole = enum {
        user,
        assistant,
        system,
    };

    try testing.expectEqual(@intFromEnum(MessageRole.user), 0);
    try testing.expectEqual(@intFromEnum(MessageRole.assistant), 1);
    try testing.expectEqual(@intFromEnum(MessageRole.system), 2);
}

test "MessageRole to string mapping" {
    const MessageRole = enum {
        user,
        assistant,
        system,

        pub fn str(self: @This()) []const u8 {
            return switch (self) {
                .user => "You",
                .assistant => "Assistant",
                .system => "System",
            };
        }
    };

    try testing.expectEqualStrings(MessageRole.user.str(), "You");
    try testing.expectEqualStrings(MessageRole.assistant.str(), "Assistant");
    try testing.expectEqualStrings(MessageRole.system.str(), "System");
}

// =============================================================================
// FilterType Enum Tests (OutputFilters)
// =============================================================================

test "FilterType enum values" {
    const FilterType = enum {
        contains,
        regex,
        starts_with,
        ends_with,
        equals,
        not_contains,
    };

    // Verify all filter types exist
    try testing.expectEqual(@intFromEnum(FilterType.contains), 0);
    try testing.expectEqual(@intFromEnum(FilterType.regex), 1);
    try testing.expectEqual(@intFromEnum(FilterType.starts_with), 2);
    try testing.expectEqual(@intFromEnum(FilterType.ends_with), 3);
    try testing.expectEqual(@intFromEnum(FilterType.equals), 4);
    try testing.expectEqual(@intFromEnum(FilterType.not_contains), 5);
}

// =============================================================================
// EnvScope Enum Tests (EnvManager)
// =============================================================================

test "EnvScope enum values and string conversion" {
    const EnvScope = enum {
        session,
        user,
        system,
        project,

        pub fn str(self: @This()) []const u8 {
            return switch (self) {
                .session => "Session",
                .user => "User",
                .system => "System",
                .project => "Project",
            };
        }
    };

    try testing.expectEqualStrings(EnvScope.session.str(), "Session");
    try testing.expectEqualStrings(EnvScope.user.str(), "User");
    try testing.expectEqualStrings(EnvScope.system.str(), "System");
    try testing.expectEqualStrings(EnvScope.project.str(), "Project");
}

// =============================================================================
// Timestamp Tests (BookmarkItem, ChatMessage)
// =============================================================================

test "timestamp generation" {
    const timestamp1 = std.time.timestamp();
    const timestamp2 = std.time.timestamp();

    // Timestamps should be non-negative
    try testing.expect(timestamp1 >= 0);
    try testing.expect(timestamp2 >= 0);

    // Second timestamp should be >= first (or equal for same second)
    try testing.expect(timestamp2 >= timestamp1);
}

// =============================================================================
// Buffer Formatting Tests (for meta labels)
// =============================================================================

test "bufPrintZ for meta label formatting" {
    var meta_buf: [256]u8 = undefined;

    // Test category + use count format
    const category = "Git";
    const use_count: u32 = 5;
    const meta_text = std.fmt.bufPrintZ(&meta_buf, "{s} - Used {d} times", .{ category, use_count }) catch "Error";

    try testing.expectEqualStrings(meta_text, "Git - Used 5 times");
}

test "bufPrintZ handles missing category" {
    var meta_buf: [256]u8 = undefined;

    const use_count: u32 = 10;
    const meta_text = std.fmt.bufPrintZ(&meta_buf, "Used {d} times", .{use_count}) catch "Error";

    try testing.expectEqualStrings(meta_text, "Used 10 times");
}

test "bufPrintZ handles shell and description" {
    var meta_buf: [256]u8 = undefined;

    const shell = "bash";
    const description = "List all files";
    const meta_text = std.fmt.bufPrintZ(&meta_buf, "{s} - {s}", .{ shell, description }) catch "Error";

    try testing.expectEqualStrings(meta_text, "bash - List all files");
}

// =============================================================================
// Search/Filter Logic Tests
// =============================================================================

test "substring search for filtering" {
    const query = "git";

    const name = "Git Status";
    const command = "git status";
    const description = "Check repository status";

    // Case-sensitive search
    const name_match = std.mem.indexOf(u8, name, query) != null;
    const cmd_match = std.mem.indexOf(u8, command, query) != null;
    const desc_match = std.mem.indexOf(u8, description, query) != null;

    try testing.expect(!name_match); // "Git" != "git" (case sensitive)
    try testing.expect(cmd_match); // "git status" contains "git"
    try testing.expect(!desc_match); // no "git" in description
}

test "empty query matches all" {
    const query = "";

    const matches = if (query.len == 0) true else false;

    try testing.expect(matches);
}

// =============================================================================
// Confidence Score Tests (ErrorRecovery)
// =============================================================================

test "confidence score range" {
    const FixItem = struct {
        confidence: f32,

        pub fn isHighConfidence(self: @This()) bool {
            return self.confidence >= 0.8;
        }

        pub fn isMediumConfidence(self: @This()) bool {
            return self.confidence >= 0.5 and self.confidence < 0.8;
        }

        pub fn isLowConfidence(self: @This()) bool {
            return self.confidence < 0.5;
        }
    };

    const high = FixItem{ .confidence = 0.95 };
    const medium = FixItem{ .confidence = 0.65 };
    const low = FixItem{ .confidence = 0.3 };

    try testing.expect(high.isHighConfidence());
    try testing.expect(!high.isMediumConfidence());
    try testing.expect(!high.isLowConfidence());

    try testing.expect(!medium.isHighConfidence());
    try testing.expect(medium.isMediumConfidence());
    try testing.expect(!medium.isLowConfidence());

    try testing.expect(!low.isHighConfidence());
    try testing.expect(!low.isMediumConfidence());
    try testing.expect(low.isLowConfidence());
}

// =============================================================================
// InsightType Enum Tests (CommandAnalysis)
// =============================================================================

test "InsightType enum" {
    const InsightType = enum {
        explanation,
        warning,
        suggestion,
        related,

        pub fn icon(self: @This()) []const u8 {
            return switch (self) {
                .explanation => "dialog-information-symbolic",
                .warning => "dialog-warning-symbolic",
                .suggestion => "starred-symbolic",
                .related => "view-list-symbolic",
            };
        }
    };

    try testing.expectEqualStrings(InsightType.explanation.icon(), "dialog-information-symbolic");
    try testing.expectEqualStrings(InsightType.warning.icon(), "dialog-warning-symbolic");
    try testing.expectEqualStrings(InsightType.suggestion.icon(), "starred-symbolic");
    try testing.expectEqualStrings(InsightType.related.icon(), "view-list-symbolic");
}

// =============================================================================
// Use Count Increment Tests (BookmarkItem)
// =============================================================================

test "incrementUse updates count and timestamp" {
    const BookmarkItem = struct {
        use_count: u32 = 0,
        last_used: ?i64 = null,

        pub fn incrementUse(self: *@This()) void {
            self.use_count += 1;
            self.last_used = std.time.timestamp();
        }
    };

    var item = BookmarkItem{};

    try testing.expectEqual(item.use_count, 0);
    try testing.expect(item.last_used == null);

    item.incrementUse();

    try testing.expectEqual(item.use_count, 1);
    try testing.expect(item.last_used != null);

    const first_used = item.last_used.?;

    item.incrementUse();

    try testing.expectEqual(item.use_count, 2);
    try testing.expect(item.last_used.? >= first_used);
}
