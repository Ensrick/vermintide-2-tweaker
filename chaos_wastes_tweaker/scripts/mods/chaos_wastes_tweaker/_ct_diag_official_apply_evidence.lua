-- Finite selected-fix evidence only. No hooks, RPCs, packages or engine writes.
-- Receipts contain scalars only; all manual checks resolve current owners afresh.
return function(mod, ctx)
    local E = {}
    local effective = assert(ctx.effective_setting)
    local last, budgets, scope = {}, {}, nil
    local function finite(n) return type(n) == "number" and n == n and math.abs(n) < math.huge end
    local function scalar(v)
        local kind = type(v)
        if kind ~= "string" and kind ~= "number" and kind ~= "boolean" and kind ~= "nil" then return "<non-scalar>" end
        return tostring(v):gsub("[%c|]", " "):sub(1, 180)
    end
    local function controller()
        local ok, rc = pcall(function()
            local mechanism = Managers and Managers.mechanism and Managers.mechanism:game_mechanism()
            return mechanism and mechanism.get_deus_run_controller and mechanism:get_deus_run_controller()
        end)
        if ok then return rc end
    end
    local function run_id(rc)
        local ok, id = pcall(function() return rc and rc.get_run_id and rc:get_run_id() end)
        if ok then return id end
    end
    local function context()
        local rc = controller()
        local ok, current = pcall(function() return LevelHelper and LevelHelper:current_level_settings() end)
        if not ok then current = nil end
        local level = current and current.level_id or "?"
        local key = tostring(rc) .. ":" .. tostring(run_id(rc)) .. ":" .. tostring(rc and rc._ct_evidence_generation) .. ":" .. tostring(level)
        if key ~= scope then scope, last, budgets = key, {}, {} end
        return rc, level, key
    end
    local function result(status, detail, fields)
        return { status = status, reason = detail, fields = fields or {} }
    end
    local function render(feature, r)
        local fields = {}
        for key, value in pairs(r.fields or {}) do fields[#fields + 1] = scalar(key) .. "=" .. scalar(value) end
        table.sort(fields)
        return "[ct:" .. feature .. "] " .. r.status .. " " .. scalar(r.reason) .. " | " .. table.concat(fields, " ")
    end
    function E.record(feature, label, fields)
        local _, level, key = context()
        local copied = { level = level, role = Managers and Managers.player and Managers.player.is_server == true and "host" or "client" }
        local rc = controller()
        copied.run_id = run_id(rc)
        for name, value in pairs(fields or {}) do
            local kind = type(value)
            if kind == "string" or kind == "number" or kind == "boolean" then copied[name] = value end
        end
        local signature = render(feature, result("APPLY_OBSERVED", label, copied))
        if last[feature] and last[feature].signature == signature then return end
        last[feature] = { scope = key, fields = copied, label = label, signature = signature }
        local used = budgets[feature] or 0
        if used >= 24 then return end
        budgets[feature] = used + 1
        if rawget(_G, "printf") then pcall(printf, "%s", render(feature, result("APPLY_OBSERVED", label, copied))) end
    end
    function E.call(name, ...)
        if type(E[name]) == "function" then pcall(E[name], ...) end
    end
    local function recent(feature)
        local _, _, key = context()
        local receipt = last[feature]
        if not receipt or receipt.scope ~= key then return result("SKIP", "no current-context apply receipt") end
        return result("SKIP", "historical apply readback only; live interaction/geometry not observable from keep", receipt.fields)
    end
    local function player_extension(system)
        local manager = Managers and Managers.player
        local player = manager and manager.local_player and manager:local_player()
        local unit = player and player.player_unit
        if not (unit and Unit and Unit.alive(unit) and ScriptUnit and ScriptUnit.has_extension) then return nil end
        return ScriptUnit.has_extension(unit, system)
    end
    function E.coins()
        local rc = context()
        local receipt = rc and rc._ct_starting_coins_receipt
        if not receipt then return result("SKIP", "no current setup receipt") end
        local fields = { incoming = receipt.incoming, local_raw = receipt.local_raw, host_effective = receipt.effective,
            requested = receipt.requested, expected = receipt.expected, actual_initial = receipt.actual,
            readable = receipt.readable == true, authority = receipt.authority, generation = receipt.generation }
        if rc.get_own_peer_id and rc.get_player_soft_currency then fields.current_spendable = rc:get_player_soft_currency(rc:get_own_peer_id()) end
        if not receipt.configured then return result("SKIP", "PASS_THROUGH invalid/unconfigured setting", fields) end
        if receipt.requested ~= receipt.expected then return result("FAIL", "setup argument differs from exact baseline", fields) end
        if receipt.authority ~= "host" then return result("SKIP", "PENDING client setup is asynchronous; no host initial readback proof", fields) end
        if not receipt.readable then return result("SKIP", "initial readback unavailable", fields) end
        if receipt.actual ~= receipt.expected then return result("FAIL", "initial readback differs from exact baseline", fields) end
        return result("PASS", "APPLIED host initial readback; current balance is not initial balance", fields)
    end
    function E.graph()
        local rc = context()
        local graph = rc and rc._path_graph
        if type(graph) ~= "table" then return result("SKIP", "no current Citadel graph") end
        local gods = { "nurgle", "tzeentch", "khorne", "slaanesh" }
        local finale = gods[effective("finale_dominant_god")]
        if not finale then return result("SKIP", "finale override disabled") end
        local approach = gods[effective("finale_approach_god")] or finale
        local found, scanned, bad = 0, 0, 0
        for _, node in pairs(graph) do
            scanned = scanned + 1
            if scanned > 512 then return result("SKIP", "graph census truncated") end
            if type(node) == "table" and type(node.level) == "string" then
                local base = node.level:match("^(arena_citadel)_") or node.level:match("^(sig_citadel)_")
                if base then
                    found = found + 1
                    local god = base == "arena_citadel" and finale or approach
                    if node.theme ~= god or node.god ~= god or not node.level:find("^" .. base .. "_" .. god .. "_path%d+$") then bad = bad + 1 end
                end
            end
        end
        if found == 0 then return result("SKIP", "no Citadel approach/finale nodes") end
        return result(bad == 0 and "PASS" or "FAIL", "fresh graph level/theme/god only; curse/map rendering remains live acceptance",
            { nodes = found, mismatches = bad, finale = finale, approach = approach })
    end
    function E.anath(ext)
        local enabled = effective("tweak_anath_raema_permanent") == true
        local repairs = mod._ct_official_boon_repairs
        local entries = repairs and repairs.anath_entries() or {}
        if #entries == 0 then return result("SKIP", "current Anath registry unavailable") end
        local registry_bad = 0
        for _, entry in ipairs(entries) do
            local buffs = entry.tbl[entry.key] and entry.tbl[entry.key].buffs
            local child = buffs and buffs[1]
            if enabled and not (buffs and #buffs == 1 and child.name == "deus_ammo_pickup_reload_speed_permanent"
                and child.stat_buff == "reload_speed" and child.multiplier == -0.5 and child.event == nil and child.duration == nil) then registry_bad = registry_bad + 1 end
        end
        if registry_bad > 0 then return result("FAIL", "current registry differs from permanent-child contract", { registries = #entries, bad = registry_bad }) end
        ext = ext or player_extension("buff_system")
        if not ext then return result("SKIP", "no current player buff extension", { enabled = enabled, registries = #entries }) end
        if (tonumber(ext._num_buffs) or 0) > 512 then return result("SKIP", "active buff census truncated") end
        local active, malformed = 0, 0
        for i = 1, math.min(tonumber(ext._num_buffs) or #(ext._buffs or {}), 512) do
            local buff = ext._buffs and ext._buffs[i]
            if buff and buff.buff_template_name == "deus_ammo_pickup_reload_speed" then
                active = active + 1
                local template = buff.template or buff
                if enabled and not (buff.buff_type == "deus_ammo_pickup_reload_speed_permanent" and template.stat_buff == "reload_speed"
                    and template.multiplier == -0.5 and template.event == nil and template.duration == nil
                    -- Native add resolves optional overrides into these live fields;
                    -- _add_stat_buff consumes buff.multiplier, not the template value.
                    and buff.multiplier == -0.5 and buff.duration == nil
                    and (buff.bonus == nil or buff.bonus == 0)) then malformed = malformed + 1 end
            end
        end
        local child_count = ext.num_buff_type and ext:num_buff_type("deus_ammo_pickup_reload_speed_permanent")
        local fields = { enabled = enabled, registries = #entries, parent_children = active, permanent_children = child_count,
            malformed = malformed, total_reload_scale = ext.apply_buffs_to_value and ext:apply_buffs_to_value(1, "reload_speed") }
        if active == 0 then return result("SKIP", "trait not currently active/wielded; registry alone is not active proof", fields) end
        if enabled and (active ~= 1 or child_count ~= 1 or malformed ~= 0) then return result("FAIL", "active permanent child is missing/duplicated/malformed", fields) end
        if not enabled then return result("SKIP", "off-control active timing requires gameplay observation", fields) end
        return result("PASS", "fresh single permanent active child; reload timing still gameplay acceptance", fields)
    end
    function E.anath_registry(label)
        local repairs = mod._ct_official_boon_repairs
        for _, entry in ipairs(repairs and repairs.anath_entries() or {}) do
            local buffs = entry.tbl[entry.key] and entry.tbl[entry.key].buffs
            local sub = buffs and buffs[1]
            E.record("288", label, { registry = entry.id, children = buffs and #buffs or 0, child = sub and sub.name,
                stat = sub and sub.stat_buff, multiplier = sub and sub.multiplier, event = sub and sub.event or "nil",
                enabled = effective("tweak_anath_raema_permanent") == true })
        end
    end
    function E.anath_after(ext)
        local r = E.anath(ext)
        r.fields.status = r.status
        E.record("288", "post-native add active readback: " .. r.reason, r.fields)
    end
    function E.ammo_fields(ext)
        return { current = ext._current_ammo, reserve = ext._available_ammo, shots_fired = ext._shots_fired,
            max_ammo = ext._max_ammo, max_clip = ext._ammo_per_clip,
            usable_clip = ext.ammo_count and ext:ammo_count(), clip_size = ext.clip_size and ext:clip_size() }
    end
    function E.ammo_check(ext)
        local fields = E.ammo_fields(ext)
        for _, name in ipairs({ "current", "reserve", "shots_fired", "max_ammo", "max_clip", "usable_clip", "clip_size" }) do
            if fields[name] == nil then return result("SKIP", "non-conventional or unreadable ammo extension: " .. name, fields) end
            if not finite(fields[name]) then return result("FAIL", "invalid native ammo number: " .. name, fields) end
        end
        local bad = fields.reserve < 0 or fields.reserve > fields.max_ammo or fields.current < 0
            or fields.current > fields.max_ammo or fields.usable_clip < 0 or fields.usable_clip > fields.clip_size
            or fields.clip_size < 0 or fields.max_ammo < 0 or fields.clip_size ~= fields.max_clip
        return result(bad and "FAIL" or "PASS", "fresh native ammo_count/clip_size and reserve bounds; refresh coverage not implied", fields)
    end
    function E.ammo_applied(ext, before_current, before_reserve)
        local fields = E.ammo_fields(ext)
        fields.before_current, fields.before_reserve = before_current, before_reserve
        E.record("256", "refresh clamp applied/read back", fields)
    end
    function E.ammo()
        local inv = player_extension("inventory_system")
        local slot = inv and inv.get_slot_data and inv:get_slot_data("slot_ranged")
        if not slot then return result("SKIP", "no current ranged slot") end
        local checked, bad = 0, 0
        for _, key in ipairs({ "left_unit_1p", "right_unit_1p" }) do
            local unit = slot[key]
            local ext = unit and Unit.alive(unit) and ScriptUnit.has_extension(unit, "ammo_system")
            if ext then
                local r = E.ammo_check(ext)
                if r.status == "FAIL" then bad = bad + 1 end
                if r.status ~= "SKIP" then checked = checked + 1 end
                if rawget(_G, "printf") then pcall(printf, "%s", render("256", r)) end
            end
        end
        return result(bad > 0 and "FAIL" or checked > 0 and "PASS" or "SKIP", "fresh current ranged extensions", { checked = checked, bad = bad })
    end
    function E.pickup(unit, go_id, pickup_name, spawn_type)
        local storage = Managers and Managers.state and Managers.state.unit_storage
        local reverse = unit and go_id ~= nil and storage and storage.unit and storage:unit(go_id) == unit or false
        E.record("322", "spawn-return (not linked proof)", { pickup = pickup_name, go_id = go_id, unit_present = unit ~= nil,
            reverse = reverse, spawn_type = spawn_type })
    end
    function E.linked()
        local rc = context()
        if not rc then return result("SKIP", "no active CW controller") end
        local state = Managers and Managers.state
        local system = state and state.entity and state.entity:system("projectile_linker_system")
        local storage = state and state.unit_storage
        if not (system and type(system.linked_projectile_units) == "table" and storage and storage.go_id and storage.unit) then return result("SKIP", "current linker/storage unavailable") end
        local seen, linked, bad, scanned = {}, 0, 0, 0
        for _, units in pairs(system.linked_projectile_units) do
            for unit in pairs(units) do
                scanned = scanned + 1
                if scanned > 128 then return result("SKIP", "link census truncated", { linked_axes = linked, bad = bad }) end
                if not seen[unit] and Unit.alive(unit) then
                    seen[unit] = true
                    local ext = ScriptUnit.has_extension(unit, "pickup_system")
                    local name = ext and ext.pickup_name
                    if type(name) == "string" and name:find("throwing_axe", 1, true) then
                        linked = linked + 1
                        local id = storage:go_id(unit)
                        local reverse = id ~= nil and storage:unit(id) == unit
                        if not reverse then bad = bad + 1 end
                        if rawget(_G, "printf") then pcall(printf, "%s", render("322", result(reverse and "PASS" or "FAIL", "CURRENT linked pickup reverse identity",
                            { pickup = name, go_id = id, role = Managers.player.is_server == true and "host" or "client" }))) end
                    end
                end
            end
        end
        return result(bad > 0 and "FAIL" or linked > 0 and "PASS" or "SKIP", "invoke before axe recovery/link timeout; each peer separately", { linked_axes = linked, bad = bad })
    end
    function E.progression()
        local rc = context()
        if not (rc and rc._run_state and rc._run_state.get_completed_level_count and rc.get_run_difficulty) then return result("SKIP", "no current progression controller") end
        local completed = rc._run_state:get_completed_level_count()
        local actual = rc:get_run_difficulty()
        local start = rc._ct_progdiff_start
        if not start then return result("SKIP", "no immutable starting tier") end
        if type(Difficulties) ~= "table" or type(DifficultyLookup) ~= "table"
            or Difficulties[DifficultyLookup[start]] ~= start then return result("SKIP", "starting tier is not currently registered") end
        local expected = start
        local enabled = effective("progressive_difficulty") == true and effective("progressive_difficulty_increase") == true
        if enabled then expected = ctx.runtime.progressive.difficulty(start, completed, Difficulties, DifficultyLookup) end
        local fields = { completed = completed, start = start, expected = expected, returned = actual, enabled = enabled,
            coin_reduction = effective("progressive_coin_reduction"), master = effective("progressive_difficulty") }
        if not enabled then return result("SKIP", "disabled control; original native difficulty retained", fields) end
        return result(actual == expected and "PASS" or "FAIL", "fresh controller getter; world difficulty/coin spending remain live acceptance", fields)
    end
    function E.coin_applied(rc, raw, credit, before)
        local after = rc:get_player_soft_currency(rc:get_own_peer_id())
        E.record("460credit", "native coin credit readback", { raw = raw, effective_credit = credit, before = before, after = after,
            delta = finite(before) and finite(after) and after - before or nil,
            readback_matches = finite(before) and finite(after) and finite(credit) and after - before == credit })
    end
    function E.chests()
        local cap = mod._ct_official_chest_cap
        if not (controller() and cap and cap.inspect) then return result("SKIP", "no current CW census owner") end
        return cap.inspect()
    end
    local verifiers = {
        coins = E.coins, ct_citadel = E.graph, ct_anath_raema = E.anath,
        ct_ammo_bounds = E.ammo, ct_linked_pickups = E.linked, ct_progression = E.progression,
        ct_chest_cap = E.chests, ct_altar_reroll = function() return recent("252") end,
        ct_trial_placement = function() return recent("471") end,
    }
    function E.verify(name)
        local verifier = assert(verifiers[name], "unknown verifier")
        local ok, value = pcall(verifier)
        if not ok then return result("SKIP", "live readback unavailable/throwing: " .. scalar(value)) end
        return value
    end
    function E.command(name)
        local r = E.verify(name)
        local line = render(name, r)
        if rawget(_G, "printf") then pcall(printf, "%s", line) end
        pcall(mod.echo, mod, "%s", line)
        return r
    end
    local function runtime_check(feature)
        return function()
            local r = E.verify(feature)
            if r.status == "PASS" then return nil end
            if r.status == "SKIP" then return { status = "SKIP", reason = r.reason } end
            return r.reason
        end
    end
    if ctx.rt_register then
        ctx.rt_register("ct_initial_coins_readback_912", runtime_check("coins"))
        ctx.rt_register("ct_citadel_graph_readback_146", runtime_check("ct_citadel"))
        ctx.rt_register("ct_anath_raema_active_288", runtime_check("ct_anath_raema"))
        ctx.rt_register("ct_meta_ammo_current_floor_256", runtime_check("ct_ammo_bounds"))
        ctx.rt_register("ct_linked_pickup_identity_322", runtime_check("ct_linked_pickups"))
        ctx.rt_register("ct_progression_readback_460", runtime_check("ct_progression"))
        ctx.rt_register("ct_chest_count_live_60", runtime_check("ct_chest_cap"))
        ctx.rt_register("ct_altar_prompt_readback_252", runtime_check("ct_altar_reroll"))
        ctx.rt_register("ct_trial_placement_readback_471", runtime_check("ct_trial_placement"))
    end
    -- Literal registration keeps the exact runnable surface source-auditable.
    mod:command("verify_ct_citadel", "Read current Citadel graph; unavailable context skips", function() return E.command("ct_citadel") end)
    mod:command("verify_ct_anath_raema", "Read current active reload child; unavailable context skips", function() return E.command("ct_anath_raema") end)
    mod:command("verify_ct_ammo_bounds", "Read current ranged ammo bounds; unavailable context skips", function() return E.command("ct_ammo_bounds") end)
    mod:command("verify_ct_linked_pickups", "Read current linked axe identities; unavailable context skips", function() return E.command("ct_linked_pickups") end)
    mod:command("verify_ct_progression", "Read current progression; unavailable context skips", function() return E.command("ct_progression") end)
    mod:command("verify_ct_chest_cap", "Read current settled chest census; unavailable context skips", function() return E.command("ct_chest_cap") end)
    mod:command("verify_ct_altar_reroll", "Read historical altar prompt receipt, not live proof", function() return E.command("ct_altar_reroll") end)
    mod:command("verify_ct_trial_placement", "Read historical trial placement receipt, not live proof", function() return E.command("ct_trial_placement") end)
    mod:command("ct_verify_anath_raema", "Alias for /verify_ct_anath_raema", function() return E.command("ct_anath_raema") end)
    return E
end
