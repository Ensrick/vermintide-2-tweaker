local mod = get_mod("enemy_tweaker")

-- _et_commands.lua — chat commands (status, dumps, verify, reset)
--
-- Every mod:command this mod registers except /et_regression_test (which
-- lives with the harness in _et_regression.lua). All read-only surfaces plus
-- /et_reset (writes inert defaults via mod:set). Per the user directive:
-- "in debug mode have things getting dumped to the log so you have all the
-- data you need for anything we can't be sure you know how to do."
--
-- Owned by: enemy_tweaker.lua entry point (dofile'd last among the new
-- modules — consumes exports from presets/swaps/mimic/roaming). No exports.

local ET = mod._et
local _mult        = ET.mult
local _scale_count = ET.scale_count
local HORDE_PRESETS      = ET.HORDE_PRESETS
local MIMIC_SYSTEMS      = ET.MIMIC_SYSTEMS
local COMPOSITION_FIELDS = ET.COMPOSITION_FIELDS
local _snap_to_canonical_size = ET.snap_to_canonical_size
local _get_original_compositions_pacing = ET.original_compositions_pacing
local _get_original_sip  = ET.get_original_sip

local function _boss_balance_log(fmt, ...)
    local engine_printf = rawget(_G, "printf")
    if engine_printf then
        pcall(engine_printf, "[et:450] " .. fmt, ...)
    end
end

-- Issue #18: surface last-applied refresh_conflict_director_patches timestamp
-- + trigger source so verification doesn't depend on log-scraping.
mod:command("et_verify_refresh", "Show last refresh_conflict_director_patches apply", function()
    if not mod._et_last_refresh_at then
        mod:echo("[et_verify_refresh] no refresh applied yet this session")
        return
    end
    mod:echo("[et_verify_refresh] last apply: %s (trigger=%s)",
        os.date("%Y-%m-%d %H:%M:%S", mod._et_last_refresh_at),
        tostring(mod._et_last_refresh_trigger))
end)

-- Issue #450: engine-state readback for every shipped boss data knob plus the
-- live Halescourge half-health monitor. The providers load after this command
-- module, so dispatch resolves them dynamically when the user invokes it.
mod:command("verify_boss_balance", "Verify boss balance values and Halescourge monitor", function()
    _boss_balance_log("=== /verify_boss_balance ===")
    local rows = type(ET.boss_balance_live_rows) == "function"
        and ET.boss_balance_live_rows() or nil
    if type(rows) ~= "table" then
        _boss_balance_log("FAIL: boss balance readback provider missing")
    else
        local pass, fail = 0, 0
        for i = 1, #rows do
            local row = rows[i]
            local verdict = row.pass and "PASS" or "FAIL"
            _boss_balance_log("%s: %s | toggle=%s | live=%s | expected=%s",
                verdict, tostring(row.name), tostring(row.enabled),
                tostring(row.live), tostring(row.expected))
            if row.pass then pass = pass + 1 else fail = fail + 1 end
        end
        _boss_balance_log("Data result: %d PASS, %d FAIL", pass, fail)
    end

    local core = ET.BossBehaviorCore
    _boss_balance_log("Skarrik ranged | toggle=%s | multiplier=%s | provider=%s",
        tostring(mod:get("boss_behavior_skarrik_ranged_dr") and true or false),
        tostring(core and core.SKARRIK_RANGED_DAMAGE_MULTIPLIER),
        type(ET.boss_behavior_scale_incoming_damage) == "function" and "ready" or "missing")
    _boss_balance_log("Deathrattler tracking | toggle=%s | multiplier=%s",
        tostring(mod:get("boss_behavior_deathrattler_tracking") and true or false),
        tostring(core and core.DEATHRATTLER_TRACKING_MULTIPLIER))
    local behavior_on = mod:get("boss_behavior_halescourge_monster") and true or false
    local state = type(ET.boss_behavior_live_state) == "function"
        and ET.boss_behavior_live_state() or nil
    _boss_balance_log("Halescourge add | toggle=%s | threshold=%s | Cata rank=%s | observer=%s",
        tostring(behavior_on), tostring(core and core.HALESCOURGE_THRESHOLD),
        tostring(core and core.CATACLYSM_RANK), state and "live" or "waiting for boss")
    if state then
        _boss_balance_log("Halescourge live | reason=%s | health=%s | attempts=%s | queued=%s | queue_id=%s",
            tostring(state.last_reason), tostring(state.last_health_percent),
            tostring(state.attempts), tostring(state.queued_breed), tostring(state.queue_id))
    end
    mod:echo("Boss balance verification written to the console log.")
end)

