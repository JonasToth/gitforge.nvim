local IssueActions = {}

---@param provider GHIssue
function IssueActions.comment_on_issue(provider)
    local log = require("gitforge.log")
    local generic_ui = require("gitforge.generic_ui")

    local comment_buf = vim.api.nvim_create_buf(false, false)
    if comment_buf == 0 then
        log.notify_failure("Failed to create buffer for commenting")
        return
    end

    local comment_file = os.tmpname()
    local cleanup = function() os.remove(comment_file) end
    log.trace_msg("Tempfile for comment: " .. comment_file)

    local perform_comment = function()
        local util = require("gitforge.utility")
        local str = util.buffer_to_string(comment_buf)
        if #str == 0 then
            log.ephemeral_info("Aborted commenting with empty content")
            cleanup()
            return
        end
        generic_ui.perform_issue_update_cmd(provider,
            function(p) return p:cmd_comment(comment_file) end)
        cleanup()
    end
    generic_ui.setup_file_command_on_close(comment_buf, comment_file, true, perform_comment, cleanup)
end

---@param title_input string
---@param provider GHIssue
local change_title = function(title_input, provider)
    if #title_input == 0 then
        require("gitforge.log").notify_failure("An empty title is not allowed")
    end
    require("gitforge.generic_ui").perform_issue_update_cmd(provider,
        function(p) return p:cmd_title_change(title_input) end)
end

---@param provider GHIssue
function IssueActions.change_issue_title(provider)
    local log = require("gitforge.log")

    log.trace_msg("Change Title")
    local curr_buf_content = vim.api.nvim_buf_get_lines(provider.buf, 0, 1, false)
    local headline_markdown = curr_buf_content[1]
    -- strip markdown header 1
    local headline = vim.trim(headline_markdown:sub(3, -1))
    vim.ui.input({ prompt = "Enter New Title: ", default = headline },
        function(input)
            if input == nil then
                log.ephemeral_info("Aborted input")
                return
            end
            if input == headline then
                log.ephemeral_info("Title did not change")
                return
            end
            change_title(input, provider)
        end)
end

---Changes the labels of issue in @c buf from comma-separated list in @c previous_labels to
---comma separated list in @c new_labels
---@param previous Set previous labels
---@param new Set new labels
---@param provider GHIssue
local change_labels = function(previous, new, provider)
    local added, removed = previous:deltaTo(new)
    if added:empty() and removed:empty() then
        require("gitforge.log").ephemeral_info("Labels did not change.")
        return
    end

    require("gitforge.generic_ui").perform_issue_update_cmd(provider,
        function(p) return p:cmd_label_change(added, removed) end)
end

---@param provider GHIssue
function IssueActions.change_issue_labels(provider)
    local previous_labels = require("gitforge.generic_issue").get_labels_from_issue_buffer(provider.buf)
    if previous_labels == nil then
        return
    end
    vim.ui.input({ prompt = "Enter New Labels: ", default = previous_labels:toCSV() },
        function(input)
            if input == nil then
                require("gitforge.log").ephemeral_info("Aborted Issue Label Change")
                return
            end
            change_labels(previous_labels, Set:createFromCSVList(input), provider)
        end)
end

---Changes the assignees of issue in @c buf from comma-separated list in @c previous_labels to
---comma separated list in @c new_labels
---@param previous Set previous assignees
---@param new Set new assignees
---@param provider GHIssue
local change_assignees = function(previous, new, provider)
    local added, removed = previous:deltaTo(new)
    if added:empty() and removed:empty() then
        require("gitforge.log").ephemeral_info("Assignees did not change.")
        return
    end

    require("gitforge.generic_ui").perform_issue_update_cmd(provider,
        function(p) return p:cmd_assignee_change(added, removed) end)
end

---@param provider GHIssue
function IssueActions.change_issue_assignees(provider)
    local previous_assignees = require("gitforge.generic_issue").get_assignee_from_issue_buffer(provider.buf)
    if previous_assignees == nil then
        return
    end
    vim.ui.input({ prompt = "Enter New Assignee(s): ", default = previous_assignees:toCSV() },
        function(input)
            if input == nil then
                require("gitforge.log").ephemeral_info("Aborted Issue Assigning")
                return
            end
            change_assignees(previous_assignees, Set:createFromCSVList(input), provider)
        end)
