//! Java Class 文件常量池管理器
//! 负责管理和解析常量池中的各种常量类型，提供常量引用解析和字符串池管理功能

const std = @import("std");
const types = @import("../common/types.zig");
const bytecode = @import("bytecode.zig");
const Allocator = std.mem.Allocator;
const StringHashMap = std.StringHashMap;
const AutoHashMap = std.AutoHashMap;
const ArrayList = std.ArrayList;

/// 常量池条目类型（重新导出以便使用）
const ConstantPoolEntry = bytecode.ConstantPoolEntry;

/// 解析后的常量值
const ResolvedConstant = union(enum) {
    utf8_string: []const u8,
    integer: i32,
    float: f32,
    long: i64,
    double: f64,
    class_name: []const u8,
    string_literal: []const u8,
    field_ref: FieldReference,
    method_ref: MethodReference,
    interface_method_ref: MethodReference,
    name_and_type: NameAndType,
};

/// 字段引用信息
const FieldReference = struct {
    class_name: []const u8,
    field_name: []const u8,
    field_type: []const u8,
};

/// 方法引用信息
const MethodReference = struct {
    class_name: []const u8,
    method_name: []const u8,
    method_descriptor: []const u8,
};

/// 名称和类型信息
const NameAndType = struct {
    name: []const u8,
    descriptor: []const u8,
};

