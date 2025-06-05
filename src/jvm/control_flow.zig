//! JVM 控制流分析器
//! 分析字节码的控制流结构，构建控制流图

const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const HashMap = std.HashMap;
const instructions = @import("instructions.zig");
const Opcode = instructions.Opcode;

/// 基本块类型
pub const BasicBlockType = enum {
    normal, // 普通基本块
    entry, // 入口块
    exit, // 出口块
    exception, // 异常处理块
};

/// 基本块
pub const BasicBlock = struct {
    id: u32,
    block_type: BasicBlockType,
    start_pc: u32,
    end_pc: u32,
    instructions: ArrayList(Instruction),
    predecessors: ArrayList(u32), // 前驱基本块ID列表
    successors: ArrayList(u32), // 后继基本块ID列表
    exception_handlers: ArrayList(u32), // 异常处理器ID列表
    dominated_by: ?u32, // 支配者基本块ID
    dominates: ArrayList(u32), // 被支配的基本块ID列表
    allocator: Allocator,

    /// 创建新的基本块
    pub fn init(allocator: Allocator, id: u32, block_type: BasicBlockType, start_pc: u32) BasicBlock {
        return BasicBlock{
            .id = id,
            .block_type = block_type,
            .start_pc = start_pc,
            .end_pc = start_pc,
            .instructions = ArrayList(Instruction).init(allocator),
            .predecessors = ArrayList(u32).init(allocator),
            .successors = ArrayList(u32).init(allocator),
            .exception_handlers = ArrayList(u32).init(allocator),
            .dominated_by = null,
            .dominates = ArrayList(u32).init(allocator),
            .allocator = allocator,
        };
    }

    /// 释放基本块资源
    pub fn deinit(self: *BasicBlock) void {
        self.instructions.deinit();
        self.predecessors.deinit();
        self.successors.deinit();
        self.exception_handlers.deinit();
        self.dominates.deinit();
    }

    /// 添加指令到基本块
    pub fn addInstruction(self: *BasicBlock, instruction: Instruction) !void {
        try self.instructions.append(instruction);
        self.end_pc = instruction.pc + instruction.length;
    }

    /// 添加后继基本块
    pub fn addSuccessor(self: *BasicBlock, successor_id: u32) !void {
        // 避免重复添加
        for (self.successors.items) |id| {
            if (id == successor_id) return;
        }
        try self.successors.append(successor_id);
    }

    /// 添加前驱基本块
    pub fn addPredecessor(self: *BasicBlock, predecessor_id: u32) !void {
        // 避免重复添加
        for (self.predecessors.items) |id| {
            if (id == predecessor_id) return;
        }
        try self.predecessors.append(predecessor_id);
    }

    /// 添加异常处理器
    pub fn addExceptionHandler(self: *BasicBlock, handler_id: u32) !void {
        try self.exception_handlers.append(handler_id);
    }

    /// 检查是否为分支块
    pub fn isBranchBlock(self: *const BasicBlock) bool {
        return self.successors.items.len > 1;
    }

    /// 检查是否为合并块
    pub fn isMergeBlock(self: *const BasicBlock) bool {
        return self.predecessors.items.len > 1;
    }

    /// 获取最后一条指令
    pub fn getLastInstruction(self: *const BasicBlock) ?Instruction {
        if (self.instructions.items.len == 0) return null;
        return self.instructions.items[self.instructions.items.len - 1];
    }
};

/// 指令信息
pub const Instruction = struct {
    pc: u32,
    opcode: Opcode,
    operands: []const u8,
    length: u8,

    /// 创建指令
    pub fn init(pc: u32, opcode: Opcode, operands: []const u8) Instruction {
        const info = instructions.getInstructionInfo(opcode);
        return Instruction{
            .pc = pc,
            .opcode = opcode,
            .operands = operands,
            .length = 1 + info.operand_count,
        };
    }
};

/// 异常处理器信息
pub const ExceptionHandler = struct {
    start_pc: u32,
    end_pc: u32,
    handler_pc: u32,
    catch_type: ?u16, // null表示catch所有异常
};

