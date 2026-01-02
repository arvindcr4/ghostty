// src/apprt_test.zig
const std = @import("std");
const testing = std.testing;
const apprt = @import("apprt.zig");
const action = @import("apprt/action.zig");
const browser = @import("apprt/browser.zig");
const embedded = @import("apprt/embedded.zig");
const gtk = @import("apprt/gtk.zig");
const ipc = @import("apprt/ipc.zig");
const none = @import("apprt/none.zig");
const runtime = @import("apprt/runtime.zig");
const structs = @import("apprt/structs.zig");
const surface = @import("apprt/surface.zig");

test "apprt initialization" {
    const allocator = testing.allocator;
    var rt = try apprt.init(allocator);
    defer rt.deinit();
    
    try testing.expect(rt.state == .initialized);
    try testing.expect(rt.allocator == allocator);
}

test "apprt shutdown sequence" {
    const allocator = testing.allocator;
    var rt = try apprt.init(allocator);
    
    try rt.start();
    try testing.expect(rt.state == .running);
    
    try rt.shutdown();
    try testing.expect(rt.state == .shutdown);
}

// src/apprt/action_test.zig
const std = @import("std");
const testing = std.testing;
const action = @import("apprt/action.zig");

test "action creation and validation" {
    const test_action = action.Action{
        .type = .quit,
        .data = .{ .quit = {} },
    };
    
    try testing.expect(test_action.type == .quit);
    try testing.expect(test_action.isValid());
}

test "action dispatching" {
    var dispatcher = try action.Dispatcher.init(testing.allocator);
    defer dispatcher.deinit();
    
    var action_called = false;
    try dispatcher.register(.quit, struct {
        fn handler(act: action.Action) !void {
            _ = act;
            action_called = true;
        }
    }.handler);
    
    const test_action = action.Action{ .type = .quit, .data = .{ .quit = {} } };
    try dispatcher.dispatch(test_action);
    try testing.expect(action_called);
}

test "action queue processing" {
    var queue = try action.Queue.init(testing.allocator);
    defer queue.deinit();
    
    const test_action = action.Action{ .type = .quit, .data = .{ .quit = {} } };
    try queue.push(test_action);
    
    const popped = try queue.pop();
    try testing.expect(popped.?.type == .quit);
}

// src/apprt/browser_test.zig
const std = @import("std");
const testing = std.testing;
const browser = @import("apprt/browser.zig");

test "browser integration initialization" {
    var browser_rt = try browser.Runtime.init(testing.allocator);
    defer browser_rt.deinit();
    
    try testing.expect(browser_rt.isReady());
}

test "browser message handling" {
    var browser_rt = try browser.Runtime.init(testing.allocator);
    defer browser_rt.deinit();
    
    const test_message = browser.Message{
        .type = .navigate,
        .url = "https://example.com",
    };
    
    try browser_rt.handleMessage(test_message);
    try testing.expect(browser_rt.lastMessage().type == .navigate);
}

test "browser JavaScript execution" {
    var browser_rt = try browser.Runtime.init(testing.allocator);
    defer browser_rt.deinit();
    
    const script = "console.log('test')";
    const result = try browser_rt.executeScript(script);
    try testing.expect(result.success);
}

// src/apprt/embedded_test.zig
const std = @import("std");
const testing = std.testing;
const embedded = @import("apprt/embedded.zig");

test "embedded runtime creation" {
    var emb_rt = try embedded.Runtime.init(testing.allocator);
    defer emb_rt.deinit();
    
    try testing.expect(emb_rt.state == .initialized);
}

test "embedded resource loading" {
    var emb_rt = try embedded.Runtime.init(testing.allocator);
    defer emb_rt.deinit();
    
    const resource = try emb_rt.loadResource("test.html");
    defer testing.allocator.free(resource);
    try testing.expect(resource.len > 0);
}

test "embedded event loop" {
    var emb_rt = try embedded.Runtime.init(testing.allocator);
    defer emb_rt.deinit();
    
    var counter: u32 = 0;
    try emb_rt.onTick(struct {
        fn tick() void {
            counter += 1;
        }
    }.tick);
    
    try emb_rt.runTicks(5);
    try testing.expect(counter == 5);
}

// src/apprt/gtk_test.zig
const std = @import("std");
const testing = std.testing;
const gtk = @import("apprt/gtk.zig");

test "GTK runtime initialization" {
    var gtk_rt = try gtk.Runtime.init(testing.allocator);
    defer gtk_rt.deinit();
    
    try testing.expect(gtk_rt.isInitialized());
}

test "GTK widget creation" {
    var gtk_rt = try gtk.Runtime.init(testing.allocator);
    defer gtk_rt.deinit();
    
    const widget = try gtk_rt.createWidget(.window);
    try testing.expect(widget.type == .window);
}

