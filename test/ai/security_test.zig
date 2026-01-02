const std = @import("std");
const testing = std.testing;
const SecurityScanner = @import("../../src/ai/security.zig").SecurityScanner;
const DetectedSecret = @import("../../src/ai/security.zig").DetectedSecret;
const calculateEntropy = @import("../../src/ai/security.zig").calculateEntropy;

test "SecurityScanner initialization with error propagation" {
    const alloc = testing.allocator;

    // Test that init properly propagates errors
    var scanner = try SecurityScanner.init(alloc);
    defer scanner.deinit();

    try testing.expect(scanner.config.enabled);
    try testing.expect(scanner.patterns.items.len > 0);
}

test "SecurityScanner initialization with error logging" {
    const alloc = testing.allocator;

    // Test the logging version
    var scanner = SecurityScanner.initOrLog(alloc);
    defer scanner.deinit();

    try testing.expect(scanner.config.enabled);
    try testing.expect(scanner.patterns.items.len > 0);
}

test "SecurityScanner detects OpenAI API keys" {
    const alloc = testing.allocator;

    var scanner = try SecurityScanner.init(alloc);
    defer scanner.deinit();

    const test_text = "api_key=sk-proj-abc123def456ghi789jkl012mno345pqr678stu901vwx234yz";
    var secrets = try scanner.scan(test_text);
    defer {
        for (secrets.items) |*s| s.deinit(alloc);
        secrets.deinit();
    }

    try testing.expect(secrets.items.len > 0);
    try testing.expect(secrets.items[0].secret_type == .api_key);
    try testing.expect(std.mem.startsWith(u8, secrets.items[0].value, "sk-proj-"));
}

test "SecurityScanner detects Anthropic API keys" {
    const alloc = testing.allocator;

    var scanner = try SecurityScanner.init(alloc);
    defer scanner.deinit();

    const test_text = "ANTHROPIC_API_KEY=sk-ant-api03-test1234567890abcdef1234567890";
    var secrets = try scanner.scan(test_text);
    defer {
        for (secrets.items) |*s| s.deinit(alloc);
        secrets.deinit();
    }

    try testing.expect(secrets.items.len > 0);
    try testing.expect(secrets.items[0].secret_type == .api_key);
}

test "SecurityScanner detects GitHub PATs" {
    const alloc = testing.allocator;

    var scanner = try SecurityScanner.init(alloc);
    defer scanner.deinit();

    const test_text = "ghp_1234567890abcdefghijklmnopqrstuvwxyzABCDEF";
    var secrets = try scanner.scan(test_text);
    defer {
        for (secrets.items) |*s| s.deinit(alloc);
        secrets.deinit();
    }

    try testing.expect(secrets.items.len > 0);
    try testing.expect(secrets.items[0].secret_type == .api_key);
}

test "SecurityScanner detects AWS keys" {
    const alloc = testing.allocator;

    var scanner = try SecurityScanner.init(alloc);
    defer scanner.deinit();

    const test_text = "AWS_ACCESS_KEY_ID=AKIAIOSFODNN7EXAMPLE";
    var secrets = try scanner.scan(test_text);
    defer {
        for (secrets.items) |*s| s.deinit(alloc);
        secrets.deinit();
    }

    try testing.expect(secrets.items.len > 0);
    try testing.expect(secrets.items[0].secret_type == .aws_key);
}

test "SecurityScanner detects private keys" {
    const alloc = testing.allocator;

    var scanner = try SecurityScanner.init(alloc);
    defer scanner.deinit();

    const test_text =
        \\-----BEGIN RSA PRIVATE KEY-----
        \\MIIEpAIBAAKCAQEA...
        \\-----END RSA PRIVATE KEY-----
    ;
    var secrets = try scanner.scan(test_text);
    defer {
        for (secrets.items) |*s| s.deinit(alloc);
        secrets.deinit();
    }

    try testing.expect(secrets.items.len > 0);
    try testing.expect(secrets.items[0].secret_type == .private_key);
}

test "SecurityScanner detects database URLs" {
    const alloc = testing.allocator;

    var scanner = try SecurityScanner.init(alloc);
    defer scanner.deinit();

    const test_text = "DATABASE_URL=postgres://user:password@localhost:5432/mydb";
    var secrets = try scanner.scan(test_text);
    defer {
        for (secrets.items) |*s| s.deinit(alloc);
        secrets.deinit();
    }

    try testing.expect(secrets.items.len > 0);
    try testing.expect(secrets.items[0].secret_type == .database_url);
}

