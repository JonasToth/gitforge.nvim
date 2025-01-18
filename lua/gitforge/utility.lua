local M = {}

---@param path string Path to a file
---@return string|nil The content of the file read with 'rb' or nil if that failed.
function M.read_file_to_string(path)
    local file = io.open(path, "rb") -- r read mode and b binary mode
    if not file then return nil end
    local content = file:read "*a" -- *a or *all reads the whole file
    file:close()
    return content
end

---Creates a string from the buffer content of @p buf
---@param buf integer Buffer Id to get the content from.
---@return string content Concatenation with "\n" and final trimming of the buffer content.
function M.buffer_to_string(buf)
    local curr_buf_content = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    return vim.trim(vim.fn.join(curr_buf_content, "\n"))
end

---Copies the buffer content from @c from_buf to @c to_buf.
---@param from_buf integer
---@param to_buf integer
function M.copy_buffer(from_buf, to_buf)
    local curr_buf_content = vim.api.nvim_buf_get_lines(from_buf, 0, -1, false)
    vim.api.nvim_buf_set_lines(to_buf, 0, -1, false, curr_buf_content)
end

---@param command table<string>|nil
---@param completion_func function
---@return vim.SystemObj|nil
function M.async_exec(command, completion_func)
    local log = require("gitforge.log")

    if command == nil then
        log.notify_failure("Provided command was 'nil'. Maybe your provider does not support this action")
        return nil
    end
    log.executed_command(command)
    return vim.system(command, { text = true, timeout = require("gitforge").opts.timeout }, completion_func)
end

return M
