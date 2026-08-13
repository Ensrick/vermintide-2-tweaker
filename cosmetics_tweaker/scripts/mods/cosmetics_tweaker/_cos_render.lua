-- _cos_render.lua -- render-path scale/grip apply helpers + the shared _is_unit primitive.
--
-- Owns the weapon visual-override apply layer that the three render hooks in the
-- entry (GearUtils.create_equipment, MenuWorldPreviewer._spawn_item_post,
-- LootItemUnitPreviewer.spawn_units) drive: unit-path scale overrides
-- (_unit_path_scale_overrides + _breton_sword_thiccc), the grip-offset table
-- (_weapon_grip_offsets, empty extension point today), and the resolve/apply
-- helpers (_resolve_for_career / _resolve_render_unit_path / _resolve_factor /
-- _apply_unit_path_scale_hand / _scale_units / _offset_units). Also home to the
-- tiny _is_unit liveness primitive, promoted here because the glow subsystem
-- (still in the entry this phase) consumes it too.
-- Split out of the god file in v0.9.78-dev Phase 2 OOP split; no behavior change.
--
-- Owned by: cosmetics_tweaker.lua entry point. Consumed via: mod:dofile.
-- Shared state: captures the entry-installed mod._cos.weapon_appearance and
-- exports mod._cos.{is_unit, scale_units, offset_units,
-- apply_unit_path_scale_hand}. Identity, hand, renderer, hook, and lifecycle
-- ownership remain with Cosmetics; only one-shot transform math is delegated.

local mod = get_mod("cosmetics_tweaker")
local _WEAPON_APPEARANCE = mod._cos.weapon_appearance
assert(type(_WEAPON_APPEARANCE) == "table"
        and type(_WEAPON_APPEARANCE.apply) == "function",
    "Cosmetics WeaponAppearance owner must be installed before _cos_render")

-- ============================================================
-- Weapon Visual Overrides
-- ============================================================
-- ---------------------------------------------------------------------------
-- VISUAL OVERRIDES — TWO DIFFERENT SCHEMAS, INTENTIONALLY
-- ---------------------------------------------------------------------------
-- 1) Scale overrides:  keyed by UNIT PATH SUBSTRING. Match against the actual
--    model the engine loads (skin's right/left_hand_unit if a skin is equipped,
--    falling back to the item's own paths). This targets the MODEL, not the
--    item template, so:
--      - vanilla `es_bastard_sword` with any Bretonian skin       → matches
--      - `es_sword_shield_breton` (paired with shield)            → matches (right hand only)
--      - character_weapon_variants Imperial Longsword             → does NOT match
--        (uses bastard_sword_template but loads `wpn_2h_sword_*` model)
--      - any third-party item that swaps to a Bretonian model     → matches
--
-- 2) Grip-offset overrides: keyed by ITEM NAME and CAREER PREFIX. These adjust
--    `Unit.local_position` (Z axis is along the blade — see
--    `feedback_grip_offset_sign.md`: +Z lowers grip, -Z raises grip).
--
-- COVERAGE: scale runs on all three rendering paths (in-game / inventory
-- preview / illusion browser). Grip-offset runs ONLY on the in-game
-- GearUtils hook, intentionally — see `feedback_grip_offset_sign.md`
-- "preview shows un-offset weapon".
--
-- See "Three Rendering Paths" in DEVELOPMENT.md for the hook list and
-- `_spawn_item_post` / `LootItemUnitPreviewer.spawn_units` hooks in the entry.

-- Tiny liveness primitive. Promoted to mod._cos this phase (glow, still in the
-- entry, consumes it via an entry-local alias); defined here because the scale
-- apply helpers below are its heaviest caller.
local function _is_unit(v) return type(v) == "userdata" and pcall(Unit.alive, v) end

-- Toggle-gated factor function. Returns the {x,y,z} scale when the user has
-- enabled the Bretonian Longsword "thiccc" option in cosmetics_tweaker_data,
-- nil otherwise. Called fresh each apply so live setting changes take effect
-- without re-spawning.
local function _breton_sword_thiccc(get)
    if get("es_bastard_sword_thiccc") then
        return { 0.65, 1.0, 1.0 }
    end
    return nil
end

-- Unit-path scale entries. Schema:
--   pattern : literal substring matched via string.find(path, pattern, 1, true)
--   factor  : function(get) -> {x,y,z}|number|nil  OR  literal {x,y,z} OR number
--   hand    : "right" | "left" | nil (nil = both hands)
local _unit_path_scale_overrides = {
    {
        -- Bretonian Longsword model family. Covers wpn_emp_gk_sword_01_t1,
        -- _01_t2, _02_t1, _02_t2 plus their _runed_* and _magic_* variants.
        -- Used by ItemMasterList entries `es_bastard_sword` (and skins) and
        -- the right-hand sword of `es_sword_shield_breton` (paired with a
        -- GK shield in the left hand — `hand = "right"` keeps the shield
        -- at native scale).
        pattern = "wpn_emp_gk_sword_",
        factor  = _breton_sword_thiccc,
        hand    = "right",
    },
}

-- Grip-offset table. Keyed by weapon item-key, values are
-- { <career_prefix> = {x, y, z}, _default = {x, y, z} } where Z is along the
-- blade. EMPTY today — kept as the extension point. See
-- `feedback_grip_offset_sign.md` for sign convention (+Z lowers grip).
local _weapon_grip_offsets = {}

-- ============================================================
-- Helpers (parallel to weapon_tweaker; consolidate into a shared
-- module if a third mod ever needs them)
-- ============================================================

