-- _cos_glow.lua -- weapon glow apply subsystem (MaterialSettingsTemplates routing).
--
-- Owns the glow customization apply pipeline: the color-preset table
-- (_COLOR_PRESETS), the shader-variable brightness/group maps (_GLOW_VAR_BRIGHTNESS
-- + _GLOW_GROUP_COLOR_SETTING), the per-peer glow read helpers (_glow_get and the
-- _glow_master_mult / _glow_var_mult / _glow_override_enabled / _glow_main_rgb /
-- _glow_rgb_for_var family that thread a wearer peer_id through every setting read),
-- the wearer-of-unit resolver (_glow_owner_peer_for_unit), the per-unit paint
-- (_apply_glow_to_unit) and its batch wrapper (_apply_glow_override), the live-
-- preview re-paint (mod._reapply_glow_on_wielded), the template-mutation apply hook
-- (_hook_apply_with_template_mutation installed on GearUtils / CosmeticUtils / the
-- _G.apply_material_settings flow global), the custom _cosmetics_tweaker_glow
-- MaterialSettingsTemplate + its GearUtils.spawn_inventory_unit injection hook.
-- Split out of the god file in v0.9.79-dev Phase 3 OOP split; no behavior change.
--
-- Owned by: cosmetics_tweaker.lua entry point. Consumed via: mod:dofile (dofile'd
-- AFTER _cos_render, whose mod._cos.is_unit primitive this module captures).
-- Shared state:
--   * exports mod._cos.{apply_glow_override, glow_owner_peer_for_unit}; the three
--     render hooks in the entry (create_equipment / _spawn_item_post /
--     LootItemUnitPreviewer.spawn_units) call them via mod._cos.*.
--   * mod._glow_by_peer (per-peer glow cache) is initialized here and captured as
--     a module local; the per-peer GLOW broadcast RPC layer (stays in the entry)
--     writes/reads the SAME table via a byte-identical entry-local alias.
--   * mod._unit_to_backend_id (weak unit->backend_id map) is initialized here (its
--     primary reader _apply_glow_to_unit lives here); the render/preview hooks in
--     the entry populate it via mod._unit_to_backend_id directly (no local alias).
--   * mod.{_reapply_glow_on_wielded, _try_install_flow_glow_hook, _glow_call_counts,
--     _glow_hooks_installed} are set here; the glow picker calls
--     mod._reapply_glow_on_wielded, on_game_state_changed calls
--     mod._try_install_flow_glow_hook, and the /glow_status command (stays in the
--     entry) reads the two counter tables.
--   * reads mod._per_item_glow_runtime (owned/written by _glow_picker.lua).
-- The /glow_status and /glow_trace commands and the per-peer glow broadcast RPC
-- layer (#421-adjacent) stay in the entry; /dump_glows (a read-only dump with no
-- apply logic) stays in _cos_diagnostics.lua.

local mod = get_mod("cosmetics_tweaker")

-- _is_unit liveness primitive: promoted to mod._cos.is_unit by _cos_render.lua
-- (Phase 2). Captured as a module local so the moved apply functions below call
-- it byte-unchanged.
local _is_unit = mod._cos.is_unit

-- Two-helper debug-logging policy (PROJECT_STANDARDS.md section 3.6). Byte-identical
-- copies of the entry's _dbg / _dbg_alert so the moved glow functions keep calling
-- them unchanged. `_dbg` = confirmation (file only); `_dbg_alert` = unexpected,
-- LOG-ONLY via pcall-guarded engine printf (#427/issue 240: mod:warning posts
-- to CHAT under VMF defaults; printf survives mod-logging-OFF, never chat).
local function _dbg(fmt, ...)
    mod:debug("[cosmetics:dbg] " .. fmt, ...)
end

local function _dbg_alert(fmt, ...)
    if not pcall(printf, "[cosmetics:dbg] " .. fmt, ...) then
        pcall(printf, "[cosmetics:dbg] (alert format error: %s)", tostring(fmt))
    end
end

