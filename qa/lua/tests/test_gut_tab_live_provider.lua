return function(H, repo_root)
    local path = repo_root
        .. "/gui_tweaker_dev/scripts/mods/gui_tweaker_dev/_gut_tab_property_policy.lua"
    local Policy = assert(loadfile(path))()

    H.test("GUT #245 trait refresh mirrors the property identity gates", function()
        local changed, traits, reason = Policy.refresh_traits(
            { key = "weapon", traits = { "old_trait" } },
            { key = "weapon", traits = { "new_trait" } })
        H.truthy(changed)
        H.equal(reason, "changed")
        H.equal(traits[1], "new_trait")

        changed, _, reason = Policy.refresh_traits(
            { key = "weapon", traits = { "same" } },
            { key = "weapon", traits = { "same" } })
        H.equal(changed, false)
        H.equal(reason, "unchanged")

        changed, _, reason = Policy.refresh_traits({ key = "a" }, { key = "b" })
        H.equal(changed, false)
        H.equal(reason, "identity_mismatch")

        changed, _, reason = Policy.refresh_traits(
            { key = "a", backend_id = "one", traits = { "x" } },
            { key = "a", backend_id = "two", traits = { "y" } })
        H.equal(changed, false)
        H.equal(reason, "instance_mismatch")

        -- a reforge can clear traits entirely: live nil traits vs cached one
        changed, traits, reason = Policy.refresh_traits(
            { key = "weapon", traits = { "old_trait" } },
            { key = "weapon" })
        H.truthy(changed)
        H.equal(#traits, 0)
    end)

    H.test("GUT #246 skin fallback chain: exact instance, synced identity, preserve", function()
        local exists = function(name) return name ~= "missing_template" end

        -- exact live instance wins over synced evidence
        local skin, source, changed = Policy.resolve_skin(
            true, "live_skin", true, "synced_skin", nil, exists)
        H.equal(skin, "live_skin")
        H.equal(source, "live_backend")
        H.truthy(changed)

        -- synced (wearer, slot) identity used when no exact instance (remote row)
        skin, source, changed = Policy.resolve_skin(
            false, nil, true, "synced_skin", nil, exists)
        H.equal(skin, "synced_skin")
        H.equal(source, "synced_cosmetic")
        H.truthy(changed)

        -- no evidence at all: preserve the vanilla reconstruction
        skin, source, changed = Policy.resolve_skin(
            false, nil, false, nil, "vanilla_skin", exists)
        H.equal(skin, "vanilla_skin")
        H.equal(source, "preserved")
        H.equal(changed, false)

        -- evidence says NO illusion: clear a stale decoration
        skin, source, changed = Policy.resolve_skin(
            true, nil, false, nil, "stale_decoration", exists)
        H.equal(skin, nil)
        H.equal(source, "live_backend")
        H.truthy(changed)

        -- unresolvable template never reaches the row (panel icon pass derefs
        -- WeaponSkins.skins[skin] unguarded)
        skin, source, changed = Policy.resolve_skin(
            false, nil, true, "missing_template", "kept", exists)
        H.equal(skin, "kept")
        H.equal(source, "unresolved_template")
        H.equal(changed, false)

        -- already-correct skin reports unchanged
        skin, source, changed = Policy.resolve_skin(
            true, "live_skin", false, nil, "live_skin", exists)
        H.equal(skin, "live_skin")
        H.equal(changed, false)
    end)

    H.test("GUT #245/#246 wire-safety filters drop only unresolvable names", function()
        local props, dropped = Policy.wire_safe_properties(
            { good = 0.1, bad = 0.2 }, { good = 1 })
        H.equal(props.good, 0.1)
        H.equal(props.bad, nil)
        H.equal(dropped, 1)

        -- no lookup available (offline/boot): filter nothing
        props, dropped = Policy.wire_safe_properties({ good = 0.1 }, nil)
        H.equal(props.good, 0.1)
        H.equal(dropped, 0)

        local traits, tdropped = Policy.wire_safe_traits(
            { "good_trait", "bad_trait" }, { good_trait = 1 })
        H.equal(#traits, 1)
        H.equal(traits[1], "good_trait")
        H.equal(tdropped, 1)

        traits, tdropped = Policy.wire_safe_traits({ "good_trait" }, nil)
        H.equal(traits[1], "good_trait")
        H.equal(tdropped, 0)
    end)

    H.test("GUT #533 collectible rows suppressed only inside the deus mechanism", function()
        H.truthy(Policy.suppress_adventure_loot_rows("deus"))
        H.equal(Policy.suppress_adventure_loot_rows("adventure"), false)
        H.equal(Policy.suppress_adventure_loot_rows("versus"), false)
        H.equal(Policy.suppress_adventure_loot_rows(nil), false)
    end)

    H.test("GUT provider owns both panel hooks and stays bounded", function()
        local runtime_path = repo_root
            .. "/gui_tweaker_dev/scripts/mods/gui_tweaker_dev/_gut_tab_property_refresh.lua"
        local file = assert(io.open(runtime_path, "rb"))
        local source = file:read("*a")
        file:close()
        -- the ONE dynamic-update hook + the #533 mission-row hook
        H.truthy(source:find('"_update_dynamic_widget_information"', 1, true) ~= nil)
        H.truthy(source:find('"_setup_mission_data"', 1, true) ~= nil)
        -- active-only + interval + log bounds survive (shape shared with the
        -- original #245 patch this provider absorbed)
        H.truthy(source:find('self._active == true', 1, true) ~= nil)
        H.truthy(source:find('now + Policy.INTERVAL', 1, true) ~= nil)
        H.truthy(source:find('log_count < Policy.MAX_LOGS', 1, true) ~= nil)
        -- skin writes are template-guarded and evidence comes from the two
        -- sanctioned sources only
        H.truthy(source:find('skin_template_exists', 1, true) ~= nil)
        H.truthy(source:find('get_cosmetic_slot', 1, true) ~= nil)
        -- the #250 talent repair still runs after vanilla populated the widgets
        H.truthy(source:find('TalentRefresh.refresh(self)', 1, true) ~= nil)
        -- display-only contract: the provider must never CALL the loadout
        -- resync (comment mentions are fine; the call form is forbidden -
        -- re-serializing a modded item key over the vanilla RPC is the
        -- cross-peer wire-safety hazard class)
        H.truthy(source:find('LoadoutUtils.sync_loadout_slot(', 1, true) == nil)
    end)
end
