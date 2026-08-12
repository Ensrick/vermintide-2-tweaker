-- Owns the shared attachment/preview spawn boundary used by Cosmetics.
--
-- This is intentionally one ordered owner.  Attachment residency, safe link
-- policy installation, LA queueing, Material-Hijack preview work, authored-hat
-- surfaces, preview glow identity, and score-hat paint all touch the same unit
-- at spawn time.  Splitting those writes across competing hooks recreates the
-- ordering bugs this boundary was designed to prevent.
--
-- Owned by: cosmetics_tweaker.lua entry point.
-- Consumed via: one ordered installer call after the frame scheduler/probe and
-- before the LA diagnostic-command/cache-bridge owners.

local SpawnBoundary = {}

local function publish_owner(mod, state)
    local owner = mod._cos_spawn_boundary_owner
    if type(owner) ~= "table" then owner = {} end
    for key in pairs(owner) do owner[key] = nil end
    owner.hook_count = state.hook_count or 0
    owner.unit_resident = state.unit_resident
    mod._cos_spawn_boundary_owner = owner
    return owner
end

function SpawnBoundary.install(mod, deps)
    deps = deps or {}
    local state = mod._cos_spawn_boundary_state
    if not state then
        state = { installed = false, hook_count = 0 }
        mod._cos_spawn_boundary_state = state
    end

    -- Refresh every action-time dependency on reload while leaving registration
    -- cardinality unchanged.
    state.application = deps.application
    state.attachment_utils = deps.attachment_utils
    state.world = deps.world
    state.unit = assert(deps.unit, "unit is required")
    state.la_bridge = assert(deps.la_bridge, "la_bridge is required")
    state.custom_hats = assert(deps.custom_hats, "custom_hats is required")
    state.gk_set = assert(deps.gk_set, "gk_set is required")
    state.mh_embed = deps.mh_embed
    state.attachment_link_policy = assert(
        deps.attachment_link_policy,
        "attachment_link_policy is required"
    )
    state.get_mod = assert(deps.get_mod, "get_mod is required")
    state.dbg = assert(deps.dbg, "dbg is required")
    state.printf = deps.printf

    state.unit_resident = state.unit_resident or function(path)
        if type(path) ~= "string" or path == "" then return true end
        local application = state.application
        local can_get = application and application.can_get
        if not can_get then return true end
        local ok, resident = pcall(can_get, "unit", path)
        if not ok then return true end
        return resident and true or false
    end

    if state.installed then return publish_owner(mod, state) end

    local attachment_utils = state.attachment_utils
    if attachment_utils then
        -- #270: every attachment path reaches this choke point before the
        -- engine-fatal World.spawn_unit assertion.  Only headpieces are
        -- optional; every other attachment keeps native behavior.
        if attachment_utils.create_attachment then
            mod:hook(attachment_utils, "create_attachment",
                function(func, world, owner_unit, attachments, slot_name,
                    item_data, show)
                    local spawn_item = item_data
                    local path = spawn_item and spawn_item.unit
                    local is_headpiece = slot_name == "slot_hat"
                    if is_headpiece and type(path) == "string" and path ~= ""
                            and not state.unit_resident(path) then
                        mod:info("[cos-hat] SKIP non-resident headpiece=%s slot=%s owner=%s (viewer package not resident; no hat instead of crash)",
                            tostring(path), tostring(slot_name),
                            tostring(type(owner_unit) == "userdata"
                                and "unit" or owner_unit))
                        return {
                            unit = nil,
                            name = item_data and item_data.name,
                            item_data = item_data,
                        }
                    end
                    local slot_data = func(world, owner_unit, attachments,
                        slot_name, spawn_item, show)
                    if slot_data and item_data
                            and item_data.name == state.custom_hats.ITEM_KEY then
                        state.custom_hats.apply_surface(
                            slot_data.unit, "live-attachment")
                    end
                    return slot_data
                end)
            state.hook_count = state.hook_count + 1
        end

        -- #270/#950: the policy rejects dead units before Unit.node's C
        -- assertion while preserving every valid optional-link pair.
        state.attachment_link_policy.install(
            mod, attachment_utils, state.la_bridge, state.unit)
    end

    -- LA also observes the lower-level World link path for hats that bypass
    -- AttachmentUtils.
    local world_api = state.world
    if world_api and world_api.link_unit then
        mod:hook_safe(world_api, "link_unit",
            function(world, child_unit, child_node, parent_unit, parent_node)
                if not state.la_bridge.registered then return end
                if type(child_unit) ~= "userdata" then return end
                if not state.unit.alive(child_unit) then return end
                if not state.unit.has_data(child_unit, "unit_name") then return end
                state.la_bridge.maybe_queue_unit(
                    world, child_unit,
                    state.unit.get_data(child_unit, "unit_name"))
            end)
        state.hook_count = state.hook_count + 1
    end

    local function queue_preview_unit(self, unit)
        if not state.la_bridge.registered then return end
        if type(unit) ~= "userdata" then return end

        local world = self._world or self.world
        local spawning = self._cos_la_spawning
        state.dbg("[LA preview] _spawn_item_unit spawning=%s world=%s",
            tostring(spawning), tostring(world))
        if spawning then
            local ok = state.la_bridge.queue_unit_direct(world, unit, spawning)
            state.dbg("[LA preview]   queue_unit_direct result=%s", tostring(ok))
            return
        end

        if state.unit.has_data(unit, "unit_name") then
            state.la_bridge.maybe_queue_unit(
                world, unit, state.unit.get_data(unit, "unit_name"))
        else
            state.la_bridge.suppress_orphan(unit)
        end
    end

    -- One combined hook preserves MH-before-vanilla and LA-after-vanilla order.
    local function spawn_item_unit_combined(func, self, unit, item_slot_type,
        item_template, attachment_node_linking, scene_graph_links,
        material_settings, skip_wield_anim)
        local mh_embed = state.mh_embed
        if mh_embed and not mh_embed.dormant and unit then
            mh_embed.replace_textures(unit)
            mh_embed.add_particles(unit, self.world)
            mh_embed.attach_anim_extension(unit)
        end

        local r1, r2 = func(self, unit, item_slot_type, item_template,
            attachment_node_linking, scene_graph_links, material_settings,
            skip_wield_anim)

        if item_slot_type == "hat" then
            local authored_key = self._cos_la_spawning
                    and state.la_bridge.backend_to_armoury[self._cos_la_spawning]
                or (self._cos_score_hat and self._cos_score_hat.armoury_key)
            if authored_key and state.custom_hats.is_custom_identity(authored_key) then
                state.custom_hats.apply_surface(unit, "hero-preview")
            elseif authored_key and state.gk_set.resolve_variant(authored_key) then
                state.gk_set.apply_variant_to_unit(
                    authored_key, unit, "hero_preview")
            end
        end

        if unit and self._cos_current_equip_backend_id
                and mod._unit_to_backend_id then
            mod._unit_to_backend_id[unit] = self._cos_current_equip_backend_id
        end

        queue_preview_unit(self, unit)

        if self._cos_score_hat and item_slot_type == "hat"
                and not state.custom_hats.is_custom_identity(
                    self._cos_score_hat.armoury_key)
                and type(unit) == "userdata" and state.unit.alive(unit) then
            local la = state.get_mod("Loremasters-Armoury")
            if la and type(la.apply_new_skin_from_texture) == "function" then
                local info = self._cos_score_hat
                state.la_bridge._bridge_active = true
                local ok, err = pcall(la.apply_new_skin_from_texture,
                    info.armoury_key, self.world, info.vanilla_key, unit)
                state.la_bridge._bridge_active = false
                if state.printf then
                    state.printf("[la-state] SCORE-HAT paint key=%s ok=%s%s",
                        tostring(info.armoury_key), tostring(ok),
                        ok and "" or (" err=" .. tostring(err)))
                end
            end
        end
        return r1, r2
    end

    mod:hook("HeroPreviewer", "_spawn_item_unit", spawn_item_unit_combined)
    mod:hook("MenuWorldPreviewer", "_spawn_item_unit", spawn_item_unit_combined)
    state.hook_count = state.hook_count + 2

    state.installed = true
    return publish_owner(mod, state)
end

return SpawnBoundary
