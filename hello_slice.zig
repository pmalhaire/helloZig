const std = @import("std");

pub fn main() void {
    // write a slice
    const slice: []const u8 = "hello slice";
    std.debug.print("slice {s}\n", .{slice});
    const array: [11]u8 = "hello array".*;
    std.debug.print("array {s}\n", .{array});
}
