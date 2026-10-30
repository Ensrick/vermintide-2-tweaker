-- #579: detached two-endpoint proof of the INSTALLED production chain.
-- This does not emulate VMF serialization/delivery, resource residency, or
-- rendering. The private transport delivers captured network_send arguments to
-- the callback captured by the other actual network_register. The native spawn
-- spy records inputs to the actual GearUtils wrapper, not engine mesh output.
return function(H, root, controls)
    controls = controls or {}
    local cwv = root .. "/character_weapon_variants/scripts/mods/character_weapon_variants/"
    local cos = root .. "/cosmetics_tweaker/scripts/mods/cosmetics_tweaker/"
    local function read(path)
        local f = assert(io.open(path, "rb")); local s = f:read("*a"); f:close()
        return (s:gsub("\r\n", "\n"))
    end
    local function load(path, env)
        local source
        local function replace(needle, replacement)
            source = source or read(path)
            local first = assert(source:find(needle, 1, true), "mutation boundary absent: " .. path)
            assert(not source:find(needle, first + #needle, true), "mutation boundary ambiguous: " .. path)
            source = source:sub(1, first - 1) .. replacement .. source:sub(first + #needle)
        end
        if controls.drop_publish and path:find("_cwv_item_identity_transport_owner.lua", 1, true) then
            replace('_send_identity_slots({ [equipment_to_spawn.slot_id] = equipment_to_spawn },\n'
                .. '\t\t\t\t\t"spawn_resynced_loadout", false, nil, true)', '-- detached mutation: publish disconnected')
        end
        if controls.drop_receiver and path:find("_cwv_item_identity_transport_owner.lua", 1, true) then
            replace('mod:network_register("cwv_item_identity", _om._cwv_receive_identity)',
                'mod:network_register("cwv_item_identity", function() end)')
        end
        if controls.drop_hand_transaction and path:find("_cwv_musket_equip_surface.lua", 1, true) then
            replace('if not owner_unit_1p and _om._husk_spawn_adapter_transaction then',
                'if false then -- detached mutation: transaction disconnected')
        end
        local chunk = source and assert(loadstring(source, "@mutated-" .. path)) or assert(loadfile(path))
        if env then setfenv(chunk, env) end
        return chunk()
    end
    local function copy(value, seen)
        if type(value) ~= "table" then return value end
        seen = seen or {}; if seen[value] then return seen[value] end
        local out = {}; seen[value] = out
        for k, v in pairs(value) do out[k] = copy(v, seen) end
        return out
    end
    local function pack(...) return { n = select("#", ...), ... } end
    local Lifecycle = load(cwv .. "_cwv_appearance_lifecycle.lua")
    local Exact = load(cwv .. "_cwv_exact_appearance.lua")
    local Descriptor = load(root .. "/tools/shared_lib/_lib_appearance_descriptor.lua")
    local Appearance = load(cwv .. "_cwv_combat_style_appearance.lua")
    local Styles = load(cwv .. "_cwv_combat_styles.lua")
    local Names = load(cos .. "_cos_offhand_names.lua")
    local Family = load(cos .. "_cos_cwv_family_contract.lua")
    local Preload = load(cos .. "_cos_offhand_preload_lifecycle.lua")
    local om_catalog = {}
    for _, name in ipairs({ "greataxe", "dawi_maces", "crowbill_family",
            "crowbill_hammer_mode", "crowbill_runtime" }) do
        om_catalog[name] = load(cwv .. "_cwv_" .. name .. ".lua")
    end
    local defs = load(cwv .. "_cwv_variant_catalog.lua")({ om = om_catalog }).definitions
    local function find_def(key)
        for _, def in ipairs(defs) do if def.item_key == key then return def end end
    end
    local FAMILIES = { "cwv_es_dual_axes", "cwv_wh_dual_axes" }
    -- Independent authored expectations: native 6.13 weapon_skins.lua:22-32,
    -- 49-59. These are not read back from the payload/descriptor under test.
    -- Fixture generated rows mirror the declared CWV Dual Axes generator; both
    -- hands of each single illusion are identical, deliberately exposing loss
    -- of the separate committed left-skin axis.
    local AXE_RIGHT = "units/weapons/player/wpn_axe_02_t2/wpn_axe_02_t2"
    local AXE_LEFT = "units/weapons/player/wpn_axe_03_t1/wpn_axe_03_t1"
    local BASE = "dr_dual_wield_axes"
    local BASE_RIGHT = "units/weapons/player/wpn_dw_axe_01_t1/wpn_dw_axe_01_t1"
    local BASE_LEFT = "units/weapons/player/wpn_dw_axe_01_t1/wpn_dw_axe_01_t1"
    local BID = "qa-579-committed-instance"
    local world_resolver_source = read(cwv .. "character_weapon_variants.lua")
    local wa = assert(world_resolver_source:find("_om._cwv_resolve_world_descriptor = function(", 1, true))
    local wb = assert(world_resolver_source:find("\n-- Husk display / transform / ledger machinery", wa, true))
    local world_resolver_body = world_resolver_source:sub(wa, wb - 1)
    local identity_source = read(cwv .. "_cwv_item_registration_owner.lua")
    local ia = assert(identity_source:find("local function _registered_cwv_key(candidate)", 1, true))
    local ib = assert(identity_source:find("\nlocal function _build_entry(def, backend_id)", ia, true))
    local identity_body = identity_source:sub(ia, ib - 1)

    local function fixture(family)
        local s = { endpoints = {}, queue = {}, traffic = {}, drops = {}, family = family }
        s.right_skin = family .. "_wh_1h_axe_skin_02"
        s.left_skin = family .. "_wh_1h_axe_skin_03"
        local function endpoint(id, remote)
            local e = { id = id, remote = remote, hooks = {}, network = {},
                native = {}, rewields = 0, writes = 0, spawns = {}, logs = {} }
            e.residency_boot = { logs = {}, hooks = {} }
            local residency_booting = false
            e.owner = {}; e.local_unit = {}
            e.player = { peer_id = remote, _local_player_id = 1,
                player_unit = e.owner, is_player_controlled = function() return true end,
                local_player_id = function() return 1 end }
            e.items = { [BASE] = { name = BASE, item_type = "dr_dual_axes",
                right_hand_unit = BASE_RIGHT, left_hand_unit = BASE_LEFT,
                template = "dual_wield_axes_template_1", can_wield = { "dr_slayer" } } }
            e.skins = { skins = {}, skin_combinations = {} }
            for _, key in ipairs(FAMILIES) do
                e.items[key] = { name = BASE, item_type = key }
                local rows = {}
                for _, authored in ipairs({ { "02", AXE_RIGHT }, { "03", AXE_LEFT } }) do
                    local skin = key .. "_wh_1h_axe_skin_" .. authored[1]
                    e.items[skin] = { item_type = "weapon_skin", matching_item_key = key,
                        cwv_owner_item_type = key, right_hand_unit = authored[2],
                        left_hand_unit = authored[2], rarity = "exotic" }
                    e.skins.skins[skin] = { right_hand_unit = authored[2],
                        left_hand_unit = authored[2], rarity = "exotic" }
                    rows[#rows + 1] = skin
                end
                e.skins.skin_combinations[key .. "_skins"] = { exotic = rows }
            end
            local native_template = { name = "dual_wield_axes_template_1" }
            e.env = setmetatable({ ItemMasterList = e.items, WeaponSkins = e.skins,
                Weapons = { dual_wield_axes_template_1 = native_template },
                CareerSettings = false, LoadoutUtils = false, CosmeticUtils = false,
                PlayerManager = false, NetworkLookup = { anims = {} },
                Unit = { alive = function(u) return u ~= nil end },
                Application = { can_get = function() return true end },
                ScriptUnit = { has_extension = function() return nil end,
                    extension = function() return nil end },
                Managers = { player = { owner = function(_, unit)
                    if unit == e.owner then return e.player end
                end }, },
                printf = function(fmt, ...)
                    local target = residency_booting and e.residency_boot.logs or e.logs
                    target[#target + 1] = string.format(fmt, ...)
                end,
            }, { __index = _G })
            e.env._G = e.env
            local function register(kind, class, method, callback)
                local token = tostring(class) .. "." .. method
                assert(not e.hooks[token], "duplicate production hook " .. token)
                e.hooks[token] = callback
                e.hooks[token .. ":kind"] = kind
                if residency_booting then
                    e.residency_boot.hooks[#e.residency_boot.hooks + 1] = token
                end
            end
            e.cos_mod = { _cos = {}, info = function() end, debug = function() end,
                localize = function(_, key) return key end,
                get = function(_, key) return e.settings and e.settings[key] end,
                set = function(_, key, value)
                    e.settings = e.settings or {}; e.settings[key] = value; e.writes = e.writes + 1
                end,
                hook_safe = function() end }
            e.env.get_mod = function(name)
                if name == "cosmetics_tweaker" then
                    if e.provider_disconnected then return nil end
                    return e.cos_mod
                end
            end
            e.persist = load(cos .. "_la_persistence.lua", e.env)
            local catalog = load(cos .. "_cos_offhand_catalog.lua", e.env).install(e.cos_mod, {
                offhand_preload_lifecycle = Preload, offhand_names = Names,
                gk_set = {}, la_bridge = { registered = false }, cwv_family_contract = Family,
                custom_illusions = {}, skin_requires_unowned_dlc = function() return false end,
                dbg = function() end, dbg_alert = function() end, get_mod = e.env.get_mod,
                get_managers = function() return e.env.Managers end,
                application = e.env.Application, network_lookup = e.env.NetworkLookup,
                weapon_skins = e.skins, item_master_list = e.items, printf = e.env.printf,
            })
            load(cos .. "_cos_offhand_state_runtime.lua", e.env).install(e.cos_mod, {
                la_bridge = { registered = false }, la_persist = e.persist, offhand_names = Names,
                decorate_shield_option = catalog.decorate_shield_option,
                get_item_master_list = function() return e.items end,
                get_managers = function() return e.env.Managers end, get_mod = e.env.get_mod,
                offhand_options = catalog.offhand_options, offhand_selection = {},
                preload_offhand_for_option = catalog.preload_offhand_for_option,
                preload_offhand_package = catalog.preload_offhand_package,
            })
            e.catalog = catalog
            e.om = { exact_appearance = Exact, appearance_descriptor = Descriptor,
                combat_style_appearance = Appearance, combat_style_policy = Styles,
                appearance_lifecycle_policy = Lifecycle,
                cosmetic_skin_wire = load(cwv .. "_cwv_cosmetic_skin_wire.lua"), _skin_keys = {},
                identity_peer_pull = load(cwv .. "_cwv_identity_peer_pull.lua", e.env),
                identity_peer_cleanup = load(cwv .. "_cwv_identity_peer_cleanup.lua", e.env),
                peer_resolver = load(cwv .. "_cwv_peer_resolver.lua"),
                exact_wire_runtime = { install_damage = function() end },
                HUSK_OVERRIDE_REF = "qa579-private-residency",
            }
            -- Execute the source owner's complete registered-key ladder rather
            -- than substituting a UUID -> family answer. The fixture's two
            -- registered membership rows come from the real catalog above.
            local registered = {}
            for _, key in ipairs(FAMILIES) do
                assert(find_def(key) and not find_def(key).cwv_retired)
                registered[key] = true
            end
            local identity = assert(loadstring("return function(_om, _registered_keys)\n"
                .. identity_body .. "\nend", "@actual-registration-identity-ladder"))
            setfenv(identity, e.env); identity()(e.om, registered)
            local resolver = assert(loadstring("return function(_om, _find_def, _resolve_cwv_def)\n"
                .. world_resolver_body .. "\nend", "@actual-entry-world-resolver"))
            setfenv(resolver, e.env)
            resolver()(e.om, find_def, function() return nil end)
            -- The post-spawn owner requires this separate transform collaborator.
            -- Run its real selection policy; numerical transform authoring is
            -- outside this identity/spawn-input proof (no engine setters).
            local transform = load(cwv .. "_cwv_husk_transform_policy.lua").bind({
                find_def = find_def, resolve_def = function() return nil end,
                plan_transform = function() return { should_apply = false } end,
                model_by_unit = {}, hand_unit = Appearance.hand_unit,
            })
            e.om._cwv_select_husk_transform_def = transform.select
            e.om._cwv_husk_transform_apply_plan = transform.plan
            e.mod = { info = function() end, warning = function() end, debug = function() end,
                _cwv_rewield = { request_peer_rewield = function() e.rewields = e.rewields + 1 end },
                hook = function(_, class, method, cb) register("hook", class, method, cb) end,
                hook_safe = function(_, class, method, cb) register("safe", class, method, cb) end,
                network_register = function(_, name, cb)
                    assert(not e.network[name]); e.network[name] = cb
                end,
                network_send = function(_, name, recipient, schema, payload)
                    local row = { sender = id, name = name, recipient = recipient,
                        schema = schema, payload = copy(payload) }
                    if controls.drop_offhand_payload and row.payload.item_key == family then
                        row.payload.offhand_skin_key = ""
                    end
                    s.traffic[#s.traffic + 1] = row
                    s.queue[#s.queue + 1] = row
                end,
                dofile = function(_, path)
                    if path:find("_cwv_outrider_projectile_wire", 1, true) then
                        return { install = function() end } -- unrelated sibling owner
                    end
                    if path:find("_lib_network_lookup", 1, true) then return {} end
                    if path:find("_cwv_identity_descriptor_planner", 1, true) then
                        return load(cwv .. "_cwv_identity_descriptor_planner.lua", e.env)
                    end
                    error("unexpected module " .. path)
                end,
            }
            -- Keep the real catalogue and the owner's boot prefix distinct from
            -- the existing installed publish/receiver/spawn observations.
            residency_booting = true
            load(cwv .. "_cwv_husk_residency_owner.lua", e.env)(e.mod, {
                om = e.om, variant_definitions = defs })
            residency_booting = false
            local spawn_phase = load(cwv .. "_cwv_musket_equip_surface.lua", e.env)(e.mod, {
                om = e.om, dbg = function() end, variant_definitions = defs })
            spawn_phase()
            load(cwv .. "_cwv_husk_path.lua", e.env)(e.mod, {
                om = e.om, variant_definitions = defs, find_def = find_def,
                is_unit = function(unit) return unit ~= nil end,
                apply_cwv_hand_transform = function() return true end,
                triplet_text = function() return "detached" end,
            })
            e.om._install_husk_wield_hook(e.mod)
            load(cwv .. "_cwv_husk_spawn_transaction.lua", e.env)(e.mod, { om = e.om })
            load(cwv .. "_cwv_item_identity_transport_owner.lua", e.env)(e.mod, {
                om = e.om, find_def = find_def, custom_skin_keys = {} })
            e.slot = { slot_id = "slot_melee", skin = s.right_skin,
                item_data = { name = BASE, backend_id = BID, cwv_key = family } }
            e.native_template = native_template
            function e.commit(skin, unit)
                return e.persist.commit_offhand_entry({ backend_id = BID,
                    hand_field = "left_hand_unit", skin_key = skin, offhand_unit = unit })
            end
            function e.publish(kind, native)
                native = native or function(_, slot)
                    H.equal(slot.skin, nil, "native wire must not encode a CWV skin")
                    return "native-result", nil, "third", nil
                end
                local callback = assert(e.hooks["SimpleInventoryExtension._spawn_resynced_loadout"])
                return callback(native, {}, e.slot, false)
            end
            function e.spawn(hand, units, native)
                units = units or { right_hand_unit = BASE_RIGHT, left_hand_unit = BASE_LEFT }
                local callback = assert(e.hooks["GearUtils.spawn_inventory_unit"])
                native = native or function(_, got_hand, template, item_units)
                    e.spawns[#e.spawns + 1] = { hand = got_hand,
                        mesh = item_units[got_hand .. "_hand_unit"], template = template }
                    return { native_spawn = got_hand }, nil, nil, "fourth"
                end
                return callback(native, {}, hand, e.native_template, units, "slot_melee",
                    { name = BASE }, nil, e.owner, "unit_template", { detached = true }, 0.5, "material")
            end
            function e.wield(native)
                local callback = assert(e.hooks["SimpleHuskInventoryExtension._wield_slot"])
                local self = { _unit = e.owner, _player = e.player }
                local equipment = { slots = { slot_melee = { item_data = { name = BASE } } } }
                return callback(native or function()
                    e.spawn("right"); e.spawn("left"); return "native-wield-result"
                end, self, {}, equipment, "slot_melee", nil, e.owner)
            end
            e.provider_disconnected = controls.drop_provider and id == "owner-579"
            s.endpoints[id] = e
            return e
        end
        s.owner = endpoint("owner-579", "observer-579")
        s.observer = endpoint("observer-579", "owner-579")
        function s.drain()
            local delivered = 0
            while #s.queue > 0 do
                assert(delivered < 32, "unbounded detached message loop")
                local row = table.remove(s.queue, 1)
                for id, e in pairs(s.endpoints) do
                    if id ~= row.sender and (row.recipient == "others" or row.recipient == id) then
                        if not s.drops[id] then
                            assert(e.network[row.name], "missing actual registered receiver")(
                                row.sender, row.schema, row.payload)
                            delivered = delivered + 1
                        end
                    end
                end
            end
            return delivered
        end
        return s
    end

    local function establish(s)
        H.equal(s.owner.commit(s.left_skin, AXE_LEFT), true)
        local writes = s.owner.writes
        local provider = s.owner.cos_mod._cos.cwv_offhand_identity
        H.equal(provider(BID, s.family, "left_hand_unit"), s.left_skin)
        H.equal(s.owner.network.cwv_item_identity, s.owner.om._cwv_receive_identity,
            "actual network registration must be live receiver")
        H.equal(s.observer.network.cwv_item_identity, s.observer.om._cwv_receive_identity,
            "actual network registration must be live receiver")
        local returns = pack(s.owner.publish())
        H.deep_equal(returns, { n = 4, "native-result", nil, "third", nil })
        H.equal(s.owner.slot.skin, s.right_skin)
        H.equal(s.drain(), 2, "one exact send plus its ACK")
        H.equal(s.owner.writes, writes, "identity reads/delivery must not persist")
        H.equal(#s.traffic, 2)
        H.equal(s.traffic[1].payload.skin_key, s.right_skin)
        H.equal(s.traffic[1].payload.offhand_skin_key, s.left_skin,
            "committed offhand must traverse planner transport")
        H.equal(s.traffic[1].payload.right_hand_unit, nil)
        H.equal(s.traffic[1].payload.left_hand_unit, nil)
        local fields, bytes = 0, 0
        for _, value in pairs(s.traffic[1].payload) do
            H.equal(type(value), "string", "semantic payload has no path/table transport")
            fields = fields + 1; bytes = bytes + #value
        end
        H.equal(fields, 8); H.equal(#s.traffic[1].payload.fingerprint, 19)
        H.truthy(bytes < 500, "bounded semantic strings, not a VMF serializer proof")
        H.equal(s.observer.rewields, 1)
    end
    local function assert_hands(s, right, left)
        H.equal(s.observer.wield(), "native-wield-result")
        H.equal(s.observer.spawns[1].mesh, right, "authored right mesh at native spawn boundary")
        H.equal(s.observer.spawns[2].mesh, left, "authored left mesh at native spawn boundary")
    end
    for _, family in ipairs(FAMILIES) do
        H.test("579 installed committed-provider publish receiver GearUtils two hands " .. family, function()
            local s = fixture(family); establish(s); assert_hands(s, AXE_RIGHT, AXE_LEFT)
            local remote, state = s.observer.om._cwv_identity_descriptor_for_peer(
                "owner-579", "slot_melee", BASE)
            H.equal(state, "exact"); H.equal(remote.skin, s.right_skin)
            H.equal(remote.offhand_skin, s.left_skin)
            H.equal(remote.right_hand_unit, AXE_RIGHT); H.equal(remote.left_hand_unit, AXE_LEFT)
            s.owner.publish(); H.equal(s.drain(), 0); H.equal(#s.traffic, 2)
            H.equal(s.observer.rewields, 1, "duplicate equip must not request a second rebuild")
        end)
        H.test("579 actual catalog and persistence deny foreign or stale committed records " .. family, function()
            local s = fixture(family)
            local other = family == FAMILIES[1] and FAMILIES[2] or FAMILIES[1]
            H.equal(s.owner.commit(other .. "_wh_1h_axe_skin_03", AXE_LEFT), true)
            local provider = s.owner.cos_mod._cos.cwv_offhand_identity
            local skin, reason = provider(BID, family, "left_hand_unit")
            H.equal(skin, nil); H.equal(reason, "foreign_or_stale")
            H.equal(s.owner.commit(s.left_skin, "units/not-the-authored-left"), true)
            skin, reason = provider(BID, family, "left_hand_unit")
            H.equal(skin, nil); H.equal(reason, "foreign_or_stale")
            local writes = s.owner.writes
            s.owner.publish(); s.drain()
            H.equal(s.traffic[1].payload.offhand_skin_key, "")
            assert_hands(s, AXE_RIGHT, AXE_RIGHT)
            H.equal(s.owner.writes, writes, "rejected save is read-only, not rewritten")
        end)
        H.test("579 missing committed selection follows primary, never unrelated instance " .. family, function()
            local s = fixture(family)
            H.equal(s.owner.persist.commit_offhand_entry({ backend_id = "qa-other-instance",
                hand_field = "left_hand_unit", skin_key = s.left_skin, offhand_unit = AXE_LEFT }), true)
            local value, reason = s.owner.cos_mod._cos.cwv_offhand_identity(BID, family, "left_hand_unit")
            H.equal(value, nil); H.equal(reason, "follow_main")
            s.owner.publish(); s.drain()
            H.equal(s.traffic[1].payload.offhand_skin_key, "")
            assert_hands(s, AXE_RIGHT, AXE_RIGHT)
        end)
        for _, fault in ipairs({ "foreign-offhand", "missing-local-skin", "changed-local-mesh",
                "fingerprint", "schema", "base", "missing-offhand-axis" }) do
            H.test("579 actual registered receiver invalidates prior exact on " .. fault .. " " .. family, function()
                local s = fixture(family); establish(s)
                local payload = copy(s.traffic[1].payload)
                local schema = Lifecycle.SCHEMA
                if fault == "foreign-offhand" then
                    local other = family == FAMILIES[1] and FAMILIES[2] or FAMILIES[1]
                    payload.offhand_skin_key = other .. "_wh_1h_axe_skin_03"
                elseif fault == "missing-local-skin" then
                    s.observer.skins.skins[s.left_skin] = nil
                elseif fault == "changed-local-mesh" then
                    s.observer.skins.skins[s.left_skin].left_hand_unit = AXE_RIGHT
                elseif fault == "fingerprint" then payload.fingerprint = "a1:wrong"
                elseif fault == "schema" then schema = schema + 1
                elseif fault == "base" then payload.base_item_key = "es_handgun"
                elseif fault == "missing-offhand-axis" then payload.offhand_skin_key = nil end
                local before = #s.traffic
                s.owner.mod:network_send("cwv_item_identity", "observer-579", schema, payload)
                H.equal(s.drain(), 1)
                H.equal(#s.traffic, before + 1, "declined descriptor must not ACK")
                local descriptor, state = s.observer.om._cwv_identity_descriptor_for_peer(
                    "owner-579", "slot_melee", BASE)
                H.equal(descriptor, nil)
                H.equal(state, fault == "base" and "stale_base" or "unavailable")
                assert_hands(s, BASE_RIGHT, BASE_LEFT)
            end)
        end
        H.test("579 foreign peer cannot populate owner's slot " .. family, function()
            local s = fixture(family)
            s.owner.commit(s.left_skin, AXE_LEFT); s.owner.publish()
            s.queue[1].sender = "unrelated-peer"
            s.drain()
            local descriptor, state = s.observer.om._cwv_identity_descriptor_for_peer(
                "owner-579", "slot_melee", BASE)
            H.equal(descriptor, nil); H.equal(state, "none")
            assert_hands(s, BASE_RIGHT, BASE_LEFT)
        end)
        H.test("579 exact-to-native owner equip clears per-hand override " .. family, function()
            local s = fixture(family); establish(s)
            s.owner.slot.item_data.backend_id = nil; s.owner.slot.item_data.cwv_key = nil; s.owner.slot.skin = nil
            s.owner.publish(); H.equal(s.drain(), 1)
            local descriptor, state = s.observer.om._cwv_identity_descriptor_for_peer(
                "owner-579", "slot_melee", BASE)
            H.equal(descriptor, nil); H.equal(state, "native")
            assert_hands(s, BASE_RIGHT, BASE_LEFT)
        end)
        H.test("579 sender error preserves exact raw slot and settings without global patches " .. family, function()
            local s = fixture(family); s.owner.commit(s.left_skin, AXE_LEFT)
            local before, meta = {}, getmetatable(_G)
            for key, value in next, _G do before[key] = value end
            local slot_meta = { __index = { untouched = "inherited" } }
            setmetatable(s.owner.slot, slot_meta)
            local raw = {}; for key, value in next, s.owner.slot do raw[key] = value end
            local saved = copy(s.owner.persist.get_saved_offhands()); local writes = s.owner.writes
            local sentinel = {}; local ok, err = pcall(s.owner.publish, nil, function(_, slot)
                H.equal(rawget(slot, "skin"), nil); error(sentinel, 0)
            end)
            H.equal(ok, false); H.equal(err, sentinel)
            H.deep_equal(s.owner.slot, raw); H.equal(getmetatable(s.owner.slot), slot_meta)
            H.deep_equal(s.owner.persist.get_saved_offhands(), saved); H.equal(s.owner.writes, writes)
            for key, value in next, _G do H.equal(value, before[key], "global added/changed: " .. key) end
            for key, value in next, before do H.equal(rawget(_G, key), value, "global removed: " .. key) end
            H.equal(getmetatable(_G), meta)
        end)
        for _, prior in ipairs({ "raw", "inherited" }) do
            H.test("579 actual husk callback restores raw context after native error " .. prior .. " " .. family, function()
                local s = fixture(family); establish(s)
                local om, sentinel = s.observer.om, {}
                local existing = { prior = true }; local meta = { __index = { _appearance_husk_wield_context = existing } }
                setmetatable(om, meta)
                if prior == "raw" then rawset(om, "_appearance_husk_wield_context", existing) end
                local before = rawget(om, "_appearance_husk_wield_context")
                local called = 0
                local ok, err = pcall(s.observer.wield, function()
                    local active = rawget(om, "_appearance_husk_wield_context")
                    H.equal(active.owner_unit_3p, s.observer.owner)
                    H.equal(active.player, s.observer.player)
                    H.equal(active.slot_name, "slot_melee")
                    s.observer.spawn("right", nil, function(_, hand, _, units)
                        called = called + 1; H.equal(hand, "right")
                        H.equal(units.right_hand_unit, AXE_RIGHT)
                        error(sentinel, 0)
                    end)
                end)
                H.equal(ok, false); H.equal(err, sentinel)
                H.equal(rawget(om, "_appearance_husk_wield_context"), before)
                H.equal(getmetatable(om), meta); H.equal(om._appearance_husk_wield_context, existing)
                H.equal(#s.observer.spawns, 0); H.equal(called, 1)
            end)
        end
        H.test("579 actual hot-join hook retries are bounded and registered ACK drains " .. family, function()
            local s = fixture(family); s.owner.commit(s.left_skin, AXE_LEFT)
            local hook = assert(s.owner.hooks["GearUtils.hot_join_sync"])
            local equipment = { slots = { slot_melee = s.owner.slot } }
            s.drops["observer-579"] = true
            H.equal(hook(function(_, _, eq)
                H.equal(eq.slots.slot_melee.skin, nil); return "native-hot-join"
            end, "observer-579", s.owner.local_unit, equipment, {}), "native-hot-join")
            s.drain()
            H.equal(s.owner.om._appearance_lifecycle:pending_delivery_count(), 1)
            for _ = 1, 40 do s.owner.mod.update(Lifecycle.RETRY_INTERVAL); s.drain() end
            H.equal(s.owner.om._appearance_lifecycle:pending_delivery_count(), 0)
            H.equal(#s.traffic, 2 + Lifecycle.MAX_RETRY_ATTEMPTS)
            local bounded = #s.traffic
            for _ = 1, 40 do s.owner.mod.update(1); s.drain() end
            H.equal(#s.traffic, bounded)
            s.drops["observer-579"] = false
            hook(function() return "again" end, "observer-579", s.owner.local_unit, equipment, {})
            s.drain()
            H.equal(s.owner.om._appearance_lifecycle:pending_delivery_count(), 0)
            H.equal(s.observer.rewields, 2,
                "complete replay requests melee exact plus first native ranged; coalescer is separate")
            local after_ack = #s.traffic
            for _ = 1, 20 do s.owner.mod.update(1); s.drain() end
            H.equal(#s.traffic, after_ack)
            assert_hands(s, AXE_RIGHT, AXE_LEFT)
        end)
    end
end
