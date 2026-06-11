return {
	mod_description = {
		en = "Adds new weapon variants combining models from different characters into lore-friendly packages.",
	},
	mace_sword_tweak = {
		en = "Mace and Sword Name and Cosmetic Tweak",
	},
	mace_sword_tweak_description = {
		en = "When ON, renames Kruber's vanilla Mace and Sword to 'Cudgel and Short Sword' and shrinks its sword (off-hand) model to match the Shortsword variant. Affects only the vanilla weapon — the CWV Sword and Mace variant is a different weapon and is unaffected.",
	},
	cwv_interaction_ammunition_javelin = {
		en = "Tuskgor Javelin",  -- pickup popup text when looking at a stuck javelin
	},

	-- ============================================================
	-- cwv_es_crossbow variant (v0.1.347-dev)
	-- ============================================================
	enable_cwv_es_crossbow         = { en = "Kruber: Crossbow (Saltzpyre's, rifle anims)" },
	enable_cwv_es_crossbow_tooltip = { en = "When ON, registers a Kruber variant of Saltzpyre's crossbow that uses Kruber's rifle 3P animations. Default ON. Known polish items: 3P grip offsets, smoke FX on shot, missing bolt in 3P — see TODO.md." },
	cwv_es_crossbow_name           = { en = "Crossbow" },
	cwv_es_crossbow_description    = { en = "An imperial-issue crossbow taken up by Reikland state troopers — same Witch-Hunter-pattern weapon, shouldered like the standard handgun." },

	-- On-ice `cwv_es_musket` variant item_type display name. The variant def is
	-- commented out (kept as a backup idea — the live musket is
	-- `cwv_es_musket_old`), but its `item_type = "cwv_es_musket"` literal is
	-- still scanned by qa/check_name_integrity.ps1 check #2. This entry resolves
	-- that reference and documents the on-ice variant's display name. Live code
	-- that operates on the musket family by backend_id prefix
	-- (`:match("^cwv_es_musket")`) keeps this key referenced. v0.1.348-dev.
	cwv_es_musket                  = { en = "Musket" },

	-- ============================================================
	-- Universal Debug Logging toggle (PROJECT_STANDARDS.md § 3.6).
	-- v0.1.340: renamed from `cwv_debug_mode` (was nested in
	-- `cwv_diagnostics_group`) to the universal `enable_debug_logging` key.
	-- ============================================================
	enable_debug_logging         = { en = "Debug Logging" },
	enable_debug_logging_tooltip = { en = "Emit detailed diagnostic logs to %%APPDATA%%\\Fatshark\\Vermintide 2\\console_logs\\. Increases log volume; enable when investigating a bug, then disable." },
}
