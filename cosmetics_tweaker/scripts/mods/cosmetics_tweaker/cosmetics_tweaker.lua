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

local MOD_VERSION = "0.9.195-dev"
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

-- v0.9.41-dev (#150): set true ONLY while inside our GearUtils.create_equipment
-- wrap — i.e. when the LIVE in-keep / in-mission player body is (re)spawning its
-- equipment. The BackendUtils.get_item_units hook reads this to tell a live-body
-- spawn apart from a customization PREVIEWER spawn (both pass the same
-- backend_id). While the customization screen is open we suppress the
-- browse-time offhand mesh override on the live body so mousing/clicking
-- illusions previews ONLY on the preview pane, never the equipped weapon on the
-- player's own body; the live body commits on screen exit via the existing
-- deferred broadcast + pulse-wield (on_exit below). Single-threaded Lua, so the
-- set→read→restore bracket is safe.
local _in_create_equipment = false

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

mod:dofile("scripts/mods/cosmetics_tweaker/_cos_518_probe") -- #518 bounded solo-visible probes: printf-only emitter + owner-wield / paint-skip / husk-miss helpers wired into the three sites below

if BackendUtils then
    mod:hook(BackendUtils, "get_item_units", function(func, item_data, backend_id, skin, career_name)
        local result = func(item_data, backend_id, skin, career_name)
        if not result then return result end

        -- v0.9.86-dev (#513): score-screen previewer LA hat MESH swap. The bracket
        -- (mod._cos_score_hat_swap) is set by the HeroPreviewer.equip_item hook ONLY
        -- around its single synchronous vanilla call, while the end-of-round
        -- TeamPreviewer lineup equips a wearer's synced LA hat. Vanilla equip_item
        -- reads result.unit for BOTH the spawn path and the package preload list
        -- (world_hero_previewer.lua:740/759), so swapping here makes the previewer
        -- itself load + spawn the LA mesh. Residency was pre-gated at the bracket
        -- set site (Application.can_get), mirroring the #270 attachment gate.
        if mod._cos_score_hat_swap and item_data and item_data.slot_type == "hat" and result.unit then
            local prev_unit = result.unit
            result.unit = mod._cos_score_hat_swap
            if printf then printf("[la-state] SCORE-HAT mesh-swap %s -> %s",
                tostring(prev_unit), tostring(result.unit)) end
        end

        -- #518: deus-yield resolved ONCE per call. Gates the weapon-side mesh
        -- overrides below (husk LA swap, husk vanilla swap, live-body
        -- _offhand_selection) so CW upgrade skins render un-stomped.
        local _deus_yield = mod._la_deus_weapon_yield()

        -- v0.9.0.6-hotfix: kind="unit" LA mesh swap for remote husks.
        -- v0.9.0.8-hotfix: instrumented at every gate so we can see WHY a
        -- swap didn't fire (cache miss vs variant miss vs package miss).
        if _current_husk_wield and _current_husk_wield.wearer_peer then
            local template = item_data and item_data.template
            local equips = _la_equips_by_peer and _la_equips_by_peer[_current_husk_wield.wearer_peer]
            local entry = equips and template and equips[template]
            if entry then
                local career_ok, career_reason =
                    mod._cos_husk_identity.entry_matches_career(
                        entry, _current_husk_wield.career_name)
                if not career_ok then
                    if printf then printf("[cos:698] HUSK mesh SKIP wearer=%s template=%s recorded=%s active=%s reason=%s",
                        tostring(_current_husk_wield.wearer_peer), tostring(template),
                        tostring(entry.wearer_career),
                        tostring(_current_husk_wield.career_name), tostring(career_reason)) end
                    entry = nil
                end
            end
            _dbg("[husk-mesh-swap probe] wearer=%s slot=%s template=%s cache_has_wearer=%s cache_has_entry=%s entry_kind=%s entry_key=%s",
                tostring(_current_husk_wield.wearer_peer),
                tostring(_current_husk_wield.slot_name),
                tostring(template),
                tostring(equips ~= nil),
                tostring(entry ~= nil),
                tostring(entry and entry.kind),
                tostring(entry and entry.armoury_key))
            -- v0.9.69-dev (Slice 0, I6 / #264): the switch-back render loss has
            -- never been pinned because every gate here logs only via _dbg.
            -- One dedup'd printf per (wearer, template, disposition) so the
            -- user's log shows whether a husk wield found the store entry.
            do
                local seen = mod._la_gate_seen
                if not seen then seen = {}; mod._la_gate_seen = seen end
                local dispo = (entry and (entry.kind or "?") .. "/" .. tostring(entry.armoury_key))
                    or (equips and "no-entry-for-template" or "no-store-for-wearer")
                local sk = tostring(_current_husk_wield.wearer_peer) .. "|" .. tostring(template) .. "|" .. dispo
                if not seen[sk] and printf then
                    seen[sk] = true
                    printf("[la-state] HUSK-GATE wearer=%s slot=%s template=%s -> %s",
                        tostring(_current_husk_wield.wearer_peer),
                        tostring(_current_husk_wield.slot_name),
                        tostring(template), dispo)
                end
            end
            -- [cos:sync] issue 154 / #1156: husk cross-char weapon mesh-swap gate.
            -- Failure signal is an EMPTY husk cache at wield (cache_has_entry=false):
            -- the swap never fires and the teammate's weapon renders wrong. Emits the
            -- exact [husk-mesh-swap probe] needle via printf so mod-logging-OFF shows it.
            if PROBE then
                PROBE.emit("cos:sync",
                    "husk_meshgate/" .. tostring(_current_husk_wield.wearer_peer) .. "/" .. tostring(template),
                    string.format("[husk-mesh-swap probe] peer=husk wearer=%s slot=%s template=%s cache_has_wearer=%s cache_has_entry=%s entry_kind=%s entry_key=%s decision=%s",
                        tostring(_current_husk_wield.wearer_peer), tostring(_current_husk_wield.slot_name),
                        tostring(template), tostring(equips ~= nil), tostring(entry ~= nil),
                        tostring(entry and entry.kind), tostring(entry and entry.armoury_key),
                        (entry and (entry.kind == "offhand" or entry.kind == "illusion") and entry.armoury_key) and "resolve-mesh" or "no-op(cache-or-kind-miss)"))
            end
            if entry and (entry.kind == "offhand" or entry.kind == "illusion")
                and entry.armoury_key
                -- #518: in a deus run the husk's weapon is a deus-generated
                -- instance; its rolled rarity skin wins over the LA mesh swap.
                and not _deus_yield
            then
                local variant, variant_source =
                    _resolve_authored_offhand_variant(entry.armoury_key)
                if not variant then
                    _dbg("[husk-mesh-swap] miss: authored variant %s unavailable", tostring(entry.armoury_key)); mod._cos518_husk_miss(entry.armoury_key, _current_husk_wield.wearer_peer, template) -- #518 printf
                    -- v0.9.0.14-hotfix: dedup'd chat warning. Surface the
                    -- missing-variant problem to the local user so they know
                    -- their LA install is missing what a peer is broadcasting
                    -- (most commonly: LA disabled in the launcher).
                    mod._la_missing_variant_logged = mod._la_missing_variant_logged or {}
                    if not mod._la_missing_variant_logged[entry.armoury_key] then
                        mod._la_missing_variant_logged[entry.armoury_key] = true
                        mod:echo("[cosmetics_tweaker] LA variant '%s' missing from your local LA install. Peer's cosmetic won't render. Enable Loremaster's Armoury in launcher + restart, or update LA.",
                            tostring(entry.armoury_key))
                    end
                elseif variant.kind == "texture"
                    and not (variant.new_units and variant.new_units[1]) then
                    -- #373: Weavebound/Shyish shields use dedicated magic
                    -- material units that do not expose LA's diffuse slot.
                    -- Swap only an exact, same-family magic unit to its vanilla
                    -- paint receiver before the husk spawns it; ordinary texture
                    -- variants still remain paint-only.
                    local hand_field = entry.hand_field or "left_hand_unit"
                    local prev = result[hand_field]
                    local receiver = LA_BRIDGE.resolve_texture_receiver(
                        entry.armoury_key, prev, entry.authored_family)
                    if receiver and _override_package_ready(receiver) then
                        result[hand_field] = receiver
                        _dbg("[husk-mesh-swap] MAGIC-RECEIVER wearer=%s hand=%s %s -> %s (armoury=%s)",
                            tostring(_current_husk_wield.wearer_peer), tostring(hand_field),
                            tostring(prev), tostring(receiver), tostring(entry.armoury_key))
                    end
                elseif not (variant.new_units and variant.new_units[1]) then
                    _dbg("[husk-mesh-swap] miss: variant %s has no new_units[1]", tostring(entry.armoury_key))
                else
                    -- v0.9.45-dev (BUG 1/2): resolve via the SHARED helper so the
                    -- local override path (below) and this husk path can't drift.
                    -- _resolve_authored_offhand_mesh derives the 3P from new_units[2]
                    -- (fallback `.."_3p"`) and verifies both halves are loadable.
                    local la_unit, la_unit_3p, mesh_ready = _resolve_authored_offhand_mesh(entry.armoury_key)
                    if not mesh_ready then
                        _dbg("[husk-mesh-swap] miss: variant %s authored mesh not loadable (1p=%s 3p=%s source=%s) — package preload may have failed",
                            tostring(entry.armoury_key), tostring(la_unit), tostring(la_unit_3p), tostring(variant_source))
                    else
                        -- v0.9.9.4-dev: write to the hand_field recorded
                        -- in the cached entry (default left for backward
                        -- compat with pre-v0.9.9.4 cache writes).
                        local hand_field = entry.hand_field or "left_hand_unit"
                        local prev = result[hand_field]
                        result[hand_field] = la_unit
                        _dbg("[husk-mesh-swap] APPLIED wearer=%s template=%s %s %s -> %s (armoury=%s)",
                            tostring(_current_husk_wield.wearer_peer), tostring(template),
                            tostring(hand_field),
                            tostring(prev), tostring(la_unit), tostring(entry.armoury_key))
                        -- v0.9.69-dev (Slice 0, I6): mod-logging-OFF-visible
                        -- confirmation that the wield-path swap fired (#264's
                        -- missing evidence). Dedup'd per (wearer, template, key).
                        do
                            local seen = mod._la_gate_seen
                            if not seen then seen = {}; mod._la_gate_seen = seen end
                            local sk = "swap|" .. tostring(_current_husk_wield.wearer_peer)
                                .. "|" .. tostring(template) .. "|" .. tostring(entry.armoury_key)
                            if not seen[sk] and printf then
                                seen[sk] = true
                                printf("[la-state] HUSK-SWAP applied wearer=%s template=%s hand=%s -> %s (key=%s)",
                                    tostring(_current_husk_wield.wearer_peer), tostring(template),
                                    tostring(hand_field), tostring(la_unit), tostring(entry.armoury_key))
                            end
                        end
                        -- v0.9.43-dev RESOLVE+HUSK trace: the husk DOES swap the
                        -- mesh to the LA custom unit (using new_units[1]/[2] for
                        -- the 1p/3p check) — this is why the CLIENT renders the
                        -- host's shield correctly while the host's own body does
                        -- not (the local path's _override_package_ready suffix
                        -- check fails). Contrast with the RESOLVE line above.
                        _trace("RESOLVE husk-mesh-swap APPLIED wearer=%s slot=%s template=%s hand=%s %s -> %s armoury=%s",
                            tostring(_current_husk_wield.wearer_peer),
                            tostring(_current_husk_wield.slot_name), tostring(template),
                            tostring(hand_field), tostring(prev), tostring(la_unit),
                            tostring(entry.armoury_key))
                        if PROBE then
                            PROBE.emit("cos:sync",
                                "husk_meshswap/" .. tostring(_current_husk_wield.wearer_peer) .. "/" .. tostring(template),
                                string.format("peer=husk wearer=%s template=%s key=%s unit=%s decision=APPLIED-mesh-swap",
                                    tostring(_current_husk_wield.wearer_peer), tostring(template),
                                    tostring(entry.armoury_key), tostring(la_unit)))
                        end
                        return result
                    end
                end
            end

            -- v0.9.82-dev (#416): VANILLA offhand mesh swap on the husk. LA armoury
            -- shields sync above via _la_equips_by_peer; a per-hand VANILLA shield /
            -- held-weapon unit pick (opt.unit / opt.intended_unit, no armoury_key)
            -- has no LA entry, so the husk previously spawned the wearer's BASE
            -- offhand (the #416 gap: Stirland / Bretonnian / GK shields invisible to
            -- peers). Read the parallel synced store and force each recorded hand's
            -- mesh, package-gated via _override_package_ready so a non-resident unit
            -- can NEVER reach the World.spawn_unit C-assert (#270/#392 class) -- a
            -- missing package degrades to the base mesh, not a crash.
            local vstore = mod._offhand_mesh_by_peer
            local vwear  = vstore and vstore[_current_husk_wield.wearer_peer]
            local vhands = vwear and template and vwear[template]
            -- #518: vanilla offhand mesh picks yield in a deus run too (same
            -- template-key leak as the LA branch above).
            if type(vhands) == "table" and not _deus_yield then
                local applied_any = false
                for hand_field, unit_path in pairs(vhands) do
                    if type(unit_path) == "string" and unit_path ~= "" then
                        local recv_item_type = item_data and item_data.item_type
                        if recv_item_type == "weapon_skin" and item_data.matching_item_key
                                and ItemMasterList then
                            local base = rawget(ItemMasterList, item_data.matching_item_key)
                            recv_item_type = base and base.item_type or recv_item_type
                        end
                        -- #583: use CWV's fingerprint-validated peer identity;
                        -- absent/mismatched identity retains the vanilla family.
                        local identity_state = "base"
                        if mod._cos_cwv_peer_identity then
                            recv_item_type, identity_state =
                                mod._cos_cwv_peer_identity.resolve_husk(recv_item_type,
                                    get_mod("character_weapon_variants"), _current_husk_wield,
                                    item_data, mod._independent_dual_item_types)
                        end
                        local compatible = mod._dual_offhand_unit_allowed(
                            recv_item_type, hand_field, unit_path)
                        local ready = compatible and _override_package_ready(unit_path)
                        if compatible and ready then
                            local prev = result[hand_field]
                            result[hand_field] = unit_path
                            applied_any = true
                            if printf then printf("[la-state] HUSK-VANILLA-SWAP wearer=%s template=%s hand=%s %s -> %s",
                                tostring(_current_husk_wield.wearer_peer), tostring(template),
                                tostring(hand_field), tostring(prev), tostring(unit_path)) end
                        end
                        -- [cos:sync] #416: husk vanilla offhand mesh decision. Shows
                        -- APPLIED vs SKIP(package-not-resident) with mod logging OFF.
                        if PROBE then
                            PROBE.emit("cos:sync",
                                "husk_vanilla/" .. tostring(_current_husk_wield.wearer_peer) .. "/" .. tostring(template) .. "/" .. tostring(hand_field),
                                string.format("peer=husk wearer=%s template=%s hand=%s unit=%s decision=%s item_type=%s identity=%s",
                                    tostring(_current_husk_wield.wearer_peer), tostring(template),
                                    tostring(hand_field), tostring(unit_path),
                                    (compatible and ready) and "APPLIED-vanilla-mesh"
                                        or (compatible and "SKIP(package-not-resident)"
                                            or "SKIP(incompatible-hand-mesh)"),
                                    tostring(recv_item_type), tostring(identity_state)))
                        end
                    end
                end
                if applied_any then return result end
            end
        end

        -- Mirror BackendUtils' skin resolution chain, including the backend_id
        -- stamped on item_data during loadout resync (v0.7.101-dev).
        local resolved_skin = skin
        local item_type = item_data and item_data.item_type
        if item_type == "weapon_skin" and item_data.matching_item_key then
            local weapon_data = rawget(ItemMasterList, item_data.matching_item_key)
            if weapon_data then
                item_type = weapon_data.item_type
            end
        end
        if not item_type then return result end
        local active_preview_bid = not _current_husk_wield
            and _active_customization_backend_id or nil
        local active_preview_item_type = not _current_husk_wield
            and mod._active_customization_item_type or nil
        local effective_backend_id, preview_identity =
            mod._la_instance_policy.resolve_preview_backend_id(
                backend_id or (item_data and item_data.backend_id), item_type,
                active_preview_bid, active_preview_item_type)
        -- Pending-skin previews may use the exact active item only when the
        -- family matches. Husk rendering never consumes this local fallback.
        if not effective_backend_id and not _current_husk_wield then
            _trace("RESOLVE preview identity rejected item_type=%s active_bid=%s active_item_type=%s state=%s",
                tostring(item_type), tostring(_active_customization_backend_id),
                tostring(mod._active_customization_item_type),
                tostring(preview_identity))
        end
        if not resolved_skin and effective_backend_id and Managers and Managers.backend then
            local backend_items = Managers.backend:get_interface("items")
            if backend_items and backend_items.get_skin then
                resolved_skin = backend_items:get_skin(effective_backend_id)
            end
        end

        -- Base templates have no skin; offhand customization must not mutate them.
        if not resolved_skin or resolved_skin == "" then return result end

        -- Selections are per backend item and per hand, never item-type globals.
        if effective_backend_id then
            _offhand_session_state.migrate_legacy(effective_backend_id)
        end
        -- #150: browsing changes only the preview; the live body commits on exit.
        local _suppress_browse_override = _in_create_equipment
            and _active_customization_backend_id ~= nil
            and effective_backend_id == _active_customization_backend_id
        if _suppress_browse_override then
            _dbg("[offhand] suppress browse-override on live body bid=%s (customization screen open)",
                tostring(effective_backend_id))
            -- Provenance for the live-body browse suppression gate.
            _trace("RESOLVE suppress-browse bid=%s (in_create_equipment + active_cust match) → live body mesh override SUPPRESSED",
                tostring(effective_backend_id))
        end
        -- #518: on the LIVE body in a deus run (create_equipment; the first CW
        -- map resolves the player's REAL backend items, so the backend_id-keyed
        -- selection genuinely matches) the deus-rolled skin owns the mesh.
        -- Preview surfaces (_in_create_equipment=false) still show the pick,
        -- since they render the keep instance.
        local sel = (not _suppress_browse_override)
            and not (_deus_yield and _in_create_equipment)
            and effective_backend_id
            and _offhand_selection[effective_backend_id]
        local selected_hand_pools = _get_offhand_options(item_type)
        if type(sel) == "table" then
            for hand_field, opt in pairs(sel) do
                local selected_pool = selected_hand_pools
                    and selected_hand_pools[hand_field]
                if type(opt) == "table"
                    and mod._la_instance_policy.selection_owned(opt, selected_pool) then
                    local override_unit = opt.unit or opt.intended_unit
                    -- LA unit variants share the husk path's authored 1P/3P
                    -- resolution; vanilla and texture-only picks retain readiness.
                    local resolved_unit, resolved_ready
                    if opt.la_armoury_key then
                        local la_1p, _la_3p, la_ready = _resolve_authored_offhand_mesh(opt.la_armoury_key)
                        if la_1p then
                            resolved_unit, resolved_ready = la_1p, la_ready
                        else
                            -- #373: pure-paint LA variants have no intended
                            -- unit. If the selected vanilla illusion is a known
                            -- magic shield, use its exact same-family paintable
                            -- counterpart instead of silently painting a shader
                            -- with no diffuse slot.
                            resolved_unit = LA_BRIDGE.resolve_texture_receiver(
                                opt.la_armoury_key, result[hand_field], opt.authored_family)
                                or override_unit
                            resolved_ready = (override_unit and _override_package_ready(override_unit)) or false
                            if resolved_unit and resolved_unit ~= override_unit then
                                resolved_ready = _override_package_ready(resolved_unit)
                            end
                        end
                    else
                        resolved_unit = override_unit
                        resolved_ready = (override_unit and _override_package_ready(override_unit)) or false
                    end
                    -- Keep suffix readiness in the trace for legacy-path comparison.
                    local variant = opt.la_armoury_key
                        and _resolve_authored_offhand_variant(opt.la_armoury_key)
                    local cg = Application and Application.can_get
                    local suffix_3p_ok = (override_unit and cg)
                        and cg("unit", tostring(override_unit) .. "_3p") or false
                    _trace("RESOLVE item_type=%s hand=%s bid=%s in_create_equipment=%s active_cust_match=%s override_unit=%s resolved_unit=%s ready=%s suffix3p_ok=%s kind=%s new_units1=%s new_units2=%s decision=%s",
                        tostring(item_type), tostring(hand_field), tostring(effective_backend_id),
                        tostring(_in_create_equipment),
                        tostring(_active_customization_backend_id ~= nil and effective_backend_id == _active_customization_backend_id),
                        tostring(override_unit), tostring(resolved_unit), tostring(resolved_ready), tostring(suffix_3p_ok),
                        tostring(variant and variant.kind),
                        tostring(variant and variant.new_units and variant.new_units[1]),
                        tostring(variant and variant.new_units and variant.new_units[2]),
                        (resolved_unit and resolved_ready) and "apply-override" or (resolved_unit and "SKIP(package-not-ready)" or "passthrough(no-mesh)"))
                    if resolved_unit and resolved_ready then
                        result[hand_field] = resolved_unit
                    elseif resolved_unit then
                        _dbg("[offhand] SKIP override %s/%s -> %s (package not ready)",
                            tostring(item_type), tostring(hand_field), tostring(resolved_unit))
                    end
                elseif type(opt) == "table" then
                    _trace("RESOLVE selection rejected bid=%s item_type=%s hand=%s reason=foreign-selection",
                        tostring(effective_backend_id), tostring(item_type),
                        tostring(hand_field))
                end
            end
        end

        -- v0.9.3.5: REVERTED the v0.9.3.4 _fallback_if_unloadable gate.
        --
        -- That gate post-processed `result` with `Application.can_get` and
        -- either fell back to `item_data[field]` or cleared the field to nil
        -- when paths were not engine-resident at the moment of the call.
        --
        -- Confirmed regressions (PC-A log 18:51:57, PC-B log 18:52:32):
        --   * 55 elf weapon fields CLEARED to nil during keep async-load
        --     windows — wpn_we_sword_01, wpn_we_dagger_01, wpn_we_deus_02
        --     all both variant AND base returned can_get=false transiently
        --     while the packages were still async-loading. Resulting nil
        --     paths left the elf's weapons INVISIBLE in her hands.
        --   * The gate ran AFTER `result.left_hand_unit = override_unit`,
        --     so the LA offhand override got OVERWRITTEN with the base
        --     vanilla path or nil whenever `can_get` was transiently false
        --     for the override path. PC-A saw vanilla shield locally;
        --     PC-B (peer, who received the broadcast separately) saw the
        --     LA variant correctly. That's the asymmetry the user reported.
        --
        -- `Application.can_get` is unreliable during the async-load window
        -- in keep — paths that ARE valid (in inventory_package_list.lua,
        -- finishing async load) return false transiently. The gate was too
        -- aggressive to be a useful defense.
        --
        -- The original crash this was meant to prevent
        -- (c_api_world.cpp:67 assert on wpn_es_deus_shield_02_magic_3p
        -- after ProfileSync unload) needs a different mechanism — likely
        -- a synchronous `Managers.package:load` before the override
        -- commits, ensuring the unit is in the resource manager when the
        -- wield RPC fires. Deferred to a follow-up.

        return result
    end)
end

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

-- In-game keep / mission body
-- THREE RENDERING PATHS COVERAGE:
--   - In-game (GearUtils.create_equipment): THIS HOOK
--   - Inventory previewer (HeroPreviewer._spawn_item): _cos_preview_runtime.lua
--   - Illusion browser (LootItemUnitPreviewer.spawn_units): _cos_preview_runtime.lua
mod:hook("GearUtils", "create_equipment", function(func, world, slot_name, item_data, unit_1p, unit_3p, is_bot, unit_template, extra_extension_data, ammo_percent, override_item_template, override_item_units, career_name)
    -- v0.9.5: fold MH embed's texture/particle work BEFORE vanilla call.
    -- Matches the original MH-embed hook order (replace then vanilla then
    -- particles). When embed is dormant (standalone enabled), MH_EMBED
    -- exports are no-ops.
    if MH_EMBED and not MH_EMBED.dormant then
        MH_EMBED.replace_textures(unit_1p)
        MH_EMBED.replace_textures(unit_3p)
        MH_EMBED.add_particles(unit_1p, world)
        MH_EMBED.add_particles(unit_3p, world)
    end
    -- v0.9.41-dev (#150): flag the live-body spawn so the get_item_units hook
    -- (called INSIDE vanilla create_equipment) can suppress the browse-time
    -- offhand override on the player's own equipped weapon while the
    -- customization screen is open. Save/restore for nested-call safety.
    local _prev_in_create_equipment = _in_create_equipment
    _in_create_equipment = true
    local result = func(world, slot_name, item_data, unit_1p, unit_3p, is_bot, unit_template, extra_extension_data, ammo_percent, override_item_template, override_item_units, career_name)
    _in_create_equipment = _prev_in_create_equipment
    -- v0.9.6 M2: stash unit→backend_id mapping for the glow picker's
    -- per-item override lookup. Weak-keyed table auto-cleans when units
    -- get destroyed. Covers all 4 hand-unit fields the previewer and
    -- in-keep paths might query.
    if result and item_data and mod._cos.bind_glow_unit then
        local bid = item_data.backend_id
        local resolved_skin = result.skin or item_data.skin
        if (not resolved_skin or resolved_skin == "") and bid and Managers and Managers.backend then
            local items = Managers.backend:get_interface("items")
            resolved_skin = items and items.get_skin and items:get_skin(bid) or resolved_skin
        end
        for _, field in ipairs({ "left_unit_1p", "right_unit_1p", "left_unit_3p", "right_unit_3p" }) do
            local u = result[field]
            if u then
                mod._cos.bind_glow_unit(u, bid, resolved_skin, slot_name,
                    item_data.name, item_data.template)
            end
        end
    end
    if result and item_data then
        -- Scale runs unconditionally — it's gated by unit-path matching, so
        -- a cwv variant equipped in this slot only gets scaled if its
        -- resolved model genuinely matches a pattern (e.g. someone applies
        -- a Bretonian skin to a cwv item, which intentionally would scale).
        mod._cos.scale_units(result, item_data, result.skin)
    end
    if result and item_data and not item_data.cwv_variant then
        -- Offset / tint / LA-paint stay item-name-keyed and so DO need the
        -- cwv_variant gate. cwv items inherit their base weapon's `name`
        -- (e.g. cwv_es_longsword.name == "es_bastard_sword"), so without
        -- this gate any item-name-keyed override on the base weapon would
        -- spuriously fire on every cwv variant. See
        -- `feedback_cwv_clone_name_clobber.md` for the full rationale.
        local weapon_key = item_data.name
        mod._cos.offset_units(result, weapon_key, career_name)
        local has_skin = result.skin ~= nil and result.skin ~= ""
        _apply_la_offhand_to_units(world, item_data, { result.left_unit_3p, result.left_unit_1p }, has_skin, nil, "ingame")
    end
    if result and item_data then
        local skin_key = result.skin or item_data.skin
        if (not skin_key or skin_key == "") and item_data.backend_id and Managers and Managers.backend then
            local items = Managers.backend:get_interface("items")
            skin_key = items and items.get_skin and items:get_skin(item_data.backend_id) or skin_key
        end
        if skin_key == GK_SET.SHIELD_SKIN_KEY then
            for _, target in ipairs({ result.left_unit_3p, result.left_unit_1p }) do
                if target and Unit.alive(target) then
                    GK_SET.apply_variant_to_unit(GK_SET.SHIELD_VARIANT_KEY, target, "create_equipment")
                end
            end
        end
    end
    if result then
        -- v0.9.0-dev: resolve wearer from the 3P unit (= player_unit body).
        -- create_equipment doesn't pass a player object, but unit_3p IS the
        -- player_unit here, so :owner(unit_3p) resolves the peer correctly
        -- for both local + remote husk equips.
        local owner_peer_id = mod._cos.glow_owner_peer_for_unit(unit_3p)
        local composed_appearance
        if item_data and item_data.backend_id then
            local restore_skin = result.skin or item_data.skin
            if (not restore_skin or restore_skin == "") and Managers and Managers.backend then
                local items = Managers.backend:get_interface("items")
                restore_skin = items and items.get_skin
                    and items:get_skin(item_data.backend_id) or restore_skin
            end
            local restored = GlowPicker.restore_runtime_for(item_data.backend_id, {
                skin = restore_skin,
            })
            if restored then
                _cos574_log("rehydrate path=create_equipment bid=%s skin=%s slot=%s",
                    tostring(item_data.backend_id), tostring(restore_skin), tostring(slot_name))
            end
            composed_appearance = _cos_resolve_composed_appearance({
                backend_id = item_data.backend_id,
                data = item_data,
                skin = restore_skin,
            }, nil, false)
        end
        mod._cos.apply_glow_override({
            result.right_unit_3p, result.right_unit_1p,
        }, owner_peer_id)
        if composed_appearance then
            if composed_appearance.shield_glow then
                mod._cos.apply_composed_shield_glow({
                    result.left_unit_3p, result.left_unit_1p,
                }, composed_appearance)
            end
        else
            mod._cos.apply_glow_override({
                result.left_unit_3p, result.left_unit_1p,
            }, owner_peer_id)
        end
    end
    return result
end)

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
-- Loremaster's Armoury bridge (Phase 1)
-- ============================================================
-- Registers LA's recolored cosmetics as separate inventory items via MIL,
-- and queues their texture swap into LA's existing apply pipeline. See
-- _la_bridge.lua for details.

local _la_bridge_init_done       = false
local _la_skin_safety_done       = false
mod.loadout_cache                = mod.loadout_cache or {}

-- Mirrors AllHats lines 38-71: cache custom slot_skin loadouts locally so
-- they're never synced to other clients (vanilla clients crash on unknown
-- skin backend_ids).
local _la_vanilla_fallback = function(name, career) return GK_SET.wire_fallback(LA_BRIDGE, name, career) end

local function _install_skin_loadout_safety()
    if _la_skin_safety_done then return end
    if not (Managers.backend and Managers.backend._interfaces and Managers.backend._interfaces["items"]) then return end
    if not BackendUtils then return end
    _la_skin_safety_done = true

    local items_iface = Managers.backend:get_interface("items")

    mod:hook(BackendUtils, "set_loadout_item", function(func, backend_id, career_name, slot_name)
        local is_clone = LA_BRIDGE.backend_to_armoury[backend_id]
        if is_clone and (slot_name == "slot_hat" or slot_name == "slot_skin") then
            mod.loadout_cache[career_name] = mod.loadout_cache[career_name] or {}
            mod.loadout_cache[career_name][slot_name] = backend_id
            _dbg("[loadout] CACHED %s %s = %s", career_name, slot_name, backend_id)
            -- v0.9.83-dev (#520): persist HERE, at the user-intent chokepoint.
            -- career_name is a call ARGUMENT, so this tap has none of the
            -- profile_by_peer resync fragility that silently dropped every
            -- save from the update_cosmetic_slot tap (that tap stays as a
            -- redundant second writer; save_cosmetic dedups). Without this,
            -- loadout_cache (session-only) was the ONLY record of the equip
            -- and the hat/outfit died with the session.
            if LA_PERSIST and career_name then
                LA_PERSIST.save_cosmetic(career_name, slot_name, backend_id)
            end
            mod._cos925_publish_loadout(items_iface, backend_id, career_name, slot_name, "cosmetic-equip")
            return
        end
        if (slot_name == "slot_hat" or slot_name == "slot_skin") and mod.loadout_cache[career_name] then
            _dbg("[loadout] CLEARED cache %s %s (vanilla bid=%s)", career_name, slot_name, backend_id)
            mod.loadout_cache[career_name][slot_name] = nil
            -- v0.9.83-dev (#520): user intentionally equipped a vanilla item
            -- over the LA one - drop the on-disk entry too, so the next boot
            -- neither rehydrates the cache nor re-injects the LA cosmetic.
            if LA_PERSIST and career_name then
                LA_PERSIST.clear_cosmetic(career_name, slot_name)
            end
        end
        local result_n, results; local function capture(...) result_n = select("#", ...); results = { ... } end
        capture(func(backend_id, career_name, slot_name))
        mod._cos925_publish_loadout(items_iface, backend_id, career_name, slot_name, "loadout-equip")
        return unpack(results, 1, result_n)
    end)

    mod:hook(items_iface, "get_loadout", function(func, self)
        local loadout = func(self)
        if LA_BRIDGE.registered then
            local all_items = nil
            for career_name, slots in pairs(loadout) do
                if type(slots) == "table" then
                    for slot_name, bid in pairs(slots) do
                        if LA_BRIDGE.backend_to_armoury[bid] and not (mod.loadout_cache[career_name] and mod.loadout_cache[career_name][slot_name]) then
                            all_items = all_items or items_iface:get_all_backend_items()
                            local vanilla_key = _la_vanilla_fallback(bid, career_name)
                            for vbid, item in pairs(all_items or {}) do
                                if item.key == vanilla_key and not LA_BRIDGE.backend_to_armoury[vbid] then
                                    slots[slot_name] = vbid
                                    break
                                end
                            end
                        end
                    end
                end
            end
        end
        for career_name, slots in pairs(mod.loadout_cache) do
            loadout[career_name] = loadout[career_name] or {}
            for slot_name, backend_id in pairs(slots) do
                loadout[career_name][slot_name] = backend_id
            end
        end
        return loadout
    end)

    mod:hook(items_iface, "get_loadout_item_id", function(func, self, career_name, slot_name, is_bot)
        -- BOT-LOADOUT FIX (v0.9.39-dev): vanilla get_loadout_item_id(self, career, slot,
        -- is_bot) resolves the BOT's designated loadout when is_bot=true, else the host's
        -- (backend_interface_item_playfab.lua:512/522). The old hook signature DROPPED the
        -- 4th `is_bot` arg, so every bot query fell through with is_bot=nil and resolved the
        -- HOST's loadout -> bots cloned the host's gear instead of using their own. Forward
        -- is_bot, and never let a bot read mod.loadout_cache (career+slot keyed, holds the
        -- LOCAL player's cross-character cosmetics). Identical to the wt v0.12.115 fix; this
        -- path is bridge-gated (_install_skin_loadout_safety), so it covers
        -- Cosmetics-authored sets even when the external LA mod is absent.
        if not is_bot and mod.loadout_cache[career_name] and mod.loadout_cache[career_name][slot_name] then
            return mod.loadout_cache[career_name][slot_name]
        end
        local raw = func(self, career_name, slot_name, is_bot)
        if raw and LA_BRIDGE.registered and LA_BRIDGE.backend_to_armoury[raw] then
            local vanilla_key = _la_vanilla_fallback(raw, career_name)
            if vanilla_key then
                local all_items = items_iface:get_all_backend_items()
                for bid, item in pairs(all_items or {}) do
                    if item.key == vanilla_key and not LA_BRIDGE.backend_to_armoury[bid] then
                        _dbg("[loadout] redirected server clone %s -> vanilla %s (%s)", raw, bid, vanilla_key)
                        return bid
                    end
                end
            end
        end
        return raw
    end)

    mod:hook(items_iface, "get_item_rarity", function(func, self, backend_id)
        local la_key = LA_BRIDGE.backend_to_armoury[backend_id]
        if la_key then
            if la_key:match("_white$") or la_key:match("_Purified$") then
                return "unique"
            end
            return "promo"
        end
        return func(self, backend_id)
    end)

    local function _fixup_server_clones()
        local all_items = items_iface:get_all_backend_items()
        if not all_items then return end
        local raw_loadout = (function()
            local save = mod.loadout_cache; mod.loadout_cache = {}
            local l = items_iface:get_loadout(); mod.loadout_cache = save; return l
        end)()
        for career_name, slots in pairs(raw_loadout or {}) do
            if type(slots) == "table" then
                for slot_name, bid in pairs(slots) do
                    if LA_BRIDGE.backend_to_armoury[bid] then
                        local vanilla_key = _la_vanilla_fallback(bid, career_name)
                        for vbid, item in pairs(all_items) do
                            if item.key == vanilla_key and not LA_BRIDGE.backend_to_armoury[vbid] then
                                _dbg("[loadout] fixup server: %s %s clone %s -> vanilla %s", career_name, slot_name, bid, vbid)
                                local iface = Managers.backend:get_loadout_interface_by_slot(slot_name)
                                if iface then iface:set_loadout_item(vbid, career_name, slot_name) end
                                break
                            end
                        end
                    end
                end
            end
        end
    end
    _fixup_server_clones()

    -- v0.9.83-dev (#520): REHYDRATE mod.loadout_cache from disk. The cache is
    -- the live source of truth for LA hat/outfit loadout state (get_loadout /
    -- get_loadout_item_id overlay it), but it was session-only - every boot
    -- started empty, so the equipped LA cosmetic fell back to the last REAL
    -- backend item ("the hat I had last equipped prior to that", issue 520).
    -- Rehydrating makes the first spawn's BackendUtils.get_loadout_item
    -- (player_unit_attachment_extension.lua:40) resolve the LA clone directly,
    -- and the hero view shows the LA item as equipped after a restart.
    -- Entries whose clone no longer exists (LA variant removed) are skipped,
    -- mirroring the offhand restore's unresolvable guard.
    if LA_PERSIST and LA_PERSIST.get_all_saved_cosmetics then
        local restored, skipped = 0, 0
        for career_name, slots in pairs(LA_PERSIST.get_all_saved_cosmetics()) do
            if type(slots) == "table" then
                for slot_name, bid in pairs(slots) do
                    if (slot_name == "slot_hat" or slot_name == "slot_skin")
                        and LA_BRIDGE.backend_to_armoury[bid]
                    then
                        mod.loadout_cache[career_name] = mod.loadout_cache[career_name] or {}
                        mod.loadout_cache[career_name][slot_name] = bid
                        restored = restored + 1
                    else
                        skipped = skipped + 1
                    end
                end
            end
        end
        if printf and (restored > 0 or skipped > 0) then
            pcall(printf, "[la-state] COSMETIC-RESTORE %d hat/outfit pick(s) rehydrated from disk, %d unresolvable (LA variant missing)",
                restored, skipped)
        end
    end

    -- Load-time provenance marker (#520): asserted by /cos_regression_test
    -- `cos_la_loadout_equip_capture_wired`.
    mod._la_skin_safety_installed = true
end

-- v0.8.57-dev: prevent network sync of LA cosmetic backend_ids to peers.
-- Crash GUID fa479a72 — friend's vanilla client received an item_names
-- index our mod had locally registered (e.g. 2959) and crashed in
-- NetworkLookup.lua:2514's strict __index metamethod when decoding.
-- Root cause: `CosmeticUtils.update_cosmetic_slot` calls
-- `player:set_data(slot, name_id)` where `name_id` is
-- `NetworkLookup.item_names[la_backend_id]` — a LOCAL index our
-- _la_bridge.register_all added via rawset. Peers don't have that
-- index → crash on decode.
-- Fix: hook update_cosmetic_slot, substitute LA backend_ids with their
-- vanilla equivalent for the sync call. Local player still sees the LA
-- hat (visual is applied via the loadout_cache + LA's own apply path,
-- not via sync_data). Husk-side rendering on peers shows the vanilla
-- equivalent — the closest thing they can render without our mod.
-- v0.8.59-dev: CosmeticUtils is a PLAIN TABLE (`CosmeticUtils = CosmeticUtils
-- or {}` at cosmetic_utils.lua:3), not a class. v0.8.58 used string-form
-- `mod:hook("CosmeticUtils", ...)` which VMF can't resolve for plain tables
-- — the hook silently never fired and the crash kept reproducing. Same
-- pitfall as BackendUtils (CLAUDE.md "Hooking" section). Must use the
-- table-form `mod:hook(CosmeticUtils, ...)` with a nil guard.
local function _wire_career_for_player(player) return GK_SET.career_for_player(player, LA_PERSIST) end

if CosmeticUtils then
    mod:hook(CosmeticUtils, "update_cosmetic_slot", function(func, player, slot, item_name, skin_name)
        -- v0.9.12-dev: persistence-driven LA injection. On the FIRST
        -- update_cosmetic_slot for a weapon slot in a new session, vanilla
        -- passes the saved vanilla-substitute skin (because PlayFab can't
        -- store LA names). If the player's current weapon backend_id has a
        -- saved LA illusion on disk, swap skin_name in to the LA bid BEFORE
        -- the substitution check below — that way the existing flow paints
        -- LA visuals AND falls through to net-safe vanilla substitution.
        -- Same idea for hat / armor via the per-career table.
        if LA_PERSIST and player and player.player_unit then
            if slot == "slot_hat" or slot == "slot_skin" then
                if item_name and LA_BRIDGE and LA_BRIDGE.backend_to_armoury
                    and not LA_BRIDGE.backend_to_armoury[item_name]
                then
                    local career = LA_PERSIST._career_name_for_player(player)
                    local saved = career and LA_PERSIST.get_saved_cosmetic(career, slot)
                    if saved and saved ~= item_name then
                        _dbg("[la-persist] inject %s/%s vanilla(%s) -> LA(%s)",
                            tostring(career), tostring(slot), tostring(item_name), tostring(saved))
                        item_name = saved
                    end
                end
            else
                if skin_name and LA_BRIDGE and LA_BRIDGE.backend_to_armoury
                    and not LA_BRIDGE.backend_to_armoury[skin_name]
                then
                    local inv = ScriptUnit.has_extension(player.player_unit, "inventory_system")
                    local slot_data = inv and inv._equipment and inv._equipment.slots
                        and inv._equipment.slots[slot]
                    local backend_id = slot_data and slot_data.item_data and slot_data.item_data.backend_id
                    local saved = backend_id and LA_PERSIST.get_saved_illusion(backend_id)
                    if saved and saved ~= skin_name then
                        _dbg("[la-persist] inject illusion %s vanilla(%s) -> LA(%s)",
                            tostring(backend_id), tostring(skin_name), tostring(saved))
                        skin_name = saved
                    end
                end
            end
        end

        -- v0.8.64-dev: substitute BOTH item_name AND skin_name. The original
        -- v0.8.58 hook substituted only item_name (the 4th arg) — but
        -- cosmetic_utils.lua:245 also reads NetworkLookup.weapon_skins[skin_name]
        -- and :249 broadcasts via player:set_data. If the user equips an LA-
        -- cloned weapon ILLUSION, the LA skin_name reaches peers' decode path
        -- and crashes them in the same NetworkLookup __index fashion as the
        -- fa479a72 crash. Same shape of substitution: LA -> vanilla via
        -- backend_to_vanilla; SKIP the call if no fallback exists.
        local effective_item_name = item_name
        local effective_skin_name = skin_name
        local la_item_subbed = false
        local la_skin_subbed = false

        if LA_BRIDGE and LA_BRIDGE.registered then
            if item_name and LA_BRIDGE.backend_to_armoury and LA_BRIDGE.backend_to_armoury[item_name] then
                local vanilla_key = _la_vanilla_fallback(item_name, _wire_career_for_player(player))
                if vanilla_key then
                    _dbg("[net-safe] update_cosmetic_slot %s LA item(%s) -> vanilla(%s)",
                        tostring(slot), tostring(item_name), tostring(vanilla_key))
                    effective_item_name = vanilla_key
                    la_item_subbed = true
                else
                    _dbg("[net-safe] update_cosmetic_slot %s LA item(%s) -> SKIP (no vanilla fallback)",
                        tostring(slot), tostring(item_name))
                    return
                end
            end
            if skin_name and LA_BRIDGE.backend_to_armoury and LA_BRIDGE.backend_to_armoury[skin_name] then
                local vanilla_skin = _la_vanilla_fallback(skin_name, _wire_career_for_player(player))
                if vanilla_skin then
                    _dbg("[net-safe] update_cosmetic_slot %s LA skin(%s) -> vanilla(%s)",
                        tostring(slot), tostring(skin_name), tostring(vanilla_skin))
                    effective_skin_name = vanilla_skin
                    la_skin_subbed = true
                else
                    _dbg("[net-safe] update_cosmetic_slot %s LA skin(%s) -> SKIP (no vanilla fallback)",
                        tostring(slot), tostring(skin_name))
                    return
                end
            end
        end

        -- v0.9.76-dev (#421): ct_* custom-illusion keys live in _custom_skin_keys,
        -- NOT in LA_BRIDGE.backend_to_armoury, so the LA branch above never catches
        -- them. Vanilla then encodes skin_id = NetworkLookup.weapon_skins[skin_name]
        -- (cosmetic_utils.lua:205-209) and writes it into the player_sync_data game
        -- object (cosmetic_utils.lua:230-251) - a GameSession field synced to EVERY
        -- peer. A peer WITHOUT cosmetics_tweaker decodes it back through the strict
        -- lookup on the playerlist/inspect read path (CosmeticUtils.get_cosmetic_slot
        -- -> get_weapon_skin_name, cosmetic_utils.lua:168-178) and fatals: the same
        -- crash class as the rpc_add_equipment axis, on a different channel.
        -- Substitute the universal vanilla "n/a" key (peers see no illusion; the
        -- local visual never reads sync data). UNCONDITIONAL - never toggle-gated
        -- (issue 371 / BUG_CLASSES 31).
        local ct_skin_subbed
        effective_skin_name, ct_skin_subbed = mod._cos_wire_safe_custom_skin(
            effective_skin_name, "update_cosmetic_slot " .. tostring(slot))

        -- v0.8.64-dev: peer-replay path for armor (slot_skin). slot_skin is
        -- "cosmetic" category, NOT "attachment", so it doesn't flow through
        -- PUAE or AttachmentUtils.hot_join_sync — those only emit cos_la_apply
        -- for hats. Fire it here so peers can replay the LA armor texture
        -- paint on the husk player_unit body. Also record into _local_la_equips
        -- so the hot_join_sync hook can re-emit to joining peers.
        if la_item_subbed and item_name and player and player.player_unit
            and Unit.alive(player.player_unit) and _send_la_apply
        then
            local kind = nil
            if slot == "slot_hat"  then kind = "hat"   end
            if slot == "slot_skin" then kind = "armor" end
            if kind then
                local armoury_key = LA_BRIDGE.backend_to_armoury[item_name]
                local equips = _local_la_equips[player.player_unit]
                if not equips then equips = {}; _local_la_equips[player.player_unit] = equips end
                equips[slot] = item_name
                _send_la_apply(player.player_unit, slot, kind, armoury_key, effective_item_name)
                -- v0.9.12-dev: persist to disk so the LA hat / armor survives
                -- the next game restart. Per-career keying mirrors vanilla's
                -- own loadout-per-career model.
                -- v0.9.83-dev (#520): this tap is now the REDUNDANT writer -
                -- the authoritative save moved to the set_loadout_item hook
                -- (career_name is an argument there). Career resolution here
                -- runs during the loadout-resync window where profile_by_peer
                -- returns nil; the failure must be VISIBLE, not silent.
                local career_name = LA_PERSIST._career_name_for_player(player)
                if career_name then
                    LA_PERSIST.save_cosmetic(career_name, slot, item_name)
                elseif printf then
                    pcall(printf, "[la-persist] WARN save skipped (career unresolved) slot=%s item=%s",
                        tostring(slot), tostring(item_name))
                end
            end
        end

        -- v0.8.66-dev: peer-replay path for WEAPON ILLUSIONS (row-1 picker).
        -- When the user equips an LA-cloned weapon illusion, skin_name (NOT
        -- item_name) is the LA bid. v0.8.64 substituted it to vanilla for
        -- crash-safety but never told peers to repaint, so peers saw vanilla
        -- color on the wielded weapon. Fire kind="illusion" with the LA
        -- armoury_key derived from skin_name. Record in _local_la_equips
        -- keyed by the cosmetic slot ("slot_melee" / "slot_ranged" etc.) so
        -- hot_join_sync can replay to joiners.
        if la_skin_subbed and skin_name and not la_item_subbed
            and player and player.player_unit and Unit.alive(player.player_unit)
            and _send_la_apply
        then
            local armoury_key = LA_BRIDGE.backend_to_armoury[skin_name]
            if armoury_key then
                local equips = _local_la_equips[player.player_unit]
                if not equips then equips = {}; _local_la_equips[player.player_unit] = equips end
                equips[slot] = skin_name
                _send_la_apply(player.player_unit, slot, "illusion", armoury_key, effective_skin_name)
                -- v0.9.12-dev: persist LA illusion per backend_id so the same
                -- weapon instance keeps its LA skin on next game restart. Works
                -- for vanilla weapons AND CIM-forged modded weapons (CIM's
                -- forged_weapons save covers the item itself; this covers the
                -- LA illusion overlay vanilla can't represent).
                local inv = ScriptUnit.has_extension(player.player_unit, "inventory_system")
                local slot_data = inv and inv._equipment and inv._equipment.slots
                    and inv._equipment.slots[slot]
                local backend_id = slot_data and slot_data.item_data and slot_data.item_data.backend_id
                if backend_id then LA_PERSIST.save_illusion(backend_id, skin_name) end
            end
        end

        -- v0.9.0-dev: LA->vanilla swap on a slot must clear the stale LA cache
        -- entry. Previously the `equips[slot] = item_name` write at lines
        -- 3284/3305 only happened inside the la_*_subbed branches; equipping
        -- a vanilla replacement left the prior LA bid in _local_la_equips,
        -- and the next hot_join_sync would replay it to joiners even though
        -- the wearer is no longer wearing LA.
        if not la_item_subbed and not la_skin_subbed
            and player and player.player_unit
        then
            local equips = _local_la_equips[player.player_unit]
            local had_local_la = equips and equips[slot] or nil
            if had_local_la then
                _dbg("[net-safe] update_cosmetic_slot %s: clearing stale LA cache entry %s",
                    tostring(slot), tostring(equips[slot]))
                equips[slot] = nil
            end
            -- v0.9.69-dev (#265, LA_SYNC_CORE_AUDIT Slice 1 / I2): revert must
            -- BROADCAST, not just clear local state. Guarded to the LOCAL
            -- human player (bots share the host peer_id -- a bot career swap
            -- must not revert the host's slots) and to slots that actually
            -- held LA state (locally tracked this session OR still present in
            -- the synced store from an earlier session/persistence restore).
            do
                local pm_r = Managers and Managers.player
                local lp_r = _local_player_safe(pm_r)
                if lp_r and player == lp_r and mod._send_la_revert then
                    local had_synced = lp_r.peer_id and _la_equips_by_peer[lp_r.peer_id]
                        and _la_equips_by_peer[lp_r.peer_id][slot] ~= nil
                    if had_local_la or had_synced then
                        local kind = (slot == "slot_hat" and "hat")
                            or (slot == "slot_skin" and "armor") or "illusion"
                        mod._send_la_revert(player.player_unit, slot, kind,
                            (kind == "illusion") and skin_name or item_name, nil)
                    end
                end
            end
            -- v0.9.12-dev: persistence parity for the clear path. If the user
            -- equips a vanilla item over a previously-saved LA one, the on-disk
            -- entry must be cleared too — otherwise next restart re-applies a
            -- cosmetic the user already unequipped.
            if slot == "slot_hat" or slot == "slot_skin" then
                -- v0.9.83-dev (#520): redundant clear (authoritative clear
                -- lives in the set_loadout_item hook); log resolution loss.
                local career_name = LA_PERSIST._career_name_for_player(player)
                if career_name then
                    LA_PERSIST.clear_cosmetic(career_name, slot)
                elseif printf then
                    pcall(printf, "[la-persist] WARN clear skipped (career unresolved) slot=%s",
                        tostring(slot))
                end
            else
                local inv = ScriptUnit.has_extension(player.player_unit, "inventory_system")
                local slot_data = inv and inv._equipment and inv._equipment.slots
                    and inv._equipment.slots[slot]
                local backend_id = slot_data and slot_data.item_data and slot_data.item_data.backend_id
                if backend_id then LA_PERSIST.clear_illusion(backend_id) end
            end
        end

        if la_item_subbed or la_skin_subbed or ct_skin_subbed then
            return func(player, slot, effective_item_name, effective_skin_name)
        end
        return func(player, slot, item_name, skin_name)
    end)
    -- Fourth #421 encode surface. The three rpc_add_equipment senders are
    -- owned by _cos_wire; this GameSession sender shares its pure policy and
    -- publishes the same regression/diagnostic ownership registry.
    mod._cos_skin_wire_surfaces.update_cosmetic_slot = true
end

-- v0.8.60-dev: SECOND sync path. SimpleInventoryExtension.add_equipment
-- calls CosmeticUtils.update_cosmetic_slot (caught by the hook above)
-- AND then immediately calls LoadoutUtils.sync_loadout_slot, which
-- broadcasts an `rpc_sync_loadout_slot` RPC with
-- `item_id = NetworkLookup.item_names[item.key]`. Peers receive the LOCAL
-- index that only the user's session knows → same crash mode as the
-- SyncData path. Substitute the item with a shadow whose `.key` is the
-- vanilla equivalent before the RPC fires. Same protection also blocks
-- LoadoutUtils.hot_join_sync, which iterates loadouts and re-invokes
-- sync_loadout_slot for each newly-joined peer.
--
-- LoadoutUtils is also a PLAIN TABLE (`LoadoutUtils = LoadoutUtils or {}`),
-- so use table-form hook with nil guard — same BackendUtils/CosmeticUtils
-- pitfall as the previous version.
if LoadoutUtils then
    mod:hook(LoadoutUtils, "sync_loadout_slot", function(func, player, slot_name, item, sync_to_specific_peer_id)
        if mod._cos_send_custom_skin_hands then
            mod._cos_send_custom_skin_hands(player and player.player_unit,
                item, item and item.skin, "sync_loadout_slot")
        end
        if item and item.key
            and LA_BRIDGE and LA_BRIDGE.registered
            and LA_BRIDGE.backend_to_armoury
            and LA_BRIDGE.backend_to_armoury[item.key]
        then
            local vanilla_key = _la_vanilla_fallback(item.key, _wire_career_for_player(player))
            if vanilla_key then
                local shadow = {}
                for k, v in pairs(item) do shadow[k] = v end
                shadow.key = vanilla_key
                _dbg("[net-safe] sync_loadout_slot %s LA(%s) -> vanilla(%s)",
                    tostring(slot_name), tostring(item.key), tostring(vanilla_key))
                return func(player, slot_name, shadow, sync_to_specific_peer_id)
            end
            _dbg("[net-safe] sync_loadout_slot %s LA(%s) -> SKIP (no vanilla fallback)",
                tostring(slot_name), tostring(item.key))
            return
        end
        return func(player, slot_name, item, sync_to_specific_peer_id)
    end)
end

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

-- v0.9.3: multi-source host_peer_id resolution.
-- `Managers.state.network.server_peer_id` is the most authoritative source,
-- but it's only wired up after mission load — in keep / lobby / pre-mission
-- it's nil. Symptom from PC-A→PC-B test 2026-05-21 17:21: user joined PC-B's
-- lobby as client, equipped 17 cosmetics in keep, every emit hit
-- `(no host peer_id yet)` and deferred. Drain only fired 102s later when
-- mission load finally populated state.network; 11/17 entries had timed out
-- by then.
-- The chat manager stores host_peer_id much earlier (foundation/scripts/
-- managers/chat/chat_manager.lua:412-417 `ChatManager.setup_network_context`).
-- Fall back to it so emits during keep / lobby see the host immediately.
local function _host_peer_id()
    local nm = Managers and Managers.state and Managers.state.network
    if nm and nm.server_peer_id then return nm.server_peer_id end
    local cm = Managers and Managers.chat
    if cm and cm.host_peer_id then return cm.host_peer_id end
    return nil
end

local function _local_peer_id_quick()
    local pm = Managers and Managers.player
    local lp = _local_player_safe(pm)
    return lp and lp.peer_id or nil
end

-- v0.9.2-hotfix: robust host detection. Previously checked only
-- `Managers.player.is_server == true`, which is transiently nil during state
-- transitions AND is unreliable in some keep contexts where the user IS
-- hosting a lobby but the field isn't set yet. Symptom in user's log
-- (console-2026-05-21-03.33.15): user was server (`I am server` at line 3198)
-- but ALL cos_la_apply emits hit the client branch and got DEFERRED because
-- both this check AND the host_peer_id lookup returned falsy at emit time.
-- New check: ALSO compare the local peer_id to the network's server_peer_id.
-- If they match, we're hosting regardless of the player_manager flag.
local function _is_local_server()
    -- Primary signal: vanilla's own flag (works in mission + most keep paths).
    if Managers and Managers.player and Managers.player.is_server == true then
        return true
    end
    -- Fallback signal: server_peer_id matches our peer_id. Catches the keep
    -- pre-mission window where Managers.player.is_server is nil but the
    -- network manager has already elected us host.
    local host = _host_peer_id()
    local local_peer = _local_peer_id_quick()
    return host ~= nil and local_peer ~= nil and host == local_peer
end

local function _wearer_unit_for_peer(wearer_peer_id)
    if not wearer_peer_id then return nil end
    local pm = Managers and Managers.player
    if not pm then return nil end
    -- v0.9.69-dev (#268, I4 targeting): resolve the HUMAN player at the peer.
    -- The old first-alive sweep over players_at_peer could return a BOT's
    -- unit on a host peer (bots share the host's peer_id at local_player_id
    -- 2..4; pairs order is arbitrary), sending a wearer's cosmetic onto a
    -- bot. player_from_peer_id defaults local_player_id=1 = the human
    -- (player_manager.lua:463-470) and is nil-safe.
    if pm.player_from_peer_id then
        local p = pm:player_from_peer_id(wearer_peer_id)
        if p and p.player_unit and Unit.alive(p.player_unit) then
            return p.player_unit
        end
    end
    -- Fallback sweep (older API shape / early-spawn window): humans only.
    local players = pm.players_at_peer and pm:players_at_peer(wearer_peer_id)
    if not players then return nil end
    for _, p in pairs(players) do
        if p.player_unit and Unit.alive(p.player_unit)
            and (not p.is_player_controlled or p:is_player_controlled()) then
            return p.player_unit
        end
    end
    return nil
end

local function _local_player_peer_id()
    local pm = Managers and Managers.player
    local lp = _local_player_safe(pm)
    return lp and lp.peer_id
end

mod._la_career_for_unit = function(unit)
    return mod._cos_husk_identity.career_for_unit(
        unit, ScriptUnit, Managers, LA_PERSIST)
end

-- v0.9.0-dev: emit dedup. CosmeticUtils.update_cosmetic_slot, PUAE
-- .game_object_initialized, PUAE.spawn_resynced_loadout, and
-- AttachmentUtils.hot_join_sync all call _send_la_apply for the same
-- equip event; receivers got 3-4 cos_la_apply messages per change, which
-- caused "Slot is not empty" errors in the create_attachment receiver and
-- visible flicker on peers. Suppress duplicates of the same
-- (wearer_peer, slot, kind, armoury_key) within a short window.
local _last_emit_at = {}
local _EMIT_DEDUP_WINDOW = 0.5

-- Client-facing emit function (used by every equip call site). Routes via
-- the host so the resulting apply is server-broadcast and consistent across
-- peers. If we ARE the host, short-circuits the round-trip.
_send_la_apply = function(unit, slot_name, kind, armoury_key, vanilla_key, hand_field)
    if not (unit and Unit.alive(unit)) then return false end
    if not (slot_name and kind and armoury_key) then return false end
    -- v0.9.9.4-dev: hand_field is optional, defaults to "left_hand_unit"
    -- (legacy behavior — only relevant to kind="offhand"/"illusion"). hat
    -- and armor paths ignore it.
    if (kind == "offhand" or kind == "illusion") and not hand_field then
        hand_field = "left_hand_unit"
    end

    local wearer_peer = nil
    local pm = Managers and Managers.player
    if pm and pm.owner then
        local owner = pm:owner(unit)
        wearer_peer = owner and owner.peer_id or nil
    end
    wearer_peer = wearer_peer or _local_player_peer_id()
    if not wearer_peer then return false end
    local wearer_career = mod._la_career_for_unit(unit)
    if not wearer_career then
        if printf then printf("[cos:698] EMIT SKIP wearer=%s slot=%s kind=%s reason=career-unproven",
            tostring(wearer_peer), tostring(slot_name), tostring(kind)) end
        return false
    end

    -- v0.9.9.4-dev: dedup key includes hand_field so the same shield/weapon
    -- equipped under different hand picks doesn't suppress legitimate
    -- second-hand emits within the 0.5s window.
    local dedup_key = wearer_peer .. "|" .. tostring(wearer_career) .. "|"
        .. tostring(slot_name) .. "|" .. tostring(kind) .. "|"
        .. tostring(armoury_key) .. "|" .. tostring(hand_field)
    local now = os.clock()
    local prev = _last_emit_at[dedup_key]
    if prev and (now - prev) < _EMIT_DEDUP_WINDOW then
        return true, "coalesced"  -- a matching emit was already accepted
    end
    _last_emit_at[dedup_key] = now

    if _is_local_server() then
        -- Record + broadcast directly. Host's own broadcast loops back to
        -- itself via "all"; the cos_la_apply receiver applies locally.
        _la_equips_by_peer[wearer_peer] = _la_equips_by_peer[wearer_peer] or {}
        _la_equips_by_peer[wearer_peer][slot_name] = mod._cos_husk_identity.new_entry(
            kind, armoury_key, vanilla_key, hand_field, wearer_career)
        _dbg("[cos_la_apply emit] HOST wearer=%s slot=%s kind=%s key=%s hand=%s",
            tostring(wearer_peer), tostring(slot_name), tostring(kind), tostring(armoury_key), tostring(hand_field))
        _trace("SYNC emit HOST->all wearer=%s slot=%s kind=%s armoury=%s hand=%s",
            tostring(wearer_peer), tostring(slot_name), tostring(kind), tostring(armoury_key), tostring(hand_field))
        -- v0.9.69-dev (Slice 0, I6): emit routing must be visible with mod
        -- logging OFF -- the #264-comment transport loss could not be pinned
        -- because this branch only logged via _dbg/_trace.
        if printf then printf("[la-state] EMIT host->all wearer=%s slot=%s kind=%s key=%s hand=%s",
            tostring(wearer_peer), tostring(slot_name), tostring(kind), tostring(armoury_key), tostring(hand_field)) end
        mod:network_send("cos_la_apply", "all", COS_RPC_SCHEMA, {
            wearer_peer_id = wearer_peer,
            slot           = slot_name,
            kind           = kind,
            armoury_key    = armoury_key,
            vanilla_key    = vanilla_key,
            hand_field     = hand_field,
            wearer_career  = wearer_career,
        })
        return true, "emitted"
    end

    -- Client: ask the host to fan out.
    -- v0.9.0.15-hotfix: VMF's `mod:network_send` does NOT accept the literal
    -- string "server" as a recipient — only "all"/"others"/"local" or a
    -- literal peer_id. The "server" string falls through to the else branch
    -- in VMF's convert_names_to_numbers, fails the _vmf_users lookup, and
    -- the packet is SILENTLY DROPPED. No error, no log, no wire activity.
    -- This bug had been live since v0.8.67-dev and only surfaced now because
    -- prior multiplayer tests had PC-A as HOST (which hits the `"all"`
    -- short-circuit above). When PC-A is a CLIENT (this session), the broken
    -- line fired every emit → host never received any cos_la_apply_req →
    -- entire LA sync chain dead. Fix: target the host's peer_id directly.
    -- Nil-guard for the level-transition window when server_peer_id may
    -- transiently be nil; pending queue retries pick it up.
    local host = _host_peer_id()
    if not host then
        -- v0.9.2-hotfix: ENQUEUE the deferred emit so it actually drains
        -- when the network state settles. Previously the request was logged
        -- and discarded — meaning a cosmetic equipped in keep before the
        -- network manager was fully wired never broadcast. User's log
        -- (console-2026-05-21-03.33.15) showed every emit DEFERRED, no
        -- broadcast, hat/shield invisible to other peers.
        mod._la_deferred_emits = mod._la_deferred_emits or {}
        mod._la_deferred_emits[#mod._la_deferred_emits + 1] = {
            wearer_peer  = wearer_peer,
            slot_name    = slot_name,
            kind         = kind,
            armoury_key  = armoury_key,
            vanilla_key  = vanilla_key,
            hand_field   = hand_field,
            wearer_career = wearer_career,
            queued_at    = os.clock(),
        }
        _dbg("[cos_la_apply emit] CLIENT->req DEFERRED+queued (no host peer_id yet) wearer=%s slot=%s key=%s queue_size=%d",
            tostring(wearer_peer), tostring(slot_name), tostring(armoury_key),
            #mod._la_deferred_emits)
        -- v0.9.69-dev (Slice 0, I6): the deferred branch is the prime suspect
        -- for the 79s-late mid-mission emits (#264 comment). printf so the
        -- user's log shows exactly when an emit queued instead of sending.
        if printf then printf("[la-state] EMIT client DEFERRED (no host yet) slot=%s kind=%s key=%s queue=%d",
            tostring(slot_name), tostring(kind), tostring(armoury_key), #mod._la_deferred_emits) end
        return true, "queued"
    end
    _dbg("[cos_la_apply emit] CLIENT->req wearer=%s slot=%s kind=%s key=%s hand=%s host=%s",
        tostring(wearer_peer), tostring(slot_name), tostring(kind), tostring(armoury_key), tostring(hand_field), tostring(host))
    _trace("SYNC emit CLIENT->req wearer=%s slot=%s kind=%s armoury=%s hand=%s host=%s",
        tostring(wearer_peer), tostring(slot_name), tostring(kind), tostring(armoury_key), tostring(hand_field), tostring(host))
    -- v0.9.69-dev (Slice 0, I6): pair this line with the host's [la-state]
    -- REQ-RECV line to pin a lost request to the wire (mid-mission transport
    -- loss, #264 comment).
    if printf then printf("[la-state] EMIT client->req host=%s slot=%s kind=%s key=%s hand=%s",
        tostring(host), tostring(slot_name), tostring(kind), tostring(armoury_key), tostring(hand_field)) end
    mod:network_send("cos_la_apply_req", host, COS_RPC_SCHEMA, {
        slot         = slot_name,
        kind         = kind,
        armoury_key  = armoury_key,
        vanilla_key  = vanilla_key,
        hand_field   = hand_field,
        wearer_career = wearer_career,
    })
    return true, "emitted"
end

-- v0.9.2-hotfix: deferred-emit drain. Called from mod.update every frame.
-- Walks the queue, retries each entry. Entries older than 30s get dropped
-- (assume the user changed their mind and re-equipped something else).
local function _drain_deferred_la_emits()
    local q = mod._la_deferred_emits
    if not q or #q == 0 then return end
    -- Only attempt drain if we now have a host AND/OR are the host ourselves.
    local host = _host_peer_id()
    local am_host = _is_local_server()
    if not host and not am_host then return end

    local now = os.clock()
    local survivors = {}
    -- v0.9.3: bumped from 30s to 300s. PC-A→PC-B test 2026-05-21 17:21 showed
    -- emits queued at lobby-join sat for 102s before the drain finally fired,
    -- by which time the original 30s timeout had purged them. Lobby load can
    -- legitimately be that slow; 5min is a safer ceiling for "user changed
    -- their mind" purging without dropping live equips.
    for _, entry in ipairs(q) do
        if (now - entry.queued_at) > 300 then
            _dbg("[cos_la_apply drain] dropping stale entry wearer=%s slot=%s key=%s age=%.1fs",
                tostring(entry.wearer_peer), tostring(entry.slot_name),
                tostring(entry.armoury_key), now - entry.queued_at)
        else
            -- Re-emit. If we're now host, the broadcast fires directly. If
            -- we're now client with a known host, the request lands.
            -- v0.9.69-dev (#265 Slice 1): revert entries drain too -- delete
            -- instead of write, payload carries revert=true and no armoury_key.
            if entry.offhand_unit ~= nil then
                -- v0.9.82-dev (#416): vanilla offhand mesh entry (its own payload
                -- field; no armoury_key). Host stores + broadcasts; client requests.
                if am_host then
                    mod._store_offhand_mesh_recv(entry.wearer_peer, entry.slot_name,
                        entry.hand_field, entry.offhand_unit)
                    mod:network_send("cos_la_apply", "all", COS_RPC_SCHEMA, {
                        wearer_peer_id = entry.wearer_peer, slot = entry.slot_name,
                        kind = "offhand", offhand_unit = entry.offhand_unit,
                        hand_field = entry.hand_field,
                    })
                else
                    mod:network_send("cos_la_apply_req", host, COS_RPC_SCHEMA, {
                        slot = entry.slot_name, kind = "offhand",
                        offhand_unit = entry.offhand_unit, hand_field = entry.hand_field,
                    })
                end
                if printf then printf("[la-state] OFFHAND-MESH drain %s slot=%s hand=%s unit=%s (queued %.1fs)",
                    am_host and "host->all" or "client->req", tostring(entry.slot_name),
                    tostring(entry.hand_field), tostring(entry.offhand_unit), now - entry.queued_at) end
            elseif am_host then
                if entry.revert then
                    if _la_equips_by_peer[entry.wearer_peer] then
                        _la_equips_by_peer[entry.wearer_peer][entry.slot_name] = nil
                    end
                else
                    _la_equips_by_peer[entry.wearer_peer] = _la_equips_by_peer[entry.wearer_peer] or {}
                    _la_equips_by_peer[entry.wearer_peer][entry.slot_name] =
                        mod._cos_husk_identity.new_entry(entry.kind, entry.armoury_key,
                            entry.vanilla_key, entry.hand_field, entry.wearer_career)
                end
                mod:network_send("cos_la_apply", "all", COS_RPC_SCHEMA, {
                    wearer_peer_id = entry.wearer_peer,
                    slot           = entry.slot_name,
                    kind           = entry.kind,
                    revert         = entry.revert or nil,
                    armoury_key    = entry.armoury_key,
                    vanilla_key    = entry.vanilla_key,
                    hand_field     = entry.hand_field,
                    wearer_career  = entry.wearer_career,
                })
                _dbg("[cos_la_apply drain] HOST broadcast wearer=%s slot=%s key=%s (was queued %.1fs)",
                    tostring(entry.wearer_peer), tostring(entry.slot_name),
                    tostring(entry.armoury_key), now - entry.queued_at)
                if printf then printf("[la-state] EMIT drain host->all wearer=%s slot=%s kind=%s key=%s revert=%s (queued %.1fs)",
                    tostring(entry.wearer_peer), tostring(entry.slot_name), tostring(entry.kind),
                    tostring(entry.armoury_key), tostring(entry.revert or false), now - entry.queued_at) end
            else
                mod:network_send("cos_la_apply_req", host, COS_RPC_SCHEMA, {
                    slot         = entry.slot_name,
                    kind         = entry.kind,
                    revert       = entry.revert or nil,
                    armoury_key  = entry.armoury_key,
                    vanilla_key  = entry.vanilla_key,
                    hand_field   = entry.hand_field,
                    wearer_career = entry.wearer_career,
                })
                _dbg("[cos_la_apply drain] CLIENT->req sent wearer=%s slot=%s key=%s host=%s (was queued %.1fs)",
                    tostring(entry.wearer_peer), tostring(entry.slot_name),
                    tostring(entry.armoury_key), tostring(host), now - entry.queued_at)
                if printf then printf("[la-state] EMIT drain client->req host=%s slot=%s kind=%s key=%s revert=%s (queued %.1fs)",
                    tostring(host), tostring(entry.slot_name), tostring(entry.kind),
                    tostring(entry.armoury_key), tostring(entry.revert or false), now - entry.queued_at) end
            end
            -- Drop entry from queue after successful re-emit.
        end
    end
    mod._la_deferred_emits = survivors
end
mod._drain_deferred_la_emits = _drain_deferred_la_emits

-- v0.9.69-dev (#265, LA_SYNC_CORE_AUDIT Slice 1 / invariant I2): REVERT
-- broadcast. Every prior emit path covered APPLY only; reverting to vanilla
-- cleared local stores and sent NOTHING, so remote peers kept the stale LA
-- cosmetic until disconnect (D2/D3 in the audit). A revert is a state change
-- like any other: same routing as _send_la_apply (host short-circuit /
-- client req / deferred queue), payload carries `revert = true` with NO
-- armoury_key. Old-version peers drop the payload harmlessly at their
-- `armoury_key` guard (schema unchanged). Attached to `mod` (not a local)
-- so call sites lexically before this point can reach it at runtime and no
-- top-level local is spent (200-local ceiling).
mod._send_la_revert = function(unit, slot_name, kind, vanilla_key, hand_field)
    if not (unit and Unit.alive(unit)) then return end
    if not (slot_name and kind) then return end
    if (kind == "offhand" or kind == "illusion") and not hand_field then
        hand_field = "left_hand_unit"
    end
    local wearer_peer = nil
    local pm = Managers and Managers.player
    if pm and pm.owner then
        local owner = pm:owner(unit)
        wearer_peer = owner and owner.peer_id or nil
    end
    wearer_peer = wearer_peer or _local_player_peer_id()
    if not wearer_peer then return end
    local dedup_key = wearer_peer .. "|" .. tostring(slot_name) .. "|" .. tostring(kind) .. "|REVERT|" .. tostring(hand_field)
    local now = os.clock()
    local prev = _last_emit_at[dedup_key]
    if prev and (now - prev) < _EMIT_DEDUP_WINDOW then
        return
    end
    _last_emit_at[dedup_key] = now

    if _is_local_server() then
        if _la_equips_by_peer[wearer_peer] then
            _la_equips_by_peer[wearer_peer][slot_name] = nil
        end
        if printf then printf("[la-state] REVERT host->all wearer=%s slot=%s kind=%s (store entry cleared)",
            tostring(wearer_peer), tostring(slot_name), tostring(kind)) end
        mod:network_send("cos_la_apply", "all", COS_RPC_SCHEMA, {
            wearer_peer_id = wearer_peer,
            slot           = slot_name,
            kind           = kind,
            revert         = true,
            vanilla_key    = vanilla_key,
            hand_field     = hand_field,
        })
        return
    end

    local host = _host_peer_id()
    if not host then
        mod._la_deferred_emits = mod._la_deferred_emits or {}
        mod._la_deferred_emits[#mod._la_deferred_emits + 1] = {
            wearer_peer  = wearer_peer,
            slot_name    = slot_name,
            kind         = kind,
            revert       = true,
            vanilla_key  = vanilla_key,
            hand_field   = hand_field,
            queued_at    = os.clock(),
        }
        if printf then printf("[la-state] REVERT client DEFERRED (no host yet) slot=%s kind=%s queue=%d",
            tostring(slot_name), tostring(kind), #mod._la_deferred_emits) end
        return
    end
    if printf then printf("[la-state] REVERT client->req host=%s slot=%s kind=%s",
        tostring(host), tostring(slot_name), tostring(kind)) end
    mod:network_send("cos_la_apply_req", host, COS_RPC_SCHEMA, {
        slot         = slot_name,
        kind         = kind,
        revert       = true,
        vanilla_key  = vanilla_key,
        hand_field   = hand_field,
    })
end

-- v0.9.82-dev (#416): receiver-side store for a VANILLA offhand mesh sync. Writes
-- the parallel _offhand_mesh_by_peer store, enforces mutual exclusion with the LA
-- store for the SAME (wearer, slot, hand), and forces a re-render on the wearer's
-- unit so the swap shows without the wearer manually re-wielding. `unit_path` = a
-- concrete unit path (STORE) or "" (CLEAR = revert that hand to the base offhand).
-- Called on every peer (host stores directly + via its own "all" loopback; clients
-- via the broadcast). Idempotent. Attached to `mod` (200-local ceiling).
mod._store_offhand_mesh_recv = function(wearer, slot_name, hand_field, unit_path)
    if not (wearer and slot_name) then return end
    hand_field = hand_field or "left_hand_unit"
    mod._offhand_mesh_by_peer[wearer] = mod._offhand_mesh_by_peer[wearer] or {}
    local by_slot = mod._offhand_mesh_by_peer[wearer]
    local is_set = type(unit_path) == "string" and unit_path ~= ""
    if is_set then
        by_slot[slot_name] = by_slot[slot_name] or {}
        by_slot[slot_name][hand_field] = unit_path
        -- A vanilla mesh supersedes any LA armoury entry on the SAME hand so the
        -- husk LA branch can't shadow it (per-(wearer,slot,hand) mutual exclusion).
        local la_entry = _la_equips_by_peer[wearer] and _la_equips_by_peer[wearer][slot_name]
        if la_entry and (la_entry.hand_field or "left_hand_unit") == hand_field then
            _la_equips_by_peer[wearer][slot_name] = nil
        end
    else
        -- CLEAR: drop this hand's vanilla mesh AND any LA entry on the same hand, so
        -- the wearer's husk re-resolves to the native base offhand.
        if by_slot[slot_name] then by_slot[slot_name][hand_field] = nil end
        local la_entry = _la_equips_by_peer[wearer] and _la_equips_by_peer[wearer][slot_name]
        if la_entry and (la_entry.hand_field or "left_hand_unit") == hand_field then
            _la_equips_by_peer[wearer][slot_name] = nil
        end
    end
    if printf then printf("[la-state] OFFHAND-MESH-STORE wearer=%s slot=%s hand=%s unit=%s decision=%s",
        tostring(wearer), tostring(slot_name), tostring(hand_field),
        tostring(unit_path), is_set and "STORE" or "CLEAR") end
    if PROBE then
        PROBE.emit("cos:sync",
            "offhand_mesh_store/" .. tostring(wearer) .. "/" .. tostring(slot_name) .. "/" .. tostring(hand_field),
            string.format("peer=recv wearer=%s slot=%s hand=%s unit=%s decision=%s",
                tostring(wearer), tostring(slot_name), tostring(hand_field),
                tostring(unit_path), is_set and "STORE" or "CLEAR"))
    end
    -- Re-render now if the wearer is spawned locally (no-op / cooldown-guarded
    -- otherwise); the store is also read on the wearer's next natural husk wield.
    local wu = _wearer_unit_for_peer(wearer)
    if wu and mod._la_native_pulse then mod._la_native_pulse(wu, "offhand-mesh") end
end

-- v0.9.82-dev (#416): client-facing emit for a VANILLA offhand mesh pick. Same
-- host-short-circuit / client-request / deferred-queue routing as _send_la_revert,
-- but carries the additive `offhand_unit` payload field (STORE path or "" CLEAR).
-- Rides the existing cos_la_apply / cos_la_apply_req VMF mod channel -- a non-mod
-- peer never receives it, so no modded key can ride a vanilla RPC into its
-- NetworkLookup (#421 floor intact). Attached to `mod` (200-local ceiling).
mod._send_offhand_mesh = function(unit, slot_name, hand_field, unit_path)
    if not (unit and Unit.alive(unit)) then return false end
    if not slot_name or unit_path == nil then return false end
    hand_field = hand_field or "left_hand_unit"
    local wearer_peer = nil
    local pm = Managers and Managers.player
    if pm and pm.owner then
        local owner = pm:owner(unit)
        wearer_peer = owner and owner.peer_id or nil
    end
    wearer_peer = wearer_peer or _local_player_peer_id()
    if not wearer_peer then return false end
    local dedup_key = wearer_peer .. "|" .. tostring(slot_name) .. "|OFFHANDMESH|"
        .. tostring(hand_field) .. "|" .. tostring(unit_path)
    local now = os.clock()
    local prev = _last_emit_at[dedup_key]
    if prev and (now - prev) < _EMIT_DEDUP_WINDOW then
        return true, "coalesced"
    end
    _last_emit_at[dedup_key] = now

    if _is_local_server() then
        mod._store_offhand_mesh_recv(wearer_peer, slot_name, hand_field, unit_path)
        if printf then printf("[la-state] OFFHAND-MESH host->all wearer=%s slot=%s hand=%s unit=%s",
            tostring(wearer_peer), tostring(slot_name), tostring(hand_field), tostring(unit_path)) end
        mod:network_send("cos_la_apply", "all", COS_RPC_SCHEMA, {
            wearer_peer_id = wearer_peer, slot = slot_name, kind = "offhand",
            offhand_unit = unit_path, hand_field = hand_field,
        })
        return true, "emitted"
    end

    local host = _host_peer_id()
    if not host then
        mod._la_deferred_emits = mod._la_deferred_emits or {}
        mod._la_deferred_emits[#mod._la_deferred_emits + 1] = {
            wearer_peer = wearer_peer, slot_name = slot_name, kind = "offhand",
            offhand_unit = unit_path, hand_field = hand_field, queued_at = os.clock(),
        }
        if printf then printf("[la-state] OFFHAND-MESH client DEFERRED (no host yet) slot=%s hand=%s unit=%s queue=%d",
            tostring(slot_name), tostring(hand_field), tostring(unit_path), #mod._la_deferred_emits) end
        return true, "queued"
    end
    if printf then printf("[la-state] OFFHAND-MESH client->req host=%s slot=%s hand=%s unit=%s",
        tostring(host), tostring(slot_name), tostring(hand_field), tostring(unit_path)) end
    mod:network_send("cos_la_apply_req", host, COS_RPC_SCHEMA, {
        slot = slot_name, kind = "offhand", offhand_unit = unit_path, hand_field = hand_field,
    })
    return true, "emitted"
end

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

-- Unified apply core. All inbound paths (cos_la_apply broadcast + pending-
-- queue replay) converge here. Returns true if applied, false if the target
-- unit isn't ready (caller can re-queue).
local function _apply_la_on_unit(owner_unit, slot_name, kind, armoury_key, vanilla_key)
    if not (owner_unit and Unit.alive(owner_unit)) then return false end
    if not (LA_BRIDGE and LA_BRIDGE.registered) then return false end

    -- #518: TERMINAL deus-yield for weapon-side kinds. Every apply trigger
    -- (cos_la_apply recv, _la_reconcile, transition walk, pending drain, husk
    -- wield re-paint, local wield re-apply) funnels through this function, so
    -- one gate here guarantees no LA offhand/illusion render can stomp a
    -- deus-rolled upgrade skin. Hats/armor pass through untouched. Dedup'd
    -- printf so the suppression is visible with mod logging OFF.
    if (kind == "offhand" or kind == "illusion") and mod._la_deus_weapon_yield() then
        local seen = mod._la_deus_yield_logged
        if not seen then seen = {}; mod._la_deus_yield_logged = seen end
        local sk = tostring(slot_name) .. "|" .. tostring(armoury_key)
        if not seen[sk] and printf then
            seen[sk] = true
            printf("[la-state] DEUS-YIELD suppressed slot=%s kind=%s key=%s (CW upgrade cosmetics win, #518)",
                tostring(slot_name), tostring(kind), tostring(armoury_key))
        end
        return false
    end

    local variant, la = _resolve_la_variant(armoury_key)
    if not variant then
        _dbg("[cos_la_apply] %s armoury_key %s missing from local SKIN_LIST — bail",
            tostring(kind), tostring(armoury_key))
        return false
    end

    if kind == "hat" then
        if variant.swap_hand ~= "hat" then return false end
        local la_unit_path = variant.new_units and variant.new_units[1]
        -- #612: Encarmine deliberately resolves to the exact Laurel donor.
        if CUSTOM_HATS and CUSTOM_HATS.is_custom_identity(armoury_key) then
            la_unit_path = CUSTOM_HATS.spawn_unit(Application, "appearance-replay")
        end
        if not la_unit_path then return false end

        -- v0.9.13-dev: guard now delegates to the pure helper
        -- `_la_chars_compatible` so the same decision is unit-testable in
        -- isolation. See its docstring for the contract. Inline doc below
        -- preserved for context on WHY this guard exists at all.
        --
        -- v0.9.11-dev CRASH/VISUAL FIX: character-mismatch gate (rewritten).
        --
        -- The v0.9.8.8 guard derived `owner_char_path` from `vanilla_key`'s
        -- IML entry — but `vanilla_key` is the CACHED LA emit's vanilla
        -- substitute (the EMITTER's hat), not the OWNER's character. For
        -- host-owned bots whose career differs from the host's, both the
        -- cached LA mesh AND `vanilla_key.unit` resolve to the host's
        -- character paths, so the comparison was a tautology that always
        -- passed. Result: GK LA hat attached to host's WP bot at mission
        -- start (host view only). Issue #14.
        --
        -- Correct source for the OWNER's character: the owner_unit's
        -- currently-attached vanilla slot_hat item_data.unit. That unit
        -- was spawned for THIS body, so its path encodes the body's
        -- character_career composite (e.g. "witch_hunter_priest" vs LA's
        -- cached "empire_soldier_breton"). If the bot doesn't have a
        -- vanilla hat yet (early-spawn race), fall back to SPProfiles
        -- via the owner's Player + profile_index, matching la_char's
        -- first segment against profile.unit_name (character base).
        -- If neither resolves, bail — safer than wrong-skeleton attach.
        do
            local owner_char_path
            local ext_peek = ScriptUnit and ScriptUnit.has_extension
                and ScriptUnit.has_extension(owner_unit, "attachment_system")
            local existing = ext_peek and ext_peek._attachments
                and ext_peek._attachments.slots
                and ext_peek._attachments.slots[slot_name]
            local existing_item_data = existing and existing.item_data
            if existing_item_data and existing_item_data.unit then
                owner_char_path = existing_item_data.unit
            end
            local profile_base
            if not owner_char_path then
                local pm = Managers and Managers.player
                local player = pm and pm.owner and pm:owner(owner_unit)
                local profile_index = player and player.profile_index
                    and (type(player.profile_index) == "function"
                        and player:profile_index() or player.profile_index)
                local profile = profile_index and rawget(_G, "SPProfiles")
                    and SPProfiles[profile_index]
                profile_base = profile and profile.unit_name
            end
            local ok, reason = _la_chars_compatible(owner_char_path, la_unit_path, profile_base)
            if not ok then
                _dbg("[cos_la_apply hat] character mismatch — %s (armoury=%s) — skipping cross-skeleton patch",
                    tostring(reason), tostring(armoury_key))
                return false
            end
        end

        -- v0.8.64-dev: husks render 3P. v0.8.62 checked only the 1P path,
        -- which is why "LA hats invisible on peers" reproduced — the 1P
        -- path was present on the wearer but the 3P attachment path the
        -- husk uses sometimes wasn't loaded on the viewer. Verify BOTH.
        local can_get = Application and Application.can_get
        local has_1p = can_get and can_get("unit", la_unit_path)
        local path_3p = la_unit_path .. "_3p"
        local has_3p = can_get and can_get("unit", path_3p)
        if not has_1p and not has_3p then
            _dbg("[cos_la_apply hat] %s: neither %s nor %s loadable — bail",
                tostring(armoury_key), tostring(la_unit_path), tostring(path_3p))
            return false
        end
        local clone_key = (ItemMasterList and rawget(ItemMasterList, armoury_key) and armoury_key)
            or (vanilla_key and ItemMasterList and rawget(ItemMasterList, vanilla_key) and vanilla_key)
        if not clone_key then
            _dbg("[cos_la_apply hat] %s: no usable IML clone source — bail", tostring(armoury_key))
            return false
        end
        local ext = ScriptUnit.has_extension(owner_unit, "attachment_system")
        if not ext or not ext.create_attachment then return false end
        -- v0.9.0-dev: tear down the prior attachment in this slot before
        -- creating the new one. AttachmentUtils.create_attachment errors with
        -- "Slot is not empty, remove attachment before creating a new one"
        -- when a previous hat is still bound — observed on PC-A across
        -- Pureheart_helm / Hippogryph_helm sequential equips. Bypass the
        -- public ext:remove_attachment() because that fires rpc_remove_attachment
        -- to peers; every cos_la_apply receiver would re-broadcast, amplifying
        -- traffic. Direct destroy + nil the slot mirrors the local cleanup
        -- remove_attachment() does, minus the RPC.
        local existing_slot = ext._attachments and ext._attachments.slots and ext._attachments.slots[slot_name]
        if existing_slot then
            if AttachmentUtils and AttachmentUtils.destroy_attachment then
                pcall(AttachmentUtils.destroy_attachment, ext._world, ext._unit, existing_slot)
            end
            ext._attachments.slots[slot_name] = nil
        end
        local item_data = table.clone(ItemMasterList[clone_key])
        item_data.unit = la_unit_path
        local ok, err = pcall(ext.create_attachment, ext, slot_name, item_data)
        if not ok then
            _dbg_alert("[cos_la_apply hat] create_attachment %s failed: %s",
                tostring(armoury_key), tostring(err))
        end
        if CUSTOM_HATS and CUSTOM_HATS.is_custom_identity(armoury_key) then
            local slot_data = ext._attachments and ext._attachments.slots
                and ext._attachments.slots[slot_name]
            local hat_unit = slot_data and slot_data.unit
            CUSTOM_HATS.apply_surface(hat_unit, "appearance-replay")
        end
        local authored_variant = GK_SET and GK_SET.resolve_variant(armoury_key)
        if authored_variant then
            local slot_data = ext._attachments and ext._attachments.slots and ext._attachments.slots[slot_name]
            local hat_unit = slot_data and slot_data.unit
            if hat_unit and Unit.alive(hat_unit) then
                GK_SET.apply_variant_to_unit(authored_variant, hat_unit, "appearance_replay")
            end
        end
        -- v0.9.0.3-hotfix: paint the LA texture onto the JUST-CREATED HAT
        -- ATTACHMENT UNIT (not the wearer's player_unit). LA's
        -- apply_new_skin_from_texture iterates `Unit.num_meshes(unit)` on the
        -- passed unit and writes textures to those meshes. For armor, the
        -- player body's own meshes carry the armor texture so passing
        -- owner_unit works. For hats, the hat is a SEPARATE attached unit
        -- (vanilla AttachmentUtils.create_attachment spawns it and stores
        -- the ref in slot_data.unit) — passing owner_unit paints the player
        -- body's meshes (no-op for hat textures). The just-created hat unit
        -- lives at ext._attachments.slots[slot_name].unit.
        if not (CUSTOM_HATS and CUSTOM_HATS.is_custom_identity(armoury_key))
            and la and type(la.apply_new_skin_from_texture) == "function" then
            local world = _level_world()
            local slot_data = ext._attachments and ext._attachments.slots and ext._attachments.slots[slot_name]
            local hat_unit = slot_data and slot_data.unit
            if world and ok and hat_unit and Unit.alive(hat_unit) then
                LA_BRIDGE._bridge_active = true
                local paint_ok, paint_err = pcall(la.apply_new_skin_from_texture, armoury_key, world, vanilla_key, hat_unit)
                LA_BRIDGE._bridge_active = false
                _dbg("[cos_la_apply hat] paint %s on hat_unit=%s ok=%s",
                    tostring(armoury_key), tostring(hat_unit), tostring(paint_ok))
                if not paint_ok then
                    _dbg_alert("[cos_la_apply hat] paint err: %s", tostring(paint_err))
                end
            else
                _dbg("[cos_la_apply hat] paint skipped: world=%s ok=%s hat_unit=%s alive=%s",
                    tostring(world ~= nil), tostring(ok), tostring(hat_unit),
                    tostring(hat_unit and Unit.alive(hat_unit)))
            end
        end
        return true
    end

    if kind == "armor" then
        if variant.swap_hand ~= "armor" then return false end
        if GK_SET and GK_SET.resolve_variant(armoury_key) then
            return GK_SET.apply_armor_to_owner(owner_unit, "appearance_replay", armoury_key)
        end
        if not la or type(la.apply_new_skin_from_texture) ~= "function" then return false end
        local world = _level_world()
        if not world then return false end
        LA_BRIDGE._bridge_active = true
        local ok, err = pcall(la.apply_new_skin_from_texture, armoury_key, world, vanilla_key, owner_unit)
        LA_BRIDGE._bridge_active = false
        if not ok then
            _dbg_alert("[cos_la_apply armor] %s on %s failed: %s",
                tostring(armoury_key), tostring(owner_unit), tostring(err))
        end
        return true
    end

    if kind == "offhand" then
        local inv = ScriptUnit.has_extension(owner_unit, "inventory_system")
        local equipment = inv and inv._equipment
        -- v0.9.72-dev WEAPON-IDENTITY GUARD (2026-07-06 18:27/18:34 session):
        -- this branch painted whatever left-hand unit was CURRENTLY wielded,
        -- ignoring which weapon the stored entry belongs to - while the store
        -- keys the same pick under THREE namespaces (weapon item key,
        -- template key, and a legacy wielded-slot key like "slot_melee" from
        -- the hot-join replay; host 18:35:44.704 shows such an entry live).
        -- Any recv/retry/transition reconcile firing while a DIFFERENT weapon
        -- was in hand painted the illusion onto that weapon. Only paint when
        -- the wielded item actually matches the stored key; otherwise return
        -- false (pending retry keeps it briefly; the next wield of the RIGHT
        -- weapon re-applies via the wield reconcile).
        -- v0.9.85-dev (#514): the v0.9.72 guard read `inv.wielded_slot`, a
        -- field that exists ONLY on SimpleHuskInventoryExtension - on the
        -- LOCAL wearer w_item was always nil and the `if w_item then` shape
        -- fell through PERMISSIVE, painting the currently wielded left-hand
        -- unit (Bret-shield pick wrapped around CWV Sword and Mace's mace at
        -- spawn replay). Now resolved via mod._la_wielded_item_matches
        -- (equipment.wielded_slot on both classes) and RESTRICTIVE when the
        -- wielded item is unresolvable: skip + re-queue, never paint blind.
        local match, w_item = mod._la_wielded_item_matches(inv, equipment, slot_name, false)
        if not match then
            local seen = mod._la_gate_seen
            if not seen then seen = {}; mod._la_gate_seen = seen end
            local w_tpl = w_item and w_item.template
            local sk = "offhand-wrongweapon|" .. tostring(slot_name) .. "|" .. tostring(w_tpl)
            if not seen[sk] and printf then
                seen[sk] = true
                printf("[la-state] APPLY SKIP wrong-weapon: entry key=%s but wielded template=%s name=%s (kind=offhand armoury=%s)",
                    tostring(slot_name), tostring(w_tpl), tostring(w_item and w_item.name), tostring(armoury_key))
            end
            return false
        end
        local left_unit = equipment and equipment.left_hand_wielded_unit_3p
        if not left_unit or not Unit.alive(left_unit) then
            -- v0.9.0.3-hotfix: silenced. Previously logged per retry → the
            -- pending-queue's per-frame retry of an offhand equip while host
            -- isn't wielding the shield spammed 24+ lines per equip until the
            -- 5-second TTL expired. The behavior is correct (drops cleanly on
            -- TTL); the noise was loud. Returning false re-queues; pending
            -- queue runner drops the entry quietly on TTL.
            return false
        end
        local world = _level_world()
        if not world then return false end
        -- v0.9.54-dev (#203, trace-confirmed): paint BOTH the 3P and the 1P
        -- wielded shield units. A HUSK has no 1P unit (left_hand_wielded_unit is
        -- nil), so this is unchanged for the husk path; but the LOCAL player —
        -- whose own #203 wield re-apply routes through here — SEES the shield in
        -- FIRST PERSON, and the 0.9.53 trace showed create_equipment's working
        -- "ingame" paint hits both units (3P `..._mesh_3p` AND 1P `..._mesh`).
        -- Painting only the 3P would never restore what the user actually sees.
        local targets, painted = { left_unit }, false
        local left_1p = equipment and equipment.left_hand_wielded_unit
        if left_1p and Unit.alive(left_1p) then targets[#targets + 1] = left_1p end
        for _, target in ipairs(targets) do
            -- v0.9.54-dev (#204): MESH-MISMATCH WARP GUARD on the husk / peer /
            -- local re-apply paint. This path paints via the un-gated
            -- "network_husk" context, which ASSUMES the get_item_units mesh-swap
            -- already replaced the vanilla shield with the LA custom mesh. For an
            -- authored shield whose mesh-swap was SKIPPED (_resolve_authored_offhand_mesh
            -- not ready, or a non-bret shield weapon — "Empire Sword and Shield" —
            -- whose offhand swap didn't fire), painting the heraldry onto the
            -- un-swapped VANILLA shield warps the texture onto the wrong model.
            -- Refuse to paint a kind="unit" LA texture onto a unit whose authored
            -- mesh is NOT the variant's custom mesh (generalizes the #150 BUG1/2
            -- gate from the local-body/previewer contexts to this peer/husk path).
            -- The WORKING bret husk swaps successfully → mesh matches → gate
            -- passes (no regression); kind="texture" variants and units with an
            -- unreadable mesh name stay permissive (return true).
            if not _offhand_paint_mesh_ok(target, armoury_key) then
                _dbg("[cos_la_apply offhand] SKIP %s on %s — mesh is NOT the swapped LA mesh (warp guard #204)",
                    tostring(armoury_key), tostring(target))
                -- _trace_paint routes through mod:info (visible with
                -- output_mode_debug OFF) and dumps target_mesh vs expected
                -- new_units[1] so the empire-shield case is pinned in the log.
                _trace_paint("network_husk", "network_husk", nil, target, armoury_key, "SKIP-mesh-mismatch")
                -- [cos:sync] #204: peer/husk offhand paint refused because the
                -- mesh-swap didn't fire (empire-shield warp case). peer=husk.
                if PROBE then
                    PROBE.emit("cos:sync",
                        "husk_offhand/" .. tostring(armoury_key) .. "/" .. tostring(target),
                        string.format("peer=husk ctx=network_husk key=%s unit=%s decision=SKIP reason=mesh-mismatch(warp-guard)",
                            tostring(armoury_key), tostring(target)))
                end
            else
                LA_BRIDGE._bridge_active = true
                local call_ok, paint_result = pcall(_apply_authored_offhand_to_unit,
                    world, target, armoury_key, vanilla_key, "network_husk")
                LA_BRIDGE._bridge_active = false
                local ok = call_ok and paint_result == true
                if PROBE then
                    PROBE.emit("cos:sync",
                        "husk_offhand/" .. tostring(armoury_key) .. "/" .. tostring(target),
                        string.format("peer=husk ctx=network_husk key=%s unit=%s decision=PAINT outcome=%s",
                            tostring(armoury_key), tostring(target), tostring(ok)))
                end
                if not call_ok then
                    _dbg_alert("[cos_la_apply offhand] %s on %s failed: %s",
                        tostring(armoury_key), tostring(target), tostring(paint_result))
                end
                -- v0.9.43-dev PAINT trace (husk/network path). On the CLIENT this
                -- paints the host's shield onto the husk's wielded left-hand unit,
                -- which by this point has already been mesh-swapped to the LA mesh
                -- by the husk get_item_units branch — so match=true is expected.
                _trace_paint("network_husk", "network_husk", nil, target, armoury_key, ok)
                painted = painted or ok
            end
        end
        return painted
    end

    if kind == "illusion" then
        local authored = GK_SET and GK_SET.resolve_variant(armoury_key)
        if authored then
            local inv = ScriptUnit.has_extension(owner_unit, "inventory_system")
            local equipment = inv and inv._equipment
            local match = mod._la_wielded_item_matches(inv, equipment, slot_name, true)
            if not match then return false end
            local applied = false
            for _, target in ipairs({
                equipment and equipment.left_hand_wielded_unit_3p,
                equipment and equipment.left_hand_wielded_unit,
            }) do
                if target and Unit.alive(target) then
                    applied = GK_SET.apply_variant_to_unit(authored, target, "wielded_shield") or applied
                end
            end
            return applied
        end
        if not la or type(la.apply_new_skin_from_texture) ~= "function" then return false end
        local inv = ScriptUnit.has_extension(owner_unit, "inventory_system")
        local equipment = inv and inv._equipment
        -- v0.9.72-dev WEAPON-IDENTITY GUARD (see offhand branch): illusion
        -- entries are keyed by the COSMETIC SLOT ("slot_melee"/"slot_ranged",
        -- from update_cosmetic_slot); only paint when that slot is the one
        -- currently wielded (or the key matches the wielded item directly).
        -- v0.9.85-dev (#514): same fix as the offhand branch - resolve the
        -- wielded slot via mod._la_wielded_item_matches (equipment.wielded_slot;
        -- `inv.wielded_slot` is husk-only, so this guard was dead on the local
        -- wearer) and skip RESTRICTIVELY when the wielded item is unresolvable.
        -- allow_slot_key=true keeps the designed slot-key match for illusion
        -- entries.
        local match, w_item = mod._la_wielded_item_matches(inv, equipment, slot_name, true)
        if not match then
            local seen = mod._la_gate_seen
            if not seen then seen = {}; mod._la_gate_seen = seen end
            local w_slot_name = (equipment and equipment.wielded_slot) or inv.wielded_slot
            local sk = "illusion-wrongweapon|" .. tostring(slot_name) .. "|" .. tostring(w_slot_name)
            if not seen[sk] and printf then
                seen[sk] = true
                printf("[la-state] APPLY SKIP wrong-weapon: entry key=%s but wielded slot=%s template=%s (kind=illusion armoury=%s)",
                    tostring(slot_name), tostring(w_slot_name), tostring(w_item and w_item.template), tostring(armoury_key))
            end
            return false
        end
        local right_unit = equipment and equipment.right_hand_wielded_unit_3p
        local left_unit_w = equipment and equipment.left_hand_wielded_unit_3p
        if (not right_unit or not Unit.alive(right_unit))
            and (not left_unit_w or not Unit.alive(left_unit_w)) then
            _dbg("[cos_la_apply illusion] %s on owner %s: no live wielded weapon unit",
                tostring(armoury_key), tostring(owner_unit))
            return false  -- re-queue: next wield will spawn
        end
        local world = _level_world()
        if not world then return false end
        LA_BRIDGE._bridge_active = true
        for _, target in ipairs({ right_unit, left_unit_w }) do
            if target and Unit.alive(target) then
                local ok, err = pcall(la.apply_new_skin_from_texture, armoury_key, world, vanilla_key, target)
                if not ok then
                    _dbg_alert("[cos_la_apply illusion] %s on %s failed: %s",
                        tostring(armoury_key), tostring(target), tostring(err))
                end
            end
        end
        LA_BRIDGE._bridge_active = false
        return true
    end

    _dbg_alert("[cos_la_apply] unknown kind %s — ignored", tostring(kind))
    return false
end

local function _try_apply_by_peer(wearer_peer_id, slot_name, kind, armoury_key, vanilla_key)
    local unit = _wearer_unit_for_peer(wearer_peer_id)
    if not unit then return false end
    return _apply_la_on_unit(unit, slot_name, kind, armoury_key, vanilla_key)
end

-- v0.9.64-dev (#233/#234): POST-SPAWN OFFHAND MESH RE-SWAP.
-- A kind="unit" LA shield gets its MESH swapped only in the spawn-time
-- BackendUtils.get_item_units path; a later texture-paint (husk repaint / local
-- wield-reapply) can only recolor, so when the live offhand unit still carries the
-- PREVIOUS (or vanilla) mesh the #204 warp-guard refuses the paint and the swap
-- silently no-ops -- #233 (host's shield spawns on the client before the client has
-- the host's entry) and #234 (mid-mission model change). This forces the mesh to
-- re-resolve by RE-EQUIPPING at the slot level: pulse-wield through the other weapon
-- slot and back, so vanilla re-runs create_equipment / _wield_slot -> get_item_units
-- re-resolves + respawns the offhand with the LA mesh. Slot-level re-equip ONLY --
-- never World.destroy_unit (that is the gt POSITION_LOOKUP nil-deref crash class).
--
-- The CALLER passes the armoury_key that the respawn will actually resolve for this
-- owner (husk: the _la_equips_by_peer entry; local: the same key echoed back on
-- cos_la_apply, which matches _offhand_selection after the #203 exit-queue fix) so
-- the post-pulse mesh CONVERGES and can't ping-pong.
--
-- Only ever call this from a SAFE context (network-callback recv handler or
-- mod.update pending-retry). NEVER from inside a _wield_slot hook body -- the pulse
-- re-fires _wield_slot and re-entering wield during wield can corrupt inventory
-- state. Gated: kind="unit" only, package-resident only, mesh-already-correct no-op,
-- per-owner cooldown + a hard try-cap (so a mesh that can't converge -- e.g. an
-- unresolved get_item_units case -- pulses a few times then stops, no endless
-- flicker), and a re-entrancy guard for the pulse's own _wield_slot fire.
local _offhand_reswap_state = setmetatable({}, { __mode = "k" })  -- owner_unit -> { t, key, tries }
local _OFFHAND_RESWAP_COOLDOWN = 1.5
local _OFFHAND_RESWAP_MAX_TRIES = 3
local function _ensure_offhand_mesh(owner_unit, hand_field, armoury_key, tag)
    if mod._cos_rewield.pulsing() then return false, "pulse-active" end
    if not (owner_unit and armoury_key and Unit.alive(owner_unit)) then return false, "owner-not-ready" end
    hand_field = hand_field or "left_hand_unit"
    local la = get_mod("Loremasters-Armoury")
    local variant = la and la.SKIN_LIST and la.SKIN_LIST[armoury_key]
    if not variant then return false, "variant-missing" end
    local inv = ScriptUnit and ScriptUnit.has_extension and ScriptUnit.has_extension(owner_unit, "inventory_system")
    local equipment = inv and inv._equipment
    if not (equipment and equipment.slots and inv.wield) then return false, "inventory-not-ready" end
    -- Already the LA mesh? -> nothing to do (the common healthy case; no flicker).
    local wielded_field = (hand_field == "right_hand_unit")
        and "right_hand_wielded_unit_3p" or "left_hand_wielded_unit_3p"
    local live = equipment[wielded_field]
    if live and Unit.alive(live) and _offhand_paint_mesh_ok(live, armoury_key) then
        return true, "already-correct"
    end
    -- Package residency: custom-unit variants use the shared LA resolver;
    -- texture variants pulse only when the live mesh is one of #373's exact
    -- magic units, targeting its same-family vanilla receiver.
    local la_unit, mesh_ready
    if variant.new_units and variant.new_units[1] then
        local _
        la_unit, _, mesh_ready = _resolve_authored_offhand_mesh(armoury_key)
    elseif variant.kind == "texture" and live and Unit.alive(live) then
        la_unit = LA_BRIDGE.resolve_texture_receiver(armoury_key, _unit_mesh_name(live))
        mesh_ready = la_unit and _override_package_ready(la_unit) or false
    end
    if not (la_unit and mesh_ready) then return false, "mesh-not-resident" end
    -- Per-owner cooldown + hard try-cap so a per-frame caller can't pulse-storm and a
    -- non-converging mesh can't flicker forever.
    local st = _offhand_reswap_state[owner_unit]
    if st and st.key == armoury_key then
        if st.tries >= _OFFHAND_RESWAP_MAX_TRIES then return false, "try-cap" end
        if (os.clock() - st.t) < _OFFHAND_RESWAP_COOLDOWN then return false, "cooldown" end
    end
    local orig_slot = LA_REPLAY_POLICY.wielded_slot(inv, equipment)
    if not orig_slot then return false, "wielded-slot-missing" end
    local pulse_slot = mod._cos_rewield.alternate_slot(equipment.slots, orig_slot)
    if not pulse_slot then return false, "alternate-slot-missing" end
    local from_mesh = (live and Unit.alive(live)) and _unit_mesh_name(live) or "<none>"
    local tries = (st and st.key == armoury_key) and (st.tries + 1) or 1
    _offhand_reswap_state[owner_unit] = { t = os.clock(), key = armoury_key, tries = tries }
    -- #1145: the wield pair is DEFERRED through the per-wearer coalescer (one
    -- pulse per wearer per frame, game-object re-checked at drain) instead of
    -- firing inline. The re-entrancy flag brackets the DEFERRED wields, which is
    -- where the re-entrancy actually is.
    local _, why = mod._cos_rewield.request(owner_unit, "offhand-mesh:" .. tostring(tag), function()
        local ok1, ok2 = mod._cos_rewield.pulse_now(inv, pulse_slot, orig_slot)
        mod:info("[cos-la-sync] RE-SWAP tag=%s owner=%s hand=%s armoury=%s try=%d from_mesh=%s -> %s pulse=%s<->%s ok=%s/%s",
            tostring(tag), tostring(owner_unit), tostring(hand_field), tostring(armoury_key), tries,
            tostring(from_mesh), tostring(la_unit), tostring(orig_slot), tostring(pulse_slot),
            tostring(ok1), tostring(ok2))
    end)
    -- The pulse has NOT happened yet, so the caller must not treat the mesh as
    -- repaired this frame; "coalesced" tells _la_reconcile to queue the paint
    -- re-apply behind the deferred pulse.
    return false, "coalesced:" .. tostring(why)
end

-- v0.9.69-dev (#265, LA_SYNC_CORE_AUDIT Slice 1): revert-side primitives.
-- Attached to `mod` (no new top-level locals; the main chunk is near the Lua
-- 200-local ceiling) but defined HERE so the closures capture the same
-- upvalues the apply path uses (_la_equips_by_peer,
-- _wearer_unit_for_peer, ...).

-- Slot-level re-equip pulse that restores the NATIVE offhand/illusion render
-- after a revert: with the store entry deleted, the pulse's get_item_units
-- re-resolution falls through to vanilla (mesh AND texture -- a fresh spawn
-- carries no LA paint). Same machinery/guards as _ensure_offhand_mesh's
-- pulse (re-entrancy flag, cooldown via _offhand_reswap_state, slot-level
-- wield only -- NEVER World.destroy_unit) but with the INVERSE gate: it runs
-- regardless of LA variant state, because the target state is vanilla.
-- Safe contexts only (network recv callback / mod.update), like the caller.
mod._la_native_pulse = function(owner_unit, tag)
    if mod._cos_rewield.pulsing() then return end
    if not (owner_unit and Unit.alive(owner_unit)) then return end
    local inv = ScriptUnit and ScriptUnit.has_extension and ScriptUnit.has_extension(owner_unit, "inventory_system")
    local equipment = inv and inv._equipment
    if not (equipment and equipment.slots and inv.wield) then return end
    local st = _offhand_reswap_state[owner_unit]
    if st and st.key == "__native__" and (os.clock() - st.t) < _OFFHAND_RESWAP_COOLDOWN then return end
    local orig_slot = LA_REPLAY_POLICY.wielded_slot(inv, equipment)
    if not orig_slot then return end
    local pulse_slot = mod._cos_rewield.alternate_slot(equipment.slots, orig_slot)
    if not pulse_slot then return end
    _offhand_reswap_state[owner_unit] = { t = os.clock(), key = "__native__", tries = 1 }
    -- #1145: same deferral as _ensure_offhand_mesh. Keyed "__native__", this
    -- pulse does NOT share the per-armoury_key cooldown, so it was free to stack
    -- on a mesh pulse in the same frame; the coalescer is the shared choke point.
    mod._cos_rewield.request(owner_unit, "native-pulse:" .. tostring(tag), function()
        local ok1, ok2 = mod._cos_rewield.pulse_now(inv, pulse_slot, orig_slot)
        if printf then printf("[la-state] NATIVE-PULSE tag=%s owner=%s pulse=%s<->%s ok=%s/%s",
            tostring(tag), tostring(owner_unit), tostring(orig_slot), tostring(pulse_slot),
            tostring(ok1), tostring(ok2)) end
    end)
end

-- Re-create the wearer's NATIVE hat attachment after a hat revert. Only
-- stomps the slot when it still renders the LA unit (if vanilla's own
-- loadout resync already replaced it, no-op) -- convergent regardless of
-- RPC-vs-resync arrival order. Residency-gated (the #270 class: never hand
-- the engine a non-resident unit; the 0.9.67 create_attachment gate
-- backstops this independently).
mod._la_restore_native_hat = function(owner_unit, slot_name, vanilla_key, la_unit_path)
    local ext = ScriptUnit and ScriptUnit.has_extension
        and ScriptUnit.has_extension(owner_unit, "attachment_system")
    if not (ext and ext.create_attachment) then return false, "no-attachment-ext" end
    local slot_data = ext._attachments and ext._attachments.slots and ext._attachments.slots[slot_name]
    local current = slot_data and slot_data.item_data and slot_data.item_data.unit
    if la_unit_path and current and current ~= la_unit_path then
        return false, "already-native"
    end
    local item = vanilla_key and ItemMasterList and rawget(ItemMasterList, vanilla_key)
    if not (item and item.unit) then return false, "no-vanilla-item" end
    if Application and Application.can_get and not Application.can_get("unit", item.unit) then
        return false, "vanilla-unit-non-resident"
    end
    if slot_data then
        if AttachmentUtils and AttachmentUtils.destroy_attachment then
            pcall(AttachmentUtils.destroy_attachment, ext._world, ext._unit, slot_data)
        end
        ext._attachments.slots[slot_name] = nil
    end
    local ok, err = pcall(ext.create_attachment, ext, slot_name, table.clone(item))
    return ok, err
end

-- Receiver for an authoritative revert broadcast (called from the
-- cos_la_apply handler, a safe network-callback context). Deletes the store
-- entry, purges any queued re-apply for the same (wearer, slot) so a
-- pending retry can't re-impose the reverted cosmetic, then restores the
-- native render per kind.
mod._la_apply_revert_recv = function(wearer, slot_name, kind, vanilla_key, hand_field)
    local entry = _la_equips_by_peer[wearer] and _la_equips_by_peer[wearer][slot_name]
    if _la_equips_by_peer[wearer] then
        _la_equips_by_peer[wearer][slot_name] = nil
    end
    if _la_pending_apply and #_la_pending_apply > 0 then
        local kept = {}
        for i = 1, #_la_pending_apply do
            local e = _la_pending_apply[i]
            if not (e[1] == wearer and e[2] == slot_name) then
                kept[#kept + 1] = e
            end
        end
        _la_pending_apply = kept
    end
    local wu = _wearer_unit_for_peer(wearer)
    local outcome
    if kind == "offhand" or kind == "illusion" then
        if wu then
            mod._la_native_pulse(wu, "revert")
            outcome = "pulse"
        else
            outcome = "wearer-not-spawned (native restores on next wield)"
        end
    elseif kind == "hat" then
        local la_unit_path = nil
        if entry and entry.armoury_key then
            local variant = _resolve_la_variant(entry.armoury_key)
            la_unit_path = variant and variant.new_units and variant.new_units[1]
        end
        local vk = vanilla_key or (entry and entry.vanilla_key)
        if wu then
            local ok, why = mod._la_restore_native_hat(wu, slot_name, vk, la_unit_path)
            outcome = ok and "hat-restored" or ("hat-restore-skipped: " .. tostring(why))
        else
            outcome = "wearer-not-spawned"
        end
    else -- armor: store delete stops future re-imposition; the body repaint
         -- rides the next native slot_skin resync / respawn (rare path;
         -- active armor un-paint needs LA API work -- see issue 265).
        outcome = "armor: store cleared, repaint deferred to native resync"
    end
    if printf then printf("[la-state] REVERT-RECV wearer=%s slot=%s kind=%s had_entry=%s -> %s",
        tostring(wearer), tostring(slot_name), tostring(kind),
        tostring(entry ~= nil), tostring(outcome)) end
end

-- v0.9.70-dev (#264, LA_SYNC_CORE_AUDIT Slice 2 / invariant I3): the SINGLE
-- render-reconcile entry point. Every trigger that (re)renders a peer's
-- cosmetic-bearing units -- recv, pending retry, transition walk, husk wield,
-- local wield -- calls THIS instead of its own bespoke re-apply, so a trigger
-- nobody special-cased (the #264 weapon switch-back) cannot fall through.
-- Reads ONLY the synced store (I1), targets ONLY the human wearer's unit
-- (I4, via _wearer_unit_for_peer), and treats mesh+paint as one gated unit
-- (I7): in safe contexts (allow_pulse=true: network callback / mod.update)
-- a stale kind="unit" mesh is pulsed via _ensure_offhand_mesh; in wield
-- contexts (allow_pulse=false: called from inside a _wield_slot body, where
-- pulsing would re-enter wield) a stale mesh is DEFERRED to the pending
-- drain, which pulses from mod.update within a frame or two.
-- Returns (applied, reason): reason="no-entry" is terminal for retry loops
-- (a revert deleted the entry); "wearer-not-spawned" is retryable.
mod._la_reconcile = function(wearer_peer, slot_name, tag, allow_pulse)
    local equips = _la_equips_by_peer[wearer_peer]
    local eq = equips and equips[slot_name]
    if not (eq and eq.kind and eq.armoury_key) then return false, "no-entry" end
    -- #518: TERMINAL deus-yield for weapon-side entries, so pending-drain
    -- retries drop immediately instead of spinning to their 5s deadline.
    -- (_apply_la_on_unit carries the same gate as the belt-and-suspenders
    -- backstop for callers that bypass reconcile.)
    if (eq.kind == "offhand" or eq.kind == "illusion") and mod._la_deus_weapon_yield() then
        return false, "deus-yield"
    end
    local wu = _wearer_unit_for_peer(wearer_peer)
    if not wu then return false, "wearer-not-spawned" end
    local active_career = mod._la_career_for_unit(wu)
    local career_ok, career_reason = mod._cos_husk_identity.entry_matches_career(
        eq, active_career)
    if not career_ok then
        _purge_stale_peer_slot(_la_equips_by_peer, wearer_peer, slot_name)
        if printf then printf("[cos:698] RECONCILE SKIP wearer=%s slot=%s kind=%s recorded=%s active=%s reason=%s",
            tostring(wearer_peer), tostring(slot_name), tostring(eq.kind),
            tostring(eq.wearer_career), tostring(active_career), tostring(career_reason)) end
        return false, career_reason
    end
    local applied = _apply_la_on_unit(wu, slot_name, eq.kind, eq.armoury_key, eq.vanilla_key)
    if eq.kind == "offhand" or eq.kind == "illusion" then
        if allow_pulse then
            local inv = ScriptUnit and ScriptUnit.has_extension
                and ScriptUnit.has_extension(wu, "inventory_system")
            local equipment = inv and inv._equipment
            local matches = mod._la_wielded_item_matches(inv, equipment, slot_name, eq.kind == "illusion")
            if matches then
                local repaired, why = _ensure_offhand_mesh(wu, eq.hand_field, eq.armoury_key, tag)
                if not applied and repaired then
                    applied = _apply_la_on_unit(wu, slot_name, eq.kind, eq.armoury_key, eq.vanilla_key)
                elseif type(why) == "string" and why:sub(1, 9) == "coalesced" then
                    -- #1145: pulse deferred, so the mesh it repairs does not
                    -- exist yet. Hand the paint re-apply to the pending drain
                    -- (the same convergence the wield-context branch below uses);
                    -- without this the deferral silently drops the re-paint.
                    _la_pending_apply[#_la_pending_apply + 1] = {
                        wearer_peer, slot_name, eq.kind, eq.armoury_key, eq.vanilla_key, os.clock() + 5,
                    }
                end
            end
        elseif applied then
            -- Wield context: verify the just-spawned mesh against the store;
            -- if the in-wield get_item_units swap silently missed (#264's
            -- failure mode), hand the mesh repair to the pending drain.
            local inv = ScriptUnit and ScriptUnit.has_extension
                and ScriptUnit.has_extension(wu, "inventory_system")
            local equipment = inv and inv._equipment
            local wf = (eq.hand_field == "right_hand_unit")
                and "right_hand_wielded_unit_3p" or "left_hand_wielded_unit_3p"
            local live = equipment and equipment[wf]
            if live and Unit.alive(live) and not _offhand_paint_mesh_ok(live, eq.armoury_key) then
                _la_pending_apply[#_la_pending_apply + 1] = {
                    wearer_peer, slot_name, eq.kind, eq.armoury_key, eq.vanilla_key, os.clock() + 5,
                }
                if printf then printf("[la-state] RECONCILE tag=%s wearer=%s slot=%s -> mesh stale after wield, deferred pulse queued (key=%s)",
                    tostring(tag), tostring(wearer_peer), tostring(slot_name), tostring(eq.armoury_key)) end
            end
        end
    end
    return applied
end

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

-- HOST: receives equip requests from clients, validates, records into
-- `_la_equips_by_peer`, broadcasts the authoritative cos_la_apply to ALL.
mod:network_register("cos_la_apply_req", function(sender_peer_id, schema_version, payload)
    if schema_version ~= COS_RPC_SCHEMA then  -- #45: drop cross-version payloads
        _dbg_alert("[rpc:schema] cos_la_apply_req mismatch from peer=%s: peer sent v%s, we expect v%d. Dropping.",
            tostring(sender_peer_id), tostring(schema_version), COS_RPC_SCHEMA)
        -- Task-3 visibility: _dbg_alert routes through mod:warning (VMF-gated,
        -- invisible with mod logging OFF). Mirror to engine printf so a dropped
        -- cross-version RPC is never a silent failure in the user's log.
        if printf then printf("[rpc:schema] cos_la_apply_req DROP peer=%s sent=v%s expect=v%d",
            tostring(sender_peer_id), tostring(schema_version), COS_RPC_SCHEMA) end
        return
    end
    if not _is_local_server() then return end  -- defense in depth
    if type(payload) ~= "table" or not sender_peer_id then return end
    local slot_name   = payload.slot
    local kind        = payload.kind
    local armoury_key = payload.armoury_key
    local vanilla_key = payload.vanilla_key
    local wearer_career = payload.wearer_career
    -- v0.9.9.4-dev: hand_field is new; older clients omit it. Default to
    -- "left_hand_unit" for offhand/illusion (legacy behavior) so peers on
    -- pre-v0.9.9.4 versions still sync correctly.
    local hand_field  = payload.hand_field
    if (kind == "offhand" or kind == "illusion") and not hand_field then
        hand_field = "left_hand_unit"
    end
    -- v0.9.69-dev (Slice 0, I6): host-side receipt line BEFORE any validation,
    -- so a client req that reaches the host but is then rejected/deduped is
    -- distinguishable from one lost on the wire (#264-comment transport loss).
    if printf then printf("[la-state] REQ-RECV from=%s slot=%s kind=%s key=%s revert=%s",
        tostring(sender_peer_id), tostring(slot_name), tostring(kind),
        tostring(armoury_key), tostring(payload.revert or false)) end
    -- v0.9.69-dev (#265 Slice 1): client-originated REVERT. No armoury_key to
    -- validate -- delete the sender's store entry and rebroadcast the revert
    -- authoritatively to all peers (the sender included, for lockstep).
    if payload.revert then
        if slot_name and kind then
            if _la_equips_by_peer[sender_peer_id] then
                _la_equips_by_peer[sender_peer_id][slot_name] = nil
            end
            mod:network_send("cos_la_apply", "all", COS_RPC_SCHEMA, {
                wearer_peer_id = sender_peer_id,
                slot           = slot_name,
                kind           = kind,
                revert         = true,
                vanilla_key    = payload.vanilla_key,
                hand_field     = hand_field,
            })
        end
        return
    end
    -- v0.9.82-dev (#416): client-originated VANILLA offhand mesh. No armoury_key to
    -- validate; store on the host + rebroadcast authoritatively to all (sender
    -- included, for lockstep). Placed before the armoury_key gate, like the revert.
    if payload.offhand_unit ~= nil then
        if slot_name and mod._store_offhand_mesh_recv then
            mod._store_offhand_mesh_recv(sender_peer_id, slot_name, hand_field, payload.offhand_unit)
            mod:network_send("cos_la_apply", "all", COS_RPC_SCHEMA, {
                wearer_peer_id = sender_peer_id, slot = slot_name, kind = "offhand",
                offhand_unit = payload.offhand_unit, hand_field = hand_field,
            })
        end
        return
    end
    if not (slot_name and kind and armoury_key) then return end
    local sender_unit = _wearer_unit_for_peer(sender_peer_id)
    local sender_live_career = sender_unit and mod._la_career_for_unit(sender_unit)
    local career_ok, career_reason = mod._cos_husk_identity.transport_career_valid(
        wearer_career, sender_live_career)
    if not career_ok then
        if printf then printf("[cos:698] REQ SKIP wearer=%s slot=%s reason=%s",
            tostring(sender_peer_id), tostring(slot_name), tostring(career_reason)) end
        return
    end
    -- v0.9.3.2-hotfix: accept armoury_keys present in EITHER our bridge index
    -- OR LA's own SKIN_LIST directly. The bridge's register_all only registers
    -- swap_hand == "hat" or "armor" variants — shields and weapons (swap_hand
    -- == "left_hand_unit" / "right_hand_unit") are NOT in armoury_to_backend.
    -- That left shield repaints silently rejected on the host side even though
    -- the client paints them locally just fine (its paint code reads LA's
    -- SKIN_LIST directly). Now: accept any armoury_key LA knows about.
    -- Burned PC-A→PC-B test 2026-05-21 17:53.
    local bridge_known = LA_BRIDGE and LA_BRIDGE.registered and LA_BRIDGE.armoury_to_backend[armoury_key]
    local la_known = false
    do
        local la = get_mod("Loremasters-Armoury")
        if la and type(la.SKIN_LIST) == "table" and la.SKIN_LIST[armoury_key] then
            la_known = true
        end
    end
    if not (bridge_known or la_known) then
        _dbg_alert("[cos_la_apply_req] reject from %s: unknown armoury_key %s",
            tostring(sender_peer_id), tostring(armoury_key))
        return
    end
    _la_equips_by_peer[sender_peer_id] = _la_equips_by_peer[sender_peer_id] or {}
    _la_equips_by_peer[sender_peer_id][slot_name] = mod._cos_husk_identity.new_entry(
        kind, armoury_key, vanilla_key, hand_field, wearer_career)
    mod:network_send("cos_la_apply", "all", COS_RPC_SCHEMA, {
        wearer_peer_id = sender_peer_id,
        slot           = slot_name,
        kind           = kind,
        armoury_key    = armoury_key,
        vanilla_key    = vanilla_key,
        hand_field     = hand_field,
        wearer_career  = wearer_career,
    })
end)

-- v0.9.70-dev (#267, LA_SYNC_CORE_AUDIT Slice 2b / invariant I9): HOST side
-- of the pull-on-ready flow. A peer that just reached StateIngame requests
-- the full LA store; we reply with one targeted cos_la_apply per recorded
-- (wearer, slot). Reuses the existing broadcast payload shape, so the
-- joiner's recv path (mirror + reconcile) needs nothing new. The requester's
-- own entries are included deliberately -- after a transition they re-drive
-- the client's local reconcile, hardening #233. Old-version peers never send
-- this RPC and ignore it if received (unknown name), so it is
-- backward-compatible without a schema bump.
mod:network_register("cos_la_state_req", function(sender_peer_id, schema_version, payload)
    if schema_version ~= COS_RPC_SCHEMA then
        if printf then printf("[rpc:schema] cos_la_state_req DROP peer=%s sent=v%s expect=v%d",
            tostring(sender_peer_id), tostring(schema_version), COS_RPC_SCHEMA) end
        return
    end
    -- #267 follow-up (tonight's 3-player session: clients retried the pull 30x /
    -- 10x and NEVER got a reply). Both early returns were silent, so the
    -- responder-side cause was invisible in the client-only logs. Log them: a
    -- non-server that still receives the req (host election flux / a peer that
    -- resolved the wrong host) and a missing sender are the two ways the host
    -- can legitimately decline to answer. If neither fires and the reply count
    -- below is still 0, the store was genuinely empty (not a lost reply).
    if not _is_local_server() then
        if printf then printf("[la-state] STATE-PULL DROP req from=%s reason=not-local-server (is_server=%s host=%s self=%s)",
            tostring(sender_peer_id),
            tostring(Managers and Managers.player and Managers.player.is_server),
            tostring(_host_peer_id()), tostring(_local_peer_id_quick())) end
        return
    end
    if not sender_peer_id then
        if printf then printf("[la-state] STATE-PULL DROP reason=no-sender-peer") end
        return
    end
    local n = 0
    for wearer_peer, slots in pairs(_la_equips_by_peer) do
        if type(slots) == "table" then
            for slot_name, entry in pairs(slots) do
                if type(entry) == "table" and entry.kind and entry.armoury_key then
                    mod:network_send("cos_la_apply", sender_peer_id, COS_RPC_SCHEMA, {
                        wearer_peer_id = wearer_peer,
                        slot           = slot_name,
                        kind           = entry.kind,
                        armoury_key    = entry.armoury_key,
                        vanilla_key    = entry.vanilla_key,
                        hand_field     = entry.hand_field,
                        wearer_career  = entry.wearer_career,
                    })
                    n = n + 1
                end
            end
        end
    end
    -- v0.9.82-dev (#416): also replay VANILLA offhand meshes so a late joiner sees
    -- peers' shield / held-weapon picks. Reuses cos_la_apply with the offhand_unit
    -- field (the joiner's recv path stores + pulses -- no new handler needed).
    for wearer_peer, slots in pairs(mod._offhand_mesh_by_peer) do
        if type(slots) == "table" then
            for slot_name, hands in pairs(slots) do
                if type(hands) == "table" then
                    for hand_field, unit_path in pairs(hands) do
                        if type(unit_path) == "string" and unit_path ~= "" then
                            mod:network_send("cos_la_apply", sender_peer_id, COS_RPC_SCHEMA, {
                                wearer_peer_id = wearer_peer, slot = slot_name,
                                kind = "offhand", offhand_unit = unit_path,
                                hand_field = hand_field,
                            })
                            n = n + 1
                        end
                    end
                end
            end
        end
    end
    -- #574 follow-up: reuse the proven pull-on-ready request instead of
    -- adding another RPC. The old AttachmentUtils push can precede the
    -- joiner's ingame membership and disappear; this reply is requested by
    -- the joiner after its host identity is usable. One targeted existing
    -- cos_glow_apply per cached wearer feeds the normal recv + bounded local
    -- equipment-ready repaint path.
    local glow_n = 0
    for wearer_peer, state in pairs(_glow_by_peer) do
        if type(state) == "table" then
            mod:network_send("cos_glow_apply", sender_peer_id, COS_RPC_SCHEMA, {
                wearer_peer_id = wearer_peer,
                state = state,
            })
            glow_n = glow_n + 1
        end
    end
    _cos574_log("state-pull reply requester=%s glow_entries=%d new_rpc=false",
        tostring(sender_peer_id), glow_n)
    if printf then printf("[la-state] STATE-PULL reply: %d entr(ies) -> requester=%s",
        n, tostring(sender_peer_id)) end
    -- v0.9.71-dev: explicit ack so the requester can distinguish "empty
    -- store" from "request lost in the load window" and stop retrying.
    mod:network_send("cos_la_state_ack", sender_peer_id, COS_RPC_SCHEMA, { count = n })
end)

-- v0.9.71-dev: requester side of the pull ack (see the retry drain in
-- mod.update). Old-version hosts never send this; the requester then retries
-- up to its cap and gives up loudly - still strictly better than one silent
-- fire-and-forget send.
mod:network_register("cos_la_state_ack", function(sender_peer_id, schema_version, payload)
    if schema_version ~= COS_RPC_SCHEMA then return end
    local attempts = type(mod._la_state_pull_pending) == "table"
        and mod._la_state_pull_pending.attempts or "?"
    mod._la_state_pull_pending = nil
    if printf then printf("[la-state] STATE-PULL acked by host=%s count=%s (attempt %s)",
        tostring(sender_peer_id),
        tostring(type(payload) == "table" and payload.count or "?"),
        tostring(attempts)) end
end)

-- v0.9.0-dev: peer-disconnect cleanup. Without this _la_equips_by_peer grows
-- unboundedly across the host's session, and stale entries replay on hot_join
-- for peers who left long ago (visible if they share peer_id with a future
-- joiner, which Steam sometimes recycles). Also clears _last_emit_at so the
-- dedup window doesn't suppress legitimate fresh emits after re-join.
-- v0.9.71-dev ROOT-CAUSE FIX (2026-07-06 17:25/17:26 session logs, both
-- machines): `PlayerManager.remove_player` fires for EVERY peer - including
-- the machine's OWN peer - on EVERY level transition, not just on
-- disconnects (host log 17:28:20.460/.471: remove_player for self AND the
-- client during the keep->mission load, each immediately followed by this
-- hook's purge line). The v0.9.0 immediate purge therefore WIPED
-- `_la_equips_by_peer` on every machine at every transition, which is why
-- TRANSITION-WALK always armed with `offhand_entries=0`, HUSK-GATE logged
-- `no-store-for-wearer` post-transition, and no illusion survived into a
-- mission (the store the audit assumed transition-proof never was).
-- Fix: DEFER the purge 30s. A transition re-adds the peer within seconds
-- (add_remote_player cancels the deadline); a genuine disconnect never
-- re-adds, so the purge still runs - the Steam peer_id-recycling rationale
-- of v0.9.0 is preserved, just 30s later. The local peer is never purged.
if rawget(_G, "PlayerManager") then
    mod:hook_safe(PlayerManager, "remove_player", function(self, peer_id, local_player_id)
        if not peer_id then return end
        local has_state = (_la_equips_by_peer and _la_equips_by_peer[peer_id]) ~= nil
            or (mod._glow_by_peer and mod._glow_by_peer[peer_id]) ~= nil
            or (mod._cos_custom_illusion_sent
                and mod._cos_custom_illusion_sent[tostring(peer_id)]) ~= nil
        if not has_state then return end
        mod._la_peer_purge_at = mod._la_peer_purge_at or {}
        if not mod._la_peer_purge_at[peer_id] then
            mod._la_peer_purge_at[peer_id] = os.clock() + 30
            if printf then printf("[la-state] PEER-PURGE scheduled peer=%s in 30s (remove_player; canceled if the peer re-adds - transitions do)",
                tostring(peer_id)) end
        end
    end)
    -- Transition/hot-join re-add cancels the pending purge. Remote peers
    -- re-enter via add_remote_player on every level load.
    mod:hook_safe(PlayerManager, "add_remote_player", function(self, peer_id, ...)
        if peer_id and mod._la_peer_purge_at and mod._la_peer_purge_at[peer_id] then
            mod._la_peer_purge_at[peer_id] = nil
            if printf then printf("[la-state] PEER-PURGE canceled peer=%s (re-added - transition, not a disconnect)",
                tostring(peer_id)) end
        end
        if LA_REPLAY_POLICY.should_publish_local_on_peer_ready(
                _local_player_peer_id(), peer_id) then
            mod._la_self_rebroadcast_pending = true
        end
        -- #660 S3: a peer appeared -> peer-ready replay edge, scoped to that
        -- peer. Its husk unit is usually not spawned yet, so most records defer
        -- here and drain on the husk-ready (SimpleHuskInventoryExtension.init)
        -- edge; invalidating just this peer keeps the coalescing scope tight.
        if peer_id and mod._cos_replay then
            mod._cos_replay.on_edge("peer-ready",
                { only_peer = peer_id, invalidate_peer = peer_id })
        end
    end)
end

-- Executes due deferred purges. Called from mod.update.
mod._la_tick_peer_purges = function()
    local q = mod._la_peer_purge_at
    if not q or not next(q) then return end
    local now = os.clock()
    local local_peer = _local_player_peer_id()
    for peer_id, deadline in pairs(q) do
        if peer_id == local_peer then
            q[peer_id] = nil  -- never purge our own state
        elseif now >= deadline then
            q[peer_id] = nil
            if _la_equips_by_peer and _la_equips_by_peer[peer_id] then
                _la_equips_by_peer[peer_id] = nil
            end
            if _last_emit_at then
                for k, _ in pairs(_last_emit_at) do
                    if type(k) == "string" and k:sub(1, #tostring(peer_id) + 1) == (tostring(peer_id) .. "|") then
                        _last_emit_at[k] = nil
                    end
                end
            end
            if mod._glow_by_peer and mod._glow_by_peer[peer_id] then
                mod._glow_by_peer[peer_id] = nil
            end
            -- v0.9.82-dev (#416): drop the disconnected peer's vanilla offhand meshes too.
            if mod._offhand_mesh_by_peer and mod._offhand_mesh_by_peer[peer_id] then
                mod._offhand_mesh_by_peer[peer_id] = nil
            end
            if mod._cos_custom_illusion_sent then
                mod._cos_custom_illusion_sent[tostring(peer_id)] = nil
            end
            if printf then printf("[la-state] PEER-PURGE executed peer=%s (no re-add within 30s - genuine leave)",
                tostring(peer_id)) end
        end
    end
end

-- ALL PEERS: receives the authoritative apply broadcast. Only accept it from
-- the host (defense against malicious peers spoofing).
mod:network_register("cos_la_apply", function(sender_peer_id, schema_version, payload)
    if schema_version ~= COS_RPC_SCHEMA then  -- #45: drop cross-version payloads
        _dbg_alert("[rpc:schema] cos_la_apply mismatch from peer=%s: peer sent v%s, we expect v%d. Dropping.",
            tostring(sender_peer_id), tostring(schema_version), COS_RPC_SCHEMA)
        if printf then printf("[rpc:schema] cos_la_apply DROP peer=%s sent=v%s expect=v%d",
            tostring(sender_peer_id), tostring(schema_version), COS_RPC_SCHEMA) end
        return
    end
    if type(payload) ~= "table" then return end
    local host = _host_peer_id()
    if host and sender_peer_id ~= host then
        _dbg_alert("[cos_la_apply] reject non-host sender %s (host=%s)",
            tostring(sender_peer_id), tostring(host))
        return
    end
    local wearer       = payload.wearer_peer_id
    local slot_name    = payload.slot
    local kind         = payload.kind
    local armoury_key  = payload.armoury_key
    local vanilla_key  = payload.vanilla_key
    local wearer_career = payload.wearer_career
    -- v0.9.9.4-dev: tolerate older peers that don't send hand_field;
    -- treat as left_hand_unit for offhand/illusion (legacy default).
    local hand_field   = payload.hand_field
    if (kind == "offhand" or kind == "illusion") and not hand_field then
        hand_field = "left_hand_unit"
    end
    -- v0.9.69-dev (#265 Slice 1): authoritative REVERT. Delete the store
    -- entry and restore the native render (pulse / hat re-create) via the
    -- receiver helper defined after _ensure_offhand_mesh. Placed BEFORE the
    -- armoury_key guard -- a revert carries none by design.
    if payload.revert then
        if wearer and slot_name and kind and mod._la_apply_revert_recv then
            mod._la_apply_revert_recv(wearer, slot_name, kind, payload.vanilla_key, hand_field)
        end
        return
    end
    -- v0.9.82-dev (#416): VANILLA offhand mesh sync (its own payload field; no
    -- armoury_key). Placed BEFORE the armoury_key gate, mirroring the revert branch.
    -- Non-mod peers never receive this VMF mod RPC, so the #421 vanilla-wire floor
    -- is a separate axis, untouched. offhand_unit "" clears (revert to base offhand).
    if payload.offhand_unit ~= nil then
        if wearer and slot_name and mod._store_offhand_mesh_recv then
            mod._store_offhand_mesh_recv(wearer, slot_name, hand_field, payload.offhand_unit)
        end
        return
    end
    if not (wearer and slot_name and kind and armoury_key) then return end
    local wearer_unit = _wearer_unit_for_peer(wearer)
    local active_career = wearer_unit and mod._la_career_for_unit(wearer_unit)
    local career_ok, career_reason = mod._cos_husk_identity.transport_career_valid(
        wearer_career, active_career)
    if not career_ok then
        if printf then printf("[cos:698] RECV SKIP wearer=%s slot=%s reason=%s",
            tostring(wearer), tostring(slot_name), tostring(career_reason)) end
        return
    end

    -- v0.9.0.7-hotfix: MIRROR THE CACHE WRITE ON CLIENTS.
    -- Previously only the HOST's `cos_la_apply_req` register handler (see
    -- the `mod:network_register("cos_la_apply_req", ...)` block above)
    -- wrote to `_la_equips_by_peer`. Clients received the broadcast and
    -- ran the apply once, but never recorded the entry — so:
    --   1. The v0.9.0.5 husk-wield re-paint hook silently no-op'd on
    --      every client (lookup returned nil every time).
    --   2. The v0.9.0.6 husk-mesh-swap in get_item_units also no-op'd
    --      on clients (same nil lookup) → kind="unit" Ostermark shields
    --      stayed vanilla on the client viewing the host.
    -- Fix: mirror the host's write here so EVERY peer (host + clients)
    -- maintains the same `_la_equips_by_peer` cache state. The host's
    -- own broadcast loops back via "all" → this handler fires on the
    -- host too, but the write is idempotent (entry already there from
    -- the cos_la_apply_req handler).
    _la_equips_by_peer[wearer] = _la_equips_by_peer[wearer] or {}
    _la_equips_by_peer[wearer][slot_name] = mod._cos_husk_identity.new_entry(
        kind, armoury_key, vanilla_key, hand_field, wearer_career)
    -- v0.9.82-dev (#416): mutual exclusion -- an LA armoury pick supersedes any
    -- parallel vanilla mesh on the SAME (wearer, slot, hand) so the husk vanilla
    -- branch can't shadow the LA mesh (the switch vanilla->LA case).
    do
        local vslot = mod._offhand_mesh_by_peer[wearer] and mod._offhand_mesh_by_peer[wearer][slot_name]
        if vslot then vslot[hand_field] = nil end
    end
    -- v0.9.0.11-hotfix: diagnostic — count cache entries to confirm the write
    -- actually persisted (and to verify the upvalue scope fix from this version).
    local n = 0
    for _, _ in pairs(_la_equips_by_peer[wearer]) do n = n + 1 end
    _dbg("[cos_la_apply recv] CACHE WRITE _la_equips_by_peer[%s][%s] now has %d slot(s) total",
        tostring(wearer), tostring(slot_name), n)

    -- v0.9.70-dev (Slice 2 / I3): recv now routes through the single
    -- reconcile entry point (paint + gated mesh pulse, wearer-scoped).
    local applied = mod._la_reconcile(wearer, slot_name, "recv", true)
    -- v0.9.61-dev (#203): [cos-la-sync] receiver-side outcome via mod:info so it
    -- lands in the HOST's log (the missing evidence for #203 -- a client log can't
    -- show the host painting the wearer's husk). Deduped on
    -- (wearer,slot,armoury,applied) so a per-frame retry cannot flood; an
    -- applied=false->true flip logs both, showing when (or if) the paint landed.
    -- The mesh-swap + paint decision itself is in the [cos:sync] husk_meshgate /
    -- husk_meshswap / husk_offhand PROBE lines (also host-side, printf).
    do
        mod._cos_la_sync_recv_seen = mod._cos_la_sync_recv_seen or {}
        local seen_key = tostring(wearer) .. "|" .. tostring(slot_name) .. "|"
            .. tostring(armoury_key) .. "|" .. tostring(applied)
        if not mod._cos_la_sync_recv_seen[seen_key] then
            mod._cos_la_sync_recv_seen[seen_key] = true
            mod:info("[cos-la-sync] RECV wearer=%s slot=%s kind=%s armoury=%s applied=%s",
                tostring(wearer), tostring(slot_name), tostring(kind),
                tostring(armoury_key), tostring(applied))
        end
    end
    _dbg("[cos_la_apply recv] from=%s wearer=%s slot=%s kind=%s key=%s applied=%s",
        tostring(sender_peer_id), tostring(wearer), tostring(slot_name),
        tostring(kind), tostring(armoury_key), tostring(applied))
    -- [cos:sync] #149/#154: husk cache population + immediate apply outcome on a
    -- broadcast receive. applied=false here is the mission-start race (wearer not
    -- spawned yet) that gets queued below for retry. peer=husk (remote wearer).
    if PROBE then
        PROBE.emit("cos:sync",
            "recv_cache/" .. tostring(wearer) .. "/" .. tostring(slot_name) .. "/" .. tostring(armoury_key),
            string.format("peer=husk event=cache_write+apply wearer=%s from=%s slot=%s kind=%s key=%s applied=%s",
                tostring(wearer), tostring(sender_peer_id), tostring(slot_name),
                tostring(kind), tostring(armoury_key), tostring(applied)))
    end
    _trace("SYNC recv from=%s wearer=%s slot=%s kind=%s armoury=%s applied=%s",
        tostring(sender_peer_id), tostring(wearer), tostring(slot_name),
        tostring(kind), tostring(armoury_key), tostring(applied))

    -- v0.9.0.10-hotfix: TRIGGER MESH SWAP for kind="unit" variants.
    -- The husk-mesh-swap branch in BackendUtils.get_item_units only fires
    -- when SimpleHuskInventoryExtension._wield_slot runs, which happens on
    -- rpc_wield_equipment (slot_melee↔slot_ranged swaps) — NOT when the
    -- host cycles shield variants via CT's picker (which emits cos_la_apply
    -- but no wield change). For kind="unit" variants (Ostermark, Bastonne
    -- custom-mesh shields), the texture-paint path returns false (mesh swap
    -- is what's needed, not paint). Without a wield event, the husk's
    -- weapon unit stays vanilla.
    --
    -- Fix: when the variant is kind="unit" AND the entry is an offhand/
    -- illusion (weapon-side, where the wield event is meaningful), force a
    -- husk re-wield so _wield_slot → BackendUtils.get_item_units → husk-mesh-
    -- swap branch → LA mesh spawns.
    --
    -- v0.9.41-dev (#149): PULSE through the OTHER weapon slot then back,
    -- mirroring the customization-exit pulse (~line 2317), instead of
    -- inv:wield(inv.wielded_slot). NOTE: vanilla
    -- SimpleHuskInventoryExtension._wield_slot (source line 641) does NOT
    -- short-circuit on same-slot — it destroy+respawns and re-calls
    -- get_item_units every time — so same-slot WOULD re-run the swap. We pulse
    -- anyway for robustness: it guarantees a clean destroy/respawn cycle after
    -- the _la_equips_by_peer cache is populated (the client's mission-start race)
    -- and matches the established pulse pattern. We end on the ORIGINAL slot so
    -- the husk stays on the weapon the host has wielded. Pcall each wield so a
    -- failure can't crash the receiver; even if the pulse fails the rest of the
    -- apply chain ran. (The texture half of the client fix is the
    -- "network_husk" paint now allowed in _la_bridge.lua.)
    -- v0.9.64-dev (#233/#234): route through the gated _ensure_offhand_mesh helper
    -- instead of the old UNCONDITIONAL pulse. The helper no-ops when the mesh is
    -- already the LA mesh (so no flicker on a same-model re-apply), only pulses a
    -- kind="unit" mesh that is stale/vanilla AND package-resident, and is bounded by
    -- a per-owner cooldown + try-cap. Covers BOTH the host's husk (wearer=remote,
    -- #233) and the local player's own body (wearer=local peer -> players_at_peer
    -- returns the local player, #234), since cos_la_apply broadcasts to "all"
    -- including the originating client. Safe context (network callback, not a
    -- _wield_slot body).
    -- v0.9.69-dev (#268, invariant I4 targeting): the mesh pulse is scoped to
    -- THE wearer's unit only (the old players_at_peer loop force-swapped a
    -- host's BOT shields). v0.9.70-dev: the pulse now lives INSIDE
    -- mod._la_reconcile (allow_pulse=true above), so nothing extra runs here.
    if not applied then
        -- Wearer unit not spawned locally yet (loading screen race / late
        -- network spawn / husk not wielding the right slot). Queue and retry
        -- on mod.update for up to 5 seconds.
        _la_pending_apply[#_la_pending_apply + 1] = {
            wearer, slot_name, kind, armoury_key, vanilla_key, os.clock() + 5,
        }
        -- [cos:sync] #149: mission-entry / late-spawn reapply deferral. This is
        -- the "LA shield reverts at mission start" window -- apply failed now,
        -- queued for retry. peer=husk (remote wearer).
        if PROBE then
            PROBE.emit("cos:sync",
                "pending/" .. tostring(wearer) .. "/" .. tostring(slot_name) .. "/" .. tostring(armoury_key),
                string.format("peer=husk event=deferred-reapply wearer=%s slot=%s kind=%s key=%s reason=wearer-not-spawned-or-wrong-slot",
                    tostring(wearer), tostring(slot_name), tostring(kind), tostring(armoury_key)))
        end
    end
end)

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

-- Map an LA-keyed attachment slot to its cos_la_apply kind. Currently only
-- slot_hat flows through the attachment path; slot_skin is "cosmetic"
-- category and arrives via CosmeticUtils.update_cosmetic_slot instead.
local function _attachment_slot_to_kind(slot_name)
    if slot_name == "slot_hat" then return "hat" end
    return nil
end

-- PUAE is a class, string-form hook is correct.
-- v0.9.0.9-hotfix: husk-side LA-aware create_attachment.
--
-- ROOT CAUSE diagnosed by hat-reequip-diagnosis agent (HAT_REEQUIP_REQUIRED_DIAGNOSIS.md):
-- Race between vanilla `rpc_create_attachment` and CT `cos_la_apply` on the client:
--   1. Client receives cos_la_apply FIRST → CT spawns LA-textured hat unit, paint ok.
--   2. Vanilla rpc_create_attachment arrives LATE → husk's create_attachment sees the
--      LA unit as old_slot_data → `remove_attachment` destroys it (and the LA paint
--      bound to that unit's materials) → spawns fresh vanilla unit. Net result:
--      vanilla-colored hat on the client view of the husk.
-- Re-equip works because by then only one RPC pair is in flight (no late vanilla
-- RPC follows CT's spawn).
--
-- Fix: hook PlayerHuskAttachmentExtension.create_attachment. When the wearer
-- has a cached LA hat entry in _la_equips_by_peer (populated on every peer by
-- the v0.9.0.7 mirror write), pre-patch `item_data.unit = la_unit_path` BEFORE
-- delegating to vanilla — so vanilla spawns the LA mesh — then apply the
-- texture on the result. This makes the late vanilla RPC IDEMPOTENT with CT's
-- earlier apply: whichever RPC arrives second still ends up with the LA-textured
-- unit visible.
mod:hook("PlayerHuskAttachmentExtension", "create_attachment", function(func, self, slot_name, item_data)
    if slot_name ~= "slot_hat" then
        return func(self, slot_name, item_data)
    end
    local pm = Managers and Managers.player
    local husk_unit = self and self._unit
    if not pm or not husk_unit then
        return func(self, slot_name, item_data)
    end
    local wearer_player = mod._cos_husk_identity.player_for_unit(pm, husk_unit)
    local wearer_peer = wearer_player and wearer_player.peer_id
    local cached = wearer_peer and _la_equips_by_peer
        and _la_equips_by_peer[wearer_peer]
        and _la_equips_by_peer[wearer_peer][slot_name]
    if not cached or cached.kind ~= "hat" or not cached.armoury_key then
        return func(self, slot_name, item_data)
    end
    local career_ok, career_reason, active_career =
        mod._cos_husk_identity.validate_live_entry(
            cached, husk_unit, ScriptUnit, Managers, LA_PERSIST)
    if not career_ok then
        if printf then printf("[cos:698] HUSK hat SKIP wearer=%s active=%s reason=%s",
            tostring(wearer_peer), tostring(active_career), tostring(career_reason)) end
        return func(self, slot_name, item_data)
    end
    -- #697: (variant, la) via the shared resolver - `la` is non-nil ONLY when
    -- the key resolved from LA's own SKIN_LIST (mirrors _apply_la_on_unit).
    local variant, la = _resolve_la_variant(cached.armoury_key)
    local la_unit = variant and variant.new_units and variant.new_units[1]
    -- #612: the late husk attachment uses the exact Laurel donor; only its
    -- spawned material instances are changed below.
    if CUSTOM_HATS and CUSTOM_HATS.is_custom_identity(cached.armoury_key) then
        la_unit = CUSTOM_HATS.spawn_unit(Application, "remote-husk")
    end
    if not la_unit then
        return func(self, slot_name, item_data)
    end

    -- v0.9.8.5 CRASH FIX: character-mismatch gate.
    --
    -- The cached LA hat's mesh is authored for ONE specific character's
    -- skeleton. Attaching it to a body with a different skeleton makes
    -- vanilla's `Unit.node(unit, "j_spine1")` C-call fail because the
    -- expected attachment node IDs don't exist on the wrong skeleton.
    --
    -- This happens when a bot replaces a player in Chaos Wastes deus
    -- runs (or any time vanilla spawns a `player_bot_unit` with a
    -- different career than the host previously customized for). The
    -- `_la_equips_by_peer[wearer_peer]` cache holds the host's LAST
    -- chosen LA hat, but the BOT'S spawn brings a unit path for the
    -- bot's character — different from the cached LA hat's character.
    --
    -- Crash trace 2026-05-22 00:35:24 (d82119d4) AND 2026-05-22 01:11:28
    -- (95a8db3d): Sienna bot spawned (`bright_wizard_necromancer`
    -- skeleton), our hook patched the unit to
    -- `way_watcher_maiden_guard/headpiece/...` (Kerillian's hat),
    -- engine: `UnitApi node failed, node #ID[3cfac529] not found in
    -- unit #ID[...]` at `c_api_unit.cpp:74`.
    --
    -- Detection: the unit path encodes the character key as the first
    -- segment after `units/beings/player/`. If incoming (vanilla item_
    -- data.unit) and cached (la_unit) character keys differ, bail —
    -- delegate to vanilla unpatched. The wearer renders their actual
    -- character's hat; user's LA selection waits for the next wearer-
    -- side equip event to re-apply on a matching skeleton.
    --
    -- Audit 2026-05-22 found 4 unsafe patches across 2 logs; 2 crashed
    -- (Sienna body), 2 didn't (Saltzpyre body — node ID overlap with
    -- Kerillian). All 4 patterns are now defused by this gate.
    local incoming_char = item_data.unit
        and string.match(item_data.unit, "^units/beings/player/([^/]+)/")
    local la_char       = string.match(la_unit, "^units/beings/player/([^/]+)/")
    if incoming_char and la_char and incoming_char ~= la_char then
        _dbg("[husk-hat-create] character mismatch — wearer=%s incoming=%s cached_LA=%s (armoury=%s) — skipping cross-skeleton patch to avoid c_api_unit.cpp:74 crash",
            tostring(wearer_peer), tostring(incoming_char), tostring(la_char), tostring(cached.armoury_key))
        return func(self, slot_name, item_data)
    end

    -- v0.9.8.8 CRASH FIX: husk body-skeleton readiness guard.
    --
    -- Vanilla AttachmentUtils.link (attachment_utils.lua:70) calls
    -- Unit.node(owner_unit, link_data.source) for each hat-link entry. On
    -- hot-join / mid-revive the husk BODY skeleton isn't yet populated, so the
    -- source node (j_spine family) is transiently absent and Unit.node ENGINE-
    -- FATALS at c_api_unit.cpp:74 -- bypassing the pcall below (CLAUDE.md
    -- "Unit.node errors bypass pcall"). The v0.9.8.5 gate above defends the
    -- TARGET hat-mesh nodes; it does NOT cover this body-side not-ready case
    -- (same-character es_gk_hat_04->es_gk_hat_03 sails through it and still
    -- fatals -- crash GUID 9533f856, questing_knight_hat_1001 in the CW keep).
    --
    -- Unlike the removed v0.9.8.3 precheck (which returned WITHOUT calling
    -- vanilla -> "no helmet visible"), a miss here DEFERS: we call vanilla
    -- UNPATCHED so the wearer's real hat shows now, and enqueue an LA re-apply
    -- so the LA hat lands once the spine populates. The hat is never dropped.
    local _attach_owner = husk_unit
    do
        local _item_tmpl = BackendUtils and BackendUtils.get_item_template
            and BackendUtils.get_item_template(item_data)
        -- Mirror player_husk_attachment_extension.lua:61-62: link_to_skin hats
        -- parent to the third-person mesh, not the body. Check the SAME unit
        -- vanilla will pass to AttachmentUtils.link as `owner`.
        if _item_tmpl and _item_tmpl.link_to_skin then
            local _mesh = self._tp_unit_mesh
            if _mesh and Unit.alive(_mesh) then
                _attach_owner = _mesh
            end
        end
        -- The source node names are plain Lua data (attachment_utils.lua:26-27
        -- reads this same table) -- derive them up front and verify each with
        -- Unit.has_node (the non-fatal boolean companion) BEFORE the fatal call.
        local _required_body_nodes
        local _linking = _item_tmpl and _item_tmpl.attachment_node_linking
            and _item_tmpl.attachment_node_linking[slot_name]
        if _linking then
            for _, ld in ipairs(_linking) do
                if type(ld.source) == "string" then
                    _required_body_nodes = _required_body_nodes or {}
                    _required_body_nodes[#_required_body_nodes + 1] = ld.source
                end
            end
        end
        -- Proxy when the template carries no explicit linking: every player body
        -- anchors hats off the spine family, so j_spine is the readiness probe.
        if not _required_body_nodes then
            _required_body_nodes = { "j_spine" }
        end
        local _body_ready = Unit.alive(_attach_owner)
        if _body_ready then
            for _, n in ipairs(_required_body_nodes) do
                if not Unit.has_node(_attach_owner, n) then
                    _body_ready = false
                    break
                end
            end
        end
        if not _body_ready then
            _dbg_alert("[husk-hat-create] body skeleton not ready (missing source node) wearer=%s slot=%s armoury=%s -- DEFERRING re-apply, NOT dropping hat",
                tostring(wearer_peer), tostring(slot_name), tostring(cached.armoury_key))
            -- Enqueue an LA re-apply (drained per-frame in mod.update, 5s
            -- deadline-bounded). Tuple shape matches the canonical enqueue.
            _la_pending_apply[#_la_pending_apply + 1] = {
                wearer_peer, slot_name, cached.kind, cached.armoury_key, cached.vanilla_key, os.clock() + 5,
            }
            -- Vanilla runs UNPATCHED: the wearer's real hat shows THIS frame;
            -- the LA override lands a frame or two later via _try_apply_by_peer.
            return func(self, slot_name, item_data)
        end
    end

    -- v0.9.8.7: Patch item_data.unit in place and call vanilla.
    --
    -- Removed the v0.9.8.3 skeleton-readiness precheck. Reasoning:
    -- the original j_spine1 crash was caused by patching a WRONG-CHARACTER
    -- LA hat onto a body whose skeleton's node IDs didn't match the hat
    -- mesh's expected nodes. v0.9.8.5's character-mismatch gate (above)
    -- prevents that crash class at the source. With same-character
    -- hats only being patched, vanilla's attachment node lookup succeeds.
    --
    -- The v0.9.8.3 precheck was overcautious and harmful: when it
    -- triggered (frequently on hot-join / mid-revive), it returned
    -- WITHOUT calling vanilla — so the husk got NO hat at all. That's
    -- the "no helmet visible" symptom users reported.
    --
    -- pcall around vanilla call remains as a last-resort safety net.
    -- If vanilla truly errors for some unexpected edge case, we don't
    -- want to propagate up and crash the client.
    local prev_unit = item_data.unit
    item_data.unit = la_unit
    _dbg("[husk-hat-create] wearer=%s slot=%s patched unit %s -> %s (LA armoury=%s)",
        tostring(wearer_peer), tostring(slot_name), tostring(prev_unit), tostring(la_unit), tostring(cached.armoury_key))
    local ok, err = pcall(func, self, slot_name, item_data)
    item_data.unit = prev_unit
    if not ok then
        _dbg_alert("[husk-hat-create] inner create_attachment errored on wearer=%s slot=%s: %s — bailing silently",
            tostring(wearer_peer), tostring(slot_name), tostring(err))
        return
    end
    local spawned_slot = self._attachments and self._attachments.slots
        and self._attachments.slots[slot_name]
    local spawned_hat = spawned_slot and spawned_slot.unit
    if CUSTOM_HATS.is_custom_identity(cached.armoury_key) then
        CUSTOM_HATS.apply_surface(spawned_hat, "remote-husk")
    end
    if GK_SET and GK_SET.resolve_variant(cached.armoury_key) and spawned_hat then
        GK_SET.apply_variant_to_unit(cached.armoury_key, spawned_hat, "remote_husk")
    end
    -- Paint the LA texture onto the just-spawned hat unit (mirrors the
    -- _apply_la_on_unit hat branch). #697: la=nil for cosmetics-side variants
    -- (GK_SET/CUSTOM_HATS paint above; LA funcs.lua:65 nil-derefs foreign keys).
    if la and type(la.apply_new_skin_from_texture) == "function" then
        local world = _level_world()
        local slot_data = self._attachments and self._attachments.slots and self._attachments.slots[slot_name]
        local hat_unit = slot_data and slot_data.unit
        if world and hat_unit and Unit.alive(hat_unit) then
            LA_BRIDGE._bridge_active = true
            local paint_ok, paint_err = pcall(la.apply_new_skin_from_texture, cached.armoury_key, world, cached.vanilla_key, hat_unit)
            LA_BRIDGE._bridge_active = false
            _dbg("[husk-hat-create] paint %s on hat_unit=%s ok=%s",
                tostring(cached.armoury_key), tostring(hat_unit), tostring(paint_ok))
            if not paint_ok then
                _dbg_alert("[husk-hat-create] paint err key=%s vanilla=%s: %s", tostring(cached.armoury_key), tostring(cached.vanilla_key), tostring(paint_err)) -- #697: key must ride the printf-backed channel
            end
        end
    elseif not la then
        _dbg("[husk-hat-create] LA paint n/a for %s (cosmetics-side variant, #697)", tostring(cached.armoury_key))
    end
    APPEARANCE_FADE_RUNTIME.enroll_husk_attachment(husk_unit, self, spawned_hat)
end)

APPEARANCE_FADE_RUNTIME.install({
    identity = mod._cos_husk_identity,
    get_store = function() return _la_equips_by_peer end,
    la_persist = LA_PERSIST,
})

-- v0.9.8.7: the v0.9.8.4 + v0.9.8.6 PlayerHuskAttachmentExtension.remove_attachment
-- guard pair has been removed entirely.
--
-- The guard existed to handle the case where v0.9.8.3's skeleton-readiness
-- precheck silently bailed — leaving `_attachments.slots[slot_name]` nil
-- when vanilla then tried to remove a hat that was never created.
--
-- v0.9.8.7 removed the v0.9.8.3 precheck (rendered unnecessary by
-- v0.9.8.5's character-mismatch gate which prevents the original crash
-- class). Without the precheck, vanilla always populates `_attachments.slots`
-- normally — so this guard has no failure mode left to defend against.
-- Removing it eliminates one more layer of speculative hook code that
-- could regress in subtle ways.

mod:hook("PlayerUnitAttachmentExtension", "game_object_initialized", function(func, self, unit, unit_go_id)
    local slots = self._attachments and self._attachments.slots
    local restore = nil
    local la_slots = nil  -- entries: { slot_name, la_backend_id, vanilla_key }
    if slots then
        for slot_name, slot_data in pairs(slots) do
            local item_data = slot_data and slot_data.item_data
            local orig = item_data and item_data.name
            local career = mod._la_career_for_unit and mod._la_career_for_unit(unit); local vanilla = _la_substitute_name(orig, career)
            if vanilla then
                restore = restore or {}
                restore[#restore + 1] = { item_data, orig }
                item_data.name = vanilla
                la_slots = la_slots or {}
                la_slots[#la_slots + 1] = { slot_name, orig, vanilla }
            end
        end
    end
    local ok, err = pcall(func, self, unit, unit_go_id)
    if restore then
        for i = 1, #restore do
            restore[i][1].name = restore[i][2]
        end
    end
    if not ok then error(err) end
    if la_slots then
        for i = 1, #la_slots do
            local slot_name, la_id, vanilla = la_slots[i][1], la_slots[i][2], la_slots[i][3]
            local kind = _attachment_slot_to_kind(slot_name)
            local armoury_key = LA_BRIDGE.backend_to_armoury and LA_BRIDGE.backend_to_armoury[la_id]
            if kind and armoury_key then
                _send_la_apply(unit, slot_name, kind, armoury_key, vanilla)
            end
        end
    end
end)

mod:hook("PlayerUnitAttachmentExtension", "spawn_resynced_loadout", function(func, self, item_to_spawn)
    local item_data = item_to_spawn and item_to_spawn.item_data
    local orig = item_data and item_data.name
    local career = mod._la_career_for_unit and mod._la_career_for_unit(self._unit); local vanilla = _la_substitute_name(orig, career)
    if vanilla then
        item_data.name = vanilla
        local ok, err = pcall(func, self, item_to_spawn)
        item_data.name = orig
        if not ok then error(err) end
        local slot_name = item_to_spawn.slot_id
        local kind = slot_name and _attachment_slot_to_kind(slot_name)
        local armoury_key = LA_BRIDGE.backend_to_armoury and LA_BRIDGE.backend_to_armoury[orig]
        if kind and armoury_key and self._unit then
            _send_la_apply(self._unit, slot_name, kind, armoury_key, vanilla)
        end
        return
    end
    return func(self, item_to_spawn)
end)
_net_safe_hook_status.PUAE = true

-- AttachmentUtils is a PLAIN TABLE (`AttachmentUtils = AttachmentUtils or {}`
-- at attachment_utils.lua:1). Same string-form pitfall as CosmeticUtils/
-- LoadoutUtils — must use table-form with nil guard, else hook silently
-- never registers.
if AttachmentUtils then
    mod:hook(AttachmentUtils, "hot_join_sync", function(func, peer_id, unit, slots, synced_buffs)
        local restore = nil
        local la_slots = nil  -- entries: { slot_name, la_backend_id, vanilla_key }
        if slots then
            for slot_name, slot_data in pairs(slots) do
                local orig = slot_data and slot_data.name
                local career = mod._la_career_for_unit and mod._la_career_for_unit(unit); local vanilla = _la_substitute_name(orig, career)
                if vanilla then
                    restore = restore or {}
                    restore[#restore + 1] = { slot_data, orig }
                    slot_data.name = vanilla
                    la_slots = la_slots or {}
                    la_slots[#la_slots + 1] = { slot_name, orig, vanilla }
                end
            end
        end
        local ok, err = pcall(func, peer_id, unit, slots, synced_buffs)
        if restore then
            for i = 1, #restore do
                restore[i][1].name = restore[i][2]
            end
        end
        if not ok then error(err) end
        -- v0.8.67-dev: signature change — _send_la_apply now routes through
        -- the host (server-authoritative). The host's broadcast to "all"
        -- includes the joining peer, so per-peer targeting is no longer
        -- needed. Each existing peer's hot_join_sync still fires its own
        -- emits for its own equips; the host receives each request, records
        -- in _la_equips_by_peer (idempotent overwrite), and re-broadcasts.
        -- Slight redundancy (each peer's equips broadcast to everyone again
        -- on each new joiner), but correct.
        if la_slots then
            for i = 1, #la_slots do
                local slot_name, la_id, vanilla = la_slots[i][1], la_slots[i][2], la_slots[i][3]
                local kind = _attachment_slot_to_kind(slot_name)
                local armoury_key = LA_BRIDGE.backend_to_armoury and LA_BRIDGE.backend_to_armoury[la_id]
                if kind and armoury_key then
                    _send_la_apply(unit, slot_name, kind, armoury_key, vanilla)
                end
            end
        end

        -- Replay non-attachment LA cosmetics (slot_skin armor, weapon-slot
        -- offhand picks, weapon-illusion paints). AttachmentUtils.hot_join_sync
        -- only walks "attachment"-category slots so these need explicit replay.
        --
        -- v0.9.0-dev: previously read ONLY `_local_la_equips[unit]`, which is
        -- populated solely by the local player's CosmeticUtils.update_cosmetic_slot
        -- hook → contains entries only for the LOCAL player's player_unit. When
        -- the host's hot_join_sync iterates OTHER existing players to replay
        -- their state to the new joiner, the lookup misses for every non-local
        -- unit, so the new joiner never received those peers' armor/illusion
        -- selections. Now we ALSO consult `_la_equips_by_peer` (authoritative
        -- per-peer store, populated by the host's cos_la_apply_req handler) and
        -- replay every recorded slot for the wearer-peer.
        do
            local equips = _local_la_equips[unit]
            if equips then
                for slot_name, la_id in pairs(equips) do
                    local kind = nil
                    if slot_name == "slot_skin" then
                        kind = "armor"
                    elseif slot_name ~= "slot_hat" then
                        kind = "illusion"
                    end
                    local armoury_key = LA_BRIDGE.backend_to_armoury and LA_BRIDGE.backend_to_armoury[la_id]
                    local career = mod._la_career_for_unit and mod._la_career_for_unit(unit); local vanilla = _la_vanilla_fallback(la_id, career)
                    if (kind == "armor" or kind == "illusion") and armoury_key then
                        _send_la_apply(unit, slot_name, kind, armoury_key, vanilla)
                    end
                end
            end

            -- v0.9.0.12-hotfix: TARGETED hot-join replay to the joining peer.
            -- Previous version called _send_la_apply which always uses "all" —
            -- but at hot_join_sync time the joiner may not yet be in the
            -- "all" target list (handshake not complete). User report v0.9.0.11:
            -- "someone joining a lobby where the hat or shield is already
            -- equipped won't see it until the other player changes their
            -- cosmetic selection". The change-broadcast hits because by then
            -- the joiner is fully connected; the initial hot-join replay
            -- raced and lost. Fix: bypass _send_la_apply, fire
            -- cos_la_apply DIRECTLY targeted at the joining peer_id.
            if _is_local_server() then
                local pm = Managers and Managers.player
                local owner = pm and pm.owner and pm:owner(unit)
                local wearer_peer = owner and owner.peer_id
                local peer_equips = wearer_peer and _la_equips_by_peer[wearer_peer]
                if peer_equips then
                    local n = 0
                    for slot_name, entry in pairs(peer_equips) do
                        if entry and entry.kind and entry.armoury_key then
                            mod:network_send("cos_la_apply", peer_id, COS_RPC_SCHEMA, {
                                wearer_peer_id = wearer_peer,
                                slot           = slot_name,
                                kind           = entry.kind,
                                armoury_key    = entry.armoury_key,
                                vanilla_key    = entry.vanilla_key,
                                hand_field     = entry.hand_field,
                                wearer_career  = entry.wearer_career,
                            })
                            n = n + 1
                        end
                    end
                    if n > 0 then
                        _dbg("[hot-join replay] sent %d cos_la_apply entries targeted at joiner=%s for wearer=%s",
                            n, tostring(peer_id), tostring(wearer_peer))
                    end
                end
                -- v0.9.0.12-hotfix: glow rebroadcast also targeted at joiner.
                if mod._glow_rebroadcast_targeted then
                    mod._glow_rebroadcast_targeted(peer_id)
                end
            end

            -- Offhand: replay the local player's CURRENTLY-wielded weapon
            -- backend if it has an LA offhand selection.
            local pm = Managers and Managers.player
            local local_player = _local_player_safe(pm)
            local local_unit = local_player and local_player.player_unit
            if local_unit == unit then
                local inv = ScriptUnit.has_extension(unit, "inventory_system")
                local equipment = inv and inv._equipment
                local wielded_slot = equipment and equipment.wielded_slot
                local slot_data = wielded_slot and equipment.slots and equipment.slots[wielded_slot]
                local item_data = slot_data and slot_data.item_data
                local bid = item_data and item_data.backend_id
                if bid then _offhand_session_state.migrate_legacy(bid) end
                local per_hand_sel = bid and _offhand_selection[bid]
                if type(per_hand_sel) == "table" then
                    -- v0.9.72-dev: key the replay by the weapon TEMPLATE, not
                    -- the wielded slot. This site was the only writer of the
                    -- legacy "slot_melee"-style offhand keys (host 18:35:44
                    -- evidence) - a namespace the weapon-identity guard in
                    -- _apply_la_on_unit can never match to an item.
                    local replay_key = (item_data and item_data.template) or wielded_slot
                    for hand_field, sel in pairs(per_hand_sel) do
                        if type(sel) == "table" and sel.la_armoury_key then
                            _send_la_apply(unit, replay_key, "offhand",
                                sel.la_armoury_key, sel.vanilla_skin, hand_field)
                        elseif type(sel) == "table" and type(sel.unit) == "string"
                                and sel.unit ~= "" and mod._send_offhand_mesh then
                            mod._send_offhand_mesh(unit, replay_key,
                                hand_field, sel.unit)
                        end
                    end
                end
            end
        end
    end)
    _net_safe_hook_status.AttachmentUtils = true
end

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
