-- Boundary tests for _cim_modded_loadout_owner.
--
-- WP-CIM-11 removed the dormant persisted modded-loadout path (capture hooks,
-- store, migration, purge, restore, live-avatar re-equip and its two commands;
-- gui_tweaker owns modded loadout persistence). What stays is live code: the
-- #562 craft auto-equip, the #1360 exact five-slot loadout primitives, the
-- `cim_craft_standard` command and the restore-callback registry that
-- cosmetics_tweaker calls (_cos_glow_cim_bridge.lua:151-158).
return function(H, repo_root)
    local root = repo_root
        .. "/crafting_in_modded_dev/scripts/mods/crafting_in_modded_dev/"

    local function read(name)
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

    local entry = read("crafting_in_modded_dev.lua")
    local owner = read("_cim_modded_loadout_owner.lua")
    local wire_owner = read("_cim_loadout_wire_owner.lua")

    local function load_owner()
        return assert(loadfile(root .. "_cim_modded_loadout_owner.lua"))()
    end

    -- A stand-in for the VMF mod object, recording everything the owner
    -- registers so cardinality can be asserted directly.
    local function fake_mod(settings)
        local m = {
            hooks = {}, commands = {}, sets = {}, echoes = {}, infos = {},
            _settings = settings or {},
        }
        function m:hook(a, b)
            self.hooks[#self.hooks + 1] = { target = type(a) == "table" and "table" or a, method = b }
        end
        function m:hook_safe(a, b)
            self.hooks[#self.hooks + 1] = { target = a, method = b, safe = true }
        end
        function m:command(name, _, fn)
            self.commands[#self.commands + 1] = name
            self["cmd_" .. name] = fn
        end
        function m:get(key) return self._settings[key] end
        function m:set(key, value) self._settings[key] = value; self.sets[key] = value end
        function m:echo(line) self.echoes[#self.echoes + 1] = tostring(line) end
        function m:info(line) self.infos[#self.infos + 1] = tostring(line) end
        return m
    end

    H.test("CIM modded-loadout owner installs exactly once at the original seam", function()
        H.equal(count_plain(entry,
            "scripts/mods/crafting_in_modded_dev/_cim_modded_loadout_owner"), 1)
        local wire_at = assert(entry:find(
            "scripts/mods/crafting_in_modded_dev/_cim_loadout_wire_owner", 1, true))
        local seam_at = assert(entry:find(
            "scripts/mods/crafting_in_modded_dev/_cim_modded_loadout_owner", 1, true))
        local athanor_at = assert(entry:find(
            "-- Athanor (Winds of Magic forge)", 1, true))
        H.truthy(wire_at < seam_at, "seam must follow the wire-safety guard")
        H.truthy(seam_at < athanor_at, "seam must precede the Athanor UI hooks")
    end)

    H.test("CIM modded-loadout owner registers no hook and only cim_craft_standard", function()
        local mod = fake_mod({ modded_loadout = { es_mercenary = { [1] = { slot_melee = "old" } } } })
        load_owner()({ mod = mod })
        H.equal(#mod.hooks, 0, "no loadout hook is installed")
        H.deep_equal(mod.commands, { "cim_craft_standard" })
        H.equal(next(mod.sets), nil, "install writes no setting")
        H.deep_equal(mod._settings.modded_loadout,
            { es_mercenary = { [1] = { slot_melee = "old" } } },
            "the saved modded_loadout setting is left as it is")
        H.equal(mod.open_standard_crafting, nil)
        mod.cmd_cim_craft_standard()
        H.truthy(mod.echoes[1] and mod.echoes[1]:find("not initialised", 1, true))
        local opened = 0
        mod.open_standard_crafting = function() opened = opened + 1 end
        mod.cmd_cim_craft_standard()
        H.equal(opened, 1, "the command dispatches to open_standard_crafting at call time")
    end)

    H.test("CIM modded-loadout owner keeps the restore-callback registry", function()
        local mod = fake_mod()
        load_owner()({ mod = mod })
        H.equal(mod._cim_register_restore_callback(function() end), true)
        H.equal(mod._cim_register_restore_callback("not a function"), false)
    end)

    H.test("CIM modded-loadout owner keeps the live auto-equip and exact-loadout surface", function()
        local mod = fake_mod()
        load_owner()({ mod = mod })
        for _, field in ipairs({
            "_cim_auto_equip_crafted_weapon", "_cim_auto_equip_slot_type",
            "_cim_snapshot_exact_loadout", "_cim_write_exact_loadout_item",
            "_cim_finalize_exact_loadout", "_cim_register_restore_callback",
        }) do
            H.equal(type(mod[field]), "function", field .. " published")
            H.equal(count_plain(entry, "mod." .. field .. " ="), 0,
                "entry must not re-publish " .. field)
        end
        H.equal(mod._cim_auto_equip_slot_type("slot_melee"), "melee")
        H.equal(mod._cim_auto_equip_slot_type("slot_ranged"), "ranged")
        H.equal(mod._cim_auto_equip_slot_type("slot_trinket_1"), nil)
        local ok, reason = mod._cim_auto_equip_crafted_weapon("es_mercenary", "slot_melee", "bid")
        H.equal(ok, false)
        H.equal(reason, "disabled", "auto-equip honours its setting")
        local snapshot, err = mod._cim_snapshot_exact_loadout(nil, {})
        H.equal(snapshot, nil)
        H.equal(err, "arguments")
        H.deep_equal({ mod._cim_write_exact_loadout_item("es_mercenary", "slot_hat", "bid", 1) },
            { false, "slot" })
        H.deep_equal({ mod._cim_finalize_exact_loadout("es_mercenary", nil) },
            { false, "assignments" })
    end)

    H.test("CIM modded-loadout owner install is idempotent", function()
        local mod = fake_mod()
        local install = load_owner()
        local first = install({ mod = mod })
        local second = install({ mod = mod })
        H.equal(first, second, "a second install returns the first exports")
        H.deep_equal(mod.commands, { "cim_craft_standard" }, "commands do not re-register")
        H.equal(#mod.hooks, 0)
        H.equal(pcall(install), false, "refuses a missing context")
        H.equal(pcall(install, {}), false, "refuses a missing mod")
    end)

    H.test("CIM dormant loadout persistence is gone from the entry and its owners", function()
        for _, needle in ipairs({
            'mod:hook_safe("BackendInterfaceItemPlayfab", "set_loadout_item"',
            'mod:hook(BU, "set_loadout_item"',
            'mod:command("cim_restore_loadout"',
            'mod:command("cim_dump_loadout"',
            "local function _modded_loadout_save()",
            "local function _modded_loadout_load()",
            "local function _migrate_modded_loadout(",
            "local function _career_value_is_flat(",
            "local function _modded_loadout_purge_stale()",
            "local function _capture_loadout_equip(",
            "local function _install_backendutils_capture()",
            "local function _reequip_live_avatar()",
            "mod._cim_clear_modded_loadout_for_bids",
            "persist_modded_loadouts",
        }) do
            H.equal(count_plain(owner, needle), 0, "owner must not keep " .. needle)
            H.equal(count_plain(entry, needle), 0, "entry must not keep " .. needle)
        end
        H.equal(count_plain(wire_owner, "persist_modded_loadouts"), 0)
        H.equal(count_plain(wire_owner, "persist_loadouts_enabled"), 0)
        for _, needle in ipairs({
            "_cim_loadout_restore_timer", "_install_backendutils_capture",
            "_restore_modded_loadout", "get_restore_modded_loadout",
            "get_modded_loadout", "set_modded_loadout", "modded_loadout_save",
            "modded_loadout_load", "_persist_loadouts_enabled",
        }) do
            H.equal(count_plain(entry, needle), 0, "entry must not keep " .. needle)
        end
    end)

    H.test("CIM modded-loadout owner leaves wire safety in its dedicated owner", function()
        -- #278/#371: sender-side rarity coercion and the modded-slot RPC are
        -- crash safety that must stay in the wire owner.
        for _, needle in ipairs({
            "local function wire_safe_rarity(rarity)",
            'mod:network_register("cim_modded_slot"',
            'mod:hook("PlayerManager", "rpc_sync_loadout_slot"',
        }) do
            H.equal(count_plain(wire_owner, needle), 1,
                "wire owner must retain " .. needle)
            H.equal(count_plain(entry, needle), 0,
                "entry must not retain " .. needle)
            H.equal(count_plain(owner, needle), 0, "owner must not absorb " .. needle)
        end
    end)

    H.test("CIM modded-loadout owner holds no Athanor view lifecycle", function()
        for _, forbidden in ipairs({
            'mod:hook("HeroView', 'mod:hook_safe("HeroView',
            'mod:hook("HeroWindow', 'mod:hook_safe("HeroWindow',
            "_unit_previewer", "shading_environment", "create_screen_gui",
            "Managers.ui", "ingame_ui", "UIWidget", "package:load",
        }) do
            H.equal(owner:find(forbidden, 1, true), nil,
                "owner must not touch " .. forbidden)
        end
        H.equal(count_plain(owner, "mod:hook"), 0)
    end)
end
