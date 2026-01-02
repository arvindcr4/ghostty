//! Unit tests for Workflow Management module
//! Tests workflow creation, parameter substitution, and persistence

const std = @import("std");
const testing = std.testing;
const Allocator = std.mem.Allocator;

const workflow = @import("../../src/ai/workflow.zig");

test "Parameter initialization and deinit" {
    const alloc = testing.allocator;

    var param = workflow.Parameter{
        .name = try alloc.dupe(u8, "files"),
        .description = try alloc.dupe(u8, "Files to stage"),
        .default_value = try alloc.dupe(u8, "."),
        .required = false,
    };
    defer param.deinit(alloc);

    try testing.expectEqualStrings(param.name, "files");
    try testing.expectEqualStrings(param.description, "Files to stage");
    try testing.expectEqualStrings(param.default_value.?, ".");
    try testing.expect(param.required == false);
}

test "Parameter with null default value deinit" {
    const alloc = testing.allocator;

    var param = workflow.Parameter{
        .name = try alloc.dupe(u8, "message"),
        .description = try alloc.dupe(u8, "Commit message"),
        .default_value = null,
        .required = true,
    };
    defer param.deinit(alloc);

    try testing.expect(param.default_value == null);
    try testing.expect(param.required == true);
}

test "Workflow initialization" {
    const alloc = testing.allocator;

    const id = try alloc.dupe(u8, "test-workflow-id");
    const name = try alloc.dupe(u8, "Test Workflow");
    defer alloc.free(id);
    defer alloc.free(name);

    var wf = workflow.Workflow.init(alloc, id, name);
    defer wf.deinit(alloc);

    try testing.expectEqual(wf.id, id);
    try testing.expectEqual(wf.name, name);
    try testing.expectEqual(wf.description, "");
    try testing.expectEqual(wf.commands.items.len, 0);
    try testing.expectEqual(wf.parameters.items.len, 0);
    try testing.expectEqual(wf.tags.items.len, 0);
    try testing.expect(wf.created_at > 0);
    try testing.expect(wf.updated_at > 0);
}

test "Workflow deinit with all fields populated" {
    const alloc = testing.allocator;

    const id = try alloc.dupe(u8, "test-workflow-id");
    const name = try alloc.dupe(u8, "Test Workflow");
    defer alloc.free(id);
    defer alloc.free(name);

    var wf = workflow.Workflow.init(alloc, id, name);

    // Populate fields
    wf.description = try alloc.dupe(u8, "Test description");
    try wf.commands.append(try alloc.dupe(u8, "echo hello"));
    try wf.parameters.append(.{
        .name = try alloc.dupe(u8, "param1"),
        .description = try alloc.dupe(u8, "Test parameter"),
        .default_value = null,
        .required = false,
    });
    try wf.tags.append(try alloc.dupe(u8, "test"));

    wf.deinit(alloc);
}

test "Workflow render without parameters" {
    const alloc = testing.allocator;

    const id = try alloc.dupe(u8, "test-workflow");
    const name = try alloc.dupe(u8, "Test");
    defer alloc.free(id);
    defer alloc.free(name);

    var wf = workflow.Workflow.init(alloc, id, name);
    defer wf.deinit(alloc);

    try wf.commands.append(try alloc.dupe(u8, "echo hello"));
    try wf.commands.append(try alloc.dupe(u8, "echo world"));

    const values = std.StringHashMap([]const u8).init(alloc);
    const result = try wf.render(alloc, values);
    defer {
        for (result.items) |cmd| alloc.free(cmd);
        result.deinit();
    }

    try testing.expectEqual(result.items.len, 2);
    try testing.expectEqualStrings(result.items[0], "echo hello");
    try testing.expectEqualStrings(result.items[1], "echo world");
}

