-- _ct_journey_difficulty_guard.lua -- issue #291 journey-stat ceiling guard.
--
-- Behavior-neutral extraction; engine globals remain late-bound in the hook.
--
-- Owned by: chaos_wastes_tweaker_dev.lua entry point.
-- Consumed via: one ordered mod:dofile installer call plus the CT regression
-- marker check; guarded by qa/lua/tests/test_ct_journey_difficulty_guard.lua.
return function(mod)

-- ============================================================
-- Journey-completion difficulty crash guard (Issue #291)
-- ============================================================
-- Vanilla StatisticsUtil._register_completed_journey_difficulty resolves the run's
-- difficulty via Managers.state.difficulty:get_default_difficulties(), which returns
-- DefaultDifficulties -- whose top entry is base "cataclysm" (difficulty_settings.lua:412,
-- list = normal/hard/harder/hardest/cataclysm). cataclysm_2 / cataclysm_3 are NOT in
-- that list, so `table.find` returns nil and the very next line does
-- `current_completed_difficulty < nil` -> hard CTD ("attempt to compare number with nil";
-- decompiled statistics_util.lua:1054, shipped bytecode reports it as :997).
--
-- The progressive_difficulty ramp above pushes a CW run up to cataclysm_3, so WINNING a
-- journey's final round (the Citadel) at cata2/cata3 crashed on the journey-stat write.
-- Confirmed in the wild (console 2026-07-04 19.45.55 + issue #291 03.27): the crash fired
-- ~1s after the ramp logged "-> difficulty=cataclysm_3", with journey_name="journey_citadel",
-- difficulty_name="cataclysm_3", difficulty_index=nil, and NO third-party difficulty mod
-- enabled. This guard ALSO shields against Onslaught / "Cata 3 & Deathwish" exposing the
-- same tiers by other means.
--
-- Fix: clamp only the RECORDED difficulty to the highest tier the vanilla journey-stat DB
-- can represent (base "cataclysm"). The player keeps journey-completion credit at that
-- ceiling; the in-mission gameplay difficulty is untouched (this hook does not feed
-- get_run_difficulty). The vanilla per-LEVEL recorder already guards this with
-- `if difficulty then` (statistics_util.lua:1013), so only the journey recorder needs it.
-- Cross-mod note: Loremaster's Armoury also hooks this function; it forwards the args
-- unchanged to the original, so our clamp reaches the vanilla body regardless of chain order.
CT_JOURNEY_DIFFICULTY_GUARD_MARKER = "journey_difficulty_clamp_to_default_max_v0.7.220"
mod:hook("StatisticsUtil", "_register_completed_journey_difficulty",
    function(func, statistics_db, player, journey_name, dominant_god, difficulty_name)
        local dm = Managers.state.difficulty
        local difficulties = dm and dm:get_default_difficulties()
        if type(difficulties) == "table" and not table.find(difficulties, difficulty_name) then
            local clamped = difficulties[#difficulties]
            pcall(printf, "[ct:journeyguard] journey '%s' completed at '%s' (not in DefaultDifficulties) -> recording as '%s' to avoid statistics_util CTD (issue #291)",
                tostring(journey_name), tostring(difficulty_name), tostring(clamped))
            difficulty_name = clamped
        end
        return func(statistics_db, player, journey_name, dominant_god, difficulty_name)
    end)

end
