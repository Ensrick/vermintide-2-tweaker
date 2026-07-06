-- _gut_native_loadouts.lua -- modded-realm-scoped native saved loadouts (issue #175)
--
-- Makes the game's NATIVE saved-loadout system (the roman-numeral I-VI loadout bar
-- in the hero view, plus its per-loadout talents and bot designation) read and write
-- a MODDED-ONLY store while the player is in the modded (EAC-untrusted) realm, so
-- official-realm loadouts are never touched by modded play and vice-versa. In the
-- OFFICIAL realm, and in Versus, the feature is completely inert (pure vanilla).
--
-- ISSUE #287 (cosmetic exemption): the "Use non-modded loadouts" READONLY mode makes the
-- GAMEPLAY loadout (gear/talents/loadout selection/bot) a read-only mirror of the official
-- data, but cosmetic slots (COSMETIC_SLOT_SET - weapon illusion, hat, portrait frame,
-- victory pose) stay freely editable. Their modded-only values live in a SEPARATE cosmetic
-- overlay (_overlay), keyed by the official loadout index, and NEVER touch official data.
-- STORE mode is unaffected (cosmetics already live in the full modded store there).
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

-- Cosmetic slots: pure-visual loadout slots (weapon illusion, hat, portrait frame,
-- victory pose) with zero gameplay weight. Issue #287: these stay EDITABLE and persist
-- modded-side even in READONLY ("Use non-modded loadouts") mode, where the gameplay
-- loadout (gear/talents/loadout selection/bot) is official-read-only. This set is exactly
-- LOADOUT_SLOT_NAMES minus GEAR_SLOT_NAMES (asserted in rt_checks); it matches vanilla
-- CosmeticUtils cosmetic_slots {frame,hat,skin} plus slot_pose, which vanilla treats as
-- cosmetic-equivalent (cosmetic_utils.lua:87-94; set_loadout_item pose branch :661).
local COSMETIC_SLOT_SET = { slot_skin = true, slot_hat = true, slot_frame = true, slot_pose = true }

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
-- Cosmetic overlay (issue #287): modded-only cosmetic slot values, consulted ONLY in
-- READONLY mode so cosmetics stay editable while the gameplay loadout mirrors official
-- read-only. Kept SEPARATE from _STORE so the STORE-mode full-loadout store and this
-- overlay never entangle their loadout-index semantics: the overlay is keyed by the
-- OFFICIAL selected loadout index (the same index the gear is read at in READONLY), so an
-- overlaid hat always lines up with the official gear shown beside it.
--   _OVERLAY[career_name] = { [official_loadout_index] = { slot_skin=id, slot_hat=id, ... } }
-- An absent value falls through to the official cosmetic (an untouched cosmetic shows your
-- official one). Official data is NEVER written.
-- ------------------------------------------------------------------
local _OVERLAY = nil

local function _overlay()
    if _OVERLAY == nil then
        local s = mod:get("native_cosmetic_overlay")
        _OVERLAY = (type(s) == "table") and s or {}
    end
    return _OVERLAY
end

local function _persist_overlay()
    mod:set("native_cosmetic_overlay", _OVERLAY)
end

-- In READONLY the gameplay loadout selection is frozen at the OFFICIAL selected index
-- (set_loadout_index is blocked), and vanilla get/set_character_data resolve a nil index
-- to self._career_loadouts[career] (base:1911/1930). The cosmetic overlay MUST key off the
-- same index so cosmetics and gear read from the same loadout row.
local function _official_index(mirror, career_name, optional_loadout_index)
    if optional_loadout_index then return optional_loadout_index end
    local sel = mirror._career_loadouts and mirror._career_loadouts[career_name]
    return sel or 1
end

-- READONLY cosmetic overlay read: overlaid value or nil (caller falls back to official).
local function _overlay_get(mirror, career_name, key, optional_loadout_index)
    local career_ov = _overlay()[career_name]
    if not career_ov then return nil end
    local row = career_ov[_official_index(mirror, career_name, optional_loadout_index)]
    return row and row[key]
end

-- READONLY cosmetic overlay write: capture modded-side, never touch official. Returns the
-- resolved index for logging.
local function _overlay_set(mirror, career_name, key, value, optional_loadout_index)
    local ov = _overlay()
    local career_ov = ov[career_name]
    if not career_ov then career_ov = {}; ov[career_name] = career_ov end
    local idx = _official_index(mirror, career_name, optional_loadout_index)
    local row = career_ov[idx]
    if not row then row = {}; career_ov[idx] = row end
    row[key] = value
    _persist_overlay()
    return idx
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
--   MODE_READONLY modded, "Use non-modded loadouts" ON: the GAMEPLAY loadout
--                 (gear/talents/loadout selection/bot) reads through to the official data
--                 and every write is blocked - the player cannot modify it from modded.
--                 EXCEPTION (issue #287): cosmetic slots (COSMETIC_SLOT_SET - illusion,
--                 hat, frame, pose) stay editable; their modded values live in the
--                 separate cosmetic overlay (_overlay), never touching official data.
-- Pure logic exposed for regression testing. Setting default_value=false => nil reads as OFF.
local MODE_OFF, MODE_STORE, MODE_READONLY = "off", "store", "readonly"
M.MODE_OFF, M.MODE_STORE, M.MODE_READONLY = MODE_OFF, MODE_STORE, MODE_READONLY

function M.mode(is_modded, use_non_modded)
    if not is_modded then return MODE_OFF end
    if use_non_modded then return MODE_READONLY end
    return MODE_STORE
end

-- issue #287: in READONLY only cosmetic slots stay editable; every gameplay slot / talent
-- write snaps back. Pure predicate exposed for regression testing.
function M.readonly_slot_editable(slot_name)
    return COSMETIC_SLOT_SET[slot_name] == true
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
-- Seeding (issue #175 requirement 5): snapshot of the official loadouts for a career
-- into the modded store. Official data is only ever READ.
--
-- issue #375 -- SELF-HEALING SEED. The original guard early-returned on ANY existing
-- store entry (`if store[career_name] then return`), which combined with the pre-seed
-- bare-entry write in the BU equip capture (:329) to permanently corrupt the store:
-- an equip that landed before the first mirror-read created a bare entry
-- `{loadouts={}}`, so the official snapshot NEVER imported and the store held only the
-- slots equipped while in modded (symptom 1). Because whole official loadout rows were
-- then missing, set_loadout_index's `if entry.loadouts[idx]` guard (:499) failed on
-- every slot switch, so selected_index never advanced and edits wrote to the wrong row
-- (symptom 2 cascades from 1).
--
-- Now: a one-time `_seeded` flag marks a fully-imported entry. A fresh career takes a
-- full official snapshot. A pre-existing PARTIAL entry (no flag -- either a bare
-- BU-capture entry or a store persisted by the buggy build) is REPAIRED once: every
-- official loadout row the store is missing is added, and any row that lost its weapons
-- (the corrupt-partial signature -- a legitimately edited loadout ALWAYS keeps both
-- weapon slots) has its missing gear refilled from official. Rows the player genuinely
-- edited (both weapons present) are left untouched, so deliberate jewelry unequips are
-- preserved. Raw field reads only (mirror._career_data / _career_loadouts) -- no
-- interface methods, so no get_item_from_id recursion (v0.2.173 burn).
-- ------------------------------------------------------------------
local function _row_is_corrupt_partial(row)
    -- A legitimately edited loadout always retains both weapon slots; a row missing
    -- either weapon is a partial capture from the pre-seed BU-equip bug (issue #375).
    if type(row) ~= "table" then return true end
    for slot in pairs(WEAPON_SLOT_SET) do
        if row[slot] == nil then return true end
    end
    return false
end

local function _ensure_seeded(mirror, career_name)
    local store = _store()
    local entry = store[career_name]
    if entry and entry._seeded then return end  -- already fully imported
    local cd = mirror._career_data and mirror._career_data[career_name]
    if type(cd) ~= "table" or cd[1] == nil then return end  -- official data not ready yet
    local selected = (mirror._career_loadouts and mirror._career_loadouts[career_name]) or 1
    if not entry then
        store[career_name] = {
            selected_index = selected,
            bot_index = nil,
            loadouts = _deepcopy(cd),   -- array of { slot=id,..., talents=str }
            _seeded = true,
        }
        _persist()
        printf("[gut_dev:NATIVE_LOADOUTS] seeded career=%s loadouts=%d selected=%d from official (fresh)",
            tostring(career_name), #cd, selected)
        return
    end
    -- Repair a partial/bare entry left by the pre-seed bug (issue #375).
    local rows_added, rows_repaired = 0, 0
    for i = 1, #cd do
        local off_row = cd[i]
        local st_row = entry.loadouts[i]
        if st_row == nil then
            entry.loadouts[i] = _deepcopy(off_row)
            rows_added = rows_added + 1
        elseif _row_is_corrupt_partial(st_row) then
            for k, v in pairs(off_row) do
                if st_row[k] == nil then st_row[k] = v end
            end
            rows_repaired = rows_repaired + 1
        end
    end
    if entry.selected_index == nil or entry.loadouts[entry.selected_index] == nil then
        entry.selected_index = selected
    end
    entry._seeded = true
    _persist()
    printf("[gut_dev:NATIVE_LOADOUTS] repaired career=%s partial store (issue #375): rows_added=%d rows_repaired=%d loadouts=%d selected=%d",
        tostring(career_name), rows_added, rows_repaired, #entry.loadouts, entry.selected_index)
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
            -- issue #375: seed the official snapshot BEFORE we can create a store entry.
            -- An equip that lands before the first mirror-read must NOT leave a bare
            -- `{loadouts={}}` entry -- that used to permanently block _ensure_seeded and
            -- was the root cause of "official loadouts only partially import". Resolve the
            -- mirror the same way _adventure_mode does (raw field, no interface method).
            local ok_m, mirror = pcall(function() return Managers.backend:get_interface("items")._backend_mirror end)
            if ok_m and mirror then _ensure_seeded(mirror, career_name) end
            local store = _store()
            local entry = store[career_name]
            -- Fallback bare entry only if seeding could not run yet (official data not
            -- ready). NOT flagged _seeded, so _ensure_seeded repairs it once data lands.
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
    local m = _mirror_mode(self)
    if m == MODE_OFF or not career_name then
        return func(self, career_name, key, optional_loadout_index)
    end
    -- READONLY: gameplay slots read straight from the official data; ONLY cosmetic slots
    -- are served from the modded overlay (issue #287), so a hat/illusion/frame/pose set in
    -- modded persists instead of snapping back. Gear/talents stay official read-only.
    if m == MODE_READONLY then
        if COSMETIC_SLOT_SET[key] then
            local v = _overlay_get(self, career_name, key, optional_loadout_index)
            if v ~= nil then return v end
        end
        return func(self, career_name, key, optional_loadout_index)
    end
    -- MODE_STORE: serve every slot from the store.
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
    local m = _mirror_mode(self)
    if m == MODE_OFF or not career_name then
        return func(self, career_name)
    end
    -- READONLY: return the official (selected, loadouts) array but overlay cosmetic slots
    -- so the per-loadout previews (hero_window_loadout_selection_console.lua:153) match what
    -- is actually equipped (issue #287). Deepcopy first - never mutate the official array.
    if m == MODE_READONLY then
        local selected, loadouts = func(self, career_name)
        local career_ov = _overlay()[career_name]
        if not career_ov or type(loadouts) ~= "table" then
            return selected, loadouts
        end
        local out = _deepcopy(loadouts)
        for idx, row in pairs(career_ov) do
            if out[idx] then
                for slot, v in pairs(row) do
                    if COSMETIC_SLOT_SET[slot] then out[idx][slot] = v end
                end
            end
        end
        return selected, out
    end
    -- MODE_STORE.
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
        -- issue #287: cosmetic edits are allowed - captured into the modded overlay, official
        -- data untouched. Gameplay-slot / talent writes stay blocked (snap back).
        if COSMETIC_SLOT_SET[key] then
            local idx = _overlay_set(self, career_name, key, value, optional_loadout_index)
            _dirtify()   -- rebuild interface caches so the overlay value is picked up
            printf("[gut_dev:NATIVE_LOADOUTS] set_character_data career=%s idx=%s key=%s -> cosmetic overlay (readonly, official untouched)",
                tostring(career_name), tostring(idx), tostring(key))
            return
        end
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
        -- issue #287: mirror the set_character_data cosmetic exemption on the LA-bypass
        -- write path too, so cosmetics equipped through an LA-cloned interface persist.
        if COSMETIC_SLOT_SET[key] then
            local idx = _overlay_set(self, career, key, value, loadout_index)
            _dirtify()
            printf("[gut_dev:NATIVE_LOADOUTS] set_career_read_only_data career=%s idx=%s key=%s -> cosmetic overlay (readonly, official untouched)",
                tostring(career), tostring(idx), tostring(key))
            return
        end
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
-- LOADOUT-PREVIEW CRASH GUARD (issue #372).
-- The hero-view loadout context menu populates a hovered saved loadout via
-- HeroWindowLoadoutSelectionConsole._populate_context_menu_loadout
-- (hero_window_loadout_selection_console.lua:811). Its EQUIPMENT loop (:913-933)
-- reads each gear slot's backend id straight off the loadout row and does
--   item = item_interface:get_item_from_id(backend_id)
--   local icon, name = UIUtils.get_ui_information_from_item(item)   -- item.data
--   content[slot].rarity = UISettings.item_rarity_textures[item.rarity]
-- with NO nil-guard -- unlike the COSMETICS loop right above it (:840-867), which
-- guards `if item then ... else Application.warning`. When `item` is nil this fatals
-- at ui_utils.lua:248 (`item.data`). We OWN the modded loadout store, and by design
-- that store legitimately holds a gear id that is unresolvable RIGHT NOW -- a
-- late-registering cim craft / LA-cosmetics per-instance UUID, or a genuinely stale
-- id (the store is never destructively sanitized; see the get_character_data
-- fallback + the two 2026-07-02 spawn-fatal burns). So a client hovering a saved
-- loadout in the keep CTDs (crash 16.09.08 log: es_mercenary slot_ranged item=nil).
-- Because we own this modded loadout surface, we own its preview: substitute any
-- unresolvable equipment id with the career's currently-equipped (always-resolvable)
-- item for that slot in a SHALLOW COPY -- NEVER mutate the store row -- and pcall the
-- vanilla call as a last-resort backstop for the pathological case where even the
-- fallback will not resolve. Resolution uses the raw tri-state _resolve_item_raw
-- (NOT iface:get_item_from_id), so we never trip the get_item_from_id -> _refresh ->
-- mirror-read recursion (v0.2.173 burn). Cosmetic slots are already nil-safe in
-- vanilla, so we leave them untouched.
--
-- Pre-flight (2026-07-06): grepped gui_tweaker_dev for hooks on
-- (HeroWindowLoadoutSelectionConsole, _populate_context_menu_loadout) -- NONE. gut's
-- other hooks on this class target _save_bot_equipment (this file, above) and
-- _show_context_menu (_gut_mission_inventory.lua) -- distinct methods.
-- ==================================================================
local EQUIPMENT_PREVIEW_SLOTS = { "slot_melee", "slot_ranged", "slot_necklace", "slot_ring", "slot_trinket_1" }

local function _shallow_copy(t)
    local c = {}
    for k, v in pairs(t) do c[k] = v end
    return c
end

mod:hook("HeroWindowLoadoutSelectionConsole", "_populate_context_menu_loadout", function(func, self, loadout, loadout_index)
    -- Resolve career for the live re-fetch + currently-equipped fallback lookup (mirrors vanilla :814-819).
    local profile = rawget(_G, "SPProfiles") and SPProfiles[self._profile_index]
    local career_settings = profile and profile.careers and profile.careers[self._career_index]
    local career_name = career_settings and career_settings.name
    local BU = rawget(_G, "BackendUtils")

    -- STALE-PREVIEW FIX (issue #379). The loadout button caches `content.loadout` once, at
    -- _populate_loadout_buttons (window-enter) time (hero_window_loadout_selection_console.lua:191).
    -- But the item interface REBUILDS self._career_loadouts as brand-new tables on every refresh
    -- (backend_interface_item_playfab.lua:166 `table.clear` -> :170 fresh per-career table -> :179
    -- fresh row tables), so the cached `content.loadout` reference is ORPHANED the moment anything
    -- dirties the interface -- e.g. equipping a weapon while the hero view stays open. The hovered
    -- context-menu preview then keeps drawing that dead snapshot until the whole inventory is closed
    -- and reopened (the only path that re-runs _populate_loadout_buttons). Re-fetch the LIVE loadout
    -- row for this index so the preview always reflects current data. get_career_loadouts is the exact
    -- interface getter vanilla's _populate_loadout_buttons calls -- it self-refreshes when dirty and
    -- (in modded) pulls from our store -- and it is NOT get_item_from_id, so there is no mirror-read
    -- recursion (v0.2.173 burn). Scoped to a modded backend view (the loadout surface we own); the
    -- official realm keeps exact vanilla behavior. Falls back to the passed `loadout` if the live row
    -- is unavailable (e.g. index out of range mid-add).
    if career_name and _adventure_mode() ~= MODE_OFF then
        local ok_live, live = pcall(function()
            local iface = Managers.backend:get_interface("items")
            local cl = iface and iface:get_career_loadouts(career_name)
            return cl and cl[loadout_index]
        end)
        if ok_live and type(live) == "table" then
            loadout = live
        end
    end

    if type(loadout) ~= "table" then
        return func(self, loadout, loadout_index)
    end

    local sanitized
    for i = 1, #EQUIPMENT_PREVIEW_SLOTS do
        local slot = EQUIPMENT_PREVIEW_SLOTS[i]
        local id = loadout[slot]
        -- Only RESOLVE_YES guarantees get_ui_information_from_item receives a real item.
        if id == nil or _resolve_item_raw(id) ~= RESOLVE_YES then
            local fb_id
            if career_name and BU and BU.get_loadout_item then
                local ok_fb, fb = pcall(BU.get_loadout_item, career_name, slot)
                fb_id = ok_fb and fb and fb.backend_id
            end
            -- Substitute only a fallback that itself resolves; otherwise leave the
            -- slot as-is and rely on the pcall backstop below.
            if fb_id and _resolve_item_raw(fb_id) == RESOLVE_YES then
                sanitized = sanitized or _shallow_copy(loadout)
                sanitized[slot] = fb_id
            end
        end
    end

    local ok = pcall(func, self, sanitized or loadout, loadout_index)
    if not ok then
        printf("[gut_dev:NATIVE_LOADOUTS] issue #372: suppressed loadout-preview crash (unresolvable equipment item; career=%s idx=%s)",
            tostring(career_name), tostring(loadout_index))
    end
    -- _populate_context_menu_loadout returns nothing (void populate); no value to forward.
end)

-- ==================================================================
-- Re-seed command. The seed is one-time by design, so a snapshot taken while the mirror
-- held bad data (e.g. blacksmith items committed to the cloud by the pre-isolation #174
-- bleed, seen 2026-07-02 on merc Kruber slot_melee) is frozen until explicitly reset.
-- /reset_modded_loadouts        -> wipe the whole modded store + cosmetic overlay
-- /reset_modded_loadouts <career> -> wipe one career (e.g. es_mercenary)
-- Next loadout touch in modded re-seeds from the CURRENT official data. Official data is
-- never written; this only discards the modded-side copies (the STORE-mode loadouts AND the
-- READONLY cosmetic overlay from issue #287), including any modded-only edits.
-- ==================================================================
mod:command("reset_modded_loadouts", "Reset modded loadouts to re-seed from official (optional: career name)", function(career_arg)
    local store = _store()
    local overlay = _overlay()
    if career_arg and career_arg ~= "" then
        if not store[career_arg] and not overlay[career_arg] then
            mod:echo("No modded loadout store for '" .. tostring(career_arg) .. "' (nothing to reset)")
            printf("[gut_dev:NATIVE_LOADOUTS] reset requested for unknown career=%s", tostring(career_arg))
            return
        end
        store[career_arg] = nil
        overlay[career_arg] = nil
        _persist()
        _persist_overlay()
        _dirtify()
        mod:echo("Modded loadouts reset for " .. career_arg .. "; they re-seed from official on next use")
        printf("[gut_dev:NATIVE_LOADOUTS] store reset career=%s (will re-seed from official)", career_arg)
    else
        local seen = {}
        for career_name in pairs(store) do seen[career_name] = true end
        for career_name in pairs(overlay) do seen[career_name] = true end
        local n = 0
        for career_name in pairs(seen) do
            store[career_name] = nil
            overlay[career_name] = nil
            n = n + 1
        end
        _persist()
        _persist_overlay()
        _dirtify()
        mod:echo("Modded loadouts reset for " .. n .. " career(s); they re-seed from official on next use")
        printf("[gut_dev:NATIVE_LOADOUTS] store reset ALL (%d careers, will re-seed from official)", n)
    end
end)

-- ==================================================================
-- /gut_loadout_status (issue #375 diagnostics) -- echo the modded loadout store state
-- to CHAT (visible with mod-logging off) plus a per-row slot dump to the console log, so
-- "is the loadout system even working" is answerable at a glance: mode, realm, and for
-- each career whether it seeded, how many loadout rows exist, the selected index, and
-- (console) which gear/cosmetic slots each row actually holds.
-- ==================================================================
mod:command("gut_loadout_status", "Show the modded loadout store state (issue #375)", function()
    local mode = _adventure_mode()
    mod:echo(string.format("[loadouts] realm_modded=%s mode=%s", tostring(_in_modded_realm()), tostring(mode)))
    if mode == MODE_OFF then
        mod:echo("  feature INERT here (official realm / Versus / not in a backend view) -- store is not consulted")
    end
    local store = _store()
    local any = false
    for career_name, entry in pairs(store) do
        any = true
        local rows = entry.loadouts or {}
        mod:echo(string.format("  %s: seeded=%s loadouts=%d selected=%s bot=%s",
            tostring(career_name), tostring(entry._seeded and true or false),
            #rows, tostring(entry.selected_index), tostring(entry.bot_index)))
        for i = 1, #rows do
            local row = rows[i]
            local filled = {}
            for _, s in ipairs(LOADOUT_SLOT_NAMES) do
                if row and row[s] ~= nil then filled[#filled + 1] = s end
            end
            printf("[gut_dev:NATIVE_LOADOUTS] status career=%s row=%d selected=%s slots=[%s] talents=%s",
                tostring(career_name), i, tostring(i == entry.selected_index),
                table.concat(filled, ","), tostring(row and row.talents))
        end
    end
    if not any then mod:echo("  store EMPTY -- open a modded hero view (and switch a loadout slot) to seed from official") end
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
    { "HeroWindowLoadoutSelectionConsole", "_populate_context_menu_loadout" },  -- issue #372 preview crash guard
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
    { name = "native_loadouts_cosmetic_exempt_readonly", fn = function()
        -- issue #287: in READONLY, cosmetic slots stay editable (served/captured through the
        -- overlay); every gameplay slot / talent write stays blocked. COSMETIC_SLOT_SET must
        -- be exactly LOADOUT_SLOT_NAMES minus GEAR_SLOT_NAMES, with no leak into the gear set.
        if type(M.readonly_slot_editable) ~= "function" then return "readonly_slot_editable missing" end
        if type(_overlay) ~= "function" or type(_overlay_get) ~= "function" or type(_overlay_set) ~= "function" then
            return "cosmetic overlay helpers missing"
        end
        local in_loadout = {}
        for _, s in ipairs(LOADOUT_SLOT_NAMES) do in_loadout[s] = true end
        for s in pairs(COSMETIC_SLOT_SET) do
            if not in_loadout[s] then return "cosmetic slot not a loadout slot: " .. s end
            if GEAR_SLOT_SET[s] then return "cosmetic slot leaked into GEAR_SLOT_SET: " .. s end
            if not M.readonly_slot_editable(s) then return "readonly_slot_editable false for cosmetic " .. s end
        end
        for _, s in ipairs(LOADOUT_SLOT_NAMES) do
            -- Every loadout slot is exactly one of gear or cosmetic (partition): both or
            -- neither is a bug. Normalize to booleans so nil (absent) compares correctly.
            local is_gear = GEAR_SLOT_SET[s] == true
            local is_cos = COSMETIC_SLOT_SET[s] == true
            if is_gear == is_cos then
                return "slot not partitioned gear/cosmetic: " .. s
            end
        end
        -- Gameplay slots and talents must NOT be editable in READONLY.
        if M.readonly_slot_editable("slot_melee") then return "gear slot_melee editable in readonly" end
        if M.readonly_slot_editable("talents") then return "talents editable in readonly" end
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
    { name = "native_loadouts_seed_repair_predicate", fn = function()
        -- issue #375: the self-heal seed classifies a row as corrupt-partial iff it is
        -- missing a WEAPON slot (a legitimately edited loadout always keeps both weapons,
        -- so intentional jewelry unequips are NOT reclassified as corrupt).
        if type(_row_is_corrupt_partial) ~= "function" then return "_row_is_corrupt_partial missing" end
        if not _row_is_corrupt_partial(nil) then return "nil row must be corrupt-partial" end
        if not _row_is_corrupt_partial({ slot_ranged = "r" }) then return "row missing slot_melee must be corrupt-partial" end
        if not _row_is_corrupt_partial({ slot_melee = "m" }) then return "row missing slot_ranged must be corrupt-partial" end
        -- Both weapons present, ring intentionally empty -> edited, NOT corrupt.
        if _row_is_corrupt_partial({ slot_melee = "m", slot_ranged = "r" }) then
            return "row with both weapons must NOT be corrupt-partial (would clobber edits)"
        end
        -- Every weapon slot must be a gear slot (repair reads gear from official).
        for slot in pairs(WEAPON_SLOT_SET) do
            if not GEAR_SLOT_SET[slot] then return "weapon slot not in gear set: " .. slot end
        end
    end },
}

printf("[gut_dev:NATIVE_LOADOUTS] module loaded (%s) modded_realm=%s hooks=%d",
    MARKER, tostring(_in_modded_realm()), #M.HOOK_TARGETS)

return M
