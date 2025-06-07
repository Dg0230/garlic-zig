//! JVM 模拟器模块
//! 提供 Java 虚拟机指令执行和状态管理功能

const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

// 导出子模块
pub const instructions = @import("instructions.zig");
pub const stack = @import("stack.zig");
pub const locals = @import("locals.zig");
pub const control_flow = @import("control_flow.zig");
pub const type_inference = @import("type_inference.zig");
const instruction_processor = @import("instruction_processor.zig");
const bytecode_parser = @import("bytecode_parser.zig");

// 重新导出常用类型
pub const Instruction = control_flow.Instruction;
pub const OperandStack = stack.OperandStack;
pub const LocalVariableTable = locals.LocalVariableTable;
pub const ControlFlowGraph = control_flow.ControlFlowGraph;
pub const TypeInferenceEngine = type_inference.TypeInferenceEngine;
const InstructionProcessor = instruction_processor.InstructionProcessor;
const BytecodeParser = bytecode_parser.BytecodeParser;
const BytecodeInstruction = bytecode_parser.BytecodeInstruction;

/// JVM 执行上下文
pub const ExecutionContext = struct {
    allocator: Allocator,
    operand_stack: OperandStack,
    local_variables: LocalVariableTable,
    control_flow_graph: ControlFlowGraph,
    type_inference: TypeInferenceEngine,
    instruction_processor: InstructionProcessor,
    bytecode_parser: BytecodeParser,

    // 执行状态
    pc: u32 = 0, // 程序计数器
    instructions: ?ArrayList(BytecodeInstruction) = null,
    is_running: bool = false,

    pub fn init(allocator: Allocator, max_stack: u16, max_locals: u16) !ExecutionContext {
        return ExecutionContext{
            .allocator = allocator,
            .operand_stack = OperandStack.init(allocator, max_stack),
            .local_variables = try LocalVariableTable.init(allocator, max_locals),
            .control_flow_graph = ControlFlowGraph.init(allocator),
            .type_inference = TypeInferenceEngine.init(allocator),
            .instruction_processor = try InstructionProcessor.init(allocator),
            .bytecode_parser = BytecodeParser.init(allocator),
        };
    }

    pub fn deinit(self: *ExecutionContext) void {
        self.operand_stack.deinit();
        self.local_variables.deinit();
        self.control_flow_graph.deinit();
        self.type_inference.deinit();
        self.instruction_processor.deinit();
        self.bytecode_parser.deinit();

        if (self.instructions) |*instructions_list| {
            self.bytecode_parser.freeInstructions(instructions_list);
        }
    }

    /// 加载字节码
    pub fn loadBytecode(self: *ExecutionContext, code: []const u8) !void {
        // 释放之前的指令
        if (self.instructions) |*instructions_list| {
            self.bytecode_parser.freeInstructions(instructions_list);
        }

        // 解析新的字节码
        self.instructions = try self.bytecode_parser.parseCode(code);
        self.pc = 0;
        self.is_running = false;
    }

    /// 执行单步
    pub fn step(self: *ExecutionContext) !?instruction_processor.ExecutionResult {
        if (self.instructions == null) return null;

        const instructions_list = self.instructions.?.items;
        if (self.pc >= instructions_list.len) return null;

        // 查找当前PC对应的指令
        const instruction_index = BytecodeParser.findInstructionIndex(instructions_list, self.pc) orelse return null;
        const instruction = instructions_list[instruction_index];

        // 执行指令
        const result = try self.instruction_processor.executeInstruction(instruction.opcode, instruction.operands, self.pc, &self.operand_stack, &self.local_variables);

        // 更新程序计数器
        self.pc = result.next_pc;

        return result;
    }

    /// 运行直到完成或遇到错误
    pub fn run(self: *ExecutionContext, max_steps: ?u32) !void {
        if (self.instructions == null) return;

        self.is_running = true;
        var steps: u32 = 0;
        const step_limit = max_steps orelse 10000; // 默认最大步数

        while (self.is_running and steps < step_limit) {
            const result = try self.step();

            if (result == null) {
                // 没有更多指令可执行
                self.is_running = false;
                break;
            }

            if (result.?.should_return) {
                // 方法返回
                self.is_running = false;
                break;
            }

            steps += 1;
        }

        if (steps >= step_limit) {
            std.debug.print("Warning: Execution stopped after {d} steps (possible infinite loop)\n", .{step_limit});
        }
    }

    /// 重置执行状态
    pub fn reset(self: *ExecutionContext) void {
        self.pc = 0;
        self.is_running = false;
        self.operand_stack.clear();
        self.local_variables.clear();
    }

    /// 打印当前状态（用于调试）
    pub fn printState(self: *ExecutionContext, writer: anytype) !void {
        try writer.print("=== JVM Execution Context State ===\n", .{});
        try writer.print("PC: {d}\n", .{self.pc});
        try writer.print("Running: {any}\n", .{self.is_running});

        try writer.print("\nOperand Stack:\n", .{});
        try self.operand_stack.print(writer);

        try writer.print("\nLocal Variables:\n", .{});
        try self.local_variables.print(writer);

        if (self.instructions) |instructions_list| {
            try writer.print("\nLoaded Instructions: {d}\n", .{instructions_list.items.len});

            // 显示当前指令附近的几条指令
            const current_index = BytecodeParser.findInstructionIndex(instructions_list.items, self.pc);
            if (current_index) |index| {
                const start = if (index >= 2) index - 2 else 0;
                const end = @min(index + 3, instructions_list.items.len);

                try writer.print("\nNearby Instructions:\n", .{});
                for (instructions_list.items[start..end], start..) |instruction, i| {
                    const marker = if (i == index) ">>> " else "    ";
                    try writer.print("{s}{any}\n", .{ marker, instruction });
                }
            }
        } else {
            try writer.print("\nNo bytecode loaded\n", .{});
        }

        try writer.print("===================================\n", .{});
    }
};
