//! JVM 操作数栈模拟器
//! 模拟 JVM 运行时的操作数栈行为

const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

/// JVM 值类型
pub const ValueType = enum {
    int,
    long,
    float,
    double,
    reference,
    return_address,
};

/// JVM 栈值
pub const StackValue = union(ValueType) {
    int: i32,
    long: i64,
    float: f32,
    double: f64,
    reference: ?*anyopaque, // 对象引用或 null
    return_address: u32, // 返回地址

    /// 获取值的大小（栈槽数）
    pub fn getSize(self: StackValue) u8 {
        return switch (self) {
            .int, .float, .reference, .return_address => 1,
            .long, .double => 2,
        };
    }

    /// 检查是否为计算类型1（占用1个栈槽）
    pub fn isCategory1(self: StackValue) bool {
        return self.getSize() == 1;
    }

    /// 检查是否为计算类型2（占用2个栈槽）
    pub fn isCategory2(self: StackValue) bool {
        return self.getSize() == 2;
    }

    /// 转换为整数（如果可能）
    pub fn toInt(self: StackValue) !i32 {
        return switch (self) {
            .int => |v| v,
            else => error.InvalidConversion,
        };
    }

    /// 转换为长整数（如果可能）
    pub fn toLong(self: StackValue) !i64 {
        return switch (self) {
            .long => |v| v,
            else => error.InvalidConversion,
        };
    }

    /// 转换为浮点数（如果可能）
    pub fn toFloat(self: StackValue) !f32 {
        return switch (self) {
            .float => |v| v,
            else => error.InvalidConversion,
        };
    }

    /// 转换为双精度浮点数（如果可能）
    pub fn toDouble(self: StackValue) !f64 {
        return switch (self) {
            .double => |v| v,
            else => error.InvalidConversion,
        };
    }

    /// 转换为引用（如果可能）
    pub fn toReference(self: StackValue) !?*anyopaque {
        return switch (self) {
            .reference => |v| v,
            else => error.InvalidConversion,
        };
    }
};

/// 操作数栈错误类型
pub const StackError = error{
    StackOverflow,
    StackUnderflow,
    InvalidOperation,
    TypeMismatch,
};