/// 控制流图
pub const ControlFlowGraph = struct {
    blocks: HashMap(u32, BasicBlock, std.hash_map.AutoContext(u32), std.hash_map.default_max_load_percentage),
    entry_block_id: u32,
    exit_block_ids: ArrayList(u32),
    exception_handlers: ArrayList(ExceptionHandler),
    next_block_id: u32,
    allocator: Allocator,

    /// 创建新的控制流图
    pub fn init(allocator: Allocator) ControlFlowGraph {
        return ControlFlowGraph{
            .blocks = HashMap(u32, BasicBlock, std.hash_map.AutoContext(u32), std.hash_map.default_max_load_percentage).init(allocator),
            .entry_block_id = 0,
            .exit_block_ids = ArrayList(u32).init(allocator),
            .exception_handlers = ArrayList(ExceptionHandler).init(allocator),
            .next_block_id = 0,
            .allocator = allocator,
        };
    }

    /// 释放控制流图资源
    pub fn deinit(self: *ControlFlowGraph) void {
        var iterator = self.blocks.iterator();
        while (iterator.next()) |entry| {
            entry.value_ptr.deinit();
        }
        self.blocks.deinit();
        self.exit_block_ids.deinit();
        self.exception_handlers.deinit();
    }

    /// 创建新的基本块
    pub fn createBlock(self: *ControlFlowGraph, block_type: BasicBlockType, start_pc: u32) !u32 {
        const block_id = self.next_block_id;
        self.next_block_id += 1;

        const block = BasicBlock.init(self.allocator, block_id, block_type, start_pc);
        try self.blocks.put(block_id, block);

        if (block_type == .entry) {
            self.entry_block_id = block_id;
        } else if (block_type == .exit) {
            try self.exit_block_ids.append(block_id);
        }

        return block_id;
    }

    /// 获取基本块
    pub fn getBlock(self: *ControlFlowGraph, block_id: u32) ?*BasicBlock {
        return self.blocks.getPtr(block_id);
    }

    /// 添加边（从source到target）
    pub fn addEdge(self: *ControlFlowGraph, source_id: u32, target_id: u32) !void {
        if (self.getBlock(source_id)) |source_block| {
            try source_block.addSuccessor(target_id);
        }

        if (self.getBlock(target_id)) |target_block| {
            try target_block.addPredecessor(source_id);
        }
    }

    /// 添加异常处理器
    pub fn addExceptionHandler(self: *ControlFlowGraph, handler: ExceptionHandler) !void {
        try self.exception_handlers.append(handler);
    }

    /// 获取所有基本块ID
    pub fn getAllBlockIds(self: *const ControlFlowGraph, allocator: Allocator) ![]u32 {
        var ids = ArrayList(u32).init(allocator);
        defer ids.deinit();

        var iterator = self.blocks.iterator();
        while (iterator.next()) |entry| {
            try ids.append(entry.key_ptr.*);
        }

        return ids.toOwnedSlice();
    }

    /// 执行深度优先搜索
    pub fn depthFirstSearch(self: *const ControlFlowGraph, allocator: Allocator, start_block_id: u32) ![]u32 {
        var visited = HashMap(u32, bool).init(allocator);
        defer visited.deinit();

        var result = ArrayList(u32).init(allocator);
        defer result.deinit();

        try self.dfsRecursive(start_block_id, &visited, &result);

        return result.toOwnedSlice();
    }

    /// DFS递归实现
    fn dfsRecursive(self: *const ControlFlowGraph, block_id: u32, visited: *HashMap(u32, bool), result: *ArrayList(u32)) !void {
        if (visited.contains(block_id)) return;

        try visited.put(block_id, true);
        try result.append(block_id);

        if (self.blocks.get(block_id)) |block| {
            for (block.successors.items) |successor_id| {
                try self.dfsRecursive(successor_id, visited, result);
            }
        }
    }

    /// 计算支配关系
    pub fn computeDominators(self: *ControlFlowGraph) !void {
        // 简化的支配者计算算法
        const all_blocks = try self.getAllBlockIds(self.allocator);
        defer self.allocator.free(all_blocks);

        // 初始化：入口块支配自己，其他块被所有块支配
        for (all_blocks) |block_id| {
            if (self.getBlock(block_id)) |block| {
                if (block.block_type == .entry) {
                    block.dominated_by = block_id;
                } else {
                    // 暂时设置为未知
                    block.dominated_by = null;
                }
            }
        }

        // 迭代计算支配关系
        var changed = true;
        while (changed) {
            changed = false;

            for (all_blocks) |block_id| {
                if (self.getBlock(block_id)) |block| {
                    if (block.block_type == .entry) continue;

                    // 找到所有前驱的共同支配者
                    var common_dominator: ?u32 = null;

                    for (block.predecessors.items) |pred_id| {
                        if (self.getBlock(pred_id)) |pred_block| {
                            if (pred_block.dominated_by) |dom| {
                                if (common_dominator == null) {
                                    common_dominator = dom;
                                } else {
                                    // 简化：选择ID较小的作为支配者
                                    if (dom < common_dominator.?) {
                                        common_dominator = dom;
                                    }
                                }
                            }
                        }
                    }

                    if (common_dominator != null and block.dominated_by != common_dominator) {
                        block.dominated_by = common_dominator;
                        changed = true;
                    }
                }
            }
        }

        // 构建支配关系
        for (all_blocks) |block_id| {
            if (self.getBlock(block_id)) |block| {
                if (block.dominated_by) |dominator_id| {
                    if (dominator_id != block_id) { // 不包括自支配
                        if (self.getBlock(dominator_id)) |dominator_block| {
                            try dominator_block.dominates.append(block_id);
                        }
                    }
                }
            }
        }
    }
};

