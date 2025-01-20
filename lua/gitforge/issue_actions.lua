local IssueActions = {}

---@class IssueListOpts
---@field state string? List issues only with specific state (e.g. open/closed)
---@field project string?
---@field limit integer? Limit the number of issues
---@field labels string? CSV-separated list of labels
---@field assignee string? CSV-separated list of assignees

---@param provider IssueProvider
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
---@param provider IssueProvider
local change_title = function(title_input, provider)
    if #title_input == 0 then
        require("gitforge.log").notify_failure("An empty title is not allowed")
    end
    require("gitforge.generic_ui").perform_issue_update_cmd(provider,
        function(p) return p:cmd_title_change(title_input) end)
end

---@param provider IssueProvider
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
---@param provider IssueProvider
local change_labels = function(previous, new, provider)
    local added, removed = previous:deltaTo(new)
    if added:empty() and removed:empty() then
        require("gitforge.log").ephemeral_info("Labels did not change.")
        return
    end
    require("gitforge.generic_ui").perform_issue_update_cmd(provider,
        function(p) return p:cmd_label_change(added, removed) end)
end

---@param provider IssueProvider
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
---@param provider IssueProvider
local change_assignees = function(previous, new, provider)
    local added, removed = previous:deltaTo(new)
    if added:empty() and removed:empty() then
        require("gitforge.log").ephemeral_info("Assignees did not change.")
        return
    end

    require("gitforge.generic_ui").perform_issue_update_cmd(provider,
        function(p) return p:cmd_assignee_change(new, added, removed) end)
end

---@param provider IssueProvider
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
---@param provider IssueProvider
function IssueActions.change_issue_description(provider)
    local log = require("gitforge.log")
    local util = require("gitforge.utility")
    local generic_ui = require("gitforge.generic_ui")

    log.trace_msg("Edit Issue Description")
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

---@param provider IssueProvider
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

---@param provider IssueProvider
function IssueActions.toggle_pin_issue(provider)
    local util = require("gitforge.utility")
    local log = require("gitforge.log")

    local issue_file = util.get_issue_data_file(provider)
    if issue_file:exists(false) then
        log.ephemeral_info("Removing " .. issue_file)
        issue_file:unlink()
    else
        log.ephemeral_info("Writing " .. issue_file)
        vim.cmd("write! " .. issue_file)
    end
end

---@param provider IssueProvider
function IssueActions.view_issue_web(provider)
    local log = require("gitforge.log")

    log.notify_change("Opening browser for issue " .. provider.issue_number)
    local webview_completer = function(handle)
        if handle.code ~= 0 then
            log.notify_failure("Failed to open issue!\n" .. handle.stderr)
            return
        end
    end
    local handle = require("gitforge.utility").async_exec(provider:cmd_view_web(), webview_completer)
    if handle then handle:wait() end
end

---@param provider IssueProvider|nil
function IssueActions.view_issue(provider)
    local log = require("gitforge.log")
    local generic_ui = require("gitforge.generic_ui")
    local prov = provider or require("gitforge.issue_provider").get_from_cwd_or_default()

    prov.buf = generic_ui.find_existing_issue_buffer(prov.project, prov.issue_number)
    if prov.buf == 0 then
        local handle = generic_ui.refresh_issue(prov, function(p)
            generic_ui.create_issue_window(p.buf)
        end)
        if handle then handle:wait() end
    else
        log.trace_msg("Found issue in buffer - displaying old state and triggering update")
        generic_ui.create_issue_window(prov.buf)
        generic_ui.refresh_issue(prov)
    end
end

-- Creates a new issue by prompting for the title. The description is written in a new buffer.
---@param provider IssueProvider|nil
-- TODO: Provide a way to select labels directly on creation.
--       Right now it needs to be done by editing the new issue.
function IssueActions.create_issue(provider)
    local log = require("gitforge.log")
    local prov = provider or require("gitforge.issue_provider").get_from_cwd_or_default()

    local title
    local description_file
    local cleanup_description_file = function()
        log.trace_msg("Cleanup description file called")
        os.remove(description_file)
    end
    local show_issue_after_creation = function(handle)
        cleanup_description_file()
        if handle.code ~= 0 then
            log.notify_failure("Failed to create issue: \n" .. handle.stderr .. "\nReturn Code: " .. handle.code)
            return
        end
        local p = prov:handle_create_issue_output_to_view_issue(handle.stdout)
        if p == nil then
            log.notify_change("Created the issue but failed to view it directly:\n" ..
                handle.stdout .. "\n" .. handle.stderr)
            return
        end
        vim.schedule(function() IssueActions.view_issue(p) end)
    end
    local create_issue_call = function()
        local cmd = prov:cmd_create_issue(title, description_file)
        local handle = require("gitforge.utility").async_exec(cmd, show_issue_after_creation)
        if handle then handle:wait() end
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
---@param provider IssueProvider
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
                        { width = 7 },                                                  -- Issue number
                        { width = require("gitforge").opts.list_max_title_length + 5 }, -- Issue title
                        { width = 10 },                                                 -- Assignees
                        { remaining = true },                                           -- Labels
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
                local assignee_str = vim.fn.join(assignees, ",")
                local search_ordinal = entry.title ..
                    ":" .. tostring(entry.number) .. ":" .. labels_str .. ":" .. assignee_str
                return make_entry.set_default_entry_mt({
                    ordinal = search_ordinal,
                    title = entry.title,
                    assignees = vim.fn.join(assignees, ","),
                    value = entry,
                    number = entry.number,
                    project = entry.project,
                    labels = labels_str,
                    display = make_display,
                }, {})
            end,
        },
        previewer = previewers.new_buffer_previewer({
            title = "Issue Preview",
            define_preview = function(self, entry)
                require("gitforge.log").trace_msg("Searching for existing rendered buffers")
                local buf = generic_ui.find_existing_issue_buffer(entry.project, entry.number)

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
                    generic_ui.set_buf_title(buf, title_ui)
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
                local p = provider:newIssue(selection.value.number, selection.value.project)
                IssueActions.view_issue(p)
            end)
            return true
        end,
    }):find()
