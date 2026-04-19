local mod = get_mod("t")

-- ============================================================
-- Any Weapon / Any Career
-- ============================================================
-- Based on Shazbot's AnyWeapon mod. Expands can_wield on every
-- ItemMasterList entry so all careers can equip any weapon.
-- Applied on game-state change (ItemMasterList loads lazily).
-- Crash-prevention hooks make off-career weapon use stable.

local _ALL_CAREERS = {
    "dr_ironbreaker", "dr_slayer",  "dr_ranger",  "dr_engineer",
    "es_huntsman",    "es_knight",  "es_mercenary", "es_questingknight",
    "we_shade",       "we_maidenguard", "we_waywatcher", "we_thornsister",
    "wh_zealot",      "wh_bountyhunter", "wh_captain", "wh_priest",
    "bw_scholar",     "bw_adept",   "bw_unchained", "bw_necromancer",
}

local _any_weapon_applied = false
-- Tracks items whose can_wield was replaced with _ALL_CAREERS so apply_weapon_unlocks
-- can detect and skip them (avoids corrupting the shared table).
local _any_weapon_originals = {}

local function apply_any_weapon()
    if _any_weapon_applied or not mod:get("any_weapon_any_career") then return end
    if not ItemMasterList then return end
    for key, weapon_data in pairs(ItemMasterList) do
        if weapon_data.can_wield then
            -- Skip items that are career-ability / career-exclusive (can_wield has exactly
            -- 1 entry). Expanding those breaks the game's own career-ability activation
            -- logic, which identifies such items by checking that only one career can wield
            -- them (BH's explosive bolt, GK's blessed blade, etc.).
            if #weapon_data.can_wield <= 1 then
                -- preserve as-is
            else
                -- Give each item its OWN copy so apply_weapon_unlocks can't corrupt
                -- another item's list by clearing one shared table.
                local copy = {}
                for i, v in ipairs(_ALL_CAREERS) do copy[i] = v end
                _any_weapon_originals[key] = weapon_data.can_wield  -- save real original
                weapon_data.can_wield = copy
            end
        end
    end
    _any_weapon_applied = true
    mod:info("AnyWeapon: expanded can_wield for multi-career items.")
end

-- ============================================================
-- Per-weapon career unlocks
-- ============================================================
-- Each setting unlock_CAREER_WEAPON adds that career to the weapon's
-- can_wield list so the career can equip the weapon normally.
-- Called alongside apply_any_weapon on every game-state change.

-- Per-career weapon unlock map.
-- Each career lists only the weapons it doesn't normally have access to
-- but whose animations are known-safe to cross-equip.
-- Key: career name. Value: list of weapon item keys.
local _WEAPON_UNLOCK_MAP = {
    -- Kruber: melee from Bardin/Saltzpyre + elf longbow (3P anim remapped to es_longbow);
    -- Bretonnian Sword and Shield (GK exclusive) for non-GK careers
    es_mercenary      = { "dr_1h_axe", "wh_1h_axe", "dr_1h_hammer", "wh_1h_hammer", "dr_shield_hammer", "wh_hammer_shield", "bw_sword", "we_longbow", "es_sword_shield" },
    es_huntsman       = { "dr_1h_axe", "wh_1h_axe", "dr_1h_hammer", "wh_1h_hammer", "dr_shield_hammer", "wh_hammer_shield", "bw_sword", "we_longbow", "es_sword_shield" },
    es_knight         = { "dr_1h_axe", "wh_1h_axe", "dr_1h_hammer", "wh_1h_hammer", "dr_shield_hammer", "wh_hammer_shield", "bw_sword", "we_longbow", "es_sword_shield" },
    es_questingknight = { "dr_1h_axe", "wh_1h_axe", "dr_1h_hammer", "wh_1h_hammer", "dr_shield_hammer", "wh_hammer_shield", "bw_sword", "we_longbow" },
    -- Bardin: can borrow Kruber's mace/mace+shield and Saltzpyre's axe/Skullsplitter
    dr_ranger         = { "es_1h_mace", "wh_1h_axe", "wh_1h_hammer", "es_mace_shield", "wh_hammer_shield" },
    dr_ironbreaker    = { "es_1h_mace", "wh_1h_axe", "wh_1h_hammer", "es_mace_shield", "wh_hammer_shield" },
    dr_slayer         = { "es_1h_mace", "wh_1h_axe", "wh_1h_hammer", "es_mace_shield", "wh_hammer_shield" },
    dr_engineer       = { "es_1h_mace", "wh_1h_axe", "wh_1h_hammer", "es_mace_shield", "wh_hammer_shield" },
    -- Kerillian: longbow for non-Waystalker careers (Waystalker already has it natively);
    -- Saltzpyre melee for all elf careers.
    -- Item keys confirmed from source: wh_fencing_sword, wh_1h_falchion, es_1h_flail.
    -- NOTE: no standalone Saltzpyre flail exists — only es_1h_flail (flail+shield combo).
    we_waywatcher     = { "wh_fencing_sword", "wh_1h_falchion", "es_1h_flail" },
    we_maidenguard    = { "we_longbow", "wh_fencing_sword", "wh_1h_falchion", "es_1h_flail" },
    we_shade          = { "we_longbow", "wh_fencing_sword", "wh_1h_falchion", "es_1h_flail" },
    we_thornsister    = { "we_longbow", "wh_fencing_sword", "wh_1h_falchion", "es_1h_flail" },
    -- Saltzpyre: Kruber's mace/sword/longbow + Bardin's hammer/axe + Sienna's sword/crowbill for all; shields only for Warrior Priest
    wh_captain        = { "es_1h_mace", "es_1h_sword", "es_longbow", "dr_1h_hammer", "dr_1h_axe", "bw_sword", "we_longbow", "bw_crowbill" },
    wh_bountyhunter   = { "es_1h_mace", "es_1h_sword", "es_longbow", "dr_1h_hammer", "dr_1h_axe", "bw_sword", "we_longbow", "bw_crowbill" },
    wh_zealot         = { "es_1h_mace", "es_1h_sword", "es_longbow", "dr_1h_hammer", "dr_1h_axe", "bw_sword", "we_longbow", "bw_crowbill" },
    wh_priest         = { "es_1h_mace", "es_1h_sword", "es_longbow", "dr_1h_hammer", "dr_1h_axe", "bw_sword", "we_longbow", "es_mace_shield", "dr_shield_hammer", "bw_crowbill" },
}

-- Saved originals keyed by weapon_key; populated on first call, never overwritten.
-- When apply_any_weapon has also run, the saved original is the pre-any-weapon list
-- (from _any_weapon_originals), so restore brings the item back to its real origin.
local _original_can_wield = {}

