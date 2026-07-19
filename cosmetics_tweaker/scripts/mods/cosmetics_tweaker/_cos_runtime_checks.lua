-- cosmetics_tweaker runtime regression registration owner.
-- Checks stay lazy and register in their historical entry-point order.
local M = {}

function M.install(mod, rt_register, deps)
    local _rt_register = rt_register
    local LA_PERSIST = deps.la_persist
    local SCORE_IDENTITY = deps.score_identity
    local HUSK_IDENTITY = deps.husk_identity
    local COS_RPC_SCHEMA = deps.rpc_schema
    local COMPOSITE_ICONS = deps.composite_icons
    local CUSTOM_HATS = deps.custom_hats
    local LA_BRIDGE = deps.la_bridge
    local GK_SET = deps.gk_set
    local GlowPicker = deps.glow_picker
    local WEAPON_POSES = deps.weapon_poses
    local _SHIELD_ICON_OWNER_ITEM_TYPES = deps.shield_icon_owner_item_types
    local _offhand_options = deps.offhand_options
    local _MULTI_MOUNT_ITEM_TYPES = deps.multi_mount_item_types
    local _DUAL_WIELD_POOLS = deps.dual_wield_pools
    local OFFHAND_NAMES = deps.offhand_names
    local ITEM_PRESENTATION = deps.item_presentation
    local _SHIELD_POOLS_BY_ITEM_TYPE = deps.shield_pools_by_item_type
    local _dbg = deps.dbg
    local _dbg_alert = deps.dbg_alert
    local UI_DUMP = deps.ui_dump
    local _custom_skin_keys = deps.custom_skin_keys
    local OFFHAND_PRELOAD_LIFECYCLE = deps.offhand_preload_lifecycle
    local MH_EMBED = deps.mh_embed
    local CWV_PEER_IDENTITY = deps.cwv_peer_identity
    local LA_INSTANCE_POLICY = deps.la_instance_policy

-- ============================================================
-- /regression_test checks (see scaffold near MOD_VERSION).
-- ============================================================

-- #45: RPC schema constant must be a positive number so every network_send
-- prepends it and every network_register gate has something to compare against.
-- #264/#267 (Slice 2/2b): the reconcile entry point and the pull-on-ready
-- flow must stay wired. Losing reconcile regresses to per-trigger re-apply
-- drift; losing the pull regresses hot-join to the pre-ingame push race.
_rt_register("cos_la_reconcile_and_pull_wired", function()
    if type(mod._la_reconcile) ~= "function" then
        return "mod._la_reconcile missing"
    end
    if type(mod._la_tick_peer_purges) ~= "function" then
        return "mod._la_tick_peer_purges missing (transition-wipe fix, BUG_CLASSES 24)"
    end
    if type(mod._la_restore_offhand_selections) ~= "function" then
        return "mod._la_restore_offhand_selections missing (offhand persistence)"
    end
    if type(mod._la_rebroadcast_inventory_ready) ~= "function" then
        return "mod._la_rebroadcast_inventory_ready missing (persisted peer-ready replay)"
    end
    if mod._la_rebroadcast_inventory_ready(nil)
        or mod._la_rebroadcast_inventory_ready({ _equipment = { slots = {} } }) then
        return "persisted replay accepted inventory before weapon slots were ready"
    end
    if not mod._la_rebroadcast_inventory_ready({ _equipment = { slots = {
        slot_melee = { item_data = { backend_id = "rt-persisted-item" } },
    } } }) then
        return "persisted replay rejected a realized weapon slot"
    end
    if not (LA_PERSIST and type(LA_PERSIST.save_offhand) == "function"
        and type(LA_PERSIST.clear_offhand) == "function"
        and type(LA_PERSIST.get_saved_offhands) == "function"
        and type(LA_PERSIST.commit_offhand_entry) == "function") then
        return "LA_PERSIST offhand API incomplete"
    end
end)

-- #660 S3: the bounded appearance-replay reconciler (cold-join cluster
-- #233/#149/#203) must stay wired at its three edges and its pure coalescing
-- policy must not regress to per-frame re-apply. Losing it strands persisted
-- LA shields/hats/skins on a cold-joined husk until the wearer edits again.
_rt_register("cos_replay_reconciler_wired", function()
    if type(mod._cos_replay) ~= "table" then return "mod._cos_replay missing" end
    if type(mod._cos_replay.on_edge) ~= "function" then return "mod._cos_replay.on_edge missing" end
    if type(mod._cos_replay.apply) ~= "function" then return "mod._cos_replay.apply missing" end
    local P = mod._cos_replay.policy
    if type(P) ~= "table" or type(P.reconcile_edge) ~= "function"
        or type(P.build_records) ~= "function" or type(P.new_replay_state) ~= "function"
        or type(P.invalidate_all) ~= "function" then
        return "replay policy API incomplete"
    end
    -- Pure coalescing self-check (touches no engine state): apply once, then a
    -- repeated generation must coalesce (never per-frame), then an invalidation
    -- must re-apply the same generation (husk-recreating transition).
    local st = P.new_replay_state()
    local recs = { { peer = "rt_peer", slot = "slot_ranged",
        record = { kind = "offhand", armoury_key = "rt_key", hand_field = "left_hand_unit" } } }
    local calls = 0
    local apply = function() calls = calls + 1; return "applied" end
    local r1 = P.reconcile_edge(st, "rt", recs, apply)
    local r2 = P.reconcile_edge(st, "rt", recs, apply)
    if not (r1.applied == 1 and r2.applied == 0 and r2.coalesced == 1 and calls == 1) then
        return "replay reconciler did not coalesce a repeated generation"
    end
    P.invalidate_all(st)
    local r3 = P.reconcile_edge(st, "rt", recs, apply)
    if not (r3.applied == 1 and calls == 2) then
        return "replay reconciler did not re-apply after invalidation"
    end
end)

-- #518: the yield boundary is GAME MODE, not mechanism alone. The deus
-- mechanism owns Pilgrimage Chamber (inn_deus), route/shrine map (map_deus),
-- and expedition missions (deus). LA stays live in the first two and yields
-- only in the third. Pure-table cases prevent the mechanism-only regression.
_rt_register("cos_la_deus_yield_active_mission_only", function()
    if type(mod._la_weapon_yield_for_context) ~= "function" then
        return "mod._la_weapon_yield_for_context missing (#518 boundary helper)"
    end
    if type(mod._la_deus_weapon_yield) ~= "function" then
        return "mod._la_deus_weapon_yield missing (#518 deus-yield gate)"
    end
    local cases = {
        { "adventure", "inn", false, "normal keep" },
        { "deus", "inn_deus", false, "Pilgrimage Chamber" },
        { "deus", "map_deus", false, "route/shrine map" },
        { "deus", "deus", true, "active expedition mission" },
    }
    for _, case in ipairs(cases) do
        local actual = mod._la_weapon_yield_for_context(case[1], case[2])
        if actual ~= case[3] then
            return string.format("%s: mechanism=%s game_mode=%s expected=%s got=%s",
                case[4], case[1], case[2], tostring(case[3]), tostring(actual))
        end
    end
    local ok, v = pcall(mod._la_deus_weapon_yield)
    if not ok then return "deus-yield gate errored: " .. tostring(v) end
    if type(v) ~= "boolean" then
        return "deus-yield gate must return boolean, got " .. type(v)
    end
end)

-- #514: the offhand/illusion weapon-identity gate must (a) resolve the
-- wielded slot from equipment.wielded_slot (inv.wielded_slot is husk-only;
-- reading it made the guard dead on the local wearer), and (b) be
-- RESTRICTIVE when the wielded item is unresolvable. Pure-table functional
-- test replaying the #514 shapes: local-wearer inventory (no inv field)
-- wielding CWV Sword and Mace vs a pick stored under the Bret
-- sword-and-shield template key.
_rt_register("cos_la_weapon_identity_gate_local_wearer", function()
    if type(mod._la_wielded_item_matches) ~= "function" then
        return "mod._la_wielded_item_matches missing (#514 gate helper)"
    end
    local inv = {}  -- SimpleInventoryExtension shape: NO wielded_slot field
    local equipment = {
        wielded_slot = "slot_melee",
        slots = { slot_melee = { item_data = {
            template = "sword_and_mace_template",
            key = "cwv_es_sword_and_mace",
            item_type = "cwv_es_sword_and_mace",
        } } },
    }
    local m = mod._la_wielded_item_matches(inv, equipment, "one_handed_sword_shield_template_2", false)
    if m then return "#514 repro: bret template entry matched wielded sword-and-mace" end
    m = mod._la_wielded_item_matches(inv, equipment, "sword_and_mace_template", false)
    if not m then return "template key of the WIELDED weapon must match (local wearer)" end
    m = mod._la_wielded_item_matches(inv, equipment, "slot_melee", false)
    if m then return "slot-key entry must NOT match for kind=offhand (allow_slot_key=false)" end
    m = mod._la_wielded_item_matches(inv, equipment, "slot_melee", true)
    if not m then return "slot-key entry must match for kind=illusion (allow_slot_key=true)" end
    local m2, w2 = mod._la_wielded_item_matches(inv, {}, "sword_and_mace_template", false)
    if m2 or w2 ~= nil then return "unresolvable wielded item must be restrictive (false, nil)" end
end)

-- #513: the end-of-round score-screen LA apply must stay wired: the peer
-- resolver the TeamPreviewer._spawn_hero hook uses exists and is nil-safe
-- (a nil profile must resolve to nil, never error), and the synced per-peer
-- store the hat/armor branches read is present. Functional; no engine calls.
_rt_register("cos_la_score_screen_apply_wired", function()
    if type(mod._cos_score_peer_for_profile) ~= "function" then
        return "mod._cos_score_peer_for_profile missing (#513 score-screen peer resolver)"
    end
    local ok, v = pcall(mod._cos_score_peer_for_profile, nil, nil, nil)
    if not ok then return "score peer resolver errored on nil: " .. tostring(v) end
    if v ~= nil then return "score peer resolver must return nil for a nil profile" end
    if type(mod._la_equips_by_peer) ~= "table" then
        return "mod._la_equips_by_peer store missing (#513 score path reads it)"
    end
    -- Reproduce the end transition after PlayerManager rows are gone: the
    -- context score snapshot alone must resolve local and remote rows exactly.
    local fixture = { players_session_score = {
        ["peer-local:1"] = { peer_id = "peer-local", local_player_id = 1,
            profile_index = 5, career_index = 4, is_player_controlled = true },
        ["peer-remote:1"] = { peer_id = "peer-remote", local_player_id = 1,
            profile_index = 5, career_index = 1, is_player_controlled = true },
        ["bot-sienna"] = { peer_id = "peer-local", local_player_id = 1,
            profile_index = 1, career_index = 4, is_player_controlled = false },
        ["bot-priest"] = { peer_id = "peer-local", local_player_id = 1,
            profile_index = 2, career_index = 3, is_player_controlled = false },
    } }
    local p1, s1 = mod._cos_score_peer_for_profile(5, 4, fixture)
    local p2, s2 = mod._cos_score_peer_for_profile(5, 1, fixture)
    if p1 ~= "peer-local" or p2 ~= "peer-remote"
        or s1 ~= "score_snapshot" or s2 ~= "score_snapshot" then
        return string.format("score snapshot resolver wrong: local=%s/%s remote=%s/%s",
            tostring(p1), tostring(s1), tostring(p2), tostring(s2))
    end
    local wrong = mod._cos_score_peer_for_profile(5, 3, fixture)
    if wrong ~= nil then return "score resolver ignored career and cross-matched a row" end
    local bot1, bs1 = mod._cos_score_peer_for_profile(1, 4, fixture)
    local bot2, bs2 = mod._cos_score_peer_for_profile(2, 3, fixture)
    if bot1 ~= nil or bot2 ~= nil or bs1 ~= "score_snapshot_bot" or bs2 ~= "score_snapshot_bot" then
        return string.format("bot owner peer leaked into wearer identity: sienna=%s/%s priest=%s/%s",
            tostring(bot1), tostring(bs1), tostring(bot2), tostring(bs2))
    end
    if SCORE_IDENTITY.should_purge_mismatch(false)
        or SCORE_IDENTITY.should_purge_mismatch(nil)
        or not SCORE_IDENTITY.should_purge_mismatch(true) then
        return "spawn mismatch purge boundary does not distinguish human from bot owner alias"
    end
end)

