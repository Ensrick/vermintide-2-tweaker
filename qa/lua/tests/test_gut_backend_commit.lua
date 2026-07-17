return function(H, repo_root)
    package.path = repo_root .. "/?.lua;" .. package.path
    local Commit = dofile(repo_root .. "/gui_tweaker_dev/scripts/mods/gui_tweaker_dev/_gut_backend_commit.lua")

    H.test("GUI loadout scrub requests exactly one forced commit", function()
        local calls = 0
        local callback_seen
        local manager = {}
        manager.commit = function(self, skip_queue, callback)
            calls = calls + 1
            H.equal(self, manager)
            H.equal(skip_queue, true)
            callback_seen = callback
            return 42
        end

        local callback = function() end
        local ok, id = Commit.request(manager, callback)
        H.truthy(ok)
        H.equal(id, 42)
        H.equal(calls, 1)
        H.equal(callback_seen, callback)
    end)

    H.test("GUI loadout scrub rejects absent and throwing backend commits", function()
        local ok, detail = Commit.request(nil, function() end)
        H.equal(ok, false)
        H.equal(detail, "backend commit interface unavailable")

        ok, detail = Commit.request({ commit = function() error("offline") end }, function() end)
        H.equal(ok, false)
        H.truthy(detail:find("offline", 1, true))

        ok, detail = Commit.request({ commit = function() return nil end }, function() end)
        H.equal(ok, false)
        H.equal(detail, "backend mirror unavailable")
    end)

    H.test("GUI loadout scrub accepts only the engine success status", function()
        local ok, detail = Commit.classify_status("success")
        H.truthy(ok)
        H.equal(detail, "success")

        ok, detail = Commit.classify_status("commit_error")
        H.equal(ok, false)
        H.equal(detail, "commit_error")

        ok, detail = Commit.classify_status(nil)
        H.equal(ok, false)
        H.equal(detail, "missing status")
    end)
end
