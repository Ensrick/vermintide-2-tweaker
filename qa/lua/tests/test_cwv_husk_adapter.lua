-- Engine-free coverage for the COMPLETE husk adapter at the
-- GearUtils.spawn_inventory_unit seam (issues 394/398/399/401/474/476/482/719,
-- BUG_CLASSES class 27 -- husk consumed only a PARTIAL variant definition):
--   * full-definition resolution: mesh re-key + pre-spawn ammo-nil + clone
--     template identity from ONE positive-identity resolution;
--   * FAIL-CLOSED residency (#474 MeshObject AV killer): explicitly borrowed
--     meshes gate on their vanilla donor MATERIAL, while self-contained bundles
--     do not; non-force-loaded vanilla overrides gate on direct engine proof;
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
	local install_musket_wire = assert(loadfile(
		mod_root .. "_cwv_old_musket_wire.lua"))()
	local old_musket_pose = dofile(mod_root .. "_cwv_old_musket_preview_pose.lua")

    local function read(path)
        local file = assert(io.open(path, "rb"))
        local source = file:read("*a")
        file:close()
        return source
    end

    local CUSTOM_MESH = "units/cwv_es_musket_custom/cwv_es_musket_custom"
    local CUSTOM_MESH_3P = CUSTOM_MESH .. "_3p"
    local BORROWED_MESH = "units/cwv_test_borrowed/cwv_test_borrowed"
    local DONOR_3P = "units/weapons/player/wpn_empire_handgun_t1/wpn_empire_handgun_t1_3p"
    local AXE_OVERRIDE = "units/weapons/player/wpn_fix_axe/wpn_fix_axe"
    local BASE_UNIT = "units/weapons/player/wpn_fix_base/wpn_fix_base"
    local OLD_MUSKET_DEF = {
        item_key = "cwv_es_musket_old",
        base_weapon = "fix_gun",
        careers = { "es_fix" },
        right_hand_unit = CUSTOM_MESH,
        item_type = "cwv_es_musket_old",
		template = "old_musket_template",
		effective_templates = {
			{ name = "old_musket_template" },
			{ name = "old_musket_template_melee" },
		},
    }

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
            item_key = "cwv_fix_borrowed",
            base_weapon = "fix_gun",
            careers = { "es_fix" },
            right_hand_unit = BORROWED_MESH,
            item_type = "cwv_fix_borrowed",
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
        if key == OLD_MUSKET_DEF.item_key then return OLD_MUSKET_DEF end
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
				old_musket_template = {
					wield_anim = "to_handgun",
					right_hand_attachment_node_linking = {
						third_person = { wielded = { profile = "rifle" } },
					},
				},
				old_musket_template_melee = {
					wield_anim = "to_polearm",
					right_hand_attachment_node_linking = {
						third_person = { wielded = { profile = "polearm" } },
					},
				},
            },
            Managers = {
                package = {
                    load = function(_, path, ref) leases[#leases + 1] = { path = path, ref = ref } end,
                    has_loaded = function() return false end,
                },
            },
			NetworkLookup = { anims = {} },
        }
        assert(loadfile(module_path))()(nil, {
            om = om,
            variant_definitions = DEFS,
            find_def = find_def,
            is_unit = function(u) return u ~= nil end,
            apply_cwv_hand_transform = function() return true end,
            triplet_text = function() return "t" end,
        })
        om._husk_custom_unit_material_donors[BORROWED_MESH] = DONOR_3P
        om._husk_custom_unit_material_donors[BORROWED_MESH .. "_3p"] = DONOR_3P
        return om, lines, leases, env
    end

    -- Install the real Old Musket identity guard around a deliberately tiny
    -- engine fixture. This keeps the ledger tests behavioral: a fabricated
    -- expected path would paint the substituted target and make them fail.
    local function install_old_musket_guard(om)
        local Descriptor = dofile(repo_root .. "/tools/shared_lib/_lib_appearance_descriptor.lua")
        local Pilot = dofile(mod_root .. "_cwv_old_musket_appearance.lua")
        local profiles = {
            held_1p_rifle = "held_1p_rifle",
            held_1p_polearm = "held_1p_polearm",
            held_3p_rifle_character = "held_3p_rifle_character",
            held_3p_polearm_character = "held_3p_polearm_character",
            display_3p_rifle = "display_3p_rifle",
        }
        local profile_positions = {
            [profiles.held_1p_rifle] = { 1, 0, 0 },
            [profiles.held_1p_polearm] = { 2, 0, 0 },
            [profiles.held_3p_rifle_character] = { 3, 0, 0 },
            [profiles.held_3p_polearm_character] = { 4, 0, 0 },
            [profiles.display_3p_rifle] = { 5, 0, 0 },
        }
        om.old_musket_attachment_profiles = profiles
		om.old_musket_preview_pose = old_musket_pose
		om.outrider_animation = om.outrider_animation or {
			dispatch_event = function() return true, "dispatched" end,
		}
        om._old_musket_attachment_profile = function(perspective, mode, carrier)
            if carrier == "display" then return profiles.display_3p_rifle end
            if perspective == "1p" then
                return mode == "melee" and profiles.held_1p_polearm
                    or profiles.held_1p_rifle
            end
            return mode == "melee" and profiles.held_3p_polearm_character
                or profiles.held_3p_rifle_character
        end
        local quaternion = setmetatable({
            to_elements = function(value)
                return value[1], value[2], value[3], value[4]
            end,
			from_elements = function(x, y, z, w) return { x, y, z, w } end,
        }, {
            __call = function(_, x, y, z, w) return { x, y, z, w } end,
        })
        local unit_api = {
            alive = function(unit) return unit and unit.dead ~= true end,
            local_position = function(unit) return unit.position end,
            local_scale = function(unit) return unit.scale end,
            local_rotation = function(unit) return unit.rotation end,
        }
        om.old_musket_appearance = Pilot.new({
            descriptor = Descriptor,
            weapon_appearance = {
                apply_report = function(unit, spec)
					local rotation = spec.rotation
					if type(rotation) == "table"
							and type(rotation.unbox) == "function" then
						rotation = rotation:unbox()
					end
                    unit.position, unit.scale, unit.rotation =
						spec.position, spec.scale, rotation
					return { ok = rotation ~= nil }
                end,
            },
            policy = {
                ITEM_KEY = OLD_MUSKET_DEF.item_key,
                SKIN_KEY = OLD_MUSKET_DEF.item_key .. "_skin",
                UNIT = CUSTOM_MESH,
                UNIT_3P = CUSTOM_MESH_3P,
                PREVIEW_PACKAGE_ALIAS = "units/vanilla/handgun_3p",
                NETWORK_PACKAGE_ALIAS_1P = "units/vanilla/handgun",
                NETWORK_PACKAGE_ALIAS_3P = "units/vanilla/handgun_3p",
                MATERIAL = CUSTOM_MESH,
                PREVIEW_MATERIAL = CUSTOM_MESH,
                TEXTURES = {},
                matches_item = function(_, key)
                    return key == OLD_MUSKET_DEF.item_key
                end,
                apply_material = function() return true, 0 end,
                unit_materials_ready = function() return true end,
            },
            unit = unit_api,
            vector = nil,
            quaternion = quaternion,
            transform_profile_source = function(profile)
                local position = profile_positions[profile]
                if not position then return nil, nil, nil end
                return position, { 0, 0, 0, 1 }, { 0.9, 0.9, 0.9 }
            end,
            attachment_profiles = profiles,
            canonical_key = function(item) return item and item.cwv_key end,
            printf = function() end,
        })
        om._old_musket_mode_for_owner = function() return "ranged" end
        om._husk_strip_cwv_ammo = function() return false end
        om._husk_apply_cwv_transform = function() end
        om._probe_579_hand_compare = function() end
        return profiles, profile_positions
    end

    local function old_musket_husk_result(om, owner, slot_name, unit)
        return om._old_musket_husk_wield(
            { _unit = owner },
            { right_hand_wielded_unit_3p = unit },
            slot_name,
            { skin = OLD_MUSKET_DEF.item_key .. "_skin" },
            { variant_key = OLD_MUSKET_DEF.item_key })
    end

    -- Swap the stub globals in around a call, restore after (repo pattern:
    -- test_cwv_exact_pair_state.lua).
    local GLOBAL_KEYS = {
        "printf", "ScriptUnit", "Unit", "ItemMasterList", "WeaponSkins",
        "Weapons", "Managers", "Application",
		"NetworkLookup",
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

	local function record_old_musket_spawn(om, env, owner, slot_name, unit,
			mode, observed_unit)
		om._old_musket_mode_for_owner = function() return mode or "ranged" end
		om._husk_identity_descriptor = exact_descriptor(
			OLD_MUSKET_DEF.item_key, CUSTOM_MESH)
		local item_units = { right_hand_unit = observed_unit or CUSTOM_MESH }
		local evidence
		with_env(env, function()
			local _, _, selected = om._husk_template_for_spawn(
				"right", {}, item_units, slot_name, { name = "fix_gun" }, owner)
			evidence = selected
			om._husk_adapter_post("right", { name = "fix_gun" }, item_units,
				slot_name, owner, unit, nil, evidence)
		end)
		return evidence
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

	H.test("#1155 Old Musket husk spawn selects the template and profile from one exact mode", function()
		for _, case in ipairs({
			{ mode = "ranged", template = "old_musket_template",
				profile = "held_3p_rifle_character", event = "to_handgun" },
			{ mode = "melee", template = "old_musket_template_melee",
				profile = "held_3p_polearm_character", event = "to_polearm" },
		}) do
			local om, _, _, env = fixture()
			local profiles = install_old_musket_guard(om)
			om._old_musket_mode_for_owner = function() return case.mode end
			om._husk_identity_descriptor = exact_descriptor(
				OLD_MUSKET_DEF.item_key, CUSTOM_MESH)
			with_env(env, function()
				local selected, def, evidence = om._husk_template_for_spawn(
					"right", {}, { right_hand_unit = CUSTOM_MESH },
					"slot_ranged", { name = "fix_gun" }, {})
				H.equal(selected, env.Weapons[case.template])
				H.equal(def, OLD_MUSKET_DEF)
				H.equal(evidence.mode, case.mode)
				H.equal(evidence.template_name, case.template)
				H.equal(evidence.attachment_profile, profiles[case.profile])
				H.equal(evidence.template_ref, selected)
			end)
		end

		local om, _, _, env = fixture()
		install_old_musket_guard(om)
		om._old_musket_mode_for_owner = function() return "foreign" end
		om._husk_identity_descriptor = exact_descriptor(
			OLD_MUSKET_DEF.item_key, CUSTOM_MESH)
		with_env(env, function()
			H.equal(om._husk_template_for_spawn("right", {},
				{ right_hand_unit = CUSTOM_MESH }, "slot_ranged",
				{ name = "fix_gun" }, {}), nil)
		end)
	end)

    H.test("#1155 self-contained Old Musket bypasses foreign donor gating", function()
        local om, _, leases, env = fixture()
        env.Application = { can_get = function(kind)
            return kind ~= "material"
        end }
        om._husk_identity_descriptor = exact_descriptor("cwv_fix_musket", CUSTOM_MESH)
        om._husk_custom_bundle_unit = function(u)
            return u == CUSTOM_MESH or u == CUSTOM_MESH .. "_3p"
        end
        local item_units = {
            right_hand_unit = "units/weapons/player/wpn_fix_gun/wpn_fix_gun",
        }
        with_env(env, function()
            om._husk_rekey_units("right", { name = "fix_gun" },
                item_units, {}, "slot_ranged")
        end)
        H.equal(item_units.right_hand_unit, CUSTOM_MESH)
        H.equal(#leases, 0)
        H.equal(om._husk_custom_unit_material_donors[CUSTOM_MESH], nil)
        H.equal(om._husk_custom_unit_material_donors[CUSTOM_MESH .. "_3p"], nil)
    end)

    H.test("#474 fail-closed: synthetic borrowed mesh keeps base and leases donor", function()
        local om, lines, leases, env = fixture()
        env.Application = { can_get = function(kind, name)
            if kind == "material" then return false end
            return true
        end }
        om._husk_identity_descriptor = exact_descriptor("cwv_fix_borrowed", BORROWED_MESH)
        om._husk_custom_bundle_unit = function(u)
            return u == BORROWED_MESH or u == BORROWED_MESH .. "_3p"
        end
        local item_units = { right_hand_unit = "units/weapons/player/wpn_fix_gun/wpn_fix_gun" }
        with_env(env, function()
            local suppress = om._husk_rekey_units("right", { name = "fix_gun" },
                item_units, {}, "slot_ranged")
            H.equal(suppress, nil, "base identity stays spawnable -- no #478 suppress")
        end)
        H.equal(item_units.right_hand_unit, "units/weapons/player/wpn_fix_gun/wpn_fix_gun",
            "borrowed mesh must NOT be written while its donor material is missing (#474)")
        H.equal(leases[1] and leases[1].path, DONOR_3P,
            "donor package must be leased so the next wield resolves")
        H.equal(leases[1] and leases[1].ref, "cwv_husk_override_units")
        H.truthy(joined(lines):find("[cwv:474] husk donor-material lease", 1, true))

        -- Same shape with the donor resident: the authored mesh is written.
        local om2, _, _, env2 = fixture()
        env2.Application = { can_get = function() return true end }
        om2._husk_identity_descriptor = exact_descriptor("cwv_fix_borrowed", BORROWED_MESH)
        om2._husk_custom_bundle_unit = om._husk_custom_bundle_unit
        local item_units2 = { right_hand_unit = "units/weapons/player/wpn_fix_gun/wpn_fix_gun" }
        with_env(env2, function()
            om2._husk_rekey_units("right", { name = "fix_gun" }, item_units2, {}, "slot_ranged")
        end)
        H.equal(item_units2.right_hand_unit, BORROWED_MESH,
            "resident donor must admit the authored custom mesh")
    end)

    H.test("#474/#660 handedness preselection preserves base until the custom mesh is spawnable", function()
        local om, lines, leases, env = fixture()
        env.Application = { can_get = function(kind)
            if kind == "material" then return false end
            return true
        end }
        om._appearance_husk_wield_context = { owner_unit_3p = {}, slot_name = "slot_ranged" }
        om._husk_identity_descriptor = exact_descriptor("cwv_fix_borrowed", BORROWED_MESH)
        om._husk_custom_bundle_unit = function(u)
            return u == BORROWED_MESH or u == BORROWED_MESH .. "_3p"
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
            H.equal(suppress, false, "deferred borrowed-mesh base must still spawn")
            H.equal(template, nil, "deferred borrowed mesh must retain the base template")
        end)
        H.equal(item_units.right_hand_unit, base_right,
            "per-hand adapter must not re-key the deferred borrowed mesh after preselection")
        H.equal(item_units.left_hand_unit, base_left,
            "per-hand adapter must preserve the complete deferred base transaction")

        local om2, _, _, env2 = fixture()
        env2.Application = { can_get = function() return true end }
        om2._appearance_husk_wield_context = { owner_unit_3p = {}, slot_name = "slot_ranged" }
        om2._husk_identity_descriptor = exact_descriptor("cwv_fix_borrowed", BORROWED_MESH)
        om2._husk_custom_bundle_unit = om._husk_custom_bundle_unit
        local resident = { right_hand_unit = base_right, left_hand_unit = base_left }
        with_env(env2, function()
            H.equal(om2._husk_preselect_units(resident, { name = "fix_gun" }, nil, nil, "es_fix"), true)
        end)
        H.equal(resident.right_hand_unit, BORROWED_MESH,
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

    H.test("#579 exact dual descriptor re-keys distinct right and left hands through the live adapter", function()
        local om, _, _, env = fixture()
        local pair = find_def("cwv_fix_pair")
        env.Application = { can_get = function() return true end }
        om._husk_identity_descriptor = function()
            return {
                variant_key = pair.item_key,
                right_hand_unit = pair.right_hand_unit,
                left_hand_unit = pair.left_hand_unit,
                fingerprint = "fp:" .. pair.item_key,
            }, "exact"
        end
        local item_units = {
            right_hand_unit = "units/weapons/player/wpn_pair_base/wpn_pair_base",
            left_hand_unit = "units/weapons/player/wpn_pair_base_left/wpn_pair_base_left",
        }
        with_env(env, function()
            local suppress_right = om._husk_adapter_pre("right", {}, item_units,
                "slot_melee", { name = "fix_pair_base" }, {})
            local suppress_left = om._husk_adapter_pre("left", {}, item_units,
                "slot_melee", { name = "fix_pair_base" }, {})
            H.equal(suppress_right, false)
            H.equal(suppress_left, false)
        end)
        H.equal(item_units.right_hand_unit, pair.right_hand_unit,
            "right-hand delivery must consume descriptor.right_hand_unit")
        H.equal(item_units.left_hand_unit, pair.left_hand_unit,
            "offhand delivery must independently consume descriptor.left_hand_unit")
        H.truthy(item_units.right_hand_unit ~= item_units.left_hand_unit,
            "the test fixture must remain asymmetric so a collapsed pair cannot pass")
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
        om._husk_identity_descriptor = exact_descriptor("cwv_fix_borrowed", BORROWED_MESH)
        om._husk_custom_bundle_unit = function(u)
            return u == BORROWED_MESH or u == BORROWED_MESH .. "_3p"
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

    H.test("#1155 stable husk equip accepts only the exact custom spawn observation", function()
		local om, _, _, env = fixture()
        local profiles, positions = install_old_musket_guard(om)
        local owner, custom_unit = {}, {}
		record_old_musket_spawn(om, env, owner, "slot_ranged", custom_unit, "ranged")

        H.equal(om._husk_observed_unit_name(custom_unit, owner,
            "slot_ranged", "right"), CUSTOM_MESH_3P)
		local accepted
		with_env(env, function()
			accepted = old_musket_husk_result(om, owner,
				"slot_ranged", custom_unit)
		end)
        H.equal(accepted.retained, true,
            "an exact returned unit/path/owner/slot/hand observation must reach stable equip")
        H.deep_equal(custom_unit.position,
            positions[profiles.held_3p_rifle_character],
            "husk equip must consume the exact held-3P rifle attachment profile")

		local om_vanilla, _, _, vanilla_env = fixture()
        install_old_musket_guard(om_vanilla)
        local vanilla_unit = {}
		record_old_musket_spawn(om_vanilla, vanilla_env, owner, "slot_ranged",
			vanilla_unit, "ranged",
			"units/weapons/player/wpn_empire_handgun_t1/wpn_empire_handgun_t1")
		local declined
		with_env(vanilla_env, function()
			declined = old_musket_husk_result(om_vanilla, owner,
				"slot_ranged", vanilla_unit)
		end)
        H.equal(declined.retained, false)
        H.equal(declined.fallback, true)
        H.equal(declined.reason, "custom-unit-not-retained",
            "an actual vanilla fallback path must never be painted as Old Musket")
    end)

	H.test("#1155 installed husk wield callback spawns rifle and polearm parents before stable apply", function()
		for _, case in ipairs({
			{ mode = "ranged", template = "old_musket_template",
				profile = "held_3p_rifle_character", event = "to_handgun" },
			{ mode = "melee", template = "old_musket_template_melee",
				profile = "held_3p_polearm_character", event = "to_polearm" },
		}) do
			local om, _, _, env = fixture()
			local profiles, positions = install_old_musket_guard(om)
			env.Application = { can_get = function() return true end }
			local owner = {}
			om._old_musket_mode_for_owner = function() return case.mode end
			om._husk_identity_descriptor = exact_descriptor(
				OLD_MUSKET_DEF.item_key, CUSTOM_MESH)
			local body_events = {}
			om.old_musket_preview_pose = old_musket_pose
			om.outrider_animation = {
				husk_event = function() return nil end,
				dispatch_event = function(unit, event, unit_api)
					body_events[#body_events + 1] = {
						unit = unit, event = event, unit_api = unit_api,
					}
					return true, "dispatched_unverified"
				end,
				emit_evidence = function() end,
			}
			om.appearance_fade = { husk_wield = function() end }
			local installed
			om._install_husk_wield_hook({
				hook = function(_, class_name, method_name, callback)
					H.equal(class_name, "SimpleHuskInventoryExtension")
					H.equal(method_name, "_wield_slot")
					installed = callback
				end,
			})
			H.truthy(installed)
			local item_units = {
				right_hand_unit = "units/weapons/player/wpn_fix_gun/wpn_fix_gun",
			}
			local slot = {
				item_data = { name = "fix_gun" },
				skin = OLD_MUSKET_DEF.item_key .. "_skin",
				item_template = {},
			}
			local equipment = { slots = { slot_ranged = slot } }
			local spawned, selected_template
			with_env(env, function()
				local result = installed(function()
					H.truthy(om._appearance_husk_wield_context,
						"the exact owner+slot context must cover vanilla spawn")
					local suppress, template, evidence = om._husk_adapter_pre(
						"right", slot.item_template, item_units, "slot_ranged",
						slot.item_data, owner)
					H.equal(suppress, false)
					selected_template = template
					spawned = {}
					equipment.right_hand_wielded_unit_3p = spawned
					om._husk_adapter_post("right", slot.item_data, item_units,
						"slot_ranged", owner, spawned, nil, evidence)
					return "vanilla-result"
				end, { _unit = owner, _player = { peer_id = "peer-rain" } },
					{}, equipment, "slot_ranged", nil, owner)
				H.equal(result, "vanilla-result")
			end)
			H.equal(om._appearance_husk_wield_context, nil)
			H.equal(selected_template, env.Weapons[case.template])
			H.deep_equal(spawned.position, positions[profiles[case.profile]])
			local path, mode, profile, template_name =
				om._husk_observed_unit_evidence(
					spawned, owner, "slot_ranged", "right")
			H.equal(path, CUSTOM_MESH_3P)
			H.equal(mode, case.mode)
			H.equal(profile, profiles[case.profile])
			H.equal(template_name, case.template)
			H.equal(#body_events, 1,
				"the exact clone body event must replay once after vanilla's base event")
			H.equal(body_events[1].unit, owner)
			H.equal(body_events[1].event, case.event)
			H.equal(body_events[1].unit_api, env.Unit)
		end
	end)

	H.test("#1155 installed husk body replay rejects a replaced template reference", function()
		local om, _, _, env = fixture()
		install_old_musket_guard(om)
		env.Application = { can_get = function() return true end }
		local owner, body_events, stable_calls = {}, 0, 0
		om._old_musket_mode_for_owner = function() return "ranged" end
		om._husk_identity_descriptor = exact_descriptor(
			OLD_MUSKET_DEF.item_key, CUSTOM_MESH)
		om.old_musket_preview_pose = old_musket_pose
		local real_reconcile = om.old_musket_appearance.reconcile
		om.old_musket_appearance.reconcile = function(...)
			stable_calls = stable_calls + 1
			return real_reconcile(...)
		end
		om.outrider_animation = {
			husk_event = function() return nil end,
			dispatch_event = function() body_events = body_events + 1 end,
			emit_evidence = function() end,
		}
		om.appearance_fade = { husk_wield = function() end }
		local installed
		om._install_husk_wield_hook({
			hook = function(_, _, _, callback) installed = callback end,
		})
		local item_units = {
			right_hand_unit = "units/weapons/player/wpn_fix_gun/wpn_fix_gun",
		}
		local slot = {
			item_data = { name = "fix_gun" },
			skin = OLD_MUSKET_DEF.item_key .. "_skin", item_template = {},
		}
		local equipment = { slots = { slot_ranged = slot } }
		with_env(env, function()
			installed(function()
				local _, _, evidence = om._husk_adapter_pre(
					"right", slot.item_template, item_units, "slot_ranged",
					slot.item_data, owner)
				local spawned = {}
				equipment.right_hand_wielded_unit_3p = spawned
				om._husk_adapter_post("right", slot.item_data, item_units,
					"slot_ranged", owner, spawned, nil, evidence)
				env.Weapons.old_musket_template = {
					wield_anim = "foreign",
					right_hand_attachment_node_linking = {
						third_person = { wielded = {} },
					},
				}
			end, { _unit = owner, _player = { peer_id = "peer-rain" } },
				{}, equipment, "slot_ranged", nil, owner)
		end)
		H.equal(body_events, 0,
			"a replaced clone table must not borrow the prior template's body event")
		H.equal(stable_calls, 0,
			"a replaced clone table must not borrow the prior attachment profile")
	end)

	H.test("#1155 installed husk wrapper restores exact contexts across auxiliary failures", function()
		for _, case in ipairs({
			{ name = "success" },
			{ name = "begin", begin_error = true },
			{ name = "end", end_error = true },
			{ name = "native", native_error = true },
			{ name = "post", post_error = true },
		}) do
			local om, _, _, env = fixture()
			local owner = { id = "owner-" .. case.name }
			local prior_appearance = { id = "appearance-prior-" .. case.name }
			local prior_style = { id = "style-prior-" .. case.name }
			local transient_style = { id = "style-live-" .. case.name }
			local begin_calls, end_calls, native_calls, post_calls, downstream_calls =
				0, 0, 0, 0, 0
			om._appearance_husk_wield_context = prior_appearance
			om.combat_styles = {
				husk_context = prior_style,
				begin_husk_wield = function(self)
					begin_calls = begin_calls + 1
					self.husk_context = transient_style
					if case.begin_error then error("begin-boom") end
				end,
				end_husk_wield = function(self)
					end_calls = end_calls + 1
					if case.end_error then error("end-boom") end
				end,
			}
			om._husk_identity_descriptor = function() return nil end
			om._old_musket_husk_wield = function()
				post_calls = post_calls + 1
				H.equal(rawget(om, "_appearance_husk_wield_context"), prior_appearance,
					"post observers must run only after exact context restoration")
				H.equal(rawget(om.combat_styles, "husk_context"), prior_style)
				if case.post_error then error("post-boom") end
			end
			om.outrider_animation = {
				husk_event = function() return nil end,
				dispatch_event = function() end,
				emit_evidence = function() end,
			}
			om.appearance_fade = { husk_wield = function() end }
			om._exact_pair_on_husk_wield = function()
				downstream_calls = downstream_calls + 1
			end
			local installed
			om._install_husk_wield_hook({
				hook = function(_, _, _, callback) installed = callback end,
			})
			local equipment = { slots = { slot_ranged = {
				item_data = { name = "fix_gun" },
			} } }
			local native_result
			local ok, result = pcall(function()
				with_env(env, function()
					native_result = installed(function()
						native_calls = native_calls + 1
						local live_appearance = rawget(
							om, "_appearance_husk_wield_context")
						H.equal(live_appearance.owner_unit_3p, owner)
						H.equal(live_appearance.slot_name, "slot_ranged")
						H.equal(rawget(om.combat_styles, "husk_context"),
							case.begin_error and prior_style or transient_style)
						if case.native_error then error("native-boom") end
						return "native-result"
					end, { _unit = owner, _player = {} }, {}, equipment,
						"slot_ranged", nil, owner)
				end)
				return native_result
			end)
			if case.native_error then
				H.equal(ok, false)
				H.truthy(tostring(result):find("native-boom", 1, true))
			else
				H.equal(ok, true)
				H.equal(result, "native-result")
			end
			H.equal(native_calls, 1, case.name .. " must run vanilla exactly once")
			H.equal(begin_calls, 1)
			H.equal(end_calls, (case.begin_error and 0 or 1))
			H.equal(post_calls, (case.native_error and 0 or 1))
			H.equal(downstream_calls, (case.native_error and 0 or 1),
				case.name .. " must preserve later post-wield observers")
			H.equal(rawget(om, "_appearance_husk_wield_context"), prior_appearance)
			H.equal(rawget(om.combat_styles, "husk_context"), prior_style)
		end
	end)

	H.test("#1155 nested husk wield restores the outer owner and slot before continuing", function()
		local om, _, _, env = fixture()
		local prior = { id = "preexisting-context" }
		local outer_owner, inner_owner = { id = "outer" }, { id = "inner" }
		om._appearance_husk_wield_context = prior
		om._husk_identity_descriptor = function() return nil end
		om.outrider_animation = {
			husk_event = function() return nil end,
			dispatch_event = function() end,
			emit_evidence = function() end,
		}
		om.appearance_fade = { husk_wield = function() end }
		local installed
		om._install_husk_wield_hook({
			hook = function(_, _, _, callback) installed = callback end,
		})
		local equipment = { slots = {
			slot_ranged = { item_data = { name = "outer" } },
			slot_melee = { item_data = { name = "inner" } },
		} }
		with_env(env, function()
			local result = installed(function()
				local outer = rawget(om, "_appearance_husk_wield_context")
				H.equal(outer.owner_unit_3p, outer_owner)
				H.equal(outer.slot_name, "slot_ranged")
				local inner_result = installed(function()
					local inner = rawget(om, "_appearance_husk_wield_context")
					H.equal(inner.owner_unit_3p, inner_owner)
					H.equal(inner.slot_name, "slot_melee")
					return "inner-result"
				end, { _unit = inner_owner, _player = {} }, {}, equipment,
					"slot_melee", nil, inner_owner)
				H.equal(inner_result, "inner-result")
				H.equal(rawget(om, "_appearance_husk_wield_context"), outer,
					"inner unwind must restore the exact outer context table")
				return "outer-result"
			end, { _unit = outer_owner, _player = {} }, {}, equipment,
				"slot_ranged", nil, outer_owner)
			H.equal(result, "outer-result")
		end)
		H.equal(rawget(om, "_appearance_husk_wield_context"), prior)
	end)

	H.test("#1155 installed husk callback uses the extension player before owner mapping exists", function()
		local om, _, _, env = fixture()
		local profiles, positions = install_old_musket_guard(om)
		env.Application = { can_get = function() return true end }
		local owner = {}
		om.peer_resolver = {
			player_peer_id = function(player) return player and player.peer_id end,
			peer_player = function() return nil end,
			owner = function() return nil end,
		}
		om._husk_identity_descriptor = exact_descriptor(
			OLD_MUSKET_DEF.item_key, CUSTOM_MESH)
		om.outrider_animation = {
			husk_event = function() return nil end,
			dispatch_event = function() end,
			emit_evidence = function() end,
		}
		om.appearance_fade = { husk_wield = function() end }
		local mod = {
			network_register = function() end,
			_cwv_rewield = { request_peer_rewield = function() end },
		}
		install_musket_wire(mod, { om = om })
		H.equal(om._old_musket_accept_mode(
			"peer-rain", "slot_ranged", "melee", nil, "identity"), true)
		local installed
		om._install_husk_wield_hook({
			hook = function(_, _, _, callback) installed = callback end,
		})
		local item_units = {
			right_hand_unit = "units/weapons/player/wpn_fix_gun/wpn_fix_gun",
		}
		local slot = {
			item_data = { name = "fix_gun" },
			skin = OLD_MUSKET_DEF.item_key .. "_skin", item_template = {},
		}
		local equipment = { slots = { slot_ranged = slot } }
		local spawned, selected
		with_env(env, function()
			installed(function()
				local suppress, template, evidence = om._husk_adapter_pre(
					"right", slot.item_template, item_units, "slot_ranged",
					slot.item_data, owner)
				H.equal(suppress, false)
				selected = template
				spawned = {}
				equipment.right_hand_wielded_unit_3p = spawned
				om._husk_adapter_post("right", slot.item_data, item_units,
					"slot_ranged", owner, spawned, nil, evidence)
			end, { _unit = owner, _player = { peer_id = "peer-rain" } },
				{}, equipment, "slot_ranged", nil, owner)
		end)
		H.equal(selected, env.Weapons.old_musket_template_melee,
			"the hinted extension player must select the peer's melee parent")
		H.deep_equal(spawned.position,
			positions[profiles.held_3p_polearm_character])
		local _, mode, profile = om._husk_observed_unit_evidence(
			spawned, owner, "slot_ranged", "right")
		H.equal(mode, "melee")
		H.equal(profile, profiles.held_3p_polearm_character)
	end)

	H.test("#1155 peer-ready wire consumes the exact observed husk parent before applying", function()
		local om, _, _, env = fixture()
		local profiles, positions = install_old_musket_guard(om)
		local owner, rendered_unit = {}, {}
		record_old_musket_spawn(om, env, owner, "slot_ranged",
			rendered_unit, "ranged")

		local observed_name, observed_mode, observed_profile, template_name,
			template_ref = om._husk_observed_unit_evidence(
				rendered_unit, owner, "slot_ranged", "right")
		H.equal(observed_name, CUSTOM_MESH_3P)
		H.equal(observed_mode, "ranged")
		H.equal(observed_profile, profiles.held_3p_rifle_character)
		H.equal(template_name, "old_musket_template")
		H.equal(template_ref, env.Weapons.old_musket_template,
			"peer-ready admission must be grounded in the exact registered template reference")

		local equipment = {
			wielded_slot = "slot_ranged",
			right_hand_wielded_unit_3p = rendered_unit,
		}
		local inventory = { equipment = function() return equipment end }
		env.ScriptUnit = {
			extension = function(_, extension_name)
				if extension_name == "inventory_system" then return inventory end
				return nil
			end,
		}
		om.peer_resolver = {
			peer_player = function(_, peer_id)
				if peer_id == "peer-rain" then return { player_unit = owner } end
			end,
		}
		om._old_musket_transform_components = function(_, mode)
			local profile = mode == "melee"
				and profiles.held_3p_polearm_character
				or profiles.held_3p_rifle_character
			return positions[profile], { 0, 0, 0, 1 }, { 0.9, 0.9, 0.9 }
		end

		local real_reconcile = om.old_musket_appearance.reconcile
		local reconciles, rewields = {}, {}
		om.old_musket_appearance.reconcile = function(unit, surface, edge, item,
				mode, context)
			reconciles[#reconciles + 1] = { unit = unit, surface = surface,
				edge = edge, mode = mode, context = context }
			return real_reconcile(unit, surface, edge, item, mode, context)
		end
		local mod = {
			network_register = function() end,
			_cwv_rewield = {
				request_peer_rewield = function(peer_id, slot_name, deps)
					rewields[#rewields + 1] = { peer_id = peer_id,
						slot_name = slot_name, tag = deps and deps.tag }
					return true, "queued"
				end,
			},
		}

		with_env(env, function()
			install_musket_wire(mod, { om = om })
			H.equal(om._old_musket_accept_mode(
				"peer-rain", "slot_ranged", "ranged", nil, "identity"), true)
			H.equal(#reconciles, 1)
			H.equal(reconciles[1].unit, rendered_unit)
			H.equal(reconciles[1].surface, "husk")
			H.equal(reconciles[1].edge, "peer_ready")
			H.equal(reconciles[1].mode, "ranged")
			H.equal(reconciles[1].context.unit_name, CUSTOM_MESH_3P)
			H.equal(reconciles[1].context.attachment_profile,
				profiles.held_3p_rifle_character)
			H.deep_equal(rendered_unit.position,
				positions[profiles.held_3p_rifle_character])
			H.equal(#rewields, 0)

			H.equal(om._old_musket_accept_mode(
				"peer-rain", "slot_ranged", "melee", nil, "identity"), true)
			H.equal(#rewields, 1,
				"a parent-changing stance must request one bounded peer re-wield")
			H.equal(rewields[1].peer_id, "peer-rain")
			H.equal(rewields[1].slot_name, "slot_ranged")
			H.equal(rewields[1].tag, "old-musket-parent:melee")
			H.equal(#reconciles, 1,
				"the melee profile must not be painted onto the ledger's stale rifle parent")
			H.deep_equal(rendered_unit.position,
				positions[profiles.held_3p_rifle_character])
		end)
	end)

    H.test("#1155 husk spawn ledger rejects missing, substituted, and stale targets", function()
        local owner = {}

        local missing = fixture()
        install_old_musket_guard(missing)
        local missing_result = old_musket_husk_result(missing, owner,
            "slot_ranged", {})
		H.equal(missing_result, nil,
            "a never-observed equipment target must fail closed")

		local substituted, _, _, substituted_env = fixture()
        install_old_musket_guard(substituted)
        local observed_unit, replacement_unit = {}, {}
		record_old_musket_spawn(substituted, substituted_env, owner,
			"slot_ranged", observed_unit, "ranged")
        local substituted_result = old_musket_husk_result(substituted, owner,
            "slot_ranged", replacement_unit)
		H.equal(substituted_result, nil,
            "a current target substituted after spawn must not borrow another unit's observation")

		local stale, _, _, stale_env = fixture()
        install_old_musket_guard(stale)
        local reused_unit = {}
		record_old_musket_spawn(stale, stale_env, owner,
			"slot_melee", reused_unit, "melee")
        local stale_result = old_musket_husk_result(stale, owner,
            "slot_ranged", reused_unit)
		H.equal(stale_result, nil,
            "a unit observation from a previous slot generation must be treated as stale")
    end)

    H.test("#1155 husk spawn ledger binds owner, slot, and hand independently", function()
        local owner, other_owner = {}, {}

		local wrong_owner, _, _, wrong_owner_env = fixture()
        install_old_musket_guard(wrong_owner)
        local owner_unit = {}
		record_old_musket_spawn(wrong_owner, wrong_owner_env, owner,
			"slot_ranged", owner_unit, "ranged")
		H.equal(old_musket_husk_result(wrong_owner, other_owner,
			"slot_ranged", owner_unit), nil,
            "another husk owner must not consume this observation")

		local wrong_hand = fixture()
        install_old_musket_guard(wrong_hand)
        local left_unit = {}
        wrong_hand._husk_adapter_post("left", { name = "fix_gun" },
            { left_hand_unit = CUSTOM_MESH }, "slot_ranged", owner,
            left_unit, nil)
        H.equal(wrong_hand._husk_observed_unit_name(left_unit, owner,
            "slot_ranged", "right"), nil,
            "a left-hand ledger row must not masquerade as the right hand")
		H.equal(old_musket_husk_result(wrong_hand, owner,
			"slot_ranged", left_unit), nil)
    end)

    H.test("call-site wiring: all-four-returns capture + adapter seams + fail-closed anchors", function()
        -- #1159: the GearUtils.spawn_inventory_unit hook that carries both adapter
        -- seams moved verbatim out of the entry into the musket equip-surface
        -- owner, because the bayonet attach and the melee-stance transform are
        -- applied inline in the same hook body. The seams themselves are
        -- unchanged, so these anchors just follow the code. The entry must hold no
        -- second copy: VMF drops a duplicate (Class, method) registration, which
        -- would silently shadow the whole husk adapter.
        local main = read(mod_root .. "_cwv_musket_equip_surface.lua")
        H.equal(select(2, read(main_path):gsub(
            'mod:hook%("GearUtils", "spawn_inventory_unit"', "")), 0,
            "entry must not re-register the spawn chokepoint")
        for _, marker in ipairs({
            -- gear_utils.lua:13 multi-return: weapon_3p, ammo_3p, weapon_1p, ammo_1p.
            "local v_w3p, v_a3p, v_w1p, v_a1p =",
            "func(world, hand, husk_spawn_template or item_template, item_units, slot_name, item_data, owner_unit_1p, owner_unit_3p, unit_template, extra_extension_data, ammo_percent, material_settings_name)",
			"_om._husk_adapter_pre(",
			"_om._husk_adapter_post(",
            "return nil, nil, nil, nil",
            "return v_w3p, v_a3p, v_w1p, v_a1p",
        }) do
            H.truthy(main:find(marker, 1, true), "missing entry adapter anchor: " .. marker)
        end
        local module_source = read(module_path)
        for _, marker in ipairs({
            "_om._husk_adapter_pre = function(hand, item_template, item_units, slot_name, item_data, owner_unit_3p)",
			"_om._husk_adapter_post = function(hand, item_data, item_units, slot_name, owner_unit_3p, v_w3p, v_a3p, spawn_evidence)",
            "_om._husk_strip_cwv_ammo(item_data, owner_unit_3p, v_a3p, slot_name, item_units)",
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
