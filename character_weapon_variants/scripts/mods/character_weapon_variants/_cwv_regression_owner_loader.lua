-- Pure, fail-before-mutation loader for decomposed regression owners.
--
-- The caller deliberately performs real `_rt_register` calls only after this
-- function returns a complete, validated row array. Child owners never receive
-- the live registration function, so a load/constructor/schema failure cannot
-- leave the shared regression runner partially populated.
return function(spec)
    if type(spec) ~= "table"
            or type(spec.name) ~= "string" or spec.name == ""
            or type(spec.constructor) ~= "function"
            or type(spec.dependencies) ~= "table"
            or type(spec.expected_count) ~= "number"
            or spec.expected_count < 1 then
        error("CWV regression owner load specification is invalid")
    end

    local rows, export = spec.constructor(spec.dependencies)
    if type(rows) ~= "table" then
        error("CWV regression owner did not return a check table: " .. spec.name)
    end
    if spec.export_type ~= nil and type(export) ~= spec.export_type then
        error("CWV regression owner returned an invalid export: " .. spec.name)
    end

    local row_count = 0
    for _ in pairs(rows) do row_count = row_count + 1 end
    if row_count ~= spec.expected_count then
        error("CWV regression owner returned an incomplete row set: " .. spec.name)
    end

    local seen = {}
    for index = 1, spec.expected_count do
        local row = rawget(rows, index)
        if type(row) ~= "table" or type(row.name) ~= "string" or row.name == ""
                or type(row.fn) ~= "function"
                or (row.opts ~= nil and type(row.opts) ~= "table") then
            error("CWV regression owner returned a malformed row: " .. spec.name)
        end
        if seen[row.name] then
            error("CWV regression owner returned a duplicate check name: " .. spec.name)
        end
        seen[row.name] = true
    end
    return rows, export
end
