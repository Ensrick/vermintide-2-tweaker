-- Complete native 6.13 methods, verbatim; never dispatch the recording queue.
-- Commit 93dea911a4cc464a0eb51cfdc3a443297bfc4550
-- scripts/managers/backend_playfab/backend_interface_quests_playfab.lua
-- _new_id:65-69; claim_quest_rewards:285-301; multiple:501-527.
-- Source Git blob: be44da375de5c2ff9e0459a88f263c207a89b139
-- Whole Git-LF SHA256: a7698ef8145b422a53a3f4a1dc2325e149be6641088414cdf5f8e077799fdea6
-- Complete method LF bytes/SHA256, without final LF:
-- _new_id 117 / ef7abe0b9a0193e1543ec7ba1da1c64c5fbf685af00fc712e675737822bf9c35
-- single 447 / 7fbdb2123a89073990a5c67337d446eb6824e503b53726558a9d4693522e4c4a
-- multiple 626 / 6a3f0b901d7ad42e3eba2073c8299ee2d18b0ef3ce3ab096a0b897804ea9c3df
local BackendInterfaceQuestsPlayfab = {}

BackendInterfaceQuestsPlayfab._new_id = function (self)
	self._last_id = self._last_id + 1

	return self._last_id
end

BackendInterfaceQuestsPlayfab.claim_quest_rewards = function (self, key)
	local id = self:_new_id()
	local data = {
		quest_key = key,
		id = id,
	}
	local request = {
		FunctionName = "generateQuestRewards",
		FunctionParameter = data,
	}
	local success_callback = callback(self, "quest_rewards_request_cb", data)
	local request_queue = self._backend_mirror:request_queue()

	request_queue:enqueue(request, success_callback, true)

	return id
end

BackendInterfaceQuestsPlayfab.claim_multiple_quest_rewards = function (self, keys)
	local quest_data = {}
	local id = self:_new_id()

	for i = 1, #keys do
		local key = keys[i]
		local data = {
			quest_key = key,
		}

		quest_data[#quest_data + 1] = data
	end

	local request = {
		FunctionName = "generateQuestRewards",
		FunctionParameter = {
			quest_data = quest_data,
			id = id,
		},
	}
	local success_callback = callback(self, "claim_multiple_quest_rewards_request_cb", quest_data, id)
	local request_queue = self._backend_mirror:request_queue()

	request_queue:enqueue(request, success_callback, true)

	return id
end

return BackendInterfaceQuestsPlayfab
