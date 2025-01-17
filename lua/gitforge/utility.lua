local M = {}

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

---@param command table<string>
---@param completion_func function
---@return vim.SystemObj 
function M.async_exec(command, completion_func)
    require("gitforge.log").executed_command(command)
    return vim.system(command, { text = true, timeout = require("gitforge").opts.timeout }, completion_func)
end

return M
