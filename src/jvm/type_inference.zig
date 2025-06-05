//! JVM 类型推断引擎
//! 分析字节码指令序列，推断变量和表达式的类型

const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const HashMap = std.HashMap;
const instructions = @import("instructions.zig");
const stack_mod = @import("stack.zig");
const locals_mod = @import("locals.zig");
const control_flow = @import("control_flow.zig");

const Opcode = instructions.Opcode;
const StackValue = stack_mod.StackValue;
const ValueType = stack_mod.ValueType;
const OperandStack = stack_mod.OperandStack;
const LocalVariableTable = locals_mod.LocalVariableTable;
const ControlFlowGraph = control_flow.ControlFlowGraph;
const BasicBlock = control_flow.BasicBlock;

/// Java 类型系统
pub const JavaType = union(enum) {
    primitive: PrimitiveType,
    reference: ReferenceType,
    array: ArrayType,
    void: void,

    /// 获取类型的栈槽大小
    pub fn getStackSize(self: JavaType) u8 {
        return switch (self) {
            .primitive => |p| switch (p) {
                .boolean, .byte, .char, .short, .int, .float => 1,
                .long, .double => 2,
            },
            .reference, .array => 1,
            .void => 0,
        };
    }

    /// 检查类型是否兼容
    pub fn isCompatibleWith(self: JavaType, other: JavaType) bool {
        return switch (self) {
            .primitive => |p1| switch (other) {
                .primitive => |p2| p1 == p2 or self.canWiden(other),
                else => false,
            },
            .reference => |r1| switch (other) {
                .reference => |r2| std.mem.eql(u8, r1.class_name, r2.class_name) or r2.isAssignableFrom(r1),
                else => false,
            },
            .array => |a1| switch (other) {
                .array => |a2| a1.element_type.isCompatibleWith(a2.element_type.*),
                .reference => |r| std.mem.eql(u8, r.class_name, "java/lang/Object"),
                else => false,
            },
            .void => other == .void,
        };
    }

    /// 检查是否可以进行类型拓宽
    pub fn canWiden(self: JavaType, target: JavaType) bool {
        if (self != .primitive or target != .primitive) return false;

        const from = self.primitive;
        const to = target.primitive;

        return switch (from) {
            .byte => to == .short or to == .int or to == .long or to == .float or to == .double,
            .short => to == .int or to == .long or to == .float or to == .double,
            .char => to == .int or to == .long or to == .float or to == .double,
            .int => to == .long or to == .float or to == .double,
            .long => to == .float or to == .double,
            .float => to == .double,
            else => false,
        };
    }
};

/// 原始类型
pub const PrimitiveType = enum {
    boolean,
    byte,
    char,
    short,
    int,
    long,
    float,
    double,
};

/// 引用类型
pub const ReferenceType = struct {
    class_name: []const u8,

    /// 检查是否可以从other类型赋值
    pub fn isAssignableFrom(self: ReferenceType, other: ReferenceType) bool {
        // 简化实现：只检查类名相等
        return std.mem.eql(u8, self.class_name, other.class_name);
    }
};

/// 数组类型
pub const ArrayType = struct {
    element_type: *const JavaType,
    dimensions: u8,
};

