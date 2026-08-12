-- Boundary + behaviour guard for the #1159 live equipment-assembly owner
-- (_cos_equipment_assembly.lua).
--
-- Two load-bearing properties this file exists to pin, both of them signals the
-- fix cannot move:
--
--   1. THE BRACKET. GearUtils.create_equipment and BackendUtils.get_item_units
--      are not merely adjacent: create_equipment sets `_in_create_equipment`
--      around its vanilla call and get_item_units - which vanilla calls from
--      INSIDE it - reads that flag to suppress the browse-time offhand override
--      on the live body (#150). The behaviour tests drive the OUTER hook and
--      assert the INNER hook's decision changes, then assert it changes back
--      after the wrap returns. Splitting the pair, or handing the flag across a
--      module boundary by value, fails those two tests and nothing else.
--
--   2. THE TWO ACCESSORS. The husk-wield owner and the entry-owned
--      `_active_customization_backend_id` both expose values that are REBOUND.
--      Each has a matched pair of tests: the first proves the owner sees
--      a value, the second REBINDS the entry-side local the way the real writer
--      does and proves the owner sees the NEW one. Converting either getter back
--      into an install-time value still passes the first test of each pair and
--      fails only the second - which is exactly the silent failure mode (a husk
--      lane frozen on the nil the local held at load).
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
        "cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_cos_equipment_assembly.lua"
    local source = read(module_relative)
    local husk_wield = read(
        "cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_cos_husk_wield_runtime.lua")
    local owner_install =
        'mod:dofile("scripts/mods/cosmetics_tweaker/_cos_equipment_assembly").install(mod, {'

    H.test("cos equipment assembly installs once at the former create_equipment site", function()
        H.equal(occurrences(entry, owner_install), 1)
        local at_owner = entry:find(owner_install, 1, true)
        -- The install sits at the LATER of the two former registration sites.
        -- Installing at the earlier one would have captured a global nil for the
        -- paint helper declared below it (the v0.9.0.11 forward-reference class).
        local at_paint_decl = entry:find("local function _apply_la_offhand_to_units", 1, true)
        local at_preview = entry:find(
            'mod:dofile("scripts/mods/cosmetics_tweaker/_cos_preview_runtime").install', 1, true)
        local at_probe = entry:find(
            'mod:dofile("scripts/mods/cosmetics_tweaker/_cos_518_probe")', 1, true)
        H.truthy(at_paint_decl and at_preview and at_probe)
        H.truthy(at_probe < at_owner)
        H.truthy(at_paint_decl < at_owner)
        H.truthy(at_owner < at_preview)
    end)

    H.test("cos equipment assembly owns both seams exclusively", function()
        -- VMF silently drops a second registration on the same (Class, method)
        -- pair, so a re-inlined copy would shadow the owner rather than fail
        -- loudly. The entry-side absence is the real guard.
        H.equal(occurrences(entry, 'mod:hook(BackendUtils, "get_item_units"'), 0)
        H.equal(occurrences(source, 'mod:hook(BackendUtils, "get_item_units"'), 1)
        H.equal(occurrences(entry, 'mod:hook("GearUtils", "create_equipment"'), 0)
        H.equal(occurrences(source, 'mod:hook("GearUtils", "create_equipment"'), 1)
        -- BackendUtils is a PLAIN TABLE: the string form silently never
        -- registers, so the nil-guarded table form must survive the move intact.
        H.equal(occurrences(source, "if BackendUtils then"), 1)
        H.equal(occurrences(source, 'mod:hook("BackendUtils"'), 0)
        -- Exactly two hooks move; the owner adds no third seam of any kind.
        H.equal(occurrences(source:gsub("%-%-[^\n]*", ""), "mod:hook("), 2)
        H.equal(occurrences(source:gsub("%-%-[^\n]*", ""), "mod:hook_safe("), 0)
        H.equal(occurrences(source:gsub("%-%-[^\n]*", ""), "mod:hook_origin("), 0)
    end)

    H.test("cos equipment assembly privatises the create_equipment bracket flag", function()
        -- The whole reason the pair travels together: this flag has exactly one
        -- writer and one reader, and both are now inside the owner.
        H.equal(occurrences(source, "local _in_create_equipment = false"), 1)
        H.equal(occurrences(entry, "local _in_create_equipment"), 0)
        H.equal(occurrences(entry, "_in_create_equipment = true"), 0)
        H.equal(occurrences(entry, "_in_create_equipment = _prev_in_create_equipment"), 0)
        H.equal(occurrences(source, "_in_create_equipment = true"), 1)
        H.equal(occurrences(source, "_in_create_equipment = _prev_in_create_equipment"), 1)
    end)

    H.test("cos equipment assembly crossing state uses the correct hand-off kind", function()
        -- REBOUND by the husk owner -> must cross through its getter, and the
        -- equipment owner must never shadow it with persistent state.
        H.equal(occurrences(entry,
            "return HUSK_WIELD_RUNTIME.current(mod)"), 1)
        H.equal(occurrences(entry, "local _current_husk_wield = nil"), 0)
        H.equal(occurrences(husk_wield, "state.current = {"), 1)
        H.equal(occurrences(husk_wield, "state.current = previous"), 1)
        H.equal(occurrences(source, "local _current_husk_wield = nil"), 0)
        H.equal(occurrences(source, "local _current_husk_wield = _get_current_husk_wield()"), 1)
        H.equal(occurrences(entry, "local _active_customization_backend_id = nil"), 1)
        H.equal(occurrences(source, "local _active_customization_backend_id = nil"), 0)
        H.equal(occurrences(source, "_get_active_customization_backend_id()"), 1)
        H.truthy(source:find("deps.get_active_customization_backend_id", 1, true))
        H.truthy(source:find("deps.get_current_husk_wield", 1, true))
        -- Both getters resolve ONCE per call, so the two hook bodies keep the
        -- original text at every one of their read sites.
        H.truthy(occurrences(source, "_current_husk_wield") > 20)
    end)

    H.test("cos equipment assembly by-value hand-offs are ordering-safe", function()
        -- These cross BY VALUE, which is only correct because the entry binds
        -- each of them ABOVE the install call. Pin the ordering so a future
        -- reorder fails here instead of handing over nil.
        local at_owner = entry:find(owner_install, 1, true)
        for _, anchor in ipairs({
            "local function _apply_la_offhand_to_units",
            "_cos_resolve_composed_appearance =\n    _cos_item_presentation_runtime.resolve_composed_appearance",
            "local _la_equips_by_peer = {}",
            "local function _get_offhand_options",
            "local _override_package_ready = _cos_offhand_catalog.override_package_ready",
        }) do
            local at = entry:find(anchor, 1, true)
            H.truthy(at, anchor)
            H.truthy(at < at_owner, anchor)
        end
        -- The paint helper stays entry-owned and is shared with the preview
        -- runtime; the owner must not have taken a private copy of it.
        H.equal(occurrences(source, "local function _apply_la_offhand_to_units"), 0)
        H.truthy(entry:find("apply_la_offhand_to_units = _apply_la_offhand_to_units,", 1, true))
    end)

    H.test("cos equipment assembly does not overlap its sibling owners", function()
        -- Comments are stripped: the header NAMES the sibling owners it composes
        -- with, and that prose must not be mistaken for a registration.
        local code = source:gsub("%-%-[^\n]*", "")
        -- The husk WEAPON wield owner sets the context this owner reads; it is
        -- not a unit-resolution seam and must not return to the entry.
        H.equal(occurrences(entry,
            'mod:hook("SimpleHuskInventoryExtension", "_wield_slot"'), 0)
        H.equal(occurrences(husk_wield,
            'mod:hook("SimpleHuskInventoryExtension", "_wield_slot"'), 1)
        H.equal(occurrences(code, "SimpleHuskInventoryExtension"), 0)
        -- Previewer spawn seams belong to _cos_preview_runtime; attachment spawn
        -- seams to _cos_attachment_spawn_sync; the customization screen to the
        -- view lifecycle owner. This owner registers none of them.
        for _, foreign in ipairs({
            "HeroPreviewer", "MenuWorldPreviewer", "LootItemUnitPreviewer",
            "PlayerHuskAttachmentExtension", "PlayerUnitAttachmentExtension",
            "AttachmentUtils", "HeroWindowItemCustomization", "UIRenderer",
        }) do
            H.equal(occurrences(code, foreign), 0, foreign)
        end
        -- No transport, no commands, no lifecycle, and no re-dofile of a stateful
        -- sibling (mod:dofile is not a singleton -- that builds a second instance).
        H.equal(occurrences(code, "network_register"), 0)
        H.equal(occurrences(code, "network_send"), 0)
        H.equal(occurrences(code, "mod:command("), 0)
        H.equal(occurrences(code, "mod.update"), 0)
        H.equal(occurrences(code, "mod.on_"), 0)
        H.equal(occurrences(code, 'mod:dofile("'), 0)
        H.truthy(source:find("Owned by:", 1, true))
        H.truthy(source:find("Consumed via:", 1, true))
    end)

    -- ------------------------------------------------------------- behaviour
    local hooks = {}
    local mod = {}
    function mod:hook(class_ref, method_name, fn)
        local key = type(class_ref) == "string" and class_ref or "BackendUtils"
        hooks[key .. ":" .. method_name] = fn
    end
    function mod:hook_safe(class_ref, method_name, fn) self:hook(class_ref, method_name, fn) end
    function mod:echo() end
    function mod:info() end

    -- Entry-side locals the owner must NOT capture by value. Both are rebound
    -- below, exactly the way the real entry writers rebind them.
    local entry_husk_wield = nil
    local entry_active_bid = "bid-A"

    local deus_yield = false
    local seen_active_bid, traces, paints = {}, {}, {}

    mod._la_deus_weapon_yield = function() return deus_yield end
    mod._cos_husk_identity = {
        entry_matches_career = function() return true, "ok" end,
    }
    mod._dual_offhand_unit_allowed = function() return true end
    mod._la_instance_policy = {
        resolve_preview_backend_id = function(backend_id, _item_type, active_bid)
            seen_active_bid[#seen_active_bid + 1] = active_bid
            return backend_id, "exact"
        end,
        selection_owned = function() return true end,
    }
    local glow_calls = {}
    mod._cos = {
        bind_glow_unit = function() glow_calls[#glow_calls + 1] = "bind" end,
        scale_units = function() glow_calls[#glow_calls + 1] = "scale" end,
        offset_units = function() glow_calls[#glow_calls + 1] = "offset" end,
        glow_owner_peer_for_unit = function() return "peer_local" end,
        apply_glow_override = function() glow_calls[#glow_calls + 1] = "glow" end,
        apply_composed_shield_glow = function() glow_calls[#glow_calls + 1] = "shield_glow" end,
    }
    mod._cos518_husk_miss = function() end

    local offhand_selection = {
        ["bid-A"] = { left_hand_unit = { unit = "units/override_shield" } },
    }
    local la_equips_by_peer = {}
    local mh_order = {}

    local deps = {
        gk_set = { SHIELD_SKIN_KEY = "gk_shield_skin", SHIELD_VARIANT_KEY = "gk_shield",
                   apply_variant_to_unit = function() end },
        glow_picker = { restore_runtime_for = function() return false end },
        la_bridge = { resolve_texture_receiver = function() return nil end },
        mh_embed = {
            dormant = false,
            replace_textures = function() mh_order[#mh_order + 1] = "replace" end,
            add_particles = function() mh_order[#mh_order + 1] = "particles" end,
        },
        probe = nil,
        apply_la_offhand_to_units = function(_world, item_data, _units, _has_skin, _bid, context)
            paints[#paints + 1] = { name = item_data and item_data.name, context = context }
        end,
        glow_log = function() end,
        resolve_composed_appearance = function() return nil end,
        dbg = function() end,
        trace = function(fmt) traces[#traces + 1] = fmt end,
        get_offhand_options = function()
            return { left_hand_unit = { "units/override_shield" } }
        end,
        la_equips_by_peer = la_equips_by_peer,
        offhand_selection = offhand_selection,
        offhand_session_state = { migrate_legacy = function() end },
        override_package_ready = function() return true end,
        resolve_authored_offhand_mesh = function()
            return "units/la_shield", "units/la_shield_3p", true
        end,
        resolve_authored_offhand_variant = function()
            return { kind = "unit", new_units = { "units/la_shield", "units/la_shield_3p" } }, "authored"
        end,
        get_current_husk_wield = function() return entry_husk_wield end,
        get_active_customization_backend_id = function() return entry_active_bid end,
    }

    -- The engine surface is installed ONLY for the install call and each
    -- behaviour test, then restored. These stubs must never leak into siblings.
    local engine = {
        BackendUtils = {},
        Managers = {},
        ItemMasterList = {},
        Application = { can_get = function() return true end },
        Unit = { alive = function() return true end },
        printf = false,
        get_mod = function() return nil end,
    }
    local function with_engine(body)
        local saved = {}
        for name, stub in pairs(engine) do
            saved[name] = rawget(_G, name)
            _G[name] = (stub ~= false) and stub or nil
        end
        local ok, err = pcall(body)
        for name in pairs(engine) do _G[name] = saved[name] end
        if not ok then error(err, 0) end
    end

    with_engine(function()
        assert(loadfile(repo_root .. "/" .. module_relative))().install(mod, deps)
    end)

    local ITEM = { item_type = "es_sword_shield", backend_id = "bid-A",
                   template = "es_sword_shield", name = "es_sword_shield",
                   skin = "es_sword_shield_skin_01" }

    local function resolve(vanilla_result)
        local function vanilla() return vanilla_result end
        return hooks["BackendUtils:get_item_units"](
            vanilla, ITEM, "bid-A", "es_sword_shield_skin_01", "es_knight")
    end

    H.test("cos equipment assembly install registers exactly the two seams", function()
        H.truthy(hooks["BackendUtils:get_item_units"])
        H.truthy(hooks["GearUtils:create_equipment"])
        H.truthy(mod._cos_equipment_assembly_owner)
    end)

    H.test("cos equipment assembly applies a committed offhand pick outside the wrap",
    function() with_engine(function()
        local result = resolve({ left_hand_unit = "units/base_shield" })
        H.equal(result.left_hand_unit, "units/override_shield")
    end) end)

    -- --------- bracket: the outer hook's flag changes the inner hook's decision
    H.test("cos equipment assembly suppresses the browse override inside the wrap",
    function() with_engine(function()
        local inner
        local function vanilla_create()
            -- Vanilla create_equipment calls get_item_units from INSIDE the wrap.
            inner = resolve({ left_hand_unit = "units/base_shield" })
            return { skin = "es_sword_shield_skin_01",
                     left_unit_1p = "l1", left_unit_3p = "l3",
                     right_unit_1p = "r1", right_unit_3p = "r3" }
        end
        hooks["GearUtils:create_equipment"](vanilla_create, "world", "slot_melee", ITEM,
            "u1p", "u3p", false, nil, nil, nil, nil, nil, "es_knight")
        -- #150: the live body must keep its committed mesh while the
        -- customization screen is browsing the same backend id.
        H.equal(inner.left_hand_unit, "units/base_shield")
    end) end)

    H.test("cos equipment assembly restores the bracket after the wrap returns",
    function() with_engine(function()
        local function vanilla_create() return { skin = "es_sword_shield_skin_01" } end
        hooks["GearUtils:create_equipment"](vanilla_create, "world", "slot_melee", ITEM,
            "u1p", "u3p", false, nil, nil, nil, nil, nil, "es_knight")
        -- Same call as the passing case above: if the flag leaked, this would now
        -- be suppressed too and the live body would never pick the override up.
        local result = resolve({ left_hand_unit = "units/base_shield" })
        H.equal(result.left_hand_unit, "units/override_shield")
    end) end)

    -- --------- accessor pair 1: the mutable customization backend id
    H.test("cos equipment assembly reads the customization backend id per call",
    function() with_engine(function()
        seen_active_bid = {}
        resolve({ left_hand_unit = "units/base_shield" })
        H.equal(seen_active_bid[1], "bid-A")
    end) end)

    H.test("cos equipment assembly follows a REBOUND customization backend id",
    function() with_engine(function()
        -- Reproduce what the view-lifecycle owner and the offhand picker do
        -- through their setters: assign a new value over the entry local. An
        -- install-time by-value hand-off would still report "bid-A" here.
        seen_active_bid = {}
        entry_active_bid = "bid-B"
        resolve({ left_hand_unit = "units/base_shield" })
        H.equal(seen_active_bid[1], "bid-B")
        entry_active_bid = "bid-A"
    end) end)

    -- --------- accessor pair 2: the husk wield context
    H.test("cos equipment assembly takes no husk lane without a husk context",
    function() with_engine(function()
        la_equips_by_peer.peer_a = {
            es_sword_shield = { kind = "offhand", armoury_key = "la_key",
                                hand_field = "left_hand_unit" },
        }
        local result = resolve({ left_hand_unit = "units/base_shield" })
        -- No husk context: this is the LOCAL lane, so the committed pick wins.
        H.equal(result.left_hand_unit, "units/override_shield")
    end) end)

    H.test("cos equipment assembly follows a REBOUND husk wield context",
    function() with_engine(function()
        -- The entry's husk _wield_slot wrap sets this stack-style before calling
        -- vanilla. A frozen install-time value would leave it nil and the husk
        -- would silently render the wearer's base shield to every peer.
        entry_husk_wield = { wearer_peer = "peer_a", slot_name = "slot_melee",
                             career_name = "es_knight" }
        local result = resolve({ left_hand_unit = "units/base_shield" })
        H.equal(result.left_hand_unit, "units/la_shield")
        -- ... and the restore half of the same bracket puts the local lane back.
        entry_husk_wield = nil
        local after = resolve({ left_hand_unit = "units/base_shield" })
        H.equal(after.left_hand_unit, "units/override_shield")
        la_equips_by_peer.peer_a = nil
    end) end)

    H.test("cos equipment assembly yields the husk mesh lane to a deus roll",
    function() with_engine(function()
        -- A backend id with NO committed pick, so only the husk lane can move
        -- the mesh here (#518: a deus-generated instance keeps its rolled skin).
        local deus_item = { item_type = "es_sword_shield", backend_id = "bid-Z",
                            template = "es_sword_shield", name = "es_sword_shield",
                            skin = "es_sword_shield_skin_01" }
        local function resolve_deus()
            local function vanilla() return { left_hand_unit = "units/base_shield" } end
            return hooks["BackendUtils:get_item_units"](
                vanilla, deus_item, "bid-Z", "es_sword_shield_skin_01", "es_knight")
        end
        entry_husk_wield = { wearer_peer = "peer_a", slot_name = "slot_melee",
                             career_name = "es_knight" }
        la_equips_by_peer.peer_a = {
            es_sword_shield = { kind = "offhand", armoury_key = "la_key",
                                hand_field = "left_hand_unit" },
        }
        H.equal(resolve_deus().left_hand_unit, "units/la_shield")
        deus_yield = true
        H.equal(resolve_deus().left_hand_unit, "units/base_shield")
        deus_yield = false
        entry_husk_wield = nil
        la_equips_by_peer.peer_a = nil
    end) end)

    H.test("cos equipment assembly runs the MH embed before the vanilla spawn",
    function() with_engine(function()
        mh_order, paints, glow_calls = {}, {}, {}
        local function vanilla_create()
            mh_order[#mh_order + 1] = "vanilla"
            return { skin = "es_sword_shield_skin_01",
                     left_unit_1p = "l1", left_unit_3p = "l3",
                     right_unit_1p = "r1", right_unit_3p = "r3" }
        end
        hooks["GearUtils:create_equipment"](vanilla_create, "world", "slot_melee", ITEM,
            "u1p", "u3p", false, nil, nil, nil, nil, nil, "es_knight")
        -- Original MH-embed hook order: replace textures, add particles, THEN
        -- the vanilla spawn.
        H.equal(mh_order[1], "replace")
        H.equal(mh_order[#mh_order], "vanilla")
        -- ... and the post-spawn lane still runs scale, offset, LA paint, glow.
        H.equal(#paints, 1)
        H.equal(paints[1].context, "ingame")
        H.truthy(#glow_calls > 0)
    end) end)
end
