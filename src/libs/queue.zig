const std = @import("std");
const Allocator = std.mem.Allocator;
const testing = std.testing;

/// 泛型队列（基于环形缓冲区）
pub fn Queue(comptime T: type) type {
    return struct {
        const Self = @This();

        data: []T,
        head: usize,
        tail: usize,
        size: usize,
        capacity: usize,
        allocator: Allocator,

        const INITIAL_CAPACITY = 16;

        /// 初始化队列
        pub fn init(allocator: Allocator) !Self {
            const data = try allocator.alloc(T, INITIAL_CAPACITY);
            return Self{
                .data = data,
                .head = 0,
                .tail = 0,
                .size = 0,
                .capacity = INITIAL_CAPACITY,
                .allocator = allocator,
            };
        }

        /// 初始化指定容量的队列
        pub fn initCapacity(allocator: Allocator, capacity: usize) !Self {
            const actual_capacity = @max(capacity, 1);
            const data = try allocator.alloc(T, actual_capacity);
            return Self{
                .data = data,
                .head = 0,
                .tail = 0,
                .size = 0,
                .capacity = actual_capacity,
                .allocator = allocator,
            };
        }

        /// 释放队列
        pub fn deinit(self: *Self) void {
            self.allocator.free(self.data);
            self.* = undefined;
        }

        /// 获取队列大小
        pub fn len(self: *const Self) usize {
            return self.size;
        }

        /// 检查队列是否为空
        pub fn isEmpty(self: *const Self) bool {
            return self.size == 0;
        }

        /// 检查队列是否已满
        pub fn isFull(self: *const Self) bool {
            return self.size == self.capacity;
        }

        /// 获取下一个索引
        fn nextIndex(self: *const Self, index: usize) usize {
            return (index + 1) % self.capacity;
        }

        /// 确保容量
        pub fn ensureCapacity(self: *Self, new_capacity: usize) !void {
            if (new_capacity <= self.capacity) return;

            const actual_capacity = std.math.ceilPowerOfTwo(usize, new_capacity) catch new_capacity;
            const new_data = try self.allocator.alloc(T, actual_capacity);

            // 复制现有数据
            if (self.size > 0) {
                if (self.head <= self.tail) {
                    // 数据是连续的
                    @memcpy(new_data[0..self.size], self.data[self.head .. self.head + self.size]);
                } else {
                    // 数据是分段的
                    const first_part_size = self.capacity - self.head;
                    @memcpy(new_data[0..first_part_size], self.data[self.head..]);
                    @memcpy(new_data[first_part_size..self.size], self.data[0..self.tail]);
                }
            }

            self.allocator.free(self.data);
            self.data = new_data;
            self.head = 0;
            self.tail = self.size;
            self.capacity = actual_capacity;
        }

        /// 入队
        pub fn enqueue(self: *Self, item: T) !void {
            if (self.isFull()) {
                try self.ensureCapacity(self.capacity * 2);
            }

            self.data[self.tail] = item;
            self.tail = self.nextIndex(self.tail);
            self.size += 1;
        }

        /// 出队
        pub fn dequeue(self: *Self) ?T {
            if (self.isEmpty()) return null;

            const item = self.data[self.head];
            self.head = self.nextIndex(self.head);
            self.size -= 1;

            return item;
        }

        /// 查看队首元素（不移除）
        pub fn peek(self: *const Self) ?T {
            if (self.isEmpty()) return null;
            return self.data[self.head];
        }

        /// 查看队尾元素（不移除）
        pub fn peekBack(self: *const Self) ?T {
            if (self.isEmpty()) return null;
            const back_index = if (self.tail == 0) self.capacity - 1 else self.tail - 1;
            return self.data[back_index];
        }

        /// 清空队列
        pub fn clear(self: *Self) void {
            self.head = 0;
            self.tail = 0;
            self.size = 0;
        }

        /// 获取指定位置的元素
        pub fn get(self: *const Self, index: usize) ?T {
            if (index >= self.size) return null;

            const actual_index = (self.head + index) % self.capacity;
            return self.data[actual_index];
        }

        /// 转换为切片（分配新内存）
        pub fn toSlice(self: *const Self) ![]T {
            const result = try self.allocator.alloc(T, self.size);

            if (self.size > 0) {
                if (self.head <= self.tail) {
                    @memcpy(result, self.data[self.head .. self.head + self.size]);
                } else {
                    const first_part_size = self.capacity - self.head;
                    @memcpy(result[0..first_part_size], self.data[self.head..]);
                    @memcpy(result[first_part_size..], self.data[0..self.tail]);
                }
            }

            return result;
        }

        /// 克隆队列
        pub fn clone(self: *const Self) !Self {
            var new_queue = try Self.initCapacity(self.allocator, self.capacity);

            if (self.size > 0) {
                if (self.head <= self.tail) {
                    @memcpy(new_queue.data[0..self.size], self.data[self.head .. self.head + self.size]);
                } else {
                    const first_part_size = self.capacity - self.head;
                    @memcpy(new_queue.data[0..first_part_size], self.data[self.head..]);
                    @memcpy(new_queue.data[first_part_size..self.size], self.data[0..self.tail]);
                }
            }

            new_queue.size = self.size;
            new_queue.tail = self.size;

            return new_queue;
        }

        /// 迭代器
        pub const Iterator = struct {
            queue: *const Self,
            index: usize,

            pub fn next(self: *Iterator) ?T {
                if (self.index >= self.queue.size) return null;

                const item = self.queue.get(self.index).?;
                self.index += 1;
                return item;
            }
        };

        /// 获取迭代器
        pub fn iterator(self: *const Self) Iterator {
            return Iterator{
                .queue = self,
                .index = 0,
            };
        }
    };
}

