-- Run: nvim --headless -u NONE -i NONE -n -l tests/search_root.lua
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.rtp:prepend(root)
vim.o.swapfile = false
vim.o.hidden = true
local resolver = require "lunavim.search.root"
local temporary = vim.fn.tempname()
local original_cwd = vim.fn.getcwd()
local get_clients = vim.lsp.get_clients

local function file(path, content)
  vim.fn.mkdir(vim.fs.dirname(path), "p")
  vim.fn.writefile(content or {}, path)
end
local function canonical(path)
  return vim.uv.fs_realpath(path)
end
local function equal(expected, actual, message)
  assert(expected == actual, (message or "Mismatch") .. ": " .. tostring(actual))
end
local function buffer(path)
  local buf = vim.api.nvim_create_buf(true, false)
  if path then
    vim.api.nvim_buf_set_name(buf, path)
  end
  return buf
end
local function cd(command, path)
  vim.cmd(command .. " " .. vim.fn.fnameescape(path))
end

local ok, err = xpcall(function()
  local project = temporary .. "/project"
  local nested = project .. "/packages/lib"
  local other = temporary .. "/other"
  local prefix = temporary .. "/project-longer"
  file(project .. "/.git", { "gitdir: /not-needed-for-root-resolution" })
  file(nested .. "/CMakeLists.txt")
  file(nested .. "/src/main.cpp", { "int main() {}" })
  file(other .. "/.gitignore")
  file(prefix .. "/file.cpp")
  cd("cd", temporary)
  local buf = buffer(nested .. "/src/main.cpp")
  vim.api.nvim_set_current_buf(buf)
  vim.lsp.get_clients = function()
    return {}
  end
  equal(canonical(project), resolver.resolve(), "Git root precedes a nested language marker")
  equal(canonical(other), resolver.resolve { cwd = "other" }, "Explicit relative directory")
  equal(canonical(vim.fn.expand "~"), resolver.resolve { cwd = "~" }, "Explicit home directory expansion")
  local invalid, reason = resolver.resolve { cwd = "missing" }
  assert(not invalid and reason:find("does not exist", 1, true))
  assert(not resolver.resolve { cwd = "" })
  equal(canonical(temporary), vim.fn.getcwd(), "Resolution must not change cwd")

  vim.lsp.get_clients = function(opts)
    equal(buf, opts.bufnr)
    return {
      { config = { root_dir = project }, workspace_folders = { { uri = vim.uri_from_fname(nested) } } },
      { root_dir = other, workspace_folders = { { uri = "https://example.invalid/not-a-file" } } },
    }
  end
  equal(canonical(nested), resolver.resolve(), "Deepest containing LSP workspace")
  vim.lsp.get_clients = function()
    return { { config = { root_dir = temporary .. "/project" } } }
  end
  equal(canonical(temporary), resolver.resolve { buf = buffer(prefix .. "/file.cpp") }, "Sibling prefix is not containment")

  cd("tcd", other)
  equal(canonical(other), resolver.resolve(), "Explicit tab cwd beats LSP")
  cd("lcd", project)
  equal(canonical(project), resolver.resolve(), "Explicit window cwd beats tab cwd")
  equal(canonical(nested), resolver.resolve { cwd = nested }, "Explicit picker cwd beats local cwd")
  local first_win = vim.api.nvim_get_current_win()
  vim.cmd "vsplit"
  local second_win = vim.api.nvim_get_current_win()
  cd("lcd", other)
  equal(canonical(project), resolver.resolve { win = first_win }, "Resolve a non-current window in its own cwd")
  equal(canonical(other), vim.fn.getcwd(), "Selected window's cwd remains untouched")
  vim.cmd "tabnew"
  local second_tab = vim.api.nvim_get_current_tabpage()
  cd("tcd", nested)
  equal(canonical(project), resolver.resolve { win = first_win }, "Resolve a window in another tab")
  equal(canonical(nested), vim.fn.getcwd(), "Other tab resolution must not change the active tab cwd")
  vim.cmd "tabclose"
  assert(not vim.api.nvim_tabpage_is_valid(second_tab))
  vim.api.nvim_win_close(second_win, true)
  cd("cd", temporary)

  vim.lsp.get_clients = function()
    return {}
  end
  local nongit = temporary .. "/nongit"
  file(nongit .. "/CMakeLists.txt")
  file(nongit .. "/src/new.cpp")
  equal(canonical(nongit), resolver.resolve { buf = buffer(nongit .. "/src/new.cpp") }, "Non-Git language project")
  local linked = temporary .. "/linked"
  assert(vim.uv.fs_symlink(project, linked))
  equal(canonical(project), resolver.resolve { cwd = linked }, "Explicit symbolic directory")
  equal(canonical(project), resolver.resolve { buf = buffer(linked .. "/new.cpp") }, "New file through symbolic project directory")

  local unnamed = buffer()
  equal(canonical(temporary), resolver.resolve { buf = unnamed }, "Unnamed buffer fallback")
  vim.bo[unnamed].buftype = "nofile"
  vim.api.nvim_buf_set_name(unnamed, project .. "/not-a-real-file")
  equal(canonical(temporary), resolver.resolve { buf = unnamed }, "Plugin buffer fallback")
  equal(canonical(temporary), resolver.resolve { buf = 999999, win = 999999 }, "Invalid editor context fallback")
  equal(canonical(temporary), vim.fn.getcwd(), "No resolution changes cwd")
end, debug.traceback)
vim.lsp.get_clients = get_clients
cd("cd", original_cwd)
vim.fn.delete(temporary, "rf")
if not ok then
  error(err)
end
print "PASS: project roots, explicit cwd, native window/tab cwd, LSP scopes, worktrees and symlinks"
