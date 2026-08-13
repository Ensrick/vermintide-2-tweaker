return function(H, repo_root)
	local D = dofile(repo_root .. "/tools/shared_lib/_lib_appearance_descriptor.lua")

	-- A fresh copy per case: M.validate reads module-level tables, so a planted
	-- mutation must not leak into the next assertion.
	local function fresh()
		return dofile(repo_root .. "/tools/shared_lib/_lib_appearance_name_authority.lua")
	end

	-- The legacy G-APPEARANCE spellings, as qa/appearance_contracts.psd1 carried
	-- them before the 2026-08-08 rename (#1158). Every one must stay RECORDED:
	-- if a rename is reverted, the gate has to answer "rename it to X" rather
	-- than "unknown name", and that instruction lives only here.
	local LEGACY_SURFACES = {
		bot_3p = "bot",
		remote_husk_3p = "husk",
		cosmetic_preview = "illusion_browser",
		athanor_preview = "cim_preview",
		lobby_preview = "lobby",
		score_screen = "score_team",
	}
	local LEGACY_EDGES = { customization_change = "customize" }

	H.test("appearance name authority agrees with the canonical descriptor", function()
		local A = fresh()
		local ok, errors = A.validate(D)
		H.truthy(ok, table.concat(errors, "\n"))
	end)

	H.test("every legacy contract spelling still binds to its canonical name", function()
		local A = fresh()
		for legacy, canonical in pairs(LEGACY_SURFACES) do
			H.equal(A.SURFACE_ALIASES[legacy], canonical,
				"surface alias lost or re-pointed: " .. legacy)
			local resolved, kind = A.resolve_surface(legacy, D)
			H.equal(resolved, canonical, legacy .. " must resolve to " .. canonical)
			H.equal(kind, "alias", legacy .. " must resolve as a legacy alias")
		end
		for legacy, canonical in pairs(LEGACY_EDGES) do
			H.equal(A.EDGE_ALIASES[legacy], canonical,
				"edge alias lost or re-pointed: " .. legacy)
			local resolved, kind = A.resolve_edge(legacy, D)
			H.equal(resolved, canonical, legacy .. " must resolve to " .. canonical)
			H.equal(kind, "alias", legacy .. " must resolve as a legacy alias")
		end
	end)

	H.test("canonical names resolve to themselves on both axes", function()
		local A = fresh()
		for _, surface in ipairs(D.CELLS) do
			local resolved, kind = A.resolve_surface(surface, D)
			H.equal(resolved, surface)
			H.equal(kind, "canonical")
		end
		for _, edge in ipairs(D.EDGES) do
			local resolved, kind = A.resolve_edge(edge, D)
			H.equal(resolved, edge)
			H.equal(kind, "canonical")
		end
	end)

	-- #1198 made the ordinary crafting bench first-class without collapsing it
	-- onto CIM's distinct Athanor preview surface.
	H.test("crafting_preview is canonical and remains distinct from cim_preview", function()
		local A = fresh()
		H.equal(A.SURFACE_ALIASES.crafting_preview, nil,
			"the vanilla crafting bench must not be aliased onto the CIM Athanor forge")
		H.equal(A.SURFACE_CENSUS_GAPS.crafting_preview, nil,
			"a canonical surface must not remain recorded as a census gap")
		local resolved, kind = A.resolve_surface("crafting_preview", D)
		H.equal(kind, "canonical")
		H.equal(resolved, "crafting_preview")
		H.truthy(D.SURFACE_SET.cim_preview and D.SURFACE_SET.crafting_preview,
			"the vanilla bench and CIM Athanor must remain separate canonical surfaces")
	end)

	H.test("finer contract edges refine a canonical edge and explain themselves", function()
		local A = fresh()
		H.equal(A.EDGE_REFINEMENTS.initial_spawn.of, "equip",
			"first unit construction refines equip, not persisted instance_load")
		for name, entry in pairs(A.EDGE_REFINEMENTS) do
			H.truthy(D.EDGE_SET[entry.of], name .. " refines a non-canonical edge")
			H.truthy(type(entry.reason) == "string" and #entry.reason > 0,
				name .. " needs a reason explaining the finer grain")
		end
	end)

	H.test("authority self-check rejects planted contradictions", function()
		local function rejects(mutate)
			local A = fresh()
			mutate(A)
			local ok, errors = A.validate(D)
			H.truthy(not ok, "planted contradiction was accepted")
			H.truthy(#errors > 0)
		end

		rejects(function(A) A.SURFACE_ALIASES.planted = "not_a_real_surface" end)
		rejects(function(A) A.SURFACE_ALIASES.husk = "bot" end)
		rejects(function(A) A.EDGE_REFINEMENTS.planted = { of = "not_a_real_edge", reason = "x" } end)
		rejects(function(A) A.EDGE_REFINEMENTS.planted = { of = "equip" } end)
		rejects(function(A) A.SURFACE_CENSUS_GAPS.planted = {} end)
		rejects(function(A) A.CONCERNS[#A.CONCERNS + 1] = "husk" end)
		rejects(function(A) A.SURFACE_CENSUS_GAPS.bot_3p = { reason = "also an alias" } end)

		-- The baseline must still pass, or the cases above prove nothing.
		local ok = fresh().validate(D)
		H.truthy(ok)
	end)

	H.test("emitted rows cover every canonical, legacy, and contract-only name", function()
		local A = fresh()
		local rows = A.rows(D)
		local by_axis = { surface = {}, edge = {}, concern = {} }
		for _, row in ipairs(rows) do
			H.truthy(by_axis[row.axis], "unknown axis in emitted rows: " .. tostring(row.axis))
			H.truthy(by_axis[row.axis][row.name] == nil,
				"duplicate emitted row: " .. row.axis .. "/" .. row.name)
			by_axis[row.axis][row.name] = row.kind
		end
		for _, surface in ipairs(D.CELLS) do
			H.equal(by_axis.surface[surface], "canonical", surface .. " missing from emitted rows")
		end
		for _, edge in ipairs(D.EDGES) do
			H.equal(by_axis.edge[edge], "canonical", edge .. " missing from emitted rows")
		end
		for legacy in pairs(LEGACY_SURFACES) do
			H.equal(by_axis.surface[legacy], "alias")
		end
		for legacy in pairs(LEGACY_EDGES) do
			H.equal(by_axis.edge[legacy], "alias")
		end
		for _, concern in ipairs(A.CONCERNS) do
			H.equal(by_axis.concern[concern], "contract-only")
		end
		H.equal(by_axis.surface.crafting_preview, "canonical")
	end)
end
