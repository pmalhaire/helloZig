const std = @import("std");
const Allocator = std.mem.Allocator;
const GPA = std.heap.GeneralPurposeAllocator;
const Error = std.mem.Allocator.Error;

// set io_mode
pub const io_mode = .evented;

/// Buff struct
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
fn write(b: *Buff, c: u8) !void {
    // todo add fail if more than size
    b.addr[b.offset] = c;
    b.*.offset += 1;
}

/// read c into our buffer
fn read(b: *Buff) !u8 {
    b.offset -= 1;
    // todo add fail if 0
    const c: u8 = b.addr[b.offset];
    return c;
}

pub fn main() !void {
    var gpa = GPA(.{}){};
    var alloc = &gpa.allocator;

    var buff = try init(3, alloc);
    defer close(buff);

    std.debug.print("writing 'a' to buff\n", .{});
    try write(buff, 'a');

    std.debug.print("reading one char from buff\n", .{});
    const c = read(buff);
    std.debug.print("char is : {c}\n", .{c});


    std.debug.print("writing 'a' then 'b' to buff\n", .{});
    // get frames without blocking
    var w1 = async write(buff, 'a');
    var w2 = async write(buff, 'b');

    // wait for frames
    try await w1;
    try await w2;
    std.debug.print("reading two char from buff\n", .{});
    // get frames
    var r1 = async read(buff);
    var r2 = async read(buff);
    // read async
    const d = try await r1;
    const e = try await r2;
    std.debug.print("chars are : {c} {c}\n", .{d, e});


}