local function _resolve_for_career(overrides, career_name)
    if not overrides or not career_name then return nil end
    local best, best_len = nil, -1
    for prefix, value in pairs(overrides) do
        if prefix ~= "_default" and #prefix > best_len and career_name:sub(1, #prefix) == prefix then
            best, best_len = value, #prefix
        end
    end
    if best ~= nil then
        if best == false then return nil end
        return best
    end
    return overrides._default
end

-- Returns the unit path the engine would actually load for this hand: a
-- skin's path takes precedence over the base item's path (mirrors
-- BackendUtils.get_item_units' resolution at backend_utils.lua:171-189).
-- `skin` may be nil/"" → fall through to item_data[hand_field].
-- `hand_field` is "right_hand_unit" or "left_hand_unit".
-- Returns nil when neither source has a path for that hand (common for
-- single-hand weapons or for hat/portrait items).
-- Mirrors BackendUtils.get_item_units' skin-vs-base resolution: when a skin
-- is equipped, the skin's per-hand unit path takes precedence; otherwise fall
-- back to the base item_data's per-hand unit. Used ONLY by the in-game
-- `GearUtils.create_equipment` hook, which doesn't expose a pre-resolved
-- spawn_data array — it gets `result.skin` from the spawn result and we have
-- to look up the rendered path ourselves. The two menu hooks
-- (`HeroPreviewer._spawn_item`, `LootItemUnitPreviewer.spawn_units`) read
-- paths directly from `spawn_data[i].unit_name` instead, which is vanilla's
-- truth source after it called BackendUtils.get_item_units once. Don't add
-- new callers for menu paths — re-introducing this resolution chain risks
-- the cwv-clone `entry.name` drift bug fixed in v0.7.98.
local function _resolve_render_unit_path(item_data, skin, hand_field)
    if skin and skin ~= "" and WeaponSkins and WeaponSkins.skins then
        local s = WeaponSkins.skins[skin]
        if s and s[hand_field] then return s[hand_field] end
    end
    return item_data and item_data[hand_field] or nil
end

-- Resolve a factor (function | {x,y,z} | number) into the shared primitive's
-- plain-Lua {x,y,z} descriptor shape.
-- Functions receive a `get(id)` accessor for live mod settings, so toggling
-- a setting without re-spawning the unit is supported (next equip applies).
-- Returns nil if the factor function returned nil (toggle off).
local function _resolve_factor(factor)
    if type(factor) == "function" then
        factor = factor(function(id) return mod:get(id) end)
    end
    if not factor then return nil end
    if type(factor) == "table" then
        return { factor[1], factor[2], factor[3] }
    end
    return { factor, factor, factor }
end

-- Apply any matching unit-path scale to one hand's units. Pass nil for any
-- slot you don't have (the menu paths only have one Unit per hand; in-game
-- has both 3p and 1p). `hand_label` is "right" or "left" — used to filter
-- entries with `hand = "right"` etc. set.
-- No-op if `path` is nil (e.g. single-hand weapon's left side).
local function _apply_unit_path_scale_hand(unit_3p, unit_1p, path, hand_label)
    if not path then return end
    for _, ov in ipairs(_unit_path_scale_overrides) do
        if (ov.hand == nil or ov.hand == hand_label)
                and path:find(ov.pattern, 1, true) then
            local scale = _resolve_factor(ov.factor)
            if scale then
                local descriptor = { scale = scale }
                if unit_3p and _is_unit(unit_3p) then
                    _WEAPON_APPEARANCE.apply(unit_3p, descriptor)
                end
                if unit_1p and _is_unit(unit_1p) then
                    _WEAPON_APPEARANCE.apply(unit_1p, descriptor)
                end
            end
        end
    end
end

-- Convenience wrapper for the GearUtils path: resolves both hand paths from
-- the spawn result + base item, then applies matching scale to all four hand
-- units. Used by the in-game create_equipment hook only — menu paths build
-- their own Unit list (one per hand, not 3p/1p split).
local function _scale_units(result, item_data, skin)
    local right_path = _resolve_render_unit_path(item_data, skin, "right_hand_unit")
    local left_path  = _resolve_render_unit_path(item_data, skin, "left_hand_unit")
    _apply_unit_path_scale_hand(result.right_unit_3p, result.right_unit_1p, right_path, "right")
    _apply_unit_path_scale_hand(result.left_unit_3p,  result.left_unit_1p,  left_path,  "left")
end

-- Grip-offset apply. Keyed by item name + career prefix; adjusts each hand
-- unit's local_position. Runs only on the in-game GearUtils path (see the
-- COVERAGE note above). No-op unless the weapon has a _weapon_grip_offsets
-- entry that resolves for the career (empty table today).
local function _offset_units(slot_data, weapon_key, career_name)
    local overrides = _weapon_grip_offsets[weapon_key]
    if not overrides then return end
    local offset = _resolve_for_career(overrides, career_name)
    if not offset then return end
    local descriptor = { offset = { offset[1], offset[2], offset[3] } }
    for _, field in ipairs({ "left_unit_1p", "right_unit_1p", "left_unit_3p", "right_unit_3p" }) do
        local unit = slot_data[field]
        if unit and _is_unit(unit) then
            _WEAPON_APPEARANCE.apply(unit, descriptor)
        end
    end
end

-- Export the render-path apply helpers + the shared _is_unit primitive onto
-- mod._cos. The render hooks (create_equipment / _spawn_item_post /
-- spawn_units) stay in the entry and call scale_units/offset_units/
-- apply_unit_path_scale_hand via mod._cos.*; glow (also in the entry this
-- phase) consumes is_unit through an entry-local alias.
mod._cos.is_unit = _is_unit
mod._cos.scale_units = _scale_units
mod._cos.offset_units = _offset_units
mod._cos.apply_unit_path_scale_hand = _apply_unit_path_scale_hand
