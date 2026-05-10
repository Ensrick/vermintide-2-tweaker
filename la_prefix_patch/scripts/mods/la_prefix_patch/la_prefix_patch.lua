local mod = get_mod("la_prefix_patch")

local MOD_VERSION = "0.3.0-dev"
mod:info("LA Prefix Patch v%s loaded", MOD_VERSION)
mod:echo("LA Prefix Patch v" .. MOD_VERSION)

-- VMF runs each mod's script inside its own new_mod() call, so when our script
-- runs LA hasn't been created yet (get_mod("Loremasters-Armoury") returns nil
-- here). We can't reach LA's instance directly. Instead we patch VMFMod's
-- prototype hook methods so that any future call from a mod whose name is
-- "Loremasters-Armoury" runs through a dupe filter; all other mods pass
-- through unchanged. Our launcher load order guarantees this patch is
-- installed before LA's mod_script runs.
--
-- LA's utils/hooks.lua registers three duplicates: LevelEndView.start,
-- LevelTransitionHandler.load_current_level, LocalizationManager._base_lookup.
-- VMF rejects the second call AND emits a warning to chat. We drop the
-- second call before VMF sees it; first registration always wins (which is
-- the correct semantics — the first _base_lookup body carries the cosmetic
-- skin-name swap, the second is a strict subset that would clobber it).

local LA_NAME = "Loremasters-Armoury"
local seen = {}

local function key_for(self, obj, method)
    return tostring(self) .. "|" .. tostring(obj) .. "::" .. tostring(method)
end

local function wrap(orig_method)
    if type(orig_method) ~= "function" then return orig_method end
    return function(self, obj, method, handler)
        if self.get_name and self:get_name() == LA_NAME then
            local k = key_for(self, obj, method)
            if seen[k] then
                return
            end
            seen[k] = true
        end
        return orig_method(self, obj, method, handler)
    end
end

if rawget(_G, "VMFMod") then
    VMFMod.hook        = wrap(VMFMod.hook)
    VMFMod.hook_safe   = wrap(VMFMod.hook_safe)
    VMFMod.hook_origin = wrap(VMFMod.hook_origin)
    mod:info("VMFMod hook methods wrapped; LA duplicate registrations will be silently ignored.")
else
    mod:warning("VMFMod prototype not found; LA dupe filter NOT installed.")
end

-- Quiet-mode toggles: gate LA's quest markers and unread-letter notifications
-- on VMF settings so the user can disable the loremaster overlay without
-- removing LA. Both toggles default to false (LA behaves as shipped).
--
-- Markers: every LA waypoint draw — board, scrolls, pickups, sword shrine —
-- funnels through `LA.render_marker`. We monkey-patch it in
-- on_all_mods_loaded (the earliest point at which get_mod returns LA's
-- instance) and gate on the toggle inside the closure, so flipping the
-- setting takes effect on the next frame without re-patching.
--
-- Notifications: LA's `NewsFeedUI.init` hook injects an `LA_unread_letter`
-- entry into `NewsFeedTemplates` with a `condition_func` that returns true
-- whenever a quest letter is unread. Since la_prefix_patch loads first, our
-- hook is innermost in the chain — when our wrapper runs, LA has already
-- registered the template (LA does its insert *before* calling func). We
-- post-wrap `condition_func` to short-circuit when the toggle is on.
mod.on_all_mods_loaded = function()
    local LA = get_mod("Loremasters-Armoury")
    if not LA then
        return
    end
    if type(LA.render_marker) == "function" and not LA._la_prefix_patch_marker_wrapped then
        local orig_render = LA.render_marker
        LA.render_marker = function(...)
            if mod:get("suppress_la_quest_markers") then
                return
            end
            return orig_render(...)
        end
        LA._la_prefix_patch_marker_wrapped = true
        mod:info("Wrapped LA.render_marker for quest-marker suppression toggle.")
    end
end

mod:hook("NewsFeedUI", "init", function(func, self, parent, ingame_ui_context)
    local result = func(self, parent, ingame_ui_context)
    local find_idx = rawget(_G, "FindNewsTemplateIndex")
    local templates = rawget(_G, "NewsFeedTemplates")
    if find_idx and templates then
        local idx = find_idx("LA_unread_letter")
        local tmpl = idx and templates[idx]
        if tmpl and not tmpl._la_prefix_patch_notif_wrapped then
            local orig_cond = tmpl.condition_func
            tmpl.condition_func = function(params)
                if mod:get("suppress_la_notifications") then
                    return false
                end
                if orig_cond then
                    return orig_cond(params)
                end
                return false
            end
            tmpl._la_prefix_patch_notif_wrapped = true
            mod:info("Wrapped LA_unread_letter condition_func for notification suppression toggle.")
        end
    end
    return result
end)
