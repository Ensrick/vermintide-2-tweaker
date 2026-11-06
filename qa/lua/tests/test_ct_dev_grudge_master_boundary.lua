-- Selected #221/#107 correction: execute the actual registered Dev callback.
-- Native provenance: grudge_mark_settings.lua:4-15,126-140 defines separate
-- base/elite_base scaffolds and the 13 BossGrudgeMarks; the universal apply at
-- terror_event_utils.lua:84-105 consumes scaffold buffs too. #323 uses the
-- native elite_base + shockwave/ignore_death_aura recipe, not a BossGrudgeMark.
return function(H, repo_root, load_production)
    local path = "chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/_ct_boss_grudge_marks.lua"
    local function installer()
        if load_production then
            local value, actual = load_production(path)
            actual = assert(actual):gsub("\\", "/")
            assert(actual:find("/overlays/ctdev/", 1, true) and actual:sub(-#path) == path,
                "test did not load the actual Dev production overlay")
            return value
        end
        return assert(loadfile(repo_root .. "/" .. path))()
    end
    local function pack(...) return { n = select("#", ...), ... } end
    local names = {
        "commander", "crippling", "crushing", "frenzy", "intangible",
        "periodic_curse", "periodic_shield", "raging", "ranged_immune",
        "regenerating", "unstaggerable", "vampiric", "warping",
    }
    local function fixture(settings, is_server)
        local callback, hooks = nil, 0
        local native_marks = { foreign_mark = true }
        for _, name in ipairs(names) do native_marks[name] = true end
        local globals = { BossGrudgeMarks = native_marks, TerrorEventUtils = {} }
        local mod = {
            hook = function(_, target, method, fn)
                assert(target == globals.TerrorEventUtils and method == "apply_breed_enhancements")
                callback, hooks = fn, hooks + 1
            end,
            command = function() end,
        }
        local context = {
            mod = mod,
            effective_setting = function(id) return settings[id] end,
            is_banned = function(master, leaf) return master == true or leaf == true end,
            get_global = function(name) return globals[name] end,
            get_managers = function() return { player = { is_server = is_server } } end,
            dbg = function() end, printf = function() end,
        }
        local install = installer()
        local exports = install(context)
        return { callback = callback, exports = exports, marks = native_marks,
            reinstall = function() install(context); return hooks end }
    end

    H.test("CT Dev master ban removes all 13 listed marks but preserves native and foreign enhancement scaffolds", function()
        local f = fixture({ ban_all_grudge_marks = true,
            ban_grudge_mark_base = true, ban_grudge_mark_elite_base = true,
            ban_grudge_mark_shockwave = true }, true)
        local base = { "grudge_mark_health", "grudge_mark_damage", name = "base", no_attribute = true }
        local elite = { "grudge_mark_elite_health", "grudge_mark_damage", name = "elite_base", no_attribute = true }
        local shockwave, death_aura = { name = "shockwave" }, { name = "ignore_death_aura" }
        local foreign, termite = { name = "foreign_mark" }, { name = "termite_base" }
        local input = { base, elite, shockwave, death_aura, foreign, termite }
        for _, name in ipairs(names) do input[#input + 1] = { name = name } end
        local data = { enhancements = input, other = "preserved" }
        local unit, breed, calls = {}, { name = "chaos_warrior" }, 0
        local result = pack(f.callback(function(u, b, actual)
            calls = calls + 1
            assert(u == unit and b == breed and actual == data)
            H.deep_equal(actual.enhancements, { base, elite, shockwave, death_aura, foreign, termite })
            assert(actual.other == "preserved")
            return "native-first", nil, "native-third", nil
        end, unit, breed, data))
        assert(calls == 1 and result.n == 4 and result[1] == "native-first"
            and result[2] == nil and result[3] == "native-third" and result[4] == nil)
        assert(base[1] == "grudge_mark_health" and elite[1] == "grudge_mark_elite_health")
        assert(f.marks.foreign_mark == true)
        for _, name in ipairs(names) do assert(f.marks[name] == nil) end
    end)

    H.test("CT Dev individual Boss Grudge ban retains exact unrelated records and their ordering", function()
        local f = fixture({ ban_grudge_mark_commander = true,
            ban_grudge_mark_base = true, ban_grudge_mark_elite_base = true }, true)
        local base, elite, commander, warping = { name = "base" }, { name = "elite_base" },
            { name = "commander" }, { name = "warping" }
        local data = { enhancements = { base, commander, elite, warping } }
        f.callback(function(_, _, actual)
            H.deep_equal(actual.enhancements, { base, elite, warping })
        end, {}, {}, data)
        assert(f.marks.commander == nil and f.marks.warping == true)
    end)

    H.test("CT Dev disabled bans preserve native payload table identity", function()
        local f = fixture({}, true)
        local entries = { { name = "base" }, { name = "elite_base" }, { name = "commander" } }
        local data = { enhancements = entries }
        f.callback(function(_, _, actual) assert(actual == data and actual.enhancements == entries) end, {}, {}, data)
    end)

    H.test("CT Dev client never applies host-only universal enhancement filtering", function()
        local f = fixture({ ban_all_grudge_marks = true }, false)
        local entries = { { name = "base" }, { name = "elite_base" }, { name = "commander" } }
        local data = { enhancements = entries }
        f.callback(function(_, _, actual) assert(actual == data and actual.enhancements == entries) end, {}, {}, data)
    end)

    H.test("CT Dev master supports string marks while preserving unknown and malformed entries", function()
        local f = fixture({ ban_all_grudge_marks = true }, true)
        local unnamed = { no_attribute = true }
        local data = { enhancements = { "base", "commander", "elite_base", unnamed, 42, "foreign_mark" } }
        f.callback(function(_, _, actual)
            H.deep_equal(actual.enhancements, { "base", "elite_base", unnamed, 42, "foreign_mark" })
        end, {}, {}, data)
        for _, value in ipairs({ false, "not-a-list", {} }) do
            local untouched = { enhancements = value }
            f.callback(function(_, _, actual) assert(actual.enhancements == value) end, {}, {}, untouched)
        end
        f.callback(function(_, _, actual) assert(actual == nil) end, {}, {}, nil)
    end)

    H.test("CT Dev master toggling restores its baseline without duplicating the universal hook", function()
        local settings = { ban_all_grudge_marks = true }
        local f = fixture(settings, true)
        assert(f.reinstall() == 1)
        settings.ban_all_grudge_marks = false
        assert(f.exports.sync())
        for _, name in ipairs(names) do assert(f.marks[name] == true) end
        assert(f.marks.foreign_mark == true)
        settings.ban_all_grudge_marks = true
        assert(f.exports.sync())
        for _, name in ipairs(names) do assert(f.marks[name] == nil) end
        assert(f.marks.foreign_mark == true and f.reinstall() == 1)
    end)
end
