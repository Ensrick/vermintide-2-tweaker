-- Issue #411: dead Anim Picker source events (bastard sword swap_charge_stance).
--
-- The picker applies a pick by matching sub.anim_event == source_event across
-- Weapons.<template>.actions.*.* and writing sub.anim_event_3p; a source event
-- with no matching top-level sub-action is a silent no-op dropdown (the logged
-- "n=0 sites={}" class). swap_charge_stance exists on bastard_sword_template
-- ONLY inside custom_start_anim_data / custom_finish_anim_data
-- (bastard_swords.lua:90/96), which ActionBase._play_additional_animation
-- (action_base.lua:133-145) fires directly on the 3P body; that path has no
-- anim_event_3p companion, so the picker can never reach it. The fix removed
-- the entry; these tests pin the whole catalogue offline against the authored
-- write-site universe so the class cannot silently return on any weapon.
--
-- This gate is deliberately qa-layer ONLY: the shipped picker file is loaded
-- and parsed READ-ONLY here (no shipped-mod change, no version bump, no
-- parity/atomicity impact). The static catalogue tables are extracted from the
-- picker source text, then cross-checked against the loaded module's own
-- M.source_events_for() surface so the extraction cannot drift from what the
-- shipped module actually advertises.
--
-- Fixture: qa/lua/tests/fixtures/wt_picker_template_anim_events.lua, generated
-- from the decompiled VT2 weapon templates (top-level sub-action anim_events
-- only). Runtime twin: wt_dev_anim_picker M.source_event_coverage() via
-- /verify_wt_anim_picker_sources and issue411_dev_picker_source_events_resolve_live.
return function(H, repo_root)
    local picker_path = repo_root
        .. "/weapon_tweaker_dev/scripts/mods/weapon_tweaker_dev/wt_dev_anim_picker.lua"
    local fixture = dofile(repo_root
        .. "/qa/lua/tests/fixtures/wt_picker_template_anim_events.lua")

    -- CWV clone templates are runtime clones of a vanilla donor; the donor's
    -- authored action vocabulary IS the clone's write-site universe.
    -- cwv_crowbill_pick_template clones Weapons.one_handed_crowbill
    -- (character_weapon_variants _cwv_crowbill_hammer_mode.lua
    -- SOURCE_TEMPLATE_KEY = "one_handed_crowbill").
    local CLONE_DONOR = {
        cwv_crowbill_pick_template = "one_handed_crowbill",
    }

    local file = assert(io.open(picker_path, "rb"))
    local source = file:read("*a")
    file:close()

    -- Extract `local <name> = { ... }` from the picker source as a real table
    -- without executing the module. The brace scan honours line comments and
    -- double-quoted strings (the picker's static tables use only double-quoted
    -- literals, no long brackets, no escapes).
    local function extract_table(name)
        local anchor = "local " .. name .. " = {"
        local start_at = source:find(anchor, 1, true)
        H.truthy(start_at, name .. " not found in picker source")
        local open_at = start_at + #anchor - 1
        local pos, depth, n = open_at, 0, #source
        while pos <= n do
            local c = source:sub(pos, pos)
            if c == '"' then
                local close = source:find('"', pos + 1, true)
                H.truthy(close, "unterminated string literal inside " .. name)
                pos = close
            elseif c == "-" and source:sub(pos + 1, pos + 1) == "-" then
                pos = (source:find("\n", pos, true) or n + 1) - 1
            elseif c == "{" then
                depth = depth + 1
            elseif c == "}" then
                depth = depth - 1
                if depth == 0 then
                    local literal = source:sub(open_at, pos)
                    local chunk = assert(loadstring("return " .. literal,
                        "@picker:" .. name))
                    return chunk()
                end
            end
            pos = pos + 1
        end
        error("unbalanced braces extracting " .. name)
    end

    -- receiver -> { attacks = weapon_key -> {events}, templates = weapon_key -> template }.
    -- Mirrors the picker's _RECV dispatch table (kruber / saltzpyre / kerillian).
    local catalog = {
        kruber = {
            attacks = extract_table("_WEAPON_ATTACKS"),
            templates = extract_table("_WEAPON_TEMPLATE"),
        },
        saltzpyre = {
            attacks = extract_table("_SALTZ_WEAPON_ATTACKS"),
            templates = extract_table("_SALTZ_WEAPON_TEMPLATE"),
        },
        kerillian = {
            attacks = extract_table("_KERI_WEAPON_ATTACKS"),
            templates = extract_table("_KERI_WEAPON_TEMPLATE"),
        },
    }

    -- Load the shipped module READ-ONLY under a get_mod stub so the textual
    -- extraction can be cross-checked against its public surface.
    local prior_get_mod = _G.get_mod
    _G.get_mod = function()
        return {
            dofile = function(_, path)
                return dofile(repo_root .. "/weapon_tweaker_dev/" .. path .. ".lua")
            end,
            debug = function() end,
            warning = function() end,
            info = function() end,
            get = function() return nil end,
        }
    end
    local ok, picker = pcall(dofile, picker_path)
    _G.get_mod = prior_get_mod
    if not ok then error(picker) end

    H.test("WT #411 extracted catalogue matches the shipped module surface", function()
        for receiver, tables in pairs(catalog) do
            for weapon_key, events in pairs(tables.attacks) do
                local advertised = picker.source_events_for(receiver, weapon_key)
                H.truthy(advertised, receiver .. "/" .. weapon_key
                    .. " missing from the loaded module's source-event surface")
                H.deep_equal(advertised, events, receiver .. "/" .. weapon_key
                    .. " extraction drifted from M.source_events_for")
            end
        end
        H.equal(picker.source_events_for("kruber", "no_such_weapon_key"), nil)
    end)

    H.test("WT #411 every picker source event resolves to an authored write site", function()
        local receivers = 0
        local events_checked = 0
        for receiver, tables in pairs(catalog) do
            receivers = receivers + 1
            for weapon_key, events in pairs(tables.attacks) do
                local label = receiver .. "/" .. weapon_key
                local template = tables.templates[weapon_key]
                H.truthy(template, label .. " has no source template")
                H.truthy(#events > 0, label .. " advertises zero source events")
                local universe_key = CLONE_DONOR[template] or template
                local universe = fixture[universe_key]
                H.truthy(universe, label .. " template " .. tostring(template)
                    .. " missing from fixture; regenerate wt_picker_template_anim_events.lua")
                local seen = {}
                for _, event in ipairs(events) do
                    H.truthy(not seen[event],
                        label .. " duplicate source event " .. tostring(event))
                    seen[event] = true
                    H.truthy(universe and universe[event],
                        label .. " source event '" .. tostring(event)
                        .. "' resolves to ZERO write sites on " .. tostring(template)
                        .. " (the #411 dead-dropdown class)")
                    events_checked = events_checked + 1
                end
            end
        end
        H.equal(receivers, 3)
        H.truthy(events_checked >= 100,
            "catalogue suspiciously small: " .. events_checked .. " events")
    end)

    H.test("WT #411 bastard sword swap_charge_stance stays out of the picker", function()
        local sword = fixture.bastard_sword_template
        H.truthy(sword, "bastard_sword_template missing from fixture")
        H.truthy(sword.attack_swing_down, "fixture bastard sword block is empty or misgenerated")
        H.equal(sword.swap_charge_stance, nil)
        for receiver, tables in pairs(catalog) do
            for weapon_key, events in pairs(tables.attacks) do
                H.truthy(weapon_key ~= "es_bastard_sword",
                    receiver .. " re-grew the baked es_bastard_sword picker entry (#519 bake)")
                for _, event in ipairs(events) do
                    H.truthy(event ~= "swap_charge_stance",
                        receiver .. "/" .. weapon_key
                        .. " advertises swap_charge_stance again (#411)")
                end
            end
        end
    end)
end
