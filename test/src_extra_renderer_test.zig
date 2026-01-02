// src/extra/bash_test.zig
const std = @import("std");
const testing = std.testing;
const bash = @import("bash.zig");

test "bash integration script generation" {
    const allocator = testing.allocator;
    const script = try bash.generateIntegrationScript(allocator);
    defer allocator.free(script);
    
    try testing.expect(script.len > 0);
    try testing.expect(std.mem.indexOf(u8, script, "ghostty") != null);
    try testing.expect(std.mem.indexOf(u8, script, "PROMPT_COMMAND") != null);
}

test "bash escape sequence handling" {
    const test_input = "test\\nvalue\\$HOME";
    const expected = "test\nvalue$HOME";
    const result = try bash.escapeSequences(testing.allocator, test_input);
    defer testing.allocator.free(result);
    
    try testing.expectEqualStrings(expected, result);
}

test "bash prompt integration" {
    const prompt = try bash.generatePromptIntegration(testing.allocator);
    defer testing.allocator.free(prompt);
    
    try testing.expect(prompt.len > 0);
    try testing.expect(std.mem.indexOf(u8, prompt, "__ghostty_precmd") != null);
}

test "bash environment setup" {
    const env = try bash.setupEnvironment(testing.allocator);
    defer testing.allocator.free(env);
    
    try testing.expect(env.len > 0);
    try testing.expect(std.mem.indexOf(u8, env, "export") != null);
}

// src/extra/fish_test.zig
const std = @import("std");
const testing = std.testing;
const fish = @import("fish.zig");

test "fish integration script generation" {
    const allocator = testing.allocator;
    const script = try fish.generateIntegrationScript(allocator);
    defer allocator.free(script);
    
    try testing.expect(script.len > 0);
    try testing.expect(std.mem.indexOf(u8, script, "ghostty") != null);
    try testing.expect(std.mem.indexOf(u8, script, "function") != null);
}

test "fish prompt function generation" {
    const prompt_func = try fish.generatePromptFunction(testing.allocator);
    defer testing.allocator.free(prompt_func);
    
    try testing.expect(prompt_func.len > 0);
    try testing.expect(std.mem.indexOf(u8, prompt_func, "fish_prompt") != null);
}

test "fish event handling" {
    const events = try fish.generateEventHandlers(testing.allocator);
    defer testing.allocator.free(events);
    
    try testing.expect(events.len > 0);
    try testing.expect(std.mem.indexOf(u8, events, "fish_prompt") != null);
}

test "fish universal variables" {
    const vars = try fish.setupUniversalVariables(testing.allocator);
    defer testing.allocator.free(vars);
    
    try testing.expect(vars.len > 0);
    try testing.expect(std.mem.indexOf(u8, vars, "set -U") != null);
}

// src/extra/sublime_test.zig
const std = @import("std");
const testing = std.testing;
const sublime = @import("sublime.zig");

test "sublime build system generation" {
    const allocator = testing.allocator;
    const build = try sublime.generateBuildSystem(allocator);
    defer allocator.free(build);
    
    try testing.expect(build.len > 0);
    try testing.expect(std.mem.indexOf(u8, build, "\"cmd\"") != null);
    try testing.expect(std.mem.indexOf(u8, build, "\"selector\"") != null);
}

test "sublime syntax highlighting" {
    const syntax = try sublime.generateSyntaxFile(testing.allocator);
    defer testing.allocator.free(syntax);
    
    try testing.expect(syntax.len > 0);
    try testing.expect(std.mem.indexOf(u8, syntax, "contexts") != null);
}

test "sublime key bindings" {
    const bindings = try sublime.generateKeyBindings(testing.allocator);
    defer testing.allocator.free(bindings);
    
    try testing.expect(bindings.len > 0);
    try testing.expect(std.mem.indexOf(u8, bindings, "\"keys\"") != null);
}

test "sublime project settings" {
    const settings = try sublime.generateProjectSettings(testing.allocator);
    defer testing.allocator.free(settings);
    
    try testing.expect(settings.len > 0);
    try testing.expect(std.mem.indexOf(u8, settings, "\"settings\"") != null);
}

// src/extra/vim_test.zig
const std = @import("std");
const testing = std.testing;
const vim = @import("vim.zig");

test "vim plugin configuration" {
    const allocator = testing.allocator;
    const config = try vim.generatePluginConfig(allocator);
    defer allocator.free(config);
    
    try testing.expect(config.len > 0);
    try testing.expect(std.mem.indexOf(u8, config, "function") != null);
}

