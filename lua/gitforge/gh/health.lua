local M = {}

M.check = function()
    vim.health.start("Github health report")
    local exe = require("gitforge").opts.github.executable
    if vim.fn.executable(exe) == 1 then
        vim.health.ok("'gh'-cli tool is found (using '" .. exe .. "')")
    else
        vim.health.error("Missing 'gh'-cli tool (tried '" .. exe .. "')")
    end
end

return M
