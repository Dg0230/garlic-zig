const std = @import("std");
const Allocator = std.mem.Allocator;
const testing = std.testing;
const memory = @import("memory.zig");
const list = @import("list.zig");

/// 可变字符串
pub const MutableString = struct {
    data: []u8,
    len: usize,
    capacity: usize,
    allocator: Allocator,

    const INITIAL_CAPACITY = 16;

    /// 初始化空字符串
    pub fn init(allocator: Allocator) !MutableString {
        const data = try allocator.alloc(u8, INITIAL_CAPACITY);
        return MutableString{
            .data = data,
            .len = 0,
            .capacity = INITIAL_CAPACITY,
            .allocator = allocator,
        };
    }

    /// 从字符串初始化
    pub fn initFromString(allocator: Allocator, str: []const u8) !MutableString {
        const capacity = @max(str.len, INITIAL_CAPACITY);
        const data = try allocator.alloc(u8, capacity);
        @memcpy(data[0..str.len], str);

        return MutableString{
            .data = data,
            .len = str.len,
            .capacity = capacity,
            .allocator = allocator,
        };
    }

    /// 初始化指定容量的字符串
    pub fn initCapacity(allocator: Allocator, capacity: usize) !MutableString {
        const data = try allocator.alloc(u8, capacity);
        return MutableString{
            .data = data,
            .len = 0,
            .capacity = capacity,
            .allocator = allocator,
        };
    }

    /// 释放字符串
    pub fn deinit(self: *MutableString) void {
        self.allocator.free(self.data);
        self.* = undefined;
    }

    /// 获取字符串长度
    pub fn length(self: *const MutableString) usize {
        return self.len;
    }

    /// 检查字符串是否为空
    pub fn isEmpty(self: *const MutableString) bool {
        return self.len == 0;
    }

    /// 获取字符串切片
    pub fn slice(self: *const MutableString) []const u8 {
        return self.data[0..self.len];
    }

    /// 获取可变字符串切片
    pub fn sliceMut(self: *MutableString) []u8 {
        return self.data[0..self.len];
    }

    /// 确保容量
    pub fn ensureCapacity(self: *MutableString, new_capacity: usize) !void {
        if (new_capacity <= self.capacity) return;

        const actual_capacity = std.math.ceilPowerOfTwo(usize, new_capacity) catch new_capacity;
        self.data = try self.allocator.realloc(self.data, actual_capacity);
        self.capacity = actual_capacity;
    }

    /// 追加字符
    pub fn appendChar(self: *MutableString, char: u8) !void {
        try self.ensureCapacity(self.len + 1);
        self.data[self.len] = char;
        self.len += 1;
    }

    /// 追加字符串
    pub fn append(self: *MutableString, str: []const u8) !void {
        try self.ensureCapacity(self.len + str.len);
        @memcpy(self.data[self.len .. self.len + str.len], str);
        self.len += str.len;
    }

    /// 追加格式化字符串
    pub fn appendFmt(self: *MutableString, comptime fmt: []const u8, args: anytype) !void {
        const formatted = try std.fmt.allocPrint(self.allocator, fmt, args);
        defer self.allocator.free(formatted);
        try self.append(formatted);
    }

    /// 插入字符
    pub fn insertChar(self: *MutableString, index: usize, char: u8) !void {
        if (index > self.len) return error.IndexOutOfBounds;

        try self.ensureCapacity(self.len + 1);

        // 移动后面的字符
        if (index < self.len) {
            std.mem.copyBackwards(u8, self.data[index + 1 .. self.len + 1], self.data[index..self.len]);
        }

        self.data[index] = char;
        self.len += 1;
    }

    /// 插入字符串
    pub fn insert(self: *MutableString, index: usize, str: []const u8) !void {
        if (index > self.len) return error.IndexOutOfBounds;

        try self.ensureCapacity(self.len + str.len);

        // 移动后面的字符
        if (index < self.len) {
            std.mem.copyBackwards(u8, self.data[index + str.len .. self.len + str.len], self.data[index..self.len]);
        }

        @memcpy(self.data[index .. index + str.len], str);
        self.len += str.len;
    }

    /// 删除字符
    pub fn removeChar(self: *MutableString, index: usize) !void {
        if (index >= self.len) return error.IndexOutOfBounds;

        // 移动后面的字符
        if (index < self.len - 1) {
            std.mem.copyForwards(u8, self.data[index .. self.len - 1], self.data[index + 1 .. self.len]);
        }

        self.len -= 1;
    }

    /// 删除范围
    pub fn removeRange(self: *MutableString, start: usize, end: usize) !void {
        if (start > end or end > self.len) return error.IndexOutOfBounds;

        const remove_len = end - start;
        if (remove_len == 0) return;

        // 移动后面的字符
        if (end < self.len) {
            std.mem.copyForwards(u8, self.data[start .. self.len - remove_len], self.data[end..self.len]);
        }

        self.len -= remove_len;
    }

    /// 清空字符串
    pub fn clear(self: *MutableString) void {
        self.len = 0;
    }

    /// 获取字符
    pub fn charAt(self: *const MutableString, index: usize) !u8 {
        if (index >= self.len) return error.IndexOutOfBounds;
        return self.data[index];
    }

    /// 设置字符
    pub fn setChar(self: *MutableString, index: usize, char: u8) !void {
        if (index >= self.len) return error.IndexOutOfBounds;
        self.data[index] = char;
    }

    /// 子字符串
    pub fn substring(self: *const MutableString, start: usize, end: usize) ![]const u8 {
        if (start > end or end > self.len) return error.IndexOutOfBounds;
        return self.data[start..end];
    }

    /// 查找字符
    pub fn indexOf(self: *const MutableString, char: u8) ?usize {
        return std.mem.indexOfScalar(u8, self.slice(), char);
    }

    /// 查找字符串
    pub fn indexOfString(self: *const MutableString, str: []const u8) ?usize {
        return std.mem.indexOf(u8, self.slice(), str);
    }

    /// 最后出现位置
    pub fn lastIndexOf(self: *const MutableString, char: u8) ?usize {
        return std.mem.lastIndexOfScalar(u8, self.slice(), char);
    }

    /// 检查是否包含
    pub fn contains(self: *const MutableString, str: []const u8) bool {
        return self.indexOfString(str) != null;
    }

    /// 检查是否以指定字符串开头
    pub fn startsWith(self: *const MutableString, prefix: []const u8) bool {
        return std.mem.startsWith(u8, self.slice(), prefix);
    }

    /// 检查是否以指定字符串结尾
    pub fn endsWith(self: *const MutableString, suffix: []const u8) bool {
        return std.mem.endsWith(u8, self.slice(), suffix);
    }

    /// 转换为小写
    pub fn toLower(self: *MutableString) void {
        for (self.data[0..self.len]) |*char| {
            char.* = std.ascii.toLower(char.*);
        }
    }

    /// 转换为大写
    pub fn toUpper(self: *MutableString) void {
        for (self.data[0..self.len]) |*char| {
            char.* = std.ascii.toUpper(char.*);
        }
    }

    /// 去除首尾空白
    pub fn trim(self: *MutableString) void {
        const trimmed = std.mem.trim(u8, self.slice(), " \t\n\r");
        const start_offset = @intFromPtr(trimmed.ptr) - @intFromPtr(self.data.ptr);

        if (start_offset > 0) {
            std.mem.copyForwards(u8, self.data[0..trimmed.len], trimmed);
        }

        self.len = trimmed.len;
    }

    /// 替换字符
    pub fn replaceChar(self: *MutableString, old_char: u8, new_char: u8) void {
        for (self.data[0..self.len]) |*char| {
            if (char.* == old_char) {
                char.* = new_char;
            }
        }
    }

    /// 克隆字符串
    pub fn clone(self: *const MutableString) !MutableString {
        return MutableString.initFromString(self.allocator, self.slice());
    }

    /// 转换为拥有的字符串
    pub fn toOwnedSlice(self: *MutableString) ![]u8 {
        const result = try self.allocator.alloc(u8, self.len);
        @memcpy(result, self.slice());
        return result;
    }
};

