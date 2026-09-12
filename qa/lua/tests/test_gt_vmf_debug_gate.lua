-- Issue #169 (gt half): the heavy dump triggers in _gt_debug_probes.lua gated on
-- the RETIRED per-mod `enable_debug_logging` key, which no gt data file declares,
-- so the gate was permanently false. The replacement gates on VMF's own logging
-- state, mirroring vmf/modules/core/logging.lua:139+146: debug emission is
-- enabled only when `logging_mode == "custom"` and `output_mode_debug > 0`.
--
-- Two locks:
--   1. Behavioral: load the PRODUCTION _gt_debug_probes.lua of every stream that
--      carries the VMF predicate and drive mod._gt_vmf_debug_enabled /
--      mod._dbg_on through the VMF semantics table (default mode off, custom+0
--      off, custom+positive on, VMF absent off).
--   2. Contract: no Dev-loaded file may EXECUTE the retired key. Stable
--      general_tweaker keeps exactly one pinned read in _gt_debug_probes.lua
--      until its user-authorized promotion (the same promotion debt that
--      check_logging.ps1 pins on path + exact text); every other stable-loaded
--      file must be clean. The repository PowerShell logging scanner
--      additionally owns the multiline/widget and quoted-prose contract.
--
-- Promotion tripwire: while a stream has `vmf_predicate = false`, its pinned
-- read must still exist. The promotion that ports the Dev predicate fails here
-- until it flips the flag (enabling the behavioral locks for that stream) and
-- deletes the matching `$legacyRetiredDebugKeyDebt` entry in check_logging.ps1.
local STREAMS = {
    { name = "general_tweaker", vmf_predicate = false, pinned_owner = "_gt_debug_probes" },
    { name = "general_tweaker_dev", vmf_predicate = true },
}
local PINNED_READ = 'return mod:get("enable_debug_logging") == true'

