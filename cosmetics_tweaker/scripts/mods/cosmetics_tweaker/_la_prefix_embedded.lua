-- ============================================================
-- LA Prefix Patch — embedded into cosmetics_tweaker (v0.9.3.1+)
-- ============================================================
-- Source archived at:
--   C:/Users/danjo/source/repos/misc-vermintide-mods/la_prefix_patch_archive/
-- Standalone Workshop mod (3721067411) keeps existing for back-compat. This
-- embed only activates when the standalone isn't running, so users who still
-- have the standalone subscribed-and-enabled don't get double-wrapped.
--
-- Three behaviors this module brings into cosmetics_tweaker:
--   (1) VMFMod.hook/hook_safe/hook_origin wrapper that de-dupes LA's known
--       duplicate registrations (LevelEndView.start,
--       LevelTransitionHandler.load_current_level,
--       LocalizationManager._base_lookup). Must install BEFORE LA's
--       mod_script runs — hence loaded at the very top of cosmetics_tweaker
--       and the LA launcher load-order requirement (LA must be enabled
--       AFTER cosmetics_tweaker in the F4 launcher).
--   (2) `get_mod("Material-Hijack")` alias that redirects to
--       material_hijack_patched when the original MH is disabled. Lets LA
--       (or any other consumer) find a working MH instance regardless of
--       which fork is enabled.
--   (3) on_all_mods_loaded post-hooks on LA.render_marker (quest-marker
--       suppression toggle) and the LA_unread_letter NewsFeed template
--       (notification suppression toggle). Gated on VMF settings that
--       default off, so LA behaves as shipped until the user opts in.
--
-- Hot-reload safety: every wrap is idempotent — guarded by a flag on the
-- wrapped object or by checking whether get_mod returns the standalone.

local mod = get_mod("cosmetics_tweaker")
if not mod then return end

-- Standalone-running guard. If the user still has la_prefix_patch
-- subscribed AND enabled in the launcher, defer to its installation
-- entirely. Avoids double-wrapping VMFMod prototypes (which would chain
-- two dedup filters; harmless but wasteful) and double-installing the
-- get_mod alias (same).
if get_mod("la_prefix_patch") then
    mod:info("[la_prefix_embed] standalone la_prefix_patch is running; embedded copy stays dormant")
    return
end

mod:info("[la_prefix_embed] activating (standalone la_prefix_patch not detected)")

local LA_NAME = "Loremasters-Armoury"
local seen = {}

local function key_for(self, obj, method)
    return tostring(self) .. "|" .. tostring(obj) .. "::" .. tostring(method)
end

-- `is_normal_hook` is true only for the plain VMFMod.hook install site (where
-- the registered handler receives `func` as its first arg and is responsible
-- for calling the original). hook_safe / hook_origin pass false.
local function wrap(orig_method, is_normal_hook)
    if type(orig_method) ~= "function" then return orig_method end
    return function(self, obj, method, handler)
        if self.get_name and self:get_name() == LA_NAME then
            local k = key_for(self, obj, method)
            if seen[k] then
                return
            end
            seen[k] = true
            -- #137: LA's StatisticsUtil.register_kill hook (utils/hooks.lua)
            -- nil-derefs `attacker_player.player_unit` when the killer has LEFT
            -- the game — player_from_unique_id() returns nil for a departed
            -- peer whose lingering DoT (e.g. a globadier's poison) scores a
            -- kill — and crashes the HOST. cosmetics_tweaker is mandated to
            -- load BEFORE LA, so a normal mod:hook from us would be the INNER
            -- wrapper and never run before LA's crash. Instead we intercept
            -- LA's registration here (this wrap runs at LA's mod:hook call,
            -- prototype-level, before any handler fires) and pcall-guard its
            -- handler. On error we still call `func(...)` so vanilla
            -- register_kill stat tracking runs. Default-ON; only an explicit
            -- `false` on the setting disables (fail-safe).
            if is_normal_hook and method == "register_kill" and type(handler) == "function" then
                local la_handler = handler
                handler = function(func, ...)
                    if mod:get("la_killquest_crash_guard") == false then
                        return la_handler(func, ...)
                    end
                    local ok = pcall(la_handler, func, ...)
                    if not ok then
                        return func(...)
                    end
                end
            end
        end
        return orig_method(self, obj, method, handler)
    end
end

if rawget(_G, "VMFMod") and not _G.VMFMod._cos_la_prefix_wrapped then
    VMFMod.hook        = wrap(VMFMod.hook, true)
    VMFMod.hook_safe   = wrap(VMFMod.hook_safe, false)
    VMFMod.hook_origin = wrap(VMFMod.hook_origin, false)
    _G.VMFMod._cos_la_prefix_wrapped = true
    mod:info("[la_prefix_embed] VMFMod hook methods wrapped; LA duplicate registrations will be silently ignored.")
else
    if not rawget(_G, "VMFMod") then
        mod:warning("[la_prefix_embed] VMFMod prototype not found; LA dupe filter NOT installed.")
    end