/// 字符串工具函数
pub const StringUtils = struct {
    /// 比较字符串（忽略大小写）
    pub fn equalsIgnoreCase(a: []const u8, b: []const u8) bool {
        if (a.len != b.len) return false;

        for (a, b) |char_a, char_b| {
            if (std.ascii.toLower(char_a) != std.ascii.toLower(char_b)) {
                return false;
            }
        }

        return true;
    }

    /// 分割字符串
    pub fn split(allocator: Allocator, str: []const u8, delimiter: []const u8) ![][]const u8 {
        var result = list.List([]const u8).init(allocator);
        defer result.deinit();

        var iterator = std.mem.splitSequence(u8, str, delimiter);
        while (iterator.next()) |part| {
            try result.append(part);
        }

        return result.toOwnedSlice(allocator);
    }

    /// 连接字符串
    pub fn join(allocator: Allocator, strings: []const []const u8, separator: []const u8) ![]u8 {
        if (strings.len == 0) return try allocator.dupe(u8, "");
        if (strings.len == 1) return try allocator.dupe(u8, strings[0]);

        var total_len: usize = 0;
        for (strings) |str| {
            total_len += str.len;
        }
        total_len += separator.len * (strings.len - 1);

        var result = try allocator.alloc(u8, total_len);
        var pos: usize = 0;

        for (strings, 0..) |str, i| {
            @memcpy(result[pos .. pos + str.len], str);
            pos += str.len;

            if (i < strings.len - 1) {
                @memcpy(result[pos .. pos + separator.len], separator);
                pos += separator.len;
            }
        }

        return result;
    }

    /// 重复字符串
    pub fn repeat(allocator: Allocator, str: []const u8, count: usize) ![]u8 {
        if (count == 0) return try allocator.dupe(u8, "");
        if (count == 1) return try allocator.dupe(u8, str);

        const result = try allocator.alloc(u8, str.len * count);
        for (0..count) |i| {
            const start = i * str.len;
            @memcpy(result[start .. start + str.len], str);
        }

        return result;
    }

    /// 填充字符串（左侧）
    pub fn padLeft(allocator: Allocator, str: []const u8, total_len: usize, pad_char: u8) ![]u8 {
        if (str.len >= total_len) return try allocator.dupe(u8, str);

        const result = try allocator.alloc(u8, total_len);
        const pad_len = total_len - str.len;

        @memset(result[0..pad_len], pad_char);
        @memcpy(result[pad_len..], str);

        return result;
    }

    /// 填充字符串（右侧）
    pub fn padRight(allocator: Allocator, str: []const u8, total_len: usize, pad_char: u8) ![]u8 {
        if (str.len >= total_len) return try allocator.dupe(u8, str);

        const result = try allocator.alloc(u8, total_len);
        const pad_len = total_len - str.len;
        _ = pad_len; // 用于标记变量已使用

        @memcpy(result[0..str.len], str);
        @memset(result[str.len..], pad_char);

        return result;
    }

    /// 反转字符串
    pub fn reverse(allocator: Allocator, str: []const u8) ![]u8 {
        const result = try allocator.alloc(u8, str.len);
        for (str, 0..) |char, i| {
            result[str.len - 1 - i] = char;
        }
        return result;
    }

    /// 检查是否为数字字符串
    pub fn isNumeric(str: []const u8) bool {
        if (str.len == 0) return false;

        for (str) |char| {
            if (!std.ascii.isDigit(char)) {
                return false;
            }
        }

        return true;
    }

    /// 检查是否为字母字符串
    pub fn isAlpha(str: []const u8) bool {
        if (str.len == 0) return false;

        for (str) |char| {
            if (!std.ascii.isAlphabetic(char)) {
                return false;
            }
        }

        return true;
    }

    /// 检查是否为字母数字字符串
    pub fn isAlphaNumeric(str: []const u8) bool {
        if (str.len == 0) return false;

        for (str) |char| {
            if (!std.ascii.isAlphanumeric(char)) {
                return false;
            }
        }

        return true;
    }
};

