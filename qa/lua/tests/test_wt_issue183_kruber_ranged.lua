-- Offline twin of the issue183_kruber_ranged_availability_contract runtime
-- check. Executes the REAL dev owners (weapon_tweaker_dev_localization +
-- weapon_tweaker_dev_data build the actual widget tree, #408 sort, and #611
-- master buckets; wt_unlock_data supplies the expanded map; wt_port_status
-- supplies the #108 metadata mirror) and drives the same
-- wt_universal_availability.kruber_ranged_contract audit the in-game suite
-- runs, plus planted-failure proofs for each failure class.
return function(H, repo_root)
    local dev_root = repo_root .. "/weapon_tweaker_dev/"
    local script_root = dev_root .. "scripts/mods/weapon_tweaker_dev/"
    local policy = dofile(script_root .. "wt_universal_availability.lua")
    local Masters = assert(loadfile(script_root .. "_wt_master_toggles.lua"))()
    local port_status = dofile(script_root .. "wt_port_status.lua")

    local function with_dev_mod(fn)
        local previous_get_mod = get_mod
        local previous_printf = printf
        local mod = {}
        function mod:dofile(path)
            return dofile(dev_root .. path .. ".lua")
        end
        function mod:localize(key) return key end
        function mod:get() return false end
        function mod:debug() end
        function mod:info() end
        function mod:warning() end
        function mod:echo() end
        function mod:command() end
        function mod:set() end
        local cwv = { is_enabled = function() return true end }
        get_mod = function(name)
            if name == "wt_dev" then return mod end
            if name == "character_weapon_variants" then return cwv end
        end
        printf = function() end
        local ok, result = pcall(fn, mod)
        get_mod = previous_get_mod
        printf = previous_printf
        if not ok then error(result, 0) end
        return result
    end

    local built = with_dev_mod(function(mod)
        dofile(script_root .. "weapon_tweaker_dev_localization.lua")
        dofile(script_root .. "weapon_tweaker_dev_data.lua")
        local unlock = dofile(script_root .. "wt_unlock_data.lua")
        return { mod = mod, unlock = unlock }
    end)
    local mod = built.mod

    local function base_env()
        return {
            unlock_map = built.unlock.weapon_unlock_map,
            loc_raw = mod._wt_loc_raw,
            master_order_by_leaf = mod._wt_master_order_by_leaf,
            master_children = mod._wt_master_children,
            port_status = port_status,
            parse_master_id = Masters.parse_master_id,
            source_order_index = Masters.source_order_index,
            source_char_of = function(child_id)
                return Masters.source_char_of(mod, child_id)
            end,
        }
    end

    local function shallow(source)
        local result = {}
        for key, value in pairs(source) do result[key] = value end
        return result
    end

    local function copy_list(source)
        local result = {}
        for index, value in ipairs(source) do result[index] = value end
        return result
    end

    H.test("WT #183 live Kruber ranged surface satisfies the contract", function()
        local env = base_env()
        for _, career in ipairs({
            "es_mercenary", "es_huntsman", "es_knight", "es_questingknight",
        }) do
            local masters = env.master_order_by_leaf["ranged_" .. career]
            H.truthy(type(masters) == "table" and #masters == 5,
                career .. " should bucket all five source characters")
        end
        H.equal(policy.kruber_ranged_contract(env), nil)
    end)

    local KERI_MASTER = "wtmaster_es_mercenary_ranged_kerillian"

    local function mutated_bucket_env(mutate)
        local env = base_env()
        env.master_children = shallow(env.master_children)
        local bucket = copy_list(env.master_children[KERI_MASTER])
        env.master_children[KERI_MASTER] = bucket
        mutate(env, bucket)
        return env
    end

    H.test("WT #183 audit rejects a missing row", function()
        local env = mutated_bucket_env(function(_, bucket)
            table.remove(bucket)
        end)
        local err = policy.kruber_ranged_contract(env)
        H.truthy(err and err:find("is missing", 1, true), tostring(err))
    end)

    H.test("WT #183 audit rejects a duplicate row", function()
        local env = mutated_bucket_env(function(_, bucket)
            bucket[#bucket + 1] = bucket[1]
        end)
        local err = policy.kruber_ranged_contract(env)
        H.truthy(err and err:find("duplicates", 1, true), tostring(err))
    end)

    H.test("WT #183 audit rejects a non-alphabetical group", function()
        local env = mutated_bucket_env(function(_, bucket)
            bucket[1], bucket[2] = bucket[2], bucket[1]
        end)
        local err = policy.kruber_ranged_contract(env)
        H.truthy(err and err:find("not alphabetical", 1, true), tostring(err))
    end)

    H.test("WT #183 audit rejects an internal-key label", function()
        local env = base_env()
        env.loc_raw = shallow(env.loc_raw)
        env.loc_raw.unlock_es_mercenary_we_longbow = { en = "we_longbow" }
        local err = policy.kruber_ranged_contract(env)
        H.truthy(err and err:find("leaks an internal key", 1, true), tostring(err))
    end)

    H.test("WT #183 audit rejects a retired lifecycle tag", function()
        local env = base_env()
        env.loc_raw = shallow(env.loc_raw)
        env.loc_raw.unlock_es_mercenary_we_longbow =
            { en = "[Untested] Kerillian: Longbow" }
        local err = policy.kruber_ranged_contract(env)
        H.truthy(err and err:find("retired lifecycle tag", 1, true), tostring(err))
    end)

    H.test("WT #183 audit rejects a broken source-group order", function()
        local env = base_env()
        env.master_order_by_leaf = shallow(env.master_order_by_leaf)
        local order = copy_list(env.master_order_by_leaf.ranged_es_mercenary)
        order[1], order[2] = order[2], order[1]
        env.master_order_by_leaf.ranged_es_mercenary = order
        local err = policy.kruber_ranged_contract(env)
        H.truthy(err and err:find("#611 source order", 1, true), tostring(err))
    end)

    H.test("WT #183 audit rejects drifted #108 redirect metadata", function()
        local env = base_env()
        env.port_status = setmetatable({
            model_substitute = function(career, weapon_key)
                if weapon_key == "wh_brace_of_pistols" then return "Crossbow" end
                return port_status.model_substitute(career, weapon_key)
            end,
        }, { __index = port_status })
        local err = policy.kruber_ranged_contract(env)
        H.truthy(err and err:find("wh_brace_of_pistols model_substitute", 1, true),
            tostring(err))
    end)

    H.test("WT #183 audit rejects invented metadata on a native row", function()
        local env = base_env()
        env.port_status = setmetatable({
            redirect_target = function(career, weapon_key)
                if weapon_key == "es_handgun" then return "Repeater Handgun" end
                return port_status.redirect_target(career, weapon_key)
            end,
        }, { __index = port_status })
        local err = policy.kruber_ranged_contract(env)
        H.truthy(err and err:find("invents metadata", 1, true), tostring(err))
    end)
end
