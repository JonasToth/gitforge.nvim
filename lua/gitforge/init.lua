local M = {}
local a = vim.api
local g_description_headline_md = '## Description'
local g_comments_headline_md = '## Comments'

function M.setup(opts)
    M.opts = opts or {}
    if M.opts.timeout == nil then
        M.opts.timeout = 2000
    end
    -- a.nvim_create_user_command("GH", M.handle_command, {})

    vim.keymap.set("n", "<leader>ql", function()
        M.list_issues({
            -- project = "llvm/llvm-project",
            -- filter_labels = "clang-tidy",
            limit = 50,
            -- assignee = "@me",
        })
    end)
    vim.keymap.set("n", "<leader>qi", function()
        M.view_issue("2", {
            -- project = "llvm/llvm-project",
            -- project = "JonasToth/dotfiles"
            -- issue_nbr = "56777",
            -- issue_nbr = "102983",
        })
    end)

    vim.keymap.set("n", "<leader>qc", M.cached_issues_picker)

    vim.keymap.set("n", "<leader>qa", function()
        M.get_labels()
    end)

    vim.keymap.set("n", "<leader>qn", function()
        M.create_issue(M.opts)
    end)
end

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
---@param buf number Buffer ID to work on.
local set_issue_buffer_options = function(buf)
    a.nvim_set_option_value('readonly', true, { buf = buf })
    a.nvim_set_option_value('buftype', 'nowrite', { buf = buf })
    a.nvim_set_option_value('filetype', 'markdown', { buf = buf })
    a.nvim_set_option_value('syntax', 'markdown', { buf = buf })

    local key_opts_from_desc = function(description)
        return { buffer = buf, nowait = true, desc = description, silent = true }
    end
    vim.keymap.set("n", "<localleader>q", ":close<CR>", key_opts_from_desc("Close Issue"))

    local log = require("gitforge.log")
    vim.keymap.set("n", "<localleader>c", function()
            vim.schedule(function()
                local issue_number = require("gitforge.generic_issue").get_issue_id_from_buf(buf)
                if issue_number == nil then
                    log.notify_failure("Failed to determine issue id to comment on in buffer " .. buf)
                    return
                end
                M.comment_on_issue(issue_number)
            end)
        end,
        key_opts_from_desc("Comment on Issue"))

    vim.keymap.set("n", "<localleader>u", function()
            M.update_issue_buffer(buf)
            log.notify_change("Updated the issue buffer")
        end,
        key_opts_from_desc("Update Issue"))

    vim.keymap.set("n", "<localleader>t", function()
            vim.schedule(function()
                log.trace_msg("Change Title")
                local curr_buf_content = a.nvim_buf_get_lines(buf, 0, 1, false)
                local headline_markdown = curr_buf_content[1]
                -- strip markdown header 1
                local headline = headline_markdown:sub(3, -1)
                vim.ui.input({ prompt = "Enter New Title: ", default = headline },
                    function(input)
                        if input == nil then
                            log.ephemeral_info("Aborted input")
                            return
                        end
                        if #input == 0 then
                            log.notify_failure("Empty new Title is not allowed")
                        end
                        M.change_title(buf, input)
                    end)
            end)
        end,
        key_opts_from_desc("Change Title"))

    vim.keymap.set("n", "<localleader>l", function()
            vim.schedule(function()
                local previous_labels = require("gitforge.generic_issue").get_labels_from_issue_buffer(buf)
                if previous_labels == nil then
                    return
                end
                vim.ui.input({ prompt = "Enter New Labels: ", default = previous_labels },
                    function(input)
                        if input == nil then
                            log.ephemeral_info("Aborted Issue Label Change")
                            return
                        end
                        M.change_labels(buf, previous_labels, input)
                    end)
            end)
        end,
        key_opts_from_desc("Change Labels"))

    vim.keymap.set("n", "<localleader>a", function()
            vim.schedule(function()
                local previous_assignee = M.get_assignee_from_issue_buffer(buf)
                if previous_assignee == nil then
                    return
                end
                vim.ui.input({ prompt = "Enter New Assignee(s): ", default = previous_assignee },
                    function(input)
                        if input == nil then
                            log.ephemeral_info("Aborted Issue Assigning")
                            return
                        end
                        M.change_assignees(buf, previous_assignee, input)
                    end)
            end)
        end,
        key_opts_from_desc("Assign Issue"))

    vim.keymap.set("n", "<localleader>e", function()
            M.change_issue_description(buf, M.opts)
        end,
        key_opts_from_desc("Edit Issue Body"))

    vim.keymap.set("n", "<localleader>s", function()
            M.change_issue_state(buf, M.opts)
        end,
        key_opts_from_desc("Edit State - Reopen/Close"))
