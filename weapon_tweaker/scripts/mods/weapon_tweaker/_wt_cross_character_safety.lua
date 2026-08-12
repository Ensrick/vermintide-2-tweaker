-- Cross-character engine-fatal safety owner (#1159).
--
-- Installs at the former post-template-patch seam. It owns Deepwood Staff
-- finger-node refusal, animation-variable RPC replay safety, body attachment
-- substitution, and the universal GearUtils.link_units sanitizer.

local M = {}

function M.install(mod, deps)
    assert(type(mod) == "table", "_wt_cross_character_safety requires mod")
    assert(type(deps) == "table", "_wt_cross_character_safety requires deps")
    local dbg = assert(deps.dbg, "missing dbg")
    local dbg_alert = assert(deps.dbg_alert, "missing dbg_alert")

    local function guard_thorn_finger_enter(original)
        return function(self, owner_unit, weapon_unit, state_data, is_local_player, world)
            if is_local_player and owner_unit and Unit.alive(owner_unit) then
                local first_person = ScriptUnit.has_extension(owner_unit, "first_person_system")
                local mesh_unit = first_person and first_person:get_first_person_mesh_unit()
                if mesh_unit and Unit.has_node and not Unit.has_node(mesh_unit, "ep_r_index") then
                    state_data.particle_ids = {}
                    state_data.nodes = state_data.nodes or {}
                    state_data.timer = 0.7
                    return
                end
            end
            return original(self, owner_unit, weapon_unit, state_data, is_local_player, world)
        end
    end

    local function patch_thorn_finger_guard()
        if not (Weapons and Unit and Unit.has_node and Unit.alive and ScriptUnit) then
            dbg_alert("[wt:tpl_patch] event=skip template=staff_life reason=missing_api")
            return
        end
        local count = 0
        for _, name in ipairs({ "staff_life", "staff_life_vs" }) do
            local template = Weapons[name]
            local synced_states = template and template.synced_states
            if synced_states then
                for _, state_name in ipairs({ "wielding", "targeting" }) do
                    local state = synced_states[state_name]
                    if type(state) == "table" and type(state.enter) == "function"
                            and not state._wt_thorn_guarded then
                        state.enter = guard_thorn_finger_enter(state.enter)
                        state._wt_thorn_guarded = true
                        count = count + 1
                    end
                end
            end
        end
        dbg("[wt:tpl_patch] event=applied template=staff_life thorn_finger_crash_guard states=%d", count)
    end
    patch_thorn_finger_guard()

    -- `skip_sync` is deliberately named and forwarded. Dropping it re-arms the
    -- host/client animation RPC feedback loop fixed under BUG_CLASSES 19.
    mod:hook("AnimationSystem", "anim_event_with_variable_float",
        function(func, self, unit, event_name, variable_name, variable_value, skip_sync)
            if unit and Unit.alive(unit) then
                local index = Unit.animation_find_variable(unit, variable_name)
                if type(index) ~= "number" then return end
            end
            return func(self, unit, event_name, variable_name, variable_value, skip_sync)
        end)

    local function validate_attachment_sources(body_unit, attachment_node_linking)
        if not attachment_node_linking
                or type(attachment_node_linking.third_person) ~= "table"
                or not body_unit or not Unit.has_node then
            return
        end
        local substituted = 0
        for _, phase in ipairs({ "display", "wielded", "unwielded" }) do
            local links = attachment_node_linking.third_person[phase]
            if type(links) == "table" then
                for _, link in ipairs(links) do
                    if type(link) == "table" and type(link.source) == "string"
                            and not Unit.has_node(body_unit, link.source) then
                        link.source = "j_hips"
                        substituted = substituted + 1
                    end
                end
            end
        end
        if substituted > 0 then
            dbg("[wt:body_attach_safe] substituted %d missing-node source(s) at spawn", substituted)
        end
    end

    -- WT_LINK_UNITS_NODE_GUARD_MARKER
    mod._wt_link_filter = function(linking, source_has_node, target_has_node)
        local safe, dropped, substituted = nil, 0, 0
        for index = 1, #linking do
            local link = linking[index]
            local source = link.source
            local source_ok = type(source) ~= "string" or source_has_node(source)
            local target_ok = type(link.target) ~= "string" or target_has_node(link.target)
            local hip_fallback = not source_ok and type(source) == "string"
                and source:sub(1, 12) == "a_unwielded_" and source_has_node("j_hips")
            if target_ok and (source_ok or hip_fallback) then
                if hip_fallback then
                    if not safe then
                        safe = {}
                        for prior = 1, index - 1 do safe[prior] = linking[prior] end
                    end
                    local copy = {}
                    for key, value in pairs(link) do copy[key] = value end
                    copy.source = "j_hips"
                    safe[#safe + 1] = copy
                    substituted = substituted + 1
                elseif safe then
                    safe[#safe + 1] = link
                end
            else
                if not safe then
                    safe = {}
                    for prior = 1, index - 1 do safe[prior] = linking[prior] end
                end
                dropped = dropped + 1
            end
        end
        return safe or linking, dropped, substituted
    end

    if GearUtils and GearUtils.link_units and Unit and Unit.has_node then
        mod:hook(GearUtils, "link_units",
            function(func, world, attachment_node_linking, link_table, source, target)
                if type(attachment_node_linking) == "table" and source and target then
                    local filtered, dropped, substituted = mod._wt_link_filter(
                        attachment_node_linking,
                        function(name) return Unit.has_node(source, name) end,
                        function(name) return Unit.has_node(target, name) end)
                    if dropped > 0 or substituted > 0 then
                        dbg("[wt:link_guard] sanitized attachment links: dropped=%d hip_fallback=%d",
                            dropped, substituted)
                        return func(world, filtered, link_table, source, target)
                    end
                end
                return func(world, attachment_node_linking, link_table, source, target)
            end)
    end

    return { validate_attachment_sources = validate_attachment_sources }
end

return M
