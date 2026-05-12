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
-- swap_hand="left_hand_unit". Indexed by VANILLA WEAPON TYPE (the prefix
-- of each `icons` table key, e.g. `es_1h_mace_shield`, `es_sword_shield_breton`).
-- LA authors each shield's texture for specific weapon UVs and lists those
-- weapons in the variant's `icons` table; the picker should mirror that
-- authoring exactly so we never paint a texture meant for one shield
-- silhouette onto a different one.
--   { es_1h_mace_shield = { {name=..., armoury_key=..., vanilla_skin=...}, ... }, ... }
M.la_offhand_options_by_weapon_type = {}

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
-- CLARIFY: pairs() iteration on ItemMasterList does NOT trigger __index, so
-- this is safe (the crashify metamethod only fires on missing-key reads).
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
    -- rawget: ItemMasterList __index crashifies on missing keys. vanilla_key
    -- is normally validated by pick_vanilla_key, but using rawget here keeps
    -- the function safe if a future caller forwards an unvalidated key.
    local original = rawget(ItemMasterList, vanilla_key)
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
-- DIAGNOSTIC PHASE (v0.7.92): re-enabled mesh swap to reproduce the crash
-- under the World.spawn_unit trace. The previous "always nil" workaround
-- silently sidestepped the bug instead of identifying it. With this and
-- the [SPAWN_TRACE] hook in cosmetics_tweaker.lua active, the LAST
-- spawn_unit log line before the assertion will be the unit name we
-- couldn't decode from the hash.
local function _resolve_intended_unit(la_key, variant, sorted_icons)
    if type(variant.new_units) == "table" and variant.new_units[1] then
        return variant.new_units[1], "new_units"
    end
    return nil, "no_override"
end

-- Decide whether an LA variant is safe to expose in our offhand picker.
--
-- Variant categories handled here:
--   * `kind="texture"` + no `new_units`           -> pure paint-over (intended_unit nil).
--   * `kind="texture"` + `new_units` + is_vanilla -> paint onto a vanilla mesh.
--   * `kind="texture"` + `new_units` + !vanilla   -> custom mesh; FILTERED.
--   * `kind="unit"`    + `new_units` + engine-resident -> custom mesh.
--
-- The `kind="unit"` path was filtered until v0.8.25 because v0.8.11-v0.8.13
-- attempts went through LA's `re_apply_illusion`, which races with LA's
-- `mod.update` loop and crashes against `NetworkLookup.inventory_packages`'s
-- strict __index when `<la_path>_3p` isn't registered (crash GUID
-- 60180105-bd15-49f2-9fa6-9f70dd851846).
--
-- Now we own the path entirely: never call LA helpers, register the LA
-- mesh paths in `NetworkLookup.inventory_packages` ourselves via `rawset`
-- at registration time (so vanilla code that reads the table for sync
-- doesn't trip the __index), and gate exposure on
-- `Application.can_get("unit", ...)` for both the 1p and _3p halves so
-- we never expose a path the engine can't actually spawn.
local function _is_supported_variant(variant)
    if variant.kind == "texture" then
        if variant.new_units and not variant.is_vanilla_unit then return false end
        return true
    end
    if variant.kind == "unit" then
        if not variant.new_units or not variant.new_units[1] or not variant.new_units[2] then return false end
        local can_get = Application and Application.can_get
        if not can_get then return false end
        if not can_get("unit", variant.new_units[1]) then return false end
        if not can_get("unit", variant.new_units[2]) then return false end
        return true
    end
    return false
end

-- Register an LA mesh path in `NetworkLookup.inventory_packages` so vanilla
-- VT2 code that reads the table during inventory sync / serialization
-- doesn't trip the strict `__index` metamethod (which `error()`s on missing
-- key). LA's compiled `.unit` files have NetworkLookup IDs assigned at
-- compile time but they aren't merged into the runtime NetworkLookup
-- bootstrap, so we add bidirectional entries (string→idx, idx→string)
-- using `rawset` to bypass the strict __index. Idempotent; safe to call
-- on every variant during build_offhand_options.
local function _register_la_path_in_network_lookup(path)
    if not path or path == "" then return end
    if not NetworkLookup or not NetworkLookup.inventory_packages then return end
    local ip = NetworkLookup.inventory_packages
    if rawget(ip, path) then return end
    local idx = #ip + 1
    rawset(ip, idx, path)
    rawset(ip, path, idx)
end

