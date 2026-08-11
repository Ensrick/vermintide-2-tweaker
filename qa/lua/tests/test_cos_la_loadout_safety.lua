-- Boundary + behaviour guard for the #1159 LA loadout-safety owner
-- (_cos_la_loadout_safety.lua).
--
-- Three load-bearing properties this file exists to pin.
--
-- 1. THE LATE-BOUND SENDER. This owner installs ABOVE the entry line that
--    assigns `_send_la_apply` (the transport owner publishes it ~600 lines
--    later), so the sender can only cross the chunk boundary as a getter. A
--    by-value hand-off still loads, still passes every substitution test below,
--    and silently freezes nil - which reads as "peers just never get told about
--    the LA hat", the exact class of bug this mod exists to fix. The matched
--    pair near the bottom is the signal the regression cannot move: the control
--    assigns the sender BEFORE install (green either way), the real test assigns
--    it AFTER install the way the entry does (red the moment the getter goes).
--
-- 2. UNCONDITIONAL SUBSTITUTION. Wire safety is never toggle-gated (issue 371 /
--    BUG_CLASSES 31). The owner must carry no settings read at all, and the
--    no-fallback case must SKIP the vanilla call rather than let an LA
--    backend_id reach the wire.
--
-- 3. THE STATUS TABLE DID NOT MOVE. `_net_safe_hook_status` stays entry state:
--    the entry declares it, brokers it to _cos_attachment_spawn_sync (which
--    writes .PUAE / .AttachmentUtils into it) and reads it back in the startup
--    verification. Nothing in this owner may read or write it, or the table
--    grows a third party and the by-reference contract stops being provable
--    from one place.
return function(H, repo_root)
    local base = "cosmetics_tweaker/scripts/mods/cosmetics_tweaker/"
    local module_relative = base .. "_cos_la_loadout_safety.lua"

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
            count, offset = count + 1, at + #needle
        end
    end

    local entry = read(base .. "cosmetics_tweaker.lua")
    local source = read(module_relative)
    local owner_install =
        'mod:dofile("scripts/mods/cosmetics_tweaker/_cos_la_loadout_safety").install(mod, {'

    -- ================================================================
    -- Boundary
    -- ================================================================

    H.test("cos la loadout safety installs once, above the sender assignment", function()
        H.equal(occurrences(entry, owner_install), 1)

        local at_install = assert(entry:find(owner_install, 1, true))
        local at_preview = assert(entry:find(
            'mod:dofile("scripts/mods/cosmetics_tweaker/_cos_preview_runtime").install',
            1, true))
        local at_transport = assert(entry:find(
            'mod:dofile("scripts/mods/cosmetics_tweaker/_cos_la_sync_transport").install',
            1, true))
        local at_assignment = assert(entry:find(
            "_send_la_apply              = LA_SYNC.send_la_apply", 1, true))
        local at_status = assert(entry:find("local _net_safe_hook_status = {", 1, true))

        -- The install sits at the exact former position of the moved block:
        -- after the preview-runtime owner, before the transport owner.
        H.truthy(at_preview < at_install)
        H.truthy(at_install < at_transport)
        -- ...and therefore BEFORE the sender exists. This ordering is the whole
        -- reason `get_send_la_apply` is a getter; if a later slice ever moves the
        -- install below the assignment, this fails and the getter can be revisited.
        H.truthy(at_install < at_assignment)
        -- The two file-scope hook registrations still run before the presence
        -- probe that reports on them.
        H.truthy(at_install < at_status)
    end)

    H.test("cos la loadout safety owns every moved definition exclusively", function()
        for _, needle in ipairs({
            "local _la_skin_safety_done       = false",
            "local _la_vanilla_fallback = function(name, career)",
            "local function _install_skin_loadout_safety()",
            "local function _fixup_server_clones()",
            "local function _wire_career_for_player(player)",
            "mod._la_skin_safety_installed = true",
            "mod._cos_skin_wire_surfaces.update_cosmetic_slot = true",
        }) do
            H.truthy(source:find(needle, 1, true), needle .. " missing from the owner")
            H.equal(entry:find(needle, 1, true), nil, needle .. " must not stay in the entry")
        end

        -- The three exports come back out as entry locals, so every consumer
        -- that stayed behind resolves the SAME function object.
        H.truthy(entry:find(
            "local _la_vanilla_fallback         = LA_LOADOUT_SAFETY.la_vanilla_fallback", 1, true))
        H.truthy(entry:find(
            "local _wire_career_for_player      = LA_LOADOUT_SAFETY.wire_career_for_player", 1, true))
        H.truthy(entry:find(
            "local _install_skin_loadout_safety = LA_LOADOUT_SAFETY.install_skin_loadout_safety", 1, true))
        -- The entry's own consumers of those exports are still there.
        H.truthy(entry:find("if LA_BRIDGE.registered then _install_skin_loadout_safety() end", 1, true))
        H.truthy(entry:find("la_vanilla_fallback = _la_vanilla_fallback,", 1, true))
        H.truthy(entry:find("career_for = _wire_career_for_player,", 1, true))
        -- The entry keeps its own bridge latch; it is not this owner's state.
        -- Strip comments: the owner's ENTRY-OWNED STATE header names it on purpose.
        H.truthy(entry:find("local _la_bridge_init_done       = false", 1, true))
        H.equal(source:gsub("%-%-[^\n]*", ""):find("_la_bridge_init_done", 1, true), nil)

        H.truthy(source:find("RESPONSIBILITY", 1, true))
        H.truthy(source:find("Consumed via:", 1, true))
        -- Re-dofile'ing a sibling would build a SECOND instance of a stateful
        -- module (mod:dofile is not a singleton), so every handle arrives via deps.
        H.equal(source:gsub("%-%-[^\n]*", ""):find("mod:dofile(", 1, true), nil)
        H.equal(source:gsub("%-%-[^\n]*", ""):find("mod:command(", 1, true), nil)
        H.equal(source:gsub("%-%-[^\n]*", ""):find("mod:network_register(", 1, true), nil)
    end)

    H.test("cos la loadout safety owns its six hooks as singletons", function()
        -- VMF silently DROPS a second registration on the same (Class, method),
        -- so a resurrected entry copy would not error - it would just stop
        -- working. Exactly one in the owner, exactly zero in the entry.
        for _, needle in ipairs({
            'mod:hook(BackendUtils, "set_loadout_item"',
            'mod:hook(items_iface, "get_loadout", function(func, self)',
            'mod:hook(items_iface, "get_loadout_item_id"',
            'mod:hook(items_iface, "get_item_rarity"',
            'mod:hook(CosmeticUtils, "update_cosmetic_slot"',
            'mod:hook(LoadoutUtils, "sync_loadout_slot"',
        }) do
            H.equal(occurrences(source, needle), 1, needle .. " must be registered exactly once")
            H.equal(entry:find(needle, 1, true), nil, needle .. " must not stay in the entry")
        end
        -- Both plain-table hooks keep their nil guard: CosmeticUtils and
        -- LoadoutUtils are `X = X or {}` tables, not classes, and a missing
        -- guard is a load-order crash rather than a silent no-op.
        H.truthy(source:find("if CosmeticUtils then", 1, true))
        H.truthy(source:find("if LoadoutUtils then", 1, true))
    end)

    H.test("the net-safe hook status table stayed entry-owned", function()
        -- Declared, written and read by the entry; brokered by the entry to the
        -- attachment-spawn owner. This owner is not a party to it at all.
        H.truthy(entry:find("local _net_safe_hook_status = {", 1, true))
        H.truthy(entry:find("_net_safe_hook_status.CosmeticUtils = CosmeticUtils ~= nil", 1, true))
        H.truthy(entry:find("_net_safe_hook_status.LoadoutUtils = LoadoutUtils ~= nil", 1, true))
        H.truthy(entry:find("net_safe_hook_status = _net_safe_hook_status,", 1, true))
        -- Strip comments: the owner's NOT-OWNED-HERE header names them on purpose.
        local exec = source:gsub("%-%-[^\n]*", "")
        H.equal(exec:find("_net_safe_hook_status", 1, true), nil,
            "the owner must not read or write the entry's status table")
        -- `_la_substitute_name` likewise stayed: its only caller is the
        -- attachment-spawn owner, and it closes over the entry's rebound export.
        H.truthy(entry:find("local function _la_substitute_name(", 1, true))
        H.equal(exec:find("_la_substitute_name", 1, true), nil)
    end)

    H.test("the LA to vanilla substitution carries no settings gate", function()
        -- Issue 371 / BUG_CLASSES 31: a peer's crash is not the local player's
        -- option, so the sender swap is unconditional by construction.
        local exec = source:gsub("%-%-[^\n]*", "")
        H.equal(exec:find("mod:get(", 1, true), nil)
        H.equal(exec:find("get_setting", 1, true), nil)
        H.equal(exec:find("mod:get_internal", 1, true), nil)
    end)

    -- ================================================================
    -- Behaviour: the real module driven through a stub install
    -- ================================================================

    local saved = {}
    local function set_globals(fixture)
        saved = {
            Unit = _G.Unit, Managers = _G.Managers, ScriptUnit = _G.ScriptUnit,
            printf = _G.printf, BackendUtils = _G.BackendUtils,
            CosmeticUtils = _G.CosmeticUtils, LoadoutUtils = _G.LoadoutUtils,
        }
        _G.Unit = { alive = function(u) return u ~= nil end }
        _G.ScriptUnit = { has_extension = function() return nil end }
        _G.printf = function() end
        _G.BackendUtils = {}
        _G.CosmeticUtils = {}
        _G.LoadoutUtils = {}
        _G.Managers = fixture
    end
    local function restore_globals()
        _G.Unit, _G.Managers, _G.ScriptUnit = saved.Unit, saved.Managers, saved.ScriptUnit
        _G.printf, _G.BackendUtils = saved.printf, saved.BackendUtils
        _G.CosmeticUtils, _G.LoadoutUtils = saved.CosmeticUtils, saved.LoadoutUtils
    end

    -- The entry-side local the getter fronts. The entry forward-declares this
    -- and only assigns it BELOW the install; rebinding it here is exactly what
    -- the entry's `_send_la_apply = LA_SYNC.send_la_apply` line does.
    local entry_send
    local mod, hooks, emits, published, persisted, backend_items, loadout_writes
    local la_equips_by_peer, local_la_equips, local_player

    local VANILLA = {
        la_hat_bid = "es_hat_vanilla",
        la_skin_bid = "es_skin_vanilla",
        la_orphan_bid = nil,   -- an LA clone with NO vanilla equivalent
    }

    local function build(options)
        options = options or {}
        hooks, emits, published, persisted = {}, {}, {}, {}
        loadout_writes = {}
        la_equips_by_peer, local_la_equips = {}, {}
        backend_items = {
            vanilla_hat = { key = "es_hat_vanilla" },
            la_hat_bid  = { key = "la_hat" },
        }
        local_player = { peer_id = "local-peer", player_unit = { "unit" } }

        mod = {
            loadout_cache = {},
            _cos_skin_wire_surfaces = {},
            _cos_wire_safe_custom_skin = function(skin_name) return skin_name, false end,
            _cos925_publish_loadout = function(_, backend_id, career, slot, reason)
                published[#published + 1] =
                    { backend_id = backend_id, career = career, slot = slot, reason = reason }
            end,
            _cos_send_custom_skin_hands = function(unit, item, skin, context)
                emits[#emits + 1] = { kind = "custom_hands", context = context, skin = skin }
            end,
            _send_la_revert = function(unit, slot, kind)
                emits[#emits + 1] = { kind = "revert", slot = slot, revert_kind = kind }
            end,
        }
        function mod:hook(target, method, fn) hooks[method] = fn end

        local items_iface = {
            get_all_backend_items = function() return backend_items end,
            get_loadout = function() return { es_knight = {} } end,
        }
        set_globals({
            backend = {
                _interfaces = { items = items_iface },
                get_interface = function() return items_iface end,
                get_loadout_interface_by_slot = function()
                    return {
                        set_loadout_item = function(_, bid, career, slot)
                            loadout_writes[#loadout_writes + 1] =
                                { bid = bid, career = career, slot = slot }
                        end,
                    }
                end,
            },
            player = {},
        })

        if options.assign_sender_before_install then
            entry_send = function(unit, slot, kind, armoury_key, vanilla_key)
                emits[#emits + 1] = { kind = kind, slot = slot,
                    armoury_key = armoury_key, vanilla_key = vanilla_key }
            end
        else
            entry_send = nil
        end

        local Owner = assert(loadfile(repo_root .. "/" .. module_relative))()
        local owner = Owner.install(mod, {
            gk_set = {
                wire_fallback = function(_, name) return VANILLA[name] end,
                career_for_player = function() return "es_knight" end,
            },
            la_bridge = {
                registered = true,
                backend_to_armoury = {
                    la_hat_bid    = "Kruber_Pureheart",
                    la_skin_bid   = "Kruber_Pureheart_Skin",
                    la_orphan_bid = "Kruber_Orphan",
                },
            },
            la_persistence = {
                _career_name_for_player = function() return "es_knight" end,
                get_saved_cosmetic = function() return nil end,
                get_saved_illusion = function() return nil end,
                get_all_saved_cosmetics = function() return options.saved_cosmetics or {} end,
                save_cosmetic = function(career, slot, bid)
                    persisted[#persisted + 1] =
                        { op = "save", career = career, slot = slot, bid = bid }
                end,
                clear_cosmetic = function(career, slot)
                    persisted[#persisted + 1] = { op = "clear", career = career, slot = slot }
                end,
                save_illusion = function() end,
                clear_illusion = function() end,
            },
            dbg = function() end,
            la_equips_by_peer = la_equips_by_peer,
            local_la_equips = local_la_equips,
            local_player_safe = function() return local_player end,
            get_send_la_apply = function() return entry_send end,
        })
        return owner, items_iface
    end

    H.test("install_skin_loadout_safety registers the backend hooks once", function()
        local owner = build()
        owner.install_skin_loadout_safety()
        local first = hooks.set_loadout_item
        H.truthy(first)
        H.truthy(hooks.get_loadout)
        H.truthy(hooks.get_loadout_item_id)
        H.truthy(hooks.get_item_rarity)
        H.equal(mod._la_skin_safety_installed, true)
        -- One-shot: a second call must not re-register (VMF would drop it, and
        -- the rehydrate/fixup would run twice).
        hooks.set_loadout_item = nil
        owner.install_skin_loadout_safety()
        restore_globals()
        H.equal(hooks.set_loadout_item, nil, "the installer must be one-shot")
    end)

    H.test("an LA clone equip is cached locally and never written to the backend", function()
        local owner = build()
        owner.install_skin_loadout_safety()
        local vanilla_reached = false
        hooks.set_loadout_item(function() vanilla_reached = true end,
            "la_hat_bid", "es_knight", "slot_hat")
        restore_globals()
        H.equal(mod.loadout_cache.es_knight.slot_hat, "la_hat_bid")
        H.equal(vanilla_reached, false,
            "an LA clone backend_id must never reach the real backend write")
        H.equal(persisted[#persisted].op, "save")
        H.equal(persisted[#persisted].bid, "la_hat_bid")
        H.equal(published[#published].reason, "cosmetic-equip")
    end)

    H.test("equipping a vanilla item over an LA one clears cache and disk", function()
        local owner = build()
        owner.install_skin_loadout_safety()
        hooks.set_loadout_item(function() end, "la_hat_bid", "es_knight", "slot_hat")
        local vanilla_reached = false
        hooks.set_loadout_item(function() vanilla_reached = true end,
            "vanilla_hat", "es_knight", "slot_hat")
        restore_globals()
        H.equal(mod.loadout_cache.es_knight.slot_hat, nil)
        H.equal(vanilla_reached, true, "a vanilla equip must reach the real backend write")
        H.equal(persisted[#persisted].op, "clear")
    end)

    H.test("the bot loadout query never reads the local player's cache", function()
        local owner = build()
        owner.install_skin_loadout_safety()
        mod.loadout_cache.es_knight = { slot_hat = "la_hat_bid" }
        local function raw() return "bot_own_hat" end
        -- Matched pair. The human read is the control: it proves the cache is
        -- populated and reachable, so the bot assertion below cannot pass
        -- vacuously.
        local human = hooks.get_loadout_item_id(raw, nil, "es_knight", "slot_hat", false)
        local bot = hooks.get_loadout_item_id(raw, nil, "es_knight", "slot_hat", true)
        restore_globals()
        H.equal(human, "la_hat_bid")
        H.equal(bot, "bot_own_hat",
            "is_bot must fall through to the bot's own designated loadout")
    end)

    H.test("get_loadout overlays the local cache onto the backend answer", function()
        local owner = build()
        owner.install_skin_loadout_safety()
        mod.loadout_cache.es_knight = { slot_hat = "la_hat_bid" }
        local loadout = hooks.get_loadout(function() return { es_knight = {} } end, nil)
        restore_globals()
        H.equal(loadout.es_knight.slot_hat, "la_hat_bid")
    end)

    H.test("update_cosmetic_slot substitutes the vanilla equivalent on the wire", function()
        build({ assign_sender_before_install = true })
        local seen
        hooks.update_cosmetic_slot(function(_, slot, item_name, skin_name)
            seen = { slot = slot, item_name = item_name, skin_name = skin_name }
        end, local_player, "slot_hat", "la_hat_bid", nil)
        restore_globals()
        H.equal(seen.item_name, "es_hat_vanilla",
            "the LA backend_id must never reach the vanilla sender")
        H.equal(seen.slot, "slot_hat")
    end)

    H.test("update_cosmetic_slot SKIPS the sender when no vanilla fallback exists", function()
        build({ assign_sender_before_install = true })
        local reached = false
        hooks.update_cosmetic_slot(function() reached = true end,
            local_player, "slot_hat", "la_orphan_bid", nil)
        restore_globals()
        H.equal(reached, false,
            "with no vanilla equivalent the only safe action is not to send at all")
    end)

    H.test("update_cosmetic_slot passes a vanilla equip straight through", function()
        build({ assign_sender_before_install = true })
        local seen
        hooks.update_cosmetic_slot(function(_, slot, item_name)
            seen = { slot = slot, item_name = item_name }
        end, local_player, "slot_hat", "vanilla_hat", nil)
        restore_globals()
        H.equal(seen.item_name, "vanilla_hat", "a non-LA equip must be untouched")
    end)

    H.test("sync_loadout_slot substitutes through a shadow, not by mutation", function()
        build({ assign_sender_before_install = true })
        local item = { key = "la_hat_bid", rarity = "promo" }
        local seen
        hooks.sync_loadout_slot(function(_, slot_name, sent)
            seen = { slot_name = slot_name, sent = sent }
        end, local_player, "slot_hat", item, nil)
        restore_globals()
        H.equal(seen.sent.key, "es_hat_vanilla")
        H.equal(seen.sent.rarity, "promo", "the shadow must carry the rest of the item")
        H.equal(item.key, "la_hat_bid",
            "the caller's item is shared state and must not be mutated")
    end)

    -- ================================================================
    -- The matched pair that a by-value sender hand-off cannot keep green
    -- ================================================================

    H.test("CONTROL: the LA emit lands when the sender exists at install time", function()
        build({ assign_sender_before_install = true })
        hooks.update_cosmetic_slot(function() end,
            local_player, "slot_hat", "la_hat_bid", nil)
        restore_globals()
        H.equal(#emits, 1)
        H.equal(emits[1].kind, "hat")
        H.equal(emits[1].armoury_key, "Kruber_Pureheart")
        H.equal(emits[1].vanilla_key, "es_hat_vanilla")
    end)

    H.test("the LA emit lands when the sender is assigned AFTER install", function()
        -- This is the entry's real shape: `_send_la_apply` is nil while this
        -- owner installs and is filled in ~600 lines below, by the transport
        -- owner. Turn `get_send_la_apply` back into an install-time value and
        -- the closure captures nil, the hook's `and _send_la_apply` guard goes
        -- false, and no peer is ever told about the hat - while the CONTROL
        -- above stays green.
        build({ assign_sender_before_install = false })
        entry_send = function(unit, slot, kind, armoury_key, vanilla_key)
            emits[#emits + 1] = { kind = kind, slot = slot,
                armoury_key = armoury_key, vanilla_key = vanilla_key }
        end
        hooks.update_cosmetic_slot(function() end,
            local_player, "slot_hat", "la_hat_bid", nil)
        restore_globals()
        H.equal(#emits, 1, "the late-assigned sender must still receive the emit")
        H.equal(emits[1].kind, "hat")
        H.equal(emits[1].vanilla_key, "es_hat_vanilla")
    end)

    H.test("the disk rehydrate restores only clones that still resolve", function()
        local owner = build({ saved_cosmetics = {
            es_knight = { slot_hat = "la_hat_bid", slot_skin = "gone_bid" },
        } })
        owner.install_skin_loadout_safety()
        restore_globals()
        H.equal(mod.loadout_cache.es_knight.slot_hat, "la_hat_bid")
        H.equal(mod.loadout_cache.es_knight.slot_skin, nil,
            "an LA variant that no longer exists must be skipped, not restored")
    end)
end
