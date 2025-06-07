//! JVM 控制流处理器
//! 实现分支、跳转、条件判断等控制流指令的处理逻辑

const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const instructions = @import("instructions.zig");
const stack = @import("stack.zig");

const Opcode = instructions.Opcode;
const OperandStack = stack.OperandStack;
const StackValue = stack.StackValue;
const ValueType = stack.ValueType;

/// 控制流处理错误类型
pub const ControlFlowError = error{
    InvalidBranchTarget,
    StackUnderflow,
    StackOverflow,
    InvalidOperation,
    TypeMismatch,
    IncompatibleTypes,
    InvalidCondition,
    OutOfMemory,
};

/// 分支结果
pub const BranchResult = struct {
    should_branch: bool,
    target_pc: u32,
    next_pc: u32,
};

/// 控制流处理器
pub const ControlFlowProcessor = struct {
    allocator: Allocator,

    pub fn init(allocator: Allocator) ControlFlowProcessor {
        return ControlFlowProcessor{
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *ControlFlowProcessor) void {
        _ = self;
    }

    /// 处理无条件跳转指令 (goto)
    pub fn processGoto(
        self: *ControlFlowProcessor,
        pc: u32,
        operands: []const u8,
    ) ControlFlowError!BranchResult {
        _ = self;

        if (operands.len < 2) return ControlFlowError.InvalidBranchTarget;

        const offset = (@as(i16, operands[0]) << 8) | @as(i16, operands[1]);
        const target_pc = @as(u32, @intCast(@as(i32, @intCast(pc)) + @as(i32, offset)));

        return BranchResult{
            .should_branch = true,
            .target_pc = target_pc,
            .next_pc = target_pc,
        };
    }

    /// 处理条件分支指令 (if*)
    pub fn processConditionalBranch(
        self: *ControlFlowProcessor,
        opcode: Opcode,
        pc: u32,
        operands: []const u8,
        operand_stack: *OperandStack,
    ) ControlFlowError!BranchResult {
        _ = self;

        if (operands.len < 2) return ControlFlowError.InvalidBranchTarget;

        const offset = (@as(i16, operands[0]) << 8) | @as(i16, operands[1]);
        const target_pc = @as(u32, @intCast(@as(i32, @intCast(pc)) + @as(i32, offset)));
        const next_pc = pc + 3;

        const should_branch = switch (opcode) {
            // 单值条件分支
            .ifeq => blk: {
                const value = try operand_stack.pop();
                const int_val = value.toInt() catch return ControlFlowError.IncompatibleTypes;
                break :blk int_val == 0;
            },
            .ifne => blk: {
                const value = try operand_stack.pop();
                const int_val = value.toInt() catch return ControlFlowError.IncompatibleTypes;
                break :blk int_val != 0;
            },
            .iflt => blk: {
                const value = try operand_stack.pop();
                const int_val = value.toInt() catch return ControlFlowError.IncompatibleTypes;
                break :blk int_val < 0;
            },
            .ifge => blk: {
                const value = try operand_stack.pop();
                const int_val = value.toInt() catch return ControlFlowError.IncompatibleTypes;
                break :blk int_val >= 0;
            },
            .ifgt => blk: {
                const value = try operand_stack.pop();
                const int_val = value.toInt() catch return ControlFlowError.IncompatibleTypes;
                break :blk int_val > 0;
            },
            .ifle => blk: {
                const value = try operand_stack.pop();
                const int_val = value.toInt() catch return ControlFlowError.IncompatibleTypes;
                break :blk int_val <= 0;
            },

            // 双值比较分支
            .if_icmpeq => blk: {
                const value2 = try operand_stack.pop();
                const value1 = try operand_stack.pop();
                const int_val1 = value1.toInt() catch return ControlFlowError.IncompatibleTypes;
                const int_val2 = value2.toInt() catch return ControlFlowError.IncompatibleTypes;
                break :blk int_val1 == int_val2;
            },
            .if_icmpne => blk: {
                const value2 = try operand_stack.pop();
                const value1 = try operand_stack.pop();
                const int_val1 = value1.toInt() catch return ControlFlowError.IncompatibleTypes;
                const int_val2 = value2.toInt() catch return ControlFlowError.IncompatibleTypes;
                break :blk int_val1 != int_val2;
            },
            .if_icmplt => blk: {
                const value2 = try operand_stack.pop();
                const value1 = try operand_stack.pop();
                const int_val1 = value1.toInt() catch return ControlFlowError.IncompatibleTypes;
                const int_val2 = value2.toInt() catch return ControlFlowError.IncompatibleTypes;
                break :blk int_val1 < int_val2;
            },
            .if_icmpge => blk: {
                const value2 = try operand_stack.pop();
                const value1 = try operand_stack.pop();
                const int_val1 = value1.toInt() catch return ControlFlowError.IncompatibleTypes;
                const int_val2 = value2.toInt() catch return ControlFlowError.IncompatibleTypes;
                break :blk int_val1 >= int_val2;
            },
            .if_icmpgt => blk: {
                const value2 = try operand_stack.pop();
                const value1 = try operand_stack.pop();
                const int_val1 = value1.toInt() catch return ControlFlowError.IncompatibleTypes;
                const int_val2 = value2.toInt() catch return ControlFlowError.IncompatibleTypes;
                break :blk int_val1 > int_val2;
            },
            .if_icmple => blk: {
                const value2 = try operand_stack.pop();
                const value1 = try operand_stack.pop();
                const int_val1 = value1.toInt() catch return ControlFlowError.IncompatibleTypes;
                const int_val2 = value2.toInt() catch return ControlFlowError.IncompatibleTypes;
                break :blk int_val1 <= int_val2;
            },

            // 引用比较分支
            .if_acmpeq => blk: {
                const value2 = try operand_stack.pop();
                const value1 = try operand_stack.pop();
                // 简单的引用比较（这里可能需要更复杂的逻辑）
                break :blk std.meta.eql(value1, value2);
            },
            .if_acmpne => blk: {
                const value2 = try operand_stack.pop();
                const value1 = try operand_stack.pop();
                // 简单的引用比较（这里可能需要更复杂的逻辑）
                break :blk !std.meta.eql(value1, value2);
            },

            // null 检查分支
            .ifnull => blk: {
                const value = try operand_stack.pop();
                break :blk switch (value) {
                    .reference => |ref| ref == null,
                    else => false,
                };
            },
            .ifnonnull => blk: {
                const value = try operand_stack.pop();
                break :blk switch (value) {
                    .reference => |ref| ref != null,
                    else => true,
                };
            },

            else => return ControlFlowError.InvalidCondition,
        };

        return BranchResult{
            .should_branch = should_branch,
            .target_pc = if (should_branch) target_pc else next_pc,
            .next_pc = if (should_branch) target_pc else next_pc,
        };
    }

    /// 处理 tableswitch 指令
    pub fn processTableSwitch(
        self: *ControlFlowProcessor,
        pc: u32,
        operands: []const u8,
        operand_stack: *OperandStack,
    ) ControlFlowError!BranchResult {
        _ = self;

        if (operands.len < 12) return ControlFlowError.InvalidBranchTarget;

        const index_value = try operand_stack.pop();
        const index = index_value.toInt() catch return ControlFlowError.IncompatibleTypes;

        // 解析 tableswitch 参数
        var offset: usize = 0;

        // 跳过填充字节，使得后续的 4 字节对齐
        const padding = (4 - ((pc + 1) % 4)) % 4;
        offset += padding;

        if (offset + 12 > operands.len) return ControlFlowError.InvalidBranchTarget;

        // 读取默认跳转偏移
        const default_offset = (@as(i32, operands[offset]) << 24) |
            (@as(i32, operands[offset + 1]) << 16) |
            (@as(i32, operands[offset + 2]) << 8) |
            @as(i32, operands[offset + 3]);
        offset += 4;

        // 读取低值
        const low = (@as(i32, operands[offset]) << 24) |
            (@as(i32, operands[offset + 1]) << 16) |
            (@as(i32, operands[offset + 2]) << 8) |
            @as(i32, operands[offset + 3]);
        offset += 4;

        // 读取高值
        const high = (@as(i32, operands[offset]) << 24) |
            (@as(i32, operands[offset + 1]) << 16) |
            (@as(i32, operands[offset + 2]) << 8) |
            @as(i32, operands[offset + 3]);
        offset += 4;

        var target_offset: i32 = default_offset;

        // 检查索引是否在范围内
        if (index >= low and index <= high) {
            const table_index = @as(usize, @intCast(index - low));
            const table_offset = offset + table_index * 4;

            if (table_offset + 4 <= operands.len) {
                target_offset = (@as(i32, operands[table_offset]) << 24) |
                    (@as(i32, operands[table_offset + 1]) << 16) |
                    (@as(i32, operands[table_offset + 2]) << 8) |
                    @as(i32, operands[table_offset + 3]);
            }
        }

        const target_pc = @as(u32, @intCast(@as(i32, @intCast(pc)) + target_offset));

        return BranchResult{
            .should_branch = true,
            .target_pc = target_pc,
            .next_pc = target_pc,
        };
    }

    /// 处理 lookupswitch 指令
    pub fn processLookupSwitch(
        self: *ControlFlowProcessor,
        pc: u32,
        operands: []const u8,
        operand_stack: *OperandStack,
    ) ControlFlowError!BranchResult {
        _ = self;

        if (operands.len < 8) return ControlFlowError.InvalidBranchTarget;

        const key_value = try operand_stack.pop();
        const key = key_value.toInt() catch return ControlFlowError.IncompatibleTypes;

        // 解析 lookupswitch 参数
        var offset: usize = 0;

        // 跳过填充字节，使得后续的 4 字节对齐
        const padding = (4 - ((pc + 1) % 4)) % 4;
        offset += padding;

        if (offset + 8 > operands.len) return ControlFlowError.InvalidBranchTarget;

        // 读取默认跳转偏移
        const default_offset = (@as(i32, operands[offset]) << 24) |
            (@as(i32, operands[offset + 1]) << 16) |
            (@as(i32, operands[offset + 2]) << 8) |
            @as(i32, operands[offset + 3]);
        offset += 4;

        // 读取匹配对数量
        const npairs = (@as(u32, operands[offset]) << 24) |
            (@as(u32, operands[offset + 1]) << 16) |
            (@as(u32, operands[offset + 2]) << 8) |
            @as(u32, operands[offset + 3]);
        offset += 4;

        var target_offset: i32 = default_offset;

        // 查找匹配的键值对
        var i: u32 = 0;
        while (i < npairs) : (i += 1) {
            if (offset + 8 > operands.len) break;

            // 读取匹配值
            const match_value = (@as(i32, operands[offset]) << 24) |
                (@as(i32, operands[offset + 1]) << 16) |
                (@as(i32, operands[offset + 2]) << 8) |
                @as(i32, operands[offset + 3]);
            offset += 4;

            // 读取跳转偏移
            const jump_offset = (@as(i32, operands[offset]) << 24) |
                (@as(i32, operands[offset + 1]) << 16) |
                (@as(i32, operands[offset + 2]) << 8) |
                @as(i32, operands[offset + 3]);
            offset += 4;

            if (key == match_value) {
                target_offset = jump_offset;
                break;
            }
        }

        const target_pc = @as(u32, @intCast(@as(i32, @intCast(pc)) + target_offset));

        return BranchResult{
            .should_branch = true,
            .target_pc = target_pc,
            .next_pc = target_pc,
        };
    }

    /// 检查是否为分支指令
    pub fn isBranchInstruction(opcode: Opcode) bool {
        return switch (opcode) {
            .goto, .goto_w, .ifeq, .ifne, .iflt, .ifge, .ifgt, .ifle, .if_icmpeq, .if_icmpne, .if_icmplt, .if_icmpge, .if_icmpgt, .if_icmple, .if_acmpeq, .if_acmpne, .ifnull, .ifnonnull, .tableswitch, .lookupswitch => true,
            else => false,
        };
    }

    /// 检查是否为条件分支指令
    pub fn isConditionalBranch(opcode: Opcode) bool {
        return switch (opcode) {
            .ifeq, .ifne, .iflt, .ifge, .ifgt, .ifle, .if_icmpeq, .if_icmpne, .if_icmplt, .if_icmpge, .if_icmpgt, .if_icmple, .if_acmpeq, .if_acmpne, .ifnull, .ifnonnull => true,
            else => false,
        };
    }

    /// 检查是否为无条件跳转指令
    pub fn isUnconditionalJump(opcode: Opcode) bool {
        return switch (opcode) {
            .goto, .goto_w => true,
            else => false,
        };
    }

    /// 检查是否为 switch 指令
    pub fn isSwitchInstruction(opcode: Opcode) bool {
        return switch (opcode) {
            .tableswitch, .lookupswitch => true,
            else => false,
        };
    }
};
