-- _ct_bot_weapon_chest_owner.lua -- CT-dev bot weapon chest and reusable-altar owner.
--
-- Owns bot weapon generation/equip, chest diagnostics, purchase visual
-- suppression, and the singleton consolidated open_chest hook. Shared altar
-- state is late-bound through injected accessors because the entry replaces
-- its per-run use table during lifecycle reset.
--
-- Owned by: chaos_wastes_tweaker_dev.lua entry point.
-- Consumed via: one ordered mod:dofile installer call, its installed chest
-- hooks, and _ct_replacement_compensation.lua through mod._ct_bot_equip_weapon;
-- guarded by qa/lua/tests/test_ct_bot_weapon_chest_owner.lua.
return function(ctx)
    assert(type(ctx) == "table", "CT bot weapon chest owner requires context")

    local mod = assert(ctx.mod, "CT bot weapon chest owner requires mod")
    local state = mod._ct_bot_weapon_chest_owner_state
    if not state then
        state = {}
        mod._ct_bot_weapon_chest_owner_state = state
    end

    state.effective_setting = assert(ctx.effective_setting,
        "CT bot weapon chest owner requires effective_setting")
    state.dbg = assert(ctx.dbg, "CT bot weapon chest owner requires debug logger")
    state.dbg_alert = assert(ctx.dbg_alert,
        "CT bot weapon chest owner requires alert logger")
    state.altar_uses = assert(ctx.altar_uses,
        "CT bot weapon chest owner requires altar-use accessor")
    state.altar_max_uses = assert(ctx.altar_max_uses,
        "CT bot weapon chest owner requires altar max-use policy")
    state.probe_collected_by_peers = assert(ctx.probe_collected_by_peers,
        "CT bot weapon chest owner requires collected-peer probe")
    state.altar_probe_watch = assert(ctx.altar_probe_watch,
        "CT bot weapon chest owner requires altar probe watch")

    local function _effective_setting(...)
        return state.effective_setting(...)
    end
    local function _dbg(...)
        return state.dbg(...)
    end
    local function _dbg_alert(...)
        return state.dbg_alert(...)
    end
    local function _altar_uses()
        return state.altar_uses()
    end

-- The chest-mirror helpers below keep the entry's original column-0 layout, so
-- they are forward-declared here rather than introduced by `local function`.
-- That keeps them scoped to this installer call instead of reading as
-- module-level definitions inside the installer closure.
local _resolve_bot_career, _bot_equip_weapon, _bot_get_current_loadout
local _gen_bot_weapon_for_slot, _diag_subscribe_if_needed