test "Workflow render with parameter substitution" {
    const alloc = testing.allocator;

    const id = try alloc.dupe(u8, "test-workflow");
    const name = try alloc.dupe(u8, "Test");
    defer alloc.free(id);
    defer alloc.free(name);

    var wf = workflow.Workflow.init(alloc, id, name);
    defer wf.deinit(alloc);

    try wf.commands.append(try alloc.dupe(u8, "echo {{message}}"));
    try wf.parameters.append(.{
        .name = try alloc.dupe(u8, "message"),
        .description = try alloc.dupe(u8, "Message to print"),
        .default_value = null,
        .required = true,
    });

    const values = std.StringHashMap([]const u8).init(alloc);
    try values.put("message", "Hello World");

    const result = try wf.render(alloc, values);
    defer {
        for (result.items) |cmd| alloc.free(cmd);
        result.deinit();
    }

    try testing.expectEqual(result.items.len, 1);
    try testing.expectEqualStrings(result.items[0], "echo Hello World");
}

test "Workflow render with default values" {
    const alloc = testing.allocator;

    const id = try alloc.dupe(u8, "test-workflow");
    const name = try alloc.dupe(u8, "Test");
    defer alloc.free(id);
    defer alloc.free(name);

    var wf = workflow.Workflow.init(alloc, id, name);
    defer wf.deinit(alloc);

    try wf.commands.append(try alloc.dupe(u8, "git add {{files}}"));
    try wf.parameters.append(.{
        .name = try alloc.dupe(u8, "files"),
        .description = try alloc.dupe(u8, "Files to stage"),
        .default_value = try alloc.dupe(u8, "."),
        .required = false,
    });

    const values = std.StringHashMap([]const u8).init(alloc);

    const result = try wf.render(alloc, values);
    defer {
        for (result.items) |cmd| alloc.free(cmd);
        result.deinit();
    }

    try testing.expectEqualStrings(result.items[0], "git add .");
}

test "Workflow render with multiple parameters" {
    const alloc = testing.allocator;

    const id = try alloc.dupe(u8, "test-workflow");
    const name = try alloc.dupe(u8, "Test");
    defer alloc.free(id);
    defer alloc.free(name);

    var wf = workflow.Workflow.init(alloc, id, name);
    defer wf.deinit(alloc);

    try wf.commands.append(try alloc.dupe(u8, "docker run -p {{port}}:{{port}} {{image}}"));

    try wf.parameters.append(.{
        .name = try alloc.dupe(u8, "port"),
        .description = try alloc.dupe(u8, "Port"),
        .default_value = try alloc.dupe(u8, "8080"),
        .required = false,
    });
    try wf.parameters.append(.{
        .name = try alloc.dupe(u8, "image"),
        .description = try alloc.dupe(u8, "Docker image"),
        .default_value = try alloc.dupe(u8, "myapp"),
        .required = false,
    });

    const values = std.StringHashMap([]const u8).init(alloc);
    try values.put("image", "nginx");

    const result = try wf.render(alloc, values);
    defer {
        for (result.items) |cmd| alloc.free(cmd);
        result.deinit();
    }

    // port uses default (8080), image uses provided value (nginx)
    try testing.expectEqualStrings(result.items[0], "docker run -p 8080:8080 nginx");
}

test "Workflow render with missing parameter" {
    const alloc = testing.allocator;

    const id = try alloc.dupe(u8, "test-workflow");
    const name = try alloc.dupe(u8, "Test");
    defer alloc.free(id);
    defer alloc.free(name);

    var wf = workflow.Workflow.init(alloc, id, name);
    defer wf.deinit(alloc);

    try wf.commands.append(try alloc.dupe(u8, "echo {{missing}}"));

    const values = std.StringHashMap([]const u8).init(alloc);

    const result = try wf.render(alloc, values);
    defer {
        for (result.items) |cmd| alloc.free(cmd);
        result.deinit();
    }

    // Missing parameter should be replaced with empty string
    try testing.expectEqualStrings(result.items[0], "echo ");
}

