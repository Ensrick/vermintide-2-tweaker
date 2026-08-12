-- Guards the #1159 altar-reuse owner extraction: everything that depends on a
-- Chaos Wastes ALTAR (DeusChestExtension) having been opened before moved
-- VERBATIM out of the ct_dev entry into _ct_altar_reuse_owner.lua.
--
-- The move carried two seam deviations, both OUTSIDE the moved block, and both
-- pinned by an executable fixture below rather than by a textual needle alone:
--   1. the use ledger now lives in the owner, so the entry's run-start
--      `_altar_uses_by_go_id = {}` became `_ct_altar_reuse.reset_uses()`. A
--      rebind is not a table wipe: if reset_uses cleared in place, or if
--      altar_uses handed out the table instead of an accessor, the open_chest
--      write seam in _ct_bot_weapon_chest_owner would keep incrementing LAST
--      RUN's table. `reset_uses rebinds` below fails on exactly that mistake.
--   2. `effective_setting` crosses as a late-binding wrapper closure, because
--      the entry's forward slot is still nil at the install position.
--      `late-binding effective_setting` below binds a wrapper whose target is
--      assigned only AFTER install, so a by-value regression fails it.
return function(H, repo_root)
    local CTSource = dofile(repo_root .. "/qa/lua/ct_source.lua")
    local root = repo_root
        .. "/chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/"
    local module_path = root .. "_ct_altar_reuse_owner.lua"

