const std = @import("std");
const Allocator = std.mem.Allocator;
const testing = std.testing;

/// 动态位集合
pub const BitSet = struct {
    data: []u64,
    bit_count: usize,
    allocator: Allocator,

    const BITS_PER_WORD = 64;
    const WORD_SHIFT = 6; // log2(64)
    const WORD_MASK = 63; // 64 - 1

    /// 初始化位集合
    pub fn init(allocator: Allocator, bit_count: usize) !BitSet {
        const word_count = (bit_count + BITS_PER_WORD - 1) / BITS_PER_WORD;
        const data = try allocator.alloc(u64, word_count);
        @memset(data, 0);

        return BitSet{
            .data = data,
            .bit_count = bit_count,
            .allocator = allocator,
        };
    }

    /// 释放位集合
    pub fn deinit(self: *BitSet) void {
        self.allocator.free(self.data);
        self.* = undefined;
    }

    /// 获取位数
    pub fn len(self: *const BitSet) usize {
        return self.bit_count;
    }

    /// 获取字数
    pub fn wordCount(self: *const BitSet) usize {
        return self.data.len;
    }

    /// 检查索引是否有效
    fn isValidIndex(self: *const BitSet, index: usize) bool {
        return index < self.bit_count;
    }

    /// 获取字索引和位偏移
    fn getWordAndBit(index: usize) struct { word: usize, bit: u6 } {
        return .{
            .word = index >> WORD_SHIFT,
            .bit = @intCast(index & WORD_MASK),
        };
    }

    /// 设置位
    pub fn set(self: *BitSet, index: usize) !void {
        if (!self.isValidIndex(index)) return error.IndexOutOfBounds;

        const pos = getWordAndBit(index);
        self.data[pos.word] |= (@as(u64, 1) << pos.bit);
    }

    /// 清除位
    pub fn unset(self: *BitSet, index: usize) !void {
        if (!self.isValidIndex(index)) return error.IndexOutOfBounds;

        const pos = getWordAndBit(index);
        self.data[pos.word] &= ~(@as(u64, 1) << pos.bit);
    }

    /// 切换位
    pub fn toggle(self: *BitSet, index: usize) !void {
        if (!self.isValidIndex(index)) return error.IndexOutOfBounds;

        const pos = getWordAndBit(index);
        self.data[pos.word] ^= (@as(u64, 1) << pos.bit);
    }

    /// 检查位是否设置
    pub fn isSet(self: *const BitSet, index: usize) !bool {
        if (!self.isValidIndex(index)) return error.IndexOutOfBounds;

        const pos = getWordAndBit(index);
        return (self.data[pos.word] & (@as(u64, 1) << pos.bit)) != 0;
    }

    /// 设置所有位
    pub fn setAll(self: *BitSet) void {
        @memset(self.data, std.math.maxInt(u64));

        // 清除超出范围的位
        const last_word_bits = self.bit_count & WORD_MASK;
        if (last_word_bits != 0 and self.data.len > 0) {
            const mask = (@as(u64, 1) << @intCast(last_word_bits)) - 1;
            self.data[self.data.len - 1] &= mask;
        }
    }

    /// 清除所有位
    pub fn clearAll(self: *BitSet) void {
        @memset(self.data, 0);
    }

    /// 设置范围内的位
    pub fn setRange(self: *BitSet, start: usize, end: usize) !void {
        if (start > end or end > self.bit_count) return error.IndexOutOfBounds;

        for (start..end) |i| {
            try self.set(i);
        }
    }

    /// 清除范围内的位
    pub fn clearRange(self: *BitSet, start: usize, end: usize) !void {
        if (start > end or end > self.bit_count) return error.IndexOutOfBounds;

        for (start..end) |i| {
            try self.unset(i);
        }
    }

    /// 计算设置的位数
    pub fn popCount(self: *const BitSet) usize {
        var count: usize = 0;
        for (self.data) |word| {
            count += @popCount(word);
        }
        return count;
    }

    /// 检查是否为空（所有位都是0）
    pub fn isEmpty(self: *const BitSet) bool {
        for (self.data) |word| {
            if (word != 0) return false;
        }
        return true;
    }

    /// 检查是否全满（所有位都是1）
    pub fn isFull(self: *const BitSet) bool {
        // 检查完整的字
        const full_words = self.bit_count / BITS_PER_WORD;
        for (self.data[0..full_words]) |word| {
            if (word != std.math.maxInt(u64)) return false;
        }

        // 检查最后一个不完整的字
        const remaining_bits = self.bit_count % BITS_PER_WORD;
        if (remaining_bits > 0 and self.data.len > full_words) {
            const mask = (@as(u64, 1) << @intCast(remaining_bits)) - 1;
            if ((self.data[full_words] & mask) != mask) return false;
        }

        return true;
    }

    /// 查找第一个设置的位
    pub fn findFirstSet(self: *const BitSet) ?usize {
        for (self.data, 0..) |word, word_index| {
            if (word != 0) {
                const bit_offset = @ctz(word);
                const bit_index = word_index * BITS_PER_WORD + bit_offset;
                if (bit_index < self.bit_count) {
                    return bit_index;
                }
            }
        }
        return null;
    }

    /// 查找第一个未设置的位
    pub fn findFirstUnset(self: *const BitSet) ?usize {
        for (self.data, 0..) |word, word_index| {
            if (word != std.math.maxInt(u64)) {
                const inverted = ~word;
                const bit_offset = @ctz(inverted);
                const bit_index = word_index * BITS_PER_WORD + bit_offset;
                if (bit_index < self.bit_count) {
                    return bit_index;
                }
            }
        }
        return null;
    }

    /// 查找下一个设置的位
    pub fn findNextSet(self: *const BitSet, start: usize) ?usize {
        const next_start = start + 1;
        if (next_start >= self.bit_count) return null;

        const start_pos = getWordAndBit(next_start);

        // 检查起始字的剩余部分
        if (start_pos.word < self.data.len) {
            const mask = ~((@as(u64, 1) << start_pos.bit) - 1);
            const masked_word = self.data[start_pos.word] & mask;
            if (masked_word != 0) {
                const bit_offset = @ctz(masked_word);
                const bit_index = start_pos.word * BITS_PER_WORD + bit_offset;
                if (bit_index < self.bit_count) {
                    return bit_index;
                }
            }
        }

        // 检查后续的字
        for (self.data[start_pos.word + 1 ..], start_pos.word + 1..) |word, word_index| {
            if (word != 0) {
                const bit_offset = @ctz(word);
                const bit_index = word_index * BITS_PER_WORD + bit_offset;
                if (bit_index < self.bit_count) {
                    return bit_index;
                }
            }
        }

        return null;
    }

    /// 位运算：与
    pub fn bitwiseAnd(self: *BitSet, other: *const BitSet) !void {
        if (self.bit_count != other.bit_count) return error.SizeMismatch;

        for (self.data, other.data) |*self_word, other_word| {
            self_word.* &= other_word;
        }
    }

    /// 位运算：或
    pub fn bitwiseOr(self: *BitSet, other: *const BitSet) !void {
        if (self.bit_count != other.bit_count) return error.SizeMismatch;

        for (self.data, other.data) |*self_word, other_word| {
            self_word.* |= other_word;
        }
    }

    /// 位运算：异或
    pub fn bitwiseXor(self: *BitSet, other: *const BitSet) !void {
        if (self.bit_count != other.bit_count) return error.SizeMismatch;

        for (self.data, other.data) |*self_word, other_word| {
            self_word.* ^= other_word;
        }
    }

    /// 位运算：非
    pub fn bitwiseNot(self: *BitSet) void {
        for (self.data) |*word| {
            word.* = ~word.*;
        }

        // 清除超出范围的位
        const last_word_bits = self.bit_count & WORD_MASK;
        if (last_word_bits != 0 and self.data.len > 0) {
            const mask = (@as(u64, 1) << @intCast(last_word_bits)) - 1;
            self.data[self.data.len - 1] &= mask;
        }
    }

    /// 检查是否与另一个位集合相交
    pub fn intersects(self: *const BitSet, other: *const BitSet) !bool {
        if (self.bit_count != other.bit_count) return error.SizeMismatch;

        for (self.data, other.data) |self_word, other_word| {
            if ((self_word & other_word) != 0) {
                return true;
            }
        }

        return false;
    }

    /// 检查是否包含另一个位集合
    pub fn contains(self: *const BitSet, other: *const BitSet) !bool {
        if (self.bit_count != other.bit_count) return error.SizeMismatch;

        for (self.data, other.data) |self_word, other_word| {
            if ((self_word & other_word) != other_word) {
                return false;
            }
        }

        return true;
    }

    /// 检查是否相等
    pub fn equals(self: *const BitSet, other: *const BitSet) bool {
        if (self.bit_count != other.bit_count) return false;

        for (self.data, other.data) |self_word, other_word| {
            if (self_word != other_word) {
                return false;
            }
        }

        return true;
    }

    /// 克隆位集合
    pub fn clone(self: *const BitSet) !BitSet {
        const new_bitset = try BitSet.init(self.allocator, self.bit_count);
        @memcpy(new_bitset.data, self.data);
        return new_bitset;
    }

    /// 调整大小
    pub fn resize(self: *BitSet, new_bit_count: usize) !void {
        const new_word_count = (new_bit_count + BITS_PER_WORD - 1) / BITS_PER_WORD;

        if (new_word_count != self.data.len) {
            self.data = try self.allocator.realloc(self.data, new_word_count);

            // 如果扩大了，初始化新的字为0
            if (new_word_count > self.data.len) {
                @memset(self.data[self.data.len..], 0);
            }
        }

        self.bit_count = new_bit_count;

        // 清除超出范围的位
        const last_word_bits = self.bit_count & WORD_MASK;
        if (last_word_bits != 0 and self.data.len > 0) {
            const mask = (@as(u64, 1) << @intCast(last_word_bits)) - 1;
            self.data[self.data.len - 1] &= mask;
        }
    }

    /// 迭代器
    pub const Iterator = struct {
        bitset: *const BitSet,
        current_index: usize,

        pub fn next(self: *Iterator) ?usize {
            if (self.current_index >= self.bitset.bit_count) return null;

            if (self.bitset.findNextSet(self.current_index)) |index| {
                self.current_index = index + 1;
                return index;
            }

            return null;
        }
    };

    /// 获取设置位的迭代器
    pub fn iterator(self: *const BitSet) Iterator {
        return Iterator{
            .bitset = self,
            .current_index = 0,
        };
    }

    /// 转换为字符串（用于调试）
    pub fn toString(self: *const BitSet, allocator: Allocator) ![]u8 {
        var result = try allocator.alloc(u8, self.bit_count);

        for (0..self.bit_count) |i| {
            result[i] = if (try self.isSet(i)) '1' else '0';
        }

        return result;
    }
};

