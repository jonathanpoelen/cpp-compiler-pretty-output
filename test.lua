#!/usr/bin/lua
-- SPDX-FileCopyrightText: 2022 Jonathan poelen <jonathan.poelen@gmail.com>
-- SPDX-License-Identifier: MIT

count_error = 0
total = 0

insert = table.insert

-- disable reading from stdin
io.input(io.open'/dev/null' or io.open'nul')
require'cpp-compiler-pretty-output'
lpeg = require'lpeg'

local last_traceback_pos = ((1-lpeg.P'test.lua')^1 * 9)^0
                         * lpeg.C(lpeg.R'09'^1)

function show_traceback()
  local msg = debug.traceback()
  local line = last_traceback_pos:match(msg)
  io.stderr:write('\x1b[31mline ', line, ':\x1b[m\n')
end

function eq_pair(a1, b1, a2, b2)
  total = total + 1
  if a1 ~= a2 or b1 ~= b2 then
    show_traceback()
    io.stderr:write(tostring(a1), ', ', tostring(b1),
                    ' != ',
                    tostring(a2), ', ', tostring(b2),
                    '\n')
    count_error = count_error + 1
  end
end

func_to_str = {
  [gcc_formatter] = 'gcc',
  [clang_formatter] = 'clang',
  [msvc_formatter] = 'msvc',
}

function eq_formatter(expected_formatter, expected_has_color, formatter, has_color)
  eq_pair(func_to_str[expected_formatter], expected_has_color,
          func_to_str[formatter], has_color)
end

