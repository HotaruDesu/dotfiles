local M = {}
local kinds = vim.lsp.protocol.CompletionItemKind
local semantic = require "lunavim.completion.semantic"
local full_list_tier = 12
local initials_tier = 4
local type_kinds = { struct = kinds.Struct, class = kinds.Class, enum = kinds.Enum }
local lexical_kinds = { [kinds.Keyword] = true, [kinds.Snippet] = true, [kinds.Variable] = true, [kinds.Field] = true, [kinds.Property] = true, [kinds.Constant] = true }

local function name(item)
  -- clangd decorates labels with spaces and bullets. LuaLS adds a call signature.
  local label = type(item.filterText) == "string" and item.filterText or vim.trim(item.label)
  return label:match "^([%a_][%w_]*)%s*%(" or label
end

local function context(ctx)
  local actual, cursor = ctx.get_line(), ctx.get_cursor()
  local line = actual:sub(1, cursor[2])
  local ft = vim.bo[ctx.bufnr].filetype
  local text = require "lunavim.completion.text"
  local position = ctx
  if ctx.line ~= actual or ctx.cursor[1] ~= cursor[1] or ctx.cursor[2] ~= cursor[2] then
    position = { mode = ctx.mode, bufnr = ctx.bufnr, line = actual, cursor = cursor, bounds = ctx.bounds }
  end
  local kind = text.kind(position)
  local keyword = vim.fn.matchstr(line, [[\k*$]])
  local query = keyword:lower()
  local before = line:sub(1, #line - #keyword)
  local cpp = ft == "cpp" or ft == "c" or ft == "objc" or ft == "objcpp"
  if cpp and kind ~= "comment" then
    local delimiter, path = line:match '^%s*#%s*include%s*([<"])([^>"]*)$'
    if path then
      return { kind = "header", query = path:match("([^/]*)$"):lower(), system = delimiter == "<" }
    end
  end
  if ft == "lua" and kind ~= "comment" then
    local module = line:match [[%f[%w_]require%s*%(?%s*["']([%w_./-]*)$]]
    if module then
      return { kind = "module", query = module:lower():gsub("/", ".") }
    end
  end
  if text.is_path(position) then
    return { kind = "path", query = "" }
  end
  if kind ~= "code" then
    return { kind = kind, query = query, markdown = ft == "markdown" }
  end
  if before:match "%.$" or before:match "%->$" or before:match "::$" or (ft == "lua" and before:match "[%w_%]%)]:$") then
    return { kind = "member", query = query }
  end
  local type_keyword = before:match "([%a_]+)%s+$"
  local call = actual:sub(cursor[2] + 1):match "^%s*%(" ~= nil
  local preferred
  if ft == "cpp" and not call and vim.startswith(query, "sta") and vim.startswith("static_cast", query) then
    preferred = require("lunavim.completion.cpp").keyword(position)
  end
  return {
    kind = cpp and "cpp" or "code",
    query = query,
    type_kind = type_kinds[type_keyword],
    expression = before:find "%f[%w_]return%s*$" or before:find "[=(,%[%+%-%*/!?:<>]%s*$",
    preferred = preferred,
    call = call,
  }
end

local function import_cost(item)
  if (type(item.additionalTextEdits) == "table" and #item.additionalTextEdits > 0) or vim.startswith(item.label, "•") then
    return 2
  end
  local insertion = type(item.textEdit) == "table" and item.textEdit.newText or item.insertText
  return type(insertion) == "string" and insertion:match "^[%w_]+::" and 1 or 0
end

local function cpp_rank(ctx, item, word, direct)
  local local_value = item.kind == kinds.Variable or item.kind == kinds.Field or item.kind == kinds.Constant
  if item.source_id == "lsp" then
    local cost = import_cost(item)
    if cost > 0 then
      return direct and 4 + cost or 9 + cost
    end
    if direct then
      if ctx.type_kind and item.kind == ctx.type_kind then
        return 1
      end
      if local_value and (word == ctx.query or ctx.expression or ctx.preferred == "static_cast") then
        return 1
      end
      if ctx.call and (item.kind == kinds.Function or item.kind == kinds.Method or item.kind == kinds.Constructor) then
        return 1
      end
      if ctx.preferred then
        return word == ctx.preferred and 2 or 3
      end
      if word == ctx.query and not ctx.type_kind then
        return 1
      end
      return 2
    end
    return 7
  end
  if item.source_id == "cpp_syntax" then
    return word == ctx.preferred and 2 or 3
  end
  if direct and item.source_id == "snippets" and ctx.query == word then
    return 2
  end
  return direct and 4 or 9
end

local function initials_match(label, query)
  if #query < 2 or not label:find "[_%u]" then
    return false
  end
  -- Only classify items Blink already matched. "pb" is a word-boundary match
  -- in push_back / pushBack, but an arbitrary subsequence in playbook.
  local separated = label:gsub("(%l)(%u)", "%1_%2"):gsub("(%u)(%u%l)", "%1_%2")
  local i = 0
  for first in ("_" .. separated):gmatch "_+([%w])" do
    i = i + 1
    if query:sub(i, i) ~= first:lower() then
      return false
    end
    if i == #query then
      return true
    end
  end
  return false
end

local function rank(ctx, item, label)
  local source = item.source_id
  local word = label:lower()
  local direct = vim.startswith(word, ctx.query)
  local lsp = source == "lsp" or source == "lazydev"
  if ctx.kind == "member" then
    if lsp and direct then
      return 1 + import_cost(item)
    end
    if lsp and initials_match(label, ctx.query) then
      return initials_tier + import_cost(item)
    end
  elseif ctx.kind == "module" then
    if source == "path" or source == "lazydev" or (lsp and (item.kind == kinds.Module or item.kind == kinds.File or item.kind == kinds.Folder)) then
      if direct or vim.startswith(word:gsub("/", "."), ctx.query) then
        return 1
      end
      -- Some providers replace just the last segment of a dotted module.
      local leaf = ctx.query:match "[./]([^./]*)$"
      if leaf and (source == "path" or not word:find "[./]") and vim.startswith(word, leaf) then
        return 2
      end
    end
  elseif ctx.kind == "header" then
    if (source == "path" or lsp) and direct then
      local header = word:gsub('[>"]$', "")
      if header == ctx.query then
        return 1
      end
      -- Public C++ standard headers are extensionless, lower-case files.
      if ctx.system and item.kind ~= kinds.Folder and header:match "^[a-z][a-z0-9_]*$" then
        return 2
      end
      return 3
    end
  elseif ctx.kind == "path" then
    if source == "path" or (lsp and (item.kind == kinds.File or item.kind == kinds.Folder)) then
      return 1
    end
  elseif ctx.kind == "cpp" then
    return cpp_rank(ctx, item, word, direct)
  elseif ctx.kind == "comment" or ctx.kind == "prose" or ctx.kind == "string" then
    if source == "snippets" or item.kind == kinds.Snippet then
      -- Markdown has useful explicit triggers such as "table" and "link".
      if ctx.markdown and ctx.kind == "prose" and word == ctx.query then
        return 2
      end
    elseif source ~= "cpp_syntax" then
      if source == "dictionary" then
        return 5
      end
      if word == ctx.query then
        return 1
      end
      return direct and 2 or 4
    end
  else
    if direct then
      if word == ctx.query then
        return 1
      end
      return lsp and lexical_kinds[item.kind] and 2 or 3
    end
    return 4
  end
end

-- Blink has already sorted these candidates. Seed a collision group with the
-- user's explicit selection so a late copy cannot take over its Enter action.
local function add_lsp(groups, label, item, ctx)
  local group = groups[label]
  if not group then
    groups[label] = { item }
    return true
  end
  for _, other in ipairs(group) do
    if semantic.same(item, other, ctx) then
      return false
    end
  end
  group[#group + 1] = item
  return true
end

local function callable(item)
  return item.kind == kinds.Function or item.kind == kinds.Method or item.kind == kinds.Constructor
end

local function merge(ctx, items)
  if ctx.mode ~= "default" or #items == 0 then
    return items
  end
  local navigation = require "lunavim.completion.navigation"
  local selected, index = navigation.selected(ctx)
  local full = navigation.is_full(ctx)
  local scope = context(ctx)
  local ranks, names = {}, {}
  local matched, direct_member, selected_item = false, false, nil
  for i, item in ipairs(items) do
    names[i] = name(item)
    local tier = rank(scope, item, names[i])
    if tier then
      matched = true
      if scope.kind == "member" and tier < initials_tier then
        direct_member = true
      end
    end
    -- Full completion keeps all sources while still putting contextual matches first.
    ranks[i] = tier or (full and full_list_tier or nil)
    if item == selected or (selected and not selected_item and navigation.same_item(selected, item, ctx)) then
      selected_item = item
    end
  end
  local semantic_names, syntax, buffers, lsp = {}, {}, {}, {}
  if selected_item and selected_item.source_id == "lsp" then
    add_lsp(lsp, name(selected_item), selected_item, ctx)
  end
  for i, item in ipairs(items) do
    -- An unattached server, unknown member or typo can still use local words.
    if not matched and scope.kind == "member" and item.source_id == "buffer" then
      ranks[i] = 1
    elseif direct_member and not full and ranks[i] and ranks[i] >= initials_tier then
      ranks[i] = nil
    end
    if ranks[i] or item == selected_item then
      local source = item.source_id
      local label = names[i]
      if source == "lsp" then
        if item ~= selected_item and not add_lsp(lsp, label, item, ctx) then
          ranks[i] = nil
        elseif import_cost(item) == 0 and (scope.kind ~= "member" or callable(item)) then
          semantic_names[label] = true
        end
      elseif source == "lazydev" or source == "snippets" then
        semantic_names[label] = true
      elseif source == "cpp_syntax" then
        syntax[label] = true
      elseif source == "buffer" then
        buffers[label] = item
      end
    end
  end
  local hidden = scope.kind == "header" and require("lunavim.completion.headers").shadowed(ctx, items, ranks, selected_item, full) or {}
  for label, buffer in pairs(buffers) do
    local group = lsp[label]
    if group and (scope.kind == "member" or buffer == selected_item) then
      for _, symbol in ipairs(group) do
        if not symbol.command and not callable(symbol) and (scope.kind == "member" or import_cost(symbol) == 0) and semantic.same_edit(buffer, symbol, ctx) then
          if buffer ~= selected_item then
            hidden[buffer] = true
          elseif #group == 1 then
            -- An explicit buffer preview wins this refresh. Keep distinct
            -- overloads or import choices available when there are several.
            hidden[symbol] = true
          end
        end
      end
    end
  end
  local buckets = {}
  for i, item in ipairs(items) do
    local tier = ranks[i]
    if tier and item ~= selected_item and not hidden[item] then
      local source, label = item.source_id, names[i]
      local duplicate = source == "buffer" and (semantic_names[label] or syntax[label])
        or source == "cpp_syntax" and semantic_names[label]
        or source == "dictionary" and buffers[label]
      if not duplicate then
        buckets[tier] = buckets[tier] or {}
        table.insert(buckets[tier], item)
      end
    end
  end
  local result = {}
  -- Keep Blink's fuzzy score, frecency and server order within each tier.
  for tier = 1, full_list_tier do
    if buckets[tier] then
      vim.list_extend(result, buckets[tier])
    end
  end
  if selected_item then
    table.insert(result, math.min(index, #result + 1), selected_item)
  end
  return semantic.annotate(result, require("blink.cmp.config").completion.list.max_items)
end

function M.setup()
  local sources = require "blink.cmp.sources.lib"
  if sources._lunavim_menu then
    return
  end
  -- Pinned Blink 1.10.2 calls this after fuzzy sorting and before its global slice.
  local limit_sources = sources.apply_max_items_for_completions
  sources.apply_max_items_for_completions = function(ctx, items)
    return merge(ctx, limit_sources(ctx, items))
  end
  sources._lunavim_menu = true
end

return M
