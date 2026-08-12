return function(H, repo_root)
    local function read(relative_path)
        local file = assert(io.open(repo_root .. "/" .. relative_path, "rb"))
        local source = file:read("*a")
        file:close()
        return source
    end

    local function occurrences(haystack, needle)
        local count, offset = 0, 1
        while true do
            local at = haystack:find(needle, offset, true)
            if not at then return count end
            count = count + 1
            offset = at + #needle
        end
    end

    local entry = read(
        "cosmetics_tweaker/scripts/mods/cosmetics_tweaker/cosmetics_tweaker.lua")
    local module_path = "cosmetics_tweaker/scripts/mods/cosmetics_tweaker/"
        .. "_cos_la_replay_runtime.lua"
    local source = read(module_path)
    local glow_transport = read(
        "cosmetics_tweaker/scripts/mods/cosmetics_tweaker/"
        .. "_cos_glow_transport.lua")
    local offhand_picker = read(
        "cosmetics_tweaker/scripts/mods/cosmetics_tweaker/"
        .. "_cos_offhand_picker.lua")
    local preview_runtime = read(
        "cosmetics_tweaker/scripts/mods/cosmetics_tweaker/"
        .. "_cos_preview_runtime.lua")
    local news_feed_safety = read(
        "cosmetics_tweaker/scripts/mods/cosmetics_tweaker/"
        .. "_cos_news_feed_safety.lua")
    -- #1159: the HeroWindowItemCustomization view lifecycle owner joined this
    -- census when its three hooks (one mod:hook, two mod:hook_safe) moved out of
    -- the entry. The whole point of the census is that the extracted family's
    -- TOTAL registration count cannot drift, so a new owner is added here rather
    -- than the expected totals being lowered.
    local view_lifecycle = read(
        "cosmetics_tweaker/scripts/mods/cosmetics_tweaker/"
        .. "_cos_customization_view_lifecycle.lua")
    -- #1159: the attachment-slot LA spawn/sync owner joined this census when its
    -- four full hooks (husk hat create, local go-init, resync, hot join) moved out
    -- of the entry. Same rule as above: a new owner is added to the census rather
    -- than the expected totals being lowered, so the family total cannot drift.
    local attachment_spawn_sync = read(
        "cosmetics_tweaker/scripts/mods/cosmetics_tweaker/"
        .. "_cos_attachment_spawn_sync.lua")
    -- #1159: the live equipment-assembly owner joined this census when its two
    -- full hooks (GearUtils.create_equipment and the BackendUtils.get_item_units
    -- resolution it brackets) moved out of the entry. Same rule again: the owner
    -- is added, the expected totals are NOT lowered.
    local equipment_assembly = read(
        "cosmetics_tweaker/scripts/mods/cosmetics_tweaker/"
        .. "_cos_equipment_assembly.lua")
    -- #1159: the LA apply / revert / reconcile owner joined this census when the
    -- unified apply core, the offhand mesh re-swap and the three revert
    -- primitives moved out of the entry. That block registered NOTHING, so the
    -- family totals below are unchanged - which is the point: the owner is in the
    -- census from day one, so the first hook anyone adds to it moves a total.
    local apply_runtime = read(
        "cosmetics_tweaker/scripts/mods/cosmetics_tweaker/"
        .. "_cos_la_apply_runtime.lua")
    -- #1159: the cos_la_* peer-sync transport owner joined this census when its
    -- four mod:network_register handlers and the PlayerManager remove_player /
    -- add_remote_player hook_safe pair moved out of the entry. Same rule as every
    -- owner above: it is ADDED to the census and the expected family totals below
    -- are NOT lowered, so the extracted family's registration count cannot drift.
    local la_sync_transport = read(
        "cosmetics_tweaker/scripts/mods/cosmetics_tweaker/"
        .. "_cos_la_sync_transport.lua")
    -- #1159: the LA loadout-safety owner joined this census when its six hooks
    -- (BackendUtils.set_loadout_item, three items-interface reads, and the
    -- CosmeticUtils / LoadoutUtils net-safe senders) moved out of the entry.
    -- Same rule as every owner above: it is ADDED to the census and the expected
    -- family totals below are NOT lowered, so the moved hooks cannot drift.
    local la_loadout_safety = read(
        "cosmetics_tweaker/scripts/mods/cosmetics_tweaker/"
        .. "_cos_la_loadout_safety.lua")
    local glow_picker_host = read(
        "cosmetics_tweaker/scripts/mods/cosmetics_tweaker/"
        .. "_cos_glow_picker_host.lua")
    local local_wield_runtime = read(
        "cosmetics_tweaker/scripts/mods/cosmetics_tweaker/"
        .. "_cos_local_wield_runtime.lua")
    -- #1159: the exact-instance item-card owner joined the census when its one
    -- UIUtils hook moved out of entry. Include it without lowering the family
    -- total so hook ownership cannot silently disappear during extraction.
    local item_presentation_runtime = read(
        "cosmetics_tweaker/scripts/mods/cosmetics_tweaker/"
        .. "_cos_item_presentation_runtime.lua")
    -- #1159 Wave 19: preserve the same total registration census after the
    -- attachment/preview spawn hooks and Moonfire impact hook moved to owners.
    local spawn_boundary = read(
        "cosmetics_tweaker/scripts/mods/cosmetics_tweaker/"
        .. "_cos_spawn_boundary.lua")
    local moonfire_puff_runtime = read(
        "cosmetics_tweaker/scripts/mods/cosmetics_tweaker/"
        .. "_cos_moonfire_puff_runtime.lua")
    local Runtime = assert(loadfile(repo_root .. "/" .. module_path))()

    H.test("Cosmetics LA replay runtime has one ordered entry owner", function()
        H.equal(occurrences(entry, "_cos_la_replay_runtime"), 1)
        H.truthy(entry:find(
            'mod:dofile("scripts/mods/cosmetics_tweaker/_cos_la_replay_runtime").install',
            1, true))
        H.equal(entry:find("mod._cos_replay.apply = function", 1, true), nil)
        H.equal(entry:find("mod._cos_replay.on_edge = function", 1, true), nil)

        -- #1159: mod._la_reconcile is no longer DEFINED in the entry - it moved
        -- verbatim into _cos_la_apply_runtime. The ordering invariant is the same
        -- one, measured at the install site that replaced the definition: the
        -- reconcile owner, then this coordinator, then every RPC consumer.
        H.equal(entry:find("mod._la_reconcile = function", 1, true), nil)
        H.truthy(apply_runtime:find("mod._la_reconcile = function", 1, true))
        local reconcile = assert(entry:find(
            'mod:dofile("scripts/mods/cosmetics_tweaker/_cos_la_apply_runtime").install',
            1, true))
        local install = assert(entry:find("_cos_la_replay_runtime", reconcile, true))
        -- #1159: the four cos_la_* receivers moved verbatim into
        -- _cos_la_sync_transport, whose second install phase runs at the exact
        -- line the first mod:network_register used to occupy. The "every RPC
        -- consumer comes last" half of the ordering invariant is measured at that
        -- call site now; the entry must no longer register the channel itself.
        H.equal(entry:find('mod:network_register("cos_la_apply_req"', 1, true), nil)
        H.truthy(la_sync_transport:find(
            'mod:network_register("cos_la_apply_req"', 1, true))
        local first_rpc = assert(entry:find(
            "LA_SYNC.install_receivers()", install, true))
        H.truthy(reconcile < install and install < first_rpc)
    end)

    H.test("Cosmetics replay extraction preserves transport and hook cardinality", function()
        local entry_exec = entry:gsub("%-%-[^\n]*", "")
            .. offhand_picker:gsub("%-%-[^\n]*", "")
            .. preview_runtime:gsub("%-%-[^\n]*", "")
            .. news_feed_safety:gsub("%-%-[^\n]*", "")
            .. view_lifecycle:gsub("%-%-[^\n]*", "")
            .. attachment_spawn_sync:gsub("%-%-[^\n]*", "")
            .. equipment_assembly:gsub("%-%-[^\n]*", "")
            .. apply_runtime:gsub("%-%-[^\n]*", "")
            .. la_sync_transport:gsub("%-%-[^\n]*", "")
            .. la_loadout_safety:gsub("%-%-[^\n]*", "")
            .. glow_picker_host:gsub("%-%-[^\n]*", "")
            .. local_wield_runtime:gsub("%-%-[^\n]*", "")
            .. item_presentation_runtime:gsub("%-%-[^\n]*", "")
            .. spawn_boundary:gsub("%-%-[^\n]*", "")
            .. moonfire_puff_runtime:gsub("%-%-[^\n]*", "")
        local module_exec = source:gsub("%-%-[^\n]*", "")
        H.equal(occurrences(entry_exec, "mod:network_register("), 4)
        H.equal(occurrences(glow_transport:gsub("%-%-[^\n]*", ""),
            "mod:network_register("), 2)
        H.equal(occurrences(entry_exec, "mod:hook("), 28)
        H.equal(occurrences(entry_exec, "mod:hook_safe("), 18)
        H.equal(occurrences(entry_exec, "mod:hook_origin("), 1)
        H.equal(occurrences(module_exec, "network_register"), 0)
        H.equal(occurrences(module_exec, "network_send"), 0)
        H.equal(occurrences(module_exec, "mod:hook"), 0)
        H.equal(occurrences(module_exec, "mod.on_"), 0)
        H.equal(occurrences(module_exec, "mod.update"), 0)
        H.equal(occurrences(source, "replay.apply = function"), 1)
        H.equal(occurrences(source, "replay.on_edge = function"), 1)
    end)

    H.test("Cosmetics replay owner is idempotent and preserves status mapping", function()
        local calls = {
            new_state = 0,
            reconcile = 0,
            pulse = 0,
            logs = 0,
        }
        local units = {
            alive = { alive = true },
            dead = { alive = false },
        }
        local policy = {}
        function policy.new_replay_state()
            calls.new_state = calls.new_state + 1
            return { generation = 1 }
        end
        function policy.invalidate_all(state)
            calls.invalidate_all = state
        end
        function policy.invalidate(state, peer)
            calls.invalidated_state = state
            calls.invalidated_peer = peer
        end
        function policy.build_records(equips, offhands, options)
            calls.equips = equips
            calls.offhands = offhands
            calls.only_peer = options.only_peer
            return { marker = "records" }
        end
        function policy.reconcile_edge(state, edge, records, apply)
            calls.edge_state = state
            calls.edge = edge
            calls.records = records
            calls.apply = apply
            return { per_peer = { peer_a = 1 }, deferred = 0, coalesced = 0 }
        end

        local mod = {
            _offhand_mesh_by_peer = { peer_a = { slot_melee = {} } },
        }
        mod._la_native_pulse = function(unit, tag)
            calls.pulse = calls.pulse + 1
            calls.pulse_unit = unit
            calls.pulse_tag = tag
        end
        mod._la_reconcile = function(peer, slot, tag, allow_pulse)
            calls.reconcile = calls.reconcile + 1
            calls.reconcile_args = { peer, slot, tag, allow_pulse }
            return calls.reconcile_result, calls.reconcile_reason
        end

        local equips = { peer_a = { slot_melee = { armoury_key = "key" } } }
        local owner = Runtime.install(mod, {
            policy = policy,
            wearer_unit_for_peer = function(peer) return units[peer] end,
            unit_alive = function(unit) return unit.alive end,
            is_local_server = function() return false end,
            la_equips_by_peer = equips,
            printf = function() calls.logs = calls.logs + 1 end,
        })
        H.equal(Runtime.install(mod, {}), owner)
        H.equal(calls.new_state, 1)
        H.equal(owner.replay, mod._cos_replay)
        H.equal(owner.policy, policy)

        H.equal(mod._cos_replay.apply("missing", "slot", {}), "defer")
        H.equal(mod._cos_replay.apply("dead", "slot", {}), "defer")
        H.equal(mod._cos_replay.apply("alive", "slot", nil), "skip")
        H.equal(mod._cos_replay.apply("alive", "slot", {
            offhand_unit = "unit_path",
        }), "applied")
        H.equal(calls.pulse, 1)
        H.equal(calls.pulse_unit, units.alive)
        H.equal(calls.pulse_tag, "replay")

        calls.reconcile_result, calls.reconcile_reason = true, nil
        H.equal(mod._cos_replay.apply("alive", "slot", {}), "applied")
        H.deep_equal(calls.reconcile_args, { "alive", "slot", "replay", true })
        calls.reconcile_result, calls.reconcile_reason = false, "no-entry"
        H.equal(mod._cos_replay.apply("alive", "slot", {}), "skip")
        calls.reconcile_result, calls.reconcile_reason = false, "deus-yield"
        H.equal(mod._cos_replay.apply("alive", "slot", {}), "skip")
        calls.reconcile_result, calls.reconcile_reason = false, "not-ready"
        H.equal(mod._cos_replay.apply("alive", "slot", {}), "defer")
    end)

    H.test("Cosmetics replay edges preserve bounded invalidation and re-arm order", function()
        local calls = {}
        local state = { generation = 3 }
        local policy = {
            new_replay_state = function() return state end,
            invalidate = function(got_state, peer)
                calls[#calls + 1] = "invalidate_peer"
                H.equal(got_state, state)
                H.equal(peer, "peer_b")
            end,
            invalidate_all = function(got_state)
                calls[#calls + 1] = "invalidate_all"
                H.equal(got_state, state)
            end,
            build_records = function(equips, offhands, options)
                calls[#calls + 1] = "build"
                H.equal(equips.marker, "equips")
                H.equal(offhands.marker, "offhands")
                H.equal(options.only_peer, "peer_b")
                return { marker = "records" }
            end,
            reconcile_edge = function(got_state, edge, records, apply)
                calls[#calls + 1] = "reconcile"
                H.equal(got_state, state)
                H.equal(edge, "peer-ready")
                H.equal(records.marker, "records")
                H.truthy(type(apply) == "function")
                return { per_peer = {}, deferred = 1, coalesced = 2 }
            end,
        }
        local mod = {
            _offhand_mesh_by_peer = { marker = "offhands" },
            _la_state_pull_exhausted = true,
            _la_reconcile = function() return false, "not-ready" end,
        }
        Runtime.install(mod, {
            policy = policy,
            wearer_unit_for_peer = function() return nil end,
            unit_alive = function() return false end,
            is_local_server = function() return false end,
            la_equips_by_peer = { marker = "equips" },
        })
        local result = mod._cos_replay.on_edge("peer-ready", {
            only_peer = "peer_b",
            invalidate_peer = "peer_b",
        })
        H.deep_equal(calls, { "invalidate_peer", "build", "reconcile" })
        H.equal(result.deferred, 1)
        H.equal(result.coalesced, 2)
        H.equal(mod._la_state_pull_exhausted, nil)
        H.deep_equal(mod._la_state_pull_pending, { attempts = 0, next_at = 0 })

        policy.build_records = function()
            calls[#calls + 1] = "build_all"
            return {}
        end
        policy.reconcile_edge = function()
            calls[#calls + 1] = "reconcile_all"
            return { per_peer = {}, deferred = 0, coalesced = 0 }
        end
        mod._cos_replay.on_edge("session-ready", { invalidate_all = true })
        H.deep_equal(calls, {
            "invalidate_peer", "build", "reconcile",
            "invalidate_all", "build_all", "reconcile_all",
        })
    end)
end