function eq(a, b)
  total = total + 1
  if a ~= b then
    local p = math.min(#a,#b)
    for i=1,p do
      if a:byte(i) ~= b:byte(i) then
        p = i
        break
      end
    end
    show_traceback()
    io.stderr:write('ERROR at index ', tostring(p),
                    ' (', tostring(#a), '|', tostring(#b), '):\n',
                    a:sub(0, p-1), '~~~~~~', a:sub(p),
                    ' !=\n',
                    b:sub(0, p-1), '~~~~~~', b:sub(p),
                    '\n')
    count_error = count_error + 1
  end
end

function convert_esc(s)
  return s:gsub('\\e', '\x1b')
end

function remove_color(s)
  return s:gsub('\x1b[^mK]+[mK]', '')
end

clang_color = convert_esc[[
\e[1mtest.cpp:4:9: \e[0m\e[0;1;31merror: \e[0m\e[1mno viable conversion from 'int' to 'A<'a'>'\e[0m
 A<'a'> a = 1; +a; foo(a);
\e[0;1;32m        ^   ~
\e[0m\e[1mtest.cpp:2:22: \e[0m\e[0;1;30mnote: \e[0mcandidate constructor (the implicit copy constructor) not viable: no known conversion from 'int' to 'const A<'a'> &' for 1st argument\e[0m
template<char> class A{};
\e[0;1;32m                     ^
\e[0m\e[1mtest.cpp:2:22: \e[0m\e[0;1;30mnote: \e[0mcandidate constructor (the implicit move constructor) not viable: no known conversion from 'int' to 'A<'a'> &&' for 1st argument\e[0m
template<char> class A{};
\e[0;1;32m                     ^
\e[0m\e[1mtest.cpp:4:16: \e[0m\e[0;1;31merror: \e[0m\e[1minvalid argument type 'A<'a'>' to unary expression\e[0m
 A<'a'> a = 1; +a; foo(a);
\e[0;1;32m               ^~
\e[0m\e[1mtest.cpp:4:20: \e[0m\e[0;1;31merror: \e[0m\e[1mno matching function for call to 'foo'\e[0m
 A<'a'> a = 1; +a; foo(a);
\e[0;1;32m                   ^~~
\e[0m\e[1mtest.cpp:1:6: \e[0m\e[0;1;30mnote: \e[0mcandidate function not viable: no known conversion from 'A<'a'>' to 'int' for 1st argument\e[0m
void foo(int){}
\e[0;1;32m     ^
\e[0m\e[1mtest.cpp:5:14: \e[0m\e[0;1;31merror: \e[0m\e[1mredefinition of 'a' with a different type: 'const char *' vs 'A<'a'>'\e[0m
 char const* a = 0 ? (""
\e[0;1;32m             ^
\e[0m\e[1mtest.cpp:4:9: \e[0m\e[0;1;30mnote: \e[0mprevious definition is here\e[0m
 A<'a'> a = 1; +a; foo(a);
\e[0;1;32m        ^
\e[0m\e[1mtest.cpp:6:21: \e[0m\e[0;1;31merror: \e[0m\e[1minvalid operands to binary expression ('const char [1]' and 'const char [1]')\e[0m
                    + "")
\e[0;1;32m                    ^ ~~
\e[0m5 errors generated.
]]

gcc_color = convert_esc[[
\e[00;37m\e[Ktest.cpp:\e[m\e[K In function ‘\e[00;32m\e[Kint main()\e[m\e[K’:
\e[00;37m\e[Ktest.cpp:4:13:\e[m\e[K \e[01;31m\e[Kerror: \e[m\e[Kconversion from ‘\e[00;32m\e[Kint\e[m\e[K’ to non-scalar type ‘\e[00;32m\e[KA<'a'>\e[m\e[K’ requested
    4 |  A<'a'> a = \e[01;31m\e[K1\e[m\e[K; +a; foo(a);
      |             \e[01;31m\e[K^\e[m\e[K
\e[00;37m\e[Ktest.cpp:4:16:\e[m\e[K \e[01;31m\e[Kerror: \e[m\e[Kno match for ‘\e[00;32m\e[Koperator+\e[m\e[K’ (operand type is ‘\e[00;32m\e[KA<'a'>\e[m\e[K’)
    4 |  A<'a'> a = 1; \e[01;31m\e[K+a\e[m\e[K; foo(a);
      |                \e[01;31m\e[K^~\e[m\e[K
\e[00;37m\e[Ktest.cpp:4:24:\e[m\e[K \e[01;31m\e[Kerror: \e[m\e[Kcannot convert ‘\e[00;32m\e[KA<'a'>\e[m\e[K’ to ‘\e[00;32m\e[Kint\e[m\e[K’
    4 |  A<'a'> a = 1; +a; foo(\e[01;31m\e[Ka\e[m\e[K);
      |                        \e[01;31m\e[K^\e[m\e[K
      |                        \e[01;31m\e[K|\e[m\e[K
      |                        \e[01;31m\e[KA<'a'>\e[m\e[K
\e[00;37m\e[Ktest.cpp:1:10:\e[m\e[K \e[01;36m\e[Knote: \e[m\e[K  initializing argument 1 of ‘\e[00;32m\e[Kvoid foo(int)\e[m\e[K’
    1 | void foo(\e[01;36m\e[Kint\e[m\e[K){}
      |          \e[01;36m\e[K^~~\e[m\e[K
\e[00;37m\e[Ktest.cpp:5:14:\e[m\e[K \e[01;31m\e[Kerror: \e[m\e[Kconflicting declaration ‘\e[00;32m\e[Kconst char* a\e[m\e[K’
    5 |  char const* \e[01;31m\e[Ka\e[m\e[K = 0 ? (""
      |              \e[01;31m\e[K^\e[m\e[K
\e[00;37m\e[Ktest.cpp:4:9:\e[m\e[K \e[01;36m\e[Knote: \e[m\e[Kprevious declaration as ‘\e[00;32m\e[KA<'a'> a\e[m\e[K’
    4 |  A<'a'> \e[01;36m\e[Ka\e[m\e[K = 1; +a; foo(a);
      |         \e[01;36m\e[K^\e[m\e[K
\e[00;37m\e[Ktest.cpp:6:21:\e[m\e[K \e[01;31m\e[Kerror: \e[m\e[Kinvalid operands of types ‘\e[00;32m\e[Kconst char [1]\e[m\e[K’ and ‘\e[00;32m\e[Kconst char [1]\e[m\e[K’ to binary ‘\e[00;32m\e[Koperator+\e[m\e[K’
    5 |  char const* a = 0 ? (\e[32m\e[K""\e[m\e[K
      |                       \e[32m\e[K~~\e[m\e[K
      |                       \e[32m\e[K|\e[m\e[K
      |                       \e[32m\e[Kconst char [1]\e[m\e[K
    6 |                     \e[01;31m\e[K+\e[m\e[K \e[34m\e[K""\e[m\e[K)
      |                     \e[01;31m\e[K^\e[m\e[K \e[34m\e[K~~\e[m\e[K
      |                       \e[34m\e[K|\e[m\e[K
      |                       \e[34m\e[Kconst char [1]\e[m\e[K
]]

msvc = [[
test.cpp(4): error C2440: 'initializing': cannot convert from 'int' to 'A<97>'
test.cpp(4): note: No constructor could take the source type, or constructor overload resolution was ambiguous
test.cpp(4): error C2675: unary '+': 'A<97>' does not define this operator or a conversion to a type acceptable to the predefined operator
test.cpp(4): error C2088: '+': illegal for class
test.cpp(4): error C2664: 'void foo(int)': cannot convert argument 1 from 'A<97>' to 'int'
test.cpp(4): note: No user-defined-conversion operator available that can perform this conversion, or the operator cannot be called
test.cpp(1): note: see declaration of 'foo'
test.cpp(5): error C2040: 'a': 'const char *' differs in levels of indirection from 'A<97>'
test.cpp(6): error C2110: '+': cannot add two pointers
]]

gcc_nocolor = remove_color(gcc_color)
clang_nocolor = remove_color(clang_color)
assert(gcc_nocolor ~= gcc_color)


function selector(output)
  return select_formatter(output:gsub('\n.*', '\n'))
end

eq_formatter(gcc_formatter, true, selector(gcc_color))
eq_formatter(gcc_formatter, false, selector(gcc_nocolor))
eq_formatter(clang_formatter, true, selector(clang_color))
eq_formatter(clang_formatter, false, selector(clang_nocolor))
eq_formatter(msvc_formatter, false, selector(msvc))


function comp_format(output_comp, formatter, has_color)
  local t = {}

  local write = function(s)
    insert(t, s)
  end

  local proc = function(s)
    insert(t, '{' .. s .. '}')
  end

  local process = formatter(write, proc, 4, has_color)
  for line in output_comp:gmatch('[^\n]*\n') do
    process(line)
  end

  return table.concat(t)
end

gcc_result = convert_esc[[
\e[00;37m\e[Ktest.cpp:4:13:\e[m\e[K \e[01;31m\e[Kerror: \e[m\e[Kconversion from ‘\e[00;32m\e[Kint\e[m\e[K’ to non-scalar type ‘{A<'a'>}’ requested
\e[00;37m\e[Ktest.cpp:4:16:\e[m\e[K \e[01;31m\e[Kerror: \e[m\e[Kno match for ‘{operator+}’ (operand type is ‘{A<'a'>}’)
\e[00;37m\e[Ktest.cpp:4:24:\e[m\e[K \e[01;31m\e[Kerror: \e[m\e[Kcannot convert ‘{A<'a'>}’ to ‘\e[00;32m\e[Kint\e[m\e[K’
\e[00;37m\e[Ktest.cpp:1:10:\e[m\e[K \e[01;36m\e[Knote: \e[m\e[K  initializing argument 1 of ‘{void foo(int)}’
\e[00;37m\e[Ktest.cpp:5:14:\e[m\e[K \e[01;31m\e[Kerror: \e[m\e[Kconflicting declaration ‘{const char* a}’
\e[00;37m\e[Ktest.cpp:4:9:\e[m\e[K \e[01;36m\e[Knote: \e[m\e[Kprevious declaration as ‘{A<'a'> a}’
\e[00;37m\e[Ktest.cpp:6:21:\e[m\e[K \e[01;31m\e[Kerror: \e[m\e[Kinvalid operands of types ‘{const char [1]}’ and ‘{const char [1]}’ to binary ‘{operator+}’
]]
eq(comp_format(gcc_color, gcc_formatter, true), gcc_result)
eq(comp_format(gcc_nocolor, gcc_formatter, false), remove_color(gcc_result))

clang_result = convert_esc[[
\e[1mtest.cpp:4:9: \e[0m\e[0;1;31merror: \e[0m\e[1mno viable conversion from 'int' to '\e[m{A<'a'>}\e[1m'\e[0m
\e[0m\e[1mtest.cpp:2:22: \e[0m\e[0;1;30mnote: \e[0mcandidate constructor (the implicit copy constructor) not viable: no known conversion from 'int' to '{const A<'a'> &}' for 1st argument\e[0m
\e[0m\e[1mtest.cpp:2:22: \e[0m\e[0;1;30mnote: \e[0mcandidate constructor (the implicit move constructor) not viable: no known conversion from 'int' to '{A<'a'> &&}' for 1st argument\e[0m
\e[0m\e[1mtest.cpp:4:16: \e[0m\e[0;1;31merror: \e[0m\e[1minvalid argument type '\e[m{A<'a'>}\e[1m' to unary expression\e[0m
\e[0m\e[1mtest.cpp:1:6: \e[0m\e[0;1;30mnote: \e[0mcandidate function not viable: no known conversion from '{A<'a'>}' to 'int' for 1st argument\e[0m
\e[0m\e[1mtest.cpp:5:14: \e[0m\e[0;1;31merror: \e[0m\e[1mredefinition of 'a' with a different type: '\e[m{const char *}\e[1m' vs '\e[m{A<'a'>}\e[1m'\e[0m
\e[0m\e[1mtest.cpp:6:21: \e[0m\e[0;1;31merror: \e[0m\e[1minvalid operands to binary expression ('\e[m{const char [1]}\e[1m' and '\e[m{const char [1]}\e[1m')\e[0m
]]
eq(comp_format(clang_color, clang_formatter, true), clang_result)
eq(comp_format(clang_nocolor, clang_formatter, false), remove_color(clang_result))

msvc_result = [[
test.cpp(4): error C2440: '{initializing}': cannot convert from 'int' to '{A<97>}'
test.cpp(4): error C2675: unary '+': '{A<97>}' does not define this operator or a conversion to a type acceptable to the predefined operator
test.cpp(4): error C2088: '+': illegal for class
test.cpp(4): error C2664: '{void foo(int)}': cannot convert argument 1 from '{A<97>}' to 'int'
test.cpp(1): note: see declaration of 'foo'
test.cpp(5): error C2040: 'a': '{const char *}' differs in levels of indirection from '{A<97>}'
test.cpp(6): error C2110: '+': cannot add two pointers
]]
eq(comp_format(msvc, msvc_formatter, false), msvc_result)


function eq_colors(expected_colors, expected_error, colors, error)
  if colors then
    local t = {}
    for k,v in pairs(colors) do
      insert(t, k .. '=' .. v)
    end
    table.sort(t)
    colors = table.concat(t, ',')
  end
  eq_pair(expected_colors, expected_error, colors, error)
end

eq_colors('', nil, parse_colors'')
eq_colors('symbol=b', nil, parse_colors'symbol=b')
eq_colors('symbol=b', nil, parse_colors'symbol=b,')
eq_colors('symbol=c', nil, parse_colors'symbol=b,symbol=c')
eq_colors('symbol=c', nil, parse_colors'symbol=b,symbol=c,')
eq_colors('symbol=b,type=c', nil, parse_colors'symbol=b,type=c')
eq_colors('symbol=b,type=c', nil, parse_colors'symbol=b,type=c,')
eq_colors(nil, 'Unknown color: xxx, yyy', parse_colors'xxx=b,type=c,yyy=d')
eq_colors(nil, 'Invalid format at index 7', parse_colors'xxx=b,type')


highlight = highlighter({
  char='1',
  controlflow='2',
  identifier='3',
  keyword='4',
  keywordtype='5',
  keywordvalue='6',
  number='7',
  othersymbol='8',
  othertype='9',
  std='10',
  string='11',
  symbol='12',
  symseparator='13',
  type='14',
})

function eq_highlight(expected, result)
  eq(expected, result and result:gsub('\x1b', ''))
end

eq_highlight([[
[1m'a'[m [1m'\x1b'[m [1m'\032'[m [1m'\''[m
[2mif[m [3ma[m [4moperator[m [5mconst[m [6mfalse[m
[7m123[m [7m1.1[m [7m.23[m
[7m1'23e3[m [7m0x2'a3[m [7m031[m
[9mvalue_type[m [10mstd[m[8m::[m[10mfloor[m[8m()[m
[11m"a\x1bb\032c"[m [12m=[m [13m,[m [14mchar[m
]],
   highlight:match[[
'a' '\x1b' '\032' '\''
if a operator const false
123 1.1 .23
1'23e3 0x2'a3 031
value_type std::floor()
"a\x1bb\032c" = , char
]])

print(tostring(total) .. ' tests ; ' .. tostring(count_error) .. ' failures')
os.exit(count_error > 254 and 254 or count_error)