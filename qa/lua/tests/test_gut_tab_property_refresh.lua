return function(H, repo_root)
    local path = repo_root
        .. "/gui_tweaker_dev/scripts/mods/gui_tweaker_dev/_gut_tab_property_policy.lua"
    local Policy = assert(loadfile(path))()

    H.test("GUT #245 replaces stale properties for the same weapon", function()
        local cached = { key = "weapon", properties = { power_vs_skaven = 0.1 } }
        local live = { key = "weapon", properties = { attack_speed = 0.05 } }
        local changed, properties, reason = Policy.refresh(cached, live)
        H.truthy(changed)
        H.equal(reason, "changed")
        H.equal(properties.attack_speed, 0.05)
        H.equal(properties.power_vs_skaven, nil)
        properties.attack_speed = 0.2
        H.equal(live.properties.attack_speed, 0.05)
    end)

    H.test("GUT #245 ignores unchanged and mismatched weapons", function()
        local changed, _, reason = Policy.refresh(
            { key = "a", properties = { x = 1, y = 2 } },
            { key = "a", properties = { y = 2, x = 1 } })
        H.equal(changed, false)
        H.equal(reason, "unchanged")

        changed, _, reason = Policy.refresh({ key = "a" }, { key = "b" })
        H.equal(changed, false)
        H.equal(reason, "identity_mismatch")

        changed, _, reason = Policy.refresh(
            { key = "a", backend_id = "instance-one", properties = { x = 1 } },
            { key = "a", backend_id = "instance-two", properties = { x = 2 } })
        H.equal(changed, false)
        H.equal(reason, "instance_mismatch")
    end)

    H.test("GUT #245 production refresh is active-only and bounded", function()
        local runtime_path = repo_root
            .. "/gui_tweaker_dev/scripts/mods/gui_tweaker_dev/_gut_tab_property_refresh.lua"
        local file = assert(io.open(runtime_path, "rb"))
        local source = file:read("*a")
        file:close()
        H.truthy(source:find('self._active == true', 1, true) ~= nil)
        H.truthy(source:find('now + Policy.INTERVAL', 1, true) ~= nil)
        H.truthy(source:find('log_count < Policy.MAX_LOGS', 1, true) ~= nil)
        H.truthy(Policy.INTERVAL >= 0.25)
        H.truthy(Policy.MAX_LOGS <= 16)
    end)
end
