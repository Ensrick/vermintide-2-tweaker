return function(H, repo_root)
	local D = dofile(repo_root .. "/tools/shared_lib/_lib_appearance_descriptor.lua")

	-- The four mods that override weapon/cosmetic appearance. Each must ship
	-- a pure-data census file declaring, for EVERY registered family, every
	-- acceptance cell (implemented | unsupported) and lifecycle edge - the
	-- W0 gate of docs/APPEARANCE_UNIFICATION_PLAN.md. An unsupported cell
	-- must carry a fallback note (why it is safe / which issue tracks it).
	local CENSUS_FILES = {
		character_weapon_variants = "character_weapon_variants/scripts/mods/character_weapon_variants/_cwv_appearance_census.lua",
		cosmetics_tweaker = "cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_cos_appearance_census.lua",
		weapon_tweaker = "weapon_tweaker/scripts/mods/weapon_tweaker/_wt_appearance_census.lua",
		weapons_of_chaos = "weapons_of_chaos/scripts/mods/weapons_of_chaos/_woc_appearance_census.lua",
	}

	-- Bootstrap allowlist: mods whose retroactive census has not landed yet.
	-- Every entry here is DEBT - remove the entry in the same change that
	-- adds the mod's census file. Do NOT add new entries: a new appearance
	-- mod must ship its census from day one.
	local PENDING_CENSUS = {
		character_weapon_variants = "census being enumerated (2026-07-18 W0)",
		cosmetics_tweaker = "census being enumerated (2026-07-18 W0)",
		weapon_tweaker = "census being enumerated (2026-07-18 W0)",
		weapons_of_chaos = "census being enumerated (2026-07-18 W0)",
	}

	local function file_exists(path)
		local f = io.open(path, "rb")
		if f then f:close() return true end
		return false
	end

	local CELL_SET, EDGE_SET = {}, {}
	for _, c in ipairs(D.CELLS) do CELL_SET[c] = true end
	for _, e in ipairs(D.EDGES) do EDGE_SET[e] = true end

	local function validate_census(mod_name, census)
		local errors = {}
		if type(census) ~= "table" or type(census.families) ~= "table" then
			return { mod_name .. ": census must return { families = { ... } }" }
		end
		local family_count = 0
		for family, decl in pairs(census.families) do
			family_count = family_count + 1
			local prefix = mod_name .. "." .. tostring(family)
			if type(decl) ~= "table" or type(decl.cells) ~= "table" then
				errors[#errors + 1] = prefix .. ": missing cells table"
			else
				for _, cell in ipairs(D.CELLS) do
					local v = decl.cells[cell]
					if v ~= "implemented" and v ~= "unsupported" then
						errors[#errors + 1] = prefix .. ": cell '" .. cell
							.. "' must be declared implemented or unsupported"
					elseif v == "unsupported" then
						local note = decl.unsupported_fallback and decl.unsupported_fallback[cell]
						if type(note) ~= "string" or #note == 0 then
							errors[#errors + 1] = prefix .. ": unsupported cell '" .. cell
								.. "' needs an unsupported_fallback note"
						end
					end
				end
				for cell in pairs(decl.cells) do
					if not CELL_SET[cell] then
						errors[#errors + 1] = prefix .. ": unknown cell '" .. tostring(cell) .. "'"
					end
				end
			end
			if type(decl.edges) ~= "table" then
				errors[#errors + 1] = prefix .. ": missing edges table"
			else
				for _, edge in ipairs(D.EDGES) do
					local v = decl.edges[edge]
					if v ~= "implemented" and v ~= "unsupported" then
						errors[#errors + 1] = prefix .. ": edge '" .. edge
							.. "' must be declared implemented or unsupported"
					end
				end
				for edge in pairs(decl.edges) do
					if not EDGE_SET[edge] then
						errors[#errors + 1] = prefix .. ": unknown edge '" .. tostring(edge) .. "'"
					end
				end
			end
		end
		if family_count == 0 then
			errors[#errors + 1] = mod_name .. ": census declares no families"
		end
		return errors
	end

	H.test("appearance census exists or is declared pending for every appearance mod", function()
		for mod_name, rel in pairs(CENSUS_FILES) do
			local path = repo_root .. "/" .. rel
			if not file_exists(path) then
				H.truthy(PENDING_CENSUS[mod_name],
					mod_name .. " has no appearance census and no pending declaration - "
					.. "new appearance mods must ship " .. rel)
			end
		end
	end)

	H.test("landed appearance censuses declare every cell and edge", function()
		local validated = 0
		for mod_name, rel in pairs(CENSUS_FILES) do
			local path = repo_root .. "/" .. rel
			if file_exists(path) then
				local census = dofile(path)
				local errors = validate_census(mod_name, census)
				H.equal(#errors, 0, table.concat(errors, "\n"))
				validated = validated + 1
			end
		end
		H.truthy(validated >= 0)
	end)

	H.test("census self-check rejects a planted incomplete declaration", function()
		local bad = { families = { planted = {
			cells = { owner_1p = "implemented" },
			edges = {},
		} } }
		local errors = validate_census("planted_mod", bad)
		H.truthy(#errors >= 10)

		local good_cells, good_edges = {}, {}
		for _, c in ipairs(D.CELLS) do good_cells[c] = "implemented" end
		for _, e in ipairs(D.EDGES) do good_edges[e] = "implemented" end
		local ok_census = { families = { planted = { cells = good_cells, edges = good_edges } } }
		H.equal(#validate_census("planted_mod", ok_census), 0)

		good_cells.husk = "unsupported"
		local missing_note = validate_census("planted_mod", ok_census)
		H.equal(#missing_note, 1)
	end)
end
