--[[
_ct_altar_reuse_owner - Chaos Wastes reusable-altar economy (#1159 / #2 file-size refactor).

RESPONSIBILITY
Owns every ct behaviour that depends on a Chaos Wastes ALTAR having been opened
before. An "altar" here is the engine class DeusChestExtension - the boon shrine
(power_up), the two weapon-swap shrines, and the weapon-upgrade shrine - NOT a
Chest of Trials (DeusCursedChestExtension, which has no purchase step at all);
the terminology banner moved into this file with the code it governs.

Vanilla altars are single-use. Issue #61 makes max uses configurable per altar
type, and everything that follows from that one decision lives here:
  * the per-altar use ledger (`_altar_uses_by_go_id`) and the two settings
    policies read off it - max uses and the geometric cost multiplier
  * the price curve: get_purchase_cost scaled by mult^uses_so_far
  * the re-roll seed mixing on all three generators, so a re-armed altar offers
    something different instead of re-rolling the identical deterministic roll
  * the two #102 relaxed gates that keep a re-armed UPGRADE altar lit and
    interactable at the same rarity tier (`<=` loosened to `<`), and the #252
    DeusUpgradeWeaponInteractionUI repaint that stops the panel contradicting
    them with the red "cannot upgrade" text
  * `collected_by_peers` retraction (v0.7.151) including its client->host
    ct_altar_uncollect RPC, without which vanilla update() re-derives "looted"
    one tick after every re-arm
  * the boon-altar no-repeat ledger's load-time initialisation
  * the read-only v0.7.157 altar_visual_probe watcher and its collected_by_peers
    formatter

Extracted VERBATIM from chaos_wastes_tweaker_dev.lua entry lines 1047-1659 with
no behaviour change. The moved lines are byte-identical to the pre-extraction
entry region (MD5-proven, zero deviations inside the moved block); the only
additions are this header, the ctx binding block below, and the export table at
the end. mod:dofile is not a singleton - the entry calls this installer EXACTLY
once, at the exact point the block used to execute (after the bot-economy
DeusRunController hooks, before the multiplayer settings-sync block), so
hook-registration order and the load-time assignment of `_ct_altar_probe_watch`,
`_ct_probe_collected_by_peers`, the two CT_RELIQUARY_REROLL_* globals, the four
mod._ct_* altar helpers, and `mod._ct_boon_altar_taken_boons` all keep their
original timing.

HOOKS OWNED (each hooked EXACTLY ONCE in the whole mod - VMF silently drops a
second registration on the same (Class, method) pair, which is how the
v0.7.129/.130 altar-reuse "fix" shipped dead for two releases):
  DeusChestExtension.update                     (read-only probe watcher)
  DeusChestExtension.get_purchase_cost
  DeusChestExtension._generate_stored_power_up
  DeusChestExtension._generate_stored_weapon
  DeusChestExtension._generate_upgraded_weapon
  DeusChestExtension.update_upgrade_chest_color
  DeusChestExtension.can_be_unlocked
  DeusUpgradeWeaponInteractionUI._populate_widget   [hook_safe]
RPC OWNED
  ct_altar_uncollect  (server handler; schema-gated on ctx.rpc_schema)
Grep-verified against every other ct_dev lua 2026-08-10; the mod-wide census is
unchanged by the move (97 hook / 29 hook_safe / 7 network_register / 44 command
sites, 109 distinct pairs, no duplicates).

COMPOSES WITH, DOES NOT OVERLAP, THE OTHER ct OWNERS
  * _ct_bot_weapon_chest_owner owns the ONE consolidated
    (DeusChestExtension, open_chest) hook - the single WRITE seam. It is the
    only place the use count is incremented and the only place the re-arm is
    performed. This file owns every READER of that count. The split is exactly
    write-site vs read-sites, which is why the ledger has to cross: the entry
    hands that owner `altar_uses` (accessor), `altar_max_uses`, plus the two
    probe globals this file defines. `mod._ct_altar_uncollect`, defined here, is
    called from that owner's re-arm branch as a mod field, so it needs no ctx
    plumbing.
  * _ct_cot_cost / _ct_cot_cost_policy own the Chest of TRIALS wave cost. A
    Chest of Trials is a different engine class with no purchase step; nothing
    in this file may grow a coin cost for it (see the terminology banner).
  * _ct_boon_registry / _ct_boon_grant_owner decide WHICH boons an altar may
    offer and what happens when one is granted. This file only records that a
    boon altar was used and re-seeds the next roll; the no-repeat FILTER that
    consumes `mod._ct_boon_altar_taken_boons` stays in the entry's
    DeusPowerUpsArray strip.
  * _ct_umbrella_policy is called (not owned) by the two settings readers here.

CROSS-FILE CONTRACT
Entry file-locals this block closed over, and how each crosses:
  ctx.dbg               entry :99   `local function`, defined once ABOVE the
                                    install site - crosses by value
  ctx.dbg_alert         entry :103  same
  ctx.rpc_schema        entry :77   constant number - crosses by value
  ctx.effective_setting entry :785  FORWARD SLOT, body assigned at entry :2631,
                                    which is AFTER this install site. It must
                                    cross as a late-binding wrapper closure
                                    (`function(name) return effective_setting(name) end`
                                    evaluated in the entry), never by value - a
                                    by-value bind would capture nil and every
                                    altar-reuse setting would read as nil at
                                    runtime. Same treatment the entry already
                                    gives _ct_boss_grudge_marks.
The asserts below turn a dropped or by-value ctx key into a load-time failure
instead of a silent nil read the first time a player walks up to an altar.

EXPORTS (consumed by the entry, which forwards two of them to
_ct_bot_weapon_chest_owner)
  altar_uses()      accessor returning the LIVE ledger table. An accessor, not
                    the table, because reset_uses REBINDS - handing out the
                    table would leave every consumer holding last run's copy.
  altar_max_uses    the max-uses policy function itself (stateless).
  reset_uses()      run-start wipe; the entry calls it from its
                    DeusRunController.setup_run hook where the inline
                    `_altar_uses_by_go_id = {}` used to sit.

Owned by: chaos_wastes_tweaker_dev.lua entry point.
Guarded by: qa/lua/tests/test_ct_altar_reuse_owner.lua,
qa/lua/tests/test_ct_entry_decomposition.lua, the #252 reroll-prompt rows in
qa/rt_textual_invariants.psd1, and the ENGINE_SURFACE.md DeusChestExtension row.
]]

local function install(mod, ctx)

assert(type(ctx) == "table", "_ct_altar_reuse_owner requires a context table")
assert(type(ctx.dbg) == "function", "_ct_altar_reuse_owner requires ctx.dbg")
assert(type(ctx.dbg_alert) == "function", "_ct_altar_reuse_owner requires ctx.dbg_alert")
assert(type(ctx.effective_setting) == "function",
    "_ct_altar_reuse_owner requires ctx.effective_setting (late-binding wrapper, not the forward slot by value)")
assert(type(ctx.rpc_schema) == "number", "_ct_altar_reuse_owner requires ctx.rpc_schema")

local _dbg              = ctx.dbg
local _dbg_alert        = ctx.dbg_alert
local effective_setting = ctx.effective_setting
local CT_RPC_SCHEMA     = ctx.rpc_schema

-- ============================================================
-- Altar reuse (v0.7.127-dev) — Issue #61: configurable max uses per altar type
-- ============================================================
-- Vanilla DeusChestExtension is single-use: `purchase()` (deus_chest_extension.lua:301)
-- sets `_is_purchased = true` and fires the `lua_update_collected` flow event;
-- the altar's "looted" animation plays and `can_be_unlocked()` (line 487) returns
-- false on subsequent attempts.
--
-- This feature lets the host configure max uses per altar type (boon shrine,
-- melee swap, ranged swap, weapon upgrade — matching the 4 DEUS_CHEST_TYPES the
-- vanilla extension already differentiates internally) with a geometric cost
-- multiplier applied per reuse.
--
-- Mechanism (3 narrow hooks):
--   1. get_purchase_cost — wrap vanilla, scale by mult^uses_so_far.
--   2. purchase — post-call, if uses < max:
--        - restore _is_purchased=false + _animation_state=nil
--        - zero _profile_index/_career_index so vanilla update() (line 134)
--          re-runs the full setup block on the next tick (re-rolls offerings,
--          fires the lua_update_<rarity> flow event so the altar visually
--          re-arms)
--   3. _generate_stored_power_up / _generate_stored_weapon — mix the use count
--      into the seed input so each re-roll produces different offerings.
--
-- All thresholds read via effective_setting so the host's values apply to
-- clients via the standard VMF broadcast. The per-unit `_altar_uses_by_go_id`
-- table is server-state (only the server's purchase() hook writes to it).
--
-- VISUAL-SYNC CAVEAT (corrected v0.7.151-dev): the vanilla chest network sync is
-- ONE-DIRECTIONAL toward "looted" only. The first open inserts the opener's peer
-- into the networked GameSession field `collected_by_peers` (server handler
-- rpc_deus_chest_looted, deus_chest_extension.lua:737-752) and NOTHING ever
-- removes it. So zeroing only the LOCAL re-arm fields is not enough: vanilla
-- update() (deus_chest_extension.lua:175) re-derives `new_is_purchased` from
-- `table.contains(collected_by_peers, peer_id)`, re-asserts _animation_state=
-- "looted" (line 177-182), and line 194 then skips _update_chest_animation_and_
-- sound_state — so the re-rolled offering hologram never re-displays. The re-arm
-- block therefore ALSO retracts the own peer from collected_by_peers (server
-- writes it directly; a client opener round-trips through the ct_altar_uncollect
-- RPC so the server clears the authoritative field). See _ct_remove_peer_from_
-- collected / mod._ct_altar_uncollect below.
--
-- UPGRADE-ALTAR ROOT CAUSE (v0.7.158-dev — the ACTUAL fix for "goes dark after
-- first use", solo host, no peers):
-- The v0.7.151 collected_by_peers uncollect was a real bug but NOT the cause of
-- the upgrade altar darkening. For an UPGRADE altar the looted look is derived
-- TWO independent ways:
--   (1) collected_by_peers membership (deus_chest_extension.lua:175) — uncollect
--       handles this, and solo-host it's a direct local write that DOES hold.
--   (2) update_upgrade_chest_color (deus_chest_extension.lua:211-243) — runs
--       EVERY tick, independent of collected_by_peers. It compares the altar's
--       rolled `_rarity` against the player's CURRENTLY WIELDED weapon rarity:
--           event = chest_rarity_order <= weapon_rarity_order
--               and "lua_interact_disabled" or LUA_UPDATE_RARITY_EVENTS[rarity]
--       After the first upgrade, the wielded weapon's rarity == the altar's
--       rolled rarity, so chest_rarity_order <= weapon_rarity_order is TRUE and
--       the altar fires `lua_interact_disabled` — the grey/"dark", can't-use
--       visual. can_be_unlocked (lines 505-517) likewise returns false, so the
--       re-armed altar is GENUINELY unusable, not just cosmetically dark.
-- The altar re-rolls `_rarity` each re-arm (update() line 140 -> _setup_rarity),
-- but the seed is constant per go_id, so it always re-rolls the SAME rarity, and
-- update_upgrade_chest_color always re-disables it. Therefore the upgrade-altar
-- re-arm must ALSO bump `_rarity` strictly above the just-upgraded weapon (capped
-- at `unique`, order 5) and clear the cached `_prev_update_upgrade_chest_color_
-- event` so the disabled-color event re-evaluates. See the upgrade branch in the
-- consolidated open_chest hook (_ct_consolidated_open_chest_hook).
local DEUS_CHEST_TYPE_TO_KEY = {
    power_up    = "power_up",
    swap_melee  = "swap_melee",
    swap_ranged = "swap_ranged",
    upgrade     = "upgrade",
}
local _altar_uses_by_go_id = {}

local function _altar_key_for(chest_type)
    if type(chest_type) ~= "string" then return nil end
    return DEUS_CHEST_TYPE_TO_KEY[chest_type]
end

local function _altar_max_uses(chest_type)
    local key = _altar_key_for(chest_type)
    if not key then return 1 end
    local v = mod._ct_umbrella_policy.value(
        effective_setting("enable_altar_reuse"),
        effective_setting("altar_reuse_count_" .. key), 1)
    if type(v) ~= "number" or v < 1 then return 1 end
    return math.floor(v)
end

local function _altar_cost_mult(chest_type)
    local key = _altar_key_for(chest_type)
    if not key then return 1 end
    local v = mod._ct_umbrella_policy.value(
        effective_setting("enable_altar_reuse"),
        effective_setting("altar_reuse_cost_mult_" .. key), 1)
    if type(v) ~= "number" or v <= 0 then return 1 end
    return v
end

-- v0.7.158-dev: ordered list of the player-usable weapon rarities (order 1..5,
-- excluding `event`/order 6 which is not granted to player weapons), and the
-- helper that returns the rarity NAME one tier above a wielded weapon (capped at
-- `unique`/order 5). Used by the upgrade-altar re-arm to bump the altar's offered
-- rarity strictly above the player's just-upgraded weapon so update_upgrade_chest_
-- color (deus_chest_extension.lua:236) stops firing `lua_interact_disabled` (the
-- dark/can't-use visual) and can_be_unlocked (lines 505-517) keeps returning true
-- until the usable rarity ceiling is reached.
--
-- Attached to `mod` (not file-scope locals) to stay under Lua 5.1's
-- 200-locals-per-chunk cap — this file is at the limit (see the same pattern on
-- mod._ct_remove_peer_from_collected / mod._ct_boon_altar_taken_boons).
mod._ct_rarity_by_order = mod._ct_rarity_by_order
    or { "plentiful", "common", "rare", "exotic", "unique" }

-- Return the rarity NAME one tier above `weapon_rarity_name`, capped at `unique`
-- (order 5). Returns nil if RaritySettings isn't loaded or the input is unknown,
-- in which case the caller leaves the vanilla-rolled rarity untouched.
-- NOTE (v0.7.211-dev): no longer called after the #102 rarity-decouple; the reward-rarity
-- bump it powered was removed. Retained only as a generic tier-step helper.
mod._ct_altar_next_rarity_above = function(weapon_rarity_name)
    local rs = rawget(_G, "RaritySettings")
    if type(weapon_rarity_name) ~= "string" or not rs then return nil end
    local cur = rs[weapon_rarity_name]
    local cur_order = cur and cur.order
    if type(cur_order) ~= "number" then return nil end
    -- one above the wielded weapon, but never above the usable ceiling (5 = unique).
    local target_order = math.min(5, cur_order + 1)
    return mod._ct_rarity_by_order[target_order]
end

-- v0.7.151-dev: retract ONE peer from a chest's networked `collected_by_peers`
-- GameSession field so the re-armed altar stops reading as looted. Without this,
-- vanilla DeusChestExtension.update (deus_chest_extension.lua:175) re-derives
-- new_is_purchased=true from the still-present peer one tick after re-arm, forces
-- _animation_state="looted" (line 177-182), and line 194 skips the anim update —
-- the re-rolled offering hologram never re-displays.
--
-- Server-owned field (written server-side at deus_chest_extension.lua:752), so a
-- client opener must round-trip through the server (see mod._ct_altar_uncollect).
-- Removes ONLY `peer_id` — never clears the whole array — because in co-op other
-- peers may legitimately have looted other (non-reusable) chests sharing nothing
-- but this is per-GameSession-object, so scoping to the own peer keeps their
-- state intact. Attached to `mod` (not a file-scope local) to stay under Lua
-- 5.1's 200-locals-per-chunk cap.
--
-- GUARD: GameSession.game_object_exists before reading (vanilla guard, e.g.
-- player_husk_locomotion_extension.lua:134), AND wrap the read/write in pcall —
-- `game_object_field` on a truly stale go_id is an engine fatal that bypasses
-- pcall the same way Unit.node does, so the existence check is the real gate; the
-- pcall just catches the ordinary Lua errors (nil game, bad field).
mod._ct_remove_peer_from_collected = function(go_id, peer_id)
    if not go_id or peer_id == nil then return end
    local network_man = Managers.state and Managers.state.network
    local game = network_man and network_man.game and network_man:game()
    if not game then return end
    if not GameSession.game_object_exists(game, go_id) then return end
    pcall(function()
        local collected = GameSession.game_object_field(game, go_id, "collected_by_peers")
        if type(collected) ~= "table" then return end
        local changed = false
        for i = #collected, 1, -1 do
            if collected[i] == peer_id then
                table.remove(collected, i)
                changed = true
            end
        end
        if changed then
            GameSession.set_game_object_field(game, go_id, "collected_by_peers", collected)
            _dbg("[altar_reuse] uncollect go_id=%s peer=%s -> %d peer(s) remain",
                tostring(go_id), tostring(peer_id), #collected)
        end
    end)
end

-- v0.7.151-dev: on altar re-arm, retract the OWN peer from collected_by_peers.
-- The re-arm runs on the buying/interacting peer (host OR client). The field is
-- server-authoritative, so:
--   * host opener writes it directly;
--   * client opener sends ct_altar_uncollect to the HOST so the server mutates
--     the authoritative copy (mirrors vanilla loot, which is server-authoritative
--     via purchase() -> send_rpc_server at deus_chest_extension.lua:315).
-- This is a pure data write to one GameSession field — it does NOT re-enter
-- purchase() or spawn anything; the next vanilla update() tick simply takes the
-- non-looted branch and re-fires the offering presentation.
mod._ct_altar_uncollect = function(ext)
    if not ext then return end
    local go_id = ext._go_id or (Managers.state and Managers.state.unit_storage
        and ext.unit and Managers.state.unit_storage:go_id(ext.unit))
    if not go_id then return end
    local drc = ext._deus_run_controller
    local own_peer_id = drc and drc.get_own_peer_id and drc:get_own_peer_id()
    if not own_peer_id then return end

    if ext._is_server then
        -- Host opener: write the server-owned field directly.
        mod._ct_remove_peer_from_collected(go_id, own_peer_id)
        return
    end

    -- Client opener: ask the host to clear our peer. VMF's network_send does NOT
    -- accept "server" as a recipient (silently dropped — VMF_RECIPES.md § 3); the
    -- real host peer_id must be resolved. The server handler resolves the SENDER
    -- (us) from the VMF sender_peer_id arg, so we only send go_id.
    local host
    if Managers.mechanism and Managers.mechanism.server_peer_id then
        host = Managers.mechanism:server_peer_id()
    end
    if not host then
        local nm = Managers.state and Managers.state.network
        host = nm and ((nm.network_client and nm.network_client.server_peer_id)
            or (nm.network_server and nm.network_server.server_peer_id))
    end
    if not host then
        _dbg("[altar_reuse] uncollect: host peer_id not yet known; skipping client RPC (go_id=%s)",
            tostring(go_id))
        return
    end
    mod:network_send("ct_altar_uncollect", host, CT_RPC_SCHEMA, go_id)
end

-- Server handler: a client re-armed this altar locally and asks us to drop its
-- peer from the chest's collected_by_peers, so everyone (including that client)
-- sees the re-rolled offering instead of the looted state. Mirrors vanilla
-- rpc_deus_chest_looted (deus_chest_extension.lua:737-752) in reverse. The
-- sending peer is resolved by VMF (sender_peer_id), NOT a raw CHANNEL_TO_PEER_ID.
mod:network_register("ct_altar_uncollect", function(sender_peer_id, schema_version, go_id)
    -- Issue #27: schema-version gate. See CT_RPC_SCHEMA block near MOD_VERSION
    -- and VMF_RECIPES.md § 10. Mismatch = drop + _dbg_alert; no state mutation.
    if schema_version ~= CT_RPC_SCHEMA then
        _dbg_alert("[rpc:schema] %s mismatch from peer=%s: peer sent v%s, we expect v%d. Dropping.",
            "ct_altar_uncollect", tostring(sender_peer_id), tostring(schema_version), CT_RPC_SCHEMA)
        return
    end
    -- Only the host owns the field; ignore if we somehow aren't the server.
    local is_server = Managers and Managers.player and Managers.player.is_server
    if not is_server then return end
    if sender_peer_id == nil or go_id == nil then return end
    mod._ct_remove_peer_from_collected(go_id, sender_peer_id)
end)

-- ============================================================
-- v0.7.157-dev Task A: ALTAR "goes dark after first use" PROBES (DIAGNOSE-ONLY)
-- ============================================================
-- The user reports weapon-UPGRADE altars set to allow >1 use still go "dark"
-- (looted look) after the FIRST use, despite the v0.7.151 re-arm + uncollect.
-- These probes are READ-ONLY: they capture the visual-state evolution across the
-- re-arm AND the next few vanilla DeusChestExtension.update ticks so the log
-- shows exactly when/why it re-darkens. NO behavior change. All lines are FORCED
-- output (unconditional mod:info, tag [altar_visual_probe]) so the user just
-- plays — no command needed. Strip the whole block once the cause is found.
--
-- _ct_altar_probe_watch[go_id] = { ticks = N, type = "<chest_type>" } — armed by
-- the open_chest re-arm path; the read-only update hook below decrements it and
-- logs each tick's derived state.
_ct_altar_probe_watch = {}

-- Read collected_by_peers for a go_id as a printable string, guarded exactly like
-- mod._ct_remove_peer_from_collected (game_object_exists gate + pcall). Returns a
-- "[p1,p2]" style string, or a status token if unreadable. Read-only.
function _ct_probe_collected_by_peers(go_id)
    if not go_id then return "<no go_id>" end
    local network_man = Managers.state and Managers.state.network
    local game = network_man and network_man.game and network_man:game()
    if not game then return "<no game>" end
    if not GameSession.game_object_exists(game, go_id) then return "<go absent>" end
    local out = "<unreadable>"
    pcall(function()
        local collected = GameSession.game_object_field(game, go_id, "collected_by_peers")
        if type(collected) ~= "table" then out = "<not table>"; return end
        local parts = {}
        for i = 1, #collected do parts[i] = tostring(collected[i]) end
        out = "[" .. table.concat(parts, ",") .. "](" .. #collected .. ")"
    end)
    return out
end

-- Read-only watcher hook on DeusChestExtension.update. ct_dev has NO other hook
-- on DeusChestExtension.update (verified: only open_chest/get_purchase_cost/
-- _generate_* /extensions_ready are hooked), so this fresh mod:hook is VMF-clean.
-- Logs the post-re-arm visual-state evolution for a watched (re-armed) chest:
-- _is_purchased / _animation_state / _profile_index plus what vanilla would
-- re-derive (new_is_purchased from collected_by_peers). DOES NOT mutate anything;
-- always calls through to vanilla and returns its result(s).
mod:hook("DeusChestExtension", "update", function(func, self, unit, input, dt, context, t)
    local go_id = self._go_id or (self.unit and Managers.state and Managers.state.unit_storage
        and Managers.state.unit_storage:go_id(self.unit))
    local watch = go_id and _ct_altar_probe_watch[go_id]

    -- pre-tick snapshot (state as vanilla update SEES it on entry)
    local pre_purchased, pre_anim, pre_profile
    if watch then
        pre_purchased = self._is_purchased
        pre_anim = self._animation_state
        pre_profile = self._profile_index
    end

    local r1, r2, r3 = func(self, unit, input, dt, context, t)

    if watch then
        local own_peer = self._deus_run_controller and self._deus_run_controller.get_own_peer_id
            and self._deus_run_controller:get_own_peer_id()
        local collected = _ct_probe_collected_by_peers(go_id)
        -- mirror vanilla's new_is_purchased derivation (deus_chest_extension.lua:175):
        -- not self._stored_purchase and chest_type ~= upgrade  OR  own peer in collected
        local DCT = rawget(_G, "DEUS_CHEST_TYPES")
        local own_in_collected = "?"
        do
            local cp = nil
            local network_man = Managers.state and Managers.state.network
            local game = network_man and network_man.game and network_man:game()
            if game and GameSession.game_object_exists(game, go_id) then
                pcall(function() cp = GameSession.game_object_field(game, go_id, "collected_by_peers") end)
            end
            if type(cp) == "table" and own_peer ~= nil then
                own_in_collected = tostring(table.contains(cp, own_peer))
            end
        end
        _dbg("[altar_visual_probe] UPDATE go_id=%s type=%s tick=%d pre{purchased=%s anim=%s prof=%s} post{purchased=%s anim=%s prof=%s} stored_purchase=%s is_upgrade=%s own_in_collected=%s collected=%s",
            tostring(go_id), tostring(watch.type), watch.ticks,
            tostring(pre_purchased), tostring(pre_anim), tostring(pre_profile),
            tostring(self._is_purchased), tostring(self._animation_state), tostring(self._profile_index),
            tostring(self._stored_purchase ~= nil),
            tostring(DCT and self._chest_type == DCT.upgrade), own_in_collected, collected)
        watch.ticks = watch.ticks - 1
        if watch.ticks <= 0 then
            _ct_altar_probe_watch[go_id] = nil
            _dbg("[altar_visual_probe] UPDATE go_id=%s watch window closed", tostring(go_id))
        end
    end

    return r1, r2, r3
end)

-- ============================================================
-- TERMINOLOGY (Chaos Wastes) -- READ BEFORE EDITING COST/CHEST CODE
-- ============================================================
-- IN-GAME, the ONLY thing called a "chest" is a CHEST OF TRIALS: a cursed
-- chest that spawns a trial enemy wave (you pay by fighting the wave, never
-- with coin). It is the engine class DeusCursedChestExtension
-- (scripts/unit_extensions/deus/deus_cursed_chest_extension.lua) -- it has NO
-- _chest_type and NO get_purchase_cost. ct's cot_enemy_multiplier targets it
-- via the terror-event spawn tag spawn_counter_category == "cursed_chest_enemies".
--
-- The boon shrine (Shrine of Solace), weapon-swap shrine, and weapon-upgrade
-- shrine are ALTARS. The ENGINE confusingly calls them all "chest":
-- DeusChestExtension with _chest_type = power_up (boon ALTAR) / swap_melee /
-- swap_ranged / upgrade. get_purchase_cost lives on THIS class; for power_up it
-- returns the stock 150 boon price (deus_chest_extension.lua:294-295).
--
-- => Any code below that branches on _chest_type == power_up is acting on a
--    BOON ALTAR, never on a Chest of Trials. The altar-reuse cost multiplier
--    (150 * mult^uses) is the intended boon-altar price. Do NOT re-introduce a
--    "trials" coin cost on this hook -- a real Chest of Trials has no purchase
--    step to override (it is DeusCursedChestExtension; you pay by fighting).
-- ============================================================

-- ============================================================
-- Boon-altar no-repeat bookkeeping
-- ============================================================
-- Records which boons the local peer has already taken from boon (power_up)
-- ALTARS this run, so the no-repeat default (in the DeusPowerUpsArray strip
-- below) can exclude already-taken boons from each subsequent altar roll. This
-- is boon-ALTAR state, NOT a Chest of Trials -- see the terminology banner
-- above. State lives on `mod` (not file-scope locals) to stay under Lua 5.1's
-- 200-locals-per-chunk cap.
mod._ct_boon_altar_taken_boons = mod._ct_boon_altar_taken_boons or {}

mod:hook("DeusChestExtension", "get_purchase_cost", function(func, self)
    local base = func(self)
    if type(base) ~= "number" or base == math.huge then return base end
    local go_id = self._go_id
    local uses = (go_id and _altar_uses_by_go_id[go_id]) or 0
    if uses == 0 then return base end
    local mult = _altar_cost_mult(self._chest_type)
    if mult == 1 then return base end
    return math.max(1, math.ceil(base * (mult ^ uses)))
end)

-- v0.7.131-dev: altar-reuse re-arm logic LIVES INSIDE the consolidated
-- consolidated `mod:hook("DeusChestExtension", "open_chest", ...)` further down the
-- file (search for `_ct_consolidated_open_chest_hook`). DO NOT add a second
-- `mod:hook("DeusChestExtension", "open_chest", ...)` here — VMF silently
-- drops duplicate hooks on the same (Class, method) per mod (see VMF_RECIPES.md
-- § 1 and feedback_vmf_no_duplicate_hooks). The v0.7.129/.130 altar-reuse
-- "fix" sat in a duplicate hook for two releases and never actually ran.
-- Helper functions remain here; the open_chest hook itself is consolidated.

-- Seed-mix hooks so each re-roll yields DIFFERENT offerings. Vanilla seeds
-- derive from (go_id, current_node.weapon_pickup_seed) — same each tick.
-- Mixing the use count into the seed produces a fresh roll without touching
-- the run-shared current_node state.
mod:hook("DeusChestExtension", "_generate_stored_power_up", function(func, self, seed)
    local go_id = self._go_id
    local uses = (go_id and _altar_uses_by_go_id[go_id]) or 0
    if uses == 0 or type(seed) ~= "number" then return func(self, seed) end
    if HashUtils and HashUtils.fnv32_hash then
        seed = HashUtils.fnv32_hash(tostring(seed) .. "_ct_reuse_" .. uses)
    else
        seed = seed + uses * 16777619  -- fallback FNV prime mix
    end
    return func(self, seed)
end)

mod:hook("DeusChestExtension", "_generate_stored_weapon", function(func, self, slots, rarity, go_id, profile_index, career_index)
    -- Weapon generation derives weapon_seed inside the function from
    -- (profile, career, current_node.weapon_pickup_seed, go_id, 1) via fnv32_hash
    -- (deus_chest_extension.lua:411). Offsetting the go_id parameter by the use
    -- count flows through the hash and produces a fresh weapon_seed -> fresh roll
    -- without copy-pasting the whole function.
    local uses = (go_id and _altar_uses_by_go_id[go_id]) or 0
    if uses == 0 then return func(self, slots, rarity, go_id, profile_index, career_index) end
    local mixed_go_id = (go_id or 0) + uses * 1000003
    return func(self, slots, rarity, mixed_go_id, profile_index, career_index)
end)

-- v0.7.158-dev Task 2: WEAPON-UPGRADE altar reroll on reuse. The upgrade altar
-- does NOT swap the weapon — it upgrades the wielded weapon in place via
-- _generate_upgraded_weapon (deus_chest_extension.lua:426), which is a DISTINCT
-- function from _generate_stored_weapon (the swap-altar path the seed-mix hook
-- above targets). So without this, every upgrade reuse produced the SAME
-- properties/trait roll. The function derives its weapon_seed inside from
-- (profile, career, current_node.weapon_pickup_seed, go_id, 1) via fnv32_hash
-- (line 431) — the SAME constant per go_id every reuse. Offsetting the go_id
-- argument by the use count flows through that hash and yields a fresh
-- properties/trait roll on the upgraded weapon, mirroring the _generate_stored_
-- weapon idiom above. Single hook on this (Class, method) — VMF-clean.
mod:hook("DeusChestExtension", "_generate_upgraded_weapon", function(func, self, weapon, slot_name, rarity, go_id, profile_index, career_index)
    local uses = (go_id and _altar_uses_by_go_id[go_id]) or 0
    -- uses==0 -> go_id unchanged; re-armed -> the v0.7.158 seed-mix. eff_go_id unifies both
    -- branches so behavior is identical to the prior two-branch form.
    local eff_go_id = (uses == 0) and go_id or ((go_id or 0) + uses * 1000003)
    local pre_key = type(weapon) == "table" and weapon.deus_item_key or nil
    local a, b = func(self, weapon, slot_name, rarity, eff_go_id, profile_index, career_index)
    -- #105 [ct:xchar105]: vanilla upgrade_item PRESERVES deus_item_key
    -- (deus_weapon_generation.lua:252-254,185-194), so pre==post is EXPECTED; a mismatch
    -- would prove a key swap. self._stored_purchase is the new weapon
    -- (deus_chest_extension.lua:441). If pre==post but the elf longbow still reverts on
    -- Kruber, the drop is render-side (wt create_equipment re-apply), not ct.
    pcall(function()
        local post = self._stored_purchase
        local post_key = type(post) == "table" and post.deus_item_key or nil
        local prof = rawget(_G, "SPProfiles")
        prof = prof and profile_index and prof[profile_index]
        local career = prof and prof.careers and career_index and prof.careers[career_index]
        pcall(printf, "[ct:xchar105] upgrade-altar slot=%s career=%s rarity=%s pre_key=%s post_key=%s %s",
            tostring(slot_name), tostring(career and career.name), tostring(rarity),
            tostring(pre_key), tostring(post_key),
            (pre_key ~= post_key) and "*** KEY CHANGED ***" or "(key preserved)")
    end)
    return a, b
end)

-- #102 (rarity escalation) FIXED v0.7.211-dev: DECOUPLE keep-lit visual from reward rarity.
-- ----------------------------------------------------------------------------------------------
-- Root cause: self._rarity is BOTH the reward tier (open_chest -> _generate_upgraded_weapon(...,
-- self._rarity), deus_chest_extension.lua:558) AND the input to the dark-gate (update_upgrade_
-- chest_color :236 / can_be_unlocked :513, both `chest_rarity_order <= weapon_rarity_order`). The
-- old v0.7.158 fix kept a re-armed altar LIT by bumping self._rarity strictly ABOVE the wielded
-- weapon every re-roll; that leaked into the reward, climbing plentiful->rare->exotic->unique.
--
-- FIX (Option B, user-chosen 2026-07-02): stop bumping self._rarity entirely (it stays at the
-- constant per-go_id rolled tier, so the reward never climbs), and relax the two dark-gates from
-- `<=` to strict `<` for a RE-ARMED upgrade altar (uses > 0). A same-tier re-roll stays LIT and
-- usable (a rare altar re-rolls a rare weapon at rare, with fresh props via the _generate_upgraded_
-- weapon seed-mix hook above) while a genuine DOWNGRADE still greys out. Same-tier upgrade cost is
-- populated + finite (DeusCostSettings.deus_chest.upgrade[r][r] = base[r]*0.5, e.g. rare=100,
-- deus_cost_settings.lua:137-173), so get_purchase_cost / can_be_unlocked's cost branch pass.
-- Depletion is unaffected: a spent altar keeps _is_purchased=true, which both hooks below (and
-- vanilla can_interact) already treat as unusable.
--
-- Both methods are otherwise unhooked in ct_dev (verified). Both hooks pass through to vanilla for
-- first-use (uses==0) and every non-upgrade chest, so the ONLY behavior change is that a re-armed
-- upgrade altar allows a same-tier re-roll instead of greying out. /ct_regression_test guards this
-- via `upgrade_altar_rarity_decouple`. #103 (looted mesh on non-final use) is a SEPARATE visual
-- path (the open_chest re-arm below) and is unaffected by this decouple.

-- Relaxed VISUAL gate. Reimplements vanilla update_upgrade_chest_color (deus_chest_extension.lua:
-- 211-243) with the rarity test loosened `<=` -> `<`. The rarity flow event is `"lua_update_" ..
-- rarity` (vanilla's file-local LUA_UPDATE_RARITY_EVENTS[rarity], built the same way at :52; it is
-- NOT a global, so it cannot be read via _G). Single hook on this (Class, method).
mod:hook("DeusChestExtension", "update_upgrade_chest_color", function(func, self)
    local DCT = rawget(_G, "DEUS_CHEST_TYPES")
    local go_id = self._go_id
    local uses = (go_id and _altar_uses_by_go_id[go_id]) or 0
    if uses == 0 or not (DCT and self._chest_type == DCT.upgrade) then
        return func(self)  -- first use / non-upgrade: pure vanilla
    end
    local rarity = self._rarity
    if not rarity then return end
    if self._is_purchased then return end          -- depleted/looted: leave vanilla dark state
    local wielded = self._get_wielded_weapon and self:_get_wielded_weapon()
    if not wielded then return end
    local rs = rawget(_G, "RaritySettings")
    local wr = rs and rs[wielded.rarity]
    local cr = rs and rs[rarity]
    if not (wr and cr) then return func(self) end
    -- RELAXED: `<` not `<=`, so same-tier stays lit; only a downgrade greys out.
    local event = (cr.order < wr.order) and "lua_interact_disabled" or ("lua_update_" .. rarity)
    if not self._prev_update_upgrade_chest_color_event or self._prev_update_upgrade_chest_color_event ~= event then
        if self.unit and Unit and Unit.flow_event
            and (not Unit.alive or Unit.alive(self.unit)) then
            pcall(Unit.flow_event, self.unit, event)
        end
        self._prev_update_upgrade_chest_color_event = event
    end
end)

-- Relaxed INTERACTION gate. Without it the altar would look lit but reject the interact. Reimplements
-- vanilla can_be_unlocked (deus_chest_extension.lua:487-537) with the SAME `<=` -> `<` loosening,
-- gated to a re-armed upgrade altar; every other vanilla gate (can_interact, cost affordability,
-- others_actually_ingame) is preserved exactly. Single hook on this (Class, method).
mod:hook("DeusChestExtension", "can_be_unlocked", function(func, self)
    local DCT = rawget(_G, "DEUS_CHEST_TYPES")
    local go_id = self._go_id
    local uses = (go_id and _altar_uses_by_go_id[go_id]) or 0
    if uses == 0 or not (DCT and self._chest_type == DCT.upgrade) then
        return func(self)  -- first use / non-upgrade: pure vanilla
    end
    if not self:can_interact() then return false end
    local drc = self._deus_run_controller
    local own_peer_id = drc and drc.get_own_peer_id and drc:get_own_peer_id()
    local soft = (own_peer_id and drc.get_player_soft_currency and drc:get_player_soft_currency(own_peer_id)) or 0
    local cost = self:get_purchase_cost() or math.huge
    local sd = rawget(_G, "script_data")
    local can_unlock = (sd and sd.unlock_all_deus_chests) or cost <= soft
    if can_unlock then
        local wielded = self._get_wielded_weapon and self:_get_wielded_weapon()
        if wielded then
            local rs = rawget(_G, "RaritySettings")
            local wr = rs and rs[wielded.rarity]
            local cr = rs and rs[self._rarity]
            if wr and cr and cr.order < wr.order then  -- RELAXED: block only a real downgrade
                can_unlock = false
            end
        end
    end
    if not can_unlock then return false end
    local nm = Managers.state and Managers.state.network
    local ps = nm and nm.profile_synchronizer
    if ps and ps.others_actually_ingame and not ps:others_actually_ingame() then
        return false
    end
    return true
end)

-- #252: same-tier temper (upgrade) altar re-roll shows the wrong (red) prompt.
-- The can_be_unlocked / update_upgrade_chest_color hooks above let a RE-ARMED upgrade altar
-- re-roll at the SAME rarity, but DeusUpgradeWeaponInteractionUI._populate_widget
-- (deus_upgrade_weapon_interaction_ui.lua:18-107) runs its OWN rarity test
-- (`weapon_rarity_order < chest_rarity_order`, :46) and at same tier takes the else branch
-- (:92-99), painting the RED disabled_text `reliquary_inactive_rarity`. ct never hooked this UI,
-- so the panel still reads "cannot upgrade" even though the altar is lit + interactable.
-- FIX: post-hook (hook_safe, runs after vanilla) the DERIVED class's _populate_widget (the method
-- is defined on DeusUpgradeWeaponInteractionUI, per the repo "hook the derived class" rule). For a
-- re-armed (uses>0) UPGRADE altar whose wielded rarity ORDER == the stored purchase's (== ONLY; a
-- real downgrade `order >` keeps the red text and is still blocked by can_be_unlocked; a real
-- upgrade `order <` already hits vanilla's available branch), repaint as available: item tooltip +
-- rarity + cost (mirrors vanilla :62-91), clear disabled_text, and set reward_info_text
-- (localize=false / white) to a plain re-roll message (no em dash). Everything is pcall-guarded, so
-- any API drift degrades to vanilla's (red) presentation rather than crashing.
CT_RELIQUARY_REROLL_MARKER = "reliquary_reroll_message:same_tier_upgrade_altar_v0.7.215"
CT_RELIQUARY_REROLL_PROMPT = "Reroll this weapon?"
mod:hook_safe("DeusUpgradeWeaponInteractionUI", "_populate_widget", function(self, interactable_unit, wielded_slot_name)
    pcall(function()
        local DCT = rawget(_G, "DEUS_CHEST_TYPES")
        if not (DCT and interactable_unit) then return end
        local SU = rawget(_G, "ScriptUnit")
        local pickup_ext = SU and SU.has_extension and SU.has_extension(interactable_unit, "pickup_system")
        if not (pickup_ext and pickup_ext._chest_type == DCT.upgrade) then return end
        local go_id = pickup_ext._go_id
        local uses = (go_id and _altar_uses_by_go_id[go_id]) or 0
        if uses == 0 then return end                        -- first use: leave vanilla path
        -- Others still joining -> vanilla shows the joining message; leave it. Derive from the
        -- profile_synchronizer (vanilla :52), NOT a self field (the agent's `self._others_actually_ingame`
        -- does not exist) -- same gate the can_be_unlocked hook above uses.
        local nm = Managers.state and Managers.state.network
        local ps = nm and nm.profile_synchronizer
        if not (ps and ps.others_actually_ingame and ps:others_actually_ingame()) then return end
        local mechanism = Managers.mechanism and Managers.mechanism:game_mechanism()
        local drc = mechanism and mechanism.get_deus_run_controller and mechanism:get_deus_run_controller()
        if not drc then return end
        local stored = pickup_ext.get_stored_purchase and pickup_ext:get_stored_purchase()
        if not stored then return end
        local melee, ranged = drc:get_own_loadout()
        local equipped = (wielded_slot_name == "slot_melee") and melee or ranged
        if not equipped then return end
        local rs = rawget(_G, "RaritySettings")
        local wr = rs and rs[equipped.rarity]
        local cr = rs and rs[stored.rarity]
        if not (wr and cr) then return end
        if wr.order ~= cr.order then return end             -- ONLY same-tier; up/downgrade untouched
        local chest_info_widget = self._widgets_by_name and self._widgets_by_name.chest_content
        local tooltip_widget    = self._widgets_by_name and self._widgets_by_name.weapon_tooltip
        if not (chest_info_widget and tooltip_widget) then return end
        local peer_id = drc:get_own_peer_id()
        local soft = drc:get_player_soft_currency(peer_id) or 0
        local cost = pickup_ext:get_purchase_cost() or 0
        tooltip_widget.content.item = equipped
        tooltip_widget.content.force_equipped = true
        tooltip_widget.style.item.draw_end_passes = true
        local rarity = stored.rarity
        chest_info_widget.content.rarity_text = rs[rarity].display_name
        local Cols = rawget(_G, "Colors")
        if Cols and Cols.get_table then chest_info_widget.style.rarity.text_color = Cols.get_table(rarity) end
        chest_info_widget.content.cost_text = soft .. "/" .. cost
        chest_info_widget.style.cost_text.text_color = (cost <= soft)
            and { 255, 255, 255, 255 } or { 255, 255, 0, 0 }
        chest_info_widget.content.reward_info_text = CT_RELIQUARY_REROLL_PROMPT
        chest_info_widget.content.show_coin_icon = true
        chest_info_widget.content.disabled_text = nil
        self._calculate_offset = true
    end)
end)

-- Exports. `altar_uses` is an ACCESSOR, not the table: reset_uses rebinds the
-- local, so a consumer that captured the table by value would keep mutating the
-- previous run's ledger. _ct_bot_weapon_chest_owner (the open_chest write seam)
-- already consumed exactly this shape when the ledger lived in the entry.
return {
    altar_uses = function()
        return _altar_uses_by_go_id
    end,
    altar_max_uses = _altar_max_uses,
    -- Run start: previous-run go_ids can collide with this run's new chests if
    -- Stingray's unit_storage cycles the same network ids, so the ledger is
    -- wiped rather than aged. Rebinding (not table.clear) is the pre-extraction
    -- statement verbatim; every reader in this chunk sees the new table through
    -- the upvalue, and the only out-of-chunk reader goes through altar_uses().
    reset_uses = function()
        _altar_uses_by_go_id = {}
    end,
}

end

return install
