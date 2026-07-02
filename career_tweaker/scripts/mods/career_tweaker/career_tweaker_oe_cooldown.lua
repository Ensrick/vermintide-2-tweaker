local mod = get_mod("crt")

-- ============================================================
-- Outcast Engineer: benefit from Cooldown Reduction bonuses  [crt v0.3.41-dev]
-- ============================================================
-- ONE opt-in (default-OFF) toggle: `oe_benefit_from_cooldown_reduction`.
--
-- ── The vanilla mismatch this fixes (all source-verified) ────────────────────
-- The trinket/charm "Cooldown Reduction" property (key `ability_cooldown_reduction`,
-- weapon_properties.lua:186) grants the `activated_cooldown` stat_buff
-- (value range -0.05..-0.10). `activated_cooldown` is consumed ONLY inside
-- `CareerExtension.start_activated_ability_cooldown`:
--     career_extension.lua:424  buffed_cooldown =
--         buff_extension:apply_buffs_to_value(new_cooldown, "activated_cooldown")
-- and that whole branch is gated on an ability `cost`
--     career_extension.lua:418  min_cooldown = ability.max_cooldown * (1 - ability.cost)
--     career_extension.lua:420  if current_cooldown <= min_cooldown or cost <= 0 then ...
-- The OE's Crank Gun ult `dr_4` (career_ability_settings_cog.lua:5-29) has
-- `cooldown = 60` but NO `cost` field -> that reduction never touches him.
--
-- Meanwhile the OE recharges his ult SOLELY through the `cooldown_regen` decay
-- loop:
--     career_extension.lua:241-246
--         cooldown_speed_multiplier = buff_extension:apply_buffs_to_value(1, "cooldown_regen")
--         self:reduce_activated_ability_cooldown(dt * cooldown_speed_multiplier, i)
-- driven by his pump buff `bardin_engineer_pump_buff` (cooldown_regen multiplier
-- +0.4, talent_settings_cog_dwarf_ranger.lua:20-22, up to 5 stacks) fighting his
-- passive `bardin_engineer_passive_no_ability_regen` (cooldown_regen multiplier
-- -1, talent_settings_cog_dwarf_ranger.lua:7-9 + :85-90).
--
-- So `activated_cooldown` (the trinket stat) and `cooldown_regen` (his only
-- recharge path) are DIFFERENT stat_buffs -> the OE gets exactly ZERO benefit
-- from Cooldown Reduction gear, purely by stat mismatch.
--
-- ── What the toggle does ─────────────────────────────────────────────────────
-- When ON, MIRROR the OE's live `activated_cooldown` reduction onto an equal
-- `cooldown_regen` BONUS so his trinket finally helps his recharge:
--     reduction = 1 - buff_extension:apply_buffs_to_value(1, "activated_cooldown")
--     e.g. a -0.10 Cooldown Reduction trinket -> apply returns 0.90 -> reduction 0.10
-- and we keep a single managed `cooldown_regen` stat_buff worth exactly
-- `reduction` on the local OE. `cooldown_regen` is a `stacking_multiplier`
-- (buff_templates.lua:40): contributions accumulate into stat_buff[0].multiplier
-- (buff_extension.lua:683-686) -- the SAME channel the OE passive (-1) and the pump
-- buff (+0.4 x up to 5 stacks) write. So we MUST contribute a `multiplier`, NOT a
-- `bonus` (stacking_multiplier silently drops the bonus of every non-first
-- registrant, and the passive already created stat_buff[0] at career init). +0.10
-- multiplier makes his pump recharge ~10% faster, plus a small passive trickle
-- that partially offsets the -1 passive.
--
-- ── How the managed bonus stays in sync (no drift / no double-apply) ─────────
-- `activated_cooldown` changes mid-run with gear/boons, so we re-evaluate on a
-- THROTTLED tick (~4x/sec) from the existing `mod.update` (NOT a new hook). We
-- keep exactly ONE managed buff id at a time:
--   * compute the target `reduction` from the live buff_extension;
--   * if it differs from the value we last applied by more than an epsilon
--     (or the buff_extension instance changed, i.e. respawn/career switch),
--     `remove_buff(old_id, skip_net_sync=true)` then `add_buff(...)` with the new
--     value and store the new id.
-- We NEVER add without removing first, so the bonus is REPLACED, never
-- accumulated. When the value is unchanged we do nothing (cheap early-out).
--
-- ── Gating (HARD requirements) ───────────────────────────────────────────────
--   (a) OE ONLY     -- gated strictly on the local player's career == "dr_engineer".
--   (b) OWNER/LOCAL -- career cooldown is read per-owner from the owner's own
--                      buff_extension; we apply to the LOCAL player's player_unit
--                      only (Managers.player:local_player().player_unit).
--   (c) DYNAMIC     -- re-evaluated each throttled tick; replace-on-change.
--   (d) CLEAN OFF   -- toggle off / career switch / no-CDR-gear (reduction ~0) /
--                      mod disabled / unit despawn all remove the managed bonus
--                      and restore EXACT vanilla.
--   (e) The buff is `client_side` + we pass `skip_net_sync` on removal: it lives
--       purely on the local OE's buff_extension (career recharge is computed
--       locally per-owner), so there is no RPC / no cross-peer NetworkLookup
--       determinism concern, and the OE pump mechanic / base behavior is
--       untouched (we only ADD a separate cooldown_regen bonus).
--   (f) Every engine call is pcall-wrapped or nil/type-guarded.
--
-- VMF no-duplicate-hook rule: this module adds NO `mod:hook` at all -- it is
-- driven from `mod.update` (the VMF per-frame callback, not a hook). The single
-- existing `mod.update` in career_tweaker.lua calls into `mod._crt_oe_cdr_tick`.
-- dofile'd from career_tweaker.lua, same as career_tweaker_armor_overcharge.

