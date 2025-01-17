local GenericIssue = {}

require("gitforge.set")

---Author of an issue or comment, corresponding to a github user or bot.
---@class Author
---@field login string Username of the author.
---@field name string? Optional real name of the author.
---@field is_bot boolean Indicate if this is a bot account.

---@class Label
---@field name string human readable representation of the label
---@field color string HTML color of the label.

---@class Comment
---@field author Author Author of the comment.
---@field createdAt string ISO-8601 formatted UTC time of the comment time.
---@field body string Content of the comment.

---Define the used interface of the JSON contents of an issue. The content
---is translated into lua tables.
---@class Issue
---@field body string Holds the description of the issue as markdown string.
---@field title string Title of the issue
---@field author Author|nil Optionally present author meta data.
---@field number string Issue-ID
---@field createdAt string ISO-8601 formatted UTC time of issue creation.
---@field closed boolean Signaling if the issue is closed.
---@field closedAt string|nil ISO-8601 formatted UTC time of issue creation.
---@field state string Representation of the current state of the issue.
---@field assignees table<Author> potentially empty list of assigned users.
---@field labels table<Label> potentially empty list of assigned labels.
---@field comments table<Comment>?

local g_description_headline_md = '## Description'
local g_comments_headline_md = '## Comments'

--- Renders the issue content into a buffer as markdown.
--- @param buf integer Buffer-Id to work on. If `nil`, a new buffer is created.
--- @param issue Issue Table of JSON data.
--- @return integer number of the buffer. Can be `0` if creation failed.
function GenericIssue.render_issue_to_buffer(buf, issue)
    local log = require("gitforge.log")
    log.trace_msg("Rendering Issue to buffer " .. buf)
    if issue == nil then
        return buf
    end

    if buf == 0 then
        buf = vim.api.nvim_create_buf(true, false)
    end

    if buf == 0 then
        log.notify_failure("Failed to create buffer to view issues")
        return 0
    end

    local desc = string.gsub(issue.body, "\r", "")
    vim.api.nvim_set_option_value('modifiable', true, { buf = buf })
    vim.api.nvim_set_option_value('readonly', false, { buf = buf })
    vim.api.nvim_set_option_value('buftype', 'nofile', { buf = buf })
    vim.api.nvim_set_option_value('swapfile', false, { buf = buf })

    vim.api.nvim_buf_set_lines(buf, 0, -1, true, { '# ' .. issue.title, '' })
    local realName = ''
    if issue.author and issue.author.name then
        realName = '(' .. issue.author.name .. ') '
    end
    vim.api.nvim_buf_set_lines(buf, -1, -1, true, { 'Number: #' .. issue.number })
    vim.api.nvim_buf_set_lines(buf, -1, -1, true,
        { 'Created by `@' .. issue.author.login .. '` ' .. realName .. 'at ' .. issue.createdAt })
    if not issue.closed then
        vim.api.nvim_buf_set_lines(buf, -1, -1, true,
            { 'Status: ' .. issue.state .. ' (' .. issue.createdAt .. ')' })
    else
        vim.api.nvim_buf_set_lines(buf, -1, -1, true,
            { 'Status: ' .. issue.state .. ' (' .. issue.closedAt .. ')' })
    end
    local assignees = {}
    for _, value in ipairs(issue.assignees) do
        table.insert(assignees, value.login)
    end
    if #assignees > 0 then
        vim.api.nvim_buf_set_lines(buf, -1, -1, true, { 'Assigned to: ' .. vim.fn.join(assignees, ',') })
    else
        vim.api.nvim_buf_set_lines(buf, -1, -1, true, { 'Assigned to: -' })
    end
    local labels = {}
    for _, value in ipairs(issue.labels) do
        table.insert(labels, value.name)
    end
    if #labels > 0 then
        vim.api.nvim_buf_set_lines(buf, -1, -1, true, { 'Labels: ' .. vim.fn.join(labels, ',') })
    end
    -- if issue_json.milestone ~= vim.NIL then
    --     a.nvim_buf_set_lines(buf, -1, -1, true, { 'Milestone: ' .. issue_json.milestone })
    -- end

    vim.api.nvim_buf_set_lines(buf, -1, -1, true, { '', g_description_headline_md, '' })
    if #desc == 0 then
        vim.api.nvim_buf_set_lines(buf, -1, -1, true, { 'No Description' })
    else
        vim.api.nvim_buf_set_lines(buf, -1, -1, true, vim.split(vim.trim(desc), '\n'))
    end
    if issue.comments ~= nil then
        vim.api.nvim_buf_set_lines(buf, -1, -1, true, { '', g_comments_headline_md })
        local comments = issue.comments
        if #comments == 0 then
            vim.api.nvim_buf_set_lines(buf, -1, -1, true, { '', 'No comments' })
        else
            for _, comment in ipairs(comments) do
                local author = comment.author.login
                local timestamp = comment.createdAt
                local body = string.gsub(comment.body, "\r", "")
                vim.api.nvim_buf_set_lines(buf, -1, -1, true,
                    { '', '#### `@' .. author .. '` at __' .. timestamp .. "__", '' })
                vim.api.nvim_buf_set_lines(buf, -1, -1, true, vim.split(vim.trim(body), '\n'))
            end
        end
    end
    vim.api.nvim_set_option_value('modifiable', false, { buf = buf })
    vim.api.nvim_set_option_value('readonly', true, { buf = buf })
    return buf