mod:command("et_dump_breeds", "List all registered breed names by faction", function()
    if not rawget(_G, "Breeds") then
        mod:echo("Breeds table not loaded yet")
        return
    end

    local factions = { skaven = {}, chaos = {}, beastmen = {}, undead = {}, other = {} }

    for name, data in pairs(Breeds) do
        if type(data) == "table" then
            local race = data.race
            if race == "skaven" then
                table.insert(factions.skaven, name)
            elseif race == "chaos" then
                table.insert(factions.chaos, name)
            elseif race == "beastmen" then
                table.insert(factions.beastmen, name)
            elseif race == "undead" then
                table.insert(factions.undead, name)
            else
                table.insert(factions.other, name)
            end
        end
    end

    for faction, breeds in pairs(factions) do
        table.sort(breeds)
        if #breeds > 0 then
            mod:echo("--- %s (%d) ---", faction, #breeds)
            for _, name in ipairs(breeds) do
                local b = Breeds[name]
                local flags = ""
                if b.special then flags = flags .. " [special]" end
                if b.boss then flags = flags .. " [boss]" end
                if b.elite then flags = flags .. " [elite]" end
                mod:echo("  %s  base_unit=%s  template=%s%s", name,
                    tostring(b.base_unit), tostring(b.unit_template), flags)
            end
        end
    end
end)

mod:command("et_dump_compositions", "List all pacing composition keys", function()
    if not rawget(_G, "HordeCompositionsPacing") then
        mod:echo("HordeCompositionsPacing not loaded")
        return
    end

    local keys = {}
    for k, _ in pairs(HordeCompositionsPacing) do
        table.insert(keys, k)
    end
    table.sort(keys)

    mod:echo("--- Pacing Compositions (%d) ---", #keys)
    for _, k in ipairs(keys) do
        local comp = HordeCompositionsPacing[k]
        local variants = 0
        if type(comp) == "table" then
            for i = 1, #comp do
                if comp[i] then variants = variants + 1 end
            end
        end
        mod:echo("  %s (%d variants)", k, variants)
    end
end)

mod:command("et_status", "Show current Enemy Tweaker state", function()
    local preset_key = mod:get("horde_preset") or "off"
    local preset = HORDE_PRESETS[preset_key]
    mod:echo("Preset: %s", preset and preset.label or "Off")
    -- v0.6.0-dev: all 4 spawn-scaling sliders surfaced
    mod:echo("Horde size:   %.1fx", _mult("horde_size_multiplier"))
    mod:echo("Event size:   %.1fx", _mult("event_size_multiplier"))
    mod:echo("Roaming size: %.1fx", _mult("roaming_size_multiplier"))
    mod:echo("Patrol size:  %.1fx", _mult("patrol_size_multiplier"))

    local swap_from = mod:get("breed_swap_from") or "off"
    local swap_to = mod:get("breed_swap_to") or "off"
    if swap_from ~= "off" and swap_to ~= "off" then
        mod:echo("Breed swap: %s -> %s", swap_from, swap_to)
    else
        mod:echo("Breed swap: none")
    end

    local any_faction_swap = false
    for _, faction in ipairs({"skaven", "chaos", "beastmen"}) do
        local target = mod:get("faction_swap_" .. faction) or "off"
        if target ~= "off" and target ~= faction then
            mod:echo("Faction swap: %s -> %s", faction, target)
            any_faction_swap = true
        end
    end
    if not any_faction_swap then
        mod:echo("Faction swap: none")
    end

    local any_mimic = false
    for _, m in ipairs(MIMIC_SYSTEMS) do
        local v = mod:get(m.setting) or "off"
        if v ~= "off" then
            mod:echo("Difficulty mimic: %s = %s", m.field, v)
            any_mimic = true
        end
    end
    if not any_mimic then
        mod:echo("Difficulty mimic: none")
    end

    if rawget(_G, "CurrentHordeSettings") then
        mod:echo("--- Active CurrentHordeSettings ---")
        for _, field in ipairs(COMPOSITION_FIELDS) do
            local v = CurrentHordeSettings[field]
            if type(v) == "string" then
                mod:echo("  %s = %s", field, v)
            elseif type(v) == "table" then
                mod:echo("  %s = [%s]", field, table.concat(v, ", "))
            end
        end
    end
end)

-- /et_reset — one-click revert of every spawn-affecting setting to its INERT
-- (vanilla) default. Enemy Tweaker is already inert out of the box (mimics
-- default "off" + skipped; the 4 size multipliers default 1.0; pacing values are
-- guarded to their vanilla baselines), so this exists to clear any value a host
-- set while exploring the menu and guarantee a clean slate. Live applied state
-- reverts on the next level load / conflict-director switch; the values are
-- inert immediately. Notify=true so each on_setting_changed re-apply runs.
mod:command("et_reset", "Reset all Enemy Tweaker SPAWN settings to inert (vanilla) defaults", function()
    local inert = {
        -- difficulty mimic (the "horde override" dropdowns) -> off
        mimic_horde = "off", mimic_specials = "off", mimic_pacing = "off",
        mimic_pack_spawning = "off", mimic_intensity = "off", mimic_boss = "off",
        -- spawn-scaling multipliers -> 1.0x
        horde_size_multiplier = 1, event_size_multiplier = 1,
        roaming_size_multiplier = 1, patrol_size_multiplier = 1,
        -- spawn pacing -> vanilla baselines
        max_grunts_override = 90, spawn_pace_multiplier = 1,
        horde_grunt_push_threshold = 60, horde_frequency_min = 50, horde_frequency_max = 100,
        ambients_ignore_threat = false,
        -- breed / faction swaps + preset -> off
        breed_swap_from = "off", breed_swap_to = "off",
        faction_swap_skaven = "off", faction_swap_chaos = "off", faction_swap_beastmen = "off",
        horde_preset = "off",
        -- the only boss control that directly queues a new spawn
        boss_behavior_halescourge_monster = false,
        boss_behavior_skarrik_ranged_dr = false,
        boss_behavior_deathrattler_tracking = false,
    }
    local n = 0
    for id, val in pairs(inert) do
        mod:set(id, val, true)
        n = n + 1
    end
    mod:echo("[et] reset %d spawn settings to inert defaults — Enemy Tweaker now changes nothing until you opt in.", n)
    mod:echo("[et] (live spawns revert on the next level load; run /et_status to confirm the settings.)")
end)

-- ============================================================
-- /verify_* and /et_spawn_dump (v0.6.0-dev — § 5.1a coverage for 4 sliders)
-- ============================================================
-- Each /verify_<feature> reports the current slider value, what live state
-- the apply function would have mutated, and a PASS/FAIL row per sampled
-- entry. The commands work from the keep where possible.

mod:command("verify_horde_size", "Verify paced horde size multiplier", function()
    local mult = _mult("horde_size_multiplier")
    mod:echo("=== /verify_horde_size ===")
    mod:echo("Setting: horde_size_multiplier = %.1fx", mult)
    if not rawget(_G, "HordeCompositionsPacing") then
        mod:echo("FAIL: HordeCompositionsPacing not loaded — run in keep, not main menu")
        return
    end
    local _original_compositions_pacing = _get_original_compositions_pacing()
    if not _original_compositions_pacing then
        mod:echo("WARN: _original_compositions_pacing nil — backup never taken (mission never loaded?)")
        return
    end
    -- Sample 'medium' (skaven), 'chaos_medium', 'beastmen_medium' — three
    -- canonical paced keys present in vanilla.
    local samples = { "medium", "chaos_medium", "beastmen_medium" }
    local pass, fail = 0, 0
    for _, key in ipairs(samples) do
        local orig = _original_compositions_pacing[key]
        local live = HordeCompositionsPacing[key]
        if not (orig and live and orig[1] and orig[1].breeds and live[1] and live[1].breeds) then
            mod:echo("  SKIP: %s — missing variants/breeds", key)
        else
            local orig_entry = orig[1].breeds[2]   -- {min, max} after first breed name
            local live_entry = live[1].breeds[2]
            if type(orig_entry) == "table" and type(live_entry) == "table" then
                local expected = _scale_count(orig_entry[1], mult)
                if live_entry[1] == expected then
                    mod:echo("  PASS: %s breed[1] min orig=%d live=%d (expected %d at %.1fx)",
                        key, orig_entry[1], live_entry[1], expected, mult)
                    pass = pass + 1
                else
                    mod:echo("  FAIL: %s breed[1] min orig=%d live=%d (expected %d at %.1fx)",
                        key, orig_entry[1], live_entry[1], expected, mult)
                    fail = fail + 1
                end
            end
        end
    end
    mod:echo("Result: %d PASS, %d FAIL", pass, fail)
end)

mod:command("verify_event_size", "Verify event horde size multiplier", function()
    local mult = _mult("event_size_multiplier")
    mod:echo("=== /verify_event_size ===")
    mod:echo("Setting: event_size_multiplier = %.1fx", mult)
    mod:echo("Apply mechanism: per-call flag on compose_blob_horde_spawn_list")
    if not rawget(_G, "SpawnerSystem") then
        mod:echo("WARN: SpawnerSystem not loaded — outer hook deferred")
    else
        mod:echo("OK: SpawnerSystem.spawn_horde_from_terror_event_ids hook installed")
    end
    if not rawget(_G, "HordeSpawner") then
        mod:echo("FAIL: HordeSpawner not loaded — inner hook missing")
        return
    end
    if type(HordeSpawner.compose_blob_horde_spawn_list) ~= "function" then
        mod:echo("FAIL: HordeSpawner.compose_blob_horde_spawn_list missing")
        return
    end
    mod:echo("OK: HordeSpawner.compose_blob_horde_spawn_list hook installed")
    mod:echo("Live state: enable Debug Logging then trigger an event-horde to see [et:spawn:event] log lines confirming spawn_list was scaled (%.1fx).", mult)
end)

mod:command("verify_roaming_size", "Verify roaming enemy density multiplier", function()
    local mult = _mult("roaming_size_multiplier")
    mod:echo("=== /verify_roaming_size ===")
    mod:echo("Setting: roaming_size_multiplier = %.1fx", mult)
    mod:echo("Canonical pack sizes: 1, 2, 3, 4, 6, 8 (slider snaps to nearest; plateaus at 8 past ~2.7x)")
    if not rawget(_G, "SizeOfInterestPoint") then
        mod:echo("FAIL: SizeOfInterestPoint not loaded — game globals unavailable")
        return
    end
    local _original_size_of_interest_point = _get_original_sip()
    if not _original_size_of_interest_point then
        mod:echo("WARN: backup not taken yet — mission never loaded; will apply on first ConflictDirector.init")
        return
    end
    -- Sample 5 entries: expected = snap-to-canonical(_scale_count(orig, mult)).
    local pass, fail, sampled = 0, 0, 0
    for ip_name, orig in pairs(_original_size_of_interest_point) do
        if sampled < 5 then
            local live = SizeOfInterestPoint[ip_name]
            local desired = _scale_count(orig, mult)
            local expected = _snap_to_canonical_size(desired)
            if live == expected then
                mod:echo("  PASS: %s orig=%s desired=%s snapped=%s live=%s",
                    ip_name, tostring(orig), tostring(desired), tostring(expected), tostring(live))
                pass = pass + 1
            else
                mod:echo("  FAIL: %s orig=%s desired=%s snapped=%s live=%s",
                    ip_name, tostring(orig), tostring(desired), tostring(expected), tostring(live))
                fail = fail + 1
            end
            sampled = sampled + 1
        end
    end
    mod:echo("Result: %d PASS, %d FAIL (sampled %d of %d entries)",
        pass, fail, sampled, (function() local n = 0; for _ in pairs(_original_size_of_interest_point) do n = n + 1 end; return n end)())
end)

mod:command("verify_patrol_size", "Verify patrol size multiplier", function()
    local mult = _mult("patrol_size_multiplier")
    mod:echo("=== /verify_patrol_size ===")
    mod:echo("Setting: patrol_size_multiplier = %.1fx", mult)
    if not rawget(_G, "AIGroupSystem") then
        mod:echo("FAIL: AIGroupSystem not loaded — hook target missing")
        return
    end
    if type(AIGroupSystem.create_formation_data) ~= "function" then
        mod:echo("FAIL: AIGroupSystem.create_formation_data missing")
        return
    end
    mod:echo("OK: AIGroupSystem.create_formation_data hook installed")
    mod:echo("Live state: enable Debug Logging then trigger a patrol event to see [et:spawn:patrol] log lines confirming formation rows were replicated %dx (base→target).",
        math.ceil(mult))
end)

-- /et_spawn_dump — dump every spawn-relevant table at once so a single
-- copy-paste from chat answers "what did the engine actually see?". Per
-- the user's directive: "in debug mode have things getting dumped to the
-- log so you have all the data you need for anything we can't be sure
-- you know how to do."
mod:command("et_spawn_dump", "Dump all spawn-scaling live state to log + chat", function()
    mod:echo("=== /et_spawn_dump ===")
    mod:echo("Multipliers: horde=%.1f event=%.1f roaming=%.1f patrol=%.1f",
        _mult("horde_size_multiplier"), _mult("event_size_multiplier"),
        _mult("roaming_size_multiplier"), _mult("patrol_size_multiplier"))

    local SIP = rawget(_G, "SizeOfInterestPoint")
    if type(SIP) == "table" then
        mod:echo("--- SizeOfInterestPoint (live) ---")
        local keys = {}
        for k in pairs(SIP) do keys[#keys + 1] = k end
        table.sort(keys)
        local _original_size_of_interest_point = _get_original_sip()
        for _, k in ipairs(keys) do
            local orig = _original_size_of_interest_point and _original_size_of_interest_point[k]
            mod:info("[et:dump:SIP] %s live=%s orig=%s", k, tostring(SIP[k]), tostring(orig))
        end
        mod:echo("  Logged %d SizeOfInterestPoint entries to console (see /et_status for slider state)", #keys)
    else
        mod:echo("SizeOfInterestPoint: not loaded")
    end

    local BPS = rawget(_G, "BreedPacksBySize")
    if type(BPS) == "table" then
        local n_types, n_sizes = 0, 0
        for pack_type, sizes in pairs(BPS) do
            n_types = n_types + 1
            if type(sizes) == "table" then
                local size_list = {}
                for sz in pairs(sizes) do size_list[#size_list + 1] = sz end
                table.sort(size_list)
                n_sizes = n_sizes + #size_list
                mod:info("[et:dump:BPS] type=%s sizes=[%s]",
                    tostring(pack_type), table.concat(size_list, ","))
            end
        end
        mod:echo("BreedPacksBySize: %d pack types, %d total sizes — see log for per-type detail",
            n_types, n_sizes)
    else
        mod:echo("BreedPacksBySize: not loaded")
    end

    local CRS = rawget(_G, "CurrentRoamingSettings")
    if type(CRS) == "table" then
        mod:echo("--- CurrentRoamingSettings ---")
        for k, v in pairs(CRS) do
            mod:info("[et:dump:CRS] %s = %s", k, tostring(v))
        end
    end

    local CHS = rawget(_G, "CurrentHordeSettings")
    if type(CHS) == "table" then
        mod:echo("--- CurrentHordeSettings (composition fields) ---")
        for _, field in ipairs(COMPOSITION_FIELDS) do
            local v = CHS[field]
            if type(v) == "string" then
                mod:echo("  %s = %s", field, v)
            elseif type(v) == "table" then
                mod:echo("  %s = [%s]", field, table.concat(v, ", "))
            end
        end
    end

    mod:echo("Enable Debug Logging then trigger a spawn — grep '[et:spawn:' in the console log for per-spawn detail (channels: paced / event / roaming / patrol / unit / refresh / init).")
end)

mod:command("et_dump_horde_composition", "Dump a single HordeCompositions[key] (e.g. /et_dump_horde_composition event_medium)", function(key)
    if not key or key == "" then
        mod:echo("Usage: /et_dump_horde_composition <key>")
        mod:echo("Example keys: event_medium, event_large_beastmen, storm_vermin_medium, chaos_raiders_small")
        return
    end
    local HC = rawget(_G, "HordeCompositions")
    if type(HC) ~= "table" then
        mod:echo("HordeCompositions not loaded")
        return
    end
    local entry = HC[key]
    if not entry then
        mod:echo("HordeCompositions[%q] = nil — not a real key", tostring(key))
        return
    end
    mod:echo("=== HordeCompositions[%q] ===", key)
    -- Each top-level entry is an array of difficulty ranks.
    for rank_idx, rank in ipairs(entry) do
        if type(rank) == "table" then
            mod:echo("  rank %d (%d variants)", rank_idx, #rank)
            for v_idx, variant in ipairs(rank) do
                if type(variant) == "table" then
                    local name = tostring(variant.name or ("variant_" .. v_idx))
                    local weight = tostring(variant.weight or "?")
                    mod:echo("    variant '%s' weight=%s", name, weight)
                    if variant.breeds then
                        for i = 1, #variant.breeds, 2 do
                            local breed = variant.breeds[i]
                            local amount = variant.breeds[i + 1]
                            local amt_str
                            if type(amount) == "table" then
                                amt_str = string.format("[%s, %s]",
                                    tostring(amount[1]), tostring(amount[2]))
                            else
                                amt_str = tostring(amount)
                            end
                            mod:echo("      %-30s %s", tostring(breed), amt_str)
                        end
                    end
                end
            end
        end
    end
end)
