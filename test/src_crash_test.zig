// src/crash/main_test.zig
const std = @import("std");
const testing = std.testing;
const main = @import("main.zig");
const dir = @import("dir.zig");
const sentry = @import("sentry.zig");

const MockCrashHandler = struct {
    const Self = @This();
    
    crash_reports: std.ArrayList(main.CrashReport),
    allocator: std.mem.Allocator,
    
    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .crash_reports = std.ArrayList(main.CrashReport).init(allocator),
            .allocator = allocator,
        };
    }
    
    pub fn deinit(self: *Self) void {
        self.crash_reports.deinit();
    }
    
    pub fn handleCrash(self: *Self, report: main.CrashReport) !void {
        try self.crash_reports.append(report);
    }
};

test "CrashReport initialization" {
    const allocator = testing.allocator;
    
    var report = try main.CrashReport.init(allocator);
    defer report.deinit();
    
    try testing.expect(report.timestamp > 0);
    try testing.expect(report.signal == 0);
    try testing.expect(report.stack_trace.items.len == 0);
}

test "CrashReport signal handling" {
    const allocator = testing.allocator;
    
    var report = try main.CrashReport.init(allocator);
    defer report.deinit();
    
    report.signal = std.os.SIG.SIGSEGV;
    report.pid = std.os.getCurrentId();
    
    try testing.expect(report.signal == std.os.SIG.SIGSEGV);
    try testing.expect(report.pid > 0);
}

test "CrashReport stack trace capture" {
    const allocator = testing.allocator;
    
    var report = try main.CrashReport.init(allocator);
    defer report.deinit();
    
    try report.captureStackTrace();
    
    try testing.expect(report.stack_trace.items.len > 0);
}

test "CrashReport serialization" {
    const allocator = testing.allocator;
    
    var report = try main.CrashReport.init(allocator);
    defer report.deinit();
    
    report.signal = std.os.SIG.SIGABRT;
    report.pid = 12345;
    try report.stack_trace.append(0x12345678);
    
    const json = try report.toJson(allocator);
    defer allocator.free(json);
    
    try testing.expect(std.mem.indexOf(u8, json, "\"signal\":6") != null);
    try testing.expect(std.mem.indexOf(u8, json, "\"pid\":12345") != null);
}

test "CrashHandler initialization" {
    const allocator = testing.allocator;
    
    var handler = try main.CrashHandler.init(allocator);
    defer handler.deinit();
    
    try testing.expect(handler.initialized);
    try testing.expect(handler.crash_dir != null);
}

test "CrashHandler signal registration" {
    const allocator = testing.allocator;
    
    var handler = try main.CrashHandler.init(allocator);
    defer handler.deinit();
    
    const signals = [_]std.os.SIG{ std.os.SIG.SIGSEGV, std.os.SIG.SIGABRT, std.os.SIG.SIGFPE };
    
    for (signals) |sig| {
        const registered = handler.isSignalRegistered(sig);
        try testing.expect(registered);
    }
}

test "CrashHandler report generation" {
    const allocator = testing.allocator;
    
    var handler = try main.CrashHandler.init(allocator);
    defer handler.deinit();
    
    var report = try handler.generateReport(std.os.SIG.SIGSEGV);
    defer report.deinit();
    
    try testing.expect(report.signal == std.os.SIG.SIGSEGV);
    try testing.expect(report.timestamp > 0);
}

test "CrashHandler file dump" {
    const allocator = testing.allocator;
    
    var tmp_dir = testing.tmpDir(.{});
    defer tmp_dir.cleanup();
    
    var handler = try main.CrashHandler.initWithDir(allocator, tmp_dir.dir);
    defer handler.deinit();
    
    var report = try handler.generateReport(std.os.SIG.SIGBUS);
    defer report.deinit();
    
    const filename = try handler.dumpReport(&report);
    defer allocator.free(filename);
    
    const file_path = try std.fs.path.join(allocator, &.{ tmp_dir.dir_path, filename });
    defer allocator.free(file_path);
    
    const file = try tmp_dir.dir.openFile(filename, .{});
    defer file.close();
    
    const contents = try file.readToEndAlloc(allocator, 1024 * 1024);
    defer allocator.free(contents);
    
    try testing.expect(contents.len > 0);
    try testing.expect(std.mem.indexOf(u8, contents, "\"signal\":10") != null);
}

