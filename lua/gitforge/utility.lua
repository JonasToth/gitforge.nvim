local M = {}

---@param path string Path to a file
---@return string|nil The content of the file read with 'rb' or nil if that failed.
function M.read_file_to_string(path)
    local file = io.open(path, "rb") -- r read mode and b binary mode
    if not file then return nil end
    local content = file:read("*a")  -- *a or *all reads the whole file
    file:close()
    return content
end

---@param file_content string File content
---@return string|nil Headline
function M.get_markdown_headline_from_file(file_content)
    local idx_first_linebreak = string.find(file_content, "\n", 1, true)
    if idx_first_linebreak == nil or idx_first_linebreak <= 3 then
        return nil
    end
    return vim.trim(string.sub(file_content, 3, idx_first_linebreak))
end

---@param file_content string Markdown rendered issue string.
---@return Label[]|nil Labels CSV string of labels.
---@return Author[]|nil Assignees CSV string of assignees.
function M.get_labels_and_assignees_from_file(file_content)
    local idx_first_linebreak = string.find(file_content, "\n", 1, true)
    if idx_first_linebreak == nil then
        return nil, nil
    end
    local idx_first_h2 = string.find(file_content, "##", idx_first_linebreak, true)
    if idx_first_h2 == nil then
        return nil, nil
    end

    local meta_data = string.sub(file_content, idx_first_linebreak, idx_first_h2)
    local labels = vim.trim(string.match(meta_data, "%cLabels: (.-)%c") or "")
    if labels == "-" then
        labels = ""
    end
    local assignees = vim.trim(string.match(meta_data, "%cAssigned to: (.-)%c") or "")
    if assignees == "-" then
        assignees = ""
    end

    require("gitforge.set")
    return M.labels_from_set(Set:createFromCSVList(labels)), M.authors_from_set(Set:createFromCSVList(assignees))
end

---Create @c Author objects from the set of strings.
---@param name_set Set Set of login names.
---@return Author[] Authors Objects with 'login' name provided from the provided strings.
function M.authors_from_set(name_set)
    local assignees = {}
    for assignee, _ in pairs(name_set.elements) do
        table.insert(assignees, { login = assignee })
    end
    return assignees
end

---Create @c Label objects from the set of strings.
---@param label_set Set label strings.
---@return Label[] Label label objects constructs from strings.
function M.labels_from_set(label_set)
    local labels = {}
    for label, _ in pairs(label_set.elements) do
        table.insert(labels, { name = label })
    end
    return labels
end

---Creates a string from the buffer content of @p buf
---@param buf integer Buffer Id to get the content from.
---@return string content Concatenation with "\n" and final trimming of the buffer content.
function M.buffer_to_string(buf)
    local curr_buf_content = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    return vim.trim(vim.fn.join(curr_buf_content, "\n"))
end

---Copies the buffer content from @c from_buf to @c to_buf.
---@param from_buf integer
---@param to_buf integer
function M.copy_buffer(from_buf, to_buf)
    local curr_buf_content = vim.api.nvim_buf_get_lines(from_buf, 0, -1, false)
    vim.api.nvim_buf_set_lines(to_buf, 0, -1, false, curr_buf_content)
end

---@param command table<string>|nil
---@param completion_func function
---@return vim.SystemObj|nil
function M.async_exec(command, completion_func)
    local log = require("gitforge.log")

    if command == nil then
        log.notify_failure("Provided command was 'nil'. Maybe your provider does not support this action")
        return nil
    end
    log.executed_command(command)
    return vim.system(command, { text = true, timeout = require("gitforge").opts.timeout }, completion_func)
end

---@param path string
function M.file_exists(path)
    return require("pathlib").new(path):is_file(false)
end

---@param path string
function M.dir_exists(path)
    return require("pathlib").new(path):is_dir(false)
end

---@return string path Path to data dir of the plugin.
function M.get_plugin_data_dir()
    ---@diagnostic disable-next-line: param-type-mismatch
    return vim.fs.normalize(vim.fs.joinpath(vim.fn.stdpath("data"), "gitforge"))
end

---@param provider IssueProvider
function M.get_project_directory(provider)
    ---@diagnostic disable-next-line: param-type-mismatch
    return vim.fs.normalize(vim.fs.joinpath(M.get_plugin_data_dir(), provider.project))
end

---@param provider IssueProvider|LabelProvider
---@return string Path
function M.create_and_get_data_dir(provider)
    local Path = require("pathlib")
    local dir = M.get_project_directory(provider)

    local provider_file = Path.new(vim.fs.joinpath(dir, "issue_provider." .. provider.provider))
    provider_file:touch(Path.permission("rw-r--r--"), true)

    return dir
end

---@param provider IssueProvider
---@return PathlibPath Path
function M.get_issue_data_file(provider)
    local proj_dir = M.create_and_get_data_dir(provider)
    return require("pathlib").new(vim.fs.joinpath(proj_dir, "issue_" .. provider.issue_number .. ".md"))
end

---@param provider LabelProvider
---@return PathlibPath Path to file containing cached project labels.
function M.get_project_labels_file(provider)
    local proj_dir = M.create_and_get_data_dir(provider)
    return require("pathlib").new(vim.fs.joinpath(proj_dir, "labels.json"))
end

return M
