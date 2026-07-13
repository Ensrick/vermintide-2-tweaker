return function(H, repo_root)
    local module_path = repo_root
        .. "/gui_tweaker_dev/scripts/mods/gui_tweaker_dev/_mod_tweaker_numeric_editor.lua"
    local Numeric = assert(loadfile(module_path))()

    H.test("numeric caret uses centered glyph origin and prefix advance", function()
        H.equal(Numeric.centered_text_left(100, 50, 20, 2), 113)
        H.equal(Numeric.caret_x(100, 50, 20, 2, 7), 120)
        H.equal(Numeric.caret_x(100, 50, 20, -1, 20), 136)
    end)

    H.test("numeric click resolves proportional sign decimal and digit boundaries", function()
        -- Synthetic measured advances for "-12.50". The widths deliberately vary;
        -- a character-count approximation cannot pass every midpoint.
        local advances = { 0, 5, 12, 19, 22, 29, 36 }
        local left = 40
        for index = 0, #advances - 1 do
            local x = left + advances[index + 1]
            H.equal(Numeric.nearest_index(x, left, advances), index)
        end
        H.equal(Numeric.nearest_index(left - 20, left, advances), 0)
        H.equal(Numeric.nearest_index(left + 100, left, advances), 6)
        H.equal(Numeric.nearest_index(left + 20.6, left, advances), 4)
    end)

    H.test("numeric caret geometry is invariant under field translation", function()
        local a = Numeric.caret_x(0, 64, 31, 1.5, 17)
        local b = Numeric.caret_x(275, 64, 31, 1.5, 17)
        H.equal(b - a, 275)
    end)
end
