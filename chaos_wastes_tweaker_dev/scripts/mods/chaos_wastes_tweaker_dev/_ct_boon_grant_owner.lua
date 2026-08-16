--[[
_ct_boon_grant_owner — the boon grant / purchase choke point (#1159 / #2 file-size refactor).

RESPONSIBILITY
Owns every seam that fires when a Chaos Wastes boon changes hands, and nothing
else:
  * the pre-grant disable gate on DeusRunController.add_power_ups — the single
    universal apply choke point every grant source funnels through (shrine pick,
    altar reward, cursed chest, Belakor temple, set reward, end-of-level, debug):
    strips disable_boon_<name> entries (#211) and, when peer parity is not
    confirmed, ct-modded entries (#426) BEFORE vanilla activates them
  * the unconditional [boon-trace] grant audit that same hook emits, including
    the #211 grant-source attribution read from mod._ct_grant_source
  * the v0.7.76 bot boon mirror: mirroring or per-bot random rolling of the
    host's boon onto every live bot, with the reentry guard, the announce line,
    and the bot economy charge/refund for the purchased-altar case
  * the second purchase seam the mirror needs: DeusRunController._try_buy_power_up
    (shrine-shop buys write the buyer's SharedState row directly and never reach
    add_power_ups), including the consolidated #458 start-shrine / #467 pricing
    delegation that shares this one hook
  * the two DeusShopView seams that render and record the price of that same
    purchase (_init_power_up_widget price text, _on_power_up_bought telemetry row)
  * the two regression checks those features register (bot_boon_announce_wired,
    bot_boon_economy_installed)

Extracted VERBATIM from chaos_wastes_tweaker_dev.lua with no behaviour change.
mod:dofile is not a singleton — the entry calls it EXACTLY once, at the exact
point this block previously executed (immediately after the #458 start-shrine and
#467 boon-pricing dofiles, immediately before the #211 grant-source tagging
hooks), so hook-registration order and _rt_register append order keep their
original timing.

COMPOSES WITH, DOES NOT OVERLAP, THE OTHER ct OWNERS
  * _ct_bot_economy.lua stays the PURE ledger (charge / credit / weapon_cost /
    shop_boon_cost / grant_cost). This module only calls it; it owns no arithmetic.
    The entry keeps the mod._ct_bot_economy_* runtime adapters (players, charge,
    log, credit_all, seed_all) it published at ~824-1006 and the coin-pickup
    hook, because those serve the weapon-chest and coin paths too.
  * _ct_bot_weapon_chest_owner.lua owns the WEAPON side of bot mirroring
    (DeusChestExtension.open_chest) and publishes mod._ct_bot_altar_cost, which
    this module READS to price an altar boon. Disjoint hooks, one shared field,
    written there and read here exactly as before.
  * _ct_start_shrine_runtime.lua (#458) and _ct_boon_pricing_runtime.lua (#467)
    own start-node purchase policy and per-boon prices. This module owns only the
    _try_buy_power_up hook they are both delegated from — the #458 comment marker
    `_ct_consolidated_try_buy_power_up_hook` moved with it, and the pair is still
    hooked exactly once mod-wide.
  * _ct_tab_panel_owner.lua previews the CONFIGURED starting boons; this module
    handles boons actually granted at runtime. No shared hook or helper.

HOOKS OWNED (each hooked EXACTLY ONCE in the whole mod — VMF silently drops a
second hook on the same Class/method pair; verified 2026-08-09):
  DeusRunController.add_power_ups        (full hook — disable gate + bot mirror)
  DeusRunController._try_buy_power_up    (full hook — consolidated #458/#466/#467)
  DeusShopView._init_power_up_widget     (full hook — #467 price text)
  DeusShopView._on_power_up_bought       (full hook — #467 telemetry price)

CROSS-FILE CONTRACT (unchanged by the move)
  * Entry helpers are reached through the mod._ct_* seams the entry publishes
    BEFORE this module loads: mod._ct_rt_register (entry ~337),
    mod._ct_effective_setting (entry ~2646), mod._ct_boon_disabled (entry ~3067),
    the mod._ct_bot_economy* adapters (entry ~824-1006), and the
    mod._ct_start_shrine_runtime / mod._ct_boon_pricing_runtime pair dofile'd on
    the four lines immediately above the dofile of this file.
  * mod._ct_is_modded_power_up and mod._ct_wire_safe come from
    _ct_meta_trait_boons.lua, which the entry dofiles LATER (~8296). Every call
    site here is already written `mod._ct_is_modded_power_up and ...` and resolves
    at CALL time, never at registration time — that was true inside the entry too,
    so the move changes nothing.
  * mod._ct_grant_source is a short-lived marker written by the #211 wrappers that
    stay in the entry (_check_set_completed ~7524, DeusCursedChestView
    ._on_button_pressed ~7535 — both BELOW this module's dofile, unchanged order)
    and by _ct_bot_weapon_chest_owner. This module reads it, and sets/restores it
    around its own bot loop, exactly as before.
  * mod._ct_bot_altar_cost is written by _ct_bot_weapon_chest_owner and read here.
  * CT_BOT_ECONOMY_MARKER stays a bare global set by the entry at ~823 and read
    bare by the moved bot_boon_economy_installed check.
  * Published on `mod` at the same script position as before, for the boon-price
    audit (entry ~885), _ct_boon_preview_helpers, _ct_profile_snapshot and the
    moved checks: mod._ct_boon_display_name, mod._ct_bot_pick_random_for_rarity.
  * NO entry file-local was left behind and NO promotion to a mod._ct_* field was
    needed. The one file-scope local this block declared, `_ct_bot_mirror_active`,
    is the mirror's reentry guard; its only appearance outside the moved lines is
    a prose mention in an entry comment (~3063), so it moved with the block and
    stays a plain file-local here.

DEVIATIONS FROM BYTE-IDENTICAL (three, all in the preamble below; the 486 moved
lines are byte-identical to entry lines 7334-7819 of v0.7.326-dev)
  1. `_dbg` is re-declared here. It is the entry's mod:debug wrapper verbatim
     (entry ~99-101); a file-local cannot cross a chunk boundary.
  2. `effective_setting` is a late-binding accessor onto mod._ct_effective_setting
     rather than the entry's forward-declared local. The entry assigns that local
     at ~2631 and publishes the SAME function object at ~2646, so every call here
     resolves to the identical function. This is the landed idiom from
     _ct_pickup_spawn_owner.lua.
  3. `_rt_register` is bound once from mod._ct_rt_register so the two moved checks
     keep byte-identical bodies and land in the SAME shared _RT_CHECKS list, in
     the same order, as before the split. Landed idiom from _ct_tab_panel_owner.lua.
]]

local mod = get_mod("ct_dev")

-- Behaviour-identical shims for the entry file-locals this block used before the
-- extraction. `_dbg` mirrors the entry's mod:debug wrapper (PROJECT_STANDARDS
-- § 3.6); the other two delegate to the mod._ct_* seams the entry publishes
-- earlier in its own chunk, so each call resolves to the exact same function
-- object.
local function _dbg(fmt, ...)
    mod:debug("[ct:dbg] " .. fmt, ...)
end

local effective_setting = function(name)
    local f = mod._ct_effective_setting
    if f then return f(name) end
    return mod:get(name)
end

local _rt_register = mod._ct_rt_register

-- ============================================================
-- Bot Boon Mirror (v0.7.76)
-- ============================================================
-- When `bots_mirror_host_boons` is on, every boon a HUMAN host gains in Chaos
-- Wastes (shrine pick, altar reward, dormant reveal, Belakor temple, blessing
-- of the gods, set reward, end-of-level grant, etc.) is also granted to every
-- bot in the lobby.
--
-- The single canonical entry point for boon application is
-- `DeusRunController.add_power_ups(new_power_ups, local_player_id, present)`
-- (deus_run_controller.lua:1126). Every code path that grants a boon — chest
-- pickup, cursed chest, shop blessing, set completion, end-of-level node
-- (`try_grant_end_of_level_deus_power_ups` falls through to this), debug — funnels
-- through here. Hooking it once covers all sources.
--
-- HOST-ONLY: Bots are entirely client-side on the host (they don't exist as
-- bots on remote peers; remote peers see them as husk units with normal buff
-- replication via the server-authoritative buff_system). So mirroring only
-- runs on `_run_state:is_server()`.
--
-- Reentry guard: re-calling `add_power_ups` for each bot would re-enter this
-- hook → infinite recursion. `_ct_bot_mirror_active` short-circuits the nested
-- calls.
--
-- Talent vs buff boons: `DeusPowerUpUtils.activate_deus_power_up` (called from
-- `add_power_ups`) branches on `power_up.talent`. Buff boons land via
-- `buff_system:add_buff(player_unit, buff_name, ...)` which works identically
-- on bot units. Talent boons mutate the backend talent ids for the receiving
-- career — that's fine when the bot has the same career as the host, but if
-- the bot is on a different career the talent slot still gets written into
-- the bot's own backend so the per-bot talent set is independent. The buff
-- the talent grants is the same one the host got.
--
-- Set completion: `_check_set_completed` runs inside `add_power_ups` post-add
-- and may recursively call `add_power_ups` for set rewards. We let those run
-- normally; the guard wraps only our bot-iteration loop so any set rewards a
-- bot triggers also mirror correctly.
local _ct_bot_mirror_active = false

-- Friendly display name for a deus boon/power-up key, for the host-side bot-boon
-- chat announcement (announce_bot_boons). Mirrors the in-file canonical pattern:
-- resolve DeusPowerUpTemplates[name].display_name via Localize, guarding the vanilla
-- "<key>" miss-sentinel; falls back to the raw key. On `mod` (not a new file-scope
-- local) per the 200-locals cap note; also lets /ct_regression_test reach it.
function mod._ct_boon_display_name(name)
    local tpl = rawget(_G, "DeusPowerUpTemplates")
    tpl = tpl and tpl[name]
    local key = tpl and tpl.display_name
    if key then
        local raw = Localize(key)
        if raw ~= "<" .. key .. ">" then return raw end
    end
    return tostring(name)
end

-- Shared rarity picker for altar/CoT mirrors and direct shrine-shop purchases.
-- The raw rarity registry retains disabled and CT-injected entries for lookup
-- parity, so every consumer must pass this same eligibility gate.
function mod._ct_bot_pick_random_for_rarity(rarity)
    local bucket = rawget(_G, "DeusPowerUpsArrayByRarity") and DeusPowerUpsArrayByRarity[rarity]
    if not bucket or #bucket == 0 then return nil end
    local eligible = {}
    for i = 1, #bucket do
        local entry = bucket[i]
        local name = entry and entry.name
        local parity_blocked = name and mod._ct_is_modded_power_up
            and mod._ct_is_modded_power_up(name)
            and not (mod._ct_wire_safe and mod._ct_wire_safe())
        if name and not mod._ct_boon_disabled(name) and not parity_blocked then
            eligible[#eligible + 1] = name
        end
    end
    if #eligible == 0 then return nil end
    return eligible[math.random(1, #eligible)]
end

-- (#144 boon-list snapshot helper removed with the retired [ct:boon144] SHRINK trace — the
-- list was proven never to lose the boon; the live instrument is mod._ct_vauls_anvil_reconcile.)

-- v0.7.159-dev Task 2: converted hook_safe -> full mod:hook so disabled boons can be
-- filtered OUT of `new_power_ups` BEFORE vanilla grants + activates them. ROOT CAUSE of
-- the `[boon-trace] DISABLED BOON GRANTED: blazing_revenge` leak: the disable filter only
-- stripped the ROLL pool (DeusPowerUpsArray / DeusPowerUpsArrayByRarity) inside the
-- generate_random_power_ups hook. But a boon ALTAR (DeusChestExtension, _chest_type ==
-- power_up) rolls + CACHES its single offered boon into `self._stored_purchase` at chest
-- SPAWN time (deus_chest_extension.lua:_generate_stored_power_up), then grants it via
-- add_power_ups on PURCHASE. If the user toggles `disable_boon_<name>` ON mid-run AFTER an
-- altar already cached that boon, the strip already missed it — the stale cached boon
-- sails through to add_power_ups. (Other specific-grant paths — set rewards via
-- _check_set_completed, starting boons — likewise bypass the pool strip.) add_power_ups is
-- the SINGLE universal apply chokepoint for every grant source, so gating HERE catches all
-- of them. effective_setting resolves host-authoritatively (host's value on clients), so
-- host + clients agree on what's disabled — a client never drops a boon the host legitimately
-- granted. Filtering to empty is safe: vanilla add_power_ups early-returns on #==0.
-- VMF singleton-hook rule: this remains the ONE (DeusRunController, add_power_ups) hook in
-- ct_dev (now a full mod:hook instead of hook_safe). DO NOT add another.
mod:hook("DeusRunController", "add_power_ups", function(func, self, new_power_ups, local_player_id, present)
    -- Pre-grant disable gate. Skip while the bot-mirror loop is granting (those entries
    -- are freshly materialized from a pool we already control, and re-filtering bot grants
    -- here is redundant; the guard also prevents touching the recursive set-reward grants).
    if not _ct_bot_mirror_active and type(new_power_ups) == "table" then
        for i = #new_power_ups, 1, -1 do
            local pu = new_power_ups[i]
            local name = pu and pu.name
            -- v0.7.200-dev (#211): shared helper (was an inline effective_setting == true check).
            if name and mod._ct_boon_disabled(name) then
                table.remove(new_power_ups, i)
                _dbg("[boon-trace] BLOCKED disabled boon at grant: %s (disable_boon_<name>=true) — stripped before add_power_ups",
                    tostring(name))
                -- Raw printf so the block is visible on the logging-OFF host too (#211).
                pcall(printf, "[boon-trace] BLOCKED disabled boon at grant: %s source=%s (issue #211)",
                    tostring(name), tostring(mod._ct_grant_source or "untagged"))
            -- v0.7.240-dev (#426): peer-parity wire gate at the canonical grant choke
            -- point (this hook covers chest, cursed chest, shop, set reward, end-of-level
            -- and debug grants). A ct-modded power-up granted while any lobby peer lacks
            -- ct rides the deus run-state sync (deus_run_state_spec.lua:60/:85) and the
            -- rpc_add_buff broadcast (buff_system.lua:302-305) as a modded lookup index
            -- and CTDs that peer. Belt-and-suspenders with the pool eject in the
            -- wire-safety block below: this catches any grant path even if a modded
            -- entry is still sitting in a rolled offer/pool snapshot.
            elseif name and mod._ct_is_modded_power_up and mod._ct_is_modded_power_up(name)
                and not (mod._ct_wire_safe and mod._ct_wire_safe()) then
                table.remove(new_power_ups, i)
                pcall(printf, "[ct:426] BLOCKED modded boon at grant: %s (peer parity not confirmed) source=%s",
                    tostring(name), tostring(mod._ct_grant_source or "untagged"))
            end
        end
    end

    -- #144: the [ct:boon144] before/after boon-list SHRINK trace that used to sit here has been
    -- RETIRED. It did its job: two clean repro logs (host + client) proved the boon list only ever
    -- GREW across grants and Vaul's Anvil (ct_boon_vauls_anvil) was never dropped from the list.
    -- The report has since been re-characterized: the boon STAYS in the list but its EFFECT stops
    -- working after an equip/wield action. That failure lives in the always_blocking perk lifecycle
    -- (deus_always_blocking_buff -> status.override_blocking), not the boon list -- so the instrument
    -- moved to mod._ct_vauls_anvil_reconcile below (tag [ct:vaul]), which both self-heals the perk
    -- every frame AND probes the exact wielded/lockout/override state on each change.
    func(self, new_power_ups, local_player_id, present)

    -- v0.7.90: unconditional audit trail for every boon grant. Logs name, rarity, recipient,
    -- and toggle state — surfaces any boon that slipped through a toggle. Tag `[boon-trace]`
    -- so the whole session's grants are greppable. Must live in this consolidated hook (VMF
    -- silently shadows duplicate hook on the same Class+method).
    -- v0.7.100-dev: dormant-specific trace fields removed (DORMANT_BOON_RARITY no longer
    -- exists; activate_dormant_* setting reads are dead). The disable_boon_* warning path
    -- still fires — that's the user-facing per-boon disable toggle and is fully active.
    -- v0.7.159-dev: with the pre-grant gate above, a DISABLED BOON GRANTED warning here now
    -- means a genuine bypass the gate didn't cover (e.g. _ct_bot_mirror_active path) — still
    -- worth surfacing.
    pcall(function()
        if not new_power_ups or #new_power_ups == 0 then return end
        local rs = self and self._run_state
        local own_peer = rs and rs.get_own_peer_id and rs:get_own_peer_id()
        local trace_is_server = rs and rs.is_server and rs:is_server()
        -- v0.7.200-dev (#211): grant-source attribution. `mod._ct_grant_source` is a
        -- short-lived marker set (and restored) around each wrapped grant path:
        -- "bot_mirror"/"bot_random" (ct's bot-boon loop below), "set_reward"
        -- (DeusRunController._check_set_completed wrapper), "cot_view_pick"
        -- (DeusCursedChestView._on_button_pressed wrapper). All markers are set+cleared
        -- synchronously within one call stack (single frame) — no race. "untagged" on the
        -- host with present=true and one boon is, per the #211 vanilla call-site map, the
        -- boon-ALTAR grant inside DeusChestExtension.open_chest. The consolidated full
        -- wrapper publishes the exact pre-purchase price for this synchronous call stack;
        -- a second hook on the same Class+method would violate the singleton invariant.
        -- That path is already double-covered by the
        -- roll-pool strip + the pre-grant gate above. Raw printf: the host runs VMF
        -- logging OFF, so mod:info/_dbg never lands there (diagnostics doctrine).
        local grant_source = tostring(mod._ct_grant_source or "untagged")
        for i = 1, #new_power_ups do
            local pu = new_power_ups[i]
            local name = pu and pu.name or "?"
            local rarity = pu and pu.rarity or "?"
            local disable_toggle = mod._ct_boon_disabled(name)
            pcall(printf, "[boon-trace] grant source=%s boon=%s rarity=%s disabled=%s recipient_local_id=%s present=%s (issue #211)",
                grant_source, tostring(name), tostring(rarity), tostring(disable_toggle),
                tostring(local_player_id), tostring(present))
            _dbg("[boon-trace] add_power_ups: name=%s rarity=%s recipient_local_id=%s present=%s peer=%s is_server=%s disable_toggle=%s",
                tostring(name), tostring(rarity), tostring(local_player_id), tostring(present),
                tostring(own_peer), tostring(trace_is_server),
                tostring(disable_toggle))
            if disable_toggle == true then
                mod:warning("[boon-trace] DISABLED BOON GRANTED: %s (disable_boon_<name>=true) source=%s — investigate source path",
                    tostring(name), grant_source)
            end
        end
    end)

    if _ct_bot_mirror_active then return end
    local mode_mirror = effective_setting("bots_mirror_host_boons")
    local mode_random = effective_setting("bots_get_random_boons")
    if not (mode_mirror or mode_random) then return end
    if not new_power_ups or #new_power_ups == 0 then return end

    local run_state = self._run_state
    if not run_state or not run_state:is_server() then return end

    -- Resolve who just got the boon. add_power_ups uses
    -- `run_state:get_own_peer_id()` for the recipient peer; the recipient
    -- local_player_id is the second arg. We want to mirror onto bots only when
    -- the recipient is a HUMAN (otherwise a bot's own grant would re-trigger
    -- the bot loop).
    local own_peer_id = run_state:get_own_peer_id()
    local recipient = Managers.player and Managers.player:player(own_peer_id, local_player_id)
    if recipient and recipient.bot_player then return end

    local player_manager = Managers.player
    if not player_manager or not player_manager.human_and_bot_players then return end
    local all_players = player_manager:human_and_bot_players()
    if not all_players then return end

    -- Filter bots and skip the recipient (defensive — recipient should be human
    -- per the check above, but harmless to double-check).
    local bots = {}
    for _, p in pairs(all_players) do
        if p ~= recipient and p.bot_player and p.player_unit and Unit.alive(p.player_unit) then
            bots[#bots + 1] = p
        end
    end
    if #bots == 0 then return end

    _dbg("[bot-boon] mode=%s host_grant=%d bot_count=%d",
        mode_random and "random" or "mirror", #new_power_ups, #bots)

    -- The audited untagged + present=true path is a purchased boon altar. The
    -- consolidated open_chest wrapper publishes its exact scaled purchase cost
    -- only for the duration of vanilla open_chest -> add_power_ups. CoT/view and
    -- end-of-level grants stay free, matching vanilla.
    local incoming_source = mod._ct_grant_source
    local boon_cost_source = (incoming_source == nil and present == true
        and mod._ct_bot_altar_cost ~= nil) and "boon_altar" or tostring(incoming_source or "free_grant")
    local boon_cost = mod._ct_bot_economy.grant_cost(boon_cost_source, mod._ct_bot_altar_cost)

    -- v0.7.120-dev: per-bot independent random pick from DeusPowerUpsArrayByRarity[rarity].
    -- Picks a random entry of the SAME rarity the host just got, then materializes via
    -- generate_specific_power_up (gives each bot a fresh client_id). Falls back to a
    -- mirror grant for that slot if the rarity bucket is empty / missing.
    local function _pick_random_for_rarity(rarity)
        return mod._ct_bot_pick_random_for_rarity(rarity)
    end

    -- Clone the power-up list per-bot. Each call needs fresh client_ids so the
    -- run_state stores distinct entries (otherwise the same client_id appears
    -- across multiple players and `remove_power_ups` matching could mis-target).
    -- announce_bot_boons (default off): host-local chat line naming each bot and the
    -- boon it received, so the host can see what bots got (esp. in random mode). mod:echo
    -- is local-only — no RPC/version-sync risk; the feature is already host-gated above.
    local announce = effective_setting("announce_bot_boons") == true
    _ct_bot_mirror_active = true
    -- v0.7.200-dev (#211): grant-source marker for the audit printf in this same hook
    -- (the bot grants below re-enter add_power_ups). Set/restored around the pcall so
    -- it can never leak past this call stack.
    local _prev_grant_source = mod._ct_grant_source
    mod._ct_grant_source = mode_random and "bot_random" or "bot_mirror"
    local ok, err = pcall(function()
        for _, bot in ipairs(bots) do
            local cloned = {}
            for i = 1, #new_power_ups do
                local host_pu = new_power_ups[i]
                local bot_name = host_pu.name
                if mode_random then
                    local picked = _pick_random_for_rarity(host_pu.rarity)
                    if picked then
                        bot_name = picked
                    end
                end
                -- v0.7.200-dev (#211) defense-in-depth: never grant a disabled boon to a
                -- bot, whatever the pick/mirror source. The random picker is now
                -- disabled-aware and mirror-mode names already passed the pre-grant gate,
                -- so this firing means a new bypass — printf it (host runs logging OFF).
                if mod._ct_boon_disabled(bot_name) then
                    pcall(printf, "[bot-boon] SKIPPED disabled boon for bot: %s (disable_boon_<name>=true, issue #211)",
                        tostring(bot_name))
                -- v0.7.240-dev (#426): parity defense-in-depth for the bot grant, same
                -- rationale as the picker filter above (this loop's add_power_ups
                -- re-entry skips the pre-grant parity gate via _ct_bot_mirror_active).
                elseif mod._ct_is_modded_power_up and mod._ct_is_modded_power_up(bot_name)
                    and not (mod._ct_wire_safe and mod._ct_wire_safe()) then
                    pcall(printf, "[ct:426] SKIPPED modded boon for bot: %s (peer parity not confirmed)",
                        tostring(bot_name))
                else
                    cloned[#cloned + 1] = DeusPowerUpUtils.generate_specific_power_up(bot_name, host_pu.rarity)
                    _dbg("[bot-boon] bot=%s slot=%d rarity=%s host=%s -> bot=%s",
                        tostring(bot.name and bot:name() or "?"),
                        i, tostring(host_pu.rarity), tostring(host_pu.name), tostring(bot_name))
                    if announce then
                        -- The boon display name can carry unfilled `%.1f` placeholders
                        -- (raw loc + description_values). Don't pre-string.format then
                        -- echo -- mod:echo string.formats its first arg, so a pre-built
                        -- string re-interprets the %.1f and prints "<Invalid string
                        -- format>". Pass the parts as args so mod:echo formats ONCE; the
                        -- boon name's % is then inert (a %s substitution value).
                        -- allow-echo: user-opted-in announce_bot_boons chat notice (checkbox, default off) naming each bot grant; not routine diagnostics (#727)
                        mod:echo("[ct] Bot %s got boon: %s (%s)",
                            tostring(bot.name and bot:name() or "?"),
                            tostring(mod._ct_boon_display_name(bot_name)),
                            mode_random and "rolled" or "mirrored")
                    end
                end
            end
            -- Charge only if at least one wire-safe boon survived selection. Bots
            -- that cannot afford a purchased altar receive nothing; free CoT and
            -- end-of-level grants use cost=0 and always pass this gate.
            local affordable = #cloned > 0 and mod._ct_bot_economy_charge(run_state,
                bot, boon_cost, boon_cost_source)
            if affordable then
                -- present=false: don't trigger the reward-popup UI for bot grants.
                local grant_ok, grant_err = pcall(self.add_power_ups, self,
                    cloned, bot:local_player_id(), false)
                if not grant_ok then
                    local peer_id, bot_local = bot:network_id(), bot:local_player_id()
                    local balance = run_state:get_player_soft_currency(peer_id, bot_local) or 0
                    run_state:set_player_soft_currency(peer_id, bot_local,
                        mod._ct_bot_economy.credit(balance, boon_cost))
                    mod._ct_bot_economy_log("boon grant failed/refunded bot=%s source=%s cost=%s error=%s",
                        tostring(bot.name and bot:name() or bot_local), tostring(boon_cost_source),
                        tostring(boon_cost), tostring(grant_err))
                end
            elseif #cloned > 0 then
                mod._ct_bot_economy_log("boon skipped bot=%s source=%s cost=%s selected=%d",
                    tostring(bot.name and bot:name() or bot:local_player_id()),
                    tostring(boon_cost_source), tostring(boon_cost), #cloned)
            end
        end
    end)
    _ct_bot_mirror_active = false
    mod._ct_grant_source = _prev_grant_source

    if not ok then
        pcall(printf, "[bot-boon] error granting boons to bots: %s", tostring(err))
        return
    end

    _dbg("[bot-boon] %s %d boon(s) onto %d bot(s)",
        mode_random and "rolled" or "mirrored", #new_power_ups, #bots)
end)

-- Shrine-shop purchases do NOT call add_power_ups: vanilla _try_buy_power_up
-- writes the buyer's SharedState row directly. Own this second source seam so
-- bot boon modes cover shrines as their tooltips promise, with an independent
-- affordability gate and the same random/disabled/parity policy as altars.
mod:hook("DeusRunController", "_try_buy_power_up", function(func, self, buyer, power_up, discount)
    -- _ct_consolidated_try_buy_power_up_hook: #458 must share this existing
    -- purchase choke point with #466. A second VMF hook on the pair is dropped.
    local start_handled, bought = false, nil
    if mod._ct_start_shrine_runtime then
        start_handled, bought = mod._ct_start_shrine_runtime.try_buy(
            self, buyer, power_up, discount)
    end
    if not start_handled then
        local pricing_handled, pricing_bought
        if mod._ct_boon_pricing_runtime then
            pricing_handled, pricing_bought = mod._ct_boon_pricing_runtime.try_buy(
                self, buyer, power_up, discount)
        end
        if pricing_handled then
            bought = pricing_bought
        else
            bought = func(self, buyer, power_up, discount)
        end
    end
    if not bought or _ct_bot_mirror_active then return bought end
    local run_state = self and self._run_state
    if not (run_state and run_state:is_server() and buyer == run_state:get_own_peer_id()) then return bought end

    local mode_mirror = effective_setting("bots_mirror_host_boons")
    local mode_random = effective_setting("bots_get_random_boons")
    if not (mode_mirror or mode_random) or not power_up then return bought end

    _ct_bot_mirror_active = true
    local ok, err = pcall(function()
        for _, bot in ipairs(mod._ct_bot_economy_players()) do
            if bot.player_unit and Unit.alive(bot.player_unit) then
                local boon_name = power_up.name
                if mode_random then
                    boon_name = mod._ct_bot_pick_random_for_rarity(power_up.rarity) or boon_name
                end
                local bot_power_up = { name = boon_name, rarity = power_up.rarity }
                local cost = start_handled and mod._ct_start_shrine_runtime.price(
                    power_up.rarity, discount, boon_name)
                    or (mod._ct_boon_pricing_runtime
                        and mod._ct_boon_pricing_runtime.price(bot_power_up, discount, 100))
                    or mod._ct_bot_economy.shop_boon_cost(rawget(_G, "DeusCostSettings"),
                        power_up.rarity, discount)
                local start_allowed = not start_handled
                    or mod._ct_start_shrine_runtime.can_purchase(self,
                        bot:network_id(), bot:local_player_id())
                local blocked = not start_allowed or mod._ct_boon_disabled(boon_name)
                    or (mod._ct_is_modded_power_up and mod._ct_is_modded_power_up(boon_name)
                        and not (mod._ct_wire_safe and mod._ct_wire_safe()))
                if not blocked and mod._ct_bot_economy_charge(run_state, bot, cost, "shrine_boon") then
                    local generated = DeusPowerUpUtils.generate_specific_power_up(boon_name, power_up.rarity)
                    local grant_ok, grant_err = pcall(self.add_power_ups, self,
                        { generated }, bot:local_player_id(), false)
                    if not grant_ok then
                        local peer_id, local_player_id = bot:network_id(), bot:local_player_id()
                        local balance = run_state:get_player_soft_currency(peer_id, local_player_id) or 0
                        run_state:set_player_soft_currency(peer_id, local_player_id,
                            mod._ct_bot_economy.credit(balance, cost))
                        mod._ct_bot_economy_log("shrine grant failed/refunded bot=%s cost=%s error=%s",
                            tostring(bot.name and bot:name() or local_player_id), tostring(cost), tostring(grant_err))
                    end
                    if grant_ok then
                        if start_handled then
                            mod._ct_start_shrine_runtime.record_purchase(self,
                                bot:network_id(), bot:local_player_id())
                        end
                        local profile_index, career_index = run_state:get_player_profile(
                            bot:network_id(), bot:local_player_id())
                        mod._ct_bot_economy_log("shrine choice bot=%s profile=%s:%s mode=%s boon=%s rarity=%s cost=%s",
                            tostring(bot.name and bot:name() or bot:local_player_id()),
                            tostring(profile_index), tostring(career_index),
                            mode_random and "random" or "mirror", tostring(boon_name),
                            tostring(power_up.rarity), tostring(cost))
                    end
                elseif blocked then
                    mod._ct_bot_economy_log("shrine choice blocked bot=%s boon=%s parity_or_disabled=true",
                        tostring(bot.name and bot:name() or bot:local_player_id()), tostring(boon_name))
                end
            end
        end
    end)
    _ct_bot_mirror_active = false
    if not ok then mod._ct_bot_economy_log("shrine bot purchase error=%s", tostring(err)) end
    return bought
end)

mod:hook("DeusShopView", "_init_power_up_widget", function(func, self, widget,
        power_up_instance, discount, current_value, max_value, profile_index, career_index)
    func(self, widget, power_up_instance, discount, current_value, max_value,
        profile_index, career_index)
    if mod._ct_boon_pricing_runtime then
        local price = mod._ct_boon_pricing_runtime.view_price(self, power_up_instance, discount)
        if price and widget and widget.content then widget.content.price_text = tostring(price) end
    end
end)

mod:hook("DeusShopView", "_on_power_up_bought", function(func, self, power_up, discount)
    func(self, power_up, discount)
    if not (mod._ct_boon_pricing_runtime and self and self._telemetry_data) then return end
    local price = mod._ct_boon_pricing_runtime.view_price(self, power_up, discount)
    local rows = self._telemetry_data.purchased_boons
    if price and type(rows) == "table" and rows[#rows] then rows[#rows].cost = price end
end)

-- #144 install-time finding (kept for the record): there is NO fixed max-boon cap in vanilla. A
-- player's active power-ups live in a dynamic SharedState Lua table (deus_run_state_spec.lua:298
-- "power_ups"); DeusRunController.add_power_ups (deus_run_controller.lua:1126) only ever appends.
-- The boon-list SHRINK hypothesis was DISPROVEN by two clean repro logs, so the [ct:boon144] list
-- trace is retired. The report is now: the boon stays in the list but its EFFECT stops after an
-- equip/wield action -> tracked by the [ct:vaul] perk reconciler/probe (see mod._ct_vauls_anvil_reconcile).

-- Regression guard for the announce_bot_boons feature. The singleton-hook invariant for
-- (DeusRunController, add_power_ups) is enforced statically by tools/mod-lint; this runtime
-- check verifies the announce wiring: the boon-name helper resolves (never empty / sentinel)
-- and the announce checkbox is actually registered.
_rt_register("bot_boon_announce_wired", function()
    if type(mod._ct_boon_display_name) ~= "function" then
        return "BOT-BOON REGRESSION: mod._ct_boon_display_name missing"
    end
    local fallback = mod._ct_boon_display_name("__ct_no_such_boon__")
    if type(fallback) ~= "string" or fallback == "" then
        return "BOT-BOON REGRESSION: _ct_boon_display_name returned empty for unknown key (should fall back to the raw key)"
    end
    if type(mod:get("announce_bot_boons")) ~= "boolean" then
        return "BOT-BOON REGRESSION: announce_bot_boons checkbox not registered (mod:get is non-boolean)"
    end
end)

_rt_register("bot_boon_economy_installed", function()
    if CT_BOT_ECONOMY_MARKER ~= "bot_economy:independent_charge_gate_v0.7.278" then
        return "#466 bot economy marker missing or stale"
    end
    local economy = mod._ct_bot_economy
    if type(economy) ~= "table" or type(economy.charge) ~= "function"
        or type(economy.credit) ~= "function" or type(economy.weapon_cost) ~= "function"
        or type(economy.shop_boon_cost) ~= "function" then
        return "#466 bot economy policy incomplete"
    end
    local allowed, balance = economy.charge(150, 100)
    if not allowed or balance ~= 50 then return "#466 affordable charge self-test failed" end
    allowed, balance = economy.charge(50, 100)
    if allowed or balance ~= 50 then return "#466 insufficient-funds self-test failed" end
    if type(mod._ct_bot_pick_random_for_rarity) ~= "function"
        or type(mod._ct_bot_economy_charge) ~= "function" then
        return "#466 bot choice/charge runtime helper missing"
    end
end)
