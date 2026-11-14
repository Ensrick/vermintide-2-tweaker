-- vt2_rig_driver: in-game half of the unattended test rig (engine-native, needs no mod framework).
--
-- This file is never bundled. The rig orchestrator sends its text (hex) in the run plan; the bootstrap
-- Workshop item compiles it with loadstring and returns the table this chunk returns. The game's own mod
-- manager then calls  driver:update(dt)  every frame and  driver:on_game_state_changed(status, name).
--
-- It walks the game from boot to the keep with no input, runs the plan's cases (Lua source delivered as hex
-- text, compiled with loadstring), prints one machine-readable line per event with engine print, saves a
-- results table into the run profile's user settings, and quits.
--
-- Evidence line format (all lines):  [vt2t:<nonce>] <KIND> key=value ...

local plan, nonce = ...

local DRIVER_VERSION = "0.4.0"
local driver = {}

local function find_mod(name)
	local get = rawget(_G, "get_mod")

	return get and get(name) or nil
end

-- ---------------------------------------------------------------------------
-- Output
-- ---------------------------------------------------------------------------
local function out(fmt, ...)
	local ok, text = pcall(string.format, fmt, ...)

	print(string.format("[vt2t:%s] %s", nonce, ok and text or ("FORMAT-ERROR " .. tostring(fmt))))
end

local function q(value)
	local text = tostring(value)

	text = text:gsub("[\r\n]+", " "):gsub('"', "'")

	return '"' .. text .. '"'
end

-- ---------------------------------------------------------------------------
-- Boot bypass (safe to repeat)
-- ---------------------------------------------------------------------------
local function apply_boot_bypass()
	local gsd = rawget(_G, "GameSettingsDevelopment")

	if gsd then
		gsd.skip_start_screen = true
	end

	local dev = rawget(_G, "Development")
	local hard = dev and dev._hardcoded_dev_params

	if hard then
		hard["skip-start-menu"] = true
	end
end

apply_boot_bypass()

-- ---------------------------------------------------------------------------
-- State
-- ---------------------------------------------------------------------------
local S = {
	phase = "BOOT",
	game_state = "?",
	t = 0,
	hb_at = 0,
	hb_seq = 0,
	phase_at = 0,
	arena_index = 0,
	arenas = {},
	cases = {},
	results = {},
	current = nil,
	started_quit = false,
	rt_capture = nil,
}

-- The console log is written through a buffer, so the orchestrator cannot rely on it for liveness.
-- A settings save is a real file write: it is the live progress channel.
local function checkpoint(note)
	pcall(function ()
		Application.set_user_setting("vt2_rig_progress", {
			nonce = nonce,
			phase = S.phase,
			t = S.t,
			note = tostring(note or ""),
			done = #S.results,
			total = #S.cases,
		})
		Application.save_user_settings()
	end)
end

local function set_phase(name)
	S.phase = name
	S.phase_at = S.t

	out("PHASE name=%s t=%.1f", name, S.t)
	checkpoint("phase " .. name)
end

-- ---------------------------------------------------------------------------
-- Plan decoding
-- ---------------------------------------------------------------------------
local function unhex(hex)
	return (hex:gsub("%x%x", function (byte)
		return string.char(tonumber(byte, 16))
	end))
end