/// 双端队列（Deque）
pub fn Deque(comptime T: type) type {
    return struct {
        const Self = @This();

        data: []T,
        head: usize,
        tail: usize,
        size: usize,
        capacity: usize,
        allocator: Allocator,

        const INITIAL_CAPACITY = 16;

        /// 初始化双端队列
        pub fn init(allocator: Allocator) !Self {
            const data = try allocator.alloc(T, INITIAL_CAPACITY);
            return Self{
                .data = data,
                .head = 0,
                .tail = 0,
                .size = 0,
                .capacity = INITIAL_CAPACITY,
                .allocator = allocator,
            };
        }

        /// 释放双端队列
        pub fn deinit(self: *Self) void {
            self.allocator.free(self.data);
            self.* = undefined;
        }

        /// 获取队列大小
        pub fn len(self: *const Self) usize {
            return self.size;
        }

        /// 检查队列是否为空
        pub fn isEmpty(self: *const Self) bool {
            return self.size == 0;
        }

        /// 获取前一个索引
        fn prevIndex(self: *const Self, index: usize) usize {
            return if (index == 0) self.capacity - 1 else index - 1;
        }

        /// 获取下一个索引
        fn nextIndex(self: *const Self, index: usize) usize {
            return (index + 1) % self.capacity;
        }

        /// 确保容量
        pub fn ensureCapacity(self: *Self, new_capacity: usize) !void {
            if (new_capacity <= self.capacity) return;

            const actual_capacity = std.math.ceilPowerOfTwo(usize, new_capacity) catch new_capacity;
            const new_data = try self.allocator.alloc(T, actual_capacity);

            // 复制现有数据
            if (self.size > 0) {
                if (self.head <= self.tail) {
                    @memcpy(new_data[0..self.size], self.data[self.head .. self.head + self.size]);
                } else {
                    const first_part_size = self.capacity - self.head;
                    @memcpy(new_data[0..first_part_size], self.data[self.head..]);
                    @memcpy(new_data[first_part_size..self.size], self.data[0..self.tail]);
                }
            }

            self.allocator.free(self.data);
            self.data = new_data;
            self.head = 0;
            self.tail = self.size;
            self.capacity = actual_capacity;
        }

        /// 从前端添加元素
        pub fn pushFront(self: *Self, item: T) !void {
            if (self.size == self.capacity) {
                try self.ensureCapacity(self.capacity * 2);
            }

            self.head = self.prevIndex(self.head);
            self.data[self.head] = item;
            self.size += 1;
        }

        /// 从后端添加元素
        pub fn pushBack(self: *Self, item: T) !void {
            if (self.size == self.capacity) {
                try self.ensureCapacity(self.capacity * 2);
            }

            self.data[self.tail] = item;
            self.tail = self.nextIndex(self.tail);
            self.size += 1;
        }

        /// 从前端移除元素
        pub fn popFront(self: *Self) ?T {
            if (self.isEmpty()) return null;

            const item = self.data[self.head];
            self.head = self.nextIndex(self.head);
            self.size -= 1;

            return item;
        }

        /// 从后端移除元素
        pub fn popBack(self: *Self) ?T {
            if (self.isEmpty()) return null;

            self.tail = self.prevIndex(self.tail);
            const item = self.data[self.tail];
            self.size -= 1;

            return item;
        }

        /// 查看前端元素
        pub fn peekFront(self: *const Self) ?T {
            if (self.isEmpty()) return null;
            return self.data[self.head];
        }

        /// 查看后端元素
        pub fn peekBack(self: *const Self) ?T {
            if (self.isEmpty()) return null;
            const back_index = self.prevIndex(self.tail);
            return self.data[back_index];
        }

        /// 清空队列
        pub fn clear(self: *Self) void {
            self.head = 0;
            self.tail = 0;
            self.size = 0;
        }

        /// 获取指定位置的元素
        pub fn get(self: *const Self, index: usize) ?T {
            if (index >= self.size) return null;

            const actual_index = (self.head + index) % self.capacity;
            return self.data[actual_index];
        }
    };
}

