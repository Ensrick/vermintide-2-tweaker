-- Engine-free coverage for the renamed-clone projectile policy (#1186).
--
-- A projectile re-resolves its own action from `ItemMasterList[item_name]`, and
-- a CWV clone inherits the BASE key as its `name`, so a variant whose template
-- was cloned under a NEW name flies with donor impact/projectile data. Only the
-- javelin family had an arm for that; the Outrider Grenade Launcher's authored
-- 0.65x damage clone never reached its grenade.
--
-- The module under test is the whole decision: which defs are affected, whether
-- a given projectile belongs to one, and what moves onto it. Everything here
-- drives the shipped module directly -- no globals, no source text.
return function(H, repo_root)
    local mod_root = repo_root
        .. "/character_weapon_variants/scripts/mods/character_weapon_variants/"
    local Policy = assert(loadfile(mod_root .. "_cwv_projectile_tunes.lua"))()

    -- Base templates named the way the item master list names them.
    local BASE_TEMPLATE = {
        launcher_base = "donor_launcher_template",
        bow_base = "shared_bow_template",
        melee_base = "donor_melee_template",
    }
    local function base_template_of(base) return BASE_TEMPLATE[base] end

    local DEFS = {
        -- Renamed clone: unreachable from the base lookup, so it needs the arm.
        { item_key = "cwv_fix_launcher", base_weapon = "launcher_base",
          template = "cwv_fix_launcher_template" },
        -- Clone registered under the base's OWN template name: the engine's base
        -- lookup already lands on it, so re-pointing would be a pointless write.
        { item_key = "cwv_fix_bow", base_weapon = "bow_base",
          template = "shared_bow_template" },
        -- No authored template at all.
        { item_key = "cwv_fix_plain", base_weapon = "melee_base" },
        -- Unknown base: nothing to compare against, so never admitted.
        { item_key = "cwv_fix_orphan", base_weapon = "missing_base",
          template = "cwv_fix_orphan_template" },
    }

    local function fresh_weapons()
        local donor_action = {
            speed = 2500,
            impact_data = { damage_profile = "donor_profile" },
            timed_data = { damage_profile = "donor_timed" },
            projectile_info = { id = "donor_projectile" },
            charge_data = { id = "donor_charge" },
        }
        local clone_action = {
            speed = 3500,
            impact_data = { damage_profile = "cwv_fix_launcher_donor_profile" },
            timed_data = { damage_profile = "cwv_fix_launcher_donor_timed" },
            projectile_info = { id = "clone_projectile" },
            charge_data = { id = "clone_charge" },
            chain_hit_settings = { id = "clone_chain" },
        }
        return {
            donor_launcher_template = { actions = { action_one = { default = donor_action } } },
            cwv_fix_launcher_template = { actions = { action_one = { default = clone_action } } },
        }, donor_action, clone_action
    end

    local LOOKUP = { action_name = "action_one", sub_action_name = "default" }

    H.test("#1186 only a RENAMED clone template joins the projectile override map", function()
        local overrides = Policy.renamed_template_defs(DEFS, base_template_of)
        H.equal(overrides.cwv_fix_launcher, "cwv_fix_launcher_template",
            "a clone under a new name is invisible to the base lookup and must be covered")
        H.equal(overrides.cwv_fix_bow, nil,
            "a clone registered under the base's own template name already resolves")
        H.equal(overrides.cwv_fix_plain, nil)
        H.equal(overrides.cwv_fix_orphan, nil,
            "an unknown base cannot be proven to be a rename")
        H.deep_equal(Policy.renamed_template_defs(nil, base_template_of), {})
        H.deep_equal(Policy.renamed_template_defs(DEFS, nil), {})
    end)

    H.test("#1186 resolve returns the clone sub-action for an owned projectile", function()
        local weapons, donor_action, clone_action = fresh_weapons()
        local overrides = Policy.renamed_template_defs(DEFS, base_template_of)
        local action, template = Policy.resolve({
            overrides = overrides,
            variant_key = "cwv_fix_launcher",
            variant_base = "launcher_base",
            item_name = "launcher_base",
            weapons = weapons,
            lookup = LOOKUP,
            base_action = donor_action,
        })
        H.equal(action, clone_action)
        H.equal(template, "cwv_fix_launcher_template")
    end)

    H.test("#1186 resolve declines every shape that is not a proven owned projectile", function()
        local weapons, donor_action = fresh_weapons()
        local overrides = Policy.renamed_template_defs(DEFS, base_template_of)
        local NIL = {}   -- explicit "unset this field": pairs() skips nil values
        local function reason(overlay)
            local args = {
                overrides = overrides,
                variant_key = "cwv_fix_launcher",
                variant_base = "launcher_base",
                item_name = "launcher_base",
                weapons = weapons,
                lookup = LOOKUP,
                base_action = donor_action,
            }
            for k, v in pairs(overlay) do
                if v == NIL then args[k] = nil else args[k] = v end
            end
            local action, why = Policy.resolve(args)
            H.equal(action, nil)
            return why
        end
        H.equal(reason({ variant_key = NIL }), "not_cwv",
            "a native weapon owns no variant key and must keep vanilla data")
        H.equal(reason({ variant_key = "cwv_fix_bow" }), "no_rename")
        -- The projectile came from a DIFFERENT weapon than the one the slot
        -- holds: never re-point a foreign projectile at our clone.
        H.equal(reason({ item_name = "bow_base" }), "base_mismatch")
        H.equal(reason({ weapons = {} }), "template_missing")
        H.equal(reason({ lookup = { action_name = "action_two", sub_action_name = "default" } }),
            "action_missing")
        H.equal(reason({ lookup = NIL }), "action_missing")
        -- Idempotency guard: the engine already handed us our own table.
        H.equal(reason({ base_action = weapons.cwv_fix_launcher_template.actions.action_one.default }),
            "already_clone")
    end)

    H.test("#1186 apply moves the authored tunes onto the projectile", function()
        local _, donor_action, clone_action = fresh_weapons()
        local ids = {
            donor_profile = 11, donor_timed = 12,
            cwv_fix_launcher_donor_profile = 91,
            cwv_fix_launcher_donor_timed = 92,
        }
        local projectile = {
            _current_action = donor_action,
            _impact_data = donor_action.impact_data,
            _impact_damage_profile_id = ids.donor_profile,
            _timed_data = donor_action.timed_data,
            _timed_damage_profile_id = ids.donor_timed,
            projectile_info = donor_action.projectile_info,
            charge_data = donor_action.charge_data,
        }
        local changed = Policy.apply(projectile, clone_action,
            function(name) return ids[name] end)
        H.truthy(changed >= 6, "the whole action identity must move, not just one field")
        H.equal(projectile._current_action, clone_action)
        H.equal(projectile._impact_data, clone_action.impact_data)
        H.equal(projectile._impact_damage_profile_id, 91,
            "the wire damage-profile id must name the variant's cloned profile")
        H.equal(projectile._timed_data, clone_action.timed_data)
        H.equal(projectile._timed_damage_profile_id, 92)
        H.equal(projectile.projectile_info, clone_action.projectile_info)
        H.equal(projectile.charge_data, clone_action.charge_data)
        H.equal(projectile.chain_hit_settings, clone_action.chain_hit_settings)
        H.equal(Policy.apply(projectile, clone_action, function(name) return ids[name] end), 0,
            "a second pass over the same projectile must be a no-op")
    end)

    H.test("#1186 an unresolvable damage-profile id keeps the donor id, never nil", function()
        -- #423: `rpc_attack_hit` carries this number. Writing nil over a working
        -- donor id is strictly worse than keeping it -- the sender-side wire
        -- policy is what substitutes a donor id for an unconfirmed peer.
        local _, donor_action, clone_action = fresh_weapons()
        local projectile = {
            _current_action = donor_action,
            _impact_data = donor_action.impact_data,
            _impact_damage_profile_id = 11,
        }
        Policy.apply(projectile, clone_action, function() return nil end)
        H.equal(projectile._impact_data, clone_action.impact_data)
        H.equal(projectile._impact_damage_profile_id, 11)
        Policy.apply(projectile, clone_action, nil)
        H.equal(projectile._impact_damage_profile_id, 11)
    end)

    H.test("#1186 apply refuses a malformed projectile or action", function()
        local _, _, clone_action = fresh_weapons()
        H.equal(Policy.apply(nil, clone_action, nil), 0)
        H.equal(Policy.apply({}, nil, nil), 0)
        H.equal(Policy.apply("not a table", clone_action, nil), 0)
    end)
end
