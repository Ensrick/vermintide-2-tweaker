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
    local source = read("_cos_offhand_picker.lua")

    H.test("offhand picker has one ordered owner and exact registration surface", function()
        H.equal(count_plain(entry,
            '"scripts/mods/cosmetics_tweaker/_cos_offhand_picker").install(mod'), 1)
        H.equal(entry:find("local function _has_offhand", 1, true), nil)
        H.equal(entry:find(
            'mod:hook("HeroWindowItemCustomization", "_setup_illusions"', 1, true), nil)
        H.equal(count_plain(source, 'mod:hook("HeroWindowItemCustomization"'), 2)
        H.equal(count_plain(source, 'mod:hook_safe("HeroWindowItemCustomization"'), 1)
        H.equal(count_plain(source,
            "HeroWindowItemCustomization._ct_on_offhand_pressed = function"), 1)
        H.equal(source:find("mod:network_register(", 1, true), nil)
        H.equal(source:find("mod:command(", 1, true), nil)
        H.equal(source:find("function mod.on_", 1, true), nil)
        H.equal(source:find("mod.update", 1, true), nil)

        local setup = assert(source:find('"_setup_illusions"', 1, true))
        local input = assert(source:find('"_handle_input"', setup, true))
        local draw = assert(source:find('"_state_draw_overview"', input, true))
        local press = assert(source:find(
            "HeroWindowItemCustomization._ct_on_offhand_pressed = function", draw, true))
        H.truthy(setup < input and input < draw and draw < press)
    end)

    H.test("offhand picker installer is idempotent and engine lookups stay action-time", function()
        local registrations = {}
        local weapon_skin_reads = 0
        local hero_window = {}
        local mod = {
            _cos = {},
            _la_option_icon_policy = {},
            hook = function(_, class, method, callback)
                registrations[#registrations + 1] =
                    { kind = "hook", class = class, method = method, callback = callback }
            end,
            hook_safe = function(_, class, method, callback)
                registrations[#registrations + 1] =
                    { kind = "safe", class = class, method = method, callback = callback }
            end,
            get = function() return false end,
        }
        local module = assert(loadfile(base .. "_cos_offhand_picker.lua"))()
        local deps = {
            magic_skin_gateway = {
                filter = function(widgets, current, resolver, show_magic)
                    H.equal(resolver("magic"), "weaves")
                    H.equal(show_magic, false)
                    return widgets, current
                end,
            },
            create_glow_editor_button = function() return {} end,
            refresh_glow_editor_button = function() end,
            refresh_illusion_glow_badges = function() end,
            set_active_customization_backend_id = function() end,
            get_offhand_options = function() return nil end,
            multi_mount_item_types = {},
            offhand_session_state = {
                migrate_legacy = function() end,
                snapshot = function() return false end,
            },
            offhand_selection = {},
            preload_offhand_for_option = function() end,
            source_illusion_name = function(key) return key end,
            offhand_names = { compose = function(primary) return primary end },
            glow_picker = {},
            la_bridge = {},
            local_player_safe = function() return nil end,
            shield_icon_owner_item_types = {},
            inventory_icon_for_offhand_unit = function() return nil end,
            dbg = function() end,
            trace = function() end,
            get_managers = function() return nil end,
            get_weapon_skins = function()
                weapon_skin_reads = weapon_skin_reads + 1
                return { skins = { magic = { material_settings_name = "weaves" } } }
            end,
            get_item_master_list = function() return {} end,
            get_ui_widget = function() return {} end,
            get_ui_renderer = function() return {} end,
            get_local_require = function() return function() return {} end end,
            hero_window_item_customization = hero_window,
            la_option_icon_policy = {
                selected_primary_skin = function() return nil end,
                resolve_for_item = function(option) return option end,
            },
        }

        local owner = module.install(mod, deps)
        H.equal(#registrations, 3)
        H.equal(registrations[1].kind, "hook")
        H.equal(registrations[1].method, "_setup_illusions")
        H.equal(registrations[2].kind, "safe")
        H.equal(registrations[2].method, "_handle_input")
        H.equal(registrations[3].kind, "hook")
        H.equal(registrations[3].method, "_state_draw_overview")
        H.equal(owner.hook_count, 3)
        H.equal(owner.method_count, 1)
        H.equal(type(hero_window._ct_on_offhand_pressed), "function")
        H.equal(weapon_skin_reads, 0, "engine table must not be read during install")

        local widgets = {}
        local kept, current = mod._filter_illusion_widgets(
            widgets, "current", function() return false end)
        H.equal(kept, widgets)
        H.equal(current, "current")
        H.equal(weapon_skin_reads, 1)

        local again = module.install(mod, {})
        H.equal(again, owner)
        H.equal(#registrations, 3)
    end)

    H.test("offhand picker remains below the extraction ceiling", function()
        local nonblank = 0
        for line in source:gmatch("[^\r\n]*") do
            if line:match("%S") then nonblank = nonblank + 1 end
        end
        H.truthy(nonblank < 1500, "picker owner exceeded 1500 nonblank lines")
    end)
end