end

---Called on an issue buffer. Parses out the current issue description, opens a new windows
---with the previous description and allows editing it. After save-closing the window, the
---description is updated on the issue.
---@param provider GHIssue
function IssueActions.change_issue_description(provider)
    local log = require("gitforge.log")
    local util = require("gitforge.utility")
    local generic_ui = require("gitforge.generic_ui")

    log.trace_msg("Edit Issue Description")
    local issue_number = provider.issue_number
    if issue_number == nil then
        log.notify_failure("Failed to retrieve issue number")
        return
    end

    local parsed_description = require("gitforge.generic_issue").get_description_from_issue_buffer(provider.buf)
    if parsed_description == nil then
        log.notify_failure("Failed to extract the description of the issue")
        return
    end
    log.trace_msg(parsed_description)

    local descr_edit_buf = vim.api.nvim_create_buf(false, false)
    if descr_edit_buf == 0 then
        log.notify_failure("Failed to create buffer to edit description")
        return
    end

    -- open new tmp buffer, like when commenting/creating
    -- sending / changing the issue body with body-file on save-close
    local tmp_desc_file = os.tmpname()
    local cleanup = function() os.remove(tmp_desc_file) end
    log.trace_msg("Tempfile for description: " .. tmp_desc_file)
    vim.api.nvim_buf_set_lines(descr_edit_buf, 0, -1, true, vim.split(parsed_description, '\n'))

    local edit_description = function()
        local new_desc = util.buffer_to_string(descr_edit_buf)
        if new_desc == parsed_description then
            log.ephemeral_info("No update to the description occured.")
        else
            generic_ui.perform_issue_update_cmd(provider,
                function(p) return p:cmd_description_change(tmp_desc_file) end)
        end
    end

    -- Jump directly into insert mode if the description is empty.
    generic_ui.setup_file_command_on_close(descr_edit_buf, tmp_desc_file, #parsed_description == 0, edit_description,
        cleanup)
end

---@param provider GHIssue
function IssueActions.change_issue_state(provider)
    local log = require("gitforge.log")

    log.trace_msg("Edit State - Open/Close")
    local issue_status = require("gitforge.generic_issue").get_status_from_issue_buffer(provider.buf)

    local list_of_next_stati = provider:next_possible_states(issue_status)
    if list_of_next_stati == nil then
        log.notify_failure("Failed to determine possible next issue states")
        return
    end
    vim.ui.select(list_of_next_stati, { prompt = "Select new issue state:", },
        function(choice)
            if issue_status == choice then
                log.ephemeral_info("Issue state did not change")
                return
            end
            log.trace_msg("From " .. issue_status .. " to " .. choice)

            require("gitforge.generic_ui").perform_issue_update_cmd(provider,
                function(p) return p:cmd_state_change(choice) end)
        end)
end

---@param provider GHIssue
function IssueActions.view_issue(provider)
    local log = require("gitforge.log")
    local generic_ui = require("gitforge.generic_ui")

    provider.buf = generic_ui.find_existing_issue_buffer(provider.issue_number)
    if provider.buf == 0 then
        generic_ui.refresh_issue(provider, function(p)
            generic_ui.create_issue_window(p.buf)
        end):wait()
    else
        log.trace_msg("Found issue in buffer - displaying old state and triggering update")
        generic_ui.create_issue_window(provider.buf)
        generic_ui.refresh_issue(provider)
    end
end

