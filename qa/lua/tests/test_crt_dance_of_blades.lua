return function(H, repo_root)
    local Policy = dofile(repo_root
        .. "/career_tweaker/scripts/mods/career_tweaker/_crt_dance_of_blades.lua")

    local function read(path)
        local f = assert(io.open(path, "rb"))
        local source = f:read("*a")
        f:close()
        return source
    end

    -- Mirrors BuffExtension.add_buff/_add_stacking_buff: every sub-buff owns a
    -- max-stack bucket keyed only by sub_buff_template.name. Duration refresh,
    -- when enabled, runs before the cap gate.
    local function simulate_engine_stack(sub_buffs, start_times)
        local buckets = {}
        local all = {}
        local per_hit = {}
        for hit = 1, #start_times do
            local start_time = start_times[hit]
            local added = { damage_dealt = 0, damage_taken = 0 }
            for i = 1, #sub_buffs do
                local sub = sub_buffs[i]
                local bucket = buckets[sub.name]
                if not bucket then
                    bucket = {}
                    buckets[sub.name] = bucket
                end
                if sub.duration and sub.refresh_durations then
                    for j = 1, #bucket do
                        bucket[j].start_time = start_time
                        bucket[j].end_time = start_time + sub.duration
                    end
                end
                if #bucket < sub.max_stacks then
                    local entry = {
                        id = hit,
                        name = sub.name,
                        stat_buff = sub.stat_buff,
                        start_time = start_time,
                        end_time = start_time + sub.duration,
                    }
                    bucket[#bucket + 1] = entry
                    all[#all + 1] = entry
                    added[sub.stat_buff] = added[sub.stat_buff] + 1
                end
            end
            per_hit[hit] = added
        end
        return { buckets = buckets, all = all, per_hit = per_hit }
    end

    local function active_counts(simulation, t)
        local counts = { damage_dealt = 0, damage_taken = 0 }
        for i = 1, #simulation.all do
            local entry = simulation.all[i]
            if entry.end_time > t then
                counts[entry.stat_buff] = counts[entry.stat_buff] + 1
            end
        end
        return counts
    end

    local function engine_has_authority(proc, is_server, is_local)
        local authority = proc.authority
        return not authority
            or authority == "server" and is_server
            or authority == "client" and is_local
    end

    local function grant_count(proc, parity_ok, contexts)
        local grants = 0
        for i = 1, #contexts do
            local context = contexts[i]
            if parity_ok and engine_has_authority(proc, context.is_server, context.is_local) then
                grants = grants + 1
            end
        end
        return grants
    end

    H.test("CRT #473 Dance uses independent engine stack buckets through the pair cap", function()
        local templates = Policy.templates()
        H.equal(Policy.validate(templates), true)
        local stack = templates[Policy.stack_buff].buffs
        local starts = {}
        for i = 1, 16 do starts[i] = (i - 1) * 0.01 end
        local simulation = simulate_engine_stack(stack, starts)
        for hit = 1, 15 do
            H.equal(simulation.per_hit[hit].damage_dealt, 1, "outgoing pair half missing at hit " .. hit)
            H.equal(simulation.per_hit[hit].damage_taken, 1, "incoming pair half missing at hit " .. hit)
        end
        H.equal(simulation.per_hit[16].damage_dealt, 0)
        H.equal(simulation.per_hit[16].damage_taken, 0)
        H.equal(#simulation.buckets[Policy.damage_stack], 15)
        H.equal(#simulation.buckets[Policy.damage_taken_stack], 15)
        H.equal(stack[1].multiplier * stack[1].max_stacks, 0.30)
        H.equal(stack[2].multiplier * stack[2].max_stacks, 0.30)
        H.equal(stack[1].refresh_durations, false)
        H.equal(stack[2].refresh_durations, false)

        local broken = Policy.templates()[Policy.stack_buff].buffs
        broken[1].name = Policy.stack_buff
        broken[2].name = Policy.stack_buff
        local old_shape = simulate_engine_stack(broken, starts)
        local old_counts = active_counts(old_shape, 0.15)
        H.equal(old_counts.damage_dealt, 8,
            "planted pre-fix shared bucket must reproduce the eight-stack outgoing cap")
        H.equal(old_counts.damage_taken, 7,
            "planted pre-fix shared bucket must reproduce the seven-stack incoming cap")
    end)

    H.test("CRT #473 Dance pairs retain staggered independent expiry", function()
        local stack = Policy.templates()[Policy.stack_buff].buffs
        local simulation = simulate_engine_stack(stack, { 0, 0.5, 1.25 })
        local by_id = {}
        for i = 1, #simulation.all do
            local entry = simulation.all[i]
            by_id[entry.id] = by_id[entry.id] or {}
            by_id[entry.id][entry.stat_buff] = entry
        end
        for id = 1, 3 do
            local pair = by_id[id]
            H.equal(pair.damage_dealt.start_time, pair.damage_taken.start_time)
            H.equal(pair.damage_dealt.end_time, pair.damage_taken.end_time)
        end
        H.equal(by_id[1].damage_dealt.end_time, 2)
        H.equal(by_id[2].damage_dealt.end_time, 2.5)
        H.equal(by_id[3].damage_dealt.end_time, 3.25)

        local expected = {
            { t = 1.99, count = 3 },
            { t = 2, count = 2 },
            { t = 2.49, count = 2 },
            { t = 2.5, count = 1 },
            { t = 3.25, count = 0 },
        }
        for i = 1, #expected do
            local counts = active_counts(simulation, expected[i].t)
            H.equal(counts.damage_dealt, expected[i].count)
            H.equal(counts.damage_taken, expected[i].count)
        end
    end)

    H.test("CRT #473 Dance has one server stack writer in every attack topology", function()
        local proc = Policy.templates()[Policy.proc_buff].buffs[1]
        local client_local = { is_server = false, is_local = true }
        local server_forwarded = { is_server = true, is_local = false }
        local host_local = { is_server = true, is_local = true }
        local bot_server = { is_server = true, is_local = false }

        H.equal(grant_count(proc, true, { client_local }), 0)
        H.equal(grant_count(proc, true, { server_forwarded }), 1)
        H.equal(grant_count(proc, true, { client_local, server_forwarded }), 1)
        H.equal(grant_count(proc, true, { host_local }), 1)
        H.equal(grant_count(proc, true, { bot_server }), 1)
        H.equal(grant_count(proc, false, { client_local, server_forwarded }), 0)
        H.equal(grant_count(proc, false, { host_local }), 0)

        local broken = Policy.templates()[Policy.proc_buff].buffs[1]
        broken.authority = nil
        H.equal(grant_count(broken, true, { client_local, server_forwarded }), 2,
            "planted pre-fix no-authority proc must reproduce the double writer")
    end)

    H.test("CRT #473 validation fails closed on authority and stack identity drift", function()
        local mutations = {
            function(t) t[Policy.proc_buff].buffs[1].authority = nil end,
            function(t) t[Policy.proc_buff].buffs[1].authority = "client" end,
            function(t) t[Policy.stack_buff].buffs[2].name = Policy.damage_stack end,
            function(t) t[Policy.stack_buff].buffs[2].stacking_name = Policy.damage_stack end,
            function(t) t[Policy.stack_buff].buffs[1].name = Policy.stack_buff end,
            function(t) t[Policy.stack_buff].buffs[3] = {} end,
            function(t) t[Policy.dodge_buff].buffs[1].dodge_buffs_to_add[2] = "wrong" end,
            function(t) t[Policy.stack_buff].buffs = nil end,
            function(t) t[Policy.proc_buff].buffs.extra = {} end,
            function(t) t[Policy.proc_buff].buffs[1] = true end,
        }
        for i = 1, #mutations do
            local templates = Policy.templates()
            mutations[i](templates)
            local ok, valid = pcall(Policy.validate, templates)
            H.equal(ok, true, "validation raised for mutation " .. i)
            H.equal(valid, false, "validation accepted mutation " .. i)
        end
        H.equal(Policy.validate(nil), false)
        H.equal(Policy.validate(1), false)
    end)

    H.test("CRT #473 Dance separates blocking dodge from enemy-hit trigger", function()
        local templates = Policy.templates()
        local dodge = templates[Policy.dodge_buff].buffs[1]
        local proc = templates[Policy.proc_buff].buffs[1]
        H.equal(dodge.event, "on_dodge")
        H.equal(dodge.buff_func, "crt_maidenguard_dance_blocking_dodge")
        H.equal(#dodge.dodge_buffs_to_add, 2)
        H.equal(proc.event, "on_hit")
        H.equal(proc.buff_func, "crt_wire_safe_add_buff")
        H.equal(proc.buff_to_add, Policy.stack_buff)
        H.equal(proc.authority, "server")
    end)

    H.test("CRT #473 production wiring preserves the stable network catalog", function()
        local source = require("crt_source").combined(repo_root)
        H.truthy(source:find("rework_we_maidenguard_dance_of_blades", 1, true))
        H.truthy(source:find("network_unsafe = true", 1, true))
        H.truthy(source:find("dance_talent_buffs_original", 1, true))
        H.truthy(source:find("crt_maidenguard_dance_blocking_dodge", 1, true))
        H.truthy(source:find("BuffTemplates[name] = _crt_make_stub()", 1, true))

        local balance = read(repo_root
            .. "/career_tweaker/scripts/mods/career_tweaker/career_tweaker_balance.lua")
        local names = assert(balance:match("local _CRT_BUFF_NAMES%s*=%s*{(.-)\n}"))
        local dodge_at = assert(names:find('"' .. Policy.dodge_buff .. '"', 1, true))
        local proc_at = assert(names:find('"' .. Policy.proc_buff .. '"', 1, true))
        local stack_at = assert(names:find('"' .. Policy.stack_buff .. '"', 1, true))
        H.truthy(dodge_at < proc_at and proc_at < stack_at,
            "network-visible Dance names changed order")
        H.equal(names:find(Policy.damage_stack, 1, true), nil,
            "local outgoing stack identity entered NetworkLookup")
        H.equal(names:find(Policy.damage_taken_stack, 1, true), nil,
            "local incoming stack identity entered NetworkLookup")
    end)

    H.test("CRT #473 setting and talent text are exposed", function()
        local data = read(repo_root .. "/career_tweaker/scripts/mods/career_tweaker/career_tweaker_data.lua")
        local loc = read(repo_root .. "/career_tweaker/scripts/mods/career_tweaker/career_tweaker_localization.lua")
        local hooks = read(repo_root .. "/career_tweaker/scripts/mods/career_tweaker/_career_tweaker_balance_hooks.lua")
        H.truthy(data:find('setting_id = "rework_we_maidenguard_dance_of_blades"', 1, true))
        H.truthy(loc:find("rework_we_maidenguard_dance_of_blades_description", 1, true))
        H.truthy(hooks:find('["kerillian_maidenguard_versatile_dodge_desc"]', 1, true))
    end)
end