/// JVM 操作数栈
pub const OperandStack = struct {
    values: ArrayList(StackValue),
    max_size: usize,
    allocator: Allocator,

    /// 创建新的操作数栈
    pub fn init(allocator: Allocator, max_size: usize) OperandStack {
        return OperandStack{
            .values = ArrayList(StackValue).init(allocator),
            .max_size = max_size,
            .allocator = allocator,
        };
    }

    /// 释放栈资源
    pub fn deinit(self: *OperandStack) void {
        self.values.deinit();
    }

    /// 获取当前栈大小
    pub fn size(self: *const OperandStack) usize {
        return self.values.items.len;
    }

    /// 检查栈是否为空
    pub fn isEmpty(self: *const OperandStack) bool {
        return self.values.items.len == 0;
    }

    /// 检查栈是否已满
    pub fn isFull(self: *const OperandStack) bool {
        return self.values.items.len >= self.max_size;
    }

    /// 清空栈
    pub fn clear(self: *OperandStack) void {
        self.values.clearRetainingCapacity();
    }

    /// 压栈操作
    pub fn push(self: *OperandStack, value: StackValue) !void {
        if (self.values.items.len + value.getSize() > self.max_size) {
            return StackError.StackOverflow;
        }
        try self.values.append(value);
    }

    /// 出栈操作
    pub fn pop(self: *OperandStack) !StackValue {
        if (self.values.items.len == 0) {
            return StackError.StackUnderflow;
        }
        return self.values.pop() orelse return StackError.StackUnderflow;
    }

    /// 查看栈顶元素（不出栈）
    pub fn peek(self: *const OperandStack) !StackValue {
        if (self.values.items.len == 0) {
            return StackError.StackUnderflow;
        }
        return self.values.items[self.values.items.len - 1];
    }

    /// 查看栈顶第n个元素（0表示栈顶）
    pub fn peekAt(self: *const OperandStack, index: usize) !StackValue {
        if (index >= self.values.items.len) {
            return StackError.StackUnderflow;
        }
        return self.values.items[self.values.items.len - 1 - index];
    }

    /// 压入整数
    pub fn pushInt(self: *OperandStack, value: i32) !void {
        try self.push(StackValue{ .int = value });
    }

    /// 压入长整数
    pub fn pushLong(self: *OperandStack, value: i64) !void {
        try self.push(StackValue{ .long = value });
    }

    /// 压入浮点数
    pub fn pushFloat(self: *OperandStack, value: f32) !void {
        try self.push(StackValue{ .float = value });
    }

    /// 压入双精度浮点数
    pub fn pushDouble(self: *OperandStack, value: f64) !void {
        try self.push(StackValue{ .double = value });
    }

    /// 压入引用
    pub fn pushReference(self: *OperandStack, value: ?*anyopaque) !void {
        try self.push(StackValue{ .reference = value });
    }

    /// 压入返回地址
    pub fn pushReturnAddress(self: *OperandStack, value: u32) !void {
        try self.push(StackValue{ .return_address = value });
    }

    /// 弹出整数
    pub fn popInt(self: *OperandStack) !i32 {
        const value = try self.pop();
        return value.toInt();
    }

    /// 弹出长整数
    pub fn popLong(self: *OperandStack) !i64 {
        const value = try self.pop();
        return value.toLong();
    }

    /// 弹出浮点数
    pub fn popFloat(self: *OperandStack) !f32 {
        const value = try self.pop();
        return value.toFloat();
    }

    /// 弹出双精度浮点数
    pub fn popDouble(self: *OperandStack) !f64 {
        const value = try self.pop();
        return value.toDouble();
    }

    /// 弹出引用
    pub fn popReference(self: *OperandStack) !?*anyopaque {
        const value = try self.pop();
        return value.toReference();
    }

    /// 复制栈顶元素
    pub fn dup(self: *OperandStack) !void {
        const value = try self.peek();
        if (!value.isCategory1()) {
            return StackError.InvalidOperation;
        }
        try self.push(value);
    }

    /// 复制栈顶元素并插入到栈顶下一个位置
    pub fn dupX1(self: *OperandStack) !void {
        if (self.values.items.len < 2) {
            return StackError.StackUnderflow;
        }

        const value1 = try self.pop(); // 栈顶
        const value2 = try self.pop(); // 栈顶下一个

        if (!value1.isCategory1() or !value2.isCategory1()) {
            return StackError.InvalidOperation;
        }

        try self.push(value1); // 复制的值
        try self.push(value2); // 原来的第二个值
        try self.push(value1); // 原来的栈顶值
    }

    /// 复制栈顶元素并插入到栈顶下两个位置
    pub fn dupX2(self: *OperandStack) !void {
        if (self.values.items.len < 2) {
            return StackError.StackUnderflow;
        }

        const value1 = try self.pop(); // 栈顶
        const value2 = try self.pop(); // 栈顶下一个

        if (!value1.isCategory1()) {
            return StackError.InvalidOperation;
        }

        if (value2.isCategory2()) {
            // 形式2: value1, value2 -> value1, value2, value1
            try self.push(value1);
            try self.push(value2);
            try self.push(value1);
        } else {
            // 形式1: value1, value2, value3 -> value1, value2, value3, value1
            if (self.values.items.len < 1) {
                return StackError.StackUnderflow;
            }
            const value3 = try self.pop();
            if (!value3.isCategory1()) {
                return StackError.InvalidOperation;
            }
            try self.push(value1);
            try self.push(value3);
            try self.push(value2);
            try self.push(value1);
        }
    }

    /// 复制栈顶两个元素
    pub fn dup2(self: *OperandStack) !void {
        if (self.values.items.len < 1) {
            return StackError.StackUnderflow;
        }

        const value1 = try self.peek();

        if (value1.isCategory2()) {
            // 形式2: value -> value, value
            try self.push(value1);
        } else {
            // 形式1: value1, value2 -> value1, value2, value1, value2
            if (self.values.items.len < 2) {
                return StackError.StackUnderflow;
            }
            const value2 = try self.peekAt(1);
            if (!value2.isCategory1()) {
                return StackError.InvalidOperation;
            }
            try self.push(value2);
            try self.push(value1);
        }
    }

    /// 交换栈顶两个元素
    pub fn swap(self: *OperandStack) !void {
        if (self.values.items.len < 2) {
            return StackError.StackUnderflow;
        }

        const value1 = try self.pop();
        const value2 = try self.pop();

        if (!value1.isCategory1() or !value2.isCategory1()) {
            return StackError.InvalidOperation;
        }

        try self.push(value1);
        try self.push(value2);
    }

    /// 打印栈状态
    pub fn print(self: *const OperandStack, writer: anytype) !void {
        try writer.print("  Size: {d}/{d}\n", .{ self.size(), self.max_size });
        if (self.isEmpty()) {
            try writer.print("  (empty)\n", .{});
            return;
        }

        for (self.values.items, 0..) |value, i| {
            try writer.print("  [{d}]: ", .{i});
            switch (value) {
                .int => |v| try writer.print("int({d})\n", .{v}),
                .long => |v| try writer.print("long({d})\n", .{v}),
                .float => |v| try writer.print("float({d})\n", .{v}),
                .double => |v| try writer.print("double({d})\n", .{v}),
                .reference => |v| try writer.print("ref({any})\n", .{v}),
                .return_address => |v| try writer.print("ret_addr({d})\n", .{v}),
            }
        }
    }

    /// 弹出栈顶元素（忽略值）
    pub fn popIgnore(self: *OperandStack) !void {
        _ = try self.pop();
    }

    /// 弹出栈顶两个元素或一个类型2元素
    pub fn pop2(self: *OperandStack) !void {
        if (self.values.items.len < 1) {
            return StackError.StackUnderflow;
        }

        const value1 = try self.pop();

        if (value1.isCategory1()) {
            // 需要再弹出一个类型1元素
            if (self.values.items.len < 1) {
                return StackError.StackUnderflow;
            }
            const value2 = try self.pop();
            if (!value2.isCategory1()) {
                return StackError.InvalidOperation;
            }
        }
        // 如果是类型2元素，已经弹出了
    }

    /// 获取栈的字符串表示（用于调试）
    pub fn toString(self: *const OperandStack, allocator: Allocator) ![]u8 {
        var result = std.ArrayList(u8).init(allocator);
        defer result.deinit();

        try result.appendSlice("Stack [bottom -> top]: ");

        for (self.values.items, 0..) |value, i| {
            if (i > 0) try result.appendSlice(", ");

            switch (value) {
                .int => |v| try result.writer().print("int({})", .{v}),
                .long => |v| try result.writer().print("long({})", .{v}),
                .float => |v| try result.writer().print("float({})", .{v}),
                .double => |v| try result.writer().print("double({})", .{v}),
                .reference => |v| try result.writer().print("ref({*})", .{v}),
                .return_address => |v| try result.writer().print("ret_addr({})", .{v}),
            }
        }

        return result.toOwnedSlice();
    }
};

