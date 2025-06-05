//! 优化器模块
//! 负责对AST和生成的代码进行优化处理

const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const HashMap = std.HashMap;
const ast = @import("ast.zig");
const ASTNode = ast.ASTNode;
const NodeType = ast.NodeType;
const BinaryOp = ast.BinaryOp;
const UnaryOp = ast.UnaryOp;
const LiteralValue = ast.LiteralValue;
const DataType = ast.DataType;

/// 优化选项
pub const OptimizationOptions = struct {
    constant_folding: bool = true,
    dead_code_elimination: bool = true,
    expression_simplification: bool = true,
    variable_inlining: bool = true,
    redundant_cast_removal: bool = true,
    loop_optimization: bool = false, // 暂时禁用，需要更复杂的分析
    method_inlining: bool = false, // 暂时禁用，需要调用图分析
};

/// 优化统计信息
pub const OptimizationStats = struct {
    constants_folded: u32 = 0,
    dead_code_removed: u32 = 0,
    expressions_simplified: u32 = 0,
    variables_inlined: u32 = 0,
    casts_removed: u32 = 0,

    /// 重置统计信息
    pub fn reset(self: *OptimizationStats) void {
        self.* = OptimizationStats{};
    }

    /// 获取总优化次数
    pub fn getTotalOptimizations(self: OptimizationStats) u32 {
        return self.constants_folded +
            self.dead_code_removed +
            self.expressions_simplified +
            self.variables_inlined +
            self.casts_removed;
    }
};

/// 变量使用信息
pub const VariableUsage = struct {
    name: []const u8,
    definition_count: u32 = 0,
    usage_count: u32 = 0,
    is_constant: bool = false,
    constant_value: ?*ASTNode = null,
};

