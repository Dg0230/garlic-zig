//! JVM 局部变量表模拟器
//! 模拟 JVM 运行时的局部变量表行为

const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const stack = @import("stack.zig");
const StackValue = stack.StackValue;
const ValueType = stack.ValueType;

/// 局部变量表错误类型
pub const LocalsError = error{
    IndexOutOfBounds,
    InvalidSlotAccess,
    TypeMismatch,
    UninitializedVariable,
};

/// 局部变量槽状态
pub const SlotState = enum {
    uninitialized, // 未初始化
    initialized, // 已初始化
    invalid, // 无效（被长类型的高位占用）
};

/// 局部变量槽
pub const LocalSlot = struct {
    value: StackValue,
    state: SlotState,

    /// 创建未初始化的槽
    pub fn uninitialized() LocalSlot {
        return LocalSlot{
            .value = StackValue{ .int = 0 },
            .state = .uninitialized,
        };
    }

    /// 创建已初始化的槽
    pub fn initialized(value: StackValue) LocalSlot {
        return LocalSlot{
            .value = value,
            .state = .initialized,
        };
    }

    /// 创建无效槽（用于长类型的高位）
    pub fn invalid() LocalSlot {
        return LocalSlot{
            .value = StackValue{ .int = 0 },
            .state = .invalid,
        };
    }

    /// 检查槽是否可读
    pub fn isReadable(self: *const LocalSlot) bool {
        return self.state == .initialized;
    }

    /// 检查槽是否可写
    pub fn isWritable(self: *const LocalSlot) bool {
        return self.state != .invalid;
    }
};

