return function(H, repo_root)
	local policy = dofile(repo_root
		.. "/weapons_of_chaos/scripts/mods/weapons_of_chaos/_woc_appearance_policy.lua")
	local pulse = dofile(repo_root
		.. "/weapons_of_chaos/scripts/mods/weapons_of_chaos/_woc_blightreaper_pulse.lua")
	local durable = dofile(repo_root
		.. "/weapons_of_chaos/scripts/mods/weapons_of_chaos/_woc_durable_transform.lua")
	local function copy(value)
		local out = {}
		for i = 1, #value do out[i] = value[i] end
		return out
	end

	local function fixture(missing)
		local calls = {
			materials = {}, textures = {}, variables = {}, transforms = 0,
			transform_specs = {}, transform_perspectives = {},
			transform_surfaces = {},
		}
		local unit = {}
		local api = {
			unit = {
				alive = function(value) return value == unit end,
				has_node = function(value, name)
					return value == unit and name == policy.TRANSFORM_NODE_NAME
				end,
				node = function(value, name)
					return value == unit and name == policy.TRANSFORM_NODE_NAME and 2 or nil
				end,
				set_all_materials = function(value, material)
					calls.materials[#calls.materials + 1] = { value, material }
				end,
				set_texture_for_materials = function(value, slot, texture)
					calls.textures[#calls.textures + 1] = { value, slot, texture }
				end,
			},
			application = {
				can_get = function(_, name) return name ~= missing end,
			},
			script_unit = {
				set_material_variable = function(value, name, variable, children)
					calls.variables[#calls.variables + 1] = {
						value, name, variable, children,
					}
				end,
			},
			printf = function() calls.diagnostics = (calls.diagnostics or 0) + 1 end,
		}
		local transform = {
			apply = function(_, value, spec, perspective, surface)
				calls.transforms = calls.transforms + 1
				calls.transform_specs[#calls.transform_specs + 1] = spec
				calls.transform_perspectives[#calls.transform_perspectives + 1] = perspective
				calls.transform_surfaces[#calls.transform_surfaces + 1] = surface
				return value == unit and spec.node == 2
					and spec.scale == policy.TRANSFORM.scale
					and spec.offset == policy.TRANSFORM.offset
					and spec.rotation == policy.TRANSFORM.rotation
			end,
		}
		return pulse.new(policy, transform, api), unit, calls
	end

	H.test("WOC #613 donor reproduces the native bounded pulse contract", function()
		local one = policy.pulse_descriptor("1p")
		local three = policy.pulse_descriptor("3p")
		H.equal(one.material, policy.VANILLA_1P)
		H.equal(three.material, policy.VANILLA_3P)
		H.equal(#one.textures, 6)
		H.equal(#three.textures, 6)
		H.equal(one.textures[4].slot, "texture_map_4617b8e0")
		H.equal(three.textures[4].slot, "texture_map_ee282ea2")
		H.equal(#policy.PULSE_VARIABLES, 3)
		H.equal(policy.PULSE_VARIABLES[1].name, "rune_emissive_color")
		H.equal(policy.PULSE_VARIABLES[1].value[1], 5)
		H.equal(policy.PULSE_VARIABLES[2].name, "intensity")
		H.equal(policy.PULSE_VARIABLES[2].value, 1.746000051498413)
		H.equal(policy.PULSE_VARIABLES[3].name, "pulse")
	end)

	H.test("WOC #613 paints one spawned unit once with no polling", function()
		local runtime, unit, calls = fixture()
		local ok, reason = runtime.apply(unit, policy.TRANSFORM, "3p", "test")
		H.truthy(ok)
		H.equal(reason, "applied")
		H.equal(#calls.materials, 1)
		H.equal(#calls.textures, 6)
		H.equal(#calls.variables, 3)
		H.equal(calls.transforms, 1)
		H.equal(calls.variables[1][4], true)

		local again, repeated = runtime.apply(unit, policy.TRANSFORM, "3p", "test")
		H.truthy(again)
		H.equal(repeated, "already-applied")
		H.equal(#calls.materials, 1)
		H.equal(#calls.textures, 6)
		H.equal(calls.transforms, 1)
	end)

	H.test("WOC #613 sends the exact canonical 90 transform through 1P and 3P pulse paths", function()
		for _, perspective in ipairs({ "1p", "3p" }) do
			local runtime, unit, calls = fixture()
			local ok, reason = runtime.apply(
				unit, policy.TRANSFORM, perspective, "perspective-contract")
			H.truthy(ok, perspective)
			H.equal(reason, "applied")
			H.equal(calls.transforms, 1)
			H.equal(calls.transform_specs[1].node, 2)
			H.equal(calls.transform_perspectives[1], perspective)
			H.equal(calls.transform_surfaces[1], "perspective-contract")
			H.deep_equal(calls.transform_specs[1].scale, { 90, 90, 90 })
			H.deep_equal(calls.transform_specs[1].offset, { 0, 0, -0.3 })
		end
	end)

	H.test("WOC #613 pulse forwards surface and perspective to durable owner", function()
		local state = {
			position = { 0, 0, 0 }, scale = { 1, 1, 1 },
			rotation = { 0, 0, 0, 1 },
		}
		local owner_unit = {}
		local owner = durable.new({
			alive = function(value) return value == owner_unit end,
			read = function()
				return {
					position = copy(state.position), scale = copy(state.scale),
					rotation = copy(state.rotation),
				}
			end,
			rotation_components = function() return { 0.5, -0.5, -0.5, 0.5 } end,
			apply = function(_, spec)
				state.position = copy(spec.position)
				state.scale = copy(spec.scale)
				state.rotation = { 0.5, -0.5, -0.5, 0.5 }
				return true
			end,
			should_track = function(surface) return surface == "owner-spawn" end,
		})
		local runtime = pulse.new(policy, owner, {
			unit = {
				alive = function(value) return value == owner_unit end,
				has_node = function(value, name)
					return value == owner_unit and name == policy.TRANSFORM_NODE_NAME
				end,
				node = function() return 2 end,
				set_all_materials = function() end,
				set_texture_for_materials = function() end,
			},
			application = { can_get = function() return true end },
			script_unit = { set_material_variable = function() end },
		})
		local ok, reason = runtime.apply(
			owner_unit, policy.TRANSFORM, "1p", "owner-spawn")
		H.equal(ok, true)
		H.equal(reason, "applied")
		H.equal(owner:count(), 1)
		H.deep_equal(state.position, { 0, 0, -0.3 })
		H.deep_equal(state.scale, { 90, 90, 90 })
	end)

	H.test("WOC #712 fails closed when the authored render node is unavailable", function()
		local runtime, unit, calls = fixture()
		-- Replace the fixture with an API that positively lacks the named node.
		runtime = pulse.new(policy, {
			apply = function() calls.transforms = calls.transforms + 1; return true end,
		}, {
			unit = {
				alive = function(value) return value == unit end,
				has_node = function() return false end,
				node = function() return 2 end,
				set_all_materials = function() end,
				set_texture_for_materials = function() end,
			},
			application = { can_get = function() return true end },
			script_unit = { set_material_variable = function() end },
		})
		local ok, reason = runtime.apply(unit, policy.TRANSFORM, "3p", "test")
		H.equal(ok, false)
		H.equal(reason, "transform-node-missing")
		H.equal(calls.transforms, 0)
	end)

	H.test("WOC #712 resolves named render node across gameplay and preview surfaces", function()
		for _, row in ipairs({
			{ "1p", "owner-spawn" },
			{ "3p", "owner-spawn" },
			{ "3p", "husk-spawn" },
			{ "3p", "character-preview" },
			{ "1p", "item-preview" },
		}) do
			local runtime, unit, calls = fixture()
			H.truthy(runtime.apply(unit, policy.TRANSFORM, row[1], row[2]))
			H.equal(calls.transforms, 1)
			H.equal(calls.transform_specs[1].node, 2)
			H.equal(calls.transform_perspectives[1], row[1])
			H.equal(calls.transform_surfaces[1], row[2])
		end
	end)

	H.test("WOC #712 replays transform for replacement units after mission transition", function()
		local before, first_unit, first_calls = fixture()
		H.truthy(before.apply(first_unit, policy.TRANSFORM, "3p", "owner-spawn"))
		local after, replacement_unit, replacement_calls = fixture()
		H.truthy(after.apply(replacement_unit, policy.TRANSFORM, "3p", "owner-spawn"))
		H.equal(first_calls.transforms, 1)
		H.equal(replacement_calls.transforms, 1)
		H.equal(replacement_calls.transform_specs[1].node, 2)
	end)

	H.test("WOC #613 fails closed before C material writes", function()
		local missing = policy.PULSE_TEXTURES_1P[2].texture
		local runtime, unit, calls = fixture(missing)
		local ok, reason = runtime.apply(unit, policy.TRANSFORM, "1p", "test")
		H.equal(ok, false)
		H.equal(reason, "texture-not-resident")
		H.equal(#calls.materials, 0)
		H.equal(#calls.textures, 0)
		H.equal(#calls.variables, 0)
		H.equal(calls.transforms, 0)
		H.equal(calls.diagnostics, 1)
	end)

	H.test("WOC #613 pulse runtime has no update or RPC path", function()
		local file = assert(io.open(repo_root
			.. "/weapons_of_chaos/scripts/mods/weapons_of_chaos/_woc_blightreaper_pulse.lua", "rb"))
		local source = file:read("*a"); file:close()
		H.equal(source:find("mod.update", 1, true), nil)
		H.equal(source:find("network_send", 1, true), nil)
		H.equal(source:find("Material.set_texture", 1, true), nil)
		H.truthy(source:find("set_texture_for_materials", 1, true))
	end)
end
