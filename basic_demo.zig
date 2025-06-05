//! Garlic Java Decompiler Demo
//! Basic functionality demonstration

const std = @import("std");
const print = std.debug.print;
const ArrayList = std.ArrayList;
const HashMap = std.HashMap;
const Allocator = std.mem.Allocator;

/// File type enumeration
const FileType = enum {
    java_class,
    jar_archive,
    dex_file,
    unknown,

    /// Get file type description
    pub fn description(self: FileType) []const u8 {
        return switch (self) {
            .java_class => "Java Class File",
            .jar_archive => "JAR Archive",
            .dex_file => "Android DEX File",
            .unknown => "Unknown File Type",
        };
    }
};

/// Detect file type from magic bytes
fn detectFileTypeFromMagic(magic: *const [4]u8) FileType {
    // Java Class file magic: 0xCAFEBABE
    if (std.mem.eql(u8, magic, &[_]u8{ 0xCA, 0xFE, 0xBA, 0xBE })) {
        return .java_class;
    }
    // JAR/ZIP file magic: 0x504B0304
    if (std.mem.eql(u8, magic, &[_]u8{ 0x50, 0x4B, 0x03, 0x04 })) {
        return .jar_archive;
    }
    // DEX file magic: "dex\n"
    if (std.mem.eql(u8, magic, &[_]u8{ 0x64, 0x65, 0x78, 0x0A })) {
        return .dex_file;
    }
    return .unknown;
}

/// JVM instruction information
const InstructionInfo = struct {
    opcode: u8,
    name: []const u8,
    description: []const u8,
};

/// File type detection demo
fn demoFileDetection() void {
    print("\n=== File Type Detection Demo ===\n", .{});

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
        print("  {s:<15} -> {s}\n", .{ file.name, file_type.description() });
    }
}

/// Data structures demo
fn demoDataStructures(allocator: Allocator) !void {
    print("\n=== Data Structures Demo ===\n", .{});

    // ArrayList demo
    print("\nArrayList Demo:\n", .{});
    var class_names = ArrayList([]const u8).init(allocator);
    defer class_names.deinit();

    try class_names.append("java.lang.Object");
    try class_names.append("java.lang.String");
    try class_names.append("java.util.ArrayList");
    try class_names.append("java.io.File");

    print("  Added {} class names:\n", .{class_names.items.len});
    for (class_names.items, 0..) |name, i| {
        print("    [{}] {s}\n", .{ i, name });
    }

    // HashMap demo
    print("\nHashMap Demo:\n", .{});
    var class_map = HashMap([]const u8, u32, std.hash_map.StringContext, std.hash_map.default_max_load_percentage).init(allocator);
    defer class_map.deinit();

    try class_map.put("java.lang.Object", 1);
    try class_map.put("java.lang.String", 2);
    try class_map.put("java.util.List", 3);
    try class_map.put("java.io.InputStream", 4);

    print("  Class name to ID mapping ({} entries):\n", .{class_map.count()});
    var iterator = class_map.iterator();
    while (iterator.next()) |entry| {
        print("    {s} -> {}\n", .{ entry.key_ptr.*, entry.value_ptr.* });
    }
}

/// Bytecode analysis demo
fn demoBytecodeAnalysis() void {
    print("\n=== Bytecode Analysis Demo ===\n", .{});

    const instructions = [_]InstructionInfo{
        .{ .opcode = 0x00, .name = "nop", .description = "No operation" },
        .{ .opcode = 0x01, .name = "aconst_null", .description = "Push null reference" },
        .{ .opcode = 0x03, .name = "iconst_0", .description = "Push int constant 0" },
        .{ .opcode = 0x12, .name = "ldc", .description = "Load constant from pool" },
        .{ .opcode = 0x15, .name = "iload", .description = "Load int from local variable" },
        .{ .opcode = 0x19, .name = "aload", .description = "Load reference from local variable" },
        .{ .opcode = 0x36, .name = "istore", .description = "Store int to local variable" },
        .{ .opcode = 0x57, .name = "pop", .description = "Pop top stack value" },
        .{ .opcode = 0x60, .name = "iadd", .description = "Integer addition" },
        .{ .opcode = 0xb1, .name = "return", .description = "Return from void method" },
    };

    print("\nJVM Instruction Set Examples ({} instructions):\n", .{instructions.len});
    for (instructions) |inst| {
        print("  0x{X:0>2} {s:<12} - {s}\n", .{ inst.opcode, inst.name, inst.description });
    }

    // Simulated method bytecode
    print("\nSimulated Method Bytecode Analysis:\n", .{});
    const method_bytecode = [_]u8{ 0x03, 0x15, 0x60, 0xac }; // iconst_0, iload_1, iadd, ireturn
    const instruction_names = [_][]const u8{ "iconst_0", "iload_1", "iadd", "ireturn" };

    print("  Method: int add(int x) {{ return 0 + x; }}\n", .{});
    print("  Bytecode sequence:\n", .{});
    for (method_bytecode, 0..) |opcode, i| {
        if (i < instruction_names.len) {
            print("    {} 0x{X:0>2} {s}\n", .{ i, opcode, instruction_names[i] });
        }
    }
}

