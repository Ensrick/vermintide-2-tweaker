-- Engine-free feasibility catalog for exposing Weave winds as Deus curses (#253).
local M = {}

M.CATALOG = {
    { wind = "metal",   mutator = "metal",   tier = "bridge_first", objective = false, resource = false },
    { wind = "fire",    mutator = "fire",    tier = "bridge_next",  objective = false, resource = false },
    { wind = "heavens", mutator = "heavens", tier = "preload",      objective = false, resource = true  },
    { wind = "life",    mutator = "life",    tier = "preload",      objective = false, resource = true  },
    { wind = "shadow",  mutator = "shadow",  tier = "preload",      objective = false, resource = true  },
    { wind = "death",   mutator = "death",   tier = "preload",      objective = false, resource = true  },
    { wind = "light",   mutator = "light",   tier = "objective",    objective = true,  resource = true  },
    { wind = "beasts",  mutator = "beasts",  tier = "objective",    objective = true,  resource = true  },
}

function M.inspect(wind_settings, mutator_templates, network_lookup, package_ready)
    local result = {
        total = #M.CATALOG,
        settings = 0,
        templates = 0,
        wire = 0,
        declared_packages = 0,
        context_required = #M.CATALOG,
        objective_required = 0,
        resource_required = 0,
        resources_ready = tonumber(package_ready) or 0,
        bridge_first = {},
        objective = {},
    }
    wind_settings = type(wind_settings) == "table" and wind_settings or {}
    mutator_templates = type(mutator_templates) == "table" and mutator_templates or {}
    local lookup = type(network_lookup) == "table" and network_lookup or {}
    for _, row in ipairs(M.CATALOG) do
        local settings = wind_settings[row.wind]
        if type(settings) == "table" and settings.mutator == row.mutator then
            result.settings = result.settings + 1
        end
        local template = mutator_templates[row.mutator]
        if type(template) == "table" then
            result.templates = result.templates + 1
            if type(template.packages) == "table" and #template.packages > 0 then
                result.declared_packages = result.declared_packages + 1
            end
        end
        if lookup[row.mutator] ~= nil then result.wire = result.wire + 1 end
        if row.objective then
            result.objective_required = result.objective_required + 1
            result.objective[#result.objective + 1] = row.wind
        end
        if row.resource then result.resource_required = result.resource_required + 1 end
        if row.tier == "bridge_first" then
            result.bridge_first[#result.bridge_first + 1] = row.wind
        end
    end
    table.sort(result.bridge_first)
    table.sort(result.objective)
    return result
end

return M