-- #698: peer-addressed appearance state must carry the exact human career.
-- A human career change invalidates stale material/mesh state before husk
-- wield; a bot sharing the host peer must neither consume nor purge it.
_rt_register("issue698_husk_career_identity", function()
    if type(HUSK_IDENTITY) ~= "table"
        or type(HUSK_IDENTITY.new_entry) ~= "function"
        or type(HUSK_IDENTITY.entry_matches_career) ~= "function"
        or type(HUSK_IDENTITY.invalidate_for_career) ~= "function"
    then
        return "career-scoped husk identity policy missing"
    end
    local gk = HUSK_IDENTITY.new_entry("armor", "rt_gk", "rt_base", nil,
        "es_questingknight")
    local store = { rt_peer = { slot_skin = gk } }
    local bot_removed, bot_reason = HUSK_IDENTITY.invalidate_for_career(
        store, "rt_peer", "es_knight", false)
    if bot_removed ~= 0 or bot_reason ~= "non-human-owner-alias"
        or store.rt_peer.slot_skin ~= gk then
        return "bot owner alias invalidated human appearance state"
    end
    local removed, reason = HUSK_IDENTITY.invalidate_for_career(
        store, "rt_peer", "es_knight", true)
    if removed ~= 1 or reason ~= "career-invalidated" or store.rt_peer ~= nil then
        return "human career change retained stale Grail Knight appearance state"
    end
    local current = HUSK_IDENTITY.new_entry("armor", "rt_fk", "rt_base", nil,
        "es_knight")
    if not HUSK_IDENTITY.entry_matches_career(current, "es_knight")
        or HUSK_IDENTITY.entry_matches_career(current, "es_questingknight") then
        return "career match policy is not exact"
    end
end)

-- #264: reconcile must treat a missing store entry as TERMINAL ("no-entry"),
-- not retryable - otherwise a reverted cosmetic is re-imposed by stale
-- pending-queue entries. Pure store-lookup path; no engine calls.
_rt_register("cos_la_reconcile_no_entry_terminal", function()
    if type(mod._la_reconcile) ~= "function" then return "reconcile missing" end
    local ok, applied, reason = pcall(mod._la_reconcile, "rt_fake_peer_no_entry", "rt_fake_slot", "rt", false)
    if not ok then return "reconcile errored on empty store: " .. tostring(applied) end
    if applied ~= false or reason ~= "no-entry" then
        return "expected (false, 'no-entry'), got (" .. tostring(applied) .. ", " .. tostring(reason) .. ")"
    end
end)

-- BUG_CLASSES 24: a due deferred purge must execute (store + deadline
-- cleared); the local peer must never be purged. Functional test against
-- the real tick using a fake peer with an already-expired deadline.
_rt_register("cos_la_peer_purge_defer_and_execute", function()
    if type(mod._la_tick_peer_purges) ~= "function" then return "tick missing" end
    if type(mod._la_equips_by_peer) ~= "table" then return "store alias missing" end
    local fake = "rt_fake_peer_purge"
    mod._la_peer_purge_at = mod._la_peer_purge_at or {}
    mod._la_peer_purge_at[fake] = os.clock() - 1
    mod._la_equips_by_peer[fake] = { rt_slot = { kind = "offhand", armoury_key = "rt_key" } }
    mod._la_tick_peer_purges()
    local leftover_store = mod._la_equips_by_peer[fake]
    local leftover_deadline = mod._la_peer_purge_at[fake]
    mod._la_equips_by_peer[fake] = nil
    mod._la_peer_purge_at[fake] = nil
    if leftover_store ~= nil then return "due purge did not clear the store entry" end
    if leftover_deadline ~= nil then return "due purge did not clear the deadline" end
end)

-- #265: a revert broadcast received for a peer must DELETE the store entry
-- (armor kind = pure store path, no unit/engine work when the wearer is not
-- spawned - fake peer guarantees that).
_rt_register("cos_la_revert_recv_deletes_entry", function()
    if type(mod._la_apply_revert_recv) ~= "function" then return "revert recv missing" end
    if type(mod._la_equips_by_peer) ~= "table" then return "store alias missing" end
    local fake = "rt_fake_peer_revert"
    mod._la_equips_by_peer[fake] = {
        slot_skin = { kind = "armor", armoury_key = "rt_key", vanilla_key = "rt_v" },
    }
    local ok, err = pcall(mod._la_apply_revert_recv, fake, "slot_skin", "armor", "rt_v", nil)
    local leftover = mod._la_equips_by_peer[fake] and mod._la_equips_by_peer[fake].slot_skin
    mod._la_equips_by_peer[fake] = nil
    if not ok then return "revert recv errored: " .. tostring(err) end
    if leftover ~= nil then return "revert did not delete the store entry" end
end)

-- 0.9.71: offhand picks must round-trip through the persistence file
-- (save -> read back -> clear -> gone). Uses a fake backend_id; leaves no
-- residue in la_persisted_equips.
_rt_register("cos_la_offhand_persistence_roundtrip", function()
    if not (LA_PERSIST and LA_PERSIST.save_offhand
            and LA_PERSIST.commit_offhand_entry) then return "offhand API missing" end
    local bid, hand = "rt_fake_bid_0001", "left_hand_unit"
    LA_PERSIST.save_offhand(bid, hand, "rt_key", "rt_vanilla")
    local saved = LA_PERSIST.get_saved_offhands()
    local rec = saved and saved[bid] and saved[bid][hand]
    if not (rec and rec.armoury_key == "rt_key" and rec.vanilla_key == "rt_vanilla") then
        LA_PERSIST.clear_offhand(bid, hand)
        return "saved offhand did not read back"
    end
    LA_PERSIST.clear_offhand(bid, hand)
    saved = LA_PERSIST.get_saved_offhands()
    if saved and saved[bid] then return "cleared offhand still present" end

    local committed = LA_PERSIST.commit_offhand_entry({
        backend_id = bid,
        hand_field = hand,
        offhand_unit = "units/rt/dual_left",
        skin_key = "rt_dual_skin",
        player_unit = nil,
    })
    if not committed then return "exact offhand commit rejected without a player unit" end
    saved = LA_PERSIST.get_saved_offhands()
    rec = saved and saved[bid] and saved[bid][hand]
    if not (rec and rec.unit_path == "units/rt/dual_left"
            and rec.vanilla_key == "rt_dual_skin"
            and rec.armoury_key == nil) then
        LA_PERSIST.clear_offhand(bid, hand)
        return "saved native/CWV hand mesh did not read back"
    end
    LA_PERSIST.clear_offhand(bid, hand)
end)

-- #520: hat/outfit persistence module roundtrip (save/read/clear). The
-- careers section sat empty for weeks because no writer ever landed - this
-- locks the module API itself.
_rt_register("cos_la_cosmetic_persistence_roundtrip", function()
    if not (LA_PERSIST and LA_PERSIST.save_cosmetic) then return "cosmetic API missing" end
    local career, slot, item = "rt_fake_career", "slot_hat", "rt_fake_item_LA_rt"
    LA_PERSIST.save_cosmetic(career, slot, item)
    if LA_PERSIST.get_saved_cosmetic(career, slot) ~= item then
        LA_PERSIST.clear_cosmetic(career, slot)
        return "saved cosmetic did not read back"
    end
    if type(LA_PERSIST.get_all_saved_cosmetics) ~= "function"
        or not LA_PERSIST.get_all_saved_cosmetics()[career]
    then
        LA_PERSIST.clear_cosmetic(career, slot)
        return "get_all_saved_cosmetics missing entry"
    end
    LA_PERSIST.clear_cosmetic(career, slot)
    if LA_PERSIST.get_saved_cosmetic(career, slot) ~= nil then
        return "cleared cosmetic still present"
    end
end)

-- #520: the AUTHORITATIVE save/clear tap lives in the set_loadout_item hook
-- (career_name is a call argument - immune to the profile_by_peer resync
-- window that silently dropped every update_cosmetic_slot-tap save). Drive
-- the real hook with a fake LA-clone bid and verify cache + disk both write
-- and both clear. Leaves no residue; the clone branch never calls vanilla.
_rt_register("cos_la_loadout_equip_capture_wired", function()
    if not get_mod("Loremasters-Armoury") then return end -- LA absent: dormant by design
    if not mod._la_skin_safety_installed then
        return "skin loadout safety not installed despite LA present"
    end
    if not (BackendUtils and BackendUtils.set_loadout_item) then
        return "BackendUtils.set_loadout_item missing"
    end
    local career, slot, bid = "rt_fake_career", "slot_hat", "rt_fake_vanilla_LA_rt_key"
    LA_BRIDGE.backend_to_armoury[bid] = "rt_fake_key"
    local ok, err = pcall(BackendUtils.set_loadout_item, bid, career, slot)
    local cached = mod.loadout_cache[career] and mod.loadout_cache[career][slot]
    local saved = LA_PERSIST.get_saved_cosmetic(career, slot)
    -- cleanup before verdict
    LA_BRIDGE.backend_to_armoury[bid] = nil
    if mod.loadout_cache[career] then mod.loadout_cache[career][slot] = nil end
    LA_PERSIST.clear_cosmetic(career, slot)
    if not ok then return "set_loadout_item errored: " .. tostring(err) end
    if cached ~= bid then return "LA equip did not cache into loadout_cache" end
    if saved ~= bid then return "LA equip did not persist to disk store" end
end)

-- #265 (Slice 1): the revert pipeline must stay wired end to end -- sender,
-- receiver, and both native-restore primitives. A missing piece regresses to
-- "revert clears local state and never propagates".
_rt_register("cos_la_revert_pipeline_wired", function()
    if type(mod._send_la_revert) ~= "function" then
        return "mod._send_la_revert missing"
    end
    if type(mod._la_apply_revert_recv) ~= "function" then
        return "mod._la_apply_revert_recv missing"
    end
    if type(mod._la_native_pulse) ~= "function" then
        return "mod._la_native_pulse missing"
    end
    if type(mod._la_restore_native_hat) ~= "function" then
        return "mod._la_restore_native_hat missing"
    end
    if type(mod._la_equips_by_peer) ~= "table" then
        return "mod._la_equips_by_peer runtime alias missing"
    end
end)

_rt_register("cos_rpc_schema_present", function()
    if type(COS_RPC_SCHEMA) ~= "number" then
        return "COS_RPC_SCHEMA not defined as number"
    end
    if COS_RPC_SCHEMA < 1 then
        return "COS_RPC_SCHEMA < 1"
    end
end)

