-- Run: nvim --headless -u NONE -i NONE -n -l tests/completion_text.lua
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.rtp:prepend(root)
for _, plugin in ipairs { "blink.cmp", "blink-cmp-dictionary", "friendly-snippets" } do
  vim.opt.rtp:append(vim.fn.stdpath "data" .. "/lazy/" .. plugin)
end
local api = vim.api
local tmp = vim.fn.tempname()
vim.fn.mkdir(tmp .. "/notes/assets/nested", "p")
vim.fn.writefile({ "test" }, tmp .. "/notes/assets/nested/fixture.md")
vim.fn.writefile({ "test" }, tmp .. "/notes/assets/local-map.svg")
vim.fn.writefile({ "test" }, tmp .. "/notes/assets/my figure.svg")
vim.fn.writefile({ "test" }, tmp .. "/notes/first.md")
api.nvim_buf_set_name(0, tmp .. "/notes/document.md")
vim.bo.filetype = "markdown"
local text = require "lunavim.completion.text"
local function context(lines, row, col)
  api.nvim_buf_set_lines(0, 0, -1, false, lines)
  row = row or #lines
  local line = lines[row]
  col = col or #line
  local word = line:sub(1, col):match "[%w_]+$" or ""
  return {
    bufnr = api.nvim_get_current_buf(),
    mode = "default",
    cursor = { row, col },
    line = line,
    providers = { "path", "snippets", "dictionary" },
    bounds = { start_col = col - #word + 1, length = #word },
    id = 1,
    get_line = function()
      return line
    end,
  }
end
local function query(send)
  local items
  send(function(response)
    items = response and response.items or {}
  end)
  assert(
    vim.wait(2000, function()
      return items ~= nil
    end),
    "Source did not return"
  )
  return items
end
local path = require("blink.cmp.sources.path").new {}
local function paths(ctx)
  return query(function(cb)
    text.path_completions(path, ctx, cb)
  end)
end
for _, sample in ipairs {
  { "[图](assets/nested/fi)", "fixture.md", "[图](assets/nested/fixture.md)" },
  { "中文说明 [图](assets/lo)", "local-map.svg", "中文说明 [图](assets/local-map.svg)" },
  { "[图](<assets/my fi>)", "my figure.svg", "[图](<assets/my figure.svg>)" },
  { "[doc](fi)", "first.md", "[doc](first.md)" },
  { "![image](assets/ne)", "nested/", "![image](assets/nested/)" },
  { "[doc](./assets/nested/fi)", "fixture.md", "[doc](./assets/nested/fixture.md)" },
} do
  local input, label, expected = unpack(sample)
  local ctx = context({ input }, 1, #input - (input:sub(-2) == ">)" and 2 or 1))
  assert(text.is_path(ctx), input)
  local accepted = false
  for _, item in ipairs(paths(ctx)) do
    if item.label == label then
      local edit = item.textEdit
      api.nvim_buf_set_text(0, 0, edit.range.start.character, 0, edit.range["end"].character, { edit.newText })
      assert(api.nvim_get_current_line() == expected, "Incorrect accepted path: " .. api.nvim_get_current_line())
      accepted = true
      break
    end
  end
  assert(accepted, "Expected a real document-relative path: " .. input)
end
for _, input in ipairs { "normal prose", "mention assets/nested/fi", "[web](https://host/assets/nested/fi", "[ref](#section" } do
  local ctx = context { input }
  assert(not text.is_path(ctx) and #paths(ctx) == 0, input)
end

local provider = text.dictionary_provider()
local readable = vim.fn.filereadable
vim.fn.filereadable = function()
  return 0
end
local missing = text.dictionary_provider()
vim.fn.filereadable = readable
assert(not missing.enabled and #missing.opts.dictionary_files == 0, "Missing system word lists should disable the source")
local cmdline = context { "[doc](assets/nested/fi" }
cmdline.mode = "cmdline"
local forwarded = false
text.path_completions({
  get_completions = function(_, ctx)
    forwarded = ctx == cmdline
  end,
}, cmdline, function() end)
assert(forwarded, "Command-line paths use the original Blink provider")
local prefix = provider.opts.get_prefix
assert(provider.min_keyword_length == 4 and provider.max_items == 3 and provider.score_offset < -5)
assert(prefix(context { "A rea" }) == "" and prefix(context { "A reas" }) == "reas")
for _, line in ipairs { "render_thing", "https://site/render", "[local](render", "[section](#render", "[mail](mailto:render", "use `render`" } do
  local col = line:sub(-1) == "`" and #line - 1 or #line
  assert(prefix(context({ line }, 1, col)) == "", line)
end
local fence = context({ "~~~c++ attrs", "render", "~~~", "plain" }, 2)
assert(text.kind(fence) == "code" and text.snippet_filetype(fence) == "cpp" and prefix(fence) == "")
local snippets = require("blink.cmp.sources.snippets.default").new { get_filetype = text.snippet_filetype }
assert(
  vim
    .iter(query(function(cb)
      snippets:get_completions(fence, cb)
    end))
    :any(function(item)
      return item.label == "sca"
    end),
  "Missing C++ snippets inside fenced code"
)
assert(text.kind(context { "```js", "render" }) == "code", "Incomplete fences still contain code")
vim.bo.filetype = "cpp"
assert(text.kind(context { "// render" }) == "comment" and text.kind(context { 'auto v = "// unsafe";' }) == "code")
assert(text.kind(context({ 'auto v = "// unsafe";' }, 1, 17)) == "string")
vim.bo.filetype = "gitcommit"
assert(prefix(context { "# ignored" }) == "" and prefix(context { "Fix rende" }) == "rende")
vim.bo.filetype = "text"
local sample = context { "Our rende" }
local words = tmp .. "/words.txt"
vim.fn.writefile({ "render", "renderer", "rendered", "rendering", "renders" }, words)
provider.opts.dictionary_files = { words }
local dictionary = require("blink-cmp-dictionary").new(provider.opts, provider)
local matches = query(function(cb)
  dictionary:get_completions(sample, cb)
end)
assert(#matches == 3, "Dictionary should return at most three entries from a matching word list")
for _, item in ipairs(matches) do
  assert(item.label:match "^rende")
end
vim.fn.delete(tmp, "rf")
print "PASS: document-relative Markdown paths, fence language, prose dictionary and code comments"
