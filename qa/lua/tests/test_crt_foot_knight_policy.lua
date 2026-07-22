return function(H, repo_root)
    local path = repo_root
        .. "/career_tweaker/scripts/mods/career_tweaker/_crt_foot_knight_policy.lua"
    local Policy = assert(loadfile(path))()

    H.test("CRT #619 shield capability includes cloned shield templates", function()
        H.equal(Policy.is_shield_type("AXE_1H_SHIELD"), true)
        H.equal(Policy.is_shield_type("MACE_1H_SHIELD"), true)
        H.equal(Policy.is_shield_type("SPEAR_1H_SHIELD"), true)
        H.equal(Policy.is_shield_type("FLAIL_1H", "one_handed_flail_shield_template"), true)
        H.equal(Policy.is_shield_type("MACE_1H", "cwv_dawi_mace_shield_template"), true)
        H.equal(Policy.is_shield_type("AXE_1H"), false)
    end)

    H.test("CRT #619 great capability excludes polearms", function()
        H.equal(Policy.is_non_polearm_great_type("AXE_2H"), true)
        H.equal(Policy.is_non_polearm_great_type("MACE_2H"), true)
        H.equal(Policy.is_non_polearm_great_type("SWORD_2H"), true)
        H.equal(Policy.is_non_polearm_great_type("PICK_2H"), true)
        H.equal(Policy.is_non_polearm_great_type("MACE_2H", "staff_scythe"), false)
        H.equal(Policy.is_non_polearm_great_type("AXE_2H", "two_handed_glaive_template"), false)
        H.equal(Policy.is_non_polearm_great_type("SPEAR_2H"), false)
        H.equal(Policy.is_non_polearm_great_type("HALBERD_2H"), false)
    end)

    H.test("CRT #619 category damage composes and caps allies", function()
        H.equal(Policy.enemy_multiplier(true, false, 0, { boss = true, armor_category = 3 }), 1.3)
        H.equal(Policy.enemy_multiplier(true, false, 0, { armor_category = 5 }), 1.3)
        H.equal(Policy.enemy_multiplier(false, true, 2, { armor_category = 2 }), 1.2)
        H.equal(Policy.enemy_multiplier(false, true, 8, { armor_category = 6 }), 1.3)
        H.equal(Policy.enemy_multiplier(false, true, 3, { armor_category = 5 }), 1)
        H.truthy(math.abs(Policy.enemy_multiplier(true, true, 3,
            { boss = true, armor_category = 3 }) - 1.69) < 0.000001)
    end)

    H.test("CRT #619 secondary melee owns only its inserted slot member", function()
        local enabled, owns = Policy.plan_secondary_slot({ "ranged" }, true, false)
        H.deep_equal(enabled, { "melee", "ranged" })
        H.equal(owns, true)

        local repeated
        repeated, owns = Policy.plan_secondary_slot(enabled, true, owns)
        H.deep_equal(repeated, { "melee", "ranged" })
        H.equal(owns, true)

        local disabled
        disabled, owns = Policy.plan_secondary_slot(repeated, false, owns)
        H.deep_equal(disabled, { "ranged" })
        H.equal(owns, false)

        local shared
        shared, owns = Policy.plan_secondary_slot({ "ranged", "melee" }, false, false)
        H.deep_equal(shared, { "ranged", "melee" })
        H.equal(owns, false)

        local repaired
        repaired, owns = Policy.plan_secondary_slot({ "melee" }, true, false)
        H.deep_equal(repaired, { "melee", "ranged" })
        H.equal(owns, false)
    end)

    H.test("CRT #935 finds sparse and detached inventory slot carriers", function()
        local backend_types = { "ranged" }
        local sparse_types = { "ranged" }
        local menu_types = { "ranged" }
        local backend = {
            name = "es_knight",
            item_slot_types_by_slot_name = { slot_ranged = backend_types },
        }
        local profiles = {
            [5] = {
                careers = {
                    [1] = { name = "es_mercenary" },
                    [3] = {
                        name = "es_knight",
                        item_slot_types_by_slot_name = { slot_ranged = sparse_types },
                    },
                },
            },
        }
        local menu_career = {
            name = "es_knight",
            item_slot_types_by_slot_name = { slot_ranged = menu_types },
        }

        local carriers = Policy.secondary_slot_carriers(
            backend, profiles, menu_career, "controller.career")
        H.equal(#carriers, 3)
        H.equal(carriers[1].slot_types, backend_types)
        H.equal(carriers[2].slot_types, sparse_types)
        H.equal(carriers[3].slot_types, menu_types)
        H.equal(carriers[3].label, "controller.career")
        for _, carrier in ipairs(carriers) do
            local planned = Policy.plan_secondary_slot(carrier.slot_types, true, false)
            H.deep_equal(planned, { "melee", "ranged" })
        end

        -- A stock alias is mutated only once even when reachable through all
        -- three discovery paths.
        profiles[5].careers[3] = backend
        local deduped = Policy.secondary_slot_carriers(backend, profiles, backend)
        H.equal(#deduped, 1)

        local foreign = Policy.secondary_slot_carriers(backend, {}, {
            name = "es_huntsman",
            item_slot_types_by_slot_name = { slot_ranged = { "ranged" } },
        })
        H.equal(#foreign, 1)
    end)

    H.test("CRT #619 talent descriptions compose live toggles and restore vanilla", function()
        local settings = {}
        local rock_key = Policy.ROCK_DESCRIPTION_KEY
        local teamwork_key = Policy.TEAMWORK_DESCRIPTION_KEY

        -- All-off is the exact vanilla restoration contract: the production
        -- Localize hook delegates when the pure resolver returns nil.
        H.equal(Policy.talent_description(rock_key, settings), nil)
        H.equal(Policy.talent_description(teamwork_key, settings), nil)

        settings.rework_es_knight_protective_presence_10m_rock_20m = true
        H.equal(Policy.talent_description(rock_key, settings),
            "Increases the range of Protective Presence to 20 meters.")

        -- Simulate a hot toggle while the menu is open: the next lookup must
        -- compose both mechanics without retaining the previous static text.
        settings.rework_es_knight_rock_shield_offense = true
        local composed = Policy.talent_description(rock_key, settings)
        H.truthy(composed:find("20 meters", 1, true))
        H.truthy(composed:find("wielding a shield", 1, true))
        H.truthy(composed:find("30%% more melee damage", 1, true))

        settings.rework_es_knight_protective_presence_10m_rock_20m = false
        local shield_only = Policy.talent_description(rock_key, settings)
        H.truthy(shield_only:find("10 meters", 1, true))
        H.equal(shield_only:find("20 meters", 1, true), nil)

        settings.rework_es_knight_teamwork_great_weapon_offense = true
        local teamwork = Policy.talent_description(teamwork_key, settings)
        H.truthy(teamwork:find("within 10 meters", 1, true))
        H.truthy(teamwork:find("non%-polearm great weapon"))
        H.truthy(teamwork:find("Armored enemies and Monsters", 1, true))

        -- Simulate closing/reopening after every toggle has returned off.
        settings.rework_es_knight_rock_shield_offense = false
        settings.rework_es_knight_teamwork_great_weapon_offense = false
        H.equal(Policy.talent_description(rock_key, settings), nil)
        H.equal(Policy.talent_description(teamwork_key, settings), nil)
    end)

    H.test("CRT #619 Final March distinguishes dead from disabled allies", function()
        H.equal(Policy.all_other_allies_dead({}), false)
        H.equal(Policy.all_other_allies_dead({ true, true, true }), true)
        H.equal(Policy.all_other_allies_dead({ true, false, true }), false)
    end)

    H.test("CRT #663 two Foot Knight aura sources share one stable result", function()
        local record = { sources = {}, claim_count = 0 }

        local count, action, changed = Policy.set_aura_claim(
            record, "foot_knight_a", "unit_a", true)
        H.equal(count, 1)
        H.equal(action, "add")
        H.equal(changed, true)

        count, action, changed = Policy.set_aura_claim(
            record, "foot_knight_b", "unit_b", true)
        H.equal(count, 2)
        H.equal(action, nil)
        H.equal(changed, true)

        count, action, changed = Policy.set_aura_claim(
            record, "foot_knight_a", nil, false)
        H.equal(count, 1)
        H.equal(action, nil)
        H.equal(changed, true)

        count, action, changed = Policy.set_aura_claim(
            record, "foot_knight_b", "unit_b", true)
        H.equal(count, 1)
        H.equal(action, nil)
        H.equal(changed, false)

        count, action, changed = Policy.set_aura_claim(
            record, "foot_knight_b", nil, false)
        H.equal(count, 0)
        H.equal(action, "remove")
        H.equal(changed, true)
    end)

    H.test("CRT #663 production owns every source-blind Foot Knight aura driver", function()
        local foot_path = repo_root
            .. "/career_tweaker/scripts/mods/career_tweaker/_crt_foot_knight.lua"
        local foot_file = assert(io.open(foot_path, "rb"))
        local source = foot_file:read("*a")
        foot_file:close()

        for _, template_name in ipairs({
            "markus_knight_passive",
            "markus_knight_improved_passive_defence_aura",
            "markus_knight_passive_block_cost_aura",
            "markus_knight_passive_range",
            "markus_knight_guard_defence",
            "markus_knight_guard",
        }) do
            H.truthy(source:find('{ template = "' .. template_name .. '"', 1, true),
                "missing source-owned driver " .. template_name)
        end
        H.truthy(source:find("policy.set_aura_claim", 1, true))
        H.truthy(source:find("server_buff_id", 1, true))
        H.equal(source:find('mod:hook(BuffSystem', 1, true), nil)
        H.equal(source:find('network:register', 1, true), nil)
    end)

    H.test("CRT #619 production composes the singleton damage hook", function()
        local path = repo_root
            .. "/career_tweaker/scripts/mods/career_tweaker/career_tweaker_armor_overcharge.lua"
        local file = assert(io.open(path, "rb"))
        local source = file:read("*a")
        file:close()
        local count = 0
        for _ in source:gmatch('mod:hook%(DamageUtils, "apply_buffs_to_damage"') do
            count = count + 1
        end
        H.equal(count, 1)
        H.truthy(source:find("fk.outgoing_damage_multiplier", 1, true))

        local foot_path = repo_root
            .. "/career_tweaker/scripts/mods/career_tweaker/_crt_foot_knight.lua"
        local foot_file = assert(io.open(foot_path, "rb"))
        local foot_source = foot_file:read("*a")
        foot_file:close()
        H.truthy(foot_source:find('BUFF_ROCK_DODGE', 1, true))
        H.truthy(foot_source:find('multiplier = 0.90', 1, true))
        H.truthy(foot_source:find('BUFF_TEAMWORK_DR_CANCEL', 1, true))
        H.truthy(foot_source:find('multiplier = 0.10', 1, true))
        H.truthy(foot_source:find('markus_knight_passive_damage_reduction', 1, true))
        H.truthy(foot_source:find('CareerSettings and CareerSettings.es_knight', 1, true))
        H.truthy(foot_source:find('policy.secondary_slot_carriers', 1, true))
        H.truthy(foot_source:find('_install_inventory_category_hook("HeroWindowLoadoutInventory",', 1, true))
        H.truthy(foot_source:find('_install_inventory_category_hook("HeroWindowLoadoutInventoryConsole",', 1, true))
        H.truthy(foot_source:find('[crt:935] menu-slot', 1, true))
        H.truthy(foot_source:find('icon = BUFF_ICONS[BUFF_UNINTERRUPTIBLE]', 1, true))
        H.truthy(foot_source:find('icon = BUFF_ICONS[BUFF_ROCK_DODGE]', 1, true))
        H.truthy(foot_source:find('icon = BUFF_ICONS[BUFF_ROCK_POWER]', 1, true))
        H.truthy(foot_source:find('icon = BUFF_ICONS[BUFF_TEAMWORK_POWER]', 1, true))
        H.truthy(foot_source:find('icon = BUFF_ICONS[BUFF_FINAL_MARCH]', 1, true))
        H.truthy(foot_source:find('if enabled and not id then', 1, true))
        H.truthy(foot_source:find('elseif not enabled and id then', 1, true))
        H.truthy(foot_source:find('while #ids > wanted do', 1, true))
        H.truthy(foot_source:find('while #ids < wanted do', 1, true))
        -- The internal +10% DR cancellation is bookkeeping, not a player
        -- effect; it must never consume a buff-bar slot.
        local cancel_start = assert(foot_source:find('_register_local_template(BUFF_TEAMWORK_DR_CANCEL', 1, true))
        local cancel_end = assert(foot_source:find('_register_local_template(BUFF_TEAMWORK_POWER', cancel_start, true))
        H.equal(foot_source:sub(cancel_start, cancel_end):find('icon =', 1, true), nil)
        -- Final March has two stat sub-buffs but deliberately one HUD icon.
        local final_start = assert(foot_source:find('_register_local_template(BUFF_FINAL_MARCH', cancel_end, true))
        local final_end = assert(foot_source:find('local function _is_foot_knight', final_start, true))
        local final_icons = 0
        for _ in foot_source:sub(final_start, final_end):gmatch('icon =') do
            final_icons = final_icons + 1
        end
        H.equal(final_icons, 1)

        local diagnostics_path = repo_root
            .. "/career_tweaker/scripts/mods/career_tweaker/_crt_diagnostics.lua"
        local diagnostics_file = assert(io.open(diagnostics_path, "rb"))
        local diagnostics_source = diagnostics_file:read("*a")
        diagnostics_file:close()
        H.truthy(diagnostics_source:find("[crt:699] icon active=true", 1, true))
        H.truthy(diagnostics_source:find("UIAtlasHelper.has_atlas_settings_by_texture_name", 1, true))
        H.truthy(diagnostics_source:find('_buff_name_to_widget[active_template.name]', 1, true))
        H.truthy(diagnostics_source:find('#hud._unused_buff_widgets', 1, true))
        H.truthy(diagnostics_source:find('hud_capacity=%d', 1, true))
        H.truthy(diagnostics_source:find('_crt_fk_icon_hidebuffs_disposition', 1, true))
        H.truthy(diagnostics_source:find('_crt_fk_icon_probe_accumulator < 0.25', 1, true))
        H.truthy(diagnostics_source:find('_CRT_FK_ICON_LOG_CAP = 64', 1, true))
        H.truthy(diagnostics_source:find('_crt_fk_icon_log_count >= _CRT_FK_ICON_LOG_CAP', 1, true))
        H.truthy(diagnostics_source:find('hud._is_spectator and hud._spectated_player_unit', 1, true))
        H.truthy(diagnostics_source:find('subject=%s', 1, true))

        local balance_path = repo_root
            .. "/career_tweaker/scripts/mods/career_tweaker/career_tweaker_balance.lua"
        local balance_file = assert(io.open(balance_path, "rb"))
        local balance_source = balance_file:read("*a")
        balance_file:close()
        local hook_path = repo_root
            .. "/career_tweaker/scripts/mods/career_tweaker/_career_tweaker_balance_hooks.lua"
        local hook_file = assert(io.open(hook_path, "rb"))
        local hook_source = hook_file:read("*a")
        hook_file:close()
        H.truthy(balance_source:find('{ buff = "markus_knight_passive",                 field = "range", value = 10 }', 1, true))
        H.truthy(balance_source:find('{ buff = "markus_knight_passive_block_cost_aura", field = "range", value = 20 }', 1, true))
        H.truthy(balance_source:find('{ buff = "markus_knight_passive_range",           field = "range", value = 20 }', 1, true))
        H.truthy(hook_source:find('["markus_knight_passive_block_cost_aura_desc_2"]', 1, true))
        H.truthy(hook_source:find('["markus_knight_damage_taken_ally_proximity_desc_2"]', 1, true))
        H.equal(hook_source:find('["markus_knight_passive_block_cost_aura_desc"]', 1, true), nil)
    end)

    local vanilla_path = repo_root
        .. "/../Vermintide-2-Source-Code/scripts/managers/talents/talent_settings_markus.lua"
    local vanilla_file = io.open(vanilla_path, "rb")
    local vanilla_source
    if vanilla_file then
        vanilla_source = vanilla_file:read("*a")
        vanilla_file:close()
    end
    local atlas_path = repo_root
        .. "/../Vermintide-2-Source-Code/scripts/ui/atlas_settings/gui_icons_atlas.lua"
    local atlas_file = io.open(atlas_path, "rb")
    local atlas_source
    if atlas_file then
        atlas_source = atlas_file:read("*a")
        atlas_file:close()
    end
    H.test_if(vanilla_source ~= nil and atlas_source ~= nil,
        "CRT #619 buff icons are resident vanilla Foot Knight atlas keys", function()
            for _, icon in ipairs({
                "markus_knight_ability_invulnerability",
                "markus_knight_passive_block_cost_aura",
                "markus_knight_damage_taken_ally_proximity",
                "markus_knight_movement_speed_on_incapacitated_allies",
            }) do
                H.truthy(vanilla_source:find('icon = "' .. icon .. '"', 1, true), icon)
                H.truthy(atlas_source:find(icon .. ' = {', 1, true), icon)
            end
        end)
end
