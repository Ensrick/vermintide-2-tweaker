local Source = {}

local CATALOG_MODULES_IN_LOAD_ORDER = {
    "_crt_balance_catalog.lua",
    "_crt_balance_catalog_early.lua",
    "_crt_balance_catalog_engineer.lua",
    "_crt_balance_catalog_focused_spirit.lua",
    "_crt_balance_catalog_late.lua",
}

local function read(path)
    local file = assert(io.open(path, "rb"))
    local source = file:read("*a")
    file:close()
    return source
end

function Source.combined(repo_root)
    local root = repo_root .. "/career_tweaker/scripts/mods/career_tweaker/"
    local chunks = { read(root .. "career_tweaker_balance.lua") }
    for _, module_name in ipairs(CATALOG_MODULES_IN_LOAD_ORDER) do
        chunks[#chunks + 1] = read(root .. module_name)
    end
    return table.concat(chunks, "\n")
end

return Source
