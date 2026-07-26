-- _gt_diag_player_stats.lua -- issue #797 live player-stat HUD.
--
-- This is a local, read-only observer. It snapshots BuffExtension's retained
-- stages and their active-buff provenance on lifecycle edges, samples bounded
-- deterministic values at 4 Hz, and never calls proc-bearing application code.
-- luacheck: globals Managers ScriptUnit Unit StatBuffApplicationMethods printf
-- luacheck: globals UIRenderer UISceneGraph Vector3 UILayer Colors UISettings
-- luacheck: globals CareerSettings PlayerUnitStatusSettings
-- luacheck: globals MeleeBuffTypes RangedBuffTypes DamageProfileTemplates

local mod = get_mod("gt_dev")
local core = mod:dofile("scripts/mods/general_tweaker_dev/_gt_player_stat_probe_core")
local hud = mod:dofile("scripts/mods/general_tweaker_dev/_gt_player_stat_hud_policy")
local clock, next_poll, trace = 0, 0, nil
local cache = core.new_cache()
local plan, rendered_lines, all_lines, rendered_fingerprint = nil, nil, nil, nil
local current_page, page_count, hud_scenegraph = 1, 1, nil
local localized, hud_text = {}, nil
local _reset_hud
local SETTING_HUD = "gt_devtools_player_stat_hud"
local SETTING_MODE = "gt_player_stat_hud_mode"
local SETTING_POSITION = "gt_player_stat_hud_position"
local SETTING_SCALE = "gt_player_stat_hud_scale"
local FONT = "materials/fonts/arial"
local ROOT = {
    root = {
        scale = "hud_scale_fit",
        position = { 0, 0, (rawget(_G, "UILayer") and UILayer.hud) or 100 },
        size = { 1920, 1080 },
    },
}
local RENDER_SETTINGS = { snap_pixel_positions = true }

local function _safe(fn)
    local ok, value = pcall(fn)
    return ok and value or nil
end

local function _localize(key)
    if localized[key] == nil then
        localized[key] = _safe(function() return mod:localize(key) end) or key
    end
    return localized[key]
end

local function _hud_text()
    if not hud_text then
        hud_text = {
            title = _localize("gt_player_stat_hud_title"),
            compact_more = _localize("gt_player_stat_hud_compact_more"),
            page = _localize("gt_player_stat_hud_page"),
            page_help = _localize("gt_player_stat_hud_page_help"),
        }
    end
    return hud_text
end

local function _extension(unit, system)
    if not unit or not ScriptUnit then return nil end
    if type(ScriptUnit.has_extension) == "function" then
        return _safe(function() return ScriptUnit.has_extension(unit, system) end)
    end
    return _safe(function() return ScriptUnit.extension(unit, system) end)
end

local function _local_unit()
    local pm = Managers and Managers.player
    local player = pm and _safe(function() return pm:local_player(1) end)
    local unit = player and player.player_unit
    if not unit or not Unit or not Unit.alive
        or not _safe(function() return Unit.alive(unit) end) then
        return nil, "local-player-unavailable"
    end
    local health = _extension(unit, "health_system")
    local status = _extension(unit, "status_system")
    if hud.unit_is_dead(health, status) then
        return nil, "local-player-dead"
    end
    return unit
end

local function _call(object, method)
    return object and type(object[method]) == "function"
        and _safe(function() return object[method](object) end) or nil
end

local function _call2(object, method)
    if not object or type(object[method]) ~= "function" then return nil, nil end
    local ok, first, second = pcall(object[method], object)
    if ok then return first, second end
    return nil, nil
end

local function _hash_text(hash, value)
    local text = tostring(value or "")
    for i = 1, #text do hash = (hash * 33 + string.byte(text, i)) % 2147483647 end
    return hash
end

