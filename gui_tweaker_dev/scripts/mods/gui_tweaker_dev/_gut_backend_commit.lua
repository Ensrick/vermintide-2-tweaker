-- _gut_backend_commit.lua -- small, engine-free wrapper for explicit backend commits.

local Commit = {}

function Commit.classify_status(status)
    if status == "success" then
        return true, "success"
    end

    return false, tostring(status or "missing status")
end

function Commit.request(backend_manager, complete_callback)
    if type(backend_manager) ~= "table" or type(backend_manager.commit) ~= "function" then
        return false, "backend commit interface unavailable"
    end

    local ok, commit_id = pcall(backend_manager.commit, backend_manager, true, complete_callback)
    if not ok then
        return false, tostring(commit_id)
    end
    if commit_id == nil then
        return false, "backend mirror unavailable"
    end

    return true, commit_id
end

return Commit