test "MutableString basic operations" {
    var str = try MutableString.init(testing.allocator);
    defer str.deinit();

    try testing.expect(str.isEmpty());
    try testing.expect(str.length() == 0);

    try str.append("Hello");
    try testing.expect(!str.isEmpty());
    try testing.expect(str.length() == 5);
    try testing.expect(std.mem.eql(u8, str.slice(), "Hello"));

    try str.appendChar(' ');
    try str.append("World");
    try testing.expect(std.mem.eql(u8, str.slice(), "Hello World"));
}

test "MutableString insert and remove" {
    var str = try MutableString.initFromString(testing.allocator, "Hello World");
    defer str.deinit();

    try str.insert(5, ", Beautiful");
    try testing.expect(std.mem.eql(u8, str.slice(), "Hello, Beautiful World"));

    try str.removeRange(5, 16);
    try testing.expect(std.mem.eql(u8, str.slice(), "Hello World"));

    try str.removeChar(5);
    try testing.expect(std.mem.eql(u8, str.slice(), "HelloWorld"));
}

test "MutableString search operations" {
    var str = try MutableString.initFromString(testing.allocator, "Hello World Hello");
    defer str.deinit();

    try testing.expect(str.indexOf('o').? == 4);
    try testing.expect(str.lastIndexOf('o').? == 16);
    try testing.expect(str.indexOfString("World").? == 6);
    try testing.expect(str.contains("World"));
    try testing.expect(!str.contains("world"));
    try testing.expect(str.startsWith("Hello"));
    try testing.expect(str.endsWith("Hello"));
}