/// 类型状态
pub const TypeState = struct {
    stack_types: ArrayList(JavaType),
    local_types: []?JavaType,
    allocator: Allocator,

    /// 创建类型状态
    pub fn init(allocator: Allocator, max_locals: usize) !TypeState {
        const local_types = try allocator.alloc(?JavaType, max_locals);
        for (local_types) |*local_type| {
            local_type.* = null;
        }

        return TypeState{
            .stack_types = ArrayList(JavaType).init(allocator),
            .local_types = local_types,
            .allocator = allocator,
        };
    }

    /// 释放类型状态
    pub fn deinit(self: *TypeState) void {
        self.stack_types.deinit();
        self.allocator.free(self.local_types);
    }

    /// 复制类型状态
    pub fn clone(self: *const TypeState) !TypeState {
        var new_state = try TypeState.init(self.allocator, self.local_types.len);

        // 复制栈类型
        for (self.stack_types.items) |stack_type| {
            try new_state.stack_types.append(stack_type);
        }

        // 复制局部变量类型
        for (self.local_types, 0..) |local_type, i| {
            new_state.local_types[i] = local_type;
        }

        return new_state;
    }

    /// 压栈类型
    pub fn pushType(self: *TypeState, java_type: JavaType) !void {
        try self.stack_types.append(java_type);
    }

    /// 出栈类型
    pub fn popType(self: *TypeState) !JavaType {
        if (self.stack_types.items.len == 0) {
            return error.StackUnderflow;
        }
        return self.stack_types.pop() orelse unreachable;
    }

    /// 查看栈顶类型
    pub fn peekType(self: *const TypeState) !JavaType {
        if (self.stack_types.items.len == 0) {
            return error.StackUnderflow;
        }
        return self.stack_types.items[self.stack_types.items.len - 1];
    }

    /// 设置局部变量类型
    pub fn setLocalType(self: *TypeState, index: usize, java_type: JavaType) !void {
        if (index >= self.local_types.len) {
            return error.IndexOutOfBounds;
        }
        self.local_types[index] = java_type;

        // 如果是长类型，标记下一个槽为无效
        if (java_type.getStackSize() == 2 and index + 1 < self.local_types.len) {
            self.local_types[index + 1] = null;
        }
    }

    /// 获取局部变量类型
    pub fn getLocalType(self: *const TypeState, index: usize) !JavaType {
        if (index >= self.local_types.len) {
            return error.IndexOutOfBounds;
        }
        return self.local_types[index] orelse error.UninitializedVariable;
    }

    /// 合并两个类型状态
    pub fn merge(self: *TypeState, other: *const TypeState) !void {
        // 栈高度必须相同
        if (self.stack_types.items.len != other.stack_types.items.len) {
            return error.IncompatibleStates;
        }

        // 合并栈类型
        for (self.stack_types.items, 0..) |*self_type, i| {
            const other_type = other.stack_types.items[i];
            self_type.* = try self.mergeTypes(self_type.*, other_type);
        }

        // 合并局部变量类型
        for (self.local_types, 0..) |*self_type, i| {
            const other_type = other.local_types[i];
            if (self_type.* != null and other_type != null) {
                self_type.* = try self.mergeTypes(self_type.*.?, other_type.?);
            } else if (!std.meta.eql(self_type.*, other_type)) {
                self_type.* = null; // 不兼容，设为未知
            }
        }
    }

    /// 合并两个类型
    fn mergeTypes(self: *TypeState, type1: JavaType, type2: JavaType) !JavaType {
        _ = self;

        if (std.meta.eql(type1, type2)) {
            return type1;
        }

        // 简化实现：如果类型不同，返回Object类型
        return JavaType{ .reference = ReferenceType{ .class_name = "java/lang/Object" } };
    }
};

/// 类型推断错误
pub const TypeInferenceError = error{
    StackUnderflow,
    StackOverflow,
    TypeMismatch,
    IndexOutOfBounds,
    UninitializedVariable,
    IncompatibleStates,
    InvalidInstruction,
};

