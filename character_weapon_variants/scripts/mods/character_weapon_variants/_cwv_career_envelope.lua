-- _cwv_career_envelope.lua -- Read-only finite career-action envelope.
--
-- Pins every unrelated raw graph cell while recognizing the exact shared
-- career install/release protocol on native sources and their private clones.
-- Canonical career body CONTENT is delegated to ActionTemplates identity;
-- this envelope does not attest semantic/gameplay safety of that shared body.
-- No mutation, repair, registry, global-library load or hook lives here.
-- Owned by: character_weapon_variants.lua entry point.
-- Consumed via: one manifest load and private by-value family factory binds.
local M = {}
local CLAIMS = "__vt2_tweaker_career_action_claims"
local CLONE = "__vt2_tweaker_career_action_clone_source"
local function career(key)
    return type(key) == "string" and key:sub(1, 14) == "action_career_"
end
local function plain(value)
    return type(value) == "table" and getmetatable(value) == nil
end
function M.bind(graph, canonical_for, resolve_mod)
    local capture, intact = assert(graph.capture), assert(graph.intact)
    assert(type(canonical_for) == "function", "career canonical getter missing")
    -- The resolver FUNCTION is captured now. Only these two literal IDs are
    -- queried later, since WT may initialize after CWV construction. Missing
    -- or throwing resolution cannot authorize a dynamic WT-owned transition.
    local function owners_now()
        local result = { character_weapon_variants = true }
        if type(resolve_mod) == "function" then
            for _, id in ipairs({ "wt", "wt_dev" }) do
                local ok, mod = pcall(resolve_mod, id)
                if ok and type(mod) == "table" then result["weapon_tweaker:" .. tostring(mod)] = true end
            end
        end
        return result
    end
    local function claim(row, value, owners)
        if not plain(row) or not rawequal(rawget(row, "value"), value) or type(rawget(row, "baseline_present")) ~= "boolean" then return false end
        local names, count = rawget(row, "owners"), 0
        if not plain(names) then return false end
        for key, enabled in next, names do
            count = count + 1
            if count > 3 or enabled ~= true or owners[key] ~= true then return false end
        end
        if count == 0 then return false end
        count = 0
        for key in next, row do
            count = count + 1
            if key ~= "value" and key ~= "owners" and key ~= "baseline_present" then return false end
        end
        return count == 3
    end
    local function copy_claim(row)
        if not plain(row) then return nil end
        local names = rawget(row, "owners")
        if not plain(names) then return nil end
        local result = { value = rawget(row, "value"), baseline_present = rawget(row, "baseline_present"), owners = {} }
        local count = 0
        for key, enabled in next, names do count = count + 1; if count > 3 then return nil end; result.owners[key] = enabled end
        for key in next, row do if key ~= "value" and key ~= "owners" and key ~= "baseline_present" then return nil end end
        return result
    end
    local function make(template, options)
        options = options or {}
        if type(template) ~= "table" or (options.role ~= "source" and options.role ~= "clone") then return nil end
        local actions, canonical = rawget(template, "actions"), canonical_for()
        if type(actions) ~= "table" or type(canonical) ~= "table" then return nil end
        if options.role == "clone" and (type(options.source) ~= "table" or type(options.token) ~= "string") then return nil end
        local claims, rows, count = rawget(template, CLAIMS), {}, 0
        for key, value in next, actions do if career(key) then
            count = count + 1; if count > 64 then return nil end
            local snapshot = capture(value, 256, 2048)
            if not snapshot then return nil end
            local source_actions = options.source and rawget(options.source, "actions")
            local expected = rawget(canonical, key)
            rows[key] = { value = value, snapshot = snapshot,
                canonical_value = rawequal(value, expected) and expected or nil,
                inherited_value = type(source_actions) == "table" and rawequal(rawget(source_actions, key), expected) and expected or nil,
                initial_claim = type(claims) == "table" and copy_claim(rawget(claims, key)) or nil }
        end end
        local claim_snapshot = type(claims) == "table" and capture(claims, 512, 4096)
        if claims ~= nil and not claim_snapshot then return nil end
        local include = options.include
        local base = capture(template, 4096, 32768, function(t, key)
            if rawequal(t, template) and (key == CLAIMS or key == CLONE) then return false end
            if rawequal(t, actions) and career(key) then return false end
            return not include or include(t, key)
        end)
        if not base then return nil end
        return { template = template, actions = actions, canonical = canonical, role = options.role,
            source = options.source, token = options.token, marker = rawget(template, CLONE),
            claims = claims, claim_snapshot = claim_snapshot, rows = rows, base = base }
    end
    local function valid(proof)
        if not proof or not intact(proof.base) or not rawequal(canonical_for(), proof.canonical) then return false end
        local template, actions, canonical = proof.template, proof.actions, proof.canonical
        local marker, claims = rawget(template, CLONE), rawget(template, CLAIMS)
        local same = rawequal(marker, proof.marker) and rawequal(claims, proof.claims)
            and (claims == nil or intact(proof.claim_snapshot))
        for name, row in next, proof.rows do
            local canonical_same = row.canonical_value and rawequal(rawget(canonical, name), row.canonical_value)
            if row.canonical_value and not canonical_same then return false end
            if not rawequal(rawget(actions, name), row.value) or (not canonical_same and not intact(row.snapshot)) then same = false end
        end
        for name in next, actions do if career(name) and not proof.rows[name] then same = false end end
        -- Unchanged native rows are pinned exactly, not invented canonical.
        if same then return true end
        if proof.role == "source" then
            if not rawequal(marker, proof.marker) then return false end
        elseif not rawequal(marker, proof.marker) and not rawequal(marker, proof.token) then return false end
        if claims ~= nil and not plain(claims) then return false end
        local owners, count = owners_now(), 0
        local function current_claim(name, value)
            local row = claims and rawget(claims, name)
            return row, claim(row, value, owners)
        end
        for name, initial in next, proof.rows do
            local value, expected = rawget(actions, name), rawget(canonical, name)
            local row, claimed = current_claim(name, value)
            if rawequal(value, initial.value) and ((initial.canonical_value ~= nil and rawequal(initial.canonical_value, expected)) or intact(initial.snapshot)) then
                if row ~= nil and (not rawequal(value, expected) or not claimed) then return false end
            else
                local prior = initial.initial_claim
                if rawequal(value, initial.value) then return false end
                local removable = prior and prior.baseline_present == false and rawequal(expected, initial.value)
                    and ((initial.canonical_value ~= nil and rawequal(initial.canonical_value, expected)) or intact(initial.snapshot))
                    and claim(prior, expected, owners)
                if value == nil then
                    if not removable or row ~= nil then return false end
                else
                    local inherited = proof.role == "clone" and rawequal(marker, proof.token)
                        and rawequal(initial.inherited_value, expected)
                    if not inherited or type(expected) ~= "table" or not rawequal(value, expected)
                            or (row ~= nil and not claimed) then return false end
                end
            end
        end
        for name, value in next, actions do if career(name) then
            count = count + 1; if count > 64 then return false end
            if not proof.rows[name] then
                local expected = rawget(canonical, name)
                local row, claimed = current_claim(name, value)
                if type(expected) ~= "table" or not rawequal(value, expected) or not claimed
                        or row.baseline_present ~= false then return false end
            end
        end end
        count = 0
        for name, row in next, claims or {} do
            count = count + 1; if count > 64 or not career(name) then return false end
            local value, expected = rawget(actions, name), rawget(canonical, name)
            if type(expected) ~= "table" or not rawequal(value, expected) or not claim(row, value, owners) then return false end
            local initial = proof.rows[name]
            if initial and initial.initial_claim == nil and rawequal(value, initial.value)
                    and row.baseline_present ~= true then return false end
        end
        return true
    end
    return { capture = make, intact = valid }
end
return M
