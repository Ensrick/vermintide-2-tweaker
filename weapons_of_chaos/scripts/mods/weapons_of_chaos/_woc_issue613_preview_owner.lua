-- Issue #613 composition owner: authenticated lease state -> remote cache and
-- exact TeamPreviewer consumers. Keeping this wiring out of the entry preserves
-- WOC's completed decomposition ceiling without hiding lifecycle ownership.
local M = {}

function M.install(context)
	local mod = assert(context and context.mod, "issue613 owner requires mod")
	local item_key = assert(context.item_key, "issue613 owner requires item key")
	local backend_id = assert(context.backend_id, "issue613 owner requires backend id")
	local preview = mod:dofile("scripts/mods/weapons_of_chaos/_woc_mod_unit_preview")
	local identity = mod:dofile(
		"scripts/mods/weapons_of_chaos/_woc_team_preview_identity")
	local preview_runtime

	local function notify_identity(peer_id, snapshot, reason)
		if preview_runtime and type(preview_runtime.notify_identity) == "function" then
			return preview_runtime:notify_identity(peer_id, snapshot, reason)
		end
		return 0
	end

	local shared = mod:dofile(
		"scripts/mods/weapons_of_chaos/_woc_shared_relic_runtime").new({
			mod = mod,
			policy = assert(context.policy, "issue613 owner requires lease policy"),
			backend_id = backend_id,
			item_key = item_key,
			remote_identity = assert(context.remote_identity,
				"issue613 owner requires remote identity cache"),
			rt_register = assert(context.rt_register,
				"issue613 owner requires regression registrar"),
			identity_listener = notify_identity,
		})

	preview_runtime = preview.install(
		assert(context.preview_policy, "issue613 owner requires preview policy"),
		assert(context.preview_appearance, "issue613 owner requires preview appearance"), {
			mod = mod,
			transform_owner = assert(context.transform_owner,
				"issue613 owner requires transform owner"),
			team_identity = identity,
			item_key = item_key,
			backend_id = backend_id,
			identity_for_peer = function(peer_id)
				return shared:identity_for_peer(peer_id)
			end,
		})

	local runtime = {}
	function runtime:contract_error()
		if type(shared.identity_for_peer) ~= "function" then
			return "authenticated lease snapshot reader is unavailable"
		end
		if type(preview_runtime) ~= "table"
				or type(preview_runtime.notify_identity) ~= "function" then
			return "TeamPreviewer identity notification seam is unavailable"
		end
		local probe = {
			key = item_key, peer_id = "peer-probe", authority_peer = "peer-host",
			authority_epoch = 1, generation = 2,
			slot_melee = true, slot_ranged = false,
		}
		if type(identity.snapshot_token(probe, "peer-probe", item_key)) ~= "string"
				or not identity.active_for_slot(
					probe, "peer-probe", item_key, "slot_melee")
				or identity.active_for_slot(
					probe, "peer-probe", item_key, "slot_ranged") then
			return "TeamPreviewer authenticated identity policy drifted"
		end
		local team = rawget(_G, "TeamPreviewer")
		local hero = rawget(_G, "HeroPreviewer")
		local weave = rawget(_G, "HeroWindowWeaveProperties")
		if not (team and type(team._spawn_hero) == "function"
				and hero and type(hero.equip_item) == "function"
				and type(hero.post_update) == "function"
				and weave and type(weave._create_item_previewer) == "function") then
			return "TeamPreviewer or exact Athanor preview seam is unavailable"
		end
	end

	return shared, runtime
end

return M
