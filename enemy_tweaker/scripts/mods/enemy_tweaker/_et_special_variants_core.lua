-- _et_special_variants_core.lua -- pure issue #452 asset census.
--
-- The premium Versus skins are player cosmetic attachments, not AI breed base
-- units. This module only classifies the tables/assets a future custom-breed
-- implementation must compose. It performs no engine access or mutation.

local M = {}

M.CANDIDATES = {
    {
        id = "bile_blight_globadier",
        base_breed = "skaven_poison_wind_globadier",
        skin = "skaven_wind_globadier_skin_1001",
        behavior_boundary = "new bile ground/camera effects and bounded networked curse-stack buff",
    },
    {
        id = "shadowskulk_gutter_runner",
        base_breed = "skaven_gutter_runner",
        skin = "skaven_gutter_runner_skin_1001",
        behavior_boundary = "proximity visibility state plus pounce/downed damage policy",
    },
    {
        id = "mist_runner_packmaster",
        base_breed = "skaven_pack_master",
        skin = "skaven_pack_master_skin_1001",
        behavior_boundary = "hook-state speed/hoist timing and explicit stagger immunity",
    },
    {
        id = "festerblight_warpfire_thrower",
        base_breed = "skaven_warpfire_thrower",
        skin = "skaven_warpfire_thrower_skin_1001",
        behavior_boundary = "portable lingering fire area, detonation radius, and super-armor data",
    },
    {
        id = "putrescent_kin_ratling_gunner",
        base_breed = "skaven_ratling_gunner",
        skin = "skaven_ratling_gunner_skin_1001",
        behavior_boundary = "burst duration, cone spread, stamina damage, and super-armor data",
    },
}

function M.audit(env)
    env = env or {}
    local rows = {}
    local missing = 0
    local resident = 0

    for i = 1, #M.CANDIDATES do
        local c = M.CANDIDATES[i]
        local breed = type(env.breeds) == "table" and env.breeds[c.base_breed] or nil
        local actions = type(env.actions) == "table" and env.actions[c.base_breed] or nil
        local item = type(env.items) == "table" and env.items[c.skin] or nil
        local cosmetic = type(env.cosmetics) == "table" and env.cosmetics[c.skin] or nil
        local attachment = cosmetic and cosmetic.third_person_attachment
        local unit = type(attachment) == "table" and attachment.unit or nil
        local unit_resident
        if type(unit) == "string" and type(env.can_get_unit) == "function" then
            local ok, result = pcall(env.can_get_unit, unit)
            unit_resident = ok and result and true or false
        end

        local structure_ready = breed ~= nil and actions ~= nil and item ~= nil
            and cosmetic ~= nil and type(unit) == "string"
        if not structure_ready then missing = missing + 1 end
        if unit_resident then resident = resident + 1 end

        rows[#rows + 1] = {
            id = c.id,
            base_breed = c.base_breed,
            skin = c.skin,
            base_present = breed ~= nil,
            actions_present = actions ~= nil,
            item_present = item ~= nil,
            cosmetic_present = cosmetic ~= nil,
            attachment_unit = unit,
            unit_resident = unit_resident,
            structure_ready = structure_ready,
            player_attachment = type(unit) == "string"
                and unit:find("/dark_pact_skins/", 1, true) ~= nil or false,
            behavior_boundary = c.behavior_boundary,
        }
    end

    return rows, {
        candidates = #M.CANDIDATES,
        missing = missing,
        resident = resident,
    }
end

return M