/// 类型推断引擎
pub const TypeInferenceEngine = struct {
    allocator: Allocator,
    block_states: HashMap(u32, TypeState, std.hash_map.AutoContext(u32), std.hash_map.default_max_load_percentage),

    /// 创建类型推断引擎
    pub fn init(allocator: Allocator) TypeInferenceEngine {
        return TypeInferenceEngine{
            .allocator = allocator,
            .block_states = HashMap(u32, TypeState, std.hash_map.AutoContext(u32), std.hash_map.default_max_load_percentage).init(allocator),
        };
    }

    /// 释放类型推断引擎
    pub fn deinit(self: *TypeInferenceEngine) void {
        var iterator = self.block_states.iterator();
        while (iterator.next()) |entry| {
            entry.value_ptr.deinit();
        }
        self.block_states.deinit();
    }

    /// 分析控制流图的类型
    pub fn analyzeTypes(self: *TypeInferenceEngine, cfg: *const ControlFlowGraph, max_locals: usize) !void {
        // 初始化入口块的类型状态
        const entry_state = try TypeState.init(self.allocator, max_locals);
        try self.block_states.put(cfg.entry_block_id, entry_state);

        // 工作列表算法
        var worklist = ArrayList(u32).init(self.allocator);
        defer worklist.deinit();

        try worklist.append(cfg.entry_block_id);

        while (worklist.items.len > 0) {
            const block_id = worklist.pop() orelse unreachable; // pop() 返回 ?u32，使用 orelse 处理

            if (cfg.blocks.get(block_id)) |block| {
                // 获取当前块的输入状态
                var current_state = if (self.block_states.getPtr(block_id)) |state|
                    try state.clone()
                else
                    try TypeState.init(self.allocator, max_locals);
                defer current_state.deinit();

                // 分析块中的每条指令
                for (block.instructions.items) |instruction| {
                    try self.analyzeInstruction(instruction, &current_state);
                }

                // 传播类型状态到后继块
                for (block.successors.items) |successor_id| {
                    var changed = false;

                    if (self.block_states.getPtr(successor_id)) |successor_state| {
                        var old_state = try successor_state.clone();
                        defer old_state.deinit();

                        try successor_state.merge(&current_state);

                        // 检查是否有变化
                        changed = !self.statesEqual(successor_state, &old_state);
                    } else {
                        // 第一次访问这个块
                        const new_state = try current_state.clone();
                        try self.block_states.put(successor_id, new_state);
                        changed = true;
                    }

                    if (changed) {
                        // 添加到工作列表
                        var already_in_worklist = false;
                        for (worklist.items) |item| {
                            if (item == successor_id) {
                                already_in_worklist = true;
                                break;
                            }
                        }
                        if (!already_in_worklist) {
                            try worklist.append(successor_id);
                        }
                    }
                }
            }
        }
    }

    /// 分析单条指令对类型状态的影响
    fn analyzeInstruction(self: *TypeInferenceEngine, instruction: control_flow.Instruction, state: *TypeState) !void {
        _ = self;

        const opcode = instruction.opcode;

        switch (opcode) {
            // 常量指令
            .aconst_null => try state.pushType(JavaType{ .reference = ReferenceType{ .class_name = "java/lang/Object" } }),
            .iconst_m1, .iconst_0, .iconst_1, .iconst_2, .iconst_3, .iconst_4, .iconst_5 => try state.pushType(JavaType{ .primitive = .int }),
            .lconst_0, .lconst_1 => try state.pushType(JavaType{ .primitive = .long }),
            .fconst_0, .fconst_1, .fconst_2 => try state.pushType(JavaType{ .primitive = .float }),
            .dconst_0, .dconst_1 => try state.pushType(JavaType{ .primitive = .double }),
            .bipush, .sipush => try state.pushType(JavaType{ .primitive = .int }),

            // 加载指令
            .iload, .iload_0, .iload_1, .iload_2, .iload_3 => {
                const index = if (opcode == .iload) instruction.operands[0] else @intFromEnum(opcode) - @intFromEnum(Opcode.iload_0);
                _ = try state.getLocalType(index); // 验证类型
                try state.pushType(JavaType{ .primitive = .int });
            },
            .lload, .lload_0, .lload_1, .lload_2, .lload_3 => {
                const index = if (opcode == .lload) instruction.operands[0] else @intFromEnum(opcode) - @intFromEnum(Opcode.lload_0);
                _ = try state.getLocalType(index);
                try state.pushType(JavaType{ .primitive = .long });
            },
            .fload, .fload_0, .fload_1, .fload_2, .fload_3 => {
                const index = if (opcode == .fload) instruction.operands[0] else @intFromEnum(opcode) - @intFromEnum(Opcode.fload_0);
                _ = try state.getLocalType(index);
                try state.pushType(JavaType{ .primitive = .float });
            },
            .dload, .dload_0, .dload_1, .dload_2, .dload_3 => {
                const index = if (opcode == .dload) instruction.operands[0] else @intFromEnum(opcode) - @intFromEnum(Opcode.dload_0);
                _ = try state.getLocalType(index);
                try state.pushType(JavaType{ .primitive = .double });
            },
            .aload, .aload_0, .aload_1, .aload_2, .aload_3 => {
                const index = if (opcode == .aload) instruction.operands[0] else @intFromEnum(opcode) - @intFromEnum(Opcode.aload_0);
                const ref_type = try state.getLocalType(index);
                try state.pushType(ref_type);
            },

            // 存储指令
            .istore, .istore_0, .istore_1, .istore_2, .istore_3 => {
                const index = if (opcode == .istore) instruction.operands[0] else @intFromEnum(opcode) - @intFromEnum(Opcode.istore_0);
                const value_type = try state.popType();
                if (value_type != .primitive or value_type.primitive != .int) {
                    return TypeInferenceError.TypeMismatch;
                }
                try state.setLocalType(index, value_type);
            },
            .lstore, .lstore_0, .lstore_1, .lstore_2, .lstore_3 => {
                const index = if (opcode == .lstore) instruction.operands[0] else @intFromEnum(opcode) - @intFromEnum(Opcode.lstore_0);
                const value_type = try state.popType();
                if (value_type != .primitive or value_type.primitive != .long) {
                    return TypeInferenceError.TypeMismatch;
                }
                try state.setLocalType(index, value_type);
            },
            .astore, .astore_0, .astore_1, .astore_2, .astore_3 => {
                const index = if (opcode == .astore) instruction.operands[0] else @intFromEnum(opcode) - @intFromEnum(Opcode.astore_0);
                const value_type = try state.popType();
                try state.setLocalType(index, value_type);
            },

            // 算术指令
            .iadd, .isub, .imul, .idiv, .irem => {
                _ = try state.popType(); // 第二个操作数
                _ = try state.popType(); // 第一个操作数
                try state.pushType(JavaType{ .primitive = .int });
            },
            .ladd, .lsub, .lmul, .ldiv, .lrem => {
                _ = try state.popType();
                _ = try state.popType();
                try state.pushType(JavaType{ .primitive = .long });
            },
            .fadd, .fsub, .fmul, .fdiv, .frem => {
                _ = try state.popType();
                _ = try state.popType();
                try state.pushType(JavaType{ .primitive = .float });
            },
            .dadd, .dsub, .dmul, .ddiv, .drem => {
                _ = try state.popType();
                _ = try state.popType();
                try state.pushType(JavaType{ .primitive = .double });
            },

            // 栈操作指令
            .pop => {
                _ = try state.popType();
            },
            .dup => {
                const top_type = try state.peekType();
                try state.pushType(top_type);
            },
            .swap => {
                const type1 = try state.popType();
                const type2 = try state.popType();
                try state.pushType(type1);
                try state.pushType(type2);
            },

            // 比较指令
            .ifeq, .ifne, .iflt, .ifge, .ifgt, .ifle => {
                _ = try state.popType(); // 弹出比较值
            },
            .if_icmpeq, .if_icmpne, .if_icmplt, .if_icmpge, .if_icmpgt, .if_icmple => {
                _ = try state.popType(); // 第二个值
                _ = try state.popType(); // 第一个值
            },

            // 返回指令
            .ireturn => {
                const return_type = try state.popType();
                if (return_type != .primitive or return_type.primitive != .int) {
                    return TypeInferenceError.TypeMismatch;
                }
            },
            .lreturn => {
                const return_type = try state.popType();
                if (return_type != .primitive or return_type.primitive != .long) {
                    return TypeInferenceError.TypeMismatch;
                }
            },
            .areturn => {
                _ = try state.popType(); // 引用类型
            },
            .@"return" => {}, // void返回

            else => {
                // 其他指令的简化处理
                // 在实际实现中需要处理所有指令
            },
        }
    }

    /// 比较两个类型状态是否相等
    fn statesEqual(self: *TypeInferenceEngine, state1: *const TypeState, state2: *const TypeState) bool {
        _ = self;

        // 比较栈类型
        if (state1.stack_types.items.len != state2.stack_types.items.len) {
            return false;
        }

        for (state1.stack_types.items, 0..) |type1, i| {
            const type2 = state2.stack_types.items[i];
            if (!std.meta.eql(type1, type2)) {
                return false;
            }
        }

        // 比较局部变量类型
        for (state1.local_types, 0..) |type1, i| {
            const type2 = state2.local_types[i];
            if (type1 == null and type2 == null) continue;
            if (type1 == null or type2 == null) return false;
            if (!std.meta.eql(type1.?, type2.?)) return false;
        }

        return true;
    }

    /// 获取基本块的输入类型状态
    pub fn getBlockInputState(self: *const TypeInferenceEngine, block_id: u32) ?*const TypeState {
        return self.block_states.getPtr(block_id);
    }
};

