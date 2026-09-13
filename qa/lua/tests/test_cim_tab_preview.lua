return function(H, repo_root)
    local core = dofile(repo_root
        .. "/crafting_in_modded_dev/scripts/mods/crafting_in_modded_dev/_cim_tab_preview_core.lua")

    local function read_all(path)
        local file = assert(io.open(path, "rb"))
        local source = file:read("*a")
        file:close()
        return source
    end

    H.test("CIM Tab preview prefers exact live equipment skin icon", function()
        local equipment = { slots = { slot_melee = { skin = "skin_gold" } } }
        local skins = { skin_gold = { inventory_icon = "gold_icon" } }
        local authoritative, skin, icon, reason = core.resolve(
            {}, equipment, "slot_melee", skins)
        H.truthy(authoritative)
        H.equal(skin, "skin_gold")
        H.equal(icon, "gold_icon")
        H.equal(reason, "exact_skin")
    end)

    H.test("CIM Tab preview recognizes authoritative default skin", function()
        local authoritative, skin, icon, reason = core.resolve(
            {}, { slots = { slot_ranged = { skin = "n/a" } } }, "slot_ranged", {})
        H.truthy(authoritative)
        H.equal(skin, nil)
        H.equal(icon, nil)
        H.equal(reason, "default_skin")
    end)

    H.test("CIM Tab preview fails closed without exact icon identity", function()
        local authoritative, skin, icon, reason = core.resolve(
            {}, { slots = { slot_melee = { skin = "missing_skin" } } }, "slot_melee", {})
        H.equal(authoritative, false)
        H.equal(skin, "missing_skin")
        H.equal(icon, nil)
        H.equal(reason, "skin_icon_unavailable")
    end)

    H.test("CIM #598 keeps safe rarity metadata separate from custom resources", function()
        H.equal(core.resolve_rarity("unique", false, true), "unique")
        H.equal(core.resolve_rarity("unique", true, true), "modded")
        H.equal(core.resolve_rarity("unique", true, false), "unique")
        H.equal(core.resolve_rarity("modded", true, false), "unique")
        H.equal(core.resolve_rarity("modded", false, false), "modded")
        H.equal(core.resolve_rarity("modded", true, nil), "modded")

        local ok, skin, icon, reason = core.resolve({},
            { slots = { slot_melee = { skin = "custom_skin" } } }, "slot_melee",
            { custom_skin = { inventory_icon = "package_local_icon" } },
            function() return false end)
        H.equal(ok, false)
        H.equal(skin, "custom_skin")
        H.equal(icon, nil)
        H.equal(reason, "skin_icon_resource_unavailable")
    end)

    H.test("CIM #598/#921 converges owner and peer rarity state", function()
        local source = read_all(repo_root
            .. "/crafting_in_modded_dev/scripts/mods/crafting_in_modded_dev/_cim_loadout_wire_owner.lua")
        H.truthy(source:find("slot_state[slot_name] = is_modded", 1, true),
            "slot state no longer retains explicit false")
        H.truthy(source:find("slot_state[slot_name] == nil", 1, true),
            "loadout consumer no longer distinguishes false from absence")
        H.truthy(source:find('is_modded, "sender")', 1, true),
            "sender-local rarity metadata priming is missing")
        H.equal(source:find('network_send, mod, "cim_modded_slot",\n                "everyone"', 1, true), nil,
            "custom side-channel must not be broadened to an unsupported recipient")

        local preview_source = read_all(repo_root
            .. "/crafting_in_modded_dev/scripts/mods/crafting_in_modded_dev/_cim_tab_preview.lua")
        H.truthy(preview_source:find('content[slot_name .. "_rarity_texture"]',
            1, true) ~= nil)
        H.truthy(preview_source:find("Core.resolve_rarity(item.rarity, true, is_modded)",
            1, true) ~= nil)
    end)

    H.test("CIM Tab does not clobber Cosmetics component presentation", function()
        local icon, name, source = core.choose_presentation("primary_icon", {
            icon = "shield_icon",
            display_name = "combined_name_key",
        })
        H.equal(icon, "shield_icon")
        H.equal(name, "combined_name_key")
        H.equal(source, "cosmetics_components")

        icon, name, source = core.choose_presentation("primary_icon", nil)
        H.equal(icon, "primary_icon")
        H.equal(name, nil)
        H.equal(source, "primary_skin")
    end)

    -- Load the real adapter and invoke the callback captured from its sole
    -- installed hook. These are ordinary table/API-boundary fixtures, not a
    -- copied implementation of the presentation or ownership policy.
    local function adapter_fixture()
        local f = { hooks = {}, checks = {}, logs = {}, reads = 0, sends = 0 }
        f.unit = {}
        f.item = { backend_id = "owned-relic", rarity = "cursed", key = "woc_blightreaper" }
        f.items = { [f.item.backend_id] = f.item }
        f.equipped_id = f.item.backend_id
        f.equipment = { slots = { slot_melee = {
            item_data = { backend_id = f.item.backend_id, rarity = "promo", name = "es_1h_sword" },
            skin = "n/a",
        } } }
        f.inventory = { _career_name = "es_mercenary" }
        function f.inventory:equipment() return f.equipment end
        f.player = { player_unit = f.unit, local_player = true, bot_player = false }
        function f.player:unique_id() return "local-human" end
        f.local_player = f.player
        f.unit_owner = f.player
        f.wire = { rarity = "promo", key = "es_1h_sword", data = { rarity = "unique" } }
        f.loadouts = { ["local-human"] = { slot_melee = f.wire } }
        f.content = { slot_melee_rarity_texture = "icon_bg_promo", slot_melee = "vanilla-icon" }
        f.ui = { _players = { { player = f.player, peer_id = "peer-a" } },
            _player_list_widgets = { { content = f.content } } }
        f.manager = {}
        function f.manager:player_loadouts() return f.loadouts end
        function f.manager:local_player() return f.local_player end
        function f.manager:owner(unit)
            return unit == f.unit and f.unit_owner or nil
        end
        f.owner = {}
        function f.owner:get_loadout_item_id(career, slot, is_bot)
            H.equal(career, "es_mercenary")
            H.equal(is_bot, false)
            return slot == "slot_melee" and f.equipped_id or nil
        end
        function f.owner:get_item_from_id(id)
            f.reads = f.reads + 1
            return f.items[id]
        end
        f.current_owner = f.owner
        f.backend = {}
        function f.backend:get_loadout_interface_by_slot() return f.current_owner end
        function f.backend:get_interface(name)
            H.equal(name, "items")
            return f.owner
        end
        f.woc = { enabled = true }
        function f.woc:is_enabled() return self.enabled end
        f.mod = { _cim_modded_slot_state = { ["local-human"] = { slot_melee = false } } }
        function f.mod:dofile(path)
            H.equal(path, "scripts/mods/crafting_in_modded_dev/_cim_tab_preview_core")
            return core
        end
        function f.mod:hook_safe(class, method, callback)
            f.hooks[#f.hooks + 1] = { class, method, callback }
        end
        function f.mod:network_send() f.sends = f.sends + 1 end
        function f.mod._cim_rt_register(name, callback) f.checks[name] = callback end
        f.env = setmetatable({
            get_mod = function(name)
                if name == "cim_dev" then return f.mod end
                if name == "WOC" then return f.woc end
            end,
            Managers = { player = f.manager, backend = f.backend },
            ALIVE = { [f.unit] = true },
            ScriptUnit = { has_extension = function(unit, extension)
                H.equal(unit, f.unit)
                H.equal(extension, "inventory_system")
                return f.inventory
            end },
            WeaponSkins = { skins = {} },
            UISettings = { item_rarity_textures = {
                promo = "icon_bg_promo", unique = "icon_bg_unique", modded = "icon_bg_modded",
                common = "icon_bg_common", cursed = "icon_bg_cursed",
            } },
            UIAtlasHelper = { has_texture_by_name = function(texture)
                return texture == "icon_bg_cursed"
            end },
            UIUtils = { get_ui_information_from_item = function() return "vanilla-icon", "name" end },
            printf = function(fmt, ...) f.logs[#f.logs + 1] = string.format(fmt, ...) end,
        }, { __index = _G })
        local chunk = assert(loadfile(repo_root
            .. "/crafting_in_modded_dev/scripts/mods/crafting_in_modded_dev/_cim_tab_preview.lua"))
        setfenv(chunk, f.env)
        chunk()
        H.equal(#f.hooks, 1, "Tab adapter must retain exactly one hook")
        H.equal(f.hooks[1][1], "IngamePlayerListUI")
        H.equal(f.hooks[1][2], "_update_dynamic_widget_information")
        function f:invoke() return self.hooks[1][3](self.ui) end
        return f
    end

    local function copy(value)
        if type(value) ~= "table" then return value end
        local result = {}
        for key, child in pairs(value) do result[key] = copy(child) end
        return result
    end

    H.test("issue598_local_cursed_frame_uses_exact_current_instance", function()
        local f = adapter_fixture()
        local wire, items, equipment, metadata = copy(f.loadouts), copy(f.items),
            copy(f.equipment), copy(f.mod._cim_modded_slot_state)
        f:invoke()
        H.equal(f.content.slot_melee_rarity_texture, "icon_bg_cursed", "first installed-hook refresh")
        H.equal(f.reads, 1)
        H.equal(f.sends, 0)
        H.deep_equal(f.loadouts, wire, "Cursed must not enter the shared loadout row")
        H.deep_equal(f.items, items, "backend instance mutated")
        H.deep_equal(f.equipment, equipment, "live equipment mutated")
        H.deep_equal(f.mod._cim_modded_slot_state, metadata, "wire metadata mutated")
        H.truthy(f.logs[1]:find("retained=icon_bg_cursed", 1, true))
        H.equal(f.checks.issue598_owner_cursed_frame_is_widget_only(), nil)
    end)

    H.test("issue598_local_frame_tracks_modded_cursed_ordinary_swaps", function()
        local f = adapter_fixture()
        f.item.rarity = "modded"
        f.mod._cim_modded_slot_state["local-human"].slot_melee = true
        f.wire.rarity = "unique"
        f:invoke()
        H.equal(f.content.slot_melee_rarity_texture, "icon_bg_modded")
        f.item.rarity = "cursed"
        f.mod._cim_modded_slot_state["local-human"].slot_melee = false
        f.wire.rarity = "promo"
        f:invoke()
        H.equal(f.content.slot_melee_rarity_texture, "icon_bg_cursed")
        f.item = { backend_id = "ordinary-copy", rarity = "common" }
        f.items[f.item.backend_id] = f.item
        f.equipped_id = f.item.backend_id
        f.equipment.slots.slot_melee.item_data.backend_id = f.item.backend_id
        f.wire.rarity = "common"
        f:invoke()
        H.equal(f.content.slot_melee_rarity_texture, "icon_bg_common")
        H.equal(f.sends, 0)
    end)

    H.test("issue598_owner_frame_reacquires_after_respawn_and_transition", function()
        local f = adapter_fixture()
        f:invoke()
        f.env.ALIVE[f.unit] = false
        f:invoke() -- Vanilla can skip its dead row, leaving our last value behind.
        H.equal(f.content.slot_melee_rarity_texture, "icon_bg_promo")
        local old_unit = f.unit
        f.unit = {}
        f.player.player_unit = f.unit
        f.env.ALIVE[f.unit] = true
        f.equipment = { slots = { slot_melee = {
            item_data = { backend_id = "owned-relic" }, skin = "n/a",
        } } }
        f:invoke()
        H.equal(f.content.slot_melee_rarity_texture, "icon_bg_cursed")
        H.equal(f.env.ALIVE[old_unit], false)
        f.env.Managers.player = nil
        f:invoke()
        H.equal(f.content.slot_melee_rarity_texture, "icon_bg_promo")
        f.env.Managers.player = f.manager
        f:invoke()
        H.equal(f.content.slot_melee_rarity_texture, "icon_bg_cursed")
        local old_content = f.content
        f.content = { slot_melee_rarity_texture = "icon_bg_promo" }
        f.ui._player_list_widgets[1].content = f.content
        f:invoke()
        H.equal(old_content.slot_melee_rarity_texture, "icon_bg_promo")
        H.equal(f.content.slot_melee_rarity_texture, "icon_bg_cursed")
    end)

    H.test("issue598_local_rarity_unknown_fails_closed", function()
        local cases = {
            { "missing provider", function(f) f.woc = nil end },
            { "disabled provider", function(f) f.woc.enabled = false end },
            { "provider without capability", function(f) f.woc.is_enabled = nil end },
            { "missing texture", function(f) f.env.UISettings.item_rarity_textures.cursed = nil end },
            { "nonresident texture", function(f) f.env.UIAtlasHelper.has_texture_by_name = function() return false end end },
            { "missing renderer", function(f) f.env.UIAtlasHelper = false end },
            { "missing instance", function(f) f.items["owned-relic"] = nil end },
            { "mismatched instance", function(f) f.item.backend_id = "other-copy" end },
            { "missing current slot", function(f) f.equipment.slots.slot_melee = nil end },
            { "missing equipment", function(f) f.equipment = nil end },
            { "missing exact id", function(f) f.equipment.slots.slot_melee.item_data.backend_id = nil end },
            { "definition rarity is not instance rarity", function(f) f.item.rarity = nil; f.item.data = { rarity = "cursed" } end },
            { "loadout changed before equip", function(f) f.equipped_id = "new-copy" end },
            { "unknown unit owner", function(f) f.unit_owner = nil end },
            { "other local player", function(f) f.local_player = {} end },
            { "missing backend", function(f) f.env.Managers.backend = nil end },
            { "missing owner", function(f) f.current_owner = nil end },
            { "missing career", function(f) f.inventory._career_name = nil end },
            { "missing local marker", function(f) f.player.local_player = nil end },
            { "missing extension provider", function(f) f.env.ScriptUnit = false end },
            { "inherited rarity is not instance rarity", function(f)
                f.item.rarity = nil
                setmetatable(f.item, { __index = { rarity = "cursed" } })
            end },
            { "inherited texture is not registered", function(f)
                f.env.UISettings.item_rarity_textures.cursed = nil
                setmetatable(f.env.UISettings.item_rarity_textures,
                    { __index = { cursed = "icon_bg_cursed" } })
            end },
        }
        for _, case in ipairs(cases) do
            local f = adapter_fixture()
            f:invoke()
            case[2](f)
            f:invoke()
            H.equal(f.content.slot_melee_rarity_texture, "icon_bg_promo", case[1])
            H.equal(f.sends, 0, case[1])
        end
    end)

    H.test("issue598_owner_frame_rechecks_career_and_each_weapon_slot", function()
        local f = adapter_fixture()
        f.equipment.slots.slot_ranged = {
            item_data = { backend_id = "ordinary-ranged" }, skin = "n/a",
        }
        f.items["ordinary-ranged"] = { backend_id = "ordinary-ranged", rarity = "common" }
        f.loadouts["local-human"].slot_ranged = { rarity = "common" }
        f.mod._cim_modded_slot_state["local-human"].slot_ranged = false
        function f.owner:get_loadout_item_id(career, slot, is_bot)
            H.equal(career, f.inventory._career_name)
            H.equal(is_bot, false)
            return slot == "slot_melee" and f.equipped_id or "ordinary-ranged"
        end
        f:invoke()
        H.equal(f.content.slot_melee_rarity_texture, "icon_bg_cursed")
        H.equal(f.content.slot_ranged_rarity_texture, "icon_bg_common")
        f.inventory._career_name = "es_knight"
        f.equipped_id = "new-career-relic"
        f.items[f.equipped_id] = { backend_id = f.equipped_id, rarity = "cursed" }
        f:invoke() -- Career/loadout replacement must not bless the old live instance.
        H.equal(f.content.slot_melee_rarity_texture, "icon_bg_promo")
        f.equipment.slots.slot_melee.item_data.backend_id = f.equipped_id
        f:invoke()
        H.equal(f.content.slot_melee_rarity_texture, "icon_bg_cursed")
        H.equal(f.content.slot_ranged_rarity_texture, "icon_bg_common")
        H.equal(f.sends, 0)
    end)

    H.test("issue598_retired_rows_and_missing_loadout_clear_owner_frame", function()
        for _, plant in ipairs({
            function(f) f.ui._players = nil end,
            function(f) f.ui._players = {} end,
            function(f) f.ui._players[1].player = nil end,
            function(f) f.loadouts = nil end,
            function(f) f.loadouts = {} end,
            function(f) f.ui._player_list_widgets = nil end,
            function(f) f.ui._player_list_widgets[1].content = nil end,
        }) do
            local f = adapter_fixture()
            f:invoke()
            plant(f)
            f:invoke()
            H.equal(f.content.slot_melee_rarity_texture, "icon_bg_promo")
            H.equal(f.item.rarity, "cursed")
            H.equal(f.wire.rarity, "promo")
        end
    end)

    H.test("issue598_foreign_owner_never_reads_items_by_guessed_id", function()
        local f = adapter_fixture()
        f:invoke()
        f.reads = 0
        f.current_owner = { get_item_from_id = function() error("foreign reader must not run") end }
        f:invoke()
        H.equal(f.reads, 0, "items lookup crossed the actual current owner boundary")
        H.equal(f.content.slot_melee_rarity_texture, "icon_bg_promo")
    end)

    H.test("issue598_throwing_contexts_clear_previous_custom_frame", function()
        local function throws() error("planted boundary failure") end
        local cases = {
            function(f) f.manager.local_player = throws end,
            function(f) f.manager.owner = throws end,
            function(f) f.manager.player_loadouts = throws end,
            function(f) f.backend.get_loadout_interface_by_slot = throws end,
            function(f) f.backend.get_interface = throws end,
            function(f) f.owner.get_loadout_item_id = throws end,
            function(f) f.owner.get_item_from_id = throws end,
            function(f) f.woc.is_enabled = throws end,
            function(f) f.env.UIAtlasHelper.has_texture_by_name = throws end,
            function(f) f.env.ScriptUnit.has_extension = throws end,
            function(f) f.inventory.equipment = throws end,
            function(f) f.player.unique_id = throws end,
        }
        for index, plant in ipairs(cases) do
            local f = adapter_fixture()
            f:invoke()
            plant(f)
            local ok, err = pcall(f.invoke, f)
            H.truthy(ok, "throwing case " .. index .. ": " .. tostring(err))
            H.equal(f.content.slot_melee_rarity_texture, "icon_bg_promo", "throwing case " .. index)
            H.equal(f.item.rarity, "cursed")
            H.equal(f.wire.rarity, "promo")
        end
    end)

    H.test("issue598_remote_rows_preserve_existing_wire_policy", function()
        for _, kind in ipairs({ "remote", "bot", "missing-woc" }) do
            local f = adapter_fixture()
            if kind == "remote" then f.player.local_player = false; f.local_player = {} end
            if kind == "bot" then f.player.bot_player = true end
            if kind == "missing-woc" then f.woc = nil end
            local wire, items = copy(f.loadouts), copy(f.items)
            f:invoke()
            H.equal(f.content.slot_melee_rarity_texture, "icon_bg_promo", kind)
            H.equal(f.reads, 0, kind)
            H.equal(f.sends, 0, kind)
            H.deep_equal(f.loadouts, wire, kind)
            H.deep_equal(f.items, items, kind)
            f.mod._cim_modded_slot_state["local-human"].slot_melee = true
            f.wire.rarity = "unique"
            f:invoke()
            H.equal(f.content.slot_melee_rarity_texture, "icon_bg_modded", kind .. " existing true")
            f.mod._cim_modded_slot_state["local-human"].slot_melee = false
            f.wire.rarity = "common"
            f:invoke()
            H.equal(f.content.slot_melee_rarity_texture, "icon_bg_common", kind .. " existing false")
        end
    end)

    H.test("issue598_widget_restore_is_exact_and_does_not_clobber_later_writer", function()
        local content, previous = { slot_melee_rarity_texture = false }, {}
        core.apply_owner_frame(content, "slot_melee", "custom", previous)
        core.restore_owner_frames(content, previous)
        H.equal(content.slot_melee_rarity_texture, false)
        content.slot_melee_rarity_texture = nil
        core.apply_owner_frame(content, "slot_melee", "custom", previous)
        core.restore_owner_frames(content, previous)
        H.equal(content.slot_melee_rarity_texture, nil)
        core.apply_owner_frame(content, "slot_melee", "custom", previous)
        content.slot_melee_rarity_texture = "new-vanilla-frame"
        core.restore_owner_frames(content, previous)
        H.equal(content.slot_melee_rarity_texture, "new-vanilla-frame")
    end)

    H.test("issue598_owner_frame_receipts_are_bounded_and_not_acceptance_verdicts", function()
        local f = adapter_fixture()
        for index = 1, 70 do
            f.woc.enabled = index % 2 == 1
            f:invoke()
        end
        H.equal(#f.logs, 24)
        for _, line in ipairs(f.logs) do
            H.truthy(line:find("[cim:598] owner_frame", 1, true))
            H.equal(line:find("PASS", 1, true), nil)
        end
    end)
end
