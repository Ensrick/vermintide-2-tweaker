-- WP-WT-04: golden pin of the wt 3P animation funnel. Executes the real
-- Unit.animation_event hook body of the public tree (_wt_anim_remap.lua) under
-- stubs (qa/lua/fixtures/wt_anim_funnel_env.lua) over a career x subject x
-- wield x event matrix, and fails when any redirect or remap decision changes.
--
-- The #536 reload router (_wt_reload_3p.lua) is not loaded by this harness, so
-- WT.reload_3p_route is nil: "reload" takes the generic path here by design.
--
-- Regenerate (only for an intended behaviour change): set WT_ANIM_GOLDEN_OUT to
-- a path, run qa/check_lua_unit_tests.ps1, review the diff, then copy the file
-- to qa/lua/tests/fixtures/wt_anim_funnel_golden.txt.
--
-- Line format, one per (policy, career, subject, wield), sorted:
--   policy|career|template|key|wield|@wield>d;e1>d1;e2>d2,d2b;...
-- Only calls whose delivered list differs from the single source event are
-- listed; an empty right side means nothing was delivered.

return function(H, repo_root)
    local load_env = dofile(repo_root .. "/qa/lua/fixtures/wt_anim_funnel_env.lua")
    local wield_patches = dofile(repo_root
        .. "/weapon_tweaker/scripts/mods/weapon_tweaker/wt_wield_patches.lua")
    local golden_path = repo_root .. "/qa/lua/tests/fixtures/wt_anim_funnel_golden.txt"

    local careers = {
        "es_mercenary", "dr_ranger", "dr_slayer", "we_waywatcher",
        "wh_captain", "wh_priest", "bw_adept",
    }
    local policies = {
        { name = "all", has_event = function() return true end },
        { name = "none", has_event = function() return false end },
    }
    local extra_events = {
        "attack_swing_left", "attack_swing_right", "attack_swing_heavy_left",
        "attack_swing_stab_02", "attack_swing_heavy_stab",
    }

    local function sorted_keys(t)
        local keys = {}
        for k in pairs(t or {}) do keys[#keys + 1] = k end
        table.sort(keys)
        return keys
    end

    local function sorted_union(sets)
        local seen, out = {}, {}
        for _, set in ipairs(sets) do
            for _, value in ipairs(set) do
                if not seen[value] then
                    seen[value] = true
                    out[#out + 1] = value
                end
            end
        end
        table.sort(out)
        return out
    end

    local function remap_table_events(entry)
        local sets = { extra_events }
        for _, prefix in ipairs(sorted_keys(entry)) do
            local tbl = entry[prefix]
            if type(tbl) == "table" then sets[#sets + 1] = sorted_keys(tbl) end
        end
        return sorted_union(sets)
    end

    local function lookup(catalog, template, career)
        local row = catalog and catalog[template]
        return row and row[career]
    end

    local function build_text()
        local lines = {}
        for _, policy in ipairs(policies) do
            local env = load_env(repo_root, policy.has_event)
            local WT = env.mod._wt
            -- One recorder per module instance: the hook captures the first func
            -- it sees as its force-fire original, so every call must share it.
            local current
            local function rec(_, event) current[#current + 1] = event end

            local subjects = {}
            for _, template in ipairs(sorted_keys(WT.three_p_template_remaps)) do
                subjects[#subjects + 1] = {
                    kind = "template", template = template, key = "wt_probe_key",
                    events = remap_table_events(WT.three_p_template_remaps[template]),
                }
            end
            local key_list = sorted_keys(WT.three_p_key_remaps)
            key_list[#key_list + 1] = "es_1h_flail"
            key_list[#key_list + 1] = "bw_1h_flail_flaming"
            for _, key in ipairs(key_list) do
                subjects[#subjects + 1] = {
                    kind = "key", template = "wt_probe_template", key = key,
                    events = remap_table_events(WT.three_p_key_remaps[key]),
                }
            end
            local suffix_probes = {}
            for _, suffix in ipairs(sorted_keys(WT.suffix_career_map)) do
                suffix_probes[#suffix_probes + 1] = "probe" .. suffix
            end
            subjects[#subjects + 1] = {
                kind = "neutral", template = "wt_probe_template", key = "wt_probe_key",
                events = sorted_union({ sorted_keys(WT.anim_redirect),
                    sorted_keys(WT.career_anim_redirect), suffix_probes, { "reload", "idle" } }),
            }

            for _, career in ipairs(careers) do
                for _, subject in ipairs(subjects) do
                    local wields
                    if subject.kind == "template" then
                        wields = { lookup(wield_patches.patches, subject.template, career)
                            or lookup(wield_patches.bulk, subject.template, career)
                            or "to_wt_probe" }
                    elseif subject.kind == "key" then
                        wields = { "to_wt_probe" }
                    else
                        wields = sorted_keys(WT.career_anim_redirect)
                        wields[#wields + 1] = "to_wt_probe"
                    end
                    for _, wield in ipairs(wields) do
                        local unit = { career = career }
                        env.husk_wield(function() end, {
                            _unit = unit,
                            _equipment = { slots = { slot_melee = { item_data = {
                                key = subject.key, template = subject.template } } } },
                        }, "slot_melee")
                        local parts = {}
                        local function call(source, label)
                            current = {}
                            env.anim(rec, unit, source)
                            if not (#current == 1 and current[1] == source) then
                                parts[#parts + 1] = label .. ">" .. table.concat(current, ",")
                            end
                        end
                        call(wield, "@" .. wield)
                        for _, event in ipairs(subject.events) do call(event, event) end
                        lines[#lines + 1] = table.concat({ policy.name, career,
                            subject.template, subject.key, wield, table.concat(parts, ";") }, "|")
                    end
                end
            end
        end
        table.sort(lines)
        return table.concat(lines, "\n") .. "\n", #lines
    end

    local function read_file(path)
        local file = io.open(path, "rb")
        if not file then return nil end
        local text = file:read("*a")
        file:close()
        return (text:gsub("\r\n", "\n"))
    end

    local function split_lines(text)
        local out = {}
        for line in text:gmatch("([^\n]*)\n") do out[#out + 1] = line end
        return out
    end

    H.test("WT 3P animation funnel matches the golden decision table", function()
        local fresh, count = build_text()
        local out_path = os.getenv("WT_ANIM_GOLDEN_OUT")
        if out_path and out_path ~= "" then
            local file = assert(io.open(out_path, "wb"))
            file:write(fresh)
            file:close()
        end
        H.truthy(count > 0 and count < 3000, "golden must stay under 3000 lines, got " .. count)
        local golden = read_file(golden_path)
        H.truthy(golden ~= nil, "missing golden " .. golden_path)
        if golden == fresh then return end
        local want, got = split_lines(golden), split_lines(fresh)
        for i = 1, math.max(#want, #got) do
            if want[i] ~= got[i] then
                error(string.format("funnel golden differs at line %d:\n  golden: %s\n  actual: %s",
                    i, tostring(want[i]), tostring(got[i])), 0)
            end
        end
        error("funnel golden differs (line endings or trailing text)", 0)
    end)
end
