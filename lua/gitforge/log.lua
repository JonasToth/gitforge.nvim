local Log = {}

---Signal that an event triggered a change of data. The user should notice this event
---even have it in a log (e.g. notification log)
---@param what_happened string Human readable information on what changed.
function Log.notify_change(what_happened)
    vim.schedule(function() vim.notify(what_happened, vim.log.levels.INFO, {}) end)
end

---Signal that an action failed to complete successfully. This is not a detailed error message.
---@param what_happened string Human readable information on what changed.
function Log.notify_failure(what_happened)
    vim.schedule(function() vim.notify(what_happened, vim.log.levels.ERROR, {}) end)
end

---Useful to signal noops or signal ineffective actions.
---@param info_msg string Message that is displayed to the user shortly.
function Log.ephemeral_info(info_msg)
    vim.schedule(function() vim.api.nvim_echo({ { info_msg } }, false, {}) end)
end

---Debug logging to trace the execution of the code. Off by default.
---@param msg any Debug trace message.
function Log.trace_msg(msg)
    vim.schedule(function() print(vim.inspect(msg)) end)
end

---@param command_table table<string> Command line call in string pieces to log
function Log.executed_command(command_table)
    if command_table == nil then
        vim.schedule(function() vim.api.nvim_echo({ "Tries to log nil as command" }, true, {}) end)
    else
        Log.trace_msg(command_table)
    end
end

return Log
