local mod = get_mod("enemy_tweaker")

-- _et_boss_balance.lua — GitHub issue 450 "Boss Balance Toggles"
--
-- Per-boss curated balance toggles. Every toggle defaults OFF (vanilla); ON
-- applies the exact value the issue asks for. Pure LOAD-TIME / on-setting-change
-- DATA mutation of boot-time globals (Breeds max_health arrays, a breed's
-- armor_category, and the grey-seer warp-lightning ExplosionTemplates
-- power_level). NO mod:hook is registered here — same discipline as
-- _et_boss_tweaks.lua, so no duplicate-hook concern with the mod's 7 hooks.
--
-- Revert-safe: each mutated field snapshots its PRISTINE vanilla value exactly
-- once (into a private `_et_bb_*` key on the owning table) and every apply
-- recomputes from that snapshot. A toggle-off, or disabling the mod, restores
-- vanilla exactly (mod:get returns falsy when the mod is disabled).
--
-- Host authority: bosses are spawned by the host and boss HP is
-- server_controlled_health_bar = true, so health scaling and warp-lightning
-- (an AI attack, resolved host-side) are fully consistent with only the HOST
-- modded. The Nurgloth ARMOR change is the exception: a player's melee/ranged
-- damage vs armor is computed on the ATTACKER's machine, so a non-modded client
-- attacking Nurgloth predicts Berserker-armor numbers; the host still applies
-- its own resolution for its hits and for modded clients. For a fully uniform
-- fight everyone should run the mod (documented in the tooltip).
--
-- SCOPE (issue 450): this module ships the breed-STAT knobs the issue asks for.
-- The behavioral knobs in the same issue are deliberately NOT here — they need
-- runtime hooks / the Chaos Wastes grudge-mark buff system, tracked as issue 531.
-- The grudge-mark pair (Skarrik Cata+ Berserk = grudge-mark frenzy; Bödvarr Cata+
-- Crippling = grudge-mark crippling) now ships in `_et_boss_grudge.lua` (the #531
-- tranche-1 hook module). The Halescourge 50%-HP mid-fight monster spawn lives
-- in `_et_boss_behavior.lua`, which also composes Skarrik ranged resistance
-- into the existing damage owner and narrows Deathrattler's tracking. Citations
-- live in the mechanics documentation.
--
-- Owned by: enemy_tweaker.lua entry point (dofile'd after _et_lifecycle, which
-- re-applies via mod._et_apply_boss_balance on every setting change).

local ET = mod._et
local _et_probe   = ET.et_probe
local rt_register = ET.rt_register

-- ----------------------------------------------------------------------------
-- Per-boss config. Health mults are the issue's exact values; each max_health
-- key is used by exactly ONE breed (verified against the decompile), so
-- mutating Breeds[breed].max_health in place scales only that boss.
--   Halescourge chaos_exalted_sorcerer             -0.70  (30% less)
--   Skarrik     skaven_storm_vermin_warlord        x1.30  (30% more)
--   Bödvarr     chaos_exalted_champion_warcamp     x1.10  (10% more)
--   Rasknitt    skaven_grey_seer                   x0.80  (4/5x)
--   Nurgloth    chaos_exalted_sorcerer_drachenfels x0.75  (3/4x)
-- ----------------------------------------------------------------------------
-- `chaos_exalted_champion` is only a source-file/action-family stem; vanilla
-- registers no Breeds entry under it. War Camp's terror event spawns Bodvarr as
-- `chaos_exalted_champion_warcamp` (terror_events_warcamp.lua:285-305), while
-- Skittergate separately spawns `chaos_exalted_champion_norsca`
-- (terror_events_skittergate.lua:39-58). Keep this identity explicit so the
-- health toggle cannot silently retune the wrong exalted champion.
local BODVARR_BREED = "chaos_exalted_champion_warcamp"

