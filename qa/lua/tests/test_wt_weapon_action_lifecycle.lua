return function(H, repo_root)
    local context = dofile(repo_root
        .. "/weapon_tweaker_dev/scripts/mods/weapon_tweaker_dev/_wt_effective_action_context.lua")
    local anim_state = dofile(repo_root
        .. "/weapon_tweaker_dev/scripts/mods/weapon_tweaker_dev/_wt_anim_state_policy.lua")

    H.test("WT #112 remap cache identity changes with receiver career", function()
        local mercenary = anim_state.remap_identity(
            "two_handed_billhooks_template", "wh_2h_billhook", "es_mercenary")
        local bounty = anim_state.remap_identity(
            "two_handed_billhooks_template", "wh_2h_billhook", "wh_bountyhunter")
        H.truthy(mercenary ~= bounty)
        H.equal(anim_state.remap_identity(nil, nil, "es_mercenary"), nil)
    end)

    H.test("WT #661 exact provider identity outranks inherited vanilla key", function()
        local canonical = {
            template = "cwv_greataxe_template",
            can_wield = { "wh_bountyhunter" },
        }
        local vanilla = { template = "two_handed_axes_template_1" }
        local effective = { actions = {} }
        local resolved, reason = context.resolve({
            id = "uuid",
            item_data = {
                key = "dr_2h_axe",
                backend_id = "uuid",
                data = { cim_acquisition_key = "cwv_es_greataxe" },
            },
        }, "wh_bountyhunter", {
            identity_resolvers = {
                function(_, item_data)
                    return item_data.data.cim_acquisition_key
                end,
            },
            item_master_list = {
                dr_2h_axe = vanilla,
                cwv_es_greataxe = canonical,
            },
            get_item_template = function() return effective end,
        })
        H.equal(reason, "ok")
        H.equal(resolved.item_key, "cwv_es_greataxe")
        H.equal(resolved.identity_source, "provider")
        H.equal(resolved.item, canonical)
        H.equal(resolved.template, effective)
        H.equal(context.is_managed(resolved, {}), true)
    end)

    H.test("WT #661 unknown providers fail open without guessing ownership", function()
        local resolved, reason = context.resolve({
            id = "pusfume-owned-instance",
            item_data = { backend_id = "pusfume-owned-instance" },
        }, "es_mercenary", {
            identity_resolvers = {},
            item_master_list = {},
            get_item_template = function() return { actions = {} } end,
        })
        H.equal(resolved, nil)
        H.equal(reason, "canonical_item_unresolved")
    end)

    H.test("WT #661 direct Pusfume items remain outside WT ownership", function()
        local resolved, reason = context.resolve({
            item_data = {
                key = "pusfume_versus_weapon",
                backend_id = "pusfume-owned-instance",
            },
        }, "es_mercenary", {
            identity_resolvers = {},
            item_master_list = {
                pusfume_versus_weapon = { template = "pusfume_template" },
            },
            get_item_template = function() return { actions = {} } end,
        })
        H.equal(reason, "ok")
        H.equal(resolved.identity_source, "direct")
        H.equal(context.is_managed(resolved, {
            es_mercenary = { "dr_2h_axe" },
        }), false)
    end)

    H.test("WT #661 direct WT ports require exact receiver declaration", function()
        local resolved, reason = context.resolve({
            item_data = { key = "dr_2h_axe", backend_id = "native-instance" },
        }, "es_mercenary", {
            identity_resolvers = {},
            item_master_list = {
                dr_2h_axe = { template = "two_handed_axes_template_1" },
            },
            get_item_template = function() return { actions = {} } end,
        })
        H.equal(reason, "ok")
        H.equal(resolved.identity_source, "direct")
        H.equal(context.is_managed(resolved, {
            es_mercenary = { "dr_2h_axe" },
        }), true)
        H.equal(context.is_managed(resolved, {
            wh_bountyhunter = { "dr_2h_axe" },
        }), false)
    end)

    H.test("WT #661 lifecycle owns the only local wield-slot hook", function()
        local function read(relative)
            local file = assert(io.open(repo_root .. "/" .. relative, "rb"))
            local source = file:read("*a")
            file:close()
            return source
        end
        local lifecycle = read("weapon_tweaker_dev/scripts/mods/weapon_tweaker_dev/_wt_weapon_action_lifecycle.lua")
        local diagnostics = read("weapon_tweaker_dev/scripts/mods/weapon_tweaker_dev/_wt_diagnostics.lua")
        local entry = read("weapon_tweaker_dev/scripts/mods/weapon_tweaker_dev/weapon_tweaker_dev.lua")
        H.truthy(lifecycle:find('mod:hook("SimpleInventoryExtension", "_wield_slot"', 1, true))
        H.truthy(lifecycle:find("pcall(reconcile, self, slot_data)", 1, true))
        H.truthy(lifecycle:find("return func", 1, true))
        H.truthy(lifecycle:find("pcall(reconcile, self, slot_data)", 1, true)
            < lifecycle:find("return func", 1, true))
        H.equal(lifecycle:find("local result = func", 1, true), nil)
        local _, engine_calls = lifecycle:gsub("func%(", "")
        H.equal(engine_calls, 1)
        H.equal(diagnostics:find('hook_safe("SimpleInventoryExtension", "_wield_slot"', 1, true), nil)
        H.truthy(entry:find("_wt_weapon_action_lifecycle", 1, true))
    end)

    H.test("CWV #661 crowbill declares both effective style templates", function()
        local file = assert(io.open(repo_root
            .. "/character_weapon_variants/scripts/mods/character_weapon_variants/_cwv_variant_catalog.lua", "rb"))
        local source = file:read("*a")
        file:close()
        local first = assert(source:find('item_key        = "cwv_es_imperial_crowbill"', 1, true))
        local last = assert(source:find('item_key        = "cwv_dr_dawi_crowbill"', first, true))
        local imperial = source:sub(first, last - 1)
        H.truthy(imperial:find("effective_templates", 1, true))
        H.truthy(imperial:find("PICK_TEMPLATE_KEY", 1, true))
        H.truthy(imperial:find("HAMMER_TEMPLATE_KEY", 1, true))
    end)

    H.test("CWV #661 prepares and installs actions on both crowbill styles", function()
        local integration = dofile(repo_root
            .. "/tools/shared_lib/_lib_career_weapon_actions.lua")
        local effective = dofile(repo_root
            .. "/tools/shared_lib/_lib_effective_weapon_templates.lua")
        local cwv = dofile(repo_root
            .. "/character_weapon_variants/scripts/mods/character_weapon_variants/_cwv_career_weapon_actions.lua")
        local canonical = { kind = "career_wh_2" }
        local source = { actions = { action_career_wh_2 = canonical } }
        local pick = { actions = { action_career_wh_2 = { kind = "copied" } } }
        local hammer = { actions = { action_career_wh_2 = { kind = "copied" } } }
        local definition = {
            item_key = "cwv_es_imperial_crowbill",
            base_weapon = "bw_1h_crowbill",
            effective_templates = {
                { name = "cwv_crowbill_pick_template",
                    source_template = "one_handed_crowbill" },
                { name = "cwv_crowbill_hammer_template",
                    source_template = "one_handed_crowbill" },
            },
        }
        local items = {
            bw_1h_crowbill = { template = "one_handed_crowbill" },
            cwv_es_imperial_crowbill = {
                template = "one_handed_crowbill",
                can_wield = { "wh_bountyhunter" },
            },
        }
        local report = cwv.install({ { def = definition } }, items, {
            one_handed_crowbill = source,
            cwv_crowbill_pick_template = pick,
            cwv_crowbill_hammer_template = hammer,
        }, {
            wh_bountyhunter = {
                activated_ability = { { action_name = "action_career_wh_2" } },
            },
        }, { action_career_wh_2 = canonical }, integration, effective,
            "character_weapon_variants")
        H.equal(report.ok, true)
        H.equal(pick.actions.action_career_wh_2, canonical)
        H.equal(hammer.actions.action_career_wh_2, canonical)
    end)
end
