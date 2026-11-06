-- Selective official integration. The public wire catalog remains owned by
-- _ct_peer_parity_owner; this module registers no custom lookup entries.
return function(mod, ctx)
    local M = {}
    local effective = assert(ctx.effective_setting)
    local register = assert(ctx.rt_register)
    local function pack(...) return { n = select("#", ...), ... } end
    local function evidence(name, ...)
        local owner = mod._ct_apply_evidence
        if owner and owner.call then owner.call(name, ...) end
    end
    M.coins = mod:dofile("scripts/mods/chaos_wastes_tweaker/_ct_starting_coins_policy")
    M.progressive = mod:dofile("scripts/mods/chaos_wastes_tweaker/_ct_progressive_difficulty")
    M.umbrella = mod:dofile("scripts/mods/chaos_wastes_tweaker/_ct_umbrella_policy")
    M.ammo = mod:dofile("scripts/mods/chaos_wastes_tweaker/_ct_ammo_guard_core")
    M.placement = mod:dofile("scripts/mods/chaos_wastes_tweaker/_ct_cot_placement_policy")
    M.illusions = mod:dofile("scripts/mods/chaos_wastes_tweaker/_ct_adventure_illusions")({ mod = mod })
    mod._ct_ammo_guard_core = M.ammo
    mod._ct_umbrella_policy = M.umbrella
    M.progressive.install_hot_join(mod, ctx.rpc_schema)
    local grudge_marks = {
        commander=true, crippling=true, crushing=true, frenzy=true,
        intangible=true, periodic_curse=true, periodic_shield=true, raging=true,
        ranged_immune=true, regenerating=true, unstaggerable=true, vampiric=true,
        warping=true,
    }

    -- #221 composes masters with saved leaves; it never overwrites mod settings.
    function M.setting(name, value, read)
        if name:find("^altar_reuse_count_") or name:find("^altar_reuse_cost_mult_") then
            return M.umbrella.value(read("enable_altar_reuse"), value, 1)
        elseif name:find("^disable_curse_") then
            return M.umbrella.banned(read("disable_all_listed_curses"), value)
        elseif name:find("^ban_trait_") then
            return M.umbrella.banned(read("ban_all_traits"), value)
        elseif name:find("^ban_grudge_mark_") and grudge_marks[name:sub(17)] then
            return M.umbrella.banned(read("ban_all_grudge_marks"), value)
        elseif name:find("^enable_boon_") and name ~= "enable_boon_reworks" then
            return M.umbrella.enabled(read("enable_boon_reworks"), value)
        end
        return value
    end

    function M.setup(self, args)
        self._ct_progdiff_start = mod._ct_progdiff_pending_host_start or args[2]
        mod._ct_progdiff_pending_host_start = nil
        local incoming, value = args[5], effective("starting_coins")
        local initial, configured = M.coins.resolve(value, incoming)
        if configured then args[5] = initial end
        self._ct_evidence_generation = (self._ct_evidence_generation or 0) + 1
        local local_ok, local_value = pcall(mod.get, mod, "starting_coins")
        if not local_ok then local_value = nil end
        self._ct_starting_coins_receipt = { expected = initial, configured = configured, requested = args[5],
            incoming = incoming, effective = value, local_raw = local_value,
            generation = self._ct_evidence_generation,
            authority = Managers and Managers.player and Managers.player.is_server == true and "host" or "client" }
    end
    function M.capture_coins(self)
        local receipt = self and self._ct_starting_coins_receipt
        if not receipt then return end
        if not receipt.configured then
            evidence("record", "912", "setup PASS_THROUGH (not APPLIED)", { incoming = receipt.incoming,
                local_raw = receipt.local_raw, host_effective = receipt.effective, requested = receipt.requested, authority = receipt.authority })
            return
        end
        local ok, actual = pcall(function()
            local peer = self:get_own_peer_id()
            return self:get_player_soft_currency(peer)
        end)
        receipt.readable, receipt.actual = ok and type(actual) == "number", ok and actual or nil
        local run_ok, run_id = pcall(function() return self:get_run_id() end)
        if run_ok then receipt.run_id = run_id end
        evidence("record", "912", "setup initial readback", { incoming = receipt.incoming, local_raw = receipt.local_raw,
            host_effective = receipt.effective, requested = receipt.requested, actual = receipt.actual,
            readable = receipt.readable, authority = receipt.authority, generation = receipt.generation,
            status = receipt.authority == "host" and receipt.readable and receipt.actual == receipt.expected and "APPLIED" or "PENDING" })
    end
    function M.credit_native(func, self, args, n, raw_amount, before)
        local result = pack(func(self, unpack(args, 1, n)))
        evidence("coin_applied", self, raw_amount, args[1], before)
        return unpack(result, 1, result.n)
    end
    function M.add_anath(func, self, template_name, params)
        local result = pack(func(self, template_name, params))
        evidence("anath_after", self)
        return unpack(result, 1, result.n)
    end
    function M.coins_regression(self)
        local receipt = self and self._ct_starting_coins_receipt
        if not (receipt and receipt.configured) then return { status = "SKIP", reason = "#912 no configured current setup receipt" } end
        if receipt.requested ~= receipt.expected then return "#912 setup argument differs from exact configured baseline" end
        if receipt.authority ~= "host" or not receipt.readable then return { status = "SKIP", reason = "#912 host initial readback unavailable/client pending" } end
        if receipt.actual ~= receipt.expected then
            return string.format("#912 initial readback=%s expected=%s", tostring(receipt.actual), tostring(receipt.expected))
        end
    end
    -- #107/#221 universal application gate, including Shadow Lieutenant's
    -- hardcoded source. The base enhancement is never a grudge mark.
    function M.filter_enhancements(enhancements, server)
        if not server or type(enhancements) ~= "table" then return enhancements end
        local kept = {}
        for i = 1, #enhancements do
            local entry = enhancements[i]
            local name = type(entry) == "table" and entry.name or type(entry) == "string" and entry
            if name == "base" or type(name) ~= "string" or effective("ban_grudge_mark_" .. name) ~= true then
                kept[#kept + 1] = entry
            end
        end
        return #kept == #enhancements and enhancements or kept
    end
    if rawget(_G, "TerrorEventUtils") then
        mod:hook(TerrorEventUtils, "apply_breed_enhancements", function(func, unit, breed, data)
            if data and type(data.enhancements) == "table" then
                local incoming = #data.enhancements
                local server = Managers and Managers.player and Managers.player.is_server == true
                data.enhancements = M.filter_enhancements(data.enhancements,
                    server)
                pcall(function()
                    evidence("record", "107", "filtered application request (not native retained-state proof)", {
                        incoming = incoming, kept = #data.enhancements, removed = incoming - #data.enhancements,
                        authority = server == true and "host" or "client", master = effective("ban_all_grudge_marks") == true,
                        breed = type(breed) == "table" and type(breed.name) == "string" and breed.name or "unknown",
                    })
                end)
            end
            return func(unit, breed, data)
        end)
    end
    function M.coin_multiplier(base)
        if not effective("progressive_difficulty") then return base end
        local mechanism = Managers and Managers.mechanism and Managers.mechanism:game_mechanism()
        local rc = mechanism and mechanism.get_deus_run_controller and mechanism:get_deus_run_controller()
        local state = rc and rc._run_state
        local completed = state and state.get_completed_level_count and state:get_completed_level_count() or 0
        local value = M.progressive.coin_multiplier(base, effective("progressive_coin_reduction"), completed)
        evidence("record", "460coin", "coin multiplier return", { base = base, reduction = effective("progressive_coin_reduction"), completed = completed, returned = value })
        return value
    end
    mod:hook("DeusRunController", "get_run_difficulty", function(func, self)
        local base = func(self)
        if not effective("progressive_difficulty") or not effective("progressive_difficulty_increase") then return base end
        local state = self and self._run_state
        local completed = state and state.get_completed_level_count and state:get_completed_level_count() or 0
        local value = M.progressive.difficulty(self._ct_progdiff_start or base, completed,
            rawget(_G, "Difficulties"), rawget(_G, "DifficultyLookup"))
        evidence("record", "460", "difficulty getter return", { native = base, start = self._ct_progdiff_start,
            completed = completed, returned = value, master = effective("progressive_difficulty"), increase = effective("progressive_difficulty_increase") })
        return value
    end)

    function M.force_finale(graph, config)
        if type(graph) ~= "table" then return end
        local gods = { "nurgle", "tzeentch", "khorne", "slaanesh" }
        local finale = gods[effective("finale_dominant_god")]
        if not finale then return end
        local approach = gods[effective("finale_approach_god")] or finale
        for _, node in pairs(graph) do
            if type(node) == "table" and type(node.level) == "string" then
                local base = node.level:match("^(arena_citadel)_") or node.level:match("^(sig_citadel)_")
                if base then
                    local before_level, before_theme, before_god, before_curse = node.level, node.theme, node.god, node.curse
                    local god = base == "arena_citadel" and finale or approach
                    local path = node.level:match("_path(%d+)$")
                    if path then node.level = base .. "_" .. god .. "_path" .. path end
                    node.theme, node.god = god, god
                    local pool = config and config.AVAILABLE_CURSES and config.AVAILABLE_CURSES[node.level_type]
                    pool = pool and pool[god]
                    if type(pool) == "table" and #pool > 0 then
                        node.curse = pool[(math.floor(tonumber(node.level_seed) or 0) % #pool) + 1]
                    end
                    local member = false
                    for _, curse in ipairs(type(pool) == "table" and pool or {}) do if curse == node.curse then member = true end end
                    evidence("record", "146", "Citadel node applied/read back", { before_level = before_level, level = node.level,
                        before_theme = before_theme, theme = node.theme, before_god = before_god, god = node.god,
                        before_curse = before_curse, curse = node.curse, curse_pool_member = member,
                        finale_control = effective("finale_dominant_god"), approach_control = effective("finale_approach_god") })
                end
            end
        end
    end

    -- #258/#271: multiply only the named injected-map interior channels after
    -- the official curse profile and the user's brightness have been applied.
    -- resource-safety: ct_public_interior_shading
    -- Same synchronous native level shading handle; exact-channel callback oracle.
    function M.light(level, theme, shading_env)
        local channels
        if level == "dlc_termite_2" then
            channels = { "secondary_sun_color", "ambient_tint", "ambient_tint_top", "exposure" }
        elseif level == "dlc_termite_3" and theme == "tzeentch" then
            channels = { "ambient_tint_top" }
        end
        for _, channel in ipairs(channels or {}) do
            if channel == "exposure" then
                local v = ShadingEnvironment.scalar(shading_env, channel)
                if v then ShadingEnvironment.set_scalar(shading_env, channel, v * 2) end
            else
                local v = ShadingEnvironment.vector3(shading_env, channel)
                if v then ShadingEnvironment.set_vector3(shading_env, channel, Vector3(v.x * 2, v.y * 2, v.z * 2)) end
            end
        end
    end

    function M.grant_stack(unit, stack_name, stack_key, target, ext)
        -- Keep the official stronger final pre-mutation gate. No donor local
        -- fallback can create a custom stack while parity is unconfirmed.
        if type(mod._ct_wire_safe) ~= "function" or mod._ct_wire_safe() ~= true then return end
        local server = Managers and Managers.player and Managers.player.is_server == true
        local mode, count = M.ammo.grant_plan(server, true, ext:num_buff_stacks(stack_key), target)
        if mode ~= "networked" then return end
        local entity = Managers.state and Managers.state.entity
        local system = entity and entity:system("buff_system")
        if not system then return end
        for _ = 1, count do system:add_buff(unit, stack_name, unit, true) end
    end
    function M.clamp_ammo(ext)
        if type(ext) ~= "table" then return end
        local before_current, before_reserve = ext._current_ammo, ext._available_ammo
        local reserve, r = M.ammo.clamp_value(ext._max_ammo, ext._available_ammo)
        local current, c = M.ammo.clamp_value(ext._max_ammo, ext._current_ammo)
        if r then ext._available_ammo = reserve end
        if c then ext._current_ammo = current end
        if r or c then pcall(printf, "[ct:256] bounded current ammo current=%s reserve=%s", tostring(ext._current_ammo), tostring(ext._available_ammo)) end
        evidence("ammo_applied", ext, before_current, before_reserve)
    end
    function M.finish_pickup(func, self, settings, pickup_name, ...)
        local result = pack(func(self, settings, pickup_name, ...))
        local unit = result[1]
        evidence("pickup", unit, result[2], pickup_name, select(4, ...))
        if mod._ct_tally_count then mod._ct_tally_count(pickup_name, unit) end
        if pickup_name == "deus_cursed_chest" and unit and mod._ct_official_chest_cap then
            mod._ct_official_chest_cap.pickup_chest(unit)
        end
        return unpack(result, 1, result.n)
    end

    -- #471 uses the native finder and spacing, with at most five passes. This
    -- function is called from the existing TerrorEventMixer singleton hook.
    function M.spawn_around(func, event, element, t)
        local cat = element and element.spawn_counter_category
        if cat ~= "cursed_chest_enemies" and cat ~= "cursed_chest_elites" then return func(event, element, t) end
        local mult = effective("cot_enemy_multiplier")
        local scale = cat == "cursed_chest_enemies" and type(mult) == "number" and mult > 1
        local amount, difficulty = element.amount, element.difficulty_amount
        if scale then
            if type(amount) == "number" then element.amount = math.max(1, math.floor(amount * mult)) end
            if type(difficulty) == "table" then
                local scaled = {}
                for key, value in pairs(difficulty) do scaled[key] = type(value) == "number" and math.max(1, math.floor(value * mult)) or value end
                element.difficulty_amount = scaled
            end
        end
        local result = pack(pcall(func, event, element, t))
        if scale then element.amount, element.difficulty_amount = amount, difficulty end
        if not result[1] then
            evidence("record", "471", "native placement threw (no completion claim)", { category = cat, error = tostring(result[2]) })
            error(result[2], 0)
        end
        local requested = event and event.spawn_table and #event.spawn_table
        local placed = event and event.spawn_positions and #event.spawn_positions
        local passes_used, telegraphs, telegraph_errors, topup_error = 0, 0, 0, nil
        if M.placement.needs_topup(requested, placed) then
            local ok, err = pcall(function()
                local finder = ConflictUtils and ConflictUtils.find_positions_around_position
                if not (finder and event.center_position) then return end
                local center = event.center_position:unbox()
                local nav = Managers.state.entity:system("ai_system"):nav_world()
                if not (center and nav) then return end
                local forbidden, accepted = {}, {}
                for i = 1, placed do forbidden[i] = event.spawn_positions[i]:unbox() end
                local _, _, used = M.placement.drain(requested, placed, M.placement.plan_passes(element.min_distance, element.max_distance), function(pass, want)
                    passes_used = passes_used + 1
                    local before = #accepted
                    finder(center, accepted, nav, pass.min_distance, pass.max_distance, want,
                        forbidden, element.distance_to_enemies or 2, pass.tries, pass.circle_subdivision,
                        element.row_distance, element.above_max, element.below_max, false, nil, nil)
                    return #accepted - before
                end)
                passes_used = used
                for i = 1, #accepted do
                    local index = #event.spawn_positions + 1
                    local boxed = Vector3Box(accepted[i])
                    if element.pre_spawn_unit_func then
                        telegraphs = telegraphs + 1
                        local telegraph_ok = pcall(element.pre_spawn_unit_func, event, element, boxed, event.spawn_table[index])
                        if not telegraph_ok then telegraph_errors = telegraph_errors + 1 end
                    end
                    event.spawn_positions[index] = boxed
                end
            end)
            if not ok then topup_error = tostring(err) end
        end
        local final = event and event.spawn_positions and #event.spawn_positions
        evidence("record", "471", "placement return (not enemy-spawn/completion proof)", { category = cat, multiplier = mult,
            requested = requested, native_placed = placed, placed = final, topup = final and placed and final - placed,
            passes = passes_used, residual = requested and final and math.max(0, requested - final), topup_error = topup_error,
            min_distance = element.min_distance, max_distance = element.max_distance, spacing = element.distance_to_enemies or 2,
            telegraph_attempts = telegraphs, telegraph_errors = telegraph_errors })
        return unpack(result, 2, result.n)
    end

    -- #470: native spawn reads rank 8 from this sparse table. Fill only that
    -- missing slot; retain every authored/nonmissing value (including zero).
    function M.backfill_sorcerer()
        local breed = Breeds and Breeds.curse_mutator_sorcerer
        local health = breed and breed.max_health
        if type(health) == "table" and health[7] ~= nil and health[8] == nil then health[8] = 150 end
    end
    mod:hook_safe("MutatorHandler", "initialize_mutators", M.backfill_sorcerer)

    -- #252 lives at the presentation boundary, not in reward generation.
    mod:hook_safe("DeusUpgradeWeaponInteractionUI", "_populate_widget", function(self, unit, slot)
        pcall(function()
            local chest = ScriptUnit and ScriptUnit.has_extension and ScriptUnit.has_extension(unit, "pickup_system")
            if not (chest and DEUS_CHEST_TYPES and chest._chest_type == DEUS_CHEST_TYPES.upgrade) then return end
            if not (chest._go_id and ctx.altar_uses(chest._go_id) > 0) then return end
            local network = Managers.state and Managers.state.network
            local synchronizer = network and network.profile_synchronizer
            if not (synchronizer and synchronizer.others_actually_ingame and synchronizer:others_actually_ingame()) then return end
            local mechanism = Managers.mechanism and Managers.mechanism:game_mechanism()
            local rc = mechanism and mechanism.get_deus_run_controller and mechanism:get_deus_run_controller()
            if not rc then return end
            local stored = chest.get_stored_purchase and chest:get_stored_purchase()
            local melee, ranged = rc:get_own_loadout()
            local equipped = slot == "slot_melee" and melee or ranged
            local rarity = RaritySettings and stored and RaritySettings[stored.rarity]
            local worn = RaritySettings and equipped and RaritySettings[equipped.rarity]
            if not (rarity and worn and rarity.order == worn.order) then return end
            local info = self._widgets_by_name and self._widgets_by_name.chest_content
            local tooltip = self._widgets_by_name and self._widgets_by_name.weapon_tooltip
            if not (info and tooltip) then return end
            local coins = rc:get_player_soft_currency(rc:get_own_peer_id()) or 0
            local cost = chest:get_purchase_cost() or 0
            tooltip.content.item, tooltip.content.force_equipped = equipped, true
            tooltip.style.item.draw_end_passes = true
            info.content.rarity_text = rarity.display_name
            if Colors and Colors.get_table then info.style.rarity.text_color = Colors.get_table(stored.rarity) end
            info.content.cost_text = coins .. "/" .. cost
            info.style.cost_text.text_color = cost <= coins and { 255, 255, 255, 255 } or { 255, 255, 0, 0 }
            info.content.reward_info_text = "Reroll this weapon?"
            info.content.show_coin_icon, info.content.disabled_text = true, nil
            self._calculate_offset = true
            evidence("record", "252", "same-tier prompt applied/read back (not purchase proof)", { go_id = chest._go_id,
                slot = slot, stored_rarity = rarity.order, equipped_rarity = worn.order, uses = ctx.altar_uses(chest._go_id),
                coins = coins, cost = cost, prompt = info.content.reward_info_text, cost_text = info.content.cost_text,
                disabled = info.content.disabled_text or "nil", force_equipped = tooltip.content.force_equipped })
        end)
    end)

    register("issue912_exact_starting_coins", function()
        for _, value in ipairs({ 0, 324, 3000 }) do
            local got, configured = M.coins.resolve(value, 175)
            if not configured or got ~= value then return "exact baseline rejected" end
        end
    end)
    register("issue470_sparse_rank8_backfill", function()
        local health = Breeds and Breeds.curse_mutator_sorcerer and Breeds.curse_mutator_sorcerer.max_health
        if type(health) == "table" and health[7] ~= nil and health[8] == nil then return "rank-8 health missing" end
    end)
    register("issue917_adventure_illusion_preservation", M.illusions.regression_check)
    register("issue107_grudge_application_master", function()
        local base = { name = "base" }
        local filtered = M.filter_enhancements({ base }, true)
        if #filtered ~= 1 or filtered[1] ~= base then return "base enhancement removed" end
    end)
    return M
end