test "vim autocmd generation" {
    const autocmd = try vim.generateAutocmd(testing.allocator);
    defer testing.allocator.free(autocmd);
    
    try testing.expect(autocmd.len > 0);
    try testing.expect(std.mem.indexOf(u8, autocmd, "autocmd") != null);
}

test "vim key mappings" {
    const mappings = try vim.generateKeyMappings(testing.allocator);
    defer testing.allocator.free(mappings);
    
    try testing.expect(mappings.len > 0);
    try testing.expect(std.mem.indexOf(u8, mappings, "nnoremap") != null);
}

test "vim statusline integration" {
    const statusline = try vim.generateStatusline(testing.allocator);
    defer testing.allocator.free(statusline);
    
    try testing.expect(statusline.len > 0);
    try testing.expect(std.mem.indexOf(u8, statusline, "statusline") != null);
}

// src/extra/zsh_test.zig
const std = @import("std");
const testing = std.testing;
const zsh = @import("zsh.zig");

test "zsh integration script generation" {
    const allocator = testing.allocator;
    const script = try zsh.generateIntegrationScript(allocator);
    defer allocator.free(script);
    
    try testing.expect(script.len > 0);
    try testing.expect(std.mem.indexOf(u8, script, "ghostty") != null);
    try testing.expect(std.mem.indexOf(u8, script, "precmd") != null);
}

test "zsh prompt generation" {
    const prompt = try zsh.generatePrompt(testing.allocator);
    defer testing.allocator.free(prompt);
    
    try testing.expect(prompt.len > 0);
    try testing.expect(std.mem.indexOf(u8, prompt, "PROMPT") != null);
}

test "zsh widget creation" {
    const widget = try zsh.createWidget(testing.allocator);
    defer testing.allocator.free(widget);
    
    try testing.expect(widget.len > 0);
    try testing.expect(std.mem.indexOf(u8, widget, "zle") != null);
}

test "zsh completion setup" {
    const completion = try zsh.setupCompletion(testing.allocator);
    defer testing.allocator.free(completion);
    
    try testing.expect(completion.len > 0);
    try testing.expect(std.mem.indexOf(u8, completion, "compdef") != null);
}

// src/renderer/main_test.zig
const std = @import("std");
const testing = std.testing;
const main = @import("main.zig");
const backend = @import("backend.zig");
const Options = @import("Options.zig");
const State = @import("State.zig");

test "renderer initialization" {
    const allocator = testing.allocator;
    var options = Options.initDefault();
    var state = try State.init(allocator, 80, 24);
    defer state.deinit();
    
    const renderer = try main.Renderer.init(allocator, &options, &state);
    defer renderer.deinit();
    
    try testing.expect(renderer.state != null);
    try testing.expect(renderer.options != null);
}

test "renderer backend selection" {
    const allocator = testing.allocator;
    var options = Options.initDefault();
    options.backend = .OpenGL;
    
    var state = try State.init(allocator, 80, 24);
    defer state.deinit();
    
    const renderer = try main.Renderer.init(allocator, &options, &state);
    defer renderer.deinit();
    
    try testing.expect(renderer.backend_type == .OpenGL);
}

test "renderer frame rendering" {
    const allocator = testing.allocator;
    var options = Options.initDefault();
    var state = try State.init(allocator, 80, 24);
    defer state.deinit();
    
    var renderer = try main.Renderer.init(allocator, &options, &state);
    defer renderer.deinit();
    
    try renderer.beginFrame();
    try renderer.endFrame();
    try testing.expect(true);
}

test "renderer resize handling" {
    const allocator = testing.allocator;
    var options = Options.initDefault();
    var state = try State.init(allocator, 80, 24);
    defer state.deinit();
    
    var renderer = try main.Renderer.init(allocator, &options, &state);
    defer renderer.deinit();
    
    try renderer.resize(100, 30);
    try testing.expect(renderer.state.width == 100);
    try testing.expect(renderer.state.height == 30);
}

// src/renderer/backend_test.zig
const std = @import("std");
const testing = std.testing;
const backend = @import("backend.zig");

test "backend creation" {
    const allocator = testing.allocator;
    const test_backend = try backend.createTestBackend(allocator);
    defer test_backend.destroy();
    
    try testing.expect(test_backend != null);
}

test "backend capabilities" {
    const allocator = testing.allocator;
    const test_backend = try backend.createTestBackend(allocator);
    defer test_backend.destroy();
    
    const caps = test_backend.getCapabilities();
    try testing.expect(caps.supports_shaders);
    try testing.expect(caps.max_texture_size > 0);
}

