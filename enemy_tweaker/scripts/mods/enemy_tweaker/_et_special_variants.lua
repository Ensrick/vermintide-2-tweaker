local mod = get_mod("enemy_tweaker")

-- _et_special_variants.lua -- #452 read-only runtime feasibility census.
--
-- Premium Versus skins are player attachment meshes. They cannot safely be
-- assigned as an AI breed's base_unit. Before a later phase creates five new
-- networked breed clones, this module proves which source rows and units exist
-- in the current retail build. Natural special spawns are observed through the
-- already-owned ConflictDirector hook; this module installs no hook, setting,
-- buff, attachment, or spawn.

local ET = mod._et
local Core = ET.SpecialVariantsCore
local rt_register = ET.rt_register
local _printf = rawget(_G, "printf") or function() end

local function _can_get_unit(path)
    local app = rawget(_G, "Application")
    if not app or type(app.can_get) ~= "function" then return false end
    return app.can_get("unit", path)
end

local function audit()
    return Core.audit({
        breeds = rawget(_G, "Breeds"),
        actions = rawget(_G, "BreedActions"),
        items = rawget(_G, "ItemMasterList"),
        cosmetics = rawget(_G, "Cosmetics"),
        behaviors = rawget(_G, "BreedBehaviors"),
        inventories = rawget(_G, "InventoryConfigurations"),
        breed_lookup = rawget(_G, "NetworkLookup")
            and rawget(_G, "NetworkLookup").breeds,
        can_get_unit = _can_get_unit,
    })
end

local function print_audit(reason)
    local rows, summary = audit()
    pcall(_printf,
        "[et:452] special-variants reason=%s candidates=%d missing=%d resident=%d behavior_changes=0 spawn_changes=0",
        tostring(reason), summary.candidates, summary.missing, summary.resident)
    for i = 1, #rows do
        local r = rows[i]
        pcall(_printf,
            "[et:452] %s base=%s actions=%s item=%s cosmetic=%s behavior=%s inventory=%s wire=%s attachment=%s resident=%s owner_nodes=%d player_attachment=%s boundary=%s",
            r.id, tostring(r.base_present), tostring(r.actions_present),
            tostring(r.item_present), tostring(r.cosmetic_present),
            tostring(r.behavior_present), tostring(r.inventory_present), tostring(r.wire_present),
            tostring(r.attachment_unit), tostring(r.unit_resident),
            r.owner_node_count, tostring(r.player_attachment), r.behavior_boundary)
    end
end

local _BY_BREED = {}
for i = 1, #Core.CANDIDATES do
    _BY_BREED[Core.CANDIDATES[i].base_breed] = Core.CANDIDATES[i]
end
local _observed = {}

-- Called after a naturally selected/spawned ordinary special has completed its
-- vanilla spawn. One row per breed per session proves whether the actual AI
-- skeleton supplies every owner/source node required by its premium player mesh.
-- No source nodes are queried because the attachment unit is deliberately not
-- spawned until this target-side compatibility gate passes.
local function observe_spawn(ai_unit, breed)
    local name = type(breed) == "table" and breed.name or nil
    local candidate = name and _BY_BREED[name] or nil
    if not candidate or _observed[name] then return end
    _observed[name] = true

    local cosmetics = rawget(_G, "Cosmetics")
    local cosmetic = cosmetics and cosmetics[candidate.skin]
    local attachment = cosmetic and cosmetic.third_person_attachment
    local nodes = Core.owner_nodes(attachment and attachment.attachment_node_linking)
    local unit_api = rawget(_G, "Unit")
    local present = 0
    local missing = {}
    for i = 1, #nodes do
        local ok, has = unit_api and type(unit_api.has_node) == "function"
            and pcall(unit_api.has_node, ai_unit, nodes[i])
        if ok and has then
            present = present + 1
        elseif #missing < 8 then
            missing[#missing + 1] = nodes[i]
        end
    end
    pcall(_printf,
        "[et:452] live breed=%s owner_nodes=%d present=%d missing=%d missing_sample=%s compatible=%s mutation=0",
        name, #nodes, present, #nodes - present,
        #missing > 0 and table.concat(missing, ",") or "none",
        tostring(#nodes > 0 and present == #nodes))
end

ET.special_variants_audit = audit
ET.SPECIAL_VARIANT_CANDIDATES = Core.CANDIDATES
ET.observe_special_variant_spawn = observe_spawn

-- Six bounded, log-only lines once per load. No chat pollution.
print_audit("mod_load")

rt_register("issue452_special_variant_assets_classified", function()
    local rows, summary = audit()
    if summary.candidates ~= 5 or #rows ~= 5 then
        return string.format("candidate count drifted: summary=%d rows=%d", summary.candidates, #rows)
    end
    if summary.missing > 0 then
        return string.format("%d/5 premium-special source structures are missing; inspect [et:452] lines", summary.missing)
    end
    for i = 1, #rows do
        local r = rows[i]
        if not r.player_attachment then
            return string.format("%s no longer resolves to a dark-pact player attachment; source re-audit required", r.id)
        end
        if r.owner_node_count == 0 then
            return string.format("%s attachment owner-node map is empty", r.id)
        end
    end
end)

rt_register("issue452_live_probe_bounded", function()
    if #Core.CANDIDATES ~= 5 then return "live probe cap drifted from five breeds" end
    if type(ET.observe_special_variant_spawn) ~= "function" then
        return "natural-spawn observer missing"
    end
end)

return {
    audit = audit,
    print_audit = print_audit,
}