test "BitSet basic operations" {
    var bitset = try BitSet.init(testing.allocator, 100);
    defer bitset.deinit();

    try testing.expect(bitset.len() == 100);
    try testing.expect(bitset.isEmpty());
    try testing.expect(bitset.popCount() == 0);

    // 设置一些位
    try bitset.set(0);
    try bitset.set(10);
    try bitset.set(50);
    try bitset.set(99);

    try testing.expect(!bitset.isEmpty());
    try testing.expect(bitset.popCount() == 4);
    try testing.expect(try bitset.isSet(0));
    try testing.expect(try bitset.isSet(10));
    try testing.expect(try bitset.isSet(50));
    try testing.expect(try bitset.isSet(99));
    try testing.expect(!try bitset.isSet(1));

    // 清除位
    try bitset.unset(10);
    try testing.expect(!try bitset.isSet(10));
    try testing.expect(bitset.popCount() == 3);

    // 切换位
    try bitset.toggle(10);
    try testing.expect(try bitset.isSet(10));
    try bitset.toggle(10);
    try testing.expect(!try bitset.isSet(10));
}

test "BitSet range operations" {
    var bitset = try BitSet.init(testing.allocator, 64);
    defer bitset.deinit();

    try bitset.setRange(10, 20);
    try testing.expect(bitset.popCount() == 10);

    for (10..20) |i| {
        try testing.expect(try bitset.isSet(i));
    }

    try bitset.clearRange(15, 20);
    try testing.expect(bitset.popCount() == 5);

    for (10..15) |i| {
        try testing.expect(try bitset.isSet(i));
    }
    for (15..20) |i| {
        try testing.expect(!try bitset.isSet(i));
    }
}

