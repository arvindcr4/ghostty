//! AI Client for Ghostty Terminal
//!
//! This module provides client implementations for various AI providers
//! including OpenAI, Anthropic (Claude), and Ollama.

const std = @import("std");
const Allocator = std.mem.Allocator;
const http = std.http;
const Uri = std.Uri;
const log = std.log.scoped(.ai_client);

const shell_module = @import("shell.zig");

/// Check if a cancellation flag is set
fn isCancelled(cancelled: ?*const std.atomic.Value(bool)) bool {
    if (cancelled) |c| return c.load(.acquire);
    return false;
}

/// SSE delimiter info
const SseDelimiter = struct {
    index: usize,
    len: usize,
};

/// Find SSE event delimiter in buffer (double newline)
fn findSseDelimiter(buf: []const u8) ?SseDelimiter {
    if (std.mem.indexOf(u8, buf, "\n\n")) |idx| {
        return .{ .index = idx, .len = 2 };
    }
    if (std.mem.indexOf(u8, buf, "\r\n\r\n")) |idx| {
        return .{ .index = idx, .len = 4 };
    }
    return null;
}

/// Consume prefix from buffer (remove processed data)
fn consumePrefix(buf: *std.ArrayListUnmanaged(u8), len: usize) void {
    if (len >= buf.items.len) {
        buf.items.len = 0;
    } else {
        std.mem.copyForwards(u8, buf.items[0..], buf.items[len..]);
        buf.items.len -= len;
    }
}

/// AI Provider types
pub const Provider = enum {
    openai,
    anthropic,
    ollama,
    custom,
    cerebras,
};

/// Write a JSON-escaped string to the writer (without surrounding quotes)
fn writeJsonEscapedString(writer: anytype, string: []const u8) !void {
    for (string) |c| {
        switch (c) {
            '"' => try writer.writeAll("\\\""),
            '\\' => try writer.writeAll("\\\\"),
            '\n' => try writer.writeAll("\\n"),
            '\r' => try writer.writeAll("\\r"),
            '\t' => try writer.writeAll("\\t"),
            0x00...0x08, 0x0B...0x0C, 0x0E...0x1F => {
                // Control characters - escape as \uXXXX
                // Note: 0x09 (tab) handled above, 0x0A (\n) handled above, 0x0D (\r) handled above
                try writer.print("\\u{x:0>4}", .{c});
            },
            else => try writer.writeByte(c),
        }
    }
}

