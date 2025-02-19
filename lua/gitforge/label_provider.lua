---Provides the abstract interface to interact with project labels.
---Returns nil for everything.
---@class LabelProvider
---@field provider string Identity of the label provider. Should be the same as the issue provider.
---@field project string|nil
---@field cmd_list_labels function Retrieve list of available labels.
LabelProvider = {
    project = nil,
    provider = "unimplemented",
}

function LabelProvider.cmd_list_labels(limit)
    require("gitforge.log").notify_failure("'cmd_list_labels' not implemented")
    return nil
end

local M = {}

function M.get_from_cwd()
    local cwd = vim.uv.cwd()
    for _, config in ipairs(require("gitforge").opts.projects) do
        if vim.startswith(cwd, vim.fs.normalize(config.path)) then
            require("gitforge.log").trace_msg("Found a matching config: " .. config.path)
            local provider = require("gitforge." .. config.issue_provider .. ".label")
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
    local prov_mod = require("gitforge").opts.default_issue_provider
    return require("gitforge." .. prov_mod .. ".label")
end

return M
