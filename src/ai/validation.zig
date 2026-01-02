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

    pub fn init(alloc: Allocator) ValidationResult {
        return .{
            .valid = true,
            .warnings = ArrayList([]const u8).init(alloc),
            .errors = ArrayList([]const u8).init(alloc),
            .risk_level = .safe,
        };
    }

    pub fn deinit(self: *ValidationResult, alloc: Allocator) void {
        for (self.warnings.items) |w| alloc.free(w);
        self.warnings.deinit();
        for (self.errors.items) |e| alloc.free(e);
        self.errors.deinit();
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
        var result = ValidationResult.init(self.alloc);
        errdefer result.deinit();

        if (!self.enabled) {
            result.valid = true;
            return result;
        }

        // Normalize command: trim whitespace, handle quotes
        const normalized = self.normalizeCommand(command);

        // Check for dangerous patterns with improved matching
        const dangerous_patterns = [_]struct {
            pattern: []const u8,
            risk: ValidationResult.RiskLevel,
            message: []const u8,
            match_fn: fn ([]const u8, []const u8) bool,
        }{
            .{ .pattern = "rm -rf /", .risk = .dangerous, .message = "Dangerous: Removing root filesystem", .match_fn = matchDangerousPattern },
            .{ .pattern = "rm -rf ~", .risk = .dangerous, .message = "Dangerous: Removing home directory", .match_fn = matchDangerousPattern },
            .{ .pattern = "rm -rf", .risk = .high, .message = "High risk: Recursive deletion", .match_fn = matchDangerousPattern },
            .{ .pattern = "dd if=", .risk = .high, .message = "High risk: Disk operations", .match_fn = matchDangerousPattern },
            .{ .pattern = "mkfs", .risk = .high, .message = "High risk: Filesystem creation", .match_fn = matchDangerousPattern },
            .{ .pattern = "fdisk", .risk = .high, .message = "High risk: Partition operations", .match_fn = matchDangerousPattern },
            .{ .pattern = "chmod 777", .risk = .medium, .message = "Warning: Overly permissive permissions", .match_fn = matchDangerousPattern },
            .{ .pattern = "sudo rm", .risk = .medium, .message = "Warning: Elevated deletion", .match_fn = matchDangerousPattern },
            .{ .pattern = "> /dev/sd", .risk = .high, .message = "High risk: Writing to block device", .match_fn = matchDangerousPattern },
            .{ .pattern = "| bash", .risk = .high, .message = "High risk: Piping to shell interpreter", .match_fn = matchDangerousPattern },
            .{ .pattern = "| sh", .risk = .high, .message = "High risk: Piping to shell interpreter", .match_fn = matchDangerousPattern },
            .{ .pattern = "curl.*|", .risk = .high, .message = "High risk: Piping curl output", .match_fn = matchCommandInjection },
            .{ .pattern = "wget.*|", .risk = .high, .message = "High risk: Piping wget output", .match_fn = matchCommandInjection },
            .{ .pattern = "../", .risk = .medium, .message = "Warning: Path traversal attempt", .match_fn = matchPathTraversal },
            .{ .pattern = "..", .risk = .low, .message = "Warning: Potential path traversal", .match_fn = matchPathTraversal },
        };

        for (dangerous_patterns) |danger| {
            if (danger.match_fn(normalized, danger.pattern)) {
                if (@intFromEnum(danger.risk) > @intFromEnum(result.risk_level)) {
                    result.risk_level = danger.risk;
                }

                if (danger.risk == .dangerous) {
                    try result.errors.append(try self.alloc.dupe(u8, danger.message));
                    result.valid = false;
                } else {
                    try result.warnings.append(try self.alloc.dupe(u8, danger.message));
                }
            }
        }

        // Check for command injection patterns
        if (self.detectCommandInjection(normalized)) {
            if (@intFromEnum(ValidationResult.RiskLevel.high) > @intFromEnum(result.risk_level)) {
                result.risk_level = .high;
            }
            try result.errors.append(try self.alloc.dupe(u8, "Dangerous: Potential command injection detected"));
            result.valid = false;
        }

        // Check for shell metacharacters in suspicious contexts
        if (self.detectShellMetacharacters(normalized)) {
            if (@intFromEnum(ValidationResult.RiskLevel.medium) > @intFromEnum(result.risk_level)) {
                result.risk_level = .medium;
            }
            try result.warnings.append(try self.alloc.dupe(u8, "Warning: Shell metacharacters detected"));
        }

        // Check for sudo usage
        if (std.mem.startsWith(u8, normalized, "sudo ") or std.mem.indexOf(u8, normalized, " sudo ") != null) {
            if (@intFromEnum(ValidationResult.RiskLevel.medium) > @intFromEnum(result.risk_level)) {
                result.risk_level = .medium;
            }
            try result.warnings.append(try self.alloc.dupe(u8, "Warning: Command requires elevated privileges"));
        }

        // Check for network operations
        if (std.mem.indexOf(u8, normalized, "curl") != null or
            std.mem.indexOf(u8, normalized, "wget") != null)
        {
            if (@intFromEnum(ValidationResult.RiskLevel.low) > @intFromEnum(result.risk_level)) {
                result.risk_level = .low;
            }
        }

        // Block dangerous commands if not allowed
        if (result.risk_level == .dangerous and !self.allow_dangerous) {
            result.valid = false;
        }

        return result;
    }

    /// Normalize command for pattern matching
    fn normalizeCommand(self: *const CommandValidator, command: []const u8) []const u8 {
        _ = self;
        // Remove leading/trailing whitespace
        const trimmed = std.mem.trim(u8, command, " \t\n\r");
        // TODO: Handle quoted strings properly
        // For now, return trimmed version
        return trimmed;
    }

    /// Match dangerous pattern with improved matching
    fn matchDangerousPattern(command: []const u8, pattern: []const u8) bool {
        // Check for exact substring match
        if (std.mem.indexOf(u8, command, pattern) != null) {
            return true;
        }

        // Use stack buffer for quoted pattern matching to avoid heap allocation
        // and fail closed if pattern is too long
        var buffer: [512]u8 = undefined;
        const max_pattern_len = 510; // 512 - 2 for quotes

        if (pattern.len > max_pattern_len) {
            // Pattern too long - fail closed for safety
            return true;
        }

        // Check for pattern with double quotes
        buffer[0] = '"';
        @memcpy(buffer[1..][0..pattern.len], pattern);
        buffer[1 + pattern.len] = '"';
        const double_quoted = buffer[0 .. 2 + pattern.len];
        if (std.mem.indexOf(u8, command, double_quoted) != null) {
            return true;
        }

        // Check for pattern with single quotes
        buffer[0] = '\'';
        @memcpy(buffer[1..][0..pattern.len], pattern);
        buffer[1 + pattern.len] = '\'';
        const single_quoted = buffer[0 .. 2 + pattern.len];
        if (std.mem.indexOf(u8, command, single_quoted) != null) {
            return true;
        }

        return false;
    }

    /// Match command injection patterns
    fn matchCommandInjection(command: []const u8, pattern: []const u8) bool {
        // Check for pattern followed by pipe or semicolon
        if (std.mem.indexOf(u8, command, pattern)) |idx| {
            const after_pattern = command[idx + pattern.len..];
            // Check if followed by shell metacharacters
            if (std.mem.indexOfAny(u8, after_pattern, "|;&`$(){}[]") != null) {
                return true;
            }
        }
        return false;
    }

    /// Match path traversal patterns
    fn matchPathTraversal(command: []const u8, pattern: []const u8) bool {
        // Check for path traversal in file operations
        if (std.mem.indexOf(u8, command, pattern)) |idx| {
            // Check if it's in a file path context
            const before = command[0..idx];
            const after = command[idx + pattern.len..];
            // Look for file operations before or after
            const file_ops = [_][]const u8{ "cat ", "rm ", "cp ", "mv ", "chmod ", "chown ", "ls ", "find ", "grep ", "sed ", "awk " };
            for (file_ops) |op| {
                if (std.mem.indexOf(u8, before, op) != null or std.mem.indexOf(u8, after, op) != null) {
                    return true;
                }
            }
        }
        return false;
    }

    /// Detect command injection attempts
    fn detectCommandInjection(self: *const CommandValidator, command: []const u8) bool {
        _ = self;
        // Check for command chaining
        const chain_chars = [_]u8{ '|', ';', '&', '`', '$', '(', ')' };
        var chain_count: usize = 0;
        for (command) |c| {
            for (chain_chars) |ch| {
                if (c == ch) {
                    chain_count += 1;
                    break;
                }
            }
        }
        // Multiple chain characters suggest injection
        if (chain_count > 2) {
            return true;
        }
        // Check for $(command) or `command` patterns
        if (std.mem.indexOf(u8, command, "$(") != null or std.mem.indexOf(u8, command, "`") != null) {
            return true;
        }
        return false;
    }

    /// Detect shell metacharacters in suspicious contexts
    fn detectShellMetacharacters(self: *const CommandValidator, command: []const u8) bool {
        _ = self;
        // Check for metacharacters that could be dangerous
        const dangerous_chars = [_]u8{ '>', '<', '|', '&', ';', '`', '$', '(', ')', '{', '}', '[', ']', '*', '?', '~' };
        var found_count: usize = 0;
        for (command) |c| {
            for (dangerous_chars) |ch| {
                if (c == ch) {
                    found_count += 1;
                    break;
                }
            }
        }
        // Multiple metacharacters suggest potential issues
        return found_count > 3;
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