/// JVM 局部变量表
pub const LocalVariableTable = struct {
    slots: []LocalSlot,
    max_locals: usize,
    allocator: Allocator,

    /// 创建新的局部变量表
    pub fn init(allocator: Allocator, max_locals: usize) !LocalVariableTable {
        const slots = try allocator.alloc(LocalSlot, max_locals);

        // 初始化所有槽为未初始化状态
        for (slots) |*slot| {
            slot.* = LocalSlot.uninitialized();
        }

        return LocalVariableTable{
            .slots = slots,
            .max_locals = max_locals,
            .allocator = allocator,
        };
    }

    /// 释放局部变量表资源
    pub fn deinit(self: *LocalVariableTable) void {
        self.allocator.free(self.slots);
    }

    /// 获取局部变量表大小
    pub fn size(self: *const LocalVariableTable) usize {
        return self.max_locals;
    }

    /// 检查索引是否有效
    pub fn isValidIndex(self: *const LocalVariableTable, index: usize) bool {
        return index < self.max_locals;
    }

    /// 清空所有局部变量
    pub fn clear(self: *LocalVariableTable) void {
        for (self.slots) |*slot| {
            slot.* = LocalSlot.uninitialized();
        }
    }

    /// 打印局部变量表状态
    pub fn print(self: *const LocalVariableTable, writer: anytype) !void {
        try writer.print("  Max locals: {d}\n", .{self.max_locals});

        var has_initialized = false;
        for (self.slots, 0..) |slot, i| {
            if (slot.state == .initialized) {
                if (!has_initialized) {
                    try writer.print("  Initialized variables:\n", .{});
                    has_initialized = true;
                }
                try writer.print("    [{d}]: ", .{i});
                switch (slot.value) {
                    .int => |v| try writer.print("int({d})\n", .{v}),
                    .long => |v| try writer.print("long({d})\n", .{v}),
                    .float => |v| try writer.print("float({d})\n", .{v}),
                    .double => |v| try writer.print("double({d})\n", .{v}),
                    .reference => |v| try writer.print("ref({any})\n", .{v}),
                    .return_address => |v| try writer.print("ret_addr({d})\n", .{v}),
                }
            }
        }

        if (!has_initialized) {
            try writer.print("  (no initialized variables)\n", .{});
        }
    }

    /// 设置局部变量值
    pub fn set(self: *LocalVariableTable, index: usize, value: StackValue) !void {
        if (!self.isValidIndex(index)) {
            return LocalsError.IndexOutOfBounds;
        }

        if (!self.slots[index].isWritable()) {
            return LocalsError.InvalidSlotAccess;
        }

        // 设置主槽
        self.slots[index] = LocalSlot.initialized(value);

        // 如果是长类型（占用2个槽），设置下一个槽为无效
        if (value.getSize() == 2) {
            if (!self.isValidIndex(index + 1)) {
                return LocalsError.IndexOutOfBounds;
            }
            self.slots[index + 1] = LocalSlot.invalid();
        }

        // 如果当前槽之前是长类型的高位，需要清理前一个槽
        if (index > 0 and self.slots[index - 1].isReadable() and
            self.slots[index - 1].value.getSize() == 2)
        {
            self.slots[index - 1] = LocalSlot.uninitialized();
        }
    }

    /// 获取局部变量值
    pub fn get(self: *const LocalVariableTable, index: usize) !StackValue {
        if (!self.isValidIndex(index)) {
            return LocalsError.IndexOutOfBounds;
        }

        const slot = &self.slots[index];
        if (!slot.isReadable()) {
            return LocalsError.UninitializedVariable;
        }

        return slot.value;
    }

    /// 设置整数值
    pub fn setInt(self: *LocalVariableTable, index: usize, value: i32) !void {
        try self.set(index, StackValue{ .int = value });
    }

    /// 设置长整数值
    pub fn setLong(self: *LocalVariableTable, index: usize, value: i64) !void {
        try self.set(index, StackValue{ .long = value });
    }

    /// 设置浮点数值
    pub fn setFloat(self: *LocalVariableTable, index: usize, value: f32) !void {
        try self.set(index, StackValue{ .float = value });
    }

    /// 设置双精度浮点数值
    pub fn setDouble(self: *LocalVariableTable, index: usize, value: f64) !void {
        try self.set(index, StackValue{ .double = value });
    }

    /// 设置引用值
    pub fn setReference(self: *LocalVariableTable, index: usize, value: ?*anyopaque) !void {
        try self.set(index, StackValue{ .reference = value });
    }

    /// 设置返回地址
    pub fn setReturnAddress(self: *LocalVariableTable, index: usize, value: u32) !void {
        try self.set(index, StackValue{ .return_address = value });
    }

    /// 获取整数值
    pub fn getInt(self: *const LocalVariableTable, index: usize) !i32 {
        const value = try self.get(index);
        return value.toInt() catch LocalsError.TypeMismatch;
    }

    /// 获取长整数值
    pub fn getLong(self: *const LocalVariableTable, index: usize) !i64 {
        const value = try self.get(index);
        return value.toLong() catch LocalsError.TypeMismatch;
    }

    /// 获取浮点数值
    pub fn getFloat(self: *const LocalVariableTable, index: usize) !f32 {
        const value = try self.get(index);
        return value.toFloat() catch LocalsError.TypeMismatch;
    }

    /// 获取双精度浮点数值
    pub fn getDouble(self: *const LocalVariableTable, index: usize) !f64 {
        const value = try self.get(index);
        return value.toDouble() catch LocalsError.TypeMismatch;
    }

    /// 获取引用值
    pub fn getReference(self: *const LocalVariableTable, index: usize) !?*anyopaque {
        const value = try self.get(index);
        return value.toReference() catch LocalsError.TypeMismatch;
    }

    /// 获取返回地址
    pub fn getReturnAddress(self: *const LocalVariableTable, index: usize) !u32 {
        const value = try self.get(index);
        return switch (value) {
            .return_address => |v| v,
            else => LocalsError.TypeMismatch,
        };
    }

    /// 递增整数局部变量
    pub fn incrementInt(self: *LocalVariableTable, index: usize, increment: i32) !void {
        const current = try self.getInt(index);
        try self.setInt(index, current +% increment); // 使用溢出包装加法
    }

    /// 检查指定索引的变量是否已初始化
    pub fn isInitialized(self: *const LocalVariableTable, index: usize) bool {
        if (!self.isValidIndex(index)) return false;
        return self.slots[index].isReadable();
    }

    /// 获取变量类型（如果已初始化）
    pub fn getType(self: *const LocalVariableTable, index: usize) !ValueType {
        if (!self.isValidIndex(index)) {
            return LocalsError.IndexOutOfBounds;
        }

        const slot = &self.slots[index];
        if (!slot.isReadable()) {
            return LocalsError.UninitializedVariable;
        }

        return @as(ValueType, slot.value);
    }

    /// 复制局部变量到另一个位置
    pub fn copy(self: *LocalVariableTable, from_index: usize, to_index: usize) !void {
        const value = try self.get(from_index);
        try self.set(to_index, value);
    }

    /// 交换两个局部变量的值
    pub fn swap(self: *LocalVariableTable, index1: usize, index2: usize) !void {
        if (!self.isValidIndex(index1) or !self.isValidIndex(index2)) {
            return LocalsError.IndexOutOfBounds;
        }

        const value1 = try self.get(index1);
        const value2 = try self.get(index2);

        try self.set(index1, value2);
        try self.set(index2, value1);
    }

    /// 获取局部变量表的字符串表示（用于调试）
    pub fn toString(self: *const LocalVariableTable, allocator: Allocator) ![]u8 {
        var result = std.ArrayList(u8).init(allocator);
        defer result.deinit();

        try result.appendSlice("Locals: ");

        for (self.slots, 0..) |slot, i| {
            if (i > 0) try result.appendSlice(", ");

            try result.writer().print("[{}]=", .{i});

            switch (slot.state) {
                .uninitialized => try result.appendSlice("uninit"),
                .invalid => try result.appendSlice("invalid"),
                .initialized => {
                    switch (slot.value) {
                        .int => |v| try result.writer().print("int({})", .{v}),
                        .long => |v| try result.writer().print("long({})", .{v}),
                        .float => |v| try result.writer().print("float({})", .{v}),
                        .double => |v| try result.writer().print("double({})", .{v}),
                        .reference => |v| try result.writer().print("ref({*})", .{v}),
                        .return_address => |v| try result.writer().print("ret_addr({})", .{v}),
                    }
                },
            }
        }

        return result.toOwnedSlice();
    }
};

