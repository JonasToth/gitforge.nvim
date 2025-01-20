local M = {}

---@class Project
---@field path string Filesystem path used to check for a prefix-match on. Passed into `vim.fs.normalize()` before matching.
---@field issue_provider "gh"|"glab"
---@field project string? Identifier of the project. E.g. "JonasToth/gitforge.nvim"

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
---@field webview string Key bind to open the issue in a browser.

---@class GForgeGithub
---@field executable string Path to 'gh' cli executable.
---
---@class GForgeGitLab
---@field executable string Path to 'glab' cli executable.

---@class GForgeOptions
---Defines plugin options.
---@field projects Project[] List of individual project configurations.
---@field timeout integer Milliseconds on how long to wait for command completion.
---@field list_max_title_length integer Number of characters to cut issue-titles of in list views.
---@field issue_keys GForgeIssueKeys?
---@field github GForgeGithub?
---@field gitlab GForgeGitLab?
---@field default_issue_provider "gh"|"glab" Default provider if no project match is found

---@param opts GForgeOptions
function M.setup(opts)
    ---@type GForgeOptions
    M.opts = opts or {}

    M.opts.projects = opts.projects or {}
    M.opts.timeout = opts.timeout or 3500
    M.opts.list_max_title_length = opts.list_max_title_length or 60
    M.opts.default_issue_provider = opts.default_issue_provider or "gh"

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
    M.opts.issue_keys.webview = ik.webview or "<localleader>w"

    M.opts.github = opts.github or {}
    M.opts.github.executable = opts.github.executable or "gh"

    M.opts.gitlab = opts.gitlab or {}
    M.opts.gitlab.executable = opts.gitlab.executable or "glab"

    vim.api.nvim_create_user_command("GForgeViewIssue", M.view_issue, {})
    vim.api.nvim_create_user_command("GForgeListIssues", M.list_issues, {})
    vim.api.nvim_create_user_command("GForgeOpenedIssues", M.list_opened_issues, {})
    vim.api.nvim_create_user_command("GForgeCreateIssue", M.create_issue, {})
end

function M.view_issue(args)
    local ia = require("gitforge.issue_actions")
    local log = require("gitforge.log")
    if #args.args == 0 then
        vim.ui.input({ prompt = "Enter Issue Number", }, function(input)
            if input == nil then
                log.ephemeral_info("Aborted input")
                return
            end
            log.ephemeral_info("Showing issue " .. input)
            local provider = require("gitforge.issue_provider").get_from_cwd_or_default():newIssue(input)
            ia.view_issue(provider)
        end)
    else
        log.ephemeral_info("Showing issue " .. args.args)
        local provider = require("gitforge.issue_provider").get_from_cwd_or_default():newIssue(args.args)
        ia.view_issue(provider)
    end
end

function M.list_issues(args)
    local provider = require("gitforge.issue_provider").get_from_cwd_or_default()
    require("gitforge.issue_actions").list_issues({}, provider)
end

function M.list_opened_issues(args)
    local provider = require("gitforge.issue_provider").get_from_cwd_or_default()
    require("gitforge.issue_actions").list_opened_issues(provider)
end

function M.create_issue(args)
    local provider = require("gitforge.issue_provider").get_from_cwd_or_default()
    require("gitforge.issue_actions").create_issue(provider)
end

return M
