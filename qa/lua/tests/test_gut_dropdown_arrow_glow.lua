-- Offline proof for #92: the Mod Tweaker dropdown arrow glow check and the widget it reads.
-- RainReligion's 0.2.354-dev log failed `mod_tweaker_dropdown_arrow_glow` with
-- `dropdown missing the drop_down_menu_arrow_clicked glow overlay`. The widget was right:
-- create_dropdown stores the sprite at content.arrow_glow_tex (the key its texture_uv pass
-- names), while the check read content.arrow_glow, which never existed. These cases lift
-- the SHIPPED DD_* constants and create_dropdown out of the definitions file (column-
-- anchored, so a reshaped block fails loudly) and drive the real contracts module on them.
return function(H, repo_root)
    local base = repo_root .. "/gui_tweaker_dev/scripts/mods/gui_tweaker_dev/"

    local function read(path)
        local file = assert(io.open(path, "rb"))
        local source = file:read("*a")
        file:close()
        return source
    end

    local defs_source = read(base .. "_mod_tweaker_definitions.lua")

    local function lift(start_needle, stop_needle)
        local from = defs_source:find(start_needle, 1, true)
        H.truthy(from, "not found in definitions: " .. start_needle)
        local stop = defs_source:find(stop_needle, from, true)
        H.truthy(stop, "no column-anchored end after: " .. start_needle)
        return defs_source:sub(from, stop + #stop_needle - 1)
    end

    -- The real factory with the real DD_* constants; only layout numbers and the shared
    -- row helpers are supplied here. UIWidget.init returns the definition, which carries
    -- the same element.passes / content / style the check reads in game.
    local function build_factory()
        local consts = lift('local DD_ARROW          = "drop_down_menu_arrow"',
            "local DD_ARROW_GLOW_ALPHA = 255\n")
        local factory = lift("local function create_dropdown(text, base_offset, depth, opts)", "\nend\n")
        local chunk = assert(loadstring(
            "local ROW_H, INDENT_PER_DEPTH, INPUT_FIELD_WIDTH, RA, LABEL_BASE_X, LIST_SG,"
                .. " _text_style, _dd_value_color_idle, _append_highlight, _append_separator = ...\n"
                .. consts .. factory .. "return create_dropdown\n", "@gut_create_dropdown"))
        local env = setmetatable({ UIWidget = { init = function(def) return def end } }, { __index = _G })
        setfenv(chunk, env)
        return chunk(32, 24, 400, 900, 12, "mt_list_start",
            function(x, y, w, size, color, halign)
                return { offset = { x, y, 10 }, size = { w, 32 }, font_size = size,
                         text_color = color, horizontal_alignment = halign }
            end,
            function() return { 255, 181, 181, 181 } end,
            function() end,
            function() end)
    end

    local function load_check(create_dropdown)
        local registered = {}
        local mod = {
            dofile = function(_, path)
                if path:find("_gut_dialogue_contract", 1, true) then return { install = function() end } end
                if path:find("_mod_tweaker_tab_labels", 1, true) then return { rt_checks = {} } end
                if path:find("_mod_tweaker_definitions", 1, true) then return { create_dropdown = create_dropdown } end
                error("unexpected dofile: " .. tostring(path))
            end,
        }
        local chunk = assert(loadfile(base .. "_gut_mod_tweaker_contracts.lua"))
        local env = setmetatable({
            get_mod = function() return mod end,
            printf = function() end,
        }, { __index = _G })
        env._G = env
        setfenv(chunk, env)
        chunk().install({
            register = function(name, fn) registered[name] = fn end,
            src_read = function() return nil end,
        })
        local check = registered.mod_tweaker_dropdown_arrow_glow
        H.equal(type(check), "function", "mod_tweaker_dropdown_arrow_glow not registered")
        return check
    end

    local function wrapped(mutate)
        local create = build_factory()
        return function(...)
            local dd = create(...)
            mutate(dd)
            return dd
        end
    end

    H.test("GUT #92 the shipped dropdown passes the arrow glow check", function()
        H.equal(load_check(build_factory())(), nil)
    end)

    H.test("GUT #92 the shipped glow matches native size and positions", function()
        local dd = build_factory()("probe", { 0, -10, 0 }, 0)
        local cy = dd.style.hotspot.offset[2] + dd.style.hotspot.size[2] / 2
        H.equal(dd.content.arrow_glow_tex, "drop_down_menu_arrow_clicked")
        H.deep_equal(dd.style.arrow_glow.texture_size, { 31, 28 })
        H.deep_equal(dd.style.arrow_down.texture_size, { 31, 15 })
        H.equal(dd.style.arrow_down.offset[2], cy - 7.5, "native base arrow at row centre -7.5")
        H.equal(dd.style.arrow_glow.offset[1], dd.style.arrow_down.offset[1])
    end)

    H.test("GUT #92 a glow sprite swap fails the check", function()
        local err = load_check(wrapped(function(dd) dd.content.arrow_glow_tex = "drop_down_menu_arrow" end))()
        H.truthy(err and err:find("glow overlay", 1, true), tostring(err))
    end)

    H.test("GUT #92 the undersized 31x15 glow fails the check", function()
        local err = load_check(wrapped(function(dd) dd.style.arrow_glow.texture_size = { 31, 15 } end))()
        H.truthy(err and err:find("31x28", 1, true), tostring(err))
    end)

    H.test("GUT #92 a glow that no longer shifts on open fails the check", function()
        local err = load_check(wrapped(function(dd)
            for _, p in ipairs(dd.element.passes) do
                if p.pass_type == "local_offset" then p.offset_function = function() end end
            end
        end))()
        H.truthy(err and err:find("glow y", 1, true), tostring(err))
    end)

    H.test("GUT #92 the 0.2.354-dev content key read is gone from the check", function()
        local contracts = read(base .. "_gut_mod_tweaker_contracts.lua")
        H.truthy(not contracts:find("dd.content.arrow_glow\n", 1, true)
            and not contracts:find("dd.content and dd.content.arrow_glow\n", 1, true),
            "the check must resolve the sprite through the pass texture_id")
    end)
end
