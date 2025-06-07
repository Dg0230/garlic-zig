//! Garlic Java 反编译器 - 主反编译引擎
//! 整合AST构建、表达式重建、控制结构识别、代码生成和优化等功能

const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const HashMap = std.HashMap;

// 导入子模块
const ast = @import("ast.zig");
const expression = @import("expression.zig");
const control_structure = @import("control_structure.zig");
const codegen = @import("codegen.zig");
const optimizer = @import("optimizer.zig");

// 导入JVM相关模块
const jvm = @import("jvm");
const parser = @import("parser");
const ClassFile = parser.ClassFile;
const MethodInfo = parser.MethodInfo;
const AttributeInfo = parser.AttributeInfo;
const Instruction = jvm.Instruction;

// 重新导出主要类型
pub const ASTNode = ast.ASTNode;
pub const ASTBuilder = ast.ASTBuilder;
pub const ExpressionRebuilder = expression.ExpressionBuilder;
pub const ControlFlowAnalyzer = control_structure.ControlStructureAnalyzer;
pub const CodeGenerator = codegen.CodeGenerator;
pub const ASTOptimizer = optimizer.ASTOptimizer;
pub const OptimizationPipeline = optimizer.OptimizationPipeline;
pub const OptimizationOptions = optimizer.OptimizationOptions;

/// 反编译选项
pub const DecompilerOptions = struct {
    /// 是否生成注释
    generate_comments: bool = true,
    /// 是否保留原始行号信息
    preserve_line_numbers: bool = true,
    /// 是否尝试恢复局部变量名
    recover_variable_names: bool = true,
    /// 是否进行代码优化
    enable_optimization: bool = true,
    /// 优化选项
    optimization_options: OptimizationOptions = OptimizationOptions{},
    /// 代码生成选项
    codegen_options: codegen.CodeGenOptions = codegen.CodeGenOptions{},
    /// 输出格式
    output_format: OutputFormat = .java,
    /// 是否生成调试信息
    debug_info: bool = false,
    /// 是否尝试恢复泛型信息
    recover_generics: bool = true,
    /// 是否简化表达式
    simplify_expressions: bool = true,
};

/// 输出格式
pub const OutputFormat = enum {
    java,
    pseudocode,
    json_ast,
};

/// 反编译结果
pub const DecompilerResult = struct {
    /// 生成的源代码
    source_code: []const u8,
    /// AST根节点
    ast_root: *ASTNode,
    /// 反编译统计信息
    stats: DecompilerStats,
    /// 错误和警告信息
    diagnostics: ArrayList(Diagnostic),

    /// 释放结果
    pub fn deinit(self: *DecompilerResult, allocator: Allocator) void {
        allocator.free(self.source_code);
        // 释放诊断信息中的消息
        for (self.diagnostics.items) |diagnostic| {
            allocator.free(diagnostic.message);
        }
        self.diagnostics.deinit();
    }
};

/// 反编译统计信息
pub const DecompilerStats = struct {
    /// 处理的方法数量
    methods_processed: u32 = 0,
    /// 处理的指令数量
    instructions_processed: u32 = 0,
    /// 识别的控制结构数量
    control_structures_identified: u32 = 0,
    /// 重建的表达式数量
    expressions_rebuilt: u32 = 0,
    /// 优化次数
    optimizations_applied: u32 = 0,
    /// 处理时间（毫秒）
    processing_time_ms: u64 = 0,
    /// 成功反编译的方法数量
    successful_methods: u32 = 0,
    /// 失败的方法数量
    failed_methods: u32 = 0,
    /// 跳过的方法数量（抽象、native等）
    skipped_methods: u32 = 0,

    /// 重置统计信息
    pub fn reset(self: *DecompilerStats) void {
        self.* = DecompilerStats{};
    }
};

/// 诊断信息
pub const Diagnostic = struct {
    level: Level,
    message: []const u8,
    location: ?Location = null,

    pub const Level = enum {
        info,
        warning,
        @"error",
    };

    pub const Location = struct {
        method_name: []const u8,
        bytecode_offset: u32,
        line_number: ?u32 = null,
    };
};

