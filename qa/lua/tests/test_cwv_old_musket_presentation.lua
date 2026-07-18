return function(H, repo_root)
    local source = require("cwv_source").combined(repo_root)
	local policy_path = repo_root
		.. "/character_weapon_variants/scripts/mods/character_weapon_variants/_cwv_old_musket_preview.lua"
	local policy_file = assert(io.open(policy_path, "rb"))
	local policy_source = policy_file:read("*a")
	policy_file:close()

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
        H.truthy(channel:find('pcall(pm.player_from_peer_id, pm, sender_peer_id)', 1, true))
        H.equal(channel:find('pcall(pm.player_from_peer_id, pm, sender_peer_id, 1)', 1, true), nil)
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
        H.truthy(source:find('pcall(Unit.animation_event, self.character_unit, wield_event)', 1, true))
    end)

	H.test("Old Musket remote stance replays after vanilla husk wield", function()
		local wire_path = repo_root
			.. "/character_weapon_variants/scripts/mods/character_weapon_variants/_cwv_old_musket_wire.lua"
		local saved_unit = rawget(_G, "Unit")
		local saved_weapons = rawget(_G, "Weapons")
		local saved_printf = rawget(_G, "printf")
		local saved_script_unit = rawget(_G, "ScriptUnit")
		local saved_managers = rawget(_G, "Managers")
		local calls = {}
		local owner, weapon_a, weapon_b, left_control = {}, {}, {}, {}
		rawset(_G, "Unit", {
			alive = function(unit)
				return unit == owner or unit == weapon_a or unit == weapon_b
					or unit == left_control
			end,
			flow_event = function(unit, event) calls[#calls + 1] = "flow:" .. event end,
			animation_event = function(unit, event) calls[#calls + 1] = "anim:" .. event end,
		})
		rawset(_G, "Weapons", {
			old_musket_template = { wield_anim = "to_handgun" },
			old_musket_template_melee = {
				wield_anim = "to_polearm",
				wield_anim_career_3p = { es_mercenary = "to_polearm_mercenary" },
			},
		})
		rawset(_G, "printf", function() end)
		local inventory = {
			_career_name = "es_mercenary",
			equipment = function()
				return {
					wielded_slot = "slot_ranged",
					right_hand_wielded_unit_3p = weapon_a,
					left_hand_wielded_unit_3p = left_control,
				}
			end,
		}
		rawset(_G, "ScriptUnit", { extension = function() return inventory end })
		rawset(_G, "Managers", { player = { owner = function() return nil end } })
		local om = {
			_cwv_key_for_item = function() return "cwv_es_musket_old" end,
			_track_old_musket_unit = function() end,
			_apply_old_musket_textures = function() end,
			_apply_old_musket_transform = function() end,
			_old_musket_transform_components = function()
				return { 0, 0, 0 }, nil, { 1, 1, 1 }
			end,
		}
		local mod = { network_register = function() end }
		assert(loadfile(wire_path))()(mod, { om = om })
		-- Old Musket is a right-hand exception by construction: its template
		-- clears left_hand_unit and mounts the custom mesh through rifles.
		H.truthy(source:find('template.left_hand_unit                    = ""', 1, true))
		H.truthy(source:find('template.left_hand_attachment_node_linking = nil', 1, true))
		H.truthy(source:find('template.right_hand_attachment_node_linking = AttachmentNodeLinking.rifles', 1, true))
		H.truthy(source:find('_om._old_musket_apply_husk_stance(owner_unit, slot_name,\n\t\t\t\tequipment and equipment.right_hand_wielded_unit_3p', 1, true))
		local event = om._old_musket_resolve_husk_wield_event("melee", "es_mercenary")
		H.equal(event, "to_polearm_mercenary")
		H.equal(om._old_musket_resolve_husk_wield_event("ranged", "es_mercenary"),
			"to_handgun")
		H.equal(om._old_musket_resolve_husk_wield_event("invalid", "es_mercenary"), nil)
		H.truthy(om._old_musket_apply_husk_stance(owner, "slot_ranged", weapon_a,
			"melee", "test"))
		H.equal(table.concat(calls, ","), "flow:lua_wield,anim:to_polearm_mercenary")
		-- Same transition is coalesced, while a rebuilt weapon unit is replayed.
		om._old_musket_apply_husk_stance(owner, "slot_ranged", weapon_a, "melee", "test")
		H.equal(#calls, 2)
		om._old_musket_apply_husk_stance(owner, "slot_ranged", weapon_a, "ranged", "test")
		H.equal(#calls, 4)
		om._old_musket_apply_husk_stance(owner, "slot_ranged", weapon_b, "melee", "test")
		H.equal(#calls, 6)
		rawset(_G, "Unit", saved_unit)
		rawset(_G, "Weapons", saved_weapons)
		rawset(_G, "printf", saved_printf)
		rawset(_G, "ScriptUnit", saved_script_unit)
		rawset(_G, "Managers", saved_managers)
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
		H.truthy(source:find('_om._old_musket_apply_husk_stance(owner_unit, slot_name', 1, true))
		local hook_at = assert(source:find('mod:hook("SimpleHuskInventoryExtension", "_wield_slot"', 1, true))
		local vanilla_at = assert(source:find('local ok, err = pcall(func, self, world, equipment, slot_name', hook_at, true))
		local apply_at = assert(source:find('_om._old_musket_apply_husk_stance(owner_unit, slot_name', hook_at, true))
		H.truthy(apply_at > vanilla_at)

        -- (3) inventory / hero character preview: transform + stance wield-anim replay.
        H.truthy(source:find('_om._apply_old_musket_transform(slot.right, "3p", _stance)', 1, true))
        H.truthy(source:find('pcall(Unit.animation_event, self.character_unit, wield_event)', 1, true))

        -- (4) illusion browser + CIM Athanor (LootItemUnitPreviewer): shared descriptor.
        H.truthy(source:find('_om._apply_old_musket_transform(unit, "3p", preview_mode)', 1, true))
        H.truthy(source:find('_om._old_musket_preview_descriptor(item)', 1, true))

        -- The transform components come from ONE source for every surface.
        H.truthy(source:find('_om._old_musket_transform_components(perspective, mode)', 1, true))

        -- The in-keep executable half of this guard ships in the bundle too.
        H.truthy(source:find('issue474_old_musket_presentation_surface_coverage', 1, true))
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
