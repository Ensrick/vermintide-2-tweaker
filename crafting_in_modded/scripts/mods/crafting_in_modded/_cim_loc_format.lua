-- _cim_loc_format.lua - pure Lua 5.1 format-directive validator for localization
-- strings (#1656). Engine-free: no VMF, no hooks, no call into the formatter.
--
-- Port of gui_tweaker_dev/scripts/mods/gui_tweaker_dev/_gut_loc_format.lua
-- (#1651). Each mod bundles its own Lua, so the code below the header is kept
-- identical to that file; qa/lua/tests/test_cim_regression_harness_1656.lua
-- pins the parity.
--
-- WHY THIS EXISTS. The `localization_format_safe` regression check used to probe
-- every loc value with `pcall(string.format, value)` and NO arguments. Legitimate
-- placeholders such as "Importing %s..." and "PAGE %d / %d" are consumed with
-- arguments (_cim_ranalds_browser.lua:45), so the bare probe fails on healthy
-- strings and failed the check (RainReligion, 0.8.135-dev keep run). Worse,
-- vanilla wraps the formatter (foundation/scripts/util/patches.lua:140-156): a
-- failed call logs a crashify exception and records the string in
-- INVALID_STRINGS (:152), after which every later call with that string returns
-- "<Invalid string format>" (:144-146) for the rest of the session. Running the
-- check therefore broke the Ranald's Gift browser messages it guards.
--
-- WHAT IT DOES. Scans the string the way lstrlib.c `scanformat` does in Lua 5.1,
-- without ever calling the formatter: "%%" is a literal percent; "%" followed by
-- optional flags ("-+ #0", at most five), an optional width (at most two digits),
-- an optional ".precision" (at most two digits) and one conversion character from
-- "cdiouxXeEfgGqs" is a directive; anything else is an unescaped percent. The
-- static gate qa/check_localization.ps1 adds one surface rule this scan mirrors:
-- a percent right after a digit ("10% chance") is a literal percentage and must
-- be written "10%%", even though "% c" would parse as a directive.
--
-- Consumers: the `localization_format_safe` check in _cim_regression_checks.lua
-- and the offline proof qa/lua/tests/test_cim_regression_harness_1656.lua.

local M = {}

M.FLAGS = "-+ #0"
M.MAX_FLAGS = 5                    -- lstrlib.c: "invalid format (repeated flags)"
M.MAX_DIGITS = 2                   -- lstrlib.c: "invalid format (width or precision too long)"
M.CONVERSIONS = "cdiouxXeEfgGqs"   -- lstrlib.c str_format switch, Lua 5.1
M.ESCAPE_HINT = "escape literal % as %%"

local ssub, sfind = string.sub, string.find

local function is_digit(c)
    return c ~= "" and c >= "0" and c <= "9"
end

local function count_while(s, j, n, accept)
    local count = 0
    while j <= n and accept(ssub(s, j, j)) do
        count = count + 1
        j = j + 1
    end
    return count, j
end

local function is_flag(c)
    return sfind(M.FLAGS, c, 1, true) ~= nil
end

-- Returns nil when `s` is safe to hand to the formatter (with the arguments its
-- directives ask for), else a reason naming the offending percent by position.
function M.validate(s)
    if type(s) ~= "string" then
        return "value is a " .. type(s) .. ", not a string"
    end
    local i, n = 1, #s
    while i <= n do
        local p = sfind(s, "%", i, true)
        if not p then
            return nil
        end
        local nxt = ssub(s, p + 1, p + 1)
        if nxt == "%" then
            i = p + 2
        elseif nxt == "" then
            return "trailing % at position " .. p .. " (" .. M.ESCAPE_HINT .. ")"
        elseif p > 1 and is_digit(ssub(s, p - 1, p - 1)) then
            return "literal % after a digit at position " .. p .. " (" .. M.ESCAPE_HINT .. ")"
        else
            local flags, j = count_while(s, p + 1, n, is_flag)
            if flags > M.MAX_FLAGS then
                return "invalid format (repeated flags) at position " .. p
            end
            local width
            width, j = count_while(s, j, n, is_digit)
            if width > M.MAX_DIGITS then
                return "invalid format (width or precision too long) at position " .. p
            end
            if ssub(s, j, j) == "." then
                local precision
                precision, j = count_while(s, j + 1, n, is_digit)
                if precision > M.MAX_DIGITS then
                    return "invalid format (width or precision too long) at position " .. p
                end
            end
            local conv = ssub(s, j, j)
            if conv == "" then
                return "unterminated directive at position " .. p .. " (" .. M.ESCAPE_HINT .. ")"
            end
            if not sfind(M.CONVERSIONS, conv, 1, true) then
                return "invalid option '%" .. conv .. "' at position " .. p .. " (" .. M.ESCAPE_HINT .. ")"
            end
            i = j + 1
        end
    end
    return nil
end

-- Scans a VMF localization table ({ key = { en = "...", de = "..." }, ... }).
-- Every string field of every entry is validated (each language runs through the
-- same formatter in VMF's safe_string_format). Keys are visited in sorted order so
-- the first reported offender is deterministic. Returns nil when clean, else one
-- reason line naming the key and language.
function M.scan(loc)
    if type(loc) ~= "table" then
        return "localization table is a " .. type(loc)
    end
    local keys = {}
    for k in pairs(loc) do
        keys[#keys + 1] = k
    end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    for _, k in ipairs(keys) do
        local entry = loc[k]
        if type(entry) == "table" then
            local langs = {}
            for lang in pairs(entry) do
                langs[#langs + 1] = lang
            end
            table.sort(langs, function(a, b) return tostring(a) < tostring(b) end)
            for _, lang in ipairs(langs) do
                local value = entry[lang]
                if type(value) == "string" then
                    local why = M.validate(value)
                    if why then
                        return 'loc key "' .. tostring(k) .. '" (' .. tostring(lang)
                            .. ") has invalid format string (" .. M.ESCAPE_HINT .. "): " .. why
                    end
                end
            end
        end
    end
    return nil
end

return M