/// AI Client interface and implementations
pub const Client = struct {
    const Self = @This();

    allocator: Allocator,
    provider: Provider,
    api_key: []const u8,
    endpoint: []const u8,
    model: []const u8,
    max_tokens: u32,
    temperature: f32,
    shell: shell_module.Shell,

    /// Create a new AI client
    pub fn init(
        alloc: Allocator,
        provider: Provider,
        api_key: []const u8,
        endpoint: []const u8,
        model: []const u8,
        max_tokens: u32,
        temperature: f32,
    ) Self {
        // Detect the current shell for context-aware command generation
        const detected_shell = shell_module.detectShell(alloc) catch .unknown;

        return .{
            .allocator = alloc,
            .provider = provider,
            .api_key = api_key,
            .endpoint = endpoint,
            .model = model,
            .max_tokens = max_tokens,
            .temperature = temperature,
            .shell = detected_shell,
        };
    }

    /// Send a chat completion request
    pub fn chat(
        self: *const Self,
        system_prompt: []const u8,
        user_prompt: []const u8,
    ) !ChatResponse {
        return switch (self.provider) {
            .openai => try self.chatOpenAI(system_prompt, user_prompt),
            .anthropic => try self.chatAnthropic(system_prompt, user_prompt),
            .ollama => try self.chatOllama(system_prompt, user_prompt),
            .custom => try self.chatCustom(system_prompt, user_prompt),
            .cerebras => try self.chatCerebras(system_prompt, user_prompt),
        };
    }

    /// Enhance system prompt with shell-specific context
    fn enhanceSystemPrompt(self: *const Self, system_prompt: []const u8) ![]const u8 {
        const shell_prompt = shell_module.getShellPrompt(self.shell);

        // Combine the original system prompt with shell-specific instructions
        return std.fmt.allocPrint(self.allocator, "{s}\n\n{s}", .{ system_prompt, shell_prompt });
    }

    /// OpenAI chat completion
    fn chatOpenAI(self: *const Self, system_prompt: []const u8, user_prompt: []const u8) !ChatResponse {
        const endpoint_str = if (self.endpoint.len > 0)
            self.endpoint
        else
            "https://api.openai.com/v1/chat/completions";

        var client: http.Client = .{ .allocator = self.allocator };
        defer client.deinit();

        // Enhance system prompt with shell-specific context
        const enhanced_prompt = try self.enhanceSystemPrompt(system_prompt);
        defer self.allocator.free(enhanced_prompt);

        // Build request body with proper JSON escaping
        const body = try self.buildOpenAIJson(enhanced_prompt, user_prompt);
        defer self.allocator.free(body);

        // Build authorization header
        const auth_header = try std.fmt.allocPrint(self.allocator, "Bearer {s}", .{self.api_key});
        defer self.allocator.free(auth_header);

        // Use Zig 0.15 fetch API with std.Io.Writer.Allocating
        var allocating_writer: std.Io.Writer.Allocating = .init(self.allocator);
        defer allocating_writer.deinit();

        const result = try client.fetch(.{
            .location = .{ .url = endpoint_str },
            .method = .POST,
            .payload = body,
            .extra_headers = &.{
                .{ .name = "Authorization", .value = auth_header },
                .{ .name = "Content-Type", .value = "application/json" },
            },
            .response_writer = &allocating_writer.writer,
        });

        if (result.status != .ok) {
            log.err("OpenAI API returned status: {}", .{result.status});
            return error.NetworkError;
        }

        const body_bytes = allocating_writer.written();

        // Parse JSON response
        const parsed = try std.json.parseFromSlice(std.json.Value, self.allocator, body_bytes, .{});
        defer parsed.deinit();

        // Extract content from response
        if (parsed.value.object.get("choices")) |choices| {
            if (choices.array.items.len > 0) {
                const first_choice = choices.array.items[0];
                if (first_choice.object.get("message")) |message| {
                    if (message.object.get("content")) |content| {
                        return .{
                            .content = try self.allocator.dupe(u8, content.string),
                            .model = try self.allocator.dupe(u8, self.model),
                            .provider = "openai",
                        };
                    }
                }
            }
        }

        // Check for error in response
        if (parsed.value.object.get("error")) |err| {
            if (err.object.get("message")) |msg| {
                log.err("OpenAI API error: {s}", .{msg.string});
            }
        }

        return error.InvalidResponse;
    }

    /// Build JSON request body for OpenAI API
    fn buildOpenAIJson(self: *const Self, system_prompt: []const u8, user_prompt: []const u8) ![]const u8 {
        var buf: std.ArrayListUnmanaged(u8) = .empty;
        errdefer buf.deinit(self.allocator);

        const writer = buf.writer(self.allocator);

        // Build: {"model":"...","messages":[{"role":"system","content":"..."},{"role":"user","content":"..."}],"max_tokens":...,"temperature":...}
        try writer.writeAll("{\"model\":\"");
        try writeJsonEscapedString(writer, self.model);
        try writer.writeAll("\",\"messages\":[{\"role\":\"system\",\"content\":\"");
        try writeJsonEscapedString(writer, system_prompt);
        try writer.writeAll("\"},{\"role\":\"user\",\"content\":\"");
        try writeJsonEscapedString(writer, user_prompt);
        try writer.writeAll("\"}],\"max_tokens\":");
        try writer.print("{}", .{self.max_tokens});

        try writer.writeAll(",\"temperature\":");
        try writer.print("{d:.1}", .{self.temperature});

        try writer.writeAll("}");

        return buf.toOwnedSlice(self.allocator);
    }

    /// Anthropic Claude chat completion
    fn chatAnthropic(self: *const Self, system_prompt: []const u8, user_prompt: []const u8) !ChatResponse {
        const endpoint_str = if (self.endpoint.len > 0)
            self.endpoint
        else
            "https://api.anthropic.com/v1/messages";

        var client: http.Client = .{ .allocator = self.allocator };
        defer client.deinit();

        // Enhance system prompt with shell-specific context
        const enhanced_prompt = try self.enhanceSystemPrompt(system_prompt);
        defer self.allocator.free(enhanced_prompt);

        // Build request body
        const body = try self.buildAnthropicJson(enhanced_prompt, user_prompt);
        defer self.allocator.free(body);

        // Use Zig 0.15 fetch API with std.Io.Writer.Allocating
        var allocating_writer: std.Io.Writer.Allocating = .init(self.allocator);
        defer allocating_writer.deinit();

        const result = try client.fetch(.{
            .location = .{ .url = endpoint_str },
            .method = .POST,
            .payload = body,
            .extra_headers = &.{
                .{ .name = "x-api-key", .value = self.api_key },
                .{ .name = "anthropic-version", .value = "2023-06-01" },
                .{ .name = "Content-Type", .value = "application/json" },
            },
            .response_writer = &allocating_writer.writer,
        });

        if (result.status != .ok) {
            log.err("Anthropic API returned status: {}", .{result.status});
            return error.InvalidResponse;
        }

        const body_bytes = allocating_writer.written();

        // Parse JSON response
        const parsed = try std.json.parseFromSlice(std.json.Value, self.allocator, body_bytes, .{});
        defer parsed.deinit();

        if (parsed.value.object.get("content")) |content| {
            if (content.array.items.len > 0) {
                const first_item = content.array.items[0];
                if (first_item.object.get("text")) |text| {
                    return .{
                        .content = try self.allocator.dupe(u8, text.string),
                        .model = try self.allocator.dupe(u8, self.model),
                        .provider = "anthropic",
                    };
                }
            }
        }

        // Check for error in response
        if (parsed.value.object.get("error")) |err| {
            if (err.object.get("message")) |msg| {
                log.err("Anthropic API error: {s}", .{msg.string});
            }
        }

        return error.InvalidResponse;
    }

    /// Build JSON request body for Anthropic API
    fn buildAnthropicJson(self: *const Self, system_prompt: []const u8, user_prompt: []const u8) ![]const u8 {
        var buf: std.ArrayListUnmanaged(u8) = .empty;
        errdefer buf.deinit(self.allocator);

        const writer = buf.writer(self.allocator);

        // Build: {"model":"...","max_tokens":...,"system":"...","messages":[{"role":"user","content":"..."}],"temperature":...}
        try writer.writeAll("{\"model\":\"");
        try writeJsonEscapedString(writer, self.model);
        try writer.writeAll("\",\"max_tokens\":");
        try writer.print("{}", .{self.max_tokens});

        try writer.writeAll(",\"system\":\"");
        try writeJsonEscapedString(writer, system_prompt);
        try writer.writeAll("\",\"messages\":[{\"role\":\"user\",\"content\":\"");
        try writeJsonEscapedString(writer, user_prompt);
        try writer.writeAll("\"}],\"temperature\":");
        try writer.print("{d:.1}", .{self.temperature});

        try writer.writeAll("}");

        return buf.toOwnedSlice(self.allocator);
    }

    /// Ollama chat completion (local LLM)
    fn chatOllama(self: *const Self, system_prompt: []const u8, user_prompt: []const u8) !ChatResponse {
        const endpoint_str = if (self.endpoint.len > 0)
            self.endpoint
        else
            "http://localhost:11434/api/chat";

        var client: http.Client = .{ .allocator = self.allocator };
        defer client.deinit();

        // Enhance system prompt with shell-specific context
        const enhanced_prompt = try self.enhanceSystemPrompt(system_prompt);
        defer self.allocator.free(enhanced_prompt);

        // Build request body
        const body = try self.buildOllamaJson(enhanced_prompt, user_prompt);
        defer self.allocator.free(body);

        // Use Zig 0.15 fetch API with std.Io.Writer.Allocating
        var allocating_writer: std.Io.Writer.Allocating = .init(self.allocator);
        defer allocating_writer.deinit();

        const result = try client.fetch(.{
            .location = .{ .url = endpoint_str },
            .method = .POST,
            .payload = body,
            .extra_headers = &.{
                .{ .name = "Content-Type", .value = "application/json" },
            },
            .response_writer = &allocating_writer.writer,
        });

        if (result.status != .ok) {
            log.err("Ollama API returned status: {}", .{result.status});
            return error.InvalidResponse;
        }

        const body_bytes = allocating_writer.written();

        // Parse JSON response
        const parsed = try std.json.parseFromSlice(std.json.Value, self.allocator, body_bytes, .{});
        defer parsed.deinit();

        if (parsed.value.object.get("message")) |message| {
            if (message.object.get("content")) |content| {
                return .{
                    .content = try self.allocator.dupe(u8, content.string),
                    .model = try self.allocator.dupe(u8, self.model),
                    .provider = "ollama",
                };
            }
        }

        return error.InvalidResponse;
    }

    /// Build JSON request body for Ollama API
    fn buildOllamaJson(self: *const Self, system_prompt: []const u8, user_prompt: []const u8) ![]const u8 {
        var buf: std.ArrayListUnmanaged(u8) = .empty;
        errdefer buf.deinit(self.allocator);

        const writer = buf.writer(self.allocator);

        // Build: {"model":"...","stream":false,"messages":[{"role":"system","content":"..."},{"role":"user","content":"..."}],"options":{"num_ctx":...}}
        try writer.writeAll("{\"model\":\"");
        try writeJsonEscapedString(writer, self.model);
        try writer.writeAll("\",\"stream\":false,\"messages\":[{\"role\":\"system\",\"content\":\"");
        try writeJsonEscapedString(writer, system_prompt);
        try writer.writeAll("\"},{\"role\":\"user\",\"content\":\"");
        try writeJsonEscapedString(writer, user_prompt);
        try writer.writeAll("\"}],\"options\":{\"num_ctx\":");
        try writer.print("{}", .{self.max_tokens});

        try writer.writeAll("}}");

        return buf.toOwnedSlice(self.allocator);
    }

    /// Custom endpoint chat completion (OpenAI-compatible)
    fn chatCustom(self: *const Self, system_prompt: []const u8, user_prompt: []const u8) !ChatResponse {
        // Use OpenAI-compatible format
        return self.chatOpenAI(system_prompt, user_prompt);
    }

    /// Cerebras chat completion (OpenAI-compatible API)
    fn chatCerebras(self: *const Self, system_prompt: []const u8, user_prompt: []const u8) !ChatResponse {
        const endpoint_str = if (self.endpoint.len > 0)
            self.endpoint
        else
            "https://api.cerebras.ai/v1/chat/completions";

        var client: http.Client = .{ .allocator = self.allocator };
        defer client.deinit();

        // Enhance system prompt with shell-specific context
        const enhanced_prompt = try self.enhanceSystemPrompt(system_prompt);
        defer self.allocator.free(enhanced_prompt);

        // Build request body with proper JSON escaping
        const body = try self.buildCerebrasJson(enhanced_prompt, user_prompt);
        defer self.allocator.free(body);

        // Build authorization header
        const auth_header = try std.fmt.allocPrint(self.allocator, "Bearer {s}", .{self.api_key});
        defer self.allocator.free(auth_header);

        // Use Zig 0.15 fetch API with std.Io.Writer.Allocating
        var allocating_writer: std.Io.Writer.Allocating = .init(self.allocator);
        defer allocating_writer.deinit();

        const result = try client.fetch(.{
            .location = .{ .url = endpoint_str },
            .method = .POST,
            .payload = body,
            .extra_headers = &.{
                .{ .name = "Authorization", .value = auth_header },
                .{ .name = "Content-Type", .value = "application/json" },
            },
            .response_writer = &allocating_writer.writer,
        });

        if (result.status != .ok) {
            log.err("Cerebras API returned status: {}", .{result.status});
            return error.NetworkError;
        }

        const body_bytes = allocating_writer.written();

        // Parse JSON response
        const parsed = try std.json.parseFromSlice(std.json.Value, self.allocator, body_bytes, .{});
        defer parsed.deinit();

        // Extract content from response
        if (parsed.value.object.get("choices")) |choices| {
            if (choices.array.items.len > 0) {
                const first_choice = choices.array.items[0];
                if (first_choice.object.get("message")) |message| {
                    if (message.object.get("content")) |content| {
                        return .{
                            .content = try self.allocator.dupe(u8, content.string),
                            .model = try self.allocator.dupe(u8, self.model),
                            .provider = "cerebras",
                        };
                    }
                }
            }
        }

        // Check for error in response
        if (parsed.value.object.get("error")) |err| {
            if (err.object.get("message")) |msg| {
                log.err("Cerebras API error: {s}", .{msg.string});
            }
        }

        return error.InvalidResponse;
    }

    /// Build JSON request body for Cerebras API (OpenAI-compatible format)
    fn buildCerebrasJson(self: *const Self, system_prompt: []const u8, user_prompt: []const u8) ![]const u8 {
        var buf: std.ArrayListUnmanaged(u8) = .empty;
        errdefer buf.deinit(self.allocator);

        const writer = buf.writer(self.allocator);

        // Build: {"model":"...","messages":[{"role":"system","content":"..."},{"role":"user","content":"..."}],"max_tokens":...,"temperature":...}
        try writer.writeAll("{\"model\":\"");
        try writeJsonEscapedString(writer, self.model);
        try writer.writeAll("\",\"messages\":[{\"role\":\"system\",\"content\":\"");
        try writeJsonEscapedString(writer, system_prompt);
        try writer.writeAll("\"},{\"role\":\"user\",\"content\":\"");
        try writeJsonEscapedString(writer, user_prompt);
        try writer.writeAll("\"}],\"max_tokens\":");
        try writer.print("{}", .{self.max_tokens});

        try writer.writeAll(",\"temperature\":");
        try writer.print("{d:.1}", .{self.temperature});

        try writer.writeAll("}");

        return buf.toOwnedSlice(self.allocator);
    }

    fn buildOpenAIJsonStream(self: *const Self, system_prompt: []const u8, user_prompt: []const u8) ![]const u8 {
        var buf: std.ArrayListUnmanaged(u8) = .empty;
        errdefer buf.deinit(self.allocator);

        const writer = buf.writer(self.allocator);

        try writer.writeAll("{\"model\":\"");
        try writeJsonEscapedString(writer, self.model);
        try writer.writeAll("\",\"messages\":[{\"role\":\"system\",\"content\":\"");
        try writeJsonEscapedString(writer, system_prompt);
        try writer.writeAll("\"},{\"role\":\"user\",\"content\":\"");
        try writeJsonEscapedString(writer, user_prompt);
        try writer.writeAll("\"}],\"max_tokens\":");
        try writer.print("{}", .{self.max_tokens});

        try writer.writeAll(",\"temperature\":");
        try writer.print("{d:.1}", .{self.temperature});

        try writer.writeAll(",\"stream\":true}");

        return buf.toOwnedSlice(self.allocator);
    }

    fn chatStreamOpenAI(
        self: *const Self,
        system_prompt: []const u8,
        user_prompt: []const u8,
        options: StreamOptions,
    ) !void {
        const endpoint_str = if (self.endpoint.len > 0)
            self.endpoint
        else
            "https://api.openai.com/v1/chat/completions";

        var client: http.Client = .{ .allocator = self.allocator };
        defer client.deinit();

        const uri = try Uri.parse(endpoint_str);

        // Enhance system prompt with shell-specific context
        const enhanced_prompt = try self.enhanceSystemPrompt(system_prompt);
        defer self.allocator.free(enhanced_prompt);

        // Build request body with streaming enabled
        const body = try self.buildOpenAIJsonStream(enhanced_prompt, user_prompt);
        defer self.allocator.free(body);

        // Build authorization header
        const auth_header = try std.fmt.allocPrint(self.allocator, "Bearer {s}", .{self.api_key});
        defer self.allocator.free(auth_header);

        var req = try client.request(.POST, uri, .{
            .headers = .{ .accept_encoding = .{ .override = "identity" } },
            .extra_headers = &.{
                .{ .name = "Authorization", .value = auth_header },
                .{ .name = "Content-Type", .value = "application/json" },
                .{ .name = "Accept", .value = "text/event-stream" },
            },
        });
        defer req.deinit();

        try req.sendBodyComplete(@constCast(body));

        var response = try req.receiveHead(&.{});
        if (response.head.status != .ok) {
            log.err("OpenAI streaming returned status: {}", .{response.head.status});
            options.callback(.{ .content = "", .done = true });
            return error.InvalidResponse;
        }

        var transfer_buffer: [4096]u8 = undefined;
        const body_reader = response.reader(&transfer_buffer);

        var read_buf: [4096]u8 = undefined;
        var sse_buf: std.ArrayListUnmanaged(u8) = .empty;
        defer sse_buf.deinit(self.allocator);

        while (true) {
            if (isCancelled(options.cancelled)) {
                options.callback(.{ .content = "", .done = true });
                return;
            }

            const bytes_read = body_reader.readVec(&.{read_buf[0..]}) catch |err| switch (err) {
                error.EndOfStream => break,
                error.ReadFailed => {
                    log.warn("OpenAI stream read error: {}", .{err});
                    options.callback(.{ .content = "", .done = true });
                    return;
                },
            };
            if (bytes_read == 0) continue;

            try sse_buf.appendSlice(self.allocator, read_buf[0..bytes_read]);

            while (true) {
                if (isCancelled(options.cancelled)) {
                    options.callback(.{ .content = "", .done = true });
                    return;
                }

                const delim = findSseDelimiter(sse_buf.items) orelse break;
                const event = sse_buf.items[0..delim.index];

                var lines = std.mem.splitScalar(u8, event, '\n');
                while (lines.next()) |line_raw| {
                    const line = std.mem.trimRight(u8, line_raw, "\r");
                    if (!std.mem.startsWith(u8, line, "data:")) continue;

                    const payload = std.mem.trim(u8, line["data:".len..], " \t\r");
                    if (payload.len == 0) continue;

                    if (std.mem.eql(u8, payload, "[DONE]")) {
                        options.callback(.{ .content = "", .done = true });
                        return;
                    }

                    const parsed = std.json.parseFromSlice(std.json.Value, self.allocator, payload, .{}) catch continue;
                    defer parsed.deinit();

                    const choices = parsed.value.object.get("choices") orelse continue;
                    if (choices.array.items.len == 0) continue;
                    const first_choice = choices.array.items[0];
                    const delta = first_choice.object.get("delta") orelse continue;
                    const content = delta.object.get("content") orelse continue;
                    if (content != .string) continue;

                    options.callback(.{ .content = content.string, .done = false });
                }

                consumePrefix(&sse_buf, delim.index + delim.len);
            }
        }

        options.callback(.{ .content = "", .done = true });
    }

    fn buildAnthropicJsonStream(self: *const Self, system_prompt: []const u8, user_prompt: []const u8) ![]const u8 {
        var buf: std.ArrayListUnmanaged(u8) = .empty;
        errdefer buf.deinit(self.allocator);

        const writer = buf.writer(self.allocator);

        try writer.writeAll("{\"model\":\"");
        try writeJsonEscapedString(writer, self.model);
        try writer.writeAll("\",\"max_tokens\":");
        try writer.print("{}", .{self.max_tokens});

        try writer.writeAll(",\"system\":\"");
        try writeJsonEscapedString(writer, system_prompt);
        try writer.writeAll("\",\"messages\":[{\"role\":\"user\",\"content\":\"");
        try writeJsonEscapedString(writer, user_prompt);
        try writer.writeAll("\"}],\"temperature\":");
        try writer.print("{d:.1}", .{self.temperature});

        try writer.writeAll(",\"stream\":true}");

        return buf.toOwnedSlice(self.allocator);
    }

    fn chatStreamAnthropic(
        self: *const Self,
        system_prompt: []const u8,
        user_prompt: []const u8,
        options: StreamOptions,
    ) !void {
        const endpoint_str = if (self.endpoint.len > 0)
            self.endpoint
        else
            "https://api.anthropic.com/v1/messages";

        var client: http.Client = .{ .allocator = self.allocator };
        defer client.deinit();

        const uri = try Uri.parse(endpoint_str);

        // Enhance system prompt with shell-specific context
        const enhanced_prompt = try self.enhanceSystemPrompt(system_prompt);
        defer self.allocator.free(enhanced_prompt);

        // Build request body with streaming enabled
        const body = try self.buildAnthropicJsonStream(enhanced_prompt, user_prompt);
        defer self.allocator.free(body);

        var req = try client.request(.POST, uri, .{
            .headers = .{ .accept_encoding = .{ .override = "identity" } },
            .extra_headers = &.{
                .{ .name = "x-api-key", .value = self.api_key },
                .{ .name = "anthropic-version", .value = "2023-06-01" },
                .{ .name = "Content-Type", .value = "application/json" },
                .{ .name = "Accept", .value = "text/event-stream" },
            },
        });
        defer req.deinit();

        try req.sendBodyComplete(@constCast(body));

        var response = try req.receiveHead(&.{});
        if (response.head.status != .ok) {
            log.err("Anthropic streaming returned status: {}", .{response.head.status});
            options.callback(.{ .content = "", .done = true });
            return error.InvalidResponse;
        }

        var transfer_buffer: [4096]u8 = undefined;
        const body_reader = response.reader(&transfer_buffer);

        var read_buf: [4096]u8 = undefined;
        var sse_buf: std.ArrayListUnmanaged(u8) = .empty;
        defer sse_buf.deinit(self.allocator);

        while (true) {
            if (isCancelled(options.cancelled)) {
                options.callback(.{ .content = "", .done = true });
                return;
            }

            const bytes_read = body_reader.readVec(&.{read_buf[0..]}) catch |err| switch (err) {
                error.EndOfStream => break,
                error.ReadFailed => {
                    log.warn("Anthropic stream read error: {}", .{err});
                    options.callback(.{ .content = "", .done = true });
                    return;
                },
            };
            if (bytes_read == 0) continue;

            try sse_buf.appendSlice(self.allocator, read_buf[0..bytes_read]);

            while (true) {
                if (isCancelled(options.cancelled)) {
                    options.callback(.{ .content = "", .done = true });
                    return;
                }

                const delim = findSseDelimiter(sse_buf.items) orelse break;
                const event = sse_buf.items[0..delim.index];

                var lines = std.mem.splitScalar(u8, event, '\n');
                while (lines.next()) |line_raw| {
                    const line = std.mem.trimRight(u8, line_raw, "\r");
                    if (!std.mem.startsWith(u8, line, "data:")) continue;

                    const payload = std.mem.trim(u8, line["data:".len..], " \t\r");
                    if (payload.len == 0) continue;

                    if (std.mem.eql(u8, payload, "event_done") or std.mem.eql(u8, payload, "[DONE]")) {
                        options.callback(.{ .content = "", .done = true });
                        return;
                    }

                    const parsed = std.json.parseFromSlice(std.json.Value, self.allocator, payload, .{}) catch continue;
                    defer parsed.deinit();

                    const obj = parsed.value.object;
                    const type_val = obj.get("type") orelse continue;
                    if (type_val != .string) continue;

                    if (std.mem.eql(u8, type_val.string, "content_block_delta")) {
                        const delta_val = obj.get("delta") orelse continue;
                        if (delta_val != .object) continue;
                        const text_val = delta_val.object.get("text") orelse continue;
                        if (text_val != .string) continue;
                        options.callback(.{ .content = text_val.string, .done = false });
                    } else if (std.mem.eql(u8, type_val.string, "message_stop")) {
                        options.callback(.{ .content = "", .done = true });
                        return;
                    }
                }

                consumePrefix(&sse_buf, delim.index + delim.len);
            }
        }

        options.callback(.{ .content = "", .done = true });
    }

    fn buildOllamaJsonStream(self: *const Self, system_prompt: []const u8, user_prompt: []const u8) ![]const u8 {
        var buf: std.ArrayListUnmanaged(u8) = .empty;
        errdefer buf.deinit(self.allocator);

        const writer = buf.writer(self.allocator);

        try writer.writeAll("{\"model\":\"");
        try writeJsonEscapedString(writer, self.model);
        try writer.writeAll("\",\"stream\":true,\"messages\":[{\"role\":\"system\",\"content\":\"");
        try writeJsonEscapedString(writer, system_prompt);
        try writer.writeAll("\"},{\"role\":\"user\",\"content\":\"");
        try writeJsonEscapedString(writer, user_prompt);
        try writer.writeAll("\"}],\"options\":{\"num_ctx\":");
        try writer.print("{}", .{self.max_tokens});
        try writer.writeAll("}}");

        return buf.toOwnedSlice(self.allocator);
    }

    fn chatStreamOllama(
        self: *const Self,
        system_prompt: []const u8,
        user_prompt: []const u8,
        options: StreamOptions,
    ) !void {
        const endpoint_str = if (self.endpoint.len > 0)
            self.endpoint
        else
            "http://localhost:11434/api/chat";

        var client: http.Client = .{ .allocator = self.allocator };
        defer client.deinit();

        const uri = try Uri.parse(endpoint_str);

        // Enhance system prompt with shell-specific context
        const enhanced_prompt = try self.enhanceSystemPrompt(system_prompt);
        defer self.allocator.free(enhanced_prompt);

        // Build request body with streaming enabled
        const body = try self.buildOllamaJsonStream(enhanced_prompt, user_prompt);
        defer self.allocator.free(body);

        var req = try client.request(.POST, uri, .{
            .headers = .{ .accept_encoding = .{ .override = "identity" } },
            .extra_headers = &.{
                .{ .name = "Content-Type", .value = "application/json" },
            },
        });
        defer req.deinit();

        try req.sendBodyComplete(@constCast(body));

        var response = try req.receiveHead(&.{});
        if (response.head.status != .ok) {
            log.err("Ollama streaming returned status: {}", .{response.head.status});
            options.callback(.{ .content = "", .done = true });
            return error.InvalidResponse;
        }

        var transfer_buffer: [4096]u8 = undefined;
        const body_reader = response.reader(&transfer_buffer);

        var read_buf: [4096]u8 = undefined;
        var line_buf: std.ArrayListUnmanaged(u8) = .empty;
        defer line_buf.deinit(self.allocator);

        while (true) {
            if (isCancelled(options.cancelled)) {
                options.callback(.{ .content = "", .done = true });
                return;
            }

            const bytes_read = body_reader.readVec(&.{read_buf[0..]}) catch |err| switch (err) {
                error.EndOfStream => break,
                error.ReadFailed => {
                    log.warn("Ollama stream read error: {}", .{err});
                    options.callback(.{ .content = "", .done = true });
                    return;
                },
            };
            if (bytes_read == 0) continue;

            try line_buf.appendSlice(self.allocator, read_buf[0..bytes_read]);

            while (true) {
                const line_end = std.mem.indexOfScalar(u8, line_buf.items, '\n') orelse break;
                const line_raw = std.mem.trimRight(u8, line_buf.items[0..line_end], "\r");
                if (line_raw.len == 0) {
                    consumePrefix(&line_buf, line_end + 1);
                    continue;
                }

                const parsed = std.json.parseFromSlice(std.json.Value, self.allocator, line_raw, .{}) catch {
                    consumePrefix(&line_buf, line_end + 1);
                    continue;
                };
                defer parsed.deinit();

                const obj = parsed.value.object;
                if (obj.get("done")) |done_val| {
                    if (done_val == .bool and done_val.bool) {
                        options.callback(.{ .content = "", .done = true });
                        return;
                    }
                }

                const message_val = obj.get("message") orelse {
                    consumePrefix(&line_buf, line_end + 1);
                    continue;
                };
                if (message_val != .object) {
                    consumePrefix(&line_buf, line_end + 1);
                    continue;
                }

                const content_val = message_val.object.get("content") orelse {
                    consumePrefix(&line_buf, line_end + 1);
                    continue;
                };
                if (content_val != .string) {
                    consumePrefix(&line_buf, line_end + 1);
                    continue;
                }

                options.callback(.{ .content = content_val.string, .done = false });
                consumePrefix(&line_buf, line_end + 1);
            }
        }

        options.callback(.{ .content = "", .done = true });
    }

    fn chatStreamCustom(
        self: *const Self,
        system_prompt: []const u8,
        user_prompt: []const u8,
        options: StreamOptions,
    ) !void {
        // Custom endpoints are OpenAI-compatible.
        return self.chatStreamOpenAI(system_prompt, user_prompt, options);
    }

    fn buildCerebrasJsonStream(self: *const Self, system_prompt: []const u8, user_prompt: []const u8) ![]const u8 {
        var buf: std.ArrayListUnmanaged(u8) = .empty;
        errdefer buf.deinit(self.allocator);

        const writer = buf.writer(self.allocator);

        try writer.writeAll("{\"model\":\"");
        try writeJsonEscapedString(writer, self.model);
        try writer.writeAll("\",\"messages\":[{\"role\":\"system\",\"content\":\"");
        try writeJsonEscapedString(writer, system_prompt);
        try writer.writeAll("\"},{\"role\":\"user\",\"content\":\"");
        try writeJsonEscapedString(writer, user_prompt);
        try writer.writeAll("\"}],\"max_tokens\":");
        try writer.print("{}", .{self.max_tokens});

        try writer.writeAll(",\"temperature\":");
        try writer.print("{d:.1}", .{self.temperature});

        try writer.writeAll(",\"stream\":true}");

        return buf.toOwnedSlice(self.allocator);
    }

    fn chatStreamCerebras(
        self: *const Self,
        system_prompt: []const u8,
        user_prompt: []const u8,
        options: StreamOptions,
    ) !void {
        const endpoint_str = if (self.endpoint.len > 0)
            self.endpoint
        else
            "https://api.cerebras.ai/v1/chat/completions";

        var client: http.Client = .{ .allocator = self.allocator };
        defer client.deinit();

        const uri = try Uri.parse(endpoint_str);

        // Enhance system prompt with shell-specific context
        const enhanced_prompt = try self.enhanceSystemPrompt(system_prompt);
        defer self.allocator.free(enhanced_prompt);

        // Build request body with streaming enabled
        const body = try self.buildCerebrasJsonStream(enhanced_prompt, user_prompt);
        defer self.allocator.free(body);

        // Build authorization header
        const auth_header = try std.fmt.allocPrint(self.allocator, "Bearer {s}", .{self.api_key});
        defer self.allocator.free(auth_header);

        var req = try client.request(.POST, uri, .{
            .headers = .{ .accept_encoding = .{ .override = "identity" } },
            .extra_headers = &.{
                .{ .name = "Authorization", .value = auth_header },
                .{ .name = "Content-Type", .value = "application/json" },
                .{ .name = "Accept", .value = "text/event-stream" },
            },
        });
        defer req.deinit();

        try req.sendBodyComplete(@constCast(body));

        var response = try req.receiveHead(&.{});
        if (response.head.status != .ok) {
            log.err("Cerebras streaming returned status: {}", .{response.head.status});
            options.callback(.{ .content = "", .done = true });
            return error.InvalidResponse;
        }

        var transfer_buffer: [4096]u8 = undefined;
        const body_reader = response.reader(&transfer_buffer);

        var read_buf: [4096]u8 = undefined;
        var sse_buf: std.ArrayListUnmanaged(u8) = .empty;
        defer sse_buf.deinit(self.allocator);

        while (true) {
            if (isCancelled(options.cancelled)) {
                options.callback(.{ .content = "", .done = true });
                return;
            }

            const bytes_read = body_reader.readVec(&.{read_buf[0..]}) catch |err| switch (err) {
                error.EndOfStream => break,
                error.ReadFailed => {
                    log.warn("Cerebras stream read error: {}", .{err});
                    options.callback(.{ .content = "", .done = true });
                    return;
                },
            };
            if (bytes_read == 0) continue;

            try sse_buf.appendSlice(self.allocator, read_buf[0..bytes_read]);

            while (true) {
                if (isCancelled(options.cancelled)) {
                    options.callback(.{ .content = "", .done = true });
                    return;
                }

                const delim = findSseDelimiter(sse_buf.items) orelse break;
                const event = sse_buf.items[0..delim.index];

                var lines = std.mem.splitScalar(u8, event, '\n');
                while (lines.next()) |line_raw| {
                    const line = std.mem.trimRight(u8, line_raw, "\r");
                    if (!std.mem.startsWith(u8, line, "data:")) continue;

                    const payload = std.mem.trim(u8, line["data:".len..], " \t\r");
                    if (payload.len == 0) continue;

                    if (std.mem.eql(u8, payload, "[DONE]")) {
                        options.callback(.{ .content = "", .done = true });
                        return;
                    }

                    const parsed = std.json.parseFromSlice(std.json.Value, self.allocator, payload, .{}) catch continue;
                    defer parsed.deinit();

                    const choices = parsed.value.object.get("choices") orelse continue;
                    if (choices.array.items.len == 0) continue;
                    const first_choice = choices.array.items[0];
                    const delta = first_choice.object.get("delta") orelse continue;
                    const content = delta.object.get("content") orelse continue;
                    if (content != .string) continue;

                    options.callback(.{ .content = content.string, .done = false });
                }

                consumePrefix(&sse_buf, delim.index + delim.len);
            }
        }

        options.callback(.{ .content = "", .done = true });
    }

    /// Send a streaming chat completion request
    /// The callback will be invoked for each chunk of the response
    pub fn chatStream(
        self: *const Self,
        system_prompt: []const u8,
        user_prompt: []const u8,
        options: StreamOptions,
    ) !void {
        if (!options.enabled) {
            // If streaming is disabled, use regular chat
            const response = try self.chat(system_prompt, user_prompt);
            defer response.deinit(self.allocator);
            options.callback(.{
                .content = response.content,
                .done = true,
            });
            return;
        }

        // Route to provider-specific streaming implementation
        switch (self.provider) {
            .openai => return self.chatStreamOpenAI(system_prompt, user_prompt, options),
            .anthropic => return self.chatStreamAnthropic(system_prompt, user_prompt, options),
            .ollama => return self.chatStreamOllama(system_prompt, user_prompt, options),
            .custom => return self.chatStreamCustom(system_prompt, user_prompt, options),
            .cerebras => return self.chatStreamCerebras(system_prompt, user_prompt, options),
        }
    }
};

