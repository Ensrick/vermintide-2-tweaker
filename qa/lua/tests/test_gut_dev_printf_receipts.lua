return function(H, repo_root)
    -- Repairs #272/#250 + load-banner hardening: user-facing diagnostics must use
    -- pcall-guarded engine printf, never mod:info (mod logging is OFF in the
    -- user's sessions, NON-NEGOTIABLE 9), and the external-scoreboard gate must
    -- honor VMF's enabled state rather than bare get_mod truthiness.
    local function read(path)
        local file = assert(io.open(repo_root .. "/" .. path, "rb"))
        local source = file:read("*a")
        file:close()
        return source
    end

    H.test("GUT load banner and receipts use pcall printf", function()
        local main = read("gui_tweaker_dev/scripts/mods/gui_tweaker_dev/gui_tweaker_dev.lua")
        H.truthy(main:find('pcall(printf, "[gut:LOAD]', 1, true),
            "load banner must be pcall(printf, ...) like ct's")
        H.equal(main:find('mod:info("[gut:LOAD]', 1, true), nil,
            "load banner regressed to mod:info (invisible with mod logging off)")

        local talent = read("gui_tweaker_dev/scripts/mods/gui_tweaker_dev/_gut_tab_talent_refresh.lua")
        H.truthy(talent:find('pcall(printf, "[gut:250]', 1, true),
            "#250 repair receipt must be pcall(printf, ...)")
        H.equal(talent:find('mod:info("[gut:250]', 1, true), nil,
            "#250 receipt regressed to mod:info")

        local live = read("gui_tweaker_dev/scripts/mods/gui_tweaker_dev/_gut_scoreboard_live.lua")
        H.truthy(live:find('pcall(printf, "[gut:272]', 1, true),
            "#272 evidence lines must be pcall(printf, ...)")
        H.equal(live:find('mod:info("[gut:272]', 1, true), nil,
            "#272 evidence regressed to mod:info")
    end)

    H.test("GUT #272 hooks gate through the enabled-aware helper", function()
        local live = read("gui_tweaker_dev/scripts/mods/gui_tweaker_dev/_gut_scoreboard_live.lua")
        local count, at = 0, 1
        while true do
            at = live:find('get_mod("reikland-scoreboard")', at, true)
            if not at then break end
            count = count + 1
            at = at + 1
        end
        H.equal(count, 1,
            "get_mod(\"reikland-scoreboard\") may appear only inside _external_scoreboard_active")
        H.truthy(live:find("_external_scoreboard_active()", 1, true),
            "hooks no longer route through the shared gate helper")
        H.truthy(live:find("pcall(external.is_enabled, external)", 1, true),
            "gate helper no longer consults :is_enabled()")
    end)

    H.test("GUT #272 gate treats a disabled external scoreboard as absent", function()
        -- Execute the production module with a minimal VMF seam and drive its
        -- returned rt check, so the gate's enabled-state behavior is exercised
        -- offline, not just spelled.
        local saved_get_mod = get_mod
        local fake_mod = {
            hooks = {},
        }
        function fake_mod:dofile(path)
            return assert(loadfile(repo_root .. "/gui_tweaker_dev/" .. path .. ".lua"))()
        end
        function fake_mod:hook_safe(class_name, method)
            self.hooks[#self.hooks + 1] = class_name .. "." .. method
        end
        get_mod = function()
            return fake_mod
        end

        local loaded, module_or_error = pcall(function()
            return assert(loadfile(repo_root
                .. "/gui_tweaker_dev/scripts/mods/gui_tweaker_dev/_gut_scoreboard_live.lua"))()
        end)
        get_mod = saved_get_mod
        if not loaded then
            error(module_or_error)
        end

        H.equal(#fake_mod.hooks, 2, "live page must own exactly its two draw hooks")
        local gate_check
        for _, check in ipairs(module_or_error.rt_checks or {}) do
            if check.name == "issue272_external_scoreboard_gate_respects_enabled" then
                gate_check = check.fn
            end
        end
        H.truthy(gate_check, "gate rt check is not registered by the module")
        H.equal(gate_check(), nil, tostring(gate_check and gate_check() or ""))
    end)
end
