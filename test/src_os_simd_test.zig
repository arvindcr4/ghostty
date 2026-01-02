// src/os/test_os.zig
const std = @import("std");
const testing = std.testing;
const os = @import("os.zig");

test "OS detection" {
    const detected_os = os.detectOS();
    switch (@import("builtin").target.os.tag) {
        .linux => {
            try testing.expect(detected_os.is_linux);
            try testing.expect(!detected_os.is_windows);
            try testing.expect(!detected_os.is_macos);
        },
        .windows => {
            try testing.expect(!detected_os.is_linux);
            try testing.expect(detected_os.is_windows);
            try testing.expect(!detected_os.is_macos);
        },
        .macos => {
            try testing.expect(!detected_os.is_linux);
            try testing.expect(!detected_os.is_windows);
            try testing.expect(detected_os.is_macos);
        },
        else => {},
    }
}

test "Environment variable handling" {
    const allocator = testing.allocator;
    
    // Test getting environment variable
    const path = try os.getenv(allocator, "PATH");
    defer allocator.free(path);
    try testing.expect(path.len > 0);
    
    // Test non-existent variable
    const nonexistent = try os.getenv(allocator, "GHOSTTY_TEST_NONEXISTENT");
    defer allocator.free(nonexistent);
    try testing.expectEqualStrings("", nonexistent);
}

test "Process spawning" {
    const allocator = testing.allocator;
    
    // Test echo command
    const result = try os.spawnProcess(allocator, &[_][]const u8{ "echo", "hello" });
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);
    
    try testing.expectEqual(0, result.exit_code);
    try testing.expectEqualStrings("hello\n", result.stdout);
}

test "File operations" {
    const allocator = testing.allocator;
    const tmp_dir = testing.tmpDir(.{});
    defer tmp_dir.cleanup();
    
    const test_file = try tmp_dir.dir.createFile("test.txt", .{});
    defer test_file.close();
    
    try test_file.writeAll("test content");
    
    const content = try os.readFile(allocator, "test.txt");
    defer allocator.free(content);
    try testing.expectEqualStrings("test content", content);
}

test "Terminal size detection" {
    const size = try os.getTerminalSize();
    try testing.expect(size.cols > 0);
    try testing.expect(size.rows > 0);
}

test "Signal handling" {
    const handler = struct {
        var signal_received: bool = false;
        
        fn handle(sig: c_int) void {
            _ = sig;
            signal_received = true;
        }
    };
    
    try os.setSignalHandler(std.os.SIGUSR1, handler.handle);
    std.os.raise(std.os.SIGUSR1) catch {};
    try testing.expect(handler.signal_received);
}

// src/os/platform/linux.zig tests
const linux = @import("platform/linux.zig");

test "Linux-specific features" {
    if (@import("builtin").target.os.tag != .linux) return;
    
    const allocator = testing.allocator;
    
    // Test proc filesystem reading
    const uptime = try linux.getUptime();
    try testing.expect(uptime > 0);
    
    // Test memory info
    const mem_info = try linux.getMemoryInfo(allocator);
    defer allocator.free(mem_info.total);
    defer allocator.free(mem_info.available);
    try testing.expect(mem_info.total.len > 0);
}

// src/os/platform/windows.zig tests
const windows = @import("platform/windows.zig");

test "Windows-specific features" {
    if (@import("builtin").target.os.tag != .windows) return;
    
    const allocator = testing.allocator;
    
    // Test registry reading
    const version = try windows.getWindowsVersion(allocator);
    defer allocator.free(version);
    try testing.expect(version.len > 0);
    
    // Test console mode
    const mode = try windows.getConsoleMode();
    try testing.expect(mode > 0);
}

// src/os/platform/macos.zig tests
const macos = @import("platform/macos.zig");

test "macOS-specific features" {
    if (@import("builtin").target.os.tag != .macos) return;
    
    const allocator = testing.allocator;
    
    // Test system version
    const version = try macos.getMacOSVersion(allocator);
    defer allocator.free(version);
    try testing.expect(version.len > 0);
    
    // Test notification center
    try macos.sendNotification("Test", "Test notification from Ghostty");
}

// src/simd/test_simd.zig
const std = @import("std");
const testing = std.testing;
const simd = @import("simd.zig");

