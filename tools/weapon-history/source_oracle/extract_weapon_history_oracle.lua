-- Source-qualified weapon-history extractor.
--
-- Usage:
--   lua5.1 extract_weapon_history_oracle.lua --source-repo <checkout>
--       <old-rev> <new-rev> <path> [<path> ...]
--   lua5.1 extract_weapon_history_oracle.lua --source-repo <checkout>
--       --profiles <old-rev> <new-rev>
--   lua5.1 extract_weapon_history_oracle.lua --source-repo <checkout>
--       --routes <current-rev> <source-spec.lua>
--   lua5.1 extract_weapon_history_oracle.lua --source-repo <checkout>
--       --rehydrate-snapshot <old-rev> <current-rev> <snapshot.lua>
--   lua5.1 extract_weapon_history_oracle.lua --source-repo <checkout>
--       --rehydrate-profiles <old-rev> <current-rev> <profiles.lua>
--   lua5.1 extract_weapon_history_oracle.lua --compare-evidence <left.lua> <right.lua>
--       scripts/settings/equipment/power_level_templates.lua
--       scripts/settings/equipment/damage_profile_templates.lua
--   lua5.1 extract_weapon_history.lua --enrich-snapshot <current-rev>
--       <generated-snapshot.lua>
--
-- The extractor executes weapon-template chunks inside a symbolic, engine-free
-- environment, compares their returned template tables, and emits the exact
-- gameplay mutations needed to project the old revision over the new one.
-- Unknown engine constants remain symbolic references; no game data is guessed.
-- Enrichment adds a source-anchor expectation beside every operation so the
-- runtime can refuse a stale game-table shape/value after a future patch.

local source_repo
if arg[1] == "--source-repo" then
    source_repo = assert(arg[2], "missing source repository")
    table.remove(arg, 1)
    table.remove(arg, 1)
end

local enrich_mode = arg[1] == "--enrich-snapshot"
local profile_mode = arg[1] == "--profiles"
local self_test_mode = arg[1] == "--self-test"
local routes_mode = arg[1] == "--routes"
local rehydrate_snapshot_mode = arg[1] == "--rehydrate-snapshot"
local rehydrate_profiles_mode = arg[1] == "--rehydrate-profiles"
local compare_mode = arg[1] == "--compare-evidence"
local arg_offset = (profile_mode or routes_mode or rehydrate_snapshot_mode
    or rehydrate_profiles_mode) and 1 or 0
local old_rev = not (self_test_mode or compare_mode) and (enrich_mode
    and assert(arg[2], "missing current revision")
    or assert(arg[1 + arg_offset], "missing old revision")) or nil
local new_rev = not (self_test_mode or compare_mode)
    and ((enrich_mode or routes_mode) and old_rev
    or assert(arg[2 + arg_offset], "missing new revision")) or nil
if not (self_test_mode or compare_mode) then
    if routes_mode then
        assert(arg[3], "missing source specification")
    else
        assert(arg[3 + arg_offset], (enrich_mode or rehydrate_snapshot_mode
                or rehydrate_profiles_mode) and "missing generated evidence module"
            or "at least one source path is required")
    end
elseif compare_mode then
    assert(arg[2] and arg[3], "two evidence modules required")
end

-- Generated numeric leaves are runtime guards. Lua 5.1 tostring(number) is
-- neither a complete IEEE-754 representation nor locale independent. Encode
-- every finite nonzero double as an exact integer significand and power of two.
assert(os.setlocale("C", "numeric"), "C numeric locale unavailable")

local function number_literal(value)
    assert(value == value, "cannot serialize NaN")
    if value == math.huge then return "math.huge" end
    if value == -math.huge then return "-math.huge" end
    if value == 0 then
        return 1 / value == -math.huge and "-math.ldexp(0,0)" or "0"
    end
    if value == math.floor(value) and math.abs(value) <= 9007199254740992 then
        return string.format("%.0f", value)
    end
    local fraction, exponent = math.frexp(value)
    local significand = fraction * 9007199254740992 -- 2^53
    return "math.ldexp(" .. string.format("%.0f", significand)
        .. "," .. tostring(exponent - 53) .. ")"
end

