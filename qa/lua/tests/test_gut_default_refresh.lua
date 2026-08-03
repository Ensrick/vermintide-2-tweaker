return function(H, repo_root)
    local core_path = repo_root
        .. "/gui_tweaker_dev/scripts/mods/gui_tweaker_dev/_gut_default_refresh_core.lua"
    local Core = assert(loadfile(core_path))()

    -- Issue #1033 presentation half: the DEFAULT reset's live refresh must fire
    -- exactly in the live keep, defer in a mission (force_respawn teleports to
    -- level start with fresh health/ammo), and skip when there is nothing to show.

    local function live_keep(overrides)
        local state = {
            mirror_live = true,
            reset_scope_active = true,
            has_player = true,
            unit_alive = true,
            game_mode_key = Core.KEEP_GAME_MODE,
            requester_available = true,
        }
        for k, v in pairs(overrides or {}) do state[k] = v end
        return state
    end

    H.test("default-refresh respawns only in the live keep", function()
        local action, reason = Core.classify(live_keep())
        H.equal(action, "respawn")
        H.equal(reason, "keep-live")
        H.equal(Core.KEEP_GAME_MODE, "inn",
            "keep detection must key off the vanilla inn game mode")
    end)

    H.test("default-refresh defers in a mission (no forced teleport-respawn)", function()
        for _, key in ipairs({ "adventure", "deus", "weave", "tutorial" }) do
            local action = Core.classify(live_keep({ game_mode_key = key }))
            H.equal(action, "defer", "mission mode " .. key .. " must defer")
        end
        local no_mode = live_keep()
        no_mode.game_mode_key = nil
        local action = Core.classify(no_mode)
        H.equal(action, "defer", "unknown game mode must defer, never respawn")
    end)

    H.test("default-refresh defers when the profile requester is unreachable", function()
        local action, reason = Core.classify(live_keep({ requester_available = false }))
        H.equal(action, "defer")
        H.equal(reason, "no-profile-requester")
    end)

    H.test("default-refresh skips a reset scoped to an inactive career", function()
        -- /reset_modded_loadouts <career> for a career the player is NOT on must
        -- not respawn the active character (refresh only the active career).
        local action, reason = Core.classify(live_keep({ reset_scope_active = false }))
        H.equal(action, "skip")
        H.equal(reason, "reset-career-not-active")
    end)

    H.test("default-refresh skips without a live Adventure mirror or live player", function()
        local action, reason = Core.classify(live_keep({ mirror_live = false }))
        H.equal(action, "skip")
        H.equal(reason, "mirror-not-adventure")
        action = Core.classify(live_keep({ unit_alive = false }))
        H.equal(action, "skip", "no live unit must skip")
        action = Core.classify(live_keep({ has_player = false }))
        H.equal(action, "skip", "no resolved identity must skip")
        action, reason = Core.classify(nil)
        H.equal(action, "skip")
        H.equal(reason, "no-state")
    end)

    H.test("default-refresh receipt matches identities and lists stale slots", function()
        local desired = { slot_melee = "m", slot_ranged = "r", slot_hat = "h" }
        local matched, mismatched = Core.match(desired,
            { slot_melee = "m", slot_ranged = "r", slot_hat = "h" })
        H.truthy(matched, "identical identities must match")
        H.equal(#mismatched, 0)

        matched, mismatched = Core.match(desired,
            { slot_melee = "old", slot_ranged = "r", slot_hat = "old_hat" })
        H.equal(matched, false)
        H.equal(#mismatched, 2)
        H.equal(mismatched[1], "slot_melee")
        H.equal(mismatched[2], "slot_hat")
    end)

    H.test("default-refresh receipt tolerates an empty desired slot", function()
        -- A reseeded row may legitimately hold no hat; an empty-but-correct slot
        -- is not staleness and must not fail the after-receipt.
        local matched = Core.match({ slot_melee = "m" },
            { slot_melee = "m", slot_hat = "whatever_is_live" })
        H.truthy(matched)
        local matched2 = Core.match({}, {})
        H.truthy(matched2, "an empty desired row trivially matches")
    end)

    H.test("default-refresh receipt fails closed on a missing live table", function()
        local matched, mismatched = Core.match({ slot_melee = "m" }, nil)
        H.equal(matched, false)
        H.equal(mismatched[1], "slot_melee")
    end)

    H.test("default-refresh watch budget is bounded and tolerant of bad input", function()
        H.equal(Core.expired(0, 15), false)
        H.equal(Core.expired(15, 15), false, "budget boundary is inclusive-hold")
        H.equal(Core.expired(15.1, 15), true)
        H.equal(Core.expired(nil, 15), false, "non-numeric elapsed must not expire early")
        H.equal(Core.expired(Core.WATCH_BUDGET_SECONDS + 1), true,
            "default budget applies when none is passed")
    end)

    H.test("default-refresh receipt slots cover the observed stale identities", function()
        -- RainReligion's report: stale melee + cosmetic on the lobby character.
        local want = { slot_melee = true, slot_ranged = true, slot_hat = true }
        local seen = {}
        for _, slot in ipairs(Core.RECEIPT_SLOTS) do
            H.truthy(want[slot], "unexpected receipt slot " .. tostring(slot))
            seen[slot] = true
        end
        for slot in pairs(want) do
            H.truthy(seen[slot], "receipt slot missing: " .. slot)
        end
    end)
end
