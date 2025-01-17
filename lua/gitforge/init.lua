local M = {}
local a = vim.api

---@param opts table
function M.setup(opts)
    M.opts = opts or {}
    if M.opts.timeout == nil then
        M.opts.timeout = 5000
    end
    -- a.nvim_create_user_command("GH", M.handle_command, {})
    local provider = require("gitforge.gh.issue")
    vim.keymap.set("n", "<leader>ql", function()
        M.list_issues({
            -- project = "llvm/llvm-project",
            -- filter_labels = "clang-tidy",
            limit = 50,
            -- assignee = "@me",
        }, provider)
    end)
    vim.keymap.set("n", "<leader>qi", function()
        M.view_issue({
            -- project = "llvm/llvm-project",
            -- project = "JonasToth/dotfiles"
            -- issue_nbr = "56777",
            -- issue_nbr = "102983",
        }, provider:newIssue("2"))
    end)

    vim.keymap.set("n", "<leader>qc", M.cached_issues_picker)
    vim.keymap.set("n", "<leader>qn", function() M.create_issue(M.opts, provider) end)
end

---@param opts table
function M.handle_command(opts)
    local subcommands = {}
    for s in opts.args:gmatch("[^ ]+") do
        table.insert(subcommands, s)
    end
    for _, command in ipairs(subcommands) do
        if command == "list-labels" then
            M.get_labels()
        end
    end
end

---Changes the buffer options for @c buf to be unchangeable by normal operations.
---Additionally, set buffer key mappings for user interface.
---@param provider GHIssue Buffer ID to work on.
function M.set_issue_buffer_options(provider)
    a.nvim_set_option_value('readonly', true, { buf = provider.buf })
    a.nvim_set_option_value('buftype', 'nowrite', { buf = provider.buf })
    a.nvim_set_option_value('filetype', 'markdown', { buf = provider.buf })
    a.nvim_set_option_value('syntax', 'markdown', { buf = provider.buf })

    local key_opts_from_desc = function(description)
        return { buffer = provider.buf, nowait = true, desc = description, silent = true }
    end
    vim.keymap.set("n", "<localleader>q", ":close<CR>", key_opts_from_desc("Close Issue"))

    local log = require("gitforge.log")
    vim.keymap.set("n", "<localleader>c", function()
            vim.schedule(function()
                local issue_number = require("gitforge.generic_issue").get_issue_id_from_buf(provider.buf)
                if issue_number == nil then
                    log.notify_failure("Failed to determine issue id to comment on in buffer " .. provider.buf)
                    return
                end
                M.comment_on_issue(provider)
            end)
        end,
        key_opts_from_desc("Comment on Issue"))

    vim.keymap.set("n", "<localleader>u", function()
            require("gitforge.generic_ui").refresh_issue(provider)
            log.notify_change("Updated the issue buffer")
        end,
        key_opts_from_desc("Update Issue"))

    vim.keymap.set("n", "<localleader>t", function()
            vim.schedule(function()
                log.trace_msg("Change Title")
                local curr_buf_content = a.nvim_buf_get_lines(provider.buf, 0, 1, false)
                local headline_markdown = curr_buf_content[1]
                -- strip markdown header 1
                local headline = vim.trim(headline_markdown:sub(3, -1))
                vim.ui.input({ prompt = "Enter New Title: ", default = headline },
                    function(input)
                        if input == nil then
                            log.ephemeral_info("Aborted input")
                            return
                        end
                        M.change_title(input, provider)
                    end)
            end)
        end,
        key_opts_from_desc("Change Title"))

    vim.keymap.set("n", "<localleader>l", function()
            vim.schedule(function()
                local previous_labels = require("gitforge.generic_issue").get_labels_from_issue_buffer(provider.buf)
                if previous_labels == nil then
                    return
                end
                vim.ui.input({ prompt = "Enter New Labels: ", default = previous_labels:toCSV() },
                    function(input)
                        if input == nil then
                            log.ephemeral_info("Aborted Issue Label Change")
                            return
                        end
                        M.change_labels(previous_labels, Set:createFromCSVList(input), provider)
                    end)
            end)
        end,
        key_opts_from_desc("Change Labels"))

    vim.keymap.set("n", "<localleader>a", function()
            vim.schedule(function()
                local previous_assignees = require("gitforge.generic_issue").get_assignee_from_issue_buffer(provider.buf)
                if previous_assignees == nil then
                    return
                end
                vim.ui.input({ prompt = "Enter New Assignee(s): ", default = previous_assignees:toCSV() },
                    function(input)
                        if input == nil then
                            log.ephemeral_info("Aborted Issue Assigning")
                            return
                        end
                        M.change_assignees(previous_assignees, Set:createFromCSVList(input), provider)
                    end)
            end)
        end,
        key_opts_from_desc("Assign Issue"))

    vim.keymap.set("n", "<localleader>e", function()
            M.change_issue_description(M.opts, provider)
        end,
        key_opts_from_desc("Edit Issue Body"))

    vim.keymap.set("n", "<localleader>s", function()
            M.change_issue_state(M.opts, provider)
        end,
        key_opts_from_desc("Edit State - Reopen/Close"))