/// Chat response from AI
pub const ChatResponse = struct {
    content: []const u8,
    model: []const u8,
    provider: []const u8,

    pub fn deinit(self: *const ChatResponse, alloc: Allocator) void {
        alloc.free(self.content);
        alloc.free(self.model);
        // provider is a string literal, don't free
    }
};

/// Streaming chunk from AI
pub const StreamChunk = struct {
    content: []const u8,
    done: bool,
};

/// Callback for streaming responses
pub const StreamCallback = *const fn (chunk: StreamChunk) void;

/// Options for streaming chat completion
pub const StreamOptions = struct {
    callback: StreamCallback,
    /// If true, stream the response. Otherwise use regular completion.
    enabled: bool = false,
    /// Optional cancellation flag (true means cancel/stop).
    cancelled: ?*const std.atomic.Value(bool) = null,
};

// ============================================================================
// Tests
// ============================================================================

test "findSseDelimiter with LF delimiter" {
    const buf1 = "data: hello\n\ndata: world";
    const result1 = findSseDelimiter(buf1);
    try std.testing.expect(result1 != null);
    try std.testing.expectEqual(@as(usize, 11), result1.?.index);
    try std.testing.expectEqual(@as(usize, 2), result1.?.len);
}

test "findSseDelimiter with CRLF delimiter" {
    const buf2 = "data: hello\r\n\r\ndata: world";
    const result2 = findSseDelimiter(buf2);
    try std.testing.expect(result2 != null);
    try std.testing.expectEqual(@as(usize, 11), result2.?.index);
    try std.testing.expectEqual(@as(usize, 4), result2.?.len);
}

