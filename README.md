# hello zig : explore zig with tmux and vim

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

it looks strange at first but why not.

there we can see that zig is not a hypster language. from the first function
choices have been made.

## doc

auto doc is under see : https://github.com/tiehuis/zig-docgen


## doing a basic io/buffer

let's try zig with a simple async io/buffer.

goal is write / read async char by char.

### step 1 sync lifo

what we need :

#### store data

struct : https://ziglang.org/documentation/master/#struct

#### allocator

memory : https://ziglang.org/documentation/master/#memory

that's all slice will be usefull next, but first make it simple.

wrong here : slice are forced by the language no pointer arithmetics !

https://github.com/ziglang/zig/issues/45

let's use slice then.

it's where it became complex

let's keep `sync_buff_0.zig` as a reference of what not to do.

and make a small alloc sample

1. alloc a slice
2. write slice
3. free slice


here zig has a nice test feature :
let's use it

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

Let's now get back to our buffer :

The only issue was the try : many zig function use the maybe concept.

std:optionnal in cpp
Maybe monad in Haskell

This tells that a function either succeed or returns an error :

ErrorType!ReturnType

This is a very elegant way of handling error and avoids the

if error checks of golang

of the exception handling in python or cpp










