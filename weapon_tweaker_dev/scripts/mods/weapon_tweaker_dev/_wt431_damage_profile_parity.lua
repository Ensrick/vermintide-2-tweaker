-- _wt431_damage_profile_parity.lua -- issue 431: custom damage profiles must
-- never ride a vanilla RPC into a peer that does not run wt.
--
-- THE CRASH (BUG_CLASSES 31, same class as issue 423 / cwv): wt appends its
-- cloned damage profiles (wt_authentic_pistol, wt_priest_punch_buffed, the
-- wt_brettsns_* set) to NetworkLookup.damage_profiles. Every attack-hit send
-- funnels through WeaponSystem.send_rpc_attack_hit (weapon_system.lua:148):
-- on a client it puts damage_profile_id on the wire to the host
-- (weapon_system.lua:182, rpc_attack_hit); the host decodes it via
-- NetworkLookup.damage_profiles[damage_profile_id] (weapon_system.lua:243).
-- A host WITHOUT wt never appended our keys, so the decode hits the strict
-- __index metatable (network_lookup.lua:2360-2367) and hard-errors:
-- "[NetworkLookup.lua] Table damage_profiles does not contain key: ...".
--
-- THE FIX (issue 371 peer-parity framework; NOT silent substitution as a
-- feature, because substituting base profiles would change advertised balance):
--   1. PARITY GATE (feature level): the three custom-profile toggles only
--      REPOINT weapon actions at the cloned profiles while every other human
--      peer is positively confirmed to run wt (VMF network beacon,
--      _lib_peer_parity.lua). The moment an unconfirmed human peer is seen,
--      the actions are restored to their vanilla profile keys, and they come
--      back automatically once everyone has wt. Solo / bots-only lobbies have
--      no foreign peer to crash, so the gate is open there.
--   2. WIRE FLOOR (unconditional backstop, class-31 fix template): a hook on
--      WeaponSystem.send_rpc_attack_hit coerces any wt-custom damage_profile_id
--      back to its clone-SOURCE vanilla id before a client send whenever
--      parity is not positively confirmed. This catches leaks the gate cannot
--      (an action mid-swing across the parity flip, a latched profile id).
--      The floor takes NO user-toggle argument by construction -- no setting
--      can turn it off (memory reference_vt2_wire_safety_never_toggle_gated,
--      issues 278/371).
--   REGISTRATION into DamageProfileTemplates/NetworkLookup stays UNCONDITIONAL
--   at load (PROJECT_STANDARDS 9.3): all same-version wt peers must agree on
--   the appended indices; registration itself crashes nobody -- only an
--   appended index ON THE WIRE does.
--
-- Cross-file contract:
--   * mod._wt431_custom_profile_fallback  (map: custom profile key -> vanilla
--     clone-source key). Populated at each registration site
--     (weapon_tweaker.lua authentic-brace + priest-punch blocks,
--     _wt_brett_sword_shield_buff.lua _buff_profile). Belt-and-suspenders
--     `or {}` init at every writer because this module loads after them.
--   * mod._wt431_profiles_allowed() -> bool, defined HERE. The three apply
--     functions (mod.wt_apply_priest_punch_buff, mod.wt_apply_brett_buff,
--     mod._wt431_brace_repoint) read it; nil-guarded at every call site so
--     "beacon missing" fails safe to NOT-allowed.
--   * Loaded from weapon_tweaker.lua AFTER weapon_tweaker_backend.lua defined
--     mod.update -- _lib_peer_parity's install() WRAPS mod.update (preserving
--     it) and would capture nil earlier (the crt issue-425 ordering rule).
--
-- Owned by: weapon_tweaker.lua entry point. Consumed via: mod:dofile.

local mod = get_mod("wt_dev")

local _printf = rawget(_G, "printf") or function() end