test "findSseDelimiter with no delimiter" {
    const buf3 = "data: hello\ndata: world";
    const result3 = findSseDelimiter(buf3);
    try std.testing.expectEqual(@as(?SseDelimiter, null), result3);
}

test "consumePrefix removes bytes from buffer" {
    const alloc = std.testing.allocator;
    var buf: std.ArrayListUnmanaged(u8) = .empty;
    defer buf.deinit(alloc);

    try buf.appendSlice(alloc, "hello world");
    consumePrefix(&buf, 6);
    try std.testing.expectEqualStrings("world", buf.items);
}

test "consumePrefix handles full consumption" {
    const alloc = std.testing.allocator;
    var buf: std.ArrayListUnmanaged(u8) = .empty;
    defer buf.deinit(alloc);

    try buf.appendSlice(alloc, "hello");
    consumePrefix(&buf, 5);
    try std.testing.expectEqual(@as(usize, 0), buf.items.len);
}

test "consumePrefix handles over-consumption" {
    const alloc = std.testing.allocator;
    var buf: std.ArrayListUnmanaged(u8) = .empty;
    defer buf.deinit(alloc);

    try buf.appendSlice(alloc, "hello");
    consumePrefix(&buf, 10);
    try std.testing.expectEqual(@as(usize, 0), buf.items.len);
}