/// 控制流分析器
pub const ControlFlowAnalyzer = struct {
    allocator: Allocator,

    /// 创建控制流分析器
    pub fn init(allocator: Allocator) ControlFlowAnalyzer {
        return ControlFlowAnalyzer{
            .allocator = allocator,
        };
    }

    /// 分析字节码构建控制流图
    pub fn analyze(self: *ControlFlowAnalyzer, bytecode: []const u8, exception_handlers: []const ExceptionHandler) !ControlFlowGraph {
        var cfg = ControlFlowGraph.init(self.allocator);

        // 第一步：识别基本块边界
        var block_starts = HashMap(u32, bool, std.hash_map.AutoContext(u32), std.hash_map.default_max_load_percentage).init(self.allocator);
        defer block_starts.deinit();

        try self.identifyBlockBoundaries(bytecode, exception_handlers, &block_starts);

        // 第二步：创建基本块
        try self.createBasicBlocks(bytecode, &block_starts, &cfg);

        // 第三步：添加异常处理器
        for (exception_handlers) |handler| {
            try cfg.addExceptionHandler(handler);
        }

        // 第四步：构建控制流边
        try self.buildControlFlowEdges(bytecode, &cfg);

        // 第五步：计算支配关系
        try cfg.computeDominators();

        return cfg;
    }

    /// 识别基本块边界
    fn identifyBlockBoundaries(self: *ControlFlowAnalyzer, bytecode: []const u8, exception_handlers: []const ExceptionHandler, block_starts: *HashMap(u32, bool, std.hash_map.AutoContext(u32), std.hash_map.default_max_load_percentage)) !void {
        _ = self;

        // 方法入口是基本块开始
        try block_starts.put(0, true);

        var pc: u32 = 0;
        while (pc < bytecode.len) {
            const opcode = @as(Opcode, @enumFromInt(bytecode[pc]));
            const info = instructions.getInstructionInfo(opcode);

            // 分支指令的目标是基本块开始
            if (instructions.isBranchInstruction(opcode)) {
                if (opcode == .goto or opcode == .goto_w) {
                    // 无条件跳转目标
                    const target = if (opcode == .goto)
                        pc + @as(i16, @bitCast(std.mem.readInt(u16, bytecode[pc + 1 .. pc + 3], .big)))
                    else
                        pc + @as(i32, @bitCast(std.mem.readInt(u32, bytecode[pc + 1 .. pc + 5], .big)));
                    try block_starts.put(@intCast(target), true);
                } else if (opcode == .tableswitch or opcode == .lookupswitch) {
                    // switch语句处理（简化）
                    // 这里需要解析switch表，暂时跳过
                } else {
                    // 条件分支指令
                    const offset = std.mem.readInt(i16, bytecode[pc + 1 .. pc + 3], .big);
                    const target = @as(i32, @intCast(pc)) + offset;
                    try block_starts.put(@intCast(target), true);

                    // 分支指令的下一条指令也是基本块开始
                    const next_pc = pc + info.operand_count + 1;
                    if (next_pc < bytecode.len) {
                        try block_starts.put(next_pc, true);
                    }
                }
            }

            // 返回指令后的指令是基本块开始
            if (instructions.isReturnInstruction(opcode)) {
                const next_pc = pc + info.operand_count + 1;
                if (next_pc < bytecode.len) {
                    try block_starts.put(next_pc, true);
                }
            }

            pc += info.operand_count + 1;
        }

        // 异常处理器的开始和结束位置是基本块边界
        for (exception_handlers) |handler| {
            try block_starts.put(handler.start_pc, true);
            try block_starts.put(handler.end_pc, true);
            try block_starts.put(handler.handler_pc, true);
        }
    }

    /// 创建基本块
    fn createBasicBlocks(self: *ControlFlowAnalyzer, bytecode: []const u8, block_starts: *HashMap(u32, bool, std.hash_map.AutoContext(u32), std.hash_map.default_max_load_percentage), cfg: *ControlFlowGraph) !void {
        var starts = ArrayList(u32).init(self.allocator);
        defer starts.deinit();

        // 收集所有基本块开始位置
        var iterator = block_starts.iterator();
        while (iterator.next()) |entry| {
            try starts.append(entry.key_ptr.*);
        }

        // 排序
        std.mem.sort(u32, starts.items, {}, std.sort.asc(u32));

        // 创建基本块
        for (starts.items, 0..) |start_pc, i| {
            const block_type: BasicBlockType = if (start_pc == 0) .entry else .normal;
            const block_id = try cfg.createBlock(block_type, start_pc);

            if (cfg.getBlock(block_id)) |block| {
                // 确定基本块的结束位置
                const end_pc = if (i + 1 < starts.items.len) starts.items[i + 1] else @as(u32, @intCast(bytecode.len));

                // 添加指令到基本块
                var pc = start_pc;
                while (pc < end_pc and pc < bytecode.len) {
                    const opcode = @as(Opcode, @enumFromInt(bytecode[pc]));
                    const info = instructions.getInstructionInfo(opcode);

                    const operand_start = pc + 1;
                    const operand_end = operand_start + info.operand_count;
                    const operands = if (operand_end <= bytecode.len) bytecode[operand_start..operand_end] else &[_]u8{};

                    const instruction = Instruction.init(pc, opcode, operands);
                    try block.addInstruction(instruction);

                    pc += info.operand_count + 1;

                    // 如果遇到返回指令，标记为出口块
                    if (instructions.isReturnInstruction(opcode)) {
                        block.block_type = .exit;
                        try cfg.exit_block_ids.append(block_id);
                        break;
                    }
                }
            }
        }
    }

    /// 构建控制流边
    fn buildControlFlowEdges(self: *ControlFlowAnalyzer, bytecode: []const u8, cfg: *ControlFlowGraph) !void {
        _ = self;
        _ = bytecode;

        // 简化实现：遍历所有基本块，根据最后一条指令添加边
        var iterator = cfg.blocks.iterator();
        while (iterator.next()) |entry| {
            const block = entry.value_ptr;

            if (block.getLastInstruction()) |last_inst| {
                if (instructions.isBranchInstruction(last_inst.opcode)) {
                    // 处理分支指令（简化实现）
                    // 这里需要根据具体的分支指令类型添加相应的边
                    // 暂时跳过详细实现
                } else if (!instructions.isReturnInstruction(last_inst.opcode)) {
                    // 非分支非返回指令，添加到下一个基本块的边
                    const next_pc = last_inst.pc + last_inst.length;

                    // 查找下一个基本块
                    var next_iterator = cfg.blocks.iterator();
                    while (next_iterator.next()) |next_entry| {
                        const next_block = next_entry.value_ptr;
                        if (next_block.start_pc == next_pc) {
                            try cfg.addEdge(block.id, next_block.id);
                            break;
                        }
                    }
                }
            }
        }
    }
};

