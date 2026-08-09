return function(H, repo_root)
    local path = repo_root
        .. "/chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/_ct_diag_tab_native533.lua"
    local f = assert(io.open(path, "rb"))
    local source = f:read("*a"); f:close()

    H.test("CT #571 Tab diagnostics are automatic and Deus-run scoped", function()
        H.truthy(source:find('mod:hook_safe("IngamePlayerListUI", "_set_active"', 1, true))
        H.truthy(source:find('M.arm(self, active)', 1, true))
        H.truthy(source:find('ls.mechanism == "deus" and "native-deus" or "injected-adventure"', 1, true))
        H.truthy(source:find('self._ct_diag_native533_armed and self._active', 1, true))
        H.truthy(source:find('trigger=_set_active(true)->settled-post-draw', 1, true))
    end)

    H.test("CT #571 diagnostics capture settled native and overlay geometry", function()
        for _, needle in ipairs({
            'provider=LevelHelper.current_level_settings',
            'loot_objectives=%s', 'mission_widgets count=%s',
            '"banner_right"', '"loot_objective"', '"collectibles_name"',
            '"collectibles_divider"', '"node_info"',
            'parent=%s align=%s/%s', 'bounds=[%s,%s,%s,%s]',
            'content=%s style=%s', 'rl.res_w', 'rl.res_h', 'rl.scale',
            'Application.user_setting("safe_rect")',
            'settled_frames=%s', 'wait_frames=%s', 'ct_layout=%s',
            'ct_row=%d key=%s', 'measured_text_w=%s',
            'nominal_right=%s nominal_top=%s',
        }) do
            H.truthy(source:find(needle, 1, true), "missing #571 census field: " .. needle)
        end
    end)

    H.test("CT #571 diagnostics wait for settled geometry and remain bounded", function()
        H.truthy(source:find('local RECORD_CAP = 64', 1, true))
        H.truthy(source:find('local SETTLE_FRAMES = 3', 1, true))
        H.truthy(source:find('local MAX_WAIT_FRAMES = 120', 1, true))
        H.truthy(source:find('geometry_settled(self)', 1, true))
        H.truthy(source:find('records >= RECORD_CAP or seen[key]', 1, true))
        H.truthy(source:find('[ct:571-native]', 1, true))
        H.equal(source:find('mod:echo', 1, true), nil, "automatic diagnostic must not pollute chat")
        H.equal(source:find('mod:info', 1, true), nil, "automatic diagnostic must use engine printf")
        H.equal(source:find('mod:command', 1, true), nil, "automatic diagnostic must not require a command")
    end)

    H.test("CT #533 census drains from the existing post-vanilla draw seam", function()
        -- #1159: the shared draw seam moved from the entry into the tab-panel
        -- owner. Needles are byte-identical; only the source file changed.
        local main_path = repo_root
            .. "/chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/_ct_tab_panel_owner.lua"
        local mf = assert(io.open(main_path, "rb"))
        local main = mf:read("*a"); mf:close()
        local ef = assert(io.open(repo_root
            .. "/chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/chaos_wastes_tweaker_dev.lua", "rb"))
        local entry_source = ef:read("*a"); ef:close()
        H.equal(entry_source:find('mod:hook_safe("IngamePlayerListUI", "_draw"', 1, true), nil,
            "the entry must not keep a shadowing copy of the shared draw seam")
        local hook = assert(main:find('mod:hook_safe("IngamePlayerListUI", "_draw"', 1, true))
        local capture = assert(main:find('pcall(mod._ct_diag_tab_native533.capture, self)', hook, true))
        local early = assert(main:find('if not has_boons and not cw then return end', hook, true))
        H.truthy(capture < early, "native census must not depend on a CT overlay existing")
        H.truthy(main:find('issue533_native_tab_diagnostics_armed', 1, true))
    end)

    H.test("CT #571 collectible construction is independent of GUT hook order", function()
        -- #1159: the shared draw seam moved from the entry into the tab-panel
        -- owner. Needles are byte-identical; only the source file changed.
        local main_path = repo_root
            .. "/chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/_ct_tab_panel_owner.lua"
        local mf = assert(io.open(main_path, "rb"))
        local main = mf:read("*a"); mf:close()
        local ef = assert(io.open(repo_root
            .. "/chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/chaos_wastes_tweaker_dev.lua", "rb"))
        local entry_source = ef:read("*a"); ef:close()
        H.equal(entry_source:find('mod:hook_safe("IngamePlayerListUI", "_draw"', 1, true), nil,
            "the entry must not keep a shadowing copy of the shared draw seam")
        local hook = assert(main:find('mod:hook_safe("IngamePlayerListUI", "_draw"', 1, true))
        local recovery = assert(main:find('mod._ct_ensure_deus_collectibles, self, "draw_recovery"', hook, true))
        local layout_path = repo_root
            .. "/chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/_ct_tab_collectibles_layout.lua"
        local lf = assert(io.open(layout_path, "rb"))
        local layout = lf:read("*a"); lf:close()
        local constructor = assert(layout:find('function mod._ct_ensure_deus_collectibles(self, source)', 1, true))
        local setup = assert(main:find('mod._ct_ensure_deus_collectibles(self, "setup_mission_data")', recovery, true))
        H.truthy(recovery > hook, "draw seam must recover when an outer setup hook suppresses CT")
        H.truthy(setup > recovery, "normal setup and draw recovery must share one constructor")
        H.truthy(layout:find('self._ct_deus_collectibles_build_failed = true', constructor, true),
            "failed late construction must latch instead of retrying every frame")
    end)
end
