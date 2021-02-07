const std = @import("std");
const Allocator = std.mem.Allocator;
const Gpa = std.heap.GeneralPurposeAllocator;

test "try to allocate memory" {
    // create a general pupose allocator
    var gpa = Gpa(.{ .enable_memory_limit = true }){};
    // get a reference the instance of the allocator
    var allocator = &gpa.allocator;
    // check that no memory has been requested
    std.testing.expect(gpa.total_requested_bytes == 0);

    // allocate some memory (not the try)
    const ptr = try allocator.alloc(u8,10);

    // check that the allocation success
    std.testing.expect(gpa.total_requested_bytes == 10);

    // free memory
    allocator.free(ptr);

    // check free success
    std.testing.expect(gpa.total_requested_bytes == 0);

}