test "GTK event handling" {
    var gtk_rt = try gtk.Runtime.init(testing.allocator);
    defer gtk_rt.deinit();
    
    var event_received = false;
    try gtk_rt.connect(.button_press, struct {
        fn handler(event: gtk.Event) void {
            _ = event;
            event_received = true;
        }
    }.handler);
    
    const test_event = gtk.Event{ .type = .button_press };
    gtk_rt.processEvent(test_event);
    try testing.expect(event_received);
}

test "GTK main loop integration" {
    var gtk_rt = try gtk.Runtime.init(testing.allocator);
    defer gtk_rt.deinit();
    
    try gtk_rt.startMainLoop();
    try testing.expect(gtk_rt.isMainLoopRunning());
    
    gtk_rt.stopMainLoop();
    try testing.expect(!gtk_rt.isMainLoopRunning());
}

// src/apprt/ipc_test.zig
const std = @import("std");
const testing = std.testing;
const ipc = @import("apprt/ipc.zig");

test "IPC channel creation" {
    var channel = try ipc.Channel.init(testing.allocator, "test_channel");
    defer channel.deinit();
    
    try testing.expect(channel.isConnected());
}

test "IPC message serialization" {
    const message = ipc.Message{
        .id = 123,
        .type = .command,
        .payload = "test payload",
    };
    
    const serialized = try message.serialize(testing.allocator);
    defer testing.allocator.free(serialized);
    
    const deserialized = try ipc.Message.deserialize(serialized);
    try testing.expect(deserialized.id == message.id);
    try testing.expect(deserialized.type == message.type);
    try testing.expect(std.mem.eql(u8, deserialized.payload, message.payload));
}

test "IPC message sending" {
    var channel = try ipc.Channel.init(testing.allocator, "test_channel");
    defer channel.deinit();
    
    const message = ipc.Message{
        .id = 456,
        .type = .data,
        .payload = "test data",
    };
    
    try channel.send(message);
    
    const received = try channel.receive();
    try testing.expect(received.id == message.id);
}

test "IPC broadcast" {
    var server = try ipc.Server.init(testing.allocator);
    defer server.deinit();
    
    var client1 = try server.connectClient();
    defer client1.deinit();
    var client2 = try server.connectClient();
    defer client2.deinit();
    
    const broadcast_msg = ipc.Message{
        .id = 789,
        .type = .notification,
        .payload = "broadcast",
    };
    
    try server.broadcast(broadcast_msg);
    
    const msg1 = try client1.receive();
    const msg2 = try client2.receive();
    try testing.expect(msg1.id == broadcast_msg.id);
    try testing.expect(msg2.id == broadcast_msg.id);
}

// src/apprt/none_test.zig
const std = @import("std");
const testing = std.testing;
const none = @import("apprt/none.zig");

test "none runtime initialization" {
    var none_rt = try none.Runtime.init(testing.allocator);
    defer none_rt.deinit();
    
    try testing.expect(none_rt.state == .initialized);
}

test "none runtime no-op operations" {
    var none_rt = try none.Runtime.init(testing.allocator);
    defer none_rt.deinit();
    
    try none_rt.start();
    try testing.expect(none_rt.state == .running);
    
    try none_rt.processEvent(.{ .type = .none });
    try none_rt.shutdown();
    try testing.expect(none_rt.state == .shutdown);
}

test "none runtime surface handling" {
    var none_rt = try none.Runtime.init(testing.allocator);
    defer none_rt.deinit();
    
    const surface = try none_rt.createSurface(.{ .width = 800, .height = 600 });
    defer none_rt.destroySurface(surface);
    
    try testing.expect(surface.isValid());
}

// src/apprt/runtime_test.zig
const std = @import("std");
const testing = std.testing;
const runtime = @import("apprt/runtime.zig");

test "runtime abstraction interface" {
    const TestRuntime = struct {
        const Self = @This();
        
        state: enum { initialized, running, shutdown } = .initialized,
        
        fn init(allocator: std.mem.Allocator) !Self {
            _ = allocator;
            return Self{};
        }
        
        fn deinit(self: *Self) void {
            self.state = .shutdown;
        }
        
        fn start(self: *Self) !void {
            self.state = .running;
        }
        
        fn shutdown(self: *Self) !void {
            self.state = .shutdown;
        }
    };
    
    var test_rt = try TestRuntime.init(testing.allocator);
    defer test_rt.deinit();
    
    try test_rt.start();
    try testing.expect(test_rt.state == .running);
    
    try test_rt.shutdown();
    try testing.expect(test_rt.state == .shutdown);
}

test "runtime factory selection" {
    const factory = runtime.Factory{};
    
    const gtk_rt = try factory.createRuntime(.gtk, testing.allocator);
    defer gtk_rt.deinit();
    try testing.expect(gtk_rt.type() == .gtk);
    
    const none_rt = try factory.createRuntime(.none, testing.allocator);
    defer none_rt.deinit();
    try testing.expect(none_rt.type() == .none);
}

