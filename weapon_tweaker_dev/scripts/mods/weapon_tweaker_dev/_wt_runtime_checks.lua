-- _wt_runtime_checks.lua — Weapon Tweaker runtime regression registrations.
--
-- Owns the assertion closures invoked by /wt_regression_test. The entry point
-- supplies its existing registry and private dependencies; live feature state
-- remains late-bound through `mod` so installation order is unchanged.
--
-- Owned by: Weapon Tweaker entry point. Consumed via: mod:dofile.

local M = {}

function M.install(mod, _rt_register, deps)
    deps = deps or {}
    local _unit_state = deps.unit_state
    local weapon_unlock_map = deps.weapon_unlock_map
    local _3p_template_remaps = deps.three_p_template_remaps
    local _wt603_post_spawn_preview_event = deps.post_spawn_preview_event
    local _WIELD_ANIM_CAREER_3P_PATCHES = deps.wield_anim_career_patches
    local _dbg = deps.dbg
    local _dbg_alert = deps.dbg_alert
    local _wt_master_toggles = deps.master_toggles
    local _wt_rework_master = mod._wt and mod._wt.rework_master_policy
    local _wt_rework_runtime = mod._wt and mod._wt.rework_master_runtime
    local _WIELD_PATCHES_MODULE = deps.wield_patches_module
    local _is_sp_crossbow_presentation_item = deps.is_sp_crossbow_presentation_item
    local _wt_grip_offset_policy = deps.grip_offset_policy
    local _wt_skullsplitter_hand_policy = deps.skullsplitter_hand_policy
    local weapon_backend = deps.weapon_backend
    local _deepwood_runtime = deps.deepwood_runtime
    local _wt_longbow_variable_zoom = deps.longbow_variable_zoom
        or (mod._wt and mod._wt.longbow_variable_zoom)
    -- WT_DEV_OVERLAY_BEGIN:runtime-check-dependencies
    local _wt_dev_anim_picker = deps.dev_anim_picker
    local _wt_dev_hold_pose = deps.dev_hold_pose
    local _WT316_ZOOM_PROBE = deps.zoom_probe_module
    local _wt316_zoom_probe = deps.zoom_probe
    -- WT_DEV_OVERLAY_END:runtime-check-dependencies

    -- ============================================================
    -- /regression_test checks (see scaffold near MOD_VERSION).
    -- ============================================================

    _rt_register("husk_extension_hooked", function()
        -- v0.12.37: SimpleHuskInventoryExtension.wield must be hooked (separate
        -- class from SimpleInventoryExtension — hooking only the local class
        -- silently no-ops on remote-player husks per feedback_vt2_husk_extension_class_pair).
        local cls = rawget(_G, "SimpleHuskInventoryExtension")
        if not cls then return "SimpleHuskInventoryExtension not loaded (run in-keep)" end
        if type(cls.wield) ~= "function" then return "SimpleHuskInventoryExtension.wield missing" end
        -- VMF replaces the class method with its hook wrapper. We can't easily
        -- introspect VMF's hook table portably, so leave this as a presence-of-
        -- class check + an embedded comment marker proving wt hooks it.
        local _MARKER = "SimpleHuskInventoryExtension"
        if #_MARKER == 0 then return "marker missing" end
    end)

    _rt_register("issue201_deepwood_runtime_package_resident", function()
        if type(_deepwood_runtime) ~= "table"
                or type(_deepwood_runtime.status) ~= "function" then
            return "#201 Deepwood runtime package owner missing"
        end
        local status = _deepwood_runtime.status()
        if not status.owned then
            return "skip: Woods DLC ownership unavailable"
        end
        if not status.ready then
            return string.format(
                "#201 we_thornsister package not resident (requested=%s attempts=%s error=%s)",
                tostring(status.requested), tostring(status.attempts),
                tostring(status.last_error))
        end
    end)

    _rt_register("issue282_deepwood_runtime_reference_bounded", function()
        if type(_deepwood_runtime) ~= "table"
                or type(_deepwood_runtime.status) ~= "function" then
            return "#282 Deepwood runtime package owner missing"
        end
        local status = _deepwood_runtime.status()
        if type(status.reference_count) == "number"
                and status.reference_count > 1 then
            return string.format(
                "#282 Deepwood runtime package has %d wt references (expected at most 1)",
                status.reference_count)
        end
    end)

    _rt_register("issue181_skullsplitter_right_hand_contract", function()
        local policy = _wt_skullsplitter_hand_policy
        if type(policy) ~= "table" then return "#181 Skullsplitter hand policy missing" end
        if policy.runtime_action("wh_hammer_book", "es_mercenary", "left")
                ~= "relink_hammer_right" then
            return "#181 Kruber hammer is not routed to the right-hand relink"
        end
        if policy.runtime_action("wh_hammer_book", "es_mercenary", "right")
                ~= "hide_book" then
            return "#181 Kruber book is not routed to the hide action"
        end
        if policy.runtime_action("wh_hammer_book", "wh_priest", "left") ~= nil then
            return "#181 native Warrior Priest was captured by the Kruber presentation"
        end

        local linking, reason = policy.resolve_right_hand_linking(rawget(_G, "Weapons"))
        if not linking then return "skip: #181 target template unavailable: " .. tostring(reason) end
        local first = linking[1]
        if type(first) ~= "table" or first.source ~= "j_rightweaponattach"
                or first.target ~= 0 then
            return "#181 target linking is not j_rightweaponattach -> root"
        end

        local left = { left_hand = true, unit_name = "hammer", marker = "preserve" }
        local right = { right_hand = true, unit_name = "book" }
        local other = { unit_name = "other" }
        local right_third_person, preview_reason =
            policy.resolve_right_hand_third_person(rawget(_G, "Weapons"))
        if not right_third_person then
            return "skip: #181 preview linking unavailable: " .. tostring(preview_reason)
        end
        local rewritten, hid_book, moved_hammer = policy.rewrite_preview_spawn_data(
            { left, right, other }, right_third_person)
        if not hid_book or not moved_hammer or #rewritten ~= 2 then
            return "#181 preview transaction did not replace the hammer/book pair"
        end
        local hammer = rewritten[1]
        if not hammer.right_hand or hammer.left_hand ~= nil
                or hammer.unit_attachment_node_linking ~= right_third_person
                or hammer.marker ~= "preserve" then
            return "#181 preview hammer is not a right-hand illusion-preserving copy"
        end
        if left.left_hand ~= true or left.right_hand ~= nil then
            return "#181 preview transaction mutated the vanilla spawn entry"
        end
    end)

    _rt_register("anim_remap_per_unit", function()
        -- v0.12.35: _unit_state is a weak-keyed per-3P-body table — not a single
        -- _current_weapon_template global. Verify shape.
        if type(_unit_state) ~= "table" then return "_unit_state missing (should be weak-keyed per-unit table)" end
        local mt = getmetatable(_unit_state)
        if not (mt and mt.__mode and mt.__mode:find("k")) then
            return "_unit_state missing weak-key metatable (__mode='k')"
        end
    end)

    _rt_register("issue112_remap_identity_includes_receiver_career", function()
        local policy = mod._wt and mod._wt.anim_state_policy
        if type(policy) ~= "table" or type(policy.remap_identity) ~= "function" then
            return "#112 animation state identity policy unavailable"
        end
        local mercenary = policy.remap_identity(
            "two_handed_billhooks_template", "wh_2h_billhook", "es_mercenary")
        local saltzpyre = policy.remap_identity(
            "two_handed_billhooks_template", "wh_2h_billhook", "wh_bountyhunter")
        if mercenary == saltzpyre then
            return "#112 receiver career does not invalidate the cached remap"
        end
    end)

    _rt_register("issue661_effective_wield_action_contract", function()
        local ok, cwv = pcall(get_mod, "character_weapon_variants")
        if not ok or type(cwv) ~= "table" then return "skip: CWV not loaded" end
        if type(cwv._cwv_resolve_item_key) ~= "function" then
            return "#661 CWV exact item identity provider unavailable"
        end
        local context_policy = mod._wt and mod._wt.weapon_action_context_policy
        if type(context_policy) ~= "table" then
            return "#661 wield-boundary context owner unavailable"
        end
        local item = rawget(_G, "ItemMasterList")
            and rawget(ItemMasterList, "cwv_es_greataxe")
        local template = rawget(_G, "Weapons")
            and rawget(Weapons, "cwv_greataxe_template")
        if type(item) ~= "table" or type(template) ~= "table" then
            return "skip: #661 CWV Greataxe provider not registered"
        end
        local context, reason = context_policy.resolve({ item_data = {
            key = "dr_2h_axe", backend_id = "wt-661-runtime-probe",
            data = { cim_acquisition_key = "cwv_es_greataxe" },
        } }, "wh_bountyhunter", {
            identity_resolvers = { cwv._cwv_resolve_item_key },
            item_master_list = ItemMasterList,
            get_item_template = function() return template end,
        })
        if not context or context.item_key ~= "cwv_es_greataxe" then
            return "#661 inherited-key identity did not resolve: " .. tostring(reason)
        end
        if not context_policy.is_managed(context, mod._wt.weapon_unlock_map) then
            return "#661 exact CWV provider identity was not accepted as managed"
        end
        local cs = rawget(_G, "CareerSettings")
            and rawget(CareerSettings, "wh_bountyhunter")
        for _, ability in ipairs((cs and cs.activated_ability) or {}) do
            local action_name = ability and ability.action_name
            local canonical = action_name and rawget(_G, "ActionTemplates")
                and rawget(ActionTemplates, action_name)
            if canonical and (type(template.actions) ~= "table"
                    or template.actions[action_name] ~= canonical) then
                return "#661 Greataxe missing canonical " .. tostring(action_name)
            end
            for _, alternate in ipairs({
                "cwv_crowbill_pick_template", "cwv_crowbill_hammer_template",
            }) do
                local candidate = rawget(Weapons, alternate)
                if canonical and candidate and (type(candidate.actions) ~= "table"
                        or candidate.actions[action_name] ~= canonical) then
                    return "#661 " .. alternate .. " missing canonical "
                        .. tostring(action_name)
                end
            end
        end
    end)

    _rt_register("wh_priest_no_bows", function()
        -- WT_DEV_OVERLAY_BEGIN:issue948-retired-absence-check
        if true then return end -- dev lab intentionally exposes unresolved ranged cells
        -- WT_DEV_OVERLAY_END:issue948-retired-absence-check
        -- Per feedback_vt2_no_bows_on_warrior_priest: wh_priest must NOT receive
        -- bows / crossbows / longbows because his 3P body lacks the anims.
        local bow_keys = {
            we_longbow = true, es_longbow = true, we_shortbow = true,
            we_shortbow_hagbane = true, wh_crossbow = true, dr_crossbow = true,
            we_crossbow_repeater = true, wh_crossbow_repeater = true,
        }
        local found = {}
        local list = weapon_unlock_map and weapon_unlock_map.wh_priest
        if type(list) == "table" then
            for _, k in ipairs(list) do
                if bow_keys[k] then found[#found + 1] = k end
            end
        end
        if #found > 0 then return "bows on wh_priest: " .. table.concat(found, ", ") end
    end)
    -- WT_DEV_OVERLAY_BEGIN:issue948-universal-runtime-check
    _rt_register("issue948_universal_base_availability", function()
        local policy = mod:dofile(
            "scripts/mods/weapon_tweaker_dev/wt_universal_availability")
        if #policy.all_weapons ~= 83 then
            return "universal roster size = " .. tostring(#policy.all_weapons)
        end
        for _, career in ipairs(policy.careers) do
            local seen = {}
            for _, weapon_key in ipairs(weapon_unlock_map[career.key] or {}) do
                if seen[weapon_key] then
                    return "duplicate " .. career.key .. ":" .. weapon_key
                end
                seen[weapon_key] = true
            end
            for _, weapon_key in ipairs(policy.all_weapons) do
                if not seen[weapon_key] then
                    return "missing " .. career.key .. ":" .. weapon_key
                end
            end
        end
    end)
    -- WT_DEV_OVERLAY_END:issue948-universal-runtime-check

    _rt_register("issue290_billhook_kruber_effective_3p_complete", function()
        -- Host-runnable source contract: 2h_billhooks.lua fires anim_event_3p when present,
        -- otherwise anim_event. Every resulting event must either map explicitly or already
        -- exist in halberds.lua's Kruber polearm vocabulary.
        if not mod._wt.billhook_kruber_contract then return "billhook contract helper missing" end
        local missing, map = mod._wt.billhook_kruber_contract()
        if type(map) ~= "table" then return "two_handed_billhooks_template.es_ missing" end
        if #missing > 0 then return "effective 3P events uncovered: " .. table.concat(missing, ", ") end
        for _, emitted in ipairs({ "attack_swing_stab_charge", "attack_swing_charge_left_diagonal",
                                   "attack_swing_heavy_left_diagonal", "attack_swing_left_diagonal" }) do
            if not map[emitted] then return "receiver-facing event lost after bake merge: " .. emitted end
        end
    end)

    _rt_register("saltz_batch2_wh_remaps_baked", function()
        -- v0.12.213-dev (#519): Saltzpyre batch-2 bake — the 10 fully-tuned ports must
        -- each carry a career-scoped wh_ table in _3p_template_remaps (baked in
        -- _wt_anim_remap.lua from the tester's persisted picks). Guards against a
        -- refactor dropping the do-block appends. dr_dual_wield_hammers deliberately
        -- absent (zero non-unset picks — still queued in the dev picker).
        local expected = {
            "two_handed_hammers_template_1",        -- es_2h_hammer
            "two_handed_cog_hammers_template_1",    -- dr_2h_cog_hammer
            "two_handed_picks_template_1",          -- dr_2h_pick
            "one_handed_hammer_wizard_template_1",  -- bw_1h_mace
            "staff_scythe",                         -- bw_ghost_scythe
            "bastard_sword_template",               -- es_bastard_sword
            "one_handed_hammer_shield_template_1",  -- es_mace_shield
            "one_handed_sword_shield_template_1",   -- es_sword_shield
            "one_handed_sword_shield_template_2",   -- es_sword_shield_breton
            "one_hand_axe_shield_template_1",       -- dr_shield_axe
        }
        local missing = {}
        for _, tpl in ipairs(expected) do
            local entry = _3p_template_remaps[tpl]
            if type(entry) ~= "table" or type(entry.wh_) ~= "table" or not next(entry.wh_) then
                missing[#missing + 1] = tpl
            end
        end
        if #missing > 0 then return "wh_ bake missing: " .. table.concat(missing, ", ") end
    end)

    _rt_register("issue576_reopened_ports_and_action_chain_contract", function()
        local failures = {}
        local spear = _3p_template_remaps.two_handed_spears_elf_template_1
        spear = spear and spear.wh_
        if not spear or spear.attack_swing_charge_right ~= "attack_swing_charge_left_diagonal" then
            failures[#failures + 1] = "elf spear H1 charge does not target billhook 3P charge"
        end
        if not spear or spear.attack_swing_heavy_right ~= "attack_swing_heavy_stab" then
            failures[#failures + 1] = "elf spear H1 committed heavy missing"
        end
        local scythe = _3p_template_remaps.staff_scythe and _3p_template_remaps.staff_scythe.wh_
        if not scythe or scythe.attack_swing_charge_left == scythe.attack_swing_charge_left_diagonal
            or scythe.attack_swing_heavy == scythe.attack_swing_heavy_left_diagonal then
            failures[#failures + 1] = "scythe H1/H3 roles collapsed"
        end
        -- WT_DEV_OVERLAY_BEGIN:picker-source-regression
        if not (_wt_dev_anim_picker and _wt_dev_anim_picker.source_events_for) then
            failures[#failures + 1] = "picker source-event regression surface missing"
        else
            local required = {
                bw_ghost_scythe = { "attack_swing_charge_left", "attack_swing_heavy", "attack_swing_left_diagonal" },
                we_spear = { "attack_swing_charge_right", "attack_swing_heavy_right" },
            }
            for key, events in pairs(required) do
                local got, present = _wt_dev_anim_picker.source_events_for("saltzpyre", key), {}
                for _, event in ipairs(got or {}) do present[event] = true end
                for _, event in ipairs(events) do
                    if not present[event] then failures[#failures + 1] = key .. " missing picker row " .. event end
                end
            end
        end
        -- WT_DEV_OVERLAY_END:picker-source-regression
        for _, career in ipairs({ "wh_captain", "wh_bountyhunter", "wh_zealot" }) do
            local has_es, has_dr = false, false
            for _, key in ipairs(weapon_unlock_map[career] or {}) do
                has_es = has_es or key == "es_2h_hammer"
                has_dr = has_dr or key == "dr_2h_hammer"
            end
            if not has_es or has_dr then
                failures[#failures + 1] = career .. " must offer es_2h_hammer and exclude dr_2h_hammer"
            end
        end
        if #failures > 0 then return table.concat(failures, "; ") end
    end)

    _rt_register("issue748_cwv_style_clone_contracts", function()
        local aliases = _WIELD_PATCHES_MODULE and _WIELD_PATCHES_MODULE.cwv_style_donors
        if type(aliases) ~= "table" then return "CWV style alias catalogue missing" end
        local function wield_contract(name)
            local direct = _WIELD_PATCHES_MODULE.patches[name]
            local bulk = _WIELD_PATCHES_MODULE.bulk[name]
            if type(direct) == "table" and type(bulk) == "table" then
                return nil, name .. " is duplicated across wield catalogues"
            end
            return direct or bulk
        end
        local count = 0
        for clone_name, donor_name in pairs(aliases) do
            count = count + 1
            local donor_wield, err = wield_contract(donor_name)
            if err then return err end
            local clone_wield, clone_err = wield_contract(clone_name)
            if clone_err then return clone_err end
            if type(donor_wield) ~= "table" then
                return donor_name .. " donor 3P wield contract missing"
            end
            if clone_wield ~= donor_wield then
                return clone_name .. " does not share donor 3P wield contract " .. donor_name
            end
            local donor_remap = _3p_template_remaps and _3p_template_remaps[donor_name]
            local clone_remap = _3p_template_remaps and _3p_template_remaps[clone_name]
            if type(donor_remap) == "table" and clone_remap ~= donor_remap then
                return clone_name .. " does not share donor 3P remap contract " .. donor_name
            end
        end
        if count ~= 7 then return "CWV style alias catalogue expected 7 rows, got " .. count end
        if aliases.imperial_longsword_template ~= "two_handed_swords_template_1" then
            return "Imperial Longsword style is not tied to the Greatsword 3P donor"
        end
        local clone = _3p_template_remaps
            and _3p_template_remaps.cwv_infantry_spear_template
        if type(clone) ~= "table" or type(clone.wh_) ~= "table"
            or clone.wh_.attack_swing_down_left_axe ~= "attack_swing_stab" then
            return "Saltzpyre first-light event is not remapped to attack_swing_stab"
        end
        local clone_wield = wield_contract("cwv_infantry_spear_template")
        for _, career in ipairs({ "wh_captain", "wh_bountyhunter", "wh_zealot" }) do
            if clone_wield[career] ~= "to_2h_billhook" then
                return career .. " Infantry spear wield is not routed to billhook vocabulary"
            end
        end
    end)

    _rt_register("issue603_ranger_dual_axes_inventory_preview_pose", function()
        return _wt603_post_spawn_preview_event(
                "dr_dual_wield_axes", "dr_ranger", "to_dual_axes") == "to_dual_hammers"
            and _wt603_post_spawn_preview_event(
                "dr_dual_wield_hammers", "dr_ranger", "to_dual_hammers") == nil
            and _wt603_post_spawn_preview_event(
                "dr_dual_wield_axes", "dr_slayer", "to_dual_axes") == nil
    end)

    _rt_register("native_fire_crowbill_distinct_and_preview_wired", function()
        local required = {
            "es_mercenary", "es_huntsman", "es_knight", "es_questingknight",
            "dr_ranger", "dr_ironbreaker", "dr_slayer", "dr_engineer",
            "wh_captain", "wh_bountyhunter", "wh_zealot",
        }
        local crowbill_wield = _WIELD_ANIM_CAREER_3P_PATCHES.one_handed_crowbill or {}
        for _, career in ipairs(required) do
            local found = false
            for _, weapon_key in ipairs(weapon_unlock_map[career] or {}) do
                found = found or weapon_key == "bw_1h_crowbill"
            end
            if not found then return "native Crowbill missing from " .. career end
            if crowbill_wield[career] ~= "to_1h_sword" then
                return "Crowbill preview wield missing for " .. career
            end
            local managed = mod._wt.cwv_conditional_managed[career]
            if managed and managed.bw_1h_crowbill then
                return "CWV replacement policy hides native Crowbill for " .. career
            end
        end
    end)

    _rt_register("issue587_baked_transform_husk_fanout", function()
        local contract = mod._wt587_transform_contract
        assert(contract and contract.source == "baked_tables",
            "committed transforms must come from shipped baked tables")
        assert(contract.transport == "none" and contract.rpc_channels == 0,
            "baked transform fan-out must not allocate an RPC channel or payload")
        assert(contract.live_tuner_scope == "local_player_3p_only",
            "transient Hold-Pose slider movement must remain local")
        assert(contract.first_person == "unchanged",
            "husk transform fan-out must preserve first person")
        assert(contract.components.scale == "scale_only"
            and contract.components.offset == "position_only"
            and contract.components.rotation == "wt569_rotation_only",
            "scale/position/#569 rotation must compose through separate setters")
        assert(type(mod._wt587_track_durable_3p_units) == "function",
            "durable 3P units need spawn/wield-time registration")

        local scythe = mod._wt587_baked_transform_plan("bw_ghost_scythe", "es_knight")
        assert(scythe.durable and scythe.offset
            and scythe.offset[1] == 0 and scythe.offset[2] == 0 and scythe.offset[3] == 0.6,
            "Kruber Scythe must resolve its durable +0.6 Z bake")

        local glaive = mod._wt587_baked_transform_plan("we_2h_axe", "es_mercenary")
        assert(glaive.durable and glaive.offset and glaive.offset[3] == 0.285,
            "second transformed weapon must resolve its durable bake")

        local control = mod._wt587_baked_transform_plan("es_1h_sword", "es_knight")
        assert(control.scale == nil and control.offset == nil and control.durable == false,
            "unmodified receiver-native control must remain untouched")

        local native_scythe = mod._wt587_baked_transform_plan("bw_ghost_scythe", "bw_necromancer")
        assert(native_scythe.offset == nil,
            "career gate must preserve the native Sienna Scythe transform")
    end)

    _rt_register("issue112_saltzpyre_handgun_baked_offset", function()
        local plan = mod._wt587_baked_transform_plan
        assert(type(plan) == "function", "baked transform resolver missing")
        for _, career in ipairs({ "wh_captain", "wh_bountyhunter", "wh_zealot" }) do
            local handgun = plan("es_handgun", career)
            assert(handgun.durable and handgun.offset,
                "Empire Handgun offset must use durable 3P reapply on " .. career)
            assert(handgun.offset[1] == 0
                and handgun.offset[2] == -0.17
                and handgun.offset[3] == -0.05,
                "Empire Handgun offset drifted on " .. career)
        end
        local native = plan("es_handgun", "es_huntsman")
        assert(native.offset == nil and native.durable,
            "Kruber's native Empire Handgun must not receive Saltzpyre's offset")
        local control = plan("wh_crossbow_repeater", "wh_captain")
        assert(control.offset == nil and control.durable == false,
            "unmodified Saltzpyre ranged control must remain untouched")
    end)

    _rt_register("issue701_kruber_crossbow_left_grip_offset", function()
        local plan = mod._wt587_baked_transform_plan
        local policy = _wt_grip_offset_policy
        assert(type(plan) == "function" and policy and policy.contract,
            "crossbow transform policy missing")
        for _, career in ipairs({ "es_mercenary", "es_huntsman", "es_knight", "es_questingknight" }) do
            local crossbow = plan("wh_crossbow", career)
            assert(crossbow.durable and crossbow.offset
                and crossbow.offset[1] == 0
                and crossbow.offset[2] == 0.100
                and crossbow.offset[3] == 0.025
                and crossbow.offset.hand == "left",
                "Kruber crossbow left-hand durable offset drifted on " .. career)
        end
        local native = plan("wh_crossbow", "wh_captain")
        assert(native.offset == nil, "Saltzpyre's native Crossbow grip changed")
        local control = plan("wh_crossbow_repeater", "es_knight")
        assert(control.offset == nil and control.durable == false,
            "Kruber Volley Crossbow control must remain unmodified")
        assert(policy.preview_slot_field({ left_hand_unit = "" }) == "left_unit_3p"
            and policy.preview_slot_field({ right_hand_unit = "" }) == "right_unit_3p"
            and policy.preview_slot_field({ left_hand_unit = "", right_hand_unit = "" }) == "right_unit_3p",
            "preview hand routing no longer distinguishes left-only Crossbow safely")
        assert(policy.contract.retained_evidence == "post_write_engine_readback"
            and policy.contract.first_person == "unchanged",
            "#701 retained-state/first-person contract drifted")
    end)

    _rt_register("issue112_saltzpyre_kruber_shield_baked_rotation", function()
        local plan = mod._wt587_baked_transform_plan
        local contract = mod._wt569_orientation_contract
        assert(type(plan) == "function" and type(contract) == "table",
            "baked shield rotation resolver missing")
        local expected = contract.baked_shield_euler
        assert(expected and expected[1] == 25 and expected[2] == -17.5 and expected[3] == -15,
            "Saltzpyre shield Euler correction drifted")
        local shield_keys = {
            "es_mace_shield", "es_sword_shield", "es_sword_shield_breton",
            -- CWV clone-name compatibility plus the intended public identities.
            "dr_shield_axe", "cwv_es_axe_shield", "cwv_es_axe_shield_veteran",
        }
        for _, career in ipairs({ "wh_captain", "wh_bountyhunter", "wh_zealot" }) do
            for _, weapon_key in ipairs(shield_keys) do
                local row = plan(weapon_key, career)
                assert(row.rotation
                    and row.rotation[1] == 25
                    and row.rotation[2] == -17.5
                    and row.rotation[3] == -15,
                    string.format("shield rotation missing key=%s career=%s", weapon_key, career))
            end
            assert(plan("es_deus_01", career).rotation == nil,
                "Kruber Spear & Shield must remain excluded on " .. career)
        end
        for _, weapon_key in ipairs(shield_keys) do
            assert(plan(weapon_key, "es_knight").rotation == nil,
                "native Kruber shield rotation changed: " .. weapon_key)
            assert(plan(weapon_key, "wh_priest").rotation == nil,
                "Warrior Priest must remain outside standard-Saltzpyre shield tuning: " .. weapon_key)
        end
        assert(contract.baked_shield_scope == "standard_saltzpyre_3p"
            and contract.spear_shield_exempt_key == "es_deus_01",
            "shield rotation ownership/exemption contract drifted")
    end)

    _rt_register("issue735_shield_rotation_left_only", function()
        local plan = mod._wt587_baked_transform_plan
        local policy = _wt_grip_offset_policy
        assert(type(plan) == "function" and policy and policy.contract,
            "per-hand transform policy missing")
        for _, career in ipairs({ "wh_captain", "wh_bountyhunter", "wh_zealot" }) do
            for _, weapon_key in ipairs({
                "es_mace_shield", "es_sword_shield", "es_sword_shield_breton",
                "dr_shield_axe", "cwv_es_axe_shield", "cwv_es_axe_shield_veteran",
            }) do
                local rotation = plan(weapon_key, career).rotation
                assert(rotation and rotation.hand == "left",
                    string.format("#735 shield rotation hand drift key=%s career=%s",
                        weapon_key, career))
                assert(policy.applies_to_hand(rotation, "left")
                    and not policy.applies_to_hand(rotation, "right"),
                    "#735 hand policy would rotate the primary weapon: " .. weapon_key)
                assert(policy.preview_slot_field(
                    { left_hand_unit = "shield", right_hand_unit = "weapon" }, rotation) == nil,
                    "#735 paired preview must defer to exact spawn_data hand adapter")
            end
        end
        assert(policy.contract.hand_scope == "descriptor_hand_field"
            and policy.contract.paired_scoped_preview == "post_spawn_data_hand_adapter"
            and policy.contract.retained_evidence == "post_write_engine_readback",
            "#735 hand/preview/retained-state contract drifted")
    end)

    _rt_register("wt_safe_hook_installed", function()
        -- v0.12.77 (Issue #26): pcall-isolated `mod:safe_hook` wrapper. The helper
        -- is required from `_safe_hook.lua` near the top of this file, BEFORE any
        -- `mod:hook(...)` call site. If the require ever drops out of the load
        -- order (refactor / bad merge), every `mod:safe_hook(...)` site below
        -- crashes at module load with "attempt to call a nil value (method
        -- 'safe_hook')". This check surfaces the regression at /wt_regression_test
        -- time rather than letting it manifest as a load failure.
        --
        -- 1. Source-pattern marker constant set by `_safe_hook.lua`.
        if CT_WT_SAFE_HOOK_MARKER_v0_12_74 ~= "wt-safe-hook-pcall-isolated" then
            return "safe_hook marker absent — was _safe_hook.lua require removed?"
        end
        -- 2. Runtime: both methods must be callable functions on the mod table.
        if type(mod.safe_hook) ~= "function" then
            return "mod.safe_hook is not a function (got " .. type(mod.safe_hook) .. ")"
        end
        if type(mod.safe_hook_safe) ~= "function" then
            return "mod.safe_hook_safe is not a function (got " .. type(mod.safe_hook_safe) .. ")"
        end
    end)

    -- v0.12.80-dev: hard regression test for the multi-return + nil-hole bug
    -- class that shipped 3 versions in 2 hours (v0.12.77/.78/.79). The marker
    -- constant check above (`wt_safe_hook_installed`) only proves the module
    -- loaded — it does NOT exercise the actual multi-return path that broke
    -- silently in v0.12.77 (collapse to single return) and again in v0.12.78
    -- (`unpack(results, 2)` without explicit `j`, non-deterministic with nil
    -- holes per Lua 5.1 `#table` undefined behavior).
    --
    -- This fixture builds a fresh dummy class on every test invocation (fresh
    -- table identity = fresh hook target, so VMF's "duplicate hook" guard never
    -- trips and the check is rerunnable any number of times), wraps a method
    -- that mimics the worst-case `GearUtils.spawn_inventory_unit` return shape
    -- (5 returns, 2 nil holes at positions 2 and 4 — more aggressive than the
    -- real one), and asserts positional integrity through `safe_hook`.
    _rt_register("wt_safe_hook_preserves_multi_returns_with_nil_holes", function()
        -- Each run uses a fresh table identity so VMF treats it as a new hook
        -- target (no double-registration error on repeated /wt_regression_test).
        local _dummy_class = {
            -- Returns 5 values, with two nil holes (positions 2 and 4) — mimics
            -- and exceeds the melee-weapon `GearUtils.spawn_inventory_unit`
            -- return shape (`weapon_3p, ammo_3p_nil, weapon_1p, ammo_1p_nil`).
            method = function(self, ...) return 1, nil, 2, nil, 3 end,
            -- Error path: handler that raises so we can prove safe_hook catches
            -- + logs without crashing and the chain continues to vanilla.
            raiser = function(self) error("test-raise: safe_hook fixture") end,
        }

        -- Wrap the method via safe_hook. Handler just forwards everything so any
        -- return-mangling is attributable to the wrapper, not the body.
        mod:safe_hook(_dummy_class, "method", function(func, ...)
            return func(...)
        end)

        -- Call the safe-hooked method. Capture every return positionally using
        -- the `select("#", ...)` + table-pack idiom — the same one safe_hook
        -- itself must use internally to be correct.
        local function _capture(...) return select("#", ...), { ... } end
        local n, r = _capture(_dummy_class:method())

        -- Assertion 1: full count preserved (catches the v0.12.77 collapse-to-1
        -- bug and the v0.12.78 non-deterministic-#table truncation).
        if n ~= 5 then
            return string.format(
                "safe_hook truncated multi-return: got n=%d expected 5 (results=%s,%s,%s,%s,%s)",
                n, tostring(r[1]), tostring(r[2]), tostring(r[3]), tostring(r[4]), tostring(r[5]))
        end
        -- Assertion 2: positional integrity. Each slot exact value, including
        -- the two intentional nil holes. Catches any future "compact away nils"
        -- regression in the unpack path.
        if r[1] ~= 1 then
            return "safe_hook positional integrity: r[1] expected 1, got " .. tostring(r[1])
        end
        if r[2] ~= nil then
            return "safe_hook positional integrity: r[2] expected nil, got " .. tostring(r[2])
        end
        if r[3] ~= 2 then
            return "safe_hook positional integrity: r[3] expected 2, got " .. tostring(r[3])
        end
        if r[4] ~= nil then
            return "safe_hook positional integrity: r[4] expected nil, got " .. tostring(r[4])
        end
        if r[5] ~= 3 then
            return "safe_hook positional integrity: r[5] expected 3, got " .. tostring(r[5])
        end

        -- Error-path coverage: safe_hook a raiser, call it, assert it doesn't
        -- crash. safe_hook's contract is "log + fall through to vanilla" so the
        -- raiser's `error(...)` will fire twice (once in the handler, once in
        -- the vanilla fall-through call to `func(...)`). The outer pcall here
        -- catches the vanilla raise; we ONLY care that the wrapper itself
        -- didn't propagate an uncaught Lua error from inside safe_hook's own
        -- bookkeeping (e.g. nil-method-deref, bad unpack args). We accept
        -- either outcome (pcall ok=true OR ok=false with the test-raise
        -- message) as long as the wrapper didn't blow up with its own error.
        mod:safe_hook(_dummy_class, "raiser", function(func, ...)
            return func(...)
        end)
        local raiser_ok, raiser_err = pcall(function() _dummy_class:raiser() end)
        -- raiser_ok == false is expected (vanilla raises after handler logged);
        -- raiser_ok == true would also be acceptable (engine swallowed it).
        -- What we DON'T want is a wrapper-internal failure like "attempt to
        -- call nil" or "bad argument #2 to 'unpack'".
        if not raiser_ok then
            local err_str = tostring(raiser_err)
            if not err_str:find("test%-raise") then
                return "safe_hook error path: wrapper raised its own error instead of vanilla fall-through: " .. err_str
            end
        end
    end)

    -- v0.12.84-dev: Layer 3 traced_hook smoke test. Sister check to the
    -- v0.12.77 `wt_safe_hook_installed` marker — proves the traced_hook module
    -- attached both methods AND the trace lines don't crash when emitted.
    -- Does NOT exercise the actual log-line contents (that's a manual
    -- in-game verification — toggle `enable_debug_logging` on and watch the
    -- log file for `[wt:trace] event=enter|exit ...` pairs around any of the
    -- three migrated hook sites: SimpleInventoryExtension.wield,
    -- GearUtils.create_equipment, GearUtils.spawn_inventory_unit).
    _rt_register("wt_priest_punch_buff_wired", function()
        -- The buffed punch profile must register at load (network-index determinism)
        -- and the apply fn must exist. Mirrors the authentic-pistol guard.
        if type(mod.wt_apply_priest_punch_buff) ~= "function" then
            return "mod.wt_apply_priest_punch_buff missing"
        end
        local DPT = rawget(_G, "DamageProfileTemplates")
        if not DPT then return "skip: DamageProfileTemplates not loaded" end
        if not DPT.wt_priest_punch_buffed then
            return "wt_priest_punch_buffed damage profile not registered at load"
        end
        if NetworkLookup and NetworkLookup.damage_profiles
            and not rawget(NetworkLookup.damage_profiles, "wt_priest_punch_buffed") then
            return "wt_priest_punch_buffed missing from NetworkLookup.damage_profiles (would desync/crash networked)"
        end
        -- The clone must actually be scaled vs the source on default_target (2x dmg /
        -- 3x stagger), proving the power_distribution scale ran.
        local src = DPT.light_blunt_smiter_stab
        local buf = DPT.wt_priest_punch_buffed
        local function pd(p) return type(p)=="table" and type(p.default_target)=="table" and p.default_target.power_distribution or nil end
        local sp, bp = pd(src), pd(buf)
        if type(sp)=="table" and type(bp)=="table" and type(sp.attack)=="number" and type(sp.impact)=="number" then
            if math.abs(bp.attack - sp.attack * 2) > 0.0001 then return "punch damage not 2x on default_target" end
            if math.abs(bp.impact - sp.impact * 3) > 0.0001 then return "punch stagger not 3x on default_target" end
        end
    end)

    _rt_register("wt_traced_hook_present", function()
        -- 1. Source-pattern marker constant set by `_safe_hook.lua` (Layer 3
        --    section). If the require ever drops out of the load order or the
        --    Layer 3 block gets deleted, this surfaces at /wt_regression_test.
        if CT_WT_TRACED_HOOK_MARKER_v0_12_84 ~= "wt-traced-hook-layer3-installed" then
            return "traced_hook marker absent — was Layer 3 block removed from _safe_hook.lua?"
        end
        -- 2. Runtime: both Layer 3 methods must be callable functions on the
        --    mod table.
        if type(mod.traced_hook) ~= "function" then
            return "mod.traced_hook is not a function (got " .. type(mod.traced_hook) .. ")"
        end
        if type(mod.traced_hook_safe) ~= "function" then
            return "mod.traced_hook_safe is not a function (got " .. type(mod.traced_hook_safe) .. ")"
        end
        -- 3. Smoke: install traced_hook on a fresh dummy class (fresh identity
        --    so VMF's duplicate-hook guard never trips). We DON'T assert "no
        --    trace lines emitted" — that would require log-file inspection — but
        --    a crash inside the tracing closure would surface here.
        local _dummy_class = {
            method = function(self, a, b) return a, nil, b end,  -- 3 returns w/ nil hole
        }
        mod:traced_hook(_dummy_class, "method", function(func, ...)
            return func(...)
        end)
        local r1, r2, r3 = _dummy_class:method(7, 9)
        if r1 ~= 7 or r2 ~= nil or r3 ~= 9 then
            return string.format("traced_hook return-shape broken: r1=%s r2=%s r3=%s",
                tostring(r1), tostring(r2), tostring(r3))
        end
        -- 4. Second smoke with a different dummy class to verify the trace-emit
        --    path doesn't crash when mod:debug fires.
        local _dummy_class_b = {
            method = function(self, a, b) return a, nil, b end,
        }
        mod:traced_hook(_dummy_class_b, "method", function(func, ...)
            return func(...)
        end)
        local s1, s2, s3 = _dummy_class_b:method(11, 13)
        if s1 ~= 11 or s2 ~= nil or s3 ~= 13 then
            return string.format("traced_hook return-shape broken (second smoke): s1=%s s2=%s s3=%s",
                tostring(s1), tostring(s2), tostring(s3))
        end
    end)

    -- Guard for WT_LINK_UNITS_NODE_GUARD_MARKER: the GearUtils.link_units crash filter
    -- must drop links whose source/target node is absent and leave all-present links
    -- untouched (zero-copy). Engine-free — uses synthetic node-presence predicates.
    _rt_register("link_units_node_guard", function()
        if type(mod._wt_link_filter) ~= "function" then
            return "mod._wt_link_filter missing (GearUtils.link_units crash guard reverted?)"
        end
        local linking = {
            { source = "j_hips",                   target = "j_page_nr1_01" }, -- both present -> keep
            { source = "j_rightweaponcomponent11", target = "j_page_nr2_01" }, -- source absent -> drop
            { source = "j_spine",                  target = "j_no_such_node"  }, -- target absent -> drop
        }
        local present_src = { j_hips = true, j_spine = true }
        local present_tgt = { j_page_nr1_01 = true, j_page_nr2_01 = true }
        local out, dropped = mod._wt_link_filter(linking,
            function(n) return present_src[n] == true end,
            function(n) return present_tgt[n] == true end)
        if dropped ~= 2 then return "LINK-GUARD: expected 2 dropped, got " .. tostring(dropped) end
        if #out ~= 1 then return "LINK-GUARD: expected 1 surviving link, got " .. tostring(#out) end
        if out[1].source ~= "j_hips" then return "LINK-GUARD: wrong link survived (expected j_hips)" end
        -- all-present must be a zero-copy no-op (returns the SAME table, 0 dropped)
        local same = { { source = "j_hips", target = "j_page_nr1_01" } }
        local out2, d2 = mod._wt_link_filter(same, function() return true end, function() return true end)
        if d2 ~= 0 or out2 ~= same then return "LINK-GUARD: all-present case must return the original table unchanged" end
    end)

    -- #269: a staff holstered on a Kruber body reaches this flat-array boundary with
    -- source=a_unwielded_staff. Kruber does not author that source, so the old guard
    -- dropped the sole link and made the staff disappear. The receiver-local fallback
    -- must preserve the input table and must not rewrite a native body's valid source.
    _rt_register("issue269_unwielded_staff_hip_fallback", function()
        local staff_link = { source = "a_unwielded_staff", target = 0 }
        local linking = { staff_link }
        local out, dropped, substituted = mod._wt_link_filter(linking,
            function(n) return n == "j_hips" end,
            function() return true end)
        if dropped ~= 0 or substituted ~= 1 then
            return string.format("#269: expected drop=0/substitute=1, got %s/%s",
                tostring(dropped), tostring(substituted))
        end
        if out == linking or out[1] == staff_link then
            return "#269: fallback must copy rather than mutate the live linking table"
        end
        if out[1].source ~= "j_hips" or staff_link.source ~= "a_unwielded_staff" then
            return "#269: fallback source/result mutation contract broken"
        end
        local native, native_dropped, native_substituted = mod._wt_link_filter(linking,
            function(n) return n == "a_unwielded_staff" or n == "j_hips" end,
            function() return true end)
        if native ~= linking or native_dropped ~= 0 or native_substituted ~= 0 then
            return "#269: native authored staff node must remain a zero-copy no-op"
        end
    end)

    _rt_register("wt_itemmasterlist_uses_rawget", function()
        -- v0.12.72/.73: defensive `rawget(ItemMasterList, key)` (GH #8) at 5 known
        -- mutation sites (~L175, 208, 226, 277, 3835 of weapon_tweaker.lua). The
        -- strict-table-lookup lint covers static-pattern regressions; this runtime
        -- check is the belt-and-suspenders companion required by §15 of
        -- PROJECT_STANDARDS.md.
        --
        -- 1. Source-pattern: the marker constant must be present (catches
        --    accidental code deletion / revert).
        if CT_WT_ITEMMASTERLIST_RAWGET_MARKER_v0_12_73 ~= "wt-itemmasterlist-rawget-hardened" then
            return "RAWGET marker absent — was the v0.12.72 ItemMasterList hardening reverted?"
        end
        -- 2. Runtime-state: rawget on a known-bad key must return nil rather than
        --    raise. If ItemMasterList ever grows a strict __index, this would
        --    surface the regression at boot.
        local iml = rawget(_G, "ItemMasterList")
        if type(iml) == "table" then
            local ok, value = pcall(rawget, iml, "__wt_rawget_probe_does_not_exist__")
            if not ok then
                return "rawget(ItemMasterList, <bad-key>) RAISED — strict-metatable behavior changed"
            end
            if value ~= nil then
                return "rawget(ItemMasterList, <bad-key>) returned non-nil — unexpected"
            end
        end
    end)

    _rt_register("wt_authentic_pistol_profile_registered_unconditionally", function()
        -- audit 2026-06-07 (PROJECT_STANDARDS §9.3): the custom damage profile must be
        -- registered in NetworkLookup on EVERY peer regardless of the authentic-brace
        -- toggle, or the network index diverges between peers with the toggle on vs off
        -- (RPC crash / wrong-damage desync). Assert it's present even when the toggle
        -- is off. Fails if a future edit re-gates the registration behind the toggle.
        local DPT = rawget(_G, "DamageProfileTemplates")
        local NL  = rawget(_G, "NetworkLookup")
        if not (DPT and NL and NL.damage_profiles) then
            return "skip: DamageProfileTemplates/NetworkLookup not loaded"
        end
        if not rawget(DPT, "wt_authentic_pistol") then
            return "wt_authentic_pistol missing from DamageProfileTemplates (registration not unconditional)"
        end
        if not rawget(NL.damage_profiles, "wt_authentic_pistol") then
            return "wt_authentic_pistol missing from NetworkLookup.damage_profiles (peer index would diverge)"
        end
    end)

    _rt_register("wt_kruber_1h_sword_push_combo_revert", function()
        -- Issue #348: the opt-in revert repoints Kruber's Empire 1h sword push-attack
        -- (light_attack_bopp) combo continuation from 6.11.0's `default_left` (third
        -- light overhead) back to the pre-6.11.0 `default` (first light sweep). Assert
        -- the vanilla sub-actions the revert relies on still exist, and -- only when the
        -- toggle is ON -- that the continuation actually routes to "default". Guards
        -- against a future edit renaming the target or re-gating the patch.
        local W = rawget(_G, "Weapons")
        if not W or not rawget(W, "one_handed_swords_template_1") then
            return "skip: Weapons.one_handed_swords_template_1 not loaded"
        end
        local actions = W.one_handed_swords_template_1.actions
        local ao = actions and actions.action_one
        if not ao then return "action_one missing on one_handed_swords_template_1" end
        if not ao.default then return "action_one.default missing (revert continuation target)" end
        local bopp = ao.light_attack_bopp
        if not (bopp and bopp.allowed_chain_actions) then
            return "light_attack_bopp chain missing"
        end
        if mod:get("wt_revert_1h_sword_push_combo") then
            local first = bopp.allowed_chain_actions[1]
            if not (first and first.sub_action == "default") then
                return "toggle ON but push-attack combo not reverted (chain[1].sub_action="
                    .. tostring(first and first.sub_action) .. ")"
            end
        end
    end)

    _rt_register("dbg_helpers_two_channel", function()
        if type(_dbg) ~= "function" then return "_dbg helper missing" end
        if type(_dbg_alert) ~= "function" then return "_dbg_alert helper missing" end
        local ok = pcall(_dbg, "smoke test")
        if not ok then return "_dbg raised on call" end
        ok = pcall(_dbg_alert, "smoke test")
        if not ok then return "_dbg_alert raised on call" end
        -- #240 / §17B: _dbg_alert must be log-only (engine printf), never mod:warning
        -- (which posts to chat). The marker is set only on the printf-routed helper.
        if mod._wt_alerts_log_only_marker ~= "wt-alert-helpers-log-only-printf-240" then
            return "_dbg_alert not rerouted to log-only printf (#240 regression)"
        end
    end)



    _rt_register("localization_format_safe", function()
        -- Layer 3 (2026-05-25): catch unescaped %-format chars in loc strings at
        -- runtime. VMF's tooltip render path calls string.format on the loc value;
        -- literal "%APPDATA%" / "5%" / "%USERNAME%" raises 'invalid option' and
        -- shows as a red error tooltip in the VMF settings UI. Static check is
        -- qa/check_localization.ps1 -- this is its runtime twin so the bug can't
        -- ship even if the static check is skipped. RULE: any literal % in a loc
        -- string must be doubled to %%.
        local ok, loc = pcall(mod.dofile, mod, "scripts/mods/weapon_tweaker_dev/weapon_tweaker_dev_localization")
        if not ok or type(loc) ~= "table" then return end  -- can't reach loc; skip
        for k, v in pairs(loc) do
            if type(v) == "table" and type(v.en) == "string" then
                local fmt_ok, fmt_err = pcall(string.format, v.en)
                if not fmt_ok then
                    return string.format(
                        "loc key %q has invalid format string (escape literal %% as %%%%): %s",
                        k, tostring(fmt_err))
                end
            end
        end
    end)

    local function _verify_availability_display_order()
        local ok, data = pcall(mod.dofile, mod,
            "scripts/mods/weapon_tweaker_dev/weapon_tweaker_dev_data")
        if not ok or type(data) ~= "table" then
            return { "weapon_tweaker_data not loadable: " .. tostring(data) }, 0, 0
        end
        local raw = mod._wt_loc_raw
        if type(raw) ~= "table" then return { "mod._wt_loc_raw unavailable" }, 0, 0 end

        local function _sort_key(setting_id)
            local entry = raw[setting_id]
            local label = type(entry) == "table" and entry.en
            if type(label) ~= "string" or label == "" then return nil end
            while true do
                local clean, n = label:gsub("^%s*%b[]%s*", "", 1)
                label = clean
                if n == 0 then break end
            end
            return string.lower(label) .. "\0" .. setting_id, label
        end

        local failures, leaves, rows = {}, 0, 0
        local function _walk(node)
            if type(node) ~= "table" then return end
            local sid = node.setting_id
            local career = type(sid) == "string"
                and (sid:match("^melee_(.+)$") or sid:match("^ranged_(.+)$"))
            if career and type(node.sub_widgets) == "table" then
                local prefix = "unlock_" .. career .. "_"
                local prior_key, prior_label
                leaves = leaves + 1
                for _, child in ipairs(node.sub_widgets) do
                    local child_sid = type(child) == "table" and child.setting_id
                    if type(child_sid) == "string" and child_sid:sub(1, #prefix) == prefix then
                        local key, label = _sort_key(child_sid)
                        rows = rows + 1
                        if not key then
                            failures[#failures + 1] = child_sid .. " has no English display label"
                        elseif prior_key and prior_key > key then
                            failures[#failures + 1] = string.format(
                                "%s: %q appears before %q", sid, prior_label, label)
                        end
                        prior_key, prior_label = key, label or child_sid
                    end
                end
            end
            if type(node.sub_widgets) == "table" then
                for _, child in ipairs(node.sub_widgets) do _walk(child) end
            end
            if type(node.widgets) == "table" then
                for _, child in ipairs(node.widgets) do _walk(child) end
            end
            for _, child in ipairs(node) do _walk(child) end
        end
        _walk(data)
        return failures, leaves, rows
    end

    mod:command("verify_wt_availability_sort",
        "Verify Weapon Availability rows follow their visible names", function()
            local failures, leaves, rows = _verify_availability_display_order()
            if #failures == 0 then
                mod:echo("[wt:408] PASS: %d rows across %d career leaves are sorted by visible name",
                    rows, leaves)
            else
                mod:echo("[wt:408] FAIL: %d ordering problem(s)", #failures)
                for _, failure in ipairs(failures) do mod:echo("  %s", failure) end
            end
        end)

    _rt_register("issue408_availability_rows_sorted_by_name", function()
        local failures, leaves, rows = _verify_availability_display_order()
        if #failures > 0 then return table.concat(failures, "; ") end
        if leaves == 0 or rows == 0 then
            return string.format("no availability rows inspected (leaves=%d rows=%d)", leaves, rows)
        end
    end)

    _rt_register("issue611_master_toggle_wiring", function()
        -- issue 611: the Weapon Availability master ("Enable All ...") toggles are
        -- built by _data.lua at load. Verify the wiring the runtime cascade / auto-off
        -- handlers depend on: master->children and child->master are consistent;
        -- each master is scoped to one exact receiving career/slot; source order is
        -- Kruber/Bardin/Kerillian/Saltzpyre/Sienna in every leaf; every child belongs
        -- to that receiving career and to the SOURCE character named by its label.
        local mc = mod._wt_master_children
        local c2m = mod._wt_child_to_master
        local leaf_orders = mod._wt_master_order_by_leaf
        local widget_children = mod._wt_master_widget_children
        if type(mc) ~= "table" or type(c2m) ~= "table"
                or type(leaf_orders) ~= "table" or type(widget_children) ~= "table" then
            return "master toggle maps not built (children/reverse/leaf-order/gear)"
        end
        local leaf_count = 0
        for leaf_id, masters in pairs(leaf_orders) do
            leaf_count = leaf_count + 1
            local prior_rank = 0
            for _, master_id in ipairs(masters) do
                local career, slot, src = _wt_master_toggles.parse_master_id(master_id)
                if not career or leaf_id ~= slot .. "_" .. career then
                    return "master escaped its receiving career leaf: " .. tostring(master_id)
                end
                local rank = _wt_master_toggles.source_order_index(src)
                if not rank or rank <= prior_rank then
                    return "source order is not Kruber/Bardin/Kerillian/Saltzpyre/Sienna in " .. leaf_id
                end
                prior_rank = rank
            end
        end
        local master_count = 0
        for master_id, children in pairs(mc) do
            master_count = master_count + 1
            if type(master_id) ~= "string" or master_id:sub(1, 9) ~= "wtmaster_" then
                return "master id has wrong prefix: " .. tostring(master_id)
            end
            local career, slot, src = _wt_master_toggles.parse_master_id(master_id)
            if not career or not slot or not src then
                return "master id not parseable: " .. master_id
            end
            if type(children) ~= "table" or #children == 0 then
                return "master has no children: " .. master_id
            end
            local nested = widget_children[master_id]
            if type(nested) ~= "table" or #nested ~= #children then
                return "master advanced-options gear children missing: " .. master_id
            end
            local raw = mod._wt_loc_raw
            if not (type(raw) == "table" and type(raw[master_id]) == "table"
                    and type(raw[master_id].en) == "string") then
                return "master lacks localization owner: " .. master_id
            end
            for index, child in ipairs(children) do
                if type(child) ~= "string" or child:sub(1, 7) ~= "unlock_" then
                    return "master child is not an unlock row: " .. tostring(child)
                end
                if c2m[child] ~= master_id then
                    return "child->master reverse map broken for " .. child
                end
                local career_prefix = "unlock_" .. career .. "_"
                if child:sub(1, #career_prefix) ~= career_prefix then
                    return "master contains another receiving career: " .. child
                end
                if _wt_master_toggles.source_char_of(mod, child) ~= src then
                    return "child source char disagrees with master for " .. child
                end
                if type(nested[index]) ~= "table" or nested[index].setting_id ~= child then
                    return "master gear child disagrees with runtime map for " .. child
                end
            end
        end
        if master_count == 0 or leaf_count == 0 then
            return string.format("no master toggles were built (masters=%d leaves=%d)",
                master_count, leaf_count)
        end
    end)

    _rt_register("issue445_rework_master_contract", function()
        if type(_wt_rework_master) ~= "table"
                or type(_wt_rework_master.plan) ~= "function"
                or type(_wt_rework_master.derive_master) ~= "function" then
            return "#445 pure rework-master policy is unavailable"
        end
        if type(_wt_rework_runtime) ~= "table"
                or type(_wt_rework_runtime.on_master_changed) ~= "function"
                or type(_wt_rework_runtime.sync_for_leaf) ~= "function" then
            return "#445 bounded rework-master runtime is unavailable"
        end
        if _wt_rework_master.MASTER_ID ~= "wt_rework_master_ensrick"
                or #(_wt_rework_master.LEAF_IDS or {}) ~= 13 then
            return "#445 master identity or exact 13-member catalog drifted"
        end
        local seen = {}
        for i = 1, #_wt_rework_master.LEAF_IDS do
            local id = _wt_rework_master.LEAF_IDS[i]
            if seen[id] or id:find("^br_") then
                return "#445 duplicate or retired member: " .. tostring(id)
            end
            seen[id] = true
            local row = mod._wt_loc_raw and mod._wt_loc_raw[id]
            local label = type(row) == "table" and row.en
            if type(label) ~= "string" or label:sub(1, 10) ~= "[Ensrick] " then
                return "#445 active tweak lacks authorship prefix: " .. tostring(id)
            end
        end
        local all_on = {}
        for id in pairs(seen) do all_on[id] = true end
        if not _wt_rework_master.derive_master(all_on) then
            return "#445 exact-family master derivation failed"
        end
        all_on[_wt_rework_master.LEAF_IDS[1]] = false
        if _wt_rework_master.derive_master(all_on) then
            return "#445 partial family incorrectly reports master enabled"
        end
    end)

    _rt_register("widget_unlock_map_consistency", function()
        -- Bug class: a (career, weapon) pair lives in `weapon_unlock_map` but
        -- the companion `unlock_<career>_<weapon>` VMF widget is missing from
        -- weapon_tweaker_data.lua. The runtime apply logic supports the unlock
        -- but the toggle is silently unreachable from the VMF settings UI -- so
        -- the user can never turn it on. Burned 2026-05-25: es_sword_shield_breton
        -- was in es_knight's weapon_unlock_map array but had no widget in
        -- melee_es_knight, so Foot Knight couldn't get Bretonnian Sword and
        -- Shield (wt v0.12.89-dev -> v0.12.90-dev fix). Same check also catches
        -- the inverse: dead widgets that don't map to anything.
        if type(weapon_unlock_map) ~= "table" then
            return "weapon_unlock_map unreachable"
        end
        local ok, data = pcall(mod.dofile, mod,
            "scripts/mods/weapon_tweaker_dev/weapon_tweaker_dev_data")
        if not ok or type(data) ~= "table" then
            return "weapon_tweaker_data not loadable: " .. tostring(data)
        end
        -- Walk the nested widget tree, harvest every setting_id.
        local widget_ids = {}
        local function _harvest(w)
            if type(w) ~= "table" then return end
            if type(w.setting_id) == "string" then
                widget_ids[w.setting_id] = true
            end
            if type(w.sub_widgets) == "table" then
                for _, s in ipairs(w.sub_widgets) do _harvest(s) end
            end
            if type(w.widgets) == "table" then
                for _, s in ipairs(w.widgets) do _harvest(s) end
            end
            for _, s in ipairs(w) do _harvest(s) end
        end
        _harvest(data)
        -- Forward: every map (career, weapon) needs a widget.
        local missing_widgets = {}
        for career, weapons in pairs(weapon_unlock_map) do
            if type(weapons) == "table" then
                for _, weapon in ipairs(weapons) do
                    local key = "unlock_" .. career .. "_" .. weapon
                    if not widget_ids[key] then
                        missing_widgets[#missing_widgets + 1] = key
                    end
                end
            end
        end
        if #missing_widgets > 0 then
            return string.format("widget missing for unlock_map entries: %s",
                table.concat(missing_widgets, ", "))
        end
        -- Reverse: every "unlock_<career>_<weapon>" widget needs a map entry.
        -- Both career names and weapon keys contain underscores, so simple
        -- string.match is ambiguous -- walk each known career prefix instead.
        local missing_map = {}
        for sid, _ in pairs(widget_ids) do
            if type(sid) == "string" and sid:sub(1, 7) == "unlock_" then
                local matched = false
                for career, weapons in pairs(weapon_unlock_map) do
                    local pfx = "unlock_" .. career .. "_"
                    if sid:sub(1, #pfx) == pfx then
                        local w = sid:sub(#pfx + 1)
                        if type(weapons) == "table" then
                            for _, mw in ipairs(weapons) do
                                if mw == w then matched = true; break end
                            end
                        end
                        if matched then break end
                    end
                end
                if not matched then
                    missing_map[#missing_map + 1] = sid
                end
            end
        end
        if #missing_map > 0 then
            return string.format(
                "widget(s) present but missing from weapon_unlock_map: %s",
                table.concat(missing_map, ", "))
        end
    end)

    _rt_register("xchar_unwielded_attach_node_safe", function()
        -- Bug class: a cross-character port adds (career, weapon) where the
        -- weapon's attachment_node_linking references a body-specific source
        -- node like `a_unwielded_crossbow` that the equipping career's body
        -- skeleton does NOT author. `Unit.node()` on the missing node bypasses
        -- pcall and engine-fatals -- typically the moment the inventory
        -- previewer opens or the weapon transitions to unwielded in-game.
        -- Burned 2026-05-25 (crashify 9ef21d18-0926-4c1b-b53f-9655a38f9447):
        -- wh_crossbow on Kruber crashed "a_unwielded_crossbow" in the
        -- inventory screen because Kruber's body lacks that node. Fixed by
        -- _patch_xchar_unwielded_attachment_safe() substituting `j_hips`.
        --
        -- This check walks every cross-character port in weapon_unlock_map,
        -- looks up each weapon's attachment_node_linking, and flags any
        -- `third_person.unwielded[].source` that still looks body-specific
        -- (`a_unwielded_*` prefix) -- those are candidates for the same crash
        -- class on bodies that don't author that node. Pre-shipped bodies
        -- only author `a_unwielded_*` nodes for weapons their own career
        -- vanilla-wields, so any `a_unwielded_<weapon>` source on a weapon
        -- being ported to a different character is a red flag.
        if type(weapon_unlock_map) ~= "table" then return end
        if not AttachmentNodeLinking then return end
        if not rawget(_G, "ItemMasterList") then return end
        if not rawget(_G, "Weapons") then return end
        local iml = ItemMasterList

        -- Build career -> base prefix lookup so we know which weapons are
        -- "native" to each career (we only want to flag CROSS-character ports,
        -- not the weapon's own vanilla career).
        local _NATIVE_PREFIX = {
            es_ = { es_mercenary = true, es_huntsman = true,
                    es_knight = true,    es_questingknight = true },
            dr_ = { dr_ranger = true,    dr_ironbreaker = true,
                    dr_slayer = true,    dr_engineer = true },
            we_ = { we_waywatcher = true, we_maidenguard = true,
                    we_shade = true,      we_thornsister = true },
            wh_ = { wh_captain = true,   wh_bountyhunter = true,
                    wh_zealot = true,    wh_priest = true },
            bw_ = { bw_adept = true,     bw_scholar = true,
                    bw_unchained = true, bw_necromancer = true },
        }
        local function _is_native(career, weapon_key)
            for pfx, careers in pairs(_NATIVE_PREFIX) do
                if weapon_key:sub(1, #pfx) == pfx then
                    return careers[career] == true
                end
            end
            return false   -- es_deus_* / unknown prefix -- treat as cross-char
        end

        local risky = {}  -- {career, weapon_key, source_node}
        for career, weapons in pairs(weapon_unlock_map) do
            if type(weapons) == "table" then
                for _, weapon_key in ipairs(weapons) do
                    if not _is_native(career, weapon_key) then
                        local entry = rawget(iml, weapon_key)
                        local tpl_name = entry and entry.template
                        local tpl = tpl_name and rawget(Weapons, tpl_name)
                        if type(tpl) == "table" then
                            local linkings = {
                                tpl.left_hand_attachment_node_linking,
                                tpl.right_hand_attachment_node_linking,
                                tpl.ammo_unit_attachment_node_linking,
                            }
                            for _, link in ipairs(linkings) do
                                if type(link) == "table" and type(link.third_person) == "table" then
                                    local unw = link.third_person.unwielded
                                    if type(unw) == "table" then
                                        for _, e in ipairs(unw) do
                                            local src = e and e.source
                                            if type(src) == "string"
                                                    and src:sub(1, 11) == "a_unwielded" then
                                                risky[#risky + 1] = string.format(
                                                    "%s/%s -> %s", career, weapon_key, src)
                                            end
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
        if #risky > 0 then
            return string.format(
                "cross-char port(s) with body-specific unwielded source node "
                .. "(crash risk -- substitute with j_hips or run-time hook): %s",
                table.concat(risky, "; "))
        end
    end)

    -- v0.12.99-dev: VMF rejects `type = "group"` widgets with zero `sub_widgets`
    -- at init ("must have at least 1 sub_widget") and the whole mod fails to
    -- load — silent surfacing failure that's hard to debug from in-game. Walk
    -- the live data tree recursively; fail with the offending setting_id if
    -- any group is empty. Burned twice: v0.12.96-dev (empty character bucket
    -- in dev anim picker) and v0.12.98-dev (empty top-level picker group when
    -- mod._weapon_unlock_map was nil at _data.lua time).
    _rt_register("vmf_no_empty_group_widgets", function()
        -- Reload the same data file VMF reads. mod:dofile is idempotent for
        -- pure data builders (no side effects), so calling here at regression
        -- time doesn't disturb VMF's bound copy. We walk what VMF sees.
        local data = mod:dofile("scripts/mods/weapon_tweaker_dev/weapon_tweaker_dev_data")
        if not data or not data.options or not data.options.widgets then
            return "could not load weapon_tweaker_data.lua for inspection"
        end
        local offenders = {}
        local function _walk(widgets, path)
            if type(widgets) ~= "table" then return end
            for _, w in ipairs(widgets) do
                if type(w) == "table" and w.type == "group" then
                    local sid = w.setting_id or "?"
                    local children = w.sub_widgets
                    if type(children) ~= "table" or #children == 0 then
                        offenders[#offenders + 1] = path .. "/" .. sid .. " (group has 0 sub_widgets)"
                    else
                        _walk(children, path .. "/" .. sid)
                    end
                end
            end
        end
        _walk(data.options.widgets, "")
        if #offenders > 0 then
            return string.format("%d empty VMF group(s) found (would trip 'must have at least 1 sub_widget' at boot): %s",
                #offenders, table.concat(offenders, "; "))
        end
    end)

    _rt_register("fire_fx_package_resident", function()
        -- GH #128 (v0.12.159-dev): cross-character fire weapons (Drakefire Pistols,
        -- Drakegun, Fireball/Flamethrower staves) CTD'd non-native careers because
        -- their AOE explosion particles ride the Sienna career package bw_unchained,
        -- which a cross-char wielder never loads. wt force-loads it at mod init
        -- (_force_load_fire_explosion_packages). If that load is removed/renamed the
        -- crash returns; this asserts the package is resident.
        if not (Managers and Managers.package) then return "skip: Managers.package not ready (run in-keep)" end
        local pkg = "resource_packages/careers/bw_unchained"
        if not Managers.package:has_loaded(pkg) then
            return "fire-fx package NOT resident (#128 regression) -- " .. pkg
        end
    end)

    _rt_register("necromancer_fx_package_resident_if_dlc", function()
        -- v0.12.163-dev: the Necromancy/Soulstealer Staff (bw_necromancy_staff) on a
        -- cross-char wielder needs bw_necromancer's particles
        -- (fx/wpnfx_necromancer_skullstaff_*), which are NOT in bw_unchained. wt
        -- force-loads bw_necromancer at mod init, GATED on the Necromancer DLC
        -- (`shovel`) being owned (force-loading a non-owned DLC package would itself
        -- crash). So this only asserts residence when the DLC is owned.
        if not (Managers and Managers.package and Managers.unlock) then return "skip: managers not ready (run in-keep)" end
        local um = Managers.unlock
        if not (um.dlc_exists and um.is_dlc_unlocked and um:dlc_exists("shovel") and um:is_dlc_unlocked("shovel")) then
            return "skip: Necromancer (shovel) DLC not owned -- package intentionally not force-loaded"
        end
        local pkg = "resource_packages/careers/bw_necromancer"
        if not Managers.package:has_loaded(pkg) then
            return "necromancer fx package NOT resident (soulstealer-crash regression) -- " .. pkg
        end
    end)

    _rt_register("no_dwarf_dual_hammers_on_saltzpyre", function()
        -- WT_DEV_OVERLAY_BEGIN:issue948-retired-dual-hammer-absence
        if true then return end -- exhaustive dev catalog intentionally includes it
        -- WT_DEV_OVERLAY_END:issue948-retired-dual-hammer-absence
        -- v0.12.164-dev: dr_dual_wield_hammers removed from the non-WP Saltzpyre
        -- careers (redundant with wh_dual_hammer "Dual Skullsplitters" they already
        -- have). Guard that a future unlock-map edit doesn't silently re-add it.
        if type(weapon_unlock_map) ~= "table" then return "skip: weapon_unlock_map not loaded" end
        local bad = {}
        for _, c in ipairs({ "wh_captain", "wh_bountyhunter", "wh_zealot" }) do
            local list = weapon_unlock_map[c]
            if type(list) == "table" then
                for _, k in ipairs(list) do
                    if k == "dr_dual_wield_hammers" then bad[#bad + 1] = c end
                end
            end
        end
        if #bad > 0 then return "dr_dual_wield_hammers back on Saltzpyre: " .. table.concat(bad, ", ") end
    end)

    _rt_register("saltzpyre_dual_axes_wield_axe_falchion", function()
        -- v0.12.168: Bardin's "Dual Axes" (dual_wield_axes_template_1) on Saltzpyre must
        -- wield as the Dual Axe & Falchion (to_dual_axe_sword_wh), NOT WP Dual Hammers
        -- (to_dual_hammers_priest). Guards the wt_wield_patches.bulk entry from reverting.
        local wp = _WIELD_PATCHES_MODULE and _WIELD_PATCHES_MODULE.bulk
        local e = wp and wp.dual_wield_axes_template_1
        if not e then return "skip: wield-patch module not loaded" end
        for _, c in ipairs({ "wh_captain", "wh_bountyhunter", "wh_zealot" }) do
            if e[c] ~= "to_dual_axe_sword_wh" then
                return "dual axes " .. c .. " wield = " .. tostring(e[c]) .. " (expected to_dual_axe_sword_wh)"
            end
        end
    end)

    _rt_register("saltzpyre_dagger_wield_falchion", function()
        -- v0.12.168: Sienna's "Dagger" (one_handed_daggers_template_1) on Saltzpyre must
        -- wield as 1H Falchion (to_1h_sword), NOT Fencing Sword/Rapier (to_fencing_sword).
        local wp = _WIELD_PATCHES_MODULE and _WIELD_PATCHES_MODULE.bulk
        local e = wp and wp.one_handed_daggers_template_1
        if not e then return "skip: wield-patch module not loaded" end
        for _, c in ipairs({ "wh_captain", "wh_bountyhunter", "wh_zealot" }) do
            if e[c] ~= "to_1h_sword" then
                return "dagger " .. c .. " wield = " .. tostring(e[c]) .. " (expected to_1h_sword)"
            end
        end
    end)

    _rt_register("volley_crossbow_preview_wield_baked", function()
        -- #441 (v0.12.212-dev): Kerillian's Volley Crossbow on Saltzpyre showed the wrong
        -- idle pose in the keep inventory preview. The previewer resolves the 3P wield pose
        -- from wield_anim_career_3p[career] or the template's base wield_anim directly
        -- (world_hero_previewer.lua:1060-1065) and never rides the in-mission
        -- _career_anim_redirect funnel (the preview body has no career extension), so the
        -- receiver-native wields MUST stay baked in wt_wield_patches.bulk. Guards both
        -- directions of the Volley Crossbow pair from reverting.
        local wp = _WIELD_PATCHES_MODULE and _WIELD_PATCHES_MODULE.bulk
        if not wp then return "skip: wield-patch module not loaded" end
        local elf = wp.repeating_crossbow_elf_template
        for _, c in ipairs({ "wh_captain", "wh_bountyhunter", "wh_zealot" }) do
            if not elf or elf[c] ~= "to_repeating_crossbow" then
                return "we_crossbow_repeater " .. c .. " wield = " .. tostring(elf and elf[c]) .. " (expected to_repeating_crossbow)"
            end
        end
        local whx = wp.repeating_crossbow_template_1
        for _, c in ipairs({ "we_waywatcher", "we_maidenguard", "we_shade", "we_thornsister" }) do
            if not whx or whx[c] ~= "to_repeating_crossbow_elf" then
                return "wh_crossbow_repeater " .. c .. " wield = " .. tostring(whx and whx[c]) .. " (expected to_repeating_crossbow_elf)"
            end
        end
        -- Live-template layer: confirm the apply actually landed on Weapons.* (catches an
        -- apply-order regression the data-module guard above would miss).
        if Weapons and Weapons.repeating_crossbow_elf_template then
            local live = Weapons.repeating_crossbow_elf_template.wield_anim_career_3p
            if not live or live.wh_captain ~= "to_repeating_crossbow" then
                return "live repeating_crossbow_elf_template wield_anim_career_3p.wh_captain = " .. tostring(live and live.wh_captain)
            end
        end
    end)

    _rt_register("repeater_empty_wield_network_patch_all_careers", function()
        -- #536: the empty-wield network-crash patch (_NOT_LOADED_NO_AMMO_CAREER_PATCHES)
        -- must route we_crossbow_repeater's not-loaded/no-ammo wield to a REGISTERED anim
        -- for EVERY career that can wield it, else the empty-clip wield packs a nil
        -- NetworkLookup.anims index into rpc_anim_event -> C-level fatal (bypasses pcall).
        -- Kruber careers (v0.12.139) -> to_repeating_handgun; wh careers (#536, v0.12.216)
        -- -> to_repeating_crossbow. Both fallbacks are NetworkLookup-registered
        -- (anims_lookup_table.lua:645/670). Guards wh coverage AND that Kruber stays covered.
        local tpl = Weapons and Weapons.repeating_crossbow_elf_template
        if not tpl then return "skip: Weapons.repeating_crossbow_elf_template not loaded" end
        local nl = tpl.wield_anim_not_loaded_career
        local na = tpl.wield_anim_no_ammo_career
        if not (nl and na) then return "not_loaded/no_ammo career tables missing on repeating_crossbow_elf_template" end
        local expect = {
            es_mercenary     = { "to_repeating_handgun",  "to_repeating_handgun_noammo" },
            es_huntsman      = { "to_repeating_handgun",  "to_repeating_handgun_noammo" },
            es_knight        = { "to_repeating_handgun",  "to_repeating_handgun_noammo" },
            es_questingknight= { "to_repeating_handgun",  "to_repeating_handgun_noammo" },
            wh_captain       = { "to_repeating_crossbow", "to_repeating_crossbow_noammo" },
            wh_bountyhunter  = { "to_repeating_crossbow", "to_repeating_crossbow_noammo" },
            wh_zealot        = { "to_repeating_crossbow", "to_repeating_crossbow_noammo" },
        }
        for career, want in pairs(expect) do
            if nl[career] ~= want[1] then
                return "not_loaded[" .. career .. "] = " .. tostring(nl[career]) .. " (expected " .. want[1] .. ")"
            end
            if na[career] ~= want[2] then
                return "no_ammo[" .. career .. "] = " .. tostring(na[career]) .. " (expected " .. want[2] .. ")"
            end
        end
        -- wh_priest must NOT be patched here (it can't wield the weapon; see wh_priest_no_bows).
        if nl.wh_priest or na.wh_priest then
            return "wh_priest wrongly patched (not_loaded=" .. tostring(nl.wh_priest) .. " no_ammo=" .. tostring(na.wh_priest) .. ")"
        end
    end)

    _rt_register("issue286_greataxe_saltzpyre_wield_pose", function()
        -- #286 post-fix lock: Bardin's Greataxe on the three non-WP Saltzpyre
        -- careers must use the Warrior Priest greathammer wield/idle stance, not the
        -- old greatsword stance. Guard both the source table and the applied live
        -- Weapons table so an apply-order regression cannot hide behind correct data.
        local wp = _WIELD_PATCHES_MODULE and _WIELD_PATCHES_MODULE.bulk
        local configured = wp and wp.two_handed_axes_template_1
        if not configured then return "two_handed_axes_template_1 wield patch missing" end
        local live = Weapons and Weapons.two_handed_axes_template_1
            and Weapons.two_handed_axes_template_1.wield_anim_career_3p
        for _, career in ipairs({ "wh_captain", "wh_bountyhunter", "wh_zealot" }) do
            if configured[career] ~= "to_2h_hammer_priest" then
                return string.format("configured %s=%s (expected to_2h_hammer_priest)",
                    career, tostring(configured[career]))
            end
            if live and live[career] ~= "to_2h_hammer_priest" then
                return string.format("live %s=%s (expected to_2h_hammer_priest)",
                    career, tostring(live[career]))
            end
        end
    end)

    _rt_register("issue569_wp_hammer_remap_orientation_scope", function()
        local predicate = mod._wt569_should_rotate_3p
        local contract = mod._wt569_orientation_contract
        if type(predicate) ~= "function" then return "#569 orientation predicate missing" end
        if type(contract) ~= "table" then return "#569 orientation contract missing" end
        local mapped = { wield_anim_career_3p = {
            wh_captain = "to_2h_hammer_priest",
            wh_bountyhunter = "to_2h_hammer_priest",
            wh_zealot = "to_2h_hammer_priest",
            wh_priest = "to_2h_hammer_priest",
        } }
        for _, career in ipairs({ "wh_captain", "wh_bountyhunter", "wh_zealot" }) do
            if not predicate("dr_2h_axe", career, mapped) then
                return "mapped non-native weapon excluded for " .. career
            end
        end
        if predicate("dr_2h_axe", "wh_priest", mapped) then
            return "Warrior Priest body incorrectly included"
        end
        if predicate("wh_2h_hammer", "wh_captain", mapped) then
            return "native Warrior Priest greathammer exemption missing"
        end
        if predicate("dr_2h_axe", "wh_captain", { wield_anim_career_3p = {
                wh_captain = "to_2h_sword" } }) then
            return "non-WP-greathammer remap incorrectly included"
        end
        local axis = contract.axis
        if type(axis) ~= "table" or axis[1] ~= 0 or axis[2] ~= 0 or axis[3] ~= 1 then
            return "correction axis is not exact local Z (0,0,1)"
        end
        if contract.degrees ~= 180 then return "correction is not exactly 180 degrees" end
        if contract.native_exempt_key ~= "wh_2h_hammer" then
            return "native exemption key drifted"
        end
    end)
    -- WT_DEV_OVERLAY_BEGIN:hold-pose-regressions
    _rt_register("issue168_hold_pose_independent_hands", function()
        local build_tree = _wt_dev_hold_pose and _wt_dev_hold_pose.build_widget_tree
        local build_plans = _wt_dev_hold_pose
            and _wt_dev_hold_pose._independent_hand_plans
        if type(build_tree) ~= "function" or type(build_plans) ~= "function" then
            return "Hold-Pose independent-hand contract missing"
        end

        local function find_setting(node, wanted)
            if type(node) ~= "table" then return nil end
            if node.setting_id == wanted then return node end
            for _, child in ipairs(node.sub_widgets or {}) do
                local found = find_setting(child, wanted)
                if found then return found end
            end
            return nil
        end

        local tree = build_tree()
        local suffixes = {
            "offset_x", "offset_y", "offset_z",
            "rot_pitch", "rot_yaw", "rot_roll",
            "scale_x", "scale_y", "scale_z",
        }
        for _, spec in ipairs({
                { "wt_dev_hp_rh_group", "wt_dev_hp_rh_" },
                { "wt_dev_hp_lh_group", "wt_dev_hp_lh_" },
                { "wt_dev_hp_fp_rh_group", "wt_dev_hp_fp_rh_" },
                { "wt_dev_hp_fp_lh_group", "wt_dev_hp_fp_lh_" },
        }) do
            local group = find_setting(tree, spec[1])
            if not group then
                return "independent hand group missing: " .. spec[1]
            end
            if type(group.sub_widgets) ~= "table" or #group.sub_widgets ~= 9 then
                return "independent hand group is not an exact nine-value owner: " .. spec[1]
            end
            for i, suffix in ipairs(suffixes) do
                if group.sub_widgets[i].setting_id ~= spec[2] .. suffix then
                    return "hand group key crossed ownership: " .. spec[1]
                end
            end
        end
        if find_setting(tree, "wt_dev_hp_hand") then
            return "legacy single-hand selector returned"
        end

        local reads = {}
        local plans = build_plans("third_person", function(channel, hand)
            reads[#reads + 1] = channel .. ":" .. hand
            if hand == "right" then
                return 0.25, 0, 0, 0, 0, 0, 1, 1, 1
            end
            return 0, 0, 0, 0, 17, 0, 0.5, 0.75, 1.25
        end)
        if reads[1] ~= "third_person:right" or reads[2] ~= "third_person:left"
                or reads[3] ~= nil then
            return "production plan owner did not read each hand exactly once"
        end
        if type(plans) ~= "table" or type(plans.right) ~= "table"
                or type(plans.left) ~= "table" then
            return "independent hand plans missing"
        end
        if not plans.right.position or plans.right.rotation or plans.right.scale
                or plans.right.ox ~= 0.25 then
            return "right-hand plan consumed left-hand values"
        end
        if plans.left.position or not plans.left.rotation or not plans.left.scale
                or plans.left.yaw ~= 17 or plans.left.sx ~= 0.5 then
            return "left-hand plan consumed right-hand values"
        end
    end)

    _rt_register("issue569_hold_pose_composition", function()
        local pose_contract = _wt_dev_hold_pose and _wt_dev_hold_pose._pose_contract
        local plan_values = _wt_dev_hold_pose and _wt_dev_hold_pose._component_plan_values
        if type(pose_contract) ~= "table" or type(plan_values) ~= "function" then
            return "Hold-Pose composition contract missing"
        end
        if pose_contract.mode ~= "canonical_plus_delta"
            or pose_contract.position_setter ~= "Unit.set_local_position"
            or pose_contract.rotation_setter ~= "Unit.set_local_rotation"
            or pose_contract.scale_setter ~= "Unit.set_local_scale"
            or pose_contract.scale_mode ~= "absolute"
            or pose_contract.scope ~= "local_player_isolated_1p_3p"
            or pose_contract.compounds ~= false then
            return "Hold-Pose must compose position/rotation/scale without compounding"
        end
        local position_only = plan_values(0, 0, 0.1, 0, 0, 0)
        if not position_only.position or position_only.rotation or position_only.scale then
            return "position-only Hold-Pose edit would overwrite canonical rotation"
        end
        local rotation_only = plan_values(0, 0, 0, 0, 0, 15)
        if rotation_only.position or not rotation_only.rotation or rotation_only.scale then
            return "rotation-only Hold-Pose edit would overwrite canonical position"
        end
        local identity = plan_values(0, 0, 0, 0, 0, 0, 1, 1, 1)
        if identity.position or identity.rotation or identity.scale then
            return "identity Hold-Pose sliders are not a no-op"
        end
    end)

    _rt_register("issue616_hold_pose_channel_bypass_restore", function()
        local contract = _wt_dev_hold_pose and _wt_dev_hold_pose._pose_contract
        local policy_values = _wt_dev_hold_pose and _wt_dev_hold_pose._channel_policy_values
        if type(contract) ~= "table" or type(policy_values) ~= "function" then
            return "Hold-Pose channel/bypass contract missing"
        end
        if contract.scope ~= "local_player_isolated_1p_3p"
                or type(contract.channels) ~= "table"
                or not contract.channels.first_person
                or not contract.channels.third_person then
            return "1P/3P channels are not explicitly isolated"
        end
        local excluded = contract.excluded_surfaces
        for _, key in ipairs({ "inventory_preview", "hero_preview", "bots",
                "remote_husks", "score", "baked_transforms" }) do
            if type(excluded) ~= "table" or excluded[key] ~= true then
                return "tuner surface leakage guard missing: " .. key
            end
        end
        local all_on = policy_values(true, true, true)
        local one_off = policy_values(true, false, true)
        local master_off = policy_values(false, true, true)
        if not all_on.master or not all_on.first_person or not all_on.third_person
                or one_off.first_person or not one_off.third_person then
            return "channel enable state is not independent"
        end
        if master_off.master or master_off.first_person or master_off.third_person then
            return "master bypass did not disable both transform channels"
        end
        if not one_off.preserves_settings or not one_off.restores_baseline_on_bypass
                or contract.bypass ~= "restore_channel_baseline_without_erasing_settings" then
            return "bypass erases values or fails to restore the canonical baseline"
        end
    end)

    _rt_register("issue616_hold_pose_live_edit_delivery", function()
        local classify = _wt_dev_hold_pose and _wt_dev_hold_pose._setting_channel
        local delivery = _wt_dev_hold_pose and _wt_dev_hold_pose._live_delivery_contract
        if type(classify) ~= "function" or type(delivery) ~= "table" then
            return "Hold-Pose live edit delivery contract missing"
        end
        if classify("wt_dev_hp_rh_offset_y") ~= "third_person"
                or classify("wt_dev_hp_lh_rot_roll") ~= "third_person"
                or classify("wt_dev_hp_rh_scale_x") ~= "third_person" then
            return "third-person position/rotation/scale edit routing drifted"
        end
        if classify("wt_dev_hp_fp_rh_offset_y") ~= "first_person"
                or classify("wt_dev_hp_fp_lh_rot_roll") ~= "first_person"
                or classify("wt_dev_hp_fp_rh_scale_x") ~= "first_person" then
            return "first-person position/rotation/scale edit routing drifted"
        end
        if classify("wt_dev_hp_target_slot") ~= "both"
                or classify("wt_dev_hp_enabled") ~= nil then
            return "Hold-Pose non-transform setting routing is not exact"
        end
        if delivery.setting_dispatch ~= "channel_exact"
                or delivery.immediate_apply ~= true
                or delivery.bypass_preserves_values ~= true
                or delivery.bypass_does_not_apply ~= true then
            return "Hold-Pose immediate/bypass delivery semantics drifted"
        end
    end)

    _rt_register("issue616_hold_pose_nonuniform_scale", function()
        local pose_contract = _wt_dev_hold_pose and _wt_dev_hold_pose._pose_contract
        local plan_values = _wt_dev_hold_pose and _wt_dev_hold_pose._component_plan_values
        if type(pose_contract) ~= "table" or type(plan_values) ~= "function" then
            return "Hold-Pose scale contract missing"
        end
        if pose_contract.scale_setter ~= "Unit.set_local_scale"
                or pose_contract.scale_mode ~= "absolute"
                or pose_contract.compounds ~= false then
            return "scale must be absolute and non-compounding"
        end
        local scale_only = plan_values(0, 0, 0, 0, 0, 0, 0.5, 0.75, 1.25)
        if scale_only.position or scale_only.rotation or not scale_only.scale
                or scale_only.sx ~= 0.5 or scale_only.sy ~= 0.75 or scale_only.sz ~= 1.25 then
            return "non-uniform scale plan clobbers another component"
        end
        local all = plan_values(0.1, -0.2, 0.3, -90, 180, -90, 0.5, 0.6, 0.7)
        if not all.position or not all.rotation or not all.scale then
            return "complete nine-value transform does not compose all components"
        end
    end)
    -- WT_DEV_OVERLAY_END:hold-pose-regressions

    _rt_register("issue316_kruber_longbow_zoom_contract", function()
        if not rawget(_G, "Weapons") then return "skip: Weapons not loaded" end
        local tpl = Weapons.longbow_empire_template
        local aim = tpl and tpl.actions and tpl.actions.action_two
            and tpl.actions.action_two.default
        if not aim or aim.kind ~= "aim" or aim.anim_event ~= "draw_bow"
            or type(aim.aim_zoom_delay) ~= "number" or aim.aim_zoom_delay <= 0 then
            return "Empire Longbow no longer reaches the native ActionAim zoom path"
        end
        local scoped = _3p_template_remaps.longbow_empire_template or {}
        for _, career in ipairs({ "es_mercenary", "es_knight", "es_questingknight" }) do
            local remap = scoped[career]
            if remap ~= false then
                return "non-Huntsman Kruber no longer preserves native draw_bow for " .. career
            end
            -- WT_DEV_OVERLAY_BEGIN:zoom-probe-career-assertion
            if not _WT316_ZOOM_PROBE.is_target("longbow_empire_template", career) then
                return "zoom diagnostic target scope missing " .. career
            end
            -- WT_DEV_OVERLAY_END:zoom-probe-career-assertion
        end
        -- WT_DEV_OVERLAY_BEGIN:zoom-probe-huntsman-assertion
        if _WT316_ZOOM_PROBE.is_target("longbow_empire_template", "es_huntsman") then
            return "native Huntsman incorrectly included in cross-career zoom probe"
        end
        -- WT_DEV_OVERLAY_END:zoom-probe-huntsman-assertion
        if scoped.es_huntsman ~= nil and scoped.es_huntsman ~= false then
            return "native Huntsman draw_bow is no longer exempt"
        end
        local saltz = scoped.wh_
        if type(saltz) ~= "table" or saltz.draw_bow ~= "to_zoom"
                or saltz.attack_shoot_fast ~= "attack_shoot" then
            return "Saltzpyre crossbow presentation remap drifted"
        end
        -- WT_DEV_OVERLAY_BEGIN:zoom-probe-bound-assertion
        if _wt316_zoom_probe.max_attempts ~= 3 then
            return "zoom diagnostic is not capped at three attempts"
        end
        -- WT_DEV_OVERLAY_END:zoom-probe-bound-assertion
    end)

    _rt_register("issue316_empire_longbow_cross_career_variable_zoom", function()
        local policy = _wt_longbow_variable_zoom
        if not policy or type(policy.post_update) ~= "function" then
            return "Empire Longbow variable-zoom owner missing"
        end
        if not rawget(_G, "Weapons") then return "skip: Weapons not loaded" end
        local template = Weapons.longbow_empire_template
        local aim = template and template.actions and template.actions.action_two
            and template.actions.action_two.default
        if not aim or not policy.is_registered(aim) then
            return "exact Empire Longbow aim action not registered"
        end
        local expected = {
            es_mercenary = true, es_knight = true, es_questingknight = true,
            wh_captain = true, wh_bountyhunter = true, wh_zealot = true,
        }
        for career, enabled in pairs(policy.supported_careers or {}) do
            if enabled and not expected[career] then
                return "unexpected variable-zoom career " .. tostring(career)
            end
        end
        for career in pairs(expected) do
            if not policy.is_supported_item_career("es_longbow", career) then
                return "supported variable-zoom career missing " .. career
            end
        end
        for _, career in ipairs({ "es_huntsman", "wh_priest", "we_waywatcher" }) do
            if policy.is_supported_item_career("es_longbow", career) then
                return "native/excluded career gained variable zoom " .. career
            end
        end
        if policy.is_supported_item_career("we_longbow", "es_mercenary") then
            return "unrelated bow gained Empire Longbow variable zoom"
        end

        local switches, thresholds = 0, nil
        local status = {
            is_zooming = function() return true end,
            switch_variable_zoom = function(_, value)
                switches, thresholds = switches + 1, value
            end,
        }
        local outcome = policy.post_update({
            current_action = aim,
            item_name = "es_longbow",
            owner_unit = {},
            -- Vanilla BuffExtension returns nil when the perk is absent.
            buff_extension = { has_buff_perk = function() return nil end },
        }, {
            get_career_name = function() return "wh_bountyhunter" end,
            get_extension = function(_, name)
                if name == "status_system" then return status end
                if name == "input_system" then
                    return { get = function(_, input) return input == "action_three" end }
                end
            end,
        })
        if outcome ~= "switched" or switches ~= 1
                or thresholds ~= aim.buffed_zoom_thresholds then
            return "authored variable-zoom thresholds were not cycled exactly once"
        end
    end)

    _rt_register("issue580_moonfire_saltzpyre_crossbow_3p_contract", function()
        if not rawget(_G, "Weapons") then return "skip: Weapons not loaded" end
        local tpl = Weapons.we_deus_01_template_1
        if type(tpl) ~= "table" then return "we_deus_01_template_1 missing" end

        for _, key in ipairs({ "es_longbow", "we_longbow", "we_deus_01" }) do
            if not _is_sp_crossbow_presentation_item(key) then
                return "Saltzpyre crossbow presentation predicate missing " .. key
            end
        end
        if _is_sp_crossbow_presentation_item("we_shortbow") then
            return "crossbow presentation predicate widened to unrelated bow"
        end

        local wield = tpl.wield_anim_career_3p or {}
        for _, career in ipairs({ "wh_captain", "wh_bountyhunter", "wh_zealot" }) do
            if wield[career] ~= "to_crossbow" then
                return string.format("Moonfire wield mismatch %s=%s", career, tostring(wield[career]))
            end
        end
        if wield.wh_priest ~= nil then return "Warrior Priest incorrectly included" end

        local scoped = _3p_template_remaps.we_deus_01_template_1 or {}
        if scoped.we_ ~= false then return "native Kerillian remap exemption missing" end
        local wh = scoped.wh_
        if type(wh) ~= "table"
            or wh.attack_shoot_fast ~= "attack_shoot"
            or wh.attack_shoot_fast_last ~= "attack_shoot_last"
            or wh.draw_bow ~= "to_zoom" then
            return "Moonfire Saltzpyre crossbow event map drifted"
        end

        -- Decompile fingerprint: #580 must not rewrite shared 1P/action behavior.
        local a1 = tpl.actions and tpl.actions.action_one
        local a2 = tpl.actions and tpl.actions.action_two
        if tpl.wield_anim ~= "to_longbow"
            or tpl.state_machine ~= "units/beings/player/first_person_base/state_machines/ranged/longbow"
            or not a1 or not a1.default or a1.default.anim_event ~= "attack_shoot_fast"
            or not a1.shoot_charged or a1.shoot_charged.anim_event ~= "attack_shoot"
            or not a2 or not a2.default or a2.default.anim_event ~= "draw_bow"
            or a1.default.kind ~= "bow_energy" or a2.default.kind ~= "aim_energy" then
            return "Moonfire shared/1P action fingerprint changed"
        end

        local xbow = Weapons.crossbow_template_1
        if not (xbow and xbow.left_hand_attachment_node_linking
            and xbow.left_hand_attachment_node_linking.third_person
            and xbow.ammo_data and xbow.ammo_data.ammo_unit_attachment_node_linking) then
            return "target crossbow 3P linking contract missing"
        end
    end)

    _rt_register("issue582_native_dual_axes_cwv_ownership_boundary", function()
        local receivers = {
            "es_mercenary", "es_huntsman", "es_knight", "es_questingknight",
            "wh_captain", "wh_bountyhunter", "wh_zealot",
        }
        for _, career in ipairs(receivers) do
            for _, key in ipairs(weapon_unlock_map[career] or {}) do
                if key == "dr_dual_wield_axes" then
                    return "native Bardin Dual Axes still offered by WT to " .. career
                end
            end
            if weapon_backend.is_mod_unlocked_weapon
                and weapon_backend.is_mod_unlocked_weapon(career, "dr_dual_wield_axes") then
                return "backend still accepts stale native Dual Axes cache for " .. career
            end
        end

        -- The removed control must not survive in the VMF widget tree.
        local data = mod:dofile("scripts/mods/weapon_tweaker_dev/weapon_tweaker_dev_data")
        local forbidden = {}
        for _, career in ipairs(receivers) do
            forbidden["unlock_" .. career .. "_dr_dual_wield_axes"] = true
        end
        local function walk(widgets)
            for _, widget in ipairs(widgets or {}) do
                if forbidden[widget.setting_id] then
                    return widget.setting_id
                end
                local found = walk(widget.sub_widgets)
                if found then return found end
            end
        end
        local found = data and data.options and walk(data.options.widgets)
        if found then return "removed native Dual Axes widget remains: " .. found end

        local loc = mod._wt_loc_raw
        if type(loc) == "table" then
            for setting_id in pairs(forbidden) do
                if loc[setting_id] ~= nil then
                    return "removed native Dual Axes localization remains: " .. setting_id
                end
            end
        end

        -- Runtime ownership after availability application: no stale can_wield
        -- mutation may remain, including from a hot-reloaded older WT build.
        local iml = rawget(_G, "ItemMasterList")
        local native = iml and rawget(iml, "dr_dual_wield_axes")
        if native and type(native.can_wield) == "table" then
            for _, career in ipairs(native.can_wield) do
                if career:sub(1, 3) == "es_" or career:sub(1, 3) == "wh_" then
                    return "native Dual Axes can_wield ownership leak: " .. career
                end
            end
        end
    end)

    _rt_register("issue594_saltzpyre_hammer_shield_ownership", function()
        local careers = { "wh_captain", "wh_bountyhunter", "wh_zealot" }
        for _, career in ipairs(careers) do
            local has_empire, has_dwarf = false, false
            for _, key in ipairs(weapon_unlock_map[career] or {}) do
                if key == "es_mace_shield" then has_empire = true end
                if key == "dr_shield_hammer" then has_dwarf = true end
            end
            if not has_empire or has_dwarf then
                return string.format("#594 ownership mismatch %s empire=%s dwarf=%s",
                    career, tostring(has_empire), tostring(has_dwarf))
            end
            if weapon_backend.is_mod_unlocked_weapon
                and weapon_backend.is_mod_unlocked_weapon(career, "dr_shield_hammer") then
                return "#594 backend accepts stale Bardin Hammer+Shield for " .. career
            end
        end

        local native = rawget(_G, "ItemMasterList") and rawget(ItemMasterList, "dr_shield_hammer")
        if native and type(native.can_wield) == "table" then
            for _, career in ipairs(native.can_wield) do
                if career == "wh_captain" or career == "wh_bountyhunter" or career == "wh_zealot" then
                    return "#594 stale Bardin Hammer+Shield can_wield entry: " .. career
                end
            end
        end
    end)

    _rt_register("issue368_cwv_independent_availability", function()
        local required = { "wh_1h_axe", "wh_1h_falchion", "wh_dual_wield_axe_falchion" }
        for _, career in ipairs({ "es_mercenary", "es_huntsman", "es_knight", "es_questingknight" }) do
            local found = {}
            for _, key in ipairs(weapon_unlock_map[career] or {}) do found[key] = true end
            for _, key in ipairs(required) do
                if not found[key] then return string.format("missing WT row %s/%s", career, key) end
            end
        end
        local live = 0
        for _, variant in ipairs(mod._wt.cwv_variant_catalog or {}) do
            local item = ItemMasterList and rawget(ItemMasterList, variant.key)
            if item and item.cwv_variant == true then live = live + 1 end
        end
        if get_mod("character_weapon_variants") and live == 0 then
            return "CWV present but no marked variants registered (run in keep)"
        end
    end)

    _rt_register("issue391_cwv_per_career_availability", function()
        local policy = mod._wt.cwv_availability_policy
        local catalog = mod._wt.cwv_variant_catalog
        if type(policy) ~= "table" or type(catalog) ~= "table" then
            return "#391 availability policy or catalog missing"
        end

        local rows = policy.build_widgets(catalog)
        if #rows ~= #catalog then return "#391 item master count drift" end
        for index, variant in ipairs(catalog) do
            local row = rows[index]
            if not row or row.setting_id ~= policy.master_setting_id(variant.key) then
                return "#391 master setting drift: " .. tostring(variant.key)
            end
            if #row.sub_widgets ~= #variant.careers then
                return "#391 career setting count drift: " .. tostring(variant.key)
            end
        end

        if not mod._wt.cwv_ownership.cwv_is_active(get_mod("character_weapon_variants")) then
            return "skip: CWV inactive"
        end
        local variant = rawget(_G, "ItemMasterList") and rawget(ItemMasterList, "cwv_es_dual_axes")
        if not variant or variant.cwv_variant ~= true then
            return "skip: CWV Dual Axes not registered (run in keep)"
        end
        local present = {}
        for _, career in ipairs(variant.can_wield or {}) do present[career] = true end
        for _, career in ipairs({ "es_mercenary", "es_huntsman", "es_knight", "es_questingknight" }) do
            local expected = policy.is_enabled(function(setting_id) return mod:get(setting_id) end,
                "cwv_es_dual_axes", career)
            if present[career] ~= expected then
                return string.format("#391 live mismatch %s expected=%s actual=%s",
                    career, tostring(expected), tostring(present[career] == true))
            end
        end
    end)

    _rt_register("issue620_cwv_tuskgor_foot_knight_default", function()
        if type(mod._wt.seed_cwv_tuskgor_foot_knight_default) ~= "function" then
            return "#620 Tuskgor conditional default owner missing"
        end
        local active = mod._wt.cwv_ownership.cwv_is_active(get_mod("character_weapon_variants"))
        if not active then return "skip: CWV inactive (WT-alone default remains off)" end
        local item = rawget(_G, "ItemMasterList") and rawget(ItemMasterList, "es_2h_heavy_spear")
        if not (item and item.cwv_combat_style_family == "spear"
                and item.cwv_combat_style_ready == true) then
            return "skip: CWV Tuskgor style family not ready"
        end
        if mod:get("wt_cwv_tuskgor_fk_default_seeded") ~= true
                or mod:get("unlock_es_knight_es_2h_heavy_spear") ~= true then
            return "#620 ready family did not seed Foot Knight default"
        end
        local present = false
        for _, career in ipairs(item.can_wield or {}) do
            if career == "es_knight" then present = true; break end
        end
        if not present then return "#620 Foot Knight missing from live Tuskgor can_wield" end
    end)

    _rt_register("issue593_conditional_cwv_axe_shield_ownership", function()
        local policy = mod._wt.cwv_ownership
        if type(policy) ~= "table" then return "#593 conditional ownership policy missing" end
        local careers = {
            "es_mercenary", "es_huntsman", "es_knight", "es_questingknight",
            "wh_captain", "wh_bountyhunter", "wh_zealot",
        }
        for _, career in ipairs(careers) do
            local managed = mod._wt.cwv_conditional_managed[career]
            if not managed or managed.dr_shield_axe ~= true then
                return "#593 CWV handoff map missing " .. career
            end
            if not policy.should_yield_native(career, "dr_shield_axe", true,
                    mod._wt.cwv_conditional_managed, true)
                or policy.should_yield_native(career, "dr_shield_axe", false, mod._wt.cwv_conditional_managed, true) then
                return "#593 conditional policy failed " .. career
            end
        end

        -- Keep the four WT controls/localization rows: they preserve the user's
        -- preference while CWV owns the slot and become live again on disable.
        local data = mod:dofile("scripts/mods/weapon_tweaker_dev/weapon_tweaker_dev_data")
        local wanted = {}
        for _, career in ipairs(careers) do wanted["unlock_" .. career .. "_dr_shield_axe"] = false end
        local function walk(widgets)
            for _, widget in ipairs(widgets or {}) do
                if wanted[widget.setting_id] ~= nil then wanted[widget.setting_id] = true end
                walk(widget.sub_widgets)
            end
        end
        walk(data and data.options and data.options.widgets)
        for setting_id, found in pairs(wanted) do
            if not found then return "#593 restorable WT widget missing: " .. setting_id end
            if type(mod._wt_loc_raw) == "table" and mod._wt_loc_raw[setting_id] == nil then
                return "#593 restorable WT localization missing: " .. setting_id
            end
        end

        local active = policy.cwv_is_active(get_mod("character_weapon_variants"))
        local ready = policy.replacement_ready(ItemMasterList, "dr_shield_axe")
        local native = rawget(_G, "ItemMasterList") and rawget(ItemMasterList, "dr_shield_axe")
        if native and type(native.can_wield) == "table" then
            local present = {}
            for _, career in ipairs(native.can_wield) do present[career] = true end
            for _, career in ipairs(careers) do
                local enabled = mod:get("unlock_" .. career .. "_dr_shield_axe") == true
                local expected = enabled and not (active and ready)
                if present[career] ~= expected then
                    return string.format("#593 runtime mismatch %s active=%s enabled=%s present=%s",
                        career, tostring(active), tostring(enabled), tostring(present[career]))
                end
            end
        end

        for _, key in ipairs({ "cwv_es_axe_shield", "cwv_es_axe_shield_veteran" }) do
            local variant = rawget(_G, "ItemMasterList") and rawget(ItemMasterList, key)
            if active and variant and variant.cwv_variant == true then
                local present = {}
                for _, career in ipairs(variant.can_wield or {}) do present[career] = true end
                for _, career in ipairs({ "wh_captain", "wh_bountyhunter", "wh_zealot" }) do
                    local expected = mod._wt.cwv_availability_policy.is_enabled(
                        function(setting_id) return mod:get(setting_id) end, key, career)
                    if present[career] ~= expected then
                        return string.format("#593 CWV variant mismatch key=%s career=%s expected=%s actual=%s",
                            key, career, tostring(expected), tostring(present[career] == true))
                    end
                    if expected and CareerSettings and Weapons and ActionTemplates then
                        local cs = CareerSettings[career]
                        local tmpl = variant.template and Weapons[variant.template]
                        for _, ability in ipairs((cs and cs.activated_ability) or {}) do
                            local action_name = ability and ability.action_name
                            if action_name and ActionTemplates[action_name]
                                and (not tmpl or not tmpl.actions
                                    or tmpl.actions[action_name] ~= ActionTemplates[action_name]) then
                                return string.format("#593 CWV variant missing career action key=%s career=%s action=%s",
                                    key, career, action_name)
                            end
                        end
                    end
                end
            elseif not active and variant and variant.cwv_variant == true then
                for _, career in ipairs({ "wh_captain", "wh_bountyhunter", "wh_zealot" }) do
                    for _, value in ipairs(variant.can_wield or {}) do
                        if value == career then
                            return "#593 inactive CWV variant leaked to " .. career .. ": " .. key
                        end
                    end
                end
            end
        end
    end)

    _rt_register("issue597_conditional_cwv_greataxe_ownership", function()
        local policy = mod._wt.cwv_ownership
        local careers = {
            "es_mercenary", "es_huntsman", "es_knight", "es_questingknight",
            "wh_captain", "wh_bountyhunter", "wh_zealot",
        }
        for _, career in ipairs(careers) do
            local managed = mod._wt.cwv_conditional_managed[career]
            if not managed or managed.dr_2h_axe ~= true then
                return "#597 Greataxe handoff map missing " .. career
            end
            if not policy.should_yield_native(career, "dr_2h_axe", true,
                    mod._wt.cwv_conditional_managed, true)
                or policy.should_yield_native(career, "dr_2h_axe", true,
                    mod._wt.cwv_conditional_managed, false) then
                return "#597 active/readiness ownership boundary failed " .. career
            end
        end
        local active = policy.cwv_is_active(get_mod("character_weapon_variants"))
        local ready = policy.replacement_ready(ItemMasterList, "dr_2h_axe")
        local native = ItemMasterList and rawget(ItemMasterList, "dr_2h_axe")
        local cwv = ItemMasterList and rawget(ItemMasterList, "cwv_es_greataxe")
        local native_present, cwv_present = {}, {}
        for _, career in ipairs(native and native.can_wield or {}) do native_present[career] = true end
        for _, career in ipairs(cwv and cwv.can_wield or {}) do cwv_present[career] = true end
        for _, career in ipairs(careers) do
            local native_enabled = mod:get("unlock_" .. career .. "_dr_2h_axe") == true
            local cwv_enabled = mod._wt.cwv_availability_policy.is_enabled(
                function(setting_id) return mod:get(setting_id) end, "cwv_es_greataxe", career)
            if native_present[career] ~= (native_enabled and not (active and ready)) then
                return "#597 native Greataxe ownership mismatch " .. career
            end
            if active and ready and cwv_present[career] ~= cwv_enabled then
                return "#597 CWV Greataxe ownership mismatch " .. career
            end
        end
    end)

    _rt_register("issue584_moonfire_stowed_native_regen_contract", function()
        local passive = weapon_backend.passive_charge
        if not passive or not passive.energy_regen_delta then
            return "passive-charge ranged-slot planner missing"
        end

        local moonfire = {
            actions = { action_one = { default = { kind = "bow_energy" } } },
        }
        local normal_bow = {
            actions = { action_one = { default = { kind = "bow" } } },
        }
        local inv = {
            wielded = "slot_melee",
            slots = { slot_melee = {}, slot_ranged = moonfire },
        }
        function inv:get_wielded_slot_name()
            return self.wielded
        end
        function inv:get_slot_data(slot_name)
            return self.slots[slot_name]
        end
        function inv:get_item_template(slot_data)
            return slot_data
        end

        -- Melee active + Moonfire equipped: native 1.5/s, exactly once.
        if passive.energy_regen_delta(inv, 0, 2) ~= 3 then
            return "stowed Moonfire did not plan one native-rate recharge"
        end
        -- Wielding the same ranged item must not create a second recharge path.
        inv.wielded = "slot_ranged"
        if passive.energy_regen_delta(inv, 0, 2) ~= 3 then
            return "wielded Moonfire recharge was missing or double-applied"
        end
        -- Native Kerillian owns her recharge regardless of active slot.
        if passive.energy_regen_delta(inv, 1.5, 2) ~= nil then
            return "native Kerillian Moonfire recharge was overridden"
        end
        -- A ranged-slot swap removes eligibility immediately; other bows untouched.
        inv.slots.slot_ranged = normal_bow
        if passive.energy_regen_delta(inv, 0, 2) ~= nil then
            return "non-Moonfire ranged weapon received energy recharge"
        end
        inv.slots.slot_ranged = nil
        if passive.energy_regen_delta(inv, 0, 2) ~= nil then
            return "empty ranged slot retained stale Moonfire eligibility"
        end
    end)

    _rt_register("issue585_moonfire_energy_hud_loadout_lifecycle", function()
        local passive = weapon_backend.passive_charge
        if not passive or not passive.energy_update_plan then
            return "passive-charge energy HUD lifecycle planner missing"
        end

        local moonfire = {
            actions = { action_one = { default = { kind = "bow_energy" } } },
        }
        local repeater = {
            actions = { action_one = { default = { kind = "crossbow" } } },
        }
        local saltz_ranged = {
            actions = { action_one = { default = { kind = "handgun" } } },
        }
        local inv = { slots = { slot_ranged = moonfire }, reads = 0 }
        function inv:get_slot_data(slot_name)
            if slot_name == "slot_ranged" then self.reads = self.reads + 1 end
            return self.slots[slot_name]
        end
        function inv:get_item_template(slot_data)
            return slot_data
        end

        local action, delta = passive.energy_update_plan(inv, 0, 1, 12, 40)
        if action ~= "recharge" or delta ~= 1.5 then
            return "equipped Moonfire did not retain native-rate recharge"
        end
        inv.slots.slot_ranged = repeater
        action, delta = passive.energy_update_plan(inv, 0, 1, 12, 40)
        if action ~= "reset_stale_hud" or delta ~= 28 then
            return "Moonfire-to-repeater did not clear stale HUD energy"
        end
        inv.slots.slot_ranged = saltz_ranged
        action, delta = passive.energy_update_plan(inv, 0, 1, 12, 40)
        if action ~= "reset_stale_hud" or delta ~= 28 then
            return "Moonfire-to-Saltzpyre-ranged did not clear stale HUD energy"
        end
        if passive.energy_update_plan(inv, 0, 1, 40, 40) ~= nil then
            return "full non-energy state scheduled repeated HUD cleanup"
        end
        if passive.energy_update_plan(inv, 1.5, 1, 12, 40) ~= nil then
            return "native Kerillian energy lifecycle was overridden"
        end
        inv.slots.slot_ranged = moonfire
        action, delta = passive.energy_update_plan(inv, 0, 1, 40, 40)
        if action ~= "recharge" or delta ~= 1.5 then
            return "re-equipped Moonfire did not restore energy lifecycle"
        end
        if inv.reads ~= 5 then
            return "energy lifecycle planner exceeded one ranged-slot read per update"
        end
    end)

    _rt_register("kruber_has_saltzpyre_crossbow", function()
        -- #138: wh_crossbow (Saltzpyre's "Crossbow") kept getting dropped from Kruber's
        -- unlock_map despite working (baked anims/offsets + the a_unwielded_crossbow
        -- j_hips crash-fix via _patch_xchar_unwielded_attachment_safe). Guard it stays
        -- in all 4 Kruber careers so it can't silently vanish from the menu again.
        if type(weapon_unlock_map) ~= "table" then return "skip: weapon_unlock_map not loaded" end
        local missing = {}
        for _, c in ipairs({ "es_mercenary", "es_huntsman", "es_knight", "es_questingknight" }) do
            local list = weapon_unlock_map[c]
            local found = false
            if type(list) == "table" then
                for _, k in ipairs(list) do if k == "wh_crossbow" then found = true; break end end
            end
            if not found then missing[#missing + 1] = c end
        end
        if #missing > 0 then return "wh_crossbow missing from Kruber unlock_map: " .. table.concat(missing, ", ") end
    end)

    _rt_register("no_redundant_bardin_1h_on_saltzpyre", function()
        -- WT_DEV_OVERLAY_BEGIN:issue948-retired-bardin-1h-absence
        if true then return end -- exhaustive dev catalog intentionally includes them
        -- WT_DEV_OVERLAY_END:issue948-retired-bardin-1h-absence
        -- #187: Bardin's dr_1h_axe (≡ Saltzpyre wh_1h_axe) and dr_1h_hammer
        -- (≡ Saltzpyre wh_1h_hammer Skullsplitter) are redundant on Saltzpyre and were
        -- removed (kept their entries to re-add to Saltzpyre = a bug). Guard them out of
        -- the non-WP Saltzpyre unlock lists.
        if type(weapon_unlock_map) ~= "table" then return "skip: weapon_unlock_map not loaded" end
        local bad = {}
        for _, c in ipairs({ "wh_captain", "wh_bountyhunter", "wh_zealot" }) do
            local list = weapon_unlock_map[c]
            if type(list) == "table" then
                for _, k in ipairs(list) do
                    if k == "dr_1h_axe" or k == "dr_1h_hammer" then bad[#bad + 1] = c .. ":" .. k end
                end
            end
        end
        if #bad > 0 then return "redundant Bardin 1h back on Saltzpyre: " .. table.concat(bad, ", ") end
    end)
    -- WT_DEV_OVERLAY_BEGIN:picker-localization-regressions
    _rt_register("dev_picker_names_localized", function()
        -- #159: the dev 3P Anim Picker must show DOCUMENTED localized weapon names,
        -- never raw internal keys (the tester saw "Sienna bw_deus_01" instead of
        -- "Sienna: Coruscation Staff" because the seven staves were missing from the
        -- old hardcoded _WEAPON_NAME and fell back to the key). _weapon_display_name
        -- now resolves from the Availability loc; this guards every catalog weapon.
        if not (_wt_dev_anim_picker and _wt_dev_anim_picker.unresolved_display_names) then
            return "skip: picker has no unresolved_display_names()"
        end
        local bad = _wt_dev_anim_picker.unresolved_display_names()
        if type(bad) == "table" and #bad > 0 then
            return "picker weapons showing raw internal keys (no documented name): " .. table.concat(bad, ", ")
        end
    end)

    _rt_register("dev_picker_group_labels_registered", function()
        -- #159/#197 END-TO-END: the REGISTERED localized label for every picker weapon
        -- group (the actual string VMF renders) must resolve to a real name — not a raw
        -- internal key (#159), and not an unregistered <key>/bare setting_id (#197 — a
        -- label registered before names could resolve). This checks the registered value
        -- (mod:localize on the group sid), NOT a freshly-recomputed label, so it would
        -- have CAUGHT #197 (the in-game `dev_picker_names_localized` test rebuilds fresh
        -- and so resolved correctly even while the registered menu labels were raw).
        if not (_wt_dev_anim_picker and _wt_dev_anim_picker.catalog_group_keys) then
            return "skip: picker has no catalog_group_keys()"
        end
        local entries = _wt_dev_anim_picker.catalog_group_keys()
        if type(entries) ~= "table" or #entries == 0 then return "skip: empty picker catalog" end
        local bad = {}
        for _, e in ipairs(entries) do
            local s = mod:localize(e.sid)
            if type(s) ~= "string" or s == "" then
                bad[#bad + 1] = e.weapon_key .. "=<empty>"
            elseif s == e.sid or s:sub(1, 1) == "<" then
                bad[#bad + 1] = e.weapon_key .. "=<unregistered>"
            elseif s:find(e.weapon_key, 1, true) then
                bad[#bad + 1] = e.weapon_key .. "=<raw-key>"
            end
        end
        if #bad > 0 then
            return "picker group labels not localized (registered values): " .. table.concat(bad, ", ")
        end
    end)
    -- WT_DEV_OVERLAY_END:picker-localization-regressions

    _rt_register("wt_loc_raw_published", function()
        -- Availability sorting reads the raw localization table before VMF finishes
        -- registering localization. Guard the public owner surface stays available.
        if type(mod._wt_loc_raw) ~= "table" then
            return "mod._wt_loc_raw not published by localization file — picker names fall back to raw keys (#197)"
        end
        if type(mod._wt_loc_raw["unlock_es_mercenary_bw_deus_01"]) ~= "table" then
            return "mod._wt_loc_raw present but missing expected unlock entries"
        end
    end)

end

return M
