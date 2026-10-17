-- Offline proof for #998: `issue998_dialogue_staged_isolation` judges only a
-- Character Dialogue that should own the staged isolation setting. Through
-- 0.2.360-dev the check returned a FAIL string ("owner unavailable; install the
-- coordinated build") for any CD whose API predates v6, and a bare PASS with no
-- CD at all, although the Dialogue tab omits the isolation row by design in both
-- setups (_mod_tweaker_dialogue.lua isolation_lead). The real contract module and
-- the real CD entry run through the dialogue fixture's test-local environment;
-- verdict() mirrors the /gut_regression_test runner (gui_tweaker_dev.lua: nil is
-- PASS, a "skip:" prefix is SKIP, any other string is FAIL).
return function(H, root)
    local fixture = assert(loadfile(root .. "/qa/lua/tests/fixtures/dialogue_transaction_fixture.lua"))()

    local function contract(f)
        local chunk = assert(loadfile(root
            .. "/gui_tweaker_dev/scripts/mods/gui_tweaker_dev/_gut_dialogue_contract.lua"))
        setfenv(chunk, f.env)
        local check
        chunk().install(function(name, fn)
            H.equal("issue998_dialogue_staged_isolation", name)
            check = fn
        end)
        H.equal(type(check), "function", "contract did not register its check")
        return check
    end

    local function verdict(result)
        if result == nil then return "PASS" end
        if type(result) == "string" and result:sub(1, 5) == "skip:" then return "SKIP" end
        return "FAIL"
    end

    local function expect(f, want, needle)
        local result = contract(f)()
        H.equal(verdict(result), want, "verdict for: " .. tostring(result))
        if needle then
            H.truthy(type(result) == "string" and result:find(needle, 1, true),
                "reason must name the setup (" .. needle .. "): " .. tostring(result))
        end
        H.equal(f.writes, 0, "the check must never write the real CD owner")
        H.equal(f.gut_writes, 0, "the check must never write a GUT shadow setting")
        return result
    end

    H.test("998 contract SKIPs by name when Character Dialogue is not installed", function()
        local f = fixture(root)
        f.absent = true
        expect(f, "SKIP", "not installed")
    end)

    H.test("998 contract SKIPs a v5 Character Dialogue (0.1.11-dev API shape)", function()
        local f = fixture(root)
        f:load_live_cd()
        -- CD 0.1.10/0.1.11-dev: API v5 had get/set_auto_isolation only, no
        -- staged descriptor and no batch completion owner.
        f.api.version, f.api.isolation_setting = 5, nil
        f.cd.on_settings_batch_changed = nil
        expect(f, "SKIP", "API v5 predates the v6 staged-isolation owner")
    end)

    H.test("998 contract SKIPs a Character Dialogue with no versioned API", function()
        local f = fixture(root)
        f.cd.character_dialogue_api = nil
        expect(f, "SKIP", "no versioned character_dialogue_api")
        local g = fixture(root)
        g.cd.character_dialogue_api.version = nil
        expect(g, "SKIP", "no versioned character_dialogue_api")
    end)

    for _, case in ipairs({
        { "descriptor missing", function(f) f.api.isolation_setting = nil end, "isolation_setting" },
        { "descriptor v2", function(f) f.api.isolation_setting.version = 2 end, "isolation_setting" },
        { "wrong setting id", function(f) f.api.isolation_setting.setting_id = "x" end, "isolation_setting" },
        { "batch owner missing", function(f) f.cd.on_settings_batch_changed = nil end, "on_settings_batch_changed" },
        { "v7 without descriptor", function(f) f.api.version, f.api.isolation_setting = 7, nil end, "API v7" },
    }) do
        H.test("998 contract FAILs a v6+ Character Dialogue with " .. case[1], function()
            local f = fixture(root)
            f:load_live_cd()
            case[2](f)
            expect(f, "FAIL", case[3])
        end)
    end

    H.test("998 contract PASSes against the real Character Dialogue entry", function()
        local f = fixture(root)
        f:load_live_cd()
        H.truthy(type(f.api.version) == "number" and f.api.version >= 6, "real CD entry is API v6+")
        expect(f, "PASS")
    end)
end
