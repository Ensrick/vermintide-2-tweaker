-- ============================================================
-- Tweaker: Buffs (`bt`)
-- ============================================================
--
-- Shared registry mod. Other Tweaker mods (wt, ct, et) check this
-- mod's master toggle to decide whether their Big Rebalance sub-
-- toggles should apply. This file is the SINGLE source of truth
-- for the canonical 328-entry registration list — formerly
-- duplicated in three byte-identical files (one per consumer mod).
--
-- Architecture:
--   - When `bt_master_enable_br_registrations` is ON, this mod
--     populates BuffTemplates / TalentBuffTemplates / NetworkLookup
--     / DamageProfileTemplates / ExplosionTemplates /
--     StatBuffApplicationMethods with the canonical list.
--   - Registration is idempotent: every entry checks `if BT[name]
--     then continue`. Safe to invoke twice; safe across hot reload.
--   - Consumer mods read the toggle via `(get_mod("bt") or {}):get(
--     "bt_master_enable_br_registrations")` — if bt isn't installed
--     the call returns nil and consumer BR features silently no-op.
--   - Cross-peer determinism: all peers with bt installed register
--     the SAME alphabetical list in the SAME order. Peers without bt
--     register nothing. Either-or in a lobby is safe; mismatched
--     (one peer with bt, one without) leaves the rpc_add_buff index
--     space misaligned and risks crashes — same constraint as before
--     but now bound to a single mod install rather than three.

local mod = get_mod("bt")
local REG = require("scripts/mods/buff_tweaker/buff_tweaker_registrations")

local MOD_VERSION = "0.1.1-alpha"

mod:info("Tweaker: Buffs v%s loaded", MOD_VERSION)
mod:echo("Tweaker: Buffs v" .. MOD_VERSION)

local _br_applied = false

-- ============================================================
-- Stub helper — vanilla buff entries are tables with a `buffs`
-- array. We seed an empty one so consumer code that does
-- `BuffTemplates[name].buffs[1] = ...` doesn't crash on nil deref
-- if we register but the consumer's per-feature toggle hasn't
-- filled in the body yet.
-- ============================================================
local function _stub_template(name)
    return { buffs = {} }
end

-- ============================================================
-- Register the 272 BuffTemplates + TalentBuffTemplates entries.
-- Mirror talent entries into TalentBuffTemplates[hero][name] per
-- the `feedback_vt2_dormant_buff_template_dual_register` rule
-- (vanilla's boot-time merge has already run by the time we get
-- here, so we have to write both tables).
-- ============================================================
local function _register_buff_templates()
    local BT  = rawget(_G, "BuffTemplates")
    local TBT = rawget(_G, "TalentBuffTemplates")
    local NL  = rawget(_G, "NetworkLookup")
    if not BT or not NL or not NL.buff_templates then
        mod:warning("[BT] BuffTemplates / NetworkLookup not loaded — skipping registration")
        return false
    end
    -- CRITICAL: NetworkLookup tables get __index that ERRORS on missing keys
    -- (network_lookup.lua:2361). Read access via `t[key]` triggers the error;
    -- must use `rawget(t, key)` for existence checks. Same bug pattern caught
    -- in crt 2026-05-22.
    for _, entry in ipairs(REG.BR_BUFF_TEMPLATES) do
        local name = entry.name
        if rawget(BT, name) == nil then
            BT[name] = _stub_template(name)
        end
        if entry.hero and TBT then
            TBT[entry.hero] = TBT[entry.hero] or {}
            if rawget(TBT[entry.hero], name) == nil then
                TBT[entry.hero][name] = BT[name]
            end
        end
        if not rawget(NL.buff_templates, name) then
            local idx = #NL.buff_templates + 1
            NL.buff_templates[idx]  = name
            NL.buff_templates[name] = idx
        end
    end
    return true
end

-- ============================================================
-- Register the 37 NewDamageProfileTemplates entries (also
-- appended to NetworkLookup.damage_profiles, mirroring vanilla
-- boot-time loop).
-- ============================================================
local function _register_damage_profiles()
    local DPT = rawget(_G, "DamageProfileTemplates")
    local NL  = rawget(_G, "NetworkLookup")
    if not DPT or not NL or not NL.damage_profiles then return end
    for _, name in ipairs(REG.BR_DAMAGE_PROFILES) do
        if rawget(DPT, name) == nil then
            -- Vanilla expects a default_target with an attack_template
            -- to avoid fassert at damage_profile registration. Seed a
            -- benign one referencing a known-good template; consumer
            -- mods that actually use the profile will overlay it.
            DPT[name] = { default_target = { attack_template = "light_blunt_tank" } }
        end
        if not rawget(NL.damage_profiles, name) then
            local idx = #NL.damage_profiles + 1
            NL.damage_profiles[idx]  = name
            NL.damage_profiles[name] = idx
        end
    end
