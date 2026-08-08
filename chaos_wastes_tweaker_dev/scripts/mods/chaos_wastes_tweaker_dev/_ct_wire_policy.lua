-- _ct_wire_policy.lua -- pure presentation policy for the #426 peer-parity gate.
--
-- The #426 beacon (see _ct_meta_trait_boons.lua "Gate surfaces") already keeps
-- ct-modded boons and miracles OFF the wire whenever a lobby peer lacks ct.
-- That runtime safety is authoritative and never depends on this module.
--
-- What was still missing is the PRESENTATION half of the issue-371 doctrine that
-- the sibling axes already ship: while the gate is closed, the saved rows that
-- control gated content must read as unavailable rather than silently doing
-- nothing. career_tweaker closes the same gap with _crt_wire_policy.lua
-- (runtime_gate_spec / try_register_runtime_gate at :79 and :97); this module is
-- ct's copy of that contract, kept pure so qa/lua tests drive the exact shipped
-- decisions with no engine globals, no hooks, and no mod handle.
--
-- Owned by: _ct_meta_trait_boons.lua. Consumed via: one mod:dofile call.

local M = {}

-- Every saved row whose content registers a ct-owned index into
-- NetworkLookup.deus_power_up_templates / .buff_templates and therefore rides a
-- vanilla RPC to peers. Grouped by what the row controls so a future boon has an
-- obvious home. The umbrella row is included deliberately: with the gate closed
-- it cannot enable anything, so leaving it live would be the one control that
-- still looks actionable.
--
-- The commented-out activate_dormant_* group in the data file is intentionally
-- absent - those widgets do not exist at runtime, and a gate spec naming an
-- unknown setting id is rejected wholesale by runtime_gate_spec.
M.GATED_SETTING_IDS = {
    -- Umbrella over every trait-boon row below.
    "enable_boon_reworks",
    -- Trait boons: power_up_ct_boon_*_unique (CT_TRAIT_BOONS).
    "enable_boon_anath_raema_swiftness",
    "enable_boon_asuryan_wrath",
    "enable_boon_manann_tempest",
    "enable_boon_taal_twinned_arrow",
    "enable_boon_vauls_anvil",
    -- Miracles: ct_miracle_* buff templates.
    "tweak_miracle_of_isha_aegis",
    "tweak_miracle_of_isha_wounds",
    "tweak_miracle_of_ulric_persistent",
}

-- Player-facing reason shown on a gated row. No issue/lifecycle metadata and no
-- em dashes (CLAUDE.md non-negotiable 11 + LOCALIZATION_STANDARD section 13).
M.GATE_REASON = "Unavailable until every player in the lobby has Tweaker: Chaos Wastes."

-- Build the Mod Tweaker gate spec. Copies the id list so a later mutation of the
-- caller's table cannot retarget a live gate, and rejects a malformed list
-- outright rather than registering a partial gate that greys the wrong rows.
function M.runtime_gate_spec(mod_id, setting_ids, evaluate)
    if type(mod_id) ~= "string" or mod_id == ""
            or type(setting_ids) ~= "table" or type(evaluate) ~= "function" then
        return nil
    end
    local copied, seen = {}, {}
    for i = 1, #setting_ids do
        local setting_id = setting_ids[i]
        if type(setting_id) ~= "string" or setting_id == "" or seen[setting_id] then
            return nil
        end
        seen[setting_id] = true
        copied[#copied + 1] = setting_id
    end
    if #copied == 0 then return nil end
    return { mod_id = mod_id, setting_ids = copied, evaluate = evaluate }
end

-- Optional bridge. GUT is not a dependency: when it is absent this returns false
-- and the runtime gate above continues to carry the whole safety burden. Both
-- the dev and stable Mod Tweaker ids are probed because a tester may run either.
function M.try_register_runtime_gate(get_mod_fn, gate_id, spec)
    if type(get_mod_fn) ~= "function" or type(gate_id) ~= "string"
            or gate_id == "" or type(spec) ~= "table" then
        return false, "runtime-gate-arguments-invalid"
    end
    for _, gut_id in ipairs({ "gut_dev", "gut" }) do
        local ok, gut = pcall(get_mod_fn, gut_id)
        local tweaker = ok and type(gut) == "table" and gut.mod_tweaker or nil
        if type(tweaker) == "table"
                and type(tweaker.register_runtime_gate) == "function" then
            return tweaker:register_runtime_gate(gate_id, spec)
        end
    end
    return false, "mod-tweaker-unavailable"
end

return M
