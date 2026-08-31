-- Issue #169 (gt half): the heavy dump triggers in _gt_debug_probes.lua gated on
-- the RETIRED per-mod `enable_debug_logging` key, which no gt data file declares,
-- so the gate was permanently false. The replacement gates on VMF's own logging
-- state, mirroring vmf/modules/core/logging.lua:139+146: debug emission is
-- enabled only when `logging_mode == "custom"` and `output_mode_debug > 0`.
--
-- Two locks:
--   1. Behavioral: load the PRODUCTION _gt_debug_probes.lua and drive
--      mod._gt_vmf_debug_enabled / mod._dbg_on through the VMF semantics table
--      (default mode off, custom+0 off, custom+positive on, VMF absent off).
--   2. Contract: no file either GT entry manifest loads may EXECUTE a read or
--      write of the retired key; prose/comment mentions stay allowed.
return function(H, repo_root)
    local dev_base = repo_root .. "/general_tweaker_dev/scripts/mods/general_tweaker_dev/"
    local stable_base = repo_root .. "/general_tweaker/scripts/mods/general_tweaker/"

    local function load_probes(base, vmf_mod)
        local hooks = {}
        local registered = {}
        local mod = {
            get = function() return nil end,
            set = function() end,
            hook = function(_, class_name, method_name, callback)
                hooks[class_name .. "." .. method_name] = callback
            end,
            hook_safe = function() end,
            command = function() end,
            echo = function() end,
            info = function() end,
            debug = function() end,
            warning = function() end,
            error = function() end,
            _gt_rt_register = function(name, callback)
                registered[name] = callback
            end,
        }
        local saved_get_mod = _G.get_mod
        local saved_printf = _G.printf
        _G.get_mod = function(name)
            if name == "VMF" then return vmf_mod end
            return mod
        end
        _G.printf = function() end
        local ok, err = pcall(assert(loadfile(base .. "_gt_debug_probes.lua")))
        -- Keep the fake get_mod installed for the caller's assertions: the
        -- helper resolves get_mod("VMF") at CALL time, not load time. The
        -- caller must invoke restore() when done.
        local function restore()
            _G.get_mod = saved_get_mod
            _G.printf = saved_printf
        end
        if not ok then
            restore()
            error(err, 0)
        end
        return mod, restore, hooks, registered
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

    H.test("GT #169 dump gate follows VMF custom-mode debug state", function()
        local mod, restore = load_probes(dev_base, fake_vmf("custom", 3))
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
            -- Default mode: the custom levels are ignored, debug falls to 0.
            H.equal(mod._gt_vmf_debug_enabled(fake_vmf("default", 3)), false)
            H.equal(mod._gt_vmf_debug_enabled(fake_vmf(nil, 3)), false)
            -- Non-numeric junk from a corrupt save fails closed, not loud.
            H.equal(mod._gt_vmf_debug_enabled(fake_vmf("custom", "x")), false)
        end)
        restore()
        if not ok then error(err, 0) end
    end)

    H.test("GT #169 dump gate fails closed when VMF is unreachable", function()
        local mod, restore = load_probes(dev_base, nil)
        local ok, err = pcall(function()
            H.equal(mod._dbg_on(), false)
            H.equal(mod._gt_vmf_debug_enabled(nil), false)
            H.equal(mod._gt_vmf_debug_enabled({}), false)
        end)
        restore()
        if not ok then error(err, 0) end
    end)

    H.test("GT #169 stable dump gate matches VMF custom-mode semantics", function()
        local mod, restore, _, registered = load_probes(stable_base, fake_vmf("custom", 2))
        local ok, err = pcall(function()
            H.equal(type(mod._gt_vmf_debug_enabled), "function")
            H.equal(mod._dbg_on(), true)
            H.equal(mod._gt_vmf_debug_enabled(fake_vmf("custom", 0)), false)
            H.equal(mod._gt_vmf_debug_enabled(fake_vmf("default", 3)), false)
            H.equal(mod._gt_vmf_debug_enabled({}), false)
            H.equal(type(registered.issue169_vmf_debug_gate), "function")
            H.equal(registered.issue169_vmf_debug_gate(), nil)

            local f = assert(io.open(stable_base .. "general_tweaker.lua", "rb"))
            local stable_main = f:read("*a")
            f:close()
            H.truthy(stable_main:find("mod%._gt_rt_register%s*=%s*_rt_register"),
                "stable main does not publish the sibling regression registrar")
        end)
        restore()
        if not ok then error(err, 0) end
    end)

    H.test("GT #169 VMF reader failures cannot suppress native HeroView hooks", function()
        for _, base in ipairs({ stable_base, dev_base }) do
            local throwing_vmf = { get = function() error("unreadable VMF setting") end }
            local mod, restore, hooks, registered = load_probes(base, throwing_vmf)
            local ok, err = pcall(function()
                local safe, enabled = pcall(mod._gt_vmf_debug_enabled, throwing_vmf)
                H.equal(safe, true)
                H.equal(enabled, false)

                _G.get_mod = function() error("VMF registry unavailable") end
                safe, enabled = pcall(mod._dbg_on)
                H.equal(safe, true)
                H.equal(enabled, false)

                local callback = hooks["HeroViewStateOverview.set_layout_by_name"]
                H.equal(type(callback), "function")
                local forwarded = 0
                local result = callback(function(_, _, marker)
                    forwarded = forwarded + 1
                    return marker
                end, {}, "equipment", "native-return")
                H.equal(forwarded, 1)
                H.equal(result, "native-return")

                H.equal(type(registered.issue169_vmf_debug_gate), "function")
                H.equal(registered.issue169_vmf_debug_gate(), nil)
            end)
            restore()
            if not ok then error(err, 0) end
        end
    end)

    -- ---- Part 2: retired-key contract over everything gt_dev loads ----

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

    H.test("GT #169 comment stripper separates executable reads from prose", function()
        -- Self-check so the scan below cannot rot into a trivially-green test.
        H.equal(strip_comments('-- mod:get("enable_debug_logging") prose'):find(RETIRED), nil)
        H.truthy(strip_comments('local x = mod:get("enable_debug_logging")'):find(RETIRED))
        H.truthy(strip_comments("mod:set('enable_debug_logging', false)"):find(RETIRED))
        H.equal(strip_comments("--[[ mod:get(\"enable_debug_logging\") ]]"):find(RETIRED), nil)
    end)

    H.test("GT #169 no loaded file executes the retired debug key", function()
        local streams = {
            {
                id = "stable",
                base = stable_base,
                entry = "general_tweaker.lua",
                data = "general_tweaker_data.lua",
                localization = "general_tweaker_localization.lua",
                module_path = "general_tweaker",
                min_files = 20,
            },
            {
                id = "dev",
                base = dev_base,
                entry = "general_tweaker_dev.lua",
                data = "general_tweaker_dev_data.lua",
                localization = "general_tweaker_dev_localization.lua",
                module_path = "general_tweaker_dev",
                min_files = 40,
            },
        }

        for _, stream in ipairs(streams) do
            local entry = read_file(stream.base .. stream.entry)
            local files = { stream.entry, stream.data, stream.localization }
            local seen = {}
            local pattern = "mod:dofile%(%s*[\"']scripts/mods/"
                .. stream.module_path .. "/([%w_]+)[\"']"
            for name in entry:gmatch(pattern) do
                if not seen[name] then
                    seen[name] = true
                    files[#files + 1] = name .. ".lua"
                end
            end
            -- Stable and Dev intentionally load different module sets. Each
            -- floor pins the current order of magnitude so a regex collapse
            -- cannot turn this contract into a vacuous pass.
            H.truthy(#files >= stream.min_files,
                stream.id .. " manifest enumeration collapsed: " .. #files .. " files")

            local offenders = {}
            for _, name in ipairs(files) do
                local stripped = strip_comments(read_file(stream.base .. name))
                if stripped:find(RETIRED) then
                    offenders[#offenders + 1] = name
                end
            end
            H.equal(#offenders, 0,
                stream.id .. " executes retired enable_debug_logging key in: "
                .. table.concat(offenders, ", "))
        end
    end)
end