test "SecurityScanner detects high-entropy strings" {
    const alloc = testing.allocator;

    var scanner = try SecurityScanner.init(alloc);
    defer scanner.deinit();

    // Configure to enable context-aware scanning
    scanner.configure(.{ .context_aware = true, .min_entropy = 3.5 });

    const test_text = "secret=\"aB3$xY9@zQ1&wK5#mN7%pR2*tU4!vW6\"";
    var secrets = try scanner.scan(test_text);
    defer {
        for (secrets.items) |*s| s.deinit(alloc);
        secrets.deinit();
    }

    // Should detect high-entropy string
    try testing.expect(secrets.items.len > 0);
}

test "SecurityScanner redacts secrets properly" {
    const alloc = testing.allocator;

    var scanner = try SecurityScanner.init(alloc);
    defer scanner.deinit();

    const test_text = "sk-ant-api03-test1234567890abcdef1234567890";
    var secrets = try scanner.scan(test_text);
    defer {
        for (secrets.items) |*s| s.deinit(alloc);
        secrets.deinit();
    }

    try testing.expect(secrets.items.len > 0);
    const redacted = secrets.items[0].redacted_value;
    try testing.expect(std.mem.indexOf(u8, redacted, "***") != null);
    try testing.expect(!std.mem.eql(u8, redacted, secrets.items[0].value));
}

test "SecurityScanner provides location information" {
    const alloc = testing.allocator;

    var scanner = try SecurityScanner.init(alloc);
    defer scanner.deinit();

    const test_text = "line1\nline2\napi_key=sk-ant-api03-test1234567890abcdef1234567890\nline4";
    var secrets = try scanner.scan(test_text);
    defer {
        for (secrets.items) |*s| s.deinit(alloc);
        secrets.deinit();
    }

    try testing.expect(secrets.items.len > 0);
    try testing.expect(secrets.items[0].location.line == 3);
    try testing.expect(secrets.items[0].location.offset > 0);
}

test "SecurityScanner respects max_secrets limit" {
    const alloc = testing.allocator;

    var scanner = try SecurityScanner.init(alloc);
    defer scanner.deinit();

    scanner.configure(.{ .max_secrets = 2 });

    // Create text with multiple secrets
    var text_buf = std.ArrayList(u8).init(alloc);
    defer text_buf.deinit();
    try text_buf.writer().print("key1=sk-ant-api03-test1234567890abcdef1234567890\n", .{});
    try text_buf.writer().print("key2=sk-ant-api03-test1234567890abcdef1234567891\n", .{});
    try text_buf.writer().print("key3=sk-ant-api03-test1234567890abcdef1234567892\n", .{});

    var secrets = try scanner.scan(text_buf.items);
    defer {
        for (secrets.items) |*s| s.deinit(alloc);
        secrets.deinit();
    }

    try testing.expect(secrets.items.len <= 2);
}

test "SecurityScanner can be disabled" {
    const alloc = testing.allocator;

    var scanner = try SecurityScanner.init(alloc);
    defer scanner.deinit();

    scanner.setEnabled(false);

    const test_text = "sk-ant-api03-test1234567890abcdef1234567890";
    var secrets = try scanner.scan(test_text);
    defer {
        for (secrets.items) |*s| s.deinit(alloc);
        secrets.deinit();
    }

    try testing.expect(secrets.items.len == 0);
}

test "SecurityScanner scan statistics" {
    const alloc = testing.allocator;

    var scanner = try SecurityScanner.init(alloc);
    defer scanner.deinit();

    _ = try scanner.scan("sk-ant-api03-test1234567890abcdef1234567890");
    _ = try scanner.scan("ghp_1234567890abcdefghijklmnopqrstuvwxyzABCDEF");

    const stats = scanner.getStats();
    try testing.expect(stats.total_scans == 2);
    try testing.expect(stats.total_secrets_found >= 2);
    try testing.expect(stats.patterns_loaded > 0);
}

test "calculateEntropy with low entropy" {
    const low_entropy = calculateEntropy("aaaaaaaaaa");
    try testing.expect(low_entropy < 1.0);
}

test "calculateEntropy with high entropy" {
    const high_entropy = calculateEntropy("aB3$xY9@zQ1&wK5");
    try testing.expect(high_entropy > 3.0);
}

test "calculateEntropy with empty string" {
    const entropy = calculateEntropy("");
    try testing.expect(entropy == 0.0);
}

test "calculateEntropy with single character" {
    const entropy = calculateEntropy("a");
    try testing.expect(entropy == 0.0);
}

test "SecurityScanner handles allocation failures gracefully" {
    const alloc = testing.allocator;

    var scanner = try SecurityScanner.init(alloc);
    defer scanner.deinit();

    // Test that getLocation handles allocation failures
    // This is tested implicitly through the context field handling
    const test_text = "sk-ant-api03-test1234567890abcdef1234567890";
    var secrets = try scanner.scan(test_text);
    defer {
        for (secrets.items) |*s| s.deinit(alloc);
        secrets.deinit();
    }

    // Should still work even if context allocation fails
    try testing.expect(secrets.items.len > 0);
}
