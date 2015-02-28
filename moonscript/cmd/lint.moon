
import insert from table
import Set from require "moonscript.data"
import Block from require "moonscript.compile"

{type: mtype} = require("moonscript.util").moon

-- globals allowed to be referenced
default_whitelist = Set {
  '_G'
  '_VERSION'
  'assert'
  'bit32'
  'collectgarbage'
  'coroutine'
  'debug'
  'dofile'
  'error'
  'getfenv'
  'getmetatable'
  'io'
  'ipairs'
  'load'
  'loadfile'
  'loadstring'
  'math'
  'module'
  'next'
  'os'
  'package'
  'pairs'
  'pcall'
  'print'
  'rawequal'
  'rawget'
  'rawlen'
  'rawset'
  'require'
  'select'
  'setfenv'
  'setmetatable'
  'string'
  'table'
  'tonumber'
  'tostring'
  'type'
  'unpack'
  'xpcall'

  "nil"
  "true"
  "false"
}

class LinterBlock extends Block
  new: (whitelist_globals=default_whitelist, ...) =>
    super ...
    @lint_errors = {}

    vc = @value_compilers
    @value_compilers = setmetatable {
      ref: (block, val) ->
        name = val[2]
        unless block\has_name(name) or whitelist_globals[name] or name\match "%."
          insert @lint_errors, {
            "accessing global `#{name}`"
            val[-1]
          }

        if unused = block.lint_unused_names
          unused[name] = nil

        vc.ref block, val
    }, __index: vc

    sc = @statement_compilers
    @statement_compilers = setmetatable {
      assign: (block, node) ->
        _, names, values = unpack node
        -- extract the names to be declared
        for name in *names
          real_name, is_local = block\extract_assign_name name
          -- already defined in some other scope
          unless is_local or real_name and not block\has_name real_name, true
            continue

          block.lint_unused_names or= {}
          block.lint_unused_names[real_name] = node[-1] or true

        sc.assign block, node
    }, __index: sc


  lint_check_unused: =>
    for name, pos in pairs @lint_unused_names
      insert @get_root_block!.lint_errors, {
        "assigned but unused `#{name}`"
        pos
      }

  render: (...) =>
    @lint_check_unused!
    super ...

  block: (...) =>
    @get_root_block or= -> @

    with super ...
      .block = @block
      .render = @render
      .get_root_block = @get_root_block
      .lint_check_unused = @lint_check_unused
      .value_compilers = @value_compilers
      .statement_compilers = @statement_compilers

format_lint = (errors, code, header) ->
  return unless next errors

  import pos_to_line, get_line from require "moonscript.util"
  formatted = for {msg, pos} in *errors
    if pos
      line = pos_to_line code, pos
      msg = "line #{line}: #{msg}"
      line_text = "> " .. get_line code, line

      sep_len = math.max #msg, #line_text
      table.concat {
        msg
        "="\rep sep_len
        line_text
      }, "\n"

    else
      msg

  table.insert formatted, 1, header if header
  table.concat formatted, "\n\n"


-- {
--   whitelist_globals: {
--     ["some_file_pattern"]: {
--       "some_var", "another_var"
--     }
--   }
-- }
whitelist_for_file = do
  local lint_config
  (fname) ->
    unless lint_config
      lint_config = {}
      pcall -> lint_config = require "lint_config"

    return default_whitelist unless lint_config.whitelist_globals
    final_list = {}
    for pattern, list in pairs lint_config.whitelist_globals
      if fname\match(pattern)
        for item in *list
          insert final_list, item

    setmetatable Set(final_list), __index: default_whitelist

lint_code = (code, name="string input", whitelist_globals) ->
  parse = require "moonscript.parse"
  tree, err = parse.string code
  return nil, err unless tree

  scope = LinterBlock whitelist_globals
  scope\stms tree
  scope\lint_check_unused!

  format_lint scope.lint_errors, code, name

lint_file = (fname) ->
  f, err = io.open fname
  return nil, err unless f
  lint_code f\read("*a"), fname, whitelist_for_file fname


{ :lint_code, :lint_file }
