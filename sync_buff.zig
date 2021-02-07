const std = @import("std");
const Allocator = std.mem.Allocator;
const GPA = std.heap.GeneralPurposeAllocator;
const Error = std.mem.Allocator.Error;

/// Buff structure
/// size the size of the buffer
/// addr the address of the undelying memory block
/// offset the first unused place in the buffer 0xffff means the buff is full
/// allocator the address of the us allocator
const Buff = struct {
    size: u32,
    addr: []u8,
    offset: u32,
    allocator: *Allocator,
};

/// init a buffer of the deisred size
fn init(size: u32, a: *Allocator) Error!*Buff {

    var ptr = try a.alloc(u8, size);
    return &Buff{
        .size = size,
        .addr = ptr,
        .offset = 0,
        .allocator = a,
    };
}

/// close the given buffer and free it's memory
fn close(b: *Buff) void {
    b.allocator.free(b.addr);
}

/// write c into our buffer
fn write(b: *Buff, c: u8) void {
    b.addr[b.offset] = c;
    b.*.offset += 1;
}

/// read c into our buffer
fn read(b: *Buff) u8 {
    b.offset -= 1;
    // fail if 0
    const c: u8 = b.addr[b.offset];
    return c;
}

pub fn main() !void {
    var gpa = GPA(.{}){};
    var alloc = &gpa.allocator;

    var buff = try init(10, alloc);
    defer close(buff);

    std.debug.print("writing 'a' to buff\n", .{});
    write(buff, 'a');


    std.debug.print("reading one char from buff\n", .{});
    const c = read(buff);
    std.debug.print("char is : {c}\n", .{c});
}
