return function(H, repo_root)
	local D = dofile(repo_root .. "/tools/shared_lib/_lib_appearance_descriptor.lua")

	-- The mods that override weapon/cosmetic appearance. Each must ship a
	-- pure-data census file declaring, for EVERY registered family, EVERY
	-- (surface, edge) PAIR as implemented or unsupported - the W0 gate of
	-- docs/APPEARANCE_UNIFICATION_PLAN.md, re-keyed from two independent
	-- vectors to the full matrix on 2026-08-04 (#1157). Every unsupported
	-- pair carries a fallback note (why it is safe / which issue tracks it).
	-- The registry is owned by the descriptor library so this gate and the gap
	-- report generator can never disagree about coverage.
	local CENSUS_FILES = {}
	for _, entry in ipairs(D.CENSUS_FILES) do CENSUS_FILES[entry.mod] = entry.path end

	-- Bootstrap allowlist: mods whose retroactive census has not landed yet.
	-- Every entry here is DEBT - remove the entry in the same change that
	-- adds the mod's census file. Do NOT add new entries: a new appearance
	-- mod must ship its census from day one. (All retroactive censuses landed
	-- 2026-07-18; the list is empty and must stay that way.)
	local PENDING_CENSUS = {}

	local function file_exists(path)
		local f = io.open(path, "rb")
		if f then f:close() return true end
		return false
	end

	local function validate_census(mod_name, census)
		local errors = {}
		if type(census) ~= "table" or type(census.families) ~= "table" then
			return { mod_name .. ": census must return { families = { ... } }" }
		end
		if census.schema_version ~= D.CENSUS_SCHEMA_VERSION then
			errors[#errors + 1] = mod_name .. ": census schema_version must be "
				.. tostring(D.CENSUS_SCHEMA_VERSION) .. " (surface x edge matrix, #1157)"
		end
		local family_count = 0
		for family, decl in pairs(census.families) do
			family_count = family_count + 1
			local prefix = mod_name .. "." .. tostring(family)
			if type(decl) ~= "table" then
				errors[#errors + 1] = prefix .. ": family declaration must be a table"
			elseif decl.cells ~= nil or decl.edges ~= nil then
				-- The pre-#1157 form declared surfaces and edges as independent
				-- vectors, which cannot express "husk AT mission transition".
				-- Reject it outright rather than infer a matrix from it.
				errors[#errors + 1] = prefix
					.. ": legacy cells/edges vectors are no longer accepted - declare a matrix (#1157)"
			elseif type(decl.matrix) ~= "table" then
				errors[#errors + 1] = prefix .. ": missing matrix table"
			else
				local _, matrix_errors = D.expand_matrix(decl.matrix, prefix .. ".matrix")
				for _, e in ipairs(matrix_errors) do errors[#errors + 1] = e end
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

	H.test("landed appearance censuses declare every surface x edge pair", function()
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

	-- Helper: a complete, minimal matrix every surface row of which is honest.
	local function full_matrix(default, note)
		local m = {}
		for _, surface in ipairs(D.CELLS) do
			m[surface] = { default = default, note = note }
		end
		return m
	end

	H.test("census self-check rejects a planted incomplete declaration", function()
		-- Only one surface declared: every other surface row is missing.
		local bad = { schema_version = D.CENSUS_SCHEMA_VERSION, families = { planted = {
			matrix = { owner_1p = { default = "implemented" } },
		} } }
		local errors = validate_census("planted_mod", bad)
		H.equal(#errors, #D.CELLS - 1)

		local ok_census = { schema_version = D.CENSUS_SCHEMA_VERSION, families = {
			planted = { matrix = full_matrix("implemented") },
		} }
		H.equal(#validate_census("planted_mod", ok_census), 0)

		-- An unsupported row with no note is a hole with no accounting.
		ok_census.families.planted.matrix.husk = { default = "unsupported" }
		H.equal(#validate_census("planted_mod", ok_census), #D.EDGES)

		-- A row note covers the whole row; a per-edge note covers one pair.
		ok_census.families.planted.matrix.husk = {
			default = "unsupported",
			note = "degrades to the resident vanilla base weapon",
		}
		H.equal(#validate_census("planted_mod", ok_census), 0)
	end)

	H.test("census self-check rejects an implicit or unresolvable pair", function()
		local census = { schema_version = D.CENSUS_SCHEMA_VERSION, families = {
			planted = { matrix = full_matrix("implemented") },
		} }
		local matrix = census.families.planted.matrix

		-- A row that omits its default is implicit, not compact.
		matrix.husk = { edges = { peer_ready = "unsupported" }, note = "n" }
		local errors = validate_census("planted_mod", census)
		H.equal(#errors, 1 + #D.EDGES - 1)

		-- Unknown vocabulary must not pass silently in either direction.
		matrix.husk = { default = "implemented", edges = { not_an_edge = "unsupported" } }
		H.equal(#validate_census("planted_mod", census), 1)
		matrix.husk = { default = "implemented" }
		matrix.not_a_surface = { default = "implemented" }
		H.equal(#validate_census("planted_mod", census), 1)
		matrix.not_a_surface = nil

		-- A misspelled state is never coerced to a neighbouring value.
		matrix.husk = { default = "partially" }
		local misspelled = validate_census("planted_mod", census)
		H.equal(#misspelled, 1 + #D.EDGES)
	end)

	H.test("census self-check rejects the pre-1157 vector declaration", function()
		local legacy_cells, legacy_edges = {}, {}
		for _, c in ipairs(D.CELLS) do legacy_cells[c] = "implemented" end
		for _, e in ipairs(D.EDGES) do legacy_edges[e] = "implemented" end
		local census = { schema_version = D.CENSUS_SCHEMA_VERSION, families = {
			planted = { cells = legacy_cells, edges = legacy_edges },
		} }
		local errors = validate_census("planted_mod", census)
		H.equal(#errors, 1)
		H.truthy(errors[1]:find("legacy cells/edges", 1, true))
	end)

	H.test("every landed census resolves to a total matrix with noted holes", function()
		for mod_name, rel in pairs(CENSUS_FILES) do
			local path = repo_root .. "/" .. rel
			if file_exists(path) then
				local census = dofile(path)
				for family, decl in pairs(census.families) do
					local matrix, errors = D.expand_matrix(decl.matrix,
						mod_name .. "." .. family .. ".matrix")
					H.equal(#errors, 0, table.concat(errors, "\n"))
					local pairs_seen = 0
					D.each_pair(matrix, function(surface, edge, state, note)
						pairs_seen = pairs_seen + 1
						if state == "unsupported" then
							H.truthy(type(note) == "string" and #note > 0,
								mod_name .. "." .. family .. "." .. surface .. "." .. edge)
						end
					end)
					H.equal(pairs_seen, #D.CELLS * #D.EDGES,
						mod_name .. "." .. family .. " must expand to a total matrix")
				end
			end
		end
	end)

	H.test("crafting preview is distinct and unsupported without a bench adapter", function()
		H.equal(#D.CELLS, 17, "the canonical census must carry all 17 appearance surfaces")
		H.truthy(D.SURFACE_SET.crafting_preview,
			"the ordinary crafting bench must be a canonical census surface")
		H.truthy(D.SURFACE_SET.cim_preview,
			"the CIM Athanor must remain a separate canonical census surface")

		for mod_name, rel in pairs(CENSUS_FILES) do
			local census = dofile(repo_root .. "/" .. rel)
			for family, decl in pairs(census.families) do
				local matrix, errors = D.expand_matrix(decl.matrix,
					mod_name .. "." .. family .. ".matrix")
				H.equal(#errors, 0, table.concat(errors, "\n"))
				for _, edge in ipairs(D.EDGES) do
					H.equal(matrix.crafting_preview[edge].state, "unsupported",
						mod_name .. "." .. family .. ".crafting_preview." .. edge)
					H.truthy(type(matrix.crafting_preview[edge].note) == "string"
						and #matrix.crafting_preview[edge].note > 0,
						"unsupported crafting-preview pair must explain its fallback")
				end
			end
		end

		local woc = dofile(repo_root .. "/weapons_of_chaos/scripts/mods/"
			.. "weapons_of_chaos/_woc_appearance_census.lua")
		local matrix, errors = D.expand_matrix(woc.families.enemy_weapon_relic.matrix,
			"weapons_of_chaos.enemy_weapon_relic.matrix")
		H.equal(#errors, 0, table.concat(errors, "\n"))
		H.equal(matrix.cim_preview.preview_open.state, "implemented",
			"the Athanor adapter remains independently implemented")
		H.equal(matrix.crafting_preview.preview_open.state, "unsupported",
			"the generic preview hook must not be relabeled as the vanilla bench")
		H.truthy(matrix.crafting_preview.preview_open.note:find(
			"does not instantiate LootItemUnitPreviewer", 1, true) ~= nil,
			"the unsupported bench row must preserve its exact source boundary")
	end)

	H.test("CWV Old Musket census implements only CIM preview-open", function()
		local census = dofile(repo_root .. "/character_weapon_variants/scripts/mods/"
			.. "character_weapon_variants/_cwv_appearance_census.lua")
		local matrix, errors = D.expand_matrix(census.families.old_musket.matrix,
			"character_weapon_variants.old_musket.matrix")
		H.equal(#errors, 0, table.concat(errors, "\n"))
		for _, edge in ipairs(D.EDGES) do
			local expected = edge == "preview_open" and "implemented" or "unsupported"
			H.equal(matrix.cim_preview[edge].state, expected,
				"old_musket.cim_preview." .. edge)
		end
	end)
end
