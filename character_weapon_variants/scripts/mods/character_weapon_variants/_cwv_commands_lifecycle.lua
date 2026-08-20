-- Commands, diagnostics and final lifecycle callback ownership.
local _parse3, _q_aa, _unbox_or_identity
local _safe_call, _dump_actor, _dbg_count_registered_cwv_items
return function(mod, ctx)
local MOD_VERSION = ctx.mod_version
local _om = ctx.om
local _dbg = ctx.dbg
local _detect_companion_mods = assert(ctx.detect_companion_mods,
	"cwv commands lifecycle requires detect_companion_mods")
local _variant_definitions = ctx.variant_definitions
local _registered_keys = ctx.registered_keys
local _give_variant = ctx.give_variant

-- ============================================================
-- Init
-- ============================================================

local _wt, _cos = _detect_companion_mods()

mod:command("cwv", "Character Weapon Variants status", function()
	mod:echo("Character Weapon Variants v%s", MOD_VERSION)
	mod:echo("  Definitions: %d", #_variant_definitions)
	local count = 0
	for _ in pairs(_registered_keys) do count = count + 1 end
	mod:echo("  Registered items: %d", count)
	mod:echo("  weapon_tweaker: %s", tostring(_wt ~= nil))
	mod:echo("  cosmetics_tweaker: %s", tostring(_cos ~= nil))
	for _, d in ipairs(_variant_definitions) do
		local status = _registered_keys[d.item_key] and "registered" or "not registered"
		mod:echo("    %s — %s (%s)", d.item_key, d.display_name, status)
	end
end)

-- v0.1.293: Old Musket live-tune commands. Separate _1p / _3p variants since
-- the FBX needs different transforms in first-person view vs other players'
-- third-person view. State stored at top of file (search "_CWV_OLD_MUSKET_POS_1P"
-- etc); commands mutate globals and call `_reapply_old_musket_transforms_all`
-- which advances the canonical descriptor generation and replays only the
-- weak-keyed targets owned by the Phase-3 reconciler. Compose-safe with
-- vanilla's attachment_node_linking.
function _parse3(a, b, c)
	a, b, c = tonumber(a), tonumber(b), tonumber(c)
	if a and b and c then return { a, b, c } end
	return nil
end

-- v0.1.295: 3-bucket commands — 1P RANGED, 1P MELEE, 3P. Convention:
-- _1p_r = first-person ranged stance (rifle), _1p_m = first-person melee
-- stance (polearm), _3p = third-person (shared across modes).
mod:command("cwv_om_pos_1p_r", "Old Musket 1P RANGED pos: /cwv_om_pos_1p_r <x> <y> <z>", function(x, y, z)
	local v = _parse3(x, y, z); if not v then mod:echo("usage: /cwv_om_pos_1p_r <x> <y> <z>"); return end
	_om._CWV_OLD_MUSKET_POS_1P_RANGED = v; _om._reapply_old_musket_transforms_all()
end)
mod:command("cwv_om_pos_1p_m", "Old Musket 1P MELEE pos: /cwv_om_pos_1p_m <x> <y> <z>", function(x, y, z)
	local v = _parse3(x, y, z); if not v then mod:echo("usage: /cwv_om_pos_1p_m <x> <y> <z>"); return end
	_om._CWV_OLD_MUSKET_POS_1P_MELEE = v; _om._reapply_old_musket_transforms_all()
end)
mod:command("cwv_om_pos_3p_r", "Old Musket 3P RANGED pos: /cwv_om_pos_3p_r <x> <y> <z>", function(x, y, z)
	local v = _parse3(x, y, z); if not v then mod:echo("usage: /cwv_om_pos_3p_r <x> <y> <z>"); return end
	_om._CWV_OLD_MUSKET_POS_3P_RANGED = v; _om._reapply_old_musket_transforms_all()
end)
mod:command("cwv_om_pos_3p_m", "Old Musket 3P MELEE pos: /cwv_om_pos_3p_m <x> <y> <z>", function(x, y, z)
	local v = _parse3(x, y, z); if not v then mod:echo("usage: /cwv_om_pos_3p_m <x> <y> <z>"); return end
	_om._CWV_OLD_MUSKET_POS_3P_MELEE = v; _om._reapply_old_musket_transforms_all()
end)
-- Rotation commands. Three operations per bucket:
--   cwv_om_rot_<bucket>      <ax> <ay> <az> <deg>  — SET (replace current with single axis-angle)
--   cwv_om_rotmul_<bucket>   <ax> <ay> <az> <deg>  — MULTIPLY current rotation by a new axis-angle
--   cwv_om_eul_<bucket>      <x_deg> <y_deg> <z_deg> — SET from Euler XYZ degrees
-- Buckets: _1p_r (1P ranged), _1p_m (1P melee), _3p.
-- Use _rotmul_ to compose rotations without solving the math — e.g., set a
-- base orientation via _rot_, then add a 90° barrel-roll via
-- `cwv_om_rotmul_1p_r 0 0 1 90` (try X / Y / Z axes; whichever rolls the gun
-- the way you want is the barrel axis after your base rotation).
-- v0.1.298: all commands box via QuaternionBox(...) for long-term storage.
-- MUL helpers unbox + multiply + re-box. See note at _CWV_OLD_MUSKET_ROT_*
-- declarations.
function _q_aa(ax, ay, az, deg) return Quaternion.axis_angle(Vector3(ax, ay, az), math.rad(deg)) end
function _unbox_or_identity(boxed) return boxed and boxed:unbox() or Quaternion.identity() end

mod:command("cwv_om_rot_1p_r", "SET 1P RANGED rot (axis-angle deg): <ax> <ay> <az> <deg>", function(ax, ay, az, deg)
	ax, ay, az, deg = tonumber(ax), tonumber(ay), tonumber(az), tonumber(deg)
	if not (ax and ay and az and deg) then mod:echo("usage: cwv_om_rot_1p_r <ax> <ay> <az> <degrees>"); return end
	_om._CWV_OLD_MUSKET_ROT_1P_RANGED = QuaternionBox(_q_aa(ax, ay, az, deg)); _om._reapply_old_musket_transforms_all()
end)
mod:command("cwv_om_rot_1p_m", "SET 1P MELEE rot (axis-angle deg): <ax> <ay> <az> <deg>", function(ax, ay, az, deg)
	ax, ay, az, deg = tonumber(ax), tonumber(ay), tonumber(az), tonumber(deg)
	if not (ax and ay and az and deg) then mod:echo("usage: cwv_om_rot_1p_m <ax> <ay> <az> <degrees>"); return end
	_om._CWV_OLD_MUSKET_ROT_1P_MELEE = QuaternionBox(_q_aa(ax, ay, az, deg)); _om._reapply_old_musket_transforms_all()
end)
mod:command("cwv_om_rot_3p_r", "SET 3P RANGED rot (axis-angle deg): <ax> <ay> <az> <deg>", function(ax, ay, az, deg)
	ax, ay, az, deg = tonumber(ax), tonumber(ay), tonumber(az), tonumber(deg)
	if not (ax and ay and az and deg) then mod:echo("usage: cwv_om_rot_3p_r <ax> <ay> <az> <degrees>"); return end
	_om._CWV_OLD_MUSKET_ROT_3P_RANGED = QuaternionBox(_q_aa(ax, ay, az, deg)); _om._reapply_old_musket_transforms_all()
end)
mod:command("cwv_om_rot_3p_m", "SET 3P MELEE rot (axis-angle deg): <ax> <ay> <az> <deg>", function(ax, ay, az, deg)
	ax, ay, az, deg = tonumber(ax), tonumber(ay), tonumber(az), tonumber(deg)
	if not (ax and ay and az and deg) then mod:echo("usage: cwv_om_rot_3p_m <ax> <ay> <az> <degrees>"); return end
	_om._CWV_OLD_MUSKET_ROT_3P_MELEE = QuaternionBox(_q_aa(ax, ay, az, deg)); _om._reapply_old_musket_transforms_all()
end)

mod:command("cwv_om_rotmul_1p_r", "MUL 1P RANGED rot by axis-angle: <ax> <ay> <az> <deg>", function(ax, ay, az, deg)
	ax, ay, az, deg = tonumber(ax), tonumber(ay), tonumber(az), tonumber(deg)
	if not (ax and ay and az and deg) then mod:echo("usage: cwv_om_rotmul_1p_r <ax> <ay> <az> <degrees>"); return end
	_om._CWV_OLD_MUSKET_ROT_1P_RANGED = QuaternionBox(Quaternion.multiply(_unbox_or_identity(_om._CWV_OLD_MUSKET_ROT_1P_RANGED), _q_aa(ax, ay, az, deg)))
	_om._reapply_old_musket_transforms_all()
end)
mod:command("cwv_om_rotmul_1p_m", "MUL 1P MELEE rot by axis-angle: <ax> <ay> <az> <deg>", function(ax, ay, az, deg)
	ax, ay, az, deg = tonumber(ax), tonumber(ay), tonumber(az), tonumber(deg)
	if not (ax and ay and az and deg) then mod:echo("usage: cwv_om_rotmul_1p_m <ax> <ay> <az> <degrees>"); return end
	_om._CWV_OLD_MUSKET_ROT_1P_MELEE = QuaternionBox(Quaternion.multiply(_unbox_or_identity(_om._CWV_OLD_MUSKET_ROT_1P_MELEE), _q_aa(ax, ay, az, deg)))
	_om._reapply_old_musket_transforms_all()
end)
mod:command("cwv_om_rotmul_3p_r", "MUL 3P RANGED rot by axis-angle: <ax> <ay> <az> <deg>", function(ax, ay, az, deg)
	ax, ay, az, deg = tonumber(ax), tonumber(ay), tonumber(az), tonumber(deg)
	if not (ax and ay and az and deg) then mod:echo("usage: cwv_om_rotmul_3p_r <ax> <ay> <az> <degrees>"); return end
	_om._CWV_OLD_MUSKET_ROT_3P_RANGED = QuaternionBox(Quaternion.multiply(_unbox_or_identity(_om._CWV_OLD_MUSKET_ROT_3P_RANGED), _q_aa(ax, ay, az, deg)))
	_om._reapply_old_musket_transforms_all()
end)
mod:command("cwv_om_rotmul_3p_m", "MUL 3P MELEE rot by axis-angle: <ax> <ay> <az> <deg>", function(ax, ay, az, deg)
	ax, ay, az, deg = tonumber(ax), tonumber(ay), tonumber(az), tonumber(deg)
	if not (ax and ay and az and deg) then mod:echo("usage: cwv_om_rotmul_3p_m <ax> <ay> <az> <degrees>"); return end
	_om._CWV_OLD_MUSKET_ROT_3P_MELEE = QuaternionBox(Quaternion.multiply(_unbox_or_identity(_om._CWV_OLD_MUSKET_ROT_3P_MELEE), _q_aa(ax, ay, az, deg)))
	_om._reapply_old_musket_transforms_all()
end)

mod:command("cwv_om_eul_1p_r", "SET 1P RANGED rot from Euler XYZ (deg): <x> <y> <z>", function(x, y, z)
	x, y, z = tonumber(x), tonumber(y), tonumber(z)
	if not (x and y and z) then mod:echo("usage: cwv_om_eul_1p_r <x_deg> <y_deg> <z_deg>"); return end
	_om._CWV_OLD_MUSKET_ROT_1P_RANGED = QuaternionBox(Quaternion.from_euler_angles_xyz(x, y, z)); _om._reapply_old_musket_transforms_all()
end)
mod:command("cwv_om_eul_1p_m", "SET 1P MELEE rot from Euler XYZ (deg): <x> <y> <z>", function(x, y, z)
	x, y, z = tonumber(x), tonumber(y), tonumber(z)
	if not (x and y and z) then mod:echo("usage: cwv_om_eul_1p_m <x_deg> <y_deg> <z_deg>"); return end
	_om._CWV_OLD_MUSKET_ROT_1P_MELEE = QuaternionBox(Quaternion.from_euler_angles_xyz(x, y, z)); _om._reapply_old_musket_transforms_all()
end)
mod:command("cwv_om_eul_3p_r", "SET 3P RANGED rot from Euler XYZ (deg): <x> <y> <z>", function(x, y, z)
	x, y, z = tonumber(x), tonumber(y), tonumber(z)
	if not (x and y and z) then mod:echo("usage: cwv_om_eul_3p_r <x_deg> <y_deg> <z_deg>"); return end
	_om._CWV_OLD_MUSKET_ROT_3P_RANGED = QuaternionBox(Quaternion.from_euler_angles_xyz(x, y, z)); _om._reapply_old_musket_transforms_all()
end)
mod:command("cwv_om_eul_3p_m", "SET 3P MELEE rot from Euler XYZ (deg): <x> <y> <z>", function(x, y, z)
	x, y, z = tonumber(x), tonumber(y), tonumber(z)
	if not (x and y and z) then mod:echo("usage: cwv_om_eul_3p_m <x_deg> <y_deg> <z_deg>"); return end
	_om._CWV_OLD_MUSKET_ROT_3P_MELEE = QuaternionBox(Quaternion.from_euler_angles_xyz(x, y, z)); _om._reapply_old_musket_transforms_all()
end)
mod:command("cwv_om_scale_1p_r", "Old Musket 1P RANGED scale: /cwv_om_scale_1p_r <x> <y> <z>", function(x, y, z)
	local v = _parse3(x, y, z); if not v then mod:echo("usage: cwv_om_scale_1p_r <x> <y> <z>"); return end
	_om._CWV_OLD_MUSKET_SCALE_1P_RANGED = v; _om._reapply_old_musket_transforms_all()
end)
mod:command("cwv_om_scale_1p_m", "Old Musket 1P MELEE scale: /cwv_om_scale_1p_m <x> <y> <z>", function(x, y, z)
	local v = _parse3(x, y, z); if not v then mod:echo("usage: cwv_om_scale_1p_m <x> <y> <z>"); return end
	_om._CWV_OLD_MUSKET_SCALE_1P_MELEE = v; _om._reapply_old_musket_transforms_all()
end)
mod:command("cwv_om_scale_3p_r", "Old Musket 3P RANGED scale: /cwv_om_scale_3p_r <x> <y> <z>", function(x, y, z)
	local v = _parse3(x, y, z); if not v then mod:echo("usage: cwv_om_scale_3p_r <x> <y> <z>"); return end
	_om._CWV_OLD_MUSKET_SCALE_3P_RANGED = v; _om._reapply_old_musket_transforms_all()
end)
mod:command("cwv_om_scale_3p_m", "Old Musket 3P MELEE scale: /cwv_om_scale_3p_m <x> <y> <z>", function(x, y, z)
	local v = _parse3(x, y, z); if not v then mod:echo("usage: cwv_om_scale_3p_m <x> <y> <z>"); return end
	_om._CWV_OLD_MUSKET_SCALE_3P_MELEE = v; _om._reapply_old_musket_transforms_all()
end)
mod:command("cwv_om_show", "Echo current Old Musket transform values (rot as Euler XYZ deg)", function()
	local function _f3(v) return string.format("(%.3f, %.3f, %.3f)", v[1], v[2], v[3]) end
	local function _fr(boxed)
		if not boxed then return "identity" end
		local x, y, z = Quaternion.to_euler_angles_xyz(boxed:unbox())
		return string.format("euler_xyz=(%.2f, %.2f, %.2f)°", x, y, z)
	end
	mod:echo("[cwv old-musket] 1P-RANGED pos=%s  rot=%s  scale=%s", _f3(_om._CWV_OLD_MUSKET_POS_1P_RANGED), _fr(_om._CWV_OLD_MUSKET_ROT_1P_RANGED), _f3(_om._CWV_OLD_MUSKET_SCALE_1P_RANGED))
	mod:echo("[cwv old-musket] 1P-MELEE  pos=%s  rot=%s  scale=%s", _f3(_om._CWV_OLD_MUSKET_POS_1P_MELEE),  _fr(_om._CWV_OLD_MUSKET_ROT_1P_MELEE),  _f3(_om._CWV_OLD_MUSKET_SCALE_1P_MELEE))
	mod:echo("[cwv old-musket] 3P-RANGED pos=%s  rot=%s  scale=%s", _f3(_om._CWV_OLD_MUSKET_POS_3P_RANGED), _fr(_om._CWV_OLD_MUSKET_ROT_3P_RANGED), _f3(_om._CWV_OLD_MUSKET_SCALE_3P_RANGED))
	mod:echo("[cwv old-musket] 3P-MELEE  pos=%s  rot=%s  scale=%s", _f3(_om._CWV_OLD_MUSKET_POS_3P_MELEE),  _fr(_om._CWV_OLD_MUSKET_ROT_3P_MELEE),  _f3(_om._CWV_OLD_MUSKET_SCALE_3P_MELEE))
end)

-- v0.1.303 probe: dump every musket item in the backend mirror, plus the
-- two related ItemMasterList entries (cwv_es_musket_old + cwv_es_musket).
-- Tells us at a glance what slot_type / template each item ended up with
-- and whether the variant was registered at all.
-- v0.1.306: dump ammo state of every alive cwv musket ammo extension
-- in the pool, plus the pool cap. Useful for verifying the shared-pool
-- behavior (chambered ammo per-item, reserve shared across items).
mod:command("cwv_musket_ammo_diag", "Dump shared-pool ammo state for all cwv muskets", function()
	if not _om._CWV_MUSKET_AMMO_EXTS then mod:echo("pool not initialized"); return end
	local count = 0
	for ext in pairs(_om._CWV_MUSKET_AMMO_EXTS) do
		local alive = ext.unit and Unit.alive(ext.unit)
		if alive then
			count = count + 1
			local pool_reserve = _om.musket_ammo_pool and _om.musket_ammo_pool:reserve_for(ext)
			local pool_cap = _om._cwv_musket_pool_cap and _om._cwv_musket_pool_cap(ext) or 0
			mod:echo("[#%d] owner=%s unit=%s slot=%s curr=%s avail=%s pool=%s/%s shots_fired=%s native_max=%s effective_max=%s clip=%s reloading=%s",
				count, tostring(ext.owner_unit), tostring(ext.unit), tostring(ext.slot_name),
				tostring(ext._current_ammo), tostring(ext._available_ammo),
				tostring(pool_reserve), tostring(pool_cap), tostring(ext._shots_fired),
				tostring(ext._max_ammo), tostring(pool_cap + (ext._ammo_per_clip or 0)), tostring(ext._ammo_per_clip),
				tostring(ext._next_reload_time ~= nil))
		else
			mod:echo("[#?] dead member (cleanup pending)")
		end
	end
	mod:echo("pool: live_members=%d reserve_per_musket=%d (capacity is owner-scoped; see each row)",
		count, _om._CWV_RESERVE_PER_MUSKET)
end)

mod:command("cwv_musket_dump", "Dump all musket items + their slot_type / template", function()
	local backend_items = Managers and Managers.backend and Managers.backend:get_interface("items")
	if backend_items and backend_items.get_all_backend_items then
		local all = backend_items:get_all_backend_items()
		local count = 0
		for backend_id, item in pairs(all or {}) do
			local data = item.data or item.master_item or item
			local key = data and (data.key or data.name) or item.ItemId or backend_id
			if type(key) == "string" and key:match("^cwv_es_musket") then
				count = count + 1
				mod:echo("[BACKEND] backend_id=%s  key=%s  slot_type=%s  template=%s  rarity=%s",
					tostring(backend_id), tostring(key),
					tostring(data and data.slot_type),
					tostring(data and data.template),
					tostring(item.rarity or (data and data.rarity)))
			end
		end
		mod:echo("[BACKEND] total cwv musket items: %d", count)
	else
		mod:echo("[BACKEND] backend_items interface unavailable")
	end

	if ItemMasterList then
		for _, k in ipairs({ "cwv_es_musket_old", "cwv_es_musket", "es_handgun" }) do
			local e = ItemMasterList[k]
			if e then
				mod:echo("[IML] %s  slot_type=%s  template=%s  rarity=%s",
					k, tostring(e.slot_type), tostring(e.template), tostring(e.rarity))
			else
				mod:echo("[IML] %s = nil", k)
			end
		end
	end
	mod:echo("[WEAPONS] old_musket_template=%s  old_musket_template_melee=%s",
		tostring(Weapons and Weapons.old_musket_template ~= nil),
		tostring(Weapons and Weapons.old_musket_template_melee ~= nil))
end)

mod:command("cwv_probe_skins", "Dump skin keys + localized names matching a weapon: /cwv_probe_skins <matching_item_key>", function(matching_item_key)
	if not matching_item_key or matching_item_key == "" then
		mod:echo("Usage: /cwv_probe_skins <matching_item_key>  (e.g. es_2h_sword, es_bastard_sword)")
		return
	end
	if not ItemMasterList then mod:echo("ItemMasterList not loaded") return end
	local results = {}
	for key, item in pairs(ItemMasterList) do
		if item.item_type == "weapon_skin" and item.matching_item_key == matching_item_key then
			results[#results + 1] = key
		end
	end
	table.sort(results)
	mod:info("=== Skins for matching_item_key='%s' (%d) ===", matching_item_key, #results)
	for _, key in ipairs(results) do
		local item = ItemMasterList[key]
		local name = key
		if item.display_name then
			local ok, loc = pcall(Localize, item.display_name)
			if ok and loc then name = loc end
		end
		mod:info("%s | %s | %s | rarity=%s", key, name, tostring(item.right_hand_unit or "?"), tostring(item.rarity or "?"))
	end
	mod:echo("Dumped %d skins to log (search for 'Skins for')", #results)
end)

-- ============================================================
-- Unit probe — diagnostic tooling for pickup-asset investigation
-- ============================================================
-- Spawns a Stingray unit at the player's feet and dumps its asset-level
-- properties (actor count, actor names, collision filters, bounding box,
-- attached extensions) to mod:info. Used to compare known-good pickup units
-- (pup_dw_thrown_axe_01_t1, prj_we_javelin_01_3ps) against candidate units
-- (wpn_emp_boar_spear_01_3p, spear_3ps) so we can decide which assets can
-- legitimately serve as pickup units without going through the full
-- spawn-throw-fail iteration cycle.
--
-- Spawned probes persist until cwv_despawn_probes is called or level changes.
--
-- Suggested probe sequence for the Tuskgor Javelin pickup investigation:
--   cwv_probe_unit units/weapons/player/wpn_emp_boar_spear_01/wpn_emp_boar_spear_01_3p
--   cwv_probe_unit units/weapons/player/wpn_dw_thrown_axe_01_t1/pup_dw_thrown_axe_01_t1
--   cwv_probe_unit units/weapons/player/wpn_we_javelin_01/prj_we_javelin_01_3ps
--   cwv_probe_unit units/weapons/player/spear_projectile/spear_3ps
--   cwv_despawn_probes
local _probe_units = {}

function _safe_call(fn, ...)
	local ok, ret = pcall(fn, ...)
	if ok then return ret end
	return nil
end

function _dump_actor(unit, idx)
	local actor = _safe_call(Unit.actor, unit, idx)
	if not actor then
		mod:info("  [%d] (nil actor)", idx)
		return
	end
	local name = _safe_call(Actor.name, actor) or "(unnamed)"
	local is_static    = _safe_call(Actor.is_static, actor)
	local is_kinematic = _safe_call(Actor.is_kinematic, actor)
	local is_dynamic   = _safe_call(Actor.is_dynamic, actor)
	local cfilter      = _safe_call(Actor.collision_filter, actor)
	mod:info("  [%d] name=%s static=%s kin=%s dyn=%s collision_filter=%s",
		idx, tostring(name),
		tostring(is_static), tostring(is_kinematic), tostring(is_dynamic),
		tostring(cfilter))
end

mod:command("cwv_probe_unit", "Spawn a unit and dump asset properties (/cwv_probe_unit <path>)", function(unit_path)
	if not unit_path or unit_path == "" then
		mod:echo("Usage: /cwv_probe_unit <unit_path>")
		mod:echo("Example paths to compare:")
		mod:echo("  units/weapons/player/wpn_emp_boar_spear_01/wpn_emp_boar_spear_01_3p")
		mod:echo("  units/weapons/player/wpn_dw_thrown_axe_01_t1/pup_dw_thrown_axe_01_t1")
		mod:echo("  units/weapons/player/wpn_we_javelin_01/prj_we_javelin_01_3ps")
		mod:echo("  units/weapons/player/spear_projectile/spear_3ps")
		return
	end
	local player = Managers.player and Managers.player:local_player()
	if not player or not player.player_unit then mod:echo("No local player unit yet (in-mission only)") return end
	local world = Managers.world and Managers.world:world("level_world")
	if not world then mod:echo("level_world not available") return end

	local player_pos = Unit.world_position(player.player_unit, 0)
	local player_rot = Unit.world_rotation(player.player_unit, 0)
	local forward    = Quaternion.forward(player_rot)
	local spawn_pos  = player_pos + forward * 1.5 + Vector3.up(player_pos) * 1.0

	-- Pre-check loadability. Stingray's World.spawn_unit asserts in C++
	-- (resource_manager().can_get(...)) when the unit isn't in a loaded
	-- resource package — pcall CANNOT catch that assertion, the engine
	-- hard-crashes. Try to verify the unit is loaded before spawning.
	-- Application.can_get / has_resource APIs vary by Stingray version;
	-- best-effort with multiple fallbacks. If none confirm loadability,
	-- refuse to spawn rather than risk a crash.
	local can_check_apis = {
		function() return Application.can_get and Application.can_get("unit", unit_path) end,
		function() return Application.has_resource and Application.has_resource("unit", unit_path) end,
	}
	local loadable = nil
	for _, check in ipairs(can_check_apis) do
		local ok, result = pcall(check)
		if ok and result ~= nil then loadable = result; break end
	end
	if loadable == false then
		mod:echo("Refusing to spawn '%s' — unit not in loaded resource packages.", unit_path)
		mod:echo("  (would crash; this unit is only loaded when its host weapon is equipped in this lobby)")
		return
	end
	-- If loadable check returned nil, we couldn't verify; user assumes risk.

	local ok, unit = pcall(World.spawn_unit, world, unit_path, spawn_pos)
	if not ok or not unit then
		mod:echo("Spawn failed: %s", tostring(unit))
		mod:info("Spawn failed for %s: %s", unit_path, tostring(unit))
		return
	end

	_probe_units[#_probe_units + 1] = unit

	mod:info("=== PROBE: %s ===", unit_path)

	-- Node hierarchy
	local num_nodes = _safe_call(Unit.num_nodes, unit) or 0
	mod:info("nodes: %d", num_nodes)
	for i = 0, math.min(num_nodes - 1, 30) do
		local name = _safe_call(Unit.node_name, unit, i)
		local pos = _safe_call(Unit.local_position, unit, i)
		local rot = _safe_call(Unit.local_rotation, unit, i)
		local px, py, pz, qx, qy, qz, qw = "?", "?", "?", "?", "?", "?", "?"
		if pos then px, py, pz = string.format("%.2f", Vector3.x(pos)), string.format("%.2f", Vector3.y(pos)), string.format("%.2f", Vector3.z(pos)) end
		if rot then
			local fwd = _safe_call(Quaternion.forward, rot)
			if fwd then qx, qy, qz = string.format("%.2f", Vector3.x(fwd)), string.format("%.2f", Vector3.y(fwd)), string.format("%.2f", Vector3.z(fwd)) end
		end
		mod:info("  [%d] name=%s local_pos=(%s,%s,%s) local_fwd=(%s,%s,%s)",
			i, tostring(name or "?"), px, py, pz, qx, qy, qz)
	end

	-- Actors
	local num_actors = _safe_call(Unit.num_actors, unit) or 0
	mod:info("actors: %d", num_actors)
	for i = 0, num_actors - 1 do
		_dump_actor(unit, i)
	end

	-- Bounding box (asset extents) — different APIs in different SDK versions; try both
	local bmin, bmax = _safe_call(function() return Unit.box(unit) end), nil
	local ok_box, b1, b2 = pcall(Unit.box, unit)
	if ok_box and b1 and b2 then
		mod:info("box min=(%.2f,%.2f,%.2f) max=(%.2f,%.2f,%.2f)",
			Vector3.x(b1), Vector3.y(b1), Vector3.z(b1),
			Vector3.x(b2), Vector3.y(b2), Vector3.z(b2))
	end

	-- Extensions — usually empty for raw World.spawn_unit (no entity_system pass);
	-- log anyway in case the unit auto-attaches anything via its asset metadata.
	local has_pickup = _safe_call(ScriptUnit.has_extension, unit, "pickup_system")
	local has_outline = _safe_call(ScriptUnit.has_extension, unit, "outline_system")
	local has_interaction = _safe_call(ScriptUnit.has_extension, unit, "interactable_system")
	mod:info("extensions: pickup=%s outline=%s interactable=%s",
		tostring(has_pickup ~= nil), tostring(has_outline ~= nil), tostring(has_interaction ~= nil))

	mod:echo("Probed '%s' (probe #%d). Walk around and inspect; cwv_despawn_probes when done. Log written to console.",
		unit_path, #_probe_units)
end)

-- Focused probe for the j_leftweaponattach investigation: spawns each
-- weapon-display rig and reports whether the named attach nodes exist.
-- See `J_LEFTWEAPONATTACH_INVESTIGATION.md` U1.
mod:command("cwv_probe_attach", "Spawn each display rig and check for j_leftweaponattach / j_rightweaponattach", function()
	local rigs = {
		"units/weapons/weapon_display/display_dual_weapons",
		"units/weapons/weapon_display/display_1h_weapon",
		"units/weapons/weapon_display/display_1h_swords",
		"units/weapons/weapon_display/display_dual_axes",
		"units/weapons/weapon_display/display_dual_daggers",
		"units/weapons/weapon_display/display_dual_hammers",
		"units/weapons/weapon_display/dual_wield_axe_falchion",
		"units/weapons/weapon_display/display_2h_weapon",
		"units/weapons/weapon_display/display_shield",
	}
	local player = Managers.player and Managers.player:local_player()
	if not player or not player.player_unit then mod:echo("No local player unit (be in keep or mission)") return end
	local world = Managers.world and Managers.world:world("level_world")
	if not world then mod:echo("level_world not available") return end

	local pos = Unit.world_position(player.player_unit, 0)
	local results = {}
	for _, path in ipairs(rigs) do
		local ok, unit = pcall(World.spawn_unit, world, path, pos)
		if not ok or not unit then
			results[#results + 1] = string.format("%s — SPAWN FAILED (%s)", path, tostring(unit))
		else
			local has_left  = pcall(Unit.node, unit, "j_leftweaponattach")
			local has_right = pcall(Unit.node, unit, "j_rightweaponattach")
			results[#results + 1] = string.format("%s — left=%s right=%s",
				path, tostring(has_left), tostring(has_right))
			pcall(World.destroy_unit, world, unit)
		end
	end

	mod:echo("=== display rig attach-node probe ===")
	for _, line in ipairs(results) do
		mod:info(line)
		mod:echo(line)
	end
	mod:echo("=== end ===")
end)

mod:command("cwv_despawn_probes", "Despawn all probe units spawned via cwv_probe_unit", function()
	local count = 0
	for _, unit in ipairs(_probe_units) do
		if unit and _safe_call(Unit.alive, unit) then
			local ok = pcall(function()
				Managers.state.unit_spawner:mark_for_deletion(unit)
			end)
			if ok then count = count + 1 end
		end
	end
	_probe_units = {}
	mod:echo("Despawned %d probe units", count)
end)

-- ============================================================================
-- Debug-mode event subscriptions (v0.1.336)
-- ============================================================================
-- Three event-driven _dbg dumps that fire only when `cwv_debug_mode` is ON.
-- Each handler short-circuits at the top via mod:get so the engine-side
-- callback overhead is the only cost when the toggle is off.
--
-- 1. Game-state transitions  -> dump registered cwv_* item count + which
--    loadout slots have cwv_* items equipped on the local player.
-- 2. Wield (SimpleInventoryExtension.wield post-hook) -> dump variant key,
--    backend_id, slot, applied skin, base template, and career when the
--    player wields any cwv_* item.
-- 3. Old Musket stance toggle -> dump prior/new stance + slot_index alongside
--    the existing per-toggle "[cwv musket] stance:" trace (which is also
--    now gated through _dbg).
--
-- Localized helper: count cwv_* item_keys present in ItemMasterList. Bails
-- gracefully when IML isn't loaded yet (boot timing).
function _dbg_count_registered_cwv_items()
    local iml = rawget(_G, "ItemMasterList")
    if type(iml) ~= "table" then return -1 end
    local n = 0
    -- ItemMasterList has the missing-key crashify metamethod (see v0.1.333),
    -- so iterate via `pairs` (which calls __pairs / next directly on the
    -- table contents — does not trigger __index). Filter to cwv_* prefix.
    for k, _ in pairs(iml) do
        if type(k) == "string" and k:sub(1, 4) == "cwv_" then
            n = n + 1
        end
    end
    return n
end

-- (1) Game state transitions. VMF surfaces engine state changes through the
-- top-level `mod.on_game_state_changed = function(status, state_name)` slot.
_om._dual_axes_fp_game_state_retry_installed = true
mod.on_game_state_changed = function(status, state_name)
	if status == "exit" and _om.old_musket_appearance then
		_om.old_musket_appearance.disconnect()
		_om._cwv_cim_latest_generation = nil
	end
    -- #586: chunk-load normally acquires the leases, but PackageManager can be
    -- cold during unusual load ordering. Every gameplay-state enter is a safe
    -- retry boundary and catalog acquisition is idempotent.
    if status == "enter" and _om._dual_weapon_fp_residency_complete ~= true then
        _om._acquire_dual_weapon_fp_residency("game_state_enter:" .. tostring(state_name))
    end

    local n = _dbg_count_registered_cwv_items()
    _dbg("on_game_state_changed: status=%s state=%s registered_cwv_items=%d",
        tostring(status), tostring(state_name), n)

	-- Only attempt the loadout snapshot on `enter` (the new state is now
	-- active) — `exit` fires before extensions are wired in the next state.
	if status ~= "enter" then return end
	-- #474: a mission/keep state enter is a bounded reconstruction boundary.
	-- Query peers and replay our current slots once; no timer or frame traffic.
	if _om._old_musket_request_states then
		_om._old_musket_request_states("game_state_enter:" .. tostring(state_name))
	end
	if _om.crowbill_runtime and _om.crowbill_runtime.request_states then
		_om.crowbill_runtime.request_states("game_state_enter:" .. tostring(state_name))
	end

    -- `Managers.player:local_player()` internally calls `peer_id()`, which
    -- THROWS "Network backend has not been set" on early state-enters
    -- (StateSplashScreen / menu) before the network backend exists. This is a
    -- diagnostics-only handler, so pcall the lookup and bail silently when the
    -- backend isn't up yet — otherwise VMF logs a (caught) error on every boot.
    if not Managers.player then return end
    local ok_pl, pl = pcall(Managers.player.local_player, Managers.player)
    if not ok_pl or not pl then return end
    local player_unit = pl.player_unit
    if not player_unit or not Unit.alive(player_unit) then
        _dbg("  loadout: no local player_unit yet (state=%s)", tostring(state_name))
        return
    end
    -- #343: first live keep/mission boundary records the observation-only smoke
    -- bomb prerequisite snapshot automatically. It is log-only and one-shot;
    -- the explicit command remains available for at most two later rechecks.
    if mod._cwv_smoke_bomb_probe then
        mod._cwv_smoke_bomb_probe.auto_run(mod)
    end
    local ok_inv, inv = pcall(ScriptUnit.extension, player_unit, "inventory_system")
    if not ok_inv or not inv or not inv.equipment then
        _dbg("  loadout: no inventory_system on local player (state=%s)", tostring(state_name))
        return
    end
    local equip = inv:equipment()
    local slots = equip and equip.slots
    if type(slots) ~= "table" then return end

    local hits = 0
    for slot_name, slot_data in pairs(slots) do
        local item_data = slot_data and slot_data.item_data
        local bid = item_data and item_data.backend_id
        if type(bid) == "string" and bid:match("^cwv_") then
            hits = hits + 1
            _dbg("  loadout slot=%s backend_id=%s template=%s skin=%s",
                tostring(slot_name), tostring(bid),
                tostring(item_data.template),
                tostring(slot_data.skin))
        end
    end
    _dbg("  loadout: %d cwv_* item(s) currently equipped", hits)
end

-- #586: these callbacks own the generated-dual FP lease catalog above. Keep
-- them idempotent because VMF may call on_disabled before on_unload.
mod.on_enabled = function()
    _om._acquire_dual_weapon_fp_residency("mod_enabled")
	if _om.crowbill_runtime and _om.crowbill_runtime.set_enabled then
		_om.crowbill_runtime.set_enabled(true)
	end
	-- #599: compose gameplay-profile ownership into the canonical lifecycle
	-- callback. Defining an earlier callback is ineffective because this owner
	-- assignment is the final VMF callback value.
	_om._apply_mace_hammer_identity(
		mod:get(_om.mace_hammer_identity_policy.SETTING_ID) ~= false)
end

mod.on_disabled = function()
	if _om.old_musket_appearance then _om.old_musket_appearance.disconnect() end
	_om._cwv_cim_latest_generation = nil
	if _om.crowbill_runtime and _om.crowbill_runtime.set_enabled then
		_om.crowbill_runtime.set_enabled(false)
	end
	_om._apply_mace_hammer_identity(false)
    _om._release_dual_weapon_fp_residency("mod_disabled")
end

mod.on_unload = function()
	if _om.old_musket_appearance then _om.old_musket_appearance.disconnect() end
	_om._cwv_cim_latest_generation = nil
	if _om.crowbill_runtime and _om.crowbill_runtime.set_enabled then
		_om.crowbill_runtime.set_enabled(false)
	end
	_om._apply_mace_hammer_identity(false)
    _om._release_dual_weapon_fp_residency("mod_unload")
end

-- (2) Variant equip event — MERGED into the canonical wield hook at line ~1317
-- (where the cross-access tracking lives). VMF `mod:hook_safe` does NOT chain
-- on the same (Class, method) — a second registration silently overwrites.
-- See v0.1.337 CHANGELOG and VMF_RECIPES.md § 1.

-- (3) Old Musket stance toggle. The toggle helper
-- `_toggle_musket_stance_and_rewield` (~line 2729) already logs its core
-- transition via `_dbg("[cwv musket] stance: %s → %s ...")`. To honor the
-- task's "log prior stance / new stance / slot_index" requirement without
-- introducing duplicate noise, attach an extra structured dump at the same
-- call site keyed off the SAME `cwv_debug_mode` toggle. Lookup happens at
-- the function entry only -- not in a hot loop -- so the cached-pattern
-- guidance doesn't apply here.
--
-- We intentionally do NOT add a hook to a vanilla method to observe this --
-- the stance toggle is a CWV-internal event with no vanilla equivalent.
-- The existing call site is the canonical fire point.

mod:command("cwv_give", "Give a variant weapon: cwv_give <item_key>", function(item_key)
	if not item_key or item_key == "" then
		mod:echo("Usage: cwv_give <item_key>")
		mod:echo("Available variants:")
		for _, d in ipairs(_variant_definitions) do
			mod:echo("  %s — %s", d.item_key, d.display_name)
		end
		return
	end
	_give_variant(item_key)
end)


end
