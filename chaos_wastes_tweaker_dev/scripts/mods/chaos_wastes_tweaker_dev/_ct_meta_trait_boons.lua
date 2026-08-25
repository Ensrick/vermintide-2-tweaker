-- _ct_meta_trait_boons.lua — Trait-boon wrapper and bounded resource hooks.
--
-- Owns CT-authored trait-boon registration, host-dependent resynchronization,
-- and bounded trait/buff hooks. Meta-boon and peer-parity ownership are
-- delegated synchronously to `_ct_meta_boon_owner.lua` and
-- `_ct_peer_parity_owner.lua` at their former inline boundaries.
-- Loaded after boon balance and registry by the ct_dev entry manifest.
--
-- Owned by: chaos_wastes_tweaker_dev.lua. Consumed via: one mod:dofile call.

local mod = get_mod("ct_dev")
local context = mod._ct_boon_runtime_context
if type(context) ~= "table" then
    error("[ct:boon-runtime] missing entry-point context")
end

local balance = mod._ct_boon_balance
local registry = mod._ct_boon_registry
if type(balance) ~= "table" or type(registry) ~= "table" then
    error("[ct:boon-runtime] balance/registry modules must load before meta boons")
end

local _dbg = context.dbg
local effective_setting = context.effective_setting
local _rt_register = context.rt_register
local _capture_returns = context.capture_returns
local _collect_setting_ids = context.collect_setting_ids
local CT_RPC_SCHEMA = context.rpc_schema

local sync_reckless_swings = balance.sync_reckless_swings
local sync_bomb_cooldown = balance.sync_bomb_cooldown
local sync_boon_movespeed = balance.sync_boon_movespeed
local sync_poison_proof_tweak = balance.sync_poison_proof_tweak
local sync_invis_potion_tweak = balance.sync_invis_potion_tweak
local sync_moot_milk_alt_tweak = balance.sync_moot_milk_alt_tweak
local sync_shard_strike = balance.sync_shard_strike
local sync_anath_raema_permanent = balance.sync_anath_raema_permanent
local apply_anath_raema_permanent_tweak = balance.apply_anath_raema_permanent_tweak
local _anath_raema_buff_entries = balance.anath_raema_buff_entries
local CT_ANATH_RAEMA_RETRY_MARKER = balance.anath_raema_retry_marker

local inject_dormant_boon = registry.inject_dormant_boon
local _add_dormant_to_pool = registry.add_dormant_to_pool
local _remove_dormant_from_pool = registry.remove_dormant_from_pool
local _injected_dormants = registry.injected_dormants
local register_buff_in_network_lookup = registry.register_buff_in_network_lookup
local register_power_up_in_network_lookup = registry.register_power_up_in_network_lookup

local sync_host_dependent_state

local install_meta_boons = mod:dofile(
    "scripts/mods/chaos_wastes_tweaker_dev/_ct_meta_boon_owner")
if type(install_meta_boons) ~= "function" then
    error("[ct:boon-runtime] meta-boon owner did not return an installer")
end
install_meta_boons(mod, {
    context = context,
    registry = registry,
})

