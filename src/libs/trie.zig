const std = @import("std");
const Allocator = std.mem.Allocator;
const testing = std.testing;
const list = @import("list.zig");

/// 字典树节点
const TrieNode = struct {
    children: [256]?*TrieNode, // 支持所有ASCII字符
    is_end: bool,
    value: ?*anyopaque, // 可选的关联值

    /// 初始化节点
    pub fn init() TrieNode {
        return TrieNode{
            .children = [_]?*TrieNode{null} ** 256,
            .is_end = false,
            .value = null,
        };
    }
};

/// 字典树
pub const Trie = struct {
    root: *TrieNode,
    size: usize,
    allocator: Allocator,

    /// 初始化字典树
    pub fn init(allocator: Allocator) !Trie {
        const root = try allocator.create(TrieNode);
        root.* = TrieNode.init();

        return Trie{
            .root = root,
            .size = 0,
            .allocator = allocator,
        };
    }

    /// 释放字典树
    pub fn deinit(self: *Trie) void {
        self.freeNode(self.root);
        self.* = undefined;
    }

    /// 递归释放节点
    fn freeNode(self: *Trie, node: *TrieNode) void {
        for (node.children) |child| {
            if (child) |c| {
                self.freeNode(c);
            }
        }
        self.allocator.destroy(node);
    }

    /// 获取字典树大小
    pub fn len(self: *const Trie) usize {
        return self.size;
    }

    /// 检查字典树是否为空
    pub fn isEmpty(self: *const Trie) bool {
        return self.size == 0;
    }

    /// 插入字符串
    pub fn insert(self: *Trie, word: []const u8) !void {
        var current = self.root;

        for (word) |char| {
            const index = char;

            if (current.children[index] == null) {
                const new_node = try self.allocator.create(TrieNode);
                new_node.* = TrieNode.init();
                current.children[index] = new_node;
            }

            current = current.children[index].?;
        }

        if (!current.is_end) {
            current.is_end = true;
            self.size += 1;
        }
    }

    /// 插入字符串并关联值
    pub fn insertWithValue(self: *Trie, word: []const u8, value: *anyopaque) !void {
        var current = self.root;

        for (word) |char| {
            const index = char;

            if (current.children[index] == null) {
                const new_node = try self.allocator.create(TrieNode);
                new_node.* = TrieNode.init();
                current.children[index] = new_node;
            }

            current = current.children[index].?;
        }

        if (!current.is_end) {
            self.size += 1;
        }

        current.is_end = true;
        current.value = value;
    }

    /// 查找字符串
    pub fn search(self: *const Trie, word: []const u8) bool {
        const node = self.findNode(word);
        return node != null and node.?.is_end;
    }

    /// 查找字符串并返回关联值
    pub fn searchWithValue(self: *const Trie, word: []const u8) ?*anyopaque {
        const node = self.findNode(word);
        if (node != null and node.?.is_end) {
            return node.?.value;
        }
        return null;
    }

    /// 检查是否存在以指定前缀开头的字符串
    pub fn startsWith(self: *const Trie, prefix: []const u8) bool {
        return self.findNode(prefix) != null;
    }

    /// 查找节点
    fn findNode(self: *const Trie, word: []const u8) ?*TrieNode {
        var current = self.root;

        for (word) |char| {
            const index = char;

            if (current.children[index] == null) {
                return null;
            }

            current = current.children[index].?;
        }

        return current;
    }

    /// 删除字符串
    pub fn remove(self: *Trie, word: []const u8) bool {
        var found = false;
        _ = self.removeHelper(self.root, word, 0, &found);
        return found;
    }

    /// 删除辅助函数
    fn removeHelper(self: *Trie, node: *TrieNode, word: []const u8, index: usize, found: *bool) bool {
        if (index == word.len) {
            if (!node.is_end) {
                return false; // 字符串不存在
            }

            node.is_end = false;
            node.value = null;
            self.size -= 1;
            found.* = true;

            // 检查是否可以删除节点
            return !self.hasChildren(node);
        }

        const char = word[index];
        const child = node.children[char];

        if (child == null) {
            return false; // 字符串不存在
        }

        const should_delete_child = self.removeHelper(child.?, word, index + 1, found);

        if (should_delete_child) {
            self.allocator.destroy(child.?);
            node.children[char] = null;

            // 如果当前节点不是单词结尾且没有其他子节点，可以删除
            return !node.is_end and !self.hasChildren(node);
        }

        return false;
    }

    /// 检查节点是否有子节点
    fn hasChildren(self: *const Trie, node: *const TrieNode) bool {
        _ = self;
        for (node.children) |child| {
            if (child != null) {
                return true;
            }
        }
        return false;
    }

    /// 获取所有以指定前缀开头的字符串
    pub fn getWordsWithPrefix(self: *const Trie, allocator: Allocator, prefix: []const u8) ![][]u8 {
        var result = list.List([]u8).init(allocator);
        defer result.deinit();

        const prefix_node = self.findNode(prefix);
        if (prefix_node == null) {
            return try result.toOwnedSlice(self.allocator);
        }

        var current_word = try allocator.alloc(u8, prefix.len + 100); // 预分配空间
        defer allocator.free(current_word);
        @memcpy(current_word[0..prefix.len], prefix);

        try self.collectWords(allocator, prefix_node.?, current_word, prefix.len, &result);

        return try result.toOwnedSlice(self.allocator);
    }

    /// 收集所有单词
    fn collectWords(self: *const Trie, allocator: Allocator, node: *TrieNode, word_buffer: []u8, current_len: usize, result: *list.List([]u8)) !void {
        if (node.is_end) {
            const word = try allocator.dupe(u8, word_buffer[0..current_len]);
            try result.append(word);
        }

        for (node.children, 0..) |child, i| {
            if (child) |c| {
                if (current_len < word_buffer.len) {
                    word_buffer[current_len] = @intCast(i);
                    try self.collectWords(allocator, c, word_buffer, current_len + 1, result);
                }
            }
        }
    }

    /// 获取所有字符串
    pub fn getAllWords(self: *const Trie, allocator: Allocator) ![][]u8 {
        var result = list.List([]u8).init(allocator);
        defer result.deinit();

        const word_buffer = try allocator.alloc(u8, 1000); // 预分配缓冲区
        defer allocator.free(word_buffer);

        try self.collectWords(allocator, self.root, word_buffer, 0, &result);

        return try result.toOwnedSlice(self.allocator);
    }

    /// 清空字典树
    pub fn clear(self: *Trie) void {
        // 释放所有子节点
        for (self.root.children) |child| {
            if (child) |c| {
                self.freeNode(c);
            }
        }

        // 重新初始化根节点
        self.root.* = TrieNode.init();
        self.size = 0;
    }

    /// 获取最长公共前缀
    pub fn longestCommonPrefix(self: *const Trie, allocator: Allocator) ![]u8 {
        var result = list.List(u8).init(allocator);
        defer result.deinit();

        var current = self.root;

        while (true) {
            var child_count: usize = 0;
            var next_char: u8 = 0;
            var next_node: ?*TrieNode = null;

            // 计算子节点数量
            for (current.children, 0..) |child, i| {
                if (child != null) {
                    child_count += 1;
                    next_char = @intCast(i);
                    next_node = child;
                }
            }

            // 如果有多个子节点或当前节点是单词结尾，停止
            if (child_count != 1 or current.is_end) {
                break;
            }

            try result.append(next_char);
            current = next_node.?;
        }

        return try result.toOwnedSlice(self.allocator);
    }

    /// 自动补全
    pub fn autoComplete(self: *const Trie, allocator: Allocator, prefix: []const u8, max_suggestions: usize) ![][]u8 {
        var result = list.List([]u8).init(allocator);
        defer result.deinit();

        const prefix_node = self.findNode(prefix);
        if (prefix_node == null) {
            return try result.toOwnedSlice(self.allocator);
        }

        var word_buffer = try allocator.alloc(u8, prefix.len + 100);
        defer allocator.free(word_buffer);
        @memcpy(word_buffer[0..prefix.len], prefix);

        try self.collectWordsLimited(allocator, prefix_node.?, word_buffer, prefix.len, &result, max_suggestions);

        return try result.toOwnedSlice(self.allocator);
    }

    /// 收集有限数量的单词
    fn collectWordsLimited(self: *const Trie, allocator: Allocator, node: *TrieNode, word_buffer: []u8, current_len: usize, result: *list.List([]u8), max_count: usize) !void {
        if (result.len() >= max_count) return;

        if (node.is_end) {
            const word = try allocator.dupe(u8, word_buffer[0..current_len]);
            try result.append(word);
            if (result.len() >= max_count) return;
        }

        for (node.children, 0..) |child, i| {
            if (child) |c| {
                if (current_len < word_buffer.len and result.len() < max_count) {
                    word_buffer[current_len] = @intCast(i);
                    try self.collectWordsLimited(allocator, c, word_buffer, current_len + 1, result, max_count);
                }
            }
        }
    }

    /// 模糊搜索（允许一定的编辑距离）
    pub fn fuzzySearch(self: *const Trie, allocator: Allocator, word: []const u8, max_distance: usize) ![][]u8 {
        var result = list.List([]u8).init(allocator);
        defer result.deinit();

        const word_buffer = try allocator.alloc(u8, word.len + max_distance + 10);
        defer allocator.free(word_buffer);

        try self.fuzzySearchHelper(allocator, self.root, word, word_buffer, 0, 0, max_distance, &result);

        return try result.toOwnedSlice(self.allocator);
    }

    /// 模糊搜索辅助函数
    fn fuzzySearchHelper(self: *const Trie, allocator: Allocator, node: *TrieNode, target: []const u8, word_buffer: []u8, word_len: usize, target_index: usize, remaining_distance: usize, result: *list.List([]u8)) !void {
        if (node.is_end and target_index == target.len) {
            const word = try allocator.dupe(u8, word_buffer[0..word_len]);
            try result.append(word);
            return;
        }

        if (remaining_distance == 0) {
            // 只能精确匹配剩余字符
            if (target_index < target.len) {
                const char = target[target_index];
                if (node.children[char]) |child| {
                    if (word_len < word_buffer.len) {
                        word_buffer[word_len] = char;
                        try self.fuzzySearchHelper(allocator, child, target, word_buffer, word_len + 1, target_index + 1, 0, result);
                    }
                }
            }
            return;
        }

        // 精确匹配
        if (target_index < target.len) {
            const char = target[target_index];
            if (node.children[char]) |child| {
                if (word_len < word_buffer.len) {
                    word_buffer[word_len] = char;
                    try self.fuzzySearchHelper(allocator, child, target, word_buffer, word_len + 1, target_index + 1, remaining_distance, result);
                }
            }
        }

        // 插入操作
        for (node.children, 0..) |child, i| {
            if (child) |c| {
                if (word_len < word_buffer.len) {
                    word_buffer[word_len] = @intCast(i);
                    try self.fuzzySearchHelper(allocator, c, target, word_buffer, word_len + 1, target_index, remaining_distance - 1, result);
                }
            }
        }

        // 删除操作
        if (target_index < target.len) {
            try self.fuzzySearchHelper(allocator, node, target, word_buffer, word_len, target_index + 1, remaining_distance - 1, result);
        }

        // 替换操作
        if (target_index < target.len) {
            for (node.children, 0..) |child, i| {
                if (child) |c| {
                    if (word_len < word_buffer.len) {
                        word_buffer[word_len] = @intCast(i);
                        try self.fuzzySearchHelper(allocator, c, target, word_buffer, word_len + 1, target_index + 1, remaining_distance - 1, result);
                    }
                }
            }
        }
    }
};

