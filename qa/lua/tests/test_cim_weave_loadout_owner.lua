-- Boundary tests for _cim_weave_loadout_owner (#1159 cim_dev decomposition).
--
-- This owner is the slice that brought the cim_dev entry under the 2500-line
-- hard limit, so it is also the slice with the most ways to be silently wrong.
-- The tests lock five things a structural move can break: the seam (one
-- install, between the immutable-relic UI and the EAC commit block), the hook
-- set (exactly the ten MUTABLE BackendInterfaceWeavesPlayFab registrations, and
-- nothing the sibling owners already hold), the injected-accessor contract (all
-- four entry stores are read LIVE, never snapshotted), the forward-declaration
-- coupling the entry still needs for `_bubble_cap`, and the bubble-cap math the
-- Athanor's grid occupancy depends on.
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
    local owner = read("_cim_weave_loadout_owner.lua")

    local function load_owner()
        return assert(loadfile(root .. "_cim_weave_loadout_owner.lua"))()
    end

    -- Stand-in for the VMF mod object. Records every registration so hook
    -- cardinality and order can be asserted directly, and serves the two
    -- dofile'd dependencies the moved body pulls at install time.
    local function fake_mod(settings)
        local m = {
            hooks = {}, dofiles = {}, settings_installs = 0,
            _settings = settings or {},
        }
        function m:hook(target, method)
            self.hooks[#self.hooks + 1] = { target = target, method = method, kind = "hook" }
        end
        function m:hook_safe(target, method)
            self.hooks[#self.hooks + 1] = { target = target, method = method, kind = "hook_safe" }
        end
        function m:command(name) self.commands = self.commands or {}; self.commands[#self.commands + 1] = name end
        function m:get(key) return self._settings[key] end
        function m:set(key, value) self._settings[key] = value end
        function m:info() end
        function m:warning() end
        function m:echo() end
        function m:dofile(path)
            self.dofiles[#self.dofiles + 1] = path
            return {
                install = function()
                    m.settings_installs = m.settings_installs + 1
                end,
            }
        end
        return m
    end

    local function install_owner(mod, stores)
        stores = stores or {}
        local install = load_owner()
        return install({
            mod = mod,
            is_active = stores.is_active or function() return false end,
            get_forge_item_props = stores.get_forge_item_props or function() return {} end,
            get_forged_weapons = stores.get_forged_weapons or function() return {} end,
            get_amulet_dirty = stores.get_amulet_dirty or function() return { false, false, false } end,
            forge_save = stores.forge_save or function() end,
        })
    end

    -- `_cap_grid_property_arrays` reports over-occupancy through the engine's
    -- raw printf before it trims. Supply that one global for the duration.
    local function with_printf(body)
        local saved = rawget(_G, "printf")
        local lines = {}
        rawset(_G, "printf", function(fmt, ...) lines[#lines + 1] = tostring(fmt) end)
        local ok, err = pcall(body, lines)
        rawset(_G, "printf", saved)
        if not ok then error(err, 0) end
        return lines
    end

    -- The seed pass reaches the backend items interface directly, exactly as it
    -- did in the entry. Supply the narrowest stand-in that lets it run.
    local function with_backend(items, body)
        local saved = rawget(_G, "Managers")
        rawset(_G, "Managers", {
            backend = { get_interface = function() return items end },
        })
        local ok, err = pcall(body)
        rawset(_G, "Managers", saved)
        if not ok then error(err, 0) end
    end

    local MUTABLE_HOOKS = {
        "get_loadout_properties", "get_loadout_traits", "get_loadout_talents",
        "get_mastery", "set_loadout_property", "remove_loadout_property",
        "set_loadout_trait", "remove_loadout_trait", "set_loadout_talent",
        "remove_loadout_talent",
    }

    H.test("CIM weave-loadout owner installs exactly once at the original seam", function()
        H.equal(count_plain(entry,
            "scripts/mods/crafting_in_modded_dev/_cim_weave_loadout_owner"), 1)

        -- The block used to execute between the immutable-relic UI install and
        -- the BackendManagerPlayFab commit suppression. It must also stay BELOW
        -- _cim_weave_economy, whose cost hook closes over the `_bubble_cap`
        -- upvalue this owner binds.
        local economy_at = assert(entry:find(
            "scripts/mods/crafting_in_modded_dev/_cim_weave_economy", 1, true))
        local relic_at = assert(entry:find(
            "scripts/mods/crafting_in_modded_dev/_cim_immutable_relic_ui", 1, true))
        local seam_at = assert(entry:find(
            "scripts/mods/crafting_in_modded_dev/_cim_weave_loadout_owner", 1, true))
        local commit_at = assert(entry:find(
            'mod:hook("BackendManagerPlayFab", "commit"', 1, true))
        H.truthy(economy_at < seam_at, "economy facade installs above the seam")
        H.truthy(relic_at < seam_at, "seam must follow the immutable-relic UI install")
        H.truthy(seam_at < commit_at, "seam must precede the commit suppression")
    end)

    H.test("CIM weave-loadout owner is the sole home of the ten mutable weave hooks", function()
        for _, method in ipairs(MUTABLE_HOOKS) do
            local needle = 'mod:hook("BackendInterfaceWeavesPlayFab", "' .. method .. '"'
            H.equal(count_plain(owner, needle), 1, "owner must own " .. method)
            H.equal(count_plain(entry, needle), 0, "entry must not retain " .. method)
        end
        for _, needle in ipairs({
            "local function _seed_one_item(",
            "local function _forge_seed_item(",
            "local function _forge_apply_to_amulet(",
            "local function _forge_apply_to_item(",
            "local function _get_career_talent_tree(",
            "local function _patch_movespeed_buff()",
            "local _AMULET_SLOT_BY_INDEX",
            "local _PROPERTY_BUBBLE_CAP_STATIC",
            "_store_property_slot = function(",
            "_cap_grid_property_arrays = function(",
            "_bubble_cap = function(",
        }) do
            H.equal(count_plain(owner, needle), 1, "owner must own " .. needle)
            H.equal(count_plain(entry, needle), 0, "entry must not retain " .. needle)
        end
    end)

    H.test("CIM weave-loadout owner leaves the commit block and wire safety in the entry", function()
        -- The commit suppression is anti-tamper safety for BOTH craft surfaces
        -- (it also reads mod._cim_standard_forge_active), so it must never sit
        -- behind this owner's install. The #278/#371 layer stays put too.
        for _, needle in ipairs({
            'mod:hook("BackendManagerPlayFab", "commit"',
            "mod._cim_standard_forge_active",
            "local function _cim_wire_safe_rarity(rarity)",
            'mod:network_register("cim_modded_slot"',
            'mod:hook("PlayerManager", "rpc_sync_loadout_slot"',
        }) do
            H.truthy(count_plain(entry, needle) >= 1, "entry must retain " .. needle)
            H.equal(count_plain(owner, needle), 0, "owner must not absorb " .. needle)
        end
    end)

    H.test("CIM weave-loadout owner keeps the public flat surface unwidened", function()
        -- The owner publishes no mod._cim_* field of its own; the only mod-table
        -- write is its private install state.
        H.equal(count_plain(owner, "mod._cim_weave_loadout_owner_state"), 2)
        for _, forbidden in ipairs({
            "mod._cim_bubble_cap", "mod._cim_store_property_slot",
            "mod._cim_forge_seed_item", "mod._cim_get_forged_weapons",
        }) do
            H.equal(owner:find(forbidden, 1, true), nil,
                "owner must not publish " .. forbidden)
            H.equal(entry:find(forbidden, 1, true), nil,
                "entry must not publish " .. forbidden)
        end
    end)

    H.test("CIM weave-loadout owner reads every entry store live, never snapshotted", function()
        -- open_forge and HeroViewStateWeaveForge.on_exit rebind _forge_item_props
        -- to a FRESH table and flip _custom_forge_active; _forge_load rebinds
        -- _forged_weapons. A captured reference would serve the previous session.
        for _, local_decl in ipairs({
            "local _custom_forge_active", "local _forge_item_props",
            "local _forged_weapons", "local _amulet_dirty",
        }) do
            H.equal(count_plain(owner, local_decl), 0,
                "owner must not declare its own " .. local_decl)
        end
        for _, accessor in ipairs({
            "is_active", "get_forge_item_props", "get_forged_weapons",
            "get_amulet_dirty", "forge_save",
        }) do
            H.truthy(owner:find("ctx." .. accessor, 1, true),
                "owner consumes ctx." .. accessor)
        end
        H.truthy(entry:find("is_active = function() return _custom_forge_active end", 1, true))
        H.truthy(entry:find("get_forge_item_props = function() return _forge_item_props end", 1, true))
        H.truthy(entry:find("get_forged_weapons = function() return _forged_weapons end", 1, true))
        H.truthy(entry:find("get_amulet_dirty = function() return _amulet_dirty end", 1, true))

        -- Drive it: rebind the store and flip the flag AFTER install, then prove
        -- the hook body seeds into the NEW table, the way a second Athanor open
        -- does. A snapshot would keep serving the previous session's seed.
        local mod = fake_mod()
        local props_store, active = {}, false
        local hooked = {}
        function mod:hook(target, method, fn) hooked[method] = fn end
        install_owner(mod, {
            is_active = function() return active end,
            get_forge_item_props = function() return props_store end,
        })

        -- Inactive: the wrapper must fall through to vanilla untouched.
        local vanilla_calls = 0
        local function vanilla() vanilla_calls = vanilla_calls + 1; return "vanilla" end
        H.equal(hooked.get_loadout_traits(vanilla, {}, "es_mercenary", "bid"), "vanilla")
        H.equal(vanilla_calls, 1)

        active = true
        local fresh = {}
        props_store = fresh
        with_backend({ get_item_from_id = function() return nil end }, function()
            local seeded = hooked.get_loadout_traits(
                function() error("vanilla must not run while the forge is cim-open") end,
                {}, "es_mercenary", "bid")
            H.equal(type(seeded), "table")
            H.truthy(next(fresh) ~= nil, "seed must land in the REBOUND props table")
            H.equal(fresh["es_mercenary|bid"].traits, seeded,
                "the hook must return the freshly seeded traits table")
        end)
        H.equal(vanilla_calls, 1, "no extra vanilla call once the forge is cim-open")
    end)

    H.test("CIM weave-loadout owner registers the ten hooks in their original order", function()
        local mod = fake_mod()
        install_owner(mod)
        H.equal(#mod.hooks, 10, "exactly the ten mutable loadout hooks install")
        for i, method in ipairs(MUTABLE_HOOKS) do
            H.equal(mod.hooks[i].target, "BackendInterfaceWeavesPlayFab", "hook " .. i .. " class")
            H.equal(mod.hooks[i].method, method, "hook " .. i .. " method")
            H.equal(mod.hooks[i].kind, "hook", "hook " .. i .. " must be a wrap hook")
        end
        -- The movespeed settings-change re-apply is registered at install, as
        -- it was in the entry, and is the owner's only dofile.
        H.deep_equal(mod.dofiles,
            { "scripts/mods/crafting_in_modded_dev/_cim_settings_runtime" })
        H.equal(mod.settings_installs, 1)
    end)

    H.test("CIM weave-loadout owner install is idempotent", function()
        local mod = fake_mod()
        local install = load_owner()
        local ctx = {
            mod = mod,
            is_active = function() return false end,
            get_forge_item_props = function() return {} end,
            get_forged_weapons = function() return {} end,
            get_amulet_dirty = function() return {} end,
            forge_save = function() end,
        }
        local first = install(ctx)
        local second = install(ctx)
        H.equal(first, second, "a second install must return the first exports")
        H.equal(#mod.hooks, 10, "hooks must not re-register")
        H.equal(mod.settings_installs, 1, "the settings listener must not re-register")
    end)

    H.test("CIM weave-loadout owner rebinds injected resolvers across a reload", function()
        local mod = fake_mod()
        local install = load_owner()
        local first_props, second_props = { a = true }, { b = true }
        local function ctx_for(props, active)
            return {
                mod = mod,
                is_active = function() return active end,
                get_forge_item_props = function() return props end,
                get_forged_weapons = function() return {} end,
                get_amulet_dirty = function() return {} end,
                forge_save = function() end,
            }
        end
        install(ctx_for(first_props, false))
        install(ctx_for(second_props, true))
        local state = mod._cim_weave_loadout_owner_state
        H.equal(state.get_forge_item_props(), second_props,
            "reload must adopt the fresh seed-store accessor")
        H.equal(state.is_active(), true, "reload must adopt the fresh active-state accessor")
        H.equal(#mod.hooks, 10, "reload must not duplicate the hooks")
    end)

    H.test("CIM weave-loadout owner refuses an incomplete context", function()
        local install = load_owner()
        H.equal(pcall(install), false)
        H.equal(pcall(install, { mod = fake_mod() }), false)
        H.equal(pcall(install, {
            mod = fake_mod(), is_active = function() return false end,
        }), false)
    end)

    H.test("CIM weave-loadout owner exports exactly the four names the entry re-binds", function()
        local mod = fake_mod()
        local exports = install_owner(mod)
        local names = {}
        for name in pairs(exports) do names[#names + 1] = name end
        table.sort(names)
        H.deep_equal(names, {
            "bubble_cap", "cap_grid_property_arrays",
            "store_property_slot", "value_for_bubbles",
        })
        for _, name in ipairs(names) do
            H.equal(type(exports[name]), "function", name .. " must be callable")
        end
        -- The late regression installer receives them under its existing keys.
        H.truthy(entry:find("bubble_cap = _bubble_cap", 1, true))
        H.truthy(entry:find("value_for_bubbles = _value_for_bubbles", 1, true))
        H.truthy(entry:find("cap_grid_property_arrays = _cap_grid_property_arrays", 1, true))
        H.truthy(entry:find("store_property_slot = _store_property_slot", 1, true))
    end)

    H.test("CIM weave-loadout owner leaves exactly one forward declaration in the entry", function()
        -- Only `_bubble_cap` has a consumer ABOVE the seam: _cim_weave_economy's
        -- get_property_mastery_costs hook resolves it at callback time. Without
        -- the forward local that closure reads a nil GLOBAL and the Athanor
        -- crashes on the first property-cost query.
        H.equal(count_plain(entry, "\nlocal _bubble_cap\n"), 1,
            "the entry keeps the one genuine forward declaration")
        H.equal(count_plain(entry, "_bubble_cap = _WEAVE_LOADOUT_OWNER.bubble_cap"), 1,
            "the seam binds the forward-declared local")
        H.truthy(entry:find("bubble_cap = function(property_name) return _bubble_cap(property_name) end", 1, true),
            "the economy facade still resolves the cap at callback time")
        -- The other three are ordinary locals assigned at the seam; the two with
        -- no entry consumer at all are gone.
        for _, decl in ipairs({
            "local _value_for_bubbles = _WEAVE_LOADOUT_OWNER.value_for_bubbles",
            "local _store_property_slot = _WEAVE_LOADOUT_OWNER.store_property_slot",
            "local _cap_grid_property_arrays = _WEAVE_LOADOUT_OWNER.cap_grid_property_arrays",
        }) do
            H.equal(count_plain(entry, decl), 1, "seam must assign " .. decl)
        end
        for _, dead in ipairs({ "\nlocal _bubbles_for_value\n", "\nlocal _strip_weave\n" }) do
            H.equal(count_plain(entry, dead), 0,
                "a forward local with no entry consumer must not survive as nil")
        end
    end)

    H.test("CIM weave-loadout owner preserves the #86 bubble caps and key normalization", function()
        local mod = fake_mod({ movespeed_2pct_mode = false })
        local exports = install_owner(mod)
        local cap = exports.bubble_cap
        -- Every caller key form collapses to the bare name (#86 take 3): the
        -- game sends `weave_stamina`, older code sent `weave_properties_stamina`.
        for _, key in ipairs({
            "stamina", "weave_stamina", "properties_stamina", "weave_properties_stamina",
        }) do
            H.equal(cap(key), 2, key .. " must cap at 2 bubbles")
        end
        for _, key in ipairs({ "movespeed", "weave_movespeed", "weave_properties_movespeed" }) do
            H.equal(cap(key), 1, key .. " must cap at 1 bubble")
        end
        H.equal(cap("weave_attack_speed"), 5, "generic properties keep the 5-bubble row")
        -- The 2pct toggle uncaps movespeed to five +2% steps, read dynamically.
        mod._settings.movespeed_2pct_mode = true
        H.equal(cap("weave_movespeed"), 5, "2pct mode must uncap movespeed live")
        H.equal(cap("weave_stamina"), 2, "2pct mode must not touch stamina")
    end)

    H.test("CIM weave-loadout owner keeps the #86 read-chokepoint trim layer-aware", function()
        local mod = fake_mod({ movespeed_2pct_mode = false })
        local exports = install_owner(mod)
        with_printf(function(logged)
            -- Single weapon: one layer, so the whole array caps at the bubble cap.
            local weapon = { weave_stamina = { 1, 2, 3, 4, 5 } }
            exports.cap_grid_property_arrays(weapon, "bid-1")
            H.deep_equal(weapon.weave_stamina, { 1, 2 })

            -- Amulet (no backend id): one property may legitimately appear once
            -- per accessory layer of ten, so a blanket trim would wrongly drop
            -- the necklace and trinket copies.
            local amulet = { weave_movespeed = { 1, 2, 11, 12, 21 } }
            exports.cap_grid_property_arrays(amulet, nil)
            H.deep_equal(amulet.weave_movespeed, { 1, 11, 21 })

            -- Already within cap: untouched, and idempotent on a second pass.
            local clean = { weave_attack_speed = { 1, 2, 3 } }
            exports.cap_grid_property_arrays(clean, "bid-1")
            exports.cap_grid_property_arrays(clean, "bid-1")
            H.deep_equal(clean.weave_attack_speed, { 1, 2, 3 })
            H.truthy(#logged >= 2, "each real trim must self-report through printf")
        end)
    end)

    H.test("CIM weave-loadout owner routes the write cap through the #959 policy", function()
        local mod = fake_mod({ movespeed_2pct_mode = false })
        local seen
        mod._cim959_accessory_property_policy = {
            store_property_slot = function(props, key, slot_index, cap, layer_size)
                seen = { key = key, slot = slot_index, cap = cap, layer_size = layer_size }
                return { slot_index }, true, "stored", 1
            end,
        }
        local exports = install_owner(mod)
        with_printf(function()
            local arr = exports.store_property_slot({}, "weave_stamina", 3, 10)
            H.deep_equal(arr, { 3 })
            H.equal(seen.cap, 2, "the policy must receive the property's own bubble cap")
            H.equal(seen.layer_size, 10)
        end)
        -- Fail loud, not silently uncapped, if the shared policy goes missing.
        mod._cim959_accessory_property_policy = nil
        H.equal(pcall(exports.store_property_slot, {}, "weave_stamina", 3, 10), false)
    end)

    H.test("CIM weave-loadout owner holds no view lifecycle or persistence store", function()
        -- The Athanor on_enter crash-guard cascade, the preview world, the
        -- widget material policy, and the persisted equip store all belong to
        -- other owners. Assert on what this file REGISTERS and CALLS.
        for _, forbidden in ipairs({
            'mod:hook("HeroView', 'mod:hook_safe("HeroView',
            'mod:hook("HeroWindow', 'mod:hook_safe("HeroWindow',
            "set_loadout_item", "_modded_loadout", "_unit_previewer",
            "shading_environment", "create_screen_gui", "Managers.ui",
            "ingame_ui", "UIWidget", "package:load", "network_register",
            "mod:command(",
        }) do
            H.equal(owner:find(forbidden, 1, true), nil,
                "owner must not touch " .. forbidden)
        end
        H.equal(count_plain(owner, "mod:hook"), 10)
    end)
end
