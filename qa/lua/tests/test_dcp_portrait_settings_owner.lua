return function(H, repo_root)
    local root = repo_root .. "/dynamic_cosmetic_portraits/scripts/mods/dynamic_cosmetic_portraits/"
    local owner = assert(loadfile(root .. "_dcp_portrait_settings_owner.lua"))()
    local source_file = assert(io.open(root .. "dynamic_cosmetic_portraits.lua", "rb"))
    local source = source_file:read("*a")
    source_file:close()

    H.test("DCP portrait settings owner preserves originals across repeat apply", function()
        local state = owner.new()
        local career = { portrait_image = "vanilla_hud", picking_image = "vanilla_medium" }
        local ok = owner.apply(state, career, {
            hud = "custom_hud_a",
            medium = "custom_medium_a",
        })
        H.truthy(ok)
        ok = owner.apply(state, career, {
            hud = "custom_hud_b",
            medium = "custom_medium_b",
        })
        H.truthy(ok)
        H.equal(state.original_portrait_image, "vanilla_hud")
        H.equal(state.original_picking_image, "vanilla_medium")
        H.equal(career.portrait_image, "custom_hud_b")
        H.equal(career.picking_image, "custom_medium_b")
    end)

    H.test("DCP portrait settings owner restores exact values including nil", function()
        local state = owner.new()
        local career = {}
        local ok = owner.apply(state, career, {
            hud = "custom_hud",
            medium = "custom_medium",
        })
        H.truthy(ok)
        ok = owner.restore(state, career)
        H.truthy(ok)
        H.equal(career.portrait_image, nil)
        H.equal(career.picking_image, nil)
        H.equal(state.active, false)
        H.equal(state.captured, false)
        H.equal(state.career, nil)
    end)

    H.test("DCP portrait settings owner rejects cross-career mutation", function()
        local state = owner.new()
        local first = { portrait_image = "first_hud", picking_image = "first_medium" }
        local second = { portrait_image = "second_hud", picking_image = "second_medium" }
        H.truthy(owner.apply(state, first, { hud = "custom", medium = "custom_medium" }))
        local ok, reason = owner.apply(state, second, {
            hud = "foreign_custom",
            medium = "foreign_medium",
        })
        H.equal(ok, false)
        H.equal(reason, "career-mismatch")
        H.equal(second.portrait_image, "second_hud")
        H.equal(second.picking_image, "second_medium")
        ok, reason = owner.restore(state, second)
        H.equal(ok, false)
        H.equal(reason, "career-mismatch")
        H.truthy(state.active)
    end)

    H.test("DCP portrait settings owner rolls back a throwing apply", function()
        local state = owner.new()
        local values = { portrait_image = "vanilla_hud", picking_image = "vanilla_medium" }
        local career = setmetatable({}, {
            __index = values,
            __newindex = function(_, key, value)
                if key == "picking_image" and value == "throw_medium" then
                    error("synthetic apply failure")
                end
                values[key] = value
            end,
        })
        local ok, reason = owner.apply(state, career, {
            hud = "custom_hud",
            medium = "throw_medium",
        })
        H.equal(ok, false)
        H.truthy(reason:find("apply%-failed"))
        H.equal(values.portrait_image, "vanilla_hud")
        H.equal(values.picking_image, "vanilla_medium")
        H.equal(state.active, false)
        H.equal(state.captured, false)
    end)

    H.test("DCP portrait settings owner retains capture when apply rollback throws", function()
        local state = owner.new()
        local values = { portrait_image = "vanilla_hud", picking_image = "vanilla_medium" }
        local rollback_blocked = true
        local career = setmetatable({}, {
            __index = values,
            __newindex = function(_, key, value)
                if key == "picking_image" and value == "throw_medium" then
                    error("synthetic apply failure")
                end
                if rollback_blocked and key == "portrait_image" and value == "vanilla_hud" then
                    error("synthetic rollback failure")
                end
                values[key] = value
            end,
        })
        local ok, reason = owner.apply(state, career, {
            hud = "custom_hud",
            medium = "throw_medium",
        })
        H.equal(ok, false)
        H.truthy(reason:find("rollback%-failed"))
        H.equal(values.portrait_image, "custom_hud")
        H.equal(state.original_portrait_image, "vanilla_hud")
        H.equal(state.original_picking_image, "vanilla_medium")
        H.equal(state.career, career)
        H.truthy(state.active)
        H.truthy(state.captured)

        rollback_blocked = false
        ok, reason = owner.restore(state, career)
        H.equal(ok, true, tostring(reason))
        H.equal(values.portrait_image, "vanilla_hud")
        H.equal(values.picking_image, "vanilla_medium")
        H.equal(state.active, false)
        H.equal(state.captured, false)
    end)

    H.test("DCP portrait settings owner retains ownership after throwing restore", function()
        local state = owner.new()
        local values = { portrait_image = "vanilla_hud", picking_image = "vanilla_medium" }
        local fail_restore = false
        local career = setmetatable({}, {
            __index = values,
            __newindex = function(_, key, value)
                if fail_restore and key == "picking_image" and value == "vanilla_medium" then
                    error("synthetic restore failure")
                end
                values[key] = value
            end,
        })
        H.truthy(owner.apply(state, career, {
            hud = "custom_hud",
            medium = "custom_medium",
        }))
        fail_restore = true
        local ok, reason = owner.restore(state, career)
        H.equal(ok, false)
        H.truthy(reason:find("restore%-failed"))
        H.equal(values.portrait_image, "custom_hud")
        H.equal(values.picking_image, "custom_medium")
        H.truthy(state.active)
        H.truthy(state.captured)
        H.equal(state.career, career)
    end)

    H.test("DCP portrait settings owner rejects a silently ignored apply", function()
        local state = owner.new()
        local values = { portrait_image = "vanilla_hud", picking_image = "vanilla_medium" }
        local career = setmetatable({}, {
            __index = values,
            __newindex = function()
                -- A proxy can legally consume a write without throwing. The
                -- owner must verify the requested pair became observable.
            end,
        })
        local ok, reason = owner.apply(state, career, {
            hud = "custom_hud",
            medium = "custom_medium",
        })
        H.equal(ok, false)
        H.truthy(reason:find("write%-not%-visible"))
        H.equal(values.portrait_image, "vanilla_hud")
        H.equal(values.picking_image, "vanilla_medium")
        H.equal(state.active, false)
        H.equal(state.captured, false)
        H.equal(state.career, nil)
    end)

    H.test("DCP portrait settings owner retains ownership after silently ignored restore", function()
        local state = owner.new()
        local values = { portrait_image = "vanilla_hud", picking_image = "vanilla_medium" }
        local ignore_restore = false
        local career = setmetatable({}, {
            __index = values,
            __newindex = function(_, key, value)
                if ignore_restore and (value == "vanilla_hud" or value == "vanilla_medium") then
                    return
                end
                values[key] = value
            end,
        })
        H.truthy(owner.apply(state, career, {
            hud = "custom_hud",
            medium = "custom_medium",
        }))
        ignore_restore = true
        local ok, reason = owner.restore(state, career)
        H.equal(ok, false)
        H.truthy(reason:find("write%-not%-visible"))
        H.equal(values.portrait_image, "custom_hud")
        H.equal(values.picking_image, "custom_medium")
        H.truthy(state.active)
        H.truthy(state.captured)
        H.equal(state.career, career)

        ignore_restore = false
        ok, reason = owner.restore(state, career)
        H.equal(ok, true, tostring(reason))
        H.equal(values.portrait_image, "vanilla_hud")
        H.equal(values.picking_image, "vanilla_medium")
    end)

    H.test("DCP portrait settings owner repeat apply of the shown pair writes nothing", function()
        local state = owner.new()
        local values = { portrait_image = "vanilla_hud", picking_image = "vanilla_medium" }
        local writes = 0
        local career = setmetatable({}, {
            __index = values,
            __newindex = function(_, key, value)
                writes = writes + 1
                values[key] = value
            end,
        })
        local pair = { hud = "custom_hud", medium = "custom_medium" }
        H.truthy(owner.apply(state, career, pair))
        H.equal(writes, 2)
        H.truthy(owner.apply(state, career, pair))
        H.equal(writes, 2, "per-frame sync of an owned, visible pair must not write")
        values.portrait_image = "drifted_hud"
        H.truthy(owner.apply(state, career, pair))
        H.equal(values.portrait_image, "custom_hud", "a drifted row is rewritten")
        H.equal(state.original_portrait_image, "vanilla_hud")
    end)

    local custom_sets = {
        { mercenary_hat_0001 = { hud = "portrait_custom_0001", medium = "medium_custom_0001" } },
        { skin_es_default = { hud = "portrait_custom_skin", medium = "medium_custom_skin" } },
    }
    local function live_row()
        return {
            portrait_image = "unit_frame_portrait_kruber_mercenary",
            picking_image = "medium_unit_frame_portrait_kruber_mercenary",
        }
    end

    H.test("DCP issue509 check passes on a healthy live row and owner", function()
        local live = live_row()
        H.equal(owner.check_transaction({ live_career = live, custom_sets = custom_sets }), nil)
        H.equal(live.portrait_image, "unit_frame_portrait_kruber_mercenary")
        H.equal(live.picking_image, "medium_unit_frame_portrait_kruber_mercenary")

        local production = owner.new()
        H.truthy(owner.apply(production, live, custom_sets[1].mercenary_hat_0001))
        H.equal(owner.check_transaction({
            live_career = live, production = production, custom_sets = custom_sets,
        }), nil)
        H.equal(live.portrait_image, "portrait_custom_0001", "identity pass keeps the swap")
        H.truthy(production.active)
        H.truthy(owner.restore(production, live))
        H.equal(live.portrait_image, "unit_frame_portrait_kruber_mercenary")

        H.equal(owner.check_transaction(nil), nil, "no live row: live halves skip")
    end)

    H.test("DCP issue509 check fails when the live row refuses writes", function()
        local values = live_row()
        local live = setmetatable({}, {
            __index = values,
            __newindex = function() error("synthetic read-only career row") end,
        })
        local reason = owner.check_transaction({ live_career = live, custom_sets = custom_sets })
        H.truthy(type(reason) == "string" and reason:find("live career row apply failed", 1, true),
            tostring(reason))
        H.equal(values.portrait_image, "unit_frame_portrait_kruber_mercenary")
    end)

    H.test("DCP issue509 check fails on broken production ownership", function()
        local live = live_row()
        local other = live_row()
        local production = owner.new()
        H.truthy(owner.apply(production, other, custom_sets[1].mercenary_hat_0001))
        local reason = owner.check_transaction({
            live_career = live, production = production, custom_sets = custom_sets,
        })
        H.truthy(type(reason) == "string" and reason:find("other than the live", 1, true),
            tostring(reason))

        -- Leak class: the vanilla capture holds a DCP portrait.
        local leaked = owner.new()
        live.portrait_image = "portrait_custom_skin"
        H.truthy(owner.apply(leaked, live, custom_sets[1].mercenary_hat_0001))
        reason = owner.check_transaction({
            live_career = live, production = leaked, custom_sets = custom_sets,
        })
        H.truthy(type(reason) == "string" and reason:find("skin_es_default", 1, true),
            tostring(reason))

        local orphan = owner.new()
        orphan.active = true
        reason = owner.check_transaction({ live_career = live, production = orphan })
        H.truthy(type(reason) == "string" and reason:find("without a captured", 1, true),
            tostring(reason))
    end)

    H.test("DCP issue509 rejects a captured custom hero-select original even with vanilla HUD", function()
        local live = live_row()
        live.picking_image = "medium_custom_skin"
        local production = owner.new()
        H.truthy(owner.apply(production, live, custom_sets[1].mercenary_hat_0001))
        local reason = owner.check_transaction({
            live_career = live, production = production, custom_sets = custom_sets,
        })
        H.truthy(type(reason) == "string" and reason:find("skin_es_default", 1, true),
            "custom picker original must be diagnosed: " .. tostring(reason))
    end)

    H.test("DCP issue509 vanilla fallback and unowned-swap check do not depend on an apply", function()
        local live = live_row()
        local production = owner.new()
        H.equal(owner.vanilla_portrait(production, live), "unit_frame_portrait_kruber_mercenary",
            "never-applied owner: the live row is vanilla")
        H.truthy(owner.apply(production, live, custom_sets[1].mercenary_hat_0001))
        H.equal(owner.vanilla_portrait(production, live), "unit_frame_portrait_kruber_mercenary",
            "active owner: the captured original, not the swap")
        H.truthy(owner.restore(production, live))
        H.equal(owner.vanilla_portrait(production, live), "unit_frame_portrait_kruber_mercenary")
        H.equal(owner.vanilla_portrait(nil, nil), nil)

        live.picking_image = "medium_custom_skin"
        local reason = owner.check_transaction({
            live_career = live, production = production, custom_sets = custom_sets,
        })
        H.truthy(type(reason) == "string" and reason:find("unowned DCP portrait skin_es_default", 1, true),
            tostring(reason))
        local _, note = owner.check_transaction({ production = production, custom_sets = custom_sets })
        H.truthy(type(note) == "string" and note:find("live half skipped", 1, true), tostring(note))
    end)

    local function block(start_needle, end_needle)
        local first = source:find(start_needle, 1, true)
        H.truthy(first, start_needle .. " missing")
        local last = source:find(end_needle, first, true)
        H.truthy(last, start_needle .. " has no end")
        return source:sub(first, last)
    end

    H.test("DCP issue509 named check and live paths route through the owner", function()
        H.truthy(source:find(
            'scripts/mods/dynamic_cosmetic_portraits/_dcp_portrait_settings_owner',
            1, true))
        local check = block('_rt_register("career_settings_swap_saves_and_restores"', "\nend)")
        H.truthy(check:find("_portrait_settings_owner.check_transaction(", 1, true),
            "named check must execute the production owner")
        H.truthy(check:find("production = _portrait_settings", 1, true),
            "named check must inspect the live production state")
        H.truthy(check:find("SPProfiles[5].careers[1]", 1, true),
            "named check must pass the live Mercenary row")
        H.equal(check:find("save_needle", 1, true), nil, "no source-spelling stand-in")

        local sync = block("local function _sync_portrait_settings()", "\nend\n")
        H.truthy(sync:find("_portrait_settings_owner.apply(_portrait_settings, career", 1, true))
        H.equal(sync:find("career.portrait_image =", 1, true), nil,
            "sync must not write the career row directly")
        local restore = block("local function _restore_portrait_settings(", "\nend\n")
        H.truthy(restore:find("_portrait_settings_owner.restore(_portrait_settings", 1, true))
        H.equal(restore:find("career.portrait_image =", 1, true), nil,
            "restore must not write the career row directly")
        local unload = block("mod.on_unload = function()", "\nend\n")
        H.truthy(unload:find("_restore_portrait_settings()", 1, true))
    end)
end