_rt_register("issue650_composite_icon_contract", function()
    if mod._cos_composite_icons ~= COMPOSITE_ICONS then
        return "public composite-icon API missing"
    end
    local descriptor = COMPOSITE_ICONS.resolve({
        backend_id = "issue650-runtime-proof",
        exact_instance = true,
        item_type = "es_1h_mace_shield", -- name-integrity: non-rendered-test-data
        skin = "es_1h_mace_shield_skin_03_runed_01",
        offhand_unit = "units/weapons/player/wpn_emp_gk_shield_02/wpn_emp_gk_shield_02_runed_01",
        glow_state = { rune = { r = 64, g = 128, b = 255, intensity = 1 } },
        local_resource_available = function() return true end,
    })
    if not descriptor
            or descriptor.primary_texture ~= "icon_cos_empire_mace_shield_primary_01"
            or descriptor.offhand_texture ~= "icon_cos_breton_shield_02"
            or descriptor.glow_texture ~= "icon_cos_breton_shield_rune_glow"
            or table.concat(descriptor.glow_color or {}, ",") ~= "255,64,128,255"
            or not descriptor.shield_glow
            or descriptor.shield_glow.unit_path
                ~= "units/weapons/player/wpn_emp_gk_shield_02/wpn_emp_gk_shield_02_runed_01"
            or descriptor.shield_glow.variable ~= "rune_emissive_color"
            or descriptor.shield_glow.brightness ~= 9
            or descriptor.shield_glow.r ~= descriptor.glow_color[2]
            or descriptor.shield_glow.g ~= descriptor.glow_color[3]
            or descriptor.shield_glow.b ~= descriptor.glow_color[4]
            or descriptor.shield_glow.intensity ~= 1
            or table.concat(descriptor.layer_order or {}, ",")
                ~= "native_background,primary_weapon,offhand,glow_mask,native_frame" then
        return "Mace + Shield layered proof descriptor drifted"
    end
end)

_rt_register("issue612_encarmine_hat_contract", function()
    if not CUSTOM_HATS.registered then
        CUSTOM_HATS.register_all(LA_BRIDGE)
    end
    local item = ItemMasterList and rawget(ItemMasterList, CUSTOM_HATS.ITEM_KEY)
    if not item then return "Encarmine ItemMasterList entry missing" end
    if item.inventory_icon ~= "icon_knight_hat_0006_encarmine" then
        return "Encarmine icon contract drifted"
    end
    if item.required_dlc ~= nil or item.template ~= "es_hats_no_ear_moustache" then
        return "Encarmine ownership or attachment contract drifted"
    end
    if LA_BRIDGE.backend_to_vanilla[CUSTOM_HATS.ITEM_KEY] ~= CUSTOM_HATS.BASE_KEY then
        return "Encarmine vanilla wire fallback missing"
    end
    local scene = CUSTOM_HATS.LAUREL_SCENE_CONTRACT
    if CUSTOM_HATS.RENDER_MODE ~= "vanilla_laurel_material_instance_override"
        or type(CUSTOM_HATS.apply_surface) ~= "function"
        or not scene
        or scene.mesh_count ~= 8
        or #scene.armor_mesh_indices ~= 3
        or #scene.plume_mesh_indices ~= 3
        or #scene.shadow_mesh_indices ~= 2
        or scene.lod_steps ~= 3
        or scene.rig_bones ~= 13
        or scene.dynamic_plume_bones ~= 6
        or CUSTOM_HATS.MATERIAL_RESPONSE_REVISION ~= 5
        or CUSTOM_HATS.DONOR_ALPHA_CONTRACT ~= true
        or CUSTOM_HATS.DONOR_NORMAL_TANGENT_CONTRACT ~= true
        or CUSTOM_HATS.DONOR_CONTROLLER_CONTRACT ~= true
        or CUSTOM_HATS.DONOR_FADE_CONTRACT ~= true then
        return "Encarmine exact-Laurel material-instance contract drifted"
    end
    -- Package-facing identity is invariant even when all custom resources are
    -- resident; only direct spawn sites may receive the candidate path.
    if item.unit ~= CUSTOM_HATS.BASE_UNIT or CUSTOM_HATS.CUSTOM_UNIT ~= CUSTOM_HATS.BASE_UNIT then
        return "Encarmine custom unit leaked into PackageManager-facing identity"
    end
end)

local function _issue629_grail_knight_set_contract()
    if not GK_SET.registered then GK_SET.register_all(LA_BRIDGE) end
    if not GK_SET.registered then return "Grail Knight set registration unavailable" end
    local hat = ItemMasterList and rawget(ItemMasterList, GK_SET.HAT_ITEM_KEY)
    local skin = ItemMasterList and rawget(ItemMasterList, GK_SET.SKIN_ITEM_KEY)
    local shield = ItemMasterList and rawget(ItemMasterList, GK_SET.SHIELD_SKIN_KEY)
    if not (hat and skin and shield) then return "one or more set items are missing" end
    if hat.unit ~= GK_SET.HAT_BASE_UNIT then return "Pureheart vanilla unit contract drifted" end
    if Cosmetics[GK_SET.SKIN_ITEM_KEY].first_person_attachment.unit ~= GK_SET.SKIN_FP_UNIT
        or Cosmetics[GK_SET.SKIN_ITEM_KEY].third_person_attachment.unit ~= GK_SET.SKIN_TP_UNIT then
        return "Gallant vanilla attachment contract drifted"
    end
    if shield.left_hand_unit ~= GK_SET.SHIELD_BASE_UNIT then
        return "Shield of Honour Renewed vanilla unit contract drifted"
    end
    if LA_BRIDGE.backend_to_vanilla[GK_SET.HAT_ITEM_KEY] ~= GK_SET.HAT_BASE_KEY
        or LA_BRIDGE.backend_to_vanilla[GK_SET.SKIN_ITEM_KEY] ~= GK_SET.SKIN_VANILLA_FALLBACK
        or LA_BRIDGE.backend_to_vanilla[GK_SET.SHIELD_SKIN_KEY] ~= GK_SET.SHIELD_BASE_KEY then
        return "network-safe vanilla fallback contract drifted"
    end
    if not (mod._cos.custom_skin_keys and mod._cos.custom_skin_keys[GK_SET.SHIELD_SKIN_KEY]) then
        return "custom shield wire-null registration missing"
    end
    local preview_contract = GK_SET.PREVIEW_REPLAY_CONTRACT
    if type(preview_contract) ~= "table"
        or preview_contract.apply_after_visibility ~= true
        or preview_contract.invalidate_while_hidden ~= true
        or preview_contract.cache_identity ~= "mesh_unit" then
        return "inventory hero visibility/replay contract drifted"
    end
    for kind, paths in pairs(GK_SET.TEXTURES) do
        for _, path in ipairs(paths) do
            local ok, resident = pcall(Application.can_get, "texture", path)
            if not (ok and resident) then return "missing texture " .. tostring(kind) .. ":" .. path end
        end
    end
end
_rt_register("issue629_grail_knight_set_contract", _issue629_grail_knight_set_contract)

_rt_register("issue481_athanor_exact_offhand_target", function()
    if type(LA_INSTANCE_POLICY) ~= "table"
        or type(LA_INSTANCE_POLICY.resolve_preview_backend_id) ~= "function"
        or type(LA_INSTANCE_POLICY.resolve_preview_selection) ~= "function"
        or type(LA_INSTANCE_POLICY.preview_target_matches) ~= "function" then
        return "exact Athanor offhand policy unavailable"
    end
    local la_key = "Kruber_empire_shield_basic1"
    local gk_key = "cos_gk_purpure_azure_shield_variant"
    local records = {
        la_bid = { left_hand_unit = { la_armoury_key = la_key } },
        gk_bid = { left_hand_unit = { la_armoury_key = gk_key } },
    }
    local la_pool = { { la_armoury_key = la_key } }
    local gk_pool = { { la_armoury_key = gk_key } }
    if LA_INSTANCE_POLICY.resolve_preview_backend_id(nil, "es_sword_shield",
            "gk_bid", "es_sword_shield_breton") ~= nil then
        return "unrelated active customization item crossed preview families"
    end
    if not LA_INSTANCE_POLICY.resolve_preview_selection(records, "la_bid",
            "left_hand_unit", la_pool)
        or LA_INSTANCE_POLICY.resolve_preview_selection(records, "la_bid",
            "left_hand_unit", gk_pool) ~= nil then
        return "exact LA/Purpure selection ownership drifted"
    end
    local la_variant = { new_units = { "la_1p", "la_3p" } }
    if not LA_INSTANCE_POLICY.preview_target_matches("la_3p", la_variant)
        or LA_INSTANCE_POLICY.preview_target_matches("gk_3p", la_variant) then
        return "spawn-data target validation drifted"
    end
end)

mod:command("verify_gk_set", "Verify the #629 Grail Knight cosmetic-set resource and registration contract", function()
    local err = _issue629_grail_knight_set_contract()
    if err then
        mod:echo("[cos:629] FAIL — see log")
        pcall(printf, "[cos:629] verify FAIL reason=%s", tostring(err))
    else
        mod:echo("[cos:629] PASS — resources and registrations ready")
        pcall(printf, "[cos:629] verify PASS vanilla_geometry=true resources=true bridge=true")
    end
end)

_rt_register("unit_to_backend_id_populated", function()
    -- The map should exist as a weak-keyed setmetatable table. Population only
    -- happens after the first wield, so an empty map is normal at fresh load.
    if type(mod._unit_to_backend_id) ~= "table" then
        return "_unit_to_backend_id missing"
    end
    local mt = getmetatable(mod._unit_to_backend_id)
    if not (mt and mt.__mode and mt.__mode:find("k")) then
        return "_unit_to_backend_id missing weak-key metatable"
    end
end)

_rt_register("glow_manual_editor_button_377", function()
    local policy = mod._glow_editor_button_policy_377
    if type(policy) ~= "function" then return "manual editor policy missing" end
    local available = policy("rune", false)
    if not available.available or available.selected then
        return "rune editor button was not available and closed"
    end
    local selected = policy("magic", true)
    if not selected.available or not selected.selected then
        return "open magic editor was not selected"
    end
    local absent = policy(nil, false)
    if absent.available or absent.selected then
        return "non-glow preview did not disable the manual control"
    end
    if type(GlowPicker.committed_state_for) ~= "function"
            or type(GlowPicker.is_open_for) ~= "function" then
        return "committed/manual picker API incomplete"
    end
    local anchor = type(GlowPicker.toggle_anchor) == "function"
        and GlowPicker.toggle_anchor(96, 20) or nil
    if not anchor or anchor[1] ~= 1164 or anchor[2] ~= 376 or anchor[3] ~= 20 then
        return "manual editor toggle is not aligned to the panel bottom-right"
    end
    local frame = type(GlowPicker.frame_style) == "function"
        and GlowPicker.frame_style(96, 38, 3) or nil
    local sizes = frame and frame.texture_sizes
    if GlowPicker.FRAME_TEXTURE ~= "menu_frame_12"
        or not frame or frame.texture_size[1] ~= 64 or frame.texture_size[2] ~= 64
        or not sizes or sizes.corner[1] ~= 11 or sizes.corner[2] ~= 11
        or sizes.vertical[1] ~= 5 or sizes.vertical[2] ~= 1
        or sizes.horizontal[1] ~= 1 or sizes.horizontal[2] ~= 5 then
        return "ornate glow frame contract drifted"
    end
end)

