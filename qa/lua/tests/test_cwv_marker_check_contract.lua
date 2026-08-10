-- Issue #1148 / #1156: the three cwv marker checks were relocated out of the entry file into
-- `_cwv_regression_identity.lua`, but the marker constants stayed file-scope locals in the
-- entry. Read as bare globals they resolved to nil, so the checks reported "was the fix
-- reverted?" FAIL against code that was verifiably present -- BUG_CLASSES 85 sub-pattern (b),
-- a marker scope-break. The repair publishes the constants on the mod table; nothing offline
-- held that repair in place.
--
-- These cases execute the REAL check bodies, lifted verbatim from the shipped module, and feed
-- them a marker table built from the values the ENTRY file authors. That is the independent
-- ground truth (5.1d rule 1): if the check's expected literal and the entry's published literal
-- ever drift apart, the check returns a reason and these cases fail. The module cannot be
-- loaded outright -- it uses Stingray's `goto` extension, which vanilla Lua 5.1 rejects -- so
-- per-check extraction is how the production text gets exercised rather than paraphrased.
return function(H, repo_root)
    local root = repo_root
        .. "/character_weapon_variants/scripts/mods/character_weapon_variants/"

    local function read(name)
        local file = assert(io.open(root .. name, "rb"))
        local source = file:read("*a")
        file:close()
        return source
    end

    local entry = read("character_weapon_variants.lua")
    local identity = read("_cwv_regression_identity.lua")

    -- The authored marker values, taken from the entry's own local definitions. Everything the
    -- checks are asserted against below descends from these, never from the checks themselves.
    local MARKER_LOCALS = {
        nl_rawget = "CT_CWV_NETWORKLOOKUP_RAWGET_MARKER_v0_1_332",
        iml_rawget = "CT_CWV_ITEMMASTERLIST_RAWGET_MARKER_v0_1_333",
        slot_extension = "CT_CWV_SLOT_EXTENSION_MARKER_v0_1_338",
    }

    local function authored_markers()
        local markers = {}
        for field, const in pairs(MARKER_LOCALS) do
            local value = entry:match("local%s+" .. const .. '%s*=%s*"([^"]+)"')
            H.truthy(value, const .. " is no longer defined in the cwv entry file")
            markers[field] = value
        end
        return markers
    end

    -- Lift `_rt_register("<name>", function() ... end)` from the module: the registration line
    -- through the first column-anchored `end)`.
    local function extract_check(name)
        local pattern = '_rt_register("' .. name .. '", function()'
        local from = identity:find(pattern, 1, true)
        H.truthy(from, name .. " is no longer registered in _cwv_regression_identity.lua")
        local line_start = identity:sub(1, from):match("()[^\n]*$")
        local block_end = identity:find("\nend)\n", from, true)
        H.truthy(block_end, name .. " check block has no column-anchored end)")
        local block = identity:sub(line_start, block_end + 5)
        local chunk, err = loadstring("local _rt_register, mod, _om = ...\n" .. block, "@" .. name)
        H.truthy(chunk, name .. " did not compile in isolation: " .. tostring(err))
        return chunk
    end

    -- A world in which all three checks should pass: markers published as the entry authors
    -- them, the collector published on _om, and engine tables shaped the way the fixes expect.
    local function make_world(overrides)
        overrides = overrides or {}
        local mod = { _cwv_fix_markers = overrides.markers ~= false and authored_markers() or nil }
        if overrides.marker_value then
            for field, value in pairs(overrides.marker_value) do
                mod._cwv_fix_markers[field] = value
            end
        end
        local _om = {
            _slot_extension_log_only = overrides.log_only ~= false,
            _collect_cross_slot_careers = overrides.collector ~= false and function()
                return { es_huntsman = true, es_knight = true, es_mercenary = true, es_questingknight = true }
            end or nil,
        }
        return mod, _om
    end

    local function run_check(name, overrides)
        local chunk = extract_check(name)
        local mod, _om = make_world(overrides)
        local captured
        local saved = {
            ItemMasterList = _G.ItemMasterList,
            NetworkLookup = _G.NetworkLookup,
            CareerSettings = _G.CareerSettings,
        }
        -- Strict metatable, exactly like the engine table the rawget fixes exist to survive.
        _G.ItemMasterList = setmetatable({}, {
            __index = function(_, key) error("ItemMaster List has no item " .. tostring(key)) end,
        })
        _G.NetworkLookup = { damage_profiles = {}, pickup_names = {} }
        _G.CareerSettings = {
            es_huntsman = { item_slot_types_by_slot_name = { slot_melee = { "melee", "ranged" } } },
            es_knight = { item_slot_types_by_slot_name = { slot_melee = { "melee", "ranged" } } },
            es_mercenary = { item_slot_types_by_slot_name = { slot_melee = { "melee", "ranged" } } },
            es_questingknight = { item_slot_types_by_slot_name = { slot_melee = { "melee", "ranged" } } },
            dr_slayer = { item_slot_types_by_slot_name = { slot_melee = { "melee" } } },
        }
        chunk(function(_, fn) captured = fn end, mod, _om)
        H.equal(type(captured), "function")
        local ok, verdict = pcall(captured)
        for key, value in pairs(saved) do _G[key] = value end
        H.truthy(ok, name .. " raised instead of returning a verdict: " .. tostring(verdict))
        return verdict
    end

    local CHECKS = {
        "cwv_itemmasterlist_uses_rawget",
        "cwv_networklookup_uses_rawget",
        "cwv_slot_extension_scoped",
    }

    H.test("CWV marker checks pass against the values the entry actually publishes", function()
        for _, name in ipairs(CHECKS) do
            H.equal(run_check(name), nil,
                name .. " disagrees with the marker value authored in the entry file")
        end
    end)

    H.test("CWV marker checks fail loudly when the publication is missing", function()
        -- #1148 itself: the read resolves to nil. Rule 2 says that must be a verdict about the
        -- read, not a silent comparison of nil against nil.
        for _, name in ipairs(CHECKS) do
            local verdict = run_check(name, { markers = false })
            H.equal(type(verdict), "string",
                name .. " returned no reason when mod._cwv_fix_markers was absent")
            H.truthy(verdict:find("marker", 1, true) or verdict:find("MARKER", 1, true))
        end
    end)

    H.test("CWV marker checks fail when a marker value drifts from the entry", function()
        local cases = {
            { "cwv_itemmasterlist_uses_rawget", { iml_rawget = "reverted" } },
            { "cwv_networklookup_uses_rawget", { nl_rawget = "reverted" } },
            { "cwv_slot_extension_scoped", { slot_extension = "reverted" } },
        }
        for _, case in ipairs(cases) do
            H.equal(type(run_check(case[1], { marker_value = case[2] })), "string",
                case[1] .. " accepted a reverted marker value")
        end
    end)

    -- Does `name` appear as CODE (not inside a line comment)? The relocated module cites the
    -- constants by name in prose, which is fine; what must never come back is a read of one.
    local function appears_in_code(source, name)
        for line in (source .. "\n"):gmatch("([^\n]*)\n") do
            local code = line:match("^(.-)%-%-") or line
            if code:find(name, 1, true) then return true, line end
        end
        return false
    end

    H.test("CWV marker checks read the mod table, never the entry's file-scope locals", function()
        -- The scope break that produced #1148 is a bare-global read of the constant name. If one
        -- reappears in the relocated module, the check silently compares nil to a string again.
        for _, const in pairs(MARKER_LOCALS) do
            local found, line = appears_in_code(identity, const)
            H.equal(found, false,
                const .. " is read in code in _cwv_regression_identity.lua; it is an entry-file "
                    .. "local and resolves to nil there (#1148): " .. tostring(line))
            H.truthy(entry:find("local " .. const, 1, true))
        end
        H.truthy(entry:find("mod._cwv_fix_markers = {", 1, true))
        for _, name in ipairs(CHECKS) do
            local from = identity:find('_rt_register("' .. name .. '", function()', 1, true)
            local to = identity:find("\nend)\n", from, true)
            local body = identity:sub(from, to)
            H.truthy(body:find("mod._cwv_fix_markers", 1, true),
                name .. " no longer reads the published marker table")
            -- The nil-guard is what turns an absent publication into a reason string instead of
            -- an index error on a nil value.
            H.truthy(body:find("mod._cwv_fix_markers\n", 1, true)
                or body:find("mod._cwv_fix_markers and", 1, true)
                or body:find("(mod._cwv_fix_markers", 1, true),
                name .. " reads the marker table without a nil-guard")
        end
    end)

    H.test("CWV slot-extension check fails when the collector publication breaks", function()
        -- The same relocation broke a CALL rather than a read: the collector is an entry-file
        -- local, and invoking it as a bare global ERRORED instead of misreading. The check must
        -- now report the scope break as a verdict.
        local verdict = run_check("cwv_slot_extension_scoped", { collector = false })
        H.equal(type(verdict), "string")
        H.truthy(verdict:find("collector", 1, true))
        H.truthy(verdict:find("1148", 1, true) or verdict:find("scope break", 1, true))
        -- #1159: the collector and its `_om` publication moved into the musket
        -- equip-surface owner with the career slot_melee override it feeds. The
        -- publication is what matters, not which file holds it -- the check in
        -- _cwv_regression_identity.lua reads it back off `_om`.
        H.truthy(read("_cwv_musket_equip_surface.lua"):find("_collect_cross_slot_careers", 1, true),
            "the musket equip-surface owner no longer publishes the cross-slot collector on _om")
        H.equal(entry:find("_collect_cross_slot_careers", 1, true), nil,
            "the entry must not keep a second cross-slot collector")
    end)

    H.test("CWV slot-extension check still guards the issue-570 log-only state", function()
        local verdict = run_check("cwv_slot_extension_scoped", { log_only = false })
        H.equal(type(verdict), "string")
        H.truthy(verdict:find("log-only", 1, true))
    end)
end