end

---Return the string of the current state of the issue buffer @c buf if possible.
---@param buf number Buffer-Id for the issue
---@return string|nil status String representation of the issue status if found,  otherwise @c nil.
function M.get_status_from_issue_buffer(buf)
    local log = require("gitforge.log")
    local curr_buf_content = a.nvim_buf_get_lines(buf, 4, 5, false)
    local status_line = curr_buf_content[1]
    if status_line == nil then
        log.notify_failure("Failed to get status line from buffer " .. buf)
        return nil;
    end
    local extracted_status = string.match(status_line, "^Status: (.+) %(")
    if extracted_status == nil then
        log.notify_failure("Failed to extract status from buffer " .. buf .. " and supposed state line:\n" .. status_line)
        return nil
    end
    return vim.trim(extracted_status)
end

---Return the comma separated list of assignees from the issue buffer @c buf if possible.
---@param buf number Buffer-ID for Issue.
---@return string|nil Returns a comma separated list of assignees on success, otherwise @c nil.
function M.get_assignee_from_issue_buffer(buf)
    local log = require("gitforge.log")
    local curr_buf_content = a.nvim_buf_get_lines(buf, 5, 6, false)
    local assignee_line = curr_buf_content[1]
    if assignee_line == nil then
        log.notify_failure("Failed to get assignee line from buffer " .. buf)
        return nil;
    end
    -- verify that the labels line is found
    if assignee_line:sub(1, 12) ~= "Assigned to:" then
        log.notify_failure("Found assignee line does not contain 'Assigned to:' at beginning of line, ERROR (line: " ..
            assignee_line .. ")")
        return nil
    end
    -- extract all labels from the line
    local assignees = assignee_line:sub(14, -1)
    if assignees == "-" then
        return ""
    else
        return assignees
    end
end

-- Returns the issue labels of the current project.
function M.get_labels()
    local log = require("gitforge.log")
    local selected_labels = {}
    local on_choice = function(choice)
        print(choice)
        table.insert(selected_labels, choice)
    end
    local handle_labels = function(handle)
        if handle.code ~= 0 then
            log.notify_failure("Failed to query Labels:\n" .. handle.stderr)
            return
        end
        vim.schedule(function()
            local label_list_json = vim.fn.json_decode(handle.stdout)
            if label_list_json == nil then
                log.notify_failure("Failed to parse JSON response for labels")
                return
            end
            vim.ui.select(label_list_json, {
                prompt = "Select Label",
                format_item = function(label_element) return label_element["name"] end
            }, on_choice)
        end)
    end
    local gh_call = { "gh", "label", "list", "--json", "name,color,description" }
    log.executed_command(gh_call)
    local output = vim.system(gh_call, { text = true, timeout = M.opts.timeout }, handle_labels)
    output:wait()

    return selected_labels
end

