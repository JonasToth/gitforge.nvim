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

---@param entry Label The label name and description to display.
---@return table Display Name and Description formatted well.
local label_picker_display = function(entry)
    local displayer = require("telescope.pickers.entry_display").create({
        separator = " ",
        items = {
            require("gitforge").opts.ui_options.label_picker, -- Label Name
            -- NOTE: The description is an optional field of Label.
            entry.description and { remaining = true },       -- Label Description
        },
    })
    return displayer({
        { entry.name },
        entry.description and { entry.description, "TelescopeResultsSpecialComment" },
    })
end

---@param provider LabelProvider
---@param continuationFunction function|nil What action to perform after the labels are retrieved.
local retrieve_labels = function(provider, continuationFunction)
    --TODO: Hardcoded 1000 may become a configuration parameter.
    local cmd = provider:cmd_list_labels(1000)
    require("gitforge.utility").async_exec(cmd, function(handle)
        local log = require("gitforge.log")
        if handle.code ~= 0 then
            log.notify_failure("Failed to retrieve labels")
            return
        end
        local labels_file = require("gitforge.utility").get_project_labels_file(provider)
        local success = labels_file:io_write(handle.stdout)
        if not success then
            log.notify_failure("Failed to cache labels in file " .. labels_file)
        else
            log.ephemeral_info("Updated chached labels in file " .. labels_file)
        end
        if continuationFunction ~= nil then
            continuationFunction(handle)
        end
    end)
end

---@param label_json string string must contain valid json.
---@param previous_labels Set set of labels already selected for the issue
---@param provider IssueProvider performs the change of labels after picking.
local labels_telescope_picker = function(label_json, previous_labels, provider)
    if label_json == nil then
        require("gitforge.log").notify_failure("Can not present labels picker, failed to retrieve labels.")
        return
    end
    local label_list = vim.fn.json_decode(label_json)
    local opts = require("telescope.themes").get_ivy({ layout_config = { prompt_position = "bottom" } })
    opts["multi_icon"] = ""

    require("gitforge.set")
    -- NOTE: Required to perform pre-selection.
    local startup_completed = false

    require("telescope.pickers").new(opts, {
        prompt_title = "Project Labels",
        finder = require("telescope.finders").new_table({
            results = label_list,
            entry_maker = function(entry)
                return require("telescope.make_entry").set_default_entry_mt({
                    ordinal = entry.name .. ":" .. entry.description,
                    display = label_picker_display,
                    value = entry,
                    name = entry.name,
                    description = entry.description,
                })
            end,
        }),
        sorter = require("telescope.config").values.generic_sorter(opts),
        attach_mappings = function(prompt_bufnr, map)
            local actions = require("telescope.actions")
            local perform_multiselect = function()
                local state = require("telescope.actions.state")
                local picker = state.get_current_picker(prompt_bufnr)

                -- Table of all selected value (mark with <tab>)
                local highlights = picker:get_multi_selection()

                -- "Enter" selected value
                local selected = state.get_selected_entry()
                actions.close(prompt_bufnr)

                require("gitforge.set")
                local selected_labels = Set:new()

                if selected ~= nil then
                    selected_labels:add(selected.value.name)
                end

                for _, hl in ipairs(highlights) do
                    selected_labels:add(hl.value.name)
                end
                change_labels(previous_labels, selected_labels, provider)
            end
            actions.select_default:replace(perform_multiselect)
            map({ "i", "n" }, "<ESC>", actions.select_default, { desc = "Commit label selection" })
            map({ "i", "n" }, "<CR>", actions.select_default, { desc = "Commit label selection" })
            map({ "i", "n" }, "<Tab>", actions.toggle_selection, { desc = "Toggle label selection" })
            map({ "i", "n" }, "<C-c>", actions.close, { desc = "Close without selection" })
            map({ "i", "n" }, "<C-j>", actions.nop, { desc = "No newline joining" })
            map({ "i", "n" }, "<C-n>", actions.move_selection_next, { desc = "Move down" })
            map({ "i", "n" }, "<Down>", actions.move_selection_next, { desc = "Move down" })
            map({ "i", "n" }, "<C-p>", actions.move_selection_previous, { desc = "Move up" })
            map({ "i", "n" }, "<Up>", actions.move_selection_previous, { desc = "Move up" })
            map({ "i", "n" }, "<C-u>", actions.results_scrolling_up, { desc = "Move page up" })
            map({ "i", "n" }, "<C-d>", actions.results_scrolling_down, { desc = "Move page down" })
            return false
        end,
        on_complete = {
            function(picker)
                if startup_completed then
                    return
                end
                local i = 1
                for entry in picker.manager:iter() do
                    if previous_labels:contains(entry.value.name) then
                        picker:add_selection(picker:get_row(i))
                    end
                    i = i + 1
                end
                startup_completed = true
            end,
        }
    }):find()
end

