return function(H, repo_root)
    local root = repo_root
        .. "/general_tweaker_dev/scripts/mods/general_tweaker_dev/"
    local policy = dofile(root .. "_gt_necro_keep_policy.lua")

    H.test("GT #659 keep-pet truth table preserves human and bot ownership", function()
        H.equal(policy.should_clear(false, false, true), true)
        H.equal(policy.should_clear(false, true, true), true)
        H.equal(policy.should_clear(true, true, true), true)
        H.equal(policy.should_clear(true, false, true), false)
        H.equal(policy.should_clear(false, true, false), false)
    end)

    H.test("GT #659 reconciles an initialized human extension idempotently", function()
        local extension = {
            _player = { bot_player = false },
            _pets_forbidden_in_level = true,
        }
        local changed, before, after, owner = policy.reconcile(extension, false)
        H.equal(changed, true)
        H.equal(before, true)
        H.equal(after, false)
        H.equal(owner, "human")

        changed, before, after, owner = policy.reconcile(extension, false)
        H.equal(changed, false)
        H.equal(before, false)
        H.equal(after, false)
        H.equal(owner, "human")
    end)

    H.test("GT #659 keeps bot gating and missing-owner behavior fail-closed", function()
        local bot = {
            _player = { bot_player = true },
            _pets_forbidden_in_level = true,
        }
        local changed, before, after, owner = policy.reconcile(bot, false)
        H.equal(changed, false)
        H.equal(before, true)
        H.equal(after, true)
        H.equal(owner, "bot")

        changed, before, after, owner = policy.reconcile(bot, true)
        H.equal(changed, true)
        H.equal(before, true)
        H.equal(after, false)
        H.equal(owner, "bot")

        changed, before, after, owner = policy.reconcile({}, true)
        H.equal(changed, false)
        H.equal(before, nil)
        H.equal(after, nil)
        H.equal(owner, "unknown")
    end)

    H.test("GT #659 owns one hook per passive lifecycle method", function()
        local file = assert(io.open(root .. "_gt_bots_keep.lua", "rb"))
        local source = file:read("*a")
        file:close()
        H.equal(select(2, source:gsub(
            'mod:hook_safe%("PassiveAbilityNecromancerCharges", "_on_talents_changed"', '')), 1)
        H.equal(select(2, source:gsub(
            'mod:hook_safe%("PassiveAbilityNecromancerCharges", "extensions_ready"', '')), 1)
        H.truthy(source:find('_bik_necro_reconcile(self, "extensions_ready")', 1, true))
    end)
end
