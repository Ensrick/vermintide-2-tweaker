-- _cim_modded_loadout_owner.lua -- CIM-dev persisted modded-loadout owner.
--
-- RESPONSIBILITY
-- Owns the complete "remember which modded item the player had equipped on each
-- (career, loadout index, slot), and put it back next session" path, and nothing
-- else:
--   * the INDEX-AWARE persisted store `career -> loadout_index -> slot -> bid`
--     (the v0.8.13-dev bot-loadout fix) and its save/load helpers
--   * the one-shot flat -> indexed migration plus the mirror-ready timing gate
--     that keeps it from homing every entry under index 1 at boot
--   * the stale-entry purge for bids no longer backed by a cim craft or a
--     `cwv_` id
--   * CAPTURE: the `BackendInterfaceItemPlayfab.set_loadout_item` hook_safe and
--     the deferred `BackendUtils.set_loadout_item` table hook that catches menu
--     equips dispatched through a Loremaster's Armoury cloned interface (#22)
--   * RESTORE: `_restore_modded_loadout`, the live-avatar re-equip, the #562
--     auto-equip-on-craft helpers, and the sibling-mod restore-callback list
--     cosmetics_tweaker registers into
--   * the three chat commands registered at this seam
--
-- The whole path is dormant in production: the master gate
-- `persist_modded_loadouts` is force-reset OFF at load in the entry (see the
-- "MASTER loadout gate" banner there) and injected here as
-- `ctx.persist_loadouts_enabled`. The machinery is kept live so the regression
-- sandbox can exercise the round trip. This owner does not decide the gate; it
-- only reads it, exactly as the entry did.
--
-- EXTRACTED VERBATIM from crafting_in_modded_dev.lua entry lines 1232-2004
-- (723 nonblank), re-indented one level with exactly ONE substantive change,
-- called out below. `mod:dofile` is not a singleton, so the entry calls the
-- installer EXACTLY once, at the precise point this block previously executed
-- (immediately after `mod._cim_rpc_loadout_guard_installed = true`, immediately
-- before the Athanor UI-hook section). Hook-registration order, command
-- registration order, and the load-time `_modded_loadout_load()` call all keep
-- their original timing.
--
-- THE ONE NON-VERBATIM LINE
-- `_modded_loadout_purge_stale` read the entry-local `_forged_weapons` table
-- directly. That local is REASSIGNED (`_forge_load` rebinds it to a fresh table
-- on every backend `_create_interfaces` pass), so a captured reference would go
-- stale and the purge would classify every live craft as unbacked. The read is
-- therefore routed through the injected `ctx.get_forged_weapons` accessor --
-- the same accessor convention `_cim_command_owner` and `_cim_regression_checks`
-- already use for this store, and it keeps the flat `mod._cim_*` public surface
-- from widening.
--
-- PUBLIC SURFACE (unchanged names, unchanged shapes)
--   mod._cim_clear_modded_loadout_for_bids / _cim_clear_modded_loadout_for_bid
--   mod._cim_register_restore_callback
--   mod._cim_auto_equip_crafted_weapon / _cim_auto_equip_slot_type
--   mod._cim_backendutils_capture_installed
-- Returned to the entry (which keeps the forward-declared `_restore_modded_loadout`
-- local and binds the rest at the seam): restore_modded_loadout,
-- install_backendutils_capture, modded_loadout_save, modded_loadout_load,
-- get_modded_loadout, set_modded_loadout. The last two exist because
-- `_cim_regression_checks` swaps the whole store table and reloads into it.
--
-- COMPOSES WITH, DOES NOT OVERLAP, THE OTHER cim OWNERS
-- This is the only cim code that hooks `set_loadout_item` on either surface.
--   * `_cim_weave_economy` fakes Weaves PROGRESSION reads while cim owns the
--     Athanor; it never touches the persisted store (its own tests assert zero
--     `_modded_loadout` / `set_loadout_item` occurrences).
--   * `_cim_forge_preview_owner` / `_cim_forge_ui_owner` / `_cim_forge_picker_owner`
--     own Athanor view lifecycle and widget state; the on_enter crash-guard
--     cascade lives entirely outside this file and is untouched.
--   * `_cim_command_owner` and `_cim_regression_checks` consume this store
--     through the accessors the entry passes them, which now resolve here.
-- Deliberately NOT included: the #278/#371 cross-peer wire-safety layer
-- (`_cim_wire_safe_rarity`, the `cim_modded_slot` RPC, the
-- `PlayerManager.rpc_sync_loadout_slot` guard) stays in the entry above this
-- seam -- it is sender-side crash safety, must never be gated on this owner's
-- persistence toggle, and is pinned there by qa/rt_textual_invariants.psd1.
--
-- `cim_craft_standard` is an ORDER-PRESERVING PASSENGER: it opens the standard
-- crafting bench, not the loadout store, but it was registered between
-- `cim_restore_loadout` and `cim_dump_loadout`. Moving it with them keeps the
-- three command registrations in their original order; splitting it out would
-- reorder them. It dispatches through `mod.open_standard_crafting` at call
-- time, so it is unaffected by the seam.

