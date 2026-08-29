-- Boundary test for the #1159 Moonfire Bow AOE owner extraction (wt + wt_dev).
--
-- Engine-free. Asserts the structural contract of the split across BOTH streams
-- of the mirror pair: bare-dofile wiring at the former execution position, hook
-- ownership and cardinality on the six projectile-impact seams, entry-side
-- absence of every moved file-scope local, the #428 shared registration owner
-- that keeps the AoE template resolvable locally and wire-deterministic, the single
-- annotated native particle boundary (resource-safety token
-- wt_535_moonfire_aoe_owner), and exact public/dev parity of the owner itself.
return function(H, repo_root)
    local STREAMS = {
        {
            tag = "wt",
            dir = repo_root .. "/weapon_tweaker/scripts/mods/weapon_tweaker/",
            entry = "weapon_tweaker.lua",
            ns = "weapon_tweaker",
            mod_id = "wt",
        },
        {
            tag = "wt_dev",
            dir = repo_root .. "/weapon_tweaker_dev/scripts/mods/weapon_tweaker_dev/",
            entry = "weapon_tweaker_dev.lua",
            ns = "weapon_tweaker_dev",
            mod_id = "wt_dev",
        },
    }

    local function read(path)
        local file = assert(io.open(path, "rb"))
        local source = file:read("*a")
        file:close()
        return source
    end

    local function count_plain(source, needle)
        local count, cursor = 0, 1
        while true do
            local at = source:find(needle, cursor, true)
            if not at then return count end
            count = count + 1
            cursor = at + #needle
        end
    end

    local MOONFIRE_NAME = "wt_moonfire_aoe_revert"
    local FALLBACK_NAME = "machinegun_poison_arrow"
    local CHECK_NAME = "wt_535_moonfire_explosion_registered"

    local function lookup_with_fallback()
        return {
            [1] = FALLBACK_NAME,
            [FALLBACK_NAME] = 1,
        }
    end

    local function raw_snapshot(value)
        local snapshot = {
            metatable = getmetatable(value),
            values = {},
            count = 0,
        }
        for key, entry in next, value do
            snapshot.count = snapshot.count + 1
            rawset(snapshot.values, key, entry)
        end
        return snapshot
    end

    local function assert_raw_unchanged(value, snapshot, label)
        H.equal(getmetatable(value), snapshot.metatable, label .. " changed metatable")
        local count = 0
        for key, entry in next, value do
            count = count + 1
            H.equal(rawget(snapshot.values, key), entry, label .. " changed or added a row")
        end
        H.equal(count, snapshot.count, label .. " changed row count")
        for key, entry in next, snapshot.values do
            H.equal(rawget(value, key), entry, label .. " changed or removed a row")
        end
    end

    local function count_log(logs, needle)
        local count = 0
        for i = 1, #logs do
            if logs[i]:find(needle, 1, true) then
                count = count + 1
            end
        end
        return count
    end

    local function execute_owner(stream, network_lookup, load_count)
        local callbacks = {}
        local logs = {}
        local helper_loads = 0
        local mod = { _wt = {} }
        mod._wt.rt_register = function(name, callback)
            callbacks[name] = callback
        end
        function mod:dofile(requested_path)
            local expected = "scripts/mods/" .. stream.ns .. "/_lib_network_lookup"
            assert(requested_path == expected, "unexpected dofile: " .. tostring(requested_path))
            helper_loads = helper_loads + 1
            return assert(loadfile(stream.dir .. "_lib_network_lookup.lua"))()
        end
        function mod:get()
            return false
        end
        function mod:hook_safe()
            error("projectile hooks must stay dormant in the owner registration harness")
        end

        local env = {
            ExplosionTemplates = {},
            Vector3Box = function()
                return { unbox = function() return 0 end }
            end,
            get_mod = function(mod_id)
                assert(mod_id == stream.mod_id, "unexpected mod id: " .. tostring(mod_id))
                return mod
            end,
            printf = function(format_string, ...)
                logs[#logs + 1] = string.format(format_string, ...)
            end,
        }
        if network_lookup ~= nil then
            env.NetworkLookup = network_lookup
        end
        env._G = env
        setmetatable(env, { __index = _G })

        for _ = 1, load_count or 1 do
            local chunk = assert(loadfile(stream.dir .. "_wt_moonfire_aoe.lua"))
            setfenv(chunk, env)
            chunk()
        end

        return {
            callbacks = callbacks,
            env = env,
            helper_loads = helper_loads,
            logs = logs,
            mod = mod,
        }
    end

    local function contained_check(state, label)
        local ok, result = pcall(state.callbacks[CHECK_NAME])
        H.truthy(ok, label .. " runtime check threw: " .. tostring(result))
        return result
    end

    for _, stream in ipairs(STREAMS) do
        local entry = read(stream.dir .. stream.entry)
        local owner = read(stream.dir .. "_wt_moonfire_aoe.lua")
        local dofile_call = 'mod:dofile("scripts/mods/' .. stream.ns .. '/_wt_moonfire_aoe")'

        H.test(stream.tag .. ": owner is bare-dofile'd exactly once by the entry", function()
            H.equal(count_plain(entry, dofile_call), 1)
            -- Bare dofile, not an installer call. The module body must run at
            -- file scope exactly where the block used to execute, which is what
            -- preserves hook-registration order and the _rt_register append order.
            H.equal(count_plain(owner, "function M.install"), 0)
            H.equal(count_plain(owner, "return function"), 0)
            H.equal(count_plain(owner, 'local mod = get_mod("' .. stream.mod_id .. '")'), 1)
            -- The moved lines closed over the entry's file-scope _rt_register.
            -- The owner must re-read the same published function, not invent one.
            H.equal(count_plain(owner, "local _rt_register = mod._wt.rt_register"), 1)
        end)

        H.test(stream.tag .. ": dofile sits between _wt_regression and the 3P swap dispatch", function()
            local regression_at = entry:find('mod:dofile("scripts/mods/' .. stream.ns .. '/_wt_regression")', 1, true)
            local owner_at = entry:find(dofile_call, 1, true)
            -- The 3P swap dispatch became its own owner in the #1159 wave-14
            -- slice, so its bare dofile is now the downstream anchor that the
            -- forward declarations used to be.
            local swap_at = entry:find('mod:dofile("scripts/mods/' .. stream.ns .. '/_wt_ingame_3p_swap_owner")', 1, true)
            H.truthy(regression_at, "_wt_regression dofile must exist in the entry")
            H.truthy(owner_at, "moonfire owner dofile must exist in the entry")
            H.truthy(swap_at, "the 3P swap owner dofile must exist in the entry")
            -- _rt_register must already be published, and the impact hooks must
            -- still register before the cross-character swap dispatch below.
            H.truthy(regression_at < owner_at, "moonfire owner must load after _wt_regression")
            H.truthy(owner_at < swap_at, "moonfire owner must load before the 3P swap dispatch")
        end)

        H.test(stream.tag .. ": the impact hook loop is owned once, and left the entry", function()
            -- One source registration site expanding to 2 classes x 3 methods.
            H.equal(count_plain(owner, "mod:hook_safe(cls, method_name, function(self, impact_data, hit_unit, hit_position)"), 1)
            H.equal(count_plain(entry, "mod:hook_safe(cls, method_name,"), 0)
            -- Quoted class names only: the entry still carries an unrelated
            -- PlayerProjectileUnitExtension mention in a #431 damage-profile
            -- comment, which is prose, not a hook root.
            for _, needle in ipairs({
                '"PlayerProjectileUnitExtension"',
                '"PlayerProjectileHuskExtension"',
                "_moonfire_hooked_classes",
                "_moonfire_hooked_methods",
            }) do
                H.equal(count_plain(owner, needle) > 0, true, needle .. " must live in the owner")
                H.equal(count_plain(entry, needle), 0, needle .. " must not remain in the entry")
            end
            -- Whole-mod cardinality on the three impact methods: nothing outside
            -- the owner may re-hook them, in either stream.
            for _, method in ipairs({ '"hit_enemy"', '"hit_level_unit"', '"hit_non_level_unit"' }) do
                H.equal(count_plain(entry, method), 0, method .. " must not be referenced by the entry")
            end
        end)

        H.test(stream.tag .. ": every moved file-scope local left the entry", function()
            for _, decl in ipairs({
                "local _MOONFIRE_PUFF_FX",
                "local _MOONFIRE_AOE_NAME",
                "local _MOONFIRE_AOE_TEMPLATE",
                "local _moonfire_jitter_offsets",
                "local function _is_moonfire_arrow",
                "local function _wt_moonfire_on_hit",
            }) do
                H.equal(count_plain(owner, decl), 1, decl .. " must be declared once in the owner")
                H.equal(count_plain(entry, decl), 0, decl .. " must not remain in the entry")
            end
            -- The toggle read is the owner's only settings dependency.
            H.equal(count_plain(owner, 'mod:get("moonfire_aoe_revert")'), 1)
            H.equal(count_plain(entry, 'mod:get("moonfire_aoe_revert")'), 0)
        end)

        H.test(stream.tag .. ": #535 registration consumes the #428 shared helper", function()
            -- Local resolution: ExplosionUtils.get_template reads ExplosionTemplates
            -- by the .name the template itself carries, so both must be present.
            H.equal(count_plain(owner, "name = _MOONFIRE_AOE_NAME,"), 1)
            H.equal(count_plain(owner, "ExplosionTemplates[_MOONFIRE_AOE_NAME] = _MOONFIRE_AOE_TEMPLATE"), 1)
            -- Wire index determinism belongs to the canonical helper. The owner
            -- must not retain a private length-based or half-pair append.
            H.equal(count_plain(owner, 'mod:dofile("scripts/mods/' .. stream.ns .. '/_lib_network_lookup")'), 1)
            H.equal(count_plain(owner, "_network_lookup.register_named("), 1)
            H.equal(count_plain(owner, '"explosion_templates",'), 1)
            H.equal(count_plain(owner, "rawset(lookup, idx, _MOONFIRE_AOE_NAME)"), 0)
            H.equal(count_plain(owner, "rawset(lookup, _MOONFIRE_AOE_NAME, idx)"), 0)
            H.equal(count_plain(owner, "#lookup + 1"), 0)
            H.equal(count_plain(owner, 'local _MOONFIRE_FALLBACK_NAME = "machinegun_poison_arrow"'), 1)
            H.equal(count_plain(owner, "mod._wt535_explosion_template_fallback[_MOONFIRE_AOE_NAME] = _MOONFIRE_FALLBACK_NAME"), 1)
            -- The regression check moved with the code it guards.
            H.equal(count_plain(owner, '_rt_register("wt_535_moonfire_explosion_registered"'), 1)
            H.equal(count_plain(entry, "wt_535_moonfire_explosion_registered"), 0)
        end)

        H.test(stream.tag .. ": the single native particle boundary stays annotated", function()
            H.equal(count_plain(owner, "World.create_particles("), 1)
            H.equal(count_plain(owner, "-- resource-safety: wt_535_moonfire_aoe_owner"), 1)
            -- The FX id is the Moonbow's own authored effect; it must not be
            -- rewritten into a free-standing string literal at the call site.
            H.equal(count_plain(owner, 'local _MOONFIRE_PUFF_FX = "fx/wpnfx_we_deus_01_impact"'), 1)
            H.equal(count_plain(owner, "World.create_particles(world, _MOONFIRE_PUFF_FX, p, Quaternion.identity())"), 1)
        end)
    end

    H.test("WT mirror pair owns exact canonical NetworkLookup helper copies", function()
        local canonical = read(repo_root .. "/tools/shared_lib/_lib_network_lookup.lua")
        local manifest = read(repo_root .. "/tools/shared_lib/manifest.psd1")
        for _, stream in ipairs(STREAMS) do
            H.equal(read(stream.dir .. "_lib_network_lookup.lua"), canonical,
                stream.tag .. " helper copy drifted")
            local consumer = '"' .. stream.dir:sub(#repo_root + 2)
                .. '_lib_network_lookup.lua"'
            consumer = consumer:gsub("\\", "/")
            H.equal(count_plain(manifest, consumer), 1,
                stream.tag .. " helper is absent or duplicated in the manifest")
        end
    end)

    for _, stream in ipairs(STREAMS) do
        H.test(stream.tag .. ": owner inserts once and a reload is idempotent", function()
            local lookup = lookup_with_fallback()
            local network_lookup = { explosion_templates = lookup }
            local state = execute_owner(stream, network_lookup, 2)

            H.equal(state.helper_loads, 2)
            H.equal(rawget(lookup, 2), MOONFIRE_NAME)
            H.equal(rawget(lookup, MOONFIRE_NAME), 2)
            H.equal(#lookup, 2)
            H.equal(count_log(state.logs, "[wt:535] registered"), 1)
            H.equal(count_log(state.logs, "[wt:428] rejected"), 0)
            H.equal(state.callbacks[CHECK_NAME](), nil)
            H.equal(rawget(state.mod._wt535_explosion_template_fallback, MOONFIRE_NAME),
                FALLBACK_NAME)
        end)

        H.test(stream.tag .. ": an existing symmetric pair is accepted without mutation", function()
            local lookup = lookup_with_fallback()
            rawset(lookup, 2, MOONFIRE_NAME)
            rawset(lookup, MOONFIRE_NAME, 2)
            local snapshot = raw_snapshot(lookup)
            local state = execute_owner(stream, { explosion_templates = lookup })

            assert_raw_unchanged(lookup, snapshot, stream.tag .. " existing pair")
            H.equal(count_log(state.logs, "[wt:535] registered"), 0)
            H.equal(count_log(state.logs, "[wt:428] rejected"), 0)
            H.equal(state.callbacks[CHECK_NAME](), nil)
        end)

        H.test(stream.tag .. ": strict outer and child lookup metatables are bypassed", function()
            local strict = {
                __index = function() error("strict __index reached") end,
                __newindex = function() error("strict __newindex reached") end,
            }
            local lookup = setmetatable(lookup_with_fallback(), strict)
            local network_lookup = setmetatable({ explosion_templates = lookup }, strict)
            local state = execute_owner(stream, network_lookup)

            H.equal(rawget(lookup, 2), MOONFIRE_NAME)
            H.equal(rawget(lookup, MOONFIRE_NAME), 2)
            H.equal(getmetatable(lookup), strict)
            H.equal(getmetatable(network_lookup), strict)
            H.equal(state.callbacks[CHECK_NAME](), nil)
        end)

        H.test(stream.tag .. ": malformed lookup shapes reject without mutation", function()
            local cases = {
                {
                    label = "sparse numeric axis",
                    reason = "numeric_side_sparse",
                    make = function()
                        local lookup = lookup_with_fallback()
                        rawset(lookup, 3, "other")
                        rawset(lookup, "other", 3)
                        return lookup
                    end,
                },
                {
                    label = "forward-only target pair",
                    reason = "pair_asymmetric",
                    make = function()
                        local lookup = lookup_with_fallback()
                        rawset(lookup, 2, MOONFIRE_NAME)
                        return lookup
                    end,
                },
                {
                    label = "reverse-only target pair",
                    reason = "pair_asymmetric",
                    make = function()
                        local lookup = lookup_with_fallback()
                        rawset(lookup, MOONFIRE_NAME, 2)
                        return lookup
                    end,
                },
                {
                    label = "foreign key type",
                    reason = "lookup_key_invalid",
                    make = function()
                        local lookup = lookup_with_fallback()
                        rawset(lookup, true, "foreign")
                        return lookup
                    end,
                },
            }
            local strict = {
                __index = function() error("strict __index reached") end,
                __newindex = function() error("strict __newindex reached") end,
            }

            for i = 1, #cases do
                local case = cases[i]
                local lookup = setmetatable(case.make(), strict)
                local network_lookup = setmetatable({ explosion_templates = lookup }, strict)
                local lookup_snapshot = raw_snapshot(lookup)
                local outer_snapshot = raw_snapshot(network_lookup)
                local state = execute_owner(stream, network_lookup, 2)

                assert_raw_unchanged(lookup, lookup_snapshot,
                    stream.tag .. " " .. case.label .. " child")
                assert_raw_unchanged(network_lookup, outer_snapshot,
                    stream.tag .. " " .. case.label .. " outer")
                H.equal(count_log(state.logs, "[wt:535] registered"), 0)
                H.equal(count_log(state.logs, "[wt:428] rejected"), 1,
                    case.label .. " rejection log was not bounded across reload")
                local result = state.callbacks[CHECK_NAME]()
                H.truthy(type(result) == "string" and result:find(case.reason, 1, true),
                    case.label .. " rejection reason did not reach the runtime check")
            end
        end)

        H.test(stream.tag .. ": absent lookup axes remain absent and do not throw", function()
            local missing_all = execute_owner(stream, nil, 2)
            H.equal(count_log(missing_all.logs, "network_lookup_missing"), 1)
            H.truthy(missing_all.callbacks[CHECK_NAME]():find("skip:", 1, true))

            local strict = {
                __index = function() error("strict __index reached") end,
                __newindex = function() error("strict __newindex reached") end,
            }
            local network_lookup = setmetatable({}, strict)
            local snapshot = raw_snapshot(network_lookup)
            local missing_child = execute_owner(stream, network_lookup, 2)
            assert_raw_unchanged(network_lookup, snapshot, stream.tag .. " missing child")
            H.equal(count_log(missing_child.logs, "lookup_missing"), 1)
            H.truthy(missing_child.callbacks[CHECK_NAME]():find("skip:", 1, true))
        end)

        H.test(stream.tag .. ": present malformed lookup axes fail closed without mutation", function()
            local strict = {
                __index = function() error("strict __index reached") end,
                __newindex = function() error("strict __newindex reached") end,
            }
            local cases = {
                {
                    label = "string child",
                    reason = "lookup_missing",
                    shape = "NetworkLookup.explosion_templates:string",
                    network_lookup = setmetatable({ explosion_templates = "bogus" }, strict),
                },
                {
                    label = "false child",
                    reason = "lookup_missing",
                    shape = "NetworkLookup.explosion_templates:boolean",
                    network_lookup = setmetatable({ explosion_templates = false }, strict),
                },
                {
                    label = "string outer",
                    reason = "network_lookup_missing",
                    shape = "NetworkLookup:string",
                    network_lookup = "bogus",
                },
            }

            for i = 1, #cases do
                local case = cases[i]
                local before = type(case.network_lookup) == "table"
                    and raw_snapshot(case.network_lookup)
                    or case.network_lookup
                local state = execute_owner(stream, case.network_lookup, 2)

                if type(case.network_lookup) == "table" then
                    assert_raw_unchanged(
                        case.network_lookup,
                        before,
                        stream.tag .. " " .. case.label
                    )
                else
                    H.equal(state.env.NetworkLookup, before,
                        case.label .. " changed the outer lookup value")
                end
                H.equal(count_log(state.logs, "[wt:535] registered"), 0)
                H.equal(count_log(state.logs, "[wt:428] rejected"), 1,
                    case.label .. " rejection log was not bounded across reload")
                local result = contained_check(
                    state,
                    stream.tag .. " " .. case.label
                )
                H.truthy(type(result) == "string"
                    and result:find("registration rejected", 1, true),
                    case.label .. " false-skipped instead of failing closed")
                H.truthy(result:find(case.reason, 1, true),
                    case.label .. " omitted the helper rejection reason")
                H.truthy(result:find(case.shape, 1, true),
                    case.label .. " omitted the malformed raw shape")
            end
        end)

        H.test(stream.tag .. ": runtime check catches a post-registration remap", function()
            local lookup = lookup_with_fallback()
            local state = execute_owner(stream, { explosion_templates = lookup })
            rawset(lookup, MOONFIRE_NAME, 1)
            local result = state.callbacks[CHECK_NAME]()
            H.truthy(type(result) == "string"
                and result:find("index changed after registration", 1, true))
        end)

        H.test(stream.tag .. ": fallback proof rejects missing and corrupted round trips", function()
            local mutations = {
                {
                    label = "nonnumeric fallback",
                    change = function(lookup)
                        rawset(lookup, FALLBACK_NAME, "bogus")
                    end,
                },
                {
                    label = "fallback remapped to the Moonfire index",
                    change = function(lookup)
                        rawset(lookup, FALLBACK_NAME, rawget(lookup, MOONFIRE_NAME))
                    end,
                },
                {
                    label = "fallback reverse row changed",
                    change = function(lookup)
                        rawset(lookup, 1, "other")
                    end,
                },
            }

            for i = 1, #mutations do
                local mutation = mutations[i]
                local lookup = lookup_with_fallback()
                local state = execute_owner(stream, { explosion_templates = lookup })
                mutation.change(lookup)
                local result = state.callbacks[CHECK_NAME]()
                H.truthy(type(result) == "string"
                    and result:find("wire-safe fallback", 1, true),
                    mutation.label .. " produced a false-green runtime check")
            end

            local no_fallback = { [1] = "other", other = 1 }
            local missing_at_load = execute_owner(
                stream,
                { explosion_templates = no_fallback }
            )
            local result = missing_at_load.callbacks[CHECK_NAME]()
            H.truthy(type(result) == "string"
                and result:find("no valid round-trip at registration", 1, true))
        end)

        H.test(stream.tag .. ": a registered lookup axis cannot disappear as a skip", function()
            local network_lookup = { explosion_templates = lookup_with_fallback() }
            local state = execute_owner(stream, network_lookup)
            rawset(network_lookup, "explosion_templates", nil)
            local result = contained_check(state, stream.tag .. " missing registered child")
            H.equal(result, "NetworkLookup.explosion_templates disappeared after registration")

            local invalid_lookup = { explosion_templates = lookup_with_fallback() }
            local invalid_state = execute_owner(stream, invalid_lookup)
            rawset(invalid_lookup, "explosion_templates", "bogus")
            local invalid_result = contained_check(
                invalid_state,
                stream.tag .. " non-table registered child"
            )
            H.truthy(type(invalid_result) == "string"
                and invalid_result:find("became invalid after registration", 1, true))
        end)

        H.test(stream.tag .. ": fallback map shape and exact identity fail closed", function()
            local non_table = execute_owner(
                stream,
                { explosion_templates = lookup_with_fallback() }
            )
            non_table.mod._wt535_explosion_template_fallback = 42
            local non_table_result = contained_check(
                non_table,
                stream.tag .. " non-table fallback map"
            )
            H.truthy(type(non_table_result) == "string"
                and non_table_result:find("fallback map missing or invalid", 1, true))

            local strict = {
                __index = function() error("strict __index reached") end,
                __newindex = function() error("strict __newindex reached") end,
            }
            local strict_state = execute_owner(
                stream,
                { explosion_templates = lookup_with_fallback() }
            )
            strict_state.mod._wt535_explosion_template_fallback = setmetatable({
                [MOONFIRE_NAME] = FALLBACK_NAME,
            }, strict)
            H.equal(contained_check(
                strict_state,
                stream.tag .. " strict valid fallback map"
            ), nil)

            strict_state.mod._wt535_explosion_template_fallback = setmetatable({}, strict)
            local strict_missing_result = contained_check(
                strict_state,
                stream.tag .. " strict missing fallback row"
            )
            H.truthy(type(strict_missing_result) == "string"
                and strict_missing_result:find("fallback identity changed", 1, true))

            local lookup = lookup_with_fallback()
            local substituted = execute_owner(stream, { explosion_templates = lookup })
            local other_name = "planted_other_fallback"
            rawset(lookup, 1, other_name)
            rawset(lookup, FALLBACK_NAME, nil)
            rawset(lookup, other_name, 1)
            rawset(
                substituted.mod._wt535_explosion_template_fallback,
                MOONFIRE_NAME,
                other_name
            )
            local substituted_result = contained_check(
                substituted,
                stream.tag .. " substituted fallback identity"
            )
            H.truthy(type(substituted_result) == "string"
                and substituted_result:find("fallback identity changed", 1, true))
        end)
    end

    H.test("public and dev owners are identical after stream normalization", function()
        local public_owner = read(STREAMS[1].dir .. "_wt_moonfire_aoe.lua")
        local dev_owner = read(STREAMS[2].dir .. "_wt_moonfire_aoe.lua")
        local normalized = dev_owner
            :gsub('get_mod%("wt_dev"%)', 'get_mod("wt")')
            :gsub("scripts/mods/weapon_tweaker_dev/_lib_network_lookup",
                "scripts/mods/weapon_tweaker/_lib_network_lookup")
        H.equal(normalized, public_owner)
    end)
end