/// 常量池管理器
pub const ConstantPoolManager = struct {
    entries: []ConstantPoolEntry,
    resolved_cache: AutoHashMap(u16, ResolvedConstant),
    string_pool: StringHashMap([]const u8),
    allocator: Allocator,

    /// 创建常量池管理器
    pub fn init(entries: []ConstantPoolEntry, allocator: Allocator) !ConstantPoolManager {
        const resolved_cache = AutoHashMap(u16, ResolvedConstant).init(allocator);
        const string_pool = StringHashMap([]const u8).init(allocator);

        return ConstantPoolManager{
            .entries = entries,
            .resolved_cache = resolved_cache,
            .string_pool = string_pool,
            .allocator = allocator,
        };
    }

    /// 释放资源
    pub fn deinit(self: *ConstantPoolManager) void {
        // 释放 string_pool 中的字符串
        var iterator = self.string_pool.iterator();
        while (iterator.next()) |entry| {
            self.allocator.free(entry.value_ptr.*);
        }

        self.resolved_cache.deinit();
        self.string_pool.deinit();
    }

    /// 验证常量池索引是否有效
    fn isValidIndex(self: *const ConstantPoolManager, index: u16) bool {
        return index > 0 and index <= self.entries.len;
    }

    /// 获取原始常量池条目
    fn getRawEntry(self: *const ConstantPoolManager, index: u16) !ConstantPoolEntry {
        if (!self.isValidIndex(index)) {
            return error.InvalidConstantPoolIndex;
        }
        return self.entries[index - 1]; // 常量池索引从1开始
    }

    /// 获取 UTF-8 字符串
    pub fn getUtf8String(self: *const ConstantPoolManager, index: u16) ![]const u8 {
        const entry = try self.getRawEntry(index);
        if (entry != .utf8) {
            return error.ExpectedUtf8Constant;
        }

        // 直接返回原始字符串
        return entry.utf8;
    }

    /// 获取类名
    fn getClassName(self: *ConstantPoolManager, index: u16) ![]const u8 {
        const entry = try self.getRawEntry(index);
        if (entry != .class) {
            return error.ExpectedClassConstant;
        }
        return self.getUtf8String(entry.class);
    }

    /// 获取字符串字面量
    fn getStringLiteral(self: *ConstantPoolManager, index: u16) ![]const u8 {
        const entry = try self.getRawEntry(index);
        if (entry != .string) {
            return error.ExpectedStringConstant;
        }
        return self.getUtf8String(entry.string);
    }

    /// 获取名称和类型信息
    fn getNameAndType(self: *ConstantPoolManager, index: u16) !NameAndType {
        const entry = try self.getRawEntry(index);
        if (entry != .name_and_type) {
            return error.ExpectedNameAndTypeConstant;
        }

        const name = try self.getUtf8String(entry.name_and_type.name_index);
        const descriptor = try self.getUtf8String(entry.name_and_type.descriptor_index);

        return NameAndType{
            .name = name,
            .descriptor = descriptor,
        };
    }

    /// 获取字段引用信息
    fn getFieldReference(self: *ConstantPoolManager, index: u16) !FieldReference {
        const entry = try self.getRawEntry(index);
        if (entry != .fieldref) {
            return error.ExpectedFieldRefConstant;
        }

        const class_name = try self.getClassName(entry.fieldref.class_index);
        const name_and_type = try self.getNameAndType(entry.fieldref.name_and_type_index);

        return FieldReference{
            .class_name = class_name,
            .field_name = name_and_type.name,
            .field_type = name_and_type.descriptor,
        };
    }

    /// 获取方法引用信息
    fn getMethodReference(self: *ConstantPoolManager, index: u16) !MethodReference {
        const entry = try self.getRawEntry(index);
        if (entry != .methodref and entry != .interface_methodref) {
            return error.ExpectedMethodRefConstant;
        }

        const class_index = switch (entry) {
            .methodref => entry.methodref.class_index,
            .interface_methodref => entry.interface_methodref.class_index,
            else => unreachable,
        };

        const name_and_type_index = switch (entry) {
            .methodref => entry.methodref.name_and_type_index,
            .interface_methodref => entry.interface_methodref.name_and_type_index,
            else => unreachable,
        };

        const class_name = try self.getClassName(class_index);
        const name_and_type = try self.getNameAndType(name_and_type_index);

        return MethodReference{
            .class_name = class_name,
            .method_name = name_and_type.name,
            .method_descriptor = name_and_type.descriptor,
        };
    }

    /// 解析常量并缓存结果
    fn resolveConstant(self: *ConstantPoolManager, index: u16) !ResolvedConstant {
        // 检查缓存
        if (self.resolved_cache.get(index)) |cached| {
            return cached;
        }

        const entry = try self.getRawEntry(index);
        const resolved = switch (entry) {
            .utf8 => ResolvedConstant{ .utf8_string = try self.getUtf8String(index) },
            .integer => ResolvedConstant{ .integer = entry.integer },
            .float => ResolvedConstant{ .float = entry.float },
            .long => ResolvedConstant{ .long = entry.long },
            .double => ResolvedConstant{ .double = entry.double },
            .class => ResolvedConstant{ .class_name = try self.getClassName(index) },
            .string => ResolvedConstant{ .string_literal = try self.getStringLiteral(index) },
            .fieldref => ResolvedConstant{ .field_ref = try self.getFieldReference(index) },
            .methodref => ResolvedConstant{ .method_ref = try self.getMethodReference(index) },
            .interface_methodref => ResolvedConstant{ .interface_method_ref = try self.getMethodReference(index) },
            .name_and_type => ResolvedConstant{ .name_and_type = try self.getNameAndType(index) },
            else => return error.UnsupportedConstantType,
        };

        // 缓存解析结果
        try self.resolved_cache.put(index, resolved);
        return resolved;
    }

    /// 获取所有字符串常量
    fn getAllStrings(self: *ConstantPoolManager) !ArrayList([]const u8) {
        var strings = ArrayList([]const u8).init(self.allocator);

        for (self.entries, 1..) |entry, i| {
            if (entry == .utf8) {
                const string = try self.getUtf8String(@intCast(i));
                try strings.append(string);
            }
        }

        return strings;
    }

    /// 获取所有类引用
    fn getAllClassReferences(self: *ConstantPoolManager) !ArrayList([]const u8) {
        var classes = ArrayList([]const u8).init(self.allocator);

        for (self.entries, 1..) |entry, i| {
            if (entry == .class) {
                const class_name = try self.getClassName(@intCast(i));
                try classes.append(class_name);
            }
        }

        return classes;
    }

    /// 获取所有方法引用
    fn getAllMethodReferences(self: *ConstantPoolManager) !ArrayList(MethodReference) {
        var methods = ArrayList(MethodReference).init(self.allocator);

        for (self.entries, 1..) |entry, i| {
            if (entry == .methodref or entry == .interface_methodref) {
                const method_ref = try self.getMethodReference(@intCast(i));
                try methods.append(method_ref);
            }
        }

        return methods;
    }

    /// 获取所有字段引用
    fn getAllFieldReferences(self: *ConstantPoolManager) !ArrayList(FieldReference) {
        var fields = ArrayList(FieldReference).init(self.allocator);

        for (self.entries, 1..) |entry, i| {
            if (entry == .fieldref) {
                const field_ref = try self.getFieldReference(@intCast(i));
                try fields.append(field_ref);
            }
        }

        return fields;
    }

    /// 验证常量池的完整性
    fn validateIntegrity(self: *ConstantPoolManager) !void {
        for (self.entries) |entry| {
            switch (entry) {
                .class => {
                    // 验证类名索引
                    const name_entry = try self.getRawEntry(entry.class);
                    if (name_entry != .utf8) {
                        return error.InvalidClassNameReference;
                    }
                },
                .string => {
                    // 验证字符串索引
                    const string_entry = try self.getRawEntry(entry.string);
                    if (string_entry != .utf8) {
                        return error.InvalidStringReference;
                    }
                },
                .fieldref => {
                    // 验证字段引用
                    const class_entry = try self.getRawEntry(entry.fieldref.class_index);
                    const nat_entry = try self.getRawEntry(entry.fieldref.name_and_type_index);
                    if (class_entry != .class or nat_entry != .name_and_type) {
                        return error.InvalidFieldReference;
                    }
                },
                .methodref => {
                    // 验证方法引用
                    const class_entry = try self.getRawEntry(entry.methodref.class_index);
                    const nat_entry = try self.getRawEntry(entry.methodref.name_and_type_index);
                    if (class_entry != .class or nat_entry != .name_and_type) {
                        return error.InvalidMethodReference;
                    }
                },
                .interface_methodref => {
                    // 验证接口方法引用
                    const class_entry = try self.getRawEntry(entry.interface_methodref.class_index);
                    const nat_entry = try self.getRawEntry(entry.interface_methodref.name_and_type_index);
                    if (class_entry != .class or nat_entry != .name_and_type) {
                        return error.InvalidInterfaceMethodReference;
                    }
                },
                .name_and_type => {
                    // 验证名称和类型引用
                    const name_entry = try self.getRawEntry(entry.name_and_type.name_index);
                    const desc_entry = try self.getRawEntry(entry.name_and_type.descriptor_index);
                    if (name_entry != .utf8 or desc_entry != .utf8) {
                        return error.InvalidNameAndTypeReference;
                    }
                },
                else => {}, // 其他类型不需要特殊验证
            }
        }
    }

    /// 打印常量池信息（用于调试）
    fn printDebugInfo(self: *ConstantPoolManager) void {
        std.debug.print("常量池信息 (共 {} 个条目):\n", .{self.entries.len});

        for (self.entries, 1..) |entry, i| {
            std.debug.print("  #{}: ", .{i});

            switch (entry) {
                .utf8 => std.debug.print("UTF8 = \"{s}\"\n", .{entry.utf8}),
                .integer => std.debug.print("Integer = {}\n", .{entry.integer}),
                .float => std.debug.print("Float = {}\n", .{entry.float}),
                .long => std.debug.print("Long = {}\n", .{entry.long}),
                .double => std.debug.print("Double = {}\n", .{entry.double}),
                .class => std.debug.print("Class = #{}\n", .{entry.class}),
                .string => std.debug.print("String = #{}\n", .{entry.string}),
                .fieldref => std.debug.print("Fieldref = #{}.#{}\n", .{ entry.fieldref.class_index, entry.fieldref.name_and_type_index }),
                .methodref => std.debug.print("Methodref = #{}.#{}\n", .{ entry.methodref.class_index, entry.methodref.name_and_type_index }),
                .interface_methodref => std.debug.print("InterfaceMethodref = #{}.#{}\n", .{ entry.interface_methodref.class_index, entry.interface_methodref.name_and_type_index }),
                .name_and_type => std.debug.print("NameAndType = #{}.#{}\n", .{ entry.name_and_type.name_index, entry.name_and_type.descriptor_index }),
                else => std.debug.print("其他类型\n", .{}),
            }
        }
    }
};