test "CrashHandler error recovery" {
    const allocator = testing.allocator;
    
    var handler = try main.CrashHandler.init(allocator);
    defer handler.deinit();
    
    // Test with invalid directory
    const invalid_path = "/invalid/path/that/does/not/exist";
    var result = handler.setCrashDir(invalid_path);
    try testing.expectError(error.FileNotFound, result);
    
    // Test recovery with valid directory
    var tmp_dir = testing.tmpDir(.{});
    defer tmp_dir.cleanup();
    
    result = handler.setCrashDir(tmp_dir.dir_path);
    try testing.expect(result == void);
}

test "CrashHandler concurrent reports" {
    const allocator = testing.allocator;
    
    var handler = try main.CrashHandler.init(allocator);
    defer handler.deinit();
    
    const num_threads = 4;
    const reports_per_thread = 10;
    
    var threads: [num_threads]std.Thread = undefined;
    var reports: [num_threads][reports_per_thread]main.CrashReport = undefined;
    
    for (0..num_threads) |i| {
        threads[i] = try std.Thread.spawn(.{}, struct {
            fn run(idx: usize, h: *main.CrashHandler, out: *[reports_per_thread]main.CrashReport) !void {
                for (0..reports_per_thread) |j| {
                    out[j] = try h.generateReport(@intCast(std.os.SIG.SIGSEGV + j % 3));
                }
            }
        }.run, .{ i, &handler, &reports[i] });
    }
    
    for (threads) |thread| {
        thread.join();
    }
    
    for (reports) |thread_reports| {
        for (thread_reports) |report| {
            defer report.deinit();
            try testing.expect(report.signal != 0);
            try testing.expect(report.timestamp > 0);
        }
    }
}

test "CrashHandler memory cleanup" {
    const allocator = testing.allocator;
    
    {
        var handler = try main.CrashHandler.init(allocator);
        defer handler.deinit();
        
        _ = try handler.generateReport(std.os.SIG.SIGILL);
    }
    
    // Verify no memory leaks after handler destruction
    try testing.expect(true);
}

// src/crash/dir_test.zig
const std = @import("std");
const testing = std.testing;
const dir = @import("dir.zig");

test "CrashDir initialization" {
    const allocator = testing.allocator;
    
    var tmp_dir = testing.tmpDir(.{});
    defer tmp_dir.cleanup();
    
    var crash_dir = try dir.CrashDir.init(allocator, tmp_dir.dir_path);
    defer crash_dir.deinit();
    
    try testing.expect(crash_dir.path != null);
    try testing.expect(std.mem.eql(u8, crash_dir.path.?, tmp_dir.dir_path));
}

test "CrashDir creation" {
    const allocator = testing.allocator;
    
    var tmp_dir = testing.tmpDir(.{});
    defer tmp_dir.cleanup();
    
    const crash_path = try std.fs.path.join(allocator, &.{ tmp_dir.dir_path, "crashes" });
    defer allocator.free(crash_path);
    
    var crash_dir = try dir.CrashDir.create(allocator, crash_path);
    defer crash_dir.deinit();
    
    var dir_handle = try tmp_dir.dir.openDir("crashes", .{});
    defer dir_handle.close();
    
    try testing.expect(true);
}

test "CrashDir exists check" {
    const allocator = testing.allocator;
    
    var tmp_dir = testing.tmpDir(.{});
    defer tmp_dir.cleanup();
    
    // Test non-existent directory
    const non_existent = try std.fs.path.join(allocator, &.{ tmp_dir.dir_path, "nonexistent" });
    defer allocator.free(non_existent);
    
    try testing.expect(!try dir.CrashDir.exists(non_existent));
    
    // Test existing directory
    var crash_dir = try dir.CrashDir.create(allocator, non_existent);
    defer crash_dir.deinit();
    
    try testing.expect(try dir.CrashDir.exists(non_existent));
}

