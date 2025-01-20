---Provides executable calls to manipulate and view issues on Github.
---@class GLabIssue:IssueProvider
---@field new function
---@field newIssue function
---@field buf integer Buffer-ID of the issue.
---@field issue_number string|nil Issue-ID of the issue.
---@field project string|nil Project-ID of the issue.
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
---@field handle_create_issue_output_to_view_issue function
local GLabIssue = {}

require("gitforge.issue_provider")
setmetatable(GLabIssue, { __index = IssueProvider })

function GLabIssue:new(buf)
    local s = setmetatable({}, { __index = GLabIssue })
    s.buf = buf
    s.project, s.issue_number = require("gitforge.generic_issue").get_issue_proj_and_id_from_buf(buf)
    return s
end

function GLabIssue:newIssue(issue_number, project)
    local s = setmetatable({}, { __index = GLabIssue })
    s.buf = 0
    s.issue_number = issue_number
    s.project = project
    return s
end

---@param url string
---@return string|nil project
---@return string|nil issue_number
local parse_gitlab_url = function(url)
    local log = require("gitforge.log")

    local url_elements = vim.split(url, "/")

    if #url_elements ~= 8 then
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

    local id = url_elements[8]
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
---@return GLabIssue|nil
function GLabIssue:newFromLink(issue_link)
    local project, issue_number = parse_gitlab_url(issue_link)
    if project == nil or issue_number == nil then
        return nil
    end
    return self:newIssue(issue_number, project)
end

function GLabIssue:cmd()
    return require("gitforge").opts.gitlab.executable
end

function GLabIssue:issue_cmd()
    local c = { self:cmd(), "issue", }
    if self.project then
        table.insert(c, "--repo")
        table.insert(c, self.project)
    end
    return c
end

function GLabIssue:edit_cmd()
    local c = self:issue_cmd()
    table.insert(c, "update")
    table.insert(c, self.issue_number)
    return c
end

function GLabIssue:cmd_fetch()
    local cmd = self:issue_cmd()
    table.insert(cmd, { "view", "--output", "json", "--comments", self.issue_number, })
    return vim.iter(cmd):flatten(math.huge):totable()
end

---@param added_labels Set
---@param removed_labels Set
function GLabIssue:cmd_label_change(added_labels, removed_labels)
    local cmd = self:edit_cmd()

    if not added_labels:empty() then
        table.insert(cmd, "--label")
        table.insert(cmd, added_labels:toCSV())
    end
    if not removed_labels:empty() then
        table.insert(cmd, "--unlabel")
        table.insert(cmd, removed_labels:toCSV())
    end

    return cmd
end

---@param new Set
---@param added_assignees Set unused
---@param removed_assignees Set unused
function GLabIssue:cmd_assignee_change(new, added_assignees, removed_assignees)
    local cmd = self:edit_cmd()
    if #new == 0 then
        table.insert(cmd, "--unassign")
    else
        table.insert(cmd, "--assignee")
        table.insert(cmd, new:toCSV())
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
    local new_desc = require("gitforge.utility").read_file_to_string(new_desc_file)
    if #new_desc == 0 then
        new_desc = " "
    end
    table.insert(cmd, "--description")
    table.insert(cmd, new_desc)
    return cmd
end

---@param current_state string Current state of the issue.
---@return table|nil possible_state A list of possible new states.
function GLabIssue:next_possible_states(current_state)
    if current_state == "opened" then
        return { "closed", current_state }
    else
        return { "reopen", current_state }
    end
end

---@param new_state string
---@return table|nil Command
function GLabIssue:cmd_state_change(new_state)
    local cmd = self:issue_cmd()
    if new_state == "closed" then
        table.insert(cmd, "close")
        table.insert(cmd, self.issue_number)
    elseif new_state == "reopen" then
        table.insert(cmd, "reopen")
        table.insert(cmd, self.issue_number)
    else
        return nil
    end
    return cmd
end

---@param comment_file string Path to temporary file to comment on
function GLabIssue:cmd_comment(comment_file)
    return vim.iter({
        self:issue_cmd(), "note", self.issue_number, "--message",
        require("gitforge.utility").read_file_to_string(comment_file)
    }):flatten(math.huge):totable()
