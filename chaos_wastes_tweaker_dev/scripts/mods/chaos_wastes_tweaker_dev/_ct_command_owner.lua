-- _ct_command_owner.lua -- CT-dev diagnostics and maintenance commands.
--
-- Behavior-neutral extraction from the entry. The installer retains the exact
-- 13-command registration order; game globals remain late-bound in callbacks.
--
-- Owned by: chaos_wastes_tweaker_dev.lua entry point.
-- Consumed via: one ordered mod:dofile installer call; guarded by
-- qa/lua/tests/test_ct_command_owner.lua.
return function(ctx)
    assert(type(ctx) == "table", "CT command owner requires context")
    local mod = assert(ctx.mod, "CT command owner requires mod")
    local AdventurePool = assert(ctx.adventure_pool, "CT command owner requires adventure pool")
    local _dump_pickup_system_state = assert(ctx.dump_pickup_system_state,
        "CT command owner requires pickup dump")
    local effective_setting = assert(ctx.effective_setting,
        "CT command owner requires effective-setting accessor")
    local MOD_VERSION = assert(ctx.mod_version, "CT command owner requires mod version")

-- ============================================================
-- Debug commands
-- ============================================================

mod:command("dump_spawners", "Dump pickup_settings + live PickupSystem spawner counts by category (Issue #58)", function()
    -- v0.7.125-dev: delegates to _dump_pickup_system_state so both the in-game
    -- on-demand command and the automatic mission_start dump produce identical
    -- output. Echoes a brief one-line summary to chat; full per-category
    -- breakdown lands in the log.
    pcall(_dump_pickup_system_state, "[pickup_dump]", true)
    mod:echo("Done. Full per-category breakdown in log.")
end)

