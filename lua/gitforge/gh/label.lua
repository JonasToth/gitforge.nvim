---Provides the interface to interact with GitLab labels.
---@class GHLabel:LabelProvider
---@field provider string "gh"
---@field project string|nil
---@field cmd_list_labels function Retrieve list of available labels.
local GHLabel = {
    provider = "gh",
    project = nil,
}

require("gitforge.label_provider")
setmetatable(GHLabel, { __index = LabelProvider })

---@param project string|nil Project identifier, project of current directory if nil.
---@return GHLabel
function GHLabel:new(project)
    local s = setmetatable({}, { __index = GHLabel })
    s.project = project
    return s
end

function GHLabel:cmd()
    return require("gitforge").opts.github.executable
end

function GHLabel:label_cmd()
    local c = { self:cmd(), "label", }
    if self.project then
        table.insert(c, "--repo")
        table.insert(c, self.project)
    end
    return c
end

---@param limit integer|nil Limit the number of retrieved labels.
---@return table Command Command to retrieve the labels of the project.
function GHLabel:cmd_list_labels(limit)
    local c = self:label_cmd()
    table.insert(c, "--sort")
    table.insert(c, "name")
    table.insert(c, "--json")
    table.insert(c, "name,description")
    if limit ~= nil then
        table.insert(c, "--limit")
        table.insert(c, tostring(limit))
    end
    table.insert(c, "list")
    return c
end

return GHLabel
