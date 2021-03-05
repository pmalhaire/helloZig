#include <stdio.h>
#include <fcntl.h>
#include <string.h>
#include <stdlib.h>
#include <unistd.h>
#include <assert.h>
#include <errno.h>
#include <sys/stat.h>
#include <sys/ioctl.h>
#include <liburing.h>

//#define DEBUG 1

#define QD 32
#define BS (16 * 1024)

static int infd, outfd;

#define READ true
#define WRITE false

struct io_data
{
    bool rw_flag;
    off_t first_offset, offset;
    size_t first_len;
    struct iovec iov;
};

static int setup_context(unsigned entries, struct io_uring *ring)
{
#ifdef DEBUG
    printf("setup_context entries:%u ring:%p\n", entries, ring);
#endif
    int ret;

    ret = io_uring_queue_init(entries, ring, 0);
    if (ret < 0)
    {
        fprintf(stderr, "queue_init: %s\n", strerror(-ret));
        return -1;
    }

    return 0;
}

static int get_file_size(int fd, off_t *size)
{
#ifdef DEBUG
    printf("get_file_size fd:%d size:%d\n", fd, *size);
#endif
    struct stat st;

    if (fstat(fd, &st) < 0)
        return -1;
    if (S_ISREG(st.st_mode))
    {
        *size = st.st_size;
        return 0;
    }
    else if (S_ISBLK(st.st_mode))
    {
        unsigned long long bytes;

        if (ioctl(fd, BLKGETSIZE64, &bytes) != 0)
            return -1;

        *size = bytes;
        return 0;
    }
    return -1;
}

static void queue_prepped(struct io_uring *ring, struct io_data *data)
{
#ifdef DEBUG
    printf("queue_prepped ring:%p io_data:%p\n", ring, data);
#endif
    struct io_uring_sqe *sqe;
    // get submission queue
    sqe = io_uring_get_sqe(ring);
    assert(sqe);

    // choose read or write depending on flag
    if (data->rw_flag == READ)
        io_uring_prep_readv(sqe, infd, &data->iov, 1, data->offset);
    else
        io_uring_prep_writev(sqe, outfd, &data->iov, 1, data->offset);

    io_uring_sqe_set_data(sqe, data);
}

static int queue_read(struct io_uring *ring, off_t size, off_t offset)
{
#ifdef DEBUG
    printf("   queue_read ring:%p size:%d offset:%d\n", ring, size, offset);
#endif
    struct io_uring_sqe *sqe;
    struct io_data *data;

    // get submission queue
    sqe = io_uring_get_sqe(ring);
    if (!sqe)
    {
        return 1;
    }

    // allocate data
    data = malloc(size + sizeof(*data));
    if (!data)
        return 1;

    // set read flag
    data->rw_flag = READ;

    // set offset
    data->offset = data->first_offset = offset;

    data->iov.iov_base = data + 1;
    data->iov.iov_len = size;
    data->first_len = size;
    // setup readv operation
    io_uring_prep_readv(sqe, infd, &data->iov, 1, offset);
    // set user data for operation
    io_uring_sqe_set_data(sqe, data);
    return 0;
}

static void queue_write(struct io_uring *ring, struct io_data *data)
{
#ifdef DEBUG
    printf("queue_write ring:%p io_data:%p\n", ring, data);
#endif
    // indicate write flag
    data->rw_flag = WRITE;
    data->offset = data->first_offset;

    data->iov.iov_base = data + 1;
    data->iov.iov_len = data->first_len;

    struct io_uring_sqe *sqe;
    // get submission queue
    sqe = io_uring_get_sqe(ring);
    assert(sqe);

    // set writev operation
    io_uring_prep_writev(sqe, outfd, &data->iov, 1, data->offset);

    // set user data for operation
    io_uring_sqe_set_data(sqe, data);
}

