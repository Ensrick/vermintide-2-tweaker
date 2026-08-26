local mod = get_mod("gut")

-- _gut_ui_tweaks_integration.lua - UI Tweaks bridge bootstrap and contracts.
--
-- Owns the absorbed HideBuffs boot guards, stock UI Tweaks synchronization,
-- temporal-fix bootstrap, and their runtime regression registrations. The main
-- entry installs it once and retains only the returned lifecycle adapters; this
-- module registers no lifecycle callback or engine hook of its own.
--
-- Owned by: gui_tweaker.lua. Consumed via: mod:dofile + install.

local M = {}

function M.install(api)
    local _rt_register = assert(api.register, "UI Tweaks integration requires register")
    local _rt_src_read = assert(api.src_read, "UI Tweaks integration requires src_read")
-- hb/ SETTING_NAMES-nil crash (2026-06-24): the BOOT loading screen fires the
-- hb/level_loading_screen.lua LoadingView.create_ui_elements hook before
-- hb_data.lua has populated mod.SETTING_NAMES, so reading
-- mod.SETTING_NAMES.HIDE_LOADING_SCREEN_SUBTITLES indexed a nil value and crashed
-- ("attempt to index field 'SETTING_NAMES' (a nil value)"). The hook now bails with
-- `if not mod.hb_fork_active() then return func(...) end` (#281) -- hb_fork_active()
-- returns false whenever mod.SETTING_NAMES is nil, so it STILL protects the boot
-- crash while also making the fork dormant when stock UI Tweaks owns. This check
-- FAILS if that guard is removed (the crash would return). Source path is derived
-- from a sibling hb/ function (mod.reapply_pickup_ranges, defined in
-- hide_elements.lua) by swapping the filename, since the level_loading_screen
-- hooks are anonymous closures with no addressable reference. Needles are split
-- so this comment/line can't self-match. No-op when source unreadable.
_rt_register("hb_setting_names_guarded", function()
    local ok, info = pcall(debug.getinfo, mod.reapply_pickup_ranges or function() end, "S")
    if not ok or type(info) ~= "table" or not info.source then return end
    local sibling = info.source:sub(1, 1) == "@" and info.source:sub(2) or info.source
    -- hide_elements.lua and level_loading_screen.lua are siblings in hb/.
    local src_path = sibling:gsub("hide_elements%.lua$", "level_loading_screen.lua")
    if src_path == sibling then return end  -- couldn't derive the sibling path; skip
    local txt = _rt_src_read(src_path)  -- (#511) io-safe; nil in retail sandbox => skip
    if not txt then return end
    local guard_needle = "if not mod.hb_fork" .. "_active() then"
    local read_needle = "mod.SETTING_NAMES.HIDE_LOADING_SCREEN" .. "_SUBTITLES"
    local guard_at = txt:find(guard_needle, 1, true)
    local read_at = txt:find(read_needle, 1, true)
    if not read_at then return end  -- hook restructured; the specific read is gone
    if not guard_at or guard_at >= read_at then
        return "hb regression: the LoadingView.create_ui_elements hook in hb/level_loading_screen.lua no longer gates on mod.hb_fork_active() before reading HIDE_LOADING_SCREEN_SUBTITLES (boot loading screen would crash 'index field SETTING_NAMES (a nil value)')"
    end
end)

-- (#281) Absorbed UI Tweaks (HideBuffs) fork boots WITHOUT Penlight. The fork's data
-- file (hb/hb_data.lua) used to `require` a Penlight module that does not exist as a
-- lua resource in the retail sandbox, so it aborted at load -- mod.SETTING_NAMES and
-- the fork's data tables went undefined and every hide/loading-screen feature went
-- silently dead. hb_data.lua now uses a plain-Lua shim (marker hb_pl_shim). RUNTIME
-- proof (authoritative in retail): the data backbone loaded and the shim-built tables
-- exist and behave. SOURCE proof (io-safe, skipped in retail; runs under CI/tools):
-- no Penlight require/usage remains and the shim marker is present. Anchor
-- mod.hb_fork_active resolves hb_data.lua's path (it defines no other function).
-- Needles split so this check can't self-match.
_rt_register("hb_penlight_removed", function()
    if type(mod.SETTING_NAMES) ~= "table" then
        return "hb regression: mod.SETTING_NAMES is not a table (hb_data.lua aborted at load -- Penlight require back?)"
    end
    if mod.SETTING_NAMES.HIDE_LOADING_SCREEN_SUBTITLES == nil or mod.SETTING_NAMES.HIDE_BOSS_HP_BAR == nil then
        return "hb regression: SETTING_NAMES is missing fork keys (hb_data.lua did not run to completion)"
    end
    -- List replacement: ubersreik_lvls is consumed as a :contains list at hide_elements.lua:251.
    local lvls = mod.ubersreik_lvls
    if type(lvls) ~= "table" or type(lvls.contains) ~= "function" then
        return "hb regression: mod.ubersreik_lvls lost its :contains method (List shim broken)"
    end
    if lvls:contains("magnus") ~= true or lvls:contains("__nope__") ~= false then
        return "hb regression: ubersreik_lvls:contains returned wrong results (List shim broken)"
    end
    -- Map replacement: career_name_to_hat_icon is a plain key->value lookup table.
    if type(mod.career_name_to_hat_icon) ~= "table" or mod.career_name_to_hat_icon.es_knight == nil then
        return "hb regression: mod.career_name_to_hat_icon missing (Map shim broken)"
    end
    local ok, info = pcall(debug.getinfo, mod.hb_fork_active or function() end, "S")
    if not ok or type(info) ~= "table" or not info.source then return end
    local src = info.source:sub(1, 1) == "@" and info.source:sub(2) or info.source
    local txt = _rt_src_read(src)  -- (#511) io-safe; nil in retail sandbox => skip
    if not txt then return end
    if txt:find("import" .. "_into", 1, true)
        or txt:find("pl." .. "List", 1, true)
        or txt:find("pl." .. "Map", 1, true) then
        return "hb regression: a Penlight reference is back in hb_data.lua (retail sandbox has no pl.* resource -> load abort)"
    end
    if not txt:find("hb_pl" .. "_shim", 1, true) then
        return "hb regression: the hb_pl_shim marker is gone from hb_data.lua (Penlight replacement removed)"
    end
end)

-- (#281) Absorbed-fork dormancy gate. With the Penlight abort fixed the fork now
-- BOOTS, so it must defer to the stock "UI Tweaks" (HideBuffs) mod when that is
-- installed + enabled (the #312 bridge owns the overlapping settings) -- otherwise
-- the same hides fire twice (and NUM_SUBTITLE_ROWS / OutlineSettings.ranges fight).
-- Previously the fork "self-gated" only by crashing; the explicit gate replaces that.
-- RUNTIME proof: the gate helpers exist and return booleans. SOURCE proof (io-safe):
-- the hide-elements hooks gate on mod.hb_fork_active() (anchor is the sibling
-- mod.reapply_pickup_ranges). Needles split so this check can't self-match.
_rt_register("hb_fork_dormancy_gate", function()
    if type(mod.hb_fork_active) ~= "function" then
        return "hb regression: mod.hb_fork_active dormancy gate missing (fork can't defer to stock UI Tweaks)"
    end
    if type(mod.hb_stock_owns) ~= "function" then
        return "hb regression: mod.hb_stock_owns missing (dormancy gate can't detect stock UI Tweaks)"
    end
    if type(mod.hb_fork_active()) ~= "boolean" or type(mod.hb_stock_owns()) ~= "boolean" then
        return "hb regression: dormancy gate did not return a boolean"
    end
    local ok, info = pcall(debug.getinfo, mod.reapply_pickup_ranges or function() end, "S")
    if not ok or type(info) ~= "table" or not info.source then return end
    local src = info.source:sub(1, 1) == "@" and info.source:sub(2) or info.source
    local txt = _rt_src_read(src)  -- (#511) io-safe; nil in retail sandbox => skip
    if not txt then return end
    if not txt:find("hb_fork" .. "_active()", 1, true) then
        return "hb regression: hide_elements.lua no longer gates on mod.hb_fork_active() (fork double-applies when stock UI Tweaks is enabled)"
    end
end)

-- UI Tweaks "Temporal Fix" (absorbed): re-aligns stock UI Tweaks (HideBuffs)
-- player HP-bar placement broken by the Versus update. Applied at
-- on_all_mods_loaded (HideBuffs must be loaded first); also tried now in case
-- HideBuffs loaded before us. No-op if UI Tweaks isn't installed. See
-- _gut_uitweaks_temporal_fix.lua for the verified diff + mechanism.
local _gut_temporal_fix = mod:dofile("scripts/mods/gui_tweaker/_gut_uitweaks_temporal_fix")
-- UI Tweaks HUD-customizer write-through (#312): when UI Tweaks (HideBuffs) is
-- installed + enabled and gut_uitweaks_sync is on, UI Tweaks OWNS the buff bar,
-- boss HP bar, overcharge bar, and energy bar -- gut's drag editor writes UI
-- Tweaks' offsets instead of its own, so the two never stack. Adds NO game hooks;
-- migrate() re-attempted at on_all_mods_loaded (HideBuffs may load after us). No-op
-- when UI Tweaks is absent. See _gut_uitweaks_sync.lua for the element map + the
-- per-element coordinate-space verification.
local _gut_uitweaks_sync = mod:dofile("scripts/mods/gui_tweaker/_gut_uitweaks_sync")
if _gut_uitweaks_sync and _gut_uitweaks_sync.install then pcall(_gut_uitweaks_sync.install) end

-- (#312) UI Tweaks integration regression tests. Split needles so the source-pattern
-- checks can never self-match; unreadable source => silent skip (pass).
local _gut_read_all = _rt_src_read  -- (#511) io-safe; nil in retail sandbox => skip

_rt_register("issue318_disabled_integrations_keep_normal_sections", function()
    local ok_p, Policy = pcall(mod.dofile, mod,
        "scripts/mods/gui_tweaker/_mod_tweaker_disabled_sections")
    if not ok_p or type(Policy) ~= "table" then
        return "#318 disabled-section policy unavailable"
    end
    local roles = { wt = "weapons", character_weapon_variants = "cwv" }
    local members, count = Policy.select_members({
        { mod_id = "wt", enabled = true },
        { mod_id = "character_weapon_variants", enabled = false },
    }, roles)
    if count ~= 2 or not members.cwv or members.cwv.enabled ~= false then
        return "#318 presence-based Equipment membership dropped disabled CWV"
    end
    local filtered, found = Policy.disable_group_subtree({
        { setting_id = "hb_group", type = "group", depth = 1 },
        { setting_id = "hide_frames", type = "checkbox", depth = 2 },
        { setting_id = "after", type = "group", depth = 1 },
    }, "hb_group")
    if not found or #filtered ~= 2 or filtered[1].disabled ~= true
        or filtered[1].tooltip ~= Policy.REASON then
        return "#318 disabled UI Tweaks subtree is not reduced to an explained header"
    end

    local ok, info = pcall(debug.getinfo, mod.on_setting_changed or function() end, "S")
    if not ok or type(info) ~= "table" or not info.source then return end
    local src = info.source:sub(1, 1) == "@" and info.source:sub(2) or info.source
    local dir = src:match("^(.*[/\\])[^/\\]*$")
    if not dir then return end
    for _, fn in ipairs({ "_mod_tweaker_view.lua", "_mod_tweaker_state.lua" }) do
        local txt = _gut_read_all(dir .. fn)
        if txt then
            if not txt:find("disabled_sections.select_" .. "members(cats, _EQUIP_ROLE)", 1, true) then
                return "#318 " .. fn .. " no longer uses presence-based Equipment membership"
            end
            if not txt:find("disabled_sections.disable_group_" .. "subtree", 1, true) then
                return "#318 " .. fn .. " no longer explains disabled UI Tweaks in place"
            end
            if not txt:find("row._disabled_in_" .. "vmf = true", 1, true) then
                return "#318 " .. fn .. " no longer renders disabled headers read-only/grey"
            end
        end
    end
end)

_rt_register("uitweaks_not_separate_modtweaker_tab", function()
    -- #312 (reworked per user): HideBuffs must NOT be in the _MY_MODS whitelist.
    -- UI Tweaks options live in gut's OWN menu under the single "UI Tweaks" group
    -- (hb_group), not as a separate Mod Tweaker tab. A re-add resurrects the
    -- duplicate tab the user flagged, so this now guards AGAINST the whitelist.
    local ok, info = pcall(debug.getinfo, mod.on_setting_changed or function() end, "S")
    if not ok or type(info) ~= "table" or not info.source then return end
    local src = info.source:sub(1, 1) == "@" and info.source:sub(2) or info.source
    local dir = src:match("^(.*[/\\])[^/\\]*$")
    if not dir then return end
    local needle = "HideBuffs = " .. "true"
    for _, fn in ipairs({ "_mod_tweaker_view.lua", "_mod_tweaker_state.lua" }) do
        local txt = _gut_read_all(dir .. fn)
        if txt and txt:find(needle, 1, true) then
            return "HideBuffs is whitelisted in " .. fn .. " -- that resurrects the separate UI Tweaks tab (#312)"
        end
    end
end)

_rt_register("uitweaks_sync_map_resolves", function()
    -- Every ELEMENT_MAP x/y key must resolve to a real HideBuffs.SETTING_NAMES entry.
    -- Skips cleanly (pass) when UI Tweaks isn't installed.
    local sync = mod._gut_uitweaks_sync
    if type(sync) ~= "table" or type(sync.ELEMENT_MAP) ~= "table" then
        return "uitweaks sync module or ELEMENT_MAP missing"
    end
    local HB = get_mod("HideBuffs")
    if not HB then return end  -- HB absent: nothing to resolve, pass.
    local names = HB.SETTING_NAMES
    if type(names) ~= "table" then return "HideBuffs.SETTING_NAMES missing" end
    for widget_id, m in pairs(sync.ELEMENT_MAP) do
        if type(m) ~= "table" or not m.x or not m.y then
            return "ELEMENT_MAP[" .. tostring(widget_id) .. "] malformed"
        end
        if names[m.x] == nil then
            return string.format("ELEMENT_MAP[%s].x=%s not in HB.SETTING_NAMES", tostring(widget_id), tostring(m.x))
        end
        if names[m.y] == nil then
            return string.format("ELEMENT_MAP[%s].y=%s not in HB.SETTING_NAMES", tostring(widget_id), tostring(m.y))
        end
    end
end)

_rt_register("uitweaks_bridged_to_stock_settings", function()
    -- (#312) The Mod Tweaker must consume HideBuffs' CURRENT VMF widget list and route
    -- every supported live node to that stock mod. A copied checkbox allow-list silently
    -- loses future groups/sliders/dropdowns/keybinds. Both twins must use the shared planner
    -- and must exclude HideBuffs from GUT's own profile snapshots.
    local ok, info = pcall(debug.getinfo, mod.on_setting_changed or function() end, "S")
    if not ok or type(info) ~= "table" or not info.source then return end
    local src = info.source:sub(1, 1) == "@" and info.source:sub(2) or info.source
    local dir = src:match("^(.*[/\\])[^/\\]*$")
    if not dir then return end
    local marker    = "[UITWEAKS-BRIDGE" .. "-312]"
    local live_marker = "[UITWEAKS-LIVE-TREE" .. "-312]"
    local call_form = "_bridge_uitweaks_to" .. "_stock(out)"
    for _, fn in ipairs({ "_mod_tweaker_view.lua", "_mod_tweaker_state.lua" }) do
        local txt = _gut_read_all(dir .. fn)
        if txt then
            if not txt:find(marker, 1, true) then
                return fn .. " dropped the UI Tweaks->stock HideBuffs bridge helper (#312)"
            end
            if not txt:find(call_form, 1, true) then
                return fn .. " no longer calls the UI Tweaks->stock HideBuffs bridge in the category build (#312)"
            end
            if not txt:find(live_marker, 1, true)
                    or not txt:find("external_group.find_mod_list", 1, true)
                    or not txt:find("external_group.replace_group_children", 1, true) then
                return fn .. " no longer folds the live HideBuffs VMF widget tree (#312)"
            end
            if not txt:find("_profile_excluded_owners", 1, true) then
                return fn .. " no longer keeps UI Tweaks out of GUT profile snapshots (#312)"
            end
        end
    end
    local planner = _gut_read_all(dir .. "_mod_tweaker_external_group.lua")
    if planner and (not planner:find("live_tree_spliced", 1, true)
            or not planner:find("exclude_owner_from_profiles", 1, true)) then
        return "shared external-group planner lost live-tree/profile-exclusion contracts (#312)"
    end
end)

_rt_register("vanilla_numeric_mirror_wired", function()
    -- Both mirror setting ids exist in the data tree AND on_setting_changed writes
    -- the vanilla engine setting.
    local ok, info = pcall(debug.getinfo, mod.on_setting_changed or function() end, "S")
    if not ok or type(info) ~= "table" or not info.source then return end
    local src = info.source:sub(1, 1) == "@" and info.source:sub(2) or info.source
    local dir = src:match("^(.*[/\\])[^/\\]*$")
    if dir then
        local data_txt = _gut_read_all(dir .. "gui_tweaker_data.lua")
        if data_txt then
            for _, sid in ipairs({ "gut_vanilla_numeric" .. "_ui", "gut_vanilla_persistent" .. "_ammo" }) do
                if not data_txt:find(sid, 1, true) then
                    return "vanilla mirror setting missing from data tree: " .. sid
                end
            end
        end
    end
    local main_txt = _gut_read_all(src)
    if main_txt and not main_txt:find('set_user_setting("numeric' .. '_ui"', 1, true) then
        return "on_setting_changed missing the numeric_ui vanilla mirror write (#312)"
    end
end)
_rt_register("freecam_invariants", function()
    -- Free Camera (#307) load-bearing invariants, source-pattern checked so the two
    -- prior-attempt failure classes can't regress silently. Resolve the module path
    -- from the main file's source dir (same idiom as the mirror-wired check above).
    local ok, info = pcall(debug.getinfo, mod.on_setting_changed or function() end, "S")
    if not ok or type(info) ~= "table" or not info.source then return end
    local src = info.source:sub(1, 1) == "@" and info.source:sub(2) or info.source
    local dir = src:match("^(.*[/\\])[^/\\]*$")
    if not dir then return end
    -- Wiring must be live regardless of source availability.
    if type(mod._gut_apply_freecam) ~= "function" then return "mod._gut_apply_freecam not wired" end
    if type(mod.gut_freecam_toggle) ~= "function" then return "mod.gut_freecam_toggle not wired" end
    local data_txt = _gut_read_all(dir .. "gui_tweaker_data.lua")
    if data_txt and not data_txt:find("gut_freecam_enabled", 1, true) then
        return "gut_freecam_enabled missing from data tree"
    end
    local fc = _gut_read_all(dir .. "_gut_freecam.lua")
    if not fc then return end   -- source not shipped in bundle; wiring checks above still ran
    -- INVARIANT 1: never call set_disabled (the nil-run_func crash class that killed
    -- the old gt attempt). Match the call form, not the word in comments.
    if fc:find("set_disabled%s*%(") or fc:find(":set_disabled") then
        return "freecam calls set_disabled -- the locomotion-freeze crash class (#307 must never reintroduce)"
    end
    -- INVARIANT 2: the anti-bleed hook is present (the fix the old attempt lacked).
    if not fc:find("is_input_blocked", 1, true) then
        return "freecam missing the PlayerInputExtension.is_input_blocked anti-bleed hook"
    end
    -- INVARIANT 3: an F8 raw keyboard poll is still offered as a convenience exit.
    if not fc:find("Keyboard.button", 1, true) then
        return "freecam missing the raw Keyboard exit poll (belt-and-suspenders exit)"
    end
    -- INVARIANT 4: the disable_free_flight gate is NOT lifted (keeps the vanilla
    -- F8/F9/drop-player dispatcher from running and misfiring).
    if fc:find("disable_free_flight%s*=%s*false") then
        return "freecam lifts disable_free_flight -- exposes the vanilla free-flight key dispatch (#307 keeps the gate up)"
    end
    -- INVARIANT 5 (#307 hard-lock fix): after _enter_free_flight steals every device via
    -- block_device_except_service, we MUST hand them back so ESC/keybind/checkbox exits
    -- keep working (the character stays frozen by is_input_blocked). If this call is ever
    -- removed the mod re-bricks: input locks with only the fragile F8 poll to escape.
    if not fc:find("device_unblock_all_services", 1, true) then
        return "freecam does not unblock input devices after entering free flight -- #307 hard input-lock regressed"
    end
    -- INVARIANT 6 (BUG_CLASSES 32, #459 family): every WorldManager lookup in the freecam
    -- module must route through the has_world-gated _live_world helper. A bare lookup on the
    -- mods_update path fasserts on Leave Game (WorldManager.world, world_manager.lua:111-115),
    -- and a nil check placed after the bare call is dead code. Functional half: the gate
    -- predicate must return nil, not raise, for a world that does not exist.
    if type(mod._gut_fc_live_world) ~= "function" then
        return "freecam _live_world gate helper not wired (mod._gut_fc_live_world) -- BUG_CLASSES 32"
    end
    local ok_lw, lw = pcall(mod._gut_fc_live_world, "__rt_no_such_world__")
    if not ok_lw then
        return "freecam _live_world RAISED on a missing world -- has_world gate broken (BUG_CLASSES 32): " .. tostring(lw)
    end
    if lw ~= nil then
        return "freecam _live_world returned a value for a missing world (gate not gating)"
    end
    -- Pattern half: no bare gated-manager lookup outside the helper (needle split so this
    -- check can't self-match its own source).
    local bare_needle = "Managers.world:" .. "world("
    if fc:find(bare_needle, 1, true) then
        return "freecam has a bare " .. bare_needle .. " call -- must route through _live_world (BUG_CLASSES 32)"
    end
    -- The state-transition force-exit must keep its dead-world release path (the engine's
    -- own _clear_free_flight), or the engine slot leaks active=true across teardown.
    if not fc:find("_clear_free_flight", 1, true) then
        return "freecam dropped the _clear_free_flight dead-world release (class-32 force-exit regressed)"
    end
end)

-- (#313) Crosshair Kill Confirmation bridge regression tests. Split needles so the
-- source-pattern checks can't self-match; unreadable source => silent skip (pass).
_rt_register("mod_tweaker_no_integrated_toplevel_tabs", function()
    -- (#339) A third-party INTEGRATED mod must NEVER get a top-level Mod Tweaker tab --
    -- a tab is only for the author's own Tweaker-series mods. Crosshair Kill Confirmation
    -- (#313, absorbed) must NOT be in the _MY_MODS whitelist of the two TAB-DRIVING files;
    -- its options fold INTO gut's Interface tab under the HUD group via _inject_ckc_into_gut
    -- (the UI Tweaks / HideBuffs #312 precedent). Re-adding CKC to _MY_MODS resurrects the
    -- wrong #313 tab this issue corrects. NOTE: the config-EXPORT whitelist in
    -- _gut_config_file.lua is a SEPARATE concern (settings snapshot/restore) and
    -- legitimately keeps CKC + HideBuffs, so it is intentionally NOT checked here.
    -- Binding rule: gui_tweaker/MOD_TWEAKER_INTEGRATION.md.
    local ok, info = pcall(debug.getinfo, mod.on_setting_changed or function() end, "S")
    if not ok or type(info) ~= "table" or not info.source then return end
    local src = info.source:sub(1, 1) == "@" and info.source:sub(2) or info.source
    local dir = src:match("^(.*[/\\])[^/\\]*$")
    if not dir then return end
    local ckc_tab_needle = '["Crosshair Kill Confirmation"] = ' .. "true"
    local fold_needle    = "_inject_ckc_into" .. "_gut"
    for _, fn in ipairs({ "_mod_tweaker_view.lua", "_mod_tweaker_state.lua" }) do
        local txt = _gut_read_all(dir .. fn)
        if txt then
            if txt:find(ckc_tab_needle, 1, true) then
                return "CKC is whitelisted in _MY_MODS in " .. fn ..
                    " -- resurrects the wrong #313 top-level tab (#339); it must fold into the HUD group"
            end
            if not txt:find(fold_needle, 1, true) then
                return "_inject_ckc_into_gut fold missing from " .. fn ..
                    " -- CKC options would not appear under the Interface>HUD category (#339)"
            end
        end
    end
end)

_rt_register("issue528_ckc_vanilla_options_isolated", function()
    -- User decision 2026-07-14: CKC belongs only to its own VMF page and the
    -- Mod Tweaker fold. Production must never hook, rewrite, augment, suppress,
    -- or redirect the vanilla Options row. Source checks are split so this
    -- regression cannot match its own needles; retail without io safely skips.
    if mod._gut_ckc_bridge ~= nil or mod._GUT_CKC_BRIDGE_MARKER ~= nil then
        return "#528 CKC vanilla-Options bridge API was published"
    end
    local ok, info = pcall(debug.getinfo, mod.on_setting_changed or function() end, "S")
    if not ok or type(info) ~= "table" or not info.source then return end
    local src = info.source:sub(1, 1) == "@" and info.source:sub(2) or info.source
    local dir = src:match("^(.*[/\\])[^/\\]*$")
    if not dir then return end
    local forbidden = {
        "_gut_ckc_" .. "bridge",
        "_gut_ckc_" .. "widget_policy",
        "_gut_ckc_" .. "render_policy",
        "cb_crosshair_" .. "kill_confirm",
        "gut_ckc_" .. "gear",
        "prepare_settings_" .. "definition",
        "_gut_mt_focus_" .. "request",
    }
    for _, fn in ipairs({ "_mod_tweaker_view.lua" }) do
        local txt = _gut_read_all(dir .. fn)
        if txt then
            for _, needle in ipairs(forbidden) do
                if txt:find(needle, 1, true) then
                    return "#528 " .. fn .. " still carries CKC Options bridge surface: " .. needle
                end
            end
        end
    end
end)

_rt_register("hud_collapsibles_hold_first_position", function()
    -- (#527) Collapsible sub-groups sit FIRST at their level (user doctrine): in the
    -- HUD group the UI Tweaks collapsible (hb_group) must precede the first loose
    -- option (gut_hud_mode), and BOTH Mod Tweaker twins must splice the CKC sub-group
    -- at the START of the HUD child block (marker [CKC-SPLICE-FIRST" .. "-527]).
    -- Source-pattern checks with split needles; unreadable source => silent skip.
    local ok, info = pcall(debug.getinfo, mod.on_setting_changed or function() end, "S")
    if not ok or type(info) ~= "table" or not info.source then return end
    local src = info.source:sub(1, 1) == "@" and info.source:sub(2) or info.source
    local dir = src:match("^(.*[/\\])[^/\\]*$")
    if not dir then return end
    local data_txt = _gut_read_all(dir .. "gui_tweaker_data.lua")
    if data_txt then
        local hb_at   = data_txt:find('"hb' .. '_group"', 1, true)
        local mode_at = data_txt:find('"gut_hud' .. '_mode"', 1, true)
        if hb_at and mode_at and hb_at > mode_at then
            return "hb_group (UI Tweaks collapsible) no longer leads the HUD group -- collapsibles sort first (#527)"
        end
    end
    local splice_needle = "CKC-SPLICE-FIRST" .. "-527"
    for _, fn in ipairs({ "_mod_tweaker_view.lua", "_mod_tweaker_state.lua" }) do
        local txt = _gut_read_all(dir .. fn)
        if txt and not txt:find(splice_needle, 1, true) then
            return fn .. " lost the " .. splice_needle .. " head-of-HUD splice (#527: CKC group must lead the HUD child block)"
        end
    end
end)

    return {
        temporal_fix = _gut_temporal_fix,
        sync = _gut_uitweaks_sync,
    }
end

return M
