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
    local owner = read("_cim_command_owner.lua")
    local standard = read("standard_forge.lua")

    H.test("CIM-dev entry remains below its frozen decomposition ceiling", function()
        local lines = 0
        for line in entry:gmatch("[^\r\n]*") do
            if line:find("%S") then lines = lines + 1 end
        end
        H.truthy(lines <= 1433,
            "CIM-dev entry exceeded the 1433-line structural completion ceiling")
        -- The bootstrap/state/wire owner slice brought the entry under the
        -- PROJECT_STANDARDS 2.2a 1500-line completion target. Pin that target
        -- independently so a later contract edit cannot relabel regrowth.
        H.truthy(lines <= 1500,
            "CIM-dev entry crossed back over the 1500-line completion target")
    end)

    H.test("CIM-dev command owner installs exactly once at the original boundary", function()
        H.equal(count_plain(entry,
            "scripts/mods/crafting_in_modded_dev/_cim_command_owner"), 1)
        H.equal(count_plain(owner,
            "scripts/mods/crafting_in_modded_dev/_cim_bulk_cleanup_command"), 1)
        H.equal(count_plain(entry,
            "scripts/mods/crafting_in_modded_dev/_cim_bulk_cleanup_command"), 0)

        -- The persistence closures moved to _cim_modded_loadout_owner; the
        -- ordering invariant is unchanged, only its anchor. The command owner
        -- still cannot install before the store exists, because it consumes
        -- accessors the loadout owner returns.
        H.equal(count_plain(entry, "local function _modded_loadout_save()"), 0,
            "persistence closures must not survive in the entry")
        local loadout_at = assert(entry:find(
            "scripts/mods/crafting_in_modded_dev/_cim_modded_loadout_owner", 1, true))
        local owner_at = assert(entry:find(
            "scripts/mods/crafting_in_modded_dev/_cim_command_owner", 1, true))
        local regression_at = assert(entry:find(
            "scripts/mods/crafting_in_modded_dev/_cim_regression_cleanup", 1, true))
        H.truthy(loadout_at < owner_at,
            "command owner requires initialized persistence closures")
        H.truthy(owner_at < regression_at,
            "command owner must publish deletion API before regression install")
    end)

    H.test("CIM-dev command owner preserves exact registration order and cardinality", function()
        local expected = {
            "forge_dump", "forge_dump_props", "forge_dump_backend",
            "forge", "forge_trait", "forge_props", "forge_skin",
            "forge_power", "forge_cancel", "forge_confirm",
            "salvage_debug", "forge_list", "forge_delete",
        }
        local actual = {}
        for name in owner:gmatch('mod:command%\("([^"]+)"') do
            actual[#actual + 1] = name
        end
        H.equal(#actual, #expected)
        for i = 1, #expected do
            H.equal(actual[i], expected[i], "command registration " .. i)
            H.equal(count_plain(entry, 'mod:command("' .. expected[i] .. '"'), 0,
                expected[i] .. " remains duplicated in entry")
        end

        H.equal(count_plain(owner, "mod:hook"), 0)
        H.equal(count_plain(owner, "network_register"), 0)
        H.equal(count_plain(owner, "mod.on_"), 0)
        H.equal(count_plain(owner, "mod.update ="), 0)
    end)

    H.test("CIM-dev command owner executes one ordered registration plan", function()
        local install = assert(loadfile(root .. "_cim_command_owner.lua"))()
        local commands, bulk_installs = {}, 0
        local mod = {
            command = function(_, name)
                commands[#commands + 1] = name
            end,
            dofile = function(_, path)
                H.equal(path,
                    "scripts/mods/crafting_in_modded_dev/_cim_bulk_cleanup_command")
                return function(context)
                    bulk_installs = bulk_installs + 1
                    H.truthy(type(context.delete_owned_ids) == "function")
                end
            end,
        }
        local noop = function() end
        install({
            mod = mod,
            is_custom_forge_active = function() return false end,
            get_forged_weapons = function() return {} end,
            get_modded_loadout = function() return {} end,
            get_more_items_lib = function() return {} end,
            forge_inject_item = noop,
            forge_create_item = noop,
            forge_detect_mil = noop,
            forge_save = noop,
            modded_loadout_save = noop,
        })
        H.deep_equal(commands, {
            "forge_dump", "forge_dump_props", "forge_dump_backend",
            "forge", "forge_trait", "forge_props", "forge_skin",
            "forge_power", "forge_cancel", "forge_confirm",
            "salvage_debug", "forge_list", "forge_delete",
        })
        H.equal(bulk_installs, 1)
        H.truthy(type(mod._cim277_delete_owned_ids) == "function")
    end)

    H.test("CIM-dev command owner retains accessor-backed mutable state", function()
        local install_first = assert(entry:find("_install_command_owner({", 1, true))
        local install_last = assert(entry:find("\n})", install_first, true))
        local install = entry:sub(install_first, install_last + 2)
        for _, dependency in ipairs({
            "is_custom_forge_active", "get_forged_weapons",
            "get_modded_loadout", "get_more_items_lib", "forge_inject_item",
            "forge_create_item", "forge_detect_mil", "forge_save",
            "modded_loadout_save",
        }) do
            H.equal(count_plain(install, dependency .. " ="), 1,
                "entry injects " .. dependency)
            H.truthy(owner:find("ctx." .. dependency, 1, true),
                "owner consumes " .. dependency)
        end
        H.equal(count_plain(entry, "_forge_pending"), 0)
        H.truthy(owner:find("local _forge_pending = nil", 1, true))
        H.truthy(owner:find("_get_forged_weapons()", 1, true))
        H.truthy(owner:find("_get_modded_loadout()", 1, true))
    end)

    H.test("CIM-dev exact-owner deletion surface remains flat and single-owned", function()
        H.equal(count_plain(owner,
            "mod._cim277_delete_owned_ids = function"), 1)
        H.equal(count_plain(entry,
            "mod._cim277_delete_owned_ids = function"), 0)
        H.equal(count_plain(standard,
            "delete_owned_ids = mod._cim277_delete_owned_ids"), 1)
        H.truthy(owner:find("deletion.execute({", 1, true))
        H.truthy(owner:find("inventory_items = mirror._inventory_items", 1, true))
        H.truthy(owner:find("persist_loadouts = _modded_loadout_save", 1, true))
        H.equal(owner:find("items:_refresh()", 1, true), nil)
    end)
end
