const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const testing = std.testing;

/// 小块内存块结构
const SmallBlock = struct {
    buffer: []u8,
    used: usize,
    next: ?*SmallBlock,
    no_enough_times: u32,

    /// 初始化小块
    fn init(allocator: Allocator, size: usize) !*SmallBlock {
        const block = try allocator.create(SmallBlock);
        errdefer allocator.destroy(block);

        block.* = SmallBlock{
            .buffer = try allocator.alloc(u8, size),
            .used = 0,
            .next = null,
            .no_enough_times = 0,
        };
        return block;
    }

    /// 释放小块
    fn deinit(self: *SmallBlock, allocator: Allocator) void {
        allocator.free(self.buffer);
        allocator.destroy(self);
    }

    /// 尝试分配内存
    fn tryAlloc(self: *SmallBlock, size: usize, alignment: usize) ?[]u8 {
        const aligned_used = std.mem.alignForward(usize, self.used, alignment);
        if (aligned_used + size <= self.buffer.len) {
            const result = self.buffer[aligned_used .. aligned_used + size];
            self.used = aligned_used + size;
            return result;
        }
        self.no_enough_times += 1;
        return null;
    }

    /// 重置块
    fn reset(self: *SmallBlock) void {
        self.used = 0;
        self.no_enough_times = 0;
    }
};

/// 大块内存块结构
const BigBlock = struct {
    buffer: []u8,
    next: ?*BigBlock,

    /// 初始化大块
    fn init(allocator: Allocator, size: usize) !*BigBlock {
        const block = try allocator.create(BigBlock);
        errdefer allocator.destroy(block);

        block.* = BigBlock{
            .buffer = try allocator.alloc(u8, size),
            .next = null,
        };
        return block;
    }

    /// 释放大块
    fn deinit(self: *BigBlock, allocator: Allocator) void {
        allocator.free(self.buffer);
        allocator.destroy(self);
    }
};

/// 内存池结构
pub const MemoryPool = struct {
    allocator: Allocator,
    small_block_size: usize,
    big_block_threshold: usize,
    current_small_block: ?*SmallBlock,
    small_blocks: ?*SmallBlock,
    big_blocks: ?*BigBlock,
    total_allocated: usize,

    const DEFAULT_SMALL_BLOCK_SIZE = 64 * 1024; // 64KB
    const DEFAULT_BIG_BLOCK_THRESHOLD = 8 * 1024; // 8KB

    /// 初始化内存池
    pub fn init(allocator: Allocator) MemoryPool {
        return MemoryPool{
            .allocator = allocator,
            .small_block_size = DEFAULT_SMALL_BLOCK_SIZE,
            .big_block_threshold = DEFAULT_BIG_BLOCK_THRESHOLD,
            .current_small_block = null,
            .small_blocks = null,
            .big_blocks = null,
            .total_allocated = 0,
        };
    }

    /// 初始化内存池（自定义大小）
    pub fn initWithSize(allocator: Allocator, small_block_size: usize, big_block_threshold: usize) MemoryPool {
        return MemoryPool{
            .allocator = allocator,
            .small_block_size = small_block_size,
            .big_block_threshold = big_block_threshold,
            .current_small_block = null,
            .small_blocks = null,
            .big_blocks = null,
            .total_allocated = 0,
        };
    }

    /// 释放内存池
    pub fn deinit(self: *MemoryPool) void {
        // 释放所有小块
        var small_block = self.small_blocks;
        while (small_block) |block| {
            const next = block.next;
            block.deinit(self.allocator);
            small_block = next;
        }

        // 释放所有大块
        var big_block = self.big_blocks;
        while (big_block) |block| {
            const next = block.next;
            block.deinit(self.allocator);
            big_block = next;
        }

        self.current_small_block = null;
        self.small_blocks = null;
        self.big_blocks = null;
        self.total_allocated = 0;
    }

    /// 清空内存池（重置所有小块，释放大块）
    pub fn clear(self: *MemoryPool) void {
        // 重置所有小块
        var small_block = self.small_blocks;
        while (small_block) |block| {
            block.reset();
            small_block = block.next;
        }

        // 释放所有大块
        var big_block = self.big_blocks;
        while (big_block) |block| {
            const next = block.next;
            block.deinit(self.allocator);
            big_block = next;
        }

        self.big_blocks = null;
        self.current_small_block = self.small_blocks;
    }

    /// 分配内存
    pub fn alloc(self: *MemoryPool, size: usize, alignment: usize) ![]u8 {
        if (size >= self.big_block_threshold) {
            return self.allocBig(size);
        } else {
            return self.allocSmall(size, alignment);
        }
    }

    /// 分配小块内存
    fn allocSmall(self: *MemoryPool, size: usize, alignment: usize) ![]u8 {
        // 尝试从当前小块分配
        if (self.current_small_block) |block| {
            if (block.tryAlloc(size, alignment)) |memory| {
                return memory;
            }
        }

        // 尝试从其他小块分配
        var block = self.small_blocks;
        while (block) |b| {
            if (b != self.current_small_block) {
                if (b.tryAlloc(size, alignment)) |memory| {
                    self.current_small_block = b;
                    return memory;
                }
            }
            block = b.next;
        }

        // 创建新的小块
        const new_block = try SmallBlock.init(self.allocator, self.small_block_size);
        new_block.next = self.small_blocks;
        self.small_blocks = new_block;
        self.current_small_block = new_block;
        self.total_allocated += self.small_block_size;

        return new_block.tryAlloc(size, alignment) orelse return error.OutOfMemory;
    }

    /// 分配大块内存
    fn allocBig(self: *MemoryPool, size: usize) ![]u8 {
        const new_block = try BigBlock.init(self.allocator, size);
        new_block.next = self.big_blocks;
        self.big_blocks = new_block;
        self.total_allocated += size;
        return new_block.buffer;
    }

    /// 重新分配内存
    pub fn realloc(self: *MemoryPool, old_memory: []u8, new_size: usize, alignment: usize) ![]u8 {
        if (new_size <= old_memory.len) {
            return old_memory[0..new_size];
        }

        const new_memory = try self.alloc(new_size, alignment);
        @memcpy(new_memory[0..old_memory.len], old_memory);
        return new_memory;
    }

    /// 获取统计信息
    pub fn getStats(self: *const MemoryPool) struct {
        total_allocated: usize,
        small_blocks_count: u32,
        big_blocks_count: u32,
    } {
        var small_count: u32 = 0;
        var small_block = self.small_blocks;
        while (small_block) |block| {
            small_count += 1;
            small_block = block.next;
        }

        var big_count: u32 = 0;
        var big_block = self.big_blocks;
        while (big_block) |block| {
            big_count += 1;
            big_block = block.next;
        }

        return .{
            .total_allocated = self.total_allocated,
            .small_blocks_count = small_count,
            .big_blocks_count = big_count,
        };
    }
};

