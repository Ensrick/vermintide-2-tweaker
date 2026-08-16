-- Engine-free coverage for the husk ammo native-pair discriminator (#1188).
--
-- CWV's husk ammo arms strip a variant's inherited ammo mesh from a base+career
-- signal: a career that CANNOT natively wield the ammo base can only be holding
-- the CWV variant. weapon_tweaker's `unlock_es_*_dr_deus_01` toggles insert
-- those exact careers into the live `dr_deus_01.can_wield`, which destroys the
-- disjointness the signal rests on -- a wt-granted REAL Trollhammer then lost
-- its torpedo on every remote view (#475 Invariant 1 violated).
--
-- The whole point of the fix is that the guard may not fire indiscriminately:
-- a naive native-pair check re-breaks the Outrider for the same player. These
-- tests drive the shipped module's real arms through `_husk_adapter_pre` /
-- `_husk_adapter_post` against a mutable can_wield, so both halves are proven.
return function(H, repo_root)
    local module_path = repo_root
        .. "/character_weapon_variants/scripts/mods/character_weapon_variants/_cwv_husk_path.lua"

    local LAUNCHER_UNIT = "units/weapons/player/wpn_fix_launcher/wpn_fix_launcher"
    local AMMO_BASE = "fix_gun_ammo"
    local STRIP_CAREER = "es_fix"
    local NATIVE_CAREER = "dr_other"

    local DEFS = {
        {
            item_key = "cwv_fix_launcher",
            base_weapon = AMMO_BASE,
            careers = { STRIP_CAREER },
            right_hand_unit = LAUNCHER_UNIT,
            no_ammo_unit = true,
            item_type = "cwv_fix_launcher",
        },
    }

    local function find_def(key)
        for _, def in ipairs(DEFS) do
            if def.item_key == key then return def end
        end
        return nil
    end

    -- Fresh module install per test: `om` collects the exports, `can_wield` is
    -- the live table the lazy native check reads (wt rewrites it at runtime).
    local function fixture()
        local om = { HUSK_OVERRIDE_REF = "cwv_husk_override_units" }
        local lines = {}
        local can_wield = { NATIVE_CAREER }
        local env = {
            printf = function(fmt, ...) lines[#lines + 1] = string.format(fmt, ...) end,
            ScriptUnit = {
                has_extension = function() return false end,
                extension = function() return nil end,
            },
            Unit = { alive = function() return true end },
            Application = { can_get = function() return true end },
            ItemMasterList = {
                [AMMO_BASE] = {
                    can_wield = can_wield,
                    ammo_unit = "fix_torpedo",
                    ammo_unit_3p = "fix_torpedo_3p",
                },
            },
            WeaponSkins = { skins = {} },
            Weapons = {},
            Managers = {
                package = {
                    load = function() end,
                    has_loaded = function() return true end,
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
        -- Neighbouring husk concerns are stubbed for the drive; the ammo arms
        -- under test are the REAL ones, reached through the real adapter halves.
        om._husk_rekey_units = function() return false end
        om._husk_template_for_spawn = function() return nil end
        om._husk_apply_cwv_transform = function() return nil end
        om._probe_579_hand_compare = function() return nil end
        om._husk_identity_descriptor = function() return nil, "none" end
        om._husk_career_name = function() return STRIP_CAREER end
        return om, lines, can_wield, env
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

    local function units(skin)
        return {
            right_hand_unit = LAUNCHER_UNIT,
            ammo_unit = "fix_torpedo",
            ammo_unit_3p = "fix_torpedo_3p",
            skin = skin,
        }
    end
    local function cleared(u)
        return u.ammo_unit == nil and u.ammo_unit_3p == nil
    end

    H.test("#1188 a disjoint pair still strips on career membership alone", function()
        local om, _, _, env = fixture()
        with_env(env, function()
            local admits, reason = om._husk_ammo_pair_admits(AMMO_BASE, STRIP_CAREER, nil)
            H.equal(admits, true)
            H.equal(reason, "base_career")
            local u = units(nil)
            om._husk_adapter_pre("right", nil, u, "slot_ranged", { name = AMMO_BASE }, {})
            H.equal(cleared(u), true,
                "the #399 Outrider fix must survive: a career that cannot natively wield the ammo base is still positive CWV identity")
            H.equal(om._husk_strip_cwv_ammo({ name = AMMO_BASE }, {}, { ammo = true },
                "slot_ranged", units(nil)), true,
                "the post-spawn arm must agree with the pre-spawn arm")
        end)
    end)

    H.test("#1188 a wt-granted native pair keeps its ammo on both arms", function()
        local om, lines, can_wield, env = fixture()
        can_wield[#can_wield + 1] = STRIP_CAREER   -- the wt unlock, at runtime
        with_env(env, function()
            local admits, reason = om._husk_ammo_pair_admits(AMMO_BASE, STRIP_CAREER, nil)
            H.equal(admits, false)
            H.equal(reason, "native_pair")
            local u = units(nil)
            om._husk_adapter_pre("right", nil, u, "slot_ranged", { name = AMMO_BASE }, {})
            H.equal(cleared(u), false,
                "a real weapon the career can currently wield must keep its ammo (#475 Invariant 1)")
            H.equal(om._husk_strip_cwv_ammo({ name = AMMO_BASE }, {}, { ammo = true },
                "slot_ranged", units(nil)), false)
        end)
        H.truthy(table.concat(lines, "\n"):find("[cwv:1188]", 1, true),
            "the decline needs a bounded receipt naming the native pair")
    end)

    H.test("#1188 the Outrider survives the same unlock on positive CWV identity", function()
        -- A naive native-pair guard re-breaks the variant for the very player who
        -- enabled the toggle. Both stronger identity signals must still strip.
        local om, _, can_wield, env = fixture()
        can_wield[#can_wield + 1] = STRIP_CAREER
        with_env(env, function()
            -- (a) the wire skin names the variant regardless of can_wield (#474).
            local admits, reason = om._husk_ammo_pair_admits(AMMO_BASE, STRIP_CAREER,
                "cwv_fix_launcher_skin")
            H.equal(admits, true)
            H.equal(reason, "skin")
            local skinned = units("cwv_fix_launcher_skin")
            om._husk_adapter_pre("right", nil, skinned, "slot_ranged", { name = AMMO_BASE }, {})
            H.equal(cleared(skinned), true,
                "a cwv-skinned variant must keep its ammo fix under a wt unlock")

            -- (b) a proven exact descriptor decides ahead of the fallback.
            om._husk_identity_descriptor = function()
                return { variant_key = "cwv_fix_launcher", base_item_key = AMMO_BASE }, "exact"
            end
            local crafted = units(nil)
            om._husk_adapter_pre("right", nil, crafted, "slot_ranged", { name = AMMO_BASE }, {})
            H.equal(cleared(crafted), true,
                "a proven CWV instance must keep its ammo fix under a wt unlock")
        end)
    end)

    H.test("#1188 an explicitly native descriptor still hard-declines", function()
        local om, _, _, env = fixture()
        with_env(env, function()
            om._husk_identity_descriptor = function() return nil, "native" end
            local u = units(nil)
            om._husk_adapter_pre("right", nil, u, "slot_ranged", { name = AMMO_BASE }, {})
            H.equal(cleared(u), false,
                "the sender proved this slot native -- the discriminator must not overrule it")
        end)
    end)

    H.test("#1188 the discriminator reports every decline shape distinctly", function()
        local om, _, _, env = fixture()
        with_env(env, function()
            local _, unknown = om._husk_ammo_pair_admits("not_a_cwv_base", STRIP_CAREER, nil)
            H.equal(unknown, "no_base")
            local _, miss = om._husk_ammo_pair_admits(AMMO_BASE, "wh_unrelated", nil)
            H.equal(miss, "career_miss")
            local _, nil_career = om._husk_ammo_pair_admits(AMMO_BASE, nil, nil)
            H.equal(nil_career, "career_miss",
                "a husk career-lookup miss must stay distinguishable from a native pair")
        end)
    end)

    H.test("#1188 an unreadable can_wield fails closed to native", function()
        local om, _, _, env = fixture()
        env.ItemMasterList[AMMO_BASE].can_wield = nil
        with_env(env, function()
            local admits, reason = om._husk_ammo_pair_admits(AMMO_BASE, STRIP_CAREER, nil)
            H.equal(admits, false)
            H.equal(reason, "native_pair",
                "an unreadable can_wield must be treated as native, never as an invitation to strip")
        end)
    end)
end
