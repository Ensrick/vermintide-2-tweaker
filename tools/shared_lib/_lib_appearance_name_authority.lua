-- Appearance NAME AUTHORITY (#660 follow-up to the #1157 census re-key).
--
-- WHY THIS FILE EXISTS
--   Two vocabularies described one domain. The census
--   (_lib_appearance_descriptor.lua M.CELLS / M.EDGES) calls the remote
--   surface "husk"; the G-APPEARANCE contracts registry
--   (qa/appearance_contracts.psd1) called the same surface "remote_husk_3p"
--   and never read the census. Two spellings for one thing means a gap can
--   hide between them: neither gate can see that the other is missing a
--   surface, because neither can tell that two rows are the same row.
--
--   The descriptor remains the SOLE authority for canonical names. This file
--   adds the binding every non-census consumer needs: which legacy spellings
--   existed and what each resolves to, which contracts-only names are
--   deliberately FINER-GRAINED than the census rather than unknown, and which
--   are genuine census gaps.
--
-- SCOPE - TOOLING ONLY, AND WHY IT IS NOT IN THE DESCRIPTOR
--   This file is deliberately NOT listed in tools/shared_lib/manifest.psd1 and
--   is never synced into a mod bundle. It records legacy QA spellings, which
--   have no business shipping to players. Do not add it to the manifest.
--
--   PROVENANCE (2026-08-08): the alias tables and the resolve_* API below were
--   first written directly into _lib_appearance_descriptor.lua under #1158.
--   They were relocated here, verbatim in behaviour, because that descriptor is
--   byte-synced into a mod bundle: manifest.psd1 registers the consumer copy
--   character_weapon_variants/scripts/mods/character_weapon_variants/
--   _lib_appearance_descriptor.lua, loaded at character_weapon_variants.lua:86.
--   Editing the descriptor therefore fails qa/check_shared_lib_drift.ps1 until
--   the CWV copy is re-synced, which would rewrite a shipped mod file (and its
--   bundle bytes) for a QA-only naming change. Keeping the legacy vocabulary
--   here leaves the descriptor - and every mod - untouched.
--
-- ADDING A NAME
--   New appearance surface and edge names enter through
--   _lib_appearance_descriptor.lua M.CELLS / M.EDGES ONLY. This file may BIND a
--   legacy spelling to one of those names; it may never invent one. Every alias
--   target and refinement parent is checked against the descriptor by
--   M.validate, so an invented name fails the gate immediately.
--
-- CONSUMERS
--   tools/shared_lib/emit-appearance-names.lua (drives this under the pinned
--   vendored Lua 5.1 host for qa/check_appearance_contracts.ps1) and
--   qa/lua/tests/test_appearance_name_authority.lua.
local M = {}

-- Legacy contracts spelling -> canonical census surface. These are BANNED
-- spellings, not permitted synonyms: qa/appearance_contracts.psd1 was renamed
-- to the canonical names on 2026-08-08. The mapping is retained so a legacy
-- spelling that reappears fails with the exact rename to apply instead of a
-- generic "unknown name".
M.SURFACE_ALIASES = {
	bot_3p = "bot",
	remote_husk_3p = "husk",
	cosmetic_preview = "illusion_browser",
	athanor_preview = "cim_preview",
	lobby_preview = "lobby",
	score_screen = "score_team",
}

M.EDGE_ALIASES = {
	customization_change = "customize",
}

-- Contracts names FINER than the census vocabulary. These are in appearance
-- scope and must not be deleted: the census declares per-family surface x edge
-- SUPPORT, while the contracts declare per-mod behavioural CONCERNS and replay
-- coverage, and the contracts axis is deliberately more granular. Each entry
-- names the canonical census edge that CONTAINS it, so a reader can still line
-- the two gates up.
M.SURFACE_REFINEMENTS = {}

M.EDGE_REFINEMENTS = {
	initial_spawn = {
		of = "equip",
		reason = "the census counts first equipment construction inside equip; the contracts split it out because a family can pass an equip-time reapply and still miss the very first spawn",
	},
	wield = {
		of = "equip",
		reason = "the census counts wield inside equip; the contracts split it out because husk wield is a separate reconstruction seam from equipment creation",
	},
	style_change = {
		of = "customize",
		reason = "the census counts Combat Style transitions inside customize; the contracts split it out because style state carries its own transport",
	},
	career_change = {
		of = "equip",
		reason = "the census counts career replacement inside equip because a career swap reconstructs equipment; the contracts track it separately so career-only regressions are visible",
	},
	hot_join = {
		of = "peer_ready",
		reason = "the census counts joining-peer replay inside peer_ready; the contracts separate the joiner arriving from the acknowledged ready handshake",
	},
	parity_ready = {
		of = "peer_ready",
		reason = "the census counts content-parity gating inside peer_ready; the contracts split it because a peer can be ready while lacking the providing mod",
	},
	rejoin = {
		of = "peer_ready",
		reason = "the census counts leave-and-rejoin inside peer_ready; the contracts split it because rejoin must also clear stale per-peer generation state",
	},
	preview_reopen = {
		of = "preview_open",
		reason = "the census counts a reopened preview inside preview_open; the contracts split it because a replacement previewer must never inherit the prior proof",
	},
	lobby_score_create = {
		of = "preview_open",
		reason = "the census counts lobby and score preview construction inside preview_open; the contracts split it because those previewers are built by a different owner",
	},
}

-- Names with NO canonical equivalent because the census cannot express them.
-- Each entry is debt against M.CELLS / M.EDGES, not a licence to keep inventing
-- names: closing one means adding the surface to the descriptor, which forces a
-- newly declared row in EVERY mod census. #1198 closed the first recorded gap:
-- crafting_preview is now a canonical surface distinct from cim_preview.
M.SURFACE_CENSUS_GAPS = {}

M.EDGE_CENSUS_GAPS = {}

-- The concern axis is contracts-only BY CONSTRUCTION. The census declares
-- whether a family supports a (surface, edge) pair at all; the contracts
-- declare which behavioural concern a change owns. The census has no concern
-- axis, so these names have no canonical equivalent and never will.
M.CONCERN_SCOPE_REASON =
	"contracts-only axis: the census declares per-family surface x edge support, the contracts declare per-mod behavioural concerns; the census has no concern axis"

M.CONCERNS = {
	"unit_identity", "transform", "material", "glow", "pose",
	"effective_template", "fade", "icon", "name",
}

local function sorted_keys(t)
	local keys = {}
	for k in pairs(t) do keys[#keys + 1] = k end
	table.sort(keys)
	return keys
end

local function nonempty_string(v)
	return type(v) == "string" and #v > 0
end

-- Checks this table against the descriptor. Returns (true, {}) or
-- (false, errors). Every alias target and refinement parent must be a CANONICAL
-- descriptor name, and no legacy name may collide with a canonical one: a
-- spelling that is both canonical and "legacy" is a contradiction that would
-- let the gate accept and reject the same string.
function M.validate(D)
	local errors = {}
	if type(D) ~= "table" or type(D.SURFACE_SET) ~= "table" or type(D.EDGE_SET) ~= "table" then
		return false, { "descriptor must expose SURFACE_SET and EDGE_SET" }
	end

	local axes = {
		{
			label = "surface", canon = D.SURFACE_SET,
			aliases = M.SURFACE_ALIASES, refinements = M.SURFACE_REFINEMENTS,
			gaps = M.SURFACE_CENSUS_GAPS,
		},
		{
			label = "edge", canon = D.EDGE_SET,
			aliases = M.EDGE_ALIASES, refinements = M.EDGE_REFINEMENTS,
			gaps = M.EDGE_CENSUS_GAPS,
		},
	}

	for _, axis in ipairs(axes) do
		local claimed = {}
		local function claim(name, kind)
			if claimed[name] then
				errors[#errors + 1] = axis.label .. " '" .. tostring(name) .. "' is declared twice ("
					.. claimed[name] .. " and " .. kind .. ")"
			end
			claimed[name] = kind
			if axis.canon[name] then
				errors[#errors + 1] = axis.label .. " '" .. tostring(name) .. "' is canonical and must not also be declared "
					.. kind .. " - remove it here or from the descriptor"
			end
		end

		for _, name in ipairs(sorted_keys(axis.aliases)) do
			claim(name, "alias")
			local target = axis.aliases[name]
			if not nonempty_string(target) or not axis.canon[target] then
				errors[#errors + 1] = axis.label .. " alias '" .. tostring(name) .. "' targets '"
					.. tostring(target) .. "', which is not a canonical descriptor name"
			end
		end

		for _, name in ipairs(sorted_keys(axis.refinements)) do
			claim(name, "refinement")
			local entry = axis.refinements[name]
			if type(entry) ~= "table" then
				errors[#errors + 1] = axis.label .. " refinement '" .. tostring(name) .. "' must be a table"
			else
				if not nonempty_string(entry.of) or not axis.canon[entry.of] then
					errors[#errors + 1] = axis.label .. " refinement '" .. tostring(name) .. "' refines '"
						.. tostring(entry.of) .. "', which is not a canonical descriptor name"
				end
				if not nonempty_string(entry.reason) then
					errors[#errors + 1] = axis.label .. " refinement '" .. tostring(name) .. "' needs a reason"
				end
			end
		end

		for _, name in ipairs(sorted_keys(axis.gaps)) do
			claim(name, "census-gap")
			local entry = axis.gaps[name]
			if type(entry) ~= "table" or not nonempty_string(entry.reason) then
				errors[#errors + 1] = axis.label .. " census gap '" .. tostring(name) .. "' needs a reason"
			end
		end
	end

	local seen_concern = {}
	for _, name in ipairs(M.CONCERNS) do
		if not nonempty_string(name) then
			errors[#errors + 1] = "concern names must be non-empty strings"
		elseif seen_concern[name] then
			errors[#errors + 1] = "concern '" .. name .. "' is declared twice"
		else
			seen_concern[name] = true
			if D.SURFACE_SET[name] or D.EDGE_SET[name] then
				errors[#errors + 1] = "concern '" .. name
					.. "' collides with a canonical surface or edge name"
			end
		end
	end
	if not nonempty_string(M.CONCERN_SCOPE_REASON) then
		errors[#errors + 1] = "CONCERN_SCOPE_REASON must explain why the concern axis has no census counterpart"
	end

	return #errors == 0, errors
end

-- Resolve a contract-vocabulary name onto the canonical axis. Returns
-- (canonical, kind), or (nil, nil) when the name is neither canonical nor a
-- registered legacy spelling, refinement, or census gap. A census gap resolves
-- to nil canonical BY DESIGN - it has no canonical name yet, which is the whole
-- point of recording it - so callers must branch on kind, never on canonical
-- alone. Relocated from _lib_appearance_descriptor.lua (#1158); see PROVENANCE.
local function resolve(name, canon_set, aliases, refinements, gaps)
	if canon_set[name] then return name, "canonical" end
	if aliases[name] then return aliases[name], "alias" end
	local refinement = refinements[name]
	if refinement then return refinement.of, "refinement" end
	if gaps[name] then return nil, "census-gap" end
	return nil, nil
end

function M.resolve_surface(name, D)
	return resolve(name, D.SURFACE_SET, M.SURFACE_ALIASES, M.SURFACE_REFINEMENTS, M.SURFACE_CENSUS_GAPS)
end

function M.resolve_edge(name, D)
	return resolve(name, D.EDGE_SET, M.EDGE_ALIASES, M.EDGE_REFINEMENTS, M.EDGE_CENSUS_GAPS)
end

-- Deterministic full name table for tooling consumers, in a fixed order so a
-- PowerShell caller can diff runs. Each row: axis, name, kind, canonical,
-- reason. kind is one of canonical | alias | refinement | census-gap |
-- contract-only.
function M.rows(D)
	local out = {}
	local function add(axis, name, kind, canonical, reason)
		out[#out + 1] = {
			axis = axis, name = name, kind = kind,
			canonical = canonical or "", reason = reason or "",
		}
	end

	for _, name in ipairs(D.CELLS) do add("surface", name, "canonical", name, "") end
	for _, name in ipairs(sorted_keys(M.SURFACE_ALIASES)) do
		add("surface", name, "alias", M.SURFACE_ALIASES[name], "")
	end
	for _, name in ipairs(sorted_keys(M.SURFACE_REFINEMENTS)) do
		local e = M.SURFACE_REFINEMENTS[name]
		add("surface", name, "refinement", e.of, e.reason)
	end
	for _, name in ipairs(sorted_keys(M.SURFACE_CENSUS_GAPS)) do
		add("surface", name, "census-gap", "", M.SURFACE_CENSUS_GAPS[name].reason)
	end

	for _, name in ipairs(D.EDGES) do add("edge", name, "canonical", name, "") end
	for _, name in ipairs(sorted_keys(M.EDGE_ALIASES)) do
		add("edge", name, "alias", M.EDGE_ALIASES[name], "")
	end
	for _, name in ipairs(sorted_keys(M.EDGE_REFINEMENTS)) do
		local e = M.EDGE_REFINEMENTS[name]
		add("edge", name, "refinement", e.of, e.reason)
	end
	for _, name in ipairs(sorted_keys(M.EDGE_CENSUS_GAPS)) do
		add("edge", name, "census-gap", "", M.EDGE_CENSUS_GAPS[name].reason)
	end

	for _, name in ipairs(M.CONCERNS) do
		add("concern", name, "contract-only", "", M.CONCERN_SCOPE_REASON)
	end

	return out
end

return M