-- ============================================================
-- Peer-parity beacon (COPIED single-source lib; master:
-- tools/shared_lib/_lib_peer_parity.lua -- edit the master, re-copy verbatim)
-- ============================================================
do
    local ok, factory = pcall(function()
        return mod:dofile("scripts/mods/weapon_tweaker_dev/_lib_peer_parity")
    end)
    if ok and type(factory) == "function" then
        local ok2, inst = pcall(factory, mod, {
            channel     = "wt_peer_parity_present",
            schema      = 1,
            mod_label   = "Weapon Tweaker",
            echo_prefix = "[wt]",
        })
        if ok2 and type(inst) == "table" then
            mod._wt_peer_parity = inst
            pcall(function() inst:install() end)
            pcall(_printf, "[wt:431] peer-parity beacon installed (channel=wt_peer_parity_present)")
        end
    end
    if not mod._wt_peer_parity then
        -- Fail-safe posture: no beacon -> _wt431_profiles_allowed stays undefined
        -- -> every gated call site reads false -> custom profiles never used.
        pcall(_printf, "[wt:431] WARN peer-parity beacon FAILED to install -- custom damage profiles stay inert (fail-safe)")
    end
end

-- true ONLY when the beacon has positively confirmed every other human peer
-- runs wt (settled state). Solo / no-other-humans counts as confirmed.
if mod._wt_peer_parity then
    mod._wt431_profiles_allowed = function()
        local pp = mod._wt_peer_parity
        if not pp then return false end
        local ok, state = pcall(function() return pp:applied_state() end)
        return ok and state == "enabled"
    end
end

-- ============================================================
-- Gated feature: re-run the three apply functions on every parity flip.
-- Each apply reads _wt431_profiles_allowed() itself, so enable and disable
-- share one body. Disable is instant (crash-safe direction); enable waits
-- the lib's settle window.
-- ============================================================
local function _wt431_reapply_profile_repoints()
    if type(mod.wt_apply_priest_punch_buff) == "function" then
        pcall(mod.wt_apply_priest_punch_buff)
    end
    if type(mod.wt_apply_brett_buff) == "function" then
        pcall(mod.wt_apply_brett_buff)
    end
    if type(mod._wt431_brace_repoint) == "function" then
        pcall(mod._wt431_brace_repoint)
    end
    -- #621: the 1H Axe cleave toggle points at private damage-profile clones
    -- only while every human peer has WT. Re-run the existing bounded balance
    -- transaction whenever that parity state changes; the other balance
    -- toggles are idempotent and remain local template edits.
    if type(mod._wt_apply_axe_balance) == "function" then
        pcall(mod._wt_apply_axe_balance, nil, false)
    end
end

if mod._wt_peer_parity then
    mod._wt_peer_parity:register_gated_feature("wt_custom_damage_profiles", {
        label      = "wt431_custom_damage_profiles_label",
        on_enable  = _wt431_reapply_profile_repoints,
        on_disable = _wt431_reapply_profile_repoints,
    })
end

-- ============================================================
-- Unconditional wire floor -- WeaponSystem.send_rpc_attack_hit
-- ============================================================
-- PURE name-level coercion (class-31 template: no toggle argument by
-- construction, so it is structurally ungateable). Exposed on the mod table
-- for /wt_regression_test.
mod._wt431_wire_safe_profile_name = function(profile_name, parity_confirmed)
    if parity_confirmed then return profile_name end
    local map = mod._wt431_custom_profile_fallback
    local fb = map and map[profile_name]
    if type(fb) == "string" then return fb end
    return profile_name
end

local _floor_logged = {}

-- id-level wrapper around the pure helper. Returns the id to put on the wire.
local function _wire_safe_profile_id(weapon_system, damage_profile_id)
    -- Host path never wires the id: weapon_system.lua:179-180 dispatches the
    -- local receiver directly, and the host (running wt) decodes fine.
    if weapon_system and weapon_system.is_server then return damage_profile_id end
    local parity_confirmed = type(mod._wt431_profiles_allowed) == "function"
        and mod._wt431_profiles_allowed() == true
    if parity_confirmed then return damage_profile_id end
    local NL = rawget(_G, "NetworkLookup")
    local lookup = NL and NL.damage_profiles
    if not lookup then return damage_profile_id end
    local name = rawget(lookup, damage_profile_id)
    if type(name) ~= "string" then return damage_profile_id end
    local safe_name = mod._wt431_wire_safe_profile_name(name, false)
    if safe_name == name then return damage_profile_id end
    local safe_id = rawget(lookup, safe_name)
    if not safe_id then return damage_profile_id end
    if not _floor_logged[name] then
        _floor_logged[name] = true
        pcall(_printf, "[wt:431] wire floor: coerced %s -> %s on rpc_attack_hit (unconfirmed peer present; parity gate should already have reverted the repoint)", name, safe_name)
    end
    return safe_id
end

