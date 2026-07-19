-- Engine-free coverage for the COMPLETE husk adapter at the
-- GearUtils.spawn_inventory_unit seam (issues 394/398/399/401/474/476/482/719,
-- BUG_CLASSES class 27 -- husk consumed only a PARTIAL variant definition):
--   * full-definition resolution: mesh re-key + pre-spawn ammo-nil + clone
--     template identity from ONE positive-identity resolution;
--   * FAIL-CLOSED residency (#474 MeshObject AV killer): custom-bundle meshes
--     gate on their vanilla donor MATERIAL; non-force-loaded vanilla overrides
--     gate on direct engine proof; every miss keeps the base identity and
--     queues one bounded package lease under HUSK_OVERRIDE_REF;
--   * ammo-nil propagation (#399) with the descriptor-primary decision order;
--   * all-four-returns capture + adapter wiring in the entry hook;
--   * the #579 per-hand compare probe shape (capped printf).
-- Layers follow test_cwv_husk_path.lua: execute the module against fixtures,
-- then grep the shipped source for the load-bearing wiring.
return function(H, repo_root)
    local mod_root = repo_root
        .. "/character_weapon_variants/scripts/mods/character_weapon_variants/"
    local module_path = mod_root .. "_cwv_husk_path.lua"
    local main_path = mod_root .. "character_weapon_variants.lua"

    local function read(path)
        local file = assert(io.open(path, "rb"))
        local source = file:read("*a")
        file:close()
        return source
    end

    local CUSTOM_MESH = "units/cwv_es_musket_custom/cwv_es_musket_custom"
    local DONOR_3P = "units/weapons/player/wpn_empire_handgun_t1/wpn_empire_handgun_t1_3p"
    local AXE_OVERRIDE = "units/weapons/player/wpn_fix_axe/wpn_fix_axe"
    local BASE_UNIT = "units/weapons/player/wpn_fix_base/wpn_fix_base"

    local DEFS = {
        {
            item_key = "cwv_fix_axe",
            base_weapon = "fix_base",
            careers = { "es_fix" },
            right_hand_unit = AXE_OVERRIDE,
            template = "fix_axe_template",
            no_ammo_unit = true,
            item_type = "cwv_fix_axe",
        },
        {
            item_key = "cwv_fix_musket",
            base_weapon = "fix_gun",
            careers = { "es_fix" },
            right_hand_unit = CUSTOM_MESH,
            item_type = "cwv_fix_musket",
        },
    }

    local function find_def(key)
        for _, def in ipairs(DEFS) do
            if def.item_key == key then return def end
        end
        return nil
    end

    -- Build a fresh module install: om table + captured printf lines + a
    -- Managers.package spy recording every load(path, ref) lease.
    local function fixture()
        local om = { HUSK_OVERRIDE_REF = "cwv_husk_override_units" }
        local lines = {}
        local leases = {}
        local env = {
            printf = function(fmt, ...) lines[#lines + 1] = string.format(fmt, ...) end,
            ScriptUnit = {
                has_extension = function() return true end,
                extension = function()
                    return { career_name = function() return "es_fix" end }
                end,
            },
            Unit = { alive = function() return true end },
            ItemMasterList = {
                fix_base = { can_wield = { "dr_other" } },
                fix_gun = { can_wield = { "dr_other" } },
            },
            WeaponSkins = { skins = {} },
            Weapons = {
                fix_axe_template = {
                    right_hand_attachment_node_linking = {
                        third_person = { wielded = {} },
                    },
                },
            },
            Managers = {
                package = {
                    load = function(_, path, ref) leases[#leases + 1] = { path = path, ref = ref } end,
                    has_loaded = function() return false end,
                },
            },
        }
        assert(loadfile(module_path))()(nil, {
            om = om,
            variant_definitions = DEFS,
            find_def = find_def,
            is_unit = function(u) return u ~= nil end,
            apply_cwv_hand_transform = function() return true end,
            triplet_text = function() return "t" end,
        })
        return om, lines, leases, env
    end

    -- Swap the stub globals in around a call, restore after (repo pattern:
    -- test_cwv_exact_pair_state.lua).
    local GLOBAL_KEYS = {
        "printf", "ScriptUnit", "Unit", "ItemMasterList", "WeaponSkins",
        "Weapons", "Managers", "Application",
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

    local function exact_descriptor(key, right_unit)
        return function()
            return {
                variant_key = key,
                right_hand_unit = right_unit,
                fingerprint = "fp:" .. key,
            }, "exact"
        end
    end

    local function joined(lines)
        return table.concat(lines, "\n")
    end

    H.test("adapter pre resolves the FULL definition: re-key + ammo-nil + clone template", function()
        local om, lines, _, env = fixture()
        env.Application = { can_get = function(kind, name) return true end }
        om._husk_identity_descriptor = exact_descriptor("cwv_fix_axe", AXE_OVERRIDE)
        local base_template = {}
        local item_units = {
            right_hand_unit = BASE_UNIT,
            ammo_unit = "fix_ammo",
            ammo_unit_3p = "fix_ammo_3p",
        }
        with_env(env, function()
            local suppress, tpl = om._husk_adapter_pre(
                "right", base_template, item_units, "slot_melee",
                { name = "fix_base" }, {})
            H.equal(suppress, false, "resident override must not suppress the spawn")
            H.equal(tpl, env.Weapons.fix_axe_template,
                "positive identity must hand the clone template to the spawn (#398)")
        end)
        H.equal(item_units.right_hand_unit, AXE_OVERRIDE,
            "display units must be the variant's override, not base (#396/#719)")
        H.equal(item_units.ammo_unit, nil, "ammo_unit must be nil'd pre-spawn (#399)")
        H.equal(item_units.ammo_unit_3p, nil, "ammo_unit_3p must be nil'd pre-spawn (#399)")
        local all = joined(lines)
        H.truthy(all:find("[cwv:399] husk ammo-nil pre-spawn", 1, true))
        H.truthy(all:find("[cwv:398] husk template identity", 1, true))
    end)

    H.test("clone template guards fail closed on a missing hand link", function()
        local om, _, _, env = fixture()
        env.Application = { can_get = function() return true end }
        env.Weapons.fix_axe_template = { }   -- no right_hand_attachment_node_linking
        om._husk_identity_descriptor = exact_descriptor("cwv_fix_axe", AXE_OVERRIDE)
        with_env(env, function()
            local tpl = om._husk_template_for_spawn(
                "right", {}, { right_hand_unit = AXE_OVERRIDE }, "slot_melee",
                { name = "fix_base" }, {})
            H.equal(tpl, nil,
                "a clone template without the hand link vanilla indexes must be declined")
        end)
    end)

    H.test("#474 fail-closed: custom mesh without resident donor keeps base and leases donor", function()
        local om, lines, leases, env = fixture()
        env.Application = { can_get = function(kind, name)
            if kind == "material" then return false end
            return true
        end }
        om._husk_identity_descriptor = exact_descriptor("cwv_fix_musket", CUSTOM_MESH)
        om._husk_custom_bundle_unit = function(u)
            return u == CUSTOM_MESH or u == CUSTOM_MESH .. "_3p"
        end
        local item_units = { right_hand_unit = "units/weapons/player/wpn_fix_gun/wpn_fix_gun" }
        with_env(env, function()
            local suppress = om._husk_rekey_units("right", { name = "fix_gun" },
                item_units, {}, "slot_ranged")
            H.equal(suppress, nil, "base identity stays spawnable -- no #478 suppress")
        end)
        H.equal(item_units.right_hand_unit, "units/weapons/player/wpn_fix_gun/wpn_fix_gun",
            "custom mesh must NOT be written while its donor material is missing (#474)")
        H.equal(leases[1] and leases[1].path, DONOR_3P,
            "donor package must be leased so the next wield resolves")
        H.equal(leases[1] and leases[1].ref, "cwv_husk_override_units")
        H.truthy(joined(lines):find("[cwv:474] husk donor-material lease", 1, true))

        -- Same shape with the donor resident: the authored mesh is written.
        local om2, _, _, env2 = fixture()
        env2.Application = { can_get = function() return true end }
        om2._husk_identity_descriptor = exact_descriptor("cwv_fix_musket", CUSTOM_MESH)
        om2._husk_custom_bundle_unit = om._husk_custom_bundle_unit
        local item_units2 = { right_hand_unit = "units/weapons/player/wpn_fix_gun/wpn_fix_gun" }
        with_env(env2, function()
            om2._husk_rekey_units("right", { name = "fix_gun" }, item_units2, {}, "slot_ranged")
        end)
        H.equal(item_units2.right_hand_unit, CUSTOM_MESH,
            "resident donor must admit the authored custom mesh")
    end)

    H.test("#476/#482 fail-closed: unproven vanilla override keeps base and leases it", function()
        local om, lines, leases, env = fixture()
        env.Application = { can_get = function(kind, name)
            -- Override unproven; everything else (the kept base) resident.
            if name == AXE_OVERRIDE .. "_3p" then return false end
            return true
        end }
        om._husk_identity_descriptor = exact_descriptor("cwv_fix_axe", AXE_OVERRIDE)
        local item_units = { right_hand_unit = BASE_UNIT }
        with_env(env, function()
            local suppress = om._husk_rekey_units("right", { name = "fix_base" },
                item_units, {}, "slot_melee")
            H.equal(suppress, nil, "kept base is resident -- render wrong-but-stable, no suppress")
        end)
        H.equal(item_units.right_hand_unit, BASE_UNIT,
            "unproven override must not be written (fail-closed residency)")
        local paths = {}
        for _, lease in ipairs(leases) do paths[lease.path] = lease.ref end
        H.equal(paths[AXE_OVERRIDE], "cwv_husk_override_units",
            "override base form must be leased for the next wield")
        H.equal(paths[AXE_OVERRIDE .. "_3p"], "cwv_husk_override_units",
            "override _3p form must be leased for the next wield")
        H.truthy(joined(lines):find("[cwv:476] husk override lease", 1, true))

        -- Direct engine proof admits the same override without a force-load ref.
        local om2, _, _, env2 = fixture()
        env2.Application = { can_get = function() return true end }
        om2._husk_identity_descriptor = exact_descriptor("cwv_fix_axe", AXE_OVERRIDE)
        local item_units2 = { right_hand_unit = BASE_UNIT }
        with_env(env2, function()
            om2._husk_rekey_units("right", { name = "fix_base" }, item_units2, {}, "slot_melee")
        end)
        H.equal(item_units2.right_hand_unit, AXE_OVERRIDE)
    end)

    H.test("#399 ammo-nil decision order: descriptor overrules, base+career falls back", function()
        local om, _, _, env = fixture()
        env.Application = { can_get = function() return true end }
        -- (1) exact identity of a NON-no_ammo variant: ammo must survive.
        om._husk_identity_descriptor = exact_descriptor("cwv_fix_musket", CUSTOM_MESH)
        local keep = { ammo_unit = "a", ammo_unit_3p = "a3" }
        with_env(env, function()
            H.equal(om._husk_ammo_nil_item_units({ name = "fix_gun" }, keep, {}, "slot_ranged"), false)
        end)
        H.equal(keep.ammo_unit, "a", "descriptor-proven non-no_ammo variant keeps its ammo")
        -- (2) no descriptor: skinless base+career positive signal nils the ammo.
        om._husk_identity_descriptor = function() return nil, "none" end
        local strip = { ammo_unit = "a", ammo_unit_3p = "a3" }
        with_env(env, function()
            H.equal(om._husk_ammo_nil_item_units({ name = "fix_base" }, strip, {}, "slot_melee"), true)
        end)
        H.equal(strip.ammo_unit, nil)
        H.equal(strip.ammo_unit_3p, nil)
        -- (3) explicit-native evidence declines.
        om._husk_identity_descriptor = function() return nil, "native" end
        local native = { ammo_unit = "a" }
        with_env(env, function()
            H.equal(om._husk_ammo_nil_item_units({ name = "fix_base" }, native, {}, "slot_melee"), false)
        end)
        H.equal(native.ammo_unit, "a", "explicitly-native slots are never stripped")
    end)

    H.test("#579 per-hand compare probe: shape, per-hand fields, dedupe cap", function()
        local om, lines, _, env = fixture()
        om._husk_identity_descriptor = exact_descriptor("cwv_fix_axe", AXE_OVERRIDE)
        local item_units = { right_hand_unit = BASE_UNIT, skin = nil }
        with_env(env, function()
            om._probe_579_hand_compare("right", { name = "fix_base" }, item_units,
                "slot_melee", {}, { unit = true })
            om._probe_579_hand_compare("right", { name = "fix_base" }, item_units,
                "slot_melee", {}, { unit = true })
            om._probe_579_hand_compare("left", { name = "fix_base" }, item_units,
                "slot_melee", {}, nil)
        end)
        H.equal(#lines, 2, "identical shapes must log once; distinct hands log separately")
        H.truthy(lines[1]:find("[cwv:579] husk hand-compare", 1, true))
        H.truthy(lines[1]:find("slot=slot_melee", 1, true))
        H.truthy(lines[1]:find("hand=right", 1, true))
        H.truthy(lines[1]:find("expected_right_hand_unit=" .. AXE_OVERRIDE, 1, true))
        H.truthy(lines[1]:find("item_units_right_hand_unit=" .. BASE_UNIT, 1, true))
        H.truthy(lines[1]:find("expected==actual=false", 1, true))
        H.truthy(lines[1]:find("spawned_3p=true", 1, true))
        H.truthy(lines[2]:find("hand=left", 1, true))
        H.truthy(lines[2]:find("expected_left_hand_unit=", 1, true))
        H.truthy(lines[2]:find("spawned_3p=false", 1, true))
    end)

    H.test("adapter post: strip return contract + transform + probe consume the same call", function()
        local om, _, _, env = fixture()
        local calls = {}
        om._husk_strip_cwv_ammo = function() calls[#calls + 1] = "strip"; return true end
        om._husk_apply_cwv_transform = function() calls[#calls + 1] = "transform" end
        om._probe_579_hand_compare = function() calls[#calls + 1] = "probe" end
        with_env(env, function()
            H.equal(om._husk_adapter_post("right", { name = "fix_base" }, {},
                "slot_melee", {}, { u = 1 }, { a = 1 }), true,
                "a fired strip must tell the entry to nil its captured ammo return")
        end)
        H.deep_equal(calls, { "strip", "transform", "probe" })
    end)

    H.test("entry wiring: all-four-returns capture + adapter seams + fail-closed anchors", function()
        local main = read(main_path)
        for _, marker in ipairs({
            -- gear_utils.lua:13 multi-return: weapon_3p, ammo_3p, weapon_1p, ammo_1p.
            "local v_w3p, v_a3p, v_w1p, v_a1p =",
            "func(world, hand, husk_spawn_template or item_template, item_units, slot_name, item_data, owner_unit_1p, owner_unit_3p, unit_template, extra_extension_data, ammo_percent, material_settings_name)",
            "_om._husk_adapter_pre(hand, item_template, item_units, slot_name, item_data, owner_unit_3p)",
            "_om._husk_adapter_post(hand, item_data, item_units, slot_name, owner_unit_3p, v_w3p, v_a3p)",
            "return nil, nil, nil, nil",
            "return v_w3p, v_a3p, v_w1p, v_a1p",
        }) do
            H.truthy(main:find(marker, 1, true), "missing entry adapter anchor: " .. marker)
        end
        local module_source = read(module_path)
        for _, marker in ipairs({
            "_om._husk_adapter_pre = function(hand, item_template, item_units, slot_name, item_data, owner_unit_3p)",
            "_om._husk_adapter_post = function(hand, item_data, item_units, slot_name, owner_unit_3p, v_w3p, v_a3p)",
            "_om._husk_strip_cwv_ammo(item_data, owner_unit_3p, v_a3p, slot_name)",
            "_om._husk_apply_cwv_transform(hand, item_data, item_units, v_w3p, owner_unit_3p, slot_name)",
            "_om._husk_material_donor_ready = function(base_unit)",
            "_om._husk_lease_override = function(base_unit)",
            "app.can_get",   -- weapons_of_chaos residency-truth recipe
            "[cwv:474] husk donor-material lease",
            "[cwv:399] husk ammo-nil pre-spawn",
            "[cwv:398] husk template identity",
            "[cwv:579] husk hand-compare",
        }) do
            H.truthy(module_source:find(marker, 1, true), "missing module adapter anchor: " .. marker)
        end
        -- Render-side only: the adapter must never gain a network send.
        local adapter_start = module_source:find("COMPLETE husk adapter", 1, true)
        H.truthy(adapter_start)
        H.equal(module_source:find("network_send", adapter_start, true), nil,
            "complete husk adapter must stay render-side (issue 741/495 wire safety)")
    end)
end