test "control flow graph creation" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var cfg = ControlFlowGraph.init(allocator);
    defer cfg.deinit();

    // 创建基本块
    const entry_id = try cfg.createBlock(.entry, 0);
    const block1_id = try cfg.createBlock(.normal, 10);
    const exit_id = try cfg.createBlock(.exit, 20);

    // 添加边
    try cfg.addEdge(entry_id, block1_id);
    try cfg.addEdge(block1_id, exit_id);

    // 验证结构
    try testing.expect(cfg.entry_block_id == entry_id);
    try testing.expect(cfg.exit_block_ids.items.len == 1);
    try testing.expect(cfg.exit_block_ids.items[0] == exit_id);

    // 验证边
    const entry_block = cfg.getBlock(entry_id).?;
    try testing.expect(entry_block.successors.items.len == 1);
    try testing.expect(entry_block.successors.items[0] == block1_id);

    const block1 = cfg.getBlock(block1_id).?;
    try testing.expect(block1.predecessors.items.len == 1);
    try testing.expect(block1.predecessors.items[0] == entry_id);
}

test "basic block operations" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var block = BasicBlock.init(allocator, 0, .normal, 0);
    defer block.deinit();

    // 添加指令
    const inst1 = Instruction.init(0, .iconst_1, &[_]u8{});
    const inst2 = Instruction.init(1, .istore_0, &[_]u8{});

    try block.addInstruction(inst1);
    try block.addInstruction(inst2);

    try testing.expect(block.instructions.items.len == 2);
    try testing.expect(block.end_pc == 2);

    // 测试后继和前驱
    try block.addSuccessor(1);
    try block.addPredecessor(2);

    try testing.expect(block.successors.items.len == 1);
    try testing.expect(block.predecessors.items.len == 1);
}
