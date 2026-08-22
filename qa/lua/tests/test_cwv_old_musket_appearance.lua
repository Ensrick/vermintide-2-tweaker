return function(H, repo_root)
	local D = dofile(repo_root .. "/tools/shared_lib/_lib_appearance_descriptor.lua")
	local WA_LIB = dofile(repo_root .. "/tools/shared_lib/_lib_weapon_appearance.lua")
	local Pilot = dofile(repo_root
		.. "/character_weapon_variants/scripts/mods/character_weapon_variants/_cwv_old_musket_appearance.lua")

	local function fixture(options)
		options = options or {}
		local alive = setmetatable({}, { __mode = "k" })
		local vector = { to_elements = function(v) return v.x, v.y, v.z end }
		local vector_new = function(x, y, z) return { x = x, y = y, z = z } end
		local raw_quaternion_kinds = setmetatable({}, { __mode = "k" })
		local quaternion_methods = {
			to_elements = function(q)
				local kind = raw_quaternion_kinds[q]
				if kind == "valid" then return 0, 0, 0, 1 end
				if kind == "invalid" then return 0 / 0, 0, 0, 1 end
				if type(q) == "table" and rawget(q, "raw_kind") == "valid" then
					return 0, 0, 0, 1
				end
				if type(q) == "table" and rawget(q, "raw_kind") == "invalid" then
					return 0 / 0, 0, 0, 1
				end
				return q.x, q.y, q.z, q.w
			end,
			from_euler_angles_xyz = function(x, y, z)
				return { x = x, y = y, z = z, w = 1 }
			end,
		}
		if not options.noncallable_quaternion then
			quaternion_methods.from_elements = function(x, y, z, w)
				if options.throw_constructor then error("constructor rejected quartet") end
				if options.nil_constructor then return nil end
				if options.raw_quaternion or options.invalid_raw_quaternion then
					local kind = options.invalid_raw_quaternion and "invalid" or "valid"
					if type(newproxy) == "function" then
						local raw = newproxy(true)
						getmetatable(raw).__index = function()
							error("opaque raw Quaternion")
						end
						raw_quaternion_kinds[raw] = kind
						return raw
					end
					return setmetatable({ raw_kind = kind }, {
						__index = function() error("opaque raw Quaternion") end,
					})
				end
				return { x = x, y = y, z = z, w = w,
					unbox = function(self) return self end }
			end
		end
		local quaternion = setmetatable(quaternion_methods, {
			__call = function() error("legacy callable Quaternion constructor used") end,
		})
		local unit_api = {}
		function unit_api.alive(unit) return alive[unit] == true end
		function unit_api.local_position(unit) return unit.position end
		function unit_api.local_scale(unit) return unit.scale end
		function unit_api.local_rotation(unit) return unit.rotation end
		function unit_api.set_local_pose(unit, _, pose)
			if options.reject_pose then error("linked root rejected pose") end
			if options.atomic_noop then return end
			unit.position, unit.scale = pose.position, pose.scale
			if options.antipode_pose then
				local x, y, z, w = quaternion_methods.to_elements(pose.rotation)
				unit.rotation = { x = -x, y = -y, z = -z, w = -w }
			else
				unit.rotation = pose.rotation
			end
		end
		local WA = WA_LIB.new({
			unit = unit_api,
			vector_new = vector_new,
			vector_to_elements = vector.to_elements,
			quaternion = quaternion,
			matrix4x4 = { from_quaternion_position_scale = function(rotation, position, scale)
				return { rotation = rotation, position = position, scale = scale }
			end },
		})
		local policy = {
			ITEM_KEY = "cwv_es_musket_old", SKIN_KEY = "cwv_es_musket_old_skin",
			UNIT = "units/cwv_es_musket_custom/cwv_es_musket_custom",
			UNIT_3P = "units/cwv_es_musket_custom/cwv_es_musket_custom_3p",
			PREVIEW_PACKAGE_ALIAS = "units/vanilla/handgun_3p",
			NETWORK_PACKAGE_ALIAS_1P = "units/vanilla/handgun",
			NETWORK_PACKAGE_ALIAS_3P = "units/vanilla/handgun_3p",
			MATERIAL = "units/cwv_es_musket_custom/cwv_es_musket_custom",
			PREVIEW_MATERIAL = "units/cwv_es_musket_custom/cwv_es_musket_custom",
			TEXTURES = { { slot = "albedo", texture = "textures/custom/albedo" } },
			matches_item = function(item, key)
				return key == "cwv_es_musket_old" or item.skin == "cwv_es_musket_old_skin"
			end,
			unit_materials_ready = function() return not options.reject_materials end,
		}
		local paint_ready = options.reject_textures ~= true
		policy.apply_material = function()
			return paint_ready, paint_ready and 1 or 0
		end
		policy.set_paint_ready = function(value) paint_ready = value == true end
		local qbox = { unbox = function() return { x = 0, y = 0, z = 0, w = 1 } end }
		local profiles = {
			held_1p_rifle = "held_1p_rifle",
			held_1p_polearm = "held_1p_polearm",
			held_3p_rifle_character = "held_3p_rifle_character",
			held_3p_polearm_character = "held_3p_polearm_character",
			display_3p_rifle = "display_3p_rifle",
		}
		local profile_positions = {
			held_1p_rifle = { x = 1, y = 2, z = 3 },
			held_1p_polearm = { x = 2, y = 3, z = 4 },
			held_3p_rifle_character = { x = 4, y = 5, z = 6 },
			held_3p_polearm_character = { x = 7, y = 8, z = 9 },
			display_3p_rifle = { x = 0, y = 0, z = 0 },
		}
		local pilot = Pilot.new({
			descriptor = D, weapon_appearance = WA, policy = policy,
			unit = unit_api, vector = vector, quaternion = quaternion,
			transform_profile_source = function(profile)
				-- Engine-like values are intentionally non-array tables. A descriptor
				-- builder that assumes `[1..3]` silently loses these fields.
				return profile_positions[profile], qbox,
					{ x = 0.9, y = 1.1, z = 1.2 }
			end,
			attachment_profiles = profiles,
			canonical_key = function(item) return item.cwv_key end,
			printf = options.printf or function() end,
		})
		local unit = { position = vector_new(0, 0, 0), scale = vector_new(1, 1, 1),
			rotation = { x = 0, y = 0, z = 0, w = 1 } }
		alive[unit] = true
		return pilot, unit, policy
	end

	H.test("CWV #1155 Old Musket descriptor preserves engine-like vectors and quaternion data", function()
		local pilot = fixture()
		local descriptor, errors = pilot.resolve({
			backend_id = "cwv_es_musket_old_001", cwv_key = "cwv_es_musket_old",
		}, "ranged", "owner_1p", { attachment_profile = "held_1p_rifle" })
		H.truthy(descriptor, errors and table.concat(errors, "; "))
		local data = D.raw(descriptor)
		H.equal(data.attachment_profile, "held_1p_rifle")
		H.deep_equal(data.transform_profiles.held_1p_rifle.position, { 1, 2, 3 })
		H.deep_equal(data.transform_profiles.held_3p_rifle_character.position, { 4, 5, 6 })
		H.deep_equal(data.transform_profiles.display_3p_rifle.position, { 0, 0, 0 })
		H.deep_equal(data.transform_profiles.held_3p_rifle_character.scale,
			{ 0.9, 1.1, 1.2 })
		H.deep_equal(data.transform_profiles.held_3p_rifle_character.rotation,
			{ 0, 0, 0, 1 })
		H.equal(data.right_hand_unit.unit_3p,
			"units/cwv_es_musket_custom/cwv_es_musket_custom_3p")
		H.equal(data.materials.authored,
			"units/cwv_es_musket_custom/cwv_es_musket_custom")
		H.equal(data.materials.preview, data.materials.authored)
		H.truthy(#D.fingerprint(descriptor) == 8)
	end)

	H.test("CWV #1155 constructs an opaque raw Quaternion only at the atomic write", function()
		local item = {
			backend_id = "cwv_es_musket_old_001", cwv_key = "cwv_es_musket_old",
		}
		local context = {
			unit_name = "units/cwv_es_musket_custom/cwv_es_musket_custom_3p",
			attachment_profile = "held_3p_rifle_character",
		}
		local raw, raw_unit = fixture({ raw_quaternion = true })
		local retained = raw.reconcile(raw_unit, "owner_3p", "equip",
			item, "ranged", context)
		H.equal(retained.retained, true)
		H.equal(retained.observation.rotation_constructed, true)
		H.equal(retained.observation.rotation_write, true)
		H.equal(retained.observation.transform_mode, "atomic-local-pose")
		H.equal(retained.observation.transform_error, nil)

		local invalid, invalid_unit = fixture({
			invalid_raw_quaternion = true,
		})
		local rejected = invalid.reconcile(invalid_unit, "owner_3p", "equip",
			item, "ranged", context)
		H.equal(rejected.retained, false)
		H.equal(rejected.observation.rotation_constructed, false)
		H.equal(rejected.observation.transform_error, "invalid-rotation")
		H.equal(rejected.observation.rotation_write, false)

		for _, options in ipairs({
			{ throw_constructor = true }, { nil_constructor = true },
		}) do
			local failed, failed_unit = fixture(options)
			local result = failed.reconcile(failed_unit, "owner_3p", "equip",
				item, "ranged", context)
			H.equal(result.retained, false)
			H.equal(result.observation.rotation_constructed, false)
			H.equal(result.observation.transform_error, "invalid-rotation")
		end
	end)

	H.test("CWV #1155 atomic rejection or no-op cannot claim retained pose", function()
		local item = {
			backend_id = "cwv_es_musket_old_001", cwv_key = "cwv_es_musket_old",
		}
		local context = {
			unit_name = "units/cwv_es_musket_custom/cwv_es_musket_custom_3p",
			attachment_profile = "held_3p_rifle_character",
		}
		local rejected, rejected_unit = fixture({ reject_pose = true })
		local rejected_result = rejected.reconcile(rejected_unit, "owner_3p", "equip",
			item, "ranged", context)
		H.equal(rejected_result.retained, false)
		H.equal(rejected_result.observation.apply, false)
		H.equal(rejected_result.observation.transform_mode, "atomic-local-pose")
		H.truthy(type(rejected_result.observation.transform_error) == "string")
		H.equal(rejected_result.observation.rotation_constructed, true)
		H.equal(rejected_result.observation.position_write, false)
		H.equal(rejected_result.observation.scale_write, false)
		H.equal(rejected_result.observation.rotation_write, false)

		local noop, noop_unit = fixture({ atomic_noop = true })
		local noop_result = noop.reconcile(noop_unit, "owner_3p", "equip",
			item, "ranged", context)
		H.equal(noop_result.retained, false)
		H.equal(noop_result.observation.apply, true)
		H.equal(noop_result.observation.rotation_constructed, true)
		H.equal(noop_result.observation.position, false)
		H.equal(noop_result.observation.scale, false)
	end)

	H.test("CWV #1155 Old Musket adapter requires retained pose and material postconditions", function()
		local pilot, unit = fixture()
		local result = pilot.reconcile(unit, "owner_3p", "equip", {
			backend_id = "cwv_es_musket_old_001", cwv_key = "cwv_es_musket_old",
		}, "ranged", { unit_name = "units/cwv_es_musket_custom/cwv_es_musket_custom_3p",
			attachment_profile = "held_3p_rifle_character" })
		H.equal(result.retained, true)
		H.equal(unit.position.x, 4)
		H.equal(unit.position.z, 6)
		H.equal(unit.scale.y, 1.1)

		local rejected, rejected_unit = fixture({ reject_pose = true })
		local failed = rejected.reconcile(rejected_unit, "owner_3p", "equip", {
			backend_id = "cwv_es_musket_old_001", cwv_key = "cwv_es_musket_old",
		}, "ranged", { unit_name = "units/cwv_es_musket_custom/cwv_es_musket_custom_3p",
			attachment_profile = "held_3p_rifle_character" })
		H.equal(failed.retained, false)
		H.equal(failed.observation.transform_mode, "atomic-local-pose")
		H.truthy(type(failed.observation.transform_error) == "string")
		H.equal(failed.observation.position_write, false)
		H.equal(failed.observation.scale_write, false)
		H.equal(failed.observation.rotation_write, false)

		local antipode, antipode_unit = fixture({ antipode_pose = true })
		local antipode_result = antipode.reconcile(antipode_unit, "owner_3p", "equip", {
			backend_id = "cwv_es_musket_old_001", cwv_key = "cwv_es_musket_old",
		}, "ranged", { unit_name = "units/cwv_es_musket_custom/cwv_es_musket_custom_3p",
			attachment_profile = "held_3p_rifle_character" })
		H.equal(antipode_result.retained, true,
			"q and -q must compare as the same retained rotation")
		H.deep_equal(antipode_result.observation.actual_rotation, { 0, 0, 0, -1 })

		local unpainted, unpainted_unit = fixture({ reject_textures = true })
		local paint_failed = unpainted.reconcile(unpainted_unit, "owner_3p", "equip", {
			backend_id = "cwv_es_musket_old_001", cwv_key = "cwv_es_musket_old",
		}, "ranged", { unit_name = "units/cwv_es_musket_custom/cwv_es_musket_custom_3p",
			attachment_profile = "held_3p_rifle_character" })
		H.equal(paint_failed.retained, false)
		H.equal(paint_failed.observation.paint, false)

		local bad_constructor, bad_constructor_unit = fixture({ noncallable_quaternion = true })
		local constructor_failed = bad_constructor.reconcile(bad_constructor_unit,
			"owner_3p", "equip", {
				backend_id = "cwv_es_musket_old_001", cwv_key = "cwv_es_musket_old",
			}, "ranged", { unit_name = "units/cwv_es_musket_custom/cwv_es_musket_custom_3p",
				attachment_profile = "held_3p_rifle_character" })
		H.equal(constructor_failed.retained, false)
		H.equal(constructor_failed.observation.apply, false)
		H.equal(constructor_failed.observation.rotation_constructed, false)
	end)

	H.test("CWV #1155 evidence exposes bounded per-channel actual and expected pose truth", function()
		local logs = {}
		local pilot, unit = fixture({
			printf = function(fmt, ...)
				logs[#logs + 1] = string.format(fmt, ...)
			end,
		})
		local item = {
			backend_id = "cwv_es_musket_old_001", cwv_key = "cwv_es_musket_old",
		}
		local cim = pilot.reconcile(unit, "cim_preview", "preview_open", item,
			"ranged", {
				unit_name = "units/cwv_es_musket_custom/cwv_es_musket_custom_3p",
				attachment_profile = "display_3p_rifle",
				cim_generation = 1,
			})
		H.equal(cim.retained, true)
		local failed = pilot.reconcile(unit, "owner_3p", "equip", item,
			"ranged", {
				unit_name = "units/cwv_es_musket_custom/cwv_es_musket_custom_3p",
				attachment_profile = "held_3p_rifle_character",
			})
		H.equal(failed.retained, true)
		local before_duplicate = #logs
		local duplicate = pilot.reconcile(unit, "owner_3p", "equip", item,
			"ranged", {
				unit_name = "units/cwv_es_musket_custom/cwv_es_musket_custom_3p",
				attachment_profile = "held_3p_rifle_character",
			})
		H.equal(duplicate.coalesced, true)
		H.equal(#logs, before_duplicate,
			"a duplicate lifecycle wrapper must not emit another structured receipt")

		local row = pilot.live_status().surfaces.owner_3p.ranged
		H.equal(row.paint, true)
		H.equal(row.apply, true)
		H.equal(row.materials, true)
		H.equal(row.position, true)
		H.equal(row.scale, true)
		H.equal(row.rotation, true)
		H.equal(row.transform_mode, "atomic-local-pose")
		H.equal(row.transform_error, nil)
		H.equal(row.rotation_constructed, true)
		H.equal(row.position_write, true)
		H.equal(row.scale_write, true)
		H.equal(row.rotation_write, true)
		H.deep_equal(row.actual_position, { 4, 5, 6 })
		H.deep_equal(row.expected_position, { 4, 5, 6 })
		H.deep_equal(row.actual_scale, { 0.9, 1.1, 1.2 })
		H.deep_equal(row.expected_scale, { 0.9, 1.1, 1.2 })
		H.deep_equal(row.actual_rotation, { 0, 0, 0, 1 })
		H.deep_equal(row.expected_rotation, { 0, 0, 0, 1 })
		H.truthy(logs[#logs]:find("paint=true apply=true materials=true", 1, true))
		H.truthy(logs[#logs]:find(
			"transform_mode=atomic-local-pose", 1, true))
		H.truthy(logs[#logs]:find(
			"actual_position=[4.00000,5.00000,6.00000] expected_position=[4.00000,5.00000,6.00000]",
			1, true))

		row.actual_position[1] = 1155
		H.equal(pilot.live_status().surfaces.owner_3p.ranged.actual_position[1], 4,
			"callers must not be able to mutate retained evidence tuples")
	end)

	H.test("CWV #1155 explicit generation repairs retained state on the same live unit", function()
		local pilot, unit = fixture()
		local item = { backend_id = "cwv_es_musket_old_001", cwv_key = "cwv_es_musket_old" }
		local context = { unit_name = "units/cwv_es_musket_custom/cwv_es_musket_custom_3p",
			attachment_profile = "held_3p_rifle_character" }
		local first, descriptor = pilot.reconcile(unit, "owner_3p", "equip", item, "ranged", context)
		H.equal(first.retained, true)
		unit.position = { x = 99, y = 99, z = 99 }
		H.equal(pilot.reapply_tracked(), 1)
		H.equal(unit.position.x, 4)
		local next_descriptor = pilot.resolve(item, "ranged", "owner_3p", context)
		H.equal(next_descriptor.generation, descriptor.generation + 1)
	end)

	H.test("CWV #1155 CIM preview-open is a retained implemented adapter cell", function()
		local pilot, unit = fixture()
		H.equal(pilot.implemented_cells.cim_preview.instance_load, true)
		H.equal(pilot.implemented_cells.cim_preview.preview_open, true)
		local result = pilot.reconcile(unit, "cim_preview", "preview_open", {
			backend_id = "cwv_es_musket_old_001", cwv_key = "cwv_es_musket_old",
		}, "ranged", {
			unit_name = "units/cwv_es_musket_custom/cwv_es_musket_custom_3p",
			attachment_profile = "display_3p_rifle",
			cim_generation = 1,
		})
		H.equal(result.ok, true)
		H.equal(result.retained, true)
		H.equal(result.fallback, nil)
	end)

	H.test("CWV #1155 CIM evidence rejects invalid generations without poisoning recovery", function()
		local pilot, unit = fixture()
		local item = {
			backend_id = "cwv_es_musket_old_001", cwv_key = "cwv_es_musket_old",
		}
		local function reconcile(generation)
			return pilot.reconcile(unit, "cim_preview", "preview_open", item,
				"ranged", {
					unit_name = "units/cwv_es_musket_custom/cwv_es_musket_custom_3p",
					attachment_profile = "display_3p_rifle",
					cim_generation = generation,
				})
		end
		for _, generation in ipairs({ 1.5, math.huge }) do
			local rejected = reconcile(generation)
			H.equal(rejected.ok, false)
			H.equal(rejected.reason, "identity-unresolved")
			H.equal(pilot.live_status().epoch, 0)
		end
		local recovered = reconcile(1)
		H.equal(recovered.retained, true)
		H.equal(pilot.live_status().cim_generation, 1)
	end)

	H.test("CWV #1155 duplicate construction failures coalesce and stable edge retries once", function()
		local pilot, unit, policy = fixture()
		local item = {
			backend_id = "cwv_es_musket_old_001", cwv_key = "cwv_es_musket_old",
		}
		local context = {
			unit_name = "units/cwv_es_musket_custom/cwv_es_musket_custom_3p",
			attachment_profile = "display_3p_rifle",
			cim_generation = 1,
		}
		policy.set_paint_ready(false)
		local first = pilot.reconcile(unit, "cim_preview", "instance_load",
			item, "ranged", context)
		local duplicate = pilot.reconcile(unit, "cim_preview", "instance_load",
			item, "ranged", context)
		H.equal(first.retained, false)
		H.equal(first.attempts, 1)
		H.equal(duplicate.coalesced, true)
		H.equal(duplicate.attempts, 1)

		policy.set_paint_ready(true)
		local stable = pilot.reconcile(unit, "cim_preview", "preview_open",
			item, "ranged", context)
		H.equal(stable.retained, true)
		H.equal(stable.attempts, 1)
		local status = pilot.live_status()
		H.equal(status.exercised, 1)
		H.equal(status.failed, 0)
		H.equal(status.retained, 1)
		H.equal(status.surfaces.cim_preview.ranged.edge, "preview_open")
		H.equal(status.surfaces.cim_preview.ranged.retained, true)
	end)

	H.test("CWV #1155 evidence is bounded by renderer-owned cells and clears on disconnect", function()
		local pilot, unit = fixture()
		local cim_item = {
			backend_id = "cwv_es_musket_old_001", cwv_key = "cwv_es_musket_old",
		}
		local equipped_item = {
			backend_id = "cwv_es_musket_old_002", cwv_key = "cwv_es_musket_old",
		}
		local context = {
			unit_name = "units/cwv_es_musket_custom/cwv_es_musket_custom_3p",
			attachment_profile = "display_3p_rifle",
			cim_generation = 1,
		}
		H.equal(pilot.live_status().exercised, 0)
		local prearm = pilot.reconcile(unit, "illusion_browser", "preview_open",
			equipped_item, "ranged", context)
		H.equal(prearm.retained, true)
		H.equal(pilot.live_status().exercised, 0,
			"ordinary renderers must not choose the exact instance owned by the live gate")
		local armed = pilot.reconcile(unit, "cim_preview", "preview_open",
			cim_item, "ranged", context)
		H.equal(armed.retained, true)
		local held = pilot.reconcile(unit, "owner_3p", "equip",
			equipped_item, "ranged", {
				unit_name = context.unit_name,
				attachment_profile = "held_3p_rifle_character",
			})
		H.equal(held.retained, true)
		local equipped_identity = {
			kind = "backend_id", value = "cwv_es_musket_old_002",
		}
		H.equal(pilot.live_target_matches(
			"owner_3p", "ranged", unit, equipped_identity), true)
		H.equal(pilot.live_target_matches(
			"owner_3p", "ranged", {}, equipped_identity), false,
			"swapping to another live unit must invalidate the stored-target proof")
		H.equal(pilot.live_target_matches("owner_3p", "ranged", unit,
			{ kind = "backend_id", value = "another-instance" }), false)
		local browser_context = {
			unit_name = context.unit_name,
			attachment_profile = "display_3p_rifle",
			preview_identity = "browser:old-musket-skin",
			preview_generation = 1,
		}
		local constructed = pilot.reconcile(unit, "illusion_browser", "instance_load",
			equipped_item, "ranged", browser_context)
		H.equal(constructed.retained, true)
		local visible = pilot.reconcile(unit, "illusion_browser", "preview_open",
			equipped_item, "ranged", browser_context)
		H.equal(visible.retained, true)
		local status = pilot.live_status()
		H.equal(status.exercised, 3)
		H.equal(status.generation, 0)
		H.equal(status.epoch, 1)
		H.deep_equal(status.identity,
			{ kind = "backend_id", value = "cwv_es_musket_old_002" })
		H.deep_equal(status.cim_identity,
			{ kind = "backend_id", value = "cwv_es_musket_old_001" })
		H.equal(status.cim_generation, 1)
		H.equal(status.surfaces.illusion_browser.ranged.mode, "ranged")
		H.equal(status.surfaces.illusion_browser.ranged.edge, "preview_open")
		H.equal(status.surfaces.illusion_browser.ranged.preview_generation, 1)
		H.deep_equal(status.surfaces.illusion_browser.ranged.identity, {
			kind = "preview_slot", value = "browser:old-musket-skin",
		})
		H.deep_equal(status.preview_lifecycles.illusion_browser, {
			generation = 1,
			identity = { kind = "preview_slot", value = "browser:old-musket-skin" },
		})
		status.identity.value = "mutated"
		status.cim_identity.value = "mutated"
		status.surfaces.illusion_browser.ranged.identity.value = "mutated"
		status.preview_lifecycles.illusion_browser.identity.value = "mutated"
		local detached = pilot.live_status()
		H.equal(detached.identity.value, "cwv_es_musket_old_002")
		H.equal(detached.cim_identity.value, "cwv_es_musket_old_001")
		H.equal(detached.surfaces.illusion_browser.ranged.identity.value,
			"browser:old-musket-skin")
		H.equal(detached.preview_lifecycles.illusion_browser.identity.value,
			"browser:old-musket-skin")
		H.equal(pilot.disconnect(), true)
		H.equal(pilot.live_status().exercised, 0)
	end)

	H.test("CWV #1156 browser evidence rejects missing, stale, foreign, and failed visible edges", function()
		local pilot, unit, policy = fixture()
		local cim_item = {
			backend_id = "cwv_es_musket_old_001", cwv_key = "cwv_es_musket_old",
		}
		local held_item = {
			backend_id = "cwv_es_musket_old_002", cwv_key = "cwv_es_musket_old",
		}
		local base = {
			unit_name = "units/cwv_es_musket_custom/cwv_es_musket_custom_3p",
			attachment_profile = "display_3p_rifle",
		}
		pilot.reconcile(unit, "cim_preview", "preview_open", cim_item,
			"ranged", {
				unit_name = base.unit_name,
				attachment_profile = base.attachment_profile,
				cim_generation = 1,
			})
		pilot.reconcile(unit, "owner_3p", "equip", held_item, "ranged", {
			unit_name = base.unit_name,
			attachment_profile = "held_3p_rifle_character",
		})
		local function browser(edge, identity, generation)
			return pilot.reconcile(unit, "illusion_browser", edge, {
				cwv_key = "cwv_es_musket_old", skin = "cwv_es_musket_old_skin",
			}, "ranged", {
				unit_name = base.unit_name,
				attachment_profile = base.attachment_profile,
				preview_identity = identity,
				preview_generation = generation,
			})
		end

		browser("instance_load", "browser:first", 1)
		local row = pilot.live_status().surfaces.illusion_browser.ranged
		H.equal(row.edge, "instance_load",
			"construction without the source visibility edge must remain visibly incomplete")

		browser("preview_open", "browser:foreign", 1)
		row = pilot.live_status().surfaces.illusion_browser.ranged
		H.equal(row.retained, false)
		H.equal(row.reason, "preview-identity-mismatch")

		browser("instance_load", "browser:second", 2)
		browser("preview_open", "browser:first", 1)
		row = pilot.live_status().surfaces.illusion_browser.ranged
		H.equal(row.retained, true)
		H.equal(row.edge, "instance_load")
		H.equal(row.preview_generation, 2,
			"a stale delivery must preserve the newer construction evidence")

		browser("preview_open", "browser:second", 2)
		row = pilot.live_status().surfaces.illusion_browser.ranged
		H.equal(row.retained, true)
		H.equal(row.edge, "preview_open")
		H.equal(row.preview_generation, 2)
		local current_fingerprint = row.fingerprint

		browser("instance_load", "browser:first", 1)
		browser("preview_open", "browser:first", 1)
		row = pilot.live_status().surfaces.illusion_browser.ranged
		H.equal(row.retained, true)
		H.equal(row.edge, "preview_open")
		H.equal(row.preview_generation, 2)
		H.equal(row.fingerprint, current_fingerprint,
			"late stale callbacks must not overwrite the latest visible success")
		H.deep_equal(pilot.live_status().preview_lifecycles.illusion_browser, {
			generation = 2,
			identity = { kind = "preview_slot", value = "browser:second" },
		})

		policy.set_paint_ready(false)
		browser("instance_load", "browser:third", 3)
		browser("preview_open", "browser:third", 3)
		row = pilot.live_status().surfaces.illusion_browser.ranged
		H.equal(row.retained, false)
		H.equal(row.paint, false,
			"a genuinely failed visible material postcondition must remain a failure")

		pilot.reconcile(unit, "cim_preview", "preview_open", {
			backend_id = "cwv_es_musket_old_003", cwv_key = "cwv_es_musket_old",
		}, "ranged", {
			unit_name = base.unit_name,
			attachment_profile = base.attachment_profile,
			cim_generation = 2,
		})
		H.equal(next(pilot.live_status().preview_lifecycles), nil,
			"a new exact evidence epoch must not inherit an older browser lifecycle")
	end)

	H.test("CWV #1155 live evidence rejects stale generations and prior item instances", function()
		local pilot, unit = fixture()
		local first_item = {
			backend_id = "cwv_es_musket_old_001", cwv_key = "cwv_es_musket_old",
		}
		local second_item = {
			backend_id = "cwv_es_musket_old_002", cwv_key = "cwv_es_musket_old",
		}
		local context = {
			unit_name = "units/cwv_es_musket_custom/cwv_es_musket_custom_3p",
			attachment_profile = "display_3p_rifle",
			cim_generation = 1,
		}
		local first = pilot.reconcile(unit, "cim_preview", "preview_open",
			first_item, "ranged", context)
		H.equal(first.retained, true)
		local before_tune = pilot.live_status()
		H.equal(before_tune.surfaces.cim_preview.ranged.generation, 0)
		H.equal(before_tune.generation, 0)
		local held = pilot.reconcile(unit, "owner_3p", "equip", second_item,
			"ranged", {
				unit_name = context.unit_name,
				attachment_profile = "held_3p_rifle_character",
			})
		H.equal(held.retained, true)
		H.equal(pilot.reapply_tracked(), 1,
			"only the held owner unit participates in explicit customize")
		local interleaved = pilot.reconcile(unit, "bot", "equip", first_item,
			"ranged", {
				unit_name = context.unit_name,
				attachment_profile = "held_3p_rifle_character",
			})
		H.equal(interleaved.retained, true)
		H.equal(pilot.live_status().identity.value, "cwv_es_musket_old_002",
			"a second slot or bot identity must not steal the CIM-armed test epoch")
		local stale = pilot.live_status()
		H.equal(stale.generation, 1)
		H.equal(stale.surfaces.cim_preview.ranged.generation, 0,
			"a tuner edit must leave preview proof stale until the preview is reopened")
		local refreshed = pilot.reconcile(unit, "cim_preview", "preview_open",
			first_item, "ranged", context)
		H.equal(refreshed.retained, true)
		H.equal(pilot.live_status().surfaces.cim_preview.ranged.generation, 1)

		local unresolved = pilot.reconcile(unit, "cim_preview", "preview_open",
			second_item, "ranged", {
				unit_name = context.unit_name, cim_generation = 2,
			})
		H.equal(unresolved.ok, false)
		H.equal(unresolved.reason, "identity-unresolved")
		local replaced = pilot.live_status()
		H.equal(replaced.epoch, 2)
		H.equal(replaced.identity, nil)
		H.deep_equal(replaced.cim_identity,
			{ kind = "backend_id", value = "cwv_es_musket_old_002" })
		H.equal(replaced.exercised, 1,
			"a new exact instance must clear every prior-instance cell")
		H.equal(replaced.surfaces.cim_preview.ranged.retained, false)
		H.equal(replaced.surfaces.cim_preview.ranged.reason, "identity-unresolved")
		H.equal(replaced.surfaces.cim_preview.ranged.fingerprint, nil)
		H.equal(replaced.surfaces.cim_preview.ranged.identity.value,
			"cwv_es_musket_old_002")
		local late = pilot.reconcile(unit, "cim_preview", "preview_open",
			first_item, "ranged", context)
		H.equal(late.ok, false)
		H.equal(pilot.live_status().epoch, 2,
			"a late provider generation must not re-arm stale evidence")
	end)

	H.test("CWV #1155 unobserved custom identity fails closed without a native write", function()
		local pilot, unit = fixture()
		local result = pilot.reconcile(unit, "owner_3p", "equip", {
			backend_id = "cwv_es_musket_old_001", cwv_key = "cwv_es_musket_old",
		}, "ranged", { attachment_profile = "held_3p_rifle_character" })
		H.equal(result.retained, false)
		H.equal(result.fallback, true)
		H.equal(result.reason, "custom-unit-not-retained")
		H.equal(unit.position.x, 0)
	end)

	H.test("CWV #1155 Old Musket declares an adapter result for every surface-edge pair", function()
		local pilot, unit = fixture()
		for _, surface in ipairs(D.SURFACES) do
			for _, edge in ipairs(D.EDGES) do
				local result = pilot.reconcile(unit, surface, edge, {
					backend_id = "cwv_es_musket_old_001", cwv_key = "cwv_es_musket_old",
				}, "ranged", { unit_name = surface == "owner_1p"
					and "units/cwv_es_musket_custom/cwv_es_musket_custom"
					or "units/cwv_es_musket_custom/cwv_es_musket_custom_3p",
					attachment_profile = surface == "owner_1p"
						and "held_1p_rifle" or "held_3p_rifle_character",
					cim_generation = surface == "cim_preview" and 1 or nil })
				H.truthy(result.ok, surface .. "/" .. edge .. ": " .. tostring(result.reason))
				local implemented = pilot.implemented_cells[surface]
					and pilot.implemented_cells[surface][edge]
				if not implemented then H.equal(result.fallback, true) end
			end
		end
	end)
end
