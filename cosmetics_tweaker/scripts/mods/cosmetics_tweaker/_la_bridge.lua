--[[
LA bridge — exposes Loremaster's Armoury cosmetic recolors as separate items
in the native VT2 inventory via MoreItemsLibrary.

LA's normal mode mutates a vanilla item's textures in-place (e.g. equipping
"Pureheart Helm" silently shows whichever color the user picked in LA's vmf
settings). This bridge instead clones each LA cosmetic variant as its own
inventory item, so the player can have "Pureheart Yellow" and "Pureheart White"
both selectable side-by-side without LA's overwrite.

Pipeline:
  1. At init: iterate LA.SKIN_LIST, filter for swap_hand in {"hat", "armor"},
     match each variant's new_units[1] back to a vanilla ItemMasterList key,
     clone that IML entry under a unique backend_id, register via MIL.
  2. On unit spawn (AttachmentUtils.link, HeroPreviewer._spawn_item_unit):
     check whether the equipped item for the relevant slot is one of our
     clones; if so, push the unit into LA's level_queue / preview_queue with
     the corresponding Armoury_key. LA's existing mod.update() then performs
     the actual texture swap.
]]

local mod = get_mod("cosmetics_tweaker")

local M = {}

M.registered            = false
M.backend_to_armoury    = {}  -- our backend_id -> LA Armoury_key
M.backend_to_vanilla    = {}  -- our backend_id -> vanilla skin key (LA expects this as `skin` arg)
M.unit_path_to_clones   = {}  -- vanilla unit path -> list of our backend_ids targeting it
M.armoury_to_backend    = {}  -- reverse: LA key -> our backend_id (for debug)
M.localization          = {}  -- display_name_key -> human-readable string

local function la()  return get_mod("Loremasters-Armoury") end
local function mil() return get_mod("MoreItemsLibrary") end

local _character_prefixes = {
    Kruber = true, Bardin = true, Sienna = true, Saltzpyre = true,
    Kerillian = true, Victor = true, Markus = true,
}

