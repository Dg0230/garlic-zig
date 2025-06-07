//! AST 构建器模块
//! 负责将字节码指令转换为抽象语法树节点

const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const HashMap = std.HashMap;

/// AST 节点类型枚举
pub const NodeType = enum {
    // 表达式节点
    literal, // 字面量
    identifier, // 标识符
    binary_op, // 二元操作
    unary_op, // 一元操作
    method_call, // 方法调用
    field_access, // 字段访问
    array_access, // 数组访问
    assignment, // 赋值
    cast, // 类型转换

    // 语句节点
    expression_stmt, // 表达式语句
    return_stmt, // 返回语句
    if_stmt, // if 语句
    while_stmt, // while 循环
    for_stmt, // for 循环
    block_stmt, // 代码块
    variable_decl, // 变量声明

    // 声明节点
    method_decl, // 方法声明
    class_decl, // 类声明
    field_decl, // 字段声明
};

/// 数据类型枚举
pub const DataType = enum {
    void,
    boolean,
    byte,
    char,
    short,
    int,
    long,
    float,
    double,
    object,
    array,

    /// 获取类型的字符串表示
    pub fn toString(self: DataType) []const u8 {
        return switch (self) {
            .void => "void",
            .boolean => "boolean",
            .byte => "byte",
            .char => "char",
            .short => "short",
            .int => "int",
            .long => "long",
            .float => "float",
            .double => "double",
            .object => "Object",
            .array => "Array",
        };
    }
};

/// 二元操作符类型
pub const BinaryOp = enum {
    add, // +
    sub, // -
    mul, // *
    div, // /
    mod, // %
    logical_and, // &&
    logical_or, // ||
    eq, // ==
    ne, // !=
    lt, // <
    le, // <=
    gt, // >
    ge, // >=
    bit_and, // &
    bit_or, // |
    bit_xor, // ^
    shl, // <<
    shr, // >>
    ushr, // >>>
    assign, // =
    cmp, // 比较操作

    /// 获取操作符的字符串表示
    pub fn toString(self: BinaryOp) []const u8 {
        return switch (self) {
            .add => "+",
            .sub => "-",
            .mul => "*",
            .div => "/",
            .mod => "%",
            .logical_and => "&&",
            .logical_or => "||",
            .eq => "==",
            .ne => "!=",
            .lt => "<",
            .le => "<=",
            .gt => ">",
            .ge => ">=",
            .bit_and => "&",
            .bit_or => "|",
            .assign => "=",
            .cmp => "cmp",
            .bit_xor => "^",
            .shl => "<<",
            .shr => ">>",
            .ushr => ">>>",
        };
    }
};

/// 一元操作符类型
pub const UnaryOp = enum {
    neg, // -
    not, // !
    bit_not, // ~
    cast, // 类型转换

    /// 获取操作符的字符串表示
    pub fn toString(self: UnaryOp) []const u8 {
        return switch (self) {
            .neg => "-",
            .not => "!",
            .bit_not => "~",
            .cast => "(cast)",
        };
    }
};

/// AST 节点结构
pub const ASTNode = struct {
    node_type: NodeType,
    data_type: ?DataType,
    children: ArrayList(*ASTNode),

    // 节点特定数据
    data: union(enum) {
        literal: LiteralData,
        identifier: []const u8,
        binary_op: BinaryOp,
        unary_op: UnaryOp,
        method_call: MethodCallData,
        field_access: FieldAccessData,
        assignment: AssignmentData,
        variable_decl: VariableDeclData,
        method_decl: MethodDeclData,
        none: void,
    },

    parent: ?*ASTNode,
    allocator: Allocator,

    /// 创建新的AST节点
    pub fn init(allocator: Allocator, node_type: NodeType) !*ASTNode {
        const node = try allocator.create(ASTNode);
        node.* = ASTNode{
            .node_type = node_type,
            .data_type = null,
            .children = ArrayList(*ASTNode).init(allocator),
            .data = .{ .none = {} },
            .parent = null,
            .allocator = allocator,
        };
        return node;
    }

    /// 释放节点内存
    pub fn deinit(self: *ASTNode) void {
        for (self.children.items) |child| {
            child.deinit();
        }
        self.children.deinit();
        self.allocator.destroy(self);
    }

    /// 添加子节点
    pub fn addChild(self: *ASTNode, child: *ASTNode) !void {
        child.parent = self;
        try self.children.append(child);
    }

    /// 设置字面量数据
    pub fn setLiteral(self: *ASTNode, value: LiteralValue, data_type: DataType) void {
        self.data = .{ .literal = LiteralData{ .value = value, .type = data_type } };
        self.data_type = data_type;
    }

    /// 设置标识符
    pub fn setIdentifier(self: *ASTNode, name: []const u8) void {
        self.data = .{ .identifier = name };
    }

    /// 设置二元操作符
    pub fn setBinaryOp(self: *ASTNode, op: BinaryOp) void {
        self.data = .{ .binary_op = op };
    }

    /// 设置一元操作符
    pub fn setUnaryOp(self: *ASTNode, op: UnaryOp) void {
        self.data = .{ .unary_op = op };
    }
};

