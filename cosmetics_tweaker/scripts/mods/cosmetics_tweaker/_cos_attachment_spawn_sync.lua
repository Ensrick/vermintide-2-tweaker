-- _cos_attachment_spawn_sync.lua - attachment-slot LA spawn/sync owner.
--
-- RESPONSIBILITY
-- Owns every engine seam at which an ATTACHMENT-category cosmetic (in practice
-- slot_hat) is spawned onto, or synchronised onto, a player body. At each of
-- those four seams the same two-step contract runs: resolve the Loremaster's
-- Armoury identity BEFORE vanilla spawns, then re-emit the LA apply AFTER
-- vanilla returns, so whichever of the racing RPCs lands second still leaves
-- the LA-textured unit visible.
--
--   * HUSK SPAWN - PlayerHuskAttachmentExtension.create_attachment. Pre-patches
--     item_data.unit to the cached LA mesh so vanilla spawns it directly (the
--     v0.9.0.9 idempotency fix for the rpc_create_attachment / cos_la_apply
--     race), gates on same-character skeletons, defers instead of dropping when
--     the body skeleton is not ready, then paints the LA texture and enrolls the
--     spawned hat with the appearance-fade runtime.
--   * LOCAL GAME-OBJECT INIT - PlayerUnitAttachmentExtension.game_object_initialized.
--     Substitutes each LA-keyed attachment name for its vanilla wire key across
--     the vanilla call, restores the originals, then emits one LA apply per slot.
--   * RESYNC - PlayerUnitAttachmentExtension.spawn_resynced_loadout. The same
--     substitute / restore / emit contract for the single resynced attachment.
--   * HOT JOIN - AttachmentUtils.hot_join_sync. The same contract for the
--     joining peer's view. Vanilla's hot_join_sync walks ONLY attachment-category
--     slots, so the non-attachment replay (slot_skin armor, weapon-slot offhand
--     picks, weapon-illusion paints, the targeted per-joiner cos_la_apply burst
--     and the glow rebroadcast) is bolted to this same seam and cannot be split
--     off without changing when it runs. It travels with the hook that carries it.
--
-- Extracted VERBATIM from cosmetics_tweaker.lua (entry lines 5159-5630 at
-- dc213743) with no behaviour change. Exactly ONE statement differs from the
-- original text, the accessor hand-off described under ENTRY-OWNED STATE below.
-- mod:dofile is not a singleton - the entry calls this installer EXACTLY once, at
-- the exact point the block previously executed, so hook registration order and
-- the load-time log ordering keep their original timing. There is deliberately no
-- re-install guard: a second install would register duplicate hooks that VMF
-- silently drops, which is precisely what a second dofile of the old inline block
-- did.
--
-- HOOKS OWNED (each hooked EXACTLY ONCE in the whole mod - VMF silently drops a
-- second hook on the same Class/method pair):
--   PlayerHuskAttachmentExtension.create_attachment       (full hook)
--   PlayerUnitAttachmentExtension.game_object_initialized (full hook)
--   PlayerUnitAttachmentExtension.spawn_resynced_loadout  (full hook)
--   AttachmentUtils.hot_join_sync                         (full hook, table form)
-- AttachmentUtils is a PLAIN TABLE, so the table-form-plus-nil-guard registration
-- is load-bearing and is preserved verbatim; the string form silently never
-- registers. The two `_net_safe_hook_status` field writes that record whether
-- those registrations happened are likewise preserved, and the entry still reads
-- them for its startup verification line (see ENTRY-OWNED STATE).
--
-- ENTRY-OWNED STATE
--   deps.get_la_pending_apply()
--     `_la_pending_apply` is an entry local that is REBOUND, not just mutated:
--     both drain sites (the revert receiver and mod.update) rebuild the queue and
--     assign the survivors back over the local. A by-value hand-off at install
--     time would capture the table that the FIRST drain discards, and every later
--     husk-hat deferral would be appended to an orphan the drain never reads. The
--     queue is therefore fetched through the accessor at enqueue time. This is the
--     single deviation from the original text.
--   deps.net_safe_hook_status
--     Handed over BY REFERENCE on purpose. This owner writes .PUAE and
--     .AttachmentUtils; the entry's "[net-safe] hook registration" startup line
--     and its incomplete-registration warning read all four fields off the same
--     table a few lines after this install call.
--   deps.send_la_apply
--     Handed over BY VALUE, unlike _cos_customization_view_lifecycle's getter.
--     `_send_la_apply` is forward-declared near the top of the entry but its real
--     assignment (entry line 2960) executes ~2200 lines ABOVE this install call,
--     so the value is already live here and is never reassigned afterwards. The
--     ordering is not left to inspection: test_cos_attachment_spawn_sync pins the
--     assignment site to a position before the install call, so a future reorder
--     fails the suite instead of silently handing over nil.
--   deps.la_equips_by_peer / local_la_equips / offhand_selection
--     By value. Each is bound once above this install call and only ever mutated
--     in place afterwards, so one shared table reference stays correct.
--
-- COMPOSES WITH, DOES NOT OVERLAP, the sibling owners:
--   _cos_appearance_fade_runtime  hooks PlayerUnitAttachmentExtension.create_attachment
--                                 (the LOCAL body) and SimpleHuskInventoryExtension
--                                 ._reapply_fade. This owner hooks the HUSK class's
--                                 create_attachment and calls the fade runtime's
--                                 enroll/install API - different classes, no shared pair.
--   _cos_attachment_link_policy   the attachment_utils.link node partition. Disjoint
--                                 method; this owner never touches node linking.
--   _cos_customization_view_lifecycle / _cos_offhand_picker / _cos_modded_illusion_swap
--                                 the HeroWindowItemCustomization screen. This owner
--                                 registers no UI hook at all.
--   _cos_glow_transport           owns the per-peer glow RPC transport. The hot-join
--                                 seam only CALLS mod._glow_rebroadcast_targeted; it
--                                 registers no network handler and no RPC of its own.
--   _cos_la_replay_runtime        owns the reconcile/replay state machine. This owner
--                                 is a set of spawn-time emitters that feed it.
-- `_cos_husk_wield_runtime` owns SimpleHuskInventoryExtension._wield_slot (the
-- husk WEAPON path), while `_cos_spawn_boundary` owns
-- AttachmentUtils.create_attachment (the #270 residency gate on optional
-- attachments); neither is an attachment-slot LA spawn/sync seam.
--
-- Owned by: cosmetics_tweaker.lua entry point.
-- Consumed via: one ordered install call at the former inline position; guarded by
-- qa/lua/tests/test_cos_attachment_spawn_sync.lua.

