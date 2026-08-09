-- _cos_preview_runtime.lua — preview lifecycle, spawn, and score-lineup owner.
--
-- Owns the existing MenuWorldPreviewer/HeroPreviewer equipment and spawn hooks,
-- TeamPreviewer score-lineup adapters, and LootItemUnitPreviewer package,
-- lifecycle, spawn, and nil-zoom hooks. It also retains the adjacent authored-
-- outfit attachment replay on PlayerUnitCosmeticExtension.extensions_ready.
-- LA transport, husk rendering, persistence, and live weapon rendering remain
-- with their existing owners. Engine state stays late-bound inside callbacks;
-- the mutable customization backend id is supplied through an action-time getter.
--
-- Owned by: cosmetics_tweaker.lua entry point.
-- Consumed via: one ordered mod:dofile installer call and the public
-- mod._cos_score_peer_for_profile helper; guarded by
-- qa/lua/tests/test_cos_preview_runtime.lua.

local PreviewRuntime = {}

function PreviewRuntime.install(mod, deps)
    deps = deps or {}
    local state = mod._cos_preview_runtime_state
    if not state then
        -- A live upgrade from the pre-state owner cannot replace already
        -- registered VMF callbacks without duplicating hooks. Preserve that
        -- legacy owner for the current session; a clean load installs the
        -- state-dispatched callbacks below.
        state = {
            installed = mod._cos_preview_runtime_owner ~= nil,
            owner = mod._cos_preview_runtime_owner,
            score_peer_for_profile = mod._cos_score_peer_for_profile,
        }
        mod._cos_preview_runtime_state = state
    end

    -- Refresh every injected dependency before the idempotence guard. The
    -- registered callbacks close only over this stable holder, so entry/module
    -- reloads cannot retain the first LA, glow, score, or helper objects.
    state.la_bridge = assert(deps.la_bridge, "la_bridge is required")
    state.custom_hats = assert(deps.custom_hats, "custom_hats is required")
    state.score_identity = assert(deps.score_identity, "score_identity is required")
    state.gk_set = assert(deps.gk_set, "gk_set is required")
    state.glow_preview_policy = assert(deps.glow_preview_policy,
        "glow_preview_policy is required")
    state.glow_picker = assert(deps.glow_picker, "glow_picker is required")
    state.dbg = assert(deps.dbg, "dbg is required")
    state.dbg_alert = assert(deps.dbg_alert, "dbg_alert is required")
    state.local_player_safe = assert(deps.local_player_safe,
        "local_player_safe is required")
    state.apply_la_offhand_to_units = assert(deps.apply_la_offhand_to_units,
        "apply_la_offhand_to_units is required")
    state.offhand_paint_mesh_ok = assert(deps.offhand_paint_mesh_ok,
        "offhand_paint_mesh_ok is required")
    state.resolve_item_type = assert(deps.resolve_item_type,
        "resolve_item_type is required")
    state.resolve_composed_appearance = assert(
        deps.resolve_composed_appearance, "resolve_composed_appearance is required")
    state.glow_log = assert(deps.glow_log, "glow_log is required")
    state.get_active_customization_backend_id = assert(
        deps.get_active_customization_backend_id,
        "get_active_customization_backend_id is required")
    state.get_mod = assert(deps.get_mod, "get_mod is required")

    if state.installed then
        mod._cos_score_peer_for_profile = state.score_peer_for_profile
        mod._cos_preview_runtime_owner = state.owner
        return state.owner
    end

-- Inventory preview (new menu)
local _mwp_pending_keys = setmetatable({}, { __mode = "k" })

-- Track the `skin` arg passed to HeroPreviewer:equip_item /
-- MenuWorldPreviewer:equip_item, keyed by previewer -> item_name. The
-- equipment menu's character preview spawns via _spawn_item with the
-- WEAPON master key (e.g. `es_breton_sword`, item_type =
-- `es_1h_sword_shield_breton`), NOT the skin item. Without this map our
-- has_skin check `item_data.item_type == "weapon_skin"` returns false
-- and the LA paint is skipped on the equipment-menu character preview
-- even though the weapon DOES have an illusion equipped via backend.
local _equip_skin_by_item = setmetatable({}, { __mode = "k" })
-- BACKEND-RESOLVE FALLBACK: vanilla-crafted Bretonnian sword & shield (and
-- some other vanilla-crafted items) have their applied illusion stored only
-- on the backend `BackendItem` object — `equip_item` is called with `skin=nil`
-- because the caller relies on `BackendUtils.get_item_units` to resolve the
-- skin internally during spawn. Without this fallback our map stored `nil`
-- for those items, `has_skin` was false in `_spawn_item_post`, and LA paint
-- was skipped on the inventory loadout mannequin (the visible character
-- preview behind/around the customization screen). User report 2026-05-06.
local function _store_equip_skin(previewer, item_name, skin, backend_id)
    if not previewer or not item_name then return end
    if (not skin or skin == "") and backend_id and Managers and Managers.backend then
        local items_iface = Managers.backend:get_interface("items")
        if items_iface and items_iface.get_skin then
            local resolved = items_iface:get_skin(backend_id)
            if resolved and resolved ~= "" then
                skin = resolved
                state.dbg("[LA preview] backend-resolved skin for %s: %s", tostring(item_name), tostring(resolved))
            end
        end
    end
    local map = _equip_skin_by_item[previewer]
    if not map then map = {}; _equip_skin_by_item[previewer] = map end
    -- v0.8.32: store both skin and backend_id so per-backend-id offhand
    -- selection can be resolved in _spawn_item_post (which doesn't have
    -- backend_id in scope but does have item_name → previewer).
    map[item_name] = { skin = skin, backend_id = backend_id }
