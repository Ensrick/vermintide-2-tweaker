-- Dedicated engine-free owner for issue #786 combat-style remote re-wield
-- convergence, descriptor retention, retry bounds, and production wiring.
-- Extracted from test_cwv_husk_adapter.lua under issue #2; behavior and
-- assertion order are intentionally unchanged.
return function(H, repo_root)
    local mod_root = repo_root
        .. "/character_weapon_variants/scripts/mods/character_weapon_variants/"
    local main_path = mod_root .. "character_weapon_variants.lua"

    local function read(path)
        local file = assert(io.open(path, "rb"))
        local source = file:read("*a")
        file:close()
        return source
    end

    -- ====================================================================
    -- Issue 786 -- Combat Style switch left the OTHER player's husk stale.
    -- Three legs, two fixed here:
    --   A. the style receiver re-wielded the husk INLINE (bypassing the #1145
    --      coalescer's mid-destroy guard and newest-wins merge) and graded the
    --      result with `right_live or left_live` -- an OR of setter-ish state
    --      (BUG_CLASSES 58). A husk still wearing the PRE-SWITCH weapon, or a
    --      shield style missing its off-hand, reported refreshed=true.
    --   B. a style switch published five scalars and NEVER republished item
    --      identity, so the deferred re-wield resolved the last published
    --      identity. The style axis now rides the delivering identity payload
    --      (the proven #474 musket_mode shape) and is applied BEFORE the
    --      changed-dedupe gate, because a style toggle leaves the identity
    --      signature byte-identical.
    -- ====================================================================
    local Policy = assert(loadfile(mod_root .. "_cwv_combat_styles.lua"))()
    local Rewield = assert(loadfile(mod_root .. "_cwv_style_rewield.lua"))()
    local coalescer_path = mod_root .. "_cwv_rewield_coalescer.lua"
    local styles_path = mod_root .. "_cwv_combat_styles.lua"
    local rewield_path = mod_root .. "_cwv_style_rewield.lua"

    -- One remote wearer whose husk really re-wields: `wield` re-populates the
    -- 3P hand units from `hands`, so a test can make the rebuild come back with
    -- one hand, both hands, or the wrong template.
    local function husk_fixture(opts)
        opts = opts or {}
        local slot_name = opts.slot or "slot_melee"
        local hands = { right = opts.right ~= false, left = opts.left == true }
        local wields = {}
        local equipment = {
            slots = { [slot_name] = { item_data = { name = opts.item_key or "es_deus_01" } } },
            wielded_slot = slot_name,
        }
        local inventory = { _equipment = equipment, wielded_slot = slot_name }
        inventory.wield = function(_, slot)
            wields[#wields + 1] = slot
            if opts.on_wield then opts.on_wield(equipment, hands) end
            equipment.right_hand_wielded_unit_3p = hands.right and { "r" } or nil
            equipment.left_hand_wielded_unit_3p = hands.left and { "l" } or nil
        end
        local unit = { "wearer" }
        return {
            slot = slot_name, hands = hands, wields = wields,
            equipment = equipment, inventory = inventory, unit = unit,
        }
    end

    -- Full A+B wiring on real modules: the shipped coalescer, the shipped
    -- combat-style runtime and the shipped verdict policy.
    local function style_fixture(opts)
        opts = opts or {}
        local husk = husk_fixture(opts)
        local Coalescer = assert(loadfile(coalescer_path))()
        local lines, sent, settings = {}, {}, {}
        local unit_api = { alive = function() return true end }
        local script_unit = {
            extension = function() return husk.inventory end,
            has_extension = function() return husk.inventory end,
        }
        local managers = { player = {
            player_from_peer_id = function() return { player_unit = husk.unit } end,
        } }
        local deps = {
            policy = Policy, coalescer = Coalescer, managers = managers,
            unit_api = unit_api, script_unit = script_unit, probe_state = {},
            printf = function(fmt, ...) lines[#lines + 1] = string.format(fmt, ...) end,
            peer_player = function() return { player_unit = husk.unit }, "test" end,
            item_key = function(item_data) return item_data and item_data.name end,
            effective_template = function()
                if opts.observed_template ~= nil then return opts.observed_template end
                return husk.equipment.slots[husk.slot].item_data.observed_template
            end,
			observed_unit_name = function(unit, owner, slot_name, hand)
				if owner ~= husk.unit or slot_name ~= husk.slot then return nil end
				if hand == "right"
						and unit == husk.equipment.right_hand_wielded_unit_3p then
					return opts.observed_right_unit
				end
				if hand == "left"
						and unit == husk.equipment.left_hand_wielded_unit_3p then
					return opts.observed_left_unit
				end
				return nil
			end,
            style_resource_resident = opts.style_resource_resident,
			descriptor_expectation = opts.descriptor_expectation,
        }
        local mod = {
            get = function(_, key) return settings[key] end,
            set = function(_, key, value) settings[key] = value end,
            network_send = function(_, channel, recipient, ...)
                sent[#sent + 1] = { channel = channel, recipient = recipient, n = select("#", ...) }
                return true
            end,
        }
        local runtime = Policy.install(mod, {
            rewield = Rewield,
            rebuild_remote = function(peer_id, slot_name, family_id, style_id, on_verdict,
					descriptor)
                return Rewield.queue_rebuild(deps, peer_id, slot_name,
					family_id, style_id, on_verdict, descriptor)
            end,
        })
        local saved_printf = _G.printf
        _G.printf = deps.printf
        return {
            husk = husk, runtime = runtime, coalescer = Coalescer, deps = deps,
            lines = lines, sent = sent,
            drain = function() return Coalescer.drain({ silent = true,
                unit_api = unit_api, script_unit = script_unit }) end,
            release = function() _G.printf = saved_printf end,
        }
    end

    local function with_fixture(opts, body)
        local fx = style_fixture(opts)
        local ok, err = pcall(body, fx)
        fx.release()
        if not ok then error(err, 0) end
    end

    H.test("#786 A2 verdict is AND-semantics over the AUTHORED expectation", function()
        local expected = Rewield.expectation(Policy, "spear_shield", "elven", "es_deus_01")
        H.equal(expected.template, Policy.ELVEN_SPEAR_SHIELD_TEMPLATE)
        H.equal(expected.left, true, "an authored shield family must expect BOTH hands")
        local base = { wielded = true, item_key = "es_deus_01",
            template = Policy.ELVEN_SPEAR_SHIELD_TEMPLATE,
            right_live = true, left_live = true }
        H.equal(Rewield.verdict(expected, base), "ok")
        H.equal(Rewield.succeeded("ok"), true)
        -- Exactly what the retired `right_live or left_live` predicate passed.
        local one_hand = { wielded = true, item_key = "es_deus_01",
            template = Policy.ELVEN_SPEAR_SHIELD_TEMPLATE,
            right_live = true, left_live = false }
        local status, detail = Rewield.verdict(expected, one_hand)
        H.equal(status, "partial", "a missing off-hand is NOT success")
        H.truthy(detail:find("missing=left", 1, true), "detail must name the hand")
        H.equal(Rewield.succeeded(status), false, "partial application is failure")
        local wrong = Rewield.verdict(expected, { wielded = true, item_key = "es_deus_01",
            template = Policy.EMPIRE_SPEAR_SHIELD_TEMPLATE,
            right_live = true, left_live = true })
        H.equal(wrong, "wrong-template", "both hands live is not proof of the style")
        H.equal(Rewield.verdict(expected, { wielded = true, item_key = "es_2h_sword",
            template = Policy.ELVEN_SPEAR_SHIELD_TEMPLATE,
            right_live = true, left_live = true }), "wrong-template",
            "a husk still wearing the pre-switch item must fail")
        H.equal(Rewield.verdict(expected, { wielded = false,
            right_live = true, left_live = true }), "failed")
        H.equal(Rewield.verdict(nil, base), "failed")
    end)

    H.test("#786 A2 expectation comes from the authored catalogue, never the husk", function()
        H.equal(Rewield.expectation(Policy, "greatsword", "kerillian", "wh_2h_sword").template,
            Policy.KERILLIAN_TEMPLATE)
        -- An authored RECEIVER override is ground truth too.
        H.equal(Rewield.expectation(Policy, "greatsword", "bretonnian", "wh_2h_sword").template,
            Policy.SALTZ_BRETONNIAN_TEMPLATE)
        H.equal(Rewield.expectation(Policy, "greatsword", "kerillian", "es_2h_sword").left,
            false, "a two-hander must not demand an off-hand unit")
        H.equal(select(2, Rewield.expectation(Policy, "greatsword", "kerillian", "es_deus_01")),
            "item family mismatch")
        H.equal(select(2, Rewield.expectation(Policy, "greatsword", "kerillian", nil)),
            "slot not ready")
        H.equal(select(2, Rewield.expectation(Policy, "greatsword", "no_such_style", "es_2h_sword")),
            "style not authored")
        H.equal(select(2, Rewield.expectation(Policy, "greatsword", "kerillian", "fix_base")),
            "item not a style member")
    end)

    H.test("#786 A1 the rebuild goes to the coalescer and the verdict waits for the drain", function()
        with_fixture({ item_key = "es_deus_01", left = true,
                observed_template = Policy.ELVEN_SPEAR_SHIELD_TEMPLATE }, function(fx)
            local verdicts = {}
            local queued, why = Rewield.queue_rebuild(fx.deps, "peerA", "slot_melee",
                "spear_shield", "elven", function(status, detail)
                    verdicts[#verdicts + 1] = { status = status, detail = detail }
                end)
            H.equal(queued, true)
            H.equal(why, "queued")
            H.equal(#fx.husk.wields, 0, "queue_rebuild must NOT wield inline")
            H.equal(#verdicts, 0, "no synchronous verdict may be manufactured")
            H.equal(fx.coalescer.depth(), 1, "the request must sit in the coalescer queue")
            local executed = fx.drain()
            H.equal(executed, 1)
            H.deep_equal(fx.husk.wields, { "slot_melee" }, "the drain owns the wield")
            H.equal(#verdicts, 1, "the verdict arrives from inside the drain")
            H.equal(verdicts[1].status, "ok")
            H.truthy(table.concat(fx.lines, "\n"):find("[cwv:786] rebuild target", 1, true))
        end)
    end)

    H.test("#786 A1/A3 an unready husk never queues and stays retryable", function()
        with_fixture({}, function(fx)
            fx.husk.inventory.wielded_slot = "slot_ranged"
            fx.husk.equipment.wielded_slot = "slot_ranged"
            local queued, reason = Rewield.queue_rebuild(fx.deps, "peerA", "slot_melee",
                "spear_shield", "elven", function() end)
            H.equal(queued, false)
            H.equal(reason, "slot not wielded")
            H.equal(fx.coalescer.depth(), 0)
            H.equal(Policy.remote_refresh_retryable("slot not ready"), true)
            H.equal(Policy.remote_refresh_retryable("slot not wielded"), false)
        end)
    end)

    H.test("#786 A3 one ledger: retry on partial, stop on success, stop at the cap", function()
        with_fixture({ item_key = "es_deus_01", left = false,
                observed_template = Policy.ELVEN_SPEAR_SHIELD_TEMPLATE }, function(fx)
            fx.runtime:accept_style_edge("peerA", "slot_melee", "spear_shield",
                "elven", "identity")
            H.equal(fx.runtime:pending_remote_refresh_count(), 1)
            fx.drain()                       -- shield style rebuilt without its off-hand
            fx.runtime:step(0)               -- consume the partial verdict
            H.equal(fx.runtime:pending_remote_refresh_count(), 1,
                "a partial verdict must stay in the ledger, not terminate")
            local joined_lines = table.concat(fx.lines, "\n")
            H.truthy(joined_lines:find("[cwv:786] verdict partial", 1, true))
            -- The off-hand shows up: the very next attempt must settle the ledger.
            fx.husk.hands.left = true
            fx.runtime:step(Policy.REMOTE_REFRESH_INTERVAL)   -- re-enqueue
            fx.drain()
            local completed = fx.runtime:step(0)
            H.equal(completed, 1)
            H.equal(fx.runtime:pending_remote_refresh_count(), 0, "success stops the ledger")
            H.truthy(table.concat(fx.lines, "\n"):find("[cwv:786] verdict ok", 1, true))
        end)
        -- Cap: a husk that never comes back with its off-hand must terminate.
        with_fixture({ item_key = "es_deus_01", left = false,
                observed_template = Policy.ELVEN_SPEAR_SHIELD_TEMPLATE }, function(fx)
            fx.runtime:accept_style_edge("peerA", "slot_melee", "spear_shield",
                "elven", "identity")
            -- Two ticks per attempt: one consumes the failing verdict and re-arms,
            -- the next re-enqueues. The cap must still be reached exactly once.
            local expired = 0
            for _ = 1, Policy.MAX_REMOTE_REFRESH_ATTEMPTS * 3 do
                fx.drain()
                local _, gone = fx.runtime:step(Policy.REMOTE_REFRESH_INTERVAL)
                expired = expired + gone
            end
            H.equal(expired, 1, "the ledger must expire exactly once at the cap")
            H.equal(fx.runtime:pending_remote_refresh_count(), 0)
            H.truthy(table.concat(fx.lines, "\n"):find("terminal=true", 1, true))
        end)
        -- A style change under a pending entry retires it; it never re-wields
        -- toward the style the wearer already left.
        with_fixture({ item_key = "es_deus_01", left = false,
                observed_template = Policy.ELVEN_SPEAR_SHIELD_TEMPLATE }, function(fx)
            fx.runtime:accept_style_edge("peerA", "slot_melee", "spear_shield",
                "elven", "identity")
            fx.drain()
            fx.runtime:accept_style_edge("peerA", "slot_melee", "spear_shield",
                "empire", "identity")
            fx.runtime:step(Policy.REMOTE_REFRESH_INTERVAL)
            H.equal(fx.runtime:pending_remote_refresh_count(), 1,
                "only the newest style edge may own the ledger")
        end)
    end)

    H.test("#786 B5 both arrival orders and duplicates converge on ONE re-wield", function()
        -- style channel first, identity second.
        with_fixture({ item_key = "es_deus_01", left = true,
                observed_template = Policy.ELVEN_SPEAR_SHIELD_TEMPLATE }, function(fx)
            fx.runtime:accept_style_edge("peerA", "slot_melee", "spear_shield",
                "elven", "style_channel")
            H.equal(fx.coalescer.depth(), 0,
                "the style channel must not fire its own unguarded rebuild")
            local owned = fx.runtime:accept_style_edge("peerA", "slot_melee",
                "spear_shield", "elven", "identity")
            H.equal(owned, true, "the identity path owns the rebuild for this edge")
            H.equal(fx.coalescer.depth(), 1)
            H.equal(fx.drain(), 1)
            H.deep_equal(fx.husk.wields, { "slot_melee" })
        end)
        -- identity first, style channel second.
        with_fixture({ item_key = "es_deus_01", left = true,
                observed_template = Policy.ELVEN_SPEAR_SHIELD_TEMPLATE }, function(fx)
            H.equal(fx.runtime:accept_style_edge("peerA", "slot_melee",
                "spear_shield", "elven", "identity"), true)
            H.equal(fx.runtime:accept_style_edge("peerA", "slot_melee",
                "spear_shield", "elven", "style_channel"), false,
                "a duplicate token must not re-arm anything")
            H.equal(fx.coalescer.depth(), 1, "still exactly one queued re-wield")
            fx.drain()
            H.deep_equal(fx.husk.wields, { "slot_melee" })
        end)
        -- duplicate deliveries on either channel.
        with_fixture({ item_key = "es_deus_01", left = true,
                observed_template = Policy.ELVEN_SPEAR_SHIELD_TEMPLATE }, function(fx)
            fx.runtime:accept_style_edge("peerA", "slot_melee", "spear_shield", "elven", "identity")
            fx.runtime:accept_style_edge("peerA", "slot_melee", "spear_shield", "elven", "identity")
            fx.runtime:accept_style_edge("peerA", "slot_melee", "spear_shield", "elven", "style_channel")
            H.equal(fx.coalescer.depth(), 1)
            fx.drain()
            H.deep_equal(fx.husk.wields, { "slot_melee" },
                "duplicates must collapse to exactly one re-wield")
            H.equal(fx.runtime:pending_remote_refresh_count(), 1)
        end)
    end)

	H.test("#660 migrated style identity retains descriptor across both arrival orders", function()
		local function descriptor(fingerprint)
			return {
				provider = "cwv_style", style_family = "greatsword",
				style_id = "bretonnian", fingerprint = fingerprint,
				base_item_key = "es_2h_sword",
				effective_template = "descriptor_bretonnian_template",
			}
		end
		local function expected(value)
			return {
				family_id = value.style_family, style_id = value.style_id,
				item_key = value.base_item_key,
				template = value.effective_template,
				right = true, left = false, fingerprint = value.fingerprint,
				right_unit = "units/weapons/player/greatsword_02_3p",
			}
		end

		-- We deliberately use a template name absent from the policy catalogue.
		-- A green verdict therefore proves the descriptor, not a re-derived row,
		-- supplied the independent postcondition.
		with_fixture({ item_key = "es_2h_sword", left = false,
				observed_template = "descriptor_bretonnian_template",
				observed_right_unit = "units/weapons/player/greatsword_02_3p",
				descriptor_expectation = expected }, function(fx)
			fx.runtime:accept_style_edge("peerA", "slot_melee", "greatsword",
				"bretonnian", "style_channel")
			local first = descriptor("fp-one")
			H.equal(fx.runtime:accept_style_edge("peerA", "slot_melee", "greatsword",
				"bretonnian", "identity", first), true)
			H.equal(fx.runtime.remote.peerA.slot_melee.descriptor, first)
			H.equal(fx.runtime:accept_style_edge("peerA", "slot_melee", "greatsword",
				"bretonnian", "style_channel"), false)
			H.equal(fx.runtime.remote.peerA.slot_melee.descriptor, first,
				"a late style channel cannot erase identity-owned appearance")
			H.equal(fx.coalescer.depth(), 1)
			fx.drain()
			local completed = fx.runtime:step(0)
			H.equal(completed, 1)

			local second = descriptor("fp-two")
			H.equal(fx.runtime:accept_style_edge("peerA", "slot_melee", "greatsword",
				"bretonnian", "identity", second), true,
				"same style with a new appearance fingerprint is a real edge")
			H.equal(fx.runtime.remote.peerA.slot_melee.descriptor, second)
			H.equal(fx.coalescer.depth(), 1)
		end)

		with_fixture({ item_key = "es_2h_sword", left = false,
				observed_template = "descriptor_bretonnian_template",
				observed_right_unit = "units/weapons/player/greatsword_02_3p",
				descriptor_expectation = expected }, function(fx)
			local valid = descriptor("fp-valid")
			H.equal(fx.runtime:accept_style_edge("peerA", "slot_melee", "greatsword",
				"bretonnian", "identity", valid), true)
			local foreign = descriptor("fp-foreign")
			foreign.style_family = "greathammer"
			H.equal(fx.runtime:accept_style_edge("peerA", "slot_melee", "greatsword",
				"bretonnian", "identity", foreign), false)
			H.equal(fx.runtime.remote.peerA.slot_melee.descriptor, valid,
				"tampered descriptor input must not replace accepted state")
		end)

		with_fixture({ item_key = "es_2h_sword", left = false,
				observed_template = "descriptor_bretonnian_template",
				observed_right_unit = "units/weapons/player/greatsword_01_3p",
				descriptor_expectation = expected }, function(fx)
			H.equal(fx.runtime:accept_style_edge("peerA", "slot_melee", "greatsword",
				"bretonnian", "identity", descriptor("fp-wrong-unit")), true)
			fx.drain()
			local completed = fx.runtime:step(0)
			H.equal(completed, 0,
				"a live vanilla hand cannot satisfy the exact descriptor")
			H.equal(fx.runtime:pending_remote_refresh_count(), 1)
			H.truthy(table.concat(fx.lines, "\n"):find("wrong-unit=right", 1, true))
		end)
	end)

    H.test("#786 B4 a style-only peer still recovers through the bounded fallback", function()
        with_fixture({ item_key = "es_deus_01", left = true,
                observed_template = Policy.ELVEN_SPEAR_SHIELD_TEMPLATE }, function(fx)
            fx.runtime:accept_style_edge("peerA", "slot_melee", "spear_shield",
                "elven", "style_channel")
            fx.runtime:step(0)
            H.equal(fx.coalescer.depth(), 0, "the grace window has not elapsed")
            fx.runtime:step(Policy.STYLE_IDENTITY_GRACE)
            H.equal(fx.coalescer.depth(), 1,
                "no identity rider ever arrived: the style channel must recover")
            fx.drain()
            H.deep_equal(fx.husk.wields, { "slot_melee" })
            H.truthy(table.concat(fx.lines, "\n"):find("style_channel_fallback", 1, true))
        end)
    end)

    H.test("#786 B1 the style rider is one compact authored-closed field", function()
        H.equal(Policy.encode_style_rider("spear_shield", "elven"), "spear_shield:elven")
        H.equal(Policy.encode_style_rider("spear_shield", "no_such_style"), nil)
        H.equal(Policy.encode_style_rider("no_such_family", "elven"), nil)
        H.equal(Policy.encode_style_rider(nil, "elven"), nil)
        local family_id, style_id = Policy.decode_style_rider("greathammer:warrior_priest")
        H.equal(family_id, "greathammer")
        H.equal(style_id, "warrior_priest")
        H.equal(Policy.decode_style_rider("greathammer:not_a_style"), nil)
        H.equal(Policy.decode_style_rider("greathammer"), nil)
        H.equal(Policy.decode_style_rider(""), nil)
        H.equal(Policy.decode_style_rider(nil), nil)
        H.equal(Policy.decode_style_rider(string.rep("a", Policy.STYLE_RIDER_MAX + 1)), nil)
        -- Worst authored pair, and its cost against VMF's 500-char RPC cap.
        local worst = 0
        for family_id_key, family in pairs(Policy.FAMILIES) do
            for style_key in pairs(family.styles) do
                local rider = Policy.encode_style_rider(family_id_key, style_key)
                worst = math.max(worst, #('"style":"' .. rider .. '",'))
            end
        end
        H.equal(worst, 37, "worst-case style rider JSON must stay a bounded 37 chars")
    end)

    H.test("#786 stage C residency probe observes without acquiring or gating", function()
        local asked = {}
        with_fixture({ item_key = "es_deus_01", left = true,
                observed_template = Policy.ELVEN_SPEAR_SHIELD_TEMPLATE,
                style_resource_resident = function(path)
                    asked[#asked + 1] = path
                    return false
                end }, function(fx)
            Rewield.queue_rebuild(fx.deps, "peerA", "slot_melee", "spear_shield",
                "elven", function() end)
            H.equal(#asked, 1, "the probe reads residency exactly once per edge")
            H.equal(asked[1], Policy.FAMILIES.spear_shield.styles.elven.resource)
            local all = table.concat(fx.lines, "\n")
            H.truthy(all:find("[cwv:786] style residency family=spear_shield style=elven", 1, true))
            H.truthy(all:find("resident=false", 1, true))
            H.equal(fx.coalescer.depth(), 1,
                "an absent resource must NOT gate the rebuild (observation only)")
            -- Bounded: the same triple never logs twice.
            Rewield.queue_rebuild(fx.deps, "peerA", "slot_melee", "spear_shield",
                "elven", function() end)
            H.equal(#asked, 1)
        end)
    end)

    H.test("#786 entry + module wiring anchors", function()
        local main = read(main_path)
            .. read(repo_root .. "/character_weapon_variants/scripts/mods/character_weapon_variants/_cwv_item_identity_transport_owner.lua")
        local styles = read(styles_path)
        local rewield_source = read(rewield_path)
        local coalescer_source = read(coalescer_path)
        for _, marker in ipairs({
            -- A1: the entry adapter delegates; it no longer wields inline.
            "return _om.style_rewield.queue_rebuild(_style_rewield_deps, peer_id,",
            "coalescer = mod._cwv_rewield",
            -- B1: the style axis is stamped on the delivering identity payload.
            "_om.combat_styles.local_style_rider",
            "if ok_style and rider then payload.style = rider end",
            -- B3: applied BEFORE the changed-dedupe gate.
            "_om.combat_style_policy.decode_style_rider(payload.style)",
            "sender_peer_id, payload.slot, fam, sid, \"identity\",",
            "== _om.combat_style_appearance.PROVIDER and descriptor or nil)",
            "if not style_owned then",
        }) do
            H.truthy(main:find(marker, 1, true), "missing entry #786 anchor: " .. marker)
        end
        local identity_at = assert(main:find("_om.combat_style_policy.decode_style_rider(payload.style)", 1, true))
        local gate = main:find("if not changed then return end", identity_at, true)
        H.truthy(gate, "the identity changed-dedupe gate must still exist")
        H.truthy(identity_at < gate,
            "the style axis must be applied BEFORE the changed-dedupe gate (#474 precedent)")
        for _, marker in ipairs({
            "function runtime:accept_style_edge(peer_id, slot_name, family_id, style_id, source,",
			"descriptor = state.descriptor",
            "pcall(deps.send_identity_slots, equipment.slots, \"combat_style\", true)",
            "off_hand = true,",
            "M.STYLE_IDENTITY_GRACE",
        }) do
            H.truthy(styles:find(marker, 1, true), "missing combat-style #786 anchor: " .. marker)
        end
        -- The retired OR predicate must not come back in live code. It survives
        -- only in the module's header post-mortem, above the first function.
        H.equal(main:find("right_live or left_live", 1, true), nil)
        local first_fn = rewield_source:find("\nlocal function ", 1, true)
        H.truthy(first_fn)
        H.equal(rewield_source:find("right_live or left_live", first_fn, true), nil,
            "AND-semantics only: no OR of hand liveness in live code")
        H.truthy(rewield_source:find(
            "if expected.left == true and observed.left_live ~= true then", 1, true),
            "the off-hand must be asserted independently")
        H.truthy(coalescer_source:find("pcall(on_verify, unit, inventory, slot, wield_error)", 1, true),
            "the coalescer must own the post-drain verification callback")
    end)
end
