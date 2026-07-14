return function(H, repo_root)
    local function read(relative_path)
        local file = assert(io.open(repo_root .. "/" .. relative_path, "rb"))
        local source = file:read("*a")
        file:close()
        return source
    end

    local reveal = read("general_tweaker_dev/scripts/mods/general_tweaker_dev/_gt_lobby_failed_join_reveal.lua")
    local probes = read("general_tweaker_dev/scripts/mods/general_tweaker_dev/_gt_debug_probes.lua")
    local entry = read("general_tweaker_dev/scripts/mods/general_tweaker_dev/general_tweaker_dev.lua")

    H.test("GT failed-join popup remains exclusively GT-owned", function()
        H.truthy(reveal:find("local function _take_over_enriched_popup", 1, true))
        H.truthy(reveal:find("_take_over_enriched_popup(self, body, diff, _queue_enriched_popup)", 1, true))
        H.truthy(reveal:find("mod._gt_failnotify_take_over = _take_over_enriched_popup", 1, true))

        for line in reveal:gmatch("[^\r\n]+") do
            local code = line:match("^%s*(.-)%s*$")
            if code:sub(1, 2) ~= "--" then
                H.equal(code:match("%f[%w](self)%._popup_id%s*="), nil)
                H.equal(code:match("%f[%w](state_loading_self)%._popup_id%s*="), nil)
            end
        end
    end)

    H.test("GT runtime suite drives the shipped no-handoff boundary", function()
        H.truthy(entry:find('issue72_lobby_failnotify_never_hands_popup_to_vanilla', 1, true))
        H.truthy(entry:find('local take_over = mod._gt_failnotify_take_over', 1, true))
        H.truthy(entry:find('if wrote_popup_id or rawget(fake_sl, "_popup_id") ~= nil then', 1, true))
    end)

    H.test("GT debug probe update wrapper matches VMF dt-only callback", function()
        H.truthy(probes:find("mod.update = function(dt)", 1, true))
        H.truthy(probes:find("if prev_update then prev_update(dt) end", 1, true))
        H.equal(probes:find("mod.update = function(self, dt)", 1, true), nil)
        H.equal(probes:find("prev_update(self, dt)", 1, true), nil)
    end)
end

