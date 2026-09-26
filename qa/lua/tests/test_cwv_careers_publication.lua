-- Offline proof for #1660: a published ItemMasterList row must never alias
-- the catalog's shared careers array. Sibling mods mutate rows in place:
-- Pusfume's roster appends its career to every melee/ranged row
-- (_pusfume_roster.lua:90,124-127) and weapon_tweaker's _set_career removes
-- and appends (_wt_availability.lua:130-137). Twenty-five Empire definitions
-- share ONE careers table (_cwv_variant_catalog.lua:9), so a by-reference
-- publish leaked one foreign append into every Empire def and four regression
-- checks. Drives the installed production registration owner's build_entry,
-- not a copy of it (loader pattern: test_cwv_acquisition_runtime.lua).
return function(H, repo_root)
    local root = repo_root .. "/character_weapon_variants/scripts/mods/character_weapon_variants/"
    local acquisition = assert(loadfile(root .. "_cwv_acquisition.lua"))()
    local function read(name)
        local file = assert(io.open(root .. name, "rb"))
        local text = file:read("*a")
        file:close()
        return text
    end
    local function clone(value)
        if type(value) ~= "table" then return value end
        local copy = {}
        for key, child in pairs(value) do copy[key] = clone(child) end
        return copy
    end
    local function registration_loader(env)
        local text = read("_cwv_item_registration_owner.lua")
        -- PUC 5.1 lacks Stingray's goto extension. Lower only the three proven
        -- continue branches in the one definition loop, preserving its body.
        local count
        text, count = text:gsub("for _, def in ipairs%(_variant_definitions%) do",
            "for _, def in ipairs(_variant_definitions) do\n\t\trepeat")
        H.equal(count, 1, "registration loop shape changed")
        text, count = text:gsub("goto continue", "break")
        H.equal(count, 3, "registration continue set changed")
        text, count = text:gsub("::continue::", "until true")
        H.equal(count, 1, "registration continue target changed")
        local chunk = assert(loadstring(text, "@_cwv_item_registration_owner.lua"))
        setfenv(chunk, env)
        return chunk()
    end

    local BASE = "dr_shield_axe"
    local AUTHORED = { "es_mercenary", "es_huntsman", "es_knight", "es_questingknight" }

    -- Install the real owner against a tiny engine fixture and hand back its
    -- published build_entry seam plus the base row it clones from.
    local function install(definitions)
        local hooks, messages = {}, {}
        local mod = { _cwv_acquisition = acquisition }
        function mod:get() return true end
        function mod:hook_safe(class, method, fn) hooks[class .. "." .. method] = fn end
        function mod:hook(class, method, fn) hooks[class .. "." .. method] = fn end
        function mod:info(fmt, ...) messages[#messages + 1] = string.format(fmt, ...) end
        mod.warning, mod.error = mod.info, mod.info
        local item_master = {
            [BASE] = { key = BASE, name = BASE, slot_type = "melee", item_type = "axe_shield",
                template = "dr_shield_axe_template", can_wield = { "dr_ranger", "dr_ironbreaker" } },
        }
        local env = setmetatable({
            get_mod = function() return nil end,
            ItemMasterList = item_master, NetworkLookup = { item_names = {} },
            Weapons = {}, CareerSettings = {}, ActionTemplates = {},
            table = setmetatable({ clone = clone }, { __index = table }),
            printf = function() end,
            WeaponSkins = { skins = {}, skin_combinations = {},
                matching_weapon_skin_item_key = function() return nil end },
            Managers = { backend = {
                get_interface = function()
                    return { get_item_from_id = function() return nil end }
                end,
                get_backend_mirror = function()
                    return { get_all_inventory_items = function() return {} end }
                end,
            } },
        }, { __index = _G })
        env._G = env
        local om = { infantry_spear = { ITEM_KEY = "cwv_es_infantry_spear" },
            deus_identity = { install = function()
                return { installed = 0, existing = 0, degraded = 0, skipped = {} }
            end } }
        registration_loader(env)(mod, {
            om = om, dbg = function() end, dbg_alert = function() end,
            variant_definitions = definitions, custom_skin_keys = {},
            network_lookup = { register_named = function(lookup, name, value)
                local index = #lookup[name] + 1
                lookup[name][index], lookup[name][value] = value, index
            end },
            cwv_career_weapon_actions = { install = function()
                return { ok = true, template_count = 0 }
            end },
        })
        return assert(om.item_registration.build_entry), item_master
    end

    H.test("CWV #1660 published can_wield is a private copy of the shared careers array", function()
        local shared = clone(AUTHORED)
        local defs = {
            { item_key = "cwv_fix_axe_shield", base_weapon = BASE, careers = shared,
                item_type = "cwv_fix_axe_shield" },
            { item_key = "cwv_fix_axe_shield_veteran", base_weapon = BASE, careers = shared,
                item_type = "cwv_fix_axe_shield" },
        }
        local build_entry = install(defs)
        local first = assert(build_entry(defs[1], "cwv_fix_axe_shield_000"))
        local second = assert(build_entry(defs[2], "cwv_fix_axe_shield_veteran_000"))
        H.deep_equal(first.can_wield, AUTHORED)
        H.deep_equal(second.can_wield, AUTHORED)
        H.truthy(first.can_wield ~= shared, "the row must not alias the catalog array")
        H.truthy(first.can_wield ~= second.can_wield, "sibling rows must not alias each other")

        -- Pusfume's roster layer: append in place to the published row.
        first.can_wield[#first.can_wield + 1] = "pusfume"
        H.deep_equal(shared, AUTHORED, "the shared catalog array is untouched")
        H.deep_equal(defs[2].careers, AUTHORED, "no sibling def sees the foreign career")
        H.deep_equal(second.can_wield, AUTHORED, "no sibling row sees the foreign career")

        -- weapon_tweaker's _set_career: remove then append in place on a row.
        table.remove(second.can_wield, 1)
        second.can_wield[#second.can_wield + 1] = "wh_captain"
        H.deep_equal(shared, AUTHORED)
        H.deep_equal(first.can_wield,
            { "es_mercenary", "es_huntsman", "es_knight", "es_questingknight", "pusfume" })

        -- The four checks read def.careers: still exactly the four authored
        -- Kruber careers with both foreign mutations applied to the rows.
        local seen = {}
        for _, career in ipairs(defs[1].careers) do seen[career] = true end
        for _, career in ipairs(AUTHORED) do
            H.truthy(seen[career], "authored career missing: " .. career)
            seen[career] = nil
        end
        H.equal(next(seen), nil, "def.careers carries a non-Kruber receiver")
    end)

    H.test("CWV #1660 a definition without careers inherits a copy of the base row's can_wield", function()
        local def = { item_key = "cwv_fix_plain", base_weapon = BASE, item_type = "cwv_fix_plain" }
        local build_entry, item_master = install({ def })
        local entry = assert(build_entry(def, "cwv_fix_plain_000"))
        H.deep_equal(entry.can_wield, { "dr_ranger", "dr_ironbreaker" })
        H.truthy(entry.can_wield ~= item_master[BASE].can_wield,
            "the clone must not alias the vanilla base row's array either")
    end)

    H.test("CWV #1660 the registration owner never publishes def.careers by reference", function()
        local source = read("_cwv_item_registration_owner.lua")
        H.equal(source:find("entry.can_wield = def.careers", 1, true), nil,
            "by-reference publish leaks a sibling mod's in-place append across every Empire def")
        H.truthy(source:find("entry.can_wield[index] = def.careers[index]", 1, true),
            "the row must carry an element-wise private copy")
    end)
end
