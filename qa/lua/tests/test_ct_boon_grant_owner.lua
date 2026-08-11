-- Boundary test for the #1159 ct_dev boon-grant owner extraction.
-- Engine-free: asserts the structural contract of the split (hook ownership and
-- cardinality on the two grant/purchase choke points, the wiring position between
-- the #458/#467 dofiles it delegates to and the #211 grant-source wrappers it
-- reads, the shims that replace the three entry file-locals, the moved regression
-- checks, and non-overlap with the bot weapon-chest / pricing / tab-panel owners).
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
    local owner = read("_ct_boon_grant_owner.lua")
    local bot_chest = read("_ct_bot_weapon_chest_owner.lua")
    local pricing = read("_ct_boon_pricing_runtime.lua")
    local shrine = read("_ct_start_shrine_runtime.lua")
    local tab_panel = read("_ct_tab_panel_owner.lua")
    -- #1159 wave 14: the shared mod._ct_boon_disabled predicate moved out of the
    -- entry into the run-creation owner, WITH the roll-pool strip that is its
    -- other caller. It is still published before this owner loads.
    local run_creation = read("_ct_run_creation_owner.lua")
    local RUN_CREATION_INSTALL =
        'mod:dofile("scripts/mods/chaos_wastes_tweaker_dev/_ct_run_creation_owner")'

    -- The four grant/purchase seams. VMF silently drops a second hook on the same
    -- Class/method pair, so a duplicate would shadow the owner with no error.
    local HOOKS = {
        'mod:hook("DeusRunController", "add_power_ups"',
        'mod:hook("DeusRunController", "_try_buy_power_up"',
        'mod:hook("DeusShopView", "_init_power_up_widget"',
        'mod:hook("DeusShopView", "_on_power_up_bought"',
    }

    local DOFILE = 'mod:dofile("scripts/mods/chaos_wastes_tweaker_dev/_ct_boon_grant_owner")'

    H.test("boon-grant owner is dofile'd exactly once by the entry", function()
        H.equal(count_plain(entry, DOFILE), 1)
        -- Bare dofile, not an installer call: the module body runs at file scope
        -- exactly where the block used to execute, which is what preserves hook
        -- registration order and _rt_register append order.
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

    H.test("no second ct hook on any owned grant/purchase method", function()
        -- Whole-mod cardinality by method name: nothing else in ct_dev may hook
        -- these four, in any file.
        for _, method in ipairs({
            '"add_power_ups"',
            '"_try_buy_power_up"',
            '"_init_power_up_widget"',
            '"_on_power_up_bought"',
        }) do
            for _, other in ipairs({
                { "entry", entry }, { "bot_chest", bot_chest }, { "pricing", pricing },
                { "shrine", shrine }, { "tab_panel", tab_panel },
            }) do
                H.equal(count_plain(other[2], "mod:hook(" .. method), 0,
                    method .. " must not be hooked in " .. other[1])
                H.equal(count_plain(other[2], "mod:hook_safe(" .. method), 0,
                    method .. " must not be hook_safe'd in " .. other[1])
            end
        end
    end)

    H.test("owner loads AFTER the runtimes it delegates to, BEFORE the #211 wrappers", function()
        local owner_at = assert(entry:find(DOFILE, 1, true))
        -- #458 start-shrine and #467 pricing runtimes are dofile'd above it: the
        -- hook body reads mod._ct_start_shrine_runtime / mod._ct_boon_pricing_runtime.
        for _, seam in ipairs({
            "mods/chaos_wastes_tweaker_dev/_ct_start_shrine_runtime",
            "mods/chaos_wastes_tweaker_dev/_ct_boon_pricing_runtime",
        }) do
            local at = assert(entry:find(seam, 1, true))
            H.truthy(at < owner_at, seam .. " must load before the owner")
        end
        -- The #211 grant-source wrappers stay in the entry and register BELOW, the
        -- same order as before the split. They write the mod._ct_grant_source this
        -- owner's audit reads at call time.
        local set_reward_at = assert(entry:find(
            'mod:hook("DeusRunController", "_check_set_completed"', 1, true))
        H.truthy(owner_at < set_reward_at,
            "the #211 grant-source wrappers must still register after the owner")
    end)

    H.test("the three entry file-locals are replaced by declared shims", function()
        -- A file-local cannot cross a chunk boundary; each of these resolves to the
        -- exact same function object the entry used.
        H.truthy(owner:find("local function _dbg(fmt, ...)", 1, true))
        H.truthy(owner:find("mod:debug(\"[ct:dbg] \" .. fmt, ...)", 1, true))
        H.truthy(owner:find("local effective_setting = function(name)", 1, true))
        H.truthy(owner:find("local f = mod._ct_effective_setting", 1, true))
        H.truthy(owner:find("local _rt_register = mod._ct_rt_register", 1, true))
        -- Each seam is published by the entry BEFORE the owner loads.
        local owner_at = assert(entry:find(DOFILE, 1, true))
        for _, seam in ipairs({
            "mod._ct_rt_register = _rt_register",
            "mod._ct_effective_setting = effective_setting",
        }) do
            local at = assert(entry:find(seam, 1, true))
            H.truthy(at < owner_at, seam .. " must be published before the owner loads")
        end
    end)

    H.test("the mirror reentry guard moved with the block and left no entry local", function()
        -- Its only appearance outside the moved lines was a prose mention in an
        -- entry comment, so no promotion to a mod._ct_* field was needed.
        H.equal(count_plain(owner, "local _ct_bot_mirror_active = false"), 1)
        H.equal(count_plain(entry, "local _ct_bot_mirror_active"), 0)
        H.equal(count_plain(entry, "mod._ct_bot_mirror_active"), 0)
        H.equal(count_plain(owner, "mod._ct_bot_mirror_active"), 0)
        -- Set and cleared on both guarded paths (add_power_ups + _try_buy_power_up).
        H.equal(count_plain(owner, "_ct_bot_mirror_active = true"), 2)
        H.equal(count_plain(owner, "_ct_bot_mirror_active = false"), 3)
    end)

    H.test("published seams and the checks that read them moved together", function()
        for _, sym in ipairs({
            "function mod._ct_boon_display_name(name)",
            "function mod._ct_bot_pick_random_for_rarity(rarity)",
        }) do
            H.equal(count_plain(owner, sym), 1, sym .. " must be defined in the owner")
            H.equal(count_plain(entry, sym), 0, sym .. " must not remain in the entry")
        end
        H.equal(count_plain(owner, '_rt_register("bot_boon_announce_wired"'), 1)
        H.equal(count_plain(owner, '_rt_register("bot_boon_economy_installed"'), 1)
        H.equal(count_plain(owner, "_rt_register("), 2)
        -- The audit that reads mod._ct_boon_display_name stays in the entry and
        -- resolves the field at CALL time, guarded -- unchanged by the move.
        H.truthy(entry:find("if mod._ct_boon_display_name then", 1, true))
    end)

    H.test("owner reads, never defines, the cross-owner state it shares", function()
        -- Written by _ct_bot_weapon_chest_owner, read here to price an altar boon.
        H.truthy(bot_chest:find("mod._ct_bot_altar_cost = _opened_cost", 1, true))
        H.truthy(owner:find("mod._ct_bot_altar_cost", 1, true))
        H.equal(count_plain(owner, "mod._ct_bot_altar_cost = "), 0)
        -- CT_BOT_ECONOMY_MARKER stays a bare global set by the entry.
        H.truthy(entry:find('CT_BOT_ECONOMY_MARKER = "bot_economy', 1, true))
        H.equal(count_plain(owner, "CT_BOT_ECONOMY_MARKER = "), 0)
        H.truthy(owner:find("CT_BOT_ECONOMY_MARKER ~=", 1, true))
    end)

    H.test("owner owns no economy arithmetic and no pricing policy", function()
        -- _ct_bot_economy stays the pure ledger; _ct_boon_pricing_runtime and
        -- _ct_start_shrine_runtime stay the price/purchase policies. This module
        -- only calls them.
        for _, sym in ipairs({
            "function M.charge",
            "function M.credit",
            "function M.shop_boon_cost",
            "function M.grant_cost",
            "function M.price",
            "function M.try_buy",
        }) do
            H.equal(count_plain(owner, sym), 0, sym .. " must stay in its policy module")
        end
        H.truthy(owner:find("mod._ct_bot_economy.grant_cost(", 1, true))
        H.truthy(owner:find("mod._ct_boon_pricing_runtime.try_buy(", 1, true))
        H.truthy(owner:find("mod._ct_start_shrine_runtime.try_buy(", 1, true))
        -- The runtime adapters the coin and weapon paths also use stay in the entry.
        for _, sym in ipairs({
            "function mod._ct_bot_economy_charge",
            "function mod._ct_bot_economy_players",
            "function mod._ct_bot_economy_log",
        }) do
            H.equal(count_plain(entry, sym), 1, sym .. " must stay in the entry")
            H.equal(count_plain(owner, sym), 0, sym .. " must not be redefined in the owner")
        end
    end)

    H.test("owner does not overlap the tab-panel owner", function()
        -- That owner previews CONFIGURED starting boons; this one handles boons
        -- actually granted at runtime. No shared hook.
        for _, head in ipairs(HOOKS) do
            H.equal(count_plain(tab_panel, head), 0, head .. " must not appear in the tab panel")
        end
        H.equal(count_plain(owner, 'mod:hook_safe("IngamePlayerListUI"'), 0)
        H.equal(count_plain(owner, 'mod:hook("IngamePlayerListUI"'), 0)
    end)

    H.test("owner carries no lifecycle surface and no commands", function()
        H.equal(count_plain(owner, "mod.on_setting_changed"), 0)
        H.equal(count_plain(owner, "mod.on_disabled"), 0)
        H.equal(count_plain(owner, "mod.on_enabled"), 0)
        H.equal(count_plain(owner, "mod.on_game_state_changed"), 0)
        H.equal(count_plain(owner, "mod:command"), 0)
        H.equal(count_plain(owner, "mod:network_register"), 0)
    end)

    H.test("the #211/#426 gates survived the move intact", function()
        -- The pre-grant disable filter and the peer-parity eject are the reason
        -- add_power_ups is hooked at all; keep both bodies pinned to this file.
        H.truthy(owner:find("if name and mod._ct_boon_disabled(name) then", 1, true))
        H.truthy(owner:find("elseif name and mod._ct_is_modded_power_up and mod._ct_is_modded_power_up(name)",
            1, true))
        H.truthy(owner:find("not (mod._ct_wire_safe and mod._ct_wire_safe())", 1, true))
        H.equal(count_plain(entry, "if name and mod._ct_boon_disabled(name) then"), 0)
        -- mod._ct_boon_disabled is defined exactly once, by the run-creation owner
        -- (it travelled with the roll-pool strip, its other caller), and is still
        -- published BEFORE this owner loads. Same needle, new file, plus an
        -- entry-side absence so a stray second definition fails the suite.
        local def_at = assert(run_creation:find(
            "function mod._ct_boon_disabled(name)", 1, true))
        H.equal(count_plain(entry, "function mod._ct_boon_disabled(name)"), 0)
        H.equal(count_plain(run_creation, "function mod._ct_boon_disabled(name)"), 1)
        H.truthy(def_at > 0)
        local publish_at = assert(entry:find(RUN_CREATION_INSTALL, 1, true))
        H.truthy(publish_at < assert(entry:find(DOFILE, 1, true)),
            "the predicate must be published before the grant owner loads")
    end)
end
