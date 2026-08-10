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
    local lifecycle = read("_cwv_commands_lifecycle.lua")
    local identity = read("_cwv_regression_identity.lua")
    local render = read("_cwv_regression_render.lua")

    H.test("CWV entry remains below its frozen line baseline", function()
        local lines = 0
        for _ in entry:gmatch("[^\r\n]+") do lines = lines + 1 end
        -- 5606 = 2026-08-10 #1159 keep/menu preview-surface owner extraction,
        -- measured after the item-registration slice that preceded it. This
        -- ceiling only ratchets DOWN as later CWV decomposition slices land.
        H.truthy(lines <= 5606, "entry line count exceeded frozen 5606-line baseline")
    end)

    H.test("CWV decomposition modules install exactly once and in lifecycle order", function()
        local modules = {
            "_cwv_variant_catalog",
            "_cwv_cross_access",
            "_cwv_core_templates",
            "_cwv_skin_registry",
            "_cwv_illusion_families",
            "_cwv_husk_residency_owner",
            "_cwv_item_registration_owner",
            "_cwv_husk_path",
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
        local registration_at = assert(entry:find("_cwv_item_registration_owner", 1, true))
        local husk_at = assert(entry:find("_cwv_husk_path", 1, true))
        local menu_preview_at = assert(entry:find("_cwv_menu_preview_owner", 1, true))
        local lifecycle_at = assert(entry:find("_cwv_commands_lifecycle", 1, true))
        local identity_at = assert(entry:find("_cwv_regression_identity", 1, true))
        local render_at = assert(entry:find("_cwv_regression_render", 1, true))
        H.truthy(cross_at < core_at)
        -- #1159: the husk-residency owner force-loads at boot, long before the
        -- skin/illusion registries and the husk-path display helpers exist.
        H.truthy(core_at < residency_at)
        H.truthy(residency_at < skin_at)
        H.truthy(core_at < skin_at)
        H.truthy(skin_at < families_at)
        -- #1159: the item-registration owner loads after the skin/illusion
        -- registrars (its #567 rebuild consumes their pools) and before the
        -- husk-path display helpers.
        H.truthy(families_at < registration_at)
        H.truthy(registration_at < husk_at)
        H.truthy(families_at < husk_at)
        -- #1159: the keep/menu preview-surface owner registers the last render
        -- hooks in the chain. It must load after the husk display helpers and
        -- before the commands/lifecycle owner, which the entry deliberately
        -- installs only once every gameplay and render hook is registered.
        H.truthy(husk_at < menu_preview_at)
        H.truthy(menu_preview_at < lifecycle_at)
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
        H.equal(#names, 81)
        H.equal(names[1], "cwv_variant_flag_present")
        H.equal(names[37], "cwv_husk_transform_coverage")
        H.equal(names[38], "cwv_husk_stale_unit_and_postcondition")
        -- issue 399 appended the husk ammo-adapter drive as the last identity
        -- check, so the identity/render boundary moved one slot right.
        H.equal(names[39], "issue399_outrider_husk_ammo_adapter")
        H.equal(names[40], "cwv_unit_bearing_variants_registered")
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
        -- husk wield diagnostic stays in the entry because it dispatches the
        -- exact-identity / combat-style / fade channels, not residency.
        H.equal(count_plain(husk_residency, "_om._husk_adapter_pre"), 0,
            "residency owner must not reach into husk-path spawn adapters")
        H.equal(count_plain(husk_residency, "_om._husk_rekey_units"), 0,
            "residency owner must not reach into husk-path mesh re-key")
        H.equal(count_plain(husk, "_force_load_husk_override_units"), 0,
            "husk-path module must not duplicate the residency pass")
        H.equal(count_plain(husk_residency, 'mod:hook("SimpleHuskInventoryExtension", "_wield_slot"'), 0,
            "husk wield diagnostic stays in the entry")
        H.equal(count_plain(entry, 'mod:hook("SimpleHuskInventoryExtension", "_wield_slot"'), 1,
            "entry keeps exactly one husk _wield_slot hook")

        -- Hook cardinality: VMF silently drops a duplicate registration on the
        -- same (Class, method), so each husk-extension pair must appear once
        -- across the whole mod. start_weapon_fx now lives in this owner.
        local fade = read("_cwv_appearance_fade.lua")
        local combined = entry .. husk .. husk_residency .. fade
        H.equal(count_plain(combined, 'mod:hook("SimpleHuskInventoryExtension", "start_weapon_fx"'), 1)
        H.equal(count_plain(combined, 'mod:hook("SimpleHuskInventoryExtension", "_wield_slot"'), 1)
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
        H.equal(count_plain(registration, "return function("), 0,
            "owner must use a named install wrapper, not an anonymous chunk")
        local ctx_fields = {
            "om", "dbg", "dbg_alert", "variant_definitions", "custom_skin_keys",
            "career_weapon_actions", "cwv_career_weapon_actions", "career_action_owner",
        }
        for _, field in ipairs(ctx_fields) do
            H.equal(count_plain(registration, "local _" .. field .. " = ctx." .. field), 1,
                "owner localizes ctx." .. field)
        end
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

        -- BOUNDARY. The give command is command surface owned by
        -- _cwv_commands_lifecycle; the spawn descriptors are the #1158
        -- exact-appearance channel; `_find_def` is reached by both plus
        -- _cwv_husk_path. All three stay in the entry.
        local entry_only = {
            "local function _find_def(item_key)",
            "local function _give_variant(item_key)",
            "_om._give_refuses_skin_only = function(def)",
            "_om._resident_override_3p = function(base_unit)",
            "_om._cwv_resolve_spawn_descriptor = function(",
            "_om._cwv_preview_meshswap_apply = function(",
            "_om._cwv_browser_meshswap_apply = function(",
        }
        for _, marker in ipairs(entry_only) do
            H.equal(count_plain(entry, marker), 1, "entry keeps " .. marker)
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
        -- rather than chain with it. Each of the seven moved pairs must appear
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
        }
        for _, hook in ipairs(hooks) do
            H.equal(count_plain(menu_preview, hook), 1, "menu preview owner registers " .. hook)
            H.equal(count_plain(entry, hook), 0, "entry no longer registers " .. hook)
            H.equal(count_plain(combined, hook), 1, "exactly one registration of " .. hook)
        end

        -- Entry-local dependencies arrive as explicit context, same shape as the
        -- sibling owners. Every one of these ten is declared once at entry file
        -- scope above the load point and never rebound, so the by-value capture
        -- cannot go stale; the three maps are shared table references whose
        -- in-place population after this point still reaches the owner.
        H.truthy(menu_preview:find("local function install(mod, ctx)", 1, true))
        H.equal(count_plain(menu_preview, "return function("), 0,
            "owner must use a named install wrapper, not an anonymous chunk")
        local ctx_fields = {
            "om", "dbg", "dbg_alert", "resolve_field", "is_unit", "transform_unit",
            "apply_cwv_hand_transform", "transform_map", "skin_transform_map",
            "crowbill_transform_by_unit",
        }
        for _, field in ipairs(ctx_fields) do
            H.equal(count_plain(menu_preview, "local _" .. field .. " = ctx." .. field), 1,
                "owner localizes ctx." .. field)
            -- Presence, not count: several sibling owners are handed the same
            -- entry locals through their own ctx tables.
            H.truthy(entry:find(field .. " = _" .. field .. ",", 1, true),
                "entry injects ctx." .. field)
        end
        H.equal(count_plain(entry,
            'mod:dofile("scripts/mods/character_weapon_variants/_cwv_menu_preview_owner")(mod, {'), 1,
            "entry installs the menu preview owner exactly once")

        -- BOUNDARY. CWV has three presentation surfaces and this owner is only
        -- the MENU one. The WORLD/BOT equipment hook and its transform-miss
        -- evidence counters stay in the entry, as do the shared def resolvers
        -- both surfaces call. `_resolve_cwv_def` and the counters are named in
        -- the owner's header comment, so pin the CODE forms, not the names.
        local entry_only = {
            'mod:hook("GearUtils", "create_equipment"',
            "local function _resolve_cwv_def(item_data, skin, resolved_unit_name)",
            "local function _find_def(item_key)",
            "local def = _resolve_cwv_def(item_data, result.skin",
            "_crowbill_transform_miss_total = _crowbill_transform_miss_total + 1",
        }
        for _, marker in ipairs(entry_only) do
            H.equal(count_plain(entry, marker), 1, "entry keeps " .. marker)
            H.equal(count_plain(menu_preview, marker), 0,
                "menu preview owner must not absorb " .. marker)
        end

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
            "[cwv:617] Old Musket preview textures applied: item=%s mode=%s targets=%d applied=%d descriptor=true",
            "[cwv preview] _resolve_preview_def returned nil for item_name=%s (info bid=%s)",
            "[cwv preview hook] HeroPreviewer._spawn_item fired item_name=%s self=%s",
            "[cwv preview hook] MenuWorldPreviewer._spawn_item fired item_name=%s self=%s",
        }
        for _, marker in ipairs(markers) do
            H.equal(count_plain(menu_preview, marker), 1, "owner keeps marker " .. marker)
            H.equal(count_plain(entry, marker), 0, "entry no longer prints " .. marker)
        end
    end)
end
