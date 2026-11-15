-- qa/runtime/cwv/a2f01_outrider_wire_name.lua
-- WP-CWV-01 rig case (audit finding A2-F01): an Outrider Grenade Launcher shot
-- creates a projectile game object whose item_template_name field is the
-- VANILLA index of dr_deus_01_template_1, while the local projectile still
-- uses the cwv grenade config (what #1320 needs).
--
-- Engine reads (Vermintide-2-Source-Code):
--   * fire path mirrored here: scripts/unit_extensions/weapons/actions/action_grenade_thrower.lua:59-75
--   * ActionUtils.spawn_player_projectile: scripts/helpers/action_utils.lua:446
--   * ProjectileSystem.spawn_player_projectile -> spawn_network_unit:
--     scripts/entity_system/systems/projectile/projectile_system.lua:178-249
--   * spawn_network_unit runs extension init, then the go initializer, then
--     GameSession.create_game_object: scripts/network/unit_spawner.lua:336-346
--   * initializer encodes action_lookup_data.item_template_name and item_name:
--     scripts/network/game_object_initializers_extractors.lua:735-755
--   * PlayerProjectileUnitExtension.projectile_info:
--     scripts/unit_extensions/weapons/projectiles/player_projectile_unit_extension.lua:78
--   * equip pattern: scripts/unit_extensions/default_player_unit/inventory/simple_inventory_extension.lua:2175-2183
--   * BackendUtils.get_loadout_item_id / set_loadout_item: scripts/managers/backend/backend_utils.lua:14, 22
--   * GameNetworkManager.request_profile: scripts/managers/network/game_network_manager.lua:358
--
-- The loadout write is restored before the case ends (rule R9). Run with the
-- WP-H-14 backend write shield on.

local MOD_ID = "character_weapon_variants"
local CAREER = "es_mercenary"
local SLOT = "slot_ranged"
local SEED_IDS = { "cwv_es_outrider_grenade_launcher_001", "cwv_es_outrider_grenade_launcher_000" }

-- Shared between run and cleanup; filled during run only.
local state = {}

local function unwrap()
    if state.unwrapped then return end
    state.unwrapped = true
    if state.create_game_object then
        GameSession.create_game_object = state.create_game_object
    end
    if state.spawner then
        if state.spawner_had_own then
            state.spawner.spawn_network_unit = state.spawn_network_unit
        else
            rawset(state.spawner, "spawn_network_unit", nil)
        end
    end
end

local function cleanup()
    unwrap()
    if state.cleaned then return end
    state.cleaned = true
    if state.equipped and state.original_id then
        pcall(BackendUtils.set_loadout_item, state.original_id, CAREER, SLOT)
        if state.inventory then
            pcall(state.inventory.create_equipment_in_slot, state.inventory, SLOT, state.original_id)
        end
    end
end

return {
    id = "cwv-a2f01-outrider-wire-name",
    issue = 0,
    class = "R",
    covers = "WP-CWV-01 RIG acceptance (A2-F01): the Outrider projectile game object carries the vanilla template index; the local shot keeps the #1320 grenade",
    arena = "keep",
    mods = { MOD_ID },
    timeout = 120,

    run = function(T)
        for k in pairs(state) do state[k] = nil end
        T.step("preconditions")
        T.require(get_mod(MOD_ID) ~= nil, "character_weapon_variants loaded")
        local weapons = rawget(_G, "Weapons")
        local template = type(weapons) == "table" and rawget(weapons, "outrider_grenade_launcher_template")
        T.require(type(template) == "table", "outrider_grenade_launcher_template built")
        local grenade_info = rawget(Projectiles, "cwv_outrider_grenade_projectile")
        T.require(type(grenade_info) == "table", "cwv grenade projectile config present")
        local donor_index = rawget(NetworkLookup.item_template_names, "dr_deus_01_template_1")
        T.require(type(donor_index) == "number", "vanilla dr_deus_01_template_1 index")
        T.note("donor_index", tostring(donor_index))
        T.note("clone_index", tostring(rawget(NetworkLookup.item_template_names, "outrider_grenade_launcher_template")))

        T.step("switch to Mercenary")
        Managers.state.network:request_profile(1, "empire_soldier", CAREER, true)
        local hero = T.wait_until(function()
            local player = Managers.player:local_player()
            local unit = player and player.player_unit
            if not (unit and Unit.alive(unit)) then return nil end
            local career = ScriptUnit.has_extension(unit, "career_system")
            return career and career:career_name() == CAREER and unit or nil
        end, 45, "Mercenary hero alive")
        T.require(hero ~= nil, "Mercenary hero alive")

        T.step("equip the Outrider seed")
        local items = Managers.backend:get_interface("items")
        local seed_id
        for i = 1, #SEED_IDS do
            if items:get_item_from_id(SEED_IDS[i]) ~= nil then seed_id = SEED_IDS[i]; break end
        end
        T.require(seed_id ~= nil, "Outrider seed item in the backend")
        T.note("seed_id", seed_id)
        local inventory = T.ext(hero, "inventory_system")
        local first_person = T.ext(hero, "first_person_system")
        state.original_id = BackendUtils.get_loadout_item_id(CAREER, SLOT)
        state.inventory = inventory
        T.note("original_id", tostring(state.original_id))
        BackendUtils.set_loadout_item(seed_id, CAREER, SLOT)
        state.equipped = true
        inventory:create_equipment_in_slot(SLOT, seed_id)
        T.frames(2)
        inventory:wield(SLOT)
        T.wait(1)
        local slot_data = inventory:get_slot_data(SLOT)
        -- Same identity read as the cwv projectile arm (_cwv_javelin_runtime_owner.lua).
        local master = slot_data and (slot_data.master_item or slot_data.item_data)
        local equipped_id = (master and master.backend_id) or (slot_data and slot_data.backend_id)
        local wielded = inventory:get_wielded_slot_name()
        T.note("wielded_slot", tostring(wielded))
        if equipped_id ~= seed_id or wielded ~= SLOT then cleanup() end
        T.require(wielded == SLOT, "slot_ranged wielded")
        T.require(equipped_id == seed_id, "seed equipped in slot_ranged")

        T.step("record the projectile spawn")
        local recorded = {}
        local spawner = Managers.state.unit_spawner
        state.create_game_object = GameSession.create_game_object
        state.spawner = spawner
        state.spawner_had_own = rawget(spawner, "spawn_network_unit") ~= nil
        state.spawn_network_unit = spawner.spawn_network_unit
        local original_create = state.create_game_object
        local original_spawn = state.spawn_network_unit
        GameSession.create_game_object = function(session, go_type, init_table, ...)
            recorded[#recorded + 1] = { go_type = go_type, init = init_table }
            return original_create(session, go_type, init_table, ...)
        end
        spawner.spawn_network_unit = function(self, ...)
            local unit, a, b = original_spawn(self, ...)
            recorded.unit = recorded.unit or unit
            return unit, a, b
        end

        T.step("fire without input")
        local a = template.actions.action_one.default
        local position, rotation = first_person:get_projectile_start_position_rotation()
        local fired, fire_err = pcall(ActionUtils.spawn_player_projectile, hero, position, rotation, 0,
            ActionUtils.pitch_from_rotation(rotation),
            Vector3.normalize(Vector3.flat(Quaternion.forward(rotation))), a.speed, "dr_deus_01",
            a.lookup_data.item_template_name, a.lookup_data.action_name, a.lookup_data.sub_action_name,
            false, 600)
        unwrap()
        T.note("fire", fired and "ok" or tostring(fire_err))

        local init
        for i = 1, #recorded do
            local row = recorded[i]
            if type(row.init) == "table" and row.init.item_template_name ~= nil then init = row.init; break end
        end
        local unit = recorded.unit
        local projectile = unit and Unit.alive(unit) and ScriptUnit.has_extension(unit, "projectile_system") or nil
        local projectile_ok = projectile ~= nil and projectile.projectile_info == grenade_info
        cleanup()
        T.require(fired, "projectile spawn call returned")
        T.require(init ~= nil, "projectile game object recorded")

        T.step("assert the wire and the local shot")
        T.expect_eq(init.item_template_name, donor_index,
            "wire item_template_name is the vanilla dr_deus_01_template_1 index")
        T.expect_eq(init.item_name, rawget(NetworkLookup.item_names, "dr_deus_01"),
            "wire item_name is the vanilla dr_deus_01 index")
        T.expect(projectile_ok, "local projectile_info is the cwv grenade config (#1320)")
        T.expect_rt(MOD_ID, "issue1320_outrider_projectile_unit_and_wire")
    end,

    cleanup = function()
        cleanup()
    end,
}
