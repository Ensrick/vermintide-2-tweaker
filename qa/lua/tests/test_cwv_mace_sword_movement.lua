-- Detached UNIT contracts only. Synthetic views below do not prove admission.
-- The last test uses the real current actor/runtime to prove Mace refusal.
return function(H, root)
    local M = assert(loadfile(root .. "/character_weapon_variants/scripts/mods/character_weapon_variants/_cwv_mace_sword_movement.lua"))()
    local Native = assert(loadfile(root .. "/qa/lua/fixtures/cwv_mace_sword_native_movement.lua"))()
    local native_root = os.getenv("VT2_NATIVE_SOURCE_ROOT") or (root .. "/../Vermintide-2-Source-Code")
    local native_available = Native.available(native_root)
    local function pack(...) return { n = select("#", ...), ... } end
    local function fixture()
        local f = { enabled = true, alive = true, graph_calls = 0, pi = 7, ci = 1 }
        f.unit, f.first, f.input, f.locomotion, f.template = {}, {}, {}, {}, {}
        f.player = { player_unit = f.unit, profile_index = function() return f.pi end, career_index = function() return f.ci end }
        f.item = { name = "es_1h_sword", backend_id = "unit-record" }
        f.slot = { item_data = f.item, item_template = f.template }
        f.equipment = { slots = { slot_melee = f.slot }, wielded_slot = "slot_melee", wielded = f.item, right_hand_wielded_unit = {} }
        f.inventory = { _unit = f.unit, player = f.player, is_bot = false, _equipment = f.equipment, _profile = {}, _career_name = "es_native" }
        f.status = { unit = f.unit, inventory_extension = f.inventory, is_disabled = function() return false end,
            move_speed_multiplier = 0.4, move_speed_multiplier_timer = 0.25 }
        f.state = { unit = f.unit, player = f.player, name = "walking", status_extension = f.status, inventory_extension = f.inventory,
            first_person_extension = f.first, input_extension = f.input, locomotion_extension = f.locomotion }
        f.csm = { unit = f.unit, player = f.player, state_machine = { state_current = f.state } }
        f.ext = { inventory_system = f.inventory, status_system = f.status, character_state_machine_system = f.csm,
            first_person_system = f.first, input_system = f.input, locomotion_system = f.locomotion }
        f.registry = { cwv_645_mace_sword_style = f.template }
        f.runtime = { store = { items = { ["unit-record"] = "synthetic-view-style" } }, describe = function()
            f.graph_calls = f.graph_calls + 1; error("full admission must not run per frame") end }
        f.actor = { inventory_profile = function() error("actor admission must not run per frame") end }
        f.constructor = { template = function() f.graph_calls = f.graph_calls + 1; error("constructor must not run per frame") end }
        f.deps = { runtime = f.runtime, actor = f.actor, constructor = f.constructor,
            enabled = function() return f.enabled end, alive = function(unit) return f.alive and unit == f.unit end,
            extensions = function(unit) return unit == f.unit and f.ext or nil end,
            local_player = function() return f.player end, weapons = function() return f.registry end }
        f.owner = M.bind(f.deps)
        -- A literal derived-view unit fixture, never passed off as O.capture.
        f.snapshot = { unit = f.unit, player = f.player, inventory = f.inventory, status = f.status, csm = f.csm, extensions = f.ext,
            equipment = f.equipment, slot_name = "slot_melee", slot = f.slot, item = f.item, identity = "unit-record", style = "synthetic-view-style",
            store = f.runtime.store, items = f.runtime.store.items, registry = f.registry, template = f.template,
            profile_fn = f.player.profile_index, career_fn = f.player.career_index, profile = 7, career = 1,
            inventory_profile = f.inventory._profile, career_name = "es_native", disabled_fn = f.status.is_disabled,
            right = f.equipment.right_hand_wielded_unit }
        function f.factor(mode) return f.owner.factor(f.snapshot, mode or "ground", f.first, f.input, f.locomotion, f.unit) end
        return f
    end
    H.test("645 movement derived view repeats without admission or graph scans", function()
        local f = fixture()
        for _ = 1, 50 do H.equal(f.factor(), 1.05) end
        H.equal(f.graph_calls, 0)
        H.equal(f.status.move_speed_multiplier, 0.4); H.equal(f.status.move_speed_multiplier_timer, 0.25)
        H.equal(f.equipment.wielded, f.item); H.equal(f.runtime.store.items["unit-record"], "synthetic-view-style")
    end)
    H.test("645 movement native argument positions and complete return tuple survive", function()
        local f, direction, calls = fixture(), {}, 0
        local function ground(first, input, locomotion, dir, speed, unit, ...)
            calls = calls + 1; H.equal(first, f.first); H.equal(input, f.input); H.equal(locomotion, f.locomotion)
            H.equal(dir, direction); H.equal(speed, 4 * 1.05); H.equal(unit, f.unit)
            H.deep_equal(pack(...), { n = 3, [1] = false, [3] = "tail" })
            return false, nil, "third", nil
        end
        H.deep_equal(pack(f.owner.ground(f.snapshot, ground, f.first, f.input, f.locomotion, direction, 4, f.unit, false, nil, "tail")),
            { n = 4, [1] = false, [3] = "third" }); H.equal(calls, 1)
        f.state.name = "falling"
        local function air(first, input, locomotion, speed, unit)
            H.equal(first, f.first); H.equal(input, f.input); H.equal(locomotion, f.locomotion)
            H.equal(speed, 3 * 1.05); H.equal(unit, f.unit); return nil, false, nil
        end
        H.deep_equal(pack(f.owner.air(f.snapshot, air, f.first, f.input, f.locomotion, 3, f.unit)), { n = 3, [2] = false })
    end)
    H.test("645 movement original errors stay original and eligibility faults deny", function()
        local f, sentinel = fixture(), {}
        local function native() error(sentinel, 0) end
        local ok, failure = pcall(f.owner.ground, f.snapshot, native, f.first, f.input, f.locomotion, {}, 4, f.unit)
        H.equal(ok, false); H.equal(failure, sentinel)
        f.status.is_disabled = function() error("destroyed status") end
        f.snapshot.disabled_fn = f.status.is_disabled
        H.equal(f.factor(), 1)
        local calls = 0
        f.owner.ground(f.snapshot, function(_, _, _, _, speed) calls = calls + 1; H.equal(speed, 4) end,
            f.first, f.input, f.locomotion, {}, 4, f.unit)
        H.equal(calls, 1)
    end)
    H.test("645 movement unknown forced disabled and pending states do not amplify", function()
        local f = fixture()
        for _, state in ipairs({ "charged", "stunned", "overcharge_exploding", "leaping", "climbing_ladder", "none" }) do
            f.state.name = state; H.equal(f.factor(), 1); H.equal(f.factor("air"), 1)
        end
        for _, state in ipairs({ "jumping", "falling" }) do f.state.name = state; H.equal(f.factor("air"), 1.05) end
        f.csm.state_machine.state_next = "leaping"; H.equal(f.factor("air"), 1); f.csm.state_machine.state_next = nil
        local calls = 0
        f.owner.air(f.snapshot, function(_, _, _, speed, unit, ...)
            calls = calls + 1; H.equal(speed, 3); H.equal(unit, f.unit); H.deep_equal(pack(...), { n = 2, [1] = 1, [2] = 0 })
        end, f.first, f.input, f.locomotion, 3, f.unit, 1, 0)
        H.equal(calls, 1)
        f.state.name = "walking"; f.snapshot.disabled_fn = function() return true end
        f.status.is_disabled = f.snapshot.disabled_fn; H.equal(f.factor(), 1)
    end)
    H.test("645 movement exact actor extension wield style registry replacement denies", function()
        local faults = {
            function(f) f.enabled = false end, function(f) f.alive = false end,
            function(f) f.player.player_unit = {} end, function(f) f.inventory.is_bot = true end,
            function(f) f.pi = 12 end, function(f) f.ci = 2 end,
            function(f) f.ext.status_system = {} end, function(f) f.ext.inventory_system = {} end,
            function(f) f.ext.character_state_machine_system = {} end, function(f) f.ext.locomotion_system = {} end,
            function(f) f.equipment.wielded_slot = "slot_ranged" end, function(f) f.slot.item_data = {} end,
            function(f) f.equipment.slots.slot_melee = { item_data = f.item } end,
            function(f) f.slot.item_template = {} end,
            function(f) f.equipment.right_hand_wielded_unit = {} end, function(f) f.item.backend_id = "replacement" end,
            function(f) f.item.cwv_key = "other" end, function(f) f.runtime.store.items["unit-record"] = "empire" end,
            function(f) f.registry.cwv_645_mace_sword_style = {} end,
        }
        for i, fault in ipairs(faults) do local f = fixture(); fault(f); H.equal(f.factor(), 1, "fault " .. i) end
    end)
    H.test("645 movement invalid native speed passes through without repair", function()
        local f = fixture()
        for _, value in ipairs({ math.huge, -math.huge, "bad", false }) do
            f.owner.ground(f.snapshot, function(_, _, _, _, actual) H.equal(actual, value) end,
                f.first, f.input, f.locomotion, {}, value, f.unit)
        end
        local nan = 0 / 0
        f.owner.ground(f.snapshot, function(_, _, _, _, actual) H.equal(actual ~= actual, true) end,
            f.first, f.input, f.locomotion, {}, nan, f.unit)
        H.equal(f.graph_calls, 0)
    end)
    H.test("645 movement actual current runtime cannot admit an absent Mace package", function()
        -- This remains the real current-runtime refusal test, not a positive
        -- production Mace admission test. See the explicit DI unit case below.
        local quiet = setmetatable({ test = function() end, test_if = function() end }, { __index = H })
        local Actors = assert(loadfile(root .. "/qa/lua/tests/test_cwv_sword_actor_admission.lua"))()(quiet, root)
        local s, f = Actors.fixture(), fixture()
        s.equipment.wielded = s.item
        f.player, f.unit, f.inventory, f.equipment, f.item = s.player, s.unit, s.inventory, s.equipment, s.item
        f.status.unit, f.status.inventory_extension = s.unit, s.inventory
        f.csm.unit, f.csm.player = s.unit, s.player
        f.ext.inventory_system = s.inventory
        local calls, describe = 0, s.runtime.describe
        s.runtime.describe = function(self, ...) calls = calls + 1; return describe(self, ...) end
        f.deps.runtime, f.deps.actor = s.runtime, s.actor
        local owner = M.bind(f.deps)
        H.equal(owner.capture(s.inventory, "slot_melee", s.item), nil)
        H.equal(calls, 1); H.equal(f.graph_calls, 0, "non-Mace row cannot reach constructor")
        H.equal(s.runtime:describe(s.item).style_id, "elven", "real current actor/package admission remains healthy")
    end)
    H.test("645 movement PURE UNIT capture denies Mace intent with an old installed template", function()
        -- Deliberate DI collaborators exercise capture's contract only. These
        -- are NOT real Mace catalogue/actor/constructor admission evidence.
        local f, admission_calls, constructor_calls = fixture(), 0, 0
        f.actor.inventory_profile = function(self, inventory, slot_name, item)
            H.equal(self, f.actor); H.equal(inventory, f.inventory)
            H.equal(slot_name, "slot_melee"); H.equal(item, f.item)
            admission_calls = admission_calls + 1; return "empire_soldier"
        end
        f.runtime.describe = function(self, item, backend_id, admit)
            H.equal(self, f.runtime); H.equal(item, f.item); H.equal(backend_id, nil)
            H.equal(admit(), "empire_soldier")
            return { item_key = "es_1h_sword", item_data = f.item, identity = "unit-record",
                family_id = "one_handed_swords", style_id = "synthetic-view-style",
                package = { template = "cwv_645_mace_sword_style", style_id = "synthetic-view-style" } }
        end
        f.constructor.template = function(direction)
            H.equal(direction, "mace_on_empire_sword"); constructor_calls = constructor_calls + 1
            return "cwv_645_mace_sword_style", f.template
        end
        local owner, old_sword_template = M.bind(f.deps), {}
        f.slot.item_template = old_sword_template
        H.equal(owner.capture(f.inventory, "slot_melee", f.item), nil,
            "saved policy and healthy registry cannot grant before installation")
        H.equal(admission_calls, 1); H.equal(constructor_calls, 1)
        f.slot.item_template = f.template
        local admitted = owner.capture(f.inventory, "slot_melee", f.item)
        H.truthy(admitted, "DI-only positive capture exercises the actual capture path")
        H.equal(owner.factor(admitted, "ground", f.first, f.input, f.locomotion, f.unit), 1.05)
        for _, replacement in ipairs({ old_sword_template, {} }) do
            f.slot.item_template = replacement
            H.equal(owner.factor(admitted, "ground", f.first, f.input, f.locomotion, f.unit), 1,
                "a stale or replaced installed template denies the retained snapshot")
        end
        f.slot.item_template = nil
        H.equal(owner.factor(admitted, "ground", f.first, f.input, f.locomotion, f.unit), 1)
        H.equal(admission_calls, 2); H.equal(constructor_calls, 2,
            "movement reads never rerun admission or recursive constructor validation")
    end)
    H.test("645 movement PURE UNIT capture retains the exact wielded slot from the closed melee pair", function()
        for _, slot_name in ipairs({ "slot_melee", "slot_ranged" }) do
            -- DI-only capture contract, not real catalogue/actor admission.
            local f, admissions, constructors = fixture(), 0, 0
            f.equipment.slots, f.equipment.wielded_slot = { [slot_name] = f.slot }, slot_name
            f.actor.inventory_profile = function(self, inventory, slot, item)
                H.equal(self, f.actor); H.equal(inventory, f.inventory); H.equal(slot, slot_name); H.equal(item, f.item)
                admissions = admissions + 1; return "empire_soldier"
            end
            f.runtime.describe = function(self, item, backend_id, admit)
                H.equal(self, f.runtime); H.equal(item, f.item); H.equal(backend_id, nil)
                H.equal(admit(), "empire_soldier")
                return { item_key = "es_1h_sword", item_data = f.item, identity = "unit-record",
                    family_id = "one_handed_swords", style_id = "synthetic-view-style",
                    package = { template = "cwv_645_mace_sword_style", style_id = "synthetic-view-style" } }
            end
            f.constructor.template = function(direction)
                H.equal(direction, "mace_on_empire_sword"); constructors = constructors + 1
                return "cwv_645_mace_sword_style", f.template
            end
            local owner = M.bind(f.deps)
            for _, denied in ipairs({ "slot_hat", "slot_grenade", "foreign" }) do
                H.equal(owner.capture(f.inventory, denied, f.item), nil)
            end
            H.equal(admissions, 0); H.equal(constructors, 0)
            local s = owner.capture(f.inventory, slot_name, f.item)
            H.truthy(s, "actual capture admits the explicitly wielded closed slot")
            H.equal(s.slot_name, slot_name); H.equal(s.slot, f.slot)
            for _ = 1, 20 do H.equal(owner.factor(s, "ground", f.first, f.input, f.locomotion, f.unit), 1.05) end
            H.equal(admissions, 1); H.equal(constructors, 1, "no per-frame discovery")
            f.equipment.wielded_slot = slot_name == "slot_melee" and "slot_ranged" or "slot_melee"
            H.equal(owner.factor(s, "ground", f.first, f.input, f.locomotion, f.unit), 1)
            f.equipment.wielded_slot = slot_name
            f.equipment.slots[slot_name] = { item_data = f.item, item_template = f.template }
            H.equal(owner.factor(s, "ground", f.first, f.input, f.locomotion, f.unit), 1,
                "the same item/template in a replacement slot is not the admitted slot")
        end
    end)
    H.test("645 movement PURE UNIT raw table identities retain native userdata equality semantics", function()
        local f = fixture()
        local original, meta = f.player, { __eq = function() return true end }
        local foreign = {}; for key, value in pairs(original) do foreign[key] = value end
        setmetatable(original, meta); setmetatable(foreign, meta)
        f.player = foreign
        H.equal(f.factor(), 1, "equal-comparing local player table cannot impersonate captured player")
        f.player = original; setmetatable(original, nil)
        H.equal(f.factor(), 1.05)
        H.equal(type(newproxy), "function", "pinned Lua5.1 host userdata fixture required")
        local first = newproxy(true)
        getmetatable(first).__eq = function() return true end
        local second = newproxy(first)
        H.equal(rawequal(first, second), false); H.equal(first == second, true)
        f.unit, f.snapshot.unit = first, first
        f.player.player_unit, f.inventory._unit, f.status.unit, f.csm.unit, f.state.unit = first, first, first, first, first
        H.equal(f.owner.factor(f.snapshot, "ground", f.first, f.input, f.locomotion, second), 1.05,
            "native userdata equality is preserved rather than blindly replaced with rawequal")
        H.equal(f.graph_calls, 0)
    end)
    -- Optional source provenance only; the four native cases must all run in
    -- a focused requalification. No original movement oracle changes.
    H.test_if(native_available, "645 movement actual native ground preserves backward strafe and upstream speed", function()
        local f = fixture()
        local n = Native.new(H, native_root, f)
        local rows = {
            { direction = n.vec(0, 1, 0), speed = 4, strafe = 0.25, x = 0, y = 4.2 },
            { direction = n.vec(0, -1, 0), speed = 4, strafe = 0.25, x = 0, y = -2.1 },
            { direction = n.vec(1, 0, 0), speed = 4, strafe = 0.25, x = 1.05, y = 0 },
            { direction = n.vec(0, 1, 0), speed = 1.6, strafe = 0.25, x = 0, y = 1.68 },
        }
        for _, row in ipairs(rows) do
            for _ = 1, 3 do
                n.reset()
                H.equal(select("#", f.owner.ground(f.snapshot, n.helper.move_on_ground, f.first, f.input,
                    f.locomotion, row.direction, row.speed, f.unit, row.strafe)), 0)
                n.expect(row.x, row.y, 0, "actual native ground penalties must retain the single adapter factor")
            end
        end
        n.reset()
        f.owner.ground(nil, n.helper.move_on_ground, f.first, f.input, f.locomotion, n.vec(0, 1, 0), 4, f.unit)
        n.expect(0, 4, 0, "inactive actual native ground speed must remain unchanged")
        H.equal(f.graph_calls, 0)
        H.equal(f.status.move_speed_multiplier, 0.4); H.equal(f.status.move_speed_multiplier_timer, 0.25)
        H.deep_equal(n.settings, { move_speed = 5, backward_move_scale = 0.5, player_speed_scale = 1 })
    end, "optional exact native CharacterStateHelper source unavailable")
    H.test_if(native_available, "645 movement actual native air retains cap backward penalty and forced arguments", function()
        local f = fixture()
        local n = Native.new(H, native_root, f)
        for _, state in ipairs({ "jumping", "falling" }) do
            f.state.name = state; n.reset()
            f.owner.air(f.snapshot, n.helper.move_in_air, f.first, f.input, f.locomotion, 2, f.unit)
            n.expect(0, 2.1, 0, "actual uncapped native air input must receive one factor")
        end
        n.reset()
        f.owner.air(f.snapshot, n.helper.move_in_air, f.first, f.input, f.locomotion, 10, f.unit)
        n.expect(0, 5, 0, "actual native air cap must not be increased by the adapter")
        n.move = n.vec(0, -1, 0); n.reset()
        f.owner.air(f.snapshot, n.helper.move_in_air, f.first, f.input, f.locomotion, 2, f.unit)
        n.expect(0, -1.05, 0, "actual native backward penalty must remain after scaling")
        n.move = n.vec(0, 1, 0); n.reset()
        f.owner.air(f.snapshot, n.helper.move_in_air, f.first, f.input, f.locomotion, 2, f.unit, 1, 0)
        n.expect(0, -1, 0, "actual forced backward input must not receive the adapter factor")
        H.equal(n.move.y, 1, "native normalized forced input must not mutate the original input vector")
        n.reset()
        f.owner.air(f.snapshot, n.helper.move_in_air, f.first, f.input, f.locomotion, 2, f.unit, nil)
        n.expect(0, 2, 0, "an explicit optional nil must preserve native speed without admission broadening")
        H.equal(f.graph_calls, 0)
        H.deep_equal(n.settings, { move_speed = 5, backward_move_scale = 0.5, player_speed_scale = 1 })
    end, "optional exact native CharacterStateHelper source unavailable")
    H.test_if(native_available, "645 movement actual native denial and error identity remain intact", function()
        local f = fixture()
        local n = Native.new(H, native_root, f)
        f.slot.item_template = {}; n.reset()
        f.owner.ground(f.snapshot, n.helper.move_on_ground, f.first, f.input, f.locomotion, n.vec(0, 1, 0), 2, f.unit)
        n.expect(0, 2, 0, "actual native helper must run unchanged for a stale installed template")
        f.slot.item_template = f.template; f.state.name = "charged"; n.reset()
        f.owner.ground(f.snapshot, n.helper.move_on_ground, f.first, f.input, f.locomotion, n.vec(0, 1, 0), 2, f.unit)
        n.expect(0, 2, 0, "shared native helper callers outside ordinary walking must remain unchanged")
        f.state.name = "walking"
        local sentinel = {}
        f.first.current_rotation = function() error(sentinel, 0) end
        n.reset()
        local ok, failure = pcall(f.owner.ground, f.snapshot, n.helper.move_on_ground,
            f.first, f.input, f.locomotion, n.vec(0, 1, 0), 2, f.unit)
        H.equal(ok, false); H.equal(failure, sentinel, "actual native error must escape without replacement")
        H.equal(n.calls, 0); H.equal(f.graph_calls, 0)
        H.equal(f.status.move_speed_multiplier, 0.4); H.equal(f.status.move_speed_multiplier_timer, 0.25)
    end, "optional exact native CharacterStateHelper source unavailable")
    H.test_if(native_available, "645 movement actual native secondary slot keeps one factor native cap and forced-input limits", function()
        local f = fixture()
        f.equipment.slots = { slot_ranged = f.slot }
        f.equipment.wielded_slot, f.snapshot.slot_name = "slot_ranged", "slot_ranged"
        local n = Native.new(H, native_root, f)
        n.reset()
        f.owner.ground(f.snapshot, n.helper.move_on_ground, f.first, f.input,
            f.locomotion, n.vec(0, 1, 0), 2, f.unit)
        n.expect(0, 2.1, 0, "secondary ground receives exactly one factor")
        f.state.name = "falling"; n.reset()
        f.owner.air(f.snapshot, n.helper.move_in_air, f.first, f.input, f.locomotion, 10, f.unit)
        n.expect(0, 5, 0, "secondary native air cap remains native")
        n.reset()
        f.owner.air(f.snapshot, n.helper.move_in_air, f.first, f.input, f.locomotion, 2, f.unit, nil)
        n.expect(0, 2, 0, "secondary explicit optional nil cannot gain a factor")
        f.state.name, f.equipment.wielded_slot = "walking", "slot_melee"; n.reset()
        f.owner.ground(f.snapshot, n.helper.move_on_ground, f.first, f.input,
            f.locomotion, n.vec(0, 1, 0), 2, f.unit)
        n.expect(0, 2, 0, "switching away denies the retained secondary snapshot")
        H.equal(f.graph_calls, 0)
    end, "optional exact native CharacterStateHelper source unavailable")
end