test "isCancelled returns false for null" {
    try std.testing.expectEqual(false, isCancelled(null));
}

test "isCancelled returns false when not cancelled" {
    var cancelled = std.atomic.Value(bool).init(false);
    try std.testing.expectEqual(false, isCancelled(&cancelled));
}

test "isCancelled returns true when cancelled" {
    var cancelled = std.atomic.Value(bool).init(true);
    try std.testing.expectEqual(true, isCancelled(&cancelled));
}

test "writeJsonEscapedString handles special characters" {
    const alloc = std.testing.allocator;
    var buf: std.ArrayListUnmanaged(u8) = .empty;
    defer buf.deinit(alloc);
    const writer = buf.writer(alloc);

    try writeJsonEscapedString(writer, "hello\nworld\t\"test\"\\path");

    try std.testing.expectEqualStrings("hello\\nworld\\t\\\"test\\\"\\\\path", buf.items);
}

test "writeJsonEscapedString handles control characters" {
    const alloc = std.testing.allocator;
    var buf: std.ArrayListUnmanaged(u8) = .empty;
    defer buf.deinit(alloc);
    const writer = buf.writer(alloc);

    try writeJsonEscapedString(writer, "a\x01b");

    // Control character 0x01 should be escaped as \u0001
    try std.testing.expectEqualStrings("a\\u0001b", buf.items);
}

