return function(H, repo_root)
    local source = require("cwv_source").combined(repo_root)

    H.test("Old Musket mode uses one event-driven state channel", function()
        local start = assert(source:find('local CHANNEL, SCHEMA = "cwv_old_musket_mode_v1", 1', 1, true))
        local finish = assert(source:find('-- v0.1.293 approach A:', start, true))
        local channel = source:sub(start, finish)
        H.truthy(source:find('mod:network_register(CHANNEL', 1, true))
        H.truthy(source:find('send("others", "query")', 1, true))
        H.truthy(source:find('_om._old_musket_record_and_publish(player_unit, wielded_slot', 1, true))
        H.equal(channel:find('mod.update = function(dt)', 1, true), nil)
    end)

    H.test("Old Musket consumers share cached owner and backend state", function()
        H.truthy(source:find('_om._old_musket_mode_for_owner(owner_unit_3p, wielded_slot)', 1, true))
        H.truthy(source:find('_om._old_musket_modes_by_backend[info.backend_id]', 1, true))
        H.truthy(source:find('Weapons.old_musket_template_melee', 1, true))
        H.truthy(source:find('pcall(Unit.animation_event, self.character_unit, wield_event)', 1, true))
    end)

    H.test("Old Musket rifle report bypasses absent NetworkLookup safely", function()
        local start = assert(source:find('_om._dispatch_old_musket_remote_fire = function', 1, true))
        local finish = assert(source:find('if rawget(_G, "ActionHandgun")', start, true))
        local dispatch = source:sub(start, finish)
        H.truthy(dispatch:find('_om._old_musket_publish_fire', 1, true))
        H.equal(dispatch:find('rawget(sounds', 1, true), nil)
        H.truthy(source:find('WwiseUtils.trigger_unit_event, world, mode, owner_unit, 0', 1, true))
    end)

    H.test("Old Musket transform writes full saved triplets and re-buckets units", function()
        H.truthy(source:find('_om._old_musket_transform_components = function', 1, true))
        H.truthy(source:find('Unit.set_local_position, unit, 0, Vector3(pos[1], pos[2], pos[3])', 1, true))
        H.truthy(source:find('Unit.set_local_scale, unit, 0, Vector3(scale[1], scale[2], scale[3])', 1, true))
        H.truthy(source:find('_om._CWV_OLD_MUSKET_UNITS_3P_RANGED[unit] = nil', 1, true))
        H.truthy(source:find('_om._CWV_OLD_MUSKET_UNITS_3P_MELEE[unit] = nil', 1, true))
    end)

    H.test("Old Musket paints CIM and browser previews per unit", function()
        local helper_start = assert(source:find('_om._apply_old_musket_textures = function', 1, true))
        local helper_finish = assert(source:find('_om._old_musket_preview_texture_targets = function', helper_start, true))
        local helper = source:sub(helper_start, helper_finish)
        H.truthy(helper:find('Unit.set_texture_for_materials', 1, true))
        H.equal(helper:find('pcall(Material.set_texture', 1, true), nil)
        H.truthy(helper:find('_om._old_musket_texture_resources_ready', 1, true))
        H.truthy(helper:find('Application and Application.can_get', 1, true))
        H.truthy(helper:find('_om._prepare_old_musket_preview_material', 1, true))
        H.truthy(source:find('Unit.set_all_materials', 1, true))

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
        H.truthy(source:find('_om._old_musket_mode_for_owner(owner_unit_3p, wielded_slot)', 1, true))

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
        H.truthy(source:find('Old Musket paint SKIP reason=%s detail=%s chat=false', 1, true))
        H.truthy(source:find('return false, 0\n\tend\n\tif preview_world then', 1, true))
        H.equal(source:find('pcall(Material.set_texture', 1, true), nil)
        H.truthy(source:find('issue617_old_musket_preview_texture_consumer', 1, true))
        H.truthy(source:find('resource preflight must fail closed on one missing texture', 1, true))
    end)
end