-- Hook pre-flight (CLAUDE.md NON-NEGOTIABLE 8): grepped 2026-07-13 -- wt has
-- NO other hook on WeaponSystem (any method). This is the single registration.
-- Every named RPC param is forwarded positionally; the tail key/value varargs
-- ride `...` untouched (memory reference_vmf_hook_drops_skip_sync_rpc_loop).
mod:hook("WeaponSystem", "send_rpc_attack_hit", function(func, self, damage_source_id, attacker_unit_id, hit_unit_id, hit_zone_id, hit_position, attack_direction, damage_profile_id, ...)
    local ok, safe_id = pcall(_wire_safe_profile_id, self, damage_profile_id)
    if ok and safe_id ~= nil then
        damage_profile_id = safe_id
    end
    return func(self, damage_source_id, attacker_unit_id, hit_unit_id, hit_zone_id, hit_position, attack_direction, damage_profile_id, ...)
end)

mod._wt431_wire_floor_installed = true
mod._wt431_parity_gated = true

-- ============================================================
-- Regression checks (/wt_regression_test)
-- ============================================================
local WT = mod._wt
if WT and type(WT.rt_register) == "function" then
    WT.rt_register("wt_431_peer_parity_beacon_installed", function()
        local pp = mod._wt_peer_parity
        if type(pp) ~= "table" then return "mod._wt_peer_parity missing (beacon not created)" end
        if not pp:is_installed() then return "beacon not installed (network_register failed?)" end
        if pp:feature_count() < 1 then return "no gated feature registered on the beacon" end
        if pp._initial_applied ~= "disabled" or pp.FAILSAFE_POSTURE ~= "feature_inert_until_confirmed" then
            return "fail-safe posture changed (must init disabled / inert-until-confirmed)"
        end
        if mod._wt431_parity_gated ~= true then return "wiring marker _wt431_parity_gated not set" end
        if type(mod._wt431_profiles_allowed) ~= "function" then
            return "_wt431_profiles_allowed missing (apply fns would read nil -> permanently inert)"
        end
        -- Pure classifier sanity (fail-safe direction).
        local c = pp.__classify
        if type(c) ~= "function" then return "classifier missing" end
        if c({ p1 = true }, {}) ~= false then return "classifier: unacked peer must gate OFF" end
        if c({ p1 = true }, { p1 = true }) ~= true then return "classifier: all-acked must gate ON" end
        if c({}, {}) ~= true then return "classifier: solo must gate ON" end
    end)

    WT.rt_register("wt_431_wire_floor_ungated", function()
        if mod._wt431_wire_floor_installed ~= true then
            return "wire-floor marker not set (send_rpc_attack_hit floor missing)"
        end
        local map = mod._wt431_custom_profile_fallback
        if type(map) ~= "table" then return "fallback map missing (registration sites did not populate it)" end
        if map.wt_authentic_pistol ~= "shot_sniper" then
            return "wt_authentic_pistol fallback must be its clone source shot_sniper"
        end
        if map.wt_priest_punch_buffed ~= "light_blunt_smiter_stab" then
            return "wt_priest_punch_buffed fallback must be its clone source light_blunt_smiter_stab"
        end
        -- Every fallback must resolve to a real NetworkLookup id -- the floor
        -- substitutes ids, so a broken fallback would wire a different bad key.
        local NL = rawget(_G, "NetworkLookup")
        if not (NL and NL.damage_profiles) then return "skip: NetworkLookup not loaded" end
        for custom, fb in pairs(map) do
            if not rawget(NL.damage_profiles, fb) then
                return string.format("fallback %s (for %s) not in NetworkLookup.damage_profiles", tostring(fb), tostring(custom))
            end
        end
        -- Pure coercion helper: correct AND takes no toggle argument (class-31
        -- fix template -- the parity flag is its ONLY gate).
        local f = mod._wt431_wire_safe_profile_name
        if type(f) ~= "function" then return "_wt431_wire_safe_profile_name missing" end
        if f("wt_authentic_pistol", false) ~= "shot_sniper" then
            return "floor must coerce a custom name while parity is unconfirmed"
        end
        if f("wt_authentic_pistol", true) ~= "wt_authentic_pistol" then
            return "floor must pass a custom name through once parity is confirmed"
        end
        if f("shot_sniper", false) ~= "shot_sniper" then
            return "floor must never touch vanilla names"
        end
    end)
end

return {}