test "MutableString case operations" {
    var str = try MutableString.initFromString(testing.allocator, "Hello World");
    defer str.deinit();

    str.toLower();
    try testing.expect(std.mem.eql(u8, str.slice(), "hello world"));

    str.toUpper();
    try testing.expect(std.mem.eql(u8, str.slice(), "HELLO WORLD"));
}

test "StringUtils split and join" {
    const parts = try StringUtils.split(testing.allocator, "a,b,c,d", ",");
    defer testing.allocator.free(parts);

    try testing.expect(parts.len == 4);
    try testing.expect(std.mem.eql(u8, parts[0], "a"));
    try testing.expect(std.mem.eql(u8, parts[3], "d"));

    const joined = try StringUtils.join(testing.allocator, parts, "|");
    defer testing.allocator.free(joined);

    try testing.expect(std.mem.eql(u8, joined, "a|b|c|d"));
}

test "StringUtils utility functions" {
    try testing.expect(StringUtils.equalsIgnoreCase("Hello", "HELLO"));
    try testing.expect(!StringUtils.equalsIgnoreCase("Hello", "World"));

    const repeated = try StringUtils.repeat(testing.allocator, "abc", 3);
    defer testing.allocator.free(repeated);
    try testing.expect(std.mem.eql(u8, repeated, "abcabcabc"));

    const padded = try StringUtils.padLeft(testing.allocator, "123", 6, '0');
    defer testing.allocator.free(padded);
    try testing.expect(std.mem.eql(u8, padded, "000123"));

    try testing.expect(StringUtils.isNumeric("12345"));
    try testing.expect(!StringUtils.isNumeric("123a5"));
    try testing.expect(StringUtils.isAlpha("abcde"));
    try testing.expect(!StringUtils.isAlpha("abc1e"));
}
