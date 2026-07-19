-- Blightreaper inspect playback and the bounded ambient-residency probe (#633).
--
-- Proven native contracts:
--   * `nds_skull_inspect` belongs to the Geheimnisnacht ritual-skull audio
--     package, which vanilla loads in the boot DLC package loop.
--   * `emitter_trophy_evil_sword` belongs to the keep-level `wwise/level_hub`
--     bank. Mission residency is not proven, so the ambient feature remains an
--     explicit, capped probe. This module never force-loads a level bank and
--     never sends an audio event over the network.
local M = {
	INSPECT_EVENT = "nds_skull_inspect",
	INSPECT_EVENT_ID = 0x094a950d,
	INSPECT_BANK = "wwise/event_geheimnisnacht",
	INSPECT_PACKAGE = "resource_packages/dlcs/geheimnisnacht_2021",
	INSPECT_MAX_SECONDS = 8,
	AMBIENT_EVENT = "emitter_trophy_evil_sword",
	AMBIENT_EVENT_ID = 0x83e93b19,
	AMBIENT_BANK = "wwise/level_hub",
	PROBE_MAX_SECONDS = 8,
	PROBE_MAX_RUNS = 3,
	SWING_EVENT = "sword_2h_swing",
	CHARGE_EVENT = "rare_sword_2h_charge_swing_execution",
	SWING_BANK = "wwise/two_handed_swords",
	SWING_SOURCE_UNIT = "units/weapons/player/wpn_emp_sword_exe_01_t1/wpn_emp_sword_exe_01_t1",
}

local function default_api()
	return {
		unit = rawget(_G, "Unit"),
		wwise_utils = rawget(_G, "WwiseUtils"),
		wwise_world = rawget(_G, "WwiseWorld"),
		managers = rawget(_G, "Managers"),
		printf = rawget(_G, "printf"),
	}
end

function M.new(injected)
	local api = injected or default_api()
	local unit_api = api.unit
	local wwise_utils = api.wwise_utils
	local wwise_world_api = api.wwise_world
	local managers = api.managers
	local printf_fn = api.printf
	local tracked_1p = setmetatable({}, { __mode = "k" })
	local local_3p_by_owner = setmetatable({}, { __mode = "k" })
	local by_action = setmetatable({}, { __mode = "k" })
	local active = {}
	local logged = {}
	local probe_runs = 0
	local runtime = {}

	local function log(format, ...)
		if type(printf_fn) == "function" then pcall(printf_fn, format, ...) end
	end

	local function log_once(key, format, ...)
		if logged[key] then return end
		logged[key] = true
		log(format, ...)
	end

	local function alive(unit)
		if unit == nil or type(unit_api) ~= "table"
				or type(unit_api.alive) ~= "function" then
			return false
		end
		local ok, result = pcall(unit_api.alive, unit)
		return ok and result == true
	end

	local function inspect_package_ready()
		local package_manager = managers and managers.package
		if not package_manager or type(package_manager.has_loaded) ~= "function" then
			-- Older VMF/engine surfaces do not expose a readable lease query. The
			-- trigger remains pcall-guarded and fails closed if the bank is absent.
			return true, "unobservable"
		end
		local ok, loaded = pcall(package_manager.has_loaded, package_manager,
			M.INSPECT_PACKAGE, "boot")
		if not ok then return false, "package-query-rejected" end
		return loaded == true, loaded == true and "loaded" or "package-not-loaded"
	end

	local function stop_track(track, reason)
		if not track or not active[track] then return false end
		active[track] = nil
		if track.action and by_action[track.action] == track then
			by_action[track.action] = nil
		end
		local should_stop = true
		if type(wwise_world_api) == "table"
				and type(wwise_world_api.is_playing) == "function" then
			local ok, playing = pcall(wwise_world_api.is_playing,
				track.wwise_world, track.playing_id)
			if ok then should_stop = playing == true end
		end
		local stopped = false
		if should_stop and type(wwise_world_api) == "table"
				and type(wwise_world_api.stop_event) == "function" then
			stopped = pcall(wwise_world_api.stop_event,
				track.wwise_world, track.playing_id)
		end
		log("[WOC:633] audio stop kind=%s reason=%s event=%s id=%s stopped=%s chat=false",
			tostring(track.kind), tostring(reason), tostring(track.event),
			tostring(track.playing_id), tostring(stopped))
		return true
	end

	local function stop_kind(kind, reason)
		local pending = {}
		for track in pairs(active) do
			if track.kind == kind then pending[#pending + 1] = track end
		end
		for i = 1, #pending do stop_track(pending[i], reason) end
	end

	local function start_track(kind, event, world, unit, seconds, action)
		if not alive(unit) then return nil, "unit-unavailable" end
		local trigger = type(wwise_utils) == "table"
			and wwise_utils.trigger_unit_event
		if type(trigger) ~= "function" then return nil, "trigger-api-unavailable" end
		local ok, playing_id, source, event_world = pcall(
			trigger, world, event, unit, 0)
		if not ok then return nil, "trigger-rejected" end
		if type(playing_id) ~= "number" or playing_id == 0 then
			return nil, "event-not-resident"
		end
		local track = {
			kind = kind,
			event = event,
			unit = unit,
			action = action,
			playing_id = playing_id,
			source = source,
			wwise_world = event_world,
			remaining = seconds,
		}
		active[track] = true
		if action then by_action[action] = track end
		return track, "started"
	end

	function runtime.observe_spawn(unit_3p, unit_1p, owner_unit_1p, owner_unit_3p)
		if unit_1p ~= nil then tracked_1p[unit_1p] = true end
		-- The local owner spawn is the only one with both owner arguments. Keep
		-- the 3P unit solely for the explicit spatial ambient probe.
		if owner_unit_1p ~= nil and owner_unit_3p ~= nil and unit_3p ~= nil then
			local_3p_by_owner[owner_unit_3p] = unit_3p
		end
	end

	function runtime.start_inspect(action)
		local weapon_unit = action and action.weapon_unit
		if not tracked_1p[weapon_unit] then return false, "not-blightreaper" end
		local ready, package_reason = inspect_package_ready()
		if not ready then
			log_once("inspect:" .. package_reason,
				"[WOC:633] inspect SKIP reason=%s event=%s package=%s chat=false",
				package_reason, M.INSPECT_EVENT, M.INSPECT_PACKAGE)
			return false, package_reason
		end
		-- Only one local inspect whisper can be owned at a time, even if an
		-- interrupted action object survives longer than expected.
		stop_kind("inspect", "inspect-restart")
		local track, reason = start_track("inspect", M.INSPECT_EVENT,
			action.world, weapon_unit, M.INSPECT_MAX_SECONDS, action)
		if not track then
			log_once("inspect:" .. tostring(reason),
				"[WOC:633] inspect SKIP reason=%s event=%s bank=%s package=%s chat=false",
				tostring(reason), M.INSPECT_EVENT, M.INSPECT_BANK, M.INSPECT_PACKAGE)
			return false, reason
		end
		log("[WOC:633] inspect started event=%s bank=%s package_state=%s max_seconds=%d owner=local-1p chat=false",
			M.INSPECT_EVENT, M.INSPECT_BANK, package_reason,
			M.INSPECT_MAX_SECONDS)
		return true, "started"
	end

	-- Blightreaper's authored custom unit has no vanilla weapon-flow graph, so
	-- ActionSweep's `sfx_swing_started` flow event is silent. These are the exact
	-- two Wwise event strings recovered from the native Executioner Sword unit.
	-- Play them only for the positively tracked local 1P WOC unit; impacts remain
	-- the native Crowbill events owned by the combat template.
	function runtime.play_swing(action, phase)
		local weapon_unit = action and action.weapon_unit
		if not tracked_1p[weapon_unit] then return false, "not-blightreaper" end
		local event = phase == "charge" and M.CHARGE_EVENT
			or phase == "release" and M.SWING_EVENT
		if not event then return false, "unknown-phase" end
		local trigger = type(wwise_utils) == "table" and wwise_utils.trigger_unit_event
		if type(trigger) ~= "function" or not alive(weapon_unit) then
			return false, "trigger-unavailable"
		end
		local ok, playing_id = pcall(trigger, action.world, event, weapon_unit, 0)
		if not ok or type(playing_id) ~= "number" or playing_id == 0 then
			log_once("swing:" .. phase,
				"[WOC:633] Executioner swing SKIP phase=%s event=%s bank=%s chat=false",
				phase, event, M.SWING_BANK)
			return false, "event-not-resident"
		end
		return true, "played"
	end

	function runtime.finish_inspect(action, reason)
		return stop_track(by_action[action], reason or "inspect-finish")
	end

	function runtime.stop_unit(unit, reason)
		local pending = {}
		for track in pairs(active) do
			if track.unit == unit then pending[#pending + 1] = track end
		end
		for i = 1, #pending do stop_track(pending[i], reason or "unit-stop") end
	end

	function runtime.stop_equipment(equipment, reason)
		if type(equipment) ~= "table" then return end
		for _, field in ipairs({
			"right_hand_wielded_unit", "right_hand_wielded_unit_3p",
			"left_hand_wielded_unit", "left_hand_wielded_unit_3p",
		}) do
			runtime.stop_unit(equipment[field], reason or "equipment-destroy")
		end
	end

	function runtime.stop_all(reason)
		local pending = {}
		for track in pairs(active) do pending[#pending + 1] = track end
		for i = 1, #pending do stop_track(pending[i], reason or "stop-all") end
	end

	function runtime.update(dt)
		dt = type(dt) == "number" and dt >= 0 and dt or 0
		local pending = {}
		for track in pairs(active) do
			track.remaining = track.remaining - dt
			if track.remaining <= 0 or not alive(track.unit) then
				pending[#pending + 1] = track
			end
		end
		for i = 1, #pending do stop_track(pending[i], "bounded-expiry") end
	end

	local function local_player_unit()
		if type(api.local_player_unit) == "function" then
			local ok, unit = pcall(api.local_player_unit)
			return ok and unit or nil
		end
		local player_manager = managers and managers.player
		if not player_manager or type(player_manager.local_player) ~= "function" then
			return nil
		end
		local ok, player = pcall(player_manager.local_player, player_manager)
		return ok and player and player.player_unit or nil
	end

	function runtime.probe_ambient()
		if probe_runs >= M.PROBE_MAX_RUNS then
			log("[WOC:633] ambient probe SKIP reason=probe-cap runs=%d/%d event=%s bank=%s chat=false",
				probe_runs, M.PROBE_MAX_RUNS, M.AMBIENT_EVENT, M.AMBIENT_BANK)
			return false, "probe-cap"
		end
		probe_runs = probe_runs + 1
		stop_kind("ambient-probe", "probe-restart")
		local owner = local_player_unit()
		local weapon_unit = owner and local_3p_by_owner[owner]
		local world
		local world_manager = managers and managers.world
		if world_manager and type(world_manager.world) == "function" then
			local ok, value = pcall(world_manager.world, world_manager, "level_world")
			if ok then world = value end
		end
		local track, reason = start_track("ambient-probe", M.AMBIENT_EVENT,
			world, weapon_unit, M.PROBE_MAX_SECONDS)
		if not track then
			log("[WOC:633] ambient probe SKIP reason=%s runs=%d/%d event=%s bank=%s force_load=false network=false chat=false",
				tostring(reason), probe_runs, M.PROBE_MAX_RUNS,
				M.AMBIENT_EVENT, M.AMBIENT_BANK)
			return false, reason
		end
		log("[WOC:633] ambient probe started runs=%d/%d event=%s bank=%s id=%s source=local-3p max_seconds=%d force_load=false network=false chat=false",
			probe_runs, M.PROBE_MAX_RUNS, M.AMBIENT_EVENT, M.AMBIENT_BANK,
			tostring(track.playing_id), M.PROBE_MAX_SECONDS)
		return true, "started"
	end

	function runtime.describe()
		log("[WOC:633] audio contract inspect_event=%s inspect_bank=%s inspect_package=%s ambient_event=%s ambient_bank=%s ambient_status=diagnostic force_load=false network=false probe_runs=%d/%d chat=false",
			M.INSPECT_EVENT, M.INSPECT_BANK, M.INSPECT_PACKAGE,
			M.AMBIENT_EVENT, M.AMBIENT_BANK, probe_runs, M.PROBE_MAX_RUNS)
	end

	function runtime.snapshot()
		local result = {
			active = 0,
			inspect = 0,
			ambient_probe = 0,
			probe_runs = probe_runs,
		}
		for track in pairs(active) do
			result.active = result.active + 1
			if track.kind == "inspect" then result.inspect = result.inspect + 1 end
			if track.kind == "ambient-probe" then
				result.ambient_probe = result.ambient_probe + 1
			end
		end
		return result
	end

	return runtime
end

return M
