-- _cos_equipment_assembly.lua - live equipment assembly seam owner.
--
-- RESPONSIBILITY
-- Owns the two nested vanilla seams that decide which unit meshes an equipped
-- item resolves to, and what is done to the units vanilla then spawns from them:
--
--   * UNIT-TABLE RESOLUTION - BackendUtils.get_item_units. The single place this
--     mod rewrites the unit table vanilla is about to spawn for an item. Four
--     override lanes share one call: the #513 score-screen LA hat mesh swap, the
--     husk LA mesh swap (kind="unit" variants plus the #373 same-family magic
--     shield paint receiver), the #416 husk VANILLA per-hand mesh swap, and the
--     per-backend-id offhand selection override that serves the live body and
--     the preview panes alike. Every lane is package-gated through
--     _override_package_ready so a non-resident unit degrades to the base mesh
--     instead of reaching World.spawn_unit (#270 / #392 class), and every
--     weapon-side lane yields to a deus-rolled skin (#518).
--
--   * LIVE-BODY ASSEMBLY - GearUtils.create_equipment. The in-keep / in-mission
--     body equipment spawn: the MH-embed texture and particle work that must run
--     before the vanilla call, the glow unit -> backend-id binding, weapon scale
--     and grip offset, the LA offhand paint, the Grail Knight shield variant,
--     the #574 glow rehydrate, and the composed-appearance glow apply.
--
-- The two seams travel together because they are BRACKETED, not merely adjacent.
-- create_equipment sets `_in_create_equipment` around its vanilla call, and
-- get_item_units - which vanilla calls from INSIDE create_equipment - reads that
-- flag to tell a live-body spawn apart from a customization previewer spawn
-- (#150: both pass the same backend_id). Nothing else in the mod reads or writes
-- the flag, so moving the pair as a unit turns entry file-scope state into state
-- private to this owner. Splitting them would leave the flag on the entry as
-- shared mutable state serving a hook the entry no longer owns.
--
-- Extracted VERBATIM from cosmetics_tweaker.lua (entry lines 677-687, 1477-1876
-- and 2131-2250 at 125f7ac8) with no behaviour change. Exactly TWO statements
-- differ from the original text, both marked DEVIATION inline and both described
-- under ENTRY-OWNED STATE below. mod:dofile is not a singleton, so the entry
-- calls this installer EXACTLY once. There is deliberately no re-install guard:
-- a second install would register duplicate hooks that VMF silently drops, which
-- is precisely what a second dofile of the old inline blocks did.
--
-- INSTALL POSITION
-- The installer runs where the LATER of the two hooks used to register (the
-- create_equipment site). Between the two former registration sites the entry
-- contains only comments, two mod:command registrations and plain local function
-- declarations - no mod:hook / mod:hook_safe / mod:hook_origin call of any kind -
-- so the mod-wide hook registration ORDER is unchanged by the move, and the
-- relative order of these two hooks is preserved. Installing at the earlier site
-- instead was rejected: `_apply_la_offhand_to_units` is declared BELOW it, so the
-- create_equipment paint call would have captured a global nil (the v0.9.0.11
-- forward-reference class this file has been burned by before).
--
-- ENTRY-OWNED STATE
--   deps.get_current_husk_wield
--     A late-binding accessor, NOT a value. The entry keeps the husk WEAPON path
--     (SimpleHuskInventoryExtension._wield_slot), and that wrap REBINDS
--     `_current_husk_wield` stack-style around every husk wield. An install-time
--     hand-off would have frozen the nil the local holds at load and silently
--     killed all three husk lanes. Resolved once per get_item_units call, at the
--     exact statement that used to perform the first inline read.
--   deps.get_active_customization_backend_id
--     A late-binding accessor for the same reason: `_active_customization_backend_id`
--     is written by _cos_customization_view_lifecycle AND by _cos_offhand_picker,
--     so one entry slot must stay authoritative. Same getter shape the entry
--     already hands _cos_preview_runtime.
--   deps.la_equips_by_peer / offhand_selection / offhand_session_state
--     By value. Each is bound once above the install call and only ever mutated
--     in place afterwards, so one shared table reference stays correct. The entry
--     re-runs `_la_equips_by_peer = _la_equips_by_peer or {}` further down, which
--     preserves the table identity because the local is already a table.
--   deps.resolve_composed_appearance / apply_la_offhand_to_units
--     By value. Both are forward-declared or declared above the install call and
--     already assigned when it runs; test_cos_equipment_assembly pins both
--     assignment sites to a position BEFORE the install call, so a future reorder
--     fails the suite instead of handing over nil.
--
-- COMPOSES WITH, DOES NOT OVERLAP, the sibling owners:
--   _cos_preview_runtime          owns the previewer spawn seams (HeroPreviewer /
--                                 MenuWorldPreviewer / LootItemUnitPreviewer). It
--                                 consumes get_item_units' output but registers no
--                                 hook on it; the two never share a hooked method.
--   _cos_attachment_spawn_sync    owns the ATTACHMENT-slot spawn/sync seams. This
--                                 owner touches hand/weapon unit fields only, and
--                                 the one hat lane it carries is the score-screen
--                                 previewer mesh swap, not an attachment spawn.
--   _cos_offhand_catalog          owns package readiness and authored mesh
--                                 resolution. This owner only CALLS those
--                                 resolvers; it never loads or refcounts packages.
--   _cos_offhand_picker /
--   _cos_offhand_session_state    own the offhand PICK. This owner only reads the
--                                 committed selection table when resolving units.
--   _cos_render / _cos_glow       own scale, offset and glow application. The
--                                 create_equipment lane calls them through
--                                 mod._cos.*; no apply logic is duplicated here.
--   _cos_la_replay_runtime /
--   _cos_wire                     own LA transport and wire safety. This owner
--                                 sends no RPC and registers no network handler.
-- `_cos_husk_wield_runtime` owns SimpleHuskInventoryExtension._wield_slot: it is
-- the husk WEAPON wield path that SETS the context this owner reads, not a
-- unit-resolution seam.
--
-- Owned by: cosmetics_tweaker.lua entry point.
-- Consumed via: one ordered install call at the former create_equipment position;
-- guarded by qa/lua/tests/test_cos_equipment_assembly.lua.

local EquipmentAssembly = {}

function EquipmentAssembly.install(mod, deps)
    deps = deps or {}

    local GK_SET                            = assert(deps.gk_set, "gk_set is required")
    local GlowPicker                        = assert(deps.glow_picker, "glow_picker is required")
    local LA_BRIDGE                         = assert(deps.la_bridge, "la_bridge is required")
    local MH_EMBED                          = assert(deps.mh_embed, "mh_embed is required")
    local PROBE                             = deps.probe
    local _apply_la_offhand_to_units        = assert(deps.apply_la_offhand_to_units, "apply_la_offhand_to_units is required")
    local _cos574_log                       = assert(deps.glow_log, "glow_log is required")
    local _cos_resolve_composed_appearance  = assert(deps.resolve_composed_appearance, "resolve_composed_appearance is required")
    local _dbg                              = assert(deps.dbg, "dbg is required")
    local _get_offhand_options              = assert(deps.get_offhand_options, "get_offhand_options is required")
    local _la_equips_by_peer                = assert(deps.la_equips_by_peer, "la_equips_by_peer is required")
    local _offhand_selection                = assert(deps.offhand_selection, "offhand_selection is required")
    local _offhand_session_state            = assert(deps.offhand_session_state, "offhand_session_state is required")
    local _override_package_ready           = assert(deps.override_package_ready, "override_package_ready is required")
    local _resolve_authored_offhand_mesh    = assert(deps.resolve_authored_offhand_mesh, "resolve_authored_offhand_mesh is required")
    local _resolve_authored_offhand_variant = assert(deps.resolve_authored_offhand_variant, "resolve_authored_offhand_variant is required")
    local _trace                            = assert(deps.trace, "trace is required")
    local _cim_preview                      = assert(deps.cim_preview, "cim_preview is required")

    local _get_current_husk_wield = assert(deps.get_current_husk_wield,
        "get_current_husk_wield is required")
    local _get_active_customization_backend_id =
        assert(deps.get_active_customization_backend_id,
            "get_active_customization_backend_id is required")

    -- v0.9.41-dev (#150): set true ONLY while inside our GearUtils.create_equipment
    -- wrap — i.e. when the LIVE in-keep / in-mission player body is (re)spawning its
    -- equipment. The BackendUtils.get_item_units hook reads this to tell a live-body
    -- spawn apart from a customization PREVIEWER spawn (both pass the same
    -- backend_id). While the customization screen is open we suppress the
    -- browse-time offhand mesh override on the live body so mousing/clicking
    -- illusions previews ONLY on the preview pane, never the equipped weapon on the
    -- player's own body; the live body commits on screen exit via the existing
    -- deferred broadcast + pulse-wield (on_exit below). Single-threaded Lua, so the
    -- set→read→restore bracket is safe.
    local _in_create_equipment = false

    if BackendUtils then
        mod:hook(BackendUtils, "get_item_units", function(func, item_data, backend_id, skin, career_name)
            local result = func(item_data, backend_id, skin, career_name)
            if not result then return result end

            -- v0.9.86-dev (#513): score-screen previewer LA hat MESH swap. The bracket
            -- (mod._cos_score_hat_swap) is set by the HeroPreviewer.equip_item hook ONLY
            -- around its single synchronous vanilla call, while the end-of-round
            -- TeamPreviewer lineup equips a wearer's synced LA hat. Vanilla equip_item
            -- reads result.unit for BOTH the spawn path and the package preload list
            -- (world_hero_previewer.lua:740/759), so swapping here makes the previewer
            -- itself load + spawn the LA mesh. Residency was pre-gated at the bracket
            -- set site (Application.can_get), mirroring the #270 attachment gate.
            if mod._cos_score_hat_swap and item_data and item_data.slot_type == "hat" and result.unit then
                local prev_unit = result.unit
                result.unit = mod._cos_score_hat_swap
                if printf then printf("[la-state] SCORE-HAT mesh-swap %s -> %s",
                    tostring(prev_unit), tostring(result.unit)) end
            end

            -- #518: deus-yield resolved ONCE per call. Gates the weapon-side mesh
            -- overrides below (husk LA swap, husk vanilla swap, live-body
            -- _offhand_selection) so CW upgrade skins render un-stomped.
            local _deus_yield = mod._la_deus_weapon_yield()

            -- v0.9.0.6-hotfix: kind="unit" LA mesh swap for remote husks.
            -- v0.9.0.8-hotfix: instrumented at every gate so we can see WHY a
            -- swap didn't fire (cache miss vs variant miss vs package miss).
        -- `_current_husk_wield` is stack-rebound by the remote-husk runtime
        -- (save / set / restore) around every husk wield, so an install-time
        -- value hand-off would freeze the nil it holds at load. Resolve it here,
        -- at the exact statement that performed the first read inline, and let
        -- the three husk lanes below share the same per-call value.
        local _current_husk_wield = _get_current_husk_wield()
            if _current_husk_wield and _current_husk_wield.wearer_peer then
                local template = item_data and item_data.template
                local equips = _la_equips_by_peer and _la_equips_by_peer[_current_husk_wield.wearer_peer]
                local entry = equips and template and equips[template]
                if entry then
                    local career_ok, career_reason =
                        mod._cos_husk_identity.entry_matches_career(
                            entry, _current_husk_wield.career_name)
                    if not career_ok then
                        if printf then printf("[cos:698] HUSK mesh SKIP wearer=%s template=%s recorded=%s active=%s reason=%s",
                            tostring(_current_husk_wield.wearer_peer), tostring(template),
                            tostring(entry.wearer_career),
                            tostring(_current_husk_wield.career_name), tostring(career_reason)) end
                        entry = nil
                    end
                end
                _dbg("[husk-mesh-swap probe] wearer=%s slot=%s template=%s cache_has_wearer=%s cache_has_entry=%s entry_kind=%s entry_key=%s",
                    tostring(_current_husk_wield.wearer_peer),
                    tostring(_current_husk_wield.slot_name),
                    tostring(template),
                    tostring(equips ~= nil),
                    tostring(entry ~= nil),
                    tostring(entry and entry.kind),
                    tostring(entry and entry.armoury_key))
                -- v0.9.69-dev (Slice 0, I6 / #264): the switch-back render loss has
                -- never been pinned because every gate here logs only via _dbg.
                -- One dedup'd printf per (wearer, template, disposition) so the
                -- user's log shows whether a husk wield found the store entry.
                do
                    local seen = mod._la_gate_seen
                    if not seen then seen = {}; mod._la_gate_seen = seen end
                    local dispo = (entry and (entry.kind or "?") .. "/" .. tostring(entry.armoury_key))
                        or (equips and "no-entry-for-template" or "no-store-for-wearer")
                    local sk = tostring(_current_husk_wield.wearer_peer) .. "|" .. tostring(template) .. "|" .. dispo
                    if not seen[sk] and printf then
                        seen[sk] = true
                        printf("[la-state] HUSK-GATE wearer=%s slot=%s template=%s -> %s",
                            tostring(_current_husk_wield.wearer_peer),
                            tostring(_current_husk_wield.slot_name),
                            tostring(template), dispo)
                    end
                end
                -- [cos:sync] issue 154 / #1156: husk cross-char weapon mesh-swap gate.
                -- Failure signal is an EMPTY husk cache at wield (cache_has_entry=false):
                -- the swap never fires and the teammate's weapon renders wrong. Emits the
                -- exact [husk-mesh-swap probe] needle via printf so mod-logging-OFF shows it.
                if PROBE then
                    PROBE.emit("cos:sync",
                        "husk_meshgate/" .. tostring(_current_husk_wield.wearer_peer) .. "/" .. tostring(template),
                        string.format("[husk-mesh-swap probe] peer=husk wearer=%s slot=%s template=%s cache_has_wearer=%s cache_has_entry=%s entry_kind=%s entry_key=%s decision=%s",
                            tostring(_current_husk_wield.wearer_peer), tostring(_current_husk_wield.slot_name),
                            tostring(template), tostring(equips ~= nil), tostring(entry ~= nil),
                            tostring(entry and entry.kind), tostring(entry and entry.armoury_key),
                            (entry and (entry.kind == "offhand" or entry.kind == "illusion") and entry.armoury_key) and "resolve-mesh" or "no-op(cache-or-kind-miss)"))
                end
                if entry and (entry.kind == "offhand" or entry.kind == "illusion")
                    and entry.armoury_key
                    -- #518: in a deus run the husk's weapon is a deus-generated
                    -- instance; its rolled rarity skin wins over the LA mesh swap.
                    and not _deus_yield
                then
                    local variant, variant_source =
                        _resolve_authored_offhand_variant(entry.armoury_key)
                    if not variant then
                        _dbg("[husk-mesh-swap] miss: authored variant %s unavailable", tostring(entry.armoury_key)); mod._cos518_husk_miss(entry.armoury_key, _current_husk_wield.wearer_peer, template) -- #518 printf
                        -- v0.9.0.14-hotfix: dedup'd chat warning. Surface the
                        -- missing-variant problem to the local user so they know
                        -- their LA install is missing what a peer is broadcasting
                        -- (most commonly: LA disabled in the launcher).
                        mod._la_missing_variant_logged = mod._la_missing_variant_logged or {}
                        if not mod._la_missing_variant_logged[entry.armoury_key] then
                            mod._la_missing_variant_logged[entry.armoury_key] = true
                            mod:echo("[cosmetics_tweaker] LA variant '%s' missing from your local LA install. Peer's cosmetic won't render. Enable Loremaster's Armoury in launcher + restart, or update LA.",
                                tostring(entry.armoury_key))
                        end
                    elseif variant.kind == "texture"
                        and not (variant.new_units and variant.new_units[1]) then
                        -- #373: Weavebound/Shyish shields use dedicated magic
                        -- material units that do not expose LA's diffuse slot.
                        -- Swap only an exact, same-family magic unit to its vanilla
                        -- paint receiver before the husk spawns it; ordinary texture
                        -- variants still remain paint-only.
                        local hand_field = entry.hand_field or "left_hand_unit"
                        local prev = result[hand_field]
                        local receiver = LA_BRIDGE.resolve_texture_receiver(
                            entry.armoury_key, prev, entry.authored_family)
                        if receiver and _override_package_ready(receiver) then
                            result[hand_field] = receiver
                            _dbg("[husk-mesh-swap] MAGIC-RECEIVER wearer=%s hand=%s %s -> %s (armoury=%s)",
                                tostring(_current_husk_wield.wearer_peer), tostring(hand_field),
                                tostring(prev), tostring(receiver), tostring(entry.armoury_key))
                        end
                    elseif not (variant.new_units and variant.new_units[1]) then
                        _dbg("[husk-mesh-swap] miss: variant %s has no new_units[1]", tostring(entry.armoury_key))
                    else
                        -- v0.9.45-dev (BUG 1/2): resolve via the SHARED helper so the
                        -- local override path (below) and this husk path can't drift.
                        -- _resolve_authored_offhand_mesh derives the 3P from new_units[2]
                        -- (fallback `.."_3p"`) and verifies both halves are loadable.
                        local la_unit, la_unit_3p, mesh_ready = _resolve_authored_offhand_mesh(entry.armoury_key)
                        if not mesh_ready then
                            _dbg("[husk-mesh-swap] miss: variant %s authored mesh not loadable (1p=%s 3p=%s source=%s) — package preload may have failed",
                                tostring(entry.armoury_key), tostring(la_unit), tostring(la_unit_3p), tostring(variant_source))
                        else
                            -- v0.9.9.4-dev: write to the hand_field recorded
                            -- in the cached entry (default left for backward
                            -- compat with pre-v0.9.9.4 cache writes).
                            local hand_field = entry.hand_field or "left_hand_unit"
                            local prev = result[hand_field]
                            result[hand_field] = la_unit
                            _dbg("[husk-mesh-swap] APPLIED wearer=%s template=%s %s %s -> %s (armoury=%s)",
                                tostring(_current_husk_wield.wearer_peer), tostring(template),
                                tostring(hand_field),
                                tostring(prev), tostring(la_unit), tostring(entry.armoury_key))
                            -- v0.9.69-dev (Slice 0, I6): mod-logging-OFF-visible
                            -- confirmation that the wield-path swap fired (#264's
                            -- missing evidence). Dedup'd per (wearer, template, key).
                            do
                                local seen = mod._la_gate_seen
                                if not seen then seen = {}; mod._la_gate_seen = seen end
                                local sk = "swap|" .. tostring(_current_husk_wield.wearer_peer)
                                    .. "|" .. tostring(template) .. "|" .. tostring(entry.armoury_key)
                                if not seen[sk] and printf then
                                    seen[sk] = true
                                    printf("[la-state] HUSK-SWAP applied wearer=%s template=%s hand=%s -> %s (key=%s)",
                                        tostring(_current_husk_wield.wearer_peer), tostring(template),
                                        tostring(hand_field), tostring(la_unit), tostring(entry.armoury_key))
                                end
                            end
                            -- v0.9.43-dev RESOLVE+HUSK trace: the husk DOES swap the
                            -- mesh to the LA custom unit (using new_units[1]/[2] for
                            -- the 1p/3p check) — this is why the CLIENT renders the
                            -- host's shield correctly while the host's own body does
                            -- not (the local path's _override_package_ready suffix
                            -- check fails). Contrast with the RESOLVE line above.
                            _trace("RESOLVE husk-mesh-swap APPLIED wearer=%s slot=%s template=%s hand=%s %s -> %s armoury=%s",
                                tostring(_current_husk_wield.wearer_peer),
                                tostring(_current_husk_wield.slot_name), tostring(template),
                                tostring(hand_field), tostring(prev), tostring(la_unit),
                                tostring(entry.armoury_key))
                            if PROBE then
                                PROBE.emit("cos:sync",
                                    "husk_meshswap/" .. tostring(_current_husk_wield.wearer_peer) .. "/" .. tostring(template),
                                    string.format("peer=husk wearer=%s template=%s key=%s unit=%s decision=APPLIED-mesh-swap",
                                        tostring(_current_husk_wield.wearer_peer), tostring(template),
                                        tostring(entry.armoury_key), tostring(la_unit)))
                            end
                            return result
                        end
                    end
                end

                -- v0.9.82-dev (#416): VANILLA offhand mesh swap on the husk. LA armoury
                -- shields sync above via _la_equips_by_peer; a per-hand VANILLA shield /
                -- held-weapon unit pick (opt.unit / opt.intended_unit, no armoury_key)
                -- has no LA entry, so the husk previously spawned the wearer's BASE
                -- offhand (the #416 gap: Stirland / Bretonnian / GK shields invisible to
                -- peers). Read the parallel synced store and force each recorded hand's
                -- mesh, package-gated via _override_package_ready so a non-resident unit
                -- can NEVER reach the World.spawn_unit C-assert (#270/#392 class) -- a
                -- missing package degrades to the base mesh, not a crash.
                local vstore = mod._offhand_mesh_by_peer
                local vwear  = vstore and vstore[_current_husk_wield.wearer_peer]
                local vhands = vwear and template and vwear[template]
                -- #518: vanilla offhand mesh picks yield in a deus run too (same
                -- template-key leak as the LA branch above).
                if type(vhands) == "table" and not _deus_yield then
                    local applied_any = false
                    for hand_field, unit_path in pairs(vhands) do
                        if type(unit_path) == "string" and unit_path ~= "" then
                            local recv_item_type = item_data and item_data.item_type
                            if recv_item_type == "weapon_skin" and item_data.matching_item_key
                                    and ItemMasterList then
                                local base = rawget(ItemMasterList, item_data.matching_item_key)
                                recv_item_type = base and base.item_type or recv_item_type
                            end
                            -- #583: use CWV's fingerprint-validated peer identity;
                            -- absent/mismatched identity retains the vanilla family.
                            local identity_state = "base"
                            if mod._cos_cwv_peer_identity then
                                recv_item_type, identity_state =
                                    mod._cos_cwv_peer_identity.resolve_husk(recv_item_type,
                                        get_mod("character_weapon_variants"), _current_husk_wield,
                                        item_data, mod._independent_dual_item_types)
                            end
                            local compatible = mod._dual_offhand_unit_allowed(
                                recv_item_type, hand_field, unit_path)
                            local ready = compatible and _override_package_ready(unit_path)
                            if compatible and ready then
                                local prev = result[hand_field]
                                result[hand_field] = unit_path
                                applied_any = true
                                if printf then printf("[la-state] HUSK-VANILLA-SWAP wearer=%s template=%s hand=%s %s -> %s",
                                    tostring(_current_husk_wield.wearer_peer), tostring(template),
                                    tostring(hand_field), tostring(prev), tostring(unit_path)) end
                            end
                            -- [cos:sync] #416: husk vanilla offhand mesh decision. Shows
                            -- APPLIED vs SKIP(package-not-resident) with mod logging OFF.
                            if PROBE then
                                PROBE.emit("cos:sync",
                                    "husk_vanilla/" .. tostring(_current_husk_wield.wearer_peer) .. "/" .. tostring(template) .. "/" .. tostring(hand_field),
                                    string.format("peer=husk wearer=%s template=%s hand=%s unit=%s decision=%s item_type=%s identity=%s",
                                        tostring(_current_husk_wield.wearer_peer), tostring(template),
                                        tostring(hand_field), tostring(unit_path),
                                        (compatible and ready) and "APPLIED-vanilla-mesh"
                                            or (compatible and "SKIP(package-not-resident)"
                                                or "SKIP(incompatible-hand-mesh)"),
                                        tostring(recv_item_type), tostring(identity_state)))
                            end
                        end
                    end
                    if applied_any then return result end
                end
            end

            -- Mirror BackendUtils' skin resolution chain, including the backend_id
            -- stamped on item_data during loadout resync (v0.7.101-dev).
            local resolved_skin = skin
            local item_type = item_data and item_data.item_type
            if item_type == "weapon_skin" and item_data.matching_item_key then
                local weapon_data = rawget(ItemMasterList, item_data.matching_item_key)
                if weapon_data then
                    item_type = weapon_data.item_type
                end
            end
            if not item_type then return result end
        -- DEVIATION 2 of 2. Same contract for the mutable customization backend
        -- id: the view-lifecycle owner and the offhand picker both write that
        -- entry local, so it is resolved per call at its original first-read
        -- point rather than captured once at install time.
            local cim_context, cim_identity, cim_scoped =
                _cim_preview.resolve_scoped_identity(item_data,
                    backend_id or (item_data and item_data.backend_id), item_type,
                    skin)
            local _active_customization_backend_id = not cim_scoped
                and _get_active_customization_backend_id() or nil
            local active_preview_bid = not _current_husk_wield
                and _active_customization_backend_id or nil
            local active_preview_item_type = not _current_husk_wield
                and mod._active_customization_item_type or nil
            local effective_backend_id, preview_identity
            if cim_scoped then
                -- A CIM scope must never borrow the customization view's
                -- mutable family fallback. Exact identity or resident base.
                effective_backend_id = cim_context and cim_context.backend_id or nil
                preview_identity = cim_identity
            else
                effective_backend_id, preview_identity =
                    mod._la_instance_policy.resolve_preview_backend_id(
                        backend_id or (item_data and item_data.backend_id), item_type,
                        active_preview_bid, active_preview_item_type)
            end
            -- Pending-skin previews may use the exact active item only when the
            -- family matches. Husk rendering never consumes this local fallback.
            if not effective_backend_id and not _current_husk_wield then
                _trace("RESOLVE preview identity rejected item_type=%s active_bid=%s active_item_type=%s state=%s",
                    tostring(item_type), tostring(_active_customization_backend_id),
                    tostring(mod._active_customization_item_type),
                    tostring(preview_identity))
            end
            if not resolved_skin and effective_backend_id and Managers and Managers.backend then
                local backend_items = Managers.backend:get_interface("items")
                if backend_items and backend_items.get_skin then
                    resolved_skin = backend_items:get_skin(effective_backend_id)
                end
            end

            -- Base templates have no skin; offhand customization must not mutate them.
            if not resolved_skin or resolved_skin == "" then return result end

            -- Selections are per backend item and per hand, never item-type globals.
            if effective_backend_id then
                _offhand_session_state.migrate_legacy(effective_backend_id)
            end
            -- #150: browsing changes only the preview; the live body commits on exit.
            local _suppress_browse_override = _in_create_equipment
                and _active_customization_backend_id ~= nil
                and effective_backend_id == _active_customization_backend_id
            if _suppress_browse_override then
                _dbg("[offhand] suppress browse-override on live body bid=%s (customization screen open)",
                    tostring(effective_backend_id))
                -- Provenance for the live-body browse suppression gate.
                _trace("RESOLVE suppress-browse bid=%s (in_create_equipment + active_cust match) → live body mesh override SUPPRESSED",
                    tostring(effective_backend_id))
            end
            -- #518: on the LIVE body in a deus run (create_equipment; the first CW
            -- map resolves the player's REAL backend items, so the backend_id-keyed
            -- selection genuinely matches) the deus-rolled skin owns the mesh.
            -- Preview surfaces (_in_create_equipment=false) still show the pick,
            -- since they render the keep instance.
            local sel = (not _suppress_browse_override)
                and not (_deus_yield and _in_create_equipment)
                and effective_backend_id
                and _offhand_selection[effective_backend_id]
            local selected_hand_pools = _get_offhand_options(item_type)
            if type(sel) == "table" then
                for hand_field, opt in pairs(sel) do
                    local selected_pool = selected_hand_pools
                        and selected_hand_pools[hand_field]
                    if type(opt) == "table"
                        and mod._la_instance_policy.selection_owned(opt, selected_pool) then
                        local override_unit = opt.unit or opt.intended_unit
                        -- LA unit variants share the husk path's authored 1P/3P
                        -- resolution; vanilla and texture-only picks retain readiness.
                        local resolved_unit, resolved_ready
                        if opt.la_armoury_key then
                            local la_1p, _la_3p, la_ready = _resolve_authored_offhand_mesh(opt.la_armoury_key)
                            if la_1p then
                                resolved_unit, resolved_ready = la_1p, la_ready
                            else
                                -- #373: pure-paint LA variants have no intended
                                -- unit. If the selected vanilla illusion is a known
                                -- magic shield, use its exact same-family paintable
                                -- counterpart instead of silently painting a shader
                                -- with no diffuse slot.
                                resolved_unit = LA_BRIDGE.resolve_texture_receiver(
                                    opt.la_armoury_key, result[hand_field], opt.authored_family)
                                    or override_unit
                                resolved_ready = (override_unit and _override_package_ready(override_unit)) or false
                                if resolved_unit and resolved_unit ~= override_unit then
                                    resolved_ready = _override_package_ready(resolved_unit)
                                end
                            end
                        else
                            resolved_unit = override_unit
                            resolved_ready = (override_unit and _override_package_ready(override_unit)) or false
                        end
                        -- Keep suffix readiness in the trace for legacy-path comparison.
                        local variant = opt.la_armoury_key
                            and _resolve_authored_offhand_variant(opt.la_armoury_key)
                        local cg = Application and Application.can_get
                        local suffix_3p_ok = (override_unit and cg)
                            and cg("unit", tostring(override_unit) .. "_3p") or false
                        _trace("RESOLVE item_type=%s hand=%s bid=%s in_create_equipment=%s active_cust_match=%s override_unit=%s resolved_unit=%s ready=%s suffix3p_ok=%s kind=%s new_units1=%s new_units2=%s decision=%s",
                            tostring(item_type), tostring(hand_field), tostring(effective_backend_id),
                            tostring(_in_create_equipment),
                            tostring(_active_customization_backend_id ~= nil and effective_backend_id == _active_customization_backend_id),
                            tostring(override_unit), tostring(resolved_unit), tostring(resolved_ready), tostring(suffix_3p_ok),
                            tostring(variant and variant.kind),
                            tostring(variant and variant.new_units and variant.new_units[1]),
                            tostring(variant and variant.new_units and variant.new_units[2]),
                            (resolved_unit and resolved_ready) and "apply-override" or (resolved_unit and "SKIP(package-not-ready)" or "passthrough(no-mesh)"))
                        local apply_override = resolved_unit and resolved_ready
                        if cim_context then
                            apply_override = _cim_preview.prepare_override(
                                cim_context, hand_field, opt, resolved_unit,
                                resolved_ready, item_type)
                        elseif cim_scoped then
                            apply_override = false
                        end
                        if resolved_unit and apply_override then
                            result[hand_field] = resolved_unit
                        elseif resolved_unit then
                            _dbg("[offhand] SKIP override %s/%s -> %s (package not ready)",
                                tostring(item_type), tostring(hand_field), tostring(resolved_unit))
                        end
                    elseif type(opt) == "table" then
                        _trace("RESOLVE selection rejected bid=%s item_type=%s hand=%s reason=foreign-selection",
                            tostring(effective_backend_id), tostring(item_type),
                            tostring(hand_field))
                    end
                end
            end

            -- v0.9.3.5: REVERTED the v0.9.3.4 _fallback_if_unloadable gate.
            --
            -- That gate post-processed `result` with `Application.can_get` and
            -- either fell back to `item_data[field]` or cleared the field to nil
            -- when paths were not engine-resident at the moment of the call.
            --
            -- Confirmed regressions (PC-A log 18:51:57, PC-B log 18:52:32):
            --   * 55 elf weapon fields CLEARED to nil during keep async-load
            --     windows — wpn_we_sword_01, wpn_we_dagger_01, wpn_we_deus_02
            --     all both variant AND base returned can_get=false transiently
            --     while the packages were still async-loading. Resulting nil
            --     paths left the elf's weapons INVISIBLE in her hands.
            --   * The gate ran AFTER `result.left_hand_unit = override_unit`,
            --     so the LA offhand override got OVERWRITTEN with the base
            --     vanilla path or nil whenever `can_get` was transiently false
            --     for the override path. PC-A saw vanilla shield locally;
            --     PC-B (peer, who received the broadcast separately) saw the
            --     LA variant correctly. That's the asymmetry the user reported.
            --
            -- `Application.can_get` is unreliable during the async-load window
            -- in keep — paths that ARE valid (in inventory_package_list.lua,
            -- finishing async load) return false transiently. The gate was too
            -- aggressive to be a useful defense.
            --
            -- The original crash this was meant to prevent
            -- (c_api_world.cpp:67 assert on wpn_es_deus_shield_02_magic_3p
            -- after ProfileSync unload) needs a different mechanism — likely
            -- a synchronous `Managers.package:load` before the override
            -- commits, ensuring the unit is in the resource manager when the
            -- wield RPC fires. Deferred to a follow-up.

            return result
        end)
    end

    -- In-game keep / mission body
    -- THREE RENDERING PATHS COVERAGE:
    --   - In-game (GearUtils.create_equipment): THIS HOOK
    --   - Inventory previewer (HeroPreviewer._spawn_item): _cos_preview_runtime.lua
    --   - Illusion browser (LootItemUnitPreviewer.spawn_units): _cos_preview_runtime.lua
    mod:hook("GearUtils", "create_equipment", function(func, world, slot_name, item_data, unit_1p, unit_3p, is_bot, unit_template, extra_extension_data, ammo_percent, override_item_template, override_item_units, career_name)
        -- v0.9.5: fold MH embed's texture/particle work BEFORE vanilla call.
        -- Matches the original MH-embed hook order (replace then vanilla then
        -- particles). When embed is dormant (standalone enabled), MH_EMBED
        -- exports are no-ops.
        if MH_EMBED and not MH_EMBED.dormant then
            MH_EMBED.replace_textures(unit_1p)
            MH_EMBED.replace_textures(unit_3p)
            MH_EMBED.add_particles(unit_1p, world)
            MH_EMBED.add_particles(unit_3p, world)
        end
        -- v0.9.41-dev (#150): flag the live-body spawn so the get_item_units hook
        -- (called INSIDE vanilla create_equipment) can suppress the browse-time
        -- offhand override on the player's own equipped weapon while the
        -- customization screen is open. Save/restore for nested-call safety.
        local _prev_in_create_equipment = _in_create_equipment
        _in_create_equipment = true
        local result = func(world, slot_name, item_data, unit_1p, unit_3p, is_bot, unit_template, extra_extension_data, ammo_percent, override_item_template, override_item_units, career_name)
        _in_create_equipment = _prev_in_create_equipment
        -- v0.9.6 M2: stash unit→backend_id mapping for the glow picker's
        -- per-item override lookup. Weak-keyed table auto-cleans when units
        -- get destroyed. Covers all 4 hand-unit fields the previewer and
        -- in-keep paths might query.
        if result and item_data and mod._cos.bind_glow_unit then
            local bid = item_data.backend_id
            local resolved_skin = result.skin or item_data.skin
            if (not resolved_skin or resolved_skin == "") and bid and Managers and Managers.backend then
                local items = Managers.backend:get_interface("items")
                resolved_skin = items and items.get_skin and items:get_skin(bid) or resolved_skin
            end
            for _, field in ipairs({ "left_unit_1p", "right_unit_1p", "left_unit_3p", "right_unit_3p" }) do
                local u = result[field]
                if u then
                    mod._cos.bind_glow_unit(u, bid, resolved_skin, slot_name,
                        item_data.name, item_data.template)
                end
            end
        end
        if result and item_data then
            -- Scale runs unconditionally — it's gated by unit-path matching, so
            -- a cwv variant equipped in this slot only gets scaled if its
            -- resolved model genuinely matches a pattern (e.g. someone applies
            -- a Bretonian skin to a cwv item, which intentionally would scale).
            mod._cos.scale_units(result, item_data, result.skin)
        end
        if result and item_data and not item_data.cwv_variant then
            -- Offset / tint / LA-paint stay item-name-keyed and so DO need the
            -- cwv_variant gate. cwv items inherit their base weapon's `name`
            -- (e.g. cwv_es_longsword.name == "es_bastard_sword"), so without
            -- this gate any item-name-keyed override on the base weapon would
            -- spuriously fire on every cwv variant. See
            -- `feedback_cwv_clone_name_clobber.md` for the full rationale.
            local weapon_key = item_data.name
            mod._cos.offset_units(result, weapon_key, career_name)
            local has_skin = result.skin ~= nil and result.skin ~= ""
            _apply_la_offhand_to_units(world, item_data, { result.left_unit_3p, result.left_unit_1p }, has_skin, nil, "ingame")
        end
        if result and item_data then
            local skin_key = result.skin or item_data.skin
            if (not skin_key or skin_key == "") and item_data.backend_id and Managers and Managers.backend then
                local items = Managers.backend:get_interface("items")
                skin_key = items and items.get_skin and items:get_skin(item_data.backend_id) or skin_key
            end
            if skin_key == GK_SET.SHIELD_SKIN_KEY then
                for _, target in ipairs({ result.left_unit_3p, result.left_unit_1p }) do
                    if target and Unit.alive(target) then
                        GK_SET.apply_variant_to_unit(GK_SET.SHIELD_VARIANT_KEY, target, "create_equipment")
                    end
                end
            end
        end
        if result then
            -- v0.9.0-dev: resolve wearer from the 3P unit (= player_unit body).
            -- create_equipment doesn't pass a player object, but unit_3p IS the
            -- player_unit here, so :owner(unit_3p) resolves the peer correctly
            -- for both local + remote husk equips.
            local owner_peer_id = mod._cos.glow_owner_peer_for_unit(unit_3p)
            local composed_appearance
            if item_data and item_data.backend_id then
                local restore_skin = result.skin or item_data.skin
                if (not restore_skin or restore_skin == "") and Managers and Managers.backend then
                    local items = Managers.backend:get_interface("items")
                    restore_skin = items and items.get_skin
                        and items:get_skin(item_data.backend_id) or restore_skin
                end
                local restored = GlowPicker.restore_runtime_for(item_data.backend_id, {
                    skin = restore_skin,
                })
                if restored then
                    _cos574_log("rehydrate path=create_equipment bid=%s skin=%s slot=%s",
                        tostring(item_data.backend_id), tostring(restore_skin), tostring(slot_name))
                end
                composed_appearance = _cos_resolve_composed_appearance({
                    backend_id = item_data.backend_id,
                    data = item_data,
                    skin = restore_skin,
                }, nil, false)
            end
            mod._cos.apply_glow_override({
                result.right_unit_3p, result.right_unit_1p,
            }, owner_peer_id)
            if composed_appearance then
                if composed_appearance.shield_glow then
                    mod._cos.apply_composed_shield_glow({
                        result.left_unit_3p, result.left_unit_1p,
                    }, composed_appearance)
                end
            else
                mod._cos.apply_glow_override({
                    result.left_unit_3p, result.left_unit_1p,
                }, owner_peer_id)
            end
        end
        return result
    end)

    -- Presence marker only, for the runtime checks and the offline suite. This is
    -- NOT a re-install guard: see the header - a second install would register
    -- duplicate hooks that VMF silently drops, exactly as a second dofile of the
    -- old inline blocks did, so the entry must keep calling this exactly once.
    mod._cos_equipment_assembly_owner = { installed = true }
    return mod._cos_equipment_assembly_owner
end

return EquipmentAssembly
