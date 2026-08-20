return function(H, repo_root)
    local source = require("cwv_source").combined(repo_root)
	local policy_path = repo_root
		.. "/character_weapon_variants/scripts/mods/character_weapon_variants/_cwv_old_musket_preview.lua"
	local policy_file = assert(io.open(policy_path, "rb"))
	local policy_source = policy_file:read("*a")
	policy_file:close()
	local pose_policy = dofile(repo_root
		.. "/character_weapon_variants/scripts/mods/character_weapon_variants/_cwv_old_musket_preview_pose.lua")

	local function install_menu_owner()
		local hooks = {}
		local om = {
			old_musket_preview_pose = {
				install = function() end,
			},
			_cwv_transform_consumers = {
				preview = function() return nil end,
				browser = function() return nil, nil end,
			},
		}
		local mod = {
			hook = function(_, class_name, method_name, callback)
				local key = class_name .. "." .. method_name
				H.equal(hooks[key], nil, "duplicate menu-preview hook " .. key)
				hooks[key] = callback
			end,
		}
		local install = dofile(repo_root
			.. "/character_weapon_variants/scripts/mods/character_weapon_variants/_cwv_menu_preview_owner.lua")
		install(mod, {
			om = om, dbg = function() end, dbg_alert = function() end,
			resolve_field = function() end, is_unit = function() return false end,
			transform_unit = function() end, apply_cwv_hand_transform = function() end,
			transform_map = {}, skin_transform_map = {}, crowbill_transform_by_unit = {},
		})
		return om, hooks
	end

    H.test("Old Musket mode uses one event-driven state channel", function()
        -- The channel implementation lives in _cwv_old_musket_wire.lua
        -- (extracted 0.1.449-dev); the entry keeps the dofile + call sites.
        local start = assert(source:find('local CHANNEL, SCHEMA = "cwv_old_musket_mode_v1", 1', 1, true))
        local finish = assert(source:find('_om._old_musket_mode_channel = CHANNEL', start, true))
        local channel = source:sub(start, finish)
        H.truthy(source:find('mod:network_register(CHANNEL', 1, true))
        H.truthy(source:find('send("others", "query")', 1, true))
        H.truthy(source:find('_om._old_musket_record_and_publish(player_unit, wielded_slot', 1, true))
        H.equal(channel:find('mod.update = function(dt)', 1, true), nil)
        -- #474 (2026-07-18): stance and shot report ALSO ride the delivering
        -- cwv_item_identity channel through ONE shared acceptor pair.
        H.truthy(channel:find('_om._old_musket_accept_mode = accept_mode', 1, true))
        H.truthy(channel:find('_om._old_musket_play_remote_fire = play_remote_fire', 1, true))
        H.truthy(source:find('payload.musket_mode = mode', 1, true))
        H.truthy(source:find('payload.slot == "cwv_musket_fire"', 1, true))
        H.truthy(source:find('slot = "cwv_musket_fire"', 1, true))
    end)

    H.test("Old Musket consumers share cached owner and backend state", function()
        -- Husk stance is keyed by the PRESENTED slot (the owner publishes it
        -- that way); equipment.wielded_slot lags the wield RPC (#474).
        H.truthy(source:find('_om._old_musket_mode_for_owner(owner_unit_3p, slot_name)', 1, true))
        H.equal(source:find('_om._old_musket_mode_for_owner(owner_unit_3p, wielded_slot)', 1, true), nil)
        H.truthy(source:find('_om._old_musket_modes_by_backend[info.backend_id]', 1, true))
        H.truthy(source:find('Weapons.old_musket_template_melee', 1, true))
		H.truthy(source:find('_om.old_musket_preview_pose.arm(self, {', 1, true))
    end)

    H.test("Old Musket rifle report bypasses absent NetworkLookup safely", function()
        local start = assert(source:find('_om._dispatch_old_musket_remote_fire = function', 1, true))
        local finish = assert(source:find('if rawget(_G, "ActionHandgun")', start, true))
        local dispatch = source:sub(start, finish)
        H.truthy(dispatch:find('_om._old_musket_publish_fire', 1, true))
        H.equal(dispatch:find('rawget(sounds', 1, true), nil)
        H.truthy(source:find('WwiseUtils.trigger_unit_event, world, event_name, owner_unit, 0', 1, true))
    end)

    H.test("Old Musket transform resolves full saved data through the bounded descriptor", function()
        H.truthy(source:find('_om._old_musket_transform_components = function', 1, true))
		H.truthy(source:find('_om.old_musket_appearance_policy.new({', 1, true))
		H.truthy(source:find('transform_source = _om._old_musket_transform_components', 1, true))
		H.truthy(source:find('quaternion = Quaternion,', 1, true),
			"production must inject the callable retail Quaternion constructor")
		H.equal(source:find('quaternion = { to_elements = Quaternion.to_elements }', 1, true), nil)
		H.truthy(source:find('_om.old_musket_appearance.reapply_tracked()', 1, true))
		H.equal(source:find('Unit.set_local_position, unit, 0, Vector3(pos[1], pos[2], pos[3])', 1, true), nil)
    end)

	H.test("Old Musket paints browser previews per unit through the descriptor", function()
		H.truthy(policy_source:find('function M.apply_textures(unit, preview_world)', 1, true))
		H.truthy(policy_source:find('Unit.set_texture_for_materials', 1, true))
		H.equal(policy_source:find('pcall(Material.set_texture', 1, true), nil)
		H.truthy(policy_source:find('M.texture_resources_ready(Application and Application.can_get)', 1, true))
		H.truthy(policy_source:find('M.prepare_preview_material(unit)', 1, true))
		H.truthy(policy_source:find('Unit.set_all_materials', 1, true))
		H.truthy(source:find('_om._apply_old_musket_textures = _om.old_musket_preview.apply_textures', 1, true))

        -- #419 named the wrapper body so the browser delivery contract is
        -- executable; the LootItemUnitPreviewer.spawn_units registration now only
        -- delegates to it, so the body is anchored by its own name.
        local hook_start = assert(source:find(
            '_om._cwv_browser_spawn_units = function(func, self, spawn_data)', 1, true))
        local hook_finish = assert(source:find('-- ============================================================\n-- Init', hook_start, true))
        local hook = source:sub(hook_start, hook_finish)
        H.truthy(hook:find('_om._old_musket_preview_texture_targets(', 1, true))
        H.truthy(hook:find('_om._old_musket_preview_descriptor(item)', 1, true))
		H.truthy(hook:find('_om.old_musket_appearance.reconcile(unit,', 1, true))
		H.truthy(hook:find('[cwv:617] Old Musket preview textures applied', 1, true))
	end)

	H.test("Old Musket marks only the Athanor previewer returned by its constructor", function()
		local om, hooks = install_menu_owner()
		local callback = assert(hooks[
			"HeroWindowWeaveProperties._create_item_previewer"])
		local returned = {}
		local self, viewport, item, activate_spin = {}, {}, {}, {}
		local seen
		local result = callback(function(...)
			seen = { n = select("#", ...), ... }
			return returned
		end, self, viewport, item, activate_spin)
		H.equal(result, returned)
		H.equal(returned._cwv_cim_preview, true)
		H.equal(seen.n, 4)
		H.equal(seen[1], self)
		H.equal(seen[2], viewport)
		H.equal(seen[3], item)
		H.equal(seen[4], activate_spin)
		H.equal(om._cwv_loot_preview_surface(returned), "cim_preview")

		local ordinary = {}
		H.equal(ordinary._cwv_cim_preview, nil)
		H.equal(om._cwv_loot_preview_surface(ordinary), "illusion_browser")
		H.equal(om._cwv_loot_preview_surface({ _cwv_cim_preview = 1 }),
			"illusion_browser")
	end)

	H.test("Old Musket real render call sites route through the shared resolver", function()
        -- issue 474: the recurring failure class was one render surface drifting
        -- off the shared resolver (husk shows the base handgun, inventory preview
        -- drops the stance pose, the Athanor shows nothing). Assert every surface
        -- routes through the single applicator/descriptor set so a refactor cannot
        -- silently drop one again.

        -- (1) owner in-world spawn: both 1P and 3P through the shared applicator.
		H.truthy(source:find('_om.old_musket_appearance.reconcile(v_w1p, "owner_1p", "equip"', 1, true))
		H.truthy(source:find('_om.old_musket_appearance.reconcile(v_w3p, "owner_3p", "equip"', 1, true))

		-- (1b) locally simulated bot 3P: GearUtils.create_equipment has its own
		-- adapter and must not be mistaken for the remote-husk spawn path.
		H.truthy(source:find('is_bot and "bot" or "owner_3p", "equip", item_data, musket_mode', 1, true),
			"bot create_equipment must enter the shared Old Musket reconciler")

		-- (2) remote husk 3P: stance resolved from the bounded channel, not the wire.
		H.truthy(source:find('_om.old_musket_appearance.reconcile(weapon_unit_3p, "husk", "equip"', 1, true))
		H.truthy(source:find('rendered_unit_name = rendered_unit_name .. "_3p"', 1, true))
		H.truthy(source:find('unit_name = rendered_unit_name,', 1, true),
			"husk adapter must prove the spawned 3P alias, not the base unit path")
		H.truthy(source:find('_om.old_musket_appearance.reconcile(unit, "husk", "peer_ready"', 1, true))
        H.truthy(source:find('_om._old_musket_mode_for_owner(owner_unit_3p, slot_name)', 1, true))

        -- (3) inventory / hero character preview: transform + stance wield-anim replay.
		H.truthy(source:find('"inventory_preview", "preview_open"', 1, true))
		H.truthy(source:find('pcall(Unit.animation_event, pending.character_unit, pending.wield_event)', 1, true))
		H.truthy(source:find('apply_transform(weapon_unit, "3p", pending.stance, pending)', 1, true),
			"final preview stability edge must retain the same stance transform")
		H.truthy(source:find('_om.old_musket_preview_pose.install(mod, function(unit, _, mode, record)', 1, true))
		H.truthy(source:find('[cwv:474/792] preview transform retained', 1, true))

		-- (4) illusion browser and CIM share LootItemUnitPreviewer, but only the
		-- instance returned by HeroWindowWeaveProperties gets the CIM marker.
		H.truthy(source:find('local function _cwv_loot_preview_surface(previewer)', 1, true))
		H.truthy(source:find('and "cim_preview" or "illusion_browser"', 1, true))
		H.truthy(source:find('preview_surface, "preview_open", item, preview_mode', 1, true))
		H.truthy(source:find('mod:hook("HeroWindowWeaveProperties", "_create_item_previewer"', 1, true))
		H.truthy(source:find('local previewer = func(self, viewport_widget, item, ...)', 1, true))
        H.truthy(source:find('_om._old_musket_preview_descriptor(item)', 1, true))

		-- (5) lobby and score are explicitly marked by TeamPreviewer, rather than
		-- inferred from Crowbill-only state.
		H.truthy(source:find('hero_previewer._cwv_team_preview = true', 1, true))
		H.truthy(source:find('self._cwv_team_peer_source == "score_snapshot"', 1, true))
		H.truthy(source:find('and "score_team" or "lobby"', 1, true))

        -- The transform components come from ONE source for every surface.
        H.truthy(source:find('_om._old_musket_transform_components(perspective, mode)', 1, true))

        -- The in-keep executable half of this guard ships in the bundle too.
		H.truthy(source:find('issue474_old_musket_presentation_surface_coverage', 1, true))
	end)

	H.test("Old Musket preview resolves the exact spawned slot with duplicate item names", function()
		local template = {
			wield_anim = "default",
			wield_anim_career = { es_huntsman = "career" },
			wield_anim_career_3p = { es_huntsman = "career_3p" },
		}
		H.equal(pose_policy.resolve_wield_event(template, "es_huntsman"), "career_3p")
		H.equal(pose_policy.resolve_wield_event(template, "es_mercenary"), "default")
		template.wield_anim_career_3p.es_huntsman = nil
		H.equal(pose_policy.resolve_wield_event(template, "es_huntsman"), "career")

		local melee_spawn = {
			{ item_slot_type = "melee", slot_index = 1 },
			{ item_slot_type = "melee", slot_index = 1 },
		}
		local ranged_spawn = { { item_slot_type = "ranged", slot_index = 2 } }
		local melee = { name = "es_handgun", backend_id = "musket-melee",
			spawn_data = melee_spawn }
		local ranged = { name = "es_handgun", backend_id = "musket-ranged",
			spawn_data = ranged_spawn }
		local previewer = { _item_info_by_slot = { melee = melee, ranged = ranged } }

		local slot, info, index = pose_policy.resolve_spawn_slot(previewer,
			"es_handgun", ranged_spawn)
		H.equal(slot, "ranged")
		H.equal(info, ranged)
		H.equal(index, 2)
		H.equal(info.backend_id, "musket-ranged")

		local cloned_spawn = { { item_slot_type = "ranged", slot_index = 2 } }
		slot, info, index = pose_policy.resolve_spawn_slot(previewer,
			"es_handgun", cloned_spawn)
		H.equal(slot, nil)
		H.equal(info, nil)
		H.equal(index, "spawn_changed")

		local ambiguous = {
			{ item_slot_type = "melee", slot_index = 1 },
			{ item_slot_type = "ranged", slot_index = 2 },
		}
		slot, info, index = pose_policy.resolve_spawn_slot(previewer,
			"es_handgun", ambiguous)
		H.equal(slot, nil)
		H.equal(info, nil)
		H.equal(index, "spawn_ambiguous")
	end)

	H.test("Old Musket preview pose waits for and consumes one stable edge", function()
		local character = {}
		local previewer = {
			character_unit = character,
			_wielded_slot_type = "ranged",
			_item_info_by_slot = {
				ranged = { name = "es_handgun", backend_id = "musket-1" },
			},
		}
		local record = {
			character_unit = character,
			item_name = "es_handgun",
			backend_id = "musket-1",
			slot_type = "ranged",
			slot_index = 2,
			stance = "melee",
			wield_event = "to_2h_spear",
		}

		H.truthy(pose_policy.arm(previewer, record))
		local stored = previewer._cwv_old_musket_pose_pending
		H.truthy(stored)
		H.equal(stored == record, false)
		local pending, reason = pose_policy.take_when_stable(previewer, false)
		H.equal(pending, nil)
		H.equal(reason, "loading")
		H.equal(previewer._cwv_old_musket_pose_pending, stored)

		pending, reason = pose_policy.take_when_stable(previewer, true)
		H.equal(pending, stored)
		H.equal(reason, "ready")
		H.equal(pending.stance, "melee")
		H.equal(previewer._cwv_old_musket_pose_pending, nil)

		pending, reason = pose_policy.take_when_stable(previewer, true)
		H.equal(pending, nil)
		H.equal(reason, "not_armed")
	end)

	H.test("Old Musket preview pose rejects invalid and stale generations", function()
		local function armed()
			local character = {}
			local previewer = {
				character_unit = character,
				_wielded_slot_type = "ranged",
				_item_info_by_slot = {
					ranged = { name = "es_handgun", backend_id = "musket-1" },
				},
			}
			H.truthy(pose_policy.arm(previewer, {
				character_unit = character,
				item_name = "es_handgun",
				backend_id = "musket-1",
				slot_type = "ranged",
				slot_index = 2,
				wield_event = "to_handgun",
				stance = "ranged",
			}))
			return previewer
		end

		H.equal(pose_policy.arm({}, { slot_type = "ranged" }), false)
		H.equal(pose_policy.arm({}, {
			character_unit = {}, item_name = "es_handgun", backend_id = string.rep("x", 129),
			slot_type = "ranged", slot_index = 2, stance = "ranged",
			wield_event = "to_handgun",
		}), false)
		local previewer = armed()
		previewer._wielded_slot_type = "melee"
		local pending, reason = pose_policy.take_when_stable(previewer, true)
		H.equal(pending, nil)
		H.equal(reason, "slot_changed")

		previewer = armed()
		previewer._item_info_by_slot.ranged.backend_id = "musket-2"
		pending, reason = pose_policy.take_when_stable(previewer, true)
		H.equal(pending, nil)
		H.equal(reason, "backend_changed")

		previewer = armed()
		previewer.character_unit = {}
		pending, reason = pose_policy.take_when_stable(previewer, true)
		H.equal(pending, nil)
		H.equal(reason, "character_changed")

		local reopened = armed()
		pending, reason = pose_policy.take_when_stable(reopened, true)
		H.truthy(pending)
		H.equal(reason, "ready")
	end)

	H.test("Old Musket crafted UUID identity does not regress to prefix-only gates", function()
        H.truthy(source:find('_om._cwv_key_for_item(_bid_for_tex, item_data)', 1, true))
        H.truthy(source:find('_spawn_cwv_key == "cwv_es_musket_old"', 1, true))
        H.truthy(source:find('_om._old_musket_bid_for_item = old_bid', 1, true))
        H.truthy(source:find('or item.ItemInstanceId', 1, true))
        H.equal(source:find('_bid_for_tex:match("^cwv_es_musket_old")', 1, true), nil)
        H.equal(source:find('or not bid:match("^cwv_es_musket_old")', 1, true), nil)
        H.truthy(source:find('issue484_crafted_old_musket_identity', 1, true))
    end)

    H.test("Old Musket texture C-call fails closed", function()
		H.truthy(policy_source:find('Old Musket paint SKIP reason=%s detail=%s chat=false', 1, true))
		H.equal(policy_source:find('pcall(Material.set_texture', 1, true), nil)
		local census_at = assert(policy_source:find('M.unit_materials_ready(unit)', 1, true))
		local paint_at = assert(policy_source:find('Unit.set_texture_for_materials(unit, binding.slot, binding.texture)', 1, true))
		H.truthy(census_at < paint_at)
		H.truthy(source:find('issue742_old_musket_texture_material_preflight', 1, true))
        H.truthy(source:find('issue617_old_musket_preview_texture_consumer', 1, true))
        H.truthy(source:find('resource preflight must fail closed on one missing texture', 1, true))
    end)
end
