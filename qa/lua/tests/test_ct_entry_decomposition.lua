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

    H.test("ct_dev entry stays below its frozen line baseline", function()
        local lines = 0
        for _ in entry:gmatch("[^\r\n]+") do lines = lines + 1 end
        -- 7675 = 2026-08-09 baseline after the #1159 boon-grant owner extraction
        -- (every seam that fires when a boon changes hands: the add_power_ups
        -- disable/parity gate and grant audit, the bot boon mirror, the
        -- consolidated _try_buy_power_up purchase hook, and the two DeusShopView
        -- price seams), atop the tab-panel, pickup-spawn, spawn-eligibility, Boss
        -- Grudge Marks, command, journey, preview-helper, weapon-trait-generation,
        -- and bot weapon-chest/reusable-altar owners. The ceiling only ratchets
        -- DOWN as more of the ct_dev entry decomposes into modules; it must never
        -- grow.
        H.truthy(lines <= 7675, "entry non-empty line count exceeded frozen 7675 baseline")
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
        H.equal(count_plain(regression, "_rt_register("), 71)
        -- The tier-by-rarity check moved with the only helper state it consumes.
        H.equal(count_plain(entry, "_rt_register("), 27)
        H.equal(count_plain(tab_panel, "_rt_register("), 6)
        H.equal(count_plain(boon_grant, "_rt_register("), 2)
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
        H.equal(count_plain(entry,
            'CT_RELIQUARY_REROLL_PROMPT = "Reroll this weapon?"'), 1)
        H.equal(count_plain(entry,
            "Re-rolls this weapon's traits and properties"), 0)
        H.equal(count_plain(entry,
            "reward_info_text = CT_RELIQUARY_REROLL_PROMPT"), 1)
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
