-- Pure price policy for issue #467.  Engine rarity remains the boon registry
-- identity; the numeric price tier is deliberately independent so retiering a
-- shop card cannot corrupt DeusPowerUps/DeusPowerUpSetLookup membership.

local M = {}

local BASE_BY_RARITY = {
    event = 100,
    rare = 200,
    exotic = 250,
    unique = 300,
}

-- First empirical balance pass.  The catalog audit supplied the complete live
-- pool; these exceptions move clearly conditional/low-agency effects down and
-- unusually broad or run-defining effects up.  Unlisted boons retain their
-- vanilla rarity price, making new upstream boons safe and visible rather than
-- silently unbuyable.
local PRICE_BY_NAME = {
    -- Conditional / narrow rare boons.
    boon_aoe_02 = 150,
    boon_aoe_03 = 150,
    cluster_barrel = 150,
    deus_damage_reduction_on_incapacitated = 150,
    deus_standing_still_damage_reduction = 150,
    money_magnet = 150,
    respawn_speed = 150,

    -- Broad rare boons.
    ability_cooldown_reduction = 225,
    attack_speed = 225,
    barkskin = 225,
    crit_chance = 225,
    health = 225,
    natural_bond = 225,

    -- Conditional / narrow exotic boons.
    boulder_bro = 200,
    deus_barrel_power = 200,
    deus_power_up_quest_granted_test_01 = 200,
    deus_push_cost_reduction = 200,

    -- Broad or run-defining exotic boons.
    boon_supportbomb_crit_01 = 300,
    boon_supportbomb_healing_01 = 300,
    boon_supportbomb_strenght_01 = 300,
    deus_health_regeneration = 300,
    deus_infinite_dodges = 300,
    deus_max_health = 300,
    deus_second_wind = 300,
    deus_uninterruptable_attacks = 300,
    pyrotechnical_echo = 300,

    -- Premium unique boons.
    boon_careerskill_06 = 350,
    boonset_crit_set_bonus = 375,
    ct_boon_taal_twinned_arrow = 350,
    ct_boon_vauls_anvil = 375,
    deus_grenade_multi_throw = 350,
    deus_parry_damage_immune = 350,
    indomitable = 350,
}

local function round(value)
    if math and type(math.round) == "function" then return math.round(value) end
    return math.floor(value + 0.5)
end

function M.base(name, rarity)
    return PRICE_BY_NAME[name] or BASE_BY_RARITY[rarity]
end

function M.price(name, rarity, discount, percent)
    local base = M.base(name, rarity)
    if type(base) ~= "number" then return nil end
    local multiplier = tonumber(percent) or 100
    if multiplier < 0 then return nil end
    local scaled = round(base * multiplier / 100)
    local reduction = round(scaled * (tonumber(discount) or 0))
    return math.max(0, scaled - reduction)
end

function M.tier(name, rarity)
    local price = M.base(name, rarity)
    if not price then return nil end
    if price <= 150 then return "budget" end
    if price <= 225 then return "standard" end
    if price <= 300 then return "premium" end
    return "run-defining"
end

function M.audit_catalog(by_rarity)
    local report = { total = 0, priced = 0, missing = {}, overrides = 0 }
    if type(by_rarity) ~= "table" then return report end
    for rarity, rows in pairs(by_rarity) do
        if type(rows) == "table" then
            for _, row in ipairs(rows) do
                local name = type(row) == "table" and row.name or row
                report.total = report.total + 1
                if M.base(name, rarity) then
                    report.priced = report.priced + 1
                    if PRICE_BY_NAME[name] then report.overrides = report.overrides + 1 end
                else
                    report.missing[#report.missing + 1] = tostring(rarity) .. ":" .. tostring(name)
                end
            end
        end
    end
    table.sort(report.missing)
    return report
end

M.BASE_BY_RARITY = BASE_BY_RARITY
M.PRICE_BY_NAME = PRICE_BY_NAME

return M
