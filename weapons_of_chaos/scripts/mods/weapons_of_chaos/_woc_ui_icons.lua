-- Atlas-presence guard for every atlas icon WOC hands to the vanilla UI (#1687).
--
-- Crash class: docs/BUG_CLASSES.md section 23. The tooltip trait pass draws
-- `trait_data.icon` (ui_passes_tooltips.lua:1282/1290) through
-- UIPasses.texture.draw (ui_passes.lua:141) into UIRenderer.script_draw_bitmap
-- (ui_renderer.lua:74). A name missing from the atlas skips the UV branch and
-- reaches the raw `Gui_bitmap` call (ui_renderer.lua:117), which is the
-- "Material 'X' not found in Gui" fatal. VT2 6.13.0 removed the 6.12.1 atlas
-- key `kerillian_shade_increased_damage_on_poisoned_or_bleeding_enemy`
-- (6.12.1 gui_icons_atlas.lua:14648), so a patch can turn a valid icon fatal.
--
-- Atlas names are proven with the engine's own lookup:
-- UIAtlasHelper.has_atlas_settings_by_texture_name (ui_atlas_helper.lua:605),
-- the same predicate the renderer branches on. UIAtlasHelper is a boot global
-- (boot.lua:1318). The fallback is vanilla's own tooltip default icon
-- (ui_passes_tooltips.lua:1134, gui_icons_atlas.lua:5674 at 6.13.0).
--
-- Custom WOC materials (icon_wpn_blightreaper, icon_bg_cursed) are not atlas
-- entries. Their safety is the renderer-injection contract in
-- _woc_inventory_icons.lua and weapons_of_chaos_data.lua, not this guard.

local M = {}

M.FALLBACK_ICON = "icons_placeholder"
M.CUSTOM_MATERIAL_ICONS = {
	icon_wpn_blightreaper = true,
	icon_bg_cursed = true,
}

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

-- Returns a name that is safe to hand to Gui drawing, and why. An unusable
-- helper fails closed to vanilla's own default instead of trusting the name.
function M.resolve(atlas_helper, preferred, fallback)
	fallback = fallback or M.FALLBACK_ICON
	local present = M.in_atlas(atlas_helper, preferred)
	if present == nil then return M.FALLBACK_ICON, "atlas_unavailable" end
	if present then return preferred, "present" end
	if M.in_atlas(atlas_helper, fallback) then return fallback, "fallback" end
	return M.FALLBACK_ICON, "fallback_unverified"
end

-- Rewrites `rows[key][field]` in place for every row whose icon is absent from
-- the atlas. Returns a list of { key, from, to, reason } for each rewrite.
function M.guard_rows(atlas_helper, rows, keys, field, fallback)
	local replaced = {}
	if type(rows) ~= "table" or type(keys) ~= "table" then return replaced end
	field = field or "icon"
	for _, key in ipairs(keys) do
		local row = rawget(rows, key)
		if type(row) == "table" then
			local current = row[field]
			local safe, reason = M.resolve(atlas_helper, current, fallback)
			if safe ~= current then
				row[field] = safe
				replaced[#replaced + 1] = {
					key = key, from = tostring(current), to = safe, reason = reason,
				}
			end
		end
	end
	return replaced
end

-- Default `report`: one engine printf line per rewrite (read-only use of the
-- global; mod logging is off for the author, CLAUDE.md rule 9).
function M.log_rewrite(row)
	local log = rawget(_G, "printf")
	if type(log) ~= "function" or type(row) ~= "table" then return end
	pcall(log, "[WOC:1687] %s icon %s not in UI atlas (%s); using %s",
		tostring(row.key), tostring(row.from), tostring(row.reason), tostring(row.to))
end

-- The only sanctioned trait-row install path: installs the moveset's intrinsic
-- rows, then re-proves every intrinsic row icon (a row an earlier install kept
-- is guarded too). `report(row)` is called once per rewrite.
function M.install_trait_rows(moveset, weapon_traits, buff_templates, atlas_helper, report)
	local ok, reason = moveset.install_intrinsic_trait_rows(weapon_traits, buff_templates)
	if not ok then return ok, reason, {} end
	local replaced = M.guard_rows(atlas_helper, weapon_traits.traits,
		moveset.intrinsic_traits(), "icon")
	if type(report) == "function" then
		for _, row in ipairs(replaced) do pcall(report, row) end
	end
	return true, reason, replaced
end

-- Install-site wrapper: logs each rewrite plus one bounded summary per site.
local _summarized = {}
function M.install_and_log(moveset, weapon_traits, buff_templates, atlas_helper, site)
	local ok, reason, replaced = M.install_trait_rows(moveset, weapon_traits,
		buff_templates, atlas_helper, M.log_rewrite)
	local log = rawget(_G, "printf")
	if not _summarized[site] and type(log) == "function" then
		_summarized[site] = true
		pcall(log, "[WOC:1687] trait icon atlas guard (%s): rows=%s rewrites=%d",
			tostring(site), tostring(reason), #replaced)
	end
	return ok, reason, replaced
end

-- Every atlas icon WOC hands to the UI, as audit entries: both intrinsic trait
-- rows and, once the Blightreaper row exists, its Athanor fallback item icon.
function M.woc_icon_rows(traits, moveset, masters, item_key, base_weapon)
	local rows = {}
	local poison = type(traits) == "table" and rawget(traits, moveset.POISON_TRAIT)
	local curse = type(traits) == "table" and rawget(traits, moveset.SHYISH_CURSE_TRAIT)
	if poison then
		rows[#rows + 1] = { label = "Poisoned Edge", icon = poison.icon,
			preferred = moveset.POISON_TRAIT_ICON }
	end
	if curse then
		rows[#rows + 1] = { label = "Shyish curse", icon = curse.icon,
			preferred = moveset.SHYISH_CURSE_ICON }
	end
	local entry = type(masters) == "table" and rawget(masters, item_key)
	if type(entry) == "table" and entry.cim_inventory_icon_fallback ~= nil then
		local base = rawget(masters, base_weapon)
		rows[#rows + 1] = { label = "Blightreaper Athanor fallback",
			icon = entry.cim_inventory_icon_fallback,
			preferred = type(base) == "table" and base.inventory_icon or nil }
	end
	return rows
end

-- In-game audit. `entries` is a list of { label, icon, preferred }. Returns nil
-- when every live icon resolves and matches its preferred constant, else the
-- first failure. A live icon outside the atlas is the crash; a preferred
-- constant outside the atlas is drift that the guard is masking.
function M.audit(atlas_helper, entries)
	if M.in_atlas(atlas_helper, M.FALLBACK_ICON) == nil then
		return "UIAtlasHelper.has_atlas_settings_by_texture_name unavailable"
	end
	for _, entry in ipairs(entries or {}) do
		if not M.in_atlas(atlas_helper, entry.icon) then
			return string.format("%s icon %s is not in the UI atlas (Gui_bitmap fatal)",
				tostring(entry.label), tostring(entry.icon))
		end
		if entry.preferred ~= nil and not M.in_atlas(atlas_helper, entry.preferred) then
			return string.format("%s preferred icon %s left the UI atlas; fallback %s in use",
				tostring(entry.label), tostring(entry.preferred), tostring(entry.icon))
		end
	end
	return nil
end

return M
