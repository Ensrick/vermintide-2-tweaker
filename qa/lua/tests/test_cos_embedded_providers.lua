-- WP-COS-05 (audit findings A3-F03, A3-F08): _la_prefix_embedded.lua replaces
-- the VMFMod prototype's hook / hook_safe / hook_origin for every mod (it drops
-- Loremaster's Armoury's duplicate registrations) and the global get_mod (so
-- "MoreItemsLibrary" and "Material-Hijack" resolve to the embedded provider
-- when the standalone mods are absent). character_weapon_variants and
-- weapons_of_chaos rely on that lookup. Nothing tested these wraps before.
-- The file is loaded for real under saved and restored globals.
return function(H, repo_root)
    local path = repo_root .. "/cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_la_prefix_embedded.lua"
    local GLOBALS = { "VMFMod", "get_mod", "_cos_mil_embed_owner", "_cos_mh_embed_owner",
        "_cos_la_prefix_get_mod_wrapped" }

    local function with_sandbox(body)
        local saved = {}
        for _, name in ipairs(GLOBALS) do saved[name] = rawget(_G, name) end
        local registry, calls = {}, {}
        local proto = {}
        local function recorder(kind, ret)
            return function(self, obj, method, handler)
                calls[#calls + 1] = { kind = kind, self = self, obj = obj, method = method, handler = handler }
                return ret
            end
        end
        proto.hook = recorder("hook", "hook-ret")
        proto.hook_safe = recorder("hook_safe", "safe-ret")
        proto.hook_origin = recorder("hook_origin", "origin-ret")
        local cos = {
            info = function() end, warning = function() end,
            get = function() return nil end, hook = function() end,
        }
        registry.cosmetics_tweaker = cos
        rawset(_G, "VMFMod", proto)
        rawset(_G, "get_mod", function(name) return registry[name] end)
        rawset(_G, "_cos_mil_embed_owner", nil)
        rawset(_G, "_cos_mh_embed_owner", nil)
        rawset(_G, "_cos_la_prefix_get_mod_wrapped", nil)
        local ok, err = pcall(function()
            assert(loadfile(path))()
            body({ registry = registry, calls = calls, proto = proto, cos = cos,
                load_again = function() assert(loadfile(path))() end })
        end)
        for _, name in ipairs(GLOBALS) do rawset(_G, name, saved[name]) end
        if not ok then error(err, 0) end
    end

    H.test("COS A3-F08 a non-LA mod's hook is forwarded unchanged", function()
        with_sandbox(function(s)
            local other = { get_name = function() return "other_mod" end }
            local handler = function() end
            local ret = VMFMod.hook(other, "SomeClass", "some_method", handler)
            H.equal(ret, "hook-ret", "the original return value is passed back")
            local last = s.calls[#s.calls]
            H.equal(last.kind, "hook")
            H.equal(last.self, other)
            H.equal(last.obj, "SomeClass")
            H.equal(last.method, "some_method")
            H.equal(last.handler, handler)
            H.equal(VMFMod.hook_safe(other, "SomeClass", "other_method", handler), "safe-ret")
        end)
    end)

    H.test("COS A3-F08 LA's second registration of the same (obj, method) is dropped", function()
        with_sandbox(function(s)
            local la = { get_name = function() return "Loremasters-Armoury" end }
            local first, second = function() end, function() end
            local before = #s.calls
            H.equal(VMFMod.hook(la, "SomeClass", "some_method", first), "hook-ret")
            H.equal(#s.calls, before + 1)
            H.equal(s.calls[#s.calls].handler, first, "the first registration is forwarded")
            H.equal(VMFMod.hook(la, "SomeClass", "some_method", second), nil)
            H.equal(#s.calls, before + 1, "the duplicate is dropped")
        end)
    end)

    H.test("COS A3-F08 get_mod resolves MoreItemsLibrary to the standalone, else the embed owner", function()
        with_sandbox(function(s)
            local other = { name = "other" }
            s.registry.other_mod = other
            _G._cos_mil_embed_owner = "cosmetics_tweaker"
            H.equal(get_mod("MoreItemsLibrary"), s.cos, "no standalone: the embed owner")
            local standalone = { is_enabled = function() return true end }
            s.registry.MoreItemsLibrary = standalone
            H.equal(get_mod("MoreItemsLibrary"), standalone, "an enabled standalone wins")
            standalone.is_enabled = function() return false end
            H.equal(get_mod("MoreItemsLibrary"), s.cos, "a disabled standalone yields to the embed owner")
            H.equal(get_mod("other_mod"), other, "any other name passes through")
            H.equal(get_mod("missing_mod"), nil)
        end)
    end)

    H.test("COS A3-F08 loading the embed twice does not wrap twice", function()
        with_sandbox(function(s)
            local hook, hook_safe, hook_origin, resolver = VMFMod.hook, VMFMod.hook_safe, VMFMod.hook_origin, get_mod
            H.truthy(hook ~= s.proto and VMFMod._cos_la_prefix_wrapped == true, "the first load wrapped the prototype")
            s.load_again()
            H.equal(VMFMod.hook, hook)
            H.equal(VMFMod.hook_safe, hook_safe)
            H.equal(VMFMod.hook_origin, hook_origin)
            H.equal(get_mod, resolver)
        end)
    end)
end
