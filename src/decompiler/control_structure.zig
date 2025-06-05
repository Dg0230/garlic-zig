//! 控制结构识别模块
//! 负责识别和重建if、while、for等控制流结构

const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const HashMap = std.HashMap;
const ast = @import("ast.zig");
const ASTNode = ast.ASTNode;
const ASTBuilder = ast.ASTBuilder;
const expression = @import("expression.zig");
const Instruction = expression.Instruction;

/// 基本块类型
pub const BasicBlock = struct {
    id: u32,
    start_pc: u32,
    end_pc: u32,
    instructions: ArrayList(Instruction),
    predecessors: ArrayList(u32),
    successors: ArrayList(u32),
    ast_nodes: ArrayList(*ASTNode),
    allocator: Allocator,

    /// 初始化基本块
    pub fn init(allocator: Allocator, id: u32, start_pc: u32) BasicBlock {
        return BasicBlock{
            .id = id,
            .start_pc = start_pc,
            .end_pc = start_pc,
            .instructions = ArrayList(Instruction).init(allocator),
            .predecessors = ArrayList(u32).init(allocator),
            .successors = ArrayList(u32).init(allocator),
            .ast_nodes = ArrayList(*ASTNode).init(allocator),
            .allocator = allocator,
        };
    }

    /// 释放基本块
    pub fn deinit(self: *BasicBlock) void {
        self.instructions.deinit();
        self.predecessors.deinit();
        self.successors.deinit();
        self.ast_nodes.deinit();
    }

    /// 添加指令
    pub fn addInstruction(self: *BasicBlock, instruction: Instruction) !void {
        try self.instructions.append(instruction);
        self.end_pc = instruction.pc;
    }

    /// 添加前驱块
    pub fn addPredecessor(self: *BasicBlock, block_id: u32) !void {
        try self.predecessors.append(block_id);
    }

    /// 添加后继块
    pub fn addSuccessor(self: *BasicBlock, block_id: u32) !void {
        try self.successors.append(block_id);
    }

    /// 添加AST节点
    pub fn addASTNode(self: *BasicBlock, node: *ASTNode) !void {
        try self.ast_nodes.append(node);
    }
};

/// 控制流图
pub const ControlFlowGraph = struct {
    blocks: HashMap(u32, BasicBlock, std.hash_map.AutoContext(u32), std.hash_map.default_max_load_percentage),
    entry_block: ?u32,
    exit_blocks: ArrayList(u32),
    allocator: Allocator,

    /// 初始化控制流图
    pub fn init(allocator: Allocator) ControlFlowGraph {
        return ControlFlowGraph{
            .blocks = HashMap(u32, BasicBlock, std.hash_map.AutoContext(u32), std.hash_map.default_max_load_percentage).init(allocator),
            .entry_block = null,
            .exit_blocks = ArrayList(u32).init(allocator),
            .allocator = allocator,
        };
    }

    /// 释放控制流图
    pub fn deinit(self: *ControlFlowGraph) void {
        var iterator = self.blocks.iterator();
        while (iterator.next()) |entry| {
            entry.value_ptr.deinit();
        }
        self.blocks.deinit();
        self.exit_blocks.deinit();
    }

    /// 添加基本块
    pub fn addBlock(self: *ControlFlowGraph, block: BasicBlock) !void {
        try self.blocks.put(block.id, block);
        if (self.entry_block == null) {
            self.entry_block = block.id;
        }
    }

    /// 获取基本块
    pub fn getBlock(self: *ControlFlowGraph, id: u32) ?*BasicBlock {
        return self.blocks.getPtr(id);
    }

    /// 添加边
    pub fn addEdge(self: *ControlFlowGraph, from: u32, to: u32) !void {
        if (self.getBlock(from)) |from_block| {
            try from_block.addSuccessor(to);
        }
        if (self.getBlock(to)) |to_block| {
            try to_block.addPredecessor(from);
        }
    }
};

/// 控制结构类型
pub const ControlStructureType = enum {
    if_then,
    if_then_else,
    while_loop,
    do_while_loop,
    for_loop,
    switch_case,
    try_catch,
};

