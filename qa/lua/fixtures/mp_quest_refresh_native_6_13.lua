-- Complete native 6.13 getQuests producer and its exact timer readers.
-- Commit 93dea911a4cc464a0eb51cfdc3a443297bfc4550
-- scripts/managers/backend_playfab/backend_interface_quests_playfab.lua
-- Source Git blob: be44da375de5c2ff9e0459a88f263c207a89b139
-- Whole Git-LF SHA256: a7698ef8145b422a53a3f4a1dc2325e149be6641088414cdf5f8e077799fdea6
-- Complete method LF bytes/SHA256, without final LF:
-- update_quests:75-115 994 / 2ece7b52cfa76098c678f329d3e3ee824582550553acaa3cb7298dc48ecf0524
-- daily:161-167 182 / 7b3d88a736677ea4f4b96941dd00c7b0cea226ab8f5ee5b33db0bffd9e388ca8
-- weekly:169-179 247 / eccd07019b9e3cc1129171a6f28e6ad5fb15bc09cff9637eec1974d4c01615a8
-- event:181-191 262 / 323aa8a72255e505fda2f785675c991424041344dedaf35fa55b3f444c59b5e2
-- The private recording queue never dispatches or supplies server semantics.
local BackendInterfaceQuestsPlayfab = {}

BackendInterfaceQuestsPlayfab.update_quests = function (self, quests_updated_cb)
	if self._quests_updating then
		return
	end

	local refresh_quests = false
	local daily_update_time = self:get_daily_quest_update_time()

	if daily_update_time <= 0 then
		refresh_quests = true
	end

	local weekly_update_time = self:get_weekly_quest_update_time()

	if weekly_update_time and weekly_update_time <= 0 then
		refresh_quests = true
	end

	for key, data in pairs(self._quests.event) do
		local event_update_time = self:get_time_left_on_event_quest(key)

		if event_update_time and event_update_time <= 0 then
			refresh_quests = true

			break
		end
	end

	if refresh_quests then
		local request = {
			FunctionName = "getQuests",
		}
		local success_callback = callback(self, "get_quests_cb")
		local request_queue = self._backend_mirror:request_queue()

		request_queue:enqueue(request, success_callback, false)

		self._quests_updated_cb = quests_updated_cb
		self._quests_updating = true
	end
end

BackendInterfaceQuestsPlayfab.get_daily_quest_update_time = function (self)
	if self._dirty then
		self:_refresh()
	end

	return self._daily_quest_update_time - self._quest_timer
end

BackendInterfaceQuestsPlayfab.get_weekly_quest_update_time = function (self)
	if self._dirty then
		self:_refresh()
	end

	if not self._weekly_quest_update_time then
		return nil
	end

	return self._weekly_quest_update_time - self._quest_timer
end

BackendInterfaceQuestsPlayfab.get_time_left_on_event_quest = function (self, key)
	if self._dirty then
		self:_refresh()
	end

	if not self._event_quest_update_times[key] then
		return nil
	end

	return self._event_quest_update_times[key] - self._quest_timer
end

return BackendInterfaceQuestsPlayfab
