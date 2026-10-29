-- Exact identity descriptor planning. No hook, RPC, render, persistence or
-- delivery state ownership. The transport and detached runtime check use the
-- same local/remote callbacks; supplied registries remain dynamically read.
local M = {}
local NATIVE_TYPES = {
    es_sword_shield = "es_1h_sword_shield",
    es_sword_shield_breton = "es_1h_sword_shield_breton",
}
local NATIVE_DONORS = {
    es_sword_shield = true, es_sword_shield_breton = true, es_deus_01 = true,
}
local function read(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, value = pcall(fn, ...)
    return ok and value or nil
end
local function field(row, key)
    return type(row) == "table" and rawget(row, key) or nil
end
function M.new(ctx)
    local _om = assert(ctx.om)
    local retained = assert(ctx.retained)
    local find_def = assert(ctx.find_def)
    local function cosmetics()
        if type(ctx.get_mod) ~= "function" then return nil, "absent" end
        local ok, value = pcall(ctx.get_mod, "cosmetics_tweaker")
        if not ok then return nil, "provider_lookup_error" end
        return value, value and "present" or "absent"
    end
    local function native_offhand_unit(item_key, item_type, hand, skin)
        if NATIVE_TYPES[item_key] ~= item_type or not NATIVE_TYPES[item_key]
                or hand ~= "left_hand_unit" then return nil end
        local cos = cosmetics()
        local api = field(field(cos, "_cos"), "cwv_native_shield_identity")
        if field(api, "schema") ~= 1 then return nil end
        local proof = read(field(api, "admit"), item_key, item_type, hand, skin)
        if field(proof, "schema") ~= 1 or field(proof, "item_key") ~= item_key
                or field(proof, "item_type") ~= item_type or field(proof, "hand") ~= hand
                or field(proof, "skin_key") ~= skin then return nil end
        local items, skins = read(ctx.get_item_master), read(ctx.get_weapon_skins)
        local base, item, row = field(items, item_key), field(items, skin), field(skins, skin)
        local source = field(proof, "source_item_key")
        local unit = field(proof, "unit")
        if field(base, "item_type") ~= item_type or not NATIVE_DONORS[source]
                or field(item, "cwv_owner_item_type") ~= nil
                or field(item, "item_type") ~= "weapon_skin"
                or field(item, "matching_item_key") ~= source
                or type(unit) ~= "string" or unit == ""
                or field(row, hand) ~= unit
                or (field(item, hand) and field(item, hand) ~= unit) then return nil end
        return unit
    end
    local function native_world(item_key, base_item_key, skin, instance_id, offhand_skin)
        local items, skins = read(ctx.get_item_master), read(ctx.get_weapon_skins)
        local base = field(items, base_item_key)
        if type(base) ~= "table" or item_key ~= base_item_key then
            return nil, base, "native_base_mismatch"
        end
        local selected = skin ~= "" and skin ~= "n/a" and skin or nil
        local descriptor, reason = _om.exact_appearance.resolve_spawn_descriptor({
            provider = "cwv_style_world", instance_id = instance_id,
            variant = { item_key = item_key, base_weapon = base_item_key,
                right_hand_unit = base.right_hand_unit, left_hand_unit = base.left_hand_unit },
            base = base, base_item_key = base_item_key, fallback_item_key = base_item_key,
            explicit_skin = selected, explicit_offhand_skin = offhand_skin,
            weapon_skins = skins, item_master = items,
            native_offhand_unit = native_offhand_unit,
        })
        return descriptor, base, reason
    end
    local function style_descriptor(item_data, slot_name, skin, row,
            base_item_key, instance_id, offhand_skin)
        if type(row) ~= "table"
                or not _om.combat_style_appearance.supports_family(row.family_id) then
            return nil, "family_not_migrated"
        end
        local def = find_def(row.item_key)
        local world, base, reason
        if def and not def.skin_only then
            base = field(read(ctx.get_item_master), def.base_weapon)
            world, _, reason = _om._cwv_resolve_world_descriptor(
                item_data or { name = def.base_weapon }, skin, nil,
                def.item_key, instance_id, offhand_skin)
            base_item_key = def.base_weapon
        else
            world, base, reason = native_world(row.item_key, base_item_key,
                skin, instance_id, offhand_skin)
        end
        if not world or type(base) ~= "table" then
            return nil, reason or "world_unavailable"
        end
        local transform_key = type(row.package.presentation) == "table"
            and row.package.presentation.transform_key or nil
        local presentation = transform_key and _om.combat_styles
            and _om.combat_styles:presentation(transform_key) or nil
        return _om.combat_style_appearance.build({ descriptor = _om.appearance_descriptor,
            package_for = function(key, style) return _om.combat_styles and _om.combat_styles:package(key, style) end,
            encode_style_rider = _om.combat_style_policy.encode_style_rider }, {
            slot_name = slot_name, row = row, world = world, base = base,
            base_item_key = base_item_key, presentation = presentation,
        })
    end
    local function committed_offhand(backend_id, item_key, native)
        local cos, state = cosmetics()
        if native and state ~= "absent" and not cos then return nil, state end
        local provider = field(field(cos, "_cos"), "cwv_offhand_identity")
        if type(provider) ~= "function" or not backend_id then
            return nil, native and cos and "provider_unready" or "follow_main"
        end
        local item_type = item_key
        if native then
            item_type = field(field(read(ctx.get_item_master), item_key), "item_type")
            if item_type ~= NATIVE_TYPES[item_key] then return nil, "native_target" end
        end
        local ok, value, reason = pcall(provider, backend_id, item_type, "left_hand_unit")
        if not ok then return nil, "provider_error" end
        if type(value) == "string" and value ~= "" then
            if native and reason ~= "committed" then return nil, "provider_state" end
            return value, "committed"
        end
        return nil, reason or "follow_main"
    end
    local planner = {}
    function planner.resolve_local(slot_data, slot_name)
        retained[slot_name] = nil
        local item_data = slot_data and slot_data.item_data
        local base_name = item_data and item_data.name
        if not item_data then return nil, base_name end
        local backend_id = item_data.backend_id
            or (item_data.mod_data and item_data.mod_data.backend_id)
        local style_row = _om.combat_styles
            and _om.combat_styles:describe(item_data, backend_id) or nil
        if style_row and _om.combat_style_appearance.supports_family(style_row.family_id) then
            local native = style_row.family_id == "sword_shield"
            local offhand_skin, offhand_state
            if native then offhand_skin, offhand_state = committed_offhand(backend_id, style_row.item_key, true)
            else offhand_state = "follow_main" end
            local descriptor, reason
            if native and not offhand_skin and offhand_state ~= "follow_main" then
                reason = offhand_state
            else
                descriptor, reason = style_descriptor(item_data, slot_name, slot_data.skin,
                    style_row, base_name, backend_id, offhand_skin)
            end
            if descriptor then
                retained[slot_name] = { identity = style_row.identity, descriptor = descriptor }
                return descriptor, base_name
            end
            pcall(ctx.printf,
                "[cwv:660] lifecycle=identity_plan adapter=style_descriptor slot=%s item=%s state=DECLINED reason=%s",
                tostring(slot_name), tostring(style_row.item_key), tostring(reason))
            return nil, base_name
        end
        local key = _om._cwv_key_for_item(backend_id, item_data)
        if not key then return nil, base_name end
        local offhand_skin = committed_offhand(backend_id, key, false)
        local skin = slot_data.skin
        return _om._cwv_resolve_world_descriptor(item_data, skin,
            nil, key, backend_id, offhand_skin), base_name
    end
    function planner.resolve_remote(payload, sender_peer_id)
        if payload.provider == _om.combat_style_appearance.PROVIDER then
            local family_id, style_id = _om.combat_style_policy.decode_style_rider(payload.style)
            local member_family = _om.combat_style_policy.member(payload.item_key)
            if not _om.combat_style_appearance.supports_family(family_id)
                    or member_family ~= family_id then return nil, "style_identity" end
            local package
            if _om.combat_style_policy.is_sword_item(payload.item_key) then
                local runtime = _om.combat_styles
                if not runtime or type(runtime.remote_actor_admitted) ~= "function"
                        or not runtime:remote_actor_admitted(sender_peer_id, payload.slot,
                            payload.item_key, family_id, style_id) then
                    return nil, "actor unavailable"
                end
                package = type(runtime.package) == "function"
                    and runtime:package(payload.item_key, style_id) or nil
            else
                -- Existing non-Sword families keep their original policy-only
                -- package path; Sword's new constructor is not their authority.
                package = _om.combat_style_policy.package(payload.item_key, style_id)
            end
            if not package or package.style_id ~= style_id then return nil, "style_package" end
            local row = { item_key = payload.item_key, family_id = family_id,
                style_id = style_id, package = package }
            return style_descriptor({ name = payload.base_item_key }, payload.slot,
                payload.skin_key, row, payload.base_item_key,
                tostring(sender_peer_id) .. ":" .. tostring(payload.slot), payload.offhand_skin_key)
        end
        local def = type(payload.item_key) == "string" and find_def(payload.item_key)
        if not def or def.skin_only or def.base_weapon ~= payload.base_item_key then
            return nil, "item_or_base"
        end
        local skin = payload.skin_key ~= "" and payload.skin_key or nil
        local offhand_skin = payload.offhand_skin_key ~= "" and payload.offhand_skin_key or nil
        local descriptor, _, reason = _om._cwv_resolve_world_descriptor(
            { name = def.base_weapon }, skin, nil, def.item_key,
            tostring(sender_peer_id) .. ":" .. tostring(payload.slot), offhand_skin)
        return descriptor, reason
    end
    return planner
end
-- Detached installed-planner check. The real committed-state owner is covered
-- by offline installed-owner tests; this check never writes a fake save, live
-- retained slot, peer ledger, RPC or engine object. Registry data is read-only.
function M.check_native_shield(ctx)
    local installed = ctx.om
    local items, skins = read(ctx.get_item_master), read(ctx.get_weapon_skins)
    if not field(items, "es_sword_shield") or not field(skins, "es_1h_sword_shield_skin_01") then
        return "#657 native Sword-and-Shield source rows unavailable"
    end
    local cos
    if type(ctx.get_mod) == "function" then
        local ok, value = pcall(ctx.get_mod, "cosmetics_tweaker")
        if not ok then return "#657 native Cosmetics provider lookup unreadable" end
        cos = value
    end
    local api = field(field(cos, "_cos"), "cwv_native_shield_identity")
    local has_native = field(api, "schema") == 1 and type(field(api, "admit")) == "function"
    if cos and not has_native then return "#657 native Cosmetics admission capability unavailable" end
    local offhand = has_native and "es_1h_sword_shield_skin_02" or nil
    local private = {}
    for key, value in pairs(installed) do private[key] = value end
    private.combat_styles = {
        describe = function(_, item)
            return { item_key = item.name, identity = "issue657-detached",
                family_id = "sword_shield", style_id = "empire",
                package = private.combat_style_policy.package(item.name, "empire") }
        end,
    }
    private._cwv_key_for_item = function() return nil end
    local detached_cos = { _cos = {
        cwv_native_shield_identity = api,
        cwv_offhand_identity = function(_, item_type, hand)
            if item_type ~= "es_1h_sword_shield" or hand ~= "left_hand_unit" then
                return nil, "native_target"
            end
            return offhand, offhand and "committed" or "follow_main"
        end,
    } }
    local planner = M.new({ om = private, retained = {}, find_def = function() return nil end,
        get_mod = function() return has_native and detached_cos or nil end,
        get_item_master = ctx.get_item_master, get_weapon_skins = ctx.get_weapon_skins,
        printf = function() end })
    local policy = private.appearance_lifecycle_policy
    local lifecycle = policy.new({resolve_local=planner.resolve_local,resolve_remote=planner.resolve_remote})
    local payload = lifecycle:payload_for("slot_melee", {
        item_data = { name = "es_sword_shield", backend_id = "issue657-detached" },
        skin = "es_1h_sword_shield_skin_01",
    })
    if not payload or payload.provider ~= private.combat_style_appearance.PROVIDER
            or payload.offhand_skin_key ~= (offhand or "") then
        return "#657 installed native planner lost primary/offhand source identity"
    end
    local _, remote, reason = lifecycle:accept("issue657-detached", policy.SCHEMA, payload)
    if not remote or reason ~= "exact" or remote.fingerprint ~= payload.fingerprint then
        return "#657 installed native receiver did not reconstruct exact source identity"
    end
    if offhand and (not remote.left_hand_unit
            or remote.left_hand_unit.unit ~= field(field(skins, offhand), "left_hand_unit")) then
        return "#657 installed native receiver lost committed left component"
    end
    local altered = {}
    for key, value in pairs(payload) do altered[key] = value end
    altered.offhand_skin_key = "foreign_skin"
    local _, rejected = lifecycle:accept("issue657-detached-tamper", policy.SCHEMA, altered)
    if rejected then return "#657 installed native receiver accepted a foreign offhand" end
end
return M