/// AST优化器
pub const ASTOptimizer = struct {
    allocator: Allocator,
    options: OptimizationOptions,
    stats: OptimizationStats,
    variable_usage: HashMap([]const u8, VariableUsage, std.hash_map.StringContext, std.hash_map.default_max_load_percentage),

    /// 初始化AST优化器
    pub fn init(allocator: Allocator, options: OptimizationOptions) ASTOptimizer {
        return ASTOptimizer{
            .allocator = allocator,
            .options = options,
            .stats = OptimizationStats{},
            .variable_usage = HashMap([]const u8, VariableUsage, std.hash_map.StringContext, std.hash_map.default_max_load_percentage).init(allocator),
        };
    }

    /// 释放AST优化器
    pub fn deinit(self: *ASTOptimizer) void {
        self.variable_usage.deinit();
    }

    /// 优化AST
    pub fn optimize(self: *ASTOptimizer, root: *ASTNode) !*ASTNode {
        self.stats.reset();

        // 多轮优化，直到没有更多改进
        var optimized_root = root;
        const max_iterations: u32 = 10;
        var iteration: u32 = 0;

        while (iteration < max_iterations) {
            const old_stats = self.stats;

            // 分析变量使用情况
            if (self.options.variable_inlining or self.options.dead_code_elimination) {
                try self.analyzeVariableUsage(optimized_root);
            }

            // 执行各种优化
            optimized_root = try self.optimizeNode(optimized_root);

            // 如果没有新的优化，退出循环
            if (self.stats.getTotalOptimizations() == old_stats.getTotalOptimizations()) {
                break;
            }

            iteration += 1;
        }

        return optimized_root;
    }

    /// 优化单个节点
    fn optimizeNode(self: *ASTOptimizer, node: *ASTNode) !*ASTNode {
        // 首先优化子节点
        for (node.children.items, 0..) |child, i| {
            node.children.items[i] = try self.optimizeNode(child);
        }

        // 然后优化当前节点
        var optimized_node = node;

        if (self.options.constant_folding) {
            optimized_node = try self.constantFolding(optimized_node);
        }

        if (self.options.expression_simplification) {
            optimized_node = try self.simplifyExpression(optimized_node);
        }

        if (self.options.redundant_cast_removal) {
            optimized_node = try self.removeRedundantCasts(optimized_node);
        }

        if (self.options.dead_code_elimination) {
            optimized_node = try self.eliminateDeadCode(optimized_node);
        }

        return optimized_node;
    }

    /// 常量折叠优化
    fn constantFolding(self: *ASTOptimizer, node: *ASTNode) !*ASTNode {
        if (node.node_type != .binary_op or node.children.items.len != 2) {
            return node;
        }

        const left = node.children.items[0];
        const right = node.children.items[1];

        // 只处理两个操作数都是字面量的情况
        if (left.node_type != .literal or right.node_type != .literal) {
            return node;
        }

        const left_data = left.data.literal;
        const right_data = right.data.literal;
        const op = node.data.binary_op;

        // 只处理整数运算
        if (left_data.value != .int_val or right_data.value != .int_val) {
            return node;
        }

        const left_val = left_data.value.int_val;
        const right_val = right_data.value.int_val;

        const result_val: i64 = switch (op) {
            .add => left_val + right_val,
            .sub => left_val - right_val,
            .mul => left_val * right_val,
            .div => if (right_val != 0) @divTrunc(left_val, right_val) else return node,
            .mod => if (right_val != 0) @mod(left_val, right_val) else return node,
            .bit_and => left_val & right_val,
            .bit_or => left_val | right_val,
            .bit_xor => left_val ^ right_val,
            .shl => left_val << @intCast(right_val),
            .shr => left_val >> @intCast(right_val),
            else => return node, // 不支持的操作
        };

        // 重用现有节点，避免内存泄漏
        node.node_type = .literal;
        node.setLiteral(.{ .int_val = result_val }, .int);

        // 清理子节点
        for (node.children.items) |child| {
            child.deinit();
        }
        node.children.clearAndFree();

        self.stats.constants_folded += 1;
        return node;
    }

    /// 表达式简化
    fn simplifyExpression(self: *ASTOptimizer, node: *ASTNode) !*ASTNode {
        if (node.node_type != .binary_op or node.children.items.len != 2) {
            return node;
        }

        const left = node.children.items[0];
        const right = node.children.items[1];
        const op = node.data.binary_op;

        // 简化规则：x + 0 = x, x * 1 = x, x * 0 = 0, etc.
        switch (op) {
            .add => {
                if (self.isZeroLiteral(right)) {
                    self.stats.expressions_simplified += 1;
                    return left;
                }
                if (self.isZeroLiteral(left)) {
                    self.stats.expressions_simplified += 1;
                    return right;
                }
            },
            .sub => {
                if (self.isZeroLiteral(right)) {
                    self.stats.expressions_simplified += 1;
                    return left;
                }
            },
            .mul => {
                if (self.isZeroLiteral(left) or self.isZeroLiteral(right)) {
                    const zero_node = try ASTNode.init(self.allocator, .literal);
                    zero_node.setLiteral(.{ .int_val = 0 }, .int);
                    self.stats.expressions_simplified += 1;
                    return zero_node;
                }
                if (self.isOneLiteral(right)) {
                    self.stats.expressions_simplified += 1;
                    return left;
                }
                if (self.isOneLiteral(left)) {
                    self.stats.expressions_simplified += 1;
                    return right;
                }
            },
            .div => {
                if (self.isOneLiteral(right)) {
                    self.stats.expressions_simplified += 1;
                    return left;
                }
            },
            .bit_and => {
                if (self.isZeroLiteral(left) or self.isZeroLiteral(right)) {
                    const zero_node = try ASTNode.init(self.allocator, .literal);
                    zero_node.setLiteral(.{ .int_val = 0 }, .int);
                    self.stats.expressions_simplified += 1;
                    return zero_node;
                }
            },
            .bit_or => {
                if (self.isZeroLiteral(right)) {
                    self.stats.expressions_simplified += 1;
                    return left;
                }
                if (self.isZeroLiteral(left)) {
                    self.stats.expressions_simplified += 1;
                    return right;
                }
            },
            else => {},
        }

        return node;
    }

    /// 移除冗余的类型转换
    fn removeRedundantCasts(self: *ASTOptimizer, node: *ASTNode) !*ASTNode {
        if (node.node_type != .cast or node.children.items.len != 1) {
            return node;
        }

        const expr = node.children.items[0];
        const target_type = node.data_type orelse return node;

        // 如果表达式的类型已经是目标类型，移除转换
        if (expr.data_type) |expr_type| {
            if (expr_type == target_type) {
                self.stats.casts_removed += 1;
                return expr;
            }
        }

        // 如果是连续的类型转换，可能可以合并或移除
        if (expr.node_type == .cast and expr.children.items.len == 1) {
            const inner_expr = expr.children.items[0];
            if (inner_expr.data_type) |inner_type| {
                if (inner_type == target_type) {
                    // 移除中间的转换
                    self.stats.casts_removed += 1;
                    const new_cast = try ASTNode.init(self.allocator, .cast);
                    new_cast.data_type = target_type;
                    try new_cast.addChild(inner_expr);
                    return new_cast;
                }
            }
        }

        return node;
    }

    /// 死代码消除
    fn eliminateDeadCode(self: *ASTOptimizer, node: *ASTNode) !*ASTNode {
        switch (node.node_type) {
            .block_stmt => {
                var new_children = ArrayList(*ASTNode).init(self.allocator);
                defer new_children.deinit();

                for (node.children.items) |child| {
                    if (!self.isDeadCode(child)) {
                        try new_children.append(child);
                    } else {
                        self.stats.dead_code_removed += 1;
                    }
                }

                // 更新子节点列表
                node.children.clearRetainingCapacity();
                try node.children.appendSlice(new_children.items);
            },
            .if_stmt => {
                if (node.children.items.len >= 2) {
                    const condition = node.children.items[0];

                    // 如果条件是常量，可以简化if语句
                    if (condition.node_type == .literal and condition.data.literal.value == .bool_val) {
                        const condition_value = condition.data.literal.value.bool_val;

                        if (condition_value) {
                            // 条件为真，返回then分支
                            self.stats.dead_code_removed += 1;
                            return node.children.items[1];
                        } else {
                            // 条件为假，返回else分支（如果存在）
                            if (node.children.items.len > 2) {
                                self.stats.dead_code_removed += 1;
                                return node.children.items[2];
                            } else {
                                // 没有else分支，返回空块
                                self.stats.dead_code_removed += 1;
                                return try ASTNode.init(self.allocator, .block_stmt);
                            }
                        }
                    }
                }
            },
            else => {},
        }

        return node;
    }

    /// 分析变量使用情况
    fn analyzeVariableUsage(self: *ASTOptimizer, node: *ASTNode) !void {
        self.variable_usage.clearRetainingCapacity();
        try self.collectVariableUsage(node);
    }

    /// 收集变量使用情况
    fn collectVariableUsage(self: *ASTOptimizer, node: *ASTNode) !void {
        switch (node.node_type) {
            .identifier => {
                if (node.data == .identifier) {
                    const name = node.data.identifier;
                    var usage = self.variable_usage.get(name) orelse VariableUsage{ .name = name };
                    usage.usage_count += 1;
                    try self.variable_usage.put(name, usage);
                }
            },
            .variable_decl => {
                if (node.data == .variable_decl) {
                    const var_data = node.data.variable_decl;
                    var usage = self.variable_usage.get(var_data.name) orelse VariableUsage{ .name = var_data.name };
                    usage.definition_count += 1;

                    // 检查是否是常量赋值
                    if (node.children.items.len > 0) {
                        const init_expr = node.children.items[0];
                        if (init_expr.node_type == .literal) {
                            usage.is_constant = true;
                            usage.constant_value = init_expr;
                        }
                    }

                    try self.variable_usage.put(var_data.name, usage);
                }
            },
            else => {},
        }

        // 递归处理子节点
        for (node.children.items) |child| {
            try self.collectVariableUsage(child);
        }
    }

    /// 判断是否是死代码
    fn isDeadCode(self: *ASTOptimizer, node: *ASTNode) bool {
        switch (node.node_type) {
            .expression_stmt => {
                if (node.children.items.len == 1) {
                    const expr = node.children.items[0];
                    // 纯表达式（没有副作用）可以被移除
                    return self.isPureExpression(expr);
                }
            },
            else => {},
        }

        return false;
    }

    /// 判断是否是纯表达式（没有副作用）
    fn isPureExpression(self: *ASTOptimizer, node: *ASTNode) bool {
        switch (node.node_type) {
            .literal, .identifier => return true,
            .binary_op, .unary_op => {
                // 算术和逻辑运算通常是纯的
                for (node.children.items) |child| {
                    if (!self.isPureExpression(child)) {
                        return false;
                    }
                }
                return true;
            },
            .method_call => return false, // 方法调用可能有副作用
            .assignment => return false, // 赋值有副作用
            else => return false,
        }
    }

    /// 判断是否是零字面量
    fn isZeroLiteral(self: *ASTOptimizer, node: *ASTNode) bool {
        _ = self;

        if (node.node_type != .literal) return false;

        const literal_data = node.data.literal;
        return switch (literal_data.value) {
            .int_val => |val| val == 0,
            .float_val => |val| val == 0.0,
            else => false,
        };
    }

    /// 判断是否是一字面量
    fn isOneLiteral(self: *ASTOptimizer, node: *ASTNode) bool {
        _ = self;

        if (node.node_type != .literal) return false;

        const literal_data = node.data.literal;
        return switch (literal_data.value) {
            .int_val => |val| val == 1,
            .float_val => |val| val == 1.0,
            else => false,
        };
    }

    /// 获取优化统计信息
    pub fn getStats(self: *ASTOptimizer) OptimizationStats {
        return self.stats;
    }

    /// 重置优化器状态
    pub fn reset(self: *ASTOptimizer) void {
        self.stats.reset();
        self.variable_usage.clearRetainingCapacity();
    }
};

