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

    vim.keymap.set("n", "<leader>qc", M.cached_issues_picker)

    vim.keymap.set("n", "<leader>qa", function()
        P(M.get_labels())
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

---Finds an existing buffer that holds @c issue_number.
---@param issue_number number
---@return integer buf_id if a matching buffer is found, otherwise @c 0
local find_existing_issue_buffer = function(issue_number)
    local title_id = forge_issue_pattern .. tostring(issue_number)
    local all_bufs = a.nvim_list_bufs()

    for _, buf_id in pairs(all_bufs) do
        local buf_name = a.nvim_buf_get_name(buf_id)
        local found = string.find(buf_name, title_id, 1, true)
        if found ~= nil then
            return buf_id
        end
    end
    return 0
end

--- Parses the buffer name and tries to retrieve the issue number and project.
---@param buf number Buffer Id for the issue buffer
local get_issue_id_from_buf = function(buf)
    local buf_name = a.nvim_buf_get_name(buf)
    if string.find(buf_name, "[Issue]", 1, true) == nil then
        return nil
    end
    for nbr in buf_name:gmatch("#(%d)") do
        return nbr
    end
end

local addToSet = function(set, key)
    set[key] = true
end

local removeFromSet = function(set, key)
    set[key] = nil
end

local setContains = function(set, key)
    return set[key] ~= nil
end

---Computes @c set1 - set2
---@param set1 table Keys are set values.
---@param set2 table Keys are set values.
---@return table Keys that are in @c set1 but not in @c set2
---@sa addToSet(), setContains()
local setDifference = function(set1, set2)
    local result_set = {}
    for key, _ in pairs(set1) do
        if not setContains(set2, key) then
            addToSet(result_set, key)
        end
    end
    return result_set
end

---Create a set from a comma separated list of labels.
---@param label_string string Comma separated list of labels.
---@return table Keys are set elements.
local createSetFromLabels = function(label_string)
    local result_set = {}
    for _, el in pairs(vim.split(label_string, ",")) do
        addToSet(result_set, el)
    end
    return result_set
end

local flattenLabelSetToLabelList = function(label_set)
    local label_table = {}
    for key, _ in pairs(label_set) do
        table.insert(label_table, key)
    end
    return vim.fn.join(label_table, ",")
end

function table.empty(self)
    for _, _ in pairs(self) do
        return false
    end
    return true
end

local create_label_update_command = function(new_label_input, previous_labels, buf)
    local previous_labels_set = createSetFromLabels(previous_labels)
    local new_labels_set = createSetFromLabels(new_label_input)
    local removed_labels = setDifference(previous_labels_set, new_labels_set)
    local new_labels = setDifference(new_labels_set, previous_labels_set)

    local issue_number = get_issue_id_from_buf(buf)
    local gh_call = { "gh", "issue", "edit", issue_number }

    if not table.empty(removed_labels) then
        table.insert(gh_call, "--remove-label")
        table.insert(gh_call, flattenLabelSetToLabelList(removed_labels))
    end

    if not table.empty(new_labels) then
        table.insert(gh_call, "--add-label")
        table.insert(gh_call, flattenLabelSetToLabelList(new_labels))
    end
    return gh_call
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

    vim.keymap.set("n", "<localleader>c", function()
            vim.schedule(function()
                local issue_number = get_issue_id_from_buf(buf)
                if issue_number == nil then
                    print("Failed to determine issue id to comment on")
                    return
                end
                M.comment_on_issue(issue_number)
            end)
        end,
        key_opts_from_desc("Comment on Issue"))

    vim.keymap.set("n", "<localleader>u", function()
            M.update_issue_buffer(buf)
        end,
        key_opts_from_desc("Update Issue"))

    vim.keymap.set("n", "<localleader>t", function()
            vim.schedule(function()
                print("Change Title")
                local curr_buf_content = a.nvim_buf_get_lines(buf, 0, 1, false)
                local headline_markdown = curr_buf_content[1]
                -- strip markdown header 1
                local headline = headline_markdown:sub(3, -1)
                vim.ui.input({ prompt = "Enter New Title: ", default = headline },
                    function(input)
                        if input == nil then
                            print("Aborted input")
                            return
                        end
                        if #input == 0 then
                            print("Empty new Title is not allowed")
                        end
                        local handle_title_update = function(handle)
                            vim.schedule(function()
                                if handle.code ~= 0 then
                                    print("Failed to update title")
                                    return
                                end
                                print("Updated title")
                                M.update_issue_buffer(buf)
                            end)
                        end
                        local issue_number = get_issue_id_from_buf(buf)
                        local gh_call = { "gh", "issue", "edit", issue_number, "--title", input }
                        local call_handle = vim.system(gh_call, { text = true, timeout = M.opts.timeout },
                            handle_title_update)
                        call_handle:wait()
                    end)
            end)
        end,
        key_opts_from_desc("Change Title"))

    vim.keymap.set("n", "<localleader>l", function()
            vim.schedule(function()
                local curr_buf_content = a.nvim_buf_get_lines(buf, 5, 6, false)
                local label_line = curr_buf_content[1]
                -- verify that the labels line is found
                if label_line:sub(1, 7) ~= "Labels:" then
                    print("Failed to query the labels from issue buffer. Error")
                    return
                end
                -- extract all labels from the line
                local previous_labels = label_line:sub(9, -1)
                vim.ui.input({ prompt = "Enter New Labels: ", default = previous_labels },
                    function(input)
                        if input == nil then
                            print("Aborted Issue Label Change")
                            return
                        end
                        local gh_call = create_label_update_command(input, previous_labels, buf)
                        local handle_label_update = function(handle)
                            vim.schedule(function()
                                if handle.code ~= 0 then
                                    print("Failed to update labels")
                                    return
                                end
                                print("Updated Labels")
                                M.update_issue_buffer(buf)
                            end)
                        end
                        local call_handle = vim.system(gh_call, { text = true, timeout = M.opts.timeout },
                            handle_label_update)
                        call_handle:wait()
                    end)
            end)
        end,
        key_opts_from_desc("Change Labels"))

    vim.keymap.set("n", "<localleader>a", function()
            print("Assign Issue")
            -- input login name
            -- assign
        end,
        key_opts_from_desc("Assign Issue"))

    vim.keymap.set("n", "<localleader>e", function()
            print("Edit Issue Body")
            -- open buffer, like when commenting
            -- sending / changing the issue body one save-close
        end,
        key_opts_from_desc("Edit Issue Body"))

    vim.keymap.set("n", "<localleader>s", function()
            print("Edit State - Open/Close")
            -- open buffer, like when commenting
            -- sending / changing the issue body one save-close
        end,
        key_opts_from_desc("Edit State - Reopen/Close"))
end

local buffer_to_string = function(buf)
    local curr_buf_content = a.nvim_buf_get_lines(buf, 0, -1, false)
    return vim.fn.join(curr_buf_content, "\n")
end

local copy_buffer = function(from_buf, to_buf)
    local curr_buf_content = a.nvim_buf_get_lines(from_buf, 0, -1, false)
    a.nvim_buf_set_lines(to_buf, 0, -1, false, curr_buf_content)
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
    a.nvim_set_option_value('readonly', false, { buf = buf })
    a.nvim_set_option_value('buftype', 'nofile', { buf = buf })
    a.nvim_set_option_value('swapfile', false, { buf = buf })

    a.nvim_buf_set_lines(buf, 0, -1, true, { '# ' .. issue_json.title, '' })
    local realName = ''
    if issue_json.author and issue_json.author.name then
        realName = '(' .. issue_json.author.name .. ') '
    end
    a.nvim_buf_set_lines(buf, -1, -1, true, { 'Number: #' .. issue_json.number })
    a.nvim_buf_set_lines(buf, -1, -1, true,
        { 'Created by `@' .. issue_json.author.login .. '` ' .. realName .. 'at ' .. issue_json.createdAt })
    if not issue_json.closed then
        a.nvim_buf_set_lines(buf, -1, -1, true, { 'Status: ' .. issue_json.state .. ' (' .. issue_json.createdAt .. ')' })
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
        a.nvim_buf_set_lines(buf, -1, -1, true, { '', '## Comments' })
        local comments = issue_json.comments
        if #comments == 0 then
            a.nvim_buf_set_lines(buf, -1, -1, true, { 'No comments' })
        else
            for _, comment in ipairs(comments) do
                local author = comment.author.login
                local timestamp = comment.createdAt
                local body = string.gsub(comment.body, "\r", "")
                a.nvim_buf_set_lines(buf, -1, -1, true, { '', '#### `@' .. author .. '` at __' .. timestamp .. "__", '' })
                a.nvim_buf_set_lines(buf, -1, -1, true, vim.split(vim.trim(body), '\n'))
            end
        end
    end
    a.nvim_set_option_value('modifiable', false, { buf = buf })
    a.nvim_set_option_value('readonly', true, { buf = buf })
    return buf
end

-- Returns the issue labels of the current project.
function M.get_labels()
    local selected_labels = {}
    local on_choice = function(choice)
        P(choice)
        table.insert(selected_labels, choice)
    end
    local handle_labels = function(handle)
        if handle.code ~= 0 then
            print("Failed to query Labels: " .. handle.stderr)
            return
        end
        vim.schedule(function ()
        local label_list_json = vim.fn.json_decode(handle.stdout)
        if label_list_json == nil then
            print("Failed to parse JSON response for labels")
            return
        end
        vim.ui.select(label_list_json, {
            prompt = "Select Label",
            format_item = function(label_element) return label_element["name"] end
        }, on_choice)
        end)
    end
    local gh_call = { "gh", "label", "list", "--json", "name,color,description" }
    local output = vim.system(gh_call, { text = true, timeout = M.opts.timeout }, handle_labels)
    output:wait()

    return selected_labels
end

function M.create_issue()
    local title = vim.fn.input({ prompt = "Issue Title: " })

    local title = "My New Issue"
    local labels = vim.fn.input({ prompt = "Labels (comma separated): " })

    vim.fn.system({ "gh", "issue", "create", "--title", title, "--label", labels })
end

function M.comment_on_issue(issue_number)
    local comment_file = os.tmpname()
    print("Tempfile for comment: " .. comment_file)
    local comment_buf = a.nvim_create_buf(false, false)
    local cleanup = function()
        os.remove(comment_file)
    end
    if comment_buf == 0 then
        print("Failed to create buffer for commenting")
        cleanup()
        return
    end
    a.nvim_buf_set_name(comment_buf, comment_file)
    a.nvim_set_option_value('readonly', false, { buf = comment_buf })
    a.nvim_set_option_value('modifiable', true, { buf = comment_buf })
    a.nvim_set_option_value('bufhidden', 'delete', { buf = comment_buf })
    a.nvim_set_option_value('buflisted', false, { buf = comment_buf })
    a.nvim_set_option_value('buftype', '', { buf = comment_buf })
    a.nvim_set_option_value('filetype', 'markdown', { buf = comment_buf })
    a.nvim_set_option_value('syntax', 'markdown', { buf = comment_buf })
    a.nvim_set_option_value('swapfile', false, { buf = comment_buf })

    local win_split = a.nvim_open_win(comment_buf, true, {
        split = "below",
    })
    if win_split == 0 then
        print("Failed to create window split for commenting")
        cleanup()
        return
    end

    vim.cmd("edit " .. comment_file)
    -- Switch to insert mode to be ready to type the comment directly.
    a.nvim_feedkeys(a.nvim_replace_termcodes("i", true, false, true), "n", false)

    local perform_comment = function()
        local str = buffer_to_string(comment_buf)
        if #str == 0 then
            print("Aborted commenting with empty content")
            cleanup()
            return
        end
        print("Wrote something in the windows")
        vim.fn.system({ "gh", "issue", "comment", issue_number, "--body-file", comment_file })
        cleanup()
    end
    a.nvim_create_autocmd("WinLeave", {
        group = a.nvim_create_augroup("GitForge", { clear = true }),
        callback = function()
            if win_split ~= 0 then
                perform_comment()
                win_split = 0

                local buf = find_existing_issue_buffer(issue_number)
                M.update_issue_buffer(buf)
            end
        end
    })
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

    local bufnrs = vim.tbl_filter(function(bufnr)
        local bufname = a.nvim_buf_get_name(bufnr)
        return string.find(bufname, "[Issue]", 1, true) ~= nil
    end, vim.api.nvim_list_bufs())

    if not next(bufnrs) then
        print("No issues buffers found")
        return
    end

    local buffers = {}
    local default_selection_idx = 1
    for _, bufnr in ipairs(bufnrs) do
        local bufname = a.nvim_buf_get_name(bufnr)
        local issue_number = get_issue_id_from_buf(bufnr)
        local element = {
            bufnr = bufnr,
            bufname = bufname,
            issue_number = issue_number,
        }
        table.insert(buffers, element)
    end

    P(buffers)
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
                    copy_buffer(entry.bufnr, self.state.bufnr)
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
                local buf = find_existing_issue_buffer(entry.number)

                -- The issue was not rendered before. Render it for the previewer, but also
                -- cache the content in a buffer.
                if buf == 0 then
                    -- Render once into the previewer.
                    a.nvim_set_option_value('filetype', 'markdown', { buf = self.state.bufnr })
                    M.render_issue_to_buffer(self.state.bufnr, entry.value)

                    -- Cache for snappy opening.
                    buf = M.render_issue_to_buffer(buf, entry.value)
                    local title_ui = issue_title_ui(entry.value)
                    a.nvim_buf_set_name(buf, title_ui)
                    set_issue_buffer_options(buf)
                else
                    -- Display the previously rendered content for the issue. Comments will be
                    -- present in this case.
                    a.nvim_set_option_value('filetype', 'markdown', { buf = self.state.bufnr })
                    copy_buffer(buf, self.state.bufnr)
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
    if opts.labels then
        table.insert(gh_call, "--label")
        table.insert(gh_call, opts.labels)
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
    local opts = {}
    local issue_number = get_issue_id_from_buf(buf)
    local gh_call = M.fetch_issue_call(issue_number, opts)
    vim.system(gh_call, { text = true, timeout = M.opts.timeout },
        function(handle)
            if handle.code ~= 0 then
                print("Failed to retrieve issue content")
                P(handle)
                return
            end
            vim.schedule(function()
                local issue_json = vim.fn.json_decode(handle.stdout)
                print("update single issue in buf: " .. tostring(buf))
                buf = M.render_issue_to_buffer(buf, issue_json)

                local title_ui = issue_title_ui(issue_json)
                a.nvim_buf_set_name(buf, title_ui)
                set_issue_buffer_options(buf)
            end)
        end)
end

function M.view_issue(issue_number, opts)
    local buf = find_existing_issue_buffer(issue_number)

    local open_buffer_with_issue = function(handle)
        if handle.code ~= 0 then
            print("Failed to retrieve issue content")
            P(handle)
            return
        end
        vim.schedule(function()
            local data = vim.fn.json_decode(handle.stdout)

            print("view single issue in buf: " .. tostring(buf))
            buf = M.render_issue_to_buffer(buf, data)

            local title_ui = issue_title_ui(data)
            a.nvim_buf_set_name(buf, title_ui)
            set_issue_buffer_options(buf)

            create_issue_window(buf, title_ui)
        end)
    end

    local gh_call = M.fetch_issue_call(issue_number, opts)

    if buf == 0 then
        P("Issue not available as buffer - creating it new")
        local call_handle = vim.system(gh_call, { text = true, timeout = M.opts.timeout }, open_buffer_with_issue)
        call_handle:wait()
    else
        P("Found issue in buffer - displaying old state and triggering update")
        local title_ui = a.nvim_buf_get_name(buf)
        create_issue_window(buf, title_ui)

        -- Trigger an update after already opening the issue in a window.
        vim.system(gh_call, { text = true, timeout = M.opts.timeout },
            function(handle)
                if handle.code ~= 0 then
                    print("Failed to retrieve issue content")
                    P(handle)
                    return
                end
                vim.schedule(function() M.update_issue_buffer(buf) end)
            end)
    end
end

return M
