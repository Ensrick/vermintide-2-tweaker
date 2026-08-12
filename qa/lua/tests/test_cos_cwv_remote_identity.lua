return function(H, repo_root)
    local bridge = dofile(repo_root
        .. "/cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_cos_cwv_peer_identity.lua")

    local allowed = { cwv_es_dual_axes = true }
    local function provider(overrides)
        local descriptor = {
            provider = "cwv",
            variant_key = "cwv_es_dual_axes",
            base_item_key = "dr_dual_wield_axes",
            fingerprint = "a1:test",
        }
        for key, value in pairs(overrides or {}) do descriptor[key] = value end
        return {
            schema = bridge.SCHEMA,
            resolve_peer = function(peer, slot, base)
                H.equal(peer, "peer-rain")
                H.equal(slot, "slot_melee")
                H.equal(base, "dr_dual_wield_axes")
                return descriptor, "exact"
            end,
        }
    end

    local args = {
        base_item_type = "dr_dual_axes",
        wearer_peer = "peer-rain",
        slot_name = "slot_melee",
        base_item_key = "dr_dual_wield_axes",
        allowed_item_types = allowed,
    }

    H.test("exact CWV peer identity selects the CWV dual compatibility pool", function()
        args.provider = provider()
        local item_type, state = bridge.resolve_item_type(args)
        H.equal(item_type, "cwv_es_dual_axes")
        H.equal(state, "exact")
    end)

    H.test("missing, stale, foreign, and unregistered identity fail closed", function()
        args.provider = nil
        H.equal(bridge.resolve_item_type(args), "dr_dual_axes")

        args.provider = provider({ base_item_key = "dr_1h_axes" })
        local item_type, state = bridge.resolve_item_type(args)
        H.equal(item_type, "dr_dual_axes")
        H.equal(state, "descriptor_mismatch")

        args.provider = provider({ provider = "other" })
        item_type, state = bridge.resolve_item_type(args)
        H.equal(item_type, "dr_dual_axes")
        H.equal(state, "descriptor_mismatch")

        args.provider = provider({ variant_key = "cwv_unknown_dual" })
        item_type, state = bridge.resolve_item_type(args)
        H.equal(item_type, "dr_dual_axes")
        H.equal(state, "unregistered_variant")
    end)

    H.test("provider errors and non-exact states retain the vanilla family", function()
        args.provider = {
            schema = bridge.SCHEMA,
            resolve_peer = function() error("boom") end,
        }
        local item_type, state = bridge.resolve_item_type(args)
        H.equal(item_type, "dr_dual_axes")
        H.equal(state, "provider_error")

        args.provider = {
            schema = bridge.SCHEMA,
            resolve_peer = function() return nil, "native" end,
        }
        item_type, state = bridge.resolve_item_type(args)
        H.equal(item_type, "dr_dual_axes")
        H.equal(state, "native")
    end)

    H.test("runtime sources wire the validated CWV descriptor without a new RPC", function()
        local function read(path)
            local file = assert(io.open(path, "rb"))
            local source = file:read("*a")
            file:close()
            return source
        end
        -- #1159: the husk item-type resolution that consumes the CWV descriptor
        -- moved into the equipment-assembly owner with the get_item_units seam.
        local cos = read(repo_root
            .. "/cosmetics_tweaker/scripts/mods/cosmetics_tweaker/cosmetics_tweaker.lua")
            .. read(repo_root .. "/cosmetics_tweaker/scripts/mods/"
                .. "cosmetics_tweaker/_cos_equipment_assembly.lua")
        local cwv = read(repo_root
            .. "/character_weapon_variants/scripts/mods/character_weapon_variants/_cwv_item_identity_transport_owner.lua")
        H.truthy(cwv:find("mod._cwv_peer_appearance = {", 1, true))
        H.truthy(cos:find("mod._cos_cwv_peer_identity.resolve_husk", 1, true))
        H.truthy(cos:find("item_data, mod._independent_dual_item_types", 1, true))
        H.equal(cos:find('network_register("cos_cwv_peer_identity', 1, true), nil)
    end)
end