local HEALTH = {
    { setting = "boss_bal_halescourge_health", breed = "chaos_exalted_sorcerer",             mult = 0.70, label = "Halescourge" },
    { setting = "boss_bal_skarrik_health",     breed = "skaven_storm_vermin_warlord",        mult = 1.30, label = "Skarrik" },
    { setting = "boss_bal_bodvarr_health",     breed = BODVARR_BREED,                         mult = 1.10, label = "Bodvarr" },
    { setting = "boss_bal_rasknitt_health",    breed = "skaven_grey_seer",                   mult = 0.80, label = "Rasknitt" },
    { setting = "boss_bal_nurgloth_health",    breed = "chaos_exalted_sorcerer_drachenfels", mult = 0.75, label = "Nurgloth" },
}

-- Armor categories (scripts/helpers/breed_utils.lua:5-10): 1 = Infantry,
-- 5 = Berserker. Nurgloth ships armor_category = 5.
local ARMOR_INFANTRY = 1

-- Mirror scripts/settings/breeds/breed_tweaks.lua networkify_health (clamp to
-- the networked range + round to the 0.25 grid) so scaled boss HP stays on the
-- same quantization vanilla ships. Health is sent over the wire; an off-grid
-- value would desync the server-controlled health bar.
local _floor, _clamp, _round = math.floor, math.clamp, math.round
local function _networkify_health(h)
    h = _clamp(h, 0, 8191.5)
    local decimal = h % 1
    return _floor(h) + _round(decimal * 4) * 0.25
end