-- Glow override (v0.8.23-dev: redesigned per-family routing).
--
-- Decouples "user color choice" from "shader variable to write". The user picks
-- one RGB; we write it to whichever shader variables actually drive emissive on
-- the target weapon. Variables that don't exist on a given mesh silently no-op
-- via Unit.set_vector3_for_materials (verified empirically by `cos glow_scan`).
--
-- Probe-confirmed paintable variables per mesh family:
--   * `_runed_*` (themed Veteran AND Stylish loot-chest white) → `rune_emissive_color`
--   * `_magic_01` (Weavebound, no template) → 4 versus channels
--   * `_magic_02` (Shyish-Infused, `versus` template) → same 4 versus channels
-- We write all 5 candidate variables on every unit; only the relevant ones land.
-- color_dots intentionally omitted — probe showed minimal visible color
-- contribution and possibly drives particle behaviour we shouldn't perturb.
local _COLOR_PRESETS = {
    -- Preset keys preserved from older builds for user-save compatibility.
    -- HDR values >1 produce bloom; rune RGBs match the source-defined templates
    -- (weapon_material_settings_templates.lua), white is a new bright-bloom value.
    purple_glow  = { 3,    1,    9    },
    golden_glow  = { 8,    5,    1.5  },
    deep_crimson = { 7,    0,    0.1  },
    life_green   = { 7,    9,    0.1  },
    lileath      = { 5.8,  6.3,  9    },
    white_glow   = { 10,   10,   10   },
}

-- Variables to write per unit, with each variable's typical max brightness.
-- Writing user RGB scaled to that brightness preserves the natural visual
-- structure of multi-channel templates (versus has 5 channels at very
-- different brightness levels — writing them all to user RGB uniformly
-- caused the v0.8.29 over-bright bug on Shyish-Infused weapons).
-- Brightness reference values come from the source-defined templates
-- (versus channels at gear_utils.lua's MaterialSettingsTemplates.versus,
-- rune_emissive_color from the rune-family templates max=9 from lileath).
-- A weapon's mesh exposes only the variables for its own family; the rest
-- silently no-op via Unit.set_vector3_for_materials.
-- Each entry: native brightness + per-channel multiplier setting + visual
-- group. The "group" maps to a per-channel COLOR picker when the user
-- enables `glow_per_channel_color_enable`, so multi-channel magic-family
-- weapons can have different colors per gradient/dots element.
-- Visual groups (per probe v0.8.22 on Weavebound Bret longsword):
--   "rune"  → drives rune_emissive_color (themed + Stylish meshes only)
--   "lower" → drives lower part of gradient on `_magic_*` (glow_high + glow_low)
--   "upper" → drives upper part of gradient on `_magic_*` (smoke_high + smoke_low)
--   "dots"  → drives the dot particles (color_dots)
local _GLOW_VAR_BRIGHTNESS = {
    rune_emissive_color = { brightness = 9,    setting = "glow_mult_rune",       group = "rune"  },
    color_glow_high     = { brightness = 4,    setting = "glow_mult_glow_high",  group = "lower" },
    color_glow_low      = { brightness = 1,    setting = "glow_mult_glow_low",   group = "lower" },
    color_smoke_high    = { brightness = 0.22, setting = "glow_mult_smoke_high", group = "upper" },
    color_smoke_low     = { brightness = 0.06, setting = "glow_mult_smoke_low",  group = "upper" },
    color_dots          = { brightness = 8.35, setting = "glow_mult_dots",       group = "dots"  },
}

-- Maps visual group → VMF setting key holding the chosen preset for that
-- group. Only consulted when `glow_per_channel_color_enable` is true.
-- "rune" intentionally absent: rune-family weapons only have one channel,
-- so per-channel separation is meaningless — they always use the main color.
local _GLOW_GROUP_COLOR_SETTING = {
    lower = "glow_color_lower_gradient",
    upper = "glow_color_upper_gradient",
    dots  = "glow_color_dots",
}

-- v0.9.0-dev: per-peer glow channel.
--
-- BEFORE: every glow read called `mod:get("...")` against the LOCAL viewer's
-- settings. When painting a remote husk, the viewer's chosen glow was applied
-- to the wearer's weapon — i.e. host saw client's weapon glowing with HOST's
-- color, not the client's. Bug 4 in the host/client desync investigation.
--
-- NOW: a new RPC channel `cos_glow_apply` (host-authoritative, mirrors
-- cos_la_apply) broadcasts each peer's glow state. Every machine caches all
-- known peers' state in `_glow_by_peer`. The glow read helpers accept an
-- optional `peer_id` arg; when set and is NOT the local player, settings are
-- read from `_glow_by_peer[peer_id]` instead of `mod:get`. The apply hook
-- resolves owner-of-unit at call time and threads peer_id through every read.
--
-- Missing cache entry (haven't received that peer's state yet, or they had
-- the bridge dormant) → returns nil from every read → no override → wearer
-- shows vanilla glow. Never bleeds the local viewer's color onto someone
-- else's weapon.
mod._glow_by_peer = mod._glow_by_peer or {}
local _glow_by_peer = mod._glow_by_peer

