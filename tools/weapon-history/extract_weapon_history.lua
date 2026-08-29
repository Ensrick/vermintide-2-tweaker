-- Source-qualified weapon-history extractor.
--
-- Usage (from the decompiled-source repository):
--   lua5.1 extract_weapon_history.lua <old-rev> <new-rev> <path> [<path> ...]
--   lua5.1 extract_weapon_history.lua --profiles <old-rev> <new-rev>
--       scripts/settings/equipment/power_level_templates.lua
--       scripts/settings/equipment/damage_profile_templates.lua
--   lua5.1 extract_weapon_history.lua --enrich-snapshot <current-rev>
--       <generated-snapshot.lua>
--   lua5.1 extract_weapon_history.lua --rehydrate-snapshot <old-rev>
--       <current-rev> <generated-snapshot.lua>
--   lua5.1 extract_weapon_history.lua --rehydrate-profiles <old-rev>
--       <current-rev> <generated-profile-snapshot.lua>
--   lua5.1 extract_weapon_history.lua --self-test
-- Set WT_HISTORY_OUTPUT to write canonical LF bytes directly to a file.
--
-- The extractor executes weapon-template chunks inside a symbolic, engine-free
-- environment, compares their returned template tables, and emits the exact
-- gameplay mutations needed to project the old revision over the new one.
-- Unknown engine constants remain symbolic references; no game data is guessed.
-- Enrichment adds a source-anchor expectation beside every operation so the
-- runtime can refuse a stale game-table shape/value after a future patch.

local enrich_mode = arg[1] == "--enrich-snapshot"
local profile_mode = arg[1] == "--profiles"
local rehydrate_snapshot_mode = arg[1] == "--rehydrate-snapshot"
local rehydrate_profiles_mode = arg[1] == "--rehydrate-profiles"
local self_test_mode = arg[1] == "--self-test"
local mode_offset = (profile_mode or rehydrate_snapshot_mode
    or rehydrate_profiles_mode) and 1 or 0
local old_rev = not self_test_mode and (enrich_mode
    and assert(arg[2], "missing current revision")
    or assert(arg[1 + mode_offset], "missing old revision")) or nil
local new_rev = not self_test_mode and (enrich_mode and old_rev
    or assert(arg[2 + mode_offset], "missing new revision")) or nil
if not self_test_mode then
    assert(arg[3 + mode_offset], (enrich_mode or rehydrate_snapshot_mode
            or rehydrate_profiles_mode) and "missing generated evidence module"
        or "at least one source path is required")
end

-- Lua 5.1's tostring(number) is not a round-trip representation of every
-- IEEE-754 double. These values become exact runtime guards, so even a lost
-- low bit makes a valid current game value look stale. Pin the numeric locale
-- as well: a decimal comma would make the generated text invalid Lua source.
assert(os.setlocale("C", "numeric"), "C numeric locale unavailable")

local function number_literal(value)
    assert(value == value, "cannot serialize NaN")
    if value == math.huge then return "math.huge" end
    if value == -math.huge then return "-math.huge" end
    return string.format("%.17g", value)
end

if self_test_mode then
    local values = {
        0, -0.0, 0.1, -0.1, 1 / 3,
        0.2866666666666667, -0.033824745565652847,
        9007199254740991, 9007199254740992,
        math.ldexp(1, -1022), math.ldexp(1, -1074),
    }
    local function exact(left, right)
        if left ~= right then return false end
        if left == 0 then return 1 / left == 1 / right end
        return true
    end
    for _, value in ipairs(values) do
        local literal = number_literal(value)
        assert(not literal:find(",", 1, true), "numeric locale leaked into Lua literal")
        local chunk, load_error = loadstring("return " .. literal)
        assert(chunk, load_error)
        assert(exact(value, chunk()), "numeric round-trip failed: " .. literal)
    end
    local ok = pcall(number_literal, 0 / 0)
    assert(not ok, "NaN must be rejected")
    io.write("weapon-history numeric serializer: PASS\n")
    return
end

local function shell_quote(value)
    return '"' .. tostring(value):gsub('"', '\\"') .. '"'
end

local function git_show(rev, path)
    local command = "git show " .. shell_quote(rev .. ":" .. path)
    local pipe = assert(io.popen(command, "r"))
    local source = pipe:read("*a")
    local ok = pipe:close()
    assert(ok and source ~= "", "git show failed for " .. rev .. ":" .. path)
    return source:gsub("^\239\187\191", "")
end

local symbol_mt = {}
local symbol_cache
local source_lines = {}

