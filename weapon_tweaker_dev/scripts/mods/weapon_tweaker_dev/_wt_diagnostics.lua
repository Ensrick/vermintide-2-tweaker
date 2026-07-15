-- _wt_diagnostics.lua -- read-only diagnostic dump/probe chat commands.
--
-- Owns the pure-diagnostic commands split out of the god file in the
-- v0.12.209-dev Phase 1 OOP decomposition: /sm_probe, /dump, /dump_actions,
-- /dump_weapons, /wt_dump_wielded, plus the wield-time weapon-data dump and its
-- SimpleInventoryExtension._wield_slot hook_safe. All read engine globals
-- (Managers / SPProfiles / ScriptUnit / Weapons / ItemMasterList / Localize) and
-- never touch the anim-remap state or mutate mod state. Public-beta commands
-- are intentionally read-only support surfaces; tuning and coverage commands
-- live only in the friends-only dev stream.
--
-- Owned by: weapon_tweaker.lua entry point. Consumed via: mod:dofile.
-- Registers the sole (SimpleInventoryExtension, _wield_slot) hook repo-wide.

local mod = get_mod("wt_dev")
-- WT_DEV_OVERLAY_BEGIN:port-coverage-audits
-- #109: audit the live Kruber unlock source rather than maintaining another
-- hand-counted tracker.  This runs once at module load, writes only to the log,
-- and is also callable on demand.  "Hidden" means the port is correctly tagged
-- [needs animations] but lacks the static picker tables required to tune it.
local function _audit_kruber_3p(log_rows)
    local wt = mod._wt or {}
    local status = wt.port_status
    local unlocks = wt.weapon_unlock_map and wt.weapon_unlock_map.es_mercenary
    if not status or type(status.audit_cross_character) ~= "function" or not unlocks then
        mod:warning("[wt:109] Kruber 3P audit unavailable (status/unlock source missing)")
        return nil
    end

    local rows, counts = status.audit_cross_character("es_mercenary", unlocks)
    mod:info("[wt:109] Kruber 3P ports=%d working=%d needs_anims=%d untested=%d picker=%d hidden_needs_anims=%d",
        counts.total, counts.working, counts.needs_animations, counts.untested,
        counts.picker_visible, counts.hidden_needs_animations)
    if log_rows then
        for _, row in ipairs(rows) do
            if row.status ~= "[working]" then
                mod:info("[wt:109] key=%s status=%s target=%s picker=%s",
                    row.weapon_key, row.status, tostring(row.redirect),
                    tostring(row.picker_visible))
            end
        end
    end
    return counts
end

_audit_kruber_3p(false)

mod:command("wt_audit_kruber_3p",
    "Log the complete Kruber cross-character 3P coverage audit", function()
        local counts = _audit_kruber_3p(true)
        if counts then
            mod:echo("[wt:109] audited %d Kruber ports; %d need animations and %d are untested (see log)",
                counts.total, counts.needs_animations, counts.untested)
        end
    end)

-- #110: Bardin's surface is intentionally small. Keep a fixed receiver wrapper
-- so this audit cannot accidentally walk a different career's unlock list.
local function _audit_bardin_3p(log_rows)
    local wt = mod._wt or {}
    local status = wt.port_status
    local unlocks = wt.weapon_unlock_map and wt.weapon_unlock_map.dr_ranger
    if not status or type(status.audit_cross_character) ~= "function" or not unlocks then
        mod:warning("[wt:110] Bardin 3P audit unavailable (status/unlock source missing)")
        return nil
    end

    local rows, counts = status.audit_cross_character("dr_ranger", unlocks)
    mod:info("[wt:110] Bardin 3P ports=%d working=%d needs_anims=%d untested=%d picker=%d",
        counts.total, counts.working, counts.needs_animations, counts.untested,
        counts.picker_visible)
    if log_rows then
        for _, row in ipairs(rows) do
            mod:info("[wt:110] key=%s status=%s target=%s model=%s",
                row.weapon_key, row.status, tostring(row.redirect),
                tostring(row.model_substitute))
        end
    end
    return counts
