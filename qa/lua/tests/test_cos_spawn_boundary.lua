return function(H, repo_root)
    local root = repo_root
        .. "/cosmetics_tweaker/scripts/mods/cosmetics_tweaker/"
    local owner_path = root .. "_cos_spawn_boundary.lua"
    local entry_path = root .. "cosmetics_tweaker.lua"
    local SpawnBoundary = dofile(owner_path)

    local function read(path)
        local file = assert(io.open(path, "rb"))
        local source = file:read("*a")
        file:close()
        return source
    end

    local function count(source, needle)
        local n, at = 0, 1
        while true do
            local found = source:find(needle, at, true)
            if not found then return n end
            n = n + 1
            at = found + #needle
        end
    end

    H.test("Cosmetics #270 preserves native UnitSpawner semantics", function()
        local source = read(repo_root
            .. "/cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_material_hijack_embedded.lua")
        local begin_at = assert(source:find(
            'mod:hook("UnitSpawner", "spawn_local_unit"', 1, true))
        local end_at = assert(source:find(
            "-- v0.9.5: HeroPreviewer._spawn_item_unit hook REMOVED", begin_at, true))
        local hook = source:sub(begin_at, end_at - 1)

        H.truthy(hook:find(
            "local unit = func(self, unit_name, position, rotation, material)", 1, true))
        H.truthy(hook:find("if not unit or not unit_alive(unit) then", 1, true))
        H.truthy(hook:find("replace_textures(unit)", 1, true))
        H.truthy(hook:find("add_particles(unit, self.world)", 1, true))
        H.equal(hook:find("Application.can_get", 1, true), nil)
        H.equal(hook:find("World.spawn_unit", 1, true), nil)
        H.equal(hook:find("POSITION_LOOKUP", 1, true), nil)
        H.equal(hook:find("return nil", 1, true), nil)

        local _, delegates = hook:gsub(
            "func%(self, unit_name, position, rotation, material%)", "")
        H.equal(delegates, 1, "native spawn must be delegated exactly once")
    end)

    H.test("Cosmetics #270 optional attachments retain their narrow residency gate", function()
        local source = read(owner_path)
        local begin_at = assert(source:find(
            'mod:hook(attachment_utils, "create_attachment"', 1, true))
        local end_at = assert(source:find(
            "-- #270/#950: the policy rejects dead units", begin_at, true))
        local hook = source:sub(begin_at, end_at - 1)
        H.truthy(hook:find('local is_headpiece = slot_name == "slot_hat"', 1, true))
        H.truthy(hook:find("not state.unit_resident(path)", 1, true))
        H.truthy(hook:find("if is_headpiece and type(path)", 1, true))
        H.truthy(hook:find(
            "unit = nil,",
            1, true))
        H.equal(hook:find('slot_name ~= "slot_hat"', 1, true), nil)
    end)

    H.test("Cosmetics spawn boundary is the exclusive ordered hook owner", function()
        local entry = read(entry_path)
        local source = read(owner_path)
        H.equal(count(entry,
            'mod:dofile("scripts/mods/cosmetics_tweaker/_cos_spawn_boundary").install'), 1)
        H.equal(count(entry,
            'mod:hook(AttachmentUtils, "create_attachment"'), 0)
        H.equal(count(entry,
            'mod:hook("HeroPreviewer", "_spawn_item_unit"'), 0)
        H.equal(count(entry,
            'mod:hook("MenuWorldPreviewer", "_spawn_item_unit"'), 0)
        H.equal(count(source,
            'mod:hook(attachment_utils, "create_attachment"'), 1)
        H.equal(count(source,
            'mod:hook("HeroPreviewer", "_spawn_item_unit"'), 1)
        H.equal(count(source,
            'mod:hook("MenuWorldPreviewer", "_spawn_item_unit"'), 1)

        for _, forbidden in ipairs({
            "network_register", "network_send", "mod:command(", "mod.update",
            "on_game_state_changed", "on_disabled", "on_unload", "mod:dofile(",
        }) do
            H.equal(source:find(forbidden, 1, true), nil, forbidden)
        end
    end)

    local function fixture()
        local hooks = {}
        local info = {}
        local link_installs = 0
        local surface_calls = 0
        local mod = { _unit_to_backend_id = {} }
        function mod:hook(target, method, callback)
            hooks[#hooks + 1] = {
                kind = "hook", target = target, method = method,
                callback = callback,
            }
        end
        function mod:hook_safe(target, method, callback)
            hooks[#hooks + 1] = {
                kind = "safe", target = target, method = method,
                callback = callback,
            }
        end
        function mod:info(...)
            info[#info + 1] = { ... }
        end

        local attachment_utils = { create_attachment = function() end }
        local world_api = { link_unit = function() end }
        local resident = false
        local deps = {
            application = {
                can_get = function(kind, path)
                    return resident or path ~= "units/missing_hat"
                end,
            },
            attachment_utils = attachment_utils,
            world = world_api,
            unit = {
                alive = function() return true end,
                has_data = function() return true end,
                get_data = function() return "units/authored" end,
            },
            la_bridge = {
                registered = true,
                backend_to_armoury = {},
                maybe_queue_unit = function() end,
                queue_unit_direct = function() return true end,
                suppress_orphan = function() end,
            },
            custom_hats = {
                ITEM_KEY = "custom_hat",
                apply_surface = function() surface_calls = surface_calls + 1 end,
                is_custom_identity = function() return false end,
            },
            gk_set = {
                resolve_variant = function() return nil end,
                apply_variant_to_unit = function() end,
            },
            attachment_link_policy = {
                install = function()
                    link_installs = link_installs + 1
                end,
            },
            get_mod = function() return nil end,
            dbg = function() end,
            printf = function() end,
        }
        local owner = SpawnBoundary.install(mod, deps)
        local function find(target, method)
            for _, hook in ipairs(hooks) do
                if hook.target == target and hook.method == method then
                    return hook.callback
                end
            end
        end
        return {
            mod = mod, deps = deps, owner = owner, hooks = hooks, info = info,
            attachment_utils = attachment_utils, world_api = world_api,
            find = find,
            set_resident = function(value) resident = value end,
            link_installs = function() return link_installs end,
            surface_calls = function() return surface_calls end,
        }
    end

    H.test("Cosmetics spawn boundary fails open generally and skips only missing hats", function()
        local f = fixture()
        local callback = assert(f.find(f.attachment_utils, "create_attachment"))
        local delegates = 0
        local function vanilla(...)
            delegates = delegates + 1
            return { unit = "spawned" }
        end

        local missing = callback(vanilla, "world", "owner", {}, "slot_hat", {
            name = "missing", unit = "units/missing_hat",
        }, true)
        H.equal(delegates, 0)
        H.equal(missing.unit, nil)
        H.equal(missing.name, "missing")

        local weapon = callback(vanilla, "world", "owner", {}, "slot_melee", {
            name = "weapon", unit = "units/missing_hat",
        }, true)
        H.equal(delegates, 1)
        H.equal(weapon.unit, "spawned")

        f.set_resident(true)
        local hat = callback(vanilla, "world", "owner", {}, "slot_hat", {
            name = "custom_hat", unit = "units/missing_hat",
        }, true)
        H.equal(delegates, 2)
        H.equal(hat.unit, "spawned")
        H.equal(f.surface_calls(), 1)
        H.equal(f.link_installs(), 1)
    end)

    H.test("Cosmetics spawn boundary install is idempotent and refreshes residency dependencies", function()
        local f = fixture()
        H.equal(#f.hooks, 4)
        H.equal(f.owner.hook_count, 4)
        local replacement = {}
        for key, value in pairs(f.deps) do replacement[key] = value end
        replacement.application = {
            can_get = function() return true end,
        }
        local again = SpawnBoundary.install(f.mod, replacement)
        H.equal(again, f.owner)
        H.equal(#f.hooks, 4)
        H.equal(f.link_installs(), 1)
        H.equal(f.owner.unit_resident("units/missing_hat"), true)
    end)
end
