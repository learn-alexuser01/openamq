@echo off
:-   This script runs various test sets
:-
echo Testing HANDLE QUERY...
test_level0 producer -h/test -dtest -mproducer -n500 -i1
test_level0 query -h/test -dtest