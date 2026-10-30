-- Exact complete native 6.13.0 login-cache functions; not a backend implementation.
-- Source commit: 93dea911a4cc464a0eb51cfdc3a443297bfc4550
-- Peddler source: scripts/managers/backend_playfab/backend_interface_peddler_playfab.lua
-- Peddler whole SHA256: a08fa03f09364291544aa532216986b7ecdc86a7853e6be98ea2f267398c0a8e
-- Manager source: scripts/managers/backend_playfab/backend_manager_playfab.lua
-- Manager whole SHA256: 50d7f0b76d8b03afac73fe7dfc021dd626d2341bb37686cd2ae6d6bf13954891
-- Each following span is LF-normalized, excluding its final newline:
-- BackendInterfacePeddlerPlayFab.init 15-35 601B SHA256 e5225510a9c46f140102d8741c6e6d014be46a7bd5584cf49b36c995f866f2a7
-- BackendInterfacePeddlerPlayFab.ready 37-39 185B SHA256 f566bf035831bee8b15c186ecf3d5650eaf95c49e83b8c97edf73e0437a44794
-- BackendInterfacePeddlerPlayFab.refresh_login_rewards 783-791 334B SHA256 89a19fe70ecd0d8de2b4621f3203da2c96b46be99ace4438175a8624bf22da54
-- BackendInterfacePeddlerPlayFab._refresh_login_rewards_cb 793-801 238B SHA256 9ad112dde324b7b36701353b96f988c2e7f5e271a336418346afd03c063c2ee4
-- BackendInterfacePeddlerPlayFab.get_login_rewards 803-805 98B SHA256 a99272164f2d35b360a78e84832963825382c0bff1ef0139420b3fe4a0c6c636
-- BackendManagerPlayFab._interfaces_ready 959-979 360B SHA256 aeae360212b710bf80466f5157579dbc0d9424ba1793356a1fed1d44d50b1c6b
-- Tests supply private recording collaborators; no queue callback/request is dispatched.
-- Init/ready are included to preserve the real population/readiness prerequisite.
local BackendInterfacePeddlerPlayFab = {}
local BackendManagerPlayFab = {}

BackendInterfacePeddlerPlayFab.init = function (self, backend_mirror)
	self._backend_mirror = backend_mirror
	self._peddler_stock = {}
	self._chips = {}
	self._app_prices = {}
	self._psn_requests = {}
	self._stock_ready = false
	self._chips_ready = false
	self._steam_stock_ready = not HAS_STEAM
	self._app_prices_ready = false
	self._steam_item_prices = {}
	self._login_rewards_cooldown = 0
	self._is_done_claiming = true

	self:refresh_stock()
	self:refresh_chips()
	self:refresh_layout_override(true)
	self:refresh_app_prices()
	self:refresh_platform_item_prices()
	self:refresh_login_rewards()
end

BackendInterfacePeddlerPlayFab.ready = function (self)
	return self._login_rewards and self._stock_ready and self._steam_stock_ready and self._chips_ready and self._app_prices_ready
end

BackendInterfacePeddlerPlayFab.refresh_login_rewards = function (self, external_cb)
	local request = {
		FunctionName = "getStoreRewards",
	}
	local request_cb = callback(self, "_refresh_login_rewards_cb", external_cb)
	local request_queue = self._backend_mirror:request_queue()

	request_queue:enqueue(request, request_cb, false)
end

BackendInterfacePeddlerPlayFab._refresh_login_rewards_cb = function (self, external_cb, result)
	local login_rewards = result.FunctionResult

	self._login_rewards = login_rewards

	if external_cb then
		external_cb(login_rewards)
	end
end

BackendInterfacePeddlerPlayFab.get_login_rewards = function (self)
	return self._login_rewards
end

BackendManagerPlayFab._interfaces_ready = function (self)
	if not self._interfaces_created then
		return false
	end

	if not self._interfaces then
		return false
	end

	local interfaces = self._interfaces

	for interface_name, interface in pairs(interfaces) do
		local ready = interface:ready()

		if not ready then
			return false
		end
	end

	return true
end

return { peddler = BackendInterfacePeddlerPlayFab, interfaces_ready = BackendManagerPlayFab._interfaces_ready }