end

-- Creates a new issue by prompting for the title. The description is written in a new buffer.
---@param opts table
---@param provider GHIssue
-- TODO: Provide a way to select labels directly on creation.
--       Right now it needs to be done by editing the new issue.
function M.create_issue(opts, provider)
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
        M.view_issue(opts, p)
    end
    local create_issue_call = function()
        local cmd = provider:cmd_create_issue(title, description_file)
        log.executed_command(cmd)
        vim.system(cmd, { text = true, timeout = opts.timeout }, show_issue_after_creation)
    end
    local write_description_in_tmp_buffer = function()
        local buf = a.nvim_create_buf(false, false)
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

---@param provider GHIssue
function M.comment_on_issue(provider)
    local log = require("gitforge.log")
    local generic_ui = require("gitforge.generic_ui")

    local comment_buf = a.nvim_create_buf(false, false)
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

---Called on an issue buffer. Parses out the current issue description, opens a new windows
---with the previous description and allows editing it. After save-closing the window, the
---description is updated on the issue.
---@param opts table Project options
---@param provider GHIssue
function M.change_issue_description(opts, provider)
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

    local descr_edit_buf = a.nvim_create_buf(false, false)
    if descr_edit_buf == 0 then
        log.notify_failure("Failed to create buffer to edit description")
        return
    end

    -- open new tmp buffer, like when commenting/creating
    -- sending / changing the issue body with body-file on save-close
    local tmp_desc_file = os.tmpname()
    local cleanup = function() os.remove(tmp_desc_file) end
    log.trace_msg("Tempfile for description: " .. tmp_desc_file)
    a.nvim_buf_set_lines(descr_edit_buf, 0, -1, true, vim.split(parsed_description, '\n'))

    local edit_description = function()
        local new_desc = util.buffer_to_string(descr_edit_buf)
        if new_desc == parsed_description then
            log.ephemeral_info("No update to the description occured.")
        else
            generic_ui.perform_issue_update_cmd(provider,
                function(p) return p:cmd_description_change(tmp_desc_file) end)
        end
    end

    generic_ui.setup_file_command_on_close(descr_edit_buf, tmp_desc_file, false, edit_description, cleanup)
end

function M.cached_issues_picker(provider)
    local ts = require("telescope")
    local pickers = require("telescope.pickers")
    local config = require("telescope.config").values
    local finders = require("telescope.finders")
    local previewers = require("telescope.previewers")
    local actions = require("telescope.actions")
    local make_entry = require("telescope.make_entry")
    local opts = {}

    local util = require("gitforge.utility")

    local bufnrs = vim.tbl_filter(function(bufnr)
        local bufname = a.nvim_buf_get_name(bufnr)
        return string.find(bufname, "[Issue]", 1, true) ~= nil
    end, vim.api.nvim_list_bufs())

    if not next(bufnrs) then
        require("gitforge.log").ephemeral_info("No issues buffers found")
        return
    end

    local buffers = {}
    local default_selection_idx = 1
    for _, bufnr in ipairs(bufnrs) do
        local bufname = a.nvim_buf_get_name(bufnr)
        local issue_number = require("gitforge.generic_issue").get_issue_id_from_buf(bufnr)
        local element = {
            bufnr = bufnr,
            bufname = bufname,
            issue_number = issue_number,
        }
        table.insert(buffers, element)
    end

    print(buffers)
    pickers
        .new({}, {
            prompt_title = "Issue Buffers",
            finder = finders.new_table {
                results = buffers,
                entry_maker = function(entry)
                    return make_entry.set_default_entry_mt({
                        ordinal = entry.issue_number .. ':' .. entry.bufname,
                        bufnr = entry.bufnr,
                        bufname = entry.bufname,
                        issue_number = entry.issue_number,
                        value = entry,
                        display = entry.issue_number .. ' || ' .. entry.bufname,
                    }, {})
                end,
            },
            previewer = previewers.new_buffer_previewer({
                title = "Issue Preview",
                define_preview = function(self, entry)
                    a.nvim_set_option_value('filetype', 'markdown', { buf = self.state.bufnr })
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
                    local p = provider:newIssue(selection.value.issue_number)
                    M.view_issue({ project = opts.project, }, p)
                end)
                return true
            end,
        })
        :find()
end

---@param issue_list_json table
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
                    a.nvim_set_option_value('filetype', 'markdown', { buf = self.state.bufnr })
                    generic_issue.render_issue_to_buffer(self.state.bufnr, entry.value)

                    -- Cache for snappy opening.
                    buf = generic_issue.render_issue_to_buffer(buf, entry.value)
                    local title_ui = generic_ui.issue_title_ui(entry.value)
                    a.nvim_buf_set_name(buf, title_ui)
                    M.set_issue_buffer_options(provider:new(buf))
                else
                    -- Display the previously rendered content for the issue. Comments will be
                    -- present in this case.
                    a.nvim_set_option_value('filetype', 'markdown', { buf = self.state.bufnr })
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
                local p = provider:newIssue(selection.value.number)
                M.view_issue({ project = opts.project, }, p)
            end)
            return true
        end,
    }):find()
