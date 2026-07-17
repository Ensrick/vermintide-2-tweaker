-- _ct_boon_registry.lua — Boon lookup, dormant, Skulls, and miracle registration.
--
-- Owns deterministic NetworkLookup/template registration, rarity-pool helpers,
-- disabled dormant/Skulls scaffolding, and the Miracle of Ulric/Isha hooks.
-- Loaded after boon balance and before meta/trait boon consumers.
--
-- Owned by: chaos_wastes_tweaker_dev.lua. Consumed via: one mod:dofile call.

local mod = get_mod("ct_dev")
local context = mod._ct_boon_runtime_context
if type(context) ~= "table" then
    error("[ct:boon-runtime] missing entry-point context")
end
local _dbg = context.dbg
local effective_setting = context.effective_setting
local MOD_VERSION = context.mod_version
local REAL_PLAYER_LOCAL_ID = context.real_player_local_id
local _ct_mutex = context.mutex
-- ============================================================
-- Activate Dormant Boons (v0.7.29-alpha)
-- ============================================================
-- 9 boons defined in vanilla `DeusPowerUpTemplates` but NOT registered in
-- `DeusPowerUpRarityPool` — they can never roll in the active CW loot pool. Each has an
-- `activate_dormant_<boon>` toggle. When on, the boon is injected into the rarity pool
-- (and all derived tables: DeusPowerUps, DeusPowerUpsArray, DeusPowerUpsArrayByRarity,
-- DeusPowerUpsLookup, DeusPowerUpBuffTemplates) using the same construction pattern as
-- vanilla's registration loop at `deus_power_up_settings.lua:7121-7176`.
--
-- LIMITATIONS:
-- * Additive only — toggling OFF doesn't remove the boon from the active run; would
--   require a game restart to fully clear. The injection takes effect on the next CW
--   run setup (since the engine reads the pool at run start).
-- * Per-boon rarity is fixed; user can't currently choose a different rarity for a
--   given dormant boon. Defaults are sensible (powerful boons → exotic, weaker → rare).
-- IMPORTANT: vanilla boon rarities are { event, rare, exotic, unique } ONLY (see
-- deus_power_up_settings.lua:7032 `DeusPowerUpRarities`). "common" / "plentiful" are
-- weapon-drop rarities and do NOT exist for boons. `existing_power_ups_lut` is keyed
-- off DeusPowerUpRarities — injecting at a non-listed rarity crashes
-- `deus_power_up_utils.lua:189` when the boon ends up in `existing_power_ups`.
-- v0.7.37 fix: squats and deus_larger_clip moved from "common" → "rare".
-- 2026-05-23 v0.7.100-dev FULLY PURGED: dormant boons removed per user request after recurring
-- Chest-of-Trials crashes. The `DORMANT_BOON_RARITY` table is GONE (not even an empty {}), and
-- every active reference to it has been purged from the file. To re-enable: restore the table
-- below, uncomment the apply-site calls at the bottom of this section
-- (pre_register_dormant_lookups + sync_dormant_boons), restore the `_should_strip` dormant
-- branch in the generate_random_power_ups hook (~L1146), restore the boon-trace hook dormant
-- fields (~L3440), restore the `/verify_dormants` chat command (~L3670), restore the
-- DORMANT_BOON_RARITY references in `deus_rarities_valid` regression check (~L7180), and
-- restore the regression checks `dormant_boons_preregistered` + `dormant_buff_dual_registered`
-- + `kill_heal_uses_permanent_heal_type` + `skulls_boons_preregistered`.
--
-- TODO(squats) — when re-enabling, promote `squats` to "unique" rarity and
-- give it the following effect: on crouch action, grant 15 seconds of
-- invisibility, with a 3-minute cooldown. (User spec 2026-05-23.) Needs:
-- (1) hook the crouch input on PlayerUnitFirstPerson (or wherever the
-- crouch press is observed) — gate per-player so only the boon-holder fires;
-- (2) apply the existing `invisibility` buff template for 15s; (3) per-buff
-- cooldown via mod-side timestamp keyed on player_unit. Vanilla `squats`
-- has no defined effect in DeusPowerUpBuffTemplates today, so this is a
-- ct-authored buff body.
--[[
local DORMANT_BOON_RARITY = {
    deus_ammo_pickup_give_allies_ammo    = "rare",
    deus_coin_pickup_regen               = "rare",
    deus_large_ammo_pickup_infinite_ammo = "exotic",
    deus_larger_clip                     = "rare",   -- v0.7.37 was "common", crashed
    deus_throw_speed_increase            = "rare",
    deus_timed_block_free_shot           = "exotic",
    deus_transmute_into_coins            = "rare",
    explosive_pushes_on_damage_taken     = "exotic",
    squats                               = "unique", -- TODO(squats): 15s invisibility on crouch, 3min cooldown
}
--]]

-- _injected_dormants and _added_to_pool stay because the meta boons (CT_META_BOONS at
-- ~L5500) and trait boons (CT_TRAIT_BOONS at ~L5750) still legitimately call
-- inject_dormant_boon / _add_dormant_to_pool — those functions are generic boon
-- injectors; only their HISTORICAL NAME mentions "dormant." They do not touch
-- DORMANT_BOON_RARITY directly.
local _injected_dormants = {}

-- v0.7.38/v0.7.40: Register a name in a NetworkLookup table. Vanilla builds these
-- lookups at boot from their backing global tables (BuffTemplates,
-- DeusPowerUpTemplates, etc.). Entries we add post-boot are NOT in the lookups, and
-- the lookup's __index metatable errors on unknown keys (network_lookup.lua:2354).
-- Append index→name and set the reverse name→index. rawget bypasses the
-- error-on-unknown-key metatable when checking for existing registration.
local function _register_in_network_lookup(lookup_key, name)
    if type(name) ~= "string" then return end
    local nl = rawget(_G, "NetworkLookup")
    local t = nl and nl[lookup_key]
    if not t then return end
    if rawget(t, name) then return end
    local idx = #t + 1
    t[idx] = name
    t[name] = idx
end
local function register_buff_in_network_lookup(buff_name)
    _register_in_network_lookup("buff_templates", buff_name)
end

local function register_power_up_in_network_lookup(power_up_name)
    _register_in_network_lookup("deus_power_up_templates", power_up_name)
end

