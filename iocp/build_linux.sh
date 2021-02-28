#!/bin/bash

FLAGS="-fpermissive -lws2_32 -static-libgcc -static-libstdc++"

i686-w64-mingw32-g++ -Iclient client/iocpclient.cpp -o client.exe $FLAGS
i686-w64-mingw32-g++ -Iserver server/iocpserver.cpp -o server.exe $FLAGS
