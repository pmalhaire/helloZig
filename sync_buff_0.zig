const std = @import("std");
const Allocator = std.mem.Allocator;

/// Buff structure
/// size the size of the buffer
/// addr the address of the undelying memory block
/// offset the first unused place in the buffer 0xffff means the buff is full
/// allocator the address of the us allocator
const Buff = struct {
    size:        u32,
    addr:        []u8,
    offset:      u32,
    allocator:   *Allocator,
};


/// init a buffer of the deisred size
fn init(size: u32, a: *Allocator) *Buff {
    const ptr = try a.alloc(u8, size);
    return *Buff {
        .size = size,
        .addr = ptr,
        .offset = 0,
        .allocator = a,
    };
}

/// close the given buffer and free it's memory
fn close(b :*Buff) void {

}

/// write c into our buffer
fn write(b :*Buff, c :u8) void {
    b.addr[b.offset] = c;
    b.*.offset += 1;
}

/// read c into our buffer
fn read(b :*Buff) u8 {
    b.offset -= 1;
    // fail if 0
    const c: u8 = b.addr[b.offset];
    return c;
}

pub fn main() !void {
    const alloc = std.heap.page_allocator;
    //defer arena.deinit();

    const buff = init( 10, alloc);
    write( buff, 'a');
    std.debug.print("ptr={c}\n", .{read(buff)});
}

