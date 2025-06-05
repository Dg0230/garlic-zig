//! 代码生成器模块
//! 负责将AST转换为Java源代码

const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const HashMap = std.HashMap;
const ast = @import("ast.zig");
const ASTNode = ast.ASTNode;
const NodeType = ast.NodeType;
const DataType = ast.DataType;
const BinaryOp = ast.BinaryOp;
const UnaryOp = ast.UnaryOp;
const LiteralValue = ast.LiteralValue;

/// 代码生成选项
pub const CodeGenOptions = struct {
    indent_size: u32 = 4,
    use_tabs: bool = false,
    max_line_length: u32 = 120,
    add_comments: bool = true,
    format_braces: BraceStyle = .same_line,

    pub const BraceStyle = enum {
        same_line, // if (condition) {
        next_line, // if (condition)
        // {
    };
};

/// 代码生成上下文
pub const CodeGenContext = struct {
    indent_level: u32 = 0,
    in_expression: bool = false,
    current_method: ?[]const u8 = null,
    current_class: ?[]const u8 = null,
    local_variables: HashMap([]const u8, DataType, std.hash_map.StringContext, std.hash_map.default_max_load_percentage),
    allocator: Allocator,

    /// 初始化代码生成上下文
    pub fn init(allocator: Allocator) CodeGenContext {
        return CodeGenContext{
            .local_variables = HashMap([]const u8, DataType, std.hash_map.StringContext, std.hash_map.default_max_load_percentage).init(allocator),
            .allocator = allocator,
        };
    }

    /// 释放代码生成上下文
    pub fn deinit(self: *CodeGenContext) void {
        self.local_variables.deinit();
    }

    /// 增加缩进级别
    pub fn increaseIndent(self: *CodeGenContext) void {
        self.indent_level += 1;
    }

    /// 减少缩进级别
    pub fn decreaseIndent(self: *CodeGenContext) void {
        if (self.indent_level > 0) {
            self.indent_level -= 1;
        }
    }

    /// 添加局部变量
    pub fn addLocalVariable(self: *CodeGenContext, name: []const u8, var_type: DataType) !void {
        try self.local_variables.put(name, var_type);
    }

    /// 获取局部变量类型
    pub fn getLocalVariableType(self: *CodeGenContext, name: []const u8) ?DataType {
        return self.local_variables.get(name);
    }
};