/// 内存池分配器适配器
pub const MemoryPoolAllocator = struct {
    pool: *MemoryPool,

    /// 创建分配器
    pub fn allocator(self: *MemoryPoolAllocator) Allocator {
        return Allocator{
            .ptr = self,
            .vtable = &.{
                .alloc = alloc,
                .resize = resize,
                .free = free,
                .remap = Allocator.noRemap,
            },
        };
    }

    fn alloc(ctx: *anyopaque, len: usize, ptr_align: std.mem.Alignment, ret_addr: usize) ?[*]u8 {
        _ = ret_addr;
        const self: *MemoryPoolAllocator = @ptrCast(@alignCast(ctx));
        const alignment = ptr_align.toByteUnits();
        const memory = self.pool.alloc(len, alignment) catch return null;
        return memory.ptr;
    }

    fn resize(ctx: *anyopaque, buf: []u8, buf_align: std.mem.Alignment, new_len: usize, ret_addr: usize) bool {
        _ = ctx;
        _ = buf_align;
        _ = ret_addr;
        return new_len <= buf.len;
    }

    fn free(ctx: *anyopaque, buf: []u8, buf_align: std.mem.Alignment, ret_addr: usize) void {
        _ = ctx;
        _ = buf;
        _ = buf_align;
        _ = ret_addr;
        // 内存池不支持单独释放，在池销毁时统一释放
    }
};

test "MemoryPool basic operations" {
    var pool = MemoryPool.init(testing.allocator);
    defer pool.deinit();

    // 测试小块分配
    const small_mem1 = try pool.alloc(100, 1);
    try testing.expect(small_mem1.len == 100);

    const small_mem2 = try pool.alloc(200, 4);
    try testing.expect(small_mem2.len == 200);

    // 测试大块分配
    const big_mem = try pool.alloc(10000, 1);
    try testing.expect(big_mem.len == 10000);

    // 检查统计信息
    const stats = pool.getStats();
    try testing.expect(stats.small_blocks_count >= 1);
    try testing.expect(stats.big_blocks_count >= 1);
}

test "MemoryPool clear and reuse" {
    var pool = MemoryPool.init(testing.allocator);
    defer pool.deinit();

    // 分配一些内存
    _ = try pool.alloc(100, 1);
    _ = try pool.alloc(10000, 1); // 大块

    const stats_before = pool.getStats();

    // 清空池
    pool.clear();

    // 再次分配
    _ = try pool.alloc(50, 1);

    const stats_after = pool.getStats();

    // 小块应该被重用，大块应该被释放
    try testing.expect(stats_after.big_blocks_count < stats_before.big_blocks_count);
}

test "MemoryPoolAllocator" {
    var pool = MemoryPool.init(testing.allocator);
    defer pool.deinit();

    var pool_allocator = MemoryPoolAllocator{ .pool = &pool };
    const allocator = pool_allocator.allocator();

    // 使用分配器接口
    const memory = try allocator.alloc(u8, 100);
    try testing.expect(memory.len == 100);

    // 释放（实际上不做任何事情）
    allocator.free(memory);
}