local function inject_dormant_boon(power_up_name, rarity)
    if _injected_dormants[power_up_name] then return end

    -- v0.7.40: Register in NetworkLookup.deus_power_up_templates immediately. Vanilla
    -- code at deus_run_state_spec.lua:60, deus_run_controller.lua:1198 (and similar)
    -- looks up the power-up by name. Without registration the lookup errors when the
    -- player selects this boon at a chest (Crashify guid 9f697495 — burned in v0.7.39).
    register_power_up_in_network_lookup(power_up_name)

    -- v0.7.67: `DeusPowerUpRarityPool` (the pool table) is no longer read here —
    -- pool insertion moved to `_add_dormant_to_pool` below. Other globals stay.
    local templates        = rawget(_G, "DeusPowerUpTemplates")
    local power_ups        = rawget(_G, "DeusPowerUps")
    local array            = rawget(_G, "DeusPowerUpsArray")
    local array_by_rarity  = rawget(_G, "DeusPowerUpsArrayByRarity")
    local lookup           = rawget(_G, "DeusPowerUpsLookup")
    local buff_templates   = rawget(_G, "DeusPowerUpBuffTemplates")
    local settings         = rawget(_G, "DeusPowerUpSettings")
    local availability_t   = rawget(_G, "DeusPowerUpAvailabilityTypes")
    local tweak_data_glob  = rawget(_G, "MorrisBuffTweakData")

    if not (templates and power_ups and array and array_by_rarity and lookup and buff_templates) then
        _dbg("[dormant] DeusPowerUp* tables not loaded yet; skipping injection of " .. tostring(power_up_name))
        return
    end

    local template = templates[power_up_name]
    if not template then
        _dbg("[dormant] template not found for " .. tostring(power_up_name))
        return
    end

    local availability = (availability_t and {
        availability_t.cursed_chest,
        availability_t.weapon_chest,
        availability_t.shrine,
    }) or {}

    -- v0.7.67 split: the rarity-pool insert is no longer done here. It moved into
    -- `_add_dormant_to_pool` below, called separately and gated by the user's
    -- toggle. This function (`inject_dormant_boon`) now does all the network-
    -- relevant registration UNCONDITIONALLY at mod-load — `DeusPowerUpsLookup`,
    -- `DeusPowerUpsArray`, `DeusPowerUpsArrayByRarity`, `DeusPowerUps`,
    -- `NetworkLookup.deus_power_up_templates`, `NetworkLookup.buff_templates`,
    -- `BuffTemplates`, `DeusPowerUpBuffTemplates`. Same set of indices across
    -- every peer regardless of which `activate_dormant_*` or `enable_boon_*`
    -- toggles each has on. Only `DeusPowerUpRarityPool` (which determines what
    -- a peer actually has the *option* to roll) stays toggle-gated.
    --
    -- Why this matters: `DeusPowerUpsLookup[boon_id]` is indexed by an integer
    -- RPC parameter (deus_mechanism.lua:1256). If host's lookup table is
    -- ordered differently from client's, host's rpc_add_buff(id=N) resolves to
    -- a DIFFERENT boon on the client. Pre-0.7.67 the gate at the pool-insert
    -- was applied to the entire `inject_dormant_boon` call, so `deus_larger_clip`
    -- (and the other 8 dormants + 11 trait boons + ct_meta_movespeed +
    -- ct_kill_heal) appeared in the lookup table only on peers with their toggle
    -- on, drifting every subsequent boon's id by +1 per absent dormant.
    -- Burned ct v0.7.66 (same class as v0.7.59 / v0.7.60).

    -- Build the new_power_up record (mirrors vanilla deus_power_up_settings.lua:7121-7176).
    local new_power_up = {}
    new_power_up.name           = power_up_name
    new_power_up.rarity         = rarity
    new_power_up.mutators       = {}
    new_power_up.availability   = availability
    new_power_up.max_amount     = template.max_amount or 1
    new_power_up.incompatibility = template.incompatibility
    new_power_up.weight         = template.weight or (settings and settings.weight_by_rarity and settings.weight_by_rarity[rarity]) or 1

    if template.talent then
        new_power_up.talent       = true
        new_power_up.talent_tier  = template.talent_tier
        new_power_up.talent_index = template.talent_index
    else
        new_power_up.display_name        = template.display_name
        new_power_up.plain_display_name  = template.plain_display_name
        new_power_up.buff_name           = "power_up_" .. power_up_name .. "_" .. rarity
        new_power_up.advanced_description = template.advanced_description
        new_power_up.description_values  = template.description_values
        new_power_up.icon                = template.icon

        local buff_template = table.clone(template.buff_template)
        local tweak_data = tweak_data_glob and tweak_data_glob[power_up_name]
        if tweak_data then
            for k, v in pairs(tweak_data) do
                buff_template.buffs[1][k] = v
            end
        end
        buff_template.buffs[1].name = new_power_up.buff_name
        buff_templates[new_power_up.buff_name] = buff_template
        -- Also register in the global BuffTemplates table. Vanilla CW boons get here via a
        -- boot-time `table.merge_recursive(dlc_settings.buff_templates, DeusPowerUpBuffTemplates)`
        -- in morris_buff_settings.lua:7310 — but that merge happens BEFORE mods load. Runtime
        -- writes to DeusPowerUpBuffTemplates don't propagate, so BuffUtils.get_buff_template
        -- (buff_utils.lua:256, reads `BuffTemplates[name]`) returns nil → crash in
        -- buff_extension.lua:177 when the buff is applied. Mirror the write here.
        local global_bt = rawget(_G, "BuffTemplates")
        if global_bt then
            global_bt[new_power_up.buff_name] = buff_template
        end
        -- v0.7.38: Network sync of boon application reads NetworkLookup.buff_templates
        -- to translate buff_name → int ID. Vanilla builds the lookup at boot from
        -- BuffTemplates; our runtime additions aren't in it, and the table's
        -- __index metatable errors on unknown keys (network_lookup.lua:2354-2358).
        -- Crash: "Table buff_templates does not contain key: power_up_<name>_<rarity>"
        -- on the second peer / first network sync. Burned in ct v0.7.34 → v0.7.37.
        register_buff_in_network_lookup(new_power_up.buff_name)
    end

    -- 3. Register in all derived tables.
    power_ups[rarity] = power_ups[rarity] or {}
    power_ups[rarity][power_up_name] = new_power_up

    table.insert(array, new_power_up)
    new_power_up.id = #array

    array_by_rarity[rarity] = array_by_rarity[rarity] or {}
    table.insert(array_by_rarity[rarity], new_power_up)

    new_power_up.lookup_id = #lookup + 1
    lookup[#lookup + 1]    = new_power_up
    lookup[power_up_name]  = new_power_up

    _injected_dormants[power_up_name] = new_power_up
    _dbg(string.format("[dormant] injected %s at rarity %s (lookup_id=%d)", power_up_name, rarity, new_power_up.lookup_id))
end

-- v0.7.67: pool insertion is now its own gated step. See the long comment inside
-- `inject_dormant_boon` for why this split is necessary. Idempotent via
-- `_added_to_pool` table — safe to call repeatedly (e.g. from both pre-register
-- and the toggled sync_dormant_boons / register_trait_boon paths).
local _added_to_pool = {}
local function _add_dormant_to_pool(power_up_name, rarity)
    if _added_to_pool[power_up_name] then return end
    -- v0.7.240-dev (#426): pool membership is peer-parity gated at THIS single
    -- choke point so no runtime caller can undo the wire gate's eject
    -- (sync_host_dependent_state re-runs register_trait_boon on every host-settings
    -- receipt, on_setting_changed re-runs it on enable_boon_* edits - both fired
    -- while parity was unconfirmed and silently re-pooled the boons; review
    -- finding, pre-ship). The nil-guard keeps LOAD-TIME inserts working: the
    -- wire-safety block below assigns mod._ct_wire_safe and then ejects everything
    -- once, so load-time inserts never leak. After load, inserts only proceed
    -- under confirmed parity (the gate's own on_enable qualifies by definition).
    if mod._ct_wire_safe and not mod._ct_wire_safe() then
        pcall(printf, "[ct:426] pool insert of %s deferred: peer parity not confirmed", tostring(power_up_name))
        return
    end
    local record = _injected_dormants[power_up_name]
    if not record then
        _dbg("[dormant] _add_dormant_to_pool: " .. tostring(power_up_name) .. " not yet registered; skipping pool insert")
        return
    end
    local pool = rawget(_G, "DeusPowerUpRarityPool")
    if not pool then return end
    pool[rarity] = pool[rarity] or {}
    table.insert(pool[rarity], { power_up_name, record.availability, {} })
    _added_to_pool[power_up_name] = true
    _dbg(string.format("[dormant] added %s to %s rarity pool (now %d entries in that rarity)", power_up_name, rarity, #pool[rarity]))
end

-- v0.7.88: previously sync_dormant_boons only added on toggle-on but never
-- removed on toggle-off. Once `_added_to_pool[name] = true`, the dormant
-- stayed in the offering pool for the rest of the session even after the
-- user un-checked the toggle in the VMF menu. This walks the DeusPowerUpRarityPool
-- entries for the given rarity and rips out the one matching `power_up_name`,
-- then clears the idempotency bit so a later toggle-on can re-add cleanly.
local function _remove_dormant_from_pool(power_up_name, rarity)
    if not _added_to_pool[power_up_name] then return end
    local pool = rawget(_G, "DeusPowerUpRarityPool")
    local arr = pool and pool[rarity]
    if arr then
        for i = #arr, 1, -1 do
            local entry = arr[i]
            if type(entry) == "table" and entry[1] == power_up_name then
                table.remove(arr, i)
            end
        end
    end
    _added_to_pool[power_up_name] = nil
    _dbg("[dormant] removed %s from %s rarity pool (toggle now OFF)", power_up_name, rarity)
end

-- 2026-05-23 v0.7.100-dev FULLY PURGED: pre_register_dormant_lookups, sync_dormant_boons,
-- and their apply-site calls. The functions iterated DORMANT_BOON_RARITY (which no longer
-- exists). The trait-boon + meta-boon paths still call `inject_dormant_boon` directly with
-- their own power-up names; those paths are unaffected by this purge.
--
-- To re-enable: uncomment the block below AND restore the DORMANT_BOON_RARITY table above.
--[[
local function pre_register_dormant_lookups()
    local templates = rawget(_G, "DeusPowerUpTemplates")
    if not templates then
        _dbg("[dormant] pre-register skipped: DeusPowerUpTemplates not yet loaded")
        return
    end
    local keys = {}
    for k in pairs(DORMANT_BOON_RARITY) do keys[#keys + 1] = k end
    table.sort(keys)
    for _, power_up_name in ipairs(keys) do
        local rarity = DORMANT_BOON_RARITY[power_up_name]
        inject_dormant_boon(power_up_name, rarity)
    end
    _dbg("[dormant] pre-registered %d dormants unconditionally for client compat", #keys)
end

local function sync_dormant_boons()
    local keys = {}
    for k in pairs(DORMANT_BOON_RARITY) do keys[#keys + 1] = k end
    table.sort(keys)
    for _, name in ipairs(keys) do
        local default_rarity = DORMANT_BOON_RARITY[name]
        if effective_setting("activate_dormant_" .. name) then
            _add_dormant_to_pool(name, default_rarity)
        else
            _remove_dormant_from_pool(name, default_rarity)
        end
    end
end

pre_register_dormant_lookups()
sync_dormant_boons()
--]]

-- ============================================================
-- v0.7.93: Khorne's Skulls Event Boons in non-Skulls CW (dormant-injection)
-- ============================================================
-- 2026-05-23 v0.7.98-dev DISABLED: full Skulls event boon implementation block-commented per
-- user request after Chest-of-Trials crash. The SKULLS_EVENT_BOONS constant + the
-- pre_register_skulls_event_lookups / _set_skulls_mutators_active / sync_skulls_event_boons
-- functions all live inside the block-comment below; nothing in this file references them once
-- this block is wrapped (the regression check that walked SKULLS_EVENT_BOONS is also disabled).
-- To re-enable, delete the wrapping `--[[` / `--]]` markers AND restore the VMF widget +
-- localization entries AND the disabled regression check.
--[[
-- The 10 Skulls boons (boon_skulls_01..08 + 2 set bonuses) are vanilla-registered
-- in DeusPowerUpTemplates at game boot — their templates, buffs, and NetworkLookup
-- entries already exist on every peer regardless of toggle state. Vanilla also
-- populates DeusPowerUps.event[boon_skulls_*], DeusPowerUpsArray, and
-- DeusPowerUpsArrayByRarity.event (via the boot-time DeusPowerUpRarityPool walk at
-- deus_power_up_settings.lua:7121-7176). The created buff variants are
-- `power_up_boon_skulls_01_event` etc., which is exactly the name the set-bonus
-- amplifier closures hard-code (`buff_extension:num_buff_stacks(
-- "power_up_boon_skulls_set_bonus_01_event")` at lines 462/487/516/etc.). So leaving
-- the vanilla "event" rarity records in place keeps the set bonuses functional.
--
-- All vanilla cares about for the seasonal gate is the per-record `mutators` field
-- ({"skulls_2023"} on every Skulls boon entry), checked by
-- deus_power_up_utils.lua:146 `compatible_mutator_active(power_up.mutators)` during
-- offering generation. To make the boons roll outside the event, we clear that
-- field at mod load — peer-safe because the array structure / network indices
-- aren't touched (only mutator semantics, which are evaluated host-side at roll
-- time on the existing record).
--
-- v0.7.85 attempted an "append to DeusPowerUpRarityPool" approach. That was a
-- no-op: DeusPowerUpRarityPool is read ONCE at boot to populate the runtime
-- arrays. The offering generator (deus_power_up_utils.lua:138-146) scans
-- DeusPowerUpsArrayByRarity, not the source pool. Replaced 2026-05-23 with this
-- direct-mutator-clear approach.
--
-- Why not the full inject_dormant_boon pattern (ct's 9 dormants + 11 trait boons)?
-- Because vanilla already did all of that for these boons at boot — every step of
-- inject_dormant_boon's registration is idempotent against vanilla's existing
-- writes, EXCEPT the unconditional `table.insert(DeusPowerUpsArray, ...)` and
-- ditto for ArrayByRarity / Lookup. Calling it would duplicate every Skulls boon
-- in the runtime arrays. Mutator-field clearing on the existing vanilla record
-- achieves the same gameplay outcome (boon becomes rollable) without the
-- duplication risk, and preserves the existing buff_name → set-bonus-amplifier
-- linkage intact. We still pre-register NetworkLookup names defensively (they're
-- already vanilla-registered but the call is idempotent).
--
-- Boons 06/07/08 (the 2025 variants) are functionally inert outside the Skulls
-- mutator: they fire on `on_mutator_skull_picked_up` (daemon-skull pickups don't
-- spawn outside the Skulls mutator) and check `num_buff_stacks("skulls_2023_buff")`
-- which is the mutator's own buff (always 0 stacks outside the mutator). They will
-- not crash — buff_func nil-checks and 0-stack multiplier=0 are vanilla-safe — but
-- a roll on one of them is largely wasted. Documented in tooltip. Boons 01-05 +
-- both set bonuses are fully functional outside the event.
local SKULLS_EVENT_BOONS = {
    "boon_skulls_01",
    "boon_skulls_02",
    "boon_skulls_03",
    "boon_skulls_04",
    "boon_skulls_05",
    "boon_skulls_06",
    "boon_skulls_07",
    "boon_skulls_08",
    "boon_skulls_set_bonus_01",
    "boon_skulls_set_bonus_02",
}

-- Cache the original `mutators` arrays (vanilla {"skulls_2023"} etc.) so we can
-- restore them on toggle-off. Indexed by power-up name. Captured at first mod-load
-- per peer; not persisted across game restart, so the restore always re-reads from
-- the live record.
local _skulls_original_mutators = {}

-- v0.7.93: pre-register the Skulls boon names in NetworkLookup unconditionally
-- (idempotent; vanilla already wrote them at boot, but cover the case of a future
-- vanilla change that defers them). Sorted iteration per
-- feedback_vt2_gated_registration_diverges. The set-bonus amplifier closures look up
-- the `power_up_boon_skulls_set_bonus_<NN>_event` buff names by string at runtime,
-- so they don't introduce additional NetworkLookup requirements beyond what vanilla
-- already provides.
local function pre_register_skulls_event_lookups()
    local templates = rawget(_G, "DeusPowerUpTemplates")
    local global_bt = rawget(_G, "BuffTemplates")
    local deus_bt = rawget(_G, "DeusPowerUpBuffTemplates")
    if not (templates and global_bt and deus_bt) then
        _dbg("[skulls-event] pre-register skipped: DeusPowerUp* tables not yet loaded")
        return
    end
    local sorted = {}
    for _, name in ipairs(SKULLS_EVENT_BOONS) do sorted[#sorted + 1] = name end
    table.sort(sorted)
    local registered = 0
    for _, power_up_name in ipairs(sorted) do
        if templates[power_up_name] then
            -- Defensive: re-register the NetworkLookup entries even though vanilla
            -- already did so. _register_in_network_lookup is idempotent (rawget
            -- guard at top), zero cost when already present.
            register_power_up_in_network_lookup(power_up_name)
            -- Vanilla's bootstrap (deus_power_up_settings.lua:7146-7161) created
            -- `power_up_<name>_event` buff variants and registered them in
            -- DeusPowerUpBuffTemplates. Mirror to _G.BuffTemplates per
            -- feedback_vt2_dormant_buff_template_dual_register — vanilla's DLCUtils
            -- merge runs at boot BEFORE mods load, so the Skulls buffs ARE already
            -- in global_bt for "event" rarity. But re-mirror defensively in case a
            -- future vanilla change defers the merge.
            local buff_name = "power_up_" .. power_up_name .. "_event"
            local buff_template = deus_bt[buff_name]
            if buff_template then
                global_bt[buff_name] = buff_template
                register_buff_in_network_lookup(buff_name)
            end
            registered = registered + 1
        else
            _dbg("[skulls-event] template %s not present in this game version — skipping (probably pre-2025 build)", tostring(power_up_name))
        end
    end
    _dbg("[skulls-event] pre-registered %d skulls boons for client compat (idempotent overlay on vanilla)", registered)
end

-- Toggle-on: clear the mutators array on each Skulls boon's runtime record so the
-- offering roller (deus_power_up_utils.lua:146) lets them through outside the
-- Skulls 2023 mutator. Toggle-off: restore the cached original {"skulls_2023"}
-- array so the boons revert to event-gated behaviour. Idempotent in both directions.
local function _set_skulls_mutators_active(enabled)
    local templates = rawget(_G, "DeusPowerUpTemplates")
    local deus_power_ups = rawget(_G, "DeusPowerUps")
    if not (templates and deus_power_ups) then
        _dbg("[skulls-event] _set_skulls_mutators_active(%s): DeusPowerUp* tables not loaded yet; skipping", tostring(enabled))
        return
    end
    local count_modified = 0
    for _, power_up_name in ipairs(SKULLS_EVENT_BOONS) do
        local record = deus_power_ups.event and deus_power_ups.event[power_up_name]
        if record then
            if _skulls_original_mutators[power_up_name] == nil then
                -- First touch — snapshot the vanilla mutators array. Even if vanilla
                -- happens to have `mutators = nil` (it doesn't, but defend), capture
                -- the empty-table marker so restore is unambiguous.
                _skulls_original_mutators[power_up_name] = record.mutators or {}
            end
            if enabled then
                record.mutators = {}
            else
                record.mutators = _skulls_original_mutators[power_up_name]
            end
            count_modified = count_modified + 1
        end
    end
    _dbg("[skulls-event] %s mutator gate on %d skulls boons (toggle=%s)",
        enabled and "cleared" or "restored", count_modified, tostring(enabled))
end

local function sync_skulls_event_boons()
    _set_skulls_mutators_active(effective_setting("enable_skulls_event_boons") == true)
end

pre_register_skulls_event_lookups()
sync_skulls_event_boons()
--]] -- 2026-05-23 v0.7.98-dev DISABLED: end Skulls event boon block (opened ~L4984)

-- ============================================================
-- Miracle of Ulric / Miracle of Isha (alternative blessing behaviors, v0.7.65)
-- ============================================================
-- Two host-synced toggles that REPLACE vanilla blessing behavior:
--   - tweak_miracle_of_ulric_persistent: vanilla blessing_of_power adds +50 to
--     each weapon's `power_level` field (deus_run_controller.lua:1671-1703).
--     That value EVAPORATES on weapon swap at an altar — the new weapon doesn't
--     have it. When the toggle is on, skip the vanilla weapon-mutation and
--     instead apply a persistent +50 power_level buff on every hero. Survives
--     swaps because it's on the player buff_extension, not the weapon entry.
--   - tweak_miracle_of_isha_alternative: vanilla blessing_of_isha runs a
--     mutator (mutator_blessing_of_isha.lua) that grants one team revive from
--     death. When the toggle is on, skip the mutator registration and instead
--     apply -25% damage_taken to every hero (persistent for the run).
--
-- Mirror writes to BuffTemplates (the global table) because the engine reads
-- via BuffUtils.get_buff_template which only consults that global; vanilla
-- merges DeusPowerUpBuffTemplates into it at boot, BEFORE mods load, so any
-- runtime writes to DeusPowerUpBuffTemplates alone are lost (per
-- feedback_vt2_dormant_buff_template_dual_register.md). Also register in
-- NetworkLookup.buff_templates via register_buff_in_network_lookup so the
-- rpc_add_buff sync path doesn't crash on unknown name.
local CT_BUFF_MIRACLE_OF_ULRIC = "ct_miracle_of_ulric"
local CT_BUFF_MIRACLE_OF_ISHA_AEGIS = "ct_miracle_of_isha_aegis"
local CT_BUFF_MIRACLE_OF_ISHA_WOUNDS = "ct_miracle_of_isha_wounds"

-- v0.7.81: Isha behavior is now a mutex checkbox cluster (per
-- LOCALIZATION_STANDARD.md § 10). Two checkboxes — `tweak_miracle_of_isha_aegis`
-- and `tweak_miracle_of_isha_wounds` — both default off (= vanilla). The mutex
-- enforcer in chaos_wastes_tweaker_mutex.lua guarantees only one can be on at
-- a time; this helper reads them and returns the canonical mode string the
-- rest of the file expects ("vanilla" / "aegis" / "wounds").
--
-- Migration: if the user previously selected a mode via the old
-- `tweak_miracle_of_isha_alternative` dropdown (v0.7.66-0.7.80), the dropdown's
-- value is still readable via mod:get even though the widget was removed.
-- We translate that legacy value into the new checkbox state on first read so
-- existing users' previous choice carries over. The migration write happens
-- once per session — subsequent calls hit the cluster directly.
--
-- v0.7.65 boolean legacy is also handled (true → aegis), in case anyone is
-- still on a pre-v0.7.66 save.
local _isha_migrated = false
local function _migrate_isha_legacy_dropdown_once()
    if _isha_migrated then return end
    _isha_migrated = true
    -- If a cluster member is already on, we've already migrated (or the user
    -- just set it via the new UI). Don't clobber.
    if effective_setting("tweak_miracle_of_isha_aegis") or effective_setting("tweak_miracle_of_isha_wounds") then
        return
    end
    local v = effective_setting("tweak_miracle_of_isha_alternative")
    -- v0.7.65 boolean → aegis; v0.7.66-0.7.80 dropdown values → matching checkbox.
    if v == true or v == "aegis" then
        mod:set("tweak_miracle_of_isha_aegis", true)
        _dbg("[miracle-isha] migrated legacy dropdown value %q -> tweak_miracle_of_isha_aegis", tostring(v))
    elseif v == "wounds" then
        mod:set("tweak_miracle_of_isha_wounds", true)
        _dbg("[miracle-isha] migrated legacy dropdown value %q -> tweak_miracle_of_isha_wounds", tostring(v))
    end
    -- v == false / nil / "vanilla" → both off (default), nothing to do.
end

local function _get_isha_mode()
    _migrate_isha_legacy_dropdown_once()
    if effective_setting("tweak_miracle_of_isha_aegis") then return "aegis" end
    if effective_setting("tweak_miracle_of_isha_wounds") then return "wounds" end
    return "vanilla"
end

local function _register_miracle_buff_templates()
    local global_bt = rawget(_G, "BuffTemplates")
    local deus_bt = rawget(_G, "DeusPowerUpBuffTemplates")
    if not global_bt then
        _dbg("[miracle] BuffTemplates not loaded; cannot register")
        return
    end

    -- +50 power_level. Shape mirrors liquid_bravado_potion
    -- (morris_buff_settings.lua:5534-5546) for the stat_buff="power_level" + bonus
    -- plumbing; is_persistent flag matches deus_special_farm_max_health_buff
    -- (deus_power_up_settings.lua:231-242) so DeusSpawning saves+reapplies it
    -- across missions until the blessing is consumed at end of run.
    --
    -- v0.7.153-dev SCOPE NOTE: ULRIC ALONE keeps `is_persistent = true` (the
    -- vanilla whole-run save/reapply path at deus_spawning.lua:249 save /
    -- :270-279 reapply). The two Isha buffs below (Aegis, Wounds) had their
    -- `is_persistent` flag DROPPED so DeusSpawning's save loop never captures
    -- them — they are now NEXT-MISSION-ONLY, applied by our own host-side
    -- `DeusSpawning._apply_initial_buffs` hook off the `rc._ct_isha_pending`
    -- flag and consumed on the next node change. See the hook below.
    local ulric_tpl = {
        buffs = {
            {
                icon = "blessing_power_01",
                name = CT_BUFF_MIRACLE_OF_ULRIC,
                stat_buff = "power_level",
                bonus = 50,
                max_stacks = 1,
                is_persistent = true,
            },
        },
    }
    global_bt[CT_BUFF_MIRACLE_OF_ULRIC] = ulric_tpl
    if deus_bt then deus_bt[CT_BUFF_MIRACLE_OF_ULRIC] = ulric_tpl end
    register_buff_in_network_lookup(CT_BUFF_MIRACLE_OF_ULRIC)

    -- -25% damage_taken (NEGATIVE multiplier — vanilla pattern: ale_defence
    -- uses multiplier=-0.04 for 4% reduction at buff_templates.lua:5325-5333).
    -- v0.7.153-dev: NO is_persistent — this is now a NEXT-MISSION-ONLY buff
    -- (re-applied by the _apply_initial_buffs hook from rc._ct_isha_pending).
    local isha_tpl = {
        buffs = {
            {
                icon = "blessing_isha_01",
                name = CT_BUFF_MIRACLE_OF_ISHA_AEGIS,
                stat_buff = "damage_taken",
                multiplier = -0.25,
                max_stacks = 1,
            },
        },
    }
    global_bt[CT_BUFF_MIRACLE_OF_ISHA_AEGIS] = isha_tpl
    if deus_bt then deus_bt[CT_BUFF_MIRACLE_OF_ISHA_AEGIS] = isha_tpl end
    register_buff_in_network_lookup(CT_BUFF_MIRACLE_OF_ISHA_AEGIS)

    -- v0.7.66: Infinite-wounds variant (recruit-style: every down is revivable
    -- instead of the 2nd down being instant death). Mirrors vanilla CW boon
    -- `indomitable` (deus_power_up_settings.lua:5056-5073) — perks-only template
    -- with no stat_buff. The `infinite_wounds` perk makes GenericStatusExtension
    -- :set_wounded skip the wounds-counter decrement (generic_status_extension
    -- .lua:1443-1450), so `has_wounds_remaining` always returns true and the
    -- death-on-down branch at player_unit_health_extension.lua:812 is never taken.
    -- v0.7.153-dev: NO is_persistent — NEXT-MISSION-ONLY (same path as Aegis).
    local isha_wounds_tpl = {
        buffs = {
            {
                icon = "blessing_isha_01",
                name = CT_BUFF_MIRACLE_OF_ISHA_WOUNDS,
                perks = { "infinite_wounds" },
                max_stacks = 1,
            },
        },
    }
    global_bt[CT_BUFF_MIRACLE_OF_ISHA_WOUNDS] = isha_wounds_tpl
    if deus_bt then deus_bt[CT_BUFF_MIRACLE_OF_ISHA_WOUNDS] = isha_wounds_tpl end
    register_buff_in_network_lookup(CT_BUFF_MIRACLE_OF_ISHA_WOUNDS)

    _dbg("[miracle] registered Ulric (+50 power), Isha-aegis (-25%% dmg taken), Isha-wounds (infinite wounds) buff templates")
end

_register_miracle_buff_templates()

-- Apply a persistent buff to every connected hero (host-only — the host-side
-- BuffSystem broadcasts add_buff via rpc_add_buff_synced so clients receive it
-- via the existing engine path). Both new buff templates are pre-registered in
-- NetworkLookup.buff_templates above, so the RPC dispatch is safe.
local function _apply_persistent_buff_to_all_heroes(buff_name)
    local is_server = Managers and Managers.player and Managers.player.is_server
    if not is_server then return end
    local side = Managers.state and Managers.state.side and Managers.state.side:get_side_from_name("heroes")
    local units = side and side.PLAYER_AND_BOT_UNITS
    if not units then return end
    local buff_system = Managers.state.entity and Managers.state.entity:system("buff_system")
    if not buff_system then return end
    for i = 1, #units do
        local u = units[i]
        if u and Unit.alive(u) then
            local be = ScriptUnit.has_extension(u, "buff_system")
            if be and not be:has_buff_type(buff_name) then
                buff_system:add_buff(u, buff_name, u)
            end
        end
    end
end

-- Single consolidated hook for both blessing overrides — VMF silently shadows
-- duplicate mod:hook on the same Class+method (feedback_vmf_hook_safe_no_chain.md).
mod:hook("DeusRunController", "_try_buy_blessing", function(func, self, buyer, blessing_name)
    -- v0.7.67 diagnostic: log every blessing_of_power entry regardless of toggle.
    -- The 2026-05-20 session showed zero entries despite the user reporting
    -- "Ulric wasn't purchaseable" — meaning the click was rejected at the UI
    -- layer (button greyed out) before reaching us. Next session will capture
    -- whether the click ever reaches _try_buy_blessing.
    if blessing_name == "blessing_of_power" then
        local toggle_on = effective_setting("tweak_miracle_of_ulric_persistent")
        local is_server = Managers and Managers.player and Managers.player.is_server
        local already = self:has_blessing(blessing_name)
        local coins = self._run_state:get_player_soft_currency(buyer, REAL_PLAYER_LOCAL_ID) or -1
        local cost = (DeusCostSettings and DeusCostSettings.shop and DeusCostSettings.shop.blessings
            and DeusCostSettings.shop.blessings[blessing_name]) or -1
        _dbg("[miracle] _try_buy_blessing entry: blessing=%s buyer=%s is_server=%s toggle=%s already=%s coins=%s cost=%s",
            tostring(blessing_name), tostring(buyer), tostring(is_server), tostring(toggle_on),
            tostring(already), tostring(coins), tostring(cost))
    end
    if blessing_name == "blessing_of_power" and effective_setting("tweak_miracle_of_ulric_persistent") then
        -- v0.7.240-dev (#426) peer-parity gate: ct_miracle_of_ulric is a ct-registered
        -- NetworkLookup.buff_templates entry. Applying it host-side broadcasts
        -- rpc_add_buff with the modded index to every client (buff_system.lua:302-305),
        -- and its is_persistent name re-applies on every later mission spawn
        -- (deus_spawning.lua:277-278) - a non-ct peer fatals decoding the index
        -- (network_lookup strict __index). Degrade: the vanilla blessing_of_power
        -- purchase, wire-safe for everyone. Solo / all-ct lobbies are unaffected.
        if not (mod._ct_wire_safe and mod._ct_wire_safe()) then
            pcall(printf, "[ct:426] Ulric persistent miracle degraded to vanilla blessing_of_power: peer parity not confirmed")
            return func(self, buyer, blessing_name)
        end
        -- Replicate vanilla affordability / dedup guards from
        -- deus_run_controller.lua:1590-1599.
        if self:has_blessing(blessing_name) then
            _dbg("[miracle] Ulric rejected: has_blessing=true (already bought)")
            return false
        end
        local current_coins = self._run_state:get_player_soft_currency(buyer, REAL_PLAYER_LOCAL_ID)
        local blessing_cost = DeusCostSettings.shop.blessings[blessing_name]
        if current_coins < blessing_cost then
            _dbg("[miracle] Ulric rejected: coins=%d < cost=%d", current_coins, blessing_cost)
            return false
        end

        _apply_persistent_buff_to_all_heroes(CT_BUFF_MIRACLE_OF_ULRIC)

        -- Replicate vanilla accounting from deus_run_controller.lua:1705-1722 so
        -- the blessing appears in run-stats UI and the lifetime decrement runs.
        local skip_metatable = true
        local blessings_with_buyer = table.clone(self._run_state:get_blessings_with_buyer(), skip_metatable)
        blessings_with_buyer[blessing_name] = buyer
        self._run_state:set_blessings_with_buyer(blessings_with_buyer)
        self._run_state:set_player_soft_currency(buyer, REAL_PLAYER_LOCAL_ID, current_coins - blessing_cost)
        local bought_blessings = table.clone(self._run_state:get_bought_blessings(), skip_metatable)
        bought_blessings[#bought_blessings + 1] = blessing_name
        self._run_state:set_bought_blessings(bought_blessings)
        self:_add_coin_tracking_entry(buyer, REAL_PLAYER_LOCAL_ID, -blessing_cost, "blessing")

        _dbg("[miracle] Ulric (persistent +50 power) applied; vanilla weapon-power bump skipped")
        return true

    elseif blessing_name == "blessing_of_isha" then
        local isha_mode = _get_isha_mode()
        if isha_mode == "vanilla" then
            return func(self, buyer, blessing_name)
        end

        -- v0.7.240-dev (#426) peer-parity gate: the Isha alternatives apply ct-registered
        -- buffs (ct_miracle_of_isha_aegis / _wounds) to every hero via rpc_add_buff -
        -- same modded-index CTD class as Ulric above. Degrade: vanilla blessing_of_isha.
        if not (mod._ct_wire_safe and mod._ct_wire_safe()) then
            pcall(printf, "[ct:426] Isha alternative (%s) degraded to vanilla blessing_of_isha: peer parity not confirmed", tostring(isha_mode))
            return func(self, buyer, blessing_name)
        end

        -- v0.7.66 fix (was v0.7.65 dedup bug): the prior implementation SKIPPED
        -- writing blessing_of_isha to blessings_with_buyer in an attempt to also
        -- suppress the auto-mutator activation. But `has_blessing` reads from
        -- blessings_with_buyer, so the shop let users re-buy the alternative on
        -- every visit and drain coins (deus_shop_view_v2.lua:854-867 also keys
        -- the "is_bought" indicator off that table). Now we DO write it (fixes
        -- the shop UX) and instead suppress the vanilla mutator behavior via
        -- the MutatorTemplates.blessing_of_isha.server_start_function hook below.
        if self:has_blessing(blessing_name) then return false end
        local current_coins = self._run_state:get_player_soft_currency(buyer, REAL_PLAYER_LOCAL_ID)
        local blessing_cost = DeusCostSettings.shop.blessings[blessing_name]
        if current_coins < blessing_cost then return false end

        -- v0.7.153-dev: ONE-MISSION scope. The buy happens in the Deus SHOP
        -- (map_deus node), where there are no player_units yet — so we cannot
        -- add the buff now. Instead stash the chosen buff name on the run
        -- controller (a host-local field that persists across the shop->mission
        -- transition, same object the bookkeeping below writes through). The
        -- DeusSpawning._apply_initial_buffs hook promotes it to "active" on the
        -- NEXT mission's first spawn, applies it to every hero/bot for that
        -- mission only, and consumes it on the mission after. Ulric is
        -- unchanged (still immediate + whole-run via is_persistent).
        self._ct_isha_pending = (isha_mode == "wounds")
            and CT_BUFF_MIRACLE_OF_ISHA_WOUNDS
            or  CT_BUFF_MIRACLE_OF_ISHA_AEGIS
        _dbg("[miracle] Isha mode=%s queued for NEXT mission only (pending=%s)",
            tostring(isha_mode), tostring(self._ct_isha_pending))

        local skip_metatable = true
        local blessings_with_buyer = table.clone(self._run_state:get_blessings_with_buyer(), skip_metatable)
        blessings_with_buyer[blessing_name] = buyer
        self._run_state:set_blessings_with_buyer(blessings_with_buyer)
        self._run_state:set_player_soft_currency(buyer, REAL_PLAYER_LOCAL_ID, current_coins - blessing_cost)
        local bought_blessings = table.clone(self._run_state:get_bought_blessings(), skip_metatable)
        bought_blessings[#bought_blessings + 1] = blessing_name
        self._run_state:set_bought_blessings(bought_blessings)
        self:_add_coin_tracking_entry(buyer, REAL_PLAYER_LOCAL_ID, -blessing_cost, "blessing")

        _dbg("[miracle] Isha alternative mode=%s queued (next mission only); vanilla revive mutator suppressed", isha_mode)
        return true
    end

    return func(self, buyer, blessing_name)
end)

-- v0.7.153-dev: ONE-MISSION Isha — apply + consume.
--
-- Mechanism (Option B). Aegis/Wounds are now NON-persistent (is_persistent
-- dropped from their templates above), so vanilla's DeusSpawning save loop
-- (deus_spawning.lua:249 `template.is_persistent` filter) never captures them
-- and they expire when the mission unloads. The buy hook stashes the chosen
-- buff name on `rc._ct_isha_pending`. This hook — the ONLY hook on DeusSpawning
-- in this file (pre-flight grep `"DeusSpawning"` -> 0 prior hooks) — promotes the
-- pending flag to "active" on the next mission's first spawn, applies it to every
-- hero/bot for that mission, and consumes it on the mission AFTER. It is keyed on
-- the run controller's current node key (rc:get_current_node_key(),
-- deus_run_controller.lua:2062) which is STABLE within a mission (set once per
-- node transition) and DISTINCT between consecutive missions (each is its own
-- graph node) — so the gate is race-free, with no dependence on game-start vs
-- spawn ordering. Respawns within the mission re-enter _apply_initial_buffs at
-- the same node key, so the buff is re-applied (guarded by has_buff_type so a
-- hero who never died is not double-stacked). Host-only; buff_system:add_buff
-- broadcasts to clients via rpc_add_buff_synced (templates are pre-registered in
-- NetworkLookup.buff_templates) exactly as _apply_persistent_buff_to_all_heroes did.
CT_ISHA_ONE_MISSION_MARKER = "isha_one_mission:apply_initial_buffs_node_key_v0.7.153"
mod:hook_safe("DeusSpawning", "_apply_initial_buffs", function(self, player)
    if not (Managers and Managers.player and Managers.player.is_server) then return end
    local rc = self._deus_run_controller
    if not rc then return end

    -- Current mission identity. get_current_node_key is the run controller's
    -- authoritative position field (same value the mission-start diagnostic
    -- reads); each combat mission is a distinct graph node.
    local level_key = rc.get_current_node_key and rc:get_current_node_key() or nil

    -- Promote a freshly-purchased pending flag to active, tagged to THIS mission.
    -- The shop is a `map` node with no player units, so _apply_initial_buffs does
    -- not fire there — the first time it fires post-purchase is the next mission.
    if rc._ct_isha_pending and not rc._ct_isha_active then
        -- v0.7.240-dev (#426): arm the pending buff only under confirmed peer parity.
        -- Not armed = stays pending; a later mission re-tries once parity is restored
        -- (state preserved, execution gated - the buy already succeeded and the coins
        -- were spent under parity, so the entitlement is kept, never destroyed).
        if mod._ct_wire_safe and mod._ct_wire_safe() then
            rc._ct_isha_active = rc._ct_isha_pending
            rc._ct_isha_pending = nil
            rc._ct_isha_active_level = level_key
            _dbg("[miracle] Isha one-mission buff %s armed for node=%s",
                tostring(rc._ct_isha_active), tostring(level_key))
        else
            pcall(printf, "[ct:426] Isha one-mission buff %s held pending: peer parity not confirmed (re-tries next mission)",
                tostring(rc._ct_isha_pending))
        end
    end

    if not rc._ct_isha_active then return end

    if level_key == rc._ct_isha_active_level then
        -- Still inside the granted mission (initial spawn wave OR a respawn).
        -- Apply to this hero/bot.
        local player_unit = player and player.player_unit
        if not (player_unit and Unit.alive(player_unit)) then return end
        local buff_system = Managers.state and Managers.state.entity
            and Managers.state.entity:system("buff_system")
        if not buff_system then return end
        local be = ScriptUnit.has_extension(player_unit, "buff_system")
        if be and not be:has_buff_type(rc._ct_isha_active) then
            -- v0.7.240-dev (#426): re-apply (initial wave + respawns) is parity-gated too,
            -- so a peer who joined mid-mission without ct is never sent the modded index.
            if mod._ct_wire_safe and mod._ct_wire_safe() then
                buff_system:add_buff(player_unit, rc._ct_isha_active, player_unit)
                _dbg("[miracle] Isha one-mission buff %s applied to a hero on node=%s",
                    tostring(rc._ct_isha_active), tostring(level_key))
            else
                pcall(printf, "[ct:426] Isha buff %s apply skipped: peer parity not confirmed", tostring(rc._ct_isha_active))
            end
        end
    else
        -- Reached a DIFFERENT mission than the one the buff was granted for —
        -- the one-mission window is over. Consume; do NOT apply.
        _dbg("[miracle] Isha one-mission buff %s expired (granted node=%s, now node=%s)",
            tostring(rc._ct_isha_active), tostring(rc._ct_isha_active_level), tostring(level_key))
        rc._ct_isha_active = nil
        rc._ct_isha_active_level = nil
    end
end)

-- v0.7.66: Suppress vanilla Isha mutator when alternative mode is active.
-- Every entry point in mutator_blessing_of_isha.lua early-returns on
-- `not data.hero_side`:
--   - server_update_function:           line 168 — `if not data.hero_side then return end`
--   - server_player_disabled_function:  line 138 — same
--   - server_player_hit_function:       line 156 — same
--   - try_activate_blessing:            only called from the two above, so dead
-- Setting data.hero_side = nil in the post-start callback neutralizes the entire mutator.
--
-- IMPORTANT (v0.7.66 QA-found): the live dispatch target is
-- `template.server.start_function`, NOT `template.server_start_function`. The
-- engine wraps every mutator at `mutator_templates.lua:236-269` (runs at engine
-- boot, before mods) — `template.server_start_function` is left as a dead
-- field, the wrapper at template.server.start_function captures the original
-- via upvalue. Hooking the dead field compiled cleanly but suppressed nothing.
-- v0.7.94-dev: regression marker — set true once the suppression hook actually
-- installed onto MutatorTemplates.blessing_of_isha.server.start_function. Read
-- by the `miracle_of_isha_hook_installed` /ct_regression_test check below.
_G.__ct_isha_suppression_hook_installed = false
do
    local mut_templates = rawget(_G, "MutatorTemplates")
    local isha_template = mut_templates and mut_templates.blessing_of_isha
    local server_tbl = isha_template and isha_template.server
    if server_tbl and type(server_tbl.start_function) == "function" then
        mod:hook(server_tbl, "start_function", function(func, context, data, unit)
            func(context, data, unit)
            local current_mode = _get_isha_mode()
            if current_mode ~= "vanilla" then
                data.hero_side = nil
                _dbg("[isha] mode=%s, applying alternative (vanilla mutator neutralized at server.start_function)", current_mode)
            end
        end)
        _G.__ct_isha_suppression_hook_installed = true
        _dbg("[miracle] Isha suppression hook installed on MutatorTemplates.blessing_of_isha.server.start_function")
    else
        _dbg("[miracle] MutatorTemplates.blessing_of_isha.server.start_function not loaded at hook time; alternative-mode suppression skipped")
    end
end

-- v0.7.94-dev: /verify_isha chat command — surfaces current mode and hook state
-- per the verify-before-shipping doctrine. Prints to chat (player can copy out).
mod:command("verify_isha", "Print Miracle of Isha mode + hook install state", function()
    local mode = _get_isha_mode()
    local aegis_raw   = mod:get("tweak_miracle_of_isha_aegis")
    local wounds_raw  = mod:get("tweak_miracle_of_isha_wounds")
    local hook_ok     = _G.__ct_isha_suppression_hook_installed == true
    local cluster_member = _ct_mutex and _ct_mutex.active and _ct_mutex.active("isha_choice") or nil

    mod:echo("=== verify_isha (v%s) ===", MOD_VERSION)
    mod:echo("  resolved mode: %s", tostring(mode))
    mod:echo("  aegis toggle:  %s   wounds toggle: %s", tostring(aegis_raw), tostring(wounds_raw))
    mod:echo("  mutex active:  %s", tostring(cluster_member))
    mod:echo("  hook installed (MutatorTemplates.blessing_of_isha.server.start_function): %s", tostring(hook_ok))

    -- Title resolution check — mod:localize returns the raw key on miss.
    local aegis_label  = mod:localize("tweak_miracle_of_isha_aegis")
    local wounds_label = mod:localize("tweak_miracle_of_isha_wounds")
    local aegis_ok  = aegis_label  and aegis_label  ~= "tweak_miracle_of_isha_aegis"  and #aegis_label > 0
    local wounds_ok = wounds_label and wounds_label ~= "tweak_miracle_of_isha_wounds" and #wounds_label > 0
    mod:echo("  aegis title:   %s (%s)",  tostring(aegis_label),  aegis_ok  and "OK" or "MISSING")
    mod:echo("  wounds title:  %s (%s)", tostring(wounds_label), wounds_ok and "OK" or "MISSING")

    -- v0.7.153-dev: one-mission pending/active flag state. Resolve the Deus run
    -- controller defensively — it is nil in the keep (no active CW run).
    local rc = nil
    local gm = Managers and Managers.state and Managers.state.game_mode
    local gmode = gm and gm:game_mode()
    rc = gmode and gmode._deus_run_controller or nil
    if rc then
        mod:echo("  one-mission flags: pending=%s active=%s active_level=%s",
            tostring(rc._ct_isha_pending), tostring(rc._ct_isha_active), tostring(rc._ct_isha_active_level))
    else
        mod:echo("  one-mission flags: <no active CW run>")
    end

    if aegis_raw and wounds_raw then
        mod:echo("  WARN: both toggles ON; logic resolves to %q (aegis preference); mutex should have prevented this", mode)
    end
end)
return {
    inject_dormant_boon = inject_dormant_boon,
    add_dormant_to_pool = _add_dormant_to_pool,
    remove_dormant_from_pool = _remove_dormant_from_pool,
    injected_dormants = _injected_dormants,
    register_buff_in_network_lookup = register_buff_in_network_lookup,
    register_power_up_in_network_lookup = register_power_up_in_network_lookup,
    miracle_buff_names = {
        ulric = CT_BUFF_MIRACLE_OF_ULRIC,
        isha_aegis = CT_BUFF_MIRACLE_OF_ISHA_AEGIS,
        isha_wounds = CT_BUFF_MIRACLE_OF_ISHA_WOUNDS,
    },
}
