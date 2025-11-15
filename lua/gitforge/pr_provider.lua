---Provides the abstract interface to interact with project pull requests.
---The cmd_* methods return the CLI call for the underlying tool, but don't execute it.
---Returns @c nil for everything
---@class PRProvider
---@field provider string Identity of the pr provider. By default, the same as the issue provider, but can differ (e.g. jira for issue, gitlab for PRs)
---@field project string|nil
---@field cmd_list_prs function Retrieve the list of pull requests according to some filtering rules. By default only open pull request not in draft mode.
PRProvider = {
    project = nil,
    provider = "unimplemented",
}

function PRProvider.cmd_list_prs()
    return nil
end

local M = {}

function M.get_from_cwd()
    local cwd = vim.uv.cwd()
    for _, config in ipairs(require("gitforge").opts.projects) do
        if vim.startswith(cwd, vim.fs.normalize(config.path)) then
            require("gitforge.log").trace_msg("Found a matching config: " .. config.path)
            local provider = require("gitforge." .. config.pr_provider .. ".pr")
            provider.project = config.project
            return provider
        end
    end
    return nil
end

function M.get_from_cwd_or_default()
    return M.get_from_cwd() or M.get_default_provider()
end

function M.get_default_provider()
    local prov_mod = require("gitforge").opts.default_pr_provider
    return require("gitforge." .. prov_mod .. ".pr")
end

return M