local function _glow_local_peer_id()
    local pm = Managers and Managers.player
    local lp = mod._local_player_safe and mod._local_player_safe(pm)
    return lp and lp.peer_id
end

local function _glow_is_local_peer(peer_id)
    if not peer_id then return true end  -- nil → caller wants local (default)
    local local_peer = _glow_local_peer_id()
    return local_peer == peer_id
end

-- Look up a per-peer glow setting. Returns nil when the peer is remote AND
-- their state hasn't been received yet (don't fall back to local viewer's
-- setting — that's the exact bug we're fixing).
local function _glow_get(peer_id, key)
    if _glow_is_local_peer(peer_id) then
        return mod:get(key)
    end
    local state = _glow_by_peer[peer_id]
    if not state then return nil end
    return state[key]
end

local function _glow_master_mult(peer_id)
    local v = _glow_get(peer_id, "glow_mult_master")
    return type(v) == "number" and v or 1.0
end

local function _glow_var_mult(setting, peer_id)
    if not setting then return 1.0 end
    local v = _glow_get(peer_id, setting)
    return type(v) == "number" and v or 1.0
end

local function _glow_override_enabled(peer_id)
    return _glow_get(peer_id, "glow_override_enable") == true
end

-- Resolves a preset key to RGB. The special key "default" (and unknown keys)
-- return nil — caller treats nil as "don't override this channel, leave
-- vanilla's value in place".
local function _resolve_preset_rgb(key)
    if not key or key == "default" then return nil end
    return _COLOR_PRESETS[key]
end

local function _glow_main_rgb(peer_id)
    if not _glow_override_enabled(peer_id) then return nil end
    return _resolve_preset_rgb(_glow_get(peer_id, "glow_override_preset"))
end

-- RGB to use for a given variable. When per-channel is enabled, the magic-
-- family groups (lower/upper/dots) consult their own dropdowns; rune-family
-- always uses the main picker (only one channel — per-channel split would be
-- meaningless). Returns nil when:
--   * override toggle is OFF, or
--   * the relevant dropdown is set to "default" — meaning this specific
--     variable should NOT be overridden, vanilla's value stays.
-- v0.9.6 M2: weak-table unit→backend_id mapping. Populated by the
-- GearUtils.create_equipment hook (line ~3416). Weak keys so units that
-- get destroyed auto-clean. Used by _apply_glow_to_unit to resolve which
-- backend_id's per-item glow override to apply.
mod._unit_to_backend_id = mod._unit_to_backend_id or setmetatable({}, { __mode = "k" })
mod._unit_glow_context = mod._unit_glow_context or setmetatable({}, { __mode = "k" })

-- #574: backend ids are owner-local and therefore cannot identify a weapon on
-- another peer.  Keep a render identity beside every spawned hand unit so the
-- receiver can constrain the wearer's active payload to the exact wielded
-- slot/illusion instead of painting every glow-capable unit it encounters.
local function _bind_glow_unit(unit, backend_id, skin, slot_name, item_name, item_template)
    if not unit or not _is_unit(unit) then return end
    if backend_id ~= nil then mod._unit_to_backend_id[unit] = backend_id end
    mod._unit_glow_context[unit] = {
        skin = skin or "",
        slot_name = slot_name,
        item_name = item_name,
        item_template = item_template,
    }
end

local function _remote_glow_context_matches(ctx, peer_state)
    if type(ctx) ~= "table" then return false end
    local expected_skin = peer_state.active_per_item_glow_skin
    if expected_skin == nil then
        local identity = peer_state.active_per_item_glow_identity
        expected_skin = type(identity) == "string" and identity:match("|skin:(.*)$") or nil
    end
    if expected_skin ~= nil and tostring(ctx.skin or "") ~= tostring(expected_skin) then return false end
    local expected_slot = peer_state.active_per_item_glow_slot
    if expected_slot and ctx.slot_name and expected_slot ~= ctx.slot_name then return false end
    local expected_name = peer_state.active_per_item_glow_item_name
    if expected_name and ctx.item_name and expected_name ~= ctx.item_name then return false end
    local expected_template = peer_state.active_per_item_glow_item_template
    if expected_template and ctx.item_template and expected_template ~= ctx.item_template then return false end
    return true
end

local function _remote_glow_matches(unit, peer_state)
    return _remote_glow_context_matches(mod._unit_glow_context[unit], peer_state)
end

