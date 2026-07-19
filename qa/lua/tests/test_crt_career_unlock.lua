return function(H, repo_root)
    local module_path = repo_root
        .. "/career_tweaker/scripts/mods/career_tweaker/_crt_career_unlock.lua"
    local main_path = repo_root
        .. "/career_tweaker/scripts/mods/career_tweaker/career_tweaker.lua"
    local Unlock = assert(loadfile(module_path))()

    local function read(path)
        local file = assert(io.open(path, "rb"))
        local source = file:read("*a")
        file:close()
        return source
    end

    local function fake_mod(enabled)
        local hooks, safe_hooks = {}, {}
        local mod = {}
        function mod:get(key)
            if key == "unlock_all_careers" then return enabled end
        end
        function mod:hook(class_name, method_name, callback)
            hooks[class_name .. "." .. method_name] = callback
        end
        function mod:hook_safe(class_name, method_name, callback)
            safe_hooks[class_name .. "." .. method_name] = callback
        end
        return mod, hooks, safe_hooks
    end

    H.test("CRT #728 unlock-all bypasses only the level gate", function()
        local mod, hooks = fake_mod(true)
        Unlock.install(mod)
        local called = 0
        local function vanilla()
            called = called + 1
            return false, "career_locked", "dlc", true
        end
        local hook = assert(hooks["ProgressionUnlocks.is_unlocked_for_profile"])
        local unlocked, reason, dlc_name, localized =
            hook(vanilla, "career_name", "empire_soldier", 1)
        H.equal(unlocked, true)
        H.equal(reason, nil)
        H.equal(dlc_name, nil)
        H.equal(localized, nil)
        H.equal(called, 0, "enabled setting must not enter vanilla level gate")
    end)

    H.test("CRT #728 disabled path preserves every vanilla return", function()
        local mod, hooks = fake_mod(false)
        Unlock.install(mod)
        local hook = assert(hooks["ProgressionUnlocks.is_unlocked_for_profile"])
        local unlocked, reason, dlc_name, localized = hook(function()
            return false, "career_locked", "owned_dlc", true
        end, "career_name", "empire_soldier", 1)
        H.equal(unlocked, false)
        H.equal(reason, "career_locked")
        H.equal(dlc_name, "owned_dlc")
        H.equal(localized, true)
    end)

    H.test("CRT #728 refresh covers both independent career grids", function()
        local mod, _, safe_hooks = fake_mod(true)
        Unlock.install(mod)
        local summary_calls = 0
        local summary = {
            _setup_hero_selection_widgets = function() summary_calls = summary_calls + 1 end,
        }
        safe_hooks["HeroWindowCharacterSummary.on_enter"](summary)

        local setup, selected, availability = 0, 0, 0
        local state = {
            _selected_profile_index = 1,
            _selected_career_index = 2,
            _setup_hero_selection_widgets = function() setup = setup + 1 end,
            _select_hero = function(_, profile, career, quiet, no_spawn)
                H.equal(profile, 1)
                H.equal(career, 2)
                H.equal(quiet, true)
                H.equal(no_spawn, true)
                selected = selected + 1
            end,
            _update_available_profiles = function() availability = availability + 1 end,
        }
        safe_hooks["CharacterSelectionStateCharacter.on_enter"](state)
        local hero_ok, selection_ok = mod._crt_refresh_career_unlock_ui()
        H.equal(hero_ok, true)
        H.equal(selection_ok, true)
        H.equal(summary_calls, 1)
        H.equal(setup, 1)
        H.equal(selected, 1)
        H.equal(availability, 1)

        safe_hooks["HeroWindowCharacterSummary.on_exit"](summary)
        safe_hooks["CharacterSelectionStateCharacter.on_exit"](state)
        local hero_after, selection_after = mod._crt_refresh_career_unlock_ui()
        H.equal(hero_after, false)
        H.equal(selection_after, false)
    end)

    H.test("CRT #728 source owns one unlock hook and no occupancy override", function()
        local module = read(module_path)
        local main = read(main_path)
        H.truthy(module:find(
            'mod:hook("ProgressionUnlocks", "is_unlocked_for_profile"', 1, true))
        H.truthy(module:find(
            'mod:hook_safe("CharacterSelectionStateCharacter",', 1, true))
        H.truthy(module:find(
            '[crt:728] character_select setting=%s', 1, true))
        H.truthy(main:find(
            'mod:dofile("scripts/mods/career_tweaker/_crt_career_unlock").install(mod)',
            1, true))
        H.equal(module:find("content.taken =", 1, true), nil,
            "CRT must not rewrite vanilla profile occupancy")
        H.equal(module:find("network_send", 1, true), nil,
            "local career-level unlock needs no network channel")
    end)
end
