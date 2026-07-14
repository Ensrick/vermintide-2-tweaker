return function(H, repo_root)
    local core = dofile(repo_root
        .. "/enemy_tweaker/scripts/mods/enemy_tweaker/_et_enemy_modifiers_core.lua")

    local function complete_env()
        local env = {
            buff_templates = {}, network_buffs = {}, enhancements = {},
            breeds = {
                special = { special = true },
                monster = { boss = true },
                elite = { elite = true },
                lord = { boss = true },
            },
            lord_set = { lord = true },
        }
        for i, cfg in ipairs(core.MODIFIERS) do
            env.buff_templates[cfg.buff] = { buffs = {} }
            env.network_buffs[cfg.buff] = i
            env.network_buffs[i] = cfg.buff
            env.enhancements[cfg.enhancement] = env.enhancements[cfg.enhancement] or {}
            table.insert(env.enhancements[cfg.enhancement], cfg.buff)
        end
        return env
    end

    H.test("ET #453 catalog has thirteen grudge and two event modifiers", function()
        H.equal(#core.MODIFIERS, 15)
        local families = { grudge = 0, geheimnisnacht = 0, devious_delvings = 0 }
        local ids = {}
        for _, cfg in ipairs(core.MODIFIERS) do
            H.equal(ids[cfg.id], nil)
            ids[cfg.id] = true
            families[cfg.family] = families[cfg.family] + 1
        end
        H.equal(families.grudge, 13)
        H.equal(families.geheimnisnacht, 1)
        H.equal(families.devious_delvings, 1)
    end)

    H.test("ET #453 modifier census proves templates wire and enhancements", function()
        local rows, summary = core.audit(complete_env())
        H.equal(#rows, 15)
        H.equal(summary.template_missing, 0)
        H.equal(summary.wire_missing, 0)
        H.equal(summary.enhancement_missing, 0)
        H.equal(summary.categories.special, 1)
        H.equal(summary.categories.boss, 1)
        H.equal(summary.categories.elite, 1)
        H.equal(summary.categories.lord, 1)
    end)

    H.test("ET #453 census detects asymmetric wire and authored-row drift", function()
        local env = complete_env()
        local first, second = core.MODIFIERS[1], core.MODIFIERS[2]
        env.network_buffs[env.network_buffs[first.buff]] = "wrong"
        env.enhancements[second.enhancement] = {}
        local _, summary = core.audit(env)
        H.equal(summary.wire_missing, 1)
        H.equal(summary.enhancement_missing, 1)
    end)

    H.test("ET #453 category policy keeps lords out of ordinary bosses", function()
        local lord_set = { lord = true }
        H.equal(core.classify_breed("lord", { boss = true }, lord_set), "lord")
        H.equal(core.classify_breed("monster", { boss = true }, lord_set), "boss")
        H.equal(core.classify_breed("special", { special = true }, lord_set), "special")
        H.equal(core.classify_breed("elite", { elite = true }, lord_set), "elite")
        H.equal(core.classify_breed("trash", {}, lord_set), nil)
    end)

    H.test("ET #453 production is diagnostic and preserves hook ownership", function()
        local path = repo_root
            .. "/enemy_tweaker/scripts/mods/enemy_tweaker/_et_enemy_modifiers.lua"
        local f = assert(io.open(path, "rb"))
        local source = f:read("*a")
        f:close()
        H.truthy(source:find("issue453_modifier_catalog_wire_ready", 1, true))
        H.truthy(source:find("et_modifier_audit", 1, true))
        H.equal(source:find("mod:hook", 1, true), nil)
        H.equal(source:find("network_send", 1, true), nil)
    end)
end