-- Creates a new issue by prompting for the title. The description is written in a new buffer.
-- TODO: Provide a way to select labels directly on creation.
--       Right now it needs to be done by editing the new issue.
function M.create_issue(opts)
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
        vim.schedule(function()
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
            local url_elements = vim.split(issue_link, "/")
            local id
            for index, value in ipairs(url_elements) do
                if index == 7 then
                    id = value
                    break
                end
            end
            if id == nil or #id == 0 then
                log.notify_failure("Failed to extract issue id from URL")
                log.trace_msg(vim.join(url_elements, " : "))
                return
            end
            local int_id = tonumber(id)
            if int_id == nil then
                log.notify_failure("Failed to parse id-string as int")
                log.trace_msg(id)
                return
            end
            M.view_issue(int_id, opts)
        end)
    end
    local create_issue_call = function()
        local gh_call = { "gh", "issue", "create", "--title", title, "--body-file", description_file }
        log.executed_command(gh_call)
        vim.system(gh_call, { text = true, timeout = opts.timeout }, show_issue_after_creation)
    end
    local write_description_in_tmp_buffer = function()
        description_file = os.tmpname()
        local buf = a.nvim_create_buf(false, false)
        log.trace_msg("Created buffer and tempfile for it")
        if buf == 0 then
            log.notify_failure("Failed to create buffer to write the description.")
            return
        end
        a.nvim_buf_set_name(buf, description_file)

        local win_split = require("gitforge.generic_ui").open_edit_window(buf)
        if win_split == 0 then
            log.notify_failure("Failed to create window split for writing the description.")
            return
        end

        log.trace_msg("Created win split for tmpfile buffer")

        vim.cmd("edit " .. description_file)
        -- Switch to insert mode to be ready to type the comment directly.
        a.nvim_feedkeys(a.nvim_replace_termcodes("i", true, false, true), "n", false)

        local autocmdid
        autocmdid = a.nvim_create_autocmd("WinLeave", {
            -- group = a.nvim_create_augroup("GitForge", { clear = true }),
            callback = function()
                log.trace_msg("Callback on WinLeave is called")
                if win_split ~= 0 then
                    create_issue_call()
                    win_split = 0
                end
                a.nvim_del_autocmd(autocmdid)
            end
        })
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

function M.comment_on_issue(issue_number)
    local log = require("gitforge.log")
    local generic_ui = require("gitforge.generic_ui")

    local comment_file = os.tmpname()
    log.trace_msg("Tempfile for comment: " .. comment_file)
    local comment_buf = a.nvim_create_buf(false, false)
    local cleanup = function() os.remove(comment_file) end
    if comment_buf == 0 then
        log.notify_failure("Failed to create buffer for commenting")
        cleanup()
        return
    end
    a.nvim_buf_set_name(comment_buf, comment_file)

    local win_split = require("gitforge.generic_ui").open_edit_window(comment_buf)
    if win_split == 0 then
        log.notify_failure("Failed to create window split for commenting")
        cleanup()
        return
    end

    vim.cmd("edit " .. comment_file)
    -- Switch to insert mode to be ready to type the comment directly.
    a.nvim_feedkeys(a.nvim_replace_termcodes("i", true, false, true), "n", false)

    local perform_comment = function()
        local util = require("gitforge.utility")
        local str = util.buffer_to_string(comment_buf)
        if #str == 0 then
            log.ephemeral_info("Aborted commenting with empty content")
            cleanup()
            return
        end
        local gh_call = { "gh", "issue", "comment", issue_number, "--body-file", comment_file }
        log.executed_command(gh_call)
        vim.fn.system(gh_call)
        log.notify_change("Commented on issue " .. issue_number)
        cleanup()
    end
    local autocmdid
    autocmdid = a.nvim_create_autocmd("WinLeave", {
        group = a.nvim_create_augroup("GitForge", { clear = true }),
        callback = function()
            if win_split ~= 0 then
                perform_comment()
                win_split = 0

                local buf = generic_ui.find_existing_issue_buffer(issue_number)
                M.update_issue_buffer(buf)
            end
            a.nvim_del_autocmd(autocmdid)
        end
    })
end

