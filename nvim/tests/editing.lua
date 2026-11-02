-- Run: NVIM_LOG_FILE=/tmp/lunavim-editing.log nvim --headless -u NONE -i NONE -n -l tests/editing.lua
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.rtp:prepend(root)
vim.opt.rtp:append(root .. "/after")
vim.opt.rtp:append(vim.fn.stdpath "data" .. "/lazy/mini.ai")
vim.o.swapfile = false
vim.lsp.log.set_level "OFF"

local function equal(expected, actual, message)
  assert(vim.deep_equal(expected, actual), (message or "Mismatch") .. ": " .. vim.inspect(actual))
end

local temporary = vim.fn.tempname()
local function file(path, lines)
  vim.fn.mkdir(vim.fs.dirname(path), "p")
  vim.fn.writefile(lines or {}, path)
end
local project_a, project_b = temporary .. "/a", temporary .. "/b"
file(project_a .. "/CMakeLists.txt")
file(project_b .. "/CMakeLists.txt")
file(project_a .. "/build/compile_commands.json", { "[]" })
file(project_b .. "/debug/compile_commands.json", { "[]" })
local canonical = function(path)
  return vim.uv.fs_realpath(path) or vim.fs.normalize(path)
end
local cmake_config = { cwd = project_a, build_directory = true }
function cmake_config:build_directory_path()
  return project_a .. "/build"
end
local cmake = {
  get_config = function()
    return cmake_config
  end,
}
local adapter = require "lunavim.lsp.cmake"
local original_cmake = package.loaded["cmake-tools"]
package.loaded["cmake-tools"] = cmake
adapter.setup(cmake)

local params, config = {}, { root_dir = project_a }
adapter.before_init(params, config)
equal(canonical(project_a .. "/build"), params.initializationOptions.compilationDatabasePath, "Existing build must work before configure")
equal(canonical(project_a .. "/build"), config._lunavim_cmake_database)

local other = {}
adapter.before_init(other, { root_dir = project_b })
equal(nil, other.initializationOptions, "Current CMake project must not leak to another root")
local missing = {}
adapter.before_init(missing, { root_dir = temporary .. "/missing" })
equal(nil, missing.initializationOptions, "No database should preserve clangd discovery")
local explicit = { initializationOptions = { compilationDatabasePath = "/explicit", custom = true } }
adapter.before_init(explicit, { root_dir = project_a })
equal("/explicit", explicit.initializationOptions.compilationDatabasePath)
local command_path = {}
adapter.before_init(command_path, { root_dir = project_a, cmd = { "clangd", "--compile-commands-dir=/explicit" } })
equal(nil, command_path.initializationOptions, "Explicit command line path must win")

local buf_a, buf_b = vim.api.nvim_create_buf(true, false), vim.api.nvim_create_buf(true, false)
local stopped, started = {}, {}
local function client(id, project, buffers, options)
  return {
    id = id,
    config = { name = "clangd", root_dir = project, init_options = options },
    attached_buffers = buffers,
    stop = function(_, timeout)
      equal(1000, timeout)
      stopped[id] = (stopped[id] or 0) + 1
    end,
  }
end
local a = client(1, project_a, { [buf_a] = true, [buf_b] = true })
local b = client(2, project_b, { [buf_b] = true })
local explicit_client = client(3, project_a, { [buf_a] = true }, { compilationDatabasePath = "/explicit" })
local get_clients, start = vim.lsp.get_clients, vim.lsp.start
vim.lsp.get_clients = function(opts)
  equal("clangd", opts.name)
  return { a, b, explicit_client }
