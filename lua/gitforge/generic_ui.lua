local GenericUI = {
    ---Constant to identify issue buffers.
    forge_issue_pattern = '[Issue] #'
}

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
function GenericUI.open_edit_window(buf)
    set_buffer_options_for_edit(buf)
    local win_split = vim.api.nvim_open_win(buf, true, {
        split = "below",
    })
    return win_split
end

---Creates a floating window for @c buf with the title @c title_ui
---Creates an autocommand to close the floating window if it looses focus.
---@param buf number Buffer-ID to display in the window.
function GenericUI.create_issue_window(buf)
    local win_options = {
        split = "above",
    }
    local win = vim.api.nvim_open_win(buf, true, win_options)
    if win == 0 then
        require("gitforge.log").notify_failure("Failed to open float for issue")
        return
    end
    -- Switch to normal mode - Telescope selection leaves in insert mode?!
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "i", false)
end

--- Returns the standardized title of an issue.
--- @param issue_json Issue Table representation of the issue JSON.
--- @return string title concatenation of issue number and a shortened title.
function GenericUI.issue_title_ui(issue_json)
    local length_threshold = 50
    local shortened_title = string.sub(issue_json.title, 1, length_threshold)
    local title_id = GenericUI.forge_issue_pattern .. tostring(issue_json.number)
    local three_dots = #issue_json.title > length_threshold and "..." or ""
    return title_id .. " - " .. shortened_title .. three_dots
end

---Finds an existing buffer that holds @c issue_number.
---@param issue_number string|nil
---@return integer buf_id if a matching buffer is found, otherwise @c 0
function GenericUI.find_existing_issue_buffer(issue_number)
    if issue_number == nil then
        return 0
    end
    local title_id = GenericUI.forge_issue_pattern .. issue_number
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

---@param provider GHIssue|nil
---@param completion function|nil
function GenericUI.refresh_issue(provider, completion)
    local log = require("gitforge.log")
    local prov = provider or require(require("gitforge").opts.default_issue_provider)

    local command = prov:cmd_fetch()

    return require("gitforge.utility").async_exec(command,
        function(handle)
            if handle.code ~= 0 then
                -- log.notify_failure("Failed to retrieve issue content")
                print("Failed to retrieve issue content")
                return
            end
            vim.schedule(function()
                local generic_issue = require("gitforge.generic_issue")

                local issue = prov:convert_cmd_result_to_issue(handle.stdout)
                log.trace_msg("update single issue in buf: " .. tostring(prov.buf))
                provider.buf = generic_issue.render_issue_to_buffer(prov.buf, issue)

                local title_ui = require("gitforge.generic_ui").issue_title_ui(issue)
                vim.api.nvim_buf_set_name(prov.buf, title_ui)
                generic_issue.set_issue_buffer_options(prov)
                log.ephemeral_info("Updated content for issue " .. prov.issue_number)

                if completion ~= nil then
                    completion(prov)
                end
            end)
        end)
end

---Blocking call to update the issue on the git forge and update the local content.
---@param provider GHIssue|nil Implementation for command generation.
---@param command_generator function Generate the command to execute.
function GenericUI.perform_issue_update_cmd(provider, command_generator)
    local log = require("gitforge.log")
    local prov = provider or require(require("gitforge").opts.default_issue_provider)

    local command = command_generator(prov)
    if command == nil then
        log.notify_failure("Failed to create command to update issue!")
        return
    end
    local handle_cmd_completion = function(handle)
        vim.schedule(function()
            if handle.code ~= 0 then
                --TODO: Better error logging
                vim.api.nvim_err_write(handle.stderr)
                vim.api.nvim_err_write(handle.stdout)
                log.notify_failure("Failed to update issue!")
                return
            end
            log.notify_change("Updated Issue")
            GenericUI.refresh_issue(prov)
        end)
    end
    require("gitforge.utility").async_exec(command, handle_cmd_completion):wait()
end

---@param buf integer
---@param tmp_file string path to temporary file
---@param switch_to_insert boolean directly switch to insert mode for faster text input.
---@param action function
---@param cleanup function
function GenericUI.setup_file_command_on_close(buf, tmp_file, switch_to_insert, action, cleanup)
    vim.api.nvim_buf_set_name(buf, tmp_file)
    local win_split = GenericUI.open_edit_window(buf)
    if win_split == 0 then
        require("gitforge.log").notify_failure("Failed to create window to edit the description")
        cleanup()
        return
    end

    --Populating the buffer with content requires an initial write.
    vim.cmd("write! " .. tmp_file)
    vim.cmd("edit " .. tmp_file)

    if switch_to_insert then
        -- Switch to insert mode to be ready to type the write directly.
        vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("i", true, false, true), "n", false)
    end

    local autocmdid
    autocmdid = vim.api.nvim_create_autocmd("WinLeave", {
        group = vim.api.nvim_create_augroup("GitForge", { clear = true }),
        callback = function()
            if win_split ~= 0 then
                action()
                cleanup()
                win_split = 0
            end
            vim.api.nvim_del_autocmd(autocmdid)
        end,
    })
end

return GenericUI
