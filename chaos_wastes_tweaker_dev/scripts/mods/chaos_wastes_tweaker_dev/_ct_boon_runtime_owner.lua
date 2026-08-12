-- Starting-boon acquisition, grant sources, diagnostics, and boss grudge sync.
return function(mod, ctx)
    local CT_META_AMMO_CAP = ctx.meta_ammo_cap
    local CT_META_AMMO_FLOOR = ctx.meta_ammo_floor
    local CT_META_AMMO_HYPERBOLIC_MARKER = ctx.meta_ammo_marker
    local CT_META_AMMO_MAX_STACKS = ctx.meta_ammo_max_stacks
    local CT_META_AMMO_STEP = ctx.meta_ammo_step
    local CT_RPC_SCHEMA = ctx.rpc_schema
    local MOD_VERSION = ctx.mod_version
    local REAL_PLAYER_LOCAL_ID = ctx.real_player_local_id
    local STARTING_COINS_MODE_MARKER = ctx.starting_coins_mode_marker
    local _CAREER_EXCLUSIVE_PICKUPS_BLOCKLIST = ctx.career_exclusive_pickups_blocklist
    local _capture_returns = ctx.capture_returns
    local _collect_setting_ids = ctx.collect_setting_ids
    local _ct_altar_reuse = ctx.altar_reuse
    local _ct_meta_ammo_cost_multiplier = ctx.meta_ammo_cost_multiplier
    local _ct_mutex = ctx.mutex
    local _dbg = ctx.dbg
    local _dbg_alert = ctx.dbg_alert
    local _rt_register = ctx.rt_register
    local effective_setting = ctx.effective_setting

-- Starting Boons
-- ============================================================

-- Pure policy seam for #556: only talent templates are suppressed by an existing
-- same-name power-up. Non-talents retain the historical starting-boon behavior.
function mod._ct_starting_talent_is_duplicate(template, name, existing_names)
    return template and template.talent == true and existing_names[name] == true
end

