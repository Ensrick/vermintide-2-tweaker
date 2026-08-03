-- _ct_parry_cooldown_policy.lua — Pure #342 parry-cooldown neutralization core.
--
-- Operates on the REGISTERED runtime buff tables (global BuffTemplates plus the
-- DeusPowerUps registration index), never on the DeusPowerUpTemplates source
-- data: registration table.clone's the source per rarity
-- (deus_power_up_settings.lua:7146-7161 -> merged into the global BuffTemplates
-- via morris_buff_settings.lua:7310), so source-side strips are no-ops after
-- boot - the exact copy-vs-source trap _ct_boon_balance.lua documents for
-- reckless_swings and the #120 bomb cooldown.
--
-- Mechanism: zero the DURATION on the registered cooldown-BUFF templates
-- instead of nil'ing the proc's `cooldown_buff` field. Two decompile-verified
-- reasons the field-nil form is wrong:
--   * static_blade_on_timed_block re-reads template.cooldown_buff at proc END
--     and calls buff_extension:add_buff(cooldown_buff, ...) unconditionally
--     (morris_buff_settings.lua:4267/:4323-4325); with the field nil'd,
--     add_buff resolves BuffUtils.get_buff_template(nil) -> nil and crashes
--     indexing buff_template.buffs (buff_extension.lua:173-174,
--     buff_utils.lua:256-262).
--   * boon_skulls_03_on_parry never reads a template field at all - it
--     hard-codes "boon_skulls_03_cooldown" for both the gate and the re-arm
--     (morris_buff_settings.lua:4632/:4655), so there is no field to strip.
-- A zero-duration cooldown buff expires on the next buff-extension update
-- (buff_extension.lua:193 duration read at add time, :272 end_time =
-- start_time, :765 removed when end_time <= t), so every subsequent timed
-- block procs - behaviorally "no cooldown" without touching proc control flow.
--
-- Pure module: no VMF, no engine globals. Offline lock:
-- qa/lua/tests/test_ct_parry_cooldown_contract.lua.

local M = {
    -- boon_skulls_03's proc hard-codes this name
    -- (morris_buff_settings.lua:4632/:4655); there is no per-rarity or
    -- template-field indirection to derive it from.
    SKULLS_COOLDOWN_NAME = "boon_skulls_03_cooldown",
    STATIC_BLADE_NAME = "static_blade",
}

-- Zero every duration on one registered cooldown-buff template.
-- Returns "neutralized" | "already" | "unreadable".
function M.neutralize_cooldown(runtime_buffs, cd_name)
    local tpl = type(runtime_buffs) == "table" and cd_name and runtime_buffs[cd_name]
    local buffs = type(tpl) == "table" and tpl.buffs
    if type(buffs) ~= "table" or #buffs == 0 then
        return "unreadable"
    end
    local changed = false
    for _, b in ipairs(buffs) do
        if type(b) == "table" and b.duration and b.duration ~= 0 then
            b.duration = 0
            changed = true
        end
    end
    return changed and "neutralized" or "already"
end

-- Walk the game's own registration (DeusPowerUps[rarity][name].buff_name,
-- built by the rarity-pool loop at deus_power_up_settings.lua:7121-7176) to
-- find every registered static_blade runtime entry and the cooldown template
-- each one references. Never hard-codes the rarity list or the
-- "power_up_<name>_<rarity>" naming scheme. Returns an array of
-- { rarity, buff_name, cooldown_name } rows, or { rarity, buff_name, error }
-- rows for registered entries whose runtime template is unreadable.
function M.registered_static_blade_cooldowns(runtime_buffs, deus_power_ups)
    local out = {}
    if type(deus_power_ups) ~= "table" then
        return out
    end
    for rarity, entries in pairs(deus_power_ups) do
        local registered = type(entries) == "table" and entries[M.STATIC_BLADE_NAME]
        local buff_name = type(registered) == "table" and registered.buff_name
        if buff_name then
            local tpl = type(runtime_buffs) == "table" and runtime_buffs[buff_name]
            local buffs = type(tpl) == "table" and tpl.buffs
            if type(buffs) ~= "table" then
                out[#out + 1] = { rarity = rarity, buff_name = buff_name,
                    error = "registered runtime template unreadable" }
            else
                local found = false
                for _, b in ipairs(buffs) do
                    if type(b) == "table" and b.cooldown_buff then
                        found = true
                        out[#out + 1] = { rarity = rarity, buff_name = buff_name,
                            cooldown_name = b.cooldown_buff }
                    end
                end
                if not found then
                    out[#out + 1] = { rarity = rarity, buff_name = buff_name,
                        error = "no cooldown_buff field on runtime entry" }
                end
            end
        end
    end
    return out
