return function(H, repo_root)
    local source = require("cwv_source").combined(repo_root)
	local policy_path = repo_root
		.. "/character_weapon_variants/scripts/mods/character_weapon_variants/_cwv_old_musket_preview.lua"
	local policy_file = assert(io.open(policy_path, "rb"))
	local policy_source = policy_file:read("*a")
	policy_file:close()
	local pose_policy = dofile(repo_root
		.. "/character_weapon_variants/scripts/mods/character_weapon_variants/_cwv_old_musket_preview_pose.lua")

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

    H.test("Old Musket transform writes full saved triplets and re-buckets units", function()
        H.truthy(source:find('_om._old_musket_transform_components = function', 1, true))
        H.truthy(source:find('Unit.set_local_position, unit, 0, Vector3(pos[1], pos[2], pos[3])', 1, true))
        H.truthy(source:find('Unit.set_local_scale, unit, 0, Vector3(scale[1], scale[2], scale[3])', 1, true))
        H.truthy(source:find('_om._CWV_OLD_MUSKET_UNITS_3P_RANGED[unit] = nil', 1, true))
        H.truthy(source:find('_om._CWV_OLD_MUSKET_UNITS_3P_MELEE[unit] = nil', 1, true))
    end)

    H.test("Old Musket paints CIM and browser previews per unit", function()
		H.truthy(policy_source:find('function M.apply_textures(unit, preview_world)', 1, true))
		H.truthy(policy_source:find('Unit.set_texture_for_materials', 1, true))
		H.equal(policy_source:find('pcall(Material.set_texture', 1, true), nil)
		H.truthy(policy_source:find('M.texture_resources_ready(Application and Application.can_get)', 1, true))
		H.truthy(policy_source:find('M.prepare_preview_material(unit)', 1, true))
		H.truthy(policy_source:find('Unit.set_all_materials', 1, true))
		H.truthy(source:find('_om._apply_old_musket_textures = _om.old_musket_preview.apply_textures', 1, true))

        local hook_start = assert(source:find('mod:hook("LootItemUnitPreviewer", "spawn_units"', 1, true))
        local hook_finish = assert(source:find('-- ============================================================\n-- Init', hook_start, true))
        local hook = source:sub(hook_start, hook_finish)
        H.truthy(hook:find('_om._old_musket_preview_texture_targets(musket_def, units, spawn_data)', 1, true))
        H.truthy(hook:find('_om._old_musket_preview_descriptor(item)', 1, true))
        H.truthy(hook:find('_om._apply_old_musket_textures(unit, true)', 1, true))
        H.truthy(hook:find('[cwv:617] Old Musket preview textures applied', 1, true))
    end)

	H.test("Old Musket presentation fans out to every render surface via the shared resolver", function()
        -- issue 474: the recurring failure class was one render surface drifting
        -- off the shared resolver (husk shows the base handgun, inventory preview
        -- drops the stance pose, the Athanor shows nothing). Assert every surface
        -- routes through the single applicator/descriptor set so a refactor cannot
        -- silently drop one again.

        -- (1) owner in-world spawn: both 1P and 3P through the shared applicator.
        H.truthy(source:find('_om._apply_old_musket_transform(v_w1p, "1p", _mode)', 1, true))
        H.truthy(source:find('_om._apply_old_musket_transform(v_w3p, "3p", _mode)', 1, true))

        -- (2) remote husk 3P: stance resolved from the bounded channel, not the wire.
        H.truthy(source:find('pcall(_om._apply_old_musket_transform, weapon_unit_3p, "3p", mode)', 1, true))
        H.truthy(source:find('_om._old_musket_mode_for_owner(owner_unit_3p, slot_name)', 1, true))

        -- (3) inventory / hero character preview: transform + stance wield-anim replay.
        H.truthy(source:find('_om._apply_old_musket_transform(slot.right, "3p", _stance)', 1, true))
		H.truthy(source:find('pcall(Unit.animation_event, pending.character_unit, pending.wield_event)', 1, true))
		H.truthy(source:find('apply_transform(weapon_unit, "3p", pending.stance)', 1, true),
			"final preview stability edge must retain the same stance transform")
		H.truthy(source:find('_om.old_musket_preview_pose.install(mod, _om._apply_old_musket_transform', 1, true))
		H.truthy(source:find('[cwv:474/792] preview transform retained', 1, true))

        -- (4) illusion browser + CIM Athanor (LootItemUnitPreviewer): shared descriptor.
        H.truthy(source:find('_om._apply_old_musket_transform(unit, "3p", preview_mode)', 1, true))
        H.truthy(source:find('_om._old_musket_preview_descriptor(item)', 1, true))

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
