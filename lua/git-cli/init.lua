local M = {}
local a = vim.api
local forge_issue_pattern = '[Issue] #'

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

--- Returns the standardized title of an issue.
--- @param issue_json table Table representation of the issue JSON.
--- @return string Concatentation of issue number and a shortened title.
local issue_title_ui = function(issue_json)
    local length_threshold = 50
    local shortened_title = string.sub(issue_json.title, 1, length_threshold)
    local title_id = forge_issue_pattern .. tostring(issue_json.number)
    local three_dots = #issue_json.title > length_threshold and "..." or ""
    return title_id .. " - " .. shortened_title .. three_dots
end

--- Renders the issue content into a buffer as markdown.
--- @param buf number Buffer-Id to work on. If `nil`, a new buffer is created.
--- @param issue_json table Table of JSON data.
--- @return number number of the buffer. Can be `0` if creation failed.
function M.render_issue_to_buffer(buf, issue_json)
    if issue_json == nil then
        return buf
    end

    if buf == 0 then
        buf = a.nvim_create_buf(true, false)
    end
    if buf == 0 then
        print("Failed to create buffer to view issues")
        return 0
    end

    print("Rendering issue in buf: " .. tostring(buf))
    local desc = string.gsub(issue_json.body, "\r", "")
    a.nvim_set_option_value('modifiable', true, { buf = buf })
    a.nvim_set_option_value('readonly', true, { buf = buf })
    a.nvim_set_option_value('buftype', 'nowrite', { buf = buf })

    a.nvim_buf_set_lines(buf, 0, -1, true, { '# ' .. issue_json.title, '' })
    local realName = ''
    if issue_json.author and issue_json.author.name then
        realName = '(' .. issue_json.author.name .. ') '
    end
    a.nvim_buf_set_lines(buf, -1, -1, true,
        { 'Created by `@' .. issue_json.author.login .. '` ' .. realName .. 'at ' .. issue_json.createdAt })
    if not issue_json.closed then
        a.nvim_buf_set_lines(buf, -1, -1, true, { 'Status: ' .. issue_json.state })
    else
        a.nvim_buf_set_lines(buf, -1, -1, true, { 'Status: ' .. issue_json.state .. ' (' .. issue_json.closedAt .. ')' })
    end
    local labels = {}
    for _, value in ipairs(issue_json.labels) do
        table.insert(labels, value.name)
    end
    if #labels > 0 then
        a.nvim_buf_set_lines(buf, -1, -1, true, { 'Labels: ' .. vim.fn.join(labels, ',') })
    end
    -- if issue_json.milestone ~= vim.NIL then
    --     P(issue_json.milestone)
    --     a.nvim_buf_set_lines(buf, -1, -1, true, { 'Milestone: ' .. issue_json.milestone })
    -- end

    a.nvim_buf_set_lines(buf, -1, -1, true, { '', '## Description', '' })
    if #desc == 0 then
        a.nvim_buf_set_lines(buf, -1, -1, true, { 'No Description' })
    else
        a.nvim_buf_set_lines(buf, -1, -1, true, vim.split(desc, '\n'))
    end
    if issue_json.comments ~= nil then
        a.nvim_buf_set_lines(buf, -1, -1, true, { '', '## Comments', '' })
        local comments = issue_json.comments
        if #comments == 0 then
            a.nvim_buf_set_lines(buf, -1, -1, true, { 'No comments' })
        else
            for _, comment in ipairs(comments) do
                local author = comment.author.login
                local timestamp = comment.createdAt
                local body = string.gsub(comment.body, "\r", "")
                a.nvim_buf_set_lines(buf, -1, -1, true, { '`@' .. author .. '` at __' .. timestamp .. "__", '' })
                a.nvim_buf_set_lines(buf, -1, -1, true, vim.split(body, '\n'))
                a.nvim_buf_set_lines(buf, -1, -1, true, { '', '---', '' })
            end
        end
    end
    a.nvim_set_option_value('modifiable', false, { buf = buf })
    return buf
end

-- Returns the issue labels of the current project.
function M.get_labels()
    local LabelList = {
        labels = {},
        descriptions = {},
        colors = {},
    }
    local on_choice = function(choice)
        table.insert(LabelList, { selected_label = choice })
    end
    local on_exit = function(obj)
        if obj.code ~= 0 then
            print("Failed to query Labels: " .. obj.stderr)
            return
        end
        local lines = {}
        for s in obj.stdout:gmatch("[^\r\n]+") do
            table.insert(lines, s)
        end

        for _, line in ipairs(lines) do
            local colums = {}
            for c in line:gmatch("[^\t]+") do
                table.insert(colums, c)
            end
            for i, str in ipairs(colums) do
                if i == 1 then
                    table.insert(LabelList.labels, str)
                elseif i == 2 then
                    table.insert(LabelList.descriptions, str)
                elseif i == 3 then
                    table.insert(LabelList.colors, str)
                end
            end
        end
        vim.ui.select(LabelList.labels, { prompt = "Select Label" }, on_choice)
    end
    local output = vim.system({ "gh", "label", "list" },
        { text = true, timeout = M.opts.timeout },
        on_exit)
    output:wait()
    P(LabelList)
    return LabelList
