local Runtime = {}

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
    if added == 0 then return merged, additions, 0, true, 0, 0 end
    local owners, accepted = {}, 0
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
    local applied, failures, last_error = 0, 0
    for _, pending in pairs(owners) do
        local ok, count, _, err = pcall(transactions.commit,
            args.category, pending, args.owner, args.set_one)
        if not ok then
            failures = failures + 1
            last_error = tostring(count)
        else
            applied = applied + (tonumber(count) or 0)
            if err then failures = failures + 1; last_error = tostring(err) end
        end
    end
    return merged, additions, added,
        applied == added and failures == 0, applied, failures, last_error
end

return Runtime
