-- _crt_buff_icons.lua - atlas-presence guard for every icon crt hands to the
-- vanilla UI (#1686).
--
-- Crash class: docs/BUG_CLASSES.md section 23 (atlas name removed by a patch).
-- BuffUI reads the live sub-buff template's `icon` (buff_ui.lua:128) and makes
-- a HUD widget for any non-nil value (buff_ui.lua:135-136, texture_icon at
-- :252). UIRenderer.script_draw_bitmap takes the UV branch only when
-- UIAtlasHelper.has_atlas_settings_by_texture_name is true (ui_renderer.lua:74);
-- any other name reaches the raw Gui_bitmap call (ui_renderer.lua:117), the
-- "Material 'X' not found in Gui" fatal. Game Version 6.13.0 (93dea911) removed
-- two 6.12.1 atlas keys crt used: kerillian_maidenguard_cooldown_on_nearby_allies
-- (6.12.1 gui_icons_atlas.lua:14508) and
-- sienna_unchained_activated_ability_power_on_enemies_hit (6.12.1
-- gui_icons_atlas.lua:7830).
--
-- Atlas names are proven with the renderer's own predicate,
-- UIAtlasHelper.has_atlas_settings_by_texture_name
-- (scripts/helpers/ui_atlas_helper.lua:605), a boot global (boot.lua:1318).
-- A buff icon that fails the check is DROPPED: a nil icon is vanilla's own
-- "no HUD widget" case (buff_ui.lua:135), so the buff still works and only its
-- HUD slot disappears. A talent icon that fails keeps the vanilla talent's own
-- icon instead. An unusable helper fails closed the same way.
--
-- Pure module: no hooks, no engine reads beyond the injected helper. Owned by
-- career_tweaker.lua (mod._crt.buff_icons), which also sweeps every
-- crt-registered template at balance load and after each balance.apply pass;
-- consumed by the Foot Knight and Engineer registrations, /crt_regression_test
-- and qa/lua/tests/test_crt_buff_icons.lua.

local M = {}

-- 6.13.0 atlas names (93dea911) for icons whose template lives outside a pure
-- factory. The Dance of Blades icon is owned by _crt_dance_of_blades.lua and
-- audited through its factory templates; Foot Knight's by _crt_foot_knight.lua.
M.UNCHAINED_ULT_ICON = "unchained_6_1"                 -- talent_settings_sienna.lua:1003/2056, gui_icons_atlas.lua:7746
M.LEADING_SHOTS_ICON = "bardin_engineer_ranged_crit_count" -- gui_icons_atlas.lua:15138 (no vanilla talent uses it)

-- true / false from the engine predicate, nil when the helper is unusable.
function M.in_atlas(atlas_helper, name)
    if type(name) ~= "string" or name == "" then return false end
    if type(atlas_helper) ~= "table"
        or type(atlas_helper.has_atlas_settings_by_texture_name) ~= "function" then
        return nil
    end
    local ok, present = pcall(atlas_helper.has_atlas_settings_by_texture_name, name)
    if not ok then return nil end
    return present == true
end

-- Drops every sub-buff icon of one template that the atlas cannot prove.
-- Returns a list of { name, index, from, reason } rewrites (empty = untouched).
function M.guard_template(atlas_helper, name, template)
    local rewrites = {}
    local buffs = type(template) == "table" and rawget(template, "buffs")
    if type(buffs) ~= "table" then return rewrites end
    for index, sub_buff in ipairs(buffs) do
        local icon = type(sub_buff) == "table" and rawget(sub_buff, "icon")
        if icon ~= nil and icon ~= false then
            local present = M.in_atlas(atlas_helper, icon)
            if present ~= true then
                sub_buff.icon = nil
                rewrites[#rewrites + 1] = {
                    name = tostring(name), index = index, from = tostring(icon),
                    reason = present == nil and "atlas_unavailable" or "not_in_atlas",
                }
            end
        end
    end
    return rewrites
end

-- Iterates a name list ({ "a", "b" }) or a name set ({ a = true }).
local function each_name(names, visit)
    if type(names) ~= "table" then return end
    for key, value in pairs(names) do
        if type(key) == "string" then
            visit(key)
        elseif type(value) == "string" then
            visit(value)
        end
    end
end

-- Guards every live template named in `names`; returns the combined rewrites
-- and how many named templates were live tables (the sweep's coverage).
function M.guard_names(atlas_helper, buff_templates, names)
    local rewrites, checked = {}, 0
    if type(buff_templates) ~= "table" then return rewrites, checked end
    each_name(names, function(name)
        local template = rawget(buff_templates, name)
        if type(template) == "table" then checked = checked + 1 end
        for _, row in ipairs(M.guard_template(atlas_helper, name, template)) do
            rewrites[#rewrites + 1] = row
        end
    end)
    return rewrites, checked
end

-- Talent icon to install: the preferred name when the atlas proves it, else
-- the vanilla talent's own icon (which vanilla itself draws).
function M.talent_icon(atlas_helper, preferred, vanilla_icon)
    if M.in_atlas(atlas_helper, preferred) == true then return preferred end
    return vanilla_icon
end

-- Module-local log ledger: each distinct drop prints once, and each sweep site
-- prints one positive summary the first time it runs, so the log stays bounded
-- across repeated balance.apply passes and proves the sweep ran.
local _logged_drops = {}
local _summarized_sites = {}

-- Engine printf lines for rewrites. `checked` (a sweep's template count) adds
-- the per-site summary; `log` is a test seam. Read-only use of the global (mod
-- logging is off for the author, CLAUDE.md rule 9); never assigned here.
function M.log_rewrites(site, rewrites, checked, log)
    log = log or rawget(_G, "printf")
    if type(log) ~= "function" or type(rewrites) ~= "table" then return end
    for _, row in ipairs(rewrites) do
        local key = tostring(row.name) .. "#" .. tostring(row.index) .. "#" .. tostring(row.from)
        if not _logged_drops[key] then
            _logged_drops[key] = true
            pcall(log, "[crt:1686] %s buff %s sub-buff %d icon %s dropped (%s)",
                tostring(site), tostring(row.name), tonumber(row.index) or 0,
                tostring(row.from), tostring(row.reason))
        end
    end
    if checked ~= nil and not _summarized_sites[tostring(site)] then
        _summarized_sites[tostring(site)] = true
        pcall(log, "[crt:1686] buff icon atlas guard (%s): templates=%d dropped=%d",
            tostring(site), tonumber(checked) or 0, #rewrites)
    end
end

-- Registration-site wrapper: guard one template, log, return it.
function M.guard_and_log(atlas_helper, site, name, template)
    M.log_rewrites(site, M.guard_template(atlas_helper, name, template))
    return template
end

-- Audit entries for every icon crt hands to the UI: the preferred constants
-- (fail on drift even while a rework is off), the Dance of Blades factory, the
-- Foot Knight icon catalog, and every live registered template.
function M.icon_entries(sources)
    sources = type(sources) == "table" and sources or {}
    local entries = {
        { label = "Unchained career-skill max US", icon = M.UNCHAINED_ULT_ICON },
        { label = "Leading Shots", icon = M.LEADING_SHOTS_ICON },
    }
    local function add_template(label, template)
        local buffs = type(template) == "table" and rawget(template, "buffs")
        for index, sub_buff in ipairs(type(buffs) == "table" and buffs or {}) do
            local icon = type(sub_buff) == "table" and rawget(sub_buff, "icon")
            if icon ~= nil then
                entries[#entries + 1] = { label = label .. "[" .. index .. "]", icon = icon }
            end
        end
    end
    for name, template in pairs(type(sources.factory_templates) == "table"
        and sources.factory_templates or {}) do
        add_template("factory " .. tostring(name), template)
    end
    for name, icon in pairs(type(sources.foot_knight_icons) == "table"
        and sources.foot_knight_icons or {}) do
        entries[#entries + 1] = { label = "Foot Knight " .. tostring(name), icon = icon }
    end
    local live = sources.buff_templates
    if type(live) == "table" then
        each_name(sources.names, function(name)
            add_template("live " .. name, rawget(live, name))
        end)
    end
    return entries
end

-- In-game audit: nil when every entry resolves in the atlas, else the first
-- failure. An empty entry list fails so the check cannot pass vacuously.
function M.audit(atlas_helper, entries)
    if type(entries) ~= "table" or #entries == 0 then
        return "no crt icon entries to audit"
    end
    for _, entry in ipairs(entries) do
        local present = M.in_atlas(atlas_helper, entry.icon)
        if present == nil then
            return "UIAtlasHelper.has_atlas_settings_by_texture_name unavailable"
        end
        if not present then
            return string.format("%s icon %s is not in the UI atlas (Gui_bitmap fatal)",
                tostring(entry.label), tostring(entry.icon))
        end
    end
    return nil
end

return M