test "Trie basic operations" {
    var trie = try Trie.init(testing.allocator);
    defer trie.deinit();

    try testing.expect(trie.isEmpty());
    try testing.expect(trie.len() == 0);

    // 插入单词
    try trie.insert("hello");
    try trie.insert("world");
    try trie.insert("help");
    try trie.insert("hell");

    try testing.expect(!trie.isEmpty());
    try testing.expect(trie.len() == 4);

    // 搜索
    try testing.expect(trie.search("hello"));
    try testing.expect(trie.search("world"));
    try testing.expect(trie.search("help"));
    try testing.expect(trie.search("hell"));
    try testing.expect(!trie.search("he"));
    try testing.expect(!trie.search("helper"));

    // 前缀检查
    try testing.expect(trie.startsWith("he"));
    try testing.expect(trie.startsWith("hel"));
    try testing.expect(trie.startsWith("hello"));
    try testing.expect(!trie.startsWith("abc"));
}

test "Trie with values" {
    var trie = try Trie.init(testing.allocator);
    defer trie.deinit();

    var value1: i32 = 100;
    var value2: i32 = 200;

    try trie.insertWithValue("key1", &value1);
    try trie.insertWithValue("key2", &value2);

    const result1 = trie.searchWithValue("key1");
    const result2 = trie.searchWithValue("key2");

    try testing.expect(result1 != null);
    try testing.expect(result2 != null);

    const val1: *i32 = @ptrCast(@alignCast(result1.?));
    const val2: *i32 = @ptrCast(@alignCast(result2.?));

    try testing.expect(val1.* == 100);
    try testing.expect(val2.* == 200);
}

