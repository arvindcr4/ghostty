//! Unit tests for Shell Detection module
//! Tests shell detection, context management, and command conversion

const std = @import("std");
const testing = std.testing;
const Allocator = std.mem.Allocator;

const shell = @import("../../src/ai/shell.zig");

test "Shell enum has all expected values" {
    try testing.expectEqual(@as(shell.Shell, .bash), shell.Shell.bash);
    try testing.expectEqual(@as(shell.Shell, .zsh), shell.Shell.zsh);
    try testing.expectEqual(@as(shell.Shell, .fish), shell.Shell.fish);
    try testing.expectEqual(@as(shell.Shell, .nushell), shell.Shell.nushell);
    try testing.expectEqual(@as(shell.Shell, .pwsh), shell.Shell.pwsh);
    try testing.expectEqual(@as(shell.Shell, .cmd), shell.Shell.cmd);
    try testing.expectEqual(@as(shell.Shell, .sh), shell.Shell.sh);
    try testing.expectEqual(@as(shell.Shell, .unknown), shell.Shell.unknown);
}

test "Shell enum str method" {
    try testing.expectEqualStrings(shell.Shell.bash.str(), "bash");
    try testing.expectEqualStrings(shell.Shell.zsh.str(), "zsh");
    try testing.expectEqualStrings(shell.Shell.fish.str(), "fish");
    try testing.expectEqualStrings(shell.Shell.nushell.str(), "nushell");
    try testing.expectEqualStrings(shell.Shell.pwsh.str(), "pwsh");
    try testing.expectEqualStrings(shell.Shell.cmd.str(), "cmd");
    try testing.expectEqualStrings(shell.Shell.sh.str(), "sh");
    try testing.expectEqualStrings(shell.Shell.unknown.str(), "unknown");
}

test "ShellContext initialization" {
    const alloc = testing.allocator;

    var ctx = shell.ShellContext.init(alloc);
    defer ctx.deinit(alloc);

    try testing.expectEqual(ctx.shell, .unknown);
    try testing.expect(ctx.shell_path == null);
    try testing.expect(ctx.version == null);
    try testing.expect(ctx.prompt == null);
    try testing.expectEqual(ctx.aliases.count(), 0);
    try testing.expectEqual(ctx.functions.count(), 0);
}

test "ShellContext aliases management" {
    const alloc = testing.allocator;

    var ctx = shell.ShellContext.init(alloc);
    defer ctx.deinit(alloc);

    // Add alias
    const key = try alloc.dupeZ(u8, "ll");
    defer alloc.free(key);
    const val = try alloc.dupeZ(u8, "ls -la");
    defer alloc.free(val);
    try ctx.aliases.put(key, val);

    try testing.expectEqual(ctx.aliases.count(), 1);
    try testing.expect(ctx.aliases.get("ll") != null);
    try testing.expectEqualStrings(ctx.aliases.get("ll").?, "ls -la");
}

test "ShellContext functions management" {
    const alloc = testing.allocator;

    var ctx = shell.ShellContext.init(alloc);
    defer ctx.deinit(alloc);

    // Add function
    const key = try alloc.dupeZ(u8, "mkcd");
    defer alloc.free(key);
    const val = try alloc.dupeZ(u8, "mkdir -p $1 && cd $1");
    defer alloc.free(val);
    try ctx.functions.put(key, val);

    try testing.expectEqual(ctx.functions.count(), 1);
    try testing.expect(ctx.functions.get("mkcd") != null);
    try testing.expectEqualStrings(ctx.functions.get("mkcd").?, "mkdir -p $1 && cd $1");
}

test "ShellContext deinit cleans up all resources" {
    const alloc = testing.allocator;

    var ctx = shell.ShellContext.init(alloc);

    // Set shell_path
    ctx.shell_path = try alloc.dupe(u8, "/bin/bash");

    // Set version
    ctx.version = try alloc.dupe(u8, "5.1.0");

    // Set prompt
    ctx.prompt = try alloc.dupe(u8, "\\w$ ");

    // Add aliases
    const key = try alloc.dupeZ(u8, "ll");
    const val = try alloc.dupeZ(u8, "ls -la");
    try ctx.aliases.put(key, val);

    // Add functions
    const fn_key = try alloc.dupeZ(u8, "mkcd");
    const fn_val = try alloc.dupeZ(u8, "mkdir -p $1 && cd $1");
    try ctx.functions.put(fn_key, fn_val);

    // Deinit should clean up everything
    ctx.deinit(alloc);
}