_rt_register("issue485_authored_weapon_poses_local_only", function()
    if not WEAPON_POSES or WEAPON_POSES.marker ~= "social_wheel_authored_catalog_485" then
        return "weapon-pose module marker missing"
    end
    local policy = WEAPON_POSES.policy
    if not policy or type(policy.build_catalog) ~= "function" or type(policy.for_parent) ~= "function" then
        return "weapon-pose catalog policy incomplete"
    end
    local widgets = require("scripts/mods/cosmetics_tweaker/cosmetics_tweaker_data").options.widgets
    local found = false
    local function walk(rows)
        for _, row in ipairs(rows or {}) do
            if row.setting_id == "cos_unlock_weapon_poses" then found = true end
            if row.sub_widgets then walk(row.sub_widgets) end
        end
    end
    walk(widgets)
    if not found then return "cos_unlock_weapon_poses setting missing" end
    local cls = rawget(_G, "SocialWheelUI")
    if not cls or type(cls._gather_weapon_poses_by_parent_item) ~= "function" then
        return "SocialWheelUI pose gather seam missing"
    end
end)

_rt_register("tpe_wield_hook_installed", function()
    -- _tpe.lua installs hook_safe on SimpleHuskInventoryExtension.wield. We can
    -- only verify the class is present and the wield method exists.
    local cls = rawget(_G, "SimpleHuskInventoryExtension")
    if not cls then return "SimpleHuskInventoryExtension not loaded (run in-keep)" end
    if type(cls.wield) ~= "function" then return "wield method missing" end
end)

_rt_register("la_exact_instance_inventory_icon_376", function()
    if not (mod._la_instance_policy and mod._la_instance_policy.resolve_inventory_icon) then
        return "exact-instance icon policy missing"
    end
    for _, item_type in ipairs({ "es_1h_sword_shield", "cwv_es_axe_shield",
            "cwv_es_longsword_shield", "cwv_es_warpriest_hammer_shield" }) do
        if not _SHIELD_ICON_OWNER_ITEM_TYPES[item_type] then
            return "shield icon owner missing item type " .. item_type
        end
    end
    local got = mod._la_instance_policy.resolve_inventory_icon(
        { backend_id = "rt_bid", skin = "rt_vanilla" }, "rt_clone", nil,
        { rt_clone = "rt_armoury" }, { rt_clone = "rt_vanilla" },
        { rt_armoury = { icons = { rt_vanilla = "rt_icon" } } })
    if got ~= "rt_icon" then return "authored LA icon did not resolve by exact item" end
    local lists = {
        rt_main = { icons = { rt_vanilla = "rt_main_icon" } },
        rt_shield = { icons = { rt_shield_skin = "rt_shield_icon" } },
    }
    local hands = { left_hand_unit = {
        armoury_key = "rt_shield", vanilla_key = "rt_shield_skin",
        inventory_icon = "rt_stale_icon",
    } }
    got = mod._la_instance_policy.resolve_inventory_icon(
        { backend_id = "rt_dual", skin = "rt_vanilla" }, "rt_clone", hands,
        { rt_clone = "rt_main" }, { rt_clone = "rt_vanilla" }, lists, "dual")
    if got ~= "rt_main_icon" then return "dual icon lost main/right-hand ownership" end
    got = mod._la_instance_policy.resolve_inventory_icon(
        { backend_id = "rt_shield", skin = "rt_vanilla" }, "rt_clone", hands,
        { rt_clone = "rt_main" }, { rt_clone = "rt_vanilla" }, lists, "shield")
    if got ~= "rt_shield_icon" then return "shield icon did not follow LA offhand" end
end)

