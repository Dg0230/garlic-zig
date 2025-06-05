//! 反编译引擎主模块
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
const jvm = @import("../jvm/jvm.zig");
const parser = @import("../parser/bytecode.zig");
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
        var decompiler = Decompiler{
            .allocator = allocator,
            .options = options,
            .ast_builder = ASTBuilder.init(allocator),
            .expression_rebuilder = ExpressionRebuilder.init(allocator),
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

        // 创建简单的类节点
        const class_node = try self.ast_builder.createIdentifier("TestClass");

        // 处理方法（简化版本）
        for (class_file.methods) |_| {
            // 简单处理方法
            self.stats.methods_processed += 1;
        }

        // 生成简单的源代码
        const source_code = try self.allocator.dupe(u8, "// Generated Java code\npublic class TestClass {\n}\n");

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
            .diagnostics = try self.diagnostics.clone(),
        };
    }

    /// 反编译单个方法
    pub fn decompileMethod(self: *Decompiler, class_file: *const ClassFile, method: *const MethodInfo) !*ASTNode {
        _ = class_file;
        // 获取方法的Code属性
        const code_attr = method.getCodeAttribute() orelse {
            try self.addDiagnostic(.warning, "Method has no code attribute", .{
                .method_name = method.getName(),
                .bytecode_offset = 0,
            });

            // 创建抽象方法节点
            return try self.ast_builder.createMethod(
                method.getName(),
                method.getReturnType(),
                method.getParameterTypes(),
                null, // 没有方法体
            );
        };

        // 解析字节码指令
        const instructions = try self.parseInstructions(code_attr.code);
        defer self.allocator.free(instructions);

        self.stats.instructions_processed += @intCast(instructions.len);

        // 构建控制流图
        const cfg = try self.control_flow_analyzer.buildCFG(instructions);

        // 识别控制结构
        const control_structures = try self.control_flow_analyzer.identifyControlStructures(cfg);
        self.stats.control_structures_identified += @intCast(control_structures.len);

        // 重建表达式
        const method_ast = try self.rebuildMethodExpressions(instructions, control_structures);

        // 创建方法节点
        const method_node = try self.ast_builder.createMethod(
            method.getName(),
            method.getReturnType(),
            method.getParameterTypes(),
            method_ast,
        );

        return method_node;
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

    /// 重建方法表达式
    fn rebuildMethodExpressions(self: *Decompiler, instructions: []const Instruction, control_structures: []const control_structure.ControlStructure) !*ASTNode {
        // 使用表达式重建器处理指令序列
        const method_body = try self.expression_rebuilder.rebuildMethod(instructions);

        // 应用控制结构信息
        const structured_body = try self.applyControlStructures(method_body, control_structures);

        self.stats.expressions_rebuilt += @intCast(instructions.len);

        return structured_body;
    }

    /// 应用控制结构
    fn applyControlStructures(self: *Decompiler, body: *ASTNode, structures: []const control_structure.ControlStructure) !*ASTNode {
        _ = self;
        _ = structures;

        // 简化实现，实际需要根据控制结构重组AST
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
pub fn decompileToJava(allocator: Allocator, class_file: *const ClassFile, options: ?DecompilerOptions) ![]const u8 {
    const decompiler_options = options orelse DecompilerOptions{};
    var decompiler = try Decompiler.init(allocator, decompiler_options);
    defer decompiler.deinit();

    const result = try decompiler.decompileClass(class_file);
    defer {
        var mutable_result = result;
        mutable_result.deinit(allocator);
    }

    return try allocator.dupe(u8, result.source_code);
}

/// 便捷函数：反编译方法到Java源代码
pub fn decompileMethodToJava(allocator: Allocator, class_file: *const ClassFile, method: *const MethodInfo, options: ?DecompilerOptions) ![]const u8 {
    const decompiler_options = options orelse DecompilerOptions{};
    var decompiler = try Decompiler.init(allocator, decompiler_options);
    defer decompiler.deinit();

    const method_ast = try decompiler.decompileMethod(class_file, method);
    return try decompiler.code_generator.generateJavaCode(method_ast);
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
