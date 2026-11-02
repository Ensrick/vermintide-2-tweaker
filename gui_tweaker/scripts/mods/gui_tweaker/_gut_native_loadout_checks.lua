-- _gut_native_loadout_checks.lua -- native-loadout ordered runtime contracts.
--
-- Builds the existing checks against the real private native-owner capabilities.
-- It neither installs hooks nor creates a store. Missing dependencies fail loudly;
-- live checks keep their late backend reads and pure checks keep detached values.
--
-- Owned by: _gut_native_loadouts.lua. Consumed via: one private mod:dofile/create.
local Checks = {}

function Checks.create(mod, deps)
    assert(type(deps) == "table", "native check dependencies required")
    local M = assert(type(deps.native) == "table" and deps.native, "native table required")
    local Policy = assert(type(deps.policy) == "table" and deps.policy, "policy table required")
    local WTTraceCore = assert(type(deps.wt_trace_core) == "table" and deps.wt_trace_core, "wt_trace_core table required")
    local ExitSnapshotCore = assert(type(deps.exit_snapshot_core) == "table" and deps.exit_snapshot_core, "exit_snapshot_core table required")
    local LoadoutLifecycle = assert(type(deps.loadout_lifecycle) == "table" and deps.loadout_lifecycle, "loadout_lifecycle table required")
    local BotLoadoutSnapshot = assert(type(deps.bot_loadout_snapshot) == "table" and deps.bot_loadout_snapshot, "bot_loadout_snapshot table required")
    local BootGuard = assert(type(deps.boot_guard) == "table" and deps.boot_guard, "boot_guard table required")
    local MARKER = assert(type(deps.marker) == "string" and deps.marker, "marker string required")
    local LOADOUT_SLOT_NAMES = assert(type(deps.loadout_slot_names) == "table" and deps.loadout_slot_names, "loadout_slot_names table required")
    local GEAR_SLOT_NAMES = assert(type(deps.gear_slot_names) == "table" and deps.gear_slot_names, "gear_slot_names table required")
    local GEAR_SLOT_SET = assert(type(deps.gear_slot_set) == "table" and deps.gear_slot_set, "gear_slot_set table required")
    local COSMETIC_SLOT_SET = assert(type(deps.cosmetic_slot_set) == "table" and deps.cosmetic_slot_set, "cosmetic_slot_set table required")
    local WEAPON_SLOT_SET = assert(type(deps.weapon_slot_set) == "table" and deps.weapon_slot_set, "weapon_slot_set table required")
    local MODE_OFF = assert(type(deps.mode_off) == "string" and deps.mode_off, "mode_off string required")
    local MODE_STORE = assert(type(deps.mode_store) == "string" and deps.mode_store, "mode_store string required")
    local MODE_READONLY = assert(type(deps.mode_readonly) == "string" and deps.mode_readonly, "mode_readonly string required")
    local RESOLVE_NO = assert(type(deps.resolve_no) == "number" and deps.resolve_no, "resolve_no number required")
    local RESOLVE_UNKNOWN = assert(type(deps.resolve_unknown) == "number" and deps.resolve_unknown, "resolve_unknown number required")
    local _adventure_mode = assert(type(deps.adventure_mode) == "function" and deps.adventure_mode, "adventure_mode function required")
    local _store = assert(type(deps.store) == "function" and deps.store, "store function required")
    local _native_bot_assignments = assert(type(deps.native_bot_assignments) == "function" and deps.native_bot_assignments, "native_bot_assignments function required")
    local _overlay = assert(type(deps.overlay) == "function" and deps.overlay, "overlay function required")
    local _overlay_get = assert(type(deps.overlay_get) == "function" and deps.overlay_get, "overlay_get function required")
    local _overlay_set = assert(type(deps.overlay_set) == "function" and deps.overlay_set, "overlay_set function required")
    local _slot_owned_by_items = assert(type(deps.slot_owned_by_items) == "function" and deps.slot_owned_by_items, "slot_owned_by_items function required")
    local _resolve_item_raw = assert(type(deps.resolve_item_raw) == "function" and deps.resolve_item_raw, "resolve_item_raw function required")
    local _row_is_corrupt_partial = assert(type(deps.row_is_corrupt_partial) == "function" and deps.row_is_corrupt_partial, "row_is_corrupt_partial function required")
    local _repair_missing_loadout_slots = assert(type(deps.repair_missing_loadout_slots) == "function" and deps.repair_missing_loadout_slots, "repair_missing_loadout_slots function required")
    local _slot_resolves = assert(type(deps.slot_resolves) == "function" and deps.slot_resolves, "slot_resolves function required")
    local _in_modded_realm = assert(type(deps.in_modded_realm) == "function" and deps.in_modded_realm, "in_modded_realm function required")

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
        { name = "issue353_outer_capture_transaction", fn = function()
            -- Issue #353: execute the same owner called by the live BackendUtils hook. This
            -- deliberately tests the whole decision/canonicalization/write transaction rather
            -- than merely calling the serializer that the hook is expected to use.
            if type(LoadoutLifecycle) ~= "table" or type(LoadoutLifecycle.capture_equip) ~= "function" then
                return "outer capture transaction owner missing"
            end
            local cases = {
                { "slot_skin", "skin_override", { override_id = "skin_override", ItemId = "skin_item" } },
                { "slot_hat", "hat_item", { ItemId = "hat_item" } },
                { "slot_frame", "frame_item", { ItemId = "frame_item" } },
                { "slot_pose", "pose_item", { ItemId = "pose_item" } },
            }
            local writes = {}
            local function run(mode, slot, item)
                return LoadoutLifecycle.capture_equip({
                    mode = mode, mode_off = MODE_OFF, career_name = "es_mercenary",
                    backend_id = "transient_bid", slot_name = slot, is_loadout_slot = true,
                    capture_slot_durable = Policy.capture_slot_durable,
                    slot_owned_by_items = function() return true end,
                    get_mirror = function() return {} end,
                    canonical_value = function(backend_id, slot_name)
                        return Policy.canonical_equip_value(slot_name, backend_id, item)
                    end,
                    write = function(write_mode, _, career, slot_name, value, source)
                        writes[#writes + 1] = { write_mode, career, slot_name, value, source }
                    end,
                })
            end
            for _, mode in ipairs({ MODE_STORE, MODE_READONLY }) do
                for _, c in ipairs(cases) do
                    local result, source = run(mode, c[1], c[3])
                    local write = writes[#writes]
                    if result ~= "captured" then return c[1] .. " transaction: " .. tostring(result) end
                    if not write or write[1] ~= mode or write[2] ~= "es_mercenary"
                        or write[3] ~= c[1] or write[4] ~= c[2] then
                        return c[1] .. " transaction wrote the wrong canonical identity"
                    end
                    if source == nil then return c[1] .. " transaction lost canonical source" end
                end
            end
            local before = #writes
            local unresolved = run(MODE_STORE, "slot_hat", nil)
            if unresolved ~= "unresolved" or #writes ~= before then
                return "unresolved cosmetic did not fail closed"
            end
            local foreign = LoadoutLifecycle.capture_equip({
                mode = MODE_STORE, mode_off = MODE_OFF, career_name = "es_mercenary",
                backend_id = "deus_run_local", slot_name = "slot_melee", is_loadout_slot = true,
                capture_slot_durable = Policy.capture_slot_durable,
                slot_owned_by_items = function() return false end,
                get_mirror = function() return {} end,
                canonical_value = function(id) return id, "backend_id" end,
                write = function() writes[#writes + 1] = {} end,
            })
            if foreign ~= "foreign-owner" or #writes ~= before then
                return "foreign gear identity did not fail closed"
            end
        end },
        { name = "issue1033_default_official_reseed_wired", fn = function()
            if type(M.reset_modded_loadouts) ~= "function" then return "reset owner missing" end
            if type(mod._gut_reset_modded_loadouts) ~= "function" then return "view adapter missing" end
            -- Presentation half (#1033): the reconcile owner must be published on the mod
            -- namespace so the reset's lazy lookup resolves at runtime.
            local presentation = mod._gut_reset_presentation
            if type(presentation) ~= "table" or type(presentation.reconcile) ~= "function"
                or type(presentation.capture_before) ~= "function" then
                return "presentation reconcile owner not published (mod._gut_reset_presentation)"
            end
            local store = { mercenary = {} }
            local overlay = { mercenary = {}, zealot = {} }
            local cleared = Policy.clear_modded_loadouts(store, overlay)
            if cleared ~= 2 or next(store) ~= nil or next(overlay) ~= nil then
                return "mod-owned clear policy failed"
            end
            -- #954 boundary: the reset wipes modded loadout data but must never drop the
            -- user's bot designation (index + detached snapshot + one-time import marker).
            local store2 = { mercenary = {
                selected_index = 2, _seeded = true, _slot_integrity_v2 = true,
                bot_index = 2, bot_loadout = { slot_melee = "bot" },
                _bot_designation_snapshot_v2 = true,
                loadouts = { { slot_melee = "a" }, { slot_melee = "bot" } },
            } }
            Policy.clear_modded_loadouts(store2, { mercenary = {} })
            local kept = store2.mercenary
            if not (kept and kept.bot_index == 2 and kept._bot_designation_snapshot_v2 == true
                and type(kept.bot_loadout) == "table" and next(kept.loadouts) == nil
                and kept._seeded == nil) then
                return "reset dropped or over-preserved the #954 bot designation"
            end
            local names = Policy.official_seed_careers({
                _career_data = { zealot = { {} }, mercenary = { {} } },
            })
            if names[1] ~= "mercenary" or names[2] ~= "zealot" or names[3] ~= nil then
                return "official career plan is not deterministic"
            end
        end },
        { name = "issue273_capture_owner_gate", fn = function()
            -- Capture side of the #273 owner invariant: gear capture fails closed unless the
            -- durable items interface owns the slot; cosmetics stay unconditionally eligible.
            if type(Policy.capture_slot_durable) ~= "function" then return "capture owner gate missing" end
            if Policy.capture_slot_durable("slot_melee", false) then return "gear capture not fail-closed" end
            if Policy.capture_slot_durable("slot_ranged", nil) then return "gear capture not fail-closed (nil owner)" end
            if not Policy.capture_slot_durable("slot_melee", true) then return "owned gear capture rejected" end
            if not Policy.capture_slot_durable("slot_hat", false) then return "cosmetic capture regressed" end
            if type(_slot_owned_by_items) ~= "function" then return "slot owner resolver missing" end
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
            -- issue #402: ordinary equips funnel through the five write methods below, but boot
            -- also owns three direct official-data writers plus the two requests feeding them.
            -- The complete containment contract is therefore all ten concrete Adventure seams.
            local want = { set_character_data = false, set_career_read_only_data = false,
                           set_loadout_index = false, add_loadout = false, delete_loadout = false,
                           _set_inital_career_data = false, _fix_career_data = false,
                           fix_career_data_request_cb = false, _verify_career_loadouts = false,
                           verify_career_loadouts_cb = false }
            for _, t in ipairs(M.HOOK_TARGETS) do
                if t[1] == "PlayFabMirrorAdventure" and want[t[2]] ~= nil then want[t[2]] = true end
            end
            for method, present in pairs(want) do
                if not present then return "official write/boot boundary not hooked: " .. method end
            end
            if type(BootGuard.in_modded_realm) ~= "function" or type(BootGuard.active) ~= "function" then
                return "official boot guard realm owner missing"
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
            -- a slot vanilla can never leave empty is missing. Unequippable accessory slots
            -- (jewelry) are exempt everywhere: a deliberate unequip is indistinguishable
            -- from loss, so the repair passes preserve it (#375 audit fix 2026-08-15).
            if type(_row_is_corrupt_partial) ~= "function" then return "_row_is_corrupt_partial missing" end
            if not _row_is_corrupt_partial(nil) then return "nil row must be corrupt-partial" end
            local full = {}
            for _, slot in ipairs(LOADOUT_SLOT_NAMES) do full[slot] = "__rt_" .. slot end
            if _row_is_corrupt_partial(full) then return "complete row classified corrupt-partial" end
            for _, slot in ipairs(LOADOUT_SLOT_NAMES) do
                local partial = {}
                for _, s in ipairs(LOADOUT_SLOT_NAMES) do partial[s] = "__rt_" .. s end
                partial[slot] = nil
                local is_corrupt = _row_is_corrupt_partial(partial)
                if Policy.is_unequippable_slot(slot) then
                    if is_corrupt then
                        return "row missing deliberately-emptiable " .. slot .. " must stay HEALTHY"
                    end
                elseif not is_corrupt then
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
            if fixed ~= 4 then return "slot migration repaired " .. tostring(fixed) .. " slots, expected 4 (jewelry exempt)" end
            if entry.loadouts[1].slot_melee ~= "m" or entry.loadouts[1].slot_ranged ~= "r" then
                return "slot migration clobbered existing weapons"
            end
            if entry.loadouts[1].slot_frame ~= "frame" or entry.loadouts[1].slot_skin ~= "skin" then
                return "slot migration did not fill visual slots"
            end
            if entry.loadouts[1].slot_necklace ~= nil or entry.loadouts[1].slot_ring ~= nil
                or entry.loadouts[1].slot_trinket_1 ~= nil then
                return "slot migration refilled a deliberately-emptiable accessory slot"
            end
            -- Every weapon slot must be a gear slot (repair reads gear from official).
            for slot in pairs(WEAPON_SLOT_SET) do
                if not GEAR_SLOT_SET[slot] then return "weapon slot not in gear set: " .. slot end
            end
        end },
        { name = "issue375_deliberate_empty_slots_preserved", fn = function()
            -- #375 audit contradiction: the one-time _slot_integrity_v2 pass refilled
            -- deliberately emptied accessory slots contrary to its own doctrine. Contract:
            -- deliberately-emptied jewelry stays empty on EVERY repair path; genuinely
            -- missing (never-emptiable) slots still repair.
            local set = Policy.UNEQUIPPABLE_SLOTS
            if type(set) ~= "table" or not (set.slot_necklace and set.slot_ring and set.slot_trinket_1) then
                return "unequippable accessory set wrong"
            end
            for slot in pairs(set) do
                if not GEAR_SLOT_SET[slot] then return "unequippable slot outside gear set: " .. slot end
                if WEAPON_SLOT_SET[slot] then return "weapon slot marked unequippable: " .. slot end
                if COSMETIC_SLOT_SET[slot] then return "cosmetic slot marked unequippable: " .. slot end
            end
            local official = {
                slot_melee = "off_m", slot_ranged = "off_r", slot_skin = "off_skin",
                slot_hat = "off_hat", slot_necklace = "off_neck", slot_ring = "off_ring",
                slot_trinket_1 = "off_trink", slot_frame = "off_frame", slot_pose = "off_pose",
                talents = "1,2,3,4,5,6",
            }
            -- Healthy row with a deliberate ring unequip: no path may refill it.
            local edited = {}
            for _, s in ipairs(LOADOUT_SLOT_NAMES) do edited[s] = "own_" .. s end
            edited.slot_ring = nil
            if Policy.row_is_corrupt_partial(edited, LOADOUT_SLOT_NAMES) then
                return "deliberate ring unequip classified corrupt"
            end
            local entry = { loadouts = { edited } }
            Policy.repair_missing_loadout_slots(entry, { official }, LOADOUT_SLOT_NAMES)
            if edited.slot_ring ~= nil then return "migration refilled a deliberate ring unequip" end
            -- Corrupt row (lost its melee): never-emptiable holes repair, jewelry holes do not.
            local corrupt = { slot_ranged = "own_r", slot_necklace = nil, slot_hat = nil }
            if not Policy.row_is_corrupt_partial(corrupt, LOADOUT_SLOT_NAMES) then
                return "row missing slot_melee must be corrupt"
            end
            local filled = Policy.repair_corrupt_row(corrupt, official)
            if corrupt.slot_melee ~= "off_m" or corrupt.slot_hat ~= "off_hat" then
                return "corrupt-row refill skipped a genuinely-missing slot"
            end
            if corrupt.talents ~= "1,2,3,4,5,6" then return "corrupt-row refill dropped talents" end
            if corrupt.slot_necklace ~= nil or corrupt.slot_ring ~= nil or corrupt.slot_trinket_1 ~= nil then
                return "corrupt-row refill touched an accessory slot"
            end
            if corrupt.slot_ranged ~= "own_r" then return "corrupt-row refill clobbered an owned slot" end
            if filled < 5 then return "corrupt-row refill count wrong: " .. tostring(filled) end
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
        { name = "issue354_exit_snapshot_lifecycle_edges", fn = function()
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
            -- Execute the same callback owner installed by gui_tweaker.lua. All three
            -- persistence edges must fire once, unrelated transitions never fire, previous
            -- callbacks remain chained, and a failing snapshot must be contained/reported.
            if type(LoadoutLifecycle.bind_snapshot_edges) ~= "function" then
                return "snapshot lifecycle owner missing"
            end
            local edges, previous, errors = {}, 0, {}
            local on_state, on_unload = LoadoutLifecycle.bind_snapshot_edges({
                snapshot = function(edge) edges[#edges + 1] = edge end,
                previous_state = function() previous = previous + 1 end,
                previous_unload = function() previous = previous + 1 end,
                report_error = function(edge) errors[#errors + 1] = edge end,
            })
            on_state("enter", "StateIngame")
            on_state("exit", "StateIngame")
            on_state("enter", "StateTitleScreen")
            on_unload()
            if table.concat(edges, ",") ~= "ingame_exit,title_enter,unload" then
                return "snapshot lifecycle edges wrong: " .. table.concat(edges, ",")
            end
            if previous ~= 4 then return "previous lifecycle callbacks not chained" end
            if #errors ~= 0 then return "healthy lifecycle reported an error" end
            local reported
            local failing = LoadoutLifecycle.bind_snapshot_edges({
                snapshot = function() error("snapshot-failure") end,
                report_error = function(edge) reported = edge end,
            })
            local ok = pcall(failing, "exit", "StateIngame")
            if not ok or reported ~= "ingame_exit" then
                return "snapshot failure was not contained and reported"
            end
        end },
    }

    for _, check in ipairs(BootGuard.regression_checks(M, MARKER, _in_modded_realm)) do
        M.rt_checks[#M.rt_checks + 1] = check
    end

    return M.rt_checks
end

return Checks