---Called on an issue buffer. Parses out the current issue description, opens a new windows
---with the previous description and allows editing it. After save-closing the window, the
---description is updated on the issue.
---@param opts table Project options
function M.change_issue_description(buf, opts)
    -- FIXME: The last instance of '## Comments' must be found, because the issue content
    --        could have this line itself! The problem is, that comments themself might have
    --        this line contained. So the last instance is wrong. Somewhere in between "smart".
    --        The solution is likely just using a weird '## Comments' headline in rendering ...
    local log = require("gitforge.log")
    local util = require("gitforge.utility")
    log.trace_msg("Edit Issue Description")
    local issue_number = require("gitforge.generic_issue").get_issue_id_from_buf(buf)
    if issue_number == nil then
        log.notify_failure("Failed to retrieve issue number for issue in buffer " .. buf)
        return
    end
    local full_issue_str = util.buffer_to_string(buf)
    local idx_start_of_desc_headline = string.find(full_issue_str, g_description_headline_md, 1, true)
    if idx_start_of_desc_headline == nil then
        log.notify_failure("Failed to find headline for description in issue buffer " .. buf)
        return
    end

    local idx_newline_after_description_headline = string.find(full_issue_str, "\n", idx_start_of_desc_headline)
    if idx_newline_after_description_headline == nil then
        log.notify_failure("Expected a newline character after headline string in issue buffer " .. buf)
        return
    else
        -- Remove the two '\n' inserted after the headline.
        idx_newline_after_description_headline = idx_newline_after_description_headline + 2
    end
    local idx_start_of_comments = string.find(full_issue_str, g_comments_headline_md,
        idx_newline_after_description_headline, true)
    if idx_start_of_comments == nil then
        idx_start_of_comments = #full_issue_str
    else
        -- Remove the '\n#' of the headline and the final '\n' of the description.
        idx_start_of_comments = idx_start_of_comments - 3
    end
    if idx_start_of_comments - idx_newline_after_description_headline < 2 then
        log.notify_failure(
            "Expected a greater distance between start of description and start of comments. Bug?! in issue buffer " ..
            buf)
        return
    end
    local parsed_description = string.sub(full_issue_str, idx_newline_after_description_headline, idx_start_of_comments)
    log.trace_msg(parsed_description)

    -- open new tmp buffer, like when commenting/creating
    -- sending / changing the issue body with body-file on save-close
    local tmp_desc_file = os.tmpname()
    local descr_edit_buf = a.nvim_create_buf(false, false)
    local cleanup = function() os.remove(tmp_desc_file) end
    if descr_edit_buf == 0 then
        log.notify_failure("Failed to create buffer to edit description")
        cleanup()
        return
    end
    a.nvim_buf_set_name(descr_edit_buf, tmp_desc_file)
    if parsed_description ~= "No Description" then
        a.nvim_buf_set_lines(descr_edit_buf, 0, -1, true, vim.split(parsed_description, '\n'))
    else
        parsed_description = ""
    end
    local win_split = require("gitforge.generic_ui").open_edit_window(descr_edit_buf)
    if win_split == 0 then
        log.notify_failure("Failed to create window to edit the description")
        cleanup()
        return
    end

    --Populating the buffer with content requires an initial write.
    vim.cmd("write! " .. tmp_desc_file)
    vim.cmd("edit " .. tmp_desc_file)

    local edit_description = function()
        local new_desc = util.buffer_to_string(descr_edit_buf)
        if new_desc == parsed_description then
            log.ephemeral_info("No update to the description occured.")
        else
            local gh_call = { "gh", "issue", "edit", issue_number, "--body-file", tmp_desc_file }
            log.executed_command(gh_call)
            vim.fn.system(gh_call)
            log.notify_change("Updated the description of issue " .. issue_number)
        end
        cleanup()
    end
    local autocmdid
    autocmdid = a.nvim_create_autocmd("WinLeave", {
        group = a.nvim_create_augroup("GitForge", { clear = true }),
        callback = function()
            if win_split ~= 0 then
                edit_description()
                win_split = 0
                M.update_issue_buffer(buf)
            end
            a.nvim_del_autocmd(autocmdid)
        end,
    })
