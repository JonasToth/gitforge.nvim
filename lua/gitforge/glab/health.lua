local M = {}

M.check = function()
    vim.health.start("GitLab health report")
    local exe = require("gitforge").opts.gitlab.executable
    if vim.fn.executable(exe) == 1 then
        vim.health.ok("'glab'-cli tool is found (using '" .. exe .. "')")
    else
        vim.health.error("Missing 'glab'-cli tool (tried '" .. exe .. "')")
    end
end

return M

