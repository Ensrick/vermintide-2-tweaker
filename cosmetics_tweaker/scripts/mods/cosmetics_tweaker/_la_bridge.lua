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

-- Engine-level log. The user runs with VMF mod-logging OFF, so mod:info is
-- invisible to them; engine `printf` writes to the game console log
-- regardless. Used for the #149 in-mission / husk kind="unit" paint outcomes
-- (ok/skip) so the user can confirm what happened without enabling Debug
-- Logging. Falls back to mod:info if `printf` isn't present on some build.
local function _plog(fmt, ...)
    local ok, msg = pcall(string.format, "[cosmetics_tweaker/LA] " .. fmt, ...)
    if not ok then msg = "[cosmetics_tweaker/LA] (log format error)" end
    if printf then printf("%s", msg) else mod:info("%s", msg) end
end

local M = {}
local SHIELD_PARITY = mod:dofile("scripts/mods/cosmetics_tweaker/_la_shield_parity")
local RESIDENCY = mod:dofile("scripts/mods/cosmetics_tweaker/_lib_resource_residency")
M.kruber_shield_item_types = SHIELD_PARITY.KRUBER_SHIELD_ITEM_TYPES
M.kruber_shield_families = SHIELD_PARITY.KRUBER_SHIELD_FAMILIES

M.registered            = false
M.la_registered         = false -- custom authored cosmetics may activate the shared registry first
M.backend_to_armoury    = {}  -- our backend_id -> LA Armoury_key
M.backend_to_vanilla    = {}  -- our backend_id -> vanilla skin key (LA expects this as `skin` arg)
M.unit_path_to_clones   = {}  -- vanilla unit path -> list of our backend_ids targeting it
M.armoury_to_backend    = {}  -- reverse: LA key -> our backend_id (for debug)
M.localization          = {}  -- display_name_key -> human-readable string

-- Shield/offhand options derived from LA SKIN_LIST entries with
-- swap_hand="left_hand_unit". Indexed by VANILLA WEAPON TYPE (the prefix
-- of each `icons` table key, e.g. `es_1h_mace_shield`, `es_sword_shield_breton`)
-- then by hand_field. LA today only ships swap_hand="left_hand_unit"
-- variants (and the bow filter weeds bows out), so the inner key is always
-- "left_hand_unit". The schema is per-hand for forward-compat with future
-- LA pistol/right-hand variants and to match cosmetics_tweaker's
-- _offhand_options structure (v0.9.9.4-dev).
--   { es_1h_mace_shield = { left_hand_unit = { {name=..., armoury_key=..., vanilla_skin=...}, ... } }, ... }
M.la_offhand_options_by_weapon_type = {}

-- Return a paintable vanilla receiver for the handful of Weavebound/Shyish
-- shield units whose magic material cannot accept LA's diffuse texture.  The
-- shared policy uses an exact, family-scoped allow-list; nil means the live
-- unit should be left alone.
function M.resolve_texture_receiver(armoury_key, unit_path, authored_family)
    local la_mod = get_mod("Loremasters-Armoury")
    local variant = la_mod and la_mod.SKIN_LIST and la_mod.SKIN_LIST[armoury_key]
    if not (variant and variant.kind == "texture" and unit_path) then return nil end
    local resolution = M._la_offhand_resolution and M._la_offhand_resolution[armoury_key]
    local family = authored_family or (resolution and resolution.authored_family)
    return SHIELD_PARITY.magic_texture_receiver(family, unit_path)
end

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

-- v0.8.66: pre-register EVERY kind="unit" left-hand LA variant's new_units paths
-- in NetworkLookup.inventory_packages BEFORE any of the gated/filtered code paths
-- run. This is the same shape of fix as ct v0.7.60 / 0.7.61 / 0.7.62 — the
-- doctrine memo `feedback_vt2_gated_registration_diverges.md` covers it.
--
-- Crash this prevents: lynnd's session 2026-05-19,
--   `network_lookup.lua:2514: Table inventory_packages does not contain key: 2296`
-- (peer 11000010ef3befb / danjo equipped an LA shield → ProfileSynchronizer
-- broadcast an inventory_list whose first_person_packages[9] resolved to network
-- index 2296 on danjo's machine but lynnd's NetworkLookup.inventory_packages
-- had no entry there).
--
-- Why the gated path diverged: `build_offhand_options` iterates `pairs(SKIN_LIST)`
-- (unordered) and only registers paths whose `_is_supported_variant` check passes
-- (`Application.can_get("unit", ...)` — timing-dependent on whether LA's units have
-- finished loading at registration time). Two peers can both have cosmetics_tweaker
-- + LA installed and still end up with different append orders or different
-- supported-variant sets. With `idx = #ip + 1`, even one skipped or reordered entry
-- shifts every subsequent index → the same path lands on different network IDs
-- across peers → ProfileSynchronizer crashes the receiver.
--
-- Sorted iteration is load-bearing per the doctrine — two peers running the same
-- ct + same LA version always assign identical indices regardless of which
-- variants their own filter thinks are presently usable. The runtime
-- `build_offhand_options` still runs the supported-variant filter for UI pool
-- building; it just no longer drives the NetworkLookup assignments.
--
-- v0.8.66-dev: extended to ALL `kind="unit"` LA variants, not just shield
-- offhands. The original `swap_hand == "left_hand_unit"` scope-limit was a
-- holdover from when only shields reached the picker. v0.8.x added direct-
-- clone hat/armor exposure (build_clone_entry), and a `kind="unit"` LA HAT or
-- WEAPON-ILLUSION equipped via cosmetics_tweaker triggers the same
-- ProfileSynchronizer leak: get_item_units returns the LA mesh path,
-- profile_packages adds it to inventory_list, equipper's
-- NetworkLookup.inventory_packages has it (LA's swap_units_new dynamically
-- inserted it on equip), the receiver's doesn't → `Table inventory_packages
-- does not contain key: <N>` fatal in network_lookup.lua's strict __index,
-- bypasses pcall via shared_state RPC decode. Crash signature: dump
-- 2026-05-19-02.05.59. Pre-registering every kind="unit" path in sorted order
-- on both peers gives both sides the same indices regardless of which variant
-- was actually equipped.
function M.pre_register_la_inventory_packages()
    if not la() then return end
    if not NetworkLookup or not NetworkLookup.inventory_packages then return end
    local SKIN_LIST = la().SKIN_LIST
    if type(SKIN_LIST) ~= "table" then return end

    local sorted_keys = {}
    for la_key, _ in pairs(SKIN_LIST) do
        sorted_keys[#sorted_keys + 1] = la_key
    end
    table.sort(sorted_keys)

    local registered = 0
    for _, la_key in ipairs(sorted_keys) do
        local variant = SKIN_LIST[la_key]
        if type(variant) == "table"
                and variant.kind == "unit"
                and type(variant.new_units) == "table" then
            local before = #NetworkLookup.inventory_packages
            -- new_units[1] = 1P / primary mesh; new_units[2] = 3P sibling for
            -- shields and weapons (left_hand_unit / right_hand_unit). For
            -- hats / armor, [2] may be nil. _register_la_path_in_network_lookup
            -- is nil-safe.
            _register_la_path_in_network_lookup(variant.new_units[1])
            _register_la_path_in_network_lookup(variant.new_units[2])
            if #NetworkLookup.inventory_packages > before then
                registered = registered + 1
            end
        end
    end
    mod:info("[LA bridge] pre_register_la_inventory_packages: %d variant(s) registered (sorted, all kind=unit)", registered)
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
    -- Per-variant cross-pollination (legacy table — superseded by the
    -- per-character rule below for shield families, but kept available
    -- for one-off non-shield additions).
}