end

---@param opts IssueListOpts
---@param provider IssueProvider|nil
function IssueActions.list_issues(opts, provider)
    local log = require("gitforge.log")
    local prov = provider or require("gitforge.issue_provider").get_from_cwd_or_default()

    local open_telescope_list = function(handle)
        if handle.code ~= 0 then
            log.notify_failure("Failed to retrieve issue list:" .. handle.stdout .. "\n" .. handle.stderr)
            return
        end
        vim.schedule(function()
            local data = prov:convert_cmd_result_to_issue_list(handle.stdout)
            create_telescope_picker_for_issue_list(data, prov)
        end)
    end
    local handle = require("gitforge.utility").async_exec(prov:cmd_list_issues(opts), open_telescope_list)
    if handle then handle:wait() end
end

---@param provider IssueProvider|nil
function IssueActions.list_opened_issues(provider)
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
        local project, issue_number = require("gitforge.generic_issue").get_issue_proj_and_id_from_buf(bufnr)
        local element = {
            bufnr = bufnr,
            bufname = bufname,
            issue_number = issue_number,
            project = project,
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
                    local prov = provider or require("gitforge.issue_provider").get_from_cwd_or_default()
                    local p = prov:newIssue(selection.value.issue_number, selection.value.project)
                    IssueActions.view_issue(p)
                end)
                return true
            end,
        })
        :find()
end

function IssueActions.list_pinned_issues()
    local util = require("gitforge.utility")
    local log = require("gitforge.log")

    -- FIXME: This function is the biggest mess of this code-base right now.
    --        - Extract good functions for utility and so on
    --        - get common functionality for telescope pickers
    --        - show the issue content in previewer, I failed to do so...

    local plugin_data = util.get_plugin_data_dir()
    if not util.dir_exists(plugin_data) then
        log.ephemeral_info("Plugin data directory " .. plugin_data .. " does not exist, no pinned issues.")
        return
    end
    local issues = {}
    --- Maps a project to its provider.
    local providers = {}

    local get_headline_from_file = function(path)
        local s = util.read_file_to_string(path)
        if s == nil then
            return nil
        end
        local idx_first_linebreak = string.find(s, "\n", 1, true)
        if idx_first_linebreak == nil or idx_first_linebreak <= 3 then
            return nil
        end
        return vim.trim(string.sub(s, 3, idx_first_linebreak))
    end

    for name, type in vim.fs.dir(plugin_data, { depth = 4 }) do
        if type == "file" then
            local el = vim.split(name, "/", { plain = true })
            if #el == 4 then
                local project = vim.fn.join({ el[1], el[2], el[3] }, "/")
                local file_parts = vim.split(el[4], "%.")
                if #file_parts == 2 then
                    local id = file_parts[1]
                    if id == "issue_provider" then
                        providers[project] = file_parts[2]
                    else
                        local issue_path = vim.fs.joinpath(plugin_data, name)
                        local headline = get_headline_from_file(issue_path)
                        if headline ~= nil then
                            table.insert(issues, {
                                project = project,
                                issue_number = id,
                                filename = issue_path,
                                headline = headline,
                            })
                        end
                    end
                end
            end
        end
    end


    local ts = require("telescope")
    local pickers = require("telescope.pickers")
    local config = require("telescope.config").values
    local finders = require("telescope.finders")
    local previewers = require("telescope.previewers")
    local actions = require("telescope.actions")
    local make_entry = require("telescope.make_entry")
    pickers
        .new({}, {
            prompt_title = "Issue Buffers",
            finder = finders.new_table {
                results = issues,
                entry_maker = function(entry)
                    -- local idx_start = string.find(entry.bufname, generic_ui.forge_issue_pattern, 1, true)
                    -- if idx_start == nil then
                    --     log.ephemeral_info("Failed to identify cache issue buffer")
                    --     return nil
                    -- end
                    -- local buf_txt = string.sub(entry.bufname, idx_start)
                    print(vim.inspect(entry))
                    return make_entry.set_default_entry_mt({
                        ordinal = entry.project .. ":" .. entry.issue_number .. ":" .. entry.headline,
                        filename = entry.filename,
                        issue_number = entry.issue_number,
                        value = entry,
                        display = entry.project .. " #" .. entry.issue_number .. " " .. entry.headline,
                    }, {})
                end,
            },
            -- previewer = require('telescope.config').values.cat_previewer,
            -- previewer = previewers.cat({
            --     title = "Pinned Issues Preview",
            -- }),
            sorter = config.generic_sorter({}),
            attach_mappings = function(prompt_bufnr)
                local state = require("telescope.actions.state")
                actions.select_default:replace(function()
                    local selection = state.get_selected_entry()
                    if selection == nil then
                        ts.utils.warn_no_selection("Missing Issue Selection")
                        return
                    end
                    actions.close(prompt_bufnr)
                    local provider_name = providers[selection.value.project]
                    if provider_name == nil then
                        log.notify_failure("Can not determine the issue provider to use")
                        return
                    end
                    local prov = require("gitforge." .. provider_name .. ".issue")
                    local p = prov:newIssue(selection.value.issue_number, selection.value.project)
                    IssueActions.view_issue(p)
                end)
                return true
            end,
        })
        :find()
end

return IssueActions
