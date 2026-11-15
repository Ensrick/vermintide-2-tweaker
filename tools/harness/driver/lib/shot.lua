-- tools/harness/driver/lib/shot.lua: T.shot records that a case asked for a still (WP-H-06 step 4).
--
-- The capture itself is WP-H-10. Until it lands, T.shot prints one SHOT line with captured=false, writes no file and
-- returns false, so a case can already name the stills it wants and its verdict never depends on one.
-- Documented in tools/harness/API.md.

return function (T, ctx)
	local case = ctx.case
	local n = 0

	function T.shot(label)
		n = n + 1

		ctx.out("SHOT id=%s n=%d label=%s captured=false t=%.1f", case.id, n, ctx.q(label), ctx.now())

		return false
	end
end
