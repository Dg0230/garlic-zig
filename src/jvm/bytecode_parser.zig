//! JVM 字节码解析器
//! 解析 class 文件中的字节码指令序列

const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const instructions = @import("instructions.zig");

const Opcode = instructions.Opcode;

/// 字节码解析错误类型
pub const ParseError = error{
    InvalidOpcode,
    UnexpectedEndOfCode,
    InvalidOperand,
    OutOfMemory,
};

/// 字节码指令
pub const BytecodeInstruction = struct {
    opcode: Opcode,
    pc: u32, // 程序计数器位置
    operands: []const u8, // 操作数
    length: u8, // 指令总长度（包括操作码和操作数）

    pub fn format(self: BytecodeInstruction, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;

        try writer.print("{d:4}: {s}", .{ self.pc, @tagName(self.opcode) });

        if (self.operands.len > 0) {
            try writer.print(" [", .{});
            for (self.operands, 0..) |operand, i| {
                if (i > 0) try writer.print(", ", .{});
                try writer.print("{d}", .{operand});
            }
            try writer.print("]", .{});
        }
    }
};

/// 字节码解析器
pub const BytecodeParser = struct {
    allocator: Allocator,

    pub fn init(allocator: Allocator) BytecodeParser {
        return BytecodeParser{
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *BytecodeParser) void {
        _ = self;
    }

    /// 解析字节码序列
    pub fn parseCode(self: *BytecodeParser, code: []const u8) ParseError!ArrayList(BytecodeInstruction) {
        var instructions_list = ArrayList(BytecodeInstruction).init(self.allocator);
        errdefer instructions_list.deinit();

        var pc: u32 = 0;

        while (pc < code.len) {
            const instruction = try self.parseInstruction(code, pc);
            try instructions_list.append(instruction);
            pc += instruction.length;
        }

        return instructions_list;
    }

    /// 解析单条指令
    pub fn parseInstruction(self: *BytecodeParser, code: []const u8, pc: u32) ParseError!BytecodeInstruction {
        if (pc >= code.len) return ParseError.UnexpectedEndOfCode;

        const opcode_byte = code[pc];
        const opcode = std.meta.intToEnum(Opcode, opcode_byte) catch return ParseError.InvalidOpcode;

        const operand_count = getOperandCount(opcode);
        const instruction_length = 1 + operand_count;

        if (pc + instruction_length > code.len) {
            return ParseError.UnexpectedEndOfCode;
        }

        // 复制操作数
        var operands: []u8 = undefined;
        if (operand_count > 0) {
            operands = try self.allocator.alloc(u8, operand_count);
            @memcpy(operands, code[pc + 1 .. pc + 1 + operand_count]);
        } else {
            operands = &[_]u8{};
        }

        return BytecodeInstruction{
            .opcode = opcode,
            .pc = pc,
            .operands = operands,
            .length = instruction_length,
        };
    }

    /// 释放指令列表中的操作数内存
    pub fn freeInstructions(self: *BytecodeParser, instructions_list: *ArrayList(BytecodeInstruction)) void {
        for (instructions_list.items) |instruction| {
            if (instruction.operands.len > 0) {
                self.allocator.free(instruction.operands);
            }
        }
        instructions_list.deinit();
    }

    /// 查找指令在列表中的索引
    pub fn findInstructionIndex(instructions_list: []const BytecodeInstruction, target_pc: u32) ?usize {
        for (instructions_list, 0..) |instruction, i| {
            if (instruction.pc == target_pc) {
                return i;
            }
        }
        return null;
    }

    /// 获取指令的操作数数量
    fn getOperandCount(opcode: Opcode) u8 {
        return switch (opcode) {
            // 无操作数指令
            .nop, .aconst_null, .iconst_m1, .iconst_0, .iconst_1, .iconst_2, .iconst_3, .iconst_4, .iconst_5, .lconst_0, .lconst_1, .fconst_0, .fconst_1, .fconst_2, .dconst_0, .dconst_1, .iload_0, .iload_1, .iload_2, .iload_3, .lload_0, .lload_1, .lload_2, .lload_3, .fload_0, .fload_1, .fload_2, .fload_3, .dload_0, .dload_1, .dload_2, .dload_3, .aload_0, .aload_1, .aload_2, .aload_3, .iaload, .laload, .faload, .daload, .aaload, .baload, .caload, .saload, .istore_0, .istore_1, .istore_2, .istore_3, .lstore_0, .lstore_1, .lstore_2, .lstore_3, .fstore_0, .fstore_1, .fstore_2, .fstore_3, .dstore_0, .dstore_1, .dstore_2, .dstore_3, .astore_0, .astore_1, .astore_2, .astore_3, .iastore, .lastore, .fastore, .dastore, .aastore, .bastore, .castore, .sastore, .pop, .pop2, .dup, .dup_x1, .dup_x2, .dup2, .dup2_x1, .dup2_x2, .swap, .iadd, .ladd, .fadd, .dadd, .isub, .lsub, .fsub, .dsub, .imul, .lmul, .fmul, .dmul, .idiv, .ldiv, .fdiv, .ddiv, .irem, .lrem, .frem, .drem, .ineg, .lneg, .fneg, .dneg, .ishl, .lshl, .ishr, .lshr, .iushr, .lushr, .iand, .land, .ior, .lor, .ixor, .lxor, .i2l, .i2f, .i2d, .l2i, .l2f, .l2d, .f2i, .f2l, .f2d, .d2i, .d2l, .d2f, .i2b, .i2c, .i2s, .lcmp, .fcmpl, .fcmpg, .dcmpl, .dcmpg, .ireturn, .lreturn, .freturn, .dreturn, .areturn, .@"return", .arraylength, .athrow, .monitorenter, .monitorexit => 0,

            // 单字节操作数指令
            .bipush, .ldc, .iload, .lload, .fload, .dload, .aload, .istore, .lstore, .fstore, .dstore, .astore, .ret => 1,

            // 双字节操作数指令
            .sipush, .ldc_w, .ldc2_w, .iinc, .ifeq, .ifne, .iflt, .ifge, .ifgt, .ifle, .if_icmpeq, .if_icmpne, .if_icmplt, .if_icmpge, .if_icmpgt, .if_icmple, .if_acmpeq, .if_acmpne, .goto, .jsr, .ifnull, .ifnonnull, .getstatic, .putstatic, .getfield, .putfield, .invokevirtual, .invokespecial, .invokestatic, .new, .newarray, .anewarray, .checkcast, .instanceof, .goto_w, .jsr_w => 2,

            // 三字节操作数指令
            .multianewarray => 3,

            // 四字节操作数指令
            .invokeinterface => 4,

            // 五字节操作数指令
            .invokedynamic => 4,

            // 可变长度指令（这里返回最小长度，实际解析时需要特殊处理）
            .tableswitch, .lookupswitch => 0, // 需要特殊处理

            // wide 指令（需要特殊处理）
            .wide => 0, // 需要特殊处理

            // 调试指令
            .breakpoint => 0,

            // 实现相关指令（通常不使用）
            .impdep1, .impdep2 => 0,

            // 未知指令
            else => 0,
        };
    }

    /// 解析可变长度指令（tableswitch, lookupswitch, wide）
    pub fn parseVariableLengthInstruction(
        self: *BytecodeParser,
        code: []const u8,
        pc: u32,
        opcode: Opcode,
    ) ParseError!BytecodeInstruction {
        switch (opcode) {
            .tableswitch => return self.parseTableSwitch(code, pc),
            .lookupswitch => return self.parseLookupSwitch(code, pc),
            .wide => return self.parseWideInstruction(code, pc),
            else => return ParseError.InvalidOpcode,
        }
    }

    /// 解析 tableswitch 指令
    fn parseTableSwitch(self: *BytecodeParser, code: []const u8, pc: u32) ParseError!BytecodeInstruction {
        if (pc >= code.len) return ParseError.UnexpectedEndOfCode;

        var offset: u32 = 1; // 跳过 opcode

        // 计算填充字节数，使得后续的 4 字节对齐
        const padding = (4 - ((pc + 1) % 4)) % 4;
        offset += padding;

        if (pc + offset + 12 > code.len) return ParseError.UnexpectedEndOfCode;

        // 跳过 default, low, high (3 * 4 bytes)
        offset += 12;

        // 读取 low 和 high 值来计算表的大小
        const low_offset = 1 + padding + 4; // 跳过 opcode, padding, default
        const high_offset = low_offset + 4;

        const low = (@as(i32, code[pc + low_offset]) << 24) |
            (@as(i32, code[pc + low_offset + 1]) << 16) |
            (@as(i32, code[pc + low_offset + 2]) << 8) |
            @as(i32, code[pc + low_offset + 3]);

        const high = (@as(i32, code[pc + high_offset]) << 24) |
            (@as(i32, code[pc + high_offset + 1]) << 16) |
            (@as(i32, code[pc + high_offset + 2]) << 8) |
            @as(i32, code[pc + high_offset + 3]);

        const table_size = @as(u32, @intCast(high - low + 1));
        offset += table_size * 4; // 每个表项 4 字节

        if (pc + offset > code.len) return ParseError.UnexpectedEndOfCode;

        const operands = try self.allocator.alloc(u8, offset - 1);
        @memcpy(operands, code[pc + 1 .. pc + offset]);

        return BytecodeInstruction{
            .opcode = .tableswitch,
            .pc = pc,
            .operands = operands,
            .length = @intCast(offset),
        };
    }

    /// 解析 lookupswitch 指令
    fn parseLookupSwitch(self: *BytecodeParser, code: []const u8, pc: u32) ParseError!BytecodeInstruction {
        if (pc >= code.len) return ParseError.UnexpectedEndOfCode;

        var offset: u32 = 1; // 跳过 opcode

        // 计算填充字节数，使得后续的 4 字节对齐
        const padding = (4 - ((pc + 1) % 4)) % 4;
        offset += padding;

        if (pc + offset + 8 > code.len) return ParseError.UnexpectedEndOfCode;

        // 跳过 default (4 bytes)
        offset += 4;

        // 读取 npairs
        const npairs_offset = 1 + padding + 4;
        const npairs = (@as(u32, code[pc + npairs_offset]) << 24) |
            (@as(u32, code[pc + npairs_offset + 1]) << 16) |
            (@as(u32, code[pc + npairs_offset + 2]) << 8) |
            @as(u32, code[pc + npairs_offset + 3]);

        offset += 4; // npairs 字段
        offset += npairs * 8; // 每个匹配对 8 字节 (match + offset)

        if (pc + offset > code.len) return ParseError.UnexpectedEndOfCode;

        const operands = try self.allocator.alloc(u8, offset - 1);
        @memcpy(operands, code[pc + 1 .. pc + offset]);

        return BytecodeInstruction{
            .opcode = .lookupswitch,
            .pc = pc,
            .operands = operands,
            .length = @intCast(offset),
        };
    }

    /// 解析 wide 指令
    fn parseWideInstruction(self: *BytecodeParser, code: []const u8, pc: u32) ParseError!BytecodeInstruction {
        if (pc + 2 >= code.len) return ParseError.UnexpectedEndOfCode;

        const modified_opcode = code[pc + 1];
        var length: u8 = 3; // wide + opcode + index (2 bytes)

        // iinc 指令需要额外的 2 字节常量
        if (modified_opcode == @intFromEnum(Opcode.iinc)) {
            length = 5; // wide + iinc + index (2 bytes) + const (2 bytes)
        }

        if (pc + length > code.len) return ParseError.UnexpectedEndOfCode;

        const operands = try self.allocator.alloc(u8, length - 1);
        @memcpy(operands, code[pc + 1 .. pc + length]);

        return BytecodeInstruction{
            .opcode = .wide,
            .pc = pc,
            .operands = operands,
            .length = length,
        };
    }

    /// 打印指令列表（用于调试）
    pub fn printInstructions(instructions_list: []const BytecodeInstruction, writer: anytype) !void {
        try writer.print("Bytecode Instructions:\n", .{});
        try writer.print("=====================\n", .{});

        for (instructions_list) |instruction| {
            try writer.print("{any}\n", .{instruction});
        }

        try writer.print("\nTotal instructions: {d}\n", .{instructions_list.len});
    }
};
