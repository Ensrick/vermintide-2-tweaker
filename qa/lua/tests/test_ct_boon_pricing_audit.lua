return function(H, repo_root)
    local Audit = dofile(repo_root
        .. "/chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/_ct_boon_pricing_audit.lua")

    H.test("CT #467 catalog is deterministic and preserves tier prices", function()
        local pools = {
            unique = { { name = "u_boon" } },
            rare = { { name = "z_boon" }, { name = "a_boon" } },
            exotic = { { name = "e_boon" } },
        }
        local templates = {
            a_boon = { display_name = "a_name", advanced_description = "a_desc" },
            z_boon = {}, e_boon = {}, u_boon = {},
        }
        local out = Audit.audit(pools, { rare = 200, exotic = 250, unique = 300 }, templates)
        H.equal(out.total, 4)
        H.equal(out.records[1].name, "a_boon")
        H.equal(out.records[1].shop_price, 200)
        H.equal(out.records[2].name, "z_boon")
        H.equal(out.records[3].rarity, "exotic")
        H.equal(out.records[4].rarity, "unique")
        H.equal(#out.anomalies, 0)
    end)

    H.test("CT #467 catalog diagnoses malformed hierarchy without mutation", function()
        local shared = { name = "shared" }
        local pools = { rare = { shared }, exotic = { shared, { name = "missing" } } }
        local out = Audit.audit(pools, { rare = 200 }, { shared = {} }, 2)
        H.equal(out.total, 3)
        H.equal(#out.records, 2)
        H.equal(out.truncated, 1)
        H.truthy(table.concat(out.anomalies, "|"):find("missing_price:exotic", 1, true))
        H.truthy(table.concat(out.anomalies, "|"):find("missing_template:missing", 1, true))
        H.truthy(table.concat(out.anomalies, "|"):find("multi_rarity:shared", 1, true))
        H.equal(shared.name, "shared")
    end)

    H.test("CT #467 proposed plan accepts only known wire-safe tiers and integer prices", function()
        local known = { boon_a = true }
        local ok, errors = Audit.validate_plan({ boon_a = { rarity = "exotic", price = 225 } }, known)
        H.equal(ok, true)
        H.equal(#errors, 0)
        ok, errors = Audit.validate_plan({
            missing = { rarity = "rare" },
            boon_a = { rarity = "common", price = 12.5 },
        }, known)
        H.equal(ok, false)
        H.equal(#errors, 3)
    end)

    H.test("CT #467 production audit is automatic bounded and observation-only", function()
        local path = repo_root
            .. "/chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/chaos_wastes_tweaker_dev.lua"
        local f = assert(io.open(path, "rb"))
        local source = f:read("*a")
        f:close()
        H.truthy(source:find("CT_BOON_PRICE_AUDIT_MARKER", 1, true))
        H.truthy(source:find("mod._ct_boon_price_audit_once(false", 1, true))
        H.truthy(source:find("max_records = 192", 1, true))
        H.truthy(source:find("[ct:467] row", 1, true))
        H.equal(source:find("DeusCostSettings.shop.power_ups[record.name]", 1, true), nil)
    end)
end