---Creates a telescope picker to select the labels of the issue.
---@param provider IssueProvider
function IssueActions.pick_issue_labels(provider)
    local log = require("gitforge.log")
    local previous_labels = require("gitforge.generic_issue").get_labels_from_issue_buffer(provider.buf)
    if previous_labels == nil then
        log.notify_failure("Failed to determine labels from issue buffer " .. provider.buf)
        return
    end

    local labelProvider = provider:new_label_provider_from_self()
    local labels_file = require("gitforge.utility").get_project_labels_file(labelProvider)
    local label_json = labels_file:io_read()
    if label_json == nil then
        retrieve_labels(labelProvider, function(handle)
            vim.schedule(function()
                labels_telescope_picker(handle.stdout, previous_labels, provider)
            end)
        end)
    else
        vim.schedule(function() retrieve_labels(labelProvider) end)
        labels_telescope_picker(label_json, previous_labels, provider)
    end
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

---Returns a function that creates a single entry for an issue in a telescope picker.
---@param entry table containing 'number', 'title', 'assignees', 'labels'
---@see issue_entry_maker
---@return function LineDisplay Function that creates the format for a single telescope entry line.
local issue_picker_line_display = function(entry)
    local displayer = require("telescope.pickers.entry_display").create({
        separator = " ",
        items = {
            entry.project and { width = 20 } or nil,
            { width = 7 },                                                  -- Issue number
            { width = require("gitforge").opts.list_max_title_length + 5 }, -- Issue title
            { width = 10 },                                                 -- Assignees
            { remaining = true },                                           -- Labels
        },
    })
    return displayer({
        -- Return the last 20 characters of the project.
        entry.project and { string.sub(entry.project, -20), "TelescopeResultsSpecialComment" } or nil,
        { "#" .. entry.number, "TelescopeResultsConstant" },
        entry.title,
        { entry.assignees,     "TelescopeResultsIdentifier" },
        { entry.labels,        "TelescopeResultsSpecialComment" },
    })
end

---Creates a single entry for an issue for telescope picker.
---@param entry Issue JSON description of the issue. Can be extended for pinned issues or issues in buffers.
---@return table PickerEntry Telescope entry with custom search ordinal, display line and issue content.
local issue_entry_maker = function(entry)
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
    return require("telescope.make_entry").set_default_entry_mt({
        ordinal = search_ordinal,
        title = entry.title,
        assignees = vim.fn.join(assignees, ","),
        value = entry,
        number = entry.number,
        project = entry.project,
        labels = labels_str,
        display = issue_picker_line_display,
        -- Present when picking from existing buffers.
        bufnr = entry.bufnr or nil,
        -- Present when picking from stored files (e.g. for pinned issues).
        filename = entry.filename or nil,
    }, {})
end

--- Performs issues viewing after an issue is selected in a telescope picker.
---@param prompt_bufnr integer ID of telescope buffer.
---@param provider IssueProvider|function Backend for the issue actions. Can be a function
---                                       that takes the selection and returns the provider.
---@return boolean true true in all cases.
local issue_pick_mapping = function(prompt_bufnr, provider)
    local ts = require("telescope")
    local actions = require("telescope.actions")
    local state = require("telescope.actions.state")
    actions.select_default:replace(function()
        local selection = state.get_selected_entry()
        if selection == nil then
            ts.utils.warn_no_selection "Missing Issue Selection"
            return
        end
        actions.close(prompt_bufnr)
        local prov
        if type(provider) == "function" then
            prov = provider(selection)
        else
            prov = provider
        end
        if prov == nil then
            require("gitforge.log").notify_failure("Can not determine the issue provider")
            return
        end
        local p = prov:newIssue(selection.value.number, selection.value.project)
        IssueActions.view_issue(p)
    end)
    -- 'return true' means "use default mappings"
    return true
end

