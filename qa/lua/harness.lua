local Harness = {}

local tests = {}

local function render(value, seen)
    local kind = type(value)
    if kind == "string" then
        return string.format("%q", value)
    end
    if kind ~= "table" then
        return tostring(value)
    end

    seen = seen or {}
    if seen[value] then
        return "<cycle>"
    end
    seen[value] = true

    local keys = {}
    for key in pairs(value) do
        keys[#keys + 1] = key
    end
    table.sort(keys, function(a, b)
        return tostring(a) < tostring(b)
    end)

    local parts = {}
    for _, key in ipairs(keys) do
        parts[#parts + 1] = "[" .. render(key, seen) .. "]=" .. render(value[key], seen)
    end
    seen[value] = nil
    return "{" .. table.concat(parts, ", ") .. "}"
end

local function deep_equal(actual, expected, seen)
    if actual == expected then
        return true
    end
    if type(actual) ~= "table" or type(expected) ~= "table" then
        return false
    end

    seen = seen or {}
    seen[actual] = seen[actual] or {}
    if seen[actual][expected] then
        return true
    end
    seen[actual][expected] = true

    for key, value in pairs(actual) do
        if not deep_equal(value, expected[key], seen) then
            return false
        end
    end
    for key in pairs(expected) do
        if actual[key] == nil then
            return false
        end
    end
    return true
end

function Harness.test(name, body)
    assert(type(name) == "string" and name ~= "", "test name must be a non-empty string")
    assert(type(body) == "function", "test body must be a function")
    tests[#tests + 1] = { name = name, body = body }
end

function Harness.equal(actual, expected, message)
    if actual ~= expected then
        error((message or "values differ") .. ": expected " .. render(expected) .. ", got " .. render(actual), 2)
    end
end

function Harness.deep_equal(actual, expected, message)
    if not deep_equal(actual, expected) then
        error((message or "tables differ") .. ": expected " .. render(expected) .. ", got " .. render(actual), 2)
    end
end

function Harness.truthy(value, message)
    if not value then
        error(message or "expected a truthy value", 2)
    end
end

function Harness.run(options)
    options = options or {}
    local failed = 0

    for _, test_case in ipairs(tests) do
        local ok, failure = xpcall(test_case.body, debug.traceback)
        if ok then
            if not options.quiet then
                io.write("  [PASS] ", test_case.name, "\n")
            end
        else
            failed = failed + 1
            io.stderr:write("  [FAIL] ", test_case.name, "\n", tostring(failure), "\n")
        end
    end

    local total = #tests
    tests = {}
    return failed == 0, total, failed
end

return Harness
