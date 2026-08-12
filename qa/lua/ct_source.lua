local M = {}

local OWNER_FILES = {
    "_ct_host_state_transport_owner.lua",
    "_ct_run_runtime_owner.lua",
    "_ct_adventure_runtime_owner.lua",
    "_ct_boon_runtime_owner.lua",
    "_ct_settings_lifecycle_owner.lua",
}

local function read(path)
    local file = assert(io.open(path, "rb"))
    local source = file:read("*a")
    file:close()
    return source
end

function M.entry(repo_root)
    return read(repo_root
        .. "/chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/chaos_wastes_tweaker_dev.lua")
end

function M.expanded(repo_root)
    local root = repo_root
        .. "/chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/"
    local source = M.entry(repo_root)
    for _, owner_file in ipairs(OWNER_FILES) do
        local owner_name = owner_file:gsub("%.lua$", "")
        local needle = "scripts/mods/chaos_wastes_tweaker_dev/" .. owner_name
        local at = assert(source:find(needle, 1, true),
            owner_name .. " is not installed by the CT entry")
        local owner_source = read(root .. owner_file)
        source = source:sub(1, at - 1) .. owner_source .. "\n" .. source:sub(at)
    end
    return source
end

return M
