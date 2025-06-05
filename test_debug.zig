const std = @import("std");
const print = std.debug.print;

pub fn main() !void {
    print("Test 1\n", .{});
    print("Test 2: {}\n", .{42});
    print("Test 3: 0x{X:0>2}\n", .{255});
    print("Test 4: {s}\n", .{"hello"});
    print("Test 5: {} 0x{X:0>2} {s}\n", .{ 1, 255, "test" });
}
