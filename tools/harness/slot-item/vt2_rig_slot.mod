-- VT2 test rig slot placeholder (WP-H-07). The published content of every "VT2 Rig Slot <n>" item: inert.
-- tools/harness/stage-build.ps1 replaces it with a local build before a rig run that names the slot.
-- Keeps one package line (the bootstrap's own package, shipped alongside) because a .mod with no package is
-- not safe as the first mod in the load order.
return {
	run = function ()
		return {}
	end,
	packages = {
		"resource_packages/vt2_rig_driver/vt2_rig_driver",
	},
}
