-- _ct_weapon_trait_generation.lua -- CT-dev weapon trait roll owner.
--
-- Owns the four DeusWeaponGeneration hooks, their save/restore bracket, the
-- rarity-tier catalogue, and the two lazily-built trait-pool caches. Runtime
-- dependencies are injected so this module retains the entry's exact hook and
-- regression-registration boundary without owning settings or wire state.
--
-- Owned by: chaos_wastes_tweaker_dev.lua entry point.
-- Consumed via: one ordered mod:dofile installer call, the entry's on_disabled
-- cache reset, and its installed VMF hooks; guarded by
-- qa/lua/tests/test_ct_weapon_trait_generation.lua.
return function(ctx)
    assert(type(ctx) == "table", "CT weapon trait generation requires context")

    local mod = assert(ctx.mod, "CT weapon trait generation requires mod")
    local effective_setting = assert(ctx.effective_setting,
        "CT weapon trait generation requires effective_setting")
    local _dbg = assert(ctx.dbg, "CT weapon trait generation requires debug logger")
    local _rt_register = assert(ctx.rt_register,
        "CT weapon trait generation requires regression registrar")

    local state = mod._ct_weapon_trait_generation_state
    if not state then
        state = { all_trait_combos_cache = nil }
        mod._ct_weapon_trait_generation_state = state
    end
    state.effective_setting = effective_setting
    state.dbg = _dbg

    -- CLARIFY: Builds the union of all trait-combinations across all CW weapons, deduplicated. Used
    -- when "Any Trait on Any Weapon" is enabled — every weapon gets the FULL pool of trait combos
    -- instead of its baked subset. The dedupe key uses "\0" as separator since trait names can't
    -- contain null bytes; this avoids ambiguity (e.g. `{"a","bc"}` vs `{"ab","c"}`).
    -- The cache is stable during one enabled session and is invalidated by the
    -- owner's disable/reset contract before a later session rebuilds game data.
    local function get_all_trait_combos()
        if state.all_trait_combos_cache then
            return state.all_trait_combos_cache
        end
        if not DeusWeapons then
            return nil
        end

        local combos = {}
        local seen = {}
        for _, data in pairs(DeusWeapons) do
            local baked = data.baked_trait_combinations
            if baked then
                for _, combo in ipairs(baked) do
                    local key = table.concat(combo, "\0")
                    if not seen[key] then
                        seen[key] = true
                        combos[#combos + 1] = combo
                    end
                end
            end
        end

        state.all_trait_combos_cache = combos
        return combos
    end

    -- CLARIFY: Trait filter has three behaviors based on the `any_trait_any_weapon` toggle and the
    -- ban list. The base pool is either the weapon's vanilla trait combos or the global expanded pool.
    -- Then any combo containing a banned trait is removed from `filtered`.
    -- The new_value selection logic:
    --   - filtered partially shrunk (some bans hit, some left): use filtered
    --   - filtered emptied (every combo had a ban): keep `base` so the weapon isn't unrollable —
    --     a fully-banned weapon would crash the upgrade UI when no traits can be picked
    --   - filtered unchanged but `expanded_pool` differs from original: use base (= expanded_pool)
    --   - filtered unchanged and base==original: skip (no patch needed)
    -- POTENTIAL BUG (LOW): When `filtered` is empty, falling back to `base` means banned traits CAN
    -- still appear on that weapon. This is a reasonable graceful-degradation choice but the UI tooltip
    -- doesn't tell the user.
    local function apply_weapon_trait_filter()
        if not DeusWeapons then
            return {}
        end

        local any_trait = state.effective_setting("any_trait_any_weapon")
        -- #119/#260: when "Any Trait on Any Weapon" is on, expand each weapon's pool to the
        -- full trait UNION of its OWN combat class (melee or ranged), NOT the cross-slot global
        -- union that get_all_trait_combos() returns. This lifts the weapon-TYPE restriction (any
        -- trait allowed within the slot, #119) while STRICTLY preserving the melee/ranged split
        -- (no melee trait leaks onto a ranged weapon or vice versa, #260) - matching the
        -- tier-by-rarity path's class-union rule (get_tier_filtered_combos / _ct_get_trait_class_pools).
        -- Falls back to the old global union only if WeaponTraits.combinations isn't loaded yet,
        -- so early-timing rolls behave exactly as before.
        local slot_pools = any_trait and mod._ct_get_trait_class_pools()
        local melee_expanded, ranged_expanded
        if slot_pools then
            melee_expanded, ranged_expanded = {}, {}
            for trait in pairs(slot_pools.melee) do melee_expanded[#melee_expanded + 1] = { trait } end
            for trait in pairs(slot_pools.ranged) do ranged_expanded[#ranged_expanded + 1] = { trait } end
        end
        local global_expanded = (any_trait and not slot_pools) and get_all_trait_combos()
        local saved = {}

        for item_key, data in pairs(DeusWeapons) do
            local original = data.baked_trait_combinations
            local expanded_pool
            if any_trait then
                if slot_pools then
                    local ttn = data.trait_table_name
                    local is_ranged = type(ttn) == "string" and not ttn:find("melee")
                    local slot_list = is_ranged and ranged_expanded or melee_expanded
                    if slot_list and #slot_list > 0 then
                        expanded_pool = slot_list
                    end
                else
                    expanded_pool = global_expanded
                end
            end
            local base = expanded_pool or original
            if base then
                local filtered = {}
                for _, combo in ipairs(base) do
                    local keep = true
                    for _, trait in ipairs(combo) do
                        if mod._ct_umbrella_policy.banned(
                            state.effective_setting("ban_all_traits"),
                            state.effective_setting("ban_trait_" .. trait)) then
                            keep = false
                            break
                        end
                    end
                    if keep then
                        filtered[#filtered + 1] = combo
                    end
                end

                local new_value
                if #filtered < #base and #filtered > 0 then
                    new_value = filtered
                elseif #filtered == 0 then
                    new_value = base
                elseif base ~= original then
                    new_value = base
                end

                if new_value and new_value ~= original then
                    saved[item_key] = original
                    data.baked_trait_combinations = new_value
                end
            end
        end

        return saved
    end

    local function restore_weapon_trait_filter(saved)
        if not DeusWeapons then
            return
        end

        for item_key, original in pairs(saved) do
            DeusWeapons[item_key].baked_trait_combinations = original
        end
    end

    -- ============================================================
    -- Trait Tier by Rarity (v0.7.28a-alpha)
    -- ============================================================
    -- TRAIT_RARITY_POOL: maps every weapon trait → set of rarities at which it can roll.
    -- Walked all 34 traits with the user 2026-05-15; basis lives in TRAITS_REFERENCE.md.
    -- T1=common (green), T2=rare (blue), T3=exotic (orange), T4=unique (red).
    -- Multi-tier means the trait is eligible in multiple rarity pools.
    --
    -- When `tweak_trait_tier_by_rarity` is on, every weapon roll/upgrade picks a trait
    -- combo whose ALL traits are eligible for the rolled rarity. Implementation: hook the
    -- public DeusWeaponGeneration methods, call vanilla, then overwrite result.traits with
    -- a tier-filtered random pick. This ALSO enables traits at common/rare rarities (which
    -- vanilla skips per `deus_weapon_generation.lua:166-169`) because we don't rely on the
    -- vanilla rarity gate — we pick from the original baked_trait_combinations and filter.
    local TRAIT_RARITY_POOL = {
        -- T1 only (common / green)
        melee_increase_damage_on_block                = { common = true },
        melee_reduce_cooldown_on_crit                 = { common = true },
        melee_shield_on_assist                        = { common = true },
        melee_timed_block_cost                        = { common = true },
        ranged_reduce_cooldown_on_crit                = { common = true },
        ranged_restore_stamina_headshot               = { common = true },
        shield_splinters                              = { common = true },
        deus_ammo_pickup_reload_speed                 = { common = true },
        deus_big_swing_stagger                        = { common = true },
        -- T2 only (rare / blue)
        melee_heal_on_crit                            = { rare = true },
        ranged_consecutive_hits_increase_power        = { rare = true },
        ranged_increase_power_level_vs_armour_crit    = { rare = true },
        ranged_reduced_overcharge                     = { rare = true },
        ranged_remove_overcharge_on_crit              = { rare = true },
        melee_counter_push_power                      = { rare = true },
        bloodthirst                                   = { rare = true },
        headhunter                                    = { rare = true },
        follow_up                                     = { rare = true },
        -- T3 only (exotic / orange)
        shield_of_isha                                = { exotic = true },
        stagger_aoe_on_crit                           = { exotic = true },
        serrated_blade                                = { exotic = true },
        melee_attack_speed_on_crit                    = { exotic = true },
        -- T4 only (unique / red)
        armor_breaker                                 = { unique = true },
        refilling_shot                                = { unique = true },
        home_run                                      = { unique = true },
        deus_crit_chain_lightning                     = { unique = true },
        deus_extra_shot                               = { unique = true },
        always_blocking                               = { unique = true },
        -- T2 + T3
        ranged_replenish_ammo_on_crit                 = { rare = true, exotic = true },
        ranged_replenish_ammo_headshot                = { rare = true, exotic = true },
        -- T3 + T4
        piercing_projectiles                          = { exotic = true, unique = true },
        crescendo_strike                              = { exotic = true, unique = true },
        deus_collateral_damage_on_melee_killing_blow  = { exotic = true, unique = true },
        deus_ranged_crit_explosion                    = { exotic = true, unique = true },
    }

    -- v0.7.177-dev #119: Trait Tier by Rarity must NOT restrict by weapon TYPE.
    -- The user assigns each trait to one-or-more rarity tiers via TRAIT_RARITY_POOL; the
    -- ONLY other restriction they want is melee-vs-ranged (a melee weapon gets melee
    -- traits, a ranged weapon gets ranged traits). The PRE-#119 implementation read the
    -- weapon's OWN `baked_trait_combinations`, which the vanilla baker had already narrowed
    -- by `compatible_weapon_list` (a weapon-TYPE restriction).
    mod._ct_get_trait_class_pools = function()
        if mod._ct_trait_class_pools then return mod._ct_trait_class_pools end
        local WT = rawget(_G, "WeaponTraits")
        if not WT or not WT.combinations then return nil end
        local melee, ranged = {}, {}
        for pool_name, combos in pairs(WT.combinations) do
            if type(pool_name) == "string" and pool_name:find("^deus_") then
                local dest = pool_name:find("melee") and melee or ranged
                for _, combo in ipairs(combos) do
                    for _, trait in ipairs(combo) do
                        dest[trait] = true
                    end
                end
            end
        end
        mod._ct_trait_class_pools = { melee = melee, ranged = ranged }
        return mod._ct_trait_class_pools
    end

    -- Returns single-trait combos eligible for `rarity` on the weapon's COMBAT CLASS
    -- (melee/ranged), drawn from the class-wide union (see #119 note above). The ban list
    -- is honored here too (a banned trait never appears). Falls back to the weapon's own
    -- baked pool ONLY if WeaponTraits.combinations isn't loaded yet, so a roll never crashes.
    local function get_tier_filtered_combos(item_key, rarity)
        if not DeusWeapons or not DeusWeapons[item_key] then return {} end
        local data = DeusWeapons[item_key]
        local pools = mod._ct_get_trait_class_pools()
        if pools then
            local ttn = data.trait_table_name
            local is_ranged = type(ttn) == "string" and not ttn:find("melee")
            local class_pool = is_ranged and pools.ranged or pools.melee
            local filtered = {}
            for trait in pairs(class_pool) do
                local rp = TRAIT_RARITY_POOL[trait]
                if rp and rp[rarity] and not mod._ct_umbrella_policy.banned(
                    state.effective_setting("ban_all_traits"),
                    state.effective_setting("ban_trait_" .. trait)) then
                    filtered[#filtered + 1] = { trait }
                end
            end
            return filtered
        end

        local original = data.baked_trait_combinations
        if not original then return {} end
        local filtered = {}
        for _, combo in ipairs(original) do
            local all_eligible = true
            for _, trait in ipairs(combo) do
                local pool = TRAIT_RARITY_POOL[trait]
                if not pool or not pool[rarity] then
                    all_eligible = false
                    break
                end
            end
            if all_eligible then
                filtered[#filtered + 1] = combo
            end
        end
        return filtered
    end

    local function tier_by_rarity_class_union_ranged_check()
        if not DeusWeapons then return "skip: DeusWeapons not loaded" end
        local pools = mod._ct_get_trait_class_pools()
        if not pools then return "skip: WeaponTraits.combinations not loaded" end
        local fire_key
        for k, data in pairs(DeusWeapons) do
            if type(data) == "table" and data.trait_table_name == "deus_ranged_heat" then
                fire_key = k
                break
            end
        end
        if not fire_key then return "skip: no deus_ranged_heat weapon found (vanilla data changed?)" end
        local combos = get_tier_filtered_combos(fire_key, "rare")
        if #combos == 0 then
            return string.format("TIER-UNION REGRESSION: ranged weapon '%s' got empty pool at rare (class union broken)", tostring(fire_key))
        end
        for _, combo in ipairs(combos) do
            for _, t in ipairs(combo) do
                if not pools.ranged[t] then
                    return string.format("TIER-UNION REGRESSION: ranged weapon '%s' offered non-ranged trait '%s'", tostring(fire_key), tostring(t))
                end
                local rp = TRAIT_RARITY_POOL[t]
                if not (rp and rp.rare) then
                    return string.format("TIER-UNION REGRESSION: weapon '%s' offered '%s' not eligible at rare tier", tostring(fire_key), tostring(t))
                end
            end
        end
    end

    local function override_traits_in_result(result, rarity)
        if not state.effective_setting("tweak_trait_tier_by_rarity") then return result end
        if not result or not result.deus_item_key then return result end
        if rarity == "plentiful" then return result end
        local combos = get_tier_filtered_combos(result.deus_item_key, rarity)
        if #combos == 0 then return result end
        local picked = combos[math.random(#combos)]
        local new_traits = {}
        for _, trait in ipairs(picked) do
            new_traits[#new_traits + 1] = trait
        end
        result.traits = new_traits
        return result
    end

    -- #221 adversarial completion: strip only the detached generated result
    -- after every generation/upgrade path (and after tier override).
    function mod._ct_strip_banned_traits_from_result(result)
        if type(result) ~= "table" then return result end
        local traits, removed = mod._ct_umbrella_policy.filter_traits(
            state.effective_setting("ban_all_traits"), result.traits, function(trait)
                return state.effective_setting("ban_trait_" .. tostring(trait))
            end)
        if removed > 0 then result.traits = traits end
        return result
    end

    -- Wrap the apply/vanilla/restore bracket so DeusWeapons is restored even
    -- when vanilla raises. The `(n,args)` pair preserves nilable trailing args.
    local function _filtered_weapon_gen(label, func, gen_rarity, n, args)
        local saved = apply_weapon_trait_filter()
        local ok, result = pcall(function() return func(unpack(args, 1, n)) end)
        restore_weapon_trait_filter(saved)
        if not ok then
            if label == "generate_weapon_for_slot" then
                state.dbg("[trait-filter] %s vanilla call raised (benign — caller pcall-guards; "
                    .. "root is vanilla empty-slot weapon_pool fassert, not the trait filter); "
                    .. "DeusWeapons restored: %s", label, tostring(result))
            else
                mod:warning("[trait-filter] %s vanilla call raised; DeusWeapons restored: %s",
                    label, tostring(result))
            end
            error(result, 2)
        end
        result = override_traits_in_result(result, gen_rarity)
        result = mod._ct_strip_banned_traits_from_result(result)
        -- #917: LAST mutation on the detached result - reapply the local
        -- player's preserved Adventure illusion. All gating (toggle, snapshot
        -- family match via matching_item_key, upgrade carry-from-prior-item,
        -- bot-mirror exclusion) lives inside the module; nil-safe when the
        -- module is absent (isolated offline loads of this file).
        local illusions = mod._ct_adventure_illusions
        if illusions and illusions.apply_to_result then
            result = illusions.apply_to_result(label, result,
                label == "upgrade_item" and args and args[1] or nil)
        end
        return result
    end

    state.filtered_weapon_gen = _filtered_weapon_gen
    state.tier_by_rarity_class_union_ranged_check =
        tier_by_rarity_class_union_ranged_check

    mod._ct_reset_weapon_trait_generation_caches = function()
        state.all_trait_combos_cache = nil
        mod._ct_trait_class_pools = nil
    end

    if state.installed then
        return false
    end

    _rt_register("tier_by_rarity_class_union_ranged", function()
        return state.tier_by_rarity_class_union_ranged_check()
    end)

    mod:hook("DeusWeaponGeneration", "generate_weapon", function(func, difficulty, run_progress, rarity, ...)
        return state.filtered_weapon_gen("generate_weapon", func, rarity,
            select("#", ...) + 3, { difficulty, run_progress, rarity, ... })
    end)

    mod:hook("DeusWeaponGeneration", "generate_weapon_for_slot", function(func, difficulty, run_progress, rarity, ...)
        return state.filtered_weapon_gen("generate_weapon_for_slot", func, rarity,
            select("#", ...) + 3, { difficulty, run_progress, rarity, ... })
    end)

    mod:hook("DeusWeaponGeneration", "generate_item_from_item_key", function(func, item_key, difficulty, run_progress, rarity, ...)
        return state.filtered_weapon_gen("generate_item_from_item_key", func, rarity,
            select("#", ...) + 4, { item_key, difficulty, run_progress, rarity, ... })
    end)

    mod:hook("DeusWeaponGeneration", "upgrade_item", function(func, item, difficulty, run_progress, target_rarity, ...)
        return state.filtered_weapon_gen("upgrade_item", func, target_rarity,
            select("#", ...) + 4, { item, difficulty, run_progress, target_rarity, ... })
    end)

    state.installed = true
    mod._ct_weapon_trait_generation_installed = true
    return true
end
