local mod = get_mod("gut")

-- ============================================================================
-- Loremaster's Armoury atlas keep-alive  (crash efadf778 guard)
-- ============================================================================
-- LA registers materials/Loremasters-Armoury/armoury_atlas for VMF custom-texture
-- injection into the "hero_view" renderer-CREATOR (LA data.lua custom_gui_textures
-- .ui_renderer_injections). The hero view's HDR sub-renderer ("hero_view_hdr") shares
-- that creator, so VMF injects the atlas into it too — at hero_view.on_enter ->
-- _setup_hdr_gui -> _setup_hdr_renderer -> create_ui_renderer.
--
-- LA ALSO dynamically UNLOADS its own package (it hooks PackageManager.unload,
-- LA utils/hooks.lua:280), so the atlas material is sometimes GONE when that early
-- HDR renderer is built. VMF then hands a missing material to create_screen_gui,
-- which takes a C-level fatal (NOT catchable by pcall — that's why cim's pcall around
-- _setup_hdr_gui doesn't help). Symptom: intermittent "[Script Error]:
-- materials/Loremasters-Armoury/armoury_atlas" when opening the hero menu.
--
-- Fix from our side (we have LA's authors' permission, but ship it in our mod): pin
-- LA's package under OUR OWN package-manager reference so LA's unload only drops LA's
-- reference — ours keeps the atlas resident, so it's always available when the HDR
-- renderer injects it. No-op if LA isn't installed.

local LA_PACKAGE = "resource_packages/Loremasters-Armoury/Loremasters-Armoury"
local GUT_REF    = "gut_la_atlas_keepalive"
local _pinned    = false
-- De-spam latch: _pin_la_package is called from FOUR sites (StateInGameRunning
-- .on_enter + the three Mod Tweaker open re-pins in gui_tweaker.lua /
-- _mod_tweaker_view.lua / _mod_tweaker_state.lua), so a user with LA installed +
-- debug logging on but LA's package not resident at pin time would otherwise get
-- the "skipping pin" line on EVERY keep entry and EVERY menu open, forever. The
-- residency CAN legitimately change (LA loads/unloads its own package), so we
-- can't suppress permanently — instead we log the not-resident state only on the
-- TRANSITION into it (edge-triggered), and clear the latch whenever the package
-- becomes resident again, so a genuine later unload still surfaces exactly once.
local _logged_not_resident = false

local function _pin_la_package()
    if _pinned then return end
    if not get_mod("Loremasters-Armoury") then return end  -- LA not installed -> nothing to guard
    local pm = Managers and Managers.package
    if not (pm and pm.load and pm.has_loaded) then return end  -- package manager not up yet; retry next entry
    -- CRASH FIX (GUID ca939793 / efadf778 — `Resource '#ID[3ac73385950a26ea]' not
    -- found`, recurs every keep entry while LA is installed). 3ac73385950a26ea IS this
    -- LA package (Stingray names bundles by murmur64A of the package path). The 4th
    -- load() arg is `asynchronous`, NOT "persistent" — our reference is held by GUT_REF
    -- regardless of it. Calling load() while the package is NOT resident makes the
    -- package manager QUEUE a fresh load that force-MATERIALIZES every member of LA's
    -- bundle; LA's installed bundle is missing an internal member, so the async
    -- _pop_queue -> resource_package step takes a C-level fatal (fires outside this
    -- frame, so the pcall below CANNOT catch it). LA unloads its own package
    -- (LA utils/hooks.lua:280), so at our on_enter it is OFTEN not resident — exactly
    -- the fresh-load path that crashed. So: ONLY pin when LA's package is ALREADY fully
    -- resident — then load() is a pure reference-count increment (no re-materialize),
    -- which is all we need to keep the atlas alive across LA's own unload. If it is not
    -- resident, do NOT trigger the load; bail and retry next entry (worst case we miss
    -- the pin and the original intermittent HDR-renderer guard applies — far better
    -- than a hard CTD on every keep entry).
    if not pm:has_loaded(LA_PACKAGE) then
        -- Edge-triggered: log ONLY on the false-edge (first call that sees it
        -- not resident since it was last resident), not on every menu open.
        if not _logged_not_resident then
            _logged_not_resident = true
            mod:debug("[gut] LA atlas package not resident at pin time; skipping pin (force-materialize crash guard). Will retry silently each entry until it's resident.")
        end
        return
    end
    -- Package IS resident now -> clear the latch so a genuine later unload surfaces
    -- once more, then pin via a pure ref-count bump (NEVER force-loads).
    _logged_not_resident = false
    local ok, err = pcall(pm.load, pm, LA_PACKAGE, GUT_REF, nil, true)
    if ok then
        _pinned = true
        mod:info("[gut] pinned Loremaster's Armoury atlas package (hero-view HDR-renderer crash guard)")
    else
        mod:warning("[gut] could not pin LA atlas package: %s", tostring(err))
    end
end

-- INSTRUMENT (v0.2.56): the Mod Tweaker BORROWS the long-lived IngameUI renderer
-- and re-pinning happens on every open. This exported probe logs the atlas
-- residency + our _pinned state at the moment of a pin attempt; logging routes
-- through mod:debug (VMF debug channel). Called by the re-pin sites in
-- gui_tweaker.lua / _mod_tweaker_view.lua right before pin().
local function _residency_snapshot(tag)
    local pm = Managers and Managers.package
    local resident = "?"
    if pm and pm.has_loaded then
        local ok, r = pcall(pm.has_loaded, pm, LA_PACKAGE)
        resident = ok and tostring(r) or ("err:" .. tostring(r))
    end
    mod:debug("[gut:la] residency probe (%s): has_loaded=%s gut_pinned=%s",
        tostring(tag), resident, tostring(_pinned))
end

local function _is_pinned() return _pinned end

-- gut hooks StateInGameRunning.update elsewhere (_ba_heroview_inject); .on_enter is
-- free, so no duplicate-hook collision. on_enter fires entering the keep/level —
-- before the player can open the hero view — so the pin lands first.
mod:hook_safe("StateInGameRunning", "on_enter", function()
    _pin_la_package()
end)

-- INSTRUMENT (v0.2.56, read-only): log-and-passthrough on PackageManager.unload,
-- filtered to LA's atlas package, to catch if anything unloads the atlas BETWEEN
-- Mod Tweaker opens (the suspected in-mission 3rd/4th-open crash cause). hook_safe
-- = pure observation, no behaviour change. gut hooks PackageManager.unload NOWHERE
-- ELSE (verified via grep before adding) — no duplicate-hook collision. Logging
-- routes through mod:debug (VMF debug channel).
mod:hook_safe("PackageManager", "unload", function(self, package_name, reference_name)
    if package_name == LA_PACKAGE then
        mod:debug("[gut:la] PackageManager.unload(%s, ref=%s) — LA atlas package being unloaded (gut_pinned=%s)",
            tostring(package_name), tostring(reference_name), tostring(_pinned))
    end
end)

return { pin = _pin_la_package, residency_snapshot = _residency_snapshot, is_pinned = _is_pinned }
