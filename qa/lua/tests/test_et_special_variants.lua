return function(H, repo_root)
    local core = dofile(repo_root
        .. "/enemy_tweaker/scripts/mods/enemy_tweaker/_et_special_variants_core.lua")

    local function complete_env(resident)
        local env = { breeds = {}, actions = {}, items = {}, cosmetics = {} }
        for _, c in ipairs(core.CANDIDATES) do
            env.breeds[c.base_breed] = { name = c.base_breed }
            env.actions[c.base_breed] = { idle = {} }
            env.items[c.skin] = { name = c.skin }
            env.cosmetics[c.skin] = {
                third_person_attachment = {
                    unit = "units/beings/player/dark_pact_skins/" .. c.id .. "/skin_1001/third_person/mesh",
                },
            }
        end
        env.can_get_unit = function() return resident end
        return env
    end

    H.test("ET #452 catalog maps five distinct ordinary specials to premium skins", function()
        H.equal(#core.CANDIDATES, 5)
        local breeds, skins = {}, {}
        for _, c in ipairs(core.CANDIDATES) do
            H.equal(breeds[c.base_breed], nil)
            H.equal(skins[c.skin], nil)
            breeds[c.base_breed], skins[c.skin] = true, true
            H.truthy(c.skin:find("skin_1001", 1, true))
        end
    end)

    H.test("ET #452 census recognizes complete structures without mutation", function()
        local env = complete_env(true)
        local before = env.cosmetics[core.CANDIDATES[1].skin].third_person_attachment.unit
        local rows, summary = core.audit(env)
        H.equal(#rows, 5)
        H.equal(summary.missing, 0)
        H.equal(summary.resident, 5)
        for _, row in ipairs(rows) do
            H.equal(row.structure_ready, true)
            H.equal(row.player_attachment, true)
            H.equal(row.unit_resident, true)
        end
        H.equal(env.cosmetics[core.CANDIDATES[1].skin].third_person_attachment.unit, before)
    end)

    H.test("ET #452 census exposes missing structure and nonresident assets", function()
        local env = complete_env(false)
        env.actions[core.CANDIDATES[2].base_breed] = nil
        env.cosmetics[core.CANDIDATES[4].skin] = nil
        local rows, summary = core.audit(env)
        H.equal(summary.missing, 2)
        H.equal(summary.resident, 0)
        H.equal(rows[2].structure_ready, false)
        H.equal(rows[4].attachment_unit, nil)
    end)

    H.test("ET #452 production module remains diagnostics-only", function()
        local path = repo_root
            .. "/enemy_tweaker/scripts/mods/enemy_tweaker/_et_special_variants.lua"
        local f = assert(io.open(path, "rb"))
        local source = f:read("*a")
        f:close()
        H.truthy(source:find("issue452_special_variant_assets_classified", 1, true))
        H.equal(source:find("mod:hook", 1, true), nil)
        H.equal(source:find("network_register", 1, true), nil)
        H.equal(source:find("World.spawn_unit", 1, true), nil)
    end)
end