end

-- Full strip: neutralize every cooldown template referenced by a registered
-- static_blade runtime entry, plus the hard-coded skulls cooldown.
-- Returns ok (boolean), summary { static_blade = rows, skulls, problems }.
function M.strip(runtime_buffs, deus_power_ups)
    local summary = { static_blade = {}, skulls = nil, problems = {} }
    if type(runtime_buffs) ~= "table" then
        summary.problems[#summary.problems + 1] = "global BuffTemplates unreadable"
        return false, summary
    end
    local entries = M.registered_static_blade_cooldowns(runtime_buffs, deus_power_ups)
    if #entries == 0 then
        summary.problems[#summary.problems + 1] =
            "no registered static_blade entries found in DeusPowerUps"
    end
    local seen = {}
    for _, e in ipairs(entries) do
        if e.error then
            summary.problems[#summary.problems + 1] = string.format(
                "%s (%s): %s", tostring(e.buff_name), tostring(e.rarity), e.error)
        elseif not seen[e.cooldown_name] then
            seen[e.cooldown_name] = true
            local result = M.neutralize_cooldown(runtime_buffs, e.cooldown_name)
            summary.static_blade[#summary.static_blade + 1] = {
                rarity = e.rarity, cooldown_name = e.cooldown_name, result = result }
            if result == "unreadable" then
                summary.problems[#summary.problems + 1] = string.format(
                    "cooldown template %s unreadable", tostring(e.cooldown_name))
            end
        end
    end
    summary.skulls = M.neutralize_cooldown(runtime_buffs, M.SKULLS_COOLDOWN_NAME)
    if summary.skulls == "unreadable" then
        summary.problems[#summary.problems + 1] = string.format(
            "cooldown template %s unreadable", M.SKULLS_COOLDOWN_NAME)
    end
    return #summary.problems == 0, summary
end

-- Verification core for the /ct_regression_test check
-- `parry_cooldowns_stripped_post_load`: returns nil when every registered
-- cooldown is fully neutralized, else a problem message. Unreadable tables are
-- a MESSAGE (= check failure), never a silent pass (#342 audit requirement).
function M.residual_report(runtime_buffs, deus_power_ups)
    if type(runtime_buffs) ~= "table" then
        return "global BuffTemplates unreadable - cannot verify parry-cooldown strip"
    end
    if type(deus_power_ups) ~= "table" then
        return "DeusPowerUps registration unreadable (morris DLC settings not loaded?)"
    end
    local problems = {}
    local entries = M.registered_static_blade_cooldowns(runtime_buffs, deus_power_ups)
    if #entries == 0 then
        problems[#problems + 1] = "no registered static_blade entries found in DeusPowerUps"
    end
    local function residual(cd_name)
        local tpl = runtime_buffs[cd_name]
        local buffs = type(tpl) == "table" and tpl.buffs
        if type(buffs) ~= "table" or #buffs == 0 then
            return string.format("cooldown template %s unreadable", tostring(cd_name))
        end
        for _, b in ipairs(buffs) do
            if type(b) == "table" and b.duration and b.duration ~= 0 then
                return string.format("%s still has duration=%s",
                    tostring(cd_name), tostring(b.duration))
            end
        end
        return nil
    end
    local seen = {}
    for _, e in ipairs(entries) do
        local problem
        if e.error then
            problem = string.format("%s (%s): %s",
                tostring(e.buff_name), tostring(e.rarity), e.error)
        elseif not seen[e.cooldown_name] then
            seen[e.cooldown_name] = true
            problem = residual(e.cooldown_name)
        end
        if problem then
            problems[#problems + 1] = problem
        end
    end
    if not seen[M.SKULLS_COOLDOWN_NAME] then
        local skulls_problem = residual(M.SKULLS_COOLDOWN_NAME)
        if skulls_problem then
            problems[#problems + 1] = skulls_problem
        end
    end
    if #problems > 0 then
        return table.concat(problems, "; ")
    end
    return nil
end

return M