test "CrashDir cleanup" {
    const allocator = testing.allocator;
    
    var tmp_dir = testing.tmpDir(.{});
    defer tmp_dir.cleanup();
    
    const crash_path = try std.fs.path.join(allocator, &.{ tmp_dir.dir_path, "cleanup_test" });
    defer allocator.free(crash_path);
    
    var crash_dir = try dir.CrashDir.create(allocator, crash_path);
    defer crash_dir.deinit();
    
    // Create some test files
    const test_files = [_][]const u8{ "crash1.json", "crash2.json", "crash3.json" };
    for (test_files) |filename| {
        const file = try crash_dir.dir.createFile(filename, .{});
        file.close();
    }
    
    try crash_dir.cleanup(.{ .max_age_seconds = 0, .max_files = 2 });
    
    // Should have only 2 files remaining
    var entries = try crash_dir.dir.iterate();
    defer entries.deinit();
    
    var count: usize = 0;
    while (try entries.next()) |entry| {
        if (entry.kind == .file) count += 1;
    }
    
    try testing.expect(count == 2);
}

test "CrashDir file listing" {
    const allocator = testing.allocator;
    
    var tmp_dir = testing.tmpDir(.{});
    defer tmp_dir.cleanup();
    
    var crash_dir = try dir.CrashDir.create(allocator, tmp_dir.dir_path);
    defer crash_dir.deinit();
    
    const test_files = [_][]const u8{ "a.json", "b.json", "c.json" };
    for (test_files) |filename| {
        const file = try crash_dir.dir.createFile(filename, .{});
        file.close();
    }
    
    var files = try crash_dir.listFiles(allocator, ".json");
    defer files.deinit();
    
    try testing.expect(files.items.len == 3);
    
    std.sort.sort([]const u8, files.items, {}, struct {
        fn lessThan(_: void, a: []const u8, b: []const u8) bool {
            return std.mem.lessThan(u8, a, b);
        }
    }.lessThan);
    
    try testing.expect(std.mem.eql(u8, files.items[0], "a.json"));
    try testing.expect(std.mem.eql(u8, files.items[1], "b.json"));
    try testing.expect(std.mem.eql(u8, files.items[2], "c.json"));
}

test "CrashDir file creation" {
    const allocator = testing.allocator;
    
    var tmp_dir = testing.tmpDir(.{});
    defer tmp_dir.cleanup();
    
    var crash_dir = try dir.CrashDir.create(allocator, tmp_dir.dir_path);
    defer crash_dir.deinit();
    
    const filename = try crash_dir.generateFilename();
    defer allocator.free(filename);
    
    try testing.expect(std.mem.endsWith(u8, filename, ".json"));
    
    const file_path = try crash_dir.createFile(filename, "test content");
    defer allocator.free(file_path);
    
    const file = try crash_dir.dir.openFile(filename, .{});
    defer file.close();
    
    const contents = try file.readToEndAlloc(allocator, 1024);
    defer allocator.free(contents);
    
    try testing.expect(std.mem.eql(u8, contents, "test content"));
}

test "CrashDir permissions" {
    const allocator = testing.allocator;
    
    var tmp_dir = testing.tmpDir(.{});
    defer tmp_dir.cleanup();
    
    var crash_dir = try dir.CrashDir.create(allocator, tmp_dir.dir_path);
    defer crash_dir.deinit();
    
    const stat = try crash_dir.dir.stat();
    try testing.expect(stat.kind == .directory);
    
    // Test that directory is readable and writable
    const test_file = try crash_dir.dir.createFile("permission_test", .{});
    test_file.close();
    
    var file = try crash_dir.dir.openFile("permission_test", .{});
    file.close();
}

test "CrashDir error handling" {
    const allocator = testing.allocator;
    
    // Test with invalid path
    const invalid_path = "/root/invalid/path";
    
    var result = dir.CrashDir.create(allocator, invalid_path);
    try testing.expectError(error.AccessDenied, result);
    
    // Test with null path
    result = dir.CrashDir.create(allocator, "");
    try testing.expectError(error.InvalidPath, result);
}

