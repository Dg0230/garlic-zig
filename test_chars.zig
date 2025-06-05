const std = @import("std");
const print = std.debug.print;

pub fn main() !void {
    print("Test 1\n", .{});
    print("Test with emoji: 🔍\n", .{});
    print("Test with chinese: 字节码\n", .{});
    print("Test with braces: { }\n", .{});
    print("Test with format: {}\n", .{42});
}
