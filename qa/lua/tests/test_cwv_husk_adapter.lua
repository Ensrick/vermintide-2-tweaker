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
        {
            item_key = "cwv_fix_pair",
            base_weapon = "fix_pair_base",
            careers = { "es_fix" },
            right_hand_unit = AXE_OVERRIDE,
            left_hand_unit = "units/weapons/player/wpn_fix_shield/wpn_fix_shield",
            item_type = "cwv_fix_pair",
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
                fix_pair_base = { can_wield = { "dr_other" } },
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

    H.test("#474/#660 handedness preselection preserves base until the custom mesh is spawnable", function()
        local om, lines, leases, env = fixture()
        env.Application = { can_get = function(kind)
            if kind == "material" then return false end
            return true
        end }
        om._appearance_husk_wield_context = { owner_unit_3p = {}, slot_name = "slot_ranged" }
        om._husk_identity_descriptor = exact_descriptor("cwv_fix_musket", CUSTOM_MESH)
        om._husk_custom_bundle_unit = function(u)
            return u == CUSTOM_MESH or u == CUSTOM_MESH .. "_3p"
        end
        local base_right = "units/weapons/player/wpn_fix_gun/wpn_fix_gun"
        local base_left = "units/weapons/player/wpn_fix_gun_mount/wpn_fix_gun_mount"
        local item_units = { right_hand_unit = base_right, left_hand_unit = base_left }
        with_env(env, function()
            H.equal(om._husk_preselect_units(item_units, { name = "fix_gun" }, nil, nil, "es_fix"), false,
                "unspawnable custom mesh must defer the whole hand-selection transaction")
        end)
        H.equal(item_units.right_hand_unit, base_right,
            "preselection must preserve the visible vanilla right hand on a residency miss")
        H.equal(item_units.left_hand_unit, base_left,
            "preselection must not clear vanilla's left hand unless the replacement transaction is admissible")
        H.equal(leases[1] and leases[1].path, DONOR_3P,
            "preselection must queue the same bounded donor lease as the re-key gate")
        H.truthy(joined(lines):find("base_preserved=true", 1, true),
            "deferred preselection needs bounded evidence that the base model survived")
        with_env(env, function()
            local suppress, template = om._husk_adapter_pre("right", {}, item_units,
                "slot_ranged", { name = "fix_gun" }, om._appearance_husk_wield_context.owner_unit_3p)
            H.equal(suppress, false, "deferred Musket base must still spawn")
            H.equal(template, nil, "deferred Musket must retain the base template")
        end)
        H.equal(item_units.right_hand_unit, base_right,
            "per-hand adapter must not re-key the deferred Musket after preselection")
        H.equal(item_units.left_hand_unit, base_left,
            "per-hand adapter must preserve the complete deferred base transaction")

        local om2, _, _, env2 = fixture()
        env2.Application = { can_get = function() return true end }
        om2._appearance_husk_wield_context = { owner_unit_3p = {}, slot_name = "slot_ranged" }
        om2._husk_identity_descriptor = exact_descriptor("cwv_fix_musket", CUSTOM_MESH)
        om2._husk_custom_bundle_unit = om._husk_custom_bundle_unit
        local resident = { right_hand_unit = base_right, left_hand_unit = base_left }
        with_env(env2, function()
            H.equal(om2._husk_preselect_units(resident, { name = "fix_gun" }, nil, nil, "es_fix"), true)
        end)
        H.equal(resident.right_hand_unit, CUSTOM_MESH,
            "resident custom mesh must be selected")
        H.equal(resident.left_hand_unit, nil,
            "resident exact descriptor may atomically remove the inherited left hand")
    end)

    H.test("#474/#660 asymmetric dual residency defers both later hand adapters", function()
        local om, lines, _, env = fixture()
        local pair = find_def("cwv_fix_pair")
        env.Application = { can_get = function(_, name)
            return name ~= pair.left_hand_unit .. "_3p"
        end }
        local owner = {}
        om._appearance_husk_wield_context = { owner_unit_3p = owner, slot_name = "slot_melee" }
        om._husk_identity_descriptor = function()
            return {
                variant_key = pair.item_key,
                right_hand_unit = pair.right_hand_unit,
                left_hand_unit = pair.left_hand_unit,
                fingerprint = "fp:" .. pair.item_key,
            }, "exact"
        end
        local base_right = "units/weapons/player/wpn_pair_base/wpn_pair_base"
        local base_left = "units/weapons/player/wpn_pair_shield/wpn_pair_shield"
        local item_units = { right_hand_unit = base_right, left_hand_unit = base_left }
        with_env(env, function()
            H.equal(om._husk_preselect_units(item_units, { name = "fix_pair_base" }, nil, nil, "es_fix"), false)
            local suppress_right = om._husk_adapter_pre("right", {}, item_units,
                "slot_melee", { name = "fix_pair_base" }, owner)
            local suppress_left = om._husk_adapter_pre("left", {}, item_units,
                "slot_melee", { name = "fix_pair_base" }, owner)
            H.equal(suppress_right, false, "ready right hand must remain base when its sibling deferred")
            H.equal(suppress_left, false, "unready left hand must remain the spawnable base")
        end)
        H.equal(item_units.right_hand_unit, base_right,
            "right-hand re-key cannot escape an atomic dual-hand deferral")
        H.equal(item_units.left_hand_unit, base_left,
            "left-hand re-key cannot escape an atomic dual-hand deferral")
        H.truthy(joined(lines):find("adapter=spawn deferred", 1, true),
            "complete adapter deferral must emit bounded evidence")
    end)

    H.test("#474/#478 atomic deferral retains the base-unit crash floor", function()
        local om, lines, _, env = fixture()
        local owner = {}
        local base_right = "units/weapons/player/wpn_fix_gun/wpn_fix_gun"
        env.Application = { can_get = function(kind, name)
            if kind == "material" then return false end
            if kind == "unit" and name == base_right .. "_3p" then return false end
            return true
        end }
        om._appearance_husk_wield_context = { owner_unit_3p = owner, slot_name = "slot_ranged" }
        om._husk_identity_descriptor = exact_descriptor("cwv_fix_musket", CUSTOM_MESH)
        om._husk_custom_bundle_unit = function(u)
            return u == CUSTOM_MESH or u == CUSTOM_MESH .. "_3p"
        end
        local base_left = "units/weapons/player/wpn_fix_gun_mount/wpn_fix_gun_mount"
        local item_units = { right_hand_unit = base_right, left_hand_unit = base_left }
        with_env(env, function()
            H.equal(om._husk_preselect_units(item_units, { name = "fix_gun" }, nil, nil, "es_fix"), false)
            local suppress = om._husk_adapter_pre("right", {}, item_units,
                "slot_ranged", { name = "fix_gun" }, owner)
            H.equal(suppress, true,
                "a nonresident retained base must still be suppressed before vanilla's unsafe spawn")
        end)
        H.equal(item_units.right_hand_unit, base_right,
            "base crash-floor suppression must not mutate the deferred transaction")
        H.equal(item_units.left_hand_unit, base_left,
            "base crash-floor suppression must preserve the sibling hand")
        H.truthy(joined(lines):find("retained base unit", 1, true),
            "base crash-floor suppression needs bounded evidence")
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

    -- ====================================================================
    -- Issue 786 -- Combat Style switch left the OTHER player's husk stale.
    -- Three legs, two fixed here:
    --   A. the style receiver re-wielded the husk INLINE (bypassing the #1145
    --      coalescer's mid-destroy guard and newest-wins merge) and graded the
    --      result with `right_live or left_live` -- an OR of setter-ish state
    --      (BUG_CLASSES 58). A husk still wearing the PRE-SWITCH weapon, or a
    --      shield style missing its off-hand, reported refreshed=true.
    --   B. a style switch published five scalars and NEVER republished item
    --      identity, so the deferred re-wield resolved the last published
    --      identity. The style axis now rides the delivering identity payload
    --      (the proven #474 musket_mode shape) and is applied BEFORE the
    --      changed-dedupe gate, because a style toggle leaves the identity
    --      signature byte-identical.
    -- ====================================================================
    local Policy = assert(loadfile(mod_root .. "_cwv_combat_styles.lua"))()
    local Rewield = assert(loadfile(mod_root .. "_cwv_style_rewield.lua"))()
    local coalescer_path = mod_root .. "_cwv_rewield_coalescer.lua"
    local styles_path = mod_root .. "_cwv_combat_styles.lua"
    local rewield_path = mod_root .. "_cwv_style_rewield.lua"

    -- One remote wearer whose husk really re-wields: `wield` re-populates the
    -- 3P hand units from `hands`, so a test can make the rebuild come back with
    -- one hand, both hands, or the wrong template.
    local function husk_fixture(opts)
        opts = opts or {}
        local slot_name = opts.slot or "slot_melee"
        local hands = { right = opts.right ~= false, left = opts.left == true }
        local wields = {}
        local equipment = {
            slots = { [slot_name] = { item_data = { name = opts.item_key or "es_deus_01" } } },
            wielded_slot = slot_name,
        }
        local inventory = { _equipment = equipment, wielded_slot = slot_name }
        inventory.wield = function(_, slot)
            wields[#wields + 1] = slot
            if opts.on_wield then opts.on_wield(equipment, hands) end
            equipment.right_hand_wielded_unit_3p = hands.right and { "r" } or nil
            equipment.left_hand_wielded_unit_3p = hands.left and { "l" } or nil
        end
        local unit = { "wearer" }
        return {
            slot = slot_name, hands = hands, wields = wields,
            equipment = equipment, inventory = inventory, unit = unit,
        }
    end

    -- Full A+B wiring on real modules: the shipped coalescer, the shipped
    -- combat-style runtime and the shipped verdict policy.
    local function style_fixture(opts)
        opts = opts or {}
        local husk = husk_fixture(opts)
        local Coalescer = assert(loadfile(coalescer_path))()
        local lines, sent, settings = {}, {}, {}
        local unit_api = { alive = function() return true end }
        local script_unit = {
            extension = function() return husk.inventory end,
            has_extension = function() return husk.inventory end,
        }
        local managers = { player = {
            player_from_peer_id = function() return { player_unit = husk.unit } end,
        } }
        local deps = {
            policy = Policy, coalescer = Coalescer, managers = managers,
            unit_api = unit_api, script_unit = script_unit, probe_state = {},
            printf = function(fmt, ...) lines[#lines + 1] = string.format(fmt, ...) end,
            peer_player = function() return { player_unit = husk.unit }, "test" end,
            item_key = function(item_data) return item_data and item_data.name end,
            effective_template = function()
                if opts.observed_template ~= nil then return opts.observed_template end
                return husk.equipment.slots[husk.slot].item_data.observed_template
            end,
            style_resource_resident = opts.style_resource_resident,
        }
        local mod = {
            get = function(_, key) return settings[key] end,
            set = function(_, key, value) settings[key] = value end,
            network_send = function(_, channel, recipient, ...)
                sent[#sent + 1] = { channel = channel, recipient = recipient, n = select("#", ...) }
                return true
            end,
        }
        local runtime = Policy.install(mod, {
            rewield = Rewield,
            rebuild_remote = function(peer_id, slot_name, family_id, style_id, on_verdict)
                return Rewield.queue_rebuild(deps, peer_id, slot_name,
                    family_id, style_id, on_verdict)
            end,
        })
        local saved_printf = _G.printf
        _G.printf = deps.printf
        return {
            husk = husk, runtime = runtime, coalescer = Coalescer, deps = deps,
            lines = lines, sent = sent,
            drain = function() return Coalescer.drain({ silent = true,
                unit_api = unit_api, script_unit = script_unit }) end,
            release = function() _G.printf = saved_printf end,
        }
    end

    local function with_fixture(opts, body)
        local fx = style_fixture(opts)
        local ok, err = pcall(body, fx)
        fx.release()
        if not ok then error(err, 0) end
    end

    H.test("#786 A2 verdict is AND-semantics over the AUTHORED expectation", function()
        local expected = Rewield.expectation(Policy, "spear_shield", "elven", "es_deus_01")
        H.equal(expected.template, Policy.ELVEN_SPEAR_SHIELD_TEMPLATE)
        H.equal(expected.left, true, "an authored shield family must expect BOTH hands")
        local base = { wielded = true, item_key = "es_deus_01",
            template = Policy.ELVEN_SPEAR_SHIELD_TEMPLATE,
            right_live = true, left_live = true }
        H.equal(Rewield.verdict(expected, base), "ok")
        H.equal(Rewield.succeeded("ok"), true)
        -- Exactly what the retired `right_live or left_live` predicate passed.
        local one_hand = { wielded = true, item_key = "es_deus_01",
            template = Policy.ELVEN_SPEAR_SHIELD_TEMPLATE,
            right_live = true, left_live = false }
        local status, detail = Rewield.verdict(expected, one_hand)
        H.equal(status, "partial", "a missing off-hand is NOT success")
        H.truthy(detail:find("missing=left", 1, true), "detail must name the hand")
        H.equal(Rewield.succeeded(status), false, "partial application is failure")
        local wrong = Rewield.verdict(expected, { wielded = true, item_key = "es_deus_01",
            template = Policy.EMPIRE_SPEAR_SHIELD_TEMPLATE,
            right_live = true, left_live = true })
        H.equal(wrong, "wrong-template", "both hands live is not proof of the style")
        H.equal(Rewield.verdict(expected, { wielded = true, item_key = "es_2h_sword",
            template = Policy.ELVEN_SPEAR_SHIELD_TEMPLATE,
            right_live = true, left_live = true }), "wrong-template",
            "a husk still wearing the pre-switch item must fail")
        H.equal(Rewield.verdict(expected, { wielded = false,
            right_live = true, left_live = true }), "failed")
        H.equal(Rewield.verdict(nil, base), "failed")
    end)

    H.test("#786 A2 expectation comes from the authored catalogue, never the husk", function()
        H.equal(Rewield.expectation(Policy, "greatsword", "kerillian", "wh_2h_sword").template,
            Policy.KERILLIAN_TEMPLATE)
        -- An authored RECEIVER override is ground truth too.
        H.equal(Rewield.expectation(Policy, "greatsword", "bretonnian", "wh_2h_sword").template,
            Policy.SALTZ_BRETONNIAN_TEMPLATE)
        H.equal(Rewield.expectation(Policy, "greatsword", "kerillian", "es_2h_sword").left,
            false, "a two-hander must not demand an off-hand unit")
        H.equal(select(2, Rewield.expectation(Policy, "greatsword", "kerillian", "es_deus_01")),
            "item family mismatch")
        H.equal(select(2, Rewield.expectation(Policy, "greatsword", "kerillian", nil)),
            "slot not ready")
        H.equal(select(2, Rewield.expectation(Policy, "greatsword", "no_such_style", "es_2h_sword")),
            "style not authored")
        H.equal(select(2, Rewield.expectation(Policy, "greatsword", "kerillian", "fix_base")),
            "item not a style member")
    end)

    H.test("#786 A1 the rebuild goes to the coalescer and the verdict waits for the drain", function()
        with_fixture({ item_key = "es_deus_01", left = true,
                observed_template = Policy.ELVEN_SPEAR_SHIELD_TEMPLATE }, function(fx)
            local verdicts = {}
            local queued, why = Rewield.queue_rebuild(fx.deps, "peerA", "slot_melee",
                "spear_shield", "elven", function(status, detail)
                    verdicts[#verdicts + 1] = { status = status, detail = detail }
                end)
            H.equal(queued, true)
            H.equal(why, "queued")
            H.equal(#fx.husk.wields, 0, "queue_rebuild must NOT wield inline")
            H.equal(#verdicts, 0, "no synchronous verdict may be manufactured")
            H.equal(fx.coalescer.depth(), 1, "the request must sit in the coalescer queue")
            local executed = fx.drain()
            H.equal(executed, 1)
            H.deep_equal(fx.husk.wields, { "slot_melee" }, "the drain owns the wield")
            H.equal(#verdicts, 1, "the verdict arrives from inside the drain")
            H.equal(verdicts[1].status, "ok")
            H.truthy(table.concat(fx.lines, "\n"):find("[cwv:786] rebuild target", 1, true))
        end)
    end)

    H.test("#786 A1/A3 an unready husk never queues and stays retryable", function()
        with_fixture({}, function(fx)
            fx.husk.inventory.wielded_slot = "slot_ranged"
            fx.husk.equipment.wielded_slot = "slot_ranged"
            local queued, reason = Rewield.queue_rebuild(fx.deps, "peerA", "slot_melee",
                "spear_shield", "elven", function() end)
            H.equal(queued, false)
            H.equal(reason, "slot not wielded")
            H.equal(fx.coalescer.depth(), 0)
            H.equal(Policy.remote_refresh_retryable("slot not ready"), true)
            H.equal(Policy.remote_refresh_retryable("slot not wielded"), false)
        end)
    end)

    H.test("#786 A3 one ledger: retry on partial, stop on success, stop at the cap", function()
        with_fixture({ item_key = "es_deus_01", left = false,
                observed_template = Policy.ELVEN_SPEAR_SHIELD_TEMPLATE }, function(fx)
            fx.runtime:accept_style_edge("peerA", "slot_melee", "spear_shield",
                "elven", "identity")
            H.equal(fx.runtime:pending_remote_refresh_count(), 1)
            fx.drain()                       -- shield style rebuilt without its off-hand
            fx.runtime:step(0)               -- consume the partial verdict
            H.equal(fx.runtime:pending_remote_refresh_count(), 1,
                "a partial verdict must stay in the ledger, not terminate")
            local joined_lines = table.concat(fx.lines, "\n")
            H.truthy(joined_lines:find("[cwv:786] verdict partial", 1, true))
            -- The off-hand shows up: the very next attempt must settle the ledger.
            fx.husk.hands.left = true
            fx.runtime:step(Policy.REMOTE_REFRESH_INTERVAL)   -- re-enqueue
            fx.drain()
            local completed = fx.runtime:step(0)
            H.equal(completed, 1)
            H.equal(fx.runtime:pending_remote_refresh_count(), 0, "success stops the ledger")
            H.truthy(table.concat(fx.lines, "\n"):find("[cwv:786] verdict ok", 1, true))
        end)
        -- Cap: a husk that never comes back with its off-hand must terminate.
        with_fixture({ item_key = "es_deus_01", left = false,
                observed_template = Policy.ELVEN_SPEAR_SHIELD_TEMPLATE }, function(fx)
            fx.runtime:accept_style_edge("peerA", "slot_melee", "spear_shield",
                "elven", "identity")
            -- Two ticks per attempt: one consumes the failing verdict and re-arms,
            -- the next re-enqueues. The cap must still be reached exactly once.
            local expired = 0
            for _ = 1, Policy.MAX_REMOTE_REFRESH_ATTEMPTS * 3 do
                fx.drain()
                local _, gone = fx.runtime:step(Policy.REMOTE_REFRESH_INTERVAL)
                expired = expired + gone
            end
            H.equal(expired, 1, "the ledger must expire exactly once at the cap")
            H.equal(fx.runtime:pending_remote_refresh_count(), 0)
            H.truthy(table.concat(fx.lines, "\n"):find("terminal=true", 1, true))
        end)
        -- A style change under a pending entry retires it; it never re-wields
        -- toward the style the wearer already left.
        with_fixture({ item_key = "es_deus_01", left = false,
                observed_template = Policy.ELVEN_SPEAR_SHIELD_TEMPLATE }, function(fx)
            fx.runtime:accept_style_edge("peerA", "slot_melee", "spear_shield",
                "elven", "identity")
            fx.drain()
            fx.runtime:accept_style_edge("peerA", "slot_melee", "spear_shield",
                "empire", "identity")
            fx.runtime:step(Policy.REMOTE_REFRESH_INTERVAL)
            H.equal(fx.runtime:pending_remote_refresh_count(), 1,
                "only the newest style edge may own the ledger")
        end)
    end)

    H.test("#786 B5 both arrival orders and duplicates converge on ONE re-wield", function()
        -- style channel first, identity second.
        with_fixture({ item_key = "es_deus_01", left = true,
                observed_template = Policy.ELVEN_SPEAR_SHIELD_TEMPLATE }, function(fx)
            fx.runtime:accept_style_edge("peerA", "slot_melee", "spear_shield",
                "elven", "style_channel")
            H.equal(fx.coalescer.depth(), 0,
                "the style channel must not fire its own unguarded rebuild")
            local owned = fx.runtime:accept_style_edge("peerA", "slot_melee",
                "spear_shield", "elven", "identity")
            H.equal(owned, true, "the identity path owns the rebuild for this edge")
            H.equal(fx.coalescer.depth(), 1)
            H.equal(fx.drain(), 1)
            H.deep_equal(fx.husk.wields, { "slot_melee" })
        end)
        -- identity first, style channel second.
        with_fixture({ item_key = "es_deus_01", left = true,
                observed_template = Policy.ELVEN_SPEAR_SHIELD_TEMPLATE }, function(fx)
            H.equal(fx.runtime:accept_style_edge("peerA", "slot_melee",
                "spear_shield", "elven", "identity"), true)
            H.equal(fx.runtime:accept_style_edge("peerA", "slot_melee",
                "spear_shield", "elven", "style_channel"), false,
                "a duplicate token must not re-arm anything")
            H.equal(fx.coalescer.depth(), 1, "still exactly one queued re-wield")
            fx.drain()
            H.deep_equal(fx.husk.wields, { "slot_melee" })
        end)
        -- duplicate deliveries on either channel.
        with_fixture({ item_key = "es_deus_01", left = true,
                observed_template = Policy.ELVEN_SPEAR_SHIELD_TEMPLATE }, function(fx)
            fx.runtime:accept_style_edge("peerA", "slot_melee", "spear_shield", "elven", "identity")
            fx.runtime:accept_style_edge("peerA", "slot_melee", "spear_shield", "elven", "identity")
            fx.runtime:accept_style_edge("peerA", "slot_melee", "spear_shield", "elven", "style_channel")
            H.equal(fx.coalescer.depth(), 1)
            fx.drain()
            H.deep_equal(fx.husk.wields, { "slot_melee" },
                "duplicates must collapse to exactly one re-wield")
            H.equal(fx.runtime:pending_remote_refresh_count(), 1)
        end)
    end)

    H.test("#786 B4 a style-only peer still recovers through the bounded fallback", function()
        with_fixture({ item_key = "es_deus_01", left = true,
                observed_template = Policy.ELVEN_SPEAR_SHIELD_TEMPLATE }, function(fx)
            fx.runtime:accept_style_edge("peerA", "slot_melee", "spear_shield",
                "elven", "style_channel")
            fx.runtime:step(0)
            H.equal(fx.coalescer.depth(), 0, "the grace window has not elapsed")
            fx.runtime:step(Policy.STYLE_IDENTITY_GRACE)
            H.equal(fx.coalescer.depth(), 1,
                "no identity rider ever arrived: the style channel must recover")
            fx.drain()
            H.deep_equal(fx.husk.wields, { "slot_melee" })
            H.truthy(table.concat(fx.lines, "\n"):find("style_channel_fallback", 1, true))
        end)
    end)

    H.test("#786 B1 the style rider is one compact authored-closed field", function()
        H.equal(Policy.encode_style_rider("spear_shield", "elven"), "spear_shield:elven")
        H.equal(Policy.encode_style_rider("spear_shield", "no_such_style"), nil)
        H.equal(Policy.encode_style_rider("no_such_family", "elven"), nil)
        H.equal(Policy.encode_style_rider(nil, "elven"), nil)
        local family_id, style_id = Policy.decode_style_rider("greathammer:warrior_priest")
        H.equal(family_id, "greathammer")
        H.equal(style_id, "warrior_priest")
        H.equal(Policy.decode_style_rider("greathammer:not_a_style"), nil)
        H.equal(Policy.decode_style_rider("greathammer"), nil)
        H.equal(Policy.decode_style_rider(""), nil)
        H.equal(Policy.decode_style_rider(nil), nil)
        H.equal(Policy.decode_style_rider(string.rep("a", Policy.STYLE_RIDER_MAX + 1)), nil)
        -- Worst authored pair, and its cost against VMF's 500-char RPC cap.
        local worst = 0
        for family_id_key, family in pairs(Policy.FAMILIES) do
            for style_key in pairs(family.styles) do
                local rider = Policy.encode_style_rider(family_id_key, style_key)
                worst = math.max(worst, #('"style":"' .. rider .. '",'))
            end
        end
        H.equal(worst, 37, "worst-case style rider JSON must stay a bounded 37 chars")
    end)

    H.test("#786 stage C residency probe observes without acquiring or gating", function()
        local asked = {}
        with_fixture({ item_key = "es_deus_01", left = true,
                observed_template = Policy.ELVEN_SPEAR_SHIELD_TEMPLATE,
                style_resource_resident = function(path)
                    asked[#asked + 1] = path
                    return false
                end }, function(fx)
            Rewield.queue_rebuild(fx.deps, "peerA", "slot_melee", "spear_shield",
                "elven", function() end)
            H.equal(#asked, 1, "the probe reads residency exactly once per edge")
            H.equal(asked[1], Policy.FAMILIES.spear_shield.styles.elven.resource)
            local all = table.concat(fx.lines, "\n")
            H.truthy(all:find("[cwv:786] style residency family=spear_shield style=elven", 1, true))
            H.truthy(all:find("resident=false", 1, true))
            H.equal(fx.coalescer.depth(), 1,
                "an absent resource must NOT gate the rebuild (observation only)")
            -- Bounded: the same triple never logs twice.
            Rewield.queue_rebuild(fx.deps, "peerA", "slot_melee", "spear_shield",
                "elven", function() end)
            H.equal(#asked, 1)
        end)
    end)

    H.test("#786 entry + module wiring anchors", function()
        local main = read(main_path)
        local styles = read(styles_path)
        local rewield_source = read(rewield_path)
        local coalescer_source = read(coalescer_path)
        for _, marker in ipairs({
            -- A1: the entry adapter delegates; it no longer wields inline.
            "return _om.style_rewield.queue_rebuild(_style_rewield_deps, peer_id,",
            "coalescer = mod._cwv_rewield",
            -- B1: the style axis is stamped on the delivering identity payload.
            "_om.combat_styles.local_style_rider",
            "if ok_style and rider then payload.style = rider end",
            -- B3: applied BEFORE the changed-dedupe gate.
            "_om.combat_style_policy.decode_style_rider(payload.style)",
            "sender_peer_id, payload.slot, fam, sid, \"identity\") == true end",
            "if not style_owned then",
        }) do
            H.truthy(main:find(marker, 1, true), "missing entry #786 anchor: " .. marker)
        end
        local gate = main:find("if not changed then return end", 1, true)
        H.truthy(gate, "the identity changed-dedupe gate must still exist")
        H.truthy(main:find("decode_style_rider", 1, true) < gate,
            "the style axis must be applied BEFORE the changed-dedupe gate (#474 precedent)")
        for _, marker in ipairs({
            "function runtime:accept_style_edge(peer_id, slot_name, family_id, style_id, source)",
            "pcall(deps.send_identity_slots, equipment.slots, \"combat_style\", true)",
            "off_hand = true,",
            "M.STYLE_IDENTITY_GRACE",
        }) do
            H.truthy(styles:find(marker, 1, true), "missing combat-style #786 anchor: " .. marker)
        end
        -- The retired OR predicate must not come back in live code. It survives
        -- only in the module's header post-mortem, above the first function.
        H.equal(main:find("right_live or left_live", 1, true), nil)
        local first_fn = rewield_source:find("\nlocal function ", 1, true)
        H.truthy(first_fn)
        H.equal(rewield_source:find("right_live or left_live", first_fn, true), nil,
            "AND-semantics only: no OR of hand liveness in live code")
        H.truthy(rewield_source:find(
            "if expected.left == true and observed.left_live ~= true then", 1, true),
            "the off-hand must be asserted independently")
        H.truthy(coalescer_source:find("pcall(on_verify, unit, inventory, slot, wield_error)", 1, true),
            "the coalescer must own the post-drain verification callback")
    end)
end
