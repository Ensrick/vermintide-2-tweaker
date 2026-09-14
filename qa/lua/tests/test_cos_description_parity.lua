-- #1567: item / illusion description-key parity. Pure provider cases run on
-- ordinary tables; the installed-hook cases drive the production _G.Localize
-- callback from _cos_illusions.lua through the same private-localizer seam the
-- #913 suite uses; the decompile scan is an optional provenance fixture.
return function(H, repo_root)
    local base = repo_root .. "/cosmetics_tweaker/scripts/mods/cosmetics_tweaker/"
    local SHYISH = "Weaponry tainted by the Wind of Death. What can possibly go wrong?"
    local WEAVE = "Weaponry forged in the Weaves."
    local shyish_typo = "wh_deus_skin_02_magic_02_desciption"
    local shyish_sibling = "wh_fencing_sword_skin_07_magic_02_description"
    local shyish_corrected = "wh_deus_skin_02_magic_02_description"
    local weave_typo = "wh_deus_01_magic_desciption"
    local weave_sibling = "wh_deus_01_magic_description"

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

    local Parity = execute(base .. "_cos_description_parity.lua", setmetatable({}, { __index = _G }))

    local function localize_from(map)
        return function(key) return map[key] or ("<" .. key .. ">") end
    end

    local function deep_copy(value)
        if type(value) ~= "table" then return value end
        local copy = {}
        for key, item in pairs(value) do copy[key] = deep_copy(item) end
        return copy
    end

    -- Installed-hook fixture: the production illusions module, the private
    -- localizer seam and a native Localize backed by an editable map. The engine
    -- tables carry the four vanilla typo rows plus one resolvable vanilla skin.
    local function fixture()
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
        cos.dofile = function(_, path)
            return execute(repo_root .. "/cosmetics_tweaker/" .. path .. ".lua", env)
        end
        env.get_mod = function(name)
            if name == "cosmetics_tweaker" then return cos end
        end
        env.printf = function(format, ...) prints[#prints + 1] = string.format(format, ...) end
        env.ItemMasterList = {
            wh_deus_skin_02_magic_02 = { description = shyish_typo, display_name = "wh_deus_skin_02_magic_02_name" },
        }
        env.WeaponSkins = { skins = {
            wh_deus_skin_02_magic_02 = { description = shyish_typo },
            wh_deus_01_skin_magic = { description = weave_typo },
            wh_deus_02_skin_magic = { description = weave_typo },
            es_1h_sword_skin_01 = { description = "es_1h_sword_skin_01_description" },
        }, skin_combinations = {} }
        env.NetworkLookup = { weapon_skins = {} }
        env.BackendInterfaceCraftingPlayfab = { get_unlocked_weapon_skins = function() end }
        local loc = execute(base .. "cosmetics_tweaker_localization.lua", env)
        local native_map = {
            [shyish_sibling] = SHYISH,
            [weave_sibling] = WEAVE,
            es_1h_sword_skin_01_description = "A sword.",
            native_control = "Native control",
        }
        local native = function(key, ...)
            calls.native = calls.native + 1
            return native_map[key] or ("<" .. tostring(key) .. ">"), ...
        end
        env.Localize = native
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
        execute(base .. "_cos_illusions.lua", env, true)
        return { env = env, cos = cos, loc = loc, checks = checks, calls = calls,
            prints = prints, native = native, native_map = native_map }
    end

    H.test("#1567 alias table pins the two vanilla typo keys and their sibling order", function()
        H.deep_equal(Parity.VANILLA_ALIASES, {
            [shyish_typo] = { shyish_corrected, shyish_sibling },
            [weave_typo] = { weave_sibling },
        })
        H.equal(#Parity.VANILLA_TYPO_ROWS, 4)
        for _, row in ipairs(Parity.VANILLA_TYPO_ROWS) do
            H.truthy(Parity.VANILLA_ALIASES[row.description_key], "every typo row has an alias")
            H.truthy(row.table == "skins" or row.table == "items", "row table is skins or items")
            H.equal(type(row.key), "string")
        end
        H.equal(Parity.SAMPLE_CAP, 12)
        H.equal(Parity.API_VERSION, 1)
    end)

    H.test("#1567 resolved accepts rendered text and rejects placeholders", function()
        H.equal(Parity.resolved("Text", "k"), true)
        H.equal(Parity.resolved("", "k"), false)
        H.equal(Parity.resolved("<k>", "k"), false)
        H.equal(Parity.resolved("k", "k"), false)
        H.equal(Parity.resolved(nil, "k"), false)
        H.equal(Parity.resolved(17, "k"), false)
    end)

    H.test("#1567 alias_route prefers the corrected spelling, then the sibling, else nil", function()
        H.equal(Parity.alias_route(shyish_typo, localize_from({ [shyish_sibling] = SHYISH })), shyish_sibling)
        H.equal(Parity.alias_route(shyish_typo, localize_from({ [shyish_sibling] = SHYISH,
            [shyish_corrected] = "Corrected" })), shyish_corrected)
        H.equal(Parity.alias_route(shyish_typo, localize_from({})), nil)
        H.equal(Parity.alias_route(shyish_typo, localize_from({ [shyish_corrected] = "" })), nil)
        H.equal(Parity.alias_route(weave_typo, localize_from({ [weave_sibling] = WEAVE })), weave_sibling)
        H.equal(Parity.alias_route(weave_sibling, localize_from({ [weave_sibling] = WEAVE })), nil,
            "correctly spelled keys are never aliased")
        H.equal(Parity.alias_route(shyish_typo, nil), nil)
        H.equal(Parity.alias_route(shyish_typo, function(key)
            if key == shyish_corrected then error("native failure") end
            return SHYISH
        end), shyish_sibling, "a throwing candidate is skipped")
    end)

    H.test("#1567 census counts distinct keys, skips test rows, caps the sorted sample and mutates nothing", function()
        local items = {
            sword = { description = "sword_description" },
            sword_dup = { description = "sword_description" },
            chest = { description = "chest_description" },
            test_item_1001 = { description = "test_item_1001_desc" },
            blank = { description = "" },
            nodesc = { display_name = "x" },
            wrapped = { data = { description = "wrapped_description" } },
        }
        local skins = {
            shy = { description = shyish_typo },
            weave = { description = weave_typo },
            custom = { description = "ct_custom_description" },
            fine = { description = "fine_description" },
        }
        local items_before, skins_before = deep_copy(items), deep_copy(skins)
        local map = { sword_description = "A sword.", fine_description = "Fine.", [shyish_typo] = SHYISH }
        local localize = function(key)
            if key == weave_typo then error("native failure") end
            return map[key] or ("<" .. key .. ">")
        end
        local is_custom = function(key) return key:sub(1, 3) == "ct_" end
        local report = Parity.census(items, skins, localize, { sample_cap = 3, is_custom = is_custom })
        H.equal(report.item_rows, 5)
        H.equal(report.skin_rows, 4)
        H.equal(report.skipped_test, 1)
        H.equal(report.keys, 7)
        H.equal(report.resolved, 3)
        H.equal(report.unresolved, 4)
        H.equal(report.bridged, 1)
        H.equal(report.custom, 1)
        H.equal(report.custom_unresolved, 1)
        H.deep_equal(report.sample, { "chest_description", "ct_custom_description", weave_typo })
        H.equal(report.truncated, true)
        H.equal(Parity.sample_text(report), "chest_description,ct_custom_description," .. weave_typo .. ",...")
        local full = Parity.census(items, skins, localize)
        H.deep_equal(full.sample, { "chest_description", "ct_custom_description", weave_typo, "wrapped_description" })
        H.equal(full.truncated, false)
        H.equal(full.custom, 0, "no custom predicate means no custom counts")
        H.deep_equal(items, items_before, "items are not mutated")
        H.deep_equal(skins, skins_before, "skins are not mutated")
        local empty = Parity.census(nil, nil, nil)
        H.deep_equal(empty, { item_rows = 0, skin_rows = 0, keys = 0, resolved = 0, unresolved = 0,
            bridged = 0, custom = 0, custom_unresolved = 0, skipped_test = 0, sample = {}, truncated = false })
        H.equal(Parity.sample_text(empty), "-")
        H.equal(Parity.sample_text(nil), "-")
        local no_localize = Parity.census(items, nil, nil)
        H.equal(no_localize.unresolved, 3, "an absent localizer resolves nothing")
    end)

    H.test("#1567 installed hook routes vanilla typo keys to sibling text and keeps native fallback", function()
        local f = fixture()
        H.equal(f.env.Localize(shyish_typo), SHYISH)
        H.equal(f.env.Localize(weave_typo), WEAVE)
        f.native_map[shyish_corrected] = "Corrected spelling"
        H.equal(f.env.Localize(shyish_typo), "Corrected spelling", "a corrected vanilla key wins")
        f.native_map[shyish_corrected] = nil
        local a, b, c, d = f.env.Localize(shyish_typo, 17, nil, 23)
        H.deep_equal({ a, b, c, d }, { SHYISH, 17, nil, 23 }, "native variadic shape is kept")
        f.native_map[shyish_sibling] = nil
        local e, g, h, i = f.env.Localize(shyish_typo, 17, nil, 23)
        H.deep_equal({ e, g, h, i }, { "<" .. shyish_typo .. ">", 17, nil, 23 }, "no sibling keeps vanilla's placeholder")
        f.native_map[shyish_sibling] = SHYISH
        H.equal(f.env.Localize(weave_sibling), WEAVE, "correct keys are untouched")
        H.equal(f.env.Localize("wh_deus_skin_02_magic_02_name"), "<wh_deus_skin_02_magic_02_name>")
        H.equal(f.env.Localize("native_control"), "Native control")
        H.equal(f.calls.private, 0)
        H.equal(#f.prints, 1, "no new load-time receipt")
        H.equal(f.cos._cos.description_parity, f.cos._cos.description_parity, "provider is published")
        H.equal(type(f.cos._cos.description_parity.census), "function")
    end)

    H.test("#1567 every registered custom illusion description resolves to authored text", function()
        local f = fixture()
        H.equal(#f.cos._cos.custom_illusions, 5)
        for _, row in ipairs(f.cos._cos.custom_illusions) do
            local key = row.skin_key .. "_description"
            local text = f.loc[key] and f.loc[key].en
            H.truthy(type(text) == "string" and #text > 0, "authored: " .. key)
            H.equal(f.env.Localize(key), text)
            H.equal(text:find("[", 1, true), nil, "no bracket tag in " .. key)
            H.equal(text:find("%", 1, true), nil, "no percent in " .. key)
            H.equal(text:find("\226\128\148", 1, true), nil, "no em dash in " .. key)
        end
        H.equal(f.calls.native, 0)
    end)

    H.test("#1567 named check passes on a parity fixture and names each defect", function()
        local f = fixture()
        local check = f.checks.issue1567_item_description_parity
        H.equal(check(), nil)
        local spear = "ct_es_heavy_spear_deus_02_description"
        local kept = f.loc[spear]
        f.loc[spear] = nil
        H.truthy(check():find("authored private description unavailable: " .. spear, 1, true))
        f.loc[spear] = kept
        local installed = f.env.Localize
        f.env.Localize = f.native
        H.truthy(check():find("global description differs", 1, true))
        f.env.Localize = installed
        f.env.WeaponSkins.skins.wh_deus_01_skin_magic.description = weave_sibling
        H.truthy(check():find("vanilla typo row changed, retire its alias: wh_deus_01_skin_magic", 1, true))
        f.env.WeaponSkins.skins.wh_deus_01_skin_magic.description = weave_typo
        f.native_map[shyish_sibling] = nil
        H.truthy(check():find("no sibling text resolves for vanilla typo key: " .. shyish_typo, 1, true))
        f.native_map[shyish_sibling] = SHYISH
        f.env.Localize = function(key, ...)
            if Parity.VANILLA_ALIASES[key] then return f.native(key, ...) end
            return installed(key, ...)
        end
        H.truthy(check():find("typo key does not follow its sibling text: " .. shyish_typo, 1, true))
        f.env.Localize = installed
        f.env.WeaponSkins.skins.broken = { description = "broken_skin_description" }
        f.env.ItemMasterList.broken_item = { description = "zz_item_description" }
        H.truthy(check():find("2 unresolved description keys: broken_skin_description,zz_item_description", 1, true))
        f.env.WeaponSkins.skins.broken = nil
        f.env.ItemMasterList.broken_item = nil
        f.env.ItemMasterList.test_item_1001 = { description = "test_item_1001_desc" }
        H.equal(check(), nil, "vanilla test rows are skipped, not reported")
        H.equal(f.checks.issue913_custom_illusion_descriptions(), nil, "the #913 check still passes")
    end)

    H.test("#1567 diagnostic command prints one finite census line", function()
        local source = read(base .. "_cos_diagnostics.lua"):gsub("\r\n", "\n")
        local block = assert(source:match('(local function _issue1567_description_census%(%).-\nmod:command%("cos_1567_diag".-\nend%))'))
        local callback = assert(block:match('\nmod:command%("cos_1567_diag".-\nend%)$'))
        H.equal(callback:find("for ", 1, true), nil, "census emitter stays loop-free")
        H.equal(callback:find("\n%s*local%s+[%w_]+%s*,"), nil, "callback keeps a simple body")
        local f = fixture()
        local registered, logs, flushed, echoed = {}, {}, 0, 0
        local env = {
            pcall = pcall, type = type, rawget = rawget, ipairs = ipairs,
            _flush_log = function() flushed = flushed + 1 end,
            printf = function(format, ...) logs[#logs + 1] = string.format(format, ...) end,
        }
        env._G = env
        env.COS = f.cos._cos
        env.mod = {
            command = function(_, name, description, fn)
                registered[name] = { description = description, callback = fn }
            end,
            echo = function() echoed = echoed + 1 end,
        }
        env.ItemMasterList = f.env.ItemMasterList
        env.WeaponSkins = f.env.WeaponSkins
        env.Localize = f.env.Localize
        setfenv(assert(loadstring(block)), env)()
        local command = assert(registered.cos_1567_diag)
        H.equal(command.description, "Census item and illusion description keys against resolved text")
        command.callback()
        H.equal(logs[1], "[cos:1567:diag] census items=6 skins=9 keys=8 resolved=8 unresolved=0 "
            .. "bridged=2 custom=5 custom_unresolved=0 skipped_test=0 sample=-")
        env.WeaponSkins.skins.broken = { description = "broken_description" }
        command.callback()
        H.equal(logs[2], "[cos:1567:diag] census items=6 skins=10 keys=9 resolved=8 unresolved=1 "
            .. "bridged=2 custom=5 custom_unresolved=0 skipped_test=0 sample=broken_description")
        env.COS = {}
        command.callback()
        H.equal(logs[3], "[cos:1567:diag] census items=0 skins=0 keys=0 resolved=0 unresolved=-1 "
            .. "bridged=-1 custom=0 custom_unresolved=-1 skipped_test=0 sample=-")
        H.equal(#logs, 3)
        H.equal(flushed, 3)
        H.equal(echoed, 3)
    end)

    -- Optional provenance: every description key in the decompiled item, skin,
    -- cosmetic and pose tables. The file manifest is pinned so the scan is
    -- deterministic; a renamed or missing file fails the case.
    local source_root = (os.getenv("VT2_SOURCE_ROOT")
        or ((os.getenv("USERPROFILE") or "") .. "/source/repos/Vermintide-2-Source-Code"))
    local manifest = {
        "scripts/settings/dlcs/anniversary_2025/item_master_list_anniversary_2025.lua",
        "scripts/settings/dlcs/anniversary_2026/item_master_list_anniversary_2026.lua",
        "scripts/settings/dlcs/bless/item_master_list_bless.lua",
        "scripts/settings/dlcs/bless/weapon_skins_bless.lua",
        "scripts/settings/dlcs/cog/item_master_list_cog.lua",
        "scripts/settings/dlcs/cog/weapon_skins_cog.lua",
        "scripts/settings/dlcs/divine/item_master_list_divine.lua",
        "scripts/settings/dlcs/geheimnisnacht_2021/item_master_list_geheimnisnacht_2021.lua",
        "scripts/settings/dlcs/geheimnisnacht_2021/weapon_skins_geheimnisnacht_2021.lua",
        "scripts/settings/dlcs/geheimnisnacht_2025/item_master_list_geheimnisnacht_2025.lua",
        "scripts/settings/dlcs/geheimnisnacht_2025/weapon_skins_geheimnisnacht_2025.lua",
        "scripts/settings/dlcs/geheimnisnacht_2026/item_master_list_geheimnisnacht_2026.lua",
        "scripts/settings/dlcs/geheimnisnacht_2026/weapon_skins_geheimnisnacht_2026.lua",
        "scripts/settings/dlcs/gotwf/item_master_list_gotwf.lua",
        "scripts/settings/dlcs/gotwf/item_master_list_gotwf_2024.lua",
        "scripts/settings/dlcs/gotwf/item_master_list_gotwf_2025.lua",
        "scripts/settings/dlcs/gotwf/item_master_list_gotwf_2026.lua",
        "scripts/settings/dlcs/gotwf/weapon_skins_gotwf.lua",
        "scripts/settings/dlcs/gotwf/weapon_skins_gotwf_2024.lua",
        "scripts/settings/dlcs/gotwf/weapon_skins_gotwf_2025.lua",
        "scripts/settings/dlcs/gotwf/weapon_skins_gotwf_2026.lua",
        "scripts/settings/dlcs/lake/item_master_list_lake.lua",
        "scripts/settings/dlcs/morris_2024/item_master_list_morris_2024.lua",
        "scripts/settings/dlcs/morris_2024/weapon_skins_morris_2024.lua",
        "scripts/settings/dlcs/morris_2025/weapon_skins_morris_2025.lua",
        "scripts/settings/dlcs/shovel/item_master_list_shovel.lua",
        "scripts/settings/dlcs/shovel/weapon_skins_shovel.lua",
        "scripts/settings/dlcs/skulls_2023/item_master_list_skulls_2023.lua",
        "scripts/settings/dlcs/skulls_2023/weapon_skins_skulls_2023.lua",
        "scripts/settings/dlcs/skulls_2025/item_master_list_skulls_2025.lua",
        "scripts/settings/dlcs/skulls_2025/weapon_skins_skulls_2025.lua",
        "scripts/settings/dlcs/skulls_2026/item_master_list_skulls_2026.lua",
        "scripts/settings/dlcs/skulls_2026/weapon_skins_skulls_2026.lua",
        "scripts/settings/dlcs/versus_rewards/item_master_list_versus_rewards.lua",
        "scripts/settings/dlcs/versus_rewards/weapon_skins_versus_rewards.lua",
        "scripts/settings/dlcs/woods/item_master_list_woods.lua",
        "scripts/settings/dlcs/woods/weapon_skins_woods.lua",
        "scripts/settings/equipment/item_master_list_anvil.lua",
        "scripts/settings/equipment/item_master_list_belakor.lua",
        "scripts/settings/equipment/item_master_list_carousel.lua",
        "scripts/settings/equipment/item_master_list_celebrate.lua",
        "scripts/settings/equipment/item_master_list_cosmetics_2022_q1.lua",
        "scripts/settings/equipment/item_master_list_cosmetics_2022_q2.lua",
        "scripts/settings/equipment/item_master_list_cosmetics_2022_q3.lua",
        "scripts/settings/equipment/item_master_list_cosmetics_2023_q1.lua",
        "scripts/settings/equipment/item_master_list_cosmetics_2023_q2.lua",
        "scripts/settings/equipment/item_master_list_cosmetics_2023_q4.lua",
        "scripts/settings/equipment/item_master_list_cosmetics_2024_q2.lua",
        "scripts/settings/equipment/item_master_list_cosmetics_2024_q3.lua",
        "scripts/settings/equipment/item_master_list_eight_ball.lua",
        "scripts/settings/equipment/item_master_list_exported.lua",
        "scripts/settings/equipment/item_master_list_karak.lua",
        "scripts/settings/equipment/item_master_list_local.lua",
        "scripts/settings/equipment/item_master_list_morris.lua",
        "scripts/settings/equipment/item_master_list_paperweight.lua",
        "scripts/settings/equipment/item_master_list_scorpion.lua",
        "scripts/settings/equipment/item_master_list_store.lua",
        "scripts/settings/equipment/item_master_list_termite.lua",
        "scripts/settings/equipment/item_master_list_test_items.lua",
        "scripts/settings/equipment/item_master_list_weapon_poses.lua",
        "scripts/settings/equipment/item_master_list_weapon_skins.lua",
        "scripts/settings/equipment/weapon_skins.lua",
        "scripts/settings/equipment/weapon_skins_anvil.lua",
        "scripts/settings/equipment/weapon_skins_lake.lua",
        "scripts/settings/equipment/weapon_skins_morris.lua",
        "scripts/settings/equipment/weapon_skins_paperweight.lua",
        "scripts/settings/equipment/weapon_skins_scorpion.lua",
    }
    local function exists(path)
        local file = io.open(path, "rb")
        if not file then return false end
        file:close()
        return true
    end
    H.test_if(exists(source_root .. "/" .. manifest[1]) and exists(source_root .. "/" .. manifest[#manifest]),
        "#1567 optional decompile scan finds only the four cited misspelled description rows", function()
            local keys, misspelled = {}, {}
            for _, relative in ipairs(manifest) do
                local path = source_root .. "/" .. relative
                H.truthy(exists(path), "manifest file present: " .. relative)
                local line_number = 0
                for line in (read(path) .. "\n"):gmatch("(.-)\n") do
                    line_number = line_number + 1
                    local key = line:match('description = "([^"]+)"')
                    if key then
                        keys[key] = true
                        local spelled = key:find("description", 1, true) ~= nil
                        local near_miss = key:find("desc", 1, true) ~= nil and not key:match("_desc$")
                        if not spelled and near_miss then
                            misspelled[#misspelled + 1] = { relative, line_number, key }
                        end
                    end
                end
            end
            H.deep_equal(misspelled, {
                { "scripts/settings/dlcs/versus_rewards/item_master_list_versus_rewards.lua", 1653, shyish_typo },
                { "scripts/settings/dlcs/versus_rewards/weapon_skins_versus_rewards.lua", 1186, shyish_typo },
                { "scripts/settings/equipment/weapon_skins_morris.lua", 573, weave_typo },
                { "scripts/settings/equipment/weapon_skins_morris.lua", 588, weave_typo },
            })
            for typo, candidates in pairs(Parity.VANILLA_ALIASES) do
                H.truthy(keys[typo], "alias covers a live vanilla key: " .. typo)
                H.truthy(keys[candidates[#candidates]], "last sibling exists in vanilla: " .. candidates[#candidates])
            end
            H.equal(keys[shyish_corrected], nil, "the corrected Shyish spelling is absent from the decompile")
        end, "optional decompiled vanilla source unavailable")
end
