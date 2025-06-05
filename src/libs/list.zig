const std = @import("std");
const Allocator = std.mem.Allocator;
const testing = std.testing;
const memory = @import("memory.zig");

/// 泛型动态列表
pub fn List(comptime T: type) type {
    return struct {
        const Self = @This();

        buffer: []T, // The actual allocated buffer
        count: usize, // Current number of items
        allocator: Allocator,

        const INITIAL_CAPACITY = 4;
        const GROWTH_FACTOR = 2;

        /// 初始化空列表
        pub fn init(allocator: Allocator) Self {
            std.debug.print("List.init: entering for type {any}\n", .{@typeName(T)});
            const result = Self{
                .buffer = &[_]T{},
                .count = 0,
                .allocator = allocator,
            };
            std.debug.print("List.init: exiting for type {any}\n", .{@typeName(T)});
            return result;
        }

        /// 初始化指定容量的列表
        pub fn initCapacity(allocator: Allocator, capacity: usize) !Self {
            const buffer = try allocator.alloc(T, capacity);
            return Self{
                .buffer = buffer,
                .count = 0,
                .allocator = allocator,
            };
        }

        /// 释放列表
        pub fn deinit(self: *Self) void {
            if (self.buffer.len > 0) { // buffer.len is the capacity
                self.allocator.free(self.buffer);
            }
            self.* = undefined;
        }

        /// 获取列表长度
        pub fn len(self: *const Self) usize {
            return self.count;
        }

        /// 检查列表是否为空
        pub fn isEmpty(self: *const Self) bool {
            return self.count == 0;
        }

        /// 获取指定索引的元素
        pub fn get(self: *const Self, index: usize) T {
            if (index >= self.count) {
                @panic("索引越界");
            }
            return self.buffer[index];
        }

        /// 获取指定索引的元素指针
        pub fn getPtr(self: *Self, index: usize) *T {
            if (index >= self.count) {
                @panic("索引越界");
            }
            return &self.buffer[index];
        }

        /// 设置指定索引的元素
        pub fn set(self: *Self, index: usize, item: T) void {
            if (index >= self.count) {
                @panic("索引越界");
            }
            self.buffer[index] = item;
        }

        /// 添加元素到列表末尾
        pub fn append(self: *Self, item: T) !void {
            try self.ensureCapacity(self.count + 1);
            self.buffer[self.count] = item;
            self.count += 1;
        }

        /// 添加多个元素到列表末尾
        pub fn appendSlice(self: *Self, items: []const T) !void {
            try self.ensureCapacity(self.count + items.len);
            @memcpy(self.buffer[self.count .. self.count + items.len], items);
            self.count += items.len;
        }

        /// 在指定位置插入元素
        pub fn insert(self: *Self, index: usize, item: T) !void {
            if (index > self.count) {
                @panic("索引越界");
            }

            try self.ensureCapacity(self.count + 1);

            // 移动元素为新元素腾出空间
            if (index < self.count) {
                std.mem.copyBackwards(T, self.buffer[index + 1 .. self.count + 1], self.buffer[index..self.count]);
            }

            self.buffer[index] = item;
            self.count += 1;
        }

        /// 移除指定索引的元素
        pub fn remove(self: *Self, index: usize) T {
            if (index >= self.count) {
                @panic("索引越界");
            }

            const item = self.buffer[index];

            // 移动后续元素
            if (index < self.count - 1) {
                std.mem.copyForwards(T, self.buffer[index .. self.count - 1], self.buffer[index + 1 .. self.count]);
            }

            self.count -= 1;
            return item;
        }

        /// 移除最后一个元素
        pub fn pop(self: *Self) ?T {
            if (self.count == 0) {
                return null;
            }

            self.count -= 1;
            return self.buffer[self.count];
        }

        /// 移除第一个匹配的元素
        pub fn removeItem(self: *Self, item: T) bool {
            for (self.buffer[0..self.count], 0..) |list_item, i| {
                if (std.meta.eql(list_item, item)) {
                    _ = self.remove(i);
                    return true;
                }
            }
            return false;
        }

        /// 清空列表
        pub fn clear(self: *Self) void {
            self.count = 0;
        }

        /// 查找元素索引
        pub fn indexOf(self: *const Self, item: T) ?usize {
            for (self.buffer[0..self.count], 0..) |list_item, i| {
                if (std.meta.eql(list_item, item)) {
                    return i;
                }
            }
            return null;
        }

        /// 检查是否包含元素
        pub fn contains(self: *const Self, item: T) bool {
            return self.indexOf(item) != null;
        }

        /// 获取第一个元素
        pub fn first(self: *const Self) ?T {
            if (self.count == 0) {
                return null;
            }
            return self.buffer[0];
        }

        /// 获取最后一个元素
        pub fn last(self: *const Self) ?T {
            if (self.count == 0) {
                return null;
            }
            return self.buffer[self.count - 1];
        }

        /// 反转列表
        pub fn reverse(self: *Self) void {
            std.mem.reverse(T, self.buffer[0..self.count]);
        }

        /// 排序列表
        pub fn sort(self: *Self, comptime lessThan: fn (lhs: T, rhs: T) bool) void {
            std.mem.sort(T, self.buffer[0..self.count], {}, struct {
                fn inner(context: void, lhs: T, rhs: T) bool {
                    _ = context;
                    return lessThan(lhs, rhs);
                }
            }.inner);
        }

        /// 确保容量足够
        fn ensureCapacity(self: *Self, new_count: usize) !void {
            if (new_count <= self.buffer.len) { // buffer.len is current capacity
                return;
            }

            const better_capacity = if (self.buffer.len == 0)
                @max(INITIAL_CAPACITY, new_count)
            else
                @max(self.buffer.len * GROWTH_FACTOR, new_count);

            self.buffer = try self.allocator.realloc(self.buffer, better_capacity);
        }

        /// 收缩容量到实际大小
        pub fn shrinkToFit(self: *Self) !void {
            if (self.buffer.len == self.count) { // buffer.len is current capacity
                return;
            }

            if (self.count == 0) {
                if (self.buffer.len > 0) {
                    self.allocator.free(self.buffer);
                }
                self.buffer = &[_]T{};
                return;
            }

            self.buffer = try self.allocator.realloc(self.buffer[0..self.count], self.count);
        }

        /// 克隆列表
        pub fn clone(self: *const Self) !Self {
            var new_list = try Self.initCapacity(self.allocator, self.count);
            @memcpy(new_list.buffer[0..self.count], self.buffer[0..self.count]);
            new_list.count = self.count;
            return new_list;
        }

        /// 转换为切片
        pub fn toSlice(self: *const Self) []const T {
            return self.buffer[0..self.count];
        }

        /// 转换为可变切片
        pub fn toMutableSlice(self: *Self) []T {
            return self.buffer[0..self.count];
        }

        /// 转换为拥有的切片，调用者获得所有权
        pub fn toOwnedSlice(self: *Self, allocator: Allocator) ![]T {
            _ = allocator; // Still ignoring, but now it's clearer that it's using self.allocator
            const result = try self.allocator.realloc(self.buffer, self.count);
            self.buffer = &[_]T{};
            self.count = 0;
            return result;
        }

        /// 迭代器
        pub const Iterator = struct {
            list: *const Self,
            index: usize,

            pub fn next(self: *Iterator) ?T {
                if (self.index >= self.list.count) {
                    return null;
                }
                const item = self.list.buffer[self.index];
                self.index += 1;
                return item;
            }
        };

        /// 获取迭代器
        pub fn iterator(self: *const Self) Iterator {
            return Iterator{
                .list = self,
                .index = 0,
            };
        }
    };
}