/// 优先队列（基于二叉堆）
pub fn PriorityQueue(comptime T: type, comptime compareFn: fn (T, T) bool) type {
    return struct {
        const Self = @This();

        data: []T,
        size: usize,
        allocator: Allocator,

        const INITIAL_CAPACITY = 16;

        /// 初始化优先队列
        pub fn init(allocator: Allocator) !Self {
            const data = try allocator.alloc(T, INITIAL_CAPACITY);
            return Self{
                .data = data,
                .size = 0,
                .allocator = allocator,
            };
        }

        /// 释放优先队列
        pub fn deinit(self: *Self) void {
            self.allocator.free(self.data);
            self.* = undefined;
        }

        /// 获取队列大小
        pub fn len(self: *const Self) usize {
            return self.size;
        }

        /// 检查队列是否为空
        pub fn isEmpty(self: *const Self) bool {
            return self.size == 0;
        }

        /// 确保容量
        pub fn ensureCapacity(self: *Self, new_capacity: usize) !void {
            if (new_capacity <= self.data.len) return;

            const actual_capacity = std.math.ceilPowerOfTwo(usize, new_capacity) catch new_capacity;
            self.data = try self.allocator.realloc(self.data, actual_capacity);
        }

        /// 上浮操作
        fn heapifyUp(self: *Self, index: usize) void {
            var current = index;

            while (current > 0) {
                const parent = (current - 1) / 2;

                if (!compareFn(self.data[current], self.data[parent])) {
                    break;
                }

                std.mem.swap(T, &self.data[current], &self.data[parent]);
                current = parent;
            }
        }

        /// 下沉操作
        fn heapifyDown(self: *Self, index: usize) void {
            var current = index;

            while (true) {
                var largest = current;
                const left = 2 * current + 1;
                const right = 2 * current + 2;

                if (left < self.size and compareFn(self.data[left], self.data[largest])) {
                    largest = left;
                }

                if (right < self.size and compareFn(self.data[right], self.data[largest])) {
                    largest = right;
                }

                if (largest == current) break;

                std.mem.swap(T, &self.data[current], &self.data[largest]);
                current = largest;
            }
        }

        /// 插入元素
        pub fn insert(self: *Self, item: T) !void {
            try self.ensureCapacity(self.size + 1);

            self.data[self.size] = item;
            self.heapifyUp(self.size);
            self.size += 1;
        }

        /// 移除并返回最高优先级元素
        pub fn extract(self: *Self) ?T {
            if (self.isEmpty()) return null;

            const result = self.data[0];
            self.size -= 1;

            if (self.size > 0) {
                self.data[0] = self.data[self.size];
                self.heapifyDown(0);
            }

            return result;
        }

        /// 查看最高优先级元素
        pub fn peek(self: *const Self) ?T {
            if (self.isEmpty()) return null;
            return self.data[0];
        }

        /// 清空队列
        pub fn clear(self: *Self) void {
            self.size = 0;
        }
    };
}