if compare_mode then
    local function load_evidence(path)
        local chunk, load_error = loadfile(path)
        assert(chunk, load_error)
        local value = chunk()
        assert(value ~= nil, path .. " returned nil")
        return value
    end
    local function exact(left, right, seen)
        if type(left) ~= type(right) then return false end
        if type(left) == "number" then
            return left == right and (left ~= 0 or 1 / left == 1 / right)
        end
        if type(left) ~= "table" then return left == right end
        seen = seen or {}
        seen[left] = seen[left] or {}
        if seen[left][right] then return true end
        seen[left][right] = true
        for key, value in pairs(left) do
            if rawget(right, key) == nil and value ~= nil then return false end
            if not exact(value, rawget(right, key), seen) then return false end
        end
        for key in pairs(right) do
            if rawget(left, key) == nil then return false end
        end
        return true
    end
    assert(exact(load_evidence(arg[2]), load_evidence(arg[3])),
        "evidence modules differ semantically")
    io.write("source-oracle evidence comparison: PASS\n")
    return
end

local function shell_quote(value)
    return '"' .. tostring(value):gsub('"', '\\"') .. '"'
end

local function git_show(rev, path)
    local prefix = source_repo and ("git -C " .. shell_quote(source_repo)) or "git"
    local command = prefix .. " show " .. shell_quote(rev .. ":" .. path)
    local pipe = assert(io.popen(command, "r"))
    local source = pipe:read("*a")
    local ok = pipe:close()
    assert(ok and source ~= "", "git show failed for " .. rev .. ":" .. path)
    return source:gsub("^\239\187\191", "")
end

local function git_blob(rev, path)
    local prefix = source_repo and ("git -C " .. shell_quote(source_repo)) or "git"
    local command = prefix .. " rev-parse " .. shell_quote(rev .. ":" .. path)
    local pipe = assert(io.popen(command, "r"))
    local blob = pipe:read("*a"):match("([0-9a-f]+)")
    local ok = pipe:close()
    assert(ok and blob and #blob == 40,
        "git rev-parse failed for " .. rev .. ":" .. path)
    return blob
end

local symbol_mt = {}
local symbol_cache = setmetatable({}, { __mode = "v" })
local source_lines = {}

