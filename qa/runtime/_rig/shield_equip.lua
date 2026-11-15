-- WP-H-14 rig acceptance: a loadout change made by a case is held back by the backend write shield, and the
-- official rows end equal to the snapshot.
--
-- Equips through the game's own setter BackendUtils.set_loadout_item
-- (Vermintide-2-Source-Code/scripts/managers/backend/backend_utils.lua:22), which writes mirror._career_data
-- (scripts/managers/backend_playfab/playfab_mirror_base.lua:1928-1941). It then triggers the commit the hero view
-- makes when it closes, Managers.backend:commit() (scripts/ui/views/hero_view/hero_view.lua:523), because nothing
-- commits while the keep sits idle (lead run 20261115-085154-shield-equip-3d617f44: the routine start-up commit
-- came during SETTLE, before the case). That commit's _check_career_data call (playfab_mirror_base.lua:2885) is
-- answered "not dirty" by the shield. This is the shield's own test: other cases still never call a commit.
-- The case waits for the commit's completion callback (status, playfab_mirror_base.lua:1861-1865), at most 30 s,
-- puts the item back through the same setter, runs OM.restore, and commits once more: a no-op with a working
-- shield, and if the shield ever failed it would send the original row back. Assertions come after the cleanup.
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

		-- the hero view's exit commit (hero_view.lua:523), with a completion callback so the case can wait for it
		local function commit_and_wait(label)
			local status
			local waited = 0

			Managers.backend:commit(false, function (result)
				status = tostring(result)
			end)

			while status == nil and waited < 30 do
				T.wait(0.5)

				waited = waited + 0.5
			end

			T.note(label .. ":status", tostring(status))
			T.note(label .. ":seconds", waited)

			return status
		end

		local snap = OM.snapshot()
		local before = T.shield()

		T.step("equip a different vanilla item through BackendUtils.set_loadout_item")
		BackendUtils.set_loadout_item(pick, career, slot)

		local equipped = BackendUtils.get_loadout_item_id(career, slot)

		T.step("commit the way the hero view does on exit, wait for the result")

		local first = commit_and_wait("commit_equipped")
		local after = T.shield()

		T.note("career_checks", after.career_checks - before.career_checks)

		T.step("put the item back, restore the snapshot, commit again")
		BackendUtils.set_loadout_item(current, career, slot)
		OM.restore(snap)

		local second = commit_and_wait("commit_restored")
		local final = T.shield()

		T.expect_eq(equipped, pick, "the official row held the new item while equipped")
		OM.assert_untouched(T, snap)
		OM.assert_clean(T, "after restore")
		T.expect_eq(final.saw_update_hero_attributes, 0, "no updateHeroAttributes request since the shield went up")
		-- A commit that never reports back leaves nothing to judge the shield by: INCONCLUSIVE. Any ASSERT FAIL above
		-- still shows in the evidence and in the CASE END failed count.
		T.require(first ~= nil and second ~= nil, "both commits reported a result within 30 s")
		T.expect_eq(first, "success", "the commit with the changed row completed")
		T.expect(after.career_checks > before.career_checks, "that commit asked _check_career_data")
		T.expect(after.blocked_characters_data > before.blocked_characters_data, "SHIELD blocked=characters_data for that commit")
		T.expect_eq(final.blocked_characters_data, after.blocked_characters_data, "nothing left to hold back after the restore")
	end,
}
