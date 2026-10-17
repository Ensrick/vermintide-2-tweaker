-- #1655: Community Builds keeps cross-career browsing, but IMPORT SELECTED
-- BUILD commits only for the career being played and, while another career is
-- browsed, the disabled button names the career to switch to. The shipped
-- browser runs through its real draw, refresh and press path; its UI globals
-- come from a test-local chunk environment, so no real global is swapped.
return function(H, repo_root)
    local root = repo_root .. "/crafting_in_modded_dev/scripts/mods/crafting_in_modded_dev/"
    local CHECK = "issue1655_ranalds_import_needs_active_career"
    local COL_DISABLED = { 190, 24, 24, 24 }
    local LABELS = { [1] = "Mercenary", [14] = "Pyromancer", [15] = "Unchained" }

    -- find/replace (optional) loads a one-site mutant of the shipped browser, so
    -- the in-game check can be shown to FAIL when a wiring line is dropped.
    local function load_browser(registered, find, replace)
        local env = setmetatable({}, { __index = _G })
        env._G = env
        env.get_mod = function()
            if not registered then return {} end
            return { _cim_rt_register = function(name, fn) registered[name] = fn end }
        end
        env.UISceneGraph = {
            init_scenegraph = function() return {} end,
            update_scenegraph = function() end,
        }
        env.UIWidget = { init = function(def) return { content = def.content, style = def.style } end }
        env.UIRenderer = {
            begin_pass = function() end, draw_widget = function() end, end_pass = function() end,
        }
        local chunk
        if find then
            local file = assert(io.open(root .. "_cim_ranalds_browser.lua", "rb"))
            local source = file:read("*a"); file:close()
            local first, last = source:find(find, 1, true)
            assert(first and not source:find(find, last + 1, true), "mutation site must occur once: " .. find)
            chunk = assert(loadstring(source:sub(1, first - 1) .. replace .. source:sub(last + 1),
                "@_cim_ranalds_browser.lua(mutant)"))
        else
            chunk = assert(loadfile(root .. "_cim_ranalds_browser.lua"))
        end
        setfenv(chunk, env)
        return chunk()
    end

    local function configure(browser, active, imports)
        local careers = {}
        for id = 1, 20 do careers[id] = "career_" .. id end
        careers[1], careers[14], careers[15] = "es_mercenary", "bw_scholar", "bw_unchained"
        browser.configure({
            catalog = { CAREERS = careers, PAGE_SIZE = 5, sort = function(rows) return rows end },
            fetcher = {
                fetch = function(_, callback)
                    callback({ { name = "Fire build", username = "author", like_count = 3,
                        date_modified = "2026-09-21T21:27:00Z" } }, nil, { rejected = 0 })
                    return true
                end,
                cancel = function() end,
            },
            current_career_id = function() return active end,
            career_label = function(id) return LABELS[id] or ("Career " .. tostring(id)) end,
            import_build = function(build)
                imports[#imports + 1] = build
                return true, { build_name = build.name }
            end,
        })
    end

    local function frame(browser) browser.draw(nil, nil, {}, nil, 0) end

    local function press(browser, name)
        browser.widgets[name].content.hotspot.on_release = true
        frame(browser)
    end

    local function import_widget(browser)
        local widget = browser.widgets.import
        return widget.content.text, widget.style.rect.color
    end

    H.test("#1655 browsing another career disables IMPORT and names that career", function()
        local imports = {}
        local browser = load_browser()
        configure(browser, 15, imports)
        H.equal(browser.open(), true)
        frame(browser)
        press(browser, "career_prev")
        H.equal(browser.career_id, 14, "CAREER browse stays available")
        press(browser, "row_1")
        H.truthy(browser.selected, "a build of the browsed career can still be selected")
        frame(browser)
        local text, color = import_widget(browser)
        H.equal(text, "SWITCH TO Pyromancer TO IMPORT")
        H.deep_equal(color, COL_DISABLED, "the import button renders disabled")
        press(browser, "import")
        H.equal(#imports, 0, "the disabled button never reaches the importer")
        H.equal(browser.widgets.import.content.hotspot.on_release, false, "the press is consumed")
    end)

    -- Guard, not fail-before proof: this case passes before and after #1655.
    H.test("#1655 guard: the active career still imports (passes before and after the fix)", function()
        local imports = {}
        local browser = load_browser()
        configure(browser, 15, imports)
        browser.open()
        frame(browser)
        press(browser, "career_prev")
        press(browser, "career_next")
        H.equal(browser.career_id, 15)
        press(browser, "row_1")
        frame(browser)
        local text, color = import_widget(browser)
        H.equal(text, "IMPORT SELECTED BUILD")
        H.truthy(color[1] ~= COL_DISABLED[1], "the import button renders enabled")
        press(browser, "import")
        H.equal(#imports, 1)
        H.equal(imports[1].name, "Fire build")
        H.equal(browser.status, "Imported and equipped: Fire build")
    end)

    H.test("#1655 an unresolved active career never impersonates career 1", function()
        local imports = {}
        local browser = load_browser()
        configure(browser, nil, imports)
        browser.open()
        H.equal(browser.career_id, 1, "the browser still opens on the first career")
        frame(browser)
        press(browser, "row_1")
        frame(browser)
        H.equal((import_widget(browser)), "SWITCH TO Mercenary TO IMPORT")
        press(browser, "import")
        H.equal(#imports, 0)

        local file = assert(io.open(root .. "crafting_in_modded_dev.lua", "rb"))
        local entry = file:read("*a"); file:close()
        local first = assert(entry:find("current_career_id = function()", 1, true))
        local last = assert(entry:find("career_label = function(career_id)", first, true))
        local resolver = entry:sub(first, last)
        H.equal(resolver:find("return 1%s"), nil, "the entry resolver no longer falls back to career 1")
        H.truthy(resolver:find("return nil", 1, true), "the entry resolver reports an unknown career")
    end)

    H.test("#1655 the disabled label shrinks and upper-cases through the native text pass", function()
        local browser = load_browser()
        configure(browser, 15, {})
        browser.open()
        frame(browser)
        local style = browser.widgets.import.style.text
        H.equal(style.dynamic_font_size, true)
        H.equal(style.upper_case, true)
        H.equal(style.font_size, 21, "the label keeps the shipped size cap")
    end)

    H.test("#1655 shipped localization matches the fallback and has no format directive", function()
        local loc = assert(loadfile(root .. "crafting_in_modded_dev_localization.lua"))()
        local entry = loc.ranalds_import_switch
        H.truthy(type(entry) == "table" and type(entry.en) == "string", "ranalds_import_switch is localized")
        H.equal(entry.en, "SWITCH TO {career} TO IMPORT")
        H.equal(entry.en:find("%", 1, true), nil,
            "a bare string.format probe of the loc table cannot mark it invalid")
        H.equal(entry.en:find("\226\128\148", 1, true), nil, "no em dash")
        local file = assert(io.open(root .. "_cim_ranalds_browser.lua", "rb"))
        local source = file:read("*a"); file:close()
        H.truthy(source:find('import_switch = "SWITCH TO {career} TO IMPORT"', 1, true),
            "the browser fallback carries the same text")
    end)

    H.test("#1655 the in-game check passes on the shipped gate, skips an unknown career and catches a regression", function()
        local registered, imports = {}, {}
        local browser = load_browser(registered)
        configure(browser, 15, imports)
        local check = registered[CHECK]
        H.equal(type(check), "function", CHECK .. " is registered with /cim_regression_test")
        local original_import = browser.import_build
        frame(browser) -- builds the widgets; the browser stays closed
        local releases, store = {}, {}
        browser.widgets.import.content.hotspot = setmetatable({}, {
            __index = store,
            __newindex = function(_, key, value)
                if key == "on_release" then releases[#releases + 1] = tostring(value) end
                store[key] = value
            end,
        })
        H.equal(check(), nil, "PASS on the shipped gate")
        H.equal(table.concat(releases, ","), "true,false,true,false,false",
            "each probe press is consumed by the real IMPORT handler, then the hotspot is cleared")
        H.equal(#imports, 0, "the probe never reaches the real importer")
        H.equal(browser.open_state, false, "probe restores the closed browser")
        H.equal(browser.status, nil, "probe restores the status line")
        H.equal(browser.selected, nil, "probe restores the selection")
        H.equal(browser.import_build, original_import, "probe restores the importer")
        H.equal(browser.widgets.import.content.hotspot.on_release, false)

        local skipped = {}
        local unresolved = load_browser(skipped)
        configure(unresolved, nil, {})
        local verdict = skipped[CHECK]()
        H.equal(type(verdict) == "string" and verdict:sub(1, 5), "skip:", "unknown career is a named SKIP")

        local shipped_state = browser.import_state
        browser.import_state = function() return true, "IMPORT SELECTED BUILD" end
        local failure = check()
        browser.import_state = shipped_state
        H.truthy(type(failure) == "string" and failure:find("Career 16", 1, true)
            and failure:sub(1, 5) ~= "skip:", "a reverted gate is a FAIL naming the career")
    end)

    H.test("#1655 the in-game check fails when the drawn IMPORT label or colour is not wired", function()
        local mutants = {
            { "widgets.import.content.text = import_label", "", "label" },
            { "_set_button_color(widgets.import, false, not can_import)",
                "_set_button_color(widgets.import, false, false)", "colour" },
        }
        for _, mutant in ipairs(mutants) do
            local registered = {}
            local browser = load_browser(registered, mutant[1], mutant[2])
            configure(browser, 15, {})
            local verdict = registered[CHECK]()
            H.truthy(type(verdict) == "string" and verdict:find("drawn IMPORT", 1, true),
                "a dropped " .. mutant[3] .. " wiring is a FAIL, got " .. tostring(verdict))
        end
    end)
end