end
vim.lsp.start = function(client_config, opts)
  started[#started + 1] = { root = client_config.root_dir, buf = opts.bufnr }
  return 10
end
cmake.compile_commands_from_lsp()
cmake.compile_commands_from_lsp()
equal({ [1] = 1 }, stopped, "Restart once per affected client, preserving other roots and explicit paths")
assert(
  vim.wait(1000, function()
    return #started == 2
  end),
  "Replacement did not reattach both buffers"
)
for _, entry in ipairs(started) do
  equal(project_a, entry.root)
end

cmake_config.cwd = project_b
function cmake_config:build_directory_path()
  return project_b .. "/debug"
end
cmake.compile_commands_from_lsp()
assert(vim.wait(1000, function()
  return #started == 3
end))
equal(1, stopped[2], "Second project not restarted")
local after_switch = {}
adapter.before_init(after_switch, { root_dir = project_a })
equal(canonical(project_a .. "/build"), after_switch.initializationOptions.compilationDatabasePath, "Remember project A after selecting project B")
local b_params = { initializationOptions = { custom = true } }
adapter.before_init(b_params, { root_dir = project_b })
equal(canonical(project_b .. "/debug"), b_params.initializationOptions.compilationDatabasePath)
equal(true, b_params.initializationOptions.custom, "Preserve unrelated initialization options")

local no_build = { cwd = temporary .. "/unconfigured" }
cmake_config = no_build
local before = #started
cmake.compile_commands_from_lsp()
equal(before, #started, "No build directory must not restart clients")
vim.lsp.get_clients, vim.lsp.start = get_clients, start
package.loaded["cmake-tools"] = original_cmake
print "PASS: CMake existing/missing databases, explicit overrides, project isolation and targeted restarts"

-- Exercise native vim.lsp.enable's root-marker path without launching a server.
local servers = require "lunavim.plugins.lsp.servers"
assert(not servers.clangd.on_new_config and servers.clangd.before_init == adapter.before_init)
assert(not servers.markdown_oxide.root_dir, "Legacy root_dir callback must not be passed to the native API")
file(temporary .. "/notes/.obsidian/workspace.json", { "{}" })
file(temporary .. "/notes/daily/note.md", { "# Note" })
local markdown = vim.api.nvim_create_buf(true, false)
vim.api.nvim_buf_set_name(markdown, temporary .. "/notes/daily/note.md")
vim.bo[markdown].filetype = "markdown"
vim.api.nvim_set_current_buf(markdown)
local detected
vim.lsp.start = function(client_config, opts)
  detected = client_config.root_dir or vim.fs.root(opts.bufnr, opts._root_markers)
  return nil
end
vim.lsp.config(
  "lunavim_markdown_test",
  vim.tbl_extend("force", servers.markdown_oxide, {
    cmd = { vim.fn.exepath "cat" },
    filetypes = { "markdown" },
  })
)
vim.lsp.enable "lunavim_markdown_test"
assert(
  vim.wait(1000, function()
    return detected ~= nil
  end),
  "Native LSP activation did not resolve Markdown root"
)
equal(canonical(temporary .. "/notes"), canonical(detected))
vim.lsp.enable("lunavim_markdown_test", false)
vim.lsp.start = start
print "PASS: Markdown activates through native LSP root detection"

local cpp = vim.api.nvim_create_buf(true, false)
vim.api.nvim_set_current_buf(cpp)
vim.bo[cpp].filetype = "cpp"
local source = {
  "class Box {",
  "  int value;",
  "};",
  "int add(int x) { return x + 1; }",
  "void loop() { for (int i = 0; i < 2; ++i) { work(); } }",
}
vim.api.nvim_buf_set_lines(cpp, 0, -1, false, source)
local parser = vim.treesitter.get_parser(cpp, "cpp")
parser:parse()
local query = assert(vim.treesitter.query.get("cpp", "textobjects"))
local captures = {}
for id, node, metadata in query:iter_captures(parser:parse()[1]:root(), cpp) do
  local name = query.captures[id]
  captures[name] = captures[name] or {}
  captures[name][#captures[name] + 1] = vim.treesitter.get_node_text(node, cpp, { metadata = metadata[id] })
end
equal("class Box {\n  int value;\n}", captures["class.outer"][1])
equal("\n  int value;\n", captures["class.inner"][1])
equal("int add(int x) { return x + 1; }", captures["function.outer"][1])
equal(" return x + 1; ", captures["function.inner"][1])
assert(captures["loop.outer"] and captures["block.inner"], "Configured code block captures missing")
local ai = require "mini.ai"
ai.setup {
  custom_textobjects = {
    f = ai.gen_spec.treesitter { a = "@function.outer", i = "@function.inner" },
    c = ai.gen_spec.treesitter { a = "@class.outer", i = "@class.inner" },
  },
}
vim.api.nvim_win_set_cursor(0, { 4, 21 })
local inner = ai.find_textobject("i", "f")
equal({ line = 4, col = 17 }, inner.from)
equal({ line = 4, col = 31 }, inner.to)
print "PASS: C++ queries and actual mini.ai function/class ranges"

-- Read the specs without loading their unrelated plugins.
_G.LunaVim = {
  plugin_lazy = function()
    return {}
  end,
  icons = { ui = {}, git = {} },
}
local lsp_specs = require "lunavim.plugins.lsp"
local format_spec = lsp_specs[3]
equal({ "cmake_format" }, format_spec.opts.formatters_by_ft.cmake)
equal(nil, format_spec.opts.formatters_by_ft["*"], "Regular formatting must not correct spelling")
equal(nil, format_spec.opts.format_on_save, "Formatting stays manual")
local configured, formatted
package.loaded.conform = {
  setup = function(opts)
    configured = opts
  end,
  format = function(opts)
    formatted = opts
  end,
}
format_spec.config(nil, format_spec.opts)
equal(format_spec.opts, configured)
vim.cmd "LunaSpellFix"
equal({ "codespell" }, formatted.formatters)
local persistence_opts
package.loaded.persistence = {
  setup = function(opts)
    persistence_opts = opts
  end,
}
for _, spec in ipairs(require "lunavim.plugins.editor") do
  if spec[1] == "folke/persistence.nvim" then
    spec.config(nil, spec.opts)
    equal(nil, persistence_opts.options, "No ignored persistence options")
    equal({ "buffers", "curdir", "tabpages", "winsize" }, vim.opt.sessionoptions:get())
  end
end
print "PASS: manual formatting, explicit spelling command and native session options"
vim.fn.delete(temporary, "rf")