-- Creates a new issue by prompting for the title. The description is written in a new buffer.
---@param provider GHIssue
-- TODO: Provide a way to select labels directly on creation.
--       Right now it needs to be done by editing the new issue.
function IssueActions.create_issue(provider)
    local log = require("gitforge.log")
    local title
    local description_file
    local cleanup_description_file = function()
        log.trace_msg("Cleanup description file called")
        os.remove(description_file)
    end
    local show_issue_after_creation = function(handle)
        cleanup_description_file()
        if handle.code ~= 0 then
            log.notify_failure("Failed to create issue: \n" .. handle.stderr)
            return
        end
        local lines = vim.split(handle.stdout, "\n")
        local issue_link
        for index, value in ipairs(lines) do
            if index == 1 then
                issue_link = value
                break
            end
        end
        if issue_link == nil or #issue_link == 0 then
            log.notify_failure("Failed to retrieve issue link for new issue")
            log.trace_msg(vim.join(lines, "\n"))
            return
        end
        local p = provider:newFromLink(issue_link)
        if p == nil then
            return
        end
        IssueActions.view_issue(p)
    end
    local create_issue_call = function()
        local cmd = provider:cmd_create_issue(title, description_file)
        require("gitforge.utility").async_exec(cmd, show_issue_after_creation):wait()
    end
    local write_description_in_tmp_buffer = function()
        local buf = vim.api.nvim_create_buf(false, false)
        if buf == 0 then
            log.notify_failure("Failed to create buffer to write the description.")
            return
        end
        description_file = os.tmpname()

        require("gitforge.generic_ui").setup_file_command_on_close(buf, description_file, true, create_issue_call,
            cleanup_description_file)
    end
    local continuation_after_title_prompt = function(input)
        if input == nil or input == "" then
            return
        end
        title = input
        write_description_in_tmp_buffer()
    end
    vim.ui.input({ prompt = "Issue Title (esc or empty to abort): " }, continuation_after_title_prompt)
end

---@param issue_list_json table<Issue>
---@param provider GHIssue
local create_telescope_picker_for_issue_list = function(issue_list_json, provider)
    local ts = require("telescope")
    local pickers = require("telescope.pickers")
    local entry_display = require("telescope.pickers.entry_display")
    local finders = require("telescope.finders")
    local config = require("telescope.config").values
    local previewers = require("telescope.previewers")
    local make_entry = require("telescope.make_entry")
    local opts = {}

    local util = require("gitforge.utility")
    local generic_ui = require("gitforge.generic_ui")

    pickers.new(opts, {
        prompt_title = "Issue List",
        -- Using the 'async_job' predefined finder does not work, as the json output is not well formatted for it.
        finder = finders.new_table {
            results = issue_list_json,
            entry_maker = function(entry)
                local displayer = entry_display.create {
                    separator = " ",
                    -- hl_chars = { ["["] = "TelescopeBorder", ["]"] = "TelescopeBorder" },
                    items = {
                        { width = 7 },
                        { width = 60 },
                        { width = 10 },
                        { remaining = true },
                    },
                }

                local make_display = function(e)
                    return displayer {
                        { "#" .. e.number, "TelescopeResultsConstant" },
                        e.title,
                        { e.assignees,     "TelescopeResultsIdentifier" },
                        { e.labels,        "TelescopeResultsSpecialComment" },
                    }
                end
                local issue_labels = {}
                for _, label in ipairs(entry.labels) do
                    table.insert(issue_labels, label.name)
                end
                local assignees = {}
                if #entry.assignees == 0 then
                    table.insert(assignees, "unassigned")
                else
                    for _, v in ipairs(entry.assignees) do
                        table.insert(assignees, "@" .. v.login)
                    end
                end
                local labels_str = vim.fn.join(issue_labels, ",")
                local search_ordinal = entry.title .. ":" .. tostring(entry.number) .. ":" .. labels_str
                return make_entry.set_default_entry_mt({
                    ordinal = search_ordinal,
                    title = entry.title,
                    assignees = vim.fn.join(assignees, ","),
                    value = entry,
                    number = entry.number,
                    labels = labels_str,
                    display = make_display,
                }, {})
            end,
        },
        previewer = previewers.new_buffer_previewer({
            title = "Issue Preview",
            define_preview = function(self, entry)
                local buf = generic_ui.find_existing_issue_buffer(entry.number)

                -- The issue was not rendered before. Render it for the previewer, but also
                -- cache the content in a buffer.
                if buf == 0 then
                    local generic_issue = require("gitforge.generic_issue")
                    -- Render once into the previewer.
                    vim.api.nvim_set_option_value('filetype', 'markdown', { buf = self.state.bufnr })
                    generic_issue.render_issue_to_buffer(self.state.bufnr, entry.value)

                    -- Cache for snappy opening.
                    buf = generic_issue.render_issue_to_buffer(buf, entry.value)
                    local title_ui = generic_ui.issue_title_ui(entry.value)
                    vim.api.nvim_buf_set_name(buf, title_ui)
                    generic_issue.set_issue_buffer_options(provider:new(buf))
                else
                    -- Display the previously rendered content for the issue. Comments will be
                    -- present in this case.
                    vim.api.nvim_set_option_value('filetype', 'markdown', { buf = self.state.bufnr })
                    util.copy_buffer(buf, self.state.bufnr)
                end
            end
        }),
        sorter = config.generic_sorter(opts),
        attach_mappings = function(prompt_bufnr)
            local actions = require("telescope.actions")
            local state = require("telescope.actions.state")
            actions.select_default:replace(function()
                local selection = state.get_selected_entry()
                if selection == nil then
                    ts.utils.warn_no_selection "Missing Issue Selection"
                    return
                end
                actions.close(prompt_bufnr)
                local p = provider:newIssue(selection.value.number)
                IssueActions.view_issue(p)
            end)
            return true
        end,
    }):find()
