-- Engine-free coverage for the CWV husk (remote-player) render path cluster:
--   * issue 399 -- descriptor-primary ammo strip (positive identity, not an
--     item_key guess);
--   * issue 395 -- stale husk override-unit ledger drains on re-spawn;
--   * issue 660 -- retained-state [cwv:huskpath] postcondition (engine readback,
--     not setter success);
--   * consolidated husk hook singleton invariant (one hook per (Class, method)).
--
-- Two layers, matching the repo pattern (test_cwv_exact_appearance.lua):
--   1. Execute the PURE remote-husk transform policy against fixtures.
--   2. Grep the shipped source for the load-bearing wiring the runtime tests in
--      _cwv_regression_identity.lua also guard, plus a main-file hook count.
return function(H, repo_root)
    local mod_root = repo_root
        .. "/character_weapon_variants/scripts/mods/character_weapon_variants/"
    local policy_path = mod_root .. "_cwv_husk_transform_policy.lua"
    local main_path = mod_root .. "character_weapon_variants.lua"
    local Policy = assert(loadfile(policy_path))()

    local function read(path)
        local file = assert(io.open(path, "rb"))
        local source = file:read("*a")
        file:close()
        return source
    end

    local function count(haystack, needle)
        local n, pos = 0, 1
        while true do
            local s = haystack:find(needle, pos, true)
            if not s then break end
            n = n + 1
            pos = s + 1
        end
        return n
    end

    local function bound_policy(model_by_unit)
        return Policy.bind({
            find_def = function(key) return key and { item_key = key } or nil end,
            resolve_def = function() return nil end,
            resolve_field = function(def, field) return def[field] end,
            model_by_unit = model_by_unit or {},
        })
    end

    H.test("husk transform plan applies only when the def authors a channel", function()
        local policy = bound_policy()

        local offset_only = policy.plan("right",
            { right_hand_offset = { 0, 0, 0.5 } }, "resolved")
        H.equal(offset_only.should_apply, true)
        H.deep_equal(offset_only.offset, { 0, 0, 0.5 })
        H.equal(offset_only.scale, nil)

        local scale_3p = policy.plan("left",
            { left_hand_scale_3p = { 0.7, 0.7, 1.0 } }, "resolved")
        H.equal(scale_3p.should_apply, true)
        H.deep_equal(scale_3p.scale, { 0.7, 0.7, 1.0 })
        H.equal(scale_3p.scale_multiplier, nil)

        local relative_scale_3p = policy.plan("right",
            { right_hand_scale_multiplier_3p = { 0.5, 0.5, 0.5 } }, "exact_model")
        H.equal(relative_scale_3p.should_apply, true)
        H.equal(relative_scale_3p.scale, nil)
        H.deep_equal(relative_scale_3p.scale_multiplier, { 0.5, 0.5, 0.5 })

        -- A def with no transform field must NOT report should_apply -- otherwise
        -- the husk apply would call the transform primitive on nothing and the
        -- postcondition would log a spurious identity write.
        local none = policy.plan("right", { item_key = "cwv_plain" }, "resolved")
        H.equal(none.should_apply, false)

        H.equal(policy.plan("right", nil, "resolved"), nil)
    end)

    H.test("husk transform select declines an exact unit mismatch", function()
        local policy = bound_policy({ variant_right_3p = { item_key = "cwv_model" } })

        -- resolved spawn unit disagrees with the exact descriptor's hand unit:
        -- decline (never transform a unit the exact identity did not author).
        local def, reason = policy.select("right",
            { right_hand_unit = "variant_right_3p" }, nil, nil, "other_unit_3p")
        H.equal(def, nil)
        H.equal(reason, "exact_unit_mismatch")

        -- exact hand unit matches AND is a known model -> the model def wins.
        local model_def, model_reason = policy.select("right",
            { right_hand_unit = "variant_right_3p" }, nil, nil, "variant_right_3p")
        H.equal(model_reason, "exact_model")
        H.equal(model_def.item_key, "cwv_model")
    end)

    H.test("issue 399 husk ammo strip is descriptor-primary, not an item_key guess", function()
        -- The husk machinery moved to _cwv_husk_path.lua (OOP W5); the hook call
        -- site stays in the entry -- assert against combined entry + modules.
        local source = require("cwv_source").combined(repo_root)
        for _, marker in ipairs({
            "_om._husk_strip_cwv_ammo = function(item_data, owner_unit_3p, ammo_unit_3p, slot_name, item_units)",
            "(1) exact identity descriptor -- authoritative when present.",
            'if edef.no_ammo_unit then why = "descriptor" else return false end',
            "(2) skinless base+career fallback",
            "stripped inherited ammo 3P unit (base=%s career=%s via=%s)",
            "_om._husk_strip_cwv_ammo(item_data, owner_unit_3p, v_a3p, slot_name, item_units)",
        }) do
            H.truthy(source:find(marker, 1, true), "missing #399 ammo-strip anchor: " .. marker)
        end
    end)

    H.test("issue 395 husk stale override-unit ledger drains on re-spawn", function()
        local source = require("cwv_source").combined(repo_root)
        for _, marker in ipairs({
            '_om._husk_unit_ledger = setmetatable({}, { __mode = "k" })',
            "_om._husk_record_override_unit = function(owner_unit_3p, slot_name, hand, unit)",
            "[cwv:395] husk stale override unit released:",
            "_om._husk_record_override_unit(owner_unit_3p, slot_name, hand, weapon_unit_3p)",
        }) do
            H.truthy(source:find(marker, 1, true), "missing #395 stale-unit anchor: " .. marker)
        end
    end)

    H.test("issue 660 husk postcondition reads retained state back from the engine", function()
        local source = require("cwv_source").combined(repo_root)
        for _, marker in ipairs({
            "_om._husk_postcondition_log = function(owner_unit_3p, slot_name, hand, def, def_source, unit, unit_name)",
            "local v = Unit.local_scale(unit, 0)",
            "local v = Unit.local_position(unit, 0)",
            "local q = Unit.local_rotation(unit, 0)",
            "[cwv:huskpath] slot=%s hand=%s def=%s source=%s unit=%s retained_scale=(%s)",
			"local _HUSK_GENERAL_RETAINED_LOG_LIMIT = 64",
			"if _husk_retained_diag.count >= _husk_retained_diag.limit then return end",
			"retained_index=%d/%d",
			"_om._cwv_durable_crowbill_owner:annotate(unit, {",
            "_om._husk_postcondition_log(owner_unit_3p, slot_name, hand, def,",
        }) do
            H.truthy(source:find(marker, 1, true), "missing #660 postcondition anchor: " .. marker)
        end
        -- Guarded by Unit.alive + Unit.has_node before any node read.
        H.truthy(source:find("has0 = Unit.has_node(unit, 0)", 1, true),
            "husk postcondition missing Unit.has_node guard")
        H.truthy(source:find("scale_multiplier=%s", 1, true),
            "husk transform diagnostic must distinguish relative from absolute scale")
    end)

    H.test("husk hooks are consolidated to one site per (Class, method)", function()
        local source = read(main_path)
        -- #1159: spawn_inventory_unit moved to the musket equip-surface owner --
        -- the bayonet attach and the melee-stance transform are applied inline in
        -- that hook body, so the hook travelled with them. The husk branch inside
        -- it is unchanged and still dispatches here through _om. Assert on the
        -- WHOLE load chain, not one file: VMF drops a duplicate registration on
        -- the same (Class, method), so a re-added entry copy would shadow the
        -- owner and silently strand every husk-side fix.
        local chain = require("cwv_source").combined(repo_root)
        local equip_surface = read(mod_root .. "_cwv_musket_equip_surface.lua")
        H.equal(count(chain, 'mod:hook("GearUtils", "spawn_inventory_unit"'), 1,
            "GearUtils.spawn_inventory_unit must be hooked exactly once")
        H.equal(count(equip_surface, 'mod:hook("GearUtils", "spawn_inventory_unit"'), 1,
            "the musket equip-surface owner holds the spawn chokepoint")
        H.equal(count(source, 'mod:hook("GearUtils", "spawn_inventory_unit"'), 0,
            "entry must not re-register GearUtils.spawn_inventory_unit")
        -- Both husk adapter halves must still be dispatched from that hook body.
        H.truthy(equip_surface:find("_om._husk_adapter_pre(hand, item_template", 1, true),
            "spawn chokepoint still calls the pre-spawn husk adapter")
        H.truthy(equip_surface:find("_om._husk_adapter_post(hand, item_data", 1, true),
            "spawn chokepoint still calls the post-spawn husk adapter")
        H.equal(count(source, 'mod:hook("SimpleHuskInventoryExtension", "_wield_slot"'), 1,
            "SimpleHuskInventoryExtension._wield_slot must be hooked exactly once")
        -- #1159: start_weapon_fx moved to the husk-residency owner, beside the
        -- #280 force-loads it is the crash floor for. Still exactly one site,
        -- and the entry must hold no shadowing registration (VMF drops dupes).
        local residency = read(mod_root .. "_cwv_husk_residency_owner.lua")
        H.equal(count(residency, 'mod:hook("SimpleHuskInventoryExtension", "start_weapon_fx"'), 1,
            "SimpleHuskInventoryExtension.start_weapon_fx must be hooked exactly once")
        H.equal(count(source, 'mod:hook("SimpleHuskInventoryExtension", "start_weapon_fx"'), 0,
            "entry must not re-register SimpleHuskInventoryExtension.start_weapon_fx")
    end)
end