test "Trie remove operations" {
    var trie = try Trie.init(testing.allocator);
    defer trie.deinit();

    try trie.insert("hello");
    try trie.insert("help");
    try trie.insert("hell");

    try testing.expect(trie.len() == 3);

    // 删除单词
    try testing.expect(trie.remove("help"));
    try testing.expect(!trie.search("help"));
    try testing.expect(trie.search("hello"));
    try testing.expect(trie.search("hell"));
    try testing.expect(trie.len() == 2);

    // 删除不存在的单词
    try testing.expect(!trie.remove("world"));
    try testing.expect(trie.len() == 2);
}

test "Trie prefix operations" {
    var trie = try Trie.init(testing.allocator);
    defer trie.deinit();

    try trie.insert("hello");
    try trie.insert("help");
    try trie.insert("hell");
    try trie.insert("world");

    // 获取以"hel"开头的单词
    const words = try trie.getWordsWithPrefix(testing.allocator, "hel");
    defer {
        for (words) |word| {
            testing.allocator.free(word);
        }
        testing.allocator.free(words);
    }

    try testing.expect(words.len == 3);

    // 自动补全
    const suggestions = try trie.autoComplete(testing.allocator, "hel", 2);
    defer {
        for (suggestions) |word| {
            testing.allocator.free(word);
        }
        testing.allocator.free(suggestions);
    }

    try testing.expect(suggestions.len == 2);
}