/// 常用队列类型别名
pub const IntQueue = Queue(i32);
pub const StringQueue = Queue([]const u8);
pub const ObjectQueue = Queue(*anyopaque);

pub const IntDeque = Deque(i32);
pub const StringDeque = Deque([]const u8);

/// 最大堆比较函数
fn maxHeapCompare(a: i32, b: i32) bool {
    return a > b;
}

/// 最小堆比较函数
fn minHeapCompare(a: i32, b: i32) bool {
    return a < b;
}

pub const MaxPriorityQueue = PriorityQueue(i32, maxHeapCompare);
pub const MinPriorityQueue = PriorityQueue(i32, minHeapCompare);

test "Queue basic operations" {
    var queue = try Queue(i32).init(testing.allocator);
    defer queue.deinit();

    try testing.expect(queue.isEmpty());
    try testing.expect(queue.len() == 0);

    try queue.enqueue(1);
    try queue.enqueue(2);
    try queue.enqueue(3);

    try testing.expect(!queue.isEmpty());
    try testing.expect(queue.len() == 3);
    try testing.expect(queue.peek().? == 1);
    try testing.expect(queue.peekBack().? == 3);

    try testing.expect(queue.dequeue().? == 1);
    try testing.expect(queue.dequeue().? == 2);
    try testing.expect(queue.len() == 1);

    try testing.expect(queue.dequeue().? == 3);
    try testing.expect(queue.isEmpty());
    try testing.expect(queue.dequeue() == null);
}

test "Queue iterator" {
    var queue = try Queue(i32).init(testing.allocator);
    defer queue.deinit();

    try queue.enqueue(1);
    try queue.enqueue(2);
    try queue.enqueue(3);

    var iter = queue.iterator();
    try testing.expect(iter.next().? == 1);
    try testing.expect(iter.next().? == 2);
    try testing.expect(iter.next().? == 3);
    try testing.expect(iter.next() == null);
}

test "Deque operations" {
    var deque = try Deque(i32).init(testing.allocator);
    defer deque.deinit();

    try deque.pushBack(1);
    try deque.pushFront(2);
    try deque.pushBack(3);
    try deque.pushFront(4);

    // 现在顺序应该是: 4, 2, 1, 3
    try testing.expect(deque.len() == 4);
    try testing.expect(deque.peekFront().? == 4);
    try testing.expect(deque.peekBack().? == 3);

    try testing.expect(deque.popFront().? == 4);
    try testing.expect(deque.popBack().? == 3);
    try testing.expect(deque.popFront().? == 2);
    try testing.expect(deque.popBack().? == 1);

    try testing.expect(deque.isEmpty());
}

test "PriorityQueue operations" {
    var pq = try MaxPriorityQueue.init(testing.allocator);
    defer pq.deinit();

    try pq.insert(3);
    try pq.insert(1);
    try pq.insert(4);
    try pq.insert(2);

    try testing.expect(pq.len() == 4);
    try testing.expect(pq.peek().? == 4); // 最大值

    try testing.expect(pq.extract().? == 4);
    try testing.expect(pq.extract().? == 3);
    try testing.expect(pq.extract().? == 2);
    try testing.expect(pq.extract().? == 1);

    try testing.expect(pq.isEmpty());
}