local function _glow_rgb_for_var(var_name, peer_id)
    -- v0.9.6 M2: per-item RUNE override is applied DIRECTLY in
    -- _apply_glow_to_unit (before this function gets called), so the
    -- per-item path doesn't go through here. This function handles the
    -- existing global override logic for both rune AND magic-family
    -- shader vars.
    if not _glow_override_enabled(peer_id) then return nil end
    local info = _GLOW_VAR_BRIGHTNESS[var_name]
    local group = info and info.group
    if _glow_get(peer_id, "glow_per_channel_color_enable") then
        local setting = group and _GLOW_GROUP_COLOR_SETTING[group]
        if setting then
            local key = _glow_get(peer_id, setting)
            -- Per-channel dropdown drives this variable. "default" → skip.
            -- Any concrete preset → use it. Unknown key → fall through to main.
            if key == "default" then return nil end
            local rgb = _resolve_preset_rgb(key)
            if rgb then return rgb end
        end
    end
    -- Fallback: main color picker (also returns nil if main is "default")
    return _glow_main_rgb(peer_id)
end

-- Resolve the wearer peer for the unit being painted. Used by the per-peer
-- glow hook to thread owner identity through. Returns nil for non-player
-- units (NPC display weapons, drops, etc.) — caller treats nil as "local
-- viewer's settings" which is the historical behavior for those paths.
local function _glow_owner_peer_for_unit(unit)
    if not unit then return nil end
    local pm = Managers and Managers.player
    if not pm then return nil end
    -- 1. Direct owner lookup (works for local player + bots; sometimes
    -- returns nil during mission-spawn race per the memory note).
    if pm.owner then
        local owner = pm:owner(unit)
        if owner and owner.peer_id then return owner.peer_id end
    end
    -- 2. Husk-side fallback: the player_unit's inventory_system has
    -- `_owner_player_id` set; not the same as peer_id but lookup via the
    -- player table works.
    if ScriptUnit and ScriptUnit.has_extension then
        local inv = ScriptUnit.has_extension(unit, "inventory_system")
        if inv and inv._owner_player_id then
            -- _owner_player_id is the unique id; walk human players to find peer
            if pm._human_players then
                for _, p in pairs(pm._human_players) do
                    if p.player_unit == unit then return p.peer_id end
                end
            end
        end
        -- 3. Last-resort husk: weapon/hat units carry no inventory_system,
        -- but their parent player_unit does. We don't traverse parents here —
        -- caller passes the OWNING player_unit (resolved upstream via
        -- equipment.left_hand_wielded_unit_3p etc. → owner of player_unit).
    end
    return nil
end

