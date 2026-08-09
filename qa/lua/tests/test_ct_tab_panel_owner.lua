-- Boundary test for the #1159 ct_dev tab-panel owner extraction.
-- Engine-free: asserts the structural contract of the split (hook ownership and
-- cardinality on IngamePlayerListUI, wiring position between the starting-boon
-- grant hook and the #458 start-shrine dofiles, the side-module load order the
-- panel depends on, the moved regression checks, and non-overlap with the two
-- spawn owners).
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
    local owner = read("_ct_tab_panel_owner.lua")
    local pickup = read("_ct_pickup_spawn_owner.lua")
    local eligibility = read("_ct_spawn_eligibility_owner.lua")
    local diag = read("_ct_diag_tab_native533.lua")
    local layout = read("_ct_tab_collectibles_layout.lua")

    -- The three IngamePlayerListUI seams ct adds to the hold-Tab panel. VMF
    -- silently drops a second hook on the same Class/method pair, so a duplicate
    -- would shadow the owner with no error at all.
    local HOOKS = {
        'mod:hook_safe("IngamePlayerListUI", "_setup_deed_reward_data"',
        'mod:hook_safe("IngamePlayerListUI", "_draw"',
        'mod:hook("IngamePlayerListUI", "_setup_mission_data"',
    }

    H.test("tab-panel owner is dofile'd exactly once by the entry", function()
        H.equal(count_plain(entry,
            'mod:dofile("scripts/mods/chaos_wastes_tweaker_dev/_ct_tab_panel_owner")'), 1)
        -- Bare dofile, not an installer call: the module body runs at file scope
        -- exactly where the block used to execute, which is what preserves hook
        -- registration order, side-module load order, and _rt_register append
        -- order.
        H.equal(count_plain(owner, "function M.install"), 0)
        H.equal(count_plain(owner, "return function"), 0)
        H.equal(count_plain(owner, 'local mod = get_mod("ct_dev")'), 1)
    end)

    H.test("every moved hook lives only in the owner, exactly once", function()
        for _, head in ipairs(HOOKS) do
            H.equal(count_plain(owner, head), 1, head .. " must be owned once")
            H.equal(count_plain(entry, head), 0, head .. " must not remain in the entry")
        end
    end)

    H.test("no second ct hook on any owned IngamePlayerListUI method", function()
        -- Whole-mod cardinality: the panel class is touched by exactly two files,
        -- and they share no method. The diagnostics module owns _set_active only.
        for _, method in ipairs({
            '"_setup_deed_reward_data"',
            '"_draw"',
            '"_setup_mission_data"',
        }) do
            H.equal(count_plain(diag, 'IngamePlayerListUI", ' .. method), 0,
                method .. " belongs to the tab-panel owner, not the diagnostics module")
            H.equal(count_plain(layout, 'IngamePlayerListUI", ' .. method), 0,
                method .. " belongs to the tab-panel owner, not the layout module")
        end
        H.equal(count_plain(diag, 'mod:hook_safe("IngamePlayerListUI", "_set_active"'), 1)
        H.equal(count_plain(owner, '"IngamePlayerListUI", "_set_active"'), 0)
        -- The layout helper is pure geometry: it hooks nothing at all.
        H.equal(count_plain(layout, "mod:hook"), 0)
    end)

    H.test("the shared _draw pass stays a single hook serving both overlays", function()
        -- #461 and #533 are one owner precisely because they cannot each own a
        -- _draw hook. Both concerns must be visible in that one body.
        H.equal(count_plain(owner, 'mod:hook_safe("IngamePlayerListUI", "_draw"'), 1)
        local draw_at = assert(owner:find(
            'mod:hook_safe("IngamePlayerListUI", "_draw"', 1, true))
        local tail = owner:sub(draw_at)
        H.truthy(tail:find("self._ct_boon_preview_widgets", 1, true),
            "#461 preview must draw from the shared pass")
        H.truthy(tail:find("mod._ct_refresh_deus_collectibles", 1, true),
            "#533 counters must draw from the same shared pass")
    end)

    H.test("owner is wired at its original slot in the entry", function()
        -- Between the DeusRunController starting-boon grant hook above and the
        -- #458 start-shrine dofiles below. Any other position would reorder hook
        -- registration or the _RT_CHECKS list.
        local grant_at = assert(entry:find(
            'mod:hook_safe("DeusRunController", "_add_initial_power_ups"', 1, true))
        local owner_at = assert(entry:find(
            'mod:dofile("scripts/mods/chaos_wastes_tweaker_dev/_ct_tab_panel_owner")', 1, true))
        local shrine_at = assert(entry:find(
            "mods/chaos_wastes_tweaker_dev/_ct_start_shrine_policy", 1, true))
        H.truthy(grant_at < owner_at, "owner must load after the starting-boon grant hook")
        H.truthy(owner_at < shrine_at, "owner must load before the #458 start-shrine modules")
    end)

    H.test("the five panel side modules are dofile'd only by the owner", function()
        for _, module in ipairs({
            "_ct_boon_preview_tooltip",
            "_ct_boon_preview_runtime",
            "_ct_boon_preview_helpers",
            "_ct_diag_tab_native533",
            "_ct_tab_collectibles_layout",
        }) do
            local path = "scripts/mods/chaos_wastes_tweaker_dev/" .. module
            H.equal(count_plain(owner, path), 1, module .. " must be loaded once by the owner")
            H.equal(count_plain(entry, path), 0, module .. " must no longer load from the entry")
        end
    end)

    H.test("layout module still loads after the draw hook that calls it", function()
        -- Pre-extraction the #571 layout dofile sat BELOW the _draw registration,
        -- and both mod._ct_*_deus_collectibles seams were resolved at call time
        -- (first draw). Preserve that ordering rather than "fixing" it, so the
        -- module's own load-time work keeps its original timing.
        local draw_at = assert(owner:find(
            'mod:hook_safe("IngamePlayerListUI", "_draw"', 1, true))
        local layout_at = assert(owner:find(
            "mods/chaos_wastes_tweaker_dev/_ct_tab_collectibles_layout", 1, true))
        H.truthy(draw_at < layout_at, "layout module must still load after the draw hook")
        -- Call-time resolution, never a hoisted upvalue.
        H.truthy(owner:find("type(mod._ct_ensure_deus_collectibles) == \"function\"", 1, true))
    end)

    H.test("the six moved regression checks live only in the owner", function()
        for _, check in ipairs({
            '_rt_register("issue461_boon_preview_wired"',
            '_rt_register("issue1004_boon_hover_tooltip_wired"',
            '_rt_register("issue556_starting_talent_identity"',
            '_rt_register("issue533_cw_tab_collectibles_wired"',
            '_rt_register("issue533_native_tab_diagnostics_armed"',
            '_rt_register("issue571_cw_tab_collectibles_safe_reflow"',
        }) do
            H.equal(count_plain(owner, check), 1, check .. " must be registered once")
            H.equal(count_plain(entry, check), 0, check .. " must not remain in the entry")
        end
        H.equal(count_plain(owner, "_rt_register("), 6)
    end)

    H.test("load-time marker globals moved with their feature", function()
        -- _ct_regression.lua and the QA textual gates read these bare as globals.
        for _, marker in ipairs({
            'CT_BOON_PREVIEW_461_MARKER = "boon_preview_pilgrimage_context"',
            'CT_BOON_TOOLTIP_1004_MARKER = "starting_boon_hover_description_v2"',
            'CT_CW_TAB_COLLECTIBLES_533_MARKER = "cw_tab_collectibles_deus_counters_v0.7.257"',
        }) do
            H.equal(count_plain(owner, marker), 1, marker .. " must be set by the owner")
            H.equal(count_plain(entry, marker), 0, marker .. " must not be set twice")
        end
    end)

    H.test("moved locals left no orphan behind in the entry", function()
        -- The block's only file-scope local. It is read by the #571 check two
        -- lines later, so it moved intact; a surviving entry declaration would be
        -- an unread orphan and a surviving entry READ would be a nil index.
        -- The entry may still NAME it in the hand-off comment; what it must not
        -- have is a declaration or a live read.
        H.equal(count_plain(entry, "local _ct_tab_layout_571"), 0)
        H.equal(count_plain(entry, "_ct_tab_layout_571."), 0)
        H.equal(count_plain(owner, "local _ct_tab_layout_571"), 1)
        H.equal(count_plain(owner, "_ct_tab_layout_571.regression"), 1)
        -- Nothing had to be promoted to a mod._ct_* field for this slice: the
        -- entry keeps no half of any moved state.
        for _, sym in ipairs({
            "create_deus_loot_widget",
            "deus_run_controller_or_nil",
        }) do
            H.equal(count_plain(entry, sym), 0, sym .. " must no longer appear in the entry")
            H.truthy(owner:find(sym, 1, true), sym .. " must live in the owner")
        end
    end)

    H.test("the mod._ct_ public surface is preserved by the owner", function()
        -- Read by the moved regression checks and by _ct_tab_collectibles_layout.
        for _, field in ipairs({
            "function mod._ct_read_deus_collectible_values",
            "function mod._ct_build_deus_collectibles",
            "function mod._ct_refresh_deus_collectibles",
            "mod._ct_boon_preview_tooltip",
            "mod._ct_diag_tab_native533",
        }) do
            H.truthy(owner:find(field, 1, true), field .. " must be published by the owner")
        end
        -- Entry-side seams the owner consumes stay defined in the entry, ahead of
        -- the dofile, and are resolved through `mod` rather than an upvalue.
        for _, seam in ipairs({
            "mod._ct_rt_register = _rt_register",
            "mod._ct_effective_setting = effective_setting",
            "function mod._ct_starting_talent_is_duplicate",
        }) do
            local seam_at = assert(entry:find(seam, 1, true), seam .. " must stay in the entry")
            local owner_at = assert(entry:find(
                'mod:dofile("scripts/mods/chaos_wastes_tweaker_dev/_ct_tab_panel_owner")', 1, true))
            H.truthy(seam_at < owner_at, seam .. " must be published before the owner loads")
        end
    end)

    H.test("the /ct_preview_boons command moved with the panel it mirrors", function()
        H.equal(count_plain(owner, 'mod:command("ct_preview_boons"'), 1)
        H.equal(count_plain(entry, 'mod:command("ct_preview_boons"'), 0)
        H.equal(count_plain(owner, "mod:command"), 1)
    end)

    H.test("tab-panel owner does not overlap the two spawn owners", function()
        -- Those owners decide what exists in the world; this one only reports
        -- run-scoped counters read from the replicated deus-run SharedState.
        for _, head in ipairs(HOOKS) do
            H.equal(count_plain(pickup, head), 0, head .. " must not appear in the pickup owner")
            H.equal(count_plain(eligibility, head), 0,
                head .. " must not appear in the eligibility owner")
        end
        for _, sym in ipairs({
            'mod:hook("PickupSystem"',
            'mod:hook("UnitSpawner"',
            "mod._ct_collectible_to_coin",
            "mod._ct_tally_count",
        }) do
            H.equal(count_plain(owner, sym), 0, sym .. " belongs to the spawn owners")
        end
        -- The counters come from DeusRunController getters, never ct bookkeeping.
        H.truthy(owner:find("get_cursed_chests_purified", 1, true))
        H.truthy(owner:find("get_player_soft_currency", 1, true))
    end)

    H.test("owner carries no lifecycle surface", function()
        H.equal(count_plain(owner, "mod.on_setting_changed"), 0)
        H.equal(count_plain(owner, "mod.on_disabled"), 0)
        H.equal(count_plain(owner, "mod.on_enabled"), 0)
        H.equal(count_plain(owner, "mod.on_game_state_changed"), 0)
    end)
end
