local mod = get_mod("gt_dev")

-- _gt_godmode_qol.lua — the gt QoL / cheat bundle (NOT the godmode body).
--
-- IMPORTANT: this module does NOT contain godmode. The godmode invisibility +
-- damage-blocking BODY (the DamageUtils.add_damage_network /
-- add_damage_network_player hooks) stays in the main file. Only the friendly-fire
-- DamageUtils.allow_friendly_fire_ranged / .allow_friendly_fire_melee hooks move
-- here — different methods, so no duplicate-hook collision with godmode.
--
-- Bundles four small self-contained QoL/cheat features (each independent):
--   (1) Unstuck (/unstuck command, no hook)
--   (2) Friendly Fire Toggle (DamageUtils.allow_friendly_fire_ranged/melee hooks)
--   (3) Player-state toggles: inn-damage / cloak / unkillable (commands, no hook)
--   (4) More Corpses (RagdollSettings cap, no hook)
--   (Disable Loading-Screen Monologues MIGRATED to gut 2026-06-29, #192.)
--
-- DISPATCH WIRING (no behavior change after extraction):
--   * mod.gt_apply_corpse_count()  — already a public name; the main-file
--     on_setting_changed branch (gt_more_corpses_*) resolves it at call time.
--     Also applied once at module load.
--   * mod.gt_inn_dmg_toggle / mod.gt_cloak_toggle / mod.gt_unkillable_toggle —
--     chat commands resolve them at invoke time.
--   * disable_friendly_fire is read directly inside the FF hooks (no apply-fn).
--
-- Extracted from general_tweaker_dev.lua (v0.2.133-dev, "refactor: extract
-- single-hook self-contained features to modules — no behavior change").
-- Owned by: general_tweaker_dev.lua entry point. Consumed via: mod:dofile
-- (runs after the main chunk, so any mod._* fields are already set).

-- ============================================================
-- Unstuck (teleport to nearest living teammate)
-- ============================================================
-- Registered under TWO command names (user request 2026-07-02): /unstuck
-- (original) and /catchup (alias). Same body via the shared local below.
-- Collision pre-flight: repo-wide grep found no other mod:command("catchup").

local function _gt_unstuck_to_teammate()
    local pm = Managers.player
    if not pm then mod:echo("Not in a level.") return end
    local player = pm:local_player()
    if not player then mod:echo("No local player.") return end
    local unit = player.player_unit
    if not unit then mod:echo("No player unit (dead?).") return end

    local self_pos = Unit.local_position(unit, 0)
    local best_human_pos, best_human_dist_sq = nil, math.huge
    local best_bot_pos, best_bot_dist_sq = nil, math.huge

    for _, p in pairs(pm:players()) do
        if p ~= player and p.player_unit and HEALTH_ALIVE[p.player_unit] then
            local pos = Unit.local_position(p.player_unit, 0)
            local d = Vector3.distance_squared(pos, self_pos)
            local is_human = p.is_player_controlled and p:is_player_controlled()
            if is_human then
                if d < best_human_dist_sq then
                    best_human_pos, best_human_dist_sq = pos, d
                end
            else
                if d < best_bot_dist_sq then
                    best_bot_pos, best_bot_dist_sq = pos, d
                end
            end
        end
    end

    local target_pos = best_human_pos or best_bot_pos
    if target_pos then
        local mover = Unit.mover(unit)
        if mover then
            Mover.set_position(mover, target_pos + Vector3(0.5, 0, 0))
        end
        mod:echo(best_human_pos and "Unstuck (to nearest human)!" or "Unstuck (to nearest bot)!")
    else
        mod:echo("No living teammate found.")
    end
end

mod:command("unstuck", "Teleport to nearest living teammate (prefers humans)", _gt_unstuck_to_teammate)
mod:command("catchup", "Teleport to nearest living teammate (prefers humans); alias of /unstuck", _gt_unstuck_to_teammate)

-- ============================================================
-- Friendly Fire Toggle
-- ============================================================
-- On Champion+, ranged FF is on by default. Hook the two gate
-- functions that everything else calls through to suppress it.
-- (These are DamageUtils.allow_friendly_fire_*, distinct from the godmode
-- add_damage_network* hooks that stay in the main file — no collision.)

mod:hook("DamageUtils", "allow_friendly_fire_ranged", function(func, ...)
    if mod:get("disable_friendly_fire") then return false end
    return func(...)
end)

mod:hook("DamageUtils", "allow_friendly_fire_melee", function(func, ...)
    if mod:get("disable_friendly_fire") then return false end
    return func(...)
end)

-- ============================================================
-- Player-state toggles (Group E — Janoti "Hacks" port)
-- ============================================================
-- Three small toggles that don't fit the other groups, all kept distinct
-- from gt's existing `god` toggle on purpose:
--
--  * `inn_dmg`   — host-only flip of `DamageUtils.is_in_inn`. When the
--    inn flag is OFF, the keep behaves like a mission (damage taken,
--    enemies could spawn, etc.). Useful for sparring with bots.
--  * `cloak`     — visual cloak that hides the player model. gt's `god`
--    already cloaks via `status_system:set_invisible(true, false,
--    "gt_godmode")`, but `god` is a multi-feature umbrella. `cloak` is a
--    standalone cosmetic toggle using a separate reason namespace so it
--    doesn't clobber god's invisibility state.
--  * `unkillable`— flips `script_data.player_unkillable`. Unlike `god`
--    you DO still take damage (and disablers still grab you) but you
--    can't be dropped below 1 HP. Mostly a "let me actually feel hits
--    while testing" mode.

mod.gt_inn_dmg_toggle = function()
    if not (Managers.player and Managers.player.is_server) then
        mod:echo("Only the host can toggle inn-damage.")
        return
    end
    if DamageUtils.is_in_inn then
        DamageUtils.is_in_inn = false
        mod:echo("Damage in keep: ENABLED.")
    else
        DamageUtils.is_in_inn = true
        mod:echo("Damage in keep: disabled (vanilla).")
    end
end

mod:command("inndmg", "Toggle whether the keep takes damage (host-only)", function()
    mod.gt_inn_dmg_toggle()
end)

-- Visual cloak: distinct from gt god's invisibility (separate reason namespace
-- so neither clobbers the other on toggle-off). The 3P body and 1P weapon
-- arms both hide because skip_first_person=false. AI perception ignores the
-- player too (same set_invisible primitive).
local _gt_cloak_active = false

mod.gt_cloak_toggle = function()
    local lp = Managers.player and Managers.player:local_player()
    local unit = lp and lp.player_unit
    if not (unit and Unit.alive(unit)) then
        mod:echo("No local player unit.")
        return
    end
    local status_ext = ScriptUnit.has_extension(unit, "status_system")
    if not (status_ext and status_ext.set_invisible) then
        mod:echo("No status extension on local player.")
        return
    end
    _gt_cloak_active = not _gt_cloak_active
    status_ext:set_invisible(_gt_cloak_active, false, "gt_cloak")
    mod:echo(_gt_cloak_active and "Cloak: ON (invisible)." or "Cloak: OFF.")
end

mod:command("cloak", "Toggle visual invisibility (separate from godmode)", function()
    mod.gt_cloak_toggle()
end)

-- Unkillable: take damage normally, but the engine refuses to drop you below
-- 1 HP while the flag is on. Vanilla globals `script_data` controls this; we
-- just flip the flag and announce.
mod.gt_unkillable_toggle = function()
    script_data = script_data or {}
    script_data.player_unkillable = not script_data.player_unkillable
    mod:echo(script_data.player_unkillable and "Unkillable: ON (still take damage)." or "Unkillable: OFF.")
end

mod:command("unkillable", "Toggle take-damage-but-never-die mode", function()
    mod.gt_unkillable_toggle()
end)

-- Disable Loading-Screen Monologues MIGRATED to gui_tweaker (gut) 2026-06-29, #192
-- — gut's _gut_monologue.lua now owns the script_data.disable_level_intro_dialogue
-- flag, the toggle, and the /gut_intromono command.

-- ============================================================
-- More Corpses (raise ragdoll cap)
-- ============================================================
-- Vanilla `RagdollSettings.max_num_ragdolls = 24` / `min_num_ragdolls = 10`
-- (unit_spawner_settings.lua:3-6). When the AI's combined alive+dead unit
-- count crosses max, UnitSpawner.update prunes corpses down to min. Raising
-- both lets more dead bodies linger before the engine starts despawning
-- them. Setting both to the same value means we cap pruning at exactly the
-- user's choice — the engine still cleans up everything beyond it, so this
-- is safe to crank without leaking units.

-- Max Ragdolls: single always-on slider (enable toggle removed 2026-06-30). We pin
-- BOTH the ragdoll cap and the prune floor to the slider value so the engine holds
-- ~count corpses instead of sawtoothing down to vanilla's min of 10. Default 24
-- (vanilla cap), up to 300.
mod.gt_apply_corpse_count = function()
    if not RagdollSettings then return end
    local count = mod:get("gt_more_corpses_count") or 24
    RagdollSettings.max_num_ragdolls = count
    RagdollSettings.min_num_ragdolls = count
end

mod.gt_apply_corpse_count()