test "SIMD feature detection" {
    const features = simd.detectFeatures();
    
    if (@import("builtin").target.cpu.arch == .x86_64) {
        // Test x86 SIMD features
        try testing.expect(features.has_sse or features.has_avx or features.has_avx2);
    } else if (@import("builtin").target.cpu.arch == .aarch64) {
        // Test ARM SIMD features
        try testing.expect(features.has_neon);
    }
}

test "Vector addition - SIMD vs scalar" {
    const allocator = testing.allocator;
    const len = 1024;
    
    const a = try allocator.alloc(f32, len);
    defer allocator.free(a);
    const b = try allocator.alloc(f32, len);
    defer allocator.free(b);
    const result_simd = try allocator.alloc(f32, len);
    defer allocator.free(result_simd);
    const result_scalar = try allocator.alloc(f32, len);
    defer allocator.free(result_scalar);
    
    // Initialize test data
    var i: usize = 0;
    while (i < len) : (i += 1) {
        a[i] = @as(f32, @floatFromInt(i)) * 0.1;
        b[i] = @as(f32, @floatFromInt(i)) * 0.2;
    }
    
    // SIMD addition
    simd.addVectors(f32, result_simd, a, b);
    
    // Scalar addition
    i = 0;
    while (i < len) : (i += 1) {
        result_scalar[i] = a[i] + b[i];
    }
    
    // Compare results
    i = 0;
    while (i < len) : (i += 1) {
        try testing.expectApproxEqAbs(result_simd[i], result_scalar[i], 0.0001);
    }
}

test "Vector multiplication - SIMD vs scalar" {
    const allocator = testing.allocator;
    const len = 1024;
    
    const a = try allocator.alloc(f32, len);
    defer allocator.free(a);
    const b = try allocator.alloc(f32, len);
    defer allocator.free(b);
    const result_simd = try allocator.alloc(f32, len);
    defer allocator.free(result_simd);
    const result_scalar = try allocator.alloc(f32, len);
    defer allocator.free(result_scalar);
    
    // Initialize test data
    var i: usize = 0;
    while (i < len) : (i += 1) {
        a[i] = @as(f32, @floatFromInt(i)) * 0.1;
        b[i] = @as(f32, @floatFromInt(i)) * 0.2;
    }
    
    // SIMD multiplication
    simd.multiplyVectors(f32, result_simd, a, b);
    
    // Scalar multiplication
    i = 0;
    while (i < len) : (i += 1) {
        result_scalar[i] = a[i] * b[i];
    }
    
    // Compare results
    i = 0;
    while (i < len) : (i += 1) {
        try testing.expectApproxEqAbs(result_simd[i], result_scalar[i], 0.0001);
    }
}

test "Vector dot product - SIMD vs scalar" {
    const allocator = testing.allocator;
    const len = 1024;
    
    const a = try allocator.alloc(f32, len);
    defer allocator.free(a);
    const b = try allocator.alloc(f32, len);
    defer allocator.free(b);
    
    // Initialize test data
    var i: usize = 0;
    while (i < len) : (i += 1) {
        a[i] = @as(f32, @floatFromInt(i)) * 0.1;
        b[i] = @as(f32, @floatFromInt(i)) * 0.2;
    }
    
    // SIMD dot product
    const dot_simd = simd.dotProduct(f32, a, b);
    
    // Scalar dot product
    var dot_scalar: f32 = 0.0;
    i = 0;
    while (i < len) : (i += 1) {
        dot_scalar += a[i] * b[i];
    }
    
    try testing.expectApproxEqAbs(dot_simd, dot_scalar, 0.001);
}

