-- WP-WT-05 / #948: on the real Saltzpyre skeleton, every configured 3P target
-- event exists. Class R closes only "the target event exists on the receiver
-- body"; how it looks stays a visual (class V) question.
-- Hero switch: GameNetworkManager.request_profile (Vermintide-2-Source-Code/
-- scripts/managers/network/game_network_manager.lua:358, as Fatshark's own
-- automation calls it at scripts/game_state/state_ingame_testify.lua:97-101).
-- Existence test: Unit.has_animation_event, used by vanilla as a plain
-- existence check (scripts/flow/flow_callbacks.lua:2978); the weapon does not
-- need to be wielded.
local PROFILE, CAREER = "witch_hunter", "wh_captain"

return {
	card = "WP-WT-05",
	issue = 948,
	class = "R",
	arena = "keep",
	mods = { "wt" },
	timeout = 180,
	run = function(T)
		local wt = get_mod("wt")
		T.require(wt ~= nil and type(wt._wt) == "table"
			and type(wt._wt.three_p_template_remaps) == "table", "wt exposes its template remaps")

		T.step("switch the local hero to " .. CAREER)
		local player = Managers.player:local_player()
		if not (player and player:career_name() == CAREER) then
			Managers.state.network:request_profile(1, PROFILE, CAREER, true)
			T.wait_until(function()
				local p = Managers.player:local_player()
				return p and p:career_name() == CAREER and p.player_unit and Unit.alive(p.player_unit)
			end, 60, "hero switched to " .. CAREER)
		end
		local u = T.local_hero()
		T.require(u ~= nil, "hero unit is alive")
		local career = T.ext(u, "career_system"):career_name()
		T.require(career == CAREER, "career is " .. CAREER)

		T.step("career wield events exist")
		local wield_checks = 0
		for name, tpl in pairs(Weapons) do
			local map = type(tpl) == "table" and rawget(tpl, "wield_anim_career_3p")
			local event = type(map) == "table" and map[career]
			if type(event) == "string" then
				wield_checks = wield_checks + 1
				T.expect(Unit.has_animation_event(u, event), name .. "|wield")
			end
		end
		T.note("wield_checks", wield_checks)

		T.step("template remap targets exist")
		local remap_checks = 0
		for name, entry in pairs(wt._wt.three_p_template_remaps) do
			-- The remap the mod selects for this career: the entry whose prefix
			-- matches the career name, else _default; false means none.
			local chosen
			for prefix, tbl in pairs(entry) do
				if prefix ~= "_default" and career:sub(1, #prefix) == prefix then
					chosen = tbl
					break
				end
			end
			if chosen == nil then chosen = entry._default end
			if type(chosen) == "table" then
				for source, target in pairs(chosen) do
					remap_checks = remap_checks + 1
					T.expect(Unit.has_animation_event(u, target), name .. "|" .. source .. ">" .. target)
				end
			end
		end
		T.note("remap_checks", remap_checks)
	end,
}
