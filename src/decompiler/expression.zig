//! 表达式重建模块
//! 负责将字节码指令序列重建为高级表达式

const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const HashMap = std.HashMap;
const ast = @import("ast.zig");
const ASTNode = ast.ASTNode;
const ASTBuilder = ast.ASTBuilder;
const BinaryOp = ast.BinaryOp;
const UnaryOp = ast.UnaryOp;
const DataType = ast.DataType;
const LiteralValue = ast.LiteralValue;

/// 字节码指令类型（简化版）
pub const Instruction = struct {
    opcode: u8,
    operands: []const u8,
    pc: u32, // 程序计数器

    /// 获取指令名称
    pub fn getName(self: Instruction) []const u8 {
        return switch (self.opcode) {
            0x00 => "nop",
            0x01 => "aconst_null",
            0x02 => "iconst_m1",
            0x03 => "iconst_0",
            0x04 => "iconst_1",
            0x05 => "iconst_2",
            0x06 => "iconst_3",
            0x07 => "iconst_4",
            0x08 => "iconst_5",
            0x10 => "bipush",
            0x11 => "sipush",
            0x12 => "ldc",
            0x15 => "iload",
            0x19 => "aload",
            0x1a => "iload_0",
            0x1b => "iload_1",
            0x1c => "iload_2",
            0x1d => "iload_3",
            0x2a => "aload_0",
            0x2b => "aload_1",
            0x2c => "aload_2",
            0x2d => "aload_3",
            0x36 => "istore",
            0x3a => "astore",
            0x3b => "istore_0",
            0x3c => "istore_1",
            0x3d => "istore_2",
            0x3e => "istore_3",
            0x4b => "astore_0",
            0x4c => "astore_1",
            0x4d => "astore_2",
            0x4e => "astore_3",
            0x60 => "iadd",
            0x64 => "isub",
            0x68 => "imul",
            0x6c => "idiv",
            0x70 => "irem",
            0x74 => "ineg",
            0x78 => "ishl",
            0x7a => "ishr",
            0x7c => "iushr",
            0x7e => "iand",
            0x80 => "ior",
            0x82 => "ixor",
            0x84 => "iinc",
            0x99 => "ifeq",
            0x9a => "ifne",
            0x9b => "iflt",
            0x9c => "ifge",
            0x9d => "ifgt",
            0x9e => "ifle",
            0x9f => "if_icmpeq",
            0xa0 => "if_icmpne",
            0xa1 => "if_icmplt",
            0xa2 => "if_icmpge",
            0xa3 => "if_icmpgt",
            0xa4 => "if_icmple",
            0xa7 => "goto",
            0xac => "ireturn",
            0xb0 => "areturn",
            0xb1 => "return",
            0xb2 => "getstatic",
            0xb3 => "putstatic",
            0xb4 => "getfield",
            0xb5 => "putfield",
            0xb6 => "invokevirtual",
            0xb7 => "invokespecial",
            0xb8 => "invokestatic",
            0xb9 => "invokeinterface",
            0xbb => "new",
            0xbc => "newarray",
            0xbd => "anewarray",
            0xbe => "arraylength",
            0xc0 => "checkcast",
            0xc1 => "instanceof",
            else => "unknown",
        };
    }
};

/// 操作数栈模拟
pub const OperandStack = struct {
    stack: ArrayList(*ASTNode),
    allocator: Allocator,

    /// 初始化操作数栈
    pub fn init(allocator: Allocator) OperandStack {
        return OperandStack{
            .stack = ArrayList(*ASTNode).init(allocator),
            .allocator = allocator,
        };
    }

    /// 释放操作数栈
    pub fn deinit(self: *OperandStack) void {
        self.stack.deinit();
    }

    /// 压栈
    pub fn push(self: *OperandStack, node: *ASTNode) !void {
        try self.stack.append(node);
    }

    /// 弹栈
    pub fn pop(self: *OperandStack) ?*ASTNode {
        if (self.stack.items.len == 0) return null;
        return self.stack.pop();
    }

    /// 查看栈顶
    pub fn peek(self: *OperandStack) ?*ASTNode {
        if (self.stack.items.len == 0) return null;
        return self.stack.items[self.stack.items.len - 1];
    }

    /// 获取栈大小
    pub fn size(self: *OperandStack) usize {
        return self.stack.items.len;
    }

    /// 清空栈
    pub fn clear(self: *OperandStack) void {
        self.stack.clearRetainingCapacity();
    }
};

