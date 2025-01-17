local M = {}

M.check = function()
    vim.health.start("Github health report")
    if vim.fn.executable("gh") == 1 then
        vim.health.ok("'gh' CLI tool is found.")
    else
        vim.health.error("Missing 'gh' CLI tool.")
    end
end

return M
