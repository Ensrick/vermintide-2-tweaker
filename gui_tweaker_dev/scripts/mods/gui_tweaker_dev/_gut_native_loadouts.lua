-- _gut_native_loadouts.lua -- modded-realm-scoped native saved loadouts (issue #175)
--
-- Makes the game's NATIVE saved-loadout system (the roman-numeral I-VI loadout bar
-- in the hero view, plus its per-loadout talents and bot designation) read and write
-- a MODDED-ONLY store while the player is in the modded (EAC-untrusted) realm, so
-- official-realm loadouts are never touched by modded play and vice-versa. In the
-- OFFICIAL realm, and in Versus, the feature is completely inert (pure vanilla).
--
-- ISOLATION APPROACH (issue #175 requirement 6) -- why the MIRROR, not the interface:
--   Every loadout read/write funnels through ONE object, the backend mirror
--   (`PlayFabMirrorAdventure`, backend_manager_playfab.lua:417). The item interface,
--   the talents interface, any MoreItemsLibrary-swapped interface, and the LA dispatch
--   all call `mirror:get_character_data` / `:get_career_loadouts` for reads and
--   `mirror:set_character_data` / `:set_loadout_index` / `:add_loadout` / `:delete_loadout`
--   for writes (backend_interface_item_playfab.lua:117/173/258/263/271/665,
--   backend_interface_talents_playfab.lua:37/150/331). So the mirror is the SMALLEST,
--   most provable no-write surface. We hook the four mirror WRITE methods and, in
--   modded+adventure, capture the intended write into our VMF store and DO NOT call the
--   original -- so `_career_data` / `_characters_data` are NEVER mutated. Because the
--   PlayFab push is a DIFF (`_check_career_data(self._career_data, self._career_data_mirror)`,
--   playfab_mirror_base.lua:2885) and the character-data push at :2891/:2903 is NOT
--   eac-gated (unlike stats/weaves/poses at :2826/2839/2857), leaving those tables
--   unmutated is exactly what guarantees the commit finds nothing dirty and never pushes
--   modded loadouts over the official cloud data. We hook the three mirror READ methods to
--   serve from the store, so the interface caches (which refresh FROM the mirror) naturally
--   pick up modded values and the in-session equip/spawn flow keeps working unchanged --
--   no reimplementation of the interface cache structures, cosmetic/pose id indirection, or
--   game-mode gating. We deliberately hook the mirror at its CONCRETE runtime subclass
--   `PlayFabMirrorAdventure` (NOT `PlayFabMirrorBase`): class.lua copies parent methods into
--   the child at definition time (class.lua:51-57), so a base-class hook would silently miss
--   the live instance (dedicated servers use `PlayFabMirrorDedicated`; the user is P2P-only,
--   so dedicated is out of scope). Realm signal is `script_data["eac-untrusted"]`
--   (application_parameter.lua:150; named `in_modded_realm` at mod_manager.lua:22; VMF's own
--   dev_console gate uses it). Failsafe: if the realm can't be determined we go fully inert.
--
-- Cross-mod: cim hooks `BackendUtils.set_loadout_item` + `BackendInterfaceItemPlayfab.set_loadout_item`
-- (equip capture) and cosmetics_tweaker hooks `BackendUtils.set_loadout_item` + the items
-- interface instance reads. Those sit at the BackendUtils / interface layer ABOVE the mirror;
-- our hooks sit BELOW, so we do not collide with them and (per NON-NEGOTIABLE 8) we hook no
-- (Class, method) pair they hold. mp (modded_progression) currently installs zero backend hooks.
--
-- Owned by: gui_tweaker_dev.lua entry point. Consumed via: mod:dofile (single call).

local mod = get_mod("gut_dev")

local MARKER = "native_loadouts_v1"

-- Canonical loadout slot list (backend_interface_item_playfab.lua:25-35). The vanilla
-- list is a file-local upvalue, so we keep our own copy.
local LOADOUT_SLOT_NAMES = {
    "slot_ranged", "slot_melee", "slot_skin", "slot_hat",
    "slot_necklace", "slot_ring", "slot_trinket_1", "slot_frame", "slot_pose",
}

-- Gear slots: the slots whose stored value is a backend id resolvable via
-- `get_item_from_id` ONCE THE OWNING SYSTEM HAS REGISTERED IT. Cosmetic slots
-- (skin/hat/frame/pose) may hold plain item KEYS (e.g. "es_2h_sword_weapon_pose_02")
-- that get_item_from_id can NEVER resolve. Two burns dictate how these are handled:
-- 2026-07-02 #1 (v0.2.170): validating cosmetic slots stripped every career's pose.
-- 2026-07-02 #2 (v0.2.172, 20:23 friend log): boot-time validation of GEAR slots dropped
--   a cosmetics/LA per-instance UUID melee id (59630ccf-...) that registers LATER than
--   the check, nulling slot_melee -> engine fatal at spawn ("Tried to wield default slot
--   slot_melee ... that contained no weapon"). "Not resolvable right now" NEVER means
--   "gone" in modded - synthetic ids (cim crafts, LA/cosmetics instances) appear late.
-- Consequently there is NO destructive sanitize pass at all: unresolvable gear ids are
-- handled per-read (see the get_character_data hook), leaving the store intact to
-- self-heal once the id registers.
local GEAR_SLOT_NAMES = {
    "slot_ranged", "slot_melee", "slot_necklace", "slot_ring", "slot_trinket_1",
}
local GEAR_SLOT_SET = {}
for i = 1, #GEAR_SLOT_NAMES do GEAR_SLOT_SET[GEAR_SLOT_NAMES[i]] = true end

-- Weapon slots must NEVER be served empty: vanilla fatals at spawn wielding an empty
-- melee/ranged slot. Jewelry may legitimately be empty, cosmetics degrade gracefully.
local WEAPON_SLOT_SET = { slot_melee = true, slot_ranged = true }

-- The VMF settings key `characters_data` discriminates Adventure from Versus
-- (`vs_characters_data`), set by the mirror subclass (playfab_mirror_adventure.lua).
-- We scope the whole feature to the Adventure mirror; Versus stays vanilla.
local ADVENTURE_DATA_KEY = "characters_data"

local M = { MARKER = MARKER }

-- ------------------------------------------------------------------
-- Store: VMF setting `native_loadouts`, kept in an in-memory working copy so the
-- hot mirror-read hooks don't re-`mod:get` a large table per slot per refresh.
--   _STORE[career_name] = {
--       selected_index = <int>,
--       bot_index      = <int or nil>,
--       loadouts       = { [i] = { [slot_name] = backend_id, ..., talents = "1,2,.." } },
--   }
-- Each loadout entry mirrors `_career_data[career][i]` 1:1 (slots + "talents" key), so
-- reads/writes are trivial passthroughs of the exact vanilla value shape.
-- ------------------------------------------------------------------
local _STORE = nil

local function _store()
    if _STORE == nil then
        local s = mod:get("native_loadouts")
        _STORE = (type(s) == "table") and s or {}
    end
    return _STORE
end

local function _persist()
    mod:set("native_loadouts", _STORE)
end

local function _deepcopy(t)
    if type(t) ~= "table" then return t end
    local c = {}
    for k, v in pairs(t) do c[k] = _deepcopy(v) end
    return c
end

-- ------------------------------------------------------------------
-- Realm detection + gate. Failsafe: any uncertainty => inert (official behavior).
-- ------------------------------------------------------------------
local function _in_modded_realm()
    local sd = rawget(_G, "script_data")
    return (sd and sd["eac-untrusted"]) and true or false
end

-- Tri-mode gate (2026-07-02 reorg: the store itself is INTRINSIC - no enable toggle):
--   MODE_OFF      official realm (or Versus/undeterminable): fully inert, vanilla behavior.
--   MODE_STORE    modded, "Use non-modded loadouts" OFF (default): store overlay -
--                 reads serve the modded store, writes captured into it, official untouched.
--   MODE_READONLY modded, "Use non-modded loadouts" ON: reads pass through to the
--                 official data, EVERY loadout write is blocked (no store, no official) -
--                 the player cannot modify loadouts from modded at all.
-- Pure logic exposed for regression testing. Setting default_value=false => nil reads as OFF.
local MODE_OFF, MODE_STORE, MODE_READONLY = "off", "store", "readonly"
M.MODE_OFF, M.MODE_STORE, M.MODE_READONLY = MODE_OFF, MODE_STORE, MODE_READONLY

function M.mode(is_modded, use_non_modded)
    if not is_modded then return MODE_OFF end
    if use_non_modded then return MODE_READONLY end
    return MODE_STORE
end

local function _feature_mode()
    if not _in_modded_realm() then return MODE_OFF end   -- official realm: cheap exit, no mod:get
    return M.mode(true, mod:get("gut_use_non_modded_loadouts"))
end

-- Mirror hooks additionally require the Adventure data key so Versus stays vanilla.
local function _mirror_mode(mirror)
    local m = _feature_mode()
    if m == MODE_OFF then return MODE_OFF end
    return (mirror._characters_data_key == ADVENTURE_DATA_KEY) and m or MODE_OFF
end

-- Interface/UI hooks lack the mirror on `self`; resolve it to check the same discriminator.
local function _adventure_mode()
    local m = _feature_mode()
    if m == MODE_OFF then return MODE_OFF end
    local ok, mirror = pcall(function()
        return Managers.backend:get_interface("items")._backend_mirror
    end)
    return (ok and mirror and mirror._characters_data_key == ADVENTURE_DATA_KEY) and m or MODE_OFF
end

-- Loadout cap read from the game, NEVER hardcoded 6 (issue #231 raises it to 30 later).
function M.max_loadouts()
    return (InventorySettings and InventorySettings.MAX_NUM_CUSTOM_LOADOUTS) or 6
end

local function _dirtify()
    -- dirtify_interfaces() marks the backend interfaces dirty so the next read rebuilds
    -- their caches from the mirror (which we serve from the store). It is NOT a network
    -- push (playfab_mirror_base.lua:1990/2033/2066 call it locally), and since our writes
    -- leave _career_data unmutated, any commit it schedules finds nothing dirty to send.
    pcall(function() Managers.backend:dirtify_interfaces() end)
end

-- ------------------------------------------------------------------
-- Seeding (issue #175 requirement 5): ONE-TIME snapshot of the official loadouts for a
-- career into the modded store on first activation. Official data is only ever READ.
-- ------------------------------------------------------------------
local function _ensure_seeded(mirror, career_name)
    local store = _store()
    if store[career_name] then return end
    local cd = mirror._career_data and mirror._career_data[career_name]
    if type(cd) ~= "table" or cd[1] == nil then return end  -- official data not ready yet
    local selected = (mirror._career_loadouts and mirror._career_loadouts[career_name]) or 1
    store[career_name] = {
        selected_index = selected,
        bot_index = nil,
        loadouts = _deepcopy(cd),   -- array of { slot=id,..., talents=str }
    }
    _persist()
    printf("[gut_dev:NATIVE_LOADOUTS] seeded career=%s loadouts=%d selected=%d from official (read-only)",
        tostring(career_name), #cd, selected)
end

-- Tri-state gear-id resolution: "yes" (item exists), "no" (checkable and absent right
-- now), "unknown" (cannot check). RAW FIELD READS ONLY - NEVER interface methods.
-- Burn 2026-07-02 #3 (v0.2.173, PC-A 21:09 log): calling iface:get_item_from_id() from
-- inside the mirror get_character_data hook recursed unboundedly - get_item_from_id ->
-- get_all_backend_items -> `if self._dirty then self:_refresh()` (backend_interface_
-- item_playfab.lua) -> _refresh -> mirror get_character_data -> our hook -> resolve ->
-- get_item_from_id -> _dirty STILL true (cleared only when _refresh completes) -> stack
-- overflow (~10k frames, surfaced at cosmetics_tweaker.lua:1513 on the same chain), and
-- the error-handler frame dumps then exhausted the 1 GiB lua_heap. Reading `_items` /
-- `_fake_items` directly (interfaces registry field per backend_manager_playfab.lua:202)
-- performs no dirty check, so re-entry is structurally impossible. A stale table during
-- a pending refresh at worst yields a transient "no" -> per-read official fallback that
-- self-heals on the next read.
local RESOLVE_YES, RESOLVE_NO, RESOLVE_UNKNOWN = 1, 2, 3
local function _resolve_item_raw(id)
    local ok, state = pcall(function()
        local backend = Managers and Managers.backend
        local iface = backend and backend._interfaces and backend._interfaces.items
        if not iface then return RESOLVE_UNKNOWN end
        local items = iface._items
        local fakes = iface._fake_items
        if not items and not fakes then return RESOLVE_UNKNOWN end
        if (items and items[id]) or (fakes and fakes[id]) then return RESOLVE_YES end
        return RESOLVE_NO
    end)
    return ok and state or RESOLVE_UNKNOWN
end

-- ------------------------------------------------------------------
-- BackendUtils equip capture (v0.2.175). With Loremaster's Armoury installed, menu equips
-- route through an LA-CLONED interface whose copied methods bypass class-level hooks, so
-- gear equips never reached the PlayFabMirrorAdventure.set_character_data capture (friend
-- logs 2026-07-02 21:25/21:27: a live equip produced ZERO captures; store stayed stale so
-- the correction did not survive relaunch). cim burned identically 2026-05-30 and solved
-- it the same way - see crafting_in_modded_dev.lua:1495 comment block. Capture at the
-- stable OUTER entry point the hero view calls (hero_view_state_overview.lua:1108),
-- TABLE-form per the repo Hooking rule, installed deferred once the backend answers
-- (cim/cosmetics timing). GEAR slots only: the interface layer rewrites cosmetic ids
-- (override_id/ItemId, backend_interface_item_playfab.lua set_loadout_item) before the
-- mirror write, so cosmetic captures stay at the mirror hook, which the real cosmetic
-- flow does reach (pose captures in the same friend logs prove it).
-- ------------------------------------------------------------------
local _bu_capture_installed = false
local function _install_bu_capture()
    if _bu_capture_installed then return end
    local BU = rawget(_G, "BackendUtils")
    if not (BU and BU.set_loadout_item and Managers and Managers.backend and Managers.backend.get_interface) then return end
    local ok_iface = pcall(function() return Managers.backend:get_interface("items") end)
    if not ok_iface then return end
    _bu_capture_installed = true
    mod:hook(BU, "set_loadout_item", function(func, backend_id, career_name, slot_name)
        -- 3-arg entry point, always the SELECTED loadout (no index arg by design).
        -- READONLY mode: no capture; the call passes through and the mirror-level write
        -- blocks make the equip snap back to the official loadout on the next refresh.
        if _adventure_mode() == MODE_STORE and career_name and backend_id and GEAR_SLOT_SET[slot_name] then
            local store = _store()
            local entry = store[career_name]
            if not entry then entry = { selected_index = 1, bot_index = nil, loadouts = {} }; store[career_name] = entry end
            local idx = entry.selected_index
            entry.loadouts[idx] = entry.loadouts[idx] or {}
            entry.loadouts[idx][slot_name] = backend_id
            _persist()
            printf("[gut_dev:NATIVE_LOADOUTS] BU equip capture career=%s idx=%s slot=%s -> store",
                tostring(career_name), tostring(idx), tostring(slot_name))
        end
        return func(backend_id, career_name, slot_name)
    end)
    printf("[gut_dev:NATIVE_LOADOUTS] BackendUtils.set_loadout_item capture installed (post-LA)")
end

local function _prepare(mirror, career_name)
    _install_bu_capture()
    _ensure_seeded(mirror, career_name)
end

-- ==================================================================
-- MIRROR READ HOOKS -- serve from the store so interface caches pick up modded values.
-- Hooked on the concrete runtime subclass PlayFabMirrorAdventure (NOT the base class).
-- ==================================================================

-- get_character_data(self, career_name, key, optional_loadout_index) -- base:1909
mod:hook("PlayFabMirrorAdventure", "get_character_data", function(func, self, career_name, key, optional_loadout_index)
    -- READONLY mode reads pass through: the official data IS the loadout source then.
    if _mirror_mode(self) ~= MODE_STORE or not career_name then
        return func(self, career_name, key, optional_loadout_index)
    end
    _prepare(self, career_name)
    local entry = _store()[career_name]
    if not entry then
        return func(self, career_name, key, optional_loadout_index)  -- not seedable yet: official read (harmless)
    end
    local idx = optional_loadout_index or entry.selected_index
    local lo = entry.loadouts[idx]
    if lo == nil then return nil end
    local value = lo[key]
    -- Non-destructive gear fallback (2026-07-02 v0.2.172 spawn-fatal burn): a gear id that
    -- is empty or unresolvable RIGHT NOW is served from the OFFICIAL value for this read
    -- only. The store is never mutated, so a late-registering modded id (cim craft,
    -- LA/cosmetics instance UUID) serves again the moment it resolves. Empty-slot fallback
    -- applies only to weapon slots (empty jewelry is a legitimate state; empty melee/ranged
    -- fatals at spawn wield).
    if GEAR_SLOT_SET[key] then
        if value == nil then
            if WEAPON_SLOT_SET[key] then
                return func(self, career_name, key, optional_loadout_index)
            end
            return nil
        end
        -- Fall back to the official value ONLY on an affirmative miss; on UNKNOWN
        -- (backend not inspectable) serve the store value unchanged - guessing
        -- "official" there would bleed official gear into modded loadouts at boot.
        if _resolve_item_raw(value) == RESOLVE_NO then
            return func(self, career_name, key, optional_loadout_index)
        end
    end
    return value
end)

-- get_career_loadouts(self, career_name) -> (selected_index, loadouts_array) -- base:1944
mod:hook("PlayFabMirrorAdventure", "get_career_loadouts", function(func, self, career_name)
    if _mirror_mode(self) ~= MODE_STORE or not career_name then
        return func(self, career_name)
    end
    _prepare(self, career_name)
    local entry = _store()[career_name]
    if not entry then
        return func(self, career_name)
    end
    return entry.selected_index, entry.loadouts
end)

-- has_loadout(self, career_name, loadout_index) -- base:1921
mod:hook("PlayFabMirrorAdventure", "has_loadout", function(func, self, career_name, loadout_index)
    if _mirror_mode(self) ~= MODE_STORE or not career_name then
        return func(self, career_name, loadout_index)
    end
    _prepare(self, career_name)
    local entry = _store()[career_name]
    if not entry then
        return func(self, career_name, loadout_index)
    end
    return entry.loadouts[loadout_index] ~= nil
end)

-- ==================================================================
-- MIRROR WRITE HOOKS -- capture into the store, NO-OP vanilla (never touch _career_data).
-- ==================================================================

-- set_character_data(self, career, key, value, set_mirror, optional_loadout_index) -- base:1928
-- key is a slot name or "talents"; value is the backend id / talent string that the
-- interface (set_loadout_item at :657-665) / talents interface (set_talents at :331)
-- already resolved. We store it verbatim -- the cosmetic/pose id rewrite is done upstream.
mod:hook("PlayFabMirrorAdventure", "set_character_data", function(func, self, career_name, key, value, set_mirror, optional_loadout_index)
    local m = _mirror_mode(self)
    if m == MODE_OFF or not career_name then
        return func(self, career_name, key, value, set_mirror, optional_loadout_index)
    end
    if m == MODE_READONLY then
        printf("[gut_dev:NATIVE_LOADOUTS] set_character_data career=%s key=%s BLOCKED (read-only non-modded loadouts)",
            tostring(career_name), tostring(key))
        return
    end
    _prepare(self, career_name)
    local store = _store()
    local entry = store[career_name]
    if not entry then    -- never pass an official write through: keep the isolation guarantee
        entry = { selected_index = 1, bot_index = nil, loadouts = {} }
        store[career_name] = entry
    end
    local idx = optional_loadout_index or entry.selected_index
    entry.loadouts[idx] = entry.loadouts[idx] or {}
    entry.loadouts[idx][key] = value
    _persist()
    printf("[gut_dev:NATIVE_LOADOUTS] set_character_data career=%s idx=%s key=%s -> store (blocked official write)",
        tostring(career_name), tostring(idx), tostring(key))
    -- NO-OP vanilla: _career_data / _characters_data stay clean => no PlayFab push.
end)

-- set_loadout_index(self, career, loadout_index) -- base:1968
mod:hook("PlayFabMirrorAdventure", "set_loadout_index", function(func, self, career_name, loadout_index)
    local m = _mirror_mode(self)
    if m == MODE_OFF or not career_name or not loadout_index then
        return func(self, career_name, loadout_index)
    end
    if m == MODE_READONLY then
        printf("[gut_dev:NATIVE_LOADOUTS] set_loadout_index career=%s BLOCKED (read-only non-modded loadouts)", tostring(career_name))
        return
    end
    _prepare(self, career_name)
    local store = _store()
    local entry = store[career_name]
    if not entry then entry = { selected_index = 1, bot_index = nil, loadouts = {} }; store[career_name] = entry end
    if entry.loadouts[loadout_index] then   -- mirror vanilla's `if career_data[loadout_index]` guard (:1975)
        entry.selected_index = loadout_index
        _persist()
        printf("[gut_dev:NATIVE_LOADOUTS] set_loadout_index career=%s -> %d (store)", tostring(career_name), loadout_index)
        _dirtify()   -- vanilla calls dirtify here (:1990); needed so the interface rebuilds the selected gear
    end
    -- NO-OP vanilla.
end)

-- add_loadout(self, career) -- base:2036
mod:hook("PlayFabMirrorAdventure", "add_loadout", function(func, self, career_name)
    local m = _mirror_mode(self)
    if m == MODE_OFF or not career_name then
        return func(self, career_name)
    end
    if m == MODE_READONLY then
        printf("[gut_dev:NATIVE_LOADOUTS] add_loadout career=%s BLOCKED (read-only non-modded loadouts)", tostring(career_name))
        return
    end
    _prepare(self, career_name)
    local store = _store()
    local entry = store[career_name]
    if not entry then entry = { selected_index = 1, bot_index = nil, loadouts = {} }; store[career_name] = entry end
    local n = #entry.loadouts
    if n < M.max_loadouts() then   -- cap from InventorySettings.MAX_NUM_CUSTOM_LOADOUTS, never hardcoded
        local old_selected = entry.selected_index
        local source = entry.loadouts[old_selected] or entry.loadouts[n] or {}
        entry.loadouts[n + 1] = _deepcopy(source)   -- vanilla clones the current loadout (:2051/2053)
        entry.selected_index = old_selected + 1      -- vanilla sets selected = selected+1 (:2050)
        _persist()
        printf("[gut_dev:NATIVE_LOADOUTS] add_loadout career=%s now=%d selected=%d (store)",
            tostring(career_name), n + 1, entry.selected_index)
        _dirtify()
    end
    -- NO-OP vanilla.
end)

-- delete_loadout(self, career, loadout_index) -- base:1994
mod:hook("PlayFabMirrorAdventure", "delete_loadout", function(func, self, career_name, loadout_index)
    local m = _mirror_mode(self)
    if m == MODE_OFF or not career_name or not loadout_index then
        return func(self, career_name, loadout_index)
    end
    if m == MODE_READONLY then
        printf("[gut_dev:NATIVE_LOADOUTS] delete_loadout career=%s BLOCKED (read-only non-modded loadouts)", tostring(career_name))
        return
    end
    _prepare(self, career_name)
    local entry = _store()[career_name]
    if not entry then return end
    local loadouts = entry.loadouts
    local n = #loadouts
    if loadout_index > n then return end   -- vanilla guard (:2001)
    if n == 1 then return end              -- vanilla guard (:2005): never delete the last
    table.remove(loadouts, loadout_index)
    if loadout_index == entry.selected_index then   -- vanilla selection fixup (:2020-2028)
        entry.selected_index = 1
    else
        entry.selected_index = math.clamp(entry.selected_index, 1, #loadouts)
    end
    _persist()
    printf("[gut_dev:NATIVE_LOADOUTS] delete_loadout career=%s removed=%d now=%d selected=%d (store)",
        tostring(career_name), loadout_index, #loadouts, entry.selected_index)
    _dirtify()
    -- NO-OP vanilla.
end)

-- set_career_read_only_data(self, character, key, value, career, set_mirror, loadout_index)
-- (base:3630) is the `_characters_data` writer - the payload source for the cloud push,
-- and vanilla does NOT eac-gate character-data pushes. Normally unreachable while gated
-- (our set_character_data no-op stops the chain before base:1941), but LA-clone bypass
-- paths can still reach it as a method call. When gated: career-scoped writes (loadout
-- slots + talents per base:1941) are captured into the store and BLOCKED so nothing
-- modded ever mutates _characters_data. career-nil (character-level) writes pass through.
mod:hook("PlayFabMirrorAdventure", "set_career_read_only_data", function(func, self, character, key, value, career, set_mirror, loadout_index)
    local m = _mirror_mode(self)
    if m == MODE_OFF or not career then
        return func(self, character, key, value, career, set_mirror, loadout_index)
    end
    if m == MODE_READONLY then
        printf("[gut_dev:NATIVE_LOADOUTS] set_career_read_only_data career=%s key=%s BLOCKED (read-only non-modded loadouts)",
            tostring(career), tostring(key))
        return
    end
    _prepare(self, career)
    local store = _store()
    local entry = store[career]
    if not entry then entry = { selected_index = 1, bot_index = nil, loadouts = {} }; store[career] = entry end
    local idx = loadout_index or entry.selected_index
    entry.loadouts[idx] = entry.loadouts[idx] or {}
    entry.loadouts[idx][key] = value
    _persist()
    printf("[gut_dev:NATIVE_LOADOUTS] set_career_read_only_data career=%s idx=%s key=%s -> store (blocked official write)",
        tostring(career), tostring(idx), tostring(key))
    -- NO-OP vanilla: _characters_data stays clean => no cloud push.
end)

-- ==================================================================
-- BOT LOADOUTS -- resolve bot designation from the store (issue #175 requirement 9).
-- ==================================================================

-- Overlay bot designations onto _bot_loadouts AFTER vanilla built it from _loadouts.
-- hook_safe (post) -- no other gut_dev hook targets refresh_bot_loadouts.
mod:hook_safe("BackendInterfaceItemPlayfab", "refresh_bot_loadouts", function(self)
    if _adventure_mode() ~= MODE_STORE then return end
    local bot = self._bot_loadouts
    if type(bot) ~= "table" then return end
    for career_name, entry in pairs(_store()) do
        local bi = entry.bot_index
        if bi and entry.loadouts[bi] then
            local slots = {}
            for i = 1, #LOADOUT_SLOT_NAMES do
                local s = LOADOUT_SLOT_NAMES[i]
                slots[s] = entry.loadouts[bi][s]
            end
            bot[career_name] = slots
        end
    end
end)

-- Bot checkbox: write bot_index to the store, SKIP the PlayerData.loadout_selection write
-- (hero_window_loadout_selection_console.lua:671-683), then refresh bot loadouts from the
-- store. Isolation: PlayerData.loadout_selection is realm-shared and not eac-gated, so we
-- never write it while modded.
mod:hook("HeroWindowLoadoutSelectionConsole", "_save_bot_equipment", function(func, self)
    local m = _adventure_mode()
    if m == MODE_OFF then
        return func(self)
    end
    if m == MODE_READONLY then
        printf("[gut_dev:NATIVE_LOADOUTS] bot_equipment BLOCKED (read-only non-modded loadouts)")
        return
    end
    local profile = SPProfiles and SPProfiles[self._profile_index]
    local career_settings = profile and profile.careers and profile.careers[self._career_index]
    local career_name = career_settings and career_settings.name
    if not career_name then return end   -- can't resolve; skip (still no vanilla PlayerData write)
    local store = _store()
    local entry = store[career_name]
    if not entry then entry = { selected_index = 1, bot_index = nil, loadouts = {} }; store[career_name] = entry end
    entry.bot_index = self._context_menu_loadout_index
    _persist()
    printf("[gut_dev:NATIVE_LOADOUTS] bot_equipment career=%s bot_index=%s -> store (skipped PlayerData write)",
        tostring(career_name), tostring(entry.bot_index))
    local ok, iface = pcall(function() return Managers.backend:get_interface("items") end)
    if ok and iface and iface.refresh_bot_loadouts then
        pcall(function() iface:refresh_bot_loadouts() end)
    end
    -- NO-OP vanilla.
end)

-- ==================================================================
-- Re-seed command. The seed is one-time by design, so a snapshot taken while the mirror
-- held bad data (e.g. blacksmith items committed to the cloud by the pre-isolation #174
-- bleed, seen 2026-07-02 on merc Kruber slot_melee) is frozen until explicitly reset.
-- /reset_modded_loadouts        -> wipe the whole modded store
-- /reset_modded_loadouts <career> -> wipe one career (e.g. es_mercenary)
-- Next loadout touch in modded re-seeds from the CURRENT official data. Official data is
-- never written; this only discards the modded-side copies (including any modded-only edits).
-- ==================================================================
mod:command("reset_modded_loadouts", "Reset modded loadouts to re-seed from official (optional: career name)", function(career_arg)
    local store = _store()
    if career_arg and career_arg ~= "" then
        if not store[career_arg] then
            mod:echo("No modded loadout store for '" .. tostring(career_arg) .. "' (nothing to reset)")
            printf("[gut_dev:NATIVE_LOADOUTS] reset requested for unknown career=%s", tostring(career_arg))
            return
        end
        store[career_arg] = nil
        _persist()
        _dirtify()
        mod:echo("Modded loadouts reset for " .. career_arg .. "; they re-seed from official on next use")
        printf("[gut_dev:NATIVE_LOADOUTS] store reset career=%s (will re-seed from official)", career_arg)
    else
        local n = 0
        for career_name in pairs(store) do
            store[career_name] = nil
            n = n + 1
        end
        _persist()
        _dirtify()
        mod:echo("Modded loadouts reset for " .. n .. " career(s); they re-seed from official on next use")
        printf("[gut_dev:NATIVE_LOADOUTS] store reset ALL (%d careers, will re-seed from official)", n)
    end
end)

-- ==================================================================
-- Regression markers (issue #175 requirement 11). Registered by gui_tweaker_dev.lua.
-- ==================================================================
M.HOOK_TARGETS = {
    { "PlayFabMirrorAdventure", "get_character_data" },
    { "PlayFabMirrorAdventure", "get_career_loadouts" },
    { "PlayFabMirrorAdventure", "has_loadout" },
    { "PlayFabMirrorAdventure", "set_character_data" },
    { "PlayFabMirrorAdventure", "set_career_read_only_data" },
    { "PlayFabMirrorAdventure", "set_loadout_index" },
    { "PlayFabMirrorAdventure", "add_loadout" },
    { "PlayFabMirrorAdventure", "delete_loadout" },
    { "BackendInterfaceItemPlayfab", "refresh_bot_loadouts" },
    { "HeroWindowLoadoutSelectionConsole", "_save_bot_equipment" },
    { "BackendUtils", "set_loadout_item" },  -- TABLE-form, installed deferred (_install_bu_capture)
}

M.rt_checks = {
    { name = "native_loadouts_installed", fn = function()
        if M.MARKER ~= MARKER then return "marker mismatch" end
        if type(_in_modded_realm) ~= "function" then return "realm detector missing" end
        local ok = pcall(_in_modded_realm)
        if not ok then return "_in_modded_realm raised" end
    end },
    { name = "native_loadouts_failsafe_inert", fn = function()
        -- Tri-mode gate: OFF in official always; STORE is the modded default (implicit
        -- feature, no enable toggle); READONLY when "Use non-modded loadouts" is ON.
        if M.mode(false, false) ~= M.MODE_OFF then return "not inert in official realm" end
        if M.mode(false, true) ~= M.MODE_OFF then return "not inert in official realm (use_non_modded on)" end
        if M.mode(false, nil) ~= M.MODE_OFF then return "not inert in official realm (nil setting)" end
        if M.mode(true, false) ~= M.MODE_STORE then return "modded default should be STORE" end
        if M.mode(true, nil) ~= M.MODE_STORE then return "nil setting should read as STORE (default OFF)" end
        if M.mode(true, true) ~= M.MODE_READONLY then return "use_non_modded on should be READONLY" end
    end },
    { name = "native_loadouts_no_hardcoded_6", fn = function()
        local expected = InventorySettings and InventorySettings.MAX_NUM_CUSTOM_LOADOUTS
        if type(expected) ~= "number" then return "MAX_NUM_CUSTOM_LOADOUTS unavailable" end
        if M.max_loadouts() ~= expected then
            return string.format("cap %s != InventorySettings.MAX_NUM_CUSTOM_LOADOUTS %s (hardcoded?)",
                tostring(M.max_loadouts()), tostring(expected))
        end
    end },
    { name = "native_loadouts_gear_fallback_nondestructive", fn = function()
        -- Two prior burns (2026-07-02): destructive sanitize stripped poses (item keys)
        -- then nulled a late-registering UUID melee id -> spawn fatal. Guard the shape:
        -- no destructive pass exists, cosmetic slots stay out of the gear set, and the
        -- weapon set (never-serve-empty) is a subset of the gear set.
        if _sanitize_career ~= nil then return "destructive _sanitize_career reintroduced" end
        -- v0.2.173 recursion burn: resolution must be raw-read tri-state, never interface methods.
        if type(_resolve_item_raw) ~= "function" then return "_resolve_item_raw missing" end
        local st = _resolve_item_raw("__rt_nonexistent_id__")
        if st ~= RESOLVE_NO and st ~= RESOLVE_UNKNOWN then
            return "tri-state resolve returned " .. tostring(st) .. " for nonexistent id"
        end
        local cosmetic = { slot_skin = true, slot_hat = true, slot_frame = true, slot_pose = true }
        local in_loadout = {}
        for _, s in ipairs(LOADOUT_SLOT_NAMES) do in_loadout[s] = true end
        for _, s in ipairs(GEAR_SLOT_NAMES) do
            if cosmetic[s] then return "cosmetic slot in GEAR_SLOT_NAMES: " .. s end
            if not in_loadout[s] then return "unknown slot in GEAR_SLOT_NAMES: " .. s end
            if not GEAR_SLOT_SET[s] then return "GEAR_SLOT_SET missing " .. s end
        end
        for s in pairs(WEAPON_SLOT_SET) do
            if not GEAR_SLOT_SET[s] then return "weapon slot not in gear set: " .. s end
        end
    end },
    { name = "native_loadouts_hook_targets_unique", fn = function()
        -- Singleton invariant proxy (NON-NEGOTIABLE 8): each (Class, method) declared once.
        local seen = {}
        for _, t in ipairs(M.HOOK_TARGETS) do
            local key = t[1] .. "." .. t[2]
            if seen[key] then return "duplicate hook target: " .. key end
            seen[key] = true
        end
    end },
}

printf("[gut_dev:NATIVE_LOADOUTS] module loaded (%s) modded_realm=%s hooks=%d",
    MARKER, tostring(_in_modded_realm()), #M.HOOK_TARGETS)

return M
