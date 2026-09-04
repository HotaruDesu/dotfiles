local M = {}

local levels = {
  debug = vim.log.levels.DEBUG,
  error = vim.log.levels.ERROR,
  info = vim.log.levels.INFO,
  trace = vim.log.levels.TRACE,
  warn = vim.log.levels.WARN,
  off = vim.log.levels.OFF,
}

function M.log_debug(msg)
  vim.notify(msg, levels.debug)
end

function M.log_error(msg)
  vim.notify(msg, levels.error)
end

function M.log_info(msg)
  vim.notify(msg, levels.info)
end

function M.log_trace(msg)
  vim.notify(msg, levels.trace)
end

function M.log_warn(msg)
  vim.notify(msg, levels.warn)
end

function M.log_off(msg)
  vim.notify(msg, levels.off)
end

return M
