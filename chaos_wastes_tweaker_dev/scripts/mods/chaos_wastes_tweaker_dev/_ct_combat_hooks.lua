--[[
_ct_combat_hooks — runtime combat / proc / Chest-of-Trials hooks.

Extracted verbatim from chaos_wastes_tweaker_dev.lua (repo issue #2 file-size
refactor) with NO behaviour change. dofile'd from the main file at the exact
point this block previously executed, so hook-registration order and the
load-time one-shots (mod._ct_ensure_warlord_trial()) keep their original timing.
mod:dofile is not a singleton — the main file calls it EXACTLY once.

Contents (each a self-registering hook, gated on its own toggle or crash-guard):
  * Manann's Tempest        — chain_lightning per-owner 8s cooldown (boon + trait)
  * Mathlann's Storm-Strike — lightning_adjecent_enemies AoE cap (crash guard #129)
  * Corrupted Flesh guard   — mark_of_nurgle_explosion gas-cloud rate cap (#104)
  * Chest of Trials         — enemy-count multiplier (#64), seed uniqueness +
                              force-rotation (#117), Skaven Warlord trial (#324)
  * Parry-proc              — strip cooldown_buff + per-career burn VFX (v0.7.128)
  * Myrmidia's Wildfire     — spread-DoT colour match by source burn status
  * Larger Clip / _max_ammo — GenericAmmoUserExtension._apply_buffs (#34)
  * Block Ranger Veteran    — deny not_consume_grenade on Morgrim's Bomb

Cross-file contract (unchanged by the move):
  * Reads host-synced settings via effective_setting -> mod._ct_effective_setting
    (published by the main file before this module loads).
  * Shares the per-mission GLOBALS _ct_cursed_chest_seq / _ct_cot_block_last with
    the main file's setup_run / _transition_next_node hooks (reset there) and the
    regression-test checks — they stay globals, never converted to locals.
  * Exposes mod._ct_cot_rotate_pick / mod._ct_ensure_warlord_trial (and the two
    warlord-trial marker flags) on `mod` for those same call sites.

NOTE (pre-existing, preserved by the move): the main file's boon-roll hook calls
`pcall(_ct128_strip_parry_cooldowns)` as a bare GLOBAL. _ct128_strip_parry_cooldowns
is (and was) a chunk-local, so that call resolved to nil (a no-op) before extraction
and still does after. The move does not change that; the call site was left untouched.
]]

local mod = get_mod("ct_dev")

-- Behaviour-identical local shims for the two main-file file-locals this block
-- used before extraction. `_dbg` mirrors the main file's mod:debug wrapper; the
-- effective_setting reader delegates to the host-synced function the main file
-- publishes as mod._ct_effective_setting (guaranteed assigned before this loads,
-- so the mod:get fallback never fires — it just mirrors the _ct_mechanic_tweaks
-- _effective helper's shape).
local function _dbg(fmt, ...)
    mod:debug("[ct:dbg] " .. fmt, ...)
end

local effective_setting = function(name)
    local f = mod._ct_effective_setting
    if f then return f(name) end
    return mod:get(name)
end

-- ============================================================
-- Manann's Tempest — single-toggle 8s cooldown for boon + trait
-- ============================================================
-- Vanilla `chain_lightning` has no cooldown: every crit triggers a chain, so high-crit
-- builds turn every fight into a strobe-light spam.
--
-- v0.7.64: ONE toggle (`tweak_manann_tempest_cooldown`, default OFF) gates BOTH the
-- boon and the trait. Previously the boon was hard-capped unconditionally — but the
-- gate at line 4024 only checked `is_trait`, so the boon's 8s window was applied
-- silently even when users wanted vanilla behavior, and "the toggle isn't doing
-- anything" was correct from the user perspective for the boon side. Now: off =
-- vanilla on both sources, on = 8s cooldown on both.
--
-- Cooldowns are tracked per `owner_unit` with separate buckets for boon vs trait, so
-- the two sources don't share a window — a player running both gets one chain per 8s
-- from each side (matches the existing "boon stacks with trait" design described above
-- at the CT_TRAIT_BOONS table). Weak-keyed so entries die with the unit.
--
-- Gate mirrors `chain_lightning`'s own ALIVE / first_hit / is_critical_strike check so
-- the cooldown only consumes when the proc would actually have fired.
--
-- v0.7.57: hook target is the GLOBAL `ProcFunctions` table, NOT
-- `BuffFunctionTemplates.functions`. `chain_lightning` lives in
-- `dlc_settings.morris.proc_functions` (morris_buff_settings.lua:2145+, separate from
-- buff_function_templates which ends at line 2144) and gets merged via
-- `DLCUtils.merge("proc_functions", ProcFunctions)` in buff_templates.lua:9533. At
-- runtime BuffExtension looks it up via `ProcFunctions[buff_func_name]`
-- (buff_extension.lua:1350) — `BuffFunctionTemplates.functions.chain_lightning` is nil
-- and was the source of the load-time "trying to hook function or method that doesn't
-- exist" error in v0.7.48 → v0.7.56. `apply_pockets_full_of_bombs_buff` happens to live
-- in `buff_function_templates` (the apply-callback category) which is why THAT hook
-- worked at the same call site.
if ProcFunctions and ProcFunctions.chain_lightning then
    local MANANN_TEMPEST_COOLDOWN_S = 8.0
    local _manann_tempest_t = setmetatable({}, { __mode = "k" })

    mod:hook(ProcFunctions, "chain_lightning", function(func, owner_unit, buff, params, world, param_order)
        local template = buff and buff.template
        local template_name = template and template.name
        local is_boon  = type(template_name) == "string"
            and string.find(template_name, "^power_up_ct_boon_manann_tempest_") ~= nil
        local is_trait = template_name == "deus_crit_chain_lightning"

        if not (is_boon or is_trait) then
            return func(owner_unit, buff, params, world, param_order)
        end
        if not effective_setting("tweak_manann_tempest_cooldown") then
            return func(owner_unit, buff, params, world, param_order)
        end

        local hit_unit = params[param_order.attacked_unit]
        local first_hit = params[param_order.first_hit]
        local is_critical_strike = params[param_order.is_critical_strike]
        if not (ALIVE[owner_unit] and ALIVE[hit_unit] and first_hit and is_critical_strike) then
            return func(owner_unit, buff, params, world, param_order)
        end

        local t = (Managers and Managers.time and Managers.time:time("game")) or 0
        local bucket = _manann_tempest_t[owner_unit]
        if not bucket then
            bucket = { boon_next_t = 0, trait_next_t = 0 }
            _manann_tempest_t[owner_unit] = bucket
        end
        local key = is_boon and "boon_next_t" or "trait_next_t"
        if t < bucket[key] then
            return
        end
        bucket[key] = t + MANANN_TEMPEST_COOLDOWN_S
        return func(owner_unit, buff, params, world, param_order)
    end)
end

-- ============================================================
-- v0.7.171-dev — Mathlann's Storm-Strike AoE cap (IMPLICIT crash guard, Issue #129)
-- ============================================================
-- DISTINCT from Manann's Tempest above (chain_lightning, capped 5). This is the VANILLA
-- boon `boon_careerskill_01` ("Mathlann's Storm-Strike" — "Your Career Skill also calls
-- down lightning on nearby enemies"), buff_func `lightning_adjecent_enemies`
-- (morris_buff_settings.lua:3744). On ult it broadphase-queries EVERY enemy in
-- template.area_radius and, per enemy, does add_damage_network + a `static_blade`
-- create_explosion + a beam fx. With a large horde (enemy_tweaker huge_shields blob,
-- n=121 in the 2026-06-25 crash) the per-enemy + cascading-explosion RPCs flood the HOST
-- reliable send queue (rpc_add_damage x2239 + rpc_add_buff x1007 -> overflow 98152) ->
-- the client gets `broken connection: authentication_denied` and the host crashes.
--
-- IMPLICIT (no toggle — a host crash must not be leave-on-able). The proc is `is_local`
-- (runs on the boon OWNER), so EVERY peer needs this build for the cap to take on the
-- peer holding the boon; an un-updated client still floods the host.
--
-- FIX: cap how many enemies the proc's MAIN broadphase sweep returns. We do NOT
-- re-implement the network-heavy damage loop; for the duration of the proc call we swap
-- `AiUtils.broadphase_query` for a wrapper that clamps ONLY the first query (the main
-- sweep — the per-enemy explosions' own queries pass through untouched) to the cap, then
-- restore it. No permanent hook on the hot broadphase fn. Defensive: pcall-guarded with a
-- guaranteed restore, and `printf` (survives mod-logging-off) on cap-engage + any error.
do
    local MATHLANN_STORMSTRIKE_CAP = 40
    local _AiUtils = rawget(_G, "AiUtils")
    if ProcFunctions and ProcFunctions.lightning_adjecent_enemies and _AiUtils and _AiUtils.broadphase_query then
        local _ms_printf = rawget(_G, "printf") or function() end
        mod:hook(ProcFunctions, "lightning_adjecent_enemies", function(func, ...)
            local orig_bq = _AiUtils.broadphase_query
            local first   = true
            _AiUtils.broadphase_query = function(...)
                local n = orig_bq(...)
                if first then
                    first = false
                    if type(n) == "number" and n > MATHLANN_STORMSTRIKE_CAP then
                        _ms_printf("[ct:mathlann_guard] Storm-Strike (boon_careerskill_01): capped %d nearby enemies -> %d (reliable-send-queue flood guard, issue #129)",
                            n, MATHLANN_STORMSTRIKE_CAP)
                        return MATHLANN_STORMSTRIKE_CAP
                    end
                end
                return n
            end
            local ok, err = pcall(func, ...)
            _AiUtils.broadphase_query = orig_bq   -- ALWAYS restore, even on error
            if not ok then
                _ms_printf("[ct:mathlann_guard] lightning_adjecent_enemies errored (broadphase restored): %s", tostring(err))
            end
        end)
        _ms_printf("[ct:mathlann_guard] Mathlann's Storm-Strike AoE cap installed (max %d targets/cast, issue #129).", MATHLANN_STORMSTRIKE_CAP)
    end
end

-- ============================================================
-- v0.7.200-dev — Corrupted Flesh gas-cloud rate guard (Issue #104)
-- ============================================================
-- The CW curse `curse_corrupted_flesh` (mutator_curse_corrupted_flesh.lua) marks up to
-- 3 concurrent enemies (30% chance); each marked enemy's death runs the
-- `mark_of_nurgle_death_explosion` buff, whose proc `mark_of_nurgle_explosion`
-- (morris_buff_settings.lua:2254-2299) spawns a FULL globadier-class gas cloud:
-- globadier_area_dot_damage AoE + poison-wind fx + nav-tag volume + an
-- rpc_area_damage broadcast to every peer. 2026-07-01 forensics
-- (dlc_bastion_nurgle_path1, both logs): ~117 networked `aoe_unit` creations in
-- 21.5 min (2.7/min steady, peak 11/min at the finale) against cataclysm/et-multiplied
-- density — sustained render/CPU load that degraded FPS on BOTH machines (same hazard
-- family as the #129 Mathlann guard, but below the network-crash threshold).
--
-- CHOKE POINT: `ProcFunctions.mark_of_nurgle_explosion` — the exact function that
-- spawns the cloud. It lives in dlc_settings.proc_functions (morris_buff_settings.lua
-- :2145+), merged into the flat global `ProcFunctions` at boot and resolved BY STRING
-- at proc time (buff_extension.lua:1350) — so a table-form hook takes effect with no
-- upvalue-capture risk (same mechanism as the Manann/Mathlann hooks above).
-- HOST-AUTHORITATIVE: the buff sits on AI units (host-side) and the body calls
-- server-only Managers.state.unit_spawner:spawn_network_unit; clients pass through
-- untouched. Suppression = returning WITHOUT calling func: no cloud unit, no nav-tag
-- volume, no rpc_area_damage — the mark's other on_death buffs (dot/pingable) run
-- normally, so nothing is left inconsistent (guard-vs-bail audited).
--
-- CAP SEMANTICS: rolling 60s window, host-side. `flesh_guard_clouds_per_minute`
-- (numeric 0-30, DEFAULT 6): 0 = vanilla/uncapped; 6/min ~ halves the observed peak
-- (11/min) while leaving the 2.7/min steady rate untouched. Host-synced automatically
-- (every non-per-peer widget joins SYNCED_SETTING_NAMES via _collect_setting_ids),
-- though only the host ever evaluates the gate — the sync just keeps /ct_diag +
-- settings-fingerprint views consistent across peers.
do
    local FLESH_GUARD_WINDOW_S = 60
    local _fg_printf = rawget(_G, "printf") or function() end
    local _fg_times = {}            -- spawn timestamps within the rolling window
    local _fg_suppressed_burst = 0  -- suppressions since the last allowed spawn
    local _fg_last_log_t = -1e9     -- rate-limits the suppression printf (1 per 5s)
    if ProcFunctions and ProcFunctions.mark_of_nurgle_explosion then
        -- Trailing `...` forwards world/param_order (proc callers pass up to 5 args even
        -- though this proc's vanilla body only names 3) — never drop vanilla's trailing
        -- params in a hook (reference_vmf_hook_drops_skip_sync_rpc_loop).
        mod:hook(ProcFunctions, "mark_of_nurgle_explosion", function(func, owner_unit, buff, params, ...)
            local is_server = Managers and Managers.player and Managers.player.is_server
            if not is_server then
                return func(owner_unit, buff, params, ...)
            end

            -- #104 (3b) AoE attribution: one cheap line per cloud (observed max 11/min)
            -- so future FPS forensics pin hazard spam in a single grep. Scoped to this
            -- deus curse mechanism only — ordinary combat explosions never route here.
            local src = "?"
            pcall(function()
                local killed = params and params[1]
                local breed = killed and Unit.alive(killed) and Unit.get_data(killed, "breed")
                src = breed and breed.name or "?"
            end)

            local cap = effective_setting("flesh_guard_clouds_per_minute")
            if type(cap) ~= "number" or cap <= 0 then
                _fg_printf("[ct:aoe] template=corrupted_flesh_explosion buff=mark_of_nurgle_death_explosion source=%s cap=off (issue #104)",
                    tostring(src))
                return func(owner_unit, buff, params, ...)  -- 0 / unset = vanilla, uncapped
            end

            local t = (Managers and Managers.time and Managers.time:time("game")) or 0
            -- Prune entries older than the window (in-place compact keeps order).
            local w = 1
            for r = 1, #_fg_times do
                if t - _fg_times[r] <= FLESH_GUARD_WINDOW_S then
                    _fg_times[w] = _fg_times[r]
                    w = w + 1
                end
            end
            for r = #_fg_times, w, -1 do _fg_times[r] = nil end

            if #_fg_times >= cap then
                _fg_suppressed_burst = _fg_suppressed_burst + 1
                if t - _fg_last_log_t >= 5 then
                    _fg_last_log_t = t
                    _fg_printf("[ct:flesh_guard] suppressed gas cloud (%d this window, cap=%d/min, issue #104)",
                        _fg_suppressed_burst, cap)
                end
                return  -- suppress: no cloud, no nav volume, no RPC broadcast
            end

            _fg_suppressed_burst = 0
            _fg_times[#_fg_times + 1] = t
            _fg_printf("[ct:aoe] template=corrupted_flesh_explosion buff=mark_of_nurgle_death_explosion source=%s window_n=%d cap=%d (issue #104)",
                tostring(src), #_fg_times, cap)
            return func(owner_unit, buff, params, ...)
        end)
        _fg_printf("[ct:flesh_guard] corrupted-flesh gas-cloud rate guard installed (window=%ds, issue #104)", FLESH_GUARD_WINDOW_S)
    else
        _fg_printf("[ct:flesh_guard] ProcFunctions.mark_of_nurgle_explosion not found at load — #104 guard INACTIVE")
    end
end

-- ============================================================
-- v0.7.130-dev — Chest of Trials enemy spawn-count multiplier (Issue #64)
-- ============================================================
-- Wraps `TerrorEventMixer.init_functions.spawn_around_origin_unit` (vanilla
-- terror_event_mixer.lua:96). Each `cursed_chest_prototype` terror event
-- (deus_generic_terror_events.lua:50+) is a sequence of `spawn_around_origin_unit`
-- elements tagged with `spawn_counter_category = "cursed_chest_enemies"`. That
-- tag is the filter — every cursed-chest spawn carries it; nothing else does.
--
-- Mechanism:
--   1. Read `effective_setting("cot_enemy_multiplier")`. Bail if missing / <=1.
--   2. Bail if element isn't cursed-chest (different filter shape, different mod scope).
--   3. Scale `element.difficulty_amount` (table of per-difficulty counts) and
--      `element.amount` (scalar fallback) by `mult`, save originals.
--   4. Call vanilla. Vanilla rebuilds `spawn_table` from the scaled values
--      (the local `breed_spawn_table_per_difficulty` is NEVER written back to
--      element — vanilla rebuilds every call — so our scale stays applied just
--      for this call without persisting across runs).
--   5. Restore originals so we don't mutate the shared template.
if rawget(_G, "TerrorEventMixer") and TerrorEventMixer.init_functions
        and TerrorEventMixer.init_functions.spawn_around_origin_unit then
    mod:hook(TerrorEventMixer.init_functions, "spawn_around_origin_unit",
        function(func, event, element, t)
            if not (element and element.spawn_counter_category == "cursed_chest_enemies") then
                return func(event, element, t)
            end
            local mult = effective_setting("cot_enemy_multiplier")
            if type(mult) ~= "number" or mult <= 1 then
                return func(event, element, t)
            end
            -- Save + scale. element is the SHARED template; we MUST restore before
            -- returning so subsequent events see vanilla values.
            local saved_amount = element.amount
            if type(saved_amount) == "number" then
                element.amount = math.max(1, math.floor(saved_amount * mult))
            end
            local saved_difficulty_amount = element.difficulty_amount
            if type(saved_difficulty_amount) == "table" then
                local scaled = {}
                for k, v in pairs(saved_difficulty_amount) do
                    scaled[k] = (type(v) == "number") and math.max(1, math.floor(v * mult)) or v
                end
                element.difficulty_amount = scaled
            end

            local ok, err = pcall(func, event, element, t)

            element.amount = saved_amount
            element.difficulty_amount = saved_difficulty_amount
            if not ok then error(err) end
            _dbg("[cot_enemy_mult] event=%s breed=%s scaled by %.1f (saved orig)",
                tostring(event and event.event_name or "?"),
                tostring(element.breed_name), mult)
        end)
end

-- ============================================================
-- v0.7.157-dev Task B — Chest of Trials uniqueness (Issue: same trial repeats)
-- ============================================================
-- USER REPORT: multiple Chests of Trials in one mission spawn the SAME enemies.
--
-- ROOT CAUSE (verified from decompiled source):
--   * A Chest of Trials is DeusCursedChestExtension. On activation (server, state
--     -> RUNNING) it calls
--       Managers.state.conflict:start_terror_event("cursed_chest_prototype",
--           Managers.mechanism:get_level_seed(), unit)
--     (deus_cursed_chest_extension.lua:105-109). EVERY cursed chest in the level
--     passes the SAME level seed.
--   * `cursed_chest_prototype` (deus_generic_terror_events.lua:50) is a master
--     event whose `inject_event` blocks each pick ONE faction challenge from an
--     `event_name_list` via
--       Math.next_random(data.seed, 1, #event_name_list)
--     (terror_event_mixer.lua:1667). `data.seed` is the seed we passed through
--     ConflictDirector.start_terror_event -> add_to_start_event_list (seed stored
--     verbatim, terror_event_mixer.lua:1572-1580).
--   * Same starting seed -> same random walk -> same challenge indices -> the
--     SAME trial every chest. That's the bug.
--
-- FIX: hook ConflictDirector.start_terror_event (HOST-AUTHORITATIVE — cursed
-- chest activation + terror events are server-side; clients never call this for
-- cursed chests). When the event is `cursed_chest_prototype`, mix a per-mission
-- activation counter into the seed so each subsequent chest's inject_event walk
-- diverges and selects a DIFFERENT challenge. Counter index 0 keeps the FIRST
-- chest on vanilla behaviour (no offset); only chests 2..N are perturbed.
--
-- The counter resets per mission via the existing DeusMechanism._transition_next_node
-- hook (search `_ct_cursed_chest_seq = 0` there) and at run start (setup_run).
-- Respects cot_enemy_multiplier: this only changes the SEED used to PICK the
-- challenge, not the spawn-count scaling (a separate spawn_around_origin_unit
-- hook), so the two features compose cleanly.
--
-- ALWAYS-ON as of v0.7.177-dev (#117): the `cursed_chest_unique_trials` toggle was
-- removed; this seed-perturbation layer now runs unconditionally on the host, paired
-- with the TerrorEventMixer.start_event force-rotation layer below.
_ct_cursed_chest_seq = _ct_cursed_chest_seq or 0  -- per-mission cursed-chest activation counter (host)
_ct_cot_block_last = _ct_cot_block_last or {}     -- per-mission: cursed_chest_prototype block_index -> last forced event_name (host)

if rawget(_G, "ConflictDirector") then
    mod:hook("ConflictDirector", "start_terror_event", function(func, self, event_name, optional_seed, origin_unit, origin_position)
        -- Only perturb the cursed-chest master event; everything else passes through.
        if event_name ~= "cursed_chest_prototype" then
            return func(self, event_name, optional_seed, origin_unit, origin_position)
        end

        -- #324 (v0.7.226-dev): (re)attempt the Skaven Warlord trial injection at
        -- chest-activation time. Mod load order between ct_dev and enemy_tweaker
        -- is not guaranteed, so the load-time attempt may have run before et
        -- registered the et_skaven_warlord breed; this call is idempotent
        -- (marker early-out) and et-absence-guarded. Merged into THIS existing
        -- hook body (single hook per Class.method - VMF drops duplicates);
        -- definition lives in the "#324 Chest of Trials: Skaven Warlord trial"
        -- block below. Runs synchronously BEFORE the prototype's inject_event
        -- chains are resolved (TerrorEventMixer.start_event happens later in
        -- the deferred start_event_list processing), so an injection completed
        -- here is visible to this very chest's trial pick.
        if type(mod._ct_ensure_warlord_trial) == "function" then
            mod._ct_ensure_warlord_trial()
        end

        -- [ct-probe] v0.7.157-dev unconditional Chest-of-Trials activation probe.
        -- Placed BEFORE the toggle gate so it fires on EVERY cursed-chest activation,
        -- toggle ON or OFF. The mod selects the trial INDIRECTLY through the seed
        -- (vanilla terror_event_mixer Math.next_random(data.seed,...) picks the
        -- faction challenge downstream — there is no in-mod "trial id"). The seed IS
        -- the trial handle: same seed => same trial. With the feature OFF, vanilla
        -- passes the SAME optional_seed to every chest (the repeat-bug signature:
        -- identical seeds); with it ON the seq>0 chests get a perturbed seed below
        -- (so a later [ct-probe] cot_seed_applied line carries the divergent seed).
        -- Grep [ct-probe] next session: identical seeds = same trial, distinct =
        -- varied. Raw printf bypasses the VMF mod-logging toggle (lands on a
        -- logging-OFF host — the gap that produced zero lines on Rain's). seq is the
        -- counter as it stands BEFORE this activation increments it.
        local probe_seq = _ct_cursed_chest_seq or 0
        pcall(function()
            printf("[ct-probe] cot_activation seq=%d base_seed=%s (always-on #117)",
                probe_seq, tostring(optional_seed or 0))
        end)

        local seq = _ct_cursed_chest_seq or 0
        _ct_cursed_chest_seq = seq + 1

        -- First chest (seq 0): leave the seed untouched -> identical to vanilla.
        -- Subsequent chests: derive a fresh seed by mixing the activation index so
        -- the inject_event Math.next_random walk lands on different indices.
        local base_seed = optional_seed or 0
        local new_seed = base_seed
        if seq > 0 then
            if HashUtils and HashUtils.fnv32_hash then
                new_seed = HashUtils.fnv32_hash(tostring(base_seed) .. "_ct_trial_" .. seq)
            else
                -- FNV-prime fallback mix (kept positive / 32-bit-ish)
                new_seed = (base_seed + seq * 2654435761) % 4294967296
            end
        end

        _dbg("[cot_unique] cursed_chest_prototype activation #%d: base_seed=%s -> seed=%s (host)",
            seq, tostring(base_seed), tostring(new_seed))

        -- [ct-probe] v0.7.157-dev: the APPLIED (derived) trial seed for this
        -- activation when the uniqueness feature is ON. seq==0 keeps base_seed
        -- (vanilla first chest); seq>0 carries the perturbed seed => a different
        -- trial. Pair with the cot_activation line above (same seq) to read the
        -- before/after seed per chest. Raw printf — lands on a logging-OFF host.
        pcall(function()
            printf("[ct-probe] cot_seed_applied seq=%d trial_seed=%s base_seed=%s",
                seq, tostring(new_seed), tostring(base_seed))
        end)

        return func(self, event_name, new_seed, origin_unit, origin_position)
    end)
end

-- ============================================================
-- #117 (v0.7.177-dev) — GUARANTEED unique Chest-of-Trials picks (force-rotation)
-- ============================================================
-- The seed-perturbation above varies the random walk, but does not GUARANTEE that
-- two chests land on different top-level trials (different seeds can still collide
-- on the same faction-challenge pick). This layer makes it deterministic: it wraps
-- TerrorEventMixer.start_event (the synchronous point where cursed_chest_prototype
-- is actually processed — terror_event_mixer.lua:1757, called from the deferred
-- start_event_list loop) and, for the cursed_chest_prototype event, force-rotates
-- each `inject_event` block's `event_name_list` to a SINGLE entry that differs from
-- that block's previous pick this mission. The vanilla pick `Math.next_random(seed,
-- 1, #list)` then has exactly one option, so the chosen top-level faction challenge
-- is the one we forced. Sub-challenges downstream still vary via the (perturbed)
-- seed, so the two layers compose. The shared GenericTerrorEvents template is mutated
-- only across the vanilla call and restored immediately after (save/restore, pcall-
-- guarded), so no global state leaks. Host-only (terror-event processing is server-
-- side); guarded on is_server for safety.
--
-- `_ct_cot_block_last[block_index]` tracks the last forced event_name per block; it
-- resets per mission alongside `_ct_cursed_chest_seq` (search `_ct_cot_block_last = {}`).
-- Stored on `mod` (not a main-chunk local) to respect Lua's 200-locals-per-chunk cap.
mod._ct_cot_rotate_pick = function(list, last)
    -- distinct event names in stable order
    local seen, distinct = {}, {}
    for _, name in ipairs(list) do
        if not seen[name] then
            seen[name] = true
            distinct[#distinct + 1] = name
        end
    end
    if #distinct <= 1 then
        return distinct[1] or list[1]
    end
    -- return the distinct option AFTER `last` (wrap) so we never repeat last's pick
    local last_idx
    for i, name in ipairs(distinct) do
        if name == last then last_idx = i break end
    end
    if not last_idx then return distinct[1] end
    return distinct[(last_idx % #distinct) + 1]
end

if rawget(_G, "TerrorEventMixer") then
    mod:hook("TerrorEventMixer", "start_event", function(func, event_name, data, id)
        local is_server = Managers and Managers.player and Managers.player.is_server
        local proto = rawget(_G, "GenericTerrorEvents") and GenericTerrorEvents.cursed_chest_prototype
        if event_name ~= "cursed_chest_prototype" or not is_server or type(proto) ~= "table" then
            return func(event_name, data, id)
        end

        local saved = {}
        for i, block in ipairs(proto) do
            if type(block) == "table" and block[1] == "inject_event"
                    and type(block.event_name_list) == "table" then
                local pick = mod._ct_cot_rotate_pick(block.event_name_list, _ct_cot_block_last[i])
                if pick then
                    saved[i] = block.event_name_list
                    block.event_name_list = { pick }
                    _ct_cot_block_last[i] = pick
                end
            end
        end

        pcall(function()
            local parts = {}
            for i, p in pairs(_ct_cot_block_last) do parts[#parts + 1] = tostring(i) .. ":" .. tostring(p) end
            printf("[ct-cot-unique] forced cursed_chest_prototype trial picks -> %s", table.concat(parts, " "))
        end)

        local ok, err = pcall(func, event_name, data, id)

        -- restore the shared template no matter what (selection already captured)
        for i, orig in pairs(saved) do
            proto[i].event_name_list = orig
        end
        if not ok then error(err) end
    end)
end

-- ============================================================
-- #324 (v0.7.226-dev) - Chest of Trials: Skaven Warlord trial (cross-mod with enemy_tweaker)
-- ============================================================
-- Adds ONE new cursed-chest trial terror event that spawns enemy_tweaker's
-- mod-added `et_skaven_warlord` boss breed (the unused champion-recolour of
-- Skarrik's model; registered by et's _et_skaven_warlord_breed.lua) plus a
-- clan-rat retinue, and injects it as a RARE pick into the skaven
-- cursed-chest pools. Folded into the always-on unique-trials behaviour
-- (#117 precedent: the cursed_chest_unique_trials toggle was removed) - no
-- new menu toggle; the feature is inert unless enemy_tweaker is installed.
--
-- TEMPLATE: mirrors GenericTerrorEvents.cursed_chest_challenge_skaven_rat_ogre
-- (deus_generic_terror_events.lua:1374-1445 - the closest boss-type trial:
-- one boss element with grudge-enhancement pre_spawn_func + one clan-rat adds
-- element + the continue_when_spawned_count completion pair), with vanilla's
-- distance/delay constants inlined from :92-107.
--
-- UPVALUE GOTCHA (CODE_REVIEW.md v0.7.89 burn): vanilla terror-event files
-- capture `TerrorEventUtils.add_enhancements_for_difficulty` as a file-scope
-- upvalue at boot (deus_generic_terror_events.lua:15), so HOOKING the util
-- never reaches vanilla events. Irrelevant for OUR event: we resolve the
-- CURRENT `TerrorEventUtils.add_enhancements_for_difficulty` reference at OUR
-- definition time (mod load / injection time), exactly the way vanilla's own
-- file resolves it at boot. That function defaults its enhancement set to
-- _G.BossGrudgeMarks at CALL time (terror_event_utils.lua:197), so ct's Boss
-- Grudge Marks banlist (sync_grudge_marks above) and the apply-chokepoint
-- filter both keep working on this trial - and the grudge NAMES rendered by
-- BossHealthUI come from GrudgeMarkedNames[et_skaven_warlord] (registered by
-- et; consumer terror_event_utils.lua:59-78).
--
-- The vanilla trial's helper funcs are FILE LOCALS we cannot reference
-- (cursed_chest_enemy_spawned_func :17-41, decal funcs :109-151), so we carry
-- verbatim ports below. The spawned_func port keeps the
-- `cursed_chest_objective_unit` buff wiring - that buff plus the
-- `cursed_chest_enemies` spawn counter is what completes the trial: the chest
-- flips to OPEN when the whole cursed_chest_prototype event finishes
-- (deus_cursed_chest_extension.lua:173 `not TerrorEventMixer.find_event(...)`),
-- and the event's final element waits for `counter.cursed_chest_enemies <= 0`.
-- NetworkedFlowStateManager note (ct DEVELOPMENT.md "state-count leak"): each
-- objective-unit buff leaks one flow-state slot in VANILLA; ct's shipped
-- clear_object_state patch (v0.7.3-alpha) already reclaims them, so this
-- trial adds no NEW leak pressure beyond any other trial.
--
-- DELIBERATE DEVIATION from the template: NO start_mission/end_mission
-- elements. (a) A NEW mission name would need Missions + a
-- NetworkLookup.mission_names entry on EVERY peer (request_mission does a
-- strict-metatable lookup at mission_system.lua:135; the id is RPC'd to
-- clients, so an unmodded client would hard-error). (b) REUSING a vanilla
-- trial's mission name risks a hard fassert: end_mission asserts the mission
-- is active (mission_system.lua:227), and two simultaneous chests sharing a
-- name would end it twice. The mission elements are objective-HUD only -
-- chest completion does not read them (deus_cursed_chest_extension.lua:173),
-- so dropping them costs a banner, not function.
--
-- ET-ABSENCE GUARD: injection only happens once `rawget(_G, "Breeds")` has
-- `et_skaven_warlord`. Load order between ct_dev and enemy_tweaker is not
-- guaranteed, so injection is retried (idempotently) from the existing
-- ConflictDirector.start_terror_event hook at chest activation (merged there
-- - see the #324 line in that hook body; NO new hook on that method, VMF
-- drops duplicates). If et is absent the skip is noted with a single printf
-- and nothing else happens.
--
-- Cross-mod ref note: the guard keys off the BREED (rawget(_G,"Breeds")),
-- not get_mod("enemy_tweaker") - et registers the breed at module load even
-- when VMF-disabled (et DEVELOPMENT.md eager doctrine), and the breed table
-- is what spawning actually needs.
mod._ct_warlord_trial_injected = false
mod._ct_warlord_trial_noted_absent = false

-- Idempotent define + inject. Returns true once injected. Safe to call from
-- module load AND from the start_terror_event hook every chest activation
-- (marker early-out).
-- 200-LOCAL NOTE: ALL of this feature's state (constants + the three
-- vanilla-func ports) lives INSIDE this function on purpose - the ct main
-- chunk sits at the Lua 5.1 200-active-locals ceiling (the first #324 build
-- failed with "main function has more than 200 local variables" even from a
-- do-block, whose locals still occupy chunk register slots while live), and
-- function-scope locals get their own 200 budget. The helper closures are
-- built at most once per session: the injected marker early-outs every later
-- call before anything is constructed.
mod._ct_ensure_warlord_trial = function()
    if mod._ct_warlord_trial_injected then
        return true
    end
    local GTE = rawget(_G, "GenericTerrorEvents")
    local TEU = rawget(_G, "TerrorEventUtils")
    if type(GTE) ~= "table" or type(TEU) ~= "table"
            or type(TEU.add_enhancements_for_difficulty) ~= "function" then
        return false
    end

    local WARLORD_BREED    = "et_skaven_warlord"
    local TRIAL_EVENT_NAME = "ct_cursed_chest_challenge_skaven_warlord"
    -- Existing skaven trial picks all carry weight = 3
    -- (deus_generic_terror_events.lua:170-277); weight 1 makes ours a
    -- rare-ish special trial (1-in-10 of the MORE_MONSTERS block, 1-in-28 of
    -- the untagged fallback block).
    local TRIAL_WEIGHT     = 1

    local B = rawget(_G, "Breeds")
    if not (B and type(B[WARLORD_BREED]) == "table") then
        -- enemy_tweaker not installed (or its breed registration failed):
        -- skip quietly, note ONCE per session.
        if not mod._ct_warlord_trial_noted_absent then
            mod._ct_warlord_trial_noted_absent = true
            pcall(printf, "[ct-warlord-trial] breed %s absent (enemy_tweaker not installed?) - Skaven Warlord trial NOT injected (#324)", WARLORD_BREED)
        end
        return false
    end

    -- Vanilla constants, inlined (deus_generic_terror_events.lua:92-107).
    local DELAY_WAVE_1    = 2
    local DELAY_SPAWN     = 4
    local DIST_SHORT      = 8
    local DIST_LONG       = 20
    local SPREAD_MED      = 7
    local DECAL_RADIUS_MAP = { boss = 2, default = 1, elite = 1.2, special = 1.2 }
    local SPAWN_DECAL_UNIT_NAME = "units/decals/deus_decal_aoe_cursedchest_01"

    -- Port of cursed_chest_enemy_spawned_func (deus_generic_terror_events.lua:17-41).
    -- Kept structurally identical to vanilla (no pcall wrapper) so the trial's
    -- risk profile matches every vanilla trial. Our boss skips the aggro
    -- branch exactly like the vanilla rat ogre (breed.boss gate).
    local function _warlord_trial_spawned_func(unit, breed, optional_data)
        if not breed.special and not breed.boss and not breed.cannot_be_aggroed then
            local player_unit = PlayerUtils.get_random_alive_hero()
            AiUtils.aggro_unit_of_enemy(unit, player_unit)
        end

        local buff_system = Managers.state.entity:system("buff_system")
        buff_system:add_buff(unit, "cursed_chest_objective_unit", unit)

        local blackboard = BLACKBOARDS[unit]
        if blackboard then
            local sound_event = "Play_normal_spawn_stinger"
            if breed.special or breed.boss then
                sound_event = "Play_special_spawn_stinger"
            end
            local audio_system = Managers.state.entity:system("audio_system")
            audio_system:play_audio_unit_event(sound_event, unit)
        end
    end

    -- Port of cursed_chest_enemy_spawn_decal_func (deus_generic_terror_events.lua:109-136).
    local function _warlord_trial_spawn_decal_func(event, element, boxed_spawn_pos, breed_name)
        local decal_map = event.decal_map or {}
        event.decal_map = decal_map

        local breed = Breeds[breed_name]
        local spawn_radius
        if breed.boss then
            spawn_radius = DECAL_RADIUS_MAP.boss
        elseif breed.special then
            spawn_radius = DECAL_RADIUS_MAP.special
        elseif breed.elite then
            spawn_radius = DECAL_RADIUS_MAP.elite
        else
            spawn_radius = DECAL_RADIUS_MAP.default
        end

        local spawn_pos = boxed_spawn_pos:unbox()
        local decal_spawn_pose = Matrix4x4.from_quaternion_position(Quaternion.identity(), spawn_pos)
        Matrix4x4.set_scale(decal_spawn_pose, Vector3(spawn_radius, spawn_radius, spawn_radius))

        local decal_unit = Managers.state.unit_spawner:spawn_network_unit(SPAWN_DECAL_UNIT_NAME, "network_synched_dummy_unit", nil, decal_spawn_pose)
        decal_map[boxed_spawn_pos] = decal_unit
    end

    -- Port of cursed_chest_enemy_despawn_decal_func (deus_generic_terror_events.lua:138-151).
    local function _warlord_trial_despawn_decal_func(event, element, boxed_spawn_pos)
        local decal_map = event.decal_map
        local unit = decal_map and decal_map[boxed_spawn_pos]
        if unit then
            Unit.flow_event(unit, "despawned")
            local unit_go_id = Managers.state.unit_storage:go_id(unit)
            Managers.state.network.network_transmit:send_rpc_clients("rpc_flow_event", unit_go_id, NetworkLookup.flow_events.despawned)
            decal_map[boxed_spawn_pos] = nil
        end
    end

    -- 1. Define the trial event. GenericTerrorEvents is resolved by NAME
    -- at event-processing time (terror_event_mixer.lua:1723
    -- `TerrorEventBlueprints[level_key][event_name] or
    -- GenericTerrorEvents[event_name]`), so a mod-load/late definition is
    -- fully visible - no boot snapshot to miss.
    if not GTE[TRIAL_EVENT_NAME] then
        GTE[TRIAL_EVENT_NAME] = {
            {
                "delay",
                duration = DELAY_WAVE_1,
            },
            {
                "play_stinger",
                stinger_name = "Play_wave_start_spawn_stinger",
            },
            {
                -- The boss element (mirrors deus_generic_terror_events.lua:1387-1401,
                -- breed swapped). pre_spawn_func applies grudge enhancements per
                -- difficulty exactly like vanilla boss trials: the mixer calls
                -- element.pre_spawn_func(optional_data, difficulty, breed_name,
                -- event, difficulty_tweak, element.enhancement_list)
                -- (terror_event_mixer.lua:148-149), which is
                -- add_enhancements_for_difficulty's exact signature
                -- (terror_event_utils.lua:191).
                "spawn_around_origin_unit",
                breed_name = WARLORD_BREED,
                spawn_counter_category = "cursed_chest_enemies",
                optional_data = {
                    prevent_killed_enemy_dialogue = true,
                    spawned_func = _warlord_trial_spawned_func,
                },
                min_distance = DIST_LONG - SPREAD_MED * 0.5,
                max_distance = DIST_LONG + SPREAD_MED * 0.5,
                pre_spawn_unit_func = _warlord_trial_spawn_decal_func,
                post_spawn_unit_func = _warlord_trial_despawn_decal_func,
                spawn_delay = DELAY_SPAWN,
                pre_spawn_func = TEU.add_enhancements_for_difficulty,
            },
            {
                -- Clan-rat retinue (mirrors deus_generic_terror_events.lua:1402-1422
                -- verbatim - same breed, same per-difficulty counts).
                "spawn_around_origin_unit",
                breed_name = "skaven_clan_rat",
                spawn_counter_category = "cursed_chest_enemies",
                difficulty_amount = {
                    cataclysm = 18,
                    hard = 12,
                    harder = 14,
                    hardest = 16,
                    normal = 10,
                },
                optional_data = {
                    prevent_killed_enemy_dialogue = true,
                    spawned_func = _warlord_trial_spawned_func,
                },
                min_distance = DIST_SHORT - SPREAD_MED * 0.5,
                max_distance = DIST_SHORT + SPREAD_MED * 0.5,
                pre_spawn_unit_func = _warlord_trial_spawn_decal_func,
                post_spawn_unit_func = _warlord_trial_despawn_decal_func,
                spawn_delay = DELAY_SPAWN,
            },
            {
                "delay",
                duration = 1,
            },
            {
                "continue_when_spawned_count",
                duration = 20,
                condition = function (counter)
                    return counter.cursed_chest_enemies > 0
                end,
            },
            {
                "continue_when_spawned_count",
                duration = 120,
                condition = function (counter)
                    return counter.cursed_chest_enemies <= 0
                end,
            },
        }
    end

    -- 2. Inject the weighted pick into the skaven faction pools. The
    -- faction event's shape is { { "one_of", { <inject blocks> } } }
    -- (deus_generic_terror_events.lua:170-277; consumed at
    -- terror_event_mixer.lua:1702-1709 element[1]=="one_of" ->
    -- ipairs(element[2])). We add to every block whose
    -- weighted_event_names already contains the rat-ogre trial - that is
    -- exactly the MORE_MONSTERS-tagged block (:214-233) and the untagged
    -- fallback block (:234-274), and never the elites/specials blocks.
    -- This is a PERMANENT (session-lifetime) template addition, guarded
    -- idempotent; the #117 force-rotation layer above operates on the
    -- PROTOTYPE's event_name_list, not these weighted lists, so the two
    -- compose without interference.
    local injected = false
    local faction_event = GTE.cursed_chest_challenge_faction_skaven
    local one_of = type(faction_event) == "table" and faction_event[1]
    local blocks = type(one_of) == "table" and one_of[1] == "one_of" and one_of[2]
    if type(blocks) == "table" then
        for _, block in ipairs(blocks) do
            local wen = type(block) == "table" and block[1] == "inject_event"
                and block.weighted_event_names
            if type(wen) == "table" then
                local is_monster_pool, already_present = false, false
                for _, entry in ipairs(wen) do
                    if entry.event_name == "cursed_chest_challenge_skaven_rat_ogre" then
                        is_monster_pool = true
                    end
                    if entry.event_name == TRIAL_EVENT_NAME then
                        already_present = true
                    end
                end
                if is_monster_pool and not already_present then
                    wen[#wen + 1] = {
                        event_name = TRIAL_EVENT_NAME,
                        weight = TRIAL_WEIGHT,
                    }
                    injected = true
                end
            end
        end
    end

    if injected then
        mod._ct_warlord_trial_injected = true
        pcall(printf, "[ct-warlord-trial] Skaven Warlord trial %s injected into cursed_chest_challenge_faction_skaven pools (weight=%d) (#324)",
            TRIAL_EVENT_NAME, TRIAL_WEIGHT)
        return true
    end
    pcall(printf, "[ct-warlord-trial] pool injection found no matching weighted block - vanilla pool shape changed? (#324)")
    return false
end

-- Load-time attempt (succeeds when enemy_tweaker loaded first); the
-- start_terror_event hook retries at every chest activation otherwise.
mod._ct_ensure_warlord_trial()

-- ============================================================
-- v0.7.128-dev — Parry-proc boon no-cooldown + per-career burn-on-ability VFX
-- ============================================================
-- 2026-05-28 user request, items 3/4/5/6 (of a 6-item batch). Items 1 (Necro
-- "+1 skeleton per active boon" career boon) and 2 (Handmaiden firewalk dash
-- boon) are deferred to a follow-up release — they require new boon-template
-- registration + career-spawn/lunge-state changes that need their own
-- focused pass. Items 3-6 reuse the well-tested Myrmidia's Wildfire
-- replacement pattern (see block immediately below this one) and are
-- ship-safe in this drop.

-- ---- Items 5 + 6: strip cooldown from parry-proc boons ----
--
-- `static_blade` (deus_power_up_settings.lua:4205, "lightning bolt on parry"
-- — fx/cw_chain_lightning + boon_career_ability_lightning_aoe damage) and
-- `boon_skulls_03` (deus_power_up_settings.lua:3140, drakegun explosion on
-- parry) both ship a `cooldown_buff` field that gates the `on_timed_block`
-- proc to once per cooldown duration via vanilla buff_extension cooldown
-- check (buff_extension.lua:1378-1390). Nuking that field at mod boot makes
-- every successful timed block fire the proc — no cooldown.
local function _ct128_strip_parry_cooldowns()
    local templates = rawget(_G, "DeusPowerUpTemplates")
    if not (templates and templates.power_ups) then
        _dbg("[ct128] DeusPowerUpTemplates not ready; parry-cooldown strip skipped")
        return false
    end
    local function strip(name)
        local pu = templates.power_ups[name]
        if not (pu and pu.buff_template and pu.buff_template.buffs) then
            _dbg("[ct128] %s missing or unexpected shape; cooldown strip skipped", name)
            return
        end
        local n_stripped = 0
        for _, b in ipairs(pu.buff_template.buffs) do
            if b.cooldown_buff then
                _dbg("[ct128] %s: stripped cooldown_buff=%s", name, tostring(b.cooldown_buff))
                b.cooldown_buff = nil
                n_stripped = n_stripped + 1
            end
        end
        if n_stripped == 0 then
            _dbg("[ct128] %s: already cooldown-free (no cooldown_buff field)", name)
        end
    end
    strip("static_blade")
    strip("boon_skulls_03")
    return true
end
-- v0.7.130-dev: the boot-time `pcall(_ct128_strip_parry_cooldowns)` was
-- removed here. DeusPowerUpTemplates is reliably absent at mod-load time in
-- VT2 (verified by log line 1308 of console-2026-05-29-02.03.57: "[ct128]
-- DeusPowerUpTemplates not ready; parry-cooldown strip skipped"), so the
-- boot call always failed and the warning was confusing noise. The strip is
-- now driven entirely by the post-load call inside the
-- `generate_random_power_ups` hook above — fires on every boon roll, is
-- idempotent, and runs well before any parry could fire the proc.

-- ---- Items 3 + 4: per-career burn-on-career-ability VFX swap ----
--
-- `boon_careerskill_02` ("burn on career ability" — deus_power_up_settings.lua:
-- 4546) uses event `on_ability_activated` + buff_func
-- `career_ability_apply_dot_to_adjecent_enemies` (morris_buff_settings.lua:3683)
-- to apply a burn DoT to nearby enemies. The DoT template is the buff's
-- `template.dot_template_name`, hard-cached in `buff.cached_custom_dot` on
-- first call.
--
-- We want the visual to match the burning character: blue Moonfire flame for
-- Elf careers, balefire green for Necromancer, vanilla orange for everyone
-- else. Same exact mechanism as the Myrmidia's Wildfire hook below — wrap the
-- proc func, pre-seed `buff.cached_custom_dot.dot_template_name` with our
-- chosen template before calling vanilla, vanilla's lazy-init guard at line
-- 3704 then leaves our template alone.
--
-- Differences from the Wildfire hook (deliberate):
--   - Wildfire selects by TARGET burn status (status_effect:has_status). This
--     hook selects by OWNER career, because the burn originates from the
--     player's career ability press, not from a kill cascade.
--   - Wildfire uses StatusEffectNames.burning_elven_magic / _balefire / _warpfire
--     for the priority race. Here the owner career is unambiguous (one
--     career per player).
local _CT128_ELF_CAREERS = {
    we_waywatcher  = true,
    we_maidenguard = true,
    we_shade       = true,
    we_thornsister = true,
}

if ProcFunctions and ProcFunctions.career_ability_apply_dot_to_adjecent_enemies then
    -- Necromancer balefire variant: vanilla generates this lazily via
    -- BalefireBurnDotLookup (buff_utils.lua:267). Resolve on first need,
    -- cache the result.
    local _ct128_balefire_resolved = false
    local _ct128_balefire_dot      = nil

    local function _resolve_balefire_dot()
        if _ct128_balefire_resolved then return _ct128_balefire_dot end
        local lookup = rawget(_G, "BalefireBurnDotLookup")
        if lookup then
            _ct128_balefire_dot = lookup["boon_career_ability_burning_aoe"]
        end
        _ct128_balefire_resolved = true
        return _ct128_balefire_dot
    end

    local function _ct128_pick_dot_for_career(owner_unit)
        local career_ext = ScriptUnit.has_extension(owner_unit, "career_system")
        if not career_ext or not career_ext.career_name then return nil end
        local career_name = career_ext:career_name()
        if career_name == "bw_necromancer" then
            return _resolve_balefire_dot() or "boon_career_ability_burning_aoe"
        end
        if _CT128_ELF_CAREERS[career_name] then
            return "we_deus_01_dot_fast"
        end
        return nil  -- nil → no override, run vanilla unchanged
    end

    mod:hook(ProcFunctions, "career_ability_apply_dot_to_adjecent_enemies",
        function(func, owner_unit, buff, params)
            local chosen = _ct128_pick_dot_for_career(owner_unit)
            if not chosen then return func(owner_unit, buff, params) end
            -- Pre-seed cached_custom_dot. Vanilla's `cached_custom_dot or {...}`
            -- pattern means a pre-set table sticks; subsequent ticks use the
            -- same cached entry without reverting.
            buff.cached_custom_dot = buff.cached_custom_dot or { dot_template_name = chosen }
            buff.cached_custom_dot.dot_template_name = chosen
            return func(owner_unit, buff, params)
        end)
end

-- ============================================================
-- Myrmidia's Wildfire — spread DoT color matches the source burn (v0.7.73)
-- ============================================================
-- Boon `boon_dot_burning_01` (Myrmidia's Wildfire). When a burning enemy dies, vanilla's
-- `boon_dot_burning_01_spread` (morris_buff_settings.lua:3714) applies the HARDCODED
-- template `boon_career_ability_burning_aoe` (vanilla orange) to nearby enemies — even
-- if the dying enemy was burning from Moonfire Bow (blue) or Necromancer balefire (purple).
--
-- We hook the proc and pick the spread template based on what burn status effect the
-- killed unit was carrying:
--
--   StatusEffectNames.burning_elven_magic  → Moonfire Bow blue flame
--                                            spread template: `we_deus_01_dot_fast`
--   StatusEffectNames.burning_balefire     → Necromancer purple
--                                            spread template: vanilla's auto-generated
--                                            `boon_career_ability_burning_aoe_balefire`
--                                            via `BalefireBurnDotLookup`
--                                            (buff_utils.lua:267 generator)
--   StatusEffectNames.burning_warpfire     → Chaos sorcerer warp-flame: keep vanilla
--                                            orange so the boon's own spread reads as
--                                            Myrmidia's fire rather than warp-corruption
--   default (StatusEffectNames.burning)    → vanilla orange (unchanged behavior)
--
-- We hook `ProcFunctions.boon_dot_burning_01_spread` (same table as `chain_lightning`
-- above — buff_func entries live in `dlc_settings.morris.proc_functions`, merged into
-- the global `ProcFunctions` at boot — see the Manann's Tempest block above for the
-- full lookup-vs-buff_function_templates split documented at v0.7.57).
--
-- Caveat: vanilla's spread uses `buff.cached_custom_dot` (one allocation reused across
-- kills). Our hook writes a fresh `dot_template_name` into the cached table per call so
-- each kill picks the right color. The other cached field (`cached_broadphase`) is
-- still reused safely.
--
-- v0.7.73: initial color-match. The hook is also the future host for the v0.7.74
-- generations cap (Phase 2C); that change will tag each spread DoT with a `generation`
-- field and bail when the source generation exceeds the slider cap, but the color-match
-- path lives here and is the contract surface.
--
-- Replicates vanilla's `is_burning` early-out via the same `unit_is_burning` query
-- (no need to call the original at all).
if ProcFunctions and ProcFunctions.boon_dot_burning_01_spread then
    -- Map status-effect name → dot_template_name we spread with. We resolve the
    -- balefire variant lazily (after boot) because vanilla generates it after
    -- buff_settings load. The `_resolved` flag flips on first hit.
    local _ct_spread_dot_by_status = {
        burning_elven_magic = "we_deus_01_dot_fast",
        burning_balefire    = nil, -- resolved lazily from BalefireBurnDotLookup
        burning_warpfire    = "boon_career_ability_burning_aoe",
        burning             = "boon_career_ability_burning_aoe",
    }
    local _ct_spread_resolved = false

    -- v0.7.74: per-unit Wildfire-spread generation tracker. Weak-keyed so entries
    -- die with the unit. Generation 0 = the player's own initial burn (NOT in this
    -- table). Generation N = applied by a spread sourced from a unit at generation
    -- (N-1). Cap reads from `tweak_wildfire_generations_cap` (1-10, default 3).
    --
    -- Why weak-keyed: unit handles are reused by the spawner, but stale entries
    -- on dead units shouldn't pin them or leak indefinitely. We don't use
    -- generation as an authoritative buff field — it's a side-band tag that
    -- accompanies the cached_custom_dot. The DoT applied by `DamageUtils.apply_dot`
    -- doesn't propagate generation natively, so we must hop via this side table.
    local _ct_wildfire_generation = setmetatable({}, { __mode = "k" })

    local function _ct_resolve_balefire_spread()
        if _ct_spread_resolved then return end
        local lookup = rawget(_G, "BalefireBurnDotLookup")
        if lookup then
            local v = lookup["boon_career_ability_burning_aoe"]
            if v then
                _ct_spread_dot_by_status.burning_balefire = v
            end
        end
        _ct_spread_resolved = true
    end

    local function _ct_pick_spread_template(killed_unit)
        local sem = Managers.state and Managers.state.status_effect
        if not sem then
            return "boon_career_ability_burning_aoe"
        end
        local StatusNames = rawget(_G, "StatusEffectNames")
        if not StatusNames then
            return "boon_career_ability_burning_aoe"
        end
        _ct_resolve_balefire_spread()

        -- Priority: elven_magic > balefire > warpfire > vanilla. Moonfire and
        -- Necromancer are player-induced and worth surfacing; warpfire is enemy
        -- ambient so it loses the priority race if any other burn is present.
        if StatusNames.burning_elven_magic and sem:has_status(killed_unit, StatusNames.burning_elven_magic) then
            return _ct_spread_dot_by_status.burning_elven_magic
        end
        if StatusNames.burning_balefire and sem:has_status(killed_unit, StatusNames.burning_balefire) then
            return _ct_spread_dot_by_status.burning_balefire
                or "boon_career_ability_burning_aoe"
        end
        if StatusNames.burning_warpfire and sem:has_status(killed_unit, StatusNames.burning_warpfire) then
            return _ct_spread_dot_by_status.burning_warpfire
        end
        return "boon_career_ability_burning_aoe"
    end

    mod:hook(ProcFunctions, "boon_dot_burning_01_spread", function(func, owner_unit, buff, params)
        local killed_unit = params[3]
        if not (killed_unit and Managers.state and Managers.state.status_effect) then
            return func(owner_unit, buff, params)
        end
        if not Managers.state.status_effect:unit_is_burning(killed_unit) then
            return
        end

        -- v0.7.74: generations cap. Generation of THIS death = whatever was
        -- recorded for killed_unit (or 0 if it wasn't a spread DoT — e.g. burnt
        -- by the player's own shot). The new spread DoT will be tagged with
        -- src_gen + 1; if that would meet or exceed the cap, we don't spread.
        local cap = effective_setting("tweak_wildfire_generations_cap") or 3
        if type(cap) ~= "number" then cap = 3 end
        local src_gen = _ct_wildfire_generation[killed_unit] or 0
        if src_gen + 1 > cap then
            return -- chain depth exceeded; stop spreading
        end
        local new_gen = src_gen + 1

        local chosen = _ct_pick_spread_template(killed_unit)

        -- Re-implement vanilla spread with our chosen template and generation
        -- tracking. Mirrors morris_buff_settings.lua:3714-3743. We always handle
        -- spread ourselves (rather than falling through to vanilla for the
        -- orange case) so generation tagging is consistent across colors.
        local template = buff.template
        buff.cached_broadphase = buff.cached_broadphase or {}
        buff.cached_custom_dot = buff.cached_custom_dot or { dot_template_name = chosen }
        buff.cached_custom_dot.dot_template_name = chosen

        local side = Managers.state.side.side_by_unit[owner_unit]
        local num_nearby_enemies = AiUtils.broadphase_query(
            POSITION_LOOKUP[killed_unit],
            template.area_radius,
            buff.cached_broadphase,
            side.enemy_broadphase_categories
        )
        local hit_zone_name = "full"
        local damage_source = "buff"
        local damage_profile, target_index, power_level, boost_curve_multiplier, is_critical_strike, aoe_data

        for i = 1, num_nearby_enemies do
            local target_unit = buff.cached_broadphase[i]
            if target_unit ~= killed_unit then
                DamageUtils.apply_dot(
                    damage_profile, target_index, power_level, target_unit,
                    owner_unit, hit_zone_name, damage_source, boost_curve_multiplier,
                    is_critical_strike, aoe_data, owner_unit, buff.cached_custom_dot
                )
                -- Tag the neighbor with the new generation. If it already has a
                -- LOWER generation tag (e.g. spread from a closer earlier source
                -- this same frame), we keep the lower one — the chain is bounded
                -- by the SHORTEST path, which is the more conservative choice
                -- for cap interpretation.
                local prev = _ct_wildfire_generation[target_unit]
                if not prev or new_gen < prev then
                    _ct_wildfire_generation[target_unit] = new_gen
                end
            end
        end
    end)
end

-- ============================================================
-- Larger Clip — scale ammo_per_reload alongside clip_size (v0.7.68 → v0.7.69 unconditional)
-- ============================================================
-- Vanilla `deus_larger_clip` (deus_power_up_settings.lua:2647-2673) uses
-- `stat_buff = "clip_size"` with multiplier 1 (+100%). On shotguns
-- (Grudge-Raker etc.) that doubles the clip from 2→4. BUT vanilla
-- `GenericAmmoUserExtension._ammo_per_reload` is set ONCE at init from the
-- weapon template (`grudge_raker.lua:155: ammo_per_reload = 2`) and is NEVER
-- passed through `apply_buffs_to_value`. So each shotgun pump still loads
-- only 2 shells, requiring 2 pumps to refill the doubled clip.
--
-- This is treated as an unintended vanilla bug (the boon is cut content
-- re-enabled by ct via activate_dormant_deus_larger_clip), not a rebalance —
-- fix applies unconditionally with no toggle. Hook fires on every weapon's
-- `_apply_buffs`; if no clip_size buff is active the scale factor is 1 and
-- nothing changes.
--
-- Captures `_ct_original_ammo_per_reload` once per extension instance to avoid
-- compounding across repeated `_apply_buffs` calls (which fire on every buff
-- add/remove). Reads the scaling factor from the ratio `_ammo_per_clip /
-- _original_ammo_per_clip` so ANY clip_size source (boon, talent, future
-- modded buff) drives the reload-tick scale too. On weapons without an
-- ammo_per_reload entry (everything that already reload-fills in one action)
-- this hook is a no-op — the `orig_reload <= 0` guard short-circuits.
-- CT_META_AMMO_MAX_AMMO_SAFETY_CLAMP_v0.7.108
-- VMF doctrine (CLAUDE.md § Hooking): `mod:hook_safe` does NOT chain on the
-- same (Class, method) — two registrations silently overwrite. So the larger-
-- clip ammo_per_reload fix AND the Issue #34 _max_ammo safety clamp share a
-- single hook body. Both run unconditionally; neither short-circuits the other.
mod:hook_safe("GenericAmmoUserExtension", "_apply_buffs", function(self)
    -- v0.7.108-dev (Issue #34) belt-and-suspenders: clamp `_max_ammo` to a
    -- finite, HUD-printable ceiling AFTER vanilla `_apply_buffs` has resolved
    -- `total_ammo` stat_buffs. With the v0.7.108 max_stacks=30 cap in place
    -- AND `_make_meta_proc` clamping num_boons to the same value, the meta-
    -- ammo boon can't push `_max_ammo` past ~4.3x base on its own. This clamp
    -- catches the case where some OTHER buff path (talent, weapon trait,
    -- foreign mod, future ct feature) ever feeds `total_ammo` enough stacks
    -- that the geometric stacking_multiplier resolution drives `_max_ammo`
    -- toward math.huge — at which point `tostring(_max_ammo) == "inf"` would
    -- render on the HUD (same shape as the wt v0.12.77 nil-hole burn). 9999
    -- is FAR above any realistic ammo pool (vanilla max is ~190 on a Drakegun
    -- pre-buffs) and stays well inside Lua's float-printable integer range.
    if type(self._max_ammo) == "number" and self._max_ammo > 9999 then
        self._max_ammo = 9999
    end

    -- Larger Clip ammo_per_reload scaling (v0.7.68 → v0.7.69 unconditional).
    -- See doc-block above this hook for the rationale.
    if not (self._original_ammo_per_clip and self._original_ammo_per_clip > 0) then return end
    if not self._ammo_per_clip then return end
    if self._ct_original_ammo_per_reload == nil then
        self._ct_original_ammo_per_reload = self._ammo_per_reload
    end
    local orig_reload = self._ct_original_ammo_per_reload
    if not orig_reload or orig_reload <= 0 then return end
    local scale = self._ammo_per_clip / self._original_ammo_per_clip
    self._ammo_per_reload = math.max(orig_reload, math.ceil(orig_reload * scale))
end)

-- ============================================================
-- Block Ranger Veteran from Saving Morgrim's
-- ============================================================
-- The `bardin_ranger_passive_consumeable_dupe_grenade` passive applies `not_consume_grenade` as a
-- proc stat_buff with proc_chance=0.1. When ActionChargedProjectileUtility.fire_charged_projectile
-- throws a grenade, it queries `apply_buffs_to_value(0, "not_consume_grenade")` to roll the proc
-- (action_charged_projectile.lua:83). We monkey-patch the buff_extension instance for the duration
-- of the call so the proc returns false specifically when the grenade is a Morgrim's Bomb. Other
-- grenades (frag, fire, conflagration) continue to roll normally.
mod:hook("ActionChargedProjectileUtility", "fire_charged_projectile", function(func, projectile_context, ...)
    if not effective_setting("rv_no_save_morgrim")
        or not projectile_context
        or projectile_context.item_name ~= "holy_hand_grenade"
        or not projectile_context.is_grenade
        or projectile_context.grenade_thrown
    then
        return func(projectile_context, ...)
    end

    local buff_ext = projectile_context.buff_extension
    if not buff_ext then
        return func(projectile_context, ...)
    end

    -- rawget so we know whether the instance had a pre-existing override (vs. inheriting via
    -- __index from the class). On restore we either reinstate the override or clear our shim.
    local had_instance_override = rawget(buff_ext, "apply_buffs_to_value") ~= nil
    local original = buff_ext.apply_buffs_to_value
    buff_ext.apply_buffs_to_value = function(self, value, stat_buff_name, ...)
        if stat_buff_name == "not_consume_grenade" then
            return value, false
        end
        return original(self, value, stat_buff_name, ...)
    end

    -- #259: also shim has_buff_perk so the RV-ability `free_grenade` PERK can't save Morgrim's,
    -- while Endless Bombs (which uniquely also grants rewield_grenade_on_throw) still can.
    local had_perk_override = rawget(buff_ext, "has_buff_perk") ~= nil
    local orig_has_perk = buff_ext.has_buff_perk
    buff_ext.has_buff_perk = function(self, perk_name, ...)
        if perk_name == "free_grenade" and not orig_has_perk(self, "rewield_grenade_on_throw") then
            return false
        end
        return orig_has_perk(self, perk_name, ...)
    end

    local ok, a, b = pcall(func, projectile_context, ...)

    if had_instance_override then
        buff_ext.apply_buffs_to_value = original
    else
        buff_ext.apply_buffs_to_value = nil
    end
    if had_perk_override then
        buff_ext.has_buff_perk = orig_has_perk
    else
        buff_ext.has_buff_perk = nil
    end

    -- #259 verify diagnostic (printf, NOT mod:info): after the throw, projectile_context
    -- .free_grenade == true means the bomb was SAVED. endless_bombs flags the intended combo.
    pcall(printf, "[ct:morgrim259] Morgrim's throw: saved=%s endless_bombs=%s (toggle blocks RV save unless endless_bombs)",
        tostring(projectile_context.free_grenade == true),
        tostring(orig_has_perk(buff_ext, "rewield_grenade_on_throw") and true or false))

    if not ok then
        error(a, 0)
    end
    return a, b
end)
