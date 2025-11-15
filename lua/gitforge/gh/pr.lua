---Provides the interface to interact with Github pull requests.
---@class GHPR:PRProvider
---@field provider string "gh"
---@field project string|nil
---@field pr_number string|nil PR-ID
---@field cmd_list_prs function Retrieve the list of PRs.
local GHPR = {
    provider = "gh",
    project = nil,
}

require("gitforge.pr_provider")
setmetatable(GHPR, { __index = PRProvider })

---@param project string|nil Project identifier, project of current directory if nil.
---@return GHPR
function GHPR:new(project)
    local s = setmetatable({}, { __index = GHPR })
    s.project = project
    return s
end

function GHPR:cmd()
    return require("gitforge").opts.github.executable
end

function GHPR:pr_cmd()
    local c = { self:cmd(), "pr" }
    if self.project then
        table.insert(c, "--repo")
        table.insert(c, self.project)
    end
    return c
end

function GHPR:cmd_fetch()
    local required_fields =
    "title,body,createdAt,author,comments,assignees,labels,number,state,milestone,closed,closedAt,url"
    local gh_call = self:pr_cmd()
    table.insert(gh_call, { "view", self.pr_number, "--json", required_fields })
    return vim.iter(gh_call):flatten(math.huge):totable()
end

function GHPR:cmd_list_prs(opts)
    local required_fields =
    "title,labels,number,state,milestone,createdAt,updatedAt,body,author,assignees,url"
    local gh_call = { self:pr_cmd(), "list", "--json", required_fields }
    return vim.iter(gh_call):flatten(math.huge):totable()
end

---@param json_input string JSON encoded result of a command execution.
---@return Issue issue Transformed JSON to the expected interface of an pr.
function GHPR:convert_cmd_result_to_pr(json_input)
    local issue = vim.fn.json_decode(json_input)
    local project, _ = require("gitforge.url_parsing").parse_github_issue_pr_url(issue.url)
    issue.project = project
    return issue
end

---@param json_input string JSON encoded result of a command execution.
---@return Issue[] issue Transformed JSON to the expected interface of an pr.
function GHPR:convert_cmd_result_to_pr_list(json_input)
    local pr_list = vim.fn.json_decode(json_input)
    local result = {}
    for _, i in pairs(pr_list) do
        local project, _ = require("gitforge.url_parsing").parse_github_issue_pr_url(i.url)
        local pr = vim.deepcopy(i)
        pr.project = project
        table.insert(result, pr)
    end
    return result
end

return GHPR
