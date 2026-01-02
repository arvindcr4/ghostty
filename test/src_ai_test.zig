const std = @import("std");
const testing = std.testing;
const ai = @import("../src/ai/main.zig");

test "AI module initialization" {
    const allocator = testing.allocator;
    var instance = try ai.AI.init(allocator);
    defer instance.deinit();
    
    try testing.expect(instance.isInitialized());
}

test "AI model loading" {
    const allocator = testing.allocator;
    var instance = try ai.AI.init(allocator);
    defer instance.deinit();
    
    try instance.loadModel("gpt-4");
    try testing.expectEqualStrings("gpt-4", instance.getCurrentModel());
}

test "AI configuration" {
    const allocator = testing.allocator;
    var instance = try ai.AI.init(allocator);
    defer instance.deinit();
    
    const config = ai.AI.Config{
        .max_tokens = 2048,
        .temperature = 0.7,
        .top_p = 0.9,
    };
    
    try instance.configure(config);
    const loaded_config = instance.getConfig();
    try testing.expectEqual(config.max_tokens, loaded_config.max_tokens);
    try testing.expectEqual(config.temperature, loaded_config.temperature);
}

test "AI request processing" {
    const allocator = testing.allocator;
    var instance = try ai.AI.init(allocator);
    defer instance.deinit();
    
    const request = "Hello, AI!";
    const response = try instance.processRequest(request);
    defer allocator.free(response);
    
    try testing.expect(response.len > 0);
}

test "AI streaming responses" {
    const allocator = testing.allocator;
    var instance = try ai.AI.init(allocator);
    defer instance.deinit();
    
    var chunks = std.ArrayList([]const u8).init(allocator);
    defer {
        for (chunks.items) |chunk| allocator.free(chunk);
        chunks.deinit();
    }
    
    try instance.streamResponse("Tell me a story", &chunks);
    try testing.expect(chunks.items.len > 0);
}

test "AI error handling" {
    const allocator = testing.allocator;
    var instance = try ai.AI.init(allocator);
    defer instance.deinit();
    
    try testing.expectError(error.InvalidModel, instance.loadModel(""));
    try testing.expectError(error.EmptyRequest, instance.processRequest(""));
}

test "AI performance metrics" {
    const allocator = testing.allocator;
    var instance = try ai.AI.init(allocator);
    defer instance.deinit();
    
    _ = try instance.processRequest("Test request");
    const metrics = instance.getMetrics();
    
    try testing.expect(metrics.request_count > 0);
    try testing.expect(metrics.total_tokens > 0);
    try testing.expect(metrics.average_response_time > 0);
}

test "AI model switching" {
    const allocator = testing.allocator;
    var instance = try ai.AI.init(allocator);
    defer instance.deinit();
    
    try instance.loadModel("gpt-3.5-turbo");
    try testing.expectEqualStrings("gpt-3.5-turbo", instance.getCurrentModel());
    
    try instance.loadModel("gpt-4");
    try testing.expectEqualStrings("gpt-4", instance.getCurrentModel());
}

test "AI context management" {
    const allocator = testing.allocator;
    var instance = try ai.AI.init(allocator);
    defer instance.deinit();
    
    try instance.addToContext("System: You are a helpful assistant");
    try instance.addToContext("User: Hello");
    
    const context = instance.getContext();
    try testing.expect(context.items.len == 2);
}

test "AI token counting" {
    const allocator = testing.allocator;
    var instance = try ai.AI.init(allocator);
    defer instance.deinit();
    
    const text = "This is a test message for token counting";
    const count = instance.countTokens(text);
    try testing.expect(count > 0);
}

test "AI rate limiting" {
    const allocator = testing.allocator;
    var instance = try ai.AI.init(allocator);
    defer instance.deinit();
    
    instance.setRateLimit(10, 60); // 10 requests per minute
    
    for (0..5) |_| {
        _ = try instance.processRequest("Test");
    }
    
    try testing.expect(!instance.isRateLimited());
}

test "AI caching" {
    const allocator = testing.allocator;
    var instance = try ai.AI.init(allocator);
    defer instance.deinit();
    
    instance.enableCaching(true);
    
    const request = "What is 2+2?";
    const response1 = try instance.processRequest(request);
    defer allocator.free(response1);
    
    const response2 = try instance.processRequest(request);
    defer allocator.free(response2);
    
    try testing.expectEqualStrings(response1, response2);
}

test "AI model capabilities" {
    const allocator = testing.allocator;
    var instance = try ai.AI.init(allocator);
    defer instance.deinit();
    
    try instance.loadModel("gpt-4");
    const capabilities = instance.getModelCapabilities();
    
    try testing.expect(capabilities.supports_functions);
    try testing.expect(capabilities.supports_streaming);
    try testing.expect(capabilities.max_tokens > 0);
}

test "AI conversation reset" {
    const allocator = testing.allocator;
    var instance = try ai.AI.init(allocator);
    defer instance.deinit();
    
    try instance.addToContext("Test message");
    try testing.expect(instance.getContext().items.len > 0);
    
    instance.resetConversation();
    try testing.expect(instance.getContext().items.len == 0);
}

test "AI batch processing" {
    const allocator = testing.allocator;
    var instance = try ai.AI.init(allocator);
    defer instance.deinit();
    
    const requests = [_][]const u8{ "Hello", "How are you?", "Goodbye" };
    const responses = try instance.batchProcess(&requests);
    defer {
        for (responses) |response| allocator.free(response);
        allocator.free(responses);
    }
    
    try testing.expectEqual(requests.len, responses.len);
    for (responses) |response| {
        try testing.expect(response.len > 0);
    }
}