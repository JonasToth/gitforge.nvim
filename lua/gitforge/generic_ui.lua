local GenericUI = {
    ---Constant to identify issue buffers.
    forge_issue_pattern = "[Issue]"
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

---Sets the title of a buffer to a custom URI for this plugin.
---@param buf integer Buffer-ID
---@param new_title string New Title
function GenericUI.set_buf_title(buf, new_title)
    vim.api.nvim_buf_set_name(buf, "gitforge://" .. new_title)
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
        require("gitforge.log").notify_failure("Failed to open window for issue")
        return
    end
    -- Switch to normal mode - Telescope selection leaves in insert mode?!
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "i", false)
end

local generate_issue_id = function(project, number)
    local title_id = GenericUI.forge_issue_pattern
    if project then
        title_id = title_id .. " " .. project
    end
    title_id = title_id .. " #" .. tostring(number)
    return title_id
end

--- Returns the standardized title of an issue.
--- @param issue Issue Table representation of the issue JSON.
--- @return string title concatenation of issue number and a shortened title.
function GenericUI.issue_title_ui(issue)
    local length_threshold = require("gitforge").opts.list_max_title_length
    local title = generate_issue_id(issue.project, issue.number) .. " - " .. issue.title
    local three_dots = #title > length_threshold and "..." or ""
    local shortened_title = string.sub(title, 1, length_threshold)
    return shortened_title .. three_dots
end

---Finds an existing buffer that holds @c issue_number.
---@param project string|nil
---@param issue_number string|nil
---@return integer buf_id if a matching buffer is found, otherwise @c 0
function GenericUI.find_existing_issue_buffer(project, issue_number)
    if issue_number == nil or project == nil then
        return 0
    end
    local title_id = generate_issue_id(project, issue_number)
    local all_bufs = vim.api.nvim_list_bufs()
    require("gitforge.log").trace_msg("Looking for: " .. title_id)

    for _, buf_id in ipairs(all_bufs) do
        local buf_name = vim.api.nvim_buf_get_name(buf_id)
        local found = string.find(buf_name, title_id, 1, true)
        if found ~= nil then
            return buf_id
        end
    end
    return 0
end

---@param provider IssueProvider|nil
---@param completion function|nil
---@return vim.SystemObj|nil
function GenericUI.refresh_issue(provider, completion)
    local log = require("gitforge.log")
    local prov = provider or require("gitforge.issue_provider").get_from_cwd_or_default()

    local command = prov:cmd_fetch()

    return require("gitforge.utility").async_exec(command,
        function(handle)
            if handle.code ~= 0 then
                log.notify_failure("Failed to retrieve issue content")
                return
            end
            vim.schedule(function()
                local generic_issue = require("gitforge.generic_issue")
                local generic_ui = require("gitforge.generic_ui")
                local util = require("gitforge.utility")

                local issue = prov:convert_cmd_result_to_issue(handle.stdout)
                if issue ~= nil then
                    log.trace_msg("update single issue in buf: " .. tostring(prov.buf))
                    prov.buf = generic_issue.render_issue_to_buffer(prov.buf, issue)
                else
                    log.notify_failure("Failed to refresh the issue in buffer " .. tostring(prov.buf))
                end

                local title_ui = generic_ui.issue_title_ui(issue)
                generic_ui.set_buf_title(prov.buf, title_ui)
                generic_issue.set_issue_buffer_options(prov)

                local persisted_issue_file = util.get_issue_data_file(prov)
                if persisted_issue_file:exists(false) then
                    local issue_content = util.buffer_to_string(prov.buf)
                    local worked = persisted_issue_file:io_write(issue_content)
                    if worked then
                        log.ephemeral_info("Updated content for issue " ..
                        prov.issue_number .. " and persisted it locally.")
                    else
                        log.ephemeral_info("Updated content for issue " ..
                        prov.issue_number .. " but failed to persist it locally.")
                    end
                else
                    log.ephemeral_info("Updated content for issue " .. prov.issue_number)
                end

                if completion ~= nil then
                    completion(prov)
                end
            end)
        end)
end

---Blocking call to update the issue on the git forge and update the local content.
---@param provider IssueProvider|nil Implementation for command generation.
---@param command_generator function Generate the command to execute.
function GenericUI.perform_issue_update_cmd(provider, command_generator)
    local log = require("gitforge.log")
    local prov = provider or require("gitforge.issue_provider").get_from_cwd_or_default()

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
    local handle = require("gitforge.utility").async_exec(command, handle_cmd_completion)
    if handle then handle:wait() end
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
