local mod = get_mod("WOC")

local MOD_VERSION = "0.1.57-dev"

mod:info("Weapons of Chaos v%s loading", MOD_VERSION)

-- ============================================================================
-- Weapons of Chaos (WOC)
-- ============================================================================
-- Lets the player characters wield ENEMY weapons and named keep-trophy props.
-- Built the duplicate-weapon way, modeled on character_weapon_variants (CWV):
-- each weapon is a real inventory item cloned from a player base weapon
-- template, with its `right_hand_unit` swapped to a different `.unit` mesh.
--
-- FIRST ITEM: "Blightreaper" — a unique relic with Sienna's one-handed
-- Crowbill action graph (bw_1h_crowbill), slowed to 83%, equippable by every
-- career of all five heroes. Its vanilla `es_1h_sword` transport identity
-- remains mixed-peer safe.
--
-- HELD MESH: the sword placed beside the Bögenhafen mission cage was extracted
-- from the level bundle and re-authored as explicit WOC-owned 1P and 3P units.
-- WOC's master package owns their residency; preview/package collectors borrow
-- the base Empire sword package identity without replacing the local render
-- unit. The keep-trophy diorama itself remains documentation-only and is never
-- force-loaded (a unit-path PackageManager load is an engine C-fatal).
-- ============================================================================

-- Two-helper debug-logging policy (PROJECT_STANDARDS.md § 3.6).
-- Routed through VMF logging channels; visible via VMF output_mode_debug / output_mode_warning.
-- `_dbg` = confirmation / expected behavior — mod:debug channel.
-- `_dbg_alert` = unexpected / wrong / mismatch. Log-only via engine printf (#427).
local function _dbg(fmt, ...)
	mod:debug("[WOC:dbg] " .. fmt, ...)
end

-- Issue #427/#240: mod:warning posts to CHAT under VMF defaults (logging.lua
-- warning mode >= 2), so a "log-only" alert spammed chat. Route through
-- pcall-guarded engine printf (log-only, survives mod-logging-OFF; pcall so a
-- format slip never faults the caller). Reserve chat for a deliberate
-- _chat_alert (none defined here).
local function _dbg_alert(fmt, ...)
	if not pcall(printf, "[WOC:dbg] " .. fmt, ...) then
		pcall(printf, "[WOC:dbg] (alert format error: %s)", tostring(fmt))
	end
end

