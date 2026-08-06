return function(H, repo_root)
    local root = repo_root
        .. "/character_weapon_variants/scripts/mods/character_weapon_variants/"

    local function read(name)
        local file = assert(io.open(root .. name, "rb"))
        local source = file:read("*a")
        file:close()
        return source
    end

    local function count_plain(source, needle)
        local count, cursor = 0, 1
        while true do
            local at = source:find(needle, cursor, true)
            if not at then return count end
            count = count + 1
            cursor = at + #needle
        end
    end

    local entry = read("character_weapon_variants.lua")
    local catalog = read("_cwv_variant_catalog.lua")
    local cross_access = read("_cwv_cross_access.lua")
    local core_templates = read("_cwv_core_templates.lua")
    local skin_registry = read("_cwv_skin_registry.lua")
    local illusion_families = read("_cwv_illusion_families.lua")
    local husk = read("_cwv_husk_path.lua")
    local lifecycle = read("_cwv_commands_lifecycle.lua")
    local identity = read("_cwv_regression_identity.lua")
    local render = read("_cwv_regression_render.lua")

    H.test("CWV entry remains below its frozen line baseline", function()
        local lines = 0
        for _ in entry:gmatch("[^\r\n]+") do lines = lines + 1 end
        -- 7825 = 2026-08-06 Phase-5 ordered skin/illusion registry extraction.
        -- Base/custom registration and generated families moved to two
        -- sub-1500-line owners at one adjacent install seam. This ceiling only
        -- ratchets DOWN as later CWV decomposition slices land.
        H.truthy(lines <= 7825, "entry line count exceeded frozen 7825-line baseline")
    end)

    H.test("CWV decomposition modules install exactly once and in lifecycle order", function()
        local modules = {
            "_cwv_variant_catalog",
            "_cwv_cross_access",
            "_cwv_core_templates",
            "_cwv_skin_registry",
            "_cwv_illusion_families",
            "_cwv_husk_path",
            "_cwv_commands_lifecycle",
            "_cwv_regression_identity",
            "_cwv_regression_render",
        }
        for _, module_name in ipairs(modules) do
            H.equal(count_plain(entry, module_name), 1, module_name .. " load count")
        end

        local cross_at = assert(entry:find("_cwv_cross_access", 1, true))
        local core_at = assert(entry:find("_cwv_core_templates", 1, true))
        local skin_at = assert(entry:find("_cwv_skin_registry", 1, true))
        local families_at = assert(entry:find("_cwv_illusion_families", 1, true))
        local husk_at = assert(entry:find("_cwv_husk_path", 1, true))
        local lifecycle_at = assert(entry:find("_cwv_commands_lifecycle", 1, true))
        local identity_at = assert(entry:find("_cwv_regression_identity", 1, true))
        local render_at = assert(entry:find("_cwv_regression_render", 1, true))
        H.truthy(cross_at < core_at)
        H.truthy(core_at < skin_at)
        H.truthy(skin_at < families_at)
        H.truthy(families_at < husk_at)
        H.truthy(husk_at < lifecycle_at)
        H.truthy(lifecycle_at < identity_at)
        H.truthy(identity_at < render_at)
    end)

    H.test("CWV skin owners inject once and preserve registrar order", function()
        H.equal(count_plain(entry, "_cwv_skin_registry"), 1)
        H.equal(count_plain(entry, "_cwv_illusion_families"), 1)
        H.equal(count_plain(entry, "CWV_SKIN_REGISTRY_INSTALL_ONCE_v1"), 1)

        for _, source in ipairs({ skin_registry, illusion_families }) do
            H.equal(count_plain(source, "mod:hook"), 0)
            H.equal(count_plain(source, "mod:network_register"), 0)
            H.equal(count_plain(source, "mod:command"), 0)
            H.equal(count_plain(source, "mod.on_game_state_changed"), 0)
            H.equal(count_plain(source, "mod.on_enabled"), 0)
            H.equal(count_plain(source, "mod.on_disabled"), 0)
            H.equal(count_plain(source, "mod.on_unload"), 0)
        end

        local registrars = {
            { skin_registry, "_register_variant_skins" },
            { skin_registry, "_register_cwv_skin_combinations" },
            { skin_registry, "_register_custom_illusions" },
            { illusion_families, "_register_infantry_spear_illusions" },
            { illusion_families, "_register_kruber_1h_sword_dual_illusions" },
            { illusion_families, "_register_saltzpyre_1h_axe_dual_illusions" },
            { illusion_families, "_register_es_1h_mace_dual_illusions" },
            { illusion_families, "_register_macesword_mace_maul_illusions" },
            { illusion_families, "_register_greataxe_model_illusions" },
            { illusion_families, "_register_rapier_illusions" },
            { illusion_families, "_register_imperial_longsword_shield_illusions" },
            { illusion_families, "_register_axe_shield_illusions" },
            { illusion_families, "_register_sword_and_mace_illusions" },
        }
        for _, registrar in ipairs(registrars) do
            local source, name = registrar[1], registrar[2]
            H.equal(count_plain(source, "local function " .. name .. "()"), 1,
                name .. " owner count")
            H.equal(count_plain(entry, "local function " .. name .. "()"), 0,
                name .. " entry duplicate")
        end

        local skin_call_order = {
            "_register_variant_skins()",
            "_register_cwv_skin_combinations()",
            "_register_custom_illusions()",
        }
        local cursor = 1
        for _, call in ipairs(skin_call_order) do
            local name = call:sub(1, -3)
            local definition = assert(skin_registry:find(
                "local function " .. name .. "()", cursor, true))
            local at = skin_registry:find(call, definition + #call, true)
            H.truthy(at, "missing ordered registrar call " .. call)
            cursor = at + #call
        end

        local family_call_order = {
            "_register_infantry_spear_illusions()",
            "_register_kruber_1h_sword_dual_illusions()",
            "_register_saltzpyre_1h_axe_dual_illusions()",
            "_register_es_1h_mace_dual_illusions()",
            "_register_macesword_mace_maul_illusions()",
            "_register_greataxe_model_illusions()",
            "_register_rapier_illusions()",
            "_register_imperial_longsword_shield_illusions()",
            "_register_axe_shield_illusions()",
            "_register_sword_and_mace_illusions()",
        }
        cursor = 1
        for _, call in ipairs(family_call_order) do
            local name = call:sub(1, -3)
            local definition = assert(illusion_families:find(
                "local function " .. name .. "()", cursor, true))
            local at = illusion_families:find(call, definition + #call, true)
            H.truthy(at, "missing ordered registrar call " .. call)
            cursor = at + #call
        end

        local unlock_at = assert(entry:find(
            'mod:hook_safe("BackendInterfaceCraftingPlayfab", "get_unlocked_weapon_skins"',
            1, true))
        local unlocks_applied_at = assert(entry:find("_apply_weapon_unlocks()", 1, true))
        local skin_at = assert(entry:find("_cwv_skin_registry", 1, true))
        local families_at = assert(entry:find("_cwv_illusion_families", 1, true))
        H.truthy(unlocks_applied_at < skin_at)
        H.truthy(skin_at < families_at)
        H.truthy(families_at < unlock_at)

        H.truthy(skin_registry:find("custom_illusions = _custom_illusions", 1, true))
        H.truthy(skin_registry:find("custom_skin_keys = _custom_skin_keys", 1, true))
        H.truthy(entry:find("local _custom_illusions = _skin_state.custom_illusions", 1, true))
        H.truthy(entry:find("local _custom_skin_keys = _skin_state.custom_skin_keys", 1, true))
        H.truthy(entry:find("custom_skin_keys = _custom_skin_keys", 1, true))
        H.truthy(illusion_families:find(
            "local _custom_skin_keys = assert(deps.custom_skin_keys", 1, true))
        H.truthy(illusion_families:find(
            "local _illusion_provenance = assert(deps.illusion_provenance", 1, true))
    end)

    H.test("CWV core-template owner injects once and preserves constructor order", function()
        H.equal(count_plain(entry, "_cwv_core_templates"), 1)
        H.equal(count_plain(entry, "CWV_CORE_TEMPLATES_INSTALL_ONCE_v1"), 1)
        H.equal(count_plain(core_templates, "mod:hook"), 0)
        H.equal(count_plain(core_templates, "mod:command"), 0)
        H.equal(count_plain(core_templates, "mod:dofile("), 0)
        H.equal(count_plain(entry, "local function _clone_damage_profile"), 0)
        H.equal(count_plain(core_templates, "local _clone_damage_profile"), 1)
        H.equal(count_plain(core_templates, "_clone_damage_profile = function"), 1)
        H.truthy(entry:find("}).clone_damage_profile", 1, true))

        local dependencies = {
            "Weapons", "DamageProfileTemplates", "PowerLevelTemplates",
            "NetworkLookup", "ItemMasterList", "AttachmentNodeLinking",
            "Projectiles", "ActionTemplates", "printf",
        }
        H.truthy(entry:find("om = _om", 1, true))
        H.truthy(core_templates:find("local _om = deps.om", 1, true))
        for _, name in ipairs(dependencies) do
            H.truthy(entry:find(name .. " = " .. name, 1, true), "entry injects " .. name)
            H.truthy(core_templates:find("local " .. name .. " = deps." .. name, 1, true),
                "owner localizes " .. name)
        end

        local ordered_calls = {
            "_create_infantry_spear_template()",
            "_create_imperial_longsword_template()",
            "_create_imperial_longsword_shield_template()",
            "_create_elven_sword_shield_template()",
            "_create_imperial_dual_swords_template()",
            "_create_cudgel_template()",
            "_create_sword_and_mace_template()",
            "_create_shortsword_template()",
            "_create_maul_template()",
            "_create_greataxe_template()",
            "_create_outrider_grenade_launcher_template()",
        }
        local cursor = 1
        for _, call in ipairs(ordered_calls) do
            local plain = core_templates:find("\n" .. call, cursor, true)
            local indented = core_templates:find("\n\t" .. call, cursor, true)
            local at = plain
            if indented and (not at or indented < at) then at = indented end
            H.truthy(at, "missing ordered constructor call " .. call)
            cursor = at + #call
        end

        local combined = require("cwv_source").combined(repo_root)
        H.truthy(combined:find("_clone_damage_profile = function", 1, true))
        H.truthy(combined:find("Created outrider_grenade_launcher_template", 1, true))
        H.equal(combined:find("_cwv_preview_meshswap_apply", 1, true) ~= nil, true)
    end)

    H.test("CWV canonical network animation hooks still have one owner", function()
        H.equal(count_plain(cross_access,
            '\nmod:hook_safe("SimpleInventoryExtension", "wield"'), 1)
        H.equal(count_plain(cross_access,
            '\nmod:hook("WeaponUnitExtension", "_play_3p_anim"'), 1)
        H.equal(count_plain(entry,
            '\nmod:hook_safe("SimpleInventoryExtension", "wield"'), 0)
        H.equal(count_plain(entry,
            '\nmod:hook("WeaponUnitExtension", "_play_3p_anim"'), 0)
        H.truthy(cross_access:find("wield_hook_registration_count", 1, true))
        H.truthy(entry:find(
            "wield_hook_registration_count = _cwv_wield_hook_registration_count", 1, true))
    end)

    H.test("CWV final lifecycle callbacks remain consolidated", function()
        for _, callback in ipairs({
            "mod.on_game_state_changed = function",
            "mod.on_enabled = function",
            "mod.on_disabled = function",
            "mod.on_unload = function",
        }) do
            H.equal(count_plain(lifecycle, "\n" .. callback), 1, callback)
            H.equal(count_plain(entry, "\n" .. callback), 0, callback .. " entry duplicate")
        end
        H.truthy(lifecycle:find("_old_musket_request_states", 1, true))
        H.truthy(lifecycle:find("crowbill_runtime.request_states", 1, true))
        H.truthy(lifecycle:find("_acquire_dual_weapon_fp_residency", 1, true))
        H.truthy(lifecycle:find("_release_dual_weapon_fp_residency", 1, true))
    end)

    H.test("CWV regression registration split preserves all checks and boundary", function()
        local names = {}
        for name in (identity .. "\n" .. render):gmatch('_rt_register%("([^"]+)"') do
            names[#names + 1] = name
        end
        H.equal(#names, 80)
        H.equal(names[1], "cwv_variant_flag_present")
        H.equal(names[37], "cwv_husk_transform_coverage")
        H.equal(names[38], "cwv_husk_stale_unit_and_postcondition")
        H.equal(names[39], "cwv_unit_bearing_variants_registered")
        H.equal(names[#names - 2], "issue567_skin_reverse_index_valid")
        H.equal(names[#names - 1], "issue704_canonical_skin_owner_and_sword_mace_sources")
        H.equal(names[#names], "issue915_maul_illusion_vanilla_provenance")
        H.truthy(entry:find("mod_version = MOD_VERSION", 1, true))
        H.truthy(entry:find("dbg = _dbg", 1, true))
        H.truthy(render:find("local MOD_VERSION = ctx.mod_version", 1, true))
        H.truthy(render:find("local _dbg = ctx.dbg", 1, true))
        local seen = {}
        for _, name in ipairs(names) do
            H.equal(seen[name], nil, "duplicate regression name " .. name)
            seen[name] = true
        end
    end)

    H.test("CWV catalog stays data-only and retains policy-backed identities", function()
        H.equal(count_plain(catalog, "mod:hook"), 0)
        H.equal(count_plain(catalog, "mod:command"), 0)
        H.truthy(catalog:find("_om.greataxe.BASE_WEAPON", 1, true))
        H.truthy(catalog:find("_om.dawi_maces.NATIVE_ONE_HANDED", 1, true))
        H.truthy(catalog:find("_om.crowbill_family.SOURCE_ITEM", 1, true))
        H.truthy(catalog:find("definitions = _variant_definitions", 1, true))
    end)

    H.test("CWV husk-path machinery lives once in its module, reached from entry hooks", function()
        -- OOP W5 husk-path extraction: the husk display / transform / ledger /
        -- postcondition helpers (#474/#475/#478/#399/#397/#394/#604/#395/#660)
        -- moved verbatim to _cwv_husk_path. Each _om._husk_* definition must live
        -- exactly ONCE, in the module; the entry keeps only the deferred hook call
        -- sites (GearUtils.spawn_inventory_unit / BackendUtils.get_item_units).
        local exports = {
            "_om._husk_rekey_units = function",
            "_om._husk_strip_cwv_ammo = function",
            "_om._husk_apply_cwv_transform = function",
            "_om._husk_preselect_units = function",
            "_om._husk_resolve_display_def = function",
            "_om._husk_record_override_unit = function",
            "_om._husk_postcondition_log = function",
            "_om._no_ammo_careers_by_base =",
            "_om._husk_unit_ledger = setmetatable",
        }
        for _, marker in ipairs(exports) do
            H.equal(count_plain(husk, marker), 1, "module owns " .. marker)
            H.equal(count_plain(entry, marker), 0, "entry no longer defines " .. marker)
        end

        -- Entry reaches the moved helpers through the COMPLETE husk adapter seams
        -- (issues 394/398/399/401/474/476/482/719): one pre-spawn call and one
        -- post-spawn call; the module owns the per-concern dispatch.
        H.truthy(entry:find("_om._husk_adapter_pre(hand, item_template", 1, true))
        H.truthy(entry:find("_om._husk_adapter_post(hand, item_data", 1, true))
        H.truthy(entry:find("_om._husk_preselect_units(result, item_data", 1, true))
        H.truthy(husk:find("_om._husk_rekey_units(hand, item_data", 1, true))
        H.truthy(husk:find("_om._husk_apply_cwv_transform(hand, item_data", 1, true))

        -- Module received its entry file-local dependencies as explicit context.
        H.truthy(husk:find("local _variant_definitions = ctx.variant_definitions", 1, true))
        H.truthy(husk:find("local _find_def = ctx.find_def", 1, true))
        H.truthy(husk:find("local _is_unit = ctx.is_unit", 1, true))
        H.truthy(husk:find("local _apply_cwv_hand_transform = ctx.apply_cwv_hand_transform", 1, true))
        H.truthy(husk:find("local _triplet_text = ctx.triplet_text", 1, true))

        -- FRESH coop-unverified printf markers survived the move byte-identical;
        -- the in-game #395/#399/#660 verification depends on these exact lines.
        H.truthy(husk:find("[cwv husk-ammo-strip] stripped inherited ammo 3P unit", 1, true))
        H.truthy(husk:find("[cwv:660] lifecycle=husk_wield adapter=hand_selection", 1, true))
        H.truthy(husk:find("[cwv husk-transform] applied hand=%s def=%s source=%s", 1, true))
        H.equal(count_plain(entry, "[cwv husk-ammo-strip] stripped inherited ammo 3P unit"), 0,
            "husk-ammo-strip marker no longer in entry")
    end)
end
