-- tools/harness/driver/lib/shot.lua: T.shot asks the rig for one still of the game (WP-H-10; the WP-H-06 stub before it).
--
-- The game cannot take the still itself: FrameCapture is nil in the retail build and Application.save_render_target
-- has no caller in the decompile, so its arguments are unknown (PROBE lines; tools/harness/README.md "Stills"). And the
-- game cannot hear back from the host: io is nil and user settings are read only at start. So the request is one-way:
-- T.shot writes vt2_rig_shot = { nonce, seq, case, n, label } into the user settings and saves them (a real file
-- write, the same channel as the progress checkpoint), prints "SHOT REQ", and holds still for `hold` seconds (default
-- 3) while run.ps1 sees the request and captures the game window into <run>\stills\. run.ps1's shots.json says what
-- it got. T.shot returns the request number, or nil when the request could not be saved; a case must never assert on
-- a still (OD-02: only presence or absence may close, and that is judged from the PNG, outside the game).
-- At most MAX_PER_CASE stills per case and no loops (H.md WP-H-10 guardrails: the author machine stalls under fast
-- redraw). Documented in tools/harness/API.md.

local MAX_PER_CASE = 5
local seq = 0

return function (T, ctx)
	local case = ctx.case
	local n = 0

	function T.shot(label, hold)
		n = n + 1
		hold = math.max(1, math.min(tonumber(hold) or 3, 10))

		if n > MAX_PER_CASE then
			ctx.out("SHOT id=%s n=%d label=%s captured=false refused=\"more than %d stills in one case\" t=%.1f", case.id, n, ctx.q(label), MAX_PER_CASE, ctx.now())

			return nil
		end

		seq = seq + 1

		local this = seq
		local saved = T.main(function ()
			return pcall(function ()
				Application.set_user_setting("vt2_rig_shot", {
					nonce = T.nonce,
					seq = this,
					case = case.id,
					n = n,
					label = tostring(label or ""),
				})
				Application.save_user_settings()
			end)
		end)

		ctx.out("SHOT REQ id=%s n=%d seq=%d label=%s hold=%d saved=%s t=%.1f", case.id, n, this, ctx.q(label), hold, tostring(saved == true), ctx.now())

		if saved ~= true then
			return nil
		end

		T.wait(hold)
		ctx.out("SHOT DONE id=%s n=%d seq=%d t=%.1f", case.id, n, this, ctx.now())

		return this
	end
end