-- ----------------------------------------------------------------------------
-- Field appliers — each snapshots pristine vanilla ONCE, then writes
-- (enabled ? scaled : vanilla). Return true when the target exists (so a
-- vanilla rename surfaces via the rt check rather than silently no-op'ing).
-- ----------------------------------------------------------------------------
local function _apply_health(breed_name, enabled, mult)
    local breeds = rawget(_G, "Breeds")
    local breed = breeds and breeds[breed_name]
    local arr = breed and breed.max_health
    if type(arr) ~= "table" then return false end
    local snap = breed._et_bb_vanilla_health
    if not snap then
        snap = {}
        for i = 1, #arr do snap[i] = arr[i] end
        breed._et_bb_vanilla_health = snap
    end
    local factor = (enabled and mult) or 1.0
    for i = 1, #snap do
        arr[i] = _networkify_health(snap[i] * factor)
    end
    return true
end

local function _apply_armor(breed_name, enabled, new_cat)
    local breeds = rawget(_G, "Breeds")
    local breed = breeds and breeds[breed_name]
    if not breed then return false end
    if breed._et_bb_vanilla_armor == nil then
        breed._et_bb_vanilla_armor = breed.armor_category
    end
    breed.armor_category = (enabled and new_cat) or breed._et_bb_vanilla_armor
    return true
end

local function _apply_explosion_power(template_name, enabled, mult)
    local templates = rawget(_G, "ExplosionTemplates")
    local expl = templates and templates[template_name] and templates[template_name].explosion
    if not expl or type(expl.power_level) ~= "number" then return false end
    if expl._et_bb_vanilla_power == nil then
        expl._et_bb_vanilla_power = expl.power_level
    end
    expl.power_level = enabled and (expl._et_bb_vanilla_power * mult) or expl._et_bb_vanilla_power
    return true
end

local function _apply_deathrattler_tracking(enabled)
    local actions = rawget(_G, "BreedActions")
    local boss = actions and actions[ET.BossBehaviorCore.DEATHRATTLER_BREED]
    local dual = boss and boss.dual_shoot_intro
    if not dual or type(dual.rotation_time) ~= "number" then return false end
    if dual._et_bb_vanilla_rotation_time == nil then
        dual._et_bb_vanilla_rotation_time = dual.rotation_time
    end
    dual.rotation_time = ET.BossBehaviorCore.deathrattler_rotation_time(
        dual._et_bb_vanilla_rotation_time, enabled)
    return true
end

-- ----------------------------------------------------------------------------
-- Apply all boss-balance toggles per current settings. Called at load and from
-- _et_lifecycle on_setting_changed / on_enabled / on_disabled.
-- ----------------------------------------------------------------------------
local function _apply_boss_balance()
    local active = {}

    for i = 1, #HEALTH do
        local e = HEALTH[i]
        local on = mod:get(e.setting) and true or false
        local ok = _apply_health(e.breed, on, e.mult)
        if ok and on then
            active[#active + 1] = string.format("%s hp x%.2f", e.label, e.mult)
        end
    end

    local light_on = mod:get("boss_bal_rasknitt_lightning") and true or false
    if _apply_explosion_power("grey_seer_warp_lightning_impact", light_on, 2.0) and light_on then
        active[#active + 1] = "Rasknitt warp-lightning x2"
    end

    local armor_on = mod:get("boss_bal_nurgloth_armor") and true or false
    if _apply_armor("chaos_exalted_sorcerer_drachenfels", armor_on, ARMOR_INFANTRY) and armor_on then
        active[#active + 1] = "Nurgloth armor->infantry"
    end

    local tracking_on = mod:get("boss_behavior_deathrattler_tracking") and true or false
    if _apply_deathrattler_tracking(tracking_on) and tracking_on then
        active[#active + 1] = "Deathrattler tracking x0.50"
    end

    -- [et:450] per-apply summary marker. Fires at boot and on every setting
    -- change; survives a mod-logging-OFF session (engine printf, rate-limited).
    -- This is the apply-time surface deliberately chosen over a per-spawn hook:
    -- all changes are boot-time data mutations (always active when toggled),
    -- and this module registers no hooks — so a summary of which bosses are
    -- modified + their effective values is both reliable and hook-free.
    if #active > 0 then
        _et_probe("boss_balance_450", "[et:450] active: %s", table.concat(active, ", "))
    else
        _et_probe("boss_balance_450", "[et:450] all toggles off (vanilla)")
    end
    return true
end

-- Expose for the on_setting_changed / on_enabled / on_disabled chain in
-- _et_lifecycle.lua (that module is dofile'd BEFORE this one, so it nil-guards
-- the reference — same pattern as mod._et_apply_fly_disable).
mod._et_apply_boss_balance = _apply_boss_balance

-- Live readback for /verify_boss_balance. This reports the values the engine
-- will consume from Breeds/ExplosionTemplates, not merely that the setter ran.
ET.boss_balance_live_rows = function()
    local rows = {}
    local breeds = rawget(_G, "Breeds") or {}
    for i = 1, #HEALTH do
        local cfg = HEALTH[i]
        local breed = breeds[cfg.breed]
        local live = breed and breed.max_health
        local vanilla = breed and breed._et_bb_vanilla_health
        local enabled = mod:get(cfg.setting) and true or false
        local pass = type(live) == "table" and type(vanilla) == "table"
        if pass then
            local factor = enabled and cfg.mult or 1
            for index = 1, #vanilla do
                if live[index] ~= _networkify_health(vanilla[index] * factor) then
                    pass = false
                    break
                end
            end
        end
        rows[#rows + 1] = {
            name = cfg.label .. " health",
            setting = cfg.setting,
            enabled = enabled,
            live = type(live) == "table" and table.concat(live, ",") or "missing",
            expected = enabled and string.format("vanilla x%.2f", cfg.mult) or "vanilla",
            pass = pass,
        }
    end

    local lightning = rawget(_G, "ExplosionTemplates")
    lightning = lightning and lightning.grey_seer_warp_lightning_impact
        and lightning.grey_seer_warp_lightning_impact.explosion
    local lightning_on = mod:get("boss_bal_rasknitt_lightning") and true or false
    local lightning_expected = lightning and lightning._et_bb_vanilla_power
        and lightning._et_bb_vanilla_power * (lightning_on and 2 or 1)
    rows[#rows + 1] = {
        name = "Rasknitt lightning",
        setting = "boss_bal_rasknitt_lightning",
        enabled = lightning_on,
        live = lightning and lightning.power_level or "missing",
        expected = lightning_expected or "snapshot missing",
        pass = lightning_expected ~= nil and lightning.power_level == lightning_expected,
    }

    local nurgloth = breeds.chaos_exalted_sorcerer_drachenfels
    local armor_on = mod:get("boss_bal_nurgloth_armor") and true or false
    local armor_expected = nurgloth and (armor_on and ARMOR_INFANTRY
        or nurgloth._et_bb_vanilla_armor)
    rows[#rows + 1] = {
        name = "Nurgloth armor",
        setting = "boss_bal_nurgloth_armor",
        enabled = armor_on,
        live = nurgloth and nurgloth.armor_category or "missing",
        expected = armor_expected or "snapshot missing",
        pass = armor_expected ~= nil and nurgloth.armor_category == armor_expected,
    }

    local actions = rawget(_G, "BreedActions")
    local deathrattler = actions and actions[ET.BossBehaviorCore.DEATHRATTLER_BREED]
    local dual = deathrattler and deathrattler.dual_shoot_intro
    local tracking_on = mod:get("boss_behavior_deathrattler_tracking") and true or false
    local tracking_expected = dual and dual._et_bb_vanilla_rotation_time
        and ET.BossBehaviorCore.deathrattler_rotation_time(
            dual._et_bb_vanilla_rotation_time, tracking_on)
    rows[#rows + 1] = {
        name = "Deathrattler tracking window",
        setting = "boss_behavior_deathrattler_tracking",
        enabled = tracking_on,
        live = dual and dual.rotation_time or "missing",
        expected = tracking_expected or "snapshot missing",
        pass = tracking_expected ~= nil and dual.rotation_time == tracking_expected,
    }
    return rows
end

-- ----------------------------------------------------------------------------
-- Regression checks (runtime-only, no io — issue 511).
-- ----------------------------------------------------------------------------
rt_register("boss_balance_targets_present", function()
    -- A vanilla rename of any boss breed / max_health / the warp-lightning
    -- template would make a toggle silently no-op. Assert every target resolves.
    local breeds = rawget(_G, "Breeds")
    if not breeds then return "Breeds global missing" end
    if HEALTH[3].breed ~= BODVARR_BREED then
        return "Bodvarr health target drifted from War Camp breed"
    end
    for i = 1, #HEALTH do
        local b = breeds[HEALTH[i].breed]
        if not b then return "missing boss breed: " .. HEALTH[i].breed end
        if type(b.max_health) ~= "table" then return "no max_health array: " .. HEALTH[i].breed end
    end
    local nurgloth = breeds.chaos_exalted_sorcerer_drachenfels
    if not nurgloth or type(nurgloth.armor_category) ~= "number" then
        return "Nurgloth armor_category missing"
    end
    local templates = rawget(_G, "ExplosionTemplates")
    local expl = templates and templates.grey_seer_warp_lightning_impact
        and templates.grey_seer_warp_lightning_impact.explosion
    if not expl or type(expl.power_level) ~= "number" then
        return "grey_seer_warp_lightning_impact.explosion.power_level missing"
    end
    local actions = rawget(_G, "BreedActions")
    local deathrattler = actions and actions[ET.BossBehaviorCore.DEATHRATTLER_BREED]
    if not (deathrattler and deathrattler.dual_shoot_intro
            and type(deathrattler.dual_shoot_intro.rotation_time) == "number") then
        return "Deathrattler dual-shoot rotation_time missing"
    end
end)

rt_register("boss_balance_revert_safe", function()
    -- Applier + expose contract present, and applying with a target does not
    -- raise. Does not assert values (settings are user state), only that the
    -- roundtrip is fault-free and the vanilla snapshot is captured.
    if type(mod._et_apply_boss_balance) ~= "function" then
        return "mod._et_apply_boss_balance not exposed"
    end
    local ok = pcall(_apply_boss_balance)
    if not ok then return "_apply_boss_balance raised" end
    local breeds = rawget(_G, "Breeds")
    local seer = breeds and breeds.skaven_grey_seer
    if seer and not seer._et_bb_vanilla_health then
        return "vanilla health snapshot not captured after apply"
    end
end)

-- Apply now — Breeds / ExplosionTemplates are boot-time globals, live-read by
-- the spawn / damage paths, so no per-spawn hook is needed.
_apply_boss_balance()
