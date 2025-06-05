//! Garlic Java 反编译器简化演示程序
//! 展示核心功能：文件类型检测、基础数据结构等

const std = @import("std");
const print = std.debug.print;
const ArrayList = std.ArrayList;
const HashMap = std.HashMap;
const Allocator = std.mem.Allocator;

/// 文件类型枚举
const FileType = enum {
    java_class,
    jar_archive,
    dex_file,
    unknown,

    /// 获取文件类型的描述
    pub fn description(self: FileType) []const u8 {
        return switch (self) {
            .java_class => "Java Class 文件",
            .jar_archive => "JAR 归档文件",
            .dex_file => "Android DEX 文件",
            .unknown => "未知文件类型",
        };
    }
};

/// 从魔数检测文件类型
fn detectFileTypeFromMagic(magic: *const [4]u8) FileType {
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

/// JVM 指令信息
const InstructionInfo = struct {
    opcode: u8,
    name: []const u8,
    description: []const u8,
};

/// 文件类型检测演示
fn demoFileDetection() void {
    print("\n=== 📁 文件类型检测演示 ===\n", .{});

    const test_files = [_]struct {
        name: []const u8,
        magic: [4]u8,
    }{
        .{ .name = "Example.class", .magic = .{ 0xCA, 0xFE, 0xBA, 0xBE } },
        .{ .name = "library.jar", .magic = .{ 0x50, 0x4B, 0x03, 0x04 } },
        .{ .name = "classes.dex", .magic = .{ 0x64, 0x65, 0x78, 0x0A } },
        .{ .name = "unknown.bin", .magic = .{ 0x00, 0x00, 0x00, 0x00 } },
    };

    for (test_files) |file| {
        const file_type = detectFileTypeFromMagic(&file.magic);
        print("  📄 {s:<15} -> {s}\n", .{ file.name, file_type.description() });
    }
}

/// 数据结构演示
fn demoDataStructures(allocator: Allocator) !void {
    print("\n=== 🏗️ 数据结构演示 ===\n", .{});

    // 演示动态数组
    print("\n📋 动态数组 (ArrayList):\n", .{});
    var class_names = ArrayList([]const u8).init(allocator);
    defer class_names.deinit();

    try class_names.append("java.lang.Object");
    try class_names.append("java.lang.String");
    try class_names.append("java.util.ArrayList");
    try class_names.append("java.io.File");

    print("  添加了 {} 个类名:\n", .{class_names.items.len});
    for (class_names.items, 0..) |name, i| {
        print("    [{}] {s}\n", .{ i, name });
    }

    // 演示哈希表
    print("\n🗂️ 哈希表 (HashMap):\n", .{});
    var class_map = HashMap([]const u8, u32, std.hash_map.StringContext, std.hash_map.default_max_load_percentage).init(allocator);
    defer class_map.deinit();

    try class_map.put("java.lang.Object", 1);
    try class_map.put("java.lang.String", 2);
    try class_map.put("java.util.List", 3);
    try class_map.put("java.io.InputStream", 4);

    print("  类名到ID的映射 ({} 个条目):\n", .{class_map.count()});
    var iterator = class_map.iterator();
    while (iterator.next()) |entry| {
        print("    {s} -> {}\n", .{ entry.key_ptr.*, entry.value_ptr.* });
    }
}

/// 字节码分析演示
fn demoBytecodeAnalysis() void {
    print("\n=== 🔍 字节码分析演示 ===\n", .{});

    const instructions = [_]InstructionInfo{
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

    print("\n📜 JVM 指令集示例 ({} 条指令):\n", .{instructions.len});
    for (instructions) |inst| {
        print("  0x{X:0>2} {s:<12} - {s}\n", .{ inst.opcode, inst.name, inst.description });
    }

    // 演示模拟的方法字节码
    print("\n🔧 模拟方法字节码分析:\n", .{});
    const method_bytecode = [_]u8{ 0x03, 0x15, 0x60, 0xac }; // iconst_0, iload_1, iadd, ireturn
    const instruction_names = [_][]const u8{ "iconst_0", "iload_1", "iadd", "ireturn" };

    print("  方法: int add(int x) {{ return 0 + x; }}\n", .{});
    print("  字节码序列:\n", .{});
    for (method_bytecode, 0..) |opcode, i| {
        if (i < instruction_names.len) {
            print("    {} 0x{X:0>2} {s}\n", .{ i, opcode, instruction_names[i] });
        }
    }
}

/// 内存使用统计
fn demoMemoryStats(allocator: Allocator) !void {
    print("\n=== 💾 内存使用演示 ===\n", .{});

    // 分配一些内存来演示
    var allocations = ArrayList([]u8).init(allocator);
    defer {
        // 释放所有分配的内存
        for (allocations.items) |slice| {
            allocator.free(slice);
        }
        allocations.deinit();
    }

    const allocation_sizes = [_]usize{ 64, 128, 256, 512, 1024 };

    print("\n🏊 内存分配测试:\n", .{});
    for (allocation_sizes) |size| {
        const ptr = allocator.alloc(u8, size) catch |err| {
            print("  ❌ 分配 {} 字节失败: {}\n", .{ size, err });
            continue;
        };
        try allocations.append(ptr);
        print("  ✅ 成功分配 {} 字节\n", .{size});
    }

    print("  📊 总共分配了 {} 个内存块\n", .{allocations.items.len});
}

/// 性能基准测试
fn demoBenchmark(allocator: Allocator) !void {
    print("\n=== ⚡ 性能基准测试 ===\n", .{});

    const iterations = 10000;

    print("\n📈 动态数组性能测试 ({} 次操作):\n", .{iterations});
    var timer = try std.time.Timer.start();

    var test_list = ArrayList(i32).init(allocator);
    defer test_list.deinit();

    // 添加元素
    const start_append = timer.read();
    for (0..iterations) |i| {
        try test_list.append(@intCast(i));
    }
    const append_time = timer.read() - start_append;

    // 随机访问
    const start_access = timer.read();
    var sum: i64 = 0;
    for (0..iterations) |i| {
        sum += test_list.items[i % test_list.items.len];
    }
    const access_time = timer.read() - start_access;

    print("  添加 {} 个元素: {d:.2} ms\n", .{ iterations, @as(f64, @floatFromInt(append_time)) / 1_000_000.0 });
    print("  随机访问 {} 次: {d:.2} ms\n", .{ iterations, @as(f64, @floatFromInt(access_time)) / 1_000_000.0 });
    print("  校验和: {} (防止优化)\n", .{sum});
}

/// 项目信息展示
fn showProjectInfo() void {
    print("\n=== 📋 项目信息 ===\n", .{});
    print("  项目名称: Garlic Java 反编译器\n", .{});
    print("  实现语言: Zig {}\n", .{@import("builtin").zig_version});
    print("  开发阶段: Alpha 版本\n", .{});
    print("  整体进度: 75% 完成\n", .{});

    print("\n🎯 已完成功能:\n", .{});
    const completed_features = [_][]const u8{
        "✅ 基础设施模块 (内存管理、数据结构)",
        "✅ 文件类型检测 (Class/JAR/DEX)",
        "✅ 常量池解析框架",
        "✅ 字节码指令定义",
        "✅ 基础解析器结构",
    };

    for (completed_features) |feature| {
        print("    {s}\n", .{feature});
    }

    print("\n🔄 开发中功能:\n", .{});
    const in_progress_features = [_][]const u8{
        "🔧 控制流分析",
        "🔧 表达式构建",
        "🔧 类型推断",
        "🔧 源码生成",
    };

    for (in_progress_features) |feature| {
        print("    {s}\n", .{feature});
    }
}

/// 主演示函数
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    print("🧄 Garlic Java 反编译器 - 功能演示\n", .{});
    print("=====================================\n", .{});

    showProjectInfo();
    demoFileDetection();
    try demoDataStructures(allocator);
    demoBytecodeAnalysis();
    try demoMemoryStats(allocator);
    try demoBenchmark(allocator);

    print("\n=== 🎯 下一步开发计划 ===\n", .{});
    const next_steps = [_][]const u8{
        "🔄 完善字节码解析器",
        "🏗️ 实现控制流分析",
        "📝 添加 Java 源码生成",
        "🧪 增加更多测试用例",
        "📦 支持 JAR 文件处理",
        "🎨 优化输出格式",
    };

    for (next_steps) |step| {
        print("  {s}\n", .{step});
    }

    print("\n✨ 演示完成！感谢使用 Garlic 反编译器！\n", .{});
}

// 测试用例
test "file type detection" {
    const testing = std.testing;

    // 测试 Java Class 文件检测
    const java_magic = [_]u8{ 0xCA, 0xFE, 0xBA, 0xBE };
    const java_type = detectFileTypeFromMagic(&java_magic);
    try testing.expect(java_type == .java_class);

    // 测试 JAR 文件检测
    const jar_magic = [_]u8{ 0x50, 0x4B, 0x03, 0x04 };
    const jar_type = detectFileTypeFromMagic(&jar_magic);
    try testing.expect(jar_type == .jar_archive);

    // 测试 DEX 文件检测
    const dex_magic = [_]u8{ 0x64, 0x65, 0x78, 0x0A };
    const dex_type = detectFileTypeFromMagic(&dex_magic);
    try testing.expect(dex_type == .dex_file);

    // 测试未知文件类型
    const unknown_magic = [_]u8{ 0x00, 0x00, 0x00, 0x00 };
    const unknown_type = detectFileTypeFromMagic(&unknown_magic);
    try testing.expect(unknown_type == .unknown);
}

test "data structures" {
    const testing = std.testing;
    const allocator = testing.allocator;

    // 测试动态数组
    var list = ArrayList(i32).init(allocator);
    defer list.deinit();

    try list.append(42);
    try list.append(84);

    try testing.expect(list.items.len == 2);
    try testing.expect(list.items[0] == 42);
    try testing.expect(list.items[1] == 84);

    // 测试哈希表
    var map = HashMap([]const u8, i32, std.hash_map.StringContext, std.hash_map.default_max_load_percentage).init(allocator);
    defer map.deinit();

    try map.put("test", 123);
    const value = map.get("test");
    try testing.expect(value != null);
    try testing.expect(value.? == 123);
}
