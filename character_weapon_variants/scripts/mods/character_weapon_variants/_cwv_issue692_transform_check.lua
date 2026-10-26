-- #692: deterministic production-writer application proof, not a live render
-- or network-surface test. All units and retained state below are detached.
-- No real Unit, player, setting, template, registry or engine flag is modified.
local M = { NAME = "issue692_inverse_transform_application" }

local ROOT = "scripts/mods/character_weapon_variants/"
local OWNER_MODULES = {
    _cwv_transform_consumer_contract = true,
    _lib_weapon_appearance = true,
    _cwv_durable_transform = true,
    _cwv_relative_scale = true,
    _cwv_transform_evidence = true,
    _cwv_crowbill_transform_runtime = true,
}
local OM_LIBRARIES = {
    "greataxe", "crowbill_family", "crowbill_hammer_mode",
    "crowbill_presentation", "husk_transform_policy", "peer_resolver",
    "combat_style_appearance",
}
local function need(value, kind, name)
    assert(type(value) == kind, "#692 dependency missing: " .. name)
    return value
end
local function copy(value)
    local result = {}
    for index, number in ipairs(value) do result[index] = number end
    return result
end
local function near(actual, expected)
    return type(actual) == "number" and actual == actual
        and math.abs(actual - expected) <= 0.000001
end
local function equal(actual, expected, label)
    need(actual, "table", label)
    for index, number in ipairs(expected) do
        assert(near(actual[index], number), "#692 retained " .. label .. " axis " .. index)
    end
end

local function fixture_api()
    local state, writes = {}, 0
    local function owned(unit)
        local row = state[unit]
        assert(row and row.alive, "detached unit unavailable")
        return row
    end
    local function root(node) assert(node == 0, "unexpected detached transform node") end
    local api = {
        vector_new = function(x, y, z) return { x, y, z } end,
        vector_to_elements = function(value) return value[1], value[2], value[3] end,
        quaternion = {
            from_euler_angles_xyz = function() error("#692 authored inverse must not write rotation") end,
        },
        matrix4x4 = { from_quaternion_position_scale = function(rotation, position, scale)
            return { rotation = copy(rotation), position = copy(position), scale = copy(scale) }
        end },
        unit = {
            alive = function(unit) return state[unit] ~= nil and state[unit].alive == true end,
            local_position = function(unit, node) root(node); return copy(owned(unit).position) end,
            local_scale = function(unit, node) root(node); return copy(owned(unit).scale) end,
            local_rotation = function(unit, node) root(node); return copy(owned(unit).rotation) end,
            set_local_pose = function(unit, node, pose)
                root(node)
                local row = owned(unit)
                writes = writes + 1
                row.position, row.scale, row.rotation = copy(pose.position), copy(pose.scale), copy(pose.rotation)
            end,
        },
    }
    local function unit(scale, position, rotation, alive)
        local handle = {}
        state[handle] = { alive = alive ~= false, scale = copy(scale),
            position = copy(position), rotation = copy(rotation) }
        return handle
    end
    return api, unit, state, function() return writes end
end

