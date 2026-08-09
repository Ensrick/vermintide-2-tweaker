-- _ct_spawn_eligibility_owner.lua -- pickup spawn-eligibility gating (#1159 / #504).
--
-- RESPONSIBILITY
-- Owns every "may this pickup claim this spawner?" decision on the host:
--   * career-exclusive pickup blocklist (v0.7.97, engineer_grenade_t1)
--   * the v0.7.165-dev coin-starvation reservation (Abundance-of-Life curse)
--   * pickup-unit loadability pre-flight (v0.7.78, Application.can_get)
--   * the injected-adventure campaign-category fallback (v0.7.64)
-- Behaviour is byte-for-byte the pre-extraction `PickupSystem._can_spawn` hook
-- plus its helper group; this module is a structural move only.
--
-- PUBLIC SURFACE (assigned onto `mod` by install(), unchanged names so the
-- earlier-defined populate_pickups hook and the regression markers keep working):
--   mod._ct_coin_reservation_test      { fraction, reserved }  -- regression marker
--   mod._ct_rebuild_coin_reserved_set  (spawner_lists)         -- called per populate pass
--   mod._ct_clear_coin_reserved_set    ()
--   mod._ct_spawner_reserved_for_coins (spawner_unit)
--
-- MANIFEST POSITION
-- dofile'd from the entry at the exact point the helper block used to sit, i.e.
-- AFTER the populate_pickups hook that calls mod._ct_rebuild_coin_reserved_set.
-- That ordering is intentional and safe: the populate hook resolves the field at
-- CALL time, and the script body finishes before any hook fires.
--
-- WHY ACCESSORS, NOT TABLES
-- The entry REASSIGNS `_career_exclusive_denial_counts` and
-- `_career_exclusive_logged_this_run` to fresh tables at every populate_pickups
-- entry (run boot) rather than clearing them in place. Capturing the table
-- references at install time would pin this module to the load-time tables, so
-- denial counts would accumulate across runs and the once-per-run log gate would
-- never reset. ctx therefore passes GETTERS that read the entry's current local.

local M = {}

-- ctx:
--   mod                          -- the VMF mod object (required)
--   dbg(fmt, ...)                -- entry's _dbg logger
--   on_injected_adventure_level()
--   career_exclusive_blocklist   -- read-only table, pickup_name -> true
--   get_denial_counts()          -- returns the CURRENT per-run denial table
--   get_logged_this_run()        -- returns the CURRENT per-run log-gate table
function M.install(ctx)
    local mod                         = ctx.mod
    local _dbg                        = ctx.dbg
    local on_injected_adventure_level = ctx.on_injected_adventure_level
    local _CAREER_EXCLUSIVE_PICKUPS_BLOCKLIST = ctx.career_exclusive_blocklist
    local get_denial_counts           = ctx.get_denial_counts
    local get_logged_this_run         = ctx.get_logged_this_run

    -- v0.7.78: pickup_settings.unit_name may reference a unit that isn't loaded on
    -- this level (e.g. `holy_hand_grenade` on Skittergate, `deus_weapon_chest` which
    -- only loads in Morris/CW mission bundles). After v0.7.64 broadened the
    -- adventure-level allowlist those entries became spawn-eligible on injected
    -- adventure missions where the unit isn't in resources, and when RNG rolled one
    -- the engine fataled in `World.spawn_unit`. Pre-flight the pickup's unit path
    -- with `Application.can_get` so the spawner is skipped (empty spot, the
    -- vanilla-equivalent of a soft veto) instead of crashing.
    local function _pickup_unit_loadable(pickup_name)
        if not Pickups then return true end  -- can't check, let it through
        for _, cat in pairs(Pickups) do
            if type(cat) == "table" then
                local settings = cat[pickup_name]
                if type(settings) == "table" then
                    local unit_name = settings.unit_name
                    if type(unit_name) ~= "string" then return true end
                    return Application.can_get("unit", unit_name)
                end
            end
        end
        return true  -- not a vanilla bucket entry; trust the caller
    end

    -- v0.7.165-dev: ROBUST coin-starvation fix (Abundance-of-Life curse). See the
    -- mechanism block in _adventure_pool.lua make_cw_pickup_settings(): on injected
    -- adventure levels our _can_spawn fallback below un-partitions vanilla's spawner
    -- types -- deus_potions, deus_soft_currency and deus_weapon_chest all compete for
    -- the SAME finite, shared primary spawner pool that PickupSystem._spawn_spread_pickups
    -- iterates per pickup_type over ONE `spawners` array, permanently table.remove()-ing
    -- each consumed spawner (pickup_system.lua:467-633, :621-626). Two facts make
    -- coins starve under the curse:
    --   1. `for pickup_type in pairs(pickup_settings)` (pickup_system.lua:470) is
    --      NON-DETERMINISTIC in Lua 5.1, so deus_potions can iterate (and drain
    --      spawners) BEFORE deus_soft_currency.
    --   2. The Abundance-of-Life curse multiplies ONLY deus_potions x3
    --      (mutator_curse_abundance_of_life.lua:7-11, applied by
    --      MutatorHandler.pickup_settings_updated_settings:544-560) -- coins stay flat.
    -- A pure count-ratio fix (request fewer potions than coins) only REDUCES the odds
    -- because allocation is per-section greedy in random type order, not proportional;
    -- on a finite-spawner level a potions-first pass can still exhaust the pool first.
    --
    -- GUARANTEE (not just reduce): reserve a deterministic ~40% slice of the primary
    -- spawners as COIN-ONLY by DENYING deus_potions / deus_weapon_chest eligibility on
    -- them here. A spawner is only table.remove()'d when a pickup that _can_spawn
    -- ALLOWED consumes it, so a spawner potions can never claim survives every potion
    -- iteration regardless of pairs() order or the curse x3 -- it is still present and
    -- coin-eligible when deus_soft_currency iterates. This mirrors vanilla's native
    -- partition (potion-spawners vs painting_scrap->coin-spawners never contend).
    --
    -- The slice is chosen by a stable per-spawner hash of `percentage_through_level`
    -- (a fixed float each primary spawner carries, read all over pickup_system.lua:
    -- 325/424/508/531) so the reserved spawners are spread UNIFORMLY across the
    -- percentage range -- coins find a reserved spawner in whatever section they
    -- iterate. No extra hook, no per-run state, deterministic within the host's single
    -- populate pass. deus_soft_currency itself is NEVER denied by this reservation.
    local _COIN_RESERVED_FRACTION = 0.40
    -- Pure hash of a percentage_through_level value -> reserved? Split out so the
    -- /ct_regression_test marker can exercise the partition math without a live unit,
    -- and so it can serve as the per-spawner fallback when no precomputed set exists.
    local function _coin_reservation_hash_reserved(p)
        if type(p) ~= "number" then return false end
        -- Stable pseudo-random in [0,1) from the spawner's fixed percentage. The big
        -- prime + frac() decorrelates it from the value's own ordering so the reserved
        -- set isn't a contiguous band at the start/end of the level.
        local h = (p * 7919.0 + 0.6180339887)
        h = h - math.floor(h)
        return h < _COIN_RESERVED_FRACTION
    end

    -- RANK-based reserved set, rebuilt once per populate_pickups pass (host). The pure
    -- per-spawner hash above is ~40% in expectation but, on a VERY small pool (e.g. 6
    -- spawners), independent hashing has a ~4% chance of reserving ZERO -- which would
    -- silently drop the coin guarantee. Building the set by RANK guarantees a floor of
    -- math.max(1, ceil(frac*N)) reserved spawners for ANY non-empty pool, closing that
    -- hole. Keyed by unit so _can_spawn can do an O(1) membership test. Reset + rebuilt
    -- at the top of the populate_pickups hook; consulted (with hash fallback) below.
    local _coin_reserved_units = {}
    local function _rebuild_coin_reserved_set(spawner_lists)
        table.clear(_coin_reserved_units)
        for _, list in ipairs(spawner_lists) do
            if type(list) == "table" then
                -- Sort by the per-spawner hash so the reserved set is the lowest-hash
                -- prefix -- deterministic, spread across percentage_through_level (the
                -- hash decorrelates from position), and a guaranteed proper-size slice.
                local ranked = {}
                for _, unit in ipairs(list) do
                    if Unit.alive(unit) then
                        local p = Unit.get_data(unit, "percentage_through_level")
                        if type(p) == "number" then
                            local h = p * 7919.0 + 0.6180339887
                            h = h - math.floor(h)
                            ranked[#ranked + 1] = { unit = unit, h = h }
                        end
                    end
                end
                table.sort(ranked, function(a, b) return a.h < b.h end)
                local n = #ranked
                if n > 0 then
                    local reserve_n = math.max(1, math.ceil(_COIN_RESERVED_FRACTION * n))
                    -- Never reserve the WHOLE pool -- potions/altars need spawners too.
                    reserve_n = math.min(reserve_n, n - 1 >= 1 and n - 1 or n)
                    for i = 1, reserve_n do
                        _coin_reserved_units[ranked[i].unit] = true
                    end
                end
            end
        end
    end
    local function _spawner_reserved_for_coins(spawner_unit)
        -- Prefer the precomputed rank-based set (built on the host this populate pass);
        -- fall back to the pure hash if it wasn't built (defensive: client, or a path
        -- that reaches _can_spawn before populate_pickups ran).
        if next(_coin_reserved_units) ~= nil then
            return _coin_reserved_units[spawner_unit] == true
        end
        return _coin_reservation_hash_reserved(Unit.get_data(spawner_unit, "percentage_through_level"))
    end
    -- Test handle for the regression marker (coin_reservation_partition).
    mod._ct_coin_reservation_test = {
        fraction = _COIN_RESERVED_FRACTION,
        reserved = _coin_reservation_hash_reserved,
    }
    -- Exposed on `mod` so the populate_pickups hook (defined EARLIER in the entry, so
    -- it can't see this module's upvalue by lexical scope) can rebuild the reserved set
    -- each pass. The function is resolved at CALL time, by which point this install has
    -- run (the entry's script body executes top-to-bottom before any hook fires).
    mod._ct_rebuild_coin_reserved_set = _rebuild_coin_reserved_set
    mod._ct_clear_coin_reserved_set = function() table.clear(_coin_reserved_units) end
    mod._ct_spawner_reserved_for_coins = _spawner_reserved_for_coins

    -- Grant CW-pickup eligibility on adventure-level spawners that have analogous
    -- adventure tags. Vanilla `PickupSystem._can_spawn` returns
    -- `Unit.get_data(spawner, pickup_name) or Managers.mechanism:can_spawn_pickup(spawner, pickup_name)`.
    -- For adventure spawners, neither path matches CW pickup types — they're tagged
    -- `potions`/`painting_scrap`/`ammo`/etc., not `deus_potion`/`deus_cursed_chest`. So
    -- our deus pickup counts in pickup_settings.primary result in "spawn debt" warnings
    -- (engine wanted N, found 0 eligible spawners).
    --
    -- Mapping (only fires on injected adventure levels):
    --   * potion spawners       → deus_potions   (any pickup in Pickups.deus_potions)
    --   * painting_scrap spots  → deus_soft_currency (Pilgrim's Coin)
    --   * non-claimed primaries → deus_weapon_chest (altars compete with ammo/healing
    --                              for remaining primary spawn slots)
    mod:hook("PickupSystem", "_can_spawn", function(func, self, spawner_unit, pickup_name)
        -- v0.7.97: career-exclusive pickup blocklist. Applied BEFORE vanilla and
        -- BEFORE the ct adventure-cat fallback, so the denial covers every path
        -- (vanilla CW deus, injected adventure, hypothetical future broadening).
        -- The owning career's grant function (e.g. Engineer's cooldown buff using
        -- `inventory_extension:add_equipment`) does NOT route through PickupSystem,
        -- so this denial does not affect legitimate career mechanics.
        if pickup_name and _CAREER_EXCLUSIVE_PICKUPS_BLOCKLIST[pickup_name] then
            local denial_counts = get_denial_counts()
            local logged_this_run = get_logged_this_run()
            denial_counts[pickup_name] = (denial_counts[pickup_name] or 0) + 1
            if not logged_this_run[pickup_name] then
                logged_this_run[pickup_name] = true
                _dbg("[pickup] denied career-exclusive: %s", pickup_name)
            end
            return false
        end

        local ok = func(self, spawner_unit, pickup_name)
        if ok then return ok end

        if not on_injected_adventure_level() then return ok end

        -- Reserved for the tome/grim → Chest of Trials conversion (see
        -- _spawn_guaranteed_pickup hook in the entry). Never let any CW pickup
        -- hijack these book spots.
        if Unit.get_data(spawner_unit, "tome") or Unit.get_data(spawner_unit, "grimoire") then
            return false
        end

        -- Triggered event spawners (lamp_oil barrels for wagon-escape, explosive_barrel
        -- for body-burn objectives, training_dummy_bob spawners, etc.) MUST stay
        -- exclusive to their tagged pickup type. The vanilla `_can_spawn` checks
        -- `Unit.get_data(spawner, pickup_name)` — only e.g. `lamp_oil = true` returns
        -- true. But `_spawn_guaranteed_pickup` iterates ALL pickup names, and our
        -- CW-type fallback below would otherwise add `healing_draught`, `strength_potion`,
        -- etc. to the candidate list, so a triggered barrel-spawner could roll a potion
        -- and break the scripted event. v0.6.32 burned this: barrels for "burn the bodies"
        -- type events sometimes appeared as potions.
        -- Same risk for guaranteed_spawn spawners (already filtered for tome/grim
        -- above) and specified spawners.
        if Unit.get_data(spawner_unit, "guaranteed_spawn") then
            return false
        end
        local triggered_spawn_id = Unit.get_data(spawner_unit, "triggered_spawn_id")
        if triggered_spawn_id and triggered_spawn_id ~= "" then
            return false
        end

        -- CW pickups accept any non-tome/grim, non-event primary spawner. They
        -- compete with vanilla ammo/healing/grenades for unclaimed slots.
        --
        -- v0.7.165-dev coin reservation: deus_soft_currency is ALWAYS eligible (never
        -- reserved-out); deus_potions and deus_weapon_chest are DENIED on the
        -- coin-reserved spawner slice so they can't drain it ahead of coins under the
        -- Abundance-of-Life x3 potion curse (see _spawner_reserved_for_coins above).
        if Pickups and Pickups.deus_potions and Pickups.deus_potions[pickup_name] then
            if mod._ct_spawner_reserved_for_coins(spawner_unit) then return false end
            return _pickup_unit_loadable(pickup_name)
        end
        if pickup_name == "deus_soft_currency" then
            return _pickup_unit_loadable(pickup_name)
        end
        if pickup_name == "deus_weapon_chest" then
            if mod._ct_spawner_reserved_for_coins(spawner_unit) then return false end
            return _pickup_unit_loadable(pickup_name)
        end

        -- v0.7.64: on injected adventure levels, ALSO allow vanilla campaign pickup
        -- categories (ammo, healing, grenades, potions, painting_scrap, level_events).
        -- Pre-v0.7.64 the comment block above incorrectly assumed vanilla `_can_spawn`
        -- already returned true on these — but for adventure levels running under the
        -- deus mechanism, `Managers.mechanism:can_spawn_pickup` routes to the deus
        -- mechanism's pickup whitelist which doesn't recognize campaign pickup names,
        -- and the per-spawner `Unit.get_data(spawner, pickup_name)` check often fails
        -- for category vs specific-name mismatches (spawner tagged "ammo=true" while
        -- pickup_name is "ammo_specific_X"). Result on Holly DLC adventure-injected
        -- levels (Magnus / Cemetery / Forest Ambush): ALL pickups silently vetoed —
        -- not just deus types — leaving the map with literally nothing on the ground.
        -- Burned in the 2026-05-19 3-player run: 13 spawn-debt warnings on magnus
        -- including ammo, healing, grenades — the vanilla pickup-types ct's earlier
        -- code path mistakenly assumed were handled before our hook.
        --
        -- Explicit allowlist (not `string.sub(cat, 1, 5) ~= "deus_"`) to keep
        -- `versus_objective`, `weave`, and other non-campaign categories out of the
        -- candidate set even if Fatshark adds them to the global Pickups table in a
        -- future patch. Tome/grim/guaranteed/triggered spawners are already filtered
        -- above; this fallback only fires on plain primary/secondary spawners.
        if Pickups then
            local ADVENTURE_CATS = { "ammo", "healing", "grenades", "potions",
                "painting_scrap", "level_events" }
            for _, category in ipairs(ADVENTURE_CATS) do
                local bucket = Pickups[category]
                if type(bucket) == "table" and bucket[pickup_name] then
                    -- v0.7.78: pickup_settings.unit_name may reference a unit that
                    -- isn't loaded on this level (e.g. `holy_hand_grenade` on
                    -- Skittergate). Soft-veto rather than letting the engine fatal
                    -- when the spawner fires.
                    local unit_name = bucket[pickup_name].unit_name
                    if type(unit_name) == "string"
                        and not Application.can_get("unit", unit_name) then
                        return false
                    end
                    return true
                end
            end
        end

        return false
    end)
end

return M
