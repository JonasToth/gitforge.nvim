---Provides the abstract interface that must be implemented by issue providers.
---Returns nil for everything.
---@class IssueProvider
---@field buf integer Buffer-ID of the issue.
---@field issue_number string|nil Issue-ID of the issue.
---@field project string | nil Project Identifier
---@field new function Create a new issue for a buffer.
---@field newIssue function Create an issue from the issue number.
---@field newFromLink function Parse a web link and return an issue provider object.
---@field cmd_fetch function
---@field cmd_label_change function
---@field cmd_assignee_change function
---@field cmd_description_change function
---@field next_possible_states function Compute next possible issue states from current state.
---@field cmd_state_change function
---@field cmd_comment function
---@field cmd_create_issue function
---@field cmd_list_issues function
---@field cmd_view_web function
---@field convert_cmd_result_to_issue function
---@field convert_cmd_result_to_issue_list function
---@field handle_create_issue_output_to_view_issue function
IssueProvider = {
    buf = -1,
    issue_number = nil,
    project = nil,
}

function IssueProvider.new()
    require("gitforge.log").notify_failure("'new' not implemented")
    return nil
end

function IssueProvider.newIssue()
    require("gitforge.log").notify_failure("'newIssue' not implemented")
    return nil
end

function IssueProvider.newFromLink()
    require("gitforge.log").notify_failure("'newFromLink' not implemented")
    return nil
end

function IssueProvider.cmd_fetch()
    require("gitforge.log").notify_failure("'cmd_fetch' not implemented")
    return nil
end

function IssueProvider.cmd_label_change()
    require("gitforge.log").notify_failure("'cmd_label_change' not implemented")
    return nil
end

function IssueProvider.cmd_assignee_change()
    require("gitforge.log").notify_failure("'cmd_assignee_change' not implemented")
    return nil
end

function IssueProvider.cmd_description_change()
    require("gitforge.log").notify_failure("'cmd_description_change' not implemented")
    return nil
end

function IssueProvider.next_possible_states()
    require("gitforge.log").notify_failure("'next_possible_states' not implemented")
    return nil
end

function IssueProvider.cmd_state_change()
    require("gitforge.log").notify_failure("'cmd_state_change' not implemented")
    return nil
end

function IssueProvider.cmd_comment()
    require("gitforge.log").notify_failure("'cmd_comment' not implemented")
    return nil
end

function IssueProvider.cmd_create_issue()
    require("gitforge.log").notify_failure("'cmd_create_issue' not implemented")
    return nil
end

function IssueProvider.cmd_list_issues()
    require("gitforge.log").notify_failure("'cmd_list_issues' not implemented")
    return nil
end

function IssueProvider.cmd_view_web()
    require("gitforge.log").notify_failure("'cmd_view_web' not implemented")
    return nil
end

function IssueProvider.convert_cmd_result_to_issue()
    require("gitforge.log").notify_failure("'convert_cmd_result_to_issue' not implemented")
    return nil
end

function IssueProvider.convert_cmd_result_to_issue_list()
    require("gitforge.log").notify_failure("'convert_cmd_result_to_issue_list' not implemented")
    return nil
end

function IssueProvider.handle_create_issue_output_to_view_issue()
    require("gitforge.log").notify_failure("'handle_create_issue_output_to_view_issue' not implemented")
    return nil
end

local M = {}

function M.get_from_cwd()
    local cwd = vim.uv.cwd()
    for _, config in ipairs(require("gitforge").opts.projects) do
        if vim.startswith(cwd, vim.fs.normalize(config.path)) then
            require("gitforge.log").trace_msg("Found a matching config: " .. config.path)
            local provider = require("gitforge." .. config.issue_provider .. ".issue")
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
    return require("gitforge." .. prov_mod .. ".issue")
end

return M