/// 代码生成器
pub const CodeGenerator = struct {
    allocator: Allocator,
    options: CodeGenOptions,
    output: ArrayList(u8),
    context: CodeGenContext,

    /// 初始化代码生成器
    pub fn init(allocator: Allocator, options: CodeGenOptions) CodeGenerator {
        return CodeGenerator{
            .allocator = allocator,
            .options = options,
            .output = ArrayList(u8).init(allocator),
            .context = CodeGenContext.init(allocator),
        };
    }

    /// 释放代码生成器
    pub fn deinit(self: *CodeGenerator) void {
        self.output.deinit();
        self.context.deinit();
    }

    /// 生成代码
    pub fn generate(self: *CodeGenerator, root: *ASTNode) ![]const u8 {
        self.output.clearRetainingCapacity();
        try self.generateNode(root);
        return try self.output.toOwnedSlice();
    }

    /// 生成单个节点的代码
    fn generateNode(self: *CodeGenerator, node: *ASTNode) anyerror!void {
        switch (node.node_type) {
            .literal => try self.generateLiteral(node),
            .identifier => try self.generateIdentifier(node),
            .binary_op => try self.generateBinaryOp(node),
            .unary_op => try self.generateUnaryOp(node),
            .method_call => try self.generateMethodCall(node),
            .field_access => try self.generateFieldAccess(node),
            .array_access => try self.generateArrayAccess(node),
            .assignment => try self.generateAssignment(node),
            .cast => try self.generateCast(node),
            .expression_stmt => try self.generateExpressionStatement(node),
            .return_stmt => try self.generateReturnStatement(node),
            .if_stmt => try self.generateIfStatement(node),
            .while_stmt => try self.generateWhileStatement(node),
            .for_stmt => try self.generateForStatement(node),
            .block_stmt => try self.generateBlockStatement(node),
            .variable_decl => try self.generateVariableDeclaration(node),
            .method_decl => try self.generateMethodDeclaration(node),
            .class_decl => try self.generateClassDeclaration(node),
            .field_decl => try self.generateFieldDeclaration(node),
        }
    }

    /// 生成字面量
    fn generateLiteral(self: *CodeGenerator, node: *ASTNode) !void {
        if (node.data != .literal) return;

        const literal_data = node.data.literal;
        switch (literal_data.value) {
            .int_val => |val| {
                try self.output.writer().print("{any}", .{val});
            },
            .float_val => |val| {
                try self.output.writer().print("{d}", .{val});
            },
            .string_val => |val| {
                try self.output.writer().print("\"{s}\"", .{val});
            },
            .bool_val => |val| {
                try self.output.writer().print("{any}", .{val});
            },
            .null_val => {
                try self.output.writer().print("null", .{});
            },
        }
    }

    /// 生成标识符
    fn generateIdentifier(self: *CodeGenerator, node: *ASTNode) !void {
        if (node.data != .identifier) return;
        try self.output.writer().print("{s}", .{node.data.identifier});
    }

    /// 生成二元操作
    fn generateBinaryOp(self: *CodeGenerator, node: *ASTNode) !void {
        if (node.data != .binary_op or node.children.items.len != 2) return;

        const op = node.data.binary_op;
        const left = node.children.items[0];
        const right = node.children.items[1];

        // 根据操作符优先级决定是否需要括号
        const needs_parens = self.needsParentheses(node);

        if (needs_parens) {
            try self.output.writer().print("(", .{});
        }

        try self.generateNode(left);
        try self.output.writer().print(" {s} ", .{op.toString()});
        try self.generateNode(right);

        if (needs_parens) {
            try self.output.writer().print(")", .{});
        }
    }

    /// 生成一元操作
    fn generateUnaryOp(self: *CodeGenerator, node: *ASTNode) !void {
        if (node.data != .unary_op or node.children.items.len != 1) return;

        const op = node.data.unary_op;
        const operand = node.children.items[0];

        try self.output.writer().print("{s}", .{op.toString()});
        try self.generateNode(operand);
    }

    /// 生成方法调用
    fn generateMethodCall(self: *CodeGenerator, node: *ASTNode) !void {
        if (node.data != .method_call) return;

        const method_data = node.data.method_call;

        // 如果有对象引用，先生成对象
        if (node.children.items.len > 0 and !method_data.is_static) {
            try self.generateNode(node.children.items[0]);
            try self.output.writer().print(".", .{});
        } else if (method_data.class_name) |class_name| {
            try self.output.writer().print("{s}.", .{class_name});
        }

        try self.output.writer().print("{s}(", .{method_data.method_name});

        // 生成参数列表
        const start_index: usize = if (method_data.is_static or node.children.items.len == 0) 0 else 1;
        for (node.children.items[start_index..], 0..) |arg, i| {
            if (i > 0) {
                try self.output.writer().print(", ", .{});
            }
            try self.generateNode(arg);
        }

        try self.output.writer().print(")", .{});
    }

    /// 生成字段访问
    fn generateFieldAccess(self: *CodeGenerator, node: *ASTNode) !void {
        if (node.data != .field_access) return;

        const field_data = node.data.field_access;

        if (field_data.is_static and field_data.class_name != null) {
            try self.output.writer().print("{s}.", .{field_data.class_name.?});
        } else if (node.children.items.len > 0) {
            try self.generateNode(node.children.items[0]);
            try self.output.writer().print(".", .{});
        }

        try self.output.writer().print("{s}", .{field_data.field_name});
    }

    /// 生成数组访问
    fn generateArrayAccess(self: *CodeGenerator, node: *ASTNode) !void {
        if (node.children.items.len != 2) return;

        const array = node.children.items[0];
        const index = node.children.items[1];

        try self.generateNode(array);
        try self.output.writer().print("[", .{});
        try self.generateNode(index);
        try self.output.writer().print("]", .{});
    }

    /// 生成赋值
    fn generateAssignment(self: *CodeGenerator, node: *ASTNode) !void {
        if (node.data != .assignment or node.children.items.len != 2) return;

        const assignment_data = node.data.assignment;
        const left = node.children.items[0];
        const right = node.children.items[1];

        try self.generateNode(left);
        try self.output.writer().print(" {s} ", .{assignment_data.operator});
        try self.generateNode(right);
    }

    /// 生成类型转换
    fn generateCast(self: *CodeGenerator, node: *ASTNode) !void {
        if (node.children.items.len != 1 or node.data_type == null) return;

        const expr = node.children.items[0];
        const target_type = node.data_type.?;

        try self.output.writer().print("({s}) ", .{target_type.toString()});
        try self.generateNode(expr);
    }

    /// 生成表达式语句
    fn generateExpressionStatement(self: *CodeGenerator, node: *ASTNode) !void {
        if (node.children.items.len != 1) return;

        try self.writeIndent();
        try self.generateNode(node.children.items[0]);
        try self.output.writer().print(";\n", .{});
    }

    /// 生成返回语句
    fn generateReturnStatement(self: *CodeGenerator, node: *ASTNode) !void {
        try self.writeIndent();
        try self.output.writer().print("return", .{});

        if (node.children.items.len > 0) {
            try self.output.writer().print(" ", .{});
            try self.generateNode(node.children.items[0]);
        }

        try self.output.writer().print(";\n", .{});
    }

    /// 生成if语句
    fn generateIfStatement(self: *CodeGenerator, node: *ASTNode) !void {
        if (node.children.items.len < 2) return;

        const condition = node.children.items[0];
        const then_stmt = node.children.items[1];
        const else_stmt = if (node.children.items.len > 2) node.children.items[2] else null;

        try self.writeIndent();
        try self.output.writer().print("if (", .{});
        try self.generateNode(condition);
        try self.output.writer().print(")", .{});

        if (self.options.format_braces == .same_line) {
            try self.output.writer().print(" {{\n", .{});
        } else {
            try self.output.writer().print("\n", .{});
            try self.writeIndent();
            try self.output.writer().print("{{\n", .{});
        }

        self.context.increaseIndent();
        try self.generateNode(then_stmt);
        self.context.decreaseIndent();

        try self.writeIndent();
        try self.output.writer().print("}}", .{});

        if (else_stmt) |else_node| {
            if (self.options.format_braces == .same_line) {
                try self.output.writer().print(" else {{\n", .{});
            } else {
                try self.output.writer().print("\nelse\n", .{});
                try self.writeIndent();
                try self.output.writer().print("{{\n", .{});
            }

            self.context.increaseIndent();
            try self.generateNode(else_node);
            self.context.decreaseIndent();

            try self.writeIndent();
            try self.output.writer().print("}}", .{});
        }

        try self.output.writer().print("\n", .{});
    }

    /// 生成while语句
    fn generateWhileStatement(self: *CodeGenerator, node: *ASTNode) !void {
        if (node.children.items.len != 2) return;

        const condition = node.children.items[0];
        const body = node.children.items[1];

        try self.writeIndent();
        try self.output.writer().print("while (", .{});
        try self.generateNode(condition);
        try self.output.writer().print(")", .{});

        if (self.options.format_braces == .same_line) {
            try self.output.writer().print(" {{\n", .{});
        } else {
            try self.output.writer().print("\n", .{});
            try self.writeIndent();
            try self.output.writer().print("{{\n", .{});
        }

        self.context.increaseIndent();
        try self.generateNode(body);
        self.context.decreaseIndent();

        try self.writeIndent();
        try self.output.writer().print("}}\n", .{});
    }

    /// 生成for语句
    fn generateForStatement(self: *CodeGenerator, node: *ASTNode) !void {
        if (node.children.items.len != 4) return;

        const init_stmt = node.children.items[0];
        const condition = node.children.items[1];
        const update = node.children.items[2];
        const body = node.children.items[3];

        try self.writeIndent();
        try self.output.writer().print("for (", .{});
        try self.generateNode(init_stmt);
        try self.output.writer().print("; ", .{});
        try self.generateNode(condition);
        try self.output.writer().print("; ", .{});
        try self.generateNode(update);
        try self.output.writer().print(")", .{});

        if (self.options.format_braces == .same_line) {
            try self.output.writer().print(" {{\n", .{});
        } else {
            try self.output.writer().print("\n", .{});
            try self.writeIndent();
            try self.output.writer().print("{{\n", .{});
        }

        self.context.increaseIndent();
        try self.generateNode(body);
        self.context.decreaseIndent();

        try self.writeIndent();
        try self.output.writer().print("}}\n", .{});
    }

    /// 生成代码块语句
    fn generateBlockStatement(self: *CodeGenerator, node: *ASTNode) !void {
        for (node.children.items) |child| {
            try self.generateNode(child);
        }
    }

    /// 生成变量声明
    fn generateVariableDeclaration(self: *CodeGenerator, node: *ASTNode) !void {
        if (node.data != .variable_decl) return;

        const var_data = node.data.variable_decl;

        try self.writeIndent();

        if (var_data.is_final) {
            try self.output.writer().print("final ", .{});
        }

        try self.output.writer().print("{s} {s}", .{ var_data.var_type.toString(), var_data.name });

        if (node.children.items.len > 0) {
            try self.output.writer().print(" = ", .{});
            try self.generateNode(node.children.items[0]);
        }

        try self.output.writer().print(";\n", .{});

        // 添加到局部变量表
        try self.context.addLocalVariable(var_data.name, var_data.var_type);
    }

    /// 生成方法声明
    fn generateMethodDeclaration(self: *CodeGenerator, node: *ASTNode) !void {
        if (node.data != .method_decl) return;

        const method_data = node.data.method_decl;

        try self.writeIndent();

        // 访问修饰符
        if (method_data.is_public) {
            try self.output.writer().print("public ", .{});
        } else if (method_data.is_private) {
            try self.output.writer().print("private ", .{});
        } else if (method_data.is_protected) {
            try self.output.writer().print("protected ", .{});
        }

        if (method_data.is_static) {
            try self.output.writer().print("static ", .{});
        }

        // 返回类型和方法名
        try self.output.writer().print("{s} {s}(", .{ method_data.return_type.toString(), method_data.name });

        // 参数列表
        for (method_data.parameters.items, 0..) |param, i| {
            if (i > 0) {
                try self.output.writer().print(", ", .{});
            }
            try self.output.writer().print("{s} {s}", .{ param.var_type.toString(), param.name });
        }

        try self.output.writer().print(")", .{});

        if (self.options.format_braces == .same_line) {
            try self.output.writer().print(" {{\n", .{});
        } else {
            try self.output.writer().print("\n", .{});
            try self.writeIndent();
            try self.output.writer().print("{{\n", .{});
        }

        // 方法体
        if (node.children.items.len > 0) {
            self.context.increaseIndent();
            self.context.current_method = method_data.name;
            try self.generateNode(node.children.items[0]);
            self.context.current_method = null;
            self.context.decreaseIndent();
        }

        try self.writeIndent();
        try self.output.writer().print("}}\n\n", .{});
    }

    /// 生成类声明
    fn generateClassDeclaration(self: *CodeGenerator, node: *ASTNode) !void {
        // 简化实现，实际应该从节点数据中获取类信息
        try self.output.writer().print("public class GeneratedClass {{\n", .{});

        self.context.increaseIndent();
        for (node.children.items) |child| {
            try self.generateNode(child);
        }
        self.context.decreaseIndent();

        try self.output.writer().print("}}\n", .{});
    }

    /// 生成字段声明
    fn generateFieldDeclaration(self: *CodeGenerator, node: *ASTNode) !void {
        _ = node; // 标记参数为已使用
        // 简化实现
        try self.writeIndent();
        try self.output.writer().print("private Object field;\n", .{});
    }

    /// 写入缩进
    fn writeIndent(self: *CodeGenerator) !void {
        const indent_count = self.context.indent_level * self.options.indent_size;

        if (self.options.use_tabs) {
            for (0..self.context.indent_level) |_| {
                try self.output.writer().print("\t", .{});
            }
        } else {
            for (0..indent_count) |_| {
                try self.output.writer().print(" ", .{});
            }
        }
    }

    /// 判断是否需要括号
    fn needsParentheses(self: *CodeGenerator, node: *ASTNode) bool {
        _ = self;
        _ = node;
        // 简化实现，实际应该根据操作符优先级判断
        return false;
    }

    /// 获取生成的代码
    pub fn getOutput(self: *CodeGenerator) []const u8 {
        return self.output.items;
    }

    /// 清空输出
    pub fn clear(self: *CodeGenerator) void {
        self.output.clearRetainingCapacity();
        self.context.indent_level = 0;
        self.context.in_expression = false;
        self.context.current_method = null;
        self.context.current_class = null;
    }
};

