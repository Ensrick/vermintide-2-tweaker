-- Actual entry, retained constructors, actor/runtime, resource owner and native
-- caller bodies. Engine extension/package hosts are ordinary recording values.
-- The optional sibling GearUtils case is native source provenance, not game/VMF.
return function(H, root)
    local CP = "/character_weapon_variants/scripts/mods/character_weapon_variants/"
    local function read(path)
        local file = assert(io.open(path, "rb"))
        local source = file:read("*a"); file:close()
        return source:gsub("\r\n", "\n")
    end
    local function load(name, env)
        local chunk = assert(loadfile(root .. CP .. name .. ".lua"))
        if env then setfenv(chunk, env) end
        return chunk()
    end
    local function pack(...) return { n = select("#", ...), ... } end
    local function span(source, first, last)
        local a = assert(source:find(first, 1, true), "actual start missing")
        H.equal(source:find(first, a + 1, true), nil, "actual start unique")
        local b = assert(source:find(last, a + #first, true), "actual end missing")
        return source:sub(a, b - 1)
    end
    local entry = read(root .. CP .. "character_weapon_variants.lua")
    local quiet = setmetatable({ test = function() end, test_if = function() end }, { __index = H })
    local Actors = assert(loadfile(root .. "/qa/lua/tests/test_cwv_sword_actor_admission.lua"))()(quiet, root)
    local F = assert(loadfile(root .. "/qa/lua/fixtures/cwv_mace_sword_construction_harness.lua"))()
    local NativeBoot = assert(loadfile(root .. "/qa/lua/fixtures/cwv_mace_sword_native_boot.lua"))()
    local native_root = root .. "/../Vermintide-2-Source-Code"
    local RESOURCE = "units/beings/player/first_person_base/state_machines/melee/1h_hammer"
    local TEMPLATE = "cwv_645_mace_sword_style"
    local function fixture(config)
        config = config or {}
        local c = F.new(H, root, config)
        if not config.omit599 then
            c.state.mace_hammer_identity, c.state.mace_hammer_identity_policy = c.mhi_state, c.mhi_policy
        end
        if config.career_action then
            -- Same real shared protocol already covered by the published Sword
            -- suite, before this test's actual serial family constructors.
            local name = "action_career_es_4"
            c.env.ActionTemplates[name] = config.career_action
            local careers = { es_questingknight = { activated_ability = { { action_name = name } } } }
            for _, donor in ipairs({ "one_handed_hammer_template_1", "one_handed_swords_template_1" }) do
                H.equal(c.integration.install(c.env.Weapons[donor], { "es_questingknight" },
                    careers, c.env.ActionTemplates, "character_weapon_variants").ok, true)
            end
        end
        local policy_env = setmetatable({}, { __index = _G })
        local s = Actors.fixture(policy_env, c)
        s.om, s.hooks, s.loads, s.refs = c.state, {}, {}, {}
        s.om.combat_styles, s.om.style_actor_admission = s.runtime, s.actor
        policy_env.Unit, policy_env.ScriptUnit = s.units, s.script
        local slot_name = config.slot_name or "slot_melee"
        if slot_name == "slot_ranged" then
            local career = { name = "es_questingknight", profile_name = "empire_soldier" }
            s.careers.es_questingknight, s.profiles[7].careers[1] = career, career
            s.inventory._career_name = "es_questingknight"
            s.equipment.slots.slot_ranged, s.equipment.slots.slot_melee = s.equipment.slots.slot_melee, nil
            s.equipment.wielded_slot = "slot_ranged"
        end
        s.managers.package = {
            has_loaded = function(_, path, reference)
                if reference == nil then
                    for key, value in pairs(s.refs) do if key:sub(1, #path + 1) == path .. "|" and value then return true end end
                    return false
                end
                return s.refs[path .. "|" .. reference] == true
            end,
            load = function(_, path, reference, callback, async, prioritize)
                s.loads[#s.loads + 1] = { path, reference, callback, async, prioritize }
                s.refs[path .. "|" .. reference] = not s.reject_resource
                if callback then callback() end
            end,
            reference_count = function(_, path, reference) return s.refs[path .. "|" .. reference] and 1 or 0 end,
            unload = function(_, path, reference) s.refs[path .. "|" .. reference] = nil end,
        }
        c.env.Managers = s.managers
        -- Whole existing #586 catalogue and acquire/release closures, including
        -- the real synchronous mod_load call. Not a second package owner.
        local residency = span(entry, "_om.DUAL_WEAPON_FP_RESIDENCY = {",
            "\n-- ============================================================\n-- Cross-character husk residency owner")
        c.T.run("return function(_om)\n" .. residency .. "\nend", c.env, "actual-entry-586-residency")(s.om)
        s.first, s.input, s.locomotion = {}, {}, {}
        s.status = { unit = s.unit, inventory_extension = s.inventory, is_disabled = function() return false end }
        s.machine_state = { unit = s.unit, player = s.player, name = "walking", status_extension = s.status,
            inventory_extension = s.inventory, first_person_extension = s.first,
            input_extension = s.input, locomotion_extension = s.locomotion }
        s.csm = { unit = s.unit, player = s.player, state_machine = { state_current = s.machine_state } }
        s.extensions = { inventory_system = s.inventory, status_system = s.status,
            character_state_machine_system = s.csm, first_person_system = s.first,
            input_system = s.input, locomotion_system = s.locomotion }
        s.script.extensions = function(unit) return unit == s.unit and s.extensions or nil end
        s.equipment.wielded, s.equipment.right_hand_wielded_unit = s.item, {}
        s.equipment.slots[slot_name].item_template = s.weapons.one_handed_swords_template_1
        s.helper = {}
        s.mod.hook = function(_, target, method, callback)
            H.equal(target, s.helper); H.equal(s.hooks[method], nil, "one singleton registration")
            s.hooks[method] = callback
        end
        s.mod.hook_safe = function(_, target, method, callback)
            H.equal(target, "PlayerManager"); H.equal(method, "assign_unit_ownership")
            H.equal(s.hooks.assign_unit_ownership, nil, "one ownership singleton registration")
            s.hooks.assign_unit_ownership = callback
        end
        local installation = span(entry, "\t_om.mace_sword_runtime = _om.sword_family:install_mace_runtime(",
            "\n\tpolicy.install_loadout_ui")
        local bind = c.T.run("return function(_om, mod, CharacterStateHelper, Unit, ScriptUnit)\n"
            .. installation .. "\nreturn _om.mace_sword_runtime end", c.env, "actual-entry-Mace-runtime-install")
        s.movement = bind(s.om, s.mod, s.helper, s.units, s.script)
        function s.speed()
            return assert(s.hooks.move_on_ground)(function(_, _, _, _, speed) return speed end,
                s.first, s.input, s.locomotion, {}, 4, s.unit)
        end
        function s.install_view()
            -- Explicit engine slot-host boundary only. The optional case below
            -- replaces this with the complete actual native GearUtils body.
            s.equipment.slots[s.equipment.wielded_slot].item_template = s.weapons[TEMPLATE]
            return s.movement:refresh(s.inventory)
        end
        return s, c
    end
    local function transport(s, method)
        local source = read(root .. CP .. "_cwv_item_identity_transport_owner.lua")
        local wire = span(source, "\t\tlocal _null_logged = {}", "\n\t\tmod._cwv_skin_wire_surfaces = {}")
        s.om.cosmetic_skin_wire = load("_cwv_cosmetic_skin_wire")
        s.om._skin_keys, s.om._probe_476 = {}, function() end
        local first = '\t\tmod:hook("SimpleInventoryExtension", "' .. method .. '", function('
        local at = assert(source:find(first, 1, true))
        local finish = assert(source:find("\n\t\tend)", at, true)) + #"\n\t\tend)"
        local env = setmetatable({
            _om = s.om, _send_identity_slots = function() end,
            peer_pull = { request = function() end },
            _custom_skin_keys = {}, printf = function() end,
        }, { __index = _G })
        local hook
        env.mod = { hook = function(_, class, name, callback)
            H.equal(class, "SimpleInventoryExtension"); H.equal(name, method); hook = callback
        end }
        local chunk = assert(loadstring(wire .. "\n" .. source:sub(at, finish), "actual-existing-transport-" .. method))
        setfenv(chunk, env); chunk()
        return assert(hook)
    end
    local function wield(s)
        local source = read(root .. CP .. "_cwv_cross_access.lua")
        local first = 'mod:hook_safe("SimpleInventoryExtension", "wield", function(self, slot_name)'
        local at = assert(source:find(first, 1, true))
        local finish = assert(source:find("\nend)", at, true)) + #"\nend)"
        local hook
        local env = setmetatable({ _om = s.om, Managers = s.managers, _dbg = function() end,
            mod = { hook_safe = function(_, class, name, callback)
                H.equal(class, "SimpleInventoryExtension"); H.equal(name, "wield"); hook = callback
            end } }, { __index = _G })
        local chunk = assert(loadstring(source:sub(at, finish), "actual-existing-wield-hook"))
        setfenv(chunk, env); chunk()
        return assert(hook)
    end
    local function template_router(s)
        local source = read(root .. CP .. "_cwv_musket_runtime.lua")
        local router = span(source, "local function install_template_router()", "\nreturn { network_lookup")
        local callback
        local env = setmetatable({ _om = s.om, Weapons = s.weapons,
            mod = { hook = function(_, class, method, handler)
                H.equal(class, "BackendUtils"); H.equal(method, "get_item_template"); callback = handler
            end } }, { __index = _G })
        local chunk = assert(loadstring(router .. "\ninstall_template_router()", "actual-consolidated-template-router"))
        setfenv(chunk, env); chunk()
        return function(item)
            return callback(function() return s.weapons.one_handed_swords_template_1 end, item)
        end
    end
    local function native_slot(s, slot_name, native_path, initial)
        local backend = { get_item_template = template_router(s),
            get_item_units = function(item) H.equal(item, s.item); return {} end }
        local env = setmetatable({ Unit = { node = function() error("not used by create_equipment") end },
            BackendUtils = backend }, { __index = _G })
        local native = read(native_path)
        if native:sub(1, 3) == string.char(239, 187, 191) then native = native:sub(4) end
        local chunk = assert(loadstring(native, "whole-native93dea-GearUtils"))
        setfenv(chunk, env); chunk()
        if initial ~= false then s.owner_missing, s.player.player_unit = true, nil end
        s.equipment.slots[slot_name] = nil
        return Actors.world_hook(s)(env.GearUtils.create_equipment, {}, slot_name, s.item,
            {}, s.unit, false, nil, nil, nil, nil, nil, s.inventory._career_name)
    end
    local function held_snapshot(s)
        for index = 1, 10 do
            local name, value = debug.getupvalue(s.hooks.move_on_ground, index)
            if name == "current_snapshot" then
                for inner = 1, 10 do
                    local key, snapshot = debug.getupvalue(value, inner)
                    if key == "snapshot" then return snapshot end
                    if key == nil then break end
                end
            end
            if name == nil then break end
        end
        error("actual private snapshot upvalue missing")
    end
    local function lifecycle(s)
        local source = read(root .. CP .. "_cwv_commands_lifecycle.lua")
        local state = span(source, "\nmod.on_game_state_changed = function(status, state_name)",
            "\n-- #586: these callbacks")
        local callbacks = span(source, "mod.on_enabled = function()", "\n-- (2) Variant equip event")
        local trace = {}
        local om = setmetatable({
            mace_sword_runtime = s.movement,
            _acquire_dual_weapon_fp_residency = function() trace[#trace + 1] = "acquire"; return s.om._acquire_dual_weapon_fp_residency("test") end,
            _release_dual_weapon_fp_residency = function()
                H.equal(s.speed(), 4, "movement cleared before native package teardown")
                trace[#trace + 1] = "release"; return s.om._release_dual_weapon_fp_residency("test")
            end,
            _apply_mace_hammer_identity = function(value)
                H.equal(s.speed(), 4, "movement not re-admitted before actual599 reapplication")
                trace[#trace + 1] = "599"; s.construction.apply_mhi(value)
            end,
        }, { __index = s.om })
        local host = { get = function() return true end }
        local env = setmetatable({ mod = host, _om = om, _dbg = function() end,
            _dbg_count_registered_cwv_items = function() return 0 end }, { __index = _G })
        local chunk = assert(loadstring(state .. "\n" .. callbacks, "actual-existing-lifecycle-callbacks"))
        setfenv(chunk, env); chunk()
        return host, trace
    end
    H.test("645 Mace actual serial constructor admission remains separate from published Sword", function()
        local s = fixture()
        H.equal(s.family_check(), nil)
        H.equal(s.mace_check(), nil, "real Mace constructor and actual runtime install required")
        local package = s.runtime:package("es_1h_sword", "mace")
        H.truthy(package, "real entry Mace dispatch must expose the retained construction")
        H.equal(package.template, TEMPLATE)
        H.equal(s.sword_family:package("we_1h_sword", "mace"), nil)
        H.equal(s.runtime:package("we_1h_sword", "mace").style_id, "elven",
            "a dormant unsupported preference may restore native, never Mace")
        for _, alias in ipairs({ "one_handed_swords_template_1", "one_handed_swords", "foreign_es_1h_sword" }) do
            H.equal(s.runtime:package(alias, "mace"), nil)
        end
        H.equal(s.policy.style("we_1h_sword", "mace"), "elven")
        H.equal(#select(3, s.policy.member("we_1h_sword")).order, 2)
        local row = s.policy.FAMILIES.one_handed_swords.styles.mace
        local resource = row.resource; row.resource = "foreign"
        H.equal(s.runtime:package("es_1h_sword", "mace"), nil)
        H.equal(s.family_check(), nil, "Mace-only row drift cannot poison published Sword")
        H.truthy(s.runtime:package("es_1h_sword", "elven"))
        row.resource = resource
        H.equal(s.mace_check(), nil)
    end)
    H.test("645 Mace missing599 authority closes only Mace with no late repair", function()
        local s, c = fixture({ omit599 = true })
        H.equal(s.runtime:package("es_1h_sword", "mace"), nil); H.truthy(s.mace_check())
        H.equal(s.family_check(), nil); H.truthy(s.runtime:package("es_1h_sword", "elven"))
        H.equal(s.runtime:next_style("es_1h_sword", "elven"), "empire",
            "an unavailable Mace cannot hide the published Sword cycle")
        H.equal(s.runtime:next_style("es_1h_sword", "empire"), "elven")
        c.state.mace_hammer_identity, c.state.mace_hammer_identity_policy = c.mhi_state, c.mhi_policy
        H.equal(s.runtime:package("es_1h_sword", "mace"), nil, "no late authority recapture")
        H.equal(rawget(c.env.Weapons, TEMPLATE), nil, "no construction or repair after trusted owner loss")
    end)
    H.test("645 Mace serial constructor preserves carrier career action and complete native inspect wield contracts", function()
        -- Opaque canonical identity data only; the sibling-native case below
        -- additionally evaluates the actual source predicate. No invented body.
        local canonical = { opaque_identity_only = true }
        local s, c = fixture({ career_action = canonical })
        local template = assert(s.weapons[TEMPLATE])
        H.equal(template.actions.action_career_es_4, canonical,
            "serial Mace construction must preserve the carrier's canonical career action")
        H.truthy(template.actions.action_inspect, "serial Mace construction must preserve native inspect")
        H.truthy(c.F.same(template.actions.action_inspect, c.env.ActionTemplates.action_inspect),
            "complete inspect graph and original callback identities survive")
        H.truthy(c.F.same(template.actions.action_wield, c.env.ActionTemplates.wield),
            "complete native right-handed wield graph survives")
        local careers = { es_questingknight = { activated_ability = { { action_name = "action_career_es_4" } } } }
        local report = c.integration.install(template, { "es_questingknight" }, careers,
            c.env.ActionTemplates, "character_weapon_variants")
        H.equal(report.ok, true); H.equal(s.mace_check(), nil)
        c.integration.release(template, "character_weapon_variants")
        H.equal(template.actions.action_career_es_4, canonical, "baseline action survives provider release")
        H.equal(s.mace_check(), nil); H.equal(s.family_check(), nil)
        local kind = template.actions.action_inspect.default.kind
        template.actions.action_inspect.default.kind = "foreign"
        H.equal(s.runtime:package("es_1h_sword", "mace"), nil); H.equal(s.family_check(), nil)
        template.actions.action_inspect.default.kind = kind
        H.equal(s.mace_check(), nil)
    end)
    H.test("645 Mace initial saved intent waits for installed template and exact586 residency", function()
        local s = fixture()
        H.equal(#s.om.DUAL_WEAPON_FP_RESIDENCY, 6)
        local found
        for _, load_row in ipairs(s.loads) do
            if load_row[1] == RESOURCE then
                H.equal(found, nil); found = load_row
                H.equal(load_row[2], "cwv_mace_sword_fp"); H.equal(load_row[3], nil)
                H.equal(load_row[4], false); H.equal(load_row[5], true)
            end
        end
        H.truthy(found, "actual initial synchronous load before first runtime admission")
        local count = #s.loads; s.om._acquire_dual_weapon_fp_residency("again"); H.equal(#s.loads, count)
        s.runtime.store.items.sword_id = "mace"
        H.equal(s.movement:refresh(s.inventory), false); H.equal(s.speed(), 4)
        H.equal(s.install_view(), true); H.equal(s.speed(), 4.2)
        s.refs[RESOURCE .. "|cwv_mace_sword_fp"] = nil
        s.refs[RESOURCE .. "|foreign_holder"] = true
        H.equal(s.runtime:package("es_1h_sword", "mace"), nil, "another owner cannot impersonate586")
        s.movement:clear(); H.equal(s.install_view(), false); H.equal(s.speed(), 4)
        s.refs[RESOURCE .. "|cwv_mace_sword_fp"] = true
        local lease_map = s.om._dual_weapon_fp_residency_held
        s.om._dual_weapon_fp_residency_held = { [RESOURCE] = true }
        H.equal(s.runtime:package("es_1h_sword", "mace"), nil, "replaced private586 cache cannot recapture authority")
        s.om._dual_weapon_fp_residency_held = lease_map
        H.equal(s.mace_check(), nil)
    end)
    H.test("645 Mace actual init resync wield boundaries refresh exact current actor and preserve tuples errors", function()
        local s = fixture()
        s.runtime.store.items.sword_id = "mace"
        local init, resync = transport(s, "game_object_initialized"), transport(s, "_spawn_resynced_loadout")
        local direct = { n = 6, [1] = false, [3] = "third", [5] = 17 }
        local wired = { n = 4, [1] = false, [3] = "third" }
        local function native()
            H.equal(s.speed(), 4, "snapshot cleared before native init/resync")
            s.equipment.slots.slot_melee.item_template = s.weapons[TEMPLATE]
            return false, nil, "third", nil, 17, nil
        end
        for _, row in ipairs({
            { function() return init(native, s.inventory, s.unit, 123) end, wired },
            { function() return resync(native, s.inventory, { slot_id = "slot_melee" }, false) end, direct },
            { function() return resync(native, s.inventory, { slot_id = "slot_melee", skin = "present" }, false) end, wired },
        }) do H.deep_equal(pack(row[1]()), row[2]); H.equal(s.speed(), 4.2) end
        H.deep_equal(pack(s.hooks.move_on_ground(function() return nil, false, nil, 17, nil end,
            s.first, s.input, s.locomotion, {}, 4, s.unit)), { n = 5, [2] = false, [4] = 17 })
        local sentinel = {}
        local ok, failure = pcall(resync, function() error(sentinel, 0) end, s.inventory, {}, false)
        H.equal(ok, false); H.equal(failure, sentinel); H.equal(s.speed(), 4)
        local record = { slot_id = "slot_melee", skin = "cwv_real_wire_probe" }
        ok, failure = pcall(resync, function()
            H.equal(record.skin, nil, "actual shared wire owner hides the custom skin")
            error(sentinel, 0)
        end, s.inventory, record, false)
        H.equal(ok, false); H.equal(failure, sentinel); H.equal(record.skin, "cwv_real_wire_probe")
        H.equal(s.speed(), 4, "wire error restores skin but never re-admits movement")
        wield(s)(s.inventory, "slot_melee"); H.equal(s.speed(), 4.2)
        local stale = { _equipment = { slots = {} } }
        init(function() return nil, false, nil end, stale, {}, 1)
        H.equal(s.speed(), 4.2, "late old-unit callback cannot clear current snapshot")
        local old_slots = s.equipment.slots; s.equipment.slots = nil
        H.deep_equal(pack(init(function()
            s.equipment.slots = old_slots; return nil, false, nil
        end, s.inventory, s.unit, 1)), { n = 3, [2] = false })
        H.equal(s.speed(), 4.2, "no-slots early path refreshes only after native creates slots")
    end)
    H.test("645 Mace real style preflight accepted write rollback and error have distinct invalidation", function()
        local s = fixture()
        s.runtime.store.items.sword_id = "mace"; H.equal(s.install_view(), true)
        H.equal(s.runtime:set_item_style(s.item, nil, "foreign", "test", false), false)
        H.equal(s.speed(), 4.2, "preflight refusal preserves current admission")
        H.equal(s.runtime:set_item_style(s.item, nil, "empire", "test", false), true)
        H.equal(s.speed(), 4)
        H.equal(s.runtime:set_item_style(s.item, nil, "mace", "test", false), true)
        H.equal(s.speed(), 4.2)
        local callback = wield(s)
        s.inventory.destroy_slot = function() return true end
        s.inventory.add_equipment = function() error("authored native rebuild refusal", 0) end
        s.inventory.wield = function() error("native wield failed before safe-hook callback", 0) end
        local ok, reason = s.runtime:set_item_style(s.item, nil, "empire", "test", true)
        H.equal(ok, false); H.equal(reason, "rebuild failed")
        H.equal(s.runtime.store.items.sword_id, "mace"); H.equal(s.speed(), 4,
            "best-effort rollback cannot silently re-admit inside an active transaction")
        callback(s.inventory, "slot_melee"); H.equal(s.speed(), 4.2)
        local setter, sentinel = s.mod.set, {}
        s.mod.set = function() error(sentinel, 0) end
        ok, reason = pcall(s.runtime.set_item_style, s.runtime, s.item, nil, "empire", "test", false)
        s.mod.set = setter
        H.equal(ok, false); H.equal(reason, sentinel); H.equal(s.speed(), 4)
    end)
    H.test("645 Mace actual actor selection permits only Empire native careers and preserves dormant preference", function()
        local s = fixture()
        s.runtime.store.items.sword_id = "mace"
        for index, name in ipairs({ "es_mercenary", "es_huntsman", "es_knight", "es_questingknight" }) do
            local career = { name = name, profile_name = "empire_soldier" }
            s.careers[name], s.profiles[7].careers[index] = career, career
            s.local_ci, s.inventory._career_name = index, name
            H.equal(s.runtime:describe(s.item).style_id, "mace")
            H.equal(s.install_view(), true); H.equal(s.speed(), 4.2)
        end
        local selected = { hero_name = "wood_elf", career_index = 1 }
        H.equal(s.runtime:describe(s.item, nil, s.runtime:loadout_actor(selected)), nil)
        H.equal(s.runtime:set_item_style(s.item, nil, "mace", "test", false, s.runtime:loadout_actor(selected)), false)
        s.local_pi = 12
        H.equal(s.runtime:describe(s.item), nil); H.equal(s.speed(), 4)
        H.equal(s.runtime.store.items.sword_id, "mace", "actor refusal never erases preference")
        s.local_pi, s.local_ci, s.inventory._career_name = 7, 1, "es_mercenary"
        H.equal(s.install_view(), true); H.equal(s.speed(), 4.2)
        s.runtime:accept_style_edge("remote", "slot_melee", "one_handed_swords", "mace", "style_channel")
        H.equal(s.runtime:effective_template_name(s.remote_item, nil, s.remote_unit, "slot_melee"), TEMPLATE)
        H.equal(s.speed(), 4.2, "remote selection never creates a second local movement owner")
    end)
    H.test("645 Mace pending selected-actor callback cannot commit or clear healthy local admission", function()
        local s, complete = fixture(), nil
        s.runtime.store.items.sword_id = "mace"; H.equal(s.install_view(), true)
        local selected = { hero_name = "empire_soldier", career_index = 1 }
        H.equal(s.runtime:request_item_style(s.item, nil, "empire", "test", true,
            function(value) complete = value end, s.runtime:loadout_actor(selected)), true)
        H.equal(type(s.complete), "function"); H.equal(s.speed(), 4.2)
        selected.hero_name = "wood_elf"
        s.complete(true)
        H.equal(complete, false); H.equal(s.runtime.pending.sword_id, nil)
        H.equal(s.runtime.store.items.sword_id, "mace"); H.equal(s.writes, 0); H.equal(s.speed(), 4.2)
    end)
    H.test("645 Mace retained row roots and raw installed identities reject equal-comparing replacements", function()
        local s, c = fixture()
        s.runtime.store.items.sword_id = "mace"; H.equal(s.install_view(), true)
        local family = s.policy.FAMILIES.one_handed_swords
        local row, member, members = family.styles.mace, family.members.es_1h_sword, family.members
        local replacement = {}; for key, value in pairs(row) do replacement[key] = value end
        family.styles.mace = replacement
        H.equal(s.runtime:package("es_1h_sword", "mace"), nil)
        H.equal(s.family_check(), nil, "only Mace row authority was replaced")
        family.styles.mace = row
        family.members = { es_1h_sword = member, we_1h_sword = members.we_1h_sword }
        H.equal(s.runtime:package("es_1h_sword", "mace"), nil)
        family.members = members
        local template, slot = s.weapons[TEMPLATE], s.equipment.slots.slot_melee
        local meta = { __eq = function() return true end }
        for _, kind in ipairs({ "installed", "registry", "slot" }) do
            H.equal(s.install_view(), true)
            if kind == "slot" then
                setmetatable(slot, meta)
                s.equipment.slots.slot_melee = setmetatable({
                    item_data = s.item, item_template = template,
                }, meta)
            else
                setmetatable(template, meta)
                local foreign = setmetatable({}, meta)
                if kind == "installed" then slot.item_template = foreign else s.weapons[TEMPLATE] = foreign end
            end
            H.equal(s.speed(), 4, "raw " .. kind .. " replacement cannot extend a previous snapshot")
            setmetatable(slot, nil); setmetatable(template, nil)
            s.equipment.slots.slot_melee, slot.item_template, s.weapons[TEMPLATE] = slot, template, template
        end
        H.equal(s.mace_check(), nil, "fixture restoration is explicit; owner never repairs")
        local registry, prior_meta = rawget(c.env, "Weapons"), getmetatable(c.env)
        local generation = c.state._cwv_damage_profile_generation
        rawset(c.env, "Weapons", nil)
        setmetatable(c.env, { __index = function(_, key)
            if key == "Weapons" then error("unknown shared registry getter", 0) end
            return _G[key]
        end })
        local ok, reason = pcall(s.mace_check)
        setmetatable(c.env, prior_meta); rawset(c.env, "Weapons", registry)
        H.equal(ok, true); H.truthy(reason, "unknown registry is an explicit refusal, not recapture/repair")
        H.equal(c.state._cwv_damage_profile_generation, generation)
        H.equal(s.mace_check(), nil)
    end)
    H.test("645 Mace actual secondary slot matrix routes one bonus and preserves non-wielded snapshots", function()
        local s = fixture({ slot_name = "slot_ranged" })
        local router, callback = template_router(s), wield(s)
        local init, resync = transport(s, "game_object_initialized"), transport(s, "_spawn_resynced_loadout")
        local primary_item = { name = "es_1h_sword", backend_id = "primary_id" }
        local primary = { item_data = primary_item, item_template = s.weapons[TEMPLATE] }
        s.equipment.slots.slot_melee = primary
        s.runtime.store.items.primary_id, s.runtime.store.items.sword_id = "mace", nil
        callback(s.inventory, "slot_ranged")
        H.equal(s.speed(), 4, "primary Mace does not amplify a wielded secondary native Sword")
        s.runtime.store.items.primary_id, s.runtime.store.items.sword_id = nil, "mace"
        primary.item_template = s.weapons.one_handed_swords_template_1
        local function install_current()
            local slot_name = s.equipment.wielded_slot
            local item = slot_name == "slot_ranged" and s.item or primary_item
            s.equipment.slots[slot_name] = { item_data = item, item_template = router(item) }
            return false, nil, "third", nil, 17, nil
        end
        H.deep_equal(pack(init(install_current, s.inventory, s.unit, 1)), { n = 4, [1] = false, [3] = "third" })
        H.equal(s.speed(), 4.2, "actual secondary post-init must receive exactly one Mace factor")
        H.deep_equal(pack(resync(install_current, s.inventory, { slot_id = "slot_ranged" }, false)),
            { n = 6, [1] = false, [3] = "third", [5] = 17 })
        H.equal(s.speed(), 4.2)
        H.deep_equal(pack(resync(install_current, s.inventory, { slot_id = "slot_ranged", skin = "cwv_probe" }, false)),
            { n = 4, [1] = false, [3] = "third" })
        H.equal(s.speed(), 4.2)
        s.runtime.store.items.primary_id, primary.item_template = "mace", s.weapons[TEMPLATE]
        H.equal(s.speed(), 4.2, "both Mace instances still grant one5 percent factor")
        local held = held_snapshot(s)
        callback(s.inventory, "slot_melee")
        H.equal(held_snapshot(s), held, "stale non-wielded wield callback must not clear or replace active capture")
        resync(function() return nil end, s.inventory, { slot_id = "slot_melee" }, false)
        H.equal(held_snapshot(s), held, "non-wielded resync must not replace active capture")
        H.equal(s.speed(), 4.2)
        s.equipment.wielded_slot, s.equipment.wielded = "slot_melee", primary_item
        H.equal(s.speed(), 4, "old secondary snapshot cannot transfer across a slot switch")
        callback(s.inventory, "slot_melee"); H.equal(s.speed(), 4.2)
        s.equipment.wielded_slot, s.equipment.wielded = "slot_ranged", s.item
        callback(s.inventory, "slot_ranged"); H.equal(s.speed(), 4.2)
        local fail, operations = false, {}
        s.inventory.destroy_slot = function(_, slot_name)
            H.equal(slot_name, "slot_ranged"); operations[#operations + 1] = "destroy"
            if fail then error("native secondary destroy failure", 0) end
            s.equipment.slots[slot_name] = nil
        end
        local creation = Actors.world_hook(s)
        s.inventory.add_equipment = function(_, slot_name, item)
            H.equal(slot_name, "slot_ranged"); H.equal(item, s.item); operations[#operations + 1] = "add"
            if fail then error("native secondary repair failure", 0) end
            s.equipment.slots[slot_name] = creation(function(_, created_slot, created_item)
                H.equal(created_slot, slot_name); H.equal(created_item, item)
                return { item_data = item, item_template = router(item) }
            end, {}, slot_name, item, {}, s.unit, false, nil, nil, nil, nil, nil, s.inventory._career_name)
        end
        s.inventory.wield = function(_, slot_name)
            H.equal(slot_name, "slot_ranged"); operations[#operations + 1] = "wield"
            if fail then error("native secondary wield failure before safe callback", 0) end
            s.equipment.wielded_slot, s.equipment.wielded = slot_name, s.item
            callback(s.inventory, slot_name)
        end
        H.equal(s.runtime:set_item_style(s.item, nil, "empire", "secondary", true), true)
        H.equal(s.equipment.slots.slot_ranged.item_template, s.weapons.one_handed_swords_template_1)
        H.equal(s.speed(), 4, "secondary native restoration removes the bonus")
        H.equal(s.runtime:set_item_style(s.item, nil, "mace", "secondary", true), true)
        H.equal(s.equipment.slots.slot_ranged.item_template, s.weapons[TEMPLATE]); H.equal(s.speed(), 4.2)
        fail = true
        local ok, reason = s.runtime:set_item_style(s.item, nil, "empire", "secondary", true)
        H.equal(ok, false); H.equal(reason, "rebuild failed")
        H.equal(s.runtime.store.items.sword_id, "mace"); H.equal(s.speed(), 4)
        fail = false
        resync(install_current, s.inventory, { slot_id = "slot_ranged" }, false)
        H.equal(s.speed(), 4.2, "only a later actual current-slot boundary re-admits after rollback")
        H.truthy(#operations >= 6); H.equal(#s.loads, 6, "slot changes do not duplicate the slot-agnostic586 lease")
        H.equal(s.refs[RESOURCE .. "|cwv_mace_sword_fp"], true); H.equal(s.family_check(), nil)
    end)
    H.test("645 Mace raw inventory item and actual registry identities cannot clear or revive another capture", function()
        local s, c = fixture()
        s.runtime.store.items.sword_id = "mace"; H.equal(s.install_view(), true)
        local meta = { __eq = function() return true end }
        local foreign = {}; for key, value in pairs(s.inventory) do foreign[key] = value end
        setmetatable(s.inventory, meta); setmetatable(foreign, meta)
        local held = held_snapshot(s)
        s.movement:invalidate_inventory(foreign)
        H.equal(s.speed(), 4.2, "equal-comparing foreign inventory must not invalidate the current capture")
        H.equal(s.movement:refresh(foreign), false)
        H.equal(held_snapshot(s), held)
        local other_item = {}; for key, value in pairs(s.item) do other_item[key] = value end
        setmetatable(s.item, meta); setmetatable(other_item, meta)
        s.movement:before_style_commit({ identity = "foreign_id", item_data = other_item, style_id = "empire" }, "mace")
        H.equal(held_snapshot(s), held, "foreign private boundary row cannot impersonate installed item identity")
        setmetatable(s.inventory, nil); setmetatable(s.item, nil)
        local root = c.env.Weapons
        local replacement = {}; for key, value in pairs(root) do replacement[key] = value end
        setmetatable(root, meta); setmetatable(replacement, meta)
        c.env.Weapons = replacement
        H.equal(s.speed(), 4, "equal-comparing actual registry root replacement denies")
        c.env.Weapons = root; setmetatable(root, nil)
        H.equal(s.speed(), 4, "restoring the root cannot revive a previously invalidated snapshot")
        wield(s)(s.inventory, "slot_melee"); H.equal(s.speed(), 4.2)
    end)
    H.test("645 Mace actual lifecycle clear disable enable unload orders599 and586 ownership", function()
        local s = fixture()
        s.runtime.store.items.sword_id = "mace"; H.equal(s.install_view(), true)
        local callbacks, trace = lifecycle(s)
        callbacks.on_game_state_changed("exit", "StateIngame"); H.equal(s.speed(), 4)
        H.equal(s.install_view(), true)
        callbacks.on_disabled(); H.equal(s.speed(), 4)
        H.deep_equal(trace, { "599", "release" })
        H.equal(s.refs[RESOURCE .. "|cwv_mace_sword_fp"], nil)
        callbacks.on_enabled(); H.equal(s.speed(), 4.2)
        H.deep_equal(trace, { "599", "release", "acquire", "599" })
        callbacks.on_unload(); H.equal(s.speed(), 4)
        H.equal(s.refs[RESOURCE .. "|cwv_mace_sword_fp"], nil)
    end)
    H.test("645 private resource extraction preserves lazy allowlist callbacks capture and thrown errors", function()
        local factory = load("_cwv_style_resource_owner")
        local calls, packages, families = 0, nil, { one = { styles = { authored = { resource = "closed" } } } }
        local acquire, resident = factory(families, function() calls = calls + 1; return packages end)
        H.equal(calls, 0, "no eager package getter")
        local ok, reason = acquire("foreign", function() error("unreachable") end)
        H.equal(ok, false); H.equal(reason, "resource is not authored"); H.equal(calls, 0)
        ok, reason = acquire("closed", function() error("unreachable") end)
        H.equal(ok, false); H.equal(reason, "package manager unavailable")
        local loaded, callbacks, args = false, {}, {}
        packages = { has_loaded = function(_, path, reference)
            args[#args + 1] = { path, reference }; return loaded
        end, load = function(_, path, reference, callback, async, prioritize)
            H.equal(path, "closed"); H.equal(reference, "cwv_combat_styles")
            H.equal(async, true); H.equal(prioritize, true); loaded = true; callback()
        end }
        families.one.styles.authored.resource = "late-foreign"
        H.equal(acquire("closed", function(...) callbacks[#callbacks + 1] = pack(...) end), true)
        H.deep_equal(callbacks[1], { n = 2, [1] = true, [2] = "resource completion was not resident" },
            "preserve the previous callback tuple exactly; no incidental truthiness-expression repair")
        H.equal(resident("closed"), true); H.equal(args[#args][2], nil, "observer owns no reference")
        H.equal(resident("late-foreign"), nil, "allowlist captured once, not recaptured")
        loaded = false
        H.equal(acquire("closed", function(...) callbacks[#callbacks + 1] = pack(...) end), false)
        H.deep_equal(callbacks[2], { n = 2, [1] = false, [2] = "held resource lost" })
        local sentinel = {}
        local throws = factory({ one = { styles = { one = { resource = "closed" } } } },
            function() return { load = function() error(sentinel, 0) end } end)
        ok, reason = pcall(throws, "closed", function() end)
        H.equal(ok, false); H.equal(reason, sentinel, "native load error is not silently swallowed")
        local first = "\tlocal acquire_style_resource, style_resource_resident ="
        local actual = span(entry, first, "\n\n\tlocal imperial_transform")
        H.truthy(assert(entry:find(first, 1, true)) < assert(entry:find("\t_om.combat_styles = policy.install", 1, true)),
            "actual resource owner binds before actual policy consumer")
        local invoke = assert(loadstring("return function(mod, policy, Managers)\n" .. actual
            .. "\nreturn acquire_style_resource, style_resource_resident end", "actual-entry-resource-owner"))()
        local P, managers, count = load("_cwv_combat_styles"), {}, 0
        local provider = { dofile = function(_, path)
            H.equal(path, "scripts/mods/character_weapon_variants/_cwv_style_resource_owner")
            count = count + 1; return factory
        end }
        local entry_acquire = invoke(provider, P, managers)
        H.equal(count, 1)
        local authored = "units/beings/player/first_person_base/state_machines/melee/1h_sword"
        ok, reason = entry_acquire(authored, function() error("not available") end)
        H.equal(ok, false); H.equal(reason, "package manager unavailable")
        managers.package = packages; loaded = true
        packages.load = function(_, path, reference, callback) H.equal(path, authored); callback() end
        P.FAMILIES = {}; provider.dofile = function() error("late loader must not run") end
        H.equal(entry_acquire(authored, function(value) H.equal(value, true) end), true)
        H.equal(count, 1, "actual entry retains returned closures; no VMF loader-cache assumption")
        ok, reason = pcall(invoke, { dofile = function() return function() error(sentinel, 0) end end },
            P, managers)
        H.equal(ok, false); H.equal(reason, sentinel, "actual factory exception is preserved at original entry boundary")
    end)
    local native_path = root .. "/../Vermintide-2-Source-Code/scripts/unit_extensions/default_player_unit/inventory/gear_utils.lua"
    local native_action_path = root .. "/../Vermintide-2-Source-Code/scripts/settings/dlcs/lake/action_templates_lake.lua"
    local native_file = io.open(native_path, "rb")
    if native_file then native_file:close() end
    local native_action_file = io.open(native_action_path, "rb")
    if native_action_file then native_action_file:close() end
    local native_boot_available = NativeBoot.available(native_root)
    H.test_if(native_file ~= nil and native_action_file ~= nil and native_boot_available,
        "645 Mace actual native GearUtils selects and installs retained template before post-init capture", function()
        local disabled, usable, action_user = false, true, {}
        local canonical_env = { ActionTemplates = {}, ScriptUnit = { extension = function(unit, system)
            H.equal(unit, action_user)
            if system == "buff_system" then return { has_buff_perk = function(_, perk)
                H.equal(perk, "disable_career_ability"); return disabled
            end } end
            H.equal(system, "career_system")
            return { get_activated_ability_data = function() return { action_name = "action_career_es_4" } end,
                can_use_activated_ability = function() return usable end }
        end } }
        setmetatable(canonical_env, { __index = _G })
        local native_action_source = read(native_action_path)
        if native_action_source:sub(1, 3) == string.char(239, 187, 191) then native_action_source = native_action_source:sub(4) end
        local native_action = assert(loadstring(native_action_source, "whole-native93dea-GK-action"))
        setfenv(native_action, canonical_env); native_action()
        local s = fixture({ career_action = canonical_env.ActionTemplates.action_career_es_4 })
        local action = s.weapons[TEMPLATE].actions.action_career_es_4
        H.equal(action, canonical_env.ActionTemplates.action_career_es_4)
        H.equal(action.default.condition_func(action_user), true, "actual native carrier ability remains usable")
        disabled = true; H.equal(action.default.condition_func(action_user), false)
        disabled, usable = false, false; H.equal(action.default.condition_func(action_user), false)
        s.managers.input = { is_device_active = function() return false end }
        H.equal(s.weapons[TEMPLATE].actions.action_inspect.default.condition_func(action_user, {}, nil), true)
        H.equal(s.weapons[TEMPLATE].actions.action_inspect.default.condition_func(action_user, {},
            { is_reloading = function() return true end }), false)
        s.runtime.store.items.sword_id = "mace"
        local slot = native_slot(s, "slot_melee", native_path)
        H.equal(slot.item_data, s.item); H.equal(slot.item_template, s.weapons[TEMPLATE])
        H.equal(slot.item_template_name, s.weapons[TEMPLATE].name)
        H.equal(s.speed(), 4, "creating a slot alone is not post-init movement admission")
        transport(s, "game_object_initialized")(function()
            s.equipment.slots.slot_melee = slot
        end, s.inventory, s.unit, 1)
        H.equal(s.speed(), 4, "native GO completion precedes ownership and cannot yet capture")
        NativeBoot.assign(H, native_root, s)
        H.equal(s.speed(), 4.2, "actual native ownership completion admits the installed object")
        s.equipment.slots.slot_melee = { item_data = s.item, item_template = {} }
        H.equal(s.speed(), 4, "equal intent with replaced installed instance is never enough")
    end, "optional sibling GearUtils/GK-action source absent; mandatory actual-owner/caller tests still run")
    H.test_if(native_file ~= nil and native_action_file ~= nil and native_boot_available,
        "645 Mace actual native secondary GearUtils restoration and resync retain the wielded slot", function()
        local s = fixture({ slot_name = "slot_ranged" })
        s.runtime.store.items.sword_id = "mace"
        local slot = native_slot(s, "slot_ranged", native_path)
        H.equal(slot.item_template, s.weapons[TEMPLATE])
        transport(s, "game_object_initialized")(function() s.equipment.slots.slot_ranged = slot end,
            s.inventory, s.unit, 1)
        H.equal(s.speed(), 4)
        NativeBoot.assign(H, native_root, s)
        H.equal(s.speed(), 4.2, "native secondary slot is admitted only after real ownership")
        local resync = transport(s, "_spawn_resynced_loadout")
        H.equal(s.runtime:set_item_style(s.item, nil, "empire", "secondary-native", false), true)
        slot = native_slot(s, "slot_ranged", native_path, false)
        H.equal(slot.item_template, s.weapons.one_handed_swords_template_1)
        resync(function() s.equipment.slots.slot_ranged = slot end, s.inventory, { slot_id = "slot_ranged" }, false)
        H.equal(s.speed(), 4, "native secondary Sword restoration has no Mace bonus")
        H.equal(s.runtime:set_item_style(s.item, nil, "mace", "secondary-native", false), true)
        H.equal(s.speed(), 4, "saved intent alone is still not installed-template proof")
        slot = native_slot(s, "slot_ranged", native_path, false)
        H.equal(slot.item_template, s.weapons[TEMPLATE])
        resync(function() s.equipment.slots.slot_ranged = slot end,
            s.inventory, { slot_id = "slot_ranged", skin = "cwv_native_secondary" }, false)
        H.equal(s.speed(), 4.2)
        H.equal(#s.loads, 6, "native secondary paths share the existing slot-agnostic586 reference")
    end, "optional sibling native slot/ownership source absent")
    H.test_if(native_file ~= nil and native_action_file ~= nil and native_boot_available,
        "645 Mace actual native spawn sync completes before post-ownership admission", function()
        local s = fixture({ slot_name = "slot_ranged" })
        s.runtime.store.items.sword_id = "mace"
        local trace = NativeBoot.spawn(H, native_root, s,
            function() return native_slot(s, "slot_ranged", native_path, false) end,
            transport(s, "game_object_initialized"))
        H.deep_equal(trace, { "native_local_spawn", "native_GO_before_ownership",
            "native_health_before_ownership", "native_ownership_side", "native_ownership_returned" })
        H.equal(s.player.player_unit, s.unit)
        H.equal(s.speed(), 4.2, "actual native post-ownership hook must capture initial Mace without later wield or polling")
    end, "optional sibling native ordered spawn/ownership source absent")
end
