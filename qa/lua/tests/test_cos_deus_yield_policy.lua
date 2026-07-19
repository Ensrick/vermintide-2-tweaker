-- Pin for the issue #518 Chaos Wastes deus-yield boundary (cosmetics_tweaker).
-- Deus weapons are GENERATED instances that clone the base item's template and
-- re-roll item.skin per rarity (deus_weapon_generation.lua:185-202, :246-249,
-- :318-321), so a keep-committed per-TEMPLATE LA pick leaked onto every CW
-- weapon and stomped the rolled upgrade skin. The shipped fix yields LA weapon
-- visuals ONLY inside an active expedition mission - the deus mechanism ALSO
-- owns the Pilgrimage Chamber ("inn_deus") and the route/shrine map
-- ("map_deus"), where LA must stay live (the 0.9.89-dev staging regression,
-- deus_mechanism.lua:28-35,49-59). This suite executes the extracted boundary
-- helper against the full context truth table and pins every weapon-side
-- consumer gate plus the in-game rt check so the boundary cannot silently
-- regress in either direction. See LA_SYNC_MODEL.md section 6.10.
return function(H, repo_root)
    local root = repo_root .. "/cosmetics_tweaker/scripts/mods/cosmetics_tweaker/"

    local function read(name)
        local f = assert(io.open(root .. name, "rb"))
        local value = f:read("*a")
        f:close()
        return value
    end

    local main = read("cosmetics_tweaker.lua")
    local checks = read("_cos_runtime_checks.lua")

    H.test("Cos #518 yield boundary is mechanism AND game mode (staging never yields)", function()
        local body = main:match(
            "mod%._la_weapon_yield_for_context%s*=%s*(function%s*%b().-\nend)")
        H.truthy(body, "_la_weapon_yield_for_context extraction failed (renamed/moved?)")
        local fn = assert(loadstring("return " .. body))()
        H.equal(fn("deus", "deus"), true, "active expedition mission must yield")
        H.equal(fn("deus", "inn_deus"), false, "Pilgrimage Chamber must keep LA live")
        H.equal(fn("deus", "map_deus"), false, "route/shrine map must keep LA live")
        H.equal(fn("adventure", "deus"), false, "non-deus mechanism must never yield")
        H.equal(fn("deus", nil), false, "unresolvable game mode fails safe (no yield)")
        H.equal(fn(nil, nil), false)
    end)

    H.test("Cos #518 early-load level fallback classifies the deus node types", function()
        -- Vanilla reserves exactly morris_hub (inn_deus) and dlc_morris_map
        -- (map_deus); every other deus level is an ingame node
        -- (deus_mechanism.lua:49-59). The fallback must keep that split so a
        -- mission cannot briefly repaint LA while GameModeManager is starting.
        H.truthy(main:find('if ok and level_key == "morris_hub" then', 1, true))
        H.truthy(main:find('game_mode_key = "inn_deus"', 1, true))
        H.truthy(main:find('elseif ok and level_key == "dlc_morris_map" then', 1, true))
        H.truthy(main:find('game_mode_key = "map_deus"', 1, true))
        H.truthy(main:find('game_mode_key = "deus"', 1, true))
    end)

    H.test("Cos #518 every weapon-side apply/paint path routes through the yield gate", function()
        -- Terminal funnel: every apply trigger (RPC recv, reconcile, transition
        -- walk, pending drain, husk/local wield re-paint) runs _apply_la_on_unit;
        -- weapon-side kinds gate there, hats/armor pass untouched.
        H.truthy(main:find(
            'if (kind == "offhand" or kind == "illusion") and mod._la_deus_weapon_yield() then',
            1, true), "terminal weapon-side yield gate missing from _apply_la_on_unit")
        -- get_item_units resolves the gate ONCE per call and gates the husk LA
        -- swap, the husk vanilla-offhand swap, and the live-body selection.
        H.truthy(main:find('local _deus_yield = mod._la_deus_weapon_yield()', 1, true),
            "get_item_units single-resolution gate missing")
        H.truthy(main:find('and not _deus_yield', 1, true),
            "husk mesh-override deus gate missing")
        H.truthy(main:find('not (_deus_yield and _in_create_equipment)', 1, true),
            "live-body gate must suppress only create_equipment, not previews")
        -- In-game LA paint skips inside a run; preview contexts stay live.
        H.truthy(main:find('if context == "ingame" and mod._la_deus_weapon_yield() then', 1, true),
            "ingame paint gate missing")
        -- Pending-apply retries treat deus-yield as terminal (no spin-to-deadline).
        H.truthy(main:find('reason ~= "deus-yield"', 1, true),
            "pending drain must treat deus-yield as a terminal reason")
        -- Local wield re-apply (the observed stomper) is gated too.
        H.truthy(main:find('and not mod._la_deus_weapon_yield()', 1, true),
            "local wield re-apply deus gate missing")
    end)

    H.test("Cos #518 in-game boundary check pins all three deus contexts", function()
        H.truthy(checks:find("cos_la_deus_yield_active_mission_only", 1, true),
            "in-game boundary rt check missing")
        H.truthy(checks:find('{ "deus", "inn_deus", false', 1, true),
            "Pilgrimage Chamber row missing from the in-game truth table")
        H.truthy(checks:find('{ "deus", "map_deus", false', 1, true),
            "route/shrine map row missing from the in-game truth table")
        H.truthy(checks:find('{ "deus", "deus", true', 1, true),
            "active-mission row missing from the in-game truth table")
    end)
end