end

function M.change_issue_state(buf, opts)
    local log = require("gitforge.log")
    log.trace_msg("Edit State - Open/Close")
    local issue_number = require("gitforge.generic_issue").get_issue_id_from_buf(buf)
    local issue_status = M.get_status_from_issue_buffer(buf)

    local compute_possible_next_states = function(current_state)
        if current_state == "OPEN" then
            return { "CLOSED completed", "CLOSED not planned", current_state }
        else
            return { "REOPEN", current_state }
        end
    end
    local list_of_next_stati = compute_possible_next_states(issue_status)
    vim.ui.select(list_of_next_stati, { prompt = "Select new issue state:", },
        function(choice)
            if issue_status == choice then
                log.ephemeral_info("Issue state did not change")
                return
            end
            log.trace_msg("From " .. issue_status .. " to " .. choice)
            local gh_call = { "gh", "issue", }
            if choice == "CLOSED completed" then
                table.insert(gh_call, "close")
                table.insert(gh_call, issue_number)
                table.insert(gh_call, "--reason")
                table.insert(gh_call, "completed")
            elseif choice == "CLOSED not planned" then
                table.insert(gh_call, "close")
                table.insert(gh_call, issue_number)
                table.insert(gh_call, "--reason")
                table.insert(gh_call, "not planned")
            elseif choice == "REOPEN" then
                table.insert(gh_call, "reopen")
                table.insert(gh_call, issue_number)
            else
                log.notify_failure("Unexpected next state occured. BUG detected. Performing no update!")
                return
            end
            log.executed_command(gh_call)
            vim.fn.system(gh_call)
            log.notify_change("Changed the state for issue " .. issue_number)
            M.update_issue_buffer(buf)
        end)
end

function M.cached_issues_picker()
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
                    M.view_issue(selection.value.issue_number, {
                        project = opts.project,
                    })
                end)
                return true
            end,
        })
        :find()
end

local create_telescope_picker_for_issue_list = function(issue_list_json)
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
                    set_issue_buffer_options(buf)
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
                M.view_issue(selection.value.number, {
                    project = opts.project,
                })
            end)
            return true
        end,
    }):find()
end

function M.list_issues(opts)
    local log = require("gitforge.log")
    local open_telescope_list = function(handle)
        if handle.code ~= 0 then
            log.notify_failure("Failed to retrieve issue list")
            return
        end
        local data = vim.json.decode(handle.stdout)
        vim.schedule(function() create_telescope_picker_for_issue_list(data) end)
    end
    local required_fields =
    "title,labels,number,state,milestone,createdAt,updatedAt,body,author,assignees"
    local gh_call = { "gh", "issue", "list", "--state", "all", "--json", required_fields }
    if opts.project then
        table.insert(gh_call, "-R")
        table.insert(gh_call, opts.project)
    end
    if opts.limit then
        table.insert(gh_call, "--limit")
        table.insert(gh_call, tostring(opts.limit))
    end
    if opts.labels then
        table.insert(gh_call, "--label")
        table.insert(gh_call, opts.labels)
    end
    if opts.assignee then
        table.insert(gh_call, "--assignee")
        table.insert(gh_call, opts.assignee)
    end
    log.executed_command(gh_call)
    local call_handle = vim.system(gh_call, { text = true, timeout = M.opts.timeout }, open_telescope_list)
    call_handle:wait()
end

function M.fetch_issue_call(issue_number, opts)
    local required_fields =
    "title,body,createdAt,author,comments,assignees,labels,number,state,milestone,closed,closedAt"
    local gh_call = { "gh", "issue", "view", issue_number, "--json", required_fields }
    if opts.project then
        table.insert(gh_call, "-R")
        table.insert(gh_call, opts.project)
    end
    return gh_call
