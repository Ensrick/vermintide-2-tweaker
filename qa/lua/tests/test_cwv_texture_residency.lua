return function(H, repo_root)
	local module_path = repo_root
		.. "/character_weapon_variants/scripts/mods/character_weapon_variants/_cwv_old_musket_preview.lua"
	local policy = assert(loadfile(module_path))()

	local function apis(meshes)
		return {
			num_meshes = function() return #meshes end,
			mesh = function(_, index) return meshes[index + 1] end,
		}, {
			num_materials = function(mesh) return #mesh end,
			material = function(mesh, index) return mesh[index + 1] end,
		}
	end

	H.test("CWV #742 material census accepts a fully bound unit", function()
		local unit_api, mesh_api = apis({
			{ "#ID[12345678]" },
			{ "#ID[abcdef01]", "#ID[87654321]" },
		})
		local ready, count = policy.unit_materials_ready({}, unit_api, mesh_api)
		H.equal(ready, true)
		H.equal(count, 3)
	end)

	H.test("CWV #742 material census rejects Stingray's null sentinel", function()
		local unit_api, mesh_api = apis({ { "#ID[00000000]" } })
		local ready, reason = policy.unit_materials_ready({}, unit_api, mesh_api)
		H.equal(ready, false)
		H.equal(reason, "material-null-0-0")
	end)

	H.test("CWV #742 material census rejects missing and empty bindings", function()
		local unit_api, mesh_api = apis({ {} })
		local ready, reason = policy.unit_materials_ready({}, unit_api, mesh_api)
		H.equal(ready, false)
		H.equal(reason, "mesh-has-no-materials-0")

		unit_api, mesh_api = apis({ { "#ID[12345678]" } })
		mesh_api.material = function() return nil end
		ready, reason = policy.unit_materials_ready({}, unit_api, mesh_api)
		H.equal(ready, false)
		H.equal(reason, "material-unresolved-0-0")
	end)

	H.test("CWV #742 material census is atomic across every mesh", function()
		local unit_api, mesh_api = apis({
			{ "#ID[12345678]" },
			{ "#ID[00000000]" },
		})
		local ready, reason = policy.unit_materials_ready({}, unit_api, mesh_api)
		H.equal(ready, false)
		H.equal(reason, "material-null-1-0")
	end)

	H.test("CWV #742 material census fails closed when introspection raises", function()
		local unit_api, mesh_api = apis({ { "#ID[12345678]" } })
		unit_api.num_meshes = function() error("engine rejected unit") end
		local ready, reason = policy.unit_materials_ready({}, unit_api, mesh_api)
		H.equal(ready, false)
		H.equal(reason, "unit-has-no-meshes")

		unit_api, mesh_api = apis({ { "#ID[12345678]" } })
		mesh_api.num_materials = function() error("engine rejected mesh") end
		ready, reason = policy.unit_materials_ready({}, unit_api, mesh_api)
		H.equal(ready, false)
		H.equal(reason, "mesh-has-no-materials-0")
	end)
end
