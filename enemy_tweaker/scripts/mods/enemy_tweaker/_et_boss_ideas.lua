local mod = get_mod("enemy_tweaker")

-- #451 source-backed, bounded feasibility diagnostics. No spawn mutation.
local ET = mod._et
local Core = ET.BossIdeasCore
local CAP, captures = 2, 0

local BLOCKERS = {
    chosen_shield = "clone regular Chaos Warrior AI; validate shield inventory and shield event vocabulary",
    chosen_greataxe = "first prototype: regular Chaos Warrior AI plus boss model/inventory contract",
    stormfiend_ratlings = "strip Deathrattler mount and intro state before portable use",
    skaven_warlock = "replace Rasknitt mount and named-spawner dependencies",
    chaos_sorcerer = "replace Halescourge arena teleport/spawner queries",
    troll_chieftain = "strip oil sockets, objective writes, phase spawners, and arena flow events",
}

local function _risk(id)
    local actions = rawget(_G, "BreedActions") or {}
    if id == "stormfiend_ratlings" then
        local row = actions.skaven_stormfiend_boss
        return row and (row.mount_unit ~= nil or row.dual_shoot_intro ~= nil) or false
    elseif id == "skaven_warlock" then
        local row = actions.skaven_grey_seer
        return row and (row.mount_unit ~= nil or row.spawn_allies ~= nil) or false
    elseif id == "chaos_sorcerer" then
        local row = actions.chaos_exalted_sorcerer
        return row and (row.spawn_boss_vortex ~= nil or row.defensive_mode ~= nil
            or row.intro_idle ~= nil) or false
    elseif id == "troll_chieftain" then
        local downed = actions.chaos_troll_chief and actions.chaos_troll_chief.downed
        return downed and (downed.downed_chunk_events ~= nil
            or downed.upped_chunk_events ~= nil) or false
    end
    return false
end

local function _resident(unit_name)
    local app = rawget(_G, "Application")
    if not app or type(app.can_get) ~= "function" then return false end
    local ok, value = pcall(app.can_get, "unit", unit_name)
    return ok and value and true or false
end

local function _audit()
    local lookup = rawget(_G, "NetworkLookup")
    local result = Core.inspect({
        breeds = rawget(_G, "Breeds"),
        actions = rawget(_G, "BreedActions"),
        behaviors = rawget(_G, "BreedBehaviors"),
        inventories = rawget(_G, "InventoryConfigurations"),
        breed_lookup = lookup and lookup.breeds,
        unit_resident = _resident,
    })
    result.arena_risks = 0
    for _, row in ipairs(result.rows) do
        row.risk_present = _risk(row.id) and true or false
        row.blocker = BLOCKERS[row.id]
        if row.risk_present then result.arena_risks = result.arena_risks + 1 end
    end
    return result
end

local function _print_audit(reason)
    if captures >= CAP then return end
    captures = captures + 1
    local result = _audit()
    pcall(printf, "[et:451] audit=%d/%d reason=%s candidates=%d missing_breeds=%d structure_ready=%d resident_models=%d arena_risks=%d behavior_changes=0",
        captures, CAP, tostring(reason), #result.rows, result.missing_breeds,
        result.structure_ready, result.resident_models, result.arena_risks)
    for _, row in ipairs(result.rows) do
        pcall(printf, "[et:451] id=%s status=%s source=%s model=%s actions=%s behavior=%s inventory=%s wire=%s source_resident=%s model_resident=%s risk=%s blocker=%s",
            row.id, row.status, tostring(row.source_present), tostring(row.model_present),
            tostring(row.actions_present), tostring(row.behavior_present),
            tostring(row.inventory_present), tostring(row.wire_present),
            tostring(row.source_resident), tostring(row.model_resident),
            tostring(row.risk_present), row.blocker)
    end
    return result
end

ET.BOSS_IDEA_CANDIDATES = Core.CANDIDATES
ET.boss_ideas_audit = _audit

_print_audit("mod_load")

mod:command("et_boss_idea_audit", "Recheck boss prototype assets (#451)", function()
    local result = _print_audit("command")
    if result then
        mod:echo("[et:451] %d/6 structural contracts, %d/6 models resident; details in log",
            result.structure_ready, result.resident_models)
    else
        mod:echo("[et:451] audit capture limit reached; use the existing log rows")
    end
end)