-- Starting-boons hook. Vanilla `_add_initial_power_ups` adds talent power-ups + event
-- boons after run setup; we append toggled starting boons after that (hook_safe = post-call).
--
-- HOST-ONLY: the server processes the hook for every peer in the lobby and uses the
-- HOST's `start_boon_*` settings — so every player gets the same starting boons,
-- whatever the host picked. Clients early-out unconditionally and never apply their
-- own start_boon settings (and never duplicate the host's grant either, which was
-- the old bug). The server's `run_state:set_player_power_ups(peer_id, ...)` call
-- syncs the granted boons to the target peer via the shared-state networking layer.
-- QUESTION: The hook signature drops the 5th arg `initial_talents_for_career` (vanilla has 5
-- positional args). hook_safe ignores extra args so this is fine, but a future maintainer adding a
-- new arg might be confused.
-- v0.7.118-dev: starting-boon grant is engine-driven (DeusRunController._add_initial_power_ups
-- fires per player-add at run start + on late joiner / bot add), NOT a user-typed operational
-- toggle. Per PROJECT_STANDARDS § 3.6 "Chat-echo policy" that means log-only, never chat.
-- Demoted from `mod:echo` to `mod:info("[ct:starting_boons] ...")` below.
mod:hook_safe("DeusRunController", "_add_initial_power_ups", function(self, peer_id, local_player_id, profile_index, career_index, initial_talents_for_career)
    local run_state = self._run_state
    if not run_state or not run_state:is_server() then return end  -- host-only
    if not DeusPowerUpsArray or not DeusPowerUpUtils then return end

    -- Vanilla has already materialized `initial_talents_for_career` into generic
    -- `talent_<tier>_<column>` power-ups before this hook_safe callback runs
    -- (deus_run_controller.lua:471-495).  Keep that post-call list as the canonical
    -- identity set: a configured starting talent that is already selected must not
    -- be appended a second time.  The fifth argument is named above as a signature
    -- lock even though the post-call list is more robust than rebuilding its mapping.
    local existing = run_state:get_player_power_ups(peer_id, local_player_id, profile_index, career_index)
    local existing_names = {}
    for _, power_up in ipairs(existing or {}) do
        if power_up and power_up.name then existing_names[power_up.name] = true end
    end

    local extra = {}
    local selected_talents_skipped = 0
    for _, entry in ipairs(DeusPowerUpsArray) do
        local name = entry.name
        if name and mod:get("start_boon_" .. name) then
            -- v0.7.240-dev (#426) peer-parity gate: a ct-modded starting boon written into
            -- this player's run-state list rides the shared-state sync as a modded
            -- deus_power_up_templates index (deus_run_state_spec.lua:60 encode / :85
            -- decode) and CTDs any non-ct peer. Vanilla starting boons are untouched.
            -- Fail-safe direction: an unconfirmed peer (e.g. a just-joined client whose
            -- beacon ack is still in flight) suppresses the MODDED grant for this event.
            local template = rawget(_G, "DeusPowerUpTemplates") and rawget(DeusPowerUpTemplates, name)
            if mod._ct_starting_talent_is_duplicate(template, name, existing_names) then
                selected_talents_skipped = selected_talents_skipped + 1
            elseif mod._ct_is_modded_power_up and mod._ct_is_modded_power_up(name)
                and not (mod._ct_wire_safe and mod._ct_wire_safe()) then
                pcall(printf, "[ct:426] starting boon %s skipped: peer parity not confirmed (modded boon would CTD a non-ct peer)", tostring(name))
            else
                extra[#extra + 1] = DeusPowerUpUtils.generate_specific_power_up(name, entry.rarity)
            end
        end
    end

    if selected_talents_skipped > 0 then
        pcall(printf, "[ct:556] starting talents: skipped=%d already selected for profile=%s career=%s",
            selected_talents_skipped, tostring(profile_index), tostring(career_index))
    end

    if #extra == 0 then return end

    -- The post-call `existing` snapshot already includes vanilla's talent + event
    -- boons. table.clone with skip_metatable keeps the array shape without copying
    -- any inherited methods.
    local skip_metatable = true
    local new_power_ups = table.clone(existing, skip_metatable)
    table.append(new_power_ups, extra)
    run_state:set_player_power_ups(peer_id, local_player_id, profile_index, career_index, new_power_ups)

    -- Resolve the player's character + career for the chat message. SPProfiles maps
    -- profile_index → profile (Kruber/Bardin/Kerillian/Sienna/Saltzpyre) and
    -- profile.careers maps career_index → career (es_mercenary, dr_slayer, etc.).
    -- Both use localization keys for display; Localize() resolves them to the
    -- player-facing names.
    local profile = rawget(_G, "SPProfiles") and SPProfiles[profile_index]
    local character = profile and profile.display_name and Localize(profile.display_name) or "?"
    local career = profile and profile.careers and profile.careers[career_index]
    local career_name = career and career.display_name and Localize(career.display_name) or "?"
    -- Player slot in the party: peer_id + local_player_id. Use party-slot index if
    -- available so users can quickly identify which on-screen panel got the boons.
    local slot_label = ""
    local party_manager = Managers.party
    if party_manager and party_manager.get_status_from_unique_id then
        local status = party_manager:get_status_from_unique_id(peer_id, local_player_id)
        if status and status.party_id and status.slot_id then
            slot_label = string.format(" [P%d:S%d]", status.party_id, status.slot_id)
        end
    end

    _dbg("[ct:starting_boons] granted %d to %s (%s)%s",
        #extra, character, career_name, slot_label)
end)

-- ============================================================
-- Hold-Tab player-list panel -> _ct_tab_panel_owner.lua (#1159)
-- ============================================================
-- Owns every ct addition to IngamePlayerListUI, the hold-Tab overlay: the #461
-- Starting-Boon preview built on panel activation in the Pilgrimage Chamber
-- plus its #1004 hover tooltip and the /ct_preview_boons text mirror, and the
-- #533 Chaos Wastes collectible counters (Chests of Trials / Pilgrim's Coins)
-- that replace vanilla's tome/grimoire/dice counters inside a deus run. Both
-- overlays share ONE guarded draw pass; that consolidation is why they are one
-- owner and not two (VMF silently drops a second hook on the same
-- Class/method pair, so IngamePlayerListUI._draw can only ever have one).
--
-- The module also wires the five side files this panel drives:
-- _ct_boon_preview_tooltip, _ct_boon_preview_runtime, _ct_boon_preview_helpers,
-- _ct_diag_tab_native533, and _ct_tab_collectibles_layout (#571).
--
-- Composes with, and does not overlap, _ct_pickup_spawn_owner /
-- _ct_spawn_eligibility_owner: those decide what exists in the world, this one
-- only reports run-scoped counters read from the replicated deus-run
-- SharedState and previews the host-effective starting-boon configuration.
--
-- dofile'd HERE, at the exact point the block used to execute -- after the
-- DeusRunController._add_initial_power_ups starting-boon grant hook above and
-- before the #458 start-shrine dofiles below -- so hook registration order,
-- side-module load order, and _rt_register append order are unchanged. The
-- module reaches this chunk's helpers through the mod._ct_* seams published
-- earlier (mod._ct_rt_register, mod._ct_effective_setting,
-- mod._ct_starting_talent_is_duplicate). No file-local had to be promoted: the
-- block's only file-scope local (_ct_tab_layout_571) is read solely inside the
-- block and moved with it.
mod:dofile("scripts/mods/chaos_wastes_tweaker_dev/_ct_tab_panel_owner")

-- ============================================================
-- Buy Starting Boons -- start-node shrine shop (#458)
-- ============================================================
-- The run's START node runs inside GameModeMapDeus, whose shared-state machine can
-- be in MAP_DECISION (the map screen) or SHOP (a shrine overlay). Vanilla starts a
-- run in MAP_DECISION; a shrine is only reached later by CHOOSING a shop node
-- (game_mode_map_deus.lua:332 new_node.node_type=="shop" -> handle_shrine_entered ->
-- states.SHOP). Both states run on the SAME persistent dlc_morris_map world (the
-- ferry-lady hub), so a shrine is an overlay + spawned idol props, NOT a separate
-- level load. That lets us open the shrine at run start with no graph or node change.
--
-- DESIGN (#458): when the HOST enables ct_buy_starting_boons, we force GameModeMapDeus
-- into its SHOP state at run start (current node still "start"). Vanilla's own SHOP ->
-- WAITING_FOR_PLAYERS_AFTER_SHOP -> MAP_DECISION path (game_mode_map_deus.lua:341-349)
-- then returns every peer to the normal first map choice after buying. We never call
-- handle_shrine_entered (that would mark the start node traversed / could alter its map
-- token) and never touch node_type -- so the start node's map APPEARANCE is unchanged,
-- exactly as the issue requires: "simply puts the player in the shop menu."
--
-- CONFIG: DeusShopView.start resolves its offer from DeusShopSettings.shop_types
-- [current_node.level] (deus_shop_view_v2.lua:181-184). The start node's level is
-- "dlc_morris_map", which is never a shop in vanilla, so shop_types["dlc_morris_map"]
-- is ours alone. We register it (power_up_count + blessings) from host-effective
-- settings so the count/miracle pool follow the host across the lobby (the ct_ keys are
-- auto-added to SYNCED_SETTING_NAMES because they are not per-peer). Boon OFFERS are
-- per-peer-seeded exactly like a vanilla shrine (each hero sees their own), so no coop
-- offer-sync is needed; the blessing SUBSET is seeded by the start node's blessings seed
-- so every peer selects the same miracles.
--
-- WIRE SAFETY: the shrine reuses vanilla's shop buy path (shop_buy_power_up /
-- shop_buy_blessing) with vanilla RPC indices. Boons offered come from
-- generate_random_power_ups -> DeusPowerUpRarityPool, which ct already parity-ejects for
-- modded boons under unconfirmed peer parity (#426), so a non-ct peer can never be
-- offered (hence never buy) a modded index. Miracles are all vanilla blessing keys
-- (deus_blessing_settings.lua). So this feature adds NO new peer-sync exposure.
--
-- INTERACTION with the free Starting Boons list (DeusRunController._add_initial_power_ups
-- hook above): they STACK and are orthogonal. The free grant runs at run setup (before
-- the shrine opens), so generate_random_power_ups sees those boons as existing and will
-- not re-offer them (vanilla dedupe, deus_run_controller.lua:1110). A pure buy-your-own
-- start = leave the free list off. Documented in the toggle tooltip.
--
-- The start-shrine feature is a natural module boundary: it owns the synthetic
-- node identity, config-before-full-sync crash floor, pricing, and purchase
-- ledger. Loading both files here keeps the monolith below its frozen baseline.
mod._ct_start_shrine_policy = mod:dofile("scripts/mods/chaos_wastes_tweaker_dev/_ct_start_shrine_policy")
mod._ct_start_shrine_runtime = mod:dofile("scripts/mods/chaos_wastes_tweaker_dev/_ct_start_shrine_runtime")
_rt_register("issue458_start_shrine_config", mod._ct_start_shrine_runtime.regression)
mod._ct_boon_pricing_runtime = mod:dofile("scripts/mods/chaos_wastes_tweaker_dev/_ct_boon_pricing_runtime")
_rt_register("issue467_individual_boon_prices", mod._ct_boon_pricing_runtime.regression)

-- ============================================================
-- Boon grant / purchase choke point -> _ct_boon_grant_owner.lua (#1159)
-- ============================================================
-- Owns every seam that fires when a Chaos Wastes boon changes hands: the
-- pre-grant disable + peer-parity gate and the [boon-trace] audit on
-- DeusRunController.add_power_ups (#211/#426), the v0.7.76 bot boon mirror and
-- its random-roll mode with the #466 bot economy charge/refund, the
-- consolidated DeusRunController._try_buy_power_up shrine-purchase hook that
-- #458 and #467 are both delegated from, the two DeusShopView price seams for
-- that purchase, and the two bot-boon regression checks.
--
-- dofile'd HERE, at the exact point the block used to execute -- immediately
-- after the #458 start-shrine and #467 boon-pricing dofiles it delegates to,
-- immediately before the #211 grant-source tagging wrappers that write the
-- mod._ct_grant_source it reads -- so hook-registration order and _rt_register
-- append order are unchanged. The module reads the entry's helpers through the
-- mod._ct_* seams published earlier in this chunk (_ct_rt_register,
-- _ct_effective_setting, _ct_boon_disabled, the _ct_bot_economy* adapters), and
-- needed NO promotion of an entry file-local: the mirror's reentry guard
-- `_ct_bot_mirror_active` is read nowhere outside the moved lines, so it moved
-- with them.
mod:dofile("scripts/mods/chaos_wastes_tweaker_dev/_ct_boon_grant_owner")

_rt_register("issue331_bot_coin_pickup_installed", function()
    local policy = mod._ct_bot_coin_pickup
    if type(policy) ~= "table" or type(policy.poll_due) ~= "function"
        or type(policy.can_claim) ~= "function" or type(policy.claim_until) ~= "function" then
        return "#331 bot coin pickup policy missing or incomplete"
    end
    if policy.pickup_name ~= "deus_soft_currency" or policy.range ~= 10
        or policy.poll_interval ~= 1 or policy.claim_ttl ~= 1.5 then
        return "#331 bot coin pickup vanilla bounds drifted"
    end
    local due, next_t = policy.poll_due(10, 9)
    if not due or next_t ~= 11 then return "#331 poll self-test failed" end
    if policy.can_claim("healing_draught", 0, 10)
        or not policy.can_claim("deus_soft_currency", 10, 10)
        or policy.can_claim("deus_soft_currency", 11, 10) then
        return "#331 claim/identity self-test failed"
    end
end)

_rt_register("issue361_miasma_customization_installed", function()
    local policy = mod._ct_miasma_policy
    if type(policy) ~= "table" or type(policy.radius) ~= "function"
        or type(policy.interval) ~= "function" or type(policy.select_owner) ~= "function" then
        return "#361 Miasma policy missing or incomplete"
    end
    if policy.radius(nil) ~= 8 or policy.interval(nil) ~= 1.3
        or policy.radius(100) ~= 30 or policy.interval(0) ~= 0.1 then
        return "#361 Miasma slider self-test failed"
    end
    if not rawget(_G, "__ct_miasma361_hook_installed") then
        return "#361 live MutatorTemplates curse update hook missing"
    end
    if type(mod._ct_sync_miasma) ~= "function" or not mod._ct_sync_miasma() then
        return "#361 Miasma buff template unavailable"
    end
end)

_rt_register("boon_price_audit_armed", function()
    if CT_BOON_PRICE_AUDIT_MARKER ~= "boon_price_audit:auto_once_bounded_v0.7.279" then
        return "#467 boon price audit marker missing or stale"
    end
    local audit = mod._ct_boon_pricing_audit
    if type(audit) ~= "table" or type(audit.audit) ~= "function"
        or type(audit.validate_plan) ~= "function" then
        return "#467 pure audit/plan policy incomplete"
    end
    if type(mod._ct_boon_price_audit_once) ~= "function" then
        return "#467 automatic runtime census missing"
    end
    local report = audit.audit({ rare = { { name = "ct_467_self_test" } } },
        { rare = 200 }, { ct_467_self_test = {} }, 1)
    if report.total ~= 1 or #report.records ~= 1
        or report.records[1].shop_price ~= 200 or #report.anomalies ~= 0 then
        return "#467 audit self-test failed"
    end
end)

-- #294 crash guard: the _spawn_pickup hook must skip a non-resident pickup unit (vanilla's
-- own _safe_to_spawn_pickup check, which the _spawn_pickup path omits). Verify the guard
-- helper exists and classifies correctly: nil settings + spawn_override_func pickups are SAFE
-- (pass-through), a bogus non-resident unit_name is UNSAFE. Marker present too.
_rt_register("pickup_residency_guard_installed", function()
    if type(CT_PICKUP_RESIDENCY_GUARD_MARKER) ~= "string" or #CT_PICKUP_RESIDENCY_GUARD_MARKER == 0 then
        return "#294 REGRESSION: CT_PICKUP_RESIDENCY_GUARD_MARKER not defined"
    end
    if type(mod._ct_pickup_unit_spawn_safe) ~= "function" then
        return "#294 REGRESSION: mod._ct_pickup_unit_spawn_safe missing (non-resident pickup crash guard)"
    end
    if mod._ct_pickup_unit_spawn_safe(nil) ~= true then
        return "#294 REGRESSION: guard must treat nil settings as safe (pass-through)"
    end
    if mod._ct_pickup_unit_spawn_safe({ unit_name = "units/x_zzz", spawn_override_func = function() end }) ~= true then
        return "#294 REGRESSION: guard must leave spawn_override_func pickups alone (they self-spawn)"
    end
    -- With Application.can_get available (in-mission), a bogus unit path must read UNSAFE.
    if rawget(_G, "Application") and Application.can_get then
        if mod._ct_pickup_unit_spawn_safe({ unit_name = "units/mutator/__ct294_bogus_unit__" }) ~= false then
            return "#294 REGRESSION: guard must classify a non-resident unit_name as UNSAFE (would crash spawn_network_unit)"
        end
    end
end)

-- #322: the _spawn_pickup hook must capture AND re-return BOTH of vanilla's return
-- values (pickup_unit, pickup_unit_go_id). Dropping the go_id (`return spawned`)
-- desyncs surface-linked pickups to clients (pickup_system.lua:1441 rpc_link_pickup).
-- Source-pattern check: assert the two-value capture + two-value return survive.
-- Anchored via the same-file #294 helper; best-effort (nil = pass if unreadable).
_rt_register("spawn_pickup_returns_both_values", function()
    -- issue 511: assert the load-time provenance marker set beside the _spawn_pickup
    -- hook instead of source-reading (the VMF sandbox has no `io`, so the old
    -- io.open self-grep threw and FAILED this on healthy code). The exact 2-value
    -- capture/return shape is delegated to a repo QA gate (PROJECT_STANDARDS 2.2b tier a).
    if CT_SPAWN_PICKUP322_MARKER ~= "spawn_pickup322:two_value_capture_and_return_v0.7.245" then
        return "#322 REGRESSION: CT_SPAWN_PICKUP322_MARKER missing/mismatch (two-return _spawn_pickup hook stripped -- linked-pickup rpc_link_pickup client sync breaks); got: " .. tostring(CT_SPAWN_PICKUP322_MARKER)
    end
end)

-- #299 ordered rescue transaction. Presence alone is insufficient: July 20 logs
-- proved the old tick existed but died silently before teleporting. Pin the pure
-- policy marker plus the arm/process/tick adapters that enforce MOVE before FREE.
_rt_register("issue299_chest_revive_team_teleport_ordered", function()
    local policy = mod._ct_chest_revive_policy
    if type(policy) ~= "table" or policy.MARKER ~= "ct299:move_before_free_v1" then
        return "#299 REGRESSION: move-before-free policy marker missing/mismatch"
    end
    if type(mod._ct299_arm) ~= "function" or type(mod._ct299_process) ~= "function" then
        return "#299 REGRESSION: ordered rescue arm/process adapters missing"
    end
    if type(mod._ct_chest_teleport_tick) ~= "function" then
        return "#299 REGRESSION: ordered rescue deferred tick missing"
    end
    if type(mod._ct_pending_team_teleport) ~= "table" then
        return "#299 REGRESSION: mod._ct_pending_team_teleport table missing (teleport arm store)"
    end
    if type(mod:get("respawn_on_chest_complete")) ~= "boolean" then
        return "#299 REGRESSION: respawn_on_chest_complete checkbox not registered (mod:get is non-boolean)"
    end
end)

-- #144 Vaul's Anvil reconciler/probe guard: the perk self-healing update func must exist and be
-- registered into BuffFunctionTemplates.functions under the name the ct boon's controller buff
-- points its update_func at, so the perk (deus_always_blocking_buff -> override_blocking) is
-- reconciled every frame instead of relying on vanilla's orphaned weapon-swap trigger. Registration
-- is deferred to whenever BuffFunctionTemplates is ready, so in a bare test env (no engine tables)
-- only the callable presence is asserted.
_rt_register("vauls_anvil_reconciler_installed", function()
    if type(mod._ct_vauls_anvil_reconcile) ~= "function" then
        return "#144 REGRESSION: mod._ct_vauls_anvil_reconcile missing (Vaul's Anvil perk reconciler)"
    end
    local bft = rawget(_G, "BuffFunctionTemplates")
    if bft and bft.functions then
        if bft.functions.ct_vauls_anvil_reconcile ~= mod._ct_vauls_anvil_reconcile then
            return "#144 REGRESSION: ct_vauls_anvil_reconcile not registered into BuffFunctionTemplates.functions (buff update_func won't resolve)"
        end
    end
end)

-- ============================================================
-- v0.7.200-dev (#211) — grant-source tagging hooks
-- ============================================================
-- Each wraps ONE vanilla grant path that re-enters DeusRunController.add_power_ups, so
-- the [boon-trace] grant printf in the consolidated add_power_ups hook above can name
-- its source. Marker is saved/restored around the wrapped call (synchronous, single
-- frame — race-free). pcall + re-raise so a vanilla error can't leave a stale marker.
--
-- Vanilla grant-path map (2026-07-01 audit for #211, deus_run_controller.lua /
-- deus_chest_extension.lua / deus_cursed_chest_view.lua / deus_run_state.lua):
--   COVERED by the roll-pool strip (generate_random_power_ups hook):
--     * boon-ALTAR stored roll  — DeusChestExtension._generate_stored_power_up:400 ->
--       controller:generate_random_power_ups:1099 -> util plural :1115
--     * shrine shop offerings   — deus_shop_view_v2.lua:184 (same controller method)
--     * Chest of Trials picks   — deus_cursed_chest_view.lua:58 (same controller method)
--     * end-of-level random     — try_grant_end_of_level_deus_power_ups:1314 + the
--       late-join RPC variant :421 (both call the plural util directly; both then write
--       run_state directly and NEVER call add_power_ups — pool strip is the only filter)
--   COVERED by the pre-grant gate (add_power_ups hook):
--     * everything that calls DeusRunController.add_power_ups (altar open_chest:548,
--       CoT view pick :299, set rewards :1291, ct's bot loop)
--   NOT COVERED (deliberate — instrument/document only):
--     * _add_initial_power_ups :471 — the player's OWN TALENTS materialized as boons
--       (must never be stripped) + run_state:get_event_boons() live-event freebies;
--       writes run_state directly. Stripping here would desync shared run state.
--     * grant_party_power_up :1770 + belakor_ingame_challenge_settings.lua:34 — quest
--       reward grants a SPECIFIC named quest power-up and activates it directly
--       (activate_deus_power_up), never entering add_power_ups.
--     * terror_event_power_up party grant :1349 — node-configured SPECIFIC party boon,
--       written to party state directly.
mod:hook("DeusRunController", "_check_set_completed", function(func, self, ...)
    local prev = mod._ct_grant_source
    mod._ct_grant_source = "set_reward"
    local ok, err = pcall(func, self, ...)
    mod._ct_grant_source = prev
    if not ok then
        mod:warning("[boon-trace] vanilla _check_set_completed raised: %s", tostring(err))
        error(err, 2)
    end
end)

mod:hook("DeusCursedChestView", "_on_button_pressed", function(func, self, ...)
    local prev = mod._ct_grant_source
    mod._ct_grant_source = "cot_view_pick"
    local ok, err = pcall(func, self, ...)
    mod._ct_grant_source = prev
    if not ok then
        mod:warning("[boon-trace] vanilla DeusCursedChestView._on_button_pressed raised: %s", tostring(err))
        error(err, 2)
    end
end)

-- Regression guard (#211): the shared disabled-boon check + the bot-picker filter and
-- grant-source tagging consolidated into the existing add_power_ups / bot-mirror hooks.
_rt_register("boon_disable_shared_gate", function()
    if type(mod._ct_boon_disabled) ~= "function" then
        return "#211 REGRESSION: mod._ct_boon_disabled missing (shared disabled-boon check)"
    end
    if mod._ct_boon_disabled("__ct_no_such_boon__") ~= false then
        return "#211 REGRESSION: _ct_boon_disabled should be false for an unknown boon key"
    end
    if mod._ct_boon_disabled(nil) ~= false then
        return "#211 REGRESSION: _ct_boon_disabled(nil) should be false"
    end
end)

-- Per-bot late-respawn re-apply. CW's `_add_initial_power_ups` (host-side per
-- peer at run start) already grants bots the talent-boon defaults; the host's
-- early-run mirror calls during initial setup then propagate via the hook
-- above. The only respawn case that bypasses both is a mid-run bot career
-- swap (rare) — vanilla doesn't re-run _add_initial_power_ups in that case
-- and there is no general "bot career swap" event in CW. We accept this as a
-- known limit; users can disable + re-enable the bot to re-grant.

-- Bot weapon-chest generation/equip, reusable-altar presentation, chest
-- diagnostics, and the singleton consolidated open_chest hook share one owner.
-- Install here to preserve the original registration order after grant tagging.
-- #1159: the four altar values below are the SAME objects as before, now sourced
-- from _ct_altar_reuse_owner (which holds the ledger and the max-uses policy) and
-- from the two probe globals that owner defines at its install site far above.
-- altar_uses stays an accessor because reset_uses rebinds the ledger each run.
mod:dofile("scripts/mods/chaos_wastes_tweaker_dev/_ct_bot_weapon_chest_owner")({
    mod = mod,
    effective_setting = effective_setting,
    dbg = _dbg,
    dbg_alert = _dbg_alert,
    altar_uses = _ct_altar_reuse.altar_uses,
    altar_max_uses = _ct_altar_reuse.altar_max_uses,
    probe_collected_by_peers = _ct_probe_collected_by_peers,
    altar_probe_watch = _ct_altar_probe_watch,
})

-- Boss Grudge Marks own their native-set baseline, universal apply filter,
-- and matching diagnostic commands behind one reload-stable owner.
local _boss_grudge_owner = mod:dofile(
    "scripts/mods/chaos_wastes_tweaker_dev/_ct_boss_grudge_marks")({
    mod = mod,
    effective_setting = function(setting_id)
        return effective_setting(setting_id)
    end,
    is_banned = function(master_value, child_value)
        return mod._ct_umbrella_policy.banned(master_value, child_value)
    end,
    get_global = function(name)
        return rawget(_G, name)
    end,
    get_managers = function()
        return Managers
    end,
    dbg = function(fmt, ...)
        return _dbg(fmt, ...)
    end,
    printf = function(fmt, ...)
        return printf(fmt, ...)
    end,
})
local sync_grudge_marks = _boss_grudge_owner.sync

-- 2026-05-23 v0.7.100-dev DISABLED: /verify_dormants chat command removed because the
-- dormant feature is fully purged. Re-enable alongside the dormant injection code.
-- The regression check `dormant_chat_commands_removed` asserts the command is absent
-- from the VMF command registry.
--[[
mod:command("verify_dormants", "Verify each dormant boon toggle vs live DeusPowerUpsArrayByRarity / DeusPowerUpRarityPool state", function()
    -- original body removed in v0.7.100-dev purge; see git history for full code.
end)
--]]

mod:command("verify_belakor", "Verify Belakor's Temple state: with_belakor / arena_belakor_node / current_node", function()
    local mechanism = Managers and Managers.mechanism and Managers.mechanism:game_mechanism()
    local rc = mechanism and mechanism.get_deus_run_controller and mechanism:get_deus_run_controller()
    local rs = rc and rc._run_state
    if not rs then
        mod:echo("[verify_belakor] N/A: no active DeusRunState (not in a CW run). Re-run after Olesya intro.")
        return
    end
    -- v0.7.120: vanilla method is `get_belakor_enabled`, NOT `get_with_belakor` —
    -- pre-v0.7.120 this command printed nil because the wrong name was used.
    local with_belakor   = (rs.get_belakor_enabled and rs:get_belakor_enabled())
                           or (rs.get_with_belakor and rs:get_with_belakor())
    local arena_node     = rs.get_arena_belakor_node and rs:get_arena_belakor_node()
    local current_node   = rs.get_current_node_key and rs:get_current_node_key()
    local force_setting  = effective_setting("force_belakor")
    local is_server      = rs.is_server and rs:is_server()
    pcall(printf, "[verify_belakor] is_server=%s force_belakor=%s belakor_enabled=%s arena_node=%s current_node=%s",
        tostring(is_server), tostring(force_setting), tostring(with_belakor),
        tostring(arena_node), tostring(current_node))
    local will_force_unique = (current_node and arena_node and current_node == arena_node) or false
    pcall(printf, "[verify_belakor] cursed_chest at current_node will force unique-tier? %s", tostring(will_force_unique))
    mod:echo(string.format("/verify_belakor: belakor_enabled=%s arena_node=%s current_node=%s (see log for full state)",
        tostring(with_belakor), tostring(arena_node), tostring(current_node)))
end)

-- v0.7.120 — `/dump_journey` runs the same full-state diagnostic as the
-- DeusMapDecisionView._start hook but on-demand from chat. Use this:
--   * Both peers run it AT THE SAME TIME (host + client) in a co-op CW run.
--   * Both logs are diffed against each other to find host/client divergence.
-- Surfaces: graph node count, arena nodes per peer, belakor_enabled, arena_belakor_node,
-- current_node, journey, force_belakor effective setting, plus per-node prefix dump.
-- Same `[belakor:diag]` tag as the auto-hooks so a single grep covers both.
mod:command("dump_journey", "Dump full CW journey state: graph nodes, arena_belakor, belakor_enabled, settings", function()
    local mechanism = Managers and Managers.mechanism and Managers.mechanism:game_mechanism()
    local rc = mechanism and mechanism.get_deus_run_controller and mechanism:get_deus_run_controller()
    if not rc then
        mod:echo("/dump_journey: no active CW run (run from inside a CW expedition).")
        return
    end
    local rs = rc._run_state
    local is_server = (rs and rs.is_server and rs:is_server()) or (Managers and Managers.player and Managers.player.is_server) or false
    local cur_key = rc.get_current_node_key and rc:get_current_node_key() or nil
    local journey = rc.get_journey_name and rc:get_journey_name() or nil
    local arena_node = rs and rs.get_arena_belakor_node and rs:get_arena_belakor_node() or nil
    local belakor_enabled = rs and rs.get_belakor_enabled and rs:get_belakor_enabled() or nil
    local seen = rc.has_own_seen_arena_belakor_node and rc:has_own_seen_arena_belakor_node() or nil
    local pg = rc._get_graph_data and rc:_get_graph_data() or nil
    local total, arena_count = 0, 0
    local arena_keys = {}
    if type(pg) == "table" then
        for k, n in pairs(pg) do
            total = total + 1
            if type(n) == "table" then
                local lvl = n.level or ""
                if type(lvl) == "string" and lvl:find("^arena") then
                    arena_count = arena_count + 1
                    arena_keys[#arena_keys + 1] = tostring(k) .. "(" .. lvl .. ",theme=" .. tostring(n.theme) .. ")"
                end
            end
        end
    end
    pcall(printf, "[belakor:diag] /dump_journey is_server=%s journey=%s current_node=%s belakor_enabled=%s arena_belakor_node=%s has_own_seen=%s graph_total=%d arena_in_graph=%d (%s) force_setting=%s",
        tostring(is_server), tostring(journey), tostring(cur_key),
        tostring(belakor_enabled), tostring(arena_node), tostring(seen),
        total, arena_count, table.concat(arena_keys, ","),
        tostring(effective_setting("force_belakor")))
    if type(pg) == "table" then
        for k, n in pairs(pg) do
            if type(n) == "table" then
                local lvl = tostring(n.level or "?")
                local prefix
                if k == "start" then
                    prefix = "<start>"
                else
                    local us = lvl:find("_")
                    prefix = (us and us > 1) and lvl:sub(1, us - 1) or lvl
                end
                local mut_str = "<nil>"
                if type(n.mutators) == "table" then
                    local list = {}
                    for i, m in ipairs(n.mutators) do list[i] = tostring(m) end
                    mut_str = "{" .. table.concat(list, ",") .. "}"
                end
                pcall(printf, "[belakor:diag] /dump_journey node %s level=%s prefix=%s theme=%s curse=%s god=%s node_type=%s level_seed=%s mutators=%s",
                    tostring(k), lvl, prefix, tostring(n.theme),
                    tostring(n.curse), tostring(n.god), tostring(n.node_type),
                    tostring(n.level_seed), mut_str)
            end
        end
    end
    mod:echo(string.format("/dump_journey: is_server=%s journey=%s arena_count=%d (see log for full per-node dump — grep [belakor:diag])",
        tostring(is_server), tostring(journey), arena_count))
end)

-- v0.7.120 — `/dump_isha` quick snapshot of Isha mutex state (Issue #54).
-- Surfaces what each peer sees: local toggles + effective_setting (host-broadcast) +
-- which description text WOULD be returned by the Localize hook. Diff host vs client
-- to confirm description-source fix.
mod:command("dump_isha", "Dump Miracle of Isha mutex state: local toggles, effective settings, description selection", function()
    local is_server = Managers and Managers.player and Managers.player.is_server
    local aegis_local = mod:get("tweak_miracle_of_isha_aegis")
    local wounds_local = mod:get("tweak_miracle_of_isha_wounds")
    local aegis_eff = effective_setting("tweak_miracle_of_isha_aegis")
    local wounds_eff = effective_setting("tweak_miracle_of_isha_wounds")
    local legacy_eff = effective_setting("tweak_miracle_of_isha_alternative")
    local desc_choice = "vanilla"
    if aegis_eff then desc_choice = "aegis"
    elseif wounds_eff then desc_choice = "wounds"
    elseif legacy_eff == true or legacy_eff == "aegis" then desc_choice = "aegis (legacy)"
    elseif legacy_eff == "wounds" then desc_choice = "wounds (legacy)"
    end
    pcall(printf, "[isha:diag] /dump_isha is_server=%s local_aegis=%s local_wounds=%s eff_aegis=%s eff_wounds=%s legacy=%s -> desc_choice=%s",
        tostring(is_server), tostring(aegis_local), tostring(wounds_local),
        tostring(aegis_eff), tostring(wounds_eff), tostring(legacy_eff), desc_choice)
    mod:echo(string.format("/dump_isha: desc_choice=%s eff_aegis=%s eff_wounds=%s (see log)",
        desc_choice, tostring(aegis_eff), tostring(wounds_eff)))
end)

-- v0.7.95: starting_coins verification (setter vs adder regression).
-- Prints current coin balance, the active setting, and whether the override
-- hook is registered. Use during a CW run to confirm the value applied.
-- #912 audit repair (2026-08-03): the value the setup_run hook APPLIES is the
-- host-broadcast effective_setting, not the local mod:get value, so report
-- BOTH - a client whose local setting differs from the host now sees the
-- mismatch instead of a falsely reassuring local-only readout.
mod:command("verify_coins", "Verify starting_coins: live coin balance vs local + host-effective setting, and override-hook registration", function()
    local mechanism = Managers and Managers.mechanism and Managers.mechanism:game_mechanism()
    local rc = mechanism and mechanism.get_deus_run_controller and mechanism:get_deus_run_controller()
    local local_setting, local_valid = mod._ct_starting_coins_policy.resolve(mod:get("starting_coins"), nil)
    local eff_setting, eff_valid = mod._ct_starting_coins_policy.resolve(effective_setting("starting_coins"), nil)
    local settings_desc = string.format("local=%s (valid=%s) host-effective=%s (valid=%s, APPLIED)%s",
        tostring(local_setting), tostring(local_valid), tostring(eff_setting), tostring(eff_valid),
        local_setting ~= eff_setting and " MISMATCH: host value wins on every peer" or "")
    local marker_present = (type(STARTING_COINS_MODE_MARKER) == "string"
        and STARTING_COINS_MODE_MARKER == mod._ct_starting_coins_policy.MARKER)
    local hook_registered_str = marker_present and "yes (setter-override mode marker present)" or "NO (marker missing)"
    if not rc then
        mod:echo(string.format("/verify_coins: %s, override-hook=%s, live balance=N/A (no active CW run - use during run)",
            settings_desc, hook_registered_str))
        pcall(printf, "[verify_coins] no active DeusRunController; %s marker=%s",
            settings_desc, tostring(marker_present))
        return
    end
    local own_peer_id = rc.get_own_peer_id and rc:get_own_peer_id()
    local balance = rc.get_player_soft_currency and own_peer_id and rc:get_player_soft_currency(own_peer_id)
    local is_server = rc.is_server and rc:is_server()
    pcall(printf, "[verify_coins] is_server=%s own_peer_id=%s %s live_balance=%s marker=%s",
        tostring(is_server), tostring(own_peer_id), settings_desc, tostring(balance), tostring(marker_present))
    mod:echo(string.format("/verify_coins: %s, live=%s, override-hook=%s, host=%s. NOTE: match expected only at run-start; mid-run balance reflects pickups/spends.",
        settings_desc, tostring(balance), hook_registered_str, tostring(is_server)))
end)

-- v0.7.97: career-exclusive pickup blocklist verifier.
-- Prints the blocklist constant + the current per-run denial counts so the
-- user can confirm the gate is working without re-reading the source.
mod:command("verify_engineer_bombs", "Verify career-exclusive pickup blocklist (Engineer crafted bombs etc.) + per-run denial counts", function()
    local names = {}
    for k in pairs(_CAREER_EXCLUSIVE_PICKUPS_BLOCKLIST) do names[#names + 1] = k end
    table.sort(names)
    if #names == 0 then
        mod:echo("/verify_engineer_bombs: blocklist EMPTY (regression?)")
        return
    end
    mod:echo(string.format("/verify_engineer_bombs: %d blocklist entries", #names))
    for _, name in ipairs(names) do
        local count = (ctx.get_career_exclusive_denial_counts()[name]) or 0
        local in_pickups = false
        if Pickups then
            for _, bucket in pairs(Pickups) do
                if type(bucket) == "table" and bucket[name] then
                    in_pickups = true
                    break
                end
            end
        end
        mod:echo(string.format("  %s : denials_this_run=%d, present_in_Pickups=%s",
            name, count, tostring(in_pickups)))
        pcall(printf, "[verify_engineer_bombs] %s denials_this_run=%d present_in_Pickups=%s",
            name, count, tostring(in_pickups))
    end
end)

-- Modified-boon runtime extraction (issue #2). The context is deliberately
-- short-lived: the module localizes every dependency during this one dofile,
-- then owns all boon/miracle/trait state and hooks at the original load point.
mod._ct_boon_runtime_context = {
    capture_returns = _capture_returns,
    collect_setting_ids = _collect_setting_ids,
    meta_ammo_cost_multiplier = _ct_meta_ammo_cost_multiplier,
    dbg = _dbg,
    rt_register = _rt_register,
    effective_setting = effective_setting,
    meta_ammo_cap = CT_META_AMMO_CAP,
    meta_ammo_floor = CT_META_AMMO_FLOOR,
    meta_ammo_marker = CT_META_AMMO_HYPERBOLIC_MARKER,
    meta_ammo_max_stacks = CT_META_AMMO_MAX_STACKS,
    meta_ammo_step = CT_META_AMMO_STEP,
    rpc_schema = CT_RPC_SCHEMA,
    mod_version = MOD_VERSION,
    mutex = _ct_mutex,
    real_player_local_id = REAL_PLAYER_LOCAL_ID,
    defeat_recovery_triggered = ctx.defeat_recovery_triggered,
}

    return {
        sync_grudge_marks = sync_grudge_marks,
    }
end
