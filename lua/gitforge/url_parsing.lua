local M = {}

---@param url string Github URL to issue or PR
---@return string|nil project
---@return string|nil item_number Integer ID of issue or pullrequest.
function M.parse_github_issue_pr_url(url)
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

return M