test "getShellPrompt returns non-empty strings for all shells" {
    try testing.expect(shell.Shell.bash.str().len > 0);
    try testing.expect(shell.Shell.zsh.str().len > 0);
    try testing.expect(shell.Shell.fish.str().len > 0);
    try testing.expect(shell.Shell.nushell.str().len > 0);
    try testing.expect(shell.Shell.pwsh.str().len > 0);
    try testing.expect(shell.Shell.cmd.str().len > 0);
    try testing.expect(shell.Shell.sh.str().len > 0);
    try testing.expect(shell.Shell.unknown.str().len > 0);

    // Check that prompts contain shell-specific keywords
    const bash_prompt = shell.getShellPrompt(.bash);
    try testing.expect(std.mem.indexOf(u8, bash_prompt, "bash") != null);

    const fish_prompt = shell.getShellPrompt(.fish);
    try testing.expect(std.mem.indexOf(u8, fish_prompt, "fish") != null);

    const pwsh_prompt = shell.getShellPrompt(.pwsh);
    try testing.expect(std.mem.indexOf(u8, pwsh_prompt, "PowerShell") != null);
}

test "convertCommand with same shell returns unchanged" {
    const alloc = testing.allocator;

    const cmd = "echo hello";
    const result = try shell.convertCommand(alloc, cmd, .bash, .bash);
    defer alloc.free(result);

    try testing.expectEqualStrings(result, cmd);
}

test "convertCommand bash to fish - variable syntax" {
    const alloc = testing.allocator;

    // Test $VAR conversion
    const cmd1 = "echo $VAR";
    const result1 = try shell.convertCommand(alloc, cmd1, .bash, .fish);
    defer alloc.free(result1);
    try testing.expectEqualStrings(result1, "echo $VAR");

    // Test ${VAR} conversion
    const cmd2 = "echo ${VAR}";
    const result2 = try shell.convertCommand(alloc, cmd2, .bash, .fish);
    defer alloc.free(result2);
    try testing.expectEqualStrings(result2, "echo $VAR");
}

test "convertCommand bash to fish - command substitution" {
    const alloc = testing.allocator;

    // Test backtick conversion
    const cmd = "echo `date`";
    const result = try shell.convertCommand(alloc, cmd, .bash, .fish);
    defer alloc.free(result);

    try testing.expectEqualStrings(result, "echo (date)");
}

test "convertCommand fish to bash - variable syntax" {
    const alloc = testing.allocator;

    const cmd = "echo $VAR";
    const result = try shell.convertCommand(alloc, cmd, .fish, .bash);
    defer alloc.free(result);

    try testing.expectEqualStrings(result, "echo ${VAR}");
}

test "convertCommand fish to bash - command substitution" {
    const alloc = testing.allocator;

    const cmd = "echo (date)";
    const result = try shell.convertCommand(alloc, cmd, .fish, .bash);
    defer alloc.free(result);

    try testing.expectEqualStrings(result, "echo $(date)");
}

test "convertCommand unsupported conversion returns original" {
    const alloc = testing.allocator;

    const cmd = "echo hello";
    const result = try shell.convertCommand(alloc, cmd, .bash, .pwsh);
    defer alloc.free(result);

    // For unsupported conversions, returns original
    try testing.expectEqualStrings(result, cmd);
}

test "convertCommand complex bash to fish" {
    const alloc = testing.allocator;

    // Test multiple conversions in one command
    const cmd = "echo ${HOME} && echo `pwd`";
    const result = try shell.convertCommand(alloc, cmd, .bash, .fish);
    defer alloc.free(result);

    try testing.expect(std.mem.indexOf(u8, result, "(pwd)") != null);
}
