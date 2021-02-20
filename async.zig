const std = @import("std");
const Allocator = std.mem.Allocator;

pub fn main() void {
    _ = async amainWrap();

    // Typically we would use an event loop to manage resuming async functions,
    // but in this example we hard code what the event loop would do,
    // to make things deterministic.
    resume async_func_frame;
}

fn amainWrap() void {
    amain() catch |e| {
        std.debug.print("{}\n", .{e});
        if (@errorReturnTrace()) |trace| {
            std.debug.dumpStackTrace(trace.*);
        }
        std.process.exit(1);
    };
}

fn amain() !void {
    const allocator = std.heap.page_allocator;
    var async_frame = async asyncFunc(allocator, "async_var");
    var awaited_async_frame = false;
    errdefer if (!awaited_async_frame) {
        if (await async_frame) |r| allocator.free(r) else |_| {}
    };


    awaited_async_frame = true;
    const async_text = try await async_frame;
    defer allocator.free(async_text);

    std.debug.print("async_text: {s}\n", .{async_text});
}

var async_func_frame: anyframe = undefined;
fn asyncFunc(allocator: *Allocator, async_text: []const u8) ![]u8 {
    const result = try std.mem.dupe(allocator, u8, "this is the async text");
    errdefer allocator.free(result);
    suspend {
        async_func_frame = @frame();
    }
    std.debug.print("asyncFunc returning\n", .{});
    return result;
}