test "CrashDir concurrent access" {
    const allocator = testing.allocator;
    
    var tmp_dir = testing.tmpDir(.{});
    defer tmp_dir.cleanup();
    
    var crash_dir = try dir.CrashDir.create(allocator, tmp_dir.dir_path);
    defer crash_dir.deinit();
    
    const num_threads = 4;
    const files_per_thread = 10;
    
    var threads: [num_threads]std.Thread = undefined;
    var filenames: [num_threads][files_per_thread][]u8 = undefined;
    
    for (0..num_threads) |i| {
        threads[i] = try std.Thread.spawn(.{}, struct {
            fn run(idx: usize, cd: *dir.CrashDir, out: *[files_per_thread][]u8, alloc: std.mem.Allocator) !void {
                for (0..files_per_thread) |j| {
                    out[j] = try cd.generateFilename();
                    _ = try cd.createFile(out[j], "test");
                }
            }
        }.run, .{ i, &crash_dir, &filenames[i], allocator });
    }
    
    for (threads) |thread| {
        thread.join();
    }
    
    // Verify all files were created
    var files = try crash_dir.listFiles(allocator, ".json");
    defer files.deinit();
    
    try testing.expect(files.items.len == num_threads * files_per_thread);
    
    // Cleanup
    for (filenames) |thread_files| {
        for (thread_files) |filename| {
            allocator.free(filename);
        }
    }
}

// src/crash/sentry_test.zig
const std = @import("std");
const testing = std.testing;
const sentry = @import("sentry.zig");

const MockHttpClient = struct {
    const Self = @This();
    
    responses: std.ArrayList(sentry.HttpResponse),
    requests: std.ArrayList(sentry.HttpRequest),
    allocator: std.mem.Allocator,
    
    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .responses = std.ArrayList(sentry.HttpResponse).init(allocator),
            .requests = std.ArrayList(sentry.HttpRequest).init(allocator),
            .allocator = allocator,
        };
    }
    
    pub fn deinit(self: *Self) void {
        self.responses.deinit();
        self.requests.deinit();
    }
    
    pub fn addResponse(self: *Self, response: sentry.HttpResponse) !void {
        try self.responses.append(response);
    }
    
    pub fn send(self: *Self, request: sentry.HttpRequest) !sentry.HttpResponse {
        try self.requests.append(request);
        if (self.responses.items.len > 0) {
            const response = self.responses.orderedRemove(0);
            return response;
        }
        return sentry.HttpResponse{
            .status_code = 200,
            .body = "OK",
        };
    }
};

test "SentryClient initialization" {
    const allocator = testing.allocator;
    
    var client = try sentry.SentryClient.init(allocator, "https://test@sentry.io/123456");
    defer client.deinit();
    
    try testing.expect(client.dsn != null);
    try testing.expect(std.mem.startsWith(u8, client.dsn.?, "https://"));
}

test "SentryClient invalid DSN" {
    const allocator = testing.allocator;
    
    const invalid_dsns = [_][]const u8{
        "invalid-dsn",
        "http://insecure@sentry.io/123",
        "https://sentry.io",
        "",
    };
    
    for (invalid_dsns) |dsn| {
        var result = sentry.SentryClient.init(allocator, dsn);
        try testing.expectError(error.InvalidDsn, result);
    }
}

test "SentryClient event creation" {
    const allocator = testing.allocator;
    
    var client = try sentry.SentryClient.init(allocator, "https://test@sentry.io/123456");
    defer client.deinit();
    
    var event = try client.createEvent("test message", .error);
    defer event.deinit();
    
    try testing.expect(std.mem.eql(u8, event.message, "test message"));
    try testing.expect(event.level == .error);
    try testing.expect(event.timestamp > 0);
}

