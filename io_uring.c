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

#define DEBUG 1

#define QD 32
#define BS (16 * 1024)

static int infd, outfd;

struct io_data
{
    int read;
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
    if (data->read)
        io_uring_prep_readv(sqe, infd, &data->iov, 1, data->offset);
    else
        io_uring_prep_writev(sqe, outfd, &data->iov, 1, data->offset);

    io_uring_sqe_set_data(sqe, data);
}

static int queue_read(struct io_uring *ring, off_t size, off_t offset)
{
#ifdef DEBUG
    printf("queue_read ring:%p size:%d offset:%d\n", ring, size, offset);
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
    data->read = 1;
    data->offset = data->first_offset = offset;

    data->iov.iov_base = data + 1;
    data->iov.iov_len = size;
    data->first_len = size;

    io_uring_prep_readv(sqe, infd, &data->iov, 1, offset);
    io_uring_sqe_set_data(sqe, data);
    return 0;
}

static void queue_write(struct io_uring *ring, struct io_data *data)
{
#ifdef DEBUG
    printf("queue_write ring:%p io_data:%p\n", ring, data);
#endif
    // indicate write flag
    data->read = 0;
    data->offset = data->first_offset;

    data->iov.iov_base = data + 1;
    data->iov.iov_len = data->first_len;

    queue_prepped(ring, data);
    io_uring_submit(ring);
}

int copy_file(struct io_uring *ring, off_t insize)
{
#ifdef DEBUG
    printf("copy_file ring:%p insize:%d\n", ring, insize);
#endif
    unsigned long reads, writes;
    struct io_uring_cqe *cqe;
    off_t write_left, offset;
    int ret;

    write_left = insize;
    writes = reads = offset = 0;

    while (insize || write_left)
    {
#ifdef DEBUG
        printf("|_copy_file->LOOP insize:%d write_left:%d\n", insize, write_left);
#endif
        int had_reads, got_comp;

        /* Queue up as many reads as we can */
        had_reads = reads;
        while (insize)
        {
#ifdef DEBUG
            printf(" |_copy_file->LOOP->QUEUE_READ insize:%d\n", insize);
#endif
            off_t this_size = insize;

            if (reads + writes >= QD)
                break;
            if (this_size > BS)
                this_size = BS;
            else if (!this_size)
                break;

            if (queue_read(ring, this_size, offset))
                break;

            insize -= this_size;
            offset += this_size;
            reads++;
        }

        if (had_reads != reads)
        {
#ifdef DEBUG
            printf("|_copy_file->LOOP submit ring:%p\n", ring);
#endif
            ret = io_uring_submit(ring);
            if (ret < 0)
            {
                fprintf(stderr, "io_uring_submit: %s\n", strerror(-ret));
                break;
            }
        }

        /* Queue is full at this point. Let's find at least one completion */
        got_comp = 0;
        while (write_left)
        {
#ifdef DEBUG
            printf(" |_copy_file->LOOP->cqe wait write_left:%d\n", write_left);
#endif
            struct io_data *data;

            if (!got_comp)
            {
                // wait for completion queue
                ret = io_uring_wait_cqe(ring, &cqe);
                got_comp = 1;
            }
            else
            {
                // retrieve from completion queue
                ret = io_uring_peek_cqe(ring, &cqe);
                if (ret == -EAGAIN)
                {
                    cqe = NULL;
                    ret = 0;
                }
            }
            if (ret < 0)
            {
                fprintf(stderr, "io_uring_peek_cqe: %s\n",
                        strerror(-ret));
                return 1;
            }
            // check that cqe is valid
            if (!cqe)
                break;
#ifdef DEBUG
            printf(" |_copy_file->LOOP->cqe get_data write_left:%d\n", write_left);
#endif
            // retrieve data from completion queue
            data = io_uring_cqe_get_data(cqe);

            // check completion queue result
            if (cqe->res < 0)
            {
                // handle again case
                if (cqe->res == -EAGAIN)
                {
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
                queue_prepped(ring, data);
                io_uring_cqe_seen(ring, cqe);
                continue;
            }

            /*
             * All done. If write, nothing else to do. If read,
             * queue up corresponding write.
             * */

            if (data->read)
            {
                // if we are reading data transfer it to the write buffer
#ifdef DEBUG
                printf(" |_copy_file->LOOP->cqe queue_write data->read:%d\n", data->read);
#endif
                queue_write(ring, data);
                write_left -= data->first_len;
                reads--;
                writes++;
            }
            else
            {
                free(data);
                writes--;
            }
            // indicate uring that action have been made
            // after io_uring_peek_cqe or io_uring_wait_cqe
            io_uring_cqe_seen(ring, cqe);
        }
    }

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
        return 1;

    if (get_file_size(infd, &insize))
        return 1;

    ret = copy_file(&ring, insize);

    close(infd);
    close(outfd);
    // exiting io_uring
    io_uring_queue_exit(&ring);
    return ret;
}