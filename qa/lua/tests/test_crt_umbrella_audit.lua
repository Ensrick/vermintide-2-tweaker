return function(H, repo_root)
    local base = repo_root .. "/career_tweaker/scripts/mods/career_tweaker/"
    local policy = assert(loadfile(base .. "_crt_umbrella_audit_policy.lua"))()
    local masters = assert(loadfile(base .. "_crt_rework_master_policy.lua"))()

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
        }, { "trn_one", "trn_two" }, function(id) return enabled[id] end, masters.FAMILIES)

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
        H.equal(s.cluster_gates, 1, "the armor cluster is the one registered gate")
        H.equal(s.cluster_total, 4)
        local line = policy.format(s)
        H.truthy(line:find("cluster_gates=1/4", 1, true), line)
        H.truthy(line:find("armor=1/2", 1, true), line)
        H.truthy(line:find("mutation=false", 1, true))
    end)

    H.test("CRT #221 cluster gate count derives from registered families, not a literal", function()
        H.equal(policy.CLUSTER_TOTAL, 4)
        H.equal(policy.gated_clusters(nil), 0)
        H.equal(policy.gated_clusters({}), 0)
        H.equal(policy.gated_clusters(masters.FAMILIES), 1)
        H.equal(policy.gated_clusters({
            ensrick = masters.FAMILIES.ensrick,
            tourney = masters.FAMILIES.tourney,
        }), 0, "authorship families are not cluster gates")
        H.equal(policy.gated_clusters({
            armor = masters.FAMILIES.armor,
            unchained = { master_id = "rework_master_unchained", ids = { "x" } },
        }), 2)
        H.deep_equal(policy.cluster_ids(masters.FAMILIES, "armor"), masters.ARMOR_IDS)
        H.deep_equal(policy.cluster_ids(masters.FAMILIES, "engineer"), {})
        H.deep_equal(policy.cluster_ids(nil, "armor"), {})

        -- Without family metadata the census still formats and reports zero gates.
        local bare = policy.snapshot({}, {}, function() return false end, nil)
        H.equal(bare.cluster_gates, 0)
        H.equal(bare.armor_total, 0)
        H.truthy(policy.format(bare):find("cluster_gates=0/4", 1, true))
    end)

    H.test("CRT #221 diagnostic catalogs match production menu and source", function()
        local function read(name)
            local file = assert(io.open(base .. name, "rb"))
            local source = file:read("*a")
            file:close()
            return source
        end
        local data_source = read("career_tweaker_data.lua")
        H.equal(policy.ARMOR_IDS, nil, "the census no longer owns a second armor literal")
        for _, id in ipairs(masters.ARMOR_IDS) do
            H.truthy(data_source:find('setting_id = "' .. id .. '"', 1, true), "missing " .. id)
        end
        H.truthy(data_source:find('setting_id = "rework_master_armor"', 1, true), "missing armor master widget")
        for _, id in ipairs(policy.UNCHAINED_RUNTIME_IDS) do
            H.truthy(data_source:find('setting_id = "' .. id .. '"', 1, true), "missing " .. id)
        end

        local source = read("career_tweaker.lua")
        H.truthy(source:find('mod._crt.ISSUE221_UMBRELLA_AUDIT_ARMED = true', 1, true))
        H.truthy(source:find('mod:command("crt_umbrella_audit"', 1, true))
        H.truthy(source:find("umbrella_audit.snapshot", 1, true))
        H.truthy(source:find("rework_master_module.FAMILIES)", 1, true),
            "census must receive the registered families")
        local audit_start = assert(source:find("-- #221's remaining Career Tweaker subgroup proposal", 1, true))
        local audit_finish = assert(source:find("local function _rework_master_snapshot", audit_start, true))
        local audit_block = source:sub(audit_start, audit_finish - 1)
        H.equal(audit_block:find("mod:set(", 1, true), nil,
            "#221 census must never write settings")
        H.equal(audit_block:find("mod:hook", 1, true), nil,
            "#221 census must not add a gameplay lifecycle owner")

        -- The armor master dispatch is wired through the shared bounded writer.
        H.truthy(source:find("mod._crt.ISSUE221_ARMOR_MASTER_ARMED = ok_rmp", 1, true))
        H.truthy(source:find("rework_master_policy:cluster_for_master(setting_id)", 1, true))
        H.truthy(source:find("rework_master_policy:cluster_for_leaf(setting_id)", 1, true))
        H.truthy(source:find("_apply_cluster_master(cluster_family", 1, true))
        H.truthy(source:find("_mark_cluster_custom(edited_cluster)", 1, true))

        local regression = read("_crt_regression.lua")
        H.truthy(regression:find('_rt_register("issue221_umbrella_audit_armed"', 1, true))
        H.truthy(regression:find('_rt_register("issue221_armor_master_transaction"', 1, true))
        H.truthy(regression:find('"cluster_gates=1/4"', 1, true))
    end)
end
