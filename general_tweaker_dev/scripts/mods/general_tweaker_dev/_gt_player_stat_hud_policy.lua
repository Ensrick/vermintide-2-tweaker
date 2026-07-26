-- _gt_player_stat_hud_policy.lua -- pure issue #797 HUD/page policy.
local M = {}

M.COMPACT_ROWS = 8
M.PAGE_ROWS = 18
M.REFRESH_SECONDS = 0.25

-- Rows distinguish consumer-effective values from exact retained factors.
-- A factor is useful provenance, but it is not mislabeled as final damage,
-- power, cleave, block, ammo, or reload output when downstream inputs are
-- target/action/profile dependent.
M.CATALOG = {
    { stat = "max_health", label = "gt_player_stat_hud_stat_max_health", base = "health", live = "max_health", consumer = "HealthExtension.get_max_health" },
    { stat = "max_fatigue", label = "gt_player_stat_hud_stat_max_fatigue", base = "stamina", live = "max_fatigue", consumer = "StatusExtension.get_max_fatigue_points" },
    { stat = "movement_speed", formula = "unsupported", reason = "stance/status/current_movement_speed_scale/player_speed_scale-dependent", label = "gt_player_stat_hud_stat_movement_speed", base = 4, consumer = "PlayerCharacterStateWalking final_move_speed" },
    -- Pinned source c5e4968 career_extension.lua:349-429 applies this stat
    -- only after current cooldown + activation cost - refund. Those call-site
    -- inputs are not retained by the sampler, so expose the exact stat factor
    -- instead of mislabeling max_cooldown * factor as an activation final.
    { stat = "activated_cooldown", label = "gt_player_stat_hud_stat_activated_cooldown", base = 1, display = "factor", consumer = "CareerExtension.start_activated_ability_cooldown activation adjustment" },
    { stat = "ability_remaining", formula = "ability_remaining", label = "gt_player_stat_hud_stat_ability_remaining", base = "cooldown", consumer = "CareerExtension.current_ability_cooldown" },
    { stat = "ability_charges", formula = "ability_charges", label = "gt_player_stat_hud_stat_ability_charges", base = "ability_max_charges", consumer = "CareerExtension.num_charges_ready" },
    { stat = "attack_speed_chain", source_stat = "attack_speed", formula = "attack_speed", action_is_animation = false, label = "gt_player_stat_hud_stat_attack_speed_chain", base = 1, consumer = "ActionUtils.get_action_time_scale (is_animation=false, custom_value=nil)" },
    { stat = "attack_speed_animation", source_stat = "attack_speed", formula = "attack_speed", action_is_animation = true, label = "gt_player_stat_hud_stat_attack_speed_animation", base = 1, consumer = "ActionUtils.get_action_time_scale (is_animation=true, custom_value=nil)" },
    { stat = "critical_strike_chance", formula = "unsupported", reason = "runtime-overrides-unobservable", label = "gt_player_stat_hud_stat_critical_strike_chance", base = "critical", consumer = "ActionUtils.get_critical_strike_chance" },
    { stat = "critical_settings_chance", formula = "critical", label = "gt_player_stat_hud_stat_critical_settings_chance", base = "critical", display = "settings", consumer = "ActionUtils.get_critical_strike_chance (action-settings path)" },
    { stat = "critical_strike_effectiveness", label = "gt_player_stat_hud_stat_critical_strike_effectiveness", base = 1, display = "factor", consumer = "critical damage profile factor" },
    { stat = "effective_power", formula = "unsupported", reason = "difficulty-profile-target-dependent", label = "gt_player_stat_hud_stat_effective_power", base = "character_power", consumer = "ActionUtils.get_power_level_for_target" },
    { stat = "power_level", label = "gt_player_stat_hud_stat_power_level", base = 1, display = "factor", consumer = "ActionUtils.apply_buffs_to_power_level" },
    { stat = "power_level_melee", label = "gt_player_stat_hud_stat_power_level_melee", base = 1, display = "factor", consumer = "ActionUtils.apply_buffs_to_power_level_on_hit" },
    { stat = "power_level_ranged", label = "gt_player_stat_hud_stat_power_level_ranged", base = 1, display = "factor", consumer = "ActionUtils.apply_buffs_to_power_level_on_hit" },
    { stat = "power_level_skaven", label = "gt_player_stat_hud_stat_power_level_skaven", base = 1, display = "factor", consumer = "ActionUtils.apply_buffs_to_power_level_on_hit" },
    { stat = "power_level_chaos", label = "gt_player_stat_hud_stat_power_level_chaos", base = 1, display = "factor", consumer = "ActionUtils.apply_buffs_to_power_level_on_hit" },
    { stat = "power_level_unarmoured", label = "gt_player_stat_hud_stat_power_level_unarmoured", base = 1, display = "factor", consumer = "ActionUtils.apply_buffs_to_power_level_on_hit" },
    { stat = "power_level_armoured", label = "gt_player_stat_hud_stat_power_level_armoured", base = 1, display = "factor", consumer = "ActionUtils.apply_buffs_to_power_level_on_hit" },
    { stat = "power_level_large", label = "gt_player_stat_hud_stat_power_level_large", base = 1, display = "factor", consumer = "ActionUtils.apply_buffs_to_power_level_on_hit" },
    { stat = "power_level_frenzy", label = "gt_player_stat_hud_stat_power_level_frenzy", base = 1, display = "factor", consumer = "ActionUtils.apply_buffs_to_power_level_on_hit" },
    { stat = "increased_weapon_damage_melee", label = "gt_player_stat_hud_stat_melee_damage", base = 1, display = "factor", consumer = "DamageUtils.calculate_damage" },
    { stat = "increased_weapon_damage_ranged", label = "gt_player_stat_hud_stat_ranged_damage", base = 1, display = "factor", consumer = "DamageUtils.calculate_damage" },
    { stat = "power_level_impact", label = "gt_player_stat_hud_stat_power_level_impact", base = 1, display = "factor", consumer = "DamageUtils.calculate_stagger" },
    { stat = "power_level_melee_cleave", label = "gt_player_stat_hud_stat_power_level_cleave", base = 1, display = "factor", consumer = "ActionSweep + ActionUtils.get_max_targets" },
    { stat = "increased_max_targets", label = "gt_player_stat_hud_stat_max_targets", base = 1, display = "factor", consumer = "ActionUtils.get_max_targets post-transform" },
    { stat = "damage_taken", label = "gt_player_stat_hud_stat_damage_taken", base = 1, display = "factor", consumer = "DamageUtils.add_damage_network_player" },
    { stat = "healing_received", label = "gt_player_stat_hud_stat_healing_received", base = 1, display = "factor", consumer = "DamageUtils.heal_network" },
    { stat = "fatigue_regen", formula = "fatigue_regen", label = "gt_player_stat_hud_stat_fatigue_regen", base = "fatigue_regen_amount", consumer = "GenericStatusExtension.update fatigue gauge per second" },
    { stat = "block_angle", label = "gt_player_stat_hud_stat_block_angle", base = 1, display = "factor", consumer = "weapon block-angle transform" },
    { stat = "block_cost", label = "gt_player_stat_hud_stat_block_cost", base = 1, display = "factor", consumer = "weapon fatigue-cost transform" },
    { stat = "push_power", label = "gt_player_stat_hud_stat_push_power", base = 1, display = "factor", consumer = "DamageUtils.calculate_stagger" },
    { stat = "push_cost", formula = "unsupported", reason = "proc-or-action-dependent", label = "gt_player_stat_hud_stat_push_cost", base = 1, consumer = "StatusExtension.add_fatigue_points" },
    { stat = "dodge_bonus", formula = "unsupported", reason = "weapon-state-dependent", label = "gt_player_stat_hud_stat_dodge_bonus", base = 1, consumer = "PlayerCharacterStateDodging" },
    { stat = "cooldown_regen", label = "gt_player_stat_hud_stat_cooldown_regen", base = 1, display = "factor", consumer = "CareerExtension.update" },
    { stat = "reload_speed", label = "gt_player_stat_hud_stat_reload_speed", base = 1, display = "factor", consumer = "weapon reload action" },
    { stat = "total_ammo", label = "gt_player_stat_hud_stat_total_ammo", base = 1, display = "factor", consumer = "AmmoExtension clip/reserve transform" },
}

