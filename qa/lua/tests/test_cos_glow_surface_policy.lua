return function(H, repo_root)
    local base = repo_root .. "/cosmetics_tweaker/scripts/mods/cosmetics_tweaker/"
    local Policy = assert(loadfile(base .. "_cos_glow_surface_policy.lua"))()
    local Instance = assert(loadfile(base .. "_cos_glow_instance_policy.lua"))()

    -- The real shader-variable brightness map shape from _cos_glow.lua.
    local VAR_BRIGHTNESS = {
        rune_emissive_color = { brightness = 9 },
        color_glow_high     = { brightness = 4 },
        color_glow_low      = { brightness = 1 },
        color_smoke_high    = { brightness = 0.22 },
        color_smoke_low     = { brightness = 0.06 },
        color_dots          = { brightness = 8.35 },
    }

    local function recorder()
        local writes = {}
        return writes, function(unit, var_name, x, y, z)
            writes[#writes + 1] = { unit = unit, var = var_name, x = x, y = y, z = z }
        end
    end

    -- Fixture units carry their bound render identity (the ctx shape
    -- _bind_glow_unit stores); match routes through the REAL instance policy.
    local function deps_for(ctx_by_unit, write)
        return {
            var_brightness = VAR_BRIGHTNESS,
            write = write,
            is_unit = function(u) return type(u) == "table" and u.alive == true end,
            match = function(u, peer_state)
                return Instance.remote_match(ctx_by_unit[u], peer_state)
            end,
        }
    end

    H.test("cos surface glow resolves transport first, local active as local fallback", function()
        local transported = { active_per_item_glow = { rune = { intensity = 1 } } }
        local by_peer = { ["peer-a"] = transported }
        local state, source = Policy.resolve_wearer_state(by_peer, "peer-a", true, {
            active_per_item_glow = { rune = { intensity = 2 } },
        })
        H.equal(state, transported, "transported payload is authoritative")
        H.equal(source, "transport")

        local local_payload = { active_per_item_glow = { rune = { intensity = 2 } } }
        state, source = Policy.resolve_wearer_state({}, "peer-local", true, local_payload)
        H.equal(state, local_payload)
        H.equal(source, "local_active")

        state, source = Policy.resolve_wearer_state({}, "peer-remote", false, local_payload)
        H.equal(state, nil, "a remote wearer must never read the local active payload")
        H.equal(source, "no-payload")

        state, source = Policy.resolve_wearer_state({}, nil, true, local_payload)
        H.equal(state, nil)
        H.equal(source, "no-wearer")
    end)

    H.test("cos surface glow repaints exactly the identity-matched units", function()
        local matched_unit = { alive = true }
        local wrong_skin = { alive = true }
        local dead = { alive = false }
        local ctx_by_unit = {
            [matched_unit] = { skin = "es_1h_mace_skin_02" },
            [wrong_skin] = { skin = "some_other_illusion" },
        }
        local peer_state = {
            active_per_item_glow_identity = "backend:b1|skin:es_1h_mace_skin_02",
            active_per_item_glow = {
                rune = { r = 255, g = 0, b = 0, intensity = 1 },
            },
        }
        local writes, write = recorder()
        local painted, considered, matched = Policy.repaint(
            { matched_unit, wrong_skin, dead }, peer_state,
            deps_for(ctx_by_unit, write))
        H.equal(considered, 2, "dead units never considered")
        H.equal(matched, 1, "only the exact-illusion unit matches (#48 bleed guard)")
        H.equal(painted, 1)
        H.equal(#writes, 1, "one active component writes one variable")
        H.equal(writes[1].unit, matched_unit)
        H.equal(writes[1].var, "rune_emissive_color")
        -- Real HDR math: 255 clamped, scale = 9 * 1 / 255 -> r = 9.
        H.equal(writes[1].x, 9)
        H.equal(writes[1].y, 0)
        H.equal(writes[1].z, 0)
    end)

    H.test("cos surface glow spans component variable pairs and honors disabled", function()
        local unit = { alive = true }
        local ctx = { [unit] = { skin = "" } }
        local peer_state = {
            active_per_item_glow_identity = "backend:b2|skin:",
            active_per_item_glow = {
                lower = { r = 0, g = 255, b = 0, intensity = 2 },
                upper = { r = 0, g = 0, b = 255, intensity = 1 },
            },
        }
        local writes, write = recorder()
        local painted = Policy.repaint({ unit }, peer_state, deps_for(ctx, write))
        H.equal(painted, 1)
        local vars = {}
        for _, w in ipairs(writes) do vars[w.var] = w end
        H.equal(vars.color_glow_high ~= nil, true, "lower spans glow_high")
        H.equal(vars.color_glow_low ~= nil, true, "lower spans glow_low")
        H.equal(vars.color_smoke_high ~= nil, true, "upper spans smoke_high")
        H.equal(vars.color_smoke_low ~= nil, true, "upper spans smoke_low")
        H.equal(#writes, 4)
        -- lower g: 255 * (4 * 2 / 255) = 8 on glow_high; 255 * (1 * 2 / 255) = 2 on glow_low.
        H.equal(vars.color_glow_high.y, 8)
        H.equal(vars.color_glow_low.y, 2)

        -- Disabled: zero-paints every known variable and claims the unit.
        local zwrites, zwrite = recorder()
        local zpainted = Policy.repaint({ unit }, {
            active_per_item_glow_identity = "backend:b2|skin:",
            active_per_item_glow = { disabled = true },
        }, deps_for(ctx, zwrite))
        H.equal(zpainted, 1)
        H.equal(#zwrites, 6, "disabled zero-paints all six variables")
        for _, w in ipairs(zwrites) do
            H.equal(w.x, 0); H.equal(w.y, 0); H.equal(w.z, 0)
        end
    end)

    H.test("cos surface glow ignores malformed peer components", function()
        local unit = { alive = true }
        local ctx = { [unit] = { skin = "s" } }
        local writes, write = recorder()
        local painted = Policy.repaint({ unit }, {
            active_per_item_glow_identity = "backend:b3|skin:s",
            active_per_item_glow = {
                rune = { r = "haxx", g = 0, b = 0, intensity = 1 },
            },
        }, deps_for(ctx, write))
        H.equal(#writes, 0, "malformed component values never reach the writer")
        -- The component still counts as active (intensity > 0): the per-item
        -- state claims the unit so the global override does not double-paint.
        H.equal(painted, 1)
    end)

    H.test("cos surface glow postcondition is painted-mesh identity, never call completion", function()
        H.equal(Policy.classify_postcondition({
            alive = true, mesh_name = "units/weapons/player/wpn_brw_sword/wpn_brw_sword_3p",
            glow_capable = true,
        }), "verified")
        H.equal(Policy.classify_postcondition({
            alive = true, mesh_name = "<no-unit_name>", glow_capable = true,
        }), "unnamed-mesh", "a mesh the surface cannot name is never success")
        H.equal(Policy.classify_postcondition({
            alive = true, mesh_name = "units/weapons/player/wpn_x/wpn_x", glow_capable = false,
        }), "no-glow-material")
        H.equal(Policy.classify_postcondition({ alive = false }), "dead-unit")
        H.equal(Policy.classify_postcondition(nil), "dead-unit")
    end)
end