-- Cheap allocation-bounded edge signature over live buff instances. These are
-- the source objects that create/remove retained _stat_buffs stages.
local function _buff_signature(buff)
    local hash, count, inspected, truncated = 5381, 0, 0, false
    for key, value in pairs(buff._buffs or {}) do
        inspected = inspected + 1
        if inspected > core.MAX_ACTIVE_BUFFS then
            truncated = true
            break
        end
        if type(value) == "table" then
            count = count + 1
            hash = _hash_text(hash, key)
            hash = _hash_text(hash, value.buff_template_name)
            hash = _hash_text(hash, value.buff_type)
            hash = _hash_text(hash, value.stat_buff_index)
            hash = _hash_text(hash, value.bonus)
            hash = _hash_text(hash, value.multiplier)
            hash = _hash_text(hash, value.proc_chance)
            hash = _hash_text(hash, value.value)
        end
    end
    return table.concat({
        tostring(count), tostring(hash), truncated and "truncated" or "complete",
    }, ":")
end

local function _equipment_context(unit)
    local inventory = _extension(unit, "inventory_system")
    local equipment = inventory and _call(inventory, "equipment")
    if type(equipment) ~= "table" and inventory
        and type(inventory.equipment) == "table" then
        equipment = inventory.equipment
    end
    local slot_name = equipment and (equipment.wielded_slot or equipment.wielded_slot_name)
    local slot = slot_name and equipment.slots and equipment.slots[slot_name]
    local item = slot and slot.item_data or equipment and equipment.wielded
    local template = inventory and _call(inventory, "get_wielded_slot_item_template")
    local action_settings
    local function inspect_weapon(weapon_unit)
        local weapon = _extension(weapon_unit, "weapon_system")
        if weapon and weapon.current_action_settings then
            return weapon.current_action_settings
        end
    end
    if equipment then
        action_settings = inspect_weapon(equipment.right_hand_wielded_unit)
            or inspect_weapon(equipment.left_hand_wielded_unit)
    end
    local lookup = action_settings and action_settings.lookup_data or {}
    local damage_profile = action_settings and (
        action_settings.damage_profile or action_settings.initial_damage_profile
        or action_settings.impact_data and action_settings.impact_data.damage_profile)
    local critical_profile_name = action_settings and (
        action_settings.damage_profile or action_settings.damage_profile_left
        or action_settings.damage_profile_right)
    local critical_profile = critical_profile_name
        and rawget(_G, "DamageProfileTemplates")
        and DamageProfileTemplates[critical_profile_name]
    local buff_type = template and template.buff_type
    local weapon_type = template and template.weapon_type
    local action_kind = action_settings and action_settings.kind
    local critical_is_melee = action_kind == "sweep"
        or action_kind == "push_stagger" or action_kind == "shield_slam"
    return {
        inventory = inventory,
        template_object = template,
        slot = tostring(slot_name or "nil"),
        item = tostring(item and (item.key or item.name or item.item_type) or "nil"),
        template = tostring(item and item.template or lookup.item_template_name or "nil"),
        style = tostring(template and (template.buff_type or template.weapon_type) or "nil"),
        action = tostring(lookup.action_name or "idle"),
        subaction = tostring(lookup.sub_action_name or "-"),
        damage_profile = tostring(damage_profile or "-"),
        action_available = action_settings ~= nil,
        action_anim_time_scale = action_settings
            and action_settings.anim_time_scale or 1,
        action_custom_time_scale = action_settings
            and action_settings.custom_anim_time_scale_mult ~= nil,
        scale_anim_by_charge_time = action_settings
            and action_settings.scale_anim_by_charge_time_buff == true,
        scale_chain_window_by_charge_time = action_settings
            and action_settings.scale_chain_window_by_charge_time_buff == true,
        action_additional_crit = action_settings
            and action_settings.additional_critical_strike_chance or 0,
        critical_is_melee = critical_is_melee,
        critical_is_heavy = critical_profile
            and critical_profile.charge_value == "heavy_attack" or false,
        is_melee = buff_type and rawget(_G, "MeleeBuffTypes")
            and MeleeBuffTypes[buff_type] == true or false,
        is_ranged = buff_type and rawget(_G, "RangedBuffTypes")
            and RangedBuffTypes[buff_type] == true or false,
        is_drakefire = weapon_type == "DRAKEFIRE",
    }
