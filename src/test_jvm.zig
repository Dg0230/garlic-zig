//! JVM 模拟器测试程序
//! 测试字节码解析和执行功能

const std = @import("std");
const jvm = @import("jvm/jvm.zig");
const instructions = @import("jvm/instructions.zig");

const ExecutionContext = jvm.ExecutionContext;
const Opcode = instructions.Opcode;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("=== Garlic JVM 模拟器测试 ===\n\n", .{});

    // 创建执行上下文
    var context = try ExecutionContext.init(allocator, 100, 10);
    defer context.deinit();

    // 测试1: 简单的算术运算
    try testSimpleArithmetic(&context);

    // 测试2: 局部变量操作
    try testLocalVariables(&context);

    // 测试3: 条件分支
    try testConditionalBranch(&context);

    std.debug.print("\n=== 所有测试完成 ===\n", .{});
}

/// 测试简单算术运算
fn testSimpleArithmetic(context: *ExecutionContext) !void {
    std.debug.print("测试1: 简单算术运算\n", .{});
    std.debug.print("计算 5 + 3 * 2\n", .{});

    // 构造字节码: iconst_5, iconst_3, iconst_2, imul, iadd
    const bytecode = [_]u8{
        @intFromEnum(Opcode.iconst_5), // 推入常量 5
        @intFromEnum(Opcode.iconst_3), // 推入常量 3
        @intFromEnum(Opcode.iconst_2), // 推入常量 2
        @intFromEnum(Opcode.imul), // 3 * 2 = 6
        @intFromEnum(Opcode.iadd), // 5 + 6 = 11
        @intFromEnum(Opcode.@"return"), // 返回
    };

    // 重置上下文
    context.reset();

    // 加载字节码
    try context.loadBytecode(&bytecode);

    // 执行
    try context.run(100);

    // 打印结果
    try context.printState(std.io.getStdOut().writer());

    std.debug.print("\n", .{});
}

/// 测试局部变量操作
fn testLocalVariables(context: *ExecutionContext) !void {
    std.debug.print("测试2: 局部变量操作\n", .{});
    std.debug.print("将常量存储到局部变量并加载\n", .{});

    // 构造字节码: iconst_1, istore_0, iconst_2, istore_1, iload_0, iload_1, iadd
    const bytecode = [_]u8{
        @intFromEnum(Opcode.iconst_1), // 推入常量 1
        @intFromEnum(Opcode.istore_0), // 存储到局部变量 0
        @intFromEnum(Opcode.iconst_2), // 推入常量 2
        @intFromEnum(Opcode.istore_1), // 存储到局部变量 1
        @intFromEnum(Opcode.iload_0), // 加载局部变量 0
        @intFromEnum(Opcode.iload_1), // 加载局部变量 1
        @intFromEnum(Opcode.iadd), // 1 + 2 = 3
        @intFromEnum(Opcode.@"return"), // 返回
    };

    // 重置上下文
    context.reset();

    // 加载字节码
    try context.loadBytecode(&bytecode);

    // 执行
    try context.run(100);

    // 打印结果
    try context.printState(std.io.getStdOut().writer());

    std.debug.print("\n", .{});
}

/// 测试条件分支
fn testConditionalBranch(context: *ExecutionContext) !void {
    std.debug.print("测试3: 条件分支\n", .{});
    std.debug.print("测试 if (5 > 3) 分支\n", .{});

    // 构造字节码: iconst_5, iconst_3, if_icmpgt 8, iconst_0, goto 10, iconst_1
    const bytecode = [_]u8{
        @intFromEnum(Opcode.iconst_5), // 0: 推入常量 5
        @intFromEnum(Opcode.iconst_3), // 1: 推入常量 3
        @intFromEnum(Opcode.if_icmpgt), // 2: 如果 5 > 3 跳转到偏移 8 (PC 2 + 6 = 8)
        0, 6, // 3-4: 跳转偏移 +6
        @intFromEnum(Opcode.iconst_0), // 5: 推入 0 (false 分支)
        @intFromEnum(Opcode.goto), // 6: 无条件跳转
        0, 2, // 7-8: 跳转偏移 +2
        @intFromEnum(Opcode.iconst_1), // 9: 推入 1 (true 分支)
        @intFromEnum(Opcode.@"return"), // 10: 返回
    };

    // 重置上下文
    context.reset();

    // 加载字节码
    try context.loadBytecode(&bytecode);

    // 执行
    try context.run(100);

    // 打印结果
    try context.printState(std.io.getStdOut().writer());

    std.debug.print("\n", .{});
}

/// 测试方法调用（模拟）
fn testMethodCall(context: *ExecutionContext) !void {
    std.debug.print("测试4: 方法调用\n", .{});
    std.debug.print("模拟 System.out.println 调用\n", .{});

    // 构造字节码: getstatic, ldc, invokevirtual
    const bytecode = [_]u8{
        @intFromEnum(Opcode.getstatic), // 获取 System.out
        0, 1, // 常量池索引 1
        @intFromEnum(Opcode.ldc), // 加载字符串常量
        2, // 常量池索引 2
        @intFromEnum(Opcode.invokevirtual), // 调用 println
        0, 3, // 常量池索引 3
        @intFromEnum(Opcode.@"return"), // 返回
    };

    // 重置上下文
    context.reset();

    // 加载字节码
    try context.loadBytecode(&bytecode);

    // 执行
    try context.run(100);

    // 打印结果
    try context.printState(std.io.getStdOut().writer());

    std.debug.print("\n", .{});
}