end

---@param title string Title of new issue, must not be empty.
---@param description_file string Path to temporary description file.
function GLabIssue:cmd_create_issue(title, description_file)
    local desc_str = require("gitforge.utility").read_file_to_string(description_file)
    return vim.iter({
        self:issue_cmd(), "create", "--title", title, "--description", desc_str, "--yes"
    }):flatten(math.huge):totable()
end

---@param output string Output of the 'create_issue' command exection. Tries to extract
---                     the issue id and return a provider for that issue.
---@return GLabIssue|nil issue If the issue can be identified, returns a provider to work on that issue.
function GLabIssue:handle_create_issue_output_to_view_issue(output)
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
    return GLabIssue:newFromLink(issue_link)
end

---@param opts IssueListOpts
---@return table command
function GLabIssue:cmd_list_issues(opts)
    local cmd = { self:issue_cmd(), "list", "--output", "json" }
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
    return vim.iter(cmd):flatten(math.huge):totable()
end

---@return table command
function GLabIssue:cmd_view_web()
    return vim.iter({ self:issue_cmd(), "issue", "view", "--web", self.issue_number }):flatten(math.huge):totable()
end

---@return Author
local conv_glab_author = function(glab_author)
    return {
        login = glab_author.username,
        name = glab_author.name,
    }
end

---@return Author[]
local conv_glab_authors = function(glab_authors)
    local result = {}
    for _, a in pairs(glab_authors) do
        table.insert(result, conv_glab_author(a))
    end
    return result
end

---@return Label
local conv_glab_label = function(glab_label)
    return {
        name = glab_label,
    }
end

---@return Label[]
local conv_glab_labels = function(glab_labels)
    local result = {}
    for _, l in pairs(glab_labels) do
        table.insert(result, conv_glab_label(l))
    end
    return result
end

---@return Comment
local conv_glab_comment = function(glab_comment)
    return {
        author = conv_glab_author(glab_comment.author),
        createdAt = glab_comment.created_at,
        body = glab_comment.body,
    }
end

---@return Comment[]
local conv_glab_comments = function(glab_comments)
    local result = {}
    for _, c in pairs(glab_comments) do
        if not c.system then
            table.insert(result, conv_glab_comment(c))
        end
    end
    return result
end

---@return Issue
local conv_glab_issue = function(glab_issue)
    local has_comments = glab_issue.Notes ~= vim.NIL and glab_issue.Notes ~= nil
    local has_closed_at = glab_issue.closed_at ~= vim.NIL
    local project, _ = parse_gitlab_url(glab_issue.web_url)
    return {
        body = glab_issue.description,
        title = glab_issue.title,
        author = conv_glab_author(glab_issue.author),
        number = glab_issue.iid,
        project = project,
        createdAt = glab_issue.created_at,
        closed = has_closed_at,
        closedAt = has_closed_at and glab_issue.closed_at or nil,
        state = glab_issue.state,
        assignees = conv_glab_authors(glab_issue.assignees),
        labels = conv_glab_labels(glab_issue.labels),
        comments = has_comments and conv_glab_comments(glab_issue.Notes) or nil,
        url = glab_issue.web_url,
    }
end

---@return Issue[]
local conv_glab_issues = function(glab_issues)
    local result = {}
    for _, i in pairs(glab_issues) do
        table.insert(result, conv_glab_issue(i))
    end
    return result
end

---@param json_input string JSON encoded result of a command execution.
---@return Issue issue Transformed JSON to the expected interface of an issue.
function GLabIssue:convert_cmd_result_to_issue(json_input)
    return conv_glab_issue(vim.fn.json_decode(json_input))
end

---@param json_input string JSON encoded result of a command execution.
---@return Issue[] issue Transformed JSON to the expected interface of an issue.
function GLabIssue:convert_cmd_result_to_issue_list(json_input)
    return conv_glab_issues(vim.fn.json_decode(json_input))
end

return GLabIssue
