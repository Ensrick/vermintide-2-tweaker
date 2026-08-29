-- Moonfire Bow pre-nerf AOE revert owner (#1159).
--
-- Extracted verbatim from the entry. The entry keeps a bare dofile at the
-- former execution position, so hook-registration order and the _rt_register
-- append order are unchanged. The #428 lookup-helper migration changes only
-- the registration primitive at that same file-scope position.
--
-- resource-safety: wt_535_moonfire_aoe_owner
-- The single native boundary here is the World.create_particles jitter cluster
-- in _wt_moonfire_on_hit. The move does not widen it: the effect
-- (fx/wpnfx_we_deus_01_impact) ships with the equipped Moonbow's own resource
-- package and the handler only runs off a live Moonfire projectile impact, so
-- the particle is resident on every peer that can reach the call. Offline
-- evidence: qa/lua/tests/test_wt_moonfire_aoe_owner.lua.

local mod = get_mod("wt_dev")
local _network_lookup = mod:dofile("scripts/mods/weapon_tweaker_dev/_lib_network_lookup")

-- Late-binding accessor. The entry's file-scope `_rt_register` local does not
-- cross the chunk boundary; `_wt_regression` publishes the same function on the
-- shared namespace and is dofile'd far above this module's load position, so
-- this reads the identical value the moved lines closed over.
local _rt_register = mod._wt.rt_register
-- ============================================================
-- Moonfire Bow pre-nerf AOE restoration
-- ============================================================
-- One toggle in weapon_overrides:
--   moonfire_aoe_revert  — pre-nerf AOE detonation + puffs (damage host-side)
-- The cosmetic-only puff (moonfire_cosmetic_puff) moved to cosmetics_tweaker
-- (Weapon & Item Appearance, cos_moonfire_cosmetic_puff) on 2026-06-29.
--
-- Implementation hooks the four impact paths on PlayerProjectileUnitExtension
-- (hit_enemy / hit_level_unit / hit_static_unit / hit_breakable_object) and
-- spawns the FX locally on every peer that runs the projectile. The full
-- revert routes through DamageUtils.create_explosion which gates damage on
-- is_server — VFX still plays on every peer, damage only applies host-side.
--
-- The shooter's item_name match (`we_deus_01*`) covers every skin/illusion
-- since item keys preserve the base prefix.

local _MOONFIRE_PUFF_FX = "fx/wpnfx_we_deus_01_impact"

-- Template must be registered in ExplosionTemplates AND carry a .name field.
-- DamageUtils.create_explosion forwards `explosion_template.name` to
-- AreaDamageSystem.add_aoe_damage_target, which later calls
-- ExplosionUtils.get_template(name) -> ExplosionTemplates[name]. The vanilla
-- auto-name loop at the end of explosion_templates.lua runs at engine boot
-- (before mods load), so we set .name explicitly here.
local _MOONFIRE_AOE_NAME = "wt_moonfire_aoe_revert"
local _MOONFIRE_FALLBACK_NAME = "machinegun_poison_arrow"
local _MOONFIRE_AOE_TEMPLATE = {
    name = _MOONFIRE_AOE_NAME,
    explosion = {
        damage_profile = "poison_aoe",
        effect_name = _MOONFIRE_PUFF_FX,
        sound_event_name = "arrow_hit_poison_cloud",
        no_prop_damage = true,
        no_friendly_fire = true,
        radius = 1.5,
        max_damage_radius = 0.75,
        use_attacker_power_level = true,
        attacker_power_level_offset = -0.5,
    },
}
if rawget(_G, "ExplosionTemplates") then
    ExplosionTemplates[_MOONFIRE_AOE_NAME] = _MOONFIRE_AOE_TEMPLATE
end

-- issue #535: register the AoE template into NetworkLookup.explosion_templates
-- UNCONDITIONALLY at load (PROJECT_STANDARDS 9.3, index determinism across wt
-- peers), mirroring the damage_profiles append idiom above (~:1891). The lookup
-- is frozen at engine boot with a strict __index that errors on any missing key
-- [src: scripts/network_lookup/network_lookup.lua build :1211 (create_lookup
-- {"n/a"}, ExplosionTemplates); strict __index :2360-2367]. Forward + reverse
-- append through the canonical shared helper. It proves the complete numeric
-- and string axes are dense and symmetric before trusting an existing pair or
-- choosing N+1, and rejects malformed state without mutation.
--
-- WIRE-PATH ANALYSIS (why this registration is belt-and-suspenders, NOT
-- load-bearing): the moonfire hook calls DamageUtils.create_explosion DIRECTLY
-- (below), never AreaDamageSystem.create_explosion. DamageUtils.create_explosion
-- never encodes via NetworkLookup.explosion_templates; its only AoE-network
-- touch is area_damage_system:add_aoe_damage_target [src: damage_utils.lua:1470],
-- which stores the name as a STRING in a host-only local ring buffer and
-- resolves it through ExplosionUtils.get_template -> ExplosionTemplates[name]
-- [src: area_damage_system.lua:280,331,347], never NetworkLookup. The ONLY
-- NetworkLookup.explosion_templates[name] encode in the explosion path is
-- AreaDamageSystem.create_explosion [src: area_damage_system.lua:162], which the
-- moonfire path never reaches. So this name never rides the wire: it cannot
-- strict-__index-fatal on encode (the wt shooter's machine) nor on decode (a
-- non-wt peer). Full trace in weapon_tweaker/ENGINE_SURFACE.md. Registration is
-- still done for index determinism + to kill the footgun should a future change
-- ever route moonfire through AreaDamageSystem.create_explosion.
local _moonfire_lookup_index
local _moonfire_lookup_reason
local _moonfire_lookup_shape_reason
local _moonfire_fallback_index
do
    local NL = rawget(_G, "NetworkLookup")
    local lookup
    if NL ~= nil and type(NL) ~= "table" then
        _moonfire_lookup_shape_reason = "NetworkLookup:" .. type(NL)
    elseif type(NL) == "table" then
        lookup = rawget(NL, "explosion_templates")
        if lookup ~= nil and type(lookup) ~= "table" then
            _moonfire_lookup_shape_reason =
                "NetworkLookup.explosion_templates:" .. type(lookup)
        end
    end
    local idx, inserted, reason = _network_lookup.register_named(
        NL,
        "explosion_templates",
        _MOONFIRE_AOE_NAME
    )
    _moonfire_lookup_index = idx
    _moonfire_lookup_reason = reason
    local fallback_index = type(lookup) == "table"
        and rawget(lookup, _MOONFIRE_FALLBACK_NAME)
    if idx
        and type(fallback_index) == "number"
        and fallback_index > 0
        and fallback_index % 1 == 0
        and rawget(lookup, fallback_index) == _MOONFIRE_FALLBACK_NAME then
        _moonfire_fallback_index = fallback_index
    end
    if inserted then
        pcall(printf, "[wt:535] registered %s into NetworkLookup.explosion_templates at index %d (wire-inert; see ENGINE_SURFACE.md)", _MOONFIRE_AOE_NAME, idx)
    elseif reason ~= "already_registered" then
        local seen = mod._wt428_moonfire_lookup_rejections
        if type(seen) ~= "table" then
            seen = {}
            mod._wt428_moonfire_lookup_rejections = seen
        end
        local reason_key = tostring(reason)
        if not rawget(seen, reason_key) then
            rawset(seen, reason_key, true)
            pcall(printf, "[wt:428] rejected NetworkLookup.explosion_templates registration for %s (%s); lookup left unchanged", _MOONFIRE_AOE_NAME, reason_key)
        end
    end
    -- Record the wire-safe vanilla fallback for the moonfire AoE. machinegun_poison_arrow
    -- is the closest vanilla explosion template: same gameplay shape - damage_profile
    -- "poison_aoe", sound "arrow_hit_poison_cloud", no_prop_damage, use_attacker_power_level
    -- [src: scripts/settings/explosion_templates.lua:6-15]. There is NO active
    -- sender-side floor hook, because moonfire has no NetworkLookup send path
    -- (analysis above) - this is the documented substitute a floor WOULD coerce
    -- to if a send path is ever added, and the /wt_regression_test check below
    -- asserts it resolves to a real vanilla index. Same map shape as the #431
    -- damage-profile fallback (mod._wt431_custom_profile_fallback).
    mod._wt535_explosion_template_fallback = mod._wt535_explosion_template_fallback or {}
    mod._wt535_explosion_template_fallback[_MOONFIRE_AOE_NAME] = _MOONFIRE_FALLBACK_NAME
end

-- issue #535 regression: the moonfire AoE template must be registered in BOTH
-- ExplosionTemplates (local resolution) and NetworkLookup.explosion_templates
-- (wire index determinism), and its recorded wire-safe fallback must resolve to
-- a real vanilla index.
_rt_register("wt_535_moonfire_explosion_registered", function()
    local tmpl = rawget(_G, "ExplosionTemplates")
    if not tmpl then return "skip: ExplosionTemplates not loaded (run in-mission)" end
    local entry = rawget(tmpl, _MOONFIRE_AOE_NAME)
    if type(entry) ~= "table" then return "wt_moonfire_aoe_revert missing from ExplosionTemplates" end
    if entry.name ~= _MOONFIRE_AOE_NAME then return "wt_moonfire_aoe_revert entry missing its .name field" end
    local NL = rawget(_G, "NetworkLookup")
    local lookup = type(NL) == "table" and rawget(NL, "explosion_templates")
    if _moonfire_lookup_shape_reason then
        return string.format(
            "wt_moonfire_aoe_revert NetworkLookup registration rejected (%s; %s)",
            tostring(_moonfire_lookup_reason),
            _moonfire_lookup_shape_reason
        )
    end
    if type(lookup) ~= "table" then
        if _moonfire_lookup_index then
            if lookup == nil then
                return "NetworkLookup.explosion_templates disappeared after registration"
            end
            return string.format(
                "NetworkLookup.explosion_templates became invalid after registration (%s)",
                type(lookup)
            )
        end
        return "skip: NetworkLookup.explosion_templates not loaded"
    end
    if not _moonfire_lookup_index then
        return string.format(
            "wt_moonfire_aoe_revert NetworkLookup registration rejected (%s)",
            tostring(_moonfire_lookup_reason)
        )
    end
    local idx = rawget(lookup, _MOONFIRE_AOE_NAME)
    if type(idx) ~= "number" then
        return "wt_moonfire_aoe_revert not in NetworkLookup.explosion_templates (an encode would strict-__index fatal)"
    end
    if idx ~= _moonfire_lookup_index then
        return "wt_moonfire_aoe_revert NetworkLookup index changed after registration"
    end
    if rawget(lookup, idx) ~= _MOONFIRE_AOE_NAME then
        return "NetworkLookup.explosion_templates reverse map broken (idx->name mismatch)"
    end
    local map = mod._wt535_explosion_template_fallback
    if type(map) ~= "table" then
        return "moonfire wire-safe fallback map missing or invalid"
    end
    local fb = rawget(map, _MOONFIRE_AOE_NAME)
    if fb ~= _MOONFIRE_FALLBACK_NAME then
        return string.format(
            "moonfire wire-safe fallback identity changed (expected %s, got %s)",
            _MOONFIRE_FALLBACK_NAME,
            tostring(fb)
        )
    end
    if not _moonfire_fallback_index then
        return string.format("wire-safe fallback %s had no valid round-trip at registration", tostring(fb))
    end
    local fallback_index = rawget(lookup, fb)
    if fallback_index ~= _moonfire_fallback_index then
        return string.format("wire-safe fallback %s index changed after registration", tostring(fb))
    end
    if rawget(lookup, fallback_index) ~= fb then
        return string.format("wire-safe fallback %s reverse map broken", tostring(fb))
    end
end)

local _moonfire_jitter_offsets = {
    Vector3Box(0.35, 0, 0.1),
    Vector3Box(-0.3, 0.2, 0.15),
    Vector3Box(0.05, -0.3, 0.2),
}

local function _is_moonfire_arrow(item_name)
    if not item_name then return false end
    return string.sub(item_name, 1, 10) == "we_deus_01"
end

local function _wt_moonfire_on_hit(self, hit_position)
    if not _is_moonfire_arrow(self.item_name) then return end
    -- moonfire_cosmetic_puff moved to cosmetics_tweaker (Weapon & Item Appearance,
    -- setting cos_moonfire_cosmetic_puff) on 2026-06-29 — wt keeps only the gameplay
    -- AOE revert. Cosmetics' puff hook skips when this revert is on (it already puffs).
    if not mod:get("moonfire_aoe_revert") then return end
    local world = self._world
    if not world or not hit_position then return end

    local rotation = Unit.alive(self._projectile_unit)
        and Unit.local_rotation(self._projectile_unit, 0)
        or Quaternion.identity()
    local owner_unit = self._owner_unit
    if not Unit.alive(owner_unit) then return end
    local is_husk = self._owner_player and not self._owner_player.local_player or false
    DamageUtils.create_explosion(
        world,
        owner_unit,
        hit_position,
        rotation,
        _MOONFIRE_AOE_TEMPLATE,
        self.scale or 1,
        self.item_name,
        self._is_server,
        is_husk,
        self._projectile_unit,
        self.power_level or 0,
        self._is_critical_strike or false,
        owner_unit
    )
    for i = 1, #_moonfire_jitter_offsets do
        local p = hit_position + _moonfire_jitter_offsets[i]:unbox()
        World.create_particles(world, _MOONFIRE_PUFF_FX, p, Quaternion.identity())
    end
end

-- Hook BOTH PlayerProjectileUnitExtension (shooter's own machine) and
-- PlayerProjectileHuskExtension (every other peer that sees the arrow). Both
-- carry the same fields _wt_moonfire_on_hit reads (item_name, _world,
-- _projectile_unit, _owner_unit, _owner_player, scale, power_level,
-- _is_critical_strike, _is_server). Without the husk hooks the puff only
-- spawns on the shooter's screen.
local _moonfire_hooked_classes = { "PlayerProjectileUnitExtension", "PlayerProjectileHuskExtension" }
local _moonfire_hooked_methods = { "hit_enemy", "hit_level_unit", "hit_non_level_unit" }
for _, class_name in ipairs(_moonfire_hooked_classes) do
    local cls = rawget(_G, class_name)
    if cls then
        for _, method_name in ipairs(_moonfire_hooked_methods) do
            if cls[method_name] then
                mod:hook_safe(cls, method_name, function(self, impact_data, hit_unit, hit_position)
                    _wt_moonfire_on_hit(self, hit_position)
                end)
            end
        end
    end
end
