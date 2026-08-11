local mod = get_mod("cosmetics_tweaker")
local RESOURCE_RESIDENCY = mod:dofile(
    "scripts/mods/cosmetics_tweaker/_lib_resource_residency")

-- #609: PlayerManager.local_player() calls Network.peer_id() directly and
-- faults once the network backend has been torn down. Vanilla's guarded API
-- returns nil unless a live network game exists (player_manager.lua:580-596).
-- Keep this above every dofile so lifecycle-reachable modules share one gate.
local function _local_player_safe(player_manager)
    local pm = player_manager or (Managers and Managers.player)
    if not (pm and type(pm.local_player_safe) == "function") then return nil end
    return pm:local_player_safe()
end
mod._local_player_safe = _local_player_safe
-- v0.9.3.1: LA Prefix Patch embedded. MUST load before anything that touches
-- LA hooks (the dedup filter wraps VMFMod's prototype methods, and LA's mod
-- script needs to load AFTER us in the F4 launcher for the wrap to catch
-- LA's duplicate registrations). Source archived at:
--   misc-vermintide-mods/la_prefix_patch_archive/
-- Self-skips if the standalone la_prefix_patch is still subscribed+enabled.
mod:dofile("scripts/mods/cosmetics_tweaker/_la_prefix_embedded")

-- v0.9.3.3: Material-Hijack (patched) embedded. Hooks Unit visibility +
-- UnitSpawner.spawn_local_unit. Source archived at:
--   misc-vermintide-mods/material_hijack_patched_archive/
-- Self-skips if the standalone (original 2771980886 OR patched 3727311798)
-- is enabled, or if a sibling tweaker mod already claimed the embed via
-- the `_G._cos_mh_embed_owner` sentinel.
-- v0.9.5: GearUtils.create_equipment + HeroPreviewer._spawn_item_unit hooks
-- DROPPED from MH embed to eliminate boot rehook warnings. MH's
-- replace_textures + add_particles + AnimTextureExtension logic now called
-- from cosmetics_tweaker's existing hooks via the module exports captured
-- below. Dormant guard (standalone enabled, sibling owner) still returns
-- a no-op table so the call sites below don't need nil-checks.
local MH_EMBED = mod:dofile("scripts/mods/cosmetics_tweaker/_material_hijack_embedded")

-- v0.9.3.6: MoreItemsLibrary embedded (upstream MIT © Aussiemon 2022).
-- Public API on cosmetics_tweaker's mod handle:
--   * mod:add_mod_items_to_masterlist(items)
--   * mod:add_mod_items_to_local_backend(items, mod_name)
--   * mod:remove_mod_items_from_local_backend(items, mod_name)
-- Consumers reach them via get_mod("MoreItemsLibrary") — la_prefix_embedded
-- aliases that lookup to whichever mod owns the embed. Self-skips if
-- standalone MoreItemsLibrary (Workshop 1422758813) is enabled, or if a
-- sibling tweaker mod already claimed via `_G._cos_mil_embed_owner`.
mod:dofile("scripts/mods/cosmetics_tweaker/_moreitemslibrary_embedded")

local U = mod:dofile("scripts/mods/cosmetics_tweaker/_cosmetic_unlocks")
local LA_BRIDGE = mod:dofile("scripts/mods/cosmetics_tweaker/_la_bridge")
local CUSTOM_HATS = mod:dofile("scripts/mods/cosmetics_tweaker/_cos_custom_hats")
mod._cos_attachment_link_policy = mod:dofile("scripts/mods/cosmetics_tweaker/_cos_attachment_link_policy")
local GK_SET = mod:dofile("scripts/mods/cosmetics_tweaker/_cos_grail_knight_set"); mod._cos_reikland_provider_registered = GK_SET.add_outfit_provider(mod:dofile("scripts/mods/cosmetics_tweaker/_cos_reikland_griffin"))
local APPEARANCE_FADE_RUNTIME = mod:dofile("scripts/mods/cosmetics_tweaker/_cos_appearance_fade_runtime").new(mod,
    { custom_hats = CUSTOM_HATS, gk_set = GK_SET, la_bridge = LA_BRIDGE })
mod._cos_appearance_fade = APPEARANCE_FADE_RUNTIME.adapter
local CWV_FAMILY_CONTRACT = mod:dofile("scripts/mods/cosmetics_tweaker/_cos_cwv_family_contract")
mod._cos_cwv_peer_identity = mod:dofile("scripts/mods/cosmetics_tweaker/_cos_cwv_peer_identity")
local OFFHAND_NAMES = mod:dofile("scripts/mods/cosmetics_tweaker/_cos_offhand_names")
local ITEM_PRESENTATION = mod:dofile("scripts/mods/cosmetics_tweaker/_cos_item_presentation")
local COMPOSITE_ICON_CATALOG = mod:dofile(
    "scripts/mods/cosmetics_tweaker/_cos_composite_icon_catalog")
local COMPOSITE_ICON_FACTORY = mod:dofile(
    "scripts/mods/cosmetics_tweaker/_cos_composite_icons")
local COMPOSITE_ICONS = COMPOSITE_ICON_FACTORY.new(COMPOSITE_ICON_CATALOG)
mod._cos_composite_icons = COMPOSITE_ICONS
local TPE = mod:dofile("scripts/mods/cosmetics_tweaker/_tpe")
local GlowPicker = mod:dofile("scripts/mods/cosmetics_tweaker/_glow_picker")
local GLOW_PREVIEW_POLICY = mod:dofile("scripts/mods/cosmetics_tweaker/_cos_glow_preview_policy")
local GLOW_BADGE = mod:dofile("scripts/mods/cosmetics_tweaker/_cos_glow_badge_policy")
local MAGIC_SKIN_GATEWAY = mod:dofile("scripts/mods/cosmetics_tweaker/_cos_magic_skin_gateway")
local LA_PERSIST = mod:dofile("scripts/mods/cosmetics_tweaker/_la_persistence")
local OFFHAND_COMMIT = mod:dofile("scripts/mods/cosmetics_tweaker/_cos_offhand_commit_policy")
local CUSTOM_ILLUSION_SYNC = mod:dofile(
    "scripts/mods/cosmetics_tweaker/_cos_custom_illusion_sync")
local LA_REPLAY_POLICY = mod:dofile("scripts/mods/cosmetics_tweaker/_cos_la_replay_policy")
mod._cos_complete_set_rebroadcast = mod:dofile(
    "scripts/mods/cosmetics_tweaker/_cos_complete_set_rebroadcast")
mod._la_instance_policy = mod:dofile("scripts/mods/cosmetics_tweaker/_cos_la_instance_policy")
mod._la_icon_provider = mod:dofile("scripts/mods/cosmetics_tweaker/_cos_la_inventory_icon").new(mod._la_instance_policy, printf, 32)
mod._la_option_icon_policy = mod:dofile(
    "scripts/mods/cosmetics_tweaker/_cos_la_option_icon_policy")
-- v0.9.49-dev (issue #186): disable Loremaster's Armoury's Okri's-Challenges /
-- achievement-book entries (main_quest + 12 sub-quests) — display, tracking and
-- completion pop-ups — behind the `la_disable_okri_challenges` toggle (default
-- ON = challenges DISABLED). Registers the AchievementManager.outline filter at
-- dofile time; the deferred template scrub runs from mod.update via LA_OKRI.tick.
local LA_OKRI = mod:dofile("scripts/mods/cosmetics_tweaker/_la_okri")
local SCORE_IDENTITY = mod:dofile("scripts/mods/cosmetics_tweaker/_cos_score_identity")
mod._cos_husk_identity = mod:dofile("scripts/mods/cosmetics_tweaker/_cos_husk_identity")
local OFFHAND_PRELOAD_LIFECYCLE = mod:dofile("scripts/mods/cosmetics_tweaker/_cos_offhand_preload_lifecycle")
mod._cos_weapon_pose_policy = mod:dofile("scripts/mods/cosmetics_tweaker/_cos_weapon_pose_policy")
local WEAPON_POSES = mod:dofile("scripts/mods/cosmetics_tweaker/_cos_weapon_poses")
-- #1145 (#660 Wave A): per-wearer re-wield coalescer + mid-destroy guard; every
-- wield pulse this mod initiates routes through it. Rationale in the module
-- header. On `mod`, not a local: this chunk is near the Lua 200-local ceiling.
mod._cos_rewield = mod:dofile("scripts/mods/cosmetics_tweaker/_cos_rewield_coalescer")
-- v0.9.24-dev: UI diagnostic dump harness. No-op at runtime unless the
-- enable_debug_logging VMF toggle is on. See _ui_dump.lua header for
-- what gets dumped per window class.
local UI_DUMP    = mod:dofile("scripts/mods/cosmetics_tweaker/_ui_dump")

-- Passive diagnostic emitter (printf, default-on, rate-limited). Drives the
-- [cos:sync] grep channel in the user's post-playtest log (LA husk/shield sync
-- divergence decisions, issues #149 #154 #200 #203 #204). See _cos_diag_lasync.lua.
-- (The [174:loadout] channel was retired with issue #174's fix; #500. File renamed
-- _diag_probe -> _cos_diag_lasync per PROJECT_STANDARDS §2.2b; #499.)
local PROBE      = mod:dofile("scripts/mods/cosmetics_tweaker/_cos_diag_lasync")

local MOD_VERSION = "0.9.201-dev"
-- #45: RPC schema version (VMF_RECIPES § 10). Prepended as the FIRST positional
-- arg of every mod:network_send this mod emits, and validated as the first arg
-- of every mod:network_register callback. On mismatch the receiver drops the
-- message (no state mutation, no crash). Bump ONLY when the payload shape of any
-- of this mod's 5 RPCs (cos_la_apply / cos_la_apply_req / cos_la_state_req /
-- cos_glow_apply / cos_glow_apply_req) changes (add/remove/reorder/retype a
-- field). ADDITIVE optional fields (v0.9.69's revert flag; v0.9.82's #416
-- offhand_unit vanilla-mesh field) and ADDITIVE RPC names (v0.9.70's
-- cos_la_state_req) do NOT bump -- old peers drop/ignore them harmlessly.
-- Schema 2 makes wearer_career mandatory for LA state, so schema-1 peers and
-- their unstamped records are deliberately dropped instead of guessed.
local COS_RPC_SCHEMA = 2
-- [mem-probe] temp Lua-footprint baseline (lua_heap 1 GiB cap diagnostic). Namespaced
-- under the mod table (v0.9.75-dev) so it no longer leaks into _G; read once at the
-- boot readout near the end of this file.
mod._cos_mem_t0 = collectgarbage("count")
-- Startup banner: log-only, NOT chat. The applied marker line further down
-- ([cosmetics] enabled v<X> settings_fp=<hash>) is the canonical version surface
-- (PROJECT_STANDARDS.md § 3.6 "Chat-echo policy").
mod:info("Cosmetics Tweaker v%s loaded", MOD_VERSION)

-- Two-helper debug-logging policy (PROJECT_STANDARDS.md § 3.6).
-- `_dbg` is for confirmation / expected behavior — mod:debug (file only,
-- gated by VMF output_mode_debug).
-- `_dbg_alert` is for unexpected / wrong / mismatch — LOG-ONLY via
-- pcall-guarded engine printf (#427/issue 240: mod:warning posts to CHAT
-- under VMF defaults; printf always lands in console-*.log, even with mod
-- logging OFF, and never in chat; pcall so a format slip never faults the
-- caller). _cos_glow.lua carries a byte-identical copy - keep in sync.
local function _dbg(fmt, ...)
    mod:debug("[cosmetics:dbg] " .. fmt, ...)
end

local function _dbg_alert(fmt, ...)
    if not pcall(printf, "[cosmetics:dbg] " .. fmt, ...) then
        pcall(printf, "[cosmetics:dbg] (alert format error: %s)", tostring(fmt))
    end
end

-- v0.9.43-dev: AGGRESSIVE LA-shield diagnostic trace channel. Distinct
-- `[cos:trace]` prefix so a single in-game repro can be grepped in isolation
-- from the rest of the [cosmetics:dbg] noise.
-- Covers the full LA-shield hover/paint/husk lifecycle (SCREEN / INPUT / WRITE /
-- RESOLVE / PAINT / HUSK / SYNC / TRANSITION) so one repro yields the causal
-- chain. Quiet/remove once those are fixed.
-- v0.9.52-dev (#150): route through mod:INFO, NOT mod:debug. This user runs with
-- VMF output_mode_debug OFF, so the prior mod:debug routing made the ENTIRE
-- INPUT/WRITE/RESOLVE/SYNC/HUSK/TRANSITION trace set INVISIBLE in their console
-- log — only the mod:info lines (`_trace_paint` PAINT + `[offhand-press]`)
-- survived, which is exactly why the hover→write→husk chain (and bugs 3/4) never
-- showed up. mod:info IS captured in their log (proven: PAINT lines land), so
-- match _trace_paint's channel.
local function _trace(fmt, ...)
    mod:info("[cos:trace] " .. fmt, ...)
end

-- Read a spawned unit's authored mesh path (the `unit_name` data field VT2
-- stamps onto equipment/shield units; same source the LA bridge walks in
-- walk_attachments). Used by the PAINT trace to compare the unit we're
-- painting against the mesh the LA variant EXPECTS — the
-- imperial-texture-on-bret-mesh bug shows up as actual_mesh ~= expected_mesh.
-- pcall-wrapped because Unit.get_data on a torn-down unit can fault.
local function _unit_mesh_name(unit)
    if type(unit) ~= "userdata" then return "<not-unit>" end
    local ok, name = pcall(function()
        if Unit.has_data and Unit.has_data(unit, "unit_name") then
            return Unit.get_data(unit, "unit_name")
        end
        return nil
    end)
    if ok and name then return tostring(name) end
    return "<no-unit_name>"
end

-- Emit ONE fully-provenanced PAINT trace line for an LA offhand paint.
--   site    = calling rendering path (loot_previewer / ingame / network_husk /
--             hero_previewer / hot_join) — the call-site tag the teammate wants
--   context = the context string actually passed to apply_offhand_to_unit
--   bid     = backend_id the paint resolved under (may be nil for husk paths)
--   unit    = the TARGET unit being painted
-- For kind="unit" variants the EXPECTED mesh is new_units[1]; if the target
-- unit's actual mesh differs, match=false flags the "imperial texture painted
-- onto the un-swapped bret mesh" case (mesh-vs-texture mismatch). Pure
-- diagnostics — never mutates anything, never paints.
local function _trace_paint(site, context, bid, unit, armoury_key, outcome)
    local variant = GK_SET and GK_SET.resolve_variant(armoury_key)
    if not variant then
        local la = get_mod("Loremasters-Armoury")
        variant = la and la.SKIN_LIST and la.SKIN_LIST[armoury_key]
    end
    local kind = variant and variant.kind or "?"
    local expected = "(texture-variant→paints base mesh)"
    local match = "n/a"
    if variant and variant.new_units then
        expected = tostring(variant.new_units[1])
    end
    local actual = _unit_mesh_name(unit)
    if variant and variant.new_units then
        match = tostring(actual == tostring(variant.new_units[1]))
    end
    mod:info("[cos:trace] PAINT site=%s ctx=%s bid=%s kind=%s key=%s target=%s target_mesh=%s expected=%s match=%s outcome=%s",
        tostring(site), tostring(context), tostring(bid), tostring(kind),
        tostring(armoury_key), tostring(unit), actual, expected, match, tostring(outcome))
end

-- Applied marker (PROJECT_STANDARDS.md § 3.6 "Applied marker line (universal)").
-- Walks the data widget tree, FNV-1a-32 hashes setting=value pairs, prints
-- one mod:info line at load. ALWAYS fires (operational telemetry).
local function _settings_fingerprint()
    local ok, data = pcall(require, "scripts/mods/cosmetics_tweaker/cosmetics_tweaker_data")
    if not ok or type(data) ~= "table" then return "nodata" end
    local keys = {}
    local function walk(node)
        if type(node) ~= "table" then return end
        if type(node.setting_id) == "string" then keys[#keys + 1] = node.setting_id end
        for _, child in pairs(node) do
            if type(child) == "table" then walk(child) end
        end
    end
    walk(data)
    if #keys == 0 then return "nosettings" end
    table.sort(keys)
    local parts = {}
    for i, k in ipairs(keys) do
        local v = mod:get(k)
        if v == true then       parts[i] = k .. "=1"
        elseif v == false then  parts[i] = k .. "=0"
        elseif v == nil then    parts[i] = k .. "=?"
        else                    parts[i] = k .. "=" .. tostring(v) end
    end
    local s = table.concat(parts, ";")
    local h = 2166136261
    for i = 1, #s do
        local byte = string.byte(s, i)
        local xored, place = 0, 1
        local hh, bb = h, byte
        for _ = 1, 32 do
            local hb, bbit = hh % 2, bb % 2
            if hb ~= bbit then xored = xored + place end
            place = place * 2
            hh = (hh - hb) / 2
            bb = (bb - bbit) / 2
        end
        h = (xored * 16777619) % 4294967296
    end
    return string.format("%08x", h)
end

mod:info("[cosmetics:LOAD] v%s enabled fp=%s OK", MOD_VERSION, _settings_fingerprint())

-- Per PROJECT_STANDARDS § 3.6 + § 14a: dev/alpha/beta/0.x versions print
-- version to chat on load so the user can see what's active. Stable
-- (>=1.0.0) versions stay silent. Detect via MOD_VERSION string match.
if MOD_VERSION:find("-dev$") or MOD_VERSION:find("-alpha$") or MOD_VERSION:find("-beta$") or MOD_VERSION:find("-rc%d*$") or MOD_VERSION:find("^0%.") then
    mod:echo(string.format("[cosmetics] v%s loaded", MOD_VERSION))
end

-- Command registration remains at its historical load position. Late runtime
-- checks register into the returned owner after all gameplay seams are wired.
local _rt_register = mod:dofile("scripts/mods/cosmetics_tweaker/_cos_command_owner").install(mod, {
        version = MOD_VERSION, local_player_safe = _local_player_safe,
        la_persist = LA_PERSIST, printf = printf,
    })

-- #1145: checks register from the module that owns the guarded code (§2.2a
-- rule 6), keeping marker and reader in one file (the #1148 scope-loss class).
mod._cos_rewield.install_checks(mod, _rt_register)

-- ============================================================
-- Material tinting research (TODO: cloned + recolored cosmetics)
-- ============================================================
-- v1: in-place tint applied to a specific hat key when spawned. Future v2 will
-- register a CLONED ItemMasterList entry so the original hat stays vanilla and
-- the tinted variant is a separate equippable item.


-- Returns true if the given Gui has the named material loaded.
--
-- IMPORTANT: `Gui.material(gui, name)` does NOT throw on missing materials in
-- this VT2 build — it returns nil silently. So pcall alone is NOT a reliable
-- probe; we MUST inspect the return value too. (An earlier version of this
-- function returned `ok` only and silently always reported "true", which made
-- the VMFOptionsView pre-check useless.)
local function _gui_has_material(gui, material_name)
    if not gui or not Gui or not Gui.material then return false end
    local ok, mat = pcall(Gui.material, gui, material_name)
    return ok and mat ~= nil
end

-- DLC ownership gate. Used across the unlock paths to refuse skins whose
-- ItemMasterList entry has `required_dlc` set when the player doesn't own
-- that DLC. Defined early because several hooks below reference it.
-- CLARIFY: this function MUST stay near the top of the file. v0.7.1 / v0.7.10
-- both crashed because forward references to it broke when callers were
-- defined above. See feedback_lua_forward_reference.md.
local function _skin_requires_unowned_dlc(skin_key)
    -- rawget required: ItemMasterList.__index calls Crashify on unknown keys
    -- (item_master_list.lua:133). LA bridge entries appear in WeaponSkins.skins
    -- but NOT in ItemMasterList — bracket access on those would crash.
    local item_data = rawget(ItemMasterList, skin_key)
    if not item_data or not item_data.required_dlc then return false end
    if not Managers.unlock then return false end
    return not Managers.unlock:is_dlc_unlocked(item_data.required_dlc)
end

-- Force-flush the engine console log so command output is on disk before the
-- user navigates anywhere. Stingray buffers writes; menu transitions flush
-- naturally but mid-keep a probe can sit in the buffer for minutes. Try every
-- known channel — whichever works in this VT2 build wins, the rest no-op.
local function _flush_log()
    pcall(function() if io and io.flush then io.flush() end end)
    pcall(function() if Log and Log.flush then Log.flush() end end)
    pcall(function()
        if Application and Application.console_command then
            -- Try several known engine-console flush command names.
            Application.console_command("flush_log")
            Application.console_command("log_flush")
            Application.console_command("flush")
        end
    end)
    mod:info("[flush] %s", tostring(os.time()))  -- nudge the buffer with a final line.
end


-- ============================================================
-- Phase 1 OOP split (v0.9.77-dev) - shared namespace + module manifest
-- ============================================================
-- mod._cos is the cross-module state table (event_tweaker's mod._evt pattern;
-- PROJECT_STANDARDS.md section 2.2a). Each _cos_*.lua module below is a
-- function-bag extraction of one self-contained concern; it reads shared
-- handles/helpers off mod._cos and registers its own hooks/commands. mod:dofile
-- is NOT a singleton, so modules never dofile each other - every module is
-- dofile'd exactly once here, AFTER the shared handles it consumes are set.
--   _cos_diagnostics : read-only dump/probe commands (was inline + probe_cosmetics)
--   _cos_illusions   : custom illusion + LA shield skin injection + Localize/unlock hooks
--   _cos_unlocks     : per-career unlocks + portrait frames + unobtainable-cosmetic grants
--   _cos_render      : weapon scale/grip apply helpers + shared _is_unit (v0.9.78-dev Phase 2)
--   _cos_glow        : weapon glow apply pipeline + MaterialSettingsTemplates routing (v0.9.79-dev Phase 3)
--   _cos_wire        : #421 custom-skin wire null/restore senders (v0.9.102-dev Phase 4a)
mod._cos = mod._cos or {}
mod._cos.U = U
mod._cos.LA_BRIDGE = LA_BRIDGE
mod._cos.encarmine_item_localization = CUSTOM_HATS.ITEM_LOCALIZATION
mod._cos.gk_set_item_localization = GK_SET.ITEM_LOCALIZATION
mod._cos.presentation_localization = mod._cos.presentation_localization or {}
mod._cos.flush_log = _flush_log
mod._cos.skin_requires_unowned_dlc = _skin_requires_unowned_dlc
-- custom_skin_keys: the illusions module fills it at registration; the wire-safety
-- null-and-restore senders (_wire_null_custom_skins) and the regression suite read
-- it. Keep an entry-local alias for the regression suite; `_cos_wire` captures the
-- same namespace table after `_cos_illusions` populates it.
mod._cos.custom_skin_keys = mod._cos.custom_skin_keys or {}
local _custom_skin_keys = mod._cos.custom_skin_keys

mod:dofile("scripts/mods/cosmetics_tweaker/_cos_diagnostics")
mod:dofile("scripts/mods/cosmetics_tweaker/_cos_illusions")
-- _cos_wire consumes the custom_skin_keys table populated by _cos_illusions,
-- so this manifest edge is load-bearing. It owns all three rpc_add_equipment
-- sender hooks and their frozen regression surface.
local _cos_wire = mod:dofile("scripts/mods/cosmetics_tweaker/_cos_wire")
assert(type(_cos_wire) == "table" and type(_cos_wire.install) == "function",
    "_cos_wire must return an installer")
assert(_cos_wire.install(mod) == true, "_cos_wire safety hooks failed to install")
mod:dofile("scripts/mods/cosmetics_tweaker/_cos_unlocks")
-- _cos_render has no load-time reads of other modules' exports and its own
-- exports (scale_units/offset_units/apply_unit_path_scale_hand/is_unit) are
-- consumed only at runtime inside the render hooks below, so its manifest
-- position is free; it sits here with the other _cos_* extractions.
mod:dofile("scripts/mods/cosmetics_tweaker/_cos_render")
-- _cos_glow consumes mod._cos.is_unit (exported by _cos_render), so it MUST be
-- dofile'd AFTER _cos_render. Its own exports (apply_glow_override,
-- glow_owner_peer_for_unit) are consumed only at runtime by the three render hooks
-- below. It also owns the init of mod._glow_by_peer + mod._unit_to_backend_id.
mod:dofile("scripts/mods/cosmetics_tweaker/_cos_glow")
-- _custom_illusions is shared: the illusions module owns/populates it; the
-- offhand force-loader (_force_load_all_offhand_packages) walks it to preload
-- each illusion's hand-unit packages on every peer.
local _custom_illusions = mod._cos.custom_illusions
-- _is_unit moved to _cos_render.lua (Phase 2). Keep a byte-identical entry-local
-- alias so the _is_unit(...) call sites still in this file stay unchanged: the
-- LA-offhand paint (_apply_la_offhand_to_units) and the glow-dump diagnostic
-- command. (The glow apply subsystem that also used it moved to _cos_glow.lua in
-- Phase 3.) The render hooks call the moved apply helpers via mod._cos.* directly.
local _is_unit = mod._cos.is_unit

-- _glow_by_peer: per-peer glow cache. _cos_glow.lua (dofile'd above) owns its init
-- (mod._glow_by_peer = mod._glow_by_peer or {}) and captures a module-local; keep a
-- byte-identical entry-local alias here for the combined LA/glow state-snapshot and
-- diagnostics paths that remain below. The dedicated glow RPC send/register layer is
-- owned by _cos_glow_transport.lua. Phase 3 OOP split (v0.9.79-dev).
local _glow_by_peer = mod._glow_by_peer

-- #574 verification evidence is deliberately bounded and log-only.  A normal
-- two-player verify run exercises send/receive plus several spawn paths; the
-- cap prevents a preview rebuild loop from growing the console log forever.
local function _cos574_log(fmt, ...)
    mod._cos574_diag_count = mod._cos574_diag_count or 0
    if mod._cos574_diag_count >= 48 then return end
    mod._cos574_diag_count = mod._cos574_diag_count + 1
    if rawget(_G, "printf") then
        local ok, message = pcall(string.format, fmt, ...)
        pcall(printf, "[cos:574] %s evidence=%d/48 chat=false",
            ok and message or tostring(fmt), mod._cos574_diag_count)
    end
end


-- ============================================================
-- Hot-reload / missing-material safety net
-- ============================================================
-- When a mod's atlas isn't on the active Gui (LA reload, VMF options view
-- with vmf_atlas not injected, etc.), the next draw fatals the engine with
-- "Material 'X' not found in Gui". ui_passes.lua captures
-- UIRenderer.draw_texture as a file-local at load time so we can't intercept
-- there. But UIRenderer.draw_widget is called via the global table from many
-- callers (vmf_options_view, NewsFeedUI per-widget, etc.) — hooking it
-- catches the most common surfaces.
-- VMFOptionsView safety hook removed: Gui.material() does not reliably detect
-- materials loaded via VMF's resource packages, so the pre-check was blocking
-- the VMF options menu from rendering entirely. VMF handles its own draw
-- lifecycle — cosmetics_tweaker should not guard it.

mod:dofile("scripts/mods/cosmetics_tweaker/_cos_news_feed_safety").install(mod, {
    dbg_alert = _dbg_alert,
    get_ui_renderer = function()
        return UIRenderer
    end,
})


-- Cosmetic unlocks (per-career can_wield) moved to _cos_unlocks.lua (v0.9.77-dev
-- Phase 1 OOP split), together with portrait frames + unobtainable-cosmetic
-- grants. apply_cosmetic_unlocks is exported as mod._cos.apply_cosmetic_unlocks;
-- the lifecycle callbacks below drive it.

mod:dofile("scripts/mods/cosmetics_tweaker/_cos_mod_lifecycle").install(mod, {
    trace = _trace,
    mh_embed = MH_EMBED,
    tpe = TPE,
    la_bridge = LA_BRIDGE,
})

mod:dofile("scripts/mods/cosmetics_tweaker/_cos_settings_runtime")
    .install(mod, CUSTOM_HATS, GK_SET, TPE)

-- v0.9.0-dev: TPE per-frame tick moved into the unified mod.update defined
-- later in the file (around line 3880, the LA bridge init driver). Previously
-- the second definition OVERWROTE this one and TPE.update silently never
-- fired since the merge. Single update function below handles both.

-- (probe_cosmetics command moved to _cos_diagnostics.lua, v0.9.77-dev Phase 1)

-- Weapon Visual Overrides (scale + grip apply layer) moved to _cos_render.lua
-- (v0.9.78-dev Phase 2 OOP split): the two-schema data tables
-- (_unit_path_scale_overrides + _breton_sword_thiccc, _weapon_grip_offsets) and
-- the resolve/apply helpers. The render HOOKS that drive them stay in this file
-- and call mod._cos.scale_units / .offset_units / .apply_unit_path_scale_hand.
-- See DEVELOPMENT.md "Module map" + "Render paths".

-- Custom weapon illusions + LA shield skin injection (and the
-- get_unlocked_weapon_skins + _G.Localize hooks for those keys) moved to
-- _cos_illusions.lua (v0.9.77-dev Phase 1 OOP split). Registered keys live on
-- mod._cos.custom_skin_keys.

-- Unlock-All portrait frames + vanilla-unobtainable cosmetic grants moved to
-- _cos_unlocks.lua (v0.9.77-dev Phase 1 OOP split).

-- ============================================================
-- Modded-realm illusion swap (bypass server-side craft block)
-- ============================================================
-- In modded realm the "Apply" button for weapon illusions is disabled
-- (HeroWindowItemCustomization._enable_craft_button force-sets enable=false
-- when script_data["eac-untrusted"]) and the server rejects craftingApplySkin2.
--
-- We intercept three points:
--   1. _enable_craft_button — temporarily clear eac-untrusted so the Apply
--      button is usable for illusion swaps. On disable, force-clear the
--      hotspot's is_held/input_pressed flags to prevent re-trigger: the
--      engine hotspot (ui_passes.lua:4386) only clears is_held on mouse
--      release, NOT when disable_button is set, so a fast craft completion
--      while the user is still holding the mouse causes an infinite
--      craft→complete→re-craft sound loop.
--   2. get_weapon_skin_from_skin_key — return synthetic backend IDs for
--      skins the player doesn't "own" in their backend inventory, so the
--      illusion browser can reference them. For vanilla locked skins this
--      is needed because get_weapon_skin_from_skin_key only searches
--      _fake_items (unlocked skins), not all known skins.
--   3. craft + update — when in modded and applying a weapon skin, write
--      item.skin directly on the local backend mirror instead of sending to
--      PlayFab. Result is deferred one frame via the update hook to match
--      the vanilla async timing and avoid same-frame completion artifacts.
--   4. _on_illusion_index_pressed — force content.locked = false so the
--      Apply button enables for skins the player hasn't earned.
--   5. _update_state_craft_button — temporarily clear eac-untrusted so the
--      craft button's disable_button flag doesn't bake in the modded check.
--
-- DLC ownership is respected: skins with a required_dlc field in
-- ItemMasterList are only unlockable if the player owns that DLC
-- (checked via Managers.unlock:is_dlc_unlocked). This prevents the mod
-- from bypassing paid cosmetic DLC paywalls.

-- Issue #377/#504: one contextual, manual Edit Glow control. Its policy,
-- refresh, and widget construction are one idempotent presentation owner;
-- positioning, input, and drawing remain with the host customization view.
local _refresh_glow_editor_button, _create_glow_editor_button
do
    local owner = mod:dofile("scripts/mods/cosmetics_tweaker/_cos_glow_editor_button").install(mod, {
            glow_picker = GlowPicker,
            glow_badge = GLOW_BADGE,
            ui_widget = UIWidget,
        })
    _refresh_glow_editor_button = owner.refresh
    _create_glow_editor_button = owner.create
end

local _cos_resolve_composed_appearance

local _cos_item_grid_presentation = mod:dofile(
    "scripts/mods/cosmetics_tweaker/_cos_item_grid_presentation").install(mod, {
        glow_badge = GLOW_BADGE,
        glow_picker = GlowPicker,
        composite_icons = COMPOSITE_ICONS,
        refresh_glow_editor_button = _refresh_glow_editor_button,
        resolve_composed_appearance = function(...)
            if _cos_resolve_composed_appearance then
                return _cos_resolve_composed_appearance(...)
            end
        end,
    })
local _refresh_illusion_glow_badges =
    _cos_item_grid_presentation.refresh_illusion_glow_badges

local MODDED_ILLUSION_SWAP = mod:dofile("scripts/mods/cosmetics_tweaker/_cos_modded_illusion_swap")
mod._cos_modded_illusion_swap_owner = MODDED_ILLUSION_SWAP.install(mod, {
    get_mod = get_mod,
    skin_requires_unowned_dlc = _skin_requires_unowned_dlc,
    custom_skin_keys = _custom_skin_keys,
    glow_picker = GlowPicker,
    refresh_glow_editor_button = _refresh_glow_editor_button,
    debug = _dbg,
    trace = _trace,
})
-- ============================================================
-- Independent offhand (shield) illusion system
-- ============================================================
-- Adds a second row of illusion buttons below the main row on the
-- weapon customization screen. The main row swaps the right-hand
-- weapon model; this row independently swaps the left-hand (shield)
-- model. Only shown for weapons that have a left_hand_unit.

-- Preload the unit packages backing an offhand override, so when the
-- in-game body re-spawns under a different illusion the engine can still
-- find our chosen shield mesh. The 1p and 3p meshes are SEPARATE packages
-- in vanilla VT2 — LA's own bootstrap loads both halves explicitly, and
-- WeaponUtils.get_weapon_packages confirms it (`unit_name` AND
-- `unit_name .. "_3p"` are queued separately). The in-game body spawns
-- BOTH halves; the customization previewer only spawns 3p. Load both.
--
-- ASYNCHRONOUS load: the former sync path predated `_override_package_ready`
-- (below). Both local and husk overrides now require Application.can_get for
-- the 1P and 3P units before exposing an override, so a queued package safely
-- degrades to the base mesh instead of reaching world.spawn_unit early. This
-- removes the startup ResourcePackage.flush storm while preserving the crash
-- gate. PackageManager invokes our callback only after force_load completes.
local _cos_offhand_catalog = mod:dofile(
    "scripts/mods/cosmetics_tweaker/_cos_offhand_catalog").install(mod, {
    offhand_preload_lifecycle = OFFHAND_PRELOAD_LIFECYCLE,
    offhand_names = OFFHAND_NAMES,
    gk_set = GK_SET,
    la_bridge = LA_BRIDGE,
    cwv_family_contract = CWV_FAMILY_CONTRACT,
    custom_illusions = _custom_illusions,
    skin_requires_unowned_dlc = _skin_requires_unowned_dlc,
    dbg = _dbg,
    dbg_alert = _dbg_alert,
    get_mod = get_mod,
    get_managers = function() return Managers end,
    application = Application,
    network_lookup = NetworkLookup,
    weapon_skins = WeaponSkins,
    item_master_list = ItemMasterList,
    printf = printf,
})
local _preload_offhand_package = _cos_offhand_catalog.preload_offhand_package
local _preload_offhand_for_option = _cos_offhand_catalog.preload_offhand_for_option
local _force_load_all_offhand_packages = _cos_offhand_catalog.force_load_all_offhand_packages
local _override_package_ready = _cos_offhand_catalog.override_package_ready
local _resolve_authored_offhand_variant = _cos_offhand_catalog.resolve_authored_offhand_variant
local _resolve_authored_offhand_mesh = _cos_offhand_catalog.resolve_authored_offhand_mesh
local _SHIELD_POOLS_BY_ITEM_TYPE = _cos_offhand_catalog.shield_pools_by_item_type
local _decorate_shield_option = _cos_offhand_catalog.decorate_shield_option
local _SHIELD_ICON_OWNER_ITEM_TYPES = _cos_offhand_catalog.shield_icon_owner_item_types
local _inventory_icon_for_offhand_unit = _cos_offhand_catalog.inventory_icon_for_offhand_unit
local _source_illusion_name = _cos_offhand_catalog.source_illusion_name
local _offhand_options = _cos_offhand_catalog.offhand_options
local _MULTI_MOUNT_ITEM_TYPES = _cos_offhand_catalog.multi_mount_item_types
local _DUAL_WIELD_POOLS = _cos_offhand_catalog.dual_wield_pools

-- _offhand_selection[backend_id][hand_field] = option_table. Vanilla
-- entries have only `unit`; LA-bridge entries have `la_armoury_key` +
-- `vanilla_skin` (no `unit` — LA paints onto whatever shield mesh the
-- user's vanilla illusion provides).
--
-- v0.8.32 KEYING CHANGE: keyed by `backend_id`, not `item_type`.
-- v0.9.9.4 SCHEMA CHANGE: per-hand nesting. `_offhand_selection[bid]` is
-- now a table whose keys are hand_field strings ("right_hand_unit" /
-- "left_hand_unit") and whose values are the option records. Single-mount
-- shield picks store under `left_hand_unit` (matching pre-v0.9.9.4
-- behavior); multi-mount picks (rapier+pistol, dual-wields) store one
-- entry per hand the user customized. In-memory only.
local _offhand_session_state = mod:dofile(
    "scripts/mods/cosmetics_tweaker/_cos_offhand_session_state").new({
    selections = {},
    baselines = mod._offhand_baseline,
    committed = mod._offhand_committed,
})
local _offhand_selection = _offhand_session_state.selections
mod._offhand_baseline = _offhand_session_state.baselines
mod._offhand_committed = _offhand_session_state.committed

-- v0.9.9.4-dev: tolerate the pre-v0.9.9.4 schema where
-- `_offhand_selection[bid]` was the option record itself (not a per-hand
-- map). Detects the old shape by checking for option-record fields (`unit`
-- / `intended_unit` / `la_armoury_key`); if found, wraps the record as
-- `{ left_hand_unit = old_record }` in place so subsequent reads see the
-- new shape. Idempotent.

-- v0.9.53-dev (#200): OFFHAND APPLY-GATE state.
-- The offhand (shield) row writes _offhand_selection[bid] on a genuine cell
-- click (post-v0.9.52 is_held gate), and — before this build — committed that
-- pick to the LIVE keep weapon on screen exit even when the user never pressed
-- Apply (the user's "clicking a cosmetic without Apply still shows the illusion
-- after I leave the inventory" report). Vanilla's row-1 weapon-illusion grid
-- only commits via the Apply/craft button; the offhand row must match that
-- contract. We snapshot the offhand state that was equipped when the screen
-- opened (`_offhand_baseline[bid]`), flag a genuine Apply in the craft-complete
-- hooks (`_offhand_committed[bid]`), and on exit REVERT to the baseline when no
-- Apply committed (see on_exit). In-memory only; keyed by backend_id.
--   * _offhand_baseline[bid] == nil   -> no snapshot taken this session (e.g. a
--                                         no-offhand weapon) -> never revert.
--   * _offhand_baseline[bid] == false -> snapshot taken, was ABSENT -> revert to
--                                         nil (no override = base shield).
--   * _offhand_baseline[bid] == table -> revert to that per-hand selection.
-- Shallow per-hand copy: the opt records themselves come from the stable
-- _get_offhand_options pool, so copying the {hand_field -> opt} mapping is
-- enough to restore which option is selected per hand.

-- v0.8.64-dev: forward decl. Real impl lives in the cos_la_apply block below
-- (~line 3300). _on_offhand_index_pressed (~line 2004) and the local-equip
-- send sites in the CosmeticUtils hook need to call this; we forward-declare
-- so the closures capture the LOCAL slot rather than falling through to a
-- nil _G._send_la_apply.
local _send_la_apply
-- Track local player's currently-equipped LA cosmetics so hot_join_sync can
-- replay them to joining peers. Map: player_unit -> { slot_name -> la_backend_id }.
-- Populated from the CosmeticUtils.update_cosmetic_slot hook (which fires on
-- every local equip for slot_hat / slot_skin / slot_frame / slot_melee /
-- slot_ranged / slot_pose). Cleared on player_unit destruction is left as
-- future work — stale entries are harmless until the next equip overwrites.
local _local_la_equips = setmetatable({}, { __mode = "k" })

-- v0.8.55-dev: track the backend_id of the weapon currently being customized.
-- Pending weapon-skin rows omit backend_id. Keep the customization screen's
-- exact item identity for the policy-gated preview fallback, then clear on exit.
local _active_customization_backend_id = nil
mod._active_customization_item_type = nil

-- v0.9.41-dev (#150) `_in_create_equipment`: moved to _cos_equipment_assembly.lua
-- (#1159) together with the only two hooks that ever read or wrote it.

-- ============================================================
-- HeroWindowItemCustomization view lifecycle
--   -> _cos_customization_view_lifecycle.lua (#1159)
-- ============================================================
-- Mount-side #228 / #235 in-mission preview shading-environment guard and
-- exit-side screen teardown (clear active customization identity, close the glow
-- picker, #200 offhand apply-gate revert, deferred LA emit drain, pulse-wield).
-- Installed HERE, at the exact point that block previously executed, so hook
-- registration order is unchanged.
--
-- `_active_customization_backend_id` and `_send_la_apply` stay ENTRY-owned locals
-- and are reached through the accessors below rather than handed over by value:
-- `_send_la_apply` is only forward-declared at this point in the file (its real
-- assignment lives in the cos_la_apply block far below), so a by-value hand-off
-- would capture nil and silently kill the exit drain. The backend id is mutable
-- and written by _cos_offhand_picker too, so one slot must stay authoritative.
mod:dofile("scripts/mods/cosmetics_tweaker/_cos_customization_view_lifecycle").install(mod, {
    resource_residency = RESOURCE_RESIDENCY,
    local_player_safe = _local_player_safe,
    glow_picker = GlowPicker,
    la_persist = LA_PERSIST,
    offhand_commit = OFFHAND_COMMIT,
    offhand_session_state = _offhand_session_state,
    dbg = _dbg,
    dbg_alert = _dbg_alert,
    trace = _trace,
    get_send_la_apply = function() return _send_la_apply end,
    get_active_customization_backend_id = function()
        return _active_customization_backend_id
    end,
    set_active_customization_backend_id = function(value)
        _active_customization_backend_id = value
    end,
})

-- LA pool merge: each weapon_type pulls the LA shields whose `icons` table
-- specifically targets that weapon_type. The bridge does the icon-driven
-- bucketing; the merge here just appends each bucket to the matching
-- vanilla-offhand list. No cross-weapon-type leakage because each
-- _offhand_options[weapon_type] is now its own table (de-aliased above).
--
-- FOCUS GATE: legacy "one shield at a time" testing whitelist. Pre-v0.8.52
-- only the 3 entries below surfaced in the picker (Ostermark, Kotbs, Reiland)
-- while the rest of LA's registered shields stayed hidden. v0.8.52-dev opens
-- this fully — every LA shield whose `icons` table targets the current weapon
-- type now appears, scoped to the wielding character per the same-character
-- rule (each LA variant's icons are already character-correct, so the merge
-- preserves the rule).
--
-- To re-enable the focus filter for debugging, populate this table with the
-- armoury_keys you want exposed; an empty table = no filter (default now).
local _LA_FOCUS_KEYS = {}

local _la_offhand_merged = false

local function _merge_la_offhand_options()
    if _la_offhand_merged then return end
    if not LA_BRIDGE.registered then return end
    if type(LA_BRIDGE.la_offhand_options_by_weapon_type) ~= "table" then return end
    local has_focus, appended, duplicates = next(_LA_FOCUS_KEYS) ~= nil, 0, 0
    -- v0.9.9.4: per-hand structure — LA_BRIDGE.la_offhand_options_by_weapon_type
    -- is `[weapon_type][hand_field] = array_of_la_opts`.
    for weapon_key, la_hand_pools in pairs(LA_BRIDGE.la_offhand_options_by_weapon_type) do
        local hand_target = _offhand_options[weapon_key]
        if not hand_target then hand_target = {}; _offhand_options[weapon_key] = hand_target end
        for hand_field, la_pool in pairs(la_hand_pools) do
            local target = hand_target[hand_field]
            if not target then target = {}; hand_target[hand_field] = target end
            for _, la_opt in ipairs(la_pool) do
                if (not has_focus) or _LA_FOCUS_KEYS[la_opt.armoury_key] then
                    local candidate = {
                        name            = la_opt.name .. " (LA)",
                        la_armoury_key  = la_opt.armoury_key,
                        vanilla_skin    = la_opt.vanilla_skin,
                        target_item_type = la_opt.target_item_type or weapon_key,
                        -- mesh the LA texture was authored for; swapped in via
                        -- BackendUtils.get_item_units so LA paints onto the right
                        -- shield shape. nil for pure-paint variants, in which case
                        -- the user's existing shield mesh is preserved.
                        intended_unit   = la_opt.intended_unit,
                        authored_family = la_opt.authored_family,
                        variant_kind    = la_opt.variant_kind,
                        rarity          = "promo",
                        -- v0.9.9.1 REVERT: dropped la_opt.icon passthrough.
                    }
                    _decorate_shield_option(candidate); if OFFHAND_NAMES.merge_unique(target, candidate, hand_field) then appended = appended + 1 else duplicates = duplicates + 1 end
                end
            end
        end
    end
    _la_offhand_merged = true
    mod:info("[offhand] merged LA shield options (focus gate: %d keys, appended=%d duplicate_identity=%d)",
        (function() local n = 0; for _ in pairs(_LA_FOCUS_KEYS) do n = n + 1 end; return n end)(), appended, duplicates)
end

-- v0.9.71-dev: restore persisted offhand (shield) picks into
-- `_offhand_selection` once the LA bridge pools exist. Reconstructs the SAME
-- option record shape `_merge_la_offhand_options` builds (la_armoury_key /
-- vanilla_skin / intended_unit) by looking the armoury_key up in
-- LA_BRIDGE.la_offhand_options_by_weapon_type, so the local render path
-- (BackendUtils.get_item_units mesh override + LA paint) treats a restored
-- pick exactly like a fresh one. One-shot; arms the self-rebroadcast so
-- peers learn the restored picks through the normal emit flow.
mod._la_restore_offhand_selections = function()
    if mod._la_offhand_restore_done then return end
    if not (LA_PERSIST and LA_PERSIST.get_saved_offhands) then return end
    local restore_now = os.clock()
    if mod._la_offhand_restore_retry_at
            and restore_now < mod._la_offhand_restore_retry_at then return end
    mod._la_offhand_restore_retry_at = restore_now + 0.5
    mod._la_offhand_restore_deadline = mod._la_offhand_restore_deadline
        or (restore_now + 15)
    local saved = LA_PERSIST.get_saved_offhands()
    if not next(saved) then mod._la_offhand_restore_done = true return end
    local la_pools = LA_BRIDGE and LA_BRIDGE.registered
        and LA_BRIDGE.la_offhand_options_by_weapon_type or nil
    local needs_la, needs_item = false, false
    for _, hands in pairs(saved) do
        for _, rec in pairs(hands) do
            if rec and rec.armoury_key
                    and not (GK_SET and GK_SET.resolve_variant(rec.armoury_key)) then
                needs_la = true
            end
            if rec then needs_item = true end
        end
    end
    if needs_la and type(la_pools) ~= "table" then return end
    -- #695: avoid warning-producing get_interface calls before backend readiness.
    local backend_mgr = Managers and Managers.backend
    local backend_items = backend_mgr and backend_mgr._interfaces
        and backend_mgr._interfaces.items and backend_mgr:get_interface("items")
    if needs_item and not (backend_items and backend_items.get_item_from_id) then return end
    if get_mod("character_weapon_variants") and mod._discover_cwv_dual_offhand_pools then
        mod._discover_cwv_dual_offhand_pools()
    end
    -- #923: restoration is qualified by exact item type + hand + Armoury
    -- key. A first-hit global key index can restore a sibling target option.
    local by_target = mod._la_option_icon_policy.index_by_target(la_pools)
    -- Cosmetics-authored offhands live in the same persisted schema but do not
    -- require Loremaster's Armoury.  Rebuild them from the canonical component
    -- pools so a saved GK shield survives restart even when LA is absent.
    for item_type, hand_pools in pairs(_offhand_options) do
        for hand_field, pool in pairs(hand_pools) do
            for _, opt in ipairs(pool) do
                if opt.la_armoury_key and opt.cos_authored
                        and not mod._la_option_icon_policy.lookup(by_target, item_type,
                            hand_field, opt.la_armoury_key) then
                    by_target[item_type] = by_target[item_type] or {}
                    by_target[item_type][hand_field] =
                        by_target[item_type][hand_field] or {}
                    by_target[item_type][hand_field][opt.la_armoury_key] = {
                        name = opt.name,
                        armoury_key = opt.la_armoury_key,
                        vanilla_skin = opt.vanilla_skin,
                        intended_unit = opt.intended_unit,
                        authored_family = opt.authored_family,
                        variant_kind = opt.variant_kind,
                        inventory_icon = opt.inventory_icon,
                        cos_authored = true,
                    }
                end
            end
        end
    end
    local n, miss, deferred = 0, 0, 0
    for backend_id, hands in pairs(saved) do
        local ok_item, item = pcall(backend_items.get_item_from_id,
            backend_items, backend_id)
        local item_data = ok_item and item and (item.data
            or (item.key and ItemMasterList and rawget(ItemMasterList, item.key)))
        local item_type = item_data and item_data.item_type
        local exact_skin = ok_item and item and item.skin or nil
        if not exact_skin and ok_item and item and backend_items.get_skin then
            local ok_skin, backend_skin = pcall(backend_items.get_skin,
                backend_items, backend_id)
            if ok_skin then exact_skin = backend_skin end
        end
        local item_pending = not (ok_item and item)
            and restore_now < mod._la_offhand_restore_deadline
        for hand_field, rec in pairs(hands) do
            local la_opt = rec and rec.armoury_key
                and mod._la_option_icon_policy.lookup(by_target, item_type,
                    hand_field, rec.armoury_key)
            local mesh_opt = nil
            local this_deferred = item_pending
            if item_pending then deferred = deferred + 1 end
            if rec and type(rec.unit_path) == "string" and rec.unit_path ~= "" then
                -- Backend records can outlive salvaged items or removed CWV
                -- variants. Resolve defensively and accept only a unit still in
                -- this exact item's compatible hand pool.
                if ok_item and item then
                    local pools = item_type and mod._ensure_independent_dual_pool
                        and mod._ensure_independent_dual_pool(item_type)
                    local pool = pools and pools[hand_field]
                    local unit_fallback, unit_ambiguous = nil, false
                    for _, candidate in ipairs(pool or {}) do
                        if candidate.unit == rec.unit_path then
                            local component_key = candidate.skin_key
                                or candidate.source_skin_key
                            if rec.vanilla_key and component_key == rec.vanilla_key then
                                mesh_opt = candidate
                                break
                            elseif not unit_fallback then
                                unit_fallback = candidate
                            else
                                unit_ambiguous = true
                            end
                        end
                    end
                    if not mesh_opt and unit_fallback and not unit_ambiguous then
                        -- Legacy records may predate the component skin key.
                        -- A unique exact-unit hit remains deterministic.
                        mesh_opt = unit_fallback
                    end
                    if not mesh_opt and (not pool or #pool == 0)
                            and restore_now < mod._la_offhand_restore_deadline then
                        deferred = deferred + 1
                        this_deferred = true
                    end
                else
                    -- CIM can own an exact saved instance before its backend
                    -- mirror injection is available. Preserve that identity and
                    -- retry boundedly instead of consuming the one-shot restore.
                    local cim = get_mod("cim_dev") or get_mod("cim")
                    local pending_cim = cim and cim._cim_get_craft
                        and cim._cim_get_craft(backend_id) ~= nil
                    if not this_deferred and pending_cim
                            and restore_now < mod._la_offhand_restore_deadline then
                        deferred = deferred + 1
                        this_deferred = true
                    end
                end
            end
            if la_opt then
                local restored = {
                    name             = la_opt.name .. " (LA)",
                    la_armoury_key   = la_opt.armoury_key,
                    target_item_type = la_opt.target_item_type or item_type,
                    intended_unit    = la_opt.intended_unit,
                    authored_family  = la_opt.authored_family,
                    variant_kind     = la_opt.variant_kind,
                    inventory_icon   = la_opt.inventory_icon,
                    cos_authored     = la_opt.cos_authored == true,
                    rarity           = "promo",
                }
                if not restored.cos_authored then
                    local la_mod = get_mod("Loremasters-Armoury")
                    restored = mod._la_option_icon_policy.resolve_for_item(restored,
                        item_type, exact_skin,
                        la_mod and la_mod.SKIN_LIST,
                        LA_BRIDGE.normalize_weapon_type)
                end
                _offhand_selection[backend_id] = _offhand_selection[backend_id] or {}
                _offhand_selection[backend_id][hand_field] = restored
                if la_opt.intended_unit then _preload_offhand_package(la_opt.intended_unit) end
                n = n + 1
            elseif mesh_opt then
                _offhand_selection[backend_id] = _offhand_selection[backend_id] or {}
                _offhand_selection[backend_id][hand_field] = mesh_opt
                _preload_offhand_for_option(mesh_opt)
                n = n + 1
            elseif not this_deferred then
                miss = miss + 1
            end
        end
    end
    if n > 0 then
        -- Peers learn restored picks via the normal state-change re-emit walk
        -- (it reads _offhand_selection for equipped backend_ids).
        mod._la_self_rebroadcast_pending = true
    end
    mod._la_offhand_restore_done = deferred == 0
        or restore_now >= mod._la_offhand_restore_deadline
    if mod._la_offhand_restore_done then
        mod._la_offhand_restore_retry_at = nil
    end
    local summary = string.format("%d|%d|%d|%s", n, miss, deferred,
        tostring(mod._la_offhand_restore_done))
    if printf and summary ~= mod._la_offhand_restore_last_summary then
        mod._la_offhand_restore_last_summary = summary
        printf("[la-state] OFFHAND-RESTORE restored=%d unresolvable=%d deferred=%d done=%s",
            n, miss, deferred, tostring(mod._la_offhand_restore_done))
    end
end

local function _cos_ui_icon_available(icon)
    -- #650: tristate (ok, class) - "transient-ui" = shipped material resident
    -- (Application.can_get) but the VMF atlas injection not serving it yet.
    return COMPOSITE_ICON_FACTORY.ui_icon_availability(icon, UIAtlasHelper,
        Application and Application.can_get)
end

local function _cos_active_skin(item, backend_id)
    local skin = backend_id and LA_PERSIST
        and LA_PERSIST.get_saved_illusion(backend_id) or nil
    if not skin or skin == "" then skin = item and item.skin end
    local item_key = item and (item.key
        or (item.data and (item.data.name or item.data.key)))
    if (not skin or skin == "") and item_key and WeaponSkins
            and WeaponSkins.default_skins then
        skin = WeaponSkins.default_skins[item_key]
    end
    return skin
end

-- Shared #650 exact-instance appearance resolver. Icon publication and held
-- shield material application both consume this descriptor; neither surface
-- may independently infer primary glow or offhand compatibility.
_cos_resolve_composed_appearance = function(item, record, publish_for_icon)
    if type(item) ~= "table" then return nil end
    if publish_for_icon ~= false then COMPOSITE_ICONS.publish(item, nil) end
    local backend_id = item.backend_id or item.ItemInstanceId
    if backend_id == nil then return nil end
    local item_data = item.data or (item.key and ItemMasterList
        and rawget(ItemMasterList, item.key))
    local item_type = item_data and item_data.item_type
    local skin = _cos_active_skin(item, backend_id)
    if not skin then return nil end

    if record == nil and LA_PERSIST then
        local live = _offhand_selection[backend_id]
        local saved = LA_PERSIST.get_saved_offhands_for(backend_id)
        record = live and live.left_hand_unit
            or (saved and saved.left_hand_unit)
    end
    local offhand_unit = type(record) == "table"
        and (record.unit_path or record.unit or record.intended_unit) or nil
    local offhand_armoury_key = type(record) == "table"
        and (record.armoury_key or record.la_armoury_key) or nil
    if not offhand_unit and not offhand_armoury_key then
        local skin_record = WeaponSkins and WeaponSkins.skins
            and WeaponSkins.skins[skin]
        local skin_data = type(skin_record) == "table"
            and (skin_record.data or skin_record) or nil
        offhand_unit = skin_data and skin_data.left_hand_unit
    end
    local glow_state = GlowPicker.committed_state_for(backend_id, { skin = skin })
    local glow_source = glow_state and "committed" or nil
    if not glow_state then
        glow_state = GlowPicker.native_state_for({ skin = skin })
        if glow_state then glow_source = "native" end
    end
    local resolve_args = {
        backend_id = backend_id,
        exact_instance = true,
        item_type = item_type,
        skin = skin,
        offhand_unit = offhand_unit,
        offhand_armoury_key = offhand_armoury_key,
        glow_state = glow_state,
        glow_source = glow_source,
    }
    local descriptor, reason = COMPOSITE_ICONS.resolve_detailed(resolve_args)
    if descriptor and publish_for_icon ~= false then
        local ready, icon_reason = COMPOSITE_ICONS.icon_ready(
            descriptor, _cos_ui_icon_available)
        if not ready then
            descriptor = nil
            reason = icon_reason
        end
    end
    if COMPOSITE_ICONS.claim_diagnostic(reason, resolve_args) then
        mod:info("[cosmetics:650] descriptor %s bid=%s type=%s skin=%s offhand=%s armoury=%s glow=%s held=%s primary=%s shield=%s",
            tostring(reason), tostring(resolve_args.backend_id),
            tostring(resolve_args.item_type), tostring(resolve_args.skin),
            tostring(resolve_args.offhand_unit),
            tostring(resolve_args.offhand_armoury_key),
            tostring(resolve_args.glow_source),
            tostring(descriptor and descriptor.shield_glow
                and descriptor.shield_glow.variable),
            tostring(descriptor and descriptor.primary_texture),
            tostring(descriptor and descriptor.offhand_texture))
    end
    if publish_for_icon ~= false then COMPOSITE_ICONS.publish(item, descriptor) end
    return descriptor, reason
end

local function _cos_localized_name(key)
    if type(key) ~= "string" or key == "" then return nil end
    local L = rawget(_G, "Localize")
    if type(L) ~= "function" then return key end
    local ok, value = pcall(L, key)
    if ok and type(value) == "string" and value ~= ""
            and value ~= key and value ~= "<" .. key .. ">" then
        return value
    end
    return key
end

local function _cos_presentation_ownership(item_type)
    if mod._independent_dual_item_types
            and mod._independent_dual_item_types[item_type] then return "dual" end
    if _SHIELD_ICON_OWNER_ITEM_TYPES[item_type] then return "shield" end
    return nil
end

local function _cos_option_for_record(item, record, exact_skin)
    if type(record) ~= "table" then return nil end
    local item_data = item and (item.data or (item.key and ItemMasterList
        and rawget(ItemMasterList, item.key)))
    local item_type = item_data and item_data.item_type
    local pools = mod._ensure_independent_dual_pool
        and mod._ensure_independent_dual_pool(item_type) or _offhand_options[item_type]
    local option = OFFHAND_NAMES.match_option(record,
        pools and pools.left_hand_unit)
    if not option and record.name
            and (record.unit or record.intended_unit or record.la_armoury_key) then
        option = record
    end
    if not option then return nil end
    local external_la = option.la_armoury_key
        and option.cos_authored ~= true
    if external_la then
        local la_mod = get_mod("Loremasters-Armoury")
        option = mod._la_option_icon_policy.resolve_for_item(option, item_type,
            exact_skin or (item and item.skin), la_mod and la_mod.SKIN_LIST,
            LA_BRIDGE.normalize_weapon_type)
    end
    -- An external LA option may use a mesh shared by several weapon families.
    -- Once its exact (Armoury key, target type, skin) mapping rejects or misses,
    -- the native card is authoritative. Generic unit lookup would select a
    -- sibling family's authored icon and recreate #923.
    if not external_la and not option.inventory_icon
            and (option.unit or option.intended_unit) then
        local recovered = _inventory_icon_for_offhand_unit(
            option.unit or option.intended_unit, nil)
        if recovered then
            local copy = {}
            for key, value in pairs(option) do copy[key] = value end
            copy.inventory_icon = recovered
            option = copy
        end
    end
    return option
end

local function _cos_primary_component_name(item, display_name, ownership, saved_illusion)
    local fallback = _cos_localized_name(display_name)
    if ownership ~= "shield" then return fallback end
    local skin_key = saved_illusion or (item and item.skin)
    local skin = skin_key and WeaponSkins and WeaponSkins.skins
        and WeaponSkins.skins[skin_key]
    local data = type(skin) == "table" and (skin.data or skin) or nil
    local primary_unit = data and data.right_hand_unit
    if not primary_unit then return fallback end
    local records = {}
    for key, candidate in pairs(WeaponSkins.skins or {}) do
        local cdata = type(candidate) == "table" and (candidate.data or candidate) or nil
        if cdata and cdata.right_hand_unit == primary_unit and cdata.display_name then
            records[#records + 1] = {
                key = type(key) == "string" and key or candidate.name,
                primary_unit = primary_unit,
                name = _cos_localized_name(cdata.display_name),
                is_pair = cdata.left_hand_unit ~= nil,
            }
        end
    end
    return OFFHAND_NAMES.primary_name_for_unit(primary_unit, records) or fallback
end

local function _cos_publish_presentation_name(primary_name, secondary_name)
    local key, combined = OFFHAND_NAMES.presentation_key(primary_name, secondary_name)
    if not key then return nil end
    mod._cos.presentation_localization[key] = combined
    return key
end

local function _cos_resolve_presentation(item, base_icon, display_name,
        base_description, ownership, record, saved_illusion)
    local exact_skin = item and item.skin
        or (type(record) == "table"
            and (record.vanilla_skin or record.vanilla_key))
    local option = _cos_option_for_record(item, record, exact_skin)
    if not option then return base_icon, display_name, base_description, false end
    local primary = _cos_primary_component_name(item, display_name, ownership, saved_illusion)
    local descriptor = ITEM_PRESENTATION.resolve({
        base_icon = base_icon,
        primary_name = primary,
        secondary_option = option,
        ownership = ownership,
        local_resource_available = _cos_ui_icon_available,
    })
    if not descriptor.changed then return base_icon, display_name, base_description, false end
    local name_key = _cos_publish_presentation_name(
        descriptor.primary_name, descriptor.secondary_name)
    local description_key, description_text = OFFHAND_NAMES.description_presentation_key(
        descriptor.secondary_description)
    if description_key then mod._cos.presentation_localization[description_key] = description_text end
    return descriptor.icon, name_key or display_name,
        description_key or base_description, true
end

-- #376 exact-instance icon seam. Vanilla passes the full backend item into
-- UIUtils and resolves the first return from item.skin / WeaponSkins
-- (ui_utils.lua:219-260). LA's real authored icon lives instead at
-- SKIN_LIST[armoury_key].icons[vanilla_skin] (LA funcs.lua:103-110). Override
-- only that first return for a backend id with a persisted LA choice; never
-- mutate shared WeaponSkins/ItemMasterList tables (the v0.9.9.0 failure).
if UIUtils and type(UIUtils.get_ui_information_from_item) == "function" then
    mod:hook(UIUtils, "get_ui_information_from_item", function(func, item)
        local inventory_icon, display_name, description, store_icon = func(item)
        if item and item._cos_presentation_display_name then
            display_name = item._cos_presentation_display_name
        end
        local backend_id = item and (item.backend_id or item.ItemInstanceId)
        if backend_id and mod._la_instance_policy and LA_PERSIST then
            local la = get_mod("Loremasters-Armoury")
            local item_data = item.data or (item.key and ItemMasterList
                and rawget(ItemMasterList, item.key))
            local item_type = item_data and item_data.item_type
            local ownership
            if mod._independent_dual_item_types
                    and mod._independent_dual_item_types[item_type] then
                ownership = "dual"
            elseif _SHIELD_ICON_OWNER_ITEM_TYPES[item_type] then
                ownership = "shield"
            end
            local saved_offhands = LA_PERSIST.get_saved_offhands_for(backend_id)
            local saved_left = saved_offhands and saved_offhands.left_hand_unit
            -- Records authored before icon ownership was introduced only
            -- persisted the exact mesh path. Derive presentation metadata on
            -- read without mutating the persistence module's read-only table.
            if ownership == "shield" and type(saved_left) == "table"
                    and not saved_left.armoury_key and not saved_left.inventory_icon
                    and saved_left.unit_path then
                local recovered_icon = _inventory_icon_for_offhand_unit(
                    saved_left.unit_path, item_data and item_data.template)
                if recovered_icon then
                    local recovered_left = {}
                    for key, value in pairs(saved_left) do recovered_left[key] = value end
                    recovered_left.inventory_icon = recovered_icon
                    saved_offhands = { left_hand_unit = recovered_left }
                end
            end
            local saved_illusion = LA_PERSIST.get_saved_illusion(backend_id)
            local icon = mod._la_icon_provider.resolve(item, saved_illusion, saved_offhands,
                LA_BRIDGE and LA_BRIDGE.backend_to_armoury,
                LA_BRIDGE and LA_BRIDGE.backend_to_vanilla,
                la and la.SKIN_LIST,
                ownership)
            if icon then inventory_icon = icon end
            _offhand_session_state.migrate_legacy(backend_id)
            local live_hands = _offhand_selection[backend_id]
            local record = live_hands and live_hands.left_hand_unit
                or (saved_offhands and saved_offhands.left_hand_unit)
            inventory_icon, display_name, description = _cos_resolve_presentation(item,
                inventory_icon, display_name, description, ownership, record,
                saved_illusion)
            -- Publish for the exact ItemGrid cell only. UIUtils also feeds
            -- crafting and Hold-Tab, whose widgets do not own the shield/glow
            -- passes; their returned vanilla/owned icon must stay unchanged.
            _cos_resolve_composed_appearance(item, record)
        end
        return inventory_icon, display_name, description, store_icon
    end)
end

-- #925: extracted retained-card refresh/publisher; callers compose singleton seams.
mod:dofile("scripts/mods/cosmetics_tweaker/_cos_ui_presentation_refresh").install(mod, {
    la_bridge = LA_BRIDGE, rt_register = _rt_register,
})

local function _get_offhand_options(item_key)
    if mod._ensure_independent_dual_pool then
        mod._ensure_independent_dual_pool(item_key)
    end
    return _offhand_options[item_key]
end

-- Receiver-side compatibility boundary for #583. A stale or malformed direct
-- mesh payload may only override a registered dual hand when that exact unit is
-- still present in that item type's compatible pool. Unknown/non-dual types
-- retain the older shield/LA behavior.
mod._dual_offhand_unit_allowed = function(item_type, hand_field, unit_path)
    if not (mod._independent_dual_item_types
            and mod._independent_dual_item_types[item_type]) then
        return true
    end
    if hand_field ~= "left_hand_unit" then return false end
    local pools = mod._ensure_independent_dual_pool(item_type)
    local pool = pools and pools[hand_field]
    for _, opt in ipairs(pool or {}) do
        if opt.unit == unit_path and unit_path ~= "" then return true end
    end
    return false
end

mod:command("la_offhand_dump", "Dump LA offhand variant -> intended_unit resolution", function()
    if LA_BRIDGE and LA_BRIDGE.dump_offhand_resolution then
        LA_BRIDGE.dump_offhand_resolution()
    else
        mod:echo("[LA bridge] dump_offhand_resolution unavailable")
    end
end)

mod:command("offhand_debug", "Dump offhand system state", function()
    mod:echo("[offhand] _offhand_options (item_type -> hand_field -> pool size):")
    for k, hand_pools in pairs(_offhand_options) do
        for hand, pool in pairs(hand_pools) do
            mod:echo("  %s/%s -> %d options", k, hand, #pool)
        end
    end
    mod:echo("[offhand] _offhand_selection (bid -> hand -> sel):")
    for k, per_hand in pairs(_offhand_selection) do
        if type(per_hand) == "table" then
            for hand, v in pairs(per_hand) do
                if type(v) == "table" then
                    local label = v.la_armoury_key and ("LA:" .. v.la_armoury_key) or tostring(v.unit)
                    mod:echo("  %s/%s -> %s", k, hand, label)
                end
            end
        end
    end
    mod:echo("[offhand] BackendUtils hooked: %s", tostring(BackendUtils ~= nil))
    mod:echo("[offhand] UIWidget available: %s", tostring(UIWidget ~= nil))
    mod:echo("[offhand] UIWidgets available: %s", tostring(UIWidgets ~= nil))
    mod:echo("[offhand] UIRenderer available: %s", tostring(UIRenderer ~= nil))
    mod:echo("[offhand] Colors available: %s", tostring(Colors ~= nil))
end)

-- The deferred bulk loader now lives in `_cos_offhand_catalog.lua`; the
-- entry-owned update loop invokes its returned function after LA bridge init.
--
-- Why this exists: when HOST picks a cross-character shield (e.g.
-- `wpn_emp_gk_shield_03` "GK Shield Blue" via the offhand picker, or equips
-- the CT custom illusion `ct_es_mace_gk_shield_01` which also uses
-- shield_03 as left_hand_unit), the CLIENT receives vanilla skin
-- propagation. Client's `SimpleHuskInventoryExtension._wield_slot` calls
-- `BackendUtils.get_item_units(item_data, nil, slot.skin, career_name)`,
-- gets shield_03's path back, then `GearUtils.spawn_inventory_unit` →
-- `unit_spawner:spawn_local_unit_with_extensions` → engine `spawn_unit`.
-- shield_03's package WAS NOT preloaded on the client — ProfileSynchronizer
-- starts an async load when peer profiles sync but it races the synchronous
-- wield RPC and loses. Result: engine spawn_unit crash, PC-B fell out of the
-- session 2026-05-19. Identical mechanism to weapon_tweaker's brace-repeater
-- crash (feedback_cwv_cross_character_unit_packages.md).
--
-- Fix: enumerate every unit_path the user might equip via CT (offhand pools
-- + custom illusions) and queue an async load at boot on EVERY peer.
-- _preload_offhand_package is idempotent via the _preloaded_offhand_packages
-- set, so re-calls are cheap.

local _cos_offhand_picker = mod:dofile(
    "scripts/mods/cosmetics_tweaker/_cos_offhand_picker").install(mod, {
    magic_skin_gateway = MAGIC_SKIN_GATEWAY,
    create_glow_editor_button = _create_glow_editor_button,
    refresh_glow_editor_button = _refresh_glow_editor_button,
    refresh_illusion_glow_badges = _refresh_illusion_glow_badges,
    set_active_customization_backend_id = function(value)
        _active_customization_backend_id = value
    end,
    get_offhand_options = _get_offhand_options,
    multi_mount_item_types = _MULTI_MOUNT_ITEM_TYPES,
    offhand_session_state = _offhand_session_state,
    offhand_selection = _offhand_selection,
    preload_offhand_for_option = _preload_offhand_for_option,
    source_illusion_name = _source_illusion_name,
    offhand_names = OFFHAND_NAMES,
    glow_picker = GlowPicker,
    la_bridge = LA_BRIDGE,
    local_player_safe = _local_player_safe,
    shield_icon_owner_item_types = _SHIELD_ICON_OWNER_ITEM_TYPES,
    inventory_icon_for_offhand_unit = _inventory_icon_for_offhand_unit,
    dbg = _dbg,
    trace = _trace,
    get_managers = function() return Managers end,
    get_weapon_skins = function() return WeaponSkins end,
    get_item_master_list = function() return ItemMasterList end,
    get_ui_widget = function() return UIWidget end,
    get_ui_renderer = function() return UIRenderer end,
    get_local_require = function() return local_require end,
    hero_window_item_customization = HeroWindowItemCustomization,
    la_option_icon_policy = mod._la_option_icon_policy,
})

-- CLARIFY: BackendUtils is a plain table, not a class. The string-form
-- hook (`mod:hook("BackendUtils", ...)`) cannot resolve it because VMF's
-- string resolution looks for class names in the loaded class table.
-- Must use TABLE-form hook with a nil guard. The nil guard handles boot
-- order — at module-load time BackendUtils may not exist yet on every
-- VT2 build. CLAUDE.md "Hooking" section.
-- v0.9.0.6-hotfix: husk-wield context. SimpleHuskInventoryExtension._wield_slot
-- (wrapped below) sets this before calling BackendUtils.get_item_units and
-- clears it after. The get_item_units hook reads it to decide whether to
-- override left_hand_unit for kind="unit" LA mesh swaps on remote husks.
-- Lua main thread is single-threaded so the set→get→clear bracket is safe.
local _current_husk_wield = nil
-- v0.9.0.11-hotfix: FORWARD DECLARATION. The real assignment lives at the
-- old declaration site below (line ~3711). Without this forward decl, the
-- BackendUtils.get_item_units hook (registered immediately below) would
-- reference `_la_equips_by_peer` as a GLOBAL (nil) — the actual local
-- declaration is much later in the file. v0.9.0.10 burned: the husk-mesh-
-- swap probe always logged cache_has_wearer=false even after the recv
-- handler had populated the cache, because the receiver captured the
-- real local but the probe captured the global. Declaring here gives every
-- subsequent reference (probe + receiver + wraps) the same upvalue.
local _la_equips_by_peer = {}

-- v0.9.82-dev (#416): parallel synced store for VANILLA offhand meshes -- per-hand
-- shield / held-weapon unit picks (opt.unit / opt.intended_unit) that carry NO LA
-- armoury_key. Keyed [wearer_peer][slot_or_template][hand_field] = unit_path. Kept
-- SEPARATE from _la_equips_by_peer so the LA reconcile / paint / hot-join machinery
-- (all armoury-key-centric) stays byte-for-byte untouched; the husk get_item_units
-- branch reads BOTH stores. Populated only by the cos_la_apply `offhand_unit` branch,
-- a VMF mod RPC that non-mod peers never receive -- so this cannot ride a vanilla RPC
-- into a non-mod peer's NetworkLookup (the #421 wire-safety floor is a separate axis,
-- untouched here). Attached to `mod` (main chunk is near the Lua 200-local ceiling).
mod._offhand_mesh_by_peer = mod._offhand_mesh_by_peer or {}

-- #518: DEUS-YIELD gate. In an active Chaos Wastes expedition mission every
-- weapon slot holds a
-- deus-GENERATED instance: generation rolls item.skin per rarity
-- (deus_weapon_generation.lua:246-249) and every shrine upgrade RE-rolls it at the
-- target rarity (:318-321) from WeaponSkins.skin_combinations - the skin change IS
-- the upgrade's visual feedback. Our LA/vanilla offhand overrides are stored per
-- KEEP weapon instance (backend_id) PLUS a template-key namespace, and deus items
-- clone the base item (create_item sets key = deus_item_data.base_item, same
-- weapon template - deus_weapon_generation.lua:185-202), so a keep pick leaked
-- onto every CW starting/upgraded weapon and stomped the rolled skin on every
-- wield (issue #518 log: "LOCAL wield-reapply stored_key=
-- one_handed_sword_shield_template_2" repeating during SPAWN mechanism=deus).
-- PRECEDENCE: CW upgrade cosmetics WIN only in an active expedition mission.
-- The deus mechanism also owns the Pilgrimage Chamber (game mode "inn_deus")
-- and route/shrine map ("map_deus"); only mission nodes use game mode "deus"
-- (deus_mechanism.lua:28-35,730-744; deus_node_settings.lua:3-22). LA must stay
-- live in those staging/map contexts. The gate reads both values on every call
-- and the synced stores stay warm, so returning to a hub re-enables rendering
-- without state loss. WEAPON-side only: hats/armor (kind="hat"/"armor") are the
-- player's real backend cosmetics, persist through CW, and are never gated.
-- Helpers are attached to `mod` (main chunk is near the Lua 200-local ceiling).
mod._la_weapon_yield_for_context = function(mechanism_name, game_mode_key)
    return mechanism_name == "deus" and game_mode_key == "deus"
end

mod._la_deus_weapon_yield = function()
    local mm = Managers and Managers.mechanism
    if not (mm and mm.current_mechanism_name) then return false end
    local mechanism_ok, mechanism_name = pcall(mm.current_mechanism_name, mm)
    if not mechanism_ok or mechanism_name ~= "deus" then return false end

    -- Prefer the live manager (`GameModeManager.game_mode_key`, source :915-917).
    -- During early equipment creation it may not exist yet, so fall back to the
    -- promoted transition data (`LevelTransitionHandler.get_current_game_mode`,
    -- source :387-389). Both report inn_deus/map_deus/deus using the node table.
    local game_mode_key
    local gm = Managers and Managers.state and Managers.state.game_mode
    if gm and gm.game_mode_key then
        local ok, value = pcall(gm.game_mode_key, gm)
        if ok then game_mode_key = value end
    end
    local lth = Managers and Managers.level_transition_handler
    if not game_mode_key then
        if lth and lth.get_current_game_mode then
            local ok, value = pcall(lth.get_current_game_mode, lth)
            if ok then game_mode_key = value end
        end
    end
    if not game_mode_key and lth and lth.get_current_level_key then
        -- Last early-load fallback. Vanilla's level classifier reserves only
        -- morris_hub and dlc_morris_map; every other deus level is an ingame
        -- node (deus_mechanism.lua:49-59). This keeps the fail direction safe:
        -- staging never yields, while a mission cannot briefly repaint LA over
        -- its rolled skin merely because GameModeManager is still starting.
        local ok, level_key = pcall(lth.get_current_level_key, lth)
        if ok and level_key == "morris_hub" then
            game_mode_key = "inn_deus"
        elseif ok and level_key == "dlc_morris_map" then
            game_mode_key = "map_deus"
        elseif ok and level_key then
            game_mode_key = "deus"
        end
    end

    local should_yield = mod._la_weapon_yield_for_context(mechanism_name, game_mode_key)
    if not should_yield and printf then
        mod._la_deus_context_seen = mod._la_deus_context_seen or {}
        local seen_key = tostring(mechanism_name) .. "/" .. tostring(game_mode_key)
        if not mod._la_deus_context_seen[seen_key] then
            mod._la_deus_context_seen[seen_key] = true
            printf("[la-state] DEUS-YIELD bypass mechanism=%s game_mode=%s (LA weapon cosmetics remain live)",
                tostring(mechanism_name), tostring(game_mode_key))
        end
    end
    return should_yield
end

mod:dofile("scripts/mods/cosmetics_tweaker/_cos_518_probe") -- #518 bounded solo-visible probes: printf-only emitter + owner-wield / paint-skip helpers wired below, plus the husk-miss helper the equipment-assembly owner calls (#1159)

-- ============================================================
-- Live equipment assembly seam
--   -> _cos_equipment_assembly.lua (#1159)
-- ============================================================
-- The BackendUtils.get_item_units unit-table rewrite used to register HERE: the
-- #513 score-screen LA hat mesh swap, the husk LA mesh swap, the #416 husk
-- vanilla per-hand mesh swap, and the per-backend-id offhand selection override.
-- It moved to the owner together with the GearUtils.create_equipment wrap that
-- brackets it, because the `_in_create_equipment` flag those two share (#150) has
-- no other reader or writer. The owner installs at the create_equipment position
-- below; only comments, two mod:command registrations and plain local function
-- declarations sit between the two former sites, so no hook registers in between
-- and the mod-wide hook order is unchanged.

-- Render-path scale helpers (_is_unit, _resolve_for_career,
-- _resolve_render_unit_path, _resolve_factor, _apply_unit_path_scale_hand,
-- _scale_units) moved to _cos_render.lua (v0.9.78-dev Phase 2 OOP split).
-- _is_unit is aliased locally in the manifest block above (glow still uses it);
-- the apply helpers are called from the render hooks below via mod._cos.*.

-- Glow apply subsystem moved to _cos_glow.lua (v0.9.79-dev Phase 3 OOP split):
-- the color presets, the shader-variable brightness/group maps, the per-peer glow
-- read helpers, _glow_owner_peer_for_unit, _apply_glow_to_unit / _apply_glow_override,
-- mod._reapply_glow_on_wielded, the template-mutation apply hook on
-- GearUtils/CosmeticUtils/_G.apply_material_settings, and the _cosmetics_tweaker_glow
-- MaterialSettingsTemplate + its GearUtils.spawn_inventory_unit injection hook. The
-- three render hooks below call mod._cos.apply_glow_override /
-- mod._cos.glow_owner_peer_for_unit. What STAYS in this file: the /glow_status +
-- /glow_trace commands below and combined LA/glow state-snapshot bookkeeping (which
-- reads mod._glow_by_peer via the entry-local alias set in the manifest). The glow
-- send/register transport itself is owned by _cos_glow_transport.lua.

mod:command("glow_status", "Report glow hook health and per-hook call counts since session start", function()
    -- v0.9.37-dev: the global "Weapon Glow Override" VMF menu was removed; glow
    -- is now driven by the per-item Glow Picker popup. `glow_override_enable` /
    -- `glow_override_preset` no longer exist as settings (mod:get → nil), so the
    -- old enable/preset echo was dropped. This command now reports apply-hook
    -- health (still load-bearing — the Glow Picker's per-item paint flows through
    -- the same _apply_glow_to_unit pipeline) and the Glow Picker open state.
    local trace = mod:get("glow_trace")
    mod:echo(string.format("[glow_status] trace=%s picker_open=%s",
        tostring(trace), tostring(GlowPicker and GlowPicker.is_open and GlowPicker.is_open())))
    for _, label in ipairs({ "gear", "flow", "cosmetic" }) do
        mod:echo(string.format("[glow_status] hook[%s] installed=%s calls_this_session=%d",
            label,
            tostring(mod._glow_hooks_installed[label]),
            mod._glow_call_counts[label] or 0))
    end
end)

mod:command("glow_trace", "Toggle per-call glow trace logging (on/off). No arg toggles; pass 1/0 to set.", function(arg)
    local current = mod:get("glow_trace") and true or false
    local new_value
    if arg == nil or arg == "" then
        new_value = not current
    else
        new_value = (arg == "1" or arg == "on" or arg == "true")
    end
    mod:set("glow_trace", new_value)
    mod:echo(string.format("[glow_trace] now %s", new_value and "ON" or "OFF"))
end)

-- Live re-paint REMOVED in v0.8.10-dev. Earlier `mod._refresh_glow` walked
-- ScriptUnit.extension(player_unit, "inventory_system")._equipment.slots and
-- painted every right_unit_1p / right_unit_3p / left_unit_1p / left_unit_3p.
-- That worked for the wielded slot but destabilized adjacent units: pressing
-- X (inspect) afterwards made hand meshes disappear and 1P state break, only
-- recoverable by switching characters. Root cause not pinned — likely the
-- engine doesn't tolerate set_vector3_for_materials on currently-invisible
-- (sheathed) 1P units. To re-add live updates, hook the wield event and
-- paint only the weapon at the moment it becomes visible. For now: changing
-- the override or preset takes effect on the NEXT weapon equip / spawn via
-- the apply_material_settings hook above.

-- _offset_units (grip-offset apply) moved to _cos_render.lua (v0.9.78-dev
-- Phase 2 OOP split); the in-game render hook below calls mod._cos.offset_units.

local function _local_career_name()
    local pm = Managers.player
    if not pm then return nil end
    local pl = _local_player_safe(pm)
    if not pl then return nil end
    local ok, name = pcall(pl.career_name, pl)
    return ok and name or nil
end

-- Resolve a weapon's item_type, walking weapon_skin -> matching weapon if needed.
local function _resolve_item_type(item_data)
    if not item_data then return nil end
    local item_type = item_data.item_type
    if item_type == "weapon_skin" and item_data.matching_item_key and ItemMasterList then
        local wd = rawget(ItemMasterList, item_data.matching_item_key)
        if wd then item_type = wd.item_type end
    end
    return item_type
end

-- If an LA offhand is selected for the given weapon item_type, paint LA
-- heraldic textures onto each provided shield unit. Vanilla offhand
-- selections (with `unit` set) are handled earlier in get_item_units;
-- LA selections are handled here, after the vanilla shield unit spawned.
--
-- `has_skin` MUST be true (a non-empty skin key/equipped illusion) — the
-- paint is gated to skinned items only, mirroring the BackendUtils.get_item_units
-- override gate. Painting the base weapon template would surprise users
-- ("base template can't have illusions applied").
-- Is it safe to paint this LA heraldry onto unit `u`? Whenever the variant
-- declares `new_units`, the spawned unit's authored mesh must be that exact 1P
-- or 3P member. This applies to both custom-unit variants and texture variants
-- which select a particular vanilla mesh. Pure-paint texture variants have no
-- declared unit and are kept safe by the authored-family pool policy.
-- Loot previewers pass the exact queued spawn_data unit path.  That evidence
-- takes precedence over runtime unit metadata and fails closed if it is absent
-- or mismatched. Other established render paths retain their runtime check.
local function _offhand_paint_mesh_ok(u, armoury_key, proven_unit_path)
    local variant = _resolve_authored_offhand_variant(armoury_key)
    if not variant then return true end
    if proven_unit_path ~= nil and variant.new_units then
        return mod._la_instance_policy.preview_target_matches(
            proven_unit_path, variant)
    end
    local actual = _unit_mesh_name(u)
    if actual == "<no-unit_name>" or actual == "<not-unit>" then return true end
    -- #373: an exact magic->base receiver mapping means this live magic unit
    -- cannot accept LA's diffuse paint. Refuse the no-op paint until the bounded
    -- wield pulse respawns the same-family receiver.
    if not variant.new_units then
        return LA_BRIDGE.resolve_texture_receiver(armoury_key, actual) == nil
    end
    return actual == tostring(variant.new_units[1])
        or (variant.new_units[2] ~= nil and actual == tostring(variant.new_units[2]))
end

-- One paint entry point for every authored offhand component.  Cosmetics owns
-- its own texture resources; Loremaster's bridge owns LA material semantics.
-- Callers never need to know which provider authored the selected row.
local function _apply_authored_offhand_to_unit(world, unit, armoury_key,
        vanilla_skin, context)
    local authored = GK_SET and GK_SET.resolve_variant(armoury_key)
    if authored then
        return GK_SET.apply_variant_to_unit(authored, unit, context)
    end
    return LA_BRIDGE.apply_offhand_to_unit(
        world, unit, armoury_key, vanilla_skin, context)
end

local function _apply_la_offhand_to_units(world, item_data, units, has_skin,
        backend_id_arg, context, proven_unit_paths)
    if not LA_BRIDGE.registered then _dbg("[LA paint] skip: authored bridge not registered"); return false end
    if not world or not item_data then _dbg("[LA paint] skip: world/item_data nil"); return false end
    if not has_skin then _dbg("[LA paint] skip: has_skin=false"); return false end
    -- v0.8.32: read selection by backend_id. Resolve from arg first, then
    -- from item_data.backend_id (vanilla stamps this on equipment resync).
    local bid = backend_id_arg or (item_data and item_data.backend_id)
    if not bid then _dbg("[LA paint] skip: no backend_id"); return false end
    -- v0.9.41-dev (#150): suppress the browse-time LA texture paint on the LIVE
    -- in-keep / in-mission body while the customization screen is open for this
    -- item. Mirrors the get_item_units mesh-override suppression: only the loot
    -- previewer shows the in-progress pick; the live body refreshes on screen
    -- exit (pulse-wield). "ingame" is the create_equipment path; the preview
    -- contexts ("loot_previewer"/"hero_previewer") are untouched. Missions are
    -- unaffected (screen closed → _active_customization_backend_id is nil).
    if context == "ingame" and _active_customization_backend_id ~= nil
        and bid == _active_customization_backend_id then
        _dbg("[LA paint] suppress ingame browse-paint for bid=%s (customization screen open)", tostring(bid))
        return false
    end
    -- #518: deus run - the rolled rarity/upgrade skin owns the live body's
    -- weapon visuals; skip the in-game LA offhand paint. Preview contexts
    -- (loot_previewer / hero_previewer render the KEEP instance) stay live.
    if context == "ingame" and mod._la_deus_weapon_yield() then
        _dbg("[LA paint] skip: deus run - CW upgrade cosmetics win (#518) bid=%s", tostring(bid)); mod._cos518_paint_skip(bid) -- #518 printf
        return false
    end
    _offhand_session_state.migrate_legacy(bid)
    local per_hand_sel = _offhand_selection[bid]
    if type(per_hand_sel) ~= "table" then
        _dbg("[LA paint] skip: no _offhand_selection for backend_id=%s", tostring(bid)); return false
    end
    -- v0.9.9.4-dev: caller passes the units it has spawned. LA paints are
    -- texture-only and idempotent across all matching unit meshes — we
    -- paint EVERY selection (any hand_field) onto EVERY passed unit. The
    -- callers below restrict `units` to the appropriate hand (e.g. ingame
    -- passes left_unit_3p/1p; loot previewer passes index 1 = left). For
    -- multi-mount weapons with LA picks on both hands the paint runs once
    -- per hand selection on whichever units the caller supplied.
    local painted = false
    local component_claimed = false
    local item_type = _resolve_item_type(item_data)
    local hand_pools = item_type and _get_offhand_options(item_type)
    for hand_field, sel in pairs(per_hand_sel) do
        local pool = hand_pools and hand_pools[hand_field]
        if type(sel) == "table" then component_claimed = true end
        if type(sel) == "table" and sel.la_armoury_key
            and mod._la_instance_policy.selection_owned(sel, pool) then
            _dbg("[LA paint] painting %s (%s) on %d units (backend_id=%s)",
                tostring(sel.la_armoury_key), hand_field, #units, tostring(bid))
            for unit_index, u in ipairs(units) do
                if u and _is_unit(u) then
                    -- v0.9.45-dev (BUG 1/2): on the LIVE in-keep / in-mission body
                    -- ("ingame") the kind="unit" mesh override can be skipped
                    -- (readiness / package-load timing) leaving the VANILLA shield
                    -- mesh (e.g. the bret heater) in hand. Painting the LA imperial
                    -- heraldry onto that un-swapped mesh is exactly the warped
                    -- imperial-texture-on-bret-mesh symptom. Refuse to paint when
                    -- the target unit's authored mesh is NOT the variant's custom
                    -- mesh.
                    -- v0.9.53-dev (#200): EXTENDED the gate from "ingame"-only to
                    -- every non-husk context (ingame + loot_previewer +
                    -- hero_previewer). This is symptom B of the user's report —
                    -- "textures wrapped around the WRONG model when previewing a
                    -- DIFFERENT model": cycling row-1 weapon illusions re-spawns the
                    -- previewer with the NEW illusion's paired shield mesh, but the
                    -- stale _offhand_selection still paints the kind="unit" LA
                    -- heraldry onto it. Gating the previewer contexts on the same
                    -- mesh-match check stops the warp without regressing the correct
                    -- case: when the previewer DID spawn the LA mesh the gate passes
                    -- (mesh matches) and the paint proceeds; when the mesh is
                    -- unreadable (<no-unit_name>), LootItemUnitPreviewer supplies its
                    -- exact queued spawn_data path and the gate fails closed on an
                    -- absent/mismatched target. The husk path ("network_husk") still
                    -- always mesh-swaps first, so it is NOT gated. Non-fatal (mesh
                    -- read is pcall-guarded in _unit_mesh_name).
                    if context ~= "network_husk"
                        and not _offhand_paint_mesh_ok(u, sel.la_armoury_key,
                            proven_unit_paths and proven_unit_paths[unit_index]) then
                        _dbg("[LA paint]   SKIP unit=%s key=%s ctx=%s — mesh is NOT the swapped LA mesh; refusing to warp heraldry onto mismatched shield",
                            tostring(u), tostring(sel.la_armoury_key), tostring(context))
                        -- _trace_paint routes through mod:info (visible with
                        -- output_mode_debug OFF) and carries the [cos:weapon-leak]-
                        -- relevant SKIP-mesh-mismatch provenance line.
                        _trace_paint(context, context, bid, u, sel.la_armoury_key, "SKIP-mesh-mismatch")
                        if PROBE then
                            PROBE.emit("cos:sync",
                                "offhand_gate/" .. tostring(context) .. "/" .. tostring(sel.la_armoury_key) .. "/" .. tostring(u),
                                string.format("peer=local ctx=%s key=%s unit=%s decision=SKIP reason=mesh-mismatch(warp-guard)",
                                    tostring(context), tostring(sel.la_armoury_key), tostring(u)))
                        end
                    else
                    local ok = _apply_authored_offhand_to_unit(
                        world, u, sel.la_armoury_key, sel.vanilla_skin, context)
                    _dbg("[LA paint]   unit=%s ok=%s", tostring(u), tostring(ok))
                    if PROBE then
                        PROBE.emit("cos:sync",
                            "offhand_gate/" .. tostring(context) .. "/" .. tostring(sel.la_armoury_key) .. "/" .. tostring(u),
                            string.format("peer=local ctx=%s key=%s unit=%s decision=PAINT outcome=%s",
                                tostring(context), tostring(sel.la_armoury_key), tostring(u), tostring(ok)))
                    end
                    -- v0.9.43-dev PAINT trace (full provenance). site == context
                    -- (loot_previewer / ingame / hero_previewer). match=false here
                    -- is the smoking gun: imperial texture painted onto a unit
                    -- whose mesh is still the bret shield (mesh override didn't
                    -- swap on this path). See _trace_paint.
                    _trace_paint(context, context, bid, u, sel.la_armoury_key, ok)
                    end
                end
            end
            painted = true
        elseif type(sel) == "table" and sel.la_armoury_key then
            _trace("PAINT selection rejected bid=%s item_type=%s hand=%s ctx=%s reason=foreign-selection",
                tostring(bid), tostring(item_type), tostring(hand_field),
                tostring(context))
        end
    end
    return component_claimed, painted
end

-- In-game keep / mission body + the item unit-table resolution it brackets.
-- THREE RENDERING PATHS COVERAGE:
--   - In-game (GearUtils.create_equipment): _cos_equipment_assembly.lua
--   - Inventory previewer (HeroPreviewer._spawn_item): _cos_preview_runtime.lua
--   - Illusion browser (LootItemUnitPreviewer.spawn_units): _cos_preview_runtime.lua
--
-- `_current_husk_wield` and `_active_customization_backend_id` stay ENTRY-owned
-- locals reached through the accessors below, never handed over by value: the
-- husk _wield_slot wrap rebinds the first stack-style on every husk wield, and
-- the second is written by both the view-lifecycle owner and the offhand picker.
mod:dofile("scripts/mods/cosmetics_tweaker/_cos_equipment_assembly").install(mod, {
    gk_set = GK_SET,
    glow_picker = GlowPicker,
    la_bridge = LA_BRIDGE,
    mh_embed = MH_EMBED,
    probe = PROBE,
    apply_la_offhand_to_units = _apply_la_offhand_to_units,
    glow_log = _cos574_log,
    resolve_composed_appearance = _cos_resolve_composed_appearance,
    dbg = _dbg,
    trace = _trace,
    get_offhand_options = _get_offhand_options,
    la_equips_by_peer = _la_equips_by_peer,
    offhand_selection = _offhand_selection,
    offhand_session_state = _offhand_session_state,
    override_package_ready = _override_package_ready,
    resolve_authored_offhand_mesh = _resolve_authored_offhand_mesh,
    resolve_authored_offhand_variant = _resolve_authored_offhand_variant,
    get_current_husk_wield = function() return _current_husk_wield end,
    get_active_customization_backend_id = function()
        return _active_customization_backend_id
    end,
})

-- Preview-only lifecycle/spawn/score owner. Keep this ordered boundary after
-- the shared render helpers and before LA bridge initialization.
mod:dofile("scripts/mods/cosmetics_tweaker/_cos_preview_runtime").install(mod, {
    la_bridge = LA_BRIDGE,
    custom_hats = CUSTOM_HATS,
    score_identity = SCORE_IDENTITY,
    gk_set = GK_SET,
    glow_preview_policy = GLOW_PREVIEW_POLICY,
    glow_picker = GlowPicker,
    dbg = _dbg,
    dbg_alert = _dbg_alert,
    local_player_safe = _local_player_safe,
    apply_la_offhand_to_units = _apply_la_offhand_to_units,
    offhand_paint_mesh_ok = _offhand_paint_mesh_ok,
    resolve_item_type = _resolve_item_type,
    resolve_composed_appearance = _cos_resolve_composed_appearance,
    glow_log = _cos574_log,
    get_active_customization_backend_id = function()
        return _active_customization_backend_id
    end,
    get_mod = get_mod,
})

-- ============================================================
-- LA loadout state + the two vanilla-RPC net-safe senders
--   -> _cos_la_loadout_safety.lua (#1159)
-- ============================================================
-- Registers LA's recolored cosmetics as separate inventory items via MIL, and
-- queues their texture swap into LA's existing apply pipeline (see
-- _la_bridge.lua); caches LA clone loadouts LOCALLY so a clone backend_id never
-- reaches PlayFab; and substitutes the vanilla equivalent on the two vanilla
-- senders that would otherwise put a locally-registered NetworkLookup index on
-- the wire and fatal a vanilla peer. Installed HERE, at the exact point that
-- block used to start - entry code between that point and the first moved
-- statement was declarations only, so the collapse reorders nothing, and the
-- two file-scope hook registrations still land before the net-safe presence
-- probe below.
--
-- `_send_la_apply` is handed over as a GETTER: the entry forward-declares it
-- above and only assigns it BELOW this install (out of the
-- _cos_la_sync_transport install), so a by-value hand-off would freeze nil.
-- `_la_equips_by_peer` and `_local_la_equips` are safe BY VALUE - each is a
-- truthy table created above and never rebound, the same proof the sibling
-- owners rely on.
--
-- `_net_safe_hook_status` deliberately did NOT move: nothing in the owner reads
-- or writes it. It stays entry state, brokered to the attachment-spawn owner
-- (which writes .PUAE / .AttachmentUtils into it) and read back by the startup
-- verification further down - one table, one broker, unchanged by this slice.
local _la_bridge_init_done       = false
local LA_LOADOUT_SAFETY = mod:dofile("scripts/mods/cosmetics_tweaker/_cos_la_loadout_safety").install(mod, {
    dbg = _dbg,
    gk_set = GK_SET,
    la_bridge = LA_BRIDGE,
    la_equips_by_peer = _la_equips_by_peer,
    la_persistence = LA_PERSIST,
    local_la_equips = _local_la_equips,
    local_player_safe = _local_player_safe,
    get_send_la_apply = function() return _send_la_apply end,
})
local _la_vanilla_fallback         = LA_LOADOUT_SAFETY.la_vanilla_fallback
local _wire_career_for_player      = LA_LOADOUT_SAFETY.wire_career_for_player
local _install_skin_loadout_safety = LA_LOADOUT_SAFETY.install_skin_loadout_safety

-- v0.8.61-dev: THIRD sync surface — attachment-RPC paths that read
-- `NetworkLookup.item_names[slot_data.item_data.name]` (or `slot_data.name`)
-- INLINE via raw table access, then send rpc_create_attachment. No
-- function wrapper can intercept the table read itself, so we pre-mutate
-- the LA-keyed name to the vanilla equivalent on the slot data, call
-- vanilla, then restore. The window is the single vanilla call — no
-- other code runs mid-call, so the swap is invisible to LOCAL apply.
--
-- Three sites covered (all decoded the same crash mode as v0.8.58-60):
--   1. PlayerUnitAttachmentExtension.game_object_initialized (line 63)
--      — local player initial spawn, sends rpc_create_attachment for
--      every attachment slot to clients (host) or server (client).
--   2. PlayerUnitAttachmentExtension.spawn_resynced_loadout (line 301)
--      — fires after a mid-mission loadout resync (dropped item, etc.).
--   3. AttachmentUtils.hot_join_sync (line 99) — fires PER NEWLY-JOINED
--      PEER for every attachment slot already worn. Plain table, must
--      use table-form + nil guard.
--
-- Hot_join uses `slot_data.name` (top-level); the two PUAE methods use
-- `slot_data.item_data.name` (nested). Both fields store the LA
-- backend_id when wearing an LA cosmetic (set by create_attachment via
-- AttachmentUtils internals).
local _net_safe_hook_status = { CosmeticUtils = false, LoadoutUtils = false, AttachmentUtils = false, PUAE = false }
_net_safe_hook_status.CosmeticUtils = CosmeticUtils ~= nil
_net_safe_hook_status.LoadoutUtils = LoadoutUtils ~= nil

local function _la_substitute_name(original_name, career_name)
    return _la_vanilla_fallback(original_name, career_name)
end

-- v0.8.64-dev: UNIFIED LA peer-sync — cos_la_apply replaces cos_la_attach.
--
-- v0.8.58-0.8.61 stopped peers crashing on LA cosmetics by substituting LA
-- backend_ids with vanilla equivalents on every outgoing vanilla RPC.
-- v0.8.62 added cos_la_attach for HATS ONLY so LA+cos_tweaker peers saw the
-- real LA hat. v0.8.64 generalises that pattern to cover all three LA
-- visual surfaces with ONE RPC:
--
--   payload = { go_id, slot, kind, armoury_key, vanilla_key }
--   kind ∈ { "hat", "armor", "offhand" }
--
-- Identity key is ARMOURY_KEY (LA's deterministic string like
-- "Kruber_Pureheart"), not la_backend_id. la_backend_id is mostly
-- deterministic across peers but has a silent-bail failure mode at the
-- receiver when its local ItemMasterList lookup misses; armoury_key matches
-- what LA's own SKIN_LIST keys by and sidesteps the issue entirely.
--
-- RACE FIX — replace, not append. Vanilla sees only the vanilla substitute
-- (existing CosmeticUtils / LoadoutUtils / PUAE / AttachmentUtils hooks do
-- the substitution). LA-aware peers receive cos_la_apply and replay.
-- Nothing races because vanilla NEVER carries an LA key over the wire.
--
-- v0.8.67-dev: SERVER-AUTHORITATIVE flow. All client equips emit a request
-- to the host (`cos_la_apply_req`); the host records the equip in
-- `_la_equips_by_peer[wearer_peer_id]` and broadcasts the authoritative
-- `cos_la_apply` to ALL peers (including the originating client, so they
-- apply in lockstep with everyone else). Peers reject any `cos_la_apply`
-- whose sender isn't the host. The host short-circuits its own local
-- equips by skipping the request hop and broadcasting directly.
--
-- Identity over the wire is now `wearer_peer_id` (deterministic across
-- peers) rather than `go_id` (which is host-relative and may not resolve
-- on late-spawn races). Receiver looks up the wearer's player_unit via
-- `Managers.player:players_at_peer(wearer_peer_id)`. If the unit isn't
-- spawned yet (mid-loading, etc.), the payload is queued and re-tried on
-- mod.update for up to 5 seconds.

-- Per-peer authoritative state (host only). Keyed by wearer_peer_id;
-- value is { [slot_name] = { kind, armoury_key, vanilla_key } }.
-- v0.9.0.11-hotfix: was `local _la_equips_by_peer = {}` here at line 3711.
-- Moved declaration to the top of the file (just above the BackendUtils
-- hook at line 2241) because that hook's husk-mesh-swap probe was
-- referencing this local — but at line 2241 the local doesn't exist yet
-- in lexical scope, so the reference compiled as a GLOBAL nil. The probe
-- always reported cache_has_wearer=false on PC-B even AFTER the recv handler
-- wrote to the cache (the receiver, declared after this line, captured
-- the real local correctly — but the BackendUtils hook captured global nil).
-- Two readers, two different upvalue resolutions. Reassign to the existing
-- table here so the rest of the file's references continue to work.
_la_equips_by_peer = _la_equips_by_peer or {}
-- v0.9.69-dev (#265, LA_SYNC_CORE_AUDIT Slice 1): runtime alias so code that
-- sits LEXICALLY BEFORE the forward declaration (the offhand picker press
-- handler, ~line 3760) can consult the synced store at runtime without
-- re-triggering the v0.9.0.11 global-nil upvalue bug. The table identity is
-- never replaced (writes are per-key), so the alias stays valid for the
-- whole session.
mod._la_equips_by_peer = _la_equips_by_peer

-- Late-spawn replay queue. Each entry:
-- { wearer_peer_id, slot, kind, armoury_key, vanilla_key, expires_at }
local _la_pending_apply = {}

-- The cos_la_* peer-sync transport, SEND half (identity + send + queue)
--   -> _cos_la_sync_transport.lua (#1159)
--
-- Peer identity (`_host_peer_id` and friends), the three senders
-- (`_send_la_apply`, `mod._send_la_revert`, `mod._send_offhand_mesh`), the
-- shared 0.5s emit-dedup window and the deferred-emit retry queue. Installed
-- HERE, at the exact point that block used to execute. The block registered
-- NOTHING - no mod:hook, mod:hook_safe, mod:hook_origin, mod:command,
-- mod:network_register or mod:dofile - so mod-wide registration cardinality AND
-- order are unchanged by construction rather than by inspection. The owner's
-- RECEIVE half installs separately, further down, at its own original position;
-- see the `install_receivers` call site.
--
-- `_la_equips_by_peer` is safe BY VALUE here: it is reassigned exactly once, at
-- FILE SCOPE a few lines above (`_la_equips_by_peer = _la_equips_by_peer or {}`,
-- identity-preserving because the left side is already a truthy table), so this
-- install captures the final table - the same proof the three sibling owners
-- below already rely on. `_la_pending_apply` is handed over as a GETTER because
-- both of its drain sites REBIND it (`_la_pending_apply = kept`) and the
-- receive half only appends: by value the append would land in a table the
-- entry had already discarded.
--
-- The five peer-identity helpers and `_send_la_apply` come straight back out as
-- entry locals. They are consumed lexically below by the apply / replay / glow
-- transport / attachment-spawn installs and by mod.update, and `_send_la_apply`
-- fills the forward declaration made ~1700 lines above for the CosmeticUtils
-- hook, so every existing call site keeps resolving the same function object.
local LA_SYNC = mod:dofile("scripts/mods/cosmetics_tweaker/_cos_la_sync_transport").install(mod, {
    dbg = _dbg,
    dbg_alert = _dbg_alert,
    glow_by_peer = _glow_by_peer,
    glow_log = _cos574_log,
    la_bridge = LA_BRIDGE,
    la_equips_by_peer = _la_equips_by_peer,
    la_persistence = LA_PERSIST,
    la_replay_policy = LA_REPLAY_POLICY,
    local_player_safe = _local_player_safe,
    probe = PROBE,
    rpc_schema = COS_RPC_SCHEMA,
    trace = _trace,
    get_la_pending_apply = function() return _la_pending_apply end,
})
local _host_peer_id         = LA_SYNC.host_peer_id
local _local_peer_id_quick  = LA_SYNC.local_peer_id_quick
local _is_local_server      = LA_SYNC.is_local_server
local _wearer_unit_for_peer = LA_SYNC.wearer_unit_for_peer
local _local_player_peer_id = LA_SYNC.local_player_peer_id
_send_la_apply              = LA_SYNC.send_la_apply

-- #918: ct_* skin ids cannot safely use vanilla's numeric weapon-skin wire
-- (#421), so send their authored hand meshes through the already-established
-- semantic offhand channel. State is keyed by wearer + weapon template so a
-- respawn can explicitly clear a previously published custom mesh. Committed
-- per-instance offhand picks remain the final writer for any claimed hand.
assert(CUSTOM_ILLUSION_SYNC.install(mod, {
    custom_skin_keys = mod._cos.custom_skin_keys,
    item_master = ItemMasterList,
    weapon_skins = WeaponSkins and WeaponSkins.skins,
    unit_alive = function(unit) return Unit.alive(unit) end,
    owner_for_unit = function(unit)
        local pm = Managers and Managers.player
        return pm and pm.owner and pm:owner(unit) or nil
    end,
    wearer_is_human = mod._cos_husk_identity.wearer_is_human,
    selection_for = function(backend_id)
        _offhand_session_state.migrate_legacy(backend_id)
        return _offhand_selection[backend_id]
    end,
    send = mod._send_offhand_mesh,
    log = printf,
}) == true, "custom illusion semantic transport failed to install")

local function _resolve_la_variant(armoury_key)
    if GK_SET and GK_SET.resolve_variant then
        local authored = GK_SET.resolve_variant(armoury_key)
        if authored then return authored, nil end
    end
    if CUSTOM_HATS and CUSTOM_HATS.resolve_variant then
        local custom = CUSTOM_HATS.resolve_variant(armoury_key)
        if custom then return custom, nil end
    end
    local la = get_mod("Loremasters-Armoury")
    if not la or type(la.SKIN_LIST) ~= "table" then return nil, nil end
    return la.SKIN_LIST[armoury_key], la
end

-- v0.9.13-dev: extracted from the v0.9.11 character-mismatch guard in
-- `_apply_la_on_unit` so the decision is unit-testable in isolation. Pure:
-- given the owner_unit's currently-equipped hat path (preferred source) AND
-- the profile base prefix (fallback when no hat is attached yet), decide
-- whether the LA hat's mesh is safe to attach to this body.
--
--   owner_char_path -- path to the OWNER's current vanilla slot_hat
--                      (e.g. "units/beings/player/empire_soldier_breton/
--                      headpiece/es_gk_hat_01") or nil if no slot_hat.
--   la_unit_path    -- path to the cached LA hat mesh
--                      (e.g. "units/beings/player/empire_soldier_breton/
--                      headpiece/es_gk_hat_03").
--   profile_base    -- character base from SPProfiles.unit_name (e.g.
--                      "empire_soldier") or nil if unresolvable.
--
-- Returns (true) when the LA mesh's character segment matches the owner's
-- character segment, otherwise (false, reason_string). When neither source
-- is resolvable, returns false — the conservative choice (no LA visual is
-- strictly better than a wrong-skeleton attach that may crash via
-- `Unit.node` failing the C-level attachment node lookup).
local function _la_chars_compatible(owner_char_path, la_unit_path, profile_base)
    local la_char = string.match(la_unit_path or "", "^units/beings/player/([^/]+)/")
    if not la_char then return true end  -- can't extract LA char; let caller proceed
    if owner_char_path then
        local owner_char = string.match(owner_char_path, "^units/beings/player/([^/]+)/")
        if owner_char then
            if owner_char == la_char then return true end
            return false, ("owner_char=%s la_char=%s"):format(owner_char, la_char)
        end
    end
    if profile_base then
        if la_char == profile_base
            or string.sub(la_char, 1, #profile_base + 1) == profile_base .. "_"
        then
            return true
        end
        return false, ("profile_base=%s la_char=%s"):format(profile_base, la_char)
    end
    return false, "no owner_char_path AND no profile_base resolvable"
end
mod._la_chars_compatible = _la_chars_compatible

-- v0.9.13-dev: passive runtime monitor. Fires on every player spawn (host's
-- own + every bot owned by the host + every husk on a remote client). For
-- the spawned unit, compares the CACHED LA hat (`_la_equips_by_peer
-- [wearer_peer]["slot_hat"]`) against the unit's actual character body. If
-- the cached LA mesh's character segment doesn't match the spawning unit's
-- character, that's the exact failure mode from issue #14 — a host-owned bot
-- whose career differs from the host's about to receive a cross-skeleton
-- attach. The v0.9.11 guard prevents the attach itself; this monitor surfaces
-- when the situation arises so any regression is visible in console without
-- needing a manual chat command.
--
-- Mismatch detections ALWAYS log (this is the safety net). Routine "here's
-- the cache state for the spawning peer" snapshots route through mod:debug,
-- gated by VMF output_mode_debug.

-- v0.9.28-dev (issue #14 cache-leak follow-up): pure invalidation helper.
-- `_la_equips_by_peer` is keyed `[peer_id][slot]` only, so when a peer
-- switches career on the same peer_id (e.g. Kerillian → Saltzpyre WHC),
-- the previous career's LA hat entry persists until the peer disconnects.
-- The v0.9.11 character-mismatch guard catches the visible apply, but the
-- stale entry keeps firing CROSS-SKELETON MISMATCH warnings on every spawn
-- of the new character. Solution: when the spawn-monitor catches a
-- mismatch, purge the offending slot from the cache so it self-heals on
-- the first post-switch spawn. Subsequent legitimate cos_la_apply RPCs
-- repopulate the slot for the current career; if there isn't one, the
-- slot stays empty and the warning stops firing.
--
-- Pulled into a module-level local so the regression test can drive it
-- with synthetic inputs (no player units / LA bridge / Managers mocks).
local function _purge_stale_peer_slot(cache, wearer_peer, slot_name)
    if not (cache and wearer_peer and slot_name) then return false end
    local equips = cache[wearer_peer]
    if not (equips and equips[slot_name]) then return false end
    equips[slot_name] = nil
    if next(equips) == nil then cache[wearer_peer] = nil end
    return true
end
mod._purge_stale_peer_slot = _purge_stale_peer_slot

mod._la_spawn_monitor = mod._cos_husk_identity.make_spawn_monitor({
    bridge = LA_BRIDGE, store = _la_equips_by_peer, persistence = LA_PERSIST,
    score_identity = SCORE_IDENTITY, script_unit = ScriptUnit, unit_api = Unit,
    managers = function() return Managers end,
    profiles = function() return rawget(_G, "SPProfiles") end,
    resolve_variant = _resolve_la_variant, chars_compatible = _la_chars_compatible,
    purge = _purge_stale_peer_slot, debug = _dbg,
    warning = function(...) mod:warning(...) end,
    print = function(...) if printf then printf(...) end end,
})

-- Wire-up note: SimpleInventoryExtension.extensions_ready is already hooked
-- inside `_la_persistence.lua` for the auto-restore queue. VMF's hook_safe
-- does NOT chain on (Class, method) (per VMF_RECIPES.md § 1) — a second
-- hook_safe registration here would silently overwrite the first and break
-- restore. Instead, the existing hook in _la_persistence.lua calls
-- `mod._la_spawn_monitor` if defined, so both behaviors run from a single
-- registration. The husk-side equivalent is hooked from this file because
-- _la_persistence only cares about the owned-player path.
--
-- v0.9.16-dev (issue #35): the husk class does NOT have `extensions_ready` —
-- only `Simple*Extension` (the self-owned variant) does. The husk class is a
-- separate root class with no inheritance (per CLAUDE.md "Self-owned vs husk
-- extension classes"), and its lifecycle entry point is `init`. The earlier
-- registration on `extensions_ready` silently no-op'd at hook-install time.
-- Hooking `init` with the husk signature `(self, extension_init_context, unit,
-- extension_init_data)` resolves the dead-hook and runs the spawn monitor on
-- every remote-player husk inventory init.
mod:hook_safe("SimpleHuskInventoryExtension", "init", function(self, extension_init_context, unit, extension_init_data)
    if mod._la_spawn_monitor then
        local ok, err = pcall(mod._la_spawn_monitor, unit)
        if not ok then _dbg_alert("[la-spawn-monitor] pcall err: %s", tostring(err)) end
    end
    -- #660 S3: a remote wearer's husk inventory is now constructed -> peer-ready
    -- replay edge. This is the per-husk "husk became available" signal that
    -- drains what session-ready/peer-ready deferred. The apply gate still
    -- defers until the husk unit is alive + skeleton-ready, and the surviving
    -- persisted stores are the source, never the live menu selection. When the
    -- wearer peer is not yet resolvable, fire without a peer scope: the
    -- preceding transition already invalidated all, so only not-yet-applied
    -- records do work (coalesced).
    if mod._cos_replay then
        local wearer_peer
        local pm = Managers and Managers.player
        if pm and pm.owner then
            local owner = pm:owner(unit)
            wearer_peer = owner and owner.peer_id or nil
        end
        mod._cos_replay.on_edge("peer-ready",
            wearer_peer and { only_peer = wearer_peer, invalidate_peer = wearer_peer } or nil)
    end
end)

-- v0.9.13-dev: mission-start state snapshot. Gated on debug_dumps. Fires
-- once when StateInGameRunning starts so the cached LA state + persisted
-- entries land in the log at the same timestamp as the mission begin —
-- makes correlating later spawn events to the snapshot trivial.
mod._la_dump_mission_state = function(reason)
    _dbg("[la-state-dump] reason=%s", tostring(reason))
    local n_peers = 0
    if _la_equips_by_peer then
        for peer, slots in pairs(_la_equips_by_peer) do
            n_peers = n_peers + 1
            for slot, entry in pairs(slots) do
                _dbg("[la-state-dump]   peer=%s slot=%s kind=%s armoury=%s vanilla=%s",
                    tostring(peer), tostring(slot), tostring(entry.kind),
                    tostring(entry.armoury_key), tostring(entry.vanilla_key))
            end
        end
    end
    local persisted = mod:get("la_persisted_equips") or {}
    local n_careers = 0
    if persisted.careers then
        for career, slots in pairs(persisted.careers) do
            n_careers = n_careers + 1
            _dbg("[la-state-dump]   persisted career=%s hat=%s skin=%s",
                tostring(career), tostring(slots.slot_hat or "-"), tostring(slots.slot_skin or "-"))
        end
    end
    local n_illusions = 0
    if persisted.illusions then
        for _ in pairs(persisted.illusions) do n_illusions = n_illusions + 1 end
    end
    _dbg("[la-state-dump] totals: %d live peer(s), %d persisted career entr(ies), %d persisted illusion(s)",
        n_peers, n_careers, n_illusions)
end

local function _level_world()
    if Managers and Managers.world and Managers.world.has_world
        and Managers.world:has_world("level_world")
    then
        return Managers.world:world("level_world")
    end
    return nil
end

-- v0.9.85-dev (#514): weapon-identity resolution for the kind=offhand and
-- kind=illusion apply gates. Returns (match, w_item):
--   match  = true when the stored entry key (slot_name) names the WIELDED
--            item (template / name / key / item_type; plus the wielded SLOT
--            name for slot-keyed entries when allow_slot_key is true).
--   w_item = the wielded item_data, or nil when unresolvable.
-- CRITICAL field note: the wielded slot name lives at
-- `equipment.wielded_slot` on BOTH inventory classes
-- (simple_inventory_extension.lua:208/669 and
-- simple_husk_inventory_extension.lua:775). `inv.wielded_slot` exists ONLY
-- on SimpleHuskInventoryExtension (simple_husk_inventory_extension.lua:321).
-- The v0.9.72 guard read the husk-only field, so on the LOCAL wearer
-- (SimpleInventoryExtension) w_item resolved to nil and the guard fell
-- through PERMISSIVE - the spawn-time state replay then painted a
-- Bret-shield LA pick (stored under one_handed_sword_shield_template_2,
-- item_master_list_lake.lua:425) onto the left-hand MACE of CWV's wielded
-- Sword and Mace (#514). Callers MUST treat "not match" - including the
-- w_item == nil unresolvable case - as SKIP (return false): the pending
-- retry / next-wield reconcile re-applies once the matching weapon is in
-- hand, so restrictive-by-default cannot strand a pick.
function mod._la_wielded_item_matches(inv, equipment, slot_name, allow_slot_key)
    local w_slot_name = LA_REPLAY_POLICY.wielded_slot(inv, equipment)
    local w_slot_data = equipment and equipment.slots and w_slot_name
        and equipment.slots[w_slot_name]
    local w_item = w_slot_data and w_slot_data.item_data
    if not w_item then
        return false, nil
    end
    local match = (slot_name == w_item.template) or (slot_name == w_item.name)
        or (slot_name == w_item.key) or (slot_name == w_item.item_type)
        or (allow_slot_key == true and slot_name == w_slot_name)
    return match, w_item
end

-- ============================================================
-- LA appearance apply / revert / reconcile runtime
--   -> _cos_la_apply_runtime.lua (#1159)
-- ============================================================
-- The unified LA apply core (`_apply_la_on_unit` and its hat / armor / offhand /
-- illusion lanes), the post-spawn offhand mesh re-swap, the three revert
-- primitives (`mod._la_native_pulse`, `mod._la_restore_native_hat`,
-- `mod._la_apply_revert_recv`) and the single render-reconcile entry point
-- (`mod._la_reconcile`). Installed HERE, at the exact point that block used to
-- execute. The block registered NOTHING - no mod:hook, mod:hook_safe,
-- mod:hook_origin, mod:command, mod:network_register or mod:dofile - so mod-wide
-- registration cardinality AND order are unchanged by construction rather than
-- by inspection, and the bounded appearance-replay coordinator installed just
-- below still sits immediately after the canonical `_la_reconcile` owner, which
-- is exactly what its own comment requires.
--
-- `_la_equips_by_peer` is safe BY VALUE here: it is reassigned exactly once, at
-- FILE SCOPE ~750 lines above (`_la_equips_by_peer = _la_equips_by_peer or {}`,
-- identity-preserving because the left side is already a truthy table), so this
-- install captures the final table - the same proof the two sibling owners below
-- already rely on. `_la_pending_apply` is handed over as a GETTER + SETTER pair
-- because BOTH of its drain sites REBIND it (`_la_pending_apply = kept`) and one
-- of those drains moved into the owner: by value, the owner's purge would be
-- invisible here and its re-queue would append to a table this file had already
-- discarded.
mod:dofile("scripts/mods/cosmetics_tweaker/_cos_la_apply_runtime").install(mod, {
    custom_hats = CUSTOM_HATS,
    gk_set = GK_SET,
    la_bridge = LA_BRIDGE,
    la_replay_policy = LA_REPLAY_POLICY,
    probe = PROBE,
    apply_authored_offhand_to_unit = _apply_authored_offhand_to_unit,
    dbg = _dbg,
    dbg_alert = _dbg_alert,
    la_chars_compatible = _la_chars_compatible,
    la_equips_by_peer = _la_equips_by_peer,
    level_world = _level_world,
    offhand_paint_mesh_ok = _offhand_paint_mesh_ok,
    override_package_ready = _override_package_ready,
    purge_stale_peer_slot = _purge_stale_peer_slot,
    resolve_authored_offhand_mesh = _resolve_authored_offhand_mesh,
    resolve_la_variant = _resolve_la_variant,
    trace_paint = _trace_paint,
    unit_mesh_name = _unit_mesh_name,
    wearer_unit_for_peer = _wearer_unit_for_peer,
    get_la_pending_apply = function() return _la_pending_apply end,
    set_la_pending_apply = function(t) _la_pending_apply = t end,
})

-- #660 S3 bounded appearance replay coordinator. Install here, immediately
-- after the canonical `_la_reconcile` HOW owner and before every RPC consumer,
-- so the historical definition/registration order is unchanged.
mod:dofile("scripts/mods/cosmetics_tweaker/_cos_la_replay_runtime").install(mod, {
    policy = LA_REPLAY_POLICY,
    wearer_unit_for_peer = _wearer_unit_for_peer,
    unit_alive = function(unit) return Unit.alive(unit) end,
    is_local_server = _is_local_server,
    la_equips_by_peer = _la_equips_by_peer,
    printf = printf,
})

-- The cos_la_* peer-sync transport, RECEIVE half (phase 2 of the same owner)
--   -> _cos_la_sync_transport.lua (#1159)
--
-- The four `mod:network_register` handlers (`cos_la_apply_req`,
-- `cos_la_state_req`, `cos_la_state_ack`, `cos_la_apply`), the host-authoritative
-- validate + record + rebroadcast, the hot-join state-pull reply, and the
-- deferred peer purge (the `PlayerManager.remove_player` / `add_remote_player`
-- hook_safe pair plus `mod._la_tick_peer_purges`).
--
-- This is the SECOND install phase of the transport owner created above, not a
-- second dofile: the receive half closes over the send half's locals
-- (`_last_emit_at`, `_wearer_unit_for_peer`, `_host_peer_id`, ...) exactly as it
-- did when both halves were file-scope neighbours in this entry. Splitting the
-- installer in two is what lets the six registrations fire at THIS line - after
-- the apply/revert owner published `mod._la_reconcile` /
-- `mod._la_apply_revert_recv` and the bounded replay coordinator published
-- `mod._cos_replay`, which the handlers call - instead of ~800 lines earlier.
-- Registration cardinality and order are therefore identical to before the move;
-- the owner asserts that this runs exactly once.
LA_SYNC.install_receivers()

-- #641/#629 contextual Hold-Tab adapter. Remote loadout snapshots deliberately
-- have no backend_id, so exact-instance persistence cannot identify their
-- independently selected hand. Reuse the existing parity-gated peer caches;
-- never add component names or resource paths to a vanilla/network payload.
mod._cos.resolve_peer_item_presentation = function(wearer_peer, ui_slot_name,
        item, base_icon, base_display_name, base_description)
    local item_data = item and item.data
    local item_type = item_data and item_data.item_type
    local ownership = _cos_presentation_ownership(item_type)
    if not (wearer_peer and ownership) then return nil end

    local candidate_keys, seen = {}, {}
    local function add(value)
        if type(value) == "string" and value ~= "" and not seen[value] then
            seen[value] = true
            candidate_keys[#candidate_keys + 1] = value
        end
    end
    add(ui_slot_name)
    add(item_data and item_data.template)
    add(item_data and item_data.name)
    add(item_data and item_data.key)
    add(item_type)
    add(item and item.name)
    add(item and item.key)

    local record = ITEM_PRESENTATION.find_peer_record(wearer_peer,
        candidate_keys, _la_equips_by_peer, mod._offhand_mesh_by_peer)
    if not record then return nil end

    if base_icon == nil or base_display_name == nil or base_description == nil then
        local icon, name, description = UIUtils.get_ui_information_from_item(item)
        base_icon = base_icon or icon
        base_display_name = base_display_name or name
        base_description = base_description or description
    end
    local icon, display_name, description, changed = _cos_resolve_presentation(item,
        base_icon, base_display_name, base_description, ownership, record, nil)
    if not changed then return nil end
    return {
        icon = icon,
        display_name = display_name,
        description = description,
        ownership = ownership,
        source = "peer_cache",
    }
end

-- The host-authoritative per-peer glow transport keeps its historical
-- post-LA-RPC, pre-husk-wield install position. The shared husk hook below
-- remains in the entry because it composes LA mesh/paint and glow replay.
local _cos_glow_transport = mod:dofile(
    "scripts/mods/cosmetics_tweaker/_cos_glow_transport").install(mod, {
        glow_by_peer = _glow_by_peer,
        rpc_schema = COS_RPC_SCHEMA,
        is_local_server = _is_local_server,
        host_peer_id = _host_peer_id,
        log = _cos574_log,
        dbg = _dbg,
        dbg_alert = _dbg_alert,
    })
local _cos574_complete_glow_rehydrate = _cos_glow_transport.complete_rehydrate

-- v0.9.0.6-hotfix: husk-wield context wrapper.
--
-- Wraps SimpleHuskInventoryExtension._wield_slot to set a thread-local
-- `_current_husk_wield` table BEFORE the vanilla call enters
-- BackendUtils.get_item_units. The CT get_item_units hook reads the context
-- (wearer_peer, slot_name) and overrides result.left_hand_unit when the
-- wearer has a kind="unit" LA mesh selection recorded in _la_equips_by_peer.
-- This is how Ostermark / Bastonne / etc. custom-mesh shields render on
-- husks instead of the vanilla mesh.
--
-- v0.9.0.8-hotfix: switched to string-form hook so VMF defers resolution
-- until the class is loaded. Table-form `mod:hook(SimpleHuskInventoryExtension, ...)`
-- gated on `rawget(_G, "SimpleHuskInventoryExtension")` silently failed when
-- the class wasn't yet loaded at mod-init time — the rawget returned nil,
-- the `if` skipped, hook NEVER registered, and no `[husk-mesh-swap]` log
-- ever fired on PC-B. String-form lets VMF queue the hook via its delayed-
-- hooks mechanism (see boot log "Attempt to hook N delayed hooks").
mod:hook("SimpleHuskInventoryExtension", "_wield_slot", function(func, self, world, equipment, slot_name, unit_1p, unit_3p)
    -- Resolve which peer owns this husk extension.
    local husk_unit = self and self._unit
    local pm = Managers and Managers.player
    local wearer_player = mod._cos_husk_identity.player_for_unit(pm, husk_unit)
    local wearer_peer = wearer_player and wearer_player.peer_id
    -- #698 regression fix: do NOT gate on is_player_controlled alone. On a host
    -- peer the human (local_player_id 1) and its bots (2..4) share ONE peer id,
    -- so a bot husk's wield legitimately resolves wearer_peer=<host peer> and is
    -- correctly skipped - but if the human's controlled flag is transiently nil
    -- during spawn/sync, the old gate ALSO skipped the human, and the log
    -- (peer-only) made a routine bot skip read as the human being dropped
    -- (tonight's 3-player session: 29x "wearer=<host peer>"). wearer_is_human is
    -- local_player_id-aware: a bot never owns local_player_id 1, so this never
    -- mis-accepts a bot, and it rescues the human under a nil controlled flag.
    local wearer_is_human, human_reason =
        mod._cos_husk_identity.wearer_is_human(wearer_player)
    local wearer_lpid = mod._cos_husk_identity.local_player_id(wearer_player)
    if wearer_peer and not wearer_is_human then
        if printf then printf("[cos:698] HUSK identity SKIP wearer=%s local_player_id=%s controlled=%s reason=%s (host bots share the wearer peer; local_player_id~=1 => bot)",
            tostring(wearer_peer), tostring(wearer_lpid),
            tostring(mod._cos_husk_identity.player_controlled(wearer_player)),
            tostring(human_reason)) end
        wearer_peer = nil
    elseif wearer_peer then
        local removed, reason, removed_slots = mod._cos_husk_identity.invalidate_for_career(
            _la_equips_by_peer, wearer_peer, self and self._career_name, true)
        if removed > 0 and printf then
            printf("[cos:698] HUSK career-change invalidated wearer=%s active=%s slots=%s reason=%s",
                tostring(wearer_peer), tostring(self and self._career_name),
                table.concat(removed_slots, ","), tostring(reason))
        end
    end
    -- v0.9.0.8-hotfix: diagnostic log.
    _dbg("[husk-wield-wrap] entry wearer=%s slot=%s husk_unit=%s",
        tostring(wearer_peer), tostring(slot_name), tostring(husk_unit))
    -- v0.9.69-dev (Slice 0, I6 / #264): a nil wearer_peer here silently kills
    -- BOTH the get_item_units mesh swap AND the post-vanilla repaint for this
    -- wield. Surface it once per husk unit in the mod-logging-OFF log.
    if not wearer_peer and husk_unit then
        local seen = mod._la_gate_seen
        if not seen then seen = {}; mod._la_gate_seen = seen end
        local sk = "wield-nopeer|" .. tostring(husk_unit)
        if not seen[sk] and printf then
            seen[sk] = true
            printf("[la-state] HUSK-WIELD wearer-unresolved husk=%s slot=%s (mesh swap + repaint skipped this path)",
                tostring(husk_unit), tostring(slot_name))
        end
    end
    -- v0.9.43-dev HUSK trace: a remote peer's body (husk) is (re)wielding a
    -- slot. This drives the husk get_item_units mesh-swap (RESOLVE husk-mesh-
    -- swap) + the post-vanilla repaint below. Repro #4 (host swaps secondary
    -- and back) fires this on every peer's husk view of the host.
    _trace("HUSK wield_slot entry wearer=%s slot=%s husk_unit=%s",
        tostring(wearer_peer), tostring(slot_name), tostring(husk_unit))
    -- Set context (stack-style).
    local prev = _current_husk_wield
    _current_husk_wield = {
        wearer_peer = wearer_peer,
        husk_unit = husk_unit,
        slot_name = slot_name,
        career_name = self and self._career_name,
    }
    -- v0.9.2.1: ALWAYS delegate to vanilla. The v0.9.2 pre-flight bail
    -- (skipping the vanilla call when can_get reported a missing unit)
    -- left `self.wielded_slot` nil, which made vanilla's subsequent
    -- `wield()` chain crash downstream at simple_husk_inventory_extension
    -- .lua:534 (`equipment.slots[wielded_slot]` → nil-index) on EVERY husk
    -- wield to a missing unit, not just the rare engine-assert case the
    -- pre-flight was guarding against. Net regression. Reverted — vanilla
    -- runs and pcall is the only catch. The pre-flight remains as a
    -- LOG-ONLY diagnostic (always-on printf via _dbg_alert, dedup'd below) so a
    -- co-op card cannot false-pass with mod logging off - issue 154 / #1156.
    -- v0.9.42-dev (#154): ENRICHED PREFLIGHT PROBE. The old warn read only the
    -- BASE item_data.<field>, but vanilla _wield_slot resolves the unit through
    -- BackendUtils.get_item_units (backend_utils.lua:144-190), which (a) prefers
    -- the per-career override `<field>_override[career]`, and (b) when a skin is
    -- present, REPLACES the unit with the skin template's unit + the skin's own
    -- per-career override. For weapon_tweaker cross-character weapons the BASE
    -- field points at the DONOR character's mesh (frequently non-resident on this
    -- viewer because nobody here is playing that character), while the unit
    -- vanilla actually spawns is wt's per-career override — which weapon_tweaker
    -- force-loads on every peer at mod init. So the old base-field warn is a
    -- FALSE ALARM whenever the RESOLVED unit is resident, which is the 160×/
    -- session log spam #154 quotes. This probe resolves the SAME unit vanilla
    -- will spawn and only warns LOUD when that resolved unit is non-resident
    -- (the genuinely risky case: wt's force-load missed this weapon for husks);
    -- the false-alarm case is demoted to a quiet file-only line.
    --
    -- Cross-char MESH ownership stays with weapon_tweaker; cosmetics' store
    -- reaches these slots via the #154 template mirror (_cos_husk_cache_bridge).
    -- This block stays read-only diagnostics (warn+proceed, v0.9.2.1).
    if Application and Application.can_get and equipment then
        local slot_data = equipment.slots and equipment.slots[slot_name]
        local item_data = slot_data and slot_data.item_data
        local skin      = slot_data and slot_data.skin
        local career    = self and self._career_name
        if item_data then
            for _, field in ipairs({ "right_hand_unit", "left_hand_unit" }) do
                local override_field = field .. "_override"
                local base = item_data[field]
                -- Mirror vanilla BackendUtils.get_item_units resolution order.
                local resolved = base
                local ov = item_data[override_field]
                if career and ov and ov[career] then resolved = ov[career] end
                local via_skin = nil
                if skin and WeaponSkins and WeaponSkins.skins then
                    -- rawget: WeaponSkins.skins can carry a strict metatable on
                    -- partially-populated peers (CLAUDE.md fragile-globals rule).
                    local st = rawget(WeaponSkins.skins, skin)
                    if st then
                        via_skin = skin
                        resolved = st[field] -- skin REPLACES the unit (may be nil)
                        local sov = st[override_field]
                        if career and sov and sov[career] then resolved = sov[career] or resolved end
                    end
                end
                -- Vanilla spawns this hand only if the resolved unit is truthy
                -- (simple_husk_inventory_extension.lua:665/669), so a nil resolved
                -- means "no unit on this hand" — nothing to check.
                if resolved and resolved ~= "" then
                    local resolved_resident = Application.can_get("unit", resolved) and true or false
                    local base_resident = (base and base ~= "" and Application.can_get("unit", base)) and true or false
                    -- Dedup so a missing/false-alarm weapon logs once per
                    -- (career, template, field, resolved) instead of every wield.
                    mod._preflight_seen = mod._preflight_seen or {}
                    local seen_key = (resolved_resident and "ok|" or "warn|")
                        .. tostring(career) .. "|" .. tostring(item_data.name)
                        .. "|" .. field .. "|" .. tostring(resolved)
                    if not mod._preflight_seen[seen_key] then
                        mod._preflight_seen[seen_key] = true
                        if not resolved_resident then
                            -- The unit vanilla WILL actually spawn is missing on
                            -- this peer → real risk (wt force-load gap for husks,
                            -- or a non-wt cross-char weapon nobody preloaded).
                            _dbg_alert("[husk-wield-wrap] PREFLIGHT WARN wearer=%s career=%s slot=%s field=%s template=%s base=%s(resident=%s) RESOLVED=%s(resident=false, NOT in resource manager) via_skin=%s - vanilla will spawn a NON-resident unit; cross-char weapon force-load (weapon_tweaker's) may have missed this for husks",
                                tostring(wearer_peer), tostring(career), tostring(slot_name), field,
                                tostring(item_data.name), tostring(base), tostring(base_resident),
                                tostring(resolved), tostring(via_skin))
                        elseif not base_resident then
                            -- Base non-resident but the RESOLVED override/skin unit
                            -- IS resident → the old warn was a false alarm. Quiet,
                            -- file-only (confirms wt/vanilla handled it).
                            _dbg("[husk-wield-wrap] PREFLIGHT OK (false alarm) wearer=%s career=%s slot=%s field=%s template=%s base=%s(resident=false) RESOLVED=%s(resident=true) via_skin=%s — base-field warn was spurious; resolved unit is resident",
                                tostring(wearer_peer), tostring(career), tostring(slot_name), field,
                                tostring(item_data.name), tostring(base), tostring(resolved), tostring(via_skin))
                        end
                    end
                end
            end
        end
    end
    local ok, r1, r2, r3, r4, r5, r6, r7, r8 = pcall(func, self, world, equipment, slot_name, unit_1p, unit_3p)
    _current_husk_wield = prev
    if not ok then
        _dbg_alert("[husk-wield-wrap] vanilla _wield_slot ERRORED wearer=%s slot=%s err=%s — pcall caught it. Husk visual likely missing/stale but host stays alive.",
            tostring(wearer_peer), tostring(slot_name), tostring(r1))
        return nil
    end

    -- #574: husk _wield_slot bypasses GearUtils.create_equipment and creates
    -- fresh hand units directly. Bind the receiver-visible identity and repaint
    -- after vanilla has installed those units; backend_id is intentionally nil
    -- because inventory instance ids are not shared between peers.
    do
        local glow_slot = equipment and equipment.slots and equipment.slots[slot_name]
        local glow_item = glow_slot and glow_slot.item_data
        local glow_units = {
            equipment and equipment.right_hand_wielded_unit_3p,
            equipment and equipment.left_hand_wielded_unit_3p,
            equipment and equipment.right_hand_wielded_unit,
            equipment and equipment.left_hand_wielded_unit,
        }
        local peer_state = wearer_peer and _glow_by_peer[wearer_peer]
        local glow_matches = 0
        if mod._cos.bind_glow_unit then
            for _, glow_unit in pairs(glow_units) do
                mod._cos.bind_glow_unit(glow_unit, nil, glow_slot and glow_slot.skin,
                    slot_name, glow_item and glow_item.name, glow_item and glow_item.template)
                if peer_state and mod._cos.remote_glow_matches
                        and mod._cos.remote_glow_matches(glow_unit, peer_state) then
                    glow_matches = glow_matches + 1
                end
            end
        end
        mod._cos.apply_glow_override(glow_units, wearer_peer)
        if wearer_peer then
            _cos574_log("repaint path=husk_wield wearer=%s skin=%s slot=%s active=%s",
                tostring(wearer_peer), tostring(glow_slot and glow_slot.skin),
                tostring(slot_name), tostring(peer_state and peer_state.active_per_item_glow ~= nil))
            if peer_state and peer_state.active_per_item_glow ~= nil and glow_matches > 0 then
                _cos574_complete_glow_rehydrate(wearer_peer, "husk_wield", glow_matches)
            end
        end
    end

    -- v0.9.0.10-hotfix: RE-PAINT MERGED IN. The v0.9.0.5 separate
    -- `mod:hook_safe(SimpleHuskInventoryExtension, "wield", ...)` was
    -- silently dropped by VMF because _tpe.lua:511 had already hooked
    -- the same Class+method (per feedback_vmf_hook_safe_no_chain). The
    -- re-paint never ran. Folding the same logic into the _wield_slot
    -- wrap (above) sidesteps the shadow — _wield_slot is not multi-hooked.
    -- Runs AFTER vanilla returns, when the just-spawned weapon units are
    -- in the slots and ready to be painted.
    if wearer_peer and _la_equips_by_peer then
        local equips = _la_equips_by_peer[wearer_peer]
        if equips then
            local slot_data = equipment and equipment.slots and equipment.slots[slot_name]
            local item_data = slot_data and slot_data.item_data
            local wielded_template = item_data and item_data.template
            for stored_key, entry in pairs(equips) do
                if entry and entry.kind and entry.armoury_key then
                    local career_ok, career_reason =
                        mod._cos_husk_identity.entry_matches_career(
                            entry, self and self._career_name)
                    local should_apply = false
                    if not career_ok then
                        if printf then printf("[cos:698] HUSK repaint SKIP wearer=%s stored_key=%s kind=%s recorded=%s active=%s reason=%s",
                            tostring(wearer_peer), tostring(stored_key), tostring(entry.kind),
                            tostring(entry.wearer_career), tostring(self and self._career_name),
                            tostring(career_reason)) end
                    elseif entry.kind == "hat" and stored_key == "slot_hat" then
                        should_apply = (slot_name == "slot_hat")
                    elseif entry.kind == "armor" and stored_key == "slot_skin" then
                        should_apply = true
                    elseif entry.kind == "offhand" or entry.kind == "illusion" then
                        if wielded_template and stored_key == wielded_template then
                            should_apply = true
                        end
                    end
                    if should_apply then
                        _dbg("[husk-wield-repaint] apply stored_key=%s kind=%s key=%s",
                            tostring(stored_key), tostring(entry.kind), tostring(entry.armoury_key))
                        -- v0.9.43-dev HUSK trace: post-vanilla re-apply of a
                        -- cached LA cosmetic onto the just-spawned husk units.
                        _trace("HUSK wield-repaint stored_key=%s kind=%s armoury=%s slot=%s wearer=%s",
                            tostring(stored_key), tostring(entry.kind), tostring(entry.armoury_key),
                            tostring(slot_name), tostring(wearer_peer))
                        -- v0.9.70-dev (#264, Slice 2 / I3): route through the single
                        -- reconcile entry point. allow_pulse=false -- we are INSIDE a
                        -- _wield_slot body (pulsing would re-enter wield); if the
                        -- in-wield get_item_units mesh swap missed, reconcile defers
                        -- a pulse to the pending drain, which runs from mod.update a
                        -- frame later. THIS is the switch-back repair path.
                        mod._la_reconcile(wearer_peer, stored_key, "husk-wield", false)
                    end
                end
            end
        end
    end

    return r1, r2, r3, r4, r5, r6, r7, r8
end)

-- v0.9.0.10-hotfix: the standalone re-paint hook_safe("...wield") was
-- SHADOWED by _tpe.lua:511's earlier registration (VMF hook_safe doesn't
-- chain — second registration on same Class+method silently dropped, per
-- feedback_vmf_hook_safe_no_chain). The re-paint logic is now folded
-- INTO the _wield_slot wrap above, after vanilla's spawn completes.
-- The wrap uses mod:hook (not hook_safe) on a different method
-- (_wield_slot vs wield) so there's no shadow conflict.

-- ============================================================
-- Attachment-slot LA spawn / sync seams
--   -> _cos_attachment_spawn_sync.lua (#1159)
-- ============================================================
-- Every engine path that spawns or syncs an ATTACHMENT-category cosmetic onto a
-- player body: PlayerHuskAttachmentExtension.create_attachment,
-- PlayerUnitAttachmentExtension.game_object_initialized / spawn_resynced_loadout,
-- and AttachmentUtils.hot_join_sync (which also carries the non-attachment
-- hot-join replay, because vanilla's hot_join_sync is the only per-joiner seam
-- and it walks attachment-category slots only). Installed HERE, at the exact
-- point that block previously executed, so hook registration order and the
-- "[net-safe] hook registration" verification below are unchanged.
--
-- `_net_safe_hook_status` is handed over BY REFERENCE: the owner writes .PUAE and
-- .AttachmentUtils, and the startup verification a few lines below reads them off
-- the same table. `_la_pending_apply` is handed over as a GETTER because the two
-- drain sites REBIND it (`_la_pending_apply = kept`); a by-value hand-off would
-- leave the husk-hat skeleton deferral appending to a table the first drain
-- discarded. `_send_la_apply` is safe by value here - unlike the view-lifecycle
-- owner far above, this install call executes ~2200 lines BELOW the sender's
-- assignment, and test_cos_attachment_spawn_sync pins that ordering.
mod:dofile("scripts/mods/cosmetics_tweaker/_cos_attachment_spawn_sync").install(mod, {
    appearance_fade_runtime = APPEARANCE_FADE_RUNTIME,
    rpc_schema = COS_RPC_SCHEMA,
    custom_hats = CUSTOM_HATS,
    gk_set = GK_SET,
    la_bridge = LA_BRIDGE,
    la_persist = LA_PERSIST,
    dbg = _dbg,
    dbg_alert = _dbg_alert,
    is_local_server = _is_local_server,
    la_equips_by_peer = _la_equips_by_peer,
    la_substitute_name = _la_substitute_name,
    la_vanilla_fallback = _la_vanilla_fallback,
    level_world = _level_world,
    local_la_equips = _local_la_equips,
    local_player_safe = _local_player_safe,
    net_safe_hook_status = _net_safe_hook_status,
    offhand_selection = _offhand_selection,
    offhand_session_state = _offhand_session_state,
    resolve_la_variant = _resolve_la_variant,
    send_la_apply = _send_la_apply,
    get_la_pending_apply = function() return _la_pending_apply end,
})

-- Startup verification: log applied/missing state for every plain-table
-- net-safe hook. Helps catch the silent-no-op failure mode where a
-- required helper table wasn't loaded yet at mod init (no runtime
-- indication other than a peer crash).
mod:info("[net-safe] hook registration: CosmeticUtils=%s LoadoutUtils=%s AttachmentUtils=%s PUAE=%s",
    tostring(_net_safe_hook_status.CosmeticUtils),
    tostring(_net_safe_hook_status.LoadoutUtils),
    tostring(_net_safe_hook_status.AttachmentUtils),
    tostring(_net_safe_hook_status.PUAE))
if not (_net_safe_hook_status.CosmeticUtils and _net_safe_hook_status.LoadoutUtils
    and _net_safe_hook_status.AttachmentUtils and _net_safe_hook_status.PUAE) then
    pcall(printf, "[cosmetics_tweaker] WARNING: one or more LA peer-sync hooks did NOT register. Restart VT2 before using LA cosmetics in a lobby.")
    mod:info("[startup] LA peer-sync hook registration incomplete; see hook status above")
end

-- #233/#267: a restored offhand is keyed by exact backend item, so its
-- authoritative replay cannot be built until the local inventory has at least
-- one realized weapon slot. PlayerUnit readiness precedes equipment readiness
-- during startup and transitions; consuming the one-shot replay flag in that
-- gap permanently loses the persisted state until the user edits it again.
-- Keep this helper engine-free so the runtime regression can exercise the
-- precise readiness boundary.
mod._la_rebroadcast_inventory_ready = function(inventory)
    return LA_REPLAY_POLICY.inventory_ready(inventory)
end

mod._cos_complete_set_rebroadcast_tick = mod._cos_complete_set_rebroadcast.new({
    policy = LA_REPLAY_POLICY,
    pending = function() return mod._la_self_rebroadcast_pending == true end,
    clear_pending = function() mod._la_self_rebroadcast_pending = false end,
    local_player = function()
        return _local_player_safe(Managers and Managers.player)
    end,
    unit_alive = function(unit) return Unit.alive(unit) end,
    inventory_for = function(unit)
        return ScriptUnit and ScriptUnit.has_extension
            and ScriptUnit.has_extension(unit, "inventory_system") or nil
    end,
    career_for = _wire_career_for_player,
    bridge_ready = function() return LA_BRIDGE.registered == true end,
    loadout_ready = function() return mod._la_skin_safety_installed == true end,
    offhand_restore_ready = function()
        return mod._la_offhand_restore_done == true
    end,
    loadout_cache = function() return mod.loadout_cache end,
    backend_to_armoury = function() return LA_BRIDGE.backend_to_armoury end,
    saved_offhands = function() return LA_PERSIST.get_saved_offhands() end,
    offhand_selection = function() return _offhand_selection end,
    migrate_selection = function(backend_id)
        return _offhand_session_state.migrate_legacy(backend_id)
    end,
    equips_by_unit = function() return _local_la_equips end,
    send_la = _send_la_apply,
    send_mesh = mod._send_offhand_mesh,
    send_custom = mod._cos_send_custom_skin_hands,
    vanilla_fallback = _la_vanilla_fallback,
    now = os.clock,
    retry_delay = 0.25,
    log = function(n)
        _dbg("[ct la-rebroadcast] accepted %d complete-set record(s)", n)
    end,
})

-- VMF calls mod.update once per frame.
-- CLARIFY: la_bridge initialization is deferred to first frame where:
--   1. ItemMasterList is loaded
--   2. Loremasters-Armoury and MoreItemsLibrary mods are present and loaded
-- (v0.9.3.9: la_bridge_enable toggle removed — bridge is unconditionally
-- on. Players who don't want LA cosmetics just don't subscribe to LA.)
-- v0.9.0-dev: warn ONCE when MoreItemsLibrary is missing. PC-B going 4 days
-- with the bridge silently dormant cost a multi-day debug — a clear log line
-- is cheap insurance.
local _la_bridge_missing_dep_logged = false
mod.update = function(dt)
    -- #1145 FIRST: flush at most one deferred wield pulse per wearer, each
    -- re-gated on a live husk game object. Top-of-frame guarantees a full frame
    -- between the queuing burst and the pulse, so a husk destroyed in between is
    -- seen as destroyed and its pulse is dropped.
    mod._cos_rewield.drain()
	CUSTOM_HATS.tick(dt)
    -- v0.9.12-dev: pump persistence-restore queue. SimpleInventoryExtension
    -- .extensions_ready queues a Player for restore; tick processes the queue
    -- once career_name + player_unit are both ready (~1 frame later).
    if LA_PERSIST and LA_PERSIST.tick_pending_restore then
        LA_PERSIST.tick_pending_restore()
    end

    -- #629: keep this edge pending until exact career, both equipped slots,
    -- saved offhand convergence, and every queued/emitted operation are proven.
    mod._cos_complete_set_rebroadcast_tick()

    -- v0.9.66-dev (#233): CLIENT-side self-heal of REMOTE peers' cached LA offhand/
    -- illusion equips after a level transition. Armed by on_game_state_changed
    -- (`_la_reapply_remote_until`). The host's post-transition rebroadcast of its own
    -- equip races the client's load window and is dropped (the "all" send fires ~25ms
    -- before the client's peer_ingame flips true), and nothing re-sends -- so the host's
    -- LA offhand reverted on the client at every mission<->keep transition.
    -- `_la_equips_by_peer` survives (only cleared on peer disconnect), so we hold the
    -- authoritative equip locally and re-drive the recv/retry apply every frame within a
    -- bounded window until the remote wearer's husk spawns and wields the offhand.
    --
    -- v0.9.66-dev fix over v0.9.65-dev, which shipped a SILENT NO-OP (0 lines in the
    -- 2026-07-03 21:15 retest): the old block called ONLY `_ensure_offhand_mesh`, which
    -- early-returns for any non-kind="unit" LA variant -- so a kind="texture" illusion
    -- (the breton shields in that retest get RECV but never a RE-SWAP) was never
    -- re-painted and the whole walk logged nothing. Now we call `_try_apply_by_peer`
    -- (re-paints the texture AND returns true only when the offhand is currently wielded)
    -- and, only when it reports the offhand wielded, `_ensure_offhand_mesh` (re-swaps a
    -- kind="unit" mesh; self-gated/no-op for kind="texture"). Gating the pulse on the
    -- wield state avoids a wasteful melee<->ranged flicker on a husk holding a ranged
    -- weapon and targets exactly the visible-revert case. Both self-gate (paint
    -- idempotent; pulse per-owner 1.5s cooldown + 3-try cap); each (peer|armoury) is
    -- FROZEN once applied so there is no per-frame repaint. Two bounded diagnostics per
    -- window (armed + summary) so a silent no-op can never ship undetected again. No new
    -- hook/RPC/force-load; no World.destroy_unit.
    if mod._la_reapply_remote_until then
        if os.clock() >= mod._la_reapply_remote_until then
            -- Window closed: emit the one-line summary (from the frozen dispositions),
            -- then disarm.
            local st = mod._la_reapply_stats
            if st then
                mod:info("[cos-la-sync] TRANSITION-WALK done applied=%d skipped_unwielded=%d skipped_unresolved=%d",
                    st.applied or 0, st.unwielded or 0, st.unresolved or 0)
                mod._la_reapply_stats = nil
            end
            mod._la_reapply_remote_until = nil
        else
            -- Skip frames without a live network game; the bounded window persists
            -- and retries once vanilla's safe player lookup becomes available.
            local pm = Managers and Managers.player
            local lp = _local_player_safe(pm)
            local local_peer = lp and lp.peer_id or nil
            if local_peer and _la_equips_by_peer then
                local st = mod._la_reapply_stats
                if not st then
                    -- First active frame of this window: arm + count what we hold, so
                    -- an empty cache (nothing to restore) is distinguishable from a walk
                    -- that reached entries but the apply no-op'd.
                    local peer_n, entry_n = 0, 0
                    for p, sl in pairs(_la_equips_by_peer) do
                        if p ~= local_peer and type(sl) == "table" then
                            local has = false
                            for _, e in pairs(sl) do
                                if type(e) == "table" and e.armoury_key
                                    and (e.kind == "offhand" or e.kind == "illusion") then
                                    entry_n = entry_n + 1
                                    has = true
                                end
                            end
                            if has then peer_n = peer_n + 1 end
                        end
                    end
                    st = { applied = 0, unwielded = 0, unresolved = 0, seen = {} }
                    mod._la_reapply_stats = st
                    mod:info("[cos-la-sync] TRANSITION-WALK armed local=%s remote_peers=%d offhand_entries=%d",
                        tostring(local_peer), peer_n, entry_n)
                end
                for peer, slots in pairs(_la_equips_by_peer) do
                    if peer ~= local_peer and type(slots) == "table" then
                        local wu = _wearer_unit_for_peer(peer)
                        for slot_name, eq in pairs(slots) do
                            if type(eq) == "table" and eq.armoury_key
                                and (eq.kind == "offhand" or eq.kind == "illusion") then
                                local dkey = tostring(peer) .. "|" .. tostring(eq.armoury_key)
                                -- Freeze each entry once it has been applied (offhand
                                -- wielded + re-painted/pulsed) so we don't repaint per frame.
                                if st.seen[dkey] ~= "applied" then
                                    if not wu then
                                        st.seen[dkey] = "unresolved"
                                    else
                                        -- v0.9.70-dev (Slice 2 / I3): route through the
                                        -- single reconcile entry point (paint + gated
                                        -- mesh pulse; this drain is a safe pulse context).
                                        -- Semantics preserved: applied only when the
                                        -- offhand is currently wielded.
                                        local applied = mod._la_reconcile(peer, slot_name, "transition", true)
                                        if applied then
                                            st.seen[dkey] = "applied"
                                        else
                                            st.seen[dkey] = "unwielded"
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
                -- Recompute the tallies from the frozen dispositions so the summary is
                -- stable regardless of per-frame churn (an entry migrates
                -- unresolved -> unwielded -> applied and then freezes).
                local a, uw, ur = 0, 0, 0
                for _, d in pairs(st.seen) do
                    if d == "applied" then a = a + 1
                    elseif d == "unwielded" then uw = uw + 1
                    else ur = ur + 1 end
                end
                st.applied, st.unwielded, st.unresolved = a, uw, ur
            end
        end
    end

    if not _la_bridge_init_done then
        if CUSTOM_HATS and not CUSTOM_HATS.registered and ItemMasterList then
            CUSTOM_HATS.register_all(LA_BRIDGE)
        end
        if GK_SET and not GK_SET.registered and ItemMasterList then
            GK_SET.register_all(LA_BRIDGE)
        end
        local has_la  = get_mod("Loremasters-Armoury") ~= nil
        local has_mil = get_mod("MoreItemsLibrary") ~= nil
        if not _la_bridge_missing_dep_logged
            and ItemMasterList
            and (not has_la or not has_mil) then
            if not has_mil then
                mod:info("[LA bridge] dependency missing: MoreItemsLibrary (Workshop ID 1422758813). bridge will stay dormant.")
            end
            if not has_la then
                -- Startup chat is version-only (#570). Keep the actionable
                -- dependency evidence in the console log without buffering a
                -- non-version chat line for the first keep frame.
                mod:info("[LA bridge] dependency missing: Loremaster's Armoury. bridge will stay dormant.")
            end
            _la_bridge_missing_dep_logged = true
        end
        if ItemMasterList
           and has_la
           and has_mil then
            LA_BRIDGE.register_all()
            LA_BRIDGE.install_apply_gate()
            -- v0.8.31 REVERT: skin injection (v0.8.29-30) didn't match
            -- the user's "shield and main weapon are changed separately"
            -- mental model. Restore the row-2 LA merge so LA shields
            -- show up in the offhand picker again. Cross-weapon leak +
            -- preview-texture issues remain known limitations to address
            -- under a different design (likely per-backend_id selection
            -- + backend-mirror persistence).
            _merge_la_offhand_options()
            -- v0.9.71-dev: pools are built - restore persisted shield picks.
            if mod._la_restore_offhand_selections then mod._la_restore_offhand_selections() end
            _la_bridge_init_done = true
        end
    end
    -- Native/CWV hand persistence is independent of LA. Retry until backend
    -- items and (when installed) CWV's generated pools are available.
    if not mod._la_offhand_restore_done and ItemMasterList
            and mod._la_restore_offhand_selections then
        mod._la_restore_offhand_selections()
    end
    -- v0.9.0.4-hotfix: bulk-preload every offhand-pool + custom-illusion unit
    -- on this peer so cross-character shield equips (host's "GK Shield Blue"
    -- etc.) don't crash this peer's husk wield path. Defer until LA bridge
    -- has finished registering (so LA's la_offhand_options_by_weapon_type is
    -- populated and gets included). Even when bridge init is skipped (no MIL),
    -- this still pre-loads the vanilla _offhand_options + _custom_illusions
    -- meshes, which is enough for non-LA picks. Function is idempotent.
    if _force_load_all_offhand_packages then _force_load_all_offhand_packages() end
    if LA_BRIDGE.registered then _install_skin_loadout_safety() end
    -- #376: wait until all local-backend injectors have had time to restore,
    -- then retire exact-item overrides whose item no longer exists. Vanilla's
    -- item interface is a direct backend-mirror lookup
    -- (backend_interface_item_playfab.lua:384-389). CIM's persisted registry
    -- is an additional authority during its mirror-rebuild window.
    if _la_bridge_init_done and not mod._la_persist_prune_done and LA_PERSIST
            and LA_PERSIST.prune_missing_items then
        mod._la_persist_prune_at = mod._la_persist_prune_at or (os.clock() + 10)
        if os.clock() >= mod._la_persist_prune_at then
            -- Issue 695: retried per frame once armed; probe _interfaces before
            -- get_interface so the pre-ready miss path can't warn every frame.
            local backend_mgr = Managers and Managers.backend
            local backend_items = backend_mgr and backend_mgr._interfaces
                and backend_mgr._interfaces.items
                and backend_mgr:get_interface("items")
            if backend_items and backend_items.get_item_from_id then
                local removed = LA_PERSIST.prune_missing_items(function(backend_id)
                    local ok, item = pcall(backend_items.get_item_from_id,
                        backend_items, backend_id)
                    if ok and item then return true end
                    for _, mod_name in ipairs({ "crafting_in_modded", "crafting_in_modded_dev" }) do
                        local cim = get_mod(mod_name)
                        local forged = cim and cim:get("forged_weapons")
                        if type(forged) == "table" and forged[backend_id] then return true end
                    end
                    if not ok then return nil end
                    return false
                end)
                mod._la_persist_prune_done = true
                if printf then printf("[la-state] INSTANCE-PRUNE %d missing item override(s) removed", removed) end
            end
        end
    end
    if mod._glow_scan_tick then mod._glow_scan_tick(dt) end; GlowPicker.ensure_cim_bridge()
    if mod._la_shield_probe_tick then mod._la_shield_probe_tick(dt) end
    -- v0.9.49-dev (#186): deferred one-time scrub of LA's Okri's-Challenge
    -- templates once LA has registered them. No-op after it fires (or while
    -- the toggle is off / LA absent).
    if LA_OKRI and LA_OKRI.tick then LA_OKRI.tick(dt) end
    -- v0.9.2-hotfix: drain LA cos_la_apply emits that deferred because the
    -- network host wasn't resolvable at emit time. Runs every frame; bails
    -- fast when queue is empty.
    if mod._drain_deferred_la_emits then mod._drain_deferred_la_emits() end

    -- v0.9.70-dev (#267, Slice 2b / I9): send the pull-on-ready state request
    -- armed by on_game_state_changed. Client-only (the host owns the store);
    -- waits until a host peer_id is resolvable, then fires exactly once per
    -- arming. The request's arrival at the host proves this peer is a live
    -- session member, so the host's targeted replies cannot lose the
    -- pre-ingame race that killed the push model.
    if mod._la_state_pull_pending then
        if _is_local_server() then
            mod._la_state_pull_pending = nil
        else
            -- v0.9.71-dev: retry-until-acked. One send proved lossy in the
            -- 2026-07-06 session (packets to/from a still-loading peer vanish
            -- silently); the pull now repeats every 5s until the host's
            -- cos_la_state_ack arrives, capped at 8 attempts.
            local st = mod._la_state_pull_pending
            if type(st) ~= "table" then st = { attempts = 0, next_at = 0 }; mod._la_state_pull_pending = st end
            local now_p = os.clock()
            if now_p >= (st.next_at or 0) then
                local pull_host = _host_peer_id()
                -- v0.9.72-dev: after leaving a session the resolver can hand
                -- back OUR OWN peer id while _is_local_server() is still
                -- transiently false (18:30:42 log: 8 retries against self).
                -- A self-targeted pull is meaningless - drop the arming.
                local self_peer = _local_peer_id_quick()
                if pull_host and self_peer and pull_host == self_peer then
                    mod._la_state_pull_pending = nil
                    pull_host = nil
                end
                if pull_host then
                    if st.attempts >= 8 then
                        if printf then printf("[la-state] STATE-PULL GAVE UP after %d unacked attempts (host=%s) - re-arm queued for next replay edge",
                            st.attempts, tostring(pull_host)) end
                        mod._la_state_pull_pending = nil
                        -- #267 follow-up: exhaustion is no longer terminal for
                        -- the session. The next bounded replay edge (peer-ready /
                        -- session-ready / lobby-return) re-arms the pull so a
                        -- cold-joiner that lost the whole 8-attempt window still
                        -- gets another chance instead of running the rest of the
                        -- session with no replayed store.
                        mod._la_state_pull_exhausted = true
                    else
                        st.attempts = st.attempts + 1
                        st.next_at = now_p + 5
                        if printf then printf("[la-state] STATE-PULL req -> host=%s (attempt %d/8)",
                            tostring(pull_host), st.attempts) end
                        mod:network_send("cos_la_state_req", pull_host, COS_RPC_SCHEMA, {})
                    end
                end
            end
        end
    end

    -- v0.9.71-dev: execute deferred peer purges (see the remove_player hook -
    -- transitions schedule-and-cancel; only genuine leaves reach execution).
    if mod._la_tick_peer_purges then mod._la_tick_peer_purges() end

    -- v0.9.0-dev: TPE per-frame tick was previously in a now-deleted earlier
    -- mod.update definition that this one overwrote. Restoring here.
    if TPE and TPE.update then TPE.update(dt) end

    -- v0.9.0-dev: pump glow-state broadcast pending re-emits.
    if mod._glow_sync_tick then mod._glow_sync_tick(dt) end

    -- #574: local material-only convergence for a snapshot that beat the
    -- remote husk's equipment spawn. Quarter-second cadence, 40 attempts/10s
    -- maximum, and no network send in the tick.
    if mod._cos574_glow_rehydrate_tick then mod._cos574_glow_rehydrate_tick() end

    -- v0.8.67-dev: drain the cos_la_apply pending queue. Entries that can't
    -- apply yet (wearer unit not spawned, husk not wielding the right slot)
    -- get retried each frame until they succeed or their 5-second deadline
    -- expires. Bounded retry prevents the queue from leaking on rare cases
    -- where a wearer's unit never spawns (e.g. player disconnected before
    -- replicating into our game session).
    if _la_pending_apply and #_la_pending_apply > 0 then
        local now = os.clock()
        local kept = {}
        for i = 1, #_la_pending_apply do
            local entry = _la_pending_apply[i]
            local wp, slot, deadline = entry[1], entry[2], entry[6]
            -- v0.9.70-dev (Slice 2 / I3): retries route through the single
            -- reconcile entry point (paint + gated mesh pulse; mod.update is a
            -- safe pulse context). reason=="no-entry" is terminal -- a revert
            -- deleted the store entry, so retrying would re-impose a cosmetic
            -- the wearer already dropped.
            local applied_now, reason = mod._la_reconcile(wp, slot, "retry", true)
            -- #518: "deus-yield" is terminal like "no-entry" - retrying inside a
            -- deus run can never succeed and would just spin to the deadline.
            if not applied_now and reason ~= "no-entry" and reason ~= "deus-yield" and now < deadline then
                kept[#kept + 1] = entry
            end
        end
        _la_pending_apply = kept
    end
end

local _cos_glow_probe = mod:dofile("scripts/mods/cosmetics_tweaker/_cos_glow_probe")
_cos_glow_probe.install(mod, {
    local_player_safe = _local_player_safe, is_unit = _is_unit, flush_log = _flush_log,
})
local _wielded_units_for_probe = _cos_glow_probe.wielded_units_for_probe
-- Spawn pipeline: detect units that match one of our cloned items and push
-- them into LA's queue. AttachmentUtils is a global table so we hook with
-- table form (string form would never resolve).
if rawget(_G, "AttachmentUtils") then
    -- Residency check: Application.can_get("unit", path) is the engine's
    -- authoritative "will World.spawn_unit succeed?" answer. Fail-open (treat as
    -- resident) when the API is unavailable or errors, so we never wrongly
    -- suppress a genuinely spawnable unit. Block-scoped so it does not consume a
    -- main-chunk local slot (Lua 5.1 200-local ceiling).
    local function _unit_resident(path)
        if type(path) ~= "string" or path == "" then return true end
        local cg = Application and Application.can_get
        if not cg then return true end
        local ok, res = pcall(cg, "unit", path)
        if not ok then return true end
        return res and true or false
    end

    -- issue #270 (crash A) -- residency gate on the attachment SPAWN choke point.
    -- Every hat/attachment apply path (PlayerUnitAttachmentExtension.create_
    -- attachment, PlayerHuskAttachmentExtension.create_attachment, spawn_resynced_
    -- loadout) funnels through AttachmentUtils.create_attachment, which at
    -- attachment_utils.lua:16 spawns `item_units.unit` via UnitSpawner.spawn_
    -- local_unit -> World.spawn_unit. On a viewer machine the wearer's swapped
    -- headpiece package is often NOT resident (the mod's hat-swap path equips
    -- outside the native inventory_list declaration, so viewers never preload
    -- it), and World.spawn_unit C-asserts (c_api_world.cpp:67), CTD'ing the
    -- viewer. `item_units.unit` is provably identical to `item_data.unit`
    -- (backend_utils.lua:153 `unit = item_data.unit`; the skin block only
    -- overrides left/right_hand/ammo units, never `unit`), so we gate on
    -- item_data.unit here BEFORE native spawns or links anything. Non-resident ->
    -- skip cleanly, returning the SAME empty slot_data shape vanilla produces when
    -- an item has no `.unit` (attachment_utils.lua:38-44). Viewer sees no hat
    -- (ugly) instead of crashing. NOTE: returning early also avoids native's
    -- unit=nil path calling AttachmentUtils.link(target=nil) -> Unit.node crash.
    if AttachmentUtils.create_attachment then
        mod:hook(AttachmentUtils, "create_attachment", function(func, world, owner_unit, attachments, slot_name, item_data, show)
            -- #612: never substitute a custom unit here. The Encarmine item
            -- points at the exact native Laurel donor and is painted after the
            -- attachment exists.
            local spawn_item = item_data
            local path = spawn_item and spawn_item.unit
            local is_headpiece = slot_name == "slot_hat"
            if is_headpiece and type(path) == "string" and path ~= ""
                    and not _unit_resident(path) then
                mod:info("[cos-hat] SKIP non-resident headpiece=%s slot=%s owner=%s (viewer package not resident; no hat instead of crash)",
                    tostring(path), tostring(slot_name),
                    tostring(type(owner_unit) == "userdata" and "unit" or owner_unit))
                return { unit = nil, name = item_data and item_data.name, item_data = item_data }
            end
            local slot_data = func(world, owner_unit, attachments, slot_name, spawn_item, show)
            if slot_data and item_data and item_data.name == CUSTOM_HATS.ITEM_KEY then
                CUSTOM_HATS.apply_surface(slot_data.unit, "live-attachment")
            end
            return slot_data
        end)
    end

    -- #270/#950: reject dead units before Unit.node's C assertion, but preserve
    -- every valid pair when a custom mesh omits optional attachment nodes.
    mod._cos_attachment_link_policy.install(mod, AttachmentUtils, LA_BRIDGE, Unit)
end

-- LA hooks World.link_unit too — some hats are linked via the lower-level
-- World API rather than AttachmentUtils. Cover both. World.link_unit signature:
-- World.link_unit(world, child_unit, child_node, parent_unit, parent_node)
if rawget(_G, "World") and World.link_unit then
    mod:hook_safe(World, "link_unit", function(world, child_unit, child_node, parent_unit, parent_node)
        if not LA_BRIDGE.registered then return end
        if type(child_unit) ~= "userdata" then return end
        if not Unit.alive(child_unit) then return end
        if not Unit.has_data(child_unit, "unit_name") then return end
        LA_BRIDGE.maybe_queue_unit(world, child_unit, Unit.get_data(child_unit, "unit_name"))
    end)
end

local function _spawn_item_unit_la_hook(self, unit)
    if not LA_BRIDGE.registered then return end
    if type(unit) ~= "userdata" then return end

    local world = self._world or self.world
    local spawning = self._cos_la_spawning
    _dbg("[LA preview] _spawn_item_unit spawning=%s world=%s", tostring(spawning), tostring(world))
    if spawning then
        local ok = LA_BRIDGE.queue_unit_direct(world, unit, spawning)
        _dbg("[LA preview]   queue_unit_direct result=%s", tostring(ok))
        return
    end

    if Unit.has_data(unit, "unit_name") then
        LA_BRIDGE.maybe_queue_unit(world, unit, Unit.get_data(unit, "unit_name"))
    else
        LA_BRIDGE.suppress_orphan(unit)
    end
end

-- v0.9.5: full mod:hook (was hook_safe) so we can fold the MH embed's
-- texture/particle/anim-extension work into the same hook instead of MH
-- registering its own. Eliminates the boot rehook warning. MH calls
-- happen BEFORE vanilla; LA bridge queue happens AFTER vanilla (matching
-- the prior hook_safe ordering).
-- v0.9.86-dev (#513): signature extended with skip_wield_anim - vanilla
-- _spawn_item passes it as the 8th arg (world_hero_previewer.lua:917) and the
-- previous 7-param wrapper silently dropped it (multi-arg truncation, VMF_RECIPES 2).
local function _spawn_item_unit_combined(func, self, unit, item_slot_type, item_template, attachment_node_linking, scene_graph_links, material_settings, skip_wield_anim)
    -- MH work before vanilla (only when embed is active, not dormant).
    if MH_EMBED and not MH_EMBED.dormant and unit then
        MH_EMBED.replace_textures(unit)
        MH_EMBED.add_particles(unit, self.world)
        MH_EMBED.attach_anim_extension(unit)
    end
    -- Vanilla.
    local r1, r2 = func(self, unit, item_slot_type, item_template, attachment_node_linking, scene_graph_links, material_settings, skip_wield_anim)
    if item_slot_type == "hat" then
        local authored_key = self._cos_la_spawning and LA_BRIDGE.backend_to_armoury[self._cos_la_spawning]
            or (self._cos_score_hat and self._cos_score_hat.armoury_key)
        if authored_key and CUSTOM_HATS.is_custom_identity(authored_key) then
            CUSTOM_HATS.apply_surface(unit, "hero-preview")
        elseif authored_key and GK_SET.resolve_variant(authored_key) then
            GK_SET.apply_variant_to_unit(authored_key, unit, "hero_preview")
        end
    end
    -- v0.9.7: stash unit→backend_id for previewer-spawned weapon units so
    -- the glow picker's live preview can resolve the right item. The
    -- backend_id was captured on `self` by the equip_item hook below.
    if unit and self._cos_current_equip_backend_id and mod._unit_to_backend_id then
        mod._unit_to_backend_id[unit] = self._cos_current_equip_backend_id
    end
    -- LA bridge queue after vanilla returns.
    _spawn_item_unit_la_hook(self, unit)
    -- v0.9.86-dev (#513): score-screen LA hat PAINT. _cos_score_hat is stamped by
    -- the HeroPreviewer.equip_item hook only on TeamPreviewer-owned previewers whose
    -- wearer has a synced LA hat. kind="texture" hats need apply_new_skin_from_texture
    -- on the JUST-SPAWNED hat unit or the mesh renders in vanilla colours
    -- (LA_SYNC_MODEL 6.2); kind="unit" meshes carry their own baked material and the
    -- call no-ops (variant.textures nil). Mirrors the husk hat paint call shape.
    if self._cos_score_hat and item_slot_type == "hat"
        and not CUSTOM_HATS.is_custom_identity(self._cos_score_hat.armoury_key)
        and type(unit) == "userdata" and Unit.alive(unit) then
        local la = get_mod("Loremasters-Armoury")
        if la and type(la.apply_new_skin_from_texture) == "function" then
            local info = self._cos_score_hat
            LA_BRIDGE._bridge_active = true
            local ok, err = pcall(la.apply_new_skin_from_texture, info.armoury_key, self.world, info.vanilla_key, unit)
            LA_BRIDGE._bridge_active = false
            if printf then printf("[la-state] SCORE-HAT paint key=%s ok=%s%s",
                tostring(info.armoury_key), tostring(ok),
                ok and "" or (" err=" .. tostring(err))) end
        end
    end
    return r1, r2
end
mod:hook("HeroPreviewer", "_spawn_item_unit", _spawn_item_unit_combined)
mod:hook("MenuWorldPreviewer", "_spawn_item_unit", _spawn_item_unit_combined)

-- v0.9.8.2: the `_equip_item_capture_bid` hook_safe pair collided with the
-- existing equip_item mod:hook registrations (VMF rehook warnings); the bid
-- stash is FOLDED into those hooks - do not re-add a separate registration.

local _cos_la_commands = mod:dofile("scripts/mods/cosmetics_tweaker/_cos_la_commands")
_cos_la_commands.install(mod, {
    la_bridge = LA_BRIDGE, local_career_name = _local_career_name, flush_log = _flush_log,
})
-- #154: mirror slot-keyed weapon-side LA entries under the wearer's wielded
-- TEMPLATE at the reconcile edge (the husk mesh gate + repaint match templates
-- only), and sweep mirror aliases on revert. Wraps mod._la_reconcile +
-- mod._la_apply_revert_recv, so it MUST attach after both definitions above.
mod:dofile("scripts/mods/cosmetics_tweaker/_cos_husk_cache_bridge").attach(mod, {
    managers = function() return Managers end, script_unit = ScriptUnit,
    probe = PROBE, printf = rawget(_G, "printf"),
})
-- ============================================================
-- Glow Picker integration (v0.9.1-dev — M1 scaffold)
-- ============================================================
-- Hooks the cosmetic-changing screen lifecycle to give the picker its own
-- input + draw phases. M1: popup panel renders, close button works,
-- placeholder text confirms the chain is alive. M2: replace placeholder with
-- per-component R/G/B + intensity sliders + persistence.
--
-- The picker draws AFTER the host window's own draw, layering above the
-- cosmetic grid. Input handling fires BEFORE the host window's input so
-- popup clicks (close button, slider drags) intercept before reaching the
-- cosmetic grid behind it.

-- Resolve the backend_id of the currently-selected cosmetic slot. Used to
-- key per-item glow customization. Returns nil if no slot is selected, the
-- selected slot is empty, or the selected slot is not a weapon (hats/skins
-- don't carry glow shader variables — glow customization only applies to
-- weapon meshes).
local function _selected_slot_backend_id_and_data(host_window)
    local idx = host_window and host_window._selected_cosmetic_slot_index
    local items = host_window and host_window._equipment_items
    if not idx or not items then return nil, nil end
    local item = items[idx]
    if not item then return nil, nil end
    -- item here is the backend item record (carries backend_id and data).
    return item.backend_id, item
end

-- M1.2: throttled draw-hook tracer so we can confirm whether the hook is
-- firing while the user is on the screen. First fire is console-only (#570).
mod._glow_hook_fired_once = mod._glow_hook_fired_once or {}

local function _glow_hook_trace(class_name, event)
    local key = class_name .. ":" .. event
    if not mod._glow_hook_fired_once[key] then
        mod._glow_hook_fired_once[key] = true
        pcall(printf, "[cos:570] [glow_picker:hook] FIRST FIRE %s (open=%s)", key, tostring(GlowPicker.is_open()))
        mod:info("[glow_picker:hook] FIRST FIRE %s (open=%s)", key, tostring(GlowPicker.is_open()))
    end
end

-- M1.4: scoped hooks on the TWO verified-correct screen classes only.
-- Earlier diag pass blindly hooked five candidate windows including ones
-- whose draw method doesn't exist (HeroWindowItemCustomization has _draw,
-- not draw) AND whose on_exit was already hooked elsewhere in this file
-- (rehook warning). Fixed here.
--
-- 1) HeroWindowCosmeticsLoadout (loadout grid) — has public `draw`,
--    `update`, `on_exit`. ALL three safe to hook here; no existing hooks.
-- 2) HeroWindowItemCustomization (per-weapon illusion-change) — has
--    `update` (line 459 of source) and INTERNAL `_draw(self, input_service,
--    dt)` at source line 1004. NO public `draw`. on_exit ALREADY hooked
--    elsewhere in this file (don't re-hook it here).
local function _resolve_input_service(self)
    return self.parent and self.parent.window_input_service
        and self.parent:window_input_service()
end

-- (1) HeroWindowCosmeticsLoadout — full hook set.
mod:hook_safe("HeroWindowCosmeticsLoadout", "on_exit", function(self, params)
    _glow_hook_trace("HeroWindowCosmeticsLoadout", "on_exit")
    GlowPicker.close()
end)

mod:hook_safe("HeroWindowCosmeticsLoadout", "update", function(self, dt, t)
    _glow_hook_trace("HeroWindowCosmeticsLoadout", "update")
    if not GlowPicker.is_open() then return end
    GlowPicker.handle_input(_resolve_input_service(self))
end)

mod:hook_safe("HeroWindowCosmeticsLoadout", "draw", function(self, dt)
    _glow_hook_trace("HeroWindowCosmeticsLoadout", "draw")
    if not GlowPicker.is_open() then return end
    local ui_renderer = self.ui_top_renderer or self.ui_renderer
    GlowPicker.draw(ui_renderer, _resolve_input_service(self), dt)
end)

-- (2) HeroWindowItemCustomization — update + _draw (no public draw).
--     on_exit deliberately NOT re-hooked here.
mod:hook_safe("HeroWindowItemCustomization", "update", function(self, dt, t)
    _glow_hook_trace("HeroWindowItemCustomization", "update")
    if not GlowPicker.is_open() then return end
    GlowPicker.handle_input(_resolve_input_service(self), self)
end)

mod:hook_safe("HeroWindowItemCustomization", "_draw", function(self, input_service, dt)
    _glow_hook_trace("HeroWindowItemCustomization", "_draw")
    if not GlowPicker.is_open() then return end
    -- v0.9.3.2-hotfix: HeroWindowItemCustomization stores renderers with
    -- UNDERSCORE prefix (`self._ui_top_renderer` per source line 1006),
    -- whereas HeroWindowCosmeticsLoadout stores them WITHOUT the prefix
    -- (`self.ui_top_renderer` per source line 167). Different naming
    -- conventions between sibling screens — check both forms. PC-A's
    -- glow picker test 2026-05-21 17:55-17:56 hit this: 7 frames of
    -- `ui_renderer is nil` echoed to chat because the non-underscore
    -- lookup returned nil.
    local ui_renderer = self._ui_top_renderer or self._ui_renderer
        or self.ui_top_renderer or self.ui_renderer
    GlowPicker.draw(ui_renderer, input_service, dt, self)
end)

mod:command("glow_picker_hooks", "List which cosmetic-screen draw hooks have fired this session", function()
    mod:echo("[glow_picker:hooks] fired so far:")
    local n = 0
    for k, _ in pairs(mod._glow_hook_fired_once) do
        mod:echo("  - %s", k)
        n = n + 1
    end
    if n == 0 then mod:echo("  (none — go to the loadout grid or click a weapon to open the illusion-change window)") end
    mod:echo("[glow_picker:hooks] GlowPicker.is_open=%s built=%s",
        tostring(GlowPicker.is_open()), tostring(GlowPicker._built))
end)

-- Manual entry point for M1 testing: `/glow_picker` chat command opens the
-- popup from anywhere (no cosmetic-screen requirement). Useful for verifying
-- the popup renders before we land the cosmetic-screen button injection.
-- The popup otherwise opens only from the in-view editor button.
mod:command("glow_picker", "Open the glow customizer popup (M1 scaffold; debug-only entry point)", function()
    mod:echo("[glow_picker] command fired. v=%s open_before=%s",
        MOD_VERSION, tostring(GlowPicker.is_open()))
    if GlowPicker.is_open() then
        GlowPicker.close()
        mod:echo("[glow_picker] closed")
        return
    end
    -- v0.9.8.9: resolve backend_id from `mod._unit_to_backend_id` instead of
    -- the non-existent `slot_data.backend_id` field. Vanilla `slot_data`
    -- from `ext:get_wielded_slot_data()` carries item_data + unit refs but
    -- NOT a backend_id field — `slot_data.backend_id` was always nil,
    -- which is why every prior session's log showed
    -- `[glow_picker] opened for backend_id=nil`. With nil bid, the picker's
    -- _live_preview bailed → mod._per_item_glow_runtime[nil] never written
    -- → _apply_glow_to_unit never found a per-item override. Picker was
    -- effectively dead on the chat-command path.
    --
    -- Empirical evidence: every recent log shows `opened for backend_id=nil`,
    -- never a non-nil UUID. Confirmed across PC-A sessions 2026-05-21+.
    --
    -- mod._unit_to_backend_id is the SAME map _apply_glow_to_unit reads.
    -- Using it ensures the picker's write key matches the apply's read key.
    -- The map is populated by GearUtils.create_equipment (in-game) +
    -- HeroPreviewer/MenuWorldPreviewer.equip_item (cosmetic preview).
    local units, slot_data = _wielded_units_for_probe()
    local bid = nil
    if units and units[1] and units[1].unit and mod._unit_to_backend_id then
        bid = mod._unit_to_backend_id[units[1].unit]
    end
    mod:echo("[glow_picker] resolved backend_id=%s (from _unit_to_backend_id[wielded_unit])",
        tostring(bid))
    GlowPicker.open_for(bid, slot_data)
    mod:echo("[glow_picker] open_after=%s built=%s. If you're NOT on a cosmetic menu, popup won't render — go to the cosmetic loadout screen. Then run /glow_picker_hooks to see which hook fires.",
        tostring(GlowPicker.is_open()), tostring(GlowPicker._built))
end)

-- v0.9.9.4-dev: switched from SimpleInventoryExtension.wield to _wield_slot.
-- _tpe.lua already hooks .wield, and VMF silently drops a second hook_safe on
-- the same Class+method (memory: reference_ct_husk_hook_shadow_tpe).
-- v0.9.54-dev (#203): SIGNATURE FIX + LOCAL LA OFFHAND RE-APPLY. Vanilla
-- SimpleInventoryExtension._wield_slot is `(self, equipment, slot_data, unit_1p,
-- unit_3p, buff_extension)` — the prior hook's `(self, world, equipment,
-- slot_name)` names were misaligned (harmless, diagnostics-only, but the trace
-- logged a unit where it meant the slot name). Corrected here.
mod:hook_safe("SimpleInventoryExtension", "_wield_slot", function(self, equipment, slot_data, unit_1p, unit_3p, buff_extension)
    local pm = Managers and Managers.player
    local lp = _local_player_safe(pm)
    if not lp then return end
    if self._unit ~= lp.player_unit then return end
    local wielded_slot = (slot_data and slot_data.id)
        or (self._equipment and self._equipment.wielded_slot)
    -- v0.9.43-dev TRANSITION trace: LOCAL player wield-slot change. Repro #4 is
    -- "host switches to secondary weapon and back" → this fires twice (to
    -- slot_ranged, then back to slot_melee). Logs from→to via self._ct_last_wielded.
    _trace("TRANSITION WIELD local from=%s to=%s",
        tostring(self._ct_last_wielded), tostring(wielded_slot))
    self._ct_last_wielded = wielded_slot; mod._cos518_owner_wield(slot_data, wielded_slot) -- #518 owner-wield probe (see _cos_518_probe.lua)

    -- v0.9.54-dev (#203): RE-APPLY the local player's committed LA offhand on
    -- EVERY local wield. Vanilla _wield_slot only toggles set_unit_visibility on
    -- the already-spawned units (no respawn, no create_equipment), so the LA
    -- shield paint was lost on the player's OWN screen at mission entry and on a
    -- primary↔secondary↔back swap — the husk path re-applies for peers, but
    -- nothing did for the local body (the comment that used to sit here said
    -- exactly that). Mirror the working husk _wield_slot re-paint: read
    -- _la_equips_by_peer[local_peer] (the same synced cache the husk uses,
    -- populated on Apply via _send_la_apply) and re-paint the wielded shield via
    -- the SAME _apply_la_on_unit helper. ADDITIVE (paint is idempotent) + GATED
    -- (the #204 mesh-mismatch warp guard inside _apply_la_on_unit degrades a
    -- non-swapped kind="unit" mesh to plain rather than warping). Does NOT touch
    -- the husk path. A kind="unit" shield whose mesh-swap was skipped at spawn
    -- stays plain here (recovering the mesh needs a respawn — out of scope).
    do
        local local_peer = lp.peer_id
        local equips = local_peer and _la_equips_by_peer and _la_equips_by_peer[local_peer]
        if equips and self._unit and Unit.alive(self._unit) then
            local item_data = slot_data and slot_data.item_data
            local wielded_template = item_data and item_data.template
            if wielded_template then
                for stored_key, entry in pairs(equips) do
                    -- OFFHAND only: the reported drop is the LA shield, and the
                    -- offhand path repaints via the safe local texture paint
                    -- (_paint_offhand_textures_locally). kind="illusion" is
                    -- deliberately EXCLUDED — its re-apply routes through LA's
                    -- apply_new_skin_from_texture, which permanently mutates
                    -- WeaponSkins/IML inventory_icons (DEVELOPMENT.md "NEVER call
                    -- LA.apply_new_skin_from_texture"); re-running that on every
                    -- local wield would amplify that mutation. (The husk path
                    -- already handles illusions remotely; a local illusion drop,
                    -- if reported, is a separate fix.)
                    -- #518: skip inside a deus run - the CW weapon shares the
                    -- keep weapon's TEMPLATE (deus items clone the base item),
                    -- so this template-keyed re-apply was the observed stomper
                    -- of deus upgrade skins. The reconcile/_apply_la_on_unit
                    -- gates also cover this; skipping here keeps the REAPPLY
                    -- probe/trace lines truthful.
                    if entry and entry.armoury_key and entry.kind == "offhand"
                        and stored_key == wielded_template
                        and not mod._la_deus_weapon_yield() then
                        _trace("LOCAL wield-reapply stored_key=%s kind=%s armoury=%s slot=%s",
                            tostring(stored_key), tostring(entry.kind),
                            tostring(entry.armoury_key), tostring(wielded_slot))
                        -- [cos:sync] #203: the local player's OWN body re-applying
                        -- its committed LA offhand on wield (primary<->secondary
                        -- swap / mission entry). peer=local. Absence of this line
                        -- for a wield where the shield visibly drops = the cache
                        -- didn't hold the entry (attribution for the #203 drop).
                        if PROBE then
                            PROBE.emit("cos:sync",
                                "local_wield/" .. tostring(wielded_slot) .. "/" .. tostring(stored_key),
                                string.format("peer=local slot=%s template=%s key=%s decision=REAPPLY",
                                    tostring(wielded_slot), tostring(stored_key), tostring(entry.armoury_key)))
                        end
                        -- v0.9.70-dev (#264/#234, Slice 2 / I3): route through the
                        -- single reconcile entry point. allow_pulse=false (inside a
                        -- wield body); a stale kind="unit" mesh on the local body is
                        -- deferred to the pending drain's safe pulse -- previously a
                        -- skipped spawn-time swap was declared out of scope here.
                        pcall(mod._la_reconcile, local_peer, stored_key, "local-wield", false)
                    end
                end
            end
        end
    end

    -- Publish the applied state for the weapon that actually became wielded.
    -- Equipment spawn order is not wield order, so this is the authoritative
    -- place to switch/clear the coop payload after restart or weapon swapping.
    do
        local bid
        local glow_units = {}
        if slot_data and type(slot_data) == "table" then
            for _, field in ipairs({ "right_unit_1p", "left_unit_1p", "right_unit_3p", "left_unit_3p" }) do
                local unit = slot_data[field]
                if unit then
                    glow_units[#glow_units + 1] = unit
                    if mod._unit_to_backend_id and mod._unit_to_backend_id[unit] then
                        bid = mod._unit_to_backend_id[unit]
                    end
                end
            end
        end
        local item_data = slot_data and slot_data.item_data
        local skin = slot_data and slot_data.skin
        if bid then
            -- Lobby leave / role transitions rebuild equipment without opening
            -- the picker. Re-read the durable owner store before selecting the
            -- active payload, then repaint the newly-visible 1P and 3P units.
            GlowPicker.restore_runtime_for(bid, { skin = skin })
        end
        if mod._cos.bind_glow_unit then
            for _, unit in pairs(glow_units) do
                mod._cos.bind_glow_unit(unit, bid, skin, wielded_slot,
                    item_data and item_data.name, item_data and item_data.template)
            end
        end
        local next_state = bid and mod._per_item_glow_runtime and mod._per_item_glow_runtime[bid] or nil
        local next_identity = bid and mod._per_item_glow_identity_runtime
            and mod._per_item_glow_identity_runtime[bid] or nil
        mod._active_per_item_glow_skin = next_state and (skin or "") or nil
        mod._active_per_item_glow_slot = next_state and wielded_slot or nil
        mod._active_per_item_glow_item_name = next_state and item_data and item_data.name or nil
        mod._active_per_item_glow_item_template = next_state and item_data and item_data.template or nil
        if mod._active_per_item_glow ~= next_state
            or mod._active_per_item_glow_identity ~= next_identity then
            mod._active_per_item_glow = next_state
            mod._active_per_item_glow_identity = next_identity
            if mod._emit_per_item_glow then mod._emit_per_item_glow() end
        end
        mod._cos.apply_glow_override(glow_units, lp.peer_id)
        if next_state then
            _cos574_log("rehydrate path=local_wield bid=%s skin=%s slot=%s active=true units=%d",
                tostring(bid), tostring(skin), tostring(wielded_slot), #glow_units)
        end
    end

end)

local _cos_runtime_checks = mod:dofile("scripts/mods/cosmetics_tweaker/_cos_runtime_checks")
_cos_runtime_checks.install(mod, _rt_register, {
    la_persist = LA_PERSIST, score_identity = SCORE_IDENTITY,
    husk_identity = mod._cos_husk_identity,
    rpc_schema = COS_RPC_SCHEMA, composite_icons = COMPOSITE_ICONS,
    custom_hats = CUSTOM_HATS, appearance_fade = mod._cos_appearance_fade,
    la_bridge = LA_BRIDGE, gk_set = GK_SET,
    glow_picker = GlowPicker, weapon_poses = WEAPON_POSES,
    shield_icon_owner_item_types = _SHIELD_ICON_OWNER_ITEM_TYPES,
    offhand_options = _offhand_options, multi_mount_item_types = _MULTI_MOUNT_ITEM_TYPES,
    dual_wield_pools = _DUAL_WIELD_POOLS, offhand_names = OFFHAND_NAMES,
    item_presentation = ITEM_PRESENTATION,
    shield_pools_by_item_type = _SHIELD_POOLS_BY_ITEM_TYPE,
    dbg = _dbg, dbg_alert = _dbg_alert, ui_dump = UI_DUMP,
    custom_skin_keys = _custom_skin_keys,
    custom_illusion_sync = CUSTOM_ILLUSION_SYNC,
    offhand_preload_lifecycle = OFFHAND_PRELOAD_LIFECYCLE, mh_embed = MH_EMBED,
    cwv_peer_identity = mod._cos_cwv_peer_identity,
    la_instance_policy = mod._la_instance_policy,
    modded_illusion_swap_owner = mod._cos_modded_illusion_swap_owner, active_skin = _cos_active_skin, offhand_selection = _offhand_selection, -- #25
    issue704_picker_family = function(surface, family, _, owner_item_type)
        return mod._cos.classify_issue704_picker_family(surface, family, mod._cwv_dual_offhand_contract, owner_item_type)
    end,
})
-- ============================================================
-- Moonfire Bow cosmetic AOE puff (moved from weapon_tweaker 2026-06-29)
-- ============================================================
-- Spawns the small blue moonfire impact puff on every Moonfire Bow (we_deus_01*)
-- arrow hit. Cosmetic only — no damage. The gameplay "pre-nerf AOE revert" stays in
-- weapon_tweaker (Weapon Overrides); when it's on it already spawns puffs as part of
-- the detonation, so we skip here to avoid doubling. Hooks BOTH the shooter's
-- PlayerProjectileUnitExtension and every other peer's PlayerProjectileHuskExtension
-- (same impact methods + fields wt used) so the puff shows on every screen. The
-- arrow's own impact FX rides the equipped Moonfire Bow's package, so create_particles
-- is safe whenever a moonfire arrow hits.
local _COS_MOONFIRE_PUFF_FX = "fx/wpnfx_we_deus_01_impact"

local function _cos_is_moonfire_arrow(item_name)
    return item_name ~= nil and string.sub(item_name, 1, 10) == "we_deus_01"
end

local function _cos_moonfire_puff_on_hit(self, hit_position)
    if not mod:get("cos_moonfire_cosmetic_puff") then return end
    if not _cos_is_moonfire_arrow(self.item_name) then return end
    -- wt's AOE revert already puffs as part of the detonation — don't double up.
    local wt = get_mod("wt")
    if wt and wt:get("moonfire_aoe_revert") then return end
    local world = self._world
    if not world or not hit_position then return end
    World.create_particles(world, _COS_MOONFIRE_PUFF_FX, hit_position, Quaternion.identity())
end

do
    local _moonfire_classes = { "PlayerProjectileUnitExtension", "PlayerProjectileHuskExtension" }
    local _moonfire_methods = { "hit_enemy", "hit_level_unit", "hit_non_level_unit" }
    for _, class_name in ipairs(_moonfire_classes) do
        local cls = rawget(_G, class_name)
        if cls then
            for _, method_name in ipairs(_moonfire_methods) do
                if cls[method_name] then
                    mod:hook_safe(cls, method_name, function(self, impact_data, hit_unit, hit_position)
                        _cos_moonfire_puff_on_hit(self, hit_position)
                    end)
                end
            end
        end
    end
end
