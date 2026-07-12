local mod = get_mod("enemy_tweaker")

-- _et_specials.lua — special spawns, per-difficulty
--
-- The user configures Max Specials Active, Max Same Type, per-special spawn
-- weight, and per-special disabled toggle independently for each difficulty
-- (Recruit / Veteran / Champion / Legend / Cataclysm 1/2/3). Defaults pulled
-- from VT2's SpecialDifficultyOverrides so unmodified sliders match vanilla.
--
-- Three SpecialsPacing hooks:
--   1) instance specials_by_slots — no override needed currently (cooldowns
--      not exposed in v0.3.1 UI), but the hook is in place for future use.
--   2) setup_functions.specials_by_slots — overrides CurrentSpecialsSettings
--      .max_specials and filters .breeds via per-breed disabled toggles,
--      restored after the original returns.
--   3) select_breed_functions.get_random_breed — applies weighted selection
--      and max_of_same override per the active difficulty.
--
-- Setting key convention (defined in enemy_tweaker_data.lua):
--   et_diff_<difficulty>_max_total
--   et_diff_<difficulty>_max_same
--   et_diff_<difficulty>_weight_<breed>
--   et_diff_<difficulty>_disabled_<breed>
--
-- Owned by: enemy_tweaker.lua entry point. No mod._et exports. mod._setting_key
-- is set by enemy_tweaker_data.lua (from the require'd breeds module) — the
-- `or` fallback covers a data-file load failure.

local ET = mod._et
local _dbg             = ET.dbg
local _dbg_alert       = ET.dbg_alert
local _hook_wrap_table = ET.hook_wrap_table

local _setting_key = mod._setting_key or function(diff_key, suffix, breed)
    if breed then return string.format("et_diff_%s_%s_%s", diff_key, suffix, breed) end
    return string.format("et_diff_%s_%s", diff_key, suffix)
end

local function _active_difficulty()
    -- Returns the current mission difficulty key (normal/hard/.../cataclysm_3)
    -- or "normal" if the manager isn't ready (mod load before any mission).
    local m = rawget(_G, "Managers")
    if not m or not m.state or not m.state.difficulty then return "normal" end
    local diff = m.state.difficulty:get_difficulty()
    return diff or "normal"
end

local function _enabled_specials_for(diff_key, source_breeds)
    -- Filter source_breeds by per-breed disabled toggle for the given difficulty.
    -- Always returns a fresh list — never mutates source.
    local out = {}
    for i = 1, #source_breeds do
        local name = source_breeds[i]
        if not mod:get(_setting_key(diff_key, "disabled", name)) then
            out[#out + 1] = name
        end
    end
    return out
end

if rawget(_G, "SpecialsPacing") then
    -- (1) Per-update hook — reserved for future cooldown overrides; currently no-op.

    -- (2) Setup-time: max_specials override + breeds filter.
    -- v0.6.0-dev: pcall result now triggers a mod:warning + graceful fallback
    -- instead of rethrowing via error(). The audit (PROJECT_STANDARDS § 4.1)
    -- flagged the rethrow as the worst-case protection gap — a Lua stack
    -- trace surfaces to the player as a kicked session instead of a "this
    -- setting broke specials" message.
    if SpecialsPacing.setup_functions and SpecialsPacing.setup_functions.specials_by_slots then
        _hook_wrap_table(SpecialsPacing.setup_functions, "specials_by_slots",
                "specials_by_slots", function(func, t, slots, method_data, state_data)
            local CSS = rawget(_G, "CurrentSpecialsSettings")
            if not CSS then
                _dbg_alert("specials_by_slots: CurrentSpecialsSettings nil — passthrough to vanilla")
                return func(t, slots, method_data, state_data)
            end

            local diff_key = _active_difficulty()
            local saved_breeds = CSS.breeds
            local saved_max    = CSS.max_specials

            local user_max = mod:get(_setting_key(diff_key, "max_total"))
            if user_max then CSS.max_specials = user_max end
            CSS.breeds = _enabled_specials_for(diff_key, saved_breeds)

            local ok, err = pcall(func, t, slots, method_data, state_data)

            CSS.breeds       = saved_breeds
            CSS.max_specials = saved_max

            if not ok then
                mod:warning("[et:specials] specials_by_slots inner errored (diff=%s): %s — settings restored, bailing to vanilla",
                    tostring(diff_key), tostring(err))
                _dbg_alert("specials_by_slots inner errored (diff=%s): %s — vanilla fallback",
                    tostring(diff_key), tostring(err))
                -- Fall through to vanilla with the original settings restored.
                return func(t, slots, method_data, state_data)
            end
        end)
    end

    -- (3) Per-pick: weighted selection + max_of_same override.
    if SpecialsPacing.select_breed_functions and SpecialsPacing.select_breed_functions.get_random_breed then
        _hook_wrap_table(SpecialsPacing.select_breed_functions, "get_random_breed",
                "get_random_breed", function(func, slots, specials_settings, method_data, state_data, ...)
            -- Preserve vanilla coordinated-attack override (set up in setup_functions
            -- when method_data.always_coordinated + same_breeds). Skipping this
            -- breaks coordinated attacks.
            if state_data and state_data.override_breed_name then
                _dbg("get_random_breed: vanilla coordinated-attack override active (%s) — passthrough",
                    tostring(state_data.override_breed_name))
                return func(slots, specials_settings, method_data, state_data, ...)
            end

            local diff_key = _active_difficulty()
            local pool = _enabled_specials_for(diff_key, specials_settings.breeds)
            if #pool == 0 then
                _dbg("get_random_breed: enabled pool empty for diff=%s — passthrough to vanilla",
                    tostring(diff_key))
                return func(slots, specials_settings, method_data, state_data, ...)
            end

            -- Weighted selection. Default weight is 1 → uniform random, matching
            -- vanilla. Setting any weight to 0 effectively disables that breed (same
            -- as the disabled checkbox, just a softer route).
            local total = 0
            local weights = {}
            for i, name in ipairs(pool) do
                local w = mod:get(_setting_key(diff_key, "weight", name)) or 1
                weights[i] = w
                total = total + w
            end
            if total <= 0 then
                -- All weights zero — fall back to uniform pick from the pool.
                return pool[math.random(1, #pool)]
            end

            -- Apply max_of_same override before the weighted pick so the loop respects it.
            local user_max_same = mod:get(_setting_key(diff_key, "max_same"))
            local max_same = user_max_same or method_data.max_of_same or 1
            if #pool == 1 then
                -- Only one eligible breed: skip the max_of_same constraint or we softlock.
                local r = math.random() * total
                local acc = 0
                for i, name in ipairs(pool) do
                    acc = acc + weights[i]
                    if r <= acc then return name end
                end
                return pool[#pool]
            end

            -- Count current alive-per-breed for max_of_same enforcement.
            local count = {}
            for i = 1, #slots do
                local b = slots[i].breed
                count[b] = (count[b] or 0) + 1
            end

            local max_tries = 20
            for _ = 1, max_tries do
                local r = math.random() * total
                local acc = 0
                for i, name in ipairs(pool) do
                    acc = acc + weights[i]
                    if r <= acc then
                        if (count[name] or 0) < max_same then
                            return name
                        end
                        break
                    end
                end
            end

            -- Last resort: return first eligible (max-of-same not yet hit), else first in pool.
            for _, name in ipairs(pool) do
                if (count[name] or 0) < max_same then return name end
            end
            return pool[1]
        end)
    end
end
