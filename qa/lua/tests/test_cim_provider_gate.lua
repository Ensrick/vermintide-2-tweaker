-- Issue 682 (Athanor craft resolution died with `reason=nil` on the immutable
-- WOC relic) + issue 628 (registered provider gate every enumerator/restorer
-- routes through). Loads the contract fresh per assertion group so routed-
-- surface state never leaks between tests.
return function(H, repo_root)
    local root = repo_root
        .. "/crafting_in_modded_dev/scripts/mods/crafting_in_modded_dev/"

    local function load_contract()
        return assert(loadfile(root .. "_cim_synthetic_item_contract.lua"))()
    end

    local function read(name)
        local file = assert(io.open(root .. name, "rb"))
        local source = file:read("*a")
        file:close()
        return source
    end

    -- Every playable career class (the relic's can_wield census from the
    -- 2026-07-19 FS log evidence; dr_ranger + wh_bountyhunter are the two
    -- careers 682 captured failing).
    local CAREERS = {
        "es_mercenary", "es_huntsman", "es_knight", "es_questingknight",
        "dr_ironbreaker", "dr_ranger", "dr_slayer", "dr_engineer",
        "we_waywatcher", "we_maidenguard", "we_shade", "we_thornsister",
        "wh_zealot", "wh_bountyhunter", "wh_captain", "wh_priest",
        "bw_adept", "bw_scholar", "bw_unchained", "bw_necromancer",
    }

    local function vanilla_master(career)
        return {
            slot_type = "melee",
            can_wield = { career },
            template = "one_handed_swords_template_1",
            item_type = "rt_weapon",
            inventory_icon = "rt_icon",
        }
    end

    local function relic_master(career)
        return {
            woc_variant = true,
            woc_unique_relic = true,
            slot_type = "melee",
            can_wield = { career },
            template = "one_handed_swords_template_1",
            item_type = "woc_blightreaper",
            inventory_icon = "rt_icon",
        }
    end

    H.test("CIM #682 craft resolution is non-nil for every career class", function()
        local contract = load_contract()
        for _, career in ipairs(CAREERS) do
            local record, reason = contract.gate_record("mirror_injection",
                "rt-bid-" .. career, {
                    item_key = "rt_weapon",
                    properties = {},
                    traits = {},
                    power_level = 300,
                    rarity = "modded",
                    via_mirror = true,
                    career_name = career,
                }, vanilla_master(career))
            H.equal(reason, nil, career .. " craft rejected")
            H.truthy(record, career .. " record missing")
            -- The exact three fields the 682 FAIL log resolved as <nil>.
            H.equal(record.item_key, "rt_weapon", career .. " key")
            H.equal(record.slot_type, "melee", career .. " slot")
            H.equal(record.rarity, "modded", career .. " rarity")
        end
    end)

    H.test("CIM #682 relic rejection is classified for every career class", function()
        local contract = load_contract()
        for _, career in ipairs(CAREERS) do
            local record, reason = contract.gate_record("mirror_injection",
                "rt-bid-" .. career, {
                    item_key = "woc_blightreaper",
                    rarity = "modded",
                    career_name = career,
                }, relic_master(career))
            H.equal(record, nil, career .. " relic craft must reject")
            -- The confirmed 682 boundary logged `reason=nil` (and/or
            -- multi-return collapse). The gate must classify it.
            H.equal(reason, "provider:immutable_relic", career .. " reason")
        end
    end)

    H.test("CIM #682 every record-gate rejection carries a non-nil reason", function()
        local contract = load_contract()
        local cases = {
            { bid = nil, input = { item_key = "rt_weapon" }, master = nil,
              expected = "backend_id" },
            { bid = "", input = { item_key = "rt_weapon" }, master = nil,
              expected = "backend_id" },
            { bid = "rt-bid", input = "not-a-table", master = nil,
              expected = "record" },
            { bid = "rt-bid", input = {}, master = nil,
              expected = "item_key" },
            { bid = "rt-bid", input = { item_key = "woc_blightreaper" },
              master = relic_master("dr_ranger"),
              expected = "provider:immutable_relic" },
        }
        for i = 1, #cases do
            local case = cases[i]
            local record, reason = contract.gate_record("rt_check",
                case.bid, case.input, case.master)
            H.equal(record, nil, "case " .. i .. " must reject")
            H.equal(reason, case.expected, "case " .. i .. " reason")
        end
    end)

    H.test("CIM #628 item-gate accept/reject table", function()
        local contract = load_contract()

        -- Accept: ordinary vanilla row (stays vanilla-owned).
        local ok, problems, provider = contract.gate_item("rt_check",
            "es_1h_sword", { slot_type = "melee", rarity = "plentiful" })
        H.equal(ok, true)
        H.equal(provider, "vanilla")
        H.deep_equal(problems, {})

        -- Accept: complete CWV definition.
        local cwv = vanilla_master("dr_ranger")
        cwv.cwv_variant = true
        ok, problems, provider = contract.gate_item("rt_check", "cwv_dr_dawi_mace", cwv)
        H.equal(ok, true, "complete cwv row rejected: " .. table.concat(problems, ","))
        H.equal(provider, "cwv")

        -- Reject: every WOC row. WOC owns one immutable trophy instance per
		-- weapon; CIM must never turn a provider definition into another copy.
        local woc = vanilla_master("es_mercenary")
        woc.woc_variant = true
        ok, problems, provider = contract.gate_item("rt_check", "woc_rt_weapon", woc)
		H.equal(ok, false)
        H.equal(provider, "woc")
		H.deep_equal(problems, { "immutable_relic" })

        -- Reject: the immutable WOC relic (682's confirmed craft target).
        ok, problems, provider = contract.gate_item("rt_check",
            "woc_blightreaper", relic_master("dr_ranger"))
        H.equal(ok, false)
        H.equal(provider, "woc")
        H.deep_equal(problems, { "immutable_relic" })

        -- Reject: malformed CWV row names every missing field.
        local malformed = { cwv_variant = true }
        ok, problems = contract.gate_item("rt_check", "cwv_rt_broken", malformed)
        H.equal(ok, false)
        H.deep_equal(problems,
            { "slot_type", "can_wield", "template", "item_type", "inventory_icon" })
    end)

    H.test("CIM #822 stale WOC save rejects before provider registration", function()
        local contract = load_contract()
        local record, reason = contract.gate_record("mirror_restore",
            "woc_blightreaper_001", {
                item_key = "woc_blightreaper",
                rarity = "modded",
                via_mirror = true,
            }, nil)
        H.equal(record, nil)
        H.equal(reason, "provider:immutable_relic")

        -- Backend-id classification also catches older records whose item key
        -- was lost before the canonical WOC definition exists.
        record, reason = contract.gate_record("mirror_restore",
            "woc_blightreaper_001", { item_key = "es_1h_sword" }, nil)
        H.equal(record, nil)
        H.equal(reason, "provider:immutable_relic")
    end)

    H.test("CIM #628 routed-surface registry and capped self-report", function()
        local contract = load_contract()

        -- Fresh instance: every expected surface is unrouted.
        H.deep_equal(contract.unrouted_surfaces(), {
            "athanor_list", "blacksmith_list", "mirror_restore",
            "mirror_injection", "salvage", "cw_conversion",
        })

        -- gate_item / gate_record self-register their surface.
        contract.gate_item("athanor_list", "es_1h_sword", { slot_type = "melee" })
        H.equal(contract.is_surface_routed("athanor_list"), true)
        contract.gate_record("mirror_injection", "rt-bid",
            { item_key = "rt_weapon" }, nil)
        H.equal(contract.is_surface_routed("mirror_injection"), true)

        -- Install-time registration covers the rest.
        contract.register_enumerator("blacksmith_list")
        contract.register_enumerator("mirror_restore")
        contract.register_enumerator("salvage")
        H.deep_equal(contract.unrouted_surfaces(), { "cw_conversion" })

        -- Capped self-report names exactly the unrouted walk, then caps.
        local lines = {}
        local printer = function(line) lines[#lines + 1] = line end
        H.equal(contract.report_unrouted(printer, 2), true)
        H.equal(contract.report_unrouted(printer, 2), true)
        H.equal(contract.report_unrouted(printer, 2), false, "cap must stop the third emit")
        H.equal(#lines, 2)
        H.truthy(lines[1]:find("unrouted walks=cw_conversion", 1, true),
            "self-report must name cw_conversion: " .. lines[1])
        H.truthy(lines[1]:find("routed=5/6", 1, true),
            "self-report must count routed surfaces: " .. lines[1])

        -- Fully routed contract stays silent.
        local routed = load_contract()
        for _, surface in ipairs(routed.PROVIDER_GATE_SURFACES) do
            routed.register_enumerator(surface)
        end
        local silent = {}
        H.equal(routed.report_unrouted(function(line) silent[#silent + 1] = line end), false)
        H.equal(#silent, 0)
    end)

    H.test("CIM #682/#793 Athanor list walk routes the provider gate", function()
        local entry = read("crafting_in_modded_dev.lua")
        -- The gate call sits inside the _setup_weapon_list hook body.
        local hook_start = entry:find('mod:hook("HeroWindowWeaveForgeWeapons", "_setup_weapon_list"', 1, true)
        H.truthy(hook_start, "_setup_weapon_list hook missing")
        local hook_end = entry:find('mod:hook("HeroWindowWeaveForgeWeapons", "_sync_backend_loadout"', 1, true)
        H.truthy(hook_end, "_sync_backend_loadout hook anchor missing")
        local hook_body = entry:sub(hook_start, hook_end)
        H.truthy(hook_body:find('gate_enumerated_row("athanor_list"', 1, true),
            "athanor_list gate call missing from _setup_weapon_list")
        H.truthy(hook_body:find('log_gate_rejections(printf, "athanor_list"', 1, true),
            "capped athanor_list rejection log missing")

        -- The rejection logger ends with the unrouted-walk self-report.
        local contract_source = read("_cim_synthetic_item_contract.lua")
        local logger_start = contract_source:find("function M.log_gate_rejections", 1, true)
        H.truthy(logger_start, "log_gate_rejections missing from the contract")
        local logger_body = contract_source:sub(logger_start, logger_start + 1200)
        H.truthy(logger_body:find("M.report_unrouted(printer)", 1, true),
            "log_gate_rejections must emit the unrouted-walk self-report")
    end)

    H.test("CIM #822 Athanor edit/loadout boundary rejects immutable relics", function()
        local entry = read("crafting_in_modded_dev.lua")
        local ui = read("_cim_immutable_relic_ui.lua")
        H.truthy(entry:find("_cim_immutable_relic_ui", 1, true))
        H.truthy(ui:find("local function editable_backend_id", 1, true))
        H.truthy(ui:find(
            "contract.is_immutable_relic_identity(item_key, item or master,",
            1, true))
        H.truthy(ui:find(
            'editable_backend_id(loadout[slot_name], "saved_loadout")',
            1, true))
        H.truthy(ui:find(
            'editable_backend_id(bid, "equipped_fallback")',
            1, true))
        H.truthy(ui:find(
            'editable_backend_id(item_backend_id, "set_loadout")',
            1, true))
    end)

    H.test("CIM #628 gate_enumerated_row collects classified rejections", function()
        local contract = load_contract()
        local rejected = {}
        H.equal(contract.gate_enumerated_row("athanor_list", "es_1h_sword",
            { slot_type = "melee" }, rejected), true)
        H.equal(contract.gate_enumerated_row("athanor_list", "woc_blightreaper",
            relic_master("dr_ranger"), rejected), false)
        H.equal(#rejected, 1)
        H.equal(rejected[1].key, "woc_blightreaper")
        H.deep_equal(rejected[1].problems, { "immutable_relic" })

        -- The capped logger names the surface, each rejection, and the
        -- overflow count; caps at `cap` detail lines.
        local many = {}
        for i = 1, 10 do
            many[i] = { key = string.format("rt_bad_%02d", i), problems = { "template" } }
        end
        local lines = {}
        contract.log_gate_rejections(function(line) lines[#lines + 1] = line end,
            "athanor_list", many, 8)
        -- 8 detail lines + 1 overflow + 1 unrouted self-report (fresh
        -- instance: everything except athanor_list is unrouted).
        H.equal(#lines, 10)
        H.truthy(lines[1]:find("provider rejected before UI surface=athanor_list key=rt_bad_01", 1, true),
            "first capped rejection line malformed: " .. lines[1])
        H.truthy(lines[9]:find("provider_rejected_more surface=athanor_list count=2", 1, true),
            "overflow line malformed: " .. lines[9])
        H.truthy(lines[10]:find("unrouted walks=", 1, true),
            "self-report line missing: " .. lines[10])
    end)

    H.test("CIM #682 no multi-return-collapsing contract call survives", function()
        local files = {
            "crafting_in_modded_dev.lua",
            "standard_forge.lua",
            "saveweapon_import.lua",
            "_cim_mil_entry_builder.lua",
        }
        for _, name in ipairs(files) do
            local source = read(name)
            -- The live 682 bug shape: `local a, b = contract and contract.f(...)`
            -- truncates the multi-return, so `b` (the reason) is always nil.
            H.equal(source:find("= contract and contract%.normalize_record"), nil,
                name .. " still collapses normalize_record")
            H.equal(source:find("= contract and contract%.gate_record"), nil,
                name .. " collapses gate_record through and/or")
            H.equal(source:find("= record\n%s+and contract%.build_mirror_payload"), nil,
                name .. " still collapses build_mirror_payload")
        end
        local entry = read("crafting_in_modded_dev.lua")
        H.truthy(entry:find('gate_record("mirror_injection"', 1, true),
            "mirror-injection boundary not routed through the record gate")
        H.truthy(entry:find('gate_record("mirror_restore"', 1, true),
            "mirror-restore boundary not routed through the record gate")
        H.truthy(entry:find('register_enumerators(\n    "athanor_list", "mirror_restore", "mirror_injection")', 1, true)
                or entry:find('register_enumerators("athanor_list", "mirror_restore", "mirror_injection")', 1, true),
            "entry does not declare its routed surfaces at install time")
        local forge = read("standard_forge.lua")
        H.truthy(forge:find('gate_record("mirror_injection"', 1, true),
            "standard-forge synth not routed through the record gate")
        H.truthy(forge:find('gate_item("blacksmith_list"', 1, true),
            "blacksmith list not routed through the item gate")
        H.truthy(forge:find('gate_item("random_craft"', 1, true),
            "random-craft pool not routed through the item gate")
        local importer = read("saveweapon_import.lua")
        H.truthy(importer:find('gate_record("mirror_injection"', 1, true),
            "saveweapon import not routed through the record gate")
        local mil = read("_cim_mil_entry_builder.lua")
        H.truthy(mil:find('gate_record("mirror_restore"', 1, true),
            "legacy MIL builder not routed through the record gate")
        local filter = read("_cim_inventory_filter.lua")
        H.truthy(filter:find('register_enumerator("salvage")', 1, true),
            "salvage adapter does not declare its routed surface")
    end)
end
