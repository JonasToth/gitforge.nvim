---@class GiteaIssue:IssueProvider
---@field provider "tea"
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
local GiteaIssue = {
    provider = "tea"
}

require("gitforge.issue_provider")
setmetatable(GiteaIssue, { __index = IssueProvider })

function GiteaIssue:new(buf)
    local s = setmetatable({}, { __index = GiteaIssue })
    s.buf = buf
    s.project, s.issue_number = require("gitforge.generic_issue").get_issue_proj_and_id_from_buf(buf)
    return s
end

function GiteaIssue:newIssue(issue_number, project)
    local s = setmetatable({}, { __index = GiteaIssue })
    s.buf = 0
    s.issue_number = issue_number
    s.project = project
    return s
end

---@param url string
---@return string|nil project
---@return string|nil issue_number
local parse_gitea_url = function(url)
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

    --NOTE: Only the organisation and repository are used to identify the project.
    --      This is due to errornous behavior with specific 'tea' commands.
    local project = orga .. "/" .. repo

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
---@return GiteaIssue|nil
function GiteaIssue:newFromLink(issue_link)
    local project, issue_number = parse_gitea_url(issue_link)
    if project == nil or issue_number == nil then
        return nil
    end
    return self:newIssue(issue_number, project)
end

function GiteaIssue:cmd()
    return require("gitforge").opts.gitea.executable
end

function GiteaIssue:issue_cmd()
    local c = { self:cmd(), "issue", }
    if self.project then
        table.insert(c, "--repo")
        table.insert(c, self.project)
    end
    return c
end

function GiteaIssue:edit_cmd()
    local c = self:issue_cmd()
    table.insert(c, "edit")
    table.insert(c, self.issue_number)
    return c
end

function GiteaIssue:cmd_fetch()
    local call = self:issue_cmd()
    local fields =
    "title,labels,index,state,milestone,created,updated,body,author,assignees,url"
    table.insert(call, {
        self.issue_number,
        "--output", "json",
        "--fields", fields,
        "--comments"
    })
    return vim.iter(call):flatten(math.huge):totable()
end

---@param new_labels Set
---@param removed_labels Set
function GiteaIssue:cmd_label_change(new_labels, removed_labels)
    local call = self:edit_cmd()

    if not removed_labels:empty() then
        table.insert(call, "--remove-labels")
        table.insert(call, removed_labels:toCSV())
    end

    if not new_labels:empty() then
        table.insert(call, "--add-labels")
        table.insert(call, new_labels:toCSV())
    end
    return call
end

---It is not possible to remove the assignees completely due to a limitation in 'tea'.
---@param new Set new set of assignees of that issue.
---@param added_assignees Set unused
---@param removed_assignees Set unused
function GiteaIssue:cmd_assignee_change(new, added_assignees, removed_assignees)
    local call = self:edit_cmd()
    table.insert(call, "--add-assignees")
    table.insert(call, new:toCSV())
    return call
end

---@param new_title string Non-empty string to change the title to.
function GiteaIssue:cmd_title_change(new_title)
    local call = self:edit_cmd()
    table.insert(call, "--title")
    table.insert(call, new_title)
    return call
end

---@param new_desc_file string File-path to temporary file containing the new description.
function GiteaIssue:cmd_description_change(new_desc_file)
    local call = self:edit_cmd()
    table.insert(call, "--description")
    table.insert(call, require("gitforge.utility").read_file_to_string(new_desc_file))
    return call
end

---@param current_state string Current state of the issue.
---@return table|nil possible_state A list of possible new states.
function GiteaIssue:next_possible_states(current_state)
    if current_state == "open" then
        return { "closed", current_state }
    else
        return { "open", current_state }
    end
end

---@param new_state string
---@return table|nil Command
function GiteaIssue:cmd_state_change(new_state)
    local call = self:issue_cmd()
    if new_state == "closed" then
        table.insert(call, "close")
        table.insert(call, self.issue_number)
    elseif new_state == "open" then
        table.insert(call, "open")
        table.insert(call, self.issue_number)
    else
        return nil
    end
    return call
end

---@param comment_file string Path to temporary file to comment on
function GiteaIssue:cmd_comment(comment_file)
    local c = { self:cmd(), "comment" }
    --NOTE: If the '--repo' argument contains a hostname, the 'tea comment' command fails.
    if self.project then
        table.insert(c, "--repo")
        table.insert(c, self.project)
    end
    table.insert(c, {
        self.issue_number,
        require("gitforge.utility").read_file_to_string(comment_file)
    })
    return vim.iter(c):flatten(math.huge):totable()
end

---@param title string Title of new issue, must not be empty.
---@param description_file string Path to temporary description file.
function GiteaIssue:cmd_create_issue(title, description_file)
    local c = self:issue_cmd()
    local description = require("gitforge.utility").read_file_to_string(description_file)
    table.insert(c, { "create", "--title", title, "--description", description })
    return vim.iter(c):flatten(math.huge):totable()
