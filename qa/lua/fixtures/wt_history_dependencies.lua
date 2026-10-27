-- Explicit dependencies for legacy history behavior fixtures. No runtime logic is replaced.
local M = {}
function M.load(script_root)
    local runtime = assert(loadfile(script_root .. "_wt_history_runtime.lua"))()
    local transaction = assert(loadfile(script_root .. "_wt_history_profile_transaction.lua"))()
    local lookup = assert(loadfile(script_root .. "_lib_network_lookup.lua"))()
    return { install = function(config)
        config.profile_transaction = transaction
        config.profile_dependencies = { lookup = lookup }
        return runtime.install(config)
    end }
end
return M