local function load_cases()
	local list = plan.cases or {}

	for i = 1, #list do
		local entry = list[i]
		local id = tostring(entry.id or ("case" .. i))
		local case = { id = id, arena = entry.arena or "keep", status = "PENDING" }
		local source = entry.hex and unhex(entry.hex) or entry.src
		local chunk, err = loadstring(source or "", "=case:" .. id)

		if not chunk then
			case.load_error = "compile: " .. tostring(err)
		else
			local ok, def = pcall(chunk)

			if not ok or type(def) ~= "table" or type(def.run) ~= "function" then
				case.load_error = "script must return a table with run(T): " .. tostring(def)
			else
				case.def = def
				case.arena = def.arena or case.arena
				case.timeout = def.timeout or 60
				case.issue = def.issue
			end
		end

		S.cases[#S.cases + 1] = case
	end

	-- arenas in first-seen order, keep first
	local seen = { keep = true }

	S.arenas = { "keep" }

	local wanted = plan.arenas or {}

	for i = 1, #wanted do
		if not seen[wanted[i]] then
			seen[wanted[i]] = true
			S.arenas[#S.arenas + 1] = wanted[i]
		end
	end

	for i = 1, #S.cases do
		local arena = S.cases[i].arena

		if not seen[arena] then
			seen[arena] = true
			S.arenas[#S.arenas + 1] = arena
		end
	end
end

-- ---------------------------------------------------------------------------
-- Engine helpers
-- ---------------------------------------------------------------------------
local function local_player()
	local pm = Managers.player

	return pm and pm:local_player()
end

local function local_hero()
	local player = local_player()
	local unit = player and player.player_unit

	if unit and Unit.alive(unit) then
		return unit
	end
end

local function level_key()
	local state = Managers.state
	local gm = state and state.game_mode

	if gm and gm.level_key then
		return gm:level_key()
	end
end

local function world_ready()
	local ok, ready = pcall(function ()
		return S.game_state == "StateIngame" and local_hero() ~= nil and level_key() ~= nil
	end)

	return ok and ready
end

local function arena_level(arena)
	if arena == "keep" then
		return nil
	end

	local key = arena:match("^mission:(.+)$") or arena:match("^level:(.+)$")

	return key
end

-- ---------------------------------------------------------------------------
-- Assertion context given to scripts
-- ---------------------------------------------------------------------------
local INCONCLUSIVE = {}

local function new_T(case)
	local T = {}
	local n = 0

	local function record(kind, ok, label, extra)
		n = n + 1
		case.asserts = (case.asserts or 0) + (kind == "ASSERT" and 1 or 0)

		if kind == "ASSERT" and not ok then
			case.failed = (case.failed or 0) + 1
			case.first_fail = case.first_fail or label
		end

		out("%s id=%s n=%d %s label=%s%s", kind, case.id, n, kind == "ASSERT" and (ok and "PASS" or "FAIL") or "-", q(label), extra or "")
	end

	T.case_id = case.id
	T.nonce = nonce

	function T.step(label)
		record("STEP", true, label)
	end

	function T.note(key, value)
		out("NOTE id=%s key=%s value=%s", case.id, tostring(key), q(value))
	end

	function T.wait(seconds)
		local until_t = S.t + (seconds or 0)

		while S.t < until_t do
			coroutine.yield()
		end
	end

	function T.frames(count)
		for _ = 1, count or 1 do
			coroutine.yield()
		end
	end

	function T.wait_until(fn, timeout, label)
		local until_t = S.t + (timeout or 10)

		while true do
			local ok, value = pcall(fn)

			if ok and value then
				return value
			end

			if S.t >= until_t then
				record("ASSERT", false, "wait_until: " .. tostring(label), " got=timeout")

				return nil
			end

			coroutine.yield()
		end
	end

	function T.require(cond, label)
		if not cond then
			out("REQUIRE id=%s FAILED label=%s", case.id, q(label))
			error(setmetatable({ label = label }, { __index = INCONCLUSIVE, __tostring = function () return "INCONCLUSIVE" end }))
		end

		return cond
	end

	function T.expect(cond, label)
		record("ASSERT", cond and true or false, label)

		return cond and true or false
	end

	function T.expect_eq(got, want, label)
		local ok = got == want

		record("ASSERT", ok, label, string.format(" got=%s want=%s", q(got), q(want)))

		return ok
	end

	function T.expect_near(got, want, tolerance, label)
		local ok = type(got) == "number" and type(want) == "number" and math.abs(got - want) <= (tolerance or 0.001)

		record("ASSERT", ok, label, string.format(" got=%s want=%s tol=%s", q(got), q(want), q(tolerance)))

		return ok
	end

	T.find_mod = find_mod
	T.local_player = local_player
	T.level_key = level_key

	function T.local_hero(timeout)
		return T.wait_until(local_hero, timeout or 30, "local hero alive")
	end

	function T.bots()
		local units = {}
		local pm = Managers.player
		local bots = pm and pm.bots and pm:bots() or {}

		for _, bot in pairs(bots) do
			if bot.player_unit and Unit.alive(bot.player_unit) then
				units[#units + 1] = bot.player_unit
			end
		end

		return units
	end

	function T.ext(unit, system_name)
		local ext = unit and ScriptUnit.has_extension(unit, system_name)

		T.require(ext, "extension " .. tostring(system_name))

		return ext
	end

	-- Runs a mod chat command. Returns the lines the command printed through VMF echo/info/warning/error.
	function T.cmd(name, ...)
		local vmf = find_mod("VMF")
		local lines = {}

		T.require(vmf and vmf.run_command, "VMF.run_command available")

		S.rt_capture = lines

		local ok, err = pcall(vmf.run_command, name, ...)

		S.rt_capture = nil

		if not ok then
			record("ASSERT", false, "command /" .. tostring(name) .. " raised", " got=" .. q(err))
		end

		return lines
	end

	function T.commands(prefix)
		local vmf = find_mod("VMF")
		local names = {}
		local list = vmf and vmf.get_commands_list and vmf.get_commands_list(prefix or "") or {}

		for i = 1, #list do
			names[#names + 1] = list[i].name
		end

		return names
	end

	return T
end

-- ---------------------------------------------------------------------------
-- VMF output capture (so results do not depend on the user's mod logging mode)
-- ---------------------------------------------------------------------------
local function install_capture()
	local VMFMod = rawget(_G, "VMFMod")

	if not VMFMod or S.capture_installed then
		return
	end

	S.capture_installed = true

	for _, method in ipairs({ "echo", "info", "warning", "error", "debug" }) do
		local original = VMFMod[method]

		if type(original) == "function" then
			VMFMod[method] = function (self, message, ...)
				local capture = S.rt_capture

				if capture then
					local ok, text = pcall(string.format, tostring(message), ...)
					local name = self and self.get_name and self:get_name() or "?"

					text = ok and text or tostring(message)
					capture[#capture + 1] = text

					out("OUT mod=%s via=%s text=%s", name, method, q(text))
				end

				return original(self, message, ...)
			end
		end
	end
end

-- ---------------------------------------------------------------------------
-- Case runner
-- ---------------------------------------------------------------------------
local function finish_case(case, verdict, detail)
	case.status = verdict
	case.detail = detail
	case.seconds = S.t - (case.began or S.t)

	S.results[#S.results + 1] = {
		id = case.id,
		verdict = verdict,
		asserts = case.asserts or 0,
		failed = case.failed or 0,
		detail = detail and tostring(detail) or "",
		seconds = case.seconds,
		issue = case.issue or 0,
	}

	out("CASE END id=%s verdict=%s asserts=%d failed=%d t=%.1f%s", case.id, verdict, case.asserts or 0, case.failed or 0, case.seconds, detail and (" detail=" .. q(detail)) or "")
	checkpoint("case " .. case.id .. " " .. verdict)

	S.current = nil
end

local function start_case(case)
	case.began = S.t

	out("CASE BEGIN id=%s issue=%s arena=%s level=%s", case.id, tostring(case.issue or 0), case.arena, tostring(level_key()))

	if case.load_error then
		finish_case(case, "ERROR", case.load_error)

		return
	end

	case.T = new_T(case)
	case.co = coroutine.create(case.def.run)
	S.current = case
end

local function step_case(case)
	if S.t - case.began > case.timeout then
		finish_case(case, "TIMEOUT", "exceeded " .. tostring(case.timeout) .. " s")

		return
	end

	local ok, err = coroutine.resume(case.co, case.T)

	if not ok then
		if type(err) == "table" and getmetatable(err) and getmetatable(err).__index == INCONCLUSIVE then
			finish_case(case, "INCONCLUSIVE", err.label)
		else
			finish_case(case, "ERROR", tostring(err) .. " | " .. tostring(debug.traceback(case.co)))
		end
	elseif coroutine.status(case.co) == "dead" then
		if (case.failed or 0) > 0 then
			finish_case(case, "FAIL", case.first_fail)
		else
			finish_case(case, "PASS")
		end
	end
end

local function next_case_for(arena)
	for i = 1, #S.cases do
		local case = S.cases[i]

		if case.status == "PENDING" and case.arena == arena then
			return case
		end
	end
end

-- ---------------------------------------------------------------------------
-- End of run
-- ---------------------------------------------------------------------------
local function finish_run(reason)
	local counts = { PASS = 0, FAIL = 0, ERROR = 0, TIMEOUT = 0, INCONCLUSIVE = 0, SKIP = 0 }

	for i = 1, #S.cases do
		local case = S.cases[i]

		if case.status == "PENDING" then
			finish_case(case, "INCONCLUSIVE", "not reached: " .. tostring(reason))
		end
	end

	for i = 1, #S.results do
		local verdict = S.results[i].verdict

		counts[verdict] = (counts[verdict] or 0) + 1
	end

	pcall(function ()
		Application.set_user_setting("vt2_rig_results", { nonce = nonce, driver = DRIVER_VERSION, reason = tostring(reason), cases = S.results })
		Application.save_user_settings()
	end)

	out("RUN END reason=%s cases=%d pass=%d fail=%d error=%d timeout=%d inconclusive=%d t=%.1f", q(reason), #S.results, counts.PASS, counts.FAIL, counts.ERROR, counts.TIMEOUT, counts.INCONCLUSIVE, S.t)
	set_phase("QUIT")

	if plan.quit ~= false then
		Boot.quit_game = true
	end
end

-- ---------------------------------------------------------------------------
-- Backend write shield (on for the whole run unless the plan says backend_shield = false)
-- ---------------------------------------------------------------------------
-- The modded realm signs in to the player's real account, and the game sends career loadouts, talents and user
-- data on its own whenever its local copy differs from the acknowledged one
-- (Vermintide-2-Source-Code/scripts/managers/backend_playfab/playfab_mirror_base.lua:2885-2911, user data at
-- _commit_user_data). A test must never change the real account. So the driver replaces, on the live mirror
-- INSTANCE only, the two functions that decide whether there is something to send: both now answer "nothing",
-- and print what they held back. The commit itself still runs and completes, so no caller waits for ever.
local function install_shield()
	if plan.backend_shield == false then
		return
	end

	local ok, mirror = pcall(function ()
		return Managers.backend:get_backend_mirror()
	end)

	if not ok or type(mirror) ~= "table" or rawget(mirror, "_vt2_rig_shield") then
		return
	end

	rawset(mirror, "_vt2_rig_shield", true)

	rawset(mirror, "_check_career_data", function (_, careers_data, career_data_mirror)
		local changed = 0

		pcall(function ()
			for career, rows in pairs(careers_data) do
				local acked_rows = career_data_mirror[career] or {}

				for index, row in pairs(rows) do
					local acked = acked_rows[index] or {}

					for key, value in pairs(row) do
						if acked[key] ~= value then
							changed = changed + 1
						end
					end
				end
			end
		end)

		if changed > 0 then
			out("SHIELD blocked=characters_data changed_fields=%d case=%s", changed, S.current and S.current.id or "-")
		end

		return false
	end)

	rawset(mirror, "_commit_user_data", function (self, new_data)
		table.clear(new_data)

		local changed = 0

		pcall(function ()
			for key, value in pairs(self._user_data) do
				if self._user_data_mirror[key] ~= value then
					changed = changed + 1
				end
			end
		end)

		if changed > 0 then
			out("SHIELD blocked=user_data changed_keys=%d case=%s", changed, S.current and S.current.id or "-")
		end
	end)

	out("SHIELD installed")
end

-- ---------------------------------------------------------------------------
-- Main loop
-- ---------------------------------------------------------------------------
local function begin_arena(index)
	S.arena_index = index

	local arena = S.arenas[index]

	if not arena then
		finish_run("plan complete")

		return
	end

	local wanted_level = arena_level(arena)

	if arena == "keep" or wanted_level == level_key() then
		set_phase("SETTLE")
	else
		out("LOAD arena=%s level=%s from=%s", arena, tostring(wanted_level), tostring(level_key()))

		local ok, err = pcall(function ()
			Managers.mechanism:debug_load_level(wanted_level, 0)
		end)

		if not ok then
			out("LOAD FAILED arena=%s err=%s", arena, q(err))

			for i = 1, #S.cases do
				if S.cases[i].status == "PENDING" and S.cases[i].arena == arena then
					finish_case(S.cases[i], "INCONCLUSIVE", "level load raised: " .. tostring(err))
				end
			end

			begin_arena(index + 1)

			return
		end

		S.wanted_level = wanted_level

		set_phase("LOADING")
	end
end

driver.update = function (_, dt)
	S.t = S.t + dt

	if S.phase == "QUIT" then
		return
	end

	if S.t - S.hb_at >= 5 then
		S.hb_at = S.t
		S.hb_seq = S.hb_seq + 1

		out("HB seq=%d t=%.1f phase=%s state=%s level=%s case=%s", S.hb_seq, S.t, S.phase, S.game_state, tostring(level_key()), S.current and S.current.id or "-")
	end

	local hard_limit = plan.timeout or 900

	if S.t > hard_limit then
		finish_run("run time limit " .. tostring(hard_limit) .. " s")

		return
	end

	if S.phase == "BOOT" then
		apply_boot_bypass()

		if world_ready() then
			install_capture()
			install_shield()
			out("KEEP READY level=%s t=%.1f", tostring(level_key()), S.t)
			begin_arena(1)
		end
	elseif S.phase == "LOADING" then
		if S.t - S.phase_at > (plan.load_timeout or 240) then
			out("LOAD TIMEOUT level=%s", tostring(S.wanted_level))

			local arena = S.arenas[S.arena_index]

			for i = 1, #S.cases do
				if S.cases[i].status == "PENDING" and S.cases[i].arena == arena then
					finish_case(S.cases[i], "INCONCLUSIVE", "level did not load in time")
				end
			end

			begin_arena(S.arena_index + 1)
		elseif world_ready() and level_key() == S.wanted_level and S.t - S.phase_at > 3 then
			install_shield()
			out("LEVEL READY level=%s t=%.1f load_seconds=%.1f", tostring(level_key()), S.t, S.t - S.phase_at)
			set_phase("SETTLE")
		end
	elseif S.phase == "SETTLE" then
		if not world_ready() then
			S.phase_at = S.t
		elseif S.t - S.phase_at >= (plan.settle or 4) then
			set_phase("RUN")
		end
	elseif S.phase == "RUN" then
		if S.current then
			step_case(S.current)
		else
			local case = next_case_for(S.arenas[S.arena_index])

			if case then
				start_case(case)
			else
				begin_arena(S.arena_index + 1)
			end
		end
	end
end

driver.on_game_state_changed = function (_, status, state_name)
	if status == "enter" then
		S.game_state = state_name

		out("STATE enter=%s t=%.1f", tostring(state_name), S.t)
	end

	apply_boot_bypass()
end

-- ---------------------------------------------------------------------------
-- Start
-- ---------------------------------------------------------------------------
load_cases()

out("RUN BEGIN driver=%s plan=%s cases=%d arenas=%s realm=modded", DRIVER_VERSION, q(plan.name or "?"), #S.cases, q(table.concat(S.arenas, ",")))

local ok_pid, pid = pcall(function ()
	return Application.process_id and Application.process_id()
end)

out("PROBE pid=%s io=%s loadstring=%s os_time=%s curl=%s cjson=%s FrameCapture=%s save_render_target=%s restart_file_log=%s console_send=%s CommandWindow=%s VMFMod=%s", tostring(ok_pid and pid), type(rawget(_G, "io")), type(rawget(_G, "loadstring")), type(os and os.time), type(Managers and Managers.curl), type(rawget(_G, "cjson")), type(rawget(_G, "FrameCapture")), type(Application.save_render_target), type(Application.restart_file_log), type(Application.console_send), type(rawget(_G, "CommandWindow")), type(rawget(_G, "VMFMod")))

return driver