end

local function _context(unit)
    local equipment = _equipment_context(unit)
    local health = _extension(unit, "health_system")
    local status = _extension(unit, "status_system")
    local career = _extension(unit, "career_system")
    local career_name = tostring(_call(career, "career_name")
        or career and career._career_name or "nil")
    local career_data = rawget(_G, "CareerSettings")
        and CareerSettings[career_name]
    local attributes = career_data and career_data.attributes or {}
    local template = equipment.template_object
    local critical_base = _call(career, "get_base_critical_strike_chance")
        or attributes.base_critical_strike_chance
    local cooldown_remaining, cooldown_max = _call2(
        career, "current_ability_cooldown")
    local ability_ready, ability_max = _call2(career, "num_charges_ready")
    local character_power = _call(career, "get_career_power_level")
    local bases = {
        health = _call(health, "get_base_max_health"),
        stamina = template and template.max_fatigue_points
            or status and status._max_fatigue_points,
        cooldown = cooldown_max or _call(career, "get_max_ability_cooldown"),
        critical = critical_base,
        fatigue_regen_amount = rawget(_G, "PlayerUnitStatusSettings")
            and PlayerUnitStatusSettings.FATIGUE_POINTS_DEGEN_AMOUNT,
        ability_max_charges = ability_max,
        character_power = character_power,
    }
    equipment.career = career_name
    equipment.health = _call(health, "current_health")
    equipment.max_health = _call(health, "get_max_health")
    equipment.max_fatigue = _call(status, "get_max_fatigue_points")
    equipment.character_power = character_power
    equipment.critical_base = critical_base
    equipment.cooldown_remaining = cooldown_remaining
    equipment.ability_ready_charges = ability_ready
    equipment.ability_max_charges = ability_max
    return equipment, bases
end

local function _identity(unit, context)
    return table.concat({
        tostring(unit), context.career, context.slot, context.item,
        context.template, context.style, context.action, context.subaction,
        context.damage_profile,
    }, "|")
end

local function _build_plan(buff)
    return core.normalize(buff._stat_buffs,
        rawget(_G, "StatBuffApplicationMethods"), buff._buffs)
end

local function _sample(unit, buff, context, bases)
    local rows = hud.build_rows(plan, bases, core.evaluate, _localize, context)
    return {
        rows = rows,
        context = context,
        active_buffs = tonumber(buff._num_buffs) or 0,
        unit = unit,
        truncated = plan.truncated or plan.source_truncated,
    }
end

