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

/// 字节码指令类型（增强版）
pub const Instruction = struct {
    opcode: u8,
    operands: []const u8,
    pc: u32,
    line_number: ?u32 = null,

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
            0x09 => "lconst_0",
            0x0a => "lconst_1",
            0x0b => "fconst_0",
            0x0c => "fconst_1",
            0x0d => "fconst_2",
            0x0e => "dconst_0",
            0x0f => "dconst_1",
            0x10 => "bipush",
            0x11 => "sipush",
            0x12 => "ldc",
            0x13 => "ldc_w",
            0x14 => "ldc2_w",
            0x15 => "iload",
            0x16 => "lload",
            0x17 => "fload",
            0x18 => "dload",
            0x19 => "aload",
            0x1a => "iload_0",
            0x1b => "iload_1",
            0x1c => "iload_2",
            0x1d => "iload_3",
            0x1e => "lload_0",
            0x1f => "lload_1",
            0x20 => "lload_2",
            0x21 => "lload_3",
            0x22 => "fload_0",
            0x23 => "fload_1",
            0x24 => "fload_2",
            0x25 => "fload_3",
            0x26 => "dload_0",
            0x27 => "dload_1",
            0x28 => "dload_2",
            0x29 => "dload_3",
            0x2a => "aload_0",
            0x2b => "aload_1",
            0x2c => "aload_2",
            0x2d => "aload_3",
            0x2e => "iaload",
            0x2f => "laload",
            0x30 => "faload",
            0x31 => "daload",
            0x32 => "aaload",
            0x33 => "baload",
            0x34 => "caload",
            0x35 => "saload",
            0x36 => "istore",
            0x37 => "lstore",
            0x38 => "fstore",
            0x39 => "dstore",
            0x3a => "astore",
            0x3b => "istore_0",
            0x3c => "istore_1",
            0x3d => "istore_2",
            0x3e => "istore_3",
            0x3f => "lstore_0",
            0x40 => "lstore_1",
            0x41 => "lstore_2",
            0x42 => "lstore_3",
            0x43 => "fstore_0",
            0x44 => "fstore_1",
            0x45 => "fstore_2",
            0x46 => "fstore_3",
            0x47 => "dstore_0",
            0x48 => "dstore_1",
            0x49 => "dstore_2",
            0x4a => "dstore_3",
            0x4b => "astore_0",
            0x4c => "astore_1",
            0x4d => "astore_2",
            0x4e => "astore_3",
            0x4f => "iastore",
            0x50 => "lastore",
            0x51 => "fastore",
            0x52 => "dastore",
            0x53 => "aastore",
            0x54 => "bastore",
            0x55 => "castore",
            0x56 => "sastore",
            0x57 => "pop",
            0x58 => "pop2",
            0x59 => "dup",
            0x5a => "dup_x1",
            0x5b => "dup_x2",
            0x5c => "dup2",
            0x5d => "dup2_x1",
            0x5e => "dup2_x2",
            0x5f => "swap",
            0x60 => "iadd",
            0x61 => "ladd",
            0x62 => "fadd",
            0x63 => "dadd",
            0x64 => "isub",
            0x65 => "lsub",
            0x66 => "fsub",
            0x67 => "dsub",
            0x68 => "imul",
            0x69 => "lmul",
            0x6a => "fmul",
            0x6b => "dmul",
            0x6c => "idiv",
            0x6d => "ldiv",
            0x6e => "fdiv",
            0x6f => "ddiv",
            0x70 => "irem",
            0x71 => "lrem",
            0x72 => "frem",
            0x73 => "drem",
            0x74 => "ineg",
            0x75 => "lneg",
            0x76 => "fneg",
            0x77 => "dneg",
            0x78 => "ishl",
            0x79 => "lshl",
            0x7a => "ishr",
            0x7b => "lshr",
            0x7c => "iushr",
            0x7d => "lushr",
            0x7e => "iand",
            0x7f => "land",
            0x80 => "ior",
            0x81 => "lor",
            0x82 => "ixor",
            0x83 => "lxor",
            0x84 => "iinc",
            0x85 => "i2l",
            0x86 => "i2f",
            0x87 => "i2d",
            0x88 => "l2i",
            0x89 => "l2f",
            0x8a => "l2d",
            0x8b => "f2i",
            0x8c => "f2l",
            0x8d => "f2d",
            0x8e => "d2i",
            0x8f => "d2l",
            0x90 => "d2f",
            0x91 => "i2b",
            0x92 => "i2c",
            0x93 => "i2s",
            0x94 => "lcmp",
            0x95 => "fcmpl",
            0x96 => "fcmpg",
            0x97 => "dcmpl",
            0x98 => "dcmpg",
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
            0xa5 => "if_acmpeq",
            0xa6 => "if_acmpne",
            0xa7 => "goto",
            0xa8 => "jsr",
            0xa9 => "ret",
            0xaa => "tableswitch",
            0xab => "lookupswitch",
            0xac => "ireturn",
            0xad => "lreturn",
            0xae => "freturn",
            0xaf => "dreturn",
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
            0xba => "invokedynamic",
            0xbb => "new",
            0xbc => "newarray",
            0xbd => "anewarray",
            0xbe => "arraylength",
            0xbf => "athrow",
            0xc0 => "checkcast",
            0xc1 => "instanceof",
            0xc2 => "monitorenter",
            0xc3 => "monitorexit",
            0xc4 => "wide",
            0xc5 => "multianewarray",
            0xc6 => "ifnull",
            0xc7 => "ifnonnull",
            0xc8 => "goto_w",
            0xc9 => "jsr_w",
            else => "unknown",
        };
    }

    /// 获取指令的操作数栈效果
    pub fn getStackEffect(self: Instruction) i32 {
        return switch (self.opcode) {
            // 常量加载指令 (+1)
            0x01...0x14 => 1,
            // 局部变量加载指令 (+1)
            0x15...0x2d => 1,
            // 数组加载指令 (-1 for index, +1 for value = 0)
            0x2e...0x35 => -1,
            // 局部变量存储指令 (-1)
            0x36...0x4e => -1,
            // 数组存储指令 (-3: array, index, value)
            0x4f...0x56 => -3,
            // 栈操作指令
            0x57 => -1, // pop
            0x58 => -2, // pop2
            0x59 => 1, // dup
            0x5a => 1, // dup_x1
            0x5b => 1, // dup_x2
            0x5c => 2, // dup2
            0x5d => 2, // dup2_x1
            0x5e => 2, // dup2_x2
            0x5f => 0, // swap
            // 算术运算指令 (-1: two operands, +1 result = -1)
            0x60...0x73 => -1,
            // 一元运算指令 (0: one operand, one result)
            0x74...0x77 => 0,
            // 位运算指令 (-1)
            0x78...0x83 => -1,
            // 类型转换指令 (0)
            0x85...0x93 => 0,
            // 比较指令 (-1 or -3)
            0x94...0x98 => if (self.opcode == 0x94) -3 else -1,
            // 条件跳转指令 (-1 or -2)
            0x99...0xa6 => if (self.opcode <= 0x9e) -1 else -2,
            // 无条件跳转指令 (0)
            0xa7...0xa9 => 0,
            // 返回指令 (-1 or 0)
            0xac...0xb1 => if (self.opcode == 0xb1) 0 else -1,
            // 字段访问指令
            0xb2 => 1, // getstatic
            0xb3 => -1, // putstatic
            0xb4 => 0, // getfield (-1 object, +1 value)
            0xb5 => -2, // putfield (-1 object, -1 value)
            // 方法调用指令 (复杂，需要根据方法签名计算)
            0xb6...0xba => -1, // 简化处理
            // 对象创建指令
            0xbb => 1, // new
            0xbc => 0, // newarray (-1 count, +1 array)
            0xbd => 0, // anewarray
            0xbe => 0, // arraylength (-1 array, +1 length)
            0xbf => -1, // athrow
            // 类型检查指令 (0)
            0xc0...0xc1 => 0,
            // 同步指令 (-1)
            0xc2...0xc3 => -1,
            // 多维数组创建 (复杂)
            0xc5 => -1, // 简化处理
            // null检查指令 (-1)
            0xc6...0xc7 => -1,
            else => 0,
        };
    }
};

/// 常量池条目类型
pub const ConstantPoolEntry = union(enum) {
    utf8: []const u8,
    integer: i32,
    float: f32,
    long: i64,
    double: f64,
    class_ref: u16,
    string_ref: u16,
    field_ref: struct { class_index: u16, name_and_type_index: u16 },
    method_ref: struct { class_index: u16, name_and_type_index: u16 },
    interface_method_ref: struct { class_index: u16, name_and_type_index: u16 },
    name_and_type: struct { name_index: u16, descriptor_index: u16 },
    method_handle: struct { reference_kind: u8, reference_index: u16 },
    method_type: u16,
    invoke_dynamic: struct { bootstrap_method_attr_index: u16, name_and_type_index: u16 },
};

