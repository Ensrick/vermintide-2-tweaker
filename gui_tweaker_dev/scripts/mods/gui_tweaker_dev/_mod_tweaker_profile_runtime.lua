-- Shared transactional runtime for Mod Tweaker profile reconciliation (#828).
-- Engine-free: presentations supply owner/transaction functions explicitly.

local Runtime = {}

-- Shared read-only semantic validation. Callers may discard the prepared full
-- replay plans (automatic initialization must apply additions only).
local function prepare_profile(args, values, defaults)
    local profiles, category = args.profiles, args.category
    local states = profiles.owner_states(values)
    local pending, prepared = {}, {}
    for member, value in pairs(values) do
        if member ~= profiles.OWNER_STATE_KEY then
            local mid, sid = profiles.split_member_key(member)
            local _, actual = args.owner(category, sid)
            local excluded = category._profile_excluded_owners
            if mid and sid and mid == actual and not (excluded and excluded[mid]) then
                assert(defaults[member] ~= nil, "unregistered profile member")
                pending[mid] = pending[mid] or {}
                pending[mid][sid] = value
            end
        end
    end
    for mid in pairs(states) do assert(pending[mid], "foreign profile-state owner") end
    for mid, buffer in pairs(pending) do
        local context = { kind = "profile", metadata = states[mid] }
        context.plan = args.transactions.prepare(category, buffer, args.owner, context)
        context.prepared = true
        prepared[mid] = context
    end
    return prepared, pending
end

function Runtime.transaction_context(view, category, pending, owner)
    local replay = view._profile_replay
    if not replay then return nil end
    local _, owner_id = owner(category, next(pending))
    return replay.contexts[owner_id]
end

-- Called by both presentations at the existing successful-capture boundary.
-- A failed replay keeps its target/context and never captures into the old slot.
function Runtime.finish_replay(view, category, profiles, store, tab_id, values)
    local replay = view._profile_replay
    if not replay then return true end
    if replay.tab_id ~= tab_id then return false end
    for mid in pairs(replay.contexts) do
        if next(view._pending[mid] or {}) then return false end
    end
    profiles.save(store, tab_id, replay.slot, values)
    profiles.set_active(store, tab_id, replay.slot)
    view._profile_slot = replay.slot
    view._profile_replay = nil
    if replay.on_complete then pcall(replay.on_complete, tab_id) end
    return true, true
end

-- One shared switch implementation: prepare every owner's complete replay
-- before publishing any setting, changing the active slot, or saving a profile.
-- Provider-private state stays in the profile envelope, never stage_set.
function Runtime.switch_profile(view, slot, args)
    local category, profiles, store = args.category, args.profiles, args.store
    local tab_id = args.tab_id
    local current = profiles.get_active(store, tab_id)
    if slot == current and not view._profile_replay then return true end
    if view:_active_category_dirty() then
        view:apply_pending(category)
        if view:_active_category_dirty() then return false, "pending transaction incomplete" end
        current = profiles.get_active(store, tab_id)
        if slot == current then return true end
    end
    local defaults, defaults_error = view:_profile_snapshot(category, true)
    if not defaults then return false, defaults_error end
    local values = profiles.load(store, tab_id, slot)
    if values then values = profiles.migrate_ct_trial_cost_map(values) end
    values = values and profiles.reconcile(values, defaults) or defaults
    local ok, contexts, groups = pcall(prepare_profile, args, values, defaults)
    if not ok then return false, tostring(contexts) end
    local snapshot, capture_error = view:_profile_snapshot(category, false)
    if not snapshot then return false, capture_error end
    if not Runtime.migrate(profiles, store, args.log) then return false, "profile migration unavailable" end
    profiles.save(store, tab_id, current, snapshot)
    view._profile_replay = { tab_id = tab_id, slot = slot, contexts = contexts,
        on_complete = args.on_complete }
    for _, buffer in pairs(groups) do
        for sid, value in pairs(buffer) do view:stage_set(category, sid, value) end
    end
    if next(groups) then view:apply_pending(category)
    else view:_profile_capture(category); view:_build_rows(category) end
    if view._profile_replay then return false, "profile transaction incomplete" end
    return true
end

function Runtime.migrate(profiles, store, log)
    local ok, changed, err = profiles.migrate_all(store)
    if not ok then
        if log then log("[gut:825] profile schema deferred error=%s", tostring(err)) end
        return false, 0, err
    end
    if changed > 0 and log then
        log("[gut:825] migrated CT trial-cost profiles=%d", changed)
    end
    return true, changed
end

function Runtime.reconcile_and_apply(args)
    local profiles = assert(args.profiles)
    local transactions = assert(args.transactions)
    local merged, additions, added = profiles.reconcile(args.values, args.defaults)
    -- Validate even when nothing was added. A successful no-op must not certify
    -- corrupt metadata or permit schema/profile bookkeeping to persist it.
    local valid, validation_error = pcall(prepare_profile, args, merged, args.defaults)
    if not valid then return merged, additions, added, false, 0, 1, tostring(validation_error) end
    local owners = {}
    local accepted = 0
    for member, value in pairs(additions) do
        local owner_id, setting_id = profiles.split_member_key(member)
        local _, actual_owner = args.owner(args.category, setting_id)
        local excluded = args.category and args.category._profile_excluded_owners
        if owner_id and setting_id and actual_owner == owner_id
                and not (excluded and excluded[owner_id]) then
            owners[owner_id] = owners[owner_id] or {}
            owners[owner_id][setting_id] = value
            accepted = accepted + 1
        end
    end
    if accepted ~= added then
        return merged, additions, added, false, 0, 1, "unowned profile member"
    end

    -- Prepare the actual additions as initialization, not ordinary user edits.
    -- Every owner may refuse this context before any migration or sibling write.
    local contexts = {}
    local prepared, prepare_error = pcall(function()
        for mid, pending in pairs(owners) do
            local context = { kind = "reconcile" }
            context.plan = transactions.prepare(args.category, pending, args.owner, context)
            context.prepared = true
            contexts[mid] = context
        end
    end)
    if not prepared then return merged, additions, added, false, 0, 1, tostring(prepare_error) end
    if args.store and not Runtime.migrate(profiles, args.store, args.log) then
        return merged, additions, added, false, 0, 1, "profile migration unavailable"
    end
    if added == 0 then return merged, additions, 0, true, 0, 0 end

    local applied = 0
    local failures = 0
    local last_error
    for mid, pending in pairs(owners) do
        local ok, count, _, err = pcall(transactions.commit,
            args.category, pending, args.owner, args.set_one, contexts[mid])
        if not ok then
            failures = failures + 1
            last_error = tostring(count)
        else
            applied = applied + (tonumber(count) or 0)
            if err then
                failures = failures + 1
                last_error = tostring(err)
            end
        end
    end
    return merged, additions, added,
        applied == added and failures == 0, applied, failures, last_error
end

-- Both automatic entrypoints validate before migration/persistence and only
-- apply absent members. Unlike an explicit switch, existing live values and
-- pending drafts do not participate in a full profile replay here.
function Runtime.ensure_profile(view, args)
    local profiles, store, category = args.profiles, args.store, args.category
    local slot = profiles.get_active(store, args.tab_id)
    view._profile_slot = slot
    local ready_key = args.tab_id .. ":" .. tostring(slot)
    if view._profile_ready[ready_key] then return true end
    local ok, err = pcall(function()
        local values = profiles.load(store, args.tab_id, slot)
        local defaults, defaults_error = view:_profile_snapshot(category, true)
        assert(defaults, defaults_error)
        if not values then
            local snapshot, capture_error = view:_profile_snapshot(category, slot ~= 1)
            assert(snapshot, capture_error)
            prepare_profile(args, snapshot, defaults)
            assert(Runtime.migrate(profiles, store, args.log), "profile migration unavailable")
            profiles.save(store, args.tab_id, slot, snapshot)
            if args.log then args.log("[gut:561] initialized tab=%s profile=%d source=%s",
                tostring(args.tab_id), slot, slot ~= 1 and "defaults" or "live") end
        else
            values = profiles.migrate_ct_trial_cost_map(values)
            local merged, _, added, applied_ok, applied, _, apply_error = Runtime.reconcile_and_apply({
                profiles = profiles, transactions = args.transactions, values = values, defaults = defaults,
                category = category, owner = args.owner, set_one = args.set_one, store = store, log = args.log,
            })
            assert(applied_ok, apply_error or "profile reconciliation incomplete")
            if added > 0 then
                profiles.save(store, args.tab_id, slot, merged)
                if args.log then args.log("[gut:828] reconciled tab=%s profile=%d added=%d applied=%d",
                    tostring(args.tab_id), slot, added, applied) end
            end
        end
    end)
    if not ok then
        if args.log then args.log("[gut:221] profile ensure deferred tab=%s profile=%d error=%s",
            tostring(args.tab_id), slot, tostring(err)) end
        return false, tostring(err)
    end
    view._profile_ready[ready_key] = true
    return true
end

return Runtime
