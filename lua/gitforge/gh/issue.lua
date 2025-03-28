---@class GHIssue:IssueProvider
---@field provider "gh"
---@field new function
---@field newIssue function
---@field buf integer Buffer-ID of the issue.
---@field issue_number string|nil Issue-ID of the issue.
---@field project string|nil Project-Id of the issue
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
local GHIssue = {
    provider = "gh"
}

require("gitforge.issue_provider")
setmetatable(GHIssue, { __index = IssueProvider })

function GHIssue:new(buf)
    local s = setmetatable({}, { __index = GHIssue })
    s.buf = buf
    s.project, s.issue_number = require("gitforge.generic_issue").get_issue_proj_and_id_from_buf(buf)
    return s
end

function GHIssue:newIssue(issue_number, project)
    local s = setmetatable({}, { __index = GHIssue })
    s.buf = 0
    s.issue_number = issue_number
    s.project = project
    return s
end

---@param url string
---@return string|nil project
---@return string|nil issue_number
local parse_github_url = function(url)
    local log = require("gitforge.log")

    local url_elements = vim.split(url, "/")

    if #url_elements ~= 7 then
        log.notify_failure("Splitting url did not return the expected number of elements.")
        log.trace_msg(vim.inspect(url_elements))
        return nil, nil
    end

    local host = url_elements[3]
    if host == nil or #host == 0 then
        log.notify_failure("Failed to extract the gitforge host")
        log.trace_msg(vim.inspect(host))
        return nil, nil
    end
    local orga = url_elements[4]
    if orga == nil or #orga == 0 then
        log.notify_failure("Failed to extract the organization")
        log.trace_msg(vim.inspect(orga))
        return nil, nil
    end

    local repo = url_elements[5]
    if repo == nil or #repo == 0 then
        log.notify_failure("Failed to extract the repository")
        log.trace_msg(vim.inspect(repo))
        return nil, nil
    end

    local project = host .. "/" .. orga .. "/" .. repo

    local id = url_elements[7]
    if id == nil or #id == 0 then
        log.notify_failure("Failed to extract issue id from URL")
        log.trace_msg(vim.join(url_elements, " : "))
        return nil, nil
    end
    local int_id = tonumber(id)
    if int_id == nil then
        log.notify_failure("Failed to parse id-string as int")
        log.trace_msg(id)
        return nil, nil
    end
    return project, tostring(int_id)
end

---@param issue_link string URL to the issue
---@return GHIssue|nil
function GHIssue:newFromLink(issue_link)
    local project, issue_number = parse_github_url(issue_link)
    if project == nil or issue_number == nil then
        return nil
    end
    return self:newIssue(issue_number, project)
end

function GHIssue:cmd()
    return require("gitforge").opts.github.executable
end

function GHIssue:issue_cmd()
    local c = { self:cmd(), "issue", }
    if self.project then
        table.insert(c, "--repo")
        table.insert(c, self.project)
    end
    return c
end

function GHIssue:edit_cmd()
    local c = self:issue_cmd()
    table.insert(c, "edit")
    table.insert(c, self.issue_number)
    return c
end

function GHIssue:cmd_fetch()
    local required_fields =
    "title,body,createdAt,author,comments,assignees,labels,number,state,milestone,closed,closedAt,url"
    local gh_call = self:issue_cmd()
    table.insert(gh_call, { "view", self.issue_number, "--json", required_fields })
    return vim.iter(gh_call):flatten(math.huge):totable()
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

---@param new Set unused
---@param added_assignees Set
---@param removed_assignees Set
function GHIssue:cmd_assignee_change(new, added_assignees, removed_assignees)
    local gh_call = self:edit_cmd()

    if not removed_assignees:empty() then
        table.insert(gh_call, "--remove-assignee")
        table.insert(gh_call, removed_assignees:toCSV())
    end

    if not added_assignees:empty() then
        table.insert(gh_call, "--add-assignee")
        table.insert(gh_call, added_assignees:toCSV())
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

---@param current_state string Current state of the issue.
---@return table|nil possible_state A list of possible new states.
function GHIssue:next_possible_states(current_state)
    if current_state == "OPEN" then
        return { "CLOSED completed", "CLOSED not planned", current_state }
    else
        return { "REOPEN", current_state }
    end
end

---@param new_state string
---@return table|nil Command
function GHIssue:cmd_state_change(new_state)
    local gh_call = self:issue_cmd()
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
    local c = self:issue_cmd()
    table.insert(c, { "comment", self.issue_number, "--body-file", comment_file })
    return vim.iter(c):flatten(math.huge):totable()
end

---@param title string Title of new issue, must not be empty.
---@param description_file string Path to temporary description file.
function GHIssue:cmd_create_issue(title, description_file)
    local c = self:issue_cmd()
    table.insert(c, { "create", "--title", title, "--body-file", description_file })
    return vim.iter(c):flatten(math.huge):totable()
end

---@param output string Output of the 'create_issue' command exection. Tries to extract
---                     the issue id and return a provider for that issue.
---@return GHIssue|nil issue If the issue can be identified, returns a provider to work on that issue.
function GHIssue:handle_create_issue_output_to_view_issue(output)
    local log = require("gitforge.log")

    local lines = vim.split(output, "\n")
    local issue_link
    for index, value in ipairs(lines) do
        if index == 1 then
            issue_link = value
            break
        end
    end
    if issue_link == nil or #issue_link == 0 then
        log.notify_failure("Failed to retrieve issue link for new issue")
        log.trace_msg(vim.join(lines, "\n"))
        return nil
    end
    log.notify_change("Created a new issue")
    return GHIssue:newFromLink(issue_link)
end

---@param opts IssueListOpts
---@return table command
function GHIssue:cmd_list_issues(opts)
    local required_fields =
    "title,labels,number,state,milestone,createdAt,updatedAt,body,author,assignees,url"
    local gh_call = { self:issue_cmd(), "list", "--state", "all", "--json", required_fields }
    if opts.state then
        table.insert(gh_call, "--state")
        table.insert(gh_call, opts.state)
    end
    if opts.project then
        table.insert(gh_call, "--repo")
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
    return vim.iter(gh_call):flatten(math.huge):totable()
end

---@return table command
function GHIssue:cmd_view_web()
    return vim.iter({ self:issue_cmd(), "view", "--web", self.issue_number }):flatten(math.huge):totable()
end

function GHIssue:new_label_provider_from_self()
    return require("gitforge.gh.label"):new(self.project)
end

---@param json_input string JSON encoded result of a command execution.
---@return Issue issue Transformed JSON to the expected interface of an issue.
function GHIssue:convert_cmd_result_to_issue(json_input)
    local issue = vim.fn.json_decode(json_input)
    local project, _ = parse_github_url(issue.url)
    issue.project = project
    return issue
end

---@param json_input string JSON encoded result of a command execution.
---@return Issue[] issue Transformed JSON to the expected interface of an issue.
function GHIssue:convert_cmd_result_to_issue_list(json_input)
    local issue_list = vim.fn.json_decode(json_input)
    local result = {}
    for _, i in pairs(issue_list) do
        local project, _ = parse_github_url(i.url)
        local issue = vim.deepcopy(i)
        issue.project = project
        table.insert(result, issue)
    end
    return result
end

return GHIssue