local function _finite(value)
    return type(value) == "number" and value == value
        and value ~= math.huge and value ~= -math.huge
end

local function _number(value)
    return _finite(value) and string.format("%.3g", value) or "?"
end

local function _sources(contribution)
    if contribution.source_label then return contribution.source_label end
    local names = {}
    for _, source in ipairs(contribution.sources or {}) do
        names[#names + 1] = source.parent .. "/" .. source.child
            .. "{" .. tostring(source.lifetime or "unknown") .. "}"
    end
    return #names > 0 and table.concat(names, ",") or "collapsed/unknown"
end

local function _empty_row(stat)
    return { stat = stat, method = "none", stages = {} }
end

local function _source_row(normalized, stat)
    local row = normalized.by_stat[stat]
    if row then return row end
    if normalized.truncated then return nil end
    return _empty_row(stat)
end

local function _unsupported(base, reason, diagnostic)
    return {
        supported = false,
        reason = reason,
        base = base,
        diagnostic = diagnostic,
    }
end

local function _extension_dead(extension)
    if not extension then return false end
    if extension.state == "dead" or extension.dead == true then return true end
    if type(extension.is_dead) ~= "function" then return false end
    local ok, dead = pcall(extension.is_dead, extension)
    return ok and dead == true
end

-- Player death is a health/status state transition, not a Unit.alive
-- transition. DeathSystem.set_dead keeps the engine unit and its extensions
-- available while it starts the death reaction.
function M.unit_is_dead(health, status)
    return _extension_dead(health) or _extension_dead(status)
end

function M.evaluate_chain(normalized, stats, base, evaluate)
    if not _finite(base) then return _unsupported(base, "base-unavailable") end
    local final, contributions = base, {}
    for _, stat in ipairs(stats) do
        local source_row = _source_row(normalized, stat)
        if not source_row then return _unsupported(base, "snapshot-truncated") end
        local value = evaluate(source_row, final)
        if not value.supported then
            return _unsupported(base, stat .. ":" .. tostring(value.reason))
        end
        for _, contribution in ipairs(value.contributions or {}) do
            contribution.stat = stat
            contribution.key_text = stat .. "/" .. contribution.key_text
            contributions[#contributions + 1] = contribution
        end
        final = value.final
    end
    return {
        supported = true,
        base = base,
        final = final,
        contributions = contributions,
    }
end

function M.reconcile(value, authoritative, source_label)
    if not value.supported or not _finite(authoritative) then return value end
    local delta = authoritative - value.final
    if math.abs(delta) > 0.000001 then
        value.contributions[#value.contributions + 1] = {
            key_text = "authoritative",
            kind = "unattributed-engine-delta",
            delta = delta,
            source_label = source_label or "authoritative getter",
            sources = {},
        }
    end
    value.final = authoritative
    return value
end

function M.state_value(base, final, source_label)
    if not _finite(base) or not _finite(final) then
        return _unsupported(base, "state-unavailable")
    end
    local contributions = {}
    if math.abs(final - base) > 0.000001 then
        contributions[1] = {
            key_text = "state",
            kind = "authoritative-state",
            delta = final - base,
            source_label = source_label,
            sources = {},
        }
    end
    return {
        supported = true,
        base = base,
        final = final,
        contributions = contributions,
    }
end

function M.action_speed_value(normalized, context, evaluate, is_animation)
    if not context.action_available then
        return _unsupported(context.action_anim_time_scale or 1, "action-unavailable")
    end
    local base = context.action_anim_time_scale or 1
    if context.action_custom_time_scale then
        return _unsupported(base, "function-action-transform")
    end
    local stats = {}
    if context.is_melee then
        stats[#stats + 1] = "attack_speed"
        stats[#stats + 1] = "attack_speed_melee"
    elseif context.is_ranged then
        stats[#stats + 1] = "attack_speed"
    end
    if context.is_drakefire then stats[#stats + 1] = "attack_speed_drakefire" end
    local value = M.evaluate_chain(normalized, stats, base, evaluate)
    if not value.supported then return value end
    if is_animation == nil then is_animation = context.action_is_animation end
    if context.scale_anim_by_charge_time and is_animation == nil
        and not context.scale_chain_window_by_charge_time then
        return _unsupported(base, "charge-time-is_animation-callsite-unobservable")
    end
    local apply_charge_time = context.scale_chain_window_by_charge_time == true
        or context.scale_anim_by_charge_time == true and is_animation == true
    if not apply_charge_time then return value end
    local charge = M.evaluate_chain(normalized, { "reduced_ranged_charge_time" }, 1, evaluate)
    if not charge.supported or not _finite(charge.final) or charge.final == 0 then
        return _unsupported(base, charge.reason or "charge-time-zero")
    end
    local before = value.final
    local sources = {}
    for _, contribution in ipairs(charge.contributions or {}) do
        for _, source in ipairs(contribution.sources or {}) do
            sources[#sources + 1] = source
        end
    end
    value.final = before / charge.final
    value.contributions[#value.contributions + 1] = {
        key_text = "reduced_ranged_charge_time/derived",
        kind = "charge-time-reciprocal",
        delta = value.final - before,
        sources = sources,
    }
    return value
end

function M.critical_value(normalized, context, evaluate)
    local base = context.critical_base
    if not context.action_available then return _unsupported(base, "action-unavailable") end
    if not _finite(base) or not _finite(context.action_additional_crit or 0) then
        return _unsupported(base, "base-unavailable")
    end
    local action_bonus = context.action_additional_crit or 0
    local start = base + action_bonus
    local stats = {
        context.critical_is_melee and "critical_strike_chance_melee"
            or "critical_strike_chance_ranged",
    }
    if context.critical_is_heavy then
        stats[#stats + 1] = "critical_strike_chance_heavy"
    end
    stats[#stats + 1] = "critical_strike_chance"
    local value = M.evaluate_chain(normalized, stats, start, evaluate)
    if not value.supported then
        value.base = base
        return value
    end
    value.base = base
    if action_bonus ~= 0 then
        table.insert(value.contributions, 1, {
            key_text = "action/additional_critical_strike_chance",
            kind = "action-base-bonus",
            delta = action_bonus,
            source_label = "current action settings",
            sources = {},
        })
    end
    return value
end

-- Pinned source c5e4968 generic_status_extension.lua:327-336 derives the
-- unbuffed gauge rate as FATIGUE_POINTS_DEGEN_AMOUNT / max_fatigue_points *
-- MAX_FATIGUE, then applies fatigue_regen and multiplies by dt. The retail
-- constants are 1.5 and 100. The live getter is authoritative because the
-- wielded template and max_fatigue buffs can both change the denominator.
function M.fatigue_regen_value(normalized, context, degen_amount, evaluate)
    local max_fatigue = context and context.max_fatigue
    if not _finite(max_fatigue) or max_fatigue <= 0 then
        return _unsupported(nil, "max-fatigue-unavailable")
    end
    if not _finite(degen_amount) then
        return _unsupported(nil, "fatigue-degen-amount-unavailable")
    end
    local base = degen_amount / max_fatigue * 100
    local source_row = _source_row(normalized, "fatigue_regen")
    if not source_row then return _unsupported(base, "snapshot-truncated") end
    return evaluate(source_row, base)
end

function M.build_rows(normalized, bases, evaluate, localize, context)
    local rows = {}
    for _, spec in ipairs(M.CATALOG) do
        local base = type(spec.base) == "string" and bases[spec.base] or spec.base
        local source_stat = spec.source_stat or spec.stat
        local source_row = _source_row(normalized, source_stat)
            or _empty_row(source_stat)
        local value
        if spec.formula == "attack_speed" then
            value = M.action_speed_value(normalized, context or {}, evaluate,
                spec.action_is_animation)
        elseif spec.formula == "critical" then
            value = M.critical_value(normalized, context or {}, evaluate)
        elseif spec.formula == "fatigue_regen" then
            value = M.fatigue_regen_value(normalized, context or {}, base, evaluate)
        elseif spec.formula == "ability_remaining" then
            value = M.state_value(base, context and context.cooldown_remaining,
                "CareerExtension.current_ability_cooldown")
        elseif spec.formula == "ability_charges" then
            value = M.state_value(base, context and context.ability_ready_charges,
                "CareerExtension.num_charges_ready")
        elseif spec.formula == "unsupported" then
            value = _unsupported(base, spec.reason)
        elseif normalized.truncated and not normalized.by_stat[spec.stat] then
            value = _unsupported(base, "snapshot-truncated")
        else
            value = evaluate(source_row, base)
        end
        if spec.live and context then
            value = M.reconcile(value, context[spec.live],
                spec.consumer .. " (unattributed remainder)")
        end
        rows[#rows + 1] = {
            stat = spec.stat,
            label = localize and localize(spec.label) or spec.stat,
            consumer = spec.consumer,
            display = spec.display,
            method = source_row.method,
            stages = source_row.stages,
            value = value,
        }
    end
    return rows
end

function M.row_text(row)
    local value = row.value or {}
    if value.supported then
        local name = row.display == "factor" and "factor"
            or row.display == "settings" and "settings" or "final"
        return string.format("%s  base=%s  %s=%s", row.label,
            _number(value.base), name, _number(value.final))
    end
    return string.format("%s  base=%s  final=UNSUPPORTED(%s)", row.label,
        _number(value.base), tostring(value.reason or "unknown"))
end

function M.all_lines(snapshot, expanded, text)
    if type(snapshot) ~= "table" then return nil end
    text = text or {}
    local c = snapshot.context or {}
    local lines = {
        text.title or "PLAYER STATS - READ ONLY",
        string.format("%s | %s | %s | template=%s | style=%s",
            tostring(c.career or "?"), tostring(c.slot or "?"),
            tostring(c.item or "?"), tostring(c.template or "?"),
            tostring(c.style or "?")),
        string.format("action=%s/%s | profile=%s",
            tostring(c.action or "idle"), tostring(c.subaction or "-"),
            tostring(c.damage_profile or "-")),
    }
    if snapshot.truncated then
        lines[#lines + 1] = "WARNING: bounded snapshot truncated; absent rows fail closed."
    end
    local visible = expanded and #snapshot.rows or math.min(#snapshot.rows, M.COMPACT_ROWS)
    for i = 1, visible do
        local row = snapshot.rows[i]
        lines[#lines + 1] = M.row_text(row)
        if expanded then
            lines[#lines + 1] = "  consumer=" .. tostring(row.consumer)
            for _, contribution in ipairs(row.value.contributions or {}) do
                lines[#lines + 1] = string.format(
                    "  stage[%s] %s delta=%s src=%s",
                    contribution.key_text, contribution.kind,
                    _number(contribution.delta), _sources(contribution))
            end
            if not row.value.supported and #row.stages > 0 then
                for _, stage in ipairs(row.stages) do
                    lines[#lines + 1] = string.format(
                        "  stage[%s] method=%s src=%s",
                        stage.key_text, row.method,
                        _sources({ sources = stage.sources }))
                end
            end
        end
    end
    if not expanded and #snapshot.rows > visible then
        lines[#lines + 1] = text.compact_more
            or "Expanded mode exposes all rows and contribution stages."
    end
    return lines
end

function M.page(lines, page, text)
    text = text or {}
    local header_count = tonumber(lines.header_count) or 3
    local headers = {}
    for i = 1, header_count do headers[i] = lines[i] end
    local body_count = math.max(0, #lines - header_count)
    local pages = math.max(1, math.ceil(body_count / M.PAGE_ROWS))
    page = math.max(1, math.min(pages, tonumber(page) or 1))
    local first = header_count + 1 + (page - 1) * M.PAGE_ROWS
    local last = math.min(#lines, first + M.PAGE_ROWS - 1)
    local output = {}
    for i = 1, header_count do output[#output + 1] = headers[i] end
    output[#output + 1] = string.format("%s %d/%d | %s",
        text.page or "page", page, pages,
        text.page_help or "/gt_stat_hud_page next|prev|#")
    for i = first, last do output[#output + 1] = lines[i] end
    return output, page, pages
end

function M.layout(line_count, scale_percent, position)
    local scale = math.max(0.75, math.min(1.25, (tonumber(scale_percent) or 100) / 100))
    local width, line_height = 760 * scale, 21 * scale
    local height = ((tonumber(line_count) or 0) * line_height) + 12 * scale
    local margin = 28
    local x = position == "bottom_right" and (1920 - margin - width) or margin
    return {
        x = x,
        top = margin + height,
        width = width,
        height = height,
        line_height = line_height,
        font_size = math.floor(16 * scale + 0.5),
        padding = 6 * scale,
    }
end

function M.max_chars(scale_percent)
    local layout = M.layout(1, scale_percent, "bottom_left")
    return math.max(24, math.floor(
        (layout.width - layout.padding * 2) / math.max(1, layout.font_size)))
end

local function _wrap_line(line, max_chars)
    line = tostring(line or "")
    if #line <= max_chars then return { line } end
    local output, remaining = {}, line
    while #remaining > max_chars do
        local cut = max_chars
        local candidate = remaining:sub(1, max_chars)
        local space = candidate:match("^.*()%s")
        if space and space > math.floor(max_chars * 0.5) then cut = space - 1 end
        output[#output + 1] = remaining:sub(1, cut)
        remaining = remaining:sub(cut + 1):gsub("^%s+", "")
        if #remaining > 0 then remaining = "  " .. remaining end
    end
    if #remaining > 0 then output[#output + 1] = remaining end
    return output
end

function M.wrap_lines(lines, max_chars)
    local output = {}
    local header_count = tonumber(lines and lines.header_count) or 3
    max_chars = math.max(24, tonumber(max_chars) or 48)
    for index, line in ipairs(lines or {}) do
        for _, wrapped in ipairs(_wrap_line(line, max_chars)) do
            output[#output + 1] = wrapped
            if index <= header_count then
                output.header_count = (output.header_count or 0) + 1
            end
        end
    end
    output.header_count = output.header_count or header_count
    return output
end

return M
