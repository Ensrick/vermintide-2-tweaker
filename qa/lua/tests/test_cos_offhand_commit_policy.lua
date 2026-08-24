return function(H, repo_root)
    local path = repo_root
        .. "/cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_cos_offhand_commit_policy.lua"
    local Policy = assert(loadfile(path))()

    local function new_mod()
        local mod = { sent = {}, logs = {} }
        function mod:info(fmt, ...)
            self.logs[#self.logs + 1] = string.format(fmt, ...)
        end
        function mod._send_offhand_mesh(unit, key, hand, mesh)
            mod.sent[#mod.sent + 1] = { "mesh", unit, key, hand, mesh }
        end
        function mod._send_la_revert(unit, key, kind, vanilla, hand)
            mod.sent[#mod.sent + 1] = { "revert", unit, key, kind, vanilla, hand }
        end
        return mod
    end

    H.test("offhand commit persists without a live render owner", function()
        local mod, calls = new_mod(), 0
        local persistence = {
            commit_offhand_entry = function(entry)
                calls = calls + 1
                H.equal(entry.backend_id, "exact_instance")
                return true, "saved-mesh"
            end,
        }
        local count = Policy.drain(mod, {{
            backend_id = "exact_instance",
            hand_field = "left_hand_unit",
            offhand_unit = "units/offhand_a",
            player_unit = nil,
        }}, persistence, nil, function() return false end)
        H.equal(count, 1)
        H.equal(calls, 1)
        H.equal(#mod.sent, 0)
        H.equal(mod._la_self_rebroadcast_pending, true)
    end)

    H.test("Apply completion commits only the exact backend item without peer delivery", function()
        local committed = {}
        local persistence = {
            commit_offhand_entry = function(entry)
                committed[#committed + 1] = {
                    backend_id = entry.backend_id,
                    hand_field = entry.hand_field,
                    skin_key = entry.skin_key,
                }
                return true, "saved-mesh"
            end,
        }
        local count = Policy.commit_for_backend({
            ["item_a|left_hand_unit"] = {
                backend_id = "item_a",
                hand_field = "left_hand_unit",
                skin_key = "axe_blue_skin",
                offhand_unit = "units/axe_blue",
            },
            ["item_b|left_hand_unit"] = {
                backend_id = "item_b",
                hand_field = "left_hand_unit",
                skin_key = "axe_red_skin",
                offhand_unit = "units/axe_red",
            },
        }, persistence, "item_a")
        H.equal(count, 1)
        H.equal(#committed, 1)
        H.equal(committed[1].backend_id, "item_a")
        H.equal(committed[1].hand_field, "left_hand_unit")
        H.equal(committed[1].skin_key, "axe_blue_skin")
    end)

    H.test("Apply completion rejects a missing exact backend identity", function()
        local calls = 0
        local count = Policy.commit_for_backend({{
            backend_id = "item_a",
            hand_field = "left_hand_unit",
            offhand_unit = "units/axe_blue",
        }}, { commit_offhand_entry = function()
            calls = calls + 1
            return true
        end }, nil)
        H.equal(count, 0)
        H.equal(calls, 0)
    end)

    H.test("live offhand peer delivery emits both item namespaces once", function()
        local mod = new_mod()
        local persistence = {
            commit_offhand_entry = function() return true, "saved-mesh" end,
        }
        local owner = {}
        local count = Policy.drain(mod, {{
            backend_id = "exact_instance",
            hand_field = "left_hand_unit",
            offhand_unit = "units/offhand_a",
            player_unit = owner,
            weapon_key = "cwv_weapon",
            template_key = "base_template",
        }}, persistence, nil, function(unit) return unit == owner end)
        H.equal(count, 1)
        H.equal(#mod.sent, 2)
        H.equal(mod.sent[1][1], "mesh")
        H.equal(mod.sent[1][3], "cwv_weapon")
        H.equal(mod.sent[2][3], "base_template")
        H.equal(mod._la_self_rebroadcast_pending, nil)
    end)

    H.test("failed exact commit does not arm replay", function()
        local mod = new_mod()
        local count = Policy.drain(mod, {{
            backend_id = "",
            hand_field = "left_hand_unit",
            player_unit = nil,
        }}, { commit_offhand_entry = function() return false, "invalid-backend-id" end },
            nil, function() return false end)
        H.equal(count, 0)
        H.equal(mod._la_self_rebroadcast_pending, nil)
    end)
end