end

-- get_mod("Material-Hijack") alias. Resolution order:
--   1. Original Material-Hijack (Workshop 2771980886) if enabled — preserves
--      vanilla behavior when user explicitly chose the original.
--   2. Standalone Material-Hijack (patched) (Workshop 3727311798) if enabled.
--   3. v0.9.3.3+: the mod that owns the embedded MH-patched copy (set via
--      `_G._cos_mh_embed_owner`). Returns the embedded mod's handle so any
--      downstream consumer that looks up Material-Hijack by mod_id sees
--      `texture_animations` and the same public surface.
--   4. Fall through to whatever original `get_mod` returns (typically nil).
do
    local _orig_get_mod = rawget(_G, "get_mod")
    if type(_orig_get_mod) == "function" and not _G._cos_la_prefix_get_mod_wrapped then
        _G.get_mod = function(name)
            if name == "Material-Hijack" then
                local original = _orig_get_mod("Material-Hijack")
                if original and type(original.is_enabled) == "function" and original:is_enabled() then
                    return original
                end
                local patched = _orig_get_mod("material_hijack_patched")
                if patched and (type(patched.is_enabled) ~= "function" or patched:is_enabled()) then
                    return patched
                end
                -- Embedded fallback (v0.9.3.3+).
                local embed_owner = _G._cos_mh_embed_owner
                if embed_owner then
                    local owner_mod = _orig_get_mod(embed_owner)
                    if owner_mod then return owner_mod end
                end
                return original
            end
            -- v0.9.3.6: MoreItemsLibrary alias. Resolution order:
            --   1. Standalone MoreItemsLibrary (Workshop 1422758813) if enabled.
            --   2. Mod that owns the embedded MIL (`_G._cos_mil_embed_owner`).
            --   3. Fall through to whatever standalone returns (typically nil).
            -- The embedded owner exposes the same public API surface on its
            -- own mod handle (add_mod_items_to_masterlist, etc.) so consumers
            -- like LA, CWV, our own _la_bridge see a working MIL regardless
            -- of whether the standalone is subscribed.
            if name == "MoreItemsLibrary" then
                local standalone = _orig_get_mod("MoreItemsLibrary")
                if standalone and (type(standalone.is_enabled) ~= "function" or standalone:is_enabled()) then
                    return standalone
                end
                local embed_owner = _G._cos_mil_embed_owner
                if embed_owner then
                    local owner_mod = _orig_get_mod(embed_owner)
                    if owner_mod then return owner_mod end
                end
                return standalone
            end
            return _orig_get_mod(name)
        end
        _G._cos_la_prefix_get_mod_wrapped = true
        mod:info("[la_prefix_embed] get_mod alias installed for Material-Hijack + MoreItemsLibrary; falls back to standalone then embedded owner.")
    end
end

-- VMF settings for the LA suppression toggles. Mirrors la_prefix_patch_data.
-- Lives in cosmetics_tweaker's settings tree under a new sub-group so users
-- find it alongside other LA-related options.
-- NOTE: actual widget registration happens in cosmetics_tweaker_data.lua;
-- this file only owns the runtime behavior gated on those settings.

mod.on_all_mods_loaded = mod.on_all_mods_loaded or function() end
local _prev_on_all_mods_loaded = mod.on_all_mods_loaded
mod.on_all_mods_loaded = function()
    if _prev_on_all_mods_loaded then
        local ok, err = pcall(_prev_on_all_mods_loaded)
        if not ok then mod:warning("[la_prefix_embed] prior on_all_mods_loaded errored: %s", tostring(err)) end
    end
    local LA = get_mod(LA_NAME)
    if not LA then return end
    if type(LA.render_marker) == "function" and not LA._la_prefix_patch_marker_wrapped then
        local orig_render = LA.render_marker
        LA.render_marker = function(...)
            if mod:get("suppress_la_quest_markers") then return end
            return orig_render(...)
        end
        LA._la_prefix_patch_marker_wrapped = true
        mod:info("[la_prefix_embed] wrapped LA.render_marker for quest-marker suppression toggle.")
    end
end

-- NewsFeedUI.init hook for LA_unread_letter suppression. Same pattern as
-- standalone but registered via cosmetics_tweaker's `mod:hook` (so it routes
-- through cosmetics_tweaker's hook table, not la_prefix_patch's).
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
                -- v0.9.49-dev (#186): the LA Okri's-Challenges disable toggle
                -- also silences LA's unread-quest-letter banner — it's the
                -- "notification" that goes with the quest line. Reuses this
                -- existing wrapper (NO second NewsFeedUI.init hook — VMF drops
                -- duplicate Class.method registrations).
                if mod:get("suppress_la_notifications") or mod:get("la_disable_okri_challenges") then return false end
                if orig_cond then return orig_cond(params) end
                return false
            end
            tmpl._la_prefix_patch_notif_wrapped = true
            mod:info("[la_prefix_embed] wrapped LA_unread_letter condition_func for notification suppression toggle.")
        end
    end
    return result
end)
