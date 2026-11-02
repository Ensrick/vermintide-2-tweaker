local mod = get_mod("gut")

-- Explicit, bounded issue #389 verification entry point. Runtime contracts are
-- registered by _gut_mod_tweaker_contracts before this module is installed.
local M = {}

function M.install(checks, register, load_view)
    assert(type(register) == "function" and type(load_view) == "function",
        "issue 389 verifier requires the bound view supplier and registrar")
    local _rt_register = register
    local math = math

    assert(type(checks) == "table", "issue 389 verifier requires the runtime check list")

-- (#389) Exercise the actual owner-aware presentation seam, not only the detached step
-- resolver. A direct resolve({}, "cim", ...) check can pass while the merged Equipment
-- category still supplies "gut_equipment" in production, which is the official-v0.2.288
-- regression. Both presentation owners must derive CIM from category._owners here.
_rt_register("issue389_mod_tweaker_owner_aware_step", function()
    local ok_view, View = load_view()
    if not ok_view or type(View) ~= "table" then return "view module unavailable" end
    local view_resolve = View._resolve_owner_step
    if type(view_resolve) ~= "function" then
        return "standalone view owner-aware step resolver unavailable"
    end
    local view_snap = View._snap_and_clamp
    if type(view_snap) ~= "function" then
        return "standalone view snap helper unavailable"
    end
    local synthesize_equipment = View._synthesize_equipment
    if type(synthesize_equipment) ~= "function" then
        return "standalone Equipment synthesizer unavailable"
    end

    -- Recreate the real N>=2 Equipment topology, then drive the production row builder and
    -- the installed typed-edit callback. This is deliberately more than a detached resolver
    -- check: #389 existed because the helper was correct while its live caller supplied the
    -- synthetic category id. The probe is local-only and stages into a fake sink.
    local cim_owner = {
        get = function(_, setting_id)
            if setting_id == "base_power_level" then return 324 end
        end,
        localize = function(_, key) return tostring(key) end,
    }
    local base_power_node = {
        setting_id = "base_power_level",
        type = "numeric",
        title = "Base Power Level",
        range = { 0, 950 },
        decimals_number = 0,
        depth = 1,
    }
    local synthesized = synthesize_equipment({
        {
            mod_id = "cosmetics_tweaker",
            mod_obj = { localize = function(_, key) return tostring(key) end },
            enabled = true,
            _flat = true,
            widgets = { { setting_id = "cosmetics_header", type = "header" } },
        },
        {
            mod_id = "cim",
            mod_obj = cim_owner,
            enabled = true,
            _flat = true,
            widgets = {
                { setting_id = "cim_header", type = "header" },
                base_power_node,
            },
        },
    })
    local equipment = nil
    for _, category in ipairs(synthesized or {}) do
        if category.mod_id == "gut_equipment" then equipment = category; break end
    end
    if type(equipment) ~= "table" then return "live Equipment synthesis did not produce a merged category" end
    local owner = equipment._owners and equipment._owners.base_power_level
    if type(owner) ~= "table" or owner.mod_id ~= "cim" or owner.mod_obj ~= cim_owner then
        return "live Equipment synthesis lost Base Power Level ownership"
    end
    equipment._contract_probe = true -- never let synthetic evidence satisfy the live receipt.

    local stage_count = 0
    local fake_view = {
        _pending = {},
        _categories = { equipment },
        _selected = 1,
        _expanded = {},
        _rows = {},
        _tabs = {},
        _profile_buttons = {},
        _max_scroll = 0,
    }
    setmetatable(fake_view, { __index = View })
    fake_view.stage_set = function(self, category, setting_id, value)
        stage_count = stage_count + 1
        return View.stage_set(self, category, setting_id, value)
    end
    local row, row_error = View._build_node_row(fake_view, base_power_node, equipment, { 0, 0, 0 }, 1)
    if type(row) ~= "table" or type(row.content) ~= "table" then
        return "live Base Power row build failed: " .. tostring(row_error)
    end
    if row.content.step ~= 25 or row.content.min ~= 0 or row.content.max ~= 950
            or row.content.value ~= 324 then
        return "live Base Power row did not carry owner step, bounds, and current value"
    end
    if row._category ~= equipment or row._setting_id ~= "base_power_level"
            or row._mod_id ~= "gut_equipment" then
        return "live Base Power row lost its merged-category metadata"
    end
    if type(View._commit_edit) ~= "function" then return "installed typed-edit callback unavailable" end
    row.content.editing = true
    row.content.edit_str = "324"
    fake_view._editing_row = row
    View._commit_edit(fake_view, row)
    if stage_count ~= 1 or row.content.value ~= 325
            or not fake_view._pending.cim or fake_view._pending.cim.base_power_level ~= 325
            or fake_view._pending.gut_equipment ~= nil then
        return "installed typed-edit callback did not snap and stage Base Power 324 to 325"
    end

    -- Drive the installed pointer-input owner too. A real row that starts off-grid at 324
    -- must increment to 350, and a multi-frame release latch must not apply it twice.
    if type(View._handle_input) ~= "function" then return "installed pointer-input callback unavailable" end
    fake_view._pending = {}
    stage_count = 0
    local arrow_row, arrow_error = View._build_node_row(fake_view, base_power_node, equipment, { 0, 0, 0 }, 1)
    if type(arrow_row) ~= "table" then return "live arrow row build failed: " .. tostring(arrow_error) end
    if type(arrow_row.content) ~= "table" or type(arrow_row.content.inc) ~= "table"
            or type(arrow_row.content.dec) ~= "table" then
        return "live arrow row did not expose both pointer controls"
    end
    fake_view._rows = { arrow_row }
    arrow_row.content.inc.on_release = true
    View._handle_input(fake_view, nil)
    if arrow_row.content.value ~= 350 or stage_count ~= 1
            or not fake_view._pending.cim or fake_view._pending.cim.base_power_level ~= 350 then
        return "installed increment callback did not snap and stage Base Power 324 to 350"
    end
    View._handle_input(fake_view, nil)
    if arrow_row.content.value ~= 350 or stage_count ~= 1 then
        return "installed increment callback repeated on one latched release"
    end
    arrow_row.content.inc.on_release = false
    View._handle_input(fake_view, nil)
    if arrow_row._arrow_latched then return "installed arrow latch did not release" end

    fake_view._pending = {}
    stage_count = 0
    arrow_row.content.value = 324
    arrow_row.content.dec.on_release = true
    View._handle_input(fake_view, nil)
    if arrow_row.content.value ~= 300 or stage_count ~= 1
            or not fake_view._pending.cim or fake_view._pending.cim.base_power_level ~= 300 then
        return "installed decrement callback did not snap and stage Base Power 324 to 300"
    end

    local merged = {
        mod_id = "gut_equipment",
        _owners = {
            base_power_level = { mod_id = "cim" },
        },
    }
    local non_owner = { mod_id = "gut_equipment" }
    local normal = { mod_id = "ct" }
    local normal_dev = { mod_id = "ct_dev" }
    local normal_cim = { mod_id = "cim" }
    local merged_dev = {
        mod_id = "gut_equipment",
        _owners = { base_power_level = { mod_id = "cim_dev" } },
    }
    local missing_owner_id = {
        mod_id = "gut_equipment",
        _owners = { base_power_level = {} },
    }
    local foreign_owner = {
        mod_id = "gut_equipment",
        _owners = { base_power_level = { mod_id = "foreign_crafter" } },
    }
    local unrelated_cim_setting = {
        mod_id = "gut_equipment",
        _owners = { another_integer = { mod_id = "cim" } },
    }
    local cases = { { "standalone view", view_resolve } }
    -- The normal ESC/hotkey/chat route is standalone. Keep the registered but dormant
    -- Hero-state implementation in the same source contract so a future deliberate re-enable
    -- cannot revive the owner-boundary defect.
    local State = rawget(_G, "HeroViewStateModTweaker")
    local state_resolve = type(State) == "table" and State._resolve_owner_step
    if type(state_resolve) ~= "function" then
        return "keep-state owner-aware step resolver unavailable"
    end
    cases[#cases + 1] = { "keep-state", state_resolve }

    -- Build the real dormant-state row and drive its installed pointer adapter. Resolver-only
    -- coverage missed #389's production caller once already, and an off-grid stored value is
    -- the discriminating case for the min-anchored #164 contract.
    if type(State._build_node_row) ~= "function" or type(State._handle_input) ~= "function" then
        return "keep-state row/input adapter unavailable"
    end
    local state_stage_count = 0
    local fake_state = {
        _pending = {},
        _categories = { equipment },
        _selected = 1,
        _expanded = {},
        _rows = {},
        _tabs = {},
        _profile_buttons = {},
        _max_scroll = 0,
    }
    setmetatable(fake_state, { __index = State })
    fake_state.stage_set = function(self, category, setting_id, value)
        state_stage_count = state_stage_count + 1
        return State.stage_set(self, category, setting_id, value)
    end
    local state_row, state_row_error = State._build_node_row(
        fake_state, base_power_node, equipment, { 0, 0, 0 }, 1)
    if type(state_row) ~= "table" or type(state_row.content) ~= "table" then
        return "keep-state Base Power row build failed: " .. tostring(state_row_error)
    end
    if state_row.content.step ~= 25 or type(state_row.content.inc) ~= "table"
            or type(state_row.content.dec) ~= "table" then
        return "keep-state Base Power row did not carry owner step and pointer controls"
    end
    fake_state._rows = { state_row }
    state_row.content.inc.on_release = true
    State._handle_input(fake_state, nil)
    if state_row.content.value ~= 350 or state_stage_count ~= 1
            or not fake_state._pending.cim or fake_state._pending.cim.base_power_level ~= 350 then
        return "keep-state increment did not snap and stage Base Power 324 to 350"
    end
    state_row.content.inc.on_release = false
    state_row.content.value = 324
    fake_state._pending = {}
    state_stage_count = 0
    state_row.content.dec.on_release = true
    State._handle_input(fake_state, nil)
    if state_row.content.value ~= 300 or state_stage_count ~= 1
            or not fake_state._pending.cim or fake_state._pending.cim.base_power_level ~= 300 then
        return "keep-state decrement did not snap and stage Base Power 324 to 300"
    end

    -- Compose the actual active-view owner result with the actual snap helper at CIM's
    -- authored 0..950 bounds. This guards the configuration seam rather than retesting a
    -- copied formula. Off-grid stored values display unchanged until the user supplies input.
    local base_step = row.content.step
    local base_row = row.content
    if view_snap(base_row, 26) ~= 25 then return "Base Power 26 did not snap to 25" end
    if view_snap(base_row, 324) ~= 325 then return "Base Power 324 did not snap to 325" end
    if view_snap(base_row, 324 - base_step) ~= 300 then
        return "Base Power decrement from off-grid 324 did not land on 300"
    end
    if view_snap(base_row, 324 + base_step) ~= 350 then
        return "Base Power increment from off-grid 324 did not land on 350"
    end
    if view_snap(base_row, 949) ~= 950 then return "Base Power 949 did not snap to 950" end
    if view_snap(base_row, 1000) ~= 950 then return "Base Power did not clamp to authored max 950" end

    for _, case in ipairs(cases) do
        local label, resolve_owner = case[1], case[2]
        if resolve_owner({}, merged, "base_power_level", 0) ~= 25 then
            return label .. " did not resolve merged Equipment base_power_level through CIM"
        end
        if resolve_owner({}, merged_dev, "base_power_level", 0) ~= 25 then
            return label .. " did not resolve merged Equipment base_power_level through CIM Dev"
        end
        if resolve_owner({ content = { setting_id = "base_power_level" } }, merged, nil, 0) ~= 25 then
            return label .. " did not use the widget setting id for owner lookup"
        end
        if resolve_owner({}, normal_cim, "base_power_level", 0) ~= 25 then
            return label .. " regressed normal CIM category step resolution"
        end
        if resolve_owner({}, non_owner, "base_power_level", 0) ~= 1 then
            return label .. " applied CIM's override without a source-qualified setting owner"
        end
        if resolve_owner({}, missing_owner_id, "base_power_level", 0) ~= 1 then
            return label .. " applied CIM's override with a nil setting-owner id"
        end
        if resolve_owner({}, foreign_owner, "base_power_level", 0) ~= 1 then
            return label .. " applied CIM's override to a foreign setting owner"
        end
        if resolve_owner({}, unrelated_cim_setting, "another_integer", 0) ~= 1 then
            return label .. " applied Base Power's override to an unrelated CIM setting"
        end
        if math.abs(resolve_owner({}, foreign_owner, "base_power_level", 2) - 0.01) > 1e-9 then
            return label .. " regressed natural decimal fallback for a foreign owner"
        end
        if resolve_owner({}, normal, "starting_coins", 0) ~= 25 then
            return label .. " regressed Starting Coins step resolution"
        end
        if resolve_owner({}, normal, "cot_cost_amount", 0) ~= 25
                or resolve_owner({}, normal_dev, "cot_cost_amount", 0) ~= 25 then
            return label .. " regressed Trial Chest Cost step resolution"
        end
        if resolve_owner({ step = 10 }, merged, "base_power_level", 0) ~= 10 then
            return label .. " regressed explicit widget-step precedence"
        end
    end
end)


    mod:command("verify_gut_slider_step", "Verify Mod Tweaker's owner-aware Base Power step", function()
        local wanted = "issue389_mod_tweaker_owner_aware_step"
        local check = nil
        for _, candidate in ipairs(checks) do
            if candidate.name == wanted then
                check = candidate.fn
                break
            end
        end
        if type(check) ~= "function" then
            mod:echo("FAIL: %s -- check is not registered", wanted)
            if type(printf) == "function" then
                pcall(printf, "[gut:issue389] verify=FAIL reason=check_not_registered")
            end
            return
        end

        local ok, err = pcall(check)
        if ok and err == nil then
            mod:echo("PASS: %s", wanted)
            if type(printf) == "function" then
                pcall(printf, "[gut:issue389] verify=PASS")
            end
            return
        end

        local reason = (not ok and tostring(err)) or tostring(err)
        mod:echo("FAIL: %s -- %s", wanted, reason)
        if type(printf) == "function" then
            pcall(printf, "[gut:issue389] verify=FAIL reason=%s", reason)
        end
    end)

    return true
end

return M
