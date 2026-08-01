-- _gut_native_loadouts.lua -- modded-realm-scoped native saved loadouts (issue #175)
--
-- Makes the game's NATIVE saved-loadout system (the roman-numeral I-VI loadout bar
-- in the hero view, plus its per-loadout talents and bot designation) read and write
-- a MODDED-ONLY store while the player is in the modded (EAC-untrusted) realm, so
-- official-realm loadouts are never touched by modded play and vice-versa. In the
-- OFFICIAL realm, and in Versus, the feature is completely inert (pure vanilla).
--
-- ISSUE #287 (mod-owned exemption): the "Use non-modded loadouts" READONLY mode makes the
-- GAMEPLAY loadout (gear/talents/loadout selection/bot) a read-only mirror of the official
-- data, but cosmetic slots (COSMETIC_SLOT_SET - weapon illusion, hat, portrait frame,
-- victory pose) and exact CWV-owned melee/ranged instance ids stay freely editable. Their
-- modded-only values live in a SEPARATE readonly overlay (_overlay), keyed by the official
-- loadout index, and NEVER touch official data. Ordinary weapons still snap back to official.
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
local Policy = mod:dofile("scripts/mods/gui_tweaker_dev/_gut_native_loadout_policy")
local WTTraceCore = mod:dofile("scripts/mods/gui_tweaker_dev/_gut_wt_loadout_trace_core")
local SelectedLoadoutTraceCore = mod:dofile("scripts/mods/gui_tweaker_dev/_gut_selected_loadout_trace_core")
local BackendCommit = mod:dofile("scripts/mods/gui_tweaker_dev/_gut_backend_commit")
local ExitSnapshotCore = mod:dofile("scripts/mods/gui_tweaker_dev/_gut_exit_snapshot_core")

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

local function _is_loadout_slot(slot_name)
    return GEAR_SLOT_SET[slot_name] or COSMETIC_SLOT_SET[slot_name]
end

-- The VMF settings key `characters_data` discriminates Adventure from Versus
-- (`vs_characters_data`), set by the mirror subclass (playfab_mirror_adventure.lua).
-- We scope the whole feature to the Adventure mirror; Versus stays vanilla.
local ADVENTURE_DATA_KEY = "characters_data"

local M = { MARKER = MARKER }

-- Issue #354: an enabled WT cross-character weapon was reported to disappear from
-- the active modded loadout intermittently across a process restart. There is no
-- exit-save transaction: GUT captures at BackendUtils.set_loadout_item and persists
-- immediately, while WT's lower interface hook keeps a separate session-only cache.
-- Trace only enabled WT weapon/career pairs, only the selected row, and deduplicate
-- each lifecycle outcome under a hard cap so normal inventory refreshes stay quiet.
local _wt_trace = WTTraceCore.new(24)

local function _wt_trace_context(career_name, backend_id)
    local backend = Managers and Managers.backend
    local iface = backend and backend._interfaces and backend._interfaces.items
    local mirror = iface and iface._backend_mirror
    local item = (iface and iface._items and iface._items[backend_id])
        or (mirror and mirror._inventory_items and mirror._inventory_items[backend_id])
    local data = item and (item.data or item)
    local item_key = item and (item.key or (data and data.key))
    local wt_dev = get_mod("wt_dev")
    local wt = get_mod("wt")
    if not item_key then
        -- The most important failure outcome is precisely that the stored backend ID
        -- is absent during launch. The item key cannot be recovered in that state, so
        -- retain one explicit unresolved record when either WT build is installed.
        return (wt_dev or wt) and "<unresolved>" or nil, "unknown"
    end

    local setting_id = "unlock_" .. tostring(career_name) .. "_" .. tostring(item_key)
    local owner = wt_dev and wt_dev:get(setting_id) == true and wt_dev
        or wt and wt:get(setting_id) == true and wt
    if not owner then return nil end

    local master = ItemMasterList and rawget(ItemMasterList, item_key)
    local can_wield = master and master.can_wield or (data and data.can_wield)
    local active = false
    if type(can_wield) == "table" then
        for i = 1, #can_wield do
            if can_wield[i] == career_name then active = true; break end
        end
    end
    return item_key, active
end

local function _trace_wt_loadout(phase, career_name, slot_name, idx, backend_id, result)
    if not WEAPON_SLOT_SET[slot_name] or not backend_id then return end
    local item_key, can_wield = _wt_trace_context(career_name, backend_id)
    if not item_key then return end
    local fields = {
        phase = phase, career = career_name, slot = slot_name, index = idx,
        backend_id = backend_id, item_key = item_key,
        can_wield = can_wield, result = result,
    }
    if WTTraceCore.take(_wt_trace, fields) then
        printf("[gut:354] phase=%s career=%s slot=%s idx=%s backend_id=%s item=%s wt_can_wield=%s result=%s trace=%d/24",
            tostring(phase), tostring(career_name), tostring(slot_name), tostring(idx),
            tostring(backend_id), tostring(item_key), tostring(can_wield), tostring(result),
            _wt_trace.count)
    end
end

M._issue354_trace_wired = true

