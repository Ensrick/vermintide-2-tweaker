local mod = get_mod("wt_dev")

-- ============================================================================
-- Bretonnian Longsword & Shield damage buff toggle
-- ============================================================================
-- Toggle `wt_brett_sword_shield_buff` (default OFF). Applies and reverts LIVE via
-- `mod.wt_apply_brett_buff` (called from on_setting_changed + once at load) — no
-- restart. It swaps the weapon template's per-attack fields between the vanilla
-- values (captured once) and the buffed values; the cloned damage profiles are
-- built once and simply pointed-to / un-pointed. Diagnostic `[wt:brettsns]` lines
-- use raw printf (survive mod-logging-OFF) and log each attack's current
-- headshot/monster/berserker so the change can be checked.
--
-- SCOPE: the template `one_handed_sword_shield_template_2` is used ONLY by the
-- Bret sword & shield + its weapon skins, so this never touches other weapons.
-- Each attack's damage profile is CLONED into a private `wt_brettsns_` copy before
-- editing, so source profiles shared with falchions / wood-elf swords stay vanilla.
--
-- SPEC ("+10% base on all, then specifics on top"):
--   BASE every attack: +10% damage, +10% attack speed,
--                      headshot -> 2, monster -> 4, berserker -> 1.25 (set).
--   ON TOP:  heavy_attack_stab (heavy 3)          +20% damage
--            light_attack_right (light 2)         +10% faster
--            light_attack_stab_postpush (push fu) +20% damage
-- DATA MAP (verified): damage = power_distribution.attack; speed = anim_time_scale;
--   headshot = default_target/targets.boost_curve_coefficient_headshot;
--   monster = armor_modifier.attack[3]; berserker = armor_modifier.attack[5].
--   armor_modifier + default_target/targets/critical_strike are PowerLevelTemplates
--   string refs. Mechanism mirrors character_weapon_variants `_clone_damage_profile`.

local _printf = rawget(_G, "printf") or function() end

local TEMPLATE_KEY  = "one_handed_sword_shield_template_2"
local PREFIX        = "wt_brettsns_"
local BASE_DAMAGE   = 1.10
local BASE_SPEED    = 1.10
local HEAVY3_DMG    = 1.20
local LIGHT2_SPEED  = 1.10
local PUSHFU_DMG    = 1.20
local SET_HEADSHOT  = 2
local MON_IDX, SET_MONSTER   = 3, 4
local BRZ_IDX, SET_BERSERKER = 5, 1.25

local EXTRA_DMG   = { heavy_attack_stab = HEAVY3_DMG, light_attack_stab_postpush = PUSHFU_DMG }
local EXTRA_SPEED = { light_attack_right = LIGHT2_SPEED }

local function _clone_plt(name, tag, editor)
    if type(name) ~= "string" or not PowerLevelTemplates then return name end
    local src = PowerLevelTemplates[name]
    if type(src) ~= "table" then return name end
    local nk = PREFIX .. tag .. name
    if not PowerLevelTemplates[nk] then
        local c = table.clone(src, true)
        pcall(editor, c)
        PowerLevelTemplates[nk] = c
    end
    return nk
end

local function _edit_target(t, dmg_mult)
    if type(t) ~= "table" then return end
    if type(t.power_distribution) == "table" and t.power_distribution.attack then
        t.power_distribution.attack = t.power_distribution.attack * dmg_mult
    end
    if t.boost_curve_coefficient_headshot ~= nil then
        t.boost_curve_coefficient_headshot = SET_HEADSHOT
    end
end

local function _edit_armor_modifier(am)
    if type(am) == "table" and type(am.attack) == "table" then
        am.attack[MON_IDX] = SET_MONSTER
        am.attack[BRZ_IDX] = SET_BERSERKER
    end
end

-- read the SOURCE profile's current headshot / monster / berserker (for the log)
local function _read_before(profile_name)
    local p = DamageProfileTemplates and DamageProfileTemplates[profile_name]
    if type(p) ~= "table" then return "?", "?", "?" end
    local hs, mon, brz = "?", "?", "?"
    local dt = p.default_target
    if type(dt) == "string" then dt = PowerLevelTemplates and PowerLevelTemplates[dt] end
    if type(dt) == "table" and dt.boost_curve_coefficient_headshot ~= nil then hs = dt.boost_curve_coefficient_headshot end
    local am = p.armor_modifier
    if type(am) == "string" then am = PowerLevelTemplates and PowerLevelTemplates[am] end
    if type(am) == "table" and type(am.attack) == "table" then mon = am.attack[MON_IDX]; brz = am.attack[BRZ_IDX] end
    return hs, mon, brz
end

