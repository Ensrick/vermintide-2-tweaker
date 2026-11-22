-- API self-test, keep part (WP-H-06): calls every helper that needs only the keep once, so a rig run proves each
-- one works in the game (tools/harness/API.md, Rig column "api-selftest"). Mission helpers (T.spawn, T.kill,
-- T.invincible) are exercised by qa/runtime/plans/mission-smoke.json; T.cmd and the regression rows by the sweep plans.
return {
	issue = 0,
	arena = "keep",
	class = "R",
	timeout = 90,
	run = function(T)
		T.step("flow helpers")
		T.expect_eq(type(T.case_id), "string", "T.case_id is the plan's case id")
		T.note("case_id", T.case_id)
		T.expect_eq(type(T.nonce), "string", "T.nonce is set")
		T.require(true, "T.require passes a true precondition")
		T.wait(0.2)
		T.frames(2)
		local seen = T.wait_until(function()
			return "ready"
		end, 5, "a true condition is seen at once")
		T.expect_eq(seen, "ready", "T.wait_until returns the value of the condition")
		T.expect_near(0.1 + 0.2, 0.3, 0.0001, "T.expect_near holds within its tolerance")
		local a, b = T.main(function(x)
			return x + 1, "main"
		end, 41)
		T.expect_eq(a, 42, "T.main hands back the first result")
		T.expect_eq(b, "main", "T.main hands back the second result")

		T.step("world helpers")
		local hero = T.local_hero(30)
		T.require(hero ~= nil, "local hero alive")
		T.expect(T.local_player() ~= nil, "T.local_player returns the player")
		T.expect_eq(T.level_key(), "inn_level", "T.level_key is the keep")
		T.expect_eq(type(T.bots()), "table", "T.bots returns a list")
		T.expect(T.ext(hero, "health_system") ~= nil, "T.ext finds the hero's health extension")

		T.step("mods and evidence helpers")
		T.expect(T.find_mod("VMF") ~= nil, "T.find_mod finds VMF")
		T.expect(#T.commands("") > 0, "T.commands lists the registered commands")
		T.expect_eq(T.shield().installed, true, "T.shield reports the installed write shield")
		T.expect_eq(type(T.shared("official_mirror")), "table", "T.shared hands out official_mirror")
		T.expect_eq(T.shot("api selftest still"), false, "T.shot records the request; no capture until WP-H-10")
	end,
}
