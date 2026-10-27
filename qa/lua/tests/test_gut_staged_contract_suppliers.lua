return function(H, root)
    local fixture = assert(loadfile(root .. "/qa/lua/tests/fixtures/dialogue_transaction_fixture.lua"))()
    local prefix = "scripts/mods/gui_tweaker_dev/"
    local function contract(f, all)
        local chunk = assert(loadfile(root .. "/gui_tweaker_dev/" .. prefix
            .. (all and "_gut_mod_tweaker_contracts.lua" or "_gut_dialogue_contract.lua")))
        setfenv(chunk, f.env)
        local checks = {}
        local function register(name, fn) checks[name] = fn end
        if all then chunk().install({ register = register, src_read = function() return nil end })
        else chunk().install(register) end
        return assert(checks[all and "mod_tweaker_exclusive_group_api" or "issue998_dialogue_staged_isolation"])
    end
    H.test("actual registered446 binds moved enforcement on fresh uncached view", function()
        local f = fixture(root)
        local gut = f.env.get_mod("gut_dev")
        gut.mod_tweaker = gut:dofile(prefix .. "_mod_tweaker")
        f.defs.create_radio = function() end -- Existing check only requires factory presence.
        H.equal(nil, contract(f, true)())
        H.equal(0, f.writes); H.equal(0, f.gut_writes)
    end)
    for _, mode in ipairs({ "owner_absent", "empty_view", "binder_absent" }) do
        H.test("actual998 returns named diagnostic for " .. mode, function()
            local f = fixture(root)
            f:load_live_cd()
            local gut = f.env.get_mod("gut_dev")
            local original = gut.dofile
            gut.dofile = function(self, p)
                if mode == "owner_absent" and p == prefix .. "_mod_tweaker_view_pending" then return end
                if p == prefix .. "_mod_tweaker_view" then
                    if mode == "empty_view" then return nil, "tail", nil end
                    if mode == "binder_absent" then return {} end
                end
                return original(self, p)
            end
            local result = contract(f, false)()
            H.truthy(type(result) == "string")
            H.truthy(result:find(mode == "owner_absent" and "staged supplier unavailable"
                or "staged owner unavailable", 1, true))
            if mode == "binder_absent" then H.truthy(result:find("private staged-view binder unavailable", 1, true)) end
            H.equal(0, f.writes); H.equal(0, f.gut_writes)
        end)
    end
end
