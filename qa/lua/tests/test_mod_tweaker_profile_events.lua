return function(H, repo_root)
    local root = repo_root .. "/gui_tweaker_dev/scripts/mods/gui_tweaker_dev/"
    local Profiles = assert(loadfile(root .. "_mod_tweaker_profiles.lua"))()
    local ProfileEvents = assert(loadfile(root .. "_mod_tweaker_profile_events.lua"))()

    local function store()
        return {
            values = {},
            get = function(self, key) return self.values[key] end,
            set = function(self, key, value) self.values[key] = value end,
        }
    end

    H.test("profile diagnostic registry reports the committed slot", function()
        local s = store()
        Profiles.set_active(s, "ct_dev", 4)
        local events = ProfileEvents.new(Profiles, s)
        local received
        H.equal(events.register("ct_dev", function(info) received = info end), true)
        local ok, emitted = events.emit("ct_dev", "profile_switch")
        H.equal(ok, true)
        H.equal(emitted, true)
        H.deep_equal(received, {
            tab_id = "ct_dev", slot = 4, phase = "profile_switch",
        })
    end)

    H.test("profile diagnostic registry stays bounded to one owner per tab", function()
        local s = store()
        local events = ProfileEvents.new(Profiles, s)
        local first, second = 0, 0
        events.register("ct_dev", function() first = first + 1 end)
        events.register("ct_dev", function() second = second + 1 end)
        H.equal(events.emit("ct_dev"), true)
        H.equal(first, 0)
        H.equal(second, 1)
        local ok, emitted = events.emit("unregistered")
        H.equal(ok, true)
        H.equal(emitted, false)
    end)

    H.test("profile diagnostic registry contains observer failures", function()
        local s = store()
        local logs = {}
        local events = ProfileEvents.new(Profiles, s, function(fmt, ...)
            logs[#logs + 1] = string.format(fmt, ...)
        end)
        H.equal(events.register("", function() end), false)
        H.equal(events.register("ct_dev", "not a callback"), false)
        events.register("ct_dev", function() error("injected observer failure") end)
        local ok, err = events.emit("ct_dev")
        H.equal(ok, false)
        H.truthy(string.find(err, "injected observer failure", 1, true))
        H.equal(#logs, 1)
    end)

    H.test("both Mod Tweaker presentations emit only after profile apply", function()
        for _, name in ipairs({ "_mod_tweaker_view.lua", "_mod_tweaker_state.lua" }) do
            local file = assert(io.open(root .. name, "rb"))
            local source = file:read("*a")
            file:close()
            local switch_at = assert(string.find(source, ":_switch_profile(slot)", 1, true))
            local switch_end = assert(string.find(source, "\nfunction ", switch_at + 1, true))
            local block = string.sub(source, switch_at, switch_end - 1)
            local apply_at = assert(string.find(block, "self:apply_pending(category)", 1, true))
            local emit_at = assert(string.find(block,
                'mt:emit_profile_diagnostic(tab_id, "profile_switch")', 1, true))
            H.truthy(apply_at < emit_at, name .. " must emit after applying the target profile")
        end
    end)

    H.test("Mod Tweaker publishes an in-game regression check for the profile API", function()
        local file = assert(io.open(root .. "_mod_tweaker.lua", "rb"))
        local source = file:read("*a")
        file:close()
        H.truthy(string.find(source,
            '_gut_rt_register("issue919_profile_diagnostic_api"', 1, true))
    end)
end
