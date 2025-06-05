const std = @import("std");
const Allocator = std.mem.Allocator;
const testing = std.testing;
const memory = @import("memory.zig");

/// 泛型哈希表
pub fn HashMap(comptime K: type, comptime V: type) type {
    return struct {
        const Self = @This();

        /// 哈希表条目
        const Entry = struct {
            key: K,
            value: V,
            hash: u64,
            next: ?*Entry,
        };

        buckets: []?*Entry,
        size: usize,
        capacity: usize,
        allocator: Allocator,

        const INITIAL_CAPACITY = 16;
        const LOAD_FACTOR = 0.75;

        /// 初始化哈希表
        pub fn init(allocator: Allocator) !Self {
            const buckets = try allocator.alloc(?*Entry, INITIAL_CAPACITY);
            @memset(buckets, null);

            return Self{
                .buckets = buckets,
                .size = 0,
                .capacity = INITIAL_CAPACITY,
                .allocator = allocator,
            };
        }

        /// 初始化指定容量的哈希表
        pub fn initCapacity(allocator: Allocator, capacity: usize) !Self {
            const actual_capacity = std.math.ceilPowerOfTwo(usize, capacity) catch capacity;
            const buckets = try allocator.alloc(?*Entry, actual_capacity);
            @memset(buckets, null);

            return Self{
                .buckets = buckets,
                .size = 0,
                .capacity = actual_capacity,
                .allocator = allocator,
            };
        }

        /// 释放哈希表
        pub fn deinit(self: *Self) void {
            self.clear();
            self.allocator.free(self.buckets);
            self.* = undefined;
        }

        /// 获取哈希表大小
        pub fn len(self: *const Self) usize {
            return self.size;
        }

        /// 检查哈希表是否为空
        pub fn isEmpty(self: *const Self) bool {
            return self.size == 0;
        }

        /// 计算键的哈希值
        fn hash(key: K) u64 {
            if (K == []const u8) {
                return std.hash_map.hashString(key);
            } else {
                var hasher = std.hash.Wyhash.init(0);
                std.hash.autoHash(&hasher, key);
                return hasher.final();
            }
        }

        /// 比较两个键是否相等
        fn keyEqual(a: K, b: K) bool {
            if (K == []const u8) {
                return std.mem.eql(u8, a, b);
            } else {
                return std.meta.eql(a, b);
            }
        }

        /// 获取桶索引
        fn getBucketIndex(self: *const Self, key_hash: u64) usize {
            return key_hash & (self.capacity - 1);
        }

        /// 查找条目
        fn findEntry(self: *const Self, key: K, key_hash: u64) ?*Entry {
            const bucket_index = self.getBucketIndex(key_hash);
            var entry = self.buckets[bucket_index];

            while (entry) |e| {
                if (e.hash == key_hash and keyEqual(e.key, key)) {
                    return e;
                }
                entry = e.next;
            }

            return null;
        }

        /// 插入或更新键值对
        pub fn put(self: *Self, key: K, value: V) !void {
            const key_hash = hash(key);

            // 检查是否需要扩容
            if (self.size >= @as(usize, @intFromFloat(@as(f64, @floatFromInt(self.capacity)) * LOAD_FACTOR))) {
                try self.resize();
            }

            // 查找现有条目
            if (self.findEntry(key, key_hash)) |entry| {
                entry.value = value;
                return;
            }

            // 创建新条目
            const new_entry = try self.allocator.create(Entry);
            new_entry.* = Entry{
                .key = key,
                .value = value,
                .hash = key_hash,
                .next = null,
            };

            // 插入到桶中
            const bucket_index = self.getBucketIndex(key_hash);
            new_entry.next = self.buckets[bucket_index];
            self.buckets[bucket_index] = new_entry;
            self.size += 1;
        }

        /// 获取值
        pub fn get(self: *const Self, key: K) ?V {
            const key_hash = hash(key);
            if (self.findEntry(key, key_hash)) |entry| {
                return entry.value;
            }
            return null;
        }

        /// 获取值的指针
        pub fn getPtr(self: *Self, key: K) ?*V {
            const key_hash = hash(key);
            if (self.findEntry(key, key_hash)) |entry| {
                return &entry.value;
            }
            return null;
        }

        /// 获取值的常量指针
        pub fn getPtrConst(self: *const Self, key: K) ?*const V {
            const key_hash = hash(key);
            if (self.findEntry(key, key_hash)) |entry| {
                return &entry.value;
            }
            return null;
        }

        /// 检查是否包含键
        pub fn contains(self: *const Self, key: K) bool {
            return self.get(key) != null;
        }

        /// 移除键值对
        pub fn remove(self: *Self, key: K) bool {
            const key_hash = hash(key);
            const bucket_index = self.getBucketIndex(key_hash);

            var prev: ?*Entry = null;
            var entry = self.buckets[bucket_index];

            while (entry) |e| {
                if (e.hash == key_hash and keyEqual(e.key, key)) {
                    if (prev) |p| {
                        p.next = e.next;
                    } else {
                        self.buckets[bucket_index] = e.next;
                    }

                    self.allocator.destroy(e);
                    self.size -= 1;
                    return true;
                }

                prev = e;
                entry = e.next;
            }

            return false;
        }

        /// 清空哈希表
        pub fn clear(self: *Self) void {
            for (self.buckets) |*bucket| {
                var entry = bucket.*;
                while (entry) |e| {
                    const next = e.next;
                    self.allocator.destroy(e);
                    entry = next;
                }
                bucket.* = null;
            }
            self.size = 0;
        }

        /// 扩容
        fn resize(self: *Self) !void {
            const old_buckets = self.buckets;
            const old_capacity = self.capacity;
            _ = old_capacity; // 用于标记变量已使用

            self.capacity *= 2;
            self.buckets = try self.allocator.alloc(?*Entry, self.capacity);
            @memset(self.buckets, null);
            self.size = 0;

            // 重新插入所有条目
            for (old_buckets) |bucket| {
                var entry = bucket;
                while (entry) |e| {
                    const next = e.next;
                    e.next = null;

                    const bucket_index = self.getBucketIndex(e.hash);
                    e.next = self.buckets[bucket_index];
                    self.buckets[bucket_index] = e;
                    self.size += 1;

                    entry = next;
                }
            }

            self.allocator.free(old_buckets);
        }

        /// 获取所有键
        pub fn keys(self: *const Self, allocator: Allocator) ![]K {
            var result = try allocator.alloc(K, self.size);
            var index: usize = 0;

            for (self.buckets) |bucket| {
                var entry = bucket;
                while (entry) |e| {
                    result[index] = e.key;
                    index += 1;
                    entry = e.next;
                }
            }

            return result;
        }

        /// 获取所有值
        pub fn values(self: *const Self, allocator: Allocator) ![]V {
            var result = try allocator.alloc(V, self.size);
            var index: usize = 0;

            for (self.buckets) |bucket| {
                var entry = bucket;
                while (entry) |e| {
                    result[index] = e.value;
                    index += 1;
                    entry = e.next;
                }
            }

            return result;
        }

        /// 迭代器
        pub const Iterator = struct {
            map: *const Self,
            bucket_index: usize,
            current_entry: ?*Entry,

            pub const Item = struct { key: K, value: V };

            pub fn next(self: *Iterator) ?Item {
                while (self.bucket_index < self.map.capacity) {
                    if (self.current_entry) |entry| {
                        const result = Item{ .key = entry.key, .value = entry.value };
                        self.current_entry = entry.next;
                        return result;
                    }

                    self.bucket_index += 1;
                    if (self.bucket_index < self.map.capacity) {
                        self.current_entry = self.map.buckets[self.bucket_index];
                    }
                }

                return null;
            }
        };

        /// 获取迭代器
        pub fn iterator(self: *const Self) Iterator {
            var iter = Iterator{
                .map = self,
                .bucket_index = 0,
                .current_entry = null,
            };

            // 找到第一个非空桶
            while (iter.bucket_index < self.capacity) {
                if (self.buckets[iter.bucket_index]) |entry| {
                    iter.current_entry = entry;
                    break;
                }
                iter.bucket_index += 1;
            }

            return iter;
        }
    };
}

