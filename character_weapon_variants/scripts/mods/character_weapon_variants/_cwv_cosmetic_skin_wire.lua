-- Issue #423 (skin axis / BUG_CLASSES 31): pure sender-side policy for the
-- CosmeticUtils.update_cosmetic_slot profile-sync channel.
--
-- update_cosmetic_slot(player, slot, item_name, skin_name) resolves
-- skin_id = NetworkLookup.weapon_skins[skin_name] and writes it via
-- player:set_data(slot .. "_skin", skin_id) into GameSession player-sync data
-- broadcast to EVERY peer (cosmetic_utils.lua:244-250). This is a FOURTH skin
-- sender, distinct from the three equipment RPCs (game_object_initialized /
-- _spawn_resynced_loadout / hot_join_sync) the mod already covers. A cwv_*
-- weapon_skins id is undefined on a peer without cwv, so when the scoreboard /
-- playerlist reads it back through the strict decode (get_weapon_skin_name,
-- cosmetic_utils.lua:168-178) that peer fatals -- the identical crash class as
-- rpc_add_equipment, on the profile-sync channel. Observed 2026-07-18:
-- weapon_skins index 924 (cwv_es_musket_old_skin) CTD'd a non-cwv client at the
-- end-of-mission scoreboard (rpc_sync_players_session_score).
--
-- Husk weapon rendering never reads this player-sync field (it resolves the
-- variant appearance from item_data + the cwv identity channel), so the
-- substitution is a pure cosmetic-display concession: it is UNCONDITIONAL, never
-- parity-gated (issue 371 / BUG_CLASSES 31 doctrine -- a modded value must never
-- ride a vanilla wire, and here it buys nothing to let it ride). Engine-free so
-- the contract runs in the offline Lua suite.

local M = {}

-- The universal vanilla "no skin" key. get_weapon_skin_id defaults to it
-- (cosmetic_utils.lua:209) and it has a boot-stable weapon_skins index on every
-- peer, so encoding it is safe for a client without cwv.
M.VANILLA_NO_SKIN = "n/a"

-- True when `skin` is a cwv-registered NetworkLookup.weapon_skins key: present in
-- the base-variant key set, the pairing/illusion custom key set, or cwv_-prefixed
-- (every cwv-injected key is cwv_-prefixed; no vanilla key is). Belt-and-suspenders
-- prefix check catches any key registered after this predicate's key sets snapshot.
function M.is_cwv_skin(skin, skin_keys, custom_skin_keys)
	if type(skin) ~= "string" then return false end
	if type(skin_keys) == "table" and skin_keys[skin] then return true end
	if type(custom_skin_keys) == "table" and custom_skin_keys[skin] then return true end
	return skin:sub(1, 4) == "cwv_"
end

-- Returns (safe_skin_name, substituted). A cwv skin is UNCONDITIONALLY coerced to
-- the vanilla "no skin" key before it can reach the profile-sync wire; a vanilla
-- (or nil) skin passes through unchanged.
function M.wire_safe_skin(skin, skin_keys, custom_skin_keys)
	if M.is_cwv_skin(skin, skin_keys, custom_skin_keys) then
		return M.VANILLA_NO_SKIN, true
	end
	return skin, false
end

-- Issue #741: temporarily remove every CWV skin from live slot records while a
-- vanilla equipment sender encodes NetworkLookup.weapon_skins.  Mod presence is
-- not numeric lookup parity: a second skin-appending mod can shift the index on
-- one otherwise-CWV-capable peer.  Therefore this helper deliberately has no
-- roster/parity input.  The real appearance travels on cwv_item_identity as
-- stable string keys; the vanilla wire always receives its universal no-skin
-- fallback.
--
-- Slot mutation is scoped to send_fn and exception-safe.  This matters because
-- these are the owner's live equipment records: leaking the temporary nil after
-- an engine error would corrupt the local appearance as well as later sends.
function M.with_safe_slots(slots, skin_keys, custom_skin_keys, send_fn, on_substitute)
	assert(type(slots) == "table", "slots must be a table")
	assert(type(send_fn) == "function", "send_fn must be a function")

	local saved = {}
	for _, slot_data in pairs(slots) do
		local skin = type(slot_data) == "table" and slot_data.skin
		if M.is_cwv_skin(skin, skin_keys, custom_skin_keys) then
			saved[#saved + 1] = { slot = slot_data, skin = skin }
			slot_data.skin = nil
			if type(on_substitute) == "function" then
				pcall(on_substitute, slot_data, skin)
			end
		end
	end

	local ok, r1, r2, r3, r4 = pcall(send_fn)
	for i = 1, #saved do
		local entry = saved[i]
		entry.slot.skin = entry.skin
	end
	if not ok then error(r1, 0) end
	return r1, r2, r3, r4
end

return M
