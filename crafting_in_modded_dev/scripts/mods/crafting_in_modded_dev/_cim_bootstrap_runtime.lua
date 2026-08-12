-- Owns CIM's load telemetry, settings dump, regression runner, and debug
-- plumbing.  Keeping the registry and command together guarantees every
-- later owner registers into the exact collection the command executes.

return function(context)
    assert(type(context) == "table", "_cim_bootstrap_runtime requires context")
    local mod = assert(context.mod, "_cim_bootstrap_runtime requires mod")
    local MOD_VERSION = assert(context.version, "_cim_bootstrap_runtime requires version")
    local print_line = context.print_line or printf

    local rehook_warnings = {}
    mod._cim_rehook_warnings = rehook_warnings
    local original_warning = mod.warning
    mod.warning = function(self, fmt, ...)
        local rendered
        if select("#", ...) > 0 and type(fmt) == "string" then
            local ok, value = pcall(string.format, fmt, ...)
            rendered = ok and value or fmt
        else
            rendered = tostring(fmt)
        end
        if type(rendered) == "string" and rendered:find("rehook active hook", 1, true) then
            rehook_warnings[#rehook_warnings + 1] = rendered
        end
        return original_warning(self, fmt, ...)
    end

    local RPC_SCHEMA = 1
    local dbg, dbg_alert = mod:dofile(
        "scripts/mods/crafting_in_modded_dev/_lib_debug")(mod, "[cim:dbg]")

    local function settings_fingerprint()
        local ok, data = pcall(require,
            "scripts/mods/crafting_in_modded_dev/crafting_in_modded_dev_data")
        if not ok or type(data) ~= "table" then return "nodata" end
        local keys = {}
        local function walk(node)
            if type(node) ~= "table" then return end
            if type(node.setting_id) == "string" then
                keys[#keys + 1] = node.setting_id
            end
            for _, child in pairs(node) do
                if type(child) == "table" then walk(child) end
            end
        end
        walk(data)
        if #keys == 0 then return "nosettings" end
        table.sort(keys)
        local parts = {}
        for i, key in ipairs(keys) do
            local value = mod:get(key)
            if value == true then
                parts[i] = key .. "=1"
            elseif value == false then
                parts[i] = key .. "=0"
            elseif value == nil then
                parts[i] = key .. "=?"
            else
                parts[i] = key .. "=" .. tostring(value)
            end
        end
        local serialized = table.concat(parts, ";")
        local hash = 2166136261
        for i = 1, #serialized do
            local byte = string.byte(serialized, i)
            local xored, place = 0, 1
            local prior, remaining = hash, byte
            for _ = 1, 32 do
                local hash_bit, byte_bit = prior % 2, remaining % 2
                if hash_bit ~= byte_bit then xored = xored + place end
                place = place * 2
                prior = (prior - hash_bit) / 2
                remaining = (remaining - byte_bit) / 2
            end
            hash = (xored * 16777619) % 4294967296
        end
        return string.format("%08x", hash)
    end

    mod:info("Crafting in Modded v%s loaded", MOD_VERSION)
    mod:info("[cim:LOAD] v%s enabled fp=%s OK", MOD_VERSION,
        settings_fingerprint())

    if MOD_VERSION:find("-dev$") or MOD_VERSION:find("-alpha$")
            or MOD_VERSION:find("-beta$") or MOD_VERSION:find("-rc%d*$")
            or MOD_VERSION:find("^0%.") then
        mod:echo(string.format("[cim] v%s loaded", MOD_VERSION))
    end

    function mod._cim_dump_settings(phase)
        local ok, err = pcall(function()
            local data = mod:dofile(
                "scripts/mods/crafting_in_modded_dev/crafting_in_modded_dev_data")
            local ids, seen = {}, {}
            local function visit(node)
                if type(node) ~= "table" then return end
                if type(node.setting_id) == "string" and node.type
                        and node.type ~= "group" and not seen[node.setting_id] then
                    seen[node.setting_id] = true
                    ids[#ids + 1] = node.setting_id
                end
                if node.sub_widgets then
                    for _, widget in ipairs(node.sub_widgets) do visit(widget) end
                end
                if node.widgets then
                    for _, widget in ipairs(node.widgets) do visit(widget) end
                end
            end
            if type(data) == "table" then visit(data.options) end
            table.sort(ids)
            local function format_value(value)
                if value == true then return "1" end
                if value == false then return "0" end
                if value == nil then return "?" end
                return tostring(value)
            end
            print_line("[cim-settings] BEGIN phase=%s v=%s count=%d",
                tostring(phase), tostring(MOD_VERSION), #ids)
            for _, id in ipairs(ids) do
                print_line("[cim-settings] %s get=%s", id,
                    format_value(mod:get(id)))
            end
            print_line("[cim-settings] END phase=%s", tostring(phase))
        end)
        if not ok then
            print_line("[cim-settings] DUMP FAILED phase=%s err=%s",
                tostring(phase), tostring(err))
        end
    end

    mod._cim_dump_settings("load")
    mod:command("cim_dump_settings",
        "Dump every cim setting_id + value to the log via raw printf", function()
            mod._cim_dump_settings("command")
            mod:echo("[cim] settings dumped to log ([cim-settings] lines).")
        end)

    local checks = {}
    local function rt_register(name, fn)
        checks[#checks + 1] = { name = name, fn = fn }
    end
    mod._cim_rt_register = rt_register

    local function rt_src_read(path)
        local io_lib = rawget(_G, "io")
        if type(io_lib) ~= "table" or type(io_lib.open) ~= "function" then
            return nil
        end
        local file = io_lib.open(path, "r")
        if not file then return nil end
        local text = file:read("*a")
        file:close()
        return text
    end

    mod:command("cim_regression_test",
        "Run regression smoke checks for past bugs", function()
            local pass, fail, skip = 0, 0, 0
            mod:echo("=== cim regression_test (v%s) ===", MOD_VERSION)
            for _, check in ipairs(checks) do
                local ok, err = pcall(check.fn)
                if ok and err == nil then
                    mod:echo("  PASS: %s", check.name)
                    pass = pass + 1
                    mod:info("[regression] PASS %s", check.name)
                elseif ok and type(err) == "string"
                        and err:sub(1, 5) == "skip:" then
                    mod:echo("  SKIP: %s -- %s", check.name,
                        err:sub(6):gsub("^%s+", ""))
                    skip = skip + 1
                    mod:info("[regression] SKIP %s: %s", check.name, err)
                else
                    local message = (not ok and tostring(err)) or tostring(err)
                    mod:echo("  FAIL: %s -- %s", check.name, message)
                    fail = fail + 1
                    mod:warning("[regression] FAIL %s: %s", check.name, message)
                end
            end
            mod:echo("=== %d passed, %d failed, %d skipped ===",
                pass, fail, skip)
        end)
    mod:info("[regression-test-command] registered as /cim_regression_test")

    return {
        rpc_schema = RPC_SCHEMA,
        dbg = dbg,
        dbg_alert = dbg_alert,
        rehook_warnings = rehook_warnings,
        rt_register = rt_register,
        rt_src_read = rt_src_read,
    }
end