/// 创建常量池管理器
fn createConstantPoolManager(entries: []ConstantPoolEntry, allocator: Allocator) !ConstantPoolManager {
    return ConstantPoolManager.init(entries, allocator);
}

/// 验证常量池引用的有效性
fn validateConstantPoolReferences(entries: []ConstantPoolEntry) !void {
    for (entries) |entry| {
        switch (entry) {
            .class => {
                if (entry.class == 0 or entry.class > entries.len) {
                    return error.InvalidConstantPoolReference;
                }
            },
            .string => {
                if (entry.string == 0 or entry.string > entries.len) {
                    return error.InvalidConstantPoolReference;
                }
            },
            .fieldref => {
                if (entry.fieldref.class_index == 0 or entry.fieldref.class_index > entries.len or
                    entry.fieldref.name_and_type_index == 0 or entry.fieldref.name_and_type_index > entries.len)
                {
                    return error.InvalidConstantPoolReference;
                }
            },
            .methodref => {
                if (entry.methodref.class_index == 0 or entry.methodref.class_index > entries.len or
                    entry.methodref.name_and_type_index == 0 or entry.methodref.name_and_type_index > entries.len)
                {
                    return error.InvalidConstantPoolReference;
                }
            },
            .interface_methodref => {
                if (entry.interface_methodref.class_index == 0 or entry.interface_methodref.class_index > entries.len or
                    entry.interface_methodref.name_and_type_index == 0 or entry.interface_methodref.name_and_type_index > entries.len)
                {
                    return error.InvalidConstantPoolReference;
                }
            },
            .name_and_type => {
                if (entry.name_and_type.name_index == 0 or entry.name_and_type.name_index > entries.len or
                    entry.name_and_type.descriptor_index == 0 or entry.name_and_type.descriptor_index > entries.len)
                {
                    return error.InvalidConstantPoolReference;
                }
            },
            else => {}, // 其他类型不需要验证引用
        }
    }
}

