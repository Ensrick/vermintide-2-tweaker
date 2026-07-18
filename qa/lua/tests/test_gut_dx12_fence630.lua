return function(H, repo_root)
    local root = repo_root .. "/gui_tweaker_dev/scripts/mods/gui_tweaker_dev/"
    local Probe = assert(loadfile(root .. "_gut_dx12_fence630.lua"))()

    H.test("#630 records a balanced borrowed-renderer lifecycle", function()
        local lines = {}
        local probe = Probe.new({ emit = function(line) lines[#lines + 1] = line end })
        probe:enter({ presentation = "standalone", renderer = "renderer-a", tab = "gut_dev" })
        probe:before_draw({ focus = true, tab = "gut_dev", rows = 12, visible = 8 })
        probe:after_draw()
        probe:before_draw({ focus = true, tab = "wt_dev", rows = 40, visible = 11 })
        probe:after_draw()
        probe:leave("on_exit")

        local state = probe:snapshot()
        H.equal(state.draw_begins, 2)
        H.equal(state.draw_ends, 2)
        H.equal(state.imbalance_count, 0)
        H.equal(state.active, false)
        H.truthy(string.find(table.concat(lines, "\n"), "tab=wt_dev", 1, true))
        H.truthy(string.find(table.concat(lines, "\n"), "balance=0", 1, true))
    end)

    H.test("#630 exposes an unmatched or re-entered draw pass", function()
        local lines = {}
        local probe = Probe.new({ emit = function(line) lines[#lines + 1] = line end })
        probe:enter({ presentation = "standalone" })
        probe:before_draw({ focus = true, tab = "wt_dev" })
        probe:before_draw({ focus = true, tab = "wt_dev" })
        probe:leave("probe")

        local state = probe:snapshot()
        H.equal(state.draw_begins, 2)
        H.equal(state.draw_ends, 0)
        H.truthy(state.imbalance_count >= 2)
        H.truthy(string.find(table.concat(lines, "\n"), "anomaly=draw_reentry", 1, true))
        H.truthy(string.find(table.concat(lines, "\n"), "balance=2", 1, true))
    end)

    H.test("#630 focus and tab evidence is edge-triggered and hard-capped", function()
        local lines = {}
        local probe = Probe.new({
            line_cap = 7,
            emit = function(line) lines[#lines + 1] = line end,
        })
        probe:enter({ presentation = "standalone" })
        for i = 1, 20 do
            probe:before_draw({ focus = i < 10, tab = i < 15 and "wt_dev" or "gut_dev" })
            probe:after_draw()
        end
        probe:leave("on_exit")

        local state = probe:snapshot()
        H.equal(#lines, 7)
        H.equal(state.lines, 7)
        H.equal(state.capped, true)
        H.equal(state.draw_begins, 20)
        H.equal(state.draw_ends, 20)
    end)

    H.test("#630 is wired around both Mod Tweaker presentation passes", function()
        for _, name in ipairs({ "_mod_tweaker_view.lua", "_mod_tweaker_state.lua" }) do
            local file = assert(io.open(root .. name, "rb"))
            local source = file:read("*a")
            file:close()
            H.truthy(string.find(source, "dx12_diag:enter", 1, true), name .. " missing enter")
            H.truthy(string.find(source, "dx12_diag:before_draw", 1, true), name .. " missing begin edge")
            H.truthy(string.find(source, "dx12_diag:after_draw", 1, true), name .. " missing end edge")
            H.truthy(string.find(source, "dx12_diag:leave", 1, true), name .. " missing exit")
        end
    end)
end