test "Matrix multiplication - SIMD vs scalar" {
    const allocator = testing.allocator;
    const size = 16;
    
    const a = try allocator.alloc(f32, size * size);
    defer allocator.free(a);
    const b = try allocator.alloc(f32, size * size);
    defer allocator.free(b);
    const result_simd = try allocator.alloc(f32, size * size);
    defer allocator.free(result_simd);
    const result_scalar = try allocator.alloc(f32, size * size);
    defer allocator.free(result_scalar);
    
    // Initialize test data
    var i: usize = 0;
    while (i < size * size) : (i += 1) {
        a[i] = @as(f32, @floatFromInt(i)) * 0.01;
        b[i] = @as(f32, @floatFromInt(i)) * 0.02;
    }
    
    // SIMD matrix multiplication
    simd.matrixMultiply(f32, result_simd, a, b, size);
    
    // Scalar matrix multiplication
    i = 0;
    while (i < size) : (i += 1) {
        var j: usize = 0;
        while (j < size) : (j += 1) {
            var sum: f32 = 0.0;
            var k: usize = 0;
            while (k < size) : (k += 1) {
                sum += a[i * size + k] * b[k * size + j];
            }
            result_scalar[i * size + j] = sum;
        }
    }
    
    // Compare results
    i = 0;
    while (i < size * size) : (i += 1) {
        try testing.expectApproxEqAbs(result_simd[i], result_scalar[i], 0.001);
    }
}

test "String operations - SIMD vs scalar" {
    const allocator = testing.allocator;
    
    const str1 = "Hello, World!";
    const str2 = "Hello, World!";
    const str3 = "Different string";
    
    // SIMD string comparison
    try testing.expect(simd.stringEquals(str1, str2));
    try testing.expect(!simd.stringEquals(str1, str3));
    
    // SIMD string length
    try testing.expectEqual(str1.len, simd.stringLength(str1));
    
    // SIMD string search
    const substr = "World";
    const pos = simd.stringFind(str1, substr);
    try testing.expect(pos.? == 7);
}

test "Fallback for non-SIMD platforms" {
    const allocator = testing.allocator;
    const len = 256;
    
    const a = try allocator.alloc(f32, len);
    defer allocator.free(a);
    const b = try allocator.alloc(f32, len);
    defer allocator.free(b);
    const result = try allocator.alloc(f32, len);
    defer allocator.free(result);
    
    // Initialize test data
    var i: usize = 0;
    while (i < len) : (i += 1) {
        a[i] = @as(f32, @floatFromInt(i)) * 0.1;
        b[i] = @as(f32, @floatFromInt(i)) * 0.2;
    }
    
    // Test fallback implementation
    simd.addVectorsFallback(f32, result, a, b);
    
    i = 0;
    while (i < len) : (i += 1) {
        try testing.expectApproxEqAbs(result[i], a[i] + b[i], 0.0001);
    }
}

// src/simd/x86/avx.zig tests
const avx = @import("x86/avx.zig");

test "AVX operations" {
    if (!simd.detectFeatures().has_avx) return;
    
    const allocator = testing.allocator;
    const len = 256;
    
    const a = try allocator.alloc(f32, len);
    defer allocator.free(a);
    const b = try allocator.alloc(f32, len);
    defer allocator.free(b);
    const result = try allocator.alloc(f32, len);
    defer allocator.free(result);
    
    // Initialize test data
    var i: usize = 0;
    while (i < len) : (i += 1) {
        a[i] = @as(f32, @floatFromInt(i)) * 0.1;
        b[i] = @as(f32, @floatFromInt(i)) * 0.2;
    }
    
    // AVX addition
    avx.addVectors256(result, a, b);
    
    i = 0;
    while (i < len) : (i += 1) {
        try testing.expectApproxEqAbs(result[i], a[i] + b[i], 0.0001);
    }
}

// src/simd/arm/neon.zig tests
const neon = @import("arm/neon.zig");

test "NEON operations" {
    if (!simd.detectFeatures().has_neon) return;
    
    const allocator = testing.allocator;
    const len = 128;
    
    const a = try allocator.alloc(f32, len);
    defer allocator.free(a);
    const b = try allocator.alloc(f32, len);
    defer allocator.free(b);
    const result = try allocator.alloc(f32, len);
    defer allocator.free(result);
    
    // Initialize test data
    var i: usize = 0;
    while (i < len) : (i += 1) {
        a[i] = @as(f32, @floatFromInt(i)) * 0.1;
        b[i] = @as(f32, @floatFromInt(i)) * 0.2;
    }
    
    // NEON addition
    neon.addVectors128(result, a, b);
    
    i = 0;
    while (i < len) : (i += 1) {
        try testing.expectApproxEqAbs(result[i], a[i] + b[i], 0.0001);
    }
}

// src/shell-integration/test_shell_integration.zig
const std = @import("std");
const testing = std.testing;
const shell_integration = @import("shell_integration.zig");

