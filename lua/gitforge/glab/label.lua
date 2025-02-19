---Provides the interface to interact with GitLab labels.
---@class GLabLabel:LabelProvider
---@field provider string "glab"
---@field project string|nil
---@field cmd_list_labels function Retrieve list of available labels.
local GLabLabel = {
    provider = "glab",
    project = nil,
}

require("gitforge.label_provider")
setmetatable(GLabLabel, { __index = LabelProvider })

---@param project string|nil Project identifier, project of current directory if nil.
---@return GLabLabel
function GLabLabel:new(project)
    local s = setmetatable({}, { __index = GLabLabel })
    s.project = project
    return s
end

function GLabLabel:cmd()
    return require("gitforge").opts.gitlab.executable
end

function GLabLabel:label_cmd()
    local c = { self:cmd(), "label", }
    if self.project then
        table.insert(c, "--repo")
        table.insert(c, self.project)
    end
    return c
end

---@param limit integer|nil Limit the number of retrieved labels.
---@return table Command Command to retrieve the labels of the project.
function GLabLabel:cmd_list_labels(limit)
    local c = self:label_cmd()
    table.insert(c, "--output")
    table.insert(c, "json")
    if limit ~= nil then
        table.insert(c, "--per-page")
        table.insert(c, tostring(limit))
    end
    table.insert(c, "list")
    return c
end

return GLabLabel