test "backend resource management" {
    const allocator = testing.allocator;
    var test_backend = try backend.createTestBackend(allocator);
    defer test_backend.destroy();
    
    const texture = try test_backend.createTexture(256, 256);
    defer test_backend.destroyTexture(texture);
    
    try testing.expect(texture != 0);
}

test "backend shader compilation" {
    const allocator = testing.allocator;
    var test_backend = try backend.createTestBackend(allocator);
    defer test_backend.destroy();
    
    const vertex_shader = "void main() { gl_Position = vec4(0.0); }";
    const fragment_shader = "void main() { gl_FragColor = vec4(1.0); }";
    
    const program = try test_backend.createShaderProgram(vertex_shader, fragment_shader);
    defer test_backend.destroyShaderProgram(program);
    
    try testing.expect(program != 0);
}

// src/renderer/cell_test.zig
const std = @import("std");
const testing = std.testing;
const cell = @import("cell.zig");

test "cell creation and initialization" {
    var test_cell = cell.Cell.init();
    
    try testing.expect(test_cell.ch == 0);
    try testing.expect(test_cell.fg == cell.Color.default);
    try testing.expect(test_cell.bg == cell.Color.default);
}

test "cell content setting" {
    var test_cell = cell.Cell.init();
    test_cell.setChar('A');
    
    try testing.expect(test_cell.ch == 'A');
}

test "cell color manipulation" {
    var test_cell = cell.Cell.init();
    test_cell.setForeground(0xFF0000);
    test_cell.setBackground(0x00FF00);
    
    try testing.expect(test_cell.fg == 0xFF0000);
    try testing.expect(test_cell.bg == 0x00FF00);
}

test "cell attributes" {
    var test_cell = cell.Cell.init();
    test_cell.setBold(true);
    test_cell.setUnderline(true);
    
    try testing.expect(test_cell.bold);
    try testing.expect(test_cell.underline);
}

test "cell comparison" {
    var cell1 = cell.Cell.init();
    var cell2 = cell.Cell.init();
    
    cell1.setChar('X');
    cell2.setChar('X');
    
    try testing.expect(cell1.equals(cell2));
}

// src/renderer/cursor_test.zig
const std = @import("std");
const testing = std.testing;
const cursor = @import("cursor.zig");

test "cursor initialization" {
    var test_cursor = cursor.Cursor.init();
    
    try testing.expect(test_cursor.x == 0);
    try testing.expect(test_cursor.y == 0);
    try testing.expect(test_cursor.visible == true);
}

test "cursor movement" {
    var test_cursor = cursor.Cursor.init();
    
    test_cursor.moveTo(10, 5);
    try testing.expect(test_cursor.x == 10);
    try testing.expect(test_cursor.y == 5);
    
    test_cursor.moveRelative(2, -1);
    try testing.expect(test_cursor.x == 12);
    try testing.expect(test_cursor.y == 4);
}

test "cursor visibility" {
    var test_cursor = cursor.Cursor.init();
    
    test_cursor.hide();
    try testing.expect(!test_cursor.visible);
    
    test_cursor.show();
    try testing.expect(test_cursor.visible);
}

test "cursor shape" {
    var test_cursor = cursor.Cursor.init();
    
    test_cursor.setShape(.Block);
    try testing.expect(test_cursor.shape == .Block);
    
    test_cursor.setShape(.Underline);
    try testing.expect(test_cursor.shape == .Underline);
}

test "cursor blinking" {
    var test_cursor = cursor.Cursor.init();
    
    test_cursor.setBlinking(true);
    try testing.expect(test_cursor.blinking);
    
    test_cursor.setBlinking(false);
    try testing.expect(!test_cursor.blinking);
}

// src/renderer/generic_test.zig
const std = @import("std");
const testing = std.testing;
const generic = @import("generic.zig");
const cell = @import("cell.zig");
const cursor = @import("cursor.zig");

test "generic renderer initialization" {
    const allocator = testing.allocator;
    var renderer = try generic.GenericRenderer.init(allocator, 80, 24);
    defer renderer.deinit();
    
    try testing.expect(renderer.width == 80);
    try testing.expect(renderer.height == 24);
}

test "generic cell rendering" {
    const allocator = testing.allocator;
    var renderer = try generic.GenericRenderer.init(allocator, 80, 24);
    defer renderer.deinit();
    
    var test_cell = cell.Cell.init();
    test_cell.setChar('T');
    
    try renderer.renderCell(0, 0, &test_cell);
    const rendered = renderer.getCell(0, 0);
    
    try testing.expect(rendered.ch == 'T');
}

