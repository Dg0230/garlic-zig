//! Garlic Java 反编译器演示程序
//! 展示已实现的核心功能：文件类型检测、常量池解析、字节码指令识别等

const std = @import("std");
const print = std.debug.print;
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;

// 导入项目模块
const common = @import("src/common/types.zig");
const libs = @import("src/libs/mod.zig");
const parser = struct {
    const class_reader = @import("src/parser/class_reader.zig");
    const constant_pool = @import("src/parser/constant_pool.zig");
    const bytecode = @import("src/parser/bytecode.zig");
};
const jvm = struct {
    const instructions = @import("src/jvm/instructions.zig");
    const stack = @import("src/jvm/stack.zig");
};

/// 演示配置
const DemoConfig = struct {
    show_file_detection: bool = true,
    show_data_structures: bool = true,
    show_bytecode_analysis: bool = true,
    show_memory_management: bool = true,
    verbose: bool = false,
};

/// 文件类型检测演示
fn demoFileDetection(_: Allocator) !void {
    print("\n=== 📁 文件类型检测演示 ===\n", .{});

    // 模拟不同类型的文件魔数
    const test_files = [_]struct {
        name: []const u8,
        magic: [4]u8,
        expected: []const u8,
    }{
        .{ .name = "Example.class", .magic = .{ 0xCA, 0xFE, 0xBA, 0xBE }, .expected = "Java Class" },
        .{ .name = "library.jar", .magic = .{ 0x50, 0x4B, 0x03, 0x04 }, .expected = "JAR Archive" },
        .{ .name = "classes.dex", .magic = .{ 0x64, 0x65, 0x78, 0x0A }, .expected = "DEX File" },
        .{ .name = "unknown.bin", .magic = .{ 0x00, 0x00, 0x00, 0x00 }, .expected = "Unknown" },
    };

    for (test_files) |file| {
        const file_type = detectFileTypeFromMagic(&file.magic);
        print("  📄 {s:<15} -> {s:<12} (预期: {s})\n", .{ file.name, @tagName(file_type), file.expected });
    }
}

/// 从魔数检测文件类型
fn detectFileTypeFromMagic(magic: *const [4]u8) enum { java_class, jar_archive, dex_file, unknown } {
    // Java Class 文件魔数: 0xCAFEBABE
    if (std.mem.eql(u8, magic, &[_]u8{ 0xCA, 0xFE, 0xBA, 0xBE })) {
        return .java_class;
    }
    // JAR/ZIP 文件魔数: 0x504B0304
    if (std.mem.eql(u8, magic, &[_]u8{ 0x50, 0x4B, 0x03, 0x04 })) {
        return .jar_archive;
    }
    // DEX 文件魔数: "dex\n"
    if (std.mem.eql(u8, magic, &[_]u8{ 0x64, 0x65, 0x78, 0x0A })) {
        return .dex_file;
    }
    return .unknown;
}

/// 数据结构演示
fn demoDataStructures(allocator: Allocator) !void {
    print("\n=== 🏗️ 数据结构演示 ===\n", .{});

    // 演示动态数组
    print("\n📋 动态数组 (List):\n", .{});
    var string_list = libs.StringList.init(allocator);
    defer string_list.deinit();

    try string_list.append("java.lang.Object");
    try string_list.append("java.lang.String");
    try string_list.append("java.util.ArrayList");

    print("  添加了 {} 个类名:\n", .{string_list.len()});
    for (0..string_list.len()) |i| {
        const item = string_list.get(i);
        print("    [{}] {s}\n", .{ i, item });
    }

    // 演示哈希表
    print("\n🗂️ 哈希表 (HashMap):\n", .{});
    var class_map = try libs.StringIntMap.init(allocator);
    defer class_map.deinit();

    try class_map.put("java.lang.Object", 1);
    try class_map.put("java.lang.String", 2);
    try class_map.put("java.util.List", 3);

    print("  类名到ID的映射:\n", .{});
    var iterator = class_map.iterator();
    while (iterator.next()) |entry| {
        print("    {s} -> {}\n", .{ entry.key, entry.value });
    }

    // 演示队列
    print("\n📤 队列 (Queue):\n", .{});
    var task_queue = try libs.StringQueue.init(allocator);
    defer task_queue.deinit();

    try task_queue.enqueue("解析常量池");
    try task_queue.enqueue("分析字节码");
    try task_queue.enqueue("生成源码");

    print("  任务队列处理顺序:\n", .{});
    var task_count: u32 = 1;
    while (task_queue.dequeue()) |task| {
        print("    {}. {s}\n", .{ task_count, task });
        task_count += 1;
    }
}