end
local function _get_equip_skin(previewer, item_name)
    if not previewer or not item_name then return nil end
    local map = _equip_skin_by_item[previewer]
    local entry = map and map[item_name]
    return entry and entry.skin or nil
end
local function _get_equip_backend_id(previewer, item_name)
    if not previewer or not item_name then return nil end
    local map = _equip_skin_by_item[previewer]
    local entry = map and map[item_name]
    return entry and entry.backend_id or nil
end

mod:hook("MenuWorldPreviewer", "equip_item", function(func, self, item_key, slot, backend_id, skin, skip_wield_anim)
    local slot_name = (type(slot) == "table" and slot.name) or tostring(slot)
    state.dbg("[LA preview] equip_item key=%s slot=%s bid=%s skin=%s is_clone=%s",
        tostring(item_key), tostring(slot_name), tostring(backend_id), tostring(skin),
        tostring(state.la_bridge.backend_to_armoury[backend_id] ~= nil))

    -- v0.9.8.2: stash backend_id for the previewer-spawned weapon units
    -- so the glow picker's per-item override resolves correctly. Folded
    -- in here instead of a separate hook_safe — using hook_safe on the
    -- same Class+method as our existing mod:hook caused rehook warnings
    -- at boot (v0.9.7 regression).
    if backend_id then self._cos_current_equip_backend_id = backend_id end

    if type(item_key) == "string" then
        local sn = (type(slot) == "table" and slot.name) or (type(slot) == "string" and slot)
        if sn then
            local map = _mwp_pending_keys[self]
            if not map then map = {}; _mwp_pending_keys[self] = map end
            map[sn:gsub("^slot_", "")] = item_key
        end
        _store_equip_skin(self, item_key, skin, backend_id)
    end

    if state.la_bridge.registered and backend_id
        and state.la_bridge.backend_to_armoury[backend_id] then
        state.dbg("[LA preview] equip_item swapping key %s -> %s for clone", tostring(item_key), tostring(backend_id))
        return func(self, backend_id, slot, backend_id, skin, skip_wield_anim)
    end

    return func(self, item_key, slot, backend_id, skin, skip_wield_anim)
end)

