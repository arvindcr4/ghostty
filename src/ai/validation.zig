//! Command Validation Module
//!
//! This module provides pre-execution safety checks for commands.

const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

const log = std.log.scoped(.ai_validation);

/// Validation result
pub const ValidationResult = struct {
    valid: bool,
    warnings: ArrayList([]const u8),
    errors: ArrayList([]const u8),
    risk_level: RiskLevel,

    pub const RiskLevel = enum {
        safe,
        low,
        medium,
        high,
        dangerous,
    };

    pub fn init() ValidationResult {
        return .{
            .valid = true,
            .warnings = .{},
            .errors = .{},
            .risk_level = .safe,
        };
    }

    pub fn deinit(self: *ValidationResult, alloc: Allocator) void {
        for (self.warnings.items) |w| alloc.free(w);
        self.warnings.deinit(alloc);
        for (self.errors.items) |e| alloc.free(e);
        self.errors.deinit(alloc);
    }
};

/// Command Validator
pub const CommandValidator = struct {
    alloc: Allocator,
    enabled: bool,
    allow_dangerous: bool,

    /// Initialize command validator
    pub fn init(alloc: Allocator) CommandValidator {
        return .{
            .alloc = alloc,
            .enabled = true,
            .allow_dangerous = false,
        };
    }

    /// Validate a command
    pub fn validate(self: *const CommandValidator, command: []const u8) !ValidationResult {
        var result = ValidationResult.init();
        errdefer result.deinit(self.alloc);

        if (!self.enabled) {
            result.valid = true;
            return result;
        }

        // Check for dangerous patterns
        const dangerous_patterns = [_]struct {
            pattern: []const u8,
            risk: ValidationResult.RiskLevel,
            message: []const u8,
        }{
            .{ .pattern = "rm -rf /", .risk = .dangerous, .message = "Dangerous: Removing root filesystem" },
            .{ .pattern = "rm -rf ~", .risk = .dangerous, .message = "Dangerous: Removing home directory" },
            .{ .pattern = "dd if=", .risk = .high, .message = "High risk: Disk operations" },
            .{ .pattern = "mkfs", .risk = .high, .message = "High risk: Filesystem creation" },
            .{ .pattern = "fdisk", .risk = .high, .message = "High risk: Partition operations" },
            .{ .pattern = "chmod 777", .risk = .medium, .message = "Warning: Overly permissive permissions" },
            .{ .pattern = "sudo rm", .risk = .medium, .message = "Warning: Elevated deletion" },
            .{ .pattern = "> /dev/sd", .risk = .high, .message = "High risk: Writing to block device" },
        };

        for (dangerous_patterns) |danger| {
            if (std.mem.indexOf(u8, command, danger.pattern)) |_| {
                if (@intFromEnum(danger.risk) > @intFromEnum(result.risk_level)) {
                    result.risk_level = danger.risk;
                }

                if (danger.risk == .dangerous) {
                    try result.errors.append(self.alloc, try self.alloc.dupe(u8, danger.message));
                    // Only invalidate if dangerous commands are not allowed
                    if (!self.allow_dangerous) {
                        result.valid = false;
                    }
                } else {
                    try result.warnings.append(self.alloc, try self.alloc.dupe(u8, danger.message));
                }
            }
        }

        // Check for sudo usage
        if (std.mem.startsWith(u8, command, "sudo ")) {
            if (@intFromEnum(ValidationResult.RiskLevel.medium) > @intFromEnum(result.risk_level)) {
                result.risk_level = .medium;
            }
            try result.warnings.append(self.alloc, try self.alloc.dupe(u8, "Warning: Command requires elevated privileges"));
        }

        // Check for network operations
        if (std.mem.indexOf(u8, command, "curl") != null or
            std.mem.indexOf(u8, command, "wget") != null)
        {
            if (@intFromEnum(ValidationResult.RiskLevel.low) > @intFromEnum(result.risk_level)) {
                result.risk_level = .low;
            }
        }

        return result;
    }

    /// Enable or disable validation
    pub fn setEnabled(self: *CommandValidator, enabled: bool) void {
        self.enabled = enabled;
    }

    /// Allow dangerous commands
    pub fn setAllowDangerous(self: *CommandValidator, allow: bool) void {
        self.allow_dangerous = allow;
    }
};

// =============================================================================
// Unit Tests for Command Validation
// =============================================================================

