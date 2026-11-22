-- WP-H-10 rig acceptance: one still in the keep. T.shot asks the rig for it and holds still; run.ps1 captures the game
-- window into <run>\stills\ and, because qa/runtime/plans/still-keep.json sets require_stills, checks that the PNG is
-- 1280x720 and brighter than the floor. The case itself only checks that the request was saved: the still is judged
-- outside the game (shots.json, summary.json "shots").
return {
	issue = 0,
	arena = "keep",
	class = "R",
	timeout = 60,
	run = function(T)
		T.require(T.local_hero(30) ~= nil, "local hero alive")
		T.step("let the keep settle")
		T.wait(5)
		T.step("one still")
		T.expect_eq(type(T.shot("keep after load")), "number", "the still request was saved")
	end,
}
