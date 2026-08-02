-- _cwv_illusion_provenance.lua -- vanilla-ownership provenance for illusion-source scans (#915)
--
-- CWV-generated ItemMasterList weapon-skin rows keep a VANILLA
-- matching_item_key for template resolution (DEVELOPMENT.md, the
-- _apply_skin_to_item crash rule) and carry `cwv_owner_item_type` as their
-- canonical cosmetic owner (#704). matching_item_key is therefore template
-- metadata, NOT source provenance: a registrar that harvests illusion sources
-- by scanning ItemMasterList on matching_item_key alone re-admits CWV's own
-- generated skins. Issue #915: the Maul picker gained a 1H sword because
-- cwv_es_sword_and_mace_skin borrows "es_dual_wield_hammer_sword" with an
-- inverse sword-right hand layout. Every family scan must call
-- `vanilla_owned` instead of open-coding the row shape, and pools that could
-- have been polluted by a pre-filter mod generation (VMF reload retains the
-- previous generation's ItemMasterList/WeaponSkins writes) are cleaned with
-- `scrub_stale_picker_entries`. Invariant pinned by
-- qa/lua/tests/test_cwv_illusion_family_provenance.lua and the
-- issue915_maul_illusion_vanilla_provenance runtime census.
--
-- Owned by: character_weapon_variants.lua entry point. Consumed via:
-- mod:dofile("scripts/mods/character_weapon_variants/_cwv_illusion_provenance")

local Provenance = {}

-- True only for a VANILLA-owned weapon-skin row: a table shaped like a skin
-- entry that does NOT carry the #704 CWV ownership field. Callers add their
-- own family condition (entry.matching_item_key == "<vanilla key>").
function Provenance.vanilla_owned(entry)
	return type(entry) == "table"
		and entry.item_type == "weapon_skin"
		and not entry.cwv_owner_item_type
end

-- Remove picker-tier entries whose SOURCE row is CWV-owned. `key_prefix` is
-- the registrar's generated-key prefix (e.g. "cwv_es_maul_"); the remainder
-- names the source skin. Registration is guarded per-key, so stale entries
-- admitted by a pre-filter generation would otherwise survive a VMF reload.
-- NetworkLookup rows are left untouched (numeric wire stability). Returns the
-- number of removed entries.
function Provenance.scrub_stale_picker_entries(combo_table_name, key_prefix)
	if not WeaponSkins or not ItemMasterList then return 0 end
	local combos = WeaponSkins.skin_combinations
		and WeaponSkins.skin_combinations[combo_table_name]
	if not combos then return 0 end

	local removed = 0
	for _, tier in pairs(combos) do
		if type(tier) == "table" then
			for i = #tier, 1, -1 do
				local tier_key = tier[i]
				local source_key = type(tier_key) == "string"
					and tier_key:sub(1, #key_prefix) == key_prefix
					and tier_key:sub(#key_prefix + 1)
				local source_row = source_key and source_key ~= ""
					and rawget(ItemMasterList, source_key)
				if type(source_row) == "table"
						and source_row.cwv_owner_item_type then
					table.remove(tier, i)
					removed = removed + 1
				end
			end
		end
	end
	return removed
end

return Provenance