/// 代码优化器（针对生成的源代码）
pub const CodeOptimizer = struct {
    allocator: Allocator,
    options: OptimizationOptions,

    /// 初始化代码优化器
    pub fn init(allocator: Allocator, options: OptimizationOptions) CodeOptimizer {
        return CodeOptimizer{
            .allocator = allocator,
            .options = options,
        };
    }

    /// 优化生成的Java代码
    pub fn optimizeCode(self: *CodeOptimizer, code: []const u8) ![]const u8 {
        var result = ArrayList(u8).init(self.allocator);
        defer result.deinit();

        var lines = std.mem.splitSequence(u8, code, "\n");

        while (lines.next()) |line| {
            const optimized_line = try self.optimizeLine(line);
            if (optimized_line.len > 0) {
                try result.appendSlice(optimized_line);
                try result.append('\n');
            }
        }

        return try result.toOwnedSlice();
    }

    /// 优化单行代码
    fn optimizeLine(self: *CodeOptimizer, line: []const u8) ![]const u8 {
        const trimmed = std.mem.trim(u8, line, " \t");

        // 移除空行
        if (trimmed.len == 0) {
            return "";
        }

        // 移除无用的分号
        if (std.mem.eql(u8, trimmed, ";")) {
            return "";
        }

        // 简化常量表达式
        if (self.options.constant_folding) {
            return try self.simplifyConstantExpressions(trimmed);
        }

        return trimmed;
    }

    /// 简化常量表达式
    fn simplifyConstantExpressions(self: *CodeOptimizer, line: []const u8) ![]const u8 {
        // 简化版本：直接返回原始行
        return try self.allocator.dupe(u8, line);
    }
};

