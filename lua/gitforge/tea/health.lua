local M = {}

M.check = function()
    vim.health.start("gitea health report")
    local exe = require("gitforge").opts.gitea.executable
    if vim.fn.executable(exe) == 1 then
        vim.health.ok("'tea'-cli tool is found (using '" .. exe .. "')")
    else
        vim.health.error("Missing 'tea'-cli tool (tried '" .. exe .. "')")
    end
end

return M