end

---@param opts IssueListOpts
---@param provider GHIssue
function IssueActions.list_issues(opts, provider)
    local log = require("gitforge.log")
    local open_telescope_list = function(handle)
        if handle.code ~= 0 then
            log.ephemeral_info("Failed to retrieve issue list")
            return
        end
        vim.schedule(function()
            local data = provider:convert_cmd_result_to_issue(handle.stdout)
            create_telescope_picker_for_issue_list(data, provider)
        end)
    end
    require("gitforge.utility").async_exec(provider:cmd_list_issues(opts), open_telescope_list):wait()
end

function IssueActions.list_cached_issues(provider)
    local ts = require("telescope")
    local pickers = require("telescope.pickers")
    local config = require("telescope.config").values
    local finders = require("telescope.finders")
    local previewers = require("telescope.previewers")
    local actions = require("telescope.actions")
    local make_entry = require("telescope.make_entry")
    local opts = {}

    local util = require("gitforge.utility")
    local generic_ui = require("gitforge.generic_ui")

    local bufnrs = vim.tbl_filter(function(bufnr)
        local bufname = vim.api.nvim_buf_get_name(bufnr)
        return string.find(bufname, generic_ui.forge_issue_pattern, 1, true) ~= nil
    end, vim.api.nvim_list_bufs())

    if not next(bufnrs) then
        require("gitforge.log").ephemeral_info("No issues buffers found")
        return
    end

    local buffers = {}
    local default_selection_idx = 1
    for _, bufnr in ipairs(bufnrs) do
        local bufname = vim.api.nvim_buf_get_name(bufnr)
        local issue_number = require("gitforge.generic_issue").get_issue_id_from_buf(bufnr)
        local element = {
            bufnr = bufnr,
            bufname = bufname,
            issue_number = issue_number,
        }
        table.insert(buffers, element)
    end

    pickers
        .new({}, {
            prompt_title = "Issue Buffers",
            finder = finders.new_table {
                results = buffers,
                entry_maker = function(entry)
                    local idx_start = string.find(entry.bufname, generic_ui.forge_issue_pattern, 1, true)
                    if idx_start == nil then
                        require("gitforge.log").ephemeral_info("Failed to identify cache issue buffer")
                        return nil
                    end
                    local buf_txt = string.sub(entry.bufname, idx_start)
                    return make_entry.set_default_entry_mt({
                        ordinal = entry.issue_number .. ':' .. entry.bufname,
                        bufnr = entry.bufnr,
                        bufname = entry.bufname,
                        issue_number = entry.issue_number,
                        value = entry,
                        display = buf_txt,
                    }, {})
                end,
            },
            previewer = previewers.new_buffer_previewer({
                title = "Issue Preview",
                define_preview = function(self, entry)
                    vim.api.nvim_set_option_value('filetype', 'markdown', { buf = self.state.bufnr })
                    util.copy_buffer(entry.bufnr, self.state.bufnr)
                end,
            }),
            sorter = config.generic_sorter(opts),
            default_selection_index = default_selection_idx,
            attach_mappings = function(prompt_bufnr)
                local state = require("telescope.actions.state")
                actions.select_default:replace(function()
                    local selection = state.get_selected_entry()
                    if selection == nil then
                        ts.utils.warn_no_selection "Missing Issue Selection"
                        return
                    end
                    actions.close(prompt_bufnr)
                    local p = provider:newIssue(selection.value.issue_number)
                    IssueActions.view_issue(p)
                end)
                return true
            end,
        })
        :find()
end

return IssueActions
