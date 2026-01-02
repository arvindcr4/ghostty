// src/datastruct/array_list_collection_test.zig
const std = @import("std");
const testing = std.testing;
const ArrayListCollection = @import("array_list_collection.zig").ArrayListCollection;

test "ArrayListCollection - basic operations" {
    const allocator = testing.allocator;
    var collection = try ArrayListCollection(u32).init(allocator);
    defer collection.deinit();

    // Test empty collection
    try testing.expect(collection.len() == 0);
    try testing.expect(collection.isEmpty());

    // Test add
    try collection.append(1);
    try collection.append(2);
    try collection.append(3);
    try testing.expect(collection.len() == 3);
    try testing.expect(!collection.isEmpty());

    // Test get
    try testing.expect(collection.get(0) == 1);
    try testing.expect(collection.get(1) == 2);
    try testing.expect(collection.get(2) == 3);

    // Test set
    try collection.set(1, 99);
    try testing.expect(collection.get(1) == 99);

    // Test remove
    const removed = try collection.removeAt(1);
    try testing.expect(removed == 99);
    try testing.expect(collection.len() == 2);
    try testing.expect(collection.get(0) == 1);
    try testing.expect(collection.get(1) == 3);
}

test "ArrayListCollection - capacity management" {
    const allocator = testing.allocator;
    var collection = try ArrayListCollection(u32).initWithCapacity(allocator, 2);
    defer collection.deinit();

    try testing.expect(collection.capacity() >= 2);

    // Fill beyond initial capacity
    for (0..10) |i| {
        try collection.append(@intCast(i));
    }

    try testing.expect(collection.len() == 10);
    try testing.expect(collection.capacity() >= 10);

    // Test shrink
    try collection.shrinkToFit();
    try testing.expect(collection.capacity() == collection.len());
}

test "ArrayListCollection - iteration" {
    const allocator = testing.allocator;
    var collection = try ArrayListCollection(u32).init(allocator);
    defer collection.deinit();

    for (0..5) |i| {
        try collection.append(@intCast(i));
    }

    var sum: u32 = 0;
    var iter = collection.iterator();
    while (iter.next()) |value| {
        sum += value.*;
    }
    try testing.expect(sum == 10); // 0+1+2+3+4

    // Test reverse iteration
    sum = 0;
    var rev_iter = collection.reverseIterator();
    while (rev_iter.next()) |value| {
        sum += value.*;
    }
    try testing.expect(sum == 10);
}

test "ArrayListCollection - edge cases" {
    const allocator = testing.allocator;
    var collection = try ArrayListCollection(u32).init(allocator);
    defer collection.deinit();

    // Test pop on empty
    try testing.expectError(error.OutOfMemory, collection.pop());

    // Test clear
    try collection.append(1);
    try collection.append(2);
    collection.clear();
    try testing.expect(collection.len() == 0);
    try testing.expect(collection.isEmpty());

    // Test insert at position
    try collection.append(1);
    try collection.append(3);
    try collection.insert(1, 2);
    try testing.expect(collection.get(0) == 1);
    try testing.expect(collection.get(1) == 2);
    try testing.expect(collection.get(2) == 3);

    // Test out of bounds
    try testing.expectError(error.OutOfBounds, collection.get(10));
    try testing.expectError(error.OutOfBounds, collection.removeAt(10));
}

test "ArrayListCollection - performance" {
    const allocator = testing.allocator;
    var collection = try ArrayListCollection(u32).init(allocator);
    defer collection.deinit();

    const start_time = std.time.nanoTimestamp();

    // Add many elements
    for (0..10000) |i| {
        try collection.append(@intCast(i));
    }

    const add_time = std.time.nanoTimestamp();

    // Access all elements
    var sum: u64 = 0;
    for (0..collection.len()) |i| {
        sum += collection.get(i);
    }

    const access_time = std.time.nanoTimestamp();

    // Remove all elements
    while (collection.len() > 0) {
        _ = collection.pop();
    }

    const end_time = std.time.nanoTimestamp();

    std.debug.print("Add time: {}ns\n", .{add_time - start_time});
    std.debug.print("Access time: {}ns\n", .{access_time - add_time});
    std.debug.print("Remove time: {}ns\n", .{end_time - access_time});

    try testing.expect(sum == 49995000); // Sum of 0..9999
}

// src/datastruct/blocking_queue_test.zig
const std = @import("std");
const testing = std.testing;
const BlockingQueue = @import("blocking_queue.zig").BlockingQueue;

