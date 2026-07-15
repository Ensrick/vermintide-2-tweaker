-- _cwv_deus_identity.lua -- preserve exact CWV owners through Chaos Wastes.
--
-- Vanilla DeusMechanism._setup_run converts an equipped item key through
-- DeusStartingWeaponTypeMapping. A missing custom key falls back to the
-- career's default weapon; mapping it to the inherited vanilla base avoids the
-- fallback but still erases the CWV template/item_type/skin family. This policy
-- instead creates one dedicated DeusWeapons row per concrete CWV owner whose
-- base_item is the CWV item itself. Property/trait generation is borrowed from
-- the vanilla Deus row for the authored base weapon; render identity is not.

local M = {}

local function copy_generation_contract(donor, item_key)
    return {
        base_item = item_key,
        property_table_name = donor.property_table_name,
        trait_table_name = donor.trait_table_name,
        baked_trait_combinations = donor.baked_trait_combinations,
        archetypes = donor.archetypes,
    }
end

function M.deus_key(item_key)
    if type(item_key) ~= "string" or item_key:sub(1, 4) ~= "cwv_" then return nil end
    return "deus_" .. item_key
end

function M.install(definitions, item_master_list, starting_mapping, deus_weapons,
        exact_identity_allowed)
    local report = {
        installed = 0, existing = 0, degraded = 0, skipped = {}, owners = {},
        exact_identity_allowed = exact_identity_allowed == true,
    }
    if type(definitions) ~= "table" or type(item_master_list) ~= "table"
            or type(starting_mapping) ~= "table" or type(deus_weapons) ~= "table" then
        report.skipped[1] = "deus_tables_unavailable"
        return report
    end

    for _, def in ipairs(definitions) do
        if type(def) == "table" and not def.skin_only and not def.cwv_retired then
            local item_key = def.item_key
            local owner = type(item_key) == "string" and rawget(item_master_list, item_key)
            local base_deus_key = type(def.base_weapon) == "string"
                and rawget(starting_mapping, def.base_weapon) or nil
            local donor = base_deus_key and rawget(deus_weapons, base_deus_key) or nil
            local dedicated_key = M.deus_key(item_key)

            if not dedicated_key or type(owner) ~= "table" then
                report.skipped[#report.skipped + 1] = tostring(item_key) .. ":owner_missing"
            elseif type(donor) ~= "table" then
                report.skipped[#report.skipped + 1] = item_key .. ":base_mapping_missing"
            else
                local existing = rawget(deus_weapons, dedicated_key)
                if type(existing) == "table" and existing.base_item == item_key then
                    report.existing = report.existing + 1
                else
                    rawset(deus_weapons, dedicated_key,
                        copy_generation_contract(donor, item_key))
                    report.installed = report.installed + 1
                end
                if exact_identity_allowed == true then
                    rawset(starting_mapping, item_key, dedicated_key)
                    report.owners[item_key] = dedicated_key
                else
                    -- Dedicated Deus keys are plain SharedState strings, not a
                    -- NetworkLookup, so a peer without CWV could not deserialize
                    -- one. Mixed/unknown parity borrows the vanilla Deus key;
                    -- the functional weapon family survives without adding a
                    -- custom identifier to vanilla transport.
                    rawset(starting_mapping, item_key, base_deus_key)
                    report.owners[item_key] = base_deus_key
                    report.degraded = report.degraded + 1
                end
            end
        end
    end

    return report
end

return M