end

function M.update_issue_buffer(buf)
    local log = require("gitforge.log")
    local generic_ui = require("gitforge.generic_ui")
    local opts = {}
    local issue_number = require("gitforge.generic_issue").get_issue_id_from_buf(buf)
    local gh_call = M.fetch_issue_call(issue_number, opts)

    log.executed_command(gh_call)
    vim.system(gh_call, { text = true, timeout = M.opts.timeout },
        function(handle)
            if handle.code ~= 0 then
                log.notify_failure("Failed to retrieve issue content")
                return
            end
            vim.schedule(function()
                local issue_json = vim.fn.json_decode(handle.stdout)
                log.trace_msg("update single issue in buf: " .. tostring(buf))
                buf = require("gitforge.generic_issue").render_issue_to_buffer(buf, issue_json)

                local title_ui = generic_ui.issue_title_ui(issue_json)
                a.nvim_buf_set_name(buf, title_ui)
                set_issue_buffer_options(buf)
                log.ephemeral_info("Updated content for issue " .. issue_number)
            end)
        end)
end

function M.view_issue(issue_number, opts)
    local log = require("gitforge.log")
    local generic_ui = require("gitforge.generic_ui")
    local generic_issue = require("gitforge.generic_issue")

    local buf = generic_ui.find_existing_issue_buffer(issue_number)

    local open_buffer_with_issue = function(handle)
        if handle.code ~= 0 then
            log.notify_failure("Failed to retrieve issue content")
            return
        end
        vim.schedule(function()
            local data = vim.fn.json_decode(handle.stdout)

            log.trace_msg("view single issue in buf: " .. tostring(buf))
            buf = generic_issue.render_issue_to_buffer(buf, data)

            local title_ui = generic_ui.issue_title_ui(data)
            a.nvim_buf_set_name(buf, title_ui)
            set_issue_buffer_options(buf)

            generic_ui.create_issue_window(buf, title_ui)
        end)
    end

    local gh_call = M.fetch_issue_call(issue_number, opts)

    if buf == 0 then
        log.trace_msg("Issue not available as buffer - creating it new")
        log.executed_command(gh_call)
        local call_handle = vim.system(gh_call, { text = true, timeout = M.opts.timeout }, open_buffer_with_issue)
        call_handle:wait()
    else
        log.trace_msg("Found issue in buffer - displaying old state and triggering update")
        local title_ui = a.nvim_buf_get_name(buf)
        generic_ui.create_issue_window(buf, title_ui)

        -- Trigger an update after already opening the issue in a window.
        log.executed_command(gh_call)
        vim.system(gh_call, { text = true, timeout = M.opts.timeout },
            function(handle)
                if handle.code ~= 0 then
                    log.notify_failure("Failed to retrieve issue content")
                    return
                end
                vim.schedule(function() M.update_issue_buffer(buf) end)
            end)
    end
end

function M.change_title(buf, title_input)
    local log = require("gitforge.log")
    local issue_number = require("gitforge.generic_issue").get_issue_id_from_buf(buf)
    local handle_title_update = function(handle)
        vim.schedule(function()
            if handle.code ~= 0 then
                log.notify_failure("Failed to update title")
                return
            end
            log.notify_change("Updated the title for issue " .. issue_number)
            M.update_issue_buffer(buf)
        end)
    end
    local gh_call = { "gh", "issue", "edit", issue_number, "--title", title_input }
    log.executed_command(gh_call)
    local call_handle = vim.system(gh_call, { text = true, timeout = M.opts.timeout }, handle_title_update)
    call_handle:wait()
end

---Compute the removed and added elements of a CSV list.
---@param new_input_csv string CSV string of elements
---@param previous_input_csv string CSV string of elements
---@return Set added elements that were added in @c new_input_csv
---@return Set removed elements that were remove in @c new_input_csv
local compute_add_and_remove_sets = function(new_input_csv, previous_input_csv)
end