/// 常量池
pub const ConstantPool = struct {
    entries: ArrayList(ConstantPoolEntry),
    allocator: Allocator,

    /// 初始化常量池
    pub fn init(allocator: Allocator) ConstantPool {
        return ConstantPool{
            .entries = ArrayList(ConstantPoolEntry).init(allocator),
            .allocator = allocator,
        };
    }

    /// 释放常量池
    pub fn deinit(self: *ConstantPool) void {
        self.entries.deinit();
    }

    /// 获取常量池条目
    pub fn get(self: *ConstantPool, index: u16) ?ConstantPoolEntry {
        if (index == 0 or index > self.entries.items.len) return null;
        return self.entries.items[index - 1];
    }

    /// 添加常量池条目
    pub fn add(self: *ConstantPool, entry: ConstantPoolEntry) !u16 {
        try self.entries.append(entry);
        return @intCast(self.entries.items.len);
    }
};

/// 类型信息
pub const TypeInfo = struct {
    data_type: DataType,
    class_name: ?[]const u8 = null,
    array_dimensions: u8 = 0,
    is_nullable: bool = true,

    /// 创建基本类型信息
    pub fn primitive(data_type: DataType) TypeInfo {
        return TypeInfo{
            .data_type = data_type,
            .is_nullable = false,
        };
    }

    /// 创建对象类型信息
    pub fn object(class_name: []const u8) TypeInfo {
        return TypeInfo{
            .data_type = .object,
            .class_name = class_name,
        };
    }

    /// 创建数组类型信息
    pub fn array(_: DataType, dimensions: u8) TypeInfo {
        return TypeInfo{
            .data_type = .array,
            .array_dimensions = dimensions,
        };
    }
};

