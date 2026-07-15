return function(H, repo_root)
	local policy = dofile(repo_root
		.. "/weapons_of_chaos/scripts/mods/weapons_of_chaos/_woc_appearance_policy.lua")
	local pulse = dofile(repo_root
		.. "/weapons_of_chaos/scripts/mods/weapons_of_chaos/_woc_blightreaper_pulse.lua")

	local function fixture(missing)
		local calls = { materials = {}, textures = {}, variables = {}, transforms = 0 }
		local unit = {}
		local api = {
			unit = {
				alive = function(value) return value == unit end,
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
			apply = function(value, spec)
				calls.transforms = calls.transforms + 1
				return value == unit and spec == policy.TRANSFORM
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
