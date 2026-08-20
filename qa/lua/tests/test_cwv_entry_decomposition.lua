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
    local husk_residency = read("_cwv_husk_residency_owner.lua")
    local registration = read("_cwv_item_registration_owner.lua")
    local menu_preview = read("_cwv_menu_preview_owner.lua")
    local weapon_transform = read("_cwv_weapon_transform_owner.lua")
    local custom_mesh = read("_cwv_custom_mesh_runtime.lua")
    local old_musket_preview = read("_cwv_old_musket_preview.lua")
    local equip_surface = read("_cwv_musket_equip_surface.lua")
    local musket_runtime = read("_cwv_musket_runtime.lua")
    local musket_ammo_hud = read("_cwv_musket_ammo_hud.lua")
    local lifecycle = read("_cwv_commands_lifecycle.lua")
    local identity = read("_cwv_regression_identity.lua")
    -- #1188/#1186 split out of the identity owner when it crossed the section 2.1
    -- hard limit; it dofiles BETWEEN identity and render, so its checks keep the
    -- registration slots they already held.
    local husk_ammo = read("_cwv_regression_husk_ammo.lua")
    local render = read("_cwv_regression_render.lua")
    local javelin_runtime = read("_cwv_javelin_runtime_owner.lua")
    local rapier_runtime = read("_cwv_rapier_runtime_owner.lua")
    local variant_bootstrap = read("_cwv_variant_bootstrap_owner.lua")
    local identity_transport = read("_cwv_item_identity_transport_owner.lua")
    local world_equipment = read("_cwv_world_equipment_owner.lua")

    H.test("CWV entry remains below its frozen line baseline", function()
        local lines = 0
        for _ in entry:gmatch("[^\r\n]+") do lines = lines + 1 end
        -- 1490 = 2026-08-12 #1159 structural completion after the javelin,
        -- rapier, variant-bootstrap, identity-transport, and world-equipment
        -- owners moved out. This ceiling only ratchets DOWN.
        H.truthy(lines <= 1490, "entry line count exceeded frozen 1490-line baseline")
    end)

    H.test("CWV completion owners stay bounded and resource-safe", function()
        local owners = {
            javelin_runtime,
            rapier_runtime,
            variant_bootstrap,
            identity_transport,
            world_equipment,
        }
        for _, source in ipairs(owners) do
            local lines = 0
            for line in source:gmatch("[^\r\n]+") do
                if line:match("%S") then lines = lines + 1 end
            end
            H.truthy(lines < 1500, "extracted owner exceeded the 1500-line owner ceiling")
        end

        -- resource-safety: cwv1159-javelin-runtime-force-load
        H.equal(count_plain(javelin_runtime,
            "resource-safety: cwv1159-javelin-runtime-force-load"), 1)
        for _, call in ipairs({
            'Managers.package:load(_TJ_THROWING_AXE_PUP, "cwv_throwing_axe_pup", nil, true, true)',
            'Managers.package:load(_TJB_HELD_UNIT, "cwv_javelin_bomb", nil, true, true)',
            'Managers.package:load(_TJB_HELD_UNIT .. "_3p", "cwv_javelin_bomb", nil, true, true)',
        }) do
            H.equal(count_plain(javelin_runtime, call), 1,
                "one file-level marker covers each moved lifetime package lease")
        end
        H.equal(count_plain(entry,
            "resource-safety: cwv1159-javelin-runtime-force-load"), 0)
    end)

    H.test("CWV decomposition modules install exactly once and in lifecycle order", function()
        local modules = {
            "_cwv_variant_catalog",
            "_cwv_cross_access",
            "_cwv_core_templates",
            "_cwv_skin_registry",
            "_cwv_illusion_families",
            "_cwv_husk_residency_owner",
            "_cwv_custom_mesh_runtime",
            "_cwv_javelin_runtime_owner",
            "_cwv_rapier_runtime_owner",
            "_cwv_variant_bootstrap_owner",
            "_cwv_item_registration_owner",
            "_cwv_weapon_transform_owner",
            "_cwv_husk_path",
            "_cwv_item_identity_transport_owner",
            "_cwv_world_equipment_owner",
            "_cwv_menu_preview_owner",
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
        local residency_at = assert(entry:find("_cwv_husk_residency_owner", 1, true))
        local custom_mesh_at = assert(entry:find("_cwv_custom_mesh_runtime", 1, true))
        local javelin_at = assert(entry:find("_cwv_javelin_runtime_owner", 1, true))
        local rapier_at = assert(entry:find("_cwv_rapier_runtime_owner", 1, true))
        local bootstrap_at = assert(entry:find("_cwv_variant_bootstrap_owner", 1, true))
        local registration_at = assert(entry:find("_cwv_item_registration_owner", 1, true))
        local transform_at = assert(entry:find("_cwv_weapon_transform_owner", 1, true))
        local husk_at = assert(entry:find("_cwv_husk_path", 1, true))
        local identity_transport_at = assert(entry:find("_cwv_item_identity_transport_owner", 1, true))
        local world_equipment_at = assert(entry:find("_cwv_world_equipment_owner", 1, true))
        local menu_preview_at = assert(entry:find("_cwv_menu_preview_owner", 1, true))
        local lifecycle_at = assert(entry:find("_cwv_commands_lifecycle", 1, true))
        local identity_at = assert(entry:find("_cwv_regression_identity", 1, true))
        local husk_ammo_at = assert(entry:find("_cwv_regression_husk_ammo", 1, true))
        local render_at = assert(entry:find("_cwv_regression_render", 1, true))
        H.truthy(cross_at < core_at)
        -- #1159: the husk-residency owner force-loads at boot, long before the
        -- skin/illusion registries and the husk-path display helpers exist.
        H.truthy(core_at < residency_at)
        -- #1159: the custom-mesh runtime owner installs the LA-pattern package
        -- shims, the inventory-package wire aliases and the Old Musket FX-proxy
        -- redirects at the same point in load its inline blocks ran: after the
        -- husk-residency boot force-loads, and well before the skin/illusion
        -- registrars and every later render surface that resolves through the
        -- `_om` seams it publishes.
        H.truthy(residency_at < custom_mesh_at)
        H.truthy(custom_mesh_at < javelin_at)
        H.truthy(javelin_at < rapier_at)
        H.truthy(rapier_at < bootstrap_at)
        H.truthy(bootstrap_at < skin_at)
        H.truthy(custom_mesh_at < skin_at)
        H.truthy(residency_at < skin_at)
        H.truthy(core_at < skin_at)
        H.truthy(skin_at < families_at)
        -- #1159: the item-registration owner loads after the skin/illusion
        -- registrars (its #567 rebuild consumes their pools) and before the
        -- husk-path display helpers.
        H.truthy(families_at < registration_at)
        -- #1159: the weapon-transform owner builds the transform registries the
        -- husk display helpers and every later render surface resolve against,
        -- and it must load after the registration owner publishes the #482
        -- backend-id resolver its `_resolve_cwv_def` ladder calls.
        H.truthy(registration_at < transform_at)
        H.truthy(transform_at < husk_at)
        H.truthy(registration_at < husk_at)
        H.truthy(families_at < husk_at)
        H.truthy(husk_at < identity_transport_at)
        H.truthy(identity_transport_at < world_equipment_at)
        H.truthy(world_equipment_at < menu_preview_at)
        -- #1159: the keep/menu preview-surface owner registers the last render
        -- hooks in the chain. It must load after the husk display helpers and
        -- before the commands/lifecycle owner, which the entry deliberately
        -- installs only once every gameplay and render hook is registered.
        H.truthy(husk_at < menu_preview_at)
        H.truthy(menu_preview_at < lifecycle_at)
        H.truthy(husk_at < lifecycle_at)
        H.truthy(lifecycle_at < identity_at)
        -- The husk-ammo owner sits BETWEEN its two siblings: _rt_register appends
        -- to one ordered runner list, so that position is what preserves the
        -- registration slots its checks held before the split.
        H.truthy(identity_at < husk_ammo_at)
        H.truthy(husk_ammo_at < render_at)
    end)

    H.test("CWV companion detection crosses the phased bootstrap boundary", function()
        H.equal(count_plain(variant_bootstrap,
            "detect_companion_mods = _detect_companion_mods"), 1,
            "bootstrap must export its diagnostic-only companion detector")
        H.equal(count_plain(entry,
            "local _detect_companion_mods = assert(_variant_runtime.detect_companion_mods"), 1,
            "entry must bind and validate the completed bootstrap export")
        H.equal(count_plain(entry,
            "detect_companion_mods = _detect_companion_mods"), 1,
            "entry must pass the validated detector to the lifecycle owner")
        H.equal(count_plain(lifecycle,
            "local _detect_companion_mods = assert(ctx.detect_companion_mods"), 1,
            "lifecycle owner must reject a missing detector before first use")
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

        local unlock_at = assert(variant_bootstrap:find(
            'mod:hook_safe("BackendInterfaceCraftingPlayfab", "get_unlocked_weapon_skins"',
            1, true))
        local unlocks_applied_at = assert(variant_bootstrap:find("_apply_weapon_unlocks()", 1, true))
        local skin_at = assert(entry:find("_cwv_skin_registry", 1, true))
        local families_at = assert(entry:find("_cwv_illusion_families", 1, true))
        H.truthy(skin_at < families_at)
        H.truthy(unlocks_applied_at < unlock_at)
        H.truthy(families_at < assert(entry:find("_finish_variant_skins(_custom_skin_keys)", 1, true)))

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

        H.truthy(entry:find("om = _om", 1, true))
        H.truthy(core_templates:find("local _om = deps.om", 1, true))

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

    H.test("CWV #1108 HUD owner loads once and installs after its ammo pool", function()
        local hud_load = 'mod:dofile("scripts/mods/character_weapon_variants/_cwv_musket_ammo_hud")'
        local runtime_load = 'mod:dofile("scripts/mods/character_weapon_variants/_cwv_musket_runtime")'
        H.equal(count_plain(entry, hud_load), 0)
        H.equal(count_plain(entry, runtime_load), 1)
        H.equal(count_plain(musket_runtime, hud_load), 1)

        local load_at = assert(musket_runtime:find(hud_load, 1, true))
        local pool_at = assert(musket_runtime:find(
            "musket_ammo_pool_policy.install", 1, true))
        local hud_at = assert(musket_runtime:find(
            "musket_ammo_hud_policy.install", 1, true))
        H.truthy(load_at < pool_at and pool_at < hud_at)
        H.equal(count_plain(musket_runtime, "musket_ammo_hud_policy.install"), 1)
        H.equal(count_plain(entry, "musket_ammo_hud_policy.install"), 0)

        H.equal(count_plain(musket_ammo_hud, '"EquipmentUI"'), 1)
        H.equal(count_plain(musket_ammo_hud, '"GamePadEquipmentUI"'), 1)
        H.equal(count_plain(musket_ammo_hud,
            'mod:hook_safe(class_name, "_sync_player_equipment"'), 1)
        H.equal(count_plain(musket_ammo_hud, "mod:hook("), 0)
        H.equal(count_plain(musket_ammo_hud, "mod:network_"), 0)
    end)

    H.test("CWV regression registration split preserves all checks and boundary", function()
        local names = {}
        -- Concatenated in ENTRY DOFILE ORDER, so the index pins below describe the
        -- order the runner actually registers in, not the order files happen to
        -- be read here.
        for name in (identity .. "\n" .. husk_ammo .. "\n" .. render)
                :gmatch('_rt_register%("([^"]+)"') do
            names[#names + 1] = name
        end
		H.equal(#names, 90)
        H.equal(names[1], "cwv_variant_flag_present")
        -- #916 registered its style contract directly after the issue620 combat
        -- style check it extends, shifting the later identity slots by one.
        H.equal(names[3], "issue916_half_swording_combat_style_contract")
        H.equal(names[5], "issue914_peer_ready_identity_lifecycle")
        H.equal(names[17], "issue1108_primary_slot_musket_ammo_hud_contract")
        H.equal(names[18], "issue273_cwv_deus_identity_is_exact")
        H.equal(names[39], "cwv_husk_transform_coverage")
        H.equal(names[40], "cwv_husk_stale_unit_and_postcondition")
        -- issue 399 appended the husk ammo-adapter drive as an identity check;
        -- #914 and #1108 each added one earlier identity check. The 1186/1188
        -- slots moved OUT of the identity owner into _cwv_regression_husk_ammo
        -- when that file crossed the section 2.1 hard limit; because the entry
        -- dofiles it between its two siblings the relative sequence is the
        -- split's proof as well as the boundary's. #1320 registers third in the
        -- husk/ammo/projectile owner.
        H.equal(names[41], "issue399_outrider_husk_ammo_adapter")
        H.equal(names[42], "issue1204_deus_identity_uses_committed_parity")
        H.equal(names[43], "issue1186_outrider_projectile_reads_cloned_tunes")
        H.equal(names[44], "issue1188_wt_native_trollhammer_keeps_ammo")
        H.equal(names[45], "issue1320_outrider_projectile_unit_and_wire")
		H.equal(names[46], "cwv_unit_bearing_variants_registered")
		H.equal(names[47], "issue482_crafted_uuid_transform_consumers")
        -- #1155 is a renderer/material/lifecycle check. Keep it in the render
        -- regression owner so identity remains below the hard file-size ceiling.
        H.equal(names[72], "issue1155_old_musket_descriptor_reconciler")
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

        -- The moved helpers are reached through the COMPLETE husk adapter seams
        -- (issues 394/398/399/401/474/476/482/719): one pre-spawn call and one
        -- post-spawn call; the module owns the per-concern dispatch. #1159 moved
        -- the spawn_inventory_unit hook that carries both seams into the musket
        -- equip-surface owner (the bayonet attach and the melee-stance transform
        -- are inline in that same hook body), so the calls are asserted there.
        -- The get_item_units seam stayed in the entry.
		H.truthy(equip_surface:find("_om._husk_adapter_pre(", 1, true))
		H.truthy(equip_surface:find("_om._husk_adapter_post(", 1, true))
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

    H.test("CWV husk-residency owner holds the boot force-loads and the #280 crash floor", function()
        -- #1159 slice: the base-unit force-load (#280), the data-driven
        -- override-unit residency pass (issues 396/401) and the start_weapon_fx
        -- nil-slot guard (#280) moved verbatim out of the entry. Each producer
        -- must live exactly ONCE, in the owner, and nowhere in the entry.
        local owned = {
            "local function _force_load_axe_shield_husk_units()",
            "local function _force_load_husk_override_units()",
            "_om._husk_override_unit_needs_residency = function(def, field)",
            'mod:hook("SimpleHuskInventoryExtension", "start_weapon_fx"',
        }
        for _, marker in ipairs(owned) do
            H.equal(count_plain(husk_residency, marker), 1, "residency owner owns " .. marker)
            H.equal(count_plain(entry, marker), 0, "entry no longer defines " .. marker)
        end

        -- The four bare globals the regression suite reads are still published,
        -- from the owner rather than the entry.
        for _, flag in ipairs({
            "_cwv_axe_shield_residency_ran = true",
            "_cwv_husk_override_residency_ran = true",
            "_cwv_husk_override_paths = _loaded",
            "_cwv_husk_fx_guard_installed = true",
        }) do
            H.equal(count_plain(husk_residency, flag), 1, "residency owner publishes " .. flag)
            H.equal(count_plain(entry, flag), 0, "entry no longer publishes " .. flag)
        end

        -- Entry-local dependencies arrive as explicit context, same shape as
        -- _cwv_husk_path. `_variant_definitions` is bound once in the entry and
        -- never rebound, so the captured reference cannot go stale.
        H.truthy(husk_residency:find("local function install(mod, ctx)", 1, true))
        H.truthy(husk_residency:find("local _om = ctx.om", 1, true))
        H.truthy(husk_residency:find("local _variant_definitions = ctx.variant_definitions", 1, true))
        H.truthy(entry:find("variant_definitions = _variant_definitions })", 1, true))

        -- Log markers the in-game #280/#396/#401 verification greps for survived
        -- the move byte-identical.
        H.truthy(husk_residency:find("[cwv axe-shield-residency] force-loaded %s (ref=%s, resident=%s)", 1, true))
        H.truthy(husk_residency:find("[cwv husk-override-residency] force-loaded %s (ref=%s, resident=%s, for=%s.%s)", 1, true))
        H.truthy(husk_residency:find("[cwv husk-fx-guard] SKIP start_weapon_fx", 1, true))

        -- BOUNDARY: the two husk owners must not overlap. Residency owns the
        -- boot force-loads; husk_path owns the per-spawn display adapters. The
		-- The executable husk wield owner lives with the spawn ledger it consumes;
		-- the entry retains only the one installer call.
        H.equal(count_plain(husk_residency, "_om._husk_adapter_pre"), 0,
            "residency owner must not reach into husk-path spawn adapters")
        H.equal(count_plain(husk_residency, "_om._husk_rekey_units"), 0,
            "residency owner must not reach into husk-path mesh re-key")
        H.equal(count_plain(husk, "_force_load_husk_override_units"), 0,
            "husk-path module must not duplicate the residency pass")
		H.equal(count_plain(husk_residency, 'mod:hook("SimpleHuskInventoryExtension", "_wield_slot"'), 0)
		H.equal(count_plain(entry, 'mod:hook("SimpleHuskInventoryExtension", "_wield_slot"'), 0)
		H.equal(count_plain(husk,
			'hook_mod:hook("SimpleHuskInventoryExtension", "_wield_slot"'), 1,
			"husk path owns exactly one executable _wield_slot hook")
		H.equal(count_plain(entry, "_om._install_husk_wield_hook(mod)"), 1)

        -- Hook cardinality: VMF silently drops a duplicate registration on the
        -- same (Class, method), so each husk-extension pair must appear once
        -- across the whole mod. start_weapon_fx now lives in this owner.
        local fade = read("_cwv_appearance_fade.lua")
        local combined = entry .. husk .. husk_residency .. fade
        H.equal(count_plain(combined, 'mod:hook("SimpleHuskInventoryExtension", "start_weapon_fx"'), 1)
		H.equal(count_plain(combined,
			'hook_mod:hook("SimpleHuskInventoryExtension", "_wield_slot"'), 1)
        H.equal(count_plain(combined, 'mod:hook("SimpleHuskInventoryExtension", "_reapply_fade"'), 1)
    end)

    H.test("CWV item-registration owner holds definition-to-backend registration", function()
        -- #1159 slice: the #482 identity ladder, the `_build_entry` clone
        -- constructor and the deferred `_auto_register_all` session pass moved
        -- verbatim out of the entry. Each producer lives exactly ONCE, in the
        -- owner, and nowhere in the entry.
        local owned = {
            "local _registered_keys = {}",
            "local function _registered_cwv_key(candidate)",
            "local function _remember_cwv_identity(backend_id, key, evidence)",
            "_om._cwv_key_for_item = function(backend_id, item_data)",
            "local function _build_entry(def, backend_id)",
            "local _auto_registered = false",
            "_om.install_deus_identities = function(reason)",
            "mod._cwv567_validate_skin_association = function(skin_key)",
            "local function _auto_register_all()",
            'mod:hook_safe("StateInGameRunning", "on_enter"',
            'mod:hook("DeusMechanism", "_setup_run"',
        }
        for _, marker in ipairs(owned) do
            H.equal(count_plain(registration, marker), 1, "registration owner owns " .. marker)
            H.equal(count_plain(entry, marker), 0, "entry no longer defines " .. marker)
        end

        -- Hook cardinality: VMF silently drops a duplicate registration on the
        -- same (Class, method), so each moved pair must appear exactly once
        -- across the whole load chain.
        local combined = require("cwv_source").combined(repo_root)
        H.equal(count_plain(combined, 'mod:hook_safe("StateInGameRunning", "on_enter"'), 1)
        H.equal(count_plain(combined, 'mod:hook("DeusMechanism", "_setup_run"'), 1)

        -- #428 NON-FOLD: the inline bidirectional NetworkLookup.item_names
        -- register moved BYTE-IDENTICAL. Collapsing it onto _lib_network_lookup
        -- is a behavior-adjacent change that rides its own slice, so the owner
        -- must not reach the shared helper.
        H.equal(count_plain(registration, "local idx = #NetworkLookup.item_names + 1"), 1)
        H.equal(count_plain(registration, "rawset(NetworkLookup.item_names, idx, key)"), 1)
        H.equal(count_plain(registration, "rawset(NetworkLookup.item_names, key, idx)"), 1)
        H.equal(count_plain(registration, "_lib_network_lookup"), 0,
            "#428 fold must not ride this slice")
        H.equal(count_plain(entry, "local idx = #NetworkLookup.item_names + 1"), 0)

        -- Entry-local dependencies arrive as explicit context, same shape as
        -- _cwv_husk_path / _cwv_husk_residency_owner. Every one of these is
        -- bound exactly once in the entry and never rebound.
        H.truthy(registration:find("local function install(mod, ctx)", 1, true))
        H.truthy(entry:find("dbg_alert = _dbg_alert,", 1, true))
        H.truthy(entry:find("cwv_career_weapon_actions = _cwv_career_weapon_actions,", 1, true))
        H.truthy(entry:find("career_action_owner = _career_action_owner,", 1, true))

        -- Seam back: the entry's two context tables consume the SAME table and
        -- function objects through _om rather than re-declaring file-scope
        -- locals (the top-level chunk is at the Lua 5.1 200-local ceiling).
        H.equal(count_plain(registration, "_om.item_registration = {"), 1)
        H.equal(count_plain(entry, "registered_keys = _om.item_registration.registered_keys,"), 2)
        H.equal(count_plain(entry, "build_entry = _om.item_registration.build_entry,"), 1)
        H.equal(count_plain(entry, "auto_register_all = _om.item_registration.auto_register_all,"), 1)

        -- BOUNDARY. Variant lookup, give semantics, and preview descriptors now
        -- share the ordered variant-bootstrap owner; registration must not
        -- absorb them.
        local bootstrap_only = {
            "local function _find_def(item_key)",
            "local function _give_variant(item_key)",
            "_om._give_refuses_skin_only = function(def)",
            "_om._resident_override_3p = function(base_unit)",
            "_om._cwv_resolve_spawn_descriptor = function(",
            "_om._cwv_preview_meshswap_apply = function(",
            "_om._cwv_browser_meshswap_apply = function(",
        }
        for _, marker in ipairs(bootstrap_only) do
            H.equal(count_plain(variant_bootstrap, marker), 1, "bootstrap keeps " .. marker)
            H.equal(count_plain(registration, marker), 0,
                "registration owner must not absorb " .. marker)
        end

        -- No overlap with the sibling owners: no husk spawn/residency reach, no
        -- skin registrar copy, no command/network/lifecycle surface.
        for _, forbidden in ipairs({
            -- `_register_variant_skins` is referenced in a moved COMMENT, so
            -- pin the definition form: the registrar body must stay in
            -- _cwv_skin_registry.
            "_om._husk_adapter_pre", "_om._husk_rekey_units",
            "_force_load_husk_override_units", "local function _register_variant_skins()",
            "mod:command", "mod:network_register", "mod.on_", "mod:dofile(",
        }) do
            H.equal(count_plain(registration, forbidden), 0,
                "registration owner must not contain " .. forbidden)
        end

        -- Log markers the in-game #482/#567/#592/#273/#661 verification greps
        -- for survived the move byte-identical.
        local markers = {
            "[cwv:482] legacy identity recovered bid=%s key=%s evidence=%s count=%d/16",
            "[cwv:661] career-action integration ready templates=%d prepared=%d restored=%d discarded_claims=%d",
            "[cwv:567] cache_invalidated=%s rebuild=%s skin=%s association=%s owner=%s combination=%s rarity=%s cache_item=%s",
            "[cwv:592] definitions=%d blacksmith_seeds=%d seed_failed=%d legacy_ids_purged=%d cim_exact_ids_preserved=true",
            "[cwv:273] deus_identity reason=%s exact=%s installed=%d existing=%d degraded=%d skipped=%d sample=%s",
            "[cwv:auto_register] SUMMARY built_ok=%d build_failed=%d skipped_skin_only=%d skipped_already=%d entries_added=%d (defs=%d)",
        }
        for _, marker in ipairs(markers) do
            H.equal(count_plain(registration, marker), 1, "owner keeps marker " .. marker)
            H.equal(count_plain(entry, marker), 0, "entry no longer prints " .. marker)
        end
    end)

    H.test("CWV menu preview owner holds every keep-menu reconstruction surface", function()
        -- #1159 slice: the previewer def resolver, the shared HeroPreviewer /
        -- MenuWorldPreviewer applier, the #604 TeamPreviewer identity bridge, the
        -- cosmetic picker's illusion filter, the two preview teardown edges and
        -- the illusion-browser spawn path moved verbatim out of the entry as ONE
        -- contiguous block. Each producer lives exactly ONCE, in the owner.
        local owned = {
            "local function _find_preview_slot_info(self, item_name, spawn_data)",
            "local function _crowbill_def_from_spawn_data(spawn_data)",
            "local function _resolve_preview_def(self, item_name, spawn_data)",
            "local function _cwv_spawn_item_post(self, item_name, spawn_data)",
			"local function _cwv_cim_preview_context(previewer)",
			"local function _cwv_loot_preview_surface(previewer)",
            "local function _reconcile_old_musket_loot(self, units, spawn_data, edge)",
            "local function _is_cwv_item(item)",
            "_om._crowbill_team_peer = function(profile_index, career_index, context)",
            "_om.old_musket_preview_pose.install(mod, function(unit, _, mode, record)",
        }
        for _, marker in ipairs(owned) do
            H.equal(count_plain(menu_preview, marker), 1, "menu preview owner owns " .. marker)
            H.equal(count_plain(entry, marker), 0, "entry no longer defines " .. marker)
        end

        -- Hook cardinality: VMF silently DROPS a duplicate registration on the
        -- same (Class, method), so a re-added entry copy would shadow this owner
        -- rather than chain with it. Each of the eight owned pairs must appear
        -- exactly once across the whole load chain, and never in the entry.
        local combined = require("cwv_source").combined(repo_root)
        local hooks = {
            'mod:hook("TeamPreviewer", "_spawn_hero"',
            'mod:hook("HeroWindowItemCustomization", "_setup_illusions"',
            'mod:hook("HeroPreviewer", "_spawn_item"',
            'mod:hook("MenuWorldPreviewer", "_spawn_item"',
            'mod:hook("HeroPreviewer", "_destroy_item_units_by_slot"',
            'mod:hook("LootItemUnitPreviewer", "_destroy_units"',
            'mod:hook("LootItemUnitPreviewer", "spawn_units"',
			'mod:hook_safe("LootItemUnitPreviewer", "_enable_item_units_visibility"',
        }
        for _, hook in ipairs(hooks) do
            H.equal(count_plain(menu_preview, hook), 1, "menu preview owner registers " .. hook)
            H.equal(count_plain(entry, hook), 0, "entry no longer registers " .. hook)
            H.equal(count_plain(combined, hook), 1, "exactly one registration of " .. hook)
        end

        H.truthy(menu_preview:find("local function install(mod, ctx)", 1, true))
        H.equal(count_plain(entry,
            'mod:dofile("scripts/mods/character_weapon_variants/_cwv_menu_preview_owner")(mod, {'), 1,
            "entry installs the menu preview owner exactly once")
		H.equal(count_plain(entry, "get_mod = get_mod,"), 1,
			"entry injects the exact CIM provider resolver once")
		H.truthy(menu_preview:find('pcall(_get_mod, "cim_dev")', 1, true))
		H.truthy(menu_preview:find("provider._cim_preview_context_for", 1, true))
		H.truthy(menu_preview:find('context.contract ~= "cim_preview_context_v1"', 1, true))
		H.equal(count_plain(menu_preview,
			'mod:hook("HeroWindowWeaveProperties", "_create_item_previewer"'), 0,
			"CWV consumes CIM's public context instead of competing for its constructor")

        -- BOUNDARY. CWV has three presentation surfaces and this owner is only
        -- the MENU one. The WORLD/BOT equipment hook and transform-miss evidence
        -- live in their dedicated owner; `_find_def` lives in the ordered
        -- variant bootstrap. The menu owner must absorb neither.
        local world_only = {
            'mod:hook("GearUtils", "create_equipment"',
			"local def = _om._cwv_world_transform_decision(",
            "_crowbill_transform_miss_total = _crowbill_transform_miss_total + 1",
        }
        for _, marker in ipairs(world_only) do
            H.equal(count_plain(world_equipment, marker), 1, "world owner keeps " .. marker)
            H.equal(count_plain(menu_preview, marker), 0,
                "menu preview owner must not absorb " .. marker)
        end
        H.equal(count_plain(variant_bootstrap, "local function _find_def(item_key)"), 1)
        H.equal(count_plain(menu_preview, "local function _find_def(item_key)"), 0)

        -- No overlap with the sibling owners: no husk spawn/residency reach, no
        -- registration path, no command / network / lifecycle / loader surface.
        for _, forbidden in ipairs({
            "_om._husk_adapter_pre", "_om._husk_rekey_units",
            "_force_load_husk_override_units", "local function _build_entry",
            "mod:command", "mod:network_register", "mod.on_", "mod:dofile(",
        }) do
            H.equal(count_plain(menu_preview, forbidden), 0,
                "menu preview owner must not contain " .. forbidden)
        end

        -- The KEY BRIDGE that keyed `_equipment_units` by numeric slot_index has
        -- been reintroduced as a string-keyed loop twice (v0.1.84 here, 0.7.88 in
        -- cosmetics_tweaker). Pin both the warning and the code it guards.
        H.truthy(menu_preview:find("KEY BRIDGE", 1, true))
        H.truthy(menu_preview:find("DO NOT remove or refactor to a string-keyed loop.", 1, true))
        H.truthy(menu_preview:find("and info.spawn_data[1].slot_index", 1, true))

        -- Log markers the in-game #474/#604/#617/#760 verification greps for
        -- survived the move byte-identical.
        local markers = {
            "[cwv:604] TEAM-PREVIEW identity unresolved profile=%s career=%s family=%s evidence=%d/16 chat=false",
            "[cwv:617/1155] Old Musket preview material retained: surface=%s edge=%s item=%s mode=%s targets=%d retained=%d descriptor=true",
            "[cwv preview] _resolve_preview_def returned nil for item_name=%s (info bid=%s)",
            "[cwv preview hook] HeroPreviewer._spawn_item fired item_name=%s self=%s",
            "[cwv preview hook] MenuWorldPreviewer._spawn_item fired item_name=%s self=%s",
        }
        for _, marker in ipairs(markers) do
            H.equal(count_plain(menu_preview, marker), 1, "owner keeps marker " .. marker)
            H.equal(count_plain(entry, marker), 0, "entry no longer prints " .. marker)
        end
    end)

    H.test("CWV custom-mesh runtime owner holds every mod-bundled mesh shim", function()
        -- #1159 slice: a mod-bundled custom mesh has no sibling .package, no
        -- NetworkLookup.inventory_packages entry, no skeleton for the vanilla
        -- template's attachment links and no flow graph for weapon FX. The four
        -- inline blocks that patched those gaps moved out of the entry as ONE
        -- contiguous block. Each producer lives exactly ONCE, in the owner. The
        -- package bridge is only a balanced vanilla lifetime alias; the custom
        -- unit and its authored PBR material are self-contained in CWV.
        local owned = {
            "local _old_musket_package_bridge = mod:dofile(",
            "_om._husk_custom_bundle_unit = function(base_unit)",
            "_om._bind_old_musket_authored_material = _om.old_musket_preview.bind_authored_material",
            "_om._apply_old_musket_appearance = _om.old_musket_preview.apply_material",
            "_om._old_musket_transform_components = function(perspective, mode)",
            "_om.old_musket_appearance = _om.old_musket_appearance_policy.new({",
            "mod._cwv_resolve_preview_descriptor = _om._old_musket_preview_descriptor",
            "_om._spawn_old_musket_fx_proxy = function(world, our_unit, vanilla_path, owner_unit, owner_hand_node_name)",
            "_om._destroy_old_musket_fx_proxy = function(our_unit)",
            "_om._reapply_old_musket_transforms_all = function()",
            "local _orig_unit_has_node = Unit.has_node",
        }
        for _, marker in ipairs(owned) do
            H.equal(count_plain(custom_mesh, marker), 1, "custom-mesh owner owns " .. marker)
            H.equal(count_plain(entry, marker), 0, "entry no longer defines " .. marker)
        end

        -- Hook cardinality: VMF silently DROPS a duplicate registration on the
        -- same (Class, method), so a re-added entry copy would shadow this owner
        -- rather than chain with it. Each of the eight moved pairs must appear
        -- exactly once across the whole load chain, and never in the entry.
        local combined = require("cwv_source").combined(repo_root)
        local hooks = {
            'mod:hook(PackageManager, "load"',
            'mod:hook(PackageManager, "unload"',
            'mod:hook(PackageManager, "has_loaded"',
            'mod:hook(Unit, "node"',
            'mod:hook(Unit, "has_node"',
            'mod:hook(Unit, "flow_event"',
            'mod:hook(Unit, "set_flow_variable"',
            'mod:hook("GearUtils", "link_units"',
        }
        for _, hook in ipairs(hooks) do
            H.equal(count_plain(custom_mesh, hook), 1, "custom-mesh owner registers " .. hook)
            H.equal(count_plain(entry, hook), 0, "entry no longer registers " .. hook)
            H.equal(count_plain(combined, hook), 1, "exactly one registration of " .. hook)
        end

        H.truthy(custom_mesh:find("local function install(mod, ctx)", 1, true))
        H.equal(count_plain(entry,
            'mod:dofile("scripts/mods/character_weapon_variants/_cwv_custom_mesh_runtime")(mod, {'), 1,
            "entry installs the custom-mesh runtime owner exactly once")

        -- The #474 stance channel and package bridge are dofiled from INSIDE the
        -- moved block. The stance channel has to stay there: its `_om` exports
        -- must exist before the fire dispatch
        -- above it runs and before the identity register far below routes into
        -- them. The bridge must also stay beside the sole PackageManager hooks.
        H.equal(count_plain(custom_mesh, "mod:dofile("), 2,
            "custom-mesh owner performs exactly two bounded nested loads")
        H.equal(count_plain(custom_mesh,
            '"scripts/mods/character_weapon_variants/_cwv_old_musket_package_bridge")'), 1,
            "the package hooks consume the #474 balanced lifetime bridge")
        H.equal(count_plain(custom_mesh,
            'mod:dofile("scripts/mods/character_weapon_variants/_cwv_old_musket_wire")(mod, { om = _om })'), 1,
            "the nested load is the #474 Old Musket stance channel")

        -- BOUNDARY. This owner covers the MESH, not the weapon. The Old Musket's
        -- item/template/stance behavior stays in the entry's consolidated
        -- get_item_template hook; the bayonet child-unit lifecycle (a second
        -- VANILLA unit linked to the rifle, not a custom-mesh gap) and every
        -- wield-side hook belong to the musket equip-surface owner, which #1159
        -- lifted out of the entry AFTER this owner landed. Either way they are
        -- not this owner's job, and each must exist exactly once mod-wide.
        local not_custom_mesh = {
            { marker = 'mod:hook("BackendUtils", "get_item_template"', home = entry },
            { marker = 'mod:hook("SimpleInventoryExtension", "_wield_slot"', home = equip_surface },
            { marker = 'mod:hook("GearUtils", "destroy_wielded"', home = equip_surface },
            { marker = "local function _attach_musket_bayonets", home = equip_surface },
            { marker = "_om._destroy_old_musket_fx_proxy(wielded_unit)", home = equip_surface },
        }
        for _, row in ipairs(not_custom_mesh) do
            H.equal(count_plain(row.home, row.marker), 1, "owner of record keeps " .. row.marker)
            H.equal(count_plain(combined, row.marker), 1,
                "exactly one definition of " .. row.marker)
            H.equal(count_plain(custom_mesh, row.marker), 0,
                "custom-mesh owner must not absorb " .. row.marker)
        end

        -- No overlap with the sibling owners: no registration path, no command /
        -- network / lifecycle / regression surface.
        for _, forbidden in ipairs({
            "_om._husk_adapter_pre", "_om._husk_rekey_units",
            "_force_load_husk_override_units", "local function _build_entry",
            "mod:command", "mod:network_register", "mod.on_", "_rt_register",
        }) do
            H.equal(count_plain(custom_mesh, forbidden), 0,
                "custom-mesh owner must not contain " .. forbidden)
        end

        -- The inventory_packages alias is FORWARD-ONLY by design (v0.1.287): we
        -- give our custom paths a vanilla network index, but never overwrite the
        -- index -> vanilla-name direction, which would hijack vanilla equip
        -- events. Both reads stay on rawget because that table has a strict
        -- __index that errors on an unknown key.
        H.truthy(custom_mesh:find(
            'nl_inventory["units/cwv_es_musket_custom/cwv_es_musket_custom"] = vanilla_1p_idx', 1, true))
        H.truthy(custom_mesh:find(
            'nl_inventory["units/cwv_es_musket_custom/cwv_es_musket_custom_3p"] = vanilla_3p_idx', 1, true))
        H.equal(count_plain(custom_mesh, "nl_inventory[vanilla"), 0,
            "the reverse index -> name mapping must stay untouched")
        H.equal(count_plain(custom_mesh, "local vanilla_1p_idx = rawget(nl_inventory,"), 1)
        H.equal(count_plain(custom_mesh, "local vanilla_3p_idx = rawget(nl_inventory,"), 1)

        -- #1155: material ownership lives in the authored asset/policy, not in
        -- this decomposition owner or a surface-specific mutation path.
        H.truthy(old_musket_preview:find(
            'pcall(unit_api.set_all_materials, unit, M.MATERIAL)', 1, true))
        H.truthy(old_musket_preview:find(
            'RESIDENCY.unit_materials_resident(', 1, true))
        H.equal(old_musket_preview:find(
            'unit_api.set_texture_for_materials', 1, true), nil)
        H.equal(custom_mesh:find('Unit.set_texture_for_materials(', 1, true), nil)

		-- v0.1.298: a raw Stingray Quaternion is a per-frame temporary, so the
		-- four held rotations plus #1155's distinct display-carrier candidate
		-- must stay BOXED or their poses turn to garbage a frame after equip.
		H.equal(count_plain(custom_mesh, "= QuaternionBox(Quaternion."), 5,
			"all held and display-profile rotations stay boxed for long-term storage")

        -- v0.1.290/291: Stingray's Unit.node throws an engine-level fatal that
        -- pcall cannot catch, so the attachment filter must test existence with
        -- Unit.has_node before linking.
        H.truthy(custom_mesh:find(
            'if type(tgt) == "string" and not Unit.has_node(target, tgt) then', 1, true))

        -- Log markers the in-game #597/#604 alias and Old Musket FX verification
        -- greps for survived the move byte-identical.
        local markers = {
            "[cwv:597] installed %d Greataxe inventory-package wire aliases",
            "[cwv:604] installed %d Crowbill inventory-package wire aliases",
            "[cwv old-musket fx] proxy spawned: path=%s linked_to=%s link_ok=%s vis_ok=%s",
            "[cwv old-musket] descriptor generation replayed to %d retained unit(s)",
        }
        for _, marker in ipairs(markers) do
            H.equal(count_plain(custom_mesh, marker), 1, "owner keeps marker " .. marker)
            H.equal(count_plain(entry, marker), 0, "entry no longer prints " .. marker)
        end
    end)

    H.test("CWV musket equip-surface owner holds the whole inventory-to-destroy path", function()
        local combined = require("cwv_source").combined(repo_root)

        -- PRODUCERS. Every definition the moved block owns lives exactly once, in
        -- the owner, and nowhere in the entry. A surviving entry copy would be a
        -- second, divergent bayonet ledger or a second career mutation.
        local producers = {
            "local _CWV_CROSS_SLOT_PREFIXES = {",
            "local function _is_cwv_musket_item(item)",
            "local function _cwv_collect_cross_slot_careers()",
            "local _MUSKET_BAYONET_UNIT_1P",
            "local _MUSKET_BAYONET_UNIT_3P",
            "local _MUSKET_BAYONET_DATA_KEY = ",
            'local _musket_bayonet_pairs = setmetatable({}, { __mode = "k" })',
            "local function _force_load_musket_bayonet_units()",
            "local _MUSKET_MELEE_STATE_MACHINE = ",
            "local function _force_load_musket_melee_assets()",
            "local function _spawn_and_link_musket_bayonet(",
            "local function _attach_musket_bayonets(",
            "local function _detach_musket_bayonet(",
            "local function _sync_all_bayonets_visibility(",
            "local function _item_backend_id(item_data)",
        }
        for _, marker in ipairs(producers) do
            H.equal(count_plain(equip_surface, marker), 1, "owner defines " .. marker)
            H.equal(count_plain(entry, marker), 0, "entry no longer defines " .. marker)
        end

        -- HOOK CARDINALITY. VMF silently DROPS a duplicate registration on the
        -- same (Class, method), so a re-added entry copy would shadow this owner
        -- rather than chain with it. Each moved pair appears exactly once across
        -- the whole load chain, and never in the entry.
        local hooks = {
            'mod:hook("ItemGridUI", "_on_category_index_change"',
            'mod:hook("ItemGridUI", "_get_items_by_filter"',
            'mod:hook("BackendInterfaceItemPlayfab", "get_filtered_items"',
            'mod:hook_safe("WeaponSpreadExtension", "init"',
            'mod:hook("WeaponSpreadExtension", "update"',
            'mod:hook("GearUtils", "spawn_inventory_unit"',
            'mod:hook("SimpleInventoryExtension", "_wield_slot"',
            'mod:hook_safe("SimpleInventoryExtension", "show_first_person_inventory"',
            'mod:hook_safe("SimpleInventoryExtension", "show_third_person_inventory"',
            'mod:hook("GearUtils", "destroy_wielded"',
        }
        for _, hook in ipairs(hooks) do
            H.equal(count_plain(equip_surface, hook), 1, "owner registers " .. hook)
            H.equal(count_plain(entry, hook), 0, "entry no longer registers " .. hook)
            H.equal(count_plain(combined, hook), 1, "exactly one registration of " .. hook)
        end

        -- TWO-PHASE INSTALL. The block was INTERLEAVED: the recognizer, career
        -- override, spread guard and bayonet constants ran BEFORE the dual-weapon
        -- FP residency, the husk-residency owner load and the husk wield
        -- diagnostic; the spawn and wield hooks ran AFTER all three. So `install`
        -- returns the second half and the entry calls it back at the second
        -- former position. Both halves must exist, in that order, and the entry
        -- must load the owner exactly once -- a second dofile would build a
        -- SECOND bayonet ledger, because mod:dofile is not a singleton.
        H.truthy(equip_surface:find("local function install(mod, ctx)", 1, true))
        H.equal(count_plain(equip_surface, "local function install_spawn_surface()"), 1,
            "owner declares the phase-two closure")
        H.equal(count_plain(equip_surface, "return install_spawn_surface"), 1,
            "install hands the phase-two closure back to the entry")
        H.equal(count_plain(entry,
            'mod:dofile("scripts/mods/character_weapon_variants/_cwv_musket_equip_surface")(mod, {'), 1,
            "entry installs the musket equip-surface owner exactly once")
        H.equal(count_plain(entry, "_install_musket_spawn_surface()"), 1,
            "entry calls phase two exactly once")
        local phase_one = assert(entry:find("_cwv_musket_equip_surface\")(mod, {", 1, true),
            "phase-one load missing")
        local phase_two = assert(entry:find("_install_musket_spawn_surface()", phase_one, true),
            "phase-two call must come after the load")
        H.truthy(phase_one < phase_two)
		-- Phase two must still land AFTER the husk-residency owner load and the
		-- husk wield diagnostic. The installer itself must be published by the
		-- husk-path dofile before the entry calls it; clean VMF loads have no stale
		-- `_om` field to mask an early call.
		local residency = assert(entry:find("_cwv_husk_residency_owner\")(mod, {", 1, true))
		local husk_owner = assert(entry:find("_cwv_husk_path\")(mod, {", 1, true))
		local husk_diag = assert(entry:find("_om._install_husk_wield_hook(mod)", 1, true))
		H.truthy(phase_one < residency)
		H.truthy(residency < husk_owner)
		H.truthy(husk_owner < husk_diag)
		H.truthy(husk_diag < phase_two)

        -- PUBLICATIONS other files read back off `_om`. The relocated
        -- cwv_slot_extension_scoped regression check (#1148) calls the collector
        -- and reads the log-only flag through the namespace, never as a global.
        for _, publication in ipairs({
            "_om._collect_cross_slot_careers = _cwv_collect_cross_slot_careers",
            "_om._slot_extension_log_only = true",
            "_om._cwv_filter_slot_name = self._cwv_filter_slot_name",
        }) do
            H.equal(count_plain(equip_surface, publication), 1, "owner publishes " .. publication)
            H.equal(count_plain(entry, publication), 0, "entry no longer publishes " .. publication)
        end

        -- RESOURCE SAFETY. Three package leases travelled with the block -- both
        -- bayonet sword units and the polearm state machine -- across TWO literal
        -- `Managers.package:load` call sites, because the two bayonet units share
        -- one `_load(unit_path, ref)` helper. One file-level marker covers both;
        -- check_native_resource_safety collects markers per FILE. The token also
        -- has to occur under qa/, which this line satisfies:
        -- resource-safety: cwv1159-musket-equip-surface-force-load
        H.truthy(equip_surface:find(
            "resource-safety: cwv1159-musket-equip-surface-force-load", 1, true),
            "owner carries its native-resource evidence marker")
        H.equal(count_plain(entry, "resource-safety: cwv1159-musket-equip-surface-force-load"), 0,
            "entry must not claim the owner's resource-safety marker")
        H.equal(count_plain(equip_surface, "Managers.package:load("), 2,
            "the marker covers exactly the two known force-load call sites")
        for _, ref in ipairs({
            '_load(_MUSKET_BAYONET_UNIT_1P, "cwv_musket_bayonet_1p")',
            '_load(_MUSKET_BAYONET_UNIT_3P, "cwv_musket_bayonet_3p")',
            'Managers.package:load(_MUSKET_MELEE_STATE_MACHINE, "cwv_musket_melee_sm", nil, true, true)',
        }) do
            H.equal(count_plain(equip_surface, ref), 1, "owner holds lease " .. ref)
        end
        H.equal(count_plain(equip_surface, "Managers.package:unload("), 0,
            "all three leases are held for the mod's lifetime, never released")
        -- The spawn helper fails CLOSED rather than loading on demand: a bayonet
        -- that is not resident is skipped for this equip, never force-loaded from
        -- inside the spawn path.
        H.truthy(equip_surface:find(
            "if not (Managers and Managers.package and Managers.package:has_loaded(bayonet_unit_path, package_ref)) then",
            1, true), "bayonet spawn is residency-gated")

        -- BOUNDARY vs the 13 sibling owners. This owner covers the equip path, so
        -- it must not absorb another owner's job: no item registration, no
        -- template construction, no command / network / regression surface, no
        -- husk helper DEFINITIONS (it only dispatches to them), and no javelin
        -- template or thrown-wire work (the #424 availability gate call it
        -- inherited is a one-line dispatch into _cwv_javelin_gate, not the gate).
        for _, forbidden in ipairs({
            "local function _build_entry",
            "_om._husk_rekey_units = function",
            "_om._husk_adapter_pre = function",
            "_force_load_husk_override_units",
            "mod:command",
            "mod:network_register",
            "_rt_register",
            "Weapons.javelin_template",
            "NetworkLookup.damage_profiles",
            "mod:hook(BackendUtils",
            'mod:hook("BackendUtils"',
        }) do
            H.equal(count_plain(equip_surface, forbidden), 0,
                "musket equip-surface owner must not contain " .. forbidden)
        end

        -- ...with ONE deliberate exception: `mod.on_all_mods_loaded`. The career
        -- slot_melee mutation has always re-run there because CareerSettings can
        -- still be partial at load time, and it must keep assigning BEFORE the
        -- husk-residency owner, which CHAINS whatever handler is installed at its
        -- own position. Phase one runs above that load, so the chain is intact.
        H.equal(count_plain(equip_surface, "function mod.on_all_mods_loaded()"), 1,
            "owner keeps the career re-extension handler")
        H.equal(count_plain(entry, "function mod.on_all_mods_loaded()"), 0,
            "entry no longer assigns on_all_mods_loaded")
        H.equal(count_plain(combined, "function mod.on_all_mods_loaded()"), 2,
            "exactly two handlers mod-wide: this assignment and the residency chain")
        H.truthy(read("_cwv_husk_residency_owner.lua"):find(
            "if previous_on_all_mods_loaded then previous_on_all_mods_loaded() end", 1, true),
            "the residency owner still chains the handler assigned above it")

        -- LOG MARKERS the in-game greps rely on survived the move byte-identical.
        local markers = {
            "[cwv slot] extended slot_melee with 'ranged' on %d careers (scoped to cross_slot variants; %d non-allowed careers reverted)",
            "[cwv melee-grid filter] kept=%d  dropped_ranged=%d  drop_samples=[%s]",
            "[cwv musket-bayonet] attach: 3p=%s 1p=%s (skipped: 3p=%s 1p=%s) total_pairs=%d",
            "[cwv musket-bayonet] sync: orphans=%d shown=%d hidden=%d",
            "[cwv musket-bayonet] pruned %d orphan(s) before new attach",
            "[cwv:935] preserved combined equipment category slot=%s",
            "[cwv:424] hid %d Tuskgor Javelin row(s): peer capability is %s",
        }
        for _, marker in ipairs(markers) do
            H.equal(count_plain(equip_surface, marker), 1, "owner keeps marker " .. marker)
            H.equal(count_plain(entry, marker), 0, "entry no longer prints " .. marker)
        end
    end)
end
