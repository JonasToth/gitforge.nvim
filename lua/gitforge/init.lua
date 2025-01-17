local M = {}
local a = vim.api

---@class GForgeIssueKeys
---Defines key binds for issue buffers.
---@field close string Key bind for closing the issue window/buffer.
---@field update string Key bind for updating the issue content.
---@field comment string Key bind to write a comment.
---@field title string Key bind to change the title.
---@field labels string Key bind to change the labels.
---@field assignees string Key bind to change the labels.
---@field description string Key bind to change the description.
---@field state string Key bind to change the state.

---@class GForgeGithub
---@field executable string Path to 'gh' cli executable.

---@class GForgeOptions
---Defines plugin options.
---@field timeout integer Milliseconds on how long to wait for command completion.
---@field issue_keys GForgeIssueKeys?
---@field github GForgeGithub?
---@field default_issue_provider string Module name that provides issue content by default.

---@param opts GForgeOptions
function M.setup(opts)
    ---@type GForgeOptions
    M.opts = opts or {}

    M.opts.timeout = opts.timeout or 3500

    local ik = opts.issue_keys or {}
    M.opts.issue_keys = ik
    M.opts.issue_keys.close = ik.close or "q"
    M.opts.issue_keys.update = ik.update or "<localleader>u"
    M.opts.issue_keys.comment = ik.comment or "<localleader>c"
    M.opts.issue_keys.title = ik.title or "<localleader>t"
    M.opts.issue_keys.labels = ik.labels or "<localleader>l"
    M.opts.issue_keys.assignees = ik.assignees or "<localleader>a"
    M.opts.issue_keys.description = ik.description or "<localleader>d"
    M.opts.issue_keys.state = ik.state or "<localleader>s"

    M.opts.github = opts.github or {}
    M.opts.github.executable = opts.github.executable or "gh"

    M.opts.default_issue_provider = opts.default_issue_provider or "gitforge.gh.issue"

    -- a.nvim_create_user_command("GH", M.handle_command, {})
    local provider = require(M.opts.default_issue_provider)
    local ia = require("gitforge.issue_actions")
    vim.keymap.set("n", "<leader>ql", function()
        ia.list_issues({
            -- project = "llvm/llvm-project",
            -- labels = "clang-tidy",
            limit = 50,
            -- assignee = "@me",
        }, provider)
    end)
    vim.keymap.set("n", "<leader>qc", function() ia.cached_issues_picker(provider) end)
    vim.keymap.set("n", "<leader>qn", function() ia.create_issue(provider) end)
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

return M