test "StreamChunk done flag semantics" {
    // Test that done=true signals end of stream
    const chunk_final = StreamChunk{ .content = "", .done = true };
    try std.testing.expect(chunk_final.done);
    try std.testing.expectEqual(@as(usize, 0), chunk_final.content.len);

    // Test that done=false signals more content coming
    const chunk_partial = StreamChunk{ .content = "hello", .done = false };
    try std.testing.expect(!chunk_partial.done);
    try std.testing.expectEqualStrings("hello", chunk_partial.content);
}

// ============================================================================
// Cerebras Unit Tests
// ============================================================================

test "Provider enum includes cerebras variant" {
    const provider = Provider.cerebras;
    try std.testing.expectEqual(Provider.cerebras, provider);
}

test "Client initialization with Cerebras provider" {
    const alloc = std.testing.allocator;
    
    const client = Client.init(
        alloc,
        Provider.cerebras,
        "test-api-key",
        "",
        "llama3.1-8b",
        1000,
        0.7,
    );
    
    try std.testing.expectEqual(Provider.cerebras, client.provider);
    try std.testing.expectEqualStrings("test-api-key", client.api_key);
    try std.testing.expectEqualStrings("llama3.1-8b", client.model);
    try std.testing.expectEqual(@as(u32, 1000), client.max_tokens);
    try std.testing.expectEqual(@as(f32, 0.7), client.temperature);
}

