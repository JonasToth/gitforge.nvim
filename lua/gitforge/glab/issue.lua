---Provides executable calls to manipulate and view issues on Github.
---@class GLabIssue
---@field new function
---@field newIssue function
---@field buf integer Buffer-ID of the issue.
---@field issue_number string|nil Issue-ID of the issue.
---@field cmd_fetch function
---@field cmd_label_change function
---@field cmd_assignee_change function
---@field cmd_description_change function
---@field cmd_state_change function
---@field cmd_comment function
---@field cmd_create_issue function
---@field cmd_list_issues function
---@field cmd_view_web function
---@field next_possible_states function Compute next possible issue states from current state.
---@field convert_cmd_result_to_issue function
---@field handle_create_issue_output_to_view_issue function
local GLabIssue = {}

function GLabIssue:new(buf)
    local s = setmetatable({}, { __index = GLabIssue })
    s.buf = buf
    s.issue_number = require("gitforge.generic_issue").get_issue_id_from_buf(buf)
    return s
end

function GLabIssue:newIssue(issue_number)
    local s = setmetatable({}, { __index = GLabIssue })
    s.buf = 0
    s.issue_number = issue_number
    return s
end

---@param issue_link string URL to the issue
---@return GHIssue|nil
function GLabIssue:newFromLink(issue_link)
    local log = require("gitforge.log")

    local url_elements = vim.split(issue_link, "/")
    local id
    for index, value in ipairs(url_elements) do
        if index == 7 then
            id = value
            break
        end
    end
    if id == nil or #id == 0 then
        log.notify_failure("Failed to extract issue id from URL")
        log.trace_msg(vim.join(url_elements, " : "))
        return nil
    end
    local int_id = tonumber(id)
    if int_id == nil then
        log.notify_failure("Failed to parse id-string as int")
        log.trace_msg(id)
        return nil
    end
    return self:newIssue(tostring(int_id))
end

function GLabIssue:cmd()
    return require("gitforge").opts.gitlab.executable
end

function GLabIssue:edit_cmd()
    return { self:cmd(), "issue", "edit", self.issue_number }
end

function GLabIssue:cmd_fetch()
    local required_fields =
    "title,body,createdAt,author,comments,assignees,labels,number,state,milestone,closed,closedAt"
    local cmd = { self:cmd(), "issue", "view", self.issue_number, "--json", required_fields }
    -- if opts.project then
    --     table.insert(cmd, "-R")
    --     table.insert(cmd, opts.project)
    -- end
    return cmd
end

---@param new_labels Set
---@param removed_labels Set
function GLabIssue:cmd_label_change(new_labels, removed_labels)
    local cmd = self:edit_cmd()

    if not removed_labels:empty() then
        table.insert(cmd, "--remove-label")
        table.insert(cmd, removed_labels:toCSV())
    end

    if not new_labels:empty() then
        table.insert(cmd, "--add-label")
        table.insert(cmd, new_labels:toCSV())
    end
    return cmd
end

---@param new_assignees Set
---@param removed_assignees Set
function GLabIssue:cmd_assignee_change(new_assignees, removed_assignees)
    local cmd = self:edit_cmd()

    if not removed_assignees:empty() then
        table.insert(cmd, "--remove-assignee")
        table.insert(cmd, removed_assignees:toCSV())
    end

    if not new_assignees:empty() then
        table.insert(cmd, "--add-assignee")
        table.insert(cmd, new_assignees:toCSV())
    end
    return cmd
end

---@param new_title string Non-empty string to change the title to.
function GLabIssue:cmd_title_change(new_title)
    local cmd = self:edit_cmd()
    table.insert(cmd, "--title")
    table.insert(cmd, new_title)
    return cmd
end

---@param new_desc_file string File-path to temporary file containing the new description.
function GLabIssue:cmd_description_change(new_desc_file)
    local cmd = self:edit_cmd()
    table.insert(cmd, "--body-file")
    table.insert(cmd, new_desc_file)
    return cmd
end

---@param new_state string
---@return table|nil Command
function GLabIssue:cmd_state_change(new_state)
    local cmd = { self:cmd(), "issue", }
    if new_state == "CLOSED completed" then
        table.insert(cmd, "close")
        table.insert(cmd, self.issue_number)
        table.insert(cmd, "--reason")
        table.insert(cmd, "completed")
    elseif new_state == "CLOSED not planned" then
        table.insert(cmd, "close")
        table.insert(cmd, self.issue_number)
        table.insert(cmd, "--reason")
        table.insert(cmd, "not planned")
    elseif new_state == "REOPEN" then
        table.insert(cmd, "reopen")
        table.insert(cmd, self.issue_number)
    else
        return nil
    end
    return cmd
end

---@param comment_file string Path to temporary file to comment on
function GLabIssue:cmd_comment(comment_file)
    return { self:cmd(), "issue", "comment", self.issue_number, "--body-file", comment_file }
end

---@param title string Title of new issue, must not be empty.
---@param description_file string Path to temporary description file.
function GLabIssue:cmd_create_issue(title, description_file)
    local desc_str = require("gitforge.utility").read_file_to_string(description_file)
    return { self:cmd(), "issue", "create", "--title", title, "--description", desc_str, "--yes" }
end

---@param output string Output of the 'create_issue' command exection. Tries to extract
---                     the issue id and return a provider for that issue.
---@return GHIssue|nil issue If the issue can be identified, returns a provider to work on that issue.
function GLabIssue:handle_create_issue_output_to_view_issue(output)
    return nil
end

---@param opts IssueListOpts
---@return table command
function GLabIssue:cmd_list_issues(opts)
    local required_fields =
    "title,labels,number,state,milestone,createdAt,updatedAt,body,author,assignees"
    local cmd = { self:cmd(), "issue", "list", "--output", "json" }
    if opts.state == "open" then
        -- thats the default
    elseif opts.state == "closed" then
        table.insert(cmd, "--closed")
    elseif opts.state == "all" then
        table.insert(cmd, "--all")
    end
    if opts.project then
        table.insert(cmd, "-R")
        table.insert(cmd, opts.project)
    end
    if opts.limit then
        table.insert(cmd, "--per-page")
        table.insert(cmd, tostring(opts.limit))
    end
    if opts.labels then
        table.insert(cmd, "--label")
        table.insert(cmd, opts.labels)
    end
    if opts.assignee then
        table.insert(cmd, "--assignee")
        table.insert(cmd, opts.assignee)
    end
    return cmd
end

---@return table command
function GLabIssue:cmd_view_web()
    return { self:cmd(), "issue", "view", "--web", self.issue_number }
end

---@param current_state string Current state of the issue.
---@return table|nil possible_state A list of possible new states.
function GLabIssue:next_possible_states(current_state)
    if current_state == "OPEN" then
        return { "CLOSED completed", "CLOSED not planned", current_state }
    else
        return { "REOPEN", current_state }
    end
end

---@param json_input string JSON encoded result of a command execution.
---@return GHIssue issue Transformed JSON to the expected interface of an issue.
function GLabIssue:convert_cmd_result_to_issue(json_input)
    return vim.fn.json_decode(json_input)
end

return GLabIssue