return function(H, repo_root)
    for _, spec in ipairs(STREAMS) do
    local stream = spec.name
    local base = repo_root .. "/" .. stream .. "/scripts/mods/" .. stream .. "/"

    local function load_probes(vmf_mod)
        local mod = {
            get = function(_, key)
                assert(key ~= "enable_debug_logging", "retired per-mod read")
                return nil
            end,
            set = function(_, key)
                assert(key ~= "enable_debug_logging", "retired per-mod write")
            end,
            hook = function() end,
            hook_safe = function() end,
            command = function() end,
            echo = function() end,
            info = function() end,
            debug = function() end,
            warning = function() end,
            error = function() end,
        }
        local saved_get_mod = rawget(_G, "get_mod")
        local saved_printf = rawget(_G, "printf")
        -- Keep the fake get_mod installed for the caller's assertions: the
        -- helper resolves get_mod("VMF") at CALL time, not load time. The
        -- caller must invoke restore() when done.
        local function restore()
            rawset(_G, "get_mod", saved_get_mod)
            rawset(_G, "printf", saved_printf)
        end
        local ok, err = pcall(function()
            rawset(_G, "get_mod", function(name)
                if name == "VMF" then return vmf_mod end
                return mod
            end)
            rawset(_G, "printf", function() end)
            -- Loading, compilation failure and execution share one cleanup path.
            local chunk = assert(loadfile(base .. "_gt_debug_probes.lua"))
            chunk()
        end)
        if not ok then
            restore()
            error(err, 0)
        end
        return mod, restore
    end

    local function fake_vmf(logging_mode, output_mode_debug)
        return {
            get = function(_, key)
                if key == "logging_mode" then return logging_mode end
                if key == "output_mode_debug" then return output_mode_debug end
                error("unexpected VMF setting read: " .. tostring(key))
            end,
        }
    end

    if spec.vmf_predicate then
        H.test(stream .. " #169 dump gate follows VMF custom-mode debug state", function()
            local mod, restore = load_probes(fake_vmf("custom", 3))
            local ok, err = pcall(function()
                H.equal(type(mod._gt_vmf_debug_enabled), "function")
                H.equal(type(mod._dbg_on), "function")
                -- logging.lua:139: debug level counts only in custom mode.
                H.equal(mod._dbg_on(), true)
                -- Injectable seam: the same helper, explicit VMF object.
                H.equal(mod._gt_vmf_debug_enabled(fake_vmf("custom", 1)), true)
                H.equal(mod._gt_vmf_debug_enabled(fake_vmf("custom", 2)), true)
                -- logging.lua:146: enabled requires level > 0.
                H.equal(mod._gt_vmf_debug_enabled(fake_vmf("custom", 0)), false)
                H.equal(mod._gt_vmf_debug_enabled(fake_vmf("custom", -1)), false)
                H.equal(mod._gt_vmf_debug_enabled(fake_vmf("custom", nil)), false)
                -- Default mode: the custom levels are ignored, debug falls to 0.
                H.equal(mod._gt_vmf_debug_enabled(fake_vmf("default", 3)), false)
                H.equal(mod._gt_vmf_debug_enabled(fake_vmf(nil, 3)), false)
                -- Non-numeric junk from a corrupt save fails closed, not loud.
                H.equal(mod._gt_vmf_debug_enabled(fake_vmf("custom", "x")), false)
            end)
            restore()
            if not ok then error(err, 0) end
        end)

        H.test(stream .. " #169 dump gate fails closed when VMF is unreachable", function()
            local mod, restore = load_probes(nil)
            local ok, err = pcall(function()
                H.equal(mod._dbg_on(), false)
                H.equal(mod._gt_vmf_debug_enabled(nil), false)
                H.equal(mod._gt_vmf_debug_enabled({}), false)
                H.equal(mod._gt_vmf_debug_enabled({ get = false }), false)
            end)
            restore()
            if not ok then error(err, 0) end
        end)

        H.test(stream .. " #169 dump gate re-evaluates VMF state without reload", function()
            local settings = { logging_mode = "default", output_mode_debug = 3 }
            local mod, restore = load_probes({ get = function(_, key) return settings[key] end })
            local ok, err = pcall(function()
                H.equal(mod._dbg_on(), false)
                settings.logging_mode = "custom"
                H.equal(mod._dbg_on(), true)
                settings.output_mode_debug = 0
                H.equal(mod._dbg_on(), false)
                settings.output_mode_debug = 1
                H.equal(mod._dbg_on(), true)
            end)
            restore()
            if not ok then error(err, 0) end
        end)
    end

    -- Exercise the actual loader's failure paths, including errors before a
    -- compiled chunk exists. The test itself always restores its planted state.
    for _, failure in ipairs({ "missing", "load-error", "runtime-error", "success" }) do
        H.test(stream .. " #169 probe loader restores raw globals after " .. failure, function()
            local saved_get_mod = rawget(_G, "get_mod")
            local saved_printf = rawget(_G, "printf")
            local saved_loadfile = rawget(_G, "loadfile")
            local saved_metatable = getmetatable(_G)
            local ok, err = pcall(function()
                for _, shape in ipairs({ "absent", "present", "inherited" }) do
                    local original_get_mod = shape == "present" and function() end or nil
                    local original_printf
                    if shape == "present" then original_printf = false end
                    rawset(_G, "get_mod", original_get_mod)
                    rawset(_G, "printf", original_printf)
                    -- Inherited values must not become new own slots on restore.
                    local inherited = { get_mod = function() end, printf = function() end }
                    setmetatable(_G, shape == "inherited" and { __index = inherited } or saved_metatable)
                    rawset(_G, "loadfile", function(path)
                        H.equal(path, base .. "_gt_debug_probes.lua")
                        if failure == "missing" then return nil, "planted missing probe" end
                        if failure == "load-error" then error("planted load error") end
                        return function()
                            if failure == "runtime-error" then error("planted runtime error") end
                        end
                    end)
                    local loaded, result, restore = pcall(load_probes, nil)
                    if loaded then restore() end
                    H.equal(loaded, failure == "success", shape .. " load outcome")
                    if not loaded then H.truthy(tostring(result):find("planted", 1, true)) end
                    H.equal(rawget(_G, "get_mod"), original_get_mod, shape .. " get_mod raw slot")
                    H.equal(rawget(_G, "printf"), original_printf, shape .. " printf raw slot")
                end
            end)
            rawset(_G, "get_mod", saved_get_mod)
            rawset(_G, "printf", saved_printf)
            rawset(_G, "loadfile", saved_loadfile)
            setmetatable(_G, saved_metatable)
            if not ok then error(err, 0) end
        end)
    end

    -- ---- Part 2: retired-key contract over each stream's loaded modules ----

    local function read_file(path)
        local f = assert(io.open(path, "rb"), "cannot open " .. path)
        local source = f:read("*a")
        f:close()
        return source
    end

    local function strip_comments(source)
        -- Long comments first (--[[ ]] and --[==[ ]==] forms), then the
        -- remainder of each line after `--`. Good enough for this codebase:
        -- a `--` inside a string literal would only over-strip, which can
        -- produce a false PASS on the same line, never a false FAIL.
        source = source:gsub("%-%-%[(=*)%[.-%]%1%]", " ")
        source = source:gsub("%-%-[^\r\n]*", "")
        return source
    end

    local RETIRED = "[:%.]%s*[gs]et%s*%(%s*[\"']enable_debug_logging[\"']"

    H.test(stream .. " #169 comment stripper separates executable reads from prose", function()
        -- Self-check so the scan below cannot rot into a trivially-green test.
        H.equal(strip_comments('-- mod:get("enable_debug_logging") prose'):find(RETIRED), nil)
        H.truthy(strip_comments('local x = mod:get("enable_debug_logging")'):find(RETIRED))
        H.truthy(strip_comments("mod:set('enable_debug_logging', false)"):find(RETIRED))
        H.equal(strip_comments("--[[ mod:get(\"enable_debug_logging\") ]]"):find(RETIRED), nil)
    end)

    H.test(stream .. " #169 loaded files execute the retired debug key only as pinned promotion debt", function()
        local entry = read_file(base .. stream .. ".lua")
        local files = {
            stream .. ".lua",
            stream .. "_data.lua",
            stream .. "_localization.lua",
        }
        local seen = {}
        for name in entry:gmatch(
                "mod:dofile%(%s*[\"']scripts/mods/" .. stream .. "/([%w_]+)[\"']") do
            if not seen[name] then
                seen[name] = true
                files[#files + 1] = name .. ".lua"
            end
        end
        -- Each manifest must enumerate its probe owner, not pass an empty scan.
        H.truthy(seen._gt_debug_probes, "probe owner is absent from the load manifest")
        H.truthy(#files >= 20, "manifest enumeration collapsed: " .. #files .. " files")

        local offenders = {}
        for _, name in ipairs(files) do
            local stripped = strip_comments(read_file(base .. name))
            if stripped:find(RETIRED) then
                offenders[#offenders + 1] = name
            end
        end
        if spec.vmf_predicate then
            H.equal(#offenders, 0,
                "retired enable_debug_logging key executed in: "
                .. table.concat(offenders, ", "))
        else
            local allowed = spec.pinned_owner .. ".lua"
            for _, name in ipairs(offenders) do
                H.equal(name, allowed,
                    "retired enable_debug_logging key executed outside the pinned stable promotion debt: "
                    .. name)
            end
        end
    end)

    if not spec.vmf_predicate then
        H.test(stream .. " #169 promotion tripwire keeps the stable predicate flag honest", function()
            local source = read_file(base .. spec.pinned_owner .. ".lua")
            H.truthy(source:find(PINNED_READ, 1, true),
                stream .. " no longer carries the pinned retired read: set vmf_predicate = true for it here"
                .. " and delete its $legacyRetiredDebugKeyDebt entry in qa/check_logging.ps1")
        end)
    end
    end
end
