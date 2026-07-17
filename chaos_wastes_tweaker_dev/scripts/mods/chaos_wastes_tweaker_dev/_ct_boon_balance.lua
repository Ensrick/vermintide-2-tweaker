-- _ct_boon_balance.lua — Existing-boon balance mutations and wipe recovery.
--
-- Owns save/restore balance tweaks for Khaine's Fury, bomb boons, Ulric's Pack,
-- movement speed, potions, Shard Strike, and Anath Raema, plus the optional
-- defeat-recovery hook. Loaded once by the ct_dev entry manifest.
--
-- Owned by: chaos_wastes_tweaker_dev.lua. Consumed via: one mod:dofile call.

local mod = get_mod("ct_dev")
local context = mod._ct_boon_runtime_context
if type(context) ~= "table" then
    error("[ct:boon-runtime] missing entry-point context")
end
local _dbg = context.dbg
local effective_setting = context.effective_setting
local MOD_VERSION = context.mod_version

local sync_reckless_swings
local sync_bomb_cooldown
local sync_ulric_pack_unlimited_range
local sync_boon_movespeed
-- ============================================================
-- Modified Boons
-- ============================================================

-- CLARIFY: `reckless_swings_originals` doubles as a "tweak active" flag. Non-nil = tweak applied.
-- This avoids double-apply (which would save the already-modified values as "originals" and lose
-- the real originals).
local reckless_swings_originals = nil

-- CLARIFY: Khaine's Fury (internal name `deus_reckless_swings`) softening:
--   vanilla:  health threshold 0.50, self-damage 3 per melee hit
--   tweaked:  health threshold 0.25, self-damage 1 per melee hit
-- Patches THREE places: the on-buff template (governs gameplay), description_values by value_type
-- (the % threshold shown in tooltip's "above X% Health"), and description_values by value_type
-- (the damage shown). The `Localize` hook below also overrides the description text since its
-- formatting may not refer to description_values directly.
--
-- See https://github.com/Ensrick/vermintide-2-tweaker/issues/5 — resolved in v0.7.92-dev.
-- Migration from positional [1]/[3] indexing to name-based lookup via _find_entry_by helper.
-- v0.7.84 added sanity guards that bail safely if FatShark reorders the arrays; name-based
-- lookup is now the default with guards retained as defense-in-depth.

-- HELPER: Find first entry in array where predicate(entry) returns true
-- Avoids hard-coded positional indices if FatShark reorders the templates.
local function _find_entry_by(arr, predicate)
    if not arr then return nil, nil end
    for i, e in ipairs(arr) do
        if predicate(e) then return i, e end
    end
    return nil, nil
end

-- v0.7.103: source-pattern sentinel for GH #5 fix (Reckless Swings name-based
-- lookup, shipped v0.7.92). Read by /ct_regression_test check
-- `reckless_swings_name_based_lookup`. If a future refactor reverts the
-- name-based lookup to positional `buffs[1]`/`description_values[1]`/`[3]`
-- indexing, the most plausible bitrot path also strips this comment block and
-- the marker constant, breaking the check. The marker is also used as an
-- upvalue inside `apply_reckless_swings_tweak` to anchor it to the function
-- body, so a partial revert that nukes the search code but leaves the marker
-- declaration would still fail the source-pattern check via the upvalue read.
local CT_RECKLESS_SWINGS_NAME_LOOKUP_MARKER = "name-based-lookup-v0.7.92"
local function apply_reckless_swings_tweak()
    if reckless_swings_originals then
        return
    end

    local power_up = rawget(_G, "DeusPowerUpTemplates")
    -- v0.7.24 bugfix: previous versions mutated DeusPowerUpBuffTemplates, but
    -- the runtime buff system reads from the GLOBAL `BuffTemplates` table which
    -- received COPIED values via DLCUtils.merge() at game boot
    -- (buff_templates.lua:9532). Mutating the source DeusPowerUpBuffTemplates
    -- has no effect on what the proc function reads — `template.damage_to_deal`
    -- inside `deus_reckless_swings_buff_on_hit` reads from BuffTemplates.
    -- Mutate BuffTemplates directly. Outer-buff health_threshold via
    -- DeusPowerUpTemplates still works because the apply path reads that
    -- table directly (deus_power_up_utils.lua:250).
    local runtime_buffs = rawget(_G, "BuffTemplates")
    if not power_up or not power_up.deus_reckless_swings then
        return
    end

    local tpl = power_up.deus_reckless_swings
    local runtime_buff_entry = runtime_buffs and runtime_buffs.deus_reckless_swings_buff

    -- v0.7.92: name-based lookup via _find_entry_by helper. Searches the buffs array
    -- for the entry where buff_to_add == "deus_reckless_swings_buff" and description_values
    -- for entries with the expected value_type fields. Sanity guards retained as defense-
    -- in-depth: verify name match and numeric types before mutation.
    local buff_index, buff_entry = _find_entry_by(
        tpl.buff_template and tpl.buff_template.buffs,
        function(e) return e and e.buff_to_add == "deus_reckless_swings_buff" end
    )
    if not buff_entry then
        mod:warning("[khaines-fury] buff entry with buff_to_add=deus_reckless_swings_buff not found — skipping tweak")
        return
    end

    -- Find description_values entries by value_type: first "percent" (threshold), then "amount" (damage)
    local dv_threshold_index, dv_threshold = _find_entry_by(
        tpl.description_values,
        function(e) return e and e.value_type == "percent" and type(e.value) == "number" end
    )
    local dv_damage_index, dv_damage = _find_entry_by(
        tpl.description_values,
        function(e) return e and e.value_type == "amount" and type(e.value) == "number" end
    )

    -- Sanity-check: all three lookup targets must exist and be numeric
    if not buff_entry or not dv_threshold or not dv_damage then
        mod:warning("[khaines-fury] vanilla template shape changed (buff=%s, dv_threshold=%s, dv_damage=%s) — skipping tweak",
            tostring(buff_entry ~= nil), tostring(dv_threshold ~= nil), tostring(dv_damage ~= nil))
        return
    end
    if type(buff_entry.health_threshold) ~= "number" or type(dv_threshold.value) ~= "number" or type(dv_damage.value) ~= "number" then
        mod:warning("[khaines-fury] expected numeric fields, got %s/%s/%s — skipping tweak",
            type(buff_entry.health_threshold), type(dv_threshold.value), type(dv_damage.value))
        return
    end

    reckless_swings_originals = {
        buff_index = buff_index,
        health_threshold = buff_entry.health_threshold,
        dv_threshold_index = dv_threshold_index,
        dv_threshold_value = dv_threshold.value,
        dv_damage_index = dv_damage_index,
        dv_damage_value = dv_damage.value,
        buff_damage = runtime_buff_entry and runtime_buff_entry.buffs[1].damage_to_deal,
    }

    buff_entry.health_threshold = 0.25
    dv_threshold.value = 0.25
    dv_damage.value = 1

    if runtime_buff_entry and runtime_buff_entry.buffs and runtime_buff_entry.buffs[1] then
        runtime_buff_entry.buffs[1].damage_to_deal = 1
    end

    -- Read the sentinel marker as an upvalue so a refactor that strips the
    -- name-based search code path also breaks this read site (the closure no
    -- longer captures the marker, so the upvalue resolves to nil). Anchor for
    -- /ct_regression_test source-pattern check `reckless_swings_name_based_lookup`.
    local _marker_anchor = CT_RECKLESS_SWINGS_NAME_LOOKUP_MARKER

    _dbg("[khaines-fury] tweak applied via name-based lookup (buff_index=%d, dv_threshold_index=%d, dv_damage_index=%d, sentinel=%s)",
        buff_index, dv_threshold_index, dv_damage_index, _marker_anchor)
