local PRActions = {}

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

---@param issue_list_json table<Issue>
---@param provider IssueProvider
local create_telescope_picker_for_pr_list = function(issue_list_json, provider)
    local opts = {}

    require("telescope.pickers").new(opts, {
        prompt_title = "PullRequest List",
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
                    -- Display the previously rendered content for the PR. Comments will be
                    -- present in this case.
                    vim.api.nvim_set_option_value('filetype', 'markdown', { buf = self.state.bufnr })
                    require("gitforge.utility").copy_buffer(buf, self.state.bufnr)
                end
            end
        }),
        sorter = require("telescope.config").values.generic_sorter(opts),
        -- TODO: View the PR after its picked from the list.
        -- attach_mappings = function(prompt_bufnr) return issue_pick_mapping(prompt_bufnr, provider) end,
    }):find()
end

---@param opts IssueListOpts
---@param provider IssueProvider|nil
function PRActions.list_prs(opts, provider)
    local log = require("gitforge.log")
    local prov = provider or require("gitforge.issue_provider").get_from_cwd_or_default()

    local open_telescope_list = function(handle)
        if handle.code ~= 0 then
            log.notify_failure("Failed to retrieve issue list:" .. handle.stdout .. "\n" .. handle.stderr)
            return
        end
        vim.schedule(function()
            local data = prov:convert_cmd_result_to_pr_list(handle.stdout)
            create_telescope_picker_for_pr_list(data, prov)
        end)
    end
    local handle = require("gitforge.utility").async_exec(prov:cmd_list_prs(opts), open_telescope_list)
    if handle then handle:wait() end
end

return PRActions