local function _buff_profile(profile_name, dmg_mult)
    if not DamageProfileTemplates then return profile_name end
    local source = DamageProfileTemplates[profile_name]
    if type(source) ~= "table" then
        _printf("[wt:brettsns] WARN missing damage profile %s", tostring(profile_name))
        return profile_name
    end
    local dtag = string.format("d%d_", math.floor(dmg_mult * 100 + 0.5))
    local new_name = PREFIX .. dtag .. profile_name
    -- issue 431: record the clone SOURCE as the wire-safe fallback for the
    -- send_rpc_attack_hit floor (_wt431_damage_profile_parity.lua). Written on
    -- both the cache-hit and fresh-build paths; `or {}` because this file
    -- loads before the parity module.
    mod._wt431_custom_profile_fallback = mod._wt431_custom_profile_fallback or {}
    mod._wt431_custom_profile_fallback[new_name] = profile_name
    if DamageProfileTemplates[new_name] then return new_name end
    local clone = table.clone(source, true)
    for _, field in ipairs({ "default_target", "critical_strike" }) do
        local v = clone[field]
        if type(v) == "string" then
            clone[field] = _clone_plt(v, dtag, function(c) _edit_target(c, dmg_mult) end)
        elseif type(v) == "table" then
            _edit_target(v, dmg_mult)
        end
    end
    local tv = clone.targets
    if type(tv) == "string" then
        clone.targets = _clone_plt(tv, dtag, function(arr)
            if type(arr) == "table" then for _, tgt in ipairs(arr) do _edit_target(tgt, dmg_mult) end end
        end)
    elseif type(tv) == "table" then
        for _, tgt in ipairs(tv) do _edit_target(tgt, dmg_mult) end
    end
    local av = clone.armor_modifier
    if type(av) == "string" then
        clone.armor_modifier = _clone_plt(av, "am_", _edit_armor_modifier)
    elseif type(av) == "table" then
        _edit_armor_modifier(av)
    end
    DamageProfileTemplates[new_name] = clone
    if NetworkLookup and NetworkLookup.damage_profiles and not rawget(NetworkLookup.damage_profiles, new_name) then
        local t = NetworkLookup.damage_profiles
        local idx = #t + 1
        rawset(t, idx, new_name); rawset(t, new_name, idx)
    end
    return new_name
end

-- ---- prepare (once): capture vanilla values + build buffed values ----------
local _prepared, _template, _originals, _buffed = false, nil, nil, nil

local function _prepare()
    if _prepared then return _template ~= nil end
    _prepared = true
    local W = rawget(_G, "Weapons")
    local template = W and W[TEMPLATE_KEY]
    if type(template) ~= "table" or type(template.actions) ~= "table" then
        _printf("[wt:brettsns] template '%s' not found — buff unavailable", TEMPLATE_KEY)
        return false
    end
    _template, _originals, _buffed = template, {}, {}
    for action_name, group in pairs(template.actions) do
        if type(group) == "table" then
            for sub_name, sub in pairs(group) do
                if type(sub) == "table" then
                    local key, o, b = action_name .. "/" .. sub_name, {}, {}
                    if sub.anim_time_scale then
                        o.anim_time_scale = sub.anim_time_scale
                        b.anim_time_scale = sub.anim_time_scale * (BASE_SPEED * (EXTRA_SPEED[sub_name] or 1))
                    end
                    if type(sub.damage_profile) == "string" then
                        o.damage_profile = sub.damage_profile
                        local dmg = BASE_DAMAGE * (EXTRA_DMG[sub_name] or 1)
                        local hs, mon, brz = _read_before(sub.damage_profile)
                        _printf("[wt:brettsns]   %s  profile=%s dmg x%.2f | current headshot=%s monster=%s berserker=%s",
                            key, sub.damage_profile, dmg, tostring(hs), tostring(mon), tostring(brz))
                        b.damage_profile = _buff_profile(sub.damage_profile, dmg)
                    end
                    if o.anim_time_scale or o.damage_profile then
                        _originals[key], _buffed[key] = o, b
                    end
                end
            end
        end
    end
    return true
end

local function _swap(use_buffed)
    if not _prepare() then return end
    local src = use_buffed and _buffed or _originals
    for action_name, group in pairs(_template.actions) do
        if type(group) == "table" then
            for sub_name, sub in pairs(group) do
                if type(sub) == "table" then
                    local v = src[action_name .. "/" .. sub_name]
                    if v then
                        if v.anim_time_scale then sub.anim_time_scale = v.anim_time_scale end
                        if v.damage_profile then sub.damage_profile = v.damage_profile end
                    end
                end
            end
        end
    end
end

-- runtime apply / revert (called from on_setting_changed, once at load, and
-- from the issue-431 peer-parity callbacks in _wt431_damage_profile_parity.lua)
function mod.wt_apply_brett_buff()
    -- issue 431: parity gate -- the buffed wt_brettsns_* profiles are only
    -- pointed-to while every other human peer is confirmed to run wt (a non-wt
    -- peer would fatal decoding our appended NetworkLookup index off
    -- rpc_attack_hit, BUG_CLASSES 31). Nil-guarded: before the beacon module
    -- loads (or if it failed) this reads false and the template stays vanilla
    -- (fail-safe). The anim_time_scale half of the buff rides along with the
    -- same gate -- the buff is advertised as one package, so it applies whole
    -- or not at all rather than shipping half its balance.
    local allowed = type(mod._wt431_profiles_allowed) == "function"
        and mod._wt431_profiles_allowed() == true
    local on = (mod:get("wt_brett_sword_shield_buff") and allowed) and true or false
    _swap(on)
    _printf("[wt:brettsns] %s (live, no restart)%s", on and "APPLIED" or "reverted",
        (mod:get("wt_brett_sword_shield_buff") and not allowed) and " -- toggle on but peer-parity unconfirmed, holding vanilla" or "")
end

mod.wt_apply_brett_buff()

return {}
