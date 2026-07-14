return function(H, repo_root)
    local module_path = repo_root
        .. "/gui_tweaker_dev/scripts/mods/gui_tweaker_dev/_gut_all_languages.lua"

    local keys = {
        "arial", "arial_masked", "arial_write_mask",
        "hell_shark_arial", "hell_shark_arial_masked",
        "hell_shark_arial_write_mask", "chat_output_font",
        "chat_output_font_masked",
    }

    local function load_case(provider, material_for)
        local old_get_mod, old_printf, old_fonts = get_mod, printf, Fonts
        local commands = {}
        local gut = {
            command = function(_, name, _, fn) commands[name] = fn end,
            echo = function() end,
        }
        get_mod = function(name)
            if name == "gut_dev" then return gut end
            if name == "support-all-languages" then return provider end
        end
        printf = function() end
        Fonts = {}
        for _, key in ipairs(keys) do Fonts[key] = { material_for(key), 16, "arial" } end

        local before = {}
        for _, key in ipairs(keys) do before[key] = Fonts[key][1] end
        local ok, api = pcall(dofile, module_path)
        local after = Fonts

        get_mod, printf, Fonts = old_get_mod, old_printf, old_fonts
        assert(ok, api)
        return api, commands, before, after
    end

    H.test("GUT #340 diagnostics never mutate vanilla Fonts", function()
        local api, commands, before, after = load_case(nil, function()
            return "materials/fonts/arial"
        end)
        H.equal(api.does_font_swap, false)
        H.equal(api.installs_hooks, false)
        H.equal(type(commands.gut_all_languages_status), "function")
        for _, key in ipairs(keys) do H.equal(after[key][1], before[key]) end
        local old_fonts = Fonts
        Fonts = after
        local scan = api.inspect_fonts()
        commands.gut_all_languages_status()
        Fonts = old_fonts
        H.equal(scan.unicode, 0)
        H.equal(scan.total, 8)
        H.equal(scan.state, "vanilla_or_other_provider")
        for _, key in ipairs(keys) do H.equal(after[key][1], before[key]) end
    end)

    H.test("GUT #340 diagnostics recognize a complete Unicode provider", function()
        local provider = { is_enabled = function() return true end }
        local api, _, _, after = load_case(provider, function()
            return "fonts/ArialUnicodeMS"
        end)
        local old_fonts = Fonts
        Fonts = after
        local scan = api.inspect_fonts()
        Fonts = old_fonts
        H.equal(api.standalone_present, true)
        H.equal(api.standalone_enabled, true)
        H.equal(scan.state, "unicode_active")
        H.equal(scan.unicode, 8)
        H.equal(scan.missing, 0)
    end)

    H.test("GUT #340 diagnostics flag partial application", function()
        local n = 0
        local api, _, _, after = load_case(nil, function()
            n = n + 1
            return n <= 3 and "fonts/ArialUnicodeMS" or "materials/fonts/arial"
        end)
        local old_fonts = Fonts
        Fonts = after
        local scan = api.inspect_fonts()
        Fonts = old_fonts
        H.equal(scan.state, "partial_swap")
        H.equal(scan.unicode, 3)
        H.equal(scan.other, 5)
    end)
end
