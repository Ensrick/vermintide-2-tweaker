-- Offline proof for #579: the per-hand husk write for a generated Dual Axes
-- pair, reproducing the 2026-09-21 FAIL shape (cwv 0.1.540-dev) and the fixed
-- shape.
--
-- Layer 1: the #914 human-only peer gate (real _cwv_peer_resolver.lua) refuses
--   the bare `{ peer_id = ... }` owner the old regression stub used ("owner not
--   human") and admits a RemotePlayer-shaped owner (remote_player.lua:8,135-145).
-- Layer 2: the real _cwv_husk_path.lua re-key. Without an exact descriptor the
--   skin branch reads ONE primary skin for both hands, and a generated pair
--   mirrors right into left (_cwv_illusion_families.lua:326), so the offhand
--   collapses onto the primary illusion. With the exact descriptor each hand
--   carries its own authored unit, and the re-key log names the identity state.
-- Layer 3: the peer gate composed with the real lifecycle ledger, the way the
--   identity transport owner composes them, drives the adapter FAIL -> PASS.
-- Layer 4: the shipped regression check builds the RemotePlayer-shaped owner.
return function(H, repo_root)
    local mod_root = repo_root
        .. "/character_weapon_variants/scripts/mods/character_weapon_variants/"
    local Resolver = assert(loadfile(mod_root .. "_cwv_peer_resolver.lua"))()
    local Lifecycle = assert(loadfile(mod_root .. "_cwv_appearance_lifecycle.lua"))()

    local function read(path)
        local file = assert(io.open(path, "rb"))
        local source = file:read("*a")
        file:close()
        return source
    end

    local BASE = "fix_dual_base"
    local HATCHET = "units/weapons/player/wpn_fix_hatchet/wpn_fix_hatchet"
    local AXE_A = "units/weapons/player/wpn_fix_axe_a/wpn_fix_axe_a"
    local AXE_B = "units/weapons/player/wpn_fix_axe_b/wpn_fix_axe_b"
    local PAIR = {
        item_key = "cwv_fix_dual_axes",
        base_weapon = BASE,
        careers = { "es_fix" },
        right_hand_unit = HATCHET,
        left_hand_unit = HATCHET,
        item_type = "cwv_fix_dual_axes",
    }
    local SKIN_A = "cwv_fix_dual_axes_skin_a"
    local SKIN_B = "cwv_fix_dual_axes_skin_b"
    local PEER = "peer-579"
    -- The receiver-side reconstruction of a pair with DISTINCT illusions.
    local EXACT = {
        provider = "cwv",
        variant_key = PAIR.item_key,
        base_item_key = BASE,
        skin = SKIN_A,
        offhand_skin = SKIN_B,
        right_hand_unit = AXE_A,
        left_hand_unit = AXE_B,
        fingerprint = "a1:fix579",
    }

    -- Swap the stub globals in around a call, restore after (repo pattern:
    -- test_cwv_husk_adapter.lua).
    local GLOBAL_KEYS = {
        "printf", "ScriptUnit", "Unit", "ItemMasterList", "WeaponSkins",
        "Weapons", "Managers", "Application", "NetworkLookup",
    }
    local function with_env(env, fn)
        local saved = {}
        for _, key in ipairs(GLOBAL_KEYS) do
            saved[key] = _G[key]
            _G[key] = env[key]
        end
        local ok, err = pcall(fn)
        for _, key in ipairs(GLOBAL_KEYS) do
            _G[key] = saved[key]
        end
        if not ok then error(err, 0) end
    end

    -- Fresh husk-path install: om table + captured printf lines. Generated
    -- pair skins carry the same unit in both hands, exactly as the Dual Axes
    -- generator writes them.
    local function fixture()
        local om = { HUSK_OVERRIDE_REF = "cwv_husk_override_units" }
        local lines = {}
        local env = {
            printf = function(fmt, ...) lines[#lines + 1] = string.format(fmt, ...) end,
            ScriptUnit = {
                has_extension = function() return false end,
                extension = function() return nil end,
            },
            Unit = { alive = function() return true end },
            ItemMasterList = { [BASE] = { can_wield = { "dr_other" } } },
            WeaponSkins = { skins = {
                [SKIN_A] = { right_hand_unit = AXE_A, left_hand_unit = AXE_A },
                [SKIN_B] = { right_hand_unit = AXE_B, left_hand_unit = AXE_B },
            } },
            Weapons = {},
            Managers = { package = {
                load = function() end,
                has_loaded = function() return true end,
            } },
            Application = { can_get = function() return true end },
            NetworkLookup = { anims = {} },
        }
        with_env(env, function()
            assert(loadfile(mod_root .. "_cwv_husk_path.lua"))()(nil, {
                om = om,
                variant_definitions = { PAIR },
                find_def = function(key) return key == PAIR.item_key and PAIR or nil end,
                is_unit = function(u) return u ~= nil end,
                apply_cwv_hand_transform = function() return true end,
                triplet_text = function() return "t" end,
            })
        end)
        return om, lines, env
    end

    -- The exact adapter the entry hook calls once per hand, driven the way the
    -- shipped regression check drives it.
    local function drive(om, env, owner)
        local item_units = { skin = SKIN_A, right_hand_unit = HATCHET, left_hand_unit = HATCHET }
        local suppress = {}
        with_env(env, function()
            suppress.right = om._husk_adapter_pre("right", {}, item_units, "slot_melee",
                { name = BASE }, owner)
            suppress.left = om._husk_adapter_pre("left", {}, item_units, "slot_melee",
                { name = BASE }, owner)
        end)
        return item_units, suppress
    end

    local function joined(lines)
        return table.concat(lines, "\n")
    end

    local function human_owner()
        -- RemotePlayer contract: peer_id field, local_player_id(), network_id(),
        -- is_player_controlled() (remote_player.lua:8,135-145).
        local owner = { peer_id = PEER, _local_player_id = 1, _player_controlled = true }
        function owner:local_player_id() return self._local_player_id end
        function owner:network_id() return self.peer_id end
        function owner:is_player_controlled() return self._player_controlled end
        return owner
    end

    H.test("CWV #579 peer gate refuses a bare peer_id owner and admits the RemotePlayer shape", function()
        local unit = {}
        local bare = { peer_id = PEER }
        local player, reason = Resolver.owner({ owner = function() return bare end }, unit)
        H.equal(player, nil, "a table with only peer_id is not a human transport identity")
        H.equal(reason, "owner not human")
        H.equal(Resolver.player_peer_id(bare), PEER,
            "the peer id itself was never the problem; the human gate was")

        local human = human_owner()
        local resolved, source = Resolver.owner({ owner = function() return human end }, unit)
        H.equal(resolved, human)
        H.equal(source, "owner")
        H.equal(Resolver.player_peer_id(resolved), PEER)
    end)

    H.test("CWV #579 without exact identity the skin branch writes the primary skin on both hands", function()
        local om, lines, env = fixture()
        om._husk_identity_descriptor = function() return nil, "none" end
        local units, suppress = drive(om, env, {})
        H.equal(suppress.right, false)
        H.equal(suppress.left, false)
        H.equal(units.right_hand_unit, AXE_A)
        H.equal(units.left_hand_unit, AXE_A,
            "the offhand collapses onto the primary skin's mirrored left (2026-09-21 log shape)")
        local all = joined(lines)
        H.truthy(all:find("[cwv:474] husk re-keyed hand=right base=" .. BASE
            .. " career=nil via skin (skin=" .. SKIN_A .. " identity=none) -> " .. AXE_A, 1, true),
            "the re-key line must name the identity state for the right hand")
        H.truthy(all:find("[cwv:474] husk re-keyed hand=left base=" .. BASE
            .. " career=nil via skin (skin=" .. SKIN_A .. " identity=none) -> " .. AXE_A, 1, true),
            "the re-key line must name the identity state for the left hand")
    end)

    H.test("CWV #579 with the exact descriptor each hand carries its own authored skin", function()
        local om, lines, env = fixture()
        om._husk_identity_descriptor = function() return EXACT, "exact" end
        local units, suppress = drive(om, env, {})
        H.equal(suppress.right, false)
        H.equal(suppress.left, false)
        H.equal(units.right_hand_unit, AXE_A)
        H.equal(units.left_hand_unit, AXE_B, "the offhand keeps the illusion saved for THAT hand")
        local all = joined(lines)
        H.truthy(all:find("hand=left base=" .. BASE .. " career=nil via identity (skin="
            .. SKIN_A .. " identity=exact) -> " .. AXE_B, 1, true),
            "the re-key line must show the identity branch for the offhand")
    end)

    H.test("CWV #579 real gate plus ledger: bare stub collapses the pair, RemotePlayer shape keeps both hands", function()
        local lifecycle = Lifecycle.new({
            resolve_local = function() return nil end,
            resolve_remote = function(payload)
                return payload.item_key == PAIR.item_key and EXACT or nil
            end,
        })
        local _, descriptor = lifecycle:accept(PEER, Lifecycle.SCHEMA, {
            slot = "slot_melee", provider = "cwv",
            item_key = PAIR.item_key, base_item_key = BASE,
            skin_key = SKIN_A, offhand_skin_key = SKIN_B,
            fingerprint = EXACT.fingerprint,
        })
        H.equal(descriptor, EXACT, "the ledger holds the exact pair for the peer")

        -- The identity transport owner's composition
        -- (_cwv_item_identity_transport_owner.lua:354-372): resolve the husk
        -- owner through the peer gate, then look the descriptor up by peer id.
        local fake_owner = {}
        local function resolver_for(owner)
            local player_manager = { owner = function(_, unit)
                return unit == fake_owner and owner or nil
            end }
            return function(owner_unit_3p, slot_name, base_name, hinted_player)
                local player = Resolver.husk_owner(player_manager, owner_unit_3p, hinted_player)
                return lifecycle:descriptor(Resolver.player_peer_id(player), slot_name, base_name)
            end
        end

        -- FAIL shape: the 0.1.540-dev stub is refused, identity resolves to
        -- "none", the offhand takes the primary skin.
        local om, _, env = fixture()
        om._husk_identity_descriptor = resolver_for({ peer_id = PEER })
        local units = drive(om, env, fake_owner)
        H.equal(units.right_hand_unit, AXE_A)
        H.equal(units.left_hand_unit, AXE_A, "bare stub: the pair collapses to one model")

        -- PASS shape: a RemotePlayer-shaped owner reaches the exact descriptor.
        local om2, lines2, env2 = fixture()
        om2._husk_identity_descriptor = resolver_for(human_owner())
        local units2, suppress2 = drive(om2, env2, fake_owner)
        H.equal(suppress2.right, false)
        H.equal(suppress2.left, false)
        H.equal(units2.right_hand_unit, AXE_A)
        H.equal(units2.left_hand_unit, AXE_B, "human owner: each hand keeps its own illusion")
        H.truthy(joined(lines2):find("identity=exact", 1, true))
    end)

    H.test("CWV #579 shipped check drives the husk adapter with a RemotePlayer-shaped owner", function()
        local source = read(mod_root .. "_cwv_regression_identity.lua")
        local start = assert(source:find(
            '_rt_register("issue579_dual_axes_preview_and_husk_skin_continuity"', 1, true))
        local finish = source:find("_rt_register(", start + 1, true) or #source
        local check = source:sub(start, finish)
        H.truthy(check:find("function human_owner:is_player_controlled()", 1, true),
            "the check's owner must answer the #914 human gate")
        H.truthy(check:find("function human_owner:local_player_id()", 1, true))
        H.truthy(check:find("function human_owner:network_id()", 1, true))
        H.truthy(check:find("if unit == fake_owner then return human_owner end", 1, true))
        H.equal(check:find("return { peer_id = peer_id }", 1, true), nil,
            "the bare peer_id stub the #914 gate refuses must not come back")
        H.truthy(check:find("_om._husk_unit_spawnable", 1, true),
            "the check prefers illusion meshes resident on this peer")
        local husk = read(mod_root .. "_cwv_husk_path.lua")
        H.truthy(husk:find("via %s (skin=%s identity=%s) -> %s", 1, true),
            "the re-key line must carry the identity state")
    end)
end