/// 字符串列表类型别名
pub const StringList = List([]const u8);

/// 整数列表类型别名
pub const IntList = List(i32);

/// 对象列表类型别名
pub const ObjectList = List(*anyopaque);

test "List basic operations" {
    var list = List(i32).init(testing.allocator);
    defer list.deinit();

    // 测试添加元素
    try list.append(1);
    try list.append(2);
    try list.append(3);

    try testing.expect(list.len() == 3);
    try testing.expect(list.get(0) == 1);
    try testing.expect(list.get(1) == 2);
    try testing.expect(list.get(2) == 3);

    // 测试插入
    try list.insert(1, 10);
    try testing.expect(list.len() == 4);
    try testing.expect(list.get(1) == 10);

    // 测试移除
    const removed = list.remove(1);
    try testing.expect(removed == 10);
    try testing.expect(list.len() == 3);

    // 测试查找
    try testing.expect(list.indexOf(2).? == 1);
    try testing.expect(list.contains(2));
    try testing.expect(!list.contains(10));
}

test "List with custom capacity" {
    var list = try List(i32).initCapacity(testing.allocator, 10);
    defer list.deinit();

    try testing.expect(list.len() == 0);
    try testing.expect(list.buffer.len == 10);

    // 添加元素不应该重新分配
    for (0..5) |i| {
        try list.append(@intCast(i));
    }

    try testing.expect(list.len() == 5);
    try testing.expect(list.buffer.len == 10);
}

test "List iterator" {
    var list = List(i32).init(testing.allocator);
    defer list.deinit();

    try list.append(1);
    try list.append(2);
    try list.append(3);

    var iter = list.iterator();
    try testing.expect(iter.next().? == 1);
    try testing.expect(iter.next().? == 2);
    try testing.expect(iter.next().? == 3);
    try testing.expect(iter.next() == null);
}

test "List sort and reverse" {
    var list = List(i32).init(testing.allocator);
    defer list.deinit();

    try list.append(3);
    try list.append(1);
    try list.append(2);

    list.sort(struct {
        fn lessThan(lhs: i32, rhs: i32) bool {
            return lhs < rhs;
        }
    }.lessThan);

    try testing.expect(list.get(0) == 1);
    try testing.expect(list.get(1) == 2);
    try testing.expect(list.get(2) == 3);

    list.reverse();

    try testing.expect(list.get(0) == 3);
    try testing.expect(list.get(1) == 2);
    try testing.expect(list.get(2) == 1);
}

test "StringList operations" {
    var list = StringList.init(testing.allocator);
    defer list.deinit();

    try list.append("hello");
    try list.append("world");

    try testing.expect(list.len() == 2);
    try testing.expect(std.mem.eql(u8, list.get(0), "hello"));
    try testing.expect(std.mem.eql(u8, list.get(1), "world"));
}
