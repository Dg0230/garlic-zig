const std = @import("std");
const print = std.debug.print;

pub fn main() !void {
    print("Test without braces\n", .{});
    print("Test with escaped braces: {{}}\n", .{});
    print("Test with single brace: {\n", .{});
}
