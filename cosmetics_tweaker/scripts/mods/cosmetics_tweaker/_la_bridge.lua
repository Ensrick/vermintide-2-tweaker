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

-- Shield/offhand options derived from LA SKIN_LIST entries with
-- swap_hand="left_hand_unit". Grouped by character prefix (Kruber/
-- Kerillian/Bardin) so the main file can fan them out across all of
-- that character's shield weapon types per the no-cross-character /
-- yes-cross-career-within-character rule.
--   { Kruber = { {name=..., armoury_key=..., vanilla_skin=...}, ... }, ... }
M.la_offhand_options_by_character = {}

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

local function build_clone_entry(vanilla_key, la_key, suffix_id, name_override)
    local original = ItemMasterList[vanilla_key]
    if not original then return nil end
    local entry = table.clone(original)

    entry.key = suffix_id
    entry.name = name_override or suffix_id
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

-- Parse `swap_hand="left_hand_unit"` entries into per-character lists.
-- We group by the character prefix in the LA key (Kruber/Kerillian/Bardin)
-- so the main file can fan each character's pool across all of that
-- character's shield-bearing weapon types — implementing the no-cross-
-- character / yes-cross-career-within-character rule.
--
-- We extract a representative vanilla skin key from the variant's `icons`
-- table to use as LA's `skin` arg when calling apply_new_skin_from_texture.
-- Diagnostic snapshot of how each LA shield variant resolved its target mesh.
M._la_offhand_resolution = {}

-- LA's SKIN_LIST entries explicitly declare their target shield mesh in
-- `variant.new_units[1]`. That's the SOURCE OF TRUTH — texture-path parsing
-- and icon-key heuristics are unreliable. For `kind="texture"` variants (the
-- vast majority of shields), `new_units[1]` is the vanilla mesh LA paints
-- textures onto. For `kind="unit"` variants, `new_units[1]` is LA's own
-- custom-authored mesh.
local function _resolve_intended_unit(la_key, variant, sorted_icons)
    if type(variant.new_units) == "table" and variant.new_units[1] then
        return variant.new_units[1], "new_units"
    end
    -- Pure-texture variant (no new_units): don't override the mesh. LA's
    -- diffuse will paint onto whichever shield the user's current illusion
    -- spawns. Works fine for Bret variants (all GK-family shields), and
    -- safer than guessing — the lex-first-icon heuristic produced visibly
    -- wrong results in earlier versions.
    return nil, "no_override"
end

-- Decide whether an LA variant is safe to expose in our offhand picker.
-- `kind="unit"` variants point to LA's custom-authored mesh files (e.g.
-- `units/empire_shield/Kruber_Empire_shield01_mesh`) that have no
-- standalone package the LootItemUnitPreviewer can load on demand —
-- spawning one crashes with "Unit not found". LA's normal pipeline
-- pre-loads them via `Managers.package:load(...)` from its own bootstrap.
-- For now, restrict to `kind="texture"` variants, which paint onto a
-- vanilla mesh that the engine already has packaged.
--
-- For `kind="texture"` variants:
--   * if `new_units[1]` exists AND `is_vanilla_unit == true`, that's the
--     vanilla mesh LA expects to paint onto -> use it as `intended_unit`
--   * else (pure-texture variant, no mesh swap) -> `intended_unit = nil`,
--     leaving the user's current shield in place; LA paints over it.
local function _is_supported_variant(variant)
    if variant.kind ~= "texture" then return false end
    -- Defensive: if a variant declares new_units but isn't marked as
    -- vanilla, treat it as a custom mesh and skip — the previewer would
    -- crash trying to spawn it.
    if variant.new_units and not variant.is_vanilla_unit then return false end
    return true
end

