-- Engine-free coverage for the illusion-browser mesh-swap DELIVERY (#419).
--
-- `LootItemUnitPreviewer._load_item_units` rebinds item_data to the BASE master
-- list entry before asking for units, so the data-level resolution cannot see a
-- crafted variant's stamp and the browser spawns the base mesh -- which the
-- transform pass then scales, producing the reported distortion. CWV fixes that
-- with a pre-pass inside the `spawn_units` wrapper.
--
-- The property that matters is ORDER: the recipe must be rewritten BEFORE
-- vanilla reads it. Asserting the descriptor adapter in isolation cannot see
-- that -- removing the pre-pass call leaves such a check green. So this drives
-- the shipped wrapper with a spy standing in for vanilla `spawn_units` and reads
-- back what the spy was actually handed.
return function(H, repo_root)
    local mod_root = repo_root
        .. "/character_weapon_variants/scripts/mods/character_weapon_variants/"
    local install = assert(loadfile(mod_root .. "_cwv_menu_preview_owner.lua"))()

    local BASE_3P = "units/weapons/player/wpn_qa419_base/wpn_qa419_base_3p"
    local VARIANT_3P = "units/weapons/player/wpn_qa419_variant/wpn_qa419_variant_3p"

    -- Install the real owner. Its load-time work only needs the preview-pose
    -- slot and a mod that records hook registrations; everything the wrapper
    -- touches at CALL time is read off `om`, which the drive controls.
    local function fixture()
        local hooks = {}
        local om = {
            old_musket_preview_pose = {
                install = function() end,
                resolve_spawn_slot = function() return nil end,
            },
            mod_unit_preview = { apply_loot_fallbacks = function(_, sd) return sd end },
        }
        local mod = {
            hook = function(_, class, method)
                hooks[#hooks + 1] = tostring(class) .. "." .. tostring(method)
            end,
            hook_safe = function(_, class, method)
                hooks[#hooks + 1] = "safe:" .. tostring(class) .. "." .. tostring(method)
            end,
            command = function() end, echo = function() end, info = function() end,
            error = function() end, warning = function() end,
            get = function() return nil end,
            dofile = function() return {} end,
        }
        install(mod, {
            om = om,
            dbg = function() end,
            dbg_alert = function() end,
            resolve_field = function(def, field) return def and def[field] end,
            is_unit = function() return false end,
            transform_unit = function() end,
            apply_cwv_hand_transform = function() end,
            transform_map = {},
            skin_transform_map = {},
            crowbill_transform_by_unit = {},
        })
        return om, mod, hooks
    end

    -- The shape the issue is about: an Athanor craft whose backend_id is a guid,
    -- so identity survives only through the stamp the browser's rebind discards.
    local function crafted_item()
        return {
            backend_id = "qa419-3f9d5218-b649-4a59-bdb0-0ac51415ce46",
            data = { name = "qa419_base", key = "qa419_base",
                mod_data = { cwv_key = "cwv_qa419" } },
        }
    end

    -- Stands in for vanilla spawn_units. Returning nil keeps the post-spawn
    -- transform pass (which needs live engine units) out of the drive, and is
    -- also the honest answer for "vanilla spawned nothing".
    local function spy()
        local seen = {}
        return seen, function(_, spawn_data)
            seen.unit_name = spawn_data[1] and spawn_data[1].unit_name
            seen.calls = (seen.calls or 0) + 1
            return nil
        end
    end

    H.test("#419 the wrapper is a named seam and the hook only delegates to it", function()
        local om, mod, hooks = fixture()
        H.equal(type(om._cwv_browser_spawn_units), "function",
            "the browser spawn_units body must be callable without the engine")
        H.equal(mod._cwv_browser_spawn_units, om._cwv_browser_spawn_units)
        local registrations = 0
        for _, name in ipairs(hooks) do
            if name == "LootItemUnitPreviewer.spawn_units" then
                registrations = registrations + 1
            end
        end
        H.equal(registrations, 1,
            "VMF drops a duplicate registration on a (Class, method) pair -- there must be exactly one")
    end)

    H.test("#419 the mesh-swap pre-pass runs BEFORE vanilla reads the recipe", function()
        local om = fixture()
        local applied = {}
        om._cwv_browser_meshswap_apply = function(item, spawn_data)
            applied.item = item
            spawn_data[1].unit_name = VARIANT_3P
        end
        local seen, vanilla = spy()
        local spawn_data = { { unit_name = BASE_3P } }
        om._cwv_browser_spawn_units(vanilla, { _item = crafted_item() }, spawn_data)
        H.equal(seen.calls, 1, "vanilla spawn_units must still be called exactly once")
        H.equal(seen.unit_name, VARIANT_3P,
            "vanilla received the base mesh -- the pre-pass did not run before the spawn")
        H.equal(applied.item and applied.item.backend_id, crafted_item().backend_id,
            "the pre-pass must receive the previewer's ORIGINAL item, not the rebound base entry")
    end)

    H.test("#419 the wrapper passes vanilla's own return value through", function()
        local om = fixture()
        om._cwv_browser_meshswap_apply = function() end
        local units = {}
        local result = om._cwv_browser_spawn_units(function() return units end,
            { _item = nil }, { { unit_name = BASE_3P } })
        H.equal(result, units,
            "the browser must still receive the units vanilla spawned")
    end)

    H.test("#419 a missing pre-pass degrades instead of erroring", function()
        -- The helper is published late in the entry's load order; the wrapper is
        -- installed before it. A browser opened in that window must spawn the
        -- base mesh, never raise inside a menu.
        local om = fixture()
        om._cwv_browser_meshswap_apply = nil
        local seen, vanilla = spy()
        om._cwv_browser_spawn_units(vanilla, { _item = crafted_item() },
            { { unit_name = BASE_3P } })
        H.equal(seen.unit_name, BASE_3P)
    end)

    H.test("#419 the #597 mod-unit fallback still runs ahead of the swap", function()
        -- Ordering between the two pre-passes is load-bearing: the fallback
        -- rewrites a non-resident custom unit to its vanilla stand-in, and the
        -- mesh swap must see that already-corrected recipe.
        local om = fixture()
        local order = {}
        om.mod_unit_preview = {
            apply_loot_fallbacks = function(_, sd) order[#order + 1] = "fallback"; return sd end,
        }
        om._cwv_browser_meshswap_apply = function() order[#order + 1] = "meshswap" end
        local _, vanilla = spy()
        om._cwv_browser_spawn_units(vanilla, { _item = crafted_item() },
            { { unit_name = BASE_3P } })
        H.deep_equal(order, { "fallback", "meshswap" })
    end)
end