-- Applied-marker fingerprint (PROJECT_STANDARDS.md § 3.6 "Applied marker line").
-- Walks the data widget tree, FNV-1a-32 hashes setting=value pairs; the marker
-- line at the bottom of this file surfaces the live config in the console log.
local function _settings_fingerprint()
	local ok, data = pcall(require, "scripts/mods/weapons_of_chaos/weapons_of_chaos_data")
	if not ok or type(data) ~= "table" then return "nodata" end
	local keys = {}
	local function walk(node)
		if type(node) ~= "table" then return end
		if type(node.setting_id) == "string" then keys[#keys + 1] = node.setting_id end
		for _, child in pairs(node) do
			if type(child) == "table" then walk(child) end
		end
	end
	walk(data)
	if #keys == 0 then return "nosettings" end
	table.sort(keys)
	local parts = {}
	for i, k in ipairs(keys) do
		local v = mod:get(k)
		if v == true then       parts[i] = k .. "=1"
		elseif v == false then  parts[i] = k .. "=0"
		elseif v == nil then    parts[i] = k .. "=?"
		else                    parts[i] = k .. "=" .. tostring(v) end
	end
	local s = table.concat(parts, ";")
	-- FNV-1a 32-bit, plain-arithmetic XOR (no bit32 in Lua 5.1 sandbox).
	local h = 2166136261
	for i = 1, #s do
		local byte = string.byte(s, i)
		local xored, place = 0, 1
		local hh, bb = h, byte
		for _ = 1, 32 do
			local hb, bbit = hh % 2, bb % 2
			if hb ~= bbit then xored = xored + place end
			place = place * 2
			hh = (hh - hb) / 2
			bb = (bb - bbit) / 2
		end
		h = (xored * 16777619) % 4294967296
	end
	return string.format("%08x", h)
end

-- Regression self-test scaffold (PROJECT_STANDARDS § 5.1a). Individual checks are
-- registered inline next to the code they cover (search "_rt_register"); run
-- in-game via /woc_regression_test.
local _RT_CHECKS = {}
local function _rt_register(name, fn)
	_RT_CHECKS[#_RT_CHECKS + 1] = { name = name, fn = fn }
end

-- (#511) io-safe source reader. The VMF retail Stingray VM registers no `io`
-- library (mods are loadstring'd into the game's shared _G; the engine registers
-- `os` but not `io`), so a bare `io.open` throws "attempt to index global 'io'
-- (a nil value)" and the regression runner's pcall reports it as a FALSE FAIL on
-- healthy code (issue 479/511). Source-pattern checks route through this helper,
-- which returns nil (-> the check's "unreadable source => skip" branch, a PASS)
-- instead of throwing. In retail the source-text half is skipped; the source-text
-- needles still run under the modding-tools build / CI and are the QA-gate
-- candidates (PROJECT_STANDARDS 2.2b tier a).
local function _rt_src_read(path)
	local io_lib = rawget(_G, "io")
	if type(io_lib) ~= "table" or type(io_lib.open) ~= "function" then
		return nil
	end
	local f = io_lib.open(path, "r")
	if not f then return nil end
	local t = f:read("*a")
	f:close()
	return t
end
mod:command("woc_regression_test", "Run WOC regression smoke checks for past bugs", function()
	local pass, fail, skip = 0, 0, 0
	mod:echo("=== WOC regression_test (v%s) ===", MOD_VERSION)
	for _, c in ipairs(_RT_CHECKS) do
		local ok, err = pcall(c.fn)
		if ok and err == nil then
			mod:echo("  PASS: %s", c.name); pass = pass + 1
		elseif ok and type(err) == "string" and err:sub(1, 5) == "skip:" then
			mod:echo("  SKIP: %s -- %s", c.name, err:sub(7)); skip = skip + 1
		else
			mod:echo("  FAIL: %s -- %s", c.name, tostring(err)); fail = fail + 1
		end
	end
	mod:echo("=== %d passed, %d failed, %d skipped ===", pass, fail, skip)
end)

-- ============================================================
-- Constants
-- ============================================================

local ITEM_KEY    = "woc_blightreaper"
local BACKEND_ID  = ITEM_KEY .. "_001"
local BASE_WEAPON = "es_1h_sword"                       -- Kruber 1H sword (clone source)
local _wire_policy = mod:dofile("scripts/mods/weapons_of_chaos/_woc_wire_policy")
local _moveset = mod:dofile("scripts/mods/weapons_of_chaos/_woc_blightreaper_moveset")
local _WIRE_PROTECTED_TRAITS = {
	[_moveset.POISON_TRAIT] = true,
	[_moveset.SHYISH_CURSE_TRAIT] = true,
}
local _power = mod:dofile("scripts/mods/weapons_of_chaos/_woc_blightreaper_power")
local _cursed = mod:dofile("scripts/mods/weapons_of_chaos/_woc_cursed_rarity")
local TEMPLATE = _moveset.TEMPLATE
-- Attack-order picker: pure permutation engine + the Blightreaper chain
-- descriptor (single source for dropdown vocabulary, defaults, and the
-- transition data layer). Registered so future CWV descriptors share the path.
local _attack_order = mod:dofile("scripts/mods/weapons_of_chaos/_woc_attack_order")
local _chain_descriptor = _moveset.chain_descriptor()
do
	local ok, reason = _attack_order.register(_chain_descriptor)
	if not ok then
		_dbg_alert("attack-order descriptor rejected: %s", tostring(reason))
	end
end
local _appearance = mod:dofile("scripts/mods/weapons_of_chaos/_woc_appearance_policy")
local _issue613 = mod:dofile("scripts/mods/weapons_of_chaos/_woc_issue613_preview_owner")
local _appearance_lib = mod:dofile("scripts/mods/weapons_of_chaos/_lib_weapon_appearance")
local _network_lookup = mod:dofile("scripts/mods/weapons_of_chaos/_lib_network_lookup")
local _durable_transform_lib = mod:dofile(
	"scripts/mods/weapons_of_chaos/_woc_durable_transform")
local _appearance_fade = mod:dofile(
	"scripts/mods/weapons_of_chaos/_lib_appearance_fade").new({
	alive = function(unit) return Unit and Unit.alive and Unit.alive(unit) end,
	get_extension = function(owner, name)
		return ScriptUnit and ScriptUnit.has_extension
			and ScriptUnit.has_extension(owner, name) or nil
	end,
	get_fade_system = function()
		local entity = Managers and Managers.state and Managers.state.entity
		return entity and entity:system("fade_system") or nil
	end,
	diag_budget = 16,
	report = function(row)
		pcall(printf, "[WOC:922] fade edge=%s result=%s linked=%d error=%s",
			tostring(row.edge), tostring(row.reason), tonumber(row.count) or 0,
			tostring(row.error))
	end,
})
local _career_weapon_actions = mod:dofile(
	"scripts/mods/weapons_of_chaos/_lib_career_weapon_actions")
local _career_action_owner = "weapons_of_chaos"
local _audio_lib = mod:dofile("scripts/mods/weapons_of_chaos/_woc_blightreaper_audio")
local _pulse_lib = mod:dofile("scripts/mods/weapons_of_chaos/_woc_blightreaper_pulse")
mod._woc_resource_residency = mod:dofile(
	"scripts/mods/weapons_of_chaos/_lib_resource_residency")
local _spirits = mod:dofile("scripts/mods/weapons_of_chaos/_woc_blightreaper_spirits")
local _inventory_icons = mod:dofile("scripts/mods/weapons_of_chaos/_woc_inventory_icons")
local _relic_policy = mod:dofile("scripts/mods/weapons_of_chaos/_woc_relic_policy")
local _shared_relic_policy = mod:dofile(
	"scripts/mods/weapons_of_chaos/_woc_shared_relic")

-- Issue 822: trophy relics are inventory rewards, never customization inputs.
-- One presentation owner drives the native flags consumed by both mouse and
-- gamepad paths.  GUT already owns the two query hooks, so WOC must not register
-- competing hooks on those same class methods.
local _customization_rejection_seen = {}
local function _log_relic_customization_block(item)
	local backend_id = type(item) == "table"
		and (item.backend_id or item.ItemInstanceId or item.ItemId) or "unknown"
	local key = tostring(backend_id)
	if not _customization_rejection_seen[key] then
		_customization_rejection_seen[key] = true
		printf("[WOC:822] immutable relic customization disabled bid=%s",
			tostring(backend_id))
	end
end

mod:hook_safe("HeroWindowLoadoutConsole", "_equip_item_presentation",
		function(self, item, slot)
	local slot_index = type(slot) == "table" and slot.slot_index
	local widget = self._widgets_by_name and self._widgets_by_name.loadout_grid
	local content = widget and widget.content
	if slot_index and content then
		local suffix = "_" .. tostring(slot_index) .. "_1"
		local blocked = _relic_policy.blocks_customization(item)
		content["item" .. suffix .. "_disabled"] = blocked and true or nil
		local hotspot = content["customize_hotspot" .. suffix]
		if hotspot then
			hotspot.disable_button = blocked
			if blocked then hotspot.on_pressed = false end
		end
		if blocked then _log_relic_customization_block(item) end
	end
end)

_rt_register("issue822_relic_customization_policy", function()
	local relic = { data = { woc_unique_relic = true } }
	if not _relic_policy.blocks_customization(relic) then
		return "marked relic remained customizable"
	end
	if _relic_policy.blocks_customization({ data = { slot_type = "melee" } }) then
		return "ordinary melee weapon was blocked"
	end
end)
local _boss_weapon_catalog = mod:dofile(
	"scripts/mods/weapons_of_chaos/_woc_boss_weapon_catalog")
mod._woc_boss_catalog_snapshot = _boss_weapon_catalog.runtime_snapshot
mod:command("woc_boss_catalog",
	"Write the source-backed boss weapon catalogue to the console log",
	function()
		_boss_weapon_catalog.emit_runtime()
		_boss_weapon_catalog.emit_authored_runtime()
	end)
_rt_register("issue642_boss_weapon_catalog_source_mapped",
	_boss_weapon_catalog.runtime_check)

-- Automatic and bounded: seven rows once at WOC load. Re-run manually with
-- /woc_boss_catalog after entering a boss mission to compare residency.
_boss_weapon_catalog.emit_runtime()
_boss_weapon_catalog.emit_authored_runtime()
-- Issue 712 / 835: retail Stingray exposes Vector3 as a callable TABLE, but
-- the shared library's default api guards its stored constructor with
-- `type(...) == "function"`, so every position/scale channel silently
-- no-oped ("invalid-position"; Unit.set_local_pose never reached). Inject
-- the policy-built api whose vector constructor is a plain Lua closure. The
-- shared library copy itself stays canonical.
local _weapon_appearance = _appearance_lib.new(_appearance.appearance_api(_G))
_rt_register("issue712_appearance_vector_ctor_wrapped", function()
	local api = _appearance.appearance_api(_G)
	if api == nil then return "skip: Vector3 global unavailable" end
	if type(api.vector_new) ~= "function" then
		return "appearance_api did not wrap the Vector3 constructor in a function"
	end
	local ok, vec = pcall(api.vector_new, 1, 2, 3)
	if not ok or vec == nil then
		return "wrapped Vector3 constructor rejected plain numbers: " .. tostring(vec)
	end
	if type(api.vector_to_elements) ~= "function" then
		return "vector_to_elements member missing from injected api"
	end
	local ok_elems, x, y, z = pcall(api.vector_to_elements, vec)
	if not ok_elems or x ~= 1 or y ~= 2 or z ~= 3 then
		return string.format("constructed vector did not roundtrip (ok=%s %s,%s,%s)",
			tostring(ok_elems), tostring(x), tostring(y), tostring(z))
	end
end)
local _transform_diag_budget = 32
local _appearance_diag_budget = 32
local function _appearance_diag(format, ...)
	if _appearance_diag_budget <= 0 then return end
	_appearance_diag_budget = _appearance_diag_budget - 1
	pcall(printf, format, ...)
end
local function _unit_snapshot(unit, node)
	if not unit or not Unit.alive(unit) then return nil end
	node = type(node) == "number" and node or 0
	local ok_pos, position = pcall(Unit.local_position, unit, node)
	local ok_scale, scale = pcall(Unit.local_scale, unit, node)
	local ok_rot, rotation = pcall(Unit.local_rotation, unit, node)
	if not ok_pos or not ok_scale or not ok_rot then return nil end
	local ok_pe, px, py, pz = pcall(Vector3.to_elements, position)
	local ok_se, sx, sy, sz = pcall(Vector3.to_elements, scale)
	local ok_re, rx, ry, rz, rw = pcall(Quaternion.to_elements, rotation)
	if not ok_pe or not ok_se or not ok_re then return nil end
	return {
		position = { px, py, pz },
		scale = { sx, sy, sz },
		rotation = { rx, ry, rz, rw },
	}
end
local function _rotation_components(value)
	local rotation = _weapon_appearance.to_quaternion(value)
	if not rotation then return nil end
	local ok, x, y, z, w = pcall(Quaternion.to_elements, rotation)
	return ok and { x, y, z, w } or nil
end
local function _pose_text(snapshot)
	if type(snapshot) ~= "table" then return "unavailable" end
	local p, s, r = snapshot.position or {}, snapshot.scale or {}, snapshot.rotation or {}
	return string.format("p={%.3f,%.3f,%.3f} s={%.3f,%.3f,%.3f} q={%.4f,%.4f,%.4f,%.4f}",
		p[1] or 0, p[2] or 0, p[3] or 0,
		s[1] or 0, s[2] or 0, s[3] or 0,
		r[1] or 0, r[2] or 0, r[3] or 0, r[4] or 0)
end
local function _write_report_text(report)
	if type(report) ~= "table" then return "unavailable" end
	local channels = report.channels or {}
	return string.format("mode=%s ok=%s node=%s error=%s scale=%s position=%s offset=%s rotation=%s",
		tostring(report.transform_mode), tostring(report.ok),
		tostring(report.transform_node), tostring(report.transform_error),
		tostring(channels.scale), tostring(channels.position),
		tostring(channels.offset), tostring(channels.rotation))
end

-- The local dev tuner intentionally owns a non-identity edit, including a
-- one-shot /wt_dev_hp_apply while live apply is off. Yield only for that exact
-- channel/slot so WOC neither fights the tuner nor abandons the canonical pose when
-- the tool is merely installed or every tuner value is identity.
local function _dev_tuner_claims(record)
	if record.surface ~= "owner-spawn" then return false end
	local get_mod_fn = rawget(_G, "get_mod")
	if type(get_mod_fn) ~= "function" then return false end
	local ok_mod, wt = pcall(get_mod_fn, "wt_dev")
	if not ok_mod or type(wt) ~= "table" or type(wt.get) ~= "function" then
		return false
	end
	local function setting(key, fallback)
		local ok, value = pcall(wt.get, wt, key)
		-- Preserve an explicit false. The compact `and/or` form turns false into
		-- the fallback and would incorrectly report 3P tuner ownership when its
		-- perspective switch is disabled (the 3P fallback is true).
		if ok and value ~= nil then return value end
		return fallback
	end
	return _durable_transform_lib.dev_tuner_claims(record, setting)
end

local _transform_owner = _durable_transform_lib.new({
	alive = function(unit) return unit and Unit.alive(unit) end,
	read = _unit_snapshot,
	rotation_components = _rotation_components,
	apply = function(unit, spec) return _weapon_appearance.apply(unit, spec) end,
	should_track = _durable_transform_lib.should_track_surface,
	should_poll = _durable_transform_lib.should_poll_record,
	should_yield = _dev_tuner_claims,
	diagnostic = function(kind, record, before, after)
		if _transform_diag_budget <= 0 then return end
		_transform_diag_budget = _transform_diag_budget - 1
		pcall(printf,
			"[WOC:712] transform proof kind=%s surface=%s perspective=%s before=%s after=%s target=%s write={%s} durable=true node=%s node_name=%s",
			tostring(kind), tostring(record.surface), tostring(record.perspective),
			_pose_text(before), _pose_text(after), _pose_text(record.target),
			_write_report_text(record.write_report), tostring(record.node),
			tostring(_appearance.TRANSFORM_NODE_NAME))
	end,
})
local _wa = _pulse_lib.new(
	_appearance, _transform_owner, nil, mod._woc_resource_residency)

-- Issue 712 live pose tuner. The canonical numbers in M.TRANSFORM are the
-- sight-verified bake; this command lets the author dial a replacement pose on
-- the live weapon and paste the result back for a later bake. Mutates the
-- shared TRANSFORM table in place (future spawns pick it
-- up at apply time) and retargets every tracked unit from its stored
-- baseline so repeated calls never compound the offset.
local _POSE_CANONICAL = {
	scale = { _appearance.TRANSFORM.scale[1], _appearance.TRANSFORM.scale[2],
		_appearance.TRANSFORM.scale[3] },
	scale_1p = _appearance.TRANSFORM_1P and _appearance.TRANSFORM_1P.scale[1]
		or _appearance.TRANSFORM.scale[1],
	offset = { _appearance.TRANSFORM.offset[1], _appearance.TRANSFORM.offset[2],
		_appearance.TRANSFORM.offset[3] },
	rotation = { _appearance.TRANSFORM.rotation[1],
		_appearance.TRANSFORM.rotation[2], _appearance.TRANSFORM.rotation[3] },
}
local function _pose_set(x, y, z, rx, ry, rz, scale, scale_1p)
	local t = _appearance.TRANSFORM
	local t1p = _appearance.TRANSFORM_1P
	t.offset[1], t.offset[2], t.offset[3] = x, y, z
	t.rotation[1], t.rotation[2], t.rotation[3] = rx, ry, rz
	if scale then t.scale[1], t.scale[2], t.scale[3] = scale, scale, scale end
	if scale_1p and t1p then
		t1p.scale[1], t1p.scale[2], t1p.scale[3] = scale_1p, scale_1p, scale_1p
	end
	local retargeted, live = _transform_owner:retarget({
		scale = t.scale,
		scale_1p = t1p and t1p.scale or nil,
		offset = t.offset,
		rotation = t.rotation,
	})
	mod:echo("[WOC pose] offset={%.3f, %.3f, %.3f} rotation={%.1f, %.1f, %.1f} scale_3p=%.3f scale_1p=%.3f -- retargeted %d of %d live unit(s)",
		t.offset[1], t.offset[2], t.offset[3],
		t.rotation[1], t.rotation[2], t.rotation[3], t.scale[1],
		t1p and t1p.scale[1] or t.scale[1], retargeted, live)
	mod:echo("[WOC pose] bake line: /woc_pose %g %g %g %g %g %g %g %g",
		t.offset[1], t.offset[2], t.offset[3],
		t.rotation[1], t.rotation[2], t.rotation[3], t.scale[1],
		t1p and t1p.scale[1] or t.scale[1])
	pcall(printf, "[WOC:712] tuner set offset={%f,%f,%f} rotation={%f,%f,%f} scale_3p=%f scale_1p=%f retargeted=%d live=%d",
		t.offset[1], t.offset[2], t.offset[3],
		t.rotation[1], t.rotation[2], t.rotation[3], t.scale[1],
		t1p and t1p.scale[1] or t.scale[1], retargeted, live)
end
mod:command("woc_pose",
	"Live-tune the Blightreaper pose: /woc_pose x y z rx ry rz [scale_3p] [scale_1p] (meters, degrees)",
	function(x, y, z, rx, ry, rz, scale, scale_1p)
		local nx, ny, nz = tonumber(x), tonumber(y), tonumber(z)
		local nrx, nry, nrz = tonumber(rx), tonumber(ry), tonumber(rz)
		local nscale = scale ~= nil and tonumber(scale) or nil
		local nscale_1p = scale_1p ~= nil and tonumber(scale_1p) or nil
		if not (nx and ny and nz and nrx and nry and nrz)
				or (scale ~= nil and not nscale)
				or (scale_1p ~= nil and not nscale_1p) then
			local t = _appearance.TRANSFORM
			local t1p = _appearance.TRANSFORM_1P
			mod:echo("[WOC pose] usage: /woc_pose x y z rx ry rz [scale_3p] [scale_1p] -- current: /woc_pose %g %g %g %g %g %g %g %g",
				t.offset[1], t.offset[2], t.offset[3],
				t.rotation[1], t.rotation[2], t.rotation[3], t.scale[1],
				t1p and t1p.scale[1] or t.scale[1])
			return
		end
		_pose_set(nx, ny, nz, nrx, nry, nrz, nscale, nscale_1p)
	end)
mod:command("woc_pose_reset", "Restore the Blightreaper pose to the shipped canonical values", function()
	_pose_set(_POSE_CANONICAL.offset[1], _POSE_CANONICAL.offset[2],
		_POSE_CANONICAL.offset[3], _POSE_CANONICAL.rotation[1],
		_POSE_CANONICAL.rotation[2], _POSE_CANONICAL.rotation[3],
		_POSE_CANONICAL.scale[1], _POSE_CANONICAL.scale_1p)
end)
mod:command("woc_pose_audit",
	"Log the baked Blightreaper pose, live readback, and Weapon Tweaker tuner ownership",
	function()
		local t = _appearance.TRANSFORM
		local t1p = _appearance.TRANSFORM_1P
		local report = _transform_owner:audit(8)
		printf("[WOC:712] pose audit canonical offset={%.3f,%.3f,%.3f} rotation={%.1f,%.1f,%.1f} scale_3p={%.3f,%.3f,%.3f} scale_1p={%.3f,%.3f,%.3f} live=%d shown=%d truncated=%d",
			t.offset[1], t.offset[2], t.offset[3],
			t.rotation[1], t.rotation[2], t.rotation[3],
			t.scale[1], t.scale[2], t.scale[3],
			t1p.scale[1], t1p.scale[2], t1p.scale[3],
			report.live, #report.rows, report.truncated)
		for i, row in ipairs(report.rows) do
			printf("[WOC:712] pose audit row=%d surface=%s perspective=%s node=%s retained=%s wt_tuner_claims=%s current=%s target=%s write={%s}",
				i, tostring(row.surface), tostring(row.perspective),
				tostring(row.node), tostring(row.retained),
				tostring(row.tuner_claims), _pose_text(row.current),
				_pose_text(row.target), _write_report_text(row.write_report))
		end
		mod:echo("[WOC pose] audit logged: %d live unit(s), %d shown, %d truncated",
			report.live, #report.rows, report.truncated)
	end)
local _audio = type(_audio_lib) == "table" and type(_audio_lib.new) == "function"
	and _audio_lib.new() or {
		observe_spawn = function() end,
		start_inspect = function() end,
		finish_inspect = function() end,
		play_swing = function() end,
		stop_equipment = function() end,
		stop_all = function() end,
		update = function() end,
		probe_ambient = function() end,
		describe = function() end,
	}
mod._woc_inventory_icons = _inventory_icons
_cursed.install({
	Colors = rawget(_G, "Colors"),
	UISettings = rawget(_G, "UISettings"),
	RaritySettings = rawget(_G, "RaritySettings"),
	RarityIndex = rawget(_G, "RarityIndex"),
	ORDER_RARITY = rawget(_G, "ORDER_RARITY"),
	NetworkLookup = rawget(_G, "NetworkLookup"),
})
if type(_wire_policy) ~= "table" or type(_wire_policy.safe_item) ~= "function" then
	-- Packaging failures must not become startup crashes. Preserve ordinary
	-- vanilla loadout syncs, but fail closed for explicit WOC identities because
	-- sending one to a peer without WOC is a peer-fatal wire contract violation.
	printf("[WOC:595] wire policy unavailable; explicit woc_ loadout sync will fail closed")
	_wire_policy = {
		safe_item = function(item, _, _, _, protected_traits)
			local key = item and item.key
			local custom = item and item.CustomData
			local data = item and item.data
			local is_woc = type(key) == "string" and key:sub(1, 4) == "woc_"
				or item and item.woc_unique_relic == true
				or type(data) == "table" and data.woc_unique_relic == true
				or type(custom) == "table"
					and (custom.woc_unique_relic == true or custom.woc_unique_relic == "true")
			if is_woc then
				return nil
			end
			if type(item) == "table" and type(item.traits) == "table" then
				local kept, removed = {}, false
				for _, trait_key in ipairs(item.traits) do
					if protected_traits and protected_traits[trait_key] then removed = true
					else kept[#kept + 1] = trait_key end
				end
				if removed then
					local shadow = {}
					for field, value in pairs(item) do shadow[field] = value end
					shadow.traits = #kept > 0 and kept or nil
					return shadow
				end
			end
			return item
		end,
	}
end

local HELD_UNIT = _appearance.UNIT_1P
local INVENTORY_ICON = _inventory_icons.ICON

local _spirit_package_requested = false
local function _ensure_spirit_package()
	if _spirit_package_requested then return true end
	local package_name, reason = _spirits.package_contract(rawget(_G, "DLCSettings"))
	local packages = Managers and Managers.package
	if not package_name or not packages or type(packages.load) ~= "function" then
		printf("[WOC:643] Shyish package unavailable: %s", tostring(reason or "package_manager_missing"))
		return false
	end
	local ok, err = pcall(packages.load, packages, package_name,
		_spirits.PACKAGE_REFERENCE, nil, true, true)
	if not ok then
		printf("[WOC:643] Shyish package request failed: %s", tostring(err))
		return false
	end
	_spirit_package_requested = true
	mod:info("[WOC:643] requested source-backed Shyish package %s", package_name)
	return true
end

local function _release_spirit_package(reason)
	if not _spirit_package_requested then return true end
	local packages = Managers and Managers.package
	if not packages or type(packages.unload) ~= "function" then
		printf("[WOC:632] Shyish package release deferred reason=%s manager=missing",
			tostring(reason))
		return false
	end
	local ok, err = pcall(packages.unload, packages, _spirits.PACKAGE,
		_spirits.PACKAGE_REFERENCE)
	if not ok then
		printf("[WOC:632] Shyish package release failed reason=%s error=%s",
			tostring(reason), tostring(err))
		return false
	end
	_spirit_package_requested = false
	printf("[WOC:632] Shyish package released reason=%s", tostring(reason))
	return true
end
_ensure_spirit_package()

-- Package lookup aliases are forward-only. WOC-capable peers retain the
-- authored unit locally; peers without WOC continue decoding the vanilla sword
-- index and never receive a Workshop unit path.
local _appearance_alias_count = 0
local function _ensure_appearance_aliases()
	local installed = _appearance.install_network_package_aliases(
		NetworkLookup and NetworkLookup.inventory_packages)
	if installed > _appearance_alias_count then _appearance_alias_count = installed end
	return installed
end
_ensure_appearance_aliases()
-- Original display reference (documentation only — do NOT reference at runtime):
--   units/props/inn/hub_trophy/hub_trophy_bogenhafen
-- The Bögenhafen keep-trophy diorama prop. Not runtime-loadable today; when a
-- The actual sword was recovered from the mission level placement instead.

-- can_wield = every career of all five heroes. Base careers sourced from
-- scripts/settings/profiles/career_settings.lua; the five DLC careers verified
-- present in scripts/settings/ (es_questingknight / dr_engineer / we_thornsister
-- / wh_priest / bw_necromancer). The game gates equipping by DLC ownership
-- separately, so we list them all (CWV strips required_dlc the same way).
local _careers = {
	-- Markus Kruber (Empire Soldier)
	"es_mercenary", "es_huntsman", "es_knight", "es_questingknight",
	-- Bardin Goreksson (Dwarf Ranger)
	"dr_ironbreaker", "dr_ranger", "dr_slayer", "dr_engineer",
	-- Kerillian (Wood Elf)
	"we_waywatcher", "we_maidenguard", "we_shade", "we_thornsister",
	-- Victor Saltzpyre (Witch Hunter)
	"wh_zealot", "wh_bountyhunter", "wh_captain", "wh_priest",
	-- Sienna Fuegonasus (Bright Wizard)
	"bw_adept", "bw_scholar", "bw_unchained", "bw_necromancer",
}

-- ============================================================
-- Display names (global Localize is NOT fed by mod _localization.lua;
-- the inventory UI Localizes display_name/description/item_type keys).
-- ============================================================

local _display_names = {
	[ITEM_KEY .. "_name"]        = mod:localize("woc_blightreaper_name"),
	[ITEM_KEY .. "_description"] = mod:localize("woc_blightreaper_description"),
	[ITEM_KEY]                   = mod:localize("woc_blightreaper_name"),  -- item_type label
	[_cursed.DISPLAY_KEY]        = "Cursed",
	woc_intrinsic_crit_property  = mod:localize("woc_intrinsic_crit_property"),
	woc_power_vs_order_property  = mod:localize("woc_power_vs_order_property"),
	woc_poisoned_edge_trait = mod:localize("woc_poisoned_edge_trait"),
	description_woc_poisoned_edge_trait = mod:localize("description_woc_poisoned_edge_trait"),
	woc_shyish_health_curse_trait = mod:localize("woc_shyish_health_curse_trait"),
	description_woc_shyish_health_curse_trait = mod:localize("description_woc_shyish_health_curse_trait"),
}

local _spirit_runtime
local _relic_runtime = mod:dofile(
	"scripts/mods/weapons_of_chaos/_woc_relic_registration_owner").install(mod, {
		item_key = ITEM_KEY,
		backend_id = BACKEND_ID,
		base_weapon = BASE_WEAPON,
		held_unit = HELD_UNIT,
		inventory_icon = INVENTORY_ICON,
		template = TEMPLATE,
		careers = _careers,
		display_names = _display_names,
		moveset = _moveset,
		power = _power,
		cursed = _cursed,
		attack_order = _attack_order,
		chain_descriptor = _chain_descriptor,
		relic_policy = _relic_policy,
		inventory_icons = _inventory_icons,
		network_lookup = _network_lookup,
		career_weapon_actions = _career_weapon_actions,
		career_action_owner = _career_action_owner,
		rt_register = _rt_register,
		dbg = _dbg,
		ensure_appearance_aliases = _ensure_appearance_aliases,
		reset_appearance_diag = function() _appearance_diag_budget = 32 end,
		start_spirits = function()
			if _spirit_runtime then return _spirit_runtime:start() end
		end,
		stop_spirits = function(reason)
			if _spirit_runtime then return _spirit_runtime:stop(reason) end
		end,
		mark_poison = function(hit_unit, owner_unit)
			if _spirit_runtime then
				return _spirit_runtime:mark_poison(hit_unit, owner_unit)
			end
		end,
		owner_has_wielded_trait = function(unit, trait_key)
			return _spirit_runtime
				and _spirit_runtime:owner_has_wielded_trait(unit, trait_key) or false
		end,
	})

-- ============================================================
-- Wire-safety: never crash a non-WOC peer (issue 278 / issue 371)
-- ============================================================
-- WOC injects ITEM_KEY into NetworkLookup.item_names (a per-peer index-append, :191).
-- Equipping the Blightreaper fires LoadoutUtils.sync_loadout_slot -> the RPC encodes
-- item_id = NetworkLookup.item_names[item.key] onto rpc_sync_loadout_slot (both
-- directions + hot_join_sync). A peer WITHOUT WOC lacks that appended index and
-- cold-decodes it at loadout_utils.lua:72 -> the strict __index metamethod fatals
-- (network_lookup.lua:2362) -> every non-WOC peer CTDs. WOC cloned CWV's item
-- registration but not its net-safe hook (issue 422).
--
-- Fix: substitute a shadow item keyed to the vanilla BASE_WEAPON (a boot-stable index
-- every peer has) before the RPC encodes. Local state is untouched (the shadow lives
-- only for this call); remote loadout panels show the base weapon, consistent with what
-- the husk already renders (the clone keeps entry.name = BASE_WEAPON). Byte-identical to
-- CWV's issue-278 fix (character_weapon_variants.lua:10166). No skin/rarity axis to fix:
-- WOC applies no skin (weapon_skin_id "n/a"). Its local Cursed rarity is also
-- replaced with the vanilla promo id in the transient wire shadow.
--
-- Prefix-match "woc_" so EVERY present/future WOC item is crash-safe. All current items
-- clone BASE_WEAPON; if a future item clones a different base, resolve the base per-key
-- (mirror CWV's _find_def) so the wire shows the right weapon -- but crash-safety holds
-- regardless, since BASE_WEAPON is a universal vanilla index. LoadoutUtils is a plain
-- table -> table-form hook with a nil guard. Sole WOC hook on (LoadoutUtils,
-- sync_loadout_slot); other mods hook it from their own registrations (VMF chains fine).
-- Returns the item to actually put on the wire for `item`: the item UNCHANGED
-- for a non-WOC key; a shadow keyed to the boot-stable BASE_WEAPON for a "woc_"
-- key; or nil when the base index can't be resolved -- in which case the caller
-- MUST skip the send. A raw woc_ key must never be structurally reachable on the
-- wire (issue 422): if the base guard short-circuits, falling through to send the
-- woc_ key is the exact non-WOC-peer CTD this hook exists to prevent (issue 278).
-- The live item is never mutated (the shadow is a shallow copy).
local function _wire_safe_item(item)
	local base_resolvable = rawget(ItemMasterList, BASE_WEAPON)
		and NetworkLookup and NetworkLookup.item_names
		and rawget(NetworkLookup.item_names, BASE_WEAPON)
	return _wire_policy.safe_item(item, BASE_WEAPON, base_resolvable,
		_relic_policy.WIRE_RARITY, _WIRE_PROTECTED_TRAITS)
end

local _blightreaper_sync_seen = false
local _remote_blightreaper = {}
local _shared_relic_runtime, _issue613_runtime = _issue613.install({
	mod = mod, policy = _shared_relic_policy, preview_policy = _appearance,
	preview_appearance = _wa, transform_owner = _transform_owner, backend_id = BACKEND_ID, item_key = ITEM_KEY,
	remote_identity = _remote_blightreaper, rt_register = _rt_register,
})
_spirit_runtime = mod:dofile(
	"scripts/mods/weapons_of_chaos/_woc_spirit_runtime_owner").new({
		mod = mod,
		spirits = _spirits,
		power = _power,
		moveset = _moveset,
		remote_identity = _remote_blightreaper,
		backend_items = function() return _relic_runtime:backend_items() end,
		ensure_package = _ensure_spirit_package,
		rt_register = _rt_register,
	})
local function _husk_peer_id(owner_unit_3p)
	if not owner_unit_3p then return nil end
	local player
	pcall(function() player = Managers.player:owner(owner_unit_3p) end)
	return player and (player.peer_id or (player.network_id and player:network_id()))
end

local function _exact_relic_resolution(item_data, backend_id)
	if backend_id == BACKEND_ID or _power.is_relic(item_data) then return true end
	if not backend_id then return false end
	local items = _relic_runtime:backend_items()
	local live
	if items and type(items.get_item_from_id) == "function" then
		pcall(function() live = items:get_item_from_id(backend_id) end)
	end
	return _power.is_relic(live)
end

-- #613: the clone deliberately retains its vanilla item name for equip safety.
-- Resolve the exact immutable backend relic at the canonical unit-table
-- producer so keep/mission, owner/husk, and preview consumers all receive the
-- authored WOC unit before their spawn recipes branch. The durable owner then
-- applies and retains the atomic authored-render-node pose on returned units.
if rawget(_G, "BackendUtils") and BackendUtils.get_item_units then
	mod:hook(BackendUtils, "get_item_units",
		function(func, item_data, backend_id, skin, career_name)
			local item_units = func(item_data, backend_id, skin, career_name)
			local exact = _exact_relic_resolution(item_data, backend_id)
			if not exact or type(item_units) ~= "table" then return item_units end
			local before = item_units.right_hand_unit
			local _, changed = _appearance.canonicalize_item_units(item_units, true)
			_appearance_diag(
				"[WOC:613] canonical item units backend=%s career=%s before=%s after=%s skin=%s replay=%s",
				tostring(backend_id), tostring(career_name), tostring(before),
				tostring(item_units.right_hand_unit), tostring(item_units.skin or skin),
				tostring(changed))
			return item_units
		end)
end

local function _returned_unit_identity(unit)
	if not unit or not Unit.alive(unit) then return "nil-or-dead" end
	local debug_name, name_hash, mesh_node = "unavailable", "unavailable", "missing"
	if type(Unit.debug_name) == "function" then
		local ok, value = pcall(Unit.debug_name, unit)
		if ok then debug_name = tostring(value) end
	end
	if type(Unit.name_hash) == "function" then
		local ok, value = pcall(Unit.name_hash, unit)
		if ok then name_hash = tostring(value) end
	end
	if type(Unit.has_node) == "function" and type(Unit.node) == "function" then
		local ok_has, has = pcall(Unit.has_node, unit, "blightreaper")
		if ok_has and has then
			local ok_node, value = pcall(Unit.node, unit, "blightreaper")
			mesh_node = ok_node and tostring(value) or "lookup-rejected"
		end
	end
	return string.format("debug=%s hash=%s mesh_node=%s",
		debug_name, name_hash, mesh_node)
end

local _unit_shape_seen = {}
local function _mesh_name(unit, index)
	if type(Unit.mesh_name) == "function" then
		local ok, value = pcall(Unit.mesh_name, unit, index)
		if ok and value ~= nil then return tostring(value) end
	end
	if type(Unit.mesh) == "function" then
		local ok, value = pcall(Unit.mesh, unit, index)
		if ok and value ~= nil then return tostring(value) end
	end
	return "unavailable"
end

local function _unit_shape_summary(unit)
	if not unit or not Unit.alive(unit) then return "nil-or-dead" end
	local scene_count, parents, meshes = "unavailable", {}, {}
	if type(Unit.num_scene_graph_items) == "function" then
		local ok, count = pcall(Unit.num_scene_graph_items, unit)
		if ok and type(count) == "number" then
			scene_count = tostring(count)
			if type(Unit.scene_graph_parent) == "function" then
				for i = 0, math.min(count - 1, 7) do
					local ok_parent, parent = pcall(Unit.scene_graph_parent, unit, i)
					parents[#parents + 1] = string.format("%d>%s", i,
						tostring(ok_parent and parent or "err"))
				end
			end
		end
	end
	if type(Unit.num_meshes) == "function" then
		local ok, count = pcall(Unit.num_meshes, unit)
		if ok and type(count) == "number" then
			for i = 0, math.min(count - 1, 5) do
				meshes[#meshes + 1] = string.format("%d:%s", i, _mesh_name(unit, i))
			end
		end
	end
	local node_name = tostring(_appearance.TRANSFORM_NODE_NAME)
	local has_node = "api-missing"
	if type(Unit.has_node) == "function" then
		local ok, value = pcall(Unit.has_node, unit, node_name)
		has_node = tostring(ok and value or "err")
	end
	return string.format("scene_count=%s parents=[%s] has_%s=%s meshes=[%s]",
		scene_count, table.concat(parents, ","),
		node_name, has_node, table.concat(meshes, ","))
end

local function _log_unit_shape_once(surface, perspective, unit)
	local key = tostring(surface) .. ":" .. tostring(perspective)
	if _unit_shape_seen[key] then return end
	_unit_shape_seen[key] = true
	_appearance_diag("[WOC:712] unit census surface=%s perspective=%s %s",
		tostring(surface), tostring(perspective), _unit_shape_summary(unit))
end

-- Remote husks resolve the intentionally vanilla wire item. Re-key the render
-- unit only when the WOC sideband positively identifies this peer+slot. Passing
-- a shallow item-data shadow with a WOC name prevents another variant mod from
-- reinterpreting the same base-sword echo after our decision.
mod:hook("GearUtils", "spawn_inventory_unit", function(func, world, hand, item_template,
		item_units, slot_name, item_data, owner_unit_1p, owner_unit_3p, ...)
	if not owner_unit_1p and hand == "right" then
		local peer_id = _husk_peer_id(owner_unit_3p)
		local active = peer_id and _remote_blightreaper[peer_id]
		active = active and active[slot_name]
		if active and type(item_units) == "table" then
			local unit_shadow = {}
			for key, value in pairs(item_units) do unit_shadow[key] = value end
			item_units = unit_shadow
			item_units.right_hand_unit = HELD_UNIT
			if type(item_data) == "table" then
				local shadow = {}
				for key, value in pairs(item_data) do shadow[key] = value end
				shadow.name = ITEM_KEY
				item_data = shadow
			end
		end
	end
	local is_blightreaper = hand == "right" and type(item_units) == "table"
		and item_units.right_hand_unit == HELD_UNIT
	local unit_3p, ammo_3p, unit_1p, ammo_1p = func(world, hand, item_template,
		item_units, slot_name, item_data, owner_unit_1p, owner_unit_3p, ...)
	if is_blightreaper then
		local surface = _durable_transform_lib.classify_surface(
			owner_unit_1p, owner_unit_3p)
		-- Issue 613: vanilla returns weapon_3p, ammo_3p ONLY when owner_unit_1p
		-- is nil (gear_utils.lua:276); husks always pass a nil 1P rig
		-- (simple_husk_inventory_extension.lua:319). Report the absent husk /
		-- preview 1P unit as the source contract; reserve "nil-or-dead" for an
		-- owner spawn (gear_utils.lua:273) that really owes a live 1P unit.
		local expects_1p = _durable_transform_lib.expects_first_person_unit(owner_unit_1p)
		_appearance_diag(
			"[WOC:613] spawn identity surface=%s requested_1p=%s requested_3p=%s returned_1p={%s} returned_3p={%s}",
			tostring(surface), tostring(item_units.right_hand_unit),
			tostring(_appearance.UNIT_3P),
			(expects_1p or unit_1p ~= nil) and _returned_unit_identity(unit_1p)
				or "not-expected vanilla-3p-only gear_utils.lua:276",
			_returned_unit_identity(unit_3p))
		_log_unit_shape_once(surface, "3p", unit_3p)
		_wa.apply(unit_3p, _appearance.transform_for("3p"), "3p", surface)
		if unit_1p then
			_log_unit_shape_once(surface, "1p", unit_1p)
			_wa.apply(unit_1p, _appearance.transform_for("1p"), "1p", surface)
		end
		_audio.observe_spawn(unit_3p, unit_1p, owner_unit_1p, owner_unit_3p)
		-- #922: custom weapon units spawned after the player's initial fade
		-- extension census must be explicitly enrolled. The adapter combines
		-- this unit with every current 3P inventory/cosmetic unit and dedupes
		-- repeated lifecycle replays.
		_appearance_fade:enroll(owner_unit_3p,
			owner_unit_1p and "owner_spawn" or "remote_husk_spawn", {
				extra_units = { unit_3p, ammo_3p },
			})
	end
	return unit_3p, ammo_3p, unit_1p, ammo_1p
end)

-- #922: the husk spawn-path enrollment above runs INSIDE vanilla wield, but
-- vanilla then calls `_reapply_fade` (simple_husk_inventory_extension.lua:319
-- then :353), replacing the fade system's linked set with only the four
-- inventory fields (simple_husk_inventory_extension.lua:292-311) and evicting
-- WOC's snapshot; the adapter's fingerprint dedup would then report
-- "unchanged" and skip every later re-apply. Re-enroll AFTER the native
-- replacement with force=true (the proven Cosmetics pattern,
-- _cos_appearance_fade_runtime.lua), gated on the same positive sideband
-- identity as the spawn re-key. Pre-flight (CLAUDE.md NON-NEGOTIABLE #8):
-- this is the sole hook on (SimpleHuskInventoryExtension, _reapply_fade) --
-- and the sole SimpleHuskInventoryExtension hook of any kind -- in WOC.
mod:hook("SimpleHuskInventoryExtension", "_reapply_fade", function(func, self, equipment)
	local result = func(self, equipment)
	local peer_id = _husk_peer_id(self and self._unit)
	local active = peer_id and _remote_blightreaper[peer_id]
	if active and next(active) then
		_appearance_fade:enroll(self and self._unit, "remote_husk_reapply", {
			inventory_extension = self,
			equipment = equipment,
			force = true,
		})
	end
	return result
end)

-- Owner/bot inventory has no husk-style fade replay. Enroll the final wielded
-- fields after vanilla has committed them, not only while the unit is spawned.
mod:hook("SimpleInventoryExtension", "_wield_slot", function(func, self,
		equipment, slot_data, unit_1p, unit_3p, buff_extension)
	local result = func(self, equipment, slot_data, unit_1p, unit_3p, buff_extension)
	if slot_data and _power.is_relic(slot_data.item_data) then
		_appearance_fade:enroll(self._unit,
			self.is_bot and "bot_wield" or "owner_wield", {
				inventory_extension = self, equipment = equipment,
			})
	end
	return result
end)

-- #633: ActionInspect is the exact action used by the cloned Crowbill graph
-- (`1h_crowbills.lua:1479` binds ActionTemplates.action_inspect verbatim).
-- Attach the boot-resident ritual-skull whisper only to a positively tracked
-- local WOC 1P unit. The helper owns and stops only its returned playing id.
mod:hook("ActionInspect", "client_owner_start_action", function(func, self, ...)
	local result = func(self, ...)
	_audio.start_inspect(self)
	return result
end)

mod:hook("ActionInspect", "finish", function(func, self, reason, ...)
	_audio.finish_inspect(self, reason or "inspect-finish")
	return func(self, reason, ...)
end)

-- The custom Blightreaper unit has no inherited weapon flow graph. Recreate
-- the exact two Executioner Sword flow outcomes at the same native action
-- seams that emit `sfx_swing_charge` and `sfx_swing_started`.
mod:hook("ActionMeleeStart", "client_owner_start_action",
	function(func, self, new_action, ...)
		local result = func(self, new_action, ...)
		_audio.play_swing(self, "charge")
		return result
	end)

local _cleave_diag_budget = 4
mod:hook("ActionSweep", "client_owner_start_action",
	function(func, self, new_action, ...)
		local result = func(self, new_action, ...)
		local cleave_applied, cleave_reason = _moveset.apply_runtime_cleave(
			self, new_action)
		if cleave_applied and _cleave_diag_budget > 0 then
			_cleave_diag_budget = _cleave_diag_budget - 1
			pcall(printf, "[WOC:632] combat sweep cleave=%.2fx attack=%.2f impact=%.2f",
				_moveset.CLEAVE_MULTIPLIER, self._max_targets_attack,
				self._max_targets_impact)
		elseif not cleave_applied and cleave_reason ~= "foreign_action"
				and _cleave_diag_budget > 0 then
			_cleave_diag_budget = _cleave_diag_budget - 1
			pcall(printf, "[WOC:632] combat sweep cleave skipped reason=%s",
				tostring(cleave_reason))
		end
		_audio.play_swing(self, "release")
		return result
	end)

-- Equipment destruction is an independent edge from ActionInspect.finish on
-- level transitions and forced inventory teardown. Merge here as the sole WOC
-- hook on (GearUtils, destroy_equipment).
mod:hook("GearUtils", "destroy_equipment", function(func, world, equipment, ...)
	_audio.stop_equipment(equipment, "equipment-destroy")
	return func(world, equipment, ...)
end)

mod:command("woc_audio_contract",
	"Log Blightreaper inspect and ambient audio provenance",
	function() _audio.describe() end)

mod:command("woc_audio_probe",
	"Probe the native keep-trophy event for 8 seconds (maximum 3 runs)",
	function() _audio.probe_ambient() end)

mod.update = function(dt)
	_transform_owner:step()
	_audio.update(dt)
	_shared_relic_runtime:update(dt)
	_spirit_runtime:update(dt)
end

mod.on_game_state_changed = function(status, state_name)
	_shared_relic_runtime:on_game_state_changed(status, state_name)
	if status == "exit" then
		_transform_owner:clear()
		_audio.stop_all("game-state-exit:" .. tostring(state_name))
	end
end

mod.on_enabled = function()
	_shared_relic_runtime:on_enabled("mod-enabled")
	_ensure_spirit_package()
	if _relic_runtime:is_registered() then _spirit_runtime:start() end
end

mod.on_disabled = function()
	_spirit_runtime:stop("mod-disabled")
	_release_spirit_package("mod-disabled")
	_transform_owner:clear()
	_audio.stop_all("mod-disabled")
	_shared_relic_runtime:reset("mod-disabled")
end

mod.on_unload = function()
	_spirit_runtime:stop("mod-unload")
	_release_spirit_package("mod-unload")
	_transform_owner:clear()
	_audio.stop_all("mod-unload")
	_shared_relic_runtime:reset("mod-unload")
end

-- Issue 278/613: the fail-safe skip below fires with `key nil` many times per
-- session (79 hits across the 24 logs of 2026-07-18) and the caller is still
-- unnamed. A nil item would also crash vanilla (`item.key` deref,
-- loadout_utils.lua:21), so the skip stays; this probe only NAMES the source.
-- debug.traceback capped to 3 caller frames, deduplicated per (shape, slot,
-- frames), hard-capped at 8 lines per session, printf log-only.
local _skip_caller_seen = {}
local _skip_caller_budget = 8
local function _log_skip_caller(item, slot_name)
	if _skip_caller_budget <= 0 then return end
	local frames = "traceback-unavailable"
	local dbg = rawget(_G, "debug")
	if type(dbg) == "table" and type(dbg.traceback) == "function"
			and type(_wire_policy.caller_frames) == "function" then
		local ok, trace = pcall(dbg.traceback, "", 2)
		local named = ok and _wire_policy.caller_frames(trace,
			{ "weapons_of_chaos", "vmf/modules", "[C]" }, 3)
		if named then frames = named end
	end
	local shape = item == nil and "nil-item"
		or type(item) ~= "table" and ("non-table-" .. type(item))
		or (item.key == nil and "table-without-key" or "key=" .. tostring(item.key))
	local dedup = shape .. "|" .. tostring(slot_name) .. "|" .. frames
	if _skip_caller_seen[dedup] then return end
	_skip_caller_seen[dedup] = true
	_skip_caller_budget = _skip_caller_budget - 1
	pcall(printf, "[WOC:278] skip caller item=%s slot=%s frames=%s chat=false",
		shape, tostring(slot_name), frames)
end

if rawget(_G, "LoadoutUtils") and LoadoutUtils.sync_loadout_slot then
	mod:hook(LoadoutUtils, "sync_loadout_slot", function(func, player, slot_name, item, sync_to_specific_peer_id)
		local is_blightreaper = _power.is_relic(item)
		_shared_relic_runtime:observe_loadout_sync(
			player, slot_name, is_blightreaper)
		if is_blightreaper then
			_blightreaper_sync_seen = true
		end
		local send_item = _wire_safe_item(item)
		if send_item == nil then
			-- Only a woc_ item with an unresolvable base reaches here. Skipping the
			-- sync is the sole crash-safe move (substituting can't help: the base
			-- itself isn't in NetworkLookup, and sending woc_ raw CTDs non-WOC peers).
			-- Mirrors CWV's skip branch (character_weapon_variants.lua:10183-10188).
			printf("[WOC:278] base '%s' unresolvable for woc_ key %s; SKIPPING loadout sync (fail-safe, issue 422)",
				BASE_WEAPON, tostring(item and item.key))
			_log_skip_caller(item, slot_name)
			return
		end
		if send_item ~= item then
			printf("[WOC:278] sync_loadout_slot net-safe: %s -> %s (slot=%s)",
				tostring(item.key), tostring(send_item.key), tostring(slot_name))
		end
		local result_n, results
		local function capture(...)
			result_n = select("#", ...)
			results = { ... }
		end
		capture(func(player, slot_name, send_item, sync_to_specific_peer_id))
		return unpack(results, 1, result_n)
	end)
end

-- issue 422 / class-31 regression: a woc_ item must never leave a woc_ key on the
-- wire. Registered here because `_wire_safe_item` is a file-local defined just
-- above. Asserts the hook target exists (install precondition) and that a fake
-- woc_ item pushed through the substitution yields no woc_ key/ItemId and does
-- not mutate the live item.
_rt_register("wire_woc_never_leaves_woc_key", function()
	if not (rawget(_G, "LoadoutUtils") and type(LoadoutUtils.sync_loadout_slot) == "function") then
		return "LoadoutUtils.sync_loadout_slot missing -- wire hook cannot install"
	end
	local fake = {
		key = "woc_test", ItemId = "woc_test", power_level = 600,
		rarity = "cursed", properties = { woc_power_vs_order = 1 },
		traits = { "woc_future_trait" },
	}
	local out = _wire_safe_item(fake)
	-- The native base + lookup are boot data, so a live game must produce the
	-- exact vanilla-keyed shadow. nil remains reserved for a genuinely broken
	-- base lookup and may not masquerade as passing verification.
	if out == nil then
		return "base sword is not wire-resolvable -- WOC sync would be skipped"
	end
	if out.key ~= BASE_WEAPON or out.ItemId ~= BASE_WEAPON then
		return string.format("expected exact base identity %s, got key=%s ItemId=%s",
			BASE_WEAPON, tostring(out.key), tostring(out.ItemId))
	end
	if out.rarity ~= _relic_policy.WIRE_RARITY or fake.rarity ~= _relic_policy.RARITY then
		return "Cursed rarity did not degrade to promo on the shadow only"
	end
	if out.properties ~= nil or out.traits ~= nil then
		return "WOC-only properties/traits remained on the wire shadow"
	end
	if fake.key ~= "woc_test" or fake.ItemId ~= "woc_test" then
		return "live item was mutated -- shadow must be a copy"
	end
	if not (fake.properties and fake.properties.woc_power_vs_order == 1)
			or not (fake.traits and fake.traits[1] == "woc_future_trait") then
		return "live WOC properties/traits were mutated by wire substitution"
	end
end)

_rt_register("issue509_registered_blightreaper_wire_contract", function()
	if not mod:get("enable_blightreaper") then
		return "skip: Blightreaper setting is disabled"
	end
	if not _relic_runtime:is_registered() then
		return "Blightreaper did not register -- check MoreItemsLibrary load order"
	end

	local entry = rawget(ItemMasterList, ITEM_KEY)
	if not entry then return "registered WOC ItemMasterList row is missing" end
	if entry.key ~= BASE_WEAPON or entry.name ~= BASE_WEAPON then
		return string.format("registered clone lost inherited base identity: key=%s name=%s",
			tostring(entry.key), tostring(entry.name))
	end

	local names = NetworkLookup and NetworkLookup.item_names
	local woc_id = names and rawget(names, ITEM_KEY)
	if type(woc_id) ~= "number" or rawget(names, woc_id) ~= ITEM_KEY then
		return "WOC NetworkLookup.item_names pair is not symmetric"
	end

	local items = Managers.backend and Managers.backend:get_interface("items")
	local live = items and items:get_item_from_id(BACKEND_ID)
	if not live then return "registered Blightreaper backend item is missing" end
	if live.key ~= BASE_WEAPON or live.ItemId ~= BASE_WEAPON then
		return string.format("backend item is not vanilla-wire keyed: key=%s ItemId=%s",
			tostring(live.key), tostring(live.ItemId))
	end
	local wire = _wire_safe_item(live)
	if type(wire) ~= "table" or wire == live or wire.key ~= BASE_WEAPON
			or wire.rarity ~= _relic_policy.WIRE_RARITY then
		return "Cursed live Blightreaper did not produce a vanilla promo wire shadow"
	end
	if wire.properties ~= nil or wire.traits ~= nil then
		return "Blightreaper wire shadow retained mod-only properties/traits"
	end
	if live.rarity ~= _relic_policy.RARITY then
		return "wire substitution mutated the local Cursed rarity"
	end
	if not _blightreaper_sync_seen then
		return "skip: equip Blightreaper once, then rerun for live hook evidence"
	end
end)

_rt_register("issue690_blightreaper_registration_gate_contract", function()
	if not mod:get("enable_blightreaper") then
		return "skip: Blightreaper setting is disabled"
	end
	local registration = _relic_runtime:registration_state()
	if not registration.registered then
		return string.format("registration deferred at gate=%s reason=%s attempts=%d",
			tostring(registration.gate), tostring(registration.reason),
			registration.attempts)
	end
	if registration.gate ~= "registered" then
		return "registered flag and registration gate state disagree"
	end
	local _moveset_report = _relic_runtime:moveset_report()
	local identity = _moveset_report and _moveset_report.career_action_identity
	if not (identity and identity.ok) then
		return "inherited career-action identity was not reconciled"
	end
	local abilities = _moveset_report and _moveset_report.ability_actions
	if not (abilities and abilities.ok) then
		return "career-action ownership was not installed"
	end
	if #(abilities.conflicting_names or {}) > 0 then
		return "career-action ownership retained a provider conflict"
	end
	if not rawget(ItemMasterList, ITEM_KEY) then
		return "registered Blightreaper ItemMasterList row is missing"
	end
end)

-- issue 509 backfill: two more locks on the wire-safety row-of-concern plus the
-- keep-entry force-load dead end. Registered here beside `_wire_safe_item` (a
-- file-local just above). See ENGINE_SURFACE.md "Wire safety" + "dead ends".
_rt_register("issue422_wire_safety_unconditional_singleton", function()
	-- The sender-side wire-safety hook on (LoadoutUtils, sync_loadout_slot) must
	-- be UNCONDITIONAL (never toggle-gated) and SINGLE (VMF silently drops a 2nd
	-- hook on the same Class.method). Prefix classification is runtime-testable
	-- even in retail; the singleton remains a source-pattern guard on THIS file (path via
	-- debug.getinfo on the file-local _rt_register); needles split so this check
	-- never self-matches; no-op when source is unreadable (deploy/bundle paths).
	if not _wire_policy.is_woc_key("woc_future_weapon")
		or _wire_policy.is_woc_key(BASE_WEAPON) then
		return "issue 422 regression: unconditional woc_ prefix classification changed"
	end
	local ok, info = pcall(debug.getinfo, _rt_register, "S")
	if not ok or type(info) ~= "table" or not info.source then return end
	local src_path = info.source:sub(1, 1) == "@" and info.source:sub(2) or info.source
	local txt = _rt_src_read(src_path)  -- (#511) io-safe; nil in retail sandbox => skip
	if not txt then return end
	local hook_needle = "mod:hook(LoadoutUtils, " .. '"sync_loadout_slot"'
	local count, pos = 0, 1
	while true do
		local s = txt:find(hook_needle, pos, true)
		if not s then break end
		count = count + 1
		pos = s + 1
	end
	if count == 0 then
		return "issue 422 regression: the (LoadoutUtils, sync_loadout_slot) wire-safety hook is gone -- non-WOC peers CTD"
	end
	if count > 1 then
		return "issue 422 regression: duplicate (LoadoutUtils, sync_loadout_slot) hook -- VMF drops the 2nd silently"
	end
end)

_rt_register("wire_non_woc_item_passthrough_identity", function()
	-- Wire safety must NEVER touch a vanilla (non-woc_) item: _wire_safe_item
	-- returns the SAME table identity unchanged for a non-woc_ key. Complements
	-- wire_woc_never_leaves_woc_key (which covers the woc_ substitution path).
	local vanilla = { key = BASE_WEAPON, ItemId = BASE_WEAPON, power_level = 300 }
	local out = _wire_safe_item(vanilla)
	if out ~= vanilla then
		return "a non-woc_ item was not passed through by identity -- wire guard is mutating vanilla loadout items"
	end
end)

_rt_register("no_unit_path_package_force_load", function()
	-- Keep-entry C-fatal dead end (DEVELOPMENT.md crash post-mortem + file header):
	-- Managers.package:load on a UNIT path (not a real .package name) hard-crashes
	-- on keep entry via the engine resource_package() C-fatal, bypassing pcall. WOC
	-- The Shyish fix loads one hash-verified real package NAME from DLCSettings;
	-- the unit path itself must remain structurally unable to reach load().
	local ok, info = pcall(debug.getinfo, _rt_register, "S")
	if not ok or type(info) ~= "table" or not info.source then return end
	local src_path = info.source:sub(1, 1) == "@" and info.source:sub(2) or info.source
	local txt = _rt_src_read(src_path)  -- (#511) io-safe; nil in retail sandbox => skip
	if not txt then return end
	local unsafe_needle = "load(_spirits.UNIT"
	if txt:find(unsafe_needle, 1, true) then
		return "Shyish unit path reached PackageManager load -- keep-entry C-fatal"
	end
end)

_rt_register("issue613_blightreaper_appearance_contract", function()
	if HELD_UNIT ~= "units/woc_blightreaper/blightreaper" then
		return "Blightreaper item no longer points at the authored WOC unit"
	end
	if _appearance.UNIT_3P ~= HELD_UNIT .. "_3p" then
		return "explicit 3P sibling contract drifted"
	end
	if _appearance_alias_count ~= 2 then
		return string.format("expected two forward inventory-package aliases, got %s",
			tostring(_appearance_alias_count))
	end
	local durable = _durable_transform_lib.CONTRACT
	if not durable or durable.attachment_node ~= 0
			or durable.target_node ~= "authored_render_node"
			or durable.target_node_name ~= _appearance.TRANSFORM_NODE_NAME
			or durable.position ~= "render_baseline_plus_offset"
			or durable.scale ~= "render_baseline_multiplier"
			or durable.rotation ~= "absolute_euler_xyz"
			or durable.write_mode ~= "atomic_local_pose"
			or durable.gameplay ~= "retained_check_then_reapply"
			or durable.preview ~= "weak_record_event_reapply"
			or durable.transport ~= "none" then
		return "durable transform-retention contract drifted"
	end
	local issue613_error = _issue613_runtime:contract_error()
	if issue613_error then return issue613_error end
	local probe = { right_hand_unit = BASE_WEAPON, left_hand_unit = "unexpected" }
	local same, changed = _appearance.canonicalize_item_units(probe, true)
	if same ~= probe or changed ~= true or probe.right_hand_unit ~= HELD_UNIT
			or probe.left_hand_unit ~= nil then
		return "canonical item-unit replay contract drifted"
	end
	local ok_1p, resident_1p = pcall(Application.can_get, "unit", HELD_UNIT)
	local ok_3p, resident_3p = pcall(Application.can_get, "unit", _appearance.UNIT_3P)
	if not ok_1p or resident_1p ~= true then return "authored 1P unit is not resident" end
	if not ok_3p or resident_3p ~= true then return "authored 3P unit is not resident" end
	for _, perspective in ipairs({ "1p", "3p" }) do
		local descriptor = _appearance.pulse_descriptor(perspective)
		local ok_material, material_ready = pcall(
			Application.can_get, "material", descriptor.material)
		if not ok_material or material_ready ~= true then
			return string.format("%s pulse donor material is not resident: %s",
				perspective, tostring(descriptor.material))
		end
		if #descriptor.textures ~= 6 or #descriptor.variables ~= 3 then
			return string.format("%s pulse descriptor is not bounded 6-texture/3-variable shape",
				perspective)
		end
		for _, binding in ipairs(descriptor.textures) do
			local ok_texture, texture_ready = pcall(
				Application.can_get, "texture", binding.texture)
			if not ok_texture or texture_ready ~= true then
				return string.format("%s pulse texture is not resident: %s",
					perspective, tostring(binding.texture))
			end
		end
	end
end)

_rt_register("issue633_blightreaper_audio_contract", function()
	if type(_audio_lib) ~= "table" or type(_audio_lib.new) ~= "function" then
		return "Blightreaper audio helper is unavailable"
	end
	if _audio_lib.INSPECT_EVENT ~= "nds_skull_inspect"
			or _audio_lib.INSPECT_BANK ~= "wwise/event_geheimnisnacht"
			or _audio_lib.INSPECT_PACKAGE
				~= "resource_packages/dlcs/geheimnisnacht_2021" then
		return "ritual-skull inspect event/bank/package evidence drifted"
	end
	if _audio_lib.AMBIENT_EVENT ~= "emitter_trophy_evil_sword"
			or _audio_lib.AMBIENT_BANK ~= "wwise/level_hub" then
		return "keep-trophy ambient event/bank evidence drifted"
	end
	if _audio_lib.SWING_EVENT ~= "sword_2h_swing"
			or _audio_lib.CHARGE_EVENT ~= "rare_sword_2h_charge_swing_execution"
			or _audio_lib.SWING_BANK ~= _moveset.EXECUTIONER_WWISE_DEP then
		return "Executioner Sword swing/charge audio evidence drifted"
	end
	local package_manager = Managers and Managers.package
	if package_manager and type(package_manager.has_loaded) == "function" then
		local ok, loaded = pcall(package_manager.has_loaded, package_manager,
			_audio_lib.INSPECT_PACKAGE, "boot")
		if ok and loaded ~= true then
			return "boot-owned ritual-skull inspect package is not loaded"
		end
	end
end)

mod._woc_trait_api = {
	capability = "woc.poison_trait.v1",
	trait_key = _moveset.POISON_TRAIT,
	category = "melee",
	is_available = function()
		if type(mod.is_enabled) ~= "function" then return true end
		local ok, enabled = pcall(mod.is_enabled, mod)
		return ok and enabled == true
	end,
}

-- CIM owns the selection/persistence surface; WOC owns the trait row and proc.
-- VMF calls this after every main file has run, so either launcher load order
-- reaches the same capability handshake. Missing CIM is a normal no-op.
local _previous_on_all_mods_loaded = mod.on_all_mods_loaded
mod.on_all_mods_loaded = function(...)
	if _previous_on_all_mods_loaded then _previous_on_all_mods_loaded(...) end
	-- The reusable poison trait is a WOC capability, not contingent on the
	-- Blightreaper acquisition toggle. Install its local row/proc before CIM
	-- evaluates the provider contract.
	local rows_ok, rows_reason = _moveset.install_intrinsic_trait_rows(
		rawget(_G, "WeaponTraits"), rawget(_G, "BuffTemplates"))
	local poison_ok, poison_reason = _relic_runtime:install_poison()
	if not rows_ok or not poison_ok then
		printf("[WOC:655] reusable poison capability unavailable: rows=%s poison=%s",
			tostring(rows_reason), tostring(poison_reason))
		return
	end
	local cim = get_mod("cim_dev") or get_mod("cim")
	if not cim or type(cim._cim_register_external_trait_provider) ~= "function" then
		mod:info("[WOC:655] CIM trait capability absent; Poisoned Edge remains intrinsic")
		return
	end
	local ok, installed, reason = pcall(cim._cim_register_external_trait_provider,
		"WOC", mod._woc_trait_api)
	if not ok or not installed then
		printf("[WOC:655] CIM trait registration failed: %s",
			tostring(ok and reason or installed))
		return
	end
	mod:info("[WOC:655] CIM Poisoned Edge capability active (%s)", tostring(reason))
end

_rt_register("issue655_blightreaper_trait_contract", function()
	local weapon_traits = rawget(_G, "WeaponTraits")
	local traits = weapon_traits and weapon_traits.traits
	local poison = traits and rawget(traits, _moveset.POISON_TRAIT)
	local curse = traits and rawget(traits, _moveset.SHYISH_CURSE_TRAIT)
	if not poison or poison.buff_name ~= _moveset.POISON_BUFF_TEMPLATE then
		return "Poisoned Edge row does not own the Hagbane proc buff"
	end
	if not curse or curse.icon ~= _moveset.SHYISH_CURSE_ICON
			or curse.crafting_disabled ~= true then
		return "intrinsic Shyish curse row/icon contract drifted"
	end
	local items = _relic_runtime:backend_items()
	local live = items and items:get_item_from_id(BACKEND_ID)
	if live and (not _moveset.item_has_trait(live, _moveset.POISON_TRAIT)
			or not _moveset.item_has_trait(live, _moveset.SHYISH_CURSE_TRAIT)) then
		return "live Blightreaper is missing one intrinsic trait"
	end
	local lookup = NetworkLookup and NetworkLookup.traits
	if lookup and (rawget(lookup, _moveset.POISON_TRAIT)
			or rawget(lookup, _moveset.SHYISH_CURSE_TRAIT)) then
		return "WOC-only trait key entered NetworkLookup.traits"
	end
end)

-- Load banners (§3.6, ct model): the pcall(printf) line below is the
-- log-provable banner - engine printf survives VMF mod logging OFF, so pinned
-- live-test cards key on "[WOC:LOAD]". The mod:info line is operational
-- telemetry visible only with mod logging ON.
pcall(printf, "[WOC:LOAD] v%s enabled fp=%s OK", MOD_VERSION, _settings_fingerprint())
mod:info("[WOC] enabled v%s settings_fp=%s (Blightreaper)", MOD_VERSION, _settings_fingerprint())

-- Per PROJECT_STANDARDS § 3.6 + § 14a: dev/alpha/beta/0.x versions print version
-- to chat on load so the user can see what's active. Stable (>=1.0.0) stays silent.
if MOD_VERSION:find("-dev$") or MOD_VERSION:find("-alpha$") or MOD_VERSION:find("-beta$") or MOD_VERSION:find("-rc%d*$") or MOD_VERSION:find("^0%.") then
	mod:echo(string.format("[WOC] v%s loaded", MOD_VERSION))
end