test "buildCerebrasJson creates valid JSON structure" {
    const alloc = std.testing.allocator;
    const client = Client.init(
        alloc,
        Provider.cerebras,
        "test-key",
        "",
        "llama3.1-8b",
        1000,
        0.7,
    );
    
    const json = try client.buildCerebrasJson("You are a helpful assistant", "Hello, world!");
    defer alloc.free(json);
    
    // Parse the JSON to verify it's valid
    const parsed = try std.json.parseFromSlice(std.json.Value, alloc, json, .{});
    defer parsed.deinit();
    
    // Verify structure
    const obj = parsed.value.object;
    try std.testing.expect(obj.contains("model"));
    try std.testing.expect(obj.contains("messages"));
    try std.testing.expect(obj.contains("max_tokens"));
    try std.testing.expect(obj.contains("temperature"));
    
    // Verify model
    const model = obj.get("model").?;
    try std.testing.expectEqualStrings("llama3.1-8b", model.string);
    
    // Verify messages array
    const messages = obj.get("messages").?.array;
    try std.testing.expectEqual(@as(usize, 2), messages.items.len);
    
    // Verify system message
    const system_msg = messages.items[0].object;
    try std.testing.expectEqualStrings("system", system_msg.get("role").?.string);
    try std.testing.expectEqualStrings("You are a helpful assistant", system_msg.get("content").?.string);
    
    // Verify user message
    const user_msg = messages.items[1].object;
    try std.testing.expectEqualStrings("user", user_msg.get("role").?.string);
    try std.testing.expectEqualStrings("Hello, world!", user_msg.get("content").?.string);
}

test "buildCerebrasJson handles JSON special characters" {
    const alloc = std.testing.allocator;
    const client = Client.init(
        alloc,
        Provider.cerebras,
        "test-key",
        "",
        "llama3.1-8b",
        1000,
        0.7,
    );
    
    const json = try client.buildCerebrasJson("System \"prompt\" with\nnewlines", "User \"prompt\" with\ttabs");
    defer alloc.free(json);
    
    // Verify JSON contains escaped characters
    try std.testing.expect(std.mem.indexOf(u8, json, "\\\"") != null); // Escaped quotes
    try std.testing.expect(std.mem.indexOf(u8, json, "\\n") != null); // Escaped newlines
    try std.testing.expect(std.mem.indexOf(u8, json, "\\t") != null); // Escaped tabs
}

test "buildCerebrasJsonStream creates valid streaming JSON" {
    const alloc = std.testing.allocator;
    const client = Client.init(
        alloc,
        Provider.cerebras,
        "test-key",
        "",
        "llama3.1-8b",
        2048,
        0.8,
    );
    
    const json = try client.buildCerebrasJsonStream("System prompt", "User prompt");
    defer alloc.free(json);
    
    // Parse the JSON to verify it's valid
    const parsed = try std.json.parseFromSlice(std.json.Value, alloc, json, .{});
    defer parsed.deinit();
    
    // Verify stream is enabled
    const obj = parsed.value.object;
    const stream = obj.get("stream").?;
    try std.testing.expect(stream == .bool);
    try std.testing.expect(stream.bool);
    
    // Verify other fields
    try std.testing.expectEqualStrings("llama3.1-8b", obj.get("model").?.string);
    try std.testing.expectEqual(@as(i64, 2048), obj.get("max_tokens").?.integer);
}

