-- _cwv_greataxe_construction_owner.lua -- Closed native-template construction.
--
-- Owns only the Greataxe template cell and retained source/clone admission.
-- No damage profiles, scalar math, lookup IDs, preview, audit or generation writes.
-- Owned by: character_weapon_variants.lua entry point.
-- Consumed via: one manifest load, private core return/bootstrap/item handoff.
--
-- Guard contract (PROJECT_STANDARDS 8.6): the exact old-constructor/item/seed
-- oracle under #428 admitted a preserved foreign cwv_greataxe_template object.
-- The original core1177-1204 clones the native Greataxe and publishes that one
-- cell; denying NEW publication when its source/ownership is unproven preserves
-- foreign/user records instead. It does not repair them or make arbitrary
-- hot-reload consumers safe. No native action lifecycle is skipped here.
local M = {}
local ITEM, TEMPLATE, DONOR = "cwv_es_greataxe", "cwv_greataxe_template", "two_handed_axes_template_1"
local CAREERS = { "es_mercenary", "es_huntsman", "es_knight", "es_questingknight" }
function M.bind(graph, career, crit)
    local capture, intact, disjoint, commit = assert(graph.capture), assert(graph.intact),
        assert(graph.disjoint), assert(graph.commit)
    local career_capture, career_intact = assert(career.capture), assert(career.intact)
    local crit_capture, crit_intact, crit_include = assert(crit.capture), assert(crit.intact), assert(crit.include)
    return function(options)
        local weapons_for, clone, family = assert(options.weapons), assert(options.clone), options.family
        local read, write = options.read or rawget, options.write or rawset
        local owned, failure
        local function policy(proof)
            if type(family) ~= "table" or getmetatable(family) ~= nil
                    or rawget(family, "ITEM_KEY") ~= ITEM or rawget(family, "TEMPLATE_KEY") ~= TEMPLATE
                    or not rawequal(rawget(family, "DEFAULT_CAREERS"), proof.careers)
                    or not intact(proof.careers_snapshot) then return false end
            return true
        end
        local function retained(proof)
            return proof ~= nil and policy(proof)
                and rawequal(weapons_for(), proof.weapons)
                and rawequal(getmetatable(proof.weapons), proof.weapons_meta)
                and rawequal(rawget(proof.weapons, DONOR), proof.source)
                and rawequal(rawget(proof.weapons, TEMPLATE), proof.template)
                and crit_intact(proof.source_crit, true) and crit_intact(proof.template_crit, true)
                and career_intact(proof.source_snapshot) and career_intact(proof.template_snapshot)
        end
        local function construct(prepare)
            local weapons = weapons_for()
            if type(weapons) ~= "table" or rawget(weapons, TEMPLATE) ~= nil then return false, "template_destination_unproven" end
            local source = rawget(weapons, DONOR)
            if type(source) ~= "table" or getmetatable(source) ~= nil
                    or type(rawget(source, "actions")) ~= "table" or getmetatable(rawget(source, "actions")) ~= nil then
                return false, "native_template_unproven"
            end
            local careers = type(family) == "table" and rawget(family, "DEFAULT_CAREERS")
            if type(careers) ~= "table" or getmetatable(careers) ~= nil then return false, "career_policy_unproven" end
            local count = 0
            for key, value in next, careers do
                count = count + 1
                if type(key) ~= "number" or CAREERS[key] ~= value then return false, "career_policy_unproven" end
            end
            if count ~= #CAREERS then return false, "career_policy_unproven" end
            local proof = { weapons = weapons, weapons_meta = getmetatable(weapons), source = source,
                careers = careers, careers_snapshot = capture(careers, 8, 16) }
            assert(policy(proof), "Greataxe closed policy changed")
            local source_before = assert(capture(source, 4096, 32768), "Greataxe source graph unproven")
            proof.source_crit = assert(crit_capture(source, weapons, DONOR, true), "Greataxe source crit authority unproven")
            proof.source_snapshot = assert(career_capture(source, { role = "source", include = function(t, key)
                return crit_include(proof.source_crit, t, key)
            end }), "Greataxe source career authority unproven")
            local template = clone(source)
            assert(type(template) == "table" and getmetatable(template) == nil
                and type(rawget(template, "actions")) == "table" and getmetatable(rawget(template, "actions")) == nil,
                "Greataxe clone shape unproven")
            assert(disjoint(source_before, capture(template, 4096, 32768)), "Greataxe clone aliases source")
            proof.template_crit = assert(crit_capture(template, weapons, TEMPLATE, false), "Greataxe detached crit authority unproven")
            assert(type(prepare) == "function" and prepare(template) == true, "Greataxe preparation rejected")
            assert(crit_intact(proof.template_crit, false), "Greataxe detached crit changed during preparation")
            local wield = rawget(template, "wield_anim_career_3p")
            assert(type(wield) == "table" and getmetatable(wield) == nil, "Greataxe wield policy unproven")
            for _, name in ipairs(CAREERS) do assert(rawget(wield, name) == "to_2h_hammer", "Greataxe redirect changed") end
            assert(policy(proof) and intact(source_before), "Greataxe source changed during preparation")
            proof.template = template
            proof.template_snapshot = assert(career_capture(template,
                { role = "clone", source = source, token = TEMPLATE .. "<-" .. DONOR, include = function(t, key)
                    return crit_include(proof.template_crit, t, key)
                end }), "Greataxe clone career authority unproven")
            local changes = { { weapons, TEMPLATE, template, "template", before = nil } }
            local ok = commit(changes, function()
                assert(rawequal(weapons_for(), weapons) and rawequal(getmetatable(weapons), proof.weapons_meta)
                    and rawequal(rawget(weapons, DONOR), source) and intact(source_before) and policy(proof),
                    "Greataxe source changed before publication")
            end, function()
                assert(retained(proof), "Greataxe complete template readback rejected")
            end, read, write)
            if not ok then return false, "template_commit_rejected" end
            owned, failure = proof, nil
            return true
        end
        local C = {}
        function C.construct(prepare)
            if owned then local ok, ready = pcall(retained, owned); return ok and ready == true end
            local ok, ready, reason = pcall(construct, prepare)
            if ok and ready then return true end
            failure = ok and reason or tostring(ready)
            return false
        end
        function C.admit(def)
            if type(def) ~= "table" or rawget(def, "item_key") ~= ITEM or rawget(def, "template") ~= TEMPLATE then return false end
            local ok, ready = pcall(retained, owned)
            return ok and ready == true
        end
        function C.check()
            local ok, ready = pcall(retained, owned)
            if not ok or not ready then return "#428 Greataxe construction unproven: " .. tostring(failure or "retained_authority_lost") end
        end
        return C
    end
end
return M
