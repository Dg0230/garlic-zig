//! JVM 模拟器模块
//! 提供 Java 虚拟机指令执行和状态管理功能

const std = @import("std");
const Allocator = std.mem.Allocator;

// 导出子模块
pub const instructions = @import("instructions.zig");
pub const stack = @import("stack.zig");
pub const locals = @import("locals.zig");
pub const control_flow = @import("control_flow.zig");
pub const type_inference = @import("type_inference.zig");

// 重新导出常用类型
pub const Instruction = instructions.Instruction;
pub const OperandStack = stack.OperandStack;
pub const LocalVariableTable = locals.LocalVariableTable;
pub const ControlFlowGraph = control_flow.ControlFlowGraph;
pub const TypeInference = type_inference.TypeInference;

/// JVM 执行上下文
pub const ExecutionContext = struct {
    stack: OperandStack,
    locals: LocalVariableTable,
    control_flow: ControlFlowGraph,
    type_inference: TypeInference,
    allocator: Allocator,

    pub fn init(allocator: Allocator, max_stack: u16, max_locals: u16) !ExecutionContext {
        return ExecutionContext{
            .stack = try OperandStack.init(allocator, max_stack),
            .locals = try LocalVariableTable.init(allocator, max_locals),
            .control_flow = try ControlFlowGraph.init(allocator),
            .type_inference = try TypeInference.init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *ExecutionContext) void {
        self.stack.deinit();
        self.locals.deinit();
        self.control_flow.deinit();
        self.type_inference.deinit();
    }
};