test "Chat response structure for Cerebras" {
    const alloc = std.testing.allocator;
    
    // Simulate a Cerebras API response
    const mock_response = "{\"id\":\"chatcmpl-123\",\"object\":\"chat.completion\",\"created\":1234567890,\"model\":\"llama3.1-8b\",\"choices\":[{\"index\":0,\"message\":{\"role\":\"assistant\",\"content\":\"This is a test response\"},\"finish_reason\":\"stop\"}]}";
    
    const parsed = try std.json.parseFromSlice(std.json.Value, alloc, mock_response, .{});
    defer parsed.deinit();
    
    // Verify we can extract the content
    const obj = parsed.value.object;
    const choices = obj.get("choices").?.array;
    try std.testing.expectEqual(@as(usize, 1), choices.items.len);
    
    const first_choice = choices.items[0].object;
    const message = first_choice.get("message").?.object;
    const content = message.get("content").?.string;
    
    try std.testing.expectEqualStrings("This is a test response", content);
    try std.testing.expectEqualStrings("llama3.1-8b", obj.get("model").?.string);
}

test "Cerebras error response handling" {
    const alloc = std.testing.allocator;
    
    // Simulate a Cerebras API error response
    const mock_error = "{\"error\":{\"message\":\"Invalid API key\",\"type\":\"authentication_error\",\"code\":\"invalid_api_key\"}}";
    
    const parsed = try std.json.parseFromSlice(std.json.Value, alloc, mock_error, .{});
    defer parsed.deinit();
    
    // Verify we can extract the error message
    const obj = parsed.value.object;
    const error_obj = obj.get("error").?.object;
    const message = error_obj.get("message").?.string;
    
    try std.testing.expectEqualStrings("Invalid API key", message);
}

test "Cerebras API endpoint default value" {
    const alloc = std.testing.allocator;
    const client = Client.init(
        alloc,
        Provider.cerebras,
        "test-key",
        "",  // Empty endpoint should use default
        "llama3.1-8b",
        1000,
        0.7,
    );
    
    // When endpoint is empty, it should resolve to the default Cerebras API endpoint
    try std.testing.expectEqualStrings("", client.endpoint);
}

test "Cerebras with custom endpoint" {
    const alloc = std.testing.allocator;
    const client = Client.init(
        alloc,
        Provider.cerebras,
        "test-key",
        "https://custom.api.cerebras.ai/v1/chat/completions",
        "llama3.1-8b",
        1000,
        0.7,
    );
    
    try std.testing.expectEqualStrings("https://custom.api.cerebras.ai/v1/chat/completions", client.endpoint);
}

test "StreamChunk for Cerebras streaming response" {
    // Test streaming chunk with content
    const chunk_with_content = StreamChunk{ .content = "streaming ", .done = false };
    try std.testing.expect(!chunk_with_content.done);
    try std.testing.expectEqualStrings("streaming ", chunk_with_content.content);
    
    // Test final chunk
    const chunk_final = StreamChunk{ .content = "", .done = true };
    try std.testing.expect(chunk_final.done);
    try std.testing.expectEqual(@as(usize, 0), chunk_final.content.len);
}

test "Cerebras model validation" {
    const models = [_][]const u8{
        "llama3.1-8b",
        "llama3.1-70b",
        "llama3.3-70b",
    };
    
    for (models) |model| {
        const alloc = std.testing.allocator;
        const client = Client.init(
            alloc,
            Provider.cerebras,
            "test-key",
            "",
            model,
            1000,
            0.7,
        );
        
        try std.testing.expectEqualStrings(model, client.model);
    }
}

test "buildCerebrasJson with empty prompts" {
    const alloc = std.testing.allocator;
    const client = Client.init(
        alloc,
        Provider.cerebras,
        "test-key",
        "",
        "llama3.1-8b",
        1000,
        0.7,
    );
    
    const json = try client.buildCerebrasJson("", "");
    defer alloc.free(json);
    
    // Should still produce valid JSON
    const parsed = try std.json.parseFromSlice(std.json.Value, alloc, json, .{});
    defer parsed.deinit();
    
    const obj = parsed.value.object;
    const messages = obj.get("messages").?.array;
    try std.testing.expectEqual(@as(usize, 2), messages.items.len);
    
    // Both messages should have empty content
    const system_msg = messages.items[0].object;
    try std.testing.expectEqualStrings("", system_msg.get("content").?.string);
    
    const user_msg = messages.items[1].object;
    try std.testing.expectEqualStrings("", user_msg.get("content").?.string);
}

test "Cerebras temperature parameter edge cases" {
    const alloc = std.testing.allocator;
    
    // Test minimum temperature (0.0)
    const client1 = Client.init(alloc, Provider.cerebras, "key", "", "model", 1000, 0.0);
    const json1 = try client1.buildCerebrasJson("system", "user");
    defer alloc.free(json1);
    try std.testing.expect(std.mem.indexOf(u8, json1, "\"temperature\":0.0") != null);
    
    // Test maximum temperature (2.0)
    const client2 = Client.init(alloc, Provider.cerebras, "key", "", "model", 1000, 2.0);
    const json2 = try client2.buildCerebrasJson("system", "user");
    defer alloc.free(json2);
    try std.testing.expect(std.mem.indexOf(u8, json2, "\"temperature\":2.0") != null);
}

test "Cerebras JSON escaping edge cases" {
    const alloc = std.testing.allocator;
    const client = Client.init(
        alloc,
        Provider.cerebras,
        "test-key",
        "",
        "llama3.1-8b",
        1000,
        0.7,
    );
    
    const test_cases = [_][]const u8{
        "Backslash: \\",
        "Quotes: \"hello\"",
        "Newlines: \nline1\nline2",
        "Tabs: \tindented",
        "Carriage return: \r",
        "Mixed: \"test\"\nwith\ttabs\rand\\backslashes",
    };
    
    for (test_cases) |test_case| {
        const json = try client.buildCerebrasJson(test_case, test_case);
        defer alloc.free(json);
        
        // Verify JSON is valid
        const parsed = try std.json.parseFromSlice(std.json.Value, alloc, json, .{});
        defer parsed.deinit();
        
        // Verify the escaped content is preserved
        const obj = parsed.value.object;
        const messages = obj.get("messages").?.array;
        const system_msg = messages.items[0].object;
        try std.testing.expectEqualStrings(test_case, system_msg.get("content").?.string);
    }
}