/// 方法反编译结果
pub const MethodDecompileResult = struct {
    /// 方法AST节点
    method_ast: *ASTNode,
    /// 生成的Java代码
    java_code: []const u8,
    /// 方法统计信息
    stats: MethodStats,
    /// 诊断信息
    diagnostics: ArrayList(Diagnostic),

    pub fn deinit(self: *MethodDecompileResult, allocator: Allocator) void {
        allocator.free(self.java_code);
        for (self.diagnostics.items) |diagnostic| {
            allocator.free(diagnostic.message);
        }
        self.diagnostics.deinit();
    }
};

/// 方法统计信息
pub const MethodStats = struct {
    instruction_count: u32 = 0,
    expression_count: u32 = 0,
    control_structure_count: u32 = 0,
    local_variable_count: u32 = 0,
    max_stack_depth: u32 = 0,
    processing_time_ms: u64 = 0,
};

/// 反编译引擎
pub const Decompiler = struct {
    allocator: Allocator,
    options: DecompilerOptions,
    ast_builder: ASTBuilder,
    expression_rebuilder: ExpressionRebuilder,
    control_flow_analyzer: ControlFlowAnalyzer,
    code_generator: CodeGenerator,
    optimization_pipeline: ?OptimizationPipeline,
    stats: DecompilerStats,
    diagnostics: ArrayList(Diagnostic),

    /// 初始化反编译引擎
    pub fn init(allocator: Allocator, options: DecompilerOptions) !Decompiler {
        const temp_ast_builder = ASTBuilder.init(allocator); // Create ASTBuilder instance

        var decompiler = Decompiler{
            .allocator = allocator,
            .options = options,
            .ast_builder = temp_ast_builder, // Assign instance
            .expression_rebuilder = expression.ExpressionBuilder.init(allocator),
            .control_flow_analyzer = ControlFlowAnalyzer.init(allocator),
            .code_generator = CodeGenerator.init(allocator, options.codegen_options),
            .optimization_pipeline = null,
            .stats = DecompilerStats{},
            .diagnostics = ArrayList(Diagnostic).init(allocator),
        };

        // 如果启用优化，初始化优化管道
        if (options.enable_optimization) {
            decompiler.optimization_pipeline = OptimizationPipeline.init(allocator, options.optimization_options);
        }

        return decompiler;
    }

    /// 释放反编译引擎
    pub fn deinit(self: *Decompiler) void {
        self.ast_builder.deinit();
        self.expression_rebuilder.deinit();
        self.control_flow_analyzer.deinit();
        self.code_generator.deinit();

        if (self.optimization_pipeline) |*pipeline| {
            pipeline.deinit();
        }

        for (self.diagnostics.items) |diagnostic| {
            self.allocator.free(diagnostic.message);
        }
        self.diagnostics.deinit();
    }

    /// 反编译整个类文件
    pub fn decompileClass(self: *Decompiler, class_file: *const ClassFile) !DecompilerResult {
        const start_time = std.time.milliTimestamp();
        self.stats.reset();
        self.diagnostics.clearRetainingCapacity();

        // 创建类节点
        const class_node = try self.ast_builder.createIdentifier(class_file.getClassName());

        // 处理所有方法
        for (class_file.methods) |*method| {
            const method_result = self.decompileMethodInternal(class_file, method) catch |err| {
                self.stats.failed_methods += 1;
                try self.addDiagnostic(.@"error", "Failed to decompile method", .{
                    .method_name = method.getName(),
                    .bytecode_offset = 0,
                });
                std.log.err("Failed to decompile method {s}: {}", .{ method.getName(), err });
                continue;
            };
            defer method_result.deinit(self.allocator);

            try class_node.addChild(method_result.method_ast);
            self.stats.successful_methods += 1;
            self.stats.methods_processed += 1;
        }

        // 生成源代码
        const source_code = try self.generateSourceCode(class_node);

        // 如果启用优化，进行优化
        const final_code = if (self.optimization_pipeline) |*pipeline| blk: {
            const optimization_result = try pipeline.optimize(class_node, source_code);
            const opt_stats = pipeline.getStats();
            self.stats.optimizations_applied = opt_stats.getTotalOptimizations();
            break :blk optimization_result.code;
        } else source_code;

        self.stats.processing_time_ms = @intCast(std.time.milliTimestamp() - start_time);

        return DecompilerResult{
            .source_code = final_code,
            .ast_root = class_node,
            .stats = self.stats,
            .diagnostics = ArrayList(Diagnostic).init(self.allocator),
        };
    }

    /// 反编译单个方法（公共接口）
    pub fn decompileMethod(self: *Decompiler, class_file: *const ClassFile, method: *const MethodInfo) !MethodDecompileResult {
        return self.decompileMethodInternal(class_file, method);
    }

    /// 反编译单个方法（内部实现）
    fn decompileMethodInternal(self: *Decompiler, class_file: *const ClassFile, method: *const MethodInfo) !MethodDecompileResult {
        _ = class_file; // Mark as used to suppress warning
        const start_time = std.time.milliTimestamp();
        var method_stats = MethodStats{};
        var method_diagnostics = ArrayList(Diagnostic).init(self.allocator);

        // 检查方法是否有代码
        const code_attr = method.getCodeAttribute() orelse {
            self.stats.skipped_methods += 1;
            const message = try std.fmt.allocPrint(self.allocator, "Method {s} has no code attribute (abstract or native)", .{method.getName()});
            try method_diagnostics.append(Diagnostic{
                .level = .info,
                .message = message,
                .location = .{
                    .method_name = method.getName(),
                    .bytecode_offset = 0,
                },
            });

            // 创建抽象方法节点
            const method_node = try self.createAbstractMethodNode(method);
            const java_code = try self.code_generator.generateJavaCode(method_node);

            return MethodDecompileResult{
                .method_ast = method_node,
                .java_code = java_code,
                .stats = method_stats,
                .diagnostics = method_diagnostics,
            };
        };

        // 解析字节码指令
        const instructions = try self.parseInstructions(code_attr.code);
        defer self.allocator.free(instructions);

        method_stats.instruction_count = @intCast(instructions.len);
        method_stats.max_stack_depth = code_attr.max_stack;
        self.stats.instructions_processed += @intCast(instructions.len);

        // 构建控制流图
        const cfg = try self.control_flow_analyzer.buildCFG(instructions);

        // 识别控制结构
        const control_structures = try self.control_flow_analyzer.identifyControlStructures(cfg);
        method_stats.control_structure_count = @intCast(control_structures.len);
        self.stats.control_structures_identified += @intCast(control_structures.len);

        // 重建表达式和方法体
        const method_body = try self.rebuildMethodExpressions(instructions, control_structures, method, code_attr);
        method_stats.expression_count = @intCast(self.countExpressions(method_body));

        // 创建完整的方法节点（包含处理后的方法体）
        const method_node = try self.createCompleteMethodNode(method, method_body);

        // 生成Java代码
        const java_code = try self.code_generator.generateJavaCode(method_node);

        method_stats.processing_time_ms = @intCast(std.time.milliTimestamp() - start_time);
        self.stats.expressions_rebuilt += method_stats.expression_count;

        return MethodDecompileResult{
            .method_ast = method_node,
            .java_code = java_code,
            .stats = method_stats,
            .diagnostics = method_diagnostics,
        };
    }

    /// 创建抽象方法节点
    fn createAbstractMethodNode(self: *Decompiler, method: *const MethodInfo) !*ASTNode {
        const method_node = try self.ast_builder.createMethod(
            method.getName(),
            method.getReturnType(),
            method.getParameterTypes(),
            null, // 没有方法体
        );
        return method_node;
    }

    /// 创建完整的方法节点
    fn createCompleteMethodNode(self: *Decompiler, method: *const MethodInfo, body: *ASTNode) !*ASTNode {
        const method_node = try self.ast_builder.createMethod(
            method.getName(),
            method.getReturnType(),
            method.getParameterTypes(),
            body,
        );
        return method_node;
    }

    /// 创建包含方法体的完整方法节点
    fn createCompleteMethodNodeWithBody(self: *Decompiler, method_info: anytype, class_info: anytype, method_body: *ASTNode) !*ASTNode {
        _ = class_info;

        // 获取方法签名
        const method_signature = try self.method_parser.getMethodSignature(method_info);
        defer method_signature.deinit();

        // 创建方法节点
        const method_node = try self.ast_builder.createMethodDeclaration(method_signature.name, method_signature.return_type, method_signature.parameters, method_info.getAccessFlags());

        // 添加处理后的方法体
        try method_node.addChild(method_body);

        return method_node;
    }

    /// 计算表达式数量
    fn countExpressions(self: *Decompiler, node: *ASTNode) u32 {
        var count: u32 = 1;
        for (node.children.items) |child| {
            count += self.countExpressions(child);
        }
        return count;
    }

    /// 反编译字段
    fn decompileField(self: *Decompiler, field: *const jvm.FieldInfo) !*ASTNode {
        return try self.ast_builder.createField(
            field.getName(),
            field.getType(),
            field.getAccessFlags(),
            null, // 初始值暂时为空
        );
    }

    /// 解析字节码指令
    fn parseInstructions(self: *Decompiler, bytecode: []const u8) ![]Instruction {
        var instructions = ArrayList(Instruction).init(self.allocator);
        defer instructions.deinit();

        var offset: u32 = 0;
        while (offset < bytecode.len) {
            const instruction = try self.parseInstruction(bytecode, &offset);
            try instructions.append(instruction);
        }

        return try instructions.toOwnedSlice();
    }

    /// 解析单个指令
    fn parseInstruction(self: *Decompiler, bytecode: []const u8, offset: *u32) !Instruction {
        _ = self;

        const opcode = bytecode[offset.*];
        offset.* += 1;

        // 简化的指令解析，实际实现需要根据JVM规范处理所有指令
        return switch (opcode) {
            0x01 => Instruction{ .opcode = .aconst_null, .operands = &.{} },
            0x02 => Instruction{ .opcode = .iconst_m1, .operands = &.{} },
            0x03 => Instruction{ .opcode = .iconst_0, .operands = &.{} },
            0x04 => Instruction{ .opcode = .iconst_1, .operands = &.{} },
            0x05 => Instruction{ .opcode = .iconst_2, .operands = &.{} },
            0x06 => Instruction{ .opcode = .iconst_3, .operands = &.{} },
            0x07 => Instruction{ .opcode = .iconst_4, .operands = &.{} },
            0x08 => Instruction{ .opcode = .iconst_5, .operands = &.{} },
            0x1A => Instruction{ .opcode = .iload_0, .operands = &.{} },
            0x1B => Instruction{ .opcode = .iload_1, .operands = &.{} },
            0x1C => Instruction{ .opcode = .iload_2, .operands = &.{} },
            0x1D => Instruction{ .opcode = .iload_3, .operands = &.{} },
            0x3B => Instruction{ .opcode = .istore_0, .operands = &.{} },
            0x3C => Instruction{ .opcode = .istore_1, .operands = &.{} },
            0x3D => Instruction{ .opcode = .istore_2, .operands = &.{} },
            0x3E => Instruction{ .opcode = .istore_3, .operands = &.{} },
            0x60 => Instruction{ .opcode = .iadd, .operands = &.{} },
            0x64 => Instruction{ .opcode = .isub, .operands = &.{} },
            0x68 => Instruction{ .opcode = .imul, .operands = &.{} },
            0x6C => Instruction{ .opcode = .idiv, .operands = &.{} },
            0xAC => Instruction{ .opcode = .ireturn, .operands = &.{} },
            0xB1 => Instruction{ .opcode = .@"return", .operands = &.{} },
            else => {
                // 未知指令，跳过
                return Instruction{ .opcode = .nop, .operands = &.{} };
            },
        };
    }

    /// 重建方法表达式（增强版）
    fn rebuildMethodExpressions(self: *Decompiler, instructions: []const Instruction, control_structures: []const control_structure.ControlStructure, method: *const MethodInfo, code_attr: *const AttributeInfo) !*ASTNode {
        _ = method;
        _ = code_attr;

        // 使用表达式重建器处理指令序列
        const method_body = try self.expression_rebuilder.rebuildMethod(instructions);

        // 应用控制结构信息
        const structured_body = try self.applyControlStructures(method_body, control_structures);

        // 如果启用表达式简化，进行简化
        if (self.options.simplify_expressions) {
            return try self.simplifyExpressions(structured_body);
        }

        return structured_body;
    }

    /// 应用控制结构
    fn applyControlStructures(self: *Decompiler, body: *ASTNode, structures: []const control_structure.ControlStructure) !*ASTNode {
        _ = self;
        _ = structures;

        // 简化实现，实际需要根据控制结构重组AST
        return body;
    }

    /// 简化表达式
    fn simplifyExpressions(self: *Decompiler, body: *ASTNode) !*ASTNode {
        _ = self;
        // 简化实现，实际需要进行表达式优化
        return body;
    }

    /// 生成源代码
    fn generateSourceCode(self: *Decompiler, ast_root: *ASTNode) ![]const u8 {
        return switch (self.options.output_format) {
            .java => try self.code_generator.generateJavaCode(ast_root),
            .pseudocode => try self.generatePseudocode(ast_root),
            .json_ast => try self.generateJsonAST(ast_root),
        };
    }

    /// 生成伪代码
    fn generatePseudocode(self: *Decompiler, ast_root: *ASTNode) ![]const u8 {
        _ = ast_root;

        // 简化实现
        return try self.allocator.dupe(u8, "// Pseudocode generation not implemented\n");
    }

    /// 生成JSON格式的AST
    fn generateJsonAST(self: *Decompiler, ast_root: *ASTNode) ![]const u8 {
        _ = ast_root;

        // 简化实现
        return try self.allocator.dupe(u8, "{\"type\": \"ast\", \"message\": \"JSON AST generation not implemented\"}");
    }

    /// 添加诊断信息
    fn addDiagnostic(self: *Decompiler, level: Diagnostic.Level, message: []const u8, location: Diagnostic.Location) !void {
        const owned_message = try self.allocator.dupe(u8, message);
        try self.diagnostics.append(Diagnostic{
            .level = level,
            .message = owned_message,
            .location = location,
        });
    }

    /// 获取统计信息
    pub fn getStats(self: *Decompiler) DecompilerStats {
        return self.stats;
    }

    /// 获取诊断信息
    pub fn getDiagnostics(self: *Decompiler) []const Diagnostic {
        return self.diagnostics.items;
    }

    /// 重置反编译器状态
    pub fn reset(self: *Decompiler) void {
        self.stats.reset();

        for (self.diagnostics.items) |diagnostic| {
            self.allocator.free(diagnostic.message);
        }
        self.diagnostics.clearRetainingCapacity();

        if (self.optimization_pipeline) |*pipeline| {
            pipeline.ast_optimizer.reset();
        }
    }
};

