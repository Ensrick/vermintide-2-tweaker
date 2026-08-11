-- _cos_la_loadout_safety.lua - LA cosmetic loadout state, and the two vanilla-RPC
-- senders that must never put an LA backend_id on the wire.
--
-- RESPONSIBILITY
-- One question: when the local player is wearing a Loremaster's Armoury (or
-- Cosmetics-authored) cosmetic, what does the REST of the world see. Two halves
-- that cannot be separated because they share `mod.loadout_cache` and one
-- LA->vanilla fallback resolver:
--
--   * LOADOUT STATE - `_install_skin_loadout_safety` and its five deferred
--     hooks (BackendUtils.set_loadout_item plus get_loadout,
--     get_loadout_item_id and get_item_rarity on the "items" backend
--     interface). LA clones are cached LOCALLY in `mod.loadout_cache` and
--     overlaid on every read, because a clone backend_id written back to
--     PlayFab is a server-side clone that no other machine can resolve. The
--     same install does the one-shot server-clone fixup and rehydrates the
--     cache from disk (#520), so the equipped hat/outfit survives a restart.
--
--   * WIRE SUBSTITUTION - the CosmeticUtils.update_cosmetic_slot and
--     LoadoutUtils.sync_loadout_slot hooks. Both encode a cosmetic identity
--     through a strict `NetworkLookup` table; an index this session registered
--     locally (crash GUID fa479a72) fatals a vanilla peer on decode. Each hook
--     substitutes the vanilla equivalent for the outgoing call and SKIPS the
--     call outright when no fallback exists. That substitution is
--     UNCONDITIONAL - never toggle-gated, never behind a settings read (issue
--     371 / BUG_CLASSES 31): a peer's crash is not the local player's option.
--
-- They travel together because the substitution hooks read the very cache the
-- loadout hooks write (a cached clone is exactly what must not reach a peer),
-- both resolve through the same `_la_vanilla_fallback`, and both maintain
-- `_local_la_equips` so the hot-join replay can re-emit what is actually worn.
-- Split them and the cache has two owners with opposite intents.
--
-- NOT OWNED HERE. The attachment-category spawn/sync seams
-- (PlayerUnitAttachmentExtension, AttachmentUtils.hot_join_sync) are the third
-- substitution surface and belong to `_cos_attachment_spawn_sync.lua`. The
-- `_net_safe_hook_status` table those hooks report into stays ENTRY-owned: no
-- code in this file reads or writes it, and the entry both brokers it to the
-- spawn-sync owner and reads it back in its startup verification.
--
-- Extracted VERBATIM from cosmetics_tweaker.lua (entry lines 1792-1798 and
-- 1800-2284 at b8e52a43) with no behaviour change. Every moved statement is
-- byte-identical modulo the uniform four-space install() indent; the move ADDS
-- exactly one statement, marked DEVIATION inline (the late-bound
-- `_send_la_apply` resolve) and described under ENTRY-OWNED STATE below.
-- mod:dofile is not a singleton, so the entry calls `install` EXACTLY once.
--
-- INSTALL POSITION
-- Single phase, at the exact point the moved block used to start. Nothing in
-- the entry executes between that point and the first moved statement, so
-- collapsing the range to one install call cannot reorder anything: entry lines
-- 1800-2007 are declarations only, and the two file-scope registrations
-- (CosmeticUtils, LoadoutUtils) still run in their original relative order and
-- still BEFORE the `_net_safe_hook_status` presence probe that follows the
-- install. The four backend hooks are deferred exactly as before - they
-- register when the entry calls `install_skin_loadout_safety()` on the frame
-- the LA bridge registers.
--
-- ENTRY-OWNED STATE
--   * `_send_la_apply` - a GETTER (`get_send_la_apply`), not a value. The entry
--     forward-declares the sender far above this install and only assigns it
--     BELOW, from the _cos_la_sync_transport install. By value this owner would
--     capture nil forever; the getter reads the entry's local at hook-fire
--     time, which is always after the assignment.
--   * `_la_equips_by_peer` and `_local_la_equips` are safe BY VALUE: each is
--     created once as a truthy table above this install and never rebound
--     (`_la_equips_by_peer = _la_equips_by_peer or {}` further down is
--     identity-preserving), so this owner holds the same table the rest of the
--     file mutates. Same proof the sibling owners already rely on.
--   * `_la_bridge_init_done` stays in the entry: it is the entry's own
--     first-frame bridge latch, read only by the entry's mod.update.
--
-- RETURNED TO THE ENTRY
-- `_la_vanilla_fallback`, `_wire_career_for_player` and
-- `_install_skin_loadout_safety` come straight back out as entry locals. Each
-- has consumers that stay in the entry (the `_la_substitute_name` wrapper and
-- two dep tables; the complete-set rebroadcast `career_for`; the mod.update
-- bridge-ready call site), and each is the SAME function object every existing
-- call site resolved before, so no behaviour depends on which chunk defines it.
--
-- Owned by: cosmetics_tweaker.lua entry point.
-- Consumed via: mod:dofile("scripts/mods/cosmetics_tweaker/_cos_la_loadout_safety")

local CosLaLoadoutSafety = {}

function CosLaLoadoutSafety.install(mod, deps)
    deps = deps or {}

    local GK_SET             = assert(deps.gk_set, "gk_set is required")
    local LA_BRIDGE          = assert(deps.la_bridge, "la_bridge is required")
    local LA_PERSIST         = assert(deps.la_persistence, "la_persistence is required")
    local _dbg               = assert(deps.dbg, "dbg is required")
    local _la_equips_by_peer = assert(deps.la_equips_by_peer, "la_equips_by_peer is required")
    local _local_la_equips   = assert(deps.local_la_equips, "local_la_equips is required")
    local _local_player_safe = assert(deps.local_player_safe, "local_player_safe is required")

    -- The entry's forward-declared LA sender crosses the chunk boundary as a
    -- late-binding accessor, never as an install-time value. See ENTRY-OWNED
    -- STATE above.
    local _get_send_la_apply = assert(deps.get_send_la_apply, "get_send_la_apply is required")

    -- ============================================================
    -- Loremaster's Armoury bridge (Phase 1)
    -- ============================================================
    -- Registers LA's recolored cosmetics as separate inventory items via MIL,
    -- and queues their texture swap into LA's existing apply pipeline. See
    -- _la_bridge.lua for details.

    local _la_skin_safety_done       = false
    mod.loadout_cache                = mod.loadout_cache or {}

    -- Mirrors AllHats lines 38-71: cache custom slot_skin loadouts locally so
    -- they're never synced to other clients (vanilla clients crash on unknown
    -- skin backend_ids).
    local _la_vanilla_fallback = function(name, career) return GK_SET.wire_fallback(LA_BRIDGE, name, career) end

    local function _install_skin_loadout_safety()
        if _la_skin_safety_done then return end
        if not (Managers.backend and Managers.backend._interfaces and Managers.backend._interfaces["items"]) then return end
        if not BackendUtils then return end
        _la_skin_safety_done = true

        local items_iface = Managers.backend:get_interface("items")

        mod:hook(BackendUtils, "set_loadout_item", function(func, backend_id, career_name, slot_name)
            local is_clone = LA_BRIDGE.backend_to_armoury[backend_id]
            if is_clone and (slot_name == "slot_hat" or slot_name == "slot_skin") then
                mod.loadout_cache[career_name] = mod.loadout_cache[career_name] or {}
                mod.loadout_cache[career_name][slot_name] = backend_id
                _dbg("[loadout] CACHED %s %s = %s", career_name, slot_name, backend_id)
                -- v0.9.83-dev (#520): persist HERE, at the user-intent chokepoint.
                -- career_name is a call ARGUMENT, so this tap has none of the
                -- profile_by_peer resync fragility that silently dropped every
                -- save from the update_cosmetic_slot tap (that tap stays as a
                -- redundant second writer; save_cosmetic dedups). Without this,
                -- loadout_cache (session-only) was the ONLY record of the equip
                -- and the hat/outfit died with the session.
                if LA_PERSIST and career_name then
                    LA_PERSIST.save_cosmetic(career_name, slot_name, backend_id)
                end
                mod._cos925_publish_loadout(items_iface, backend_id, career_name, slot_name, "cosmetic-equip")
                return
            end
            if (slot_name == "slot_hat" or slot_name == "slot_skin") and mod.loadout_cache[career_name] then
                _dbg("[loadout] CLEARED cache %s %s (vanilla bid=%s)", career_name, slot_name, backend_id)
                mod.loadout_cache[career_name][slot_name] = nil
                -- v0.9.83-dev (#520): user intentionally equipped a vanilla item
                -- over the LA one - drop the on-disk entry too, so the next boot
                -- neither rehydrates the cache nor re-injects the LA cosmetic.
                if LA_PERSIST and career_name then
                    LA_PERSIST.clear_cosmetic(career_name, slot_name)
                end
            end
            local result_n, results; local function capture(...) result_n = select("#", ...); results = { ... } end
            capture(func(backend_id, career_name, slot_name))
            mod._cos925_publish_loadout(items_iface, backend_id, career_name, slot_name, "loadout-equip")
            return unpack(results, 1, result_n)
        end)

        mod:hook(items_iface, "get_loadout", function(func, self)
            local loadout = func(self)
            if LA_BRIDGE.registered then
                local all_items = nil
                for career_name, slots in pairs(loadout) do
                    if type(slots) == "table" then
                        for slot_name, bid in pairs(slots) do
                            if LA_BRIDGE.backend_to_armoury[bid] and not (mod.loadout_cache[career_name] and mod.loadout_cache[career_name][slot_name]) then
                                all_items = all_items or items_iface:get_all_backend_items()
                                local vanilla_key = _la_vanilla_fallback(bid, career_name)
                                for vbid, item in pairs(all_items or {}) do
                                    if item.key == vanilla_key and not LA_BRIDGE.backend_to_armoury[vbid] then
                                        slots[slot_name] = vbid
                                        break
                                    end
                                end
                            end
                        end
                    end
                end
            end
            for career_name, slots in pairs(mod.loadout_cache) do
                loadout[career_name] = loadout[career_name] or {}
                for slot_name, backend_id in pairs(slots) do
                    loadout[career_name][slot_name] = backend_id
                end
            end
            return loadout
        end)

        mod:hook(items_iface, "get_loadout_item_id", function(func, self, career_name, slot_name, is_bot)
            -- BOT-LOADOUT FIX (v0.9.39-dev): vanilla get_loadout_item_id(self, career, slot,
            -- is_bot) resolves the BOT's designated loadout when is_bot=true, else the host's
            -- (backend_interface_item_playfab.lua:512/522). The old hook signature DROPPED the
            -- 4th `is_bot` arg, so every bot query fell through with is_bot=nil and resolved the
            -- HOST's loadout -> bots cloned the host's gear instead of using their own. Forward
            -- is_bot, and never let a bot read mod.loadout_cache (career+slot keyed, holds the
            -- LOCAL player's cross-character cosmetics). Identical to the wt v0.12.115 fix; this
            -- path is bridge-gated (_install_skin_loadout_safety), so it covers
            -- Cosmetics-authored sets even when the external LA mod is absent.
            if not is_bot and mod.loadout_cache[career_name] and mod.loadout_cache[career_name][slot_name] then
                return mod.loadout_cache[career_name][slot_name]
            end
            local raw = func(self, career_name, slot_name, is_bot)
            if raw and LA_BRIDGE.registered and LA_BRIDGE.backend_to_armoury[raw] then
                local vanilla_key = _la_vanilla_fallback(raw, career_name)
                if vanilla_key then
                    local all_items = items_iface:get_all_backend_items()
                    for bid, item in pairs(all_items or {}) do
                        if item.key == vanilla_key and not LA_BRIDGE.backend_to_armoury[bid] then
                            _dbg("[loadout] redirected server clone %s -> vanilla %s (%s)", raw, bid, vanilla_key)
                            return bid
                        end
                    end
                end
            end
            return raw
        end)

        mod:hook(items_iface, "get_item_rarity", function(func, self, backend_id)
            local la_key = LA_BRIDGE.backend_to_armoury[backend_id]
            if la_key then
                if la_key:match("_white$") or la_key:match("_Purified$") then
                    return "unique"
                end
                return "promo"
            end
            return func(self, backend_id)
        end)

        local function _fixup_server_clones()
            local all_items = items_iface:get_all_backend_items()
            if not all_items then return end
            local raw_loadout = (function()
                local save = mod.loadout_cache; mod.loadout_cache = {}
                local l = items_iface:get_loadout(); mod.loadout_cache = save; return l
            end)()
            for career_name, slots in pairs(raw_loadout or {}) do
                if type(slots) == "table" then
                    for slot_name, bid in pairs(slots) do
                        if LA_BRIDGE.backend_to_armoury[bid] then
                            local vanilla_key = _la_vanilla_fallback(bid, career_name)
                            for vbid, item in pairs(all_items) do
                                if item.key == vanilla_key and not LA_BRIDGE.backend_to_armoury[vbid] then
                                    _dbg("[loadout] fixup server: %s %s clone %s -> vanilla %s", career_name, slot_name, bid, vbid)
                                    local iface = Managers.backend:get_loadout_interface_by_slot(slot_name)
                                    if iface then iface:set_loadout_item(vbid, career_name, slot_name) end
                                    break
                                end
                            end
                        end
                    end
                end
            end
        end
        _fixup_server_clones()

        -- v0.9.83-dev (#520): REHYDRATE mod.loadout_cache from disk. The cache is
        -- the live source of truth for LA hat/outfit loadout state (get_loadout /
        -- get_loadout_item_id overlay it), but it was session-only - every boot
        -- started empty, so the equipped LA cosmetic fell back to the last REAL
        -- backend item ("the hat I had last equipped prior to that", issue 520).
        -- Rehydrating makes the first spawn's BackendUtils.get_loadout_item
        -- (player_unit_attachment_extension.lua:40) resolve the LA clone directly,
        -- and the hero view shows the LA item as equipped after a restart.
        -- Entries whose clone no longer exists (LA variant removed) are skipped,
        -- mirroring the offhand restore's unresolvable guard.
        if LA_PERSIST and LA_PERSIST.get_all_saved_cosmetics then
            local restored, skipped = 0, 0
            for career_name, slots in pairs(LA_PERSIST.get_all_saved_cosmetics()) do
                if type(slots) == "table" then
                    for slot_name, bid in pairs(slots) do
                        if (slot_name == "slot_hat" or slot_name == "slot_skin")
                            and LA_BRIDGE.backend_to_armoury[bid]
                        then
                            mod.loadout_cache[career_name] = mod.loadout_cache[career_name] or {}
                            mod.loadout_cache[career_name][slot_name] = bid
                            restored = restored + 1
                        else
                            skipped = skipped + 1
                        end
                    end
                end
            end
            if printf and (restored > 0 or skipped > 0) then
                pcall(printf, "[la-state] COSMETIC-RESTORE %d hat/outfit pick(s) rehydrated from disk, %d unresolvable (LA variant missing)",
                    restored, skipped)
            end
        end

        -- Load-time provenance marker (#520): asserted by /cos_regression_test
        -- `cos_la_loadout_equip_capture_wired`.
        mod._la_skin_safety_installed = true
    end

    -- v0.8.57-dev: prevent network sync of LA cosmetic backend_ids to peers.
    -- Crash GUID fa479a72 — friend's vanilla client received an item_names
    -- index our mod had locally registered (e.g. 2959) and crashed in
    -- NetworkLookup.lua:2514's strict __index metamethod when decoding.
    -- Root cause: `CosmeticUtils.update_cosmetic_slot` calls
    -- `player:set_data(slot, name_id)` where `name_id` is
    -- `NetworkLookup.item_names[la_backend_id]` — a LOCAL index our
    -- _la_bridge.register_all added via rawset. Peers don't have that
    -- index → crash on decode.
    -- Fix: hook update_cosmetic_slot, substitute LA backend_ids with their
    -- vanilla equivalent for the sync call. Local player still sees the LA
    -- hat (visual is applied via the loadout_cache + LA's own apply path,
    -- not via sync_data). Husk-side rendering on peers shows the vanilla
    -- equivalent — the closest thing they can render without our mod.
    -- v0.8.59-dev: CosmeticUtils is a PLAIN TABLE (`CosmeticUtils = CosmeticUtils
    -- or {}` at cosmetic_utils.lua:3), not a class. v0.8.58 used string-form
    -- `mod:hook("CosmeticUtils", ...)` which VMF can't resolve for plain tables
    -- — the hook silently never fired and the crash kept reproducing. Same
    -- pitfall as BackendUtils (CLAUDE.md "Hooking" section). Must use the
    -- table-form `mod:hook(CosmeticUtils, ...)` with a nil guard.
    local function _wire_career_for_player(player) return GK_SET.career_for_player(player, LA_PERSIST) end

    if CosmeticUtils then
        mod:hook(CosmeticUtils, "update_cosmetic_slot", function(func, player, slot, item_name, skin_name)
            -- DEVIATION (#1159): resolve the entry's forward-declared LA sender
            -- at the first read. In the entry `_send_la_apply` is declared
            -- `local` far above this hook and only ASSIGNED further down, out of
            -- the _cos_la_sync_transport install; this owner installs ABOVE that
            -- assignment, so an install-time by-value hand-off would capture nil.
            -- The four call sites below stay byte-identical, and nothing in this
            -- hook body reassigns the sender.
            local _send_la_apply = _get_send_la_apply()
            -- v0.9.12-dev: persistence-driven LA injection. On the FIRST
            -- update_cosmetic_slot for a weapon slot in a new session, vanilla
            -- passes the saved vanilla-substitute skin (because PlayFab can't
            -- store LA names). If the player's current weapon backend_id has a
            -- saved LA illusion on disk, swap skin_name in to the LA bid BEFORE
            -- the substitution check below — that way the existing flow paints
            -- LA visuals AND falls through to net-safe vanilla substitution.
            -- Same idea for hat / armor via the per-career table.
            if LA_PERSIST and player and player.player_unit then
                if slot == "slot_hat" or slot == "slot_skin" then
                    if item_name and LA_BRIDGE and LA_BRIDGE.backend_to_armoury
                        and not LA_BRIDGE.backend_to_armoury[item_name]
                    then
                        local career = LA_PERSIST._career_name_for_player(player)
                        local saved = career and LA_PERSIST.get_saved_cosmetic(career, slot)
                        if saved and saved ~= item_name then
                            _dbg("[la-persist] inject %s/%s vanilla(%s) -> LA(%s)",
                                tostring(career), tostring(slot), tostring(item_name), tostring(saved))
                            item_name = saved
                        end
                    end
                else
                    if skin_name and LA_BRIDGE and LA_BRIDGE.backend_to_armoury
                        and not LA_BRIDGE.backend_to_armoury[skin_name]
                    then
                        local inv = ScriptUnit.has_extension(player.player_unit, "inventory_system")
                        local slot_data = inv and inv._equipment and inv._equipment.slots
                            and inv._equipment.slots[slot]
                        local backend_id = slot_data and slot_data.item_data and slot_data.item_data.backend_id
                        local saved = backend_id and LA_PERSIST.get_saved_illusion(backend_id)
                        if saved and saved ~= skin_name then
                            _dbg("[la-persist] inject illusion %s vanilla(%s) -> LA(%s)",
                                tostring(backend_id), tostring(skin_name), tostring(saved))
                            skin_name = saved
                        end
                    end
                end
            end

            -- v0.8.64-dev: substitute BOTH item_name AND skin_name. The original
            -- v0.8.58 hook substituted only item_name (the 4th arg) — but
            -- cosmetic_utils.lua:245 also reads NetworkLookup.weapon_skins[skin_name]
            -- and :249 broadcasts via player:set_data. If the user equips an LA-
            -- cloned weapon ILLUSION, the LA skin_name reaches peers' decode path
            -- and crashes them in the same NetworkLookup __index fashion as the
            -- fa479a72 crash. Same shape of substitution: LA -> vanilla via
            -- backend_to_vanilla; SKIP the call if no fallback exists.
            local effective_item_name = item_name
            local effective_skin_name = skin_name
            local la_item_subbed = false
            local la_skin_subbed = false

            if LA_BRIDGE and LA_BRIDGE.registered then
                if item_name and LA_BRIDGE.backend_to_armoury and LA_BRIDGE.backend_to_armoury[item_name] then
                    local vanilla_key = _la_vanilla_fallback(item_name, _wire_career_for_player(player))
                    if vanilla_key then
                        _dbg("[net-safe] update_cosmetic_slot %s LA item(%s) -> vanilla(%s)",
                            tostring(slot), tostring(item_name), tostring(vanilla_key))
                        effective_item_name = vanilla_key
                        la_item_subbed = true
                    else
                        _dbg("[net-safe] update_cosmetic_slot %s LA item(%s) -> SKIP (no vanilla fallback)",
                            tostring(slot), tostring(item_name))
                        return
                    end
                end
                if skin_name and LA_BRIDGE.backend_to_armoury and LA_BRIDGE.backend_to_armoury[skin_name] then
                    local vanilla_skin = _la_vanilla_fallback(skin_name, _wire_career_for_player(player))
                    if vanilla_skin then
                        _dbg("[net-safe] update_cosmetic_slot %s LA skin(%s) -> vanilla(%s)",
                            tostring(slot), tostring(skin_name), tostring(vanilla_skin))
                        effective_skin_name = vanilla_skin
                        la_skin_subbed = true
                    else
                        _dbg("[net-safe] update_cosmetic_slot %s LA skin(%s) -> SKIP (no vanilla fallback)",
                            tostring(slot), tostring(skin_name))
                        return
                    end
                end
            end

            -- v0.9.76-dev (#421): ct_* custom-illusion keys live in _custom_skin_keys,
            -- NOT in LA_BRIDGE.backend_to_armoury, so the LA branch above never catches
            -- them. Vanilla then encodes skin_id = NetworkLookup.weapon_skins[skin_name]
            -- (cosmetic_utils.lua:205-209) and writes it into the player_sync_data game
            -- object (cosmetic_utils.lua:230-251) - a GameSession field synced to EVERY
            -- peer. A peer WITHOUT cosmetics_tweaker decodes it back through the strict
            -- lookup on the playerlist/inspect read path (CosmeticUtils.get_cosmetic_slot
            -- -> get_weapon_skin_name, cosmetic_utils.lua:168-178) and fatals: the same
            -- crash class as the rpc_add_equipment axis, on a different channel.
            -- Substitute the universal vanilla "n/a" key (peers see no illusion; the
            -- local visual never reads sync data). UNCONDITIONAL - never toggle-gated
            -- (issue 371 / BUG_CLASSES 31).
            local ct_skin_subbed
            effective_skin_name, ct_skin_subbed = mod._cos_wire_safe_custom_skin(
                effective_skin_name, "update_cosmetic_slot " .. tostring(slot))

            -- v0.8.64-dev: peer-replay path for armor (slot_skin). slot_skin is
            -- "cosmetic" category, NOT "attachment", so it doesn't flow through
            -- PUAE or AttachmentUtils.hot_join_sync — those only emit cos_la_apply
            -- for hats. Fire it here so peers can replay the LA armor texture
            -- paint on the husk player_unit body. Also record into _local_la_equips
            -- so the hot_join_sync hook can re-emit to joining peers.
            if la_item_subbed and item_name and player and player.player_unit
                and Unit.alive(player.player_unit) and _send_la_apply
            then
                local kind = nil
                if slot == "slot_hat"  then kind = "hat"   end
                if slot == "slot_skin" then kind = "armor" end
                if kind then
                    local armoury_key = LA_BRIDGE.backend_to_armoury[item_name]
                    local equips = _local_la_equips[player.player_unit]
                    if not equips then equips = {}; _local_la_equips[player.player_unit] = equips end
                    equips[slot] = item_name
                    _send_la_apply(player.player_unit, slot, kind, armoury_key, effective_item_name)
                    -- v0.9.12-dev: persist to disk so the LA hat / armor survives
                    -- the next game restart. Per-career keying mirrors vanilla's
                    -- own loadout-per-career model.
                    -- v0.9.83-dev (#520): this tap is now the REDUNDANT writer -
                    -- the authoritative save moved to the set_loadout_item hook
                    -- (career_name is an argument there). Career resolution here
                    -- runs during the loadout-resync window where profile_by_peer
                    -- returns nil; the failure must be VISIBLE, not silent.
                    local career_name = LA_PERSIST._career_name_for_player(player)
                    if career_name then
                        LA_PERSIST.save_cosmetic(career_name, slot, item_name)
                    elseif printf then
                        pcall(printf, "[la-persist] WARN save skipped (career unresolved) slot=%s item=%s",
                            tostring(slot), tostring(item_name))
                    end
                end
            end

            -- v0.8.66-dev: peer-replay path for WEAPON ILLUSIONS (row-1 picker).
            -- When the user equips an LA-cloned weapon illusion, skin_name (NOT
            -- item_name) is the LA bid. v0.8.64 substituted it to vanilla for
            -- crash-safety but never told peers to repaint, so peers saw vanilla
            -- color on the wielded weapon. Fire kind="illusion" with the LA
            -- armoury_key derived from skin_name. Record in _local_la_equips
            -- keyed by the cosmetic slot ("slot_melee" / "slot_ranged" etc.) so
            -- hot_join_sync can replay to joiners.
            if la_skin_subbed and skin_name and not la_item_subbed
                and player and player.player_unit and Unit.alive(player.player_unit)
                and _send_la_apply
            then
                local armoury_key = LA_BRIDGE.backend_to_armoury[skin_name]
                if armoury_key then
                    local equips = _local_la_equips[player.player_unit]
                    if not equips then equips = {}; _local_la_equips[player.player_unit] = equips end
                    equips[slot] = skin_name
                    _send_la_apply(player.player_unit, slot, "illusion", armoury_key, effective_skin_name)
                    -- v0.9.12-dev: persist LA illusion per backend_id so the same
                    -- weapon instance keeps its LA skin on next game restart. Works
                    -- for vanilla weapons AND CIM-forged modded weapons (CIM's
                    -- forged_weapons save covers the item itself; this covers the
                    -- LA illusion overlay vanilla can't represent).
                    local inv = ScriptUnit.has_extension(player.player_unit, "inventory_system")
                    local slot_data = inv and inv._equipment and inv._equipment.slots
                        and inv._equipment.slots[slot]
                    local backend_id = slot_data and slot_data.item_data and slot_data.item_data.backend_id
                    if backend_id then LA_PERSIST.save_illusion(backend_id, skin_name) end
                end
            end

            -- v0.9.0-dev: LA->vanilla swap on a slot must clear the stale LA cache
            -- entry. Previously the `equips[slot] = item_name` write at lines
            -- 3284/3305 only happened inside the la_*_subbed branches; equipping
            -- a vanilla replacement left the prior LA bid in _local_la_equips,
            -- and the next hot_join_sync would replay it to joiners even though
            -- the wearer is no longer wearing LA.
            if not la_item_subbed and not la_skin_subbed
                and player and player.player_unit
            then
                local equips = _local_la_equips[player.player_unit]
                local had_local_la = equips and equips[slot] or nil
                if had_local_la then
                    _dbg("[net-safe] update_cosmetic_slot %s: clearing stale LA cache entry %s",
                        tostring(slot), tostring(equips[slot]))
                    equips[slot] = nil
                end
                -- v0.9.69-dev (#265, LA_SYNC_CORE_AUDIT Slice 1 / I2): revert must
                -- BROADCAST, not just clear local state. Guarded to the LOCAL
                -- human player (bots share the host peer_id -- a bot career swap
                -- must not revert the host's slots) and to slots that actually
                -- held LA state (locally tracked this session OR still present in
                -- the synced store from an earlier session/persistence restore).
                do
                    local pm_r = Managers and Managers.player
                    local lp_r = _local_player_safe(pm_r)
                    if lp_r and player == lp_r and mod._send_la_revert then
                        local had_synced = lp_r.peer_id and _la_equips_by_peer[lp_r.peer_id]
                            and _la_equips_by_peer[lp_r.peer_id][slot] ~= nil
                        if had_local_la or had_synced then
                            local kind = (slot == "slot_hat" and "hat")
                                or (slot == "slot_skin" and "armor") or "illusion"
                            mod._send_la_revert(player.player_unit, slot, kind,
                                (kind == "illusion") and skin_name or item_name, nil)
                        end
                    end
                end
                -- v0.9.12-dev: persistence parity for the clear path. If the user
                -- equips a vanilla item over a previously-saved LA one, the on-disk
                -- entry must be cleared too — otherwise next restart re-applies a
                -- cosmetic the user already unequipped.
                if slot == "slot_hat" or slot == "slot_skin" then
                    -- v0.9.83-dev (#520): redundant clear (authoritative clear
                    -- lives in the set_loadout_item hook); log resolution loss.
                    local career_name = LA_PERSIST._career_name_for_player(player)
                    if career_name then
                        LA_PERSIST.clear_cosmetic(career_name, slot)
                    elseif printf then
                        pcall(printf, "[la-persist] WARN clear skipped (career unresolved) slot=%s",
                            tostring(slot))
                    end
                else
                    local inv = ScriptUnit.has_extension(player.player_unit, "inventory_system")
                    local slot_data = inv and inv._equipment and inv._equipment.slots
                        and inv._equipment.slots[slot]
                    local backend_id = slot_data and slot_data.item_data and slot_data.item_data.backend_id
                    if backend_id then LA_PERSIST.clear_illusion(backend_id) end
                end
            end

            if la_item_subbed or la_skin_subbed or ct_skin_subbed then
                return func(player, slot, effective_item_name, effective_skin_name)
            end
            return func(player, slot, item_name, skin_name)
        end)
        -- Fourth #421 encode surface. The three rpc_add_equipment senders are
        -- owned by _cos_wire; this GameSession sender shares its pure policy and
        -- publishes the same regression/diagnostic ownership registry.
        mod._cos_skin_wire_surfaces.update_cosmetic_slot = true
    end

    -- v0.8.60-dev: SECOND sync path. SimpleInventoryExtension.add_equipment
    -- calls CosmeticUtils.update_cosmetic_slot (caught by the hook above)
    -- AND then immediately calls LoadoutUtils.sync_loadout_slot, which
    -- broadcasts an `rpc_sync_loadout_slot` RPC with
    -- `item_id = NetworkLookup.item_names[item.key]`. Peers receive the LOCAL
    -- index that only the user's session knows → same crash mode as the
    -- SyncData path. Substitute the item with a shadow whose `.key` is the
    -- vanilla equivalent before the RPC fires. Same protection also blocks
    -- LoadoutUtils.hot_join_sync, which iterates loadouts and re-invokes
    -- sync_loadout_slot for each newly-joined peer.
    --
    -- LoadoutUtils is also a PLAIN TABLE (`LoadoutUtils = LoadoutUtils or {}`),
    -- so use table-form hook with nil guard — same BackendUtils/CosmeticUtils
    -- pitfall as the previous version.
    if LoadoutUtils then
        mod:hook(LoadoutUtils, "sync_loadout_slot", function(func, player, slot_name, item, sync_to_specific_peer_id)
            if mod._cos_send_custom_skin_hands then
                mod._cos_send_custom_skin_hands(player and player.player_unit,
                    item, item and item.skin, "sync_loadout_slot")
            end
            if item and item.key
                and LA_BRIDGE and LA_BRIDGE.registered
                and LA_BRIDGE.backend_to_armoury
                and LA_BRIDGE.backend_to_armoury[item.key]
            then
                local vanilla_key = _la_vanilla_fallback(item.key, _wire_career_for_player(player))
                if vanilla_key then
                    local shadow = {}
                    for k, v in pairs(item) do shadow[k] = v end
                    shadow.key = vanilla_key
                    _dbg("[net-safe] sync_loadout_slot %s LA(%s) -> vanilla(%s)",
                        tostring(slot_name), tostring(item.key), tostring(vanilla_key))
                    return func(player, slot_name, shadow, sync_to_specific_peer_id)
                end
                _dbg("[net-safe] sync_loadout_slot %s LA(%s) -> SKIP (no vanilla fallback)",
                    tostring(slot_name), tostring(item.key))
                return
            end
            return func(player, slot_name, item, sync_to_specific_peer_id)
        end)
    end

    local owner = {
        install_skin_loadout_safety = _install_skin_loadout_safety,
        la_vanilla_fallback         = _la_vanilla_fallback,
        wire_career_for_player      = _wire_career_for_player,
    }
    mod._cos_la_loadout_safety_owner = owner
    return owner
end

return CosLaLoadoutSafety
