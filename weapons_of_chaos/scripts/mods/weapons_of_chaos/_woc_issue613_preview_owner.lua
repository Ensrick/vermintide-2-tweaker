-- Issue #613 composition owner: authenticated lease state -> remote cache and
-- exact TeamPreviewer consumers. Keeping this wiring out of the entry preserves
-- WOC's completed decomposition ceiling without hiding lifecycle ownership.
local M = {}

function M.install(context)
	local mod = assert(context and context.mod, "issue613 owner requires mod")
	local item_key = assert(context.item_key, "issue613 owner requires item key")
	local backend_id = assert(context.backend_id, "issue613 owner requires backend id")
	local preview_policy = assert(context.preview_policy,
		"issue613 owner requires preview policy")
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
		preview_policy,
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
		local transform = preview_policy.TRANSFORM
		local transform_1p = preview_policy.TRANSFORM_1P
		if not transform or transform.scale[1] ~= 0.9
				or transform.scale[2] ~= 0.9 or transform.scale[3] ~= 0.9
				or transform.rotation[1] ~= -180
				or transform.rotation[2] ~= -90 or transform.rotation[3] ~= -90
				or transform.offset[1] ~= 0 or transform.offset[2] ~= 0
				or transform.offset[3] ~= -0.3 then
			return "canonical third-person transform contract drifted"
		end
		if not transform_1p or transform_1p.scale[1] ~= 0.8
				or transform_1p.scale[2] ~= 0.8 or transform_1p.scale[3] ~= 0.8
				or transform_1p.rotation ~= transform.rotation
				or transform_1p.offset ~= transform.offset then
			return "canonical first-person transform contract drifted"
		end
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
		local menu = rawget(_G, "MenuWorldPreviewer")
		local loot = rawget(_G, "LootItemUnitPreviewer")
		local weave = rawget(_G, "HeroWindowWeaveProperties")
		if not (team and type(team._spawn_hero) == "function"
				and hero and type(hero.equip_item) == "function"
				and type(hero.play_character_animation) == "function"
				and type(hero.trigger_pose_animation) == "function"
				and type(hero.reset_pose_animation) == "function"
				and type(hero.post_update) == "function"
				and type(hero._spawn_item) == "function"
				and type(hero._destroy_item_units_by_slot) == "function"
				and type(hero.clear_units) == "function"
				and type(hero.on_exit) == "function"
				and menu and type(menu._spawn_item) == "function"
				and type(menu.play_character_animation) == "function"
				and type(menu.trigger_pose_animation) == "function"
				and type(menu.reset_pose_animation) == "function"
				and type(menu.post_update) == "function"
				and type(menu._destroy_item_units_by_slot) == "function"
				and type(menu.clear_units) == "function"
				and type(menu.on_exit) == "function"
				and loot and type(loot.load_package) == "function"
				and type(loot.spawn_units) == "function"
				and type(loot._destroy_units) == "function"
				and type(loot._unload_packages) == "function"
				and weave and type(weave._create_item_previewer) == "function") then
			return "required Team, Hero, Menu, Loot, or Athanor preview seam is unavailable"
		end
	end

	return shared, runtime
end

return M
