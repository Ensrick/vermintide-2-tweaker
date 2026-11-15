-- WP-WT-04: loads the production public-tree _wt_anim_remap.lua under stubs and
-- captures its Unit.animation_event and SimpleHuskInventoryExtension.wield
-- handlers. One call = one isolated module instance (fresh upvalues, fresh
-- per-unit state).
--
-- Not loaded here: the #536 reload router (_wt_reload_3p.lua), so
-- WT.reload_3p_route is nil and reload events take the generic path. The
-- entry's later template patchers (longbow ports) are not run either; the
-- harness pins the module's own tables.
--
-- has_event(unit, event) answers Unit.has_animation_event for every unit.
return function(repo_root, has_event)
    local tree_root = repo_root .. "/weapon_tweaker/"
    local hooks = {}
    local mod = {
        _wt = {
            feature_enabled = function() return true end,
            local_career_name = function() return nil end,
            dbg = function() end,
            MOD_VERSION = "test",
            weapon_unlock_map = {},
        },
    }

    local env
    local function load_into_env(path)
        local chunk = assert(loadfile(path))
        setfenv(chunk, env)
        return chunk()
    end

    function mod.dofile(_, path) return load_into_env(tree_root .. path .. ".lua") end
    function mod.hook(_, class_name, method, fn) hooks[class_name .. "." .. method] = fn end
    function mod.safe_hook(_, class_name, method, fn) hooks[class_name .. "." .. method] = fn end
    function mod.traced_hook() end
    function mod.command() end
    function mod.echo() end
    function mod.info() end

    env = setmetatable({
        get_mod = function(name)
            if name == "wt" then return mod end
            return nil
        end,
        Unit = {
            has_animation_event = function(unit, event) return has_event(unit, event) end,
        },
        ScriptUnit = {
            has_extension = function(unit, system)
                if system == "career_system" and unit.career then
                    return { _career_name = unit.career }
                end
            end,
        },
        Managers = {
            player = {
                local_player = function() return nil end,
                owner = function() return nil end,
            },
        },
    }, { __index = _G })

    -- The entry publishes this before dofiling the funnel (weapon_tweaker.lua:413).
    mod._wt.build_3p_template_remaps = mod:dofile("scripts/mods/weapon_tweaker/_wt_anim_remap_data")
    mod:dofile("scripts/mods/weapon_tweaker/_wt_anim_remap")

    return {
        mod = mod,
        anim = assert(hooks["Unit.animation_event"], "Unit.animation_event hook not registered"),
        husk_wield = assert(hooks["SimpleHuskInventoryExtension.wield"],
            "SimpleHuskInventoryExtension.wield hook not registered"),
    }
end
