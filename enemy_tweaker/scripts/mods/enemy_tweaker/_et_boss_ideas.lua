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
-- EAGER-REGISTRATION DOCTRINE: module-level direct table writes, pcall
-- bracketed, safe when the mod is VMF-disabled (DEVELOPMENT.md "Lessons").
-- The ONLY spawn surface is the test-only host command /et_spawn_chosen and
-- gt's Creature Spawner (#454 enumerates live Breeds). No pool integration.
--
-- NETWORK / UNMODDED-CLIENT CONSTRAINT: same as the Skaven Warlord — the
-- breed name joins NetworkLookup.breeds and .damage_sources, so EVERY peer
-- must have enemy_tweaker INSTALLED (enabled or not) before this spawns.
--
-- PACKAGE RESIDENCY POLICY (explicit): EnemyPackageLoaderSettings.alias_to_breed
-- resolves the clone to chaos_warrior (enemy_package_loader.lua:189/:263), and
-- the spawn command REFUSES unless is_breed_processed("et_chosen_greataxe")
-- reports the chaos_warrior package already resident on this mission — we
-- never trigger a dynamic per-breed package load whose bundle existence for
-- an always-startup breed is [unverified].
local NLLib = ET.NetworkLookupLib
local CHOSEN = Core.CHOSEN
local CHOSEN_BREED = CHOSEN.name

local function _chosen_log(fmt, ...)
    if not pcall(printf, "[et:451] " .. fmt, ...) then
        pcall(printf, "[et:451] (log format error: %s)", tostring(fmt))
    end
end

-- A previously published breed survives VMF hot reload, while the mod object
-- (including readiness fields) does not.  Re-run the strict lookup proof on
-- every entry and only republish readiness after both identities pass.
local function _register_chosen_wire_identity()
    local nl = rawget(_G, "NetworkLookup")
    if type(nl) ~= "table" then
        _chosen_log("ALERT: NetworkLookup unavailable — Chosen NOT registered")
        return false
    end
    local _, b_ins, b_reason = NLLib.register_named(nl, "breeds", CHOSEN_BREED)
    if not b_ins and b_reason ~= "already_registered" then
        _chosen_log("ALERT: NetworkLookup.breeds registration failed (%s) — Chosen NOT registered", tostring(b_reason))
        return false
    end
    local _, d_ins, d_reason = NLLib.register_named(nl, "damage_sources", CHOSEN_BREED)
    if not d_ins and d_reason ~= "already_registered" then
        _chosen_log("ALERT: NetworkLookup.damage_sources registration failed (%s) — Chosen NOT registered", tostring(d_reason))
        return false
    end
    return true
end

