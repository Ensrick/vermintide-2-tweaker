-- WP-WT-08: in a mission with bots fighting a horde, wt swallows no error on
-- a vanilla path (safe_hook fallback, create_equipment {} fallback, funnel
-- pcalls). Counters: mod._wt.swallowed; in-mod check wt_no_swallowed_errors;
-- every swallow prints a [wt:SWALLOW] line, which the host forbids.
-- Spawn: ConflictDirector.spawn_queued_unit
-- (Vermintide-2-Source-Code/scripts/managers/conflict_director/conflict_director.lua:1732),
-- same call as qa/runtime/_rig/mission_military.lua.
return {
	card = "WP-WT-08",
	issue = 0,
	arena = "mission:military",
	mods = { "wt" },
	timeout = 150,
	host_forbid_log = { "[wt:SWALLOW]" },
	run = function(T)
		local wt = get_mod("wt")
		T.require(wt ~= nil and type(wt._wt) == "table", "wt is loaded")
		local hero = T.local_hero(30)
		T.require(hero ~= nil, "local hero unit is alive")
		local bots = T.bots()
		T.note("bot_count", #bots)
		T.require(#bots > 0, "bots are alive")

		T.step("spawn a horde next to the hero")
		local count = 12
		if T.spawn then
			for i = 1, count do T.spawn("skaven_slave", { 3 + (i % 4), (i % 3) - 1, 0 }) end
		else
			local conflict = Managers.state.conflict
			T.require(conflict ~= nil and Breeds.skaven_slave ~= nil, "conflict director and breed exist")
			local origin = POSITION_LOOKUP[hero]
			for i = 1, count do
				local pos = origin + Vector3(3 + (i % 4), (i % 3) - 1, 0)
				conflict:spawn_queued_unit(Breeds.skaven_slave, Vector3Box(pos),
					QuaternionBox(Quaternion.identity()), "spawn_one", nil, "horde_hidden", nil)
			end
		end

		T.step("bots fight for 60 s")
		T.wait(60)
		local s = wt._wt.swallowed or {}
		T.note("swallowed", string.format("create_equipment=%d anim_event=%d safe_hook=%d",
			s.create_equipment or 0, s.anim_event or 0, s.safe_hook or 0))

		T.step("no swallowed error")
		if T.expect_rt then
			T.expect_rt("wt", "wt_no_swallowed_errors")
		else
			local verdict
			for _, row in ipairs(wt._wt.run_regression()) do
				if row.name == "wt_no_swallowed_errors" then verdict = row end
			end
			T.expect(verdict ~= nil, "wt_no_swallowed_errors is registered")
			T.expect_eq(verdict and verdict.result, "PASS", "wt_no_swallowed_errors: "
				.. tostring(verdict and verdict.detail))
		end
	end,
}
