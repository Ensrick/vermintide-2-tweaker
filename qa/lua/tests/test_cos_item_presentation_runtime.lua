return function(H, repo_root)
    local root = repo_root
        .. "/cosmetics_tweaker/scripts/mods/cosmetics_tweaker/"
    local runtime_path = root .. "_cos_item_presentation_runtime.lua"
    local entry_path = root .. "cosmetics_tweaker.lua"
    local Runtime = dofile(runtime_path)
    local ItemPresentation = dofile(root .. "_cos_item_presentation.lua")
    local OffhandNames = dofile(root .. "_cos_offhand_names.lua")
    local CompositeIconFactory = dofile(root .. "_cos_composite_icons.lua")

    local function read(path)
        local f = assert(io.open(path, "rb"))
        local source = f:read("*a")
        f:close()
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

    local function fixture(overrides)
        local hooks = {}
        local infos = {}
        local mod = {
            _cos = { presentation_localization = {} },
            _independent_dual_item_types = {},
            _la_option_icon_policy = {
                resolve_for_item = function(option) return option end,
            },
        }
        function mod:hook(target, method, callback)
            hooks[#hooks + 1] = {
                target = target,
                method = method,
                callback = callback,
            }
        end
        function mod:info(...)
            infos[#infos + 1] = { ... }
        end

        local UIUtils = {
            get_ui_information_from_item = function()
                return "base_icon", "base_name", "base_description", "store_icon"
            end,
        }
        local saved_skin = "saved_skin"
        local item_master = {
            weapon = { item_type = "shield_weapon" },
        }
        local weapon_skins = {
            skins = {
                saved_skin = {
                    right_hand_unit = "units/primary",
                    display_name = "primary_name",
                },
            },
            default_skins = { weapon = "default_skin" },
        }
        local offhand_options = {
            shield_weapon = {
                left_hand_unit = {
                    {
                        unit = "units/shield",
                        name = "Shield Name",
                        description = "Shield description.",
                    },
                },
            },
        }
        local deps = {
            composite_icon_factory = {
                ui_icon_availability = function() return true end,
            },
            ui_atlas_helper = {},
            get_application = function() return nil end,
            la_persist = {
                get_saved_illusion = function() return saved_skin end,
                get_saved_offhands_for = function() return nil end,
            },
            get_item_master_list = function() return item_master end,
            get_weapon_skins = function() return weapon_skins end,
            offhand_selection = {},
            glow_picker = {
                committed_state_for = function() return nil end,
                native_state_for = function() return nil end,
            },
            composite_icons = {
                publish = function() end,
                resolve_detailed = function() return nil, "control" end,
                icon_ready = function() return true end,
                claim_diagnostic = function() return false end,
            },
            offhand_names = OffhandNames,
            shield_icon_owner_item_types = { shield_weapon = true },
            offhand_options = offhand_options,
            get_mod = function() return nil end,
            la_bridge = {
                normalize_weapon_type = function(value) return value end,
            },
            inventory_icon_for_offhand_unit = function() return nil end,
            item_presentation = ItemPresentation,
            la_icon_provider = { resolve = function() return nil end },
            la_instance_policy = {},
            offhand_session_state = { migrate_legacy = function() end },
            get_localize = function()
                return function(key) return key .. "_localized" end
            end,
            ui_utils = UIUtils,
        }
        for key, value in pairs(overrides or {}) do
            deps[key] = value
        end
        local owner = Runtime.install(mod, deps)
        return {
            mod = mod,
            deps = deps,
            owner = owner,
            hooks = hooks,
            infos = infos,
            ui_utils = UIUtils,
            set_saved_skin = function(value) saved_skin = value end,
        }
    end

    H.test("Cosmetics item presentation runtime owns both adapters at historical seams", function()
        local entry = read(entry_path)
        local runtime = read(runtime_path)
        H.equal(count(entry,
            'mod:dofile(\n    "scripts/mods/cosmetics_tweaker/_cos_item_presentation_runtime").install'), 1)
        H.equal(count(entry, "_cos_item_presentation_runtime.install_peer({"), 1)
        H.equal(count(entry, 'mod:hook(UIUtils, "get_ui_information_from_item"'), 0)
        H.equal(count(entry, "mod._cos.resolve_peer_item_presentation = function"), 0)
        H.equal(count(runtime, 'mod:hook(UIUtils, "get_ui_information_from_item"'), 1)
        H.equal(count(runtime, "mod._cos.resolve_peer_item_presentation = function"), 1)

        local base_at = assert(entry:find(
            "local _cos_item_presentation_runtime = mod:dofile(", 1, true))
        local refresh_at = assert(entry:find(
            'mod:dofile("scripts/mods/cosmetics_tweaker/_cos_ui_presentation_refresh")',
            base_at, true))
        H.truthy(base_at < refresh_at)
        local receivers_at = assert(entry:find("LA_SYNC.install_receivers()", 1, true))
        local peer_at = assert(entry:find(
            "_cos_item_presentation_runtime.install_peer({", receivers_at, true))
        local glow_at = assert(entry:find(
            '"scripts/mods/cosmetics_tweaker/_cos_glow_transport"', peer_at, true))
        H.truthy(receivers_at < peer_at and peer_at < glow_at)
    end)

    H.test("Cosmetics item presentation runtime adds no transport or lifecycle surface", function()
        local runtime = read(runtime_path)
        for _, forbidden in ipairs({
            "network_register", "network_send", "mod:command(", "mod.update",
            "on_game_state_changed", "on_disabled", "on_unload", "mod:dofile(",
        }) do
            H.equal(runtime:find(forbidden, 1, true), nil, forbidden)
        end
    end)

    H.test("Cosmetics item presentation install is idempotent and refreshes dependencies", function()
        local f = fixture()
        H.equal(#f.hooks, 1)
        H.equal(f.hooks[1].method, "get_ui_information_from_item")
        H.equal(f.owner.active_skin({ key = "weapon" }, "backend"), "saved_skin")

        local replacement = {}
        for key, value in pairs(f.deps) do replacement[key] = value end
        replacement.la_persist = {
            get_saved_illusion = function() return "replacement_skin" end,
            get_saved_offhands_for = function() return nil end,
        }
        local again = Runtime.install(f.mod, replacement)
        H.equal(again, f.owner)
        H.equal(#f.hooks, 1)
        H.equal(f.owner.active_skin({ key = "weapon" }, "backend"),
            "replacement_skin")
    end)

    H.test("Cosmetics item presentation preserves the optional UI atlas fallback", function()
        local f = fixture({
            ui_atlas_helper = false,
            composite_icon_factory = CompositeIconFactory,
        })
        f.owner.ctx.ui_atlas_helper = nil
        local available, reason = f.owner.ui_icon_available("custom_icon")
        H.equal(available, false)
        H.equal(reason, "missing-resource")
        H.equal(#f.hooks, 1)
    end)

    H.test("Cosmetics UIUtils adapter preserves all vanilla returns without exact identity", function()
        local f = fixture()
        local callback = f.hooks[1].callback
        local icon, name, description, store = callback(function()
            return "vanilla_icon", "vanilla_name", "vanilla_description", "store_icon"
        end, { key = "weapon" })
        H.equal(icon, "vanilla_icon")
        H.equal(name, "vanilla_name")
        H.equal(description, "vanilla_description")
        H.equal(store, "store_icon")
    end)

    H.test("Cosmetics peer presentation is one late phase over existing caches", function()
        local f = fixture()
        f.owner.install_peer({
            la_equips_by_peer = {},
            get_offhand_mesh_by_peer = function()
                return {
                    peer_a = {
                        slot_melee = { left_hand_unit = "units/shield" },
                    },
                }
            end,
        })
        local first = f.mod._cos.resolve_peer_item_presentation
        f.owner.install_peer({
            la_equips_by_peer = {},
            get_offhand_mesh_by_peer = function() return {} end,
        })
        H.equal(f.mod._cos.resolve_peer_item_presentation, first)
        H.equal(first("peer_a", "slot_melee", {
            key = "weapon",
            data = { item_type = "shield_weapon" },
        }, "base_icon", "Primary", "Primary description"), nil,
            "reinstall refreshes the action-time peer cache")

        f.owner.install_peer({
            la_equips_by_peer = {},
            get_offhand_mesh_by_peer = function()
                return {
                    peer_a = {
                        slot_melee = { left_hand_unit = "units/shield" },
                    },
                }
            end,
        })
        local result = first("peer_a", "slot_melee", {
            key = "weapon",
            data = { item_type = "shield_weapon" },
        }, "base_icon", "Primary", "Primary description")
        H.equal(result.source, "peer_cache")
        H.equal(result.ownership, "shield")
        H.truthy(result.display_name ~= nil)
        H.truthy(result.description ~= "Primary description")
    end)
end