test "java type system" {
    const testing = std.testing;

    // 测试原始类型
    const int_type = JavaType{ .primitive = .int };
    const long_type = JavaType{ .primitive = .long };

    try testing.expect(int_type.getStackSize() == 1);
    try testing.expect(long_type.getStackSize() == 2);

    // 测试类型兼容性
    try testing.expect(int_type.isCompatibleWith(int_type));
    try testing.expect(int_type.isCompatibleWith(long_type)); // int 可以拓宽到 long

    // 测试类型拓宽
    try testing.expect(int_type.canWiden(long_type));
    try testing.expect(!long_type.canWiden(int_type));
}

test "type state operations" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var state = try TypeState.init(allocator, 5);
    defer state.deinit();

    // 测试栈操作
    const int_type = JavaType{ .primitive = .int };
    try state.pushType(int_type);

    const popped_type = try state.popType();
    try testing.expect(std.meta.eql(popped_type, int_type));

    // 测试局部变量
    try state.setLocalType(0, int_type);
    const local_type = try state.getLocalType(0);
    try testing.expect(std.meta.eql(local_type, int_type));
}

test "type inference engine" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var engine = TypeInferenceEngine.init(allocator);
    defer engine.deinit();

    // 创建简单的控制流图进行测试
    var cfg = ControlFlowGraph.init(allocator);
    defer cfg.deinit();

    const entry_id = try cfg.createBlock(.entry, 0);
    _ = entry_id;

    // 分析类型（简化测试）
    try engine.analyzeTypes(&cfg, 5);

    // 验证入口块有类型状态
    try testing.expect(engine.getBlockInputState(cfg.entry_block_id) != null);
}