/// 字面量值联合体
pub const LiteralValue = union(enum) {
    int_val: i64,
    float_val: f64,
    string_val: []const u8,
    bool_val: bool,
    null_val: void,
};

/// 字面量数据
pub const LiteralData = struct {
    value: LiteralValue,
    type: DataType,
};

/// 方法调用数据
pub const MethodCallData = struct {
    method_name: []const u8,
    class_name: ?[]const u8,
    is_static: bool,
};

/// 字段访问数据
pub const FieldAccessData = struct {
    field_name: []const u8,
    class_name: ?[]const u8,
    is_static: bool,
};

/// 赋值数据
pub const AssignmentData = struct {
    operator: []const u8, // "=", "+=", "-=", etc.
};

/// 变量声明数据
pub const VariableDeclData = struct {
    name: []const u8,
    var_type: DataType,
    is_final: bool,
};

/// 方法声明数据
pub const MethodDeclData = struct {
    name: []const u8,
    return_type: DataType,
    parameters: ArrayList(VariableDeclData),
    is_static: bool,
    is_public: bool,
    is_private: bool,
    is_protected: bool,
};

/// AST 构建器
pub const ASTBuilder = struct {
    allocator: Allocator,
    root: ?*ASTNode,
    nodes: ArrayList(*ASTNode),

    /// 初始化AST构建器
    pub fn init(allocator: Allocator) ASTBuilder {
        return ASTBuilder{
            .allocator = allocator,
            .root = null,
            .nodes = ArrayList(*ASTNode).init(allocator),
        };
    }

    /// 释放AST构建器
    pub fn deinit(self: *ASTBuilder) void {
        // 如果有根节点，释放根节点（会递归释放所有子节点）
        if (self.root) |root| {
            root.deinit();
        } else {
            // 如果没有设置根节点，释放所有没有父节点的节点
            for (self.nodes.items) |node| {
                if (node.parent == null) {
                    node.deinit();
                }
            }
        }
        self.nodes.deinit();
    }

    /// 创建字面量节点
    pub fn createLiteral(self: *ASTBuilder, value: LiteralValue, data_type: DataType) !*ASTNode {
        const node = try ASTNode.init(self.allocator, .literal);
        node.setLiteral(value, data_type);
        try self.nodes.append(node);
        return node;
    }

    /// 创建整数字面量节点
    pub fn createIntLiteral(self: *ASTBuilder, value: i64) !*ASTNode {
        return self.createLiteral(.{ .int_val = value }, .int);
    }

    /// 创建字符串字面量节点
    pub fn createStringLiteral(self: *ASTBuilder, value: []const u8) !*ASTNode {
        return self.createLiteral(.{ .string_val = value }, .object);
    }

    /// 创建标识符节点
    pub fn createIdentifier(self: *ASTBuilder, name: []const u8) !*ASTNode {
        const node = try ASTNode.init(self.allocator, .identifier);
        node.setIdentifier(name);
        try self.nodes.append(node);
        return node;
    }

    /// 创建二元操作节点
    pub fn createBinaryOp(self: *ASTBuilder, op: BinaryOp, left: *ASTNode, right: *ASTNode) !*ASTNode {
        const node = try ASTNode.init(self.allocator, .binary_op);
        node.setBinaryOp(op);
        try node.addChild(left);
        try node.addChild(right);
        try self.nodes.append(node);
        return node;
    }

    /// 创建一元操作节点
    pub fn createUnaryOp(self: *ASTBuilder, op: UnaryOp, operand: *ASTNode) !*ASTNode {
        const node = try ASTNode.init(self.allocator, .unary_op);
        node.setUnaryOp(op);
        try node.addChild(operand);
        try self.nodes.append(node);
        return node;
    }

    /// 创建方法调用节点（带名称）
    pub fn createMethodCallByName(self: *ASTBuilder, method_name: []const u8, class_name: ?[]const u8, is_static: bool) !*ASTNode {
        const node = try ASTNode.init(self.allocator, .method_call);
        node.data = .{ .method_call = MethodCallData{
            .method_name = method_name,
            .class_name = class_name,
            .is_static = is_static,
        } };
        try self.nodes.append(node);
        return node;
    }

    /// 创建方法节点
    pub fn createMethod(self: *ASTBuilder, method_name: []const u8, return_type: []const u8, parameter_types: []const []const u8, body: ?*ASTNode) !*ASTNode {
        const node = try ASTNode.init(self.allocator, .method_decl);
        // 简化实现，实际需要更复杂的方法数据结构
        _ = method_name;
        _ = return_type;
        _ = parameter_types;

        if (body) |method_body| {
            try node.addChild(method_body);
        }

        try self.nodes.append(node);
        return node;
    }

    /// 创建字段节点
    pub fn createField(self: *ASTBuilder, field_name: []const u8, field_type: []const u8, access_flags: u16, initial_value: ?*ASTNode) !*ASTNode {
        const node = try ASTNode.init(self.allocator, .field_decl);
        // 简化实现，实际需要更复杂的字段数据结构
        _ = field_name;
        _ = field_type;
        _ = access_flags;

        if (initial_value) |value| {
            try node.addChild(value);
        }

        try self.nodes.append(node);
        return node;
    }

    /// 创建方法声明节点
    pub fn createMethodDeclaration(self: *ASTBuilder, name: []const u8, return_type: []const u8, parameters: []const u8, access_flags: u16) !*ASTNode {
        const node = try ASTNode.init(self.allocator, .method_decl);
        // 简化实现，实际需要更复杂的方法数据结构
        _ = name;
        _ = return_type;
        _ = parameters;
        _ = access_flags;
        try self.nodes.append(node);
        return node;
    }

    /// 创建块语句节点
    pub fn createBlockStatement(self: *ASTBuilder) !*ASTNode {
        const node = try ASTNode.init(self.allocator, .block_stmt);
        try self.nodes.append(node);
        return node;
    }

    /// 创建代码块节点（别名）
    pub fn createBlock(self: *ASTBuilder) !*ASTNode {
        return self.createBlockStatement();
    }

    /// 创建返回语句节点
    pub fn createReturnStatement(self: *ASTBuilder, expr: ?*ASTNode) !*ASTNode {
        const node = try ASTNode.init(self.allocator, .return_stmt);
        if (expr) |e| {
            try node.addChild(e);
        }
        try self.nodes.append(node);
        return node;
    }

    /// 创建返回语句节点（别名）
    pub fn createReturn(self: *ASTBuilder, expr: ?*ASTNode) !*ASTNode {
        return self.createReturnStatement(expr);
    }

    /// 创建表达式语句节点
    pub fn createExpressionStatement(self: *ASTBuilder, expr: *ASTNode) !*ASTNode {
        const node = try ASTNode.init(self.allocator, .expression_stmt);
        try node.addChild(expr);
        try self.nodes.append(node);
        return node;
    }

    /// 创建方法调用节点
    pub fn createMethodCall(self: *ASTBuilder, target: *ASTNode, args: []*ASTNode) !*ASTNode {
        const node = try ASTNode.init(self.allocator, .method_call);
        try node.addChild(target);
        for (args) |arg| {
            try node.addChild(arg);
        }
        try self.nodes.append(node);
        return node;
    }

    /// 创建字段访问节点
    pub fn createFieldAccess(self: *ASTBuilder, object: *ASTNode, field_name: []const u8) !*ASTNode {
        const node = try ASTNode.init(self.allocator, .field_access);
        try node.addChild(object);
        // 简化实现，实际需要存储字段名
        _ = field_name;
        try self.nodes.append(node);
        return node;
    }

    /// 创建赋值节点
    pub fn createAssignment(self: *ASTBuilder, left: *ASTNode, right: *ASTNode) !*ASTNode {
        const node = try ASTNode.init(self.allocator, .assignment);
        try node.addChild(left);
        try node.addChild(right);
        try self.nodes.append(node);
        return node;
    }

    /// 创建注释节点（简化实现）
    pub fn createComment(self: *ASTBuilder, text: []const u8) !*ASTNode {
        // 暂时用字符串字面量表示注释
        return self.createStringLiteral(text);
    }

    /// 创建if语句节点
    pub fn createIf(self: *ASTBuilder, condition: *ASTNode, then_stmt: *ASTNode, else_stmt: ?*ASTNode) !*ASTNode {
        const node = try ASTNode.init(self.allocator, .if_stmt);
        try node.addChild(condition);
        try node.addChild(then_stmt);
        if (else_stmt) |e| {
            try node.addChild(e);
        }
        try self.nodes.append(node);
        return node;
    }

    /// 创建局部变量节点
    pub fn createLocalVariable(self: *ASTBuilder, index: u8) !*ASTNode {
        const node = try ASTNode.init(self.allocator, .identifier);
        // 使用变量索引创建变量名
        const var_name = try std.fmt.allocPrint(self.allocator, "var{d}", .{index});
        node.setIdentifier(var_name);
        try self.nodes.append(node);
        return node;
    }

    /// 创建数组长度节点
    pub fn createArrayLength(self: *ASTBuilder, array: *ASTNode) !*ASTNode {
        const node = try ASTNode.init(self.allocator, .field_access);
        try node.addChild(array);
        try self.nodes.append(node);
        return node;
    }

    /// 创建异常抛出节点
    pub fn createThrow(self: *ASTBuilder, exception: *ASTNode) !*ASTNode {
        const node = try ASTNode.init(self.allocator, .expression_stmt);
        try node.addChild(exception);
        try self.nodes.append(node);
        return node;
    }

    /// 创建监视器进入节点
    pub fn createMonitorEnter(self: *ASTBuilder, object: *ASTNode) !*ASTNode {
        const node = try ASTNode.init(self.allocator, .expression_stmt);
        try node.addChild(object);
        try self.nodes.append(node);
        return node;
    }

    /// 创建监视器退出节点
    pub fn createMonitorExit(self: *ASTBuilder, object: *ASTNode) !*ASTNode {
        const node = try ASTNode.init(self.allocator, .expression_stmt);
        try node.addChild(object);
        try self.nodes.append(node);
        return node;
    }

    /// 设置根节点
    pub fn setRoot(self: *ASTBuilder, root: *ASTNode) void {
        self.root = root;
    }
};

