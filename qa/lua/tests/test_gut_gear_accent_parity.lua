-- (#717) Gear-parent accent twin parity. 7d31174 (#611) gave every enabled
-- gear-parent row the warm-tan chrome accent {255,160,146,101} in the mission
-- twin (_mod_tweaker_view.lua) but not the keep twin (_mod_tweaker_state.lua),
-- so the same master/advanced rows rendered plain font_default in the keep Mod
-- Tweaker. Both build-time twins must carry the identical accent block inside
-- their _append_row gear branch, and the accent must stay a build-time style
-- write (no new widget pass).
return function(H, repo_root)
    local root = repo_root .. "/gui_tweaker_dev/scripts/mods/gui_tweaker_dev/"

    local function read(name)
        local file = assert(io.open(root .. name, "rb"))
        local source = file:read("*a")
        file:close()
        return source
    end

    H.test("both dev twins tan-accent gear-parent rows identically", function()
        for _, name in ipairs({ "_mod_tweaker_view.lua", "_mod_tweaker_state.lua" }) do
            local source = read(name)
            H.truthy(string.find(source, "_advanced_parent_accent", 1, true),
                name .. " must mark gear-parent rows with _advanced_parent_accent")
            H.truthy(string.find(source,
                "accent[1], accent[2], accent[3], accent[4] = 255, 160, 146, 101", 1, true),
                name .. " must write the warm-tan gear-parent accent (#611/#717)")
            H.truthy(string.find(source, "not row._disabled_in_vmf", 1, true),
                name .. " must keep disabled VMF rows grey instead of accenting them")
        end
    end)
end
