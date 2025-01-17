M = {}

local set_buffer_options_for_edit = function(buf)
    vim.api.nvim_set_option_value('readonly', false, { buf = buf })
    vim.api.nvim_set_option_value('modifiable', true, { buf = buf })
    vim.api.nvim_set_option_value('bufhidden', 'delete', { buf = buf })
    vim.api.nvim_set_option_value('buflisted', false, { buf = buf })
    vim.api.nvim_set_option_value('buftype', '', { buf = buf })
    vim.api.nvim_set_option_value('filetype', 'markdown', { buf = buf })
    vim.api.nvim_set_option_value('syntax', 'markdown', { buf = buf })
    vim.api.nvim_set_option_value('swapfile', false, { buf = buf })
end

---Opens a window split below and sets the provided buffer up for editing it.
---@return integer window ID of the new window.
function M.open_edit_window(buf)
    set_buffer_options_for_edit(buf)
    local win_split = vim.api.nvim_open_win(buf, true, {
        split = "below",
    })
    return win_split
end

---Creates a floating window for @c buf with the title @c title_ui
---Creates an autocommand to close the floating window if it looses focus.
---@param buf number Buffer-ID to display in the window.
---@param title_ui string Human Readable title for the window.
function M.create_issue_window(buf, title_ui)
    local width = math.ceil(math.min(vim.o.columns, math.min(100, vim.o.columns - 20)))
    local height = math.ceil(math.min(vim.o.lines, math.max(20, vim.o.lines - 10)))
    local row = math.ceil(vim.o.lines - height) * 0.5 - 1
    local col = math.ceil(vim.o.columns - width) * 0.5 - 1
    local win_options = {
        -- 'relative' creates a floating window
        relative = 'editor',
        title = title_ui,
        title_pos = 'center',
        width = width,
        height = height,
        col = col,
        row = row,
        border = "single"
    }
    local win = vim.api.nvim_open_win(buf, true, win_options)
    if win == 0 then
        require("gitforge.log").notify_failure("Failed to open float for issue")
        return
    end
    -- Switch to normal mode - Telescope selection leaves in insert mode?!
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "i", false)
    -- FIXME: This autocmd definition fails with vim.ui.input() Calls.
    --        The window is closed, even though it should still exist.
    --        Use <C-W>p to switch to the previous window if moving out of the float.
    -- -- Automatically close then float when it is left.
    -- local autocmdid
    -- autocmdid = a.nvim_create_autocmd("WinLeave", {
    --     -- group = a.nvim_create_augroup("GitForge", { clear = true }),
    --     callback = function()
    --         if win ~= 0 then
    --             a.nvim_win_close(win, true)
    --             win = 0
    --         end
    --         a.nvim_del_autocmd(autocmdid)
    --     end
    -- })
end

---Constant to identify issue buffers.
local forge_issue_pattern = '[Issue] #'

--- Returns the standardized title of an issue.
--- @param issue_json table Table representation of the issue JSON.
--- @return string title concatenation of issue number and a shortened title.
function M.issue_title_ui(issue_json)
    local length_threshold = 50
    local shortened_title = string.sub(issue_json.title, 1, length_threshold)
    local title_id = forge_issue_pattern .. tostring(issue_json.number)
    local three_dots = #issue_json.title > length_threshold and "..." or ""
    return title_id .. " - " .. shortened_title .. three_dots
end

---Finds an existing buffer that holds @c issue_number.
---@param issue_number number
---@return integer buf_id if a matching buffer is found, otherwise @c 0
function M.find_existing_issue_buffer(issue_number)
    local title_id = forge_issue_pattern .. tostring(issue_number)
    local all_bufs = vim.api.nvim_list_bufs()

    for _, buf_id in pairs(all_bufs) do
        local buf_name = vim.api.nvim_buf_get_name(buf_id)
        local found = string.find(buf_name, title_id, 1, true)
        if found ~= nil then
            return buf_id
        end
    end
    return 0
end

return M
