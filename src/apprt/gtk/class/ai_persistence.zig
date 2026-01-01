//! Persistence Helper for AI Features
//! Provides JSON-based save/load functionality for AI UI components

const std = @import("std");
const Allocator = std.mem.Allocator;

const log = std.log.scoped(.gtk_ghostty_ai_persistence);

pub fn getConfigDir(alloc: Allocator) ![]const u8 {
    // Try XDG_CONFIG_HOME first
    if (std.posix.getenv("XDG_CONFIG_HOME")) |xdg_config| {
        return try std.fmt.allocPrint(alloc, "{s}/ghostty", .{xdg_config});
    }
    
    // Fall back to ~/.config/ghostty
    if (std.posix.getenv("HOME")) |home| {
        return try std.fmt.allocPrint(alloc, "{s}/.config/ghostty", .{home});
    }
    
    return error.NoHomeDir;
}

pub fn ensureConfigDir(alloc: Allocator) ![]const u8 {
    const config_dir = try getConfigDir(alloc);
    std.fs.makeDirAbsolute(config_dir) catch |err| {
        if (err != error.PathAlreadyExists) {
            alloc.free(config_dir);
            return err;
        }
    };
    return config_dir;
}

pub fn getDataFilePath(alloc: Allocator, filename: []const u8) ![]const u8 {
    const config_dir = try ensureConfigDir(alloc);
    defer alloc.free(config_dir);
    return std.fmt.allocPrint(alloc, "{s}/{s}", .{ config_dir, filename });
}

pub fn saveJson(_: Allocator, filepath: []const u8, value: anytype) !void {
    var file = try std.fs.cwd().createFile(filepath, .{});
    defer file.close();

    var buffered = std.io.bufferedWriter(file.writer());

    try std.json.stringify(value, .{ .whitespace = .indent_2 }, buffered.writer());

    // Flush explicitly to catch I/O errors (disk full, etc.)
    try buffered.flush();
}

pub fn loadJson(comptime T: type, alloc: Allocator, filepath: []const u8) !T {
    const file = std.fs.cwd().openFile(filepath, .{}) catch |err| {
        if (err == error.FileNotFound) {
            // Return error for file not found - caller must handle explicitly
            // Using std.mem.zeroes is unsafe for types with pointer fields
            return error.FileNotFound;
        }
        return err;
    };
    defer file.close();

    const file_size = try file.getEndPos();
    const contents = try alloc.alloc(u8, file_size);
    defer alloc.free(contents);

    _ = try file.readAll(contents);

    const parsed = try std.json.parseFromSlice(T, alloc, contents, .{});
    defer parsed.deinit();

    return parsed.value;
}
