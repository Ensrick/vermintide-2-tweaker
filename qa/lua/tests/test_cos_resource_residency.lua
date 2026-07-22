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
        H.equal(Residency.VERSION, 2)

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

    H.test("Shared #749 tri-state probe preserves unknown external resources", function()
        local state, reason = Residency.probe(
            "material", "materials/pusfume/custom", nil, nil, "global_renderer")
        H.equal(state, Residency.STATE_UNKNOWN)
        H.equal(reason, "missing_can_get")

        state, reason = Residency.probe(
            "material", "materials/pusfume/custom",
            { can_get = function() error("external registry unavailable") end },
            nil, "global_renderer")
        H.equal(state, Residency.STATE_UNKNOWN)
        H.equal(reason, "can_get_error")

        state, reason = Residency.probe(
            "material", "materials/definitely_absent",
            { can_get = function() return false end }, nil, "global_renderer")
        H.equal(state, Residency.STATE_ABSENT)
        H.equal(reason, "not_resident")

        state, reason = Residency.probe(
            "material", "materials/resident",
            { can_get = function() return true end }, nil, "global_renderer")
        H.equal(state, Residency.STATE_RESIDENT)
        H.equal(reason, "resident")
    end)

    H.test("Shared #749 owned resource helpers fail closed on unknown probes", function()
        local ok, reason = Residency.material_resident(
            "materials/owned", nil, nil, "owned_surface")
        H.equal(ok, false)
        H.equal(reason, "missing_can_get")

        ok, reason = Residency.shading_environment_resident(
            "environment/ui_hdr",
            { can_get = function(kind, path)
                return kind == "shading_environment" and path == "environment/ui_hdr"
            end }, nil, "preview")
        H.equal(ok, true)
        H.equal(reason, "resident")
    end)

    H.test("Shared #749 texture sets are atomic before native writes", function()
        local probes = 0
        local ok, reason, count = Residency.texture_set_resident({
            { slot = "diffuse", texture = "textures/a" },
            { slot = "normal", texture = "textures/b" },
            { slot = "packed", texture = "textures/missing" },
        }, {
            can_get = function(_, path)
                probes = probes + 1
                return path ~= "textures/missing"
            end,
        }, nil, "remote_husk")
        H.equal(ok, false)
        H.equal(reason, "not_resident")
        H.equal(count, 2)
        H.equal(probes, 3)

        ok, reason, count = Residency.texture_set_resident({
            diffuse = "textures/a",
            normal = "textures/b",
        }, { can_get = function() return true end }, nil, "loot_previewer")
        H.equal(ok, true)
        H.equal(reason, "resident")
        H.equal(count, 2)

        local malformed_probes = 0
        ok, reason, count = Residency.texture_set_resident({
            [1] = { slot = "diffuse", texture = "textures/a" },
            [3] = { slot = "packed", texture = "textures/b" },
        }, { can_get = function() malformed_probes = malformed_probes + 1; return true end },
        nil, "loot_previewer")
        H.equal(ok, false)
        H.equal(reason, "malformed_texture_set")
        H.equal(count, 0)
        H.equal(malformed_probes, 0)

        ok, reason, count = Residency.texture_set_resident({
            { slot = "diffuse", texture = "textures/a" },
            normal = "textures/b",
        }, { can_get = function() malformed_probes = malformed_probes + 1; return true end },
        nil, "loot_previewer")
        H.equal(ok, false)
        H.equal(reason, "malformed_texture_set")
        H.equal(count, 0)
        H.equal(malformed_probes, 0)
    end)

    H.test("Shared #749 unit material closure rejects unresolved handles", function()
        local unit = {}
        local unit_api = {
            alive = function(candidate) return candidate == unit end,
            num_meshes = function() return 1 end,
            mesh = function() return {} end,
        }
        local mesh_api = {
            num_materials = function() return 1 end,
            material = function() return nil end,
        }
        local ok, reason, count = Residency.unit_materials_resident(
            unit, unit_api, mesh_api, nil, "network_husk")
        H.equal(ok, false)
        H.equal(reason, "material_unresolved_0_0")
        H.equal(count, 0)

        mesh_api.material = function() return "#ID[00000000]" end
        ok, reason = Residency.unit_materials_resident(
            unit, unit_api, mesh_api, nil, "network_husk")
        H.equal(ok, false)
        H.equal(reason, "material_null_0_0")

        mesh_api.material = function() return "#ID[12345678]" end
        ok, reason, count = Residency.unit_materials_resident(
            unit, unit_api, mesh_api, nil, "network_husk")
        H.equal(ok, true)
        H.equal(reason, "resident")
        H.equal(count, 1)

        unit_api.num_meshes = function() return 1.5 end
        ok, reason = Residency.unit_materials_resident(
            unit, unit_api, mesh_api, nil, "network_husk")
        H.equal(ok, false)
        H.equal(reason, "unit_has_no_meshes")
    end)

    H.test("Shared #749 exact Gui closure rejects absent renderer materials", function()
        local renderer = { gui = {} }
        local ok, reason = Residency.gui_material_resident(
            renderer, "custom_icon", { material = function() return nil end },
            nil, "athanor")
        H.equal(ok, false)
        H.equal(reason, "gui_material_absent")

        ok, reason = Residency.gui_material_resident(
            renderer, "custom_icon", { material = function() return "#ID[00000000]" end },
            nil, "athanor")
        H.equal(ok, false)
        H.equal(reason, "gui_material_absent")

        local handle = {}
        ok, reason = Residency.gui_material_resident(
            renderer, "custom_icon", { material = function() return handle end },
            nil, "athanor")
        H.equal(ok, true)
        H.equal(reason, "resident")
    end)

    H.test("Shared #749 global material filter drops proved absence only", function()
        local calls = 0
        local args = {
            "immediate",
            "material", "materials/resident",
            "material", "materials/absent",
            "material", "materials/third_party",
            "opaque-token",
        }
        local out, count, report = Residency.filter_material_pairs(
            #args, args, {
                can_get = function(_, path)
                    calls = calls + 1
                    if path == "materials/resident" then return true end
                    if path == "materials/absent" then return false end
                    error("third-party registry unavailable")
                end,
            }, nil, "ui_renderer_create")
        H.equal(calls, 3)
        H.equal(report.changed, true)
        H.equal(#report.dropped, 1)
        H.equal(report.dropped[1], "materials/absent")
        H.equal(#report.unknown, 1)
        H.equal(report.unknown[1].path, "materials/third_party")
        H.equal(count, #args - 2)
        H.equal(table.concat(out, "|"),
            "immediate|material|materials/resident|material|materials/third_party|opaque-token")

        out, count, report = Residency.filter_material_pairs(
            2.5, args, { can_get = function() error("must not probe") end },
            nil, "ui_renderer_create")
        H.equal(out, nil)
        H.equal(count, 0)
        H.equal(report.changed, false)
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

    -- resource-safety: cos749-la-atomic-texture-closure
    H.test("Cosmetics #749 active LA bridge uses strict residency at native texture boundary", function()
        local source = read("cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_la_bridge.lua")
        H.truthy(source:find('mod:dofile("scripts/mods/cosmetics_tweaker/_lib_resource_residency")', 1, true))
        H.truthy(source:find("#749 residency SKIP", 1, true))

        local active_paint = assert(source:find("local function _paint_offhand_textures_locally", 1, true))
        H.truthy(source:find("RESIDENCY.texture_set_resident(", active_paint, true))
        H.truthy(source:find("RESIDENCY.unit_materials_resident(", 1, true))
        H.equal(source:find("RESIDENCY.texture_bind_resident(", 1, true), nil)
        local preflight = assert(source:find("RESIDENCY.texture_set_resident(", active_paint, true))
        local native_write = assert(source:find("Unit.set_texture_for_materials(unit, binding.slot, binding.texture)", active_paint, true))
        H.truthy(preflight < native_write)
        H.equal(source:find("not can_get or can_get(\"texture\"", active_paint, true), nil)
    end)

    H.test("Cosmetics #749 local resource-residency copy matches shared contract", function()
        local shared = read("tools/shared_lib/_lib_resource_residency.lua")
        for _, local_path in ipairs({
            "character_weapon_variants/scripts/mods/character_weapon_variants/_lib_resource_residency.lua",
            "cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_lib_resource_residency.lua",
            "crafting_in_modded_dev/scripts/mods/crafting_in_modded_dev/_lib_resource_residency.lua",
            "general_tweaker_dev/scripts/mods/general_tweaker_dev/_lib_resource_residency.lua",
            "gui_tweaker_dev/scripts/mods/gui_tweaker_dev/_lib_resource_residency.lua",
            "weapons_of_chaos/scripts/mods/weapons_of_chaos/_lib_resource_residency.lua",
        }) do
            H.equal(read(local_path), shared, "copy drift: " .. local_path)
        end
    end)

    H.test("Cosmetics #696 brackets the material-manager boundary with bounded identity", function()
        local source = read(
            "cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_material_hijack_embedded.lua")
        H.truthy(source:find("local MH_MAT_BIND_TRACE_CAP = 24", 1, true))
        H.truthy(source:find("local function _set_material_traced(unit, mat_slot, mat, convention)", 1, true))
        H.truthy(source:find("[cos:696] bind-start source=", 1, true))
        H.truthy(source:find("[cos:696] bind-end source=", 1, true))
        H.truthy(source:find(
            'local key = source .. "|" .. unit_name .. "|" .. tostring(mat_slot) .. "|" .. tostring(mat)',
            1, true))
        H.equal(source:find(
            'local key = tostring(unit) .. "|" .. tostring(mat_slot) .. "|" .. tostring(mat)',
            1, true), nil, "respawn-unique unit handles must not defeat the trace cap")

        local mat_to_use = assert(source:find('if unit_has_data(unit, "mat_to_use") then', 1, true))
        local mat_list = assert(source:find('if unit_has_data(unit, "mat_list") then', mat_to_use, true))
        local mat_to_use_trace = assert(source:find('_set_material_traced(', mat_to_use, true))
        H.truthy(mat_to_use_trace < mat_list)
        H.truthy(source:find('unit, plan.mat_slot, mat, "mat_to_use")',
            mat_to_use_trace, true) < mat_list)
        H.truthy(source:find('_set_material_traced(unit, mat_slot, mat, "mat_list")', mat_list, true))
    end)

    H.test("Cosmetics #749 Material-Hijack writers prove atomic textures and live materials", function()
        local static = read(
            "cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_material_hijack_embedded.lua")
        local animated = read(
            "cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_material_hijack_embedded_anim.lua")
        local static_write = assert(static:find(
            "material_set_texture(target, binding.slot, binding.texture)", 1, true))
        H.truthy(assert(static:find("RESIDENCY.texture_set_resident(", 1, true)) < static_write)
        H.truthy(assert(static:find("RESIDENCY.unit_materials_resident(", 1, true)) < static_write)
        H.truthy(assert(static:find("RESIDENCY.material_resident(", 1, true)) < static_write)
        H.equal(static:find("Application.can_get(\"texture\"", 1, true), nil)

        local animated_write = assert(animated:find(
            "material_set_texture(material, texure_slot_name, texture)", 1, true))
        H.truthy(assert(animated:find("RESIDENCY.texture_bind_resident(", 1, true)) < animated_write)
        H.truthy(assert(animated:find("RESIDENCY.unit_materials_resident(", 1, true)) < animated_write)
        H.equal(animated:find("Application.can_get(\"texture\"", 1, true), nil)
    end)
end
