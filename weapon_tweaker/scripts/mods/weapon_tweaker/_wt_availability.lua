-- _wt_availability.lua -- cross-character weapon availability control surface.
--
-- Owns the can_wield management + career-ability action injection split out of
-- the god file in the v0.12.209-dev Phase 1 OOP decomposition:
--   * apply_weapon_unlocks             -- strip/add mod-managed careers on ItemMasterList[*].can_wield
--   * patch_career_actions_on_weapons  -- inject the unlocking career's ability action onto the weapon template
--   * clear_weapon_unlocks             -- on_disabled revert of the can_wield additions
--   * clear_career_action_injections   -- on_disabled revert of the injected ability actions
-- plus the one-shot `_strip_removed_unlocks` cleanup and the shared
-- `_career_action_injections` bookkeeping table. No behavior change from the
-- pre-split god file -- the entry aliases each exported function as a file-local
-- (`local apply_weapon_unlocks = mod._wt.apply_weapon_unlocks`, ...) so every
-- lifecycle-callback / backend-install call site is byte-identical.
--
-- Owned by: weapon_tweaker.lua entry point. Consumed via: mod:dofile (after
-- wt_unlock_data.lua populates mod._wt.weapon_unlock_map / .cwv_managed, and
-- before the lifecycle callbacks that call these functions are defined).
-- Shared state: reads mod._wt.weapon_unlock_map; exports
-- mod._wt.apply_weapon_unlocks / .patch_career_actions_on_weapons /
-- .clear_weapon_unlocks / .clear_career_action_injections. `feature_enabled`
-- stays in the entry (the anim funnel reads it on a hot path).

local mod = get_mod("wt")
local WT = mod._wt
local weapon_unlock_map = WT.weapon_unlock_map
local _cwv_conditional   = WT.cwv_conditional_managed
local _cwv_ownership     = mod:dofile("scripts/mods/weapon_tweaker/_wt_cwv_ownership")
local _cwv_variant_catalog = mod:dofile("scripts/mods/weapon_tweaker/wt_cwv_variant_catalog")
local _cwv_availability_policy = mod:dofile("scripts/mods/weapon_tweaker/_wt_cwv_availability_policy")
local _career_weapon_actions = mod:dofile(
    "scripts/mods/weapon_tweaker/_lib_career_weapon_actions")
local _career_action_owner = "weapon_tweaker:" .. tostring(mod)
WT.cwv_variant_catalog = _cwv_variant_catalog
WT.cwv_ownership         = _cwv_ownership
WT.cwv_availability_policy = _cwv_availability_policy

local function _cwv_active()
    return _cwv_ownership.cwv_is_active(get_mod("character_weapon_variants"))
end

local function _cwv_replacement_ready(weapon_key)
    return _cwv_ownership.replacement_ready(ItemMasterList, weapon_key)
end

local function _get_setting(setting_id)
    return mod:get(setting_id)
end

-- #620: native Tuskgor Spear remains a WT-alone default-off Foot Knight port,
-- but CWV's ready Combat Style family authors that pair default-on. The hidden
-- seed runs once per profile, only after the positive live IML marker exists,
-- so late load/hot reload converges without repeatedly overriding a later user
-- choice. Existing explicit/saved values remain ordinary WT settings.
local function _seed_cwv_tuskgor_foot_knight_default()
    if not (_cwv_active() and ItemMasterList) then return false end
    local item = rawget(ItemMasterList, "es_2h_heavy_spear")
    local ready = item and item.cwv_combat_style_family == "spear"
        and item.cwv_combat_style_ready == true
    if not ready or mod:get("wt_cwv_tuskgor_fk_default_seeded") then return ready == true end
    mod:set("wt_cwv_tuskgor_fk_default_seeded", true, false)
    if mod:get("unlock_es_knight_es_2h_heavy_spear") ~= true then
        mod:set("unlock_es_knight_es_2h_heavy_spear", true, false)
    end
    mod:info("[wt:620] CWV Tuskgor Combat Style ready; seeded Foot Knight availability ON")
    return true
end
WT.seed_cwv_tuskgor_foot_knight_default = _seed_cwv_tuskgor_foot_knight_default

-- Pairs removed from `weapon_unlock_map`. Users who had the
-- corresponding `unlock_es_*_<weapon>` toggle = true before the removal will
-- have the career still in the weapon's `item.can_wield` list. The regular
-- strip-rebuild walk inside `apply_weapon_unlocks` only iterates pairs that
-- ARE in the map, so a removed pair would leak the can_wield entry forever.
-- This list keeps a one-shot cleanup invariant: every init pass strips the
-- removed careers from these weapons' can_wield, idempotently. Originally
-- Kruber-only in v0.12.57; generalized for #582 in v0.12.226-dev.
local _removed_pairs = {
    es_mercenary      = { "wh_hammer_shield", "dr_shield_hammer", "dr_dual_wield_axes" },
    es_huntsman       = { "wh_hammer_shield", "dr_shield_hammer", "dr_dual_wield_axes" },
    es_knight         = { "wh_hammer_shield", "dr_shield_hammer", "dr_dual_wield_axes" },
    es_questingknight = { "wh_hammer_shield", "dr_shield_hammer", "dr_dual_wield_axes" },
    -- #582/#594: these native Bardin items are not Saltzpyre ownership rows.
    -- Explicit tombstones clean hot-reloaded/persisted can_wield mutations
    -- from earlier WT versions even though the pairs no longer exist in map.
    wh_captain        = { "dr_dual_wield_axes", "dr_shield_hammer" },
    wh_bountyhunter   = { "dr_dual_wield_axes", "dr_shield_hammer" },
    wh_zealot         = { "dr_dual_wield_axes", "dr_shield_hammer" },
}