// 导出公共接口
const exports = struct {
    const ConstantPoolManager = @This().ConstantPoolManager;
    const ResolvedConstant = @This().ResolvedConstant;
    const FieldReference = @This().FieldReference;
    const MethodReference = @This().MethodReference;
    const NameAndType = @This().NameAndType;
    const createConstantPoolManager = @This().createConstantPoolManager;
    const validateConstantPoolReferences = @This().validateConstantPoolReferences;
};

test "常量池管理器基础功能测试" {
    const testing = std.testing;
    const allocator = testing.allocator;

    // 创建测试用的常量池条目
    var entries = [_]ConstantPoolEntry{
        ConstantPoolEntry{ .utf8 = "java/lang/Object" },
        ConstantPoolEntry{ .class = 1 },
        ConstantPoolEntry{ .utf8 = "<init>" },
        ConstantPoolEntry{ .utf8 = "()V" },
        ConstantPoolEntry{ .name_and_type = .{ .name_index = 3, .descriptor_index = 4 } },
        ConstantPoolEntry{ .methodref = .{ .class_index = 2, .name_and_type_index = 5 } },
    };

    var manager = try ConstantPoolManager.init(&entries, allocator);
    defer manager.deinit();

    // 测试获取 UTF-8 字符串
    const class_name = try manager.getUtf8String(1);
    try testing.expectEqualStrings("java/lang/Object", class_name);

    // 测试获取类名
    const resolved_class_name = try manager.getClassName(2);
    try testing.expectEqualStrings("java/lang/Object", resolved_class_name);

    // 测试获取方法引用
    const method_ref = try manager.getMethodReference(6);
    try testing.expectEqualStrings("java/lang/Object", method_ref.class_name);
    try testing.expectEqualStrings("<init>", method_ref.method_name);
    try testing.expectEqualStrings("()V", method_ref.method_descriptor);
}

test "常量池引用验证测试" {
    const testing = std.testing;

    // 测试有效的常量池引用
    var valid_entries = [_]ConstantPoolEntry{
        ConstantPoolEntry{ .utf8 = "TestClass" },
        ConstantPoolEntry{ .class = 1 },
    };

    try validateConstantPoolReferences(&valid_entries);

    // 测试无效的常量池引用
    var invalid_entries = [_]ConstantPoolEntry{
        ConstantPoolEntry{ .utf8 = "TestClass" },
        ConstantPoolEntry{ .class = 5 }, // 引用不存在的索引
    };

    try testing.expectError(error.InvalidConstantPoolReference, validateConstantPoolReferences(&invalid_entries));
}
