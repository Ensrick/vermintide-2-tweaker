return function(H, repo_root)
    -- Repairs #153/#292: keys the ENGINE localizes (hidden-passive perk rows via
    -- global Localize, Video-tab profile title/tooltip/dropdown labels via
    -- localize=true widget fields) must be supplied to the engine backend
    -- localizer, with VMF "%%" escapes collapsed (the engine path has no
    -- string.format pass for these strings, ui_utils.lua:36-38).
    local ENGINE_UI_LOC_KEYS = {
        "gut_hidden_passive_whc_headshot_name",
        "gut_hidden_passive_whc_headshot_desc",
        "gut_hidden_passive_whc_crit_name",
        "gut_hidden_passive_whc_crit_desc",
        "gut_hidden_passive_whc_combined_name",
        "gut_hidden_passive_whc_combined_desc",
        "gut_video_profiles_header",
        "gut_video_profile_selector",
        "gut_video_profile_selector_tooltip",
        "gut_video_profile_action",
        "gut_video_profile_action_tooltip",
    }

    local function read(path)
        local file = assert(io.open(repo_root .. "/" .. path, "rb"))
        local source = file:read("*a")
        file:close()
        return source
    end

    local localization = assert(loadfile(repo_root
        .. "/gui_tweaker_dev/scripts/mods/gui_tweaker_dev/gui_tweaker_dev_localization.lua"))()

    H.test("GUT #153/#292 every engine-rendered key has an English string", function()
        for _, key in ipairs(ENGINE_UI_LOC_KEYS) do
            local entry = localization[key]
            H.truthy(type(entry) == "table" and type(entry.en) == "string",
                key .. " missing from gui_tweaker_dev_localization.lua")
        end
    end)

    H.test("GUT #153/#292 escape collapse leaves single literal percents", function()
        -- Mirror the production gsub: the engine renders the collapsed string
        -- verbatim, so no "%%" may survive and every intended "%" must remain.
        local collapsed = localization.gut_hidden_passive_whc_headshot_desc.en
            :gsub("%%%%", "%%")
        H.equal(collapsed, "+25% headshot damage.")
        for _, key in ipairs(ENGINE_UI_LOC_KEYS) do
            local text = localization[key].en:gsub("%%%%", "%%")
            H.equal(text:find("%%%%"), nil, key .. " keeps a double percent after collapse")
        end
    end)

    H.test("GUT #153/#292 main file supplies the keys to the engine localizer", function()
        local main = read("gui_tweaker_dev/scripts/mods/gui_tweaker_dev/gui_tweaker_dev.lua")
        for _, key in ipairs(ENGINE_UI_LOC_KEYS) do
            H.truthy(main:find('"' .. key .. '"', 1, true),
                key .. " absent from the ENGINE_UI_LOC_KEYS supply list")
        end
        H.truthy(main:find(':gsub("%%%%", "%%")', 1, true),
            "the VMF %% escape collapse is missing")
        H.truthy(main:find("pcall(loc.append_backend_localizations, loc, _engine_ui_localizations())",
            1, true), "engine-UI keys are not appended to the backend localizer")
        H.truthy(main:find('"issue153_292_engine_ui_loc_supplied"', 1, true),
            "in-game loc-resolution regression check is missing")
        -- Re-registration path: the supply call must live inside the same
        -- function the LocalizationManager.init re-init hook drives.
        H.truthy(main:find('mod:hook_safe("LocalizationManager", "init"', 1, true),
            "LocalizationManager re-init re-registration is gone")
    end)
end
