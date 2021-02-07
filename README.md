# hello zig : explore zig through a LIFO buffer

![ZIG](https://camo.githubusercontent.com/99f388a65a6eed1d03fc9bc24c983debcb2445e07f53af825e28e69c049a6912/68747470733a2f2f7a69676c616e672e6f72672f7a69672d6c6f676f2e737667)

why this repo. i explored many languages from functionnal to assembly.

zig has many things that are really cool :

- small language : not many thing to have in brain
- pointers and memory safety
- multiplatform
- early project everything is to be done

## deps

install zig : https://ziglang.org/download/

install zig for vim : https://github.com/ziglang/zig.vim

## starting over

let's say hello world :

```
const std = @import("std");


pub fn main() void {
    // WRONG on purpose
    std.debug.print("hello, world !\n");
}
```

wrong here

`std.debug.print` takes two arguments so the basic hello world is

```
const std = @import("std");


pub fn main() void {
    std.debug.print("hello, world !\n", .{});
}
```

It looks strange at first but why not.

There we can see that zig is not a hype language. from the first function
choices have been made.

## doc generation

Not ready yet.

Auto doc is underway see : https://github.com/tiehuis/zig-docgen


## doing a basic io/buffer

let's try zig with a simple async io/buffer.

goal is write / read async char by char.

### step 1 alloc

what we need :

#### store data

struct : https://ziglang.org/documentation/master/#struct

#### allocator

memory : https://ziglang.org/documentation/master/#memory

Note : At first you may want to use pointer arithmetics. But slices are forced by the language no pointer arithmetics !

https://github.com/ziglang/zig/issues/45

#### slices

Slice follow a very similar syntax than golang one :

```
// write a slice
const slice: []const u8 = "hello slice";
// write an array
const array: [11]u8 = "hello array".*;
```

see : https://ziglang.org/documentation/master/#Slices


### test alloc sample

It's where `zig` doc must be read.


and make a small alloc sample

1. alloc a slice
2. write slice
3. free slice


here zig has a nice test feature :
let's use it. see https://ziglang.org/documentation/master/#Zig-Test


```
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
```

run the test

```
zig test alloc.zig
```

### step 2 :sync lifo

Now that the allocation is cleared. Let's now get back to our buffer.

Many zig function use the maybe concept.
Coming fron the `Maybe monad` in Haskell then adapted to other languages.
For example the `std:optionnal` in cpp.

This tells that a function either succeed or returns an error :
`ErrorType!ReturnType`

This is a very elegant way of handling error and avoid other language issues :
- If error checks of golang (improved since 1.13).
- Exception handling in python (not improved here).


see https://ziglang.org/documentation/master/#Errors

#### code


We write 4 functions :

init

```
fn init(size: u32, a: *Allocator) Error!*Buff {
```

write

```
fn write(b: *Buff, c: u8) void {
```

read

```
fn read(b: *Buff) u8 {
```


close
```
fn close(b: *Buff) void {
```

The program :

```ziglang
const std = @import("std");
const Allocator = std.mem.Allocator;
const GPA = std.heap.GeneralPurposeAllocator;
const Error = std.mem.Allocator.Error;

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
fn write(b: *Buff, c: u8) void {
    // todo add fail if more than size
    b.addr[b.offset] = c;
    b.*.offset += 1;
}

/// read c into our buffer
fn read(b: *Buff) u8 {
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
    write(buff, 'a');


    std.debug.print("reading one char from buff\n", .{});
    const c = read(buff);
    std.debug.print("char is : {c}\n", .{c});


    std.debug.print("writing 'a' then 'b' to buff\n", .{});
    write(buff, 'a');
    write(buff, 'b');



    std.debug.print("reading two char from buff\n", .{});
    const d = read(buff);
    const e = read(buff);
    std.debug.print("chars are : {c} {c}\n", .{d, e});

    // test failure uncomment next line : overflow
    // const f = read(buff);

    // test failure uncomment next line : out of bound
    // write(buff, '1'); write(buff, '2'); write(buff, '3'); write(buff, '4');

}
```

#### test it

```
zig run sync_buff.zig
```

output

```
writing 'a' to buff
reading one char from buff
char is : a
writing 'a' then 'b' to buff
reading two char from buff
chars are : b a
```

#### safety

Let's try to read a value that is not there.

uncomment the overflow error in sync_buff.zig

```
zig run sync_buff.zig
```

error :

```
thread 34197 panic: integer overflow
/home/pierrot/dev/helloZig/sync_buff.zig:44:14: 0x2363d1 in read (sync_buff)
    b.offset -= 1;
             ^
/home/pierrot/dev/helloZig/sync_buff.zig:78:19: 0x22ddb4 in main (sync_buff)
    const f = read(buff);
                  ^
/home/pierrot/.zig/lib/std/start.zig:345:37: 0x205684 in std.start.posixCallMainAndExit (sync_buff)
            const result = root.main() catch |err| {
                                    ^
/home/pierrot/.zig/lib/std/start.zig:163:5: 0x205522 in std.start._start (sync_buff)
    @call(.{ .modifier = .never_inline }, posixCallMainAndExit, .{});
    ^
Aborted (core dumped)
```

Let's try to read a value that is not there.

uncomment the out of bound error in sync_buff.zig

```
zig run sync_buff.zig
```

error :


```
thread 35402 panic: index out of bounds
/home/pierrot/dev/helloZig/sync_buff.zig:38:11: 0x2362a9 in write (sync_buff)
    b.addr[b.offset] = c;
          ^
/home/pierrot/dev/helloZig/sync_buff.zig:83:64: 0x22ddec in main (sync_buff)
    write(buff, '1'); write(buff, '2'); write(buff, '3'); write(buff, '4');
                                                               ^
/home/pierrot/.zig/lib/std/start.zig:345:37: 0x205684 in std.start.posixCallMainAndExit (sync_buff)
            const result = root.main() catch |err| {
                                    ^
/home/pierrot/.zig/lib/std/start.zig:163:5: 0x205522 in std.start._start (sync_buff)
    @call(.{ .modifier = .never_inline }, posixCallMainAndExit, .{});
    ^
Aborted (core dumped)
```

## samples

All code samples here are available in this repo : https://github.com/pmalhaire/helloZig.


## Conclusion

Zig is definetly simple for an experienced developper. It exposes in a simple maner complex concepts.
It's a very good language to have in your toolbox. It will probably grow fast in the coming years.