end

--- Parses the buffer name and tries to retrieve the issue number and project.
---@param buf number Buffer Id for the issue buffer
function GenericIssue.get_issue_id_from_buf(buf)
    local buf_name = vim.api.nvim_buf_get_name(buf)
    if string.find(buf_name, "[Issue]", 1, true) == nil then
        return nil
    end
    for nbr in buf_name:gmatch("#(%d+)") do
        return nbr
    end
end

---Return the comma separated list of labels from the issue buffer @c buf if possible.
---@param buf number Buffer-ID for issue.
---@return Set|nil labels Set of extracted labels. @c nil if that failed.
function GenericIssue.get_labels_from_issue_buffer(buf)
    local log = require("gitforge.log")
    local curr_buf_content = vim.api.nvim_buf_get_lines(buf, 6, 7, false)
    local label_line = curr_buf_content[1]
    if label_line == nil then
        log.notify_failure("Failed to get expected label line from buffer " .. buf)
        return nil;
    end
    -- verify that the labels line is found
    if label_line:sub(1, 7) ~= "Labels:" then
        return Set:new()
    end
    -- extract all labels from the line
    return Set:createFromCSVList(label_line:sub(9, -1))
end

---Return the string of the current state of the issue buffer @c buf if possible.
---@param buf number Buffer-Id for the issue
---@return string|nil status String representation of the issue status if found,  otherwise @c nil.
function GenericIssue.get_status_from_issue_buffer(buf)
    local log = require("gitforge.log")
    local curr_buf_content = vim.api.nvim_buf_get_lines(buf, 4, 5, false)
    local status_line = curr_buf_content[1]
    if status_line == nil then
        log.notify_failure("Failed to get status line from buffer " .. buf)
        return nil;
    end
    local extracted_status = string.match(status_line, "^Status: (.+) %(")
    if extracted_status == nil then
        log.notify_failure("Failed to extract status from buffer " .. buf .. " and supposed state line:\n" .. status_line)
        return nil
    end
    return vim.trim(extracted_status)
end

---Return the comma separated list of assignees from the issue buffer @c buf if possible.
---@param buf number Buffer-ID for Issue.
---@return Set|nil assignees A set of assignees or @c nil if extraction failed.
function GenericIssue.get_assignee_from_issue_buffer(buf)
    local log = require("gitforge.log")
    local curr_buf_content = vim.api.nvim_buf_get_lines(buf, 5, 6, false)
    local assignee_line = curr_buf_content[1]
    if assignee_line == nil then
        log.notify_failure("Failed to get assignee line from buffer " .. buf)
        return nil;
    end
    -- verify that the labels line is found
    if assignee_line:sub(1, 12) ~= "Assigned to:" then
        log.notify_failure("Found assignee line does not contain 'Assigned to:' at beginning of line, ERROR (line: " ..
            assignee_line .. ")")
        return nil
    end
    -- extract all labels from the line
    local assignees = assignee_line:sub(14, -1)
    if assignees == "-" then
        return Set:new()
    else
        return Set:createFromCSVList(assignees)
    end
end

return GenericIssue