local function humanize_armoury_key(la_key)
    local parts = {}
    for word in la_key:gmatch("[^_]+") do
        parts[#parts + 1] = word
    end
    if #parts > 0 and _character_prefixes[parts[1]] then
        table.remove(parts, 1)
    end
    for i, word in ipairs(parts) do
        parts[i] = word:sub(1, 1):upper() .. word:sub(2):lower()
    end
    return table.concat(parts, " ")
end

-- Build vanilla unit-path -> ItemMasterList key index
local function build_unit_index()
    local idx = {}
    for key, entry in pairs(ItemMasterList) do
        if type(entry) == "table" and type(entry.unit) == "string" then
            -- prefer first-seen; if collisions happen we'll log
            if not idx[entry.unit] then idx[entry.unit] = key end
        end
    end
    return idx
end

local function pick_vanilla_key(la_variant, unit_index)
    if type(la_variant.new_units) ~= "table" then return nil end
    for _, unit_path in ipairs(la_variant.new_units) do
        local k = unit_index[unit_path]
        if k then return k, unit_path end
    end
    return nil
end

local function build_clone_entry(vanilla_key, la_key, suffix_id)
    local original = ItemMasterList[vanilla_key]
    if not original then return nil end
    local entry = table.clone(original)

    entry.key = suffix_id
    entry.name = suffix_id
    entry.cos_la_armoury_key = la_key
    entry.cos_la_vanilla_key = vanilla_key

    local name_key = suffix_id .. "_name"
    entry.display_name = name_key
    local readable = humanize_armoury_key(la_key)
    M.localization[name_key] = readable .. " (LA)"

    entry.rarity = "exotic"

    ItemMasterList[suffix_id] = entry

    entry.mod_data = {
        backend_id     = suffix_id,
        ItemInstanceId = suffix_id,
        CustomData     = { rarity = "exotic" },
        rarity         = "exotic",
    }

    return entry, suffix_id
end

function M.register_all()
    if M.registered then return end
    if not la() or not mil() then
        mod:info("[LA bridge] LA or MIL not present; skipping registration")
        return
    end
    if not ItemMasterList then return end
    if type(la().SKIN_LIST) ~= "table" then return end

    local unit_index = build_unit_index()
    local entries_to_register = {}
    local registered, skipped = 0, {}

    for la_key, variant in pairs(la().SKIN_LIST) do
        local hand = variant.swap_hand
        if hand == "hat" or hand == "armor" then
            local vanilla_key, unit_path = pick_vanilla_key(variant, unit_index)
            if vanilla_key then
                local backend_id = vanilla_key .. "_LA_" .. la_key
                local entry = build_clone_entry(vanilla_key, la_key, backend_id)
                if entry then
                    table.insert(entries_to_register, entry)
                    M.backend_to_armoury[backend_id] = la_key
                    M.backend_to_vanilla[backend_id] = vanilla_key
                    M.armoury_to_backend[la_key]     = backend_id
                    M.unit_path_to_clones[unit_path] = M.unit_path_to_clones[unit_path] or {}
                    table.insert(M.unit_path_to_clones[unit_path], backend_id)
                    registered = registered + 1
                end
            else
                table.insert(skipped, la_key)
            end
        end
    end

    if #entries_to_register > 0 then
        mil():add_mod_items_to_local_backend(entries_to_register, "cosmetics_tweaker")

        if NetworkLookup and NetworkLookup.item_names then
            for _, entry in ipairs(entries_to_register) do
                local key = entry.key or entry.name
                if key and not rawget(NetworkLookup.item_names, key) then
                    local idx = #NetworkLookup.item_names + 1
                    rawset(NetworkLookup.item_names, idx, key)
                    rawset(NetworkLookup.item_names, key, idx)
                end
            end
        end
    end

    M.registered = true
    mod:info("[LA bridge] registered %d items, skipped %d (no vanilla unit match)", registered, #skipped)
    if #skipped > 0 then mod:info("[LA bridge] skipped: %s", table.concat(skipped, ", ")) end
end

-- Find any equipped clone for the given vanilla unit path. Returns
-- (backend_id, armoury_key, vanilla_key) or nil.
-- Walks the per-career loadout for ALL careers, since LA's hooks fire across
-- world units that may not belong to the local player (e.g. preview pawns).
local function find_active_clone_for_unit_path(unit_path)
    local clones = M.unit_path_to_clones[unit_path]
    if not clones then return nil end
    if not Managers.backend then return nil end
    local items_iface = Managers.backend:get_interface("items")
    if not items_iface then return nil end

    local loadout = items_iface:get_loadout()
    if type(loadout) ~= "table" then return nil end

    for _, slots in pairs(loadout) do
        if type(slots) == "table" then
            for _, equipped_id in pairs(slots) do
                for _, our_id in ipairs(clones) do
                    if equipped_id == our_id then
                        return our_id, M.backend_to_armoury[our_id], M.backend_to_vanilla[our_id]
                    end
                end
            end
        end
    end
    return nil
end

M.trace = false  -- set true via `cos la_trace 1` to log every hook firing
M._bridge_active = false
M._gate_installed = false

function M.install_apply_gate()
    if M._gate_installed then return end
    local LA = la()
    if not LA or not LA.apply_new_skin_from_texture then return end
    M._gate_installed = true

    local original_apply = LA.apply_new_skin_from_texture
    M._original_apply = original_apply
    LA.apply_new_skin_from_texture = function(armoury_key, world, skin, unit)
        if M.armoury_to_backend[armoury_key] and not M._bridge_active then
            if M.trace then mod:info("[LA bridge] GATE blocked managed key %s", armoury_key) end
            return
        end
        if M.trace then mod:info("[LA bridge] GATE allowed %s (bridge_active=%s)", armoury_key, tostring(M._bridge_active)) end
        return original_apply(armoury_key, world, skin, unit)
    end
    mod:info("[LA bridge] apply gate installed (raw replacement)")
end

local function suppress_la_queue(unit)
    local LA = la()
    if not LA then return end
    if LA.level_queue then LA.level_queue[unit] = nil end
    if LA.preview_queue then LA.preview_queue[unit] = nil end
    if LA.armory_preview_queue then LA.armory_preview_queue[unit] = nil end
    if M.trace then mod:info("[LA bridge]   suppressed LA queues for vanilla hat") end
end

local function apply_direct(world, unit, armoury_key, vanilla_key, label)
    local LA = la()
    if not LA then return false end
    if not LA.SKIN_LIST or not LA.SKIN_LIST[armoury_key] then return false end

    if LA.apply_new_skin_from_texture then
        LA.SKIN_LIST[armoury_key].swap_skin = vanilla_key or LA.SKIN_LIST[armoury_key].swap_skin
        M._bridge_active = true
        local ok, err = pcall(LA.apply_new_skin_from_texture, armoury_key, world, vanilla_key, unit)
        M._bridge_active = false
        if M.trace then mod:info("[LA bridge]   %s applied %s direct ok=%s", label or "direct", armoury_key, tostring(ok)) end
        if ok then
            suppress_la_queue(unit)
            return true
        end
    end

    local payload = { Armoury_key = armoury_key, skin = vanilla_key }
    local routed = "level_queue"
    if Managers.world:has_world("level_world") and world == Managers.world:world("level_world") then
        LA.level_queue[unit] = payload
    elseif Managers.world:has_world("character_preview") and world == Managers.world:world("character_preview") then
        LA.preview_queue[unit] = payload; routed = "preview_queue"
    elseif Managers.world:has_world("armory_preview") and world == Managers.world:world("armory_preview") then
        LA.armory_preview_queue[unit] = payload; routed = "armory_preview_queue"
    else
        LA.level_queue[unit] = payload; routed = "level_queue (fallback)"
    end
    if M.trace then mod:info("[LA bridge]   %s queued %s on %s (direct failed)", label or "direct", armoury_key, routed) end
    return true
end

function M.queue_unit_direct(world, unit, backend_id)
    local armoury_key = M.backend_to_armoury[backend_id]
    local vanilla_key = M.backend_to_vanilla[backend_id]
    if not armoury_key then return false end
    return apply_direct(world, unit, armoury_key, vanilla_key, backend_id)
end

function M.suppress_orphan(unit)
    if not M.registered then return end
    local LA = la()
    if not LA then return end
    for _, queue in ipairs({LA.preview_queue, LA.armory_preview_queue, LA.level_queue}) do
        if queue and queue[unit] then
            local ak = queue[unit].Armoury_key
            if ak and M.armoury_to_backend[ak] then
                queue[unit] = nil
                if M.trace then mod:info("[LA bridge]   suppress_orphan cleared %s", ak) end
            end
        end
    end
end

function M.maybe_queue_unit(world, unit, unit_name)
    if M.trace then mod:info("[LA bridge] hook fired unit_name=%s", tostring(unit_name)) end
    if not (unit and unit_name) then return false end
    if not M.registered then return false end

    local clones = M.unit_path_to_clones[unit_name]
    if not clones then return false end

    if M.trace then mod:info("[LA bridge] hit unit_name=%s (%d clones target it)", unit_name, #clones) end

    local backend_id, armoury_key, vanilla_key = find_active_clone_for_unit_path(unit_name)
    if not armoury_key then
        if M.trace then mod:info("[LA bridge]   no clone equipped for this unit path") end
        suppress_la_queue(unit)
        return false
    end

    return apply_direct(world, unit, armoury_key, vanilla_key, backend_id)
end

-- Walk a unit and any of its attachments / equipped slots, calling visit(unit, depth).
-- Best-effort across all extension types we know carry attachments.
local function walk_attachments(root, visit)
    if type(root) ~= "userdata" or not Unit.alive(root) then return end
    local seen = {}
    local function rec(u, depth)
        if depth > 6 then return end
        if seen[u] then return end
        seen[u] = true
        visit(u, depth)
        if type(u) ~= "userdata" then return end
        -- attachment_system
        if ScriptUnit.has_extension(u, "attachment_system") then
            local ext = ScriptUnit.extension(u, "attachment_system")
            if ext and ext._attachments then
                for _, child in pairs(ext._attachments) do
                    if type(child) == "userdata" and Unit.alive(child) then rec(child, depth + 1) end
                end
            end
        end
        -- inventory_system slot_hat
        if ScriptUnit.has_extension(u, "inventory_system") then
            local ext = ScriptUnit.extension(u, "inventory_system")
            local slots = ext and ext._equipment and ext._equipment.slots
            if slots then
                for slot_name, slot in pairs(slots) do
                    for k, v in pairs(slot or {}) do
                        if type(v) == "userdata" and Unit.alive(v) then rec(v, depth + 1) end
                    end
                end
            end
        end
    end
    rec(root, 0)
end

-- Force-apply a specific LA variant to the player's currently spawned hat unit.
-- Bypasses our detection logic entirely — confirms whether the LA pipeline
-- itself is working. Usage: cos la_force Kruber_Pureheart_helm_white
function M.force_apply(armoury_key)
    local LA = la()
    if not LA then mod:echo("[la_force] LA not loaded"); return end
    if not LA.SKIN_LIST or not LA.SKIN_LIST[armoury_key] then
        mod:echo("[la_force] unknown armoury_key: " .. tostring(armoury_key)); return
    end

    local target_unit_name = LA.SKIN_LIST[armoury_key].new_units and LA.SKIN_LIST[armoury_key].new_units[1]
    mod:echo("[la_force] looking for unit with unit_name=" .. tostring(target_unit_name))

    local p = Managers.player and Managers.player:local_player()
    local pu = p and p.player_unit
    if not pu then mod:echo("[la_force] no player_unit"); return end

    local found = nil
    walk_attachments(pu, function(u, depth)
        local name = (Unit.has_data(u, "unit_name") and Unit.get_data(u, "unit_name")) or "<no_unit_name>"
        local skin = (Unit.has_data(u, "skin_name") and Unit.get_data(u, "skin_name")) or "-"
        local hand = (Unit.has_data(u, "hand_unit") and Unit.get_data(u, "hand_unit")) or "-"
        mod:info("[la_force]   d=%d unit_name=%s skin=%s hand=%s", depth, name, tostring(skin), tostring(hand))
        if name == target_unit_name and not found then found = u end
    end)

    if not found then mod:echo("[la_force] no unit matched; see log for full attachment dump"); return end

    local world = Managers.world:world("level_world")
    -- LA needs `skin` arg to identify which IML/WeaponSkins icon to swap; pass
    -- the vanilla key derived from the unit_name index.
    local vanilla_key = nil
    for k, e in pairs(ItemMasterList) do
        if type(e) == "table" and e.unit == target_unit_name then vanilla_key = k; break end
    end
    LA.level_queue[found] = { Armoury_key = armoury_key, skin = vanilla_key }
    mod:echo("[la_force] queued " .. armoury_key .. " for " .. tostring(vanilla_key) .. " on found unit; LA update should apply next tick")
end

-- Diagnostic: walk player and dump every attachment with its unit_name/skin/hand
function M.dump_player_attachments()
    local p = Managers.player and Managers.player:local_player()
    local pu = p and p.player_unit
    if not pu then mod:echo("no player_unit"); return end
    mod:echo("[dump] player attachments (see log):")
    walk_attachments(pu, function(u, depth)
        local name = (Unit.has_data(u, "unit_name") and Unit.get_data(u, "unit_name")) or "<no_unit_name>"
        local skin = (Unit.has_data(u, "skin_name") and Unit.get_data(u, "skin_name")) or "-"
        local hand = (Unit.has_data(u, "hand_unit") and Unit.get_data(u, "hand_unit")) or "-"
        mod:info("[dump]   d=%d unit_name=%s skin=%s hand=%s", depth, name, tostring(skin), tostring(hand))
    end)
end

-- Diagnostic: dump the registry to console
function M.debug_dump()
    mod:echo("[LA bridge] %d clones registered", (function()
        local n = 0; for _ in pairs(M.backend_to_armoury) do n = n + 1 end; return n
    end)())
    for backend_id, armoury_key in pairs(M.backend_to_armoury) do
        mod:info("  %s  ->  %s", backend_id, armoury_key)
    end
end

return M
