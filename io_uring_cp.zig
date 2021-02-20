const std = @import("std");
const os = std.os;

/// some code is borrowed from  Vincent Rischmann thx to him

pub fn setup(entries: usize, params: *os.linux.io_uring_params) !os.fd_t {
    @memset(@ptrCast([*]align(8) u8, params), 0, @sizeOf(@TypeOf(params.*)));

    const ring_fd = os.linux.io_uring_setup(
        @intCast(u32, entries),
        params,
    );

    return @intCast(i32, ring_fd);
}

const UserData = struct {
    const Self = @This();

    opcode: os.linux.IORING_OP,
    iovec: *os.iovec,

    pub fn printIovec(self: *Self) void {
        const slice = self.iovec.iov_base[0..self.iovec.iov_len];
        std.debug.warn("{} (size = {})\n", .{ slice, slice.len });
    }
};

pub fn main() anyerror!void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    var allocator = &arena.allocator;

    // Parse the process arguments

    var args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    // Default values for the tunables:
    //  * 8 SQE
    //  * 128KiB per iovec
    var nb_sqes: usize = 8;
    var iovec_size: usize = 131072;

    if (args.len < 3) {
        std.debug.warn("Usage: zig-uring <source> <target>", .{});
        std.process.exit(1);
    }

    var verbose: bool = false;
    var start_positional_arg_pos: usize = 1;
    for (args) |arg, i| {
        if (i == 0) continue;

        if (std.mem.startsWith(u8, arg, "--nb-sqes=")) {
            const value = std.mem.trimLeft(u8, arg, "--nb-sqes=");
            nb_sqes = try std.fmt.parseInt(usize, value, 10);
        } else if (std.mem.startsWith(u8, arg, "--iovec-size=")) {
            const value = std.mem.trimLeft(u8, arg, "--iovec-size=");
            iovec_size = try std.fmt.parseInt(usize, value, 10);
        } else if (std.mem.eql(u8, arg, "--verbose")) {
            verbose = true;
        } else {
            start_positional_arg_pos = i;
            break;
        }
    }

    if (verbose) {
        std.debug.warn("copying {s} to {s}\n", .{
            args[start_positional_arg_pos],
            args[start_positional_arg_pos + 1],
        });
    }

    var file = try std.fs.cwd().openFile(args[start_positional_arg_pos], .{});
    defer file.close();
    var output_file = try std.fs.cwd().createFile(args[start_positional_arg_pos + 1], .{});
    defer output_file.close();

    // Validate the tunables.

    if (verbose) {
        std.debug.warn("nb SQEs: {} ; iovec size: {}\n", .{
            nb_sqes,
            iovec_size,
        });
    }

    const file_size = (try file.stat()).size;

    // Initialize io_
    var params: os.linux.io_uring_params = undefined;
    const ring_fd = try setup(nb_sqes, &params);

    // var sring = try SubmissionRing.init(ring_fd, params.sq_entries, params.sq_off);
    // var cring = try CompletionRing.init(ring_fd, params.cq_entries, params.cq_off);
    var ring = try std.os.linux.IO_Uring.init(32, 0);
    // Allocate the user data and initialize it.
    // Our user data also owns the iovecs filled by the kernel.
    var iovecs = try allocator.alloc(os.iovec, nb_sqes);
    for (iovecs) |_, i| {
        var buf = try allocator.allocWithOptions(u8, iovec_size, null, null);
        iovecs[i].iov_base = @ptrCast([*]u8, buf);
        iovecs[i].iov_len = buf.len;
    }

    var read_user_data = try allocator.alloc(UserData, nb_sqes);
    var write_user_data = try allocator.alloc(UserData, nb_sqes);

    // State needed to fully read the file.
    //
    // Remaining bytes to read in the file.
    var remaining = file_size;
    // Current user data in the slice of user data.
    // Always 0 <= current_user_data < user_data.len.
    var inflight: usize = 0;
    // Offset into the file to read in the next syscalls.
    var offset: usize = 0;

    // loop until all file is copied
    while (remaining > 0) {
        var original_inflight = inflight;

        while (remaining > 0 and inflight < nb_sqes) {
            // choose iovector
            var iovec = &iovecs[inflight];

            // read iovec_size or remaining id < iovec_size
            const size = if (remaining > iovec_size) iovec_size else remaining;
            iovec.iov_len = size;

            {
                // submit read for input file
                var sqe = try ring.get_sqe();
                sqe.opcode = .READV;
                sqe.fd = file.handle;
                sqe.flags |= std.os.linux.IOSQE_IO_LINK;
                sqe.addr = @ptrCast(*u64, &iovec).*;
                sqe.off = @intCast(u64, offset);
                sqe.len = @intCast(u32, 1);

                var el = &read_user_data[inflight];
                el.iovec = iovec;
                el.opcode = .READV;
                sqe.user_data = @intCast(u64, @ptrToInt(el));
            }
            var read_res = try ring.submit();
            if (verbose) {
                std.debug.print("submit read inflight {} {} sqe \n", .{
                    inflight,
                    read_res,
                });
            }

            {
                // submit write for outputfile
                var sqe = try ring.get_sqe();
                sqe.opcode = .WRITEV;
                sqe.fd = output_file.handle;
                sqe.addr = @ptrCast(*u64, &iovec).*;
                sqe.off = @intCast(u64, offset);
                sqe.len = @intCast(u32, 1);

                var el = &write_user_data[inflight];
                el.iovec = iovec;
                el.opcode = .WRITEV;
                sqe.user_data = @intCast(u64, @ptrToInt(el));
            }
            var write_res = try ring.submit();
            if (verbose) {
                std.debug.print("submit write inflight {} {} sqe \n", .{
                    inflight,
                    write_res,
                });
            }
            offset += size;
            // this seams wrong as we are not granted the read size
            remaining -= size;

            inflight += 2;
        }

        if (original_inflight != inflight) {
            _ = try ring.enter(
                @intCast(u32, inflight),
                @intCast(u32, inflight),
                os.linux.IORING_ENTER_GETEVENTS,
            );
        }
        while (inflight > 0) : (inflight -= 1) {
            // wait for both cqe
            var cqe = try ring.copy_cqe();
            if (verbose) {
                std.debug.print("received {} cqe \n", .{
                    cqe,
                });
            }
            if (cqe.res < 0) {
                switch (cqe.res) {
                    // os.ECANCELED => {
                    //     offset = user_data_el.offset;
                    // },
                    - os.EINVAL => {
                        std.debug.warn("either you're trying to read too much data (can't read more than a isize), or the number of iovecs in a single SQE is > 1024\n", .{});
                        std.process.exit(1);
                    },
                    else => {
                        std.debug.warn("errno: {}", .{cqe.res});
                        std.process.exit(1);
                    },
                }
            }
        }
    }
}
