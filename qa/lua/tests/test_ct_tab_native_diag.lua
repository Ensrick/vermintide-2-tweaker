return function(H, repo_root)
    local path = repo_root
        .. "/chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/_ct_diag_tab_native533.lua"
    local f = assert(io.open(path, "rb"))
    local source = f:read("*a"); f:close()

    H.test("CT #533 native Tab diagnostics are automatic and native-map scoped", function()
        H.truthy(source:find('mod:hook_safe("IngamePlayerListUI", "_set_active"', 1, true))
        H.truthy(source:find('M.arm(self, active)', 1, true))
        H.truthy(source:find('ls.mechanism == "deus"', 1, true))
        H.truthy(source:find('self._ct_diag_native533_armed and self._active', 1, true))
        H.truthy(source:find('trigger=_set_active(true)->post_draw', 1, true))
    end)

    H.test("CT #533 native Tab diagnostics capture source geometry and providers", function()
        for _, needle in ipairs({
            'provider=LevelHelper.current_level_settings',
            'loot_objectives=%s', 'mission_widgets count=%s',
            '"banner_right"', '"loot_objective"', '"collectibles_name"',
            '"collectibles_divider"', '"node_info"',
            'parent=%s align=%s/%s', 'bounds=[%s,%s,%s,%s]',
            'content=%s style=%s', 'rl.res_w', 'rl.res_h', 'rl.scale',
            'Application.user_setting("safe_rect")',
        }) do
            H.truthy(source:find(needle, 1, true), "missing #533 census field: " .. needle)
        end
    end)

    H.test("CT #533 native Tab diagnostics are deduplicated capped and log-only", function()
        H.truthy(source:find('local RECORD_CAP = 24', 1, true))
        H.truthy(source:find('records >= RECORD_CAP or seen[key]', 1, true))
        H.truthy(source:find('[ct:533-native]', 1, true))
        H.equal(source:find('mod:echo', 1, true), nil, "automatic diagnostic must not pollute chat")
        H.equal(source:find('mod:command', 1, true), nil, "automatic diagnostic must not require a command")
    end)

    H.test("CT #533 census drains from the existing post-vanilla draw seam", function()
        local main_path = repo_root
            .. "/chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/chaos_wastes_tweaker_dev.lua"
        local mf = assert(io.open(main_path, "rb"))
        local main = mf:read("*a"); mf:close()
        local hook = assert(main:find('mod:hook_safe("IngamePlayerListUI", "_draw"', 1, true))
        local capture = assert(main:find('pcall(mod._ct_diag_tab_native533.capture, self)', hook, true))
        local early = assert(main:find('if not has_boons and not cw then return end', hook, true))
        H.truthy(capture < early, "native census must not depend on a CT overlay existing")
        H.truthy(main:find('issue533_native_tab_diagnostics_armed', 1, true))
    end)
end