/// 控制结构
pub const ControlStructure = struct {
    structure_type: ControlStructureType,
    header_block: u32,
    body_blocks: ArrayList(u32),
    else_blocks: ArrayList(u32),
    exit_block: ?u32,
    condition_node: ?*ASTNode,
    allocator: Allocator,

    /// 初始化控制结构
    pub fn init(allocator: Allocator, structure_type: ControlStructureType, header_block: u32) ControlStructure {
        return ControlStructure{
            .structure_type = structure_type,
            .header_block = header_block,
            .body_blocks = ArrayList(u32).init(allocator),
            .else_blocks = ArrayList(u32).init(allocator),
            .exit_block = null,
            .condition_node = null,
            .allocator = allocator,
        };
    }

    /// 释放控制结构
    pub fn deinit(self: *ControlStructure) void {
        self.body_blocks.deinit();
        self.else_blocks.deinit();
    }
};

/// 控制结构识别器
pub const ControlStructureAnalyzer = struct {
    allocator: Allocator,
    cfg: ControlFlowGraph,
    ast_builder: ASTBuilder,
    structures: ArrayList(ControlStructure),

    /// 初始化控制结构识别器
    pub fn init(allocator: Allocator) ControlStructureAnalyzer {
        return ControlStructureAnalyzer{
            .allocator = allocator,
            .cfg = ControlFlowGraph.init(allocator),
            .ast_builder = ASTBuilder.init(allocator),
            .structures = ArrayList(ControlStructure).init(allocator),
        };
    }

    /// 释放控制结构识别器
    pub fn deinit(self: *ControlStructureAnalyzer) void {
        self.cfg.deinit();
        self.ast_builder.deinit();
        for (self.structures.items) |*structure| {
            structure.deinit();
        }
        self.structures.deinit();
    }

    /// 从指令序列构建控制流图
    pub fn buildCFG(self: *ControlStructureAnalyzer, instructions: []const Instruction) !void {
        const current_block_id: u32 = 0;
        _ = current_block_id; // 避免未使用变量警告
        var block_starts = std.AutoHashMap(u32, void).init(self.allocator);
        defer block_starts.deinit();

        // 第一遍：识别基本块的起始位置
        try block_starts.put(0, {}); // 第一条指令总是基本块的开始

        for (instructions) |instruction| {
            switch (instruction.opcode) {
                // 分支指令
                0x99...0xa4, 0xa7 => { // if*, goto
                    if (instruction.operands.len >= 2) {
                        const offset = (@as(i16, instruction.operands[0]) << 8) | instruction.operands[1];
                        const target_pc = @as(u32, @intCast(@as(i32, @intCast(instruction.pc)) + offset));
                        try block_starts.put(target_pc, {});
                        try block_starts.put(instruction.pc + 3, {}); // 下一条指令
                    }
                },
                // 返回指令
                0xac, 0xb0, 0xb1 => {
                    if (instruction.pc + 1 < instructions.len) {
                        try block_starts.put(instruction.pc + 1, {});
                    }
                },
                else => {},
            }
        }

        // 第二遍：构建基本块
        var block_start_list = ArrayList(u32).init(self.allocator);
        defer block_start_list.deinit();

        var start_iterator = block_starts.iterator();
        while (start_iterator.next()) |entry| {
            try block_start_list.append(entry.key_ptr.*);
        }

        std.sort.heap(u32, block_start_list.items, {}, std.sort.asc(u32));

        for (block_start_list.items, 0..) |start_pc, i| {
            var block = BasicBlock.init(self.allocator, @intCast(i), start_pc);

            const end_pc = if (i + 1 < block_start_list.items.len)
                block_start_list.items[i + 1]
            else
                std.math.maxInt(u32);

            for (instructions) |instruction| {
                if (instruction.pc >= start_pc and instruction.pc < end_pc) {
                    try block.addInstruction(instruction);
                }
            }

            try self.cfg.addBlock(block);
        }

        // 第三遍：添加控制流边
        for (block_start_list.items, 0..) |_, i| {
            if (self.cfg.getBlock(@intCast(i))) |block| {
                if (block.instructions.items.len > 0) {
                    const last_instruction = block.instructions.items[block.instructions.items.len - 1];

                    switch (last_instruction.opcode) {
                        // 无条件跳转
                        0xa7 => { // goto
                            if (last_instruction.operands.len >= 2) {
                                const offset = (@as(i16, last_instruction.operands[0]) << 8) | last_instruction.operands[1];
                                const target_pc = @as(u32, @intCast(@as(i32, @intCast(last_instruction.pc)) + offset));
                                if (self.findBlockByPC(target_pc)) |target_id| {
                                    try self.cfg.addEdge(@intCast(i), target_id);
                                }
                            }
                        },
                        // 条件跳转
                        0x99...0xa4 => { // if*
                            if (last_instruction.operands.len >= 2) {
                                const offset = (@as(i16, last_instruction.operands[0]) << 8) | last_instruction.operands[1];
                                const target_pc = @as(u32, @intCast(@as(i32, @intCast(last_instruction.pc)) + offset));
                                if (self.findBlockByPC(target_pc)) |target_id| {
                                    try self.cfg.addEdge(@intCast(i), target_id);
                                }
                            }
                            // 添加到下一个基本块的边
                            if (i + 1 < block_start_list.items.len) {
                                try self.cfg.addEdge(@intCast(i), @intCast(i + 1));
                            }
                        },
                        // 返回指令
                        0xac, 0xb0, 0xb1 => {
                            // 不添加边，这是退出块
                        },
                        else => {
                            // 顺序执行到下一个基本块
                            if (i + 1 < block_start_list.items.len) {
                                try self.cfg.addEdge(@intCast(i), @intCast(i + 1));
                            }
                        },
                    }
                }
            }
        }
    }

    /// 根据PC查找基本块ID
    fn findBlockByPC(self: *ControlStructureAnalyzer, pc: u32) ?u32 {
        var iterator = self.cfg.blocks.iterator();
        while (iterator.next()) |entry| {
            const block = entry.value_ptr;
            if (pc >= block.start_pc and pc <= block.end_pc) {
                return block.id;
            }
        }
        return null;
    }

    /// 识别控制结构
    pub fn analyzeControlStructures(self: *ControlStructureAnalyzer) !void {
        var iterator = self.cfg.blocks.iterator();
        while (iterator.next()) |entry| {
            const block = entry.value_ptr;
            try self.analyzeBlock(block);
        }
    }

    /// 分析单个基本块
    fn analyzeBlock(self: *ControlStructureAnalyzer, block: *BasicBlock) !void {
        if (block.instructions.items.len == 0) return;

        const last_instruction = block.instructions.items[block.instructions.items.len - 1];

        switch (last_instruction.opcode) {
            // if 条件跳转
            0x99...0xa4 => {
                try self.analyzeIfStructure(block);
            },
            // goto 无条件跳转
            0xa7 => {
                try self.analyzeGotoStructure(block);
            },
            else => {},
        }
    }

    /// 分析if结构
    fn analyzeIfStructure(self: *ControlStructureAnalyzer, header_block: *BasicBlock) !void {
        if (header_block.successors.items.len != 2) return;

        const then_block_id = header_block.successors.items[0];
        const else_block_id = header_block.successors.items[1];

        // 检查是否是简单的if-then结构
        if (self.cfg.getBlock(then_block_id)) |_| {
            if (self.cfg.getBlock(else_block_id)) |_| {
                // 查找汇合点
                const merge_block = self.findMergeBlock(then_block_id, else_block_id);

                if (merge_block != null) {
                    // 创建if-then-else结构
                    var structure = ControlStructure.init(self.allocator, .if_then_else, header_block.id);
                    try structure.body_blocks.append(then_block_id);
                    try structure.else_blocks.append(else_block_id);
                    structure.exit_block = merge_block;
                    try self.structures.append(structure);
                } else {
                    // 创建简单if-then结构
                    var structure = ControlStructure.init(self.allocator, .if_then, header_block.id);
                    try structure.body_blocks.append(then_block_id);
                    try self.structures.append(structure);
                }
            }
        }
    }

    /// 分析goto结构（可能是循环）
    fn analyzeGotoStructure(self: *ControlStructureAnalyzer, block: *BasicBlock) !void {
        if (block.successors.items.len != 1) return;

        const target_id = block.successors.items[0];

        // 检查是否是回边（循环）
        if (target_id <= block.id) {
            // 这可能是一个循环的回边
            if (self.cfg.getBlock(target_id)) |_| {
                var structure = ControlStructure.init(self.allocator, .while_loop, target_id);

                // 收集循环体中的所有基本块
                try self.collectLoopBlocks(&structure, target_id, block.id);

                try self.structures.append(structure);
            }
        }
    }

    /// 查找两个基本块的汇合点
    fn findMergeBlock(self: *ControlStructureAnalyzer, block1_id: u32, block2_id: u32) ?u32 {
        const block1 = self.cfg.getBlock(block1_id) orelse return null;
        const block2 = self.cfg.getBlock(block2_id) orelse return null;

        // 简单实现：查找第一个共同的后继
        for (block1.successors.items) |succ1| {
            for (block2.successors.items) |succ2| {
                if (succ1 == succ2) {
                    return succ1;
                }
            }
        }

        return null;
    }

    /// 收集循环体中的基本块
    fn collectLoopBlocks(self: *ControlStructureAnalyzer, structure: *ControlStructure, header_id: u32, back_edge_id: u32) !void {
        var visited = std.AutoHashMap(u32, void).init(self.allocator);
        defer visited.deinit();

        var stack = ArrayList(u32).init(self.allocator);
        defer stack.deinit();

        try stack.append(back_edge_id);

        while (stack.items.len > 0) {
            const current_id = stack.pop() orelse break;
            if (visited.contains(current_id) or current_id == header_id) {
                continue;
            }

            try visited.put(current_id, {});
            try structure.body_blocks.append(current_id);

            if (self.cfg.getBlock(current_id)) |block| {
                for (block.predecessors.items) |pred_id| {
                    if (!visited.contains(pred_id) and pred_id != header_id) {
                        try stack.append(pred_id);
                    }
                }
            }
        }
    }

    /// 构建控制结构的AST
    pub fn buildControlStructureAST(self: *ControlStructureAnalyzer) !?*ASTNode {
        if (self.structures.items.len == 0) return null;

        const root = try self.ast_builder.createBlock();

        for (self.structures.items) |structure| {
            const structure_node = try self.buildStructureAST(structure);
            if (structure_node) |node| {
                try root.addChild(node);
            }
        }

        return root;
    }

    /// 构建单个控制结构的AST
    fn buildStructureAST(self: *ControlStructureAnalyzer, structure: ControlStructure) !?*ASTNode {
        switch (structure.structure_type) {
            .if_then => {
                const condition = try self.createDummyCondition();
                const then_stmt = try self.ast_builder.createBlock();
                return try self.ast_builder.createIf(condition, then_stmt, null);
            },
            .if_then_else => {
                const condition = try self.createDummyCondition();
                const then_stmt = try self.ast_builder.createBlock();
                const else_stmt = try self.ast_builder.createBlock();
                return try self.ast_builder.createIf(condition, then_stmt, else_stmt);
            },
            .while_loop => {
                const condition = try self.createDummyCondition();
                const body = try self.ast_builder.createBlock();
                const while_node = try ASTNode.init(self.allocator, .while_stmt);
                try while_node.addChild(condition);
                try while_node.addChild(body);
                return while_node;
            },
            else => {
                return null;
            },
        }
    }

    /// 创建虚拟条件表达式
    fn createDummyCondition(self: *ControlStructureAnalyzer) !*ASTNode {
        return try self.ast_builder.createLiteral(.{ .bool_val = true }, .boolean);
    }

    /// 获取控制流图
    pub fn getCFG(self: *ControlStructureAnalyzer) *ControlFlowGraph {
        return &self.cfg;
    }

    /// 获取识别的控制结构
    pub fn getStructures(self: *ControlStructureAnalyzer) []const ControlStructure {
        return self.structures.items;
    }
};

// 测试
test "控制结构识别基础功能测试" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var analyzer = ControlStructureAnalyzer.init(allocator);
    defer analyzer.deinit();

    // 创建简单的指令序列（if语句）
    const instructions = [_]Instruction{
        .{ .opcode = 0x04, .operands = &[_]u8{}, .pc = 0 }, // iconst_1
        .{ .opcode = 0x99, .operands = &[_]u8{ 0, 6 }, .pc = 1 }, // ifeq +6
        .{ .opcode = 0x05, .operands = &[_]u8{}, .pc = 4 }, // iconst_2
        .{ .opcode = 0xb1, .operands = &[_]u8{}, .pc = 5 }, // return
        .{ .opcode = 0x06, .operands = &[_]u8{}, .pc = 7 }, // iconst_3
        .{ .opcode = 0xb1, .operands = &[_]u8{}, .pc = 8 }, // return
    };

    try analyzer.buildCFG(&instructions);
    try analyzer.analyzeControlStructures();

    const structures = analyzer.getStructures();
    try testing.expect(structures.len > 0);
}