end

_audit_bardin_3p(false)

mod:command("wt_audit_bardin_3p",
    "Log the complete Bardin cross-character 3P coverage audit", function()
        local counts = _audit_bardin_3p(true)
        if counts then
            mod:echo("[wt:110] audited %d Bardin ports; %d working (see log)",
                counts.total, counts.working)
        end
    end)

-- #111: read-only census for Kerillian's large cross-character surface.
local function _audit_kerillian_3p(log_rows)
    local wt = mod._wt or {}
    local status = wt.port_status
    local unlocks = wt.weapon_unlock_map and wt.weapon_unlock_map.we_waywatcher
    if not status or type(status.audit_cross_character) ~= "function" or not unlocks then
        mod:warning("[wt:111] Kerillian 3P audit unavailable (status/unlock source missing)")
        return nil
    end

    local rows, counts = status.audit_cross_character("we_waywatcher", unlocks)
    mod:info("[wt:111] Kerillian 3P ports=%d working=%d needs_anims=%d untested=%d picker=%d hidden_needs_anims=%d",
        counts.total, counts.working, counts.needs_animations, counts.untested,
        counts.picker_visible, counts.hidden_needs_animations)
    if log_rows then
        for _, row in ipairs(rows) do
            if row.status ~= "[working]" then
                mod:info("[wt:111] key=%s status=%s target=%s picker=%s",
                    row.weapon_key, row.status, tostring(row.redirect),
                    tostring(row.picker_visible))
            end
        end
    end
    return counts
end

_audit_kerillian_3p(false)

mod:command("wt_audit_kerillian_3p",
    "Log the complete Kerillian cross-character 3P coverage audit", function()
        local counts = _audit_kerillian_3p(true)
        if counts then
            mod:echo("[wt:111] audited %d Kerillian ports; %d need animations and %d are untested (see log)",
                counts.total, counts.needs_animations, counts.untested)
        end
    end)

-- #112: all three non-Warrior-Priest careers intentionally share one unlock
-- surface. Audit each to catch career drift, but log unresolved rows once.
local function _audit_saltzpyre_3p(log_rows)
    local wt = mod._wt or {}
    local status = wt.port_status
    local unlock_map = wt.weapon_unlock_map
    if not status or type(status.audit_cross_character) ~= "function" or not unlock_map then
        mod:warning("[wt:112] Saltzpyre 3P audit unavailable (status/unlock source missing)")
        return nil
    end

    local careers = { "wh_captain", "wh_bountyhunter", "wh_zealot" }
    local baseline_rows
    local baseline_counts
    local parity = true
    for _, career in ipairs(careers) do
        local unlocks = unlock_map[career]
        if not unlocks then
            mod:warning("[wt:112] Saltzpyre 3P audit unavailable (missing %s unlocks)", career)
            return nil
        end
        local rows, counts = status.audit_cross_character(career, unlocks)
        if not baseline_rows then
            baseline_rows = rows
            baseline_counts = counts
        else
            if counts.total ~= baseline_counts.total then parity = false end
            for i, row in ipairs(rows) do
                local base = baseline_rows[i]
                if not base or base.weapon_key ~= row.weapon_key or base.status ~= row.status then
                    parity = false
                    break
                end
            end
        end
    end

    local target_count = 0
    local no_target_count = 0
    for _, row in ipairs(baseline_rows) do
        if row.status ~= "[working]" then
            if row.redirect then target_count = target_count + 1 else no_target_count = no_target_count + 1 end
        end
    end
    mod:info("[wt:112] Saltzpyre non-WP careers=3 parity=%s ports=%d working=%d needs_anims=%d untested=%d picker=%d hidden_needs_anims=%d targets=%d no_target=%d",
        tostring(parity), baseline_counts.total, baseline_counts.working,
        baseline_counts.needs_animations, baseline_counts.untested,
        baseline_counts.picker_visible, baseline_counts.hidden_needs_animations,
        target_count, no_target_count)
    if log_rows then
        for _, row in ipairs(baseline_rows) do
            if row.status ~= "[working]" then
                mod:info("[wt:112] key=%s status=%s target=%s picker=%s model=%s",
                    row.weapon_key, row.status, tostring(row.redirect),
                    tostring(row.picker_visible), tostring(row.model_substitute))
            end
        end
    end
    baseline_counts.parity = parity
    baseline_counts.target_count = target_count
    baseline_counts.no_target_count = no_target_count
    return baseline_counts