-- ------------------------------------------------------------------
-- Store: VMF setting `native_loadouts`, kept in an in-memory working copy so the
-- hot mirror-read hooks don't re-`mod:get` a large table per slot per refresh.
--   _STORE[career_name] = {
--       selected_index = <int>,
--       bot_index      = <int or nil>,
--       bot_loadout    = <detached slot snapshot or nil>,
--       _bot_designation_snapshot_v2 = <one-time native-import marker>,
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
-- Readonly overlay (issue #287): modded-only cosmetic and exact CWV-instance values,
-- consulted ONLY in READONLY mode so mod-owned values stay editable while ordinary gameplay
-- values mirror official read-only. Kept SEPARATE from _STORE so the full-loadout store and this
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

-- READONLY mod-owned overlay read: overlaid value or nil (caller falls back to official).
local function _overlay_get(mirror, career_name, key, optional_loadout_index)
    local career_ov = _overlay()[career_name]
    if not career_ov then return nil end
    local row = career_ov[_official_index(mirror, career_name, optional_loadout_index)]
    return row and row[key]
end

-- READONLY mod-owned overlay write: capture modded-side, never touch official. Returns the
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

local function _overlay_clear(mirror, career_name, key, optional_loadout_index)
    local career_ov = _overlay()[career_name]
    if not career_ov then return false end
    local row = career_ov[_official_index(mirror, career_name, optional_loadout_index)]
    if not row or row[key] == nil then return false end
    row[key] = nil
    _persist_overlay()
    return true
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
--                 EXCEPTION (issue #287): cosmetic slots plus exact `cwv_*_NNN` weapon
--                 instances stay editable; their modded values live in the separate
--                 readonly overlay (_overlay), never touching official data.
-- Pure logic exposed for regression testing. Setting default_value=false => nil reads as OFF.
local MODE_OFF, MODE_STORE, MODE_READONLY = Policy.MODE_OFF, Policy.MODE_STORE, Policy.MODE_READONLY
M.MODE_OFF, M.MODE_STORE, M.MODE_READONLY = MODE_OFF, MODE_STORE, MODE_READONLY

function M.mode(is_modded, use_non_modded)
    return Policy.mode(is_modded, use_non_modded)
end

-- issue #287: in READONLY cosmetics and exact CWV instances stay editable; ordinary gear and
-- every other gameplay/talent write snap back. Pure predicate exposed for regression testing.
function M.readonly_slot_editable(slot_name, backend_id)
    return Policy.readonly_action(slot_name, backend_id) == "preserve"
end
M.readonly_action = Policy.readonly_action
M.is_cwv_backend_id = Policy.is_cwv_backend_id

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
local function _adventure_mode(items_iface)
    local m = _feature_mode()
    if m == MODE_OFF then return MODE_OFF end
    local mirror = items_iface and items_iface._backend_mirror
    local ok = mirror ~= nil
    if not mirror then
        ok, mirror = pcall(function()
            return Managers.backend:get_interface("items")._backend_mirror
        end)
    end
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
    -- A complete native loadout row owns EVERY loadout slot, not only melee/ranged.
    -- issue #402 follow-up: the first repair pass only treated missing weapons as
    -- partial corruption, so old rows could keep weapons while silently lacking
    -- outfit/hat/frame/pose/accessory slots. Those missing visual/accessory slots
    -- then looked like realm bleed or blank cosmetics. Keep this predicate aligned
    -- with LOADOUT_SLOT_NAMES so the whole row is repaired as one contract.
    if type(row) ~= "table" then return true end
    for i = 1, #LOADOUT_SLOT_NAMES do
        local slot = LOADOUT_SLOT_NAMES[i]
        if row[slot] == nil then return true end
    end
    return false
end

local function _repair_missing_loadout_slots(entry, official_rows)
    if type(entry) ~= "table" or type(entry.loadouts) ~= "table" or type(official_rows) ~= "table" then
        return 0
    end
    local repaired = 0
    for i = 1, #official_rows do
        local off_row = official_rows[i]
        local st_row = entry.loadouts[i]
        if type(off_row) == "table" and type(st_row) == "table" then
            for s = 1, #LOADOUT_SLOT_NAMES do
                local slot = LOADOUT_SLOT_NAMES[s]
                if st_row[slot] == nil and off_row[slot] ~= nil then
                    st_row[slot] = off_row[slot]
                    repaired = repaired + 1
                end
            end
        end
    end
    return repaired
end

local function _ensure_seeded(mirror, career_name, defer_persist)
    local store = _store()
    local entry = store[career_name]
    local cd = mirror._career_data and mirror._career_data[career_name]
    if entry and entry._seeded and entry._slot_integrity_v2 then return false end
    if type(cd) ~= "table" or cd[1] == nil then return false end
    local selected = (mirror._career_loadouts and mirror._career_loadouts[career_name]) or 1
    if not entry then
        store[career_name] = {
            selected_index = selected,
            bot_index = nil,
            loadouts = _deepcopy(cd),   -- array of { slot=id,..., talents=str }
            _seeded = true,
            _slot_integrity_v2 = true,
        }
        if not defer_persist then _persist() end
        if not defer_persist then
            printf("[gut_dev:NATIVE_LOADOUTS] seeded career=%s loadouts=%d selected=%d from official (fresh)",
                tostring(career_name), #cd, selected)
        end
        return true
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
    local slots_repaired = _repair_missing_loadout_slots(entry, cd)
    if entry.selected_index == nil or entry.loadouts[entry.selected_index] == nil then
        entry.selected_index = selected
    end
    entry._seeded = true
    entry._slot_integrity_v2 = true
    if not defer_persist then _persist() end
    if not defer_persist then
        printf("[gut_dev:NATIVE_LOADOUTS] repaired career=%s partial store (issues #375/#402): rows_added=%d rows_repaired=%d slots_repaired=%d loadouts=%d selected=%d",
            tostring(career_name), rows_added, rows_repaired, slots_repaired, #entry.loadouts, entry.selected_index)
    end
    return true
end

-- Tri-state gear-id resolution: "yes" (item PRESENTABLE right now), "no" (checkable and
-- absent right now), "unknown" (cannot check). RAW FIELD READS ONLY - NEVER interface methods.
--
-- issue #387 FIX (v0.2.215) -- FAITHFUL to get_item_from_id. This predicate must agree with
-- what the hero-view presentation uses, `iface:get_item_from_id(id)`, or a served weapon reads
-- "presentable" here yet renders nil downstream and the slot STICKS on the previously-wielded
-- weapon after a loadout switch. Source (backend_interface_item_playfab.lua:384-388):
--   get_item_from_id(id) == get_all_backend_items()[id] == self._items[id]  (after a dirty _refresh)
-- It consults `self._items` ONLY -- NEVER `self._fake_items`, and applies NO other validation
-- (no data/removed-set check; there is no _all_backend_items field). The OLD resolver returned
-- YES on `_items`-OR-`_fake_items` presence: `_fake_items` is a strict subset of `_items` in the
-- normal case (the mirror inserts every fake into BOTH, playfab_mirror_base.lua:2400-2401), so it
-- added no true positives -- but in the game-mode branch `self._items` is a FROZEN CLONE taken at
-- the last refresh (:68-73) while `_fake_items` stays live, so a fake-only / stale-clone id read
-- YES here yet get_item_from_id (which rebuilds `_items`) returned nil. That divergence was the
-- #387 stuck-weapon signature (es_mercenary loadout-5 melee C60E860C16C0B5E9: served store, never
-- presentable). So: drop the `_fake_items` positive and read the SAME source get_item_from_id
-- resolves against.
--   _dirty == false : `self._items` IS what get_item_from_id returns -> read it directly.
--   _dirty == true  : (a loadout switch sets _dirty, :667) `self._items` is stale; get_item_from_id
--     would _refresh and rebuild it from `backend_mirror:get_all_inventory_items()` (:75) plus the
--     active game-mode overlay (:68-73). Predict from those SOURCE tables.
--
-- Burn 2026-07-02 #3 (v0.2.173, PC-A 21:09 log): calling iface:get_item_from_id() from inside the
-- mirror get_character_data hook recursed unboundedly - get_item_from_id -> get_all_backend_items ->
-- `if self._dirty then self:_refresh()` -> _refresh -> mirror get_character_data -> our hook ->
-- resolve -> get_item_from_id -> _dirty STILL true -> stack overflow (~10k frames, surfaced at
-- cosmetics_tweaker.lua:1513) then 1 GiB lua_heap exhaustion. Every read below is a PLAIN FIELD
-- INDEX (no method call, no dirty check): `get_all_inventory_items()` is a bare `return
-- self._inventory_items` (playfab_mirror_base.lua:2189), so reading `_inventory_items` directly
-- performs no refresh and re-entry is structurally impossible. A stale table at worst yields a
-- transient "no" -> per-read official fallback that self-heals on the next read.
local RESOLVE_YES, RESOLVE_NO, RESOLVE_UNKNOWN = 1, 2, 3
local function _resolve_item_raw(id)
    local ok, state = pcall(function()
        local backend = Managers and Managers.backend
        local iface = backend and backend._interfaces and backend._interfaces.items
        if not iface then return RESOLVE_UNKNOWN end
        if not iface._dirty then
            local items = iface._items                       -- exactly what get_item_from_id reads when clean
            if items == nil then return RESOLVE_UNKNOWN end
            return items[id] and RESOLVE_YES or RESOLVE_NO
        end
        -- dirty: self._items is stale; predict the pending rebuild from its sources.
        local mirror = iface._backend_mirror
        local inv = mirror and mirror._inventory_items       -- backend_mirror:get_all_inventory_items() -> _items on refresh (:75)
        local gm = iface._active_game_mode_specific_items    -- overlaid onto _items on refresh (:71-73)
        if inv == nil and gm == nil then return RESOLVE_UNKNOWN end
        if (inv and inv[id]) or (gm and gm[id]) then return RESOLVE_YES end
        return RESOLVE_NO
    end)
    return ok and state or RESOLVE_UNKNOWN
end

-- ------------------------------------------------------------------
-- issue #387 diagnostic (weapons don't follow the selected loadout while jewelry/cosmetics
-- do). get_character_data is HOT (called per slot per interface refresh), so a raw printf
-- would flood the log. Throttled to ONE line per (career, slot, ROW) whenever that row's
-- served (value, source) CHANGES -- exactly a loadout switch or an equip -- so the log reads
-- as a clean per-change trace: which id each GEAR slot served, from the modded STORE or an
-- OFFICIAL fallback. Always-on in dev, never a menu toggle (throttle, don't remove).
--
-- issue 480 (the 20,120-line flood): the original cache was keyed (career, slot) ONLY, with
-- the row index inside the signature -- but interface refreshes read the SAME slot across
-- MULTIPLE loadout indices back to back (previews iterate rows), so consecutive reads always
-- differed from the single cached signature and every read re-emitted an identical line every
-- ~3 ms. Keying by (career, slot, idx) gives each row its own cache cell: the first
-- occurrence still prints verbatim, an identical repeat never does, and a genuine per-row
-- value/source change (the issue-474 mechanism-3 signal) still prints exactly once.
-- Cache is bounded: careers x gear slots x loadout rows, well under a thousand entries.
-- ------------------------------------------------------------------
local _gear_read_trace = {}
local function _trace_should_emit(career_name, key, idx, value, source)
    local tk = tostring(career_name) .. "/" .. tostring(key) .. "/" .. tostring(idx)
    local sig = tostring(value) .. "|" .. tostring(source)
    if _gear_read_trace[tk] ~= sig then
        _gear_read_trace[tk] = sig
        return true
    end
    return false
end

-- Issue #375 regression boundary.  A selected native-loadout row has been observed
-- serving one weapon from a different row after a row switch.  The existing #387
-- trace identifies each slot independently, but cannot prove which selected row and
-- caller requested the pair.  Emit one atomic snapshot at the mirror read boundary:
-- requested/resolved/selected indices, both weapons in the resolved row, both weapons
-- in the canonical selected row, the value actually returned, and the caller surface.
-- Reads are hot, so the pure trace core deduplicates per caller/row/slot and caps the
-- cache at 128 entries.  No command or menu toggle is required to collect evidence.
local _selected_loadout_trace = SelectedLoadoutTraceCore.new(128)

local function _selected_read_caller()
    if not (debug and debug.getinfo) then return "unknown" end
    for level = 3, 10 do
        local ok, info = pcall(debug.getinfo, level, "nS")
        if not ok or not info then break end
        local source = tostring(info.short_src or info.source or "unknown")
        if not string.find(source, "_gut_native_loadouts", 1, true)
            and not string.find(source, "vmf_hook", 1, true)
        then
            local name = info.name and (":" .. tostring(info.name)) or ""
            return source .. name
        end
    end
    return "unknown"
end

local function _trace_selected_read(entry, career_name, key, requested_index, resolved_index, served_value, source)
    if not (entry and WEAPON_SLOT_SET[key]) then return end
    local row = entry.loadouts and entry.loadouts[resolved_index]
    local selected_row = entry.loadouts and entry.loadouts[entry.selected_index]
    local caller = _selected_read_caller()
    local snapshot = {
        career = career_name,
        slot = key,
        requested_index = requested_index,
        resolved_index = resolved_index,
        selected_index = entry.selected_index,
        row_melee = row and row.slot_melee,
        row_ranged = row and row.slot_ranged,
        selected_melee = selected_row and selected_row.slot_melee,
        selected_ranged = selected_row and selected_row.slot_ranged,
        served_value = served_value,
        source = source,
        caller = caller,
    }
    if _selected_loadout_trace:record(snapshot) then
        printf("[gut_dev:NATIVE_LOADOUTS] #375 selected-read career=%s caller=%s requested=%s resolved=%s selected=%s row=[melee=%s ranged=%s] canonical=[melee=%s ranged=%s] served=[slot=%s value=%s source=%s]",
            tostring(career_name), tostring(caller), tostring(requested_index),
            tostring(resolved_index), tostring(entry.selected_index),
            tostring(snapshot.row_melee), tostring(snapshot.row_ranged),
            tostring(snapshot.selected_melee), tostring(snapshot.selected_ranged),
            tostring(key), tostring(served_value), tostring(source))
    end
end
M.trace_should_emit = _trace_should_emit   -- exported for the /gut_regression_test throttle check
local function _trace_gear_read(career_name, key, idx, value, source)
    if _trace_should_emit(career_name, key, idx, value, source) then
        printf("[gut_dev:NATIVE_LOADOUTS] #387 gear-read career=%s slot=%s idx=%s value=%s source=%s",
            tostring(career_name), tostring(key), tostring(idx), tostring(value), source)
    end
end

-- ------------------------------------------------------------------
-- Official-space gear fallback (P0, residual of issues 387/372). `store_idx` is a
-- STORE-space loadout index: in MODE_STORE, get_career_loadouts serves the STORE's rows, so
-- every explicit index circulating through the interface/UI is an index into OUR store, not
-- into official `_career_data`. The two spaces share no relationship (the store grows via
-- add_loadout in modded; official rows grow only in the official realm), so forwarding a
-- store index into the official read is wrong: vanilla indexes
-- `_career_data[career][index]` directly and returns nil for a missing row
-- (playfab_mirror_base.lua:1909-1919), and a nil weapon slot fatals at spawn wield
-- ("Tried to wield default slot ... contained no weapon").
-- Translation: pass nil, so vanilla resolves the official SELECTED row via
-- `_career_loadouts[career]` (:1911) -- a row that exists whenever official data exists.
-- Last resort for WEAPON slots only: the career's default loadout
-- (get_default_loadouts :1955-1966; array of rows, backend_interface_item_playfab.lua
-- :207-222). If even that is nil we printf loudly and serve nil rather than invent an id --
-- never spawn from a guess. `read_official` is the wrapped vanilla get_character_data.
-- ------------------------------------------------------------------
local function _official_gear_fallback(read_official, mirror, career_name, key, store_idx)
    local v = read_official(mirror, career_name, key, nil)   -- nil = official SELECTED row
    if v ~= nil then return v end
    if WEAPON_SLOT_SET[key] then
        local ok_d, defaults = pcall(mirror.get_default_loadouts, mirror, career_name)
        local row = ok_d and type(defaults) == "table" and defaults[1] or nil
        local dv = row and row[key] or nil
        if dv ~= nil then
            _trace_gear_read(career_name, key, store_idx, dv, "official-fallback-default")  -- issue #387
            return dv
        end
        pcall(printf, "[gut_dev:NATIVE_LOADOUTS] WEAPON SLOT UNRESOLVED career=%s slot=%s store_idx=%s: official selected row and default loadout both nil, serving nil",
            tostring(career_name), tostring(key), tostring(store_idx))
    end
    return nil
end
M.official_gear_fallback = _official_gear_fallback   -- exported for the /gut_regression_test translation check

-- ------------------------------------------------------------------
-- BackendUtils equip capture (v0.2.175). With Loremaster's Armoury installed, menu equips
-- route through an LA-CLONED interface whose copied methods bypass class-level hooks, so
-- gear equips never reached the PlayFabMirrorAdventure.set_character_data capture (friend
-- logs 2026-07-02 21:25/21:27: a live equip produced ZERO captures; store stayed stale so
-- the correction did not survive relaunch). cim burned identically 2026-05-30 and solved
-- it the same way - see crafting_in_modded_dev.lua:1495 comment block. Capture at the
-- stable OUTER entry point the hero view calls (hero_view_state_overview.lua:1108),
-- TABLE-form per the repo Hooking rule, installed deferred once the backend answers
-- (cim/cosmetics timing). Issue #353 extends this seam to COSMETIC slots too: LA cosmetic
-- dispatch can bypass the concrete mirror hook just like LA gear dispatch. BackendUtils
-- still carries the transient backend id, so resolve the item through the SAME selected
-- loadout interface and translate it exactly as vanilla does (`override_id or ItemId`,
-- backend_interface_item_playfab.lua:656-663) before writing the modded store/overlay.
-- ------------------------------------------------------------------
local _bu_capture_installed = false
local _bu_unresolved_seen = {}

local function _bu_canonical_value(backend_id, slot_name)
    if not Policy.is_cosmetic_slot(slot_name) then
        return Policy.canonical_equip_value(slot_name, backend_id, nil)
    end
    local ok_iface, iface = pcall(function()
        return Managers.backend:get_loadout_interface_by_slot(slot_name)
    end)
    if not ok_iface or not iface or type(iface.get_all_backend_items) ~= "function" then
        return nil, "loadout_interface_unavailable"
    end
    -- Safe here: this is the outer menu-equip hook, not a mirror read hook. Calling this
    -- from get_character_data would recurse through _refresh and exhaust the Lua heap.
    local ok_items, all_items = pcall(iface.get_all_backend_items, iface)
    local item = ok_items and type(all_items) == "table" and all_items[backend_id] or nil
    return Policy.canonical_equip_value(slot_name, backend_id, item)
end

local function _capture_bu_equip(mode, mirror, career_name, slot_name, value, source)
    if mode == MODE_READONLY then
        if Policy.readonly_action(slot_name, value) ~= "preserve" then return end
        local idx = _overlay_set(mirror, career_name, slot_name, value, nil)
        _dirtify()
        printf("[gut_dev:NATIVE_LOADOUTS] BU equip capture career=%s idx=%s slot=%s source=%s -> readonly overlay",
            tostring(career_name), tostring(idx), tostring(slot_name), tostring(source))
        return
    end
    if mode ~= MODE_STORE then return end
    -- issue #375: seed the official snapshot BEFORE we can create a store entry.
    _ensure_seeded(mirror, career_name)
    local store = _store()
    local entry = store[career_name]
    -- Fallback bare entry only if seeding could not run yet (official data not ready).
    -- NOT flagged _seeded, so _ensure_seeded repairs it once data lands.
    if not entry then entry = { selected_index = 1, bot_index = nil, loadouts = {} }; store[career_name] = entry end
    local idx = entry.selected_index
    entry.loadouts[idx] = entry.loadouts[idx] or {}
    entry.loadouts[idx][slot_name] = value
    _persist()
    _trace_wt_loadout("capture", career_name, slot_name, idx, value, "stored")
    printf("[gut_dev:NATIVE_LOADOUTS] BU equip capture career=%s idx=%s slot=%s source=%s -> store",
        tostring(career_name), tostring(idx), tostring(slot_name), tostring(source))
end

local function _install_bu_capture()
    if _bu_capture_installed then return end
    local BU = rawget(_G, "BackendUtils")
    if not (BU and BU.set_loadout_item and Managers and Managers.backend and Managers.backend.get_interface) then return end
    local ok_iface = pcall(function() return Managers.backend:get_interface("items") end)
    if not ok_iface then return end
    _bu_capture_installed = true
    mod:hook(BU, "set_loadout_item", function(func, backend_id, career_name, slot_name)
        -- 3-arg entry point, always the SELECTED loadout (no index arg by design).
        local mode = _adventure_mode()
        local is_loadout_slot = _is_loadout_slot(slot_name)
        if mode ~= MODE_OFF and career_name and backend_id and is_loadout_slot then
            local ok_m, mirror = pcall(function() return Managers.backend:get_interface("items")._backend_mirror end)
            local value, source = _bu_canonical_value(backend_id, slot_name)
            if ok_m and mirror and value ~= nil then
                _capture_bu_equip(mode, mirror, career_name, slot_name, value, source)
            elseif COSMETIC_SLOT_SET[slot_name] then
                -- Bounded evidence for an unexpected LA/item-registry timing miss. Never
                -- persist the transient backend id into a cosmetic slot as a guess.
                local token = tostring(slot_name) .. "\0" .. tostring(backend_id) .. "\0" .. tostring(source)
                if not _bu_unresolved_seen[token] then
                    _bu_unresolved_seen[token] = true
                    printf("[gut_dev:NATIVE_LOADOUTS] BU cosmetic capture SKIP career=%s slot=%s bid=%s reason=%s mirror=%s",
                        tostring(career_name), tostring(slot_name), tostring(backend_id), tostring(source), tostring(ok_m and mirror ~= nil))
                end
            end
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
    -- READONLY: ordinary gameplay values read straight from official; mod-owned cosmetics
    -- and exact CWV instances are served from the overlay so receiver-local equips do not
    -- snap back. Talents and ordinary gear stay official read-only.
    if m == MODE_READONLY then
        local v = _overlay_get(self, career_name, key, optional_loadout_index)
        if v ~= nil and Policy.readonly_action(key, v) == "preserve" then
            return v
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
    if lo == nil then
        _trace_selected_read(entry, career_name, key, optional_loadout_index, idx, nil, "store-row-missing")
        return nil
    end
    local value = lo[key]
    -- Non-destructive gear fallback (2026-07-02 v0.2.172 spawn-fatal burn): a gear id that
    -- is empty or unresolvable RIGHT NOW is served from the OFFICIAL value for this read
    -- only. The store is never mutated, so a late-registering modded id (cim craft,
    -- LA/cosmetics instance UUID) serves again the moment it resolves. Empty-slot fallback
    -- applies only to weapon slots (empty jewelry is a legitimate state; empty melee/ranged
    -- fatals at spawn wield).
    if GEAR_SLOT_SET[key] then
        -- BOTH fallback calls below go through _official_gear_fallback, which passes a NIL
        -- index (official selected row). `idx` here is STORE-space; the pre-fix code forwarded
        -- it into the official read, where a missing official row returned nil and an empty
        -- weapon slot fataled at spawn (P0; residual of issues 387/372).
        if value == nil then
            if WEAPON_SLOT_SET[key] then
                _trace_gear_read(career_name, key, idx, value, "official-fallback-nil-weapon")  -- issue #387
                local served = _official_gear_fallback(func, self, career_name, key, idx)
                _trace_selected_read(entry, career_name, key, optional_loadout_index, idx, served, "official-fallback-nil-weapon")
                return served
            end
            _trace_gear_read(career_name, key, idx, value, "store-nil-jewelry")  -- issue #387
            return nil
        end
        -- Fall back to the official value ONLY on an affirmative miss; on UNKNOWN
        -- (backend not inspectable) serve the store value unchanged - guessing
        -- "official" there would bleed official gear into modded loadouts at boot.
        local rstate = _resolve_item_raw(value)
        if rstate == RESOLVE_NO then
            if idx == entry.selected_index then
                _trace_wt_loadout("apply", career_name, key, idx, value, "official-fallback-resolve-no")
            end
            _trace_gear_read(career_name, key, idx, value, "official-fallback-resolve-no")  -- issue #387
            local served = _official_gear_fallback(func, self, career_name, key, idx)
            _trace_selected_read(entry, career_name, key, optional_loadout_index, idx, served, "official-fallback-resolve-no")
            return served
        end
        -- issue #387: split YES vs UNKNOWN. Empirically (console-2026-07-06-21.28) a weapon
        -- served on UNKNOWN can still fail at PRESENTATION (get_item_from_id -> nil), leaving
        -- the slot stuck on the previously-wielded weapon after a loadout switch (es_mercenary
        -- loadout-5 melee C60E860C16C0B5E9: served source=store, never resolved to an item, so
        -- the grid kept loadout-6's melee while the ranged slot updated normally). YES means
        -- the raw registry holds it right now; UNKNOWN means we could not inspect the registry.
        _trace_gear_read(career_name, key, idx, value, rstate == RESOLVE_YES and "store-yes" or "store-unknown")  -- issue #387
        if idx == entry.selected_index then
            _trace_wt_loadout("apply", career_name, key, idx, value,
                rstate == RESOLVE_YES and "served-store-yes" or "served-store-unknown")
        end
    end
    _trace_selected_read(entry, career_name, key, optional_loadout_index, idx, value,
        GEAR_SLOT_SET[key] and "store" or "store-non-gear")
    return value
end)

-- get_career_loadouts(self, career_name) -> (selected_index, loadouts_array) -- base:1944
mod:hook("PlayFabMirrorAdventure", "get_career_loadouts", function(func, self, career_name)
    local m = _mirror_mode(self)
    if m == MODE_OFF or not career_name then
        return func(self, career_name)
    end
    -- READONLY: return the official (selected, loadouts) array but overlay mod-owned values
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
                    if Policy.readonly_action(slot, v) == "preserve" then out[idx][slot] = v end
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
        -- issue #287: mod-owned edits are captured into the readonly overlay, official data
        -- stays untouched. Ordinary gameplay/talent writes remain blocked.
        local action = Policy.readonly_action(key, value)
        if action == "preserve" then
            local idx = _overlay_set(self, career_name, key, value, optional_loadout_index)
            _dirtify()   -- rebuild interface caches so the overlay value is picked up
            printf("[gut_dev:NATIVE_LOADOUTS] set_character_data career=%s idx=%s key=%s value=%s -> readonly overlay (official untouched)",
                tostring(career_name), tostring(idx), tostring(key), tostring(value))
            return
        elseif action == "clear" then
            local cleared = _overlay_clear(self, career_name, key, optional_loadout_index)
            if cleared then _dirtify() end
            printf("[gut_dev:NATIVE_LOADOUTS] set_character_data career=%s key=%s value=%s -> official fallback (cleared_mod_overlay=%s)",
                tostring(career_name), tostring(key), tostring(value), tostring(cleared))
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
        -- issue #287: mirror the set_character_data mod-owned exemption on the LA-bypass
        -- write path too, so cosmetics/CWV instances through an LA-cloned interface persist.
        local action = Policy.readonly_action(key, value)
        if action == "preserve" then
            local idx = _overlay_set(self, career, key, value, loadout_index)
            _dirtify()
            printf("[gut_dev:NATIVE_LOADOUTS] set_career_read_only_data career=%s idx=%s key=%s value=%s -> readonly overlay (official untouched)",
                tostring(career), tostring(idx), tostring(key), tostring(value))
            return
        elseif action == "clear" then
            local cleared = _overlay_clear(self, career, key, loadout_index)
            if cleared then _dirtify() end
            printf("[gut_dev:NATIVE_LOADOUTS] set_career_read_only_data career=%s key=%s value=%s -> official fallback (cleared_mod_overlay=%s)",
                tostring(career), tostring(key), tostring(value), tostring(cleared))
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

-- #954 extracts both bot-specific hooks into one owner. It persists a detached
-- designation snapshot so later edits to the player's source row cannot change
-- the bot, while leaving official/readonly behavior on the vanilla boundary.
local BotLoadoutSnapshot = mod:dofile("scripts/mods/gui_tweaker_dev/_gut_bot_loadout_snapshot")
local function _native_bot_assignments()
    local selection = PlayerData and PlayerData.loadout_selection
    if type(selection) ~= "table" then return nil end
    if selection.bot_equipment == nil then return {} end
    if type(selection.bot_equipment) ~= "table" then return nil end
    return selection.bot_equipment
end
BotLoadoutSnapshot.install(mod, {
    mode = _adventure_mode, store = _store, persist = _persist,
    policy = Policy, slot_names = LOADOUT_SLOT_NAMES,
    mode_off = MODE_OFF, mode_store = MODE_STORE, mode_readonly = MODE_READONLY,
    log_prefix = "gut_dev", native_bot_assignments = _native_bot_assignments,
})

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
-- other hooks on this class target _save_bot_equipment (_gut_bot_loadout_snapshot.lua) and
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
-- Re-seed owner + command. The seed is one-time by design, so a snapshot taken while the mirror
-- held bad data (e.g. blacksmith items committed to the cloud by the pre-isolation #174
-- bleed, seen 2026-07-02 on merc Kruber slot_melee) is frozen until explicitly reset.
-- /reset_modded_loadouts        -> wipe the whole modded store + cosmetic overlay
-- /reset_modded_loadouts <career> -> wipe one career (e.g. es_mercenary)
-- Issue #1033 additionally calls this owner after a confirmed Mod Tweaker DEFAULT
-- transaction for WT/Cosmetics. It clears the modded copies and, when the Adventure
-- mirror is live, clones every official career immediately with ONE final persistence
-- write. Official data is read only; no backend method or cloud write is called.
-- ==================================================================
function M.reset_modded_loadouts(career_arg, source, echo_result)
    local store = _store()
    local overlay = _overlay()
    local cleared, explicit_found = Policy.clear_modded_loadouts(store, overlay, career_arg)
    if career_arg and career_arg ~= "" and not explicit_found then
        if echo_result then
            mod:echo("No modded loadout store for '" .. tostring(career_arg) .. "' (nothing to reset)")
        end
        printf("[gut_dev:NATIVE_LOADOUTS] reset requested for unknown career=%s", tostring(career_arg))
        return true, { cleared = 0, seeded = 0, mirror = false }
    end

    local ok_mirror, mirror = pcall(function()
        return Managers.backend:get_interface("items")._backend_mirror
    end)
    local adventure = ok_mirror and mirror
        and mirror._characters_data_key == ADVENTURE_DATA_KEY
    local seeded = 0
    if adventure then
        local careers = Policy.official_seed_careers(mirror, career_arg)
        for i = 1, #careers do
            if _ensure_seeded(mirror, careers[i], true) then seeded = seeded + 1 end
        end
    end
    -- One bounded persistence transaction regardless of career count. The mirror
    -- methods remain untouched, so the official cloud diff stays empty.
    _persist()
    _persist_overlay()
    _dirtify()
    if echo_result then
        mod:echo(string.format(
            "Modded loadouts reset for %d career(s); %d copied from official",
            cleared, seeded))
    end
    printf("[gut:1033] source=%s cleared=%d seeded=%d adventure_mirror=%s writes=2 dirtify=1",
        tostring(source or "command"), cleared, seeded, tostring(adventure and true or false))
    return true, { cleared = cleared, seeded = seeded, mirror = adventure and true or false }
end

mod._gut_reset_modded_loadouts = function(source)
    return M.reset_modded_loadouts(nil, source or "api", false)
end

mod:command("reset_modded_loadouts", "Reset modded loadouts to re-seed from official (optional: career name)", function(career_arg)
    M.reset_modded_loadouts(career_arg, "command", true)
end)

-- ==================================================================
-- /gut_loadout_status (issue #375 diagnostics) -- echo the modded loadout store state
-- to CHAT (visible with mod-logging off) plus a per-row slot dump to the console log, so
-- "is the loadout system even working" is answerable at a glance: mode, realm, and for
-- each career whether it seeded, how many loadout rows exist, the selected index, and
-- (console) which gear/cosmetic slots each row actually holds.
-- ==================================================================
-- issue #387 presentation-side resolution probe. SAFE to call get_item_from_id here because
-- this runs in a chat-command context, NOT inside a mirror read hook (the v0.2.173 recursion
-- was get_item_from_id called from within the get_character_data hook). Returns the resolved
-- item key (or nil) so a dangling/unresolvable weapon id -- the id that leaves a slot stuck on
-- the previous weapon at switch time -- is visible per row.
local function _probe_resolve(id)
    if id == nil then return nil end
    local ok, key = pcall(function()
        local iface = Managers.backend:get_interface("items")
        local item = iface and iface:get_item_from_id(id)
        return item and item.data and (item.data.key or item.data.name)
    end)
    return ok and key or nil
end

local function _slot_resolves(slot_name, id)
    if id == nil then return false end
    if _probe_resolve(id) ~= nil then return true end
    if COSMETIC_SLOT_SET[slot_name] and rawget(_G, "ItemMasterList") and rawget(ItemMasterList, id) then
        return true
    end
    return false
end

mod:command("gut_loadout_status", "Show the modded loadout store state + resolve gear ids (issue #375/#387)", function(career_arg)
    local mode = _adventure_mode()
    mod:echo(string.format("[loadouts] realm_modded=%s mode=%s", tostring(_in_modded_realm()), tostring(mode)))
    if mode == MODE_OFF then
        mod:echo("  feature INERT here (official realm / Versus / not in a backend view) -- store is not consulted")
    end
    local filter = (career_arg and career_arg ~= "") and career_arg or nil
    local store = _store()
    local any = false
    for career_name, entry in pairs(store) do
        if not filter or career_name == filter then
            any = true
            local rows = entry.loadouts or {}
            -- Count unresolvable WEAPON ids across rows (the #387 stuck-weapon signature).
            local weapon_fail = 0
            local slot_integrity_fail = 0
            for i = 1, #rows do
                local row = rows[i]
                for _, slot in ipairs(LOADOUT_SLOT_NAMES) do
                    local id = row and row[slot]
                    if id == nil or not _slot_resolves(slot, id) then
                        slot_integrity_fail = slot_integrity_fail + 1
                    end
                end
                for slot in pairs(WEAPON_SLOT_SET) do
                    local id = row and row[slot]
                    if id ~= nil and _probe_resolve(id) == nil then weapon_fail = weapon_fail + 1 end
                end
            end
            mod:echo(string.format("  %s: seeded=%s slots_v2=%s loadouts=%d selected=%s bot=%s weapon_ids_unresolvable=%d slot_integrity_failures=%d",
                tostring(career_name), tostring(entry._seeded and true or false), tostring(entry._slot_integrity_v2 and true or false),
                #rows, tostring(entry.selected_index), tostring(entry.bot_index), weapon_fail, slot_integrity_fail))
            for i = 1, #rows do
                local row = rows[i]
                local filled = {}
                local missing = {}
                for _, s in ipairs(LOADOUT_SLOT_NAMES) do
                    if row and row[s] ~= nil then filled[#filled + 1] = s
                    else missing[#missing + 1] = s end
                end
                printf("[gut_dev:NATIVE_LOADOUTS] status career=%s row=%d selected=%s slots=[%s] missing=[%s] talents=%s",
                    tostring(career_name), i, tostring(i == entry.selected_index),
                    table.concat(filled, ","), table.concat(missing, ","), tostring(row and row.talents))
                -- issue #387: resolve each GEAR slot id both ways -- raw registry (what the
                -- get_character_data fallback consults) AND get_item_from_id (what the hero-view
                -- presentation consults). A slot with raw=UNKNOWN/YES but get_item_from_id=FAIL is
                -- exactly the stuck-weapon case: served from the store, unpresentable at switch.
                if row then
                    for _, s in ipairs(GEAR_SLOT_NAMES) do
                        local id = row[s]
                        if id ~= nil then
                            local raw = _resolve_item_raw(id)
                            local rawname = (raw == RESOLVE_YES and "raw=YES") or (raw == RESOLVE_NO and "raw=NO") or "raw=UNKNOWN"
                            local key = _probe_resolve(id)
                            printf("[gut_dev:NATIVE_LOADOUTS] status-resolve career=%s row=%d %s id=%s %s get_item_from_id=%s",
                                tostring(career_name), i, s, tostring(id), rawname, tostring(key or "<FAIL>"))
                        end
                    end
                end
            end
        end
    end
    if not any then
        if filter then mod:echo("  no store entry for '" .. filter .. "'")
        else mod:echo("  store EMPTY -- open a modded hero view (and switch a loadout slot) to seed from official") end
    end
end)

-- ==================================================================
-- /scrub_official_loadouts (issue #402) -- OFFICIAL-realm repair for the pre-isolation #174
-- bleed: modded/dangling native loadout ids committed to the OFFICIAL cloud loadouts
-- BEFORE the modded-realm isolation (this file) existed. Audit 2026-07-06 (decompiled source):
-- every runtime write that diverges official _career_data from its mirror (and so reaches the
-- PlayFab cloud) funnels through PlayFabMirrorBase.set_character_data -- it writes _career_data
-- at :1933 BEFORE delegating to set_career_read_only_data at :1941, so it is the SOLE choke
-- point, and weapons, cosmetics, accessories, frame, and pose all persist through the same
-- row-slot path. We hook it and no-op it in modded, so NO new leak is possible. But rows
-- already corrupted by the pre-isolation bleed never self-heal -- this repairs them.
--
-- REPORT (default, read-only, safe anywhere): list every official loadout slot in
--   LOADOUT_SLOT_NAMES whose stored id is missing or does NOT resolve by the slot-appropriate
--   policy (backend item, or for cosmetics a known ItemMasterList key).
-- APPLY (`/scrub_official_loadouts apply`): replace each broken slot's id with a resolvable id
--   the player ALREADY OWNS for that same slot (taken from another of their official loadout
--   rows). It writes ONLY a value it has verified resolves, into a slot that is CURRENTLY broken,
--   so it can never break a working slot; if no owned replacement resolves it reports and skips
--   (re-equip that slot manually). HARD-GATED to the OFFICIAL realm: in modded, set_character_data
--   is captured to the store, so the official write would never land -- refuse and say so.
-- ==================================================================
mod:command("scrub_official_loadouts", "Repair modded/dangling OFFICIAL loadout slot ids (issue #402; add 'apply' to write, default report-only)", function(arg)
    local do_apply = (arg == "apply")
    if do_apply and _in_modded_realm() then
        mod:echo("[scrub] REFUSED -- you are in the MODDED realm; an official write is captured to the modded store here.")
        mod:echo("[scrub] Enter the OFFICIAL (EAC-trusted) realm, open the hero view, then run: /scrub_official_loadouts apply")
        return
    end
    local ok_m, mirror = pcall(function() return Managers.backend:get_interface("items")._backend_mirror end)
    if not ok_m or not mirror or type(mirror._career_data) ~= "table" then
        mod:echo("[scrub] backend not ready -- open the hero view first, then re-run")
        return
    end
    -- A replacement must itself resolve; only ever an id the player already owns for this slot.
    local function _owned_replacement(slot, rows)
        for i = 1, #rows do
            local id = rows[i] and rows[i][slot]
            if _slot_resolves(slot, id) then return id end
        end
        return nil
    end
    mod:echo(string.format("[scrub] official loadout audit (%s)%s",
        do_apply and "APPLY" or "report-only", _in_modded_realm() and " [WARN: modded realm -- report only]" or ""))
    local broken, fixed, skipped = 0, 0, 0
    for career_name, rows in pairs(mirror._career_data) do
        if type(rows) == "table" then
            for i = 1, #rows do
                local row = rows[i]
                if type(row) == "table" then
                    for _, slot in ipairs(LOADOUT_SLOT_NAMES) do
                        local id = row[slot]
                        if not _slot_resolves(slot, id) then
                            broken = broken + 1
                            printf("[gut_dev:NATIVE_LOADOUTS] #402 official BROKEN career=%s row=%d slot=%s id=%s",
                                tostring(career_name), i, slot, tostring(id))
                            if do_apply then
                                local repl = _owned_replacement(slot, rows)
                                if repl ~= nil then
                                    local ok_w = pcall(function() mirror:set_character_data(career_name, slot, repl, nil, i) end)
                                    if ok_w then
                                        fixed = fixed + 1
                                        printf("[gut_dev:NATIVE_LOADOUTS] #402 official REPAIRED career=%s row=%d slot=%s -> %s",
                                            tostring(career_name), i, slot, tostring(repl))
                                    else
                                        skipped = skipped + 1
                                    end
                                else
                                    skipped = skipped + 1
                                    printf("[gut_dev:NATIVE_LOADOUTS] #402 official NO-OWNED-REPLACEMENT career=%s row=%d slot=%s (re-equip this slot manually)",
                                        tostring(career_name), i, slot)
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    if broken == 0 then
        mod:echo("[scrub] official loadouts clean -- no broken native loadout slots")
    elseif do_apply then
        local skipped_suffix = skipped > 0 and string.format(" (%d skipped -- re-equip manually)", skipped) or ""
        if fixed == 0 then
            mod:echo(string.format("[scrub] repaired 0/%d broken slot(s)%s; no cloud commit was requested",
                broken, skipped_suffix))
            return
        end

        local function commit_complete(status)
            local committed, detail = BackendCommit.classify_status(status)
            if committed then
                mod:echo(string.format("[scrub] cloud commit complete -- repaired %d/%d broken slot(s)%s",
                    fixed, broken, skipped_suffix))
                printf("[gut_dev:NATIVE_LOADOUTS] #402 cloud commit SUCCESS fixed=%d broken=%d skipped=%d status=%s",
                    fixed, broken, skipped, tostring(status))
            else
                mod:echo(string.format("[scrub] repair is local but cloud commit FAILED (%s); retry /scrub_official_loadouts apply",
                    detail))
                printf("[gut_dev:NATIVE_LOADOUTS] #402 cloud commit FAILED fixed=%d broken=%d skipped=%d status=%s",
                    fixed, broken, skipped, detail)
            end
        end

        local requested, commit_id = BackendCommit.request(Managers and Managers.backend, commit_complete)
        if requested then
            mod:echo(string.format("[scrub] repaired %d/%d broken slot(s)%s; cloud commit requested (id=%s)",
                fixed, broken, skipped_suffix, tostring(commit_id)))
            printf("[gut_dev:NATIVE_LOADOUTS] #402 cloud commit REQUESTED id=%s fixed=%d broken=%d skipped=%d",
                tostring(commit_id), fixed, broken, skipped)
        else
            mod:echo(string.format("[scrub] repaired %d/%d locally%s, but cloud commit could not start (%s)",
                fixed, broken, skipped_suffix, tostring(commit_id)))
            printf("[gut_dev:NATIVE_LOADOUTS] #402 cloud commit NOT-STARTED fixed=%d broken=%d skipped=%d reason=%s",
                fixed, broken, skipped, tostring(commit_id))
        end
    else
        mod:echo(string.format("[scrub] found %d broken slot(s) -- see console for ids. To fix: enter the OFFICIAL realm and run /scrub_official_loadouts apply", broken))
    end
end)

-- ==================================================================
-- EXIT-TIME SNAPSHOT BACKSTOP (issues #354, #353, #287, #175, #273).
--
-- The store above is captured on EQUIP EVENTS only (the mirror write hooks + the outer
-- BackendUtils.set_loadout_item capture), each persisted immediately. Any loadout/cosmetic
-- state that reaches the LIVE backend interface through a path that fires NONE of those hooks
-- (an LA-cloned cosmetic dispatch #353, a WT cross-character weapon whose enable/apply lands
-- outside a captured equip #354) is never written to the store and is lost on quit. This is
-- the BACKSTOP: at bounded exit edges (wired from gui_tweaker_dev.lua to StateIngame exit /
-- StateTitleScreen enter / on_unload) it re-reads the live selected loadout and reconciles any
-- diverged slot into the SAME store via the SAME single writer (_persist / _persist_overlay).
-- It is a second capture TRIGGER, never a second store or format. The pure diff arithmetic is
-- _gut_exit_snapshot_core.lua (offline-tested); this half does the engine reads + persist.
--
-- NO NEW HOOK. Pre-flight (2026-07-18): this adds ZERO mod:hook / mod:hook_safe. It reads live
-- values with plain BackendUtils.* function CALLS and writes through the existing store helpers,
-- and is driven by VMF lifecycle callbacks (mod.on_game_state_changed / mod.on_unload) chained
-- in the entry point -- so there is no (Class, method) collision to clear (NON-NEGOTIABLE 8).
--
-- ISOLATION. Before any BackendUtils read, the snapshot asks BackendManager which interface
-- owns that slot and proceeds only when it is the durable `items` interface. A mechanism-owned
-- slot (notably Deus melee/ranged) is a SKIP: its generated backend id is run-local and must
-- never enter the Adventure store (#273). Cosmetics remain eligible in Deus because vanilla
-- maps those slots to `items`. Eligible reads then go through BackendUtils.get_loadout_item_id /
-- get_loadout_item -- the exact readers the hero view uses. These are NOT mirror-read hooks, so
-- calling get_item_from_id underneath here does NOT recurse (the v0.2.173 1 GiB burn was
-- get_item_from_id called from INSIDE the
-- get_character_data hook; an exit edge is not a mirror read -- same safety /gut_loadout_status
-- relies on). Gear reconciles only a value that resolves to a registered item RIGHT NOW
-- (RESOLVE_YES); an unresolved live read is a SKIP, never a clear, so a late-registering
-- synthetic id can never blank a stored id (#375/#387 non-destructive doctrine). Official realm
-- / Versus / non-adventure backend => fully inert. Official cloud data is never written (the
-- store/overlay are modded-only; #175 isolation guarantee is untouched).
-- ==================================================================

-- True only when the durable items interface currently owns `slot_name`. BackendManager's
-- per-slot dispatch is the authoritative boundary; unknown/throwing resolution fails closed.
local function _slot_owned_by_items(slot_name)
    local backend = Managers and Managers.backend
    if not (backend and backend.get_loadout_interface_by_slot and backend.get_interface) then
        return false
    end
    local ok, slot_interface, items_interface = pcall(function()
        return backend:get_loadout_interface_by_slot(slot_name), backend:get_interface("items")
    end)
    return ok and ExitSnapshotCore.slot_owned_by_items(slot_interface, items_interface)
end

-- Read one career+slot's LIVE equipped value, canonicalized to the store's format (gear = raw
-- backend id; cosmetics = override_id or ItemId, the same identity the equip capture stores).
-- Returns nil + a reason to SKIP the slot (foreign owner / no live value / unresolved) -- a nil
-- never overwrites the store.
local function _live_slot_value(career_name, slot_name)
    if not _slot_owned_by_items(slot_name) then
        return nil, "foreign-loadout-interface"
    end
    local BU = rawget(_G, "BackendUtils")
    if COSMETIC_SLOT_SET[slot_name] then
        if not (BU and BU.get_loadout_item) then return nil end
        -- get_loadout_item resolves the live equipped item through the per-slot (LA-aware)
        -- interface; take vanilla's stored identity (override_id or ItemId), matching
        -- Policy.canonical_equip_value. Safe here: exit edge, not a mirror read.
        local ok, item = pcall(BU.get_loadout_item, career_name, slot_name, false)
        if not ok or type(item) ~= "table" then return nil end
        local v = item.override_id or item.ItemId
        return (type(v) == "string" and v ~= "") and v or nil
    end
    if not (BU and BU.get_loadout_item_id) then return nil end
    local ok, backend_id = pcall(BU.get_loadout_item_id, career_name, slot_name, false)
    if not ok or backend_id == nil then return nil end
    -- Gear: only a genuinely-registered live id (RESOLVE_YES). RESOLVE_NO/UNKNOWN => skip so a
    -- transiently-unresolvable live read never overwrites a good stored id (raw tri-state, never
    -- an interface method -- no get_item_from_id recursion).
    if _resolve_item_raw(backend_id) ~= RESOLVE_YES then return nil end
    return backend_id
end

-- Build the live selected-row values for one career over `slots` (nil entries omitted).
local function _build_live_row(career_name, slots)
    local row = {}
    local foreign_slot_reads = 0
    for i = 1, #slots do
        local slot = slots[i]
        local v, reason = _live_slot_value(career_name, slot)
        if v ~= nil then row[slot] = v end
        if reason == "foreign-loadout-interface" then
            foreign_slot_reads = foreign_slot_reads + 1
        end
    end
    return row, foreign_slot_reads
end

-- Resolve the live Adventure mirror at an exit edge (mirror-less `self` here). Returns nil for
-- Versus / non-adventure / backend-down so the snapshot stays inert exactly where the mirror
-- hooks do.
local function _exit_adventure_mirror()
    local ok, mirror = pcall(function() return Managers.backend:get_interface("items")._backend_mirror end)
    if ok and mirror and mirror._characters_data_key == ADVENTURE_DATA_KEY then return mirror end
    return nil
end

-- M.exit_snapshot(edge_name) -> total_diverged, wrote. Idempotent: a clean state diverges 0 and
-- writes nothing. Bounded: <= #careers x #slots live reads, once per edge (never per frame).
function M.exit_snapshot(edge_name)
    local mode = _feature_mode()
    if mode == MODE_OFF then return 0, false end
    local mirror = _exit_adventure_mirror()
    if not mirror then
        printf("[gut:persist] edge=%s diverged=0 written=false (not adventure backend)", tostring(edge_name))
        return 0, false
    end

    local total, wrote, foreign_slot_reads = 0, false, 0
    if mode == MODE_STORE then
        local store = _store()
        local live_by_career = {}
        for career_name in pairs(store) do
            local live, foreign = _build_live_row(career_name, LOADOUT_SLOT_NAMES)
            live_by_career[career_name] = live
            foreign_slot_reads = foreign_slot_reads + foreign
        end
        local diverged, merged_rows, per_career =
            ExitSnapshotCore.reconcile_selected(live_by_career, store, LOADOUT_SLOT_NAMES)
        if diverged > 0 then
            for career_name, merged in pairs(merged_rows) do
                local entry = store[career_name]
                entry.loadouts[entry.selected_index] = merged
                printf("[gut:persist] edge=%s career=%s idx=%s reconciled=%d slots -> store",
                    tostring(edge_name), tostring(career_name), tostring(entry.selected_index),
                    tostring(per_career[career_name]))
            end
            _persist()
            _dirtify()
            wrote = true
        end
        total = diverged
    elseif mode == MODE_READONLY then
        -- #287: gameplay gear is official-read-only; only mod-owned cosmetics + exact CWV
        -- instances live modded-side, in the overlay keyed by the official selected index. Back
        -- up those for careers the overlay already tracks (first-touch is the eager capture's job).
        local overlay = _overlay()
        for career_name, career_ov in pairs(overlay) do
            local idx = _official_index(mirror, career_name, nil)
            local stored_row = career_ov[idx]
            if type(stored_row) == "table" then
                local live, foreign = _build_live_row(career_name, LOADOUT_SLOT_NAMES)
                foreign_slot_reads = foreign_slot_reads + foreign
                local filtered = {}
                for slot, v in pairs(live) do
                    if Policy.readonly_action(slot, v) == "preserve" then filtered[slot] = v end
                end
                local merged, dn = ExitSnapshotCore.diff_row(filtered, stored_row, LOADOUT_SLOT_NAMES)
                if dn > 0 then
                    career_ov[idx] = merged
                    total = total + dn
                    printf("[gut:persist] edge=%s career=%s idx=%s reconciled=%d slots -> readonly overlay",
                        tostring(edge_name), tostring(career_name), tostring(idx), tostring(dn))
                end
            end
        end
        if total > 0 then
            _persist_overlay()
            _dirtify()
            wrote = true
        end
    end

    printf("[gut:persist] edge=%s diverged=%d written=%s foreign_slot_reads=%d",
        tostring(edge_name), total, tostring(wrote), foreign_slot_reads)
    return total, wrote
end

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
    { "BackendInterfaceItemPlayfab", "get_bot_loadout" },
    { "HeroWindowLoadoutSelectionConsole", "_save_bot_equipment" },
    { "HeroWindowLoadoutSelectionConsole", "_populate_context_menu_loadout" },  -- issue #372 preview crash guard
    { "BackendUtils", "set_loadout_item" },  -- TABLE-form, installed deferred (_install_bu_capture)
}

M.rt_checks = {
    { name = "issue954_bot_loadout_snapshot", fn = function()
        local err = BotLoadoutSnapshot.contract_check(Policy, LOADOUT_SLOT_NAMES)
        if err or _adventure_mode() ~= MODE_STORE then return err end
        local ok, iface = pcall(function() return Managers.backend:get_interface("items") end)
        if not ok or not iface then return "runtime items interface unavailable" end
        local native = _native_bot_assignments()
        if type(native) ~= "table" then return "native bot designation store unavailable" end
        return BotLoadoutSnapshot.live_check(
            iface, _store(), Policy, LOADOUT_SLOT_NAMES, native)
    end },
    { name = "issue354_wt_loadout_lifecycle_trace", fn = function()
        if M._issue354_trace_wired ~= true then return "WT loadout lifecycle trace is not wired" end
        if type(WTTraceCore) ~= "table" or type(WTTraceCore.take) ~= "function" then
            return "bounded WT trace core missing"
        end
    end },
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
    { name = "native_loadouts_mod_owned_exempt_readonly", fn = function()
        -- issue #287: in READONLY, cosmetics and exact CWV instances stay editable through the
        -- overlay; ordinary gameplay/talent writes stay blocked. COSMETIC_SLOT_SET must
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
        if not M.readonly_slot_editable("slot_melee", "cwv_es_dual_axes_001") then
            return "CWV melee instance not preserved in readonly"
        end
        if not M.readonly_slot_editable("slot_melee", "cwv_es_dual_maces_100") then
            return "crafted CWV melee instance not preserved in readonly"
        end
        if M.readonly_slot_editable("slot_melee", "D12DB867521442B3") then
            return "official melee instance editable in readonly"
        end
        if M.readonly_slot_editable("talents") then return "talents editable in readonly" end
    end },
    { name = "native_loadouts_la_cosmetic_outer_capture", fn = function()
        -- issue #353: LA-cloned dispatch can miss the concrete mirror hook. The stable
        -- BackendUtils seam must canonicalize all visual slots before store/overlay capture.
        if type(_bu_canonical_value) ~= "function" or type(_capture_bu_equip) ~= "function" then
            return "LA outer capture helpers missing"
        end
        local cases = {
            { "slot_skin", "skin_override", { override_id = "skin_override", ItemId = "skin_item" } },
            { "slot_hat", "hat_item", { ItemId = "hat_item" } },
            { "slot_frame", "frame_item", { ItemId = "frame_item" } },
            { "slot_pose", "pose_item", { ItemId = "pose_item" } },
        }
        for _, c in ipairs(cases) do
            local value = Policy.canonical_equip_value(c[1], "transient_bid", c[3])
            if value ~= c[2] then return c[1] .. " canonicalized to " .. tostring(value) end
        end
        local value = Policy.canonical_equip_value("slot_hat", "transient_bid", nil)
        if value ~= nil then return "unresolved cosmetic retained transient backend id" end
    end },
    { name = "issue1033_default_official_reseed_wired", fn = function()
        if type(M.reset_modded_loadouts) ~= "function" then return "reset owner missing" end
        if type(mod._gut_reset_modded_loadouts) ~= "function" then return "view adapter missing" end
        local store = { mercenary = {} }
        local overlay = { mercenary = {}, zealot = {} }
        local cleared = Policy.clear_modded_loadouts(store, overlay)
        if cleared ~= 2 or next(store) ~= nil or next(overlay) ~= nil then
            return "mod-owned clear policy failed"
        end
        local names = Policy.official_seed_careers({
            _career_data = { zealot = { {} }, mercenary = { {} } },
        })
        if names[1] ~= "mercenary" or names[2] ~= "zealot" or names[3] ~= nil then
            return "official career plan is not deterministic"
        end
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
    { name = "native_loadouts_official_write_chokepoint", fn = function()
        -- issue #402: the SOLE runtime write that diverges official _career_data from its mirror
        -- (and thus reaches the PlayFab cloud) is PlayFabMirrorBase.set_character_data -- it writes
        -- _career_data at playfab_mirror_base.lua:1933 BEFORE delegating to set_career_read_only_data
        -- at :1941, and both weapons AND the portrait FRAME (slot_frame) persist through it. Blocking
        -- these five in modded is the COMPLETE isolation guarantee, so each MUST stay a hooked target
        -- (a dropped hook would re-open the leak). Audit source: the two 2026-07-06 investigations.
        local want = { set_character_data = false, set_career_read_only_data = false,
                       set_loadout_index = false, add_loadout = false, delete_loadout = false }
        for _, t in ipairs(M.HOOK_TARGETS) do
            if t[1] == "PlayFabMirrorAdventure" and want[t[2]] ~= nil then want[t[2]] = true end
        end
        for method, present in pairs(want) do
            if not present then return "official-write choke point not hooked: " .. method end
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
    { name = "native_loadouts_fallback_index_translation", fn = function()
        -- P0 (residual of issues 387/372): the MODE_STORE official gear fallback must NEVER
        -- forward a store-space loadout index into the official read -- vanilla indexes
        -- _career_data[career][index] directly and returns nil for a missing row
        -- (playfab_mirror_base.lua:1909-1919); a nil weapon slot fatals at spawn wield.
        -- Driven synthetically: a stub official read that only has a SELECTED row (nil index).
        if type(M.official_gear_fallback) ~= "function" then return "official_gear_fallback missing" end
        local seen_idx = "never-called"
        local official = function(mirror, career, key, idx)
            seen_idx = idx
            if idx == nil then return "official_selected_" .. tostring(key) end
            return nil   -- any explicit (store-space) index has no official row
        end
        local v = M.official_gear_fallback(official, {}, "__rt_career__", "slot_melee", 5)
        if seen_idx ~= nil then
            return "fallback forwarded index " .. tostring(seen_idx) .. " into the official read (must pass nil = selected row)"
        end
        if v ~= "official_selected_slot_melee" then
            return "fallback did not serve the official selected row: " .. tostring(v)
        end
        -- Weapon-slot last resort: official selected row also nil -> career default loadout row 1.
        local dead = function() return nil end
        local mirror_with_defaults = { get_default_loadouts = function(self, career)
            return { { slot_melee = "__rt_default_melee__" } }
        end }
        v = M.official_gear_fallback(dead, mirror_with_defaults, "__rt_career__", "slot_melee", 5)
        if v ~= "__rt_default_melee__" then
            return "weapon-slot last-resort default loadout not served: " .. tostring(v)
        end
        -- Non-weapon gear slot: nil is a legitimate final answer (no default forcing).
        v = M.official_gear_fallback(dead, mirror_with_defaults, "__rt_career__", "slot_necklace", 5)
        if v ~= nil then return "non-weapon gear slot must be allowed to resolve nil, got " .. tostring(v) end
    end },
    { name = "native_loadouts_trace_throttle_per_change", fn = function()
        -- issue 480: the #387 gear-read trace flooded 20,120 lines in one session because the
        -- cache was keyed (career, slot) only -- interleaved reads across loadout rows
        -- re-emitted on every read. Contract: emit the first occurrence, suppress an identical
        -- repeat, do NOT re-fire on interleaved rows, DO fire once on a genuine per-row
        -- value/source change.
        if type(M.trace_should_emit) ~= "function" then return "trace_should_emit missing" end
        local c, s = "__rt480_career__", "__rt480_slot__"
        -- Re-runnable: seed with a sentinel so a previous /gut_regression_test pass can't leave
        -- the exact first tuple cached.
        M.trace_should_emit(c, s, 1, "__seed__", "__seed__")
        M.trace_should_emit(c, s, 2, "__seed__", "__seed__")
        if not M.trace_should_emit(c, s, 1, "idA", "store-yes") then return "first occurrence suppressed" end
        if M.trace_should_emit(c, s, 1, "idA", "store-yes") then return "identical repeat not throttled (the #480 flood)" end
        if not M.trace_should_emit(c, s, 2, "idB", "store-yes") then return "first read of a different row suppressed" end
        if M.trace_should_emit(c, s, 1, "idA", "store-yes") then return "interleaved row re-read re-emitted (the exact #480 flood shape)" end
        if not M.trace_should_emit(c, s, 1, "idC", "store-yes") then return "genuine value change suppressed" end
        if not M.trace_should_emit(c, s, 1, "idC", "official-fallback-resolve-no") then return "genuine source change suppressed" end
    end },
    { name = "native_loadouts_seed_repair_predicate", fn = function()
        -- issues #375/#402: the self-heal seed classifies a row as corrupt-partial when
        -- ANY canonical loadout slot is missing. The old weapon-only predicate let a row
        -- keep melee/ranged while losing outfit/hat/frame/pose/accessory state, which made
        -- realm bleed look "mostly fixed" while visual slots still rotted invisibly.
        if type(_row_is_corrupt_partial) ~= "function" then return "_row_is_corrupt_partial missing" end
        if not _row_is_corrupt_partial(nil) then return "nil row must be corrupt-partial" end
        local full = {}
        for _, slot in ipairs(LOADOUT_SLOT_NAMES) do full[slot] = "__rt_" .. slot end
        if _row_is_corrupt_partial(full) then return "complete row classified corrupt-partial" end
        for _, slot in ipairs(LOADOUT_SLOT_NAMES) do
            local partial = {}
            for _, s in ipairs(LOADOUT_SLOT_NAMES) do partial[s] = "__rt_" .. s end
            partial[slot] = nil
            if not _row_is_corrupt_partial(partial) then
                return "row missing " .. slot .. " must be corrupt-partial"
            end
        end
        if type(_repair_missing_loadout_slots) ~= "function" then return "_repair_missing_loadout_slots missing" end
        local entry = { loadouts = { { slot_melee = "m", slot_ranged = "r" } } }
        local fixed = _repair_missing_loadout_slots(entry, {
            {
                slot_melee = "off_m", slot_ranged = "off_r", slot_skin = "skin", slot_hat = "hat",
                slot_necklace = "neck", slot_ring = "ring", slot_trinket_1 = "trinket",
                slot_frame = "frame", slot_pose = "pose",
            },
        })
        if fixed ~= 7 then return "slot migration repaired " .. tostring(fixed) .. " slots, expected 7" end
        if entry.loadouts[1].slot_melee ~= "m" or entry.loadouts[1].slot_ranged ~= "r" then
            return "slot migration clobbered existing weapons"
        end
        if entry.loadouts[1].slot_frame ~= "frame" or entry.loadouts[1].slot_skin ~= "skin" then
            return "slot migration did not fill visual slots"
        end
        -- Every weapon slot must be a gear slot (repair reads gear from official).
        for slot in pairs(WEAPON_SLOT_SET) do
            if not GEAR_SLOT_SET[slot] then return "weapon slot not in gear set: " .. slot end
        end
    end },
    { name = "issue402_official_scrub_all_slots", fn = function()
        -- issue #402: official repair must cover the SAME slot contract as the modded store,
        -- not the old weapon/frame subset, and must treat nil visual slots as repairable damage.
        if type(_slot_resolves) ~= "function" then return "_slot_resolves missing" end
        if _slot_resolves("slot_frame", nil) then return "nil frame resolved as healthy" end
        if not rawget(_G, "ItemMasterList") then _G.ItemMasterList = {} end
        ItemMasterList.__rt_frame_key = { key = "__rt_frame_key" }
        local cosmetic_ok = _slot_resolves("slot_frame", "__rt_frame_key")
        local gear_bad = _slot_resolves("slot_necklace", "__rt_frame_key")
        ItemMasterList.__rt_frame_key = nil
        if not cosmetic_ok then
            return "cosmetic ItemMasterList key did not resolve"
        end
        if gear_bad then
            return "gear slot resolved through cosmetic ItemMasterList fallback"
        end
    end },
    { name = "native_loadouts_exit_snapshot_backstop", fn = function()
        -- issues #354/#353/#287/#175: the exit-time backstop must be wired, must reuse the pure
        -- core, and must be non-destructive + idempotent (a nil live value never clears a stored
        -- slot; a clean state diverges 0). The recursion/isolation safety is structural (exit
        -- edge, RESOLVE_YES gate, raw reads) and covered by the offline harness.
        if type(M.exit_snapshot) ~= "function" then return "exit_snapshot not wired" end
        if type(ExitSnapshotCore) ~= "table" or type(ExitSnapshotCore.diff_row) ~= "function"
            or type(ExitSnapshotCore.reconcile_selected) ~= "function"
            or type(ExitSnapshotCore.slot_owned_by_items) ~= "function" then
            return "exit snapshot pure core missing"
        end
        local items_interface, deus_interface = {}, {}
        if not ExitSnapshotCore.slot_owned_by_items(items_interface, items_interface) then
            return "items-owned slot rejected"
        end
        if ExitSnapshotCore.slot_owned_by_items(deus_interface, items_interface) then
            return "foreign mechanism-owned slot accepted"
        end
        local slots = { "slot_melee", "slot_ranged", "slot_hat" }
        -- nil live value must NOT clear a stored slot; a differing live value overwrites.
        local merged, dn = ExitSnapshotCore.diff_row(
            { slot_melee = "live_melee" }, { slot_melee = "old_melee", slot_ranged = "keep_r" }, slots)
        if dn ~= 1 then return "diff_row diverged count wrong: " .. tostring(dn) end
        if merged.slot_melee ~= "live_melee" then return "diverged slot not overwritten" end
        if merged.slot_ranged ~= "keep_r" then return "unrelated stored slot not preserved" end
        -- clean state diverges 0 and returns no merged row (idempotent, no write).
        local m2, d2 = ExitSnapshotCore.diff_row({ slot_melee = "live_melee" }, merged, slots)
        if d2 ~= 0 or m2 ~= nil then return "clean diff not idempotent" end
    end },
}

printf("[gut_dev:NATIVE_LOADOUTS] module loaded (%s) modded_realm=%s hooks=%d",
    MARKER, tostring(_in_modded_realm()), #M.HOOK_TARGETS)

return M