-- v0.8.57-dev: per-character shield item_type pool, split by mesh family.
-- #266 supersedes this split for Kruber availability via SHIELD_PARITY below;
-- the family map remains the authored-shield detector and the policy for the
-- other characters.
--
-- Every LA shield variant whose la_key starts with a character prefix is
-- automatically added to other shield-bearing item_types for that character
-- — but only within the same mesh family. A `kind="texture"` variant
-- authored for the Bret heater-shield mesh paints onto whatever mesh the
-- base item uses, so cross-pollinating it onto Empire kite-shield items
-- wraps the Bret-UV texture onto Empire geometry (visible artifact: Bret
-- texture stretched on Empire shield model). Splitting Kruber's shields
-- into `empire` (kite shield: sword+shield, mace+shield, deus_01) and
-- `breton` (heater shield: sword+shield_breton) keeps each variant within
-- the mesh family it was authored for.
--
-- `kind="unit"` variants carry their own mesh in `new_units[1]` — those
-- swap the displayed mesh on apply, so they render correctly across any
-- base item. For them we cross-pollinate across the whole character pool
-- (see `_LA_CHARACTER_ALL_SHIELDS` below).
--
-- LA's per-variant `icons` table already provides character-correct
-- targeting; this only adds weapon-type expansion WITHIN a character's
-- mesh family (or across the character's full pool for kind="unit").
local _LA_CHARACTER_SHIELD_FAMILIES = {
    Kruber = {
        empire = { "es_1h_sword_shield", "es_1h_mace_shield", "es_deus_01" },
        breton = { "es_1h_sword_shield_breton" },
    },
    Bardin    = { dwarf = { "dr_1h_axe_shield", "dr_1h_hammer_shield" } },
    Kerillian = { wood_elf = { "we_1h_spears_shield" } },
    Saltzpyre = { imperial = { "wh_flail_shield", "wh_hammer_shield" } },
}

-- Reverse map: shield item_type → family key (within character). Used to
-- detect a variant's authored family from its `icons` table.
local _SHIELD_TYPE_TO_FAMILY = {}
for _, families in pairs(_LA_CHARACTER_SHIELD_FAMILIES) do
    for family, types in pairs(families) do
        for _, wt in ipairs(types) do
            _SHIELD_TYPE_TO_FAMILY[wt] = family
        end
    end
end

-- Flat per-character shield pool (all families merged), used for the
-- broad cross-pollination of `kind="unit"` custom-mesh variants. Same set
-- the old `_LA_CHARACTER_SHIELD_TYPES` exposed.
local _LA_CHARACTER_ALL_SHIELDS = {}
for character, families in pairs(_LA_CHARACTER_SHIELD_FAMILIES) do
    local all = {}
    for _, types in pairs(families) do
        for _, wt in ipairs(types) do all[#all + 1] = wt end
    end
    _LA_CHARACTER_ALL_SHIELDS[character] = all
end

-- Set of every shield item_type across all characters, for filtering
-- non-shield variants (bows etc.) out of the offhand pool. LA's bow
-- variants share `swap_hand = "left_hand_unit"` with shields because the
-- bow body is wielded in the left hand, so the swap_hand filter alone
-- isn't enough to distinguish them.
local _ALL_SHIELD_TYPES = {}
for wt, _ in pairs(_SHIELD_TYPE_TO_FAMILY) do
    _ALL_SHIELD_TYPES[wt] = true
end
for _, wt in ipairs(SHIELD_PARITY.KRUBER_SHIELD_ITEM_TYPES) do
    _ALL_SHIELD_TYPES[wt] = true
end

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
    -- v0.8.66: sorted iteration. After pre_register_la_inventory_packages has
    -- already filled NetworkLookup.inventory_packages for every kind="unit"
    -- left_hand variant, the per-variant calls inside this loop are no-ops via
    -- the rawget(ip, path) guard. Sorting still matters defensively: any future
    -- mutation that depends on first-seen order will be deterministic across
    -- peers. pairs() over a string-keyed table is not guaranteed deterministic.
    local sorted_keys = {}
    for la_key, _ in pairs(SKIN_LIST) do
        sorted_keys[#sorted_keys + 1] = la_key
    end
    table.sort(sorted_keys)
    for _, la_key in ipairs(sorted_keys) do
        local variant = SKIN_LIST[la_key]
        if variant.swap_hand == "left_hand_unit"
            and _is_supported_variant(variant)
            and type(variant.icons) == "table"
        then
            local character = la_key:match("^([A-Z][a-z]+)_")
            if character and _character_prefixes[character] then
                local weapon_types = {}
                local sorted_icons = {}
                local authored_family = nil
                local has_shield_authored = false
                for icon_key, _ in pairs(variant.icons) do
                    sorted_icons[#sorted_icons + 1] = icon_key
                    local wt = icon_key:match("^(.-)_skin_")
                    if wt then
                        local normalized = _normalize_weapon_type(wt)
                        weapon_types[normalized] = true
                        local family = _SHIELD_TYPE_TO_FAMILY[normalized]
                        if family then
                            has_shield_authored = true
                            -- Prefer the first family found; multi-family
                            -- icon sets are rare and ambiguous.
                            authored_family = authored_family or family
                        end
                    end
                end
                local extras = _LA_EXTRA_WEAPON_TYPES[la_key]
                if extras then
                    for wt, _ in pairs(extras) do
                        local normalized = _normalize_weapon_type(wt)
                        weapon_types[normalized] = true
                        if _SHIELD_TYPE_TO_FAMILY[normalized] then
                            has_shield_authored = true
                            authored_family = authored_family or _SHIELD_TYPE_TO_FAMILY[normalized]
                        end
                    end
                end

                -- v0.8.57: bow / non-shield filter. LA bow variants also use
                -- `swap_hand = "left_hand_unit"` (the bow body wields in the
                -- left hand), so they pass the outer if. Only proceed if at
                -- least one of the variant's authored icons maps to a known
                -- shield item_type. Symptom prior: Kerillian bow models
                -- appeared as offhand options on her spear+shield.
                if has_shield_authored then
                    -- v0.8.57: family-aware cross-pollination.
                    --   kind="unit" or texture+canonical-unit → broad pool across all the
                    --                    character's shield item_types.
                    --                    The variant carries its own mesh
                    --                    in new_units[1] so it renders
                    --                    correctly on any base item.
                    --   pure texture    → restricted to the variant's
                    --                    authored family. Texture is
                    --                    authored for a specific mesh's UV
                    --                    layout; painting it onto a
                    --                    different mesh family wraps
                    --                    incorrectly (Bret texture on
                    --                    Empire mesh visible as warped
                    --                    artwork).
                    -- Any Kruber variant carrying an authored mesh can span his
                    -- complete catalogue. Pure-paint texture variants must stay
                    -- inside their authored UV family.
                    if SHIELD_PARITY.add_compatible_targets(
                            character, variant.kind, authored_family, weapon_types,
                            variant.new_units and variant.new_units[1] ~= nil) then
                        -- Compatible targets added by the shared policy.
                    elseif variant.kind == "unit" then
                        local char_pool = _LA_CHARACTER_ALL_SHIELDS[character]
                        if char_pool then
                            for _, wt in ipairs(char_pool) do
                                weapon_types[_normalize_weapon_type(wt)] = true
                            end
                        end
                    elseif authored_family then
                        local family_pool = _LA_CHARACTER_SHIELD_FAMILIES[character]
                            and _LA_CHARACTER_SHIELD_FAMILIES[character][authored_family]
                        if family_pool then
                            for _, wt in ipairs(family_pool) do
                                weapon_types[_normalize_weapon_type(wt)] = true
                            end
                        end
                    end
                    table.sort(sorted_icons)
                    local vanilla_skin_key = sorted_icons[1]
                    local intended_unit, source = _resolve_intended_unit(la_key, variant, sorted_icons)
                    -- For every canonical-mesh variant, register both
                    -- new_units entries (1p and 3p) in
                    -- NetworkLookup.inventory_packages so vanilla code
                    -- reading the table for sync doesn't crash on the
                    -- strict __index. kind="texture" variants point to
                    -- vanilla meshes that are already in the table.
                    if variant.new_units then
                        _register_la_path_in_network_lookup(variant.new_units[1])
                        _register_la_path_in_network_lookup(variant.new_units[2])
                    end
                    M._la_offhand_resolution[la_key] = {
                        intended_unit = intended_unit,
                        source        = source,
                        authored_family = authored_family,
                        texture_path  = (variant.textures and variant.textures[1]) or nil,
                        icon_keys     = sorted_icons,
                        weapon_types  = weapon_types,
                    }
                    -- v0.9.9.1 REVERT: removed the v0.9.9.0 WeaponSkins
                    -- icon lookup. User reported "the latest has the wrong
                    -- icons for everything" — the assumption that
                    -- `WeaponSkins.skins[la_armoury_key].inventory_icon`
                    -- carries the LA-authored custom icon was wrong (or
                    -- the lookup returned an unrelated icon path). LA's
                    -- actual icon storage format needs a proper
                    -- diagnostic probe before re-attempting. Reverting
                    -- to pre-v0.9.9.0 opt shape (no icon field).
                    local opt = {
                        name          = humanize_armoury_key(la_key),
                        armoury_key   = la_key,
                        vanilla_skin  = vanilla_skin_key,
                        intended_unit = intended_unit,
                        authored_family = authored_family,
                        variant_kind  = variant.kind,
                    }
                    -- v0.9.9.4-dev: nest under hand_field. LA only ships
                    -- swap_hand="left_hand_unit" today, so the outer hand
                    -- bucket is always left_hand_unit. If LA later ships
                    -- right-hand variants, the bucket key would change to
                    -- variant.swap_hand and the consumer (picker) already
                    -- knows how to render per-hand rows.
                    local hand_field = "left_hand_unit"
                    for wt, _ in pairs(weapon_types) do
                        local per_hand = M.la_offhand_options_by_weapon_type[wt]
                        if not per_hand then per_hand = {}; M.la_offhand_options_by_weapon_type[wt] = per_hand end
                        local list = per_hand[hand_field]
                        if not list then list = {}; per_hand[hand_field] = list end
                        list[#list + 1] = opt
                    end
                end
            end
        end
    end
    M.report_magic_receiver_gaps()
end

-- #373 boot-time validation pass (log-only, capped): walk the live
-- WeaponSkins tables and printf-flag every magic/runed shield skin whose
-- family has no paint-receiver row, so the NEXT missing row self-reports in
-- the user's log instead of dead-ending silently (resolved_unit=nil).
-- One pass per session; printf survives mod-logging-OFF.
local _receiver_gap_report_done = false
function M.report_magic_receiver_gaps()
    if _receiver_gap_report_done then return end
    local skins = rawget(_G, "WeaponSkins")
    skins = skins and skins.skins
    local pf = rawget(_G, "printf")
    if type(skins) ~= "table" or not pf then return end
    _receiver_gap_report_done = true
    local gaps = SHIELD_PARITY.find_receiver_gaps(skins,
        function(item_type) return _SHIELD_TYPE_TO_FAMILY[item_type] end,
        function(skin_key)
            local prefix = tostring(skin_key):match("^(.-)_skin_")
            return prefix and _normalize_weapon_type(prefix) or nil
        end)
    local cap = 10
    for i = 1, math.min(#gaps, cap) do
        pf("[cos:373] RECEIVER-GAP skin=%s family=%s unit=%s (magic/runed shield has no paint receiver row - LA heraldry will dead-end)",
            gaps[i].skin, gaps[i].family, gaps[i].unit)
    end
    if #gaps > cap then
        pf("[cos:373] RECEIVER-GAP +%d more (capped at %d)", #gaps - cap, cap)
    elseif #gaps == 0 then
        pf("[cos:373] receiver coverage OK: no magic/runed shield family gaps")
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
    if M.la_registered then return end
    if not la() or not mil() then
        mod:info("[LA bridge] LA or MIL not present; skipping registration")
        return
    end
    if not ItemMasterList then return end
    if type(la().SKIN_LIST) ~= "table" then return end

    -- v0.8.66: pre-register kind="unit" left-hand variant inventory_packages
    -- BEFORE any other registration so two peers always assign identical network
    -- indices regardless of their per-machine filter outcomes. See
    -- pre_register_la_inventory_packages above and the doctrine memo
    -- feedback_vt2_gated_registration_diverges.md.
    M.pre_register_la_inventory_packages()

    local unit_index = build_unit_index()
    local entries_to_register = {}
    local registered, skipped = 0, {}

    -- v0.8.66: sorted iteration so the order in which we append to
    -- entries_to_register (and downstream NetworkLookup.item_names below) is
    -- identical across peers. pairs() over a string-keyed table is not
    -- guaranteed deterministic across LuaJIT VMs even with the same key set.
    local sorted_la_keys = {}
    for la_key, _ in pairs(la().SKIN_LIST) do
        sorted_la_keys[#sorted_la_keys + 1] = la_key
    end
    table.sort(sorted_la_keys)

    for _, la_key in ipairs(sorted_la_keys) do
        local variant = la().SKIN_LIST[la_key]
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
    for weapon_type, per_hand in pairs(M.la_offhand_options_by_weapon_type) do
        for hand_field, list in pairs(per_hand) do
            mod:info("[LA bridge] %s/%s offhand pool: %d entries", weapon_type, hand_field, #list)
        end
    end

    M.la_registered = true
    M.registered = true
    mod:info("[LA bridge] registered %d items, skipped %d (no vanilla unit match)", registered, #skipped)
    if #skipped > 0 then mod:info("[LA bridge] skipped: %s", table.concat(skipped, ", ")) end
end

-- Find any equipped clone for the given vanilla unit path. Returns
-- (backend_id, armoury_key, vanilla_key) or nil.
-- Walks the per-career loadout for ALL careers, since LA's hooks fire across
-- world units that may not belong to the local player (e.g. preview pawns).
--
-- v0.8.66-dev: consult cosmetics_tweaker.mod.loadout_cache FIRST. The
-- get_loadout hook in cosmetics_tweaker.lua rewrites LA backend_ids back to
-- vanilla in the returned loadout (for net-safety — peers can't decode the LA
-- bids). When apply_direct → maybe_queue_unit → find_active_clone called
-- get_loadout, the LA bid was already gone, the lookup missed, apply_direct
-- never fired, the apply_gate stayed closed, LA's own update loop was blocked
-- → local player saw vanilla on themselves. Reading from loadout_cache
-- (populated un-rewritten by the set_loadout_item hook for slot_hat / slot_skin)
-- gives us the LA bid that should drive apply_direct.
local function find_active_clone_for_unit_path(unit_path)
    local clones = M.unit_path_to_clones[unit_path]
    if not clones then return nil end

    -- Fast path: check the un-rewritten loadout_cache populated by
    -- cosmetics_tweaker.lua:3099 (set_loadout_item hook). This is the
    -- single source of truth for LA hat/armor equips on the local player.
    local cosmetics_mod = get_mod("cosmetics_tweaker")
    local cache = cosmetics_mod and cosmetics_mod.loadout_cache
    if type(cache) == "table" then
        for _, slots in pairs(cache) do
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
    end

    -- Fallback: vanilla loadout. The get_loadout hook re-injects loadout_cache
    -- entries on top of the rewritten table (cosmetics_tweaker.lua:3135-3140),
    -- so this path still matches in steady state for LA hat/armor. It also
    -- catches LA-cloned weapon illusions / other slots that don't flow
    -- through loadout_cache.
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
    -- v0.9.33: gate checks _gate_installed so that if uninstall can't restore the
    -- original (another mod re-wrapped on top of us — see uninstall_apply_gate),
    -- clearing the flag still makes a stranded gate a transparent passthrough.
    local gate_fn = function(armoury_key, world, skin, unit)
        if M._gate_installed and M.armoury_to_backend[armoury_key] and not M._bridge_active then
            if M.trace then mod:info("[LA bridge] GATE blocked managed key %s", armoury_key) end
            return
        end
        if M.trace then mod:info("[LA bridge] GATE allowed %s (bridge_active=%s)", armoury_key, tostring(M._bridge_active)) end
        return original_apply(armoury_key, world, skin, unit)
    end
    M._gate_fn = gate_fn  -- v0.9.33: saved so uninstall can verify the live fn is still ours
    LA.apply_new_skin_from_texture = gate_fn
    mod:info("[LA bridge] apply gate installed (raw replacement)")
end

-- audit 2026-06-07 (F7): install_apply_gate() RAW-replaces
-- LA.apply_new_skin_from_texture with a blocking closure but never restored it.
-- cosmetics_tweaker is is_togglable=true, and mod.on_disabled only flushes TPE,
-- so after an in-session F4 disable LA's OWN recolor for bridge-managed keys
-- stayed permanently blocked until a game restart. Restore the captured original
-- here and clear the installed flag so a later re-enable can re-install cleanly.
-- (Injected ItemMasterList/NetworkLookup entries can't be safely removed
-- mid-session — we deliberately leave those and only restore the apply fn.)
function M.uninstall_apply_gate()
    if not M._gate_installed then return end
    local LA = la()
    -- Only restore if LA is still present AND the live apply fn is still our gate
    -- (don't clobber a different override another mod may have layered on since).
    -- v0.9.33: the guard the comment above always described is now actually
    -- implemented via M._gate_fn (audit follow-up: comment/code mismatch). When the
    -- live fn is foreign we leave the chain intact; clearing _gate_installed below
    -- makes our gate (wherever it sits in the chain) a transparent passthrough.
    if LA and M._original_apply then
        if M._gate_fn == nil or LA.apply_new_skin_from_texture == M._gate_fn then
            LA.apply_new_skin_from_texture = M._original_apply
            mod:info("[LA bridge] apply gate uninstalled (original restored)")
        else
            -- Ungated: this is a teardown that could not fully complete; the user
            -- should see it without Debug Logging on.
            mod:warning("[LA bridge] live apply fn is not our gate (another mod layered on top since install); leaving the chain intact — our gate goes transparent instead of restoring")
        end
    end
    M._original_apply  = nil
    M._gate_fn         = nil
    M._gate_installed  = false
    M._bridge_active   = false
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
    -- Cosmetics-authored units carry their final materials in the compiled
    -- unit. They participate in the shared appearance/fallback registry but
    -- must never be handed to Loremaster's external painter.
    if M.custom_variants and M.custom_variants[armoury_key] then return true end
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
local _residency_diag_seen = {}

local function _residency_diag_once(reason, resource_type, path, slot, context)
    local key = table.concat({
        tostring(reason), tostring(resource_type), tostring(path),
        tostring(slot), tostring(context)
    }, "|")
    if _residency_diag_seen[key] then return end
    _residency_diag_seen[key] = true
    _plog("#749 residency SKIP ctx=%s type=%s slot=%s path=%s reason=%s",
        tostring(context or "?"), tostring(resource_type), tostring(slot),
        tostring(path), tostring(reason))
end

local function _paint_unit_is_live(unit, context)
    return RESIDENCY.live_unit(unit, Unit, _residency_diag_once, context)
end

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
--
-- v0.8.51-dev: bulk-extracted from LA's source `.unit` files in
-- `C:\Users\danjo\source\repos\Loremasters-Armoury\units\<dir>\<file>.unit`
-- for every kind="unit" shield variant. All 20 share the same
-- `mat_to_use = wpn_empire_handgun_02_t2`, so the parent_packages map
-- below is uniform across the family (see la_kind_unit_parent_packages
-- block further down).
--
-- Kerillian shields have TWO mat_slots in vanilla LA (slot1=handle,
-- slot2=shield). The current `Unit.set_texture_for_materials` painter
-- writes uniformly across all materials on the unit, so we use slot2
-- (the shield face — the primary visual element). The handle will
-- render with the same texture; visually imperfect but the prominent
-- visual element renders correctly. A future per-material painter
-- could refine this; for alpha it's acceptable.
--
-- Empire and Bardin shields are single-slot — straightforward.
local _LA_KIND_UNIT_TEXTURES = {
    -- ===== Empire (Kruber) — single slot1=shield =====
    Kruber_empire_shield_basic1 = {
        diff = "textures/Kruber_empire_shield_basic1/Kruber_empire_shield_basic1_diffuse",
        norm = "textures/Kruber_empire_shield_basic1/Kruber_empire_shield_basic1_normal",
        pack = "textures/Kruber_empire_shield_basic1/Kruber_empire_shield_basic1_combined",
    },
    Kruber_empire_shield_basic1_Ostermark01 = {
        diff = "textures/Kruber_empire_shield_basic1_Ostermark01/Kruber_empire_shield_basic1_Ostermark01_diffuse",
        norm = "textures/Kruber_empire_shield_basic1/Kruber_empire_shield_basic1_normal",
        pack = "textures/Kruber_empire_shield_basic1/Kruber_empire_shield_basic1_combined",
    },
    Kruber_empire_shield_basic2 = {
        diff = "textures/Kruber_empire_shield_basic2/Kruber_empire_shield_basic2_Ostland01_diffuse",
        norm = "textures/Kruber_empire_shield_basic2/Kruber_empire_shield_basic2_normal",
        pack = "textures/Kruber_empire_shield_basic2/Kruber_empire_shield_basic2_combined",
    },
    Kruber_empire_shield_basic2_Kotbs01 = {
        diff = "textures/Kruber_empire_shield_basic2_Kotbs01/Kruber_empire_shield_basic2_Kotbs01_diffuse",
        norm = "textures/Kruber_empire_shield_basic2/Kruber_empire_shield_basic2_normal",
        pack = "textures/Kruber_empire_shield_basic2/Kruber_empire_shield_basic2_combined",
    },
    Kruber_empire_shield_basic2_Middenheim = {
        diff = "textures/Kruber_empire_shield_basic2_Middenheim01B/Kruber_empire_shield_basic2_Middenheim01_diffuse",
        norm = "textures/Kruber_empire_shield_basic2/Kruber_empire_shield_basic2_normal",
        pack = "textures/Kruber_empire_shield_basic2/Kruber_empire_shield_basic2_combined",
    },
    Kruber_empire_shield_basic3_Middenheim01 = {
        diff = "textures/Kruber_empire_shield_basic3/Kruber_empire_shield_basic3_Middenheim01_diffuse",
        norm = "textures/Kruber_empire_shield_basic3/Kruber_empire_shield_basic3_normal",
        pack = "textures/Kruber_empire_shield_basic3/Kruber_empire_shield_basic3_combined",
    },

    -- ===== Bardin (Dwarf) — single slot1=Tex_0457_0 =====
    Bardin_dwarf_shield_basicClean_KarakNorn01 = {
        diff = "textures/Bardin_dwarf_shield_basicClean_KarakNorn01/Bardin_dwarf_shield_basicClean_KarakNorn01_diffuse",
        norm = "textures/Bardin_dwarf_shield_basicClean_KarakNorn01/Bardin_dwarf_shield_basicClean_KarakNorn01_normal",
        pack = "textures/Bardin_dwarf_shield_basicClean_KarakNorn01/Bardin_dwarf_shield_basicClean_KarakNorn01_combined",
    },
    Bardin_dwarf_shield_heroClean_KarakNorn01 = {
        diff = "textures/Bardin_dwarf_shield_heroClean_KarakNorn01/Bardin_dwarf_shield_heroClean_KarakNorn01_diffuse",
        norm = "textures/Bardin_dwarf_shield_heroClean_KarakNorn01/Bardin_dwarf_shield_heroClean_KarakNorn01_normal",
        pack = "textures/Bardin_dwarf_shield_heroClean_KarakNorn01/Bardin_dwarf_shield_heroClean_KarakNorn01_combined",
    },

    -- ===== Kerillian (Elf) — TWO mat_slots in vanilla LA (slot1=handle,
    --     slot2=shield); we use slot2 (shield face — primary visual).
    --     Two sub-groups by normal/pack base path (extracted verbatim from
    --     source `.unit` slot2 entries):
    --       basicClean group: `textures/elf_shield/Kerillian_elf_shield_basicClean_*`
    --       heroClean group:  `textures/elf_shield/Shield/Kerillian_elf_shield_heroClean_*`
    Kerillian_elf_shield_basic_Avelorn01_mesh = {
        -- Mesh path: Kerillian_elf_shield_heroClean_mesh_Avelorn01, but slot2
        -- in this .unit points to the basicClean-group normal/pack.
        -- diff filename oddity: ends in `_diffuse1` (with trailing 1).
        diff = "textures/Kerillian_elf_shield_basic_Avelorn01/Kerillian_elf_shield_basicClean_Avelorn01_diffuse1",
        norm = "textures/elf_shield/Kerillian_elf_shield_basicClean_normal",
        pack = "textures/elf_shield/Kerillian_elf_shield_basicClean_combined",
    },
    Kerillian_elf_shield_basic2_mesh = {
        diff = "textures/Kerillian_elf_shield_basic2_Griffongate01/Kerillian_elf_shield_basic2_Griffongate01_diffuse",
        norm = "textures/elf_shield/Kerillian_elf_shield_basicClean_normal",
        pack = "textures/elf_shield/Kerillian_elf_shield_basicClean_combined",
    },
    -- heroClean group (norm/pack under elf_shield/Shield/)
    Kerillian_elf_shield_heroClean_Saphery01 = {
        diff = "textures/Kerillian_elf_shield_heroClean_Saphery01/Kerillian_elf_shield_heroClean_Saphery01_diffuse",
        norm = "textures/elf_shield/Shield/Kerillian_elf_shield_heroClean_normal",
        pack = "textures/elf_shield/Shield/Kerillian_elf_shield_heroClean_combined",
    },
    Kerillian_elf_shield_heroClean_Caledor01 = {
        diff = "textures/Kerillian_elf_shield_heroClean_Caledor01/Kerillian_elf_shield_heroClean_Caledor01_diffuse",
        norm = "textures/elf_shield/Shield/Kerillian_elf_shield_heroClean_normal",
        pack = "textures/elf_shield/Shield/Kerillian_elf_shield_heroClean_combined",
    },
    Kerillian_elf_shield_heroClean_Avelorn02 = {
        diff = "textures/Kerillian_elf_shield_heroClean_Avelorn02/Kerillian_elf_shield_heroClean_Avelorn02_diffuse",
        norm = "textures/elf_shield/Shield/Kerillian_elf_shield_heroClean_normal",
        pack = "textures/elf_shield/Shield/Kerillian_elf_shield_heroClean_combined",
    },
    Kerillian_elf_shield_heroClean_Eataine01 = {
        diff = "textures/Kerillian_elf_shield_heroClean_Eataine01/Kerillian_elf_shield_heroClean_Eataine01_diffuse",
        norm = "textures/elf_shield/Shield/Kerillian_elf_shield_heroClean_normal",
        pack = "textures/elf_shield/Shield/Kerillian_elf_shield_heroClean_combined",
    },
    Kerillian_elf_shield_heroClean_Chrace01 = {
        diff = "textures/Kerillian_elf_shield_heroClean_Chrace01/Kerillian_elf_shield_heroClean_Chrace01_diffuse",
        norm = "textures/elf_shield/Shield/Kerillian_elf_shield_heroClean_normal",
        pack = "textures/elf_shield/Shield/Kerillian_elf_shield_heroClean_combined",
    },
    -- basicClean group (norm/pack under elf_shield/ directly)
    Kerillian_elf_shield_basicClean = {
        diff = "textures/Kerillian_elf_shield_basicClean_Eataine01/Kerillian_elf_shield_basicClean_Eataine01_diffuse",
        norm = "textures/elf_shield/Kerillian_elf_shield_basicClean_normal",
        pack = "textures/elf_shield/Kerillian_elf_shield_basicClean_combined",
    },
    -- Note: in source `.unit` the texture directory is "EagleGate01" (capital
    -- G) while the diffuse filename has lowercase "Eaglegate01". Match source.
    Kerillian_elf_shield_basic2_Eaglegate01 = {
        diff = "textures/Kerillian_elf_shield_basic2_EagleGate01/Kerillian_elf_shield_basic2_Eaglegate01_diffuse",
        norm = "textures/elf_shield/Kerillian_elf_shield_basicClean_normal",
        pack = "textures/elf_shield/Kerillian_elf_shield_basicClean_combined",
    },
    Kerillian_elf_shield_basicClean_Saphery01 = {
        diff = "textures/Kerillian_elf_shield_basicClean_Saphery01/Kerillian_elf_shield_basicClean_Saphery01_diffuse",
        norm = "textures/elf_shield/Kerillian_elf_shield_basicClean_normal",
        pack = "textures/elf_shield/Kerillian_elf_shield_basicClean_combined",
    },
    Kerillian_elf_shield_basicClean_Caledor01 = {
        diff = "textures/Kerillian_elf_shield_basicClean_Caledor01/Kerillian_elf_shield_basicClean_Caledor01_diffuse",
        norm = "textures/elf_shield/Kerillian_elf_shield_basicClean_normal",
        pack = "textures/elf_shield/Kerillian_elf_shield_basicClean_combined",
    },
    Kerillian_elf_shield_basicClean_Chrace01 = {
        diff = "textures/Kerillian_elf_shield_basicClean_Chrace01/Kerillian_elf_shield_basicClean_Chrace01_diffuse",
        norm = "textures/elf_shield/Kerillian_elf_shield_basicClean_normal",
        pack = "textures/elf_shield/Kerillian_elf_shield_basicClean_combined",
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
--
-- v0.8.51-dev: bulk-extracted across all 20 kind="unit" shields. LA
-- consistently uses `wpn_empire_handgun_02_t2` as the parent material
-- for every custom-mesh shield (Empire / Bardin / Kerillian), so the
-- map is uniform.
local _LA_HANDGUN_PARENT = "units/weapons/player/wpn_empire_handgun_02_t2/wpn_empire_handgun_02_t2"
M.la_kind_unit_parent_packages = {
    -- Empire (Kruber)
    Kruber_empire_shield_basic1                = _LA_HANDGUN_PARENT,
    Kruber_empire_shield_basic1_Ostermark01    = _LA_HANDGUN_PARENT,
    Kruber_empire_shield_basic2                = _LA_HANDGUN_PARENT,
    Kruber_empire_shield_basic2_Kotbs01        = _LA_HANDGUN_PARENT,
    Kruber_empire_shield_basic2_Middenheim     = _LA_HANDGUN_PARENT,
    Kruber_empire_shield_basic3_Middenheim01   = _LA_HANDGUN_PARENT,
    -- Bardin (Dwarf)
    Bardin_dwarf_shield_basicClean_KarakNorn01 = _LA_HANDGUN_PARENT,
    Bardin_dwarf_shield_heroClean_KarakNorn01  = _LA_HANDGUN_PARENT,
    -- Kerillian (Elf)
    Kerillian_elf_shield_basic_Avelorn01_mesh  = _LA_HANDGUN_PARENT,
    Kerillian_elf_shield_basic2_mesh           = _LA_HANDGUN_PARENT,
    Kerillian_elf_shield_heroClean_Saphery01   = _LA_HANDGUN_PARENT,
    Kerillian_elf_shield_heroClean_Caledor01   = _LA_HANDGUN_PARENT,
    Kerillian_elf_shield_heroClean_Avelorn02   = _LA_HANDGUN_PARENT,
    Kerillian_elf_shield_heroClean_Eataine01   = _LA_HANDGUN_PARENT,
    Kerillian_elf_shield_heroClean_Chrace01    = _LA_HANDGUN_PARENT,
    Kerillian_elf_shield_basicClean            = _LA_HANDGUN_PARENT,
    Kerillian_elf_shield_basic2_Eaglegate01    = _LA_HANDGUN_PARENT,
    Kerillian_elf_shield_basicClean_Saphery01  = _LA_HANDGUN_PARENT,
    Kerillian_elf_shield_basicClean_Caledor01  = _LA_HANDGUN_PARENT,
    Kerillian_elf_shield_basicClean_Chrace01   = _LA_HANDGUN_PARENT,
}

-- Preview-only scale multiplier per `kind="unit"` shield. Applied via
-- `Unit.set_local_scale(unit, 0, Vector3(s, s, s))` ONLY in the
-- LootItemUnitPreviewer (customization-preview) context — does NOT
-- affect in-game or inventory-mannequin rendering. Default 2.0 when
-- an entry is absent. Custom-mesh LA shields tend to render small in
-- the previewer's intrinsic zoom; this brings them to a visible size
-- comparable to vanilla shield illusions.
M.la_kind_unit_preview_scale_default = 2.0
M.la_kind_unit_preview_scale = {
    -- Kruber_empire_shield_basic1 = 2.0,  -- example override
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

-- v0.9.41-dev (#149): AV-safety precheck for painting a kind="unit" LA shield
-- in the "ingame" / "network_husk" contexts. `Unit.set_texture_for_materials`
-- is a C-level call that access-violates at offset 0x8 (BYPASSING pcall) when a
-- target material is the engine null sentinel (#ID[00000000]) — the failure
-- mode that kept the in-game paint gated off through v0.8.46/47/48. That null
-- case is specific to the customization PREVIEWER's narrow per-world resource
-- scope; the in-mission and remote-husk bodies spawn the LA mesh through the
-- real game pipeline, so its `mat_to_use` parent material
-- (wpn_empire_handgun_02_t2) is bound at engine level and the null case should
-- not occur. We still verify (non-fatally, every call pcall-wrapped) that the
-- unit carries at least one real (non-null) material and REFUSE to paint
-- otherwise, so a bad-material case degrades to "no heraldry" rather than
-- crashing mission start. Never calls Material.num_parameters / parameter_name
-- / parameter_type (those raise a resource_manager.cpp fault that bypasses
-- pcall — see cosmetics_tweaker.lua:435-438).
local function _kind_unit_paint_is_safe(unit, armoury_key, context)
    local ok, reason, count = RESIDENCY.unit_materials_resident(
        unit, Unit, Mesh, nil, context)
    if not ok then
        _plog("#149 paint SKIP %s ctx=%s: unit material closure failed reason=%s count=%s",
            tostring(armoury_key), tostring(context), tostring(reason), tostring(count))
        return false
    end
    return true
end

local function _paint_offhand_textures_locally(unit, variant, armoury_key, context)
    if not _paint_unit_is_live(unit, context) then return false end

    -- History (v0.8.43/44): the 0x8 AV in `Unit.set_texture_for_materials` on
    -- kind="unit" meshes is the customization PREVIEWER's null material
    -- (#ID[00000000]) — the LA mesh's compiled material isn't instantiated in
    -- the LootItemUnitPreviewer's per-world resource scope even though the
    -- package is globally loaded. That's why the previewer path first does
    -- Unit.set_all_materials(parent) to bind a real material. v0.9.41-dev (#149)
    -- re-enabled painting for the "ingame" / "network_husk" contexts (the real
    -- mission / husk bodies, where the parent material IS bound) behind the
    -- _kind_unit_paint_is_safe precheck — those were the host's bare-mesh and
    -- the client's no-skin symptoms. See the per-context routing below.
    if variant.kind == "unit" then
        -- Context routing for kind="unit" custom-mesh shields:
        --
        --   * "loot_previewer" (customization preview): the previewer's narrow
        --     per-world resource scope resolves the LA mesh's material to
        --     #ID[00000000] (null) at spawn, so we MUST Unit.set_all_materials
        --     the parent vanilla material before painting (else the paint AVs),
        --     and scale the unit up to a visible size. (v0.8.45-49 history.)
        --
        --   * "ingame" / "network_husk": the in-mission / remote-husk body
        --     spawns the LA mesh through the real game pipeline, so its
        --     `mat_to_use` parent material is already bound at engine level. We
        --     must NOT Unit.set_all_materials (doing so in v0.8.47 made the
        --     in-game mesh massive) and must NOT scale. We DO paint the heraldry
        --     textures (with an AV-safety precheck) so the shield isn't a bare
        --     imperial mesh — #149: the host saw an imperial shield WITHOUT the
        --     Kotbs LA skin in-mission, and the client saw the vanilla mesh.
        --     The previewer-only AV (null material) cannot occur here, but the
        --     precheck degrades a hypothetical bad-material case to "no paint"
        --     instead of crashing mission start.
        --
        --   * "hero_previewer" (inventory mannequin) / unknown: LA's own
        --     HeroPreviewer hook re-paints that path; we stay out (no paint).
        if context == "loot_previewer" then
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

            -- v0.8.49: scale up the unit in the customization preview only.
            -- kind="unit" meshes render visibly smaller than vanilla shield
            -- illusions in the previewer's intrinsic zoom; this normalizes them
            -- without affecting in-game or inventory-mannequin rendering.
            local scale = (M.la_kind_unit_preview_scale and M.la_kind_unit_preview_scale[armoury_key])
                or M.la_kind_unit_preview_scale_default or 1.0
            if scale ~= 1.0 and Unit.set_local_scale and Vector3 then
                local ok = pcall(Unit.set_local_scale, unit, 0, Vector3(scale, scale, scale))
                if M.trace then
                    mod:info("[LA fix kind=unit %s] Unit.set_local_scale(0, %sx) ok=%s",
                        tostring(armoury_key), tostring(scale), tostring(ok))
                end
            end
            -- Fall through to the texture-painting code below.
        elseif context == "ingame" or context == "network_husk" then
            -- v0.9.41-dev (#149): paint the heraldry onto the real in-mission /
            -- husk LA mesh. NO set_all_materials, NO scale (previewer-only).
            -- AV-safety precheck so a null-material case degrades to "no paint"
            -- instead of a C-level access violation that bypasses pcall.
            -- Fall through to the texture-painting code below.
        else
            -- "hero_previewer" or unknown: vanilla / LA's own hooks render it.
            if M.trace then
                mod:info("[LA bridge] kind=unit %s context=%s — skipping (rendered by vanilla/LA path)",
                    tostring(armoury_key), tostring(context))
            end
            return false
        end
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

    local bindings = {}
    if diff then bindings[#bindings + 1] = { slot = SHIELD_DIFF_SLOT, texture = diff } end
    if pack then bindings[#bindings + 1] = { slot = SHIELD_PACK_SLOT, texture = pack } end
    if norm then bindings[#bindings + 1] = { slot = SHIELD_NORM_SLOT, texture = norm } end
    if variant.special_textures then
        for _, tx in ipairs(variant.special_textures) do
            if tx then bindings[#bindings + 1] = { slot = tx.slot, texture = tx.texture } end
        end
    end

    if #bindings < 1 then return false end
    -- A globally resident texture set is unsafe if this exact spawned unit has
    -- null/unresolved materials. Run the same closure for texture-only and
    -- custom-mesh variants on every active consumer surface (#149/#742/#749).
    if not _kind_unit_paint_is_safe(unit, armoury_key, context) then return false end
    if variant.kind == "unit" then
        _plog("#149 paint OK %s ctx=%s — applying heraldry",
            tostring(armoury_key), tostring(context))
    end
    local resident, reason = RESIDENCY.texture_set_resident(
        bindings, Application, nil, context)
    if not resident then
        _plog("#749 paint SKIP %s ctx=%s: atomic texture closure failed reason=%s",
            tostring(armoury_key), tostring(context), tostring(reason))
        return false
    end
    for i = 1, #bindings do
        local binding = bindings[i]
        -- resource-safety: cos749-la-atomic-texture-closure
        Unit.set_texture_for_materials(unit, binding.slot, binding.texture)
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
-- itself is working. Usage: /la_force Kruber_Pureheart_helm_white
function M.force_apply(armoury_key)
    local LA = la()
    if not LA then mod:echo("[la_force] LA not loaded"); return end
    if not LA.SKIN_LIST or not LA.SKIN_LIST[armoury_key] then
        mod:echo("[la_force] unknown armoury_key: " .. tostring(armoury_key)); return
    end

    local target_unit_name = LA.SKIN_LIST[armoury_key].new_units and LA.SKIN_LIST[armoury_key].new_units[1]
    mod:echo("[la_force] looking for unit with unit_name=" .. tostring(target_unit_name))

    local p = mod._local_player_safe and mod._local_player_safe(Managers.player)
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
    local p = mod._local_player_safe and mod._local_player_safe(Managers.player)
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