test "BlockingQueue - basic operations" {
    const allocator = testing.allocator;
    var queue = try BlockingQueue(u32).init(allocator, 5);
    defer queue.deinit();

    // Test empty queue
    try testing.expect(queue.isEmpty());
    try testing.expect(queue.len() == 0);

    // Test enqueue
    try queue.enqueue(1);
    try queue.enqueue(2);
    try queue.enqueue(3);
    try testing.expect(queue.len() == 3);
    try testing.expect(!queue.isEmpty());

    // Test dequeue
    const item1 = try queue.dequeue();
    try testing.expect(item1 == 1);
    const item2 = try queue.dequeue();
    try testing.expect(item2 == 2);
    try testing.expect(queue.len() == 1);
}

test "BlockingQueue - capacity limits" {
    const allocator = testing.allocator;
    var queue = try BlockingQueue(u32).init(allocator, 3);
    defer queue.deinit();

    // Fill to capacity
    try queue.enqueue(1);
    try queue.enqueue(2);
    try queue.enqueue(3);

    // Should be full
    try testing.expect(queue.isFull());

    // Try to enqueue when full (should block or error)
    // This test assumes blocking behavior with timeout
    const result = queue.enqueueTimeout(4, std.time.ns_per_ms * 10);
    try testing.expectError(error.Timeout, result);
}

test "BlockingQueue - timeout operations" {
    const allocator = testing.allocator;
    var queue = try BlockingQueue(u32).init(allocator, 5);
    defer queue.deinit();

    // Test dequeue timeout on empty queue
    const result = queue.dequeueTimeout(std.time.ns_per_ms * 10);
    try testing.expectError(error.Timeout, result);

    // Test enqueue timeout on full queue
    for (0..5) |i| {
        try queue.enqueue(@intCast(i));
    }
    const enqueue_result = queue.enqueueTimeout(99, std.time.ns_per_ms * 10);
    try testing.expectError(error.Timeout, enqueue_result);
}

test "BlockingQueue - thread safety single producer single consumer" {
    const allocator = testing.allocator;
    var queue = try BlockingQueue(u32).init(allocator, 100);
    defer queue.deinit();

    const num_items: u32 = 1000;
    var producer_done: bool = false;
    var consumer_sum: u32 = 0;

    const producer_thread = try std.Thread.spawn(.{}, struct {
        queue: *BlockingQueue(u32),
        num_items: u32,
        done: *bool,
        fn run(ctx: @This()) !void {
            for (0..ctx.num_items) |i| {
                try ctx.queue.enqueue(@intCast(i));
            }
            ctx.done.* = true;
        }
    }.run, .{ &queue, num_items, &producer_done });

    const consumer_thread = try std.Thread.spawn(.{}, struct {
        queue: *BlockingQueue(u32),
        num_items: u32,
        sum: *u32,
        done: *const bool,
        fn run(ctx: @This()) !void {
            var received: u32 = 0;
            while (received < ctx.num_items) {
                const item = try ctx.queue.dequeue();
                ctx.sum.* += item;
                received += 1;
            }
        }
    }.run, .{ &queue, num_items, &consumer_sum, &producer_done });

    producer_thread.join();
    consumer_thread.join();

    try testing.expect(consumer_sum == num_items * (num_items - 1) / 2);
}

test "BlockingQueue - multiple producers multiple consumers" {
    const allocator = testing.allocator;
    var queue = try BlockingQueue(u32).init(allocator, 1000);
    defer queue.deinit();

    const num_producers = 4;
    const num_consumers = 3;
    const items_per_producer = 250;
    const total_items = num_producers * items_per_producer;

    var producer_done: [num_producers]bool = std.mem.zeroes([num_producers]bool);
    var consumer_sums: [num_consumers]u32 = std.mem.zeroes([num_consumers]u32);

    var producer_threads: [num_producers]std.Thread = undefined;
    for (&producer_threads, 0..) |*thread, i| {
        thread.* = try std.Thread.spawn(.{}, struct {
            queue: *BlockingQueue(u32),
            items: u32,
            offset: u32,
            done: *bool,
            fn run(ctx: @This()) !void {
                for (0..ctx.items) |j| {
                    try ctx.queue.enqueue(ctx.offset + @as(u32, @intCast(j)));
                }
                ctx.done.* = true;
            }
        }.run, .{ &queue, items_per_producer, @as(u32, @intCast(i * items_per_producer)), &producer_done[i] });
    }

    var consumer_threads: [num_consumers]std.Thread = undefined;
    for (&consumer_threads, 0..) |*thread, i| {
        thread.* = try std.Thread.spawn(.{}, struct {
            queue: *BlockingQueue(u32),
            sum: *u32,
            done: *const [num_producers]bool,
            fn run(ctx: @This()) !void {
                while (!std.mem.eql(bool, ctx.done, &[_]bool{true} ** num_producers) or !ctx.queue.isEmpty()) {
                    const item = try ctx.queue.dequeue();
                    ctx.sum.* += item;
                }
            }
        }.run, .{ &queue, &consumer_sums[i], &producer_done });
    }

    for (producer_threads) |thread| thread.join();
    for (consumer_threads) |thread| thread.join();

    var total_sum: u32 = 0;
    for (consumer_sums) |sum| {
        total_sum += sum;
    }

    const expected_sum = total_items * (total_items - 1) / 2;
    try testing.expect(total_sum == expected_sum);
}

