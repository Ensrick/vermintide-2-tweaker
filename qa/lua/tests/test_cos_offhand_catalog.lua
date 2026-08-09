-- resource-safety: cos1159-offhand-package-preload
return function(H, repo_root)
    local base = repo_root .. "/cosmetics_tweaker/scripts/mods/cosmetics_tweaker/"

    local function read(name)
        local file = assert(io.open(base .. name, "rb"))
        local source = file:read("*a")
        file:close()
        return source
    end

    local function count_plain(source, needle)
        local count, at = 0, 1
        while true do
            local found = source:find(needle, at, true)
            if not found then return count end
            count = count + 1
            at = found + #needle
        end
    end

    local entry = read("cosmetics_tweaker.lua")
    local source = read("_cos_offhand_catalog.lua")

    H.test("offhand catalog package boundary keeps its resource-safety marker", function()
        H.truthy(source:find("resource-safety: cos1159-offhand-package-preload", 1, true))
        H.equal(count_plain(source, "Managers.package:load("), 1)
    end)

    H.test("offhand catalog has one entry owner and no registration surfaces", function()
        H.equal(count_plain(entry,
            '"scripts/mods/cosmetics_tweaker/_cos_offhand_catalog").install(mod'), 1)
        H.equal(count_plain(entry, "local _offhand_preload_lifecycle"), 0)
        H.equal(count_plain(entry, "local _force_loaded_all_offhand_done"), 0)
        H.equal(count_plain(source, "local _offhand_preload_lifecycle"), 1)
        H.equal(count_plain(source, "local _force_loaded_all_offhand_done"), 1)
        for _, forbidden in ipairs({
            "mod:hook(", "mod:hook_safe(", "mod:network_register(",
            "mod:command(", "function mod.on_",
        }) do
            H.equal(source:find(forbidden, 1, true), nil, forbidden)
        end
    end)

    H.test("offhand catalog install is idempotent and preserves package ownership", function()
        local new_count, hook_count = 0, 0
        local loaded, callbacks, unloaded = {}, {}, {}
        local lifecycle = {
            new = function()
                new_count = new_count + 1
                local ledger = { states = {}, stats = { late_callbacks_ignored = 0 }, generation = 0 }
                function ledger:mark_resident(path) self.states[path] = "resident" end
                function ledger:begin(path)
                    if self.states[path] then return nil end
                    self.generation = self.generation + 1
                    self.states[path] = { generation = self.generation }
                    return self.generation
                end
                function ledger:complete(path, generation)
                    local state = self.states[path]
                    if type(state) == "table" and state.generation == generation then
                        self.states[path] = "ready"
                        return true
                    end
                    self.stats.late_callbacks_ignored =
                        self.stats.late_callbacks_ignored + 1
                    return false
                end
                function ledger:cancel(path) self.states[path] = nil end
                function ledger:release()
                    local paths = {}
                    for path, state in pairs(self.states) do
                        if state ~= "resident" then paths[#paths + 1] = path end
                    end
                    self.states = {}
                    return paths
                end
                return ledger
            end,
        }
        local package_manager = {
            has_loaded = function() return false end,
            load = function(_, path, _, callback)
                loaded[path] = true
                callbacks[path] = callback
            end,
            reference_count = function(_, path)
                return loaded[path] and 1 or 0
            end,
            unload = function(_, path)
                unloaded[path] = (unloaded[path] or 0) + 1
            end,
        }
        local mod = {
            _cos = {},
            localize = function(_, key) return key end,
            info = function() end,
            debug = function() end,
            hook = function() hook_count = hook_count + 1 end,
            hook_safe = function() hook_count = hook_count + 1 end,
            network_register = function() hook_count = hook_count + 1 end,
            command = function() hook_count = hook_count + 1 end,
        }
        local weapon_skins = {
            skins = {
                alpha = { data = {
                    left_hand_unit = "units/test/icon",
                    inventory_icon = "icon_alpha",
                    template = "wrong",
                } },
                beta = { data = {
                    left_hand_unit = "units/test/icon",
                    inventory_icon = "icon_beta",
                    template = "preferred",
                } },
            },
            skin_combinations = {},
        }
        local module = assert(loadfile(base .. "_cos_offhand_catalog.lua"))()
        local deps = {
            offhand_preload_lifecycle = lifecycle,
            offhand_names = {
                decorate = function(option) return option end,
                readable_source_name = function(key) return key end,
                inventory_rows = function(records) return records end,
            },
            gk_set = {
                resolve_variant = function(key)
                    if key == "authored" then
                        return { new_units = { "units/authored", "units/authored_3p" } }
                    end
                end,
            },
            la_bridge = { kruber_shield_item_types = {} },
            cwv_family_contract = {
                families = {},
                dual_sources = function() return {} end,
                shield_pool_source = function() return nil end,
                skin_source_allowed = function() return true end,
            },
            custom_illusions = {},
            skin_requires_unowned_dlc = function() return false end,
            dbg = function() end,
            dbg_alert = function() end,
            get_mod = function() return nil end,
            get_managers = function() return { package = package_manager } end,
            application = {
                can_get = function(kind, path)
                    return kind == "package"
                        or (kind == "unit" and path:find("units/authored", 1, true) == 1)
                end,
            },
            network_lookup = { inventory_packages = {} },
            weapon_skins = weapon_skins,
            item_master_list = {},
            printf = function() end,
        }

        local owner = module.install(mod, deps)
        local again = module.install(mod, {})
        H.equal(owner, again)
        H.equal(new_count, 1)
        H.equal(hook_count, 0)
        H.equal(owner.offhand_options.es_1h_mace_shield.left_hand_unit
            == owner.shield_pools_by_item_type.es_1h_sword_shield, false,
            "derived pools must remain de-aliased")
        H.equal(owner.inventory_icon_for_offhand_unit(
            "units/test/icon", "preferred"), "icon_beta")
        H.equal(type(owner.decorate_shield_option), "function")
        H.equal(type(owner.source_illusion_name), "function")

        local one_p, three_p, ready = owner.resolve_authored_offhand_mesh("authored")
        H.equal(one_p, "units/authored")
        H.equal(three_p, "units/authored_3p")
        H.truthy(ready)

        owner.preload_offhand_package("units/test/package")
        H.equal((function()
            local count = 0
            for _ in pairs(loaded) do count = count + 1 end
            return count
        end)(), 18)
        for _, callback in pairs(callbacks) do callback() end
        H.equal(mod._release_offhand_packages("test"), 18)
        local release_count = 0
        for _, count in pairs(unloaded) do release_count = release_count + count end
        H.equal(release_count, 18)
    end)
end