int copy_file(struct io_uring *ring, const off_t insize)
{
#ifdef DEBUG
    printf("copy_file ring:%p insize:%d\n", ring, insize);
#endif
    // reads and writes counts
    unsigned long reads, writes;
    // completion queue
    struct io_uring_cqe *cqe;
    // write_left bytes and offset
    off_t write_left, read_left, offset;
    int ret;

    // at start entire file has to be read and written
    write_left = read_left = insize;
    writes = reads = offset = 0;

    // flag used submit io for read
    bool read_done;

    // try to write until the end : write_left
    // wait for last write submission writes > 0
    while (write_left || writes > 0)
    {
#ifdef DEBUG
        printf("|_copy_file->LOOP read_left:%d write_left:%d\n", read_left, write_left);
#endif

        /* Queue up as many reads as we can */
        read_done = false;
        while (read_left)
        {
#ifdef DEBUG
            printf("  |_copy_file->LOOP->QUEUE_READ read_left:%d\n", read_left);
#endif
            // if queue is full wait for completion
            if (reads + writes >= QD)
                break;
            // if no more to read break
            if (!read_left)
                break;
            // if the size is bigger than block size
            // just read one block
            off_t read_size = read_left > BS ? BS : read_left;

            // try to read
            if (queue_read(ring, read_size, offset))
            {
                break;
            }

            read_left -= read_size;
            offset += read_size;
            reads++;
            read_done = true;
        }

        // if at least one read have been done submit queue
        if (read_done)
        {
#ifdef DEBUG
            printf("|_copy_file->LOOP submit ring:%p\n", ring);
#endif
            ret = io_uring_submit(ring);
            if (ret < 0)
            {
                fprintf(stderr, "io_uring_submit read error: %s\n", strerror(-ret));
                break;
            }
        }

#ifdef DEBUG
        printf("|_copy_file->LOOP->cqe wait write_left:%d\n", write_left);
#endif
        struct io_data *data;

        // wait for completion queue
        ret = io_uring_wait_cqe(ring, &cqe);
        if (ret < 0)
        {
            fprintf(stderr, "io_uring_peek_cqe: %s\n",
                    strerror(-ret));
            return 1;
        }
        // check that cqe is valid
        assert(cqe);

        // retrieve data from completion queue
        data = io_uring_cqe_get_data(cqe);

        // check completion queue result
        if (cqe->res < 0)
        {
            // handle again case
            if (cqe->res == -EAGAIN)
            {
                // push the operation again
                queue_prepped(ring, data);
                io_uring_cqe_seen(ring, cqe);
                continue;
            }
            // any other case lead to an error
            fprintf(stderr, "cqe failed: %s\n",
                    strerror(-cqe->res));
            return 1;
        }
        else if (cqe->res != data->iov.iov_len)
        {
            // read or write is shorter than expected
            // adjusting the queue size accordingly
            data->iov.iov_base += cqe->res;
            data->iov.iov_len -= cqe->res;
            // push the operation for missing data
            queue_prepped(ring, data);
            io_uring_cqe_seen(ring, cqe);
            continue;
        }

        /*
             * All done. If write, nothing else to do. If read,
             * queue up corresponding write.
             * */
#ifdef DEBUG
        printf("|_copy_file->LOOP->cqe queue_write data->rw_flag:%d\n", data->rw_flag);
#endif
        // read received
        if (data->rw_flag == READ)
        {
            // if we are reading data transfer it to the write buffer
            queue_write(ring, data);
            ret = io_uring_submit(ring);
            if (ret < 0)
            {
                fprintf(stderr, "io_uring_submit write error: %s\n", strerror(-ret));
                break;
            }

            write_left -= data->first_len;
            reads--;
            writes++;
        }
        // write received
        else
        {
            free(data);
            writes--;
        }
        // indicate uring that action have been made
        // after io_uring_peek_cqe or io_uring_wait_cqe
        io_uring_cqe_seen(ring, cqe);
    }
    // bug here in some case all is not finished
    return 0;
}

int main(int argc, char *argv[])
{
    struct io_uring ring;
    off_t insize;
    int ret;

    if (argc < 3)
    {
        printf("Usage: %s <infile> <outfile>\n", argv[0]);
        return 1;
    }

    infd = open(argv[1], O_RDONLY);
    if (infd < 0)
    {
        perror("open infile");
        return 1;
    }

    outfd = open(argv[2], O_WRONLY | O_CREAT | O_TRUNC, 0644);
    if (outfd < 0)
    {
        perror("open outfile");
        return 1;
    }

    if (setup_context(QD, &ring))
    {
        perror("setup context");
        return 1;
    }

    if (get_file_size(infd, &insize))
    {
        perror("get_file_size");
        return 1;
    }

    ret = copy_file(&ring, insize);

    close(infd);
    close(outfd);
    // exiting io_uring
    io_uring_queue_exit(&ring);
    return ret;
}
