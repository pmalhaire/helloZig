#!/bin/bash

gcc io_uring.c -luring -o io_uring
chmod +x io_uring
echo >/tmp/toto; for i in {1..10000};do echo "toto[$i]" >>/tmp/toto;done
./io_uring /tmp/toto /tmp/tata