local function _sample_fingerprint(snapshot)
    local parts = {
        snapshot.context.action, snapshot.context.subaction,
        snapshot.context.damage_profile, tostring(snapshot.context.health),
    }
    for _, row in ipairs(snapshot.rows) do
        parts[#parts + 1] = row.stat
        parts[#parts + 1] = row.value.supported and tostring(row.value.final)
            or tostring(row.value.reason)
    end
    return table.concat(parts, "|")
end

local function _repaginate()
    if not all_lines then
        rendered_lines = nil
        return
    end
    rendered_lines, current_page, page_count = hud.page(
        all_lines, current_page, _hud_text())
end

local function _clear_panel()
    cache = core.new_cache()
    plan, rendered_lines, all_lines, rendered_fingerprint = nil, nil, nil, nil
    current_page, page_count, hud_scenegraph = 1, 1, nil
end

local function _refresh(force)
    local unit, unavailable_reason = _local_unit()
    if not unit then
        _clear_panel()
        return nil, unavailable_reason
    end
    local buff = _extension(unit, "buff_system")
    if not buff or type(buff._stat_buffs) ~= "table" then
        _clear_panel()
        return nil, "buff-extension-unavailable"
    end
    local context, bases = _context(unit)
    local signature = _buff_signature(buff)
    local identity = _identity(unit, context)
    if force then cache.next_sample = clock end
    local due, edge = core.cache_due(cache, clock, identity, signature)
    if not due and not force then return nil, "not-due" end
    if edge or not plan then plan = _build_plan(buff) end
    local snapshot = _sample(unit, buff, context, bases)
    local fingerprint = _sample_fingerprint(snapshot)
    if fingerprint ~= rendered_fingerprint or edge or force then
        rendered_fingerprint = fingerprint
        all_lines = hud.wrap_lines(hud.all_lines(snapshot,
            mod:get(SETTING_MODE) == "expanded", _hud_text()),
            hud.max_chars(mod:get(SETTING_SCALE)))
        local header_count = tonumber(all_lines.header_count) or 3
        current_page = math.min(current_page, math.max(1,
            math.ceil(math.max(0, #all_lines - header_count) / hud.PAGE_ROWS)))
        _repaginate()
        core.record_allocation(cache, #snapshot.rows, #all_lines)
    end
    snapshot.fingerprint = core.fingerprint(plan)
    return snapshot
end

local function _emit(snapshot, phase)
    local c = snapshot.context
    pcall(printf,
        "[gt:797] phase=%s career=%s slot=%s item=%s template=%s style=%s action=%s/%s profile=%s health=%s/%s active_buffs=%d stages=%d truncated=%s",
        tostring(phase), c.career, c.slot, c.item, c.template, c.style,
        c.action, c.subaction, c.damage_profile, tostring(c.health),
        tostring(c.max_health), snapshot.active_buffs, plan.contributions,
        tostring(plan.truncated))
    for _, row in ipairs(snapshot.rows) do
        pcall(printf, "[gt:797] stat=%s method=%s %s consumer=%s",
            row.stat, row.method, hud.row_text(row), row.consumer)
        local entries = row.value.supported and row.value.contributions
            or row.stages or {}
        for _, entry in ipairs(entries or {}) do
            local contribution = row.value.supported and entry or nil
            local stage_key = contribution and contribution.key_text
                or entry.key_text
            pcall(printf,
                "[gt:797] stat=%s stage=%s kind=%s delta=%s reason=%s sources=%d",
                row.stat, tostring(stage_key),
                contribution and contribution.kind or "unsupported",
                tostring(contribution and contribution.delta),
                tostring(row.value.reason or "none"), #(entry.sources or {}))
            for _, source in ipairs(entry.sources or {}) do
                pcall(printf,
                    "[gt:797] stat=%s stage=%s source_parent=%s source_child=%s source_id=%s",
                    row.stat, tostring(stage_key),
                    source.parent, source.child, source.id)
            end
        end
    end
end

local function _capture(phase)
    local snapshot, reason = _refresh(true)
    if not snapshot then
        pcall(printf, "[gt:797] phase=%s skip=%s", tostring(phase), tostring(reason))
        return nil
    end
    _emit(snapshot, phase)
    return snapshot
end

_reset_hud = function()
    _clear_panel()
    next_poll = 0
end

local function _update(dt)
    clock = clock + (tonumber(dt) or 0)
    if mod:get(SETTING_HUD) == true then
        if clock >= next_poll then
            next_poll = clock + core.SAMPLE_SECONDS
            _refresh(false)
        end
    elseif rendered_lines then
        _reset_hud()
    end
    if trace then
        local offset = core.take_due(trace, clock)
        if offset ~= nil then
            local snapshot = _capture(string.format("trace_%.2f", offset))
            core.record(trace, offset, snapshot and snapshot.fingerprint or "unavailable")
            if core.complete(trace) then
                pcall(printf, "[gt:797] trace complete records=%d window=10.00", #trace.records)
                trace = nil
            end
        end
    end
end

local function _color(name, fallback)
    local colors = rawget(_G, "Colors")
    return colors and type(colors.get_table) == "function"
        and _safe(function() return colors.get_table(name) end) or fallback
end

local function _draw(self, dt)
    if mod:get(SETTING_HUD) ~= true or not rendered_lines then return end
    local context = self and self._ingame_ui_context
    local renderer = context and context.ui_renderer
        or (Managers.ui and Managers.ui._ingame_ui_context
            and Managers.ui._ingame_ui_context.ui_top_renderer)
    if not renderer then return end
    local input = context and context.input_manager
        and context.input_manager:get_service("ingame_menu")
    if not hud_scenegraph then hud_scenegraph = UISceneGraph.init_scenegraph(ROOT) end
    local layout = hud.layout(#rendered_lines, mod:get(SETTING_SCALE),
        mod:get(SETTING_POSITION))
    local heading = _color("font_title", { 255, 255, 205, 80 })
    local normal = _color("white", { 255, 225, 225, 225 })
    UIRenderer.begin_pass(renderer, hud_scenegraph, input, dt, nil, RENDER_SETTINGS)
    for i = 1, #rendered_lines do
        local y = layout.top - layout.padding - i * layout.line_height
        UIRenderer.draw_text(renderer, rendered_lines[i], FONT, layout.font_size, nil,
            Vector3(layout.x + layout.padding, y, 997), i == 1 and heading or normal)
    end
    UIRenderer.end_pass(renderer)
end

if type(mod._gt_register_update) == "function" then
    mod._gt_register_update("gt797_player_stat_probe", _update)
    mod._gt_player_stat_probe_update_registered = true
end

mod:command("gt_stat_probe", "Log one read-only local player stat snapshot", function()
    _capture("single")
end)

mod:command("gt_stat_trace", "Log five bounded stat snapshots over ten seconds", function()
    trace = core.new_trace(clock)
    pcall(printf, "[gt:797] trace armed samples=%d window=10.00", #core.TRACE_OFFSETS)
end)

mod:command("gt_stat_hud_page", "Select HUD page: next, prev, or a number", function(value)
    local requested = tonumber(value)
    if value == "prev" then requested = current_page - 1 end
    if value == nil or value == "" or value == "next" then requested = current_page + 1 end
    current_page = math.max(1, math.min(page_count, requested or current_page))
    _repaginate()
end)

mod:command("gt_stat_hud_metrics", "Log bounded stat HUD cache metrics", function()
    pcall(printf,
        "[gt:797] metrics samples=%d rebuilds=%d formatted=%d allocated_rows=%d allocated_lines=%d max_rows=%d max_lines=%d",
        cache.samples, cache.rebuilds, cache.formatted, cache.allocated_rows,
        cache.allocated_lines, cache.max_rows, cache.max_lines)
end)

mod._gt_player_stat_snapshot = _capture
mod._gt_player_stat_hud_draw = _draw
mod._gt_player_stat_hud_reset = _reset_hud

if type(mod._gt_rt_register) == "function" then
    mod._gt_rt_register("issue797_player_stat_diagnostics_armed", function()
        if mod._gt_player_stat_probe_update_registered ~= true
            or type(mod._gt_player_stat_snapshot) ~= "function"
            or core.MAX_STAT_TYPES ~= 256 or core.MAX_CONTRIBUTIONS ~= 1024
            or #core.TRACE_OFFSETS ~= 5 then
            return "player stat diagnostics wiring incomplete"
        end
    end)
    mod._gt_rt_register("issue797_player_stat_hud", function()
        local layout = hud.layout(22, 125, "bottom_right")
        if type(mod._gt_player_stat_hud_draw) ~= "function"
            or type(mod._gt_player_stat_hud_reset) ~= "function"
            or hud.COMPACT_ROWS ~= 8 or hud.PAGE_ROWS ~= 18
            or hud.REFRESH_SECONDS ~= 0.25
            or layout.x < 0 or layout.top - layout.height < 0
            or layout.x + layout.width > 1920 then
            return "player stat HUD wiring/layout incomplete"
        end
    end)
end

return core
