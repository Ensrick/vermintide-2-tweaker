return function(H, repo_root)
    local module_path = repo_root
        .. "/character_weapon_variants/scripts/mods/character_weapon_variants/_cwv_exact_pair_state.lua"
    local main_path = repo_root
        .. "/character_weapon_variants/scripts/mods/character_weapon_variants/character_weapon_variants.lua"

    local function read(path)
        local file = assert(io.open(path, "rb"))
        local source = file:read("*a")
        file:close()
        return source
    end

    local function fixture()
        local handler, sent
        local mod = {
            network_register = function(_, _, callback) handler = callback end,
            network_send = function(_, channel, target, schema, op, slot, skin)
                sent = { channel, target, schema, op, slot, skin }
            end,
        }
        local om = {}
        assert(loadfile(module_path))().install(mod, om)
        return om, function() return handler end, function() return sent end
    end

    H.test("CWV #567 exact-pair protocol is VMF-only and transition-driven", function()
        local source = read(module_path)
        H.truthy(source:find('local CHANNEL = "cwv_exact_pair_state_v1"', 1, true))
        H.equal(source:find("rawget(NetworkLookup", 1, true), nil)
        H.equal(source:find("NetworkLookup.weapon_skins", 1, true), nil)
        H.equal(source:find("mod.update", 1, true), nil)
        local om, _, sent = fixture()
        H.equal(om._exact_pair_schema, 1)
        H.truthy(om._exact_pair_skin_predicate(
            "cwv_es_sword_and_mace_wpn_emp_sword_02_t1_wpn_emp_mace_03_t1"))
        H.equal(sent()[4], "query")
    end)

    H.test("CWV #567 receiver restores exact skin and hand order to a live husk", function()
        local om, handler = fixture()
        local skin = "cwv_es_sword_and_mace_wpn_emp_sword_02_t1_wpn_emp_mace_03_t1"
        local unit = {}
        local calls = {}
        local inv = {
            owner_unit = unit,
            _equipment = {
                wielded_slot = "slot_melee",
                slots = {
                    slot_melee = {
                        skin = nil,
                        item_data = { name = "es_dual_wield_hammer_sword" },
                    },
                },
            },
            add_equipment = function(self, slot, item, applied_skin)
                calls[#calls + 1] = { "add", slot, item, applied_skin }
                self._equipment.slots[slot].skin = applied_skin
            end,
            wield = function(_, slot) calls[#calls + 1] = { "wield", slot } end,
        }

        local old_managers, old_unit, old_script_unit = Managers, Unit, ScriptUnit
        Managers = { player = {
            player_from_peer_id = function() return { player_unit = unit } end,
        } }
        Unit = { alive = function(candidate) return candidate == unit end }
        ScriptUnit = { extension = function() return inv end }
        handler()("remote-peer", 1, "state", "slot_melee", skin)
        Managers, Unit, ScriptUnit = old_managers, old_unit, old_script_unit

        H.equal(calls[1][1], "add")
        H.equal(calls[1][2], "slot_melee")
        H.equal(calls[1][3], "es_dual_wield_hammer_sword")
        H.equal(calls[1][4], skin)
        H.equal(calls[2][1], "wield")
        H.equal(om._exact_pair_state_by_peer["remote-peer"].slot_melee, skin)
        handler()("remote-peer", 1, "clear", "slot_melee", "")
        H.equal(om._exact_pair_state_by_peer["remote-peer"].slot_melee, nil)
    end)

    H.test("CWV #567 exact state is wired into every reconstruction surface", function()
        local source = require("cwv_source").combined(repo_root)
        for _, marker in ipairs({
            '_exact_pair_publish_inventory(self, "wield")',
            '_exact_pair_publish_inventory(self, "game_object_initialized")',
            '_exact_pair_publish_inventory(self, "spawn_resynced_loadout")',
            '_exact_pair_publish_local("hot_join_sync")',
            '_exact_pair_query("gameplay_enter")',
            '_exact_pair_on_husk_wield(self, slot_name)',
            '_om.exact_appearance.resolve({',
        }) do
            H.truthy(source:find(marker, 1, true), "missing integration marker: " .. marker)
        end
    end)
end