ET.rt_register("issue451_boss_ideas_safely_decomposed", function()
    local result = _audit()
    if #result.rows ~= 6 then
        return string.format("candidate count drifted: got %d, expected 6", #result.rows)
    end
    if result.missing_breeds > 0 then
        return string.format("%d source/model breed keys missing", result.missing_breeds)
    end
    if result.structure_ready ~= 6 then
        return string.format("only %d/6 source contracts structurally ready", result.structure_ready)
    end
    if result.arena_risks < 4 then
        return string.format("only %d/4 arena-coupling markers remain; source re-audit required",
            result.arena_risks)
    end
end)

-- ============================================================
-- #451 first implementation slice: the greataxe Chosen prototype breed
-- ============================================================
-- The census above deterministically returned candidates=6 structure_ready=6
-- resident_models=0: every Bodvarr-MODEL concept is blocked on package
-- residency. The dictated first slice sidesteps that blocker entirely: clone
-- the regular `chaos_warrior` breed (model, AI, and its own two-handed
-- greataxe inventory are resident wherever Chaos enemies are), apply the
-- engine-free Core.apply_chosen_overrides policy (2000 HP flat, monster
-- stagger gate boss_staggers, display name), and walk the full
-- enemy_tweaker/DEVELOPMENT.md breed-adding checklist exactly like
-- _et_skaven_warlord_breed.lua (each step cites the snapshot it neutralizes).
--
-- EAGER-REGISTRATION DOCTRINE: one module-load declarative transaction through
-- the #1413 registrar, safe when the mod is VMF-disabled (DEVELOPMENT.md).
-- The ONLY spawn surface is the test-only host command /et_spawn_chosen and
-- gt's Creature Spawner (#454 enumerates live Breeds). No pool integration.
--
-- NETWORK FLOOR (#451B): a dedicated exact channel fingerprints both ET breed
-- names, their registrar semantics, and all three numeric ids. The command
-- refuses without positive pre-ack; both ConflictDirector spawn surfaces also
-- substitute the validated vanilla donor if another caller bypasses it.
--
-- PACKAGE RESIDENCY POLICY (explicit): EnemyPackageLoaderSettings.alias_to_breed
-- resolves the clone to chaos_warrior (enemy_package_loader.lua:189/:263), and
-- the spawn command REFUSES unless is_breed_processed("et_chosen_greataxe")
-- reports the chaos_warrior package already resident on this mission — we
-- never trigger a dynamic per-breed package load whose bundle existence for
-- an always-startup breed is [unverified].
local Registrar = ET.CustomBreedRegistrar
local Identity = ET.CustomBreedIdentity
local CHOSEN = Core.CHOSEN
local CHOSEN_BREED = CHOSEN.name

local function _chosen_log(fmt, ...)
    if not pcall(printf, "[et:451] " .. fmt, ...) then
        pcall(printf, "[et:451] (log format error: %s)", tostring(fmt))
    end
end

-- The same declarative registrar owns the Chosen and Warlord surfaces.  This
-- owner contributes only policy: clone overrides, an exact reload signature,
-- one ephemeral localization row, and its public readiness flag.
local _source = rawget(rawget(_G, "Breeds") or {}, CHOSEN.source_breed)
local _source_fields = {
    "boss", "elite", "threat_value", "infighting", "category_mask",
    "run_on_spawn", "run_on_death", "run_on_despawn",
}
local _source_nil = {}
local _source_before = nil
if type(_source) == "table" then
    _source_before = {}
    for i = 1, #_source_fields do
        local value = rawget(_source, _source_fields[i])
        _source_before[i] = value == nil and _source_nil or value
    end
end

local function _conflict_method(name)
    local managers = rawget(_G, "Managers")
    local conflict = managers and managers.state and managers.state.conflict
    local method = type(conflict) == "table" and conflict[name]
    if type(method) ~= "function" then
        error("chosen_conflict_method_missing:" .. name, 0)
    end
    return method, conflict
end

local _breed_utils = rawget(_G, "BreedUtils")
local _inject_breed_category_mask = type(_breed_utils) == "table"
    and _breed_utils.inject_breed_category_mask or nil
local chosen_services = {
    boss_infighting = rawget(rawget(_G, "InfightingSettings") or {}, "boss"),
    inject_breed_category_mask = function(breed)
        if type(_inject_breed_category_mask) ~= "function" then
            error("BreedUtils.inject_breed_category_mask missing", 0)
        end
        return _inject_breed_category_mask(breed)
    end,
    add_boss = function(unit)
        local method, conflict = _conflict_method("add_unit_to_bosses")
        return method(conflict, unit)
    end,
    add_angry = function(_, blackboard)
        local method, conflict = _conflict_method("add_angry_boss")
        return method(conflict, 1, blackboard)
    end,
    remove_boss = function(unit)
        local method, conflict = _conflict_method("remove_unit_from_bosses")
        return method(conflict, unit)
    end,
    remove_angry = function()
        local method, conflict = _conflict_method("add_angry_boss")
        return method(conflict, -1)
    end,
}

mod._et_chosen_ready = false
local chosen_ok, chosen_reason = Registrar.register({
    owner = "enemy_tweaker.chosen_greataxe",
    name = CHOSEN_BREED,
    source_breed = CHOSEN.source_breed,
    race = "chaos",
    fingerprint = assert(Identity.fingerprint_for(CHOSEN_BREED),
        "missing Chosen registrar fingerprint"),
    configure = function(breed)
        local configured, reason = Core.apply_chosen_overrides(
            breed, CHOSEN, chosen_services)
        if not configured then error(reason, 0) end
    end,
    validate_breed = function(breed, source)
        if breed.display_name ~= CHOSEN.display_name_key
            or breed.default_inventory_template ~= CHOSEN.inventory_template
            or breed.boss ~= true or breed.elite ~= nil
            or breed.boss_staggers ~= true
            or breed.show_health_bar ~= true
            or breed.far_off_despawn_immunity ~= true
            or breed.threat_value ~= CHOSEN.threat_value
            or type(breed.infighting) ~= "table"
            or type(breed.category_mask) ~= "number"
            or type(breed.max_health) ~= "table"
            or type(breed.run_on_spawn) ~= "function"
            or type(breed.run_on_death) ~= "function"
            or type(breed.run_on_despawn) ~= "function" then
            return nil, "chosen_override_mismatch"
        end
        if type(source) ~= "table" or breed.run_on_spawn == source.run_on_spawn
                or breed.run_on_death == source.run_on_death
                or breed.run_on_despawn == source.run_on_despawn then
            return nil, "chosen_lifecycle_wrapper_mismatch"
        end
        for i = 1, 8 do
            if breed.max_health[i] ~= 2000 then return nil, "chosen_health_mismatch" end
        end
        local captured_mask = breed.category_mask
        local category_ok = pcall(chosen_services.inject_breed_category_mask, breed)
        if not category_ok or breed.category_mask ~= captured_mask then
            return nil, "chosen_category_mask_stale"
        end
        return true
    end,
    presentations = {
        { target = mod._et_warlord2_loc_strings,
            key = CHOSEN.display_name_key, value = CHOSEN.display_name_en,
            ephemeral = true },
    },
    readiness = {
        { target = mod, key = "_et_chosen_ready", value = true },
    },
})
if chosen_ok then
    _chosen_log("breed %s %s through atomic registrar (source=%s; inventory=%s)",
        CHOSEN_BREED, tostring(chosen_reason), CHOSEN.source_breed,
        tostring(CHOSEN.inventory_template))
else
    _chosen_log("ALERT: Chosen registration rejected (%s) — prototype unavailable this session",
        tostring(chosen_reason))
end

ET.rt_register("issue1413_atomic_custom_breed_registration", function()
    local ok, reason = Registrar.validate_all_registered()
    if not ok then return tostring(reason) end
end)

-- Test-only spawn command (host, in-mission, residency-gated). Spawns ONE
-- Chosen at the local player's feet (player position is nav-valid; POSITION_
-- LOOKUP is stale for the local player in chat phase, so read live via
-- Unit.world_position) facing the player. Uses the vanilla queued spawn path
-- (conflict_director.lua:1732) exactly like vanilla debug spawns (:2639,
-- spawn_category "debug_spawn").
mod:command("et_spawn_chosen", "Spawn the greataxe Chosen prototype (#451 test only, host)", function()
    local player_manager = Managers.player
    if not (player_manager and player_manager.is_server) then
        mod:echo("[et:451] host only: the Chosen spawn is server-authoritative")
        return
    end
    local conflict = Managers.state and Managers.state.conflict
    if not conflict or not conflict.spawn_queued_unit then
        mod:echo("[et:451] no active mission")
        return
    end
    local Breeds_t = rawget(_G, "Breeds")
    if not mod._et_chosen_ready or not (Breeds_t and Breeds_t[CHOSEN_BREED]) then
        mod:echo("[et:451] Chosen breed not registered this session (see log)")
        return
    end
    local epl = conflict.enemy_package_loader
    local resident = epl and epl.is_breed_processed
        and epl:is_breed_processed(CHOSEN_BREED)
    if not resident then
        mod:echo("[et:451] Chaos Warrior package is not loaded on this mission - use a mission that has Chaos enemies")
        return
    end
    local exact_safe = type(ET.custom_breeds_exact_safe) == "function"
        and ET.custom_breeds_exact_safe()
    if exact_safe ~= true then
        mod:echo("[et:451] Chosen spawn blocked: every human peer must pre-ack the exact Enemy Tweaker custom-breed identity")
        return
    end
    local player = player_manager:local_player()
    local unit = player and player.player_unit
    if not unit or not Unit.alive(unit) then
        mod:echo("[et:451] no live local hero unit")
        return
    end
    local pos = Unit.world_position(unit, 0)
    local rot = Unit.world_rotation(unit, 0)
    local face_player = Quaternion.multiply(rot, Quaternion(Vector3.up(), math.pi))
    conflict:spawn_queued_unit(Breeds_t[CHOSEN_BREED], Vector3Box(pos),
        QuaternionBox(face_player), "debug_spawn", nil, nil, {})
    _chosen_log("spawn queued at player position (test command)")
    mod:echo("[et:451] Chosen queued after exact peer/catalog confirmation.")
end)

ET.rt_register("issue451_chosen_greataxe_prototype", function()
    if not mod._et_chosen_ready then
        return "Chosen breed not registered (see [et:451] ALERT rows)"
    end
    local breeds = rawget(_G, "Breeds")
    local breed = breeds and breeds[CHOSEN_BREED]
    if type(breed) ~= "table" then return "published breed missing from Breeds" end
    if breed.boss ~= true or breed.elite ~= nil then
        return "Chosen is not classified exclusively as a boss"
    end
    if breed.boss_staggers ~= true then return "monster stagger policy missing" end
    if breed.show_health_bar ~= true then return "boss health bar missing" end
    if breed.far_off_despawn_immunity ~= true then return "far-despawn immunity missing" end
    if breed.threat_value ~= 32 then return "boss threat value drifted" end
    local infighting = rawget(rawget(_G, "InfightingSettings") or {}, "boss")
    if type(infighting) == "table" and not rawequal(breed.infighting, infighting) then
        return "boss infighting policy drifted"
    end
    local category_before = breed.category_mask
    local probe_ok = pcall(chosen_services.inject_breed_category_mask, breed)
    if not probe_ok or breed.category_mask ~= category_before then
        return "breed category mask is stale"
    end
    if type(breed.max_health) ~= "table" or breed.max_health[1] ~= 2000
            or breed.max_health[8] ~= 2000 then
        return "2000 HP stat block drifted"
    end
    if breed.default_inventory_template ~= CHOSEN.inventory_template then
        return "greataxe inventory template drifted"
    end
    local inventories = rawget(_G, "InventoryConfigurations")
    if inventories and type(inventories[CHOSEN.inventory_template]) ~= "table" then
        return "inventory template missing from InventoryConfigurations"
    end
    local src = breeds[CHOSEN.source_breed]
    if type(src) == "table" and _source_before then
        for i = 1, #_source_fields do
            local key = _source_fields[i]
            local value = _source_before[i]
            if value == _source_nil then value = nil end
            if rawget(src, key) ~= value then
                return "vanilla chaos_warrior mutated at " .. tostring(key)
            end
        end
    end
    local actions = rawget(_G, "BreedActions")
    if actions and type(actions[CHOSEN_BREED]) ~= "table" then
        return "BreedActions clone missing"
    end
    local nl = rawget(_G, "NetworkLookup")
    for _, table_name in ipairs({ "breeds", "damage_sources", "statistics_path_names" }) do
        local lookup = nl and rawget(nl, table_name)
        local idx = lookup and rawget(lookup, CHOSEN_BREED)
        if type(idx) ~= "number" or rawget(lookup, idx) ~= CHOSEN_BREED then
            return "wire pair asymmetric or missing in NetworkLookup." .. table_name
        end
    end
    local elites = rawget(_G, "ELITES")
    if type(elites) == "table" and rawget(elites, CHOSEN_BREED) ~= nil then
        return "Chosen leaked into ELITES"
    end
    local epls = rawget(_G, "EnemyPackageLoaderSettings")
    if not epls or epls.alias_to_breed[CHOSEN_BREED] ~= CHOSEN.source_breed then
        return "package alias to chaos_warrior missing"
    end
    local sd = rawget(_G, "StatisticsDefinitions")
    local sd_player = sd and sd.player
    if sd_player and not (sd_player.kills_per_breed[CHOSEN_BREED]
            and sd_player.damage_dealt_per_breed[CHOSEN_BREED]) then
        return "per-breed statistics seeds missing"
    end
end)
