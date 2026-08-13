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
		local quaternion_methods = {
			to_elements = function(q) return q.x, q.y, q.z, q.w end,
			from_euler_angles_xyz = function(x, y, z)
				return { x = x, y = y, z = z, w = 1 }
			end,
		}
		local quaternion_mt = options.noncallable_quaternion and {} or { __call = function(_, x, y, z, w)
			return { x = x, y = y, z = z, w = w,
				unbox = function(self) return self end }
		end }
		local quaternion = setmetatable(quaternion_methods, quaternion_mt)
		local unit_api = {}
		function unit_api.alive(unit) return alive[unit] == true end
		function unit_api.local_position(unit) return unit.position end
		function unit_api.local_scale(unit) return unit.scale end
		function unit_api.local_rotation(unit) return unit.rotation end
		function unit_api.set_local_pose(unit, _, pose)
			if not options.reject_pose then
				unit.position, unit.scale, unit.rotation = pose.position, pose.scale, pose.rotation
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
			PREVIEW_MATERIAL = "units/vanilla/handgun_3p",
			TEXTURES = { { slot = "albedo", texture = "textures/custom/albedo" } },
			matches_item = function(item, key)
				return key == "cwv_es_musket_old" or item.skin == "cwv_es_musket_old_skin"
			end,
			apply_textures = function()
				return not options.reject_textures, options.reject_textures and 0 or 1
			end,
			unit_materials_ready = function() return not options.reject_materials end,
		}
		local qbox = { unbox = function() return { x = 0, y = 0, z = 0, w = 1 } end }
		local pilot = Pilot.new({
			descriptor = D, weapon_appearance = WA, policy = policy,
			unit = unit_api, vector = vector, quaternion = quaternion,
			transform_source = function(perspective)
				-- Engine-like values are intentionally non-array tables. A descriptor
				-- builder that assumes `[1..3]` silently loses these fields.
				return perspective == "1p" and { x = 1, y = 2, z = 3 }
					or { x = 4, y = 5, z = 6 }, qbox,
					{ x = 0.9, y = 1.1, z = 1.2 }
			end,
			canonical_key = function(item) return item.cwv_key end,
			printf = function() end,
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
		}, "ranged", "owner_1p")
		H.truthy(descriptor, errors and table.concat(errors, "; "))
		H.deep_equal(descriptor.transform_1p.position, { 1, 2, 3 })
		H.deep_equal(descriptor.transform_3p.position, { 4, 5, 6 })
		H.deep_equal(descriptor.transform_3p.scale, { 0.9, 1.1, 1.2 })
		H.deep_equal(descriptor.transform_3p.rotation, { 0, 0, 0, 1 })
		H.equal(descriptor.right_hand_unit.unit_3p,
			"units/cwv_es_musket_custom/cwv_es_musket_custom_3p")
		H.truthy(#D.fingerprint(descriptor) == 8)
	end)

	H.test("CWV #1155 Old Musket adapter requires retained pose and material postconditions", function()
		local pilot, unit = fixture()
		local result = pilot.reconcile(unit, "owner_3p", "equip", {
			backend_id = "cwv_es_musket_old_001", cwv_key = "cwv_es_musket_old",
		}, "ranged", { unit_name = "units/cwv_es_musket_custom/cwv_es_musket_custom_3p" })
		H.equal(result.retained, true)
		H.equal(unit.position.x, 4)
		H.equal(unit.position.z, 6)
		H.equal(unit.scale.y, 1.1)

		local rejected, rejected_unit = fixture({ reject_pose = true })
		local failed = rejected.reconcile(rejected_unit, "owner_3p", "equip", {
			backend_id = "cwv_es_musket_old_001", cwv_key = "cwv_es_musket_old",
		}, "ranged", { unit_name = "units/cwv_es_musket_custom/cwv_es_musket_custom_3p" })
		H.equal(failed.retained, false)
		H.equal(failed.reason, "retained-postcondition-failed")

		local unpainted, unpainted_unit = fixture({ reject_textures = true })
		local paint_failed = unpainted.reconcile(unpainted_unit, "owner_3p", "equip", {
			backend_id = "cwv_es_musket_old_001", cwv_key = "cwv_es_musket_old",
		}, "ranged", { unit_name = "units/cwv_es_musket_custom/cwv_es_musket_custom_3p" })
		H.equal(paint_failed.retained, false)
		H.equal(paint_failed.observation.paint, false)

		local bad_constructor, bad_constructor_unit = fixture({ noncallable_quaternion = true })
		local constructor_failed = bad_constructor.reconcile(bad_constructor_unit,
			"owner_3p", "equip", {
				backend_id = "cwv_es_musket_old_001", cwv_key = "cwv_es_musket_old",
			}, "ranged", { unit_name = "units/cwv_es_musket_custom/cwv_es_musket_custom_3p" })
		H.equal(constructor_failed.retained, false)
		H.equal(constructor_failed.observation.apply, false)
	end)

	H.test("CWV #1155 explicit generation repairs retained state on the same live unit", function()
		local pilot, unit = fixture()
		local item = { backend_id = "cwv_es_musket_old_001", cwv_key = "cwv_es_musket_old" }
		local context = { unit_name = "units/cwv_es_musket_custom/cwv_es_musket_custom_3p" }
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
		H.equal(pilot.implemented_cells.cim_preview.preview_open, true)
		local result = pilot.reconcile(unit, "cim_preview", "preview_open", {
			backend_id = "cwv_es_musket_old_001", cwv_key = "cwv_es_musket_old",
		}, "ranged", {
			unit_name = "units/cwv_es_musket_custom/cwv_es_musket_custom_3p",
		})
		H.equal(result.ok, true)
		H.equal(result.retained, true)
		H.equal(result.fallback, nil)
	end)

	H.test("CWV #1155 Old Musket declares an adapter result for every surface-edge pair", function()
		local pilot, unit = fixture()
		for _, surface in ipairs(D.SURFACES) do
			for _, edge in ipairs(D.EDGES) do
				local result = pilot.reconcile(unit, surface, edge, {
					backend_id = "cwv_es_musket_old_001", cwv_key = "cwv_es_musket_old",
				}, "ranged", { unit_name = surface == "owner_1p"
					and "units/cwv_es_musket_custom/cwv_es_musket_custom"
					or "units/cwv_es_musket_custom/cwv_es_musket_custom_3p" })
				H.truthy(result.ok, surface .. "/" .. edge .. ": " .. tostring(result.reason))
				local implemented = pilot.implemented_cells[surface]
					and pilot.implemented_cells[surface][edge]
				if not implemented then H.equal(result.fallback, true) end
			end
		end
	end)
end
