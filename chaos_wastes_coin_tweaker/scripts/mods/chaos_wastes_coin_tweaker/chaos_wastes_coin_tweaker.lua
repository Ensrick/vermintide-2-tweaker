local mod = get_mod("chaos_wastes_coin_tweaker")

-- ============================================================
-- Commands
-- ============================================================

mod:command("win", "Complete the current map", function()
    if Managers.state and Managers.state.game_mode then
        Managers.state.game_mode:complete_level()
    else
        mod:echo("No active game mode.")
    end
end)

-- ============================================================
-- Coin Multiplier
-- ============================================================

mod:hook(DeusRunController, "on_soft_currency_picked_up", function(func, self, ...)
    local args = { ... }
    local raw_amount = args[1]

    if type(raw_amount) == "number" then
        local multiplier = mod:get("coin_multiplier")
        args[1] = math.max(1, math.floor(raw_amount * multiplier))
        mod:info("Coin pickup: %d -> %d (x%.2f)", raw_amount, args[1], multiplier)
    end

    return func(self, unpack(args))
end)

-- ============================================================
-- Starting Coins
-- ============================================================

mod:hook_safe(DeusRunController, "init", function(self)
    local starting = mod:get("starting_coins")
    if starting and starting > 0 then
        -- on_soft_currency_picked_up will also apply the coin multiplier,
        -- so the actual coins granted = starting_coins * multiplier.
        if self.on_soft_currency_picked_up then
            self:on_soft_currency_picked_up(starting)
        end
    end
end)

-- ============================================================
-- Boon Options Count
-- ============================================================
-- generate_random_power_ups is called for both shrines (default 4 options)
-- and chests (default 3 options). We distinguish by the count arg value.

local SHRINE_DEFAULT = 4
local CHEST_DEFAULT  = 3

mod:hook(DeusPowerUpUtils, "generate_random_power_ups", function(func, ...)
    local args = { ... }

    local count_idx = nil
    for i, v in ipairs(args) do
        if type(v) == "number" and v >= 1 and v <= 10 then
            count_idx = i
            break
        end
    end

    if count_idx then
        local original = args[count_idx]
        local custom_count

        if original == SHRINE_DEFAULT then
            custom_count = mod:get("shrine_boon_count")
        elseif original == CHEST_DEFAULT then
            custom_count = mod:get("chest_boon_count")
        end

        if custom_count and custom_count ~= original then
            mod:info("Boon options: args[%d]=%d -> %d", count_idx, original, custom_count)
            args[count_idx] = custom_count
        end
    else
        mod:info("Boon options: could not find count arg, logging all: %s %s %s %s",
            tostring(args[1]), tostring(args[2]), tostring(args[3]), tostring(args[4]))
    end

    return func(unpack(args))
end)

-- ============================================================
-- Curse Disabling
-- ============================================================

mod:hook(Mutator, "activate", function(func, self, ...)
    local name = self._name
        or (type(self.name) == "function" and self:name())
        or self.mutator_name
        or ""

    if name ~= "" and mod:get("disable_curse_" .. name:gsub("^curse_", "")) then
        mod:info("Suppressed curse: %s", name)
        return
    end

    return func(self, ...)
end)
