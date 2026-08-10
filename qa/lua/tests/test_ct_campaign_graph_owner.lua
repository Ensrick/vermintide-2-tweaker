-- Guards the #1159 campaign-graph owner extraction: the deus_populate_graph
-- generator seam and the #145/#146 Citadel god rewrite moved VERBATIM out of the
-- ct_dev entry into _ct_campaign_graph_owner.lua. Every assertion below is a
-- property the move must not have changed.
return function(H, repo_root)
    local root = repo_root
        .. "/chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/"

    local function read(name)
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
    local owner = read("_ct_campaign_graph_owner.lua")

    H.test("campaign-graph owner is a named ctx installer, not an anonymous chunk", function()
        H.truthy(owner:find("local function install(mod, ctx)", 1, true))
        H.truthy(owner:find("\nreturn install\n", 1, true))
        H.equal(count_plain(owner, "return function("), 0)
    end)

    H.test("owner is dofile'd exactly once, at the original block position", function()
        H.equal(count_plain(entry,
            "scripts/mods/chaos_wastes_tweaker_dev/_ct_campaign_graph_owner"), 1)
        -- Position invariant: the installer sits between the map-scene hook that
        -- used to precede the block and the ghost-scythe recovery that used to
        -- follow it. Load order decides hook-registration order, so this is the
        -- property that keeps the move behaviour-neutral.
        local map_scene = assert(entry:find(
            'mod:hook("DeusMapScene", "on_enter"', 1, true))
        local install_at = assert(entry:find(
            "scripts/mods/chaos_wastes_tweaker_dev/_ct_campaign_graph_owner", 1, true))
        local gear_utils = assert(entry:find(
            'mod:hook("GearUtils", "create_equipment"', 1, true))
        H.truthy(map_scene < install_at,
            "owner must install after the DeusMapScene.on_enter hook, as the block did")
        H.truthy(install_at < gear_utils,
            "owner must install before the per-career weapon override recovery")
    end)

    H.test("the CW graph generator is hooked exactly once, in the owner", function()
        H.equal(count_plain(owner, 'mod:hook(_G, "deus_populate_graph"'), 1)
        H.equal(count_plain(entry, 'mod:hook(_G, "deus_populate_graph"'), 0)
        -- VMF silently drops a second registration on the same pair, so a stray
        -- copy anywhere would be a silent no-op rather than a visible error.
        for _, sibling in ipairs({
            "_ct_pickup_spawn_owner.lua",
            "_ct_spawn_eligibility_owner.lua",
            "_ct_tab_panel_owner.lua",
            "_ct_boon_grant_owner.lua",
            "_ct_curse_lighting_owner.lua",
            "_ct_combat_hooks.lua",
            "_ct_bot_weapon_chest_owner.lua",
            "_ct_command_owner.lua",
            "_ct_journey_difficulty_guard.lua",
            "_ct_weapon_trait_generation.lua",
            "_ct_boss_grudge_marks.lua",
            "_ct_boon_registry.lua",
            "_ct_boon_preview_helpers.lua",
            "_ct_regression.lua",
        }) do
            H.equal(count_plain(read(sibling), 'mod:hook(_G, "deus_populate_graph"'), 0,
                sibling .. " must not hook the graph generator")
        end
    end)

    H.test("#145/#146 Citadel rewrite stays wired at BOTH generator branches", function()
        H.equal(count_plain(owner, "mod._ct_force_finale_god(result[1], config)"), 2)
        H.equal(count_plain(entry, "mod._ct_force_finale_god(result[1], config)"), 0)
        H.truthy(owner:find(
            'CT_CITADEL145_FIX_MARKER = "citadel145:force_finale_god_fix_v0.7.219"', 1, true))
        H.truthy(owner:find(
            'CT_CITADEL145_MARKER = "citadel145:resolved_god_census_v0.7.212"', 1, true))
        -- The two markers must NOT also remain in the entry: two assignments to the
        -- same global would make the regression check pass off whichever ran last.
        H.equal(count_plain(entry, "CT_CITADEL145_FIX_MARKER ="), 0)
        H.equal(count_plain(entry, "CT_CITADEL145_MARKER ="), 0)
    end)

    H.test("the three read-only graph probes moved with the seams that call them", function()
        for _, export in ipairs({
            "mod._ct_citadel145_dump = function",
            "mod._ct_curse56_dump = function",
            "mod._ct_mission136_dump = function",
            "mod._ct_force_finale_god = function",
        }) do
            H.equal(count_plain(owner, export), 1, export .. " defined once in the owner")
            H.equal(count_plain(entry, export), 0, export .. " must not remain in the entry")
        end
        -- _ct_regression.lua reaches all four through the mod namespace at CALL
        -- time, so its presence checks survive the chunk split unchanged.
        local regression = read("_ct_regression.lua")
        H.truthy(regression:find("mod._ct_force_finale_god", 1, true))
        H.truthy(regression:find("mod._ct_citadel145_dump", 1, true))
        H.truthy(regression:find("mod._ct_mission136_dump", 1, true))
    end)

    H.test("the graph-snapshot RPC transport stays in the entry", function()
        -- The owner CALLS the broadcast and the apply; it must never own the
        -- receiver, the chunk buffers, or the mutable snapshot state. Reading
        -- _ct_host_graph_snapshot from another chunk would capture a stale nil.
        H.equal(count_plain(owner, "mod:network_register("), 0)
        H.equal(count_plain(owner, "_ct_host_graph_snapshot"), 0)
        H.equal(count_plain(owner, "apply_host_graph_snapshot_to_live_run"), 0)
        H.truthy(entry:find('mod:network_register("ct_graph_snapshot_chunk"', 1, true))
        H.truthy(entry:find("local function apply_graph_snapshot(graph_data)", 1, true))
        H.truthy(entry:find("local function broadcast_graph_snapshot(graph_data)", 1, true))
        -- Both are still called from the owner, one per generator branch pair.
        H.equal(count_plain(owner, "broadcast_graph_snapshot(result[1])"), 2)
        H.equal(count_plain(owner, "apply_graph_snapshot(result[1])"), 2)
    end)

    H.test("every ctx key the owner binds is supplied by the entry installer", function()
        local keys = {
            dbg                      = "ctx.dbg",
            effective_setting        = "ctx.effective_setting",
            is_curse_disabled        = "ctx.is_curse_disabled",
            finale_gods              = "ctx.finale_gods",
            apply_graph_snapshot     = "ctx.apply_graph_snapshot",
            broadcast_graph_snapshot = "ctx.broadcast_graph_snapshot",
        }
        local install_at = assert(entry:find(
            "scripts/mods/chaos_wastes_tweaker_dev/_ct_campaign_graph_owner", 1, true))
        local call_site = entry:sub(install_at, install_at + 600)
        for key, ref in pairs(keys) do
            H.truthy(owner:find(ref, 1, true), "owner must bind " .. ref)
            H.truthy(owner:find('requires ' .. ref, 1, true),
                ref .. " must be assert-guarded so a dropped key fails at load")
            H.truthy(call_site:find(key .. " ", 1, true),
                "entry installer must supply " .. key)
        end
    end)

    H.test("every ctx source is assigned once and above the installer", function()
        -- The whole extraction rests on this: each name below is bound BY VALUE in
        -- the owner, which is only safe because the entry assigns it exactly once
        -- and strictly before the dofile. A second assignment anywhere would make
        -- the owner hold a stale object and would need a late-binding accessor
        -- instead (the _cim_weave_loadout_owner _bubble_cap pattern).
        local install_at = assert(entry:find(
            "scripts/mods/chaos_wastes_tweaker_dev/_ct_campaign_graph_owner", 1, true))
        local single_assignment = {
            ["local function _dbg(fmt, ...)"]                    = true,
            ["effective_setting = function(name)"]               = true,
            ["is_curse_disabled = function(curse_name)"]          = true,
            ['local FINALE_GODS = { "nurgle", "tzeentch", "khorne", "slaanesh" }'] = true,
            ["local function apply_graph_snapshot(graph_data)"]   = true,
            ["local function broadcast_graph_snapshot(graph_data)"] = true,
        }
        for needle in pairs(single_assignment) do
            H.equal(count_plain(entry, needle), 1,
                needle .. " must be assigned exactly once in the entry")
            local at = assert(entry:find(needle, 1, true))
            H.truthy(at < install_at, needle .. " must be assigned above the installer")
        end
        -- FINALE_GODS is a shared table, not a copy: the owner must not redeclare it.
        H.equal(count_plain(owner, 'local FINALE_GODS = {'), 0)
    end)

    H.test("the runtime curse-disable hooks live in the node-entry owner, unsplit", function()
        -- Generation-time filtering (this owner) and runtime nulling are the two
        -- halves of the same curse policy. They share only the is_curse_disabled
        -- predicate, which the entry still owns and passes to BOTH. The runtime
        -- half became its own slice in 0.7.334-dev (_ct_node_entry_owner); what
        -- this test pins now is that the five hooks stayed together when they
        -- moved, and that not one of them leaked into the generation owner.
        local node_entry = read("_ct_node_entry_owner.lua")
        for _, needle in ipairs({
            'mod:hook("MutatorHandler", "_activate_mutator"',
            'mod:hook("DeusMechanism", "get_current_node_curse"',
            'mod:hook("DeusMechanism", "_transition_next_node"',
            'mod:hook("DeusMechanism", "start_next_round"',
            'mod:hook("DeusMapDecisionView", "_enable_hover"',
        }) do
            H.equal(count_plain(node_entry, needle), 1,
                needle .. " stays in the node-entry owner")
            H.equal(count_plain(entry, needle), 0, needle .. " left the entry")
            H.equal(count_plain(owner, needle), 0, needle .. " must not move to the owner")
        end
        -- The shared predicate is still ONE entry-owned function handed to both.
        H.equal(count_plain(entry, "is_curse_disabled = function(curse_name)"), 1)
        H.equal(count_plain(owner, "is_curse_disabled = function(curse_name)"), 0)
        H.equal(count_plain(node_entry, "is_curse_disabled = function(curse_name)"), 0)
        -- The generation-time filter and its restore moved as a pair.
        H.equal(count_plain(owner, "local function filter_available_curses(config)"), 1)
        H.equal(count_plain(owner, "local function restore_available_curses(saved)"), 1)
        H.equal(count_plain(entry, "filter_available_curses"), 0)
        H.equal(count_plain(entry, "restore_available_curses"), 0)
    end)

    H.test("owner registers no command, no RPC and no regression check", function()
        H.equal(count_plain(owner, "mod:command"), 0)
        H.equal(count_plain(owner, "mod:network_send"), 0)
        H.equal(count_plain(owner, "_rt_register("), 0)
        H.equal(count_plain(owner, "local _RT_CHECKS"), 0)
    end)
end
