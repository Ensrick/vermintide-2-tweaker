-- Issue #664: the Executioner light-headshot toggle read parity=false in every
-- one of 54 sessions (899 identical `[wt:664] ... enabled=false parity=false`
-- lines), solo included. Root cause: weapon_tweaker_backend.lua's M.install
-- (run at the BOTTOM of weapon_tweaker.lua) assigned mod.update with a naked
-- overwrite AFTER _wt431_damage_profile_parity.lua had wrapped mod.update with
-- the peer-parity beacon tick, so the tick never ran and applied_state() froze
-- at the fail-safe "disabled". This suite pins:
--   1. behaviorally, on the SHIPPED wt copy of _lib_peer_parity: a naked
--      post-install mod.update overwrite reproduces the frozen-disabled bug,
--      and the prev_update-preserving assignment (the fix) lets a solo session
--      settle to "enabled" and fire the gated feature's on_enable;
--   2. the fix pattern is present in weapon_tweaker_backend.lua (both wiring
--      halves: the prev_update capture and the pcall chain);
--   3. the beacon module is still dofile'd BEFORE weapon_backend.install in
--      weapon_tweaker.lua (the ordering the fix documents);
--   4. the #664 setting-id chain: the widget id in weapon_tweaker_data.lua ==
--      the policy constant == the on_setting_changed dispatch arm, so the
--      enabled= side of the log line follows the checkbox.
local function register(Harness, repo_root)
    local wt_dir = repo_root .. "/weapon_tweaker/scripts/mods/weapon_tweaker"

    local function read(path)
        local file = assert(io.open(path, "rb"))
        local source = file:read("*a")
        file:close()
        return source
    end

    local function load_wt_lib_factory()
        local chunk, err = loadfile(wt_dir .. "/_lib_peer_parity.lua")
        if not chunk then error(err) end
        return chunk()
    end

    -- Minimal solo runtime: roster has only the local player, so the beacon's
    -- _other_human_peers() set is empty and solo settles with settle window 0.
    local function with_solo_runtime(body)
        local previous_managers, previous_network = Managers, Network
        Managers = {
            player = {
                human_players = function()
                    return { { peer_id = "host", name = function() return "Host" end } }
                end,
            },
        }
        Network = { peer_id = function() return "host" end }
        local ok, err = xpcall(body, debug.traceback)
        Managers, Network = previous_managers, previous_network
        if not ok then error(err, 0) end
    end

    local function fake_mod()
        return {
            network_register = function() end,
            network_send = function() end,
            debug = function() end,
            echo = function() end,
        }
    end

    Harness.test("WT #664 naked mod.update overwrite after install freezes solo parity at disabled", function()
        with_solo_runtime(function()
            local factory = load_wt_lib_factory()
            local mod = fake_mod()
            local inst = factory(mod, { poll_interval = 0, settle_enable = 0 })
            local enabled_calls = 0
            inst:register_gated_feature("wt_custom_damage_profiles", {
                on_enable = function() enabled_calls = enabled_calls + 1 end,
            })
            inst:install()
            Harness.truthy(type(mod.update) == "function", "install must wrap mod.update")

            -- The pre-fix backend behavior: M.install stomps the wrapper.
            mod.update = function() end

            for _ = 1, 5 do
                mod.update(0.6)
            end
            Harness.equal("disabled", inst:applied_state(),
                "stomped beacon tick must reproduce the frozen parity=false state")
            Harness.equal(0, enabled_calls, "on_enable must never fire once the tick is dead")
        end)
    end)

    Harness.test("WT #664 prev_update-preserving assignment lets solo settle to enabled", function()
        with_solo_runtime(function()
            local factory = load_wt_lib_factory()
            local mod = fake_mod()
            local inst = factory(mod, { poll_interval = 0, settle_enable = 0 })
            local enabled_calls = 0
            local state_inside_callback
            inst:register_gated_feature("wt_custom_damage_profiles", {
                on_enable = function()
                    enabled_calls = enabled_calls + 1
                    state_inside_callback = inst:applied_state()
                end,
            })
            inst:install()

            -- The FIXED backend behavior: preserve whatever per-frame driver
            -- was installed first (weapon_tweaker_backend.lua M.install).
            local backend_ran = 0
            local prev_update = mod.update
            mod.update = function(dt)
                if prev_update then pcall(prev_update, dt) end
                backend_ran = backend_ran + 1
            end

            mod.update(0.6)
            mod.update(0.6)
            Harness.truthy(backend_ran >= 2, "backend body must keep running")
            Harness.equal("enabled", inst:applied_state(),
                "solo roster must settle the beacon to enabled once the tick survives")
            Harness.equal(1, enabled_calls, "gated feature's on_enable must fire exactly once")
            Harness.equal("enabled", state_inside_callback,
                "applied state must already read enabled inside on_enable (issue 506 contract)")
        end)
    end)

    Harness.test("WT #664 backend M.install preserves the previously-installed mod.update", function()
        local backend = read(wt_dir .. "/weapon_tweaker_backend.lua")
        local capture_at = backend:find("local prev_update = mod.update", 1, true)
        Harness.truthy(capture_at, "backend must capture the earlier update before assigning its own")
        -- Search from the capture offset: an older doc comment above also
        -- contains the literal `mod.update = function(dt)` text.
        local assign_at = backend:find("mod.update = function(dt)", capture_at, true)
        Harness.truthy(assign_at, "the real assignment must follow the prev_update capture")
        local chain_at = backend:find("if prev_update then pcall(prev_update, dt) end", assign_at, true)
        Harness.truthy(chain_at,
            "backend update must chain the preserved driver (the beacon tick) inside its body")
    end)

    Harness.test("WT #664 beacon still installs before weapon_backend.install stomps could occur", function()
        local source = read(wt_dir .. "/weapon_tweaker.lua")
        local beacon_at = source:find('mod:dofile("scripts/mods/weapon_tweaker/_wt431_damage_profile_parity")', 1, true)
        local backend_install_at = source:find("weapon_backend.install(mod", 1, true)
        Harness.truthy(beacon_at, "beacon dofile missing")
        Harness.truthy(backend_install_at, "backend install call missing")
        Harness.truthy(beacon_at < backend_install_at,
            "beacon must wrap mod.update before backend M.install runs")
    end)

    Harness.test("WT #664 setting-id chain widget == policy constant == dispatch arm", function()
        local policy = dofile(wt_dir .. "/_wt_axe_balance.lua")
        Harness.equal("wt_executioner_light_headshot_bonus", policy.EXECUTIONER_LIGHT_HEADSHOT_SETTING)
        local data = read(wt_dir .. "/weapon_tweaker_data.lua")
        Harness.truthy(data:find('setting_id = "' .. policy.EXECUTIONER_LIGHT_HEADSHOT_SETTING .. '"', 1, true),
            "widget for the executioner toggle must exist under the policy's id")
        local source = read(wt_dir .. "/weapon_tweaker.lua")
        Harness.truthy(source:find("_wt_axe_balance_policy.EXECUTIONER_LIGHT_HEADSHOT_SETTING then", 1, true),
            "on_setting_changed must dispatch the executioner setting to the balance apply")
        Harness.truthy(source:find("[wt:664] applied:", 1, true),
            "the #664 evidence printf must remain (proves enabled=/parity= at each apply)")
    end)
end

return register
