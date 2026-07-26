-- Detached bot-loadout owner (#954). The saved-loadout module supplies the
-- realm/store seams; this owner registers the two bot-specific hooks exactly
-- once and never touches official persistence.
local Runtime = {}

Runtime.MARKER = "gut-954-bot-read-reconcile"

local MAX_COMPARE_DEPTH = 12
local MAX_COMPARE_NODES = 256
local MAX_STORE_CAREERS = 64

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

function Runtime.live_check(items, saved_store, policy, slot_names)
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
end

function Runtime.install(mod, deps)
    local mode = deps.mode
    local store = deps.store
    local persist = deps.persist
    local policy = deps.policy
    local slot_names = deps.slot_names
    local mode_store = deps.mode_store
    local log_prefix = deps.log_prefix
    -- The backend replaces `_bot_loadouts` whenever it refreshes. Remember the
    -- exact table that we audited, but still compare its designated rows on
    -- every bot-loadout read so an unexpected in-place writer is repaired and
    -- reported. `get_bot_loadout` is an equip/read edge, not a frame callback.
    local audited_bot_tables = setmetatable({}, { __mode = "k" })
    local pending_persist = setmetatable({}, { __mode = "k" })
    local last_reconcile_error = nil

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

        local identity_changed = audited_bot_tables[self] ~= bot
        local migrations, replacements = {}, {}
        for career_name, entry in pairs(all) do
            if type(entry) == "table" then
                local bot_index = entry.bot_index
                local rows = type(entry.loadouts) == "table" and entry.loadouts or nil
                local snapshot = entry.bot_loadout
                -- One-time migration for stores written before #954. Snapshot the
                -- current designated row once; later owner edits cannot alias it.
                if type(snapshot) ~= "table" and bot_index and rows and rows[bot_index] then
                    local snapshot_detail
                    snapshot, snapshot_detail = policy.snapshot_bot_loadout(rows[bot_index], slot_names)
                    if snapshot_detail then
                        return false, "migration-snapshot-" .. tostring(snapshot_detail)
                    end
                    if snapshot then
                        migrations[#migrations + 1] = {
                            career_name = career_name,
                            entry = entry,
                            snapshot = snapshot,
                            source_index = bot_index,
                        }
                    end
                end
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

        -- Commit only after every row has passed the bounded validation/copy
        -- phase. One corrupt later career must not leave earlier owners
        -- half-migrated or half-reconciled in memory.
        for i = 1, #migrations do
            local migration = migrations[i]
            migration.entry.bot_loadout = migration.snapshot
            printf("[gut:954] migrated detached bot loadout career=%s source_index=%s",
                tostring(migration.career_name), tostring(migration.source_index))
        end
        local drifted = 0
        for i = 1, #replacements do
            local replacement = replacements[i]
            bot[replacement.career_name] = replacement.snapshot
            if replacement.drifted then drifted = drifted + 1 end
        end
        local migrated = #migrations > 0
        local applied = #replacements
        audited_bot_tables[self] = bot
        if migrated or pending_persist[self] then
            local persisted = pcall(persist)
            pending_persist[self] = not persisted
            if not persisted then
                return false, "persist-failed"
            end
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
            last_reconcile_error = nil
        elseif detail and detail ~= last_reconcile_error then
            last_reconcile_error = detail
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
        persist()
        printf("[%s:NATIVE_LOADOUTS] bot_equipment career=%s bot_index=%s detached_snapshot=%s -> store (skipped PlayerData write)",
            log_prefix, tostring(career_name), tostring(entry.bot_index),
            tostring(entry.bot_loadout ~= nil))

        local ok, iface = pcall(function() return Managers.backend:get_interface("items") end)
        if ok and iface and iface.refresh_bot_loadouts then
            pcall(function() iface:refresh_bot_loadouts() end)
        end
    end)
end

function Runtime.contract_check(policy, slot_names)
    if Runtime.MARKER ~= "gut-954-bot-read-reconcile" then return "marker mismatch" end
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
end

return Runtime
