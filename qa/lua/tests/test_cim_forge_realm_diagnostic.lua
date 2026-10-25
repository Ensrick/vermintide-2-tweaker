-- #1694: exercise the actual forge-open diagnostic with the production realm
-- adapter. Private chunk environments preserve the host's raw globals exactly.
return function(H, repo_root)
    local root = repo_root .. "/crafting_in_modded_dev/scripts/mods/crafting_in_modded_dev/"

    local function fixture(spec)
        local emitted, hooks = {}, {}
        local environment = setmetatable({
            script_data = spec.script_data or {},
            Development = spec.development,
            MODDED_REALM = spec.native,
            Managers = { player = { local_player = function() return nil end } },
        }, { __index = _G })
        environment._G = environment
        environment.printf = function(fmt, ...)
            emitted[#emitted + 1] = string.format(fmt, ...)
        end
        local mod = {
            get = function() return nil end,
            info = function() end,
            command = function() end,
            hook_safe = function(_, class, method, callback)
                hooks[#hooks + 1] = { class, method, callback }
            end,
        }
        environment.mod = mod
        environment.get_mod = function(name)
            if name == "cim_dev" then return mod end
            if name == "mp" then return spec.sibling end
        end
        local authority_chunk = assert(loadfile(root .. "_lib_modded_realm_authority.lua"))
        setfenv(authority_chunk, environment)
        environment.RealmAuthority = authority_chunk()

        -- Execute the exact entry-owned adapter instead of supplying a copied
        -- test predicate that could keep passing after production wiring drifts.
        local file = assert(io.open(root .. "crafting_in_modded_dev.lua", "rb"))
        local entry = file:read("*a")
        file:close()
        local binding = assert(entry:match("(mod%._cim_is_modded_realm = function%(%).-\nend)"),
            "missing CIM entry-owned realm adapter")
        local bind = assert(loadstring(binding, "@cim-entry-realm-adapter"))
        setfenv(bind, environment)
        bind()
        local debug_chunk = assert(loadfile(root .. "cim_debug.lua"))
        setfenv(debug_chunk, environment)
        debug_chunk()
        return mod, environment, emitted, hooks
    end

    local cases = {
        { name = "native modded without obsolete flag", native = true, expected = true },
        { name = "native modded overrides obsolete false", native = true,
            script_data = { ["eac-untrusted"] = false }, expected = true },
        { name = "native official rejects obsolete true", native = false,
            script_data = { ["eac-untrusted"] = true }, expected = false },
        { name = "malformed native number denies legacy permission", native = 1,
            script_data = { ["eac-untrusted"] = true }, expected = false },
        { name = "malformed native string denies sibling permission", native = "true",
            sibling = { is_modded_realm = function() return true end }, expected = false },
        { name = "absent native preserves legacy flag",
            script_data = { ["eac-untrusted"] = true }, expected = true },
        { name = "absent native preserves launch fallback",
            development = { application_parameter = { eac_untrusted = "" } }, expected = true },
        { name = "absent native preserves MP fallback",
            sibling = { is_modded_realm = function() return true end }, expected = true },
        { name = "absent authority denies by default", expected = false },
    }

    for _, spec in ipairs(cases) do
        H.test("CIM forge realm diagnostic: " .. spec.name, function()
            local old_native = rawget(_G, "MODDED_REALM")
            local old_script_data = rawget(_G, "script_data")
            local mod, environment, emitted = fixture(spec)
            local script_data = environment.script_data
            local old_legacy = rawget(script_data, "eac-untrusted")
            H.equal(type(mod._cim_autodump_forge_open), "function")
            mod._cim_autodump_forge_open("HeroWindowCrafting")
            H.equal(#emitted, 1, "realm evidence must use raw printf, not VMF logging")
            H.truthy(emitted[1]:find("[cim:1694] forge_open class=HeroWindowCrafting modded_realm="
                .. tostring(spec.expected), 1, true), emitted[1])
            H.equal(emitted[1]:find("eac_untrusted=", 1, true), nil,
                "realm evidence must not be mislabeled as a retired EAC flag")
            H.equal(rawget(environment, "MODDED_REALM"), spec.native)
            H.equal(rawget(script_data, "eac-untrusted"), old_legacy)
            H.equal(rawget(_G, "MODDED_REALM"), old_native)
            H.equal(rawget(_G, "script_data"), old_script_data)
        end)
    end

    H.test("CIM forge diagnostic rereads current realm and existing authority", function()
        local mod, environment, emitted = fixture({ native = true })
        mod._cim_autodump_forge_open("HeroWindowCrafting")
        environment.MODDED_REALM = false
        mod._cim_autodump_forge_open("HeroWindowCraftingConsole")
        H.equal(#emitted, 2)
        H.truthy(emitted[1]:find("modded_realm=true", 1, true))
        H.truthy(emitted[2]:find("class=HeroWindowCraftingConsole modded_realm=false", 1, true))
        local reads = 0
        mod._cim_is_modded_realm = function() reads = reads + 1; return true end
        mod._cim_autodump_forge_open("HeroWindowCrafting")
        H.equal(reads, 1, "forge-open must query the current entry-owned authority exactly once")
    end)
end