test "operand stack basic operations" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var stack = OperandStack.init(allocator, 10);
    defer stack.deinit();

    // 测试空栈
    try testing.expect(stack.isEmpty());
    try testing.expect(stack.size() == 0);

    // 测试压栈
    try stack.pushInt(42);
    try testing.expect(!stack.isEmpty());
    try testing.expect(stack.size() == 1);

    // 测试查看栈顶
    const top = try stack.peek();
    try testing.expect(top == .int);
    try testing.expect(top.int == 42);

    // 测试出栈
    const popped = try stack.popInt();
    try testing.expect(popped == 42);
    try testing.expect(stack.isEmpty());
}

test "operand stack type operations" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var stack = OperandStack.init(allocator, 10);
    defer stack.deinit();

    // 测试不同类型
    try stack.pushInt(123);
    try stack.pushLong(456789);
    try stack.pushFloat(3.14);
    try stack.pushDouble(2.718281828);
    try stack.pushReference(null);

    // 测试类型转换
    _ = try stack.popReference();
    const d = try stack.popDouble();
    try testing.expect(@abs(d - 2.718281828) < 0.000001);

    const f = try stack.popFloat();
    try testing.expect(@abs(f - 3.14) < 0.001);

    const l = try stack.popLong();
    try testing.expect(l == 456789);

    const i = try stack.popInt();
    try testing.expect(i == 123);
}

test "operand stack dup operations" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var stack = OperandStack.init(allocator, 10);
    defer stack.deinit();

    // 测试 dup
    try stack.pushInt(42);
    try stack.dup();
    try testing.expect(stack.size() == 2);

    const val1 = try stack.popInt();
    const val2 = try stack.popInt();
    try testing.expect(val1 == 42);
    try testing.expect(val2 == 42);

    // 测试 swap
    try stack.pushInt(1);
    try stack.pushInt(2);
    try stack.swap();

    const first = try stack.popInt();
    const second = try stack.popInt();
    try testing.expect(first == 1);
    try testing.expect(second == 2);
}

test "operand stack overflow and underflow" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var stack = OperandStack.init(allocator, 2);
    defer stack.deinit();

    // 测试栈溢出
    try stack.pushInt(1);
    try stack.pushInt(2);
    try testing.expectError(StackError.StackOverflow, stack.pushInt(3));

    // 清空栈
    stack.clear();

    // 测试栈下溢
    try testing.expectError(StackError.StackUnderflow, stack.pop());
    try testing.expectError(StackError.StackUnderflow, stack.peek());
}
