-- _cwv_exact_wire_runtime.lua -- runtime owner for CWV's two independent exact
-- wire axes (#423 damage profiles, #424 thrown resources).
--
-- Pure catalog/disposition logic lives in the sibling policy modules
-- (_cwv_damage_profile_wire.lua, _cwv_thrown_wire_policy.lua); this file owns
-- the engine contact: the exact-mode peer-parity instances, the
-- ProjectileUnitsFromUnitName inverse registration, and the sole cwv hook on
-- WeaponSystem.send_rpc_attack_hit.
--
-- WHY TWO DEDICATED CHANNELS rather than upgrading `cwv_peer_parity_present`:
-- the presence channel is a protocol generation that deployed CWV builds
-- already speak, and it gates surfaces (appearance lifecycle #914, the javelin
-- feature) that must keep their existing semantics. A dedicated exact channel
-- makes an old peer and an exact peer fail closed in BOTH directions -- the
-- same reasoning wt records at _wt431_damage_profile_parity.lua:85-90.
--
-- Owned by: character_weapon_variants.lua. Consumed via: mod:dofile.

local M = {}

local function _printf(...)
	pcall(rawget(_G, "printf") or function() end, ...)
end

-- Vanilla builds this inverse ONCE at projectile_units.lua:59-63. CWV appends
-- its row afterwards, so the inverse consumed by
-- TransientPackageLoader.add_projectile (transient_package_loader.lua:155) and
-- PlayerProjectileHuskExtension (player_projectile_husk_extension.lua:60) never
-- learns about it. Extend it explicitly; a native or foreign owner of the same
-- unit name is PRESERVED and exact parity fails closed instead.
local function ensure_projectile_inverse(globals, spec)
	local inverse = globals and globals.ProjectileUnitsFromUnitName
	local projectile_units = globals and globals.ProjectileUnits
	local projectile_row = type(projectile_units) == "table"
		and rawget(projectile_units, spec.projectile_key)
	if type(inverse) ~= "table" then
		_printf("[cwv:424] ProjectileUnitsFromUnitName missing; exact projectile wire remains disabled")
		return false
	end
	if type(projectile_row) ~= "table"
			or projectile_row.projectile_unit_name ~= spec.inflight_unit then
		_printf("[cwv:424] ProjectileUnits.%s does not own %s; inverse registration refused",
			tostring(spec.projectile_key), tostring(spec.inflight_unit))
		return false
	end
	local existing = rawget(inverse, spec.inflight_unit)
	if existing == nil then
		rawset(inverse, spec.inflight_unit, spec.projectile_key)
		return true
	end
	if existing ~= spec.projectile_key then
		_printf("[cwv:424] ProjectileUnitsFromUnitName collision for %s (owner=%s, wanted=%s); exact projectile wire remains disabled",
			tostring(spec.inflight_unit), tostring(existing), tostring(spec.projectile_key))
		return false
	end
	return true
end

-- mod:dofile returns a FRESH module per call (never a singleton), so the parity
-- library is a factory: build one instance per exact channel.
local function new_exact_parity(mod, channel, identity)
	if type(identity) ~= "string" then return nil, "identity-missing" end
	local ok, factory = pcall(function()
		return mod:dofile("scripts/mods/character_weapon_variants/_lib_peer_parity")
	end)
	if not ok or type(factory) ~= "function" then return nil, "factory-missing" end
	local ok_new, instance = pcall(factory, mod, {
		channel = channel,
		schema = mod.CWV_RPC_SCHEMA,
		mod_label = "Character Weapon Variants",
		echo_prefix = "[cwv]",
		wire_identity = identity,
	})
	if not ok_new or type(instance) ~= "table" then return nil, tostring(instance) end
	-- Two independent commit signals, both required. `installed` is install()'s
	-- own return; `is_installed` is the instance's committed state. #1158's
	-- install-transaction fanout is what makes the first one real -- before it,
	-- install() returned nothing, so this factory answered "install-failed" for
	-- every exact channel and cwv's #423/#424 gates were permanently inert.
	local ok_install, installed = pcall(instance.install, instance)
	local ok_state, is_installed = pcall(instance.is_installed, instance)
	if not (ok_install and installed == true and ok_state and is_installed == true) then
		return nil, "install-failed"
	end
	return instance
end

-- ---------------------------------------------------------------------------
-- Thrown resources (#424): projectile_units + husks + pickup_names
-- ---------------------------------------------------------------------------
function M.install_thrown(mod, om, globals, spec)
	om._cwv_thrown_spec = spec
	ensure_projectile_inverse(globals, spec)
	local snapshot, capture_err = om.thrown_wire_policy.capture(
		om.wire_catalog, globals, spec)
	om._cwv_thrown_wire_snapshot = snapshot
	if snapshot then
		local parity, parity_err = new_exact_parity(
			mod, "cwv_thrown_resources_exact_v1", snapshot.identity)
		mod._cwv_thrown_peer_parity = parity
		if parity then
			_printf("[cwv:424] exact thrown catalog=%s rows=%d beacon=cwv_thrown_resources_exact_v1",
				tostring(snapshot.identity), #snapshot.rows)
		else
			_printf("[cwv:424] WARN exact thrown parity unavailable (%s); thrown feature stays inert",
				tostring(parity_err))
		end
	else
		_printf("[cwv:424] WARN exact thrown catalog unavailable (%s); thrown feature stays inert",
			tostring(capture_err))
	end

	-- Exposed as a mod-level function so the javelin gate, the entry-file
	-- senders, and /cwv_regression_test all read ONE verdict.
	function mod._cwv_thrown_wire_safe()
		return om.thrown_wire_policy.exact_safe(
			mod._cwv_thrown_peer_parity, om._cwv_thrown_wire_snapshot)
	end
	-- Catalog-only arm, without the lobby-wide applied_state: the per-peer
	-- hot-join verdict needs "our rows have not drifted" separately from
	-- "every peer agreed".
	function mod._cwv_thrown_catalog_intact()
		local ok, intact = pcall(om.thrown_wire_policy.integrity,
			om._cwv_thrown_wire_snapshot)
		return ok and intact == true
	end
	om._cwv_thrown_wire_installed = true
end

-- ---------------------------------------------------------------------------
-- Damage profiles (#423): the sole cwv hook on WeaponSystem.send_rpc_attack_hit
-- ---------------------------------------------------------------------------
-- rpc_attack_hit is client->server (weapon_system.lua:182) and the host decodes
-- the id STRICTLY (weapon_system.lua:243, no rawget), so a cwv index reaching a
-- host with a different catalog terminates that host. send_rpc_attack_hit is
-- the single choke point: every attack RPC in the decompile (weapon_system /
-- damage_utils / projectiles / area_damage / the lunge + shield/push/BH
-- actions) routes its damage_profile_id through it.
--
-- The substitution is a GAMEPLAY degradation, never a crash: an unproven cwv
-- profile becomes its recorded vanilla clone SOURCE (the base weapon's own
-- behaviour), then vanilla `default`, and only a profile with neither proven
-- donor is dropped.
function M.install_damage(mod, om)
	local NL = rawget(_G, "NetworkLookup")
	local snapshot, wire_err = om.damage_profile_wire.capture(
		om.wire_catalog, NL and NL.damage_profiles,
		om._cwv_damage_profile_wire_source, om._cwv_damage_profile_generation)
	om._cwv_damage_wire_snapshot = snapshot
	if snapshot then
		local parity, parity_err = new_exact_parity(
			mod, "cwv_damage_profiles_exact_v1", snapshot.identity)
		mod._cwv_damage_peer_parity = parity
		if parity then
			_printf("[cwv:423] exact damage catalog=%s rows=%d beacon=cwv_damage_profiles_exact_v1",
				tostring(snapshot.identity), #snapshot.rows)
		else
			_printf("[cwv:423] WARN exact damage parity unavailable (%s); every cwv profile substitutes",
				tostring(parity_err))
		end
	else
		_printf("[cwv:423] WARN exact damage catalog unavailable (%s); every cwv profile substitutes",
			tostring(wire_err))
	end

	function mod._cwv_damage_wire_safe()
		local pp = mod._cwv_damage_peer_parity
		if type(pp) ~= "table" then return false end
		local ok_i, installed = pcall(pp.is_installed, pp)
		local ok_s, state = pcall(pp.applied_state, pp)
		local ok_c, intact = pcall(om.damage_profile_wire.catalog_intact,
			om._cwv_damage_wire_snapshot, om._cwv_damage_profile_generation)
		return ok_i and installed == true and ok_s and state == "enabled"
			and ok_c and intact == true
	end

	-- Legacy helper contract (/cwv_regression_test + _cwv_regression_render):
	-- returns the substitute for a cwv id, or nil for a vanilla id.
	om._wire_safe_damage_profile_id = function(id)
		local lookup = rawget(_G, "NetworkLookup")
		lookup = lookup and lookup.damage_profiles
		if not om._cwv_damage_wire_snapshot then
			local safe, disposition = om.damage_profile_wire.resolve_unconfirmed(
				lookup, om._cwv_damage_profile_wire_source, id)
			if disposition == "vanilla" then return nil end
			return safe
		end
		local safe, disposition = om.damage_profile_wire.profile_id_for_send(
			false, id, false, om._cwv_damage_wire_snapshot,
			om._cwv_damage_profile_generation)
		if disposition == "vanilla" then return nil end
		return safe
	end

	-- Pure gate decision, testable without a WeaponSystem instance.
	om._wire_dp_for_send = function(is_server, id)
		if is_server then return id, "server" end
		if not om._cwv_damage_wire_snapshot then
			-- No exact catalog: fall back to master's unconditional
			-- name-level floor rather than trusting presence parity.
			local lookup = rawget(_G, "NetworkLookup")
			lookup = lookup and lookup.damage_profiles
			return om.damage_profile_wire.resolve_unconfirmed(
				lookup, om._cwv_damage_profile_wire_source, id)
		end
		local ok, exact = pcall(mod._cwv_damage_wire_safe)
		return om.damage_profile_wire.profile_id_for_send(is_server, id,
			ok and exact == true, om._cwv_damage_wire_snapshot,
			om._cwv_damage_profile_generation)
	end

	-- Hook pre-flight (CLAUDE.md NON-NEGOTIABLE 8): grepped 2026-08-08 -- this
	-- is the ONLY cwv registration on (WeaponSystem, any method). It moved here
	-- from character_weapon_variants.lua so the entry chunk does not carry the
	-- exact-wire graph; do not re-add a second registration there.
	local logged = {}
	mod:hook("WeaponSystem", "send_rpc_attack_hit", function(func, self,
			damage_source_id, attacker_unit_id, hit_unit_id, hit_zone_id,
			hit_position, attack_direction, damage_profile_id, ...)
		local send_id, disposition = om._wire_dp_for_send(self.is_server, damage_profile_id)
		if disposition == "drop" then
			if not logged[damage_profile_id] then
				logged[damage_profile_id] = true
				local lookup = rawget(_G, "NetworkLookup")
				lookup = lookup and lookup.damage_profiles
				_printf("[cwv:423] blocked unsafe hit: profile=%s(%s) exact catalog unconfirmed and no vanilla fallback resolved",
					tostring(lookup and rawget(lookup, damage_profile_id)),
					tostring(damage_profile_id))
			end
			return nil
		end
		if send_id ~= damage_profile_id then
			if not logged[damage_profile_id] then
				logged[damage_profile_id] = true
				local lookup = rawget(_G, "NetworkLookup")
				lookup = lookup and lookup.damage_profiles
				_printf("[cwv:423] wire dmg-profile sub: %s(%s) -> %s (exact catalog unconfirmed; base-weapon damage this hit)",
					tostring(lookup and rawget(lookup, damage_profile_id)),
					tostring(damage_profile_id), tostring(send_id))
			end
			damage_profile_id = send_id
		end
		return func(self, damage_source_id, attacker_unit_id, hit_unit_id,
			hit_zone_id, hit_position, attack_direction, damage_profile_id, ...)
	end)
	om._dp_wire_hook_installed = true
end

return M
