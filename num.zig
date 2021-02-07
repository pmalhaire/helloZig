const std = @import("std");
const expect = @import("std").testing.expect;

const int: i8 = 8;

pub fn main() void {
    std.debug.print("Hello, {s} {d}!\n", .{"World", int});
}

test "if statement expression" {
    const a = true;
    var x: u16 = 0;
    x += if (a) 1 else 2;
    expect(x == 1);
}
