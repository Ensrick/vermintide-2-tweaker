-- gt_dev issue 332 (v0.2.250-dev): full-arity regression pin for the mutator
-- death-explosion hooks in _gt_solo_qol.lua (BUG_CLASSES class 19: a hooked
-- vanilla fn that names fewer params than vanilla silently collapses the
-- trailing args to nil).
--
-- Vanilla signatures (decompile, grep-verified 2026-07-18):
--   * AiUtils.generic_mutator_explosion(unit, blackboard,
--     explosion_template_name, do_damage)
--     [scripts/unit_extensions/human/ai_player_unit/ai_utils.lua:575; do_damage
--     gates the attacker arg of DamageUtils.create_explosion at :583]
--   * AreaDamageSystem.rpc_create_explosion(self, channel_id, attacker_unit_id,
--     attacker_is_level_unit, position, rotation, explosion_template_name_id,
--     scale, damage_source_id, attacker_power_level, is_critical_strike,
--     source_attacker_unit_id)
--     [scripts/entity_system/systems/area_damage/area_damage_system.lua:473]
--
-- The pre-v0.2.186 bug: the host hook captured 3 params and called func() with
-- 3, passing do_damage=nil on every non-suppressed call. These needles pin the
-- full-arity capture AND forward on both hooks, and reject the exact 3-arg
-- regression shape.
return function(H, repo_root)
    local qol_path = repo_root
        .. "/general_tweaker_dev/scripts/mods/general_tweaker_dev/_gt_solo_qol.lua"
    local f = assert(io.open(qol_path, "rb")); local qol = f:read("*a"); f:close()

    H.test("GT host mutator-explosion hook captures and forwards all 4 vanilla args", function()
        H.truthy(qol:find(
            'mod:hook("AiUtils", "generic_mutator_explosion", function (func, killed_unit, blackboard, explosion_template_name, do_damage)',
            1, true))
        H.truthy(qol:find(
            "return func(killed_unit, blackboard, explosion_template_name, do_damage)",
            1, true))
        -- Reject the exact regression shape: a 3-arg forward drops do_damage
        -- (plain-text needle; the healthy 4-arg call does not match it because
        -- its paren closes after ", do_damage").
        H.equal(qol:find("func(killed_unit, blackboard, explosion_template_name)", 1, true), nil)
    end)

    H.test("GT client rpc_create_explosion hook names the full 12-param vanilla signature", function()
        local sig = "function (func, self, channel_id, attacker_unit_id, attacker_is_level_unit,"
            .. " position, rotation, explosion_template_name_id, scale, damage_source_id,"
            .. " attacker_power_level, is_critical_strike, source_attacker_unit_id)"
        H.truthy(qol:find(sig, 1, true))
        local fwd = "return func(self, channel_id, attacker_unit_id, attacker_is_level_unit,"
            .. " position, rotation, explosion_template_name_id, scale, damage_source_id,"
            .. " attacker_power_level, is_critical_strike, source_attacker_unit_id)"
        H.truthy(qol:find(fwd, 1, true))
    end)

    H.test("GT mutator-explosion hooks stay singletons per (Class, method)", function()
        -- VMF drops a 2nd hook on the same pair; exactly one registration each.
        local function count(needle)
            local n, from = 0, 1
            while true do
                local at = qol:find(needle, from, true)
                if not at then return n end
                n = n + 1
                from = at + 1
            end
        end
        H.equal(count('mod:hook("AiUtils", "generic_mutator_explosion"'), 1)
        H.equal(count('mod:hook("AreaDamageSystem", "rpc_create_explosion"'), 1)
        -- Both paths share the strict template filter so normal bomb/artillery
        -- explosions are never touched.
        H.truthy(qol:find("_gt_is_mutator_explosion(explosion_template_name)", 1, true))
        H.truthy(qol:find("_gt_is_mutator_explosion(name)", 1, true))
    end)
end