local function reset_symbol_cache()
    -- Symbols are evaluation-local. Reusing a proxy object across immutable
    -- revisions would make environment identity depend on traversal history.
    symbol_cache = setmetatable({}, { __mode = "v" })
end
reset_symbol_cache()

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
    local children = rawget(value, "__children")
    if not children then
        children = {}
        rawset(value, "__children", children)
    end
    local cached = children[key]
    if cached then return cached end
    cached = symbol(value.__symbol .. "." .. tostring(key))
    children[key] = cached
    return cached
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
    reset_symbol_cache()
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
            for _, value in ipairs(values) do result[value] = true end
            return result
        end,
        sort = table.sort,
    }
    -- Most equipment chunks return their templates directly. DLC equipment
    -- settings instead mutate DLCSettings and return nil. Preserve symbolic
    -- fallback for every other DLC while giving the woods evaluator the exact
    -- side-effect owner needed by Deepwood Staff's vortex definition.
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
        local woods = rawget(env.DLCSettings, "woods")
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

local value_equal
value_equal = function(a, b, seen)
    if getmetatable(a) == symbol_mt or getmetatable(b) == symbol_mt then
        return getmetatable(a) == symbol_mt and getmetatable(b) == symbol_mt
            and a.__symbol == b.__symbol
    end
    local a_type, b_type = type(a), type(b)
    if a_type ~= b_type then return false end
    if a_type ~= "table" and a_type ~= "function" then return a == b end

    seen = seen or {}
    if seen[a] ~= nil then return seen[a] == b end
    seen[a] = b

    if a_type == "function" then
        local a_source, b_source = function_fingerprint(a), function_fingerprint(b)
        if a_source == nil or b_source == nil or a_source ~= b_source then return false end
        -- Decompiled template callbacks often close over another helper and a
        -- scalar-only configuration table. Compare that complete acyclic
        -- closure graph instead of flagging source-identical functions merely
        -- because each immutable revision produced a distinct Lua object.
        local index = 1
        while true do
            local a_name, a_value = debug.getupvalue(a, index)
            local b_name, b_value = debug.getupvalue(b, index)
            if a_name == nil or b_name == nil then return a_name == b_name end
            if a_name ~= b_name or not value_equal(a_value, b_value, seen) then
                return false
            end
            index = index + 1
        end
    end

    for key, value in pairs(a) do
        if not value_equal(value, rawget(b, key), seen) then return false end
    end
    for key in pairs(b) do
        if rawget(a, key) == nil then return false end
    end
    return true
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

local function table_equal(a, b, seen)
    return value_equal(a, b, seen)
end

local function path_copy(path, key)
    local result = {}
    for index = 1, #path do result[index] = path[index] end
    result[#result + 1] = key
    return result
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

local function serialize(value, indent, active)
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
    active = active or {}
    assert(not active[value], "cycle in serialized evidence")
    active[value] = true
    local keys = {}
    for key in pairs(value) do keys[#keys + 1] = key end
    table.sort(keys, canonical_key_less)
    if #keys == 0 then active[value] = nil; return "{}" end
    local pad, child_pad = string.rep(" ", indent), string.rep(" ", indent + 4)
    local parts = { "{" }
    for _, key in ipairs(keys) do
        local rendered_key
        if type(key) == "string" and key:match("^[%a_][%w_]*$") then
            rendered_key = key
        else
            rendered_key = "[" .. serialize(key, indent + 4, active) .. "]"
        end
        parts[#parts + 1] = "\n" .. child_pad .. rendered_key .. " = "
            .. serialize(value[key], indent + 4, active) .. ","
    end
    parts[#parts + 1] = "\n" .. pad .. "}"
    active[value] = nil
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

-- Re-read both sides of every already-audited operation. This preserves the
-- deliberately bounded operation/path selection while proving that neither the
-- historical result nor the current guard is inherited from a lossy artifact.
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
        for _, op in ipairs(record.ops or {}) do
            local historical_value, historical_exists = value_at(historical, op.path)
            local current_value, current_exists = value_at(current, op.path)
            op.value = historical_exists and serializable_clone(historical_value) or nil
            op.unset = not historical_exists
            op.expected_current = current_exists and serializable_clone(current_value) or nil
            op.expected_current_unset = not current_exists
        end
    end

    emit("-- Rehydrated from immutable source revisions; do not hand-edit.\n"
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
        for name, profile in pairs(env.DamageProfileTemplates or {}) do
            profiles[name] = profile
        end
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

    emit("-- Rehydrated from immutable source revisions; do not hand-edit.\n"
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
            op.expected_current = exists and serializable_clone(value) or nil
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