-- v0.9.0-dev: per-peer glow apply. `owner_peer_id` resolves which peer's
-- settings drive the override. nil means "local viewer" (legacy behavior for
-- NPC display weapons, pickups, etc.).
local function _apply_glow_to_unit(unit, owner_peer_id)
    if not unit or not _is_unit(unit) then return end
    -- v0.9.6 M2: per-item override BEFORE the global toggle gate. The
    -- popup is "always available regardless of toggle" per user direction.
    -- Rune and magic components use HDR scaling: user RGB / 255 × native template
    -- brightness (9 for rune_emissive_color per _GLOW_VAR_BRIGHTNESS)
                -- × intensity slider value. intensity=0 → skip (vanilla shows through).
    do
        local pi
        if owner_peer_id and not _glow_is_local_peer(owner_peer_id) then
            local peer_state = _glow_by_peer[owner_peer_id]
            pi = peer_state and _remote_glow_matches(unit, peer_state)
                and peer_state.active_per_item_glow or nil
        elseif mod._per_item_glow_runtime and mod._unit_to_backend_id then
            local bid = mod._unit_to_backend_id[unit]
            pi = bid and mod._per_item_glow_runtime[bid] or nil
        end
        if type(pi) == "table" then
                -- v0.9.8: per-item explicit OFF toggle. If user disabled
                -- glow for this item, paint zeros (effectively disable)
                -- and skip both per-item and global paths. Vanilla
                -- material set_vector3 with zeros = no emissive output.
                if pi.disabled then
                    for var_name, _ in pairs(_GLOW_VAR_BRIGHTNESS) do
                        pcall(Unit.set_vector3_for_materials, unit, var_name, Vector3(0, 0, 0))
                    end
                    return
                end
                -- v0.9.8: helper for per-component HDR scaling. Reads
                -- shader var's native brightness from _GLOW_VAR_BRIGHTNESS,
                -- multiplies by user intensity, divides by 255 (user RGB
                -- is 0-255), writes to material.
                local function _paint_var(var_name, r, g, b, intensity)
                    local info = _GLOW_VAR_BRIGHTNESS[var_name]
                    if not info then return end
                    -- Peer payloads are untrusted. Ignore malformed component
                    -- values rather than allowing arithmetic on strings/tables.
                    if type(r) ~= "number" or type(g) ~= "number" or type(b) ~= "number"
                        or type(intensity) ~= "number" then return end
                    r = math.max(0, math.min(255, r))
                    g = math.max(0, math.min(255, g))
                    b = math.max(0, math.min(255, b))
                    intensity = math.max(0, math.min(5, intensity))
                    local scale = (info.brightness or 1) * intensity / 255
                    pcall(Unit.set_vector3_for_materials, unit, var_name,
                        Vector3(r * scale, g * scale, b * scale))
                end
                local function _component_active(component)
                    return type(component) == "table"
                        and type(component.intensity) == "number"
                        and component.intensity > 0
                end
                -- RUNE family: single channel.
                if _component_active(pi.rune) then
                    _paint_var("rune_emissive_color",
                        pi.rune.r or 0, pi.rune.g or 0, pi.rune.b or 0, pi.rune.intensity)
                end
                -- v0.9.8: MAGIC family components. Each component spans
                -- multiple shader vars (lower = glow_high+glow_low,
                -- upper = smoke_high+smoke_low, dots = single). All share
                -- the user's RGB at scaled brightness so vanilla's
                -- coordinated brightness pairs remain proportional.
                if _component_active(pi.lower) then
                    _paint_var("color_glow_high",
                        pi.lower.r or 0, pi.lower.g or 0, pi.lower.b or 0, pi.lower.intensity)
                    _paint_var("color_glow_low",
                        pi.lower.r or 0, pi.lower.g or 0, pi.lower.b or 0, pi.lower.intensity)
                end
                if _component_active(pi.upper) then
                    _paint_var("color_smoke_high",
                        pi.upper.r or 0, pi.upper.g or 0, pi.upper.b or 0, pi.upper.intensity)
                    _paint_var("color_smoke_low",
                        pi.upper.r or 0, pi.upper.g or 0, pi.upper.b or 0, pi.upper.intensity)
                end
                if _component_active(pi.dots) then
                    _paint_var("color_dots",
                        pi.dots.r or 0, pi.dots.g or 0, pi.dots.b or 0, pi.dots.intensity)
                end
                -- If ANY component painted, treat per-item as fully
                -- handled — skip global override. Detection: at least
                -- one component had intensity > 0.
                if _component_active(pi.rune)
                    or _component_active(pi.lower)
                    or _component_active(pi.upper)
                    or _component_active(pi.dots) then
                    return
                end
        end
    end
    if not _glow_override_enabled(owner_peer_id) then return end
    -- Per-variable: skip if rgb is nil (main = "default" AND no per-channel
    -- color set for this var's group), else write user RGB scaled to native
    -- brightness × master × per-channel multiplier. mult=0 also skips.
    local master_mult = _glow_master_mult(owner_peer_id)
    for var_name, info in pairs(_GLOW_VAR_BRIGHTNESS) do
        local rgb = _glow_rgb_for_var(var_name, owner_peer_id)
        if rgb then
            local var_mult = _glow_var_mult(info.setting, owner_peer_id)
            if var_mult > 0 then
                local user_max = math.max(rgb[1], rgb[2], rgb[3], 0.0001)
                local effective = info.brightness * var_mult * master_mult
                local s = effective / user_max
                pcall(Unit.set_vector3_for_materials, unit, var_name,
                    Vector3(rgb[1] * s, rgb[2] * s, rgb[3] * s))
            end
        end
    end
end

-- v0.9.6 M2: helper for popup live-preview. Re-applies glow on the
-- currently-wielded weapon units. Called from glow picker's on_change
-- callback during slider drag. Best-effort; failures silent.
mod._reapply_glow_on_wielded = function()
    local pm = Managers and Managers.player
    local lp = mod._local_player_safe and mod._local_player_safe(pm)
    local pu = lp and lp.player_unit
    if not (pu and Unit.alive(pu) and ScriptUnit and ScriptUnit.has_extension) then return end
    local ext = ScriptUnit.has_extension(pu, "inventory_system")
    if not ext then return end
    local sd_fn = ext.get_wielded_slot_data
    local slot_data = sd_fn and ext:get_wielded_slot_data()
    if not slot_data then return end
    for _, field in ipairs({ "right_unit_1p", "right_unit_3p", "left_unit_1p", "left_unit_3p" }) do
        local u = slot_data[field]
        if u and _is_unit(u) then
            pcall(_apply_glow_to_unit, u, _glow_local_peer_id())
        end
    end
end

-- Repaint a wearer's already-spawned weapon units when an authoritative peer
-- update arrives; otherwise the RGB would not become visible until a re-wield.
mod._reapply_glow_for_peer = function(peer_id)
    if not peer_id then return 0 end
    local pm = Managers and Managers.player
    local players = pm and pm._human_players
    if type(players) ~= "table" then return 0 end
    for _, player in pairs(players) do
        if player and player.peer_id == peer_id then
            local pu = player.player_unit
            local ext = pu and ScriptUnit and ScriptUnit.has_extension
                and ScriptUnit.has_extension(pu, "inventory_system")
            local slot_data = ext and ext.get_wielded_slot_data and ext:get_wielded_slot_data()
            local equipment = ext and ext._equipment
            local units = {}
            if slot_data then
                for _, field in ipairs({ "right_unit_1p", "right_unit_3p", "left_unit_1p", "left_unit_3p" }) do
                    if slot_data[field] then units[#units + 1] = slot_data[field] end
                end
            end
            if equipment then
                for _, field in ipairs({ "right_hand_wielded_unit_3p", "left_hand_wielded_unit_3p",
                    "right_hand_wielded_unit", "left_hand_wielded_unit" }) do
                    if equipment[field] then units[#units + 1] = equipment[field] end
                end
            end
            local wielded_slot = equipment and equipment.wielded_slot
            local wielded_data = (equipment and equipment.slots and wielded_slot)
                and equipment.slots[wielded_slot] or slot_data
            local item_data = wielded_data and wielded_data.item_data
            local applied = 0
            local remote = not _glow_is_local_peer(peer_id)
            local peer_state = remote and _glow_by_peer[peer_id] or nil
            for _, unit in pairs(units) do
                _bind_glow_unit(unit, nil, wielded_data and wielded_data.skin,
                    wielded_slot, item_data and item_data.name, item_data and item_data.template)
                -- Report success only for a unit that can actually consume the
                -- authoritative payload. A spawned husk with incomplete
                -- slot/skin identity must keep the bounded join retry armed.
                if not remote or (peer_state and _remote_glow_matches(unit, peer_state)) then
                    pcall(_apply_glow_to_unit, unit, peer_id)
                    applied = applied + 1
                end
            end
            return applied
        end
    end
    return 0
end

-- Backward-compatible alias used by the existing call site at create_equipment.
local function _glow_preset_rgb() return _glow_main_rgb() end

-- v0.9.0-dev: accept owner peer so glow on remote players' weapons reads from
-- the wearer's settings, not the local viewer's. Caller MUST pass owner peer
-- explicitly — units array doesn't carry per-unit owner info, so the resolution
-- happens at the create_equipment hook where we know the player_unit being
-- equipped.
local function _apply_glow_override(units, owner_peer_id)
    for _, u in pairs(units) do _apply_glow_to_unit(u, owner_peer_id) end
end

-- Glow override (v0.8.16-dev): TEMPLATE MUTATION approach.
--
-- Why we changed mechanism: hook_safe-overlay (v0.8.4-v0.8.15) reliably painted
-- 3p but never visually changed 1p, even though `Unit.set_vector3_for_materials`
-- returned ok=true on every 1p call (verified via [GLOW-trace] in v0.8.5).
-- User confirmed vanilla 1P glow IS paintable (a deep_crimson skin glows red
-- in 1P with override off), so it's not a 1P-shader-doesn't-have-the-variable
-- limit. Theory: when our overlay runs after vanilla's apply_material_settings,
-- something in the 1P spawn path re-binds the original template values (likely
-- the unit's flow graph fires on visibility-toggle / wield and reads the original
-- template via a separate code path). Best counter: don't overlay AFTER vanilla;
-- instead, mutate `MaterialSettingsTemplates[name]` to hold our values BEFORE
-- vanilla reads them, then restore the table after vanilla returns. Vanilla's
-- own writes carry our values. NoGlow uses a similar template-mutation trick
-- to zero out emissive.
-- Per-hook call counters for `cos glow_status` diagnostics.
mod._glow_call_counts = { gear = 0, flow = 0, cosmetic = 0 }
mod._glow_hooks_installed = { gear = false, flow = false, cosmetic = false }

local function _hook_apply_with_template_mutation(class_id, label)
    mod:hook(class_id, "apply_material_settings", function(func, unit, material_settings_name)
        mod._glow_call_counts[label] = (mod._glow_call_counts[label] or 0) + 1
        -- v0.9.0-dev: resolve the wearer of the unit to thread per-peer glow
        -- settings through. For local player + bots → local peer_id (reads
        -- mod:get). For remote husks → wearer peer_id (reads _glow_by_peer).
        -- For non-player units (NPC display weapons, pickups, drops) →
        -- nil → defaults to local viewer (legacy behavior; nobody owns
        -- these). The lookup is fast (single :owner() call) — no measurable
        -- overhead vs the previous fully-local read.
        local owner_peer_id = _glow_owner_peer_for_unit(unit)
        if not _glow_override_enabled(owner_peer_id) then
            if mod:get("glow_trace") then
                _dbg("[GLOW] %s call template=%s peer=%s (override OFF, passthrough)",
                    label, tostring(material_settings_name), tostring(owner_peer_id))
            end
            return func(unit, material_settings_name)
        end
        local template = MaterialSettingsTemplates and MaterialSettingsTemplates[material_settings_name]
        if not template then
            if mod:get("glow_trace") then
                _dbg("[GLOW] %s call template=%s peer=%s (template nil, passthrough)",
                    label, tostring(material_settings_name), tostring(owner_peer_id))
            end
            return func(unit, material_settings_name)
        end
        if mod:get("glow_trace") then
            _dbg("[GLOW] %s mutate template=%s peer=%s",
                label, tostring(material_settings_name), tostring(owner_peer_id))
        end
        -- Mutate per-variable. Skip variables whose color resolves to nil
        -- (= "Default" preset OR main is "Default" with no per-channel color
        -- for this variable's group) — the template's vanilla value passes
        -- through to the spawn unchanged. Skip variables whose mult is 0.
        -- Color and brightness come from _glow_rgb_for_var (respects per-
        -- channel-color toggle) and the var's mult setting.
        local master_mult = _glow_master_mult(owner_peer_id)
        local saved = {}
        for var_name, entry in pairs(template) do
            if entry.type == "vector3" then
                local var_rgb = _glow_rgb_for_var(var_name, owner_peer_id)
                local info = _GLOW_VAR_BRIGHTNESS[var_name]
                local var_mult = info and _glow_var_mult(info.setting, owner_peer_id) or 1.0
                if var_rgb and var_mult > 0 then
                    saved[var_name] = { x = entry.x, y = entry.y, z = entry.z }
                    local orig_max = math.max(entry.x, entry.y, entry.z, 0.0001)
                    local user_max = math.max(var_rgb[1], var_rgb[2], var_rgb[3], 0.0001)
                    local s = (orig_max * var_mult * master_mult) / user_max
                    entry.x, entry.y, entry.z = var_rgb[1] * s, var_rgb[2] * s, var_rgb[3] * s
                end
            end
        end
        local ok, err = pcall(func, unit, material_settings_name)
        -- Restore originals so other consumers of the template see vanilla values
        for var_name, orig in pairs(saved) do
            local entry = template[var_name]
            if entry then entry.x, entry.y, entry.z = orig.x, orig.y, orig.z end
        end
        if not ok then _dbg_alert("[GLOW] %s vanilla apply errored: %s", label, tostring(err)) end
    end)
    mod._glow_hooks_installed[label] = true
end

_hook_apply_with_template_mutation("GearUtils", "gear")
if rawget(_G, "CosmeticUtils") and CosmeticUtils.apply_material_settings then
    _hook_apply_with_template_mutation("CosmeticUtils", "cosmetic")
else
    mod:info("[GLOW] CosmeticUtils.apply_material_settings nil at hook time")
end

-- v0.9.0-dev: `_G.apply_material_settings` is a BARE GLOBAL declared in
-- `scripts/flow/flow_callbacks_foundation.lua:896`. That file is loaded
-- lazily by Stingray's flow graph (typically first hub/level enter), not
-- during boot. VMF mod-load runs before any flow node fires, so at hook
-- install time the symbol is genuinely nil. Try eagerly; on miss, retry from
-- mod.on_game_state_changed (defined earlier). NOTE: this _G site is the
-- bare-global path used ONLY by NPC display weapons / keep weapon racks —
-- player wielded weapons, husks, projectiles, pickups, and previewer all
-- route through GearUtils.apply_material_settings (already hooked above),
-- so this is purely a coverage-completeness fix for hub setpieces.
local function _try_install_flow_glow_hook()
    if mod._glow_hooks_installed.flow then return true end
    if not _G.apply_material_settings then return false end
    _hook_apply_with_template_mutation(_G, "flow")
    mod:info("[GLOW] _G.apply_material_settings hook installed (deferred)")
    return true
end

if not _try_install_flow_glow_hook() then
    mod:info("[GLOW] _G.apply_material_settings nil at boot; will retry on game-state change")
end
mod._try_install_flow_glow_hook = _try_install_flow_glow_hook

-- Custom template + spawn-time injection for non-templated meshes.
--
-- Stylish (`_runed_01`) loot-chest white-glow weapons and Weavebound (`_magic_01`)
-- WoM Athanor weapons have NO `material_settings_name` on their skins. Vanilla
-- never calls `apply_material_settings` on them, so our template-mutation hook
-- never fires. The previous direct post-spawn paint at `create_equipment`
-- (`_apply_glow_override`) writes via `Unit.set_vector3_for_materials` BUT
-- doesn't bind on 1P units (same engine-internal rejection that bit themed
-- weapons in v0.8.4-v0.8.15 before we switched to template mutation).
--
-- Solution: register our own template containing every variable these meshes
-- might expose, then hook `GearUtils.spawn_inventory_unit` to inject the
-- template name when the override is on AND the weapon's mesh suffix matches
-- a non-templated paintable family. Vanilla then calls apply_material_settings
-- with our template, our template-mutation hook fires, mutates per-variable
-- to user RGB, vanilla writes via the trusted path that DOES bind 1P. Solves
-- both problems with the same mechanism that fixed themed weapons.
--
-- Initial values are the typical brightness per variable; the mutation hook's
-- per-variable scaling preserves these magnitudes when applying user RGB.
if rawget(_G, "MaterialSettingsTemplates") then
    MaterialSettingsTemplates._cosmetics_tweaker_glow = {
        rune_emissive_color = { type = "vector3", x = 9,    y = 9,    z = 9    },
        color_glow_high     = { type = "vector3", x = 4,    y = 4,    z = 4    },
        color_glow_low      = { type = "vector3", x = 1,    y = 1,    z = 1    },
        color_smoke_high    = { type = "vector3", x = 0.22, y = 0.22, z = 0.22 },
        color_smoke_low     = { type = "vector3", x = 0.06, y = 0.06, z = 0.06 },
        -- color_dots included so users can experiment with it on Weavebound /
        -- Stylish meshes via the advanced multiplier. Per-channel mult defaults
        -- to 0 (skip) so the channel is inert by default — probe (v0.8.22)
        -- showed it darkens Weavebound when set high.
        color_dots          = { type = "vector3", x = 8.35, y = 8.35, z = 8.35 },
    }
end

mod:hook("GearUtils", "spawn_inventory_unit", function(func, world, hand, item_template, item_units, slot_name, item_data, owner_unit_1p, owner_unit_3p, unit_template, extra_extension_data, ammo_percent, material_settings_name)
    -- Only inject when override is on AND the weapon currently has no native template.
    -- v0.9.37-dev: `glow_override_enable` no longer exists as a VMF setting (the
    -- global "Weapon Glow Override" menu was removed in favor of the per-item
    -- Glow Picker). mod:get returns nil → this branch never fires → injection
    -- is inert. Left guarded (not ripped out) so a future global-glow feature
    -- could re-enable it by restoring the setting. The Glow Picker drives
    -- non-templated meshes via its own per-item runtime path, not this injection.
    if material_settings_name == nil and mod:get("glow_override_enable") and item_units then
        local mesh = item_units[hand .. "_hand_unit"]
        if mesh and (mesh:find("_runed_01$") or mesh:find("_magic_01$")) then
            material_settings_name = "_cosmetics_tweaker_glow"
            if mod:get("glow_trace") then
                _dbg("[GLOW] inject template for mesh=%s hand=%s", tostring(mesh), tostring(hand))
            end
        end
    end
    return func(world, hand, item_template, item_units, slot_name, item_data, owner_unit_1p, owner_unit_3p, unit_template, extra_extension_data, ammo_percent, material_settings_name)
end)

-- ============================================================
-- Exports (mod._cos) consumed by the render hooks in the entry
-- ============================================================
-- Coupling point 2 (peer-owner lookup): the in-game create_equipment hook resolves
-- the wearer via glow_owner_peer_for_unit, then batch-paints via apply_glow_override.
-- The two menu-preview render hooks call apply_glow_override with no owner (nil =
-- local viewer, historical behavior for non-owned preview units). Same consumption
-- pattern as the Phase 2 scale/grip exports (mod._cos.scale_units etc.).
mod._cos.apply_glow_override = _apply_glow_override
mod._cos.glow_owner_peer_for_unit = _glow_owner_peer_for_unit
mod._cos.bind_glow_unit = _bind_glow_unit
mod._cos.remote_glow_matches = _remote_glow_matches
mod._cos.remote_glow_context_matches = _remote_glow_context_matches
