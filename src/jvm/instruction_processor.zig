//! JVM 字节码指令处理器
//! 实现具体的指令执行逻辑，包括算术、比较、栈操作和局部变量指令

const std = @import("std");
const Allocator = std.mem.Allocator;
const instructions = @import("instructions.zig");
const stack = @import("stack.zig");
const locals = @import("locals.zig");
const method_call_processor = @import("method_call_processor.zig");
const control_flow_processor = @import("control_flow_processor.zig");

const Opcode = instructions.Opcode;
const OperandStack = stack.OperandStack;
const LocalVariableTable = locals.LocalVariableTable;
const StackValue = stack.StackValue;
const ValueType = stack.ValueType;
const MethodCallProcessor = method_call_processor.MethodCallProcessor;
const ControlFlowProcessor = control_flow_processor.ControlFlowProcessor;

/// 指令处理错误类型
pub const ProcessorError = error{
    InvalidInstruction,
    StackUnderflow,
    StackOverflow,
    TypeMismatch,
    DivisionByZero,
    InvalidLocalIndex,
    IncompatibleTypes,
    InvalidBranchTarget,
    InvalidCondition,
    InvalidOperation,
    InvalidMethodReference,
    MethodNotFound,
    InvalidSignature,
    InvalidConversion,
    IndexOutOfBounds,
    InvalidSlotAccess,
    UninitializedVariable,
    OutOfMemory,
};

/// 指令执行结果
pub const ExecutionResult = struct {
    next_pc: u32, // 下一条指令的程序计数器
    should_return: bool = false, // 是否应该返回
    return_value: ?StackValue = null, // 返回值（如果有）
    exception: ?StackValue = null, // 异常值（如果有）
    branch_target: ?u32 = null, // 分支目标地址（如果有）
};

