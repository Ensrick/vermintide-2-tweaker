-- _mp_loot_diag_runtime.lua — issue #607 local loot-layer instrumentation.
--
-- The modded realm cannot complete the EAC-challenged PlayFab requests used by
-- vanilla mission awards and chest openings. This owner observes the local
-- seams on either side of that boundary so one ordinary mission can identify
-- the first missing layer without requiring a successful backend callback.
-- It never originates a request, awards a container, opens a container, or
-- retains a backend/player id.

local Runtime = {}

local SETTING = "issue607_loot_diag_v1"

function Runtime.install(mod, deps)
    deps = deps or {}
    local LootDiag = assert(deps.loot_diag, "loot_diag is required")
    local get_inventory_store = assert(deps.get_inventory_store,
        "get_inventory_store is required")
    local rt_register = assert(deps.rt_register, "rt_register is required")
    local realm_state = assert(deps.realm_state, "realm_state is required")
    local print_log = assert(deps.print_log, "print_log is required")
    local item_master_list = assert(deps.item_master_list,
        "item_master_list is required")
    local capture = assert(deps.capture, "capture is required")
    local unpack_results = assert(deps.unpack_results, "unpack_results is required")
    local now = assert(deps.now, "now is required")

    local function ledger()
        return LootDiag.normalize(mod:get(SETTING))
    end

    local function chest_context(self, data)
        local mirror = self and self._backend_mirror
        local inventory = mirror and mirror.get_all_inventory_items
            and mirror:get_all_inventory_items() or nil
        local chest = inventory and data and inventory[data.playfab_id] or nil
        local chest_key = chest and chest.ItemId or "unknown"
        local rarity_tables = mirror and mirror.get_rarity_tables
            and mirror:get_rarity_tables() or nil
        return {
            chest_key = chest_key,
            hero_name = data and data.hero_name,
            game_mode = data and data.game_mode_key,
            amount = data and data.amount,
            rarity_row = rarity_tables and rarity_tables[chest_key] or nil,
        }
    end

    local function request_queue(backend)
        local mirror = backend and backend._backend_mirror
        local getter = mirror and mirror.request_queue
        if type(getter) ~= "function" then return nil end
        local ok, queue = pcall(getter, mirror)
        return ok and queue or nil
    end

    local function emit(event, context, result)
        local realm = realm_state()
        if type(realm) ~= "table" or
                not LootDiag.should_capture(realm["eac-untrusted"]) then return nil end
        local emitted
        local ok, err = pcall(function()
            local next_ledger, record
            if event == "success" then
                next_ledger, record = LootDiag.capture(ledger(), context, result, now())
            else
                next_ledger, record = LootDiag.record(ledger(), event, context, now())
            end
            if not next_ledger then error(record, 0) end
            mod:set(SETTING, next_ledger, false)
            local verified = ledger()
            if verified.serial ~= record.serial then
                error("diagnostic persistence verification failed", 0)
            end
            local first_missing = LootDiag.diagnose(verified)
            print_log("[mp:607] event=%s serial=%d flow=%s request=%s reason=%s chest=%s " ..
                "items=%d local_items=%d local_containers=%d local_uses=%d " ..
                "award_capable=%s open_capable=%s first_missing=%s backend=%s",
                record.event, record.serial, record.flow, record.request_name,
                record.reason, record.chest_key, record.item_count, record.local_items,
                record.local_containers, record.local_container_uses,
                tostring(record.local_award_capable), tostring(record.local_open_capable),
                first_missing, record.backend)
            emitted = record
        end)
        if not ok then
            pcall(print_log, "[mp:607] event=instrument_error reason=%s backend=none",
                tostring(err):gsub("[^%w_%-%.]", "_"):sub(1, 96))
        end
        return emitted
    end

    local function emit_local_ledger(flow, reason)
        local facts = LootDiag.local_ledger_facts(get_inventory_store())
        return emit("local_ledger", {
            flow = flow,
            reason = reason,
            backend = "none",
            local_items = facts.items,
            local_containers = facts.containers,
            local_container_uses = facts.container_uses,
            local_award_capable = facts.award_capable,
            local_open_capable = facts.open_capable,
        })
    end

    -- `_mp607_consolidated_loot_layer_diagnostics`: one hook per actual seam.
    -- The end-level wrapper names every current vanilla parameter and forwards
    -- future trailing arguments so instrumentation cannot change reward behavior.
    mod:hook("BackendInterfaceLootPlayfab", "generate_end_of_level_loot",
        function(func, self, game_won, quick_play_bonus, difficulty, level_key,
                hero_name, start_experience, end_experience, versus_start_experience,
                versus_end_experience, loot_profile_name, deed_item_name,
                deed_backend_id, game_mode_key, game_time,
                end_of_level_rewards_arguments, ...)
            emit("end_level", {
                flow = "end_level",
                request_name = "generateEndOfLevelLoot",
                reason = "mission_reward_entry",
                backend = "none",
                won = game_won,
                difficulty = difficulty,
                level_key = level_key,
                hero_name = hero_name,
                game_mode = game_mode_key,
                local_award_capable = LootDiag.LOCAL_CONTAINER_AWARD_IMPLEMENTED,
                local_open_capable = LootDiag.LOCAL_CONTAINER_OPEN_IMPLEMENTED,
            })
            local n, results = capture(func(self, game_won, quick_play_bonus,
                difficulty, level_key, hero_name, start_experience, end_experience,
                versus_start_experience, versus_end_experience, loot_profile_name,
                deed_item_name, deed_backend_id, game_mode_key, game_time,
                end_of_level_rewards_arguments, ...))
            emit_local_ledger("end_level", "post_native_enqueue")
            return unpack_results(results, 1, n)
        end)

    mod:hook("BackendInterfaceLootPlayfab", "open_loot_chest",
        function(func, self, hero_name, backend_id, game_mode_key, num_chests, ...)
            local context = chest_context(self, {
                hero_name = hero_name,
                playfab_id = backend_id,
                game_mode_key = game_mode_key,
                amount = num_chests,
            })
            if context.chest_key == "unknown" or
                    LootDiag.is_mission_chest(context.chest_key) then
                context.flow = "open"
                context.request_name = "generateLootChestRewards"
                context.reason = "spoils_of_war_entry"
                context.backend = "none"
                context.local_award_capable = LootDiag.LOCAL_CONTAINER_AWARD_IMPLEMENTED
                context.local_open_capable = LootDiag.LOCAL_CONTAINER_OPEN_IMPLEMENTED
                emit("open", context)
            end
            local n, results = capture(func(self, hero_name, backend_id,
                game_mode_key, num_chests, ...))
            emit_local_ledger("open", "post_native_enqueue")
            return unpack_results(results, 1, n)
        end)

    -- The request queue is the last local seam before EAC/network work begins
    -- [src: playfab_request_queue.lua:25-55]. Observe after vanilla enqueues it;
    -- this yields the local numeric id without adding a request.
    mod:hook("PlayFabRequestQueue", "enqueue",
        function(func, self, request, success_callback, send_eac_challenge,
                error_callback, ...)
            local n, results = capture(func(self, request, success_callback,
                send_eac_challenge, error_callback, ...))
            local request_name = type(request) == "table"
                and rawget(request, "FunctionName") or nil
            local flow = LootDiag.request_flow(request_name)
            if flow then
                emit("pre_request", {
                    flow = flow,
                    request_name = request_name,
                    request_id = results[1],
                    reason = send_eac_challenge
                        and "eac_challenge_required" or "no_eac_challenge",
                    backend = "native_queue",
                    local_award_capable = LootDiag.LOCAL_CONTAINER_AWARD_IMPLEMENTED,
                    local_open_capable = LootDiag.LOCAL_CONTAINER_OPEN_IMPLEMENTED,
                })
            end
            return unpack_results(results, 1, n)
        end)

    local function emit_rejection(backend, reason_override)
        local queue = request_queue(backend)
        local request_name = LootDiag.active_request_name(queue)
        if not request_name then return end
        emit("rejection", {
            flow = LootDiag.request_flow(request_name),
            request_name = request_name,
            reason = reason_override or LootDiag.rejection_reason(queue),
            backend = "native_rejection",
            local_award_capable = LootDiag.LOCAL_CONTAINER_AWARD_IMPLEMENTED,
            local_open_capable = LootDiag.LOCAL_CONTAINER_OPEN_IMPLEMENTED,
        })
        emit_local_ledger(LootDiag.request_flow(request_name), "at_backend_rejection")
    end

    -- Both rejection owners retain vanilla behavior. The EAC owner is expected
    -- in the modded realm; the API owner distinguishes transport/service failure
    -- without logging the raw backend payload.
    mod:hook("BackendManagerPlayFab", "playfab_eac_error", function(func, self, ...)
        emit_rejection(self)
        return func(self, ...)
    end)

    mod:hook("BackendManagerPlayFab", "playfab_api_error",
        function(func, self, result, error_code, ...)
            emit_rejection(self, "playfab_api_error")
            return func(self, result, error_code, ...)
        end)

    -- An unexpected successful opening remains useful R&D evidence, but is not
    -- required to arm or complete this diagnostic.
    mod:hook("BackendInterfaceLootPlayfab", "loot_chest_rewards_request_cb",
        function(func, self, data, result, ...)
            local context = chest_context(self, data)
            if LootDiag.is_mission_chest(context.chest_key) then
                emit("success", context, result)
            end
            local n, results = capture(func(self, data, result, ...))
            emit_local_ledger("open", "post_native_callback")
            return unpack_results(results, 1, n)
        end)

    rt_register("issue607_local_loot_layer_diagnostic_contract", function()
        if LootDiag.ACTIVE ~= true then return "#607 diagnostic unexpectedly retired" end
        if not LootDiag.should_capture(true, true) or
            LootDiag.should_capture(false, true) or LootDiag.should_capture(nil, true) or
            LootDiag.should_capture(true, false) then
            return "#607 modded-realm or retirement gate failed"
        end
        if not LootDiag.is_mission_chest("loot_chest_04_06") or
            LootDiag.is_mission_chest("commendation_chest") then
            return "#607 mission-container scope failed"
        end
        if not LootDiag.is_target_request("generateEndOfLevelLoot") or
            not LootDiag.is_target_request("generateLootChestRewards") or
            LootDiag.is_target_request("generateQuestRewards") then
            return "#607 request scope failed"
        end
        local queue = { _active_entry = {
            request = { FunctionName = "generateEndOfLevelLoot" },
            eac_challenge_success = true,
        } }
        if LootDiag.active_request_name(queue) ~= "generateEndOfLevelLoot" or
            LootDiag.rejection_reason(queue) ~= "eac_failed_verification" then
            return "#607 rejection attribution failed"
        end
        if LootDiag.MAX_RECORDS ~= 12 or LootDiag.MAX_ITEMS ~= 6 or
            LootDiag.MAX_RARITIES ~= 10 then
            return "#607 bounds changed"
        end
        local facts = LootDiag.local_ledger_facts({
            a = { ItemId = "es_sword" },
            b = { ItemId = "loot_chest_03_04", RemainingUses = 2 },
        })
        if facts.items ~= 2 or facts.containers ~= 1 or facts.container_uses ~= 2 or
            facts.award_capable or facts.open_capable then
            return "#607 local-ledger census or honest capability state failed"
        end
        local diagnostic = LootDiag.record(nil, "end_level", {
            flow = "end_level", request_name = "generateEndOfLevelLoot",
        }, 1)
        if LootDiag.diagnose(diagnostic) ~= "request_enqueue" then
            return "#607 first missing request layer was not named"
        end
        diagnostic = LootDiag.record(diagnostic, "pre_request", {
            flow = "end_level", request_name = "generateEndOfLevelLoot",
        }, 2)
        if LootDiag.diagnose(diagnostic) ~= "local_container_award" then
            return "#607 first missing local layer was not named"
        end
        local fake_result = { FunctionResult = { items = {
            { ItemId = "es_sword", CustomData = {
                rarity = "rare", power_level = "211",
            } },
        }, consumed_chest = { RemainingUses = 0 } } }
        local success_ledger, record = LootDiag.capture(diagnostic, {
            chest_key = "loot_chest_03_04", hero_name = "empire_soldier",
            game_mode = "adventure", rarity_row = { rare = 75, exotic = 25 },
        }, fake_result, 3)
        if not success_ledger or record.event ~= "success" or
            record.items[1].rarity ~= "rare" then
            return "pure callback summary failed"
        end
        for i = 4, 24 do
            success_ledger = LootDiag.record(success_ledger, "local_ledger", {}, i)
        end
        if #success_ledger.records ~= LootDiag.MAX_RECORDS then
            return "diagnostic ledger is unbounded"
        end
    end)

    mod:command("mp_loot_diag", "Show or reset bounded issue #607 loot diagnostics",
        function(action)
            if action == "reset" then
                mod:set(SETTING, LootDiag.empty(), false)
                mod:echo("#607 loot-layer diagnostic reset. " ..
                    "Passive modded-realm observation remains active.")
                return
            end
            local current = ledger()
            local facts = LootDiag.catalogue_facts(item_master_list())
            local local_facts = LootDiag.local_ledger_facts(get_inventory_store())
            mod:echo("#607 diagnostic active=%s events=%d/%d first_missing=%s " ..
                "local_items=%d containers=%d uses=%d catalogue_gear=%d dlc_gated=%d",
                tostring(LootDiag.ACTIVE), #current.records, LootDiag.MAX_RECORDS,
                LootDiag.diagnose(current), local_facts.items, local_facts.containers,
                local_facts.container_uses, facts.gear, facts.dlc_gated)
            for _, record in ipairs(current.records) do
                mod:echo("  #%d event=%s flow=%s request=%s reason=%s chest=%s " ..
                    "items=%d local_containers=%d",
                    record.serial, record.event, record.flow, record.request_name,
                    record.reason, record.chest_key, record.item_count,
                    record.local_containers)
            end
        end)

    return {
        setting = SETTING,
        emit = emit,
        emit_local_ledger = emit_local_ledger,
    }
end

return Runtime
