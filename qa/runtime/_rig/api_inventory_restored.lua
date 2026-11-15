-- API self-test, T.equip restore: runs after api_inventory.lua. Its cleanup put the old melee item back with the same
-- setter, so every official row equals the backend's acknowledged copy again (INV-B of
-- qa/runtime/_shared/official_mirror.lua) and no row holds a mod-minted id (INV-A).
return {
	issue = 0,
	arena = "keep",
	class = "R",
	timeout = 30,
	run = function(T)
		local OM = T.shared("official_mirror")

		T.require(T.local_hero(30) ~= nil, "local hero alive")
		OM.assert_clean(T, "after the T.equip restore")
	end,
}