end

_audit_saltzpyre_3p(false)

mod:command("wt_audit_saltzpyre_3p",
    "Log non-Warrior-Priest Saltzpyre cross-character 3P coverage", function()
        local counts = _audit_saltzpyre_3p(true)
        if counts then
            mod:echo("[wt:112] audited %d Saltzpyre ports; %d need animations (see log)",
                counts.total, counts.needs_animations)
        end
    end)

-- #113: Warrior Priest is a distinct melee-only receiver. Its seven-entry
-- catalog is intentionally closed so a future ordinary-Saltzpyre or ranged
-- leak is visible immediately rather than silently classified as native.
local _WP_EXPECTED = {
    es_1h_flail = true,
    wh_1h_hammer = true,
    wh_2h_hammer = true,
    wh_dual_hammer = true,
    wh_flail_shield = true,
    wh_hammer_book = true,
    wh_hammer_shield = true,
}

local function _audit_warrior_priest_3p(log_rows)
    local wt = mod._wt or {}
    local status = wt.port_status
    local unlocks = wt.weapon_unlock_map and wt.weapon_unlock_map.wh_priest
    if not status or type(status.audit_cross_character) ~= "function" or not unlocks then
        mod:warning("[wt:113] Warrior Priest 3P audit unavailable (status/unlock source missing)")
        return nil
    end

    local unique = {}
    local total = 0
    local unexpected = 0
    for _, weapon_key in ipairs(unlocks) do
        if type(weapon_key) == "string" and not unique[weapon_key] then
            unique[weapon_key] = true
            total = total + 1
            if not _WP_EXPECTED[weapon_key] then unexpected = unexpected + 1 end
        end
    end
    local missing = 0
    for weapon_key in pairs(_WP_EXPECTED) do
        if not unique[weapon_key] then missing = missing + 1 end
    end

    local rows, counts = status.audit_cross_character("wh_priest", unlocks)
    local native = total - counts.total
    mod:info("[wt:113] Warrior Priest catalog=%d native=%d cross=%d working=%d needs_anims=%d picker=%d unexpected=%d missing=%d",
        total, native, counts.total, counts.working, counts.needs_animations,
        counts.picker_visible, unexpected, missing)
    if log_rows then
        for _, row in ipairs(rows) do
            mod:info("[wt:113] key=%s status=%s target=%s model=%s picker=%s",
                row.weapon_key, row.status, tostring(row.redirect),
                tostring(row.model_substitute), tostring(row.picker_visible))
        end
    end
    counts.catalog_total = total
    counts.native = native
    counts.unexpected = unexpected
    counts.missing = missing
    return counts
end

_audit_warrior_priest_3p(false)

mod:command("wt_audit_warrior_priest_3p",
    "Log Warrior Priest melee-only 3P coverage", function()
        local counts = _audit_warrior_priest_3p(true)
        if counts then
            mod:echo("[wt:113] audited %d Warrior Priest weapons; %d cross-character (see log)",
                counts.catalog_total, counts.total)
        end
    end)
-- WT_DEV_OVERLAY_END:port-coverage-audits

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

-- Hook: SimpleInventoryExtension._wield_slot fires for every local-player
-- wield. slot_data.id carries the item key. hook_safe so we never perturb
-- the wield path. Husk extension intentionally NOT hooked -- we want our
-- own equips, not teammates'.
mod:hook_safe("SimpleInventoryExtension", "_wield_slot",
    function(self, equipment, slot_data, unit_1p, unit_3p, buff_extension)
        local item_key = slot_data
            and (slot_data.id
                or (slot_data.item_data and slot_data.item_data.key))
        _wt_dump_weapon_data(item_key, "wield_slot")
    end)

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
