---Provides executable calls to manipulate and view issues on Github.
---@class GHIssue
---@field buf integer Buffer-ID of the issue.
---@field issue_number string|nil Issue-ID of the issue.
---@field cmd_fetch function
---@field cmd_label_change function
---@field cmd_assignee_change function
---@field cmd_description_change function
---@field cmd_state_change function
---@field cmd_comment function
---@field next_possible_states function Compute next possible issue states from current state.
---@field convert_cmd_result_to_issue function
local GHIssue = {}

function GHIssue:new(buf)
    local s = setmetatable({}, { __index = GHIssue })
    s.buf = buf
    s.issue_number = require("gitforge.generic_issue").get_issue_id_from_buf(buf)
    return s
end

function GHIssue:newIssue(issue_number)
    local s = setmetatable({}, { __index = GHIssue })
    s.buf = 0
    s.issue_number = issue_number
    return s
end

function GHIssue:edit_cmd()
    return { "gh", "issue", "edit", self.issue_number }
end

function GHIssue:cmd_fetch()
    local required_fields =
    "title,body,createdAt,author,comments,assignees,labels,number,state,milestone,closed,closedAt"
    print(vim.inspect(self))
    local gh_call = { "gh", "issue", "view", self.issue_number, "--json", required_fields }
    -- if opts.project then
    --     table.insert(gh_call, "-R")
    --     table.insert(gh_call, opts.project)
    -- end
    return gh_call
end

---@param new_labels Set
---@param removed_labels Set
function GHIssue:cmd_label_change(new_labels, removed_labels)
    local gh_call = self:edit_cmd()

    if not removed_labels:empty() then
        table.insert(gh_call, "--remove-label")
        table.insert(gh_call, removed_labels:toCSV())
    end

    if not new_labels:empty() then
        table.insert(gh_call, "--add-label")
        table.insert(gh_call, new_labels:toCSV())
    end
    return gh_call
end

---@param new_assignees Set
---@param removed_assignees Set
function GHIssue:cmd_assignee_change(new_assignees, removed_assignees)
    local gh_call = self:edit_cmd()

    if not removed_assignees:empty() then
        table.insert(gh_call, "--remove-assignee")
        table.insert(gh_call, removed_assignees:toCSV())
    end

    if not new_assignees:empty() then
        table.insert(gh_call, "--add-assignee")
        table.insert(gh_call, new_assignees:toCSV())
    end
    return gh_call
end

---@param new_title string Non-empty string to change the title to.
function GHIssue:cmd_title_change(new_title)
    local gh_call = self:edit_cmd()
    table.insert(gh_call, "--title")
    table.insert(gh_call, new_title)
    return gh_call
end

---@param new_desc_file string File-path to temporary file containing the new description.
function GHIssue:cmd_description_change(new_desc_file)
    local gh_call = self:edit_cmd()
    table.insert(gh_call, "--body-file")
    table.insert(gh_call, new_desc_file)
    return gh_call
end

---@param new_state string
---@return table|nil Command
function GHIssue:cmd_state_change(new_state)
    local gh_call = { "gh", "issue", }
    if new_state == "CLOSED completed" then
        table.insert(gh_call, "close")
        table.insert(gh_call, self.issue_number)
        table.insert(gh_call, "--reason")
        table.insert(gh_call, "completed")
    elseif new_state == "CLOSED not planned" then
        table.insert(gh_call, "close")
        table.insert(gh_call, self.issue_number)
        table.insert(gh_call, "--reason")
        table.insert(gh_call, "not planned")
    elseif new_state == "REOPEN" then
        table.insert(gh_call, "reopen")
        table.insert(gh_call, self.issue_number)
    else
        return nil
    end
    return gh_call
end

---@param comment_file string Path to temporary file to comment on
function GHIssue:cmd_comment(comment_file)
    return { "gh", "issue", "comment", self.issue_number, "--body-file", comment_file }
end

---@param current_state string Current state of the issue.
---@return table|nil possible_state A list of possible new states.
function GHIssue:next_possible_states(current_state)
    if current_state == "OPEN" then
        return { "CLOSED completed", "CLOSED not planned", current_state }
    else
        return { "REOPEN", current_state }
    end
end

---@param json_input string JSON encoded result of a command execution.
---@return GHIssue issue Transformed JSON to the expected interface of an issue.
function GHIssue:convert_cmd_result_to_issue(json_input)
    return vim.fn.json_decode(json_input)
end

return GHIssue
