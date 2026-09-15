return function(H, repo_root)
    local path = repo_root
        .. "/gui_tweaker_dev/scripts/mods/gui_tweaker_dev/_gut_loadout_page_mapper.lua"
    local Mapper = assert(loadfile(path))()

    H.test("GUT #231 thirty slots are five pages of six", function()
        H.equal(Mapper.PAGE_SIZE, 6)
        H.equal(Mapper.TARGET, 30)
        H.equal(Mapper.page_count(0), 1)
        H.equal(Mapper.page_count(1), 1)
        H.equal(Mapper.page_count(6), 1)
        H.equal(Mapper.page_count(7), 2)
        H.equal(Mapper.page_count(30), 5)
        H.equal(Mapper.page_count(31), 6)
        H.equal(Mapper.page_count("x"), 1)
    end)

    H.test("GUT #231 logical, page and physical slot round-trip", function()
        H.equal(Mapper.page_of(1), 1)
        H.equal(Mapper.slot_of(1), 1)
        H.equal(Mapper.page_of(6), 1)
        H.equal(Mapper.slot_of(6), 6)
        H.equal(Mapper.page_of(7), 2)
        H.equal(Mapper.slot_of(7), 1)
        H.equal(Mapper.page_of(30), 5)
        H.equal(Mapper.slot_of(30), 6)
        H.equal(Mapper.logical_of(2, 3), 9)
        H.equal(Mapper.logical_of(5, 6), 30)
        H.equal(Mapper.logical_of(1, 7), nil)
        H.equal(Mapper.logical_of(0, 1), nil)
        H.equal(Mapper.page_of(0), nil)
        H.equal(Mapper.slot_of(2.5), nil)
        H.equal(Mapper.physical_slot(9, 2), 3)
        H.equal(Mapper.physical_slot(9, 1), nil)
        H.equal(Mapper.physical_slot(nil, 1), nil)
        H.equal(Mapper.check_bijection(30), nil)
        H.equal(Mapper.check_bijection(30, 4), nil)
    end)

    H.test("GUT #231 visible count, clamp and auto-reveal", function()
        H.equal(Mapper.visible_count(1, 6), 6)
        H.equal(Mapper.visible_count(2, 6), 0)
        H.equal(Mapper.visible_count(2, 9), 3)
        H.equal(Mapper.visible_count(5, 30), 6)
        H.equal(Mapper.clamp_page(9, 9), 2)
        H.equal(Mapper.clamp_page(0, 9), 1)
        H.equal(Mapper.clamp_page(nil, 9), 1)
        H.equal(Mapper.reveal_page(9, 9, 1), 2)
        H.equal(Mapper.reveal_page(3, 9, 2), 1)
        H.equal(Mapper.reveal_page(40, 9, 2), 2)
        H.equal(Mapper.reveal_page(nil, 9, 7), 2)
        H.equal(Mapper.reveal_page(30, 30, 1), 5)
    end)

    H.test("GUT #231 strip geometry reserves the next-page slot only when paging", function()
        local single = Mapper.layout(1, 6, 48, 5)
        H.equal(single.show_controls, false)
        H.equal(single.visible, 6)
        H.equal(single.strip_offset, -265)
        H.equal(single.add_hover_offset, 318)
        H.equal(single.page_count, 1)
        local first = Mapper.layout(1, 9, 48, 5)
        H.equal(first.show_controls, true)
        H.equal(first.visible, 6)
        H.equal(first.strip_offset, -318)
        H.equal(first.add_hover_offset, 371)
        H.equal(first.has_previous, false)
        H.equal(first.has_next, true)
        local last = Mapper.layout(2, 9, 48, 5)
        H.equal(last.visible, 3)
        H.equal(last.strip_offset, -159)
        H.equal(last.add_hover_offset, 212)
        H.equal(last.has_previous, true)
        H.equal(last.has_next, false)
        H.equal(last.prev_offset, -53)
        H.equal(last.next_offset, -53)
        local clamped = Mapper.layout(9, 9, 48, 5)
        H.equal(clamped.page, 2)
        local empty = Mapper.layout(1, 0, 48, 5)
        H.equal(empty.visible, 0)
        H.equal(empty.strip_offset, 0)
    end)

    H.test("GUT #231 text Roman numerals never request a texture", function()
        local expected = {
            [1] = "I", [2] = "II", [3] = "III", [4] = "IV", [5] = "V", [6] = "VI", [7] = "VII",
            [8] = "VIII", [9] = "IX", [10] = "X", [14] = "XIV", [19] = "XIX", [20] = "XX",
            [24] = "XXIV", [29] = "XXIX", [30] = "XXX", [3999] = "MMMCMXCIX",
        }
        for n, roman in pairs(expected) do
            H.equal(Mapper.roman(n), roman, "roman(" .. n .. ")")
        end
        H.equal(Mapper.roman(0), "")
        H.equal(Mapper.roman(-4), "")
        H.equal(Mapper.roman(2.5), "")
        H.equal(Mapper.roman(4000), "")
        H.equal(Mapper.roman("IX"), "")
        for n = 1, 30 do
            H.equal(Mapper.roman(n):find("^[IVX]+$") ~= nil, true, "numeral " .. n .. " uses only I, V, X")
        end
    end)

    H.test("GUT #231 paging is modded STORE Adventure only", function()
        H.equal(Mapper.should_page(true, "store", "characters_data"), true)
        H.equal(Mapper.should_page(false, "store", "characters_data"), false)
        H.equal(Mapper.should_page(true, "readonly", "characters_data"), false)
        H.equal(Mapper.should_page(true, "off", "characters_data"), false)
        H.equal(Mapper.should_page(true, "store", "vs_characters_data"), false)
        H.equal(Mapper.should_page(true, "store", nil), false)
        H.equal(Mapper.should_page(nil, "store", "characters_data"), false)
    end)

    H.test("GUT #231 runtime owner never indexes the physical buttons by a logical index", function()
        local owner_path = repo_root
            .. "/gui_tweaker_dev/scripts/mods/gui_tweaker_dev/_gut_loadout_paging.lua"
        local file = assert(io.open(owner_path, "rb"))
        local source = file:read("*a")
        file:close()
        local forbidden = {
            "_loadout_button_widgets[self._",
            "_loadout_button_widgets[loadout_index]",
            "_loadout_button_widgets[new_context_menu_loadout_index]",
            "_loadout_button_widgets[idx]",
            "loadout_icon_",
            "custom_loadout_",
        }
        for _, needle in ipairs(forbidden) do
            H.equal(source:find(needle, 1, true), nil, "forbidden access: " .. needle)
        end
        H.equal(source:find('"_show_context_menu"', 1, true), nil, "no second _show_context_menu hook")
        H.equal(source:find('"_save_bot_equipment"', 1, true), nil, "no second _save_bot_equipment hook")
        H.equal(source:find('"_populate_context_menu_loadout"', 1, true), nil,
            "no second _populate_context_menu_loadout hook")
        H.equal(source:find("Mapper.slot_of(logical)", 1, true) ~= nil, true, "widget lookup goes through the mapper")
    end)
end
