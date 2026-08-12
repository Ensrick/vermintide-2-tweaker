return function(H, repo_root)
    local base = repo_root
        .. "/cosmetics_tweaker/scripts/mods/cosmetics_tweaker/"
    local module_path = base .. "_cos_husk_wield_runtime.lua"
    local entry_path = base .. "cosmetics_tweaker.lua"
    local Runtime = dofile(module_path)

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

    local function fixture()
        local hooks, reconciles = {}, {}
        local glow = { binds = 0, applies = 0, completes = 0 }
        local player = { peer_id = "peer-a", local_player_id = 1 }
        local mod = {
            _cos = {
                bind_glow_unit = function() glow.binds = glow.binds + 1 end,
                remote_glow_matches = function() return true end,
                apply_glow_override = function() glow.applies = glow.applies + 1 end,
            },
        }
        function mod:hook(class, method, callback)
            hooks[#hooks + 1] = {
                class = class, method = method, callback = callback,
            }
        end
        function mod._la_reconcile(peer, key, reason, pulse)
            reconciles[#reconciles + 1] = {
                peer = peer, key = key, reason = reason, pulse = pulse,
            }
        end
        local store = {
            ["peer-a"] = {
                template_a = {
                    kind = "offhand", armoury_key = "shield",
                    wearer_career = "career-a",
                },
            },
        }
        local deps = {
            get_managers = function() return { player = {} } end,
            husk_identity = {
                player_for_unit = function() return player end,
                wearer_is_human = function() return true, "human" end,
                local_player_id = function(p) return p.local_player_id end,
                player_controlled = function() return true end,
                invalidate_for_career = function() return 0, "same", {} end,
                entry_matches_career = function() return true end,
            },
            la_equips_by_peer = store,
            get_application = function()
                return { can_get = function() return true end }
            end,
            get_weapon_skins = function() return { skins = {} } end,
            glow_by_peer = {
                ["peer-a"] = { active_per_item_glow = { 1, 2, 3 } },
            },
            complete_glow_rehydrate = function()
                glow.completes = glow.completes + 1
            end,
            dbg = function() end, dbg_alert = function() end,
            trace = function() end, glow_log = function() end,
            printf = function() end,
        }
        local owner = Runtime.install(mod, deps)
        return {
            mod = mod, deps = deps, owner = owner, hooks = hooks,
            reconciles = reconciles, glow = glow,
        }
    end

    H.test("Cosmetics remote husk wield owner is exclusive and bounded", function()
        local entry, source = read(entry_path), read(module_path)
        H.equal(count(entry, "HUSK_WIELD_RUNTIME.install(mod, {"), 1)
        H.equal(count(entry,
            'mod:hook("SimpleHuskInventoryExtension", "_wield_slot"'), 0)
        H.equal(count(source,
            'mod:hook("SimpleHuskInventoryExtension", "_wield_slot"'), 1)
        for _, forbidden in ipairs({
            "network_register", "network_send", "mod:command(", "mod.update",
            "on_game_state_changed", "on_disabled", "on_unload", "mod:dofile(",
        }) do
            H.equal(source:find(forbidden, 1, true), nil, forbidden)
        end
    end)

    H.test("Cosmetics remote husk wield brackets vanilla and repaints", function()
        local f = fixture()
        H.equal(#f.hooks, 1)
        local equipment = {
            slots = {
                slot_melee = {
                    skin = "skin-a",
                    item_data = {
                        name = "weapon-a", template = "template_a",
                        right_hand_unit = "right", left_hand_unit = "left",
                    },
                },
            },
            right_hand_wielded_unit_3p = "right-3p",
            left_hand_wielded_unit_3p = "left-3p",
            right_hand_wielded_unit = "right-1p",
            left_hand_wielded_unit = "left-1p",
        }
        local saw_context
        local function vanilla()
            saw_context = Runtime.current(f.mod)
            return 1, 2, 3, 4, 5, 6, 7, 8
        end
        local values = { f.hooks[1].callback(
            vanilla, { _unit = "husk", _career_name = "career-a" },
            "world", equipment, "slot_melee", "u1", "u3") }
        H.equal(saw_context.wearer_peer, "peer-a")
        H.equal(saw_context.slot_name, "slot_melee")
        H.equal(Runtime.current(f.mod), nil)
        H.equal(#values, 8)
        H.equal(values[1], 1)
        H.equal(values[8], 8)
        H.equal(f.glow.binds, 4)
        H.equal(f.glow.applies, 1)
        H.equal(f.glow.completes, 1)
        H.equal(#f.reconciles, 1)
        H.equal(f.reconciles[1].reason, "husk-wield")
        H.equal(f.reconciles[1].pulse, false)
    end)

    H.test("Cosmetics remote husk wield restores context after vanilla error", function()
        local f = fixture()
        local equipment = {
            slots = {
                slot_melee = {
                    item_data = { name = "weapon-a", template = "template_a" },
                },
            },
        }
        local result = f.hooks[1].callback(
            function() error("planted") end,
            { _unit = "husk", _career_name = "career-a" },
            "world", equipment, "slot_melee")
        H.equal(result, nil)
        H.equal(Runtime.current(f.mod), nil)
        H.equal(#f.reconciles, 0)
        local again = Runtime.install(f.mod, f.deps)
        H.equal(again, f.owner)
        H.equal(#f.hooks, 1)
    end)
end