local function install(ctx)
    assert(type(ctx) == "table", "CIM modded loadout owner requires context")

    local mod = assert(ctx.mod, "CIM modded loadout owner requires mod")

    local state = mod._cim_modded_loadout_owner_state
    if not state then
        state = {}
        mod._cim_modded_loadout_owner_state = state
    end

    -- Refresh the injected dependencies BEFORE the install guard. A development
    -- reload re-executes the entry, which builds fresh closures over the
    -- reloaded `_forged_weapons`; holding the first install's closures would
    -- point the stale purge at the pre-reload store. Same ordering the sibling
    -- owners use (_cim_weave_economy, _cim_forge_picker_owner).
    state.persist_loadouts_enabled = assert(ctx.persist_loadouts_enabled,
        "CIM modded loadout owner requires the persistence gate")
    state.get_forged_weapons = assert(ctx.get_forged_weapons,
        "CIM modded loadout owner requires the forged-weapons accessor")

    -- mod:dofile is not a singleton. A second install would re-register both
    -- capture hooks and all three commands, so hand back the first install's
    -- exports instead. Nothing below this guard runs twice.
    if state.exports then
        return state.exports
    end

    -- One indirection so the moved body keeps its original call text while the
    -- resolvers above stay replaceable across a reload.
    local function _persist_loadouts_enabled()
        return state.persist_loadouts_enabled()
    end
    local function _get_forged_weapons()
        return state.get_forged_weapons()
    end

    -- Mirrors the entry's own forward declaration. The definition sits mid-body;
    -- the export below hands it back to the entry local that the
    -- BackendManagerPlayFab._create_interfaces hook and mod.update close over.
    local _restore_modded_loadout

    -- ============================================================
    -- Modded inventory filter + loadout restore
    -- ============================================================
    -- The mod-realm view: hide vanilla weapons from the inventory grid (toggleable),
    -- and remember the last modded item the player equipped on each (career, slot)
    -- so that switching to vanilla and back doesn't wipe their modded loadout.


    -- ============================================================
    -- Persisted modded-loadout store — INDEX-AWARE schema (v0.8.13-dev)
    -- ============================================================
    -- Schema: _modded_loadout[career_name][loadout_index][slot_name] = backend_id.
    --
    -- WHY the index dimension exists (the v0.8.13-dev bot-loadout fix):
    -- VT2 stores gear as PlayFabMirrorBase._career_data[career][loadout_index][slot].
    -- `_career_loadouts[career]` is the player's SELECTED (active) index;
    -- `PlayerData.loadout_selection.bot_equipment[career]` is a bot's DESIGNATED
    -- index. Vanilla bot equip READS each bot's gear from its DESIGNATED index
    -- (backend_interface_item_playfab.lua:150 →
    -- get_character_data(career, slot, bot_loadout_index)).
    --
    -- The pre-0.8.13 store was FLAT (career -> slot -> bid) with no index. Both
    -- capture hooks dropped `optional_loadout_index`, and restore wrote with no
    -- index arg, so set_loadout_item/set_character_data DEFAULTED every write to
    -- the SELECTED index (playfab_mirror_base.lua:1930). Result: a bot's
    -- designated-index modded gear was never persisted/restored to that index ->
    -- bots cloned the host's selected loadout; and the player's modded items got
    -- conflated across loadout switches. Adding the index dimension fixes both:
    -- captures store the bid under the index it was actually written to, and
    -- restore stamps each saved item back into ITS index.
    local _modded_loadout = {}

    -- Resolve the LIVE selected loadout index for a career from the backend mirror,
    -- LA-safe (same _backend_mirror access pattern used at ~:549). Returns an
    -- integer index, or `fallback` (default 1) when the mirror / career isn't
    -- available yet. Never throws — capture/restore call this at timing-fragile
    -- moments where the mirror may be nil.
    local function _resolve_selected_index(career_name, fallback)
        fallback = fallback or 1
        if not career_name then return fallback end
        local items_iface = Managers.backend and Managers.backend.get_interface
            and Managers.backend:get_interface("items")
        local mirror = items_iface and items_iface._backend_mirror
        if not mirror then return fallback end
        -- Prefer the direct table read; fall back to the public accessor.
        local ok, idx = pcall(function()
            if mirror._career_loadouts then
                return mirror._career_loadouts[career_name]
            end
        end)
        if ok and type(idx) == "number" then return idx end
        if mirror.get_career_loadouts then
            local ok2, sel = pcall(mirror.get_career_loadouts, mirror, career_name)
            if ok2 and type(sel) == "number" then return sel end
        end
        return fallback
    end

    -- Detect whether a career's stored value is the OLD flat shape
    -- (slot_name -> bid string) vs the NEW indexed shape (index -> {slot -> bid}).
    -- Heuristic, type-safe against partial/corrupt data:
    --   * indexed: at least one entry keyed by a NUMBER whose value is a table.
    --   * flat:    at least one entry keyed by a STRING (slot name) whose value is
    --              a string bid (or nil).
    -- A career table with only number->table entries is indexed; anything carrying
    -- a string-keyed string value is treated as flat and migrated.
    local function _career_value_is_flat(career_tbl)
        if type(career_tbl) ~= "table" then return false end
        for k, v in pairs(career_tbl) do
            if type(k) == "string" then
                -- A slot-name key. Flat shape (value should be a bid string, but
                -- even a stray non-table here means this isn't the indexed shape).
                return true
            elseif type(k) == "number" and type(v) ~= "table" then
                -- A numeric key pointing at a non-table = corrupt; not valid
                -- indexed data. Treat as flat so migration re-homes it safely.
                return true
            end
        end
        return false
    end

    -- v0.7.67-dev (issue #22): tracks the bid we last re-equipped onto the LIVE keep
    -- avatar per "career/slot", so the repeated restore passes (1.0s + 3.0s deferred)
    -- don't destroy+recreate the same weapon unit every pass (visible flicker). Keyed
    -- "career/slot" → bid. Cleared for a slot when the equip-capture hook sees a
    -- change there, so a later restore re-applies if needed.
    local _reequipped = {}

    -- True only while _restore_modded_loadout is replaying saved state. The capture
    -- path checks this so restore's OWN set_loadout_item writes don't: (a) re-process
    -- into _modded_loadout (and mutate it mid-pairs()-iteration), nor (b) pre-mark
    -- _reequipped and starve the live re-equip (the v0.7.67 self-defeat bug that left
    -- [reequip] empty).
    local _restoring = false

    local function _modded_loadout_save()
        mod:set("modded_loadout", _modded_loadout)
    end

    -- One-time, NO-DATA-LOSS migration from the old FLAT schema
    -- (career -> slot -> bid) to the indexed schema
    -- (career -> index -> slot -> bid). Existing users' saved data is flat; we
    -- re-home each flat entry under the career's REAL (live selected) loadout index.
    -- That's the safest target: pre-0.8.13 cim only ever stamped the SELECTED index,
    -- so the flat entries WERE the selected-index gear — assigning them there
    -- preserves the exact prior behavior for the player's active loadout while
    -- unlocking per-index storage going forward.
    --
    -- ⚠ TIMING (v0.8.14-dev fix for the v0.8.13-dev blocker): this MUST run at a
    -- MIRROR-READY moment, NOT at script-eval / boot. `_resolve_selected_index`
    -- only returns the real per-career selected index once the backend mirror
    -- exists; at boot it always falls back to 1, which would home EVERY migrated
    -- flat entry under index 1. For a player whose actual selected index is not 1,
    -- that re-homed their saved gear to the wrong loadout and the keep avatar
    -- re-equipped vanilla (`_reequip_live_avatar` reads the live selected index and
    -- found nothing there). The migration is therefore driven from
    -- `_restore_modded_loadout` (mirror-confirmed) via `_run_loadout_migration`
    -- below, NOT from `_modded_loadout_load`.
    --
    -- Mutates `data` in place (per career). Returns true if anything was migrated
    -- (caller persists). Guards every step against partial/corrupt entries; never
    -- drops a saved bid. The `mirror_ready` flag gates the fallback: when the mirror
    -- is confirmed up we DO accept the resolved index (even if it's 1, that's the
    -- real selected index); when it's NOT up we SKIP the career entirely and leave
    -- it flat for a later pass (don't home to a guessed index).
    local function _migrate_modded_loadout(data, mirror_ready)
        if type(data) ~= "table" then return false end
        local migrated = false
        for career_name, career_tbl in pairs(data) do
            if _career_value_is_flat(career_tbl) then
                if not mirror_ready then
                    -- Mirror not up yet — DON'T guess an index. Leave this career
                    -- flat; the next mirror-ready restore pass migrates it.
                    mod:info("[loadout-migrate] %s deferred (mirror not ready)", tostring(career_name))
                else
                    local index = _resolve_selected_index(career_name)
                    local indexed = { [index] = {} }
                    for slot_name, bid in pairs(career_tbl) do
                        -- Only re-home well-formed (string slot -> bid) entries; keep
                        -- any stray numeric->table entry (mixed/corrupt save) intact so
                        -- no data is lost.
                        if type(slot_name) == "string" then
                            indexed[index][slot_name] = bid
                        elseif type(slot_name) == "number" and type(bid) == "table" then
                            indexed[slot_name] = bid
                        end
                    end
                    data[career_name] = indexed
                    migrated = true
                    mod:info("[loadout-migrate] %s flat->indexed under live selected index %d",
                        tostring(career_name), index)
                end
            end
        end
        return migrated
    end

    -- One-shot guard: once a mirror-ready migration pass converts every flat career
    -- and persists, this flips true so subsequent restore passes don't re-scan /
    -- re-migrate. It is also idempotent WITHOUT the flag — `_career_value_is_flat`
    -- returns false for already-indexed careers, so a re-run is a no-op — but the
    -- flag avoids the per-pass walk and the redundant persist on the 1.0s/3.0s
    -- deferred restore passes and the manual /cim_restore_loadout command.
    local _loadout_migration_done = false

    -- Mirror-ready migration driver. Called from `_restore_modded_loadout` (where
    -- the backend mirror is confirmed loaded). Detects any remaining flat-shape
    -- career, homes it to its REAL live selected index, and persists once. If the
    -- mirror is somehow still unavailable, migrates nothing this pass and leaves the
    -- one-shot flag UNSET so the next deferred pass re-attempts (no data lost).
    local function _run_loadout_migration()
        if _loadout_migration_done then return end
        -- Confirm the mirror really is reachable before committing to an index.
        local items_iface = Managers.backend and Managers.backend.get_interface
            and Managers.backend:get_interface("items")
        local mirror_ready = (items_iface and items_iface._backend_mirror) and true or false
        local migrated = _migrate_modded_loadout(_modded_loadout, mirror_ready)
        if migrated then
            _modded_loadout_save()
        end
        -- Only declare the one-shot done once we've actually had a mirror-ready pass
        -- AND nothing flat remains. If the mirror wasn't ready, leave the flag unset
        -- so the next restore pass re-attempts.
        if mirror_ready then
            local any_flat = false
            for _, career_tbl in pairs(_modded_loadout) do
                if _career_value_is_flat(career_tbl) then any_flat = true break end
            end
            if not any_flat then _loadout_migration_done = true end
        end
    end

    -- Boot/script-eval load: pull the raw saved payload into memory AS-IS (flat or
    -- indexed). NO migration here — migration is deferred to `_run_loadout_migration`
    -- at the first mirror-ready restore pass (see the timing note above). Until then
    -- `_modded_loadout` may carry the OLD flat shape for some careers; every early
    -- consumer that walks it before the migration runs must tolerate the flat shape
    -- (audited v0.8.14-dev: `_cim_clear_modded_loadout_for_bid` is the only such
    -- pre-mirror consumer and now handles both shapes; the restore loop and
    -- `_reequip_live_avatar` run AFTER `_run_loadout_migration` in the same call).
    local function _modded_loadout_load()
        local data = mod:get("modded_loadout")
        if type(data) == "table" then
            _modded_loadout = data
        else
            _modded_loadout = {}
        end
    end

    _modded_loadout_load()

    -- Public helper for sibling modules (standard_forge.lua salvage synth) to drop
    -- a salvaged backend_id out of the saved loadout — otherwise loadout-restore
    -- on next session would try to re-equip a non-existent item.
    mod._cim_clear_modded_loadout_for_bids = function(backend_ids)
        local core = mod._cim277_bulk_core
        local dirty = core and core.clear_loadout_refs
            and core.clear_loadout_refs(_modded_loadout, backend_ids)
        if dirty then _modded_loadout_save() end
        return dirty and true or false
    end

    mod._cim_clear_modded_loadout_for_bid = function(backend_id)
        if not backend_id then return false end
        return mod._cim_clear_modded_loadout_for_bids({ backend_id })
    end

    -- v0.7.33-alpha one-shot migration. Old (pre-v0.7.33) cim never cleared
    -- _modded_loadout entries when the user equipped a non-cim item. The fix in
    -- v0.7.33 keeps state correct GOING FORWARD but doesn't heal save data from
    -- before the fix. This migration walks _modded_loadout once at session load
    -- and purges every entry whose bid isn't in `_forged_weapons` (cim crafts)
    -- and doesn't match `cwv_*` (character_weapon_variants). Stale entries
    -- pointing to non-existent items can't be restored anyway, so dropping them
    -- avoids re-trying the same MISSING restore log line every session.
    -- LOAD-BEARING compatibility exception, not ownership: see
    -- docs/CROSS_MOD_ARCHITECTURE.md "CIM ↔ CWV backend-ID convention" and #70/#592.
    local function _modded_loadout_purge_stale()
        local removed = 0
        -- Indexed schema: career -> index -> slot -> bid.
        for career_name, indices in pairs(_modded_loadout) do
            if type(indices) == "table" then
                for index, slots in pairs(indices) do
                    if type(slots) == "table" then
                        for slot_name, bid in pairs(slots) do
                            local keep = false
                            if type(bid) == "string" then
                                if _get_forged_weapons()[bid] then keep = true
                                elseif bid:sub(1, 4) == "cwv_" then keep = true
                                end
                            end
                            if not keep then
                                slots[slot_name] = nil
                                removed = removed + 1
                                mod:info("[loadout-purge] %s[%s]/%s -> %s (bid not in forged_weapons or cwv_*)",
                                    tostring(career_name), tostring(index), tostring(slot_name), tostring(bid))
                            end
                        end
                    end
                end
            end
        end
        if removed > 0 then
            _modded_loadout_save()
            mod:info("[loadout-purge] removed %d stale loadout entries", removed)
        end
    end

    -- Sibling-mod post-restore extension point. cosmetics_tweaker registers its
    -- LA-illusion / paint / offhand reapply here so the re-apply runs AFTER cim
    -- has restored the modded backend_ids to their loadout slots. Fires on every
    -- restore pass (initial + 1.0s deferred + 3.0s deferred), so registered
    -- callbacks must be idempotent. Public API: `mod._cim_register_restore_callback(fn)`.
    local _restore_callbacks = {}
    mod._cim_register_restore_callback = function(fn)
        if type(fn) ~= "function" then
            mod:info("[restore] register_restore_callback ignored: arg not a function")
            return false
        end
        _restore_callbacks[#_restore_callbacks + 1] = fn
        return true
    end

    -- Assigned to the forward-declared local at the top of the Forge core section,
    -- so the `_create_interfaces` hook can call it.
    --
    -- v0.7.33-alpha: verbose per-entry logging. Previous versions only logged the
    -- aggregate "Restored N modded loadout entries" count, which made it
    -- impossible to diagnose user reports like "my <X> didn't come back". Now
    -- every saved entry is logged with career + slot + bid + result (restored /
    -- missing-from-mirror / pcall-error). Counts are still echoed for chat
    -- visibility; the per-entry detail lives in `mod:info` (log only).

    -- v0.7.67-dev (issue #22): re-equip the LIVE keep avatar after the loadout data
    -- write. set_loadout_item updates what the inventory/loadout RECORDS as equipped,
    -- but the keep character unit spawned BEFORE the deferred restore ran, so it's
    -- still holding the pre-restore (vanilla/default) weapons. Replicate vanilla's
    -- HeroViewStateOverview equip path (hero_view_state_overview.lua:707-715): for
    -- the CURRENT career's restored slots, recreate the equipment/attachment on the
    -- spawned unit so the visible weapon matches the saved loadout. Only the local
    -- current career has a live unit; other careers re-read from data when next
    -- selected/spawned. NOT the issue-#12 risk (that was craft-time divergence; here
    -- we make the live unit MATCH already-correct data).
    --
    -- Guards: network game ready, a living local player_unit (in the keep), the
    -- right extension present. Fully pcall-guarded — a transition-timing failure
    -- degrades to "data correct, visual updates on next career select", never a
    -- crash. Per-(career/slot/bid) dedup via _reequipped avoids re-spawning the same
    -- unit on every deferred restore pass (flicker).
    local function _reequip_live_avatar()
        local net = Managers.state and Managers.state.network
        if not (net and net.game and net:game()) then return end
        local pl = Managers.player and Managers.player:local_player()
        local unit = pl and pl.player_unit
        if not (unit and Unit.alive(unit)) then return end
        local profile_index = pl:profile_index()
        local career_index = pl:career_index()
        local profile = SPProfiles and SPProfiles[profile_index]
        local career = profile and profile.careers and profile.careers[career_index]
        local career_name = career and career.name
        if not career_name then return end
        -- The live keep unit shows the player's SELECTED loadout index, so only
        -- re-equip the slots saved under that index. (Bot-designated indices have
        -- no live local unit — they re-read from data when next spawned.)
        local sel_index = _resolve_selected_index(career_name, 1)
        local indices = _modded_loadout[career_name]
        local slots = type(indices) == "table" and indices[sel_index]
        if not slots then return end

        local items = Managers.backend and Managers.backend:get_interface("items")
        if not items then return end
        local inv_ext = ScriptUnit.has_extension(unit, "inventory_system")
        local att_ext = ScriptUnit.has_extension(unit, "attachment_system")

        for slot_name, backend_id in pairs(slots) do
            local key = career_name .. "/" .. slot_name
            if _reequipped[key] ~= backend_id then
                local item = items:get_item_from_id(backend_id)
                local slot_type = item and item.data and item.data.slot_type
                local ok, err
                if (slot_type == "melee" or slot_type == "ranged")
                   and inv_ext and inv_ext.create_equipment_in_slot then
                    ok, err = pcall(inv_ext.create_equipment_in_slot, inv_ext, slot_name, backend_id)
                elseif (slot_type == "trinket" or slot_type == "ring" or slot_type == "necklace")
                   and att_ext and att_ext.create_attachment_in_slot then
                    ok, err = pcall(att_ext.create_attachment_in_slot, att_ext, slot_name, backend_id)
                end
                if ok then
                    _reequipped[key] = backend_id
                    mod._cim_reequip_ok = (mod._cim_reequip_ok or 0) + 1
                    mod:info("[reequip] live avatar %s -> %s (%s)", key, tostring(backend_id), tostring(slot_type))
                elseif err then
                    -- Record for the reequip_live_api_ok regression check: if the
                    -- vanilla create_equipment/attachment API signature ever drifts
                    -- or we call it at the wrong time, this surfaces it from a log.
                    mod._cim_reequip_last_err = tostring(err)
                    mod:info("[reequip] FAILED %s (%s): %s", key, tostring(slot_type), tostring(err))
                end
            end
        end
    end

    -- Issue #562: equip the exact freshly-created backend id, not another item with
    -- the same ItemMasterList key. The items interface accepts an explicit loadout
    -- index and writes it through to set_character_data
    -- (backend_interface_item_playfab.lua:635-667). The live keep avatar is a
    -- separate surface: vanilla's inventory equip path writes the loadout and then
    -- queues/recreates the equipment unit (hero_view_state_overview.lua:1070-1139).
    -- Keep those two surfaces together here so craft-time auto-equip cannot regress
    -- into issue #12's historical "new icon, old weapon unit" divergence.
    local _AUTO_EQUIP_WEAPON_SLOTS = {
        slot_melee = "melee",
        slot_ranged = "ranged",
    }

    local function _auto_equip_slot_type(slot_name)
        return _AUTO_EQUIP_WEAPON_SLOTS[slot_name]
    end

    local function _auto_equip_crafted_weapon(career_name, slot_name, backend_id)
        if not mod:get("auto_equip_new_weapons") then return false, "disabled" end

        local expected_slot_type = _auto_equip_slot_type(slot_name)
        if not expected_slot_type then return false, "not a weapon slot" end
        if not career_name or not backend_id then return false, "missing craft identity" end

        local items = Managers.backend and Managers.backend:get_interface("items")
        if not items then return false, "items backend not ready" end

        local item = items:get_item_from_id(backend_id)
        local slot_type = item and item.data and item.data.slot_type
        if slot_type ~= expected_slot_type then
            return false, string.format("crafted slot mismatch (%s for %s)", tostring(slot_type), tostring(slot_name))
        end

        local loadout_index = _resolve_selected_index(career_name, 1)
        local ok_write, write_result = pcall(
            items.set_loadout_item,
            items,
            backend_id,
            career_name,
            slot_name,
            loadout_index
        )
        if not ok_write or write_result == false then
            return false, "loadout write failed: " .. tostring(write_result)
        end

        -- Recreate the current local career's weapon unit immediately. If the
        -- player unit is unavailable during a state transition, the indexed data
        -- write above remains authoritative and the next spawn reads the new bid.
        local live_equipped = false
        local pl = Managers.player and Managers.player:local_player()
        local unit = pl and pl.player_unit
        local profile_index = pl and pl:profile_index()
        local career_index = pl and pl:career_index()
        local profile = SPProfiles and profile_index and SPProfiles[profile_index]
        local current_career = profile and profile.careers and career_index
            and profile.careers[career_index] and profile.careers[career_index].name
        if current_career == career_name and unit and Unit.alive(unit) then
            local inv_ext = ScriptUnit.has_extension(unit, "inventory_system")
            if inv_ext and inv_ext.create_equipment_in_slot then
                local ok_live, live_err = pcall(
                    inv_ext.create_equipment_in_slot,
                    inv_ext,
                    slot_name,
                    backend_id
                )
                if ok_live then
                    live_equipped = true
                    _reequipped[career_name .. "/" .. slot_name] = backend_id
                else
                    mod._cim_auto_equip_last_err = tostring(live_err)
                    pcall(printf, "[cim:562] live auto-equip failed career=%s slot=%s bid=%s err=%s",
                        tostring(career_name), tostring(slot_name), tostring(backend_id), tostring(live_err))
                end
            end
        end

        local event = Managers.state and Managers.state.event
        if event and event.trigger then
            pcall(event.trigger, event, "event_set_loadout_items")
        end

        mod._cim_auto_equip_last = {
            backend_id = backend_id,
            career_name = career_name,
            slot_name = slot_name,
            loadout_index = loadout_index,
            live_equipped = live_equipped,
        }
        return true, live_equipped and "live" or "loadout"
    end

    mod._cim_auto_equip_crafted_weapon = _auto_equip_crafted_weapon
    mod._cim_auto_equip_slot_type = _auto_equip_slot_type

    _restore_modded_loadout = function()
        -- v0.8.15-dev MASTER gate: when loadout persistence is OFF (default), cim
        -- does NOT touch loadouts at all — no flat->indexed migration, no stale
        -- purge, no set_loadout_item writes, no live-avatar re-equip. The whole
        -- restore (and the migration it drives via _run_loadout_migration) is a
        -- no-op, leaving vanilla player AND bot loadouts exactly as the base game
        -- writes them.
        if not _persist_loadouts_enabled() then
            mod:info("[restore] skipped — loadout persistence removed from cim (moved to Tweaker: GUI)")
            return
        end
        _modded_loadout_load()
        -- v0.8.14-dev: run the flat->indexed migration HERE, at the first
        -- mirror-ready moment, so each migrated flat entry homes to the career's
        -- REAL live selected index (not the boot-time fallback of 1). One-shot +
        -- idempotent; re-attempts on a later deferred pass if the mirror still
        -- isn't up. MUST run before purge/restore below so those walk the indexed
        -- shape. (The v0.8.13-dev blocker: this used to run at script-eval where the
        -- mirror is absent, homing every entry to index 1 and breaking multi-loadout
        -- users whose selected index != 1.)
        _run_loadout_migration()
        -- Purge stale entries (bids no longer in _forged_weapons / cwv_*) before
        -- attempting restore. Idempotent — runs every restore pass; first session
        -- after v0.7.33-alpha may purge dozens of entries, subsequent sessions zero.
        _modded_loadout_purge_stale()
        local items = Managers.backend and Managers.backend:get_interface("items")
        if not items then
            mod:info("[restore] skipped — items backend interface not ready")
            return
        end

        -- v0.7.54-dev: dump full saved-loadout state at restore entry (gated on
        -- enable_debug_logging) so we see every (career, slot) that SHOULD be
        -- restored — not just the ones the loop iterates. Helps detect cases
        -- where `_modded_loadout` is missing entries the user expects.
        if mod._cim_autodump_restore_pass then
            pcall(mod._cim_autodump_restore_pass, "pre-restore", _modded_loadout)
        end

        -- Total entries seen vs restored vs skipped — diagnostic-only.
        local total, restored, missing, errored = 0, 0, 0, 0
        -- Guard the capture path off while we replay saved state (see _restoring).
        -- INVARIANT: _restoring MUST be reset to false before this function returns,
        -- or the equip-capture hook stays disabled for the whole session (no equips
        -- saved/restored). There are NO early returns between here and the reset at
        -- the bottom of the loop, and every call that can throw inside the bracket is
        -- pcall-guarded. Keep it that way: do not add an un-pcall'd throwing call here.
        _restoring = true
        -- Indexed schema: career -> index -> slot -> bid. Each saved item is
        -- restored to ITS OWN index by passing `loadout_index` as the 4th arg to
        -- set_loadout_item -> set_character_data(..., optional_loadout_index)
        -- (backend_interface_item_playfab.lua:665, playfab_mirror_base.lua:1928).
        -- This is the core bot fix: a bot's designated-index modded gear lands on
        -- that index instead of being stamped into the host's selected index.
        for career_name, indices in pairs(_modded_loadout) do
            if type(indices) == "table" then
                for loadout_index, slots in pairs(indices) do
                    if type(slots) == "table" then
                        for slot_name, backend_id in pairs(slots) do
                            total = total + 1
                            -- pcall-guarded: a throw here (LA-clone drift, stale template-cache
                            -- hit from standard_forge's get_item_from_id hook, malformed mirror
                            -- entry) would otherwise propagate out and strand _restoring=true.
                            local ok_get, item = pcall(items.get_item_from_id, items, backend_id)
                            if not ok_get then item = nil end
                            if not item then
                                missing = missing + 1
                                mod:info("[restore] MISSING %s[%s]/%s -> %s (item not in mirror; will retry next state transition)",
                                    tostring(career_name), tostring(loadout_index), tostring(slot_name), tostring(backend_id))
                            else
                                local item_key = item.key or item.ItemId or (item.data and item.data.key) or "<unknown>"
                                -- Pass the SAVED index as the 4th arg so the write targets
                                -- that index, not the live SELECTED one. Type-guard: only
                                -- pass a numeric index (a corrupt non-number key falls back
                                -- to vanilla's selected-index default rather than throwing).
                                local index_arg = (type(loadout_index) == "number") and loadout_index or nil
                                local ok, err = pcall(items.set_loadout_item, items, backend_id, career_name, slot_name, index_arg)
                                if ok then
                                    restored = restored + 1
                                    mod:info("[restore] OK %s[%s]/%s -> %s (%s)",
                                        tostring(career_name), tostring(loadout_index), tostring(slot_name), tostring(backend_id), tostring(item_key))
                                else
                                    errored = errored + 1
                                    mod:info("[restore] ERROR %s[%s]/%s -> %s: %s",
                                        tostring(career_name), tostring(loadout_index), tostring(slot_name), tostring(backend_id), tostring(err))
                                end
                                -- v0.7.54-dev: immediately read back via get_loadout_item_id
                                -- to PROVE the write reached the layer the inventory reads
                                -- from. If set_loadout_item returns ok but read-back returns
                                -- a different bid (or nil), the mirror silently rejected our
                                -- write OR a different persistence layer is the source of truth.
                                -- This is the proof issue #22 needs.
                                if mod._cim_autodump_restore_entry then
                                    pcall(mod._cim_autodump_restore_entry,
                                        career_name, slot_name, backend_id, items, ok, err, index_arg)
                                end
                            end
                        end
                    end
                end
            end
        end
        _restoring = false
        if total > 0 then
            mod:info("[restore] total=%d restored=%d missing=%d errored=%d",
                total, restored, missing, errored)
        end

        -- v0.7.67-dev (issue #22): after writing the loadout DATA, re-equip the live
        -- keep avatar for the current career so the visible weapon matches what we
        -- just restored (the unit spawned before this deferred pass). Pcall-guarded.
        pcall(_reequip_live_avatar)

        -- Fan out to sibling-mod restore callbacks (e.g. cosmetics_tweaker reapplies
        -- its persisted LA illusion / paint / offhand selections per (career, slot)
        -- now that the modded backend_ids are live in the mirror). Fires on EVERY
        -- restore pass — initial + 1.0s deferred + 3.0s deferred — so subscribers
        -- should make their re-apply idempotent. Wrapped in pcall so a broken
        -- callback can't take down cim's restore.
        if _restore_callbacks then
            for _, cb in ipairs(_restore_callbacks) do
                local ok, err = pcall(cb)
                if not ok then
                    mod:info("[restore] sibling callback errored: %s", tostring(err))
                end
            end
        end

        -- Debug autodump: per-career summary of saved entries. No-op when
        -- debug_mode is OFF. Called after restore so the log reflects the
        -- post-restore state.
        if mod._cim_autodump_restore_done then
            pcall(mod._cim_autodump_restore_done, "post-restore")
        end
    end

    -- Capture each set_loadout_item call so we can track per-(career, slot) state.
    --
    -- Pre-v0.7.33-alpha bug (root cause of "didn't restore my equipped items"
    -- user report 2026-05-23): this hook only saved entries when the new item was
    -- modded — and NEVER cleared a slot when the user later equipped a non-cim
    -- (vanilla / Save Weapon / Loadout Manager / etc.) item there. Stale modded
    -- entries stayed in `_modded_loadout` indefinitely.
    --
    -- On next session boot, `_restore_modded_loadout` ran AFTER vanilla PlayFab
    -- restored each slot — and faithfully re-equipped the stale modded item,
    -- clobbering what the user had actually equipped at session-end.
    --
    -- Fix: ALWAYS clear the slot entry first. Then, only if the new item is
    -- modded, re-save the entry. Vanilla equips clean up the cim record; modded
    -- equips refresh it. Either way the saved state matches what's currently
    -- equipped instead of frozen at first-modded-equip-ever.
    -- Shared equip capture. Records the equipped item into _modded_loadout (clear
    -- the slot first; re-save only if the new item is modded — so vanilla equips
    -- clean up the cim record and modded equips refresh it). `from_live_equip` is
    -- true for the BackendUtils menu path (vanilla already re-spawned the unit, so
    -- sync the re-equip dedup map); false for bare interface writes.
    --
    -- Skipped entirely while restore replays saved state (_restoring): those writes
    -- aren't new equips, must not mutate _modded_loadout mid-pairs()-iteration, and
    -- must not pre-mark _reequipped (which would starve the live re-equip).
    -- `loadout_index` is the index THIS equip wrote to. The 4-arg
    -- BackendInterfaceItemPlayfab.set_loadout_item path carries it explicitly
    -- (`optional_loadout_index`); the 3-arg BackendUtils menu path does NOT, so the
    -- caller resolves the LIVE selected index off the mirror and passes it in. A nil
    -- here falls back to the resolved selected index (matching vanilla's
    -- get/set_character_data default) so the capture never lands index-less.
    local function _capture_loadout_equip(career_name, slot_name, item_id, from_live_equip, loadout_index)
        -- v0.8.15-dev master gate: when loadout persistence is OFF (default), cim
        -- captures NOTHING — `_modded_loadout` is never read or written, so neither
        -- the BackendInterfaceItemPlayfab hook_safe nor the BackendUtils full hook
        -- perturbs the vanilla equip. The BackendUtils hook still calls func(...) so
        -- the underlying vanilla write is byte-identical; this just skips the record.
        if not _persist_loadouts_enabled() then return end
        if _restoring then return end
        if not item_id or not career_name or not slot_name then return end

        -- Resolve the index this write targets: explicit arg wins; otherwise the
        -- live selected index (vanilla's default target when no index is passed).
        if type(loadout_index) ~= "number" then
            loadout_index = _resolve_selected_index(career_name, 1)
        end

        if mod._cim_autodump_equip_event then
            local items_iface = Managers.backend and Managers.backend:get_interface("items")
            pcall(mod._cim_autodump_equip_event, career_name, slot_name, item_id, items_iface, from_live_equip, loadout_index)
        end

        -- Indexed schema: career -> index -> slot -> bid. Clear the (index, slot)
        -- first; re-save only if the new item is modded (vanilla equips clean up the
        -- cim record at THAT index, modded equips refresh it). Other indices for the
        -- same career/slot are untouched — that's the whole point of the fix.
        local career_tbl = _modded_loadout[career_name]
        local index_tbl = career_tbl and career_tbl[loadout_index]
        local was_stale = index_tbl and index_tbl[slot_name]
        if index_tbl then
            index_tbl[slot_name] = nil
        end

        local is_modded = mod._cim_is_modded_backend_id and mod._cim_is_modded_backend_id(item_id)
        if is_modded then
            _modded_loadout[career_name] = _modded_loadout[career_name] or {}
            _modded_loadout[career_name][loadout_index] = _modded_loadout[career_name][loadout_index] or {}
            _modded_loadout[career_name][loadout_index][slot_name] = item_id
        end

        if from_live_equip then
            -- The menu equip already recreated the unit; sync dedup so the next
            -- restore pass doesn't needlessly re-spawn this slot. The live keep unit
            -- only ever shows the selected index, and menu equips write the selected
            -- index, so the bare "career/slot" dedup key stays correct.
            _reequipped[career_name .. "/" .. slot_name] = item_id
        end

        if was_stale or is_modded then
            _modded_loadout_save()
        end
    end

    -- Direct interface writes (restore — guarded by _restoring — or any code calling
    -- the items interface method directly). from_live_equip=false: a bare data write
    -- doesn't re-spawn the unit. Capture the 4th arg `optional_loadout_index` so a
    -- write to a NON-selected index (e.g. configuring a bot's designated loadout) is
    -- recorded under that index, not the selected one.
    mod:hook_safe("BackendInterfaceItemPlayfab", "set_loadout_item", function(self, item_id, career_name, slot_name, optional_loadout_index)
        _capture_loadout_equip(career_name, slot_name, item_id, false, optional_loadout_index)
    end)

    -- THE menu-equip capture (issue #22 root fix). With Loremaster's Armoury active,
    -- HeroViewStateOverview._set_loadout_item → BackendUtils.set_loadout_item →
    -- get_loadout_interface_by_slot(slot):set_loadout_item dispatches through an
    -- LA-CLONED interface, so the BackendInterfaceItemPlayfab hook above NEVER fires
    -- for the player's actual equips — _modded_loadout stayed frozen and nothing was
    -- restored next session (confirmed from log 2026-05-30: user equipped every slot
    -- on es_mercenary, zero equip_events captured). Hook the stable OUTER entry point
    -- (BackendUtils — a plain table, so TABLE-form hook per the repo "Hooking" rule)
    -- so we capture every menu equip BEFORE the LA dispatch. Installed deferred (once
    -- backend interfaces exist, i.e. post-LA-bridge) from mod.update via
    -- _install_backendutils_capture — same timing cosmetics_tweaker uses for its own
    -- BackendUtils.set_loadout_item hook.
    local _backendutils_capture_installed = false
    local function _install_backendutils_capture()
        if _backendutils_capture_installed then return end
        local BU = rawget(_G, "BackendUtils")
        if not (BU and BU.set_loadout_item and Managers.backend and Managers.backend.get_interface) then return end
        local ok_iface = pcall(function() return Managers.backend:get_interface("items") end)
        if not ok_iface then return end
        _backendutils_capture_installed = true
        mod._cim_backendutils_capture_installed = true  -- for the regression check
        mod:hook(BU, "set_loadout_item", function(func, backend_id, career_name, slot_name)
            -- BackendUtils.set_loadout_item is 3-arg and always writes the SELECTED
            -- index, so pass nil for loadout_index — the capture helper resolves the
            -- live selected index off the mirror and stores the bid under it.
            _capture_loadout_equip(career_name, slot_name, backend_id, true, nil)
            return func(backend_id, career_name, slot_name)
        end)
        mod:info("[cim] BackendUtils.set_loadout_item capture installed (post-LA menu-equip capture)")
    end

    mod:command("cim_restore_loadout", "Manually re-equip the saved modded loadout (use if your modded weapons didn't come back after a restart)", function()
        if not _restore_modded_loadout then mod:echo("Restore helper not initialised yet."); return end
        _modded_loadout_load()
        local count = 0
        -- Indexed schema: career -> index -> slot -> bid.
        for career_name, indices in pairs(_modded_loadout) do
            if type(indices) == "table" then
                for _, slots in pairs(indices) do
                    if type(slots) == "table" then
                        for _ in pairs(slots) do count = count + 1 end
                    end
                end
            end
        end
        mod:echo(string.format("[cim] %d saved modded loadout entries; restoring...", count))
        _restore_modded_loadout()
        mod:echo("[cim] Done. If items are still missing, run /cim_dump_loadout to see what's saved.")
    end)

    -- Open the VANILLA standard crafting bench (salvage / craft / re-roll / upgrade
    -- / apply-illusion). Works in the Keep always; in adventure missions when
    -- 'Allow in mission' is ON. Material-clean (unlike the Athanor /forge_hotkey).
    -- mod.open_standard_crafting is defined further down (Athanor section); the
    -- command is registered at load and dispatches at runtime, so order is fine.
    mod:command("cim_craft_standard", "Open the standard crafting bench (salvage / craft / re-roll properties + traits / upgrade rarity / apply illusion). Keep always; in mission with 'Allow in mission' ON. Adventure only.", function()
        if type(mod.open_standard_crafting) == "function" then
            mod.open_standard_crafting()
        else
            mod:echo("Standard crafting opener not initialised yet.")
        end
    end)


    mod:command("cim_dump_loadout", "Print the saved modded loadout table to chat", function()
        _modded_loadout_load()
        local items = Managers.backend and Managers.backend:get_interface("items")
        local total = 0
        -- Indexed schema: career -> index -> slot -> bid.
        for career_name, indices in pairs(_modded_loadout) do
            if type(indices) == "table" then
                for index, slots in pairs(indices) do
                    if type(slots) == "table" then
                        for slot_name, bid in pairs(slots) do
                            local item = items and items:get_item_from_id(bid)
                            local in_mirror = item and "yes" or "MISSING"
                            mod:echo(string.format("  %s[%s] %s -> %s (in_mirror=%s)",
                                career_name, tostring(index), slot_name, tostring(bid), in_mirror))
                            total = total + 1
                        end
                    end
                end
            end
        end
        mod:echo(string.format("[cim] %d entries saved (across %d careers)", total,
            (function() local c = 0; for _ in pairs(_modded_loadout) do c = c + 1 end; return c end)()))
    end)

    state.exports = {
        restore_modded_loadout = _restore_modded_loadout,
        install_backendutils_capture = _install_backendutils_capture,
        modded_loadout_save = _modded_loadout_save,
        modded_loadout_load = _modded_loadout_load,
        get_modded_loadout = function() return _modded_loadout end,
        set_modded_loadout = function(value) _modded_loadout = value end,
    }
    return state.exports
end

return install
