return function(H, repo_root)
    local root = repo_root
        .. "/character_weapon_variants/scripts/mods/character_weapon_variants/"

    local function read(name)
        local file = assert(io.open(root .. name, "rb"))
        local source = file:read("*a")
        file:close()
        return source:gsub("\r\n", "\n")
    end

    local function payload(source, begin_marker, end_marker)
        local begin_at = assert(source:find(begin_marker .. "\n", 1, true))
        local start_at = begin_at + #begin_marker + 1
        local end_at = assert(source:find("\n" .. end_marker, start_at, true))
        local moved = source:sub(start_at, end_at - 1)
        -- The payload is indented once because it now lives inside an installer
        -- function. Remove only that structural indent before comparing it with
        -- the exact former entry-file bytes.
        return moved:gsub("^\t", ""):gsub("\n\t", "\n")
    end

    -- Standard-Lua-5.1 FNV-1a implementation used elsewhere in this repo.
    local function fnv1a32(source)
        local hash = 2166136261
        for index = 1, #source do
            local byte = string.byte(source, index)
            local xored, place = 0, 1
            local h, b = hash, byte
            for _ = 1, 32 do
                local h_bit, b_bit = h % 2, b % 2
                if h_bit ~= b_bit then xored = xored + place end
                place = place * 2
                h = (h - h_bit) / 2
                b = (b - b_bit) / 2
            end
            hash = (xored * 16777619) % 4294967296
        end
        return string.format("%08x", hash)
    end

    H.test("CWV base/custom skin payload matches its reviewed bytes", function()
        -- Baselined at extraction (49723 / 9221c064) as byte-identical to the
        -- former entry-file payload. Issue 399 is the FIRST deliberate behavioral
        -- change inside the markers: the generated skin now honours
        -- `def.no_ammo_unit` on both `ammo_unit` and `ammo_unit_3p`, so a def that
        -- ever gains a `left_hand_unit` cannot re-declare the donor's torpedo.
        -- Re-baselined here; the lock now pins the reviewed bytes, not the
        -- extraction identity. Any further change must be re-reviewed the same way.
        local source = read("_cwv_skin_registry.lua")
        local moved = payload(source,
            "-- CWV_SKIN_REGISTRY_PAYLOAD_BEGIN_v1",
            "-- CWV_SKIN_REGISTRY_PAYLOAD_END_v1")
        H.equal(#moved, 50389)
        H.equal(fnv1a32(moved), "dfd65734")
    end)

    H.test("CWV generated-family payload preserves the surveyed registrar bytes", function()
        local source = read("_cwv_illusion_families.lua")
        local moved = payload(source,
            "-- CWV_ILLUSION_FAMILIES_PAYLOAD_BEGIN_v1",
            "-- CWV_ILLUSION_FAMILIES_PAYLOAD_END_v1")
        -- The only intentional payload substitution is the explicit injected
        -- provenance alias in place of five `mod` table reaches.
        H.equal(#moved, 59828)
        H.equal(fnv1a32(moved), "1b563bc8")
    end)

    H.test("CWV skin extraction preserves lookup append and table-identity contracts", function()
        local registry = read("_cwv_skin_registry.lua")
        local families = read("_cwv_illusion_families.lua")
        local entry = read("character_weapon_variants.lua")

        H.truthy(registry:find("custom_skin_keys = _custom_skin_keys", 1, true))
        H.truthy(registry:find("custom_illusions = _custom_illusions", 1, true))
        H.truthy(families:find(
            "local _custom_skin_keys = assert(deps.custom_skin_keys", 1, true))
        H.truthy(entry:find(
            "custom_skin_keys = _custom_skin_keys", 1, true))

		for _, key in ipairs({ "es_careers", "wh_careers", "kruber_1h_dual_skin_keys" }) do
			H.truthy(registry:find(key .. " = _" .. key, 1, true))
			H.truthy(entry:find(key .. " = _skin_state." .. key, 1, true))
		end

        for _, source in ipairs({ registry, families }) do
            H.truthy(source:find("#NetworkLookup.weapon_skins + 1", 1, true)
                or source:find("local idx = #tbl + 1", 1, true)
                or source:find("local idx = #lookup + 1", 1, true))
            H.truthy(source:find("NetworkLookup.item_names", 1, true)
                or source:find('{ "weapon_skins", "item_names" }', 1, true))
            H.truthy(source:find("rawset", 1, true))
        end
    end)

	H.test("CWV generated-family installer binds exported registry identities", function()
		local families = read("_cwv_illusion_families.lua")
		local marker = "\n-- CWV_ILLUSION_FAMILIES_PAYLOAD_BEGIN_v1"
		local marker_at = assert(families:find(marker, 1, true))
		local preamble = families:sub(1, marker_at - 1)
		local probe = preamble .. [[
	return {
		custom_skin_keys = _custom_skin_keys,
		es_careers = _es_careers,
		wh_careers = _wh_careers,
		kruber_1h_dual_skin_keys = _kruber_1h_dual_skin_keys,
	}
end
]]
		local chunk = assert(loadstring(probe, "@_cwv_illusion_families_dependency_probe.lua"))
		local install = chunk()
		local sentinels = {
			custom_skin_keys = {},
			es_careers = {},
			wh_careers = {},
			kruber_1h_dual_skin_keys = {},
		}
		local bound = install({}, {
			om = {},
			custom_skin_keys = sentinels.custom_skin_keys,
			illusion_provenance = {},
			es_all_careers = {},
			wh_all_careers = {},
			es_careers = sentinels.es_careers,
			wh_careers = sentinels.wh_careers,
			kruber_1h_dual_skin_keys = sentinels.kruber_1h_dual_skin_keys,
		})

		for key, sentinel in pairs(sentinels) do
			H.equal(bound[key], sentinel)
		end
	end)

	H.test("CWV Kruber dual-sword registrar executes with exact exported state", function()
		local families = read("_cwv_illusion_families.lua")
		local start_at = assert(families:find(
			"\tlocal function _register_kruber_1h_sword_dual_illusions()", 1, true))
		local end_marker = "\n\t_register_kruber_1h_sword_dual_illusions()"
		local end_at = assert(families:find(end_marker, start_at, true))
		local registrar = families:sub(start_at, end_at + #end_marker - 1)

		-- PUC Lua 5.1 cannot parse Vermintide's supported `goto`. Execute the
		-- exact production registrar body after a fixture-only lowering of its
		-- two continue branches to a one-shot repeat/break block.
		registrar = registrar:gsub(
			"for _, source_key in ipairs%(source_keys%) do",
			"for _, source_key in ipairs(source_keys) do\n\t\t\trepeat")
		registrar = registrar:gsub("goto continue", "break")
		registrar = registrar:gsub("\t\t\t::continue::", "\t\t\tuntil true")

		local fixture_source = [[
return function(mod, deps)
	local ItemMasterList = deps.ItemMasterList
	local WeaponSkins = deps.WeaponSkins
	local NetworkLookup = deps.NetworkLookup
	local _illusion_provenance = deps.illusion_provenance
	local _custom_skin_keys = deps.custom_skin_keys
	local _es_careers = deps.es_careers
	local _kruber_1h_dual_skin_keys = deps.kruber_1h_dual_skin_keys
]] .. registrar .. [[
	return _custom_skin_keys, _kruber_1h_dual_skin_keys
end
]]
		local install = assert(loadstring(fixture_source,
			"@_cwv_kruber_dual_sword_registrar_fixture.lua"))()
		local source_key = "es_1h_sword_skin_fixture"
		local new_key = "cwv_es_dual_swords_" .. source_key
		local careers = { "es_mercenary", "es_huntsman" }
		local skin_keys, marker_keys = {}, {}
		local item_master_list = {
			[source_key] = { matching_item_key = "es_1h_sword" },
		}
		local weapon_skins = {
			skins = {
				[source_key] = {
					right_hand_unit = "units/weapons/player/fixture_sword",
					rarity = "exotic",
					display_name = "fixture_sword",
				},
			},
			skin_combinations = {
				cwv_es_dual_swords_skins = { exotic = {} },
			},
		}
		local lookup = { weapon_skins = {}, item_names = {} }
		local returned_skins, returned_markers = install({ info = function() end }, {
			ItemMasterList = item_master_list,
			WeaponSkins = weapon_skins,
			NetworkLookup = lookup,
			illusion_provenance = { vanilla_owned = function() return true end },
			custom_skin_keys = skin_keys,
			es_careers = careers,
			kruber_1h_dual_skin_keys = marker_keys,
		})

		H.equal(returned_skins, skin_keys)
		H.equal(returned_markers, marker_keys)
		H.equal(item_master_list[new_key].can_wield, careers)
		H.truthy(skin_keys[new_key])
		H.truthy(marker_keys[new_key])
		H.equal(lookup.weapon_skins[1], new_key)
		H.equal(lookup.weapon_skins[new_key], 1)
		H.equal(lookup.item_names[1], new_key)
		H.equal(lookup.item_names[new_key], 1)
		H.equal(weapon_skins.skin_combinations.cwv_es_dual_swords_skins.exotic[1], new_key)
	end)
end
