-- _ct_official_feature_leaf.lua - selective official feature installation.
--
-- Owns only the #289, #323, #361 and #505 leaf load graph. The public entry
-- supplies its existing host-effective readers; this owner adds no wire catalog,
-- transport, feasibility observer, preview panel or profile diagnostics.
-- Consumed once by chaos_wastes_tweaker.lua after _ct_rt_register is published.
return function(ctx)
    assert(type(ctx) == "table", "CT feature leaf requires context")
    local mod = assert(ctx.mod, "CT feature leaf requires mod")
    assert(type(ctx.effective_setting) == "function", "CT feature leaf requires effective_setting")
    assert(type(ctx.is_curse_disabled) == "function", "CT feature leaf requires is_curse_disabled")
    if mod._ct_official_feature_leaf then return mod._ct_official_feature_leaf end

    local state = {}
    mod._ct_effective_setting = ctx.effective_setting
    state.modifiers = mod:dofile("scripts/mods/chaos_wastes_tweaker/_ct_progressive_modifier_runtime")({
        mod = mod,
        effective_setting = ctx.effective_setting,
        is_curse_disabled = ctx.is_curse_disabled,
    })
    state.elites = mod:dofile("scripts/mods/chaos_wastes_tweaker/_ct_progressive_elite_runtime")({
        mod = mod,
        effective_setting = ctx.effective_setting,
    })
    mod:dofile("scripts/mods/chaos_wastes_tweaker/_ct_miasma")
    mod:dofile("scripts/mods/chaos_wastes_tweaker/_ct_dev_mission")

    -- Called from the existing settings/host-state reapply path, not a new hook.
    state.reapply_miasma = function()
        return mod._ct_sync_miasma()
    end

    if type(mod._ct_rt_register) == "function" then
        mod._ct_rt_register("issue361_miasma_customization_installed", function()
            local policy = mod._ct_miasma_policy
            if type(policy) ~= "table" or type(policy.radius) ~= "function"
                    or type(policy.interval) ~= "function" or type(policy.select_owner) ~= "function" then
                return "#361 Miasma policy missing or incomplete"
            end
            if policy.radius(nil) ~= 8 or policy.interval(nil) ~= 1.3
                    or policy.radius(100) ~= 30 or policy.interval(0) ~= 0.1 then
                return "#361 Miasma slider self-test failed"
            end
            local dead, living = {}, {}
            local owner = policy.select_owner(living, { dead }, function(unit) return unit == living end)
            if owner ~= living then return "#361 dead carrier replaced the living owner" end
            if not mod._ct_miasma361_hook_installed then
                return "#361 live MutatorTemplates curse update hook missing"
            end
            if type(mod._ct_sync_miasma) ~= "function" or not mod._ct_sync_miasma() then
                return "#361 Miasma buff template unavailable"
            end
        end)

        mod._ct_rt_register("single_mission_loader_redesign_505", function()
            if not mod._ct_dev_mission_loaded then return "single-mission loader module did not load" end
            if type(mod.ct_dev_load_selected_mission) ~= "function" then
                return "ct_dev_load_selected_mission keybind target missing"
            end
            if type(mod._ct_dev_mission_do_load) ~= "function" then return "single-mission load primitive missing" end
            if type(mod._ct505_in_pilgrimage_chamber) ~= "function"
                    or not mod._ct505_in_pilgrimage_chamber("morris_hub")
                    or mod._ct505_in_pilgrimage_chamber("inn_level")
                    or mod._ct505_in_pilgrimage_chamber("dlc_morris_map") then
                return "Pilgrimage Chamber gate must accept only morris_hub"
            end
            local cat = mod._ct_dev_mission_catalog
            if type(cat) ~= "table" or type(cat.compose_level_key) ~= "function"
                    or type(cat.build_menu_group) ~= "function" then return "mission catalog/composer missing" end
            if not (cat.sanitize_progress and cat.MAX_RUN_PROGRESS == 0.999
                    and cat.PROGRESS[#cat.PROGRESS] == 0.999 and cat.sanitize_progress(1) == 0.999) then
                return "unsafe run progress"
            end
            local key, theme, path = cat.compose_level_key("pat_forest", "curse_rotten_miasma",
                { pat_forest = { paths = { 3 } } })
            if key ~= "pat_forest_nurgle_path3" or theme ~= "nurgle" or path ~= 3 then
                return "curse/theme/valid-path composition mismatch"
            end
            local ids = {}
            for _, child in ipairs(cat.build_menu_group().sub_widgets or {}) do ids[child.setting_id] = true end
            if ids.ctdm_theme or ids.ctdm_path or ids.ctdm_blessing then return "removed mission selectors returned" end
            if not (ids.ctdm_base and ids.ctdm_curse and ids.ctdm_progress) then
                return "required mission/curse/progress selectors missing"
            end
            if not mod._ct505_uses_starting_boons then return "existing Starting Boons seam missing" end
        end)
    end

    mod._ct_official_feature_leaf = state
    return state
end
