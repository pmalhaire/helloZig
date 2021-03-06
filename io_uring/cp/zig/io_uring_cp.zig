const std = @import("std");
const os = std.os;

const DEBUG: bool = false;

const QD :u13 = 32;
const BS :usize = (16 * 1024);

var infd :std.fs.File = undefined;
var outfd :std.fs.File = undefined;

/// some code is borrowed from  Vincent Rischmann thx to him

const IoData = struct {
    opcode: os.linux.IORING_OP,
    first_offset: usize,
    offset: usize,
    first_len :usize,
    iov: *os.iovec,
};

pub fn setup(entries: u13, flags: u32) !os.linux.IO_Uring {

    if (DEBUG) {
        std.debug.print("setup {} {}\n", .{
            entries,
            flags,
        });
    }

    return os.linux.IO_Uring.init(entries, flags);
}

pub fn queue_prepped(ring :os.linux.IO_Uring, ioData :*IoData) !void
{

    if (DEBUG){
            std.debug.print("queue_prepped {} {}\n", .{
                ring,
                ioData,
            });
    }
    var sqe = try ring.get_sqe();

    if (ioData.opcode == .READV)  {
        sqe.opcode = .READV;
        sqe.fd = infd.handle;
        sqe.flags |= std.os.linux.IOSQE_IO_LINK;
        sqe.addr = @ptrCast(*u64, &iovec).*;
        sqe.off = @intCast(u64, offset);
        sqe.len = @intCast(u32, 1);
        var el = &read_user_data[inflight];
        el.iov = iovec;
        el.opcode = .READV;
        sqe.user_data = @intCast(u64, @ptrToInt(el));
    } else {
        sqe.opcode = .WRITEV;
        sqe.fd = outfd.handle;
        sqe.addr = @ptrCast(*u64, &iovec).*;
        sqe.off = @intCast(u64, write_offset);
        sqe.len = @intCast(u32, 1);

        var el = &write_user_data[write_inflight];
        el.iov = iovec;
        el.opcode = .WRITEV;
        sqe.user_data = @intCast(u64, @ptrToInt(el));
    }
}

pub fn queue_read(ring :*os.linux.IO_Uring, size :usize, offset :usize) !void
{
    // submit read for input file
    var sqe = try ring.get_sqe();
    sqe.opcode = .READV;
    sqe.fd = infd.handle;
    sqe.flags |= std.os.linux.IOSQE_IO_LINK;
    //sqe.addr = @ptrCast(*u64, &iovec).*;
    sqe.off = @intCast(u64, offset);
    sqe.len = @intCast(u32, 1);

    // var el = &read_user_data[inflight];
    // el.iov = iovec;
    // el.opcode = .READV;
    // sqe.user_data = @intCast(u64, @ptrToInt(el));
}

pub fn queue_write(ring :os.linux.IO_Uring, size :usize, offset :usize) !void
{
    // submit read for input file
    const sqe = try ring.get_sqe();
    sqe.opcode = .WRITEV;
    sqe.fd = outfd.handle;
    sqe.addr = @ptrCast(*u64, &iovec).*;
    sqe.off = @intCast(u64, write_offset);
    sqe.len = @intCast(u32, 1);

    var el = &write_user_data[write_inflight];
    el.iov = iovec;
    el.opcode = .WRITEV;
    sqe.user_data = @intCast(u64, @ptrToInt(el));
}

pub fn main() anyerror!void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    var allocator = &arena.allocator;


    var args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (DEBUG) {
        std.debug.print("copying {s} to {s}\n", .{
            args[1],
            args[2],
        });
    }

    infd = try std.fs.cwd().openFile(args[1], .{});
    defer infd.close();
    outfd = try std.fs.cwd().createFile(args[2], .{});
    defer outfd.close();

    if (DEBUG) {
        std.debug.warn("nb SQEs: {} ; iovec size: {}\n", .{
            QD,
            BS,
        });
    }

    const insize = (try infd.stat()).size;

    // Initialize io_uring
    var ring = try setup(QD, 0);

    var reads: usize = 0;
    var writes: usize = 0;
    var offset: usize = 0;

    var write_left: usize = insize;
    var read_left: usize = insize;

    // flag used submit io for read
    var read_done: bool = false;

    // try to write until the end : write_left
    // wait for last write submission writes > 0
    while ( write_left > 0 or writes > 0 )
    {

        read_done = false;

        while (read_left > 0)
        {
            // choose iovector
            //var iovec = &iovecs[inflight];

            // if queue is full wait for completion
            if (reads + writes >= QD)
                break;
            // if no more to read break
            if (read_left == 0)
                break;

            // if the size is bigger than block size
            // just read one block
            var read_size: usize = read_left;
            if ( read_left > BS ) {
                read_size = BS;
            }
            // try to read
            try queue_read(&ring, read_size, offset);
            // {
            //     break;
            // }

            read_left -= read_size;
            offset += read_size;
            reads += 1;
            read_done = true;
        }

        // if at least one read have been done submit queue
        if (read_done)
        {

            var ret = try ring.submit();
            if (ret < 0)
            {
                std.debug.print("io_uring_submit read error\n");
                break;
            }
        }
        var io_data: *IoData = undefined;

        // wait for cqe
        var cqe = try ring.copy_cqe();
        if (DEBUG) {
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
                    std.debug.warn("cqe errno: {}", .{cqe.res});
                    std.process.exit(1);
                },
            }
        }

        // read received
        if (io_data.opcode == .READV)
        {
            // if we are reading data transfer it to the write buffer
            //queue_write(&ring, io_data);
            var ret = try ring.submit();
            if (ret < 0)
            {
                std.debug.print("io_uring_submit read error\n");
                break;
            }
            // write_left -= data.first_len;
            reads -= 1;
            writes += 1;
        }

    }
}