end

-- CLARIFY: Mirrors apply_reckless_swings_tweak. Note the early-out when DeusPowerUpTemplates is
-- gone (e.g. user left Chaos Wastes) — we still clear the originals flag so the next entry can
-- re-apply cleanly. This is the only path that nils the flag without doing the actual restore.
local function revert_reckless_swings_tweak()
    if not reckless_swings_originals then
        return
    end

    local power_up = rawget(_G, "DeusPowerUpTemplates")
    -- v0.7.24: revert from runtime BuffTemplates (same fix as apply).
    local runtime_buffs = rawget(_G, "BuffTemplates")
    if not power_up or not power_up.deus_reckless_swings then
        reckless_swings_originals = nil
        return
    end

    local tpl = power_up.deus_reckless_swings
    local runtime_buff_entry = runtime_buffs and runtime_buffs.deus_reckless_swings_buff

    -- v0.7.92: revert using stored indices from apply (name-based lookup)
    if tpl.buff_template and tpl.buff_template.buffs then
        local buff_entry = tpl.buff_template.buffs[reckless_swings_originals.buff_index]
        if buff_entry then
            buff_entry.health_threshold = reckless_swings_originals.health_threshold
        end
    end
    if tpl.description_values then
        local dv_threshold = tpl.description_values[reckless_swings_originals.dv_threshold_index]
        local dv_damage = tpl.description_values[reckless_swings_originals.dv_damage_index]
        if dv_threshold then
            dv_threshold.value = reckless_swings_originals.dv_threshold_value
        end
        if dv_damage then
            dv_damage.value = reckless_swings_originals.dv_damage_value
        end
    end

    if runtime_buff_entry and runtime_buff_entry.buffs and runtime_buff_entry.buffs[1] and reckless_swings_originals.buff_damage then
        runtime_buff_entry.buffs[1].damage_to_deal = reckless_swings_originals.buff_damage
    end

    reckless_swings_originals = nil
end

-- CLARIFY: Description override for Khaine's Fury lives in the consolidated _G.Localize
-- hook above (search for ADV_TITLE_OVERRIDES). Centralized to avoid the VMF
-- "Attempting to rehook active hook [Localize]" warning when two hooks compete for the
-- same target. The `reckless_swings_originals` gate ensures the override only fires
-- while the tweak is active.

-- CLARIFY: Assignment to the forward-declared `sync_reckless_swings`. From here on, references at
-- the top of the file (in generate_random_power_ups hook) and the on_setting_changed callback
-- below resolve to this function.
sync_reckless_swings = function()
    if effective_setting("tweak_reckless_swings") then
        apply_reckless_swings_tweak()
    else
        revert_reckless_swings_tweak()
    end
end

-- CLARIFY: Apply once at mod load. If the user has the toggle on AND DeusPowerUpTemplates is
-- already loaded (e.g. they enter the Keep, hot-reload doesn't apply since chaos_wastes_tweaker is
-- restart-only per CLAUDE.md), this immediately patches. Outside CW, DeusPowerUpTemplates is nil
-- and the apply silently no-ops; the generate_random_power_ups hook re-runs sync on first roll.
sync_reckless_swings()

