-- Pin for the issue #518 Chaos Wastes deus-yield boundary (cosmetics_tweaker).
-- Deus weapons are GENERATED instances that clone the base item's template and
-- re-roll item.skin per rarity (deus_weapon_generation.lua:185-202, :246-249,
-- :318-321), so a keep-committed per-TEMPLATE LA pick leaked onto every CW
-- weapon and stomped the rolled upgrade skin. The shipped fix yields LA weapon
-- visuals ONLY inside an active expedition mission - the deus mechanism ALSO
-- owns the Pilgrimage Chamber ("inn_deus") and the route/shrine map
-- ("map_deus"), where LA must stay live (the 0.9.89-dev staging regression,
-- deus_mechanism.lua:28-35,49-59). This suite executes the extracted boundary
-- helper against the full context truth table and pins every weapon-side
-- consumer gate plus the in-game rt check so the boundary cannot silently
-- regress in either direction. See LA_SYNC_MODEL.md section 6.10.
return function(H, repo_root)
    local root = repo_root .. "/cosmetics_tweaker/scripts/mods/cosmetics_tweaker/"

    local function read(name)
        local f = assert(io.open(root .. name, "rb"))
        local value = f:read("*a")
        f:close()
        return value
    end

    local main = read("cosmetics_tweaker.lua")
    local checks = read("_cos_runtime_checks.lua")
    -- #1159: the BackendUtils.get_item_units seam that resolves the yield gate
    -- ONCE per call, and the GearUtils.create_equipment wrap whose flag the
    -- live-body gate reads, moved verbatim into the equipment-assembly owner.
    -- The gates below are pinned on the owner, with entry-side absence asserted,
    -- so a re-inlined copy fails instead of silently shadowing the owner.
    local assembly = read("_cos_equipment_assembly.lua")
    -- #1159: the unified apply core (_apply_la_on_unit) - the TERMINAL funnel
    -- every weapon-side apply trigger runs through - moved verbatim into the
    -- apply/revert owner. Same treatment: the gate is pinned on the owner and
    -- asserted absent from the entry.
    local apply_runtime = read("_cos_la_apply_runtime.lua")

    H.test("Cos #518 yield boundary is mechanism AND game mode (staging never yields)", function()
        local body = main:match(
            "mod%._la_weapon_yield_for_context%s*=%s*(function%s*%b().-\nend)")
        H.truthy(body, "_la_weapon_yield_for_context extraction failed (renamed/moved?)")
        local fn = assert(loadstring("return " .. body))()
        H.equal(fn("deus", "deus"), true, "active expedition mission must yield")
        H.equal(fn("deus", "inn_deus"), false, "Pilgrimage Chamber must keep LA live")
        H.equal(fn("deus", "map_deus"), false, "route/shrine map must keep LA live")
        H.equal(fn("adventure", "deus"), false, "non-deus mechanism must never yield")
        H.equal(fn("deus", nil), false, "unresolvable game mode fails safe (no yield)")
        H.equal(fn(nil, nil), false)
    end)

    H.test("Cos #518 early-load level fallback classifies the deus node types", function()
        -- Vanilla reserves exactly morris_hub (inn_deus) and dlc_morris_map
        -- (map_deus); every other deus level is an ingame node
        -- (deus_mechanism.lua:49-59). The fallback must keep that split so a
        -- mission cannot briefly repaint LA while GameModeManager is starting.
        H.truthy(main:find('if ok and level_key == "morris_hub" then', 1, true))
        H.truthy(main:find('game_mode_key = "inn_deus"', 1, true))
        H.truthy(main:find('elseif ok and level_key == "dlc_morris_map" then', 1, true))
        H.truthy(main:find('game_mode_key = "map_deus"', 1, true))
        H.truthy(main:find('game_mode_key = "deus"', 1, true))
    end)

    H.test("Cos #518 every weapon-side apply/paint path routes through the yield gate", function()
        -- Terminal funnel: every apply trigger (RPC recv, reconcile, transition
        -- walk, pending drain, husk/local wield re-paint) runs _apply_la_on_unit;
        -- weapon-side kinds gate there, hats/armor pass untouched.
        H.truthy(apply_runtime:find(
            'if (kind == "offhand" or kind == "illusion") and mod._la_deus_weapon_yield() then',
            1, true), "terminal weapon-side yield gate missing from _apply_la_on_unit")
        H.equal(main:find(
            'if (kind == "offhand" or kind == "illusion") and mod._la_deus_weapon_yield() then',
            1, true), nil,
            "the terminal apply gate must live with its apply core, not in the entry")
        H.truthy(apply_runtime:find("local function _apply_la_on_unit(", 1, true),
            "the apply core must live in _cos_la_apply_runtime")
        H.equal(main:find("local function _apply_la_on_unit(", 1, true), nil,
            "the entry must not re-declare the apply core")
        -- get_item_units resolves the gate ONCE per call and gates the husk LA
        -- swap, the husk vanilla-offhand swap, and the live-body selection.
        H.truthy(assembly:find('local _deus_yield = mod._la_deus_weapon_yield()', 1, true),
            "get_item_units single-resolution gate missing")
        H.equal(main:find('local _deus_yield = mod._la_deus_weapon_yield()', 1, true), nil,
            "the get_item_units gate must live with its hook, not in the entry")
        H.truthy(assembly:find('and not _deus_yield', 1, true),
            "husk mesh-override deus gate missing")
        H.truthy(assembly:find('not (_deus_yield and _in_create_equipment)', 1, true),
            "live-body gate must suppress only create_equipment, not previews")
        -- The bracket flag is now PRIVATE to the assembly owner's install scope:
        -- the entry may still name it in prose, but must declare and write it
        -- nowhere. Both hooks that share it live in the owner or the pairing has
        -- been broken.
        H.equal(main:find("local _in_create_equipment", 1, true), nil,
            "the create_equipment bracket flag is private to the assembly owner")
        H.equal(main:find("_in_create_equipment = true", 1, true), nil,
            "only the assembly owner may set the create_equipment bracket flag")
        H.truthy(assembly:find("local _in_create_equipment = false", 1, true),
            "the assembly owner must own the bracket flag declaration")
        -- In-game LA paint skips inside a run; preview contexts stay live.
        H.truthy(main:find('if context == "ingame" and mod._la_deus_weapon_yield() then', 1, true),
            "ingame paint gate missing")
        -- Pending-apply retries treat deus-yield as terminal (no spin-to-deadline).
        H.truthy(main:find('reason ~= "deus-yield"', 1, true),
            "pending drain must treat deus-yield as a terminal reason")
        -- Local wield re-apply (the observed stomper) is gated too.
        H.truthy(main:find('and not mod._la_deus_weapon_yield()', 1, true),
            "local wield re-apply deus gate missing")
    end)

    H.test("Cos #518 in-game boundary check pins all three deus contexts", function()
        H.truthy(checks:find("cos_la_deus_yield_active_mission_only", 1, true),
            "in-game boundary rt check missing")
        H.truthy(checks:find('{ "deus", "inn_deus", false', 1, true),
            "Pilgrimage Chamber row missing from the in-game truth table")
        H.truthy(checks:find('{ "deus", "map_deus", false', 1, true),
            "route/shrine map row missing from the in-game truth table")
        H.truthy(checks:find('{ "deus", "deus", true', 1, true),
            "active-mission row missing from the in-game truth table")
    end)

    -- #518 diagnostics-armed probe contract. The pinned falsifier is "the log
    -- records the wielded weapon with a non-empty skin= value"; these tests
    -- lock the bounded emitter semantics (printf-only, [cos:518] prefix,
    -- dedupe, 16-record per-channel cap) and the three emit sites (owner
    -- wield probe, local paint-skip, husk-side variant miss). The emitter and
    -- probe helpers live in the _cos_518_probe.lua owner module (the entry
    -- file sits at its decomposition ceiling); the entry keeps the wiring.
    local probe_module = read("_cos_518_probe.lua")

    local function extract_emitter()
        local body = probe_module:match(
            "mod%._cos518_emit%s*=%s*(function%s*%b().-\nend)")
        H.truthy(body, "mod._cos518_emit extraction failed (renamed/moved?)")
        return body
    end

    local function build_emitter(env_printf)
        local body = extract_emitter()
        local chunk = assert(loadstring("return " .. body))
        local stub_mod = {}
        local env = {
            mod = stub_mod,
            rawget = rawget,
            _G = env_printf and { printf = env_printf } or {},
        }
        setfenv(chunk, env)
        return chunk(), stub_mod
    end

    H.test("Cos #518 probe emitter is printf-guarded, prefixed, chat-free", function()
        local body = extract_emitter()
        H.truthy(body:find('rawget(_G, "printf")', 1, true),
            "emitter must guard on rawget(_G, \"printf\")")
        H.truthy(body:find('"[cos:518] " .. fmt', 1, true),
            "emitter must prepend the [cos:518] prefix")
        H.equal(body:find("echo", 1, true), nil,
            "emitter must never route through chat/echo")
        local lines = {}
        local emit = build_emitter(function(f, ...)
            lines[#lines + 1] = string.format(f, ...)
        end)
        H.equal(emit("wield", "k1", "OWNER-WIELD item=%s skin=%s", "sword", "skin_red"), true)
        H.equal(#lines, 1)
        H.truthy(lines[1]:find("[cos:518] ", 1, true) == 1,
            "emitted line must start with the [cos:518] prefix")
        H.truthy(lines[1]:find("skin=skin_red", 1, true),
            "emitted line must carry the formatted skin= value")
    end)

    H.test("Cos #518 probe emitter dedupes per key and caps at 16 per channel", function()
        local lines = {}
        local emit, stub_mod = build_emitter(function(f, ...)
            lines[#lines + 1] = string.format(f, ...)
        end)
        H.equal(emit("wield", "item_a|skin_1", "r=%s", "a"), true)
        H.equal(emit("wield", "item_a|skin_1", "r=%s", "a"), false,
            "duplicate (item,skin) key must not re-emit")
        H.equal(#lines, 1)
        for i = 2, 20 do
            emit("wield", "item_a|skin_" .. i, "r=%d", i)
        end
        H.equal(#lines, 16, "wield channel must cap at 16 records")
        H.equal(stub_mod._cos518_probe_state.wield.count, 16)
        H.equal(emit("wield", "item_fresh|skin_fresh", "r=%s", "x"), false,
            "capped channel must refuse fresh keys")
        -- Channels are independently bounded: a capped wield channel must not
        -- starve the paint-skip / husk-miss channels.
        H.equal(emit("paint-skip", "bid-1", "r=%s", "b"), true)
        H.equal(#lines, 17)
    end)

    H.test("Cos #518 probe emitter is inert without engine printf", function()
        local emit, stub_mod = build_emitter(nil)
        H.equal(emit("wield", "k", "r=%s", "a"), false)
        H.equal(stub_mod._cos518_probe_state, nil,
            "no printf must mean no state mutation")
    end)

    H.test("Cos #518 owner-wield probe rides the single local _wield_slot hook", function()
        -- Merge-into-existing-hook doctrine: exactly ONE registration on
        -- (SimpleInventoryExtension, _wield_slot) - VMF drops a second.
        local _, hook_count = main:gsub(
            'mod:hook_safe%("SimpleInventoryExtension", "_wield_slot"', "")
        H.equal(hook_count, 1,
            "expected exactly one SimpleInventoryExtension._wield_slot hook")
        H.truthy(main:find('mod:dofile("scripts/mods/cosmetics_tweaker/_cos_518_probe")', 1, true),
            "probe module not wired by the entry")
        H.truthy(main:find('mod._cos518_owner_wield(slot_data, wielded_slot)', 1, true),
            "owner-wield probe call missing from the local _wield_slot hook body")
        H.truthy(probe_module:find('mod._cos518_emit("wield"', 1, true),
            "owner-wield probe emit site missing")
        H.truthy(probe_module:find(
            '"OWNER-WIELD slot=%s item=%s skin=%s deus_yield=%s"', 1, true),
            "owner-wield probe must log item key + resolved skin + yield verdict")
        H.truthy(probe_module:find(
            'tostring(item_key) .. "|" .. tostring(skin)', 1, true),
            "owner-wield probe must dedupe per (item,skin)")
        H.truthy(probe_module:find('mechanism_name ~= "deus" then return', 1, true),
            "owner-wield probe must gate on the Chaos Wastes mechanism")
    end)

    H.test("Cos #518 failure-path decisions are promoted to printf, _dbg retained", function()
        -- Local paint skip (was _dbg-only at the ingame deus gate).
        H.truthy(main:find('mod._cos518_paint_skip(bid)', 1, true),
            "paint-skip promotion call missing")
        H.truthy(probe_module:find('mod._cos518_emit("paint-skip"', 1, true),
            "paint-skip emit site missing")
        H.truthy(main:find(
            '_dbg("[LA paint] skip: deus run - CW upgrade cosmetics win (#518) bid=%s"',
            1, true), "paint-skip _dbg line must be retained")
        -- Husk-side authored-variant miss (was _dbg-only).
        H.truthy(assembly:find('mod._cos518_husk_miss(entry.armoury_key', 1, true),
            "husk-miss promotion call missing")
        H.equal(main:find('mod._cos518_husk_miss(', 1, true), nil,
            "the husk-miss probe travels with the get_item_units seam")
        H.truthy(probe_module:find('mod._cos518_emit("husk-miss"', 1, true),
            "husk-miss emit site missing")
        H.truthy(assembly:find(
            '_dbg("[husk-mesh-swap] miss: authored variant %s unavailable"',
            1, true), "husk-miss _dbg line must be retained")
    end)
end