local OE_CAREER       = "dr_engineer"
local BUFF_NAME       = "crt_oe_cdr_mirror"
local MIRROR_STAT     = "activated_cooldown"   -- the trinket stat we read
local GRANT_STAT      = "cooldown_regen"       -- the recharge stat we feed
-- Below this absolute reduction we consider there to be no meaningful CDR gear
-- and remove the managed bonus entirely (clean vanilla with no-CDR-gear).
local MIN_REDUCTION   = 0.0001
-- Re-apply only when the target moves more than this (avoids churn from
-- floating-point noise; one trinket tier step is 0.05 so this is well under it).
local SYNC_EPSILON    = 0.0005
local TICK_INTERVAL   = 0.25                   -- ~4x/sec throttle

-- ── Managed-bonus state (single buff at a time) ──────────────────────────────
local _managed_id   = nil    -- buff id returned by add_buff (nil => none applied)
local _managed_be   = nil    -- the buff_extension instance the bonus lives on
local _managed_value = nil   -- the reduction we last applied (for drift check)
local _tick_acc     = 0

-- ── Register the managed buff template (once, at load) ───────────────────────
-- A single no-duration `cooldown_regen` MULTIPLIER whose magnitude is
-- driven by `variable_value` at add_buff time:
--   add_buff(BUFF_NAME, { variable_value = v }) ->
--     multiplier = math.lerp(0, variable_multiplier_max, v) = v   (buff_extension.lua:233-237)
-- so passing variable_value = reduction yields exactly `multiplier = reduction`,
-- which accumulates into the cooldown_regen stacking_multiplier root.
-- `client_side = true` keeps it off the network (local-only recharge math).
local function _ensure_template()
    local BT = rawget(_G, "BuffTemplates")
    if not BT then return false end
    local existing = BT[BUFF_NAME]
    if type(existing) == "table" and existing._crt_oe_cdr_real then
        return true
    end
    BT[BUFF_NAME] = {
        _crt_oe_cdr_real = true,
        buffs = {
            {
                name                    = BUFF_NAME,
                stat_buff               = GRANT_STAT,
                variable_multiplier_max = 1.0,   -- variable_value v -> multiplier = v
                client_side             = true,
            },
        },
    }
    return true
end