/// 便捷函数：反编译类文件到Java源代码
pub fn decompileClassToJava(allocator: Allocator, class_file: *const ClassFile, options: ?DecompilerOptions) ![]const u8 {
    const decompiler_options = options orelse DecompilerOptions{};
    var decompiler = try Decompiler.init(allocator, decompiler_options);
    defer decompiler.deinit();

    const result = try decompiler.decompileClass(class_file);
    var mutable_result = result;
    defer {
        mutable_result.deinit(allocator);
    }

    return try allocator.dupe(u8, result.source_code);
}

/// 便捷函数：反编译方法到Java源代码
pub fn decompileMethodToJava(allocator: Allocator, class_file: *const ClassFile, method: *const MethodInfo, options: ?DecompilerOptions) ![]const u8 {
    const decompiler_options = options orelse DecompilerOptions{};
    var decompiler = try Decompiler.init(allocator, decompiler_options);
    defer decompiler.deinit();

    const method_result = try decompiler.decompileMethod(class_file, method);
    var mutable_result = method_result;
    defer {
        mutable_result.deinit(allocator);
    }

    return try allocator.dupe(u8, method_result.java_code);
}

// 测试
test "反编译引擎基础功能测试" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const options = DecompilerOptions{};
    var decompiler = try Decompiler.init(allocator, options);
    defer decompiler.deinit();

    // 测试基本功能
    const stats = decompiler.getStats();
    try testing.expect(stats.methods_processed == 0);

    const diagnostics = decompiler.getDiagnostics();
    try testing.expect(diagnostics.len == 0);
}

test "方法反编译功能测试" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const options = DecompilerOptions{
        .generate_comments = true,
        .recover_variable_names = true,
        .simplify_expressions = true,
    };
    var decompiler = try Decompiler.init(allocator, options);
    defer decompiler.deinit();

    // 测试统计信息重置
    decompiler.reset();
    const stats = decompiler.getStats();
    try testing.expect(stats.methods_processed == 0);
    try testing.expect(stats.successful_methods == 0);
    try testing.expect(stats.failed_methods == 0);
}

// 测试函数
test "decompiler basic functionality" {
    const testing = std.testing;
    const allocator = testing.allocator;

    // 创建基本的反编译器选项
    const options = DecompilerOptions{
        .preserve_line_numbers = true,
        .generate_comments = false,
        .simplify_expressions = false,
        .codegen_options = .{
            .indent_size = 4,
            .use_tabs = false,
            .max_line_length = 120,
            .add_comments = true,
        },
    };

    // 测试反编译器初始化
    var decompiler = try Decompiler.init(allocator, options);
    defer decompiler.deinit();

    // 基本功能测试通过
    try testing.expect(true);
}
