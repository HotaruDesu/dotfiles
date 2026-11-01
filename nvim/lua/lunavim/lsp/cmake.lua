local M = {}

-- cmake-tools tracks the selected project globally. Keep each clangd client's
-- database tied to its own root instead of the last project selected in CMake.
local databases = {}
local pending_restarts = {}

local function canonical(path)
  if type(path) ~= "string" or path == "" then
    return nil
  end
  path = vim.fs.normalize(vim.fn.fnamemodify(path, ":p"))
  return vim.uv.fs_realpath(path) or path
end

local function database_exists(directory)
  local stat = directory and vim.uv.fs_stat(vim.fs.joinpath(directory, "compile_commands.json"))
  return stat and stat.type == "file"
end

local function selected_database(cmake)
  local config = cmake.get_config()
  if not config or not config.build_directory then
    return nil
  end
  local root = canonical(config.cwd)
  local directory = canonical(config:build_directory_path())
  if root and database_exists(directory) then
    return root, directory
  end
end

local function explicit_database(config, options)
  local path = options and options ~= vim.NIL and options.compilationDatabasePath
  if path and path ~= config._lunavim_cmake_database then
    return true
  end
  if type(config.cmd) == "table" then
    for _, arg in ipairs(config.cmd) do
      if arg == "--compile-commands-dir" or arg:match "^%-%-compile%-commands%-dir=" then
        return true
      end
    end
  end
  return false
end

local function restart(client)
  if pending_restarts[client.id] then
    return
  end
  pending_restarts[client.id] = true
  local config = vim.deepcopy(client.config)
  local buffers = vim.tbl_keys(client.attached_buffers)
  client:stop(1000)
  vim.schedule(function()
    -- start() reuses the replacement for subsequent buffers and excludes the
    -- stopping client. No global LspRestart: other project roots stay attached.
    for _, buf in ipairs(buffers) do
      if vim.api.nvim_buf_is_loaded(buf) then
        vim.lsp.start(config, { bufnr = buf })
      end
    end
    pending_restarts[client.id] = nil
  end)
end

function M.before_init(params, config)
  if explicit_database(config, params.initializationOptions) then
    return
  end
  local root = canonical(config.root_dir)
  if not root then
    return
  end

  local cmake = package.loaded["cmake-tools"]
  if not cmake and vim.uv.fs_stat(vim.fs.joinpath(root, "CMakeLists.txt")) then
    local ok, plugin = pcall(require, "cmake-tools")
    if ok then
      cmake = plugin
    end
  end
  if cmake and type(cmake) == "table" then
    local selected_root, directory = selected_database(cmake)
    if selected_root == root then
      databases[root] = directory
    end
  end
  local directory = databases[root]
  if not database_exists(directory) then
    return
  end
  local options = params.initializationOptions
  if options == nil or options == vim.NIL then
    options = {}
  end
  options.compilationDatabasePath = directory
  params.initializationOptions = options
  config._lunavim_cmake_database = directory
end

-- Called by cmake-tools only after a successful configure. Seed on setup too,
-- so an existing build is available before this session's first configure.
function M.refresh(cmake, restart_clients)
  local root, directory = selected_database(cmake)
  if not root then
    return
  end
  databases[root] = directory
  if restart_clients then
    for _, client in ipairs(vim.lsp.get_clients { name = "clangd" }) do
      if canonical(client.config.root_dir) == root and not explicit_database(client.config, client.config.init_options) then
        restart(client)
      end
    end
  end
end

function M.setup(cmake)
  cmake.compile_commands_from_lsp = function()
    M.refresh(cmake, true)
  end
  M.refresh(cmake, false)
end

return M