test "generic cursor rendering" {
    const allocator = testing.allocator;
    var renderer = try generic.GenericRenderer.init(allocator, 80, 24);
    defer renderer.deinit();
    
    var test_cursor = cursor.Cursor.init();
    test_cursor.moveTo(5, 3);
    
    try renderer.renderCursor(&test_cursor);
    const cursor_pos = renderer.getCursorPosition();
    
    try testing.expect(cursor_pos.x == 5);
    try testing.expect(cursor_pos.y == 3);
}

test "generic screen clearing" {
    const allocator = testing.allocator;
    var renderer = try generic.GenericRenderer.init(allocator, 80, 24);
    defer renderer.deinit();
    
    var test_cell = cell.Cell.init();
    test_cell.setChar('X');
    try renderer.renderCell(0, 0, &test_cell);
    
    try renderer.clear();
    const cleared = renderer.getCell(0, 0);
    
    try testing.expect(cleared.ch == 0);
}

test "generic scroll region" {
    const allocator = testing.allocator;
    var renderer = try generic.GenericRenderer.init(allocator, 80, 24);
    defer renderer.deinit();
    
    try renderer.setScrollRegion(5, 20);
    const region = renderer.getScrollRegion();
    
    try testing.expect(region.top == 5);
    try testing.expect(region.bottom == 20);
}

// src/renderer/Options_test.zig
const std = @import("std");
const testing = std.testing;
const Options = @import("Options.zig");

test "options default initialization" {
    var options = Options.initDefault();
    
    try testing.expect(options.backend == .Auto);
    try testing.expect(options.font_size == 12);
    try testing.expect(options.width == 80);
    try testing.expect(options.height == 24);
}

test "options validation" {
    var options = Options.initDefault();
    options.font_size = -1;
    
    try testing.expectError(error.InvalidFontSize, options.validate());
}

test "options font configuration" {
    var options = Options.initDefault();
    options.font_family = "Monospace";
    options.font_size = 14;
    
    try testing.expectEqualStrings("Monospace", options.font_family);
    try testing.expect(options.font_size == 14);
}

test "options color scheme" {
    var options = Options.initDefault();
    options.color_scheme = "dark";
    
    try testing.expectEqualStrings("dark", options.color_scheme);
}

test "options performance settings" {
    var options = Options.initDefault();
    options.vsync = true;
    options.max_fps = 60;
    
    try testing.expect(options.vsync);
    try testing.expect(options.max_fps == 60);
}

// src/renderer/State_test.zig
const std = @import("std");
const testing = std.testing;
const State = @import("State.zig");
const cell = @import("cell.zig");

test "state initialization" {
    const allocator = testing.allocator;
    var state = try State.init(allocator, 80, 24);
    defer state.deinit();
    
    try testing.expect(state.width == 80);
    try testing.expect(state.height == 24);
    try testing.expect(state.grid != null);
}

test "state cell access" {
    const allocator = testing.allocator;
    var state = try State.init(allocator, 80, 24);
    defer state.deinit();
    
    var test_cell = cell.Cell.init();
    test_cell.setChar('H');
    
    try state.setCell(10, 5, test_cell);
    const retrieved = state.getCell(10, 5);
    
    try testing.expect(retrieved.ch == 'H');
}

test "state bounds checking" {
    const allocator = testing.allocator;
    var state = try State.init(allocator, 80, 24);
    defer state.deinit();
    
    try testing.expectError(error.OutOfBounds, state.getCell(100, 100));
    try testing.expectError(error.OutOfBounds, state.setCell(100, 100, undefined));
}

test "state resize" {
    const allocator = testing.allocator;
    var state = try State.init(allocator, 80, 24);
    defer state.deinit();
    
    try state.resize(100, 30);
    try testing.expect(state.width == 100);
    try testing.expect(state.height == 30);
}

test "state dirty tracking" {
    const allocator = testing.allocator;
    var state = try State.init(allocator, 80, 24);
    defer state.deinit();
    
    try testing.expect(!state.isDirty());
    
    var test_cell = cell.Cell.init();
    test_cell.setChar('X');
    try state.setCell(0, 0, test_cell);
    
    try testing.expect(state.isDirty());
    state.clearDirty();
    try testing.expect(!state.isDirty());
}

test "state scroll operation" {
    const allocator = testing.allocator;
    var state = try State.init(allocator, 80, 24);
    defer state.deinit();
    
    try state.scroll(1);
    try testing.expect(state.scroll_offset == 1);
    
    try state.scroll(-1);
    try testing.expect(state.scroll_offset == 0);
}