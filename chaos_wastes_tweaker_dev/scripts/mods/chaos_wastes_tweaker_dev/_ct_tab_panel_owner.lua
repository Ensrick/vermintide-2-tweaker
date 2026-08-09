--[[
_ct_tab_panel_owner — the hold-Tab player-list panel (#1159 / #2 file-size refactor).

RESPONSIBILITY
Owns every ct addition to IngamePlayerListUI, the hold-Tab overlay, and nothing
else:
  * the #461 Starting-Boon preview built on panel activation in the Pilgrimage
    Chamber, its #1004 hover tooltip pump, and the /ct_preview_boons text mirror
  * the #533 Chaos Wastes collectible counters (Chests of Trials, Pilgrim's
    Coins) that replace vanilla's tome/grimoire/dice counters inside a deus run
  * the single consolidated draw pass both overlays share
  * the wiring of the three side modules this panel drives:
    _ct_boon_preview_tooltip (policy), _ct_boon_preview_runtime (#1004 widget
    runtime), _ct_boon_preview_helpers (identity + row builders),
    _ct_diag_tab_native533 (native census), _ct_tab_collectibles_layout (#571
    native offsets)
  * the six regression checks those features register

Extracted VERBATIM from chaos_wastes_tweaker_dev.lua with no behaviour change.
mod:dofile is not a singleton — the entry calls it EXACTLY once, at the exact
point this block previously executed (immediately after the
DeusRunController._add_initial_power_ups starting-boon grant hook, immediately
before the #458 start-shrine dofiles), so hook-registration order, side-module
load order, and _rt_register append order all keep their original timing.

COMPOSES WITH, DOES NOT OVERLAP, THE OTHER ct OWNERS
This module is the only ct code that touches the player-list panel; no other
owner hooks IngamePlayerListUI. In particular it shares nothing with
_ct_spawn_eligibility_owner (which spawner may a pickup claim) or
_ct_pickup_spawn_owner (what that spawner produces): those two decide what
exists in the world, this one only reports run-scoped counters and previews the
configured starting boons. The counters read the replicated deus-run
SharedState through DeusRunController getters, never ct's own spawn bookkeeping.

HOOKS OWNED (each hooked EXACTLY ONCE in the whole mod — VMF silently drops a
second hook on the same Class/method pair; verified 2026-08-09):
  IngamePlayerListUI._setup_deed_reward_data (hook_safe, #461 build point)
  IngamePlayerListUI._draw                   (hook_safe, SHARED #461 + #533 pass)
  IngamePlayerListUI._setup_mission_data     (full hook, #533 build point)
_ct_diag_tab_native533 hooks the FOURTH method on this class (_set_active); it
stays in its own file and is installed from here.

COMMANDS OWNED
  /ct_preview_boons (#461 textual mirror; sole registration in the mod)

CROSS-FILE CONTRACT (unchanged by the move)
  * Entry helpers are reached through the mod._ct_* seams the entry publishes
    BEFORE this module loads: mod._ct_rt_register (entry ~337),
    mod._ct_effective_setting / mod._ct_effective_setting_source (entry ~2646),
    mod._ct_starting_talent_is_duplicate (entry ~7152), and the
    mod._ct_pilgrimage_context / mod._ct_in_pilgrimage_chamber pair published by
    _ct_dev_mission.lua (entry ~463).
  * `_rt_register` is bound once below from mod._ct_rt_register so the six moved
    checks keep their byte-identical bodies and land in the SAME shared
    _RT_CHECKS list, in the same order, as before the split.
  * The three preview seams this file drives (_ct_boon_preview_tooltip,
    _ct_boon_preview_runtime, _ct_boon_preview_helpers) are dofile'd from HERE,
    at their original positions inside the block, so mod._ct_collect_start_boons
    and friends still exist by the time the first Tab press builds a row.
  * mod._ct_ensure_deus_collectibles / mod._ct_layout_deus_collectibles come from
    _ct_tab_collectibles_layout, dofile'd near the END of this block — AFTER the
    _draw hook registers. That was already true in the entry: both are resolved
    at CALL time (first draw), never at registration time.
  * Load-time globals set here and read bare by later chunks (the /ct_regression
    suite and the QA textual gates): CT_BOON_PREVIEW_461_MARKER,
    CT_BOON_TOOLTIP_1004_MARKER, CT_CW_TAB_COLLECTIBLES_533_MARKER. They stay
    globals.
  * Published on `mod` for the regression checks and _ct_tab_collectibles_layout:
    mod._ct_read_deus_collectible_values, mod._ct_build_deus_collectibles,
    mod._ct_refresh_deus_collectibles, mod._ct_boon_preview_tooltip,
    mod._ct_diag_tab_native533.
  * NO entry file-local was left behind: the only local this block declared at
    file scope (_ct_tab_layout_571) is read solely by the #571 check two lines
    later, so it moved with the block and no promotion to a mod._ct_* field was
    needed.
]]

local mod = get_mod("ct_dev")

-- Behaviour-identical shim for the one entry file-local this block used before
-- the extraction: the shared _RT_CHECKS registrar. The entry exposes the exact
-- same function object on `mod` at its definition site, so registration order
-- and the registry itself are unchanged (PROJECT_STANDARDS § 2.2a).
local _rt_register = mod._ct_rt_register

-- ============================================================
-- Starting-Boon Preview on the Tab-hold panel (#461)
-- ============================================================
-- Feature (issue #461): "When holding TAB in the keep, show a preview list of the
-- starting boons with their icons on the right pop-out panel."
--
-- Surface: IngamePlayerListUI (the keep/mission Tab-hold player list). Its right panel
-- (scenegraph parent "banner_right") already hosts the vanilla deed-reward icon strip
-- (reward_item passes) AND the CW node-info boon icon (terror_event_power_up_icon), so
-- THIS renderer is vanilla-proven to resolve Deus boon-icon textures on this exact panel
-- (ingame_player_list_ui_v2.lua / _definitions.lua). Data source is the mod's own
-- host-config -> available in the keep before any run exists.
--
-- Risk posture (untestable UI; PROJECT_STANDARDS 2.2b + "no-guessing" doctrine): we do
-- NOT append into vanilla's `_reward_widgets` (those draw in vanilla's UNguarded pass, so
-- a boon-icon atlas that is not resident in the keep could assert mid-loop and kill the
-- whole panel render). Instead we build our OWN widgets and draw them in our OWN
-- begin_pass/end_pass with each draw_widget individually pcall-wrapped -- worst case our
-- pass no-ops and the panel is byte-identical to vanilla. Icon and name are SEPARATE
-- widgets per row, so a boon whose icon texture will not resolve still shows its NAME
-- (fonts are always resident): graceful degradation, never a blank/crashing row.
--
-- Data: `mod._ct_collect_start_boons` mirrors the grant hook's enumeration
-- (DeusPowerUpsArray x start_boon_<name>) but resolves through `effective_setting`, so a
-- CLIENT previews the HOST's configured boons once the host-settings sync has landed
-- (falls back to the client's own toggles pre-sync -- see CHANGELOG limitation note).
-- ct's hooks on IngamePlayerListUI, all on DISTINCT methods (singleton-clean; ct had no
-- hook on this class before #461): `_setup_deed_reward_data` (fires on EVERY panel
-- activation -- set_active(true) calls it, ingame_player_list_ui_v2.lua:1224 -- so the
-- gate below re-evaluates per Tab press), `_draw` (the SHARED guarded draw pass -- also
-- draws the #533 deus collectible counters; NEVER add a second _draw hook), and
-- `_setup_mission_data` (#533 build point, below).
--
-- v0.7.258 follow-up fixes (user report on the 0.7.251 ship):
-- (1) "header but no rows": the first ship anchored rows on the "reward_item"
--     scenegraph node, which carries NO size and so inherits banner_right's full
--     660x1080 rect (ui_scenegraph.lua:109 `node_def.size or parent.size`). That node's
--     origin computes to world y = -750 (below the screen); vanilla only renders there
--     via pass-level vertical_alignment "top" inside the inherited rect
--     (create_reward_item icon style, _definitions.lua:1750, aligned by
--     UIUtils.align_box_inplace, helpers/ui_utils.lua:542-558). Our rows used
--     center/default alignment, so every row landed at negative screen y -- invisible --
--     while the header, anchored on the SIZED "reward_divider" node ({264,32}, world
--     y~348 at 1080p reference), rendered fine. Fix: anchor ALL rows on
--     "reward_divider" too and stack them below the header with per-row offsets
--     (2 columns x 9 rows, 28px pitch, "+N more" overflow) inside the band that is
--     empty in the gated context (no deed rewards, no collectibles in the keep).
-- (2) "shows all over the keep": the queue gate shipped in v0.7.258 was too
--     late. July 20 v0.7.305 logs prove the desired pre-queue context already
--     reports level=morris_hub, while the queue predicate remains false. The
--     preview now shares #505's exact native chamber-level predicate.
CT_BOON_PREVIEW_461_MARKER = "boon_preview_pilgrimage_context"
CT_BOON_TOOLTIP_1004_MARKER = "starting_boon_hover_description_v2"
mod._ct_boon_preview_tooltip = mod:dofile(
    "scripts/mods/chaos_wastes_tweaker_dev/_ct_boon_preview_tooltip")
mod:dofile("scripts/mods/chaos_wastes_tweaker_dev/_ct_boon_preview_runtime").install(mod)

mod:dofile("scripts/mods/chaos_wastes_tweaker_dev/_ct_boon_preview_helpers")({
    mod = mod,
})

-- Build point: vanilla calls _setup_deed_reward_data on EVERY panel activation
-- (set_active(true), ingame_player_list_ui_v2.lua:1224), so all gates below
-- re-evaluate per Tab press. Gates: keep UI, the local display toggle, and the
-- exact `morris_hub` Pilgrimage Chamber level shared with #505. Queue state is
-- diagnostic only: the requested preparation window begins before queueing.
-- Builds row widgets onto the instance. Tooltip layout is deferred until a
-- row's first hover, then cached; all one-time work is policy-bounded.
mod:hook_safe("IngamePlayerListUI", "_setup_deed_reward_data", function(self)
    self._ct_boon_preview_widgets = nil
    self._ct_boon_header_widget = nil
    local local_enabled = mod:get("preview_starting_boons") == true
    local level_key = mod._ct_pilgrimage_context
        and mod._ct_pilgrimage_context.current_level_key(Managers) or nil
    local in_chamber = mod._ct_in_pilgrimage_chamber
        and mod._ct_in_pilgrimage_chamber(level_key) or false
    local queued = mod._ct_preparing_cw_expedition()
    if not self._is_in_inn or not in_chamber or not local_enabled then
        pcall(printf,
            "[ct:461] boon preview suppressed context=%s level=%s keep_ui=%s local_enabled=%s host_effective_enabled=%s source=%s queued=%s",
            in_chamber and "pilgrimage_chamber" or "outside_pilgrimage_chamber",
            tostring(level_key), tostring(self._is_in_inn == true), tostring(local_enabled),
            tostring(mod._ct_effective_setting("preview_starting_boons") == true),
            tostring(mod._ct_effective_setting_source()), tostring(queued))
        return
    end
    local ok, err = pcall(function()
        local boons = mod._ct_collect_start_boons()
        if #boons == 0 then
            pcall(printf,
                "[ct:461] boon preview suppressed context=pilgrimage_chamber level=%s reason=no_configured_boons source=%s queued=%s",
                tostring(level_key), tostring(mod._ct_effective_setting_source()), tostring(queued))
            return
        end
        self._ct_boon_preview_widgets = mod._ct_build_boon_preview_widgets(boons)
        self._ct_boon_header_widget = mod._ct_build_boon_preview_header(
            string.format("%s (%d)", mod:localize("ct_boon_preview_header"), #boons))
        pcall(printf,
            "[ct:461] boon preview built context=pilgrimage_chamber level=%s boons=%d source=%s queued=%s",
            tostring(level_key), #boons, tostring(mod._ct_effective_setting_source()), tostring(queued))
    end)
    if not ok then
        self._ct_boon_preview_widgets = nil
        self._ct_boon_header_widget = nil
        pcall(printf, "[ct:461] boon-preview build failed (panel unaffected): %s", tostring(err))
    end
end)

-- #533 diagnostics follow-up: arm on native Tab-overlay activation and sample from
-- this existing singleton draw seam after vanilla has resolved final scenegraph bounds.
-- Kept in a side module to avoid growing this near-limit main chunk.
mod._ct_diag_tab_native533 = mod:dofile("scripts/mods/chaos_wastes_tweaker_dev/_ct_diag_tab_native533")
mod._ct_diag_tab_native533.install()

-- Draw point: our OWN begin_pass/end_pass layered on top of vanilla's, each draw_widget
-- pcall-guarded so a non-resident texture can never crash the panel render.
-- hook_safe = runs after vanilla's _draw closed its pass (ingame_player_list_ui_v2.lua:1755).
-- SINGLE ct hook on (IngamePlayerListUI, _draw) -- VMF silently drops a second
-- registration on the same pair. This one body draws BOTH ct overlays: the #461 keep
-- boon preview AND the #533 deus collectible counters. Each concern bails independently.
mod:hook_safe("IngamePlayerListUI", "_draw", function(self, dt)
    -- Automatic, bounded, log-only native CW census. This runs before the overlay
    -- early-return so diagnostics do not depend on either CT widget being present.
    pcall(mod._ct_diag_tab_native533.capture, self)
    local widgets = self._ct_boon_preview_widgets
    local has_boons = widgets and #widgets > 0
    local cw = self._ct_deus_collectibles
    -- #571 load-order fence: gut_dev can suppress setup before CT's wrapper runs.
    -- Recover CT's owner-specific rows once, from this consolidated draw seam.
    if not cw and type(mod._ct_ensure_deus_collectibles) == "function" then
        pcall(mod._ct_ensure_deus_collectibles, self, "draw_recovery"); cw = self._ct_deus_collectibles
    end
    if not has_boons and not cw then return end
    pcall(function()
        local r = self._ui_top_renderer
        local sg = self._ui_scenegraph
        local im = self._input_manager
        local input_service = im and im:get_service("player_list_input")
        local rs = self._render_settings
        if not (r and sg and input_service and rs) then return end
        -- Hotspot state from the preceding frame lets a hovered row build its
        -- tooltip before this frame's renderer pass. First hover therefore has
        -- at most a one-frame delay, and no allocation occurs inside the pass.
        if has_boons and self._cursor_active then
            for i = 1, #widgets do
                local widget = widgets[i]
                local hotspot = widget._ct_boon_hover_target
                    and widget.content and widget.content.hotspot
                if hotspot and hotspot.is_hover
                    and not widget._ct_boon_tooltip_attempted then
                    widget._ct_boon_tooltip_attempted = true
                    widget._ct_boon_tooltip_widget = mod._ct_build_boon_tooltip_widget(
                        widget._ct_boon_tooltip_data, r)
                end
            end
        end
        UIRenderer.begin_pass(r, sg, input_service, dt, nil, rs)
        if has_boons then
            local hdr = self._ct_boon_header_widget
            if hdr then pcall(UIRenderer.draw_widget, r, hdr) end
            local tooltip
            for i = 1, #widgets do
                local widget = widgets[i]
                pcall(UIRenderer.draw_widget, r, widget)
                local hotspot = widget._ct_boon_hover_target
                    and widget.content and widget.content.hotspot
                if self._cursor_active and hotspot and hotspot.is_hover then
                    tooltip = widget._ct_boon_tooltip_widget
                end
            end
            if tooltip then
                local wheel = input_service:get("scroll_axis")
                local gamepad_active = im:is_device_active("gamepad")
                local controller_pressed = gamepad_active
                    and input_service:get("right_press") == true
                local controller_down = gamepad_active
                    and input_service:get("right_hold") == true
                local delta, latched, controller_step =
                    mod._ct_boon_preview_tooltip.navigation_step(
                        wheel and wheel.y, controller_pressed, controller_down,
                        tooltip._ct_controller_page_latched)
                tooltip._ct_controller_page_latched = latched
                pcall(mod._ct_scroll_boon_tooltip, tooltip, delta, controller_step)
                pcall(mod._ct_update_boon_tooltip_hint, tooltip, gamepad_active)
                pcall(UIRenderer.draw_widget, r, tooltip)
            end
        end
        if cw then
            -- #533: refresh the counter values (vanilla _sync_missions cadence -- every
            -- active frame, write-on-change; ingame_player_list_ui_v2.lua:1128/:516-545),
            -- then draw vanilla's own Collectibles header + divider (vanilla skips them
            -- itself while _mission_count == 0 -- :1663-1665) and our two counter rows.
            pcall(mod._ct_layout_deus_collectibles, self)
            pcall(mod._ct_refresh_deus_collectibles, self)
            if self._collectibles_name then pcall(UIRenderer.draw_widget, r, self._collectibles_name) end
            if self._collectibles_divider then pcall(UIRenderer.draw_widget, r, self._collectibles_divider) end
            local rows = cw.rows
            for i = 1, #rows do
                pcall(UIRenderer.draw_widget, r, rows[i].widget)
            end
        end
        UIRenderer.end_pass(r)
    end)
end)

-- Textual preview + /verify surface for #461. Works even if the panel icons do not render,
-- and confirms the host-effective boon list the panel would show.
mod:command("ct_preview_boons", "List the starting boons this run will grant (host-effective) -- the #461 Tab-hold preview", function()
    local boons = mod._ct_collect_start_boons()
    if #boons == 0 then
        mod:echo("[ct] No starting boons configured. Enable some under Starting Boons in the ct menu.")
        return
    end
    mod:echo("%s", string.format("[ct] Starting Boons preview (%d) -- shown on the Tab panel in the Pilgrimage Chamber:", #boons))
    for i = 1, #boons do
        local b = boons[i]
        mod:echo("%s", string.format("  %d. %s [%s]%s", i, b.display or b.name, tostring(b.rarity),
            b.modded and " (modded -- wire-gated for non-ct peers)" or ""))
    end
    local level_key = mod._ct_pilgrimage_context
        and mod._ct_pilgrimage_context.current_level_key(Managers) or nil
    mod:echo("%s", mod._ct_in_pilgrimage_chamber and mod._ct_in_pilgrimage_chamber(level_key)
        and "[ct] Pilgrimage Chamber active: the Tab panel shows this list now."
        or string.format("[ct] Outside the Pilgrimage Chamber (level=%s): enter it through the Chaos Wastes keep door to show this list.", tostring(level_key)))
end)

-- #461 regression: the marker + both build helpers + the display toggle stay wired, so a
-- future refactor can't silently drop the Tab-hold boon preview.
_rt_register("issue461_boon_preview_wired", function()
    if CT_BOON_PREVIEW_461_MARKER ~= "boon_preview_pilgrimage_context" then
        return "#461 REGRESSION: CT_BOON_PREVIEW_461_MARKER missing/mismatch; got " .. tostring(CT_BOON_PREVIEW_461_MARKER)
    end
    if type(mod._ct_collect_start_boons) ~= "function" then
        return "#461 REGRESSION: mod._ct_collect_start_boons missing"
    end
    if type(mod._ct_build_boon_preview_widgets) ~= "function" then
        return "#461 REGRESSION: mod._ct_build_boon_preview_widgets missing"
    end
    if type(mod._ct_collect_start_boons()) ~= "table" then
        return "#461 REGRESSION: _ct_collect_start_boons must return a table"
    end
    if type(mod:get("preview_starting_boons")) ~= "boolean" then
        return "#461 REGRESSION: preview_starting_boons checkbox not registered (mod:get non-boolean)"
    end
    -- #461 chamber follow-up: use the same exact level-key boundary as #505.
    -- The queue probe remains diagnostic, never a display gate.
    if type(mod._ct_in_pilgrimage_chamber) ~= "function" then
        return "#461 REGRESSION: shared Pilgrimage Chamber gate missing"
    end
    if not mod._ct_in_pilgrimage_chamber("morris_hub")
        or mod._ct_in_pilgrimage_chamber("inn_level")
        or mod._ct_in_pilgrimage_chamber("dlc_morris_map") then
        return "#461 REGRESSION: preview chamber gate must accept only morris_hub"
    end
    local sample = mod._ct_build_boon_preview_widgets({ { name = "rt_probe", display = "rt probe", icon = nil } })
    if type(sample) ~= "table" or #sample == 0 then
        return "#461 REGRESSION: _ct_build_boon_preview_widgets built no widgets for a 1-boon list"
    end
    for i = 1, #sample do
        if sample[i].scenegraph_id == "reward_item" then
            return "#461 REGRESSION: preview widget anchored on sizeless reward_item node (off-screen bug class)"
        end
    end
end)

_rt_register("issue1004_boon_hover_tooltip_wired", function()
    if CT_BOON_TOOLTIP_1004_MARKER ~= "starting_boon_hover_description_v2" then
        return "#1004 REGRESSION: hover-tooltip marker missing/mismatch"
    end
    local policy = mod._ct_boon_preview_tooltip
    if type(policy) ~= "table" or type(policy.resolve_description) ~= "function"
        or type(policy.layout_description) ~= "function"
        or type(policy.navigation_step) ~= "function"
        or type(policy.production_geometry) ~= "function" then
        return "#1004 REGRESSION: tooltip policy incomplete"
    end
    if type(mod._ct_start_boon_description) ~= "function"
        or type(mod._ct_build_boon_tooltip_widget) ~= "function"
        or type(mod._ct_scroll_boon_tooltip) ~= "function"
        or type(mod._ct_update_boon_tooltip_hint) ~= "function" then
        return "#1004 REGRESSION: tooltip runtime helpers missing"
    end
    if type(policy.LIMITS) ~= "table"
        or policy.LIMITS.max_description_bytes ~= 16384
        or policy.LIMITS.max_pages ~= 16
        or policy.LIMITS.max_measure_calls ~= 256 then
        return "#1004 REGRESSION: tooltip allocation limits missing/mismatch"
    end
    local layout = policy.layout_description("Runtime description",
        function() return 20 end)
    if type(layout) ~= "table" or layout.measured_description_height ~= 20 then
        return "#1004 REGRESSION: measured tooltip layout failed"
    end
end)

-- #556 regression: lock both halves of the talent-specific contract. The pure
-- duplicate policy must reject only an already-present talent, while the live
-- identity resolver must use the current career's native name/icon when one is
-- available in the keep.
_rt_register("issue556_starting_talent_identity", function()
    if type(mod._ct_starting_talent_is_duplicate) ~= "function" then
        return "#556 REGRESSION: duplicate-selected-talent policy missing"
    end
    if not mod._ct_starting_talent_is_duplicate(
        { talent = true }, "talent_2_2", { talent_2_2 = true }) then
        return "#556 REGRESSION: selected talent_2_2 would be appended twice"
    end
    if mod._ct_starting_talent_is_duplicate(
        { talent = true }, "talent_2_2", { talent_2_1 = true }) then
        return "#556 REGRESSION: a different talent was incorrectly suppressed"
    end
    if mod._ct_starting_talent_is_duplicate(
        { talent = false }, "attack_speed", { attack_speed = true }) then
        return "#556 REGRESSION: non-talent starting-boon behavior changed"
    end
    if type(mod._ct_start_boon_identity) ~= "function" then
        return "#556 REGRESSION: career-specific preview identity resolver missing"
    end

    local manager = Managers and Managers.player
    local player = manager and manager:local_player()
    if not player then return "skip: local player unavailable for talent identity" end
    local ok, profile_index, career_index = pcall(function()
        return player:profile_index(), player:career_index()
    end)
    if not ok then return "skip: local profile/career unavailable" end
    local rarity
    for _, entry in ipairs(rawget(_G, "DeusPowerUpsArray") or {}) do
        if entry.name == "talent_2_2" then rarity = entry.rarity break end
    end
    if not rarity then return "#556 REGRESSION: vanilla talent_2_2 power-up absent" end
    local display, icon = mod._ct_start_boon_identity(
        "talent_2_2", rarity, profile_index, career_index)
    if type(display) ~= "string" or display == "" or display == "talent_2_2" then
        return "#556 REGRESSION: talent preview retained generic identity " .. tostring(display)
    end
    if type(icon) ~= "string" or icon == "" then
        return "#556 REGRESSION: talent preview did not resolve a career icon"
    end
end)

-- ============================================================
-- CW Collectibles on the Tab-hold panel (#533)
-- ============================================================
-- BUG (#533): with Adventure-missions-in-CW enabled, an injected Adventure level's
-- Tab-hold right panel showed the ADVENTURE collectible counters (tomes / grimoires /
-- loot dice). Root cause: LevelSettings post-processing defaults `loot_objectives =
-- { grimoire = 2, tome = 3, ... }` onto every `mechanism == "adventure"` level
-- (level_settings.lua:1889-1896), and IngamePlayerListUI._setup_mission_data builds
-- the counter widgets purely from the CURRENT level's loot_objectives
-- (ingame_player_list_ui_v2.lua:436-441) -- it never consults the RUN mechanism.
-- Vanilla CW (deus) levels carry no loot_objectives, so vanilla builds no counters
-- there; an injected adventure level running under the deus mechanism inherits the
-- adventure default and builds counters for pickups that DO NOT EXIST on it (ct
-- converts tome/grim spawners to Chests of Trials and pedestals to Pilgrim's Coins).
--
-- FIX: full wrapper on _setup_mission_data (sole ct hook on that method; dup-check
-- 2026-07-13 -- the #461 hooks are on _setup_deed_reward_data/_draw). Outside a deus
-- run (stock Adventure, keep, hubs) -> passthrough, byte-identical vanilla. Inside a
-- deus run -> skip vanilla's build (no tome/grim/dice widgets; _mission_count stays 0
-- so vanilla's own Collectibles header stays off) and build the DEUS counters instead:
-- Chests of Trials + Pilgrim's Coins. Gate = "the mechanism exposes a live
-- deus_run_controller", the same every-peer-correct idiom as on_injected_adventure_level
-- (this file) -- NEVER IS_INJECTED_ADVENTURE_LEVEL, which is EMPTY on a client until
-- the ct graph snapshot lands, and pointless anyway: the counters are equally right on
-- vanilla CW levels, so ALL deus missions get them (consistent across the run).
--
-- DATA (peer-correct on host AND client -- both read the replicated deus-run
-- SharedState): Chests of Trials = get_cursed_chests_purified(own_peer)
-- (deus_run_controller.lua:2070; server-incremented for EVERY peer on chest completion
-- :767-777, replicated via SharedState, deus_run_state.lua:20/:236-244). Pilgrim's
-- Coins = get_player_soft_currency(own_peer) (deus_run_controller.lua:925-927 -- the
-- EXACT getter the vanilla HUD coin indicator polls on every peer,
-- deus_soft_currency_indicator_ui.lua:51-68), floored like that HUD (:78).
--
-- WIDGETS: a copy of vanilla's create_loot_widget
-- (ingame_player_list_ui_v2_definitions.lua:843-1041 -- a file-local we cannot reach)
-- minus its glow pass (deus_icons_coin/_boon have no `*_glow` atlas sibling), anchored
-- on the vanilla "loot_objective" scenegraph node with vanilla's own row math. Icons
-- are gui_icons_atlas entries (deus_icons_coin :11946, deus_icons_boon :10532) -- the
-- same atlas family this exact panel already resolves for node-info boon/curse icons.
-- Risk posture (untestable UI, same as #461): build is pcall-bracketed with a vanilla
-- fallback, drawing rides the existing guarded _draw pass -- worst case the block
-- no-ops and the panel renders pure vanilla.
CT_CW_TAB_COLLECTIBLES_533_MARKER = "cw_tab_collectibles_deus_counters_v0.7.257"
do
    -- Live deus run controller or nil (stock Adventure / keep -> nil). Correct on every
    -- peer: only the deus mechanism exposes get_deus_run_controller.
    local function deus_run_controller_or_nil()
        local mm = Managers.mechanism
        local mech = mm and mm.game_mechanism and mm:game_mechanism()
        return (mech and mech.get_deus_run_controller and mech:get_deus_run_controller()) or nil
    end

    -- The two deus counter rows (order = display order, top to bottom).
    local ROWS = {
        { key = "chests", icon = "deus_icons_boon", label_key = "ct_tab_chests_of_trials" },
        { key = "coins",  icon = "deus_icons_coin", label_key = "ct_tab_pilgrims_coins" },
    }
    -- Native-sized; #571 reuses vanilla's widget-local two-per-row offset loop.
    local ICON_SIZE = 80

    -- Verbatim copy of vanilla create_loot_widget (definitions:843-1041) MINUS the
    -- glow_icon pass/style: `texture .. "_glow"` does not exist for the deus icons and
    -- a missing atlas texture would kill the draw. Everything else (amount-gated lit
    -- icon over a black silhouette, title bottom-right of the icon, counter above it)
    -- is vanilla's own layout so the pane matches the adventure counters it replaces.
    local function create_deus_loot_widget(texture, text, scale)
        local texture_settings = UIAtlasHelper.get_atlas_settings_by_texture_name(texture)
        local texture_size = texture_settings.size
        scale = scale or 1
        return {
            scenegraph_id = "loot_objective",
            element = {
                passes = {
                    { pass_type = "text", style_id = "text", text_id = "text" },
                    { pass_type = "text", style_id = "text_shadow", text_id = "text" },
                    {
                        pass_type = "text", style_id = "counter_text", text_id = "counter_text",
                        content_check_function = function(content) return content.amount > 0 end,
                    },
                    {
                        pass_type = "text", style_id = "counter_text_disabled", text_id = "counter_text",
                        content_check_function = function(content) return content.amount == 0 end,
                    },
                    { pass_type = "text", style_id = "counter_text_shadow", text_id = "counter_text" },
                    {
                        pass_type = "texture", style_id = "icon", texture_id = "icon",
                        content_check_function = function(content) return content.amount > 0 end,
                    },
                    { pass_type = "texture", style_id = "background_icon", texture_id = "icon" },
                },
            },
            content = {
                amount = 0,
                counter_text = "x0",
                text = text or "n/a",
                icon = texture,
            },
            style = {
                text = {
                    font_size = 32, font_type = "hell_shark_header",
                    horizontal_alignment = "left", vertical_alignment = "bottom",
                    text_color = Colors.get_table("font_title"),
                    offset = { scale * texture_size[1], scale * texture_size[2] - 50, 1 },
                },
                text_shadow = {
                    font_size = 32, font_type = "hell_shark_header",
                    horizontal_alignment = "left", vertical_alignment = "bottom",
                    text_color = Colors.get_table("black"),
                    offset = { scale * texture_size[1] + 1, scale * texture_size[2] - 50 - 1, 0 },
                },
                counter_text = {
                    font_size = 32, font_type = "hell_shark_header",
                    horizontal_alignment = "left", vertical_alignment = "top",
                    text_color = Colors.get_table("font_default"),
                    offset = { scale * texture_size[1], -40, 1 },
                },
                counter_text_disabled = {
                    font_size = 32, font_type = "hell_shark_header",
                    horizontal_alignment = "left", vertical_alignment = "top",
                    text_color = { 255, 130, 130, 130 },
                    offset = { scale * texture_size[1], -40, 1 },
                },
                counter_text_shadow = {
                    font_size = 32, font_type = "hell_shark_header",
                    horizontal_alignment = "left", vertical_alignment = "top",
                    text_color = Colors.get_table("black"),
                    offset = { scale * texture_size[1] + 1, -41, 0 },
                },
                icon = {
                    horizontal_alignment = "left", vertical_alignment = "top",
                    color = { 255, 255, 255, 255 },
                    offset = { 0, 0, 1 },
                    texture_size = { scale * texture_size[1], scale * texture_size[2] },
                },
                background_icon = {
                    horizontal_alignment = "left", vertical_alignment = "top",
                    color = { 255, 0, 0, 0 },
                    offset = { 0, 0, 0 },
                    texture_size = { scale * texture_size[1], scale * texture_size[2] },
                },
            },
            offset = { 0, 0, 0 },
        }
    end

    -- Own-peer chest/coin values, or nil outside a deus run. Exposed on mod for the
    -- regression check and any future /verify surface.
    function mod._ct_read_deus_collectible_values()
        local dc = deus_run_controller_or_nil()
        if not dc then return nil end
        local peer = dc.get_own_peer_id and dc:get_own_peer_id()
        if not peer then return nil end
        local chests = (dc.get_cursed_chests_purified and dc:get_cursed_chests_purified(peer)) or 0
        local coins = (dc.get_player_soft_currency and dc:get_player_soft_currency(peer)) or 0
        return {
            chests = math.floor((tonumber(chests) or 0) + 0.5),
            coins = math.floor(tonumber(coins) or 0),  -- HUD indicator floors too (:78)
        }
    end

    -- Build once; live placement happens after the scenegraph resolves below.
    function mod._ct_build_deus_collectibles()
        local rows = {}
        for i, spec in ipairs(ROWS) do
            local title = mod:localize(spec.label_key)
            local widget = UIWidget.init(create_deus_loot_widget(spec.icon, title, 1))
            rows[#rows + 1] = { key = spec.key, title = title, widget = widget, last = nil }
        end
        return { rows = rows, layout_signature = nil }
    end

    -- Per-frame value refresh while the panel draws (called from the shared _draw hook
    -- above). Mirrors vanilla _sync_missions: only rewrite content when the value
    -- changed (ingame_player_list_ui_v2.lua:530-543).
    function mod._ct_refresh_deus_collectibles(self)
        local cw = self._ct_deus_collectibles
        if not cw then return end
        local values = mod._ct_read_deus_collectible_values()
        if not values then return end
        for _, row in ipairs(cw.rows) do
            local v = values[row.key] or 0
            if v ~= row.last then
                row.last = v
                local content = row.widget.content
                content.amount = v
                content.counter_text = "x" .. tostring(v)
            end
        end
    end
    -- Build point + adventure-counter suppression. FULL wrapper (not hook_safe): under
    -- the deus mechanism vanilla must NOT run -- it would build tome/grim/dice counters
    -- from the injected level's defaulted loot_objectives. Keep/hubs stay vanilla.
    mod:hook("IngamePlayerListUI", "_setup_mission_data", function(func, self, level_settings)
        self._ct_deus_collectibles = nil
        self._ct_deus_collectibles_build_failed = nil
        if self._is_in_inn or (level_settings and level_settings.hub_level)
            or not deus_run_controller_or_nil() then
            return func(self, level_settings)
        end
        if not mod._ct_ensure_deus_collectibles(self, "setup_mission_data") then
            return func(self, level_settings)
        end
        -- Deliberately NOT calling func: on a deus-run level the vanilla build is either
        -- a no-op (vanilla CW level, no loot_objectives) or wrong (injected adventure
        -- level, defaulted adventure loot_objectives).
    end)
end

local _ct_tab_layout_571 = mod:dofile("scripts/mods/chaos_wastes_tweaker_dev/_ct_tab_collectibles_layout")

-- #533 regression: marker + all three helpers stay wired, and the value reader honors
-- its outside-a-deus-run nil contract (in the keep it MUST be nil; mid-run a table).
_rt_register("issue533_cw_tab_collectibles_wired", function()
    if CT_CW_TAB_COLLECTIBLES_533_MARKER ~= "cw_tab_collectibles_deus_counters_v0.7.257" then
        return "#533 REGRESSION: CT_CW_TAB_COLLECTIBLES_533_MARKER missing/mismatch; got " .. tostring(CT_CW_TAB_COLLECTIBLES_533_MARKER)
    end
    if type(mod._ct_build_deus_collectibles) ~= "function" then
        return "#533 REGRESSION: mod._ct_build_deus_collectibles missing"
    end
    if type(mod._ct_refresh_deus_collectibles) ~= "function" then
        return "#533 REGRESSION: mod._ct_refresh_deus_collectibles missing"
    end
    if type(mod._ct_read_deus_collectible_values) ~= "function" then
        return "#533 REGRESSION: mod._ct_read_deus_collectible_values missing"
    end
    local v = mod._ct_read_deus_collectible_values()
    if v ~= nil and (type(v) ~= "table" or type(v.chests) ~= "number" or type(v.coins) ~= "number") then
        return "#533 REGRESSION: value reader contract broken (expected nil outside a deus run or {chests=n, coins=n} inside one)"
    end
end)

_rt_register("issue533_native_tab_diagnostics_armed", mod._ct_diag_tab_native533.regression)

_rt_register("issue571_cw_tab_collectibles_safe_reflow", _ct_tab_layout_571.regression)