test "SentryClient event with exception" {
    const allocator = testing.allocator;
    
    var client = try sentry.SentryClient.init(allocator, "https://test@sentry.io/123456");
    defer client.deinit();
    
    var exception = sentry.Exception{
        .type = "SIGSEGV",
        .value = "Segmentation fault",
        .stacktrace = &[_]u64{ 0x1234, 0x5678, 0x9abc },
    };
    
    var event = try client.createEventWithException("Crash detected", .fatal, exception);
    defer event.deinit();
    
    try testing.expect(event.exception != null);
    try testing.expect(std.mem.eql(u8, event.exception.?.type, "SIGSEGV"));
}

test "SentryClient event serialization" {
    const allocator = testing.allocator;
    
    var client = try sentry.SentryClient.init(allocator, "https://test@sentry.io/123456");
    defer client.deinit();
    
    var event = try client.createEvent("test event", .warning);
    defer event.deinit();
    
    try event.addTag("environment", "test");
    try event.addExtra("test_key", "test_value");
    
    const json = try event.toJson(allocator);
    defer allocator.free(json);
    
    try testing.expect(std.mem.indexOf(u8, json, "\"message\":\"test event\"") != null);
    try testing.expect(std.mem.indexOf(u8, json, "\"level\":\"warning\"") != null);
    try testing.expect(std.mem.indexOf(u8, json, "\"environment\":\"test\"") != null);
}

test "SentryClient submission success" {
    const allocator = testing.allocator;
    
    var mock_http = MockHttpClient.init(allocator);
    defer mock_http.deinit();
    
    try mock_http.addResponse(.{
        .status_code = 200,
        .body = "{\"id\":\"test-id\"}",
    });
    
    var client = try sentry.SentryClient.initWithHttp(allocator, "https://test@sentry.io/123456", mock_http.send);
    defer client.deinit();
    
    var event = try client.createEvent("test submission", .info);
    defer event.deinit();
    
    const result = try client.submitEvent(&event);
    try testing.expect(result.status_code == 200);
    try testing.expect(mock_http.requests.items.len == 1);
}

test "SentryClient submission failure" {
    const allocator = testing.allocator;
    
    var mock_http = MockHttpClient.init(allocator);
    defer mock_http.deinit();
    
    try mock_http.addResponse(.{
        .status_code = 400,
        .body = "Bad Request",
    });
    
    var client = try sentry.SentryClient.initWithHttp(allocator, "https://test@sentry.io/123456", mock_http.send);
    defer client.deinit();
    
    var event = try client.createEvent("test failure", .error);
    defer event.deinit();
    
    const result = try client.submitEvent(&event);
    try testing.expect(result.status_code == 400);
}

test "SentryClient retry mechanism" {
    const allocator = testing.allocator;
    
    var mock_http = MockHttpClient.init(allocator);
    defer mock_http.deinit();
    
    // First two attempts fail, third succeeds
    try mock_http.addResponse(.{ .status_code = 500, .body = "Server Error" });
    try mock_http.addResponse(.{ .status_code = 503, .body = "Service Unavailable" });
    try mock_http.addResponse(.{ .status_code = 200, .body = "OK" });
    
    var client = try sentry.SentryClient.initWithHttp(allocator, "https://test@sentry.io/123456", mock_http.send);
    defer client.deinit();
    
    var event = try client.createEvent("retry test", .error);
    defer event.deinit();
    
    const result = try client.submitEventWithRetry(&event, 3);
    try testing.expect(result.status_code == 200);
    try testing.expect(mock_http.requests.items.len == 3);
}

test "SentryClient rate limiting" {
    const allocator = testing.allocator;
    
    var mock_http = MockHttpClient.init(allocator);
    defer mock_http.deinit();
    
    try mock_http.addResponse(.{
        .status_code = 429,
        .body = "Rate Limited",
        .headers = std.StringHashMap([]const u8).init(allocator),
    });
    
    var client = try sentry.SentryClient.initWithHttp(allocator, "https://test@sentry.io/123456", mock_http.send);
    defer client.deinit();
    
    var event = try client.createEvent("rate limit test", .warning);
    defer event.deinit();
    
    const result = try client.submitEvent(&event);
    try testing.expect(result.status_code == 429);
}

