return function(H, repo_root)
    local Policy = assert(loadfile(repo_root
        .. "/chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/_ct_weave_metal_policy.lua"))()

    H.test("CT #253 Metal policy is default-off, hidden, and bounded", function()
        H.equal(Policy.DEFAULT_ENABLED, false)
        H.equal(Policy.EXPOSED_IN_MENU, false)
        H.equal(Policy.WIND, "metal")
        H.equal(Policy.MUTATOR, "metal")
        H.equal(Policy.MECHANISM, "deus")
        H.equal(Policy.COMMAND, "ct_weave_metal")
        H.equal(Policy.MIN_STRENGTH, 1)
        H.equal(Policy.MAX_STRENGTH, 5)
        H.equal(Policy.DEFAULT_STRENGTH, 1)
        H.deep_equal(Policy.CONTEXT_KEYS, { "wind", "wind_strength" })
    end)

    H.test("CT #253 strength normalizes whole numbers inside 1..5 only", function()
        H.equal(Policy.normalize_strength(1), 1)
        H.equal(Policy.normalize_strength("5"), 5)
        H.equal(Policy.normalize_strength(3.0), 3)
        H.equal(Policy.normalize_strength(0), nil)
        H.equal(Policy.normalize_strength(6), nil)
        H.equal(Policy.normalize_strength(2.5), nil)
        H.equal(Policy.normalize_strength("abc"), nil)
        H.equal(Policy.normalize_strength(nil), nil)
        H.equal(Policy.normalize_strength(0 / 0), nil)
        H.equal(Policy.effective_strength(nil), 1)
        H.equal(Policy.effective_strength("4"), 4)
        H.equal(Policy.effective_strength(99), 1)
    end)

    H.test("CT #253 context exposes only wind and wind_strength", function()
        local context = Policy.build_context(3)
        H.deep_equal(context, { wind = "metal", wind_strength = 3 })
        H.deep_equal(Policy.context_keys(context), { "wind", "wind_strength" })
        H.equal(Policy.context_matches(context), true)
        H.deep_equal(Policy.build_context(nil), { wind = "metal", wind_strength = 1 })
        H.deep_equal(Policy.build_context("bad"), { wind = "metal", wind_strength = 1 })

        local ok, why = Policy.context_matches({ wind = "metal", wind_strength = 2, weave_manager = {} })
        H.equal(ok, false)
        H.truthy(why:find("keys drifted", 1, true), why)
        ok, why = Policy.context_matches({ wind = "fire", wind_strength = 2 })
        H.equal(ok, false)
        H.truthy(why:find("wind drifted", 1, true), why)
        ok, why = Policy.context_matches({ wind = "metal", wind_strength = 9 })
        H.equal(ok, false)
        H.truthy(why:find("wind_strength invalid", 1, true), why)
        ok = Policy.context_matches({ wind = "metal" })
        H.equal(ok, false)
        ok = Policy.context_matches(nil)
        H.equal(ok, false)
    end)

    H.test("CT #253 command grammar: on, off, status, strength N", function()
        H.deep_equal(Policy.parse_command(nil), { action = "status" })
        H.deep_equal(Policy.parse_command(""), { action = "status" })
        H.deep_equal(Policy.parse_command("ON"), { action = "on" })
        H.deep_equal(Policy.parse_command("off"), { action = "off" })
        H.deep_equal(Policy.parse_command("status"), { action = "status" })
        H.deep_equal(Policy.parse_command("strength", "4"), { action = "strength", strength = 4 })
        H.deep_equal(Policy.parse_command("Strength", 2), { action = "strength", strength = 2 })

        local parsed, why = Policy.parse_command("strength")
        H.equal(parsed, nil)
        H.equal(why, "strength must be a whole number from 1 to 5")
        parsed, why = Policy.parse_command("strength", "7")
        H.equal(parsed, nil)
        H.truthy(why:find("1 to 5", 1, true))
        parsed, why = Policy.parse_command("strength", "2.5")
        H.equal(parsed, nil)
        parsed, why = Policy.parse_command("on", "now")
        H.equal(parsed, nil)
        H.equal(why, "'on' takes no argument")
        parsed, why = Policy.parse_command("enable")
        H.equal(parsed, nil)
        H.equal(why, "unknown action 'enable'")
        parsed, why = Policy.parse_command(42)
        H.equal(parsed, nil)
        H.equal(why, "unknown action")
    end)

    H.test("CT #253 transition is pure and reports change", function()
        local enabled, strength, changed = Policy.transition({ action = "on" }, false, 1)
        H.deep_equal({ enabled, strength, changed }, { true, 1, true })
        enabled, strength, changed = Policy.transition({ action = "on" }, true, 1)
        H.deep_equal({ enabled, strength, changed }, { true, 1, false })
        enabled, strength, changed = Policy.transition({ action = "off" }, true, 3)
        H.deep_equal({ enabled, strength, changed }, { false, 3, true })
        enabled, strength, changed = Policy.transition({ action = "off" }, false, 3)
        H.deep_equal({ enabled, strength, changed }, { false, 3, false })
        enabled, strength, changed = Policy.transition({ action = "strength", strength = 4 }, false, 1)
        H.deep_equal({ enabled, strength, changed }, { false, 4, true })
        enabled, strength, changed = Policy.transition({ action = "strength", strength = 4 }, true, 4)
        H.deep_equal({ enabled, strength, changed }, { true, 4, false })
        enabled, strength, changed = Policy.transition({ action = "status" }, "yes", "bad")
        H.deep_equal({ enabled, strength, changed }, { false, 1, false })
    end)

    H.test("CT #253 composition appends metal once, host-only, deus-only, never mutating input", function()
        local input = { "deus_more_hordes", "curse_empathy" }
        local list, reason = Policy.compose_mutators(input, { enabled = true, is_server = true, mechanism = "deus" })
        H.deep_equal(list, { "deus_more_hordes", "curse_empathy", "metal" })
        H.equal(reason, "appended")
        H.deep_equal(input, { "deus_more_hordes", "curse_empathy" })
        H.truthy(list ~= input)

        list, reason = Policy.compose_mutators({}, { enabled = true, is_server = true, mechanism = "deus" })
        H.deep_equal(list, { "metal" })
        H.equal(reason, "appended")

        list, reason = Policy.compose_mutators(input, { enabled = false, is_server = true, mechanism = "deus" })
        H.equal(list, nil)
        H.equal(reason, "disabled")
        list, reason = Policy.compose_mutators(input, { enabled = "true", is_server = true, mechanism = "deus" })
        H.equal(list, nil)
        H.equal(reason, "disabled")
        list, reason = Policy.compose_mutators(input, { enabled = true, is_server = false, mechanism = "deus" })
        H.equal(list, nil)
        H.equal(reason, "client")
        list, reason = Policy.compose_mutators(input, { enabled = true, is_server = true, mechanism = "adventure" })
        H.equal(list, nil)
        H.equal(reason, "mechanism:adventure")
        list, reason = Policy.compose_mutators(input, { enabled = true, is_server = true })
        H.equal(list, nil)
        H.equal(reason, "mechanism:nil")
        list, reason = Policy.compose_mutators(nil, { enabled = true, is_server = true, mechanism = "deus" })
        H.equal(list, nil)
        H.equal(reason, "no_list")
        list, reason = Policy.compose_mutators({ "metal" }, { enabled = true, is_server = true, mechanism = "deus" })
        H.equal(list, nil)
        H.equal(reason, "already_listed")
        list, reason = Policy.compose_mutators(input)
        H.equal(list, nil)
        H.equal(reason, "disabled")
    end)

    H.test("CT #253 armor snapshot and mismatch count prove exact restoration", function()
        local template = {
            primary_armor_category = 6,
            modify_primary_armor_category_breeds = { "chaos_warrior", "skaven_storm_vermin", "beastmen_bestigor" },
        }
        local names = Policy.armor_breeds(template)
        H.deep_equal(names, { "chaos_warrior", "skaven_storm_vermin", "beastmen_bestigor" })
        H.truthy(names ~= template.modify_primary_armor_category_breeds)
        H.deep_equal(Policy.armor_breeds({}), {})
        H.deep_equal(Policy.armor_breeds(nil), {})

        local breeds = {
            chaos_warrior = { primary_armor_category = 3 },
            skaven_storm_vermin = { primary_armor_category = 3 },
            beastmen_bestigor = {},
        }
        local snapshot, count = Policy.snapshot_armor(breeds, names)
        H.equal(count, 3)
        H.deep_equal(snapshot, { chaos_warrior = 3, skaven_storm_vermin = 3, beastmen_bestigor = false })

        local bad, total = Policy.armor_mismatches(breeds, snapshot)
        H.deep_equal({ bad, total }, { 0, 3 })
        -- Simulate the wrapped start applying category 6 (mutator_templates.lua:36-61).
        for _, name in ipairs(names) do breeds[name].primary_armor_category = 6 end
        bad, total = Policy.armor_mismatches(breeds, snapshot)
        H.deep_equal({ bad, total }, { 3, 3 })
        -- Simulate the wrapped stop restoring (mutator_templates.lua:63-73).
        breeds.chaos_warrior.primary_armor_category = 3
        breeds.skaven_storm_vermin.primary_armor_category = 3
        breeds.beastmen_bestigor.primary_armor_category = nil
        bad, total = Policy.armor_mismatches(breeds, snapshot)
        H.deep_equal({ bad, total }, { 0, 3 })
        -- A missing breed table counts as a mismatch against a numeric snapshot.
        breeds.chaos_warrior = nil
        bad = Policy.armor_mismatches(breeds, snapshot)
        H.equal(bad, 1)
        bad, total = Policy.armor_mismatches(nil, nil)
        H.deep_equal({ bad, total }, { 0, 0 })
    end)

    H.test("CT #253 status text names the hidden-menu contract", function()
        local text = Policy.status_text({
            enabled = false, strength = 2, is_server = true, mechanism = "deus",
            bridged = true, level_active = false, activations = 1, teardowns = 1, restored_bad = 0,
        })
        H.equal(text, "Metal wind adapter: off (hidden from the curse menu); strength 2; host=yes; mechanism=deus; bridge=ready; level=idle; activations=1 teardowns=1 armor_faults=0")
        text = Policy.status_text({ enabled = true, level_active = true })
        H.equal(text, "Metal wind adapter: ON (hidden from the curse menu); strength 1; host=no; mechanism=none; bridge=missing; level=armed; activations=0 teardowns=0 armor_faults=0")
        H.equal(Policy.status_text(nil):find("Metal wind adapter: off", 1, true), 1)
    end)
end
