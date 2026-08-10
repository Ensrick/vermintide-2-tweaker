-- Boundary + behaviour guard for the #1159 attachment-slot LA spawn/sync owner
-- (_cos_attachment_spawn_sync.lua).
--
-- The load-bearing property this file exists to pin: `_la_pending_apply` is an
-- entry local that both drain sites REBIND (`_la_pending_apply = kept`), so the
-- owner must resolve the queue through a getter AT ENQUEUE TIME. The last two
-- tests are a matched pair: the first proves a deferral reaches the queue, the
-- second REBINDS the entry-side local the way a real drain does and proves the
-- next deferral reaches the NEW table and not the discarded one. That is a signal
-- the fix cannot move -- converting the getter back into an install-time value
-- still passes the first test and fails only the second, which is exactly the
-- silent failure mode (deferrals accumulating in an orphan nobody drains).
--
-- The second unmovable signal is ordering: `_send_la_apply` IS handed over by
-- value here, which is only safe because the entry assigns it far above this
-- install call. That ordering is asserted, not assumed.
return function(H, repo_root)
    local function read(relative)
        local file = assert(io.open(repo_root .. "/" .. relative, "rb"))
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

    local entry = read("cosmetics_tweaker/scripts/mods/cosmetics_tweaker/cosmetics_tweaker.lua")
    local module_relative =
        "cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_cos_attachment_spawn_sync.lua"
    local source = read(module_relative)
    local owner_install =
        'mod:dofile("scripts/mods/cosmetics_tweaker/_cos_attachment_spawn_sync").install(mod, {'

    H.test("cos attachment spawn sync installs once at the former inline position", function()
        H.equal(occurrences(entry, owner_install), 1)
        local at_owner = entry:find(owner_install, 1, true)
        local at_husk_wield = entry:find(
            'mod:hook("SimpleHuskInventoryExtension", "_wield_slot"', 1, true)
        local at_netsafe = entry:find(
            'mod:info("[net-safe] hook registration:', 1, true)
        H.truthy(at_husk_wield and at_netsafe)
        -- After the husk WEAPON wield hook the entry keeps, and before the
        -- startup verification that reads the status fields this owner writes.
        H.truthy(at_husk_wield < at_owner)
        H.truthy(at_owner < at_netsafe)
    end)

    H.test("cos attachment spawn sync owns all four spawn/sync seams exclusively", function()
        local pairs_owned = {
            '"PlayerHuskAttachmentExtension", "create_attachment"',
            '"PlayerUnitAttachmentExtension", "game_object_initialized"',
            '"PlayerUnitAttachmentExtension", "spawn_resynced_loadout"',
        }
        for _, pair in ipairs(pairs_owned) do
            -- VMF silently drops a second registration on the same (Class,
            -- method) pair, so a re-inlined copy would shadow the owner rather
            -- than fail loudly. The entry-side absence is the real guard.
            H.equal(occurrences(entry, pair), 0)
            H.equal(occurrences(source, pair), 1)
        end
        H.equal(occurrences(entry, 'mod:hook(AttachmentUtils, "hot_join_sync"'), 0)
        H.equal(occurrences(source, 'mod:hook(AttachmentUtils, "hot_join_sync"'), 1)
        -- AttachmentUtils is a PLAIN TABLE: the string form silently never
        -- registers, so the nil-guarded table form must survive the move intact.
        H.equal(occurrences(source, "if AttachmentUtils then"), 1)
        H.equal(occurrences(source, 'mod:hook("AttachmentUtils"'), 0)
        -- The entry keeps the OTHER AttachmentUtils method (the #270 residency
        -- gate on optional attachments) and the husk WEAPON wield path.
        H.equal(occurrences(entry, 'mod:hook(AttachmentUtils, "create_attachment"'), 1)
        H.equal(occurrences(source, 'mod:hook(AttachmentUtils, "create_attachment"'), 0)
    end)

    H.test("cos attachment spawn sync does not overlap its sibling owners", function()
        local fade = read(
            "cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_cos_appearance_fade_runtime.lua")
        -- The fade runtime hooks the LOCAL body's create_attachment; this owner
        -- hooks the HUSK class's. Same method name, different class, no shadow.
        H.equal(occurrences(fade, '"PlayerUnitAttachmentExtension", "create_attachment"'), 1)
        H.equal(occurrences(source, '"PlayerUnitAttachmentExtension", "create_attachment"'), 0)
        H.equal(occurrences(source, '"_reapply_fade"'), 0)
        local link_policy = read(
            "cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_cos_attachment_link_policy.lua")
        H.truthy(link_policy:find('"link"', 1, true))
        H.equal(occurrences(source, '"link"'), 0)
        -- This owner is a set of spawn-time emitters; it registers no RPC of its
        -- own and no UI hook, and it never re-dofiles a stateful sibling
        -- (mod:dofile is not a singleton -- that would build a second instance).
        H.equal(occurrences(source, "network_register"), 0)
        H.equal(occurrences(source, 'mod:hook("HeroWindowItemCustomization"'), 0)
        H.equal(occurrences(source, 'mod:hook_safe("HeroWindowItemCustomization"'), 0)
        H.equal(occurrences(source, 'mod:dofile("'), 0)
        H.truthy(source:find("Owned by:", 1, true))
        H.truthy(source:find("Consumed via:", 1, true))
    end)

    H.test("cos attachment spawn sync crossing state uses the correct hand-off kind", function()
        -- REBOUND by the entry -> must cross as a getter, and the owner must not
        -- shadow it with a local of its own.
        -- #1159: TWO owners now take the retry queue this way - this one, and
        -- _cos_la_apply_runtime, which additionally needs the matching SETTER
        -- because the drain that rebinds the queue moved into it. The census is
        -- raised to 2 rather than relaxed, so a hand-off that silently reverts to
        -- by-value still fails here.
        H.equal(occurrences(entry, "get_la_pending_apply = function() return _la_pending_apply end,"), 2)
        H.equal(occurrences(entry, "set_la_pending_apply = function(t) _la_pending_apply = t end,"), 1)
        H.equal(source:find("local _la_pending_apply", 1, true), nil)
        H.equal(occurrences(source, "local _pending = _get_la_pending_apply()"), 1)
        -- Handed over BY REFERENCE: the owner writes these two fields and the
        -- entry's startup verification reads all four off the same table.
        H.truthy(entry:find("net_safe_hook_status = _net_safe_hook_status,", 1, true))
        H.equal(occurrences(source, "_net_safe_hook_status.PUAE = true"), 1)
        H.equal(occurrences(source, "_net_safe_hook_status.AttachmentUtils = true"), 1)
        H.equal(source:find("local _net_safe_hook_status = {", 1, true), nil)
    end)

    H.test("cos attachment spawn sync by-value LA sender is ordering-safe", function()
        -- `_send_la_apply` crosses BY VALUE, which is only correct because the
        -- entry's real assignment executes ABOVE this install call. Pin the
        -- ordering so a future reorder fails here instead of handing over nil.
        local at_decl = entry:find("local _send_la_apply", 1, true)
        local at_assign = entry:find("_send_la_apply = function(unit, slot_name, kind,", 1, true)
        local at_owner = entry:find(owner_install, 1, true)
        H.truthy(at_decl and at_assign and at_owner)
        H.truthy(at_decl < at_assign)
        H.truthy(at_assign < at_owner)
        H.truthy(entry:find("send_la_apply = _send_la_apply,", 1, true))
        -- The owner binds the sender ONCE from deps and keeps the original call
        -- sites byte-identical; it must never re-declare or reassign it.
        H.equal(occurrences(source, "local _send_la_apply"), 1)
        H.truthy(source:find("local _send_la_apply          = deps.send_la_apply", 1, true))
    end)

    -- ------------------------------------------------------------- behaviour
    local hooks = {}
    local mod = {}
    function mod:hook(class_ref, method_name, fn)
        local key = type(class_ref) == "string" and class_ref or "AttachmentUtils"
        hooks[key .. ":" .. method_name] = fn
    end
    function mod:hook_safe(class_ref, method_name, fn) self:hook(class_ref, method_name, fn) end
    function mod:info() end
    function mod:network_send() end

    mod._cos_husk_identity = {
        player_for_unit = function(_pm, unit) return { peer_id = unit and unit.peer } end,
        validate_live_entry = function() return true, "ok", "es_questing_knight" end,
    }
    mod._la_career_for_unit = function() return "es_questing_knight" end

    -- The entry-side local the owner must NOT capture by value. Rebound below,
    -- exactly the way both real drain sites rebind it.
    local entry_pending = {}
    local emits = {}
    local alerts = {}

    local la_equips_by_peer = {
        peer_a = { slot_hat = { kind = "hat", armoury_key = "la_key", vanilla_key = "es_hat_base" } },
    }
    local net_safe_hook_status =
        { CosmeticUtils = false, LoadoutUtils = false, AttachmentUtils = false, PUAE = false }

    local deps = {
        appearance_fade_runtime = {
            install = function() end,
            enroll_husk_attachment = function() end,
        },
        rpc_schema = 2,
        custom_hats = { is_custom_identity = function() return false end },
        gk_set = { resolve_variant = function() return nil end },
        la_bridge = { backend_to_armoury = { la_backend = "la_key" } },
        la_persist = { marker = "la-persist" },
        dbg = function() end,
        dbg_alert = function(fmt) alerts[#alerts + 1] = fmt end,
        is_local_server = function() return false end,
        la_equips_by_peer = la_equips_by_peer,
        la_substitute_name = function(name)
            if name == "la_backend" then return "es_hat_base" end
            return nil
        end,
        la_vanilla_fallback = function() return "es_hat_base" end,
        level_world = function() return nil end,
        local_la_equips = setmetatable({}, { __mode = "k" }),
        local_player_safe = function() return nil end,
        net_safe_hook_status = net_safe_hook_status,
        offhand_selection = {},
        offhand_session_state = { migrate_legacy = function() end },
        resolve_la_variant = function()
            return { new_units = { "units/beings/player/empire_questing_knight/hat" } }, nil
        end,
        send_la_apply = function(unit, slot_name, kind, armoury_key, vanilla_key)
            emits[#emits + 1] = { unit = unit, slot = slot_name, kind = kind,
                                  armoury = armoury_key, vanilla = vanilla_key }
        end,
        get_la_pending_apply = function() return entry_pending end,
    }

    -- The engine surface is installed ONLY for the duration of the install call
    -- and each behaviour test, then restored. These stubs must never leak into
    -- sibling test files.
    local husk_body = { peer = "peer_a" }
    local engine = {
        AttachmentUtils = {},
        Managers = { player = {} },
        Unit = {
            alive = function() return true end,
            -- The husk body skeleton is NOT ready: this is the deferral path.
            has_node = function() return false end,
        },
        ScriptUnit = { has_extension = function() return nil end },
        BackendUtils = { get_item_template = function() return nil end },
        Application = {},
        printf = function() end,
    }
    local function with_engine(body)
        local saved = {}
        for name, stub in pairs(engine) do saved[name] = rawget(_G, name); _G[name] = stub end
        local ok, err = pcall(body)
        for name in pairs(engine) do _G[name] = saved[name] end
        if not ok then error(err, 0) end
    end

    local installed
    with_engine(function()
        installed = assert(loadfile(repo_root .. "/" .. module_relative))().install(mod, deps)
    end)

    H.test("cos attachment spawn sync install registers four hooks and reports success", function()
        H.equal(installed, true)
        H.truthy(hooks["PlayerHuskAttachmentExtension:create_attachment"])
        H.truthy(hooks["PlayerUnitAttachmentExtension:game_object_initialized"])
        H.truthy(hooks["PlayerUnitAttachmentExtension:spawn_resynced_loadout"])
        H.truthy(hooks["AttachmentUtils:hot_join_sync"])
        -- Both registration flags were recorded on the ENTRY-owned table.
        H.equal(net_safe_hook_status.PUAE, true)
        H.equal(net_safe_hook_status.AttachmentUtils, true)
    end)

    H.test("cos attachment spawn sync passes a non-hat slot straight through", function() with_engine(function()
        local delegated = 0
        local function vanilla() delegated = delegated + 1 end
        hooks["PlayerHuskAttachmentExtension:create_attachment"](
            vanilla, { _unit = husk_body }, "slot_skin", { unit = "x" })
        H.equal(delegated, 1)
        H.equal(#entry_pending, 0)
    end) end)

    H.test("cos attachment spawn sync substitutes then re-emits on go-init", function() with_engine(function()
        local slot = { item_data = { name = "la_backend" } }
        local seen_during_vanilla
        local function vanilla(self) seen_during_vanilla = self._attachments.slots.slot_hat.item_data.name end
        local self = { _attachments = { slots = { slot_hat = slot } } }
        hooks["PlayerUnitAttachmentExtension:game_object_initialized"](vanilla, self, husk_body, 7)
        -- Vanilla saw the wire-safe vanilla key ...
        H.equal(seen_during_vanilla, "es_hat_base")
        -- ... the original LA key was restored afterwards ...
        H.equal(slot.item_data.name, "la_backend")
        -- ... and exactly one LA apply was emitted for the slot.
        H.equal(#emits, 1)
        H.equal(emits[1].slot, "slot_hat")
        H.equal(emits[1].kind, "hat")
        H.equal(emits[1].armoury, "la_key")
        H.equal(emits[1].vanilla, "es_hat_base")
        emits = {}
    end) end)

    H.test("cos attachment spawn sync applies the same contract to a resync", function() with_engine(function()
        local item_data = { name = "la_backend" }
        local seen_during_vanilla
        local function vanilla(_self, spawn) seen_during_vanilla = spawn.item_data.name end
        hooks["PlayerUnitAttachmentExtension:spawn_resynced_loadout"](
            vanilla, { _unit = husk_body }, { item_data = item_data, slot_id = "slot_hat" })
        H.equal(seen_during_vanilla, "es_hat_base")
        H.equal(item_data.name, "la_backend")
        H.equal(#emits, 1)
        H.equal(emits[1].kind, "hat")
        emits = {}
    end) end)

    H.test("cos attachment spawn sync defers instead of dropping an unready hat", function() with_engine(function()
        local delegated = 0
        local function vanilla() delegated = delegated + 1 end
        hooks["PlayerHuskAttachmentExtension:create_attachment"](
            vanilla, { _unit = husk_body }, "slot_hat",
            { unit = "units/beings/player/empire_questing_knight/base" })
        -- Vanilla still runs UNPATCHED, so the wearer's real hat shows this frame.
        H.equal(delegated, 1)
        -- ... and the LA re-apply is queued rather than dropped.
        H.equal(#entry_pending, 1)
        H.equal(entry_pending[1][1], "peer_a")
        H.equal(entry_pending[1][2], "slot_hat")
        H.equal(entry_pending[1][3], "hat")
        H.equal(entry_pending[1][4], "la_key")
        H.truthy(#alerts > 0)
    end) end)

    H.test("cos attachment spawn sync deferral follows a REBOUND entry queue", function() with_engine(function()
        -- Reproduce what both real drain sites do: keep the survivors in a NEW
        -- table and assign it over the entry local. An install-time by-value
        -- hand-off would still be holding `discarded` after this line.
        local discarded = entry_pending
        entry_pending = {}
        local function vanilla() end
        hooks["PlayerHuskAttachmentExtension:create_attachment"](
            vanilla, { _unit = husk_body }, "slot_hat",
            { unit = "units/beings/player/empire_questing_knight/base" })
        H.equal(#entry_pending, 1, "deferral must land in the queue the entry holds NOW")
        H.equal(#discarded, 1, "the discarded queue must not have grown")
        H.equal(entry_pending[1][4], "la_key")
    end) end)
end
