#!/bin/bash
set -e
mkdir -p build
gcc c/io_uring_cp.c -O3 -luring -o build/c_io_uring_cp
chmod +x build/c_io_uring_cp
zig build-exe zig/io_uring_cp.zig -femit-bin=build/zig_io_uring_cp
chmod +x build/zig_io_uring_cp
echo >/tmp/toto; for i in {1..10000};do echo "toto[$i]" >>/tmp/toto;done
echo "c timing :"
time build/c_io_uring_cp /tmp/toto /tmp/tata
diff -q /tmp/toto /tmp/tata

echo "zig timing :"
time build/zig_io_uring_cp /tmp/toto /tmp/tata
diff -q /tmp/toto /tmp/tata
