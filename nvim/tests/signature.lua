-- Run: XDG_STATE_HOME=/tmp/lunavim-signature-state NVIM_LOG_FILE=/tmp/lunavim-signature.log nvim --headless -u NONE -i NONE -n -l tests/signature.lua
-- Uses the installed C++ parser; LSP replies are controlled without networking.
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.rtp:prepend(root)
vim.o.swapfile = false
vim.o.hidden = true
local edits = require "lunavim.plugins.lsp.signature.edits"
local signature = require "lunavim.plugins.lsp.signature"
local syntax = require "lunavim.plugins.lsp.signature.syntax"
local targets = require "lunavim.plugins.lsp.signature.targets"

local function equal(expected, actual, message)
  assert(vim.deep_equal(expected, actual), (message or "Mismatch") .. ": " .. vim.inspect(actual))
end

local function buffer(lines)
  local buf = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_buf_set_name(buf, vim.fn.tempname() .. ".cpp")
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].filetype = "cpp"
  return buf
end

local function text(buf)
  return table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
end

local function target(buf, row, word)
  local line = vim.api.nvim_buf_get_lines(buf, row, row + 1, false)[1]
  return assert(syntax.classify(buf, row, assert(line:find(word, 1, true)) - 1))
end

local function location(buf, row, word)
  local line = vim.api.nvim_buf_get_lines(buf, row, row + 1, false)[1]
  local col = assert(line:find(word, 1, true)) - 1
  local character = vim.str_utfindex(line, "utf-16", col, false)
  return {
    uri = vim.uri_from_bufnr(buf),
    range = { start = { line = row, character = character }, ["end"] = { line = row, character = character + #word } },
  }
end

local function state_for(declaration, definition, references)
  return {
    declaration = declaration,
    definition = definition,
    encoding = "utf-16",
    references = references or {},
  }
end

-- A single URI must retain both edits, preserve default arguments only in the
-- declaration, and preserve the definition's different parameter names.
local same = buffer {
  "class T { public: static int sum(int left = 1, int right = 2); };",
  "int T::sum(int a, int b) { return a + b; }",
  "int total = T::sum(1, 2);",
}
local decl = target(same, 0, "sum")
local def = target(same, 1, "sum")
local state = state_for(decl, def, { location(same, 0, "sum"), location(same, 1, "sum"), location(same, 2, "sum"), location(same, 2, "sum") })
local edited = assert(syntax.parse_edited("static long sum(long right = 2, long left = 1)", "sum"))
assert(syntax.validate_parameter_names(decl.parameters, edited.parameters))
local declaration_text, definition_text = edits.replacement_texts(state, edited)
local plan = edits.plan(state, declaration_text, definition_text)
equal(2, #plan.workspace_edit.changes[decl.uri], "A same-file edit was lost")
equal(1, #plan.quickfix, "Call sites should be deduplicated and exclude targets")
assert(edits.apply(state, plan))
assert(text(same):find("static long sum(long right = 2, long left = 1)", 1, true), text(same))
assert(text(same):find("long T::sum(long b, long a) { return a + b; }", 1, true), text(same))
assert(vim.bo[same].modified and vim.fn.filereadable(vim.api.nvim_buf_get_name(same)) == 0, "Applying a signature must leave the file unsaved")

-- Cross-file edits and UTF-16 positions after multibyte characters exercise the
-- protocol conversion instead of only ASCII offsets.
local header = buffer { "/*说明😀*/ int f(int value);" }
local source = buffer { "/*说明😀*/ int f(int value) { return value; }" }
local h = target(header, 0, "f(")
local s = target(source, 0, "f(")
local found = assert(targets.choose_targets(h, {
  declaration = location(header, 0, "f"),
  definition = location(source, 0, "f"),
  references = {},
}, "utf-16"))
equal(h.uri, found.declaration.uri)
equal(s.uri, found.definition.uri)
local changed = assert(syntax.parse_edited("int f(int value, int extra = 0)", "f"))
local dh, ds = edits.replacement_texts(found, changed)
local cross_plan = edits.plan(found, dh, ds)
equal(2, vim.tbl_count(cross_plan.workspace_edit.changes))
assert(edits.apply(found, cross_plan))
equal("/*说明😀*/ int f(int value, int extra = 0);", text(header))
equal("/*说明😀*/ int f(int value, int extra) { return value; }", text(source))

-- A preview is a snapshot, never authority to overwrite newer text.
local fresh_state = state_for(target(header, 0, "f("), target(source, 0, "f("))
local stale_plan = edits.plan(fresh_state, "int f()", "int f() ")
local old_source = text(source)
vim.api.nvim_buf_set_lines(header, 0, 0, false, { "// changed after preview" })
local applied, stale_error = edits.apply(fresh_state, stale_plan)
assert(not applied and stale_error:find("changed during preview", 1, true))
equal(old_source, text(source), "Stale preview modified the other target")

for _, input in ipairs {
  "int f(int value); int other()",
  "int f(int value), other()",
  "int f(int value); int field",
  "public: int f(int value)",
  "int f(int value) {}",
  "",
} do
  local parsed = syntax.parse_edited(input, "f")
  assert(not parsed, "Accepted more than one supported signature: " .. input)
end
assert(syntax.parse_edited("/* comment */ int f(int value)", "f"))
assert(syntax.parse_edited("T(int value)", "T"))
assert(syntax.parse_edited("~T()", "~T"))
assert(not syntax.parse_edited("virtual int f(int value)", "f"))
assert(not syntax.parse_edited("int g(int value)", "f"))
local renamed = assert(syntax.parse_edited("int f(int renamed)", "f"))
assert(not syntax.validate_parameter_names(h.parameters, renamed.parameters))
local unsupported = buffer { "template<class T> T fun(T value);", "int operator+(int value);" }
assert(not syntax.classify(unsupported, 0, 22))
assert(not syntax.classify(unsupported, 1, 5))
print "PASS: signature parsing, transforms, same/cross-file edits, UTF-16, call sites and stale previews"

-- The request harness records real protocol calls and lets replies arrive in
-- arbitrary order, including after cancel/timeout. It never opens a server.
local function client()
  local c = { offset_encoding = "utf-16", calls = {}, cancelled = {} }
  function c:request(method, params, callback, bufnr)
    self.calls[#self.calls + 1] = { method = method, params = params, callback = callback, bufnr = bufnr }
    return true, #self.calls
  end
  function c:cancel_request(request_id)
    self.cancelled[request_id] = true
  end
  function c:reply(index, result, err)
    self.calls[index].callback(err, result)
  end
  return c
end

local request_header = buffer { "int f(int value);" }
local request_source = buffer { "int f(int value) { return value; }" }
vim.api.nvim_set_current_buf(request_header)
local current = target(request_header, 0, "f(")
local results = {
  location(request_header, 0, "f"),
  location(request_source, 0, "f"),
  {},
}
local c = client()
local completed = {}
targets.discover(c, current, function(result, err)
  completed[#completed + 1] = { result = result, err = err }
end)
equal(3, #c.calls)
assert(c.calls[3].params.context.includeDeclaration, "Reference discovery omitted declarations")
c:reply(3, results[3])
c:reply(1, results[1])
equal(0, #completed)
c:reply(2, results[2])
equal(1, #completed)
assert(completed[1].result and not completed[1].err, vim.inspect(completed))

local old, latest = client(), client()
local old_results, latest_results = 0, 0
local first_id = targets.discover(old, current, function()
  old_results = old_results + 1
end)
local second_id = targets.discover(latest, current, function()
  latest_results = latest_results + 1
end)
assert(second_id > first_id)
equal(3, vim.tbl_count(old.cancelled), "Superseded discovery kept requests alive")
for index, result in ipairs(results) do
  old:reply(index, result)
end
equal(0, old_results, "Stale discovery completed")
for index, result in ipairs(results) do
  latest:reply(index, result)
end
equal(1, latest_results)

local switched, switched_results = client(), 0
targets.discover(switched, current, function()
  switched_results = switched_results + 1
end)
vim.api.nvim_set_current_buf(request_source)
for index, result in ipairs(results) do
  switched:reply(index, result)
end
equal(0, switched_results, "A reply after leaving the source stole focus")
equal(3, vim.tbl_count(switched.cancelled))
vim.api.nvim_set_current_buf(request_header)

local changed_client, changed_error = client(), nil
targets.discover(changed_client, current, function(_, err)
  changed_error = err
end)
vim.api.nvim_buf_set_lines(request_header, 0, 0, false, { "// changed during request" })
changed_client:reply(1, results[1])
assert(changed_error and changed_error:find("changed", 1, true))
equal(2, vim.tbl_count(changed_client.cancelled), "Source edit left other requests alive")

local timeout_client, timeout_results, timeout_error = client(), 0, nil
current = target(request_header, 1, "f(")
targets.discover(timeout_client, current, function(_, err)
  timeout_results = timeout_results + 1
  timeout_error = err
end, { timeout_ms = 10 })
assert(
  vim.wait(1000, function()
    return timeout_results == 1
  end, 5),
  "Timeout did not complete"
)
assert(timeout_error:find("timed out", 1, true))
equal(3, vim.tbl_count(timeout_client.cancelled))
for index, result in ipairs(results) do
  timeout_client:reply(index, result)
end
equal(1, timeout_results, "A late reply repeated the timeout callback")

local cancelled, cancel_results = client(), 0
targets.discover(cancelled, current, function()
  cancel_results = cancel_results + 1
end)
targets.cancel()
for index, result in ipairs(results) do
  cancelled:reply(index, result)
end
equal(0, cancel_results)
equal(3, vim.tbl_count(cancelled.cancelled))
signature.setup()
assert(vim.fn.exists ":CppChangeSignature" == 2)
print "PASS: request ordering, cancellation, supersession, buffer changes, timeout and late replies"

-- Exercise editor -> preview -> edit -> preview -> apply through the existing
-- buffer-local mapping callbacks, including the common floating-window style.
local ui = require "lunavim.plugins.lsp.signature.ui"
local ui_header = buffer { "int visible(int value);" }
local ui_source = buffer { "int visible(int value) { return value; }" }
local ui_state = state_for(target(ui_header, 0, "visible"), target(ui_source, 0, "visible"))
vim.api.nvim_set_current_buf(ui_header)
ui.open(ui_state)
local editor_buf = vim.api.nvim_get_current_buf()
local editor_win = vim.api.nvim_get_current_win()
equal("editor", vim.api.nvim_win_get_config(editor_win).relative)
equal(require("lunavim.config.ui").get().float_blend, vim.wo[editor_win].winblend)
local preview_key = vim.fn.maparg("<C-s>", "i", false, true)
assert(preview_key.buffer == 1 and type(preview_key.callback) == "function")
for _, key in ipairs { "q", "<Esc>" } do
  assert(vim.fn.maparg(key, "n", false, true).buffer == 1, "Editor lost " .. key)
end
vim.api.nvim_buf_set_lines(editor_buf, 0, -1, false, { "long visible(int value)" })
preview_key.callback()
local preview_buf = vim.api.nvim_get_current_buf()
assert(preview_buf ~= editor_buf and vim.bo.filetype == "diff")
for _, key in ipairs { "y", "e", "q", "<Esc>" } do
  assert(vim.fn.maparg(key, "n", false, true).buffer == 1, "Preview lost " .. key)
end
vim.fn.maparg("e", "n", false, true).callback()
equal(editor_buf, vim.api.nvim_get_current_buf())
preview_key.callback()
vim.fn.maparg("y", "n", false, true).callback()
equal("long visible(int value);", text(ui_header))
equal("long visible(int value) { return value; }", text(ui_source))
assert(not vim.api.nvim_win_is_valid(editor_win) and not vim.api.nvim_buf_is_valid(preview_buf))
print "PASS: existing signature editor/preview keys, modern float styling and unsaved UI apply"