test "SentryClient breadcrumb tracking" {
    const allocator = testing.allocator;
    
    var client = try sentry.SentryClient.init(allocator, "https://test@sentry.io/123456");
    defer client.deinit();
    
    try client.addBreadcrumb("user action", .info, "user clicked button");
    try client.addBreadcrumb("navigation", .debug, "page loaded");
    
    try testing.expect(client.breadcrumbs.items.len == 2);
    try testing.expect(std.mem.eql(u8, client.breadcrumbs.items[0].message, "user action"));
    try testing.expect(client.breadcrumbs.items[0].level == .info);
}

test "SentryClient user context" {
    const allocator = testing.allocator;
    
    var client = try sentry.SentryClient.init(allocator, "https://test@sentry.io/123456");
    defer client.deinit();
    
    try client.setUserContext(.{
        .id = "user123",
        .email = "test@example.com",
        .username = "testuser",
    });
    
    try testing.expect(client.user_context != null);
    try testing.expect(std.mem.eql(u8, client.user_context.?.id, "user123"));
}

test "SentryClient tags and extras" {
    const allocator = testing.allocator;
    
    var client = try sentry.SentryClient.init(allocator, "https://test@sentry.io/123456");
    defer client.deinit();
    
    try client.setTag("version", "1.0.0");
    try client.setTag("build", "debug");
    try client.setExtra("memory_usage", "256MB");
    try client.setExtra("cpu_cores", "8");
    
    try testing.expect(client.tags.count() == 2);
    try testing.expect(client.extras.count() == 2);
    
    const version = client.tags.get("version").?;
    try testing.expect(std.mem.eql(u8, version, "1.0.0"));
}

test "SentryClient error handling" {
    const allocator = testing.allocator;
    
    var client = try sentry.SentryClient.init(allocator, "https://test@sentry.io/123456");
    defer client.deinit();
    
    // Test with null event
    var result = client.submitEvent(null);
    try testing.expectError(error.InvalidEvent, result);
    
    // Test with oversized event
    var large_event = try client.createEvent("large event", .error);
    defer large_event.deinit();
    
    var large_data = try allocator.alloc(u8, 1024 * 1024);
    defer allocator.free(large_data);
    @memset(large_data, 'x');
    
    try large_event.addExtra("large_data", large_data);
    
    result = client.submitEvent(&large_event);
    try testing.expectError(error.EventTooLarge, result);
}

// src/crash/sentry_envelope_test.zig
const std = @import("std");
const testing = std.testing;
const sentry_envelope = @import("sentry_envelope.zig");

test "Envelope initialization" {
    const allocator = testing.allocator;
    
    var envelope = try sentry_envelope.Envelope.init(allocator);
    defer envelope.deinit();
    
    try testing.expect(envelope.event_id.len == 32);
    try testing.expect(envelope.items.items.len == 0);
}

test "Envelope event ID generation" {
    const allocator = testing.allocator;
    
    var envelope1 = try sentry_envelope.Envelope.init(allocator);
    defer envelope1.deinit();
    
    var envelope2 = try sentry_envelope.Envelope.init(allocator);
    defer envelope2.deinit();
    
    try testing.expect(!std.mem.eql(u8, envelope1.event_id, envelope2.event_id));
    try testing.expect(envelope1.event_id.len == 32);
}

test "Envelope adding event item" {
    const allocator = testing.allocator;
    
    var envelope = try sentry_envelope.Envelope.init(allocator);
    defer envelope.deinit();
    
    const event_json = "{\"message\":\"test\",\"level\":\"error\"}";
    try envelope.addEvent(event_json);
    
    try testing.expect(envelope.items.items.len == 1);
    try testing.expect(envelope.items.items[0].type == .event);
    try testing.expect(std.mem.eql(u8, envelope.items.items[0].data, event_json));
}

