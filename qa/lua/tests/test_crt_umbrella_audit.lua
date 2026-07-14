return function(H, repo_root)
    local base = repo_root .. "/career_tweaker/scripts/mods/career_tweaker/"
    local policy = assert(loadfile(base .. "_crt_umbrella_audit_policy.lua"))()

    H.test("CRT #221 umbrella audit is bounded and observation-only", function()
        local enabled = {
            rework_bw_unchained_one = true,
            rework_dr_engineer_one = true,
            armor_gromril_ignore_chip = true,
            unchained_no_overcharge_from_ff = true,
            trn_one = true,
        }
        local s = policy.snapshot({
            "rework_bw_unchained_one", "rework_bw_unchained_two",
            "rework_dr_engineer_one", "rework_es_mercenary_one",
        }, { "trn_one", "trn_two" }, function(id) return enabled[id] end)

        H.equal(s.ensrick_active, 2)
        H.equal(s.ensrick_total, 4)
        H.equal(s.tourney_active, 1)
        H.equal(s.tourney_total, 2)
        H.equal(s.unchained_active, 1)
        H.equal(s.unchained_total, 2)
        H.equal(s.engineer_active, 1)
        H.equal(s.engineer_total, 1)
        H.equal(s.armor_active, 1)
        H.equal(s.armor_total, 2)
        H.equal(s.runtime_active, 1)
        H.equal(s.runtime_total, 3)
        local line = policy.format(s)
        H.truthy(line:find("cluster_gates=0/4", 1, true))
        H.truthy(line:find("mutation=false", 1, true))
    end)

    H.test("CRT #221 diagnostic catalogs match production menu and source", function()
        local function read(name)
            local file = assert(io.open(base .. name, "rb"))
            local source = file:read("*a")
            file:close()
            return source
        end
        local data_source = read("career_tweaker_data.lua")
        for _, id in ipairs(policy.ARMOR_IDS) do
            H.truthy(data_source:find('setting_id = "' .. id .. '"', 1, true), "missing " .. id)
        end
        for _, id in ipairs(policy.UNCHAINED_RUNTIME_IDS) do
            H.truthy(data_source:find('setting_id = "' .. id .. '"', 1, true), "missing " .. id)
        end

        local source = read("career_tweaker.lua")
        H.truthy(source:find("crt_umbrella_audit", 1, true))
        H.truthy(source:find("umbrella_audit.snapshot", 1, true))
    end)
end
