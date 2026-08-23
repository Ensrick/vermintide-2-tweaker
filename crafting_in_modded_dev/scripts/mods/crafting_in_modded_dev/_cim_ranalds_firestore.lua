-- Bounded asynchronous Firestore reader for Ranald's Gift (#1360).
-- No request can mutate game state; callbacks return normalized catalogue rows.

local M = {}

M.ENDPOINT = "https://firestore.googleapis.com/v1/projects/ranaldsgift/databases/(default)/documents:runQuery?key=AIzaSyBD4fAmwgqETnUzgH3D7MLG08_nbH7FH8Y"
M.BATCH_SIZE = 100
M.MAX_RESULTS = 800
M.MAX_RESPONSE_BYTES = 524288
M.MAX_TOTAL_BYTES = 4194304

local FIELD_NAMES = {
    "careerId", "name", "username", "likeCount", "dateModified",
    "talent1", "talent2", "talent3", "talent4", "talent5", "talent6",
    "primaryWeapon", "secondaryWeapon", "necklace", "charm", "trinket",
}

local function _firestore_value(value, depth)
    if type(value) ~= "table" or depth > 8 then return nil end
    if value.stringValue ~= nil then return tostring(value.stringValue) end
    if value.integerValue ~= nil then return tonumber(value.integerValue) end
    if value.doubleValue ~= nil then return tonumber(value.doubleValue) end
    if value.booleanValue ~= nil then return value.booleanValue == true end
    if value.timestampValue ~= nil then return tostring(value.timestampValue) end
    if value.nullValue ~= nil then return nil end
    local map = value.mapValue and value.mapValue.fields
    if type(map) == "table" then
        local output = {}
        for key, child in pairs(map) do output[key] = _firestore_value(child, depth + 1) end
        return output
    end
    local array = value.arrayValue and value.arrayValue.values
    if type(array) == "table" then
        local output = {}
        for i = 1, #array do output[i] = _firestore_value(array[i], depth + 1) end
        return output
    end
    return nil
end

function M.query(career_id, limit, start_after)
    local fields = {}
    for i = 1, #FIELD_NAMES do fields[i] = { fieldPath = FIELD_NAMES[i] } end
    local query = {
        structuredQuery = {
            select = { fields = fields },
            from = { { collectionId = "builds" } },
            where = {
                fieldFilter = {
                    field = { fieldPath = "careerId" },
                    op = "EQUAL",
                    value = { integerValue = tostring(career_id) },
                },
            },
            orderBy = { {
                field = { fieldPath = "__name__" }, direction = "ASCENDING",
            } },
            limit = limit,
        },
    }
    if start_after then
        query.structuredQuery.startAt = {
            before = false,
            values = { { referenceValue = start_after } },
        }
    end
    return query
end

function M.decode_rows(body, decode, catalog)
    if type(body) ~= "string" then return nil, "response_body" end
    if #body > M.MAX_RESPONSE_BYTES then return nil, "response_too_large" end
    local ok, rows = pcall(decode, body)
    if not ok or type(rows) ~= "table" then return nil, "invalid_json" end
    local builds, rejected, document_count, last_name = {}, 0, 0, nil
    for i = 1, #rows do
        local document = rows[i] and rows[i].document
        if type(document) == "table" and type(document.fields) == "table" then
            document_count = document_count + 1
            last_name = document.name
            local plain = { name = document.name, fields = {} }
            for key, value in pairs(document.fields) do
                plain.fields[key] = _firestore_value(value, 0)
            end
            local build = catalog.normalize_document(plain)
            if build then
                builds[#builds + 1] = build
            else
                rejected = rejected + 1
            end
        end
    end
    return builds, nil, rejected, {
        document_count = document_count,
        last_name = last_name,
    }
end

function M.new(options)
    assert(type(options) == "table", "Ranald Firestore requires options")
    local catalog = assert(options.catalog, "Ranald Firestore requires catalog")
    local get_curl = assert(options.get_curl, "Ranald Firestore requires get_curl")
    local get_json = assert(options.get_json, "Ranald Firestore requires get_json")
    local api = { generation = 0, pending = false }

    function api.cancel()
        api.generation = api.generation + 1
        api.pending = false
    end

    function api.fetch(career_id, callback)
        if not catalog.CAREERS[tonumber(career_id)] then return false, "career_id" end
        if type(callback) ~= "function" then return false, "callback" end
        local curl = get_curl()
        local json = get_json()
        if not curl or type(curl.post) ~= "function" then return false, "curl_unavailable" end
        if not json or type(json.encode) ~= "function" or type(json.decode) ~= "function" then
            return false, "json_unavailable"
        end
        api.generation = api.generation + 1
        local generation = api.generation
        api.pending = true
        local aggregate, rejected_total, bytes_total = {}, 0, 0
        local function finish_error(reason)
            if generation ~= api.generation then return end
            api.pending = false
            callback(nil, reason)
        end
        local request_batch
        request_batch = function(start_after)
            local remaining = M.MAX_RESULTS - #aggregate
            local limit = math.min(M.BATCH_SIZE, remaining)
            local ok_body, body = pcall(json.encode,
                M.query(tonumber(career_id), limit, start_after))
            if not ok_body then finish_error("query_encode"); return false end
            local function done(success, code, headers, data, userdata)
                if generation ~= api.generation then return end
                if not success or tonumber(code) ~= 200 then
                    finish_error("http_" .. tostring(code or "failed")); return
                end
                bytes_total = bytes_total + #(data or "")
                if bytes_total > M.MAX_TOTAL_BYTES then
                    finish_error("response_total_too_large"); return
                end
                local builds, err, rejected, meta = M.decode_rows(data, json.decode, catalog)
                if not builds then finish_error(err); return end
                rejected_total = rejected_total + rejected
                for i = 1, #builds do aggregate[#aggregate + 1] = builds[i] end
                local full_batch = meta.document_count == limit
                if full_batch and #aggregate < M.MAX_RESULTS and meta.last_name then
                    request_batch(meta.last_name)
                    return
                end
                api.pending = false
                callback(aggregate, nil, {
                    rejected = rejected_total, bytes = bytes_total,
                    truncated = full_batch and #aggregate >= M.MAX_RESULTS,
                })
            end
            local ok_post, post_err = pcall(curl.post, curl, M.ENDPOINT, body,
                { "Content-Type: application/json" }, done,
                { generation = generation, career_id = career_id }, {})
            if not ok_post then
                finish_error("request_failed:" .. tostring(post_err))
                return false
            end
            return true
        end
        if not request_batch(nil) then return false, "request_failed" end
        return true, generation
    end

    return api
end

return M
