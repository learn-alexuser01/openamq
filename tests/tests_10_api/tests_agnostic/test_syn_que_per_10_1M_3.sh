#!/bin/sh

repeats=2
clients="../../../clients"

export PATH=$PATH:$clients:$PATH:$clients/agnostic
echo "The test will be repeated $repeats time(s)."
time amqpcli_serial -h /test -n $(($repeats * 10)) -l 1048576 -x -i 0 