-- ============================================================
-- Bot Weapon-Chest Mirror (v0.7.120-dev)
-- ============================================================
-- When `bots_mirror_host_weapon_upgrades` is on, every time the HOST opens a
-- deus weapon reliquary, every bot also receives the equivalent operation:
--   * swap_melee / swap_ranged chest -> bot gets a freshly-rolled random
--     weapon of the same rarity for its CW career (independent roll per bot,
--     using the bot's own career weapon pool).
--   * upgrade chest ("temper") -> bot's currently-equipped CW weapon is
--     upgraded to the same target rarity with re-rolled traits / properties.
--   * power_up chests are ignored here — the existing add_power_ups hook
--     already handles boon-side mirroring.
--
-- HOST-ONLY: same reasoning as Bot Boon Mirror. Bots are local-side on the
-- host; the host's `DeusChestExtension.open_chest` only fires when the host
-- themselves opens a chest (clients fire their own local copy). Server-
-- authoritative SimpleInventoryExtension replication carries the bot's new
-- weapon unit to remote peers.
--
-- The Equip pipeline mirrors vanilla `_equip_weapon` (deus_chest_extension.lua:581):
--   1. deus_backend:grant_deus_weapon(item)   -- assigns backend_id
--   2. mutate _bot_loadouts[bot_career][slot_name] = backend_id  (no public setter)
--   3. bot_inventory:create_equipment_in_slot(slot_name, backend_id, 1)
--   4. deus_backend:refresh_deus_weapons_in_items_backend()
--   5. _run_state:set_player_loadout(host_peer, bot_local_id, profile, career, slot, item_string)
--
-- Step 2 is the only break from public API. There's no `BackendInterfaceDeusBase.
-- set_bot_loadout_item(item_backend_id, career_name, slot_name)` — the bot-loadout
-- table is populated once at run start by `DeusMechanism._build_deus_inventory`
-- and never mutated mid-run by vanilla. We reach in directly. Wrapped in pcall
-- so the run survives any deviation in backend structure.
state.bot_weapon_mirror_active = state.bot_weapon_mirror_active == true

function _resolve_bot_career(bot)
    local profile_index, career_index = nil, nil
    if Managers.state and Managers.state.network and Managers.state.network.profile_synchronizer then
        local sync = Managers.state.network.profile_synchronizer
        if sync.profile_by_peer then
            -- Husk/bot resolution is the same as for any player_unit.
            local peer = bot:network_id()
            local local_id = bot:local_player_id()
            profile_index, career_index = sync:profile_by_peer(peer, local_id)
        end
    end
    if not profile_index or not career_index or profile_index == 0 then
        local profile = bot.profile_index and bot:profile_index()
        local career = bot.career_index and bot:career_index()
        if profile and career then
            profile_index, career_index = profile, career
        end
    end
    if not profile_index or not career_index or profile_index == 0 or career_index == 0 then
        return nil, nil, nil
    end
    local profile = SPProfiles[profile_index]
    local career = profile and profile.careers and profile.careers[career_index]
    return profile_index, career_index, career and career.name or nil
end

function _bot_equip_weapon(bot, new_weapon, slot_name, run_state, host_peer_id)
    if not new_weapon or not slot_name then
        return false, "no weapon or slot"
    end
    local profile_index, career_index, career_name = _resolve_bot_career(bot)
    if not career_name then
        return false, "unresolved bot career"
    end

    local deus_backend = Managers.backend and Managers.backend.get_interface and Managers.backend:get_interface("deus")
    if not deus_backend then
        return false, "no deus backend"
    end

    new_weapon.preferred_slot_name = slot_name
    deus_backend:grant_deus_weapon(new_weapon)
    deus_backend:refresh_deus_weapons_in_items_backend()
    local backend_id = new_weapon.backend_id
    if not backend_id then
        return false, "grant_deus_weapon did not assign backend_id"
    end

    -- Step 2: reach into _bot_loadouts directly (no public setter exists). Keyed by
    -- career_name, then slot_name -> backend_id. Initialize the per-career sub-table
    -- if vanilla didn't populate it for this slot.
    local bot_loadouts = rawget(deus_backend, "_bot_loadouts")
    if type(bot_loadouts) == "table" then
        bot_loadouts[career_name] = bot_loadouts[career_name] or {}
        bot_loadouts[career_name][slot_name] = backend_id
    else
        _dbg_alert("[bot-weap] deus_backend._bot_loadouts missing or non-table (got %s) — backend state may diverge",
            type(bot_loadouts))
    end

    -- Step 3: swap the live weapon unit on the bot. The inventory_system extension
    -- is the same SimpleInventoryExtension that human players use; bots are just
    -- AI-controlled player_units. create_equipment_in_slot replaces the existing
    -- slot unit and server-replicates to husks on remote peers.
    local bot_unit = bot.player_unit
    if bot_unit and Unit.alive(bot_unit) then
        local inv_ext = ScriptUnit.has_extension(bot_unit, "inventory_system")
        if inv_ext and inv_ext.create_equipment_in_slot then
            inv_ext:create_equipment_in_slot(slot_name, backend_id, 1)
        else
            _dbg_alert("[bot-weap] bot %s missing inventory_system or create_equipment_in_slot",
                tostring(bot.name and bot:name() or "?"))
        end
    end

    -- Step 5: persist into CW run_state so the bot's loadout survives respawn /
    -- `_update_career_loadout` reads. We need the lower-level set_player_loadout
    -- (DeusRunController.save_loadout is hardcoded to REAL_PLAYER_LOCAL_ID).
    local item_string = DeusWeaponGeneration.serialize_weapon(new_weapon)
    if run_state and run_state.set_player_loadout then
        run_state:set_player_loadout(host_peer_id, bot:local_player_id(),
            profile_index, career_index, slot_name, item_string)
    end

    _dbg("[bot-weap] bot=%s career=%s slot=%s rarity=%s key=%s power=%s backend_id=%s",
        tostring(bot.name and bot:name() or "?"),
        tostring(career_name), tostring(slot_name),
        tostring(new_weapon.rarity), tostring(new_weapon.deus_item_key),
        tostring(new_weapon.power_level), tostring(backend_id))

    return true
end

-- #465's replacement hook is registered earlier in this chunk but fires only
-- after load. Export the one canonical bot equip primitive so a human->bot
-- handoff updates the live/backend loadout as well as the SharedState row.
state.bot_equip_weapon = _bot_equip_weapon
    state.public_bot_equip_weapon = state.public_bot_equip_weapon or function(...)
        return state.bot_equip_weapon(...)
    end
    mod._ct_bot_equip_weapon = state.public_bot_equip_weapon

    if state.installed then
        return false
    end

function _bot_get_current_loadout(bot, run_state, host_peer_id, slot_name)
    local profile_index, career_index, _ = _resolve_bot_career(bot)
    if not profile_index or not career_index then return nil end
    if not (run_state and run_state.get_player_loadout) then return nil end
    local item_string = run_state:get_player_loadout(host_peer_id, bot:local_player_id(),
        profile_index, career_index, slot_name)
    if not item_string then return nil end
    local ok, weapon = pcall(DeusWeaponGeneration.deserialize_weapon, item_string)
    if not ok then
        _dbg_alert("[bot-weap] deserialize failed for bot=%s slot=%s: %s",
            tostring(bot.name and bot:name() or "?"), slot_name, tostring(weapon))
        return nil
    end
    return weapon
end

function _gen_bot_weapon_for_slot(bot, run_state, target_rarity, slot_name, seed)
    local _, _, bot_career_name = _resolve_bot_career(bot)
    if not bot_career_name then return nil end
    local whitelist = run_state and run_state.get_weapon_group_whitelist and run_state:get_weapon_group_whitelist()
    if not whitelist then return nil end
    local pool = DeusWeaponGeneration.generate_weapon_pool(bot_career_name, whitelist)
    if not pool or not pool[target_rarity] then
        _dbg_alert("[bot-weap] no weapon pool for bot career=%s rarity=%s", tostring(bot_career_name), tostring(target_rarity))
        return nil
    end
    -- generate_weapon_for_slot picks from the slot's bucket only.
    local difficulty = run_state and run_state.get_run_difficulty and run_state:get_run_difficulty()
    local current_node = run_state and run_state.get_current_node_key and run_state:get_current_node_key()
    local run_progress = 0
    if current_node then
        local graph = Managers.mechanism:game_mechanism()
        local deus_run = graph and graph.get_deus_run_controller and graph:get_deus_run_controller()
        local node_data = deus_run and deus_run._get_graph_data and deus_run:_get_graph_data()
        if node_data and node_data[current_node] then
            run_progress = node_data[current_node].run_progress or 0
        end
    end
    local slot_short = slot_name == "slot_melee" and "melee" or "ranged"
    local ok, weapon = pcall(DeusWeaponGeneration.generate_weapon_for_slot,
        difficulty or "normal", run_progress, target_rarity, seed, pool, slot_short)
    if not ok or not weapon then
        _dbg_alert("[bot-weap] generate_weapon_for_slot failed bot=%s slot=%s rarity=%s err=%s",
            tostring(bot.name and bot:name() or "?"), slot_name, target_rarity, tostring(weapon))
        return nil
    end
    return weapon
end

-- Diagnostic event subscribers (gated on VMF debug logging via _dbg). The
-- event_manager gets torn down + recreated between missions, so we register
-- lazily and use a per-event-manager guard so re-registrations don't pile up.
state.diag_event_manager_ref = state.diag_event_manager_ref
-- NOTE (v0.7.216 fix): this table was `setmetatable({}, { __mode = "v" })` - a
-- WEAK-VALUED table. Its values ARE the handler functions below, referenced nowhere
-- else, so the GC collected them between file-load and the first mission; by the time
-- _diag_subscribe_if_needed ran, `state.diag_subscriber.player_pickup_deus_weapon_chest`
-- was nil and EventManager.register fatally fasserted "No function found with name ...
-- on supplied object" (event_manager.lua:16) inside the pcall, so the pickup/chest
-- diagnostic NEVER attached (it fired on every map populate). A plain strong table keeps
-- the handlers alive; the module-scope local lives for the whole session (no leak), and
-- the vanilla EventManager already stores subscribers weakly on its own side.
state.diag_subscriber = state.diag_subscriber or {}

state.diag_subscriber.player_pickup_deus_weapon_chest = function(self, player)
    local name = player and player.name and player:name() or "?"
    local is_bot = player and player.bot_player and "BOT" or "human"
    _dbg("[diag] event:player_pickup_deus_weapon_chest player=%s (%s)", tostring(name), is_bot)
end

state.diag_subscriber.chest_unlock_failed = function(self, chest_type)
    _dbg("[diag] event:chest_unlock_failed chest_type=%s", tostring(chest_type))
end

function _diag_subscribe_if_needed()
    local ev = Managers.state and Managers.state.event
    if not ev or ev == state.diag_event_manager_ref then return end
    state.diag_event_manager_ref = ev
    local ok, err = pcall(function()
        ev:register(state.diag_subscriber,
            "player_pickup_deus_weapon_chest", "player_pickup_deus_weapon_chest",
            "chest_unlock_failed",              "chest_unlock_failed")
    end)
    if not ok then
        pcall(printf, "[diag] subscriber register failed: %s", tostring(err))
    else
        _dbg("[diag] diagnostic event subscribers registered (new event_manager)")
    end
end

mod:hook_safe("DeusChestExtension", "extensions_ready", function(self)
    _diag_subscribe_if_needed()
end)

-- #103 — PREVENT the structure-collapse animation on a re-armed altar.
-- ============================================================
-- Symptom (user 2026-06-30): a re-usable altar with uses remaining correctly
-- KEEPS its glow/offering (our open_chest post-hook re-fires lua_update_<chest_type>),
-- but its physical MODEL still shows the collapsed/looted pose after a single use.
--
-- Root cause: vanilla purchase() (deus_chest_extension.lua:301-317) fires
-- `Unit.flow_event(self.unit, "lua_update_collected")` — the STRUCTURE-collapse
-- transition in the altar unit's flow graph. That event is ONE-WAY (vanilla altars
-- are single-use, so nothing ever un-collapses them). Re-firing lua_update_<chest_type>
-- afterward (our open_chest re-arm) restores the offering hologram/glow but NOT the
-- collapsed structure — exactly the reported "glow OK, model collapsed".
--
-- Fix (Peregrinaje's approach = PREVENTION, not reversal — verified against the
-- Peregrinaje extract, which for reusable altars keeps _is_purchased=false and simply
-- never fires lua_update_collected): when this purchase will leave uses remaining, we
-- suppress ONLY that one flow event for the duration of vanilla purchase(), so the
-- structure never collapses in the first place. Everything else about purchase()
-- (cost via our get_purchase_cost hook, _is_purchased, "looted" anim state, the
-- rpc_deus_chest_looted round-trip) is left byte-identical to today, so the existing
-- open_chest post-hook re-arm operates on exactly the state it always has.
--
-- FAILS SAFE: the flow-event filter is installed under pcall; if it can't be installed
-- or restored, we fall back to plain vanilla purchase() — the altar collapses as it
-- does today (no visual fix on that path, but NO regression to glow/cost/currency).
-- The FINAL use (uses will be spent) always calls vanilla so the altar collapses
-- normally when genuinely depleted. `purchase` is a DIFFERENT method from our
-- `open_chest` hook, so this is not a duplicate hook. Uses check matches open_chest's
-- (`_altar_uses()` is incremented in the open_chest post-hook AFTER purchase(),
-- so re-arm here = (current + 1) < max, identical to open_chest's `uses < max`).
mod:hook("DeusChestExtension", "purchase", function(func, self)
    local go_id = self._go_id
    local max_uses = (type(self._chest_type) == "string" and state.altar_max_uses(self._chest_type)) or 1
    local will_rearm = go_id and (((_altar_uses()[go_id] or 0) + 1) < max_uses)
    if not will_rearm then
        return func(self)  -- single / final use: collapse normally
    end

    local unit = self.unit
    local real_flow_event = Unit.flow_event
    local ok_install = pcall(function()
        Unit.flow_event = function(u, event, ...)
            if u == unit and event == "lua_update_collected" then
                return  -- swallow the structure-collapse for this re-armed altar
            end
            return real_flow_event(u, event, ...)
        end
    end)
    if not ok_install then
        pcall(function() Unit.flow_event = real_flow_event end)
        return func(self)  -- couldn't install the filter -> behave exactly as today
    end

    local ok, err = pcall(func, self)
    pcall(function() Unit.flow_event = real_flow_event end)  -- ALWAYS restore
    if not ok then
        -- purchase() errored under the filter. Do NOT re-run it (would double-charge);
        -- the filter is already restored. Log via printf (visible with mod-logging off).
        pcall(printf, "[altar_reuse] purchase under collapse-filter errored (go_id=%s): %s",
            tostring(go_id), tostring(err))
    end
end)

-- _ct_consolidated_open_chest_hook
-- =================================
-- THIS IS THE ONLY `open_chest` hook in ct_dev. Both the v0.7.127 altar-reuse
-- re-arm logic AND the bot-weapon-mirror logic live in this single
-- `mod:hook_safe`. DO NOT add a second `mod:hook(DeusChestExtension, open_chest)`
-- or `mod:hook_safe(DeusChestExtension, open_chest)` anywhere else in this
-- file — VMF silently DROPS the second hook (see VMF_RECIPES.md § 1 +
-- feedback_vmf_no_duplicate_hooks). It happened in v0.7.129/.130 and the
-- altar-reuse "fix" sat there as dead code for two releases. Catch via
-- /ct_regression_test → `open_chest_hook_singleton`. Source-pattern marker:
-- the string `_ct_consolidated_open_chest_hook` on this line.
mod:hook("DeusChestExtension", "open_chest", function(func, self)
    -- #100 fix (v0.7.169-dev): capture the rarity vanilla open_chest JUST used to
    -- upgrade the host's weapon, BEFORE the upgrade-altar re-arm block below bumps
    -- self._rarity one tier higher for the NEXT use. The bot-weapon-mirror (further
    -- down this same hook) must mirror the rarity the HOST actually received, not the
    -- bumped next-use value — otherwise bots land one tier above the host
    -- (log-confirmed 2026-06-25 go_id=62: host wielded=rare, altar bumped to exotic,
    -- bots got exotic). Captured for all chest types; only the upgrade path is bumped,
    -- so swap_melee/swap_ranged see their unchanged self._rarity here.
    local _opened_rarity = self._rarity
    local _opened_cost = self:get_purchase_cost()
    local prior_bot_altar_cost = mod._ct_bot_altar_cost
    if self._chest_type == DEUS_CHEST_TYPES.power_up then
        mod._ct_bot_altar_cost = _opened_cost
    end
    local vanilla_ok, vanilla_err = pcall(func, self)
    mod._ct_bot_altar_cost = prior_bot_altar_cost
    if not vanilla_ok then error(vanilla_err) end
    -- v0.7.131-dev altar-reuse re-arm (was a separate mod:hook in v0.7.129/.130,
    -- which collided with the bot-weapon-mirror hook below and was dropped by
    -- VMF). Runs FIRST so re-arm fires regardless of bot-mirror reentrancy state.
    -- Vanilla open_chest just finished (_post_chest_unlock → purchase, then
    -- _equip_weapon for weapon chests) — both completed with real profile_index,
    -- so we can safely zero it here to force the chest's `update` loop into its
    -- re-roll branch.
    do
        local go_id = self._go_id
        if go_id then
            _altar_uses()[go_id] = (_altar_uses()[go_id] or 0) + 1
            local uses = _altar_uses()[go_id]
            local max_uses = state.altar_max_uses(self._chest_type)

            -- v0.7.157-dev Task A [altar_visual_probe]: FORCED-OUTPUT diagnosis
            -- (unconditional mod:info — user just plays, no command needed). Capture
            -- chest_type / go_id / use count / re-arm branch decision, and
            -- collected_by_peers BEFORE the uncollect runs. Read-only.
            local is_server = Managers and Managers.player and Managers.player.is_server
            local collected_before = state.probe_collected_by_peers(go_id)
            _dbg("[altar_visual_probe] OPEN go_id=%s chest_type=%s uses=%d/%d rearm_branch=%s is_server=%s is_purchased=%s anim=%s profile_idx=%s collected_before=%s",
                tostring(go_id), tostring(self._chest_type), uses, max_uses,
                tostring(uses < max_uses), tostring(is_server),
                tostring(self._is_purchased), tostring(self._animation_state),
                tostring(self._profile_index), collected_before)

            if uses < max_uses then
                self._is_purchased = false
                self._animation_state = nil
                self._profile_index = 0
                self._career_index = 0
                -- v0.7.151-dev: ALSO retract this peer from the networked
                -- collected_by_peers GameSession field, kept adjacent to the
                -- _profile_index/_career_index zeroing so the next vanilla
                -- update() tick sees consistent state. Without it, vanilla
                -- update() (deus_chest_extension.lua:175) re-derives
                -- new_is_purchased=true from the still-present peer and re-loots
                -- the altar VISUALLY (line 177-182 -> _animation_state="looted"
                -- -> line 194 skips the anim update -> hologram never reappears).
                -- Pure data write to one field; does NOT re-enter purchase().
                mod._ct_altar_uncollect(self)

                -- v0.7.159-dev (the "used-up visual fires on use 1" root-cause fix):
                -- vanilla purchase() (deus_chest_extension.lua:308) ALREADY fired
                -- `lua_update_collected` — the used-up/looted MODEL transition — on
                -- THIS open, BEFORE this post-hook runs. Clearing _is_purchased /
                -- _animation_state above only stops the looted state being RE-asserted
                -- in update() (line 175-182); it does NOT un-fire the flow event, so
                -- the flow graph stays on the collected/looted mesh. The only thing
                -- that pulls it back to the live/available presentation is re-firing
                -- `lua_update_<chest_type>` (the SAME event vanilla emits at line 142
                -- when it re-rolls), but vanilla only does that inside the
                -- profile_index-changed branch (line 134) — racy and not guaranteed on
                -- the re-arm tick. Re-fire it here, deterministically, so a re-armed
                -- altar (uses < max) leaves the used-up look IMMEDIATELY. The depleted
                -- (else) branch deliberately re-fires NOTHING, leaving vanilla's
                -- lua_update_collected in place, so the used-up visual now shows ONLY
                -- after the final use. Per-peer: each peer runs its own post-hook +
                -- its own update() derivation off the host-authoritative
                -- collected_by_peers, so host and clients both flip available->used-up
                -- only when the host's configured max uses are spent. pcall-guarded
                -- per the repo Unit.flow_event rule (engine call, fatal bypasses pcall
                -- on a dead unit — has_unit guard + pcall).
                if self.unit and Unit and Unit.flow_event
                    and (not Unit.alive or Unit.alive(self.unit))
                    and type(self._chest_type) == "string" then
                    pcall(Unit.flow_event, self.unit, "lua_update_" .. self._chest_type)
                end

                _dbg("[altar_reuse] go_id=%s type=%s used %d/%d -> re-arm",
                    tostring(go_id), tostring(self._chest_type), uses, max_uses)

                -- v0.7.211-dev #102 DECOUPLE (was the v0.7.158 rarity bump): do NOT bump
                -- self._rarity on re-arm. The reward tier is self._rarity (open_chest ->
                -- _generate_upgraded_weapon), so bumping it climbed the reward each use. Instead
                -- self._rarity stays at the constant rolled tier and the relaxed
                -- update_upgrade_chest_color / can_be_unlocked hooks (near _generate_upgraded_weapon,
                -- `<=` -> strict `<` for a re-armed upgrade altar) keep the altar lit + usable at
                -- same-tier without inflating the reward. Here we just refresh the rolled tier's glow
                -- and clear the cached color memo so the color logic re-evaluates on the next tick.
                if self._chest_type == DEUS_CHEST_TYPES.upgrade then
                    if self._rarity and self.unit and Unit and Unit.flow_event
                        and (not Unit.alive or Unit.alive(self.unit)) then
                        pcall(Unit.flow_event, self.unit, "lua_update_" .. self._rarity)
                    end
                    self._prev_update_upgrade_chest_color_event = nil
                    _dbg("[altar_reuse] upgrade re-arm go_id=%s altar_rarity=%s (no bump, decoupled)",
                        tostring(go_id), tostring(self._rarity))
                end

                -- v0.7.157-dev Task A [altar_visual_probe]: collected_by_peers AFTER
                -- the uncollect, plus the post-re-arm visual state we just wrote.
                -- Arm the per-go_id update-tick watcher so the read-only
                -- DeusChestExtension.update hook logs how vanilla re-derives the
                -- state over the next few ticks (does it re-set _is_purchased /
                -- _animation_state="looted"?).
                local collected_after = state.probe_collected_by_peers(go_id)
                local own_peer = self._deus_run_controller and self._deus_run_controller.get_own_peer_id
                    and self._deus_run_controller:get_own_peer_id()
                _dbg("[altar_visual_probe] REARM go_id=%s chest_type=%s own_peer=%s collected_after=%s post_rearm{is_purchased=%s anim=%s profile_idx=%s}",
                    tostring(go_id), tostring(self._chest_type), tostring(own_peer),
                    collected_after, tostring(self._is_purchased),
                    tostring(self._animation_state), tostring(self._profile_index))
                state.altar_probe_watch[go_id] = { ticks = 8, type = tostring(self._chest_type) }
            else
                _dbg("[altar_visual_probe] DEPLETED go_id=%s chest_type=%s uses=%d/%d -> stays looted (max reached, expected dark)",
                    tostring(go_id), tostring(self._chest_type), uses, max_uses)
            end
        else
            _dbg("[altar_visual_probe] OPEN no go_id on ext (chest_type=%s) — re-arm path skipped entirely",
                tostring(self._chest_type))
        end
    end

    -- ---- Boon-altar no-repeat bookkeeping (runs on the buying peer) ----
    -- For boon (power_up) ALTARS: record the taken boon for the per-run no-repeat
    -- default (always-on), so later boon altars don't re-offer it. This is a boon
    -- ALTAR / Shrine of Solace, NOT a Chest of Trials -- see the terminology
    -- banner near the get_purchase_cost hook.
    if self._chest_type == DEUS_CHEST_TYPES.power_up then
        local taken = self._stored_purchase and self._stored_purchase.name
        if taken then
            mod._ct_boon_altar_taken_boons = mod._ct_boon_altar_taken_boons or {}
            mod._ct_boon_altar_taken_boons[taken] = true
        end
        _dbg("[boon_altar] boon altar opened; taken boon=%s", tostring(taken))
    end

    -- ---- Bot weapon mirror (was the only body before v0.7.131 consolidation) ----
    if state.bot_weapon_mirror_active then return end
    if not _effective_setting("bots_mirror_host_weapon_upgrades") then return end

    local run_controller = self._deus_run_controller
    local run_state = run_controller and run_controller._run_state
    if not run_state or not run_state:is_server() then return end

    local chest_type = self._chest_type
    if chest_type == DEUS_CHEST_TYPES.power_up then
        -- boon chests are handled by the add_power_ups bot-mirror hook above.
        return
    end
    if chest_type ~= DEUS_CHEST_TYPES.swap_melee
            and chest_type ~= DEUS_CHEST_TYPES.swap_ranged
            and chest_type ~= DEUS_CHEST_TYPES.upgrade then
        _dbg("[bot-weap] open_chest fired with unrecognized chest_type=%s", tostring(chest_type))
        return
    end

    -- Recipient = host human local player. Bots cannot open chests, so this is
    -- always the host when on the server.
    local host_peer_id = run_state:get_own_peer_id()
    local target_slot
    if chest_type == DEUS_CHEST_TYPES.swap_melee then
        target_slot = "slot_melee"
    elseif chest_type == DEUS_CHEST_TYPES.swap_ranged then
        target_slot = "slot_ranged"
    else
        -- upgrade chest: vanilla upgrades the host's wielded weapon; for the bot
        -- we'll upgrade the bot's currently-wielded slot independently.
        local _, wielded_slot = self:_get_wielded_weapon()
        target_slot = wielded_slot or "slot_melee"
    end

    -- #100 fix (v0.7.169-dev): use the rarity the HOST's weapon was actually upgraded
    -- to on THIS open (captured at hook entry before the re-arm bump), NOT the live
    -- self._rarity — for upgrade altars the re-arm block above has already bumped
    -- self._rarity one tier higher for the next use, which is what made bots land a
    -- tier above the host. For swap altars _opened_rarity == self._rarity (no bump).
    local target_rarity = _opened_rarity
    if not target_rarity then
        _dbg("[bot-weap] no chest rarity recorded — aborting bot mirror")
        return
    end

    local player_manager = Managers.player
    if not player_manager or not player_manager.human_and_bot_players then return end
    local all_players = player_manager:human_and_bot_players()
    if not all_players then return end

    local bots = {}
    for _, p in pairs(all_players) do
        if p.bot_player and p.player_unit and Unit.alive(p.player_unit) then
            bots[#bots + 1] = p
        end
    end
    if #bots == 0 then
        _dbg("[bot-weap] no live bots present — chest_type=%s rarity=%s", tostring(chest_type), tostring(target_rarity))
        return
    end

    _dbg("[bot-weap] host opened chest_type=%s rarity=%s target_slot=%s bots=%d",
        tostring(chest_type), tostring(target_rarity), tostring(target_slot), #bots)

    state.bot_weapon_mirror_active = true
    local ok, err = pcall(function()
        local go_id = self._go_id or (Managers.state.unit_storage and Managers.state.unit_storage:go_id(self.unit))
        for bi, bot in ipairs(bots) do
            -- Per-bot seed: chest go_id + bot local id + bot peer + slot. Keeps
            -- rolls reproducible if vanilla determinism matters for replay diff.
            local bot_seed_input = string.format("%s_%s_%s_%s",
                tostring(go_id or 0), tostring(bot:local_player_id()),
                tostring(bot:network_id() or "?"), target_slot)
            local seed = HashUtils.fnv32_hash(bot_seed_input)
            local new_weapon
            local current = _bot_get_current_loadout(bot, run_state, host_peer_id, target_slot)
            if chest_type == DEUS_CHEST_TYPES.upgrade then
                if current then
                    local current_order = RaritySettings[current.rarity] and RaritySettings[current.rarity].order or 0
                    local target_order = RaritySettings[target_rarity] and RaritySettings[target_rarity].order or 0
                    if current_order >= target_order then
                        _dbg("[bot-weap] bot=%s slot=%s current rarity=%s >= chest rarity=%s — skipping upgrade",
                            tostring(bot.name and bot:name() or "?"), target_slot,
                            tostring(current.rarity), tostring(target_rarity))
                    else
                        local difficulty = run_state:get_run_difficulty()
                        local current_node_key = run_state:get_current_node_key()
                        local graph = run_controller._get_graph_data and run_controller:_get_graph_data()
                        local progress = graph and graph[current_node_key] and graph[current_node_key].run_progress or 0
                        new_weapon = DeusWeaponGeneration.upgrade_item(current, difficulty, progress, target_rarity, seed)
                    end
                else
                    _dbg_alert("[bot-weap] bot=%s slot=%s has no current CW weapon to upgrade — synthesizing fresh",
                        tostring(bot.name and bot:name() or "?"), target_slot)
                    new_weapon = _gen_bot_weapon_for_slot(bot, run_state, target_rarity, target_slot, seed)
                end
            else
                new_weapon = _gen_bot_weapon_for_slot(bot, run_state, target_rarity, target_slot, seed)
            end
            -- #121 DIAGNOSTIC [ct:bots121]: log the tier the bot lands on vs the host's
            -- opened tier. Post #100/#102, live self._rarity == _opened_rarity == target_rarity
            -- and new_weapon.rarity should equal target_rarity (== host tier). ANY drift here
            -- (bot_after order > host tier) is the "one tier above" smoking gun. Read-only.
            pcall(function()
                local pre_rarity = "n/a"
                if chest_type == DEUS_CHEST_TYPES.upgrade then
                    local c = _bot_get_current_loadout(bot, run_state, host_peer_id, target_slot)
                    pre_rarity = c and tostring(c.rarity) or "none"
                end
                pcall(printf, "[ct:bots121] bot=%s chest=%s slot=%s host_opened_rarity=%s live_self_rarity=%s target_rarity=%s bot_before=%s bot_after=%s (issue #121)",
                    tostring(bot.name and bot:name() or "?"), tostring(chest_type), tostring(target_slot),
                    tostring(_opened_rarity), tostring(self._rarity), tostring(target_rarity),
                    tostring(pre_rarity), tostring(new_weapon and new_weapon.rarity))
            end)
            if new_weapon then
                local bot_cost = mod._ct_bot_economy.weapon_cost(rawget(_G, "DeusCostSettings"),
                    chest_type, current and current.rarity, target_rarity, _opened_cost)
                if mod._ct_bot_economy_charge(run_state, bot, bot_cost, "weapon_" .. tostring(chest_type)) then
                    local equipped_ok, equip_err = _bot_equip_weapon(bot, new_weapon, target_slot, run_state, host_peer_id)
                    if not equipped_ok then
                        -- A failed equip must be economically atomic: restore the
                        -- charge and leave the bot's prior weapon intact.
                        local peer_id, local_player_id = bot:network_id(), bot:local_player_id()
                        local balance = run_state:get_player_soft_currency(peer_id, local_player_id) or 0
                        run_state:set_player_soft_currency(peer_id, local_player_id,
                            mod._ct_bot_economy.credit(balance, bot_cost))
                        _dbg_alert("[bot-weap] equip failed bot_idx=%d (refunded %d): %s",
                            bi, bot_cost, tostring(equip_err))
                    end
                else
                    mod._ct_bot_economy_log("weapon skipped bot=%s chest=%s cost=%s current=%s target=%s",
                        tostring(bot.name and bot:name() or bot:local_player_id()), tostring(chest_type),
                        tostring(bot_cost), tostring(current and current.rarity), tostring(target_rarity))
                end
            else
                _dbg("[bot-weap] bot_idx=%d produced no new weapon (skip)", bi)
            end
        end
    end)
    state.bot_weapon_mirror_active = false

    if not ok then
        pcall(printf, "[bot-weap] error mirroring weapon chest to bots: %s", tostring(err))
        return
    end

    _dbg("[bot-weap] mirrored chest_type=%s rarity=%s onto %d bot(s)",
        tostring(chest_type), tostring(target_rarity), #bots)
end)

    state.installed = true
    mod._ct_bot_weapon_chest_owner_installed = true
    return true
end
