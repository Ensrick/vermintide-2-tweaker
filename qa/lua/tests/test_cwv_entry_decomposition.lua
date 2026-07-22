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
    local husk = read("_cwv_husk_path.lua")
    local lifecycle = read("_cwv_commands_lifecycle.lua")
    local identity = read("_cwv_regression_identity.lua")
    local render = read("_cwv_regression_render.lua")

    H.test("CWV entry remains below its frozen line baseline", function()
        local lines = 0
        for _ in entry:gmatch("[^\r\n]+") do lines = lines + 1 end
        -- 11084 = 2026-07-18 OOP W5 husk-path extraction: the 740-line husk
        -- display/transform/ledger/postcondition `do...end` block moved verbatim
        -- to _cwv_husk_path.lua (was 11791). The ceiling only ratchets DOWN as
        -- the ct_dev/cwv decomposition (OOP W5) extracts modules.
        H.truthy(lines <= 11084, "entry line count exceeded frozen 11084-line baseline")
    end)

    H.test("CWV decomposition modules install exactly once and in lifecycle order", function()
        local modules = {
            "_cwv_variant_catalog",
            "_cwv_cross_access",
            "_cwv_husk_path",
            "_cwv_commands_lifecycle",
            "_cwv_regression_identity",
            "_cwv_regression_render",
        }
        for _, module_name in ipairs(modules) do
            H.equal(count_plain(entry, module_name), 1, module_name .. " load count")
        end

        local cross_at = assert(entry:find("_cwv_cross_access", 1, true))
        local husk_at = assert(entry:find("_cwv_husk_path", 1, true))
        local lifecycle_at = assert(entry:find("_cwv_commands_lifecycle", 1, true))
        local identity_at = assert(entry:find("_cwv_regression_identity", 1, true))
        local render_at = assert(entry:find("_cwv_regression_render", 1, true))
        H.truthy(cross_at < husk_at)
        H.truthy(husk_at < lifecycle_at)
        H.truthy(lifecycle_at < identity_at)
        H.truthy(identity_at < render_at)
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
        H.equal(#names, 76)
        H.equal(names[1], "cwv_variant_flag_present")
        H.equal(names[35], "cwv_husk_transform_coverage")
        H.equal(names[36], "cwv_husk_stale_unit_and_postcondition")
        H.equal(names[37], "cwv_unit_bearing_variants_registered")
        H.equal(names[#names], "issue567_skin_reverse_index_valid")
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
