-- Offline proof for #1651: the `localization_format_safe` regression check used
-- to probe every loc value with `pcall(string.format, value)` and no arguments,
-- which rejects the #231 placeholder strings ("Page %d/%d") and, on RainReligion's
-- 0.2.354-dev build, surfaced as the VMF hook-chain error because Loremasters
-- Armoury hooks string.format. The replacement is a pure scan in
-- `_gut_loc_format.lua`. The module is loaded under an environment whose
-- string.format is the live hooked shape, and every call to it is counted; the
-- global is never swapped (incident #1643).
return function(H, repo_root)
    local base = repo_root .. "/gui_tweaker_dev/scripts/mods/gui_tweaker_dev/"
    local HOOKED = "scripts/mods/vmf/modules/core/hooks.lua:180: bad argument #2 to 'hook_chain' (no value)"

    local function read(path)
        local file = assert(io.open(path, "rb"))
        local source = file:read("*a")
        file:close()
        return source
    end

    -- The live build's string.format: VMF's internal hook closure (LA hooks the
    -- slot), which raised the exact message above on the paged label.
    local function hooked_string()
        local calls = 0
        local shadow = setmetatable({
            format = function() calls = calls + 1; error(HOOKED, 0) end,
        }, { __index = string })
        return shadow, function() return calls end
    end

    local function load_module()
        local chunk = assert(loadfile(base .. "_gut_loc_format.lua"))
        local shadow, calls = hooked_string()
        local env = setmetatable({ string = shadow }, { __index = _G })
        setfenv(chunk, env)
        return chunk(), calls
    end

    local function load_loc()
        return assert(loadfile(base .. "gui_tweaker_dev_localization.lua"))()
    end

    -- The 0.2.355-dev probe shape, under plain Lua 5.1.
    local function legacy_probe(value)
        return pcall(string.format, value)
    end

    H.test("GUT #1651 the 0.2.355-dev probe rejects the live paged loadout label", function()
        local loc = load_loc()
        H.equal(loc.gut_loadout_page_label.en, "Page %d/%d")
        local ok, err = legacy_probe(loc.gut_loadout_page_label.en)
        H.equal(ok, false, "a bare formatter probe cannot accept a placeholder string")
        H.truthy(tostring(err):find("bad argument #2", 1, true), tostring(err))
        local shadow = hooked_string()
        local hooked_ok, hooked_err = pcall(shadow.format, loc.gut_loadout_page_label.en)
        H.equal(hooked_ok, false)
        H.equal(hooked_err, HOOKED, "under the live hook the same defect reads as the hook_chain error")
    end)

    H.test("GUT #1651 validator accepts every legitimate directive without touching the formatter", function()
        local M, calls = load_module()
        for _, s in ipairs({
            "Page %d/%d", "Loadout %s", "+25%% headshot damage.", "Chance: %d%%",
            "%5.2f", "%-3d", "%+.1f", "%q", "%%", "100%% done", "no percent at all", "",
            "%x %X %o %u %c %e %E %g %G %i", "% d", "%#x", "%05.1f", "%99.99f",
        }) do
            H.equal(M.validate(s), nil, s)
        end
        H.equal(calls(), 0, "the validator must never call the formatter")
    end)

    H.test("GUT #1651 validator rejects unescaped percents with the escape hint", function()
        local M, calls = load_module()
        for _, s in ipairs({
            "%APPDATA%", "5%", "Grenadier % Chance", "10% chance", "50% off %s",
            "%", "trailing %", "%z", "%-", "%123d", "%.123f", "%------d", "%USERNAME%",
        }) do
            H.truthy(type(M.validate(s)) == "string", s .. " must be rejected")
        end
        H.truthy(M.validate("%APPDATA%"):find("invalid option '%A' at position 1", 1, true))
        H.truthy(M.validate("%APPDATA%"):find("escape literal % as %%", 1, true))
        H.truthy(M.validate("5%"):find("trailing % at position 2", 1, true))
        H.truthy(M.validate("10% chance"):find("literal % after a digit at position 3", 1, true))
        H.truthy(M.validate("%-"):find("unterminated directive", 1, true))
        H.truthy(M.validate("%123d"):find("width or precision too long", 1, true))
        H.truthy(M.validate("%------d"):find("repeated flags", 1, true))
        H.equal(M.validate(42), "value is a number, not a string")
        H.equal(calls(), 0)
    end)

    H.test("GUT #1651 the live loc table passes the pure scan and fails the legacy probe", function()
        local M, calls = load_module()
        local loc = load_loc()
        H.equal(M.scan(loc), nil, "every gut loc string must be format-safe")
        H.equal(calls(), 0)
        -- The legacy probe rejects the two #231 placeholder keys the live check tripped on.
        for _, key in ipairs({ "gut_loadout_page_label", "gut_loadout_slot_title" }) do
            H.equal((legacy_probe(loc[key].en)), false, key .. " must reproduce the 0.2.355-dev false FAIL")
        end
        -- The scan still catches the bug class the check exists for.
        loc.gut_rt1651_probe = { en = "Saved to %APPDATA%" }
        local why = M.scan(loc)
        H.truthy(why and why:find(
            'loc key "gut_rt1651_probe" (en) has invalid format string (escape literal % as %%)', 1, true),
            tostring(why))
        loc.gut_rt1651_probe = nil
        H.equal(M.scan(loc), nil)
    end)

    H.test("GUT #1651 scan visits every language and reports deterministically", function()
        local M = load_module()
        local first = M.scan({ zeta = { en = "5%" }, alpha = { en = "fine", de = "10% Chance" } })
        H.truthy(first and first:find('loc key "alpha" (de)', 1, true), tostring(first))
        H.equal(M.scan({ alpha = { en = "ok %s", note = 7 } }), nil)
        H.equal(M.scan({ alpha = "not a table" }), nil)
        H.truthy(M.scan(nil):find("localization table is a nil", 1, true))
    end)

    H.test("GUT #1651 the validator module never references the formatter", function()
        local code = read(base .. "_gut_loc_format.lua"):gsub("%-%-[^\n]*", "")
        H.equal(code:find("string.format", 1, true), nil, "no formatter call in the validator")
        H.equal(code:find("%.format%s*%("), nil, "no formatter alias call in the validator")
    end)

    H.test("GUT #1651 the live check routes through the pure scan", function()
        local main = read(base .. "gui_tweaker_dev.lua")
        local from = main:find('_rt_register("localization_format_safe"', 1, true)
        H.truthy(from, "localization_format_safe registration not found")
        local to = main:find("\nend)\n", from, true)
        H.truthy(to, "localization_format_safe block has no column-anchored end)")
        local block = main:sub(from, to)
        H.equal(block:find("string.format", 1, true), nil, "the check must not probe the formatter")
        H.truthy(block:find("_gut_loc_format.scan(loc)", 1, true), "the check must return the pure scan verdict")
        H.equal(select(2, main:gsub('scripts/mods/gui_tweaker_dev/_gut_loc_format"', "")), 1,
            "the validator has exactly one owner in the entry file")
    end)
end