test "Workflow render with mixed content" {
    const alloc = testing.allocator;

    const id = try alloc.dupe(u8, "test-workflow");
    const name = try alloc.dupe(u8, "Test");
    defer alloc.free(id);
    defer alloc.free(name);

    var wf = workflow.Workflow.init(alloc, id, name);
    defer wf.deinit(alloc);

    try wf.commands.append(try alloc.dupe(u8, "echo start {{name}} end"));

    try wf.parameters.append(.{
        .name = try alloc.dupe(u8, "name"),
        .description = try alloc.dupe(u8, "Name"),
        .default_value = null,
        .required = false,
    });

    const values = std.StringHashMap([]const u8).init(alloc);
    try values.put("name", "test");

    const result = try wf.render(alloc, values);
    defer {
        for (result.items) |cmd| alloc.free(cmd);
        result.deinit();
    }

    try testing.expectEqualStrings(result.items[0], "echo start test end");
}

test "BuiltinWorkflows gitCommit" {
    const alloc = testing.allocator;

    const wf = try workflow.BuiltinWorkflows.gitCommit(alloc);
    defer {
        wf.deinit(alloc);
        alloc.destroy(wf);
    };

    try testing.expectEqualStrings(wf.id, "builtin-git-commit");
    try testing.expectEqualStrings(wf.name, "Git Commit & Push");
    try testing.expect(wf.commands.items.len == 3);
    try testing.expect(wf.parameters.items.len == 2);

    const values = std.StringHashMap([]const u8).init(alloc);
    try values.put("files", ".");
    try values.put("message", "Initial commit");

    const result = try wf.render(alloc, values);
    defer {
        for (result.items) |cmd| alloc.free(cmd);
        result.deinit();
    }

    try testing.expectEqualStrings(result.items[0], "git add .");
    try testing.expectEqualStrings(result.items[1], "git commit -m \"Initial commit\"");
    try testing.expectEqualStrings(result.items[2], "git push");
}

test "BuiltinWorkflows dockerBuildRun" {
    const alloc = testing.allocator;

    const wf = try workflow.BuiltinWorkflows.dockerBuildRun(alloc);
    defer {
        wf.deinit(alloc);
        alloc.destroy(wf);
    };

    try testing.expectEqualStrings(wf.id, "builtin-docker-build");
    try testing.expectEqualStrings(wf.name, "Docker Build & Run");
    try testing.expect(wf.commands.items.len == 2);
    try testing.expect(wf.parameters.items.len == 3);

    const values = std.StringHashMap([]const u8).init(alloc);
    try values.put("image_name", "myapp");
    try values.put("path", ".");
    try values.put("port", "3000");

    const result = try wf.render(alloc, values);
    defer {
        for (result.items) |cmd| alloc.free(cmd);
        result.deinit();
    }

    try testing.expectEqualStrings(result.items[0], "docker build -t myapp .");
    try testing.expectEqualStrings(result.items[1], "docker run -d -p 3000:3000 myapp");
}

test "BuiltinWorkflows npmPublish" {
    const alloc = testing.allocator;

    const wf = try workflow.BuiltinWorkflows.npmPublish(alloc);
    defer {
        wf.deinit(alloc);
        alloc.destroy(wf);
    };

    try testing.expectEqualStrings(wf.id, "builtin-npm-publish");
    try testing.expectEqualStrings(wf.name, "NPM Test & Publish");
    try testing.expect(wf.commands.items.len == 3);
    try testing.expect(wf.parameters.items.len == 1);

    const values = std.StringHashMap([]const u8).init(alloc);
    try values.put("version_type", "minor");

    const result = try wf.render(alloc, values);
    defer {
        for (result.items) |cmd| alloc.free(cmd);
        result.deinit();
    }

    try testing.expectEqualStrings(result.items[0], "npm test");
    try testing.expectEqualStrings(result.items[1], "npm version minor");
    try testing.expectEqualStrings(result.items[2], "npm publish");
}
