-- (#717) Gear-parent accent twin parity. 7d31174 (#611) gave every enabled
-- gear-parent row the warm-tan chrome accent {255,160,146,101} in the mission
-- twin (_mod_tweaker_view.lua) but not the keep twin (_mod_tweaker_state.lua),
-- so the same master/advanced rows rendered plain font_default in the keep Mod
-- Tweaker. 3353d708 mirrored the block; the #717 hardening then collapsed both
-- copies into ONE callable policy site (defs.apply_gear_parent_accent in
-- _mod_tweaker_definitions.lua) that both twins' _append_row gear branches
-- consume, so the twins cannot drift again. This test pins the single-site
-- shape AND functionally drives the extracted pure helper through the three
-- policy cases the /gut_regression_test runtime check also covers.
return function(H, repo_root)
    local root = repo_root .. "/gui_tweaker_dev/scripts/mods/gui_tweaker_dev/"

    local function read(name)
        local file = assert(io.open(root .. name, "rb"))
        local source = file:read("*a")
        file:close()
        return source
    end

    H.test("both dev twins consume the ONE shared gear-parent accent policy", function()
        for _, name in ipairs({ "_mod_tweaker_view.lua", "_mod_tweaker_state.lua" }) do
            local source = read(name)
            H.truthy(string.find(source, "defs.apply_gear_parent_accent(row, has_gear)", 1, true),
                name .. " must call the shared gear-parent accent policy (#611/#717)")
            H.truthy(not string.find(source, "255, 160, 146, 101", 1, true),
                name .. " must NOT carry an inline accent literal - the color decision"
                    .. " lives only in _mod_tweaker_definitions.lua")
        end
    end)

    H.test("definitions owns the single accent decision site", function()
        local source = read("_mod_tweaker_definitions.lua")
        H.truthy(string.find(source, "local function apply_gear_parent_accent(row, has_gear)", 1, true),
            "definitions must define apply_gear_parent_accent(row, has_gear)")
        H.truthy(string.find(source,
            "accent[1], accent[2], accent[3], accent[4] = 255, 160, 146, 101", 1, true),
            "policy must write the warm-tan accent Colors.font_button_normal (#611/#717)")
        H.truthy(string.find(source, "not row._disabled_in_vmf", 1, true),
            "policy must keep disabled VMF rows grey instead of accenting them")
        H.truthy(string.find(source, "row._advanced_parent_accent = true", 1, true),
            "policy must mark gear-parent rows with _advanced_parent_accent")
    end)

    H.test("runtime regression check for the accent policy is registered", function()
        local source = read("_gut_mod_tweaker_contracts.lua")
        H.truthy(string.find(source, '_rt_register("issue717_gear_parent_accent_policy"', 1, true),
            "contracts must register the issue717 accent-policy runtime check")
        H.truthy(string.find(source, "[gut:717] accent policy OK", 1, true),
            "runtime check must printf the #717 card evidence needle")
    end)

    H.test("extracted policy drives parent/disabled/child exactly", function()
        -- The helper is deliberately PURE (no engine deps), so extract its chunk
        -- (function start to the first column-0 `end`) and run it under host Lua.
        local source = read("_mod_tweaker_definitions.lua")
        local chunk = string.match(source,
            "(local function apply_gear_parent_accent%(row, has_gear%).-\nend\n)")
        H.truthy(chunk, "could not extract the apply_gear_parent_accent chunk")
        local factory = assert(loadstring(chunk .. "\nreturn apply_gear_parent_accent"))
        local apply = factory()
        H.equal(type(apply), "function", "extracted policy must be callable")

        -- Enabled gear parent -> warm tan (utils/colors.lua:1021-1026) + marker.
        local parent = { style = { label = { text_color = { 255, 255, 255, 255 } } } }
        H.equal(apply(parent, true), true, "enabled gear parent must take the accent")
        H.deep_equal(parent.style.label.text_color, { 255, 160, 146, 101 },
            "enabled gear parent must be font_button_normal warm tan")
        H.equal(parent._advanced_parent_accent, true,
            "gear parent must carry the _advanced_parent_accent marker")

        -- VMF-disabled gear parent -> existing grey preserved (still marked).
        local disabled = { _disabled_in_vmf = true,
            style = { label = { text_color = { 255, 128, 128, 128 } } } }
        H.equal(apply(disabled, true), false, "disabled parent must not be accented")
        H.deep_equal(disabled.style.label.text_color, { 255, 128, 128, 128 },
            "disabled gear parent must keep its grey tint")

        -- Ordinary non-gear child -> completely untouched.
        local child = { style = { label = { text_color = { 255, 255, 255, 255 } } } }
        H.equal(apply(child, false), false, "ordinary child must not be accented")
        H.deep_equal(child.style.label.text_color, { 255, 255, 255, 255 },
            "ordinary child row must keep its authored color")
        H.equal(child._advanced_parent_accent, nil,
            "ordinary child must not gain the gear-parent marker")
    end)
end