local AttachmentSpawnSync = {}

function AttachmentSpawnSync.install(mod, deps)
    deps = deps or {}

    local APPEARANCE_FADE_RUNTIME = deps.appearance_fade_runtime
    local COS_RPC_SCHEMA          = deps.rpc_schema
    local CUSTOM_HATS             = deps.custom_hats
    local GK_SET                  = deps.gk_set
    local LA_BRIDGE               = deps.la_bridge
    local LA_PERSIST              = deps.la_persist
    local _dbg                    = deps.dbg
    local _dbg_alert              = deps.dbg_alert
    local _is_local_server        = deps.is_local_server
    local _la_equips_by_peer      = deps.la_equips_by_peer
    local _la_substitute_name     = deps.la_substitute_name
    local _la_vanilla_fallback    = deps.la_vanilla_fallback
    local _level_world            = deps.level_world
    local _local_la_equips        = deps.local_la_equips
    local _local_player_safe      = deps.local_player_safe
    local _net_safe_hook_status   = deps.net_safe_hook_status
    local _offhand_selection      = deps.offhand_selection
    local _offhand_session_state  = deps.offhand_session_state
    local _resolve_la_variant     = deps.resolve_la_variant
    local _send_la_apply          = deps.send_la_apply

    -- Rebound by the entry, never captured by value. See ENTRY-OWNED STATE above.
    local _get_la_pending_apply   = deps.get_la_pending_apply

    -- Map an LA-keyed attachment slot to its cos_la_apply kind. Currently only
    -- slot_hat flows through the attachment path; slot_skin is "cosmetic"
    -- category and arrives via CosmeticUtils.update_cosmetic_slot instead.
    local function _attachment_slot_to_kind(slot_name)
        if slot_name == "slot_hat" then return "hat" end
        return nil
    end

    -- PUAE is a class, string-form hook is correct.
    -- v0.9.0.9-hotfix: husk-side LA-aware create_attachment.
    --
    -- ROOT CAUSE diagnosed by hat-reequip-diagnosis agent (HAT_REEQUIP_REQUIRED_DIAGNOSIS.md):
    -- Race between vanilla `rpc_create_attachment` and CT `cos_la_apply` on the client:
    --   1. Client receives cos_la_apply FIRST → CT spawns LA-textured hat unit, paint ok.
    --   2. Vanilla rpc_create_attachment arrives LATE → husk's create_attachment sees the
    --      LA unit as old_slot_data → `remove_attachment` destroys it (and the LA paint
    --      bound to that unit's materials) → spawns fresh vanilla unit. Net result:
    --      vanilla-colored hat on the client view of the husk.
    -- Re-equip works because by then only one RPC pair is in flight (no late vanilla
    -- RPC follows CT's spawn).
    --
    -- Fix: hook PlayerHuskAttachmentExtension.create_attachment. When the wearer
    -- has a cached LA hat entry in _la_equips_by_peer (populated on every peer by
    -- the v0.9.0.7 mirror write), pre-patch `item_data.unit = la_unit_path` BEFORE
    -- delegating to vanilla — so vanilla spawns the LA mesh — then apply the
    -- texture on the result. This makes the late vanilla RPC IDEMPOTENT with CT's
    -- earlier apply: whichever RPC arrives second still ends up with the LA-textured
    -- unit visible.
    mod:hook("PlayerHuskAttachmentExtension", "create_attachment", function(func, self, slot_name, item_data)
        if slot_name ~= "slot_hat" then
            return func(self, slot_name, item_data)
        end
        local pm = Managers and Managers.player
        local husk_unit = self and self._unit
        if not pm or not husk_unit then
            return func(self, slot_name, item_data)
        end
        local wearer_player = mod._cos_husk_identity.player_for_unit(pm, husk_unit)
        local wearer_peer = wearer_player and wearer_player.peer_id
        local cached = wearer_peer and _la_equips_by_peer
            and _la_equips_by_peer[wearer_peer]
            and _la_equips_by_peer[wearer_peer][slot_name]
        if not cached or cached.kind ~= "hat" or not cached.armoury_key then
            return func(self, slot_name, item_data)
        end
        local career_ok, career_reason, active_career =
            mod._cos_husk_identity.validate_live_entry(
                cached, husk_unit, ScriptUnit, Managers, LA_PERSIST)
        if not career_ok then
            if printf then printf("[cos:698] HUSK hat SKIP wearer=%s active=%s reason=%s",
                tostring(wearer_peer), tostring(active_career), tostring(career_reason)) end
            return func(self, slot_name, item_data)
        end
        -- #697: (variant, la) via the shared resolver - `la` is non-nil ONLY when
        -- the key resolved from LA's own SKIN_LIST (mirrors _apply_la_on_unit).
        local variant, la = _resolve_la_variant(cached.armoury_key)
        local la_unit = variant and variant.new_units and variant.new_units[1]
        -- #612: the late husk attachment uses the exact Laurel donor; only its
        -- spawned material instances are changed below.
        if CUSTOM_HATS and CUSTOM_HATS.is_custom_identity(cached.armoury_key) then
            la_unit = CUSTOM_HATS.spawn_unit(Application, "remote-husk")
        end
        if not la_unit then
            return func(self, slot_name, item_data)
        end

        -- v0.9.8.5 CRASH FIX: character-mismatch gate.
        --
        -- The cached LA hat's mesh is authored for ONE specific character's
        -- skeleton. Attaching it to a body with a different skeleton makes
        -- vanilla's `Unit.node(unit, "j_spine1")` C-call fail because the
        -- expected attachment node IDs don't exist on the wrong skeleton.
        --
        -- This happens when a bot replaces a player in Chaos Wastes deus
        -- runs (or any time vanilla spawns a `player_bot_unit` with a
        -- different career than the host previously customized for). The
        -- `_la_equips_by_peer[wearer_peer]` cache holds the host's LAST
        -- chosen LA hat, but the BOT'S spawn brings a unit path for the
        -- bot's character — different from the cached LA hat's character.
        --
        -- Crash trace 2026-05-22 00:35:24 (d82119d4) AND 2026-05-22 01:11:28
        -- (95a8db3d): Sienna bot spawned (`bright_wizard_necromancer`
        -- skeleton), our hook patched the unit to
        -- `way_watcher_maiden_guard/headpiece/...` (Kerillian's hat),
        -- engine: `UnitApi node failed, node #ID[3cfac529] not found in
        -- unit #ID[...]` at `c_api_unit.cpp:74`.
        --
        -- Detection: the unit path encodes the character key as the first
        -- segment after `units/beings/player/`. If incoming (vanilla item_
        -- data.unit) and cached (la_unit) character keys differ, bail —
        -- delegate to vanilla unpatched. The wearer renders their actual
        -- character's hat; user's LA selection waits for the next wearer-
        -- side equip event to re-apply on a matching skeleton.
        --
        -- Audit 2026-05-22 found 4 unsafe patches across 2 logs; 2 crashed
        -- (Sienna body), 2 didn't (Saltzpyre body — node ID overlap with
        -- Kerillian). All 4 patterns are now defused by this gate.
        local incoming_char = item_data.unit
            and string.match(item_data.unit, "^units/beings/player/([^/]+)/")
        local la_char       = string.match(la_unit, "^units/beings/player/([^/]+)/")
        if incoming_char and la_char and incoming_char ~= la_char then
            _dbg("[husk-hat-create] character mismatch — wearer=%s incoming=%s cached_LA=%s (armoury=%s) — skipping cross-skeleton patch to avoid c_api_unit.cpp:74 crash",
                tostring(wearer_peer), tostring(incoming_char), tostring(la_char), tostring(cached.armoury_key))
            return func(self, slot_name, item_data)
        end

        -- v0.9.8.8 CRASH FIX: husk body-skeleton readiness guard.
        --
        -- Vanilla AttachmentUtils.link (attachment_utils.lua:70) calls
        -- Unit.node(owner_unit, link_data.source) for each hat-link entry. On
        -- hot-join / mid-revive the husk BODY skeleton isn't yet populated, so the
        -- source node (j_spine family) is transiently absent and Unit.node ENGINE-
        -- FATALS at c_api_unit.cpp:74 -- bypassing the pcall below (CLAUDE.md
        -- "Unit.node errors bypass pcall"). The v0.9.8.5 gate above defends the
        -- TARGET hat-mesh nodes; it does NOT cover this body-side not-ready case
        -- (same-character es_gk_hat_04->es_gk_hat_03 sails through it and still
        -- fatals -- crash GUID 9533f856, questing_knight_hat_1001 in the CW keep).
        --
        -- Unlike the removed v0.9.8.3 precheck (which returned WITHOUT calling
        -- vanilla -> "no helmet visible"), a miss here DEFERS: we call vanilla
        -- UNPATCHED so the wearer's real hat shows now, and enqueue an LA re-apply
        -- so the LA hat lands once the spine populates. The hat is never dropped.
        local _attach_owner = husk_unit
        do
            local _item_tmpl = BackendUtils and BackendUtils.get_item_template
                and BackendUtils.get_item_template(item_data)
            -- Mirror player_husk_attachment_extension.lua:61-62: link_to_skin hats
            -- parent to the third-person mesh, not the body. Check the SAME unit
            -- vanilla will pass to AttachmentUtils.link as `owner`.
            if _item_tmpl and _item_tmpl.link_to_skin then
                local _mesh = self._tp_unit_mesh
                if _mesh and Unit.alive(_mesh) then
                    _attach_owner = _mesh
                end
            end
            -- The source node names are plain Lua data (attachment_utils.lua:26-27
            -- reads this same table) -- derive them up front and verify each with
            -- Unit.has_node (the non-fatal boolean companion) BEFORE the fatal call.
            local _required_body_nodes
            local _linking = _item_tmpl and _item_tmpl.attachment_node_linking
                and _item_tmpl.attachment_node_linking[slot_name]
            if _linking then
                for _, ld in ipairs(_linking) do
                    if type(ld.source) == "string" then
                        _required_body_nodes = _required_body_nodes or {}
                        _required_body_nodes[#_required_body_nodes + 1] = ld.source
                    end
                end
            end
            -- Proxy when the template carries no explicit linking: every player body
            -- anchors hats off the spine family, so j_spine is the readiness probe.
            if not _required_body_nodes then
                _required_body_nodes = { "j_spine" }
            end
            local _body_ready = Unit.alive(_attach_owner)
            if _body_ready then
                for _, n in ipairs(_required_body_nodes) do
                    if not Unit.has_node(_attach_owner, n) then
                        _body_ready = false
                        break
                    end
                end
            end
            if not _body_ready then
                _dbg_alert("[husk-hat-create] body skeleton not ready (missing source node) wearer=%s slot=%s armoury=%s -- DEFERRING re-apply, NOT dropping hat",
                    tostring(wearer_peer), tostring(slot_name), tostring(cached.armoury_key))
                -- Enqueue an LA re-apply (drained per-frame in mod.update, 5s
                -- deadline-bounded). Tuple shape matches the canonical enqueue.
                -- #1159 boundary deviation: the entry REBINDS _la_pending_apply at both drain sites, so the queue is fetched through the accessor at enqueue time.
                local _pending = _get_la_pending_apply()
                _pending[#_pending + 1] = {
                    wearer_peer, slot_name, cached.kind, cached.armoury_key, cached.vanilla_key, os.clock() + 5,
                }
                -- Vanilla runs UNPATCHED: the wearer's real hat shows THIS frame;
                -- the LA override lands a frame or two later via _try_apply_by_peer.
                return func(self, slot_name, item_data)
            end
        end

        -- v0.9.8.7: Patch item_data.unit in place and call vanilla.
        --
        -- Removed the v0.9.8.3 skeleton-readiness precheck. Reasoning:
        -- the original j_spine1 crash was caused by patching a WRONG-CHARACTER
        -- LA hat onto a body whose skeleton's node IDs didn't match the hat
        -- mesh's expected nodes. v0.9.8.5's character-mismatch gate (above)
        -- prevents that crash class at the source. With same-character
        -- hats only being patched, vanilla's attachment node lookup succeeds.
        --
        -- The v0.9.8.3 precheck was overcautious and harmful: when it
        -- triggered (frequently on hot-join / mid-revive), it returned
        -- WITHOUT calling vanilla — so the husk got NO hat at all. That's
        -- the "no helmet visible" symptom users reported.
        --
        -- pcall around vanilla call remains as a last-resort safety net.
        -- If vanilla truly errors for some unexpected edge case, we don't
        -- want to propagate up and crash the client.
        local prev_unit = item_data.unit
        item_data.unit = la_unit
        _dbg("[husk-hat-create] wearer=%s slot=%s patched unit %s -> %s (LA armoury=%s)",
            tostring(wearer_peer), tostring(slot_name), tostring(prev_unit), tostring(la_unit), tostring(cached.armoury_key))
        local ok, err = pcall(func, self, slot_name, item_data)
        item_data.unit = prev_unit
        if not ok then
            _dbg_alert("[husk-hat-create] inner create_attachment errored on wearer=%s slot=%s: %s — bailing silently",
                tostring(wearer_peer), tostring(slot_name), tostring(err))
            return
        end
        local spawned_slot = self._attachments and self._attachments.slots
            and self._attachments.slots[slot_name]
        local spawned_hat = spawned_slot and spawned_slot.unit
        if CUSTOM_HATS.is_custom_identity(cached.armoury_key) then
            CUSTOM_HATS.apply_surface(spawned_hat, "remote-husk")
        end
        if GK_SET and GK_SET.resolve_variant(cached.armoury_key) and spawned_hat then
            GK_SET.apply_variant_to_unit(cached.armoury_key, spawned_hat, "remote_husk")
        end
        -- Paint the LA texture onto the just-spawned hat unit (mirrors the
        -- _apply_la_on_unit hat branch). #697: la=nil for cosmetics-side variants
        -- (GK_SET/CUSTOM_HATS paint above; LA funcs.lua:65 nil-derefs foreign keys).
        if la and type(la.apply_new_skin_from_texture) == "function" then
            local world = _level_world()
            local slot_data = self._attachments and self._attachments.slots and self._attachments.slots[slot_name]
            local hat_unit = slot_data and slot_data.unit
            if world and hat_unit and Unit.alive(hat_unit) then
                LA_BRIDGE._bridge_active = true
                local paint_ok, paint_err = pcall(la.apply_new_skin_from_texture, cached.armoury_key, world, cached.vanilla_key, hat_unit)
                LA_BRIDGE._bridge_active = false
                _dbg("[husk-hat-create] paint %s on hat_unit=%s ok=%s",
                    tostring(cached.armoury_key), tostring(hat_unit), tostring(paint_ok))
                if not paint_ok then
                    _dbg_alert("[husk-hat-create] paint err key=%s vanilla=%s: %s", tostring(cached.armoury_key), tostring(cached.vanilla_key), tostring(paint_err)) -- #697: key must ride the printf-backed channel
                end
            end
        elseif not la then
            _dbg("[husk-hat-create] LA paint n/a for %s (cosmetics-side variant, #697)", tostring(cached.armoury_key))
        end
        APPEARANCE_FADE_RUNTIME.enroll_husk_attachment(husk_unit, self, spawned_hat)
    end)

    APPEARANCE_FADE_RUNTIME.install({
        identity = mod._cos_husk_identity,
        get_store = function() return _la_equips_by_peer end,
        la_persist = LA_PERSIST,
    })

    -- v0.9.8.7: the v0.9.8.4 + v0.9.8.6 PlayerHuskAttachmentExtension.remove_attachment
    -- guard pair has been removed entirely.
    --
    -- The guard existed to handle the case where v0.9.8.3's skeleton-readiness
    -- precheck silently bailed — leaving `_attachments.slots[slot_name]` nil
    -- when vanilla then tried to remove a hat that was never created.
    --
    -- v0.9.8.7 removed the v0.9.8.3 precheck (rendered unnecessary by
    -- v0.9.8.5's character-mismatch gate which prevents the original crash
    -- class). Without the precheck, vanilla always populates `_attachments.slots`
    -- normally — so this guard has no failure mode left to defend against.
    -- Removing it eliminates one more layer of speculative hook code that
    -- could regress in subtle ways.

    mod:hook("PlayerUnitAttachmentExtension", "game_object_initialized", function(func, self, unit, unit_go_id)
        local slots = self._attachments and self._attachments.slots
        local restore = nil
        local la_slots = nil  -- entries: { slot_name, la_backend_id, vanilla_key }
        if slots then
            for slot_name, slot_data in pairs(slots) do
                local item_data = slot_data and slot_data.item_data
                local orig = item_data and item_data.name
                local career = mod._la_career_for_unit and mod._la_career_for_unit(unit); local vanilla = _la_substitute_name(orig, career)
                if vanilla then
                    restore = restore or {}
                    restore[#restore + 1] = { item_data, orig }
                    item_data.name = vanilla
                    la_slots = la_slots or {}
                    la_slots[#la_slots + 1] = { slot_name, orig, vanilla }
                end
            end
        end
        local ok, err = pcall(func, self, unit, unit_go_id)
        if restore then
            for i = 1, #restore do
                restore[i][1].name = restore[i][2]
            end
        end
        if not ok then error(err) end
        if la_slots then
            for i = 1, #la_slots do
                local slot_name, la_id, vanilla = la_slots[i][1], la_slots[i][2], la_slots[i][3]
                local kind = _attachment_slot_to_kind(slot_name)
                local armoury_key = LA_BRIDGE.backend_to_armoury and LA_BRIDGE.backend_to_armoury[la_id]
                if kind and armoury_key then
                    _send_la_apply(unit, slot_name, kind, armoury_key, vanilla)
                end
            end
        end
    end)

    mod:hook("PlayerUnitAttachmentExtension", "spawn_resynced_loadout", function(func, self, item_to_spawn)
        local item_data = item_to_spawn and item_to_spawn.item_data
        local orig = item_data and item_data.name
        local career = mod._la_career_for_unit and mod._la_career_for_unit(self._unit); local vanilla = _la_substitute_name(orig, career)
        if vanilla then
            item_data.name = vanilla
            local ok, err = pcall(func, self, item_to_spawn)
            item_data.name = orig
            if not ok then error(err) end
            local slot_name = item_to_spawn.slot_id
            local kind = slot_name and _attachment_slot_to_kind(slot_name)
            local armoury_key = LA_BRIDGE.backend_to_armoury and LA_BRIDGE.backend_to_armoury[orig]
            if kind and armoury_key and self._unit then
                _send_la_apply(self._unit, slot_name, kind, armoury_key, vanilla)
            end
            return
        end
        return func(self, item_to_spawn)
    end)
    _net_safe_hook_status.PUAE = true

    -- AttachmentUtils is a PLAIN TABLE (`AttachmentUtils = AttachmentUtils or {}`
    -- at attachment_utils.lua:1). Same string-form pitfall as CosmeticUtils/
    -- LoadoutUtils — must use table-form with nil guard, else hook silently
    -- never registers.
    if AttachmentUtils then
        mod:hook(AttachmentUtils, "hot_join_sync", function(func, peer_id, unit, slots, synced_buffs)
            local restore = nil
            local la_slots = nil  -- entries: { slot_name, la_backend_id, vanilla_key }
            if slots then
                for slot_name, slot_data in pairs(slots) do
                    local orig = slot_data and slot_data.name
                    local career = mod._la_career_for_unit and mod._la_career_for_unit(unit); local vanilla = _la_substitute_name(orig, career)
                    if vanilla then
                        restore = restore or {}
                        restore[#restore + 1] = { slot_data, orig }
                        slot_data.name = vanilla
                        la_slots = la_slots or {}
                        la_slots[#la_slots + 1] = { slot_name, orig, vanilla }
                    end
                end
            end
            local ok, err = pcall(func, peer_id, unit, slots, synced_buffs)
            if restore then
                for i = 1, #restore do
                    restore[i][1].name = restore[i][2]
                end
            end
            if not ok then error(err) end
            -- v0.8.67-dev: signature change — _send_la_apply now routes through
            -- the host (server-authoritative). The host's broadcast to "all"
            -- includes the joining peer, so per-peer targeting is no longer
            -- needed. Each existing peer's hot_join_sync still fires its own
            -- emits for its own equips; the host receives each request, records
            -- in _la_equips_by_peer (idempotent overwrite), and re-broadcasts.
            -- Slight redundancy (each peer's equips broadcast to everyone again
            -- on each new joiner), but correct.
            if la_slots then
                for i = 1, #la_slots do
                    local slot_name, la_id, vanilla = la_slots[i][1], la_slots[i][2], la_slots[i][3]
                    local kind = _attachment_slot_to_kind(slot_name)
                    local armoury_key = LA_BRIDGE.backend_to_armoury and LA_BRIDGE.backend_to_armoury[la_id]
                    if kind and armoury_key then
                        _send_la_apply(unit, slot_name, kind, armoury_key, vanilla)
                    end
                end
            end

            -- Replay non-attachment LA cosmetics (slot_skin armor, weapon-slot
            -- offhand picks, weapon-illusion paints). AttachmentUtils.hot_join_sync
            -- only walks "attachment"-category slots so these need explicit replay.
            --
            -- v0.9.0-dev: previously read ONLY `_local_la_equips[unit]`, which is
            -- populated solely by the local player's CosmeticUtils.update_cosmetic_slot
            -- hook → contains entries only for the LOCAL player's player_unit. When
            -- the host's hot_join_sync iterates OTHER existing players to replay
            -- their state to the new joiner, the lookup misses for every non-local
            -- unit, so the new joiner never received those peers' armor/illusion
            -- selections. Now we ALSO consult `_la_equips_by_peer` (authoritative
            -- per-peer store, populated by the host's cos_la_apply_req handler) and
            -- replay every recorded slot for the wearer-peer.
            do
                local equips = _local_la_equips[unit]
                if equips then
                    for slot_name, la_id in pairs(equips) do
                        local kind = nil
                        if slot_name == "slot_skin" then
                            kind = "armor"
                        elseif slot_name ~= "slot_hat" then
                            kind = "illusion"
                        end
                        local armoury_key = LA_BRIDGE.backend_to_armoury and LA_BRIDGE.backend_to_armoury[la_id]
                        local career = mod._la_career_for_unit and mod._la_career_for_unit(unit); local vanilla = _la_vanilla_fallback(la_id, career)
                        if (kind == "armor" or kind == "illusion") and armoury_key then
                            _send_la_apply(unit, slot_name, kind, armoury_key, vanilla)
                        end
                    end
                end

                -- v0.9.0.12-hotfix: TARGETED hot-join replay to the joining peer.
                -- Previous version called _send_la_apply which always uses "all" —
                -- but at hot_join_sync time the joiner may not yet be in the
                -- "all" target list (handshake not complete). User report v0.9.0.11:
                -- "someone joining a lobby where the hat or shield is already
                -- equipped won't see it until the other player changes their
                -- cosmetic selection". The change-broadcast hits because by then
                -- the joiner is fully connected; the initial hot-join replay
                -- raced and lost. Fix: bypass _send_la_apply, fire
                -- cos_la_apply DIRECTLY targeted at the joining peer_id.
                if _is_local_server() then
                    local pm = Managers and Managers.player
                    local owner = pm and pm.owner and pm:owner(unit)
                    local wearer_peer = owner and owner.peer_id
                    local peer_equips = wearer_peer and _la_equips_by_peer[wearer_peer]
                    if peer_equips then
                        local n = 0
                        for slot_name, entry in pairs(peer_equips) do
                            if entry and entry.kind and entry.armoury_key then
                                mod:network_send("cos_la_apply", peer_id, COS_RPC_SCHEMA, {
                                    wearer_peer_id = wearer_peer,
                                    slot           = slot_name,
                                    kind           = entry.kind,
                                    armoury_key    = entry.armoury_key,
                                    vanilla_key    = entry.vanilla_key,
                                    hand_field     = entry.hand_field,
                                    wearer_career  = entry.wearer_career,
                                })
                                n = n + 1
                            end
                        end
                        if n > 0 then
                            _dbg("[hot-join replay] sent %d cos_la_apply entries targeted at joiner=%s for wearer=%s",
                                n, tostring(peer_id), tostring(wearer_peer))
                        end
                    end
                    -- v0.9.0.12-hotfix: glow rebroadcast also targeted at joiner.
                    if mod._glow_rebroadcast_targeted then
                        mod._glow_rebroadcast_targeted(peer_id)
                    end
                end

                -- Offhand: replay the local player's CURRENTLY-wielded weapon
                -- backend if it has an LA offhand selection.
                local pm = Managers and Managers.player
                local local_player = _local_player_safe(pm)
                local local_unit = local_player and local_player.player_unit
                if local_unit == unit then
                    local inv = ScriptUnit.has_extension(unit, "inventory_system")
                    local equipment = inv and inv._equipment
                    local wielded_slot = equipment and equipment.wielded_slot
                    local slot_data = wielded_slot and equipment.slots and equipment.slots[wielded_slot]
                    local item_data = slot_data and slot_data.item_data
                    local bid = item_data and item_data.backend_id
                    if bid then _offhand_session_state.migrate_legacy(bid) end
                    local per_hand_sel = bid and _offhand_selection[bid]
                    if type(per_hand_sel) == "table" then
                        -- v0.9.72-dev: key the replay by the weapon TEMPLATE, not
                        -- the wielded slot. This site was the only writer of the
                        -- legacy "slot_melee"-style offhand keys (host 18:35:44
                        -- evidence) - a namespace the weapon-identity guard in
                        -- _apply_la_on_unit can never match to an item.
                        local replay_key = (item_data and item_data.template) or wielded_slot
                        for hand_field, sel in pairs(per_hand_sel) do
                            if type(sel) == "table" and sel.la_armoury_key then
                                _send_la_apply(unit, replay_key, "offhand",
                                    sel.la_armoury_key, sel.vanilla_skin, hand_field)
                            elseif type(sel) == "table" and type(sel.unit) == "string"
                                    and sel.unit ~= "" and mod._send_offhand_mesh then
                                mod._send_offhand_mesh(unit, replay_key,
                                    hand_field, sel.unit)
                            end
                        end
                    end
                end
            end
        end)
        _net_safe_hook_status.AttachmentUtils = true
    end
    return true
end

return AttachmentSpawnSync
