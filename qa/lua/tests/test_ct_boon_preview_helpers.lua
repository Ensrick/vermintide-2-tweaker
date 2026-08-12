return function(H, repo_root)
    local CTSource = dofile(repo_root .. "/qa/lua/ct_source.lua")
    local root = repo_root
        .. "/chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/"

local function read(name)
        if tostring(name):find("chaos_wastes_tweaker_dev.lua", 1, true) then
            return CTSource.expanded(repo_root)
        end
        local file = assert(io.open(root .. name, "rb"))
        local source = file:read("*a")
        file:close()
        return source
    end

    local function count_plain(source, needle)
        local count, cursor = 0, 1
        while true do
            local at = source:find(needle, cursor, true)
            if not at then return count end
            count = count + 1
            cursor = at + #needle
        end
    end

    local entry = read("chaos_wastes_tweaker_dev.lua")
    local owner = read("_ct_boon_preview_helpers.lua")
    local helpers = {
        "_ct_preparing_cw_expedition",
        "_ct_start_boon_identity",
        "_ct_start_boon_description",
        "_ct_collect_start_boons",
        "_ct_build_boon_preview_header",
        "_ct_build_boon_preview_widgets",
    }

    H.test("ct boon-preview helper owner preserves the extracted bytes", function()
        local first = "-- TRUE while this peer's party is queued for a Chaos Wastes expedition"
        local last = "    return out\nend"
        local start_at = assert(owner:find(first, 1, true))
        local cursor, last_at = start_at, nil
        while true do
            local at = owner:find(last, cursor, true)
            if not at then break end
            last_at = at
            cursor = at + 1
        end
        local block = owner:sub(start_at, assert(last_at) + #last - 1)
        local sum, rolling = 0, 0
        for i = 1, #block do
            local byte = block:byte(i)
            sum = sum + byte
            rolling = (rolling * 131 + byte) % 2147483647
        end
        H.equal(#block, 11841)
        H.equal(sum, 949398)
        H.equal(rolling, 353894663)
    end)

    H.test("ct boon-preview helper owner has one explicit dependency and bounded ownership", function()
        H.equal(count_plain(owner, "local mod = assert(ctx.mod,"), 1)
        H.equal(count_plain(owner, "ctx."), 1)
        for _, name in ipairs(helpers) do
            local needle = "function mod." .. name .. "("
            H.equal(count_plain(owner, needle), 1, name .. " owner cardinality")
            H.equal(count_plain(entry, needle), 0, name .. " must leave the entry")
        end
        H.equal(count_plain(owner, "mod:hook"), 0)
        H.equal(count_plain(owner, "mod:command"), 0)
        H.equal(count_plain(owner, "network_register"), 0)
        H.equal(count_plain(owner, "mod.on_"), 0)
        H.equal(count_plain(owner, "mod.update ="), 0)
    end)

    H.test("ct boon-preview helper owner loads once at the safe manifest sub-boundary", function()
        -- #1159: the hold-Tab panel (and with it this helper's load site and the
        -- hooks that consume it) moved into _ct_tab_panel_owner.lua. The ordering
        -- contract is unchanged and the needles are byte-identical; the file they
        -- are read from is now the panel owner.
        local panel = read("_ct_tab_panel_owner.lua")
        local needle = "scripts/mods/chaos_wastes_tweaker_dev/_ct_boon_preview_helpers"
        H.equal(count_plain(panel, needle), 1)
        H.equal(count_plain(entry, needle), 0,
            "the helper must no longer load from the entry")
        local runtime_at = assert(panel:find(
            "scripts/mods/chaos_wastes_tweaker_dev/_ct_boon_preview_runtime", 1, true))
        local owner_at = assert(panel:find(needle, 1, true))
        local setup_at = assert(panel:find(
            'mod:hook_safe("IngamePlayerListUI", "_setup_deed_reward_data"', 1, true))
        H.truthy(runtime_at < owner_at, "tooltip policy/runtime must exist before helper install")
        H.truthy(owner_at < setup_at, "helpers must install before the panel hook consumes them")
        H.equal(count_plain(panel,
            'mod:hook_safe("IngamePlayerListUI", "_draw"'), 1,
            "the shared #461/#533 draw seam must remain singleton-owned in the panel owner")
        H.equal(count_plain(entry,
            'mod:hook_safe("IngamePlayerListUI", "_draw"'), 0,
            "the entry must not keep a shadowing copy of the shared draw seam")
        H.equal(count_plain(owner, "_ct_deus_collectibles"), 0,
            "the helper owner must not absorb the cross-feature draw seam")
    end)

    H.test("ct boon-preview helpers preserve bounded engine-free behavior and clean globals", function()
        local names = {
            "Managers", "DeusPowerUpsArray", "DeusPowerUpTemplates",
            "DeusPowerUpUtils", "UIWidget", "UIWidgets",
        }
        local saved = {}
        for _, name in ipairs(names) do
            saved[name] = { present = rawget(_G, name) ~= nil, value = rawget(_G, name) }
        end

        local ok, err = xpcall(function()
            local lobby = {
                lobby_data = function(_, key)
                    if key == "mechanism" then return "deus" end
                    if key == "matchmaking" then return "true" end
                end,
            }
            local player = {
                profile_index = function() return 1 end,
                career_index = function() return 2 end,
            }
            Managers = {
                matchmaking = { _state = { NAME = "MatchmakingStateIdle" }, lobby = lobby },
                player = { local_player = function() return player end },
            }
            DeusPowerUpsArray = {
                { name = "zeta", rarity = "rare" },
                { name = "alpha", rarity = "common" },
            }
            DeusPowerUpTemplates = {
                zeta = { icon = "icon_zeta" },
                alpha = { icon = "icon_alpha" },
            }
            DeusPowerUpUtils = {}
            UIWidget = { init = function(definition) return definition end }
            UIWidgets = {
                create_simple_text = function(text, scenegraph_id)
                    return { scenegraph_id = scenegraph_id, content = { text = text } }
                end,
            }

            local mod = {
                _ct_boon_preview_tooltip = {
                    resolve_description = function(args)
                        return "Description " .. args.instance.name
                    end,
                },
                _ct_boon_display_name = function(name)
                    return name == "alpha" and "Alpha" or "Zeta"
                end,
                _ct_effective_setting = function() return true end,
                _ct_is_modded_power_up = function(name) return name == "zeta" end,
                get = function() return true end,
                localize = function(_, key) return key end,
            }
            local installer = assert(loadfile(root .. "_ct_boon_preview_helpers.lua"))()
            installer({ mod = mod })

            H.truthy(mod._ct_preparing_cw_expedition())
            local boons = mod._ct_collect_start_boons()
            H.equal(#boons, 2)
            H.equal(boons[1].name, "alpha")
            H.equal(boons[1].description, "Description alpha")
            H.equal(boons[2].name, "zeta")
            H.equal(boons[2].modded, true)
            local header = mod._ct_build_boon_preview_header("Starting Boons")
            H.equal(header.scenegraph_id, "reward_divider")
            local widgets = mod._ct_build_boon_preview_widgets(boons)
            H.equal(#widgets, 4)
            H.equal(widgets[1]._ct_boon_tooltip_data, boons[1])
        end, debug.traceback)

        for _, name in ipairs(names) do
            local prior = saved[name]
            rawset(_G, name, prior.present and prior.value or nil)
        end
        if not ok then error(err, 0) end
        for _, name in ipairs(names) do
            H.equal(rawget(_G, name), saved[name].present and saved[name].value or nil,
                name .. " global must be restored")
        end
    end)
end
