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
            -- labels = "clang-tidy",
            limit = 50,
            -- assignee = "@me",
        }, provider)
    end)
    vim.keymap.set("n", "<leader>qc", function() M.cached_issues_picker(provider) end)
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
        M.view_issue(p)
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
                    M.view_issue(p)
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
                    generic_issue.set_issue_buffer_options(provider:new(buf))
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
                M.view_issue(p)
            end)
            return true
        end,
    }):find()
end

---@param opts IssueListOpts
---@param provider GHIssue
function M.list_issues(opts, provider)
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
    local gh_call = provider:cmd_list_issues(opts)
    log.executed_command(gh_call)
    local call_handle = vim.system(gh_call, { text = true, timeout = M.opts.timeout }, open_telescope_list)
    call_handle:wait()
end

---@param provider GHIssue
function M.view_issue(provider)
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

return M