-- ============================================================
-- Mod Boon: Khaine's Communion — 1 green HP per kill (v0.7.32-alpha)
-- ============================================================
-- Heal 1 permanent (green) health every time the player kills an enemy. Exotic rarity.
-- Catalogued under Defensive > Health in the boon tree (per user verdict — health-themed
-- effect groups by effect, not by mod-added origin), but display name carries the
-- "(Mod Boon)" prefix so it's flagged.
--
-- Implementation: proc function with `authority = "server"` so the heal fires once
-- per kill on the server, then `DamageUtils.heal_network` networks the heal to the
-- killer's owning peer. Heal type `heal_from_proc` restores permanent HP (green),
-- not THP.
-- ============================================================
-- Mod Boons: Trait-as-Boon (v0.7.34-alpha)
-- ============================================================
-- 4 weapon traits re-introduced as opt-in exotic boons. Each is gated behind its own
-- toggle in Reworks > Reworks: Boons (default off). When enabled, the trait's buff
-- template is cloned into a new power-up at exotic rarity.
--
-- STACKING WITH TRAIT:
-- * Vaul's Anvil — naturally non-stacks (always_blocking is a binary perk; having two
--   sources of the same perk = same effect as one source).
-- * Manann's Tempest — stacks (each buff fires its own chain_lightning proc on crit,
--   so 2 buffs = 2 independent chains per crit).
-- * Taal's Twinned Arrow — stacks (extra_shot stat_buff bonus is additive: 2 buffs =
--   +2 projectiles).
-- * Asuryan's Wrath — stacks (each fires its own proc roll on melee kill, so 2 buffs
--   = roughly +75% effective proc chance vs +50% baseline).
--
-- TAAL'S TWINNED ARROW RESTRICTION: user asked for "only granted if ranged weapon in
-- slot 2." Vanilla VT2 careers all have a ranged slot, so the case is rare. If the
-- player ends up with this boon but no ranged weapon, the stat_buff is just inert
-- (no shots fire = no extra projectiles). Skipping the gate for v0.7.34; can add an
-- offer-time filter if it becomes a real issue.
-- #144: Vaul's Anvil perk reconciler + probe (replaces vanilla always_blocking_update on ct's
-- boon controller buff; registered into BuffFunctionTemplates.functions in pre_register_trait_boon_
-- lookups and pointed at by the cloned controller sub-buff's update_func).
--
-- The boon's effect is the `deus_always_blocking_buff`, which drives status.override_blocking on/off
-- (apply/remove_always_blocking, morris_buff_settings.lua:1003/1009). Vanilla maintains that perk
-- ONLY reactively: block-broken lockout recovery, plus an ORPHANED weapon-swap trigger
-- (always_blocking_weapon_swap, :3093) that NOTHING in the shipped engine ever calls. So once the
-- perk is dropped -- e.g. by the block-broken 10s lockout, or a buff refresh on some equip/wield/
-- pickup action -- there is no reliable path that re-adds it, and the boon "stops working" while
-- still sitting in the boon list (exactly the #144 re-characterization). This reconciler is
-- authoritative EVERY frame: the perk is present IFF a melee weapon is wielded AND the lockout is
-- not active, so it self-heals any drop the moment the player is back on melee. Runs in the same
-- buff-update context vanilla always_blocking_update did (buff_extension.lua:794), so add_buff/
-- remove_buff of the perk carry the same authority/network path (apply/remove_always_blocking do
-- the override_blocking network send). It also edge-logs `[ct:vaul]` (raw printf; the host runs VMF
-- logging OFF) on every state change, including a `desync` watch (override_blocking not matching the
-- wielded/lockout state even though the perk presence is correct) -- if that ever fires the loss is
-- deeper than perk presence and the log will say so. On `mod.` (not a file-scope local) per the Lua
-- 5.1 200-locals cap. pcall-free hot path but every engine call is existence-guarded.
mod._ct_vauls_anvil_reconcile = function(unit, buff, params)  -- luacheck: ignore params
    local buff_ext = ScriptUnit.has_extension(unit, "buff_system")
    local inv_ext  = ScriptUnit.has_extension(unit, "inventory_system")
    if not (buff_ext and inv_ext) then return end
    local perk_name = (buff.template and buff.template.buff_to_add) or "deus_always_blocking_buff"
    local eq       = inv_ext:equipment()
    local wielded  = eq and eq.wielded and eq.wielded.slot_type or nil
    local melee    = wielded == "melee"
    local locked   = buff_ext:has_buff_type("deus_always_blocking_lock_out") and true or false
    local want     = melee and not locked
    local has_perk = buff_ext:has_buff_type(perk_name) and true or false
    local action   = "none"

    if want and not has_perk then
        buff.buff_id = buff_ext:add_buff(perk_name)
        has_perk = true
        action = "readd"
    elseif (not want) and has_perk then
        if buff.buff_id then buff_ext:remove_buff(buff.buff_id) end
        buff.buff_id = nil
        has_perk = false
        action = melee and "remove_lockout" or "remove_ranged"
    end

    -- Watch (not healed here): override_blocking should equal `want` once the perk state is right.
    -- Per the engine, override_blocking is set ONLY by apply/remove_always_blocking, so reconciling
    -- the perk above should keep it correct; a persistent desync would mean an external clear.
    local status_ext = ScriptUnit.has_extension(unit, "status_system")
    local override   = status_ext and status_ext.override_blocking
    local desync     = status_ext and ((want and override ~= true) or ((not want) and override ~= nil)) or false

    -- Edge-triggered: log only when the state changes, so per-mission volume stays tiny.
    local sig = string.format("%s|%s|%s|%s|%s", tostring(wielded), tostring(locked), tostring(has_perk), tostring(override), action)
    if buff._ct_vaul_sig ~= sig then
        buff._ct_vaul_sig = sig
        pcall(printf, "[ct:vaul] wielded=%s melee=%s locked=%s has_perk=%s override_blocking=%s want=%s action=%s desync=%s (#144)",
            tostring(wielded), tostring(melee), tostring(locked), tostring(has_perk),
            tostring(override), tostring(want), action, tostring(desync))
    end
end

local CT_TRAIT_BOONS = {
    { name = "ct_boon_vauls_anvil",         toggle = "enable_boon_vauls_anvil",         rarity = "unique", icon = "deus_icon_meta_01", source_buff = "always_blocking" },
    { name = "ct_boon_manann_tempest",      toggle = "enable_boon_manann_tempest",      rarity = "unique", icon = "deus_icon_meta_01", source_buff = "deus_crit_chain_lightning" },
    { name = "ct_boon_taal_twinned_arrow",  toggle = "enable_boon_taal_twinned_arrow",  rarity = "unique", icon = "deus_icon_meta_01", source_buff = "deus_extra_shot" },
    { name = "ct_boon_asuryan_wrath",       toggle = "enable_boon_asuryan_wrath",       rarity = "unique", icon = "deus_icon_meta_01", source_buff = "deus_collateral_damage_on_melee_killing_blow" },
    -- #464 follow-up: Anath Raema's Swiftness could never appear in the Disabled/Starting
    -- Boons menus because it is a weapon TRAIT (deus_ammo_pickup_reload_speed,
    -- weapon_traits_morris.lua:528; rolled in the deus_ranged_ammo trait pool :853 and
    -- deus_trollhammer_torpedo :975), NOT a DeusPowerUpTemplates power-up - vanilla has no
    -- boon form of it, so the BOON_TREE enumeration had nothing to list. This 5th
    -- trait-as-boon closes that gap. `literal_buffs` (fixed template) instead of
    -- `source_buff`: the trait's BuffTemplates entry is MUTABLE (the
    -- tweak_anath_raema_permanent rework save-and-restores it, see
    -- apply_anath_raema_permanent_tweak ~L10755), so a load-time clone would silently
    -- change the boon's behavior with the rework toggle's state at load. The literal is
    -- deterministic: ALWAYS the permanent variant. multiplier -0.5 = reload HOLD TIME
    -- x 0.5 (reload_speed is an INVERSE stat: weapon_unit_extension.lua:966 composes
    -- value x (multiplier + 1), buff_extension.lua:1431-1432; the #464 sign-error class).
    -- Menu category: Offensive > Ranged in BOON_TREE (beside vanilla boon_range_01
    -- "Anath Raema's Cruel Volley"), not Mod Boons - the vanilla trait is ranged-pool
    -- and the user looks for it by function (#464 comment 2026-07-12).
    { name = "ct_boon_anath_raema_swiftness", toggle = "enable_boon_anath_raema_swiftness", rarity = "unique", icon = "deus_icon_meta_01",
        literal_buffs = { { name = "ct_boon_anath_raema_swiftness", stat_buff = "reload_speed", multiplier = -0.5, max_stacks = 1 } } },
}
local function register_trait_boon(spec)
    -- v0.7.67: registration (NetworkLookup, buff template, DeusPowerUps* sides)
    -- now happens unconditionally in pre_register_trait_boon_lookups. This
    -- function is only responsible for the toggle-gated pool insert, which
    -- determines whether the user actually rolls the boon.
    if not mod._ct_umbrella_policy.enabled(
        effective_setting("enable_boon_reworks"), effective_setting(spec.toggle)) then
        _remove_dormant_from_pool(spec.name, spec.rarity)
        return
    end
    _add_dormant_to_pool(spec.name, spec.rarity)
    _dbg("[trait-boon] enabled " .. spec.name .. " at rarity " .. spec.rarity)
end

-- v0.7.61: same shape as pre_register_dormant_lookups (v0.7.60). The gated
-- register_trait_boon below skips registration entirely when the peer's
-- enable_boon_<name> toggle is off, so without this pre-registration step two
-- peers with different toggle states (host enables Vaul's Anvil + Manann's
-- Tempest, client only enables Manann's Tempest) appended a different ordered
-- subset of `power_up_ct_boon_*_unique` entries to NetworkLookup.buff_templates
-- and matching deus_power_up_templates entries -- so the host's rpc_add_buff
-- for a trait-boon index resolved to either the wrong buff or a missing key on
-- the client. Pre-register every trait boon's DeusPowerUpTemplate, buff
-- template, and NetworkLookup entries unconditionally at mod-load in sorted
-- order; the gated register_trait_boon below only does pool injection now (its
-- own writes to buff_templates / NetworkLookup are idempotent early-outs).
local function pre_register_trait_boon_lookups()
    local templates       = rawget(_G, "DeusPowerUpTemplates")
    local buff_templates  = rawget(_G, "BuffTemplates")
    local dpubt           = rawget(_G, "DeusPowerUpBuffTemplates")
    if not (templates and buff_templates and dpubt) then
        _dbg("[trait-boon] pre-register skipped: globals not yet loaded")
        return
    end
    -- #144: register ct's Vaul's Anvil perk reconciler into the shared buff-function table
    -- BEFORE any buff can resolve it. buff_extension.update calls
    -- BuffFunctionTemplates.functions[update_func](...) UNGUARDED (buff_extension.lua:794), so a
    -- buff must never name an unregistered function. We therefore only repoint the boon's
    -- update_func to "ct_vauls_anvil_reconcile" when this registration actually succeeded; otherwise
    -- the clone keeps vanilla "always_blocking_update" (always present) and simply falls back to
    -- vanilla behavior -- no crash. BuffFunctionTemplates is a core global loaded before mods, so
    -- readiness here is the normal case.
    local _ct_reconciler_ready = false
    do
        local buff_funcs = rawget(_G, "BuffFunctionTemplates")
        if buff_funcs and buff_funcs.functions and type(mod._ct_vauls_anvil_reconcile) == "function" then
            buff_funcs.functions.ct_vauls_anvil_reconcile = mod._ct_vauls_anvil_reconcile
            _ct_reconciler_ready = true
        else
            _dbg("[trait-boon] BuffFunctionTemplates not ready -- Vaul's Anvil keeps vanilla always_blocking_update (reconciler deferred)")
        end
    end
    local sorted = {}
    for _, spec in ipairs(CT_TRAIT_BOONS) do sorted[#sorted + 1] = spec end
    table.sort(sorted, function(a, b) return a.name < b.name end)
    -- v0.7.63-alpha: register the NetworkLookup NAMES unconditionally (sorted
    -- order, every peer assigns identical indices regardless of which source
    -- buffs are loaded in their BuffTemplates). The buff-template clone +
    -- DeusPowerUpBuffTemplates write still requires source_template, but those
    -- side tables don't determine the sequential NetworkLookup id — only the
    -- name registration does. Splitting them prevents the receiver-side crash
    -- pattern where peer A skipped Vaul's Anvil (source 'always_blocking'
    -- missing for some reason) but peer B registered it → all subsequent
    -- power_up names land on different ids → `Table deus_power_up_templates
    -- does not contain key: N` fatal in network_lookup.lua's strict __index
    -- when peer B's rpc_add_buff reaches peer A. Crash dumps 2026-05-19
    -- 02:59:56 + 03:08:36 (key 177 on the client side).
    --
    -- Same shape as the v0.8.66-dev LA fix: deterministic name registration
    -- decouples NetworkLookup indices from runtime-dependent state, and the
    -- gated content writes (templates / dpubt / buff_templates) remain
    -- idempotent early-outs in the gated register_trait_boon below.
    for _, spec in ipairs(sorted) do
        register_power_up_in_network_lookup(spec.name)
        local buff_name = "power_up_" .. spec.name .. "_" .. spec.rarity
        register_buff_in_network_lookup(buff_name)
    end
    local count, placeholder_count = 0, 0
    for _, spec in ipairs(sorted) do
        -- #464: a spec may carry `literal_buffs` (a fixed buff array) instead of a
        -- `source_buff` to clone - used when the source template is runtime-mutable
        -- (see the ct_boon_anath_raema_swiftness spec comment above). The clone loop
        -- below copies each sub-buff, so the spec's literal stays pristine.
        local source_template = spec.literal_buffs and { buffs = spec.literal_buffs }
            or buff_templates[spec.source_buff]
        -- v0.7.67 hardening (QA-found): write a `templates[spec.name]` entry
        -- UNCONDITIONALLY in sorted order so `inject_dormant_boon` below doesn't
        -- early-out on missing template — if it did, `DeusPowerUpsLookup` would
        -- drift across peers (the exact bug class this refactor targets). When
        -- the source buff is missing on a peer, we ship a placeholder template
        -- with an empty buff array. The boon won't FUNCTION gameplay-wise on
        -- that peer, but its lookup_id will align with peers that do have it —
        -- so rpc_add_buff dispatches still resolve to the correct boon name and
        -- the run doesn't crash. Today all four source buffs (always_blocking,
        -- deus_crit_chain_lightning, deus_extra_shot,
        -- deus_collateral_damage_on_melee_killing_blow) are vanilla and always
        -- present, but this hardening guards against future DLC-gated source
        -- buffs that could differ across peers.
        if not templates[spec.name] then
            local cloned_buffs = {}
            if source_template and source_template.buffs then
                for i, sub in ipairs(source_template.buffs) do
                    cloned_buffs[i] = table.clone(sub)
                end
            else
                placeholder_count = placeholder_count + 1
                _dbg("[trait-boon] %s: source buff '%s' missing — using empty placeholder buffs (boon non-functional on this peer but lookup_id stays aligned)",
                    spec.name, tostring(spec.source_buff))
                -- Single placeholder buff with the correct name field so
                -- inject_dormant_boon's `buff_template.buffs[1].name = buff_name`
                -- assignment doesn't nil-crash.
                cloned_buffs[1] = { name = "placeholder" }
            end
            -- #144: repoint Vaul's Anvil's controller sub-buff to ct's self-healing reconciler
            -- (mod._ct_vauls_anvil_reconcile). Vanilla always_blocking_update only re-applies the
            -- perk reactively -- via block-broken lockout recovery and an ORPHANED weapon-swap
            -- trigger (always_blocking_weapon_swap, morris_buff_settings.lua:3093, which nothing in
            -- the engine ever fires) -- so once deus_always_blocking_buff is dropped by equip/wield
            -- churn it can stay off (the "stops working after an equip action" report). The
            -- reconciler is authoritative every frame: perk present IFF melee wielded AND not
            -- lockout. Matched by the perk field so array order is irrelevant; only repointed when
            -- the function is confirmed registered (see _ct_reconciler_ready) so the buff never
            -- names an unregistered update_func.
            if spec.name == "ct_boon_vauls_anvil" and _ct_reconciler_ready then
                for _, sub in ipairs(cloned_buffs) do
                    if type(sub) == "table" and sub.buff_to_add == "deus_always_blocking_buff"
                        and sub.update_func == "always_blocking_update" then
                        sub.update_func = "ct_vauls_anvil_reconcile"
                    end
                end
            end
            templates[spec.name] = {
                advanced_description = "description_" .. spec.name,
                display_name         = "display_name_" .. spec.name,
                icon                 = spec.icon,
                max_amount           = 1,
                rectangular_icon     = true,
                buff_template        = { buffs = cloned_buffs },
                description_values   = {},
            }
        end
        local buff_name = "power_up_" .. spec.name .. "_" .. spec.rarity
        local buff_template = table.clone(templates[spec.name].buff_template)
        buff_template.buffs[1].name = buff_name
        dpubt[buff_name] = buff_template
        buff_templates[buff_name] = buff_template
        -- Full registration (NetworkLookup IDs, DeusPowerUps / Array / Lookup,
        -- buff template tables) — UNCONDITIONAL so every peer's
        -- DeusPowerUpsLookup ordering matches regardless of source-buff
        -- availability. Pool insert is gated separately in register_trait_boon.
        inject_dormant_boon(spec.name, spec.rarity)
        count = count + 1
    end
    _dbg("[trait-boon] pre-registered %d trait boons for client compat (%d using placeholder buffs)",
        count, placeholder_count)
end

pre_register_trait_boon_lookups()

for _, spec in ipairs(CT_TRAIT_BOONS) do
    register_trait_boon(spec)
end

-- Assignment to the forward-declared `sync_host_dependent_state` (see top of file).
-- Called by the ct_sync_host_settings RPC handler immediately after a client
-- receives the host's settings payload, so any template/pool mutations gated on
-- a synced setting are reapplied with the host's values. Apply order mirrors the
-- one-shot calls each sync_* function does at module load.
sync_host_dependent_state = function()
    sync_reckless_swings()
    sync_bomb_cooldown()
    sync_boon_movespeed()
    sync_poison_proof_tweak()
    sync_invis_potion_tweak()
    sync_moot_milk_alt_tweak()
    sync_shard_strike()
    sync_anath_raema_permanent()
    -- User-suggestion mechanic tweaks live in _ct_mechanic_tweaks.lua (own chunk to
    -- stay under the 200-local main-chunk cap); re-applied here on host-settings receipt.
    if mod._ct_sync_shadow_skull_stun then mod._ct_sync_shadow_skull_stun() end
    if mod._ct_sync_miasma then mod._ct_sync_miasma() end
    -- 2026-05-23 v0.7.100-dev FULLY PURGED: sync_dormant_boons() — function no longer
    -- exists (block-commented along with DORMANT_BOON_RARITY). Re-enable alongside the
    -- L4721-style apply-site uncomment.
    for _, spec in ipairs(CT_TRAIT_BOONS) do
        register_trait_boon(spec)
    end
end

-- v0.7.240-dev (#406): ct_kill_heal RE-ENABLED. It was block-commented in v0.7.98-dev
-- (user request after a Chest-of-Trials crash); the user's issue-406 verify comment now
-- explicitly requires it selectable as a starting boon ("This boon is missing from
-- selectable starting boons... Fix that first"), and the two hazards that motivated the
-- removal are both addressed: the client heal fassert is gated (is_server gate below,
-- issue 406) and modded-boon wire exposure is peer-parity gated (issue 426 wire-safety
-- block below). Every peer on v0.7.240-dev re-registers the name identically, so the
-- lookup-order invariant (feedback_vt2_gated_registration_diverges) holds the same way
-- it did for the removal. The matching VMF widget line is catalogued once in
-- `_data.lua` BOON_TREE > mod_boons; both Disabled Boons and Starting Boons derive
-- from that one row. The kill_heal regression check is restored in the same version.
do
    -- v0.7.63-alpha: register NetworkLookup names FIRST, unconditionally, BEFORE
    -- the globals-ready gate. Two peers running the same ct version must always
    -- assign the same sequential index to "ct_kill_heal" regardless of whether
    -- their `DeusPowerUpTemplates` / `BuffFunctionTemplates` globals happened to
    -- be loaded at module-init time on each peer. Same fix pattern as
    -- pre_register_trait_boon_lookups: name registration decoupled from
    -- template construction so the lookup ids stay deterministic across peers.
    register_power_up_in_network_lookup("ct_kill_heal")
    register_buff_in_network_lookup("power_up_ct_kill_heal_exotic")

    local power_ups  = rawget(_G, "DeusPowerUpTemplates")
    local buff_funcs = rawget(_G, "BuffFunctionTemplates")

    if power_ups and buff_funcs and buff_funcs.functions then
        local CT_KILL_HEAL_AMOUNT = 1
        local _ct406_heal_diag_count = 0
        local CT406_HEAL_DIAG_CAP = 12
        local function _ct406_log_heal(result, unit, amount, before_hp, after_hp)
            if _ct406_heal_diag_count >= CT406_HEAL_DIAG_CAP then return end
            _ct406_heal_diag_count = _ct406_heal_diag_count + 1
            pcall(printf, "[ct:406] kill_heal result=%s server=%s alive=%s amount=%s hp_before=%s hp_after=%s count=%d/%d",
                tostring(result),
                tostring(Managers and Managers.player and Managers.player.is_server),
                tostring(ALIVE and ALIVE[unit]),
                tostring(amount),
                tostring(before_hp),
                tostring(after_hp),
                _ct406_heal_diag_count,
                CT406_HEAL_DIAG_CAP)
        end

        -- v0.7.295-dev (#406): restore a visible 1 permanent-green HP per kill
        -- and keep a bounded diagnostic receipt. The important vanilla constraint
        -- remains the heal_type: `health_regen` is in
        -- GenericStatusExtension.is_permanent_heal(), while the older
        -- `heal_from_proc` path becomes temporary health. The buff template itself
        -- has `authority = "server"`; this explicit gate keeps older hook paths
        -- from tripping DamageUtils.heal_network's "Only server can heal" fassert.
        buff_funcs.functions.ct_kill_heal_on_kill = function(unit, buff, params)
            -- Issue 406: heal_network fasserts "Only server can heal" on
            -- clients (damage_utils.lua:2636) - a CLIENT taking this boon
            -- crashed on their next kill (same class as crt issue 405).
            -- Vanilla gate per buff_templates.lua:325/:404: the client
            -- instance no-ops; the host's instance of the synced buff
            -- grants the heal.
            if not (Managers and Managers.player and Managers.player.is_server) then
                _ct406_log_heal("skip-client", unit, CT_KILL_HEAL_AMOUNT, nil, nil)
                return
            end
            if not (ALIVE and ALIVE[unit]) then
                _ct406_log_heal("skip-dead-unit", unit, CT_KILL_HEAL_AMOUNT, nil, nil)
                return
            end

            local before_hp = nil
            local after_hp = nil
            local health_extension = ScriptUnit and ScriptUnit.has_extension and ScriptUnit.has_extension(unit, "health_system")
            if health_extension and health_extension.current_permanent_health then
                local ok, value = pcall(function() return health_extension:current_permanent_health() end)
                if ok then before_hp = value end
            end

            DamageUtils.heal_network(unit, unit, CT_KILL_HEAL_AMOUNT, "health_regen")

            if health_extension and health_extension.current_permanent_health then
                local ok, value = pcall(function() return health_extension:current_permanent_health() end)
                if ok then after_hp = value end
            end
            _ct406_log_heal("healed", unit, CT_KILL_HEAL_AMOUNT, before_hp, after_hp)
        end

        power_ups.ct_kill_heal = {
            advanced_description = "description_ct_kill_heal",
            display_name         = "display_name_ct_kill_heal",
            icon                 = "deus_icon_meta_01",  -- placeholder; future: dedicated heal-on-kill icon
            max_amount           = 1,
            rectangular_icon     = true,
            buff_template = {
                buffs = {
                    {
                        authority = "server",
                        buff_func = "ct_kill_heal_on_kill",
                        event     = "on_kill",
                        name      = "ct_kill_heal",
                    },
                },
            },
            description_values = {},
        }

        inject_dormant_boon("ct_kill_heal", "exotic")
        _add_dormant_to_pool("ct_kill_heal", "exotic")
        pcall(printf, "[ct:406] ct_kill_heal re-enabled at rarity exotic (is_server heal gate active; pool membership peer-parity gated per issue 426)")
    else
        _dbg("[mod-boon] DeusPowerUpTemplates / BuffFunctionTemplates not ready for ct_kill_heal — NetworkLookup name reserved, template construction deferred")
    end
end

do
    local install_peer_parity_owner = mod:dofile(
        "scripts/mods/chaos_wastes_tweaker_dev/_ct_peer_parity_owner")
    if type(install_peer_parity_owner) ~= "function" then
        error("[ct:peer-parity-owner] owner did not return an installer")
    end
    if install_peer_parity_owner(mod, {
        rt_register = _rt_register,
        collect_setting_ids = _collect_setting_ids,
        rpc_schema = CT_RPC_SCHEMA,
        add_dormant_to_pool = _add_dormant_to_pool,
        remove_dormant_from_pool = _remove_dormant_from_pool,
        injected_dormants = _injected_dormants,
        trait_boons = CT_TRAIT_BOONS,
        register_trait_boon = register_trait_boon,
    }) ~= true then
        error("[ct:peer-parity-owner] owner did not confirm synchronous install")
    end
end

_rt_register("issue406_kill_heal_mod_boon_catalog", function()
    -- `ct_kill_heal` is one CT-authored DeusPowerUpTemplates entry. BOON_TREE
    -- is only a menu catalog; moving its single row must expose the existing
    -- definition on both generated surfaces without cloning the boon itself.
    local templates = rawget(_G, "DeusPowerUpTemplates")
    if type(templates) ~= "table" or type(rawget(templates, "ct_kill_heal")) ~= "table" then
        return "skip: canonical DeusPowerUpTemplates.ct_kill_heal definition missing (run in keep)"
    end

    local ok, data = pcall(mod.dofile, mod,
        "scripts/mods/chaos_wastes_tweaker_dev/chaos_wastes_tweaker_dev_data")
    if not ok or type(data) ~= "table" then return "could not load realized CT widget catalog" end

    local targets = {
        disable_boon_ct_kill_heal = "disable_boon_mod_boons_group",
        start_boon_ct_kill_heal = "start_boon_mod_boons_group",
    }
    local found = {}
    local function walk(node, parent_id)
        if type(node) ~= "table" then return end
        local id = node.setting_id
        if targets[id] then
            found[id] = found[id] or {}
            found[id][#found[id] + 1] = parent_id
        end
        local next_parent = (node.type == "group" and id) or parent_id
        for _, field in ipairs({ "widgets", "sub_widgets" }) do
            for _, child in ipairs(node[field] or {}) do walk(child, next_parent) end
        end
    end
    walk(data.options, nil)

    for setting_id, expected_parent in pairs(targets) do
        local parents = found[setting_id] or {}
        if #parents ~= 1 then
            return string.format("%s occurs %d times; expected one BOON_TREE-derived widget",
                setting_id, #parents)
        end
        if parents[1] ~= expected_parent then
            return string.format("%s catalogued under %s, expected Mod Boons parent %s",
                setting_id, tostring(parents[1]), expected_parent)
        end
    end
    -- #406 follow-up: structural presence was already correct in v0.7.264, but
    -- the realized category still called itself "New Scaling Boons". That is a
    -- discoverability failure for a non-scaling heal boon. Lock the actual
    -- player-facing route, not only the invisible setting-id ancestry.
    local start_group = mod:localize("start_boon_mod_boons_group")
    local disable_group = mod:localize("disable_boon_mod_boons_group")
    local start_item = mod:localize("start_boon_ct_kill_heal")
    if not tostring(start_group):find("Starting Boons: Modded Boons", 1, true) then
        return "#406 start category is not player-visible as Starting Boons: Modded Boons"
    end
    if not tostring(disable_group):find("Disable Boons: Modded Boons", 1, true) then
        return "#406 disable category is not player-visible as Disable Boons: Modded Boons"
    end
    if not tostring(start_item):find("Khaine's Communion", 1, true) then
        return "#406 starting widget lost the player-facing Khaine's Communion name"
    end
end)

_rt_register("anath_raema_registry_retry_288", function()
    if CT_ANATH_RAEMA_RETRY_MARKER ~= "anath_raema:enforce_at_add_buff_v0.7.268" then
        return "exact add-boundary retry marker missing"
    end
    if not effective_setting("tweak_anath_raema_permanent") then
        return nil -- behavior assertions apply only when the rework is intentionally enabled
    end
    apply_anath_raema_permanent_tweak()
    local entries = _anath_raema_buff_entries()
    -- #1156: both registries only exist keep-side. Mid-mission this used to score FAIL against
    -- healthy code (2026-08-04 log); the context is not something the check can control, so it
    -- skips rather than accusing the tweak of being broken.
    if #entries ~= 2 then return "skip: WeaponTraits + BuffTemplates registries are keep-only (run in-keep)" end
    if not (balance.get_anath_raema_originals() and balance.get_anath_raema_originals().templates.weapon_traits
            and balance.get_anath_raema_originals().templates.buff_templates) then
        return "two registries must preserve independent originals"
    end
    for _, e in ipairs(entries) do
        local sb = e.tbl[e.key] and e.tbl[e.key].buffs and e.tbl[e.key].buffs[1]
        if not sb or sb.name ~= "deus_ammo_pickup_reload_speed_permanent"
                or sb.stat_buff ~= "reload_speed" or sb.multiplier ~= -0.5 or sb.event ~= nil then
            return e.id .. " did not resolve to the permanent -0.5 reload template"
        end
    end
    return nil
end)

-- #464 follow-up: Anath Raema's Swiftness trait-as-boon must (a) be registered as a
-- power-up, (b) carry the PERMANENT reload template with a NEGATIVE reload_speed
-- multiplier (inverse stat - the #464 sign-error class), and (c) be exposed in BOTH
-- boon menu surfaces (the report: user could not find it under Offensive > Ranged in
-- either the Disabled Boons or Starting Boons trees).
_rt_register("anath_raema_trait_boon_464", function()
    local f = mod._ct_is_modded_power_up
    if type(f) ~= "function" or not f("ct_boon_anath_raema_swiftness") then
        return "ct_boon_anath_raema_swiftness must be in the modded registry"
    end
    local tpl = rawget(_G, "DeusPowerUpTemplates")
    local t = tpl and tpl.ct_boon_anath_raema_swiftness
    local b = t and t.buff_template and t.buff_template.buffs and t.buff_template.buffs[1]
    if not b then return "DeusPowerUpTemplates.ct_boon_anath_raema_swiftness buff template missing" end
    if b.stat_buff ~= "reload_speed" then return "boon buff must be a reload_speed stat_buff" end
    if type(b.multiplier) ~= "number" or b.multiplier >= 0 then
        return "reload_speed multiplier must be NEGATIVE (inverse stat; positive = SLOWER reload, the #464 bug)"
    end
    -- Menu exposure: walk the REALIZED widget tree (same source _ct_dump_settings uses)
    -- so a BOON_TREE regression that drops the entry fails here, not in the field.
    local ids_ok, ids = pcall(_collect_setting_ids)
    if not ids_ok or type(ids) ~= "table" then return "could not collect widget setting ids" end
    local have = {}
    for _, id in ipairs(ids) do have[id] = true end
    if not have["disable_boon_ct_boon_anath_raema_swiftness"] then
        return "disable_boon_ct_boon_anath_raema_swiftness widget missing (Disabled Boons > Offensive > Ranged)"
    end
    if not have["start_boon_ct_boon_anath_raema_swiftness"] then
        return "start_boon_ct_boon_anath_raema_swiftness widget missing (Starting Boons > Offensive > Ranged)"
    end
    if not have["enable_boon_anath_raema_swiftness"] then
        return "enable_boon_anath_raema_swiftness widget missing (Reworks > Reworks: Boons > new)"
    end
    return nil
end)

-- ============================================================
-- Home Brewer +50% potency for reworked potions (v0.7.31-alpha)
-- ============================================================
-- When the toggle is on AND the player has Home Brewer (the boon that grants the
-- `not_consume_potion` perk), the reworked Moot Milk potion's numerical multipliers are
-- scaled by 1.5x for that specific drink. Implementation: hook BuffExtension.add_buff,
-- save the template's multiplier/bonus fields, scale, call vanilla add, restore.
--
-- Only scales `moot_milk_potion` and `moot_milk_potion_increased` (the reworked variants)
-- — `poison_proof_potion` has binary immunity with no multiplier field, so potency is
-- moot for it. Duration is intentionally NOT scaled (Decanter is the duration lever;
-- Home Brewer is the potency lever — they remain orthogonal).
--
-- LIMITATIONS:
-- * RACE: BuffTemplates is shared global; two players drinking simultaneously could see
--   one peer's scaled values briefly. Rare in practice (potion drinks are individual)
--   and the effect is just stat values, not safety-critical.
-- * No NetworkLookup variant registration — multiplayer-safe because every peer
--   applies its own buff (with its own perk check) via this hook.
local HOME_BREWER_BREWED_TEMPLATES = {
    moot_milk_potion           = true,
    moot_milk_potion_increased = true,
}

-- v0.7.203-dev multi-return marker: the Home Brewer add_buff hook's guarded
-- (scaled-potency) path forwards ALL of vanilla's returns (id, sub_buffs_added,
-- first_buff) via _capture_returns + unpack(results, 1, n), NOT a collapsing
-- `local result = func(...); return result`. Global (not a main-chunk local) to
-- dodge the Lua 5.1 200-local cap. Asserted by /ct_regression_test
-- "home_brewer_add_buff_multireturn_preserved".
CT_HOME_BREWER_MULTIRETURN_MARKER = "home_brewer_add_buff:capture_returns_unpack_v0.7.203"

mod:hook("BuffExtension", "add_buff", function(func, self, template_name, params)
    -- Issue #288: mod load can precede one or both Morris registries. Enforce at
    -- the exact native lookup boundary so startup timing cannot retain the event buff.
    if template_name == "deus_ammo_pickup_reload_speed" and effective_setting("tweak_anath_raema_permanent") then
        apply_anath_raema_permanent_tweak()
        CT_ANATH_RAEMA_ADD_DIAG_COUNT = (CT_ANATH_RAEMA_ADD_DIAG_COUNT or 0) + 1
        if CT_ANATH_RAEMA_ADD_DIAG_COUNT <= 8 then
            local bt = rawget(_G, "BuffTemplates")
            local sb = bt and bt[template_name] and bt[template_name].buffs and bt[template_name].buffs[1]
            pcall(printf, "[ct:288] add parent=%s child=%s stat=%s mult=%s event=%s n=%d",
                tostring(template_name), tostring(sb and sb.name), tostring(sb and sb.stat_buff),
                tostring(sb and sb.multiplier), tostring(sb and sb.event), CT_ANATH_RAEMA_ADD_DIAG_COUNT)
        end
    end
    if not effective_setting("tweak_home_brewer_potency") then
        return func(self, template_name, params)
    end
    if not (type(template_name) == "string" and HOME_BREWER_BREWED_TEMPLATES[template_name]) then
        return func(self, template_name, params)
    end
    if not self.has_buff_perk or not self:has_buff_perk("not_consume_potion") then
        return func(self, template_name, params)
    end
    local bt = rawget(_G, "BuffTemplates")
    local sub_buffs = bt and bt[template_name] and bt[template_name].buffs
    if not sub_buffs then
        return func(self, template_name, params)
    end
    local saved = {}
    for i, sb in ipairs(sub_buffs) do
        if sb.multiplier or sb.bonus then
            saved[i] = { multiplier = sb.multiplier, bonus = sb.bonus }
            if sb.multiplier then sb.multiplier = sb.multiplier * 1.5 end
            if sb.bonus      then sb.bonus      = sb.bonus      * 1.5 end
        end
    end
    -- v0.7.203-dev: vanilla BuffExtension.add_buff returns THREE values
    -- (id, sub_buffs_added, first_buff — buff_extension.lua:517). The prior
    -- `local result = func(...)` / `return result` collapsed that to the first
    -- return, dropping sub_buffs_added + first_buff for any caller that reads them
    -- (VMF_RECIPES §2/§2a). Capture the real arity and forward every return;
    -- restore the scaled sub-buff fields in between. Marker
    -- CT_HOME_BREWER_MULTIRETURN_MARKER documents this fix for the regression check.
    local n, results = _capture_returns(func(self, template_name, params))
    for i, s in pairs(saved) do
        sub_buffs[i].multiplier = s.multiplier
        sub_buffs[i].bonus      = s.bonus
    end
    return unpack(results, 1, n)
end)

-- ============================================================
-- Endless Bombs: strip the LEFTOVER Morgrim's when the potion ENDS
-- ============================================================
-- Intent (user, 2026-06-28): Endless Bombs (pockets_full_of_bombs) is SUPPOSED to work with
-- Morgrim's Bomb (holy_hand_grenade) — players deliberately save a Morgrim's to throw during the
-- potion, and that's fine/desired. The ONLY exploit: if you don't throw your last Morgrim's
-- before the potion expires, it persists (effectively duplicated) so you carry it to the next
-- potion and do it again. So we do NOT eat the bomb on drink or mid-potion (v0.7.178/.179 did —
-- WRONG, that broke the intended combo). We strip the LEFTOVER Morgrim's only when the potion
-- EXPIRES, and only if the player drank it while holding one.
--
-- Mechanism: pockets_full_of_bombs_potion(_increased) declares
-- remove_buff_func = "remove_deus_potion_buff" (morris_buff_settings.lua), which fires on
-- duration expiry. That remove func is SHARED by every deus potion, so we gate on a flag
-- (buff.ct_endless_had_morgrim) that ONLY the pockets apply-hook sets — no buff-name match
-- needed, and other potions are unaffected. The buff instance persists fields across
-- apply/update/remove (vanilla itself stores buff.previous_multiplier), so the flag survives to
-- expiry. Hook target is the merged BuffFunctionTemplates.functions table; guard for load order.
-- #101 regression sentinel (v0.7.181-dev): the consume must be on EXPIRY (remove_deus_potion_buff)
-- via the buff.ct_endless_had_morgrim flag — NOT a consume-on-drink (v0.7.178) or continuous
-- mid-potion eat (v0.7.179), both of which broke the intended potion+Morgrim's combo. Global to
-- dodge the 200-local cap. Asserted by /ct_regression_test "endless_bombs_strip_on_expiry".
CT_ENDLESS_BOMBS_MARKER = "endless_bombs:strip_leftover_morgrim_on_expiry_v0.7.181"
if BuffFunctionTemplates and BuffFunctionTemplates.functions then
    -- At DRINK: only RECORD whether the player held a Morgrim's (do NOT consume it — it must stay
    -- usable during the potion). Morgrim's lives in slot_grenade (deus_blessing_settings.lua:85).
    mod:hook(BuffFunctionTemplates.functions, "apply_pockets_full_of_bombs_buff", function(func, unit, buff, params)
        if effective_setting("endless_bombs_consumes_morgrim") == true then
            local inv = ScriptUnit.has_extension(unit, "inventory_system")
            local sd = inv and inv:get_slot_data("slot_grenade")
            local nm = sd and sd.item_data and sd.item_data.name
            if nm == "holy_hand_grenade" then
                buff.ct_endless_had_morgrim = true
            end
            -- printf, NOT mod:info (user runs VMF mod-logging OFF).
            pcall(printf, "[endless-bombs] drink: grenade=%s had_morgrim=%s (kept for the potion; stripped on expiry)",
                tostring(nm or "<none>"), tostring(buff.ct_endless_had_morgrim == true))
        end
        return func(unit, buff, params)
    end)

    -- At EXPIRY: if they drank with a Morgrim's AND a leftover one is still in slot_grenade, strip
    -- it (kills the un-thrown-duplicate carry-over). Flag-gated -> other deus potions untouched.
    mod:hook(BuffFunctionTemplates.functions, "remove_deus_potion_buff", function(func, unit, buff, params, world)
        local result = func(unit, buff, params, world)
        if buff and buff.ct_endless_had_morgrim and effective_setting("endless_bombs_consumes_morgrim") == true then
            local inv = ScriptUnit.has_extension(unit, "inventory_system")
            local sd = inv and inv:get_slot_data("slot_grenade")
            local nm = sd and sd.item_data and sd.item_data.name
            if nm == "holy_hand_grenade" then
                -- If the player is actively wielding the bomb when it's stripped, destroying the
                -- slot leaves them stuck in the bomb/throw pose on a now-empty slot, unable to
                -- switch weapons. Capture the wielded slot BEFORE destroying; if it was the
                -- grenade, interrupt the weapon action and wield melee (slot 1) so they recover.
                local was_wielding = inv.get_wielded_slot_name and inv:get_wielded_slot_name()
                inv:destroy_slot("slot_grenade")
                if was_wielding == "slot_grenade" then
                    if rawget(_G, "CharacterStateHelper") then
                        pcall(CharacterStateHelper.stop_weapon_actions, inv, "dropped")
                    end
                    pcall(function() inv:wield("slot_melee") end)
                end
                pcall(printf, "[endless-bombs] potion ended -> stripped leftover Morgrim's%s",
                    (was_wielding == "slot_grenade") and " (was wielding it -> swapped to melee)" or "")
            else
                pcall(printf, "[endless-bombs] potion ended; no leftover Morgrim's (grenade=%s)", tostring(nm or "<empty>"))
            end
        end
        return result
    end)

end
return {
    sync_host_dependent_state = sync_host_dependent_state,
    trait_boons = CT_TRAIT_BOONS,
    register_trait_boon = register_trait_boon,
}
