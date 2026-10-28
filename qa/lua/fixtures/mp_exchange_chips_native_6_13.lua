-- Complete native 6.13 request producer and exact captured store constant.
-- Commit 93dea911a4cc464a0eb51cfdc3a443297bfc4550
-- scripts/managers/backend_playfab/backend_interface_peddler_playfab.lua:7,661-674.
-- Source Git blob: cc0c9609646f558d4e489d9d78824ef32536feae
-- Whole Git-LF SHA256: f3e6427fea47b271d8cd9f0bac3346d68b73df2b8d375835ff0a70fadf5c77e4
-- Complete method 569 LF bytes (no final LF); SHA256:
-- 37d6f60ef8f68817ee213b0f27f40ecddd12306d86216694e8a3d8a7f5077715
-- Tests stop at a private recording queue; callbacks are never dispatched.
local BackendInterfacePeddlerPlayFab = {}
local PEDDLER_ID = "Store"

BackendInterfacePeddlerPlayFab.exchange_chips = function (self, item_id, chip_type, expected_chip_amount, external_cb)
	local request = {
		StoreId = PEDDLER_ID,
		ItemId = item_id,
		VirtualCurrency = chip_type,
		Price = expected_chip_amount,
	}
	local success_cb = callback(self, "_exchange_chips_success_cb", external_cb)
	local error_cb = callback(self, "_exchange_chips_error_cb", external_cb)
	local mirror = self._backend_mirror
	local request_queue = mirror:request_queue()

	request_queue:enqueue_api_request("PurchaseItem", request, success_cb, error_cb)
end

return BackendInterfacePeddlerPlayFab.exchange_chips
