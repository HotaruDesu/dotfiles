-- Use Blink's real edit-range and offset compensation, with controlled replies.
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.rtp:prepend(root)
vim.opt.rtp:append(vim.fn.stdpath "data" .. "/lazy/blink.cmp")
local headers = require "lunavim.completion.headers"
local api, kinds = vim.api, vim.lsp.protocol.CompletionItemKind
local dir = vim.fn.tempname()
api.nvim_buf_set_name(0, dir .. "/source.cpp")
vim.o.virtualedit = "onemore"

local function pair(before, after, name, target, consume_next)
  local col = #before
  local start = assert(before:find '[^/<"]*$') - 1
  api.nvim_buf_set_lines(0, 0, -1, false, { before .. after })
  api.nvim_win_set_cursor(0, { 1, col })
  local ctx = {
    bufnr = api.nvim_get_current_buf(),
    get_line = api.nvim_get_current_line,
    get_cursor = function()
      return api.nvim_win_get_cursor(0)
    end,
  }
  local function item(source, insertion, stop)
    return {
      kind = kinds.File,
      source_id = source,
      label = insertion,
      cursor_column = start,
      textEdit = { newText = insertion, range = { start = { line = 0, character = start }, ["end"] = { line = 0, character = stop } } },
    }
  end
  local path = item("path", name, start)
  path.data = { full_path = dir .. "/" .. target }
  local lsp = item("lsp", name .. '"', start + (consume_next and 1 or 0))
  return ctx, path, lsp
end

local function check(ctx, items, hidden, selected, full, ranks)
  local actual = headers.shadowed(ctx, items, ranks or vim.tbl_map(function()
    return 1
  end, items), selected, full)
  assert(vim.tbl_count(actual) == #hidden, "Unexpected number of hidden headers: " .. vim.inspect(actual))
  for _, item in ipairs(hidden) do
    assert(actual[item], "Wrong source kept")
  end
end

local ctx, path, lsp = pair('#include "./engine/ren', '" // comment', "renderer.hpp", "engine/renderer.hpp", true)
check(ctx, { path, lsp }, { path })
check(ctx, { lsp, path }, { path }, nil, true)
check(ctx, { path, lsp }, { lsp }, path)
check(ctx, { path, lsp }, { path }, lsp)
check(ctx, { path, lsp }, {}, nil, false, { [1] = 1 })
local other_server = vim.tbl_extend("force", lsp, { client_id = 9999, detail = "second server" })
check(ctx, { path, lsp, other_server }, {}, path)
local different_dir = vim.tbl_extend("force", path, { data = { full_path = dir .. "/other/renderer.hpp" } })
check(ctx, { different_dir, lsp }, {})
local extra = vim.tbl_extend("force", lsp, { additionalTextEdits = { { range = lsp.textEdit.range, newText = "#define FEATURE" } } })
check(ctx, { path, extra }, {})
check(ctx, { path, vim.tbl_extend("force", lsp, { command = { command = "updateHeaders" } }) }, {})
check(ctx, { path, vim.tbl_extend("force", lsp, { data = { target = "other/header" } }) }, {})

ctx, path, lsp = pair('#include "./模块/ren', '"', "renderer.hpp", "模块/renderer.hpp", true)
local get_client = vim.lsp.get_client_by_id
local resolves = false
vim.lsp.get_client_by_id = function(id)
  if id == 9999 then
    return {
      offset_encoding = "utf-16",
      supports_method = function()
        return resolves
      end,
    }
  end
  return get_client(id)
end
lsp.client_id = 9999
local range = lsp.textEdit.range
for _, position in pairs(range) do
  position.character = vim.str_utfindex(ctx.get_line(), "utf-16", position.character)
end
lsp.textEdit.range, lsp.textEdit.insert, lsp.textEdit.replace = nil, range, range
check(ctx, { path, lsp }, { path })
resolves = true
check(ctx, { path, lsp }, {}) -- The server can still attach edits and commands at acceptance.
vim.lsp.get_client_by_id = get_client

ctx, path, lsp = pair('#include "./ty', " ", "types.hpp", "types.hpp", true)
check(ctx, { path, lsp }, { path })
check(ctx, { path, lsp }, {}, nil, true)
check(ctx, { path, lsp }, { lsp }, path)
ctx, path, lsp = pair('#include "./ty', " // keep this comment", "types.hpp", "types.hpp", false)
check(ctx, { path, lsp }, {})

ctx, path, lsp = pair('#include "./ty', 'pes.hpp"', "types.hpp", "types.hpp", false)
-- Same final line but one cursor is inside the filename, away from its delimiter.
path.textEdit.range["end"].character = path.cursor_column + #"pes.hpp"
lsp.textEdit.newText = "ty"
check(ctx, { path, lsp }, {})

ctx, path, lsp = pair('#include "./en', '"', "engine/", "engine", true)
path.kind, lsp.kind = kinds.Folder, kinds.Folder
lsp.textEdit.newText = "engine/"
lsp.textEdit.range["end"].character = lsp.cursor_column
check(ctx, { path, lsp }, { path })
lsp.kind = kinds.File
check(ctx, { path, lsp }, {})
ctx, path, lsp = pair("#include <ty", ">", "types.hpp", "types.hpp", true)
lsp.textEdit.newText = "types.hpp>"
check(ctx, { path, lsp }, {}) -- The system include root may contain another types.hpp.
print "PASS: header actions preserve paths, closers, cursor positions and explicit selections"
