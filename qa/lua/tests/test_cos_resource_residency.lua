return function(H, repo_root)
    local function read(relative_path)
        local file = assert(io.open(repo_root .. "/" .. relative_path, "rb"))
        local source = file:read("*a")
        file:close()
        return source
    end

    local shared_path = repo_root .. "/tools/shared_lib/_lib_resource_residency.lua"
    local Residency = dofile(shared_path)

    local function logger()
        local calls = {}
        return calls, function(reason, resource_type, path, slot, context)
            calls[#calls + 1] = {
                reason = reason,
                resource_type = resource_type,
                path = path,
                slot = slot,
                context = context,
            }
        end
    end

    H.test("Cosmetics #749 resource residency helper is strict fail-closed", function()
        H.equal(Residency.VERSION, 1)

        local calls, log = logger()
        local ok, reason = Residency.texture_bind_resident(
            "texture_map_c0ba2942", "textures/missing", nil, log, "loot_previewer")
        H.equal(ok, false)
        H.equal(reason, "missing_can_get")
        H.equal(calls[1].reason, "missing_can_get")

        ok, reason = Residency.texture_bind_resident(
            "texture_map_c0ba2942", "textures/missing",
            { can_get = function() return false end }, log, "loot_previewer")
        H.equal(ok, false)
        H.equal(reason, "not_resident")

        ok, reason = Residency.texture_bind_resident(
            "texture_map_c0ba2942", "textures/explodes",
            { can_get = function() error("probe failed") end }, log, "loot_previewer")
        H.equal(ok, false)
        H.equal(reason, "can_get_error")

        ok, reason = Residency.texture_bind_resident(
            "", "textures/valid", { can_get = function() return true end }, log, "loot_previewer")
        H.equal(ok, false)
        H.equal(reason, "malformed_slot")

        ok, reason = Residency.texture_bind_resident(
            "texture_map_c0ba2942", {}, { can_get = function() return true end }, log, "loot_previewer")
        H.equal(ok, false)
        H.equal(reason, "malformed_path")
    end)

    H.test("Cosmetics #749 resource residency helper allows only proved resident textures", function()
        local probes = {}
        local ok, reason = Residency.texture_bind_resident(
            "texture_map_c0ba2942",
            "textures/resident",
            {
                can_get = function(resource_type, path)
                    probes[#probes + 1] = { resource_type, path }
                    return resource_type == "texture" and path == "textures/resident"
                end,
            },
            nil,
            "network_husk"
        )
        H.equal(ok, true)
        H.equal(reason, "resident")
        H.equal(probes[1][1], "texture")
        H.equal(probes[1][2], "textures/resident")
    end)

    H.test("Cosmetics #749 live-unit proof rejects absent or malformed units", function()
        local calls, log = logger()
        local ok, reason = Residency.live_unit(nil, { alive = function() return true end }, log, "ingame")
        H.equal(ok, false)
        H.equal(reason, "missing_unit")

        ok, reason = Residency.live_unit({}, { alive = function() return true end }, log, "ingame")
        H.equal(ok, false)
        H.equal(reason, "malformed_unit")
        H.equal(calls[1].reason, "missing_unit")
        H.equal(calls[2].reason, "malformed_unit")
    end)

    H.test("Cosmetics #749 active LA bridge uses strict residency at native texture boundary", function()
        local source = read("cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_la_bridge.lua")
        H.truthy(source:find('mod:dofile("scripts/mods/cosmetics_tweaker/_lib_resource_residency")', 1, true))
        H.truthy(source:find("local function _texture_bind_resident(slot, texture, context)", 1, true))
        H.truthy(source:find("RESIDENCY.texture_bind_resident(slot, texture, Application", 1, true))
        H.truthy(source:find("#749 residency SKIP", 1, true))

        local active_paint = assert(source:find("local function _paint_offhand_textures_locally", 1, true))
        H.truthy(source:find("_texture_bind_resident(SHIELD_DIFF_SLOT, diff, context)", active_paint, true))
        H.truthy(source:find("_texture_bind_resident(SHIELD_PACK_SLOT, pack, context)", active_paint, true))
        H.truthy(source:find("_texture_bind_resident(SHIELD_NORM_SLOT, norm, context)", active_paint, true))
        H.equal(source:find("not can_get or can_get(\"texture\"", active_paint, true), nil)
    end)

    H.test("Cosmetics #749 local resource-residency copy matches shared contract", function()
        local shared = read("tools/shared_lib/_lib_resource_residency.lua")
        local local_copy = read("cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_lib_resource_residency.lua")
        H.equal(local_copy, shared)
    end)
end