/// 字符串到整数的哈希表
pub const StringIntMap = HashMap([]const u8, i32);

/// 整数到字符串的哈希表
pub const IntStringMap = HashMap(i32, []const u8);

/// 字符串到对象的哈希表
pub const StringObjectMap = HashMap([]const u8, *anyopaque);

test "HashMap basic operations" {
    var map = try HashMap([]const u8, i32).init(testing.allocator);
    defer map.deinit();

    // 测试插入和获取
    try map.put("hello", 1);
    try map.put("world", 2);
    try map.put("test", 3);

    try testing.expect(map.len() == 3);
    try testing.expect(map.get("hello").? == 1);
    try testing.expect(map.get("world").? == 2);
    try testing.expect(map.get("test").? == 3);
    try testing.expect(map.get("notfound") == null);

    // 测试更新
    try map.put("hello", 10);
    try testing.expect(map.get("hello").? == 10);
    try testing.expect(map.len() == 3);

    // 测试包含
    try testing.expect(map.contains("hello"));
    try testing.expect(!map.contains("notfound"));

    // 测试移除
    try testing.expect(map.remove("hello"));
    try testing.expect(!map.remove("hello"));
    try testing.expect(map.len() == 2);
    try testing.expect(map.get("hello") == null);
}

test "HashMap with integer keys" {
    var map = try HashMap(i32, []const u8).init(testing.allocator);
    defer map.deinit();

    try map.put(1, "one");
    try map.put(2, "two");
    try map.put(3, "three");

    try testing.expect(map.len() == 3);
    try testing.expect(std.mem.eql(u8, map.get(1).?, "one"));
    try testing.expect(std.mem.eql(u8, map.get(2).?, "two"));
    try testing.expect(std.mem.eql(u8, map.get(3).?, "three"));
}

test "HashMap iterator" {
    var map = try HashMap(i32, i32).init(testing.allocator);
    defer map.deinit();

    try map.put(1, 10);
    try map.put(2, 20);
    try map.put(3, 30);

    var iter = map.iterator();
    var count: usize = 0;
    var sum: i32 = 0;

    while (iter.next()) |entry| {
        count += 1;
        sum += entry.value;
    }

    try testing.expect(count == 3);
    try testing.expect(sum == 60);
}

test "HashMap resize" {
    var map = try HashMap(i32, i32).init(testing.allocator);
    defer map.deinit();

    // 插入足够多的元素触发扩容
    for (0..100) |i| {
        try map.put(@intCast(i), @intCast(i * 2));
    }

    try testing.expect(map.len() == 100);

    // 验证所有元素都还在
    for (0..100) |i| {
        try testing.expect(map.get(@intCast(i)).? == @as(i32, @intCast(i * 2)));
    }
}

test "HashMap clear" {
    var map = try HashMap(i32, i32).init(testing.allocator);
    defer map.deinit();

    try map.put(1, 10);
    try map.put(2, 20);
    try testing.expect(map.len() == 2);

    map.clear();
    try testing.expect(map.len() == 0);
    try testing.expect(map.isEmpty());
    try testing.expect(map.get(1) == null);
}
