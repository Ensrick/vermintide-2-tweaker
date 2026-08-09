local M = {}

-- CLARIFY: separate feature_enabled implementation from the one in
-- weapon_tweaker.lua because this module receives `mod` as a parameter
-- (it's a sub-module, not the mod's own scope). Both implementations use the
-- same "nil setting => fall back to default_value" pattern; default_value=true
-- means "feature enabled by default".
-- POTENTIAL BUG (LOW): `default_value ~= false` returns true if default_value
-- is nil OR true. So `feature_enabled(mod, "x")` (no default supplied) returns
-- true. Callers below all pass `true` explicitly so this is harmless, but the
-- behavior diverges from the same-named function in weapon_tweaker.lua which
-- treats omitted default as "enabled by default" (same effective result).
local function feature_enabled(mod, setting_id, default_value)
    local value = mod:get(setting_id)
    if value == nil then
        return default_value ~= false
    end

    return value == true
end

-- CLARIFY: invoked once at the bottom of weapon_tweaker.lua (~L3043). Sets
-- up backend hooks. The two availability callbacks are invoked together only
-- on a bounded CWV active-state transition so can_wield and career actions
-- cannot drift across enable/disable/hot-reload.
function M.install(mod, weapon_unlock_map, apply_weapon_unlocks, patch_career_actions_on_weapons)
    local cache_policy = mod:dofile("scripts/mods/weapon_tweaker_dev/_wt_loadout_cache_policy")
    local previous_cache = mod.loadout_cache
    local cache_reset
    mod.loadout_cache, mod.loadout_cache_schema, cache_reset = cache_policy.ensure_schema(
        previous_cache, mod.loadout_cache_schema)
    M.cache_policy = cache_policy
    mod._wt.weapon_backend = M
    local cwv_ownership = mod._wt and mod._wt.cwv_ownership
    local cwv_managed = mod._wt and mod._wt.cwv_conditional_managed or {}
    local function cwv_active()
        return cwv_ownership
            and cwv_ownership.cwv_is_active(get_mod("character_weapon_variants"))
            or false
    end
    local function cwv_axe_shield_ready()
        return cwv_ownership
            and cwv_ownership.replacement_ready(ItemMasterList, "dr_shield_axe") or false
    end
    local function cwv_greataxe_ready()
        return cwv_ownership
            and cwv_ownership.replacement_ready(ItemMasterList, "dr_2h_axe") or false
    end
    M._last_cwv_active = cwv_active()
    M._last_cwv_axe_shield_ready = cwv_axe_shield_ready()
    M._last_cwv_greataxe_ready = cwv_greataxe_ready()

    -- Passive overcharge-vent / energy-regen restore for cross-character
    -- overcharge weapons (Sienna staves) + the Moonfire Bow on careers that
    -- lack the native rate. Exposes M.tick(dt); driven from mod.update below
    -- (the single per-frame surface VMF schedules). Loaded once here. See the
    -- module header for the full networking / consumption-side rationale.
    local passive_charge = mod:dofile("scripts/mods/weapon_tweaker_dev/_wt_passive_charge")
    M.passive_charge = passive_charge
    local overcharge_presentation = mod:dofile("scripts/mods/weapon_tweaker_dev/_wt_overcharge_presentation")
    M.overcharge_presentation = overcharge_presentation

    -- #374/#388: EnergyData seeding for careers granted an energy weapon
    -- (Moonfire family). The module header carries the full decompile-cited
    -- design; install() defines mod._wt374_seed_energy_data /
    -- mod._wt374_revert_energy_data and runs the initial seed. Re-seeded at
    -- the availability seams in mod.update below and the entry point's
    -- state-change / unlock-setting handlers; reverted from on_disabled.
    mod:dofile("scripts/mods/weapon_tweaker_dev/_wt_energy_seed").install(mod)

    local function is_mod_unlocked_weapon(career_name, weapon_key)
        if not career_name or not weapon_key then
            return false
        end

        local career_weapons = weapon_unlock_map[career_name]
        if not career_weapons then
            return false
        end

        if cwv_ownership and cwv_ownership.should_yield_native(
                career_name, weapon_key, cwv_active(), cwv_managed,
                cwv_ownership.replacement_ready(ItemMasterList, weapon_key)) then
            return false
        end

        for _, unlocked_key in ipairs(career_weapons) do
            if unlocked_key == weapon_key and mod:get("unlock_" .. career_name .. "_" .. weapon_key) then
                return true
            end
        end

        return false
    end
    -- Regression-visible pure ownership predicate. The read-side hooks below
    -- use this same closure, so a removed pair is rejected before any stale
    -- cached backend id can override vanilla's loadout.
    M.is_mod_unlocked_weapon = is_mod_unlocked_weapon

    local function is_native_weapon(career_name, weapon_key)
        local predicate = mod._wt and mod._wt.is_native_weapon
        return type(predicate) == "function" and predicate(career_name, weapon_key) == true
    end

    local function should_cache_weapon(career_name, weapon_key)
        return is_mod_unlocked_weapon(career_name, weapon_key)
            and not is_native_weapon(career_name, weapon_key)
    end
    M.is_native_weapon = is_native_weapon
    M.should_cache_weapon = should_cache_weapon

    local _trace_seen = {}
    local _trace_count = 0
    local _TRACE_LIMIT = 64
    local function trace_1190(action, career_name, loadout_index, slot_name, weapon_key, result)
        local signature = table.concat({
            tostring(action), tostring(career_name), tostring(loadout_index),
            tostring(slot_name), tostring(weapon_key), tostring(result),
        }, "|")
        if _trace_seen[signature] or _trace_count >= _TRACE_LIMIT then return end
        _trace_seen[signature] = true
        _trace_count = _trace_count + 1
        printf("[wt:1190] action=%s career=%s row=%s slot=%s weapon=%s result=%s",
            tostring(action), tostring(career_name), tostring(loadout_index),
            tostring(slot_name), tostring(weapon_key), tostring(result))
    end

    -- Unlike the bounded/deduplicated trace above, this ledger preserves the
    -- ordered live evidence needed by `/verify_wt_loadout_cache`. It is armed
    -- explicitly so ordinary play does not accumulate diagnostic state.
    local _observations = { epoch = 0, armed = false, events = {} }
    local _OBSERVATION_LIMIT = 192
    M.issue1190_observations = _observations

    local function reset_observations()
        _observations.epoch = _observations.epoch + 1
        _observations.armed = true
        _observations.sequence = 0
        _observations.events = {}
        _observations.overflow = false
        _observations.invalidated = nil
        _observations.last_reads = {}
        _observations.last_previews = {}
        return _observations.epoch
    end

    local function observe_1190(kind, fields)
        if not _observations.armed then return end
        fields = fields or {}
        local group_key = tostring(fields.career) .. "\0" .. tostring(fields.slot)
        if kind == "write" then
            _observations.last_reads[group_key] = nil
            _observations.last_previews[group_key] = nil
        elseif kind == "selected-read" then
            local signature = table.concat({
                tostring(fields.row), tostring(fields.effective_id), tostring(fields.route),
            }, "|")
            if _observations.last_reads[group_key] == signature then return end
            _observations.last_reads[group_key] = signature
        elseif kind == "row-preview" then
            local signature = table.concat({
                tostring(fields.valid), tostring(fields.cached_rows), tostring(fields.vanilla_rows),
            }, "|")
            if _observations.last_previews[group_key] == signature then return end
            _observations.last_previews[group_key] = signature
        elseif kind == "row-add" or kind == "row-delete" then
            _observations.last_reads = {}
            _observations.last_previews = {}
        end
        _observations.sequence = _observations.sequence + 1
        if #_observations.events >= _OBSERVATION_LIMIT then
            _observations.overflow = true
            return
        end
        fields.kind = kind
        fields.sequence = _observations.sequence
        _observations.events[#_observations.events + 1] = fields
    end

    local function invalidate_observations(reason)
        if _observations.armed then
            _observations.invalidated = reason or "runtime-state-changed"
        end
    end

    local function tracked_slots()
        local tracked = {}
        if not _observations.armed then return tracked end
        for _, event in ipairs(_observations.events) do
            if event.kind == "write" and event.career and event.slot then
                tracked[event.career] = tracked[event.career] or {}
                tracked[event.career][event.slot] = true
            end
        end
        return tracked
    end

    if cache_reset then
        trace_1190("schema", "all", cache_policy.SCHEMA_VERSION, "all", "all",
            type(previous_cache) == "table" and next(previous_cache) and "legacy-cleared" or "initialized")
    end

    local function normalize_index(value)
        local index = tonumber(value)
        if not index or index < 1 or index % 1 ~= 0 then return nil end
        return index
    end

    -- GUT owns the selected row in its mirror hook while modded loadouts are
    -- active. Ask the mirror method first; reading `_career_loadouts` directly
    -- would observe the unrelated official row and recreate #1190.
    local function get_career_state(items_interface, career_name)
        local mirror = items_interface and items_interface._backend_mirror
        if mirror and type(mirror.get_career_loadouts) == "function" then
            local ok, selected_index, loadouts = pcall(
                mirror.get_career_loadouts, mirror, career_name)
            if ok then
                return normalize_index(selected_index), loadouts
            end
        end
        local selected_index = mirror and mirror._career_loadouts
            and mirror._career_loadouts[career_name]
        local loadouts = items_interface and items_interface._career_loadouts
            and items_interface._career_loadouts[career_name]
        return normalize_index(selected_index), loadouts
    end

    local function resolve_write_index(items_interface, career_name, optional_loadout_index)
        local explicit_index = normalize_index(optional_loadout_index)
        local selected_index, loadouts = get_career_state(items_interface, career_name)
        local resolved_index = explicit_index or selected_index
        local source = explicit_index and "optional" or "selected"
        if not resolved_index or type(loadouts) ~= "table"
                or type(loadouts[resolved_index]) ~= "table" then
            return nil, source
        end
        return resolved_index, source
    end

    function M.clear_loadout_cache(reason)
        local changed = cache_policy.clear_all(mod.loadout_cache)
        if changed then
            trace_1190("clear", "all", "all", "all", "all", reason or "requested")
        end
        if reason then invalidate_observations(reason) end
        return changed
    end

    M._filter_dirty = false

    function M.refresh_on_setting_change(mod)
        invalidate_observations("weapon-availability-changed")
        if not feature_enabled(mod, "enable_weapon_backend_hooks", true) then
            M.clear_loadout_cache("backend-hooks-disabled")
            M._filter_dirty = true
            return
        end
        if Managers.backend and Managers.backend._interfaces
                and Managers.backend._interfaces["items"] then
            local items_interface = Managers.backend:get_interface("items")
            local stale = {}
            for career_name, rows in pairs(mod.loadout_cache) do
                for loadout_index, slots in pairs(rows) do
                    for slot_name, backend_id in pairs(slots) do
                        local item = items_interface:get_item_from_id(backend_id)
                        local weapon_key = item and (item.key or (item.data and item.data.key))
                        -- A synthetic id may become resolvable after another
                        -- backend interface finishes loading. Preserve unknown
                        -- ids and retry instead of deleting them prematurely.
                        if item and not should_cache_weapon(career_name, weapon_key) then
                            stale[#stale + 1] = { career_name, loadout_index, slot_name }
                        end
                    end
                end
            end
            for _, key in ipairs(stale) do
                cache_policy.clear(mod.loadout_cache, key[1], key[2], key[3])
            end
        end

        M._filter_dirty = true
    end

    local function get_cached_backend_item(items_interface, career_name, loadout_index, slot_name)
        local backend_id = cache_policy.get(
            mod.loadout_cache, career_name, loadout_index, slot_name)
        if not backend_id then
            return nil, nil
        end

        local item = items_interface:get_item_from_id(backend_id)
        if not item then
            -- Keep unresolved synthetic ids retryable; omit only this read.
            return nil, nil
        end

        local weapon_key = item.key or (item.data and item.data.key)
        if not should_cache_weapon(career_name, weapon_key) then
            cache_policy.clear(mod.loadout_cache, career_name, loadout_index, slot_name)
            trace_1190("read-skip", career_name, loadout_index, slot_name, weapon_key,
                is_native_weapon(career_name, weapon_key) and "native-evicted" or "disabled-evicted")
            return nil, nil
        end

        return backend_id, item
    end

    function M.runtime_check_issue1190()
        local probe, schema = cache_policy.ensure_schema({}, cache_policy.SCHEMA_VERSION)
        cache_policy.set(probe, "dr_slayer", 1, "slot_melee", "row-one")
        cache_policy.set(probe, "dr_slayer", 3, "slot_melee", "row-three")
        if schema ~= cache_policy.SCHEMA_VERSION
                or cache_policy.get(probe, "dr_slayer", 1, "slot_melee") ~= "row-one"
                or cache_policy.get(probe, "dr_slayer", 2, "slot_melee") ~= nil
                or cache_policy.get(probe, "dr_slayer", 3, "slot_melee") ~= "row-three" then
            return "#1190 cache policy is not isolated by loadout row"
        end

        local ownership = mod._wt and mod._wt.native_weapon_ownership
        local slayer = ownership and ownership.dr_slayer
        if not slayer or slayer.dr_2h_axe == nil or slayer.dr_handgun == nil then
            return "#1190 immutable native ownership catalog is not ready"
        end
        if slayer.dr_2h_axe ~= true then
            return "#1190 native Slayer Greataxe was not classified as vanilla-owned"
        end
        if slayer.dr_handgun ~= false then
            return "#1190 non-native Slayer Handgun was classified as vanilla-owned"
        end
        return nil
    end

    local function observation_groups()
        local groups = {}
        for _, event in ipairs(_observations.events) do
            if event.kind == "write" and event.row_source == "selected"
                    and event.career and event.slot and event.row then
                local key = event.career .. "\0" .. event.slot
                local group = groups[key]
                if not group then
                    group = {
                        career = event.career,
                        slot = event.slot,
                        native = {},
                        cross = {},
                    }
                    groups[key] = group
                end
                if event.ownership == "native" and event.route == "vanilla"
                        and event.writer_result == true then
                    group.native[event.row] = event
                elseif event.ownership == "cross" and event.route == "cache" then
                    group.cross[event.row] = event
                end
            end
        end
        return groups
    end

    local function selected_read_runs(group, after_sequence)
        local runs = {}
        for _, event in ipairs(_observations.events) do
            if event.kind == "selected-read" and event.sequence > after_sequence
                    and event.career == group.career and event.slot == group.slot then
                local previous = runs[#runs]
                if previous and previous.row == event.row then
                    runs[#runs] = event
                else
                    runs[#runs + 1] = event
                end
            end
        end
        return runs
    end

    local function evaluate_live_observations()
        if not _observations.armed then
            return "not-run", "run /verify_wt_loadout_cache reset before the test cycle"
        end
        if _observations.invalidated then
            return "not-run", "observation epoch invalidated by " .. tostring(_observations.invalidated)
                .. "; reset and repeat"
        end
        if _observations.overflow then
            return "not-run", "observation ledger overflowed; reset and repeat the bounded test cycle"
        end

        local groups = observation_groups()
        local native_count, cross_count, read_count, preview_count, bot_count = 0, 0, 0, 0, 0
        for _, event in ipairs(_observations.events) do
            if event.kind == "write" and event.ownership == "native"
                    and event.route == "vanilla" and event.writer_result == true then
                native_count = native_count + 1
            end
            if event.kind == "write" and event.row_source == "selected"
                    and event.ownership == "native" and event.route == "vanilla"
                    and event.writer_result ~= true then
                return "fail", "the game's loadout writer rejected a native weapon change"
            end
            if event.kind == "write" and event.ownership == "cross"
                    and event.route == "cache" then cross_count = cross_count + 1 end
            if event.kind == "selected-read" then read_count = read_count + 1 end
            if event.kind == "row-preview" then preview_count = preview_count + 1 end
            if event.kind == "bot-read" and event.route == "vanilla"
                    and event.ok == true then bot_count = bot_count + 1 end
            if event.kind == "bot-read" and event.route ~= "vanilla" then
                return "fail", "a bot lookup was served by the player cache"
            end
        end

        for _, group in pairs(groups) do
            local native_rows = {}
            for row, event in pairs(group.native) do
                local duplicate_id = false
                for _, existing in ipairs(native_rows) do
                    if existing.backend_id == event.backend_id then duplicate_id = true; break end
                end
                if not duplicate_id then native_rows[#native_rows + 1] = event end
            end
            table.sort(native_rows, function(a, b) return a.row < b.row end)

            if #native_rows >= 2 then
                for cross_row, cross in pairs(group.cross) do
                    local first, second
                    for _, native in ipairs(native_rows) do
                        if native.row ~= cross_row then
                            if not first then first = native
                            elseif not second then second = native; break end
                        end
                    end
                    if first and second then
                        local cached = cache_policy.get(mod.loadout_cache,
                            group.career, cross_row, group.slot)
                        if cached ~= cross.backend_id then
                            return "fail", string.format(
                                "cross-career cache leaf changed: %s row %d %s",
                                group.career, cross_row, group.slot)
                        end
                        if cache_policy.get(mod.loadout_cache,
                                group.career, first.row, group.slot)
                                or cache_policy.get(mod.loadout_cache,
                                    group.career, second.row, group.slot) then
                            return "fail", "a native row retained a WT cache overlay"
                        end

                        local after_sequence = math.max(
                            cross.sequence, first.sequence, second.sequence)
                        local runs = selected_read_runs(group, after_sequence)
                        for _, run in ipairs(runs) do
                            if run.row ~= cross_row and run.effective_id == cross.backend_id then
                                return "fail", string.format(
                                    "cross-career id bled from row %d into row %s",
                                    cross_row, tostring(run.row))
                            end
                        end

                        local function expected_native(run)
                            if run.row == first.row then
                                return run.route == "vanilla"
                                    and run.effective_id == first.backend_id
                            elseif run.row == second.row then
                                return run.route == "vanilla"
                                    and run.effective_id == second.backend_id
                            end
                            return false
                        end
                        local function expected_cross(run)
                            return run.row == cross_row and run.route == "cache"
                                and run.effective_id == cross.backend_id
                        end

                        local cycle_complete = false
                        for i = 1, #runs do
                            if expected_cross(runs[i]) then
                                for j = i + 1, #runs do
                                    if expected_native(runs[j]) then
                                        for k = j + 1, #runs do
                                            if expected_native(runs[k])
                                                    and runs[k].row ~= runs[j].row then
                                                for n = k + 1, #runs do
                                                    if expected_cross(runs[n]) then
                                                        cycle_complete = true
                                                        break
                                                    end
                                                end
                                            end
                                            if cycle_complete then break end
                                        end
                                    end
                                    if cycle_complete then break end
                                end
                            end
                            if cycle_complete then break end
                        end

                        local preview_ok = false
                        for _, event in ipairs(_observations.events) do
                            if event.kind == "row-preview"
                                    and event.sequence > after_sequence
                                    and event.career == group.career
                                    and event.slot == group.slot then
                                if event.valid ~= true then
                                    return "fail", "all-row preview changed a non-cached row"
                                end
                                if event.cached_rows >= 1 and event.vanilla_rows >= 2 then
                                    preview_ok = true
                                end
                            end
                        end

                        if cycle_complete and preview_ok and bot_count > 0 then
                            return "pass", string.format(
                                "CORE PASS epoch=%d career=%s slot=%s cycle=%d>%d>%d>%d bot=vanilla preview=isolated",
                                _observations.epoch, group.career, group.slot,
                                cross_row, first.row, second.row, cross_row)
                        end
                    end
                end
            end
        end

        return "not-run", string.format(
            "CORE NOT RUN epoch=%d native_writes=%d cross_writes=%d selected_reads=%d previews=%d bot_reads=%d",
            _observations.epoch, native_count, cross_count, read_count, preview_count, bot_count)
    end

    function M.verify_loadout_cache(action)
        local failure = M.runtime_check_issue1190()
        if failure then return "fail", failure end
        if not mod.done_hooking_backend then
            return "not-ready", "backend hooks have not reached the live items interface"
        end

        local items_interface = Managers.backend and Managers.backend:get_interface("items")
        if not items_interface then return "not-ready", "items interface is unavailable" end
        action = string.lower(tostring(action or ""))
        if action == "reset" then
            local epoch = reset_observations()
            return "armed", string.format(
                "epoch=%d; equip two native weapons and one cross-career weapon in distinct rows, then cycle cross>native>native>cross",
                epoch)
        elseif action ~= "" then
            return "not-run", "usage: /verify_wt_loadout_cache [reset]"
        end

        -- Read-only live dispatch through the installed bot path. The bot-depth
        -- guard in the hooks proves that nested get_loadout calls stay vanilla.
        if _observations.armed then
            local probe
            for _, event in ipairs(_observations.events) do
                if event.kind == "write" and event.career and event.slot then
                    probe = event
                end
            end
            if probe then
                pcall(items_interface.get_loadout_item_id, items_interface,
                    probe.career, probe.slot, true)
            end
        end

        return evaluate_live_observations()
    end

    if type(mod._wt.rt_register) == "function" then
        mod._wt.rt_register("issue1190_loadout_cache_is_row_scoped",
            M.runtime_check_issue1190)
    end

    -- CLARIFY: deferred initialization. Two one-shot guards:
    --   1. _applied_unlocks: apply_weapon_unlocks needs ItemMasterList loaded.
    --      Runs once when ItemMasterList is first available.
    --   2. done_hooking_backend: backend hooks need the items_interface INSTANCE
    --      (not class). Hooking an instance method is required because the
    --      class-form hook on `BackendInterfaceItemPlayfab.set_loadout_item`
    --      can collide with weave-mode interface usage and other mods. Runs
    --      once when Managers.backend has interfaces created (in the lobby).
    -- VMF schedules `mod.update` every frame so the conditions are polled.
    -- VMF passes the frame `dt` as the first arg (repo-wide convention:
    -- `mod.update = function(dt) ... end`); the deferred-init guards below
    -- ignore it, but the passive-charge tick needs it.
    --
    -- #664 ROOT CAUSE FIX: this assignment executes from M.install
    -- (weapon_tweaker.lua bottom, ~L4300), which runs AFTER
    -- _wt431_damage_profile_parity.lua (~L2655) already wrapped mod.update
    -- with the peer-parity beacon tick. The old naked `mod.update = ...`
    -- STOMPED that wrapper, so the beacon never ticked, applied_state()
    -- froze at its fail-safe "disabled", and every parity-gated damage
    -- profile toggle read parity=false forever - even solo (54/54 logs:
    -- `[wt:664] ... enabled=false parity=false`). Preserve any earlier
    -- per-frame driver exactly like _lib_peer_parity's own install() does,
    -- so whichever side assigns last keeps the other alive regardless of
    -- load order.
    local _bot_read_depth = 0
    local prev_update = mod.update
    mod.update = function(dt)
        if prev_update then pcall(prev_update, dt) end
        if mod._wt368_deferred_availability then
            mod._wt368_deferred_availability = nil
            apply_weapon_unlocks()
            -- CWV creates its private ItemMasterList/template rows from its own
            -- StateInGameRunning callback.  Availability without the matching
            -- action reconciliation leaves a late-created weapon wieldable but
            -- unable to expose the current career's activated-ability action.
            patch_career_actions_on_weapons()
            -- #374/#388: availability just settled (including CWV's late rows),
            -- so re-derive which careers now hold an energy weapon and seed
            -- their EnergyData rows before any energy extension initializes.
            if mod._wt374_seed_energy_data then mod._wt374_seed_energy_data() end
            mod:info("[wt:368] deferred final availability + career-action reconciliation applied")
        end
        -- Per-frame passive-charge restore (cross-character staves / Moonfire
        -- Bow). Self-gated on its VMF toggle (default OFF) and the local owned
        -- player only; pcall-isolated internally so it can never break init.
        passive_charge.tick(dt)
        pcall(overcharge_presentation.tick)

        -- Per-frame DURABLE 3P grip-offset re-apply (the Necromancer Ghost
        -- Scythe on Kruber, etc.). A one-shot create_equipment offset is stomped
        -- by the engine's per-tick canonical-pose reset in-game (preview-OK /
        -- in-game-wrong), so members of _DURABLE_GRIP_OFFSETS re-apply every
        -- frame on the local player's wielded 3P unit. 3P-ONLY, career-gated,
        -- additive-from-canonical (never compounds). See the _DURABLE_GRIP_OFFSETS
        -- header in weapon_tweaker.lua / OFFSETS.md. Defined on the mod table
        -- because that's where the offset data lives (separate dofile scope).
        -- Guarded: nil before weapon_tweaker.lua finishes loading (load order).
        if mod._reapply_durable_grip_offsets then
            pcall(mod._reapply_durable_grip_offsets)
        end

        -- #569: durable, absolute 3P-only local-Z half-turn for non-native
        -- weapons on standard Saltzpyre careers whose live wield redirect is
        -- the Warrior Priest greathammer family. Tracks local/bot/husk/preview
        -- units and restores canonical rotation while unwielded.
        if mod._wt569_reapply_3p_orientation then
            pcall(mod._wt569_reapply_3p_orientation)
        end

        -- #593: CWV may be enabled/disabled or hot-reloaded without a game
        -- state transition. Reconcile exactly once per ownership transition:
        -- can_wield is strip/rebuilt and stale WT loadout-cache rows are pruned.
        local owns_axe_shield = cwv_active()
        local axe_shield_ready = cwv_axe_shield_ready()
        local greataxe_ready = cwv_greataxe_ready()
        if owns_axe_shield ~= M._last_cwv_active
                or axe_shield_ready ~= M._last_cwv_axe_shield_ready
                or greataxe_ready ~= M._last_cwv_greataxe_ready then
            M._last_cwv_active = owns_axe_shield
            M._last_cwv_axe_shield_ready = axe_shield_ready
            M._last_cwv_greataxe_ready = greataxe_ready
            apply_weapon_unlocks()
            patch_career_actions_on_weapons()
            if mod._wt_apply_axe_balance then mod._wt_apply_axe_balance(nil, false) end
            if mod._wt374_seed_energy_data then mod._wt374_seed_energy_data() end
            M.refresh_on_setting_change(mod)
            mod:info("[wt:593/597] CWV ownership transition active=%s axe_shield_ready=%s greataxe_ready=%s; native fallbacks reconciled",
                tostring(owns_axe_shield), tostring(axe_shield_ready), tostring(greataxe_ready))
        end

        if not mod._applied_unlocks and ItemMasterList then
            mod._applied_unlocks = true
            apply_weapon_unlocks()
            if mod._wt374_seed_energy_data then mod._wt374_seed_energy_data() end
        end

        if not mod.done_hooking_backend and Managers.backend and Managers.backend._interfaces
                and Managers.backend._interfaces["items"] then
            mod.done_hooking_backend = true
            local items_interface = Managers.backend:get_interface("items")

            -- #582: eagerly prune cache entries whose ownership disappeared in
            -- this version (notably native dr_dual_wield_axes on ES/WH). The
            -- get_loadout/get_loadout_item_id hooks also revalidate on every
            -- read, but doing this once here makes hot-reload/session-retained
            -- state converge before the first inventory query.
            M.refresh_on_setting_change(mod)

            -- #1190: only genuinely cross-career weapons bypass the official
            -- writer. Cache them by (career, loadout row, slot); native weapons
            -- clear only that exact overlay leaf and pass through to vanilla.
            -- The explicit optional row wins, otherwise the selected row comes
            -- from the mirror accessor (including GUT's private row space).
            mod:hook(items_interface, "set_loadout_item", function(func, self, backend_id, career_name, slot_name, ...)
                local optional_loadout_index = select(1, ...)
                local loadout_index, row_source = resolve_write_index(
                    self, career_name, optional_loadout_index)
                if not feature_enabled(mod, "enable_weapon_backend_hooks", true) then
                    M.clear_loadout_cache("backend-hooks-disabled")
                    return func(self, backend_id, career_name, slot_name, ...)
                end

                local item_data = self:get_item_from_id(backend_id)
                local weapon_key = item_data and (item_data.key or (item_data.data and item_data.data.key))
                if should_cache_weapon(career_name, weapon_key) then
                    -- A cross-career id must never reach the PlayFab writer.
                    -- If no authoritative row exists, reject rather than guess.
                    if not loadout_index then
                        trace_1190("write", career_name, "unknown", slot_name,
                            weapon_key, "rejected-no-row")
                        observe_1190("write", {
                            career = career_name, row = nil, row_source = row_source,
                            slot = slot_name, backend_id = backend_id, weapon_key = weapon_key,
                            ownership = "cross", route = "rejected",
                        })
                        return false
                    end
                    cache_policy.set(mod.loadout_cache, career_name,
                        loadout_index, slot_name, backend_id)
                    trace_1190("write", career_name, loadout_index, slot_name,
                        weapon_key, "cross-career-cached")
                    observe_1190("write", {
                        career = career_name, row = loadout_index, row_source = row_source,
                        slot = slot_name, backend_id = backend_id, weapon_key = weapon_key,
                        ownership = "cross", route = "cache",
                    })
                    return true
                end

                if loadout_index then
                    cache_policy.clear(mod.loadout_cache, career_name,
                        loadout_index, slot_name)
                end
                trace_1190("write", career_name, loadout_index or "unknown",
                    slot_name, weapon_key,
                    is_native_weapon(career_name, weapon_key)
                        and "native-passthrough" or "unmanaged-passthrough")

                local result = func(self, backend_id, career_name, slot_name, ...)
                observe_1190("write", {
                    career = career_name, row = loadout_index, row_source = row_source,
                    slot = slot_name, backend_id = backend_id, weapon_key = weapon_key,
                    ownership = is_native_weapon(career_name, weapon_key)
                        and "native" or "unmanaged",
                    route = "vanilla", writer_result = result,
                })
                return result
            end)

            mod:hook(items_interface, "get_loadout", function(func, self)
                local loadout = func(self)
                if not feature_enabled(mod, "enable_weapon_backend_hooks", true) then
                    M.clear_loadout_cache("backend-hooks-disabled")
                    return loadout
                end
                if _bot_read_depth > 0 then return loadout end

                local cached_careers = {}
                for career_name in pairs(mod.loadout_cache) do
                    cached_careers[#cached_careers + 1] = career_name
                end
                for _, career_name in ipairs(cached_careers) do
                    local rows = mod.loadout_cache[career_name]
                    local loadout_index = get_career_state(self, career_name)
                    local slots = loadout_index and rows and rows[loadout_index]
                    if loadout[career_name] and slots then
                        local output_row = {}
                        for key, value in pairs(loadout[career_name]) do output_row[key] = value end
                        loadout[career_name] = output_row
                        local slot_names = {}
                        for slot_name in pairs(slots) do slot_names[#slot_names + 1] = slot_name end
                        for _, slot_name in ipairs(slot_names) do
                            local cached_id, item = get_cached_backend_item(
                                self, career_name, loadout_index, slot_name)
                            local weapon_key = item and (item.key or (item.data and item.data.key))
                            if cached_id then
                                output_row[slot_name] = cached_id
                                trace_1190("read-loadout", career_name, loadout_index,
                                    slot_name, weapon_key, "override")
                            end
                        end
                    end
                end

                for career_name, slots in pairs(tracked_slots()) do
                    local loadout_index = get_career_state(self, career_name)
                    local row = loadout[career_name]
                    if loadout_index and type(row) == "table" then
                        for slot_name in pairs(slots) do
                            local effective_id = row[slot_name]
                            local cached_id = cache_policy.get(mod.loadout_cache,
                                career_name, loadout_index, slot_name)
                            observe_1190("selected-read", {
                                career = career_name, row = loadout_index,
                                slot = slot_name, effective_id = effective_id,
                                route = cached_id and cached_id == effective_id
                                    and "cache" or "vanilla",
                                source = "get_loadout",
                            })
                        end
                    end
                end

                return loadout
            end)

            -- The loadout selector consumes every row, not only the selected
            -- row. Overlay a deep copy so preview buttons stay row-correct and
            -- the backend interface's own tables are never mutated.
            mod:hook(items_interface, "get_career_loadouts", function(func, self, career_name)
                local loadouts = func(self, career_name)
                if not feature_enabled(mod, "enable_weapon_backend_hooks", true) then
                    M.clear_loadout_cache("backend-hooks-disabled")
                    return loadouts
                end
                if not mod.loadout_cache[career_name] then return loadouts end

                local stale = {}
                local output = cache_policy.overlay_rows(loadouts, mod.loadout_cache,
                    career_name, function(backend_id, _, loadout_index, slot_name)
                        local item = self:get_item_from_id(backend_id)
                        local weapon_key = item and (item.key or (item.data and item.data.key))
                        local accepted = item and should_cache_weapon(career_name, weapon_key)
                        if accepted then
                            trace_1190("read-rows", career_name, loadout_index,
                                slot_name, weapon_key, "override")
                        elseif item then
                            stale[#stale + 1] = { loadout_index, slot_name }
                        end
                        return accepted == true
                    end)
                for _, key in ipairs(stale) do
                    cache_policy.clear(mod.loadout_cache, career_name, key[1], key[2])
                end

                local slots = tracked_slots()[career_name]
                if slots then
                    for slot_name in pairs(slots) do
                        local valid, cached_rows, vanilla_rows = true, 0, 0
                        for loadout_index, base_row in pairs(loadouts or {}) do
                            local output_row = output and output[loadout_index]
                            if type(base_row) == "table" and type(output_row) == "table" then
                                local cached_id = cache_policy.get(mod.loadout_cache,
                                    career_name, loadout_index, slot_name)
                                if cached_id then
                                    cached_rows = cached_rows + 1
                                    if output_row[slot_name] ~= cached_id then valid = false end
                                else
                                    vanilla_rows = vanilla_rows + 1
                                    if output_row[slot_name] ~= base_row[slot_name] then valid = false end
                                end
                            end
                        end
                        observe_1190("row-preview", {
                            career = career_name, slot = slot_name, valid = valid,
                            cached_rows = cached_rows, vanilla_rows = vanilla_rows,
                        })
                    end
                end
                return output
            end)

            -- Mirror vanilla/GUT row lifecycle only after the underlying row
            -- count proves that the requested operation succeeded.
            mod:hook(items_interface, "add_loadout", function(func, self, career_name)
                local old_selected, old_loadouts = get_career_state(self, career_name)
                local old_count = type(old_loadouts) == "table" and #old_loadouts or nil
                local result = func(self, career_name)
                local _, new_loadouts = get_career_state(self, career_name)
                local new_count = type(new_loadouts) == "table" and #new_loadouts or nil
                if old_count and new_count == old_count + 1 then
                    local cloned = cache_policy.clone_added_row(mod.loadout_cache,
                        career_name, old_selected, new_count)
                    trace_1190("add-row", career_name, new_count, "all", "all",
                        cloned and "overlay-cloned" or "no-overlay")
                    observe_1190("row-add", {
                        career = career_name, source_row = old_selected,
                        row = new_count, old_count = old_count, new_count = new_count,
                        overlay_cloned = cloned == true,
                    })
                end
                return result
            end)

            mod:hook(items_interface, "delete_loadout", function(func, self, career_name, loadout_index)
                local _, old_loadouts = get_career_state(self, career_name)
                local old_count = type(old_loadouts) == "table" and #old_loadouts or nil
                local result = func(self, career_name, loadout_index)
                local _, new_loadouts = get_career_state(self, career_name)
                local new_count = type(new_loadouts) == "table" and #new_loadouts or nil
                if old_count and new_count == old_count - 1 then
                    local shifted = cache_policy.delete_row(mod.loadout_cache,
                        career_name, loadout_index, old_count)
                    trace_1190("delete-row", career_name, loadout_index, "all", "all",
                        shifted and "overlay-shifted" or "no-overlay")
                    observe_1190("row-delete", {
                        career = career_name, row = loadout_index,
                        old_count = old_count, new_count = new_count,
                        overlay_shifted = shifted == true,
                    })
                end
                return result
            end)

            -- Selected-row read mirror. Bot lookups always remain vanilla.
            mod:hook(items_interface, "get_loadout_item_id", function(func, self, career_name, slot_name, is_bot)
                if not feature_enabled(mod, "enable_weapon_backend_hooks", true) then
                    M.clear_loadout_cache("backend-hooks-disabled")
                    return func(self, career_name, slot_name, is_bot)
                end

                -- audit 2026-06-07: vanilla get_loadout_item_id(self, career, slot, is_bot)
                -- (backend_interface_item_playfab.lua:512) takes a 4th `is_bot` arg that this
                -- hook previously DROPPED on both fall-through calls, so bot loadout lookups
                -- silently resolved via the player-default path. Only answer the LOCAL
                -- player's loadout from our modded cache; bot queries fall through to vanilla
                -- (bots have their own loadout) with is_bot preserved.
                if is_bot then
                    _bot_read_depth = _bot_read_depth + 1
                    local ok, result = pcall(func, self, career_name, slot_name, is_bot)
                    _bot_read_depth = _bot_read_depth - 1
                    observe_1190("bot-read", {
                        career = career_name, slot = slot_name,
                        effective_id = ok and result or nil, route = "vanilla", ok = ok,
                    })
                    if not ok then error(result) end
                    return result
                end

                local loadout_index = get_career_state(self, career_name)
                local cached_id, item = get_cached_backend_item(
                    self, career_name, loadout_index, slot_name)
                local weapon_key = item and (item.key or (item.data and item.data.key))
                if cached_id then
                    trace_1190("read-item", career_name, loadout_index,
                        slot_name, weapon_key, "override")
                    observe_1190("selected-read", {
                        career = career_name, row = loadout_index,
                        slot = slot_name, effective_id = cached_id,
                        route = "cache", source = "get_loadout_item_id",
                    })
                    return cached_id
                end

                local result = func(self, career_name, slot_name, is_bot)
                observe_1190("selected-read", {
                    career = career_name, row = loadout_index,
                    slot = slot_name, effective_id = result,
                    route = "vanilla", source = "get_loadout_item_id",
                })
                return result
            end)
        end

    end

    -- POTENTIAL BUG (LOW): table-form hook on `ItemGridUI`. If `ItemGridUI`
    -- isn't loaded yet at the moment M.install() runs (called from
    -- weapon_tweaker.lua bottom — after all top-level requires), this would
    -- raise "argument 'obj' should have the 'string/table' type, not 'nil'".
    -- ItemGridUI is loaded by inventory UI dependencies which load early, so
    -- this has not failed in practice. But the safer pattern is the
    -- string-form `mod:hook("ItemGridUI", ...)` per CLAUDE.md.
    mod:hook(ItemGridUI, "_on_category_index_change", function(func, self, index, keep_page_index)
        if feature_enabled(mod, "enable_weapon_ui_hooks", true) then
            if M._filter_dirty and self._category_settings then
                for _, s in ipairs(self._category_settings) do
                    if s._base_item_filter then
                        s.item_filter = s._base_item_filter
                        s._base_item_filter = nil
                    end
                end
                M._filter_dirty = false
            end

            local settings = self._category_settings and self._category_settings[index]
            if settings then
                local career_name = self._career_name
                local weapon_map = weapon_unlock_map[career_name]

                if settings._base_item_filter then
                    settings.item_filter = settings._base_item_filter
                end

                -- CLARIFY: only patch the filter when it's the EXACT vanilla
                -- "melee/ranged adventure mode" filter string. If a different
                -- mod or game mode (Versus, weave, etc.) has changed the
                -- filter, leave it alone — appending `or item_key == "..."`
                -- to a non-matching filter would change semantics.
                local base_filter = settings.item_filter
                if (base_filter == "( slot_type == melee ) and item_rarity ~= magic" or base_filter == "( slot_type == ranged ) and item_rarity ~= magic") and weapon_map then
                    local extra_filter = ""
                    for _, weapon_key in ipairs(weapon_map) do
                        if mod:get("unlock_" .. career_name .. "_" .. weapon_key) then
                            extra_filter = extra_filter .. " or item_key == \"" .. weapon_key .. "\""
                        end
                    end

                    if extra_filter ~= "" then
                        settings._base_item_filter = base_filter
                        settings.item_filter = "(" .. base_filter .. ")" .. extra_filter
                    end
                end
            end
        end

        return func(self, index, keep_page_index)
    end)
end

return M