/// 代码格式化器
pub const CodeFormatter = struct {
    allocator: Allocator,
    options: CodeGenOptions,

    /// 初始化代码格式化器
    pub fn init(allocator: Allocator, options: CodeGenOptions) CodeFormatter {
        return CodeFormatter{
            .allocator = allocator,
            .options = options,
        };
    }

    /// 格式化代码
    pub fn format(self: *CodeFormatter, code: []const u8) ![]const u8 {
        var result = ArrayList(u8).init(self.allocator);
        defer result.deinit();

        var lines = std.mem.splitSequence(u8, code, "\n");
        var indent_level: u32 = 0;

        while (lines.next()) |line| {
            const trimmed = std.mem.trim(u8, line, " \t");

            if (trimmed.len == 0) {
                try result.append('\n');
                continue;
            }

            // 调整缩进级别
            if (std.mem.endsWith(u8, trimmed, "}")) {
                if (indent_level > 0) indent_level -= 1;
            }

            // 写入缩进
            for (0..indent_level * self.options.indent_size) |_| {
                try result.append(' ');
            }

            // 写入代码行
            try result.appendSlice(trimmed);
            try result.append('\n');

            // 调整缩进级别
            if (std.mem.endsWith(u8, trimmed, "{")) {
                indent_level += 1;
            }
        }

        return try result.toOwnedSlice();
    }
};

// 测试
test "代码生成基础功能测试" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const options = CodeGenOptions{};
    var generator = CodeGenerator.init(allocator, options);
    defer generator.deinit();

    // 创建简单的AST
    var ast_builder = ast.ASTBuilder.init(allocator);
    defer ast_builder.deinit();

    const literal = try ast_builder.createLiteral(.{ .int_val = 42 }, .int);
    const code = try generator.generate(literal);
    defer allocator.free(code);

    try testing.expect(std.mem.eql(u8, code, "42"));
}