-- Build per-weapon-type LA shield pools.
--
-- For each LA SKIN_LIST entry with `swap_hand = "left_hand_unit"`, parse the
-- `icons` table — its keys are vanilla skin keys of the form
-- `<weapon_type>_skin_<...>` (e.g. `es_1h_mace_shield_skin_03`,
-- `es_sword_shield_breton_skin_01`). The prefix before `_skin_` is the
-- weapon type LA authored that texture for. We add the variant to those
-- weapon types' pools.
--
-- The `_LA_EXTRA_WEAPON_TYPES` map below adds extra weapon types per
-- variant — used when the user wants an LA shield to appear on a weapon
-- type LA didn't include in its `icons` table. The shield still displays
-- with LA's authored mesh + texture combo (e.g. Ostermark on a Bret weapon
-- still renders the deus shield + Ostermark texture, the same combo as on
-- mace+shield). This is the path for "I want this LA shield available on
-- THIS weapon too" decisions made one shield at a time as we walk the list.
local _LA_EXTRA_WEAPON_TYPES = {
    -- Ostermark + Kotbs are authored for Empire mace/sword/deus UVs but the
    -- player wants them available on Bret longsword+shield as well; the
    -- mesh swaps to deus_shield_03 (matches the texture's UVs) so it
    -- displays as the LA combo rather than wrapping onto Bret UVs.
    Kruber_empire_shield_hero1_Ostermark01 = { es_1h_sword_shield_breton = true },
    Kruber_empire_shield_hero1_Kotbs01     = { es_1h_sword_shield_breton = true },
    -- Empire shield 01 mesh (Reiland-style). Custom kind="unit" mesh; same
    -- "show LA's authored shape on Bret weapon" rationale as Ostermark.
    Kruber_empire_shield_basic1            = { es_1h_sword_shield_breton = true },
}

-- LA's icon keys sometimes use a different name than the game's actual
-- `ItemMasterList[item].item_type` value. The picker queries the table by
-- item_type at runtime, so a key mismatch here = the LA pool builds under
-- the wrong key and the picker shows nothing.
--
-- Known cases:
--   * `es_sword_shield_breton_skin_*` (LA icon key) -> `es_1h_sword_shield_breton`
--     (game item_type). LA omitted the `_1h_` infix that the game uses for
--     this family. Without this alias, every Bret-authored LA shield
--     (Bastonne, Reynard, Luidhard, Lothar, Alberic) silently builds into
--     a pool the game never queries.
local _LA_WEAPON_TYPE_ALIAS = {
    es_sword_shield_breton = "es_1h_sword_shield_breton",
}

local function _normalize_weapon_type(wt)
    return _LA_WEAPON_TYPE_ALIAS[wt] or wt
end

local function build_offhand_options()
    M.la_offhand_options_by_weapon_type = {}
    M._la_offhand_resolution = {}
    local SKIN_LIST = la().SKIN_LIST
    for la_key, variant in pairs(SKIN_LIST) do
        if variant.swap_hand == "left_hand_unit"
            and _is_supported_variant(variant)
            and type(variant.icons) == "table"
        then
            local character = la_key:match("^([A-Z][a-z]+)_")
            if character and _character_prefixes[character] then
                local weapon_types = {}
                local sorted_icons = {}
                for icon_key, _ in pairs(variant.icons) do
                    sorted_icons[#sorted_icons + 1] = icon_key
                    local wt = icon_key:match("^(.-)_skin_")
                    if wt then weapon_types[_normalize_weapon_type(wt)] = true end
                end
                local extras = _LA_EXTRA_WEAPON_TYPES[la_key]
                if extras then
                    for wt, _ in pairs(extras) do weapon_types[_normalize_weapon_type(wt)] = true end
                end
                table.sort(sorted_icons)
                local vanilla_skin_key = sorted_icons[1]
                local intended_unit, source = _resolve_intended_unit(la_key, variant, sorted_icons)
                -- For kind="unit" custom-mesh variants, register both new_units
                -- entries (1p and _3p) in NetworkLookup.inventory_packages so
                -- vanilla code reading the table for sync doesn't crash on the
                -- strict __index. kind="texture" variants point to vanilla
                -- meshes that are already in the table.
                if variant.kind == "unit" and variant.new_units then
                    _register_la_path_in_network_lookup(variant.new_units[1])
                    _register_la_path_in_network_lookup(variant.new_units[2])
                end
                M._la_offhand_resolution[la_key] = {
                    intended_unit = intended_unit,
                    source        = source,
                    texture_path  = (variant.textures and variant.textures[1]) or nil,
                    icon_keys     = sorted_icons,
                    weapon_types  = weapon_types,
                }
                local opt = {
                    name          = humanize_armoury_key(la_key),
                    armoury_key   = la_key,
                    vanilla_skin  = vanilla_skin_key,
                    intended_unit = intended_unit,
                }
                for wt, _ in pairs(weapon_types) do
                    local list = M.la_offhand_options_by_weapon_type[wt]
                    if not list then list = {}; M.la_offhand_options_by_weapon_type[wt] = list end
                    list[#list + 1] = opt
                end
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
    local can_get = Application and Application.can_get
    for la_key, info in pairs(M._la_offhand_resolution) do
        local u = info.intended_unit
        local has_1p = (u and can_get) and can_get("unit", u) or false
        local has_3p = (u and can_get) and can_get("unit", u .. "_3p") or false
        local has_pkg = (u and can_get) and can_get("package", u) or false
        local wt_list = {}
        if info.weapon_types then
            for wt, _ in pairs(info.weapon_types) do wt_list[#wt_list + 1] = wt end
            table.sort(wt_list)
        end
        mod:info("  %-55s 1p=%s 3p=%s pkg=%s -> %s  weapons=[%s]",
            la_key,
            tostring(has_1p),
            tostring(has_3p),
            tostring(has_pkg),
            tostring(u),
            table.concat(wt_list, ","))
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
    M._build_la_path_to_parent_package()
    for weapon_type, list in pairs(M.la_offhand_options_by_weapon_type) do
        mod:info("[LA bridge] %s offhand pool: %d entries", weapon_type, #list)
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

-- Texture-fallback map for `kind="unit"` LA shields whose textures live in
-- the source `.unit` file's `colors / normals / MABs` fields (which LA's
-- compiled bundle reads but the vanilla previewer's resource scope doesn't
-- bind reliably). We extract them manually and paint per-unit via
-- `Unit.set_texture_for_materials` at spawn time. The customization preview
-- world doesn't drag in vanilla shield package dependencies (only the LA
-- mesh is in scope), so the compiled material's references go unbound and
-- the shield renders mesh-only-no-texture there. Painting explicitly per
-- unit fixes it because the textures themselves are in LA's globally-
-- loaded resource_package.
--
-- Source for these paths: `units/empire_shield/<la_mesh>.unit` `colors`,
-- `normals`, `MABs` keys at slot1.
local _LA_KIND_UNIT_TEXTURES = {
    Kruber_empire_shield_basic1 = {
        diff = "textures/Kruber_empire_shield_basic1/Kruber_empire_shield_basic1_diffuse",
        norm = "textures/Kruber_empire_shield_basic1/Kruber_empire_shield_basic1_normal",
        pack = "textures/Kruber_empire_shield_basic1/Kruber_empire_shield_basic1_combined",
    },
}

-- Parent vanilla package per LA `kind="unit"` shield. LA's compiled `.unit`
-- inherits its shader graph from a vanilla unit (specified by `mat_to_use`
-- in the source `.unit`); the customization previewer's narrow resource
-- scope doesn't include that vanilla unit's package by default, so the
-- material can't fully initialize and textures fall back to magenta /
-- missing. Loading the parent package onto the previewer's reference
-- brings the shader into scope.
--
-- Source for these mappings: `mat_to_use` field in
-- `units/.../<la_mesh>.unit` (LA's source repo).
M.la_kind_unit_parent_packages = {
    Kruber_empire_shield_basic1 = "units/weapons/player/wpn_empire_handgun_02_t2/wpn_empire_handgun_02_t2",
}

-- Reverse map (LA mesh path → parent package) built at register-all time
-- so the previewer's `load_package` hook can look up the parent without
-- knowing the armoury_key. Keys are both the 1p and _3p forms of the LA
-- mesh path; the previewer queries the _3p form.
M.la_path_to_parent_package = {}

-- Hoisted onto M so `register_all` can call it without forward-ref
-- crashes (per `feedback_lua_forward_reference.md` — local-function
-- declarations are scoped at parse time, so a `local function` declared
-- AFTER its caller resolves to nil at call time, not the function body).
function M._build_la_path_to_parent_package()
    M.la_path_to_parent_package = {}
    local SKIN_LIST = la() and la().SKIN_LIST
    if not SKIN_LIST then return end
    for armoury_key, parent in pairs(M.la_kind_unit_parent_packages) do
        local variant = SKIN_LIST[armoury_key]
        if variant and type(variant.new_units) == "table" then
            if variant.new_units[1] then
                M.la_path_to_parent_package[variant.new_units[1]] = parent
            end
            if variant.new_units[2] then
                M.la_path_to_parent_package[variant.new_units[2]] = parent
            end
        end
    end
end

-- Paint LA's textures onto a single unit using `Unit.set_texture_for_materials`,
-- the same per-unit primitive vanilla VT2 uses for `MaterialSettingsTemplates`
-- (`gear_utils.lua:150`, `cosmetic_utils.lua:72`, `flow_callbacks_foundation.lua:939`).
--
-- Why this and not `Material.set_texture` (the previous implementation):
-- `Material.set_texture(mat, slot, path)` mutates the SHARED material — the
-- same one referenced by every other shield unit using that vanilla mesh, in
-- the world AND in the inventory mannequin AND in the illusion browser. So
-- one click leaked the LA texture onto every other shield, and a subsequent
-- "Default" pick or texture unload turned them all magenta. Per-unit
-- bindings via `Unit.set_texture_for_materials` are intercepted by the
-- engine before the shared material is touched, so unit destruction (e.g.
-- next re-equip) implicitly drops the override and the shared material is
-- never modified.
--
-- LIMITATION: `Unit.set_texture_for_materials` applies to ALL materials on
-- the unit that have a slot of the given variable name. The previous
-- implementation supported `skip_meshes` (per-mesh exclusion) and
-- `textures_other_mesh` (per-mesh override) — finer granularity than this
-- API offers. For shields whose `skip_meshes` is empty (e.g. the first
-- focused-triage candidate `Kruber_empire_shield_hero1_Ostermark01`) this
-- doesn't matter; if a future LA shield uses skip_meshes we'll need a
-- per-mesh fallback. We log a warning when we drop those overrides so the
-- regression is visible.

-- v0.8.45 probe: walk the spawned LA mesh and dump material state so we can
-- diagnose the 0x8 AV in Unit.set_texture_for_materials. All Stingray calls
-- are pcall-wrapped. Per `cosmetics_tweaker.lua:435-438`, NEVER call
-- Material.num_parameters / parameter_name / parameter_type — they raise a
-- C++ resource_manager.cpp fault that bypasses pcall.
local _LA_PROBE_SLOTS = { SHIELD_DIFF_SLOT, SHIELD_PACK_SLOT, SHIELD_NORM_SLOT }

-- v0.8.46: one-shot enumeration of the engine's introspection / mutation
-- API surface. We need to know whether Mesh.set_material, Material.set_texture,
-- and friends actually exist before designing the null-material swap. Runs
-- once per process (gated by a flag). Pcall around each pairs() call in case
-- the underlying table is userdata with metamethod side effects.
local _LA_PROBE_API_DUMPED = false
local function _dump_api_surface()
    if _LA_PROBE_API_DUMPED then return end
    _LA_PROBE_API_DUMPED = true
    local function dump(name, t)
        if type(t) ~= "table" then
            mod:info("[LA probe API] %s is %s, not a table", name, type(t))
            return
        end
        local keys = {}
        local ok = pcall(function()
            for k, v in pairs(t) do
                keys[#keys + 1] = tostring(k) .. ":" .. type(v)
            end
        end)
        if not ok then
            mod:info("[LA probe API] %s pairs() errored", name)
            return
        end
        table.sort(keys)
        mod:info("[LA probe API] %s (%d entries):", name, #keys)
        -- Chunk into groups of 6 per line to keep the log readable.
        local line = {}
        for i, k in ipairs(keys) do
            line[#line + 1] = k
            if #line >= 6 or i == #keys then
                mod:info("[LA probe API]   %s", table.concat(line, ", "))
                line = {}
            end
        end
    end
    dump("Unit",     _G.Unit)
    dump("Mesh",     _G.Mesh)
    dump("Material", _G.Material)
end

local function _probe_la_unit_materials(unit, armoury_key)
    _dump_api_surface()
    local tag = tostring(armoury_key)
    mod:info("[LA probe %s] === begin ===", tag)
    if not unit or type(unit) ~= "userdata" then
        mod:info("[LA probe %s] unit invalid (type=%s)", tag, type(unit))
        return
    end
    local ok_alive, alive = pcall(Unit.alive, unit)
    mod:info("[LA probe %s] Unit.alive ok=%s val=%s", tag, tostring(ok_alive), tostring(alive))
    if not (ok_alive and alive) then return end

    local ok_act, n_act = pcall(Unit.num_actors, unit)
    mod:info("[LA probe %s] Unit.num_actors ok=%s val=%s", tag, tostring(ok_act), tostring(n_act))

    local ok_nodes, n_nodes = pcall(Unit.num_nodes, unit)
    mod:info("[LA probe %s] Unit.num_nodes ok=%s val=%s", tag, tostring(ok_nodes), tostring(n_nodes))

    local ok_vis, vis = pcall(Unit.is_visible, unit)
    mod:info("[LA probe %s] Unit.is_visible ok=%s val=%s", tag, tostring(ok_vis), tostring(vis))

    local ok_n, n_meshes = pcall(Unit.num_meshes, unit)
    mod:info("[LA probe %s] Unit.num_meshes ok=%s val=%s", tag, tostring(ok_n), tostring(n_meshes))
    if not (ok_n and type(n_meshes) == "number") then
        mod:info("[LA probe %s] cannot enumerate meshes; aborting probe", tag)
        return
    end

    for i = 0, n_meshes - 1 do
        local ok_m, mesh = pcall(Unit.mesh, unit, i)
        mod:info("[LA probe %s] mesh[%d] ok=%s val=%s", tag, i, tostring(ok_m), tostring(mesh))
        if ok_m and mesh and Mesh then
            local ok_mn, mname = pcall(function() return Unit.mesh_name and Unit.mesh_name(unit, i) end)
            if ok_mn and mname then mod:info("[LA probe %s]   Unit.mesh_name(%d)=%s", tag, i, tostring(mname)) end

            local ok_nm, n_mats = pcall(Mesh.num_materials, mesh)
            mod:info("[LA probe %s]   Mesh.num_materials ok=%s val=%s", tag, tostring(ok_nm), tostring(n_mats))
            if ok_nm and type(n_mats) == "number" then
                for j = 0, n_mats - 1 do
                    local ok_mat, mat = pcall(Mesh.material, mesh, j)
                    mod:info("[LA probe %s]     material[%d] ok=%s val=%s", tag, j, tostring(ok_mat), tostring(mat))
                    if ok_mat and mat and Material then
                        for _, slot in ipairs(_LA_PROBE_SLOTS) do
                            if Material.has_variable then
                                local okv, has = pcall(Material.has_variable, mat, slot)
                                mod:info("[LA probe %s]       has_variable(%s) ok=%s val=%s",
                                    tag, slot, tostring(okv), tostring(has))
                            end
                            if Material.get_texture then
                                local okt, tex = pcall(Material.get_texture, mat, slot)
                                mod:info("[LA probe %s]       get_texture(%s) ok=%s val=%s",
                                    tag, slot, tostring(okt), tostring(tex))
                            end
                        end
                    end
                end
            end
        end
    end
    mod:info("[LA probe %s] === end ===", tag)
end

local function _paint_offhand_textures_locally(unit, variant, armoury_key, context)
    if not unit or type(unit) ~= "userdata" then return false end
    if not Unit.alive(unit) then return false end

    -- v0.8.44: REVERTED v0.8.43 re-enable. The hypothesis was that v0.8.39's
    -- parent-package preload (wpn_empire_handgun_02_t2 for Reiland) would
    -- make `Unit.set_texture_for_materials` safe on bundled meshes. v0.8.43
    -- test result: same AV at 0x8 (GUID 45a2a017). The 0x8 dereference is
    -- not the shader-graph being absent — it's something else (likely the
    -- LA mesh's compiled material not being instantiated in the customization
    -- preview's specific world, even though the package is globally loaded).
    -- Stingray materials are per-world; globally-loaded ≠ scoped to the
    -- LootItemUnitPreviewer's render world. Staying disabled until we have
    -- a different binding primitive or replicate LA's swap_units_new
    -- NetworkLookup aliasing for the customization preview path.
    if variant.kind == "unit" then
        -- v0.8.48: ONLY apply the material swap in the LootItemUnitPreviewer
        -- (customization preview) context. v0.8.47 broke in-game rendering
        -- (LA mesh became massive) because the swap ran on already-correctly-
        -- bound units in the in-game and hero-previewer worlds. Those paths
        -- already render the LA mesh correctly without our intervention;
        -- the customization preview is the only world where material[0] is
        -- #ID[00000000] (per v0.8.45 probe). Skip the swap AND the paint
        -- for non-previewer contexts to keep the v0.8.46 safe-no-paint
        -- behavior for in-game/inventory (where painting still AVs because
        -- the *paint texture binding* is what 0x8-faulted, not the swap).
        if context ~= "loot_previewer" then
            if M.trace then
                mod:info("[LA bridge] kind=unit %s context=%s — skipping swap+paint (vanilla path renders correctly)",
                    tostring(armoury_key), tostring(context))
            end
            return false
        end

        -- Customization-preview context: swap the null material, then paint.
        local parent_path = M.la_kind_unit_parent_packages and M.la_kind_unit_parent_packages[armoury_key]
        if parent_path and Unit.set_all_materials then
            local ok, err = pcall(Unit.set_all_materials, unit, parent_path)
            mod:info("[LA fix kind=unit %s] Unit.set_all_materials(%s) ok=%s err=%s",
                tostring(armoury_key), parent_path, tostring(ok), tostring(err))
        else
            mod:info("[LA fix kind=unit %s] no parent_path or Unit.set_all_materials missing — paint will likely AV",
                tostring(armoury_key))
        end
        -- Fall through to the texture-painting code below. The swap should
        -- have given us a real material slot to paint into.
    end

    -- Resolution order for textures:
    --   1. variant.textures (LA's SKIN_LIST entry; populated for kind="texture" variants)
    --   2. _LA_KIND_UNIT_TEXTURES[armoury_key] (manual extraction from the
    --      source `.unit` file for `kind="unit"` variants whose SKIN_LIST
    --      lacks a textures array)
    --   3. nothing — the mesh is responsible for its own texture binding
    local diff, pack, norm
    if type(variant.textures) == "table" then
        diff = variant.textures[1]
        pack = variant.textures[2]
        norm = variant.textures[3]
    end
    local fallback = armoury_key and _LA_KIND_UNIT_TEXTURES[armoury_key]
    if fallback then
        if not diff then diff = fallback.diff end
        if not pack then pack = fallback.pack end
        if not norm then norm = fallback.norm end
    end

    if (variant.skip_meshes and next(variant.skip_meshes)) or variant.textures_other_mesh then
        if M.trace then
            mod:info("[LA bridge] WARN: variant has skip_meshes/textures_other_mesh; per-unit paint skips that nuance")
        end
    end

    local can_get = Application and Application.can_get
    if diff and (not can_get or can_get("texture", diff)) then
        Unit.set_texture_for_materials(unit, SHIELD_DIFF_SLOT, diff)
    end
    if pack and (not can_get or can_get("texture", pack)) then
        Unit.set_texture_for_materials(unit, SHIELD_PACK_SLOT, pack)
    end
    if norm and (not can_get or can_get("texture", norm)) then
        Unit.set_texture_for_materials(unit, SHIELD_NORM_SLOT, norm)
    end

    if variant.special_textures then
        for _, tx in ipairs(variant.special_textures) do
            if tx.slot and tx.texture and (not can_get or can_get("texture", tx.texture)) then
                Unit.set_texture_for_materials(unit, tx.slot, tx.texture)
            end
        end
    end

    return (diff or pack or norm or variant.special_textures) ~= nil
end

-- Dead code retained for reference; the function above now handles painting.
-- Marked as `_legacy_*` so a grep for `_paint_offhand_textures_locally`
-- yields only the active implementation. Safe to delete after the focused-
-- triage Ostermark01 round confirms the new path works end-to-end.
local function _legacy_paint_offhand_textures_via_shared_material(unit, variant)
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
-- REVIEW: parameters `world` and `vanilla_skin` are unused — local paint
-- only touches the unit's own materials. Could be dropped, but keeping for
-- API parity with apply_direct() / queue_unit_direct() in case the call
-- path ever needs to fall back to LA's queue system.
function M.apply_offhand_to_unit(world, unit, armoury_key, vanilla_skin, context)
    if not armoury_key then return false end
    local LA = la()
    if not LA or type(LA.SKIN_LIST) ~= "table" then return false end
    local variant = LA.SKIN_LIST[armoury_key]
    if not variant then return false end
    local ok = _paint_offhand_textures_locally(unit, variant, armoury_key, context)
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

    -- REVIEW: the surrounding code path goes through level_queue (not
    -- apply_direct), so the apply gate's _bridge_active flag is bypassed.
    -- For diagnostics that's fine. But this is the only place LA's queues
    -- are still touched directly; if the gate were to be tightened to
    -- block queue-based applies as well, this command would silently fail.
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