/// AST 遍历器
pub const ASTVisitor = struct {
    /// 访问节点的函数指针类型
    pub const VisitFn = *const fn (*ASTNode, *anyopaque) anyerror!void;

    /// 深度优先遍历AST
    pub fn visitDepthFirst(node: *ASTNode, context: *anyopaque, visit_fn: VisitFn) !void {
        try visit_fn(node, context);

        for (node.children.items) |child| {
            try visitDepthFirst(child, context, visit_fn);
        }
    }

    /// 广度优先遍历AST
    pub fn visitBreadthFirst(allocator: Allocator, root: *ASTNode, context: *anyopaque, visit_fn: VisitFn) !void {
        var queue = ArrayList(*ASTNode).init(allocator);
        defer queue.deinit();

        try queue.append(root);

        while (queue.items.len > 0) {
            const node = queue.orderedRemove(0);
            try visit_fn(node, context);

            for (node.children.items) |child| {
                try queue.append(child);
            }
        }
    }
};

// 测试
test "AST基础功能测试" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var builder = ASTBuilder.init(allocator);
    defer builder.deinit();

    // 创建字面量节点
    const literal = try builder.createLiteral(.{ .int_val = 42 }, .int);
    try testing.expect(literal.node_type == .literal);
    try testing.expect(literal.data_type.? == .int);

    // 创建标识符节点
    const identifier = try builder.createIdentifier("variable");
    try testing.expect(identifier.node_type == .identifier);

    // 创建二元操作节点
    const binary_op = try builder.createBinaryOp(.add, literal, identifier);
    try testing.expect(binary_op.node_type == .binary_op);
    try testing.expect(binary_op.children.items.len == 2);

    // 设置根节点以确保所有节点都能被正确释放
    builder.setRoot(binary_op);
}