test "BitSet find operations" {
    var bitset = try BitSet.init(testing.allocator, 100);
    defer bitset.deinit();

    try bitset.set(5);
    try bitset.set(25);
    try bitset.set(75);

    try testing.expect(bitset.findFirstSet().? == 5);
    try testing.expect(bitset.findNextSet(5).? == 25);
    try testing.expect(bitset.findNextSet(25).? == 75);
    try testing.expect(bitset.findNextSet(75) == null);

    try testing.expect(bitset.findFirstUnset().? == 0);
}

test "BitSet bitwise operations" {
    var bitset1 = try BitSet.init(testing.allocator, 64);
    defer bitset1.deinit();
    var bitset2 = try BitSet.init(testing.allocator, 64);
    defer bitset2.deinit();

    try bitset1.set(0);
    try bitset1.set(10);
    try bitset1.set(20);

    try bitset2.set(10);
    try bitset2.set(20);
    try bitset2.set(30);

    // 测试相交
    try testing.expect(try bitset1.intersects(&bitset2));

    // 测试或运算
    try bitset1.bitwiseOr(&bitset2);
    try testing.expect(try bitset1.isSet(0));
    try testing.expect(try bitset1.isSet(10));
    try testing.expect(try bitset1.isSet(20));
    try testing.expect(try bitset1.isSet(30));
    try testing.expect(bitset1.popCount() == 4);
}

test "BitSet iterator" {
    var bitset = try BitSet.init(testing.allocator, 100);
    defer bitset.deinit();

    try bitset.set(5);
    try bitset.set(15);
    try bitset.set(25);

    var iter = bitset.iterator();
    try testing.expect(iter.next().? == 5);
    try testing.expect(iter.next().? == 15);
    try testing.expect(iter.next().? == 25);
    try testing.expect(iter.next() == null);
}
