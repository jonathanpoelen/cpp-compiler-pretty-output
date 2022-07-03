#!/bin/sh
eval `luarocks path`
"$(dirname "$(realpath "$0")")"/cpp-compiler-pretty-output.lua "$@"
