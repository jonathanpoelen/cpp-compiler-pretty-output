#!/usr/bin/lua
-- SPDX-FileCopyrightText: 2022 Jonathan poelen <jonathan.poelen@gmail.com>
-- SPDX-License-Identifier: MIT

local insert = table.insert

local lpeg = require'lpeg'
local Cp = lpeg.Cp()
local C = lpeg.C
local P = lpeg.P
local R = lpeg.R
local S = lpeg.S

local function After(patt)
  local patt2 = patt
  if type(patt) == 'string' then
    patt2 = #patt
    patt = P(patt)
  end
  return (1-patt)^1 * patt2
end

local function CAfter(patt)
  local patt2 = patt
  if type(patt) then
    patt2 = #patt
    patt = P(patt)
  end
  return C((1-patt)^1) * patt2
end

local function Until(patt)
  return (1-P(patt))^1
end

local function Until0(patt)
  return (1-P(patt))^0
end

local function CUntil(patt)
  return C((1-P(patt))^1)
end


function clang_formatter(write, format, expression_threshold, has_color)
  local state_line;
  local state_color;

  local reformat = function(p1, t1, p2, t2)
    local r1 = #t1 >= expression_threshold
    local r2 = t2 and #t2 >= expression_threshold

    if not (r1 or r2) then
      write(state_line)
      return
    end

    local line = state_line
    local reset = state_color and '\x1b[m' or ''
    local color = state_color and '\x1b[1m' or ''

    if r1 then
      write(line:sub(0, p1-1))
      write(reset)
      format(t1)
      write(color)
      if not r2 then
        write(line:sub(p1+#t1))
        return
      end
      write(line:sub(p1+#t1, p2-1))
    else -- if r2
      write(line:sub(0, p2-1))
    end
    write(reset)
    format(t2)
    write(color)
    write(line:sub(p2+#t2))
  end

  -- test.cpp:3:21: error: bla bla ('{type1}' and '{type2}')
  -- test.cpp:3:21: error: bla bla '{type1}' (to|vs) '{type2}'
  -- test.cpp:3:12: error: bla bla '{type1}' to unary expression
  -- test.cpp:6:14: error: redefinition of 'ident' with a different type: '{type1}' vs '{type2}'
  -- /!\ with {type} = A<'a'> => '{type}' => 'A<'a'>'
  local suffix = has_color and "\x1b[0m\n" or "\n"
  local type1 = P"('" * Cp * CAfter"' and '" * Cp * CUntil("')" .. suffix)
  local type2 = P"'" * Cp * CUntil(P"' to " + "' vs ")
              * ( P"' to unary"
                + ( P"' to '" + P"' vs '") * Cp
                  * CUntil(P"' for " + ("'" .. suffix))
                )

  local error = has_color and '\x1b[0;1;31merror: \x1b[0m' or ': error: '
  local warn = has_color and '\x1b[0;1;35mwarning: \x1b[0m' or ': warning: '
  local note = has_color and '\x1b[0;1;30mnote: \x1b[0m' or ': note: '
  local redefinition = P(error)
                     * ( P((has_color and '\x1b[1m' or '') .. "redefinition of '")
                       * Until"' with " * 7
                       )^-1

  local set_nocolor = function() state_color = false end
  local candidate_ctor = (has_color and P(note) / set_nocolor or P(note))
                       * P'candidate constructor ('^-1

  local patt = Until(P(note) + warn + error)
             * (candidate_ctor + redefinition + #warn)
             * Until(S"'(") * ((type1 + type2) / reformat)

  if has_color then
    patt = P'\x1b' * patt
  end

  return function(line)
    state_line = line
    state_color = has_color
    return patt:match(line)
  end
end

local function consume_formatter(write, format, expression_threshold, create_pattern)
  local state_line
  local state_pos

  local reformat = function(p1, t, p2)
    if #t >= expression_threshold then
      write(state_line:sub(state_pos, p1-1))
      format(t)
      state_pos = p2
    end
  end

  local patt = create_pattern(reformat) * (Cp / function()
    write(state_line:sub(state_pos))
  end)

  return function(line)
    state_line = line
    state_pos = 1
    return patt:match(line)
  end
end

function gcc_formatter(out, format, expression_threshold, has_color)
  return consume_formatter(out, format, expression_threshold, function(reformat)
    -- test.cpp:4:12: error: no match for ‘operator+’ (operand type is ‘A<'a'>’)
    local patt
    if has_color then
      local k = P'\x1b[K'^-1
      patt = P'\x1b' * Until'm' * 1 * k
           * CUntil'\x1b' * '\x1b[m' * k
    else
      patt = CUntil'’'
    end

    patt = Until(P'error: ' + 'note: ' + 'warning: ') * 9
         * (After'‘' * Cp * patt * Cp / reformat)^1

    if has_color then
      return P'\x1b' * patt
    end

    return patt
  end)
end

function msvc_formatter(out, format, expression_threshold)
  return consume_formatter(out, format, expression_threshold, function(reformat)
    -- test.cpp(4): error C2664: 'void foo(int)': cannot convert argument 1 from 'A<97>' to 'int'
    -- type A<'a'> is displayed as A<97>
    return (After" '" * Cp * CUntil"'" * Cp * 1 / reformat)^1
  end)
end

function select_formatter(line)
  local is_gcc = line:find('‘', 0, true)

  -- with ANSI color
  if line:byte() == 0x1b then
    if is_gcc then
      return gcc_formatter, true
    end
    return clang_formatter, true
  end

  if is_gcc then
    return gcc_formatter, false
  end

  -- test.cpp(4): (msvc)
  -- or
  -- test.cpp:4:9: (clang)
  local c = (Until(S':(') * C(1)):match(line)
  if c == ':' then
    return clang_formatter, false
  end

  return msvc_formatter, false
end


local kw_colors = {
  char=true,
  controlflow=true,
  identifier=true,
  keyword=true,
  keywordtype=true,
  keywordvalue=true,
  number=true,
  othersymbol=true,
  parenthesis=true,
  brace=true,
  bracket=true,
  othertype=true,
  std=true,
  string=true,
  symbol=true,
  symseparator=true,
  type=true,
}

function parse_colors(str)
  local colors = {}
  local errors = {}

  local patt = (C(Until'=') * 1 * C(Until0',') / function(name, style)
    if kw_colors[name] then
      colors[name] = style
    else
      insert(errors, name)
    end
  end * P','^-1)^0 * Cp

  local pos = patt:match(str)
  if pos ~= #str + 1 then
    return nil, 'Invalid format at index ' .. tostring(pos)
  end

  if #errors ~= 0 then
    return nil, 'Unknown color: ' .. table.concat(errors, ', ')
  end

  return colors
end

function colors_list()
  local t = {}
  for k,_ in pairs(kw_colors) do
    insert(t, k)
  end
  table.sort(t)
  return t
end

function highlighter(colors)
  local fns = {}
  local color = function(k, patt)
    local style = colors[k]
    if #style ~= 0 then
      local fn = fns[style]
      if not fn then
        local prefix = '\x1b[' .. style .. 'm'
        fn = function(s) return prefix .. s .. '\x1b[m' end
        fns[style] = fn
      end
      return patt / fn
    end
    return patt
  end

  local tocppint = function(patt)
    patt = patt^1
    return patt * ("'" * patt)^0
  end

  local alpha = R('az','AZ')
  local alnum = R('az','AZ','09')
  local hex = R('09','af','AF')

  local symbols = S'=<>!&|^~+-*/%'^1
  local other_symbols = S':?.'^1
  local bracket       = S'[]'^1
  local parent        = S'()'^1
  local brace         = S'{}'^1
  local sep_symbols = S',;'
  local specialchar = P'\\x' * hex^2
                    + P'\\0' * R'07'^0
                    + P'\\' * 1
  local char = "'" * (specialchar + 1) * P"'"^-1
  local string = '"' * (Until(S'\\"') + (P'\\' * 1))^0 * P'"'^-1
  local int = '0x' * tocppint(hex) + tocppint(R'09')
  local number = P'.'^-1 * int * (P'.'^-1 * int)^-1 * (S'eE' * int)^-1
  local ident = alpha^1 * (alnum^1 + '_')^0
  local noident = alnum + '_'
  local ws = S' \t'^1

  local control_flow = P'break' + 'case' + 'catch' + 'continue'
                     + 'co_' * (P'await' + 'return' + 'yield')
                     + 'do' + 'else' + 'for' + 'goto' + 'if'
                     + 'return' + 'switch' + 'throw' + 'try'
                     + 'while'

  local kw_value = P'false' + 'nullptr' + 'this' + 'true'

  local kw_type = P'const' + 'explicit' + 'mutable' + 'register'
                + 'static' + 'thread_local' + 'volatile'

  local keywords = 'align' * (P'as' + 'of') + 'auto'
                 + 'class' + 'concept'
                 + P'const' * (P'expr' + 'eval' + 'init' + '_cast')
                 + 'decltype' + 'default' + 'delete' + 'dynamic_cast'
                 + 'enum' + 'export' + 'extern'
                 + 'final' + 'friend'
                 + 'inline'
                 + 'namespace' + 'new' + 'noexcept'
                 + 'operator'
                 + 'private' + 'protected' + 'public'
                 + 'reinterpret_cast' + 'requires'
                 + 'sizeof' + 'static_assert' + 'static_cast'
                 + 'struct'
                 + 'template'
                 + 'typedef' + 'typeid' + 'typename'
                 + 'union' + 'using'
                 + 'virtual'
                 + 'final' + 'override' + 'import' + 'module'

  local type = P'void' + 'long' + 'short' + 'unsigned' + 'signed'
             + 'float' + 'double' + 'wchar' + 'bool'
             + S'su'^-1 * 'size_t'
             + P'u'^-1 * (
                 'int' * (P'_fast' + '_least' + 'max' + 'ptr')^-1
               + 'char'
             ) * R'09'^0 * P'_t'^-1

  local type_suffix = P'_type' + '_t'
  local other_type = (alnum^1 + '_' - type_suffix)^1 * type_suffix

  local patt = lpeg.Cs((ws
             + color('symbol', symbols)
             + color('symseparator', sep_symbols)
             + color('number', number) -- contains .
             + color('othersymbol', other_symbols) -- contains .
             + color('brace', brace)
             + color('bracket', bracket)
             + color('parenthesis', parent)
             + color('char', char)
             + color('string', string)
             + color('controlflow', control_flow * -noident)
             + color('keywordvalue', kw_value * -noident)
             + color('keyword', keywords * -noident)
             + color('keywordtype', kw_type * -noident)
             + color('type', type)
             + color('othertype', other_type * -noident)
             + color('std', P'std') * color('othersymbol', P'::') * color('std', ident)
             + color('identifier', ident)
             + 1
             )^0)

  return patt
end


function parse_cli(defaults, arg)
  local file_map = {
    ['/dev/stdin']=io.stdin,
    ['/dev/stdout']=io.stdout,
    ['/dev/stderr']=io.stderr,
  }
  local function _tofile(filename, default)
    if filename or filename == '-' then
      return default
    end

    local file = file_map[filename]
    if file then
      return file
    end

    return io.open(filename)
  end

  local function tofile(default)
    return function(filename)
      return _tofile(filename, default)
    end
  end

  local function set_and_reset_column(args, k, s)
    args[k] = s
    args.column = nil
  end

  local argparse = require'argparse'

  local parser = argparse()
    :name'cpp-compiler-pretty-output'
    :description'C++ Pretty output'
    :epilog'Project url: https://github.com/jonathanpoelen/cpp-template-tree/'
    :add_complete()


  parser:flag'--version'
    :action(function() print("1.0.0") os.exit(0) end)
  parser
    :argument('cmd', 'Command used for formatting. Default is CPP_PRETTY_OUTPUT_CMD environment variable or a basic syntax highlighter.\n/!\\ Must be manually escaped.')
    :args'*'
    :action(function(args, k, t)
      if #t ~= 0 then
        args[k] = table.concat(t, ' ')
      end
      parser._handle_options = false
    end)
  parser
    :option('-i --input', 'Input file. - is equivalent to stdin. Default is stdin')
    :argname'<file>'
    :default(defaults.input)
    :convert(tofile(defaults.input))
  parser
    :option('-o --output', 'Output file. - is equivalent to stdout. Default is stdin')
    :argname'<file>'
    :default(defaults.output)
    :convert(tofile(defaults.output))
  parser
    :option('-p --prefix', 'Insert a string before each formatting')
    :argname'<str>'
    :action(set_and_reset_column)
  parser
    :option('-s --suffix', 'Insert a string after each formatting')
    :argname'<str>'
    :action(set_and_reset_column)
  parser
    :option('-C --color', 'Color for prefix and suffix')
    :argname'<ANSI_STYLE>'
    :default(defaults.color)
  parser
    :option('-c --column', 'When a valid number, automatic calculation --prefix and --suffix')
    :argname'<COLUMNS>'
  parser
    :option('--char', 'Character for --column')
    :default(defaults.char)
    :argname'<COLUMNS>'
  parser
    :option('-l --line-threshold', 'Number of characters needed before reformatting a line')
    :argname'<N>'
    :convert(tonumber)
  parser
    :option('-e --expression-threshold', 'Number of characters needed before reformatting a expression')
    :argname'<N>'
    :convert(tonumber)
  parser
    :option('-f --filter', [[
'command' use cmd parameter as a shell argument.
'module' use cmd parameter as a lua module that takes 3 or 4 parameters:
 - output (file object)
 - prefix (string)
 - suffix (string)
 - highlighter (function(str):string with -M)
'highlight' is a basic C++ highlighter ; cmd parameter is ignored.
Note: CPP_PRETTY_OUTPUT_FORCE_HIGHLIGH=1 variable environment force -f highlight]])
    :choices{'command', 'module', 'highlight'}
    :argname'<TYPE>'
    -- :default'command' -- don't use, this disables -E
  parser
    :flag('-E', 'alias of -f highlight')
    :target'filter'
    :action(function(args) args.filter = 'highlight' end)
  parser
    :option('-I --input-type')
    :choices{'auto', 'gcc', 'clang', 'msvc'}
    :argname'<TYPE>'
    :default(defaults.input_type)
  parser
    :option('-F --filter-colors', [[
ANSI styles for basic C++ highlighter.
Read CPP_PRETTY_OUTPUT_COLORS environment variable by default.
Format: name=style[,name=style,...]
name are
  - ]] .. table.concat(colors_list(), '\n  - '))
    :argname'<STYLES>'
    :convert(parse_colors)
  parser
    :flag('-M --highlighter-with-module', 'Add basic C++ highlighter with -f module')
  parser
    :flag('-n --highlight-when-not-processed', 'Use basic C++ highlighter when reformatting is not applied (-e option)')
    :default(defaults.highlighter_with_module)
  parser
    :flag('-N --disable-highlight-when-not-processed', 'opposite of -n')
    :target'highlight_when_not_processed'
    :action'store_false'

  return parser:parse(arg)
end

function normalize_args(args)
  local column = args.column or os.getenv('COLUMNS')
  if column and not (args.prefix and args.suffix) then
    local n = tonumber(column)
    if n and n > 0 then
      local line = string.rep(args.char, n)
      args.prefix = args.prefix or '\n' .. line
      args.suffix = args.suffix or line
    end
  end

  args.prefix = args.prefix or ''
  args.suffix = args.suffix or ''

  local color = args.color
  if #color ~= 0 then
    if #args.prefix ~= 0 then
      args.prefix = '\x1b[' .. color .. 'm' .. args.prefix .. '\x1b[0m'
    end
    if #args.suffix ~= 0 then
      args.suffix = '\n\x1b[' .. color .. 'm' .. args.suffix .. '\x1b[0m'
    end
  end
end


args = {
  char='─',
  color='38;5;238',
  input=io.input(),
  output=io.output(),
  input_type='auto',
  highlighter_with_module=true,
}
if #arg > 0 then
  if arg[1]:byte() == 0x2D --[['-']] then
    args = parse_cli(args)
  else
    args.cmd = table.concat(arg, ' ')
  end
end
normalize_args(args)

local filter_type = args.filter
local cmd = args.cmd or os.getenv'CPP_PRETTY_OUTPUT_CMD'

local is_highlight = (filter_type == 'highlight' or os.getenv'CPP_PRETTY_OUTPUT_FORCE_HIGHLIGH' == '1')
local use_highlight = not cmd or #cmd == 0 or is_highlight
local fallback_on_highlight = (args.highlight_when_not_processed ~= false)
local low_threshold = use_highlight or fallback_on_highlight

local input = args.input
local output = args.output
local line_threshold = args.line_threshold or (low_threshold and 30 or 120)
local expression_threshold = args.expression_threshold or (use_highlight and 3 or 80)
local prefix = args.prefix
local suffix = args.suffix

if low_threshold or (args.highlighter_with_module and filter_type == 'module') then
  local colors = args.filter_colors or os.getenv'CPP_PRETTY_OUTPUT_COLORS' or {}
  colors.string = colors.string or '38;5;114'
  colors.char = colors.char or colors.string
  colors.controlflow = colors.controlflow or '38;5;215;1'
  colors.identifier = colors.identifier or '38;5;149'
  colors.keyword = colors.keyword or '38;5;203'
  colors.keywordtype = colors.keywordtype or '38;5;75;3'
  colors.keywordvalue = colors.keywordvalue or '38;5;141'
  colors.number = colors.number or '38;5;179'
  colors.othertype = colors.othertype or '38;5;75'
  colors.othersymbol = colors.othersymbol or '38;5;231'
  colors.parenthesis = colors.parenthesis or colors.othersymbol
  colors.bracket = colors.bracket or colors.othersymbol
  colors.brace = colors.brace or colors.othersymbol
  colors.std = colors.std or '38;5;176'
  colors.symbol = colors.symbol or '38;5;44'
  colors.symseparator = colors.symseparator or '38;5;227'
  colors.type = colors.type or '38;5;81'
  highlight = highlighter(colors)
  write_highlight = function(str)
    output:write(highlight:match(str))
  end
end

if use_highlight then
  proccess_format = write_highlight
elseif filter_type == 'module' then
  proccess_format = require(args.cmd)(output, prefix, suffix,
                                      highlight and function(str)
                                        return highlight:match(str)
                                      end)
else
  function proccess_format(str)
    local coproc, err = io.popen(cmd, 'w')
    if err then
      error(err)
    end

    output:write(prefix)
    output:flush()
    coproc:write(str)
    coproc:close()
    output:write(suffix)
  end
end


local line = input:read'L'

if is_highlight then
  while line do
    proccess_format(line)
    line = input:read'L'
  end
else
  if line then
    local formatter, has_color
    if args.input_type == 'auto' then
      formatter, has_color = select_formatter(line)
    else
      local formatters = {
        gcc=gcc_formatter,
        msvc=msvc_formatter,
        clang=clang_formatter,
      }
      formatter = formatters[filter_type]
      has_color = line:byte() == '\x1b'
    end

    function writter(s)
      output:write(s)
    end

    -- apply proccess_format or highlight
    if proccess_format ~= write_highlight and fallback_on_highlight then
      local old_proccess_format = proccess_format
      local old_expression_threshold = expression_threshold
      expression_threshold = 0
      proccess_format = function(str)
        if #str >= old_expression_threshold then
          old_proccess_format(str)
        else
          output:write(highlight:match(str))
        end
      end
    end

    local process = formatter(writter, proccess_format, expression_threshold, has_color)

    repeat
      if #line < line_threshold or not process(line) then
        output:write(line)
      end
      line = input:read'L'
    until not line
  end
end
