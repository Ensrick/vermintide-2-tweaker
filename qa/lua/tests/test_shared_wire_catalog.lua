local function register(H, repo_root)
    local Catalog = assert(loadfile(repo_root
        .. "/tools/shared_lib/_lib_wire_catalog.lua"))()

    local function lookup(rows)
        local out = {}
        for i = 1, #rows do
            out[i] = rows[i]
            out[rows[i]] = i
        end
        return out
    end

    H.test("shared wire catalog is deterministic and namespace-separated", function()
        local nl = lookup({ "vanilla", "crt_a", "crt_z" })
        local a, err_a, names_a = Catalog.build_identity(
            "crt.buff_templates", { crt_z = true, crt_a = true }, nl)
        local b, err_b, names_b = Catalog.build_identity(
            "crt.buff_templates", { crt_a = true, crt_z = true }, nl)
        H.equal(err_a, nil)
        H.equal(err_b, nil)
        H.equal(a, b)
        H.deep_equal(names_a, { "crt_a", "crt_z" })
        H.deep_equal(names_a, names_b)
        local other = assert(Catalog.build_identity(
            "other.buff_templates", { crt_a = true, crt_z = true }, nl))
        H.truthy(other ~= a, "semantic namespace must be part of the identity")
    end)

    H.test("shared wire catalog fingerprints exact owned and fallback ids", function()
        local entries = { custom_a = "vanilla_a", custom_b = "vanilla_b" }
        local base = lookup({ "vanilla_a", "vanilla_b", "custom_a", "custom_b" })
        local identity = assert(Catalog.build_identity("damage_profiles", entries, base))

        local shifted_owned = lookup({ "vanilla_a", "vanilla_b", "custom_b", "custom_a" })
        H.truthy(assert(Catalog.build_identity(
            "damage_profiles", entries, shifted_owned)) ~= identity)

        local shifted_fallback = lookup({ "vanilla_b", "vanilla_a", "custom_a", "custom_b" })
        H.truthy(assert(Catalog.build_identity(
            "damage_profiles", entries, shifted_fallback)) ~= identity)

        local changed = { custom_a = "vanilla_b", custom_b = "vanilla_a" }
        H.truthy(assert(Catalog.build_identity(
            "damage_profiles", changed, base)) ~= identity)
    end)

    H.test("shared wire catalog rejects partial or malformed proof", function()
        local nl = lookup({ "vanilla", "custom" })
        H.equal(Catalog.build_identity(nil, { custom = true }, nl), nil)
        H.equal(Catalog.build_identity("", { custom = true }, nl), nil)
        H.equal(Catalog.build_identity("axis", {}, nl), nil)
        H.equal(Catalog.build_identity("axis", { custom = false }, nl), nil)
        H.equal(Catalog.build_identity("axis", { custom = "missing" }, nl), nil)

        nl[2] = "wrong"
        local identity, err = Catalog.build_identity("axis", { custom = true }, nl)
        H.equal(identity, nil)
        H.truthy(err:find("lookup%-mismatch") ~= nil)
    end)

    H.test("shared wire catalog identity is exact-mode transport safe", function()
        local identity = assert(Catalog.build_identity("axis", { custom = true },
            lookup({ "vanilla", "custom" })))
        H.truthy(#identity <= 64)
        H.truthy(identity:match("^[%w_.:%-]+$") ~= nil)
    end)
end

return register
