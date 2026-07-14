-- Issue #438: Mercenary's "On Yer Feet, Mates!" uses rpc_request_revive,
-- unlike the normal interaction path. Vanilla's HealthSystem handler revives
-- and emits telemetry but omits StatisticsUtil.register_revive; Comet's Gift
-- explicitly calls it after its own instant revive. Repair that exact omission
-- on the authoritative server while remaining inert if vanilla/another hook
-- has already incremented the statistic.

local mod = get_mod("gut_dev")
local Policy = mod:dofile("scripts/mods/gui_tweaker_dev/_gut_revive_scoreboard_policy")
local TALENT = "markus_mercenary_activated_ability_revive"
local diagnostic_count = 0
local DIAGNOSTIC_CAP = 16

local function _context_before(self, revived_unit_go_id, reviver_unit_go_id)
    if not self.is_server or not self.unit_storage then return nil end

    local revived_unit = self.unit_storage:unit(revived_unit_go_id)
    local reviver_unit = self.unit_storage:unit(reviver_unit_go_id)
    if not revived_unit or not reviver_unit then return nil end

    local talent_extension = ScriptUnit.has_extension(reviver_unit, "talent_system")
    local status_extension = ScriptUnit.has_extension(revived_unit, "status_system")
    if not talent_extension or not status_extension then return nil end

    local player = Managers.player:owner(reviver_unit)
    local statistics_db = Managers.player:statistics_db()
    if not player or not statistics_db then return nil end

    local stats_id = player:stats_id()
    if stats_id == nil then return nil end

    return {
        is_server = true,
        has_talent = talent_extension:has_talent(TALENT) == true,
        was_career_revivable = status_extension:is_available_for_career_revive() == true,
        revives_before = statistics_db:get_stat(stats_id, "revives"),
        statistics_db = statistics_db,
        stats_id = stats_id,
        reviver_unit = reviver_unit,
        revived_unit = revived_unit,
    }
end

-- Hook pre-flight: no other gui_tweaker_dev hook targets
-- HealthSystem.rpc_request_revive. The source handler has no return values.
mod:hook("HealthSystem", "rpc_request_revive", function(func, self, channel_id,
        revived_unit_go_id, reviver_unit_go_id)
    local context = _context_before(self, revived_unit_go_id, reviver_unit_go_id)
    func(self, channel_id, revived_unit_go_id, reviver_unit_go_id)

    if not context then return end
    context.revives_after = context.statistics_db:get_stat(context.stats_id, "revives")
    if not Policy.should_repair(context) then return end

    StatisticsUtil.register_revive(
        context.reviver_unit, context.revived_unit, context.statistics_db)

    if diagnostic_count < DIAGNOSTIC_CAP then
        diagnostic_count = diagnostic_count + 1
        printf("[gut:438] credited On Yer Feet revive stats_id=%s before=%s after=%s record=%d/%d",
            tostring(context.stats_id), tostring(context.revives_before),
            tostring(context.revives_after + 1), diagnostic_count, DIAGNOSTIC_CAP)
    end
end)

return {
    policy = Policy,
    diagnostic_cap = DIAGNOSTIC_CAP,
    rt_checks = {
        {
            name = "issue438_on_yer_feet_revive_credit",
            fn = function()
                if not Policy.should_repair({
                    is_server = true,
                    has_talent = true,
                    was_career_revivable = true,
                    revives_before = 4,
                    revives_after = 4,
                }) then
                    return "missing-stat Mercenary career revive was not repaired"
                end
                if Policy.should_repair({
                    is_server = true,
                    has_talent = true,
                    was_career_revivable = true,
                    revives_before = 4,
                    revives_after = 5,
                }) then
                    return "already-credited revive would be double-counted"
                end
                if DIAGNOSTIC_CAP > 16 then return "diagnostic cap is unbounded" end
            end,
        },
    },
}
