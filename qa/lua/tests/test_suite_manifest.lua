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

    H.test("suite manifest accepts completed direct and transitive registration evidence", function()
        H.equal(policy.audit({ "test_direct", "test_child" }, {
            test_direct = true, test_child = true,
        }), nil)
    end)

    H.test("suite manifest rejects importing a suite without executing its registration", function()
        H.truthy(policy.audit({ "test_import_only" }, {
            test_import_only = function() end,
        }), "a loaded registration function is not an executed suite")
    end)

    H.test("suite manifest fails on missing or non-completion evidence", function()
        local reason = policy.audit({ "test_direct", "test_unlisted" }, { test_direct = true })
        H.equal(reason, "unreached test suites: test_unlisted")
        for _, value in ipairs({ false, "test_unlisted", {}, function() end }) do
            H.equal(policy.audit({ "test_unlisted" }, { test_unlisted = value }), reason)
        end
        H.equal(policy.audit({}, {}), "suite inventory required")
        H.equal(policy.audit({ "test_direct" }, false), "completed-registration inventory required")
    end)

    H.test("suite tracker observes completed nested calls and preserves nil return holes", function()
        local tracked, completed
        local calls = 0
        local modules = {
            test_child = function() calls = calls + 1 end,
            test_parent = function(value)
                tracked("test_child")(value)
                return "head", nil, "tail"
            end,
            production_helper = function() end,
        }
        tracked, completed = policy.track(function(name) return modules[name] end)
        local parent = tracked("test_parent")
        H.equal(tracked("test_parent"), parent)
        H.equal(completed.test_parent, nil)
        H.truthy(policy.audit({ "test_parent", "test_child" }, completed))
        local a, b, c = parent("fixture")
        H.equal(a, "head"); H.equal(b, nil); H.equal(c, "tail")
        H.equal(calls, 1)
        H.equal(policy.audit({ "test_parent", "test_child" }, completed), nil)
        H.equal(tracked("production_helper"), modules.production_helper)
        H.equal(completed.production_helper, nil)
    end)

    H.test("suite tracker never accepts a thrown registration hidden by its parent", function()
        local tracked, completed
        local modules = {
            test_child = function() error("registration failed") end,
            test_parent = function() pcall(tracked("test_child")) end,
        }
        tracked, completed = policy.track(function(name) return modules[name] end)
        tracked("test_parent")()
        H.equal(completed.test_parent, true)
        H.equal(completed.test_child, nil)
        H.equal(policy.audit({ "test_parent", "test_child" }, completed),
            "unreached test suites: test_child")
    end)

    H.test("suite manifest rejects duplicate explicit registrations after merges", function()
        H.equal(policy.validate_explicit({ "test_a", "test_b" }), nil)
        H.equal(policy.validate_explicit({ "test_a", "test_a" }), "duplicate explicit suite: test_a")
        H.equal(policy.validate_explicit({ "test_a", false }), "invalid explicit suite name")
        H.equal(policy.validate_explicit({}), "explicit suite list required")
    end)
end