end

-- ============================================================
-- Register the 16 explosion templates. Per memory
-- `reference_vt2_custom_explosion_template`, mod-defined entries
-- need `.name` set and to be inserted into _G.ExplosionTemplates
-- (which is what we do here). Consumer mods overlay body fields.
-- ============================================================
local function _register_explosion_templates()
    local ET = rawget(_G, "ExplosionTemplates")
    if not ET then return end
    for _, name in ipairs(REG.BR_EXPLOSION_TEMPLATES) do
        if not ET[name] then
            ET[name] = { name = name }
        end
    end
end

-- ============================================================
-- Register the 3 StatBuffApplicationMethods as
-- "stacking_multiplier". Does NOT enter NetworkLookup but is
-- still part of the canonical name list so all peers register
-- the same methods.
-- ============================================================
local function _register_stat_buff_methods()
    local SBA = rawget(_G, "StatBuffApplicationMethods")
    if not SBA then return end
    -- The exact application-method semantics live in vanilla; we
    -- mirror the upstream pattern from
    -- experimental_talent_changes.lua line 1248 where each name
    -- was registered as a stacking_multiplier alias.
    local stacking_multiplier_method = SBA.stacking_multiplier
    if not stacking_multiplier_method then return end
    for _, name in ipairs(REG.BR_STAT_BUFF_METHODS) do
        if not SBA[name] then
            SBA[name] = stacking_multiplier_method
        end
    end
end

-- ============================================================
-- Master apply — idempotent, callable from on_setting_changed.
-- Once applied, _br_applied is sticky for the session (we don't
-- unregister; per `feedback_vt2_gated_registration_diverges`,
-- once names are in NetworkLookup other peers may already have
-- bound RPC indices to them). Turning the master off mid-session
-- just leaves the names registered as inert stubs; consumer
-- per-feature toggles still gate on the live setting value.
-- ============================================================
local function _apply_master()
    if _br_applied then return end
    if not mod:get("bt_master_enable_br_registrations") then return end
    if not _register_buff_templates() then return end
    _register_damage_profiles()
    _register_explosion_templates()
    _register_stat_buff_methods()
    _br_applied = true
    mod:info("[BT] master registrations applied: %d buff templates, %d damage profiles, %d explosion templates, %d statbuff methods",
        #REG.BR_BUFF_TEMPLATES, #REG.BR_DAMAGE_PROFILES,
        #REG.BR_EXPLOSION_TEMPLATES, #REG.BR_STAT_BUFF_METHODS)
end

-- ============================================================
-- Public API for consumer mods
-- ============================================================
-- Callable from wt / ct / et:
--     local bt = get_mod("bt")
--     if bt and bt.is_br_active and bt:is_br_active() then ... end
-- Returns true ONLY when the master is on AND registrations have
-- actually been applied this session. False otherwise (or nil if
-- bt isn't installed — calling pattern is
-- `(get_mod("bt") or {}).is_br_active and get_mod("bt"):is_br_active()`).
mod.is_br_active = function(self)
    return _br_applied and (mod:get("bt_master_enable_br_registrations") == true)
end

-- ============================================================
-- Lifecycle wiring
-- ============================================================
mod.on_all_mods_loaded = function()
    _apply_master()
end

mod.on_game_state_changed = function(status, state_name)
    -- Some boot states (StateLoading / StateTitleScreen) populate
    -- NetworkLookup tables after VMF's mod-init pass, so try a
    -- late application here too. Idempotent.
    _apply_master()
end

mod.on_setting_changed = function(setting_id)
    if setting_id == "bt_master_enable_br_registrations" then
        if mod:get("bt_master_enable_br_registrations") then
            _apply_master()
            if not _br_applied then
                mod:echo("[BT] Cannot apply yet — vanilla tables not loaded. Restart the game with the master enabled to inject Big Rebalance registrations.")
            end
        else
            mod:echo("[BT] Master toggled OFF. Registrations remain present this session (cannot safely unregister); restart to fully clear.")
        end
    end
end
