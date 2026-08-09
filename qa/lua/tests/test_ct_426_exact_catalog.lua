-- Offline contract for ct's #426 exact boon catalog (closes the #1191
-- index-drift crash class). Drives the shipped pure module directly: no engine
-- globals, no hooks, no mod handle.
--
-- The crash this locks: ct registers modded boons into two process-local
-- NetworkLookup axes and syncs them BY INTEGER. Two ct peers whose registration
-- order differed numbered the same boons differently, both acked the presence
-- beacon, and the first grant decoded to the wrong template on the other
-- process - a strict-__index fatal, not a nil.
return function(H, repo_root)
    local base = repo_root
        .. "/chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/"
    local policy = assert(loadfile(base .. "_ct_wire_policy.lua"))()
    local Catalog = assert(loadfile(base .. "_lib_wire_catalog.lua"))()

    -- A NetworkLookup axis is bidirectional: lookup[name] = id, lookup[id] = name.
    local function new_axis(seed_names)
        local axis = {}
        for i = 1, #(seed_names or {}) do
            axis[i] = seed_names[i]
            axis[seed_names[i]] = i
        end
        return axis
    end

    -- Stand-in for vanilla's pre-populated axes, so ct never starts numbering at 1.
    local function new_lookup()
        return {
            deus_power_up_templates = new_axis({ "natural_bond", "deus_larger_clip" }),
            buff_templates = new_axis({ "power_up_movespeed_exotic", "deus_ammo_pickup" }),
        }
    end

    -- What the mod does when a boon is registered one at a time, in whatever
    -- order the feature toggles happened to run: append if absent.
    local function register_in_feature_order(lookup, axis_name, names)
        local axis = lookup[axis_name]
        for i = 1, #names do
            if axis[names[i]] == nil then
                local id = #axis + 1
                axis[id], axis[names[i]] = names[i], id
            end
        end
    end

    local function sorted_keys(map)
        local out = {}
        for key in pairs(map) do out[#out + 1] = key end
        table.sort(out)
        return out
    end

    -- Everything catalog_ready reads, built to agree with a given lookup.
    local function new_globals(lookup)
        local templates, powers, buffs = {}, {}, {}
        for name, spec in pairs(policy.power_up_entries()) do
            templates[name] = {}
            powers[spec.rarity] = powers[spec.rarity] or {}
            powers[spec.rarity][name] = {}
        end
        for name in pairs(policy.buff_entries()) do buffs[name] = {} end
        return {
            NetworkLookup = lookup,
            DeusPowerUpTemplates = templates,
            DeusPowerUps = powers,
            BuffTemplates = buffs,
        }
    end

    -- ---------------------------------------------------------------- catalog

    H.test("CT #426 catalogs are closed, counted, and exclude vanilla names", function()
        local powers = policy.power_up_entries()
        local buffs = policy.buff_entries()
        H.equal(policy.count(powers), 12)
        H.equal(policy.count(buffs), 21)
        H.equal(policy.count(powers) + policy.count(buffs), policy.WIRE_ROW_COUNT)
        H.equal(policy.POWER_UP_COUNT, 12)
        H.equal(policy.BUFF_COUNT, 21)

        -- Every power-up carries a rarity the boon roller accepts. common and
        -- plentiful are weapon-drop tiers and crash existing_power_ups_lut.
        local valid_rarity = { event = true, rare = true, exotic = true, unique = true }
        for name, spec in pairs(powers) do
            H.truthy(valid_rarity[spec.rarity], name .. " has an unrollable rarity")
        end

        H.equal(policy.is_power_up("ct_kill_heal"), true)
        H.equal(policy.is_power_up("ct_boon_vauls_anvil"), true)
        H.equal(policy.is_power_up("natural_bond"), false)
        H.equal(policy.is_power_up(nil), false)
        H.equal(policy.is_buff("ct_miracle_of_ulric"), true)
        H.equal(policy.is_buff("power_up_ct_kill_heal_exotic"), true)
        H.equal(policy.is_buff("power_up_movespeed_exotic"), false)
        H.equal(policy.is_buff(nil), false)

        -- A power-up name is never also a buff name; they live on separate axes.
        for name in pairs(powers) do
            H.equal(policy.is_buff(name), false, name .. " must not be a buff row")
        end

        -- The returned tables are copies: mutating one must not retarget the gate.
        powers.ct_kill_heal = nil
        buffs.ct_miracle_of_ulric = nil
        H.equal(policy.count(policy.power_up_entries()), 12)
        H.equal(policy.is_buff("ct_miracle_of_ulric"), true)
    end)

    H.test("CT #426 registry readiness is two-way", function()
        local registry = {}
        for name in pairs(policy.power_up_entries()) do registry[name] = {} end
        H.equal(policy.power_registry_ready(registry), true)

        registry.ct_kill_heal = nil
        local ok, err = policy.power_registry_ready(registry)
        H.equal(ok, false)
        H.truthy(err:find("registered%-power%-missing"), "got " .. tostring(err))

        registry.ct_kill_heal = {}
        registry.ct_boon_new_thing = {}
        local ok2, err2 = policy.power_registry_ready(registry)
        H.equal(ok2, false, "a boon injected without a catalog entry must be caught")
        H.truthy(err2:find("registered%-power%-unowned"), "got " .. tostring(err2))

        H.equal(policy.power_registry_ready(nil), false)
    end)

    -- ------------------------------------------------------------ reservation

    H.test("CT #426 reservation is sorted, complete, and idempotent", function()
        local lookup = new_lookup()
        local reserved = assert(policy.reserve_lookups(lookup))
        H.equal(reserved.power_up, 12)
        H.equal(reserved.buff, 21)

        -- Reserved ids follow sorted name order, appended after vanilla's rows.
        local names = sorted_keys(policy.power_up_entries())
        for i = 1, #names do
            H.equal(lookup.deus_power_up_templates[names[i]], 2 + i,
                names[i] .. " landed on the wrong id")
            H.equal(lookup.deus_power_up_templates[2 + i], names[i])
        end

        -- Re-running adds nothing and moves nothing.
        local again = assert(policy.reserve_lookups(lookup))
        H.equal(again.power_up, 0)
        H.equal(again.buff, 0)
        H.equal(lookup.deus_power_up_templates[names[1]], 3)

        -- Vanilla rows are untouched.
        H.equal(lookup.deus_power_up_templates.natural_bond, 1)
        H.equal(lookup.deus_power_up_templates[1], "natural_bond")
    end)

    H.test("CT #426 reservation refuses a half-written lookup row", function()
        local lookup = new_lookup()
        -- Forward mapping only: vanilla decodes by integer, so this row would be
        -- a fatal decode on the receiving peer rather than a local nil.
        lookup.deus_power_up_templates.ct_kill_heal = 99
        local ok, err = policy.reserve_lookups(lookup)
        H.equal(ok, nil)
        H.truthy(err:find("lookup%-mismatch"), "got " .. tostring(err))

        local missing = { deus_power_up_templates = new_axis({}) }
        local ok2, err2 = policy.reserve_lookups(missing)
        H.equal(ok2, nil)
        H.truthy(err2:find("lookup%-axis%-missing:buff_templates"), "got " .. tostring(err2))
        H.equal(policy.reserve_lookups(nil), nil)
    end)

    -- -------------------------------------------------- the #1191 drift proof

    H.test("CT #1191 two peers registering in different orders agree", function()
        -- The regression, planted: peer B enables its boons in a different order
        -- than peer A (different toggles, different DLC, different load order).
        local names = sorted_keys(policy.power_up_entries())
        local reversed = {}
        for i = #names, 1, -1 do reversed[#reversed + 1] = names[i] end

        -- WITHOUT the reservation, feature-order registration drifts.
        local drift_a, drift_b = new_lookup(), new_lookup()
        register_in_feature_order(drift_a, "deus_power_up_templates", names)
        register_in_feature_order(drift_b, "deus_power_up_templates", reversed)
        H.truthy(drift_a.deus_power_up_templates[names[1]]
                ~= drift_b.deus_power_up_templates[names[1]],
            "fixture is not exercising drift: both peers numbered the boon alike")
        local id_a = Catalog.build_identity("ct.deus_power_up_templates",
            { [names[1]] = true }, drift_a.deus_power_up_templates)
        local id_b = Catalog.build_identity("ct.deus_power_up_templates",
            { [names[1]] = true }, drift_b.deus_power_up_templates)
        H.truthy(id_a ~= id_b, "drifted catalogs must not share an identity")

        -- WITH the reservation running first, the same divergent registration
        -- order is numerically identical on both processes.
        local fixed_a, fixed_b = new_lookup(), new_lookup()
        assert(policy.reserve_lookups(fixed_a))
        assert(policy.reserve_lookups(fixed_b))
        register_in_feature_order(fixed_a, "deus_power_up_templates", names)
        register_in_feature_order(fixed_b, "deus_power_up_templates", reversed)
        for i = 1, #names do
            H.equal(fixed_a.deus_power_up_templates[names[i]],
                fixed_b.deus_power_up_templates[names[i]],
                names[i] .. " still drifts after reservation")
        end
        H.equal(policy.build_identity(Catalog, fixed_a),
            policy.build_identity(Catalog, fixed_b))
    end)

    H.test("CT #1191 a drifted peer reads as parity-absent", function()
        local mine = new_lookup()
        assert(policy.reserve_lookups(mine))
        local identity = assert(policy.build_identity(Catalog, mine))
        H.truthy(#identity <= 64, "identity must fit the 64-char wire field")
        H.truthy(identity:match("^[%w_.:%-]+$") ~= nil,
            "identity must use the restricted transport alphabet")
        H.truthy(identity:find("ct%-wire%-v1:33:") == 1, "got " .. identity)

        -- Same catalog, one boon on a different integer: the peer must not match.
        local theirs = new_lookup()
        assert(policy.reserve_lookups(theirs))
        local axis = theirs.deus_power_up_templates
        local moved = "ct_kill_heal"
        local old_id, new_id = axis[moved], #axis + 1
        axis[old_id] = nil
        axis[moved], axis[new_id] = new_id, moved
        local drifted = assert(policy.build_identity(Catalog, theirs))
        H.truthy(drifted ~= identity, "a moved boon index must change the identity")

        -- A peer missing one cataloged boon entirely cannot produce an identity.
        local partial = new_lookup()
        assert(policy.reserve_lookups(partial))
        local paxis = partial.buff_templates
        local gone_id = paxis.ct_miracle_of_ulric
        paxis.ct_miracle_of_ulric, paxis[gone_id] = nil, nil
        local none, err = policy.build_identity(Catalog, partial)
        H.equal(none, nil)
        H.truthy(tostring(err):find("lookup%-mismatch"), "got " .. tostring(err))
    end)

    -- ------------------------------------------------------------- readiness

    H.test("CT #426 catalog readiness spans every table the grant path reads", function()
        local lookup = new_lookup()
        assert(policy.reserve_lookups(lookup))
        local globals = new_globals(lookup)
        H.equal(policy.catalog_ready(globals), true)

        -- A boon in the pool but missing from BuffTemplates crashes on first
        -- apply (buff_extension.lua:177) - the dual-table registration trap.
        local no_buff = new_globals(lookup)
        no_buff.BuffTemplates.ct_miracle_of_ulric = nil
        local ok, err = policy.catalog_ready(no_buff)
        H.equal(ok, false)
        H.truthy(err:find("buff%-template%-missing"), "got " .. tostring(err))

        local no_rarity = new_globals(lookup)
        no_rarity.DeusPowerUps.unique.ct_boon_vauls_anvil = nil
        local ok2, err2 = policy.catalog_ready(no_rarity)
        H.equal(ok2, false)
        H.truthy(err2:find("power%-runtime%-missing"), "got " .. tostring(err2))

        local no_template = new_globals(lookup)
        no_template.DeusPowerUpTemplates.ct_kill_heal = nil
        local ok3, err3 = policy.catalog_ready(no_template)
        H.equal(ok3, false)
        H.truthy(err3:find("power%-template%-missing"), "got " .. tostring(err3))

        -- Nothing registered at all must fail rather than pass vacuously.
        H.equal(policy.catalog_ready({}), false)
        H.equal(policy.catalog_ready(nil), false)
    end)

    H.test("CT #426 identity refuses to build without the shared library", function()
        local lookup = new_lookup()
        assert(policy.reserve_lookups(lookup))
        local none, err = policy.build_identity(nil, lookup)
        H.equal(none, nil)
        H.equal(err, "wire-catalog-library-missing")
        H.equal(policy.build_identity({}, lookup), nil)
    end)

    -- ------------------------------------------------------------- integrity

    H.test("CT #426 integrity fails closed on post-boot drift", function()
        local lookup = new_lookup()
        assert(policy.reserve_lookups(lookup))
        local snapshot = assert(policy.capture_integrity(lookup))
        H.equal(#snapshot.rows, policy.WIRE_ROW_COUNT)
        H.equal(policy.integrity(snapshot), true)

        -- A third party renumbers one row after ct committed its identity.
        local moved = lookup.buff_templates.ct_miracle_of_isha_aegis
        lookup.buff_templates.ct_miracle_of_isha_aegis = moved + 500
        local ok, err = policy.integrity(snapshot)
        H.equal(ok, false)
        H.truthy(err:find("integrity%-mismatch"), "got " .. tostring(err))
        lookup.buff_templates.ct_miracle_of_isha_aegis = moved
        H.equal(policy.integrity(snapshot), true)

        -- A wholesale axis replacement must be caught even if the new table
        -- happens to carry the same names and ids.
        local replacement = {}
        for key, value in pairs(lookup.buff_templates) do replacement[key] = value end
        lookup.buff_templates = replacement
        H.equal(policy.integrity(snapshot), false)

        -- Malformed or truncated snapshots never read intact.
        H.equal(policy.integrity(nil), false)
        H.equal(policy.integrity({}), false)
        local short = { network_lookup = snapshot.network_lookup, rows = {} }
        for i = 1, #snapshot.rows - 1 do short.rows[i] = snapshot.rows[i] end
        H.equal(policy.integrity(short), false)

        H.equal(policy.capture_integrity(nil), nil)
        local bad, bad_err = policy.capture_integrity({ buff_templates = new_axis({}) })
        H.equal(bad, nil)
        H.truthy(tostring(bad_err):find("lookup%-axis%-missing"), "got " .. tostring(bad_err))
    end)

    -- --------------------------------------------------------------- filters

    H.test("CT #426 strip filters remove only cataloged rows", function()
        local rows = {
            { name = "natural_bond" },
            { name = "ct_kill_heal" },
            { name = "deus_larger_clip" },
            { name = "ct_boon_manann_tempest" },
        }
        local kept, removed = policy.filter_power_ups(rows)
        H.equal(removed, 2)
        H.equal(#kept, 2)
        -- Survivors keep their exact identity and order, not a rebuilt copy.
        H.equal(kept[1], rows[1])
        H.equal(kept[2], rows[3])

        local names = { "natural_bond", "ct_meta_crit", "deus_larger_clip" }
        local kept_names, removed_names = policy.filter_power_up_names(names)
        H.equal(removed_names, 1)
        H.deep_equal(kept_names, { "natural_bond", "deus_larger_clip" })

        local buffs = {
            "power_up_movespeed_exotic",
            "ct_miracle_of_ulric",
            "ct_meta_ammo_stack",
            "deus_ammo_pickup",
        }
        local kept_buffs, removed_buffs = policy.filter_persistent_buffs(buffs)
        H.equal(removed_buffs, 2)
        H.deep_equal(kept_buffs, { "power_up_movespeed_exotic", "deus_ammo_pickup" })

        -- Nothing to filter is not an error; a nil list yields an empty list.
        H.deep_equal(select(1, policy.filter_power_ups(nil)), {})
        H.equal(select(2, policy.filter_persistent_buffs(nil)), 0)
        -- A malformed row (no name) is preserved, never silently dropped.
        local odd = { { rarity = "exotic" }, "not-a-row" }
        local kept_odd, removed_odd = policy.filter_power_ups(odd)
        H.equal(removed_odd, 0)
        H.equal(#kept_odd, 2)
    end)

    H.test("CT #426 purchases of cataloged content need the exact gate", function()
        H.equal(policy.purchase_allowed("ct_kill_heal", true), true)
        H.equal(policy.purchase_allowed("ct_kill_heal", false), false)
        H.equal(policy.purchase_allowed("ct_kill_heal", nil), false)
        -- Vanilla content is always purchasable; the gate never degrades it.
        H.equal(policy.purchase_allowed("natural_bond", false), true)
    end)

    -- ---------------------------------------------------------- presentation

    H.test("CT #426 gated rows cover every control that enables wire content", function()
        local ids = policy.GATED_SETTING_IDS
        H.equal(#ids, 21)

        local seen = {}
        for i = 1, #ids do
            H.equal(type(ids[i]), "string")
            H.equal(seen[ids[i]], nil, "duplicate gated row " .. tostring(ids[i]))
            seen[ids[i]] = true
        end

        -- One start_boon_ row per cataloged power-up: a starting boon is gate
        -- surface 3, so a new boon must not be able to slip in ungated.
        for name in pairs(policy.power_up_entries()) do
            H.truthy(seen["start_boon_" .. name],
                "no gated starting-boon row for " .. name)
        end
        H.truthy(seen.enable_boon_reworks, "the umbrella row must be gated")
        H.truthy(seen.tweak_miracle_of_ulric_persistent)
        H.truthy(seen.tweak_miracle_of_isha_aegis)
        H.truthy(seen.tweak_miracle_of_isha_wounds)

        -- Disabling modded content is safe in any lobby: greying those rows would
        -- take away the only control that still works while parity is missing.
        for i = 1, #ids do
            H.equal(ids[i]:find("disable_boon_", 1, true), nil,
                ids[i] .. " must not be gated")
        end

        -- The accessor hands out a copy.
        local copy = policy.runtime_gate_setting_ids()
        H.equal(#copy, #ids)
        copy[1] = "mutated"
        H.truthy(policy.GATED_SETTING_IDS[1] ~= "mutated")
    end)

    H.test("CT #426 gate reason is player-facing", function()
        local reason = policy.GATE_REASON
        H.equal(type(reason), "string")
        H.truthy(#reason > 0)
        -- CLAUDE.md non-negotiable 11: no em dashes, no lifecycle metadata.
        H.equal(reason:find("\226\128\148", 1, true), nil, "em dash in menu text")
        H.equal(reason:find("[", 1, true), nil, "lifecycle marker in menu text")
        H.equal(reason:lower():find("issue", 1, true), nil)
    end)

    H.test("CT #426 gate spec keeps its validating three-arg form", function()
        local evaluate = function() return false, policy.GATE_REASON end

        -- ct and crt take the id list explicitly; wt's copy takes (mod_id,
        -- evaluate). The explicit list is what lets the caller and these tests
        -- push adversarial input through the SAME validator the ship path uses.
        local spec = policy.runtime_gate_spec("ct_dev", policy.GATED_SETTING_IDS, evaluate)
        H.equal(type(spec), "table")
        H.equal(spec.mod_id, "ct_dev")
        H.equal(#spec.setting_ids, 21)
        local available, reason = spec.evaluate()
        H.equal(available, false)
        H.equal(reason, policy.GATE_REASON)

        -- The spec owns its own list: mutating the caller's table afterwards
        -- must not retarget a live gate.
        local caller_list = { "enable_boon_reworks", "tweak_miracle_of_isha_aegis" }
        local owned = policy.runtime_gate_spec("ct_dev", caller_list, evaluate)
        caller_list[1] = "something_else"
        H.equal(owned.setting_ids[1], "enable_boon_reworks")

        -- Malformed input is rejected wholesale rather than greying wrong rows.
        H.equal(policy.runtime_gate_spec("ct_dev", { "a", "a" }, evaluate), nil)
        H.equal(policy.runtime_gate_spec("ct_dev", {}, evaluate), nil)
        H.equal(policy.runtime_gate_spec("ct_dev", { "ok", 7 }, evaluate), nil)
        H.equal(policy.runtime_gate_spec("ct_dev", { "ok", "" }, evaluate), nil)
        H.equal(policy.runtime_gate_spec("", policy.GATED_SETTING_IDS, evaluate), nil)
        H.equal(policy.runtime_gate_spec(nil, policy.GATED_SETTING_IDS, evaluate), nil)
        H.equal(policy.runtime_gate_spec("ct_dev", policy.GATED_SETTING_IDS, nil), nil)

        -- Omitting the list falls back to the module's own rows.
        local defaulted = policy.runtime_gate_spec("ct_dev", nil, evaluate)
        H.equal(#defaulted.setting_ids, 21)
    end)

    H.test("CT #426 Mod Tweaker bridge is optional and fails closed", function()
        local spec = policy.runtime_gate_spec("ct_dev", policy.GATED_SETTING_IDS,
            function() return false, policy.GATE_REASON end)

        H.equal(policy.try_register_runtime_gate(nil, "id", spec), false)
        H.equal(policy.try_register_runtime_gate(function() end, "", spec), false)
        H.equal(policy.try_register_runtime_gate(function() end, "id", nil), false)

        -- GUT absent: runtime safety is unaffected, so this only reports false.
        local absent, why = policy.try_register_runtime_gate(
            function() return nil end, "ct_dev:426:peer-parity", spec)
        H.equal(absent, false)
        H.equal(why, "mod-tweaker-unavailable")

        -- A get_mod that throws must not escape.
        H.equal(policy.try_register_runtime_gate(
            function() error("boom") end, "id", spec), false)

        -- Dev GUI present but broken must not stop the stable alias from owning
        -- presentation.
        local registered_with
        local gut_dev = { mod_tweaker = { register_runtime_gate = function()
            error("dev gui damaged")
        end } }
        local gut = { mod_tweaker = { register_runtime_gate = function(_, gate_id)
            registered_with = gate_id
            return true
        end } }
        local ok = policy.try_register_runtime_gate(function(id)
            if id == "gut_dev" then return gut_dev end
            return gut
        end, "ct_dev:426:peer-parity", spec)
        H.equal(ok, true)
        H.equal(registered_with, "ct_dev:426:peer-parity")
    end)
end
