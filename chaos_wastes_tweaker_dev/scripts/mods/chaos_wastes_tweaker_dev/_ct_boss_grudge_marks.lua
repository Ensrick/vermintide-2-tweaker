-- OWNER: Boss Grudge Marks runtime (#107 / Phase 5 #1159)
-- RESPONSIBILITY: capture/restore the native BossGrudgeMarks set, apply the
-- host-authoritative universal enhancement filter, and own the two matching
-- diagnostic commands.
-- PUBLIC SURFACE: stable owner map { sync, names, get_baseline } published as
-- mod._ct_boss_grudge_marks; the entry retains only a local sync facade.
-- INSTALL ORDER: original entry boundary after start-shrine installation and
-- before the remaining verification commands/settings lifecycle.
-- INVARIANTS: no settings/RPC ownership, one hook, two commands, late-bound
-- settings/manager/log dependencies, and reload-stable vanilla baseline.

local MARK_NAMES = {
    "commander", "crippling", "crushing", "frenzy", "intangible",
    "periodic_curse", "periodic_shield", "raging", "ranged_immune",
    "regenerating", "unstaggerable", "vampiric", "warping",
}

return function(ctx)
    assert(type(ctx) == "table", "_ct_boss_grudge_marks requires context")
    local mod = assert(ctx.mod, "_ct_boss_grudge_marks requires mod")
    assert(type(ctx.effective_setting) == "function",
        "_ct_boss_grudge_marks requires effective_setting")
    assert(type(ctx.is_banned) == "function",
        "_ct_boss_grudge_marks requires is_banned")
    assert(type(ctx.get_global) == "function",
        "_ct_boss_grudge_marks requires get_global")
    assert(type(ctx.get_managers) == "function",
        "_ct_boss_grudge_marks requires get_managers")
    assert(type(ctx.dbg) == "function", "_ct_boss_grudge_marks requires dbg")
    assert(type(ctx.printf) == "function", "_ct_boss_grudge_marks requires printf")

    local state = mod._ct_boss_grudge_marks_state
    if not state then
        state = {
            baseline = nil,
            hook_installed = false,
            commands_installed = false,
            installed = false,
            exports = {},
        }
        mod._ct_boss_grudge_marks_state = state
    end

    -- Refresh before the idempotence guard. Registered callbacks close over
    -- this holder rather than retaining an entry chunk from an earlier reload.
    state.effective_setting = ctx.effective_setting
    state.is_banned = ctx.is_banned
    state.get_global = ctx.get_global
    state.get_managers = ctx.get_managers
    state.dbg = ctx.dbg
    state.printf = ctx.printf

    local exports = state.exports

    local function mark_is_banned(name)
        return state.is_banned(
            state.effective_setting("ban_all_grudge_marks"),
            state.effective_setting("ban_grudge_mark_" .. name))
    end

    local function capture_baseline()
        if state.baseline then return end
        local bgm = state.get_global("BossGrudgeMarks")
        if not bgm then return end
        state.baseline = {}
        for name, value in pairs(bgm) do
            state.baseline[name] = value
        end
    end

    if not exports.sync then
        exports.sync = function()
            capture_baseline()
            local bgm = state.get_global("BossGrudgeMarks")
            if not bgm or not state.baseline then
                state.dbg("[grudge] sync skipped: _G.BossGrudgeMarks=%s baseline=%s",
                    tostring(bgm), tostring(state.baseline))
                return false
            end

            for name, value in pairs(state.baseline) do
                bgm[name] = value
            end
            local banned = {}
            for _, name in ipairs(MARK_NAMES) do
                if mark_is_banned(name) then
                    bgm[name] = nil
                    banned[#banned + 1] = name
                end
            end
            if #banned > 0 then
                state.dbg("[grudge] %d marks banned: %s",
                    #banned, table.concat(banned, ", "))
            else
                state.dbg("[grudge] no marks banned; vanilla BossGrudgeMarks restored")
            end
            return true
        end
        exports.names = MARK_NAMES
        exports.get_baseline = function()
            return state.baseline
        end
    end

    local first_install = not state.installed
    state.installed = true

    -- Match the original load-time mutation boundary on every dofile pass. The
    -- baseline itself remains stable so a reload cannot snapshot a filtered set.
    exports.sync()

    local terror_event_utils = state.get_global("TerrorEventUtils")
    if terror_event_utils and not state.hook_installed then
        state.hook_installed = true
        mod:hook(terror_event_utils, "apply_breed_enhancements",
            function(func, unit, breed, optional_data)
                local enhancements = optional_data and optional_data.enhancements
                local managers = state.get_managers()
                local is_server = managers and managers.player
                    and managers.player.is_server
                if type(enhancements) == "table" and #enhancements > 0 then
                    local applied, removed = {}, {}
                    if is_server then
                        local kept = {}
                        for i = 1, #enhancements do
                            local enhancement = enhancements[i]
                            local name = (type(enhancement) == "table" and enhancement.name)
                                or (type(enhancement) == "string" and enhancement)
                                or nil
                            if type(name) == "string" and mark_is_banned(name) then
                                removed[#removed + 1] = name
                            else
                                kept[#kept + 1] = enhancement
                                applied[#applied + 1] = name or "?"
                            end
                        end
                        if #removed > 0 then
                            optional_data.enhancements = kept
                        end
                    else
                        for i = 1, #enhancements do
                            local enhancement = enhancements[i]
                            applied[#applied + 1] =
                                (type(enhancement) == "table" and enhancement.name)
                                or tostring(enhancement)
                        end
                    end
                    pcall(state.printf,
                        "[grudge-spawn] breed=%s is_server=%s applied=[%s] banned_stripped=[%s]",
                        tostring(breed and breed.name), tostring(is_server),
                        table.concat(applied, ", "), table.concat(removed, ", "))
                end
                return func(unit, breed, optional_data)
            end)
    end

    if not state.commands_installed then
        state.commands_installed = true

        mod:command("dump_grudge_marks",
            "Dump the live BossGrudgeMarks set and each entry's status", function()
                local bgm = state.get_global("BossGrudgeMarks")
                local breed_enhancements = state.get_global("BreedEnhancements")
                if not bgm then
                    mod:echo("[grudge] BossGrudgeMarks not loaded yet.")
                    return
                end
                local baseline_count = 0
                for _ in pairs(state.baseline or {}) do baseline_count = baseline_count + 1 end
                local live_count = 0
                for _ in pairs(bgm) do live_count = live_count + 1 end
                pcall(state.printf,
                    "[DUMP:grudge_marks] === baseline: %d entries ===", baseline_count)
                pcall(state.printf,
                    "[DUMP:grudge_marks] === live BossGrudgeMarks: %d entries ===",
                    live_count)
                pcall(state.printf,
                    "[DUMP:grudge_marks] name\ttoggle_on\tlive_present\tdisplay_name_key")
                for _, name in ipairs(MARK_NAMES) do
                    local toggle_on = mark_is_banned(name)
                    local live_present = bgm[name] ~= nil
                    local entry = breed_enhancements and breed_enhancements[name]
                    local display_name = entry and entry.display_name
                        or ("display_name_" .. name)
                    pcall(state.printf, "[DUMP:grudge_marks] %s\t%s\t%s\t%s",
                        name, tostring(toggle_on), tostring(live_present), display_name)
                end
                mod:echo(string.format(
                    "dump_grudge_marks: %d marks (see log for per-mark detail).",
                    #MARK_NAMES))
            end)

        mod:command("verify_grudge_marks",
            "Verify each Boss Grudge Mark toggle vs live BossGrudgeMarks state",
            function()
                local bgm = state.get_global("BossGrudgeMarks")
                if not bgm then
                    mod:echo("[verify_grudge] FAIL: _G.BossGrudgeMarks not loaded.")
                    return
                end
                local pass, fail = 0, 0
                for _, name in ipairs(MARK_NAMES) do
                    local toggle_on = mark_is_banned(name)
                    local live_present = bgm[name] ~= nil
                    local expected_present = not toggle_on
                    if live_present == expected_present then
                        pass = pass + 1
                        pcall(state.printf,
                            "[verify_grudge] PASS: %s (banned=%s live=%s)",
                            name, tostring(toggle_on), tostring(live_present))
                    else
                        fail = fail + 1
                        mod:warning(
                            "[verify_grudge] FAIL: %s — banned=%s but live=%s (expected live=%s)",
                            name, tostring(toggle_on), tostring(live_present),
                            tostring(expected_present))
                    end
                end
                mod:echo(string.format(
                    "/verify_grudge_marks: %d PASS, %d FAIL (%d total)",
                    pass, fail, #MARK_NAMES))
            end)
    end

    mod._ct_boss_grudge_marks = exports
    return exports, first_install
end