local function build_offhand_options()
    M.la_offhand_options_by_character = {}
    M._la_offhand_resolution = {}
    local SKIN_LIST = la().SKIN_LIST
    for la_key, variant in pairs(SKIN_LIST) do
        if variant.swap_hand == "left_hand_unit" and _is_supported_variant(variant) then
            local character = la_key:match("^([A-Z][a-z]+)_")
            if character and _character_prefixes[character] then
                local sorted_icons = {}
                if type(variant.icons) == "table" then
                    for icon_key, _ in pairs(variant.icons) do
                        sorted_icons[#sorted_icons + 1] = icon_key
                    end
                    table.sort(sorted_icons)
                end
                local vanilla_skin_key = sorted_icons[1]
                local intended_unit, source = _resolve_intended_unit(la_key, variant, sorted_icons)
                M._la_offhand_resolution[la_key] = {
                    intended_unit = intended_unit,
                    source        = source,
                    texture_path  = (variant.textures and variant.textures[1]) or nil,
                    icon_keys     = sorted_icons,
                }
                local list = M.la_offhand_options_by_character[character]
                if not list then list = {}; M.la_offhand_options_by_character[character] = list end
                list[#list + 1] = {
                    name          = humanize_armoury_key(la_key),
                    armoury_key   = la_key,
                    vanilla_skin  = vanilla_skin_key,
                    intended_unit = intended_unit,
                }
            end
        end
    end
end

-- Diagnostic: dump LA shield variant -> resolved intended_unit mapping, with
-- the source (texture_hint vs first_icon) and the texture path. Use this to
-- find variants whose intended_unit is wrong and add new patterns to
-- _texture_mesh_hints (or a manual override table).
function M.dump_offhand_resolution()
    if not M._la_offhand_resolution then mod:echo("no resolution data"); return end
    mod:echo("[LA bridge] offhand resolution:")
    for la_key, info in pairs(M._la_offhand_resolution) do
        mod:info("  %-50s -> %s [%s]  tex=%s",
            la_key,
            tostring(info.intended_unit),
            tostring(info.source),
            tostring(info.texture_path))
    end
    mod:echo("[LA bridge] %d variants — see log for full mapping",
        (function() local n = 0; for _ in pairs(M._la_offhand_resolution) do n = n + 1 end; return n end)())
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

            if not vanilla_key and hand == "armor" and variant.cosmetic_key then
                vanilla_key = variant.cosmetic_key
                if not rawget(ItemMasterList, vanilla_key) then vanilla_key = nil end
                if vanilla_key and variant.new_units and variant.new_units[1] then
                    unit_path = variant.new_units[1]
                end
            end

            if vanilla_key then
                local backend_id = vanilla_key .. "_LA_" .. la_key
                local name_override = (hand == "armor") and vanilla_key or nil
                local entry = build_clone_entry(vanilla_key, la_key, backend_id, name_override)
                if entry then
                    table.insert(entries_to_register, entry)
                    M.backend_to_armoury[backend_id] = la_key
                    M.backend_to_vanilla[backend_id] = vanilla_key
                    M.armoury_to_backend[la_key]     = backend_id
                    if unit_path then
                        M.unit_path_to_clones[unit_path] = M.unit_path_to_clones[unit_path] or {}
                        table.insert(M.unit_path_to_clones[unit_path], backend_id)
                    end
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

    build_offhand_options()
    for character, list in pairs(M.la_offhand_options_by_character) do
        mod:info("[LA bridge] %s offhand pool: %d entries", character, #list)
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

-- Texture slot hashes for shields (swap_hand="left_hand_unit"). Mirrors
-- LA's funcs.lua local constants — kept inline here so we never need to
-- call LA's `apply_new_skin_from_texture`, which has destructive side
-- effects (mutates `WeaponSkins.skins[skin].inventory_icon` and
-- `ItemMasterList[skin].inventory_icon` globally) that leaked LA icons
-- into vanilla weapons across the inventory UI.
local SHIELD_DIFF_SLOT = "texture_map_c0ba2942"
local SHIELD_PACK_SLOT = "texture_map_0205ba86"
local SHIELD_NORM_SLOT = "texture_map_59cd86b9"

-- Local re-implementation of LA's `apply_texture_to_all_world_units` for
-- shields only. Touches ONLY the supplied unit's mesh materials. No
-- WeaponSkins / ItemMasterList writes. Safe to call on preview spawns.
local function _paint_offhand_textures_locally(unit, variant)
    if not unit or type(unit) ~= "userdata" then return false end
    if not Unit.alive(unit) then return false end
    if type(variant.textures) ~= "table" then return false end

    local diff = variant.textures[1]
    local pack = variant.textures[2]
    local norm = variant.textures[3]
    local skip_meshes = variant.skip_meshes or {}
    local textures_other_mesh = variant.textures_other_mesh
    local special_textures = variant.special_textures
    local mat_to_skip = variant.mat_to_skip or {}

    local num_meshes = Unit.num_meshes(unit)
    for i = 0, num_meshes - 1 do
        local skip_key = "skip" .. tostring(i)
        local mesh_diff, mesh_pack, mesh_norm = diff, pack, norm
        local skip_this = false
        if skip_meshes[skip_key] then
            local override = textures_other_mesh and textures_other_mesh[skip_key]
            if override then
                if override[1] then mesh_diff = override[1] end
                if override[2] then mesh_pack = override[2] end
                if override[3] then mesh_norm = override[3] end
            else
                skip_this = true
            end
        end
        if not skip_this then
            local mesh = Unit.mesh(unit, i)
            local num_mats = Mesh.num_materials(mesh)
            for j = 0, num_mats - 1 do
                local mat = Mesh.material(mesh, j)
                if mesh_diff then Material.set_texture(mat, SHIELD_DIFF_SLOT, mesh_diff) end
                if mesh_pack then Material.set_texture(mat, SHIELD_PACK_SLOT, mesh_pack) end
                if mesh_norm then Material.set_texture(mat, SHIELD_NORM_SLOT, mesh_norm) end
                if special_textures and not mat_to_skip["skip" .. tostring(j)] then
                    for _, tx in ipairs(special_textures) do
                        if tx.slot and tx.texture then
                            Material.set_texture(mat, tx.slot, tx.texture)
                        end
                    end
                end
            end
        end
    end
    return true
end

-- Apply an LA offhand variant to a specific shield unit. Used by the
-- two-row offhand UI to paint LA heraldics onto the player's left-hand
-- (shield) unit after it spawns. We DO NOT call LA's
-- `apply_new_skin_from_texture` because that mutates global WeaponSkins
-- and ItemMasterList icon fields. Local paint only.
function M.apply_offhand_to_unit(world, unit, armoury_key, vanilla_skin)
    if not armoury_key then return false end
    local LA = la()
    if not LA or type(LA.SKIN_LIST) ~= "table" then return false end
    local variant = LA.SKIN_LIST[armoury_key]
    if not variant then return false end
    local ok = _paint_offhand_textures_locally(unit, variant)
    if M.trace then mod:info("[LA bridge]   offhand local paint %s ok=%s", armoury_key, tostring(ok)) end
    return ok
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