test "Envelope adding attachment" {
    const allocator = testing.allocator;
    
    var envelope = try sentry_envelope.Envelope.init(allocator);
    defer envelope.deinit();
    
    const attachment_data = "crash log content";
    try envelope.addAttachment("crash.log", attachment_data);
    
    try testing.expect(envelope.items.items.len == 1);
    try testing.expect(envelope.items.items[0].type == .attachment);
    try testing.expect(std.mem.eql(u8, envelope.items.items[0].filename.?, "crash.log"));
}

test "Envelope adding breadcrumb" {
    const allocator = testing.allocator;
    
    var envelope = try sentry_envelope.Envelope.init(allocator);
    defer envelope.deinit();
    
    const breadcrumb_json = "{\"message\":\"user action\",\"timestamp\":1234567890}";
    try envelope.addBreadcrumb(breadcrumb_json);
    
    try testing.expect(envelope.items.items.len == 1);
    try testing.expect(envelope.items.items[0].type == .breadcrumb);
}

test "Envelope serialization" {
    const allocator = testing.allocator;
    
    var envelope = try sentry_envelope.Envelope.init(allocator);
    defer envelope.deinit();
    
    try envelope.addEvent("{\"message\":\"test\"}");
    try envelope.addAttachment("test.log", "log content");
    
    const serialized = try envelope.serialize(allocator);
    defer allocator.free(serialized);
    
    // Check envelope header
    try testing.expect(std.mem.startsWith(u8, serialized, "{\"event_id\":\""));
    try testing.expect(std.mem.endsWith(u8, serialized, "\n"));
    
    // Check item separators
    const parts = std.mem.split(u8, serialized, "\n");
    var count: usize = 0;
    while (parts.next()) |_| count += 1;
    
    try testing.expect(count >= 3); // header + event + attachment
}

test "Envelope item headers" {
    const allocator = testing.allocator;
    
    var envelope = try sentry_envelope.Envelope.init(allocator);
    defer envelope.deinit();
    
    try envelope.addEvent("{\"message\":\"test\"}");
    
    const serialized = try envelope.serialize(allocator);
    defer allocator.free(serialized);
    
    // Check for item header
    try testing.expect(std.mem.indexOf(u8, serialized, "{\"type\":\"event\"") != null);
    try testing.expect(std.mem.indexOf(u8, serialized, "\"content_type\":\"application/json\"") != null);
}

test "Envelope size limits" {
    const allocator = testing.allocator;
    
    var envelope = try sentry_envelope.Envelope.init(allocator);
    defer envelope.deinit();
    
    // Add large attachment
    var large_data = try allocator.alloc(u8, sentry_envelope.MAX_ENVELOPE_SIZE + 1);
    defer allocator.free(large_data);
    @memset(large_data, 'x');
    
    var result = envelope.addAttachment("large.log", large_data);
    try testing.expectError(error.EnvelopeTooLarge, result);
}

test "Envelope multiple items" {
    const allocator = testing.allocator;
    
    var envelope = try sentry_envelope.Envelope.init(allocator);
    defer envelope.deinit();
    
    try envelope.addEvent("{\"message\":\"main event\"}");
    try envelope.addBreadcrumb("{\"message\":\"breadcrumb 1\"}");
    try envelope.addBreadcrumb("{\"message\":\"breadcrumb 2\"}");
    try envelope.addAttachment("minidump.dmp", "dump content");
    
    try testing.expect(envelope.items.items.len == 4);
    
    const serialized = try envelope.serialize(allocator);
    defer allocator.free(serialized);
    
    // Verify all items are present
    try testing.expect(std.mem.indexOf(u8, serialized, "\"type\":\"event\"") != null);
    try testing.expect(std.mem.indexOf(u8, serialized, "\"type\":\"breadcrumb\"") != null);
    try testing.expect(std.mem.indexOf(u8, serialized, "\"type\":\"attachment\"") != null);
}

test "Envelope compression" {
    const allocator = testing.allocator;
    
    var envelope = try sentry_envelope.Envelope.init(allocator);
    defer envelope.deinit();
    
    // Add enough data to make compression worthwhile
    var large_content = try allocator.alloc(u8, 10000);
    defer allocator.free(large_content);
    @memset(large_content, 'x');
    
    try envelope.addAttachment("large.log", large_content);
    
    const compressed = try envelope.serializeCompressed(allocator);
    defer allocator.free(compressed);
    
    const uncompressed = try envelope.serialize(allocator);
    defer allocator.free(uncompressed);
    
    try testing.expect(compressed.len < uncompressed.len);
}

