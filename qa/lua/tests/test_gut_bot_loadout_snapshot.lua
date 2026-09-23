-- Offline proof for the #954 detached bot owner's native-designation import,
-- centred on the 0.2.355-dev modded-career path: a career designated in the
-- native PlayerData store but absent from the GUT store (Pusfume in Rain's
-- v0.2.354-dev log, `native bot designation not imported career=pusfume`)
-- must be imported as one detached snapshot, retried when the designation
-- appears late, bounded by MAX_STORE_CAREERS, and never aliased to the cache
-- row. The module's printf calls resolve through a test-local environment
-- seam; the global printf is never swapped (incident #1643).
return function(H, repo_root)
    local base = repo_root .. "/gui_tweaker_dev/scripts/mods/gui_tweaker_dev/"
    local Policy = assert(loadfile(base .. "_gut_native_loadout_policy.lua"))()
    local SLOTS = { "slot_melee", "slot_ranged", "slot_necklace", "slot_ring", "slot_trinket_1" }
    local PROBE = "gut_rt954_modded_probe"
    local MARKER = "_bot_designation_snapshot_v2"

    local function load_runtime(lines)
        local chunk = assert(loadfile(base .. "_gut_bot_loadout_snapshot.lua"))
        local env = setmetatable({
            printf = function(fmt, ...) lines[#lines + 1] = string.format(fmt, ...) end,
        }, { __index = _G })
        setfenv(chunk, env)
        return chunk()
    end

    local function count_lines(lines, needle)
        local n = 0
        for i = 1, #lines do
            if lines[i]:find(needle, 1, true) then n = n + 1 end
        end
        return n
    end

    -- Installs the owner against captured hooks and fake seams. `refresh`
    -- drives the hook_safe after-refresh path, `read` the get_bot_loadout wrap.
    local function install(opts)
        local hooks, registered, lines = {}, {}, {}
        local mod = {
            hook_safe = function(_, class, method, fn) hooks[class .. "." .. method] = fn end,
            hook = function(_, class, method, fn) hooks[class .. "." .. method] = fn end,
            _gut_rt_register = function(name, fn) registered[name] = fn end,
        }
        local Runtime = load_runtime(lines)
        local state = { store = opts.store or {}, native = opts.native or {}, persisted = 0 }
        Runtime.install(mod, {
            mode = function() return "store" end,
            mode_store = "store", mode_off = "off", mode_readonly = "readonly",
            store = function() return state.store end,
            persist = function() state.persisted = state.persisted + 1 end,
            policy = Policy, slot_names = SLOTS, log_prefix = "test",
            native_bot_assignments = function() return state.native end,
            seed_career = opts.seed_career,
        })
        local refresh = assert(hooks["BackendInterfaceItemPlayfab.refresh_bot_loadouts"])
        local read_hook = assert(hooks["BackendInterfaceItemPlayfab.get_bot_loadout"])
        local function read(iface)
            return read_hook(function(self) return self._bot_loadouts end, iface)
        end
        return Runtime, state, lines, refresh, read, registered
    end

    local function probe_row()
        return { slot_melee = "probe_melee", slot_ranged = "probe_ranged", ignored = "metadata" }
    end

    H.test("GUT #954 native-only modded career designation imports one detached snapshot", function()
        local row = probe_row()
        local Runtime, state, lines, refresh, read = install({
            store = {},
            native = { [PROBE] = 1 },
        })
        local iface = { _bot_loadouts = { [PROBE] = row } }
        refresh(iface)

        H.equal(Runtime.live_check(iface, state.store, Policy, SLOTS, state.native), nil,
            "native designation for a store-absent modded career must be imported")
        local entry = state.store[PROBE]
        H.truthy(type(entry) == "table", "store entry must be created for the native-only career")
        H.equal(entry[MARKER], true)
        H.equal(entry.bot_index, 1)
        H.equal(entry.selected_index, 1)
        H.deep_equal(entry.loadouts, {})
        H.deep_equal(entry.bot_loadout, { slot_melee = "probe_melee", slot_ranged = "probe_ranged" })
        H.truthy(entry.bot_loadout ~= row, "persisted snapshot must not alias the cache row")
        H.truthy(iface._bot_loadouts[PROBE] ~= row, "cache row must be replaced by a detached copy")
        H.truthy(iface._bot_loadouts[PROBE] ~= entry.bot_loadout,
            "cache copy must not share identity with the persisted snapshot")
        H.equal(state.persisted, 1)
        H.equal(count_lines(lines, "[gut:954] native-only career import career=" .. PROBE .. " index=1 source=native-bot-cache"), 1)
        H.equal(count_lines(lines, "[gut:954] native bot designation import imported=1 absent=0 invalid=0 existing=0 deferred=0 seeded=0"), 1)
        H.equal(Runtime.ledger.native_only_imports, 1)
        H.equal(Runtime.ledger.last_native_only.career_name, PROBE)
        H.equal(Runtime.ledger.last_native_only.reason, "refresh")

        -- The #954 guarantee: the player's row and the cache row are both
        -- detached from the persisted snapshot, and in-place cache drift is
        -- repaired on the next bounded read.
        row.slot_melee = "player-edited"
        refresh(iface)
        H.equal(iface._bot_loadouts[PROBE].slot_melee, "probe_melee")
        iface._bot_loadouts[PROBE].slot_melee = "drift"
        read(iface)
        H.equal(iface._bot_loadouts[PROBE].slot_melee, "probe_melee")
        H.equal(entry.bot_loadout.slot_melee, "probe_melee")
        H.equal(count_lines(lines, "reason=bot-read identity_changed=false applied=1 drifted=1"), 1)
        H.equal(Runtime.ledger.native_only_imports, 1, "a committed career is never imported twice")
        H.equal(state.persisted, 1, "reconcile without migration persists nothing")
    end)

    H.test("GUT #954 native-only import sits beside an already-owned vanilla career", function()
        local owned = {
            selected_index = 2, bot_index = 1,
            bot_loadout = { slot_melee = "owned_melee", slot_ranged = "owned_ranged" },
            [MARKER] = true,
            loadouts = { [1] = { slot_melee = "owned_melee", slot_ranged = "owned_ranged" } },
        }
        local Runtime, state, _, refresh = install({
            store = { dr_ranger = owned },
            native = { dr_ranger = 1, [PROBE] = 1 },
        })
        local iface = { _bot_loadouts = {
            dr_ranger = { slot_melee = "player_melee", slot_ranged = "player_ranged" },
            [PROBE] = probe_row(),
        } }
        refresh(iface)
        H.equal(Runtime.live_check(iface, state.store, Policy, SLOTS, state.native), nil)
        H.equal(iface._bot_loadouts.dr_ranger.slot_melee, "owned_melee")
        H.equal(state.store[PROBE].bot_loadout.slot_melee, "probe_melee")
        H.equal(state.store.dr_ranger, owned, "owned entry identity untouched")
        H.equal(state.persisted, 1)
    end)

    H.test("GUT #954 a designation appearing after the first import is imported on the next read", function()
        local Runtime, state, lines, refresh, read = install({ store = {}, native = {} })
        local iface = { _bot_loadouts = { [PROBE] = probe_row() } }
        refresh(iface)
        H.equal(state.store[PROBE], nil)
        H.equal(state.persisted, 0)
        H.equal(#lines, 1, "only the identity reconcile line")

        state.native[PROBE] = 2
        read(iface)
        H.equal(Runtime.live_check(iface, state.store, Policy, SLOTS, state.native), nil)
        H.equal(state.store[PROBE].bot_index, 2)
        H.equal(state.store[PROBE][MARKER], true)
        H.equal(Runtime.ledger.last_native_only.reason, "bot-read")
        H.equal(state.persisted, 1)
    end)

    H.test("GUT #954 a native-only career without a bot row defers and retries", function()
        local Runtime, state, lines, refresh = install({ store = {}, native = { [PROBE] = 1 } })
        local iface = { _bot_loadouts = {} }
        refresh(iface)
        H.equal(state.store[PROBE], nil, "nothing is sealed without a source row")
        H.equal(state.persisted, 0)
        H.equal(count_lines(lines, "native bot designation import imported=0 absent=0 invalid=0 existing=0 deferred=1 seeded=0"), 1)
        refresh(iface)
        H.equal(count_lines(lines, "deferred=1"), 1, "identical summaries are deduplicated")

        iface._bot_loadouts[PROBE] = probe_row()
        refresh(iface)
        H.equal(Runtime.live_check(iface, state.store, Policy, SLOTS, state.native), nil)
        H.equal(state.store[PROBE].bot_index, 1)
    end)

    H.test("GUT #954 seed seam outranks the bot cache for a native-only career", function()
        local seeded_with, store = {}, {}
        local Runtime, state, lines, refresh = install({
            store = store,
            native = { [PROBE] = 2 },
            seed_career = function(iface, career_name)
                seeded_with[#seeded_with + 1] = { iface = iface, career_name = career_name }
                store[career_name] = {
                    selected_index = 1, bot_index = nil, _seeded = true, _slot_integrity_v2 = true,
                    loadouts = {
                        [1] = { slot_melee = "official_one" },
                        [2] = { slot_melee = "official_two", slot_ranged = "official_two_ranged" },
                    },
                }
                return true
            end,
        })
        local iface = { _bot_loadouts = { [PROBE] = probe_row() } }
        refresh(iface)
        H.equal(#seeded_with, 1)
        H.equal(seeded_with[1].iface, iface, "seed seam receives the concrete interface")
        H.equal(seeded_with[1].career_name, PROBE)
        H.equal(Runtime.live_check(iface, state.store, Policy, SLOTS, state.native), nil)
        H.deep_equal(state.store[PROBE].bot_loadout,
            { slot_melee = "official_two", slot_ranged = "official_two_ranged" })
        H.equal(state.store[PROBE].bot_index, 2)
        H.equal(iface._bot_loadouts[PROBE].slot_melee, "official_two")
        H.equal(count_lines(lines, "native-only career import"), 0, "seeded rows import through the store path")
        H.equal(count_lines(lines, "imported=1 absent=0 invalid=0 existing=0 deferred=0 seeded=1"), 1)
        H.equal(Runtime.ledger.native_only_imports, 0)
        H.equal(state.persisted, 1)

        refresh(iface)
        H.equal(#seeded_with, 1, "a seeded career is never seeded again")
    end)

    H.test("GUT #954 a throwing seed seam falls back to the bot cache", function()
        local Runtime, state, _, refresh = install({
            store = {}, native = { [PROBE] = 1 },
            seed_career = function() error("mirror unavailable") end,
        })
        local iface = { _bot_loadouts = { [PROBE] = probe_row() } }
        refresh(iface)
        H.equal(Runtime.live_check(iface, state.store, Policy, SLOTS, state.native), nil)
        H.equal(Runtime.ledger.last_native_only.source, "native-bot-cache")
    end)

    H.test("GUT #954 native-only scan and store budget are bounded", function()
        local wide = {}
        for i = 1, 65 do wide["gut_rt954_wide_" .. i] = 1 end
        local Runtime, state, lines, refresh = install({ store = {}, native = wide })
        local iface = { _bot_loadouts = {} }
        refresh(iface)
        H.equal(next(state.store), nil, "no store write past the native bound")
        H.equal(state.persisted, 0)
        H.equal(count_lines(lines, "reconcile deferred reason=refresh detail=native-career-bound"), 1)
        H.equal(Runtime.ledger.last_reconcile_error, "native-career-bound")

        local full = {}
        for i = 1, 64 do full["gut_rt954_full_" .. i] = { selected_index = 1, loadouts = {} } end
        local _, state2, lines2, refresh2 = install({ store = full, native = { [PROBE] = 1 } })
        refresh2({ _bot_loadouts = { [PROBE] = probe_row() } })
        H.equal(state2.store[PROBE], nil)
        H.equal(count_lines(lines2, "detail=store-career-bound"), 1)
    end)

    H.test("GUT #954 invalid native-only indexes create nothing", function()
        local Runtime, state, lines, refresh = install({
            store = {}, native = { [PROBE] = 0, gut_rt954_text = "1", gut_rt954_frac = 1.5 },
        })
        local iface = { _bot_loadouts = { [PROBE] = probe_row(), gut_rt954_text = probe_row(), gut_rt954_frac = probe_row() } }
        refresh(iface)
        H.equal(next(state.store), nil)
        H.equal(state.persisted, 0)
        H.equal(count_lines(lines, "imported=0 absent=0 invalid=3 existing=0 deferred=0 seeded=0"), 1)
        H.equal(Runtime.ledger.native_only_imports, 0)
    end)

    H.test("GUT #954 contract check and registered sibling pass on fakes", function()
        local Runtime, _, _, _, _, registered = install({
            store = {}, native = {}, seed_career = function() return false end,
        })
        H.equal(Runtime.contract_check(Policy, SLOTS), nil)
        H.equal(Runtime.modded_career_proof(Policy, SLOTS), nil)
        local sibling = registered.issue954_modded_career_import
        H.truthy(type(sibling) == "function", "sibling check must register through mod._gut_rt_register")
        H.equal(sibling(), nil)
    end)

    H.test("GUT #954 pure planner never writes the store or the cache", function()
        local Runtime = load_runtime({})
        local store, bot, row = {}, {}, probe_row()
        bot[PROBE] = row
        local plans, counts, detail = Runtime.plan_native_only(
            store, { [PROBE] = 1 }, bot, Policy, SLOTS, nil, Runtime.MAX_STORE_CAREERS)
        H.equal(detail, nil)
        H.equal(#plans, 1)
        H.deep_equal(counts, { imported = 1, invalid = 0, deferred = 0, seeded = 0 })
        H.equal(next(store), nil, "planning writes nothing")
        H.equal(bot[PROBE], row, "planning replaces nothing")
        H.equal(plans[1].source, "native-bot-cache")
    end)
end