---@param new_labels Set
---@param removed_labels Set
local create_label_update_command = function(new_labels, removed_labels, buf)
    local issue_number = require("gitforge.generic_issue").get_issue_id_from_buf(buf)
    local gh_call = { "gh", "issue", "edit", issue_number }

    if not removed_labels:empty() then
        table.insert(gh_call, "--remove-label")
        table.insert(gh_call, removed_labels:toCSV())
    end

    if not new_labels:empty() then
        table.insert(gh_call, "--add-label")
        table.insert(gh_call, new_labels:toCSV())
    end
    return gh_call
end

---@param new_assignees Set
---@param removed_assignees Set
local create_assignee_update_command = function(new_assignees, removed_assignees, buf)
    local issue_number = require("gitforge.generic_issue").get_issue_id_from_buf(buf)
    local gh_call = { "gh", "issue", "edit", issue_number }

    if not removed_assignees:empty() then
        table.insert(gh_call, "--remove-assignee")
        table.insert(gh_call, removed_assignees:toCSV())
    end

    if not new_assignees:empty() then
        table.insert(gh_call, "--add-assignee")
        table.insert(gh_call, new_assignees:toCSV())
    end
    return gh_call
end

---Changes the labels of issue in @c buf from comma-separated list in @c previous_labels to
---comma separated list in @c new_labels
---@param buf number Buffer-ID of the issue
---@param previous string comma separated list of the previous labels, used for set difference
---@param new string comma separated list of new labels, used for set difference
function M.change_labels(buf, previous, new)
    require("gitforge.set")
    local log = require("gitforge.log")

    local added, removed = Set:createFromCSVList(previous):deltaTo(Set:createFromCSVList(new))
    if removed:empty() and added:empty() then
        log.ephemeral_info("Labels did not change.")
        return
    end
    local gh_call = create_label_update_command(added, removed, buf)
    if gh_call == nil then
        log.notify_failure("Failed to generate command to update labels.")
        return
    end
    local handle_label_update = function(handle)
        vim.schedule(function()
            if handle.code ~= 0 then
                a.nvim_err_write(handle.stderr)
                a.nvim_err_write(handle.stdout)
                log.notify_failure("Failed to update labels")
                return
            end
            log.notify_change("Updated Labels")
            M.update_issue_buffer(buf)
        end)
    end
    log.executed_command(gh_call)
    local call_handle = vim.system(gh_call, { text = true, timeout = M.opts.timeout }, handle_label_update)
    call_handle:wait()
end

---Changes the assignees of issue in @c buf from comma-separated list in @c previous_labels to
---comma separated list in @c new_labels
---@param buf number Buffer-ID of the issue
---@param previous string comma separated list of the previous assignees, used for set difference
---@param new string comma separated list of new assignees, used for set difference
function M.change_assignees(buf, previous, new)
    require("gitforge.set")
    local log = require("gitforge.log")

    local added, removed = Set:createFromCSVList(previous):deltaTo(Set:createFromCSVList(new))
    if removed:empty() and added:empty() then
        log.ephemeral_info("Assignees did not change.")
        return
    end

    local gh_call = create_assignee_update_command(added, removed, buf)
    if gh_call == nil then
        log.notify_failure("Failed to create command to update assignees")
        return
    end
    local handle_assignee_update = function(handle)
        vim.schedule(function()
            if handle.code ~= 0 then
                --TODO: Better error logging
                a.nvim_err_write(handle.stderr)
                a.nvim_err_write(handle.stdout)
                log.notify_failure("Failed to update assignees")
                return
            end
            log.notify_change("Updated Assignees")
            M.update_issue_buffer(buf)
        end)
    end
    log.executed_command(gh_call)
    local call_handle = vim.system(gh_call, { text = true, timeout = M.opts.timeout }, handle_assignee_update)
    call_handle:wait()
end

return M
