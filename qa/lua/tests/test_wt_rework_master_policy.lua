return function(H, repo_root)
    local stable_path = repo_root
        .. "/weapon_tweaker/scripts/mods/weapon_tweaker/_wt_rework_master_policy.lua"
    local dev_path = repo_root
        .. "/weapon_tweaker_dev/scripts/mods/weapon_tweaker_dev/_wt_rework_master_policy.lua"
    local policy = assert(loadfile(stable_path))()
    local dev_policy = assert(loadfile(dev_path))()

    local function change_map(changes)
        local out = {}
        for i = 1, #changes do
            H.equal(out[changes[i].id], nil, "duplicate write for " .. changes[i].id)
            out[changes[i].id] = changes[i].value
        end
        return out
    end

    local function table_count(values)
        local count = 0
        for _ in pairs(values or {}) do count = count + 1 end
        return count
    end

    H.test("WT rework master owns the exact active tweak family", function()
        H.equal(#policy.LEAF_IDS, 15)
        H.equal(#dev_policy.LEAF_IDS, #policy.LEAF_IDS)
        for i = 1, #policy.LEAF_IDS do
            H.equal(dev_policy.LEAF_IDS[i], policy.LEAF_IDS[i])
            H.truthy(policy.is_member(policy.LEAF_IDS[i]))
            H.equal(policy.LEAF_IDS[i]:find("^br_"), nil, "retired Big Rebalance leaked into family")
        end
    end)

    H.test("WT rework master plans only changed writes", function()
        local current = { [policy.MASTER_ID] = false }
        for i = 1, #policy.LEAF_IDS do current[policy.LEAF_IDS[i]] = false end
        current[policy.LEAF_IDS[1]] = true
        local planned = policy.plan(true, current)
        local changes = change_map(planned)
        H.equal(#planned, #policy.LEAF_IDS)
        H.equal(changes[policy.LEAF_IDS[1]], nil, "already-on leaf must not be rewritten")
        H.equal(changes[policy.MASTER_ID], true)
    end)

    H.test("WT rework master derives exact and partial states", function()
        local current = {}
        for i = 1, #policy.LEAF_IDS do current[policy.LEAF_IDS[i]] = true end
        H.equal(policy.derive_master(current), true)
        current[policy.LEAF_IDS[5]] = false
        H.equal(policy.derive_master(current), false)
    end)

    H.test("WT tweak labels carry one idempotent authorship prefix", function()
        for i = 1, #policy.LEAF_IDS do
            local id = policy.LEAF_IDS[i]
            local once = policy.decorate_label(id, "Example")
            H.equal(once, "[Ensrick] Example")
            H.equal(policy.decorate_label(id, once), once)
        end
        H.equal(policy.decorate_label("br_retired", "Retired"), "Retired")
    end)

    local function load_surface(root, namespace)
        local old_get_mod = _G.get_mod
        local old_printf = _G.printf
        local mod = {
            _wt = {},
            localize = function(_, id) return id end,
            get = function() return false end,
            set = function() end,
            debug = function() end,
            info = function() end,
            warning = function() end,
            echo = function() end,
            command = function() end,
        }
        function mod:dofile(path)
            if path:find("_wt_rework_master_policy$", 1) then return policy end
            local module_path = repo_root .. "/" .. namespace .. "/" .. path .. ".lua"
            return assert(loadfile(module_path))()
        end
        _G.get_mod = function(name)
            if name == "wt" or name == "wt_dev" then return mod end
            return nil
        end
        _G.printf = function() end
        local ok_data, data = pcall(assert(loadfile(root .. "/" .. namespace .. "_data.lua")))
        local ok_loc, loc = pcall(assert(loadfile(root .. "/" .. namespace .. "_localization.lua")))
        _G.get_mod = old_get_mod
        _G.printf = old_printf
        H.truthy(ok_data, tostring(data))
        H.truthy(ok_loc, tostring(loc))
        return data, loc
    end

    H.test("WT stable and dev menus expose one nested family master", function()
        local surfaces = {
            {
                repo_root .. "/weapon_tweaker/scripts/mods/weapon_tweaker",
                "weapon_tweaker",
            },
            {
                repo_root .. "/weapon_tweaker_dev/scripts/mods/weapon_tweaker_dev",
                "weapon_tweaker_dev",
            },
        }
        for _, surface in ipairs(surfaces) do
            local data, loc = load_surface(surface[1], surface[2])
            local masters, leaves, visible_tweaks, parent = 0, {}, {}, nil
            local function visit(widget, parent_id)
                if type(widget) ~= "table" then return end
                if widget.setting_id == policy.MASTER_ID then
                    masters = masters + 1
                    parent = parent_id
                    H.equal(widget.type, "checkbox")
                elseif widget.type == "checkbox" then
                    if policy.is_member(widget.setting_id) then
                        leaves[widget.setting_id] = true
                    end
                    if parent_id == "weapon_overrides" then
                        visible_tweaks[widget.setting_id] = true
                    end
                end
                for _, child in ipairs(widget.sub_widgets or {}) do
                    visit(child, widget.setting_id)
                end
            end
            for _, widget in ipairs(data.options and data.options.widgets or {}) do visit(widget, nil) end
            H.equal(masters, 1)
            H.equal(parent, "wt_rework_master_group")
            H.equal(table_count(visible_tweaks), #policy.LEAF_IDS,
                "every visible Weapon Tweak must belong to the master catalog")
            for i = 1, #policy.LEAF_IDS do
                local id = policy.LEAF_IDS[i]
                H.truthy(leaves[id], id .. " is absent from visible Weapon Tweaks")
                H.truthy(visible_tweaks[id], id .. " is not a direct visible Weapon Tweak")
                H.equal(loc[id].en:sub(1, #policy.LABEL_PREFIX), policy.LABEL_PREFIX)
            end
            H.equal(loc.wt_rework_master_group.en, "Master Toggles")
        end
    end)

    H.test("WT master runtime uses non-notifying bounded leaf writes", function()
        local paths = {
            repo_root .. "/weapon_tweaker/scripts/mods/weapon_tweaker/_wt_rework_master_runtime.lua",
            repo_root .. "/weapon_tweaker_dev/scripts/mods/weapon_tweaker_dev/_wt_rework_master_runtime.lua",
        }
        for _, path in ipairs(paths) do
            local file = assert(io.open(path, "rb"))
            local source = file:read("*a")
            file:close()
            H.truthy(source:find("mod:set(changes[i].id, changes[i].value, false)", 1, true),
                path .. " does not suppress per-leaf notifications")
            H.truthy(source:find("runtime._batch", 1, true),
                path .. " lacks the synchronous re-entry guard")
            H.truthy(source:find("apply_live()", 1, true),
                path .. " lacks one post-batch owner dispatch")
        end
    end)

    H.test("WT master runtime applies one owner pass after thirteen silent writes", function()
        local runtime_module = assert(loadfile(repo_root
            .. "/weapon_tweaker/scripts/mods/weapon_tweaker/_wt_rework_master_runtime.lua"))()
        local values, writes, applies = { [policy.MASTER_ID] = true }, {}, 0
        for i = 1, #policy.LEAF_IDS do values[policy.LEAF_IDS[i]] = false end
        local mod = {
            get = function(_, id) return values[id] end,
            set = function(_, id, value, notify)
                values[id] = value
                writes[#writes + 1] = { id = id, notify = notify }
            end,
            warning = function() end,
        }
        local old_printf = _G.printf
        _G.printf = function() end
        local runtime = runtime_module.new(mod, policy, function() applies = applies + 1 end)
        H.equal(runtime:on_master_changed(policy.MASTER_ID), true)
        _G.printf = old_printf
        H.equal(#writes, #policy.LEAF_IDS)
        H.equal(applies, 1)
        for i = 1, #writes do H.equal(writes[i].notify, false) end
        H.equal(runtime:is_batching(), false)
        H.equal(runtime:on_master_changed("unrelated"), false)
    end)
end