test "Shell detection" {
    const allocator = testing.allocator;
    
    // Test shell detection from environment
    const shell = try shell_integration.detectShell(allocator);
    defer allocator.free(shell);
    
    // Should detect one of the supported shells
    const supported_shells = [_][]const u8{ "bash", "zsh", "fish", "powershell", "cmd" };
    var found = false;
    for (supported_shells) |s| {
        if (std.mem.eql(u8, shell, s)) {
            found = true;
            break;
        }
    }
    try testing.expect(found);
}

test "Bash integration script generation" {
    const allocator = testing.allocator;
    
    const script = try shell_integration.generateBashScript(allocator);
    defer allocator.free(script);
    
    // Check for essential bash functions
    try testing.expect(std.mem.indexOf(u8, script, "_ghostty_preexec()") != null);
    try testing.expect(std.mem.indexOf(u8, script, "_ghostty_precmd()") != null);
    try testing.expect(std.mem.indexOf(u8, script, "PROMPT_COMMAND") != null);
}

test "Zsh integration script generation" {
    const allocator = testing.allocator;
    
    const script = try shell_integration.generateZshScript(allocator);
    defer allocator.free(script);
    
    // Check for essential zsh functions
    try testing.expect(std.mem.indexOf(u8, script, "_ghostty_preexec()") != null);
    try testing.expect(std.mem.indexOf(u8, script, "_ghostty_precmd()") != null);
    try testing.expect(std.mem.indexOf(u8, script, "preexec_functions") != null);
    try testing.expect(std.mem.indexOf(u8, script, "precmd_functions") != null);
}

test "Fish integration script generation" {
    const allocator = testing.allocator;
    
    const script = try shell_integration.generateFishScript(allocator);
    defer allocator.free(script);
    
    // Check for essential fish functions
    try testing.expect(std.mem.indexOf(u8, script, "_ghostty_preexec") != null);
    try testing.expect(std.mem.indexOf(u8, script, "_ghostty_precmd") != null);
    try testing.expect(std.mem.indexOf(u8, script, "__fish_preexec_functions") != null);
    try testing.expect(std.mem.indexOf(u8, script, "__fish_precmd_functions") != null);
}

test "PowerShell integration script generation" {
    const allocator = testing.allocator;
    
    const script = try shell_integration.generatePowerShellScript(allocator);
    defer allocator.free(script);
    
    // Check for essential PowerShell functions
    try testing.expect(std.mem.indexOf(u8, script, "function _ghostty_preexec") != null);
    try testing.expect(std.mem.indexOf(u8, script, "function _ghostty_precmd") != null);
}

test "Command integration" {
    const allocator = testing.allocator;
    
    // Test command extraction
    const command_line = "ls -la /home/user";
    const command = try shell_integration.extractCommand(allocator, command_line);
    defer allocator.free(command);
    try testing.expectEqualStrings("ls", command);
    
    // Test argument extraction
    const args = try shell_integration.extractArguments(allocator, command_line);
    defer allocator.free(args);
    try testing.expect(args.len == 3);
    try testing.expectEqualStrings("ls", args[0]);
    try testing.expectEqualStrings("-la", args[1]);
    try testing.expectEqualStrings("/home/user", args[2]);
}

test "Working directory tracking" {
    const allocator = testing.allocator;
    
    // Test working directory extraction
    const cwd = try shell_integration.getCurrentWorkingDirectory(allocator);
    defer allocator.free(cwd);
    try testing.expect(cwd.len > 0);
    
    // Test directory change detection
    const old_dir = try allocator.dupe(u8, cwd);
    defer allocator.free(old_dir);
    
    // Simulate directory change
    const new_dir = "/tmp";
    const changed = shell_integration.hasDirectoryChanged(old_dir, new_dir);
    try testing.expect(changed);
}

test "Environment variable integration" {
    const allocator = testing.allocator;
    
    // Test environment variable setting
    try shell_integration.setShellVariable(allocator, "GHOSTTY_TEST", "test_value");
    
    const value = try shell_integration.getShellVariable(allocator, "GHOSTTY_TEST");
    defer allocator.free(value);
    try testing.expectEqualStrings("test_value", value);
}

