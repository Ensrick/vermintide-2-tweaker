return function(H, repo_root)
    local function read(path)
        local file = assert(io.open(path, "rb"))
        local source = file:read("*a")
        file:close()
        return source
    end

    local cos_base = repo_root .. "/cosmetics_tweaker/scripts/mods/cosmetics_tweaker/"
    local stable_path = repo_root
        .. "/crafting_in_modded/scripts/mods/crafting_in_modded/_cim_custom_glow_notice.lua"
    local dev_path = repo_root
        .. "/crafting_in_modded_dev/scripts/mods/crafting_in_modded_dev/_cim_custom_glow_notice.lua"
    local Gateway = dofile(cos_base .. "_cos_magic_skin_gateway.lua")
    local Notice = dofile(stable_path)

    H.test("Cosmetics #48 magic skins are hidden by default with equipped guard", function()
        local families = { weave = "weaves", shyish = "shyish", blue = "blue_glow" }
        local function widget(key) return { content = { skin_key = key }, offset = { 0, 0, 0 } } end
        local kept, removed = Gateway.filter({
            widget("plain"), widget("weave"), widget("shyish"),
            widget("blue"), widget("equipped_weave"),
        }, "equipped_weave", function(key)
            if key == "equipped_weave" then return "weaves" end
            return families[key]
        end, false)
        H.equal(removed, 2)
        H.equal(#kept, 3)
        H.equal(kept[1].content.skin_key, "plain")
        H.equal(kept[3].content.skin_key, "equipped_weave")
        H.truthy(kept[1].offset[1] < kept[3].offset[1])
    end)

    H.test("Cosmetics #48 explicit gateway reveals every magic-family skin", function()
        local widgets = {
            { content = { skin_key = "weave" }, offset = { 9, 0, 0 } },
            { content = { skin_key = "shyish" }, offset = { 19, 0, 0 } },
        }
        local kept, removed = Gateway.filter(widgets, nil,
            function() return "weaves" end, true)
        H.equal(kept, widgets)
        H.equal(removed, 0)
        H.equal(widgets[1].offset[1], 9, "reveal path must retain vanilla geometry")
    end)

    H.test("CIM #48 custom-glow absence notice is identical across streams", function()
        H.equal(read(stable_path), read(dev_path))
    end)

    H.test("CIM #48 dev absence notice emits via pcall(printf), not mod:info", function()
        -- The user runs with mod logging OFF, so mod:info never reaches their
        -- console log and the pinned card's step 4 evidence goes missing.
        -- Dev stream only: stable picks the conversion up at promotion.
        local entry = read(repo_root
            .. "/crafting_in_modded_dev/scripts/mods/crafting_in_modded_dev/_cim_forge_state_owner.lua")
        H.truthy(entry:find("custom_glow blobs that won't apply", 1, true),
            "custom_glow absence notice emission missing from forge owner")
        H.truthy(entry:find("pcall(print_line,", 1, true),
            "notice must emit through the injected raw-print adapter")
        local main_entry = read(repo_root
            .. "/crafting_in_modded_dev/scripts/mods/crafting_in_modded_dev/crafting_in_modded_dev.lua")
        H.truthy(main_entry:find(
            "print_line = function(fmt, ...) printf(fmt, ...) end", 1, true),
            "production must bind the notice adapter to raw printf")
    end)

    H.test("CIM #48 custom-glow absence notice emits once and remains log-only", function()
        local notice = Notice.new()
        local records = {
            a = { custom_glow = { schema = 1 } },
            b = { custom_glow = { schema = 1 } },
            c = {},
        }
        local count, emit = notice:observe(records, function() return {} end)
        H.equal(count, 2)
        H.equal(emit, false, "installed Cosmetics suppresses the notice")
        count, emit = notice:observe(records, function() return nil end)
        H.equal(count, 2)
        H.equal(emit, true)
        H.equal(notice:observe(records, function() return nil end), 2)
        local _, second_emit = notice:observe(records, function() return nil end)
        H.equal(second_emit, false)
    end)

    H.test("CIM #48 custom-glow notice fails closed on provider lookup error", function()
        local notice = Notice.new()
        local records = { a = { custom_glow = true } }
        local count, emit = notice:observe(records, function() error("planted") end)
        H.equal(count, 1)
        H.equal(emit, false)
        local _, retry_emit = notice:observe(records, function() return nil end)
        H.equal(retry_emit, true, "failed lookup must remain retryable")
    end)
end