local function _register_chosen()
    mod._et_chosen_ready = false
    local Breeds_t = rawget(_G, "Breeds")
    local BreedActions_t = rawget(_G, "BreedActions")
    if type(Breeds_t) ~= "table" or type(BreedActions_t) ~= "table" then
        _chosen_log("Breeds/BreedActions not loaded — Chosen registration skipped")
        return false
    end
    if Breeds_t[CHOSEN_BREED] then
        if not _register_chosen_wire_identity() then return false end
        mod._et_chosen_ready = true
        _chosen_log("breed %s revalidated on hot reload", CHOSEN_BREED)
        return true
    end
    local src = Breeds_t[CHOSEN.source_breed]
    if type(src) ~= "table" then
        _chosen_log("source breed %s missing — Chosen registration skipped", CHOSEN.source_breed)
        return false
    end

    -- 1. Deep copy (table.clone recurses subtables, functions by reference —
    -- foundation/scripts/util/table.lua:31-48) + engine-free override policy.
    local ok, breed = pcall(table.clone, src)
    if not ok or type(breed) ~= "table" then
        _chosen_log("ALERT: table.clone(%s) failed: %s — Chosen NOT registered",
            CHOSEN.source_breed, tostring(breed))
        return false
    end
    Core.apply_chosen_overrides(breed, CHOSEN)

    -- 2. NetworkLookup.breeds + damage_sources FIRST and fail-closed (shared
    -- lib guard patterns): both carry a strict __index metatable
    -- (network_lookup.lua:2360-2367) and AI melee resolves the breed name as
    -- a damage_source (ai_utils.lua:266 -> damage_utils.lua:1839). A failed
    -- or asymmetric wire pair aborts the whole registration so a
    -- spawnable-but-unwired breed can never exist. [unverified] headroom of
    -- the damage_source_id network type above the vanilla count — one
    -- appended entry assumed within budget, same as the Skaven Warlord.
    if not _register_chosen_wire_identity() then return false end

    -- 3. BreedActions clone (checklist step 5).
    if BreedActions_t[CHOSEN.source_breed] and not BreedActions_t[CHOSEN_BREED] then
        local a_ok, actions = pcall(table.clone, BreedActions_t[CHOSEN.source_breed])
        if a_ok and type(actions) == "table" then
            BreedActions_t[CHOSEN_BREED] = actions
        else
            _chosen_log("ALERT: BreedActions clone failed: %s", tostring(actions))
        end
    end

    -- 4. threat_values upvalue (checklist step 1; conflict_director.lua ~2297
    -- boot snapshot, nil*amount crash at live 2479 without it).
    local CD = rawget(_G, "ConflictDirector")
    if CD and CD.set_threat_value then
        CD.set_threat_value(nil, CHOSEN_BREED, breed.threat_value or 0)
    else
        _chosen_log("ALERT: ConflictDirector.set_threat_value unavailable — threat value NOT seeded")
    end

    -- 5. StatisticsDefinitions per-breed seeds (checklist step 2; vanilla loop
    -- statistics_definitions.lua:615-657 runs at file load only; every entry
    -- carries `name` per statistics_database.lua:102 live).
    local sd = rawget(_G, "StatisticsDefinitions")
    local player = sd and sd.player
    if player and player.kills_per_breed then
        player.kills_per_breed[CHOSEN_BREED] = {
            sync_on_hot_join = true, value = 0, name = CHOSEN_BREED,
        }
        player.kills_per_breed_persistent[CHOSEN_BREED] = {
            source = "player_data", value = 0, name = CHOSEN_BREED,
            database_name = "kills_per_breed_persistent_" .. CHOSEN_BREED,
        }
        player.kill_assists_per_breed[CHOSEN_BREED] = { value = 0, name = CHOSEN_BREED }
        player.damage_dealt_per_breed[CHOSEN_BREED] = { value = 0, name = CHOSEN_BREED }
        -- kills_per_race: race "chaos" already seeded at boot
        -- (statistics_definitions.lua:637-642 guard).
        player.kills_per_breed_difficulty[CHOSEN_BREED] = {}
        player.kill_assists_per_breed_difficulty[CHOSEN_BREED] = {}
        local diffs = rawget(_G, "DifficultySettings")
        if diffs then
            for difficulty_name in pairs(diffs) do
                player.kills_per_breed_difficulty[CHOSEN_BREED][difficulty_name] = {
                    value = 0, name = CHOSEN_BREED .. "_" .. difficulty_name,
                }
                player.kill_assists_per_breed_difficulty[CHOSEN_BREED][difficulty_name] = {
                    value = 0, name = CHOSEN_BREED .. "_" .. difficulty_name,
                }
            end
        end
    else
        _chosen_log("ALERT: StatisticsDefinitions.player unavailable — per-breed stats NOT seeded")
    end

    -- 6. PerformanceManager belt (checklist step 3; _activated_per_breed is
    -- rebuilt from pairs(Breeds) in init at level start, performance_manager
    -- .lua:84-88 — seed any already-live instance for hot-reload edges).
    local mgrs = rawget(_G, "Managers")
    local perf = mgrs and mgrs.state and mgrs.state.performance
    if perf and type(perf._activated_per_breed) == "table" then
        perf._activated_per_breed[CHOSEN_BREED] = perf._activated_per_breed[CHOSEN_BREED] or 0
    end

    -- 7. Package alias (enemy_package_loader_settings.lua:188-199 pattern;
    -- loader resolves ALIAS_TO_BREED at :189/:263/:955): the clone rides the
    -- chaos_warrior package. See PACKAGE RESIDENCY POLICY above.
    local epls = rawget(_G, "EnemyPackageLoaderSettings")
    if epls and type(epls.alias_to_breed) == "table" then
        epls.alias_to_breed[CHOSEN_BREED] = CHOSEN.source_breed
        local bta = epls.breed_to_aliases
        if type(bta) == "table" then
            bta[CHOSEN.source_breed] = bta[CHOSEN.source_breed] or {}
            local aliases = bta[CHOSEN.source_breed]
            local present = false
            for i = 1, #aliases do
                if aliases[i] == CHOSEN_BREED then present = true break end
            end
            if not present then aliases[#aliases + 1] = CHOSEN_BREED end
        end
    else
        _chosen_log("ALERT: EnemyPackageLoaderSettings unavailable — package alias NOT registered")
    end

    -- 8. Dismemberments share (boot loop hit_reactions_template_compiler
    -- .lua:174-189; consumer indexes UNGUARDED at
    -- generic_hit_reaction_extension.lua:544-545). Identical hit zones.
    local dis = rawget(_G, "Dismemberments")
    if dis and dis[CHOSEN.source_breed] and not dis[CHOSEN_BREED] then
        dis[CHOSEN_BREED] = dis[CHOSEN.source_breed]
    end

    -- 9. CHAOS race set (breeds.lua:75 + :329-330 boot loop).
    local chaos_set = rawget(_G, "CHAOS")
    if type(chaos_set) == "table" then
        chaos_set[CHOSEN_BREED] = true
    end

    -- 10. BreedHitZonesLookup mirror (breeds.lua:24/112; runtime writer
    -- damage_utils.lua:1725 keys by breed name).
    local bhzl = rawget(_G, "BreedHitZonesLookup")
    if type(bhzl) == "table" and not bhzl[CHOSEN_BREED] and breed.hit_zones_lookup then
        bhzl[CHOSEN_BREED] = breed.hit_zones_lookup
    end

    -- 11. Display name: ride the mod's single _G.Localize hook (owned by
    -- _et_skaven_warlord_breed.lua, loaded earlier in the manifest — a second
    -- hook on the same pair would be VMF-dropped). Contents are read per call.
    if type(mod._et_warlord2_loc_strings) == "table" then
        mod._et_warlord2_loc_strings[CHOSEN.display_name_key] = CHOSEN.display_name_en
    else
        _chosen_log("ALERT: Localize string table unavailable — Chosen name renders as raw key")
    end

    -- FINAL: publish only after every step above succeeded or logged a
    -- degraded-but-safe ALERT. Presence in Breeds is the spawn go/no-go.
    Breeds_t[CHOSEN_BREED] = breed
    mod._et_chosen_ready = true
    _chosen_log("breed %s registered (clone of %s; 2000 HP flat, boss_staggers, inventory=%s)",
        CHOSEN_BREED, CHOSEN.source_breed, tostring(breed.default_inventory_template))
    return true
