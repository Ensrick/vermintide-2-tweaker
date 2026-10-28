-- Exact complete native 6.13.0 request producer; not a backend implementation.
-- Commit: 93dea911a4cc464a0eb51cfdc3a443297bfc4550
-- scripts/managers/backend_playfab/backend_interface_peddler_playfab.lua:811-828
-- Whole source SHA256: a08fa03f09364291544aa532216986b7ecdc86a7853e6be98ea2f267398c0a8e
-- Method LF bytes (no final newline): 480; SHA256: f56d6f76ae3181240002c4679557f3a9340a9af0d885243692a04bcce5ffef44
-- Tests supply a private recording queue; no callback is dispatched/network used.
local BackendInterfacePeddlerPlayFab = {}

BackendInterfacePeddlerPlayFab.claim_login_rewards = function (self, external_cb, offset)
	if not self._is_done_claiming then
		return
	end

	local request = {
		FunctionName = "claimStoreRewards",
		FunctionParameter = {
			offset = offset,
		},
	}
	local request_cb = callback(self, "_claim_store_rewards_cb", external_cb, offset)
	local request_queue = self._backend_mirror:request_queue()

	request_queue:enqueue(request, request_cb, true)

	self._is_done_claiming = false
end

return BackendInterfacePeddlerPlayFab.claim_login_rewards
