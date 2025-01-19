---Provides the abstract interface that must be implemented by issue providers.
---Returns nil for everything.
---@class IssueProvider
---@field buf integer Buffer-ID of the issue.
---@field issue_number string|nil Issue-ID of the issue.
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
}

function IssueProvider.new() return nil end

function IssueProvider.newIssue() return nil end

function IssueProvider.newFromLink() return nil end

function IssueProvider.cmd_fetch() return nil end

function IssueProvider.cmd_label_change() return nil end

function IssueProvider.cmd_assignee_change() return nil end

function IssueProvider.cmd_description_change() return nil end

function IssueProvider.next_possible_states() return nil end

function IssueProvider.cmd_state_change() return nil end

function IssueProvider.cmd_comment() return nil end

function IssueProvider.cmd_create_issue() return nil end

function IssueProvider.cmd_list_issues() return nil end

function IssueProvider.cmd_view_web() return nil end

function IssueProvider.convert_cmd_result_to_issue() return nil end

function IssueProvider.convert_cmd_result_to_issue_list() return nil end

function IssueProvider.handle_create_issue_output_to_view_issue() return nil end

local M = {}

function M.get_default_provider()
    return require(require("gitforge").opts.default_issue_provider)
end

return M
