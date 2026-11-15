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
--
-- 0.4.4 (WP-H-04): plan arenas run in order and may repeat (the keep is inn_level, reloaded when needed); T.spawn,
-- T.kill, T.teleport, T.invincible, T.end_level and T.return_to_keep; each case's helper changes are undone
-- when it ends (run_cleanups). Engine calls that take a unit run in the main update through T.main, never inside
-- the case coroutine (they fail there: "Attempting get_data with reference from another lua state").
--
-- 0.4.5 (WP-H-03): T.cmd runs the command in the main update; every "  <VERDICT>: <check>" row a regression
-- suite echoes is kept per mod for T.expect_rt; tools/harness/Parse-Sweep.ps1 turns the OUT lines into sweep.json.
--
-- 0.4.6 (WP-H-06): helper groups under tools/harness/driver/lib/ travel in the plan (plan.libs) and add their
-- helpers to every case's T (load_libs, install_libs); the first groups are T.set and the T.shot stub.
-- tools/harness/API.md lists every helper.
--
-- 0.4.7 (WP-H-06 actor group): T.teleport takes { x, y, z } or a Vector3Box and builds the Vector3 in the main update.

local plan, nonce = ...

local DRIVER_VERSION = "0.4.7"
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
	main_jobs = {},
	started_quit = false,
	rt_capture = nil,
	rt_results = {},
	keep_ready = false,
	shared = {},
	libs = {},
	om_snapshot = nil,
	-- what the backend write shield did; T.shield() hands cases a copy
	shield = {
		installed = false,
		installed_at = -1,
		career_checks = 0,
		user_data_checks = 0,
		keep_decorations_checks = 0,
		blocked_characters_data = 0,
		blocked_user_data = 0,
		blocked_keep_decorations = 0,
		saw_update_hero_attributes = 0,
		saw_requests = 0,
	},
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

	-- WP-H-04: the plan's arenas in their own order, repeats allowed (keep, mission:military, keep returns to the
	-- keep before quitting); the run always starts in the keep; arenas of cases the plan does not list follow.
	local seen = { keep = true }
	local wanted = plan.arenas or {}

	S.arenas = { "keep" }

	for i = 1, #wanted do
		local arena = tostring(wanted[i])

		if i > 1 or arena ~= "keep" then
			S.arenas[#S.arenas + 1] = arena
		end

		seen[arena] = true
	end

	for i = 1, #S.cases do
		local arena = S.cases[i].arena

		if not seen[arena] then
			seen[arena] = true
			S.arenas[#S.arenas + 1] = arena
		end
	end
end

-- Shared helpers (qa/runtime/_shared/*.lua) travel in the plan as hex text like the cases. Each returns a table.
-- Cases get one with T.shared(name); the driver itself uses official_mirror for its end-of-run restore.
local function load_shared()
	local list = plan.shared or {}

	for i = 1, #list do
		local entry = list[i]
		local id = tostring(entry.id or ("shared" .. i))
		local chunk, err = loadstring(entry.hex and unhex(entry.hex) or "", "=shared:" .. id)
		local ok, lib = false, err

		if chunk then
			ok, lib = pcall(chunk)
		end

		if ok and type(lib) == "table" then
			S.shared[id] = lib

			out("SHARED id=%s ok=true", id)
		else
			out("SHARED id=%s ok=false err=%s", id, q(lib))
		end
	end
end

-- WP-H-06: helper groups (tools/harness/driver/lib/*.lua, sent by New-RigProfile.ps1 -LibDir in file-name order)
-- travel in the plan as hex text. Each chunk returns install(T, ctx); install_libs calls every one for each case
-- after the driver's own helpers. A group that does not load is named in a LIB line and its helpers stay nil, so a
-- case that calls one ends as ERROR.
local function load_libs()
	local list = plan.libs or {}

	for i = 1, #list do
		local entry = list[i]
		local id = tostring(entry.id or ("lib" .. i))
		local chunk, err = loadstring(entry.hex and unhex(entry.hex) or "", "=lib:" .. id)
		local ok, install = false, err

		if chunk then
			ok, install = pcall(chunk)
		end

		if ok and type(install) == "function" then
			S.libs[#S.libs + 1] = { id = id, install = install }

			out("LIB id=%s ok=true", id)
		else
			out("LIB id=%s ok=false err=%s", id, q(ok and ("returned " .. type(install) .. ", not an install function") or install))
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

-- The keep is the hub level inn_level (LevelSettings.inn_level.hub_level = true,
-- Vermintide-2-Source-Code/scripts/settings/level_settings.lua:50-57), so debug_load_level can return to it.
local KEEP_LEVEL = "inn_level"

local function arena_level(arena)
	if arena == "keep" then
		return KEEP_LEVEL
	end

	local key = arena:match("^mission:(.+)$") or arena:match("^level:(.+)$")

	return key
end

-- Host-side level change (Vermintide-2-Source-Code/scripts/managers/game_mode/game_mechanism_manager.lua:880-892;
-- Adventure: mechanisms/adventure_mechanism.lua:580-594 picks the hub state for a hub level).
local function load_level(level)
	Managers.mechanism:debug_load_level(level, 0)
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

	-- Runs fn(...) in the driver's main update, outside this case's coroutine, and returns its results; an error
	-- raised there is raised here. Engine calls that take a unit fail inside a coroutine (lead run
	-- 20261115-144350-mission-smoke-75899d31: "Attempting get_data with reference from another lua state" in
	-- AiUtils.kill_unit, scripts/helpers/damage_utils.lua:1917), so every helper below that hands a unit to the
	-- engine goes through here, and a case does the same for its own such calls. Costs one update.
	function T.main(fn, ...)
		local job = { fn = fn, args = { n = select("#", ...), ... } }

		S.main_jobs[#S.main_jobs + 1] = job

		while not job.done do
			coroutine.yield()
		end

		if not job.ok then
			error(job.err, 0)
		end

		return unpack(job.results, 1, job.results.n)
	end

	function T.ext(unit, system_name)
		local ext = unit and T.main(ScriptUnit.has_extension, unit, system_name)

		T.require(ext, "extension " .. tostring(system_name))

		return ext
	end

	-- WP-H-04 actor helpers (host side, no OS input), all run in the main update (T.main). Whatever a helper
	-- changes is undone when the case ends: case.cleanups runs newest first in finish_case, in the main update.
	case.cleanups = case.cleanups or {}

	-- Queues one enemy next to the hero the way the game's own test hook does
	-- (Vermintide-2-Source-Code/scripts/managers/conflict_director/conflict_director_testify.lua:18-22;
	-- ConflictDirector.spawn_queued_unit, conflict_director.lua:1732) and returns the unit once it is alive
	-- (spawned_units_by_breed, conflict_director.lua:2144). The unit is killed at cleanup if still alive.
	-- offset: a Vector3 or { x, y, z } relative to the hero.
	function T.spawn(breed_name, offset, timeout)
		local queued, why = T.main(function ()
			local conflict = Managers.state.conflict
			local breed = Breeds[breed_name]
			local hero = local_hero()

			if not conflict then
				return nil, "conflict director exists"
			elseif not breed then
				return nil, "breed " .. tostring(breed_name) .. " exists"
			elseif not hero then
				return nil, "local hero alive"
			end

			local before = {}

			for _, unit in pairs(conflict:spawned_units_by_breed(breed_name) or {}) do
				before[unit] = true
			end

			local position = Unit.local_position(hero, 0)

			if type(offset) == "table" then
				position = position + Vector3(offset[1] or offset.x or 0, offset[2] or offset.y or 0, offset[3] or offset.z or 0)
			elseif offset ~= nil then
				position = position + offset
			end

			conflict:spawn_queued_unit(breed, Vector3Box(position), QuaternionBox(Quaternion.identity()))

			return { conflict = conflict, before = before }
		end)

		T.require(queued ~= nil, why)

		local deadline = S.t + (timeout or 15)
		local unit

		repeat
			unit = T.main(function ()
				for _, candidate in pairs(queued.conflict:spawned_units_by_breed(breed_name) or {}) do
					if not queued.before[candidate] and Unit.alive(candidate) then
						return candidate
					end
				end
			end)
		until unit ~= nil or S.t >= deadline

		if unit then
			case.cleanups[#case.cleanups + 1] = function ()
				if HEALTH_ALIVE[unit] then
					AiUtils.kill_unit(unit)
				end
			end
		else
			T.expect(false, "spawned " .. tostring(breed_name) .. " within " .. tostring(timeout or 15) .. " s")
		end

		return unit
	end

	-- Kills a unit with the game's own helper (AiUtils.kill_unit, ai_player_unit/ai_utils.lua:1326).
	function T.kill(unit)
		return T.main(function ()
			if unit and HEALTH_ALIVE[unit] then
				AiUtils.kill_unit(unit)

				return true
			end

			return false
		end)
	end

	-- Moves a unit that has a teleport_to locomotion (PlayerUnitLocomotionExtension.teleport_to,
	-- default_player_unit/player_unit_locomotion_extension.lua:1005). position: { x, y, z } or a Vector3Box (built into a
	-- Vector3 inside the main update, like T.spawn's offset), or a Vector3 (it reaches the engine one update later).
	function T.teleport(unit, position)
		local moved = T.main(function ()
			local locomotion = unit and ScriptUnit.has_extension(unit, "locomotion_system")

			if not (locomotion and locomotion.teleport_to) then
				return false
			end

			local target = position

			if type(position) == "table" and position.unbox == nil then
				target = Vector3(position[1] or position.x or 0, position[2] or position.y or 0, position[3] or position.z or 0)
			else
				-- a box (engine type, unbox method) gives its value; a plain Vector3 has no unbox and is used as it is
				local unboxed, value = pcall(function ()
					return position:unbox()
				end)

				if unboxed and value ~= nil then
					target = value
				end
			end

			locomotion:teleport_to(target)

			return true
		end)

		T.require(moved, "unit can be teleported")
	end

	-- The hero's health extension flag read by get_is_invincible (generic/generic_health_extension.lua:496-512;
	-- the player damage gate at default_player_unit/player_unit_health_extension.lua:780). Restored at cleanup.
	function T.invincible(on)
		local done = T.main(function ()
			local hero = local_hero()
			local health = hero and ScriptUnit.has_extension(hero, "health_system")

			if not health then
				return false
			end

			if not case.invincible_saved then
				local previous = health.is_invincible

				case.invincible_saved = true
				case.cleanups[#case.cleanups + 1] = function ()
					health.is_invincible = previous
				end
			end

			health.is_invincible = on and true or false

			return true
		end)

		T.require(done, "hero health extension")
	end

	-- Ends the level as host: GameModeManager.complete_level / fail_level (game_mode/game_mode_manager.lua:636, 645).
	function T.end_level(result)
		local done = T.main(function ()
			local game_mode = Managers.state.game_mode

			if not game_mode then
				return false
			end

			if result == "fail" then
				game_mode:fail_level()
			else
				game_mode:complete_level()
			end

			return true
		end)

		T.require(done, "game mode manager")
	end

	-- Loads the keep and waits until it is ready (the hero alive in StateIngame on inn_level).
	function T.return_to_keep(timeout)
		T.main(function ()
			if level_key() ~= KEEP_LEVEL then
				load_level(KEEP_LEVEL)
			end
		end)

		return T.wait_until(function ()
			return world_ready() and level_key() == KEEP_LEVEL
		end, timeout or 240, "back in the keep")
	end

	-- Runs a mod chat command in the main update (T.main: a regression suite's checks touch units) and returns the
	-- lines the command printed through VMF echo/info/warning/error. Regression rows it prints ("  PASS: <check>")
	-- are kept for T.expect_rt for the rest of the boot.
	function T.cmd(name, ...)
		local vmf = find_mod("VMF")

		T.require(vmf and vmf.run_command, "VMF.run_command available")

		local args = { n = select("#", ...), ... }
		local lines, ok, err = T.main(function ()
			local captured = {}

			S.rt_capture = captured

			local ran, why = pcall(vmf.run_command, name, unpack(args, 1, args.n))

			S.rt_capture = nil

			return captured, ran, why
		end)

		if not ok then
			record("ASSERT", false, "command /" .. tostring(name) .. " raised", " got=" .. q(err))
		end

		return lines
	end

	-- WP-H-03: a named in-mod regression check passed in this boot. Reads the rows that T.cmd captured from the
	-- mod's /<mod>_regression_test (run it earlier in the boot, e.g. with qa/runtime/_rig/sweep_regression.lua).
	-- PASS and XPASS pass; FAIL, XFAIL and BAD-SHAPE fail; SKIP or a missing suite or check is INCONCLUSIVE.
	function T.expect_rt(mod_id, check_name)
		local suite = S.rt_results[mod_id]

		T.require(suite ~= nil, "regression suite of " .. tostring(mod_id) .. " ran earlier in this boot")

		local row = suite[check_name]

		T.require(row ~= nil, "check " .. tostring(check_name) .. " reported by " .. tostring(mod_id))
		T.require(row.verdict ~= "SKIP", "check " .. tostring(check_name) .. " not skipped (" .. tostring(row.detail) .. ")")

		local ok = row.verdict == "PASS" or row.verdict == "XPASS"

		record("ASSERT", ok, "rt " .. tostring(mod_id) .. " " .. tostring(check_name), " got=" .. q(row.verdict) .. (row.detail ~= "" and (" detail=" .. q(row.detail)) or ""))

		return ok
	end

	-- A copy of what the backend write shield did so far (counts only; see install_shield).
	function T.shield()
		local copy = {}

		for key, value in pairs(S.shield) do
			copy[key] = value
		end

		return copy
	end

	-- A shared helper sent with the plan (qa/runtime/_shared/<name>.lua), or INCONCLUSIVE when it is missing.
	function T.shared(name)
		local lib = S.shared[name]

		T.require(lib ~= nil, "shared helper " .. tostring(name) .. " delivered with the plan")

		return lib
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

	-- WP-H-06 helper groups. ctx is all a group gets from the driver: the case (its id and cleanups list), the
	-- evidence printers and the engine readers above. A group that raises while installing is named and skipped.
	local ctx = {
		case = case,
		record = record,
		out = out,
		q = q,
		now = function ()
			return S.t
		end,
		find_mod = find_mod,
		local_player = local_player,
		local_hero = local_hero,
		level_key = level_key,
	}

	for i = 1, #S.libs do
		local lib = S.libs[i]
		local ok, err = pcall(lib.install, T, ctx)

		if not ok then
			out("LIB ERROR id=%s case=%s err=%s", lib.id, case.id, q(err))
		end
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

					-- WP-H-03: the row every runner echoes, "  <VERDICT>: <check>[ -- <detail>]"
					-- (e.g. weapon_tweaker/scripts/mods/weapon_tweaker/_wt_regression.lua, chat command body)
					local verdict, check, rest = text:match("^%s*(%u[%u%-]*): (%S+)(.*)$")

					if method == "echo" and (verdict == "PASS" or verdict == "FAIL" or verdict == "SKIP" or verdict == "XFAIL" or verdict == "XPASS" or verdict == "BAD-SHAPE") then
						local suite = S.rt_results[name] or {}

						S.rt_results[name] = suite
						suite[check] = { verdict = verdict, detail = (rest:gsub("^%s*%-%-%s*", "")) }
					end
				end

				return original(self, message, ...)
			end
		end
	end
end

-- ---------------------------------------------------------------------------
-- Case runner
-- ---------------------------------------------------------------------------
local function run_cleanups(case)
	local list = case.cleanups

	if type(list) ~= "table" or #list == 0 then
		return
	end

	local errors = 0

	for i = #list, 1, -1 do
		local ok, err = pcall(list[i])

		if not ok then
			errors = errors + 1

			out("CLEANUP ERROR id=%s err=%s", case.id, q(err))
		end
	end

	out("CLEANUP id=%s actions=%d errors=%d", case.id, #list, errors)

	case.cleanups = {}
end

-- T.main jobs (WP-H-04): queued by a case's coroutine, run here in the main update right after the resume, so
-- engine calls that take a unit never run inside the coroutine.
local function pack(...)
	return { n = select("#", ...), ... }
end

local function run_main_jobs()
	local jobs = S.main_jobs

	if #jobs == 0 then
		return
	end

	S.main_jobs = {}

	for i = 1, #jobs do
		local job = jobs[i]
		local r = pack(pcall(job.fn, unpack(job.args, 1, job.args.n)))

		job.ok = r[1]

		if job.ok then
			job.results = { n = r.n - 1 }

			for k = 2, r.n do
				job.results[k - 1] = r[k]
			end
		else
			job.err = r[2]
		end

		job.done = true
	end
end

local function finish_case(case, verdict, detail)
	S.main_jobs = {}

	run_cleanups(case)

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
-- Official loadout rows: snapshot at KEEP READY, restore before quitting (WP-H-14 step 3)
-- ---------------------------------------------------------------------------
-- A second line of defence behind the write shield: whatever a case left changed in mirror._career_data is put
-- back to the copy taken at KEEP READY before the game quits, so no change is left pending for a later commit.
-- Raw field writes through OM.restore (qa/runtime/_shared/official_mirror.lua); never a commit. Off together
-- with the shield (plan backend_shield = false).
local function take_official_snapshot()
	local OM = S.shared.official_mirror

	if plan.backend_shield == false then
		return
	end

	if not OM then
		out("SHIELD snapshot skipped reason=%s", q("official_mirror helper not delivered with the plan"))

		return
	end

	local ok, snap = pcall(OM.snapshot)

	if ok and type(snap) == "table" then
		local careers = 0

		for _ in pairs(snap) do
			careers = careers + 1
		end

		S.om_snapshot = snap

		out("SHIELD snapshot careers=%d t=%.1f", careers, S.t)
	else
		out("SHIELD snapshot failed err=%s", q(snap))
	end
end

local function restore_official_mirror()
	local snap = S.om_snapshot
	local OM = S.shared.official_mirror

	if not snap or not OM then
		return
	end

	local changed, extra = 0, 0
	local ok, err = pcall(function ()
		local rows_now = Managers.backend:get_backend_mirror()._career_data

		for career, rows in pairs(snap) do
			for index, row in pairs(rows) do
				local now = rows_now[career] and rows_now[career][index] or {}

				for key, value in pairs(row) do
					if now[key] ~= value then
						changed = changed + 1
					end
				end

				for key in pairs(now) do
					if row[key] == nil then
						extra = extra + 1
					end
				end
			end
		end

		OM.restore(snap)
	end)

	out("SHIELD restore changed_fields=%d extra_fields=%d ok=%s%s", changed, extra, tostring(ok), ok and "" or (" err=" .. q(err)))
end

-- ---------------------------------------------------------------------------
-- End of run
-- ---------------------------------------------------------------------------
local function finish_run(reason)
	local counts = { PASS = 0, FAIL = 0, ERROR = 0, TIMEOUT = 0, INCONCLUSIVE = 0, SKIP = 0 }

	restore_official_mirror()

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
--
-- 0.4.1: the shield goes up on the first tick on which the backend mirror exists, not at KEEP READY. Run
-- smoke-keep-4b32903a showed why: the game sends its routine start-up save (_commit_internal "1", request
-- updateHeroAttributes) about 4 s BEFORE the keep is ready. The shield also watches the mirror's request queue
-- and prints the top-level key NAMES of every updateHeroAttributes request (never values), so a run's
-- evidence shows what the game still sent.
--
-- 0.4.2: run smoke-keep-5f5ca4b0 showed that the start-up save carries one key, keep_decorations: the
-- account's painting layout decoded and encoded again (backend_interface_keep_decorations_playfab.lua:7-22,
-- 62-64; compared as a string at playfab_mirror_base.lua:2879-2883). The shield now answers that comparison
-- with the acknowledged string, so a rig run sends no hero-attribute save at all, and prints how many
-- painting slots it held back when a case changed the layout.
--
-- 0.4.3 (WP-H-14): the shield keeps counts that cases read with T.shield(), prints the function name of every
-- other cloud-script request built after KEEP READY, and the driver puts the official career rows back to the
-- KEEP READY snapshot before it quits (take_official_snapshot / restore_official_mirror above).
local function shield_keep_decorations(mirror)
	local ok, interface = pcall(function ()
		local interfaces = rawget(Managers.backend, "_interfaces")

		return type(interfaces) == "table" and interfaces.keep_decorations
	end)

	if not ok or type(interface) ~= "table" or rawget(interface, "_vt2_rig_shield") then
		return
	end

	local encode = interface.get_keep_decorations_json

	if type(encode) ~= "function" then
		return
	end

	rawset(interface, "_vt2_rig_shield", true)
	rawset(interface, "get_keep_decorations_json", function (self)
		local acked = rawget(mirror, "_read_only_data_mirror")

		acked = type(acked) == "table" and acked.keep_decorations

		if type(acked) ~= "string" then
			return encode(self)
		end

		S.shield.keep_decorations_checks = S.shield.keep_decorations_checks + 1

		pcall(function ()
			local before, now, changed = cjson.decode(acked), self._keep_decorations, 0

			for slot, painting in pairs(now) do
				if before[slot] ~= painting then
					changed = changed + 1
				end
			end

			for slot in pairs(before) do
				if now[slot] == nil then
					changed = changed + 1
				end
			end

			if changed > 0 then
				S.shield.blocked_keep_decorations = S.shield.blocked_keep_decorations + 1
			end

			if changed > 0 and changed ~= S.shield_keep_changed then
				S.shield_keep_changed = changed

				out("SHIELD blocked=keep_decorations changed_slots=%d case=%s", changed, S.current and S.current.id or "-")
			end
		end)

		return acked
	end)

	out("SHIELD keep_decorations installed t=%.1f state=%s", S.t, tostring(S.game_state))
end

local function install_shield()
	if plan.backend_shield == false then
		return
	end

	local ok, mirror = pcall(function ()
		return Managers.backend:get_backend_mirror()
	end)

	if not ok or type(mirror) ~= "table" then
		return
	end

	shield_keep_decorations(mirror)

	if rawget(mirror, "_vt2_rig_shield") then
		return
	end

	rawset(mirror, "_vt2_rig_shield", true)

	local queue = rawget(mirror, "_request_queue")

	if type(queue) == "table" and not rawget(queue, "_vt2_rig_watch") and type(queue.enqueue) == "function" then
		local enqueue = queue.enqueue

		rawset(queue, "_vt2_rig_watch", true)
		-- Observe and pass through: key NAMES of updateHeroAttributes (never values), and after KEEP READY the
		-- function name of every other cloud-script request the game builds
		-- (the game itself logs "Enqueuing ExecuteCloudScript request" at playfab_request_queue.lua:49).
		rawset(queue, "enqueue", function (self, request, ...)
			pcall(function ()
				local name = type(request) == "table" and request.FunctionName

				S.shield.saw_requests = S.shield.saw_requests + 1

				if name == "updateHeroAttributes" then
					local keys = {}
					local attributes = type(request.FunctionParameter) == "table" and request.FunctionParameter.hero_attributes

					if type(attributes) == "table" then
						for key in pairs(attributes) do
							keys[#keys + 1] = tostring(key)
						end

						table.sort(keys)
					end

					S.shield.saw_update_hero_attributes = S.shield.saw_update_hero_attributes + 1

					out("SHIELD saw request=updateHeroAttributes keys=%s characters_key=%s", q(table.concat(keys, ",")), q(rawget(mirror, "_characters_data_key")))
				elseif S.keep_ready and type(name) == "string" then
					out("SHIELD saw request=%s case=%s", tostring(name), S.current and S.current.id or "-")
				end
			end)

			return enqueue(self, request, ...)
		end)
	end

	rawset(mirror, "_check_career_data", function (_, careers_data, career_data_mirror)
		local changed = 0

		S.shield.career_checks = S.shield.career_checks + 1

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
			S.shield.blocked_characters_data = S.shield.blocked_characters_data + 1

			out("SHIELD blocked=characters_data changed_fields=%d case=%s", changed, S.current and S.current.id or "-")
		end

		return false
	end)

	rawset(mirror, "_commit_user_data", function (self, new_data)
		table.clear(new_data)

		local changed = 0

		S.shield.user_data_checks = S.shield.user_data_checks + 1

		pcall(function ()
			for key, value in pairs(self._user_data) do
				if self._user_data_mirror[key] ~= value then
					changed = changed + 1
				end
			end
		end)

		if changed > 0 then
			S.shield.blocked_user_data = S.shield.blocked_user_data + 1

			out("SHIELD blocked=user_data changed_keys=%d case=%s", changed, S.current and S.current.id or "-")
		end
	end)

	S.shield.installed = true
	S.shield.installed_at = S.t

	out("SHIELD installed t=%.1f state=%s", S.t, tostring(S.game_state))
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

	if wanted_level == nil then
		out("LOAD FAILED arena=%s err=%s", arena, q("arena not supported by this driver"))

		for i = 1, #S.cases do
			if S.cases[i].status == "PENDING" and S.cases[i].arena == arena then
				finish_case(S.cases[i], "INCONCLUSIVE", "arena not supported by this driver: " .. tostring(arena))
			end
		end

		begin_arena(index + 1)

		return
	end

	if wanted_level == level_key() then
		set_phase("SETTLE")
	else
		out("LOAD arena=%s level=%s from=%s", arena, tostring(wanted_level), tostring(level_key()))

		local ok, err = pcall(load_level, wanted_level)

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

	install_shield()

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
			S.keep_ready = true
			take_official_snapshot()
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
			run_main_jobs()
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
load_shared()
load_libs()

local ok_pid, pid = pcall(function ()
	return Application.process_id and Application.process_id()
end)

out("PROBE pid=%s io=%s loadstring=%s os_time=%s curl=%s cjson=%s FrameCapture=%s save_render_target=%s restart_file_log=%s console_send=%s CommandWindow=%s VMFMod=%s", tostring(ok_pid and pid), type(rawget(_G, "io")), type(rawget(_G, "loadstring")), type(os and os.time), type(Managers and Managers.curl), type(rawget(_G, "cjson")), type(rawget(_G, "FrameCapture")), type(Application.save_render_target), type(Application.restart_file_log), type(Application.console_send), type(rawget(_G, "CommandWindow")), type(rawget(_G, "VMFMod")))

return driver
