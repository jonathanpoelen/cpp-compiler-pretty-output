package = "cpp-compiler-pretty-output"
version = "1.1-1"
source = {
  url = "git://github.com/jonathanpoelen/cpp-compiler-pretty-output",
  tag = "v1.1.1"
}
description = {
  summary = "Highlight output parts of C++ compilers.",
  detailed = "Allows you to apply a command or color the expressions displayed in the error, warning and note messages of C++ compilers.",
  homepage = "https://github.com/jonathanpoelen/cpp-compiler-pretty-output",
  license = "MIT"
}
dependencies = {
  "lua >= 5.1",
  "lpeg >= 1.0",
  "argparse >= 0.7",
}
build = {
  type = "none",
  install = {
    bin = {
      ["cpp-compiler-pretty-output"] = "cpp-compiler-pretty-output.lua",
    }
  },
}