/// 优化管道
pub const OptimizationPipeline = struct {
    allocator: Allocator,
    ast_optimizer: ASTOptimizer,
    code_optimizer: CodeOptimizer,

    /// 初始化优化管道
    pub fn init(allocator: Allocator, options: OptimizationOptions) OptimizationPipeline {
        return OptimizationPipeline{
            .allocator = allocator,
            .ast_optimizer = ASTOptimizer.init(allocator, options),
            .code_optimizer = CodeOptimizer.init(allocator, options),
        };
    }

    /// 释放优化管道
    pub fn deinit(self: *OptimizationPipeline) void {
        self.ast_optimizer.deinit();
    }

    /// 执行完整的优化流程
    pub fn optimize(self: *OptimizationPipeline, ast_root: *ASTNode, code: []const u8) !struct { ast: *ASTNode, code: []const u8 } {
        // 首先优化AST
        const optimized_ast = try self.ast_optimizer.optimize(ast_root);

        // 然后优化生成的代码
        const optimized_code = try self.code_optimizer.optimizeCode(code);

        return .{ .ast = optimized_ast, .code = optimized_code };
    }

    /// 获取优化统计信息
    pub fn getStats(self: *OptimizationPipeline) OptimizationStats {
        return self.ast_optimizer.getStats();
    }
};

// 测试
test "优化器基础功能测试" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const options = OptimizationOptions{};
    var optimizer = ASTOptimizer.init(allocator, options);
    defer optimizer.deinit();

    // 创建简单的AST进行测试
    var ast_builder = ast.ASTBuilder.init(allocator);
    defer ast_builder.deinit();

    const left = try ast_builder.createLiteral(.{ .int_val = 5 }, .int);
    const right = try ast_builder.createLiteral(.{ .int_val = 3 }, .int);
    const add_node = try ast_builder.createBinaryOp(.add, left, right);

    const optimized = try optimizer.optimize(add_node);

    // 应该被优化为常量8
    try testing.expect(optimized.node_type == .literal);
    try testing.expect(optimized.data.literal.value.int_val == 8);

    const stats = optimizer.getStats();
    try testing.expect(stats.constants_folded > 0);
}
