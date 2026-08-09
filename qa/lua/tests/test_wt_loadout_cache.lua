return function(H, repo_root)
    local public_path = repo_root
        .. "/weapon_tweaker/scripts/mods/weapon_tweaker/_wt_loadout_cache_policy.lua"
    local dev_path = repo_root
        .. "/weapon_tweaker_dev/scripts/mods/weapon_tweaker_dev/_wt_loadout_cache_policy.lua"
    local public_native_path = repo_root
        .. "/weapon_tweaker/scripts/mods/weapon_tweaker/_wt_native_weapon_ownership.lua"
    local dev_native_path = repo_root
        .. "/weapon_tweaker_dev/scripts/mods/weapon_tweaker_dev/_wt_native_weapon_ownership.lua"
    local Public = assert(loadfile(public_path))()
    local Dev = assert(loadfile(dev_path))()
    local PublicNative = assert(loadfile(public_native_path))()
    local DevNative = assert(loadfile(dev_native_path))()

    local function read(path)
        local file = assert(io.open(path, "rb"))
        local source = file:read("*a")
        file:close()
        return source
    end

    local function each_policy(body)
        body(Public, "public")
        body(Dev, "dev")
    end

    H.test("WT #1190 public and dev cache policies remain identical", function()
        H.equal(read(public_path), read(dev_path))
        H.equal(Public.SCHEMA_VERSION, 2)
        H.equal(Dev.SCHEMA_VERSION, Public.SCHEMA_VERSION)
    end)

    H.test("WT #1190 immutable native ownership matches the canonical 83-weapon dump", function()
        H.equal(read(public_native_path), read(dev_native_path))
        local careers = {
            "es_mercenary", "es_huntsman", "es_knight", "es_questingknight",
            "dr_ranger", "dr_ironbreaker", "dr_slayer", "dr_engineer",
            "we_waywatcher", "we_maidenguard", "we_shade", "we_thornsister",
            "wh_captain", "wh_bountyhunter", "wh_zealot", "wh_priest",
            "bw_adept", "bw_scholar", "bw_unchained", "bw_necromancer",
        }
        local expected = {}
        local weapon_count = 0
        for line in io.lines(repo_root .. "/dumps/weapon_native_careers.txt") do
            local weapon_key, slot_type, display_name, csv = line:match(
                "^%s*(.-)%s*|%s*(.-)%s*|%s*(.-)%s*|%s*(.-)%s*$")
            H.truthy(weapon_key and slot_type and display_name and csv,
                "malformed weapon-native dump row")
            weapon_key = weapon_key:gsub("^\239\187\191", "")
            weapon_count = weapon_count + 1
            expected[weapon_key] = {}
            for career_name in csv:gmatch("[^,%s]+") do
                expected[weapon_key][career_name] = true
            end
        end
        H.equal(weapon_count, 83)

        for weapon_key, native_careers in pairs(expected) do
            for _, career_name in ipairs(careers) do
                local expected_native = native_careers[career_name] == true
                H.equal(PublicNative.is_native(career_name, weapon_key), expected_native,
                    "public mismatch " .. career_name .. "/" .. weapon_key)
                H.equal(DevNative.is_native(career_name, weapon_key), expected_native,
                    "dev mismatch " .. career_name .. "/" .. weapon_key)
            end
        end
    end)

    H.test("WT #1190 ownership ignores pre-mutated can_wield and fails unknown pairs closed", function()
        local pre_mutated_item = { can_wield = { "dr_ranger", "dr_slayer" } }
        H.equal(pre_mutated_item.can_wield[2], "dr_slayer")
        H.equal(PublicNative.is_native("dr_slayer", "dr_handgun"), false)
        H.equal(PublicNative.is_native("dr_slayer", "future_modded_weapon"), false)
        H.equal(PublicNative.is_native("dr_slayer", "dr_2h_axe"), true)
        H.equal(PublicNative.is_native("es_questingknight", "es_1h_sword"), true)

        local snapshot = PublicNative.snapshot({
            dr_slayer = { "dr_2h_axe", "dr_handgun", "future_modded_weapon" },
        })
        H.equal(snapshot.dr_slayer.dr_2h_axe, true)
        H.equal(snapshot.dr_slayer.dr_handgun, false)
        H.equal(snapshot.dr_slayer.future_modded_weapon, false)
    end)

    H.test("WT #1190 schema reset rejects rowless and malformed cache state", function()
        each_policy(function(Policy, stream)
            local legacy = { dr_slayer = { slot_melee = "greataxe" } }
            local normalized, schema, reset = Policy.ensure_schema(legacy, 1)
            H.equal(schema, Policy.SCHEMA_VERSION, stream)
            H.equal(reset, true, stream)
            H.equal(next(normalized), nil, stream)
            H.equal(legacy.dr_slayer.slot_melee, "greataxe",
                stream .. " normalization mutated caller-owned legacy state")

            normalized, schema, reset = Policy.ensure_schema(legacy, Policy.SCHEMA_VERSION)
            H.equal(reset, true, stream .. " accepted legacy shape under current marker")
            H.equal(next(normalized), nil, stream)

            local current = { dr_slayer = { [3] = { slot_melee = "dual_hammers" } } }
            normalized, schema, reset = Policy.ensure_schema(current, Policy.SCHEMA_VERSION)
            H.equal(normalized, current, stream .. " replaced valid current cache")
            H.equal(reset, false, stream)
        end)
    end)

    H.test("WT #1190 set get and clear are isolated by saved row", function()
        each_policy(function(Policy, stream)
            local cache = {}
            H.equal(Policy.set(cache, "dr_slayer", 1, "slot_melee", "coghammer"), true, stream)
            H.equal(Policy.set(cache, "dr_slayer", 3, "slot_melee", "dual_hammers"), true, stream)
            H.equal(Policy.set(cache, "dr_slayer", 3, "slot_ranged", "dual_axes"), true, stream)

            H.equal(Policy.get(cache, "dr_slayer", 1, "slot_melee"), "coghammer", stream)
            H.equal(Policy.get(cache, "dr_slayer", 2, "slot_melee"), nil, stream)
            H.equal(Policy.get(cache, "dr_slayer", 3, "slot_melee"), "dual_hammers", stream)

            H.equal(Policy.clear(cache, "dr_slayer", 3, "slot_melee"), true, stream)
            H.equal(Policy.get(cache, "dr_slayer", 1, "slot_melee"), "coghammer", stream)
            H.equal(Policy.get(cache, "dr_slayer", 3, "slot_melee"), nil, stream)
            H.equal(Policy.get(cache, "dr_slayer", 3, "slot_ranged"), "dual_axes", stream)
            Policy.clear(cache, "dr_slayer", 3, "slot_ranged")
            Policy.clear(cache, "dr_slayer", 1, "slot_melee")
            H.equal(cache.dr_slayer, nil, stream .. " left empty cache branches")
        end)
    end)

    H.test("WT #1190 added rows clone only their selected-row overlay", function()
        each_policy(function(Policy, stream)
            local cache = {}
            Policy.set(cache, "dr_slayer", 2, "slot_melee", "dual_hammers")
            Policy.set(cache, "dr_slayer", 1, "slot_melee", "greataxe")

            H.equal(Policy.clone_added_row(cache, "dr_slayer", 2, 3), true, stream)
            H.equal(Policy.get(cache, "dr_slayer", 3, "slot_melee"), "dual_hammers", stream)
            Policy.set(cache, "dr_slayer", 2, "slot_ranged", "throwing_axes")
            H.equal(Policy.get(cache, "dr_slayer", 3, "slot_ranged"), nil,
                stream .. " clone aliases its source row")
            H.equal(Policy.get(cache, "dr_slayer", 1, "slot_melee"), "greataxe", stream)

            H.equal(Policy.clone_added_row(cache, "dr_ranger", 1, 2), false, stream)
            H.equal(cache.dr_ranger, nil, stream)
        end)
    end)

    H.test("WT #1190 deletion shifts sparse cached rows without bleeding careers", function()
        each_policy(function(Policy, stream)
            local cache = {
                dr_slayer = {
                    [1] = { slot_melee = "greataxe" },
                    [3] = { slot_melee = "dual_hammers" },
                    [5] = { slot_ranged = "throwing_axes" },
                },
                dr_ranger = { [2] = { slot_melee = "coghammer" } },
            }

            H.equal(Policy.delete_row(cache, "dr_slayer", 2, 5), true, stream)
            H.equal(Policy.get(cache, "dr_slayer", 1, "slot_melee"), "greataxe", stream)
            H.equal(Policy.get(cache, "dr_slayer", 2, "slot_melee"), "dual_hammers", stream)
            H.equal(Policy.get(cache, "dr_slayer", 3, "slot_melee"), nil, stream)
            H.equal(Policy.get(cache, "dr_slayer", 4, "slot_ranged"), "throwing_axes", stream)
            H.equal(cache.dr_slayer[5], nil, stream)
            H.equal(Policy.get(cache, "dr_ranger", 2, "slot_melee"), "coghammer", stream)

            H.equal(Policy.delete_row(cache, "dr_slayer", 6, 5), false, stream)
        end)
    end)

    H.test("WT #1190 row overlay is deep copied and never mutates either input", function()
        each_policy(function(Policy, stream)
            local source = {
                [1] = { slot_melee = "axe", metadata = { label = "one" } },
                [2] = { slot_melee = "hammer", metadata = { label = "two" } },
            }
            local cache = { dr_slayer = {
                [1] = { slot_melee = "cross_one" },
                [2] = { slot_melee = "rejected" },
                [4] = { slot_melee = "outside_live_rows" },
            } }
            local seen = {}

            local output = Policy.overlay_rows(source, cache, "dr_slayer",
                function(backend_id, career_name, row, slot_name)
                    seen[#seen + 1] = table.concat({ backend_id, career_name, row, slot_name }, ":")
                    return backend_id ~= "rejected"
                end)

            H.equal(output[1].slot_melee, "cross_one", stream)
            H.equal(output[2].slot_melee, "hammer", stream)
            H.equal(output[4], nil, stream .. " created a nonexistent engine row")
            H.equal(source[1].slot_melee, "axe", stream .. " mutated source row")
            H.equal(cache.dr_slayer[1].slot_melee, "cross_one", stream .. " mutated cache row")
            H.truthy(output ~= source, stream .. " returned source table")
            H.truthy(output[1] ~= source[1], stream .. " shallow-copied row")
            H.truthy(output[1].metadata ~= source[1].metadata, stream .. " shallow-copied nested data")
            output[1].metadata.label = "changed"
            H.equal(source[1].metadata.label, "one", stream)
            H.equal(#seen, 2, stream .. " validated cache outside live rows")
        end)
    end)

    H.test("WT #1190 clear all preserves cache table identity", function()
        each_policy(function(Policy, stream)
            local cache = { dr_slayer = { [1] = { slot_melee = "axe" } } }
            local identity = cache
            H.equal(Policy.clear_all(cache), true, stream)
            H.equal(cache, identity, stream)
            H.equal(next(cache), nil, stream)
            H.equal(Policy.clear_all(cache), false, stream)
        end)
    end)

    H.test("WT #1190 backend hooks preserve row and ownership boundaries", function()
        local streams = {
            {
                root = repo_root .. "/weapon_tweaker/scripts/mods/weapon_tweaker/",
                entry = "weapon_tweaker.lua",
            },
            {
                root = repo_root .. "/weapon_tweaker_dev/scripts/mods/weapon_tweaker_dev/",
                entry = "weapon_tweaker_dev.lua",
            },
        }
        for _, stream in ipairs(streams) do
            local backend = read(stream.root .. "weapon_tweaker_backend.lua")
            local availability = read(stream.root .. "_wt_availability.lua")
            local diagnostics = read(stream.root .. "_wt_diagnostics.lua")
            local settings = read(stream.root .. "_wt_settings_runtime.lua")
            local entry = read(stream.root .. stream.entry)

            H.truthy(backend:find("and not is_native_weapon(career_name, weapon_key)", 1, true))
            H.truthy(backend:find("local optional_loadout_index = select(1, ...)", 1, true))
            H.truthy(backend:find('mod:hook(items_interface, "get_career_loadouts"', 1, true))
            H.truthy(backend:find('mod:hook(items_interface, "add_loadout"', 1, true))
            H.truthy(backend:find('mod:hook(items_interface, "delete_loadout"', 1, true))
            H.truthy(backend:find("type(loadouts[resolved_index]) ~= \"table\"", 1, true))
            H.truthy(backend:find("_bot_read_depth = _bot_read_depth + 1", 1, true))
            H.truthy(backend:find('return "not-ready", "backend hooks have not reached', 1, true))
            H.truthy(backend:find('return "not-run", "run /verify_wt_loadout_cache reset', 1, true))
            H.truthy(backend:find('observe_1190("row-preview"', 1, true))
            H.truthy(backend:find('and "native-evicted" or "disabled-evicted"', 1, true))
            H.truthy(backend:find("and event.writer_result == true", 1, true))
            H.truthy(backend:find("the game's loadout writer rejected a native weapon change", 1, true))

            local mirror_accessor = assert(backend:find("mirror.get_career_loadouts", 1, true))
            local mirror_field = assert(backend:find("mirror._career_loadouts", 1, true))
            H.truthy(mirror_accessor < mirror_field,
                "selected row must resolve through the GUT-aware accessor first")

            H.truthy(availability:find("_wt_native_weapon_ownership", 1, true))
            H.truthy(availability:find(
                "WT.native_weapon_ownership = _native_weapon_ownership.snapshot", 1, true))
            H.equal(availability:find("_capture_native_weapon_ownership", 1, true), nil)
            H.truthy(diagnostics:find("local WT = mod._wt", 1, true))
            H.truthy(diagnostics:find('mod:command("verify_wt_loadout_cache"', 1, true))
            H.truthy(diagnostics:find('["not-run"] = "CORE NOT RUN"', 1, true))
            H.truthy(settings:find('c.backend.clear_loadout_cache("backend-hook-setting-changed")', 1, true))
            H.truthy(availability:find('backend.clear_loadout_cache("mod-disabled")', 1, true))
            H.truthy(backend:find('issue1190_loadout_cache_is_row_scoped', 1, true))
            H.truthy(entry:find("weapon_backend.install", 1, true))
        end
    end)
end
