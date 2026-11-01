local M = {}
local uv = vim.uv
local wrapped = setmetatable({}, { __mode = "k" })

local function stop_timer(state)
  if state.timer then
    state.timer:stop()
    if not state.timer:is_closing() then
      state.timer:close()
    end
    state.timer = nil
  end
end

local function loaded_buffer(item, path)
  local buf = item.buf
  if not (buf and vim.api.nvim_buf_is_loaded(buf)) and path then
    buf = vim.fn.bufnr(path)
  end
  return buf and buf > 0 and vim.api.nvim_buf_is_loaded(buf) and buf or nil
end

local function truncate_lines(lines, max_line_length)
  for i, line in ipairs(lines) do
    if #line > max_line_length then
      lines[i] = line:sub(1, max_line_length) .. "..."
    end
  end
  return lines
end

local function text_lines(text, max_line_length)
  local lines = vim.split(text:gsub("\r\n", "\n"), "\n", { plain = true })
  if lines[#lines] == "" then
    table.remove(lines)
  end
  return truncate_lines(lines, max_line_length)
end

---Delay file previews until selection settles, keeping file I/O out of input.
---The returned close callback must be chained into the picker's on_close hook.
---@param original fun(ctx: snacks.picker.preview.ctx): boolean?
---@param opts? {delay_ms?:integer, plain_size?:integer, max_size?:integer}
---@return fun(ctx: snacks.picker.preview.ctx), fun(picker: snacks.Picker)
function M.wrap(original, opts)
  if wrapped[original] then
    return original, wrapped[original]
  end
  opts = vim.tbl_extend("force", { delay_ms = 120, plain_size = 256 * 1024, max_size = 1024 * 1024 }, opts or {})
  local states = setmetatable({}, { __mode = "k" })

  local function close(picker)
    local state = states[picker]
    if state then
      state.token = state.token + 1
      stop_timer(state)
      states[picker] = nil
    end
  end

  local function preview(ctx)
    local picker = ctx.picker
    local state = states[picker]
    if not state then
      state = { token = 0 }
      states[picker] = state
    end
    stop_timer(state)
    state.token = state.token + 1
    local token = state.token
    local item = ctx.item
    local pos = vim.deepcopy(item.pos)
    local win = ctx.preview.win.win

    local function valid()
      return states[picker] == state
        and state.token == token
        and not picker.closed
        and ctx.preview.win:valid()
        and ctx.preview.win.win == win
        and vim.api.nvim_win_is_valid(win)
        and not picker.layout:is_hidden "preview"
        and picker:current { resolve = false } == item
        and vim.deep_equal(item.pos, pos)
    end

    -- Rendering is asynchronous now, so reproduce the synchronous preview's
    -- buffer cleanup and title update after each completed operation.
    local function render(callback, rendered_item)
      if not valid() then
        return
      end
      local old_buf = ctx.preview.win.buf
      local ok, result = pcall(callback)
      if not ok then
        ctx.preview:reset()
        ctx.preview:set_title "Preview unavailable"
        ctx.preview:set_lines { "Could not load preview:", tostring(result) }
      end
      local new_buf = ctx.preview.win.buf
      if new_buf ~= old_buf then
        ctx.preview:clear(old_buf)
      end
      ctx.preview.win:set_title(ctx.preview.title or "")
      state.rendered_item = ok and result ~= false and rendered_item or nil
      state.rendered_win = win
      state.rendered_buf = new_buf
      state.rendered_tick = vim.api.nvim_buf_get_changedtick(new_buf)
    end

    local function plain(lines, title)
      render(function()
        -- reset() switches to the preview scratch before stopping its parser.
        -- Never stop Treesitter or change options on an open source buffer.
        ctx.preview:reset()
        ctx.preview:set_title(title)
        ctx.preview:set_lines(lines)
        ctx.preview:loc()
      end)
    end

    local function begin()
      if not valid() then
        return
      end
      local path = Snacks.picker.util.path(item)
      local buf = loaded_buffer(item, path)
      local stat = not buf and path and uv.fs_stat(path) or nil
      local size = buf and vim.api.nvim_buf_get_offset(buf, vim.api.nvim_buf_line_count(buf)) or stat and stat.size
      local title = item.preview_title or item.title or path and vim.fn.fnamemodify(path, ":t") or "Preview"
      local file_opts = picker.opts.previewers.file
      local max_size = math.min(opts.max_size, file_opts.max_size or opts.max_size)
      local line_length = file_opts.max_line_length or 500

      if size and size > max_size then
        plain(
          { ("File is %.1f MiB; preview limit is %.1f MiB."):format(size / 1024 / 1024, max_size / 1024 / 1024), "Open the file to view its contents." },
          title .. " (too large)"
        )
        return
      end
      if size and size >= opts.plain_size and (buf or stat and stat.type == "file") then
        if buf then
          local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
          plain(truncate_lines(lines, line_length), title .. " (plain text)")
          return
        end
        uv.fs_open(
          path,
          "r",
          438,
          vim.schedule_wrap(function(open_err, fd)
            if not fd then
              if valid() then
                plain({ "Could not read file:", tostring(open_err) }, title)
              end
              return
            end
            if not valid() then
              uv.fs_close(fd)
              return
            end
            -- One bounded asynchronous read is enough for the medium-file tier.
            -- File descriptors are closed even if a selection changes mid-read.
            uv.fs_read(fd, max_size + 1, 0, function(read_err, data)
              uv.fs_close(fd)
              vim.schedule(function()
                if not valid() then
                  return
                end
                if read_err or not data then
                  plain({ "Could not read file:", tostring(read_err) }, title)
                elseif #data > max_size then
                  plain({ "File grew beyond the preview limit.", "Open the file to view its contents." }, title .. " (too large)")
                elseif data:find "[%z\1-\8\11\12\14-\31]" then
                  plain({ "Binary file; open it to inspect its contents." }, title .. " (binary)")
                else
                  plain(text_lines(data, line_length), title .. " (plain text)")
                end
              end)
            end)
          end)
        )
        return
      end

      local rendered_item = vim.tbl_extend("force", {}, item, buf and { buf = buf } or {})
      -- A no-match query resets the existing scratch in place. Its window and
      -- buffer handles survive, but its contents no longer represent the last
      -- rendered file, so the default file preview must read that file again.
      local previous = state.rendered_win == win
          and state.rendered_buf == ctx.preview.win.buf
          and state.rendered_tick == vim.api.nvim_buf_get_changedtick(ctx.preview.win.buf)
          and state.rendered_item
        or nil
      local proxy = setmetatable({ item = rendered_item }, {
        __index = function(_, key)
          if key == "prev" then
            return previous
          end
          return ctx[key]
        end,
      })
      render(function()
        return original(proxy)
      end, rendered_item)
    end

    local timer = assert(uv.new_timer())
    state.timer = timer
    timer:start(
      opts.delay_ms,
      0,
      vim.schedule_wrap(function()
        if state.timer == timer then
          stop_timer(state)
        end
        if valid() then
          local ok, err = pcall(begin)
          if not ok then
            plain({ "Could not load preview:", tostring(err) }, "Preview unavailable")
          end
        end
      end)
    )
  end

  wrapped[preview] = close
  return preview, close
end

return M
