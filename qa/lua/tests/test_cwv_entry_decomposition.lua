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
    local lifecycle = read("_cwv_commands_lifecycle.lua")
    local identity = read("_cwv_regression_identity.lua")
    local render = read("_cwv_regression_render.lua")

    H.test("CWV entry remains below its frozen line baseline", function()
        local lines = 0
        for _ in entry:gmatch("[^\r\n]+") do lines = lines + 1 end
        H.truthy(lines <= 11617, "entry line count exceeded frozen 11617-line baseline")
    end)

    H.test("CWV decomposition modules install exactly once and in lifecycle order", function()
        local modules = {
            "_cwv_variant_catalog",
            "_cwv_cross_access",
            "_cwv_commands_lifecycle",
            "_cwv_regression_identity",
            "_cwv_regression_render",
        }
        for _, module_name in ipairs(modules) do
            H.equal(count_plain(entry, module_name), 1, module_name .. " load count")
        end

        local cross_at = assert(entry:find("_cwv_cross_access", 1, true))
        local lifecycle_at = assert(entry:find("_cwv_commands_lifecycle", 1, true))
        local identity_at = assert(entry:find("_cwv_regression_identity", 1, true))
        local render_at = assert(entry:find("_cwv_regression_render", 1, true))
        H.truthy(cross_at < lifecycle_at)
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
        H.equal(#names, 68)
        H.equal(names[1], "cwv_variant_flag_present")
        H.equal(names[32], "cwv_husk_transform_coverage")
        H.equal(names[33], "cwv_unit_bearing_variants_registered")
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
end