test "BlockingQueue - peek operations" {
    const allocator = testing.allocator;
    var queue = try BlockingQueue(u32).init(allocator, 5);
    defer queue.deinit();

    // Peek on empty queue
    try testing.expectError(error.Empty, queue.peek());

    try queue.enqueue(42);
    try queue.enqueue(99);

    // Peek should return first element without removing
    const peeked = try queue.peek();
    try testing.expect(peeked == 42);
    try testing.expect(queue.len() == 2);

    // Dequeue should still return 42
    const dequeued = try queue.dequeue();
    try testing.expect(dequeued == 42);
}

// src/datastruct/cache_table_test.zig
const std = @import("std");
const testing = std.testing;
const CacheTable = @import("cache_table.zig").CacheTable;

test "CacheTable - basic operations" {
    const allocator = testing.allocator;
    var cache = try CacheTable(u32, u32).init(allocator, 10);
    defer cache.deinit();

    // Test empty cache
    try testing.expect(cache.len() == 0);
    try testing.expect(cache.isEmpty());

    // Test put and get
    try cache.put(1, 100);
    try cache.put(2, 200);
    try testing.expect(cache.len() == 2);

    const value1 = try cache.get(1);
    try testing.expect(value1 == 100);
    const value2 = try cache.get(2);
    try testing.expect(value2 == 200);

    // Test contains
    try testing.expect(cache.contains(1));
    try testing.expect(cache.contains(2));
    try testing.expect(!cache.contains(3));
}

test "CacheTable - cache eviction" {
    const allocator = testing.allocator;
    var cache = try CacheTable(u32, u32).init(allocator, 3);
    defer cache.deinit();

    // Fill cache to capacity
    try cache.put(1, 100);
    try cache.put(2, 200);
    try cache.put(3, 300);
    try testing.expect(cache.len() == 3);

    // Add one more to trigger eviction
    try cache.put(4, 400);
    try testing.expect(cache.len() == 3);

    // Check that least recently used item was evicted
    try testing.expect(!cache.contains(1));
    try testing.expect(cache.contains(2));
    try testing.expect(cache.contains(3));
    try testing.expect(cache.contains(4));
}

test "CacheTable - LRU behavior" {
    const allocator = testing.allocator;
    var cache = try CacheTable(u32, u32).init(allocator, 3);
    defer cache.deinit();

    // Fill cache
    try cache.put(1, 100);
    try cache.put(2, 200);
    try cache.put(3, 300);

    // Access item 1 to make it recently used
    _ = try cache.get(1);

    // Add new item, should evict 2 (least recently used)
    try cache.put(4, 400);
    try testing.expect(!cache.contains(2));
    try testing.expect(cache.contains(1));
    try testing.expect(cache.contains(3));
    try testing.expect(cache.contains(4));
}

test "CacheTable - update existing key" {
    const allocator = testing.allocator;
    var cache = try CacheTable(u32, u32).init(allocator, 5);
    defer cache.deinit();

    try cache.put(1, 100);
    try testing.expect((try cache.get(1)) == 100);

    // Update existing key
    try cache.put(1, 999);
    try testing.expect((try cache.get(1)) == 999);
    try testing.expect(cache.len() == 1); // Should not increase size
}

test "CacheTable - remove operations" {
    const allocator = testing.allocator;
    var cache = try CacheTable(u32, u32).init(allocator, 5);
    defer cache.deinit();

    try cache.put(1, 100);
    try cache.put(2, 200);
    try cache.put(3, 300);

    // Remove existing key
    const removed = try cache.remove(2);
    try testing.expect(removed == 200);
    try testing.expect(!cache.contains(2));
    try testing.expect(cache.len() == 2);

    // Try to remove non-existent key
    try testing.expectError(error.KeyNotFound, cache.remove(99));
}

test "CacheTable - clear operation" {
    const allocator = testing.allocator;
    var cache = try CacheTable(u32, u32).init(allocator, 10);
    defer cache.deinit();

    for (0..5) |i| {
        try cache.put(@intCast(i), @intCast(i * 100));
    }

    try testing.expect(cache.len() == 5);
    cache.clear();
    try testing.expect(cache.len() == 0);
    try testing.expect(cache.isEmpty());
}

