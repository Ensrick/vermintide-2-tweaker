-- tools/harness/driver/lib/wire.lua: T.transmit_spy, a record of the RPCs this machine sends (WP-H-06 group "wire").
--
-- A helper group (tools/harness/API.md). The solo check for lookup-index bugs (docs/program/vp/D1.md section 0.2,
-- primitive P7): a solo host still calls the senders, so the ids recorded are the ones a client would receive, even
-- though nothing leaves the machine. Nothing is changed on the way: every call goes through to the sender it replaced.

-- Every sender of NetworkTransmit (Vermintide-2-Source-Code/scripts/network/network_transmit.lua:169-533); each takes
-- (self, rpc_name, ...).
local SENDERS = {
	"send_rpc", "send_rpc_server", "send_rpc_dedicated_server", "send_rpc_party_clients", "send_rpc_party", "send_rpc_side",
	"send_rpc_side_clients", "send_rpc_clients", "send_rpc_clients_except", "send_rpc_side_clients_except", "send_rpc_all",
	"send_rpc_all_except",
}

return function (T, ctx)
	local case = ctx.case

	-- Starts recording the calls to the senders of Managers.state.network.network_transmit
	-- (GameNetworkManager, scripts/managers/network/game_network_manager.lua:109) whose rpc_name is `rpc_names` (one
	-- name, a list of names, or nil for every RPC). Each wrapper is set on the instance and calls the sender it found
	-- there, so class hooks and instance hooks installed before keep running. Returns a spy:
	--   spy.calls        list of { rpc = name, via = sender, n = count, args = { ... } }; args are what followed
	--                    rpc_name (for send_rpc the peer id comes first, for the *_except and party/side senders their
	--                    routing arguments do); engine values (a Vector3, a unit) are kept as tostring text, because
	--                    they are frame temporaries or references the case must not hold
	--   spy.count(name)  number of recorded calls of that RPC (all when nil)
	--   spy.stop()       puts the senders back; also done at cleanup
	-- INCONCLUSIVE when there is no network transmit (outside StateIngame).
	function T.transmit_spy(rpc_names)
		local network = Managers.state.network
		local transmit = network and network.network_transmit

		T.require(type(transmit) == "table", "network transmit exists")

		local wanted

		if type(rpc_names) == "string" then
			wanted = { [rpc_names] = true }
		elseif type(rpc_names) == "table" then
			wanted = {}

			for _, name in ipairs(rpc_names) do
				wanted[name] = true
			end
		end

		local spy = { calls = {} }
		local installed = {}

		for _, sender in ipairs(SENDERS) do
			local through = transmit[sender]

			if type(through) == "function" then
				local wrapper

				wrapper = function (self, rpc_name, ...)
					if wanted == nil or wanted[rpc_name] then
						local n = select("#", ...)
						local args = {}

						for i = 1, n do
							local value = select(i, ...)

							args[i] = type(value) == "userdata" and tostring(value) or value
						end

						spy.calls[#spy.calls + 1] = { rpc = rpc_name, via = sender, n = n, args = args }
					end

					return through(self, rpc_name, ...)
				end

				installed[#installed + 1] = { sender = sender, previous = rawget(transmit, sender), wrapper = wrapper }
				rawset(transmit, sender, wrapper)
			end
		end

		function spy.count(name)
			local total = 0

			for _, call in ipairs(spy.calls) do
				if name == nil or call.rpc == name then
					total = total + 1
				end
			end

			return total
		end

		local stopped = false

		function spy.stop()
			if stopped then
				return
			end

			stopped = true

			local kept = 0

			for _, entry in ipairs(installed) do
				-- only undo our own wrapper: something installed on top of it after the spy started stays
				if rawget(transmit, entry.sender) == entry.wrapper then
					rawset(transmit, entry.sender, entry.previous)
				else
					kept = kept + 1
				end
			end

			ctx.out("SPY STOP id=%s calls=%d senders=%d replaced_after_start=%d", case.id, #spy.calls, #installed, kept)
		end

		case.cleanups[#case.cleanups + 1] = spy.stop

		ctx.out("SPY START id=%s rpc=%s senders=%d", case.id, type(rpc_names) == "table" and table.concat(rpc_names, ",") or tostring(rpc_names or "all"), #installed)

		return spy
	end
end
