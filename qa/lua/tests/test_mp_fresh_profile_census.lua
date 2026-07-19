return function(H, repo_root)
    local Census = dofile(repo_root
        .. "/modded_progression/scripts/mods/modded_progression/_mp_diag_fresh_profile.lua")
    local source_root = repo_root .. "/../Vermintide-2-Source-Code/scripts/"
    local manager_path = source_root .. "managers/backend_playfab/backend_manager_playfab.lua"

    local function read(path)
        local file = assert(io.open(path, "rb"))
        local source = file:read("*a")
        file:close()
        return source
    end

    local function exists(path)
        local file = io.open(path, "rb")
        if file then file:close() end
        return file ~= nil
    end

    local function interface(spec, mirror)
        local value = { [spec.mirror_field] = mirror }
        for _, method in ipairs(spec.methods) do value[method] = function() end end
        return value
    end
    local function complete_backend()
        local mirror, backend = {}, { _interfaces = {} }
        backend._backend_mirror = mirror
        for _, method in ipairs(Census.MANAGER_METHODS) do backend[method] = function() end end
        for _, spec in ipairs(Census.PROFILE_INTERFACES) do
            backend._interfaces[spec.name] = interface(spec, mirror)
        end
        return backend
    end

    H.test("MP #840 census catalog is closed and source-slice explicit", function()
        H.equal(Census.validate_catalog(), true)
        H.equal(#Census.PROFILE_INTERFACES, 9)
        H.equal(Census.PROFILE_INTERFACES[1].name, "items")
        H.equal(Census.PROFILE_INTERFACES[4].name, "peddler")
        H.equal(Census.PROFILE_INTERFACES[6].name, "quests")
        H.equal(Census.PROFILE_INTERFACES[9].name, "keep_decorations")
    end)

    H.test_if(exists(manager_path),
        "MP #840 census retains the decompiled manager override and mirror contract", function()
        local manager = read(manager_path)
        H.truthy(manager:find("BackendManagerPlayFab.add_loadout_interface_override", 1, true))
        H.truthy(manager:find("BackendManagerPlayFab.add_talents_interface_override", 1, true))
        H.truthy(manager:find("BackendManagerPlayFab.set_total_power_level_interface_for_game_mode", 1, true))
        H.truthy(manager:find("return self._interfaces[interface_name]", 1, true))
        H.truthy(manager:find("BackendManagerPlayFab.get_read_only_data", 1, true))
        H.truthy(manager:find("BackendManagerPlayFab.get_backend_mirror", 1, true))

        local statistics = read(source_root
            .. "managers/backend_playfab/backend_interface_statistics_playfab.lua")
        local peddler = read(source_root
            .. "managers/backend_playfab/backend_interface_peddler_playfab.lua")
        local store = read(source_root .. "settings/dlcs/store/store_common_settings.lua")
        H.truthy(statistics:find("self._mirror = mirror", 1, true))
        H.truthy(peddler:find("self._backend_mirror = backend_mirror", 1, true))
        H.truthy(store:find('playfab_class = "BackendInterfacePeddlerPlayFab"', 1, true))
        end, "optional decompiled vanilla source is not present in this clean clone")

    H.test("MP #840 complete interfaces retain canonical mirror identity", function()
        local report = Census.audit(complete_backend())
        local summary = Census.summary(report)
        H.equal(summary.present, 9)
        H.equal(summary.methods_missing, 0)
        H.equal(summary.manager_methods_missing, 0)
        H.equal(summary.mirror_mismatch, 0)
        H.equal(summary.topology_complete, true)
        H.equal(summary.all_share_canonical, true)
    end)

    H.test("MP #840 census exposes missing and split interface boundaries", function()
        local backend = complete_backend()
        backend._interfaces.items.get_loadout = nil
        backend._interfaces.peddler._backend_mirror = {}
        backend._interfaces.statistics = nil
        backend.get_read_only_data = nil
        local summary = Census.summary(Census.audit(backend))
        H.equal(summary.present, 8)
        H.equal(summary.methods_missing, 1)
        H.equal(summary.manager_methods_missing, 1)
        H.equal(summary.mirror_mismatch, 1)
        H.equal(summary.topology_complete, false)
        H.equal(summary.all_share_canonical, false)
    end)

    H.test("MP #840 census fails closed when a mirror field is absent", function()
        local backend = complete_backend()
        backend._interfaces.statistics._mirror = nil
        local summary = Census.summary(Census.audit(backend))
        H.equal(summary.present, 9)
        H.equal(summary.methods_missing, 0)
        H.equal(summary.mirror_mismatch, 1)
        H.equal(summary.topology_complete, false)
        H.equal(summary.all_share_canonical, false)
    end)

    H.test("MP #840 production remains read-only and emits bounded engine diagnostics", function()
        local path = repo_root
            .. "/modded_progression/scripts/mods/modded_progression/modded_progression.lua"
        local file = assert(io.open(path, "rb"))
        local source = file:read("*a")
        file:close()
        H.truthy(source:find('mod:command("mp_fresh_profile_census"', 1, true))
        H.truthy(source:find("_mp840_capture_when_backend_ready", 1, true))
        H.equal(source:find("FreshProfileCensus.audit", 1, true) ~= nil, true)
        H.truthy(source:find('printf("[mp:840]', 1, true))
        H.equal(source:find('mod:echo("#840', 1, true), nil)

        local module_path = repo_root
            .. "/modded_progression/scripts/mods/modded_progression/_mp_diag_fresh_profile.lua"
        local module_file = assert(io.open(module_path, "rb"))
        local module_source = module_file:read("*a")
        module_file:close()
        H.equal(module_source:find("Managers", 1, true), nil)
        H.equal(module_source:find("mod:", 1, true), nil)
    end)
end
