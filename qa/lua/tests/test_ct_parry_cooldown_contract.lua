-- #342 parry-cooldown strip contract (2026-08-03 audit repair).
--
-- The pre-repair strip was a provable triple no-op: it guarded on a
-- `DeusPowerUpTemplates.power_ups` sub-table that never existed (the table is
-- FLAT name-keyed, deus_power_up_settings.lua:1182/:7040/:7128), it mutated
-- SOURCE data that registration table.clone's per rarity
-- (deus_power_up_settings.lua:7146-7161), and boon_skulls_03 has no strippable
-- field (proc hard-codes "boon_skulls_03_cooldown",
-- morris_buff_settings.lua:4632/:4655). The repair targets the REGISTERED
-- runtime cooldown-buff templates via _ct_parry_cooldown_policy.lua by
-- zeroing their DURATION - nil'ing `cooldown_buff` itself would crash the
-- static_blade proc's unconditional trailing add_buff(cooldown_buff)
-- (morris_buff_settings.lua:4323-4325 -> buff_extension.lua:173-174).
return function(H, repo_root)
    local base = repo_root
        .. "/chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/"

    local function read(path)
        local file = assert(io.open(path, "rb"))
        local source = file:read("*a")
        file:close()
        return source
    end

    local Policy = assert(loadfile(base .. "_ct_parry_cooldown_policy.lua"))()

    -- Fixture mirrors the shapes the game registers: DeusPowerUps[rarity][name]
    -- rows carrying buff_name (deus_power_up_settings.lua:7146), and the
    -- registered runtime templates in BuffTemplates. The "customrarity" row
    -- with its own cooldown name proves both the rarity list and the cooldown
    -- name are DERIVED from registration, never hard-coded.
    local function fixture()
        local runtime = {
            power_up_static_blade_rare = { buffs = {
                { name = "power_up_static_blade_rare", cooldown_buff = "static_blade_cooldown_buff" } } },
            power_up_static_blade_customrarity = { buffs = {
                { name = "power_up_static_blade_customrarity", cooldown_buff = "static_blade_cooldown_custom" } } },
            static_blade_cooldown_buff = { buffs = {
                { name = "static_blade_cooldown_buff", is_cooldown = true, duration = 6 } } },
            static_blade_cooldown_custom = { buffs = {
                { name = "static_blade_cooldown_custom", is_cooldown = true, duration = 4 } } },
            boon_skulls_03_cooldown = { buffs = {
                { name = "boon_skulls_03_cooldown", is_cooldown = true, duration = 8 } } },
        }
        local deus = {
            rare = { static_blade = { buff_name = "power_up_static_blade_rare" },
                other_boon = { buff_name = "power_up_other_boon_rare" } },
            customrarity = { static_blade = { buff_name = "power_up_static_blade_customrarity" } },
            exotic = {},
        }
        return runtime, deus
    end

    H.test("CT #342 strip zeroes registered cooldown durations for derived rarities", function()
        local runtime, deus = fixture()
        local ok, summary = Policy.strip(runtime, deus)
        H.truthy(ok, table.concat(summary.problems, "; "))
        H.equal(runtime.static_blade_cooldown_buff.buffs[1].duration, 0)
        H.equal(runtime.static_blade_cooldown_custom.buffs[1].duration, 0)
        H.equal(runtime.boon_skulls_03_cooldown.buffs[1].duration, 0)
    end)

    H.test("CT #342 strip never nils cooldown_buff (unconditional add_buff crash guard)", function()
        local runtime, deus = fixture()
        Policy.strip(runtime, deus)
        H.equal(runtime.power_up_static_blade_rare.buffs[1].cooldown_buff,
            "static_blade_cooldown_buff",
            "cooldown_buff must survive: the proc calls add_buff(cooldown_buff) unconditionally")
        H.equal(runtime.power_up_static_blade_customrarity.buffs[1].cooldown_buff,
            "static_blade_cooldown_custom")
    end)

    H.test("CT #342 strip is idempotent", function()
        local runtime, deus = fixture()
        H.truthy(Policy.strip(runtime, deus))
        local ok, summary = Policy.strip(runtime, deus)
        H.truthy(ok)
        H.equal(summary.skulls, "already")
        for _, row in ipairs(summary.static_blade) do
            H.equal(row.result, "already")
        end
    end)

    H.test("CT #342 residual_report fails before the strip and passes after", function()
        local runtime, deus = fixture()
        local before = Policy.residual_report(runtime, deus)
        H.truthy(before and before:find("duration", 1, true),
            "pre-strip vanilla durations must FAIL the check, not silently pass")
        Policy.strip(runtime, deus)
        H.equal(Policy.residual_report(runtime, deus), nil)
    end)

    H.test("CT #342 residual_report fails on unreadable runtime tables", function()
        local runtime, deus = fixture()
        H.truthy(Policy.residual_report(nil, deus))
        H.truthy(Policy.residual_report(runtime, nil))
        H.truthy(Policy.residual_report({}, deus),
            "registered entries missing from BuffTemplates must be a failure")
        H.truthy(Policy.residual_report(runtime, { rare = {} }),
            "no registered static_blade entries must be a failure")
    end)

    H.test("CT #342 exports and invokes the deferred parry strip explicitly", function()
        local combat = read(base .. "_ct_combat_hooks.lua")
        local main = read(base .. "chaos_wastes_tweaker_dev.lua")

        H.truthy(combat:find("mod._ct128_strip_parry_cooldowns = function()", 1, true))
        H.truthy(combat:find("_ct_parry_cooldown_policy", 1, true),
            "combat hooks must route the strip through the pure policy module")
        H.truthy(combat:find("mod._ct342_parry_cooldown_policy = ", 1, true),
            "policy must be published for the regression check")
        H.equal(combat:find("templates.power_ups", 1, true), nil,
            "#342: DeusPowerUpTemplates has no power_ups sub-table (flat name-keyed map)")
        H.equal(combat:find("b.cooldown_buff = nil", 1, true), nil,
            "#342: nil'ing cooldown_buff crashes the proc's trailing add_buff")
        -- #1159 wave 14: the lazy invocation piggybacks on the boon roll, which
        -- moved into _ct_run_creation_owner. Needles are byte-identical; only the
        -- file moved. The strip DEFINITION and its policy stay in _ct_combat_hooks.
        local run_creation = read(base .. "_ct_run_creation_owner.lua")
        H.truthy(run_creation:find("local strip = mod._ct128_strip_parry_cooldowns", 1, true))
        H.equal(main:find("local strip = mod._ct128_strip_parry_cooldowns", 1, true), nil,
            "a second invocation site would run the strip off a roll it does not gate")
        H.equal(main:find("pcall(_ct128_strip_parry_cooldowns)", 1, true), nil)
        H.equal(run_creation:find("pcall(_ct128_strip_parry_cooldowns)", 1, true), nil,
            "#130: the boot-time bare call ran before DeusPowerUpTemplates existed")
        H.truthy(run_creation:find("[ct:342] parry-cooldown strip failed", 1, true))
    end)

    H.test("CT #342 regression check consumes residual_report and cannot silently pass", function()
        local regression = read(base .. "_ct_regression.lua")
        local pos = assert(regression:find('_rt_register("parry_cooldowns_stripped_post_load"', 1, true))
        local block = regression:sub(pos, pos + 1400)
        H.truthy(block:find("residual_report", 1, true),
            "regression check must verify through the shared policy core")
        H.equal(block:find("return nil  -- pre-load", 1, true), nil,
            "#342: unreadable templates must FAIL the check, not silently pass")
        H.equal(block:find(".power_ups", 1, true), nil,
            "#342: check must not resurrect the phantom .power_ups sub-table access")
    end)
end