end

---@param output string Output of the 'create_issue' command exection. Tries to extract
---                     the issue id and return a provider for that issue.
---@return GiteaIssue|nil issue If the issue can be identified, returns a provider to work on that issue.
function GiteaIssue:handle_create_issue_output_to_view_issue(output)
    local log = require("gitforge.log")

    local lines = vim.split(output, "\n")
    local issue_link
    for index, value in ipairs(lines) do
        if index == 8 then
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
    return GiteaIssue:newFromLink(issue_link)
end

---@param opts IssueListOpts
---@return table command
function GiteaIssue:cmd_list_issues(opts)
    local required_fields =
    "title,labels,index,state,milestone,created,updated,body,author,assignees,url"
    local call = {
        self:issue_cmd(), "list",
        "--fields", required_fields,
        "--output", "json"
    }
    if opts.state then
        table.insert(call, "--state")
        table.insert(call, opts.state)
    else
        table.insert(call, "--state")
        table.insert(call, "all")
    end
    if opts.project then
        table.insert(call, "--repo")
        table.insert(call, opts.project)
    end
    if opts.limit then
        table.insert(call, "--limit")
        table.insert(call, tostring(opts.limit))
    end
    if opts.labels then
        table.insert(call, "--labels")
        table.insert(call, opts.labels)
    end
    if opts.assignee then
        table.insert(call, "--assignee")
        table.insert(call, opts.assignee)
    end
    return vim.iter(call):flatten(math.huge):totable()
end

---@return table command
function GiteaIssue:cmd_view_web()
    local c = self:cmd()
    if self.project then
        table.insert(c, "--repo")
        table.insert(c, self.project)
    end
    return vim.iter({ c, "open", self.issue_number }):flatten(math.huge):totable()
end

function GiteaIssue:new_label_provider_from_self()
    return require("gitforge.tea.label"):new(self.project)
end

---@return Label
local conv_gitea_label = function(glab_label)
    return { name = glab_label }
end

---@return Label[]
local conv_gitea_labels = function(labels_string)
    local result = {}
    for _, l in pairs(vim.split(labels_string, " ")) do
        table.insert(result, conv_gitea_label(l))
    end
    return result
end

---@param assignees_string string
---@return Author[]
local conv_gitea_assignees = function(assignees_string)
    local result = {}
    for _, name in pairs(vim.split(assignees_string, " ")) do
        local trimmed_name = vim.trim(name)
        if #trimmed_name > 0 then
            table.insert(result, { login = trimmed_name })
        end
    end
    return result
end

---Convert the 'tea' comment format for a single issue to the standardized Comment class.
---@return Comment
local conv_gitea_comments = function(json_comments)
    local result = {}
    for _, value in ipairs(json_comments) do
        table.insert(result, {
            author = { login = value.author},
            createdAt = value.created,
            body = value.body,
        })
    end
    return result
end

---@param json_input string raw text representation of the issue content.
---@return Issue issue Extracted the properties of the issue from the text.
function GiteaIssue:convert_cmd_result_to_issue(json_input)
    local json = vim.fn.json_decode(json_input)
    return {
        title = json.issue.title,
        body = json.issue.title,
        author = { login = json.issue.user },
        project = json.issue.project,
        number = json.issue.index,
        createdAt = json.issue.created,
        closed = json.issue.state == "closed",
        closedAt = json.issue.closedAt,
        state = json.issue.state,
        assignees = json.issue.assignees,
        labels = json.issue.labels,
        comments = conv_gitea_comments(json.comments),
    }
end

---Translates the JSON structure returned by 'tea' into the standardized @c Issue type.
local conv_single_gitea_issue = function(gitea_issue)
    local project, _ = parse_gitea_url(gitea_issue.url)
    local issue = {
        title = gitea_issue.title,
        body = gitea_issue.body,
        author = { login = gitea_issue.author },
        project = project,
        number = gitea_issue.index,
        createdAt = gitea_issue.created,
        closed = gitea_issue.state == "closed",
        --NOTE: closedAt can not be provided by the 'tea' cli tool.
        --      'updated' is the next best thing.
        closedAt = gitea_issue.updated,
        state = gitea_issue.state,
        assignees = conv_gitea_assignees(gitea_issue.assignees),
        labels = conv_gitea_labels(gitea_issue.labels),
        -- only the number of comments is provided by 'tea'. This is not useful.
        comments = nil,
    }
    return issue
end

---@param json_input string JSON encoded result of a command execution.
---@return Issue[] issue Transformed JSON to the expected interface of an issue.
function GiteaIssue:convert_cmd_result_to_issue_list(json_input)
    local issue_list = vim.fn.json_decode(json_input)
    local result = {}
    for _, issue in pairs(issue_list) do
        table.insert(result, conv_single_gitea_issue(issue))
    end
    return result
end

return GiteaIssue
