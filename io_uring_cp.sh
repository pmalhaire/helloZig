#!/bin/bash

gcc io_uring_cp.c -luring -o io_uring_cp
chmod +x io_uring_cp
echo >/tmp/toto; for i in {1..10000};do echo "toto[$i]" >>/tmp/toto;done
./io_uring_cp /tmp/toto /tmp/tata