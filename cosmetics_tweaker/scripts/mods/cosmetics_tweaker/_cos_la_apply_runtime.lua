-- _cos_la_apply_runtime.lua - LA appearance apply / revert / reconcile runtime.
--
-- RESPONSIBILITY
-- Owns the render side of a stored LA (Loremaster's Armoury) appearance entry:
-- turning an entry in the synced store into pixels on a live body, and putting
-- the body back to vanilla when the entry goes away. One responsibility, two
-- directions:
--
--   * APPLY - `_apply_la_on_unit` is the unified apply core. Every inbound
--     trigger (the cos_la_apply broadcast, the pending-queue replay, the
--     transition walk, the husk wield re-paint, the local wield re-apply)
--     converges here, which is why the #518 deus-yield gate and the #14
--     cross-skeleton character gate can each sit at exactly one place. It
--     dispatches the four LA kinds: hat (attachment teardown + create +
--     paint), armor (body texture or Grail Knight authored variant), offhand
--     and illusion (the #204 mesh-mismatch warp guard, then the 3P + 1P paint
--     pair from #203).
--
--   * REVERT - `mod._la_native_pulse` (slot-level re-equip so vanilla
--     re-resolves an un-painted mesh), `mod._la_restore_native_hat`
--     (residency-gated native hat re-attach), and `mod._la_apply_revert_recv`
--     (the authoritative revert receiver: delete the store entry, purge any
--     queued re-apply for the same wearer+slot so a pending retry cannot
--     re-impose what was just reverted, then restore per kind).
--
-- `mod._la_reconcile` is the seam between the two: the single render-reconcile
-- entry point (#264 / LA_SYNC_CORE_AUDIT Slice 2, invariant I3) that reads the
-- store, resolves the wearer, applies, and decides whether a stale kind="unit"
-- mesh may be pulsed now or must be deferred to the pending drain.
--
-- Apply and revert travel together because they share three pieces of private
-- state and machinery that exist for no other reason:
--   `_offhand_reswap_state` (the per-owner pulse cooldown + try-cap weak table)
--   is written by BOTH `_ensure_offhand_mesh` (keyed by armoury_key) and
--   `mod._la_native_pulse` (keyed "__native__"); splitting them would leave a
--   shared mutable cooldown table on the entry serving two different owners.
--   `_apply_la_on_unit` is called by the reconcile path and by
--   `_try_apply_by_peer`, and `_ensure_offhand_mesh` is called by both
--   reconcile and the revert-side pulse. Nothing outside this file reads any
--   of the six locals declared here.
--
-- Extracted VERBATIM from cosmetics_tweaker.lua (entry lines 3131-3813 at
-- 4e10b56f) with no behaviour change. NO original statement was modified: the
-- move adds FOUR lines and changes none, each marked DEVIATION inline and all
-- four described under ENTRY-OWNED STATE below. mod:dofile is not a singleton,
-- so the entry calls this installer EXACTLY once.
--
-- INSTALL POSITION
-- The installer runs at the exact line the moved block used to start. The block
-- contained NO registration of any kind - no mod:hook, mod:hook_safe,
-- mod:hook_origin, mod:command, mod:network_register or mod:dofile - so the
-- mod-wide registration cardinality AND order are unchanged by construction,
-- not merely by inspection. The nearest registrations bracket it: the
-- SimpleHuskInventoryExtension.init hook_safe ~100 lines above, and the
-- _cos_la_replay_runtime install immediately below, which the entry comment
-- pins as having to sit "immediately after the canonical _la_reconcile HOW
-- owner". Installing here keeps that adjacency exactly.
--
-- ENTRY-OWNED STATE
--   deps.get_la_pending_apply / deps.set_la_pending_apply
--     A late-binding accessor PAIR, not a value. `_la_pending_apply` is the LA
--     retry queue, and its drain sites REBIND it (`_la_pending_apply = kept`)
--     rather than mutating in place - one of those drains is inside this file
--     (`mod._la_apply_revert_recv`), the other stays on the entry (mod.update).
--     A by-value hand-off would break in BOTH directions: this owner would
--     append to a table the entry's drain had already discarded, and this
--     owner's own purge would be invisible to the entry. The getter is
--     resolved once per call at the exact statement that used to perform the
--     first inline read; the setter is called immediately after the untouched
--     rebind statement so the entry's local becomes the same new table. The
--     entry already hands the same getter to _cos_attachment_spawn_sync for
--     this exact reason.
--   deps.la_equips_by_peer
--     By value, and provably safe. The synced store is declared `= {}` at entry
--     line 1376 and reassigned exactly once, at FILE SCOPE (entry line 2365,
--     `_la_equips_by_peer = _la_equips_by_peer or {}`), which cannot change the
--     identity because the left side is already a truthy table. That statement
--     executes ~750 lines ABOVE this install call, so the table this owner
--     captures is the final one. The two sibling owners installed just below
--     (_cos_la_replay_runtime) and further down (_cos_attachment_spawn_sync)
--     already take it by value on the same proof.
--   Everything else in deps
--     By value. Each is a `local function` or a module handle bound above the
--     install call and never reassigned anywhere in the entry (verified by a
--     file-scope assignment scan, not by eye).
--
-- NOT OWNED HERE (deliberate)
--   `_cos_la_husk_identity_runtime` owns `mod._la_wielded_item_matches`, the
--   weapon-identity guard shared with `_cos_husk_wield_runtime`.
--   `_cos_spawn_boundary` owns AttachmentUtils.create_attachment. This owner
--   CALLS the guard through `mod.`, and calls the attachment extension's own
--   `ext.create_attachment` method, which is a different engine seam.
--
-- DEAD-CODE NOTE (carried across unchanged, deliberately)
--   `_try_apply_by_peer` has no call site anywhere in the mod. The v0.9.66-dev
--   comment in mod.update that says "Now we call `_try_apply_by_peer`" was made
--   stale by v0.9.70-dev, which routed that walk through `mod._la_reconcile`
--   instead. It is moved verbatim rather than deleted: this slice is a pure
--   structural move, and removing a function is a behaviour question (however
--   small) that belongs in its own change with its own review.
--
-- Consumed via: one ordered install call at the former block position. Exports
-- stay on `mod` (`_la_native_pulse`, `_la_restore_native_hat`,
-- `_la_apply_revert_recv`, `_la_reconcile`), so every existing consumer -
-- the cos_la_apply receiver, the pending drain, the transition walk, the husk
-- and local wield paths - resolves them exactly as before.

local LaApplyRuntime = {}

function LaApplyRuntime.install(mod, deps)
    deps = deps or {}

    local CUSTOM_HATS                     = assert(deps.custom_hats, "custom_hats is required")
    local GK_SET                          = assert(deps.gk_set, "gk_set is required")
    local LA_BRIDGE                       = assert(deps.la_bridge, "la_bridge is required")
    local LA_REPLAY_POLICY                = assert(deps.la_replay_policy, "la_replay_policy is required")
    local PROBE                           = deps.probe
    local _apply_authored_offhand_to_unit = assert(deps.apply_authored_offhand_to_unit, "apply_authored_offhand_to_unit is required")
    local _dbg                            = assert(deps.dbg, "dbg is required")
    local _dbg_alert                      = assert(deps.dbg_alert, "dbg_alert is required")
    local _la_chars_compatible            = assert(deps.la_chars_compatible, "la_chars_compatible is required")
    local _la_equips_by_peer              = assert(deps.la_equips_by_peer, "la_equips_by_peer is required")
    local _level_world                    = assert(deps.level_world, "level_world is required")
    local _offhand_paint_mesh_ok          = assert(deps.offhand_paint_mesh_ok, "offhand_paint_mesh_ok is required")
    local _override_package_ready         = assert(deps.override_package_ready, "override_package_ready is required")
    local _purge_stale_peer_slot          = assert(deps.purge_stale_peer_slot, "purge_stale_peer_slot is required")
    local _resolve_authored_offhand_mesh  = assert(deps.resolve_authored_offhand_mesh, "resolve_authored_offhand_mesh is required")
    local _resolve_la_variant             = assert(deps.resolve_la_variant, "resolve_la_variant is required")
    local _trace_paint                    = assert(deps.trace_paint, "trace_paint is required")
    local _unit_mesh_name                 = assert(deps.unit_mesh_name, "unit_mesh_name is required")
    local _wearer_unit_for_peer           = assert(deps.wearer_unit_for_peer, "wearer_unit_for_peer is required")

    -- The rebound LA retry queue crosses the chunk boundary as an accessor PAIR,
    -- never as an install-time value. See ENTRY-OWNED STATE in the header.
    local _get_la_pending_apply = assert(deps.get_la_pending_apply, "get_la_pending_apply is required")
    local _set_la_pending_apply = assert(deps.set_la_pending_apply, "set_la_pending_apply is required")

    -- Unified apply core. All inbound paths (cos_la_apply broadcast + pending-
    -- queue replay) converge here. Returns true if applied, false if the target
    -- unit isn't ready (caller can re-queue).
    local function _apply_la_on_unit(owner_unit, slot_name, kind, armoury_key, vanilla_key)
        if not (owner_unit and Unit.alive(owner_unit)) then return false end
        if not (LA_BRIDGE and LA_BRIDGE.registered) then return false end

        -- #518: TERMINAL deus-yield for weapon-side kinds. Every apply trigger
        -- (cos_la_apply recv, _la_reconcile, transition walk, pending drain, husk
        -- wield re-paint, local wield re-apply) funnels through this function, so
        -- one gate here guarantees no LA offhand/illusion render can stomp a
        -- deus-rolled upgrade skin. Hats/armor pass through untouched. Dedup'd
        -- printf so the suppression is visible with mod logging OFF.
        if (kind == "offhand" or kind == "illusion") and mod._la_deus_weapon_yield() then
            local seen = mod._la_deus_yield_logged
            if not seen then seen = {}; mod._la_deus_yield_logged = seen end
            local sk = tostring(slot_name) .. "|" .. tostring(armoury_key)
            if not seen[sk] and printf then
                seen[sk] = true
                printf("[la-state] DEUS-YIELD suppressed slot=%s kind=%s key=%s (CW upgrade cosmetics win, #518)",
                    tostring(slot_name), tostring(kind), tostring(armoury_key))
            end
            return false
        end

        local variant, la = _resolve_la_variant(armoury_key)
        if not variant then
            _dbg("[cos_la_apply] %s armoury_key %s missing from local SKIN_LIST — bail",
                tostring(kind), tostring(armoury_key))
            return false
        end

        if kind == "hat" then
            if variant.swap_hand ~= "hat" then return false end
            local la_unit_path = variant.new_units and variant.new_units[1]
            -- #612: Encarmine deliberately resolves to the exact Laurel donor.
            if CUSTOM_HATS and CUSTOM_HATS.is_custom_identity(armoury_key) then
                la_unit_path = CUSTOM_HATS.spawn_unit(Application, "appearance-replay")
            end
            if not la_unit_path then return false end

            -- v0.9.13-dev: guard now delegates to the pure helper
            -- `_la_chars_compatible` so the same decision is unit-testable in
            -- isolation. See its docstring for the contract. Inline doc below
            -- preserved for context on WHY this guard exists at all.
            --
            -- v0.9.11-dev CRASH/VISUAL FIX: character-mismatch gate (rewritten).
            --
            -- The v0.9.8.8 guard derived `owner_char_path` from `vanilla_key`'s
            -- IML entry — but `vanilla_key` is the CACHED LA emit's vanilla
            -- substitute (the EMITTER's hat), not the OWNER's character. For
            -- host-owned bots whose career differs from the host's, both the
            -- cached LA mesh AND `vanilla_key.unit` resolve to the host's
            -- character paths, so the comparison was a tautology that always
            -- passed. Result: GK LA hat attached to host's WP bot at mission
            -- start (host view only). Issue #14.
            --
            -- Correct source for the OWNER's character: the owner_unit's
            -- currently-attached vanilla slot_hat item_data.unit. That unit
            -- was spawned for THIS body, so its path encodes the body's
            -- character_career composite (e.g. "witch_hunter_priest" vs LA's
            -- cached "empire_soldier_breton"). If the bot doesn't have a
            -- vanilla hat yet (early-spawn race), fall back to SPProfiles
            -- via the owner's Player + profile_index, matching la_char's
            -- first segment against profile.unit_name (character base).
            -- If neither resolves, bail — safer than wrong-skeleton attach.
            do
                local owner_char_path
                local ext_peek = ScriptUnit and ScriptUnit.has_extension
                    and ScriptUnit.has_extension(owner_unit, "attachment_system")
                local existing = ext_peek and ext_peek._attachments
                    and ext_peek._attachments.slots
                    and ext_peek._attachments.slots[slot_name]
                local existing_item_data = existing and existing.item_data
                if existing_item_data and existing_item_data.unit then
                    owner_char_path = existing_item_data.unit
                end
                local profile_base
                if not owner_char_path then
                    local pm = Managers and Managers.player
                    local player = pm and pm.owner and pm:owner(owner_unit)
                    local profile_index = player and player.profile_index
                        and (type(player.profile_index) == "function"
                            and player:profile_index() or player.profile_index)
                    local profile = profile_index and rawget(_G, "SPProfiles")
                        and SPProfiles[profile_index]
                    profile_base = profile and profile.unit_name
                end
                local ok, reason = _la_chars_compatible(owner_char_path, la_unit_path, profile_base)
                if not ok then
                    _dbg("[cos_la_apply hat] character mismatch — %s (armoury=%s) — skipping cross-skeleton patch",
                        tostring(reason), tostring(armoury_key))
                    return false
                end
            end

            -- v0.8.64-dev: husks render 3P. v0.8.62 checked only the 1P path,
            -- which is why "LA hats invisible on peers" reproduced — the 1P
            -- path was present on the wearer but the 3P attachment path the
            -- husk uses sometimes wasn't loaded on the viewer. Verify BOTH.
            local can_get = Application and Application.can_get
            local has_1p = can_get and can_get("unit", la_unit_path)
            local path_3p = la_unit_path .. "_3p"
            local has_3p = can_get and can_get("unit", path_3p)
            if not has_1p and not has_3p then
                _dbg("[cos_la_apply hat] %s: neither %s nor %s loadable — bail",
                    tostring(armoury_key), tostring(la_unit_path), tostring(path_3p))
                return false
            end
            local clone_key = (ItemMasterList and rawget(ItemMasterList, armoury_key) and armoury_key)
                or (vanilla_key and ItemMasterList and rawget(ItemMasterList, vanilla_key) and vanilla_key)
            if not clone_key then
                _dbg("[cos_la_apply hat] %s: no usable IML clone source — bail", tostring(armoury_key))
                return false
            end
            local ext = ScriptUnit.has_extension(owner_unit, "attachment_system")
            if not ext or not ext.create_attachment then return false end
            -- v0.9.0-dev: tear down the prior attachment in this slot before
            -- creating the new one. AttachmentUtils.create_attachment errors with
            -- "Slot is not empty, remove attachment before creating a new one"
            -- when a previous hat is still bound — observed on PC-A across
            -- Pureheart_helm / Hippogryph_helm sequential equips. Bypass the
            -- public ext:remove_attachment() because that fires rpc_remove_attachment
            -- to peers; every cos_la_apply receiver would re-broadcast, amplifying
            -- traffic. Direct destroy + nil the slot mirrors the local cleanup
            -- remove_attachment() does, minus the RPC.
            local existing_slot = ext._attachments and ext._attachments.slots and ext._attachments.slots[slot_name]
            if existing_slot then
                if AttachmentUtils and AttachmentUtils.destroy_attachment then
                    pcall(AttachmentUtils.destroy_attachment, ext._world, ext._unit, existing_slot)
                end
                ext._attachments.slots[slot_name] = nil
            end
            local item_data = table.clone(ItemMasterList[clone_key])
            item_data.unit = la_unit_path
            local ok, err = pcall(ext.create_attachment, ext, slot_name, item_data)
            if not ok then
                _dbg_alert("[cos_la_apply hat] create_attachment %s failed: %s",
                    tostring(armoury_key), tostring(err))
            end
            if CUSTOM_HATS and CUSTOM_HATS.is_custom_identity(armoury_key) then
                local slot_data = ext._attachments and ext._attachments.slots
                    and ext._attachments.slots[slot_name]
                local hat_unit = slot_data and slot_data.unit
                CUSTOM_HATS.apply_surface(hat_unit, "appearance-replay")
            end
            local authored_variant = GK_SET and GK_SET.resolve_variant(armoury_key)
            if authored_variant then
                local slot_data = ext._attachments and ext._attachments.slots and ext._attachments.slots[slot_name]
                local hat_unit = slot_data and slot_data.unit
                if hat_unit and Unit.alive(hat_unit) then
                    GK_SET.apply_variant_to_unit(authored_variant, hat_unit, "appearance_replay")
                end
            end
            -- v0.9.0.3-hotfix: paint the LA texture onto the JUST-CREATED HAT
            -- ATTACHMENT UNIT (not the wearer's player_unit). LA's
            -- apply_new_skin_from_texture iterates `Unit.num_meshes(unit)` on the
            -- passed unit and writes textures to those meshes. For armor, the
            -- player body's own meshes carry the armor texture so passing
            -- owner_unit works. For hats, the hat is a SEPARATE attached unit
            -- (vanilla AttachmentUtils.create_attachment spawns it and stores
            -- the ref in slot_data.unit) — passing owner_unit paints the player
            -- body's meshes (no-op for hat textures). The just-created hat unit
            -- lives at ext._attachments.slots[slot_name].unit.
            if not (CUSTOM_HATS and CUSTOM_HATS.is_custom_identity(armoury_key))
                and la and type(la.apply_new_skin_from_texture) == "function" then
                local world = _level_world()
                local slot_data = ext._attachments and ext._attachments.slots and ext._attachments.slots[slot_name]
                local hat_unit = slot_data and slot_data.unit
                if world and ok and hat_unit and Unit.alive(hat_unit) then
                    LA_BRIDGE._bridge_active = true
                    local paint_ok, paint_err = pcall(la.apply_new_skin_from_texture, armoury_key, world, vanilla_key, hat_unit)
                    LA_BRIDGE._bridge_active = false
                    _dbg("[cos_la_apply hat] paint %s on hat_unit=%s ok=%s",
                        tostring(armoury_key), tostring(hat_unit), tostring(paint_ok))
                    if not paint_ok then
                        _dbg_alert("[cos_la_apply hat] paint err: %s", tostring(paint_err))
                    end
                else
                    _dbg("[cos_la_apply hat] paint skipped: world=%s ok=%s hat_unit=%s alive=%s",
                        tostring(world ~= nil), tostring(ok), tostring(hat_unit),
                        tostring(hat_unit and Unit.alive(hat_unit)))
                end
            end
            return true
        end

        if kind == "armor" then
            if variant.swap_hand ~= "armor" then return false end
            if GK_SET and GK_SET.resolve_variant(armoury_key) then
                return GK_SET.apply_armor_to_owner(owner_unit, "appearance_replay", armoury_key)
            end
            if not la or type(la.apply_new_skin_from_texture) ~= "function" then return false end
            local world = _level_world()
            if not world then return false end
            LA_BRIDGE._bridge_active = true
            local ok, err = pcall(la.apply_new_skin_from_texture, armoury_key, world, vanilla_key, owner_unit)
            LA_BRIDGE._bridge_active = false
            if not ok then
                _dbg_alert("[cos_la_apply armor] %s on %s failed: %s",
                    tostring(armoury_key), tostring(owner_unit), tostring(err))
            end
            return true
        end

        if kind == "offhand" then
            local inv = ScriptUnit.has_extension(owner_unit, "inventory_system")
            local equipment = inv and inv._equipment
            -- v0.9.72-dev WEAPON-IDENTITY GUARD (2026-07-06 18:27/18:34 session):
            -- this branch painted whatever left-hand unit was CURRENTLY wielded,
            -- ignoring which weapon the stored entry belongs to - while the store
            -- keys the same pick under THREE namespaces (weapon item key,
            -- template key, and a legacy wielded-slot key like "slot_melee" from
            -- the hot-join replay; host 18:35:44.704 shows such an entry live).
            -- Any recv/retry/transition reconcile firing while a DIFFERENT weapon
            -- was in hand painted the illusion onto that weapon. Only paint when
            -- the wielded item actually matches the stored key; otherwise return
            -- false (pending retry keeps it briefly; the next wield of the RIGHT
            -- weapon re-applies via the wield reconcile).
            -- v0.9.85-dev (#514): the v0.9.72 guard read `inv.wielded_slot`, a
            -- field that exists ONLY on SimpleHuskInventoryExtension - on the
            -- LOCAL wearer w_item was always nil and the `if w_item then` shape
            -- fell through PERMISSIVE, painting the currently wielded left-hand
            -- unit (Bret-shield pick wrapped around CWV Sword and Mace's mace at
            -- spawn replay). Now resolved via mod._la_wielded_item_matches
            -- (equipment.wielded_slot on both classes) and RESTRICTIVE when the
            -- wielded item is unresolvable: skip + re-queue, never paint blind.
            local match, w_item = mod._la_wielded_item_matches(inv, equipment, slot_name, false)
            if not match then
                local seen = mod._la_gate_seen
                if not seen then seen = {}; mod._la_gate_seen = seen end
                local w_tpl = w_item and w_item.template
                local sk = "offhand-wrongweapon|" .. tostring(slot_name) .. "|" .. tostring(w_tpl)
                if not seen[sk] and printf then
                    seen[sk] = true
                    printf("[la-state] APPLY SKIP wrong-weapon: entry key=%s but wielded template=%s name=%s (kind=offhand armoury=%s)",
                        tostring(slot_name), tostring(w_tpl), tostring(w_item and w_item.name), tostring(armoury_key))
                end
                return false
            end
            local left_unit = equipment and equipment.left_hand_wielded_unit_3p
            if not left_unit or not Unit.alive(left_unit) then
                -- v0.9.0.3-hotfix: silenced. Previously logged per retry → the
                -- pending-queue's per-frame retry of an offhand equip while host
                -- isn't wielding the shield spammed 24+ lines per equip until the
                -- 5-second TTL expired. The behavior is correct (drops cleanly on
                -- TTL); the noise was loud. Returning false re-queues; pending
                -- queue runner drops the entry quietly on TTL.
                return false
            end
            local world = _level_world()
            if not world then return false end
            -- v0.9.54-dev (#203, trace-confirmed): paint BOTH the 3P and the 1P
            -- wielded shield units. A HUSK has no 1P unit (left_hand_wielded_unit is
            -- nil), so this is unchanged for the husk path; but the LOCAL player —
            -- whose own #203 wield re-apply routes through here — SEES the shield in
            -- FIRST PERSON, and the 0.9.53 trace showed create_equipment's working
            -- "ingame" paint hits both units (3P `..._mesh_3p` AND 1P `..._mesh`).
            -- Painting only the 3P would never restore what the user actually sees.
            local targets, painted = { left_unit }, false
            local left_1p = equipment and equipment.left_hand_wielded_unit
            if left_1p and Unit.alive(left_1p) then targets[#targets + 1] = left_1p end
            for _, target in ipairs(targets) do
                -- v0.9.54-dev (#204): MESH-MISMATCH WARP GUARD on the husk / peer /
                -- local re-apply paint. This path paints via the un-gated
                -- "network_husk" context, which ASSUMES the get_item_units mesh-swap
                -- already replaced the vanilla shield with the LA custom mesh. For an
                -- authored shield whose mesh-swap was SKIPPED (_resolve_authored_offhand_mesh
                -- not ready, or a non-bret shield weapon — "Empire Sword and Shield" —
                -- whose offhand swap didn't fire), painting the heraldry onto the
                -- un-swapped VANILLA shield warps the texture onto the wrong model.
                -- Refuse to paint a kind="unit" LA texture onto a unit whose authored
                -- mesh is NOT the variant's custom mesh (generalizes the #150 BUG1/2
                -- gate from the local-body/previewer contexts to this peer/husk path).
                -- The WORKING bret husk swaps successfully → mesh matches → gate
                -- passes (no regression); kind="texture" variants and units with an
                -- unreadable mesh name stay permissive (return true).
                if not _offhand_paint_mesh_ok(target, armoury_key) then
                    _dbg("[cos_la_apply offhand] SKIP %s on %s — mesh is NOT the swapped LA mesh (warp guard #204)",
                        tostring(armoury_key), tostring(target))
                    -- _trace_paint routes through mod:info (visible with
                    -- output_mode_debug OFF) and dumps target_mesh vs expected
                    -- new_units[1] so the empire-shield case is pinned in the log.
                    _trace_paint("network_husk", "network_husk", nil, target, armoury_key, "SKIP-mesh-mismatch")
                    -- [cos:sync] #204: peer/husk offhand paint refused because the
                    -- mesh-swap didn't fire (empire-shield warp case). peer=husk.
                    if PROBE then
                        PROBE.emit("cos:sync",
                            "husk_offhand/" .. tostring(armoury_key) .. "/" .. tostring(target),
                            string.format("peer=husk ctx=network_husk key=%s unit=%s decision=SKIP reason=mesh-mismatch(warp-guard)",
                                tostring(armoury_key), tostring(target)))
                    end
                else
                    LA_BRIDGE._bridge_active = true
                    local call_ok, paint_result = pcall(_apply_authored_offhand_to_unit,
                        world, target, armoury_key, vanilla_key, "network_husk")
                    LA_BRIDGE._bridge_active = false
                    local ok = call_ok and paint_result == true
                    if PROBE then
                        PROBE.emit("cos:sync",
                            "husk_offhand/" .. tostring(armoury_key) .. "/" .. tostring(target),
                            string.format("peer=husk ctx=network_husk key=%s unit=%s decision=PAINT outcome=%s",
                                tostring(armoury_key), tostring(target), tostring(ok)))
                    end
                    if not call_ok then
                        _dbg_alert("[cos_la_apply offhand] %s on %s failed: %s",
                            tostring(armoury_key), tostring(target), tostring(paint_result))
                    end
                    -- v0.9.43-dev PAINT trace (husk/network path). On the CLIENT this
                    -- paints the host's shield onto the husk's wielded left-hand unit,
                    -- which by this point has already been mesh-swapped to the LA mesh
                    -- by the husk get_item_units branch — so match=true is expected.
                    _trace_paint("network_husk", "network_husk", nil, target, armoury_key, ok)
                    painted = painted or ok
                end
            end
            return painted
        end

        if kind == "illusion" then
            local authored = GK_SET and GK_SET.resolve_variant(armoury_key)
            if authored then
                local inv = ScriptUnit.has_extension(owner_unit, "inventory_system")
                local equipment = inv and inv._equipment
                local match = mod._la_wielded_item_matches(inv, equipment, slot_name, true)
                if not match then return false end
                local applied = false
                for _, target in ipairs({
                    equipment and equipment.left_hand_wielded_unit_3p,
                    equipment and equipment.left_hand_wielded_unit,
                }) do
                    if target and Unit.alive(target) then
                        applied = GK_SET.apply_variant_to_unit(authored, target, "wielded_shield") or applied
                    end
                end
                return applied
            end
            if not la or type(la.apply_new_skin_from_texture) ~= "function" then return false end
            local inv = ScriptUnit.has_extension(owner_unit, "inventory_system")
            local equipment = inv and inv._equipment
            -- v0.9.72-dev WEAPON-IDENTITY GUARD (see offhand branch): illusion
            -- entries are keyed by the COSMETIC SLOT ("slot_melee"/"slot_ranged",
            -- from update_cosmetic_slot); only paint when that slot is the one
            -- currently wielded (or the key matches the wielded item directly).
            -- v0.9.85-dev (#514): same fix as the offhand branch - resolve the
            -- wielded slot via mod._la_wielded_item_matches (equipment.wielded_slot;
            -- `inv.wielded_slot` is husk-only, so this guard was dead on the local
            -- wearer) and skip RESTRICTIVELY when the wielded item is unresolvable.
            -- allow_slot_key=true keeps the designed slot-key match for illusion
            -- entries.
            local match, w_item = mod._la_wielded_item_matches(inv, equipment, slot_name, true)
            if not match then
                local seen = mod._la_gate_seen
                if not seen then seen = {}; mod._la_gate_seen = seen end
                local w_slot_name = (equipment and equipment.wielded_slot) or inv.wielded_slot
                local sk = "illusion-wrongweapon|" .. tostring(slot_name) .. "|" .. tostring(w_slot_name)
                if not seen[sk] and printf then
                    seen[sk] = true
                    printf("[la-state] APPLY SKIP wrong-weapon: entry key=%s but wielded slot=%s template=%s (kind=illusion armoury=%s)",
                        tostring(slot_name), tostring(w_slot_name), tostring(w_item and w_item.template), tostring(armoury_key))
                end
                return false
            end
            local right_unit = equipment and equipment.right_hand_wielded_unit_3p
            local left_unit_w = equipment and equipment.left_hand_wielded_unit_3p
            if (not right_unit or not Unit.alive(right_unit))
                and (not left_unit_w or not Unit.alive(left_unit_w)) then
                _dbg("[cos_la_apply illusion] %s on owner %s: no live wielded weapon unit",
                    tostring(armoury_key), tostring(owner_unit))
                return false  -- re-queue: next wield will spawn
            end
            local world = _level_world()
            if not world then return false end
            LA_BRIDGE._bridge_active = true
            for _, target in ipairs({ right_unit, left_unit_w }) do
                if target and Unit.alive(target) then
                    local ok, err = pcall(la.apply_new_skin_from_texture, armoury_key, world, vanilla_key, target)
                    if not ok then
                        _dbg_alert("[cos_la_apply illusion] %s on %s failed: %s",
                            tostring(armoury_key), tostring(target), tostring(err))
                    end
                end
            end
            LA_BRIDGE._bridge_active = false
            return true
        end

        _dbg_alert("[cos_la_apply] unknown kind %s — ignored", tostring(kind))
        return false
    end

    local function _try_apply_by_peer(wearer_peer_id, slot_name, kind, armoury_key, vanilla_key)
        local unit = _wearer_unit_for_peer(wearer_peer_id)
        if not unit then return false end
        return _apply_la_on_unit(unit, slot_name, kind, armoury_key, vanilla_key)
    end

    -- v0.9.64-dev (#233/#234): POST-SPAWN OFFHAND MESH RE-SWAP.
    -- A kind="unit" LA shield gets its MESH swapped only in the spawn-time
    -- BackendUtils.get_item_units path; a later texture-paint (husk repaint / local
    -- wield-reapply) can only recolor, so when the live offhand unit still carries the
    -- PREVIOUS (or vanilla) mesh the #204 warp-guard refuses the paint and the swap
    -- silently no-ops -- #233 (host's shield spawns on the client before the client has
    -- the host's entry) and #234 (mid-mission model change). This forces the mesh to
    -- re-resolve by RE-EQUIPPING at the slot level: pulse-wield through the other weapon
    -- slot and back, so vanilla re-runs create_equipment / _wield_slot -> get_item_units
    -- re-resolves + respawns the offhand with the LA mesh. Slot-level re-equip ONLY --
    -- never World.destroy_unit (that is the gt POSITION_LOOKUP nil-deref crash class).
    --
    -- The CALLER passes the armoury_key that the respawn will actually resolve for this
    -- owner (husk: the _la_equips_by_peer entry; local: the same key echoed back on
    -- cos_la_apply, which matches _offhand_selection after the #203 exit-queue fix) so
    -- the post-pulse mesh CONVERGES and can't ping-pong.
    --
    -- Only ever call this from a SAFE context (network-callback recv handler or
    -- mod.update pending-retry). NEVER from inside a _wield_slot hook body -- the pulse
    -- re-fires _wield_slot and re-entering wield during wield can corrupt inventory
    -- state. Gated: kind="unit" only, package-resident only, mesh-already-correct no-op,
    -- per-owner cooldown + a hard try-cap (so a mesh that can't converge -- e.g. an
    -- unresolved get_item_units case -- pulses a few times then stops, no endless
    -- flicker), and a re-entrancy guard for the pulse's own _wield_slot fire.
    local _offhand_reswap_state = setmetatable({}, { __mode = "k" })  -- owner_unit -> { t, key, tries }
    local _OFFHAND_RESWAP_COOLDOWN = 1.5
    local _OFFHAND_RESWAP_MAX_TRIES = 3
    local function _ensure_offhand_mesh(owner_unit, hand_field, armoury_key, tag)
        if mod._cos_rewield.pulsing() then return false, "pulse-active" end
        if not (owner_unit and armoury_key and Unit.alive(owner_unit)) then return false, "owner-not-ready" end
        hand_field = hand_field or "left_hand_unit"
        local la = get_mod("Loremasters-Armoury")
        local variant = la and la.SKIN_LIST and la.SKIN_LIST[armoury_key]
        if not variant then return false, "variant-missing" end
        local inv = ScriptUnit and ScriptUnit.has_extension and ScriptUnit.has_extension(owner_unit, "inventory_system")
        local equipment = inv and inv._equipment
        if not (equipment and equipment.slots and inv.wield) then return false, "inventory-not-ready" end
        -- Already the LA mesh? -> nothing to do (the common healthy case; no flicker).
        local wielded_field = (hand_field == "right_hand_unit")
            and "right_hand_wielded_unit_3p" or "left_hand_wielded_unit_3p"
        local live = equipment[wielded_field]
        if live and Unit.alive(live) and _offhand_paint_mesh_ok(live, armoury_key) then
            return true, "already-correct"
        end
        -- Package residency: custom-unit variants use the shared LA resolver;
        -- texture variants pulse only when the live mesh is one of #373's exact
        -- magic units, targeting its same-family vanilla receiver.
        local la_unit, mesh_ready
        if variant.new_units and variant.new_units[1] then
            local _
            la_unit, _, mesh_ready = _resolve_authored_offhand_mesh(armoury_key)
        elseif variant.kind == "texture" and live and Unit.alive(live) then
            la_unit = LA_BRIDGE.resolve_texture_receiver(armoury_key, _unit_mesh_name(live))
            mesh_ready = la_unit and _override_package_ready(la_unit) or false
        end
        if not (la_unit and mesh_ready) then return false, "mesh-not-resident" end
        -- Per-owner cooldown + hard try-cap so a per-frame caller can't pulse-storm and a
        -- non-converging mesh can't flicker forever.
        local st = _offhand_reswap_state[owner_unit]
        if st and st.key == armoury_key then
            if st.tries >= _OFFHAND_RESWAP_MAX_TRIES then return false, "try-cap" end
            if (os.clock() - st.t) < _OFFHAND_RESWAP_COOLDOWN then return false, "cooldown" end
        end
        local orig_slot = LA_REPLAY_POLICY.wielded_slot(inv, equipment)
        if not orig_slot then return false, "wielded-slot-missing" end
        local pulse_slot = mod._cos_rewield.alternate_slot(equipment.slots, orig_slot)
        if not pulse_slot then return false, "alternate-slot-missing" end
        local from_mesh = (live and Unit.alive(live)) and _unit_mesh_name(live) or "<none>"
        local tries = (st and st.key == armoury_key) and (st.tries + 1) or 1
        _offhand_reswap_state[owner_unit] = { t = os.clock(), key = armoury_key, tries = tries }
        -- #1145: the wield pair is DEFERRED through the per-wearer coalescer (one
        -- pulse per wearer per frame, game-object re-checked at drain) instead of
        -- firing inline. The re-entrancy flag brackets the DEFERRED wields, which is
        -- where the re-entrancy actually is.
        local _, why = mod._cos_rewield.request(owner_unit, "offhand-mesh:" .. tostring(tag), function()
            local ok1, ok2 = mod._cos_rewield.pulse_now(inv, pulse_slot, orig_slot)
            mod:info("[cos-la-sync] RE-SWAP tag=%s owner=%s hand=%s armoury=%s try=%d from_mesh=%s -> %s pulse=%s<->%s ok=%s/%s",
                tostring(tag), tostring(owner_unit), tostring(hand_field), tostring(armoury_key), tries,
                tostring(from_mesh), tostring(la_unit), tostring(orig_slot), tostring(pulse_slot),
                tostring(ok1), tostring(ok2))
        end)
        -- The pulse has NOT happened yet, so the caller must not treat the mesh as
        -- repaired this frame; "coalesced" tells _la_reconcile to queue the paint
        -- re-apply behind the deferred pulse.
        return false, "coalesced:" .. tostring(why)
    end

    -- v0.9.69-dev (#265, LA_SYNC_CORE_AUDIT Slice 1): revert-side primitives.
    -- Attached to `mod` (no new top-level locals; the main chunk is near the Lua
    -- 200-local ceiling) but defined HERE so the closures capture the same
    -- upvalues the apply path uses (_la_equips_by_peer,
    -- _wearer_unit_for_peer, ...).

    -- Slot-level re-equip pulse that restores the NATIVE offhand/illusion render
    -- after a revert: with the store entry deleted, the pulse's get_item_units
    -- re-resolution falls through to vanilla (mesh AND texture -- a fresh spawn
    -- carries no LA paint). Same machinery/guards as _ensure_offhand_mesh's
    -- pulse (re-entrancy flag, cooldown via _offhand_reswap_state, slot-level
    -- wield only -- NEVER World.destroy_unit) but with the INVERSE gate: it runs
    -- regardless of LA variant state, because the target state is vanilla.
    -- Safe contexts only (network recv callback / mod.update), like the caller.
    mod._la_native_pulse = function(owner_unit, tag)
        if mod._cos_rewield.pulsing() then return end
        if not (owner_unit and Unit.alive(owner_unit)) then return end
        local inv = ScriptUnit and ScriptUnit.has_extension and ScriptUnit.has_extension(owner_unit, "inventory_system")
        local equipment = inv and inv._equipment
        if not (equipment and equipment.slots and inv.wield) then return end
        local st = _offhand_reswap_state[owner_unit]
        if st and st.key == "__native__" and (os.clock() - st.t) < _OFFHAND_RESWAP_COOLDOWN then return end
        local orig_slot = LA_REPLAY_POLICY.wielded_slot(inv, equipment)
        if not orig_slot then return end
        local pulse_slot = mod._cos_rewield.alternate_slot(equipment.slots, orig_slot)
        if not pulse_slot then return end
        _offhand_reswap_state[owner_unit] = { t = os.clock(), key = "__native__", tries = 1 }
        -- #1145: same deferral as _ensure_offhand_mesh. Keyed "__native__", this
        -- pulse does NOT share the per-armoury_key cooldown, so it was free to stack
        -- on a mesh pulse in the same frame; the coalescer is the shared choke point.
        mod._cos_rewield.request(owner_unit, "native-pulse:" .. tostring(tag), function()
            local ok1, ok2 = mod._cos_rewield.pulse_now(inv, pulse_slot, orig_slot)
            if printf then printf("[la-state] NATIVE-PULSE tag=%s owner=%s pulse=%s<->%s ok=%s/%s",
                tostring(tag), tostring(owner_unit), tostring(orig_slot), tostring(pulse_slot),
                tostring(ok1), tostring(ok2)) end
        end)
    end

    -- Re-create the wearer's NATIVE hat attachment after a hat revert. Only
    -- stomps the slot when it still renders the LA unit (if vanilla's own
    -- loadout resync already replaced it, no-op) -- convergent regardless of
    -- RPC-vs-resync arrival order. Residency-gated (the #270 class: never hand
    -- the engine a non-resident unit; the 0.9.67 create_attachment gate
    -- backstops this independently).
    mod._la_restore_native_hat = function(owner_unit, slot_name, vanilla_key, la_unit_path)
        local ext = ScriptUnit and ScriptUnit.has_extension
            and ScriptUnit.has_extension(owner_unit, "attachment_system")
        if not (ext and ext.create_attachment) then return false, "no-attachment-ext" end
        local slot_data = ext._attachments and ext._attachments.slots and ext._attachments.slots[slot_name]
        local current = slot_data and slot_data.item_data and slot_data.item_data.unit
        if la_unit_path and current and current ~= la_unit_path then
            return false, "already-native"
        end
        local item = vanilla_key and ItemMasterList and rawget(ItemMasterList, vanilla_key)
        if not (item and item.unit) then return false, "no-vanilla-item" end
        if Application and Application.can_get and not Application.can_get("unit", item.unit) then
            return false, "vanilla-unit-non-resident"
        end
        if slot_data then
            if AttachmentUtils and AttachmentUtils.destroy_attachment then
                pcall(AttachmentUtils.destroy_attachment, ext._world, ext._unit, slot_data)
            end
            ext._attachments.slots[slot_name] = nil
        end
        local ok, err = pcall(ext.create_attachment, ext, slot_name, table.clone(item))
        return ok, err
    end

    -- Receiver for an authoritative revert broadcast (called from the
    -- cos_la_apply handler, a safe network-callback context). Deletes the store
    -- entry, purges any queued re-apply for the same (wearer, slot) so a
    -- pending retry can't re-impose the reverted cosmetic, then restores the
    -- native render per kind.
    mod._la_apply_revert_recv = function(wearer, slot_name, kind, vanilla_key, hand_field)
        local entry = _la_equips_by_peer[wearer] and _la_equips_by_peer[wearer][slot_name]
        if _la_equips_by_peer[wearer] then
            _la_equips_by_peer[wearer][slot_name] = nil
        end
        -- DEVIATION (#1159): resolve the rebound entry-owned retry queue at the first read.
        local _la_pending_apply = _get_la_pending_apply()
        if _la_pending_apply and #_la_pending_apply > 0 then
            local kept = {}
            for i = 1, #_la_pending_apply do
                local e = _la_pending_apply[i]
                if not (e[1] == wearer and e[2] == slot_name) then
                    kept[#kept + 1] = e
                end
            end
            _la_pending_apply = kept
            -- DEVIATION (#1159): propagate the rebind to the entry-owned local.
            _set_la_pending_apply(_la_pending_apply)
        end
        local wu = _wearer_unit_for_peer(wearer)
        local outcome
        if kind == "offhand" or kind == "illusion" then
            if wu then
                mod._la_native_pulse(wu, "revert")
                outcome = "pulse"
            else
                outcome = "wearer-not-spawned (native restores on next wield)"
            end
        elseif kind == "hat" then
            local la_unit_path = nil
            if entry and entry.armoury_key then
                local variant = _resolve_la_variant(entry.armoury_key)
                la_unit_path = variant and variant.new_units and variant.new_units[1]
            end
            local vk = vanilla_key or (entry and entry.vanilla_key)
            if wu then
                local ok, why = mod._la_restore_native_hat(wu, slot_name, vk, la_unit_path)
                outcome = ok and "hat-restored" or ("hat-restore-skipped: " .. tostring(why))
            else
                outcome = "wearer-not-spawned"
            end
        else -- armor: store delete stops future re-imposition; the body repaint
             -- rides the next native slot_skin resync / respawn (rare path;
             -- active armor un-paint needs LA API work -- see issue 265).
            outcome = "armor: store cleared, repaint deferred to native resync"
        end
        if printf then printf("[la-state] REVERT-RECV wearer=%s slot=%s kind=%s had_entry=%s -> %s",
            tostring(wearer), tostring(slot_name), tostring(kind),
            tostring(entry ~= nil), tostring(outcome)) end
    end

    -- v0.9.70-dev (#264, LA_SYNC_CORE_AUDIT Slice 2 / invariant I3): the SINGLE
    -- render-reconcile entry point. Every trigger that (re)renders a peer's
    -- cosmetic-bearing units -- recv, pending retry, transition walk, husk wield,
    -- local wield -- calls THIS instead of its own bespoke re-apply, so a trigger
    -- nobody special-cased (the #264 weapon switch-back) cannot fall through.
    -- Reads ONLY the synced store (I1), targets ONLY the human wearer's unit
    -- (I4, via _wearer_unit_for_peer), and treats mesh+paint as one gated unit
    -- (I7): in safe contexts (allow_pulse=true: network callback / mod.update)
    -- a stale kind="unit" mesh is pulsed via _ensure_offhand_mesh; in wield
    -- contexts (allow_pulse=false: called from inside a _wield_slot body, where
    -- pulsing would re-enter wield) a stale mesh is DEFERRED to the pending
    -- drain, which pulses from mod.update within a frame or two.
    -- Returns (applied, reason): reason="no-entry" is terminal for retry loops
    -- (a revert deleted the entry); "wearer-not-spawned" is retryable.
    mod._la_reconcile = function(wearer_peer, slot_name, tag, allow_pulse)
        local equips = _la_equips_by_peer[wearer_peer]
        local eq = equips and equips[slot_name]
        if not (eq and eq.kind and eq.armoury_key) then return false, "no-entry" end
        -- #518: TERMINAL deus-yield for weapon-side entries, so pending-drain
        -- retries drop immediately instead of spinning to their 5s deadline.
        -- (_apply_la_on_unit carries the same gate as the belt-and-suspenders
        -- backstop for callers that bypass reconcile.)
        if (eq.kind == "offhand" or eq.kind == "illusion") and mod._la_deus_weapon_yield() then
            return false, "deus-yield"
        end
        local wu = _wearer_unit_for_peer(wearer_peer)
        if not wu then return false, "wearer-not-spawned" end
        local active_career = mod._la_career_for_unit(wu)
        local career_ok, career_reason = mod._cos_husk_identity.entry_matches_career(
            eq, active_career)
        if not career_ok then
            _purge_stale_peer_slot(_la_equips_by_peer, wearer_peer, slot_name)
            if printf then printf("[cos:698] RECONCILE SKIP wearer=%s slot=%s kind=%s recorded=%s active=%s reason=%s",
                tostring(wearer_peer), tostring(slot_name), tostring(eq.kind),
                tostring(eq.wearer_career), tostring(active_career), tostring(career_reason)) end
            return false, career_reason
        end
        local applied = _apply_la_on_unit(wu, slot_name, eq.kind, eq.armoury_key, eq.vanilla_key)
        if eq.kind == "offhand" or eq.kind == "illusion" then
            if allow_pulse then
                local inv = ScriptUnit and ScriptUnit.has_extension
                    and ScriptUnit.has_extension(wu, "inventory_system")
                local equipment = inv and inv._equipment
                local matches = mod._la_wielded_item_matches(inv, equipment, slot_name, eq.kind == "illusion")
                if matches then
                    local repaired, why = _ensure_offhand_mesh(wu, eq.hand_field, eq.armoury_key, tag)
                    if not applied and repaired then
                        applied = _apply_la_on_unit(wu, slot_name, eq.kind, eq.armoury_key, eq.vanilla_key)
                    elseif type(why) == "string" and why:sub(1, 9) == "coalesced" then
                        -- #1145: pulse deferred, so the mesh it repairs does not
                        -- exist yet. Hand the paint re-apply to the pending drain
                        -- (the same convergence the wield-context branch below uses);
                        -- without this the deferral silently drops the re-paint.
                        -- DEVIATION (#1159): resolve the rebound entry-owned retry queue at the first read.
                        local _la_pending_apply = _get_la_pending_apply()
                        _la_pending_apply[#_la_pending_apply + 1] = {
                            wearer_peer, slot_name, eq.kind, eq.armoury_key, eq.vanilla_key, os.clock() + 5,
                        }
                    end
                end
            elseif applied then
                -- Wield context: verify the just-spawned mesh against the store;
                -- if the in-wield get_item_units swap silently missed (#264's
                -- failure mode), hand the mesh repair to the pending drain.
                local inv = ScriptUnit and ScriptUnit.has_extension
                    and ScriptUnit.has_extension(wu, "inventory_system")
                local equipment = inv and inv._equipment
                local wf = (eq.hand_field == "right_hand_unit")
                    and "right_hand_wielded_unit_3p" or "left_hand_wielded_unit_3p"
                local live = equipment and equipment[wf]
                if live and Unit.alive(live) and not _offhand_paint_mesh_ok(live, eq.armoury_key) then
                    -- DEVIATION (#1159): resolve the rebound entry-owned retry queue at the first read.
                    local _la_pending_apply = _get_la_pending_apply()
                    _la_pending_apply[#_la_pending_apply + 1] = {
                        wearer_peer, slot_name, eq.kind, eq.armoury_key, eq.vanilla_key, os.clock() + 5,
                    }
                    if printf then printf("[la-state] RECONCILE tag=%s wearer=%s slot=%s -> mesh stale after wield, deferred pulse queued (key=%s)",
                        tostring(tag), tostring(wearer_peer), tostring(slot_name), tostring(eq.armoury_key)) end
                end
            end
        end
        return applied
    end

    -- Presence marker only, for the runtime checks and the offline suite. This is
    -- NOT a re-install guard: the moved block registered nothing, but it DOES
    -- define mod._la_reconcile and the three revert primitives, so a second
    -- install would silently replace live closures mid-session. The entry must
    -- keep calling this exactly once.
    mod._cos_la_apply_runtime_owner = { installed = true }
    return mod._cos_la_apply_runtime_owner
end

return LaApplyRuntime