-- Resolve the LOCAL player + unit + buff_extension, but ONLY when the local
-- player is the Outcast Engineer. Returns (unit, buff_extension) or nil. Whole
-- body pcall'd: Managers.player:local_player() raises at early states.
local function _local_oe_context()
    local ok, unit, be = pcall(function()
        local pm = Managers.player
        local p = pm and pm:local_player()
        if not p then return nil, nil end
        local unit = p.player_unit
        if not (unit and Unit.alive(unit)) then return nil, nil end
        local ce = ScriptUnit.has_extension(unit, "career_system")
        if not (ce and ce.career_name) then return nil, nil end
        if ce:career_name() ~= OE_CAREER then return nil, nil end
        local be = ScriptUnit.has_extension(unit, "buff_system")
        if not be then return nil, nil end
        return unit, be
    end)
    if ok then return unit, be end
    return nil, nil
end

-- Remove the managed bonus if present. skip_net_sync = true (local-only buff).
-- Tolerant of a stale/dead buff_extension (pcall): on respawn the old instance
-- is gone, so we just drop our handle.
local function _clear_managed()
    if _managed_id and _managed_be then
        pcall(function()
            if _managed_be.remove_buff then
                _managed_be:remove_buff(_managed_id, true)
            end
        end)
    end
    _managed_id, _managed_be, _managed_value = nil, nil, nil
end

-- Apply (or re-apply) the managed bonus at `reduction` on buff_extension `be`.
local function _apply_managed(be, reduction)
    local ok, id = pcall(function()
        if not be.add_buff then return nil end
        local new_id = be:add_buff(BUFF_NAME, { variable_value = reduction })
        return new_id
    end)
    if ok and id then
        _managed_id, _managed_be, _managed_value = id, be, reduction
        return true
    end
    -- add failed -> leave no managed handle (state already cleared by caller)
    _managed_id, _managed_be, _managed_value = nil, nil, nil
    return false
end

-- Throttled tick. Called every frame from career_tweaker.lua's mod.update; does
-- real work at most ~4x/sec. Keeps the single managed cooldown_regen bonus in
-- sync with the live activated_cooldown reduction. Throw-proof.
mod._crt_oe_cdr_tick = function(dt)
    _tick_acc = _tick_acc + (dt or 0)
    if _tick_acc < TICK_INTERVAL then return end
    _tick_acc = 0

    -- Toggle OFF (or mod disabled, since VMF returns nil from get when off):
    -- remove the managed bonus and bail to exact vanilla.
    if not mod:get("oe_benefit_from_cooldown_reduction") then
        if _managed_id then _clear_managed() end
        return
    end

    local unit, be = _local_oe_context()
    if not be then
        -- Not the OE right now (career switch / not spawned / despawn): drop the
        -- managed bonus cleanly. _clear_managed tolerates a dead extension.
        if _managed_id then _clear_managed() end
        return
    end

    -- Re-register the template lazily (BuffTemplates may not exist at boot).
    if not _ensure_template() then
        if _managed_id then _clear_managed() end
        return
    end

    -- If the buff_extension instance changed (respawn) our old id is dead -> drop
    -- the handle so we re-apply against the live instance below.
    if _managed_id and _managed_be ~= be then
        _managed_id, _managed_be, _managed_value = nil, nil, nil
    end

    -- Read the live activated_cooldown reduction off the OWNER's own extension.
    local ok, applied = pcall(function()
        return be:apply_buffs_to_value(1, MIRROR_STAT)
    end)
    if not ok or type(applied) ~= "number" then
        if _managed_id then _clear_managed() end
        return
    end
    -- applied is e.g. 0.90 for a -0.10 reduction; reduction is the positive gap.
    local reduction = 1 - applied
    if reduction < 0 then reduction = 0 end

    -- No meaningful CDR gear -> ensure no managed bonus (clean vanilla).
    if reduction < MIN_REDUCTION then
        if _managed_id then _clear_managed() end
        return
    end

    -- In sync already? (same instance + value within epsilon) -> nothing to do.
    if _managed_id and _managed_be == be and _managed_value
       and math.abs(_managed_value - reduction) <= SYNC_EPSILON then
        return
    end

    -- Value/instance changed: REPLACE the single managed bonus (remove then add),
    -- never accumulate.
    _clear_managed()
    _apply_managed(be, reduction)
end

-- Called from on_disabled / on_game_state_changed cleanup so the bonus never
-- lingers after the mod is turned off or we leave a mission.
mod._crt_oe_cdr_clear = function()
    _clear_managed()
end

return {
    tick  = mod._crt_oe_cdr_tick,
    clear = mod._crt_oe_cdr_clear,
}