/// 方法参数加载器
pub const ParameterLoader = struct {
    /// 加载方法参数到局部变量表
    /// is_static: 是否为静态方法
    /// parameters: 参数值数组
    /// locals: 目标局部变量表
    pub fn loadParameters(
        is_static: bool,
        parameters: []const StackValue,
        locals: *LocalVariableTable,
    ) !void {
        var index: usize = 0;

        // 非静态方法的第0个位置是this引用
        if (!is_static) {
            // 这里应该设置this引用，暂时设为null
            try locals.setReference(0, null);
            index = 1;
        }

        // 加载参数
        for (parameters) |param| {
            try locals.set(index, param);
            index += param.getSize();
        }
    }

    /// 计算方法参数占用的局部变量槽数
    pub fn calculateParameterSlots(is_static: bool, parameters: []const StackValue) usize {
        var slots: usize = if (is_static) 0 else 1; // this引用占用1个槽

        for (parameters) |param| {
            slots += param.getSize();
        }

        return slots;
    }
};

test "local variable table basic operations" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var locals = try LocalVariableTable.init(allocator, 5);
    defer locals.deinit();

    // 测试设置和获取整数
    try locals.setInt(0, 42);
    const value = try locals.getInt(0);
    try testing.expect(value == 42);

    // 测试类型检查
    try testing.expectError(LocalsError.TypeMismatch, locals.getFloat(0));

    // 测试未初始化变量
    try testing.expectError(LocalsError.UninitializedVariable, locals.get(1));
}

test "local variable table long values" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var locals = try LocalVariableTable.init(allocator, 5);
    defer locals.deinit();

    // 测试长整数（占用2个槽）
    try locals.setLong(1, 123456789);
    const long_value = try locals.getLong(1);
    try testing.expect(long_value == 123456789);

    // 检查第2个槽被标记为无效
    try testing.expectError(LocalsError.UninitializedVariable, locals.get(2));

    // 测试覆盖长类型
    try locals.setInt(1, 999);
    const int_value = try locals.getInt(1);
    try testing.expect(int_value == 999);
}

test "local variable table parameter loading" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var locals = try LocalVariableTable.init(allocator, 10);
    defer locals.deinit();

    // 测试静态方法参数加载
    const params = [_]StackValue{
        StackValue{ .int = 100 },
        StackValue{ .long = 200 },
        StackValue{ .float = 3.14 },
    };

    try ParameterLoader.loadParameters(true, &params, &locals);

    // 验证参数
    try testing.expect(try locals.getInt(0) == 100);
    try testing.expect(try locals.getLong(1) == 200); // 占用槽1和2
    try testing.expect(@abs(try locals.getFloat(3) - 3.14) < 0.001);

    // 测试槽数计算
    const slots = ParameterLoader.calculateParameterSlots(true, &params);
    try testing.expect(slots == 4); // int(1) + long(2) + float(1) = 4
}

test "local variable table increment operation" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var locals = try LocalVariableTable.init(allocator, 5);
    defer locals.deinit();

    // 测试递增操作
    try locals.setInt(0, 10);
    try locals.incrementInt(0, 5);
    const result = try locals.getInt(0);
    try testing.expect(result == 15);

    // 测试溢出
    try locals.setInt(1, std.math.maxInt(i32));
    try locals.incrementInt(1, 1);
    const overflow_result = try locals.getInt(1);
    try testing.expect(overflow_result == std.math.minInt(i32));
}

test "local variable table bounds checking" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var locals = try LocalVariableTable.init(allocator, 3);
    defer locals.deinit();

    // 测试索引越界
    try testing.expectError(LocalsError.IndexOutOfBounds, locals.setInt(3, 42));
    try testing.expectError(LocalsError.IndexOutOfBounds, locals.get(5));

    // 测试长类型越界
    try testing.expectError(LocalsError.IndexOutOfBounds, locals.setLong(2, 123)); // 需要槽2和3，但只有0-2
}