/// 局部变量表
pub const LocalVariables = struct {
    variables: HashMap(u32, *ASTNode, std.hash_map.AutoContext(u32), std.hash_map.default_max_load_percentage),
    allocator: Allocator,

    /// 初始化局部变量表
    pub fn init(allocator: Allocator) LocalVariables {
        return LocalVariables{
            .variables = HashMap(u32, *ASTNode, std.hash_map.AutoContext(u32), std.hash_map.default_max_load_percentage).init(allocator),
            .allocator = allocator,
        };
    }

    /// 释放局部变量表
    pub fn deinit(self: *LocalVariables) void {
        self.variables.deinit();
    }

    /// 设置局部变量
    pub fn set(self: *LocalVariables, index: u32, node: *ASTNode) !void {
        try self.variables.put(index, node);
    }

    /// 获取局部变量
    pub fn get(self: *LocalVariables, index: u32) ?*ASTNode {
        return self.variables.get(index);
    }
};

/// 表达式重建器
pub const ExpressionBuilder = struct {
    allocator: Allocator,
    ast_builder: ASTBuilder,
    operand_stack: OperandStack,
    local_variables: LocalVariables,

    /// 初始化表达式重建器
    pub fn init(allocator: Allocator) ExpressionBuilder {
        return ExpressionBuilder{
            .allocator = allocator,
            .ast_builder = ASTBuilder.init(allocator),
            .operand_stack = OperandStack.init(allocator),
            .local_variables = LocalVariables.init(allocator),
        };
    }

    /// 释放表达式重建器
    pub fn deinit(self: *ExpressionBuilder) void {
        self.ast_builder.deinit();
        self.operand_stack.deinit();
        self.local_variables.deinit();
    }

    /// 处理单个指令
    pub fn processInstruction(self: *ExpressionBuilder, instruction: Instruction) !void {
        switch (instruction.opcode) {
            // 常量加载指令
            0x01 => try self.handleAConstNull(),
            0x02 => try self.handleIConst(-1),
            0x03 => try self.handleIConst(0),
            0x04 => try self.handleIConst(1),
            0x05 => try self.handleIConst(2),
            0x06 => try self.handleIConst(3),
            0x07 => try self.handleIConst(4),
            0x08 => try self.handleIConst(5),
            0x10 => try self.handleBiPush(instruction.operands),
            0x11 => try self.handleSiPush(instruction.operands),
            0x12 => try self.handleLdc(instruction.operands),

            // 局部变量加载指令
            0x15 => try self.handleILoad(instruction.operands),
            0x19 => try self.handleALoad(instruction.operands),
            0x1a => try self.handleILoad0(),
            0x1b => try self.handleILoad1(),
            0x1c => try self.handleILoad2(),
            0x1d => try self.handleILoad3(),
            0x2a => try self.handleALoad0(),
            0x2b => try self.handleALoad1(),
            0x2c => try self.handleALoad2(),
            0x2d => try self.handleALoad3(),

            // 局部变量存储指令
            0x36 => try self.handleIStore(instruction.operands),
            0x3a => try self.handleAStore(instruction.operands),
            0x3b => try self.handleIStore0(),
            0x3c => try self.handleIStore1(),
            0x3d => try self.handleIStore2(),
            0x3e => try self.handleIStore3(),
            0x4b => try self.handleAStore0(),
            0x4c => try self.handleAStore1(),
            0x4d => try self.handleAStore2(),
            0x4e => try self.handleAStore3(),

            // 算术运算指令
            0x60 => try self.handleIAdd(),
            0x64 => try self.handleISub(),
            0x68 => try self.handleIMul(),
            0x6c => try self.handleIDiv(),
            0x70 => try self.handleIRem(),
            0x74 => try self.handleINeg(),

            // 位运算指令
            0x78 => try self.handleIShl(),
            0x7a => try self.handleIShr(),
            0x7c => try self.handleIUShr(),
            0x7e => try self.handleIAnd(),
            0x80 => try self.handleIOr(),
            0x82 => try self.handleIXor(),

            // 字段访问指令
            0xb2 => try self.handleGetStatic(instruction.operands),
            0xb3 => try self.handlePutStatic(instruction.operands),
            0xb4 => try self.handleGetField(instruction.operands),
            0xb5 => try self.handlePutField(instruction.operands),

            // 方法调用指令
            0xb6 => try self.handleInvokeVirtual(instruction.operands),
            0xb7 => try self.handleInvokeSpecial(instruction.operands),
            0xb8 => try self.handleInvokeStatic(instruction.operands),

            // 返回指令
            0xac => try self.handleIReturn(),
            0xb0 => try self.handleAReturn(),
            0xb1 => try self.handleReturn(),

            else => {
                // 未实现的指令，暂时忽略
                std.log.warn("未实现的指令: 0x{x:0>2} ({s})", .{ instruction.opcode, instruction.getName() });
            },
        }
    }

    /// 处理 aconst_null 指令
    fn handleAConstNull(self: *ExpressionBuilder) !void {
        const node = try self.ast_builder.createLiteral(.{ .null_val = {} }, .object);
        try self.operand_stack.push(node);
    }

    /// 处理 iconst 指令
    fn handleIConst(self: *ExpressionBuilder, value: i32) !void {
        const node = try self.ast_builder.createLiteral(.{ .int_val = value }, .int);
        try self.operand_stack.push(node);
    }

    /// 处理 bipush 指令
    fn handleBiPush(self: *ExpressionBuilder, operands: []const u8) !void {
        if (operands.len < 1) return;
        const value = @as(i8, @bitCast(operands[0]));
        const node = try self.ast_builder.createLiteral(.{ .int_val = value }, .int);
        try self.operand_stack.push(node);
    }

    /// 处理 sipush 指令
    fn handleSiPush(self: *ExpressionBuilder, operands: []const u8) !void {
        if (operands.len < 2) return;
        const value = (@as(i16, operands[0]) << 8) | operands[1];
        const node = try self.ast_builder.createLiteral(.{ .int_val = value }, .int);
        try self.operand_stack.push(node);
    }

    /// 处理 ldc 指令
    fn handleLdc(self: *ExpressionBuilder, operands: []const u8) !void {
        if (operands.len < 1) return;
        const index = operands[0];
        // 这里应该从常量池获取实际值，暂时创建一个占位符
        const name = try std.fmt.allocPrint(self.allocator, "CONST_{any}", .{index});
        const node = try self.ast_builder.createIdentifier(name);
        try self.operand_stack.push(node);
    }

    /// 处理 iload 指令
    fn handleILoad(self: *ExpressionBuilder, operands: []const u8) !void {
        if (operands.len < 1) return;
        const index = operands[0];
        try self.loadLocalVariable(index);
    }

    /// 处理 iload_0 指令
    fn handleILoad0(self: *ExpressionBuilder) !void {
        try self.loadLocalVariable(0);
    }

    /// 处理 iload_1 指令
    fn handleILoad1(self: *ExpressionBuilder) !void {
        try self.loadLocalVariable(1);
    }

    /// 处理 iload_2 指令
    fn handleILoad2(self: *ExpressionBuilder) !void {
        try self.loadLocalVariable(2);
    }

    /// 处理 iload_3 指令
    fn handleILoad3(self: *ExpressionBuilder) !void {
        try self.loadLocalVariable(3);
    }

    /// 处理 aload 指令
    fn handleALoad(self: *ExpressionBuilder, operands: []const u8) !void {
        if (operands.len < 1) return;
        const index = operands[0];
        try self.loadLocalVariable(index);
    }

    /// 处理 aload_0 指令
    fn handleALoad0(self: *ExpressionBuilder) !void {
        try self.loadLocalVariable(0);
    }

    /// 处理 aload_1 指令
    fn handleALoad1(self: *ExpressionBuilder) !void {
        try self.loadLocalVariable(1);
    }

    /// 处理 aload_2 指令
    fn handleALoad2(self: *ExpressionBuilder) !void {
        try self.loadLocalVariable(2);
    }

    /// 处理 aload_3 指令
    fn handleALoad3(self: *ExpressionBuilder) !void {
        try self.loadLocalVariable(3);
    }

    /// 加载局部变量
    fn loadLocalVariable(self: *ExpressionBuilder, index: u32) !void {
        if (self.local_variables.get(index)) |var_node| {
            try self.operand_stack.push(var_node);
        } else {
            // 创建新的变量引用
            const name = try std.fmt.allocPrint(self.allocator, "var_{any}", .{index});
            const node = try self.ast_builder.createIdentifier(name);
            try self.local_variables.set(index, node);
            try self.operand_stack.push(node);
        }
    }

    /// 处理 istore 指令
    fn handleIStore(self: *ExpressionBuilder, operands: []const u8) !void {
        if (operands.len < 1) return;
        const index = operands[0];
        try self.storeLocalVariable(index);
    }

    /// 处理 istore_0 指令
    fn handleIStore0(self: *ExpressionBuilder) !void {
        try self.storeLocalVariable(0);
    }

    /// 处理 istore_1 指令
    fn handleIStore1(self: *ExpressionBuilder) !void {
        try self.storeLocalVariable(1);
    }

    /// 处理 istore_2 指令
    fn handleIStore2(self: *ExpressionBuilder) !void {
        try self.storeLocalVariable(2);
    }

    /// 处理 istore_3 指令
    fn handleIStore3(self: *ExpressionBuilder) !void {
        try self.storeLocalVariable(3);
    }

    /// 处理 astore 指令
    fn handleAStore(self: *ExpressionBuilder, operands: []const u8) !void {
        if (operands.len < 1) return;
        const index = operands[0];
        try self.storeLocalVariable(index);
    }

    /// 处理 astore_0 指令
    fn handleAStore0(self: *ExpressionBuilder) !void {
        try self.storeLocalVariable(0);
    }

    /// 处理 astore_1 指令
    fn handleAStore1(self: *ExpressionBuilder) !void {
        try self.storeLocalVariable(1);
    }

    /// 处理 astore_2 指令
    fn handleAStore2(self: *ExpressionBuilder) !void {
        try self.storeLocalVariable(2);
    }

    /// 处理 astore_3 指令
    fn handleAStore3(self: *ExpressionBuilder) !void {
        try self.storeLocalVariable(3);
    }

    /// 存储局部变量
    fn storeLocalVariable(self: *ExpressionBuilder, index: u32) !void {
        if (self.operand_stack.pop()) |value| {
            try self.local_variables.set(index, value);
        }
    }

    /// 处理 iadd 指令
    fn handleIAdd(self: *ExpressionBuilder) !void {
        try self.handleBinaryOp(.add);
    }

    /// 处理 isub 指令
    fn handleISub(self: *ExpressionBuilder) !void {
        try self.handleBinaryOp(.sub);
    }

    /// 处理 imul 指令
    fn handleIMul(self: *ExpressionBuilder) !void {
        try self.handleBinaryOp(.mul);
    }

    /// 处理 idiv 指令
    fn handleIDiv(self: *ExpressionBuilder) !void {
        try self.handleBinaryOp(.div);
    }

    /// 处理 irem 指令
    fn handleIRem(self: *ExpressionBuilder) !void {
        try self.handleBinaryOp(.mod);
    }

    /// 处理 ineg 指令
    fn handleINeg(self: *ExpressionBuilder) !void {
        if (self.operand_stack.pop()) |operand| {
            const node = try self.ast_builder.createUnaryOp(.neg, operand);
            try self.operand_stack.push(node);
        }
    }

    /// 处理 ishl 指令
    fn handleIShl(self: *ExpressionBuilder) !void {
        try self.handleBinaryOp(.shl);
    }

    /// 处理 ishr 指令
    fn handleIShr(self: *ExpressionBuilder) !void {
        try self.handleBinaryOp(.shr);
    }

    /// 处理 iushr 指令
    fn handleIUShr(self: *ExpressionBuilder) !void {
        try self.handleBinaryOp(.ushr);
    }

    /// 处理 iand 指令
    fn handleIAnd(self: *ExpressionBuilder) !void {
        try self.handleBinaryOp(.bit_and);
    }

    /// 处理 ior 指令
    fn handleIOr(self: *ExpressionBuilder) !void {
        try self.handleBinaryOp(.bit_or);
    }

    /// 处理 ixor 指令
    fn handleIXor(self: *ExpressionBuilder) !void {
        try self.handleBinaryOp(.bit_xor);
    }

    /// 处理二元操作
    fn handleBinaryOp(self: *ExpressionBuilder, op: BinaryOp) !void {
        const right = self.operand_stack.pop();
        const left = self.operand_stack.pop();

        if (left != null and right != null) {
            const node = try self.ast_builder.createBinaryOp(op, left.?, right.?);
            try self.operand_stack.push(node);
        }
    }

    /// 处理 getstatic 指令
    fn handleGetStatic(self: *ExpressionBuilder, operands: []const u8) !void {
        if (operands.len < 2) return;
        const index = (@as(u16, operands[0]) << 8) | operands[1];
        const name = try std.fmt.allocPrint(self.allocator, "STATIC_FIELD_{any}", .{index});
        const node = try self.ast_builder.createIdentifier(name);
        try self.operand_stack.push(node);
    }

    /// 处理 putstatic 指令
    fn handlePutStatic(self: *ExpressionBuilder, operands: []const u8) !void {
        if (operands.len < 2) return;
        const index = (@as(u16, operands[0]) << 8) | operands[1];
        if (self.operand_stack.pop()) |value| {
            const field_name = try std.fmt.allocPrint(self.allocator, "STATIC_FIELD_{any}", .{index});
            const field_node = try self.ast_builder.createIdentifier(field_name);
            const assign_node = try ASTNode.init(self.allocator, .assignment);
            assign_node.data = .{ .assignment = .{ .operator = "=" } };
            try assign_node.addChild(field_node);
            try assign_node.addChild(value);
            try self.operand_stack.push(assign_node);
        }
    }

    /// 处理 getfield 指令
    fn handleGetField(self: *ExpressionBuilder, operands: []const u8) !void {
        if (operands.len < 2) return;
        const index = (@as(u16, operands[0]) << 8) | operands[1];
        if (self.operand_stack.pop()) |object| {
            const field_name = try std.fmt.allocPrint(self.allocator, "field_{any}", .{index});
            const node = try ASTNode.init(self.allocator, .field_access);
            node.data = .{ .field_access = .{ .field_name = field_name, .class_name = null, .is_static = false } };
            try node.addChild(object);
            try self.operand_stack.push(node);
        }
    }

    /// 处理 putfield 指令
    fn handlePutField(self: *ExpressionBuilder, operands: []const u8) !void {
        if (operands.len < 2) return;
        const index = (@as(u16, operands[0]) << 8) | operands[1];
        const value = self.operand_stack.pop();
        const object = self.operand_stack.pop();

        if (object != null and value != null) {
            const field_name = try std.fmt.allocPrint(self.allocator, "field_{any}", .{index});
            const field_node = try ASTNode.init(self.allocator, .field_access);
            field_node.data = .{ .field_access = .{ .field_name = field_name, .class_name = null, .is_static = false } };
            try field_node.addChild(object.?);

            const assign_node = try ASTNode.init(self.allocator, .assignment);
            assign_node.data = .{ .assignment = .{ .operator = "=" } };
            try assign_node.addChild(field_node);
            try assign_node.addChild(value.?);
            try self.operand_stack.push(assign_node);
        }
    }

    /// 处理 invokevirtual 指令
    fn handleInvokeVirtual(self: *ExpressionBuilder, operands: []const u8) !void {
        if (operands.len < 2) return;
        const index = (@as(u16, operands[0]) << 8) | operands[1];
        const method_name = try std.fmt.allocPrint(self.allocator, "method_{any}", .{index});
        const node = try self.ast_builder.createMethodCall(method_name, null, false);
        // 这里应该根据方法签名弹出相应数量的参数
        // 暂时只弹出对象引用
        if (self.operand_stack.pop()) |object| {
            try node.addChild(object);
        }
        try self.operand_stack.push(node);
    }

    /// 处理 invokespecial 指令
    fn handleInvokeSpecial(self: *ExpressionBuilder, operands: []const u8) !void {
        if (operands.len < 2) return;
        const index = (@as(u16, operands[0]) << 8) | operands[1];
        const method_name = try std.fmt.allocPrint(self.allocator, "special_method_{any}", .{index});
        const node = try self.ast_builder.createMethodCall(method_name, null, false);
        if (self.operand_stack.pop()) |object| {
            try node.addChild(object);
        }
        try self.operand_stack.push(node);
    }

    /// 处理 invokestatic 指令
    fn handleInvokeStatic(self: *ExpressionBuilder, operands: []const u8) !void {
        if (operands.len < 2) return;
        const index = (@as(u16, operands[0]) << 8) | operands[1];
        const method_name = try std.fmt.allocPrint(self.allocator, "static_method_{any}", .{index});
        const node = try self.ast_builder.createMethodCall(method_name, null, true);
        try self.operand_stack.push(node);
    }

    /// 处理 ireturn 指令
    fn handleIReturn(self: *ExpressionBuilder) !void {
        if (self.operand_stack.pop()) |value| {
            const node = try self.ast_builder.createReturn(value);
            try self.operand_stack.push(node);
        }
    }

    /// 处理 areturn 指令
    fn handleAReturn(self: *ExpressionBuilder) !void {
        if (self.operand_stack.pop()) |value| {
            const node = try self.ast_builder.createReturn(value);
            try self.operand_stack.push(node);
        }
    }

    /// 处理 return 指令
    fn handleReturn(self: *ExpressionBuilder) !void {
        const node = try self.ast_builder.createReturn(null);
        try self.operand_stack.push(node);
    }

    /// 获取当前栈顶表达式
    pub fn getCurrentExpression(self: *ExpressionBuilder) ?*ASTNode {
        return self.operand_stack.peek();
    }

    /// 重建方法体
    pub fn rebuildMethod(self: *ExpressionBuilder, instructions: []const Instruction) !*ASTNode {
        // 处理所有指令
        for (instructions) |instruction| {
            try self.processInstruction(instruction);
        }

        // 创建方法体块节点
        const method_body = try self.ast_builder.createBlock();

        // 如果栈中有表达式，将其作为方法体的内容
        if (self.getCurrentExpression()) |expr| {
            try method_body.addChild(expr);
        }

        return method_body;
    }

    /// 清空状态
    pub fn reset(self: *ExpressionBuilder) void {
        self.operand_stack.clear();
    }
};

// 测试
test "表达式重建基础功能测试" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var builder = ExpressionBuilder.init(allocator);
    defer builder.deinit();

    // 测试常量加载
    const iconst_1 = Instruction{ .opcode = 0x04, .operands = &[_]u8{}, .pc = 0 };
    try builder.processInstruction(iconst_1);
    try testing.expect(builder.operand_stack.size() == 1);

    const iconst_2 = Instruction{ .opcode = 0x05, .operands = &[_]u8{}, .pc = 1 };
    try builder.processInstruction(iconst_2);
    try testing.expect(builder.operand_stack.size() == 2);

    // 测试加法运算
    const iadd = Instruction{ .opcode = 0x60, .operands = &[_]u8{}, .pc = 2 };
    try builder.processInstruction(iadd);
    try testing.expect(builder.operand_stack.size() == 1);

    const result = builder.getCurrentExpression();
    try testing.expect(result != null);
    try testing.expect(result.?.node_type == .binary_op);
}