mod:command("dump_potions", "Dump resolved in-game names for every CW potion (potion_*_01 in ItemMasterList)", function()
    local iml = rawget(_G, "ItemMasterList")
    if not iml then
        mod:echo("ItemMasterList not loaded.")
        return
    end
    local sorted = {}
    for key, entry in pairs(iml) do
        if type(entry) == "table" and entry.slot_type == "potion" then
            sorted[#sorted + 1] = key
        end
    end
    table.sort(sorted)
    local count = 0
    for _, key in ipairs(sorted) do
        local entry = iml[key]
        local display_raw = Localize(key)
        local display = (display_raw ~= "<" .. key .. ">") and display_raw or "(no display loc)"
        local desc_key = entry.description
        local desc_raw = desc_key and Localize(desc_key) or ""
        local desc = (desc_key and desc_raw ~= "<" .. desc_key .. ">") and desc_raw or "(no description loc)"
        local tmpl = entry.temporary_template or "(none)"
        pcall(printf, "[DUMP:potions] %s\tdisplay='%s'\ttemplate=%s\tdesc='%s'", key, display, tmpl, desc)
        count = count + 1
    end
    mod:echo(string.format("dump_potions: %d potions dumped to log.", count))
end)

mod:command("dump_boon_loc", "Dump resolved display names and descriptions for all boons", function()
    if not DeusPowerUpTemplates or not DeusPowerUpsArray then
        mod:echo("DeusPowerUpTemplates not loaded (must be in Chaos Wastes).")
        return
    end

    local sorted_keys = {}
    for key in pairs(DeusPowerUpTemplates) do
        sorted_keys[#sorted_keys + 1] = key
    end
    table.sort(sorted_keys)

    local count = 0
    for _, key in ipairs(sorted_keys) do
        local tpl = DeusPowerUpTemplates[key]
        local display_key = tpl.display_name
        local desc_key = tpl.advanced_description

        local display_text = ""
        if display_key then
            local raw = Localize(display_key)
            if raw ~= "<" .. display_key .. ">" then
                display_text = raw
            end
        end

        local desc_text = ""
        if desc_key then
            local raw = Localize(desc_key)
            if raw ~= "<" .. desc_key .. ">" then
                desc_text = raw
            end
        end

        pcall(printf, "[DUMP:boon_loc] %s\t%s\t%s", key, display_text, desc_text)
        count = count + 1
    end

    mod:echo(string.format("dump_boon_loc: %d boons dumped to log. Check console log for tab-separated output.", count))
end)

mod:command("ct_boon_price_audit", "Re-run the bounded #467 live boon tier/price census", function()
    mod._ct467_audit_done = false
    local mechanism = Managers and Managers.mechanism
        and Managers.mechanism.game_mechanism and Managers.mechanism:game_mechanism()
    local run_controller = mechanism and mechanism.get_deus_run_controller
        and mechanism:get_deus_run_controller()
    local report = mod._ct_boon_price_audit_once(true, run_controller)
    if report then
        mod:echo("Boon price census written to the log: %d live rows.", report.total)
    else
        mod:echo("Boon price census unavailable; enter Chaos Wastes and try again.")
    end
end)

mod:command("ct_boon_price_status", "Report individual boon-price coverage for issue #467", function()
    if not mod._ct_boon_pricing_runtime then
        mod:echo("[ct:467] individual boon pricing runtime unavailable")
        return
    end
    local report = mod._ct_boon_pricing_runtime.summary()
    mod:echo("[ct:467] Individual Boon Prices=%s catalog=%d/%d overrides=%d missing=%d",
        tostring(effective_setting("ct_individual_boon_prices")), report.priced,
        report.total, report.overrides, #report.missing)
end)

mod:command("dump_boons", "Deep dump of all DeusPowerUpTemplates + buff data to log", function(filter)
    if not DeusPowerUpTemplates then
        mod:echo("DeusPowerUpTemplates not loaded (must be in Chaos Wastes).")
        return
    end

    local function dump_table(tbl, prefix, lines, depth)
        if depth > 6 then
            lines[#lines + 1] = prefix .. "... (max depth)"
            return
        end
        local keys = {}
        for k in pairs(tbl) do keys[#keys + 1] = k end
        table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
        for _, k in ipairs(keys) do
            local v = tbl[k]
            local key_str = prefix .. tostring(k)
            if type(v) == "table" then
                lines[#lines + 1] = key_str .. " = {"
                dump_table(v, prefix .. "  ", lines, depth + 1)
                lines[#lines + 1] = prefix .. "}"
            elseif type(v) == "function" then
                lines[#lines + 1] = key_str .. " = [function]"
            else
                lines[#lines + 1] = key_str .. " = " .. tostring(v) .. "  (" .. type(v) .. ")"
            end
        end
    end

    local function lookup_buff(name)
        if not name then return nil end
        local sources = {
            { rawget(_G, "DeusPowerUpBuffTemplates"), "DeusPowerUpBuffTemplates" },
            { rawget(_G, "BuffTemplates"), "BuffTemplates" },
            { rawget(_G, "NetworkedBuffTemplates"), "NetworkedBuffTemplates" },
        }
        for _, src in ipairs(sources) do
            if src[1] and src[1][name] then
                return src[1][name], src[2]
            end
        end
        return nil, nil
    end

    local sorted_keys = {}
    for key in pairs(DeusPowerUpTemplates) do
        if not filter or key:find(filter, 1, true) then
            sorted_keys[#sorted_keys + 1] = key
        end
    end
    table.sort(sorted_keys)

    local count = 0
    for _, key in ipairs(sorted_keys) do
        local tpl = DeusPowerUpTemplates[key]
        local lines = {}
        lines[#lines + 1] = "========== " .. key .. " =========="

        lines[#lines + 1] = "--- PowerUp Template ---"
        dump_table(tpl, "  ", lines, 0)

        local buff_name = tpl.buff_template_name or tpl.buff_name
        if buff_name then
            local buff_tpl, source = lookup_buff(buff_name)
            if buff_tpl then
                lines[#lines + 1] = "--- Buff Template: " .. buff_name .. " (from " .. source .. ") ---"
                dump_table(buff_tpl, "  ", lines, 0)
            else
                lines[#lines + 1] = "--- Buff Template: " .. buff_name .. " NOT FOUND in any buff table ---"
            end
        end

        for _, line in ipairs(lines) do
            pcall(printf, "[DUMP:boon_deep] %s", line)
        end
        count = count + 1
    end

    mod:echo(string.format("dump_boons: %d boons dumped to log%s", count,
        filter and (" matching '" .. filter .. "'") or ""))
end)

mod:command("dump_buffs", "Deep dump of all buff templates referenced by boons", function(filter)
    if not DeusPowerUpTemplates then
        mod:echo("DeusPowerUpTemplates not loaded (must be in Chaos Wastes).")
        return
    end

    local function dump_table(tbl, prefix, lines, depth)
        if depth > 6 then
            lines[#lines + 1] = prefix .. "... (max depth)"
            return
        end
        local keys = {}
        for k in pairs(tbl) do keys[#keys + 1] = k end
        table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
        for _, k in ipairs(keys) do
            local v = tbl[k]
            local key_str = prefix .. tostring(k)
            if type(v) == "table" then
                lines[#lines + 1] = key_str .. " = {"
                dump_table(v, prefix .. "  ", lines, depth + 1)
                lines[#lines + 1] = prefix .. "}"
            elseif type(v) == "function" then
                lines[#lines + 1] = key_str .. " = [function]"
            else
                lines[#lines + 1] = key_str .. " = " .. tostring(v) .. "  (" .. type(v) .. ")"
            end
        end
    end

    local buff_sources = {}
    local src_names = { "BuffTemplates", "NetworkedBuffTemplates", "DeusPowerUpBuffTemplates", "DeusBuffTemplates" }
    for _, name in ipairs(src_names) do
        local tbl = rawget(_G, name)
        if tbl then buff_sources[name] = tbl end
    end

    local function lookup_buff(name)
        for src_name, src_tbl in pairs(buff_sources) do
            if src_tbl[name] then return src_tbl[name], src_name end
        end
        return nil, nil
    end

    local refs = {}
    local function collect_refs(tbl, depth)
        if depth > 6 or type(tbl) ~= "table" then return end
        for k, v in pairs(tbl) do
            if type(v) == "string" and (k == "buff_to_add" or k == "buff_to_add_revived"
                or k == "cooldown_buff" or k == "full_heal_buff" or k == "removal_buff") then
                refs[v] = true
            elseif type(v) == "table" then
                if k == "buff_to_add" or k == "buff_to_add_revived" then
                    for _, name in pairs(v) do
                        if type(name) == "string" then refs[name] = true end
                    end
                else
                    collect_refs(v, depth + 1)
                end
            end
        end
    end

    for _, tpl in pairs(DeusPowerUpTemplates) do
        collect_refs(tpl, 0)
    end

    local sorted = {}
    for name in pairs(refs) do
        if not filter or name:find(filter, 1, true) then
            sorted[#sorted + 1] = name
        end
    end
    table.sort(sorted)

    local count = 0
    for _, name in ipairs(sorted) do
        local lines = {}
        local buff_tpl, source = lookup_buff(name)
        if buff_tpl then
            lines[#lines + 1] = "========== " .. name .. " (from " .. source .. ") =========="
            dump_table(buff_tpl, "  ", lines, 0)
            count = count + 1
        else
            lines[#lines + 1] = "========== " .. name .. " NOT FOUND =========="
        end
        for _, line in ipairs(lines) do
            pcall(printf, "[DUMP:buff_deep] %s", line)
        end
    end

    mod:echo(string.format("dump_buffs: %d/%d referenced buffs found%s", count, #sorted,
        filter and (" matching '" .. filter .. "'") or ""))
end)

mod:command("dump_mutators", "Dump all mutator templates to log", function(filter)
    local src = rawget(_G, "MutatorTemplates")
    if not src then
        mod:echo("MutatorTemplates not loaded.")
        return
    end

    local entries = {}
    for key, tpl in pairs(src) do
        if not filter or key:find(filter, 1, true) then
            entries[#entries + 1] = key
        end
    end
    table.sort(entries)

    for _, key in ipairs(entries) do
        local tpl = src[key]
        local line = string.format("%-40s display=%s",
            key, tostring(tpl.display_name or tpl.name or "?"))
        mod:echo(line)
        pcall(printf, "[DUMP:mutators] %s", line)
    end

    mod:echo(string.format("dump_mutators: %d templates", #entries))
end)

mod:command("dump_traits", "Dump every CW weapon trait that can roll, with localized display name and description", function(filter)
    if not DeusWeapons then
        mod:echo("DeusWeapons not loaded.")
        return
    end
    local WT = rawget(_G, "WeaponTraits")
    if not WT or not WT.traits then
        mod:echo("WeaponTraits.traits not loaded.")
        return
    end

    local rollable = {}
    for _, data in pairs(DeusWeapons) do
        local baked = data.baked_trait_combinations
        if baked then
            for _, combo in ipairs(baked) do
                for _, trait_name in ipairs(combo) do
                    rollable[trait_name] = true
                end
            end
        end
    end

    local sorted = {}
    for name in pairs(rollable) do
        if not filter or name:find(filter, 1, true) then
            sorted[#sorted + 1] = name
        end
    end
    table.sort(sorted)

    local function resolve(key)
        if not key then return "" end
        local raw = Localize(key)
        if raw and raw ~= "<" .. key .. ">" then
            return raw
        end
        return ""
    end

    pcall(printf, "[DUMP:traits] === %d rollable CW traits ===", #sorted)
    pcall(printf, "[DUMP:traits] trait_name\tdisplay_name_key\tdisplay_text\tdesc_key\tdesc_text")
    for _, name in ipairs(sorted) do
        local td = WT.traits[name]
        local dn_key = td and td.display_name or ""
        local desc_key = td and td.advanced_description or ""
        pcall(printf, "[DUMP:traits] %s\t%s\t%s\t%s\t%s",
            name, dn_key, resolve(dn_key), desc_key, resolve(desc_key))
    end
    mod:echo(string.format("dump_traits: %d traits dumped to log.", #sorted))
end)

-- Resolves the canonical in-game display name for every adventure level AND every
-- vanilla CW scenario in the catalog. Emits tab-separated rows to the log
-- (`[DUMP:adv_names]`) for paste-back into _adventure_pool.lua. The level's
-- `display_name` is a loc key that Localize() resolves to the English string. Works
-- in the keep or the CW hub — no need to be in a mission.
mod:command("dump_adventure_names", "Resolve in-game names for every adventure level + CW scenario", function()
    if not LevelSettings then
        mod:echo("LevelSettings not loaded.")
        return
    end

    local function resolve(key)
        if not key or key == "" then return "" end
        local raw = Localize(key)
        if raw and raw ~= "<" .. key .. ">" then return raw end
        return ""
    end

    pcall(printf, "[DUMP:adv_names] === ADVENTURE MISSIONS ===")
    pcall(printf, "[DUMP:adv_names] level_key\tdisplay_text\tdlc_name\tact\tlevel_bundle_path")
    for _, entry in ipairs(AdventurePool.ADVENTURE_MISSIONS) do
        local lvl = entry.key
        local v = rawget(LevelSettings, lvl)
        local dn_key = v and v.display_name or ""
        local level_name = v and v.level_name or ""
        local dlc_name = v and v.dlc_name or "(base)"
        local act = v and v.act or ""
        pcall(printf, "[DUMP:adv_names] %s\t%s\t%s\t%s\t%s", lvl, resolve(dn_key), dlc_name, act, level_name)
    end

    pcall(printf, "[DUMP:adv_names] === CW SCENARIOS ===")
    pcall(printf, "[DUMP:adv_names] cw_key\ttitle_key\tdisplay_text\tbase_level_name")
    for _, scen in ipairs(AdventurePool.CW_SCENARIOS) do
        local dls = rawget(DEUS_LEVEL_SETTINGS or {}, scen.key)
        -- CW levels' user-facing title is `<level_key>_title` per level_settings_morris.lua:112
        local title_key = scen.key .. "_title"
        local base = dls and dls.base_level_name or scen.key
        pcall(printf, "[DUMP:adv_names] %s\t%s\t%s\t%s", scen.key, title_key, resolve(title_key), base)
    end

    local total = #AdventurePool.ADVENTURE_MISSIONS + #AdventurePool.CW_SCENARIOS
    mod:echo(string.format("dump_adventure_names: %d entries dumped to log (%d adventures + %d CW).",
        total, #AdventurePool.ADVENTURE_MISSIONS, #AdventurePool.CW_SCENARIOS))
end)

mod:command("pool_status", "Dump current CW map-pool state (TRAVEL/SIGNATURE keys per journey)", function()
    AdventurePool.dump_pool_state()
end)

-- Manual re-run of pool injection. Useful for debugging: if you toggle settings in VMF
-- and want to see them take effect without restarting the game, run this from the keep
-- BEFORE entering a CW run. The engine reads LEVEL_AVAILABILITY at run setup
-- (DeusMechanism._setup_run); changes only take effect for the NEXT run, not the current one.
mod:command("force_inject_pool", "Re-run adventure pool injection now", function()
    if not mod:get("inject_adventure_maps") then
        mod:echo("inject_adventure_maps is OFF — enable it first.")
        return
    end
    local n = AdventurePool.inject_pool()
    mod:echo("inject_pool ran: " .. tostring(n) .. " adventures injected (check log for details).")
end)

mod:command("cw_status", "Show Chaos Wastes Tweaker state", function()
    mod:echo("Chaos Wastes Tweaker v" .. MOD_VERSION)
    mod:echo("  Altars: upgrade=" .. tostring(mod:get("chest_upgrade_count") or -1)
        .. " melee_swap=" .. tostring(mod:get("chest_swap_melee_count") or -1)
        .. " ranged_swap=" .. tostring(mod:get("chest_swap_ranged_count") or -1)
        .. " boon=" .. tostring(mod:get("chest_power_up_count") or -1)
        .. " (-1=Default, 0=zero)")
    mod:echo("  Chests of Trials: " .. tostring(mod:get("cursed_chest_count") or -1) .. " (-1=Default, 0=zero)")
    mod:echo("  Arena ammo: " .. tostring(mod:get("arena_ammo_count") or -1) .. " (-1=Default, 0=zero)")
    mod:echo("  Campaign potions: " .. tostring(mod:get("enable_campaign_potions") or false))
end)

end