local function remember_source(source, source_name)
    local lines = {}
    for line in (source .. "\n"):gmatch("(.-)\n") do
        lines[#lines + 1] = line
    end
    source_lines["@" .. source_name] = lines
end

local function function_source(value)
    local info = debug.getinfo(value, "S")
    local lines = info and source_lines[info.source]
    if not lines or not info.linedefined or not info.lastlinedefined then return nil end
    local body = {}
    for line = info.linedefined, info.lastlinedefined do
        body[#body + 1] = lines[line] or ""
    end
    return table.concat(body, "\n")
end

-- The source repository spans multiple decompiler generations.  Comparing raw
-- spans would report an executable change for formatting-only rewrites such as
-- `end` becoming `end,`, or reordered indentation around an otherwise
-- identical anonymous function.  Produce a conservative lexical fingerprint:
-- comments and insignificant whitespace are discarded, while every byte in a
-- quoted/long string remains significant.  The one optional trailing comma is
-- the containing table field separator, not part of the function itself.
local function function_fingerprint(value)
    local source = function_source(value)
    if not source then return nil end
    local output, index, length = {}, 1, #source
    local function long_bracket_at(position)
        if source:sub(position, position) ~= "[" then return nil end
        local equals = source:sub(position):match("^%[(=*)%[")
        if equals == nil then return nil end
        return equals, "]" .. equals .. "]"
    end
    while index <= length do
        local char = source:sub(index, index)
        local next_two = source:sub(index, index + 1)
        if next_two == "--" then
            local equals, closing = long_bracket_at(index + 2)
            if equals ~= nil then
                local finish = source:find(closing, index + 4 + #equals, true)
                index = finish and (finish + #closing) or (length + 1)
            else
                local finish = source:find("\n", index + 2, true)
                index = finish and (finish + 1) or (length + 1)
            end
        elseif char == "'" or char == '"' then
            local quote, finish = char, index + 1
            while finish <= length do
                local current = source:sub(finish, finish)
                if current == "\\" then
                    finish = finish + 2
                elseif current == quote then
                    finish = finish + 1
                    break
                else
                    finish = finish + 1
                end
            end
            output[#output + 1] = source:sub(index, finish - 1)
            index = finish
        elseif char == "[" then
            local equals, closing = long_bracket_at(index)
            if equals ~= nil then
                local finish = source:find(closing, index + 2 + #equals, true)
                finish = finish and (finish + #closing) or (length + 1)
                output[#output + 1] = source:sub(index, finish - 1)
                index = finish
            else
                output[#output + 1] = char
                index = index + 1
            end
        elseif char:match("%s") then
            index = index + 1
        else
            output[#output + 1] = char
            index = index + 1
        end
    end
    local fingerprint = table.concat(output)
    return (fingerprint:gsub(",$", ""))
end

local function symbol(expression)
    local cached = symbol_cache[expression]
    if cached then return cached end
    local value = setmetatable({ __symbol = expression }, symbol_mt)
    symbol_cache[expression] = value
    return value
end

local function expression(value)
    if getmetatable(value) == symbol_mt then return value.__symbol end
    if type(value) == "string" then return string.format("%q", value) end
    if type(value) == "number" then return number_literal(value) end
    return tostring(value)
end

symbol_mt.__index = function(value, key)
    return symbol(value.__symbol .. "." .. tostring(key))
end
symbol_mt.__call = function(value, ...)
    local args = {}
    for index = 1, select("#", ...) do
        args[index] = expression(select(index, ...))
    end
    return symbol(value.__symbol .. "(" .. table.concat(args, ",") .. ")")
end
symbol_mt.__add = function(a, b) return symbol("(" .. expression(a) .. "+" .. expression(b) .. ")") end
symbol_mt.__sub = function(a, b) return symbol("(" .. expression(a) .. "-" .. expression(b) .. ")") end
symbol_mt.__mul = function(a, b) return symbol("(" .. expression(a) .. "*" .. expression(b) .. ")") end
symbol_mt.__div = function(a, b) return symbol("(" .. expression(a) .. "/" .. expression(b) .. ")") end
symbol_mt.__unm = function(a) return symbol("(-" .. expression(a) .. ")") end
symbol_mt.__concat = function(a, b) return symbol("(" .. expression(a) .. ".." .. expression(b) .. ")") end
symbol_mt.__tostring = function(value) return value.__symbol end

local function deep_clone(value, seen)
    if type(value) ~= "table" or getmetatable(value) == symbol_mt then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local clone = {}
    seen[value] = clone
    for key, child in pairs(value) do clone[deep_clone(key, seen)] = deep_clone(child, seen) end
    return clone
end

local function merge(target, source)
    for key, value in pairs(source or {}) do
        if type(value) == "table" and getmetatable(value) ~= symbol_mt
                and type(target[key]) == "table" and getmetatable(target[key]) ~= symbol_mt then
            merge(target[key], value)
        else
            target[key] = deep_clone(value)
        end
    end
    return target
end

local function environment()
    local env = {
        assert = assert,
        error = error,
        ipairs = ipairs,
        next = next,
        pairs = pairs,
        pcall = pcall,
        rawget = rawget,
        rawset = rawset,
        select = select,
        setmetatable = setmetatable,
        tonumber = tonumber,
        tostring = tostring,
        type = type,
        unpack = unpack,
        math = math,
        string = string,
    }
    env.table = {
        clone = deep_clone,
        merge = merge,
        concat = table.concat,
        insert = table.insert,
        remove = table.remove,
        set = function(values)
            assert(type(values) == "table", "table.set expects a table")
            local result = {}
            for index = 1, #values do result[values[index]] = true end
            return result
        end,
        sort = table.sort,
    }
    env.DLCSettings = { woods = {} }
    setmetatable(env.DLCSettings, {
        __index = function(target, key)
            local value = symbol("DLCSettings." .. tostring(key))
            rawset(target, key, value)
            return value
        end,
    })
    env._G = env
    env.require = function() return nil end
    env.fassert = function(condition, message, ...)
        if not condition then error(string.format(message or "fassert failed", ...), 2) end
        return condition
    end
    env.DLCUtils = {
        map_list = function() end,
        require_list = function() end,
    }
    setmetatable(env, {
        __index = function(target, key)
            local value = symbol(tostring(key))
            rawset(target, key, value)
            return value
        end,
    })
    return env
end

local function evaluate(source, source_name)
    remember_source(source, source_name)
    local chunk, load_error = loadstring(source, "@" .. source_name)
    assert(chunk, load_error)
    local env = environment()
    setfenv(chunk, env)
    local ok, result = pcall(chunk)
    assert(ok, source_name .. ": " .. tostring(result))
    if result == nil then
        local dlc_settings = rawget(env, "DLCSettings")
        local woods = type(dlc_settings) == "table"
            and rawget(dlc_settings, "woods")
        local vortex_templates = type(woods) == "table"
            and rawget(woods, "vortex_templates")
        if type(vortex_templates) == "table" then result = vortex_templates end
    end
    assert(type(result) == "table", source_name .. " did not return a template table")
    return result
end

local function execute_into(env, source, source_name)
    remember_source(source, source_name)
    local chunk, load_error = loadstring(source, "@" .. source_name)
    assert(chunk, load_error)
    setfenv(chunk, env)
    local ok, result = pcall(chunk)
    assert(ok, source_name .. ": " .. tostring(result))
    return result
end

local excluded_root = {
    aim_assist_settings = true,
    attack_meta_data = true,
    buff_type = true,
    display_unit = true,
    left_hand_attachment_node_linking = true,
    left_hand_unit = true,
    right_hand_attachment_node_linking = true,
    right_hand_unit = true,
    state_machine = true,
    tooltip_compare = true,
    tooltip_detail = true,
    tooltip_keywords = true,
    tooltip_special_action_description = true,
    weapon_diagram = true,
    weapon_type = true,
    wield_anim = true,
    wwise_dep_left_hand = true,
    wwise_dep_right_hand = true,
}

local function scalar_equal(a, b)
    if getmetatable(a) == symbol_mt or getmetatable(b) == symbol_mt then
        return getmetatable(a) == symbol_mt and getmetatable(b) == symbol_mt
            and a.__symbol == b.__symbol
    end
    if type(a) == "function" and type(b) == "function" then
        local a_source, b_source = function_fingerprint(a), function_fingerprint(b)
        return a_source ~= nil and b_source ~= nil and a_source == b_source
    end
    return type(a) == type(b) and a == b
end

local function table_equal(a, b, seen)
    if type(a) ~= "table" or type(b) ~= "table"
            or getmetatable(a) == symbol_mt or getmetatable(b) == symbol_mt then
        return scalar_equal(a, b)
    end
    seen = seen or {}
    if seen[a] == b then return true end
    seen[a] = b
    for key, value in pairs(a) do
        if not table_equal(value, b[key], seen) then return false end
    end
    for key in pairs(b) do
        if a[key] == nil then return false end
    end
    return true
end

local function path_copy(path, key)
    local result = {}
    for index = 1, #path do result[index] = path[index] end
    result[#result + 1] = key
    return result
end

local key_type_order = { number = 1, string = 2, boolean = 3 }
local function canonical_key_less(left, right)
    local left_type, right_type = type(left), type(right)
    local left_order, right_order = key_type_order[left_type], key_type_order[right_type]
    assert(left_order and right_order,
        "unsupported table key type: " .. tostring(left_type) .. "/" .. tostring(right_type))
    if left_order ~= right_order then return left_order < right_order end
    if left_type == "boolean" then return left == false and right == true end
    return left < right
end

local function collect_ops(old_value, new_value, path, ops, unsupported)
    if table_equal(old_value, new_value) then return end
    local old_type, new_type = type(old_value), type(new_value)
    if old_type == "function" or new_type == "function" then
        unsupported[#unsupported + 1] = table.concat(path, ".") .. " (function changed)"
        return
    end
    if old_type ~= "table" or new_type ~= "table"
            or getmetatable(old_value) == symbol_mt or getmetatable(new_value) == symbol_mt then
        ops[#ops + 1] = { path = path, value = old_value, unset = old_value == nil }
        return
    end
    -- Recurse through arrays too.  Treating an array as one replacement value
    -- is unsafe when any element contains a callback: one unrelated scalar
    -- delta would make the serializer attempt to carry a live function object,
    -- and would hide which executable path was actually unsupported. Numeric
    -- index operations preserve array ordering while isolating real callbacks.
    local keys, seen = {}, {}
    for key in pairs(old_value) do seen[key] = true; keys[#keys + 1] = key end
    for key in pairs(new_value) do if not seen[key] then keys[#keys + 1] = key end end
    table.sort(keys, canonical_key_less)
    for _, key in ipairs(keys) do
        collect_ops(old_value[key], new_value[key], path_copy(path, key), ops, unsupported)
    end
end

local function serialize(value, indent)
    indent = indent or 0
    local value_type = type(value)
    if value == nil then return "nil" end
    if value_type == "boolean" then return tostring(value) end
    if value_type == "number" then
        return number_literal(value)
    end
    if value_type == "string" then return string.format("%q", value) end
    if getmetatable(value) == symbol_mt then
        return "{ ref = " .. string.format("%q", value.__symbol) .. " }"
    end
    assert(value_type == "table", "cannot serialize " .. value_type)
    local keys = {}
    for key in pairs(value) do keys[#keys + 1] = key end
    table.sort(keys, canonical_key_less)
    if #keys == 0 then return "{}" end
    local pad, child_pad = string.rep(" ", indent), string.rep(" ", indent + 4)
    local parts = { "{" }
    for _, key in ipairs(keys) do
        local rendered_key
        if type(key) == "string" and key:match("^[%a_][%w_]*$") then
            rendered_key = key
        else
            rendered_key = "[" .. serialize(key, indent + 4) .. "]"
        end
        parts[#parts + 1] = "\n" .. child_pad .. rendered_key .. " = "
            .. serialize(value[key], indent + 4) .. ","
    end
    parts[#parts + 1] = "\n" .. pad .. "}"
    return table.concat(parts)
end

local function emit(text)
    local output_path = os.getenv("WT_HISTORY_OUTPUT")
    if output_path and output_path ~= "" then
        local file = assert(io.open(output_path, "wb"))
        file:write(text)
        file:close()
    else
        io.write(text)
    end
end

local function value_at(root, path)
    local node = root
    for index = 1, #path do
        if type(node) ~= "table" then return nil, false end
        node = rawget(node, path[index])
        if node == nil then return nil, false end
    end
    return node, true
end

local function serializable_clone(value, seen)
    if type(value) == "function" then
        return { __wt_history_expected_type = "function" }
    end
    if type(value) ~= "table" or getmetatable(value) == symbol_mt then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local copy = {}
    seen[value] = copy
    for key, child in pairs(value) do
        copy[serializable_clone(key, seen)] = serializable_clone(child, seen)
    end
    return copy
end

-- This oracle lane deliberately owns its own presence-preserving branch.
-- Keeping it independent from the primary evaluator prevents a shared
-- `false`-to-nil implementation bug from making both lanes agree incorrectly.
local function oracle_copy_present_leaf(value, is_present)
    if not is_present then
        return nil
    end
    return serializable_clone(value)
end

if self_test_mode then
    local values = {
        0, -0.0, 0.1, -0.1, 1 / 3, 9007199254740991,
        9007199254740992, math.ldexp(1, -1022), math.ldexp(1, -1074),
        math.huge, -math.huge,
    }
    local function exact(left, right)
        if left ~= right then return false end
        if left == 0 then return 1 / left == 1 / right end
        return true
    end
    for _, value in ipairs(values) do
        local literal = number_literal(value)
        local chunk, load_error = loadstring("return " .. literal)
        assert(chunk, load_error)
        assert(exact(value, chunk()), "numeric round-trip failed: " .. literal)
    end
    local ok = pcall(number_literal, 0 / 0)
    assert(not ok, "NaN must be rejected")

    local states = {
        { name = "true", is_present = true, leaf = true },
        { name = "false", is_present = true, leaf = false },
        { name = "absent", is_present = false },
    }
    local function read_state(state)
        local container = {}
        if state.is_present then rawset(container, "leaf", state.leaf) end
        return value_at(container, { "leaf" })
    end
    for _, old_state in ipairs(states) do
        for _, live_state in ipairs(states) do
            local old_value, old_present = read_state(old_state)
            local live_value, live_present = read_state(live_state)
            local row = {}
            row.unset = not old_present
            row.value = oracle_copy_present_leaf(old_value, old_present)
            row.expected_current_unset = not live_present
            row.expected_current = oracle_copy_present_leaf(
                live_value, live_present)

            assert(old_present == old_state.is_present,
                "oracle old presence mismatch: " .. old_state.name)
            assert(live_present == live_state.is_present,
                "oracle live presence mismatch: " .. live_state.name)
            assert((rawget(row, "value") ~= nil) == old_state.is_present,
                "oracle old field presence mismatch: " .. old_state.name)
            assert((rawget(row, "expected_current") ~= nil)
                    == live_state.is_present,
                "oracle live field presence mismatch: " .. live_state.name)
            if old_state.is_present then
                assert(row.value == old_state.leaf,
                    "oracle old value mismatch: " .. old_state.name)
            end
            if live_state.is_present then
                assert(row.expected_current == live_state.leaf,
                    "oracle live value mismatch: " .. live_state.name)
            end
            local text = serialize(row)
            if old_state.name == "false" then
                assert(text:find("value = false", 1, true),
                    "oracle dropped serialized old false")
            elseif old_state.name == "absent" then
                assert(not text:find("\n    value =", 1, true),
                    "oracle serialized an absent old leaf")
            end
            if live_state.name == "false" then
                assert(text:find("expected_current = false", 1, true),
                    "oracle dropped serialized live false")
            elseif live_state.name == "absent" then
                assert(not text:find("\n    expected_current =", 1, true),
                    "oracle serialized an absent live leaf")
            end
        end
    end
    assert(serialize({ expected_current = false }):find(
        "expected_current = false", 1, true),
        "oracle standalone false serialization failed")
    assert(serialize({}) == "{}", "oracle standalone absence serialization failed")
    io.write("source-oracle numeric and 3x3 presence serializers: PASS\n")
    return
end

if routes_mode then
    local spec_path = arg[3]
    local spec_chunk, spec_error = loadfile(spec_path)
    assert(spec_chunk, spec_error)
    local spec = assert(spec_chunk(), "source specification returned nil")
    assert(spec.revisions.current == old_rev,
        "route revision does not match source specification")

    local template_cache = {}
    local function source_templates(path)
        if not template_cache[path] then
            template_cache[path] = evaluate(
                git_show(old_rev, path), old_rev .. ":" .. path)
        end
        return template_cache[path]
    end

    local function collect_profile_paths(node, path, wanted, output, seen)
        if type(node) ~= "table" or getmetatable(node) == symbol_mt then return end
        seen = seen or {}
        if seen[node] then return end
        seen[node] = true
        local keys = {}
        for key in pairs(node) do
            if type(key) == "string" or type(key) == "number" then
                keys[#keys + 1] = key
            end
        end
        table.sort(keys, function(left, right)
            if type(left) == type(right) then return left < right end
            return type(left) < type(right)
        end)
        for _, key in ipairs(keys) do
            local value = rawget(node, key)
            local child_path = path_copy(path, key)
            if type(key) == "string" and key:find("damage_profile", 1, true)
                    and type(value) == "string" and wanted[value] then
                output[#output + 1] = { native_name = value, path = child_path }
            end
            collect_profile_paths(value, child_path, wanted, output, seen)
        end
    end

    local routes, source_paths = {}, {}
    local path_revisions = {}
    local function sorted_string_keys(value)
        local keys = {}
        for key in pairs(value or {}) do
            assert(type(key) == "string", "route specification keys must be strings")
            keys[#keys + 1] = key
        end
        table.sort(keys)
        return keys
    end
    local function route_key(route)
        local parts = {}
        for index, key in ipairs(route.path) do parts[index] = tostring(key) end
        return route.template .. "|" .. route.native_name .. "|" .. table.concat(parts, ".")
    end
    local function require_blob(revision, path)
        path_revisions[revision] = path_revisions[revision] or {}
        path_revisions[revision][path] = true
    end
    for _, family in ipairs(spec.families or {}) do
        routes[family.id] = {}
        for _, template in ipairs(sorted_string_keys(family.templates)) do
            local path = family.templates[template]
            source_paths[path] = true
            local current_template = assert(source_templates(path)[template],
                "missing current template " .. template)
            for _, state_id in ipairs(sorted_string_keys(family.states)) do
                local profile_names = family.states[state_id]
                routes[family.id][state_id] = routes[family.id][state_id] or {}
                local wanted = {}
                for _, profile_name in ipairs(profile_names) do wanted[profile_name] = true end
                local found = {}
                collect_profile_paths(current_template, {}, wanted, found)
                for _, route in ipairs(found) do
                    route.template = template
                    routes[family.id][state_id][#routes[family.id][state_id] + 1] = route
                end
                require_blob(assert(spec.revisions[state_id]), path)
            end
            require_blob(old_rev, path)
        end
        for _, state_id in ipairs(sorted_string_keys(family.states)) do
            local profile_names = family.states[state_id]
            for _, profile_name in ipairs(profile_names) do
                local profile_path = assert(spec.profile_source_paths[profile_name],
                    "missing profile source path for " .. profile_name)
                require_blob(assert(spec.revisions[state_id]), profile_path)
                require_blob(old_rev, profile_path)
            end
            table.sort(routes[family.id][state_id], function(left, right)
                return route_key(left) < route_key(right)
            end)
        end
    end
    for _, path in ipairs(spec.extra_source_paths or {}) do
        require_blob(old_rev, path)
        for state_id in pairs(spec.revisions or {}) do
            if state_id ~= "current" then require_blob(spec.revisions[state_id], path) end
        end
    end
    local source_blobs = {}
    for revision, paths in pairs(path_revisions) do
        source_blobs[revision] = {}
        for path in pairs(paths) do source_blobs[revision][path] = git_blob(revision, path) end
    end
    emit("-- Regenerated from immutable decompiled-source Git objects; do not hand-edit.\n"
        .. "return " .. serialize({
        schema = 1,
        oracle_id = spec.oracle_id,
        current_revision = old_rev,
        source_blobs = source_blobs,
        routes = routes,
    }) .. "\n")
    return
end

if rehydrate_snapshot_mode then
    local snapshot_path = arg[4]
    local chunk, load_error = loadfile(snapshot_path)
    assert(chunk, load_error)
    local snapshot = assert(chunk(), snapshot_path .. " did not return a snapshot")
    local old_cache, current_cache = {}, {}
    local function templates(cache, revision, path)
        if not cache[path] then
            cache[path] = evaluate(git_show(revision, path), revision .. ":" .. path)
        end
        return cache[path]
    end
    for _, record in ipairs(snapshot.records or {}) do
        local historical = templates(old_cache, old_rev, record.source_path)[record.template]
        local current = templates(current_cache, new_rev, record.source_path)[record.template]
        assert(type(historical) == "table", "historical template missing: " .. record.template)
        assert(type(current) == "table", "current template missing: " .. record.template)
        for _, operation in ipairs(record.ops or {}) do
            local historical_value, historical_exists = value_at(historical, operation.path)
            local current_value, current_exists = value_at(current, operation.path)
            operation.value = oracle_copy_present_leaf(
                historical_value, historical_exists)
            operation.unset = not historical_exists
            operation.expected_current = oracle_copy_present_leaf(
                current_value, current_exists)
            operation.expected_current_unset = not current_exists
        end
    end
    emit("-- Independently rehydrated from immutable source revisions.\n"
        .. "return " .. serialize(snapshot) .. "\n")
    return
end

if rehydrate_profiles_mode then
    local snapshot_path = arg[4]
    local chunk, load_error = loadfile(snapshot_path)
    assert(chunk, load_error)
    local snapshot = assert(chunk(), snapshot_path .. " did not return a profile snapshot")
    local profile_paths = {
        "scripts/settings/dlcs/morris/damage_profile_templates_dlc_morris.lua",
        "scripts/settings/equipment/damage_profile_templates_dlc_cog.lua",
        "scripts/settings/equipment/damage_profile_templates_dlc_woods.lua",
    }
    local function profiles_at(revision)
        local env = environment()
        execute_into(env, git_show(revision,
            "scripts/settings/equipment/power_level_templates.lua"),
            revision .. ":scripts/settings/equipment/power_level_templates.lua")
        execute_into(env, git_show(revision,
            "scripts/settings/equipment/damage_profile_templates.lua"),
            revision .. ":scripts/settings/equipment/damage_profile_templates.lua")
        local profiles = {}
        for name, profile in pairs(env.DamageProfileTemplates or {}) do profiles[name] = profile end
        for _, path in ipairs(profile_paths) do
            local returned = execute_into(env, git_show(revision, path), revision .. ":" .. path)
            assert(type(returned) == "table", path .. " did not return profiles")
            for name, profile in pairs(returned) do profiles[name] = profile end
        end
        return profiles
    end
    local historical_profiles = profiles_at(old_rev)
    local current_profiles = profiles_at(new_rev)
    local exact = {}
    for name in pairs(snapshot.profiles or {}) do
        assert(type(historical_profiles[name]) == "table",
            "historical profile missing: " .. tostring(name))
        assert(type(current_profiles[name]) == "table",
            "current profile missing: " .. tostring(name))
        exact[name] = serializable_clone(historical_profiles[name])
    end
    snapshot.profiles = exact
    emit("-- Independently rehydrated from immutable source revisions.\n"
        .. "return " .. serialize(snapshot) .. "\n")
    return
end

if enrich_mode then
    local snapshot_path = arg[3]
    local chunk, load_error = loadfile(snapshot_path)
    assert(chunk, load_error)
    local snapshot = assert(chunk(), snapshot_path .. " did not return a snapshot")
    local cache = {}

    local function current_templates(path)
        if not cache[path] then
            cache[path] = evaluate(git_show(new_rev, path), new_rev .. ":" .. path)
        end
        return cache[path]
    end

    for _, record in ipairs(snapshot.records or {}) do
        local current = current_templates(record.source_path)[record.template]
        assert(type(current) == "table", "current template missing: " .. record.template)
        for _, op in ipairs(record.ops or {}) do
            local value, exists = value_at(current, op.path)
            op.expected_current = oracle_copy_present_leaf(value, exists)
            op.expected_current_unset = not exists
        end
    end

    emit("-- Generated from decompiled source revisions; do not hand-edit.\n"
        .. "return " .. serialize(snapshot) .. "\n")
    return
end

if profile_mode then
    local power_path = assert(arg[4], "profile mode needs power-level source path")
    local damage_path = assert(arg[5], "profile mode needs damage-profile source path")
    local function profile_snapshot(revision)
        local env = environment()
        execute_into(env, git_show(revision, power_path), revision .. ":" .. power_path)
        execute_into(env, git_show(revision, damage_path), revision .. ":" .. damage_path)
        return assert(env.DamageProfileTemplates, "DamageProfileTemplates unavailable")
    end
    local old_profiles = profile_snapshot(old_rev)
    local new_profiles = profile_snapshot(new_rev)
    local profiles = {}
    for name, profile in pairs(old_profiles) do
        if type(name) == "string" and not name:match("_no_damage$")
                and type(profile) == "table" and type(new_profiles[name]) == "table"
                and not table_equal(profile, new_profiles[name]) then
            profiles[name] = profile
        end
    end
    emit("-- Generated from decompiled source revisions; do not hand-edit.\n"
        .. "return " .. serialize({
        old_revision = old_rev,
        new_revision = new_rev,
        profiles = profiles,
    }) .. "\n")
    return
end

local records = {}
for index = 3, #arg do
    local path = arg[index]
    local old_templates = evaluate(git_show(old_rev, path), old_rev .. ":" .. path)
    local new_templates = evaluate(git_show(new_rev, path), new_rev .. ":" .. path)
    local names, seen = {}, {}
    for name in pairs(old_templates) do seen[name] = true; names[#names + 1] = name end
    for name in pairs(new_templates) do if not seen[name] then names[#names + 1] = name end end
    table.sort(names)
    for _, name in ipairs(names) do
        local ops, unsupported = {}, {}
        local old_template, new_template = old_templates[name], new_templates[name]
        if type(old_template) == "table" and type(new_template) == "table" then
            local keys, key_seen = {}, {}
            for key in pairs(old_template) do key_seen[key] = true; keys[#keys + 1] = key end
            for key in pairs(new_template) do if not key_seen[key] then keys[#keys + 1] = key end end
            table.sort(keys, canonical_key_less)
            for _, key in ipairs(keys) do
                if not excluded_root[key] and not tostring(key):match("^sound_event_") then
                    collect_ops(old_template[key], new_template[key], { key }, ops, unsupported)
                end
            end
        end
        if #ops > 0 or #unsupported > 0 then
            records[#records + 1] = {
                source_path = path,
                template = name,
                ops = ops,
                unsupported = unsupported,
            }
        end
    end
end

table.sort(records, function(a, b) return a.template < b.template end)
emit("-- Generated from decompiled source revisions; do not hand-edit.\n"
    .. "return " .. serialize({
    old_revision = old_rev,
    new_revision = new_rev,
    records = records,
}) .. "\n")