local function _strip_removed_unlocks()
    if not ItemMasterList then return end
    for career, weapons in pairs(_removed_pairs) do
        for _, weapon_key in ipairs(weapons) do
            -- Issue #8 (2026-05-23): defensive `rawget` — `weapon_key` here is
            -- from an internal literal table so a strict-metatable Crashify is
            -- unreachable today, but the convention is to never index
            -- ItemMasterList with a non-literal key. Cheap, future-proof.
            local item = rawget(ItemMasterList, weapon_key)
            if item and item.can_wield then
                for i = #item.can_wield, 1, -1 do
                    if item.can_wield[i] == career then
                        table.remove(item.can_wield, i)
                    end
                end
            end
        end
    end
end

local function _set_career(item, career, enabled)
    if not item then return end
    item.can_wield = item.can_wield or {}
    for i = #item.can_wield, 1, -1 do
        if item.can_wield[i] == career then table.remove(item.can_wield, i) end
    end
    if enabled then item.can_wield[#item.can_wield + 1] = career end
end

-- CWV registers owner definitions after VMF has built WT's menu. Enumerate
-- the live IML on every bounded availability reconciliation and only claim a
-- catalog row when CWV's positive marker is present.
local function _apply_cwv_variant_unlocks()
    if not ItemMasterList then return end
    local active = _cwv_active()
    for _, variant in ipairs(_cwv_variant_catalog) do
        local item = rawget(ItemMasterList, variant.key)
        if item and item.cwv_variant == true then
            if active then
                for _, career in ipairs(variant.careers) do
                    local enabled = _cwv_availability_policy.is_enabled(
                        _get_setting,
                        variant.key,
                        career)
                    _set_career(item, career, enabled)
                end
            else
                -- CWV owns its authored careers. WT removes only cross-receiver
                -- careers that this catalog explicitly adds, so disabling or
                -- hot-reloading CWV cannot leave its Empire Axe+Shield on Saltz.
                for _, career in ipairs(variant.conditional_careers or {}) do
                    _set_career(item, career, false)
                end
                for _, career in ipairs(variant.authored_careers or {}) do
                    _set_career(item, career, true)
                end
            end
        end
    end
end

-- CLARIFY: The strip-then-add pattern is required because this runs on
-- on_setting_changed too — toggling a checkbox off must REMOVE the career
-- from can_wield, not just leave it. Direct-modifying ItemMasterList is the
-- ONLY way (BackendUtils.can_wield_item is unhookable from split mods —
-- see DEVELOPMENT.md "Don't hook BackendUtils.can_wield_item").
local function apply_weapon_unlocks()
    if not ItemMasterList then return end

    _seed_cwv_tuskgor_foot_knight_default()

    -- Drop stale can_wield entries for pairs removed from `weapon_unlock_map`
    -- since the last release. Idempotent — runs every init + on_setting_changed.
    _strip_removed_unlocks()

    local has_cwv = _cwv_active()

    -- Strip all mod-managed careers from can_wield
    for career, weapons in pairs(weapon_unlock_map) do
        for _, weapon_key in ipairs(weapons) do
            local item = rawget(ItemMasterList, weapon_key)
            if item and item.can_wield then
                for i = #item.can_wield, 1, -1 do
                    if item.can_wield[i] == career then
                        table.remove(item.can_wield, i)
                    end
                end
            end
        end
    end

    -- Add back only enabled ones
    for career, weapons in pairs(weapon_unlock_map) do
        for _, weapon_key in ipairs(weapons) do
            local conditional_yield = _cwv_ownership.should_yield_native(
                career, weapon_key, has_cwv, _cwv_conditional,
                _cwv_replacement_ready(weapon_key))
            if not conditional_yield then
                if mod:get("unlock_" .. career .. "_" .. weapon_key) then
                    local item = rawget(ItemMasterList, weapon_key)
                    if item then
                        if not item.can_wield then item.can_wield = {} end
                        local already = false
                        for _, value in ipairs(item.can_wield) do
                            if value == career then already = true; break end
                        end
                        if not already then
                            item.can_wield[#item.can_wield + 1] = career
                        end
                    end
                end
            end
        end
    end
    _apply_cwv_variant_unlocks()
end

-- CLARIFY: tracks which (template, action_name) entries were injected by
-- patch_career_actions_on_weapons so subsequent calls (on setting change) can
-- back them out before re-applying. Without this, toggling settings would
-- accumulate stale ability-action entries on weapon templates.
local _career_action_injections = {}

local function _release_career_action_claims()
    for tmpl_key in pairs(_career_action_injections) do
        local tmpl = Weapons and Weapons[tmpl_key]
        if tmpl then
            _career_weapon_actions.release(tmpl, _career_action_owner)
        end
    end
    _career_action_injections = {}
end

local function _inject_career_actions(template, template_key, career_name, failures)
    local report = _career_weapon_actions.install(template, { career_name },
        CareerSettings, ActionTemplates, _career_action_owner)
    if (report.claimed or 0) > 0 then
        _career_action_injections[template_key] = true
    end
    for _, action_name in ipairs(report.missing_actions or {}) do
        failures[action_name] = true
    end
    for _, career in ipairs(report.missing_careers or {}) do
        failures["career:" .. tostring(career)] = true
    end
    for _, action_name in ipairs(report.conflicting_names or {}) do
        failures["conflict:" .. tostring(action_name)] = true
    end
end

-- CLARIFY: when a cross-career weapon is unlocked, that weapon's template
-- needs the unlocking career's ABILITY action (e.g. Ranger Veteran's smoke
-- bomb) so the ability still works while wielding the unlocked weapon.
-- Without this patch, activating the career ability on a cross-career weapon
-- silently does nothing because the action isn't on that template.
local function patch_career_actions_on_weapons()
    if not Weapons or not CareerSettings or not ActionTemplates or not ItemMasterList then return end

    _release_career_action_claims()
    local has_cwv = _cwv_active()
    local failures = {}

    for career, weapons in pairs(weapon_unlock_map) do
        for _, weapon_key in ipairs(weapons) do
            local yields_to_cwv = _cwv_ownership.should_yield_native(
                career, weapon_key, has_cwv, _cwv_conditional,
                _cwv_replacement_ready(weapon_key))
            if not yields_to_cwv and mod:get("unlock_" .. career .. "_" .. weapon_key) then
                local item = rawget(ItemMasterList, weapon_key)
                local tmpl_key = item and item.template
                local tmpl = tmpl_key and Weapons[tmpl_key]
                if tmpl and tmpl.actions then
                    _inject_career_actions(tmpl, tmpl_key, career, failures)
                end
            end
        end
    end

    -- Every enabled CWV career needs its career ability on the live variant
    -- template. The donor fallback may be off independently, and Infantry
    -- Spear also exposes default-off receivers that its authored template
    -- cannot know about without WT.
    if _cwv_active() then
        for _, variant in ipairs(_cwv_variant_catalog) do
            local item = rawget(ItemMasterList, variant.key)
            if item and item.cwv_variant == true then
                for _, career in ipairs(variant.careers or {}) do
                    if _cwv_availability_policy.is_enabled(_get_setting, variant.key, career) then
                        local tmpl = item.template and Weapons[item.template]
                        if tmpl and tmpl.actions then
                            _inject_career_actions(
                                tmpl, item.template, career, failures)
                        end
                    end
                end
            end
        end
    end
    if next(failures) then
        local names = {}
        for name in pairs(failures) do names[#names + 1] = name end
        table.sort(names)
        mod:error("[wt:career-actions] incomplete weapon ability integration: %s",
            table.concat(names, ","))
    end
end

-- Clean disable: strip every cross-career career name this mod added to ItemMasterList[*].can_wield
-- and every ability action it injected into Weapons[*].actions. Without this, disabling the mod
-- via VMF would leave cross-career unlocks active on every affected weapon until game restart.
-- The restore-and-mutate phases of apply_weapon_unlocks / patch_career_actions_on_weapons already
-- handle the strip step on every call, so we just clear the management state and re-call: every
-- mod:get("unlock_*") read returns nil/false post-disable, so the add-back phase contributes nothing.
local function clear_weapon_unlocks()
    if not ItemMasterList then return end
    for career, weapons in pairs(weapon_unlock_map) do
        for _, weapon_key in ipairs(weapons) do
            local item = rawget(ItemMasterList, weapon_key)
            if item and item.can_wield then
                for i = #item.can_wield, 1, -1 do
                    if item.can_wield[i] == career then
                        table.remove(item.can_wield, i)
                    end
                end
            end
        end
    end
    -- Remove WT-owned cross-receiver access to live CWV variants as well. The
    -- four authored Kruber careers remain CWV-owned and are not touched here.
    for _, variant in ipairs(_cwv_variant_catalog) do
        local item = rawget(ItemMasterList, variant.key)
        if item and item.cwv_variant == true then
            for _, career in ipairs(variant.conditional_careers or {}) do
                _set_career(item, career, false)
            end
            for _, career in ipairs(variant.authored_careers or {}) do
                _set_career(item, career, true)
            end
        end
    end
end

local function clear_career_action_injections()
    _release_career_action_claims()
end

WT.apply_weapon_unlocks            = apply_weapon_unlocks
WT.patch_career_actions_on_weapons = patch_career_actions_on_weapons
WT.clear_weapon_unlocks            = clear_weapon_unlocks
WT.clear_career_action_injections  = clear_career_action_injections
