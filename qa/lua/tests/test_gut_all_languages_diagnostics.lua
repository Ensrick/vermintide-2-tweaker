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
        local old_get_mod, old_printf, old_fonts, old_managers = get_mod, printf, Fonts, Managers
        local commands, echoes, logs = {}, {}, {}
        local gut = {
            command = function(_, name, _, fn) commands[name] = fn end,
            echo = function(_, format_string, ...)
                echoes[#echoes + 1] = string.format(format_string, ...)
            end,
        }
        get_mod = function(name)
            if name == "gut_dev" then return gut end
            if name == "support-all-languages" then return provider end
        end
        printf = function(format_string, ...)
            logs[#logs + 1] = string.format(format_string, ...)
        end
        Managers = {
            player = {
                human_players = function()
                    return {
                        { name = function() return "ASCII" end },
                        { name = function() return string.char(0xD0, 0x98, 0xD0, 0xBC, 0xD1, 0x8F) end },
                    }
                end,
            },
        }
        Fonts = {}
        for _, key in ipairs(keys) do Fonts[key] = { material_for(key), 16, "arial" } end

        local before = {}
        for _, key in ipairs(keys) do before[key] = Fonts[key][1] end
        local ok, api = pcall(dofile, module_path)
        local after = Fonts

        get_mod, printf, Fonts, Managers = old_get_mod, old_printf, old_fonts, old_managers
        assert(ok, api)
        return api, commands, before, after, echoes, logs
    end

    H.test("GUT #340 diagnostics never mutate vanilla Fonts", function()
        local api, commands, before, after, echoes, logs = load_case(nil, function()
            return "materials/fonts/arial"
        end)
        H.equal(api.does_font_swap, false)
        H.equal(api.installs_hooks, false)
        H.equal(type(commands.gut_all_languages_status), "function")
        for _, key in ipairs(keys) do H.equal(after[key][1], before[key]) end
        local old_fonts = Fonts
        Fonts = after
        local scan = api.inspect_fonts()
        local old_managers = Managers
        Managers = { player = { human_players = function()
            return { { name = function() return "ASCII" end } }
        end } }
        commands.gut_all_languages_status()
        Managers = old_managers
        Fonts = old_fonts
        H.equal(scan.unicode, 0)
        H.equal(scan.total, 8)
        H.equal(scan.state, "vanilla_font_active")
        H.truthy(#echoes >= 8, "status command should emit status plus six bounded glyph rows")
        H.truthy(#logs >= 2, "status command should log the bounded player-name UTF-8 report")
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
        H.equal(scan.vanilla, 5)
        H.equal(scan.other, 0)
    end)

    H.test("GUT #340 UTF-8 metrics separate intact bytes from missing glyphs", function()
        local api = select(1, load_case(nil, function() return "materials/fonts/arial" end))
        local ascii = api.utf8_metrics("Kruber")
        H.equal(ascii.valid, true)
        H.equal(ascii.codepoints, 6)
        H.equal(ascii.non_ascii, 0)

        local cyrillic = api.glyph_samples[3].text
        local unicode = api.utf8_metrics(cyrillic)
        H.equal(unicode.valid, true)
        H.equal(unicode.codepoints, 6)
        H.equal(unicode.non_ascii, 6)

        local malformed = api.utf8_metrics(string.char(0xE2, 0x28, 0xA1))
        H.equal(malformed.valid, false)
        H.equal(malformed.reason, "invalid_continuation")
        H.equal(malformed.offset, 2)
    end)

    H.test("GUT #340 glyph matrix covers six language families with valid UTF-8", function()
        local api = select(1, load_case(nil, function() return "materials/fonts/arial" end))
        H.equal(#api.glyph_samples, 6)
        for _, sample in ipairs(api.glyph_samples) do
            H.equal(type(sample.label), "string")
            H.equal(api.utf8_metrics(sample.text).valid, true)
        end
    end)

    H.test("GUT #340 player-name probe reports bytes without rewriting names", function()
        local api = select(1, load_case(nil, function() return "materials/fonts/arial" end))
        local old_managers = Managers
        local utf8_name = string.char(0xE6, 0x97, 0xA5, 0xE6, 0x9C, 0xAC)
        Managers = { player = { human_players = function()
            return {
                { name = function() return "ASCII" end },
                { name = function() return utf8_name end },
                { name = function() return string.char(0xC0, 0xAF) end },
            }
        end } }
        local report = api.inspect_player_names()
        Managers = old_managers
        H.equal(report.total, 3)
        H.equal(report.valid, 2)
        H.equal(report.invalid, 1)
        H.equal(report.non_ascii, 1)
        H.equal(report.state, "malformed_name_bytes")
    end)
end
