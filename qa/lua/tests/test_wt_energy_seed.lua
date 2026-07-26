-- Issues #374/#388: EnergyData seeding for careers granted an energy weapon.
-- Vanilla defines rows only for the four Kerillian careers, each
-- { depletion_cooldown = 5, max_value = 25, recharge_delay = 0.2,
--   recharge_rate = 1.5 } (energy_data.lua:4-27); every spawn path reads
-- `EnergyData[career] or {}` locally (owner bulldozer_player.lua:207, bot
-- player_bot.lua:140, husk game_object_initializers_extractors.lua:2128/2296).
-- This suite pins the engine-free policy module (_wt_energy_seed.lua): the
-- exact vanilla seed values, energy-template recognition (bow_energy /
-- aim_energy, we_deus_01.lua), career derivation from final can_wield state,
-- add-only semantics with private per-career rows, marker-exact revert, and
-- the weapon_tweaker.lua / weapon_tweaker_backend.lua wiring seams.
local function register(Harness, repo_root)
    local wt_dir = repo_root .. "/weapon_tweaker/scripts/mods/weapon_tweaker"
    local seed = dofile(wt_dir .. "/_wt_energy_seed.lua")

    local function read(path)
        local file = assert(io.open(path, "rb"))
        local source = file:read("*a")
        file:close()
        return source
    end

    local function energy_template(kind)
        return {
            actions = {
                action_one = {
                    default = { kind = kind or "bow_energy" },
                },
            },
        }
    end

    Harness.test("WT #374 seed equals the vanilla Kerillian EnergyData row", function()
        -- energy_data.lua:4-27 - every we_ row is 5 / 25 / 0.2 / 1.5.
        Harness.equal(5, seed.SEED.depletion_cooldown)
        Harness.equal(25, seed.SEED.max_value)
        Harness.equal(0.2, seed.SEED.recharge_delay)
        Harness.equal(1.5, seed.SEED.recharge_rate)
    end)

    Harness.test("WT #374 energy weapon template recognition (bow_energy / aim_energy)", function()
        Harness.truthy(seed.is_energy_weapon_template(energy_template("bow_energy")))
        Harness.truthy(seed.is_energy_weapon_template(energy_template("aim_energy")))
        Harness.truthy(not seed.is_energy_weapon_template(energy_template("sweep")))
        Harness.truthy(not seed.is_energy_weapon_template({ actions = {} }))
        Harness.truthy(not seed.is_energy_weapon_template(nil))
    end)

    Harness.test("WT #374 careers derive from the FINAL can_wield of energy items only", function()
        local weapons = {
            moonfire_template = energy_template("bow_energy"),
            sword_template = energy_template("sweep"),
        }
        local iml = {
            we_deus_01 = {
                template = "moonfire_template",
                can_wield = { "we_waywatcher", "es_mercenary", "wh_zealot" },
            },
            es_1h_sword = {
                template = "sword_template",
                can_wield = { "es_knight" },
            },
            hat_item = { no_template_here = true },
        }
        local careers = seed.energy_careers(iml, weapons)
        Harness.truthy(careers.we_waywatcher)
        Harness.truthy(careers.es_mercenary)
        Harness.truthy(careers.wh_zealot)
        Harness.equal(nil, careers.es_knight, "non-energy items must not contribute careers")
        local count = 0
        for _ in pairs(careers) do count = count + 1 end
        Harness.equal(3, count)
    end)

    Harness.test("WT #374 apply adds only missing rows as private marker-tagged clones", function()
        local native_row = {
            depletion_cooldown = 5, max_value = 25,
            recharge_delay = 0.2, recharge_rate = 1.5,
        }
        local energy_data = { we_waywatcher = native_row }
        local added_names = {}
        local added = seed.apply(energy_data,
            { we_waywatcher = true, es_mercenary = true, wh_zealot = true }, added_names)
        Harness.equal(2, added)
        Harness.truthy(rawequal(energy_data.we_waywatcher, native_row),
            "an existing (native) row must never be replaced or mutated")
        Harness.equal(nil, native_row[seed.ROW_MARKER], "native row must stay unmarked")
        for _, career in ipairs({ "es_mercenary", "wh_zealot" }) do
            local row = energy_data[career]
            Harness.truthy(row, career .. " row must be seeded")
            Harness.equal(1.5, row.recharge_rate)
            Harness.equal(0.2, row.recharge_delay)
            Harness.equal(25, row.max_value)
            Harness.equal(5, row.depletion_cooldown)
            Harness.truthy(row[seed.ROW_MARKER], "seeded rows must carry the revert marker")
        end
        Harness.truthy(not rawequal(energy_data.es_mercenary, energy_data.wh_zealot),
            "each career must get a PRIVATE row (shared-template mutation trap)")
        -- Idempotent: a second apply adds nothing.
        Harness.equal(0, seed.apply(energy_data, { es_mercenary = true, wh_zealot = true }))
        table.sort(added_names)
        Harness.equal("es_mercenary", added_names[1])
        Harness.equal("wh_zealot", added_names[2])
    end)

    Harness.test("WT #374 revert removes exactly the marker-tagged rows", function()
        local native_row = { recharge_rate = 1.5 }
        local foreign_row = { recharge_rate = 9 }
        local energy_data = { we_shade = native_row, bw_scholar = foreign_row }
        seed.apply(energy_data, { es_huntsman = true, dr_ranger = true })
        Harness.equal(2, seed.revert(energy_data))
        Harness.equal(nil, energy_data.es_huntsman)
        Harness.equal(nil, energy_data.dr_ranger)
        Harness.truthy(rawequal(energy_data.we_shade, native_row), "native row must survive revert")
        Harness.truthy(rawequal(energy_data.bw_scholar, foreign_row),
            "unmarked foreign rows must survive revert")
        Harness.equal(0, seed.revert(energy_data), "second revert must be a no-op")
    end)

    Harness.test("WT #374 install defines the mod entry points and seeds through live globals", function()
        local prev_energy, prev_iml, prev_weapons =
            rawget(_G, "EnergyData"), rawget(_G, "ItemMasterList"), rawget(_G, "Weapons")
        local ok, err = xpcall(function()
            EnergyData = { we_waywatcher = { recharge_rate = 1.5 } }
            Weapons = { moonfire_template = energy_template("bow_energy") }
            ItemMasterList = {
                we_deus_01 = {
                    template = "moonfire_template",
                    can_wield = { "we_waywatcher", "es_mercenary" },
                },
            }
            local fake_mod = {}
            local returned = seed.install(fake_mod)
            Harness.truthy(rawequal(returned, seed), "install must return the module")
            Harness.truthy(EnergyData.es_mercenary, "install must run the initial seed")
            Harness.equal(1.5, EnergyData.es_mercenary.recharge_rate)
            Harness.equal(0, fake_mod._wt374_seed_energy_data(), "re-seed must be idempotent")
            Harness.equal(1, fake_mod._wt374_revert_energy_data(),
                "revert must remove exactly the seeded row")
            Harness.equal(nil, EnergyData.es_mercenary)
            Harness.truthy(EnergyData.we_waywatcher, "native row must survive revert")
        end, debug.traceback)
        EnergyData, ItemMasterList, Weapons = prev_energy, prev_iml, prev_weapons
        if not ok then error(err, 0) end
    end)

    Harness.test("WT #374/#388 wiring: seed runs at every availability seam and reverts on disable", function()
        local backend = read(wt_dir .. "/weapon_tweaker_backend.lua")
        Harness.truthy(backend:find('mod:dofile("scripts/mods/weapon_tweaker/_wt_energy_seed").install(mod)', 1, true),
            "backend M.install must install the seeding entry points (and the initial seed)")
        local _, backend_calls = backend:gsub(
            "if mod%._wt374_seed_energy_data then mod%._wt374_seed_energy_data%(%) end", "")
        Harness.equal(3, backend_calls,
            "backend must re-seed at the deferred-availability, CWV-transition, and first-unlock seams")
        local source = read(wt_dir .. "/weapon_tweaker.lua")
        local _, seed_calls = source:gsub(
            "if mod%._wt374_seed_energy_data then mod%._wt374_seed_energy_data%(%) end", "")
        local settings_runtime = read(wt_dir .. "/_wt_settings_runtime.lua")
        local _, runtime_seed_calls = settings_runtime:gsub(
            "if mod%._wt374_seed_energy_data then mod%._wt374_seed_energy_data%(%) end", "")
        Harness.equal(4, seed_calls + runtime_seed_calls,
            "WT must re-seed at state change, both setting arms, and the #1002 batch seam")
        Harness.truthy(source:find(
            "if mod._wt374_revert_energy_data then mod._wt374_revert_energy_data() end", 1, true),
            "on_disabled must revert the seeded rows")
    end)
end

return register
