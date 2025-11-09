---Provides the interface to interact with Gitea labels.
---@class TeaLabel:LabelProvider
---@field provider string "tea"
---@field project string|nil
---@field cmd_list_labels function Retrieve list of available labels.
local TeaLabel = {
    provider = "tea",
    project = nil,
}

require("gitforge.label_provider")
setmetatable(TeaLabel, { __index = LabelProvider })

---@param project string|nil Project identifier, project of current directory if nil.
---@return TeaLabel
function TeaLabel:new(project)
    local s = setmetatable({}, { __index = TeaLabel })
    s.project = project
    return s
end

function TeaLabel:cmd()
    return require("gitforge").opts.gitea.executable
end

function TeaLabel:label_cmd()
    local c = { self:cmd(), "labels", }
    if self.project then
        table.insert(c, "--repo")
        table.insert(c, self.project)
    end
    return c
end

---@param limit integer|nil Limit the number of retrieved labels.
---@return table Command Command to retrieve the labels of the project.
function TeaLabel:cmd_list_labels(limit)
    local c = self:label_cmd()
    table.insert(c, "list")
    table.insert(c, "--output")
    table.insert(c, "json")
    if limit ~= nil then
        table.insert(c, "--limit")
        table.insert(c, tostring(limit))
    end
    return c
end

return TeaLabel