test "runtime capabilities" {
    const factory = runtime.Factory{};
    
    const gtk_rt = try factory.createRuntime(.gtk, testing.allocator);
    defer gtk_rt.deinit();
    try testing.expect(gtk_rt.hasCapability(.gui));
    try testing.expect(gtk_rt.hasCapability(.events));
    
    const none_rt = try factory.createRuntime(.none, testing.allocator);
    defer none_rt.deinit();
    try testing.expect(!none_rt.hasCapability(.gui));
}

// src/apprt/structs_test.zig
const std = @import("std");
const testing = std.testing;
const structs = @import("apprt/structs.zig");

test "runtime configuration struct" {
    var config = structs.RuntimeConfig.initDefault();
    config.width = 1024;
    config.height = 768;
    config.title = "Test App";
    
    try testing.expect(config.width == 1024);
    try testing.expect(config.height == 768);
    try testing.expect(std.mem.eql(u8, config.title, "Test App"));
}

test "event struct creation and cloning" {
    const original = structs.Event{
        .type = .key_press,
        .timestamp = 123456,
        .data = .{ .key = .{ .code = 65, .state = .pressed } },
    };
    
    const cloned = try original.clone(testing.allocator);
    defer cloned.deinit(testing.allocator);
    
    try testing.expect(cloned.type == original.type);
    try testing.expect(cloned.timestamp == original.timestamp);
}

test "surface properties validation" {
    var props = structs.SurfaceProperties{
        .width = 800,
        .height = 600,
        .format = .rgba8888,
    };
    
    try testing.expect(props.isValid());
    
    props.width = 0;
    try testing.expect(!props.isValid());
}

test "message queue operations" {
    var queue = structs.MessageQueue.init(testing.allocator);
    defer queue.deinit();
    
    const msg1 = structs.Message{ .id = 1, .type = .info, .data = "test1" };
    const msg2 = structs.Message{ .id = 2, .type = .info, .data = "test2" };
    
    try queue.push(msg1);
    try queue.push(msg2);
    
    const popped1 = try queue.pop();
    const popped2 = try queue.pop();
    
    try testing.expect(popped1.?.id == 1);
    try testing.expect(popped2.?.id == 2);
    try testing.expect(queue.pop() == null);
}

// src/apprt/surface_test.zig
const std = @import("std");
const testing = std.testing;
const surface = @import("apprt/surface.zig");

test "surface creation and destruction" {
    var sf = try surface.Surface.init(testing.allocator, .{ .width = 640, .height = 480 });
    defer sf.deinit();
    
    try testing.expect(sf.width() == 640);
    try testing.expect(sf.height() == 480);
    try testing.expect(sf.isValid());
}

test "surface rendering operations" {
    var sf = try surface.Surface.init(testing.allocator, .{ .width = 100, .height = 100 });
    defer sf.deinit();
    
    try sf.clear(.{ .r = 255, .g = 255, .b = 255, .a = 255 });
    
    const pixel = try sf.getPixel(50, 50);
    try testing.expect(pixel.r == 255);
    try testing.expect(pixel.g == 255);
    try testing.expect(pixel.b == 255);
    try testing.expect(pixel.a == 255);
}

test "surface buffer management" {
    var sf = try surface.Surface.init(testing.allocator, .{ .width = 10, .height = 10 });
    defer sf.deinit();
    
    const buffer = try sf.getBuffer();
    try testing.expect(buffer.len == 10 * 10 * 4); // RGBA
    
    try sf.present();
    try testing.expect(sf.isDirty() == false);
}

test "surface event handling" {
    var sf = try surface.Surface.init(testing.allocator, .{ .width = 100, .height = 100 });
    defer sf.deinit();
    
    var resize_called = false;
    try sf.onResize(struct {
        fn handler(width: u32, height: u32) void {
            _ = width;
            _ = height;
            resize_called = true;
        }
    }.handler);
    
    try sf.resize(200, 200);
    try testing.expect(resize_called);
    try testing.expect(sf.width() == 200);
    try testing.expect(sf.height() == 200);
}

test "surface composition" {
    var sf1 = try surface.Surface.init(testing.allocator, .{ .width = 50, .height = 50 });
    defer sf1.deinit();
    var sf2 = try surface.Surface.init(testing.allocator, .{ .width = 50, .height = 50 });
    defer sf2.deinit();
    
    try sf1.clear(.{ .r = 255, .g = 0, .b = 0, .a = 255 });
    try sf2.clear(.{ .r = 0, .g = 255, .b = 0, .a = 255 });
    
    try sf1.blit(sf2, .{ .x = 25, .y = 25 });
    
    const pixel = try sf1.getPixel(30, 30);
    try testing.expect(pixel.g == 255);
}