/// 操作数栈模拟（增强版）
pub const OperandStack = struct {
    stack: ArrayList(*ASTNode),
    type_stack: ArrayList(TypeInfo),
    allocator: Allocator,

    /// 初始化操作数栈
    pub fn init(allocator: Allocator) OperandStack {
        return OperandStack{
            .stack = ArrayList(*ASTNode).init(allocator),
            .type_stack = ArrayList(TypeInfo).init(allocator),
            .allocator = allocator,
        };
    }

    /// 释放操作数栈
    pub fn deinit(self: *OperandStack) void {
        self.stack.deinit();
        self.type_stack.deinit();
    }

    /// 压栈
    pub fn push(self: *OperandStack, node: *ASTNode) !void {
        try self.stack.append(node);
        try self.type_stack.append(self.inferType(node));
    }

    /// 压栈（带类型信息）
    pub fn pushWithType(self: *OperandStack, node: *ASTNode, type_info: TypeInfo) !void {
        try self.stack.append(node);
        try self.type_stack.append(type_info);
    }

    /// 弹栈
    pub fn pop(self: *OperandStack) ?*ASTNode {
        if (self.stack.items.len == 0) return null;
        _ = self.type_stack.pop();
        return self.stack.pop();
    }

    /// 弹栈（带类型信息）
    pub fn popWithType(self: *OperandStack) ?struct { node: *ASTNode, type_info: TypeInfo } {
        if (self.stack.items.len == 0) return null;
        const type_info = self.type_stack.pop();
        const node = self.stack.pop();
        return .{ .node = node, .type_info = type_info };
    }

    /// 查看栈顶
    pub fn peek(self: *OperandStack) ?*ASTNode {
        if (self.stack.items.len == 0) return null;
        return self.stack.items[self.stack.items.len - 1];
    }

    /// 查看栈顶类型
    pub fn peekType(self: *OperandStack) ?TypeInfo {
        if (self.type_stack.items.len == 0) return null;
        return self.type_stack.items[self.type_stack.items.len - 1];
    }

    /// 获取栈大小
    pub fn size(self: *OperandStack) usize {
        return self.stack.items.len;
    }

    /// 清空栈
    pub fn clear(self: *OperandStack) void {
        self.stack.clearRetainingCapacity();
        self.type_stack.clearRetainingCapacity();
    }

    /// 推断节点类型
    fn inferType(self: *OperandStack, node: *ASTNode) TypeInfo {
        _ = self;
        return switch (node.node_type) {
            .literal => {
                const value = node.data.literal.value;
                return switch (value) {
                    .int_val => TypeInfo.primitive(.int),
                    .float_val => TypeInfo.primitive(.float),
                    .string_val => TypeInfo.object("java/lang/String"),
                    .bool_val => TypeInfo.primitive(.boolean),
                    .null_val => TypeInfo{ .data_type = .object, .is_nullable = true },
                };
            },
            .binary_op => TypeInfo.primitive(.int), // 简化处理
            .unary_op => TypeInfo.primitive(.int), // 简化处理
            .method_call => TypeInfo.primitive(.int), // 需要根据方法签名推断
            .field_access => TypeInfo.primitive(.int), // 需要根据字段类型推断
            .array_access => TypeInfo.primitive(.int), // 需要根据数组元素类型推断
            else => TypeInfo.primitive(.int),
        };
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

/// 表达式重建器（增强版）
pub const ExpressionBuilder = struct {
    allocator: Allocator,
    ast_builder: ASTBuilder,
    operand_stack: OperandStack,
    local_variables: LocalVariables,
    constant_pool: ?*ConstantPool = null,
    current_method_signature: ?[]const u8 = null,
    exception_handlers: ArrayList(ExceptionHandler),

    /// 异常处理器信息
    pub const ExceptionHandler = struct {
        start_pc: u32,
        end_pc: u32,
        handler_pc: u32,
        catch_type: ?u16, // 常量池索引，null表示finally
    };

    /// 初始化表达式重建器
    pub fn init(allocator: Allocator) ExpressionBuilder {
        return ExpressionBuilder{
            .allocator = allocator,
            .ast_builder = ASTBuilder.init(allocator),
            .operand_stack = OperandStack.init(allocator),
            .local_variables = LocalVariables.init(allocator),
            .exception_handlers = ArrayList(ExceptionHandler).init(allocator),
        };
    }

    /// 释放表达式重建器
    pub fn deinit(self: *ExpressionBuilder) void {
        self.ast_builder.deinit();
        self.operand_stack.deinit();
        self.local_variables.deinit();
        self.exception_handlers.deinit();
    }

    /// 设置常量池
    pub fn setConstantPool(self: *ExpressionBuilder, constant_pool: *ConstantPool) void {
        self.constant_pool = constant_pool;
    }

    /// 设置当前方法签名
    pub fn setMethodSignature(self: *ExpressionBuilder, signature: []const u8) void {
        self.current_method_signature = signature;
    }

    /// 添加异常处理器
    pub fn addExceptionHandler(self: *ExpressionBuilder, handler: ExceptionHandler) !void {
        try self.exception_handlers.append(handler);
    }

    /// 处理单个指令（增强版）
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
            0x09 => try self.handleLConst(0),
            0x0a => try self.handleLConst(1),
            0x0b => try self.handleFConst(0.0),
            0x0c => try self.handleFConst(1.0),
            0x0d => try self.handleFConst(2.0),
            0x0e => try self.handleDConst(0.0),
            0x0f => try self.handleDConst(1.0),
            0x10 => try self.handleBiPush(instruction.operands),
            0x11 => try self.handleSiPush(instruction.operands),
            0x12 => try self.handleLdc(instruction.operands),
            0x13 => try self.handleLdcW(instruction.operands),
            0x14 => try self.handleLdc2W(instruction.operands),

            // 局部变量加载指令
            0x15 => try self.handleILoad(instruction.operands),
            0x16 => try self.handleLLoad(instruction.operands),
            0x17 => try self.handleFLoad(instruction.operands),
            0x18 => try self.handleDLoad(instruction.operands),
            0x19 => try self.handleALoad(instruction.operands),
            0x1a => try self.handleILoad0(),
            0x1b => try self.handleILoad1(),
            0x1c => try self.handleILoad2(),
            0x1d => try self.handleILoad3(),
            0x1e => try self.handleLLoad0(),
            0x1f => try self.handleLLoad1(),
            0x20 => try self.handleLLoad2(),
            0x21 => try self.handleLLoad3(),
            0x22 => try self.handleFLoad0(),
            0x23 => try self.handleFLoad1(),
            0x24 => try self.handleFLoad2(),
            0x25 => try self.handleFLoad3(),
            0x26 => try self.handleDLoad0(),
            0x27 => try self.handleDLoad1(),
            0x28 => try self.handleDLoad2(),
            0x29 => try self.handleDLoad3(),
            0x2a => try self.handleALoad0(),
            0x2b => try self.handleALoad1(),
            0x2c => try self.handleALoad2(),
            0x2d => try self.handleALoad3(),

            // 数组加载指令
            0x2e => try self.handleIALoad(),
            0x2f => try self.handleLALoad(),
            0x30 => try self.handleFALoad(),
            0x31 => try self.handleDALoad(),
            0x32 => try self.handleAALoad(),
            0x33 => try self.handleBALoad(),
            0x34 => try self.handleCALoad(),
            0x35 => try self.handleSALoad(),

            // 局部变量存储指令
            0x36 => try self.handleIStore(instruction.operands),
            0x37 => try self.handleLStore(instruction.operands),
            0x38 => try self.handleFStore(instruction.operands),
            0x39 => try self.handleDStore(instruction.operands),
            0x3a => try self.handleAStore(instruction.operands),
            0x3b => try self.handleIStore0(),
            0x3c => try self.handleIStore1(),
            0x3d => try self.handleIStore2(),
            0x3e => try self.handleIStore3(),
            0x3f => try self.handleLStore0(),
            0x40 => try self.handleLStore1(),
            0x41 => try self.handleLStore2(),
            0x42 => try self.handleLStore3(),
            0x43 => try self.handleFStore0(),
            0x44 => try self.handleFStore1(),
            0x45 => try self.handleFStore2(),
            0x46 => try self.handleFStore3(),
            0x47 => try self.handleDStore0(),
            0x48 => try self.handleDStore1(),
            0x49 => try self.handleDStore2(),
            0x4a => try self.handleDStore3(),
            0x4b => try self.handleAStore0(),
            0x4c => try self.handleAStore1(),
            0x4d => try self.handleAStore2(),
            0x4e => try self.handleAStore3(),

            // 数组存储指令
            0x4f => try self.handleIAStore(),
            0x50 => try self.handleLAStore(),
            0x51 => try self.handleFAStore(),
            0x52 => try self.handleDAStore(),
            0x53 => try self.handleAAStore(),
            0x54 => try self.handleBAStore(),
            0x55 => try self.handleCAStore(),
            0x56 => try self.handleSAStore(),

            // 栈操作指令
            0x57 => try self.handlePop(),
            0x58 => try self.handlePop2(),
            0x59 => try self.handleDup(),
            0x5a => try self.handleDupX1(),
            0x5b => try self.handleDupX2(),
            0x5c => try self.handleDup2(),
            0x5d => try self.handleDup2X1(),
            0x5e => try self.handleDup2X2(),
            0x5f => try self.handleSwap(),

            // 算术运算指令
            0x60 => try self.handleIAdd(),
            0x61 => try self.handleLAdd(),
            0x62 => try self.handleFAdd(),
            0x63 => try self.handleDAdd(),
            0x64 => try self.handleISub(),
            0x65 => try self.handleLSub(),
            0x66 => try self.handleFSub(),
            0x67 => try self.handleDSub(),
            0x68 => try self.handleIMul(),
            0x69 => try self.handleLMul(),
            0x6a => try self.handleFMul(),
            0x6b => try self.handleDMul(),
            0x6c => try self.handleIDiv(),
            0x6d => try self.handleLDiv(),
            0x6e => try self.handleFDiv(),
            0x6f => try self.handleDDiv(),
            0x70 => try self.handleIRem(),
            0x71 => try self.handleLRem(),
            0x72 => try self.handleFRem(),
            0x73 => try self.handleDRem(),
            0x74 => try self.handleINeg(),
            0x75 => try self.handleLNeg(),
            0x76 => try self.handleFNeg(),
            0x77 => try self.handleDNeg(),

            // 位运算指令
            0x78 => try self.handleIShl(),
            0x79 => try self.handleLShl(),
            0x7a => try self.handleIShr(),
            0x7b => try self.handleLShr(),
            0x7c => try self.handleIUShr(),
            0x7d => try self.handleLUShr(),
            0x7e => try self.handleIAnd(),
            0x7f => try self.handleLAnd(),
            0x80 => try self.handleIOr(),
            0x81 => try self.handleLOr(),
            0x82 => try self.handleIXor(),
            0x83 => try self.handleLXor(),
            0x84 => try self.handleIInc(instruction.operands),

            // 类型转换指令
            0x85 => try self.handleI2L(),
            0x86 => try self.handleI2F(),
            0x87 => try self.handleI2D(),
            0x88 => try self.handleL2I(),
            0x89 => try self.handleL2F(),
            0x8a => try self.handleL2D(),
            0x8b => try self.handleF2I(),
            0x8c => try self.handleF2L(),
            0x8d => try self.handleF2D(),
            0x8e => try self.handleD2I(),
            0x8f => try self.handleD2L(),
            0x90 => try self.handleD2F(),
            0x91 => try self.handleI2B(),
            0x92 => try self.handleI2C(),
            0x93 => try self.handleI2S(),

            // 比较指令
            0x94 => try self.handleLCmp(),
            0x95 => try self.handleFCmpL(),
            0x96 => try self.handleFCmpG(),
            0x97 => try self.handleDCmpL(),
            0x98 => try self.handleDCmpG(),

            // 条件跳转指令
            0x99 => try self.handleIfEq(instruction.operands),
            0x9a => try self.handleIfNe(instruction.operands),
            0x9b => try self.handleIfLt(instruction.operands),
            0x9c => try self.handleIfGe(instruction.operands),
            0x9d => try self.handleIfGt(instruction.operands),
            0x9e => try self.handleIfLe(instruction.operands),
            0x9f => try self.handleIfICmpEq(instruction.operands),
            0xa0 => try self.handleIfICmpNe(instruction.operands),
            0xa1 => try self.handleIfICmpLt(instruction.operands),
            0xa2 => try self.handleIfICmpGe(instruction.operands),
            0xa3 => try self.handleIfICmpGt(instruction.operands),
            0xa4 => try self.handleIfICmpLe(instruction.operands),
            0xa5 => try self.handleIfACmpEq(instruction.operands),
            0xa6 => try self.handleIfACmpNe(instruction.operands),

            // 无条件跳转指令
            0xa7 => try self.handleGoto(instruction.operands),
            0xa8 => try self.handleJsr(instruction.operands),
            0xa9 => try self.handleRet(instruction.operands),

            // 表跳转指令
            0xaa => try self.handleTableSwitch(instruction.operands),
            0xab => try self.handleLookupSwitch(instruction.operands),

            // 返回指令
            0xac => try self.handleIReturn(),
            0xad => try self.handleLReturn(),
            0xae => try self.handleFReturn(),
            0xaf => try self.handleDReturn(),
            0xb0 => try self.handleAReturn(),
            0xb1 => try self.handleReturn(),

            // 字段访问指令
            0xb2 => try self.handleGetStatic(instruction.operands),
            0xb3 => try self.handlePutStatic(instruction.operands),
            0xb4 => try self.handleGetField(instruction.operands),
            0xb5 => try self.handlePutField(instruction.operands),

            // 方法调用指令
            0xb6 => try self.handleInvokeVirtual(instruction.operands),
            0xb7 => try self.handleInvokeSpecial(instruction.operands),
            0xb8 => try self.handleInvokeStatic(instruction.operands),
            0xb9 => try self.handleInvokeInterface(instruction.operands),
            0xba => try self.handleInvokeDynamic(instruction.operands),

            // 对象和数组操作指令
            0xbb => try self.handleNew(instruction.operands),
            0xbc => try self.handleNewArray(instruction.operands),
            0xbd => try self.handleANewArray(instruction.operands),
            0xbe => try self.handleArrayLength(),
            0xbf => try self.handleAThrow(),

            // 类型检查指令
            0xc0 => try self.handleCheckCast(instruction.operands),
            0xc1 => try self.handleInstanceOf(instruction.operands),

            // 同步指令
            0xc2 => try self.handleMonitorEnter(),
            0xc3 => try self.handleMonitorExit(),

            // 扩展指令
            0xc4 => try self.handleWide(instruction.operands),
            0xc5 => try self.handleMultiANewArray(instruction.operands),
            0xc6 => try self.handleIfNull(instruction.operands),
            0xc7 => try self.handleIfNonNull(instruction.operands),
            0xc8 => try self.handleGotoW(instruction.operands),
            0xc9 => try self.handleJsrW(instruction.operands),

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

    /// 处理 lconst 指令
    fn handleLConst(self: *ExpressionBuilder, value: i64) !void {
        const node = try self.ast_builder.createLiteral(.{ .int_val = value }, .long);
        try self.operand_stack.push(node);
    }

    /// 处理 fconst 指令
    fn handleFConst(self: *ExpressionBuilder, value: f32) !void {
        const node = try self.ast_builder.createLiteral(.{ .float_val = value }, .float);
        try self.operand_stack.push(node);
    }

    /// 处理 dconst 指令
    fn handleDConst(self: *ExpressionBuilder, value: f64) !void {
        const node = try self.ast_builder.createLiteral(.{ .float_val = value }, .double);
        try self.operand_stack.push(node);
    }

    /// 处理 ldc_w 指令
    fn handleLdcW(self: *ExpressionBuilder, operands: []const u8) !void {
        if (operands.len < 2) return;
        const index = (@as(u16, operands[0]) << 8) | operands[1];
        try self.loadConstant(index);
    }

    /// 处理 ldc2_w 指令
    fn handleLdc2W(self: *ExpressionBuilder, operands: []const u8) !void {
        if (operands.len < 2) return;
        const index = (@as(u16, operands[0]) << 8) | operands[1];
        try self.loadConstant(index);
    }

    /// 从常量池加载常量
    fn loadConstant(self: *ExpressionBuilder, index: u16) !void {
        if (self.constant_pool) |cp| {
            if (cp.get(index)) |entry| {
                const node = switch (entry) {
                    .integer => |val| try self.ast_builder.createLiteral(.{ .int_val = val }, .int),
                    .float => |val| try self.ast_builder.createLiteral(.{ .float_val = val }, .float),
                    .long => |val| try self.ast_builder.createLiteral(.{ .int_val = val }, .long),
                    .double => |val| try self.ast_builder.createLiteral(.{ .float_val = val }, .double),
                    .string_ref => |_| try self.ast_builder.createLiteral(.{ .string_val = "STRING_CONST" }, .object),
                    else => try self.ast_builder.createIdentifier("UNKNOWN_CONST"),
                };
                try self.operand_stack.push(node);
                return;
            }
        }
        // 如果没有常量池或找不到条目，创建占位符
        const name = try std.fmt.allocPrint(self.allocator, "CONST_{}", .{index});
        const node = try self.ast_builder.createIdentifier(name);
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

    /// 处理 lload 指令
    fn handleLLoad(self: *ExpressionBuilder, operands: []const u8) !void {
        if (operands.len < 1) return;
        const index = operands[0];
        try self.loadLocalVariable(index);
    }

    /// 处理 fload 指令
    fn handleFLoad(self: *ExpressionBuilder, operands: []const u8) !void {
        if (operands.len < 1) return;
        const index = operands[0];
        try self.loadLocalVariable(index);
    }

    /// 处理 dload 指令
    fn handleDLoad(self: *ExpressionBuilder, operands: []const u8) !void {
        if (operands.len < 1) return;
        const index = operands[0];
        try self.loadLocalVariable(index);
    }

    /// 处理 lload_0 指令
    fn handleLLoad0(self: *ExpressionBuilder) !void {
        try self.loadLocalVariable(0);
    }

    /// 处理 lload_1 指令
    fn handleLLoad1(self: *ExpressionBuilder) !void {
        try self.loadLocalVariable(1);
    }

    /// 处理 lload_2 指令
    fn handleLLoad2(self: *ExpressionBuilder) !void {
        try self.loadLocalVariable(2);
    }

    /// 处理 lload_3 指令
    fn handleLLoad3(self: *ExpressionBuilder) !void {
        try self.loadLocalVariable(3);
    }

    /// 处理 fload_0 指令
    fn handleFLoad0(self: *ExpressionBuilder) !void {
        try self.loadLocalVariable(0);
    }

    /// 处理 fload_1 指令
    fn handleFLoad1(self: *ExpressionBuilder) !void {
        try self.loadLocalVariable(1);
    }

    /// 处理 fload_2 指令
    fn handleFLoad2(self: *ExpressionBuilder) !void {
        try self.loadLocalVariable(2);
    }

    /// 处理 fload_3 指令
    fn handleFLoad3(self: *ExpressionBuilder) !void {
        try self.loadLocalVariable(3);
    }

    /// 处理 dload_0 指令
    fn handleDLoad0(self: *ExpressionBuilder) !void {
        try self.loadLocalVariable(0);
    }

    /// 处理 dload_1 指令
    fn handleDLoad1(self: *ExpressionBuilder) !void {
        try self.loadLocalVariable(1);
    }

    /// 处理 dload_2 指令
    fn handleDLoad2(self: *ExpressionBuilder) !void {
        try self.loadLocalVariable(2);
    }

    /// 处理 dload_3 指令
    fn handleDLoad3(self: *ExpressionBuilder) !void {
        try self.loadLocalVariable(3);
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

    /// 处理 iaload 指令
    fn handleIALoad(self: *ExpressionBuilder) !void {
        try self.handleArrayLoad(.int);
    }

    /// 处理 laload 指令
    fn handleLALoad(self: *ExpressionBuilder) !void {
        try self.handleArrayLoad(.long);
    }

    /// 处理 faload 指令
    fn handleFALoad(self: *ExpressionBuilder) !void {
        try self.handleArrayLoad(.float);
    }

    /// 处理 daload 指令
    fn handleDALoad(self: *ExpressionBuilder) !void {
        try self.handleArrayLoad(.double);
    }

    /// 处理 aaload 指令
    fn handleAALoad(self: *ExpressionBuilder) !void {
        try self.handleArrayLoad(.object);
    }

    /// 处理 baload 指令
    fn handleBALoad(self: *ExpressionBuilder) !void {
        try self.handleArrayLoad(.byte);
    }

    /// 处理 caload 指令
    fn handleCALoad(self: *ExpressionBuilder) !void {
        try self.handleArrayLoad(.char);
    }

    /// 处理 saload 指令
    fn handleSALoad(self: *ExpressionBuilder) !void {
        try self.handleArrayLoad(.short);
    }

    /// 通用数组加载处理
    fn handleArrayLoad(self: *ExpressionBuilder, element_type: ast.DataType) !void {
        const index = self.operand_stack.pop() orelse return;
        const array_ref = self.operand_stack.pop() orelse return;

        const access_node = try self.allocator.create(ast.ASTNode);
        access_node.* = ast.ASTNode{
            .node_type = .array_access,
            .data_type = null,
            .children = ArrayList(*ast.ASTNode).init(self.allocator),
            .data = .{ .none = {} },
            .parent = null,
            .allocator = self.allocator,
        };
        try access_node.children.append(array_ref);
        try access_node.children.append(index);

        try self.operand_stack.push(access_node);
        try self.operand_stack.pushWithType(access_node, TypeInfo.primitive(element_type));
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

    /// 处理 lstore 指令
    fn handleLStore(self: *ExpressionBuilder, operands: []const u8) !void {
        if (operands.len < 1) return;
        const index = operands[0];
        try self.storeLocalVariable(index);
    }

    /// 处理 fstore 指令
    fn handleFStore(self: *ExpressionBuilder, operands: []const u8) !void {
        if (operands.len < 1) return;
        const index = operands[0];
        try self.storeLocalVariable(index);
    }

    /// 处理 dstore 指令
    fn handleDStore(self: *ExpressionBuilder, operands: []const u8) !void {
        if (operands.len < 1) return;
        const index = operands[0];
        try self.storeLocalVariable(index);
    }

    /// 处理 lstore_0 指令
    fn handleLStore0(self: *ExpressionBuilder) !void {
        try self.storeLocalVariable(0);
    }

    /// 处理 lstore_1 指令
    fn handleLStore1(self: *ExpressionBuilder) !void {
        try self.storeLocalVariable(1);
    }

    /// 处理 lstore_2 指令
    fn handleLStore2(self: *ExpressionBuilder) !void {
        try self.storeLocalVariable(2);
    }

    /// 处理 lstore_3 指令
    fn handleLStore3(self: *ExpressionBuilder) !void {
        try self.storeLocalVariable(3);
    }

    /// 处理 fstore_0 指令
    fn handleFStore0(self: *ExpressionBuilder) !void {
        try self.storeLocalVariable(0);
    }

    /// 处理 fstore_1 指令
    fn handleFStore1(self: *ExpressionBuilder) !void {
        try self.storeLocalVariable(1);
    }

    /// 处理 fstore_2 指令
    fn handleFStore2(self: *ExpressionBuilder) !void {
        try self.storeLocalVariable(2);
    }

    /// 处理 fstore_3 指令
    fn handleFStore3(self: *ExpressionBuilder) !void {
        try self.storeLocalVariable(3);
    }

    /// 处理 dstore_0 指令
    fn handleDStore0(self: *ExpressionBuilder) !void {
        try self.storeLocalVariable(0);
    }

    /// 处理 dstore_1 指令
    fn handleDStore1(self: *ExpressionBuilder) !void {
        try self.storeLocalVariable(1);
    }

    /// 处理 dstore_2 指令
    fn handleDStore2(self: *ExpressionBuilder) !void {
        try self.storeLocalVariable(2);
    }

    /// 处理 dstore_3 指令
    fn handleDStore3(self: *ExpressionBuilder) !void {
        try self.storeLocalVariable(3);
    }

    /// 处理数组存储指令
    fn handleIAStore(self: *ExpressionBuilder) !void {
        try self.handleArrayStore();
    }

    fn handleLAStore(self: *ExpressionBuilder) !void {
        try self.handleArrayStore();
    }

    fn handleFAStore(self: *ExpressionBuilder) !void {
        try self.handleArrayStore();
    }

    fn handleDAStore(self: *ExpressionBuilder) !void {
        try self.handleArrayStore();
    }

    fn handleAAStore(self: *ExpressionBuilder) !void {
        try self.handleArrayStore();
    }

    fn handleBAStore(self: *ExpressionBuilder) !void {
        try self.handleArrayStore();
    }

    fn handleCAStore(self: *ExpressionBuilder) !void {
        try self.handleArrayStore();
    }

    fn handleSAStore(self: *ExpressionBuilder) !void {
        try self.handleArrayStore();
    }

    /// 通用数组存储处理
    fn handleArrayStore(self: *ExpressionBuilder) !void {
        const value = self.operand_stack.pop() orelse return;
        const index = self.operand_stack.pop() orelse return;
        const array_ref = self.operand_stack.pop() orelse return;

        const access_node = try self.allocator.create(ast.ASTNode);
        access_node.* = ast.ASTNode{
            .node_type = .array_access,
            .data_type = null,
            .children = ArrayList(*ast.ASTNode).init(self.allocator),
            .data = .{ .none = {} },
            .parent = null,
            .allocator = self.allocator,
        };
        try access_node.children.append(array_ref);
        try access_node.children.append(index);

        const assign_node = try self.allocator.create(ast.ASTNode);
        assign_node.* = ast.ASTNode{
            .node_type = .assignment,
            .data_type = null,
            .children = ArrayList(*ast.ASTNode).init(self.allocator),
            .data = .{ .assignment = .{ .operator = "=" } },
            .parent = null,
            .allocator = self.allocator,
        };
        try assign_node.children.append(access_node);
        try assign_node.children.append(value);

        // 数组存储通常作为语句处理，这里暂时推入栈中
        try self.operand_stack.push(assign_node);
    }

    /// 栈操作指令
    fn handlePop(self: *ExpressionBuilder) !void {
        _ = self.operand_stack.pop();
    }

    fn handlePop2(self: *ExpressionBuilder) !void {
        _ = self.operand_stack.pop();
        _ = self.operand_stack.pop();
    }

    fn handleDup(self: *ExpressionBuilder) !void {
        if (self.operand_stack.peek()) |top| {
            try self.operand_stack.push(top);
        }
    }

    fn handleDupX1(self: *ExpressionBuilder) !void {
        const value1 = self.operand_stack.pop() orelse return;
        const value2 = self.operand_stack.pop() orelse return;
        try self.operand_stack.push(value1);
        try self.operand_stack.push(value2);
        try self.operand_stack.push(value1);
    }

    fn handleDupX2(self: *ExpressionBuilder) !void {
        const value1 = self.operand_stack.pop() orelse return;
        const value2 = self.operand_stack.pop() orelse return;
        const value3 = self.operand_stack.pop() orelse return;
        try self.operand_stack.push(value1);
        try self.operand_stack.push(value3);
        try self.operand_stack.push(value2);
        try self.operand_stack.push(value1);
    }

    fn handleDup2(self: *ExpressionBuilder) !void {
        const value1 = self.operand_stack.pop() orelse return;
        const value2 = self.operand_stack.pop() orelse return;
        try self.operand_stack.push(value2);
        try self.operand_stack.push(value1);
        try self.operand_stack.push(value2);
        try self.operand_stack.push(value1);
    }

    fn handleDup2X1(self: *ExpressionBuilder) !void {
        const value1 = self.operand_stack.pop() orelse return;
        const value2 = self.operand_stack.pop() orelse return;
        const value3 = self.operand_stack.pop() orelse return;
        try self.operand_stack.push(value2);
        try self.operand_stack.push(value1);
        try self.operand_stack.push(value3);
        try self.operand_stack.push(value2);
        try self.operand_stack.push(value1);
    }

    fn handleDup2X2(self: *ExpressionBuilder) !void {
        const value1 = self.operand_stack.pop() orelse return;
        const value2 = self.operand_stack.pop() orelse return;
        const value3 = self.operand_stack.pop() orelse return;
        const value4 = self.operand_stack.pop() orelse return;
        try self.operand_stack.push(value2);
        try self.operand_stack.push(value1);
        try self.operand_stack.push(value4);
        try self.operand_stack.push(value3);
        try self.operand_stack.push(value2);
        try self.operand_stack.push(value1);
    }

    fn handleSwap(self: *ExpressionBuilder) !void {
        const value1 = self.operand_stack.pop() orelse return;
        const value2 = self.operand_stack.pop() orelse return;
        try self.operand_stack.push(value1);
        try self.operand_stack.push(value2);
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

    /// 处理 ladd 指令
    fn handleLAdd(self: *ExpressionBuilder) !void {
        try self.handleBinaryOp(.add);
    }

    /// 处理 fadd 指令
    fn handleFAdd(self: *ExpressionBuilder) !void {
        try self.handleBinaryOp(.add);
    }

    /// 处理 dadd 指令
    fn handleDAdd(self: *ExpressionBuilder) !void {
        try self.handleBinaryOp(.add);
    }

    /// 处理 isub 指令
    fn handleISub(self: *ExpressionBuilder) !void {
        try self.handleBinaryOp(.sub);
    }

    /// 处理 lsub 指令
    fn handleLSub(self: *ExpressionBuilder) !void {
        try self.handleBinaryOp(.sub);
    }

    /// 处理 fsub 指令
    fn handleFSub(self: *ExpressionBuilder) !void {
        try self.handleBinaryOp(.sub);
    }

    /// 处理 dsub 指令
    fn handleDSub(self: *ExpressionBuilder) !void {
        try self.handleBinaryOp(.sub);
    }

    /// 处理 imul 指令
    fn handleIMul(self: *ExpressionBuilder) !void {
        try self.handleBinaryOp(.mul);
    }

    /// 处理 lmul 指令
    fn handleLMul(self: *ExpressionBuilder) !void {
        try self.handleBinaryOp(.mul);
    }

    /// 处理 fmul 指令
    fn handleFMul(self: *ExpressionBuilder) !void {
        try self.handleBinaryOp(.mul);
    }

    /// 处理 dmul 指令
    fn handleDMul(self: *ExpressionBuilder) !void {
        try self.handleBinaryOp(.mul);
    }

    /// 处理 idiv 指令
    fn handleIDiv(self: *ExpressionBuilder) !void {
        try self.handleBinaryOp(.div);
    }

    /// 处理 ldiv 指令
    fn handleLDiv(self: *ExpressionBuilder) !void {
        try self.handleBinaryOp(.div);
    }

    /// 处理 fdiv 指令
    fn handleFDiv(self: *ExpressionBuilder) !void {
        try self.handleBinaryOp(.div);
    }

    /// 处理 ddiv 指令
    fn handleDDiv(self: *ExpressionBuilder) !void {
        try self.handleBinaryOp(.div);
    }

    /// 处理 irem 指令
    fn handleIRem(self: *ExpressionBuilder) !void {
        try self.handleBinaryOp(.mod);
    }

    /// 处理 lrem 指令
    fn handleLRem(self: *ExpressionBuilder) !void {
        try self.handleBinaryOp(.mod);
    }

    /// 处理 frem 指令
    fn handleFRem(self: *ExpressionBuilder) !void {
        try self.handleBinaryOp(.mod);
    }

    /// 处理 drem 指令
    fn handleDRem(self: *ExpressionBuilder) !void {
        try self.handleBinaryOp(.mod);
    }

    /// 处理 ineg 指令
    fn handleINeg(self: *ExpressionBuilder) !void {
        if (self.operand_stack.pop()) |operand| {
            const node = try self.ast_builder.createUnaryOp(.neg, operand);
            try self.operand_stack.push(node);
        }
    }

    /// 处理 lneg 指令
    fn handleLNeg(self: *ExpressionBuilder) !void {
        if (self.operand_stack.pop()) |operand| {
            const node = try self.ast_builder.createUnaryOp(.neg, operand);
            try self.operand_stack.push(node);
        }
    }

    /// 处理 fneg 指令
    fn handleFNeg(self: *ExpressionBuilder) !void {
        if (self.operand_stack.pop()) |operand| {
            const node = try self.ast_builder.createUnaryOp(.neg, operand);
            try self.operand_stack.push(node);
        }
    }

    /// 处理 dneg 指令
    fn handleDNeg(self: *ExpressionBuilder) !void {
        if (self.operand_stack.pop()) |operand| {
            const node = try self.ast_builder.createUnaryOp(.neg, operand);
            try self.operand_stack.push(node);
        }
    }

    /// 处理 ishl 指令
    fn handleIShl(self: *ExpressionBuilder) !void {
        try self.handleBinaryOp(.shl);
    }

    /// 处理 lshl 指令
    fn handleLShl(self: *ExpressionBuilder) !void {
        try self.handleBinaryOp(.shl);
    }

    /// 处理 ishr 指令
    fn handleIShr(self: *ExpressionBuilder) !void {
        try self.handleBinaryOp(.shr);
    }

    /// 处理 lshr 指令
    fn handleLShr(self: *ExpressionBuilder) !void {
        try self.handleBinaryOp(.shr);
    }

    /// 处理 iushr 指令
    fn handleIUShr(self: *ExpressionBuilder) !void {
        try self.handleBinaryOp(.ushr);
    }

    /// 处理 lushr 指令
    fn handleLUShr(self: *ExpressionBuilder) !void {
        try self.handleBinaryOp(.ushr);
    }

    /// 处理 iand 指令
    fn handleIAnd(self: *ExpressionBuilder) !void {
        try self.handleBinaryOp(.bit_and);
    }

    /// 处理 land 指令
    fn handleLAnd(self: *ExpressionBuilder) !void {
        try self.handleBinaryOp(.bit_and);
    }

    /// 处理 ior 指令
    fn handleIOr(self: *ExpressionBuilder) !void {
        try self.handleBinaryOp(.bit_or);
    }

    /// 处理 lor 指令
    fn handleLOr(self: *ExpressionBuilder) !void {
        try self.handleBinaryOp(.bit_or);
    }

    /// 处理 ixor 指令
    fn handleIXor(self: *ExpressionBuilder) !void {
        try self.handleBinaryOp(.bit_xor);
    }

    /// 处理 lxor 指令
    fn handleLXor(self: *ExpressionBuilder) !void {
        try self.handleBinaryOp(.bit_xor);
    }

    /// 处理 iinc 指令
    fn handleIInc(self: *ExpressionBuilder, operands: []const u8) !void {
        if (operands.len < 2) return;
        const index = operands[0];
        const increment = @as(i8, @bitCast(operands[1]));

        // 创建局部变量标识符
        const var_name = try std.fmt.allocPrint(self.allocator, "local_{d}", .{index});
        const var_node = try self.ast_builder.createIdentifier(var_name);

        // 创建增量值节点
        const increment_node = try self.ast_builder.createIntLiteral(@as(i64, increment));

        // 创建加法操作
        const add_node = try self.ast_builder.createBinaryOp(.add, var_node, increment_node);

        // 创建赋值操作
        const assign_node = try ASTNode.init(self.allocator, .assignment);
        assign_node.data = .{ .assignment = .{ .operator = "=" } };
        try assign_node.addChild(var_node);
        try assign_node.addChild(add_node);

        try self.operand_stack.push(assign_node);
    }

    /// 处理 i2l 指令 - int转long
    fn handleI2L(self: *ExpressionBuilder) !void {
        try self.handleTypeConversion(.long);
    }

    /// 处理 i2f 指令 - int转float
    fn handleI2F(self: *ExpressionBuilder) !void {
        try self.handleTypeConversion(.float);
    }

    /// 处理 i2d 指令 - int转double
    fn handleI2D(self: *ExpressionBuilder) !void {
        try self.handleTypeConversion(.double);
    }

    /// 处理 l2i 指令 - long转int
    fn handleL2I(self: *ExpressionBuilder) !void {
        try self.handleTypeConversion(.int);
    }

    /// 处理 l2f 指令 - long转float
    fn handleL2F(self: *ExpressionBuilder) !void {
        try self.handleTypeConversion(.float);
    }

    /// 处理 l2d 指令 - long转double
    fn handleL2D(self: *ExpressionBuilder) !void {
        try self.handleTypeConversion(.double);
    }

    /// 处理 f2i 指令 - float转int
    fn handleF2I(self: *ExpressionBuilder) !void {
        try self.handleTypeConversion(.int);
    }

    /// 处理 f2l 指令 - float转long
    fn handleF2L(self: *ExpressionBuilder) !void {
        try self.handleTypeConversion(.long);
    }

    /// 处理 f2d 指令 - float转double
    fn handleF2D(self: *ExpressionBuilder) !void {
        try self.handleTypeConversion(.double);
    }

    /// 处理 d2i 指令 - double转int
    fn handleD2I(self: *ExpressionBuilder) !void {
        try self.handleTypeConversion(.int);
    }

    /// 处理 d2l 指令 - double转long
    fn handleD2L(self: *ExpressionBuilder) !void {
        try self.handleTypeConversion(.long);
    }

    /// 处理 d2f 指令 - double转float
    fn handleD2F(self: *ExpressionBuilder) !void {
        try self.handleTypeConversion(.float);
    }

    /// 处理 i2b 指令 - int转byte
    fn handleI2B(self: *ExpressionBuilder) !void {
        try self.handleTypeConversion(.byte);
    }

    /// 处理 i2c 指令 - int转char
    fn handleI2C(self: *ExpressionBuilder) !void {
        try self.handleTypeConversion(.char);
    }

    /// 处理 i2s 指令 - int转short
    fn handleI2S(self: *ExpressionBuilder) !void {
        try self.handleTypeConversion(.short);
    }

    /// 通用类型转换处理
    fn handleTypeConversion(self: *ExpressionBuilder, target_type: ast.DataType) !void {
        const operand = self.operand_stack.pop() orelse return;

        // 创建类型转换节点 - 使用cast节点类型
        const cast_node = try ast.ASTNode.init(self.ast_builder.allocator, .cast);
        cast_node.data_type = target_type;
        try cast_node.addChild(operand);

        try self.ast_builder.nodes.append(cast_node);

        try self.operand_stack.push(cast_node);
    }

    /// 处理 lcmp 指令
    fn handleLCmp(self: *ExpressionBuilder) !void {
        try self.handleBinaryOp(.cmp);
    }

    /// 处理 fcmpl 指令
    fn handleFCmpL(self: *ExpressionBuilder) !void {
        try self.handleBinaryOp(.cmp);
    }

    /// 处理 fcmpg 指令
    fn handleFCmpG(self: *ExpressionBuilder) !void {
        try self.handleBinaryOp(.cmp);
    }

    /// 处理 dcmpl 指令
    fn handleDCmpL(self: *ExpressionBuilder) !void {
        try self.handleBinaryOp(.cmp);
    }

    /// 处理 dcmpg 指令
    fn handleDCmpG(self: *ExpressionBuilder) !void {
        try self.handleBinaryOp(.cmp);
    }

    /// 处理 ifeq 指令
    fn handleIfEq(self: *ExpressionBuilder, operands: []const u8) !void {
        const value = self.operand_stack.pop() orelse return;
        const zero = try self.ast_builder.createIntLiteral(0);
        const condition = try self.ast_builder.createBinaryOp(.eq, value, zero);
        const if_node = try self.ast_builder.createIf(condition, try self.ast_builder.createBlock(), null);
        try self.operand_stack.push(if_node);
        _ = operands;
    }

    /// 处理 ifne 指令
    fn handleIfNe(self: *ExpressionBuilder, operands: []const u8) !void {
        const value = self.operand_stack.pop() orelse return;
        const zero = try self.ast_builder.createIntLiteral(0);
        const condition = try self.ast_builder.createBinaryOp(.ne, value, zero);
        const if_node = try self.ast_builder.createIf(condition, try self.ast_builder.createBlock(), null);
        try self.operand_stack.push(if_node);
        _ = operands;
    }

    /// 处理 iflt 指令
    fn handleIfLt(self: *ExpressionBuilder, operands: []const u8) !void {
        const value = self.operand_stack.pop() orelse return;
        const zero = try self.ast_builder.createIntLiteral(0);
        const condition = try self.ast_builder.createBinaryOp(.lt, value, zero);
        const if_node = try self.ast_builder.createIf(condition, try self.ast_builder.createBlock(), null);
        try self.operand_stack.push(if_node);
        _ = operands;
    }

    /// 处理 ifge 指令
    fn handleIfGe(self: *ExpressionBuilder, operands: []const u8) !void {
        const value = self.operand_stack.pop() orelse return;
        const zero = try self.ast_builder.createIntLiteral(0);
        const condition = try self.ast_builder.createBinaryOp(.ge, value, zero);
        const if_node = try self.ast_builder.createIf(condition, try self.ast_builder.createBlock(), null);
        try self.operand_stack.push(if_node);
        _ = operands;
    }

    /// 处理 ifgt 指令
    fn handleIfGt(self: *ExpressionBuilder, operands: []const u8) !void {
        const value = self.operand_stack.pop() orelse return;
        const zero = try self.ast_builder.createIntLiteral(0);
        const condition = try self.ast_builder.createBinaryOp(.gt, value, zero);
        const if_node = try self.ast_builder.createIf(condition, try self.ast_builder.createBlock(), null);
        try self.operand_stack.push(if_node);
        _ = operands;
    }

    /// 处理 ifle 指令
    fn handleIfLe(self: *ExpressionBuilder, operands: []const u8) !void {
        const value = self.operand_stack.pop() orelse return;
        const zero = try self.ast_builder.createIntLiteral(0);
        const condition = try self.ast_builder.createBinaryOp(.le, value, zero);
        const if_node = try self.ast_builder.createIf(condition, try self.ast_builder.createBlock(), null);
        try self.operand_stack.push(if_node);
        _ = operands;
    }

    /// 处理 if_icmpeq 指令
    fn handleIfICmpEq(self: *ExpressionBuilder, operands: []const u8) !void {
        const value2 = self.operand_stack.pop() orelse return;
        const value1 = self.operand_stack.pop() orelse return;
        const condition = try self.ast_builder.createBinaryOp(.eq, value1, value2);
        const if_node = try self.ast_builder.createIf(condition, try self.ast_builder.createBlock(), null);
        try self.operand_stack.push(if_node);
        _ = operands;
    }

    /// 处理 if_icmpne 指令
    fn handleIfICmpNe(self: *ExpressionBuilder, operands: []const u8) !void {
        const value2 = self.operand_stack.pop() orelse return;
        const value1 = self.operand_stack.pop() orelse return;
        const condition = try self.ast_builder.createBinaryOp(.ne, value1, value2);
        const if_node = try self.ast_builder.createIf(condition, try self.ast_builder.createBlock(), null);
        try self.operand_stack.push(if_node);
        _ = operands;
    }

    /// 处理 if_icmplt 指令
    fn handleIfICmpLt(self: *ExpressionBuilder, operands: []const u8) !void {
        const value2 = self.operand_stack.pop() orelse return;
        const value1 = self.operand_stack.pop() orelse return;
        const condition = try self.ast_builder.createBinaryOp(.lt, value1, value2);
        const if_node = try self.ast_builder.createIf(condition, try self.ast_builder.createBlock(), null);
        try self.operand_stack.push(if_node);
        _ = operands;
    }

    /// 处理 if_icmpge 指令
    fn handleIfICmpGe(self: *ExpressionBuilder, operands: []const u8) !void {
        const value2 = self.operand_stack.pop() orelse return;
        const value1 = self.operand_stack.pop() orelse return;
        const condition = try self.ast_builder.createBinaryOp(.ge, value1, value2);
        const if_node = try self.ast_builder.createIf(condition, try self.ast_builder.createBlock(), null);
        try self.operand_stack.push(if_node);
        _ = operands;
    }

    /// 处理 if_icmpgt 指令
    fn handleIfICmpGt(self: *ExpressionBuilder, operands: []const u8) !void {
        const value2 = self.operand_stack.pop() orelse return;
        const value1 = self.operand_stack.pop() orelse return;
        const condition = try self.ast_builder.createBinaryOp(.gt, value1, value2);
        const if_node = try self.ast_builder.createIf(condition, try self.ast_builder.createBlock(), null);
        try self.operand_stack.push(if_node);
        _ = operands;
    }

    /// 处理 if_icmple 指令
    fn handleIfICmpLe(self: *ExpressionBuilder, operands: []const u8) !void {
        const value2 = self.operand_stack.pop() orelse return;
        const value1 = self.operand_stack.pop() orelse return;
        const condition = try self.ast_builder.createBinaryOp(.le, value1, value2);
        const if_node = try self.ast_builder.createIf(condition, try self.ast_builder.createBlock(), null);
        try self.operand_stack.push(if_node);
        _ = operands;
    }

    /// 处理 if_acmpeq 指令
    fn handleIfACmpEq(self: *ExpressionBuilder, operands: []const u8) !void {
        const value2 = self.operand_stack.pop() orelse return;
        const value1 = self.operand_stack.pop() orelse return;
        const condition = try self.ast_builder.createBinaryOp(.eq, value1, value2);
        const if_node = try self.ast_builder.createIf(condition, try self.ast_builder.createBlock(), null);
        try self.operand_stack.push(if_node);
        _ = operands;
    }

    /// 处理 if_acmpne 指令
    fn handleIfACmpNe(self: *ExpressionBuilder, operands: []const u8) !void {
        const value2 = self.operand_stack.pop() orelse return;
        const value1 = self.operand_stack.pop() orelse return;
        const condition = try self.ast_builder.createBinaryOp(.ne, value1, value2);
        const if_node = try self.ast_builder.createIf(condition, try self.ast_builder.createBlock(), null);
        try self.operand_stack.push(if_node);
        _ = operands;
    }

    /// 处理 goto 指令
    fn handleGoto(self: *ExpressionBuilder, operands: []const u8) !void {
        // goto指令通常不产生表达式节点，只是控制流
        _ = self;
        _ = operands;
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

        const node = try self.ast_builder.createMethodCallByName(method_name, null, false);

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
        const node = try self.ast_builder.createMethodCallByName(method_name, null, false);
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
        const node = try self.ast_builder.createMethodCallByName(method_name, null, true);
        try self.operand_stack.push(node);
    }

    /// 处理 invokeinterface 指令
    fn handleInvokeInterface(self: *ExpressionBuilder, operands: []const u8) !void {
        if (operands.len < 2) return;
        const index = (@as(u16, operands[0]) << 8) | operands[1];
        const method_name = try std.fmt.allocPrint(self.allocator, "interface_method_{any}", .{index});
        const node = try self.ast_builder.createMethodCallByName(method_name, null, false);
        // 这里应该根据方法签名弹出相应数量的参数
        // 暂时只弹出对象引用
        if (self.operand_stack.pop()) |object| {
            try node.addChild(object);
        }
        try self.operand_stack.push(node);
    }

    /// 处理 invokedynamic 指令
    fn handleInvokeDynamic(self: *ExpressionBuilder, operands: []const u8) !void {
        if (operands.len < 2) return;
        const index = (@as(u16, operands[0]) << 8) | operands[1];
        const method_name = try std.fmt.allocPrint(self.allocator, "dynamic_method_{any}", .{index});
        const node = try self.ast_builder.createMethodCallByName(method_name, null, false);
        try self.operand_stack.push(node);
    }

    /// 处理 new 指令 (创建新对象)
    fn handleNew(self: *ExpressionBuilder, operands: []const u8) !void {
        if (operands.len < 2) return;
        const index = (@as(u16, operands[0]) << 8) | operands[1];
        const class_name = try std.fmt.allocPrint(self.allocator, "Class_{any}", .{index});
        const node = try self.ast_builder.createComment(try std.fmt.allocPrint(self.ast_builder.allocator, "new {s}", .{class_name}));
        try self.operand_stack.push(node);
    }

    /// 处理 newarray 指令 (创建基本类型数组)
    fn handleNewArray(self: *ExpressionBuilder, operands: []const u8) !void {
        if (operands.len < 1) return;
        const array_type = operands[0];
        const count = self.operand_stack.pop() orelse return;
        const node = try self.ast_builder.createComment(try std.fmt.allocPrint(self.ast_builder.allocator, "new array[{any}] of type {d}", .{ count, array_type }));
        try self.operand_stack.push(node);
    }

    /// 处理 anewarray 指令 (创建引用类型数组)
    fn handleANewArray(self: *ExpressionBuilder, operands: []const u8) !void {
        if (operands.len < 2) return;
        const index = (@as(u16, operands[0]) << 8) | operands[1];
        const count = self.operand_stack.pop() orelse return;
        const node = try self.ast_builder.createComment(try std.fmt.allocPrint(self.ast_builder.allocator, "new array[{any}] of class {d}", .{ count, index }));
        try self.operand_stack.push(node);
    }

    /// 处理 checkcast 指令 (类型检查转换)
    fn handleCheckCast(self: *ExpressionBuilder, operands: []const u8) !void {
        if (operands.len < 2) return;
        const index = (@as(u16, operands[0]) << 8) | operands[1];
        const object = self.operand_stack.pop() orelse return;
        const node = try self.ast_builder.createComment(try std.fmt.allocPrint(self.ast_builder.allocator, "checkcast {any} to class {d}", .{ object, index }));
        try self.operand_stack.push(node);
    }

    /// 处理 instanceof 指令 (类型检查)
    fn handleInstanceOf(self: *ExpressionBuilder, operands: []const u8) !void {
        if (operands.len < 2) return;
        const index = (@as(u16, operands[0]) << 8) | operands[1];
        const object = self.operand_stack.pop() orelse return;
        const node = try self.ast_builder.createComment(try std.fmt.allocPrint(self.ast_builder.allocator, "{any} instanceof class {d}", .{ object, index }));
        try self.operand_stack.push(node);
    }

    /// 处理 arraylength 指令 (获取数组长度)
    fn handleArrayLength(self: *ExpressionBuilder) !void {
        const array = self.operand_stack.pop() orelse return;
        const node = try self.ast_builder.createArrayLength(array);
        try self.operand_stack.push(node);
    }

    /// 处理 athrow 指令 (抛出异常)
    fn handleAThrow(self: *ExpressionBuilder) !void {
        const exception = self.operand_stack.pop() orelse return;
        const node = try self.ast_builder.createThrow(exception);
        try self.operand_stack.push(node);
    }

    /// 处理 monitorenter 指令 (进入监视器)
    fn handleMonitorEnter(self: *ExpressionBuilder) !void {
        const object = self.operand_stack.pop() orelse return;
        const node = try self.ast_builder.createMonitorEnter(object);
        try self.operand_stack.push(node);
    }

    /// 处理 monitorexit 指令 (退出监视器)
    fn handleMonitorExit(self: *ExpressionBuilder) !void {
        const object = self.operand_stack.pop() orelse return;
        const node = try self.ast_builder.createMonitorExit(object);
        try self.operand_stack.push(node);
    }

    /// 处理 wide 指令 (扩展指令)
    fn handleWide(self: *ExpressionBuilder, operands: []const u8) !void {
        if (operands.len < 1) return;
        // wide 指令用于扩展下一个指令的操作数范围
        // 这里简单地创建一个注释节点作为占位符
        const node = try self.ast_builder.createComment(try std.fmt.allocPrint(self.ast_builder.allocator, "wide instruction with opcode {d}", .{operands[0]}));
        try self.operand_stack.push(node);
    }

    /// 处理 multianewarray 指令 (创建多维数组)
    fn handleMultiANewArray(self: *ExpressionBuilder, operands: []const u8) !void {
        if (operands.len < 3) return;
        const index = (@as(u16, operands[0]) << 8) | operands[1];
        const dimensions = operands[2];

        // 弹出维度大小
        var i: u8 = 0;
        while (i < dimensions) : (i += 1) {
            _ = self.operand_stack.pop();
        }

        const node = try self.ast_builder.createComment(try std.fmt.allocPrint(self.ast_builder.allocator, "new multidimensional array of class {d} with {d} dimensions", .{ index, dimensions }));
        try self.operand_stack.push(node);
    }

    /// 处理 ifnull 指令 (如果为 null 则跳转)
    fn handleIfNull(self: *ExpressionBuilder, operands: []const u8) !void {
        if (operands.len < 2) return;
        const offset = (@as(i16, operands[0]) << 8) | operands[1];

        _ = self.operand_stack.pop() orelse return;
        const node = try self.ast_builder.createComment(try std.fmt.allocPrint(self.ast_builder.allocator, "if null jump to offset {d}", .{offset}));
        try self.operand_stack.push(node);
    }

    /// 处理 ifnonnull 指令 (如果不为 null 则跳转)
    fn handleIfNonNull(self: *ExpressionBuilder, operands: []const u8) !void {
        if (operands.len < 2) return;
        const offset = (@as(i16, operands[0]) << 8) | operands[1];

        _ = self.operand_stack.pop() orelse return;
        const node = try self.ast_builder.createComment(try std.fmt.allocPrint(self.ast_builder.allocator, "if not null jump to offset {d}", .{offset}));
        try self.operand_stack.push(node);
    }

    /// 处理 goto_w 指令 (宽跳转)
    fn handleGotoW(self: *ExpressionBuilder, operands: []const u8) !void {
        if (operands.len < 4) return;
        const offset = (@as(i32, operands[0]) << 24) | (@as(i32, operands[1]) << 16) | (@as(i32, operands[2]) << 8) | operands[3];

        const node = try self.ast_builder.createComment(try std.fmt.allocPrint(self.ast_builder.allocator, "goto wide offset {d}", .{offset}));
        try self.operand_stack.push(node);
    }

    /// 处理 ireturn 指令
    fn handleIReturn(self: *ExpressionBuilder) !void {
        if (self.operand_stack.pop()) |value| {
            const node = try self.ast_builder.createReturn(value);
            try self.operand_stack.push(node);
        }
    }

    /// 处理 lreturn 指令 (return long)
    fn handleLReturn(self: *ExpressionBuilder) !void {
        if (self.operand_stack.pop()) |value| {
            const node = try self.ast_builder.createReturn(value);
            try self.operand_stack.push(node);
        }
    }

    /// 处理 freturn 指令 (return float)
    fn handleFReturn(self: *ExpressionBuilder) !void {
        if (self.operand_stack.pop()) |value| {
            const node = try self.ast_builder.createReturn(value);
            try self.operand_stack.push(node);
        }
    }

    /// 处理 dreturn 指令 (return double)
    fn handleDReturn(self: *ExpressionBuilder) !void {
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

    /// 处理 ret 指令 (return from subroutine)
    fn handleRet(self: *ExpressionBuilder, operands: []const u8) !void {
        const index = operands[0];
        // RET instruction returns from a subroutine using the address stored in local variable at index
        const local_var = try self.ast_builder.createLocalVariable(index);
        const comment = try self.ast_builder.createComment(try std.fmt.allocPrint(self.ast_builder.allocator, "RET from local variable {d}", .{index}));
        try self.operand_stack.push(comment);
        _ = local_var;
    }

    /// 处理 tableswitch 指令
    fn handleTableSwitch(self: *ExpressionBuilder, operands: []const u8) !void {
        const value = self.operand_stack.pop() orelse return;
        // TableSwitch is a complex switch statement with consecutive case values
        const comment = try self.ast_builder.createComment("TableSwitch instruction");
        try self.operand_stack.push(comment);
        _ = operands;
        _ = value;
    }

    /// 处理 lookupswitch 指令
    fn handleLookupSwitch(self: *ExpressionBuilder, operands: []const u8) !void {
        const value = self.operand_stack.pop() orelse return;
        // LookupSwitch is a switch statement with sparse case values
        const comment = try self.ast_builder.createComment("LookupSwitch instruction");
        try self.operand_stack.push(comment);
        _ = operands;
        _ = value;
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

    fn handleJsr(self: *ExpressionBuilder, operands: []const u8) !void {
        const offset = (@as(i16, @bitCast(@as(u16, operands[0]) << 8 | @as(u16, operands[1]))));
        // JSR pushes the return address onto the stack and jumps to subroutine
        const return_addr_node = try self.ast_builder.createLiteral(LiteralValue{ .int_val = 0 }, DataType.int); // Placeholder for return address
        try self.operand_stack.push(return_addr_node);

        // Create a comment node for JSR instruction since createGoto doesn't exist
        const comment = try self.ast_builder.createComment(try std.fmt.allocPrint(self.ast_builder.allocator, "JSR offset: {d}", .{offset}));
        try self.operand_stack.push(comment);
    }

    fn handleJsrW(self: *ExpressionBuilder, operands: []const u8) !void {
        const offset = (@as(i32, @bitCast(@as(u32, operands[0]) << 24 | @as(u32, operands[1]) << 16 | @as(u32, operands[2]) << 8 | @as(u32, operands[3]))));
        // JSR_W pushes the return address onto the stack and jumps to subroutine
        const return_addr_node = try self.ast_builder.createLiteral(LiteralValue{ .int_val = 0 }, DataType.int); // Placeholder for return address
        try self.operand_stack.push(return_addr_node);

        // Create a comment node for JSR_W instruction since createGoto doesn't exist
        const comment = try self.ast_builder.createComment(try std.fmt.allocPrint(self.ast_builder.allocator, "JSR_W offset: {d}", .{offset}));
        try self.operand_stack.push(comment);
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
