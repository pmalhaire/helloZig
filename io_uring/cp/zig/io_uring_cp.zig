const std = @import("std");
const os = std.os;

const DEBUG: bool = false;

const QD :u13 = 32;
const BS :usize = (16 * 1024);

var infd :std.fs.File = undefined;
var outfd :std.fs.File = undefined;

/// some code is borrowed from  Vincent Rischmann thx to him

const IoData = struct {
    rw_flag: os.linux.IORING_OP,
    first_offset: usize,
    offset: usize,
    first_len :usize,
    iov: [] os.iovec,
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

pub fn queue_prepped(ring :*os.linux.IO_Uring, data :*IoData) !void
{
    if (DEBUG){
            std.debug.print("queue_prepped {} {}\n", .{
                ring,
                data,
            });
    }
    const sqe = try ring.get_sqe();

    if (data.rw_flag == .READV)  {
        os.linux.io_uring_prep_readv(sqe, infd.handle, data.iov, data.offset);
    } else {
        // kinda const cast (did not found better)
        os.linux.io_uring_prep_writev(sqe, outfd.handle, @ptrCast(*[]const os.iovec_const, &data.iov).*, data.offset);
    }

    sqe.user_data = @ptrToInt(data);
}

pub fn queue_read(ring :*os.linux.IO_Uring, allocator :*std.mem.Allocator, size :usize, offset :usize) !void
{
    if (DEBUG){
            std.debug.print("   queue_read size:{} offset:{}\n", .{
                size,
                offset,
            });
    }
    var data: *IoData = try allocator.create(IoData);
    data.* = .{
        .rw_flag = .READV,
        .first_offset = offset,
        .offset = offset,
        .iov = try allocator.alloc(os.iovec, 1),
        .first_len = size,
    };

    const buf = try allocator.alloc(u8, size);
    data.iov[0].iov_base = buf.ptr;
    data.iov[0].iov_len = buf.len;


    // get submission queue
    const sqe = try ring.get_sqe();

    os.linux.io_uring_prep_readv(sqe, infd.handle, data.iov, data.offset);

    sqe.user_data = @ptrToInt(data);
}

pub fn queue_write(ring :*os.linux.IO_Uring, data :*IoData) !void
{
    if (DEBUG){
            std.debug.print("queue_write {}\n", .{
                data,
            });
    }
    // indicate write flag
    data.rw_flag = .WRITEV;

    data.offset = data.first_offset;

    const sqe = try ring.get_sqe();

    os.linux.io_uring_prep_writev(sqe, outfd.handle, @ptrCast(*[]const os.iovec_const, &data.iov).*, data.offset);

    sqe.user_data = @ptrToInt(data);
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

    // pending reads sent to sqe
    var reads: usize = 0;

    // pending reads sent to sqe
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
        if (DEBUG){
                std.debug.print("while write {} {}\n", .{
                    write_left,
                    writes,
                });
        }
        read_done = false;

        while (read_left > 0)
        {
            if (DEBUG){
                std.debug.print("while read {}\n", .{
                    read_left,

                });
            }
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
            queue_read(&ring, allocator, read_size, offset) catch {
                if (DEBUG){
                        std.debug.print("queue_read fail sqe is full\n", .{
                        });
                }
                break;
            };

            read_left -= read_size;
            offset += read_size;
            reads += 1;
            read_done = true;
        }

        // if at least one read have been done submit queue
        if (read_done)
        {
            if (DEBUG) {
                std.debug.print("submit read\n", .{});
            }
            var ret = try ring.submit();
            if (ret < 0)
            {
                std.debug.print("io_uring_submit read error\n");
                break;
            }
        }
        if (DEBUG) {
            std.debug.print("wait for cqe w:{} r:{}\n", .{
                writes,
                reads,
            });
        }
        // wait for cqe
        var cqe = try ring.copy_cqe();
        if (DEBUG) {
            std.debug.print("received cqe {}  \n", .{
                cqe,
            });
        }

        var io_data: *IoData = @intToPtr(*IoData, cqe.user_data);
        if (cqe.res < 0) {
            switch (cqe.res) {
                -std.os.EAGAIN => {
                    // push the operation again
                    try queue_prepped(&ring, io_data);
                    //io_uring_cqe_seen(ring, cqe);
                    continue;
                },
                -os.EINVAL => {
                    std.debug.warn("either you're trying to read too much data (can't read more than a isize), or the number of iovecs in a single SQE is > 1024\n", .{});
                    std.process.exit(1);
                },
                else => {
                    std.debug.warn("cqe errno: {}", .{cqe.res});
                    std.process.exit(1);
                },
            }
        }
        //else if (cqe.res != io_data.iov[0].iov_len)
        // {
        //     // read or write is shorter than expected
        //     // adjusting the queue size accordingly
        //     io_data.iov[0].iov_base += @intCast(usize, cqe.res);
        //     io_data.iov[0].iov_len -= @intCast(usize, cqe.res);
        //     // push the operation for missing data
        //     try queue_prepped(&ring, io_data);
        //     //io_uring_cqe_seen(ring, cqe);
        //     continue;
        // }

        // read received
        if (io_data.rw_flag == .READV)
        {
            // if we are reading data transfer it to the write buffer
            try queue_write(&ring, io_data);
            var ret = try ring.submit();
            if (ret < 0)
            {
                std.debug.print("io_uring_submit write error\n");
                break;
            }
            write_left -= io_data.first_len;
            reads -= 1;
            writes += 1;
        }       else
        {
            allocator.destroy(io_data.iov[0].iov_base);
            allocator.free(io_data.iov);
            allocator.destroy(io_data);
            writes -= 1;
        }

    }
}
