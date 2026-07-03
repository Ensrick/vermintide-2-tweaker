local mod = get_mod("gt")

-- _gt_misc_features.lua — three small self-contained features:
--   (1) Adventure "save a consumable" trait odds (load-time data mutation; no hook)
--   (2) Choose Grail Knight Quests (PassiveAbilityQuestingKnight._generate_quest_pool)
--   (3) Ready Up! (VoteManager.rpc_client_complete_vote + host countdown shortcut)
--
-- Each feature is independent (no shared state) and each hook is a singleton —
-- verified disjoint from the rest of the mod. Dispatch wiring (no behavior
-- change after extraction):
--   * mod._gt_apply_adv_save_traits()  — already the public name; the main-file
--     on_setting_changed branch (gt_adventure_save_trait_chance) resolves it at
--     call time. Also applied once at module load.
--   * mod.gt_ready_up_now()            — host shortcut; chat command + keybind
--     (data file function_name) resolve it at call time.
-- The Grail-Knight /gt_regression_test check (gk_quest_dropdowns_dont_share_options)
-- stays in the main file — it inspects the DATA file, not a moved function.
--
-- Extracted from general_tweaker.lua (v0.2.133-dev, "refactor: extract
-- single-hook self-contained features to modules — no behavior change").
-- Owned by: general_tweaker.lua entry point. Consumed via: mod:dofile
-- (runs after the main chunk, so any mod._* fields are already set).

-- ============================================================
-- Adventure "save a consumable" trait odds (moved from ct 2026-06-18)
-- ============================================================
-- Home Brewer / Healers Touch / Grenadier are Adventure charm traits with a
-- chance to NOT consume the potion / healing item / grenade on use. Vanilla is
-- 25% each (WeaponTraits.buff_templates.{trait_ring_not_consume_potion,
-- trait_necklace_not_consume_healing, trait_trinket_not_consume_grenade}
-- .buffs[1].proc_chance = 0.25; weapon_traits.lua:69/84/104). The proc gate reads
-- buffs[1].proc_chance at add_buff time (buff_extension.lua:642). Absolute load-
-- time data mutation (also mirrored into the global BuffTemplates defensively);
-- each peer applies its own value to its own data, so no host-sync is needed.
-- Adventure-only — CW boons live in DeusPowerUpBuffTemplates and are untouched.
do
    local ADV_SAVE_TRAITS = {
        "trait_ring_not_consume_potion",      -- Home Brewer
        "trait_necklace_not_consume_healing", -- Healers Touch
        "trait_trinket_not_consume_grenade",  -- Grenadier
    }

    local function _adv_save_entries()
        local out = {}
        local wt = rawget(_G, "WeaponTraits")
        local bt = rawget(_G, "BuffTemplates")
        for _, key in ipairs(ADV_SAVE_TRAITS) do
            local wt_t = wt and wt.buff_templates and wt.buff_templates[key]
            local wt_buff = wt_t and wt_t.buffs and wt_t.buffs[1]
            if wt_buff then out[#out + 1] = wt_buff end
            local bt_t = bt and bt[key]
            local bt_buff = bt_t and bt_t.buffs and bt_t.buffs[1]
            if bt_buff then out[#out + 1] = bt_buff end
        end
        return out
    end

    -- Exposed on `mod` so on_setting_changed (in the main file) can re-apply it
    -- -- the table-field reference resolves at call time.
    mod._gt_apply_adv_save_traits = function()
        local pct = mod:get("gt_adventure_save_trait_chance")
        if type(pct) ~= "number" then pct = 25 end
        local target = math.max(1, math.min(75, pct)) / 100  -- absolute proc chance
        local entries = _adv_save_entries()
        if #entries == 0 then
            mod:info("[gt:adv-save-traits] WeaponTraits not loaded yet; will retry on setting change")
            return
        end
        for _, b in ipairs(entries) do
            b.proc_chance = target
        end
        mod:debug("[gt:adv-save-traits] set %d trait proc_chance(s) to %.2f (pct=%d)", #entries, target, pct)
    end

    -- WeaponTraits is a boot-time global; apply now.
    mod._gt_apply_adv_save_traits()
end

-- ============================================================
-- Choose Grail Knight Quests
-- ============================================================
-- Override `PassiveAbilityQuestingKnight._generate_quest_pool` to return a
-- list whose FIRST THREE entries are the user's chosen quests. Vanilla's
-- caller (_start_quest_from_pool) consumes the first N items, so by
-- biasing the front of the pool we deterministically dictate which quests
-- the player gets, while leaving the rest of the pool intact for the
-- `markus_questing_knight_passive_additional_quest` talent (4th quest in
-- CW) and any future quest-pulling code that walks further into the list.
--
-- Setting id prefix `gt_gk_` so we don't collide with the standalone
-- ChooseGrailKnightQuests mod's setting names (quest1/quest2/quest3).

local function _gt_gk_find_in_pool(pool, reward, used)
    for i, quest in ipairs(pool) do
        if quest.reward == reward and not used[i] then
            return i
        end
    end
    return nil
end

if PassiveAbilityQuestingKnight then
    mod:hook(PassiveAbilityQuestingKnight, "_generate_quest_pool", function(func, self, ...)
        local pool = func(self, ...)
        if not mod:get("gt_gk_quests_enabled") then
            return pool
        end
        local selections = {
            mod:get("gt_gk_quest1") or "random",
            mod:get("gt_gk_quest2") or "random",
            mod:get("gt_gk_quest3") or "random",
        }
        local used = {}
        local chosen = {}
        for _, sel in ipairs(selections) do
            if sel and sel ~= "random" then
                local idx = _gt_gk_find_in_pool(pool, sel, used)
                if idx then
                    used[idx] = true
                    chosen[#chosen + 1] = pool[idx]
                end
            end
        end
        -- Append the rest of the (still-shuffled) pool after the user's
        -- selections so `markus_questing_knight_passive_additional_quest`
        -- and any other code that reads beyond index 3 still finds quests.
        for i, quest in ipairs(pool) do
            if not used[i] then
                chosen[#chosen + 1] = quest
            end
        end
        return chosen
    end)
end

-- ============================================================
-- Ready Up! (skip Bridge of Shadows countdown)
-- ============================================================
-- Two paths:
--   1. `mod.gt_ready_up_now` — host-callable shortcut (chat + keybind) that
--      jumps straight past the Bridge of Shadows countdown. Maps to
--      `Managers.matchmaking:countdown_completed()`, the same function the
--      countdown UI fires when it reaches zero.
--   2. `gt_auto_ready_on_vote_pass` — when on, hook
--      VoteManager.rpc_client_complete_vote so that any vote whose
--      vote_result == 1 (i.e. accepted) immediately triggers
--      countdown_completed() instead of waiting for the bridge animation.
--
-- All clients receive the rpc but only the server's call to
-- countdown_completed() has effect (the engine guards it server-side), so
-- gating on `Managers.player.is_server` keeps the echo line accurate even
-- though the underlying call is safe to invoke on clients.

mod.gt_ready_up_now = function()
    if not (Managers.matchmaking and Managers.matchmaking.countdown_completed) then
        mod:echo("Matchmaking manager not available (must be in the keep).")
        return
    end
    if not (Managers.player and Managers.player.is_server) then
        mod:echo("Only the host can ready up the lobby.")
        return
    end
    Managers.matchmaking:countdown_completed()
    mod:echo("Ready up — starting now.")
end

mod:command("readyup", "Skip the Bridge of Shadows countdown and start the game now (host-only)", function()
    mod.gt_ready_up_now()
end)

if VoteManager then
    mod:hook_safe(VoteManager, "rpc_client_complete_vote", function(self, channel_id, vote_result)
        if not mod:get("gt_auto_ready_on_vote_pass") then return end
        if vote_result ~= 1 then return end
        if not (Managers.player and Managers.player.is_server) then return end
        if not (Managers.matchmaking and Managers.matchmaking.countdown_completed) then return end
        Managers.matchmaking:countdown_completed()
    end)
end
