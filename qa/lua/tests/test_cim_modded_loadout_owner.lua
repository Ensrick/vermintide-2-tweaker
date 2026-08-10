-- Boundary tests for _cim_modded_loadout_owner (#1159 cim_dev decomposition).
--
-- The owner is a behavior-neutral move of the persisted modded-loadout path out
-- of the cim_dev entry. These tests lock the three things a structural move can
-- silently break: the entry seam (one install, correct order, nothing left
-- behind), the injected-accessor contract (the forge store is READ LIVE, never
-- snapshotted), and the exported surface the entry re-binds.
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

    local function load_owner()
        return assert(loadfile(root .. "_cim_modded_loadout_owner.lua"))()
    end

    -- A stand-in for the VMF mod object, recording everything the owner
    -- registers so cardinality and order can be asserted directly.
    local function fake_mod(settings)
        local m = {
            hooks = {}, commands = {}, sets = {}, echoes = {}, infos = {},
            _settings = settings or {},
        }
        function m:hook(a, b, c)
            if type(a) == "table" then
                self.hooks[#self.hooks + 1] = { target = "table", method = b, kind = "hook" }
            else
                self.hooks[#self.hooks + 1] = { target = a, method = b, kind = "hook" }
            end
            return c
        end
        function m:hook_safe(a, b, c)
            self.hooks[#self.hooks + 1] = { target = a, method = b, kind = "hook_safe" }
            return c
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

    local function install_owner(mod, forged)
        local install = load_owner()
        return install({
            mod = mod,
            persist_loadouts_enabled = function() return false end,
            get_forged_weapons = function() return forged end,
        })
    end

    H.test("CIM modded-loadout owner installs exactly once at the original seam", function()
        H.equal(count_plain(entry,
            "scripts/mods/crafting_in_modded_dev/_cim_modded_loadout_owner"), 1)

        -- The seam sits between the #278/#371 wire-safety guard (which stays in
        -- the entry) and the Athanor UI hook section, exactly where the moved
        -- block used to execute.
        local wire_at = assert(entry:find(
            "mod._cim_rpc_loadout_guard_installed = true", 1, true))
        local seam_at = assert(entry:find(
            "scripts/mods/crafting_in_modded_dev/_cim_modded_loadout_owner", 1, true))
        local athanor_at = assert(entry:find(
            "-- Athanor (Winds of Magic forge)", 1, true))
        H.truthy(wire_at < seam_at, "seam must follow the wire-safety guard")
        H.truthy(seam_at < athanor_at, "seam must precede the Athanor UI hooks")
    end)

    H.test("CIM modded-loadout owner is the sole home of the capture hooks and commands", function()
        for _, needle in ipairs({
            'mod:hook_safe("BackendInterfaceItemPlayfab", "set_loadout_item"',
            'mod:hook(BU, "set_loadout_item"',
            'mod:command("cim_restore_loadout"',
            'mod:command("cim_craft_standard"',
            'mod:command("cim_dump_loadout"',
            "local function _modded_loadout_save()",
            "local function _modded_loadout_load()",
            "local function _modded_loadout_purge_stale()",
            "local function _capture_loadout_equip(",
            "local function _install_backendutils_capture()",
            "local function _auto_equip_crafted_weapon(",
        }) do
            H.equal(count_plain(owner, needle), 1, "owner must own " .. needle)
            H.equal(count_plain(entry, needle), 0, "entry must not retain " .. needle)
        end
    end)

    H.test("CIM modded-loadout owner keeps the public flat surface unwidened", function()
        for _, field in ipairs({
            "mod._cim_clear_modded_loadout_for_bids",
            "mod._cim_clear_modded_loadout_for_bid",
            "mod._cim_register_restore_callback",
            "mod._cim_auto_equip_crafted_weapon",
            "mod._cim_auto_equip_slot_type",
        }) do
            H.truthy(owner:find(field .. " =", 1, true),
                "owner must publish " .. field)
            H.equal(count_plain(entry, field .. " ="), 0,
                "entry must not re-publish " .. field)
        end
        -- The forge store stays private: it reaches the owner as an injected
        -- accessor, never as a new mod._cim_* field.
        H.equal(count_plain(entry, "mod._cim_get_forged_weapons"), 0)
        H.equal(count_plain(owner, "mod._cim_get_forged_weapons"), 0)
    end)

    H.test("CIM modded-loadout owner reads the forge store live, never snapshotted", function()
        -- _forge_load rebinds _forged_weapons to a FRESH table on every backend
        -- _create_interfaces pass. A snapshot would make the stale purge treat
        -- every live craft as unbacked and delete the player's saved loadout.
        -- One call site in the purge, one in the reload-safe indirection.
        H.equal(count_plain(owner, "_get_forged_weapons()"), 2)
        H.equal(count_plain(owner, "local _forged_weapons"), 0)
        H.truthy(owner:find("state.get_forged_weapons = assert(ctx.get_forged_weapons", 1, true))
        H.truthy(entry:find("get_forged_weapons = function() return _forged_weapons end", 1, true))

        local mod = fake_mod({ modded_loadout = {
            es_mercenary = { [1] = { slot_melee = "gone", slot_ranged = "cwv_keep" } },
        } })
        local forged = {}
        local exports = install_owner(mod, forged)
        H.equal(type(exports.restore_modded_loadout), "function")

        -- Rebind the store the way _forge_load does, AFTER install.
        forged = { gone = { key = "es_1h_sword" } }
        local store = exports.get_modded_loadout()
        H.equal(store.es_mercenary[1].slot_melee, "gone")

        -- Reach the purge through the public clear path's sibling: run the
        -- exported loader then assert the accessor sees the rebound table.
        H.equal(count_plain(owner, "if _get_forged_weapons()[bid] then keep = true"), 1)
    end)

    H.test("CIM modded-loadout owner registers its commands in the original order", function()
        local mod = fake_mod()
        install_owner(mod, {})
        H.deep_equal(mod.commands, {
            "cim_restore_loadout", "cim_craft_standard", "cim_dump_loadout",
        })
    end)

    H.test("CIM modded-loadout owner registers exactly one eager capture hook", function()
        local mod = fake_mod()
        install_owner(mod, {})
        H.equal(#mod.hooks, 1, "only the interface capture installs at load")
        H.equal(mod.hooks[1].target, "BackendInterfaceItemPlayfab")
        H.equal(mod.hooks[1].method, "set_loadout_item")
        H.equal(mod.hooks[1].kind, "hook_safe")
        -- The BackendUtils table hook is deferred until the backend (and the
        -- Loremaster's Armoury bridge) exist; it must not fire at install.
        H.equal(mod._cim_backendutils_capture_installed, nil)
    end)

    H.test("CIM modded-loadout owner loads the persisted store at install time", function()
        local saved = { bw_scholar = { [2] = { slot_melee = "cim_1" } } }
        local mod = fake_mod({ modded_loadout = saved })
        local exports = install_owner(mod, {})
        H.equal(exports.get_modded_loadout(), saved,
            "install must adopt the persisted table, as the entry did at load")
    end)

    H.test("CIM modded-loadout owner round-trips the regression store swap", function()
        local mod = fake_mod({ modded_loadout = { a = { [1] = { slot_melee = "x" } } } })
        local exports = install_owner(mod, {})
        -- This is the exact sequence _cim_regression_checks drives.
        exports.set_modded_loadout({})
        H.deep_equal(exports.get_modded_loadout(), {})
        exports.modded_loadout_load()
        H.equal(exports.get_modded_loadout().a[1].slot_melee, "x",
            "reload must repopulate the same local the getter returns")
        -- save writes through the VMF setting the loader reads.
        exports.set_modded_loadout({ b = { [1] = { slot_ranged = "y" } } })
        exports.modded_loadout_save()
        H.equal(mod.sets.modded_loadout.b[1].slot_ranged, "y")
    end)

    H.test("CIM modded-loadout owner install is idempotent", function()
        local mod = fake_mod()
        local install = load_owner()
        local ctx = {
            mod = mod,
            persist_loadouts_enabled = function() return false end,
            get_forged_weapons = function() return {} end,
        }
        local first = install(ctx)
        local second = install(ctx)
        H.equal(first, second, "a second install must return the first exports")
        H.equal(#mod.commands, 3, "commands must not re-register")
        H.equal(#mod.hooks, 1, "hooks must not re-register")
    end)

    H.test("CIM modded-loadout owner rebinds injected resolvers across a reload", function()
        -- A dev reload re-executes the entry, which builds fresh closures over
        -- the reloaded _forged_weapons. The guard must not pin the first
        -- install's resolvers, or the stale purge reads the pre-reload store.
        local mod = fake_mod()
        local install = load_owner()
        local first_store, second_store = { a = true }, { b = true }
        local seen
        install({
            mod = mod,
            persist_loadouts_enabled = function() return false end,
            get_forged_weapons = function() seen = first_store; return first_store end,
        })
        install({
            mod = mod,
            persist_loadouts_enabled = function() return true end,
            get_forged_weapons = function() seen = second_store; return second_store end,
        })
        H.equal(mod._cim_modded_loadout_owner_state.get_forged_weapons(), second_store,
            "reload must adopt the fresh forge-store accessor")
        H.equal(mod._cim_modded_loadout_owner_state.persist_loadouts_enabled(), true,
            "reload must adopt the fresh persistence gate")
        H.equal(#mod.hooks, 1, "reload must not duplicate the capture hook")
        H.equal(#mod.commands, 3, "reload must not duplicate commands")
    end)

    H.test("CIM modded-loadout owner refuses an incomplete context", function()
        local install = load_owner()
        H.equal(pcall(install), false)
        H.equal(pcall(install, { mod = fake_mod() }), false)
        H.equal(pcall(install, {
            mod = fake_mod(), persist_loadouts_enabled = function() return false end,
        }), false)
    end)

    H.test("CIM modded-loadout owner leaves the wire-safety layer in the entry", function()
        -- #278/#371: sender-side rarity coercion and the modded-slot RPC are
        -- crash safety that must never sit behind this owner's persistence gate.
        for _, needle in ipairs({
            "local function _cim_wire_safe_rarity(rarity)",
            'mod:network_register("cim_modded_slot"',
            'mod:hook("PlayerManager", "rpc_sync_loadout_slot"',
        }) do
            H.equal(count_plain(entry, needle), 1, "entry must retain " .. needle)
            H.equal(count_plain(owner, needle), 0, "owner must not absorb " .. needle)
        end
    end)

    H.test("CIM modded-loadout owner exports every name the entry re-binds", function()
        for _, name in ipairs({
            "restore_modded_loadout", "install_backendutils_capture",
            "modded_loadout_save", "modded_loadout_load",
            "get_modded_loadout", "set_modded_loadout",
        }) do
            H.truthy(owner:find(name .. " =", 1, true),
                "owner must export " .. name)
            H.truthy(entry:find("_LOADOUT_OWNER." .. name, 1, true),
                "entry must bind " .. name)
        end
        local mod = fake_mod()
        local exports = install_owner(mod, {})
        for _, name in ipairs({
            "restore_modded_loadout", "install_backendutils_capture",
            "modded_loadout_save", "modded_loadout_load",
            "get_modded_loadout", "set_modded_loadout",
        }) do
            H.equal(type(exports[name]), "function", name .. " must be callable")
        end
    end)

    H.test("CIM modded-loadout owner keeps the entry's deferred consumers wired", function()
        -- mod.update installs the post-LA capture; _create_interfaces and the
        -- deferred timer call restore. Both still resolve entry locals.
        H.truthy(entry:find("_restore_modded_loadout = _LOADOUT_OWNER.restore_modded_loadout", 1, true))
        H.truthy(entry:find("local _install_backendutils_capture = _LOADOUT_OWNER.install_backendutils_capture", 1, true))
        H.equal(count_plain(entry, "_install_backendutils_capture()"), 1)
        H.equal(count_plain(entry,
            "local _restore_modded_loadout -- forward declaration"), 1)
        -- The late installers consume the store through the owner's accessors.
        H.equal(count_plain(entry, "get_modded_loadout = _LOADOUT_OWNER.get_modded_loadout"), 2)
        H.equal(count_plain(entry, "set_modded_loadout = _LOADOUT_OWNER.set_modded_loadout"), 1)
        H.equal(count_plain(entry, "function() return _modded_loadout end"), 0)
    end)

    H.test("CIM modded-loadout owner holds no Athanor view lifecycle", function()
        -- The on_enter crash-guard cascade, the preview world, and the widget
        -- material policy belong to the forge owners. This move must not have
        -- dragged any of it along. Assert on what the owner REGISTERS and CALLS
        -- rather than on every mention: two comments legitimately name
        -- HeroViewStateOverview, because that is the vanilla equip path the
        -- BackendUtils capture hook exists to intercept.
        for _, forbidden in ipairs({
            'mod:hook("HeroView', 'mod:hook_safe("HeroView',
            'mod:hook("HeroWindow', 'mod:hook_safe("HeroWindow',
            "_unit_previewer", "shading_environment", "create_screen_gui",
            "Managers.ui", "ingame_ui", "UIWidget", "package:load",
        }) do
            H.equal(owner:find(forbidden, 1, true), nil,
                "owner must not touch " .. forbidden)
        end
        -- Every hook it does register is a backend loadout-write chokepoint.
        H.equal(count_plain(owner, "mod:hook"), 2)
    end)
end
