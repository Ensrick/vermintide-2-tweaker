-- _ct_profile_snapshot.lua - atomic profile/runtime evidence for issue #919.
--
-- Engine-free capture/format helpers are exported for offline tests. install()
-- adds a single bounded printf line at the concrete profile, host-sync, and run
-- setup boundaries without adding hooks or changing gameplay state.

local Snapshot = {}
local MAX_NAMES = 12
local MAX_NAME_BYTES = 48

local function clean(value)
    local text = tostring(value == nil and "nil" or value)
    text = text:gsub("[%c]", " "):gsub("\\", "\\\\"):gsub('"', '\\"')
    if #text > MAX_NAME_BYTES then text = text:sub(1, MAX_NAME_BYTES - 3) .. "..." end
    return text
end

local function selected_boons(entries, getter, label)
    local names = {}
    local seen = {}
    if type(entries) == "table" and type(getter) == "function" then
        for _, entry in ipairs(entries) do
            local name = entry and entry.name
            if type(name) == "string" and not seen[name] then
                local ok, enabled = pcall(getter, "start_boon_" .. name)
                if ok and enabled then
                    seen[name] = true
                    local display = name
                    if type(label) == "function" then
                        local label_ok, resolved = pcall(label, name)
                        if label_ok and type(resolved) == "string" and resolved ~= "" then
                            display = resolved
                        end
                    end
                    names[#names + 1] = clean(display)
                end
            end
        end
    end
    table.sort(names, function(a, b) return string.lower(a) < string.lower(b) end)
    local count = #names
    while #names > MAX_NAMES do table.remove(names) end
    return names, count, count - #names
end

local function read(getter, key)
    if type(getter) ~= "function" then return nil end
    local ok, value = pcall(getter, key)
    return ok and value or nil
end

function Snapshot.capture(args)
    args = args or {}
    local local_get = args.local_get or function() return nil end
    local effective_get = args.effective_get or local_get
    local local_names, local_count, local_truncated = selected_boons(
        args.entries, local_get, args.boon_label)
    local effective_names, effective_count, effective_truncated = selected_boons(
        args.entries, effective_get, args.boon_label)
    local selected_curse = args.selected_curse
    local selected_label = "None"
    if selected_curse then
        selected_label = selected_curse
        if type(args.curse_label) == "function" then
            local ok, resolved = pcall(args.curse_label, selected_curse)
            if ok and resolved ~= nil then selected_label = resolved end
        end
    end
    local local_miasma = read(local_get, "disable_curse_rotten_miasma") and true or false
    local effective_miasma = read(effective_get, "disable_curse_rotten_miasma") and true or false
    return {
        phase = clean(args.phase or "manual"),
        role = clean(args.role or "unknown"),
        profile = tonumber(args.profile) or 1,
        effective_source = clean(args.effective_source or "unknown"),
        coins_local = read(local_get, "starting_coins"),
        coins_effective = read(effective_get, "starting_coins"),
        miasma_disabled_local = local_miasma,
        miasma_disabled_effective = effective_miasma,
        selected_curse = clean(selected_label),
        selected_conflict = selected_curse == "curse_rotten_miasma" and effective_miasma or false,
        boon_local = local_names,
        boon_local_count = local_count,
        boon_local_truncated = local_truncated,
        boon_effective = effective_names,
        boon_effective_count = effective_count,
        boon_effective_truncated = effective_truncated,
    }
end

local function list(names)
    local quoted = {}
    for i = 1, #names do quoted[i] = '"' .. names[i] .. '"' end
    return "[" .. table.concat(quoted, ",") .. "]"
end

function Snapshot.format(snapshot, sequence)
    return string.format(
        '[ct:919] seq=%d phase=%s role=%s profile=%d effective_source=%s coins_local=%s coins_effective=%s miasma_disabled_local=%s miasma_disabled_effective=%s selected_curse="%s" selected_conflict=%s boon_local_count=%d boon_local=%s boon_effective_count=%d boon_effective=%s local_truncated=%d effective_truncated=%d',
        tonumber(sequence) or 0, snapshot.phase, snapshot.role, snapshot.profile,
        snapshot.effective_source, tostring(snapshot.coins_local), tostring(snapshot.coins_effective),
        tostring(snapshot.miasma_disabled_local), tostring(snapshot.miasma_disabled_effective),
        snapshot.selected_curse, tostring(snapshot.selected_conflict),
        snapshot.boon_local_count, list(snapshot.boon_local),
        snapshot.boon_effective_count, list(snapshot.boon_effective),
        snapshot.boon_local_truncated, snapshot.boon_effective_truncated)
end

function Snapshot.install(mod)
    local sequence = 0
    local pending = nil

    function mod._ct919_log_profile_snapshot(phase, profile_override)
        sequence = sequence + 1
        local ok, result = pcall(function()
            local role = (Managers and Managers.player and Managers.player.is_server) and "host" or "client"
            local gut = get_mod("gut_dev") or get_mod("gut")
            local profile = profile_override
            if not profile and gut and gut.mod_tweaker and gut.mod_tweaker.get_active_profile then
                local active_ok, resolved = pcall(gut.mod_tweaker.get_active_profile,
                    gut.mod_tweaker, "ct_dev")
                if active_ok then profile = resolved end
            end
            local cat = mod._ct_dev_mission_catalog
            local curse_index = tonumber(mod:get("ctdm_curse")) or 0
            local selected_curse = cat and curse_index > 0 and cat.CURSES[curse_index] or nil
            local effective_get = mod._ct_effective_setting or function(key) return mod:get(key) end
            return Snapshot.capture({
                phase = phase,
                role = role,
                profile = profile,
                effective_source = mod._ct_effective_setting_source
                    and mod._ct_effective_setting_source() or "unknown",
                local_get = function(key) return mod:get(key) end,
                effective_get = effective_get,
                entries = rawget(_G, "DeusPowerUpsArray"),
                boon_label = mod._ct_boon_display_name,
                selected_curse = selected_curse,
                curse_label = cat and cat.curse_label,
            })
        end)
        if not ok then
            pcall(printf, "[ct:919] seq=%d snapshot_error=%s", sequence, clean(result))
            return nil
        end
        pcall(printf, "%s", Snapshot.format(result, sequence))
        return result
    end

    function mod._ct919_profile_setting_changed(setting_id)
        if setting_id == "starting_coins" or setting_id == "disable_curse_rotten_miasma"
                or setting_id == "ctdm_curse"
                or (type(setting_id) == "string" and setting_id:find("^start_boon_")) then
            pending = 0.25
        end
    end

    function mod._ct919_profile_tick(dt)
        if not pending then return end
        pending = pending - (tonumber(dt) or 0)
        if pending <= 0 then
            pending = nil
            mod._ct919_log_profile_snapshot("settings_settled")
        end
    end

    mod:command("ct_profile_audit",
        "Write one bounded Chaos Wastes profile/runtime snapshot to the log",
        function()
            mod._ct919_log_profile_snapshot("manual")
            mod:echo("Chaos Wastes profile snapshot written to the log ([ct:919]).")
        end)

    mod._ct919_profile_snapshot_installed = true

    if type(mod._ct_rt_register) == "function" then
        mod._ct_rt_register("issue919_profile_snapshot_installed", function()
            if mod._ct919_profile_snapshot_installed ~= true then
                return "profile snapshot installation marker is absent"
            end
            if type(mod._ct919_log_profile_snapshot) ~= "function"
                    or type(mod._ct919_profile_setting_changed) ~= "function"
                    or type(mod._ct919_profile_tick) ~= "function" then
                return "profile snapshot runtime boundary is incomplete"
            end
        end)
    end
end

return Snapshot