test "Envelope validation" {
    const allocator = testing.allocator;
    
    var envelope = try sentry_envelope.Envelope.init(allocator);
    defer envelope.deinit();
    
    // Empty envelope should be invalid
    try testing.expectError(error.EmptyEnvelope, envelope.validate());
    
    try envelope.addEvent("{\"message\":\"test\"}");
    
    // Valid envelope
    try envelope.validate();
    
    // Add invalid JSON
    try envelope.addAttachment("test.log", "content");
    envelope.items.items[1].data = "invalid json{";
    
    try testing.expectError(error.InvalidJson, envelope.validate());
}

test "Envelope metadata" {
    const allocator = testing.allocator;
    
    var envelope = try sentry_envelope.Envelope.init(allocator);
    defer envelope.deinit();
    
    try envelope.setMetadata("sdk", "ghostty/1.0.0");
    try envelope.setMetadata("platform", "native");
    
    const serialized = try envelope.serialize(allocator);
    defer allocator.free(serialized);
    
    try testing.expect(std.mem.indexOf(u8, serialized, "\"sdk\":{\"name\":\"ghostty\",\"version\":\"1.0.0\"}") != null);
    try testing.expect(std.mem.indexOf(u8, serialized, "\"platform\":\"native\"") != null);
}

test "Envelope rate limit headers" {
    const allocator = testing.allocator;
    
    var envelope = try sentry_envelope.Envelope.init(allocator);
    defer envelope.deinit();
    
    try envelope.addEvent("{\"message\":\"test\"}");
    
    const headers = try envelope.getRateLimitHeaders(allocator);
    defer {
        for (headers.keys()) |key| {
            allocator.free(key);
        }
        for (headers.values()) |value| {
            allocator.free(value);
        }
        headers.deinit();
    }
    
    try testing.expect(headers.count() > 0);
}

test "Envelope error handling" {
    const allocator = testing.allocator;
    
    var envelope = try sentry_envelope.Envelope.init(allocator);
    defer envelope.deinit();
    
    // Test adding null data
    var result = envelope.addAttachment("test.log", "");
    try testing.expectError(error.EmptyData, result);
    
    // Test invalid filename
    result = envelope.addAttachment("", "content");
    try testing.expectError(error.InvalidFilename, result);
    
    // Test too many items
    for (0..sentry_envelope.MAX_ITEMS + 1) |i| {
        const filename = try std.fmt.allocPrint(allocator, "file{}.log", .{i});
        defer allocator.free(filename);
        
        if (i < sentry_envelope.MAX_ITEMS) {
            try envelope.addAttachment(filename, "content");
        } else {
            result = envelope.addAttachment(filename, "content");
            try testing.expectError(error.TooManyItems, result);
        }
    }
}

test "Envelope concurrent access" {
    const allocator = testing.allocator;
    
    var envelope = try sentry_envelope.Envelope.init(allocator);
    defer envelope.deinit();
    
    const num_threads = 4;
    const items_per_thread = 10;
    
    var threads: [num_threads]std.Thread = undefined;
    
    for (0..num_threads) |i| {
        threads[i] = try std.Thread.spawn(.{}, struct {
            fn run(e: *sentry_envelope.Envelope, thread_id: usize) !void {
                for (0..items_per_thread) |j| {
                    const filename = try std.fmt.allocPrint(e.allocator, "thread{}/item{}.log", .{ thread_id, j });
                    defer e.allocator.free(filename);
                    _ = e.addAttachment(filename, "content") catch {};
                }
            }
        }.run, .{ &envelope, i });
    }
    
    for (threads) |thread| {
        thread.join();
    }
    
    // Verify envelope is still valid
    if (envelope.items.items.len > 0) {
        try envelope.validate();
    }
}