/// 字节码指令处理器
pub const InstructionProcessor = struct {
    allocator: Allocator,
    method_call_processor: MethodCallProcessor,
    control_flow_processor: ControlFlowProcessor,

    pub fn init(allocator: Allocator) !InstructionProcessor {
        return InstructionProcessor{
            .allocator = allocator,
            .method_call_processor = try MethodCallProcessor.init(allocator),
            .control_flow_processor = ControlFlowProcessor.init(allocator),
        };
    }

    pub fn deinit(self: *InstructionProcessor) void {
        self.method_call_processor.deinit();
        self.control_flow_processor.deinit();
    }

    /// 执行单条指令
    pub fn executeInstruction(
        self: *InstructionProcessor,
        opcode: Opcode,
        operands: []const u8,
        pc: u32,
        operand_stack: *OperandStack,
        local_vars: *LocalVariableTable,
    ) ProcessorError!ExecutionResult {
        return switch (opcode) {
            // 常量指令
            .nop => self.executeNop(pc),
            .aconst_null => self.executeAconstNull(pc, operand_stack),
            .iconst_m1 => self.executeIconst(pc, operand_stack, -1),
            .iconst_0 => self.executeIconst(pc, operand_stack, 0),
            .iconst_1 => self.executeIconst(pc, operand_stack, 1),
            .iconst_2 => self.executeIconst(pc, operand_stack, 2),
            .iconst_3 => self.executeIconst(pc, operand_stack, 3),
            .iconst_4 => self.executeIconst(pc, operand_stack, 4),
            .iconst_5 => self.executeIconst(pc, operand_stack, 5),
            .bipush => self.executeBipush(pc, operands, operand_stack),
            .sipush => self.executeSipush(pc, operands, operand_stack),

            // 局部变量加载指令
            .iload => self.executeIload(pc, operands, operand_stack, local_vars),
            .iload_0 => self.executeIloadN(pc, operand_stack, local_vars, 0),
            .iload_1 => self.executeIloadN(pc, operand_stack, local_vars, 1),
            .iload_2 => self.executeIloadN(pc, operand_stack, local_vars, 2),
            .iload_3 => self.executeIloadN(pc, operand_stack, local_vars, 3),
            .aload => self.executeAload(pc, operands, operand_stack, local_vars),
            .aload_0 => self.executeAloadN(pc, operand_stack, local_vars, 0),
            .aload_1 => self.executeAloadN(pc, operand_stack, local_vars, 1),
            .aload_2 => self.executeAloadN(pc, operand_stack, local_vars, 2),
            .aload_3 => self.executeAloadN(pc, operand_stack, local_vars, 3),

            // 局部变量存储指令
            .istore => self.executeIstore(pc, operands, operand_stack, local_vars),
            .istore_0 => self.executeIstoreN(pc, operand_stack, local_vars, 0),
            .istore_1 => self.executeIstoreN(pc, operand_stack, local_vars, 1),
            .istore_2 => self.executeIstoreN(pc, operand_stack, local_vars, 2),
            .istore_3 => self.executeIstoreN(pc, operand_stack, local_vars, 3),
            .astore => self.executeAstore(pc, operands, operand_stack, local_vars),
            .astore_0 => self.executeAstoreN(pc, operand_stack, local_vars, 0),
            .astore_1 => self.executeAstoreN(pc, operand_stack, local_vars, 1),
            .astore_2 => self.executeAstoreN(pc, operand_stack, local_vars, 2),
            .astore_3 => self.executeAstoreN(pc, operand_stack, local_vars, 3),

            // 栈操作指令
            .pop => self.executePop(pc, operand_stack),
            .pop2 => self.executePop2(pc, operand_stack),
            .dup => self.executeDup(pc, operand_stack),
            .dup_x1 => self.executeDupX1(pc, operand_stack),
            .dup_x2 => self.executeDupX2(pc, operand_stack),
            .dup2 => self.executeDup2(pc, operand_stack),
            .swap => self.executeSwap(pc, operand_stack),

            // 算术指令
            .iadd => self.executeIadd(pc, operand_stack),
            .isub => self.executeIsub(pc, operand_stack),
            .imul => self.executeImul(pc, operand_stack),
            .idiv => self.executeIdiv(pc, operand_stack),
            .irem => self.executeIrem(pc, operand_stack),
            .ineg => self.executeIneg(pc, operand_stack),
            .iand => self.executeIand(pc, operand_stack),
            .ior => self.executeIor(pc, operand_stack),
            .ixor => self.executeIxor(pc, operand_stack),
            .ishl => self.executeIshl(pc, operand_stack),
            .ishr => self.executeIshr(pc, operand_stack),
            .iushr => self.executeIushr(pc, operand_stack),

            // 比较指令
            .ifeq => self.executeIfeq(pc, operands, operand_stack),
            .ifne => self.executeIfne(pc, operands, operand_stack),
            .iflt => self.executeIflt(pc, operands, operand_stack),
            .ifge => self.executeIfge(pc, operands, operand_stack),
            .ifgt => self.executeIfgt(pc, operands, operand_stack),
            .ifle => self.executeIfle(pc, operands, operand_stack),
            .if_icmpeq => self.executeIfIcmpeq(pc, operands, operand_stack),
            .if_icmpne => self.executeIfIcmpne(pc, operands, operand_stack),
            .if_icmplt => self.executeIfIcmplt(pc, operands, operand_stack),
            .if_icmpge => self.executeIfIcmpge(pc, operands, operand_stack),
            .if_icmpgt => self.executeIfIcmpgt(pc, operands, operand_stack),
            .if_icmple => self.executeIfIcmple(pc, operands, operand_stack),
            .if_acmpeq => self.executeIfAcmpeq(pc, operands, operand_stack),
            .if_acmpne => self.executeIfAcmpne(pc, operands, operand_stack),

            // 控制流指令
            .goto => self.executeGoto(pc, operands),
            .@"return" => self.executeReturn(pc),
            .ireturn => self.executeIreturn(pc, operand_stack),
            .areturn => self.executeAreturn(pc, operand_stack),
            .tableswitch => self.executeTableSwitch(pc, operands, operand_stack),
            .lookupswitch => self.executeLookupSwitch(pc, operands, operand_stack),
            .ifnull, .ifnonnull => self.executeConditionalBranch(opcode, pc, operands, operand_stack),

            // 方法调用指令
            .invokevirtual => self.executeInvokeVirtual(pc, operands, operand_stack),
            .invokespecial => self.executeInvokeSpecial(pc, operands, operand_stack),
            .invokestatic => self.executeInvokeStatic(pc, operands, operand_stack),
            .invokeinterface => self.executeInvokeInterface(pc, operands, operand_stack),

            else => ProcessorError.InvalidInstruction,
        };
    }

    // ==================== 常量指令实现 ====================

    fn executeNop(self: *InstructionProcessor, pc: u32) ProcessorError!ExecutionResult {
        _ = self;
        return ExecutionResult{ .next_pc = pc + 1 };
    }

    fn executeAconstNull(self: *InstructionProcessor, pc: u32, operand_stack: *OperandStack) ProcessorError!ExecutionResult {
        _ = self;
        try operand_stack.push(StackValue{ .reference = null });
        return ExecutionResult{ .next_pc = pc + 1 };
    }

    fn executeIconst(self: *InstructionProcessor, pc: u32, operand_stack: *OperandStack, value: i32) ProcessorError!ExecutionResult {
        _ = self;
        try operand_stack.push(StackValue{ .int = value });
        return ExecutionResult{ .next_pc = pc + 1 };
    }

    fn executeBipush(self: *InstructionProcessor, pc: u32, operands: []const u8, operand_stack: *OperandStack) ProcessorError!ExecutionResult {
        _ = self;
        if (operands.len < 1) return ProcessorError.InvalidInstruction;
        const value = @as(i8, @bitCast(operands[0]));
        try operand_stack.push(StackValue{ .int = @as(i32, value) });
        return ExecutionResult{ .next_pc = pc + 2 };
    }

    fn executeSipush(self: *InstructionProcessor, pc: u32, operands: []const u8, operand_stack: *OperandStack) ProcessorError!ExecutionResult {
        _ = self;
        if (operands.len < 2) return ProcessorError.InvalidInstruction;
        const value = (@as(i16, operands[0]) << 8) | @as(i16, operands[1]);
        try operand_stack.push(StackValue{ .int = @as(i32, value) });
        return ExecutionResult{ .next_pc = pc + 3 };
    }

    // ==================== 局部变量加载指令实现 ====================

    fn executeIload(self: *InstructionProcessor, pc: u32, operands: []const u8, operand_stack: *OperandStack, local_vars: *LocalVariableTable) ProcessorError!ExecutionResult {
        _ = self;
        if (operands.len < 1) return ProcessorError.InvalidInstruction;
        const index = operands[0];
        const value = try local_vars.getInt(index);
        try operand_stack.push(StackValue{ .int = value });
        return ExecutionResult{ .next_pc = pc + 2 };
    }

    fn executeIloadN(self: *InstructionProcessor, pc: u32, operand_stack: *OperandStack, local_vars: *LocalVariableTable, index: u8) ProcessorError!ExecutionResult {
        _ = self;
        const value = try local_vars.getInt(index);
        try operand_stack.push(StackValue{ .int = value });
        return ExecutionResult{ .next_pc = pc + 1 };
    }

    fn executeAload(self: *InstructionProcessor, pc: u32, operands: []const u8, operand_stack: *OperandStack, local_vars: *LocalVariableTable) ProcessorError!ExecutionResult {
        _ = self;
        if (operands.len < 1) return ProcessorError.InvalidInstruction;
        const index = operands[0];
        const value = try local_vars.getReference(index);
        try operand_stack.push(StackValue{ .reference = value });
        return ExecutionResult{ .next_pc = pc + 2 };
    }

    fn executeAloadN(self: *InstructionProcessor, pc: u32, operand_stack: *OperandStack, local_vars: *LocalVariableTable, index: u8) ProcessorError!ExecutionResult {
        _ = self;
        const value = try local_vars.getReference(index);
        try operand_stack.push(StackValue{ .reference = value });
        return ExecutionResult{ .next_pc = pc + 1 };
    }

    // ==================== 局部变量存储指令实现 ====================

    fn executeIstore(self: *InstructionProcessor, pc: u32, operands: []const u8, operand_stack: *OperandStack, local_vars: *LocalVariableTable) ProcessorError!ExecutionResult {
        _ = self;
        if (operands.len < 1) return ProcessorError.InvalidInstruction;
        const index = operands[0];
        const value = try operand_stack.pop();
        const int_value = try value.toInt();
        try local_vars.setInt(index, int_value);
        return ExecutionResult{ .next_pc = pc + 2 };
    }

    fn executeIstoreN(self: *InstructionProcessor, pc: u32, operand_stack: *OperandStack, local_vars: *LocalVariableTable, index: u8) ProcessorError!ExecutionResult {
        _ = self;
        const value = try operand_stack.pop();
        const int_value = try value.toInt();
        try local_vars.setInt(index, int_value);
        return ExecutionResult{ .next_pc = pc + 1 };
    }

    fn executeAstore(self: *InstructionProcessor, pc: u32, operands: []const u8, operand_stack: *OperandStack, local_vars: *LocalVariableTable) ProcessorError!ExecutionResult {
        _ = self;
        if (operands.len < 1) return ProcessorError.InvalidInstruction;
        const index = operands[0];
        const value = try operand_stack.pop();
        const ref_value = try value.toReference();
        try local_vars.setReference(index, ref_value);
        return ExecutionResult{ .next_pc = pc + 2 };
    }

    fn executeAstoreN(self: *InstructionProcessor, pc: u32, operand_stack: *OperandStack, local_vars: *LocalVariableTable, index: u8) ProcessorError!ExecutionResult {
        _ = self;
        const value = try operand_stack.pop();
        const ref_value = try value.toReference();
        try local_vars.setReference(index, ref_value);
        return ExecutionResult{ .next_pc = pc + 1 };
    }

    // ==================== 栈操作指令实现 ====================

    fn executePop(self: *InstructionProcessor, pc: u32, operand_stack: *OperandStack) ProcessorError!ExecutionResult {
        _ = self;
        _ = try operand_stack.pop();
        return ExecutionResult{ .next_pc = pc + 1 };
    }

    fn executePop2(self: *InstructionProcessor, pc: u32, operand_stack: *OperandStack) ProcessorError!ExecutionResult {
        _ = self;
        const value1 = try operand_stack.pop();
        if (value1.isCategory2()) {
            // 弹出一个类型2值
        } else {
            // 弹出两个类型1值
            _ = try operand_stack.pop();
        }
        return ExecutionResult{ .next_pc = pc + 1 };
    }

    fn executeDup(self: *InstructionProcessor, pc: u32, operand_stack: *OperandStack) ProcessorError!ExecutionResult {
        _ = self;
        const value = try operand_stack.peek();
        try operand_stack.push(value);
        return ExecutionResult{ .next_pc = pc + 1 };
    }

    fn executeDupX1(self: *InstructionProcessor, pc: u32, operand_stack: *OperandStack) ProcessorError!ExecutionResult {
        _ = self;
        const value1 = try operand_stack.pop();
        const value2 = try operand_stack.pop();
        try operand_stack.push(value1);
        try operand_stack.push(value2);
        try operand_stack.push(value1);
        return ExecutionResult{ .next_pc = pc + 1 };
    }

    fn executeDupX2(self: *InstructionProcessor, pc: u32, operand_stack: *OperandStack) ProcessorError!ExecutionResult {
        _ = self;
        const value1 = try operand_stack.pop();
        const value2 = try operand_stack.pop();

        if (value2.isCategory2()) {
            // 形式2: value1, value2 -> value1, value2, value1
            try operand_stack.push(value1);
            try operand_stack.push(value2);
            try operand_stack.push(value1);
        } else {
            // 形式1: value1, value2, value3 -> value1, value3, value2, value1
            const value3 = try operand_stack.pop();
            try operand_stack.push(value1);
            try operand_stack.push(value3);
            try operand_stack.push(value2);
            try operand_stack.push(value1);
        }
        return ExecutionResult{ .next_pc = pc + 1 };
    }

    fn executeDup2(self: *InstructionProcessor, pc: u32, operand_stack: *OperandStack) ProcessorError!ExecutionResult {
        _ = self;
        const value1 = try operand_stack.pop();

        if (value1.isCategory2()) {
            // 形式2: 复制一个类型2值
            try operand_stack.push(value1);
            try operand_stack.push(value1);
        } else {
            // 形式1: 复制两个类型1值
            const value2 = try operand_stack.pop();
            try operand_stack.push(value2);
            try operand_stack.push(value1);
            try operand_stack.push(value2);
            try operand_stack.push(value1);
        }
        return ExecutionResult{ .next_pc = pc + 1 };
    }

    fn executeSwap(self: *InstructionProcessor, pc: u32, operand_stack: *OperandStack) ProcessorError!ExecutionResult {
        _ = self;
        const value1 = try operand_stack.pop();
        const value2 = try operand_stack.pop();
        try operand_stack.push(value1);
        try operand_stack.push(value2);
        return ExecutionResult{ .next_pc = pc + 1 };
    }

    // ==================== 算术指令实现 ====================

    fn executeIadd(self: *InstructionProcessor, pc: u32, operand_stack: *OperandStack) ProcessorError!ExecutionResult {
        _ = self;
        const value2 = try operand_stack.pop();
        const value1 = try operand_stack.pop();
        const int1 = try value1.toInt();
        const int2 = try value2.toInt();
        const result = int1 +% int2; // 使用溢出包装加法
        try operand_stack.push(StackValue{ .int = result });
        return ExecutionResult{ .next_pc = pc + 1 };
    }

    fn executeIsub(self: *InstructionProcessor, pc: u32, operand_stack: *OperandStack) ProcessorError!ExecutionResult {
        _ = self;
        const value2 = try operand_stack.pop();
        const value1 = try operand_stack.pop();
        const int1 = try value1.toInt();
        const int2 = try value2.toInt();
        const result = int1 -% int2; // 使用溢出包装减法
        try operand_stack.push(StackValue{ .int = result });
        return ExecutionResult{ .next_pc = pc + 1 };
    }

    fn executeImul(self: *InstructionProcessor, pc: u32, operand_stack: *OperandStack) ProcessorError!ExecutionResult {
        _ = self;
        const value2 = try operand_stack.pop();
        const value1 = try operand_stack.pop();
        const int1 = try value1.toInt();
        const int2 = try value2.toInt();
        const result = int1 *% int2; // 使用溢出包装乘法
        try operand_stack.push(StackValue{ .int = result });
        return ExecutionResult{ .next_pc = pc + 1 };
    }

    fn executeIdiv(self: *InstructionProcessor, pc: u32, operand_stack: *OperandStack) ProcessorError!ExecutionResult {
        _ = self;
        const value2 = try operand_stack.pop();
        const value1 = try operand_stack.pop();
        const int1 = try value1.toInt();
        const int2 = try value2.toInt();

        if (int2 == 0) {
            return ProcessorError.DivisionByZero;
        }

        const result = @divTrunc(int1, int2);
        try operand_stack.push(StackValue{ .int = result });
        return ExecutionResult{ .next_pc = pc + 1 };
    }

    fn executeIrem(self: *InstructionProcessor, pc: u32, operand_stack: *OperandStack) ProcessorError!ExecutionResult {
        _ = self;
        const value2 = try operand_stack.pop();
        const value1 = try operand_stack.pop();
        const int1 = try value1.toInt();
        const int2 = try value2.toInt();

        if (int2 == 0) {
            return ProcessorError.DivisionByZero;
        }

        const result = @rem(int1, int2);
        try operand_stack.push(StackValue{ .int = result });
        return ExecutionResult{ .next_pc = pc + 1 };
    }

    fn executeIneg(self: *InstructionProcessor, pc: u32, operand_stack: *OperandStack) ProcessorError!ExecutionResult {
        _ = self;
        const value = try operand_stack.pop();
        const int_value = try value.toInt();
        const result = -%int_value; // 使用溢出包装取负
        try operand_stack.push(StackValue{ .int = result });
        return ExecutionResult{ .next_pc = pc + 1 };
    }

    fn executeIand(self: *InstructionProcessor, pc: u32, operand_stack: *OperandStack) ProcessorError!ExecutionResult {
        _ = self;
        const value2 = try operand_stack.pop();
        const value1 = try operand_stack.pop();
        const int1 = try value1.toInt();
        const int2 = try value2.toInt();
        const result = int1 & int2;
        try operand_stack.push(StackValue{ .int = result });
        return ExecutionResult{ .next_pc = pc + 1 };
    }

    fn executeIor(self: *InstructionProcessor, pc: u32, operand_stack: *OperandStack) ProcessorError!ExecutionResult {
        _ = self;
        const value2 = try operand_stack.pop();
        const value1 = try operand_stack.pop();
        const int1 = try value1.toInt();
        const int2 = try value2.toInt();
        const result = int1 | int2;
        try operand_stack.push(StackValue{ .int = result });
        return ExecutionResult{ .next_pc = pc + 1 };
    }

    fn executeIxor(self: *InstructionProcessor, pc: u32, operand_stack: *OperandStack) ProcessorError!ExecutionResult {
        _ = self;
        const value2 = try operand_stack.pop();
        const value1 = try operand_stack.pop();
        const int1 = try value1.toInt();
        const int2 = try value2.toInt();
        const result = int1 ^ int2;
        try operand_stack.push(StackValue{ .int = result });
        return ExecutionResult{ .next_pc = pc + 1 };
    }

    fn executeIshl(self: *InstructionProcessor, pc: u32, operand_stack: *OperandStack) ProcessorError!ExecutionResult {
        _ = self;
        const value2 = try operand_stack.pop();
        const value1 = try operand_stack.pop();
        const int1 = try value1.toInt();
        const int2 = try value2.toInt();
        const shift_amount = @as(u5, @intCast(int2 & 0x1f)); // 只使用低5位
        const result = int1 << shift_amount;
        try operand_stack.push(StackValue{ .int = result });
        return ExecutionResult{ .next_pc = pc + 1 };
    }

    fn executeIshr(self: *InstructionProcessor, pc: u32, operand_stack: *OperandStack) ProcessorError!ExecutionResult {
        _ = self;
        const value2 = try operand_stack.pop();
        const value1 = try operand_stack.pop();
        const int1 = try value1.toInt();
        const int2 = try value2.toInt();
        const shift_amount = @as(u5, @intCast(int2 & 0x1f)); // 只使用低5位
        const result = int1 >> shift_amount;
        try operand_stack.push(StackValue{ .int = result });
        return ExecutionResult{ .next_pc = pc + 1 };
    }

    fn executeIushr(self: *InstructionProcessor, pc: u32, operand_stack: *OperandStack) ProcessorError!ExecutionResult {
        _ = self;
        const value2 = try operand_stack.pop();
        const value1 = try operand_stack.pop();
        const int1 = try value1.toInt();
        const int2 = try value2.toInt();
        const shift_amount = @as(u5, @intCast(int2 & 0x1f)); // 只使用低5位
        const uint1 = @as(u32, @bitCast(int1));
        const result = @as(i32, @bitCast(uint1 >> shift_amount));
        try operand_stack.push(StackValue{ .int = result });
        return ExecutionResult{ .next_pc = pc + 1 };
    }

    // ==================== 比较指令实现 ====================

    fn executeIfeq(self: *InstructionProcessor, pc: u32, operands: []const u8, operand_stack: *OperandStack) ProcessorError!ExecutionResult {
        _ = self;
        if (operands.len < 2) return ProcessorError.InvalidInstruction;
        const value = try operand_stack.pop();
        const int_value = try value.toInt();
        const offset = (@as(i16, operands[0]) << 8) | @as(i16, operands[1]);

        if (int_value == 0) {
            const target = @as(u32, @intCast(@as(i32, @intCast(pc)) + @as(i32, offset)));
            return ExecutionResult{ .next_pc = pc + 3, .branch_target = target };
        } else {
            return ExecutionResult{ .next_pc = pc + 3 };
        }
    }

    fn executeIfne(self: *InstructionProcessor, pc: u32, operands: []const u8, operand_stack: *OperandStack) ProcessorError!ExecutionResult {
        _ = self;
        if (operands.len < 2) return ProcessorError.InvalidInstruction;
        const value = try operand_stack.pop();
        const int_value = try value.toInt();
        const offset = (@as(i16, operands[0]) << 8) | @as(i16, operands[1]);

        if (int_value != 0) {
            const target = @as(u32, @intCast(@as(i32, @intCast(pc)) + @as(i32, offset)));
            return ExecutionResult{ .next_pc = pc + 3, .branch_target = target };
        } else {
            return ExecutionResult{ .next_pc = pc + 3 };
        }
    }

    fn executeIflt(self: *InstructionProcessor, pc: u32, operands: []const u8, operand_stack: *OperandStack) ProcessorError!ExecutionResult {
        _ = self;
        if (operands.len < 2) return ProcessorError.InvalidInstruction;
        const value = try operand_stack.pop();
        const int_value = try value.toInt();
        const offset = (@as(i16, operands[0]) << 8) | @as(i16, operands[1]);

        if (int_value < 0) {
            const target = @as(u32, @intCast(@as(i32, @intCast(pc)) + @as(i32, offset)));
            return ExecutionResult{ .next_pc = pc + 3, .branch_target = target };
        } else {
            return ExecutionResult{ .next_pc = pc + 3 };
        }
    }

    fn executeIfge(self: *InstructionProcessor, pc: u32, operands: []const u8, operand_stack: *OperandStack) ProcessorError!ExecutionResult {
        _ = self;
        if (operands.len < 2) return ProcessorError.InvalidInstruction;
        const value = try operand_stack.pop();
        const int_value = try value.toInt();
        const offset = (@as(i16, operands[0]) << 8) | @as(i16, operands[1]);

        if (int_value >= 0) {
            const target = @as(u32, @intCast(@as(i32, @intCast(pc)) + @as(i32, offset)));
            return ExecutionResult{ .next_pc = pc + 3, .branch_target = target };
        } else {
            return ExecutionResult{ .next_pc = pc + 3 };
        }
    }

    fn executeIfgt(self: *InstructionProcessor, pc: u32, operands: []const u8, operand_stack: *OperandStack) ProcessorError!ExecutionResult {
        _ = self;
        if (operands.len < 2) return ProcessorError.InvalidInstruction;
        const value = try operand_stack.pop();
        const int_value = try value.toInt();
        const offset = (@as(i16, operands[0]) << 8) | @as(i16, operands[1]);

        if (int_value > 0) {
            const target = @as(u32, @intCast(@as(i32, @intCast(pc)) + @as(i32, offset)));
            return ExecutionResult{ .next_pc = pc + 3, .branch_target = target };
        } else {
            return ExecutionResult{ .next_pc = pc + 3 };
        }
    }

    fn executeIfle(self: *InstructionProcessor, pc: u32, operands: []const u8, operand_stack: *OperandStack) ProcessorError!ExecutionResult {
        _ = self;
        if (operands.len < 2) return ProcessorError.InvalidInstruction;
        const value = try operand_stack.pop();
        const int_value = try value.toInt();
        const offset = (@as(i16, operands[0]) << 8) | @as(i16, operands[1]);

        if (int_value <= 0) {
            const target = @as(u32, @intCast(@as(i32, @intCast(pc)) + @as(i32, offset)));
            return ExecutionResult{ .next_pc = pc + 3, .branch_target = target };
        } else {
            return ExecutionResult{ .next_pc = pc + 3 };
        }
    }

    fn executeIfIcmpeq(self: *InstructionProcessor, pc: u32, operands: []const u8, operand_stack: *OperandStack) ProcessorError!ExecutionResult {
        _ = self;
        if (operands.len < 2) return ProcessorError.InvalidInstruction;
        const value2 = try operand_stack.pop();
        const value1 = try operand_stack.pop();
        const int1 = try value1.toInt();
        const int2 = try value2.toInt();
        const offset = (@as(i16, operands[0]) << 8) | @as(i16, operands[1]);

        if (int1 == int2) {
            const target = @as(u32, @intCast(@as(i32, @intCast(pc)) + @as(i32, offset)));
            return ExecutionResult{ .next_pc = pc + 3, .branch_target = target };
        } else {
            return ExecutionResult{ .next_pc = pc + 3 };
        }
    }

    fn executeIfIcmpne(self: *InstructionProcessor, pc: u32, operands: []const u8, operand_stack: *OperandStack) ProcessorError!ExecutionResult {
        _ = self;
        if (operands.len < 2) return ProcessorError.InvalidInstruction;
        const value2 = try operand_stack.pop();
        const value1 = try operand_stack.pop();
        const int1 = try value1.toInt();
        const int2 = try value2.toInt();
        const offset = (@as(i16, operands[0]) << 8) | @as(i16, operands[1]);

        if (int1 != int2) {
            const target = @as(u32, @intCast(@as(i32, @intCast(pc)) + @as(i32, offset)));
            return ExecutionResult{ .next_pc = pc + 3, .branch_target = target };
        } else {
            return ExecutionResult{ .next_pc = pc + 3 };
        }
    }

    fn executeIfIcmplt(self: *InstructionProcessor, pc: u32, operands: []const u8, operand_stack: *OperandStack) ProcessorError!ExecutionResult {
        _ = self;
        if (operands.len < 2) return ProcessorError.InvalidInstruction;
        const value2 = try operand_stack.pop();
        const value1 = try operand_stack.pop();
        const int1 = try value1.toInt();
        const int2 = try value2.toInt();
        const offset = (@as(i16, operands[0]) << 8) | @as(i16, operands[1]);

        if (int1 < int2) {
            const target = @as(u32, @intCast(@as(i32, @intCast(pc)) + @as(i32, offset)));
            return ExecutionResult{ .next_pc = pc + 3, .branch_target = target };
        } else {
            return ExecutionResult{ .next_pc = pc + 3 };
        }
    }

    fn executeIfIcmpge(self: *InstructionProcessor, pc: u32, operands: []const u8, operand_stack: *OperandStack) ProcessorError!ExecutionResult {
        _ = self;
        if (operands.len < 2) return ProcessorError.InvalidInstruction;
        const value2 = try operand_stack.pop();
        const value1 = try operand_stack.pop();
        const int1 = try value1.toInt();
        const int2 = try value2.toInt();
        const offset = (@as(i16, operands[0]) << 8) | @as(i16, operands[1]);

        if (int1 >= int2) {
            const target = @as(u32, @intCast(@as(i32, @intCast(pc)) + @as(i32, offset)));
            return ExecutionResult{ .next_pc = pc + 3, .branch_target = target };
        } else {
            return ExecutionResult{ .next_pc = pc + 3 };
        }
    }

    fn executeIfIcmpgt(self: *InstructionProcessor, pc: u32, operands: []const u8, operand_stack: *OperandStack) ProcessorError!ExecutionResult {
        _ = self;
        if (operands.len < 2) return ProcessorError.InvalidInstruction;
        const value2 = try operand_stack.pop();
        const value1 = try operand_stack.pop();
        const int1 = try value1.toInt();
        const int2 = try value2.toInt();
        const offset = (@as(i16, operands[0]) << 8) | @as(i16, operands[1]);

        if (int1 > int2) {
            const target = @as(u32, @intCast(@as(i32, @intCast(pc)) + @as(i32, offset)));
            return ExecutionResult{ .next_pc = pc + 3, .branch_target = target };
        } else {
            return ExecutionResult{ .next_pc = pc + 3 };
        }
    }

    fn executeIfIcmple(self: *InstructionProcessor, pc: u32, operands: []const u8, operand_stack: *OperandStack) ProcessorError!ExecutionResult {
        _ = self;
        if (operands.len < 2) return ProcessorError.InvalidInstruction;
        const value2 = try operand_stack.pop();
        const value1 = try operand_stack.pop();
        const int1 = try value1.toInt();
        const int2 = try value2.toInt();
        const offset = (@as(i16, operands[0]) << 8) | @as(i16, operands[1]);

        if (int1 <= int2) {
            const target = @as(u32, @intCast(@as(i32, @intCast(pc)) + @as(i32, offset)));
            return ExecutionResult{ .next_pc = pc + 3, .branch_target = target };
        } else {
            return ExecutionResult{ .next_pc = pc + 3 };
        }
    }

    fn executeIfAcmpeq(self: *InstructionProcessor, pc: u32, operands: []const u8, operand_stack: *OperandStack) ProcessorError!ExecutionResult {
        _ = self;
        if (operands.len < 2) return ProcessorError.InvalidInstruction;
        const value2 = try operand_stack.pop();
        const value1 = try operand_stack.pop();
        const ref1 = try value1.toReference();
        const ref2 = try value2.toReference();
        const offset = (@as(i16, operands[0]) << 8) | @as(i16, operands[1]);

        if (ref1 == ref2) {
            const target = @as(u32, @intCast(@as(i32, @intCast(pc)) + @as(i32, offset)));
            return ExecutionResult{ .next_pc = pc + 3, .branch_target = target };
        } else {
            return ExecutionResult{ .next_pc = pc + 3 };
        }
    }

    fn executeIfAcmpne(self: *InstructionProcessor, pc: u32, operands: []const u8, operand_stack: *OperandStack) ProcessorError!ExecutionResult {
        _ = self;
        if (operands.len < 2) return ProcessorError.InvalidInstruction;
        const value2 = try operand_stack.pop();
        const value1 = try operand_stack.pop();
        const ref1 = try value1.toReference();
        const ref2 = try value2.toReference();
        const offset = (@as(i16, operands[0]) << 8) | @as(i16, operands[1]);

        if (ref1 != ref2) {
            const target = @as(u32, @intCast(@as(i32, @intCast(pc)) + @as(i32, offset)));
            return ExecutionResult{ .next_pc = pc + 3, .branch_target = target };
        } else {
            return ExecutionResult{ .next_pc = pc + 3 };
        }
    }

    // ==================== 控制流指令实现 ====================

    fn executeReturn(self: *InstructionProcessor, pc: u32) ProcessorError!ExecutionResult {
        _ = self;
        return ExecutionResult{ .next_pc = pc + 1, .should_return = true };
    }

    fn executeIreturn(self: *InstructionProcessor, pc: u32, operand_stack: *OperandStack) ProcessorError!ExecutionResult {
        _ = self;
        const value = try operand_stack.pop();
        return ExecutionResult{ .next_pc = pc + 1, .should_return = true, .return_value = value };
    }

    fn executeAreturn(self: *InstructionProcessor, pc: u32, operand_stack: *OperandStack) ProcessorError!ExecutionResult {
        _ = self;
        const value = try operand_stack.pop();
        return ExecutionResult{ .next_pc = pc + 1, .should_return = true, .return_value = value };
    }

    // ==================== 方法调用指令实现 ====================

    fn executeInvokeVirtual(self: *InstructionProcessor, pc: u32, operands: []const u8, operand_stack: *OperandStack) ProcessorError!ExecutionResult {
        if (operands.len < 2) return ProcessorError.InvalidInstruction;

        const result = try self.method_call_processor.processInvokeVirtual(operands, operand_stack, null // TODO: 传入实际的常量池
        );

        if (result.return_value) |return_value| {
            try operand_stack.push(return_value);
        }

        return ExecutionResult{ .next_pc = pc + 3 };
    }

    fn executeInvokeSpecial(self: *InstructionProcessor, pc: u32, operands: []const u8, operand_stack: *OperandStack) ProcessorError!ExecutionResult {
        if (operands.len < 2) return ProcessorError.InvalidInstruction;

        const result = try self.method_call_processor.processInvokeSpecial(operands, operand_stack, null // TODO: 传入实际的常量池
        );

        if (result.return_value) |return_value| {
            try operand_stack.push(return_value);
        }

        return ExecutionResult{ .next_pc = pc + 3 };
    }

    fn executeInvokeStatic(self: *InstructionProcessor, pc: u32, operands: []const u8, operand_stack: *OperandStack) ProcessorError!ExecutionResult {
        if (operands.len < 2) return ProcessorError.InvalidInstruction;

        const result = try self.method_call_processor.processInvokeStatic(operands, operand_stack, null // TODO: 传入实际的常量池
        );

        if (result.return_value) |return_value| {
            try operand_stack.push(return_value);
        }

        return ExecutionResult{ .next_pc = pc + 3 };
    }

    fn executeInvokeInterface(self: *InstructionProcessor, pc: u32, operands: []const u8, operand_stack: *OperandStack) ProcessorError!ExecutionResult {
        if (operands.len < 4) return ProcessorError.InvalidInstruction;

        const result = try self.method_call_processor.processInvokeInterface(operands, operand_stack, null // TODO: 传入实际的常量池
        );

        if (result.return_value) |return_value| {
            try operand_stack.push(return_value);
        }

        return ExecutionResult{ .next_pc = pc + 5 };
    }

    // ==================== 新增的控制流指令实现 ====================

    fn executeTableSwitch(self: *InstructionProcessor, pc: u32, operands: []const u8, operand_stack: *OperandStack) ProcessorError!ExecutionResult {
        const result = try self.control_flow_processor.processTableSwitch(pc, operands, operand_stack);
        return ExecutionResult{ .next_pc = result.next_pc, .branch_target = result.target_pc };
    }

    fn executeLookupSwitch(self: *InstructionProcessor, pc: u32, operands: []const u8, operand_stack: *OperandStack) ProcessorError!ExecutionResult {
        const result = try self.control_flow_processor.processLookupSwitch(pc, operands, operand_stack);
        return ExecutionResult{ .next_pc = result.next_pc, .branch_target = result.target_pc };
    }

    fn executeGoto(self: *InstructionProcessor, pc: u32, operands: []const u8) ProcessorError!ExecutionResult {
        const result = try self.control_flow_processor.processGoto(pc, operands);
        return ExecutionResult{ .next_pc = result.next_pc, .branch_target = result.target_pc };
    }

    fn executeConditionalBranch(self: *InstructionProcessor, opcode: Opcode, pc: u32, operands: []const u8, operand_stack: *OperandStack) ProcessorError!ExecutionResult {
        const result = try self.control_flow_processor.processConditionalBranch(opcode, pc, operands, operand_stack);
        return ExecutionResult{ .next_pc = result.next_pc, .branch_target = if (result.should_branch) result.target_pc else null };
    }
};
