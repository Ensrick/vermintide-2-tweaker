-- Engine-free coverage for husk admission of CWV's own bundled model meshes (#719).
--
-- A remote peer only ever re-keys a weapon onto a non-vanilla mesh through the
-- custom-bundle arm: `_om._resident_override_3p` rejects anything outside
-- `units/weapons/player/` (#418, and force-loading a mod path is the #403 boot
-- fatal) and `_husk_lease_override` rejects the same prefix. Before #719 that
-- arm answered only for the Old Musket, so every Greataxe and Crowbill model was
-- inadmissible on every peer and the observer kept the shadowed vanilla donor --
-- Kruber's Imperial Crowbill rendering as Sienna's Crowbill for the whole
-- mission.
--
-- Two halves, both driven on shipped code:
--   1. each family answers for its OWN authored catalog, and every model it
--      claims is actually shipped in the master package manifest;
--   2. the husk residency floor and mesh re-key admit a claimed mesh, and still
--      fail closed for a borrowed-material mesh whose donor is absent.
return function(H, repo_root)
    local mod_root = repo_root
        .. "/character_weapon_variants/scripts/mods/character_weapon_variants/"
    local husk_path = mod_root .. "_cwv_husk_path.lua"
    local Crowbill = assert(loadfile(mod_root .. "_cwv_crowbill_family.lua"))()
    local Greataxe = assert(loadfile(mod_root .. "_cwv_greataxe.lua"))()

    local function read(path)
        local file = assert(io.open(path, "rb"))
        local source = file:read("*a")
        file:close()
        return source
    end

    -- The shipped bundle manifest is the resource ground truth for "this unit is
    -- resident whenever the mod is loaded" -- the property the admission arm
    -- asserts. It is a data file, not the Lua under test.
    local manifest = read(repo_root
        .. "/character_weapon_variants/resource_packages/character_weapon_variants/character_weapon_variants.package")

    local FAMILIES = {
        { name = "Crowbill", policy = Crowbill },
        { name = "Greataxe", policy = Greataxe },
    }

    H.test("#719 every authored model mesh is claimed by its family and shipped", function()
        for _, family in ipairs(FAMILIES) do
            local models = family.policy.usable_models()
            H.truthy(#models > 0, family.name .. " has no usable models to admit")
            for _, model in ipairs(models) do
                local unit = model.right_hand_unit
                H.equal(family.policy.is_bundled_unit(unit), true,
                    family.name .. " does not claim its own authored mesh " .. tostring(unit))
                -- Both forms must be in the manifest: the husk appends "_3p".
                H.truthy(manifest:find('"' .. unit .. '"', 1, true),
                    "master package does not ship " .. unit)
                H.truthy(manifest:find('"' .. unit .. '_3p"', 1, true),
                    "master package does not ship " .. unit .. "_3p")
            end
        end
    end)

    H.test("#719 family admission stays scoped to its own bundled namespace", function()
        -- The vanilla donor these variants shadow must NEVER be admitted here:
        -- it is owned by the residency/lease arms, and letting the custom-bundle
        -- arm claim it would void the #418 force-load reference contract.
        H.equal(Crowbill.is_bundled_unit(Crowbill.PLACEHOLDER_UNIT), false)
        H.equal(Greataxe.is_bundled_unit(
            "units/weapons/player/wpn_dwarf_2h_axe_01_t1/wpn_dwarf_2h_axe_01_t1"), false)
        local sample = Crowbill.usable_models()[1].right_hand_unit
        H.equal(Greataxe.is_bundled_unit(sample), false,
            "a family must not claim another family's mesh")
        -- The BASE form is the contract; callers never pass the _3p form, and
        -- claiming it would let a "_3p_3p" spawn target through.
        H.equal(Crowbill.is_bundled_unit(sample .. "_3p"), false)
        H.equal(Crowbill.is_bundled_unit(nil), false)
        H.equal(Crowbill.is_bundled_unit(""), false)
        H.equal(Greataxe.is_bundled_unit(42), false)
    end)

    -- Husk-side drive: install the real module with a bundled-unit predicate
    -- composed exactly as production composes it (each family answering for its
    -- own catalog) and a borrowed-material mesh alongside, to prove the two
    -- kinds of custom mesh take different admission paths.
    local BORROWED = "units/cwv_es_musket_custom/cwv_es_musket_custom"
    local DONOR_3P = "units/weapons/player/wpn_empire_handgun_t1/wpn_empire_handgun_t1_3p"
    local BUNDLED = Crowbill.usable_models()[1].right_hand_unit
    local BASE_UNIT = Crowbill.PLACEHOLDER_UNIT

    local DEFS = {
        { item_key = "cwv_fix_crowbill", base_weapon = "fix_crowbill_base",
          careers = { "es_fix" }, right_hand_unit = BUNDLED, item_type = "cwv_fix_crowbill" },
        { item_key = "cwv_fix_musket", base_weapon = "fix_gun",
          careers = { "es_fix" }, right_hand_unit = BORROWED, item_type = "cwv_fix_musket" },
    }
    local function find_def(key)
        for _, def in ipairs(DEFS) do
            if def.item_key == key then return def end
        end
        return nil
    end

    local function fixture()
        local om = { HUSK_OVERRIDE_REF = "cwv_husk_override_units" }
        local lines, leases = {}, {}
        local env = {
            printf = function(fmt, ...) lines[#lines + 1] = string.format(fmt, ...) end,
            ScriptUnit = { has_extension = function() return false end,
                extension = function() return nil end },
            Unit = { alive = function() return true end },
            ItemMasterList = {
                fix_crowbill_base = { can_wield = { "bw_other" } },
                fix_gun = { can_wield = { "dr_other" } },
            },
            WeaponSkins = { skins = {} },
            Weapons = {},
            Managers = {
                package = {
                    load = function(_, path, ref) leases[#leases + 1] = { path = path, ref = ref } end,
                    has_loaded = function() return false end,
                },
            },
        }
        assert(loadfile(husk_path))()(nil, {
            om = om,
            variant_definitions = DEFS,
            find_def = find_def,
            is_unit = function(u) return u ~= nil end,
            apply_cwv_hand_transform = function() return true end,
            triplet_text = function() return "t" end,
        })
        -- Production composition: the Old Musket bridge pair, then each family's
        -- own catalog answer.
        om._husk_custom_bundle_unit = function(unit)
            if unit == BORROWED then return true end
            for _, family in ipairs(FAMILIES) do
                if family.policy.is_bundled_unit(unit) then return true end
            end
            return false
        end
        om._husk_material_donor_ready = om._husk_material_donor_ready
        return om, lines, leases, env
    end

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

    H.test("#719 a self-contained bundled mesh clears the husk spawn floor", function()
        -- Residency for these paths is structural: they ship in CWV's master
        -- package, which loads with the mod, so this code cannot run while they
        -- are absent. Asking the global resource system about a Workshop bundle
        -- path is the lookup that does not answer reliably -- so the floor must
        -- NOT hinge on it, or hand preselection defers forever and the peer keeps
        -- the vanilla donor mesh (the #719 symptom).
        for _, answer in ipairs({ "silent", "denied" }) do
            local om, _, _, env = fixture()
            env.Application = { can_get = function()
                if answer == "silent" then return nil end
                return false
            end }
            with_env(env, function()
                H.equal(om._husk_material_donor_ready(BUNDLED), true,
                    "a self-contained mesh declares no donor material to gate on")
                H.equal(om._husk_unit_spawnable(BUNDLED), true,
                    "the spawn floor must admit a bundled mesh when can_get answers " .. answer)
            end)
        end
    end)

    H.test("#719 the husk re-key writes the authored bundled mesh", function()
        local om, lines, leases, env = fixture()
        env.Application = { can_get = function() return true end }
        om._husk_identity_descriptor = function()
            return { variant_key = "cwv_fix_crowbill", right_hand_unit = BUNDLED,
                fingerprint = "fp:crowbill" }, "exact"
        end
        local item_units = { right_hand_unit = BASE_UNIT }
        with_env(env, function()
            H.equal(om._husk_rekey_units("right", { name = "fix_crowbill_base" },
                item_units, {}, "slot_melee"), nil)
        end)
        H.equal(item_units.right_hand_unit, BUNDLED,
            "the remote peer must leave the vanilla donor and take the authored model")
        H.equal(#leases, 0,
            "a bundled mesh needs no package lease -- leasing a mod path is the #403 boot fatal")
        H.truthy(table.concat(lines, "\n"):find("husk re-keyed hand=right", 1, true))
    end)

    H.test("#719 hand preselection admits the bundled mesh as one transaction", function()
        local om, _, _, env = fixture()
        env.Application = { can_get = function() return true end }
        om._appearance_husk_wield_context = { owner_unit_3p = {}, slot_name = "slot_melee" }
        om._husk_identity_descriptor = function()
            return { variant_key = "cwv_fix_crowbill", right_hand_unit = BUNDLED,
                fingerprint = "fp:crowbill" }, "exact"
        end
        local result = { right_hand_unit = BASE_UNIT, left_hand_unit = "vanilla_left" }
        with_env(env, function()
            H.equal(om._husk_preselect_units(result, { name = "fix_crowbill_base" },
                nil, nil, "es_fix"), true)
        end)
        H.equal(result.right_hand_unit, BUNDLED)
        H.equal(result.left_hand_unit, nil,
            "a one-handed exact descriptor atomically removes the inherited offhand")
    end)

    H.test("#719 a borrowed-material mesh still gates on its donor", function()
        -- The two custom-mesh kinds must not collapse into one rule: the Old
        -- Musket borrows a vanilla material, and spawning it while that package
        -- is absent is the #474 MeshObject access violation.
        local om, lines, leases, env = fixture()
        env.Application = { can_get = function(kind) return kind ~= "material" end }
        with_env(env, function()
            H.equal(om._husk_unit_spawnable(BORROWED), false)
            H.equal(om._husk_unit_spawnable(BUNDLED), true,
                "the donor gate must not spill onto a mesh that declares no donor")
        end)
        H.equal(leases[1] and leases[1].path, DONOR_3P,
            "the borrowed-material mesh must still queue its bounded donor lease")
        H.truthy(table.concat(lines, "\n"):find("[cwv:474] husk donor-material lease", 1, true))
    end)
end
