#!/usr/bin/lua
-- SPDX-FileCopyrightText: 2022 Jonathan poelen <jonathan.poelen@gmail.com>
-- SPDX-License-Identifier: MIT

local insert = table.insert

local lpeg = require'lpeg'
local Cp = lpeg.Cp()
local Cc = lpeg.Cc
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


function clang_formatter(out, format, expression_threshold, translation, has_color)
  local state_line
  local state_note
  local state_color
  local state_cat

  local reformat_impl = function(p1, t1, ot1, p2, t2, ot2)
    local r1 = #t1 >= expression_threshold
    local r2 = t2 and #t2 >= expression_threshold

    if not (r1 or r2) then
      out:write(state_line)
      return
    end

    local line = state_line
    local reset = state_color and '\x1b[m' or ''
    local color = state_color and '\x1b[1m' or ''

    if r1 then
      out:write(line:sub(0, p1-1), reset)
      format(t1, state_cat)
      if not r2 then
        out:write(color, line:sub(p1+#t1))
        return
      end
      out:write(color, line:sub(p1+#t1, p2-1), reset)
    else -- if r2
      out:write(line:sub(0, p2-1), reset)
    end
    format(t2, state_cat)
    out:write(color, line:sub(p2+#t2))
  end

  local reformat = function(p1, t1, p2, t2)
    reformat_impl(p1, t1, t1, p2, t2, t2)
  end

  local diffreplacement = function(s)
    return #s ~= 4 --[[ \e[0m ]] and '/*{*/' or '/*}*/'
  end

  local reformat2 = function(p1, t1, p2, t2)
    local ot1 = t1
    local ot2 = t2

    -- remove color in
    -- ... no known conversion from 'Type<[...], xxx>' to 'Type<[...], yyy>'
    t1 = t1:gsub('\x1b%[[^m]*m', diffreplacement, 2)
    t2 = t2:gsub('\x1b%[[^m]*m', diffreplacement, 2)

    state_color = false
    reformat_impl(p1, t1, ot1, p2, t2, ot2)
  end

  local setcat = function(cat)
    state_cat = cat
  end
  local cat0 = Cc(1) / setcat
  local cat1 = Cc(2) / setcat
  local cat2 = Cc(3) / setcat

  -- test.cpp:3:21: error: bla bla ('{type1}' and '{type2}')
  -- test.cpp:3:21: error: bla bla '{type1}' (to|vs) '{type2}'
  -- test.cpp:3:12: error: bla bla '{type1}' to unary expression
  -- test.cpp:6:14: error: redefinition of 'ident' with a different type: '{type1}' vs '{type2}'
  -- test.cpp:6:14: note: in instantiation of template class '{type}' requested here
  -- /!\ with {type} = A<'a'> => '{type}' => 'A<'a'>'
  local suffix = has_color and "\x1b[0m\n" or "\n"
  local type1 = P"('" * Cp * CAfter"' and '" * Cp * CUntil("')" .. suffix)
  local type2 = P"'" * Cp * CUntil(P"' to " + "' vs ")
              * ( P"' to unary"
                + ( P"' to '" + P"' vs '") * Cp
                  * CUntil(P"' for " + ("'" .. suffix))
                )
  local typeA = Cp * CAfter"' " * After'\n'
  local typeB = Cp * CAfter"' to '" * Cp * CAfter"' " * After'\n'

  local error = has_color and '\x1b[0;1;31merror: \x1b[0m' or ': error: '
  local warn  = has_color and '\x1b[0;1;35mwarning: \x1b[0m' or ': warning: '
  local note  = P(has_color and '\x1b[0;1;30mnote: \x1b[0m' or ': note: ')
  local redefinition = P(error)
                     * ( P((has_color and '\x1b[1m' or '') .. "redefinition of '")
                       * Until"' with " * 7
                       )
                     * cat0

  local set_note = function()
    state_color = false
    state_note = true
    state_cat = 3
  end
  local patt_note = (has_color and note / set_note or note * cat2)
                  * ( P'in instantiation of ' * After"'" * typeA / reformat
                    + P'candidate constructor ('^-1 * Until(S"'(") * type2 / reformat
                    )
  if has_color then
    patt_note = note * 'candidate constructor not viable: no known conversion from \''
                     * cat2 * (typeB / reformat2)
              + patt_note
  end

  local patt = Until(note + warn + error)
             * ( patt_note
               + redefinition * Until(S"'(") * (type2 / reformat)
               + (P(warn) * cat1 + P(error) * cat0)
                * Until(S"'(") * ((type1 + type2) / reformat)
               )

  if has_color then
    -- colored line without ^
    patt = P'\x1b' * -P'[0;1;32m' * patt
  else
    patt = -P' ' * patt
  end

  return function(line)
    state_line = line
    state_note = false
    state_color = has_color
    return patt:match(line)
  end
end

local function consume_formatter(out, format, expression_threshold, create_pattern)
  local state_line
  local state_pos
  local state_cat

  local reformat = function(p1, t, p2)
    if #t >= expression_threshold then
      out:write(state_line:sub(state_pos, p1-1))
      format(t, state_cat)
      state_pos = p2
    end
  end

  local setcat = function(cat)
    state_cat = cat
  end

  local patt = create_pattern(reformat, setcat)
             * (Cp / function()
                  out:write(state_line:sub(state_pos))
                end)

  return function(line)
    state_line = line
    state_pos = 1
    return patt:match(line)
  end
end

function gcc_formatter(out, format, expression_threshold, translation, has_color)
  return consume_formatter(out, format, expression_threshold, function(reformat, setcat)
    -- test.cpp:4:12: error: no match for ‘operator+’ (operand type is ‘A<'a'>’)
    -- test.cpp:4:12: note: ‘{type1}’ is not usable as a {type2} function because:
    -- test.hpp: In instantiation of ‘{type}’:
    -- test.hpp:66:124:   required from ‘{type}’
    local patt
    if has_color then
      local k = P'\x1b[K'^-1
      patt = P'\x1b' * Until'm' * 1 * k
           * CUntil'\x1b' * '\x1b[m' * k
    else
      patt = CUntil'’'
    end

    local prefix = has_color and '\x1b[K' or ': '
    local note  = prefix .. translation.note    .. ': '
    local warn  = prefix .. translation.warning .. ': '
    local error = prefix .. translation.error   .. ': '

    patt = ( Until(P(note) + warn + error)
           * ( note  * Cc(3) / setcat
             + warn  * Cc(2) / setcat
             + error * Cc(1) / setcat
             )
           + Cc(4) / setcat
           )
           * (After'‘' * Cp * patt * Cp / reformat)^1

    return -P' ' * patt
  end)
end

function msvc_formatter(out, format, expression_threshold, translation)
  return consume_formatter(out, format, expression_threshold, function(reformat, setcat)
    -- test.cpp(4): error C2664: 'void foo(int)': cannot convert argument 1 from 'A<97>' to 'int'
    -- type A<'a'> is displayed as A<97>
    local patt = After" '"
               * ( (R('az','AZ')^1 + S'=<>!&|^~+-*%/,'^1) * "'"
                 + Cp * CUntil"'" * Cp * 1 / reformat
                 )
    return After': '
         * ( P(translation.note .. ':') * Cc(3) / setcat
           + P(translation.warning .. ' ') * 5 * Cc(2) / setcat
           + P(translation.error .. ' ') * 5 * Cc(1) / setcat
           )
         * patt^1
  end)
end

local _select_patt_cache
function select_formatter(line)
  local gcc_pos = line:find('‘', 0, true)
  if gcc_pos then
    return gcc_formatter, (line:byte(gcc_pos+3) == 0x1b)
  end

  if not _select_patt_cache then
    -- test.cpp(4): (msvc)
    -- or
    -- test.cpp:4:9: (clang)
    local digits = R'09'^1
    _select_patt_cache = Until( '(' * digits * '): '
                              + ':' * digits * ':' * digits * ': '
                              )
                              * ( P'(' * Cc(1)
                                + P':' * Cc(2)
                                )
  end

  local x = _select_patt_cache:match(line)

  if x == 2 then
    return clang_formatter, (line:byte() == 0x1b)
  end

  if x == 1 then
    return msvc_formatter, false
  end

  return nil, nil
end


function parse_key_value(str, kargs, err_name)
  local table_result = {}
  local errors = {}

  local patt = (C(Until'=') * 1 * C(Until0',') / function(name, value)
    if kargs[name] then
      table_result[name] = value
    else
      insert(errors, name)
    end
  end * P','^-1)^0 * Cp

  local pos = patt:match(str)
  if pos ~= #str + 1 then
    return nil, 'Invalid format at index ' .. tostring(pos)
  end

  if #errors ~= 0 then
    return nil, 'Unknown ' .. err_name .. ': ' .. table.concat(errors, ', ')
  end

  return table_result
end

local kw_colors = {
  char=true,
  comment=true,
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
  return parse_key_value(str, kw_colors, 'color')
end

function parse_translation(str)
  return parse_key_value(str, {note=true, error=true, warning=true}, 'color')
end

function parse_filter_line(str)
  local t, err = parse_key_value(str, {note=true, error=true, warning=true, context=true}, 'category')
  if t then
    for k,v in pairs(t) do
      v = v:byte()
      if v == 0x32 --[[2]] or v == 0x68 --[[h]] then
        t[k] = 2
      elseif v == 0x31 --[[1]] or v == 0x63 --[[c]] then
        t[k] = 1
      else
        t[k] = 0
      end
    end
  end
  return t, err
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
  local compute_pattern = function(style, patt)
    -- apply style on previous patterns
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

  local symbols = (S'=<>!&|^~+-*%' + P'/' * -S'/*')^1
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
  local number = '0b' * tocppint(S'01')
               + P'.'^-1 * int * (P'.'^-1 * int)^-1 * (S'eE' * int)^-1
  local comment = P'/*' * Until0'*/' * P(2)^-1
                + P'//' * Until0'\n'
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

  local accu_patt = ws

  local previous_style
  local previous_patterns

  local push_color = function(k, patt)
    local style = colors[k]

    if style == previous_style then
      previous_patterns = previous_patterns + patt
      return
    end

    accu_patt = accu_patt + compute_pattern(previous_style, previous_patterns)

    previous_style = style
    previous_patterns = patt
  end

  local std_color = colors['std']
  local othersymbol_color = colors['othersymbol']

  previous_style = colors['comment']
  previous_patterns = comment
  push_color('symbol', symbols)
  push_color('symseparator', sep_symbols)
  push_color('number', number) -- contains .
  push_color('othersymbol', other_symbols) -- contains .
  push_color('parenthesis', parent)
  push_color('brace', brace)
  push_color('bracket', bracket)
  push_color('char', char)
  push_color('string', string)
  push_color('controlflow', control_flow * -noident)
  push_color('keywordvalue', kw_value * -noident)
  push_color('keyword', keywords * -noident)
  push_color('keywordtype', kw_type * -noident)
  push_color('type', type)
  push_color('othertype', other_type * -noident)
  if othersymbol_color == std_color then
    push_color('std', P'std::' * ident)
    push_color('identifier', ident)
    accu_patt = accu_patt
              + compute_pattern(previous_style, previous_patterns)
  else
    accu_patt = accu_patt
              + compute_pattern(previous_style, previous_patterns)
              + compute_pattern(std_color, P'std')
              * compute_pattern(othersymbol_color, P'::')
              * compute_pattern(std_color, ident)
              + compute_pattern(colors['identifier'], ident)
  end

  return lpeg.Cs((accu_patt + accu_patt + 1)^0)
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
    :option('-I --input-type', 'compiler formatter are auto, gcc, gcc-color, clang, clang-color and msvc\nDefault value is CPP_PRETTY_OUTPUT_INPUT_TYPE or auto')
    :choices{'auto', 'gcc', 'gcc-color', 'clang', 'clang-color', 'msvc'}
    :argname'<TYPE>'
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
  parser
    :option('-t --translation', 'translation for error, warning and note. Format is word=newword,...')
    :argname'<TRANSLATIONS>'
    :convert(parse_translation)
  parser
    :option('-T --filter-line', 'apply the filter only on certain lines. Format is word=value,... with word as error, warning, note or context and value are 0 / note, 1 / cmd or 2 / highlight')
    :argname'<CATEGORIES>'
    :convert(parse_filter_line)

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

local filter_line = args.filter_line or {}
filter_line = {
  filter_line.error or 1,
  filter_line.warning or 1,
  filter_line.note or 1,
  filter_line.context or 1,
}

if low_threshold or (args.highlighter_with_module and filter_type == 'module') then
  local colors = args.filter_colors

  -- parse environment variable or error
  if not colors then
    local str_colors = os.getenv'CPP_PRETTY_OUTPUT_COLORS'
    if str_colors then
      local parsed_colors, msg_error = parse_colors(str_colors)
      if parsed_colors then
        colors = parsed_colors
      else
        io.stderr:write('CPP_PRETTY_OUTPUT_COLORS environment variable: '
                      .. msg_error .. '\n')
        os.exit(1)
      end
    end
  end

  -- init colors
  colors = colors or {}
  colors = {
    char = colors.char or colors.string or '38;5;114',
    comment = colors.controlflow or '38;5;241',
    controlflow = colors.controlflow or '38;5;215;1',
    identifier = colors.identifier or '38;5;149',
    keyword = colors.keyword or '38;5;203',
    keywordtype = colors.keywordtype or '38;5;75;3',
    keywordvalue = colors.keywordvalue or '38;5;141',
    number = colors.number or '38;5;179',
    othertype = colors.othertype or '38;5;75',
    othersymbol = colors.othersymbol or '38;5;231',
    parenthesis = colors.parenthesis or colors.parent or colors.othersymbol or '38;5;231',
    bracket = colors.bracket or colors.othersymbol or '38;5;231',
    brace = colors.brace or colors.othersymbol or '38;5;231',
    std = colors.std or '38;5;176',
    string = colors.string or '38;5;114',
    symbol = colors.symbol or '38;5;44',
    symseparator = colors.symseparator or '38;5;227',
    type = colors.type or '38;5;81',
  }

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
    local formatters = {
      gcc=gcc_formatter,
      msvc=msvc_formatter,
      clang=clang_formatter,
      ['gcc-color']=gcc_formatter,
      ['clang-color']=clang_formatter,
    }

    -- init input_type
    local input_type = os.getenv'CPP_PRETTY_OUTPUT_INPUT_TYPE'
    if input_type and input_type ~= '' then
      if not formatters[input_type] then
        io.stderr:write("CPP_PRETTY_OUTPUT_INPUT_TYPE environment variable: Unknown value: '"
                      .. input_type
                      .. "'. Must be one of 'auto', 'gcc', 'gcc-color', 'clang', 'clang-color', 'msvc'\n")
        os.exit(1)
      end
    else
      input_type = args.input_type or 'auto'
    end

    -- get formatter
    local formatter, has_color
    if input_type == 'auto' then
      while true do
        formatter, has_color = select_formatter(line)
        if formatter then
          break
        end
        -- formatter not found, display the current line and read the next one
        output:write(line)
        line = input:read'L'
        if not line then
          return 0
        end
      end
    else
      formatter = formatters[input_type]
      has_color = input_type:byte(-1) == 0x72 -- r
    end

    local reformat
    -- apply proccess_format or highlight
    if proccess_format ~= write_highlight and fallback_on_highlight then
      local old_expression_threshold = expression_threshold
      expression_threshold = 0
      reformat = function(str, cat)
        cat = filter_line[cat]
        if cat == 1 and #str >= old_expression_threshold then
          proccess_format(str)
        elseif cat >= 1 then
          output:write(highlight:match(str))
        else
          output:write(str)
        end
      end
    else
      reformat = function(str, cat)
        if filter_line[cat] >= 1 then
          output:write(highlight:match(str))
        else
          output:write(str)
        end
      end
    end

    local translation = args.translation or {}
    translation = {
      note = translation.note or 'note',
      error = translation.error or 'error',
      warning = translation.warning or 'warning',
    }

    local process = formatter(output, reformat, expression_threshold,
                              translation, has_color)

    repeat
      if #line < line_threshold or not process(line) then
        output:write(line)
      end
      line = input:read'L'
    until not line
  end
end
