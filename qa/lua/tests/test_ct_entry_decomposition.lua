return function(H, repo_root)
    local root = repo_root
        .. "/chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/"

    local function read(name)
        local file = assert(io.open(root .. name, "rb"))
        local source = file:read("*a")
        file:close()
        return source
    end

    local function count_plain(source, needle)
        local count, cursor = 0, 1
        while true do
            local at = source:find(needle, cursor, true)
            if not at then return count end
            count = count + 1
            cursor = at + #needle
        end
    end

    local entry = read("chaos_wastes_tweaker_dev.lua")
    local regression = read("_ct_regression.lua")
    local weapon_traits = read("_ct_weapon_trait_generation.lua")
    local bot_weapon_chest = read("_ct_bot_weapon_chest_owner.lua")
    local tab_panel = read("_ct_tab_panel_owner.lua")
    local boon_grant = read("_ct_boon_grant_owner.lua")
    local campaign_graph = read("_ct_campaign_graph_owner.lua")
    local altar_reuse = read("_ct_altar_reuse_owner.lua")
    local chest_revive = read("_ct_chest_revive_owner.lua")
    local boon_offer_view = read("_ct_boon_offer_view_owner.lua")
    local pickup_population = read("_ct_pickup_population_owner.lua")

    H.test("ct_dev entry stays below its frozen line baseline", function()
        local lines = 0
        for _ in entry:gmatch("[^\r\n]+") do lines = lines + 1 end
        -- 5665 = 2026-08-10 baseline after the #1159 pickup-population owner
        -- extraction (everything ct does at PickupSystem.populate_pickups: the
        -- per-mission altar / Chest-of-Trials / arena-ammo BUDGET patched into
        -- LevelSettings pickup_settings and restored around vanilla's call, the
        -- campaign-potion injection with full-group renormalization, the #143
        -- Morgrim's grenade redistribution, the #58/#156 spawn census with its
        -- 8s delayed printf, the entry probes, and the #132
        -- DeusCursedChestExtension.extensions_ready chest ground truth).
        --
        -- It replaces the 6108 baseline set by the #1159 boon-offer view owner
        -- extraction (everything ct does to WHERE the offered-boon widgets sit
        -- in the shrine DeusShopView and the Chest of Trials
        -- DeusCursedChestView: the degenerate-arc NaN repair, both build hooks,
        -- the #115/#114 scroll block, and the two wrapping update hooks that
        -- drive its per-frame reflow and input), which in turn replaced the 6433
        -- baseline set by the #1159 chest-revive owner
        -- extraction (everything ct does to the PARTY when a Chest of Trials
        -- completes: the host-gated OPEN detector, the three-downed-state
        -- triage, the #299 move-before-free rescue transaction with its arm /
        -- process / deferred-tick adapters, and the two post-respawn
        -- compensations - 50% temporary health and the single "revived" wound
        -- above Recruit), which in turn replaced the 6801 baseline set by the
        -- #1159 altar-reuse owner
        -- extraction (everything that depends on a DeusChestExtension ALTAR having been
        -- opened before: the #61 use ledger and its two settings policies, the
        -- mult^uses price curve, the re-roll seed mixing on all three generators,
        -- the #102 relaxed lit/interactable gates, the #252 upgrade-panel repaint,
        -- the v0.7.151 collected_by_peers retraction with its ct_altar_uncollect
        -- RPC, and the read-only v0.7.157 altar_visual_probe watcher), atop the
        -- campaign-graph, boon-grant, tab-panel, pickup-spawn, spawn-eligibility,
        -- Boss Grudge Marks, command, journey, preview-helper,
        -- weapon-trait-generation, and bot weapon-chest owners. The ceiling only
        -- ratchets DOWN as more of the ct_dev entry decomposes into modules; it
        -- must never grow.
        H.truthy(lines <= 5665, "entry non-empty line count exceeded frozen 5665 baseline")
    end)

    H.test("ct_dev regression module is dofile'd exactly once, at the suite's position", function()
        H.equal(count_plain(entry,
            "scripts/mods/chaos_wastes_tweaker_dev/_ct_regression"), 1)
        -- The module must install AFTER the sibling modules that set the marker
        -- globals its checks read (e.g. _ct_combat_hooks / _ct_boon_registry) and
        -- BEFORE the trailing feature dofiles, so /ct_regression_test append order
        -- is unchanged.
        local reg_at = assert(entry:find(
            "mods/chaos_wastes_tweaker_dev/_ct_regression", 1, true))
        local combat_at = assert(entry:find(
            "mods/chaos_wastes_tweaker_dev/_ct_combat_hooks", 1, true))
        local mech_at = assert(entry:find(
            "mods/chaos_wastes_tweaker_dev/_ct_mechanic_tweaks", 1, true))
        H.truthy(combat_at < reg_at,
            "_ct_combat_hooks (marker owner) must load before the regression suite")
        H.truthy(reg_at < mech_at,
            "regression suite must install before the trailing feature dofiles")
    end)

    H.test("ct_dev regression check registry is complete and not duplicated", function()
        -- Every _rt_register( occurrence (active checks + block-commented disabled
        -- stubs) is conserved across the split: the pre-extraction entry held 101;
        -- after extraction the module holds 68 and the entry retains 33 (the ~30
        -- scattered checks, the inline starting-coins check, and the commented
        -- stubs). No check was lost or duplicated: 68 + 33 == 101.
        -- v0.7.298-dev adds two NEW module checks (ct_meta_ammo_server_auth_grant_249,
        -- cursed_chest_reconcile_132): module 68 -> 70, conserved total 103.
        -- v0.7.304-dev adds one NEW module check (cot471_placement_topup, the #471
        -- Chest-of-Trials placement top-up marker): module 70 -> 71, total 104.
        -- Issue #1004 adds one NEW inline UI check while preserving module order:
        -- entry 33 -> 34, total 105.
        -- Issue #467 adds one NEW inline exact-price runtime check:
        -- entry 34 -> 35, total 106.
        -- Issue #52 registers the skull diagnostic's M.regression at its wiring
        -- site (issue52_skull_diag_installed): entry 35 -> 36, total 107.
        -- #1159 tab-panel owner: the six hold-Tab checks (#461, #1004, #556, #533,
        -- the native-diag arm, and #571) move WITH their feature, so the entry
        -- drops 35 -> 29 and the new owner holds exactly 6. The conserved total is
        -- unchanged; no check was lost, renamed, or duplicated.
        -- #1159 boon-grant owner: the two bot-boon checks (bot_boon_announce_wired,
        -- bot_boon_economy_installed) likewise move WITH their feature, so the
        -- entry drops 29 -> 27 and that owner holds exactly 2. Conserved total
        -- still unchanged.
        -- #1159 campaign-graph owner: the moved region carried NO _rt_register at
        -- all, so every count below is unchanged by that extraction. The two
        -- checks that guard its code (citadel145_probe_installed and
        -- citadel145_force_finale_god_fix) already lived in _ct_regression.lua and
        -- read the CT_CITADEL145_* globals plus the mod._ct_* exports at call
        -- time, so they keep working across the chunk boundary untouched.
        H.equal(count_plain(regression, "_rt_register("), 71)
        -- The tier-by-rarity check moved with the only helper state it consumes.
        H.equal(count_plain(entry, "_rt_register("), 27)
        H.equal(count_plain(tab_panel, "_rt_register("), 6)
        H.equal(count_plain(boon_grant, "_rt_register("), 2)
        H.equal(count_plain(campaign_graph, "_rt_register("), 0)
        -- #1159 altar-reuse owner: like the campaign-graph slice, the moved region
        -- carried NO _rt_register at all, so every count here is unchanged by that
        -- extraction. The checks that guard its code all read globals or mod._ct_*
        -- fields at CALL time, so they keep working across the new chunk boundary
        -- untouched, and each stays where it already lived:
        --   _ct_regression.lua  reliquary_reroll_message_hook (CT_RELIQUARY_REROLL_*,
        --                       both now defined by the owner)
        --   _ct_regression.lua  upgrade_altar_rarity_decouple (its marker global is
        --                       declared at entry ~line 743, ABOVE the moved region,
        --                       so it did not move)
        --   _ct_regression.lua  altar_reuse_hook_on_open_chest (the open_chest write
        --                       seam, which belongs to _ct_bot_weapon_chest_owner)
        --   entry               boon_altar_no_repeat (reads the taken-boon table the
        --                       owner now initialises at load time)
        H.equal(count_plain(altar_reuse, "_rt_register("), 0)
        -- #1159 chest-revive owner: same story again. The moved region carried
        -- NO _rt_register, and the one check that guards it -
        -- issue299_chest_revive_team_teleport_ordered - deliberately STAYS in
        -- the entry. It reads mod._ct_chest_revive_policy, mod._ct299_arm,
        -- mod._ct299_process, mod._ct_chest_teleport_tick and
        -- mod._ct_pending_team_teleport off `mod` at CALL time, so leaving it
        -- put keeps /ct_regression_test's output order byte-identical AND turns
        -- it into a live boundary assertion: if the owner ever stops publishing
        -- one of those five fields, an entry-side check fails.
        H.equal(count_plain(chest_revive, "_rt_register("), 0)
        H.equal(count_plain(entry, '_rt_register("issue299_chest_revive_team_teleport_ordered"'), 1)
        -- #1159 boon-offer view owner: same story once more. The moved region
        -- carried NO _rt_register, and boon_offer_scrollbar_wired - the one
        -- check that guards it - already lived in _ct_regression.lua and asserts
        -- mod._ct_boon_scroll_setup off `mod` at CALL time, so it keeps working
        -- across the new chunk boundary and stays a live boundary assertion.
        H.equal(count_plain(boon_offer_view, "_rt_register("), 0)
        H.equal(count_plain(regression, '_rt_register("boon_offer_scrollbar_wired"'), 1)
        -- #1159 pickup-population owner: same story once more. The moved region
        -- carried NO _rt_register, so every count above is unchanged by it. The
        -- two checks that guard its code stay in _ct_regression.lua and keep
        -- working across the new chunk boundary because neither reads anything
        -- the move relocated: pickup_dump_helpers_forward_declared asserts the
        -- entry's two forward-declared dump slots (still entry locals, now ALSO
        -- reached by the owner through late-binding ctx wrappers), and
        -- diag_132_134_136_present resolves mod._ct_tally_cursed_count off `mod`
        -- at CALL time - which the owner still publishes. That makes both live
        -- boundary assertions for this slice.
        H.equal(count_plain(pickup_population, "_rt_register("), 0)
        H.equal(count_plain(regression, '_rt_register("pickup_dump_helpers_forward_declared"'), 1)
        H.equal(count_plain(regression, '_rt_register("diag_132_134_136_present"'), 1)
        H.truthy(regression:find("mod._ct_tally_cursed_count", 1, true),
            "the #132 cross-check must keep reading the census off mod at call time")
        H.equal(count_plain(weapon_traits, "_rt_register("), 1)
        H.equal(count_plain(bot_weapon_chest,
            'mod:hook("DeusChestExtension", "open_chest"'), 1)
        -- The shared _RT_CHECKS registrar stays defined and exposed in the entry;
        -- the module registers through the exposed handle, never a second registry.
        H.truthy(entry:find("mod._ct_rt_register = _rt_register", 1, true))
        H.truthy(regression:find("local _rt_register = mod._ct_rt_register", 1, true))
        -- Same registrar seam for the #1159 tab-panel owner: it must bind the
        -- exposed handle, never build a second _RT_CHECKS list.
        H.truthy(tab_panel:find("local _rt_register = mod._ct_rt_register", 1, true))
        H.equal(count_plain(tab_panel, "local _RT_CHECKS"), 0)
        -- Same registrar seam for the #1159 boon-grant owner.
        H.truthy(boon_grant:find("local _rt_register = mod._ct_rt_register", 1, true))
        H.equal(count_plain(boon_grant, "local _RT_CHECKS"), 0)
    end)

    H.test("CT #252 owns the approved short reroll prompt once", function()
        -- #1159: the prompt moved to the altar-reuse owner WITH the hook that
        -- paints it. The gate follows the code - same needles, new file - plus an
        -- entry-side absence assertion so a stray second definition in the entry
        -- (which would shadow nothing but drift silently) fails the suite.
        H.equal(count_plain(altar_reuse,
            'CT_RELIQUARY_REROLL_PROMPT = "Reroll this weapon?"'), 1)
        H.equal(count_plain(entry, "CT_RELIQUARY_REROLL_PROMPT"), 0)
        H.equal(count_plain(altar_reuse,
            "Re-rolls this weapon's traits and properties"), 0)
        H.equal(count_plain(entry,
            "Re-rolls this weapon's traits and properties"), 0)
        H.equal(count_plain(altar_reuse,
            "reward_info_text = CT_RELIQUARY_REROLL_PROMPT"), 1)
        -- _ct_regression.lua reads both globals at CALL time, so the runtime check
        -- keeps working across the new chunk boundary.
        H.truthy(regression:find(
            'CT_RELIQUARY_REROLL_PROMPT ~= "Reroll this weapon?"', 1, true))
    end)

    H.test("ct_dev extracted checks live only in the module; inline check only in entry", function()
        -- Representative moved checks: absent from the entry, present once in the module.
        H.equal(count_plain(entry, '_rt_register("no_roamers_strip_arity_356"'), 0)
        H.equal(count_plain(regression, '_rt_register("no_roamers_strip_arity_356"'), 1)
        H.equal(count_plain(entry, '_rt_register("chunk_sends_paced_not_bursted"'), 0)
        H.equal(count_plain(regression, '_rt_register("chunk_sends_paced_not_bursted"'), 1)
        -- #1159 boon-grant owner: the two bot-boon checks live ONLY there now.
        H.equal(count_plain(entry, '_rt_register("bot_boon_announce_wired"'), 0)
        H.equal(count_plain(boon_grant, '_rt_register("bot_boon_announce_wired"'), 1)
        H.equal(count_plain(entry, '_rt_register("bot_boon_economy_installed"'), 0)
        H.equal(count_plain(boon_grant, '_rt_register("bot_boon_economy_installed"'), 1)
        -- The one check that reads the mutable `_starting_coins_applied_for_run`
        -- upvalue deliberately STAYS inline in the entry (moving it would capture a
        -- stale nil - the dropped-upvalue burn class), and its upvalue stays a
        -- file-local in the entry.
        H.equal(count_plain(entry, '_rt_register("starting_coins_value_matches_setting"'), 1)
        H.equal(count_plain(regression, '_rt_register("starting_coins_value_matches_setting"'), 0)
        H.truthy(entry:find("local _starting_coins_applied_for_run", 1, true))
    end)

    H.test("ct_dev lifecycle callbacks remain single-owner in the entry", function()
        for _, cb in ipairs({
            "mod.on_setting_changed = function",
            "mod.on_disabled = function",
        }) do
            H.equal(count_plain(entry, "\n" .. cb), 1, cb .. " entry owner")
            H.equal(count_plain(regression, "\n" .. cb), 0, cb .. " must not appear in the module")
        end
    end)

    H.test("ct_dev regression module is a pure ctx-keyed installer", function()
        -- return function(mod, ctx) contract with the ctx-wired seam header - the
        -- only non-verbatim part of the extraction.
        H.truthy(regression:find("return function(mod, ctx)", 1, true))
        H.truthy(regression:find("local _dbg = ctx.dbg", 1, true))
        H.truthy(regression:find("local MOD_VERSION = ctx.mod_version", 1, true))
        H.truthy(regression:find("local _ct_mutex = ctx.mutex", 1, true))
        -- No chat commands were folded into the check suite (commands stay in the
        -- entry / diagnostics surfaces).
        H.equal(count_plain(regression, "mod:command"), 0)
    end)
end
