-- _la_persistence.lua
--
-- Persists LA equips across game restarts. LA-cloned hats / armor / weapon
-- illusions aren't real PlayFab items, so vanilla's loadout-restore drops
-- them on every restart and the user has to re-equip from scratch. This
-- module saves every LA equip the moment it's applied and replays them on
-- player spawn (hat / armor) or first wield (weapon illusions).
--
-- Storage: single VMF setting `la_persisted_equips`, shape:
--   {
--     schema = 1,
--     careers   = { [career_name] = { slot_hat = la_item, slot_skin = la_item } },
--     illusions = { [backend_id] = la_skin_name },
--     offhands  = { [backend_id] = { [hand_field] = { armoury_key... | unit_path... } } },
--   }
--
-- Save tap points (v0.9.83-dev, #520): the AUTHORITATIVE hat/armor save and
-- clear live in cosmetics_tweaker.lua's BackendUtils.set_loadout_item hook
-- (_install_skin_loadout_safety) - career_name arrives as a call argument
-- there, immune to the profile_by_peer resync-window nil that silently
-- dropped every save from the older tap. The v0.9.12 taps at the
-- _send_la_apply emit call sites remain as redundant writers (dedup makes
-- them idempotent). Restore: boot-time loadout_cache rehydration in
-- _install_skin_loadout_safety + the player spawn hook installed at the
-- bottom of this file (extensions_ready on SimpleInventoryExtension).
--
-- Public API on the module table (returned from dofile):
--   M.save_cosmetic(career_name, slot, la_item_name)
--   M.save_illusion(backend_id, la_skin_name)
--   M.clear_cosmetic(career_name, slot)
--   M.clear_illusion(backend_id)
--   M.get_saved_cosmetic(career_name, slot)  -> la_item_name or nil
--   M.get_saved_illusion(backend_id)          -> la_skin_name or nil
--   M.restore_for_player(player)              -- re-emit saved hat/armor
--   M.is_known_backend_id(backend_id)         -- has any saved illusion?
--   M.save_offhand / clear_offhand / get_saved_offhands
--
-- Career name resolution: player.career_name or
-- SPProfiles[player.profile_index].careers[player.career_index].name.
-- Backend_id resolution: inv._equipment.slots[slot].item_data.backend_id.

local mod = get_mod("cosmetics_tweaker")

local M = {}

local SETTING_KEY = "la_persisted_equips"
local SCHEMA = 1

-- In-memory mirror to avoid mod:get/mod:set round-trips on every call.
-- Loaded once at module init; mutated by save/clear; persisted to disk on
-- every mutation (small writes, infrequent).
local _state = nil

local function _empty_state()
    return { schema = SCHEMA, careers = {}, illusions = {}, offhands = {} }
end

local function _load()
    local data = mod:get(SETTING_KEY)
    if type(data) ~= "table" then
        _state = _empty_state()
        return
    end
    _state = {
        schema = data.schema or SCHEMA,
        careers = (type(data.careers) == "table") and data.careers or {},
        illusions = (type(data.illusions) == "table") and data.illusions or {},
        -- v0.9.71-dev: offhand (shield) picks per weapon instance. Additive
        -- section, same schema number - older builds ignore unknown keys.
        -- Shape: offhands[backend_id][hand_field] =
        --   { armoury_key, vanilla_key } OR { unit_path }.
        offhands = (type(data.offhands) == "table") and data.offhands or {},
    }
end

local function _persist()
    if not _state then _load() end
    mod:set(SETTING_KEY, _state)
end

_load()

-- Resolve career_name from a Player object. Try `player.career_name` first
-- (some careers expose it directly), then the player unit's career/inventory
-- extensions, then fall back to SPProfiles indexing.
--
-- v0.9.83-dev (#520): the player-object path routes through
-- ProfileSynchronizer.profile_by_peer (bulldozer_player.lua:29-38/91-116),
-- which walks `get_peers_with_full_profiles()` and returns NIL while a
-- loadout resync is in flight — exactly the window in which the deferred
-- attachment spawn fires update_cosmetic_slot for a menu equip
-- (player_unit_attachment_extension.lua:267-293). The save tap then
-- resolved career=nil and silently dropped the write, so LA hats/armor
-- never persisted (careers=[] on disk while offhands saved fine). Fix:
-- read the career from the UNIT-resident extensions, which are populated
-- at unit init (career_extension.lua:23 `self._career_name`,
-- simple_inventory_extension.lua:47) and are immune to the resync window.
local function _career_name_for_player(player)
    if not player then return nil end
    if type(player.career_name) == "function" then
        local ok, name = pcall(player.career_name, player)
        if ok and type(name) == "string" then return name end
    end
    -- Unit-resident fallbacks (survive the profile_by_peer resync window).
    local unit = player.player_unit
    if unit and Unit.alive(unit) and ScriptUnit then
        local career_ext = ScriptUnit.has_extension(unit, "career_system")
        if career_ext then
            if type(career_ext.career_name) == "function" then
                local ok, name = pcall(career_ext.career_name, career_ext)
                if ok and type(name) == "string" then return name end
            end
            if type(career_ext._career_name) == "string" then
                return career_ext._career_name
            end
        end
        local inv_ext = ScriptUnit.has_extension(unit, "inventory_system")
        if inv_ext and type(inv_ext._career_name) == "string" then
            return inv_ext._career_name
        end
    end
    local profile_index = player.profile_index
    local career_index = player.career_index
    if type(profile_index) == "function" then
        local ok, idx = pcall(profile_index, player)
        profile_index = ok and idx or nil
    end
    if type(career_index) == "function" then
        local ok, idx = pcall(career_index, player)
        career_index = ok and idx or nil
    end
    if not (profile_index and career_index) then return nil end
    local profiles = rawget(_G, "SPProfiles")
    local profile = profiles and profiles[profile_index]
    local careers = profile and profile.careers
    local career = careers and careers[career_index]
    return career and career.name
end

M._career_name_for_player = _career_name_for_player

-- ============================================================
-- Save / clear / read API
-- ============================================================

M.save_cosmetic = function(career_name, slot, la_item_name)
    if not (career_name and slot and la_item_name) then return end
    if slot ~= "slot_hat" and slot ~= "slot_skin" then return end
    if not _state then _load() end
    _state.careers[career_name] = _state.careers[career_name] or {}
    if _state.careers[career_name][slot] == la_item_name then return end
    _state.careers[career_name][slot] = la_item_name
    _persist()
    mod:info("[la-persist] save %s/%s = %s", tostring(career_name), tostring(slot), tostring(la_item_name))
end

M.clear_cosmetic = function(career_name, slot)
    if not (career_name and slot) then return end
    if not _state then _load() end
    local c = _state.careers[career_name]
    if not c or c[slot] == nil then return end
    mod:info("[la-persist] clear %s/%s (was %s)", tostring(career_name), tostring(slot), tostring(c[slot]))
    c[slot] = nil
    if next(c) == nil then _state.careers[career_name] = nil end
    _persist()
end

M.get_saved_cosmetic = function(career_name, slot)
    if not (career_name and slot) then return nil end
    if not _state then _load() end
    local c = _state.careers[career_name]
    return c and c[slot] or nil
end

-- v0.9.83-dev (#520): full careers view for the boot-time loadout_cache
-- rehydration in cosmetics_tweaker.lua (_install_skin_loadout_safety).
-- Read-only by contract - callers must not mutate the returned table.
M.get_all_saved_cosmetics = function()
    if not _state then _load() end
    return _state.careers or {}
end

M.save_illusion = function(backend_id, la_skin_name)
    if not (backend_id and la_skin_name) then return end
    if not _state then _load() end
    if _state.illusions[backend_id] == la_skin_name then return end
    _state.illusions[backend_id] = la_skin_name
    _persist()
    mod:info("[la-persist] save illusion %s = %s", tostring(backend_id), tostring(la_skin_name))
end

M.clear_illusion = function(backend_id)
    if not backend_id then return end
    if not _state then _load() end
    if _state.illusions[backend_id] == nil then return end
    mod:info("[la-persist] clear illusion %s (was %s)",
        tostring(backend_id), tostring(_state.illusions[backend_id]))
    _state.illusions[backend_id] = nil
    _persist()
end

M.get_saved_illusion = function(backend_id)
    if not backend_id then return nil end
    if not _state then _load() end
    return _state.illusions[backend_id]
end

M.is_known_backend_id = function(backend_id)
    return M.get_saved_illusion(backend_id) ~= nil
end

-- v0.9.71-dev: OFFHAND (shield) pick persistence. `_offhand_selection` was
-- the ONLY LA store with no on-disk mirror, so every shield illusion died
-- with the session (user report 2026-07-06). Saved on a committed Apply,
-- cleared on a committed vanilla revert, restored into `_offhand_selection`
-- once the LA bridge has built its option pools (the restore entry point
-- lives in cosmetics_tweaker.lua, `mod._la_restore_offhand_selections`).

M.save_offhand = function(backend_id, hand_field, armoury_key, vanilla_key, unit_path)
    if not (backend_id and hand_field) then return end
    if not armoury_key and (type(unit_path) ~= "string" or unit_path == "") then return end
    if not _state then _load() end
    _state.offhands = _state.offhands or {}
    _state.offhands[backend_id] = _state.offhands[backend_id] or {}
    local cur = _state.offhands[backend_id][hand_field]
    if cur and cur.armoury_key == armoury_key and cur.vanilla_key == vanilla_key
        and cur.unit_path == unit_path then return end
    _state.offhands[backend_id][hand_field] = {
        armoury_key = armoury_key, vanilla_key = vanilla_key, unit_path = unit_path,
    }
    _persist()
    mod:info("[la-persist] save offhand %s/%s = %s", tostring(backend_id),
        tostring(hand_field), tostring(armoury_key or unit_path))
end

M.clear_offhand = function(backend_id, hand_field)
    if not (backend_id and hand_field) then return end
    if not _state then _load() end
    local o = _state.offhands and _state.offhands[backend_id]
    if not o or o[hand_field] == nil then return end
    mod:info("[la-persist] clear offhand %s/%s (was %s)", tostring(backend_id),
        tostring(hand_field), tostring(o[hand_field].armoury_key))
    o[hand_field] = nil
    if next(o) == nil then _state.offhands[backend_id] = nil end
    _persist()
end

M.get_saved_offhands = function()
    if not _state then _load() end
    return _state.offhands or {}
end

-- ============================================================
-- Restore
-- ============================================================

-- Re-equip the saved LA hat + armor for the player's CURRENT career. Called
-- from the player-spawn hook below (and exposed for manual re-trigger via
-- the cos_persist_replay chat command). Idempotent: if the slot already
-- carries the saved LA item, vanilla's update_cosmetic_slot is a no-op.
M.restore_for_player = function(player)
    if not player then return 0 end
    local career_name = _career_name_for_player(player)
    if not career_name then
        mod:info("[la-persist] restore: no career_name for player — skipping")
        return 0
    end
    if not _state then _load() end
    local saved = _state.careers[career_name]
    if not saved then return 0 end
    local CosmeticUtils = rawget(_G, "CosmeticUtils")
    if not CosmeticUtils or type(CosmeticUtils.update_cosmetic_slot) ~= "function" then
        mod:info("[la-persist] restore: CosmeticUtils not loaded yet — deferred")
        return 0
    end
    local applied = 0
    for _, slot in ipairs({ "slot_hat", "slot_skin" }) do
        local la_item = saved[slot]
        if la_item then
            local ok, err = pcall(CosmeticUtils.update_cosmetic_slot, player, slot, la_item, nil)
            if ok then
                applied = applied + 1
                mod:info("[la-persist] restore %s/%s = %s (ok)",
                    tostring(career_name), tostring(slot), tostring(la_item))
            else
                mod:info("[la-persist] restore %s/%s = %s FAILED: %s",
                    tostring(career_name), tostring(slot), tostring(la_item), tostring(err))
            end
        end
    end
    return applied
end

-- ============================================================
-- Player spawn hook — auto-restore on local player ready.
-- ============================================================
-- SimpleInventoryExtension.extensions_ready fires once the player_unit has
-- full inventory state set up; this is when CosmeticUtils.update_cosmetic_slot
-- becomes safe to call on it (career, profile, slots all populated).
-- Hook_safe so we don't disturb vanilla's return value.
--
-- Bots also pass through extensions_ready; they have a career too. We restore
-- for whatever Player owns the unit (works for the host's main career AND
-- any bot the host owns whose career happens to have a saved LA hat —
-- consistent with vanilla's per-career loadout behavior).
mod:hook_safe("SimpleInventoryExtension", "extensions_ready", function(self, world, unit)
    local pm = rawget(_G, "Managers") and Managers.player
    if not pm or not pm.owner then return end
    local owner = pm:owner(unit)
    if not owner then return end
    -- Run on next frame via a tiny mod.update queue, because at extensions_ready
    -- time the player's career_name field can be unset for ~1 frame. Defer.
    M._pending_restore = M._pending_restore or {}
    M._pending_restore[#M._pending_restore + 1] = { player = owner, deadline = os.clock() + 5 }
    -- v0.9.13-dev: fan out to the spawn monitor (defined in cosmetics_tweaker
    -- .lua, exposed via mod handle). VMF hook_safe doesn't chain on the same
    -- (Class, method), so we share this one registration rather than risk the
    -- second one shadowing — see VMF_RECIPES.md § 1.
    if mod._la_spawn_monitor then
        local ok, err = pcall(mod._la_spawn_monitor, unit)
        if not ok then mod:info("[la-spawn-monitor] pcall err: %s", tostring(err)) end
    end
end)

-- Pump pending restores. Called from mod.update.
M.tick_pending_restore = function()
    if not M._pending_restore or #M._pending_restore == 0 then return end
    local now = os.clock()
    local keep = {}
    for i = 1, #M._pending_restore do
        local entry = M._pending_restore[i]
        if now > entry.deadline then
            -- Timed out; drop quietly.
        else
            local player = entry.player
            local player_unit = player and player.player_unit
            if player_unit and Unit.alive(player_unit) and _career_name_for_player(player) then
                M.restore_for_player(player)
                -- Done; do not re-queue.
            else
                keep[#keep + 1] = entry
            end
        end
    end
    M._pending_restore = keep
end

return M