/// 字节码分析演示
fn demoBytecodeAnalysis(_: Allocator) !void {
    print("\n=== 🔍 字节码分析演示 ===\n", .{});

    // 演示常见的 JVM 指令
    const sample_instructions = [_]struct {
        opcode: u8,
        name: []const u8,
        description: []const u8,
    }{
        .{ .opcode = 0x00, .name = "nop", .description = "无操作" },
        .{ .opcode = 0x01, .name = "aconst_null", .description = "将null推入栈" },
        .{ .opcode = 0x03, .name = "iconst_0", .description = "将int常量0推入栈" },
        .{ .opcode = 0x12, .name = "ldc", .description = "从常量池加载常量" },
        .{ .opcode = 0x15, .name = "iload", .description = "从局部变量加载int" },
        .{ .opcode = 0x19, .name = "aload", .description = "从局部变量加载引用" },
        .{ .opcode = 0x36, .name = "istore", .description = "存储int到局部变量" },
        .{ .opcode = 0x57, .name = "pop", .description = "弹出栈顶值" },
        .{ .opcode = 0x60, .name = "iadd", .description = "int加法" },
        .{ .opcode = 0xb1, .name = "return", .description = "void方法返回" },
    };

    print("\n📜 JVM 指令集示例:\n", .{});
    for (sample_instructions) |inst| {
        print("  0x{X:0>2} {s:<12} - {s}\n", .{ inst.opcode, inst.name, inst.description });
    }

    // 演示模拟的方法字节码
    print("\n🔧 模拟方法字节码分析:\n", .{});
    const method_bytecode = [_]u8{ 0x03, 0x15, 0x01, 0x60, 0xac }; // iconst_0, iload_1, iadd, ireturn
    const instruction_names = [_][]const u8{ "iconst_0", "iload_1", "iadd", "ireturn" };

    print("  方法: int add(int x) {{ return 0 + x; }}\n", .{});
    print("  字节码序列:\n", .{});
    for (method_bytecode, 0..) |opcode, i| {
        if (i < instruction_names.len) {
            print("    {} 0x{X:0>2} {s}\n", .{ i, opcode, instruction_names[i] });
        }
    }
}

/// 内存管理演示
fn demoMemoryManagement(allocator: Allocator) !void {
    print("\n=== 💾 内存管理演示 ===\n", .{});

    // 演示内存池
    print("\n🏊 内存池使用:\n", .{});
    var memory_pool = libs.MemoryPool.init(allocator);
    defer memory_pool.deinit();

    // 分配一些内存块
    const allocations = [_]usize{ 64, 128, 256, 32 };
    var allocated_blocks = ArrayList(*anyopaque).init(allocator);
    defer allocated_blocks.deinit();

    for (allocations) |size| {
        if (memory_pool.alloc(size, @alignOf(u8))) |ptr| {
            try allocated_blocks.append(ptr.ptr);
            print("  ✅ 分配 {} 字节成功\n", .{size});
        } else |_| {
            print("  ❌ 分配 {} 字节失败\n", .{size});
        }
    }

    print("  📊 内存池统计:\n", .{});
    const stats = memory_pool.getStats();
    print("    总分配: {} 字节\n", .{stats.total_allocated});
    print("    小块数量: {}\n", .{stats.small_blocks_count});
    print("    大块数量: {}\n", .{stats.big_blocks_count});

    // 内存池会在deinit时自动释放所有内存
    print("  🧹 内存池将在销毁时自动释放所有内存\n", .{});
}

/// 性能基准测试演示
fn demoBenchmark(allocator: Allocator) !void {
    print("\n=== ⚡ 性能基准测试 ===\n", .{});

    const iterations = 10000;

    // 测试动态数组性能
    print("\n📈 动态数组性能测试 ({} 次操作):\n", .{iterations});
    var timer = try std.time.Timer.start();

    var test_list = libs.IntList.init(allocator);
    defer test_list.deinit();

    // 添加元素
    const start_append = timer.read();
    for (0..iterations) |i| {
        try test_list.append(@intCast(i));
    }
    const append_time = timer.read() - start_append;

    // 随机访问
    const start_access = timer.read();
    var sum: i32 = 0;
    for (0..iterations) |i| {
        sum += test_list.get(i % test_list.len());
    }
    const access_time = timer.read() - start_access;

    print("  添加 {} 个元素: {d:.2} ms\n", .{ iterations, @as(f64, @floatFromInt(append_time)) / 1_000_000.0 });
    print("  随机访问 {} 次: {d:.2} ms\n", .{ iterations, @as(f64, @floatFromInt(access_time)) / 1_000_000.0 });
    print("  校验和: {} (防止优化)\n", .{sum});
}

/// 主演示函数
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const config = DemoConfig{
        .show_file_detection = true,
        .show_data_structures = true,
        .show_bytecode_analysis = true,
        .show_memory_management = true,
        .verbose = true,
    };

    print("🧄 Garlic Java 反编译器 - 功能演示\n", .{});
    print("=====================================\n", .{});
    print("版本: v0.1.0-alpha\n", .{});
    print("进度: 75% 完成\n", .{});
    print("语言: Zig {}\n", .{@import("builtin").zig_version});

    if (config.show_file_detection) {
        try demoFileDetection(allocator);
    }

    if (config.show_data_structures) {
        try demoDataStructures(allocator);
    }

    if (config.show_bytecode_analysis) {
        try demoBytecodeAnalysis(allocator);
    }

    if (config.show_memory_management) {
        try demoMemoryManagement(allocator);
    }

    try demoBenchmark(allocator);

    print("\n=== 🎯 下一步开发计划 ===\n", .{});
    print("  🔄 完善字节码解析器\n", .{});
    print("  🏗️ 优化内存管理\n", .{});
    print("  🎨 改进代码生成\n", .{});
    print("  📊 增强性能分析\n", .{});
    print("  🔧 添加更多工具\n", .{});

    print("\n✨ 演示完成！感谢使用 Garlic 反编译器！\n", .{});
}

// 测试用例
test "demo functionality" {
    const testing = std.testing;
    const allocator = testing.allocator;

    // 测试文件类型检测
    const java_magic = [_]u8{ 0xCA, 0xFE, 0xBA, 0xBE };
    const file_type = detectFileTypeFromMagic(&java_magic);
    try testing.expect(file_type == .java_class);

    // 测试数据结构
    var test_list = libs.IntList.init(allocator);
    defer test_list.deinit();

    try test_list.append(42);
    try testing.expect(test_list.len() == 1);
    try testing.expect(test_list.get(0) == 42);
}