local function read(name)
        if tostring(name):find("chaos_wastes_tweaker_dev.lua", 1, true) then
            return CTSource.expanded(repo_root)
        end
        local file = assert(io.open(root .. name, "rb"))
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

    local entry = read("chaos_wastes_tweaker_dev.lua")
    local owner = read("_ct_altar_reuse_owner.lua")
    local peer_manifest = read("_ct_peer_manifest_owner.lua")
    -- #1159 wave 14: the setup_run hook that performs the run-start ledger wipe
    -- now lives here, so the wipe assertions below read this file, not the entry.
    local run_creation = read("_ct_run_creation_owner.lua")

    -- ------------------------------------------------------------------
    -- Executable fixture: load the real module and install it against a
    -- recording mod stub. Nothing below reaches the engine - the module only
    -- registers callbacks at load time.
    -- ------------------------------------------------------------------
    local function fixture()
        local hooks, order = {}, {}
        local rpcs = {}
        local mod = {}

        function mod:hook(class_name, method_name, callback)
            local key = class_name .. "." .. method_name
            H.equal(hooks[key], nil, "duplicate hook " .. key)
            hooks[key] = callback
            order[#order + 1] = "hook:" .. key
        end

        function mod:hook_safe(class_name, method_name, callback)
            local key = class_name .. "." .. method_name
            H.equal(hooks[key], nil, "duplicate safe hook " .. key)
            hooks[key] = callback
            order[#order + 1] = "safe:" .. key
        end

        function mod:network_register(event, callback)
            H.equal(rpcs[event], nil, "duplicate rpc " .. event)
            rpcs[event] = callback
            order[#order + 1] = "rpc:" .. event
        end

        function mod:network_send() end

        local function install(overrides)
            overrides = overrides or {}
            local ctx = {
                dbg = function() end,
                dbg_alert = function() end,
                effective_setting = function() return nil end,
                rpc_schema = 1,
            }
            for key, value in pairs(overrides) do
                if value == "\0drop" then ctx[key] = nil else ctx[key] = value end
            end
            local installer = assert(loadfile(module_path))()
            return installer(mod, ctx)
        end

        return mod, hooks, rpcs, order, install
    end

    -- The module writes a handful of globals at load time. Snapshot and restore
    -- them so the suite stays order-independent.
    local function with_clean_globals(body)
        local names = {
            "_ct_altar_probe_watch",
            "_ct_probe_collected_by_peers",
            "CT_RELIQUARY_REROLL_MARKER",
            "CT_RELIQUARY_REROLL_PROMPT",
        }
        local saved = {}
        for _, name in ipairs(names) do saved[name] = rawget(_G, name) end
        local ok, err = pcall(body)
        for _, name in ipairs(names) do _G[name] = saved[name] end
        if not ok then error(err, 0) end
    end

    H.test("altar-reuse owner is a named ctx installer, not an anonymous chunk", function()
        H.truthy(owner:find("local function install(mod, ctx)", 1, true))
        H.truthy(owner:find("\nreturn install\n", 1, true))
        H.equal(count_plain(owner, "return function("), 0)
    end)

    H.test("owner is dofile'd exactly once, at the original block position", function()
        H.equal(count_plain(entry,
            "scripts/mods/chaos_wastes_tweaker_dev/_ct_altar_reuse_owner"), 1)
        -- Position invariant: the installer sits between the bot-economy coin
        -- hook that used to precede the block and the multiplayer settings-sync
        -- block that used to follow it. Load order decides hook-registration
        -- order, so this is the property that keeps the move behaviour-neutral.
        local coin_hook = assert(entry:find(
            'mod:hook("DeusRunController", "on_soft_currency_picked_up"', 1, true))
        local install_at = assert(entry:find(
            "scripts/mods/chaos_wastes_tweaker_dev/_ct_altar_reuse_owner", 1, true))
        local sync_block = assert(entry:find(
            "local PER_PEER_SETTING_NAMES = {", 1, true))
        H.truthy(coin_hook < install_at,
            "owner must install after the bot-economy coin hook, as the block did")
        H.truthy(install_at < sync_block,
            "owner must install before the multiplayer settings-sync block")
    end)

    H.test("all eight altar hooks and the uncollect RPC live in the owner", function()
        -- Needles are newline-anchored on purpose: this file's own comments quote
        -- several of these pairs verbatim (the "DO NOT add a second open_chest
        -- hook" warning is the whole reason the consolidation exists), and a bare
        -- substring would count prose as a registration.
        local moved = {
            '\nmod:hook("DeusChestExtension", "update"',
            '\nmod:hook("DeusChestExtension", "get_purchase_cost"',
            '\nmod:hook("DeusChestExtension", "_generate_stored_power_up"',
            '\nmod:hook("DeusChestExtension", "_generate_stored_weapon"',
            '\nmod:hook("DeusChestExtension", "_generate_upgraded_weapon"',
            '\nmod:hook("DeusChestExtension", "update_upgrade_chest_color"',
            '\nmod:hook("DeusChestExtension", "can_be_unlocked"',
            '\nmod:hook_safe("DeusUpgradeWeaponInteractionUI", "_populate_widget"',
            '\nmod:network_register("ct_altar_uncollect"',
        }
        for _, needle in ipairs(moved) do
            H.equal(count_plain(owner, needle), 1, needle .. " owned exactly once")
            H.equal(count_plain(entry, needle), 0, needle .. " must not remain in the entry")
        end
        -- VMF silently drops a second registration on the same (Class, method)
        -- pair - that is how the v0.7.129/.130 altar-reuse "fix" shipped dead for
        -- two releases. Assert no sibling owner re-registers any of them.
        for _, sibling in ipairs({
            "_ct_bot_weapon_chest_owner.lua",
            "_ct_campaign_graph_owner.lua",
            "_ct_pickup_spawn_owner.lua",
            "_ct_spawn_eligibility_owner.lua",
            "_ct_tab_panel_owner.lua",
            "_ct_boon_grant_owner.lua",
            "_ct_curse_lighting_owner.lua",
            "_ct_combat_hooks.lua",
            "_ct_command_owner.lua",
            "_ct_journey_difficulty_guard.lua",
            "_ct_run_creation_owner.lua",
            "_ct_weapon_trait_generation.lua",
            "_ct_boss_grudge_marks.lua",
            "_ct_boon_registry.lua",
            "_ct_boon_preview_helpers.lua",
            "_ct_regression.lua",
        }) do
            local text = read(sibling)
            for _, needle in ipairs(moved) do
                H.equal(count_plain(text, needle), 0,
                    sibling .. " must not re-register " .. needle)
            end
        end
    end)

    H.test("the open_chest WRITE seam stays with _ct_bot_weapon_chest_owner", function()
        -- The split is exactly write-site vs read-sites. The one consolidated
        -- open_chest hook increments the ledger and performs the re-arm; every
        -- reader of that count moved here. A copy of the write seam in this file
        -- would be silently dropped by VMF and the ledger would stop advancing.
        local bot_chest = read("_ct_bot_weapon_chest_owner.lua")
        H.equal(count_plain(bot_chest, '\nmod:hook("DeusChestExtension", "open_chest"'), 1)
        H.equal(count_plain(owner, '\nmod:hook("DeusChestExtension", "open_chest"'), 0)
        H.equal(count_plain(entry, '\nmod:hook("DeusChestExtension", "open_chest"'), 0)
        -- That owner reaches the ledger through the accessor and mod._ct_altar_uncollect
        -- through the mod namespace, so neither needs a second definition here.
        H.truthy(bot_chest:find("state.altar_uses()", 1, true))
        H.truthy(bot_chest:find("mod._ct_altar_uncollect(self)", 1, true))
        H.equal(count_plain(owner, "mod._ct_altar_uncollect = function(ext)"), 1)
    end)

    H.test("the ledger is a single owner file-local reached only by accessor", function()
        H.equal(count_plain(owner, "local _altar_uses_by_go_id = {}"), 1)
        H.equal(count_plain(entry, "_altar_uses_by_go_id"), 0)
        -- The run-start wipe is the exported rebind, called exactly once. #1159
        -- wave 14 moved the setup_run hook that holds it into
        -- _ct_run_creation_owner, so the needles are byte-identical and only the
        -- file moved; the entry-side absence below is what makes a stray second
        -- wipe (which would clear a table nothing else reads) fail.
        H.equal(count_plain(run_creation, "_ct_altar_reuse.reset_uses()"), 1)
        H.equal(count_plain(entry, "_ct_altar_reuse.reset_uses()"), 0)
        local setup_run = assert(run_creation:find(
            'mod:hook("DeusRunController", "setup_run"', 1, true))
        local reset_at = assert(run_creation:find("_ct_altar_reuse.reset_uses()", 1, true))
        H.truthy(reset_at > setup_run,
            "the ledger wipe must still sit inside the setup_run hook body")
        -- The owner reaches the ledger only through the injected accessor, so a
        -- by-value capture regression that froze a nil would fail load-time.
        H.truthy(run_creation:find("local _ct_altar_reuse = ctx.altar_reuse", 1, true))
        H.truthy(entry:find("altar_reuse = _ct_altar_reuse,", 1, true))
    end)

    H.test("network transports stay outside the altar owner", function()
        -- The manifest transport now has its own owner; settings and graph sync
        -- remain entry-owned. None may leak into this altar-only owner.
        for _, needle in ipairs({
            "_ct_host_settings",
            "_ct_host_graph_snapshot",
            "_ct_peer_manifests",
            "ct_sync_host_settings_chunk",
            "ct_graph_snapshot_chunk",
            "ct_peer_manifest_chunk",
        }) do
            H.equal(count_plain(owner, needle), 0,
                needle .. " must not appear in the altar-reuse owner")
        end
        for _, needle in ipairs({
            'mod:network_register("ct_sync_host_settings_chunk"',
            'mod:network_register("ct_graph_snapshot_chunk"',
        }) do
            H.equal(count_plain(entry, needle), 1, needle .. " stays in the entry")
        end
        H.equal(count_plain(peer_manifest,
            'mod:network_register("ct_peer_manifest_chunk"'), 1,
            "peer-manifest RPC stays in its dedicated owner")
    end)

    H.test("owner registers no command and no regression check", function()
        H.equal(count_plain(owner, "mod:command"), 0)
        H.equal(count_plain(owner, "_rt_register("), 0)
        H.equal(count_plain(owner, "local _RT_CHECKS"), 0)
    end)

    H.test("#252 reroll prompt and its marker are defined once, here", function()
        H.equal(count_plain(owner,
            'CT_RELIQUARY_REROLL_PROMPT = "Reroll this weapon?"'), 1)
        H.equal(count_plain(owner, "CT_RELIQUARY_REROLL_MARKER ="), 1)
        H.equal(count_plain(entry, "CT_RELIQUARY_REROLL_PROMPT"), 0)
        H.equal(count_plain(entry, "CT_RELIQUARY_REROLL_MARKER"), 0)
        -- The #102 decouple marker did NOT move: it is declared above the moved
        -- region, so it must still be the entry's, exactly once.
        H.equal(count_plain(entry, "CT_UPGRADE_ALTAR_RARITY_DECOUPLE_MARKER ="), 1)
        H.equal(count_plain(owner, "CT_UPGRADE_ALTAR_RARITY_DECOUPLE_MARKER"), 0)
    end)

    H.test("every ctx key the owner binds is supplied by the entry installer", function()
        local keys = {
            dbg               = "ctx.dbg",
            dbg_alert         = "ctx.dbg_alert",
            effective_setting = "ctx.effective_setting",
            rpc_schema        = "ctx.rpc_schema",
        }
        local install_at = assert(entry:find(
            "scripts/mods/chaos_wastes_tweaker_dev/_ct_altar_reuse_owner", 1, true))
        local call_site = entry:sub(install_at, install_at + 400)
        for key, ref in pairs(keys) do
            H.truthy(owner:find(ref, 1, true), "owner must bind " .. ref)
            H.truthy(owner:find("requires " .. ref, 1, true),
                ref .. " must be assert-guarded so a dropped key fails at load")
            H.truthy(call_site:find(key .. " =", 1, true),
                "entry installer must supply " .. key)
        end
    end)

    H.test("dropping any ctx key fails at LOAD, not at the first altar", function()
        with_clean_globals(function()
            for _, key in ipairs({ "dbg", "dbg_alert", "effective_setting", "rpc_schema" }) do
                local _, _, _, _, install = fixture()
                local ok = pcall(install, { [key] = "\0drop" })
                H.equal(ok, false, "missing ctx." .. key .. " must abort the install")
            end
            -- A non-table ctx is caught too.
            local installer = assert(loadfile(module_path))()
            H.equal(pcall(installer, {}, nil), false)
        end)
    end)

    H.test("installing registers exactly 7 hooks, 1 safe hook and 1 RPC", function()
        with_clean_globals(function()
            local _, hooks, rpcs, order, install = fixture()
            install()
            local hook_count, safe_count, rpc_count = 0, 0, 0
            for _, entry_name in ipairs(order) do
                if entry_name:sub(1, 5) == "hook:" then hook_count = hook_count + 1
                elseif entry_name:sub(1, 5) == "safe:" then safe_count = safe_count + 1
                else rpc_count = rpc_count + 1 end
            end
            H.equal(hook_count, 7)
            H.equal(safe_count, 1)
            H.equal(rpc_count, 1)
            H.truthy(hooks["DeusChestExtension.get_purchase_cost"])
            H.truthy(hooks["DeusUpgradeWeaponInteractionUI._populate_widget"])
            H.truthy(rpcs["ct_altar_uncollect"])
        end)
    end)

    H.test("install defines the probe globals and the mod._ct_* altar helpers", function()
        with_clean_globals(function()
            _G._ct_altar_probe_watch = nil
            _G._ct_probe_collected_by_peers = nil
            _G.CT_RELIQUARY_REROLL_PROMPT = nil
            local mod, _, _, _, install = fixture()
            install()
            -- Consumed by _ct_bot_weapon_chest_owner through the entry's ctx table,
            -- and by _ct_regression.lua at check time.
            H.equal(type(rawget(_G, "_ct_altar_probe_watch")), "table")
            H.equal(type(rawget(_G, "_ct_probe_collected_by_peers")), "function")
            H.equal(rawget(_G, "CT_RELIQUARY_REROLL_PROMPT"), "Reroll this weapon?")
            H.equal(type(mod._ct_altar_uncollect), "function")
            H.equal(type(mod._ct_remove_peer_from_collected), "function")
            H.equal(type(mod._ct_altar_next_rarity_above), "function")
            H.equal(type(mod._ct_rarity_by_order), "table")
            -- The boon-altar no-repeat ledger is initialised at load, which is
            -- what the entry's `boon_altar_no_repeat` regression check asserts.
            H.equal(type(mod._ct_boon_altar_taken_boons), "table")
        end)
    end)

    H.test("reset_uses REBINDS the ledger and altar_uses tracks the new table", function()
        with_clean_globals(function()
            local _, _, _, _, install = fixture()
            local exports = install()
            local before = exports.altar_uses()
            H.equal(type(before), "table")
            before[1234] = 3
            exports.reset_uses()
            local after = exports.altar_uses()
            -- A rebind, not an in-place clear: a NEW table, and the accessor
            -- follows it. Clearing in place would return the same table here, and
            -- the open_chest write seam (which caches nothing but calls the
            -- accessor each time) would be fine either way - but a consumer that
            -- captured the TABLE would silently keep the old one, which is the
            -- exact reason altar_uses is an accessor.
            H.truthy(after ~= before, "reset_uses must rebind, not clear in place")
            H.equal(after[1234], nil)
            H.equal(before[1234], 3, "the pre-reset table must be left untouched")
            -- Second reset from a fresh state still yields a distinct table.
            local third = (function() exports.reset_uses(); return exports.altar_uses() end)()
            H.truthy(third ~= after)
        end)
    end)

    H.test("late-binding effective_setting: a wrapper assigned AFTER install still resolves", function()
        with_clean_globals(function()
            -- This mirrors the entry exactly: the forward slot is nil when the
            -- installer runs and is only assigned later. Binding ctx.effective_setting
            -- BY VALUE at the install site would freeze nil here and every
            -- altar-reuse setting would read as nil in game.
            local forward_slot
            local wrapper = function(name) return forward_slot(name) end
            local mod, _, _, _, install = fixture()
            local exports = install({ effective_setting = wrapper })
            H.equal(forward_slot, nil, "the slot must still be unassigned at install time")

            local asked = {}
            forward_slot = function(name)
                asked[#asked + 1] = name
                if name == "enable_altar_reuse" then return true end
                if name == "altar_reuse_count_upgrade" then return 3 end
                return nil
            end
            mod._ct_umbrella_policy = {
                value = function(master, configured, vanilla)
                    if master == false then return vanilla end
                    return configured
                end,
            }
            H.equal(exports.altar_max_uses("upgrade"), 3)
            H.equal(asked[1], "enable_altar_reuse")
            H.equal(asked[2], "altar_reuse_count_upgrade")
            -- Unknown chest type short-circuits before any settings read.
            H.equal(exports.altar_max_uses("not_an_altar"), 1)
            -- Master toggle off falls back to the vanilla single use.
            forward_slot = function(name)
                if name == "enable_altar_reuse" then return false end
                return 5
            end
            H.equal(exports.altar_max_uses("power_up"), 1)
        end)
    end)

    H.test("exports are exactly the three the entry forwards", function()
        with_clean_globals(function()
            local _, _, _, _, install = fixture()
            local exports = install()
            local names = {}
            for key in pairs(exports) do names[#names + 1] = key end
            table.sort(names)
            H.deep_equal(names, { "altar_max_uses", "altar_uses", "reset_uses" })
            -- The entry forwards two of them verbatim into the write-seam owner.
            H.truthy(entry:find("altar_uses = _ct_altar_reuse.altar_uses", 1, true))
            H.truthy(entry:find("altar_max_uses = _ct_altar_reuse.altar_max_uses", 1, true))
        end)
    end)
end
