local M = {}

M.check = function()
    vim.health.start("GitForge health report")
    local opts = require("gitforge").opts
    local default_issue_provider_ok, import_err = pcall(require, opts.default_issue_provider)
    if default_issue_provider_ok then
        vim.health.ok("Default issue provider can be imported (using '" .. opts.default_issue_provider .. "')")
    else
        vim.health.error("The default issue provider can not be imported ('" .. opts.default_issue_provider .. "')")
        vim.health.error(import_err)
    end
end

return M
