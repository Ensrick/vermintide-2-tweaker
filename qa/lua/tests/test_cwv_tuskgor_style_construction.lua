-- Offline actual-source Tuskgor coverage; not gameplay or VMF acceptance.
return function(H, root)
    local F = assert(loadfile(root .. "/qa/lua/fixtures/cwv_tuskgor_style_construction_harness.lua"))()
    local available = F.available(root)
    local function native_test(name, body)
        H.test_if(available, name, body, "optional sibling6.13 native Tuskgor/Elf inputs absent")
    end
    local function native_snapshot(c)
        local profiles = {}; for _, name in ipairs(F.names) do profiles[name] = c.env.DamageProfileTemplates[name] end
        return assert(c.graph.capture({ c.env.Weapons[F.donor], c.env.Weapons[F.receiver], profiles,
            c.env.PowerLevelTemplates, c.env.ItemMasterList.we_spear }, 8192, 131072))
    end
    native_test("#645 Tuskgor complete native attack graph exact scalars and Elf non-attack identity", function()
        local c = F.new(H, root); local native = native_snapshot(c)
        local generation, audits = c.state._cwv_damage_profile_generation, c.audit().profiles
        local owner = c.create(); H.truthy(owner.construct(), "actual detached Tuskgor constructor must succeed")
        F.verify(H, c, owner)
        H.equal(c.state._cwv_damage_profile_generation, generation + 9, "nine actual profile encounters")
        H.equal(c.audit().profiles, audits + 9, "real private audit contribution, not a substitute cloner")
        H.truthy(c.graph.intact(native), "complete native sources, physical Elf item and power tables unchanged")
        local _, value = owner.template(); local receiver = c.env.Weapons[F.receiver]
        H.equal(value.max_fatigue_points, 6); H.equal(value.actions.action_one.push.push_radius, 2.4)
        H.truthy(F.same(value.buffs, receiver.buffs), "Elf native dodge retained")
        H.truthy(F.same(value.actions.action_two, receiver.actions.action_two), "Elf native block graph retained")
        H.truthy(F.same(value.actions.action_inspect, receiver.actions.action_inspect), "Elf native ordered inspect graph retained")
        H.truthy(F.same(value.actions.action_wield, receiver.actions.action_wield), "Elf native wield action retained")
        H.equal(value.actions.action_two.default.allowed_chain_actions[3].action, "action_wield", "Elf block wield row stays last, not Tuskgor-first")
        H.equal(rawget(c.env.ItemMasterList, F.key), nil, "no craft item/style activation")
    end)
    native_test("#645 Tuskgor repeated construction does not compound scalars or publish again", function()
        local c = F.new(H, root); local owner = c.create(); H.truthy(owner.construct()); F.verify(H, c, owner)
        local before = F.snapshot(c)
        H.truthy(owner.construct()); H.truthy(c.graph.intact(before), "whole state unchanged on second construction")
        F.verify(H, c, owner)
        local empty = F.new(H, root); empty.state._cwv_wire_fallback_profile_id = nil
        local first = empty.create(); H.truthy(first.construct()); F.verify(H, empty, first)
        H.equal(empty.state._cwv_wire_fallback_profile_id, empty.lookup.heavy_slashing_tank, "first actual native profile encounter supplies fallback")
        local after = F.snapshot(empty); H.truthy(first.construct()); H.truthy(empty.graph.intact(after))
    end)
    native_test("#645 Tuskgor source-proven block-cost axis is not borrowed into Elf receiver", function()
        -- The historical value now comes from the actual WT entry/owner/ledger,
        -- not a literal cell assignment. The existing result assertions stay.
        for _, value in ipairs({ .5, .25 }) do
            local c = F.new(H, root, value == .25 and { history = "pre_3_1_delta" } or nil)
            H.equal(c.env.Weapons[F.donor].block_fatigue_point_multiplier, value)
            local native = native_snapshot(c); local owner = c.create(); H.truthy(owner.construct())
            F.verify(H, c, owner); local _, template = owner.template()
            H.equal(template.block_fatigue_point_multiplier, .5, "receiver block cost is authoritative")
            H.equal(c.env.Weapons[F.donor].block_fatigue_point_multiplier, value)
            H.truthy(c.graph.intact(native))
        end
    end)
    native_test("#645 Tuskgor both push axes scale impact and cleave without damage or timing bonus", function()
        local c = F.new(H, root); local owner = c.create(); H.truthy(owner.construct()); F.verify(H, c, owner)
        local _, template = owner.template(); local push = template.actions.action_one.push
        H.equal(rawget(push, "anim_time_scale"), nil, "ordinary push speed remains native absent")
        for _, name in ipairs({ "medium_push", "light_push" }) do
            local source, actual = c.env.DamageProfileTemplates[name], c.env.DamageProfileTemplates[F.prefix .. name]
            H.equal(actual.no_damage, true); H.equal(actual.is_push, true); H.equal(rawget(actual, "critical_strike"), nil)
            H.equal(actual.default_target.power_distribution.attack, source.default_target.power_distribution.attack)
            H.equal(actual.default_target.power_distribution.impact, source.default_target.power_distribution.impact * .85)
            H.equal(actual.cleave_distribution.attack, source.cleave_distribution.attack * .85)
            H.equal(actual.cleave_distribution.impact, source.cleave_distribution.impact * .85)
        end
    end)
    native_test("#645 Tuskgor foreign destinations malformed native profiles and aliasing clones refuse unchanged", function()
        local changes = {
            function(c) c.env.Weapons[F.key] = {} end,
            function(c) c.env.DamageProfileTemplates[F.prefix .. "heavy_slashing_tank"] = {} end,
            function(c) c.lookup[F.prefix .. "heavy_slashing_tank"] = 999 end,
            function(c) c.state._cwv_damage_profile_wire_source[F.prefix .. "heavy_slashing_tank"] = "foreign" end,
            function(c) c.state._cwv_wire_fallback_profile_id = 999999 end,
            function(c) c.env.DamageProfileTemplates.medium_spear_smiter_stab.critical_strike.impact_armor_power_modifer[5] = nil end,
            function(c) c.env.DamageProfileTemplates.light_push.critical_strike = {} end,
        }
        for _, change in ipairs(changes) do
            local c = F.new(H, root); change(c); local before = F.snapshot(c); local owner = c.create()
            H.equal(owner.construct(), false); H.truthy(owner.check()); H.equal(owner.template(), nil)
            H.truthy(c.graph.intact(before), "refusal does not repair/adopt/overwrite source")
        end
        local c = F.new(H, root); local before = F.snapshot(c)
        local owner = c.create({ clone = function(v) return v end })
        H.equal(owner.construct(), false); H.truthy(c.graph.intact(before), "aliasing clone is not writable owned data")
    end)
    native_test("#645 Tuskgor reached write and readback faults rollback profile lookup source template audit generation", function()
        for _, tag in ipairs({ "profile:", "numeric:", "reverse:", "source:", "template:", "audit:profiles", "audit:comparisons", "audit:failure", "generation", "fallback" }) do
            for _, mode in ipairs({ "write", "readback" }) do
                local c = F.new(H, root)
                if tag == "fallback" then c.state._cwv_wire_fallback_profile_id = nil end
                local before, hit = F.snapshot(c), 0; local options = {}
                local function matches(value) return value:sub(1, #tag) == tag end
                if mode == "write" then options.write = function(t, k, v, label)
                    rawset(t, k, v); if matches(label) then hit = hit + 1; error("reached Tuskgor write fault") end
                end else options.read = function(t, k, label)
                    if matches(label) then hit = hit + 1; return {} end; return rawget(t, k)
                end end
                local owner = c.create(options); H.equal(owner.construct(), false); H.equal(hit, 1, "actual journal class must be reached")
                H.truthy(owner.check()); H.equal(owner.template(), nil); H.truthy(c.graph.intact(before), "exact owned rollback")
            end
        end
    end)
    native_test("#645 Tuskgor intervening writer or root replacement is refused without erasing external work", function()
        for _, mode in ipairs({ "source", "root" }) do
            local c = F.new(H, root); local before = F.snapshot(c)
            local action = c.env.Weapons[F.donor].actions.action_one.heavy_attack_left
            local old_time, old_lookup, foreign, hit = action.total_time, c.lookup, {}, 0
            local owner = c.create({ scalar = function(settings)
                local planner = c.core.detached_scalar_factory(settings); local actual = planner.clone_damage_profile
                planner.clone_damage_profile = function(...)
                    local name = actual(...)
                    if hit == 0 then hit = 1; if mode == "source" then action.total_time = old_time + .001 else c.env.NetworkLookup.damage_profiles = foreign end end
                    return name
                end
                return planner
            end })
            H.equal(owner.construct(), false); H.equal(hit, 1); H.equal(owner.template(), nil)
            if mode == "source" then H.equal(action.total_time, old_time + .001); action.total_time = old_time
            else H.equal(c.env.NetworkLookup.damage_profiles, foreign); c.env.NetworkLookup.damage_profiles = old_lookup end
            H.truthy(c.graph.intact(before), "only the disclosed external write differed")
        end
    end)
    native_test("#645 Tuskgor retained source custom pair and receiver drift deny construction result without repair", function()
        local changes = {
            function(c) c.env.Weapons[F.receiver].max_fatigue_points = 99 end,
            function(c) c.env.Weapons[F.donor].actions.action_one.default.anim_event = "foreign" end,
            function(c) c.env.DamageProfileTemplates[F.prefix .. "heavy_slashing_tank"].cleave_distribution.attack = 99 end,
            function(c) c.lookup["medium_push"] = 999 end,
            function(c) c.lookup[F.prefix .. "light_push"] = 999 end,
        }
        for _, change in ipairs(changes) do
            local c = F.new(H, root); local owner = c.create(); H.truthy(owner.construct()); change(c)
            local after = F.snapshot(c); H.equal(owner.construct(), false); H.equal(owner.template(), nil); H.truthy(owner.check())
            H.truthy(c.graph.intact(after), "drift denial is observation, never a repair")
        end
    end)
end