-- ============================================================
-- Bomb Boon Cooldown Tweak
-- ============================================================
-- The `drop_item_on_ability_use` boon (rally flag / Morgrim's / Endless Bombs) reads its per-item
-- cooldowns from `buff_template.buffs[1].cooldown_durations` at proc time
-- (morris_buff_settings.lua:2830). Mutating that table in place lets us uniformly override the
-- vanilla 180/180/120 with a single configurable value. Mirrors the reckless_swings save-and-
-- restore pattern: the mutation persists across hook calls within a session, so on_disabled has
-- to revert it.

local bomb_cooldown_originals = nil

local function apply_bomb_cooldown_tweak()
    if bomb_cooldown_originals then
        return
    end
    local power_up = rawget(_G, "DeusPowerUpTemplates")
    local tpl = power_up and power_up.drop_item_on_ability_use
    local buff_entry = tpl and tpl.buff_template and tpl.buff_template.buffs and tpl.buff_template.buffs[1]
    local durations = buff_entry and buff_entry.cooldown_durations
    if not durations then
        _dbg("[bomb-cooldown] DeusPowerUpTemplates.drop_item_on_ability_use not loaded yet; will retry on next boon roll")
        return
    end

    local override = effective_setting("bomb_boon_cooldown")
    if not override or override <= 0 then
        _dbg("[bomb-cooldown] override=%s (no change)", tostring(override))
        return
    end

    bomb_cooldown_originals = {}
    local before = {}
    for k, v in pairs(durations) do
        before[#before + 1] = string.format("%s=%d", k, v)
        bomb_cooldown_originals[k] = v
        durations[k] = override
    end
    _dbg("[bomb-cooldown] override=%d applied. Was: %s", override, table.concat(before, ", "))
end

local function revert_bomb_cooldown_tweak()
    if not bomb_cooldown_originals then
        return
    end
    local power_up = rawget(_G, "DeusPowerUpTemplates")
    local tpl = power_up and power_up.drop_item_on_ability_use
    local buff_entry = tpl and tpl.buff_template and tpl.buff_template.buffs and tpl.buff_template.buffs[1]
    local durations = buff_entry and buff_entry.cooldown_durations
    if durations then
        for k, v in pairs(bomb_cooldown_originals) do
            durations[k] = v
        end
    end
    bomb_cooldown_originals = nil
end

sync_bomb_cooldown = function()
    -- Always revert first so a setting change from one positive value to another re-applies the
    -- new value (rather than silently no-op'ing because originals are already saved).
    revert_bomb_cooldown_tweak()
    local override = effective_setting("bomb_boon_cooldown")
    if override and override > 0 then
        apply_bomb_cooldown_tweak()
    end
end

sync_bomb_cooldown()

-- #120 (v0.7.177-dev): the template-mutation above mutates the SOURCE
-- DeusPowerUpTemplates table, but the runtime buff resolves `buff.template` from a
-- registered copy (same copy-vs-source trap that forced reckless_swings to patch both
-- tables) — so the cooldown override "did nothing". This hook makes the override
-- authoritative by working on the LIVE buff: it wraps the `drop_item_on_ability_use`
-- proc (morris_buff_settings.lua:2742 — drops a bomb/medkit/potion when you pop your
-- career ult, then arms the `drop_item_on_ability_use_cooldown` buff whose duration
-- gates the next drop) and, after vanilla runs, overrides that cooldown buff's
-- duration to the user's configured interval. Vanilla itself sets `buff.duration`
-- AFTER add_buff (line 2830), so a post-call duration write is the supported pattern
-- and works for intervals SHORTER or longer than the vanilla 180/180/120. interval 0
-- = leave vanilla untouched. Runs on the proc'ing player's machine; the interval is
-- host-synced via effective_setting so every peer uses the host's value.
-- #120 fix (v0.7.214-dev RETARGET): the real reason the cooldown "did nothing" was
-- that this hook was never installed. `drop_item_on_ability_use` is a PROC function,
-- dispatched at proc time via `ProcFunctions[buff.buff_func]`
-- (buff_extension.lua:1351-1352) and registered into the global `ProcFunctions`
-- (DLCSettings.morris.proc_functions -> DLCUtils.merge, buff_templates.lua:9589). It
-- is NOT a member of `BuffFunctionTemplates.functions` (that key is nil there), so the
-- old guard was always false and `mod:hook` never ran -> total no-op. Retargeted to the
-- global `ProcFunctions`; the dispatch re-reads `ProcFunctions[name]` on EVERY proc
-- (no add-buff caching), so a table-entry hook is honored. The wrapper CAPTURES and
-- RETURNS the proc's value: dispatch does `success = buff_func(...)` and `success`
-- gates `remove_on_proc` removal (buff_extension.lua:1354). Vanilla's proc returns nil,
-- so this is behavior-identical today, but returning it keeps us correct if a future
-- patch makes the proc return a value.
if rawget(_G, "ProcFunctions") and ProcFunctions.drop_item_on_ability_use then
    mod:hook(ProcFunctions, "drop_item_on_ability_use", function(func, owner_unit, buff, params, ...)
        local ret = func(owner_unit, buff, params, ...)

        local interval = effective_setting("bomb_boon_cooldown")
        if interval and interval > 0 and rawget(_G, "ALIVE") and ALIVE[owner_unit] then
            local buff_ext = ScriptUnit.has_extension(owner_unit, "buff_system")
            local cd = buff_ext and buff_ext.get_non_stacking_buff
                and buff_ext:get_non_stacking_buff("drop_item_on_ability_use_cooldown")
            if cd then
                -- Re-anchors to the ORIGINAL drop: start_time is unchanged, so
                -- end_time = start_time + interval. Idempotent across repeat pops.
                cd.duration = interval
                pcall(printf, "[ct-bomb-boon] drop_item cooldown overridden -> %ds", interval)
            end
        end

        return ret
    end)
end

-- ============================================================
-- #120 (v0.7.230-dev): rate-limit the BOMB-BUBBLE boons (the real #120 target)
-- ============================================================
-- The hook above gates `drop_item_on_ability_use` (drop-a-bomb-on-ult). But #120 is
-- about the "bomb bubble" boon set (`boon_supportbomb_concentration/crit/healing/
-- speed_01`), which that hook never touches. Confirmed from console
-- 2026-07-05-23.03.16 (v0.7.229-dev): the player held `boon_supportbomb_concentration_01`
-- yet ZERO `[ct-bomb-boon]` markers fired -- because those boons proc through a DIFFERENT
-- function, `grenade_explode_buff_area` on the `on_grenade_exploded` event
-- (deus_power_up_settings.lua:4389+, shared by all four supportbomb boons; body at
-- morris_buff_settings.lua:3131), which just `add_buff`s the AoE zone on EVERY grenade
-- explosion with NO cooldown (boon_supportbomb_shared_data = {duration=10, radius=6} only,
-- buff_tweak_data.lua:583). So the same `bomb_boon_cooldown` interval now ALSO gates the
-- bubbles. `grenade_explode_buff_area` is a global `ProcFunctions` member (re-read per
-- proc -> table hook honored) and server-only (its own is_server guard), so the
-- host-synced interval applies uniformly. Duplicate-hook pre-flight: zero prior ct hooks
-- on grenade_explode_buff_area (grep). Last-proc time is stamped on the buff INSTANCE
-- (`_ct_last_bubble_t`) -> naturally per-owner + per-boon, auto-cleared when the run's
-- buff is removed. interval 0 = leave vanilla untouched (a bubble every explosion).
if rawget(_G, "ProcFunctions") and ProcFunctions.grenade_explode_buff_area then
    mod:hook(ProcFunctions, "grenade_explode_buff_area", function(func, owner_unit, buff, params, ...)
        local interval = effective_setting("bomb_boon_cooldown")
        if interval and interval > 0 and buff then
            local t = Managers and Managers.time and Managers.time:time("game")
            if t then
                local name = buff.template and buff.template.name or "?"
                local last = buff._ct_last_bubble_t
                if last and (t - last) < interval then
                    pcall(printf, "[ct-bomb-boon] supportbomb '%s' gated: %.1fs since last < %ds -> bubble skipped",
                        tostring(name), t - last, interval)
                    return  -- rate-limited: skip the buff-area spawn this explosion
                end
                buff._ct_last_bubble_t = t
                -- Presentation only: the display module either applies a local HUD
                -- buff for the host-owner or sends one bounded, owner-targeted VMF
                -- event. It cannot alter this gate's timestamp or vanilla proc call.
                mod._ct_bomb_cooldown_display.notify_allowed(owner_unit, name, interval)
                pcall(printf, "[ct-bomb-boon] supportbomb '%s' proc allowed (min interval %ds)",
                    tostring(name), interval)
            end
        end
        return func(owner_unit, buff, params, ...)
    end)
end

-- ============================================================
-- Ulric's Pack (wolfpack) Unlimited Aura Range
-- ============================================================
-- Vanilla `wolfpack` boon's proximity buff has `range_check = { radius = 20, ... }`
-- (deus_power_up_settings.lua:3829-3835). BuffAreaHelper.update_range_check reads
-- `range_check_template.radius` fresh on every tick (buff_area_helper.lua:26), so a
-- one-time mutation of that field is sufficient — no per-frame hook needed. Mirror
-- the bomb_cooldown save-and-restore pattern: on_setting_changed re-syncs without
-- restart, and revert lets toggling off restore vanilla 20m radius.
--
-- Per `feedback_vt2_gated_registration_diverges.md`: this only mutates an existing
-- vanilla template field; it never registers/unregisters the boon, never touches
-- BuffTemplates, NetworkLookup, or any sequential-index table. Safe to gate on the
-- per-user toggle. Host-authoritative: each peer mutates locally for their own
-- buff-extension proximity ticks, and the buff itself is applied via standard
-- buff-system propagation so client peers without the toggle still see the buff's
-- effect — they just compute their own proximity passes at vanilla 20m. Toggle the
-- host's setting and the host's proximity passes (which drive who gets the buff
-- via wolfpack_entered_range/wolfpack_left_range RPCs) ignore distance.

local wolfpack_radius_original = nil

local function apply_wolfpack_unlimited_range()
    if wolfpack_radius_original ~= nil then
        return
    end
    local power_up = rawget(_G, "DeusPowerUpTemplates")
    local tpl = power_up and power_up.wolfpack
    local buff_entry = tpl and tpl.buff_template and tpl.buff_template.buffs and tpl.buff_template.buffs[1]
    local rc = buff_entry and buff_entry.range_check
    if not rc or type(rc.radius) ~= "number" then
        _dbg("[ulric-pack-range] DeusPowerUpTemplates.wolfpack not loaded yet; will retry on next sync")
        return
    end
    wolfpack_radius_original = rc.radius
    rc.radius = math.huge
    _dbg("[ulric-pack-range] radius %s -> math.huge", tostring(wolfpack_radius_original))
end

local function revert_wolfpack_unlimited_range()
    if wolfpack_radius_original == nil then
        return
    end
    local power_up = rawget(_G, "DeusPowerUpTemplates")
    local tpl = power_up and power_up.wolfpack
    local buff_entry = tpl and tpl.buff_template and tpl.buff_template.buffs and tpl.buff_template.buffs[1]
    local rc = buff_entry and buff_entry.range_check
    if rc then
        rc.radius = wolfpack_radius_original
    end
    wolfpack_radius_original = nil
end

sync_ulric_pack_unlimited_range = function()
    revert_wolfpack_unlimited_range()
    if effective_setting("ulric_pack_unlimited_range") then
        apply_wolfpack_unlimited_range()
    end
end

sync_ulric_pack_unlimited_range()

-- ============================================================
-- Movement Speed Boon Tweak (5% -> 10%)
-- ============================================================
-- The vanilla `movespeed` boon (a one-of-a-kind CW mission-completion reward, boon-treated)
-- adds `apply_movement_buff` with multiplier 1.05 (sourced from
-- `MorrisBuffTweakData.movespeed.multiplier`) and shows "5%" in the tooltip (sourced from
-- `MorrisBuffTweakData.movespeed.description_value`). The values are baked at game load by
-- `deus_power_up_settings.lua` into two places:
--   * Gameplay: `DeusPowerUpBuffTemplates.power_up_movespeed_<rarity>.buffs[1].multiplier` (1.05),
--     one entry per rarity (common/rare/legendary).
--   * Tooltip:  `DeusPowerUpTemplates.movespeed.description_values[1].value` (0.05), shared by
--     all rarities via reference — a single mutation propagates to every rarity tooltip.
-- We mirror the reckless_swings save-and-restore: snapshot originals on apply, restore them on
-- revert, and call sync from the boon-roll hook + on_setting_changed.

local MOVESPEED_RARITIES = { "common", "rare", "legendary" }
local boon_movespeed_originals = nil

local function apply_boon_movespeed_tweak()
    if boon_movespeed_originals then
        return
    end

    local power_up = rawget(_G, "DeusPowerUpTemplates")
    local buff_tpls = rawget(_G, "DeusPowerUpBuffTemplates")
    local tpl = power_up and power_up.movespeed
    if not tpl or not buff_tpls then
        return
    end

    local desc_value_entry = tpl.description_values and tpl.description_values[1]
    if not desc_value_entry then
        return
    end

    local per_rarity = {}
    for i = 1, #MOVESPEED_RARITIES do
        local rarity = MOVESPEED_RARITIES[i]
        local buff_entry = buff_tpls["power_up_movespeed_" .. rarity]
        local sub = buff_entry and buff_entry.buffs and buff_entry.buffs[1]
        if sub and sub.multiplier then
            per_rarity[rarity] = sub.multiplier
            sub.multiplier = 1.10
        end
    end

    boon_movespeed_originals = {
        desc_value = desc_value_entry.value,
        per_rarity = per_rarity,
    }

    desc_value_entry.value = 0.10
end

local function revert_boon_movespeed_tweak()
    if not boon_movespeed_originals then
        return
    end

    local power_up = rawget(_G, "DeusPowerUpTemplates")
    local buff_tpls = rawget(_G, "DeusPowerUpBuffTemplates")
    local tpl = power_up and power_up.movespeed
    local desc_value_entry = tpl and tpl.description_values and tpl.description_values[1]

    if desc_value_entry then
        desc_value_entry.value = boon_movespeed_originals.desc_value
    end

    if buff_tpls then
        for rarity, original_mult in pairs(boon_movespeed_originals.per_rarity) do
            local buff_entry = buff_tpls["power_up_movespeed_" .. rarity]
            local sub = buff_entry and buff_entry.buffs and buff_entry.buffs[1]
            if sub then
                sub.multiplier = original_mult
            end
        end
    end

    boon_movespeed_originals = nil
end

sync_boon_movespeed = function()
    if effective_setting("tweak_boon_movespeed") then
        apply_boon_movespeed_tweak()
    else
        revert_boon_movespeed_tweak()
    end
end

sync_boon_movespeed()

-- ============================================================
-- Potion Reworks (v0.7.26-alpha)
-- ============================================================
-- BuffTemplates is the runtime merged table built by DLCUtils.merge at boot
-- (`buff_templates.lua:5568`-ish). Source `DLCSettings.morris.buff_templates` is the
-- per-DLC definition; mutating it after merge has no effect on what the runtime reads
-- (same gotcha as Khaine's Fury v0.7.24). All mutations target `BuffTemplates.<name>`
-- directly.
--
-- Pattern matches reckless_swings: snapshot originals once on apply, restore on revert,
-- re-run sync on settings change. The action's vanilla `_increased` resolution (in
-- `action_potion.lua:68`, gated on `potion_duration` perk) automatically picks up the
-- modified `_increased` variant when Decanter is held — no extra plumbing needed for
-- Decanter composition.
--
-- TODO v0.7.27: Home Brewer composition (+50% potency when home_brewer is held). Needs
-- a buff-apply hook + `_brewed` / `_brewed_increased` variant registration in
-- NetworkLookup.buff_templates.

-- --- Poison Proof duration tweak (vanilla 120s/240s -> 240s/360s) ---
local poison_proof_originals = nil

local function apply_poison_proof_tweak()
    if poison_proof_originals then
        return
    end
    local bt = rawget(_G, "BuffTemplates")
    local base = bt and bt.poison_proof_potion
    local inc = bt and bt.poison_proof_potion_increased
    local base_buff = base and base.buffs and base.buffs[1]
    local inc_buff = inc and inc.buffs and inc.buffs[1]
    if not base_buff or not inc_buff then
        _dbg("[poison-proof] BuffTemplates not loaded yet; will retry on settings sync")
        return
    end
    poison_proof_originals = {
        base = base_buff.duration,
        inc = inc_buff.duration,
    }
    base_buff.duration = 240
    inc_buff.duration = 360
    _dbg(string.format("[poison-proof] applied: base=%s -> 240, increased=%s -> 360",
        tostring(poison_proof_originals.base), tostring(poison_proof_originals.inc)))
end

local function revert_poison_proof_tweak()
    if not poison_proof_originals then
        return
    end
    local bt = rawget(_G, "BuffTemplates")
    local base_buff = bt and bt.poison_proof_potion and bt.poison_proof_potion.buffs and bt.poison_proof_potion.buffs[1]
    local inc_buff = bt and bt.poison_proof_potion_increased and bt.poison_proof_potion_increased.buffs and bt.poison_proof_potion_increased.buffs[1]
    if base_buff then base_buff.duration = poison_proof_originals.base end
    if inc_buff then inc_buff.duration = poison_proof_originals.inc end
    poison_proof_originals = nil
end

local function sync_poison_proof_tweak()
    if effective_setting("tweak_poison_proof_duration") then
        apply_poison_proof_tweak()
    else
        revert_poison_proof_tweak()
    end
end

sync_poison_proof_tweak()

-- --- Killer in the Shadows (invisibility potion) 2x duration ---
-- Vanilla: base 5s / increased 15s (MorrisBuffTweakData.killer_in_the_shadows_potion.duration).
-- BuffTemplates copies duration by value at template generation, so we mutate the
-- BuffTemplates entry directly (the MorrisBuffTweakData mutation is a no-op post-boot).
local invis_potion_originals = nil

local function apply_invis_potion_tweak()
    if invis_potion_originals then
        return
    end
    local bt = rawget(_G, "BuffTemplates")
    local base = bt and bt.killer_in_the_shadows_potion
    local inc = bt and bt.killer_in_the_shadows_potion_increased
    local base_buff = base and base.buffs and base.buffs[1]
    local inc_buff = inc and inc.buffs and inc.buffs[1]
    if not base_buff or not inc_buff then
        _dbg("[invis-potion] BuffTemplates not loaded yet; will retry on settings sync")
        return
    end
    invis_potion_originals = {
        base = base_buff.duration,
        inc = inc_buff.duration,
    }
    base_buff.duration = (invis_potion_originals.base or 5) * 2
    inc_buff.duration = (invis_potion_originals.inc or 15) * 2
    _dbg(string.format("[invis-potion] applied: base=%s -> %s, increased=%s -> %s",
        tostring(invis_potion_originals.base), tostring(base_buff.duration),
        tostring(invis_potion_originals.inc), tostring(inc_buff.duration)))
end

local function revert_invis_potion_tweak()
    if not invis_potion_originals then
        return
    end
    local bt = rawget(_G, "BuffTemplates")
    local base_buff = bt and bt.killer_in_the_shadows_potion and bt.killer_in_the_shadows_potion.buffs and bt.killer_in_the_shadows_potion.buffs[1]
    local inc_buff = bt and bt.killer_in_the_shadows_potion_increased and bt.killer_in_the_shadows_potion_increased.buffs and bt.killer_in_the_shadows_potion_increased.buffs[1]
    if base_buff then base_buff.duration = invis_potion_originals.base end
    if inc_buff then inc_buff.duration = invis_potion_originals.inc end
    invis_potion_originals = nil
end

local function sync_invis_potion_tweak()
    if effective_setting("tweak_invis_potion_2x") then
        apply_invis_potion_tweak()
    else
        revert_invis_potion_tweak()
    end
end

sync_invis_potion_tweak()

-- --- Hangover Brew (moot_milk) alternative effect ---
-- Vanilla buff structure (morris_buff_settings.lua:5804): 3 buffs
--   1. screenspace FX (`fx/screenspace_hungover_01`)
--   2. movespeed (apply_movement_buff, +50% MS for 1.5s)
--   3. damage (stat_buff increased_weapon_damage, multiplier 1)
-- Alt structure: 3 buffs for 60s
--   1. screenspace FX (keep hungover for visual feedback)
--   2. movement speed +25% for full duration
--   3. infinite_dodge perk
--   4. stamina regen (fatigue_regen stat_buff) +40%
-- Decanter automatically picks `_increased` (90s) via vanilla action_potion.lua resolution.

local moot_milk_originals = nil

local function build_moot_milk_alt_buffs(duration)
    return {
        {
            activation_effect = "fx/screenspace_drink_01",
            continuous_effect = "fx/screenspace_drink_looping",
            icon = "potion_hold_my_beer",
            max_stacks = 1,
            name = "moot_milk_potion",
            refresh_durations = true,
            remove_buff_func = "remove_deus_potion_buff",
            duration = duration,
        },
        {
            -- v0.7.50: WAS 0.25 (which is a literal multiplier on move_speed, so the player
            -- moved at 25% of base speed — a -75% slow). `apply_movement_buff` does
            -- `move_speed *= multiplier`; vanilla speed_boost_potion uses 1.5 for +50%.
            -- 1.25 = +25% as the surrounding comment / changelog have always claimed.
            apply_buff_func = "apply_movement_buff",
            max_stacks = 1,
            name = "moot_milk_potion_movement_speed_alt",
            refresh_durations = true,
            remove_buff_func = "remove_movement_buff",
            duration = duration,
            multiplier = 1.25,
            path_to_movement_setting_to_modify = {
                "move_speed",
            },
        },
        {
            max_stacks = 1,
            name = "moot_milk_potion_infinite_dodge_alt",
            refresh_durations = true,
            duration = duration,
            perks = {
                -- v0.7.44: was `buff_perks.infinite_dodge`. The `buff_perks` global is
                -- a `table.enum` map of name → name string. At mod-load timing it isn't
                -- always populated in `_G` (the buff system's perk_names file is
                -- required AFTER mods init in some load orders), so the lookup returned
                -- nil and the apply silently bailed at the `rawget(_G, "buff_perks")`
                -- gate below — meaning Moot Milk stayed vanilla for the whole session.
                -- Using the literal string is functionally identical (the buff system
                -- looks up perks by string key, which IS what `table.enum` stores).
                "infinite_dodge",
            },
        },
        {
            max_stacks = 1,
            name = "moot_milk_potion_stamina_regen_alt",
            refresh_durations = true,
            stat_buff = "fatigue_regen",
            duration = duration,
            multiplier = 0.40,
        },
    }
end

local function apply_moot_milk_alt_tweak()
    if moot_milk_originals then
        return
    end
    local bt = rawget(_G, "BuffTemplates")
    local base = bt and bt.moot_milk_potion
    local inc = bt and bt.moot_milk_potion_increased
    if not base or not inc then
        _dbg("[moot-milk-alt] BuffTemplates not loaded yet; will retry on settings sync")
        return
    end
    -- v0.7.44: removed `buff_perks` gate. The previous gate bailed when the global
    -- wasn't populated yet (logged in 2026-05-15 session); the replacement uses the
    -- literal string "infinite_dodge" in build_moot_milk_alt_buffs above, which is
    -- functionally equivalent and doesn't require the global.
    moot_milk_originals = {
        base_buffs = base.buffs,
        inc_buffs = inc.buffs,
    }
    base.buffs = build_moot_milk_alt_buffs(60)
    inc.buffs = build_moot_milk_alt_buffs(90)
    _dbg("[moot-milk-alt] applied: base=60s, increased=90s (+25%% MS, infinite dodge, +40%% stamina regen)")
end

local function revert_moot_milk_alt_tweak()
    if not moot_milk_originals then
        return
    end
    local bt = rawget(_G, "BuffTemplates")
    if bt and bt.moot_milk_potion then bt.moot_milk_potion.buffs = moot_milk_originals.base_buffs end
    if bt and bt.moot_milk_potion_increased then bt.moot_milk_potion_increased.buffs = moot_milk_originals.inc_buffs end
    moot_milk_originals = nil
end

local function sync_moot_milk_alt_tweak()
    if effective_setting("tweak_moot_milk_alt") then
        apply_moot_milk_alt_tweak()
    else
        revert_moot_milk_alt_tweak()
    end
end

sync_moot_milk_alt_tweak()

-- ============================================================
-- Shard Strike duration nerf (v0.7.28b-alpha)
-- ============================================================
-- Shard Strike (`armor_breaker` weapon trait) spawns a 16-second damaging stagger aura
-- around the player on killing an armoured enemy. Vanilla 16s is widely considered
-- overtuned (top-tier offensive AND defensive). This nerf lets the user shorten the
-- duration to any value 1-16s. At 16 = vanilla (no-op).
--
-- Mutates `WeaponTraits.buff_templates.armor_breaker.buffs[1].duration` directly. The
-- buff template is merged from `weapon_traits_morris.lua:980` (BuffUtils.apply_buff_tweak_data)
-- and registered at game boot, so the runtime value is whatever lives in WeaponTraits at
-- the moment add_buff is called. Mod load happens after merge, so our mutation takes
-- effect for all subsequent procs. ALSO mutates `BuffTemplates.armor_breaker` if present
-- (defensive — some merge paths copy into the global BuffTemplates).
local shard_strike_originals = nil

local function _shard_strike_buff_entries()
    local out = {}
    local wt = rawget(_G, "WeaponTraits")
    local wt_buff = wt and wt.buff_templates and wt.buff_templates.armor_breaker and wt.buff_templates.armor_breaker.buffs and wt.buff_templates.armor_breaker.buffs[1]
    if wt_buff then out[#out+1] = wt_buff end
    local bt = rawget(_G, "BuffTemplates")
    local bt_buff = bt and bt.armor_breaker and bt.armor_breaker.buffs and bt.armor_breaker.buffs[1]
    if bt_buff then out[#out+1] = bt_buff end
    return out
end

local function revert_shard_strike_tweak()
    if not shard_strike_originals then return end
    for _, b in ipairs(_shard_strike_buff_entries()) do
        b.duration = shard_strike_originals.duration
    end
    shard_strike_originals = nil
end

local function apply_shard_strike_tweak()
    local user_value = effective_setting("tweak_shard_strike_duration") or 16
    local target = math.max(1, math.min(16, user_value))
    if target == 16 then
        revert_shard_strike_tweak()
        return
    end
    local entries = _shard_strike_buff_entries()
    if #entries == 0 then
        _dbg("[shard-strike] WeaponTraits.buff_templates.armor_breaker not loaded yet; will retry on settings sync")
        return
    end
    if not shard_strike_originals then
        shard_strike_originals = { duration = entries[1].duration }
    end
    for _, b in ipairs(entries) do
        b.duration = target
    end
end

local function sync_shard_strike()
    apply_shard_strike_tweak()
end

sync_shard_strike()

-- ============================================================
-- Anath Raema's Swiftness — permanent reload speed (v0.7.36-alpha)
-- ============================================================
-- Vanilla: the trait `deus_ammo_pickup_reload_speed` watches `on_consumable_picked_up`
-- and adds a 10-second `deus_ammo_pickup_reload_speed_buff` (+50% reload speed) on
-- ammo pickup. This rework swaps the parent trait template for a passive permanent
-- +50% `reload_speed` stat_buff that's active whenever the weapon (with the trait) is
-- wielded.
--
-- Mutates BOTH `WeaponTraits.buff_templates.deus_ammo_pickup_reload_speed` (the trait
-- registry the trait system reads at apply time) AND `BuffTemplates.deus_ammo_pickup_reload_speed`
-- (the global runtime buff lookup). Save-and-restore so the toggle is reversible.
local anath_raema_originals = nil
CT_ANATH_RAEMA_RETRY_MARKER = "anath_raema:enforce_at_add_buff_v0.7.268"

local function _anath_raema_buff_entries()
    local out = {}
    local wt = rawget(_G, "WeaponTraits")
    if wt and wt.buff_templates and wt.buff_templates.deus_ammo_pickup_reload_speed then
        out[#out + 1] = { id = "weapon_traits", tbl = wt.buff_templates, key = "deus_ammo_pickup_reload_speed" }
    end
    local bt = rawget(_G, "BuffTemplates")
    if bt and bt.deus_ammo_pickup_reload_speed then
        out[#out + 1] = { id = "buff_templates", tbl = bt, key = "deus_ammo_pickup_reload_speed" }
    end
    return out
end

local function revert_anath_raema_permanent_tweak()
    if not anath_raema_originals then return end
    for _, e in ipairs(_anath_raema_buff_entries()) do
        e.tbl[e.key] = anath_raema_originals.templates[e.id] or e.tbl[e.key]
    end
    anath_raema_originals = nil
end

local function apply_anath_raema_permanent_tweak()
    local entries = _anath_raema_buff_entries()
    if #entries == 0 then
        _dbg("[anath-raema] templates not loaded yet; will retry on settings sync")
        return
    end
    -- The two registries can become available on different frames. Preserve each
    -- independently and enforce every currently available entry on every retry.
    if not anath_raema_originals then
        anath_raema_originals = { templates = {} }
    end

    -- Replacement template: single permanent stat_buff. multiplier = -0.5 matches the
    -- vanilla on-pickup multiplier MorrisBuffTweakData.deus_ammo_pickup_reload_speed_buff.multiplier
    -- (buff_tweak_data.lua:225 = -0.5). The `reload_speed` stat_buff scales the reload HOLD TIME
    -- (weapon_unit_extension.lua:966 -> apply_buffs_to_value -> value * (1 + multiplier),
    -- buff_extension.lua:1431-1432), so it is an INVERSE stat: a NEGATIVE multiplier shortens the
    -- hold time = FASTER reload. Every vanilla faster-reload buff is negative (Bounty Hunter passive
    -- -0.2, Huntsman ability -0.4). A prior +0.5 here multiplied hold time by 1.5 = 50% SLOWER (#464).
    local replacement = anath_raema_originals.replacement
    if not replacement then
        replacement = {
            buffs = {
                {
                    name        = "deus_ammo_pickup_reload_speed_permanent",
                    stat_buff   = "reload_speed",
                    multiplier  = -0.5,
                    max_stacks  = 1,
                },
            },
        }
        anath_raema_originals.replacement = replacement
    end
    for _, e in ipairs(entries) do
        if not anath_raema_originals.templates[e.id] then
            local original = e.tbl[e.key]
            -- A later registry may have been assembled from the earlier one after
            -- CT patched it. Never preserve our replacement as the "vanilla" value.
            if original == replacement then
                original = anath_raema_originals.templates.weapon_traits
                    or anath_raema_originals.templates.buff_templates
            end
            if original and original ~= replacement then
                anath_raema_originals.templates[e.id] = original
            end
        end
        e.tbl[e.key] = replacement
    end
end

local function sync_anath_raema_permanent()
    if effective_setting("tweak_anath_raema_permanent") then
        apply_anath_raema_permanent_tweak()
    else
        revert_anath_raema_permanent_tweak()
    end
end

sync_anath_raema_permanent()

mod:command("ct_verify_anath_raema", "Report #288 template and active reload-buff state (wield the trait weapon first)", function()
    local bt = rawget(_G, "BuffTemplates")
    local tpl = bt and bt.deus_ammo_pickup_reload_speed
    local sb = tpl and tpl.buffs and tpl.buffs[1]
    mod:echo("=== ct #288 Anath Raema (v%s) ===", MOD_VERSION)
    mod:echo("setting=%s template_child=%s stat=%s multiplier=%s event=%s",
        tostring(effective_setting("tweak_anath_raema_permanent")),
        tostring(sb and sb.name), tostring(sb and sb.stat_buff),
        tostring(sb and sb.multiplier), tostring(sb and sb.event))

    local pl = Managers.player and Managers.player:local_player()
    local unit = pl and pl.player_unit
    local be = unit and Unit.alive(unit) and ScriptUnit.has_extension(unit, "buff_system")
    if not be then
        mod:echo("active=unavailable (enter the keep/mission and wield the trait weapon)")
        return
    end
    local active = 0
    for _, buff in pairs(be._buffs or {}) do
        if buff.buff_template_name == "deus_ammo_pickup_reload_speed" then
            active = active + 1
            mod:echo("active[%d] child=%s stat=%s multiplier=%s event=%s",
                active, tostring(buff.buff_type), tostring(buff.template and buff.template.stat_buff),
                tostring(buff.multiplier), tostring(buff.template and buff.template.event))
        end
    end
    mod:echo("active_count=%d total_reload_time_scale=%s expected_trait_scale=0.5",
        active, tostring(be:apply_buffs_to_value(1, "reload_speed")))
end)

-- ============================================================
-- Defeat Recovery: soft wipe recovery with penalty (v0.7.39-alpha)
-- ============================================================
-- When `tweak_defeat_recovery` is on and the team would wipe, instead force-respawn
-- everyone in place and apply a penalty: zero own coins + remove 5 random own boons.
-- The mission continues from the wipe point — this is NOT a full level reload (the
-- engine doesn't expose a safe mid-run "reload current level" path; that'd require a
-- full level transition with all the run-state replication that entails).
--
-- LIMITATIONS:
-- * Per-peer locality: each peer applies the penalty to their OWN coins and boons.
--   In MP, every peer needs ct with the toggle on for the team to share the rescue.
--   If only the host has ct, the host doesn't lose / the run continues, but other
--   peers' coins/boons are not modified.
-- * Recovery fires once per round (per level). Subsequent wipes on the same level end
--   the run normally. This prevents infinite loops and keeps recovery a finite resource.
-- * Reset on level transition via the existing `_transition_next_node` hook.
-- (Flag itself is forward-declared near the top of the file; just used here.)

local function _apply_local_defeat_penalty()
    local mechanism = Managers.mechanism and Managers.mechanism:game_mechanism()
    local deus_run_controller = mechanism and mechanism.get_deus_run_controller and mechanism:get_deus_run_controller()
    if not deus_run_controller then
        _dbg("[defeat-recovery] no deus_run_controller; skipping penalty")
        return
    end
    local run_state = deus_run_controller._run_state
    if not run_state then return end

    local local_peer_id = run_state:get_own_peer_id()
    local local_player_id = 1  -- REAL_PLAYER_LOCAL_ID per deus_run_controller.lua:29

    -- Zero own coins.
    run_state:set_player_soft_currency(local_peer_id, local_player_id, 0)
    _dbg("[defeat-recovery] zeroed own coins")

    -- Pick 5 random boons (or fewer if you have less than 5) and remove them.
    local profile_index, career_index = run_state:get_player_profile(local_peer_id, local_player_id)
    local power_ups = run_state:get_player_power_ups(local_peer_id, local_player_id, profile_index, career_index)
    if power_ups and #power_ups > 0 then
        local indices = {}
        for i = 1, #power_ups do indices[i] = i end
        local to_remove = math.min(5, #indices)
        local removed_names = {}
        for _ = 1, to_remove do
            local pick = math.random(#indices)
            local boon_idx = indices[pick]
            table.remove(indices, pick)
            local boon = power_ups[boon_idx]
            if boon and boon.name then
                removed_names[#removed_names + 1] = boon.name
                deus_run_controller:remove_power_ups(boon.name, local_player_id)
            end
        end
        _dbg(string.format("[defeat-recovery] removed %d boons: %s", #removed_names, table.concat(removed_names, ", ")))
    else
        _dbg("[defeat-recovery] no boons to remove")
    end
end

local function _force_respawn_team()
    if not Managers.state.game_mode then return end
    local game_mode = Managers.state.game_mode:game_mode()
    if game_mode and game_mode.force_respawn_dead_players then
        game_mode:force_respawn_dead_players()
        _dbg("[defeat-recovery] force-respawned dead players")
    end
end

mod:hook("GameModeDeus", "evaluate_end_conditions", function(func, self, ...)
    -- v0.7.64: host-synced. The hook itself only runs on the host (GameModeDeus is
    -- server-authoritative), so this read effectively gets the host's value either
    -- way — but using effective_setting keeps the lookup pattern uniform with the
    -- rest of the codebase and survives any future re-entry from a client context.
    if not effective_setting("tweak_defeat_recovery") then
        return func(self, ...)
    end
    if context.defeat_recovery_triggered() then
        -- Already burned the recovery for this round; normal end-condition resolution.
        return func(self, ...)
    end
    local ended, reason = func(self, ...)
    if ended and reason == "lost" then
        context.defeat_recovery_triggered(true)
        _apply_local_defeat_penalty()
        _force_respawn_team()
        _dbg("[defeat-recovery] intercepted wipe — penalty applied, players respawned, round continues")
        return false  -- Don't propagate the "lost" outcome.
    end
    return ended, reason
end)

return {
    sync_reckless_swings = sync_reckless_swings,
    sync_bomb_cooldown = sync_bomb_cooldown,
    sync_ulric_pack_unlimited_range = sync_ulric_pack_unlimited_range,
    sync_boon_movespeed = sync_boon_movespeed,
    sync_poison_proof_tweak = sync_poison_proof_tweak,
    sync_invis_potion_tweak = sync_invis_potion_tweak,
    sync_moot_milk_alt_tweak = sync_moot_milk_alt_tweak,
    sync_shard_strike = sync_shard_strike,
    sync_anath_raema_permanent = sync_anath_raema_permanent,
    revert_reckless_swings_tweak = revert_reckless_swings_tweak,
    revert_bomb_cooldown_tweak = revert_bomb_cooldown_tweak,
    revert_boon_movespeed_tweak = revert_boon_movespeed_tweak,
    revert_poison_proof_tweak = revert_poison_proof_tweak,
    revert_invis_potion_tweak = revert_invis_potion_tweak,
    revert_moot_milk_alt_tweak = revert_moot_milk_alt_tweak,
    revert_shard_strike_tweak = revert_shard_strike_tweak,
    revert_anath_raema_permanent_tweak = revert_anath_raema_permanent_tweak,
    apply_anath_raema_permanent_tweak = apply_anath_raema_permanent_tweak,
    anath_raema_buff_entries = _anath_raema_buff_entries,
    find_entry_by = _find_entry_by,
    reckless_swings_marker = CT_RECKLESS_SWINGS_NAME_LOOKUP_MARKER,
    anath_raema_retry_marker = CT_ANATH_RAEMA_RETRY_MARKER,
    get_reckless_swings_originals = function()
        return reckless_swings_originals
    end,
    get_anath_raema_originals = function()
        return anath_raema_originals
    end,
}
