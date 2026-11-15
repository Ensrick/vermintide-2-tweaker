-- WP-CIM-06 (#1654, #277): the forge state owner never writes a store that would
-- break VMF's settings save, keeps rejected records instead of dropping them,
-- and leaves a clean store untouched at load
-- (crafting_in_modded_dev/.../_cim_forge_state_owner.lua).

local function deep_copy(value)
    if type(value) ~= "table" then return value end
    local copy = {}
    for k, v in pairs(value) do copy[k] = deep_copy(v) end
    return copy
end

return function(H, repo_root)
    local root = repo_root
        .. "/crafting_in_modded_dev/scripts/mods/crafting_in_modded_dev/"
    local contract = assert(loadfile(root .. "_cim_synthetic_item_contract.lua"))()
    -- Loaded per test so a missing module fails these cases, not the suite.
    local function load_store_policy()
        local chunk, err = loadfile(root .. "_cim_store_policy.lua")
        assert(chunk, "cim store policy module is missing: " .. tostring(err))
        return chunk()
    end

    local es_2h_sword = {
        slot_type = "melee", can_wield = { "es_mercenary" },
        template = "two_handed_swords_template_1", item_type = "es_2h_sword",
        inventory_icon = "icon_es_2h_sword", rarity = "plentiful",
    }

    local function record(extra)
        local r = {
            item_key = "es_2h_sword", slot_type = "melee", power_level = 300,
            rarity = "modded", via_mirror = true, properties = {}, traits = {},
        }
        for k, v in pairs(extra or {}) do r[k] = v end
        return r
    end

    local function fake_mod(settings)
        local mod = {
            settings = settings, sets = {}, printed = {},
            _cim_external_trait_policy = {
                merge_traits = function(active) return active or {} end,
                partition = function(combined) return combined, {} end,
                REQUIRED_CAPABILITY_BY_PROVIDER = {},
                RESERVED_PROVIDER_BY_TRAIT = {},
            },
            _cim_synthetic_item_contract = contract,
            _cim_store_policy = load_store_policy(),
            _cim_favorite_persistence = nil,
        }
        function mod:get(key) return self.settings[key] end
        function mod:set(key, value)
            self.sets[key] = (self.sets[key] or 0) + 1
            self.settings[key] = value
        end
        function mod:info() end
        function mod:echo() end
        function mod:warning() end
        function mod:hook() end
        function mod:hook_safe() end
        function mod:dofile(path)
            if path:find("_cim_custom_glow_notice", 1, true) then
                return { new = function()
                    return { observe = function() return 0, false end }
                end }
            end
            if path:find("_cim_mil_entry_builder", 1, true) then
                return function(weapon, backend_id)
                    return { backend_id = backend_id, key = weapon.item_key }
                end
            end
            error("unexpected dofile: " .. tostring(path))
        end
        return mod
    end

    local function install(mod, masters)
        local checks = {}
        local owner = assert(loadfile(root .. "_cim_forge_state_owner.lua"))()({
            mod = mod,
            rt_register = function(name, fn) checks[name] = fn end,
            print_line = function(fmt, ...)
                mod.printed[#mod.printed + 1] = string.format(fmt, ...)
            end,
            get_mod = function() return nil end,
            get_managers = function() return nil end,
            get_item_master_list = function() return masters or { es_2h_sword = es_2h_sword } end,
            get_weapon_traits = function() return nil end,
            get_cjson = function() return nil end,
            get_item_helper = function() return nil end,
            get_athanor_inject_all = function() return nil end,
            get_restore_modded_loadout = function() return nil end,
        })
        return owner, checks
    end

    H.test("cim store: a non-serializable craft is refused and the stored table is unchanged", function()
        local mod = fake_mod({ forged_weapons = { kept = record() } })
        local owner, checks = install(mod)
        local stored_before = deep_copy(mod.settings.forged_weapons)
        local sets_before = mod.sets.forged_weapons or 0

        local ok, reason = mod._cim_register_craft("mixed", record({
            custom_glow = { 1, 2, color = "red" },
        }))
        H.equal(ok, false)
        H.equal(type(reason), "string")
        H.equal(reason:sub(1, 5), "save:", reason)
        H.deep_equal(mod.settings.forged_weapons, stored_before, "stored table unchanged")
        H.equal(mod.sets.forged_weapons or 0, sets_before, "no settings write")
        H.equal(owner.get_forged_weapons().mixed, nil, "nothing published in memory")
        local refused = false
        for _, line in ipairs(mod.printed) do
            if line:find("[cim:store] REFUSED write: record mixed field custom_glow", 1, true) then
                refused = true
            end
        end
        H.truthy(refused, "refusal printed with id and field")
        H.equal(checks.issue_cim_store_serializable(), nil, "live store still serializable")
    end)

    H.test("cim store: a woc relic record moves to forged_weapons_rejected", function()
        local mod = fake_mod({
            forged_weapons = {
                relic = record({ item_key = "woc_blightreaper" }),
                kept = record(),
            },
        })
        local owner = install(mod, {
            es_2h_sword = es_2h_sword,
            woc_blightreaper = {
                slot_type = "melee", can_wield = { "es_mercenary" },
                template = "two_handed_swords_template_1", item_type = "woc",
                rarity = "unique", woc_unique_relic = true,
            },
        })
        H.equal(owner.get_forged_weapons().relic, nil, "relic not restorable")
        H.truthy(owner.get_forged_weapons().kept ~= nil)
        local rejected = mod.settings.forged_weapons_rejected
        H.equal(type(rejected), "table")
        H.equal(type(rejected.relic), "table", "relic kept under its id")
        H.equal(rejected.relic.record.item_key, "woc_blightreaper")
        H.equal(type(rejected.relic.reason), "string")
        H.equal(mod.settings.forged_weapons.relic, nil, "rejected record rewritten out of the live store")
        H.truthy(mod.settings.forged_weapons.kept ~= nil)
    end)

    H.test("cim store: load() leaves a clean store untouched", function()
        local mod = fake_mod({ forged_weapons = { a = record(), b = record() } })
        install(mod)
        H.equal(mod.sets.forged_weapons, nil, "no write from load()")
        H.equal(mod.sets.forged_weapons_rejected, nil)
    end)

    H.test("cim store: load() rewrites a migrated record once", function()
        local mod = fake_mod({ forged_weapons = { legacy = record({ rarity = "promo", via_mirror = nil }) } })
        install(mod)
        H.equal(mod.sets.forged_weapons, 1, "promo migration written back")
        H.equal(mod.settings.forged_weapons.legacy.rarity, "modded")
    end)
end
