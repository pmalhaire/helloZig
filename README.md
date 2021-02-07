# hello zig : explore zig through a LIFO buffer

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

It looks strange at first but why not.

There we can see that zig is not a hype language. from the first function
choices have been made.

## doc generation

Not ready yet.

Auto doc is underway see : https://github.com/tiehuis/zig-docgen


## doing a basic io/buffer

let's try zig with a simple async io/buffer.

goal is write / read async char by char.

### step 1 sync lifo

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
