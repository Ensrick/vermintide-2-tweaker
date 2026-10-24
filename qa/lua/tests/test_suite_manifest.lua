return function(H, repo_root)
    local policy = dofile(repo_root .. "/qa/lua/suite_manifest.lua")

    H.test("suite manifest accepts LF and CRLF module inventories", function()
        H.deep_equal(assert(policy.parse("test_a\ntest_b\n")), { "test_a", "test_b" })
        H.deep_equal(assert(policy.parse("test_a\r\ntest_b\r\n")), { "test_a", "test_b" })
    end)

    H.test("suite manifest rejects ambiguous or malformed discovery", function()
        for _, source in ipairs({ "", "test_a", "test_a\ntest_a\n", "test_a\n\n",
            "test_a\r\ninvalid\n", "../test_a\n", "test_A\n", "test_a.lua\n",
            "\239\187\191test_a\n", string.rep("a", 1048577) }) do
            local names, reason = policy.parse(source)
            H.equal(names, nil, "invalid inventory accepted")
            H.equal(type(reason), "string")
        end
        H.equal(policy.parse(false), nil)
    end)

    H.test("suite manifest accepts actual direct and transitive imports", function()
        local register = function() end
        H.equal(policy.audit({ "test_direct", "test_child" }, {
            test_direct = register, test_child = register,
        }), nil)
    end)

    H.test("suite manifest fails on an unlisted file or fake cache sentinel", function()
        local register = function() end
        local reason = policy.audit({ "test_direct", "test_unlisted" }, { test_direct = register })
        H.equal(reason, "unreached test suites: test_unlisted")
        for _, value in ipairs({ true, false, "test_unlisted", {} }) do
            H.equal(policy.audit({ "test_unlisted" }, { test_unlisted = value }), reason)
        end
        H.equal(policy.audit({}, {}), "suite inventory required")
        H.equal(policy.audit({ "test_direct" }, false), "module-load inventory required")
    end)

    H.test("suite manifest rejects duplicate explicit registrations after merges", function()
        H.equal(policy.validate_explicit({ "test_a", "test_b" }), nil)
        H.equal(policy.validate_explicit({ "test_a", "test_a" }), "duplicate explicit suite: test_a")
        H.equal(policy.validate_explicit({ "test_a", false }), "invalid explicit suite name")
        H.equal(policy.validate_explicit({}), "explicit suite list required")
    end)
end
