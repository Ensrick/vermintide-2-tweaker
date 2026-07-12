local mod = get_mod("enemy_tweaker")

-- _et_banner.lua — beastman banner toggles (v0.7.2-dev)
--
-- Three toggles for the beastmen standard-bearer's planted banner: bearer
-- staggerable during placement (BreedActions ignore_staggers flip), banner
-- breakable by ranged (BeastmenStandardHealthExtension.add_damage widened
-- accept set), and no camera jerk on placement (ExplosionTemplates
-- player-catapult nulling). Each snapshots vanilla at first apply and
-- restores on toggle-off / mod-disable.
--
-- Owned by: enemy_tweaker.lua entry point. Consumed via mod._et exports:
-- apply_banner_bearer_stagger_toggle, apply_banner_camera_jerk_toggle
-- (the lifecycle module re-applies both; camera takes force_off=true from
-- on_disabled).

local ET = mod._et
local rt_register = ET.rt_register
local _spawn_dbg  = ET.spawn_dbg
local _safe       = ET.safe
local _hook_wrap  = ET.hook_wrap

-- (1) Bearer staggerable during placement: vanilla
--     BreedActions.beastmen_standard_bearer.place_standard_stagger_immune
--     has ignore_staggers = { true, true, true, true, true, true } — bearer
--     can't be interrupted out of the place animation. We backup the table
--     at first apply and flip all six entries to false when our setting is
--     on; restore on disable. The BT picks between place_standard (already
--     staggerable) and place_standard_stagger_immune based on its own
--     considerations, so we mutate the immune variant in place so EITHER
--     selection respects the toggle.
--
-- (2) Banner breakable by ranged: vanilla
--     BeastmenStandardHealthExtension.add_damage allow-set is melee
--     light/heavy + a small explosive/torch whitelist (see vanilla
--     beastmen_standard_health_extension.lua:25-44). We hook the function
--     and, when the setting is on, also accept attack_type values
--     "projectile", "instant_projectile", "heavy_instant_projectile"
--     (canonical NetworkLookup.buff_attack_types strings — every ranged
--     weapon in the game uses one of these).

local _banner_bearer_ignore_staggers_original  -- backup of the 6-entry vanilla table

local function _apply_banner_bearer_stagger_toggle()
    local BA = rawget(_G, "BreedActions")
    if type(BA) ~= "table" then return end
    local sb = BA.beastmen_standard_bearer
    if type(sb) ~= "table" then return end
    local action = sb.place_standard_stagger_immune
    if type(action) ~= "table" then return end
    if type(action.ignore_staggers) ~= "table" then return end

    if _banner_bearer_ignore_staggers_original == nil then
        -- Snapshot vanilla on first apply so we can restore exact state.
        _banner_bearer_ignore_staggers_original = {}
        for i = 1, 6 do _banner_bearer_ignore_staggers_original[i] = action.ignore_staggers[i] end
    end

    if mod:get("banner_bearer_staggerable_during_placement") then
        for i = 1, 6 do action.ignore_staggers[i] = false end
        _spawn_dbg("banner", "bearer stagger-immunity disabled — place_standard_stagger_immune.ignore_staggers set to all-false")
    else
        for i = 1, 6 do action.ignore_staggers[i] = _banner_bearer_ignore_staggers_original[i] end
        _spawn_dbg("banner", "bearer stagger-immunity restored to vanilla")
    end
end

-- Apply now if BreedActions already loaded (likely true at mod-script-time
-- for most launches), and on every ConflictDirector.init (mission load) +
-- on setting change. on_disabled also restores.
_safe("banner_apply_initial", _apply_banner_bearer_stagger_toggle)

