local M = {}

local markers = {
  "CMakeLists.txt",
  "CMakePresets.json",
  "Makefile",
  "meson.build",
  "configure.ac",
  "configure.in",
  "go.work",
  "go.mod",
  "package.json",
  "Cargo.toml",
  "pyproject.toml",
  "setup.py",
  ".clangd",
  "compile_commands.json",
  "compile_flags.txt",
  ".obsidian",
  "obsidian.vimrc",
}

-- Resolve existing ancestors too: a new file may not exist yet, even though
-- its project directory is reached through a symbolic link.
local function canonical(path)
  path = vim.fs.normalize(path)
  local resolved = vim.uv.fs_realpath(path)
  if resolved then
    return vim.fs.normalize(resolved)
  end
  local parent = vim.fs.dirname(path)
  if parent and parent ~= path then
    return vim.fs.joinpath(canonical(parent), vim.fs.basename(path))
  end
  return path
end

local function directory(path)
  local stat = path and vim.uv.fs_stat(path)
  return stat and stat.type == "directory" and canonical(path) or nil
end

local function contains(root, file)
  local prefix = root:sub(-1) == "/" and root or root .. "/"
  return root == file or file:sub(1, #prefix) == prefix
end

local function lsp_root(buf, file)
  local deepest
  local function consider(path)
    local root = type(path) == "string" and directory(path) or nil
    if root and contains(root, file) and (not deepest or #root > #deepest) then
      deepest = root
    end
  end
  for _, client in ipairs(vim.lsp.get_clients { bufnr = buf }) do
    consider(client.root_dir)
    consider(client.config and client.config.root_dir)
    for _, workspace in ipairs(client.workspace_folders or {}) do
      if type(workspace.uri) == "string" and workspace.uri:sub(1, 7) == "file://" then
        local ok, path = pcall(vim.uri_to_fname, workspace.uri)
        if ok then
          consider(path)
        end
      end
    end
  end
  return deepest
end

local function window_context(win)
  if not win or win == 0 or not vim.api.nvim_win_is_valid(win) then
    win = vim.api.nvim_get_current_win()
  end
  local tab = vim.api.nvim_tabpage_get_number(vim.api.nvim_win_get_tabpage(win))
  -- nvim_win_call changes curwin but deliberately keeps the process cwd.
  -- Explicit window/tab arguments read the real local directories instead.
  local cwd = vim.fn.getcwd(win, tab)
  local localdir = vim.fn.haslocaldir(win, tab) ~= 0 or vim.fn.haslocaldir(-1, tab) ~= 0
  return win, canonical(cwd), localdir
end

---@class LunaSearchRootOptions
---@field cwd? string Explicit directory, relative to the selected window's cwd.
---@field win? integer Main editor window; defaults to the current window.
---@field buf? integer Main editor buffer; defaults to the selected window's buffer.

---Find a search root without modifying a window, tab or global working directory.
---@param opts? LunaSearchRootOptions
---@return string? root
---@return string? error Invalid explicit directories are errors, not a different search scope.
function M.resolve(opts)
  opts = opts or {}
  local win, cwd, localdir = window_context(opts.win)
  if opts.cwd ~= nil then
    if type(opts.cwd) ~= "string" or opts.cwd == "" then
      return nil, "Search directory must be a non-empty path"
    end
    local path = opts.cwd
    if path == "~" or path:sub(1, 2) == "~/" then
      path = vim.fn.expand "~" .. path:sub(2)
    elseif path:sub(1, 1) ~= "/" and not path:match "^%a:[/\\]" then
      path = vim.fs.joinpath(cwd, path)
    end
    local root = directory(path)
    if not root then
      return nil, "Search directory does not exist: " .. opts.cwd
    end
    return root
  end
  if localdir then
    return cwd
  end

  local buf = opts.buf or vim.api.nvim_win_get_buf(win)
  if not vim.api.nvim_buf_is_valid(buf) or vim.bo[buf].buftype ~= "" then
    return cwd
  end
  local name = vim.api.nvim_buf_get_name(buf)
  if name == "" then
    return cwd
  end
  local file = canonical(name)
  local root = lsp_root(buf, file)
  if root then
    return root
  end
  -- Git is considered before language markers so nested CMake/package files
  -- do not accidentally shrink a repository-wide search.
  return vim.fs.root(file, ".git") or vim.fs.root(file, markers) or cwd
end

return M
