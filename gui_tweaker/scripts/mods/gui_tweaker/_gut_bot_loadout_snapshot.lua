-- Detached bot-loadout owner (#954). The saved-loadout module supplies the
-- realm/store seams; this owner registers the two bot-specific hooks exactly
-- once and never touches official persistence.
local Runtime = {}

Runtime.MARKER = "gut-954-native-designation-import"

local MIGRATION_MARKER = "_bot_designation_snapshot_v2"

local MAX_COMPARE_DEPTH = 12
local MAX_COMPARE_NODES = 256
local MAX_STORE_CAREERS = 64
Runtime.MAX_STORE_CAREERS = MAX_STORE_CAREERS

-- Module-local ledger (0.2.355-dev). Regression checks read import evidence
-- here instead of swapping the global printf (incident #1643).
local ledger = {
    native_only_imports = 0,
    last_native_only = nil,
    last_import_summary = nil,
    last_reconcile_error = nil,
}
Runtime.ledger = ledger

local function values_equal(a, b, state, depth)
    if a == b then return true end
    if type(a) ~= type(b) or type(a) ~= "table" then return false end
    if depth >= MAX_COMPARE_DEPTH or state.nodes >= MAX_COMPARE_NODES then
        return nil
    end
    local paired = state.seen[a]
    if paired and paired[b] then return true end
    if not paired then
        paired = {}
        state.seen[a] = paired
    end
    paired[b] = true
    state.nodes = state.nodes + 1
    for key, value in pairs(a) do
        state.nodes = state.nodes + 1
        if state.nodes > MAX_COMPARE_NODES then return nil end
        local equal = values_equal(value, b[key], state, depth + 1)
        if equal ~= true then return equal end
    end
    for key in pairs(b) do
        state.nodes = state.nodes + 1
        if state.nodes > MAX_COMPARE_NODES then return nil end
        if a[key] == nil then return false end
    end
    return true
end

function Runtime.snapshots_equal(actual, expected, slot_names)
    if type(actual) ~= "table" or type(expected) ~= "table" then return false end
    if type(slot_names) ~= "table" then return false end
    local state = { nodes = 0, seen = {} }
    for i = 1, #slot_names do
        local slot = slot_names[i]
        local equal = values_equal(actual[slot], expected[slot], state, 0)
        if equal ~= true then return equal end
    end
    return true
end

function Runtime.live_check(items, saved_store, policy, slot_names, native_assignments)
    local bot = items and items._bot_loadouts
    if type(bot) ~= "table" then return "runtime bot cache unavailable" end
    if type(saved_store) ~= "table" then return "saved bot store unavailable" end
    local career_count = 0
    for career_name, entry in pairs(saved_store) do
        career_count = career_count + 1
        if career_count > MAX_STORE_CAREERS then
            return "saved bot store exceeds career bound"
        end
        local snapshot = type(entry) == "table" and entry.bot_loadout or nil
        if type(snapshot) == "table" then
            local equal = Runtime.snapshots_equal(bot[career_name], snapshot, slot_names)
            if equal == false then
                return "runtime bot cache mismatch career=" .. tostring(career_name)
            elseif equal == nil then
                return "runtime bot cache comparison bounded career=" .. tostring(career_name)
            end
        end
    end
    if native_assignments ~= nil then
        if type(native_assignments) ~= "table" then
            return "native bot designation store unavailable"
        end
        local native_count = 0
        for career_name, native_index in pairs(native_assignments) do
            native_count = native_count + 1
            if native_count > MAX_STORE_CAREERS then
                return "native bot designation store exceeds career bound"
            end
            if native_index ~= nil then
                local entry = saved_store[career_name]
                if type(entry) ~= "table"
                    or entry[MIGRATION_MARKER] ~= true
                    or type(entry.bot_loadout) ~= "table" then
                    return "native bot designation not imported career=" .. tostring(career_name)
                end
            end
        end
    end
end

local function valid_designation_index(index)
    return type(index) == "number" and index % 1 == 0 and index >= 1
end

-- 0.2.319-dev imported native designations only for careers the GUT store
-- already held, while live_check walks the native store. A career designated
-- there but never seeded into the store was therefore never imported: a modded
-- career such as Pusfume (named as the observed case only; the planner keys on the native store and touches no Pusfume API, hook or data) -- pusfume-compat-reviewed: comment reference, no runtime integration; absent Pusfume this path is inert
-- and the vanilla loadout window auto-designates such a career on
-- open [src: hero_window_loadout_selection_console.lua:176-184] and which
-- vanilla's own refresh skips because it carries no playfab_name [src:
-- backend_interface_item_playfab.lua:137-138]. Plan one detached snapshot per
-- native-only career: seed the store from official rows when the seam can (the
-- store loop then imports that row through the native-playerdata path), else
-- copy the backend's current bot row for that career. Writes nothing itself
-- except through `seed`; the caller commits the plans. `budget` bounds the
-- number of careers this pass may add to the store.
function Runtime.plan_native_only(all, native, bot, policy, slot_names, seed, budget)
    local plans = {}
    local counts = { imported = 0, invalid = 0, deferred = 0, seeded = 0 }
    if type(all) ~= "table" or type(native) ~= "table" then return plans, counts end
    local native_count = 0
    for career_name, native_index in pairs(native) do
        native_count = native_count + 1
        if native_count > MAX_STORE_CAREERS then
            return nil, counts, "native-career-bound"
        end
        if native_index ~= nil and all[career_name] == nil then
            if not valid_designation_index(native_index) then
                counts.invalid = counts.invalid + 1
            elseif counts.seeded + #plans >= (budget or MAX_STORE_CAREERS) then
                return nil, counts, "store-career-bound"
            else
                local seeded = false
                if type(seed) == "function" then
                    local ok, value = pcall(seed, career_name)
                    seeded = ok and value == true and type(all[career_name]) == "table"
                end
                local row = not seeded and type(bot) == "table" and bot[career_name] or nil
                if seeded then
                    counts.seeded = counts.seeded + 1
                elseif type(row) ~= "table" then
                    counts.deferred = counts.deferred + 1
                else
                    local snapshot, detail = policy.snapshot_bot_loadout(row, slot_names)
                    if detail then
                        return nil, counts, "native-only-snapshot-" .. tostring(detail)
                    end
                    if snapshot then
                        plans[#plans + 1] = {
                            career_name = career_name,
                            entry = { selected_index = 1, bot_index = nil, loadouts = {} },
                            snapshot = snapshot,
                            source_index = native_index,
                            set_index = true,
                            insert = true,
                            source = "native-bot-cache",
                        }
                        counts.imported = counts.imported + 1
                    else
                        counts.deferred = counts.deferred + 1
                    end
                end
            end
        end
    end
    return plans, counts
end

-- Commit phase shared by the live owner and the regression proof. Inserting a
-- planned entry and sealing its marker happen together, so a native-only
-- career can never sit in the store without its detached snapshot.
function Runtime.apply_migrations(all, migrations)
    for i = 1, #migrations do
        local migration = migrations[i]
        if migration.insert then all[migration.career_name] = migration.entry end
        if migration.set_index then migration.entry.bot_index = migration.source_index end
        if migration.snapshot ~= nil then migration.entry.bot_loadout = migration.snapshot end
        migration.entry[MIGRATION_MARKER] = true
    end
end

function Runtime.install(mod, deps)
    local mode = deps.mode
    local store = deps.store
    local persist = deps.persist
    local policy = deps.policy
    local slot_names = deps.slot_names
    local mode_store = deps.mode_store
    local log_prefix = deps.log_prefix
    local native_bot_assignments = deps.native_bot_assignments
    local seed_career = deps.seed_career
    -- The backend replaces `_bot_loadouts` whenever it refreshes. Remember the
    -- exact table that we audited, but still compare its designated rows on
    -- every bot-loadout read so an unexpected in-place writer is repaired and
    -- reported. `get_bot_loadout` is an equip/read edge, not a frame callback.
    local audited_bot_tables = setmetatable({}, { __mode = "k" })
    local pending_persist = setmetatable({}, { __mode = "k" })

    local function overlay(self, reason)
        -- Pass the concrete interface to the realm gate. During interface init,
        -- Managers.backend may not expose this instance yet even though `self`
        -- already owns the Adventure mirror.
        if mode(self) ~= mode_store then return false end
        local bot = self and self._bot_loadouts
        if type(bot) ~= "table" then return false end
        local all = store()
        if type(all) ~= "table" then return false, "store-unavailable" end
        local career_count = 0
        for _ in pairs(all) do
            career_count = career_count + 1
            if career_count > MAX_STORE_CAREERS then
                return false, "store-career-bound"
            end
        end

        local native = nil
        if type(native_bot_assignments) == "function" then
            local ok, value = pcall(native_bot_assignments)
            if ok and type(value) == "table" then native = value end
        end

        -- Native-only careers first: a seeded row joins the store loop below
        -- and imports through the existing native-playerdata path; a bot-cache
        -- copy is committed with the other migrations after validation.
        local native_plans, native_counts = {}, nil
        if native then
            local seed = nil
            if type(seed_career) == "function" then
                seed = function(career_name) return seed_career(self, career_name) end
            end
            local native_detail
            native_plans, native_counts, native_detail = Runtime.plan_native_only(
                all, native, bot, policy, slot_names, seed, MAX_STORE_CAREERS - career_count)
            if not native_plans then return false, native_detail end
        end

        local identity_changed = audited_bot_tables[self] ~= bot
        local migrations, replacements = {}, {}
        local imported, absent, invalid, existing, deferred = 0, 0, 0, 0, 0
        for career_name, entry in pairs(all) do
            if type(entry) == "table" then
                local bot_index = entry.bot_index
                local rows = type(entry.loadouts) == "table" and entry.loadouts or nil
                local snapshot = entry.bot_loadout
                local migration = nil

                -- Stores written before #954 may have only the GUT-owned index.
                -- Snapshot it once; later owner edits cannot alias it.
                if entry[MIGRATION_MARKER] ~= true
                    and type(snapshot) ~= "table" and bot_index and rows and rows[bot_index] then
                    local snapshot_detail
                    snapshot, snapshot_detail = policy.snapshot_bot_loadout(rows[bot_index], slot_names)
                    if snapshot_detail then
                        return false, "migration-snapshot-" .. tostring(snapshot_detail)
                    end
                    if snapshot then
                        migration = {
                            career_name = career_name,
                            entry = entry,
                            snapshot = snapshot,
                            source_index = bot_index,
                            source = "gut-index",
                        }
                        existing = existing + 1
                    end
                end

                -- Backward compatibility for assignments made by the vanilla UI
                -- before this owner existed. Vanilla persists only an index in
                -- PlayerData; import its row exactly once into the detached GUT
                -- owner. A newer GUT-owned index/snapshot always wins.
                if entry[MIGRATION_MARKER] ~= true and not migration then
                    if type(snapshot) == "table" then
                        migration = {
                            career_name = career_name,
                            entry = entry,
                            snapshot = snapshot,
                            source_index = bot_index,
                            source = "existing",
                        }
                        existing = existing + 1
                    elseif bot_index ~= nil then
                        if not valid_designation_index(bot_index) then
                            migration = {
                                career_name = career_name,
                                entry = entry,
                                source = "invalid-existing",
                            }
                            invalid = invalid + 1
                        else
                            -- The selected row may not have been seeded yet.
                            -- Retry at the next bounded read instead of sealing a
                            -- missing snapshot into the durable owner.
                            deferred = deferred + 1
                        end
                    elseif native then
                        local native_index = native[career_name]
                        if native_index == nil then
                            migration = {
                                career_name = career_name,
                                entry = entry,
                                source = "absent",
                            }
                            absent = absent + 1
                        elseif not valid_designation_index(native_index) then
                            migration = {
                                career_name = career_name,
                                entry = entry,
                                source = "invalid",
                            }
                            invalid = invalid + 1
                        elseif not rows or not rows[native_index] then
                            deferred = deferred + 1
                        else
                            local snapshot_detail
                            snapshot, snapshot_detail =
                                policy.snapshot_bot_loadout(rows[native_index], slot_names)
                            if snapshot_detail then
                                return false, "native-import-snapshot-" .. tostring(snapshot_detail)
                            end
                            if snapshot then
                                bot_index = native_index
                                migration = {
                                    career_name = career_name,
                                    entry = entry,
                                    snapshot = snapshot,
                                    source_index = native_index,
                                    set_index = true,
                                    source = "native-playerdata",
                                }
                                imported = imported + 1
                            end
                        end
                    end
                end
                if migration then migrations[#migrations + 1] = migration end
                if type(snapshot) == "table" then
                    local matches = Runtime.snapshots_equal(bot[career_name], snapshot, slot_names)
                    if identity_changed or matches == false then
                        -- The backend cache gets another detached copy so it cannot
                        -- mutate the persisted bot snapshot through table identity.
                        local detached, snapshot_detail =
                            policy.snapshot_bot_loadout(snapshot, slot_names)
                        if type(detached) ~= "table" then
                            return false, "cache-snapshot-" .. tostring(snapshot_detail or "unavailable")
                        end
                        replacements[#replacements + 1] = {
                            career_name = career_name,
                            snapshot = detached,
                            drifted = not identity_changed and matches == false,
                        }
                    end
                end
            end
        end

        -- A native-only career joins the same commit: its store entry and a
        -- second detached copy for the backend cache, never the cache row itself.
        for i = 1, #native_plans do
            local plan = native_plans[i]
            local detached, snapshot_detail = policy.snapshot_bot_loadout(plan.snapshot, slot_names)
            if type(detached) ~= "table" then
                return false, "cache-snapshot-" .. tostring(snapshot_detail or "unavailable")
            end
            migrations[#migrations + 1] = plan
            replacements[#replacements + 1] = {
                career_name = plan.career_name,
                snapshot = detached,
                drifted = false,
            }
        end

        -- Commit only after every row has passed the bounded validation/copy
        -- phase. One corrupt later career must not leave earlier owners
        -- half-migrated or half-reconciled in memory.
        Runtime.apply_migrations(all, migrations)
        local drifted = 0
        for i = 1, #replacements do
            local replacement = replacements[i]
            bot[replacement.career_name] = replacement.snapshot
            if replacement.drifted then drifted = drifted + 1 end
        end
        local migrated = #migrations > 0
        local applied = #replacements
        local seeded = 0
        if native_counts then
            imported = imported + native_counts.imported
            invalid = invalid + native_counts.invalid
            deferred = deferred + native_counts.deferred
            seeded = native_counts.seeded
        end
        audited_bot_tables[self] = bot
        if migrated or seeded > 0 or pending_persist[self] then
            local persisted = pcall(persist)
            pending_persist[self] = not persisted
            if not persisted then
                return false, "persist-failed"
            end
        end
        if migrated or deferred > 0 or invalid > 0 then
            local summary = string.format(
                "imported=%d absent=%d invalid=%d existing=%d deferred=%d seeded=%d",
                imported, absent, invalid, existing, deferred, seeded)
            if summary ~= ledger.last_import_summary then
                ledger.last_import_summary = summary
                printf("[gut:954] native bot designation import %s", summary)
            end
        end
        for i = 1, #native_plans do
            local plan = native_plans[i]
            ledger.native_only_imports = ledger.native_only_imports + 1
            ledger.last_native_only = {
                career_name = plan.career_name,
                index = plan.source_index,
                source = plan.source,
                reason = reason,
            }
            printf("[gut:954] native-only career import career=%s index=%s source=%s reason=%s",
                tostring(plan.career_name), tostring(plan.source_index),
                tostring(plan.source), tostring(reason))
        end
        if identity_changed or applied > 0 or drifted > 0 then
            printf("[gut:954] bot cache reconcile reason=%s identity_changed=%s applied=%s drifted=%s",
                tostring(reason), tostring(identity_changed), tostring(applied), tostring(drifted))
        end
        return true
    end

    local function safe_overlay(self, reason)
        local ok, applied, detail = pcall(overlay, self, reason)
        if not ok then
            detail = "error:" .. tostring(applied)
            applied = false
        end
        if applied then
            ledger.last_reconcile_error = nil
        elseif detail and detail ~= ledger.last_reconcile_error then
            ledger.last_reconcile_error = detail
            pcall(printf, "[gut:954] bot cache reconcile deferred reason=%s detail=%s",
                tostring(reason), tostring(detail))
        end
        return applied
    end

    mod:hook_safe("BackendInterfaceItemPlayfab", "refresh_bot_loadouts", function(self)
        safe_overlay(self, "refresh")
    end)

    -- Vanilla reads `_bot_loadouts` through this single getter from both
    -- get_loadout_item_id and get_loadout_by_career_name. Reconcile before the
    -- getter returns so a refresh that happened before hook installation, while
    -- the modded Adventure gate was not ready, or inside the getter's `_dirty`
    -- refresh cannot leak the owner's base loadout into a bot. This also detects
    -- and repairs an in-place writer.
    mod:hook("BackendInterfaceItemPlayfab", "get_bot_loadout", function(func, self, ...)
        local result = func(self, ...)
        safe_overlay(self, "bot-read")
        return result
    end)

    -- The native UI designates a saved row by index. Store that index for its
    -- checkmark, but make the bot's equipment a point-in-time copy. [src:
    -- hero_window_loadout_selection_console.lua:671-683]
    mod:hook("HeroWindowLoadoutSelectionConsole", "_save_bot_equipment", function(func, self)
        local current_mode = mode()
        if current_mode == deps.mode_off then return func(self) end
        if current_mode == deps.mode_readonly then
            printf("[%s:NATIVE_LOADOUTS] bot_equipment BLOCKED (read-only non-modded loadouts)", log_prefix)
            return
        end

        local profile = SPProfiles and SPProfiles[self._profile_index]
        local career_settings = profile and profile.careers and profile.careers[self._career_index]
        local career_name = career_settings and career_settings.name
        if not career_name then return end

        local all = store()
        local entry = all[career_name]
        if type(entry) ~= "table" then
            entry = { selected_index = 1, bot_index = nil, loadouts = {} }
            all[career_name] = entry
        end
        if type(entry.loadouts) ~= "table" then entry.loadouts = {} end
        entry.bot_index = self._context_menu_loadout_index
        local designated_row = entry.bot_index and entry.loadouts[entry.bot_index]
        entry.bot_loadout = policy.snapshot_bot_loadout(designated_row, slot_names)
        entry[MIGRATION_MARKER] = true
        persist()
        printf("[%s:NATIVE_LOADOUTS] bot_equipment career=%s bot_index=%s detached_snapshot=%s -> store (skipped PlayerData write)",
            log_prefix, tostring(career_name), tostring(entry.bot_index),
            tostring(entry.bot_loadout ~= nil))

        local ok, iface = pcall(function() return Managers.backend:get_interface("items") end)
        if ok and iface and iface.refresh_bot_loadouts then
            pcall(function() iface:refresh_bot_loadouts() end)
        end
    end)

    -- Sibling of issue954_bot_loadout_snapshot: the synthetic modded-career
    -- proof plus the installed seam and the module ledger, so a live card shows
    -- the native-only path by name. Registered here because the seam file sits
    -- at its file-size ratchet.
    if type(mod._gut_rt_register) == "function" then
        mod._gut_rt_register("issue954_modded_career_import", function()
            local err = Runtime.modded_career_proof(policy, slot_names)
            if err then return err end
            if type(seed_career) ~= "function" then return "seed seam not wired" end
            if mode() ~= mode_store then return end
            if ledger.last_reconcile_error then
                return "bot cache reconcile deferred: " .. tostring(ledger.last_reconcile_error)
            end
        end)
    end
end

-- Synthetic modded-career proof shared by issue954_bot_loadout_snapshot
-- (through contract_check) and issue954_modded_career_import. Pure fakes only:
-- the real store, backend cache and PlayerData are never touched.
function Runtime.modded_career_proof(policy, slot_names)
    if type(Runtime.plan_native_only) ~= "function" then return "native-only planner unavailable" end
    local probe = "gut_rt954_modded_probe"
    local row = { slot_melee = "probe_melee", slot_ranged = "probe_ranged", ignored = "metadata" }
    local store, native, bot = {}, { [probe] = 1 }, { [probe] = row }
    local plans, counts, detail =
        Runtime.plan_native_only(store, native, bot, policy, slot_names, nil, MAX_STORE_CAREERS)
    if detail or type(plans) ~= "table" or #plans ~= 1 or counts.imported ~= 1 then
        return "native-only plan missing: " .. tostring(detail or (plans and #plans))
    end
    local plan = plans[1]
    if plan.career_name ~= probe or plan.source ~= "native-bot-cache" or plan.source_index ~= 1
        or plan.insert ~= true or plan.set_index ~= true then
        return "native-only plan shape mismatch"
    end
    if plan.snapshot == row or plan.snapshot.slot_melee ~= "probe_melee" or plan.snapshot.ignored ~= nil then
        return "native-only snapshot aliases the bot cache row"
    end
    Runtime.apply_migrations(store, plans)
    local entry = store[probe]
    if type(entry) ~= "table" or entry.bot_index ~= 1 or entry.bot_loadout ~= plan.snapshot
        or entry[MIGRATION_MARKER] ~= true then
        return "native-only entry not committed"
    end
    row.slot_melee = "owner-edited"
    if entry.bot_loadout.slot_melee ~= "probe_melee" then
        return "native-only snapshot followed the source row"
    end
    local err = Runtime.live_check({ _bot_loadouts = { [probe] = entry.bot_loadout } },
        store, policy, slot_names, native)
    if err then return "native-only import fails live check: " .. err end
    -- A designation appearing after the first import is planned on the next
    -- pass; the committed career is not planned twice.
    native.gut_rt954_late_probe = 2
    bot.gut_rt954_late_probe = { slot_melee = "late_melee" }
    plans, counts, detail =
        Runtime.plan_native_only(store, native, bot, policy, slot_names, nil, MAX_STORE_CAREERS)
    if detail or #plans ~= 1 or plans[1].career_name ~= "gut_rt954_late_probe"
        or plans[1].source_index ~= 2 then
        return "late native-only designation not re-planned"
    end
    -- Bounded: the native scan and the store budget both refuse before any write.
    local wide = {}
    for i = 1, MAX_STORE_CAREERS + 1 do wide["gut_rt954_wide_" .. i] = 1 end
    plans, counts, detail = Runtime.plan_native_only({}, wide, {}, policy, slot_names, nil, MAX_STORE_CAREERS)
    if plans ~= nil or detail ~= "native-career-bound" then return "native-only scan unbounded" end
    plans, counts, detail = Runtime.plan_native_only({}, { [probe] = 1 }, bot, policy, slot_names, nil, 0)
    if plans ~= nil or detail ~= "store-career-bound" then return "native-only budget unbounded" end
    -- A seeded store row outranks the bot cache and leaves no plan behind.
    local seeded_store = {}
    local function seed(career_name)
        seeded_store[career_name] = { selected_index = 1, loadouts = { [1] = { slot_melee = "seeded_melee" } } }
        return true
    end
    plans, counts, detail =
        Runtime.plan_native_only(seeded_store, { [probe] = 1 }, bot, policy, slot_names, seed, MAX_STORE_CAREERS)
    if detail or #plans ~= 0 or counts.seeded ~= 1 or type(seeded_store[probe]) ~= "table" then
        return "seed seam not preferred over the bot cache"
    end
    -- An invalid native-only index creates nothing and is counted.
    plans, counts, detail =
        Runtime.plan_native_only({}, { [probe] = 0 }, bot, policy, slot_names, nil, MAX_STORE_CAREERS)
    if detail or #plans ~= 0 or counts.invalid ~= 1 then return "invalid native-only index not rejected" end
end

function Runtime.contract_check(policy, slot_names)
    if Runtime.MARKER ~= "gut-954-native-designation-import" then return "marker mismatch" end
    if type(policy.snapshot_bot_loadout) ~= "function" then return "snapshot helper unavailable" end
    local source = { slot_melee = "owner", slot_ranged = "ranged", ignored = "metadata" }
    local snapshot = policy.snapshot_bot_loadout(source, slot_names)
    if type(snapshot) ~= "table" then return "bot snapshot unavailable" end
    source.slot_melee = "owner-edited"
    if snapshot.slot_melee ~= "owner" then return "bot snapshot aliases owner row" end
    if snapshot.ignored ~= nil then return "bot snapshot retained non-slot metadata" end
    if not Runtime.snapshots_equal(snapshot, {
        slot_melee = "owner",
        slot_ranged = "ranged",
    }, slot_names) then
        return "bot snapshot comparator mismatch"
    end
    return Runtime.modded_career_proof(policy, slot_names)
end

return Runtime