---@param issue_list_json table<Issue>
---@param provider IssueProvider
local create_telescope_picker_for_issue_list = function(issue_list_json, provider)
    local opts = {}

    require("telescope.pickers").new(opts, {
        prompt_title = "Issue List",
        -- Using the 'async_job' predefined finder does not work, as the json output is not well formatted for it.
        finder = require("telescope.finders").new_table({
            results = issue_list_json,
            entry_maker = issue_entry_maker,
        }),
        previewer = require("telescope.previewers").new_buffer_previewer({
            title = "Issue Preview",
            define_preview = function(self, entry)
                require("gitforge.log").trace_msg("Searching for existing rendered buffers")
                local generic_ui = require("gitforge.generic_ui")
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
                    require("gitforge.utility").copy_buffer(buf, self.state.bufnr)
                end
            end
        }),
        sorter = require("telescope.config").values.generic_sorter(opts),
        attach_mappings = function(prompt_bufnr) return issue_pick_mapping(prompt_bufnr, provider) end,
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

---Parses the content of a buffer to reconstruct an issue object.
---@param bufnr integer Buffer-ID where an issue was rendered to previously.
---@return Issue|nil reconstructed_issue Proper issue object or nil on failure.
local issue_from_buffer = function(bufnr)
    local gi = require("gitforge.generic_issue")
    local util = require("gitforge.utility")
    local bufname = vim.api.nvim_buf_get_name(bufnr)
    local project, issue_number = gi.get_issue_proj_and_id_from_buf(bufnr)
    local title = gi.get_title_from_issue_buffer(bufnr)
    if title == nil then
        require("gitforge.log").notify_failure("Expected title not found in issue buffer " .. bufnr)
        return nil
    end
    local labels = util.labels_from_set(gi.get_labels_from_issue_buffer(bufnr) or Set:new())
    local assignees = util.authors_from_set(gi.get_assignee_from_issue_buffer(bufnr) or Set:new())

    local separator_idx = string.find(bufname, " - ", 1, true)
    if separator_idx == nil then
        require("gitforge.log").notify_failure("Expected title separator not found in issue buffer name")
        return nil
    end
    return {
        bufnr = bufnr,
        bufname = bufname,
        title = title,
        assignees = assignees,
        value = { number = issue_number, project = project },
        number = issue_number,
        project = project,
        labels = labels,
    }
end

---@param provider IssueProvider|nil
function IssueActions.list_opened_issues(provider)
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
    for _, bufnr in ipairs(bufnrs) do
        local reconstructed_issue = issue_from_buffer(bufnr)
        if reconstructed_issue ~= nil then
            table.insert(buffers, reconstructed_issue)
        end
    end

    local opts = {}
    local prov = provider or require("gitforge.issue_provider").get_from_cwd_or_default()
    require("telescope.pickers").new(opts, {
        prompt_title = "Issue Buffers",
        finder = require("telescope.finders").new_table({
            results = buffers,
            entry_maker = issue_entry_maker,
        }),
        previewer = require("telescope.previewers").new_buffer_previewer({
            title = "Issue Preview",
            define_preview = function(self, entry)
                vim.api.nvim_set_option_value('filetype', 'markdown', { buf = self.state.bufnr })
                require("gitforge.utility").copy_buffer(entry.bufnr, self.state.bufnr)
            end,
        }),
        sorter = require("telescope.config").values.generic_sorter(opts),
        default_selection_index = 1,
        attach_mappings = function(prompt_bufnr) return issue_pick_mapping(prompt_bufnr, prov) end,
    }):find()
end

---@param plugin_data string
---@param name string
---@return table|nil IssueInfo
local make_pinned_file = function(plugin_data, name, project, id)
    local issue_path = vim.fs.joinpath(plugin_data, name)
    local util = require("gitforge.utility")

    local file_content = util.read_file_to_string(issue_path)
    if file_content == nil then
        return nil
    end
    local headline = util.get_markdown_headline_from_file(file_content)
    local labels, assignees = util.get_labels_and_assignees_from_file(file_content)
    local issue_number = string.match(id, "issue_(.*)")
    if headline ~= nil and issue_number ~= nil then
        return {
            project = project,
            number = issue_number,
            title = headline,
            labels = labels or {},
            assignees = assignees or {},
            filename = issue_path,
        }
    end
end

---@return string|nil project
---@return string|nil id
---@return string|nil file_extension
local project_id_from_path = function(name)
    local elements = vim.split(name, "/", { plain = true })
    if #elements > 2 then
        local project = elements[1]
        for i = 2, #elements - 1 do
            project = project .. "/" .. elements[i]
        end
        local file_parts = vim.split(elements[#elements], "%.")
        if #file_parts == 2 then
            return project, file_parts[1], file_parts[2]
        else
            return nil, nil, nil
        end
    else
        return nil, nil, nil
    end
end

function IssueActions.list_pinned_issues()
    local util = require("gitforge.utility")
    local log = require("gitforge.log")

    local plugin_data = util.get_plugin_data_dir()
    if not util.dir_exists(plugin_data) then
        log.ephemeral_info("Plugin data directory " .. plugin_data .. " does not exist, no pinned issues.")
        return
    end
    --- Array of all issues to show.
    local issues = {}
    --- Maps a project to its provider.
    local providers = {}

    for name, type in vim.fs.dir(plugin_data, { depth = 4 }) do
        if type == "file" then
            local project, id, file_extension = project_id_from_path(name)
            if project and id and file_extension then
                if id == "issue_provider" then
                    providers[project] = file_extension
                elseif string.match(id, "issue_.*") then
                    local f = make_pinned_file(plugin_data, name, project, id)
                    if f then
                        table.insert(issues, f)
                    end
                else
                    -- Skip
                end
            end
        end
    end

    local opts = {}
    require("telescope.pickers").new(opts, {
        prompt_title = "Pinned Issues",
        finder = require("telescope.finders").new_table {
            results = issues,
            entry_maker = issue_entry_maker,
        },
        previewer = require("telescope.previewers").vim_buffer_cat.new(opts),
        sorter = require("telescope.config").values.generic_sorter(opts),
        attach_mappings = function(prompt_bufnr)
            return issue_pick_mapping(prompt_bufnr, function(selection)
                local provider_string = providers[selection.value.project]
                if provider_string == nil then return nil end
                return require("gitforge." .. provider_string .. ".issue")
            end)
        end,
    }):find()
end

return IssueActions