/// Memory usage demo
fn demoMemoryStats(allocator: Allocator) !void {
    print("\n=== Memory Usage Demo ===\n", .{});

    var allocations = ArrayList(*anyopaque).init(allocator);
    defer {
        // Free all allocated memory
        for (allocations.items) |ptr| {
            allocator.free(@as([*]u8, @ptrCast(ptr))[0..64]);
        }
        allocations.deinit();
    }

    const allocation_sizes = [_]usize{ 64, 128, 256, 512, 1024 };

    print("\nMemory Allocation Test:\n", .{});
    for (allocation_sizes) |size| {
        const ptr = allocator.alloc(u8, size) catch |err| {
            print("  Failed to allocate {} bytes: {}\n", .{ size, err });
            continue;
        };
        try allocations.append(ptr.ptr);
        print("  Successfully allocated {} bytes\n", .{size});
    }

    print("  Total allocated blocks: {}\n", .{allocations.items.len});
}

/// Performance benchmark
fn demoBenchmark(allocator: Allocator) !void {
    print("\n=== Performance Benchmark ===\n", .{});

    const iterations = 10000;

    print("\nArrayList Performance Test ({} operations):\n", .{iterations});
    var timer = try std.time.Timer.start();

    var test_list = ArrayList(i32).init(allocator);
    defer test_list.deinit();

    // Append elements
    const start_append = timer.read();
    for (0..iterations) |i| {
        try test_list.append(@intCast(i));
    }
    const append_time = timer.read() - start_append;

    // Random access
    const start_access = timer.read();
    var sum: i64 = 0;
    for (0..iterations) |i| {
        sum += test_list.items[i % test_list.items.len];
    }
    const access_time = timer.read() - start_access;

    print("  Append {} elements: {d:.2} ms\n", .{ iterations, @as(f64, @floatFromInt(append_time)) / 1_000_000.0 });
    print("  Random access {} times: {d:.2} ms\n", .{ iterations, @as(f64, @floatFromInt(access_time)) / 1_000_000.0 });
    print("  Checksum: {} (prevent optimization)\n", .{sum});
}

/// Show project information
fn showProjectInfo() void {
    print("\n=== Project Information ===\n", .{});
    print("  Project: Garlic Java Decompiler\n", .{});
    print("  Language: Zig {}\n", .{@import("builtin").zig_version});
    print("  Stage: Alpha Version\n", .{});
    print("  Progress: 75%% Complete\n", .{});

    print("\nCompleted Features:\n", .{});
    const completed_features = [_][]const u8{
        "[x] Infrastructure modules (memory, data structures)",
        "[x] File type detection (Class/JAR/DEX)",
        "[x] Constant pool parsing framework",
        "[x] Bytecode instruction definitions",
        "[x] Basic parser structure",
    };

    for (completed_features) |feature| {
        print("    {s}\n", .{feature});
    }

    print("\nIn Progress Features:\n", .{});
    const in_progress_features = [_][]const u8{
        "[ ] Control flow analysis",
        "[ ] Expression building",
        "[ ] Type inference",
        "[ ] Source code generation",
    };

    for (in_progress_features) |feature| {
        print("    {s}\n", .{feature});
    }
}

/// Main demo function
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    print("Garlic Java Decompiler - Feature Demo\n", .{});
    print("====================================\n", .{});

    showProjectInfo();
    demoFileDetection();
    try demoDataStructures(allocator);
    demoBytecodeAnalysis();
    try demoMemoryStats(allocator);
    try demoBenchmark(allocator);

    print("\n=== Next Development Steps ===\n", .{});
    const next_steps = [_][]const u8{
        "[ ] Complete bytecode parser",
        "[ ] Implement control flow analysis",
        "[ ] Add Java source code generation",
        "[ ] Increase test coverage",
        "[ ] Support JAR file processing",
        "[ ] Optimize output formatting",
    };

    for (next_steps) |step| {
        print("  {s}\n", .{step});
    }

    print("\nDemo completed! Thank you for using Garlic Decompiler!\n", .{});
}

// Test cases
test "file type detection" {
    const testing = std.testing;

    // Test Java Class file detection
    const java_magic = [_]u8{ 0xCA, 0xFE, 0xBA, 0xBE };
    const java_type = detectFileTypeFromMagic(&java_magic);
    try testing.expect(java_type == .java_class);

    // Test JAR file detection
    const jar_magic = [_]u8{ 0x50, 0x4B, 0x03, 0x04 };
    const jar_type = detectFileTypeFromMagic(&jar_magic);
    try testing.expect(jar_type == .jar_archive);

    // Test DEX file detection
    const dex_magic = [_]u8{ 0x64, 0x65, 0x78, 0x0A };
    const dex_type = detectFileTypeFromMagic(&dex_magic);
    try testing.expect(dex_type == .dex_file);

    // Test unknown file type
    const unknown_magic = [_]u8{ 0x00, 0x00, 0x00, 0x00 };
    const unknown_type = detectFileTypeFromMagic(&unknown_magic);
    try testing.expect(unknown_type == .unknown);
}

test "data structures" {
    const testing = std.testing;
    const allocator = testing.allocator;

    // Test ArrayList
    var list = ArrayList(i32).init(allocator);
    defer list.deinit();

    try list.append(42);
    try list.append(84);

    try testing.expect(list.items.len == 2);
    try testing.expect(list.items[0] == 42);
    try testing.expect(list.items[1] == 84);

    // Test HashMap
    var map = HashMap([]const u8, i32, std.hash_map.StringContext, std.hash_map.default_max_load_percentage).init(allocator);
    defer map.deinit();

    try map.put("test", 123);
    const value = map.get("test");
    try testing.expect(value != null);
    try testing.expect(value.? == 123);
}
