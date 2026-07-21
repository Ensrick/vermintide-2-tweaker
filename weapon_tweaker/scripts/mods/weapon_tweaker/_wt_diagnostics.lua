-- _wt_diagnostics.lua -- diagnostic dump/probe commands and wield boundary.
--
-- Owns the pure-diagnostic commands split out of the god file in the
-- v0.12.209-dev Phase 1 OOP decomposition: /sm_probe, /dump, /dump_actions,
-- /dump_weapons, /wt_dump_wielded, plus the wield-time weapon-data dump and its
-- SimpleInventoryExtension._wield_slot hook_safe. All read engine globals
-- (Managers / SPProfiles / ScriptUnit / Weapons / ItemMasterList / Localize) and
-- Public-beta commands remain read-only support surfaces. The sole wield hook
-- also invokes WT's idempotent career-action reconciliation for the effective
-- runtime template (#661); tuning and coverage commands remain dev-only.
--
-- Owned by: weapon_tweaker.lua entry point. Consumed via: mod:dofile.
-- Wield-time mutation is deliberately owned by _wt_weapon_action_lifecycle.lua;
-- this module owns only explicit, read-only diagnostic commands.

local mod = get_mod("wt")

-- Keys are profile/character names. Warrior Priest (wh_priest career) shares
-- the witch_hunter profile but uses a distinct 3P skeleton, so it's listed
-- separately under its own key for `wt sm_probe`. Note: "way_watcher" is the
-- path for `we_` careers — VT2's source uses this naming.
local _3p_state_machine_paths = {
    empire_soldier            = "units/beings/player/third_person_base/empire_soldier/chr_third_person_base",
    witch_hunter              = "units/beings/player/third_person_base/witch_hunter/chr_third_person_base",
    witch_hunter_warrior_priest = "units/beings/player/third_person_base/witch_hunter_warrior_priest/chr_third_person_base",
    bright_wizard             = "units/beings/player/third_person_base/bright_wizard/chr_third_person_base",
    dwarf_ranger              = "units/beings/player/third_person_base/dwarf_ranger/chr_third_person_base",
    wood_elf                  = "units/beings/player/third_person_base/way_watcher/chr_third_person_base",
}

mod:command("sm_probe", "Probe what 3P state machine resources exist for all characters", function()
    local pm = Managers.player
    local player = pm and pm:local_player()
    if not player or not player.player_unit then
        mod:echo("No player unit")
        return
    end
    local unit_3p = player.player_unit
    local pkg = Managers.package

    local function log(msg)
        mod:echo(msg)
        mod:info("[PROBE] %s", msg)
    end

    for name, path in pairs(_3p_state_machine_paths) do
        local loaded = "?"
        if pkg then
            local ok_c, val = pcall(function() return pkg:has_loaded(path, "global") end)
            if ok_c then loaded = tostring(val)
            else loaded = "err" end
        end
        log(string.format("  %-16s loaded=%s", name, loaded))
    end

    local ok_sm, has_sm = pcall(Unit.has_animation_state_machine, unit_3p)
    log("3P has_animation_state_machine: " .. (ok_sm and tostring(has_sm) or "err"))

    local test_events = {
        "to_2h_sword", "to_2h_sword_we", "to_bastard_sword", "to_spear", "to_polearm",
        "to_1h_sword", "to_1h_hammer", "to_2h_billhook", "to_longbow", "to_es_longbow",
        "to_1h_sword_shield", "to_1h_hammer_shield", "to_dual_wield", "to_2h_hammer",
        "to_2h_axe", "to_1h_axe", "to_1h_falchion", "to_1h_flail", "to_crossbow",
        "to_repeating_crossbow", "to_handgun", "to_blunderbuss",
        "attack_swing_right", "attack_swing_left", "attack_swing_down",
        "attack_swing_up_left", "attack_swing_down_left", "attack_swing_down_right",
        "attack_swing_heavy", "attack_swing_heavy_right", "attack_swing_heavy_left",
        "attack_swing_heavy_down", "attack_swing_heavy_left_diagonal",
        "attack_swing_heavy_right_diagonal",
        "attack_swing_charge", "attack_swing_charge_left", "attack_swing_charge_right",
        "attack_swing_charge_left_diagonal", "attack_swing_charge_right_diagonal_pose",
        "attack_swing_charge_down_pose", "attack_swing_charge_left_diagonal_pose",
        "attack_swing_charge_stab", "attack_swing_charge_down",
        "attack_swing_stab", "attack_swing_stab_02", "attack_swing_stab_lh",
        "attack_swing_left_diagonal", "attack_swing_down_left_axe",
        "attack_push", "push_stab", "parry_pose",
    }
    log("Events on 3P unit:")
    for _, ev in ipairs(test_events) do
        local ok_e, has = pcall(Unit.has_animation_event, unit_3p, ev)
        if ok_e and has then
            log(string.format("  %-40s TRUE", ev))
        else
            log(string.format("  %-40s false", ev))
        end
    end
end)

mod:command("dump", "Dump equipped item data to log", function()
    local player = Managers.player:local_player()
    if not player then
        mod:echo("No local player found")
        return
    end

    local profile_index = player:profile_index()
    local profile = SPProfiles[profile_index]
    local career_index = player:career_index()
    local career = profile.careers[career_index]
    local career_name = career.name

    mod:echo("Career: " .. tostring(career_name))
    mod:info("=== EQUIPPED ITEM DUMP for %s ===", career_name)

    local inventory_ext = ScriptUnit.extension(player.player_unit, "inventory_system")
    local equipment = inventory_ext and inventory_ext:equipment()
    if not equipment or not equipment.slots then
        mod:echo("No equipment data available")
        return
    end

    for slot_name, slot_data in pairs(equipment.slots) do
        if slot_data.item_data then
            local item = slot_data.item_data
            local key = item.key or "?"
            local item_type = item.item_type or item.data and item.data.item_type or "?"
            local template = item.template or item.data and item.data.template or "?"
            local rarity = item.rarity or "?"
            local left = item.left_hand_unit or item.data and item.data.left_hand_unit or "none"
            local right = item.right_hand_unit or item.data and item.data.right_hand_unit or "none"

            mod:echo("%s: %s (%s)", slot_name, key, item_type)
            mod:info("[%s] key=%s  item_type=%s  template=%s  rarity=%s", slot_name, key, item_type, template, rarity)
            mod:info("[%s] left_hand_unit=%s", slot_name, left)
            mod:info("[%s] right_hand_unit=%s", slot_name, right)

            if item.can_wield then
                mod:info("[%s] can_wield=%s", slot_name, table.concat(item.can_wield, ", "))
            end

            if item.data then
                for data_key, data_val in pairs(item.data) do
                    if type(data_val) ~= "table" then
                        mod:info("[%s] data.%s=%s", slot_name, tostring(data_key), tostring(data_val))
                    end
                end
            end
        end
    end

    mod:info("=== END EQUIPPED ITEM DUMP ===")
    mod:echo("Dump written to log")
end)

mod:command("dump_actions", "Dump weapon action anim events (usage: /dump_actions [pattern])", function(pattern)
    pattern = pattern or ""
    if not Weapons then mod:echo("Weapons not loaded yet.") return end
    local tmpl_count = 0
    local action_count = 0
    local sorted_keys = {}
    for tmpl_key, _ in pairs(Weapons) do
        if tmpl_key:find(pattern, 1, true) then
            sorted_keys[#sorted_keys + 1] = tmpl_key
        end
    end
    table.sort(sorted_keys)
    for _, tmpl_key in ipairs(sorted_keys) do
        local tmpl = Weapons[tmpl_key]
        local header = "=== " .. tmpl_key .. " (wield_anim=" .. tostring(tmpl.wield_anim) .. ") ==="
        mod:echo(header)
        mod:info(header)
        tmpl_count = tmpl_count + 1
        if tmpl.actions then
            for action_name, action_data in pairs(tmpl.actions) do
                for sub_name, sub in pairs(action_data) do
                    if type(sub) == "table" and (sub.anim_event or sub.anim_event_3p) then
                        local ae = tostring(sub.anim_event or "-")
                        local ae3 = tostring(sub.anim_event_3p or "-")
                        local line = "  " .. action_name .. "." .. sub_name .. "  1P=" .. ae .. "  3P=" .. ae3
                        mod:echo(line)
                        mod:info(line)
                        action_count = action_count + 1
                    end
                end
            end
        end
    end
    local summary = "dump_actions: " .. tmpl_count .. " templates, " .. action_count .. " actions"
    mod:echo(summary)
    mod:info(summary)
end)

mod:command("dump_weapons", "Dump all weapons with native careers and localized names", function()
    if not ItemMasterList then mod:echo("ItemMasterList not loaded.") return end
    local Localize = Localize
    local count = 0
    local total = 0
    local types_seen = {}
    local sorted = {}
    for key, item in pairs(ItemMasterList) do
        total = total + 1
        local t = item.item_type or item.slot_type or "nil"
        types_seen[t] = (types_seen[t] or 0) + 1
        if item.can_wield then
            sorted[#sorted + 1] = key
        end
    end
    table.sort(sorted)
    mod:echo("ItemMasterList: " .. total .. " total, " .. #sorted .. " with can_wield")
    local type_parts = {}
    for t, c in pairs(types_seen) do type_parts[#type_parts + 1] = t .. "=" .. c end
    mod:info("Types: " .. table.concat(type_parts, ", "))
    mod:info("=== WEAPON DUMP: key | item_type | slot_type | display_name | can_wield ===")
    for _, key in ipairs(sorted) do
        local item = rawget(ItemMasterList, key)
        local display = key
        if item.display_name then
            local ok, loc = pcall(Localize, item.display_name)
            if ok and loc then display = loc end
        end
        local wield = table.concat(item.can_wield, ",")
        local it = tostring(item.item_type or "nil")
        local st = tostring(item.slot_type or "nil")
        local line = key .. " | " .. it .. " | " .. st .. " | " .. display .. " | " .. wield
        mod:info(line)
        count = count + 1
    end
    mod:info("=== END WEAPON DUMP: %d weapons ===", count)
    mod:echo("Dumped " .. count .. " weapons to log")
end)

-- ============================================================
-- Wield-time weapon-data dump  (v0.12.90-dev)
-- ============================================================
-- When `enable_debug_logging` is ON, every local-player wield emits a
-- structured dump of the wielded weapon's ItemMasterList entry: animations,
-- state machines, can_wield list, resolved unit paths. Lets the user (and
-- Claude) read the log to see exactly what wt sees the moment a weapon is
-- equipped -- useful for diagnosing "weapon X isn't available on career Y"
-- or "wrong 3P anim on cross-character port" without in-game repro.
--
-- Also exposed as `/wt_dump_wielded` for one-shot dumps of the currently
-- held weapon (forces a dump regardless of the toggle).
local function _wt_dump_weapon_data(item_key, source)
    if type(item_key) ~= "string" or item_key == "" then
        mod:debug("[wt:wield_dump] no item_key (source=%s)", tostring(source))
        return
    end
    local iml = rawget(_G, "ItemMasterList")
    local entry = iml and rawget(iml, item_key)
    if type(entry) ~= "table" then
        mod:debug("[wt:wield_dump] %s (source=%s) -- no ItemMasterList entry",
            item_key, tostring(source))
        return
    end
    mod:debug("[wt:wield_dump] === %s (source=%s) ===", item_key, tostring(source))
    mod:debug("[wt:wield_dump]   slot_type=%s item_type=%s template=%s",
        tostring(entry.slot_type), tostring(entry.item_type), tostring(entry.template))
    mod:debug("[wt:wield_dump]   display_name=%s inventory_icon=%s required_dlc=%s",
        tostring(entry.display_name), tostring(entry.inventory_icon),
        tostring(entry.required_dlc))
    mod:debug("[wt:wield_dump]   anim_event=%s wield_anim=%s",
        tostring(entry.anim_event), tostring(entry.wield_anim))
    mod:debug("[wt:wield_dump]   anim_event_3p=%s wield_anim_3p=%s",
        tostring(entry.anim_event_3p), tostring(entry.wield_anim_3p))
    mod:debug("[wt:wield_dump]   state_machine=%s state_machine_3p=%s",
        tostring(entry.state_machine), tostring(entry.state_machine_3p))
    if type(entry.can_wield) == "table" then
        mod:debug("[wt:wield_dump]   can_wield=[%s]",
            table.concat(entry.can_wield, ","))
    end
    if entry.left_hand_unit or entry.right_hand_unit then
        mod:debug("[wt:wield_dump]   1p left=%s right=%s",
            tostring(entry.left_hand_unit), tostring(entry.right_hand_unit))
    end
    if entry.left_hand_unit_3p or entry.right_hand_unit_3p then
        mod:debug("[wt:wield_dump]   3p left=%s right=%s",
            tostring(entry.left_hand_unit_3p), tostring(entry.right_hand_unit_3p))
    end
end

WT.dump_weapon_data = _wt_dump_weapon_data

mod:command("wt_dump_wielded",
    "Dump everything wt knows about the currently wielded weapon.",
    function()
        local pm = Managers.player
        local lp = pm and pm:local_player()
        local punit = lp and lp.player_unit
        if not punit then
            mod:echo("[wt_dump_wielded] no local player unit")
            return
        end
        local inv = ScriptUnit.has_extension(punit, "inventory_system")
        if not inv then
            mod:echo("[wt_dump_wielded] no inventory extension")
            return
        end
        local slot = inv.get_wielded_slot_name and inv:get_wielded_slot_name()
        local slot_data = slot and inv.get_slot_data and inv:get_slot_data(slot)
        local item_key = slot_data
            and (slot_data.id
                or (slot_data.item_data and slot_data.item_data.key))
        _wt_dump_weapon_data(item_key, "command")
        mod:echo("[wt_dump_wielded] dumped %s -- see console log",
            tostring(item_key))
    end)
