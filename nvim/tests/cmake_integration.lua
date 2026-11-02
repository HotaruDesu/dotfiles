-- Run: XDG_STATE_HOME=/tmp/lunavim-cmake-state NVIM_LOG_FILE=/tmp/lunavim-cmake.log nvim --headless -u NONE -i NONE -n -l tests/cmake_integration.lua
-- Uses disposable projects and the installed CMake/compiler/clangd; no downloads.
for _, command in ipairs { "cmake", "clangd", "ninja" } do
  if vim.fn.executable(command) ~= 1 then
    print("SKIP: CMake integration requires " .. command)
    return
  end
end
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.rtp:prepend(root)
vim.o.swapfile = false
vim.lsp.log.set_level "OFF"
local temporary = vim.fn.tempname()
local adapter = require "lunavim.lsp.cmake"
local server = require("lunavim.plugins.lsp.servers").clangd
local published = {}
local original_cmake = package.loaded["cmake-tools"]
local selected
local cmake = {
  get_config = function()
    return selected
  end,
}
package.loaded["cmake-tools"] = cmake

local function write(path, lines)
  vim.fn.mkdir(vim.fs.dirname(path), "p")
  vim.fn.writefile(lines, path)
end

local function wait_for(predicate, message)
  assert(vim.wait(15000, predicate, 20), message)
end

local function source(value)
  return {
    '#include "fixture.h"',
    "#ifndef REQUIRED_VALUE",
    '#error "compile database missing"',
    "#endif",
    ('static_assert(REQUIRED_VALUE == %d, "wrong compile database");'):format(value),
    "int example() { return fixture(); }",
  }
end

local function project(name, value)
  local path = temporary .. "/" .. name
  write(path .. "/CMakeLists.txt", {
    "cmake_minimum_required(VERSION 3.20)",
    "project(LunaFixture LANGUAGES CXX)",
    "add_library(fixture OBJECT main.cpp)",
    'target_include_directories(fixture PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}/include")',
    "target_compile_definitions(fixture PRIVATE REQUIRED_VALUE=${REQUIRED_VALUE})",
  })
  write(path .. "/include/fixture.h", { "inline int fixture() { return 1; }" })
  write(path .. "/main.cpp", source(value))
  return path
end

local function configure(path, directory, value)
  local result = vim
    .system({
      vim.fn.exepath "cmake",
      "-S",
      path,
      "-B",
      directory,
      "-G",
      "Ninja",
      "-DCMAKE_EXPORT_COMPILE_COMMANDS=ON",
      "-DREQUIRED_VALUE=" .. value,
    }, { text = true })
    :wait(30000)
  assert(result.code == 0, "CMake configure failed: " .. result.stdout .. result.stderr)
  selected = {
    cwd = path,
    build_directory = true,
    build_directory_path = function()
      return directory
    end,
  }
end

local function open(path)
  local buf = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_buf_set_name(buf, path .. "/main.cpp")
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.fn.readfile(path .. "/main.cpp"))
  vim.bo[buf].filetype = "cpp"
  local config = vim.deepcopy(server)
  config.name, config.root_dir = "clangd", path
  config.handlers = {
    ["textDocument/publishDiagnostics"] = function(err, result, ctx, options)
      published[result.uri] = (published[result.uri] or 0) + 1
      vim.lsp.handlers["textDocument/publishDiagnostics"](err, result, ctx, options)
    end,
  }
  return buf, assert(vim.lsp.start(config, { bufnr = buf }))
end

local function diagnostics_ready(buf)
  return (published[vim.uri_from_bufnr(buf)] or 0) > 0
end

local function client_at(path)
  for _, client in ipairs(vim.lsp.get_clients { name = "clangd" }) do
    if client.config.root_dir == path then
      return client
    end
  end
end

local ok, err = xpcall(function()
  local a, b = project("a", 111), project("b", 222)
  configure(a, a .. "/first", 111)
  adapter.setup(cmake)
  local buf_a, id_a = open(a)
  configure(b, b .. "/second", 222)
  adapter.refresh(cmake, false)
  local buf_b, id_b = open(b)
  wait_for(function()
    return diagnostics_ready(buf_a) and diagnostics_ready(buf_b)
  end, "clangd did not publish diagnostics")
  assert(#vim.diagnostic.get(buf_a) == 0, vim.inspect(vim.diagnostic.get(buf_a)))
  assert(#vim.diagnostic.get(buf_b) == 0, vim.inspect(vim.diagnostic.get(buf_b)))
  assert(client_at(a).config._lunavim_cmake_database == vim.uv.fs_realpath(a .. "/first"))
  assert(client_at(b).config._lunavim_cmake_database == vim.uv.fs_realpath(b .. "/second"))
  print "PASS: real clangd consumes distinct CMake include paths and compile definitions for two simultaneous roots"

  -- The unsaved assertion fails with A's old compile definition. After switching
  -- build directories, the replacement must consume the new definition.
  vim.api.nvim_buf_set_lines(buf_a, 0, -1, false, source(333))
  wait_for(function()
    return #vim.diagnostic.get(buf_a) > 0
  end, "Old database did not produce expected failing static_assert")
  configure(a, a .. "/third", 333)
  published[vim.uri_from_bufnr(buf_a)] = 0
  cmake.compile_commands_from_lsp()
  wait_for(function()
    local client = client_at(a)
    return client and client.id ~= id_a and client.initialized and diagnostics_ready(buf_a) and #vim.diagnostic.get(buf_a) == 0
  end, "Project A did not restart with the newly generated database")
  assert(client_at(a).config._lunavim_cmake_database == vim.uv.fs_realpath(a .. "/third"))
  assert(client_at(b).id == id_b, "Unrelated project's clangd was restarted")
  assert(vim.deep_equal(vim.api.nvim_buf_get_lines(buf_a, 0, -1, false), source(333)), "Restart lost unsaved source")
  assert(vim.bo[buf_a].modified, "Restart cleared the modified flag")
  assert(vim.lsp.buf_is_attached(buf_a, client_at(a).id) and vim.lsp.buf_is_attached(buf_b, id_b))
  print "PASS: successful configure replaces only the affected clangd, consumes the new database and preserves unsaved buffers"
end, debug.traceback)
local stopping = {}
for _, client in ipairs(vim.lsp.get_clients { name = "clangd" }) do
  if client.config.root_dir and client.config.root_dir:find(temporary, 1, true) == 1 then
    stopping[#stopping + 1] = client.id
    client:stop(1000)
  end
end
vim.wait(3000, function()
  return vim.iter(stopping):all(function(id)
    return vim.lsp.get_client_by_id(id) == nil
  end)
end, 20)
package.loaded["cmake-tools"] = original_cmake
vim.fn.delete(temporary, "rf")
if not ok then
  error(err)
end
