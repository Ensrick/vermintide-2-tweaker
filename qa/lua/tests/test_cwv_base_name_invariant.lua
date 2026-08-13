-- #1125: execute the shipped cwv_inherits_base_name regression body against
-- exact base, nil, wrong-base, and cwv-key identities. Native item/damage
-- decoding needs equality with def.base_weapon; rejecting only a cwv_ prefix
-- is insufficient.
return function(H, repo_root)
    local path = repo_root
        .. "/character_weapon_variants/scripts/mods/character_weapon_variants/"
        .. "_cwv_regression_identity.lua"
    local file = assert(io.open(path, "rb"))
    local source = file:read("*a")
    file:close()

    local function run(rows)
        local captured
        local pattern = '_rt_register("cwv_inherits_base_name", function()'
        local from = assert(source:find(pattern, 1, true))
        local line_start = assert(source:sub(1, from):match("()[^\n]*$"))
        local block_end = assert(source:find("\nend)\n", from, true))
        local block = source:sub(line_start, block_end + 5)
        local chunk = assert(loadstring(
            "local _rt_register, _rt_iter_cwv_entries = ...\n" .. block,
            "@cwv_inherits_base_name_fixture"))
        chunk(function(_, fn) captured = fn end, function() return rows, nil end)
        return captured()
    end

    H.test("CWV #1125 exact base-name identity passes", function()
        H.equal(run({
            { key = "cwv_exact", entry = { name = "es_1h_sword" },
                def = { base_weapon = "es_1h_sword" } },
        }), nil)
    end)

    H.test("CWV #1125 nil clone name fails", function()
        local verdict = run({
            { key = "cwv_nil", entry = {},
                def = { base_weapon = "es_1h_sword" } },
        })
        H.equal(type(verdict), "string")
        H.truthy(verdict:find("name=nil base=es_1h_sword", 1, true))
    end)

    H.test("CWV #1125 wrong vanilla base fails", function()
        local verdict = run({
            { key = "cwv_wrong", entry = { name = "dr_1h_axe" },
                def = { base_weapon = "es_1h_sword" } },
        })
        H.equal(type(verdict), "string")
        H.truthy(verdict:find("name=dr_1h_axe base=es_1h_sword", 1, true))
    end)

    H.test("CWV #1125 cwv-key clobber still fails", function()
        local verdict = run({
            { key = "cwv_bad", entry = { name = "cwv_bad" },
                def = { base_weapon = "es_1h_sword" } },
        })
        H.equal(type(verdict), "string")
        H.truthy(verdict:find("name=cwv_bad base=es_1h_sword", 1, true))
    end)

    H.test("CWV #1125 absent authored base cannot satisfy nil equality", function()
        local verdict = run({
            { key = "cwv_no_base", entry = {}, def = {} },
        })
        H.equal(type(verdict), "string")
        H.truthy(verdict:find("name=nil base=nil", 1, true))
    end)

    H.test("CWV #1125 check source pins exact base identity", function()
        H.truthy(source:find(
            'if type(e.def.base_weapon) ~= "string" or n ~= e.def.base_weapon then',
            1, true))
        H.truthy(source:find("entry.name must equal exact base_weapon", 1, true))
        H.equal(source:find('n:sub(1, 4) == "cwv_"', 1, true), nil)
    end)
end