test "CommandValidator.validate detects rm -rf / as dangerous" {
    const validator = CommandValidator.init(std.testing.allocator);
    var result = try validator.validate("rm -rf /");
    defer result.deinit(std.testing.allocator);

    try std.testing.expect(!result.valid);
    try std.testing.expectEqual(ValidationResult.RiskLevel.dangerous, result.risk_level);
    try std.testing.expect(result.errors.items.len > 0);
}

test "CommandValidator.validate detects rm -rf ~ as dangerous" {
    const validator = CommandValidator.init(std.testing.allocator);
    var result = try validator.validate("rm -rf ~");
    defer result.deinit(std.testing.allocator);

    try std.testing.expect(!result.valid);
    try std.testing.expectEqual(ValidationResult.RiskLevel.dangerous, result.risk_level);
}

test "CommandValidator.validate detects dd as high risk" {
    const validator = CommandValidator.init(std.testing.allocator);
    var result = try validator.validate("dd if=/dev/zero of=/dev/sda");
    defer result.deinit(std.testing.allocator);

    try std.testing.expect(result.valid); // High risk but not blocked by default
    try std.testing.expectEqual(ValidationResult.RiskLevel.high, result.risk_level);
}

test "CommandValidator.validate detects mkfs as high risk" {
    const validator = CommandValidator.init(std.testing.allocator);
    var result = try validator.validate("mkfs.ext4 /dev/sdb1");
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(ValidationResult.RiskLevel.high, result.risk_level);
}

test "CommandValidator.validate detects chmod 777 as medium risk" {
    const validator = CommandValidator.init(std.testing.allocator);
    var result = try validator.validate("chmod 777 /var/www");
    defer result.deinit(std.testing.allocator);

    try std.testing.expect(result.valid);
    try std.testing.expectEqual(ValidationResult.RiskLevel.medium, result.risk_level);
    try std.testing.expect(result.warnings.items.len > 0);
}

test "CommandValidator.validate detects sudo commands" {
    const validator = CommandValidator.init(std.testing.allocator);
    var result = try validator.validate("sudo apt update");
    defer result.deinit(std.testing.allocator);

    try std.testing.expect(result.valid);
    try std.testing.expect(@intFromEnum(result.risk_level) >= @intFromEnum(ValidationResult.RiskLevel.medium));
    try std.testing.expect(result.warnings.items.len > 0);
}

test "CommandValidator.validate allows safe commands" {
    const validator = CommandValidator.init(std.testing.allocator);
    var result = try validator.validate("ls -la");
    defer result.deinit(std.testing.allocator);

    try std.testing.expect(result.valid);
    try std.testing.expectEqual(ValidationResult.RiskLevel.safe, result.risk_level);
    try std.testing.expect(result.errors.items.len == 0);
    try std.testing.expect(result.warnings.items.len == 0);
}

test "CommandValidator.validate allows git commands" {
    const validator = CommandValidator.init(std.testing.allocator);
    var result = try validator.validate("git commit -m 'update'");
    defer result.deinit(std.testing.allocator);

    try std.testing.expect(result.valid);
    try std.testing.expectEqual(ValidationResult.RiskLevel.safe, result.risk_level);
}

test "CommandValidator.setEnabled skips validation when disabled" {
    var validator = CommandValidator.init(std.testing.allocator);
    validator.setEnabled(false);

    var result = try validator.validate("rm -rf /"); // Would normally be dangerous
    defer result.deinit(std.testing.allocator);

    try std.testing.expect(result.valid); // Passes because validation is disabled
}

test "CommandValidator.setAllowDangerous allows dangerous commands" {
    var validator = CommandValidator.init(std.testing.allocator);
    validator.setAllowDangerous(true);

    var result = try validator.validate("rm -rf /");
    defer result.deinit(std.testing.allocator);

    try std.testing.expect(result.valid); // Dangerous but allowed
    try std.testing.expectEqual(ValidationResult.RiskLevel.dangerous, result.risk_level);
}

test "ValidationResult.init creates valid result" {
    var result = ValidationResult.init();
    defer result.deinit(std.testing.allocator);

    try std.testing.expect(result.valid);
    try std.testing.expectEqual(ValidationResult.RiskLevel.safe, result.risk_level);
    try std.testing.expect(result.errors.items.len == 0);
    try std.testing.expect(result.warnings.items.len == 0);
}
