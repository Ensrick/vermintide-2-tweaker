-- #913: exercise the installed production Localize callback, not string presence.
-- The deterministic seam is the private mod localizer; optional local VMF/native
-- sources strengthen provenance without becoming required CI dependencies.
return function(H, repo_root)
    local base = repo_root .. "/cosmetics_tweaker/scripts/mods/cosmetics_tweaker/"
    local mallet = "ct_es_2h_hammer_tut_01"
    local mace = "ct_es_mace_gk_shield_01"
    local authored = {
        [mallet] = "The wooden training mallet from Kruber's Prologue, swung as a Great Hammer.",
        [mace] = "An Empire mace paired with a Bretonnian shield.",
    }

    local function read(path)
        local file = assert(io.open(path, "rb"))
        local text = file:read("*a")
        file:close()
        return text
    end

    local function execute(path, env, lower_continue)
        local text = read(path):gsub("^\239\187\191", "")
        if lower_continue then
            local count
            text, count = text:gsub("if _custom_skin_keys%[skin_key%] then goto continue end",
                "if not _custom_skin_keys[skin_key] then")
            H.equal(count, 1, "exact Lua 5.1 continue lowering branch")
            text, count = text:gsub("::continue::", "end")
            H.equal(count, 1, "exact Lua 5.1 continue lowering label")
        end
        return setfenv(assert(loadstring(text, "@" .. path)), env)()
    end

    local function fixture(real_sources)
        local env = setmetatable({}, { __index = _G })
        env._G = env
        local checks, prints, hooks, calls = {}, {}, {}, { private = 0, native = 0 }
        local api = {
            get_name = function(self) return self.name end,
            is_enabled = function() return true end,
            get_internal_data = function() return false end,
            info = function() end, error = function() end, warning = function() end,
            get = function() return false end,
        }
        local cos = setmetatable({ name = "cosmetics_tweaker", _cos = {
            LA_BRIDGE = { localization = { la_control = "Loremaster control" } },
            custom_skin_keys = {}, skin_requires_unowned_dlc = function() return false end,
            encarmine_item_localization = { hat_control = "Hat control" },
            gk_set_item_localization = { outfit_control = "Outfit control" },
            presentation_localization = { presentation_control = "Presentation control" },
        }, _cos_command_owner = { register = function(name, fn)
            H.equal(checks[name], nil, "duplicate runtime check")
            checks[name] = fn
        end } }, { __index = api })
        local vmf = setmetatable({ name = "VMF", dofile = function() return {} end,
            check_wrong_argument_type = function() return false end }, { __index = api })
        cos.dofile = function(_, path)
            return execute(repo_root .. "/cosmetics_tweaker/" .. path .. ".lua", env)
        end
        env.get_mod = function(name)
            if name == "VMF" then return vmf end
            if name == "cosmetics_tweaker" then return cos end
        end
        env.printf = function(format, ...) prints[#prints + 1] = string.format(format, ...) end
        env.ItemMasterList = {}
        env.WeaponSkins = { skins = {}, skin_combinations = {} }
        env.NetworkLookup = { weapon_skins = {} }
        env.BackendInterfaceCraftingPlayfab = { get_unlocked_weapon_skins = function() end }
        local loc = execute(base .. "cosmetics_tweaker_localization.lua", env)
        local native = function(key, ...)
            calls.native = calls.native + 1
            return key == "native_control" and "Native control" or ("<" .. tostring(key) .. ">"), ...
        end
        env.Localize = native
        local set_language
        if real_sources then
            env.VMFMod = api
            env.Application = { user_setting = function() return "en" end }
            set_language = function(language)
                env.Application.user_setting = function() return language end
                execute(real_sources.vmf .. "/localization.lua", env)
                vmf.initialize_mod_localization(cos, loc)
            end
            set_language("en")
            env.class = function() return {} end
            env.fassert = assert
            env.Localizer = { lookup = function() return nil end }
            execute(real_sources.native, env)
            local manager = setmetatable({ _localizers = {},
                _backend_localizations = { native_control = "Native control" },
                _find_macro_callback_to_self = function(text) return text end,
            }, { __index = env.LocalizationManager })
            native = function(key, ...)
                calls.native = calls.native + 1
                return manager:lookup(key), ...
            end
            env.Localize = native
            execute(real_sources.vmf .. "/hooks.lua", env)
        else
            cos.localize = function(_, key, ...)
                calls.private = calls.private + 1
                local row = loc[key]
                return row and string.format(row.en, ...) or ("<" .. tostring(key) .. ">")
            end
            cos.hook = function(_, object, method, callback)
                H.equal(object, env, "only global Localize is installed")
                H.equal(method, "Localize")
                H.equal(hooks[method], nil, "singleton Localize owner")
                hooks[method] = callback
                local original = object[method]
                object[method] = function(...) return callback(original, ...) end
            end
            cos.hook_safe = function(_, class, method)
                H.equal(class, "BackendInterfaceCraftingPlayfab")
                H.equal(method, "get_unlocked_weapon_skins")
            end
        end
        execute(base .. "_cos_illusions.lua", env, true)
        return { env = env, cos = cos, loc = loc, checks = checks, calls = calls,
            prints = prints, native = native, set_language = set_language }
    end

    H.test("Cosmetics registered mallet and mace descriptions cross the installed global hook", function()
        local f = fixture()
        H.equal(#f.cos._cos.custom_illusions, 5)
        for skin, text in pairs(authored) do
            local key = skin .. "_description"
            H.equal(f.loc[key].en, text, "independent authored copy")
            H.equal(f.env.ItemMasterList[skin].description, key)
            H.equal(f.env.WeaponSkins.skins[skin].description, key)
            H.equal(f.env.Localize(key), text)
        end
        H.equal(f.calls.private, 2)
        H.equal(f.calls.native, 0)
        H.equal(f.checks.issue913_custom_illusion_descriptions(), nil)
        H.equal(#f.prints, 1)
        H.equal(f.prints[1], "[cos:913] applied: registered custom-description bridge catalog_rows=5")
    end)

    H.test("Cosmetics leaves the three unauthored spear descriptions visibly unavailable", function()
        local f = fixture()
        for index = 1, 3 do
            local key = "ct_es_heavy_spear_deus_0" .. index .. "_description"
            H.equal(f.loc[key], nil, "do not invent or borrow unrelated flavor text")
            H.equal(f.env.Localize(key), "<" .. key .. ">")
        end
        H.equal(f.calls.native, 3)
    end)

    H.test("Cosmetics description allowlist excludes unregistered and neighboring private keys", function()
        local f = fixture()
        f.loc.ct_foreign_description = { en = "Must stay private" }
        f.loc[mallet .. "_description_extra"] = { en = "Must stay private" }
        H.equal(f.env.Localize("ct_foreign_description"), "<ct_foreign_description>")
        H.equal(f.env.Localize(mallet .. "_description_extra"), "<" .. mallet .. "_description_extra>")
        f.cos._cos.custom_skin_keys[mallet] = nil
        H.equal(f.env.Localize(mallet .. "_description"), "<" .. mallet .. "_description>")
        H.equal(f.calls.private, 0)
    end)

    H.test("Cosmetics preserves names, hats, presentation, LA and native variadic results", function()
        local f = fixture()
        for _, row in ipairs(f.cos._cos.custom_illusions) do
            H.equal(f.env.Localize(row.skin_key .. "_name"), row.display_name)
        end
        H.equal(f.env.Localize("hat_control"), "Hat control")
        H.equal(f.env.Localize("outfit_control"), "Outfit control")
        H.equal(f.env.Localize("presentation_control"), "Presentation control")
        H.equal(f.env.Localize("la_control"), "Loremaster control")
        H.equal(f.env.Localize("missing_control"), "<missing_control>")
        local a, b, c, d = f.env.Localize("native_control", 17, nil, 23)
        H.deep_equal({ a, b, c, d }, { "Native control", 17, nil, 23 })
        H.equal(f.calls.private, 0)
    end)

    H.test("Cosmetics reads private localization afresh and formats percent only once", function()
        local f = fixture()
        local key = mallet .. "_description"
        f.loc[key].en = "Test text: 25%%; %s"
        H.equal(f.env.Localize(key, "one"), "Test text: 25%; one")
        f.loc[key].en = "Replacement: %s"
        H.equal(f.env.Localize(key, "two"), "Replacement: two")
        f.cos.localize = function(_, received, ...)
            H.equal(received, key)
            H.equal(select("#", ...), 3)
            local a, b, c = ...
            H.equal(a, 17); H.equal(b, nil); H.equal(c, 23)
            return "Replacement provider"
        end
        H.equal(f.env.Localize(key, 17, nil, 23), "Replacement provider")
    end)

    local malformed = { false, 17, {}, "", "<INVALID STRING FORMAT>",
        "<" .. mallet .. "_description>", mallet .. "_description" }
    for index, value in ipairs(malformed) do
        H.test("Cosmetics malformed private description follows original fallback " .. index, function()
            local f = fixture()
            f.cos.localize = function() return value end
            local key = mallet .. "_description"
            local a, b, c, d = f.env.Localize(key, 17, nil, 23)
            H.deep_equal({ a, b, c, d }, { "<" .. key .. ">", 17, nil, 23 })
            f.cos._cos.presentation_localization[key] = "Presentation fallback"
            H.equal(f.env.Localize(key), "Presentation fallback")
            f.cos._cos.presentation_localization[key] = nil
            f.cos._cos.LA_BRIDGE.localization[key] = "LA fallback"
            H.equal(f.env.Localize(key), "LA fallback")
        end)
    end

    H.test("Cosmetics absent or throwing private localizer retains vanilla fallback", function()
        local f = fixture()
        local key = mallet .. "_description"
        f.cos.localize = function() return nil end
        H.equal(f.env.Localize(key), "<" .. key .. ">")
        f.cos.localize = function() error("private localizer failure") end
        H.equal(f.env.Localize(key), "<" .. key .. ">")
        f.cos.localize = nil
        H.equal(f.env.Localize(key), "<" .. key .. ">")
    end)

    H.test("Cosmetics named live check detects disconnected hook and corrupted skin identities", function()
        local f = fixture()
        local check = f.checks.issue913_custom_illusion_descriptions
        H.equal(check(), nil)
        local installed = f.env.Localize
        f.env.Localize = f.native
        H.truthy(check():find("global description differs", 1, true))
        f.env.Localize = installed
        f.env.WeaponSkins.skins[mallet].description = "foreign"
        H.truthy(check():find("registered description identity missing", 1, true))
        f.env.WeaponSkins.skins[mallet].description = mallet .. "_description"
        f.loc[mallet .. "_description"] = nil
        H.truthy(check():find("authored private description unavailable", 1, true))
    end)

    local home = os.getenv("USERPROFILE") or ""
    local vmf = (os.getenv("VT2_VMF_SOURCE_ROOT") or (home .. "/source/repos/Vermintide-Mod-Framework"))
        .. "/vmf/scripts/mods/vmf/modules/core"
    local native = (os.getenv("VT2_SOURCE_ROOT") or (home .. "/source/repos/Vermintide-2-Source-Code"))
        .. "/foundation/scripts/managers/localization/localization_manager.lua"
    local function exists(path)
        local file = io.open(path, "rb")
        if not file then return false end
        file:close()
        return true
    end
    H.test_if(exists(vmf .. "/localization.lua") and exists(vmf .. "/hooks.lua") and exists(native),
        "Cosmetics optional actual VMF/native Localize preserves language and English fallback", function()
            local f = fixture({ vmf = vmf, native = native })
            local key = mallet .. "_description"
            H.equal(f.env.Localize(key), authored[mallet])
            H.equal(f.env.Localize("native_control"), "Native control")
            H.equal(f.checks.issue913_custom_illusion_descriptions(), nil)
            f.loc[key].fr = "Texte fran\195\167ais: 25%%"
            f.set_language("fr")
            H.equal(f.env.Localize(key), "Texte fran\195\167ais: 25%")
            H.equal(f.env.Localize(mace .. "_description"), authored[mace])
            f.loc[key].fr = "%q"
            H.equal(f.env.Localize(key), authored[mallet], "malformed French falls back to English")
            f.loc[key].en = "%q"
            H.equal(f.env.Localize(key), "<" .. key .. ">", "both malformed fall through")
            f.loc[key].en = authored[mallet]
            f.set_language("en")
            H.equal(f.env.Localize(key), authored[mallet])
            local before = f.calls.native
            H.equal(f.cos:localize(key), authored[mallet])
            H.equal(f.calls.native, before, "private localizer does not recurse globally")
            local a, b, c, d = f.env.Localize("native_control", 17, nil, 23)
            H.deep_equal({ a, b, c, d }, { "Native control", 17, nil, 23 })
        end, "optional local VMF + decompiled localization sources unavailable")
end