test "CacheTable - iteration" {
    const allocator = testing.allocator;
    var cache = try CacheTable(u32, u32).init(allocator, 5);
    defer cache.deinit();

    // Insert test data
    try cache.put(1, 100);
    try cache.put(2, 200);
    try cache.put(3, 300);

    var count: usize = 0;
    var sum: u32 = 0;
    var iter = cache.iterator();
    while (iter.next()) |entry| {
        count += 1;
        sum += entry.value_ptr.*;
    }

    try testing.expect(count == 3);
    try testing.expect(sum == 600);
}

test "CacheTable - thread safety" {
    const allocator = testing.allocator;
    var cache = try CacheTable(u32, u32).init(allocator, 100);
    defer cache.deinit();

    const num_threads = 4;
    const operations_per_thread = 250;
    var threads: [num_threads]std.Thread = undefined;
    var thread_sums: [num_threads]u32 = std.mem.zeroes([num_threads]u32);

    for (&threads, 0..) |*thread, i| {
        thread.* = try std.Thread.spawn(.{}, struct {
            cache: *CacheTable(u32, u32),
            operations: u32,
            offset: u32,
            sum: *u32,
            fn run(ctx: @This()) !void {
                for (0..ctx.operations) |j| {
                    const key = ctx.offset + @as(u32, @intCast(j));
                    const value = key * 10;
                    
                    // Mix of put and get operations
                    if (j % 3 == 0) {
                        try ctx.cache.put(key, value);
                    } else {
                        if (ctx.cache.get(key)) |v| {
                            ctx.sum.* += v;
                        } else |err| {
                            // Key not found, that's ok
                            _ = err;
                        }
                    }
                }
            }
        }.run, .{ &cache, operations_per_thread, @as(u32, @intCast(i * operations_per_thread)), &thread_sums[i] });
    }

    for (threads) |thread| thread.join();

    // Verify cache is in a consistent state
    try testing.expect(cache.len() <= 100);
}

test "CacheTable - hit miss statistics" {
    const allocator = testing.allocator;
    var cache = try CacheTable(u32, u32).init(allocator, 5);
    defer cache.deinit();

    // Initially no hits or misses
    try testing.expect(cache.hitCount() == 0);
    try testing.expect(cache.missCount() == 0);

    // Add some items
    try cache.put(1, 100);
    try cache.put(2, 200);

    // Generate hits
    _ = try cache.get(1);
    _ = try cache.get(2);
    _ = try cache.get(1);

    // Generate misses
    _ = cache.get(3) catch |err| {
        try testing.expect(err == error.KeyNotFound);
    };
    _ = cache.get(4) catch |err| {
        try testing.expect(err == error.KeyNotFound);
    };

    try testing.expect(cache.hitCount() == 3);
    try testing.expect(cache.missCount() == 2);

    // Reset statistics
    cache.resetStats();
    try testing.expect(cache.hitCount() == 0);
    try testing.expect(cache.missCount() == 0);
}

test "CacheTable - performance test" {
    const allocator = testing.allocator;
    var cache = try CacheTable(u32, u32).init(allocator, 1000);
    defer cache.deinit();

    const num_operations = 10000;
    const start_time = std.time.nanoTimestamp();

    // Insert operations
    for (0..num_operations) |i| {
        try cache.put(@intCast(i), @intCast(i * 10));
    }

    const insert_time = std.time.nanoTimestamp();

    // Lookup operations (mix of hits and misses)
    var hits: u32 = 0;
    for (0..num_operations) |i| {
        const key = @as(u32, @intCast(i)) % 1500; // Some will miss
        if (cache.get(key)) |_| {
            hits += 1;
        } else |_| {}
    }

    const lookup_time = std.time.nanoTimestamp();

    std.debug.print("Insert time: {}ns\n", .{insert_time - start_time});
    std.debug.print("Lookup time: {}ns\n", .{lookup_time - insert_time});
    std.debug.print("Hit rate: {d:.2}%\n", .{@as(f64, @floatFromInt(hits)) / @as(f64, @floatFromInt(num_operations)) * 100.0});

    try testing.expect(hits > 0);
}

test "CacheTable - edge cases" {
    const allocator = testing.allocator;
    
    // Test with zero capacity (should handle gracefully)
    var cache = try CacheTable(u32, u32).init(allocator, 0);
    defer cache.deinit();

    // Should not be able to add anything
    try cache.put(1, 100);
    try testing.expect(cache.isEmpty()); // Should be immediately evicted

    // Test with very large keys
    cache.deinit();
    cache = try CacheTable(u64, u64).init(allocator, 10);
    defer cache.deinit();

    const large_key: u64 = std.math.maxInt(u64) - 1;
    try cache.put(large_key, large_key);
    try testing.expect((try cache.get(large_key)) == large_key);
}