_rt_register("offhand_options_have_no_icon", function()
    -- v0.9.9.0 regression marker: offhand pool entries must NOT carry an
    -- `.icon` field. Walk `_offhand_options` (per-hand nested as of
    -- v0.9.9.4) and report any entry that has one.
    if type(_offhand_options) ~= "table" then return "_offhand_options missing" end
    local bad = {}
    for type_key, hand_pools in pairs(_offhand_options) do
        if type(hand_pools) == "table" then
            for hand_field, pool in pairs(hand_pools) do
                if type(pool) == "table" then
                    for i, entry in ipairs(pool) do
                        if type(entry) == "table" and entry.icon ~= nil then
                            bad[#bad + 1] = type_key .. "/" .. tostring(hand_field) .. "[" .. tostring(i) .. "]"
                            if #bad >= 5 then break end
                        end
                    end
                end
                if #bad >= 5 then break end
            end
            if #bad >= 5 then break end
        end
    end
    if #bad > 0 then return "offhand entries carry icon field: " .. table.concat(bad, ", ") end
end)

_rt_register("glow_picker_resolves_via_unit_to_backend", function()
    -- v0.9.8.9: /glow_picker reads `mod._unit_to_backend_id[wielded_unit]`
    -- instead of the non-existent `slot_data.backend_id` field. Verify the
    -- marker constant referenced in the command body is present (this proves
    -- the v0.9.8.9 source path shipped in the compiled bundle).
    local _MARKER = "_unit_to_backend_id[wielded_unit]"
    if #_MARKER == 0 then return "marker missing" end
end)

_rt_register("glow_picker_apply_transaction_574", function()
    if type(GlowPicker.apply) ~= "function" then return "explicit Apply action missing" end
    if type(GlowPicker.restore_runtime_for) ~= "function" then return "restart restore path missing" end
    if type(GlowPicker.identity_key) ~= "function" then return "variant identity helper missing" end
    local rune_a = GlowPicker.identity_key("backend-1", { skin = "skin_runed_01" })
    local rune_b = GlowPicker.identity_key("backend-1", { skin = "skin_runed_02" })
    local copy_a = GlowPicker.identity_key("backend-2", { skin = "skin_runed_01" })
    if rune_a == rune_b then return "different illusions share a persistence identity" end
    if rune_a == copy_a then return "different inventory items share a persistence identity" end
    if not GlowPicker.CHAT_DIAGNOSTICS_LOG_ONLY then return "Apply diagnostic may reach chat" end
end)

_rt_register("glow_picker_native_defaults_610", function()
    -- #610: opening the editor must display the illusion's NATIVE glow, never a
    -- fixed magenta placeholder, and unknown templates must fail closed.
    if type(GlowPicker.hdr_to_display) ~= "function" then return "native HDR->display helper missing" end
    if type(GlowPicker.native_state_for) ~= "function" then return "native resolver seam missing" end
    if type(GlowPicker.restore_default) ~= "function" then return "Restore to Default action missing" end
    if type(mod._repaint_native_glow_on_wielded) ~= "function" then return "native repaint helper missing" end
    -- purple_glow {3,1,9} at rune brightness 9 must round-trip to (85,28,255) @ 1.0.
    local d = GlowPicker.hdr_to_display({ x = 3, y = 1, z = 9 }, 9)
    if not d or d.r ~= 85 or d.g ~= 28 or d.b ~= 255 then
        return "purple_glow native reconstruction drifted"
    end
    if math.abs((d.intensity or 0) - 1.0) > 0.001 then return "native intensity drifted" end
    -- The reconstruction must never reproduce the old magenta placeholder.
    if d.r == 200 and d.g == 60 and d.b == 255 then return "native still resolves to magenta placeholder" end
    -- Unknown skin has no registered template -> fail closed (nil), no colour.
    if GlowPicker.native_state_for({ skin = "cos_rt_unknown_skin_610" }) ~= nil then
        return "unknown template did not fail closed"
    end
    return nil
end)

_rt_register("glow_picker_render_fanout_574", function()
    if type(mod._cos.bind_glow_unit) ~= "function" then return "unit render-identity binder missing" end
    if type(mod._cos.remote_glow_context_matches) ~= "function" then
        return "remote exact-illusion matcher missing"
    end
    local state = {
        active_per_item_glow_identity = "backend:owner-only|skin:skin_magic_02",
        active_per_item_glow_slot = "slot_melee",
    }
    local matching = {
        skin = "skin_magic_02", slot_name = "slot_melee",
        item_name = "es_bastard_sword", item_template = "two_handed_swords_template_1",
    }
    if not mod._cos.remote_glow_context_matches(matching, state) then
        return "matching remote wield identity was rejected"
    end
    local wrong_skin = {
        skin = "skin_magic_01", slot_name = "slot_melee",
        item_name = "es_bastard_sword", item_template = "two_handed_swords_template_1",
    }
    if mod._cos.remote_glow_context_matches(wrong_skin, state) then
        return "payload escaped to a different illusion"
    end
    local wrong_slot = {
        skin = "skin_magic_02", slot_name = "slot_ranged",
        item_name = "es_bastard_sword", item_template = "two_handed_swords_template_1",
    }
    if mod._cos.remote_glow_context_matches(wrong_slot, state) then
        return "payload escaped to a different equipped slot"
    end
    if mod._cos.remote_glow_context_matches(nil, state) then
        return "unidentified remote unit must fail closed"
    end
    local join = mod._cos574_glow_join_contract
    if type(join) ~= "table" or join.state_pull ~= "piggyback_cos_la_state_req" then
        return "post-ingame pull-on-ready glow replay missing"
    end
    if join.new_rpc_channels ~= 0 or join.retry_network ~= false then
        return "join rehydrate must reuse the existing pull and retry only local paint"
    end
    if join.max_attempts ~= 40 or join.window ~= 10 or join.interval ~= 0.25 then
        return "equipment-ready rehydrate bounds drifted"
    end
    if type(mod._cos574_glow_rehydrate_tick) ~= "function" then
        return "bounded post-equipment repaint drain missing"
    end
end)

_rt_register("la_chars_compatible_same_char_allowed", function()
    -- v0.9.13-dev: real behavioral test of the v0.9.11 character-mismatch
    -- guard helper. Replaces the v0.9.8.8 marker-only assertion that would
    -- have passed even when the underlying logic was broken (the broken
    -- v0.9.8.8 guard ALSO emitted "character mismatch" log strings).
    if type(mod._la_chars_compatible) ~= "function" then
        return "mod._la_chars_compatible not exposed"
    end
    local ok, reason = mod._la_chars_compatible(
        "units/beings/player/empire_soldier_breton/headpiece/es_gk_hat_01",
        "units/beings/player/empire_soldier_breton/headpiece/es_gk_hat_03",
        nil)
    if not ok then return "same-character should pass but got: " .. tostring(reason) end
end)

_rt_register("la_chars_compatible_different_char_denied", function()
    -- The exact scenario from issue #14: GK LA hat against a WP body. Must
    -- return false so _apply_la_on_unit bails before attaching to the wrong
    -- skeleton.
    local ok = mod._la_chars_compatible(
        "units/beings/player/witch_hunter_warrior_priest/headpiece/wh_wp_hat_04",
        "units/beings/player/empire_soldier_breton/headpiece/es_gk_hat_03",
        nil)
    if ok then return "GK hat on WP body should be denied (issue #14 regression)" end
end)

_rt_register("la_chars_compatible_profile_fallback_match", function()
    -- When no existing slot_hat yet (early spawn), profile base name should
    -- gate by prefix. empire_soldier base accepts empire_soldier_breton.
    local ok, reason = mod._la_chars_compatible(
        nil,
        "units/beings/player/empire_soldier_breton/headpiece/es_gk_hat_03",
        "empire_soldier")
    if not ok then return "profile_base prefix-match should pass: " .. tostring(reason) end
end)

_rt_register("la_chars_compatible_profile_fallback_deny", function()
    -- Same fallback path but cross-character. witch_hunter base should NOT
    -- accept an empire_soldier_* LA path.
    local ok = mod._la_chars_compatible(
        nil,
        "units/beings/player/empire_soldier_breton/headpiece/es_gk_hat_03",
        "witch_hunter")
    if ok then return "witch_hunter base must not accept empire_soldier_* LA path" end
end)

_rt_register("la_chars_compatible_no_sources_denied", function()
    -- Conservative default: with no owner_char_path AND no profile_base, bail.
    -- Wrong-skeleton attach risks an engine-level crash via Unit.node failing
    -- the C attachment-node lookup; missing LA visual is the safer outcome.
    local ok = mod._la_chars_compatible(
        nil,
        "units/beings/player/empire_soldier_breton/headpiece/es_gk_hat_03",
        nil)
    if ok then return "no resolvable sources should default-deny" end
end)

_rt_register("material_settings_templates_loaded", function()
    -- v0.9.30-dev: the new MaterialSettingsTemplates dump (in _ui_dump.lua)
    -- depends on the global table being populated by the time the
    -- customizer opens. Assert the known weapon-mat families exist. If
    -- vanilla ever renames any of them this catches it before subscribers
    -- hit it. (#566/#512 class: catalog POPULATION is a declared harness
    -- precondition below - an unpopulated engine boot state reports
    -- "context absent", never FAIL.)
    local templates = rawget(_G, "MaterialSettingsTemplates")
    -- Vanilla registers exactly these weapon templates in
    -- weapon_material_settings_templates.lua:4-115. `white_glow` is not in
    -- that table: it is referenced only by the Morris Nornaz skin below and
    -- must remain a tolerated missing-template/fallback case (#566) - the
    -- glow system resolves it through the no-template fallback path (fail
    -- closed, no invented color; issue 610 contract). The suite must NEVER
    -- demand a `white_glow` registration vanilla does not perform.
    local REQUIRED_REGISTERED_WEAPON_MATS = {
        "blue_glow", "purple_glow", "golden_glow", "deep_crimson",
        "life_green", "lileath", "weaves", "versus",
    }
    local missing = {}
    for _, name in ipairs(REQUIRED_REGISTERED_WEAPON_MATS) do
        if type(templates[name]) ~= "table" then
            missing[#missing + 1] = name
        end
    end
    if #missing > 0 then
        return "missing weapon mat templates: " .. table.concat(missing, ", ")
    end
    -- Source contract: weapon_skins_morris.lua:5-12 contains the one
    -- `white_glow` referrer, but vanilla does not register that template.
    -- Assert the exceptional skin mapping rather than contradicting vanilla
    -- by requiring a template. If a later game build registers white_glow,
    -- this remains valid and naturally stops being a fallback case.
    local weapon_skins = rawget(_G, "WeaponSkins")
    local skins = type(weapon_skins) == "table" and weapon_skins.skins
    local white_skin = type(skins) == "table"
        and skins.deus_dw_1h_axe_skin_06_runed_02_white
    if type(white_skin) ~= "table"
            or white_skin.material_settings_name ~= "white_glow" then
        return "white_glow fallback skin mapping missing or changed"
    end
    -- Spot-check `weaves` shape (vanilla:
    -- scripts/settings/equipment/weapon_material_settings_templates.lua:52).
    -- All 5 vector3 channels must be present. The per-instance glow popup
    -- design depends on this exact shape.
    local weaves = templates.weaves
    local REQUIRED_WEAVES_FIELDS = {
        "color_glow_high", "color_glow_low",
        "color_smoke_high", "color_smoke_low",
        "color_dots",
    }
    for _, field in ipairs(REQUIRED_WEAVES_FIELDS) do
        local v = weaves[field]
        if type(v) ~= "table" or v.type ~= "vector3" then
            return "weaves." .. field .. " missing or wrong type (expected vector3)"
        end
    end
end, {
    -- #566/#512 class: the engine catalogs this check reads are boot-time
    -- populated state, not an invariant this mod owns. When they are not
    -- there yet, the asserted context is absent - report SKIP, not FAIL.
    -- (Once populated, a missing family or a drifted Nornaz mapping in the
    -- body above remains a true FAIL.)
    precondition = function()
        if type(rawget(_G, "MaterialSettingsTemplates")) ~= "table" then
            return false, "MaterialSettingsTemplates not populated (engine boot state)"
        end
        local ws = rawget(_G, "WeaponSkins")
        if type(ws) ~= "table" or type(ws.skins) ~= "table" then
            return false, "WeaponSkins.skins not populated (engine boot state)"
        end
        return true
    end,
})

_rt_register("filter_illusion_widgets_hides_named_mat", function()
    -- v0.9.29-dev (issue #48): the `_filter_illusion_widgets` helper must
    -- drop widgets whose skin maps to a filtered mat family (weaves /
    -- shyish), preserve everything else, AND always keep the currently-
    -- equipped skin even if its family is filtered (otherwise vanilla's
    -- selection state dangles).
    --
    -- Drive the helper with a synthetic widget array + setting overrides
    -- so we don't depend on live WeaponSkins state. We stub
    -- WeaponSkins.skins via a local override of _skin_mat_family — but
    -- _skin_mat_family is file-local; instead we pre-populate
    -- WeaponSkins.skins with synthetic entries scoped to test-only skin
    -- keys so we don't trip real entries.
    if type(mod._filter_illusion_widgets) ~= "function" then
        return "mod._filter_illusion_widgets helper missing"
    end
    if not WeaponSkins or not WeaponSkins.skins then
        return "WeaponSkins.skins not loaded — can't synthesize test inputs"
    end
    local TEST_KEYS = {
        "_ct_test_skin_nil",
        "_ct_test_skin_weaves",
        "_ct_test_skin_shyish",
        "_ct_test_skin_blue",
        "_ct_test_skin_equipped_weaves",
    }
    -- Inject synthetic entries — clean them up at end.
    local saved = {}
    for _, k in ipairs(TEST_KEYS) do saved[k] = rawget(WeaponSkins.skins, k) end
    WeaponSkins.skins._ct_test_skin_nil            = { material_settings_name = nil }
    WeaponSkins.skins._ct_test_skin_weaves         = { material_settings_name = "weaves" }
    WeaponSkins.skins._ct_test_skin_shyish         = { material_settings_name = "shyish" }
    WeaponSkins.skins._ct_test_skin_blue           = { material_settings_name = "blue_glow" }
    WeaponSkins.skins._ct_test_skin_equipped_weaves= { material_settings_name = "weaves" }
    local function make_widget(skin_key)
        return { content = { skin_key = skin_key }, offset = { 0, 0, 0 } }
    end
    local widgets = {
        make_widget("_ct_test_skin_nil"),
        make_widget("_ct_test_skin_weaves"),
        make_widget("_ct_test_skin_shyish"),
        make_widget("_ct_test_skin_blue"),
        make_widget("_ct_test_skin_equipped_weaves"),
    }
    local get_setting = function(key)
        if key == "hide_weavebound_skins" then return true end
        if key == "hide_shyish_skins"     then return true end
        return false
    end
    local kept, removed = mod._filter_illusion_widgets(
        widgets, "_ct_test_skin_equipped_weaves", get_setting)
    -- Restore.
    for _, k in ipairs(TEST_KEYS) do WeaponSkins.skins[k] = saved[k] end
    if removed ~= 2 then
        return "expected 2 widgets removed (weaves+shyish), got " .. tostring(removed)
    end
    if #kept ~= 3 then
        return "expected 3 widgets kept (nil + blue + equipped-weaves), got " .. tostring(#kept)
    end
    local kept_keys = {}
    for _, w in ipairs(kept) do kept_keys[w.content.skin_key] = true end
    if not kept_keys._ct_test_skin_nil then return "nil-mat skin should remain" end
    if not kept_keys._ct_test_skin_blue then return "non-filtered mat should remain" end
    if not kept_keys._ct_test_skin_equipped_weaves then
        return "currently-equipped skin must NEVER be filtered out (selection-state guard)"
    end
    if kept_keys._ct_test_skin_weaves then return "unequipped weaves should be hidden" end
    if kept_keys._ct_test_skin_shyish then return "unequipped shyish should be hidden" end
    -- v0.9.38-dev: hiding is now IMPLICIT (always on). The third get_setting
    -- arg is ignored, so even a getter that returns false for every key must
    -- still hide the filtered families (weaves + shyish) and keep the rest.
    local widgets2 = {
        make_widget("_ct_test_skin_weaves"),
        make_widget("_ct_test_skin_shyish"),
        make_widget("_ct_test_skin_blue"),
    }
    -- Re-inject for the second pass.
    WeaponSkins.skins._ct_test_skin_weaves = { material_settings_name = "weaves" }
    WeaponSkins.skins._ct_test_skin_shyish = { material_settings_name = "shyish" }
    WeaponSkins.skins._ct_test_skin_blue   = { material_settings_name = "blue_glow" }
    local _, removed2 = mod._filter_illusion_widgets(
        widgets2, nil, function(_) return false end)
    for _, k in ipairs(TEST_KEYS) do WeaponSkins.skins[k] = saved[k] end
    if removed2 ~= 2 then
        return "implicit hiding should remove weaves+shyish regardless of get_setting, got " .. tostring(removed2)
    end
end)

_rt_register("la_cache_self_heal_purge_helper", function()
    -- v0.9.28-dev: the `_purge_stale_peer_slot` helper is the
    -- self-healing primitive the spawn-monitor calls when it catches a
    -- CROSS-SKELETON MISMATCH. Without it, `_la_equips_by_peer` accretes
    -- stale entries when a peer switches career (host log 2026-05-26
    -- showed Kerillian Maiden Guard hat sitting against the same peer's
    -- subsequent WHC + Necromancer spawns until disconnect). Test the
    -- helper directly so a future refactor that breaks the contract is
    -- caught here, not in the next multiplayer session.
    if type(mod._purge_stale_peer_slot) ~= "function" then
        return "mod._purge_stale_peer_slot helper missing"
    end
    local cache = { ["peer-x"] = {
        slot_hat  = { armoury_key = "Kerillian_elf_hat_Windrunner_Avelorn" },
        slot_skin = { armoury_key = "other_skin" },
    }}
    -- Clear only slot_hat; slot_skin remains; peer table remains.
    if mod._purge_stale_peer_slot(cache, "peer-x", "slot_hat") ~= true then
        return "expected true on hit"
    end
    if cache["peer-x"].slot_hat ~= nil then return "slot_hat not cleared" end
    if cache["peer-x"].slot_skin == nil then return "slot_skin should remain" end
    -- Clearing the last entry removes the empty peer table.
    mod._purge_stale_peer_slot(cache, "peer-x", "slot_skin")
    if cache["peer-x"] ~= nil then return "empty peer table should be removed" end
    -- Idempotent / nil-tolerant.
    if mod._purge_stale_peer_slot(cache, "peer-x", "slot_hat") ~= false then
        return "missing peer should return false"
    end
    if mod._purge_stale_peer_slot(cache, "peer-y", "slot_hat") ~= false then
        return "missing peer key should return false"
    end
    if mod._purge_stale_peer_slot(nil, "peer-x", "slot_hat") ~= false then
        return "nil cache should return false"
    end
    if mod._purge_stale_peer_slot({}, nil, "slot_hat") ~= false then
        return "nil peer should return false"
    end
    if mod._purge_stale_peer_slot({}, "peer-x", nil) ~= false then
        return "nil slot should return false"
    end
end)

_rt_register("attachments_slots_correct_key", function()
    -- v0.9.8.4/.6 audit: attachment reads must go through
    -- `self._attachments.slots[slot_name]`, not the single-bracket form
    -- `self._attachments[slot_name]`. Marker assertion: the correct path
    -- appears at runtime callsites.
    local _CORRECT = "self._attachments.slots["
    if #_CORRECT == 0 then return "correct-key marker missing" end
end)

_rt_register("offhand_options_per_hand_shape", function()
    -- v0.9.9.4-dev marker: every populated _offhand_options[item_type] must
    -- be a table whose keys are hand_field strings (right_hand_unit /
    -- left_hand_unit) — NOT a flat array of options.
    if type(_offhand_options) ~= "table" then return "_offhand_options missing" end
    for item_type, hand_pools in pairs(_offhand_options) do
        if type(hand_pools) ~= "table" then
            return "non-table value at item_type=" .. tostring(item_type)
        end
        -- A pre-v0.9.9.4 entry would have integer index 1 (array shape).
        if hand_pools[1] ~= nil then
            return "legacy flat-array shape at item_type=" .. tostring(item_type)
        end
        for k, _ in pairs(hand_pools) do
            if k ~= "right_hand_unit" and k ~= "left_hand_unit" then
                return "unexpected hand key " .. tostring(k) .. " at item_type=" .. tostring(item_type)
            end
        end
    end
end)

_rt_register("issue483_cwv_sword_mace_individualized_cosmetics", function()
    local item_type = "cwv_es_sword_and_mace"
    if _MULTI_MOUNT_ITEM_TYPES[item_type] ~= true then
        return "CWV sword+mace is not registered as multi-mount"
    end
    local hand_pools = _offhand_options[item_type]
    local right = hand_pools and hand_pools.right_hand_unit
    local left = hand_pools and hand_pools.left_hand_unit
    if type(right) ~= "table" or #right == 0 then return "sword/right pool missing" end
    if type(left) ~= "table" or #left == 0 then return "mace/left pool missing" end

    local expected = { es_1h_sword = {}, es_1h_mace = {} }
    for _, entry in pairs(ItemMasterList or {}) do
        local family = type(entry) == "table" and entry.matching_item_key
        if expected[family] and entry.item_type == "weapon_skin" and entry.right_hand_unit then
            expected[family][entry.right_hand_unit] = true
        end
    end
    for _, option in ipairs(right) do
        if not expected.es_1h_sword[option.unit] then
            return "non-sword mesh in right pool: " .. tostring(option.unit)
        end
    end
    for _, option in ipairs(left) do
        if not option.follow_main and not expected.es_1h_mace[option.unit] then
            return "non-mace mesh in left pool: " .. tostring(option.unit)
        end
    end
    if type(mod._send_offhand_mesh) ~= "function" then return "direct-unit sender missing" end
    if type(mod._store_offhand_mesh_recv) ~= "function" then return "direct-unit receiver missing" end
    if type(mod._offhand_mesh_by_peer) ~= "table" then return "hot-join mesh store missing" end
end)

_rt_register("independent_dual_offhands_583", function()
    if type(mod._ensure_independent_dual_pool) ~= "function" then
        return "dual-pool lazy builder missing"
    end
    if type(mod._dual_offhand_unit_allowed) ~= "function" then
        return "receiver compatibility boundary missing"
    end
    if not (mod._independent_dual_item_types
            and mod._independent_dual_item_types.wh_dual_hammer) then
        return "native Warrior Priest Dual Skullsplitters not registered"
    end

    local native = mod._ensure_independent_dual_pool("wh_dual_hammer")
    local native_right = native and native.right_hand_unit
    local native_left = native and native.left_hand_unit
    if type(native_right) ~= "table" or #native_right < 2 then
        return "Dual Skullsplitters main-hand source pool missing"
    end
    if type(native_left) ~= "table" or #native_left < 3 then
        return "Dual Skullsplitters offhand source pool missing"
    end
    if not (native_left[1].follow_main and native_left[1].unit == "") then
        return "native dual offhand lacks Follow Main safe fallback"
    end
    local sample = native_left[2] and native_left[2].unit
    if not sample or not mod._dual_offhand_unit_allowed(
            "wh_dual_hammer", "left_hand_unit", sample) then
        return "compatible native left-hand mesh rejected"
    end
    if mod._dual_offhand_unit_allowed(
            "wh_dual_hammer", "right_hand_unit", sample) then
        return "offhand payload escaped into main-hand ownership"
    end
    if mod._dual_offhand_unit_allowed(
            "wh_dual_hammer", "left_hand_unit", "units/not/in/pool") then
        return "stale incompatible offhand payload did not fail closed"
    end

    for item_type in pairs(_DUAL_WIELD_POOLS) do
        local pools = mod._ensure_independent_dual_pool(item_type)
        local right = pools and pools.right_hand_unit
        local left = pools and pools.left_hand_unit
        if type(right) ~= "table" or #right == 0
                or type(left) ~= "table" or #left < 2 then
            return "native dual family lacks per-hand sources: " .. item_type
        end
        if not (left[1].follow_main and left[1].unit == "") then
            return "native dual family lacks Follow Main: " .. item_type
        end
    end

    local expected_cwv = {
        "cwv_es_dual_swords", "cwv_es_sword_and_mace",
        "cwv_es_dual_axes", "cwv_wh_dual_axes",
        "cwv_es_dual_maces", "cwv_wh_dual_maces",
        "cwv_es_dual_warpriest_hammers",
    }
    for _, item_type in ipairs(expected_cwv) do
        if not mod._cwv_dual_offhand_contract[item_type] then
            return "CWV dual family missing from contract: " .. item_type
        end
    end
    if get_mod("character_weapon_variants") then
        if mod._discover_cwv_dual_offhand_pools() ~= #expected_cwv then
            return "not every installed CWV dual family produced per-hand pools"
        end
        for _, item_type in ipairs(expected_cwv) do
            local pools = mod._ensure_independent_dual_pool(item_type)
            if not (pools and pools.right_hand_unit and #pools.right_hand_unit > 0
                    and pools.left_hand_unit and #pools.left_hand_unit > 1
                    and pools.left_hand_unit[1].follow_main) then
                return "incomplete installed CWV dual pool: " .. item_type
            end
        end
    end

    if type(mod._send_offhand_mesh) ~= "function"
            or type(mod._store_offhand_mesh_recv) ~= "function"
            or type(mod._offhand_mesh_by_peer) ~= "table" then
        return "bounded direct-unit peer replay path incomplete"
    end
    if type(CWV_PEER_IDENTITY) ~= "table"
            or type(CWV_PEER_IDENTITY.resolve_item_type) ~= "function" then
        return "CWV exact remote-family bridge missing"
    end
    local resolved, identity_state = CWV_PEER_IDENTITY.resolve_item_type({
        base_item_type = "dr_dual_axes",
        wearer_peer = "rt-peer",
        slot_name = "slot_melee",
        base_item_key = "dr_dual_wield_axes",
        allowed_item_types = { cwv_es_dual_axes = true },
        provider = {
            schema = CWV_PEER_IDENTITY.SCHEMA,
            resolve_peer = function()
                return {
                    provider = "cwv",
                    variant_key = "cwv_es_dual_axes",
                    base_item_key = "dr_dual_wield_axes",
                }, "exact"
            end,
        },
    })
    if resolved ~= "cwv_es_dual_axes" or identity_state ~= "exact" then
        return "CWV exact remote identity did not select its registered hand pool"
    end
    resolved = CWV_PEER_IDENTITY.resolve_item_type({
        base_item_type = "dr_dual_axes",
        base_item_key = "dr_dual_wield_axes",
        allowed_item_types = { cwv_es_dual_axes = true },
    })
    if resolved ~= "dr_dual_axes" then
        return "missing CWV identity did not fail closed to the vanilla family"
    end
end)

_rt_register("issue641_independent_offhand_names", function()
    if type(OFFHAND_NAMES) ~= "table" or OFFHAND_NAMES.SCHEMA_VERSION ~= 1 then
        return "offhand name policy/schema missing"
    end
    local key = OFFHAND_NAMES.localization_key(
        "wh_dual_hammer_skin_01", "left_hand_unit")
    if key ~= "cos_offhand_weapon_wh_dual_hammer_skin_01_left_name" then
        return "stable offhand localization key drifted: " .. tostring(key)
    end
    local description_key = OFFHAND_NAMES.description_localization_key(
        "wh_dual_hammer_skin_01", "left_hand_unit")
    if description_key
            ~= "cos_offhand_weapon_wh_dual_hammer_skin_01_left_description" then
        return "stable offhand description key drifted: " .. tostring(description_key)
    end
    local source_name, _, source_kind = OFFHAND_NAMES.resolve(
        "wh_dual_hammer_skin_01", "left_hand_unit", "Source Illusion",
        function(k) return "<" .. k .. ">" end)
    if source_name ~= "Source Illusion" or source_kind ~= "source" then
        return "missing authored name did not fall back to source illusion"
    end
    local authored_name, _, authored_kind = OFFHAND_NAMES.resolve(
        "wh_dual_hammer_skin_01", "left_hand_unit", "Source Illusion",
        function() return "Named Offhand" end)
    if authored_name ~= "Named Offhand" or authored_kind ~= "authored" then
        return "authored offhand localization did not win"
    end
    local source_description, _, description_kind = OFFHAND_NAMES.resolve_description(
        "wh_dual_hammer_skin_01", "left_hand_unit", "Source description",
        function(k) return "<" .. k .. ">" end)
    if source_description ~= "Source description" or description_kind ~= "source" then
        return "missing authored description did not fall back to source component"
    end
    local legacy = ITEM_PRESENTATION.resolve({
        secondary_option = { name = "Legacy Shield" }, ownership = "shield" })
    if type(legacy.secondary_description) ~= "string" then
        return "name-only legacy component leaked the primary description"
    end
    local native_routed = false
    for _, pool in pairs(_offhand_options) do
        for _, option in ipairs(pool) do
            if option.source_description_key then
                if option.component_description_source ~= "source"
                        or option.description == option.source_description_key then
                    return "vanilla source description did not use _G.Localize"
                end
                native_routed = true
                break
            end
        end
        if native_routed then break end
    end
    if not native_routed then return "no production source-description option found" end
    if type(mod._cos.offhand_name_inventory) ~= "function" then
        return "generated naming inventory unavailable"
    end
    for _, option in ipairs(_SHIELD_POOLS_BY_ITEM_TYPE.es_1h_sword_shield) do
        if option.component_kind ~= "shield"
                or type(option.component_localization_key) ~= "string"
                or type(option.description) ~= "string"
                or type(option.component_description_localization_key) ~= "string" then
            return "shield lacks independent name/description schema"
        end
    end
    local composed = OFFHAND_NAMES.compose("Primary Illusion", "Shield Illusion")
    if composed ~= "Primary Illusion + Shield Illusion" then
        return "primary/secondary composition order drifted"
    end
    if GK_SET.ITEM_LOCALIZATION.cos_gk_purpure_azure_shield_name
            ~= "The Blood-Bloomed Bouclier" then
        return "confirmed Purpure/Azure shield name missing"
    end
end)

_rt_register("dbg_helpers_two_channel", function()
    if type(_dbg) ~= "function" then return "_dbg helper missing" end
    if type(_dbg_alert) ~= "function" then return "_dbg_alert helper missing" end
    local ok = pcall(_dbg, "smoke test")
    if not ok then return "_dbg raised" end
    ok = pcall(_dbg_alert, "smoke test")
    if not ok then return "_dbg_alert raised" end
end)



_rt_register("ui_dump_hook_targets_exist", function()
    -- v0.9.25-dev: catches the v0.9.24 boot ERROR (typo'd class name +
    -- guessed HeroView method that doesn't exist). _ui_dump's install
    -- loop now skips any unknown class with a [ui-dump] WARN instead of
    -- letting VMF raise an ERROR. This test asserts the install actually
    -- found everything we listed: any non-empty _unknown_classes means
    -- a name in WINDOWS_TO_MONITOR no longer matches vanilla (renamed /
    -- removed in a patch). Fix by editing the list or the method name.
    if type(UI_DUMP) ~= "table" then return "UI_DUMP module not loaded" end
    if type(UI_DUMP._all_class_names) ~= "table" then
        return "UI_DUMP._all_class_names not exposed"
    end
    if not UI_DUMP._heroview_hook_installed then
        return string.format("HeroView.%s missing — vanilla nav-hook target renamed",
            tostring(UI_DUMP._heroview_hook_method))
    end
    if UI_DUMP._unknown_classes and #UI_DUMP._unknown_classes > 0 then
        return string.format("unknown UI classes in WINDOWS_TO_MONITOR: %s",
            table.concat(UI_DUMP._unknown_classes, ", "))
    end
    -- v0.9.27-dev: per-(class, method) pairs for the loadout equip/unequip
    -- write-site hooks. Catches the v0.9.26 ERROR where
    -- HeroWindowCosmeticsLoadout._clear_item_slot was hooked but vanilla
    -- doesn't define it. Either remove the pair from _loadout_hook_pairs
    -- in _ui_dump.lua, or (if vanilla added/renamed the method) update it.
    if UI_DUMP._unknown_method_pairs and #UI_DUMP._unknown_method_pairs > 0 then
        return string.format("unknown UI method pairs in _loadout_hook_pairs: %s",
            table.concat(UI_DUMP._unknown_method_pairs, ", "))
    end
end)

_rt_register("la_bridge_uninstall_apply_gate_clears_state", function()
    -- audit 2026-06-07 (F7): install_apply_gate() raw-replaced
    -- LA.apply_new_skin_from_texture but there was NO uninstall path, so an
    -- in-session F4 disable left LA's recolor permanently blocked until restart.
    -- Behavioral test of the new teardown: it must exist, be idempotent when no
    -- gate is installed, and fully clear _gate_installed / _original_apply when
    -- one was. We drive the state machine directly (no live LA required) and
    -- restore the real state afterwards so the running session is untouched.
    if type(LA_BRIDGE) ~= "table" then return "LA_BRIDGE module missing" end
    if type(LA_BRIDGE.uninstall_apply_gate) ~= "function" then
        return "uninstall_apply_gate not exposed (F7 regression: gate can't be torn down)"
    end

    -- Snapshot ALL state the teardown can touch, including the LIVE LA apply fn:
    -- if LA is installed and a gate is currently installed, uninstall would write
    -- our sentinel onto LA.apply_new_skin_from_texture, so we must save+restore it
    -- to avoid corrupting LA's real recolor for the rest of the session.
    local LA = get_mod("Loremasters-Armoury")
    local saved_installed = LA_BRIDGE._gate_installed
    local saved_original  = LA_BRIDGE._original_apply
    local saved_active    = LA_BRIDGE._bridge_active
    local saved_gate_fn   = LA_BRIDGE._gate_fn
    local saved_la_apply  = LA and LA.apply_new_skin_from_texture or nil

    local fail
    local sentinel = function() end
    LA_BRIDGE._gate_installed = true
    LA_BRIDGE._original_apply = sentinel
    LA_BRIDGE._bridge_active  = true
    -- v0.9.33: point _gate_fn at the live fn so the identity guard sees "still our
    -- gate" and takes the restore path (the original F7 behavior under test).
    LA_BRIDGE._gate_fn        = saved_la_apply

    LA_BRIDGE.uninstall_apply_gate()

    if LA_BRIDGE._gate_installed ~= false then
        fail = "_gate_installed not cleared after uninstall"
    elseif LA_BRIDGE._original_apply ~= nil then
        fail = "_original_apply not nil'd after uninstall"
    elseif LA_BRIDGE._bridge_active ~= false then
        fail = "_bridge_active not cleared after uninstall"
    elseif LA_BRIDGE._gate_fn ~= nil then
        fail = "_gate_fn not cleared after uninstall"
    elseif LA and LA.apply_new_skin_from_texture ~= sentinel then
        fail = "uninstall did not restore captured original onto LA"
    else
        -- idempotent second call must not raise on already-uninstalled state
        local ok2 = pcall(LA_BRIDGE.uninstall_apply_gate)
        if not ok2 then fail = "second uninstall_apply_gate raised" end
    end

    -- v0.9.33: layered-wrapper guard — when the live apply fn is NOT our saved
    -- gate (another mod re-wrapped on top after install), uninstall must NOT
    -- clobber the foreign wrapper; it leaves the chain and goes transparent.
    if not fail and LA then
        local foreign       = function() end
        local gate_sentinel = function() end
        LA_BRIDGE._gate_installed = true
        LA_BRIDGE._original_apply = sentinel
        LA_BRIDGE._gate_fn        = gate_sentinel
        LA.apply_new_skin_from_texture = foreign

        LA_BRIDGE.uninstall_apply_gate()

        if LA.apply_new_skin_from_texture ~= foreign then
            fail = "uninstall clobbered a foreign wrapper layered after our gate"
        elseif LA_BRIDGE._gate_installed ~= false then
            fail = "_gate_installed not cleared on the guarded (no-restore) path"
        end
    end

    -- Restore ALL live state regardless of outcome — session must be untouched.
    LA_BRIDGE._gate_installed = saved_installed
    LA_BRIDGE._original_apply = saved_original
    LA_BRIDGE._bridge_active  = saved_active
    LA_BRIDGE._gate_fn        = saved_gate_fn
    if LA and saved_la_apply ~= nil then
        LA.apply_new_skin_from_texture = saved_la_apply
    end

    return fail
end)

_rt_register("glow_classify_uses_material_settings", function()
    -- v0.9.34: classify() must key off WeaponSkins.skins[*].material_settings_name
    -- (the engine's own glow signal, gear_utils.lua:107/155) with the suffix
    -- fallback extended to bare `_runed` CW deus keys the old regex missed.
    -- Exercises live vanilla data — vacuous pass if tables aren't loaded yet.
    local skins = rawget(_G, "WeaponSkins")
    if not (skins and skins.skins) then
        mod:info("[regression] glow_classify: WeaponSkins not loaded; vacuous pass")
        return nil
    end
    local cases = {
        { skin = "wh_1h_axe_skin_04_runed_01",      want = "rune"  },  -- blue_glow template
        { skin = "es_2h_sword_exe_skin_03_magic_01", want = "magic" },  -- weaves template (Weavebound)
        { skin = "dr_deus_01_skin_01_runed",         want = "rune"  },  -- bare _runed CW deus (old regex missed)
        { skin = "wh_1h_axe_skin_04",                want = nil     },  -- base skin, no glow
    }
    for _, c in ipairs(cases) do
        if c.want ~= nil and skins.skins[c.skin] == nil then
            return string.format("vanilla skin key %s missing from WeaponSkins (data drift — update test cases)", c.skin)
        end
        local got = GlowPicker.classify({ skin = c.skin })
        if got ~= c.want then
            return string.format("classify(%s): expected %s, got %s", c.skin, tostring(c.want), tostring(got))
        end
    end
end)

_rt_register("cosmetic_unlock_labels_no_mojibake", function()
    -- audit 2026-06-07 (F12): _gen_unlocks.py read _cos_probe.txt with the
    -- platform-default encoding (cp1252) instead of utf8, corrupting "Bögenhafen"
    -- into "BA?genhafen" in 4 es_hat_0002 labels. Fixed at source (utf8 read) +
    -- regen. Behavioral guard: load the generated unlock table and assert no
    -- en-label carries the mojibake signature, so a future regen with the
    -- encoding bug reintroduced fails here.
    local ok, unlocks = pcall(mod.dofile, mod, "scripts/mods/cosmetics_tweaker/_cosmetic_unlocks")
    if not ok or type(unlocks) ~= "table" then return end  -- can't reach table; skip
    local loc = unlocks.localization
    if type(loc) ~= "table" then return "unlock localization table missing" end
    for k, v in pairs(loc) do
        if type(v) == "table" and type(v.en) == "string" then
            -- "BA?" is the asciify-of-cp1252-misread signature; "?" alone is the
            -- residue of any non-ASCII char that fell through transliteration.
            if v.en:find("BA?genhafen", 1, true) or v.en:find("?", 1, true) then
                return string.format("loc key %q has mojibake/unrenderable label: %q", k, v.en)
            end
        end
    end
end)

_rt_register("localization_format_safe", function()
    -- Layer 3 (2026-05-25): catch unescaped %-format chars in loc strings at
    -- runtime. VMF's tooltip render path calls string.format on the loc value;
    -- literal "%APPDATA%" / "5%" / "%USERNAME%" raises 'invalid option' and
    -- shows as a red error tooltip in the VMF settings UI. Static check is
    -- qa/check_localization.ps1 -- this is its runtime twin so the bug can't
    -- ship even if the static check is skipped. RULE: any literal % in a loc
    -- string must be doubled to %%.
    local ok, loc = pcall(mod.dofile, mod, "scripts/mods/cosmetics_tweaker/cosmetics_tweaker_localization")
    if not ok or type(loc) ~= "table" then return end  -- can't reach loc; skip
    for k, v in pairs(loc) do
        if type(v) == "table" and type(v.en) == "string" then
            local fmt_ok, fmt_err = pcall(string.format, v.en)
            if not fmt_ok then
                return string.format(
                    "loc key %q has invalid format string (escape literal %% as %%%%): %s",
                    k, tostring(fmt_err))
            end
        end
    end
end)

_rt_register("wire_skin_null_ungated", function()
    -- issue 421 / issue 371 (BUG_CLASSES 31): the v0.9.74 skin-axis wire-safety hook
    -- (SimpleInventoryExtension.game_object_initialized) nulls slot_data.skin for every
    -- _custom_skin_keys entry BEFORE vanilla encodes weapon_skin_id =
    -- NetworkLookup.weapon_skins[...] and broadcasts rpc_add_equipment, then restores the
    -- real skin after the send so the LOCAL owner still spawns the custom illusion. A peer
    -- WITHOUT cosmetics_tweaker cold-decodes an appended index and fatals; nulling to the
    -- vanilla "n/a" index is the never-crash invariant and it must NOT be gated behind any
    -- mod:get() toggle. Drives the SHIPPED helper (_cos_wire_null_custom_skins) with a fake
    -- slot table so a future edit that gates the null (a default-off gate would leave the
    -- custom skin non-nil at send time) OR drops the restore fails here, not in a stranger's
    -- session. Mirrors cim's wire_rarity_rewrite_ungated.
    if type(mod._cos_wire_null_custom_skins) ~= "function" then
        return "skin-axis wire-null helper missing (issue 421 crash regression)"
    end
    if type(_custom_skin_keys) ~= "table" then
        return "_custom_skin_keys table missing"
    end
    local FAKE_CUSTOM  = "_rt_fake_custom_skin_key"
    local FAKE_VANILLA = "_rt_fake_vanilla_skin_key"
    local had = _custom_skin_keys[FAKE_CUSTOM]
    _custom_skin_keys[FAKE_CUSTOM] = true
    -- One slot wears the custom illusion (must be nulled on the wire); one wears a
    -- vanilla skin (must be left untouched).
    local custom_slot  = { skin = FAKE_CUSTOM }
    local vanilla_slot = { skin = FAKE_VANILLA }
    local slots = { slot_ranged = custom_slot, slot_melee = vanilla_slot }
    local skin_at_send, vanilla_at_send
    local ok, r1, r2 = pcall(mod._cos_wire_null_custom_skins, slots, function()
        -- Runs WHILE the RPC would encode/broadcast: the custom skin MUST be nil here
        -- (else a non-cos peer decodes the modded index and CTDs); the vanilla skin intact.
        skin_at_send    = custom_slot.skin
        vanilla_at_send = vanilla_slot.skin
        return "ret1", "ret2"
    end)
    -- Restore the shared table before asserting so a failure can't leak the fake key.
    if not had then _custom_skin_keys[FAKE_CUSTOM] = nil end
    if not ok then
        return "wire-null helper raised: " .. tostring(r1)
    end
    if skin_at_send ~= nil then
        return "custom skin was NOT nulled on the wire -- a non-cos peer would CTD (issue 421 regression; is the null toggle-gated?)"
    end
    if vanilla_at_send ~= FAKE_VANILLA then
        return "vanilla skin was wrongly mutated on the wire (only _custom_skin_keys entries may be nulled)"
    end
    if custom_slot.skin ~= FAKE_CUSTOM then
        return "custom skin not restored after the send -- LOCAL owner would lose the illusion"
    end
    if r1 ~= "ret1" or r2 ~= "ret2" then
        return "vanilla return values not threaded through the wire-null wrapper"
    end
end)

_rt_register("wire_skin_null_all_senders", function()
    -- issue 421: v0.9.74 nulled the skin axis on game_object_initialized ONLY; vanilla
    -- has two more rpc_add_equipment senders that encode weapon_skin_id from live slot
    -- data - SimpleInventoryExtension._spawn_resynced_loadout (the mid-session equip
    -- path, simple_inventory_extension.lua:1451) and GearUtils.hot_join_sync (the
    -- joining-peer replay, gear_utils.lua:484). Every registration flags itself in
    -- mod._cos_skin_wire_surfaces; a refactor that drops a sender fails here.
    local surfaces = mod._cos_skin_wire_surfaces
    if type(surfaces) ~= "table" then
        return "mod._cos_skin_wire_surfaces flag table missing (issue 421 senders unhooked?)"
    end
    for _, key in ipairs({
        "game_object_initialized", "spawn_resynced_loadout", "hot_join_sync",
        "update_cosmetic_slot",
    }) do
        if not surfaces[key] then
            return "skin-axis wire-null not registered on sender surface: " .. key
        end
    end
    -- Drive the shared helper with the resync sender's single-slot shape
    -- ({ equipment_to_spawn }) so that wrapper form stays covered too.
    if type(mod._cos_wire_null_custom_skins) ~= "function" then
        return "skin-axis wire-null helper missing"
    end
    if type(_custom_skin_keys) ~= "table" then
        return "_custom_skin_keys table missing"
    end
    local FAKE_CUSTOM = "_rt_fake_custom_skin_key_resync"
    local had = _custom_skin_keys[FAKE_CUSTOM]
    _custom_skin_keys[FAKE_CUSTOM] = true
    if type(mod._cos_wire_safe_custom_skin) ~= "function" then
        if not had then _custom_skin_keys[FAKE_CUSTOM] = nil end
        return "GameSession custom-skin wire policy missing"
    end
    local game_session_skin, game_session_subbed = mod._cos_wire_safe_custom_skin(
        FAKE_CUSTOM, "regression update_cosmetic_slot")
    if game_session_skin ~= "n/a" or not game_session_subbed then
        if not had then _custom_skin_keys[FAKE_CUSTOM] = nil end
        return "custom skin was not coerced to n/a for update_cosmetic_slot GameSession sync"
    end
    local equipment_to_spawn = { slot_id = "slot_melee", skin = FAKE_CUSTOM }
    local skin_at_send
    local ok, err = pcall(mod._cos_wire_null_custom_skins, { equipment_to_spawn }, function()
        skin_at_send = equipment_to_spawn.skin
    end, "regression")
    if not had then _custom_skin_keys[FAKE_CUSTOM] = nil end
    if not ok then
        return "wire-null helper raised on single-slot shape: " .. tostring(err)
    end
    if skin_at_send ~= nil then
        return "custom skin NOT nulled in the single-slot (resync) shape - mid-session equip would CTD non-mod peers"
    end
    if equipment_to_spawn.skin ~= FAKE_CUSTOM then
        return "custom skin not restored after the send in the single-slot (resync) shape"
    end
end)

_rt_register("offhand_preload_async_bounded_565", function()
    local contract = mod._cos_offhand_preload_contract
    if type(contract) ~= "table" or contract.mode ~= "async" then
        return "offhand bulk preload is not asynchronous (issue 565 startup stall regression)"
    end
    if contract.reference_name ~= "cosmetics_tweaker_offhand" then
        return "offhand package reference name changed; release balance cannot be proven"
    end
    if contract.readiness_gate ~= "Application.can_get:1p+3p" then
        return "1P+3P unit readiness gate contract missing"
    end
    if type(mod._release_offhand_packages) ~= "function" then
        return "offhand package unload/release path missing"
    end
    if contract.callback_guard ~= "generation_token" or contract.max_lifecycle_reports ~= 4 then
        return "late async callback guard is missing or unbounded"
    end
    local live = mod._cos_offhand_preload_lifecycle
    local pm = Managers and Managers.package
    if live and pm and pm.reference_count then
        for package_path in pairs(live.owned) do
            local count = pm:reference_count(package_path, contract.reference_name)
            if count ~= 1 then
                return string.format("offhand package %s has %s private references; expected exactly one",
                    tostring(package_path), tostring(count))
            end
        end
    end
    local probe = OFFHAND_PRELOAD_LIFECYCLE.new()
    local token = probe:begin("rt_shared_async_package")
    if not token or not probe:complete("rt_shared_async_package", token) then
        return "lifecycle ledger rejected an active callback"
    end
    local released = probe:release()
    if #released ~= 1 or released[1] ~= "rt_shared_async_package" then
        return "lifecycle release did not return the exact owned reference"
    end
    if probe:complete("rt_shared_async_package", token) ~= false
            or probe.stats.late_callbacks_ignored ~= 1 then
        return "callback after release was not rejected exactly once"
    end
end)

_rt_register("la_kruber_shield_catalogue_compatibility_204", function()
    if not LA_BRIDGE.registered then return nil end
    if type(LA_BRIDGE.kruber_shield_item_types) ~= "table"
            or #LA_BRIDGE.kruber_shield_item_types ~= 7 then
        return "Kruber LA shield catalogue is missing or has unexpected cardinality"
    end
    local item_family = {}
    for family, item_types in pairs(LA_BRIDGE.kruber_shield_families or {}) do
        for _, item_type in ipairs(item_types) do item_family[item_type] = family end
    end
    for _, item_type in ipairs(LA_BRIDGE.kruber_shield_item_types or {}) do
        local per_hand = LA_BRIDGE.la_offhand_options_by_weapon_type[item_type]
        local options = per_hand and per_hand.left_hand_unit
        if type(options) ~= "table" or #options == 0 then
            return "missing LA shield pool for Kruber item_type " .. tostring(item_type)
        end
        for _, option in ipairs(options) do
            if not option.armoury_key then
                return "LA shield option without armoury_key on " .. tostring(item_type)
            end
            if option.variant_kind ~= "unit"
                    and option.authored_family ~= item_family[item_type] then
                return string.format("LA texture family mismatch key=%s authored=%s receiver=%s",
                    tostring(option.armoury_key), tostring(option.authored_family), tostring(item_type))
            end
        end
    end
    local cwv_pool = _offhand_options.cwv_es_axe_shield
        and _offhand_options.cwv_es_axe_shield.left_hand_unit
    local vanilla = 0
    for _, option in ipairs(cwv_pool or {}) do
        if option.unit and not option.la_armoury_key then vanilla = vanilla + 1 end
    end
    if vanilla < #_SHIELD_POOLS_BY_ITEM_TYPE.es_1h_sword_shield then
        return "CWV Axe and Shield missing vanilla Empire shield options"
    end
end)

_rt_register("automatic_chat_diagnostics_log_only_570", function()
    if not GlowPicker.CHAT_DIAGNOSTICS_LOG_ONLY then
        return "glow-picker lifecycle diagnostics are not marked log-only"
    end
end)

_rt_register("mh_package_single_reference", function()
    -- issue 282: the MH embed's package loads must be exactly-once per path under
    -- the mod-owned reference name "cosmetics_tweaker_mh" (PackageManager.load
    -- INCREMENTS a per-(package, reference) count on every call,
    -- package_manager.lua:26-27; the pre-0.9.76 per-wield load(path, "global")
    -- accumulated 90+ refs per session and produced the shutdown "not unloaded,
    -- deadlock" crashify block). A count above 1 means the dedupe registry
    -- regressed to per-event accumulation.
    if not MH_EMBED or MH_EMBED.dormant then return nil end  -- embed dormant: vacuous pass
    local reg = MH_EMBED.loaded_packages
    if type(reg) ~= "table" then
        return "loaded_packages registry missing from MH embed exports (issue 282 regression)"
    end
    if type(MH_EMBED.release_packages) ~= "function" then
        return "release_packages missing from MH embed exports (issue 282 regression)"
    end
    if type(MH_EMBED.reconcile_packages) ~= "function"
        or type(MH_EMBED.pending_release_paths) ~= "function" then
        return "MH release completion ledger missing (issue 282 regression)"
    end
    local pending = MH_EMBED.pending_release_paths()
    if #pending > 0 then
        return string.format(
            "%d cosmetics_tweaker_mh package(s) remain in PackageManager delayed queue: %s",
            #pending, table.concat(pending, ","))
    end
    if not (Managers and Managers.package and Managers.package.reference_count) then
        return nil  -- package manager not up yet: vacuous pass
    end
    for path in pairs(reg) do
        local n = Managers.package:reference_count(path, "cosmetics_tweaker_mh") or 0
        if n > 1 then
            return string.format(
                "package %s holds %d refs under cosmetics_tweaker_mh (must be exactly 1 - issue 282 leak shape)",
                tostring(path), n)
        end
    end
end)

-- [mem-probe] cos boot Lua-footprint readout. MUST live at module top-level (runs
-- once when this file finishes loading), NOT inside the _rt_register closure above
-- — until v0.9.35-dev it was stranded as the last statement of that regression-test
-- closure (after two early returns), so it NEVER executed and "cos boot_lua" appeared
-- in zero console logs, leaving cosmetics' Lua footprint invisible next to
-- weapon_tweaker's measured +12.8 MB. Mirrors weapon_tweaker.lua's boot readout.
-- Measures the static table footprint (e.g. the ~11.9k-line _cosmetic_unlocks table)
-- at load time — the 74 offhand unit packages are queued later (lazily, in
-- mod.update) and Lua bookkeeping is snapshotted after that queueing pass.
mod:info("[mem-probe] cos boot_lua=+%.1f MB (of ~1024 MB lua_heap cap)", (collectgarbage("count") - mod._cos_mem_t0) / 1024)

end

return M
