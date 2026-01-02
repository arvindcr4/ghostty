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

    /// Normalize whitespace in command for pattern matching
    /// Collapses multiple spaces/tabs into single space
    fn normalizeWhitespace(self: *const CommandValidator, command: []const u8) ![]const u8 {
        var normalized: std.ArrayList(u8) = .{};
        errdefer normalized.deinit(self.alloc);

        var prev_space = true; // Start true to trim leading whitespace
        for (command) |c| {
            if (c == ' ' or c == '\t') {
                if (!prev_space) {
                    try normalized.append(self.alloc, ' ');
                    prev_space = true;
                }
            } else {
                try normalized.append(self.alloc, c);
                prev_space = false;
            }
        }

        // Trim trailing whitespace
        while (normalized.items.len > 0 and normalized.items[normalized.items.len - 1] == ' ') {
            _ = normalized.pop();
        }

        return normalized.toOwnedSlice(self.alloc);
    }

    /// Check if command contains 'rm' with both -r/-R and -f flags
    fn hasRmRecursiveForce(command: []const u8) bool {
        // Look for 'rm' command
        if (std.mem.indexOf(u8, command, "rm ")) |rm_pos| {
            const after_rm = command[rm_pos + 3 ..];
            // Check for recursive flag (-r, -R, --recursive)
            const has_recursive = std.mem.indexOf(u8, after_rm, "-r") != null or
                std.mem.indexOf(u8, after_rm, "-R") != null or
                std.mem.indexOf(u8, after_rm, "--recursive") != null;
            // Check for force flag (-f, --force)
            const has_force = std.mem.indexOf(u8, after_rm, "-f") != null or
                std.mem.indexOf(u8, after_rm, "--force") != null;
            return has_recursive and has_force;
        }
        return false;
    }

    /// Check if command targets root or home directory
    fn targetsRootOrHome(command: []const u8) bool {
        // Check for / at end or followed by space (root)
        if (std.mem.endsWith(u8, command, " /") or std.mem.indexOf(u8, command, " / ") != null) {
            return true;
        }
        // Check for ~ at end or followed by space (home)
        if (std.mem.endsWith(u8, command, " ~") or std.mem.indexOf(u8, command, " ~ ") != null) {
            return true;
        }
        // Check for explicit paths
        if (std.mem.indexOf(u8, command, " /bin") != null or
            std.mem.indexOf(u8, command, " /etc") != null or
            std.mem.indexOf(u8, command, " /usr") != null or
            std.mem.indexOf(u8, command, " /var") != null or
            std.mem.indexOf(u8, command, " /home") != null)
        {
            return true;
        }
        return false;
    }

    /// Validate a command
    pub fn validate(self: *const CommandValidator, command: []const u8) !ValidationResult {
        var result = ValidationResult.init();
        errdefer result.deinit(self.alloc);

        if (!self.enabled) {
            result.valid = true;
            return result;
        }

        // Normalize command whitespace for consistent pattern matching
        const normalized = try self.normalizeWhitespace(command);
        defer self.alloc.free(normalized);

        // Check for dangerous rm patterns (handles flag variations)
        if (hasRmRecursiveForce(normalized) and targetsRootOrHome(normalized)) {
            result.risk_level = .dangerous;
            try result.errors.append(self.alloc, try self.alloc.dupe(u8, "Dangerous: Recursive forced deletion of critical directory"));
            if (!self.allow_dangerous) {
                result.valid = false;
            }
        }

        // Check for other dangerous patterns
        const dangerous_patterns = [_]struct {
            pattern: []const u8,
            risk: ValidationResult.RiskLevel,
            message: []const u8,
        }{
            .{ .pattern = "dd if=", .risk = .high, .message = "High risk: Disk operations" },
            .{ .pattern = "mkfs", .risk = .high, .message = "High risk: Filesystem creation" },
            .{ .pattern = "fdisk", .risk = .high, .message = "High risk: Partition operations" },
            .{ .pattern = "chmod 777", .risk = .medium, .message = "Warning: Overly permissive permissions" },
            .{ .pattern = "> /dev/sd", .risk = .high, .message = "High risk: Writing to block device" },
            .{ .pattern = "> /dev/nvme", .risk = .high, .message = "High risk: Writing to block device" },
            .{ .pattern = ":(){ :|:& };:", .risk = .dangerous, .message = "Dangerous: Fork bomb detected" },
        };

        for (dangerous_patterns) |danger| {
            if (std.mem.indexOf(u8, normalized, danger.pattern)) |_| {
                if (@intFromEnum(danger.risk) > @intFromEnum(result.risk_level)) {
                    result.risk_level = danger.risk;
                }

                if (danger.risk == .dangerous) {
                    try result.errors.append(self.alloc, try self.alloc.dupe(u8, danger.message));
                    if (!self.allow_dangerous) {
                        result.valid = false;
                    }
                } else {
                    try result.warnings.append(self.alloc, try self.alloc.dupe(u8, danger.message));
                }
            }
        }

        // Check for sudo usage (with normalized whitespace)
        if (std.mem.startsWith(u8, normalized, "sudo ")) {
            if (@intFromEnum(ValidationResult.RiskLevel.medium) > @intFromEnum(result.risk_level)) {
                result.risk_level = .medium;
            }
            try result.warnings.append(self.alloc, try self.alloc.dupe(u8, "Warning: Command requires elevated privileges"));

            // Check for sudo rm specifically
            if (std.mem.indexOf(u8, normalized, "sudo rm") != null) {
                if (@intFromEnum(ValidationResult.RiskLevel.medium) > @intFromEnum(result.risk_level)) {
                    result.risk_level = .medium;
                }
                try result.warnings.append(self.alloc, try self.alloc.dupe(u8, "Warning: Elevated deletion"));
            }
        }

        // Check for network operations
        if (std.mem.indexOf(u8, normalized, "curl") != null or
            std.mem.indexOf(u8, normalized, "wget") != null)
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

test "CommandValidator.validate detects rm with extra whitespace" {
    const validator = CommandValidator.init(std.testing.allocator);
    // Extra spaces should still be detected
    var result = try validator.validate("rm  -rf   /");
    defer result.deinit(std.testing.allocator);

    try std.testing.expect(!result.valid);
    try std.testing.expectEqual(ValidationResult.RiskLevel.dangerous, result.risk_level);
}

test "CommandValidator.validate detects rm --recursive --force variations" {
    const validator = CommandValidator.init(std.testing.allocator);
    // Long form flags should also be detected
    var result = try validator.validate("rm --recursive --force /");
    defer result.deinit(std.testing.allocator);

    try std.testing.expect(!result.valid);
    try std.testing.expectEqual(ValidationResult.RiskLevel.dangerous, result.risk_level);
}

test "CommandValidator.validate detects rm -rf /etc as dangerous" {
    const validator = CommandValidator.init(std.testing.allocator);
    var result = try validator.validate("rm -rf /etc");
    defer result.deinit(std.testing.allocator);

    try std.testing.expect(!result.valid);
    try std.testing.expectEqual(ValidationResult.RiskLevel.dangerous, result.risk_level);
}

test "CommandValidator.validate detects fork bomb" {
    const validator = CommandValidator.init(std.testing.allocator);
    var result = try validator.validate(":(){ :|:& };:");
    defer result.deinit(std.testing.allocator);

    try std.testing.expect(!result.valid);
    try std.testing.expectEqual(ValidationResult.RiskLevel.dangerous, result.risk_level);
}
