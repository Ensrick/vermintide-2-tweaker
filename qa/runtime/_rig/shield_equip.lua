-- WP-H-14 rig acceptance: a loadout change made by a case is held back by the backend write shield, and the
-- official rows end equal to the snapshot.
--
-- Equips through the game's own setter BackendUtils.set_loadout_item
-- (Vermintide-2-Source-Code/scripts/managers/backend/backend_utils.lua:22), which writes mirror._career_data
-- (scripts/managers/backend_playfab/playfab_mirror_base.lua:1928-1941). The case never commits: it waits up to 30 s
-- for the game's own next commit, whose _check_career_data call (playfab_mirror_base.lua:2885) the shield answers
-- with "not dirty". It puts the item back through the same setter, then OM.restore, before any assertion.
-- Host side, run.ps1's default host_forbid_log fails the run on any updateHeroAttributes request in the log.
return {
	issue = 0,
	arena = "keep",
	class = "R",
	timeout = 120,
	run = function(T)
		local OM = T.shared("official_mirror")

		T.require(T.shield().installed, "backend write shield installed")
		T.require(OM.baseline_clean(), "official mirror clean at case start")
		T.require(T.local_hero(30) ~= nil, "local hero alive")

		local player = T.local_player()
		local career = player and player:career_name()

		T.require(type(career) == "string", "local career known")

		local slot = "slot_melee"
		local current = BackendUtils.get_loadout_item_id(career, slot)

		T.require(current ~= nil, "a melee item is equipped")

		-- a second owned vanilla melee item this career can wield (fields at playfab_mirror_base.lua:1700-1716, 1776-1786)
		local pick
		local items = Managers.backend:get_interface("items")

		for backend_id, item in pairs(items:get_all_backend_items()) do
			local data = item.data

			if not pick and backend_id ~= current and type(data) == "table" and data.slot_type == "melee"
				and item.rarity ~= "magic" and data.rarity ~= "magic" and type(data.can_wield) == "table" and not OM.minted(backend_id) then
				for _, name in ipairs(data.can_wield) do
					if name == career then
						pick = backend_id
					end
				end
			end
		end

		T.require(pick ~= nil, "a second owned vanilla melee item for " .. career)
		T.note("career", career)
		T.note("equip", tostring(current) .. " -> " .. tostring(pick))

		local snap = OM.snapshot()
		local before = T.shield()

		T.step("equip a different vanilla item through BackendUtils.set_loadout_item")
		BackendUtils.set_loadout_item(pick, career, slot)

		local equipped = BackendUtils.get_loadout_item_id(career, slot)

		T.step("wait for the game's next commit, at most 30 s")

		local waited = 0

		while T.shield().career_checks == before.career_checks and waited < 30 do
			T.wait(0.5)

			waited = waited + 0.5
		end

		local after = T.shield()

		T.note("seconds_to_commit", waited)
		T.note("career_checks", after.career_checks - before.career_checks)

		T.step("put the item back, then restore the snapshot")
		BackendUtils.set_loadout_item(current, career, slot)
		OM.restore(snap)

		T.expect_eq(equipped, pick, "the official row held the new item while equipped")
		OM.assert_untouched(T, snap)
		OM.assert_clean(T, "after restore")
		T.expect_eq(after.saw_update_hero_attributes, 0, "no updateHeroAttributes request since the shield went up")
		-- No commit in 30 s leaves nothing to judge the shield by: INCONCLUSIVE. Any ASSERT FAIL above still shows
		-- in the evidence and in the CASE END failed count.
		T.require(after.career_checks > before.career_checks, "the game made a commit within 30 s")
		T.expect(after.blocked_characters_data > before.blocked_characters_data, "SHIELD blocked=characters_data for that commit")
	end,
}
