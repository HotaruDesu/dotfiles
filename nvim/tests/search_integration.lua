-- Exercise the production source hooks, not just the isolated adapters.
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.rtp:prepend(root)
vim.opt.rtp:append(vim.fn.stdpath "data" .. "/lazy/snacks.nvim")
vim.o.swapfile = false
vim.o.columns, vim.o.lines = 150, 45
_G.LunaVim = require "lunavim"
local config = require "lunavim.config.search"
assert(config.files == "snacks" and config.grep == "snacks", "Unqualified backends must remain opt-in")
local warmed, stopped, refreshed = 0, 0, 0
package.loaded["lunavim.search.fff"] = {
  warm = function()
    warmed = warmed + 1
  end,
  stop = function()
    stopped = stopped + 1
  end,
  refresh = function()
    refreshed = refreshed + 1
  end,
  status = function()
    return {}
  end,
}
local preview = require "lunavim.search.preview"
local wrap, wrappers = preview.wrap, 0
preview.wrap = function(...)
  wrappers = wrappers + 1
  return wrap(...)
end
local search = require "lunavim.search"
require("snacks").setup(require("lunavim.ui_specs.snacks")[1].opts)
search.setup()
search.setup()
local temporary = vim.fn.tempname()
vim.fn.mkdir(temporary, "p")
vim.fn.writefile({ "int Needle = 42;" }, temporary .. "/main.cpp")
local closed = 0
local ok, err = xpcall(function()
  for _, kind in ipairs { "files", "grep" } do
    local before = wrappers
    local picker = Snacks.picker(kind, {
      cwd = temporary,
      search = kind == "grep" and "Needle" or nil,
      on_close = function()
        closed = closed + 1
      end,
    })
    assert(
      vim.wait(2000, function()
        return picker.shown and not picker:is_active() and picker.list:count() > 0
      end, 5),
      kind .. " production source did not finish"
    )
    assert(wrappers == before + 1, "Source config must wrap previews exactly once")
    assert(picker.opts.cwd == vim.uv.fs_realpath(temporary) and picker.opts.show_delay == 0)
    assert(
      vim.wait(2000, function()
        local lines = vim.api.nvim_buf_get_lines(picker.preview.win.buf, 0, -1, false)
        return table.concat(lines, "\n"):find("int Needle", 1, true) ~= nil
      end, 5),
      "Production source preview remained blank"
    )
    vim.cmd "LunaSearchRefresh"
    assert(
      vim.wait(2000, function()
        return not picker:is_active()
      end, 5),
      "Refreshed finder did not finish"
    )
    picker:close()
  end
  assert(closed == 2 and warmed == 0 and refreshed == 2, "Default searches must not start a native worker")
  vim.cmd "LunaSearchBackend grep fff"
  assert(config.grep == "fff" and warmed == 1)
  vim.cmd "LunaSearchBackend grep snacks"
  assert(config.grep == "snacks" and stopped == 1, "Disabling both native sources must stop the worker")
  local autocmds = vim.api.nvim_get_autocmds { group = "LunaVimSearch" }
  assert(#autocmds == 6, "Repeated setup duplicated search listeners")
end, debug.traceback)
for _, picker in ipairs(Snacks.picker.get()) do
  picker:close()
end
vim.fn.delete(temporary, "rf")
if not ok then
  error(err)
end
print "PASS: production source hooks wrap once, preserve callbacks, refresh and keep native indexing opt-in"