-- (3) No camera jerk on placement: vanilla
--     ExplosionTemplates.standard_bearer_explosion.explosion catapults/pushes
--     PLAYERS when the standard slams down (catapult_players=true,
--     player_push_speed=10, catapult_force=7 — belladonna_equipment_settings.lua),
--     which launches the player and jerks their camera ("forces the camera when
--     set down"). This toggle nulls the player-knockback vectors on the explosion
--     template so placement no longer moves the player's camera. The explosion's
--     effect on nearby beastmen (the stagger) is unaffected. Snapshot vanilla at
--     first apply; restore on off/disable. force_off=true forces the vanilla
--     restore (used from on_disabled).
local _banner_explosion_original
local function _apply_banner_camera_jerk_toggle(force_off)
    local ETempl = rawget(_G, "ExplosionTemplates")
    local tmpl = type(ETempl) == "table" and ETempl.standard_bearer_explosion
    local expl = type(tmpl) == "table" and tmpl.explosion
    if type(expl) ~= "table" then return end

    if _banner_explosion_original == nil then
        _banner_explosion_original = {
            catapult_players  = expl.catapult_players,
            player_push_speed = expl.player_push_speed,
            catapult_force    = expl.catapult_force,
            catapult_force_z  = expl.catapult_force_z,
        }
    end

    if (not force_off) and mod:get("banner_no_camera_jerk_on_placement") then
        expl.catapult_players  = false
        expl.player_push_speed = 0
        expl.catapult_force    = 0
        if expl.catapult_force_z ~= nil then expl.catapult_force_z = 0 end
        _spawn_dbg("banner", "standard placement player-catapult disabled (no camera jerk)")
    else
        expl.catapult_players  = _banner_explosion_original.catapult_players
        expl.player_push_speed = _banner_explosion_original.player_push_speed
        expl.catapult_force    = _banner_explosion_original.catapult_force
        expl.catapult_force_z  = _banner_explosion_original.catapult_force_z
        _spawn_dbg("banner", "standard placement player-catapult restored to vanilla")
    end
end
_safe("banner_camera_apply_initial", _apply_banner_camera_jerk_toggle)

-- BeastmenStandardHealthExtension.add_damage hook — extends can_damage_banner.
-- Vanilla body (paraphrased):
--   can_damage_banner = attack_type == "heavy_attack" or "light_attack"
--                       or white_listed_damage_sources[damage_source_name]
-- We can't simply pass through to vanilla because vanilla's gate REJECTS
-- ranged before it gets to super.add_damage. So we replicate the vanilla
-- decision path with our widened set when the setting is on.
local _BANNER_RANGED_ATTACK_TYPES = {
    projectile = true,
    instant_projectile = true,
    heavy_instant_projectile = true,
}
if rawget(_G, "BeastmenStandardHealthExtension") then
    _hook_wrap("BeastmenStandardHealthExtension", "add_damage",
            "banner.add_damage",
            function(func, self, attacker_unit, damage_amount, hit_zone_name, damage_type,
                     hit_position, damage_direction, damage_source_name, hit_ragdoll_actor,
                     damaging_unit, hit_react_type, is_critical_strike, added_dot,
                     first_hit, total_hits, attack_type, backstab_multiplier, target_index)
        -- If the setting is off, vanilla decides — no behavior change.
        if not mod:get("banner_breakable_by_ranged") then
            return func(self, attacker_unit, damage_amount, hit_zone_name, damage_type,
                hit_position, damage_direction, damage_source_name, hit_ragdoll_actor,
                damaging_unit, hit_react_type, is_critical_strike, added_dot,
                first_hit, total_hits, attack_type, backstab_multiplier, target_index)
        end

        -- Setting is on. If this is a ranged attack vanilla would reject, we
        -- relay the call straight to the parent's add_damage (which is what
        -- vanilla does for accepted attacks). For everything else, defer to
        -- vanilla — preserves the suicide path and the existing whitelist.
        if attack_type and _BANNER_RANGED_ATTACK_TYPES[attack_type] then
            _spawn_dbg("banner", "ranged hit accepted: attack_type=%s damage_source=%s",
                tostring(attack_type), tostring(damage_source_name))
            local GHE = rawget(_G, "GenericHealthExtension")
            if GHE and type(GHE.add_damage) == "function" then
                GHE.add_damage(self, attacker_unit, damage_amount, hit_zone_name, damage_type,
                    hit_position, damage_direction, damage_source_name, hit_ragdoll_actor,
                    damaging_unit, hit_react_type, is_critical_strike, added_dot,
                    first_hit, total_hits, attack_type, backstab_multiplier, target_index)
                -- Also play vanilla's taking-damage sfx since we bypassed
                -- vanilla's add_damage where it normally fires.
                local std_ext = rawget(_G, "ScriptUnit") and ScriptUnit.has_extension(self._unit, "ai_supplementary_system")
                if std_ext and std_ext.standard_template and std_ext.standard_template.sfx_taking_damage then
                    local WU = rawget(_G, "WwiseUtils")
                    if WU and type(WU.trigger_unit_event) == "function" then
                        WU.trigger_unit_event(std_ext.world, std_ext.standard_template.sfx_taking_damage, self._unit, 0)
                    end
                end
                return
            end
            -- GenericHealthExtension not available — fall through to vanilla.
        end

        return func(self, attacker_unit, damage_amount, hit_zone_name, damage_type,
            hit_position, damage_direction, damage_source_name, hit_ragdoll_actor,
            damaging_unit, hit_react_type, is_critical_strike, added_dot,
            first_hit, total_hits, attack_type, backstab_multiplier, target_index)
    end)
end

ET.apply_banner_bearer_stagger_toggle = _apply_banner_bearer_stagger_toggle
ET.apply_banner_camera_jerk_toggle = _apply_banner_camera_jerk_toggle

rt_register("banner_hook_targets_present", function()
    -- v0.7.2-dev: verifies the two engine surfaces the banner toggles mutate
    -- are still present. Catches engine API rename at install time so the
    -- toggles never silently no-op.
    local missing = {}
    local BA = rawget(_G, "BreedActions")
    if type(BA) ~= "table" then
        missing[#missing+1] = "BreedActions table"
    else
        local sb = BA.beastmen_standard_bearer
        if type(sb) ~= "table" then missing[#missing+1] = "BreedActions.beastmen_standard_bearer" end
        if sb and type(sb.place_standard_stagger_immune) ~= "table" then
            missing[#missing+1] = "BreedActions.beastmen_standard_bearer.place_standard_stagger_immune"
        end
        if sb and sb.place_standard_stagger_immune and type(sb.place_standard_stagger_immune.ignore_staggers) ~= "table" then
            missing[#missing+1] = "place_standard_stagger_immune.ignore_staggers"
        end
        if sb and sb.place_standard_stagger_immune and sb.place_standard_stagger_immune.ignore_staggers
           and #sb.place_standard_stagger_immune.ignore_staggers ~= 6 then
            missing[#missing+1] = string.format("ignore_staggers length changed (was 6, now %d)",
                #sb.place_standard_stagger_immune.ignore_staggers)
        end
    end
    local BSHE = rawget(_G, "BeastmenStandardHealthExtension")
    if not BSHE then
        missing[#missing+1] = "BeastmenStandardHealthExtension (run in keep)"
    elseif type(BSHE.add_damage) ~= "function" then
        missing[#missing+1] = "BeastmenStandardHealthExtension.add_damage (field type changed)"
    end
    local GHE = rawget(_G, "GenericHealthExtension")
    if not GHE or type(GHE.add_damage) ~= "function" then
        missing[#missing+1] = "GenericHealthExtension.add_damage (needed for the bypass-vanilla-accept path)"
    end
    if #missing > 0 then return "banner surface missing: " .. table.concat(missing, ", ") end
end)