end

function M.create_issue()
    local title = vim.fn.input({ prompt = "Issue Title: " })

    local title = "My New Issue"
    local labels = vim.fn.input({ prompt = "Labels (comma separated): " })

    vim.fn.system({ "gh", "issue", "create", "--title", title, "--label", labels })
end

local create_telescope_picker_for_issue_list = function(issue_list_json)
    local ts = require("telescope")
    local pickers = require("telescope.pickers")
    local entry_display = require("telescope.pickers.entry_display")
    local finders = require("telescope.finders")
    local config = require("telescope.config")
    local previewers = require("telescope.previewers")
    local make_entry = require("telescope.make_entry")
    local opts = {}

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
                if #entry.assignees then
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
                a.nvim_set_option_value('filetype', 'markdown', { buf = self.state.bufnr })
                M.render_issue_to_buffer(self.state.bufnr, entry.value)
            end
        }),
        sorter = config.values.generic_sorter(opts),
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
    local open_telescope_list = function(handle)
        if handle.code ~= 0 then
            print("Failed to retrieve issue list")
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
    if opts.filter_labels then
        table.insert(gh_call, "--label")
        table.insert(gh_call, opts.filter_labels)
    end
    if opts.assignee then
        table.insert(gh_call, "--assignee")
        table.insert(gh_call, opts.assignee)
    end
    P(gh_call)
    local call_handle = vim.system(gh_call, { text = true, timeout = M.opts.timeout }, open_telescope_list)
    call_handle:wait()
end

---Creates a floating window for @c buf with the title @c title_ui
---Creates an autocommand to close the floating window if it looses focus.
---@param buf number Buffer-ID to display in the window.
---@param title_ui string Human Readable title for the window.
local create_issue_window = function(buf, title_ui)
    local width = math.ceil(math.min(vim.o.columns, math.min(100, vim.o.columns - 20)))
    local height = math.ceil(math.min(vim.o.lines, math.max(20, vim.o.lines - 10)))
    local row = math.ceil(vim.o.lines - height) * 0.5 - 1
    local col = math.ceil(vim.o.columns - width) * 0.5 - 1
    local win_options = {
        relative = 'editor',
        title = title_ui,
        title_pos = 'center',
        width = width,
        height = height,
        col = col,
        row = row,
        border = "single"
    }
    local win = a.nvim_open_win(buf, true, win_options)
    if win == 0 then
        print("Failed to open float for issue")
        return
    end
    -- Switch to normal mode - Telescope selection leaves in insert mode?!
    a.nvim_feedkeys(a.nvim_replace_termcodes("<Esc>", true, false, true), "i", false)
    -- Automatically close then float when it is left.
    a.nvim_create_autocmd("WinLeave", {
        group = a.nvim_create_augroup("GitForge", { clear = true }),
        callback = function()
            if win ~= 0 then
                a.nvim_win_close(win, true)
                win = 0
            end
        end
    })
end

local find_existing_issue_buffer = function(issue_number)
    local title_id = forge_issue_pattern .. tostring(issue_number)
    local all_bufs = a.nvim_list_bufs()

    for _, buf_id in pairs(all_bufs) do
        local buf_name = a.nvim_buf_get_name(buf_id)
        local found = string.find(buf_name, title_id, 1, true)
        if found ~= nil then
            print("Found existing ticket buffer - reusing and updating it")
            return buf_id
        end
    end
    return 0
end

local set_issue_buffer_options = function(buf)
    a.nvim_set_option_value('readonly', true, { buf = buf })
    a.nvim_set_option_value('buftype', 'nowrite', { buf = buf })
    a.nvim_set_option_value('filetype', 'markdown', { buf = buf })
    a.nvim_set_option_value('syntax', 'markdown', { buf = buf })
end

function M.view_issue(issue_number, opts)
    local open_buffer_with_issue = function(handle)
        if handle.code ~= 0 then
            print("Failed to retrieve issue content")
            P(handle)
            return
        end
        vim.schedule(function()
            local data = vim.fn.json_decode(handle.stdout)

            local buf = find_existing_issue_buffer(issue_number)

            print("view single issue in buf: " .. tostring(buf))
            buf = M.render_issue_to_buffer(buf, data)

            local title_ui = issue_title_ui(data)
            a.nvim_buf_set_name(buf, title_ui)
            set_issue_buffer_options(buf)

            a.nvim_buf_set_keymap(buf, "n", "q", ":close<CR>",
                { nowait = true, desc = "Close Issue", silent = true })

            create_issue_window(buf, title_ui)
        end)
    end

    local required_fields =
    "title,body,createdAt,author,comments,assignees,labels,number,state,milestone,closed,closedAt"
    local gh_call = { "gh", "issue", "view", issue_number, "--json", required_fields }
    if opts.project then
        table.insert(gh_call, "-R")
        table.insert(gh_call, opts.project)
    end
    P(gh_call)

    local call_handle = vim.system(gh_call, { text = true, timeout = M.opts.timeout }, open_buffer_with_issue)
    call_handle:wait()
end

return M
