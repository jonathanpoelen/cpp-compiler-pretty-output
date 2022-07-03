Highlight parts of the compiler output.

> clang++ test.cpp -fdiagnostics-color=always |& cpp-compiler-pretty-output.lua

![output sample](./sample.png "output sample")

An external command like `clang-format` can be configured to format very large expressions.
