-- gt_dev issues 139/384/385 (v0.2.250-dev): aid-errand pin + veto-state
-- classification + below-leash branch instrument.
--
-- Functional half: drives the pure policy seams in _gt_teleport_loop_policy
-- (pin_need_type / pin_should_release / should_log_below_leash) with stub
-- status objects -- the same truth tables the runtime /gt_regression_test
-- checks assert in-game, locked here so a refactor fails offline first.
--
-- Textual half (the #511 relocation target: io is nil in the VMF sandbox, so
-- these SOURCE invariants live in the repo QA gate, not runtime checks):
--   * the #384 veto scan stays side-scoped (side:player_units(), never the
--     follow target) and its predicate keeps ALL disabler states + awaiting
--     assisted respawn;
--   * the pin is armed at every aid-pick return site and consulted before the
--     FIX 13 heal injection;
--   * the #492 bailout carries its reason and the teleport vetoes discriminate
--     no-path (release) from no-progress (hold while pinned);
--   * the #385 instrument logs pre-snap distance with the branch stamp.
return function(H, repo_root)
    local policy = dofile(repo_root
        .. "/general_tweaker_dev/scripts/mods/general_tweaker_dev/_gt_teleport_loop_policy.lua")

    -- Stub status extension: all-false, flip named flags true per case.
    local function st(o)
        o = o or {}
        local function g(k) return function() return o[k] or false end end
        return {
            is_knocked_down               = g("knocked"),
            get_is_ledge_hanging          = g("ledge"),
            is_pulled_up                  = g("pulled"),
            is_hanging_from_hook          = g("hook"),
            is_ready_for_assisted_respawn = g("awaiting"),
        }
    end

    H.test("GT pin need-type classifies the interactable errand states", function()
        H.equal(policy.pin_need_type(st{ knocked = true }, false), "knocked_down")
        H.equal(policy.pin_need_type(st{ ledge = true }, false), "ledge")
        H.equal(policy.pin_need_type(st{ ledge = true, pulled = true }, false), nil)
        H.equal(policy.pin_need_type(st{ hook = true }, false), "hook")
        H.equal(policy.pin_need_type(st{}, true), nil)
        H.equal(policy.pin_need_type(nil, true), nil)
        -- Vanilla priority order (player_bot_base.lua:909-917): knocked_down
        -- outranks ledge/hook when states coincide.
        H.equal(policy.pin_need_type(st{ knocked = true, hook = true }, false), "knocked_down")
        H.equal(policy.pin_need_type(st{ ledge = true, hook = true }, false), "ledge")
    end)

    H.test("GT pin awaiting-rescue relabel rides the FIX 3 gate only", function()
        H.equal(policy.pin_need_type(st{ awaiting = true }, true), "knocked_down")
        H.equal(policy.pin_need_type(st{ awaiting = true }, false), nil)
        -- A knocked ally relabels identically with or without the rescue gate.
        H.equal(policy.pin_need_type(st{ knocked = true }, true), "knocked_down")
    end)

    H.test("GT pin release matrix: recovery and no-path release, no-progress holds", function()
        -- Ally no longer classifies -> release.
        local release, why = policy.pin_should_release(nil, false, nil, false)
        H.equal(release, true)
        H.equal(why, "ally_recovered_or_gone")
        -- Authoritative engine give-up (no-path bail on the pinned ally) -> release.
        release, why = policy.pin_should_release("knocked_down", true, "no-path", true)
        H.equal(release, true)
        H.equal(why, "no_path_bail")
        -- The #384 log gap: a no-progress bail while the ally still classifies
        -- must HOLD (it released the veto into a teleport loop in the field).
        H.equal(policy.pin_should_release("knocked_down", true, "no-progress", true), false)
        -- A bail for a DIFFERENT unit never releases this pin.
        H.equal(policy.pin_should_release("knocked_down", true, "no-path", false), false)
        -- No bail, ally still down -> hold.
        H.equal(policy.pin_should_release("hook", false, nil, false), false)
        -- Defensive: bail with an unstamped reason holds the errand (need_type
        -- stays set, so every distance trigger self-declines at the source).
        H.equal(policy.pin_should_release("knocked_down", true, nil, true), false)
    end)

    H.test("GT below-leash instrument logs only under min(leash, 40) and caps", function()
        H.equal(policy.should_log_below_leash(2.8, 15, 0, 24), true)
        H.equal(policy.should_log_below_leash(15, 15, 0, 24), false)
        -- 20 m is a legitimate tighter-leash trigger at leash 15, an anomaly at leash 40.
        H.equal(policy.should_log_below_leash(20, 15, 0, 24), false)
        H.equal(policy.should_log_below_leash(20, 40, 0, 24), true)
        -- At/above vanilla's 40 m floor the vanilla trigger owns the teleport.
        H.equal(policy.should_log_below_leash(45, 60, 0, 24), false)
        H.equal(policy.should_log_below_leash(39, 60, 0, 24), true)
        -- Session cap silences; nil count treated as zero; malformed fails closed.
        H.equal(policy.should_log_below_leash(2.8, 15, 24, 24), false)
        H.equal(policy.should_log_below_leash(2.8, 15, nil, 24), true)
        H.equal(policy.should_log_below_leash(nil, 15, 0, 24), false)
        H.equal(policy.should_log_below_leash(2.8, nil, 0, 24), false)
        H.truthy(type(policy.BELOW_LEASH_LOG_CAP) == "number" and policy.BELOW_LEASH_LOG_CAP > 0)
    end)

    H.test("GT production wires pin, bail reason, and instrument (source invariants)", function()
        local fixes_path = repo_root
            .. "/general_tweaker_dev/scripts/mods/general_tweaker_dev/_gt_bot_fixes.lua"
        local f = assert(io.open(fixes_path, "rb")); local fixes = f:read("*a"); f:close()
        local owner_path = repo_root
            .. "/general_tweaker_dev/scripts/mods/general_tweaker_dev/_gt_bot_aid_owner.lua"
        local o = assert(io.open(owner_path, "rb")); local owner = o:read("*a"); o:close()

        -- #384 pin: marker + armed at all three aid-pick return sites + held
        -- before the FIX 13 heal injection.
        H.truthy(owner:find("GT_BOT384_AID_ERRAND_PIN_MARKER_v0_2_250", 1, true))
        H.truthy(owner:find("_gt384_arm_pin(blackboard, ally, need_type)", 1, true))
        H.truthy(owner:find('_gt384_arm_pin(blackboard, best_unit, "knocked_down")', 1, true))
        H.truthy(owner:find("_gt384_arm_pin(blackboard, _fr_unit, _fr_need)", 1, true))
        H.truthy(owner:find("_gt384_hold_pin(blackboard, self_pos, _gt_rescue_awaiting_active)", 1, true))

        -- #492 bail reason is stamped and both teleport vetoes discriminate on
        -- it (no-path releases; no-progress holds while the pin is live).
        H.truthy(owner:find("blackboard._gt492_bailout_reason = reason", 1, true))
        H.truthy(fixes:find('blackboard._gt492_bailout_reason ~= "no-progress"', 1, true))
        H.truthy(fixes:find("not _gt384_pin_live(blackboard)", 1, true))

        -- #384 veto scan stays side-scoped with the FULL predicate: roster from
        -- side:player_units() (bots + awaiting included; PLAYER_UNITS is
        -- human-only and drops awaiting units, side_manager.lua:338-340).
        H.truthy(owner:find("local punits = side and side.player_units and side:player_units()", 1, true))
        local pred_from = owner:find("local function _gt_status_needs_aid_or_rescue(st)", 1, true)
        H.truthy(pred_from)
        local pred_to = owner:find("end", pred_from, true)
        H.truthy(pred_to)
        local pred_body = owner:sub(pred_from, pred_to)
        for _, clause in ipairs({
            "is_knocked_down", "is_hanging_from_hook", "get_is_ledge_hanging",
            "is_pulled_up", "is_pounced_down", "is_grabbed_by_pack_master",
            "is_grabbed_by_tentacle", "is_grabbed_by_chaos_spawn", "is_in_vortex",
            "is_grabbed_by_corruptor", "is_ready_for_assisted_respawn",
        }) do
            H.truthy(pred_body:find(clause, 1, true))
        end

        -- #385 instrument: marker + pre-snap distance capture + the capped line.
        H.truthy(fixes:find("GT_BOT385_BELOW_LEASH_INSTRUMENT_MARKER_v0_2_250", 1, true))
        H.truthy(fixes:find("mod._gt385_no_path_distance(blackboard) or nil", 1, true))
        H.truthy(fixes:find("[gt:385] below-leash TELEPORT", 1, true))
        H.truthy(fixes:find("policy.should_log_below_leash(p385_pre_dist, leash_m,", 1, true))
    end)
end
