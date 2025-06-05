const std = @import("std");
const print = std.debug.print;
const Allocator = std.mem.Allocator;

fn demoBytecodeAnalysis(allocator: Allocator) !void {
    print("\n=== 🔍 字节码分析演示 ===\n", .{});

    // 演示模拟的方法字节码
    print("\n🔧 模拟方法字节码分析:\n", .{});
    const method_bytecode = [_]u8{ 0x03, 0x15, 0x01, 0x60, 0xac }; // iconst_0, iload_1, iadd, ireturn
    const instruction_names = [_][]const u8{ "iconst_0", "iload_1", "iadd", "ireturn" };

    print("  方法: int add(int x) { return 0 + x; }\n", .{});
    print("  字节码序列:\n", .{});
    for (method_bytecode, 0..) |opcode, i| {
        if (i < instruction_names.len) {
            print("    {} 0x{X:0>2} {s}\n", .{ i, opcode, instruction_names[i] });
        }
    }
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    try demoBytecodeAnalysis(allocator);
    print("\n✨ 测试完成！\n", .{});
}