end

---@param opts table
---@param provider GHIssue
function M.list_issues(opts, provider)
    local log = require("gitforge.log")
    local open_telescope_list = function(handle)
        if handle.code ~= 0 then
            log.ephemeral_info("Failed to retrieve issue list")
            return
        end
        local data = provider:convert_cmd_result_to_issue(handle.stdout)
        vim.schedule(function() create_telescope_picker_for_issue_list(data, provider) end)
    end
    local gh_call = provider:cmd_list_issues(opts)
    log.executed_command(gh_call)
    local call_handle = vim.system(gh_call, { text = true, timeout = M.opts.timeout }, open_telescope_list)
    call_handle:wait()
end

---@param opts table
---@param provider GHIssue
function M.view_issue(opts, provider)
    local log = require("gitforge.log")
    local generic_ui = require("gitforge.generic_ui")

    provider.buf = generic_ui.find_existing_issue_buffer(provider.issue_number)
    if provider.buf == 0 then
        generic_ui.refresh_issue(provider, function(p, issue)
            local title_ui = generic_ui.issue_title_ui(issue)
            generic_ui.create_issue_window(p.buf, title_ui)
        end):wait()
    else
        log.trace_msg("Found issue in buffer - displaying old state and triggering update")
        local title_ui = a.nvim_buf_get_name(provider.buf)
        generic_ui.create_issue_window(provider.buf, title_ui)
        generic_ui.refresh_issue(provider)
    end
end

---@param title_input string
---@param provider GHIssue
function M.change_title(title_input, provider)
    if #title_input == 0 then
        require("gitforge.log").notify_failure("An empty title is not allowed")
    end
    require("gitforge.generic_ui").perform_issue_update_cmd(provider,
        function(p) return p:cmd_title_change(title_input) end)
end

---Changes the labels of issue in @c buf from comma-separated list in @c previous_labels to
---comma separated list in @c new_labels
---@param previous Set previous labels
---@param new Set new labels
---@param provider GHIssue
function M.change_labels(previous, new, provider)
    local added, removed = previous:deltaTo(new)
    if added:empty() and removed:empty() then
        require("gitforge.log").ephemeral_info("Labels did not change.")
        return
    end

    require("gitforge.generic_ui").perform_issue_update_cmd(provider,
        function(p) return p:cmd_label_change(added, removed) end)
end

---Changes the assignees of issue in @c buf from comma-separated list in @c previous_labels to
---comma separated list in @c new_labels
---@param previous Set previous assignees
---@param new Set new assignees
---@param provider GHIssue
function M.change_assignees(previous, new, provider)
    local added, removed = previous:deltaTo(new)
    if added:empty() and removed:empty() then
        require("gitforge.log").ephemeral_info("Assignees did not change.")
        return
    end

    require("gitforge.generic_ui").perform_issue_update_cmd(provider,
        function(p) return p:cmd_assignee_change(added, removed) end)
end

---@param provider GHIssue
function M.change_issue_state(opts, provider)
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

return M