local function apply_weapon_unlocks()
    if not ItemMasterList then return end

    -- Collect every weapon key this mod might touch.
    local all_weapon_keys = {}
    for _, weapons in pairs(_WEAPON_UNLOCK_MAP) do
        for _, weapon_key in ipairs(weapons) do
            all_weapon_keys[weapon_key] = true
        end
    end

    for weapon_key in pairs(all_weapon_keys) do
        local item = ItemMasterList[weapon_key]
        if item and item.can_wield then
            -- Save original once. If apply_any_weapon already swapped can_wield to a copy,
            -- use _any_weapon_originals to get back to the real pre-mod list.
            if not _original_can_wield[weapon_key] then
                local real_orig = _any_weapon_originals[weapon_key] or item.can_wield
                local orig = {}
                for i, v in ipairs(real_orig) do orig[i] = v end
                _original_can_wield[weapon_key] = orig
            end
            -- Restore in-place. Each item now owns its own can_wield table (not shared),
            -- so clearing it here only affects this one item.
            local t    = item.can_wield
            local orig = _original_can_wield[weapon_key]
            while #t > 0 do table.remove(t) end
            for _, v in ipairs(orig) do t[#t + 1] = v end
        end
    end

    -- Re-apply only currently-enabled unlocks.
    for career, weapons in pairs(_WEAPON_UNLOCK_MAP) do
        for _, weapon_key in ipairs(weapons) do
            if mod:get("unlock_" .. career .. "_" .. weapon_key) then
                local item = ItemMasterList[weapon_key]
                if item and item.can_wield then
                    local already = false
                    for _, c in ipairs(item.can_wield) do
                        if c == career then already = true; break end
                    end
                    if not already then
                        item.can_wield[#item.can_wield + 1] = career
                    end
                end
            end
        end
    end
end

local function _safe_create_equipment(func, world, slot_name, item_data, unit_1p, unit_3p, is_bot, unit_template, extra_extension_data, ammo_percent, override_item_template, override_item_units, career_name)
    local result
    local ok, err = pcall(function()
        result = func(world, slot_name, item_data, unit_1p, unit_3p, is_bot, unit_template, extra_extension_data, ammo_percent, override_item_template, override_item_units, career_name)
    end)
    if not ok then
        local iname = item_data and item_data.name or "?"
        mod:warning("create_equipment failed (career=%s item=%s slot=%s): %s", tostring(career_name), iname, tostring(slot_name), tostring(err))
    end
    return result
end

mod:hook("GearUtils", "create_equipment", _safe_create_equipment)

-- 3P crossbow model swap for Saltzpyre + longbow: DEFERRED
-- BackendUtils.get_item_units feeds both 1P and 3P from the same call.
-- Swapping left_hand_unit there breaks 1P (bow invisible, arrow visible).
-- Need a 3P-only hook point. Documented in WORK_ITEMS.md.

-- ============================================================
-- Talent & Ability Swapping
-- ============================================================
-- Directly mutates the live TalentTrees global (which is read every time the
-- game looks up a talent by tier/index) and the CareerSettings activated_ability
-- / passive_ability fields (read by career_extension:init at level load).
-- All originals are saved before mutation so the function is safe to call
-- repeatedly — it restores first, then re-applies the current settings.

local _talent_swap_originals = {}  -- [career_name] = { tree, activated_ability, passive_ability }

local function apply_talent_swaps()
    if not CareerSettings or not TalentTrees then return end

    -- Restore all previous overrides to their originals
    for career_name, orig in pairs(_talent_swap_originals) do
        local cs = CareerSettings[career_name]
        if cs then
            local trees = TalentTrees[cs.profile_name]
            if trees then trees[cs.talent_tree_index] = orig.tree end
            cs.activated_ability = orig.activated_ability
            cs.passive_ability   = orig.passive_ability
        end
    end
    _talent_swap_originals = {}

    -- Apply current settings
    for _, career_name in ipairs(_ALL_CAREERS) do
        local src_name = mod:get("talent_swap_" .. career_name)
        if src_name and src_name ~= "none" then
            local cs  = CareerSettings[career_name]
            local src = CareerSettings[src_name]
            if cs and src then
                -- Save originals before first modification
                _talent_swap_originals[career_name] = {
                    tree              = TalentTrees[cs.profile_name] and TalentTrees[cs.profile_name][cs.talent_tree_index],
                    activated_ability = cs.activated_ability,
                    passive_ability   = cs.passive_ability,
                }

                -- Swap talent tree slot (read in-place by TalentTrees[profile][tree_idx][tier][col])
                local dst_trees = TalentTrees[cs.profile_name]
                local src_trees = TalentTrees[src.profile_name]
                if dst_trees and src_trees then
                    dst_trees[cs.talent_tree_index] = src_trees[src.talent_tree_index]
                end

                -- Swap career ability and passive (read by CareerUtils at level spawn)
                cs.activated_ability = src.activated_ability
                cs.passive_ability   = src.passive_ability
            end
        end
    end
end

-- ============================================================
-- Career ability: inject action into non-native weapon templates
-- ============================================================
-- CharacterStateHelper._check_chain_action AND _get_chain_action_data both read
-- item_template.actions[action_name]. Non-native weapon templates lack the career
-- action, so the button is silently ignored. We persistently inject the action so
-- both lookups find it. Tracked in _career_action_injections for clean removal.
-- NOTE: BH with non-native ranged weapons has a second blocker — input_override
-- "action_career" isn't wired for non-native weapons. See WORK_ITEMS.md.
local _career_action_injections = {}  -- [tmpl_key][action_name] = true

local function patch_career_actions_on_weapons()
    if not Weapons or not CareerSettings or not ActionTemplates or not ItemMasterList then return end

    -- Remove all previously injected actions first
    for tmpl_key, actions in pairs(_career_action_injections) do
        local tmpl = Weapons[tmpl_key]
        if tmpl and tmpl.actions then
            for action_name in pairs(actions) do
                tmpl.actions[action_name] = nil
            end
        end
    end
    _career_action_injections = {}

    for career, weapons in pairs(_WEAPON_UNLOCK_MAP) do
        local cs = CareerSettings[career]
        if cs then
            local ability_list = cs.activated_ability
            local ability = ability_list and ability_list[1]
            local action_name = ability and ability.action_name
            local action_template = action_name and ActionTemplates[action_name]
            if action_template then
                for _, weapon_key in ipairs(weapons) do
                    if mod:get("unlock_" .. career .. "_" .. weapon_key) then
                        local item = ItemMasterList[weapon_key]
                        local tmpl_key = item and item.template
                        local tmpl = tmpl_key and Weapons[tmpl_key]
                        if tmpl and tmpl.actions and not tmpl.actions[action_name] then
                            tmpl.actions[action_name] = action_template
                            _career_action_injections[tmpl_key] = _career_action_injections[tmpl_key] or {}
                            _career_action_injections[tmpl_key][action_name] = true
                        end
                    end
                end
            end
        end
    end
end

mod.on_game_state_changed = function(status, state_name)
    apply_any_weapon()
    apply_weapon_unlocks()
    apply_talent_swaps()
    patch_career_actions_on_weapons()
end

mod.on_setting_changed = function(setting_id)
    if setting_id == "any_weapon_any_career" then
        apply_any_weapon()
    end
    if setting_id:find("^unlock_") then
        apply_weapon_unlocks()
        patch_career_actions_on_weapons()
    end
    if setting_id:find("^talent_swap_") then
        apply_talent_swaps()
    end
end

-- ============================================================
-- Missing skeleton node guard
-- ============================================================

mod:hook("Unit", "node", function(func, unit, node_name, ...)
    if type(node_name) == "string" and not Unit.has_node(unit, node_name) then
        return 0
    end
    return func(unit, node_name, ...)
end)

-- Crash prevention: nil explosion template.
mod:hook("DamageUtils", "create_explosion", function(func, world, attacker_unit, position, rotation, explosion_template, ...)
    if not explosion_template then return end
    return func(world, attacker_unit, position, rotation, explosion_template, ...)
end)

mod:hook("AreaDamageSystem", "create_explosion", function(func, self, attacker_unit, position, rotation, explosion_template_name, ...)
    if not ExplosionTemplates or not ExplosionTemplates[explosion_template_name] then return false end
    return func(self, attacker_unit, position, rotation, explosion_template_name, ...)
end)

-- ============================================================
-- Cross-career wield animation substitution
-- ============================================================
-- When a career equips a weapon from a different character, the weapon template's
-- wield_anim event (e.g. "to_fencing_sword") doesn't exist on that career's 3P
-- skeleton, so nothing plays.  We intercept Unit.animation_event: if the event is
-- absent we try a chain of per-event fallbacks in order, using the first one the
-- unit actually has.  This is safe because the fallback only fires when the
-- original event is missing — it never redirects events the unit can already play.
-- Wield-anim substitution table.
-- Key = animation event the game tries to fire; value = ordered fallback list.
-- The hook below uses Unit.has_animation_event to pick the first fallback the
-- unit's skeleton actually has.  Only wield-anim events need entries here —
-- attack/aim/reload anims are driven by the weapon action system, not this hook.
--
-- Confirmed working:
--   to_longbow → to_crossbow_loaded: Saltzpyre wields elf/empire longbow with
--     crossbow animation.  Attack/aim/reload still use longbow logic (no fix yet).
-- Confirmed NOT working (skeleton incompatible):
--   to_es_longbow on Saltzpyre — removed; Saltzpyre has no bow anim at all.
-- Unknown / needs probe_3p on elf:
--   to_fencing_sword, to_1h_flail, to_flail_shield on elf skeleton.
local _wield_anim_fallbacks = {
    to_longbow              = { "to_crossbow_loaded", "to_es_longbow" },
    to_fencing_sword        = { "to_sword_and_dagger", "to_1h_sword" },
    to_1h_flail             = { "to_1h_sword" },
    to_flail_shield         = { "to_1h_sword" },
}

mod:hook("Unit", "animation_event", function(func, unit, event_name, ...)
    if not Unit.has_animation_event(unit, event_name) then
        local fallbacks = _wield_anim_fallbacks[event_name]
        if fallbacks then
            for _, fb in ipairs(fallbacks) do
                if Unit.has_animation_event(unit, fb) then
                    pcall(func, unit, fb, ...)
                    return
                end
            end
        end
        return
    end
    pcall(func, unit, event_name, ...)
end)

-- Crash prevention: attachment node mismatches when equipping off-career weapons.
mod:hook("SimpleInventoryExtension", "_wield_slot", function(func, self, equipment, slot_data, unit_1p, unit_3p, buff_extension)
    local ret
    local ok, err = pcall(function() ret = func(self, equipment, slot_data, unit_1p, unit_3p, buff_extension) end)
    if not ok then
        mod:warning("_wield_slot error (slot=%s): %s", tostring(slot_data and slot_data.slot_name), tostring(err))
    end
    return ret
end)

mod:hook("SimpleHuskInventoryExtension", "_wield_slot", function(func, self, world, equipment, slot_name, unit_1p, unit_3p)
    local ret
    local ok, err = pcall(function() ret = func(self, world, equipment, slot_name, unit_1p, unit_3p) end)
    if not ok then
        mod:warning("_wield_slot (husk) error (slot=%s): %s", tostring(slot_name), tostring(err))
    end
    return ret
end)

-- ============================================================
-- Commands
-- ============================================================

-- Probe what 3P animation events exist on the local player's character unit.
-- Run in-game as Saltzpyre to discover which wield anims his state machine supports.
mod:command("probe_3p", "List which ranged wield animation events exist on the local player's 3P unit", function()
    local pm = Managers.player
    local player = pm and pm:local_player()
    local unit = player and player.player_unit
    if not unit then mod:echo("No player unit (must be in a level).") return end

    local candidates = {
        -- Kruber longbow
        "to_es_longbow", "to_es_longbow_noammo",
        -- Elf longbow
        "to_longbow", "to_longbow_noammo",
        -- Saltzpyre crossbow
        "to_crossbow", "to_crossbow_loaded", "to_crossbow_noammo",
        -- Saltzpyre repeating crossbow
        "to_repeating_crossbow", "to_repeating_crossbow_noammo",
        -- Saltzpyre pistols
        "to_brace_of_pistols", "to_wh_brace_of_pistols",
        "to_flintlock_pistol", "to_wh_flintlock_pistol",
        -- Generic
        "to_ranged", "idle_ranged",
    }

    local found = {}
    local missing = {}
    for _, ev in ipairs(candidates) do
        if Unit.has_animation_event(unit, ev) then
            found[#found + 1] = ev
        else
            missing[#missing + 1] = ev
        end
    end

    mod:echo("=== 3P anim events FOUND ===")
    for _, ev in ipairs(found) do mod:echo("  YES: " .. ev) end
    mod:echo("=== MISSING ===")
    for _, ev in ipairs(missing) do mod:echo("  no:  " .. ev) end
end)

mod:command("find_class", "Find global class names matching a pattern", function(pattern)
    pattern = pattern:lower()
    local found = {}
    for k, v in pairs(_G) do
        if type(k) == "string" and k:lower():find(pattern) then
            found[#found + 1] = k .. " (" .. type(v) .. ")"
        end
    end
    table.sort(found)
    for _, s in ipairs(found) do
        mod:echo(s)
    end
end)

mod:command("inspect", "List methods of a global class", function(name)
    local cls = _G[name]
    if not cls then mod:echo("Not found: " .. name) return end
    local found = {}
    for k, v in pairs(cls) do
        if type(v) == "function" then
            found[#found + 1] = k
        end
    end
    table.sort(found)
    for _, s in ipairs(found) do
        mod:echo(s)
    end
end)

-- Dump Weapons template entries matching a pattern and their wield_anim / wield_anim_3p fields.
-- Usage: t dump_templates fencing   (finds all templates whose key contains "fencing")
mod:command("dump_templates", "List Weapons templates matching a pattern with their wield_anim fields", function(pattern)
    pattern = pattern or ""
    if not Weapons then mod:echo("Weapons global not available (load a level first).") return end
    local found = {}
    for key, tmpl in pairs(Weapons) do
        if key:find(pattern) then
            local wield = tostring(tmpl.wield_anim or "nil")
            found[#found+1] = string.format("key=%-45s wield_anim=%s", key, wield)
        end
    end
    table.sort(found)
    if #found == 0 then
        mod:echo("No templates matching '" .. pattern .. "'.")
    else
        mod:echo(string.format("Found %d templates matching '%s':", #found, pattern))
        for _, s in ipairs(found) do mod:echo(s) end
    end
end)

-- Dump Weapons template entries whose key contains "crossbow" and their unit_3p paths.
-- Run in-game after a level loads (Weapons global is populated at level start).
mod:command("dump_crossbow", "Log crossbow weapon templates and their 3P unit paths", function()
    if not Weapons then mod:echo("Weapons global not available (load a level first).") return end
    local found = {}
    for key, tmpl in pairs(Weapons) do
        if key:find("crossbow") then
            found[#found+1] = string.format("key=%-40s unit_3p=%s", key, tostring(tmpl.unit_3p))
        end
    end
    table.sort(found)
    if #found == 0 then
        mod:echo("No crossbow entries found in Weapons global.")
    else
        mod:echo(string.format("Found %d crossbow templates:", #found))
        for _, s in ipairs(found) do mod:echo(s) end
    end
end)

-- Dump ItemMasterList items with a single-career can_wield — these are typically
-- career ability weapons.  Run after a level loads (ItemMasterList must be populated).
mod:command("dump_career_items", "Log items whose can_wield has exactly 1 entry (career ability weapons)", function()
    if not ItemMasterList then mod:echo("ItemMasterList not loaded yet.") return end
    local found = {}
    for key, item in pairs(ItemMasterList) do
        if item.can_wield and #item.can_wield == 1 then
            found[#found+1] = string.format("key=%-40s career=%s", key, item.can_wield[1])
        end
    end
    table.sort(found)
    mod:echo(string.format("Found %d single-career items:", #found))
    for _, s in ipairs(found) do mod:echo(s) end
end)

-- Dump all fields of an ItemMasterList entry to find where unit paths actually live.
mod:command("dump_item", "Dump all fields of an ItemMasterList entry", function(key)
    key = key or "wh_crossbow"
    if not ItemMasterList then mod:echo("ItemMasterList not loaded") return end
    local item = ItemMasterList[key]
    if not item then mod:echo("Key not found: " .. key) return end
    local function dump_table(t, prefix)
        for k, v in pairs(t) do
            local vtype = type(v)
            if vtype == "table" then
                mod:echo(prefix .. tostring(k) .. " = {table}")
                dump_table(v, prefix .. "  ")
            elseif vtype == "function" then
                mod:echo(prefix .. tostring(k) .. " = [function]")
            else
                mod:echo(prefix .. tostring(k) .. " = " .. tostring(v))
            end
        end
    end
    mod:echo("=== ItemMasterList['" .. key .. "'] ===")
    dump_table(item, "  ")
end)

-- Dump BH's activated_ability template structure
mod:command("dump_bh_ability", "Dump BH career ability template fields", function()
    if not CareerSettings then mod:echo("CareerSettings not loaded") return end
    local cs = CareerSettings["wh_bountyhunter"]
    if not cs then mod:echo("wh_bountyhunter not found") return end
    mod:echo("activated_ability type: " .. type(cs.activated_ability))
    if type(cs.activated_ability) == "table" then
        for k, v in pairs(cs.activated_ability) do
            mod:echo("  " .. tostring(k) .. " = " .. (type(v)=="function" and "[function]" or tostring(v)))
        end
    elseif type(cs.activated_ability) == "string" then
        mod:echo("  value: " .. cs.activated_ability)
    end
end)

mod:command("unstuck", "Teleport to nearest living teammate", function()
    local pm = Managers.player
    if not pm then mod:echo("Not in a level.") return end
    local player = pm:local_player()
    if not player then mod:echo("No local player.") return end
    local unit = player.player_unit
    if not unit then mod:echo("No player unit (dead?).") return end

    local target_pos = nil
    for _, p in pairs(pm:players()) do
        if p ~= player and p.player_unit and HEALTH_ALIVE[p.player_unit] then
            target_pos = Unit.local_position(p.player_unit, 0)
            break
        end
    end

    if target_pos then
        local mover = Unit.mover(unit)
        if mover then
            Mover.set_position(mover, target_pos + Vector3(0.5, 0, 0))
        end
        mod:echo("Unstuck!")
    else
        mod:echo("No living teammate found.")
    end
end)

local _godmode = false

mod:command("god", "Toggle godmode (invincibility)", function()
    _godmode = not _godmode
    mod:echo("Godmode " .. (_godmode and "ON" or "OFF"))
end)

mod:command("win", "Complete the current map", function()
    if Managers.state and Managers.state.game_mode then
        Managers.state.game_mode:complete_level()
    else
        mod:echo("No active game mode.")
    end
end)

-- ============================================================
-- Godmode
-- ============================================================

mod:hook("DamageUtils", "add_damage_network", function(func, attacked_unit, ...)
    if _godmode then
        local pm = Managers.player
        local player = pm and pm:local_player()
        local local_unit = player and player.player_unit
        if local_unit and attacked_unit == local_unit then
            return 0
        end
    end
    return func(attacked_unit, ...)
end)

-- ============================================================
-- Coin Multiplier
-- ============================================================

local _granting_starting_coins = false

mod:hook("DeusRunController", "on_soft_currency_picked_up", function(func, self, ...)
    local args = { ... }
    local raw_amount = args[1]

    if type(raw_amount) == "number" and not _granting_starting_coins then
        local multiplier = mod:get("coin_multiplier")
        args[1] = math.max(1, math.floor(raw_amount * multiplier))
        mod:info("Coin pickup: %d -> %d (x%.2f)", raw_amount, args[1], multiplier)
    end

    return func(self, unpack(args))
end)

-- ============================================================
-- Starting Coins
-- ============================================================
-- setup_run fires exactly once when a brand-new Chaos Wastes run begins
-- (not on each map transition or post-game). Perfect hook for run-start grants.

mod:hook_safe("DeusRunController", "setup_run", function(self)
    local starting = mod:get("starting_coins")
    if starting and starting > 0 then
        if self.on_soft_currency_picked_up then
            mod:info("Starting coins: granting %d", starting)
            _granting_starting_coins = true
            self:on_soft_currency_picked_up(starting)
            _granting_starting_coins = false
        end
    end
end)

-- ============================================================
-- Boon Options Count + Boon Filtering
-- ============================================================
-- generate_random_power_ups is called for both shrines (default 4 options)
-- and chests (default 3 options). We distinguish by the count arg value.
-- We also filter disabled boons from the result and support a dump command
-- to discover boon IDs by inspecting the live pool.

local SHRINE_DEFAULT = 4
local CHEST_DEFAULT  = 3

mod._dump_boons = false  -- set true by "t dump_boons" command

mod:command("dump_boons", "Log all boon IDs from the next shrine/chest roll", function()
    mod._dump_boons = true
    mod:echo("Boon dump enabled - open a shrine or chest to capture IDs.")
end)

mod:hook("DeusPowerUpUtils", "generate_random_power_ups", function(func, ...)
    local args = { ... }

    -- Modify count (existing logic)
    local count_idx = nil
    for i, v in ipairs(args) do
        if type(v) == "number" and v >= 1 and v <= 10 then
            count_idx = i
            break
        end
    end

    if count_idx then
        local original = args[count_idx]
        local custom_count

        if original == SHRINE_DEFAULT then
            custom_count = mod:get("shrine_boon_count")
        elseif original == CHEST_DEFAULT then
            custom_count = mod:get("chest_boon_count")
        end

        if custom_count and custom_count ~= original then
            mod:info("Boon options: args[%d]=%d -> %d", count_idx, original, custom_count)
            args[count_idx] = custom_count
        end
    else
        mod:info("Boon options: could not find count arg: %s %s %s %s",
            tostring(args[1]), tostring(args[2]), tostring(args[3]), tostring(args[4]))
    end

    -- Dump input pool for ID discovery
    if mod._dump_boons then
        mod:info("=== BOON POOL DUMP: %d args ===", #args)
        for i, v in ipairs(args) do
            if type(v) == "table" then
                local n = 0
                for _ in pairs(v) do n = n + 1 end
                mod:info("  args[%d] = table (%d entries)", i, n)
                for j, entry in ipairs(v) do
                    if type(entry) == "table" then
                        mod:info("    [%d] name=%s rarity=%s", j,
                            tostring(entry.name), tostring(entry.rarity))
                    else
                        mod:info("    [%d] = %s (%s)", j, tostring(entry), type(entry))
                    end
                end
            else
                mod:info("  args[%d] = %s (%s)", i, tostring(v), type(v))
            end
        end
    end

    -- Remove disabled boons from the draw pool before calling func.
    -- This ensures disabled boons are never drawn in the first place, so the
    -- returned count is always accurate — not reduced by post-draw filtering.
    -- Covers all availability types:
    --   shrine         → shrine shops
    --   cursed_chest   → Chests of Trials
    --   weapon_chest   → in-mission boon altars (power_up type) AND end-of-level grants
    --   terror_event   → terror event rewards
    -- Note: actual weapon generation goes through DeusWeaponGeneration.generate_weapon,
    -- which never calls generate_random_power_ups, so no special-casing is needed.
    local removed_main   = {}  -- {index, boon} removed from DeusPowerUpsArray
    local removed_rarity = {}  -- per-rarity removals from DeusPowerUpsArrayByRarity

    if DeusPowerUpsArray then
        for i = #DeusPowerUpsArray, 1, -1 do
            local boon = DeusPowerUpsArray[i]
            local key  = boon and boon.name and ("disable_boon_" .. boon.name)
            if key and mod:get(key) then
                table.remove(DeusPowerUpsArray, i)
                removed_main[#removed_main + 1] = { index = i, boon = boon }
                mod:info("Pool remove: %s", boon.name)
            end
        end
        if DeusPowerUpsArrayByRarity then
            for rarity, arr in pairs(DeusPowerUpsArrayByRarity) do
                removed_rarity[rarity] = {}
                for i = #arr, 1, -1 do
                    local boon = arr[i]
                    local key  = boon and boon.name and ("disable_boon_" .. boon.name)
                    if key and mod:get(key) then
                        table.remove(arr, i)
                        removed_rarity[rarity][#removed_rarity[rarity] + 1] = { index = i, boon = boon }
                    end
                end
            end
        end
    end

    -- Call original — returns (seed, new_power_ups)
    local new_seed, new_power_ups = func(unpack(args))

    -- Restore removed boons (iterate in reverse to preserve original indices)
    for i = #removed_main, 1, -1 do
        local e = removed_main[i]
        table.insert(DeusPowerUpsArray, e.index, e.boon)
    end
    for rarity, removed in pairs(removed_rarity) do
        local arr = DeusPowerUpsArrayByRarity[rarity]
        for i = #removed, 1, -1 do
            local e = removed[i]
            table.insert(arr, e.index, e.boon)
        end
    end

    -- Dump result for ID discovery
    if mod._dump_boons and type(new_power_ups) == "table" then
        mod:info("=== BOON RESULT DUMP ===")
        for i, boon in ipairs(new_power_ups) do
            if type(boon) == "table" then
                mod:info("  [%d] name=%s rarity=%s", i,
                    tostring(boon.name), tostring(boon.rarity))
            end
        end
        mod._dump_boons = false
        mod:echo("Boon dump complete - check the log for IDs.")
    end

    return new_seed, new_power_ups
end)

-- ============================================================
-- Arc Layout: NaN Fix + Spacing Expansion for Chest of Trials
-- ============================================================
-- The boon arc places N items evenly across a fixed angular span.
-- With a fixed span, more items = smaller gaps → hitbox overlap → crash.
--
-- Shrine (DeusShopView): _shop_item_widgets. Already sized for 4-5; only needs NaN fix.
-- Chest (DeusCursedChestView): _power_up_widgets. Sized for 3; needs expansion for 4-5.
--
-- Expansion formula: each widget offset *= (n-1)/(n_default-1).
-- This stretches the arc so adjacent-item spacing matches the default-count spacing.
-- The background may clip slightly but items will NOT overlap (no crash).

local function fix_arc_nan(widgets)
    -- NaN fix: count=1 → (count-1)=0 → game divides by zero → NaN offset → crash.
    if not widgets or #widgets ~= 1 then return end
    local w = widgets[1]
    if w and w.offset then
        if w.offset[1] ~= w.offset[1] then w.offset[1] = 0 end
        if w.offset[2] ~= w.offset[2] then w.offset[2] = 0 end
    end
end

mod:hook_safe("DeusShopView", "_create_ui_elements", function(self)
    -- Shrine is already sized generously; only guard against the NaN crash.
    fix_arc_nan(self._shop_item_widgets)
end)

-- TODO: Chest background panel clips when boon count > 3. Need to scale up the
-- background scenegraph node to match the expanded arc. Use `t dump_chest_view`
-- then open a chest to find the node names and sizes. See also: DeusShopView for
-- how the shrine handles 4-5 items (its background is already wide enough).
mod:hook_safe("DeusCursedChestView", "create_ui_elements", function(self)
    fix_arc_nan(self._power_up_widgets)
    if mod._dump_chest_view then
        mod._dump_chest_view = false
        mod:info("=== DeusCursedChestView scenegraph ===")
        if self._ui_scenegraph then
            for k, v in pairs(self._ui_scenegraph) do
                if type(v) == "table" then
                    local sx = v.size and v.size[1] or "?"
                    local sy = v.size and v.size[2] or "?"
                    local px = v.position and v.position[1] or "?"
                    local py = v.position and v.position[2] or "?"
                    mod:info("  scenegraph[%s]: size=(%s,%s) pos=(%s,%s)", tostring(k), tostring(sx), tostring(sy), tostring(px), tostring(py))
                else
                    mod:info("  scenegraph[%s] = %s", tostring(k), tostring(v))
                end
            end
        else
            mod:info("  _ui_scenegraph is nil")
        end
        mod:info("=== DeusCursedChestView widget list ===")
        if self._widgets then
            for i, w in ipairs(self._widgets) do
                mod:info("  widget[%d]: name=%s", i, tostring(w and w.name or "?"))
            end
        else
            mod:info("  _widgets is nil")
        end
        mod:info("=== power_up_widgets count: %d ===", self._power_up_widgets and #self._power_up_widgets or 0)
        mod:echo("dump_chest_view complete - check the log.")
    end
end)

mod:command("dump_chest_view", "Dump DeusCursedChestView scenegraph and widget names on next open", function()
    mod._dump_chest_view = true
    mod:echo("dump_chest_view armed - open a Chest of Trials to capture layout data.")
end)

-- ============================================================
-- Friendly Fire Toggle
-- ============================================================
-- On Champion+, ranged FF is on by default. Hook the two gate functions
-- that everything else calls through to suppress it when toggled off.

mod:hook("DamageUtils", "allow_friendly_fire_ranged", function(func, ...)
    if mod:get("disable_friendly_fire") then return false end
    return func(...)
end)

mod:hook("DamageUtils", "allow_friendly_fire_melee", function(func, ...)
    if mod:get("disable_friendly_fire") then return false end
    return func(...)
end)

-- ============================================================
-- Duplicate Career Allowance
-- ============================================================
-- By default the game reserves each hero (profile) for exactly one player.
-- When a joining player's wanted hero is taken, they get redirected to a free
-- one. Three hooks suppress that enforcement:
--
-- 1. ProfileSynchronizer.get_profile_index_reservation — make the wanted hero
--    always appear unoccupied so handle_profile_delegation_for_joining_player
--    keeps the player on their chosen hero.
-- 2. ProfileSynchronizer.try_reserve_profile_for_peer — if the reservation
--    state still rejects the request (another peer holds the slot in state),
--    return true anyway so assign_full_profile proceeds per-peer correctly.
-- 3. ProfileSynchronizer.is_free_in_lobby — unblock the profile picker UI so
--    players can select an already-chosen hero from the lobby popup.

mod:hook("ProfileSynchronizer", "get_profile_index_reservation", function(func, self, party_id, profile_index)
    if mod:get("allow_duplicate_careers") then return nil, nil end
    return func(self, party_id, profile_index)
end)

mod:hook("ProfileSynchronizer", "try_reserve_profile_for_peer", function(func, self, party_id, peer_id, profile_index, career_index)
    local result = func(self, party_id, peer_id, profile_index, career_index)
    if result then return true end
    -- func returned false: profile is reserved by another peer.
    -- When duplicate careers are allowed, let it proceed without touching state.
    if mod:get("allow_duplicate_careers") then return true end
    return false
end)

mod:hook("ProfileSynchronizer", "is_free_in_lobby", function(func, profile_index, lobby_data, optional_party_id)
    if mod:get("allow_duplicate_careers") then return true end
    return func(profile_index, lobby_data, optional_party_id)
end)

-- ============================================================
-- Curse Disabling
-- ============================================================

local function is_curse_disabled(curse_name)
    if type(curse_name) ~= "string" or not curse_name:find("^curse_") then return false end
    local key = "disable_curse_" .. curse_name:gsub("^curse_", "")
    return mod:get(key) == true
end

-- Gate 1: MutatorHandler._activate_mutator — suppresses the curse effect itself.
mod:hook("MutatorHandler", "_activate_mutator", function(func, self, name, ...)
    if is_curse_disabled(name) then
        mod:echo("Suppressed curse: " .. name)
        return
    end
    return func(self, name, ...)
end)

-- Gate 2: DeusMechanism.get_current_node_curse — suppresses the popup (DeusCurseUI)
-- and prevents flow_callback_set_deus_curse_active from ever activating the curse.
mod:hook("DeusMechanism", "get_current_node_curse", function(func, self, ...)
    local curse = func(self, ...)
    if is_curse_disabled(curse) then return nil end
    return curse
end)

-- Gate 3: DeusMapDecisionView._enable_hover — hides the chaos god icon/text in
-- the map tooltip for nodes whose curse is disabled.
-- Gate 4: DeusMechanism._transition_next_node — clears current_node.curse before
-- get_next_level_data runs so curse packages are never loaded (prevents sky/env effects).
mod:hook("DeusMechanism", "_transition_next_node", function(func, self, next_node_key, ...)
    local drc = self._deus_run_controller
    local graph_data = drc and drc:get_graph_data()
    local node = graph_data and graph_data[next_node_key]
    local saved_curse = node and node.curse

    if saved_curse and is_curse_disabled(saved_curse) then
        mod:info("Clearing curse from node before level load: %s", saved_curse)
        node.curse = nil
    end

    local results = { func(self, next_node_key, ...) }

    if saved_curse and is_curse_disabled(saved_curse) then
        node.curse = saved_curse
    end

    return unpack(results)
end)

-- Gate 5: DeusMechanism.start_next_round — clears current_node.curse before the
-- mutators list is built so the curse mutator is never activated in-game.
-- Also clears current_node.theme to suppress god-themed sky/shader mutators
-- that load from DeusThemeSettings[theme].mutators. Theme is reset to "wastes"
-- (the neutral no-god theme) so the visual effects don't load either.
mod:hook("DeusMechanism", "start_next_round", function(func, self, ...)
    local drc = self._deus_run_controller
    local current_node = drc and drc:get_current_node()
    local saved_curse = current_node and current_node.curse
    local saved_theme = current_node and current_node.theme

    if saved_curse and is_curse_disabled(saved_curse) then
        mod:info("Clearing curse+theme from node before mutator build: %s", saved_curse)
        current_node.curse = nil
        current_node.theme = "wastes"
    end

    local results = { func(self, ...) }

    if saved_curse and is_curse_disabled(saved_curse) then
        current_node.curse = saved_curse
        current_node.theme = saved_theme
    end

    return unpack(results)
end)

mod:hook("DeusMapDecisionView", "_enable_hover", function(func, self, node_key, ...)
    local graph_data = self._deus_run_controller and self._deus_run_controller:get_graph_data()
    local node = graph_data and graph_data[node_key]
    if node and is_curse_disabled(node.curse) then
        local saved_theme = node.theme
        node.theme = nil
        func(self, node_key, ...)
        node.theme = saved_theme
        return
    end
    return func(self, node_key, ...)
end)

-- ============================================================
-- Boon Localization — auto-name from game data
-- ============================================================
-- DeusPowerUpTemplates[name].display_name is the real in-game localization key.
-- Managers.localization:append_backend_localizations() writes directly into the
-- table that Localize() checks first, so subsequent mod:localize(setting_id)
-- calls (which VMF falls back to Localize() for unknown keys) return correct names.
-- Also patches mod._localization directly in case VMF uses its own lookup table.

local _boon_loc_patched = false

local function patch_boon_localization()
    if _boon_loc_patched then return end
    if not DeusPowerUpTemplates or not DeusPowerUpsArray then return end
    _boon_loc_patched = true

    local injections = {}
    for _, entry in ipairs(DeusPowerUpsArray) do
        local name = entry.name
        if name then
            local template = DeusPowerUpTemplates[name]
            local display_key = template and template.display_name
            local display_name
            if display_key then
                local raw = Localize(display_key)
                -- Localize returns "<key>" when not found; discard that
                if raw ~= "<" .. display_key .. ">" then
                    display_name = raw
                end
            end
            display_name = display_name or name
            injections["disable_boon_" .. name] = display_name
            injections["start_boon_"   .. name] = display_name
        end
    end

    -- Inject into game's localization backend (VMF falls back to Localize())
    if Managers.localization then
        Managers.localization:append_backend_localizations(injections)
    end

    -- Also patch VMF's own localization table directly, in case it doesn't
    -- fall back to Localize() for settings it already has entries for.
    if type(mod._localization) == "table" then
        for key, display_name in pairs(injections) do
            if not mod._localization[key] then
                mod._localization[key] = {}
            end
            mod._localization[key].en = display_name
        end
    end
end

mod:hook_safe("DeusRunController", "init", function()
    patch_boon_localization()
end)

-- ============================================================
-- Starting Boons
-- ============================================================
-- Runs after _add_initial_power_ups so career talents are already set.
-- Looks up rarity from DeusPowerUpsArray (the live boon pool) — disabled boons
-- are only removed from the pool during generate_random_power_ups calls and
-- always restored immediately, so the pool is complete here. This means
-- a boon can be in both the disable list and the start list: it won't appear
-- at shrines/chests, but the player still receives it at run start.

mod:hook_safe("DeusRunController", "_add_initial_power_ups", function(self, peer_id, local_player_id, profile_index, career_index)
    local run_state = self._run_state
    local own_peer_id = run_state and run_state:get_own_peer_id()

    -- On the server: grant boons for any peer (host's own init + client inits via rpc_deus_set_initial_setup).
    -- On a client: only grant for own peer (local path; host will authoritative-set anyway).
    if not run_state:is_server() and peer_id ~= own_peer_id then return end
    if not DeusPowerUpsArray or not DeusPowerUpUtils then return end

    -- Build rarity lookup from the live pool so we never need a hardcoded map.
    local rarity_of = {}
    for _, entry in ipairs(DeusPowerUpsArray) do
        local name = entry.name
        if name and not rarity_of[name] then
            rarity_of[name] = entry.rarity
        end
    end

    local extra = {}
    for _, entry in ipairs(DeusPowerUpsArray) do
        local name = entry.name
        if name and mod:get("start_boon_" .. name) then
            extra[#extra + 1] = DeusPowerUpUtils.generate_specific_power_up(name, entry.rarity)
            mod:info("Starting boon: %s (%s)", name, entry.rarity)
        end
    end

    if #extra == 0 then return end

    local skip_metatable = true
    local existing = run_state:get_player_power_ups(peer_id, local_player_id, profile_index, career_index)
    local new_power_ups = table.clone(existing, skip_metatable)
    table.append(new_power_ups, extra)
    run_state:set_player_power_ups(peer_id, local_player_id, profile_index, career_index, new_power_ups)
    mod:echo(string.format("Granted %d starting boon(s).", #extra))
end)

-- ============================================================
-- Weapon Chest Distribution
-- ============================================================
-- Each level's in-mission weapon chests are lazily typed when first opened.
-- The type list (upgrade/swap_melee/swap_ranged/power_up) is built from
-- LevelSettings[level_key].deus_weapon_chest_distribution on first use, then
-- cached in self._deus_weapon_chest_distribution for the rest of that level.
-- We intercept the rebuild step to substitute our own counts.

mod:hook("DeusRunController", "get_deus_weapon_chest_type", function(func, self)
    local chest_distribution = self._deus_weapon_chest_distribution

    if (not chest_distribution or #chest_distribution == 0) and DEUS_CHEST_TYPES then
        local upgrade  = mod:get("chest_upgrade_count")
        local swap_m   = mod:get("chest_swap_melee_count")
        local swap_r   = mod:get("chest_swap_ranged_count")
        local power_up = mod:get("chest_power_up_count")

        -- Only override if any count differs from the original defaults
        local sig_default = { upgrade = 1, swap_melee = 1, swap_ranged = 1, power_up = 2 }
        local is_custom = upgrade  ~= sig_default.upgrade
                       or swap_m   ~= sig_default.swap_melee
                       or swap_r   ~= sig_default.swap_ranged
                       or power_up ~= sig_default.power_up

        if is_custom then
            local dist = {}
            for _ = 1, upgrade  do dist[#dist + 1] = DEUS_CHEST_TYPES.upgrade    end
            for _ = 1, swap_m   do dist[#dist + 1] = DEUS_CHEST_TYPES.swap_melee end
            for _ = 1, swap_r   do dist[#dist + 1] = DEUS_CHEST_TYPES.swap_ranged end
            for _ = 1, power_up do dist[#dist + 1] = DEUS_CHEST_TYPES.power_up   end

            if #dist > 0 then
                local run_state = self._run_state
                local node_key  = run_state and run_state:get_current_node_key()
                local path_graph = self:_get_graph_data()
                local node = path_graph and node_key and path_graph[node_key]
                local seed  = node and HashUtils and HashUtils.fnv32_hash(node.level_seed) or 0
                table.shuffle(dist, seed)

                self._deus_weapon_chest_distribution = dist
                local chest_type = dist[#dist]
                dist[#dist] = nil
                return chest_type
            end
        end
    end

    return func(self)
end)

-- ============================================================
-- Banned Weapon Traits + Any Trait on Any Weapon
-- ============================================================
-- Before generation/upgrade, temporarily replace each weapon's
-- baked_trait_combinations with a (possibly expanded, possibly filtered) pool,
-- then restore immediately after.
--
-- any_trait_any_weapon: gives every weapon the union of all weapons' combos.
-- ban_trait_*: strips combos containing that trait from the effective pool.

local _all_trait_combos_cache = nil

local function get_all_trait_combos()
    if _all_trait_combos_cache then return _all_trait_combos_cache end
    if not DeusWeapons then return nil end
    local all_combos = {}
    local seen = {}
    for _, data in pairs(DeusWeapons) do
        local combos = data.baked_trait_combinations
        if combos then
            for _, combo in ipairs(combos) do
                local key = table.concat(combo, "\0")
                if not seen[key] then
                    seen[key] = true
                    all_combos[#all_combos + 1] = combo
                end
            end
        end
    end
    _all_trait_combos_cache = all_combos
    return all_combos
end

local function apply_weapon_trait_filter()
    if not DeusWeapons then return {} end
    local any_trait = mod:get("any_trait_any_weapon")
    local expanded_pool = any_trait and get_all_trait_combos()
    local saved = {}

    for item_key, data in pairs(DeusWeapons) do
        local original = data.baked_trait_combinations
        local base = expanded_pool or original
        if not base then break end

        -- Apply ban filter to the effective pool
        local filtered = {}
        for _, combo in ipairs(base) do
            local ok = true
            for _, trait in ipairs(combo) do
                if mod:get("ban_trait_" .. trait) then
                    ok = false
                    break
                end
            end
            if ok then
                filtered[#filtered + 1] = combo
            end
        end

        -- Determine new value to install:
        --   filtered if we removed some AND alternatives remain
        --   base     if any_trait expanded it but nothing was banned
        --   nil      if nothing changed
        local new_val
        if #filtered < #base and #filtered > 0 then
            new_val = filtered                   -- filtered down
        elseif #filtered == 0 then
            new_val = base                       -- all banned: safety, keep original pool
        elseif base ~= original then
            new_val = base                       -- expanded by any_trait, no bans
        end

        if new_val and new_val ~= original then
            saved[item_key] = original
            data.baked_trait_combinations = new_val
        end
    end
    return saved
end

local function restore_weapon_trait_filter(saved)
    if not DeusWeapons then return end
    for item_key, original in pairs(saved) do
        DeusWeapons[item_key].baked_trait_combinations = original
    end
end

mod:hook("DeusWeaponGeneration", "generate_weapon", function(func, ...)
    local saved = apply_weapon_trait_filter()
    local result = func(...)
    restore_weapon_trait_filter(saved)
    return result
end)

mod:hook("DeusWeaponGeneration", "generate_weapon_for_slot", function(func, ...)
    local saved = apply_weapon_trait_filter()
    local result = func(...)
    restore_weapon_trait_filter(saved)
    return result
end)

mod:hook("DeusWeaponGeneration", "upgrade_item", function(func, ...)
    local saved = apply_weapon_trait_filter()
    local result = func(...)
    restore_weapon_trait_filter(saved)
    return result
end)

-- ============================================================
-- Run Structure: Force Belakor + Finale God Override
-- ============================================================
-- _setup_run is called on the host immediately after the run parameters are
-- resolved (dominant_god from vote/backend, with_belakor from backend cycle).
-- We intercept on the host (is_server=true) to override those values before
-- they are synced to clients via rpc_deus_setup_run.
--
-- Dominant god values: 1=Nurgle, 2=Tzeentch, 3=Khorne, 4=Slaanesh, 0=default.

local _FINALE_GODS = { "nurgle", "tzeentch", "khorne", "slaanesh" }

mod:hook("DeusMechanism", "_setup_run", function(func, self, run_id, run_seed, is_server, server_peer_id, difficulty, journey_name, dominant_god, with_belakor, mutators, boons)
    if is_server then
        if mod:get("force_belakor") then
            with_belakor = true
        end

        local god_idx = mod:get("finale_dominant_god")
        if god_idx and god_idx > 0 then
            local god = _FINALE_GODS[god_idx]
            if god then
                dominant_god = god
                mod:info("Finale god override: %s", god)
            end
        end
    end

    return func(self, run_id, run_seed, is_server, server_peer_id, difficulty, journey_name, dominant_god, with_belakor, mutators, boons)
end)

-- ============================================================
-- Pickup Spawn Counts (Weapon Altars, Chests of Trials, Arena Ammo)
-- + Campaign Potions in Chaos Wastes
-- ============================================================
-- Altar/chest counts: patch DEUS_LEVEL_PICKUP_SETTINGS presets.
-- Arena ammo: patch the current level's pickup_settings via LevelHelper
--   (handles both shared default_arena_pickup_settings and arena_belakor's
--   inline table); arena = primary with no deus_weapon_chest field.
-- Campaign potions: temporarily inject damage/speed/cooldown potions into
--   Pickups.deus_potions so they can appear alongside Chaos Wastes potions.
--   All three have spawn_weighting=0.2 (same as deus potions), safe to add.

mod:hook("PickupSystem", "populate_pickups", function(func, self, ...)
    if not LevelHelper then return func(self, ...) end

    local altar_total  = mod:get("chest_upgrade_count")
                       + mod:get("chest_swap_melee_count")
                       + mod:get("chest_swap_ranged_count")
                       + mod:get("chest_power_up_count")
    local cursed_count = mod:get("cursed_chest_count")
    local arena_ammo   = mod:get("arena_ammo_count")
    local potions_on   = mod:get("enable_campaign_potions")

    local altar_custom  = altar_total  ~= 5  -- default: 1+1+1+2
    local cursed_custom = cursed_count ~= 1  -- default: 1
    local ammo_custom   = arena_ammo   ~= 2  -- default: 2

    if not altar_custom and not cursed_custom and not ammo_custom and not potions_on then
        return func(self, ...)
    end

    -- Patch via LevelHelper:current_level_settings() — works for both preset
    -- references (e.g. default_signature_pickup_settings) and inline tables
    -- (e.g. arena_belakor). This is the same table populate_pickups will read.
    -- Arenas are identified by absence of deus_weapon_chest (no altars on arenas).
    local saved = {}
    local cur = LevelHelper:current_level_settings()
    local cur_ps = cur and cur.pickup_settings
    if cur_ps then
        for _, diff_data in pairs(cur_ps) do
            if type(diff_data) == "table" and diff_data.primary then
                local p = diff_data.primary
                local is_arena = p.deus_weapon_chest == nil
                local entry = { tbl = p }

                if not is_arena then
                    if altar_custom and p.deus_weapon_chest ~= nil then
                        entry.deus_weapon_chest = p.deus_weapon_chest
                        p.deus_weapon_chest = altar_total
                    end
                    if cursed_custom and p.deus_cursed_chest ~= nil then
                        entry.deus_cursed_chest = p.deus_cursed_chest
                        p.deus_cursed_chest = cursed_count
                    end
                else
                    if ammo_custom and p.ammo ~= nil then
                        entry.ammo = p.ammo
                        p.ammo = arena_ammo
                    end
                end

                if entry.deus_weapon_chest ~= nil
                or entry.deus_cursed_chest ~= nil
                or entry.ammo            ~= nil then
                    saved[#saved + 1] = entry
                end
            end
        end
    end

    -- Inject campaign potions into Pickups.deus_potions.
    local added_potions = {}
    if potions_on and Pickups and Pickups.deus_potions and Pickups.potions then
        for _, name in ipairs({ "damage_boost_potion", "speed_boost_potion", "cooldown_reduction_potion" }) do
            if Pickups.potions[name] and not Pickups.deus_potions[name] then
                Pickups.deus_potions[name] = Pickups.potions[name]
                added_potions[#added_potions + 1] = name
            end
        end
    end

    local results = { func(self, ...) }

    -- Restore everything.
    for _, entry in ipairs(saved) do
        local p = entry.tbl
        if entry.deus_weapon_chest ~= nil then p.deus_weapon_chest = entry.deus_weapon_chest end
        if entry.deus_cursed_chest ~= nil then p.deus_cursed_chest = entry.deus_cursed_chest end
        if entry.ammo              ~= nil then p.ammo              = entry.ammo              end
    end
    for _, name in ipairs(added_potions) do
        Pickups.deus_potions[name] = nil
    end

    return unpack(results)
end)
