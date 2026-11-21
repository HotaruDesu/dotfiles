local M = {}
local uv = vim.uv
local wrapped = setmetatable({}, { __mode = "k" })

local function input_pending(picker)
  local filter = picker.input.filter
  return picker.input:get() ~= (picker.opts.live and filter.search or filter.pattern)
end

local function stop_timer(state, key)
  local timer = state[key]
  if timer then
    timer:stop()
    if not timer:is_closing() then
      timer:close()
    end
    state[key] = nil
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

---Snacks throttles selection previews. Only defer expensive highlighting here.
---The returned close callback must be chained into the picker's on_close hook.
---@param original fun(ctx: snacks.picker.preview.ctx): boolean?
---@param opts? {delay_ms?:integer, highlight_ms?:integer, plain_size?:integer, max_size?:integer}
---@return fun(ctx: snacks.picker.preview.ctx), fun(picker: snacks.Picker)
function M.wrap(original, opts)
  if wrapped[original] then
    return original, wrapped[original]
  end
  opts = vim.tbl_extend("force", { delay_ms = 0, highlight_ms = 80, plain_size = 256 * 1024, max_size = 1024 * 1024 }, opts or {})
  local states = setmetatable({}, { __mode = "k" })
  local ordinary = original == require("snacks.picker.preview").file

  local function close(picker)
    local state = states[picker]
    if state then
      states[picker] = nil
      state.token = state.token + 1
      state.pending = nil
      stop_timer(state, "timer")
      stop_timer(state, "highlight_timer")
      state.detach()
      vim.api.nvim_del_autocmd(state.input_listener)
      -- In-flight libuv callbacks still own and close their file descriptor.
    end
  end

  local function preview(ctx)
    local picker = ctx.picker
    local state = states[picker]
    if not state then
      state = { token = 0, query = picker.input:get(), input_at = uv.hrtime() }
      states[picker] = state
      state.observe = function()
        local item = not picker.closed and picker:current { resolve = false } or nil
        local query = not picker.closed and picker.input:get() or nil
        local query_changed = query ~= state.query
        if query_changed then
          state.query, state.input_at = query, uv.hrtime()
          state.changed_at = state.input_at
          stop_timer(state, "highlight_timer")
        end
        if item ~= state.selected or not vim.deep_equal(item and item.pos, state.selected_pos) then
          state.selected, state.selected_pos = item, item and item.pos and vim.deepcopy(item.pos)
          state.changed_at = uv.hrtime()
          state.token = state.token + 1
          state.pending = nil
          state.resume_highlight = nil
          stop_timer(state, "highlight_timer")
        end
        if not query_changed and not picker:is_active() and not input_pending(picker) and state.resume_highlight and not state.highlight_timer then
          state.resume_highlight()
        end
        if state.wake then
          state.wake()
        end
      end
      state.detach = require("lunavim.search.observe").attach(picker, state.observe)
      state.input_listener = vim.api.nvim_create_autocmd({ "TextChangedI", "TextChanged" }, {
        buffer = picker.input.win.buf,
        callback = state.observe,
      })
    end
    state.observe()
    stop_timer(state, "timer")
    stop_timer(state, "highlight_timer")
    state.resume_highlight = nil
    state.token = state.token + 1
    local token, item = state.token, ctx.item
    local pos, win = item.pos and vim.deepcopy(item.pos), ctx.preview.win.win
    local function valid()
      return states[picker] == state
        and state.token == token
        and not picker.closed
        and ctx.preview.win:valid()
        and ctx.preview.win.win == win
        and not picker.layout:is_hidden "preview"
        and picker:current { resolve = false } == item
        and vim.deep_equal(item.pos, pos)
    end
    local path = Snacks.picker.util.path(item)
    local title = item.preview_title or item.title or path and vim.fn.fnamemodify(path, ":t") or "Preview"
    local file_opts = picker.opts.previewers.file
    local max_size = math.min(opts.max_size, file_opts.max_size or opts.max_size)
    local line_length = file_opts.max_line_length or 500

    local function remember(rendered_item)
      state.rendered_item = rendered_item
      state.rendered_win, state.rendered_buf = win, ctx.preview.win.buf
      state.rendered_tick = vim.api.nvim_buf_get_changedtick(ctx.preview.win.buf)
    end
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
      if ctx.preview.win.buf ~= old_buf then
        ctx.preview:clear(old_buf)
      end
      ctx.preview.win:set_title(ctx.preview.title or "")
      remember(ok and result ~= false and rendered_item or nil)
    end
    local function plain(lines, label, rendered_item)
      render(function()
        -- reset switches away from source buffers before stopping a parser.
        ctx.preview:reset()
        ctx.preview:set_title(label)
        ctx.preview:set_lines(lines)
        ctx.preview:loc()
      end, rendered_item)
    end
    local function failure(err)
      plain({ "Could not load preview:", tostring(err) }, "Preview unavailable")
    end
    local function too_large()
      plain({ "File exceeds the preview limit of " .. max_size / 1024 .. " KiB.", "Open the file to view its contents." }, title .. " (too large)")
    end
    local function previous()
      return state.rendered_win == win
          and state.rendered_buf == ctx.preview.win.buf
          and state.rendered_tick == vim.api.nvim_buf_get_changedtick(ctx.preview.win.buf)
          and state.rendered_item
        or nil
    end
    local function highlight()
      if not valid() or not previous() then
        return
      end
      local buf, tick = ctx.preview.win.buf, state.rendered_tick
      state.resume_highlight = highlight
      local timer = assert(uv.new_timer())
      state.highlight_timer = timer
      local remaining = math.max(0, opts.highlight_ms - (uv.hrtime() - state.changed_at) / 1e6)
      timer:start(
        remaining,
        0,
        vim.schedule_wrap(function()
          if state.highlight_timer ~= timer then
            return
          end
          stop_timer(state, "highlight_timer")
          state.resume_highlight = nil
          if valid() and ctx.preview.win.buf == buf and vim.api.nvim_buf_get_changedtick(buf) == tick then
            -- Only our scratch buffer reaches this path; source parsers are reused.
            local ok, err = pcall(ctx.preview.highlight, ctx.preview, { file = path, ft = file_opts.ft, buf = buf })
            if not ok then
              vim.b[buf].lunavim_preview_highlight_error = tostring(err)
            end
          end
        end)
      )
    end
    local function delegate(buf)
      local rendered_item = vim.tbl_extend("force", {}, item, buf and { buf = buf } or {})
      local prev = previous()
      local proxy = setmetatable({ item = rendered_item }, {
        __index = function(_, key)
          if key == "prev" then
            return prev
          end
          return ctx[key]
        end,
      })
      render(function()
        return original(proxy)
      end, rendered_item)
    end

    -- One read chain and one replaceable pending request, even on slow disks.
    local pump
    pump = function()
      if state.active or not state.pending or states[picker] ~= state then
        return
      end
      local request = state.pending
      if not request.valid() then
        state.pending = nil
        return
      end
      -- Finding/matching and typed input have priority over preview rendering.
      -- Selection-only navigation does not incur this typing grace period.
      -- Snacks' live-query throttle can be waiting with no active finder yet.
      -- Do not render the previous query's selection during that idle gap.
      if picker:is_active() or input_pending(picker) then
        return
      end
      local now = uv.hrtime()
      local ready_at = math.max(request.ready_at, state.input_at and state.input_at + 80e6 or 0)
      if now < ready_at then
        if not state.timer then
          local timer = assert(uv.new_timer())
          state.timer = timer
          timer:start(
            math.ceil((ready_at - now) / 1e6),
            0,
            vim.schedule_wrap(function()
              if state.timer == timer then
                stop_timer(state, "timer")
                pump()
              end
            end)
          )
        end
        return
      end
      state.pending = nil
      state.active = true
      local function done(callback)
        local ok, err = true, nil
        if callback and request.valid() then
          if picker:is_active() or input_pending(picker) or state.input_at and uv.hrtime() < state.input_at + 80e6 then
            -- Keep the latest selection through a typed query without forcing
            -- extra preview callbacks or redraws of unchanged results.
            state.pending = state.pending or request
          else
            ok, err = pcall(callback)
          end
        end
        if not ok then
          request.failure(err)
        end
        state.active = false
        if state.pending then
          vim.schedule(pump)
        end
      end
      local ok, err = pcall(request.run, done)
      if not ok then
        done(function()
          request.failure(err)
        end)
      end
    end

    local function render_loaded(buf)
      local size = vim.api.nvim_buf_get_offset(buf, vim.api.nvim_buf_line_count(buf))
      if size > max_size then
        too_large()
      elseif size >= opts.plain_size then
        plain(truncate_lines(vim.api.nvim_buf_get_lines(buf, 0, -1, false), line_length), title .. " (plain text)")
      elseif ordinary then
        render(function()
          ctx.preview:set_title(title)
          ctx.preview:set_buf(buf)
          ctx.preview:loc()
        end, item)
      else
        delegate(buf)
      end
    end
    local function begin(done)
      local buf = loaded_buffer(item, path)
      if buf then
        return done(function()
          render_loaded(buf)
        end)
      end
      -- Custom, URI and image previewers retain their own semantics.
      if not ordinary or not path or path:find "^%w+://" or Snacks.image.supports_file(path) and Snacks.image.config.enabled ~= false then
        return done(function()
          delegate()
        end)
      end
      local prev = previous()
      if prev and Snacks.picker.util.path(prev) == path then
        return done(function()
          render(function()
            ctx.preview:loc()
          end, item)
          if not vim.treesitter.highlighter.active[ctx.preview.win.buf] and vim.bo[ctx.preview.win.buf].syntax == "" then
            highlight()
          end
        end)
      end
      uv.fs_stat(
        path,
        vim.schedule_wrap(function(stat_err, stat)
          if not valid() then
            return done()
          end
          if not stat then
            return done(function()
              failure(stat_err)
            end)
          elseif stat.type == "directory" then
            return done(function()
              delegate()
            end)
          elseif stat.type ~= "file" then
            return done(function()
              plain({ "Not a regular file; open it to inspect its contents." }, title)
            end)
          elseif stat.size > max_size then
            return done(too_large)
          end
          uv.fs_open(
            path,
            "r",
            438,
            vim.schedule_wrap(function(open_err, fd)
              if not fd then
                return done(function()
                  failure(open_err)
                end)
              end
              local function finish(read_err, data)
                uv.fs_close(fd, function()
                  vim.schedule(function()
                    done(function()
                      local source = loaded_buffer(item, path)
                      if source then
                        -- A source may have opened/changed while the disk read ran.
                        render_loaded(source)
                      elseif read_err or not data then
                        failure(read_err)
                      elseif #data > max_size then
                        too_large()
                      elseif data:find "%z" or data:find "[\1-\8\11\12\14-\31]" and not (file_opts.ft or vim.filetype.match { filename = path }) then
                        plain({ "Binary file; open it to inspect its contents." }, title .. " (binary)")
                      else
                        local small = #data < opts.plain_size
                        plain(text_lines(data, line_length), title .. (small and "" or " (plain text)"), small and item or nil)
                        if small then
                          highlight()
                        end
                      end
                    end)
                  end)
                end)
              end
              if not valid() then
                return finish(nil, nil)
              end
              uv.fs_read(fd, max_size + 1, 0, finish)
            end)
          )
        end)
      )
    end
    state.pending = { valid = valid, run = begin, failure = failure, ready_at = uv.hrtime() + opts.delay_ms * 1e6 }
    state.wake = function()
      if not state.pending or state.active or state.scheduled or picker:is_active() or input_pending(picker) then
        return
      end
      state.scheduled = true
      vim.schedule(function()
        state.scheduled = false
        pump()
      end)
    end
    state.wake()
  end

  wrapped[preview] = close
  return preview, close
end

return M