local function exercise(deps)
    need(deps, "table", "check context")
    local source_mod = need(deps.mod, "table", "CWV owner")
    need(source_mod.dofile, "function", "CWV module loader")
    local live = need(deps.om, "table", "CWV modules")
    local install = need(deps.transform_owner, "function", "production transform owner")
    local policy = need(live.combat_style_policy, "table", "combat style policy")
    need(policy.package, "function", "style package resolver")
    need(policy.encode_style_rider, "function", "style rider encoder")
    local styles = need(live.combat_styles, "table", "authored style runtime")
    need(styles.presentation, "function", "authored presentation resolver")
    local appearance = need(live.combat_style_appearance, "table", "style appearance")
    need(appearance.build, "function", "immutable style builder")
    need(appearance.transform_decision, "function", "immutable transform consumer")
    local descriptor = need(live.appearance_descriptor, "table", "immutable descriptor library")
    need(descriptor.build, "function", "immutable descriptor constructor")
    local base = need(deps.base_item, "table", "native Bretonnian Longsword")
    assert(type(base.right_hand_unit) == "string" and base.right_hand_unit ~= "",
        "#692 native Bretonnian hand unit missing")
    need(deps.find_def, "function", "variant definition resolver")

    local authored = need(styles:presentation("bretonnian_greatsword_inverse"),
        "table", "authored Bretonnian inverse")
    assert(authored.item_key == "cwv_style_bretonnian_greatsword_inverse",
        "#692 wrong authored inverse identity")
    local api, new_unit, retained, write_count = fixture_api()
    local om = { _cwv_key_for_item = function() return nil end }
    for _, name in ipairs(OM_LIBRARIES) do
        om[name] = need(live[name], "table", name)
    end
    local scratch = {
        dofile = function(_, path)
            local name = type(path) == "string" and path:match("/([^/]+)$")
            assert(OWNER_MODULES[name] and path == ROOT .. name,
                "#692 unexpected owner module: " .. tostring(path))
            return need(source_mod:dofile(path), "table", name)
        end,
        get = function() error("#692 unexpected settings read") end,
        set = function() error("#692 unexpected settings write") end,
    }
    install(scratch, {
        om = om, variant_definitions = {}, find_def = deps.find_def,
        custom_illusions = {}, custom_skin_keys = {}, appearance_api = api,
    })
    local writer = need(om.weapon_transform, "table", "detached production writer")
    local apply = need(writer.apply_cwv_hand_transform, "function", "production per-hand apply")
    need(writer.plan_cwv_hand_transform, "function", "production per-hand planner")
    local function build(style_id, presentation)
        local package = need(policy.package("es_bastard_sword", style_id), "table", "style package")
        assert(package.style_id == style_id and package.family_id == "greatsword",
            "#692 style package identity mismatch")
        local key = type(package.presentation) == "table" and package.presentation.transform_key or nil
        assert(style_id == "bretonnian" and key == nil and presentation == nil
            or style_id ~= "bretonnian" and key == "bretonnian_greatsword_inverse"
                and presentation == authored, "#692 style presentation wire disconnected")
        local result, reason = appearance.build({ descriptor = descriptor,
            encode_style_rider = policy.encode_style_rider }, {
            slot_name = "slot_melee",
            row = { item_key = "es_bastard_sword", family_id = package.family_id,
                style_id = style_id, package = package },
            world = { right_hand_unit = base.right_hand_unit },
            base = base, base_item_key = "es_bastard_sword", presentation = presentation,
        })
        assert(result and type(result.fingerprint) == "string", "#692 descriptor build failed: " .. tostring(reason))
        return result
    end
    local rotation = { 0.1, 0.2, 0.3, 0.4 }
    local expected_scale = { 1, 1.25, 1.1111111111111112 }
    local expected_position = { 2, -3, 4.065 }
    local applied_units = 0
    for _, style_id in ipairs({ "greatsword", "kerillian" }) do
        local immutable = build(style_id, authored)
        local def = need(appearance.transform_decision(immutable), "table", "immutable transform definition")
        for _, perspective in ipairs({ "1p", "3p" }) do
            local right = new_unit({ 0.85, 0.95, 1.05 }, { 2, -3, 4 }, rotation)
            local left = new_unit({ 0.7, 0.8, 0.9 }, { -5, 6, -7 }, rotation)
            local before = write_count()
            for _ = 1, 2 do
                apply(right, def, "right", perspective, "detached_issue692")
                equal(retained[right].scale, expected_scale, "right scale")
                equal(retained[right].position, expected_position, "right position")
                equal(retained[right].rotation, rotation, "right rotation")
            end
            assert(write_count() == before + 2, "#692 production writes disconnected or duplicated")
            local stable_writes = write_count()
            apply(left, def, "left", perspective, "detached_issue692")
            equal(retained[left].scale, { 0.7, 0.8, 0.9 }, "offhand scale")
            equal(retained[left].position, { -5, 6, -7 }, "offhand position")
            equal(retained[left].rotation, rotation, "offhand rotation")
            local dead = new_unit({ 1, 1, 1 }, { 2, -3, 4 }, rotation, false)
            apply(dead, def, "right", perspective, "detached_issue692")
            equal(retained[dead].scale, { 1, 1, 1 }, "dead scale")
            equal(retained[dead].position, { 2, -3, 4 }, "dead position")
            apply({}, def, "right", perspective, "detached_issue692")
            apply(nil, def, "right", perspective, "detached_issue692")
            assert(write_count() == stable_writes, "#692 dead/foreign/offhand control wrote a pose")
            applied_units = applied_units + 1
        end
    end
    local native = build("bretonnian", nil)
    assert(appearance.transform_decision(native) == false, "#692 native style unexpectedly transforms")
    local native_unit = new_unit({ 0.6, 1.2, 0.4 }, { -2, 3, -4 }, rotation)
    local before = write_count()
    apply(native_unit, false, "right", "3p", "detached_issue692")
    equal(retained[native_unit].scale, { 0.6, 1.2, 0.4 }, "native scale")
    equal(retained[native_unit].position, { -2, 3, -4 }, "native position")
    equal(retained[native_unit].rotation, rotation, "native rotation")
    assert(write_count() == before and applied_units == 4, "#692 native control or application matrix incomplete")
    return { scope = "detached_production_writer", transformed_units = applied_units,
        retained_writes = write_count(), live_surfaces_verified = false }
end

function M.run(deps)
    local ok, result = pcall(exercise, deps)
    if not ok then return tostring(result) end
    return nil, result
end

function M.register(mod, ctx, _om, _find_def, _rt_register)
_rt_register("issue692_inverse_transform_application", function()
	-- Detached numeric application only. PR #1728 separately tests consumer
	-- wiring; live frames, transitions and remote peers remain acceptance work.
	local check = ctx.issue692_check
	if type(check) ~= "table" or type(check.run) ~= "function" then
		return "#692 deterministic application check owner missing"
	end
	return check.run({ mod = mod, om = _om, find_def = _find_def,
		transform_owner = ctx.issue692_transform_owner, base_item = ctx.issue692_base_item })
end)
end

return M