end

local _chosen_ok, _chosen_err = pcall(_register_chosen)
if not _chosen_ok then
    _chosen_log("ALERT: Chosen registration errored: %s — prototype unavailable this session", tostring(_chosen_err))
end

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
    mod:echo("[et:451] Chosen queued. Reminder: every player in the lobby must have Enemy Tweaker installed.")
end)

ET.rt_register("issue451_chosen_greataxe_prototype", function()
    if not mod._et_chosen_ready then
        return "Chosen breed not registered (see [et:451] ALERT rows)"
    end
    local breeds = rawget(_G, "Breeds")
    local breed = breeds and breeds[CHOSEN_BREED]
    if type(breed) ~= "table" then return "published breed missing from Breeds" end
    if breed.boss_staggers ~= true then return "monster stagger policy missing" end
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
    if type(src) == "table" and src.boss_staggers then
        return "vanilla chaos_warrior mutated: boss_staggers leaked to the source breed"
    end
    local actions = rawget(_G, "BreedActions")
    if actions and type(actions[CHOSEN_BREED]) ~= "table" then
        return "BreedActions clone missing"
    end
    local nl = rawget(_G, "NetworkLookup")
    for _, table_name in ipairs({ "breeds", "damage_sources" }) do
        local lookup = nl and rawget(nl, table_name)
        local idx = lookup and rawget(lookup, CHOSEN_BREED)
        if type(idx) ~= "number" or rawget(lookup, idx) ~= CHOSEN_BREED then
            return "wire pair asymmetric or missing in NetworkLookup." .. table_name
        end
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