test "Prompt integration" {
    const allocator = testing.allocator;
    
    // Test prompt modification
    const original_prompt = "$ ";
    const modified_prompt = try shell_integration.modifyPrompt(allocator, original_prompt);
    defer allocator.free(modified_prompt);
    
    // Should contain original prompt plus Ghostty additions
    try testing.expect(std.mem.indexOf(u8, modified_prompt, original_prompt) != null);
    try testing.expect(modified_prompt.len > original_prompt.len);
}

test "Shell compatibility checks" {
    const allocator = testing.allocator;
    
    // Test bash compatibility
    const bash_compat = shell_integration.checkShellCompatibility("bash");
    try testing.expect(bash_compat);
    
    // Test zsh compatibility
    const zsh_compat = shell_integration.checkShellCompatibility("zsh");
    try testing.expect(zsh_compat);
    
    // Test fish compatibility
    const fish_compat = shell_integration.checkShellCompatibility("fish");
    try testing.expect(fish_compat);
    
    // Test unknown shell
    const unknown_compat = shell_integration.checkShellCompatibility("unknown_shell");
    try testing.expect(!unknown_compat);
}

test "Integration script installation" {
    const allocator = testing.allocator;
    const tmp_dir = testing.tmpDir(.{});
    defer tmp_dir.cleanup();
    
    // Test script installation
    const script_content = "#!/bin/bash\necho 'test'";
    try shell_integration.installIntegrationScript(allocator, tmp_dir.dir, "test.sh", script_content);
    
    // Verify script was installed
    const installed_content = try tmp_dir.dir.readFileAlloc(allocator, "test.sh", 1024);
    defer allocator.free(installed_content);
    try testing.expectEqualStrings(script_content, installed_content);
}

test "Shell feature detection" {
    const allocator = testing.allocator;
    
    // Test feature detection for current shell
    const shell = try shell_integration.detectShell(allocator);
    defer allocator.free(shell);
    
    const features = try shell_integration.detectShellFeatures(allocator, shell);
    defer allocator.free(features);
    
    // Should detect at least basic features
    try testing.expect(features.len > 0);
    
    // Check for common features
    var has_arrays = false;
    var has_functions = false;
    
    for (features) |feature| {
        if (std.mem.eql(u8, feature, "arrays")) has_arrays = true;
        if (std.mem.eql(u8, feature, "functions")) has_functions = true;
    }
    
    try testing.expect(has_functions);
}

test "Performance monitoring integration" {
    const allocator = testing.allocator;
    
    // Test command timing
    const start_time = std.time.nanoTimestamp();
    std.time.sleep(10_000_000); // 10ms
    const end_time = std.time.nanoTimestamp();
    
    const duration = shell_integration.calculateCommandDuration(start_time, end_time);
    try testing.expect(duration >= 10_000_000);
    try testing.expect(duration < 20_000_000);
}

test "Error handling in shell integration" {
    const allocator = testing.allocator;
    
    // Test handling of invalid shell
    const script = shell_integration.generateScriptForShell(allocator, "invalid_shell");
    try testing.expectError(error.UnsupportedShell, script);
    
    // Test handling of empty command
    const command = shell_integration.extractCommand(allocator, "");
    try testing.expectError(error.EmptyCommand, command);
}

test "Cross-platform shell integration" {
    const allocator = testing.allocator;
    
    // Test Windows-specific integration
    if (@import("builtin").target.os.tag == .windows) {
        const ps_script = try shell_integration.generatePowerShellScript(allocator);
        defer allocator.free(ps_script);
        try testing.expect(ps_script.len > 0);
        
        const cmd_script = try shell_integration.generateCmdScript(allocator);
        defer allocator.free(cmd_script);
        try testing.expect(cmd_script.len > 0);
    }
    
    // Test Unix-specific integration
    if (@import("builtin").target.os.tag != .windows) {
        const bash_script = try shell_integration.generateBashScript(allocator);
        defer allocator.free(bash_script);
        try testing.expect(bash_script.len > 0);
        
        const zsh_script = try shell_integration.generateZshScript(allocator);
        defer allocator.free(zsh_script);
        try testing.expect(zsh_script.len > 0);
        
        const fish_script = try shell_integration.generateFishScript(allocator);
        defer allocator.free(fish_script);
        try testing.expect(fish_script.len > 0);
    }
}