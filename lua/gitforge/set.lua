---@class Set
---@field elements table<string, boolean>
---@brief Keeps the strings as keys of a table. If the key has a value, its element is in the set.
Set = {}

function Set:new()
    local s = setmetatable({}, { __index = Set })
    s.elements = {}
    return s
end

---@param csv_string string Comma-separated values
---@return Set elements The CSV string is split and deduplicated. Strings are trimmed and empty strings are removed.
function Set:createFromCSVList(csv_string)
    local result_set = Set:new()
    for _, el in pairs(vim.split(csv_string, ",")) do
        local trimmed = vim.trim(el)
        if #trimmed > 0 then
            result_set:add(trimmed)
        end
    end
    return result_set
end

---Adds key to the set. If it is already present, nothing happens.
function Set:add(key)
    self.elements[key] = true
end

---Removes key from the set. If it is not present, nothing happens.
function Set:remove(key)
    self.elements[key] = nil
end

---@return boolean isContained returns true if the value is in the set.
function Set:contains(key)
    return self.elements[key] ~= nil
end

---@return boolean isEmpty returns true if no elements are present in the set.
function Set:empty()
    for _, _ in pairs(self.elements) do
        return false
    end
    return true
end

---Computes @c self - other
---@param other Set Keys are set values.
---@return Set difference All elements that are in @c self but not in @c other
function Set:difference(other)
    ---@type Set
    local result_set = Set:new()
    for key, _ in pairs(self.elements) do
        if not other:contains(key) then
            result_set:add(key)
        end
    end
    return result_set
end

---Computes what elements were added and removed in @c other compared to @c self.
---@param other Set set to compute the delta to.
---@return Set added all elements that have to be added to @c self to become @c other
---@return Set remove all elements that have to be removed from @c self to become @c other
function Set:deltaTo(other)
    local removed = self:difference(other)
    local new = other:difference(self)
    return new, removed
end

---@return string CSV Joins each element in the set with a ',' together to form on string.
function Set:toCSV()
    local label_table = {}
    for key, _ in pairs(self.elements) do
        table.insert(label_table, key)
    end
    return vim.fn.join(label_table, ",")
end
