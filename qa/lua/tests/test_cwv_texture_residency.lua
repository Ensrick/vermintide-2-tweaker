return function(H, repo_root)
	local module_path = repo_root
		.. "/character_weapon_variants/scripts/mods/character_weapon_variants/_cwv_old_musket_preview.lua"
	local policy = assert(loadfile(module_path))()
	local residency = assert(loadfile(repo_root
		.. "/character_weapon_variants/scripts/mods/character_weapon_variants/_lib_resource_residency.lua"))()
	policy.set_resource_residency(residency)

	local function apis(meshes)
		return {
			alive = function() return true end,
			num_meshes = function() return #meshes end,
			mesh = function(_, index) return meshes[index + 1] end,
		}, {
			num_materials = function(mesh) return #mesh end,
			material = function(mesh, index) return mesh[index + 1] end,
		}
	end

	local function apply_fixture(options)
		options = options or {}
		local events, probes = {}, {}
		local meshes = options.meshes or { { "#ID[11551155]" } }
		local application = {
			can_get = function(kind, path)
				events[#events + 1] = "probe:" .. tostring(kind) .. ":" .. tostring(path)
				probes[#probes + 1] = { kind = kind, path = path }
				if options.throw_probe == kind
						or options.throw_probe == kind .. ":" .. tostring(path) then
					error("probe rejected")
				end
				if kind == "texture" then
					return options.missing_texture ~= path
				end
				if kind == "material" then return options.material_ready ~= false end
				return false
			end,
		}
		local unit_api = {
			alive = function()
				events[#events + 1] = "alive"
				if options.throw_alive then error("alive rejected") end
				return options.alive ~= false
			end,
			set_all_materials = function(_, material)
				events[#events + 1] = "bind:" .. tostring(material)
				if options.throw_bind then error("bind rejected") end
			end,
			num_meshes = function()
				events[#events + 1] = "num_meshes"
				if options.throw_num_meshes then error("mesh census rejected") end
				return #meshes
			end,
			mesh = function(_, index)
				events[#events + 1] = "mesh:" .. tostring(index)
				if options.throw_mesh then error("mesh rejected") end
				return meshes[index + 1]
			end,
		}
		local mesh_api = {
			num_materials = function(mesh)
				events[#events + 1] = "num_materials"
				if options.throw_num_materials then error("material count rejected") end
				return #mesh
			end,
			material = function(mesh, index)
				events[#events + 1] = "material:" .. tostring(index)
				if options.throw_material then error("material rejected") end
				return mesh[index + 1]
			end,
		}
		local ok, count = policy.apply_material({}, options.preview == true, {
			application = application, unit = unit_api, mesh = mesh_api,
		})
		return ok, count, events, probes
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

	H.test("CWV #1155 authored material bind proves all resources before one native write", function()
		for _, preview in ipairs({ false, true }) do
			local ok, count, events, probes = apply_fixture({ preview = preview })
			H.equal(ok, true)
			H.equal(count, 5)
			H.equal(#probes, 6)
			for index, binding in ipairs(policy.TEXTURES) do
				H.equal(probes[index].kind, "texture")
				H.equal(probes[index].path, binding.texture)
			end
			H.equal(probes[6].kind, "material")
			H.equal(probes[6].path, policy.MATERIAL)
			H.equal(events[1], "alive")
			H.equal(events[7], "probe:material:" .. policy.MATERIAL)
			H.equal(events[8], "bind:" .. policy.MATERIAL)
			H.equal(events[9], "alive")
			H.equal(events[10], "num_meshes")
		end
	end)

	H.test("CWV #1155 authored material bind fails before writes on liveness and resource errors", function()
		local first_texture = policy.TEXTURES[1].texture
		for _, options in ipairs({
			{ alive = false },
			{ throw_alive = true },
			{ missing_texture = first_texture },
			{ throw_probe = "texture:" .. first_texture },
			{ material_ready = false },
			{ throw_probe = "material" },
		}) do
			local ok, count, events = apply_fixture(options)
			H.equal(ok, false)
			H.equal(count, 0)
			for _, event in ipairs(events) do
				H.equal(event:find("bind:", 1, true), nil,
					"native material write preceded complete closure")
			end
		end
	end)

	H.test("CWV #1155 authored material bind contains native and post-bind errors", function()
		for _, options in ipairs({
			{ throw_bind = true },
			{ throw_num_meshes = true },
			{ throw_mesh = true },
			{ throw_num_materials = true },
			{ throw_material = true },
			{ meshes = { { "#ID[00000000]" } } },
			{ meshes = { {} } },
		}) do
			local ok, count, events = apply_fixture(options)
			H.equal(ok, false)
			H.equal(count, 0)
			local binds = 0
			for _, event in ipairs(events) do
				if event == "bind:" .. policy.MATERIAL then binds = binds + 1 end
			end
			H.equal(binds, 1, "post-closure path must attempt exactly one authored bind")
		end
	end)

	H.test("CWV #1155 production source never performs runtime texture painting", function()
		local file = assert(io.open(module_path, "rb"))
		local source = file:read("*a")
		file:close()
		H.equal(source:find("\n\tUnit.set_texture_for_materials(", 1, true), nil)
		H.equal(source:find("\n\tMaterial.set_texture(", 1, true), nil)
	end)
end
