-- Pins the #154 husk-cache dual-namespace mirror: slot-keyed weapon-side LA
-- entries (update_cosmetic_slot illusion emits under "slot_melee"/"slot_ranged")
-- must become reachable under the wielded TEMPLATE key the husk mesh gate and
-- repaint actually read, and revert must sweep every alias.
return function(Harness, repo_root)
    local bridge = dofile(repo_root
        .. "/cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_cos_husk_cache_bridge.lua")

    local function entry(kind, key, hand_field)
        return { kind = kind, armoury_key = key, vanilla_key = "vanilla",
            hand_field = hand_field or "left_hand_unit", wearer_career = "es_mercenary" }
    end

    local function fake_mod(wearer, slot_name, template)
        local inv = {
            _equipment = { slots = { [slot_name] = {
                item_data = { template = template } } } },
        }
        local unit = { "unit" }
        local mod = {
            _la_equips_by_peer = {},
            _offhand_mesh_by_peer = {},
            _reconcile_calls = {},
            _revert_calls = {},
        }
        mod._la_reconcile = function(w, s, tag, allow_pulse)
            mod._reconcile_calls[#mod._reconcile_calls + 1] = { w, s, tag, allow_pulse }
            local eq = mod._la_equips_by_peer[w] and mod._la_equips_by_peer[w][s]
            if not eq then return false, "no-entry" end
            -- Mimic production: slot-namespace keys can never match an item
            -- (the weapon-identity guard), template keys apply.
            if bridge.WIELD_SLOTS[s] then return false, "wearer-not-spawned" end
            return true
        end
        mod._la_apply_revert_recv = function(w, s)
            mod._revert_calls[#mod._revert_calls + 1] = { w, s }
            if mod._la_equips_by_peer[w] then mod._la_equips_by_peer[w][s] = nil end
        end
        local deps = {
            managers = function()
                return { player = { player_from_peer_id = function(_, peer)
                    if peer == wearer then return { player_unit = unit } end
                end } }
            end,
            script_unit = { has_extension = function(u, name)
                if u == unit and name == "inventory_system" then return inv end
            end },
            printf = function() end,
        }
        return mod, deps, inv
    end

    Harness.test("cos #154 wielded_template reads the equipped slot's template", function()
        local inv = { _equipment = { slots = { slot_melee = {
            item_data = { template = "bastard_sword_template" } } } } }
        Harness.equal(bridge.wielded_template(inv, "slot_melee"), "bastard_sword_template")
        Harness.equal(bridge.wielded_template(inv, "slot_ranged"), nil)
        Harness.equal(bridge.wielded_template(nil, "slot_melee"), nil)
        Harness.equal(bridge.wielded_template({ _equipment = { slots = {
            slot_melee = { item_data = { template = "" } } } } }, "slot_melee"), nil)
    end)

    Harness.test("cos #154 mirror aliases slot entries under the template key", function()
        local e = entry("illusion", "Kruber_key")
        local store = { peer = { slot_melee = e } }
        local vstore = { peer = { bastard_sword_template = { left_hand_unit = "stale" } } }
        local book = {}
        Harness.equal(bridge.mirror(store, vstore, book, "peer", "slot_melee",
            "bastard_sword_template"), "mirrored")
        Harness.equal(store.peer.bastard_sword_template, e,
            "mirror must store the identical entry table (identity alias)")
        Harness.equal(book["peer|bastard_sword_template"], "slot_melee")
        Harness.equal(vstore.peer.bastard_sword_template.left_hand_unit, nil,
            "mirror must clear the parallel vanilla mesh for the mirrored hand")
        Harness.equal(bridge.mirror(store, vstore, book, "peer", "slot_melee",
            "bastard_sword_template"), "already")
    end)

    Harness.test("cos #154 direct template writes always beat mirrors", function()
        local slot_entry = entry("illusion", "newer_slot_key")
        local direct = entry("offhand", "direct_template_key")
        local store = { peer = { slot_melee = slot_entry, tmpl = direct } }
        local book = {}
        Harness.equal(bridge.mirror(store, nil, book, "peer", "slot_melee", "tmpl"),
            "direct-write-wins")
        Harness.equal(store.peer.tmpl, direct)
        -- A key this bridge itself mirrored earlier may be replaced.
        book["peer|tmpl"] = "slot_melee"
        Harness.equal(bridge.mirror(store, nil, book, "peer", "slot_melee", "tmpl"),
            "mirrored")
        Harness.equal(store.peer.tmpl, slot_entry)
    end)

    Harness.test("cos #154 mirror refuses bad namespaces and non-weapon kinds", function()
        local store = { peer = {
            slot_hat = entry("hat", "hat_key"),
            slot_melee = entry("illusion", "k"),
        } }
        Harness.equal(bridge.mirror(store, nil, {}, "peer", "slot_hat", "tmpl"), nil,
            "attachment slots must never mirror")
        Harness.equal(bridge.mirror(store, nil, {}, "peer", "slot_melee", "slot_melee"), nil,
            "template == slot is not an alias")
        store.peer.slot_ranged = entry("armor", "armor_key")
        Harness.equal(bridge.mirror(store, nil, {}, "peer", "slot_ranged", "tmpl"), nil,
            "non-weapon kinds must never mirror")
        Harness.equal(bridge.mirror(store, nil, {}, "peer", "slot_career_skill_weapon",
            "tmpl"), nil, "missing entry mirrors nothing")
    end)

    Harness.test("cos #154 sweep_aliases removes every identity alias only", function()
        local e = entry("illusion", "k")
        local other = entry("offhand", "other")
        local store = { peer = { slot_melee = e, tmpl_a = e, tmpl_b = e, keep = other } }
        local book = { ["peer|tmpl_a"] = "slot_melee", ["peer|tmpl_b"] = "slot_melee" }
        Harness.equal(bridge.sweep_aliases(store, "peer", e, book), 3)
        Harness.equal(store.peer.slot_melee, nil)
        Harness.equal(store.peer.tmpl_a, nil)
        Harness.equal(store.peer.tmpl_b, nil)
        Harness.equal(store.peer.keep, other, "unrelated entries survive the sweep")
        Harness.equal(book["peer|tmpl_a"], nil)
        Harness.equal(bridge.sweep_aliases(store, "peer", nil, book), 0)
    end)

    Harness.test("cos #154 attached reconcile mirrors then re-drives the template key", function()
        local mod, deps = fake_mod("peer", "slot_melee", "bastard_sword_template")
        Harness.truthy(bridge.attach(mod, deps))
        local e = entry("illusion", "Kruber_key")
        mod._la_equips_by_peer.peer = { slot_melee = e }
        local applied = mod._la_reconcile("peer", "slot_melee", "recv", true)
        Harness.truthy(applied, "template-key reconcile result must win when it applies")
        Harness.equal(mod._la_equips_by_peer.peer.bastard_sword_template, e)
        Harness.equal(#mod._reconcile_calls, 2)
        Harness.equal(mod._reconcile_calls[1][2], "slot_melee")
        Harness.equal(mod._reconcile_calls[2][2], "bastard_sword_template")
        Harness.equal(mod._reconcile_calls[2][3], "recv")
        -- Non-wield keys pass straight through, one original call only.
        mod._reconcile_calls = {}
        local ok, reason = mod._la_reconcile("peer", "slot_hat", "recv", true)
        Harness.equal(ok, false)
        Harness.equal(reason, "no-entry")
        Harness.equal(#mod._reconcile_calls, 1)
    end)

    Harness.test("cos #154 unresolvable wearer defers and converges on retry", function()
        local mod, deps = fake_mod("peer", "slot_melee", "bastard_sword_template")
        -- First pass: the wearer peer is unknown (not spawned locally yet).
        local hidden = true
        local real_managers = deps.managers
        deps.managers = function()
            if hidden then return { player = { player_from_peer_id = function() end } } end
            return real_managers()
        end
        Harness.truthy(bridge.attach(mod, deps))
        local e = entry("illusion", "k")
        mod._la_equips_by_peer.peer = { slot_melee = e }
        local applied, reason = mod._la_reconcile("peer", "slot_melee", "recv", true)
        Harness.equal(applied, false)
        Harness.equal(reason, "wearer-not-spawned")
        Harness.equal(mod._la_equips_by_peer.peer.bastard_sword_template, nil,
            "no mirror while the wearer's template is unresolvable")
        -- Retry after spawn (the pending drain path): mirror + apply.
        hidden = false
        applied = mod._la_reconcile("peer", "slot_melee", "retry", true)
        Harness.truthy(applied)
        Harness.equal(mod._la_equips_by_peer.peer.bastard_sword_template, e)
    end)

    Harness.test("cos #154 attached revert sweeps mirror aliases with the slot", function()
        local mod, deps = fake_mod("peer", "slot_melee", "bastard_sword_template")
        Harness.truthy(bridge.attach(mod, deps))
        local e = entry("illusion", "k")
        mod._la_equips_by_peer.peer = { slot_melee = e }
        mod._la_reconcile("peer", "slot_melee", "recv", true)
        Harness.equal(mod._la_equips_by_peer.peer.bastard_sword_template, e)
        mod._la_apply_revert_recv("peer", "slot_melee", "illusion", "vanilla", "left_hand_unit")
        Harness.equal(#mod._revert_calls, 1)
        Harness.equal(mod._la_equips_by_peer.peer.slot_melee, nil)
        Harness.equal(mod._la_equips_by_peer.peer.bastard_sword_template, nil,
            "revert must not strand the mirrored template alias")
    end)

    Harness.test("cos #154 attach refuses when the seams are missing", function()
        Harness.equal(bridge.attach({}, { printf = function() end }), false)
    end)

    -- ---------------------------------------------------------------------
    -- #476: the WEAPON/TEMPLATE-keyed namespace the #154 WIELD_SLOTS mirror
    -- deliberately excludes. CWV wearers store entries under OWNER-LOCAL keys
    -- (variant item_type + variant template); observers reach them through the
    -- read-side candidate resolver, not through a mirror alias.
    -- ---------------------------------------------------------------------

    local peer_identity = dofile(repo_root
        .. "/cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_cos_cwv_peer_identity.lua")

    local IML_476 = {
        cwv_es_longsword_shield = {
            template = "imperial_longsword_shield_template",
        },
    }

    local function cwv_provider(descriptor, state)
        return { _cwv_peer_appearance = { schema = 1,
            resolve_peer = function() return descriptor, state end } }
    end

    local BASE_ITEM_476 = {
        name = "es_sword_shield_breton",
        key = "es_sword_shield_breton",
        item_type = "es_1h_sword_shield_breton",
        template = "one_handed_sword_shield_template_2",
    }

    local EXACT_DESCRIPTOR_476 = {
        provider = "cwv",
        variant_key = "cwv_es_longsword_shield",
        base_item_key = "es_sword_shield_breton",
    }

    Harness.test("cos #476 husk candidates resolve the wearer's exact CWV keys", function()
        local cands, state = peer_identity.husk_variant_candidates(
            cwv_provider(EXACT_DESCRIPTOR_476, "exact"),
            { wearer_peer = "peer", slot_name = "slot_melee" },
            BASE_ITEM_476, IML_476)
        Harness.equal(state, "exact")
        Harness.equal(cands.variant_key, "cwv_es_longsword_shield")
        Harness.equal(cands.template, "imperial_longsword_shield_template")
    end)

    Harness.test("cos #476 husk candidates fail closed on every identity doubt", function()
        local husk = { wearer_peer = "peer", slot_name = "slot_melee" }
        -- No CWV mod / provider at all.
        Harness.equal(peer_identity.husk_variant_candidates(
            nil, husk, BASE_ITEM_476, IML_476), nil)
        -- Provider resolves, but not to an exact state.
        Harness.equal(peer_identity.husk_variant_candidates(
            cwv_provider(EXACT_DESCRIPTOR_476, "stale"),
            husk, BASE_ITEM_476, IML_476), nil)
        -- Descriptor claims a different base item (fingerprint mismatch).
        Harness.equal(peer_identity.husk_variant_candidates(
            cwv_provider({ provider = "cwv",
                variant_key = "cwv_es_longsword_shield",
                base_item_key = "es_sword_shield" }, "exact"),
            husk, BASE_ITEM_476, IML_476), nil)
        -- Variant not registered in the local ItemMasterList.
        Harness.equal(peer_identity.husk_variant_candidates(
            cwv_provider(EXACT_DESCRIPTOR_476, "exact"),
            husk, BASE_ITEM_476, {}), nil)
        -- Provider steering to a non-CWV key is refused outright.
        Harness.equal(peer_identity.husk_variant_candidates(
            cwv_provider({ provider = "cwv", variant_key = "es_2h_hammer",
                base_item_key = "es_sword_shield_breton" }, "exact"),
            husk, BASE_ITEM_476,
            { es_2h_hammer = { template = "two_handed_hammers_template_1" } }),
            nil)
    end)

    Harness.test("cos #476 shared base template is never admitted as a candidate", function()
        -- A CWV row that keeps the vanilla family template must extend only
        -- the variant KEY; surfacing the shared template would key-match a
        -- native wielder of the same family (#514 collision class).
        local cands = peer_identity.husk_variant_candidates(
            cwv_provider(EXACT_DESCRIPTOR_476, "exact"),
            { wearer_peer = "peer", slot_name = "slot_melee" },
            BASE_ITEM_476,
            { cwv_es_longsword_shield = {
                template = "one_handed_sword_shield_template_2" } })
        Harness.equal(cands.variant_key, "cwv_es_longsword_shield")
        Harness.equal(cands.template, nil)
    end)

    local function install_identity_runtime(cwv_mod)
        local runtime = dofile(repo_root
            .. "/cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_cos_la_husk_identity_runtime.lua")
        local mod = {
            hook_safe = function() end,
            warning = function() end,
            get = function() return nil end,
        }
        mod._cos_cwv_peer_identity = peer_identity
        runtime.install(mod, {
            get_mod = function(name)
                if name == "character_weapon_variants" then return cwv_mod end
            end,
            husk_identity = { make_spawn_monitor = function() return function() end end },
            la_bridge = {},
            la_equips_by_peer = {},
            la_persist = {},
            score_identity = {},
            unit = {},
            get_managers = function() return nil end,
            get_profiles = function() return nil end,
            la_replay_policy = { wielded_slot = function(inv, equipment)
                return (equipment and equipment.wielded_slot)
                    or (inv and inv.wielded_slot)
            end },
            dbg = function() end,
            dbg_alert = function() end,
        })
        return mod
    end

    Harness.test("cos #476 apply gate matches owner-local CWV keys on the observer", function()
        local saved_iml = _G.ItemMasterList
        _G.ItemMasterList = IML_476
        local ok, err = pcall(function()
            local mod = install_identity_runtime(
                cwv_provider(EXACT_DESCRIPTOR_476, "exact"))
            local inv = { _player = { peer_id = "wearer" } }
            local equipment = { wielded_slot = "slot_melee",
                slots = { slot_melee = { item_data = BASE_ITEM_476 } } }
            -- The two owner-local store keys now match on the observer.
            Harness.truthy(mod._la_wielded_item_matches(
                inv, equipment, "imperial_longsword_shield_template", false))
            Harness.truthy(mod._la_wielded_item_matches(
                inv, equipment, "cwv_es_longsword_shield", false))
            -- Vanilla candidates are untouched.
            Harness.truthy(mod._la_wielded_item_matches(
                inv, equipment, "one_handed_sword_shield_template_2", false))
            -- A foreign family's key still never matches.
            Harness.equal(mod._la_wielded_item_matches(
                inv, equipment, "sword_and_mace_template", false), false)
        end)
        _G.ItemMasterList = saved_iml
        if not ok then error(err, 0) end
    end)

    Harness.test("cos #476 apply gate fails closed without an exact CWV identity", function()
        local saved_iml = _G.ItemMasterList
        _G.ItemMasterList = IML_476
        local ok, err = pcall(function()
            local inv = { _player = { peer_id = "wearer" } }
            local equipment = { wielded_slot = "slot_melee",
                slots = { slot_melee = { item_data = BASE_ITEM_476 } } }
            -- Provider present but stale: both CWV keys must stay rejected.
            local stale = install_identity_runtime(
                cwv_provider(EXACT_DESCRIPTOR_476, "stale"))
            Harness.equal(stale._la_wielded_item_matches(
                inv, equipment, "imperial_longsword_shield_template", false), false)
            Harness.equal(stale._la_wielded_item_matches(
                inv, equipment, "cwv_es_longsword_shield", false), false)
            -- No CWV mod at all: same fail-closed result.
            local absent = install_identity_runtime(nil)
            Harness.equal(absent._la_wielded_item_matches(
                inv, equipment, "imperial_longsword_shield_template", false), false)
            -- #514 local-wearer scenario is unchanged: no player identity on
            -- the inventory means the vanilla candidate set is authoritative.
            local local_inv = {}
            local local_equipment = { wielded_slot = "slot_melee",
                slots = { slot_melee = { item_data = {
                    template = "sword_and_mace_template",
                    key = "cwv_es_sword_and_mace",
                    item_type = "cwv_es_sword_and_mace",
                } } } }
            local gate = install_identity_runtime(
                cwv_provider(EXACT_DESCRIPTOR_476, "exact"))
            Harness.equal(gate._la_wielded_item_matches(
                local_inv, local_equipment,
                "one_handed_sword_shield_template_2", false), false)
            Harness.truthy(gate._la_wielded_item_matches(
                local_inv, local_equipment, "sword_and_mace_template", false))
        end)
        _G.ItemMasterList = saved_iml
        if not ok then error(err, 0) end
    end)

    Harness.test("cos #154 entry file attaches the bridge after both seam definitions", function()
        local path = repo_root
            .. "/cosmetics_tweaker/scripts/mods/cosmetics_tweaker/cosmetics_tweaker.lua"
        local f = assert(io.open(path, "rb"))
        local source = f:read("*a"); f:close()
        local function read_owner()
            local o = assert(io.open(repo_root
                .. "/cosmetics_tweaker/scripts/mods/cosmetics_tweaker/"
                .. "_cos_la_apply_runtime.lua", "rb"))
            local text = o:read("*a"); o:close()
            return text
        end
        local attach_at = source:find("_cos_husk_cache_bridge\").attach(mod", 1, true)
        Harness.truthy(attach_at, "entry file must attach the #154 bridge")
        -- #1159: both seams moved verbatim into _cos_la_apply_runtime, so the
        -- entry no longer DEFINES them - it installs the owner that does. The
        -- ordering invariant is unchanged and still checked, just against the
        -- install site, which is exactly where the definitions used to sit.
        local owner_at = source:find("_cos_la_apply_runtime\").install(mod", 1, true)
        Harness.truthy(owner_at and owner_at < attach_at,
            "bridge must attach after the apply/revert owner is installed")
        Harness.equal(source:find("mod._la_reconcile = function", 1, true), nil,
            "mod._la_reconcile belongs to _cos_la_apply_runtime, not the entry")
        Harness.equal(source:find("mod._la_apply_revert_recv = function", 1, true), nil,
            "mod._la_apply_revert_recv belongs to _cos_la_apply_runtime, not the entry")
        local owner = read_owner()
        Harness.truthy(owner:find("mod._la_reconcile = function", 1, true),
            "the owner must define mod._la_reconcile")
        Harness.truthy(owner:find("mod._la_apply_revert_recv = function", 1, true),
            "the owner must define mod._la_apply_revert_recv")
    end)
end