-- Also intercept HeroPreviewer (the equipment menu's character preview).
-- This is the previewer the user reported showing the "default shield
-- texture" instead of the LA-painted shield — it spawns the WEAPON master
-- key, not a skin entry, so our weapon_skin gate would skip the paint
-- without this skin tracking.
mod:hook("HeroPreviewer", "equip_item", function(func, self, item_name, slot, backend_id, skin, skip_wield_anim)
    -- v0.9.8.2: stash backend_id (see same fold in MenuWorldPreviewer hook above)
    if backend_id then self._cos_current_equip_backend_id = backend_id end
    if type(item_name) == "string" then
        _store_equip_skin(self, item_name, skin, backend_id)
    end
    -- v0.9.86-dev (#513): end-of-round score screen LA hat. The score lineup
    -- (TeamPreviewer:_spawn_hero -> HeroPreviewer, the BASE class - the derived
    -- MenuWorldPreviewer copy never runs here) equips the hat from
    -- players_session_scores, which carries only the NET-SAFE VANILLA key
    -- (CosmeticUtils.get_cosmetic_slot reads player sync data our
    -- update_cosmetic_slot hook substituted for wire safety), with backend_id
    -- nil - so every LA identity is gone by the time this previewer spawns.
    -- Recover it from the synced per-peer store: _cos_wearer_peer is stamped
    -- by our TeamPreviewer._spawn_hero hook (score screen only; the keep
    -- inventory previewer never has it). Mesh swaps via the bracketed
    -- get_item_units branch; paint happens post-spawn in
    -- _spawn_item_unit_combined (kind="texture" hats render vanilla colours
    -- without it, LA_SYNC_MODEL 6.2).
    local swap_unit = nil
    if self._cos_wearer_peer and type(slot) == "table" and slot.name == "slot_hat" then
        self._cos_score_hat = nil
        local peer_slots = mod._la_equips_by_peer and mod._la_equips_by_peer[self._cos_wearer_peer]
        local entry = peer_slots and peer_slots.slot_hat
        if entry and entry.kind == "hat" and entry.armoury_key then
            local la = state.get_mod("Loremasters-Armoury")
            local variant = state.custom_hats and state.custom_hats.resolve_variant
                and state.custom_hats.resolve_variant(entry.armoury_key)
                or (la and la.SKIN_LIST and la.SKIN_LIST[entry.armoury_key])
            if variant then
                local la_unit = variant.new_units and variant.new_units[1]
                if la_unit then
                    -- Residency gate (mirrors the #270 create_attachment gate):
                    -- a non-loadable mesh degrades to the synced vanilla hat,
                    -- never a World.spawn_unit C-assert.
                    local cg = Application and Application.can_get
                    if cg then
                        local okr, resident = pcall(cg, "unit", la_unit)
                        if not (okr and resident) then la_unit = nil end
                    end
                end
                swap_unit = la_unit
                self._cos_score_hat = {
                    armoury_key = entry.armoury_key,
                    vanilla_key = entry.vanilla_key or item_name,
                }
                if printf then printf("[la-state] SCORE-HAT equip peer=%s key=%s mesh=%s",
                    tostring(self._cos_wearer_peer), tostring(entry.armoury_key),
                    tostring(swap_unit or "(paint-only)")) end
            end
        end
    end
    if swap_unit then
        mod._cos_score_hat_swap = swap_unit
        local r1, r2 = func(self, item_name, slot, backend_id, skin, skip_wield_anim)
        mod._cos_score_hat_swap = nil
        return r1, r2
    end
    return func(self, item_name, slot, backend_id, skin, skip_wield_anim)
end)

-- ============================================================
-- #513: end-of-round score screen (TeamPreviewer hero lineup) LA apply
-- ============================================================
-- The adventure/deus/weave end views build their hero lineup from
-- players_session_scores (ScoreboardHelper reads player SYNC data =
-- net-safe vanilla keys) and spawn it through TeamPreviewer ->
-- HeroPreviewer (team_previewer.lua:20/126). None of the live-body /
-- husk apply paths run there (no attachment extension, no husk wield),
-- so LA hats/outfits rendered vanilla (#513). NOTE: the end views
-- themselves are class-COPIES (LevelEndViewDeus = class(_, LevelEndView)
-- copies methods at boot), so we hook the previewer classes that are
-- instantiated directly, never the views.

-- Resolve which peer a score-screen hero belongs to. hero_data carries
-- profile_index/career_index but NOT peer/local-player identity
-- (LevelEndView._get_hero_from_score drops it). The snapshot must therefore
-- match both indexes and prove the row is player-controlled before its
-- peer/local tuple may address the human-only LA store. ctx = TeamPreviewer's ingame_ui_context (has
-- profile_synchronizer, state_ingame_running.lua:287); falls back to the
-- network manager's synchronizer, then to player:profile_index().
state.score_peer_for_profile = function(profile_index, career_index, ctx)
    if profile_index == nil or career_index == nil then return nil end

    -- #513 follow-up: use the end view's OWN immutable score snapshot first.
    -- LevelEndViewBase stores it on context.players_session_score before the
    -- level transition removes PlayerManager rows. Each player_data retains
    -- exact peer_id/local_player_id/profile/career; _get_hero_from_score drops
    -- peer_id when constructing TeamPreviewer's hero_data. The previous live-
    -- PlayerManager-only resolver therefore returned nil for every lineup row
    -- after PlayerManager:remove_player (latest repro: removals at 21:08:34,
    -- TeamPreviewer package load at 21:08:35). Matching profile+career against
    -- the snapshot restores the identity without touching network-safe item data.
    local scores = ctx and ctx.players_session_score
    if type(scores) == "table" then
        -- ScoreboardHelper assigns every bot the owning host's peer_id
        -- [src: scoreboard_helper.lua:352,393-398]. That id is network
        -- ownership, not wearer identity. The pure resolver therefore
        -- requires an exact profile+career HUMAN row before exposing the
        -- human-only LA store; bot/untrusted rows fail closed.
        return state.score_identity.resolve_snapshot(profile_index, career_index, scores)
    end

    -- Keep the old live-player path as a fallback for non-end-view users of
    -- TeamPreviewer (Versus party/parading screens) where the score snapshot is
    -- absent but PlayerManager rows are still resident.
    local pm = Managers and Managers.player
    if not (pm and pm.human_players) then return nil end
    local psync = ctx and ctx.profile_synchronizer
    if not psync then
        local ns = Managers.state and Managers.state.network
        psync = ns and ns.profile_synchronizer
    end
    local ok_players, players = pcall(pm.human_players, pm)
    if not ok_players or type(players) ~= "table" then return nil end
    for _, p in pairs(players) do
        local pi, ci
        if psync and psync.profile_by_peer and p.peer_id then
            local ok_lpid, lpid = pcall(p.local_player_id, p)
            local ok_pi, rpi, rci = pcall(psync.profile_by_peer, psync, p.peer_id, ok_lpid and lpid or 1)
            if ok_pi then pi, ci = rpi, rci end
        end
        if pi == nil and type(p.profile_index) == "function" then
            local ok_pi, r = pcall(p.profile_index, p)
            if ok_pi then pi = r end
        end
        if ci == nil and type(p.career_index) == "function" then
            local ok_ci, r = pcall(p.career_index, p)
            if ok_ci then ci = r end
        end
        if pi == profile_index and ci == career_index then
            return p.peer_id, "live_player_fallback"
        end
    end
    return nil
end
mod._cos_score_peer_for_profile = state.score_peer_for_profile

-- Stamp wearer state before spawn; clear exact authored identity/cache so a
-- reused previewer cannot carry one score row into another (#513/#698/#730).
mod:hook("TeamPreviewer", "_spawn_hero", function(func, self, hero_previewer, hero_data)
    if hero_previewer and hero_data then
        hero_previewer._cos_score_armor_variant = nil; hero_previewer._cos_gk_score_armor_applied_mesh = nil; hero_previewer._cos_score_applied_armor_variant = nil
        local okp, peer, source = pcall(state.score_peer_for_profile,
            hero_data.profile_index, hero_data.career_index, self._context)
        peer = okp and peer or nil
        hero_previewer._cos_wearer_peer = peer
        if printf then
            mod._cos513_score_diag_seen = mod._cos513_score_diag_seen or {}
            mod._cos513_score_diag_count = mod._cos513_score_diag_count or 0
            local peer_slots = peer and mod._la_equips_by_peer and mod._la_equips_by_peer[peer]
            local local_peer
            local pm = Managers and Managers.player
            local lp = state.local_player_safe(pm)
            local_peer = lp and lp.peer_id
            if not local_peer and Network and Network.peer_id then
                local okn, value = pcall(Network.peer_id)
                if okn then local_peer = value end
            end
            local role = source == "score_snapshot_bot" and "bot"
                or (not peer and "unresolved" or (peer == local_peer and "local" or "remote"))
            local token = table.concat({ tostring(hero_data.profile_index), tostring(hero_data.career_index),
                tostring(peer), tostring(source), role,
                tostring(peer_slots and peer_slots.slot_hat and peer_slots.slot_hat.armoury_key),
                tostring(peer_slots and peer_slots.slot_skin and peer_slots.slot_skin.armoury_key) }, "|")
            if not mod._cos513_score_diag_seen[token] and mod._cos513_score_diag_count < 16 then
                mod._cos513_score_diag_seen[token] = true
                mod._cos513_score_diag_count = mod._cos513_score_diag_count + 1
                printf("[la-state] SCORE-ROW role=%s profile=%s career=%s peer=%s source=%s resolver_ok=%s store(hat=%s,skin=%s) evidence=%d/16 chat=false",
                    role, tostring(hero_data.profile_index), tostring(hero_data.career_index),
                    tostring(peer), tostring(source or "none"), tostring(okp),
                    tostring(peer_slots and peer_slots.slot_hat and peer_slots.slot_hat.armoury_key or "-"),
                    tostring(peer_slots and peer_slots.slot_skin and peer_slots.slot_skin.armoury_key or "-"),
                    mod._cos513_score_diag_count)
            end
        end
    end
    return func(self, hero_previewer, hero_data)
end)

-- LA ARMOR (slot_skin, kind="armor") on the score-screen body. The hero
-- spawns with the net-safe vanilla base skin (player_data.hero_skin);
-- the LA outfit is a texture paint over it. cb_hero_unit_spawned_skin_preview
-- fires right after _spawn_hero_unit (world_hero_previewer.lua:531-536), while
-- hidden. Authored providers retain their key and paint after post_update;
-- the legacy LA adapter below remains separately owned by LA (#730).
mod:hook_safe("TeamPreviewer", "cb_hero_unit_spawned_skin_preview", function(self, hero_previewer, hero_data)
    local peer = hero_previewer and hero_previewer._cos_wearer_peer
    local peer_slots = peer and mod._la_equips_by_peer and mod._la_equips_by_peer[peer]
    local entry = peer_slots and peer_slots.slot_skin
    if not (entry and entry.kind == "armor" and entry.armoury_key) then return end
    local authored = state.gk_set and state.gk_set.resolve_variant(entry.armoury_key)
    if authored then
        hero_previewer._cos_score_armor_variant = entry.armoury_key; hero_previewer._cos_gk_score_armor_applied_mesh = nil; hero_previewer._cos_score_applied_armor_variant = nil
        return
    end
    local la = state.get_mod("Loremasters-Armoury")
    local variant = la and la.SKIN_LIST and la.SKIN_LIST[entry.armoury_key]
    if not (variant and type(la.apply_new_skin_from_texture) == "function") then return end
    local world = hero_previewer.world
    local targets = {}
    local mesh_unit = hero_previewer.mesh_unit
    local character_unit = hero_previewer.character_unit
    if type(mesh_unit) == "userdata" and Unit.alive(mesh_unit) then targets[#targets + 1] = mesh_unit end
    if type(character_unit) == "userdata" and Unit.alive(character_unit) then targets[#targets + 1] = character_unit end
    for i = 1, #targets do
        state.la_bridge._bridge_active = true
        local ok, err = pcall(la.apply_new_skin_from_texture, entry.armoury_key, world, entry.vanilla_key, targets[i])
        state.la_bridge._bridge_active = false
        if printf then printf("[la-state] SCORE-ARMOR paint key=%s target=%d/%d ok=%s%s",
            tostring(entry.armoury_key), i, #targets, tostring(ok),
            ok and "" or (" err=" .. tostring(err))) end
    end
end)

-- Apply the authored outfit to the actual vanilla 1P/3P mesh attachments.
-- The custom Cosmetics entry reuses those attachments verbatim, so native
-- animation, visibility and fade behavior remain authoritative.
mod:hook_safe("PlayerUnitCosmeticExtension", "extensions_ready", function(self)
    local variant_key = self._cosmetics and state.gk_set.resolve_skin_variant(self._cosmetics.skin)
    if variant_key then
        local tp = self._tp_unit_mesh
        if tp and Unit.alive(tp) then
            state.gk_set.apply_variant_to_unit(variant_key, tp, "third_person")
        end
        local fp_ext = ScriptUnit.has_extension(self._unit, "first_person_system")
        local fp = fp_ext and fp_ext.get_first_person_mesh_unit and fp_ext:get_first_person_mesh_unit()
        if fp and Unit.alive(fp) then
            state.gk_set.apply_variant_to_unit(variant_key, fp, "first_person")
        end
    end
end)

mod:hook_safe("HeroPreviewer", "post_update", function(self)
    state.gk_set.apply_armor_to_hero_preview(self)
    if self._cos_score_armor_variant then
        state.gk_set.apply_armor_to_score_preview(self, self._cos_score_armor_variant)
    end
end)

local function _spawn_item_post(self, item_name, spawn_data)
    if not spawn_data then return end

    -- LA offhand paint: independent of scaling, runs whenever the
    -- previewed weapon has an LA offhand selected.
    if item_name and ItemMasterList then
        -- rawget: _spawn_item can be called with LA backend_ids (our
        -- equip_item hook swaps item_key -> backend_id for clones) or
        -- arbitrary keys from third-party mods.
        local item_data = rawget(ItemMasterList, item_name)
        local world = self._world or self.world
        if world and item_data then
            local equip_units = self._equipment_units
            if equip_units then
                local left_units = {}
                for _, slot in pairs(equip_units) do
                    if type(slot) == "table" and slot.left then
                        left_units[#left_units + 1] = slot.left
                    end
                end
                if #left_units > 0 then
                    -- has_skin is true if either:
                    --   (a) The previewed item itself is a weapon_skin entry
                    --       (inventory grid hover on a skin item), OR
                    --   (b) An equip_item call on this previewer passed a
                    --       non-empty `skin` arg for this item_name (the
                    --       equipment-menu character preview path — the
                    --       user has an illusion equipped via backend, but
                    --       _spawn_item runs with the WEAPON master key, so
                    --       item_type alone can't tell us that).
                    -- Base weapons hovered in the inventory grid hit
                    -- neither and pass-through unchanged, matching the
                    -- "we add options on top of illusions, never mutate
                    -- base templates" rule.
                    local stored_skin = _get_equip_skin(self, item_name)
                    local stored_bid  = _get_equip_backend_id(self, item_name)
                    local has_skin = (item_data.item_type == "weapon_skin")
                            or (stored_skin and stored_skin ~= "")
                    state.apply_la_offhand_to_units(world, item_data, left_units,
                        has_skin, stored_bid, "hero_previewer")
                    if stored_skin == state.gk_set.SHIELD_SKIN_KEY
                        or item_name == state.gk_set.SHIELD_SKIN_KEY then
                        for _, target in ipairs(left_units) do
                            state.gk_set.apply_variant_to_unit(
                                state.gk_set.SHIELD_VARIANT_KEY, target, "hero_previewer")
                        end
                    end
                end
            end
        end
    end

    -- Per-slot scale by unit path. Read paths from spawn_data[i].unit_name —
    -- vanilla equip_item already resolved skin + ammo + base via
    -- BackendUtils.get_item_units (world_hero_previewer.lua:675) and stored the
    -- final per-hand resource path on each spawn_data entry. That's the only
    -- truth source for "what unit is being rendered in this slot RIGHT NOW";
    -- looking it up from `info.name` -> ItemMasterList -> right_hand_unit then
    -- chasing a separate `info.skin_name` -> WeaponSkins.skins lookup is a
    -- redundant resolution chain that drifts whenever a clone (cwv) inherits
    -- its base's `name` field. We rely entirely on this truth source now —
    -- no cwv_variant gate needed: a cwv variant's spawn_data unit_name is
    -- always the variant's own model, so it can't accidentally match a
    -- base-weapon pattern. _item_info_by_slot is keyed by string slot_type
    -- ("melee"/"ranged"); spawn_data[1].slot_index bridges to _equipment_units
    -- which is numeric-slot-keyed.
    -- spawn_data shape (per HeroPreviewer.equip_item):
    --   [N] = { left_hand=true|nil, right_hand=true|nil, unit_name="..._3p",
    --           slot_index=N, ... }
    local equip_units = self._equipment_units
    local slot_info   = self._item_info_by_slot
    if not equip_units or not slot_info then return end
    for slot_type, info in pairs(slot_info) do
        if info.spawn_data and info.spawn_data[1] then
            local slot_index = info.spawn_data[1].slot_index
            local slot = slot_index and equip_units[slot_index]
            if type(slot) == "table" then
                local right_path, left_path
                for _, sd in ipairs(info.spawn_data) do
                    if sd.right_hand then right_path = sd.unit_name end
                    if sd.left_hand  then left_path  = sd.unit_name end
                end
                if mod:get("cos_thiccc_trace") then
                    state.dbg("[thiccc] preview name=%s skin=%s right=%s left=%s",
                        tostring(info.name), tostring(info.skin_name),
                        tostring(right_path), tostring(left_path))
                end
                mod._cos.apply_unit_path_scale_hand(slot.right, nil, right_path, "right")
                mod._cos.apply_unit_path_scale_hand(slot.left,  nil, left_path,  "left")
                -- #574: equip_item and _spawn_item are separated by async
                -- package loading.  `_cos_current_equip_backend_id` can point at
                -- a later request by spawn time, so bind from vanilla's durable
                -- per-slot info record and rehydrate before painting.
                local bid = info.backend_id or _get_equip_backend_id(self, info.name)
                local skin = info.skin_name or _get_equip_skin(self, info.name)
                local item_data = ItemMasterList and rawget(ItemMasterList, info.name)
                local restored = bid and state.glow_picker.restore_runtime_for(
                    bid, { skin = skin })
                if mod._cos.bind_glow_unit then
                    mod._cos.bind_glow_unit(slot.right, bid, skin, slot_type,
                        info.name, item_data and item_data.template)
                    mod._cos.bind_glow_unit(slot.left, bid, skin, slot_type,
                        info.name, item_data and item_data.template)
                end
                local composed_appearance = bid and state.resolve_composed_appearance({
                    backend_id = bid,
                    data = item_data,
                    skin = skin,
                }, nil, false) or nil
                mod._cos.apply_glow_override({ slot.right })
                if composed_appearance then
                    if composed_appearance.shield_glow then
                        mod._cos.apply_composed_shield_glow(
                            { slot.left }, composed_appearance)
                    end
                else
                    mod._cos.apply_glow_override({ slot.left })
                end
                if restored then
                    state.glow_log("rehydrate path=hero_preview bid=%s skin=%s slot=%s",
                        tostring(bid), tostring(skin), tostring(slot_type))
                end
            end
        end
    end
end

local function _spawn_item_wrapper(func, self, item_name, spawn_data)
    local is_direct_clone = state.la_bridge.registered and item_name
        and state.la_bridge.backend_to_armoury[item_name]
    state.dbg("[LA preview] _spawn_item name=%s direct=%s", tostring(item_name), tostring(is_direct_clone ~= nil))
    if is_direct_clone then
        self._cos_la_spawning = item_name
        state.dbg("[LA preview]   -> spawning clone %s", item_name)
    end
    -- #612: Encarmine now spawns the package-safe Laurel donor unchanged.
    -- `_spawn_item_unit_combined` paints only that instance after spawn, so the
    -- preview keeps Laurel's complete LOD/rig/controller/fade contract.
    local result = func(self, item_name, spawn_data)
    self._cos_la_spawning = nil
    _spawn_item_post(self, item_name, spawn_data)
    return result
end

mod:hook("HeroPreviewer", "_spawn_item", _spawn_item_wrapper)
mod:hook("MenuWorldPreviewer", "_spawn_item", _spawn_item_wrapper)

-- LootItemUnitPreviewer.load_package — short-circuit for engine-resident
-- units. Vanilla shield/weapon meshes ship as their OWN standalone
-- `units/.../wpn_xxx.package` files; the previewer's `load_package` calls
-- `Managers.package:load` on those, the load completes, `_on_load_complete`
-- flips `self._loaded_packages[path] = true`, and `_spawn_items` runs.
-- LA's custom-mesh shields, however, are all bundled into a single
-- `resource_packages/Loremasters-Armoury/Loremasters-Armoury` package —
-- there is no standalone `units/Kerillian_elf_shield/<...>_3p.package`.
-- A `Managers.package:load` call on those paths phantom-succeeds without
-- ever firing the completion callback, so the previewer's gate at
-- `_spawn_items` (loot_item_unit_previewer.lua:511) stays blocked and
-- `World.spawn_unit` is never called → user sees "no model at all".
-- VMF auto-loads each mod's `.mod` packages, so when LA is enabled its
-- main package is globally loaded and every `units/*` path inside it
-- becomes engine-resident — meaning `Application.can_get("unit", path)`
-- returns true even though the path isn't a valid standalone-package id.
-- We detect that case and immediately mark the previewer's gate flags
-- so `_spawn_items` proceeds to call `World.spawn_unit`, which succeeds
-- against the globally-loaded resource package.
-- v0.8.26 + v0.8.27 attempted to take a per-previewer reference on LA's
-- main package (async then sync) so its materials/textures would bind into
-- the previewer's scope. v0.8.26 (async) didn't fix the texture-less
-- preview; v0.8.27 (sync) crashed with `Resource '#ID[3ac73385950a26ea]'
-- was not found` (GUID 930aff6f-7e47-4f72-a661-b8222e862fc2). Reverted to
-- the plain v0.8.12 short-circuit. kind="unit" LA shields render mesh
-- correctly in-game and on the inventory mannequin but are texture-less
-- in the customization preview specifically. Documented limitation; needs
-- a different approach. CORRECTED (2026-06-21): the crash hash
-- `3ac73385950a26ea` is NOT a vanilla material — it is LA's WHOLE package
-- (`resource_packages/Loremasters-Armoury/Loremasters-Armoury`; Stingray names
-- every bundle by murmur64A of its package path). v0.8.27 crashed because the
-- sync `load()` FORCE-MATERIALIZED that package, and LA's installed bundle is
-- missing an internal member -> a C-level resource_package fatal (uncatchable
-- by pcall; fires async). gut's `_la_atlas_keepalive.lua` (v0.2.54) hit + fixed
-- the same class: only reference LA's package when it is ALREADY resident
-- (pm:has_loaded) so load() is a pure ref-count bump; NEVER force-load it.
-- Tracks per-previewer parent-package references already taken so we
-- don't sync-load the same vanilla parent twice for one previewer
-- instance. Weak-keyed by previewer.
local _la_parent_pkg_ref_by_previewer = setmetatable({}, { __mode = "k" })

mod:hook("LootItemUnitPreviewer", "load_package", function(func, self, package_name)
    if package_name and Application and Application.can_get
        and Application.can_get("unit", package_name)
        and not Application.can_get("package", package_name)
    then
        -- Existing short-circuit: gate-flip so spawn proceeds.
        self._packages_to_load[package_name] = true
        self._loaded_packages[package_name] = true

        -- v0.8.39: take a per-previewer reference on the LA mesh's parent
        -- vanilla package. LA's compiled `.unit` inherits its shader graph
        -- from that vanilla unit (per `mat_to_use` in the source `.unit`).
        -- Without the parent in the previewer's scope, the shader doesn't
        -- bind, the material doesn't fully initialize, and Reiland renders
        -- with missing/magenta textures. Sync load so the parent is fully
        -- bound before `_spawn_items` runs in the same frame. Vanilla
        -- packages are well-tested so this is safer than v0.8.27's attempt
        -- to sync-load LA's whole main package (which has its own broken
        -- references).
        local parent_pkg = state.la_bridge
            and state.la_bridge.la_path_to_parent_package
            and state.la_bridge.la_path_to_parent_package[package_name]
        if parent_pkg and Managers and Managers.package then
            local refs = _la_parent_pkg_ref_by_previewer[self]
            if not refs then
                refs = {}
                _la_parent_pkg_ref_by_previewer[self] = refs
            end
            if not refs[parent_pkg] then
                local reference_name = "LootItemUnitPreviewer"
                if self._unique_id then
                    reference_name = reference_name .. tostring(self._unique_id)
                end
                local ok, err = pcall(Managers.package.load,
                    Managers.package, parent_pkg, reference_name, nil, false)
                if ok then
                    refs[parent_pkg] = true
                    state.dbg("[LA preview-load] sync-loaded parent %s for %s",
                        parent_pkg, package_name)
                else
                    state.dbg_alert("[LA preview-load] FAILED to load parent %s for %s: %s",
                        parent_pkg, package_name, tostring(err))
                end
            end
        end
        return
    end
    return func(self, package_name)
end)

-- v0.9.76-dev (#282 sweep): release the per-previewer parent-package references
-- taken by the load_package hook above. Vanilla LootItemUnitPreviewer.destroy
-- unloads only ITS OWN _loaded_packages/_packages_to_load entries
-- (loot_item_unit_previewer.lua:64-66 + 423-451); our v0.8.39 parent refs use
-- the same "LootItemUnitPreviewer<unique_id>" reference name but a package
-- vanilla never tracked, so every illusion-browser open of an LA clone item
-- accumulated one never-released reference per parent package - the same
-- accumulate-per-event shape as the MH embed leak, at browser-open frequency.
-- hook_safe AFTER vanilla destroy (units already despawned; a still-held
-- resource goes through PackageManager's delayed-unload queue). Sole cosmetics
-- hook on (LootItemUnitPreviewer, destroy) - grep-verified 2026-07-11.
mod:hook_safe("LootItemUnitPreviewer", "destroy", function(self)
    local refs = _la_parent_pkg_ref_by_previewer[self]
    if not refs then return end
    _la_parent_pkg_ref_by_previewer[self] = nil
    local reference_name = "LootItemUnitPreviewer"
    if self._unique_id then
        reference_name = reference_name .. tostring(self._unique_id)
    end
    for parent_pkg in pairs(refs) do
        local ok, err = pcall(Managers.package.unload, Managers.package, parent_pkg, reference_name)
        if ok then
            pcall(printf, "[cos:282] unload (previewer destroy): %s ref=%s",
                tostring(parent_pkg), reference_name)
        else
            pcall(printf, "[cos:282] unload FAILED (previewer destroy) for %s: %s",
                tostring(parent_pkg), tostring(err))
        end
    end
end)

-- Illusion/skin browser preview (LootItemUnitPreviewer)
-- NOTE: must use mod:hook (not hook_safe) so we can capture the returned
-- `units` array. The caller (`_on_packages_loaded`) only assigns
-- `self._spawned_units = units` AFTER spawn_units returns, so reading
-- `self._spawned_units` from inside a hook_safe sees stale or nil data.
mod:hook("LootItemUnitPreviewer", "spawn_units", function(func, self, spawn_data)
    local units = func(self, spawn_data)

    local item = self._item
    if not item then return units end
    local item_data = item.data
    local left_path  = spawn_data and spawn_data[1] and spawn_data[1].unit_name or nil
    local right_path = spawn_data and spawn_data[2] and spawn_data[2].unit_name or nil
    local preview = state.glow_preview_policy.resolve_spawn(item,
        state.get_active_customization_backend_id(),
        mod._active_customization_item_type, state.resolve_item_type,
        mod._la_instance_policy.resolve_preview_backend_id)
    local skin_key, has_skin, preview_backend_id = preview.skin, preview.has_skin, preview.preview_backend_id

    -- LA offhand paint: spawn order is left (shield) = index 1, right (weapon) = index 2.
    -- Use the freshly-returned `units` array, not self._spawned_units (not yet assigned).
    -- Only paint when the previewed item carries an illusion context (it's a
    -- weapon_skin entry, OR the previewer was given a skin via item.skin).
    do
        local world = self._background_world or self._world or self.world
        if has_skin and world and item_data and units and units[1] then
            -- v0.8.55-dev: when previewing a pending-cycle skin, item.backend_id
            -- is nil. Fall back to the customization screen's active backend_id
            -- so the LA paint follows the row-2 offhand selection while user
            -- cycles row-1 main-hand illusions.
            local component_claimed = state.apply_la_offhand_to_units(world, item_data,
                { units[1] }, true, preview_backend_id, "loot_previewer", { left_path })
            if not component_claimed and skin_key == state.gk_set.SHIELD_SKIN_KEY
                and state.offhand_paint_mesh_ok(units[1],
                    state.gk_set.SHIELD_VARIANT_KEY, left_path) then
                state.gk_set.apply_variant_to_unit(
                    state.gk_set.SHIELD_VARIANT_KEY, units[1], "loot_previewer")
            end
        end
    end

    if not units then return units end

    -- Read the rendered unit paths straight from spawn_data — same truth-source
    -- approach as `_spawn_item_post`. Vanilla `_load_item_units`
    -- (loot_item_unit_previewer.lua:270) already called BackendUtils.get_item_units
    -- and stored the resolved per-hand path on each entry as `unit_name`.
    -- Spawn order is fixed: index 1 = left (shield), index 2 = right (weapon),
    -- per `_load_item_units` always queueing left-then-right. DEVELOPMENT.md
    -- "Three Rendering Paths" documents this contract.
    -- No cwv_variant gate needed: a cwv item's spawn_data unit_name is always
    -- the variant's own model, never the base weapon's path.
    mod._cos.apply_unit_path_scale_hand(units[2], nil, right_path, "right")
    mod._cos.apply_unit_path_scale_hand(units[1], nil, left_path,  "left")
    state.glow_preview_policy.bind_spawned(
        units, preview, state.glow_picker, mod._cos, state.dbg)
    mod._cos.apply_glow_override({ units[1], units[2] })

    return units
end)

-- #148 guard: a preview whose link unit failed to resolve (e.g. an LA custom
-- item with no display_unit) still latches _items_spawned via the hand-unit
-- package path, leaving _unit_start_position_boxed nil; a later zoom request
-- (set_zoom_fraction → _zoom_dirty) then crashes at
-- loot_item_unit_previewer.lua:142 (`self._unit_start_position_boxed:unbox()`).
-- The sibling rotation branch is already vanilla-nil-guarded (`if link_unit`);
-- this zoom branch is the one Fatshark missed. Clear the pending zoom when the
-- boxed start position is absent — there's no link unit to reposition, so
-- preview rotation/visibility is unaffected. Reached from the Weave Forge
-- overview (crash GUID per Issue #148, locals confirm link_unit = nil).
mod:hook("LootItemUnitPreviewer", "update", function(func, self, dt, t, input_service)
    if self._zoom_dirty and not self._unit_start_position_boxed then
        self._zoom_dirty = nil
    end
    return func(self, dt, t, input_service)
end)

    local owner = {
        score_peer_for_profile = state.score_peer_for_profile,
        hook_count = 12,
    }
    state.owner = owner
    state.installed = true
    mod._cos_score_peer_for_profile = state.score_peer_for_profile
    mod._cos_preview_runtime_owner = owner
    return owner
end

return PreviewRuntime
