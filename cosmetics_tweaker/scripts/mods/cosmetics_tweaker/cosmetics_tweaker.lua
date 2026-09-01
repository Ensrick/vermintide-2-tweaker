local mod = get_mod("cosmetics_tweaker")
local RESOURCE_RESIDENCY = mod:dofile(
    "scripts/mods/cosmetics_tweaker/_lib_resource_residency")
local WEAPON_APPEARANCE = mod:dofile("scripts/mods/cosmetics_tweaker/_lib_weapon_appearance").new()

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

local U = mod:dofile("scripts/mods/cosmetics_tweaker/_cosmetic_unlocks"); mod._cos_network_lookup = mod:dofile("scripts/mods/cosmetics_tweaker/_lib_network_lookup")
mod._cos_la_registration_owner_module = mod:dofile("scripts/mods/cosmetics_tweaker/_la_registration_owner"); local LA_BRIDGE = mod:dofile("scripts/mods/cosmetics_tweaker/_la_bridge")
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
-- ([174:loadout] retired with #174/#500; _diag_probe renamed per §2.2b/#499.)
local PROBE      = mod:dofile("scripts/mods/cosmetics_tweaker/_cos_diag_lasync")

local MOD_VERSION = "0.9.219-dev"
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
mod._cos.weapon_appearance = WEAPON_APPEARANCE
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
-- #420: the equipment/preview helpers capture the shared instance installed above.
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
local _cos_glow_diagnostics_runtime = mod:dofile(
    "scripts/mods/cosmetics_tweaker/_cos_glow_diagnostics_runtime").install(mod, {
    printf = rawget(_G, "printf"),
})
local _cos574_log = _cos_glow_diagnostics_runtime.log


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
    offhand_commit = OFFHAND_COMMIT, la_persist = LA_PERSIST,
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

-- Independent-offhand catalog state owner (#1159). It shares the canonical
-- catalog/selection tables with the picker and render owners, but owns every
-- catalog-state transition: merge, exact-instance restore, lazy lookup, and
-- receiver-side dual-unit validation. No hook/RPC/command/update registration.
local _cos_offhand_state_runtime = mod:dofile(
    "scripts/mods/cosmetics_tweaker/_cos_offhand_state_runtime").install(mod, {
    gk_set = GK_SET,
    la_bridge = LA_BRIDGE,
    la_persist = LA_PERSIST,
    offhand_names = OFFHAND_NAMES,
    decorate_shield_option = _decorate_shield_option,
    offhand_options = _offhand_options,
    offhand_selection = _offhand_selection,
    preload_offhand_package = _preload_offhand_package,
    preload_offhand_for_option = _preload_offhand_for_option,
    get_mod = get_mod,
    get_managers = function() return Managers end,
    get_item_master_list = function() return ItemMasterList end,
    now = os.clock,
    printf = printf,
})
local _merge_la_offhand_options =
    _cos_offhand_state_runtime.merge_la_offhand_options
local _get_offhand_options = _cos_offhand_state_runtime.get_offhand_options

-- #376/#650 engine-facing exact-instance item-card owner. The engine-free
-- descriptor policy remains in _cos_item_presentation.lua; this adapter owns
-- the one UIUtils hook and exports the same functions consumed later in entry.
local _cos_item_presentation_runtime = mod:dofile(
    "scripts/mods/cosmetics_tweaker/_cos_item_presentation_runtime").install(mod, {
    composite_icon_factory = COMPOSITE_ICON_FACTORY,
    ui_atlas_helper = UIAtlasHelper,
    get_application = function() return Application end,
    la_persist = LA_PERSIST,
    get_item_master_list = function() return ItemMasterList end,
    get_weapon_skins = function() return WeaponSkins end,
    offhand_selection = _offhand_selection,
    glow_picker = GlowPicker,
    composite_icons = COMPOSITE_ICONS,
    offhand_names = OFFHAND_NAMES,
    shield_icon_owner_item_types = _SHIELD_ICON_OWNER_ITEM_TYPES,
    offhand_options = _offhand_options,
    get_mod = get_mod,
    la_bridge = LA_BRIDGE,
    inventory_icon_for_offhand_unit = _inventory_icon_for_offhand_unit,
    item_presentation = ITEM_PRESENTATION,
    la_icon_provider = mod._la_icon_provider,
    la_instance_policy = mod._la_instance_policy,
    offhand_session_state = _offhand_session_state,
    get_localize = function() return rawget(_G, "Localize") end,
    ui_utils = UIUtils,
})
_cos_resolve_composed_appearance =
    _cos_item_presentation_runtime.resolve_composed_appearance
local _cos_active_skin = _cos_item_presentation_runtime.active_skin

-- #925: extracted retained-card refresh/publisher; callers compose singleton seams.
mod:dofile("scripts/mods/cosmetics_tweaker/_cos_ui_presentation_refresh").install(mod, {
    la_bridge = LA_BRIDGE, rt_register = _rt_register,
})

mod:dofile("scripts/mods/cosmetics_tweaker/_cos_offhand_diagnostics").install(mod, {
    la_bridge = LA_BRIDGE,
    offhand_options = _offhand_options,
    offhand_selection = _offhand_selection,
    surfaces = { BackendUtils = BackendUtils, UIWidget = UIWidget, UIWidgets = UIWidgets, UIRenderer = UIRenderer, Colors = Colors },
})

-- The catalog owner asynchronously preloads every selectable 1P/3P offhand
-- package on every peer before synchronous husk wield can spawn it. Readiness
-- gates fail closed to the base mesh; repeated requests are idempotent.

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

-- BackendUtils is a plain table: its owner uses a nil-guarded table-form hook.
-- The remote-husk owner keeps the stack-style wield context. It is loaded here
-- so the equipment-assembly hook can consume its stable accessor before the
-- actual _wield_slot hook installs at its historical position below.
local HUSK_WIELD_RUNTIME = mod:dofile(
    "scripts/mods/cosmetics_tweaker/_cos_husk_wield_runtime")
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

mod:dofile("scripts/mods/cosmetics_tweaker/_cos_deus_yield_policy").install(mod, {
    get_managers = function() return Managers end,
    printf = printf,
})
mod:dofile("scripts/mods/cosmetics_tweaker/_cos_diag_deus_yield") -- #518 bounded solo-visible diagnostics: printf-only emitter + owner-wield / paint-skip helpers wired below, plus the husk-miss helper the equipment-assembly owner calls (#1159)

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
-- mod._cos.glow_owner_peer_for_unit. Status/trace commands and bounded #574
-- evidence live in _cos_glow_diagnostics_runtime; transport lives in
-- _cos_glow_transport.lua.

_cos_glow_diagnostics_runtime.install_commands(GlowPicker)
-- Do not restore bulk live repaint: painting invisible/sheathed 1P units broke
-- inspect and hand meshes. Glow changes converge on the next bounded wield or
-- spawn through the owned material-apply pipeline.

-- _offset_units (grip-offset apply) moved to _cos_render.lua (v0.9.78-dev
-- Phase 2 OOP split); the in-game render hook below calls mod._cos.offset_units.

-- Local offhand apply owner (#1159). The mesh-match gate and authored paint
-- dispatch remain one transaction shared by live equipment and both previewers.
-- Mutable customization identity crosses through a getter; every other hand-off
-- is bound above this install and never rebound.
local _cos_offhand_apply_runtime = mod:dofile(
    "scripts/mods/cosmetics_tweaker/_cos_offhand_apply_runtime").install(mod, {
    gk_set = GK_SET,
    la_bridge = LA_BRIDGE,
    probe = PROBE,
    dbg = _dbg,
    trace = _trace,
    trace_paint = _trace_paint,
    unit_mesh_name = _unit_mesh_name,
    is_unit = _is_unit,
    offhand_selection = _offhand_selection,
    offhand_session_state = _offhand_session_state,
    get_offhand_options = _get_offhand_options,
    resolve_authored_offhand_variant = _resolve_authored_offhand_variant,
    get_item_master_list = function() return ItemMasterList end,
    get_active_customization_backend_id = function()
        return _active_customization_backend_id
    end,
})
local _resolve_item_type = _cos_offhand_apply_runtime.resolve_item_type
local _offhand_paint_mesh_ok =
    _cos_offhand_apply_runtime.offhand_paint_mesh_ok
local _apply_authored_offhand_to_unit =
    _cos_offhand_apply_runtime.apply_authored_offhand_to_unit
local _apply_la_offhand_to_units = _cos_offhand_apply_runtime.apply_la_offhand_to_units
local _cos_cim_preview = mod:dofile("scripts/mods/cosmetics_tweaker/_cos_cim_preview_wiring")(mod, get_mod, _get_offhand_options, _offhand_session_state, _offhand_selection, _resolve_authored_offhand_variant, _apply_authored_offhand_to_unit, _is_unit, LA_BRIDGE)
-- In-game keep / mission body + the item unit-table resolution it brackets.
-- THREE RENDERING PATHS COVERAGE:
--   - In-game (GearUtils.create_equipment): _cos_equipment_assembly.lua
--   - Inventory previewer (HeroPreviewer._spawn_item): _cos_preview_runtime.lua
--   - Illusion browser (LootItemUnitPreviewer.spawn_units): _cos_preview_runtime.lua
--
-- The remote-husk owner and entry-owned active customization identity are
-- reached through accessors, never handed over by value: both are rebound.
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
    resolve_authored_offhand_variant = _resolve_authored_offhand_variant, cim_preview = _cos_cim_preview,
    get_current_husk_wield = function()
        return HUSK_WIELD_RUNTIME.current(mod)
    end,
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
    get_mod = get_mod, cim_preview = _cos_cim_preview,
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

-- ============================================================
-- LA remote-husk identity and spawn owner
--   -> _cos_la_husk_identity_runtime.lua (#1159)
-- ============================================================
-- Installs at the first declaration in the former block. No hooks, commands,
-- or module loads occurred before its original init-hook site, so registration
-- order is unchanged while every identity consumer shares one policy owner.
local _cos_la_husk_identity_runtime = mod:dofile(
    "scripts/mods/cosmetics_tweaker/_cos_la_husk_identity_runtime").install(
        mod, {
            gk_set = GK_SET,
            custom_hats = CUSTOM_HATS,
            get_mod = get_mod,
            husk_identity = mod._cos_husk_identity,
            la_bridge = LA_BRIDGE,
            la_equips_by_peer = _la_equips_by_peer,
            la_persist = LA_PERSIST,
            score_identity = SCORE_IDENTITY,
            script_unit = ScriptUnit,
            unit = Unit,
            get_managers = function() return Managers end,
            get_profiles = function() return rawget(_G, "SPProfiles") end,
            la_replay_policy = LA_REPLAY_POLICY,
            dbg = _dbg,
            dbg_alert = _dbg_alert,
            printf = printf,
        })
local _resolve_la_variant =
    _cos_la_husk_identity_runtime.resolve_la_variant
local _la_chars_compatible =
    _cos_la_husk_identity_runtime.chars_compatible
local _purge_stale_peer_slot =
    _cos_la_husk_identity_runtime.purge_stale_peer_slot
local _level_world = _cos_la_husk_identity_runtime.level_world

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

-- #641/#629 Hold-Tab peer-cache phase. Install only after LA transport owns
-- its receivers, preserving the historical availability boundary.
_cos_item_presentation_runtime.install_peer({
    la_equips_by_peer = _la_equips_by_peer,
    get_offhand_mesh_by_peer = function() return mod._offhand_mesh_by_peer end,
})

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

-- ============================================================
-- Remote-husk wield transaction -> _cos_husk_wield_runtime.lua (#1159)
-- ============================================================
-- Installs at the exact former hook site. The owner keeps the context bracket,
-- resolved-unit residency probe, vanilla return preservation, glow repaint,
-- and LA reconcile in one atomic callback.
HUSK_WIELD_RUNTIME.install(mod, {
    get_managers = function() return Managers end,
    husk_identity = mod._cos_husk_identity,
    la_equips_by_peer = _la_equips_by_peer,
    get_application = function() return Application end,
    get_weapon_skins = function() return WeaponSkins end,
    glow_by_peer = _glow_by_peer,
    complete_glow_rehydrate = _cos574_complete_glow_rehydrate,
    dbg = _dbg,
    dbg_alert = _dbg_alert,
    trace = _trace,
    glow_log = _cos574_log,
    printf = printf,
})

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

-- VMF calls the dedicated scheduler once per frame. Install at the exact former
-- mod.update boundary so all dependencies above are initialized before the
-- scheduler becomes visible and all diagnostics below retain their order.
mod._cos_update_scheduler_owner = mod:dofile(
    "scripts/mods/cosmetics_tweaker/_cos_update_scheduler").install(mod, {
    custom_hats = CUSTOM_HATS,
    la_persist = LA_PERSIST,
    la_bridge = LA_BRIDGE,
    gk_set = GK_SET,
    get_mod = get_mod,
    get_item_master_list = function() return ItemMasterList end,
    merge_la_offhand_options = _merge_la_offhand_options,
    force_load_all_offhand_packages = _force_load_all_offhand_packages,
    install_skin_loadout_safety = _install_skin_loadout_safety,
    local_player_safe = _local_player_safe,
    la_equips_by_peer = _la_equips_by_peer,
    wearer_unit_for_peer = _wearer_unit_for_peer,
    get_la_bridge_init_done = function() return _la_bridge_init_done end,
    set_la_bridge_init_done = function(v) _la_bridge_init_done = v end,
    is_local_server = _is_local_server,
    host_peer_id = _host_peer_id,
    local_peer_id_quick = _local_peer_id_quick,
    rpc_schema = COS_RPC_SCHEMA,
    get_managers = function() return Managers end,
    now = os.clock,
    printf = printf,
    la_okri = LA_OKRI,
    tpe = TPE,
    glow_picker = GlowPicker,
    get_la_pending_apply = function() return _la_pending_apply end,
    set_la_pending_apply = function(t) _la_pending_apply = t end,
})

local _cos_diag_glow = mod:dofile("scripts/mods/cosmetics_tweaker/_cos_diag_glow")
_cos_diag_glow.install(mod, {
    local_player_safe = _local_player_safe, is_unit = _is_unit, flush_log = _flush_log,
})
local _wielded_units_for_probe = _cos_diag_glow.wielded_units_for_probe
-- ============================================================
-- Attachment / preview spawn boundary -> _cos_spawn_boundary.lua (#1159)
-- ============================================================
-- Keeps residency, safe linking, MH-before-vanilla, LA-after-vanilla, authored
-- hat surfaces, preview glow identity, and score-hat paint in one ordered owner.
-- Splitting these writes across hooks on the same spawn seam would make their
-- final-writer order implicit again.
mod:dofile("scripts/mods/cosmetics_tweaker/_cos_spawn_boundary").install(mod, {
    application = Application,
    attachment_utils = rawget(_G, "AttachmentUtils"),
    world = rawget(_G, "World"),
    unit = Unit,
    la_bridge = LA_BRIDGE,
    custom_hats = CUSTOM_HATS,
    gk_set = GK_SET,
    mh_embed = MH_EMBED,
    attachment_link_policy = mod._cos_attachment_link_policy,
    get_mod = get_mod,
    dbg = _dbg,
    printf = printf,
})

-- v0.9.8.2: the `_equip_item_capture_bid` hook_safe pair collided with the
-- existing equip_item mod:hook registrations (VMF rehook warnings); the bid
-- stash is FOLDED into those hooks - do not re-add a separate registration.

local _cos_la_commands = mod:dofile("scripts/mods/cosmetics_tweaker/_cos_la_commands")
_cos_la_commands.install(mod, {
    la_bridge = LA_BRIDGE, local_player_safe = _local_player_safe,
    get_managers = function() return Managers end, flush_log = _flush_log,
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
-- Glow picker host integration -> _cos_glow_picker_host.lua (#1159)
-- ============================================================
-- Owns the five verified cosmetic-window hooks plus the two manual diagnostic
-- commands. Installed at the former inline position to preserve registration
-- order; dependencies refresh through a stable hot-reload state holder.
mod:dofile("scripts/mods/cosmetics_tweaker/_cos_glow_picker_host").install(mod, {
    glow_picker = GlowPicker,
    printf = printf,
    mod_version = MOD_VERSION,
    wielded_units_for_probe = _wielded_units_for_probe,
})

-- ============================================================
-- Local wield appearance replay -> _cos_local_wield_runtime.lua (#1159)
-- ============================================================
-- Owns the local player's already-spawned LA offhand and per-item glow replay.
-- The remote husk path remains in its existing transport/render owners.
mod:dofile("scripts/mods/cosmetics_tweaker/_cos_local_wield_runtime").install(mod, {
    local_player_safe = _local_player_safe,
    get_managers = function() return Managers end,
    unit = Unit,
    la_equips_by_peer = _la_equips_by_peer,
    glow_picker = GlowPicker,
    trace = _trace,
    glow_log = _cos574_log,
    probe = PROBE,
})

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
    weapon_appearance = WEAPON_APPEARANCE,
    cwv_peer_identity = mod._cos_cwv_peer_identity,
    la_instance_policy = mod._la_instance_policy,
    modded_illusion_swap_owner = mod._cos_modded_illusion_swap_owner, active_skin = _cos_active_skin, offhand_selection = _offhand_selection, -- #25
    issue704_picker_family = function(surface, family, _, owner_item_type)
        return mod._cos.classify_issue704_picker_family(surface, family, mod._cwv_dual_offhand_contract, owner_item_type)
    end,
})
-- ============================================================
-- Moonfire Bow cosmetic impact owner -> _cos_moonfire_puff_runtime.lua (#1159)
-- ============================================================
mod:dofile("scripts/mods/cosmetics_tweaker/_cos_moonfire_puff_runtime").install(mod, {
    get_mod = get_mod,
    get_class = function(class_name) return rawget(_G, class_name) end,
    get_world = function() return World end,
    get_quaternion = function() return Quaternion end,
})
