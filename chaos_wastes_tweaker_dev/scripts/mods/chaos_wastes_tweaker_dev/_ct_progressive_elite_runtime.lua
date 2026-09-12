-- _ct_progressive_elite_runtime.lua -- host-authoritative progressive elite
-- enhancement owner (#323). Default-off.
--
-- Owns the single CT hook on (ConflictDirector, _post_spawn_unit). Fresh spawns
-- and breed-freezer reuse both finish there [src: conflict_director.lua:1859-1868,
-- 2024]. The hook runs vanilla FIRST, so every vanilla writer has already chosen
-- and applied its list: pre-spawn terror events and cursed chests
-- [src: terror_event_utils.lua:182-203], Geheimnisnacht Hard Mode's in-pass append
-- [src: mutator_geheimnisnacht_2021_hard_mode.lua:125-155], and vanilla's own
-- `apply_breed_enhancements` call [src: conflict_director.lua:2034-2041]. CT then
-- marks a still-unmarked ordinary elite through that same vanilla function.
--
-- CT never writes the spawn's `optional_data`. One table is shared by every unit
-- of a horde [src: horde_spawner.lua:1236-1242] and the enemy recycler re-spawns
-- units from the stored table [src: enemy_recycler.lua:662,708], so a list left
-- there would mark later horde trash and re-marked respawns. The marks go through
-- a private per-unit table instead, which also carries the grudge name index
-- vanilla would otherwise draw from the terror-event RNG
-- [src: terror_event_utils.lua:80-84]. Selection is a pure hash of the spawn
-- queue id and breed name, so the option consumes no gameplay RNG.
--
-- Wire safety: the marks reach clients only through vanilla identities. Buffs go
-- through BuffSystem.add_buff -> rpc_add_buff keyed by NetworkLookup.buff_templates
-- and replay on hot join [src: buff_system.lua:66-96, 277-310;
-- network_lookup.lua:1144-1146]; attributes go through AISystem.set_attribute ->
-- rpc_set_attribute_* keyed by NetworkLookup.attributes, seeded from
-- BreedEnhancements at boot and replayed on hot join [src: ai_system.lua:76-80,
-- 1592-1612, 1654-1686; network_lookup.lua:2287-2294]. No mod-defined lookup
-- entry is involved and clients need no CT for the enhancement to render.
--
-- Owned by: chaos_wastes_tweaker_dev.lua entry point (installed before
-- _ct_progressive_elite_audit, which attaches through state.add_observer).
-- Guarded by qa/lua/tests/test_ct_progressive_elite_runtime_owner.lua and the
-- /ct_regression_test check `issue323_progressive_elite_runtime`.
return function(ctx)
    assert(type(ctx) == "table", "CT progressive elite runtime requires context")
    local mod = assert(ctx.mod, "CT progressive elite runtime requires mod")
    local effective_setting = assert(ctx.effective_setting,
        "CT progressive elite runtime requires effective_setting")
    -- Engine seams default to the live game; tests inject doubles. The entry
    -- passes only mod + effective_setting (it sits at the 200-local ceiling).
    local Policy = ctx.policy or (type(mod.dofile) == "function"
        and mod:dofile("scripts/mods/chaos_wastes_tweaker_dev/_ct_progressive_elite_policy"))
    assert(type(Policy) == "table", "CT progressive elite runtime requires policy")
    local function managers()
        return rawget(_G, "Managers")
    end
    local is_server = ctx.is_server or function()
        local live = managers()
        return (live and live.player and live.player.is_server) == true
    end
    -- Depth exactly as _ct_progressive_elite_audit resolves it; nil outside a
    -- Deus run so nothing is ever selected in Adventure or the keep.
    local completed_level_count = ctx.completed_level_count or function()
        local live = managers()
        local manager = live and live.mechanism
        local mechanism = manager and manager.game_mechanism and manager:game_mechanism()
        local controller = mechanism and mechanism.get_deus_run_controller
            and mechanism:get_deus_run_controller()
        return controller and controller.get_completed_level_count
            and controller:get_completed_level_count() or nil
    end
    -- Per-unit truth: vanilla's apply writes grudge_marked.name_index before any
    -- buff [src: terror_event_utils.lua:80-84]. A freezer-reused unit keeps an
    -- emptied category table, so presence of the key, not the table, decides
    -- [src: ai_system.lua:648-664, 1574-1590].
    local already_marked = ctx.already_marked or function(ai_unit)
        local live = managers()
        local entity = live and live.state and live.state.entity
        local ai_system = entity and entity:system("ai_system")
        local attributes = ai_system and ai_system:get_attributes(ai_unit)
        local marked = type(attributes) == "table" and attributes.grudge_marked or nil
        return type(marked) == "table" and marked.name_index ~= nil
    end
    -- Resolved at call time so CT's grudge-mark filter hook
    -- (_ct_boss_grudge_marks.lua) and any other mod's wrapper still run.
    local apply_enhancements = ctx.apply_enhancements or function(ai_unit, breed, data)
        return TerrorEventUtils.apply_breed_enhancements(ai_unit, breed, data)
    end
    local templates = ctx.templates or function()
        return rawget(_G, "BreedEnhancements")
    end
    local log = ctx.log or function(fmt, ...)
        pcall(printf, fmt, ...)
    end

    -- Idempotent: a second install never registers a second hook.
    if mod._ct_progressive_elite_runtime_state then
        return mod._ct_progressive_elite_runtime_state
    end

    local state = {
        installed = true,
        hook_pair = "ConflictDirector._post_spawn_unit",
        setting_id = "progressive_elite_enhancements",
        step_setting_id = "progressive_elite_step_percent",
        applied = 0,
        preserved = 0,
        no_identity = 0,
        errors = 0,
        log_rows = 0,
        LOG_CAP = 12,
        ERROR_CAP = 4,
        observers = {},
        last_error = nil,
    }
    mod._ct_progressive_elite_runtime_state = state

    local function enabled()
        return effective_setting(state.setting_id) == true
    end

    local function step()
        return Policy.clamp_step(effective_setting(state.step_setting_id))
    end

    state.enabled = enabled
    state.step = step
    state.activation = function()
        return enabled() and "enabled" or "disabled"
    end
    state.rate_label = function()
        return Policy.rate_label(step())
    end
    state.add_observer = function(fn)
        if type(fn) == "function" then
            state.observers[#state.observers + 1] = fn
        end
    end

    local function record_error(kind, err)
        state.errors = state.errors + 1
        state.last_error = tostring(err)
        if state.errors <= state.ERROR_CAP then
            log("[ct:323] %s %d/%d err=%s", kind, state.errors, state.ERROR_CAP, tostring(err))
        end
    end

    -- Decision only; it reads the spawn payload but never writes it.
    local function select_for(ai_unit, breed, optional_data, spawn_queue_id)
        if not is_server() then return nil end
        if not enabled() then return nil end
        if Policy.classify_breed(breed) ~= "elite" then return nil end
        if (type(optional_data) == "table" and optional_data.enhancements ~= nil)
                or already_marked(ai_unit) then
            -- A vanilla writer already marked this unit. Never stack onto it.
            state.preserved = state.preserved + 1
            return nil
        end
        local depth = completed_level_count()
        if type(depth) ~= "number" then return nil end
        if type(spawn_queue_id) ~= "number" then
            state.no_identity = state.no_identity + 1
            return nil
        end
        local list, recipe = Policy.enhancements_for_spawn(spawn_queue_id, breed, depth,
            templates(), step())
        return list, recipe, depth
    end

    local function pack(...)
        return select("#", ...), { ... }
    end

    -- hook-test: issue323_progressive_elite_runtime
    -- _ct_consolidated_post_spawn_unit_hook (singleton for this (Class, method)).
    mod:hook("ConflictDirector", "_post_spawn_unit", function(func, self, ai_unit, go_id,
            breed, spawn_pos, spawn_category, spawn_animation, optional_data,
            spawn_type, spawn_queue_id, ...)
        -- Vanilla always runs first, with every argument and return value preserved.
        local count, results = pack(func(self, ai_unit, go_id, breed, spawn_pos,
            spawn_category, spawn_animation, optional_data, spawn_type, spawn_queue_id, ...))
        local applied_recipe
        local ok, list, recipe, depth = pcall(select_for, ai_unit, breed, optional_data,
            spawn_queue_id)
        if ok and list then
            local private_data = {
                enhancements = list,
                name_index = Policy.name_index(spawn_queue_id, breed.name),
            }
            local applied_ok, apply_err = pcall(apply_enhancements, ai_unit, breed, private_data)
            if applied_ok then
                applied_recipe = recipe
                state.applied = state.applied + 1
                if state.log_rows < state.LOG_CAP then
                    state.log_rows = state.log_rows + 1
                    log("[ct:323] apply %d/%d breed=%s recipe=%s spawn=%s completed=%d rate=%d",
                        state.log_rows, state.LOG_CAP, tostring(breed.name),
                        tostring(recipe), tostring(spawn_queue_id), depth,
                        Policy.rate(depth, step()))
                end
            else
                record_error("apply_error", apply_err)
            end
        elseif not ok then
            record_error("select_error", list)
        end
        local observers = state.observers
        for i = 1, #observers do
            pcall(observers[i], breed, spawn_queue_id, applied_recipe, optional_data)
        end
        return unpack(results, 1, count)
    end)

    if type(mod._ct_rt_register) == "function" then
        mod._ct_rt_register("issue323_progressive_elite_runtime", function()
            local conflict_director = rawget(_G, "ConflictDirector")
            if type(conflict_director) ~= "table"
                    or type(conflict_director._post_spawn_unit) ~= "function" then
                return "ConflictDirector._post_spawn_unit seam missing"
            end
            local terror_event_utils = rawget(_G, "TerrorEventUtils")
            if type(terror_event_utils) ~= "table"
                    or type(terror_event_utils.apply_breed_enhancements) ~= "function" then
                return "TerrorEventUtils.apply_breed_enhancements seam missing"
            end
            local ai_system = rawget(_G, "AISystem")
            if type(ai_system) ~= "table" or type(ai_system.get_attributes) ~= "function" then
                return "AISystem.get_attributes seam missing"
            end
            local catalog = templates()
            if type(catalog) ~= "table" then
                return "BreedEnhancements catalog missing"
            end
            if type(catalog[Policy.BASE_RECIPE]) ~= "table" then
                return "elite_base template missing"
            end
            if #Policy.ELITE_RECIPES ~= 2 then
                return "elite allowlist drift: " .. tostring(#Policy.ELITE_RECIPES)
            end
            local boss_marks = rawget(_G, "BossGrudgeMarks")
            for _, name in ipairs(Policy.ELITE_RECIPES) do
                if type(catalog[name]) ~= "table" then
                    return "elite recipe template missing: " .. name
                end
                if type(boss_marks) == "table" and boss_marks[name] then
                    return "allowlist entry is a boss grudge mark: " .. name
                end
            end
            local elite = { elite = true, name = "chaos_warrior" }
            local special = { special = true, name = "skaven_gutter_runner" }
            local monster = { boss = true, elite = true, name = "chaos_troll" }
            local trash = { name = "skaven_slave" }
            for depth = 0, Policy.MAX_STEPS + 2 do
                for roll = 0, 99 do
                    for pick = 1, #Policy.ELITE_RECIPES do
                        local list, recipe = Policy.enhancements_for(depth, roll, elite,
                            pick, catalog)
                        if list then
                            if not Policy.is_elite_recipe(recipe) then
                                return "non-allowlisted recipe selected: " .. tostring(recipe)
                            end
                            if list[1] ~= catalog[Policy.BASE_RECIPE]
                                    or list[2] ~= catalog[recipe] or #list ~= 2 then
                                return "recipe shape drift for " .. tostring(recipe)
                            end
                            if roll >= Policy.rate(depth) then
                                return "selection above the depth rate"
                            end
                        elseif roll < Policy.rate(depth) then
                            return "selection missing below the depth rate"
                        end
                        if Policy.enhancements_for(depth, roll, special, pick, catalog) then
                            return "special breed selected"
                        end
                        if Policy.enhancements_for(depth, roll, monster, pick, catalog) then
                            return "monster breed selected"
                        end
                        if Policy.enhancements_for(depth, roll, trash, pick, catalog) then
                            return "trash breed selected"
                        end
                    end
                end
            end
            if Policy.rate_label(Policy.DEFAULT_STEP_PERCENT) ~= "0/5/10/15/20" then
                return "default rate table drift: " .. Policy.rate_label(Policy.DEFAULT_STEP_PERCENT)
            end
            if Policy.rate(0, step()) ~= 0 then
                return "first map must stay at zero percent"
            end
            if state.hook_pair ~= "ConflictDirector._post_spawn_unit" then
                return "hook pair drift: " .. tostring(state.hook_pair)
            end
            if state.errors > 0 then
                return "runtime selection/apply errors this session: " .. tostring(state.last_error)
            end
            if state.no_identity > 0 then
                return "elite spawns without a spawn queue id this session: "
                    .. tostring(state.no_identity)
            end
        end)
    end

    log("[ct:323] runtime installed activation=%s rates=%s hook=%s",
        state.activation(), state.rate_label(), state.hook_pair)

    return state
end
