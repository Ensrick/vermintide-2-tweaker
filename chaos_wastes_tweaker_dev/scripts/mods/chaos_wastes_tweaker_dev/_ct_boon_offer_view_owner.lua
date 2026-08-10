--[[
_ct_boon_offer_view_owner - layout of the two Deus boon-offer views
(#1159 / #2 file-size refactor).

RESPONSIBILITY
Owns everything ct does to WHERE the offered-boon widgets sit in the two views
that offer boons, and to the input that moves them. Those two views are the
shrine (engine class DeusShopView, up to 4 offers on a vertical arc) and the
Chest of Trials (DeusCursedChestView, up to 3). Both lay their offer widgets out
once at build time and never scroll, so both break the same way when ct raises
the offer caps - and both are repaired here, by the same code:
  * the degenerate-arc repair: vanilla computes each widget's arc offset from
    `cos(angle) * radius` with `angle = 0/0` when the view builds exactly ONE
    widget, so the lone offer renders at a NaN screen position and is invisible.
    fix_arc_nan detects NaN via `x ~= x` and centres the widget instead.
  * the two build hooks themselves - the single permitted registration on
    DeusShopView._create_ui_elements and on DeusCursedChestView.create_ui_elements
  * the whole _ct_boon_scroll block (#115 / #114): when the configured offer count
    exceeds what the arc fits, it flattens the arc into a row-snapped vertical
    list, parks off-window rows at y = -20000 where no hotspot can reach them,
    injects a hand-authored track+thumb scrollbar into the view's own _widgets
    array, and drives wheel / drag / track-page input from a per-frame pass
  * the two wrapping `update` hooks that run that per-frame pass BEFORE vanilla
    draws, so the reflow and the input land in the same frame

Extracted from chaos_wastes_tweaker_dev.lua entry lines 2711-3104 with no
behaviour change. ONE contiguous chunk moved and it is byte-identical to the
pre-extraction entry region (MD5-proven, zero edits inside it); the only
additions are this header, the ctx binding block below, and the closing `end` /
`return install`. mod:dofile is not a singleton, so the entry calls this
installer EXACTLY once.

ZERO LOAD-ORDER DEVIATION
The installer sits at the exact line the moved region occupied - immediately
after the DeusPowerUpUtils.generate_random_power_ups hook and immediately before
the MutatorHandler._activate_mutator hook - so every hook in the mod still
registers in its original relative order. Nothing was reordered, split, or
skipped, which is why this file needs no ordering-deviation argument at all.

HOOKS OWNED (each hooked EXACTLY ONCE in the whole mod - VMF silently drops a
second registration on the same (Class, method) pair)
  DeusShopView._create_ui_elements          [hook_safe]
  DeusCursedChestView.create_ui_elements    [hook_safe]
  DeusShopView.update                       [hook]
  DeusCursedChestView.update                [hook]
No RPC, no command, no _rt_register moved with this slice. The mod-wide census
is unchanged by the move (97 hook / 29 hook_safe / 7 network_register /
44 command sites), verified before and after by two independent methods.

THE TWO PASSENGERS IN THE SHOP BUILD BODY, AND WHY THEY ARE NOT A LEAK
VMF allows one registration per (Class, method) pair, so the single
_create_ui_elements body is also where #458 and the boon-pricing runtime get
their build-time callback. Both stay one-line dispatches:
    mod._ct_start_shrine_runtime.decorate_shop(self)
    mod._ct_boon_pricing_runtime.enforce_shop(self)
This file owns the hook SITE, never the price policy - it cannot tell you what a
boon costs. Both fields are resolved off `mod` at CALL time behind a nil guard,
and both modules are dofile'd LATER in the entry than this installer, so the
guard is load-order-correct exactly as it was before the move.

COMPOSES WITH, DOES NOT OVERLAP, THE OTHER ct OWNERS
Every neighbour touches a DIFFERENT (Class, method) pair on the same two view
classes, which is what keeps four owners on two views collision-free:
  * _ct_start_shrine_runtime owns DeusShopView._get_power_up_costs,
    _update_shop_widgets and start - affordability, per-offer enable/disable and
    the #458 synthetic start shrine. Prices and purchase gating, not geometry.
  * _ct_boon_grant_owner owns DeusShopView._init_power_up_widget and
    _on_power_up_bought - the #467 price text on a card and the purchase
    telemetry. It decorates ONE card; this file decides where cards sit.
  * the entry still owns DeusCursedChestView._on_button_pressed - #211
    grant-source tagging around the pick. It is a grant-provenance concern with
    no layout in it, and it must stay next to the other grant-source wrappers.
  * _ct_boon_preview_tooltip / _ct_boon_preview_runtime own what a hovered offer
    SAYS. Nothing here may grow a tooltip, and nothing there may move a widget.
  * WHICH boons are offered is DeusPowerUpUtils.generate_random_power_ups, still
    in the entry directly above the install site. Offer CONTENT and offer LAYOUT
    are deliberately separate: this file must keep working no matter what the
    pool produces, and is written to (it only ever reads `#boon_widgets`).

CROSS-FILE CONTRACT
Entry file-locals the moved chunk closed over, and how each crosses:
  ctx.dbg  entry :99, the pcall-guarded `local function _dbg` (#427: mod:warning
           posts to CHAT under VMF defaults, so diagnostics go through debug /
           printf instead). Exactly ONE call site moved with the chunk - the
           v0.7.67 blessing-offering dump in the shop build body. `_dbg` is a
           `local function` that is never reassigned, so a by-value bind would
           also be correct today; it crosses as a late-binding wrapper anyway so
           the binding survives the install site moving, matching
           _ct_altar_reuse_owner (#1236) and _ct_chest_revive_owner (#1237). The
           assert below turns a dropped key into a load-time failure instead of
           a nil call the first time a shrine opens.
`mod` is the installer's first parameter, exactly as the other ct owners take it.
`fix_arc_nan` - the only main-chunk local the moved region declared - had ZERO
references anywhere outside those lines (real-parser proven), so it becomes an
install-scope local with identical closure semantics and crosses nothing.
Everything else the chunk reads is an engine global reachable from any chunk:
UIWidget, UISceneGraph, UIInverseScaleVectorToResolution, Mouse, math.

EXPORTS: none. The single seam is `mod._ct_boon_scroll_setup`, assigned by the
moved code and consumed by the two build hooks that moved with it, so the whole
call graph now lives inside this file. It stays a `mod` field rather than
becoming an install-time return because _ct_regression.lua's
`boon_offer_scrollbar_wired` check asserts its presence off `mod` at CALL time -
that check is this slice's live boundary assertion and is deliberately left
where it is.

Owned by: chaos_wastes_tweaker_dev.lua entry point.
Guarded by: qa/lua/tests/test_ct_boon_offer_view_owner.lua,
qa/lua/tests/test_ct_entry_decomposition.lua, the #115 / #114 rows in
qa/rt_textual_invariants.psd1, and the DeusShopView / DeusCursedChestView rows in
chaos_wastes_tweaker_dev/ENGINE_SURFACE.md.
]]

local function install(mod, ctx)

assert(type(ctx) == "table", "_ct_boon_offer_view_owner requires a context table")
assert(type(ctx.dbg) == "function",
    "_ct_boon_offer_view_owner requires ctx.dbg (late-binding wrapper, not the entry local by value)")

-- The moved chunk below calls `_dbg(...)` unqualified, exactly as it did in the
-- entry. Binding the ctx wrapper to that same name is what lets the chunk stay
-- byte-identical across the move.
local _dbg = ctx.dbg

-- CLARIFY: Workaround for a vanilla VT2 layout bug. When a shrine/cursed-chest only spawns ONE
-- widget on the arc, vanilla code computes the offset via `cos(angle) * radius` where `angle = 0/0`
-- (NaN from division-by-zero in degenerate single-element arc). The widget then renders at NaN
-- screen position and is invisible. Replacing NaN with 0 centers the single widget. NaN is detected
-- via `x ~= x` (the only value that isn't equal to itself in IEEE 754).
-- QUESTION: Why only fix the 1-widget case? If the issue can also occur for 0 or N>1 widgets, this
-- silently fails to repair them. May be intentional — maybe FatShark's layout only divides by zero
-- when count == 1.
local function fix_arc_nan(widgets)
    if not widgets or #widgets ~= 1 then
        return
    end

    local widget = widgets[1]
    if widget and widget.offset then
        if widget.offset[1] ~= widget.offset[1] then
            widget.offset[1] = 0
        end
        if widget.offset[2] ~= widget.offset[2] then
            widget.offset[2] = 0
        end
    end
end

mod:hook_safe("DeusShopView", "_create_ui_elements", function(self, shop_settings, power_ups, blessings)
    fix_arc_nan(self._shop_item_widgets)
    -- #458: the synthetic start shrine owns a local price policy. The runtime
    -- module uses the same price helper for this display and the charged value.
    if mod._ct_start_shrine_runtime then
        mod._ct_start_shrine_runtime.decorate_shop(self)
    end
    if mod._ct_boon_pricing_runtime then
        mod._ct_boon_pricing_runtime.enforce_shop(self)
    end
    -- v0.7.67 diagnostic: log the blessings the shop is offering this visit. The
    -- 2026-05-20 session had blessing_of_power available at shop_strife but the
    -- user reported it "wasn't purchaseable" with zero buy attempts in logs. This
    -- captures whether the blessing was even in the offering pool, plus the buyer
    -- state at shop-open so we can tell from logs alone whether the button was
    -- already greyed out when the shop opened.
    if type(blessings) == "table" then
        local names = {}
        for i = 1, #blessings do names[i] = tostring(blessings[i]) end
        local with_buyer = self._deus_run_controller and self._deus_run_controller:get_blessings_with_buyer() or {}
        local buyer_dump = {}
        for k, v in pairs(with_buyer) do buyer_dump[#buyer_dump + 1] = tostring(k) .. "=" .. tostring(v) end
        _dbg("[miracle] DeusShopView opened type=%s blessings=[%s] already_bought={%s}",
            tostring(self._shop_type), table.concat(names, ","), table.concat(buyer_dump, ","))
    end

    -- v0.7.199-dev: boon-offer scrollbar setup, merged into this body because
    -- (DeusShopView, _create_ui_elements) is already hooked here (VMF dup-hook
    -- rule: one hook per (Class, method) pair). Implementation lives in the
    -- _ct_boon_scroll block below. Only the OFFERED boon widgets scroll;
    -- blessings and the owned-boons side panel are untouched.
    if mod._ct_boon_scroll_setup then
        local boon_widgets = {}
        local offers = self._shop_items and self._shop_items.power_ups
        if type(offers) == "table" then
            for i = 1, #offers do
                local entry = offers[i]
                if entry and entry.widget then
                    boon_widgets[#boon_widgets + 1] = entry.widget
                end
            end
        end
        mod._ct_boon_scroll_setup(self, boon_widgets, 4)
    end
end)

mod:hook_safe("DeusCursedChestView", "create_ui_elements", function(self)
    fix_arc_nan(self._power_up_widgets)

    -- v0.7.199-dev: boon-offer scrollbar setup, merged into this body because
    -- (DeusCursedChestView, create_ui_elements) is already hooked here (VMF
    -- dup-hook rule). Implementation in the _ct_boon_scroll block below.
    -- _power_up_widgets holds ONLY the offered boons in this view (no
    -- blessings exist here).
    if mod._ct_boon_scroll_setup then
        mod._ct_boon_scroll_setup(self, self._power_up_widgets, 3)
    end
end)

-- ============================================================================
-- _ct_boon_scroll -- scrollbar for the shrine / cursed-chest boon offerings
-- (v0.7.199-dev)
--
-- The shrine (DeusShopView) and cursed chest (DeusCursedChestView) lay their
-- offered-boon widgets on a fixed vertical arc with no scrolling, so raising
-- the offered-boon caps (shrine_boon_count / chest_boon_count, now 1..50 in
-- the data file) would strand most rows off-screen and unselectable. When the
-- offer count exceeds what fits (shop: 4 rows, chest: 3 rows), this block:
--   1. flattens the arc into a row-snapped vertical list (row height 194 =
--      power_up_root.size[2] in both defs files), showing `visible` rows
--      centered on the power_up_root scenegraph node;
--   2. parks off-window rows at offset y = -20000, far off-screen, which makes
--      their hotspots unreachable by the cursor -- vanilla's own input loops
--      (_handle_input / hold-to-purchase) then naturally skip them, and we
--      never touch content.button_hotspot.disable_button (vanilla update owns
--      that field);
--   3. draws a hand-authored track+thumb scrollbar (plain rect passes +
--      hotspot passes) to the right of the boon column, injected into the
--      view's self._widgets so the vanilla draw loop renders it (verified:
--      deus_shop_view_v2._draw and deus_cursed_chest_view.draw both iterate
--      self._widgets).
-- Interactions: mouse wheel = 1 row per notch; click on the track above /
-- below the thumb = page a full window; hold + drag the thumb = jump to any
-- row (cursor y mapped through the track, row-snapped).
-- At or below the vanilla row counts this block does nothing at all -- the
-- vanilla arc (plus fix_arc_nan above) stays byte-identical.
--
-- Consolidation note: setup is invoked from the two existing hook_safe bodies
-- ABOVE (VMF dup-hook rule -- do NOT add another hook on _create_ui_elements /
-- create_ui_elements). The two `update` hooks at the bottom of this block are
-- the only hooks registered here; grep-verified 2026-07-01 that no other
-- ct_dev hook targets either view's `update`.
-- Wrapped in do..end so no new chunk-level locals land in the main chunk
-- (Lua 5.1's 200-local limit); the only export is mod._ct_boon_scroll_setup.
-- ============================================================================
do
    local ROW_H = 194                -- one boon row == power_up_root height (both views)
    local NODE_CENTER_Y = ROW_H / 2  -- rows are centered on power_up_root's vertical center
    -- Scrollbar geometry, relative to power_up_root's bottom-left corner. The
    -- boon column spans x 0..484 on that node (widget style offsets run 0..484
    -- in create_power_up_shop_item), so the track sits just right of it.
    -- First-guess cosmetics -- tune in-game if it overlaps or floats.
    local TRACK_X = 500
    local TRACK_W = 12
    local THUMB_W = 8
    local HIDDEN_Y = -20000

    -- Track (dim) + thumb (brass) rects, one hotspot each, all anchored to
    -- power_up_root. Colors are {A,R,G,B}. NOTE: rect passes position purely
    -- via style.offset added to the node's bottom-left world position --
    -- UIRenderer.draw_widget ignores horizontal/vertical_alignment for rect
    -- passes (alignment only applies to passes that call align_box_inplace,
    -- e.g. texture with texture_size), so explicit offsets are used here.
    -- The thumb's style.offset[2] is rewritten every frame by _reposition.
    local function _build_scrollbar_definition(track_h, thumb_h)
        local track_bottom = NODE_CENTER_Y - track_h / 2
        return {
            scenegraph_id = "power_up_root",
            offset = { 0, 0, 0 },
            element = {
                passes = {
                    { pass_type = "rect", style_id = "track" },
                    { pass_type = "rect", style_id = "thumb" },
                    { pass_type = "hotspot", style_id = "track", content_id = "track_hotspot" },
                    { pass_type = "hotspot", style_id = "thumb", content_id = "thumb_hotspot" },
                },
            },
            content = {
                track_hotspot = {},
                thumb_hotspot = {},
            },
            style = {
                track = {
                    size = { TRACK_W, track_h },
                    offset = { TRACK_X, track_bottom, 8 },
                    color = { 160, 15, 12, 10 },
                },
                thumb = {
                    size = { THUMB_W, thumb_h },
                    offset = { TRACK_X + (TRACK_W - THUMB_W) / 2, track_bottom + track_h - thumb_h, 9 },
                    color = { 255, 170, 145, 100 },
                },
            },
        }
    end

    -- Row-snapped reflow: rows [top .. top+visible-1] stack vertically centered
    -- on the node (slot 0 on top); everything else parks off-screen. The
    -- center_offset math reproduces vanilla's own row spacing exactly (vanilla
    -- count==visible offsets are 291/97/-97/-291 for 4 rows, 194/0/-194 for 3),
    -- so an engaged view's visible rows sit where vanilla would have put them.
    local function _reposition(st)
        local widgets = st.widgets
        local top = st.top
        local visible = st.visible
        local center_offset = (visible - 1) / 2 * ROW_H

        for i = 1, st.count do
            local widget = widgets[i]

            if widget and widget.offset then
                if top <= i and i <= top + visible - 1 then
                    local slot = i - top -- 0-based row within the visible window
                    widget.offset[1] = 0 -- flatten the arc's sin() x-sway
                    widget.offset[2] = center_offset - slot * ROW_H
                else
                    widget.offset[1] = 0
                    widget.offset[2] = HIDDEN_Y
                end
            end
        end

        local sw = st.scrollbar_widget

        if sw and sw.style and sw.style.thumb then
            local frac = st.max_top > 1 and (top - 1) / (st.max_top - 1) or 0
            local track_top = NODE_CENTER_Y + st.track_h / 2

            sw.style.thumb.offset[2] = track_top - frac * (st.track_h - st.thumb_h) - st.thumb_h
        end
    end

    local function _setup(view, boon_widgets, visible)
        view._ct_boon_scroll = nil -- fresh per create_ui_elements pass

        if type(boon_widgets) ~= "table" then
            return
        end

        local count = #boon_widgets

        if count <= visible then
            return -- fits the vanilla arc; stay 100% vanilla (fix_arc_nan already ran)
        end

        local widgets = view._widgets

        if type(widgets) ~= "table" then
            -- Future-patch shape change: degrade to "no scroll" rather than crash.
            mod:warning("[ct:boon_scroll] view has no _widgets array; scrollbar not injected, scroll disabled")
            return
        end

        local track_h = visible * ROW_H
        local thumb_h = math.max(24, visible / count * track_h)
        local scrollbar_widget = UIWidget.init(_build_scrollbar_definition(track_h, thumb_h))

        widgets[#widgets + 1] = scrollbar_widget
        view._ct_boon_scroll = {
            widgets = boon_widgets,
            count = count,
            visible = visible,
            row_h = ROW_H,
            top = 1,
            max_top = count - visible + 1,
            track_h = track_h,
            thumb_h = thumb_h,
            scrollbar_widget = scrollbar_widget,
        }

        _reposition(view._ct_boon_scroll)
        -- Apply-site log (PROJECT_STANDARDS 5.1a): fires once per view open.
        mod:info("[ct:boon_scroll] engaged: %d boons offered, %d visible rows, %d scroll positions",
            count, visible, count - visible + 1)
    end

    -- Exported entry point, called from the two hook_safe bodies above. pcall
    -- wrap so a vanilla shape change degrades to no-scroll instead of killing
    -- the view build.
    mod._ct_boon_scroll_setup = function(view, boon_widgets, visible)
        local ok, err = pcall(_setup, view, boon_widgets, visible)

        if not ok then
            view._ct_boon_scroll = nil
            mod:warning("[ct:boon_scroll] setup errored: %s (scroll disabled, vanilla layout kept)", tostring(err))
        end
    end

    -- Wheel delta (y axis) from the view's input service; raw Mouse fallback.
    -- Both views run on IngameMenuKeymaps, which maps scroll_axis to the mouse
    -- wheel axis on win32 (controller_settings.lua), so the fallback should
    -- never trigger in practice.
    local function _wheel_delta(view)
        local delta = 0
        local input_service = view.input_service and view:input_service()

        if input_service and input_service.get then
            local axis = input_service:get("scroll_axis")

            if axis then
                delta = axis.y or 0
            end
        end

        if delta == 0 and rawget(_G, "Mouse") and Mouse.axis and Mouse.axis_index then
            local axis = Mouse.axis(Mouse.axis_index("wheel"))

            if axis then
                delta = axis.y or 0
            end
        end

        return delta
    end

    -- Cursor y in 1080p UI space (y-up, same space as scenegraph world
    -- positions) -- mirrors vanilla UIWidgets.create_scrollbar's held_function.
    local function _cursor_ui_y(view)
        local input_service = view.input_service and view:input_service()
        local cursor = input_service and input_service.get and input_service:get("cursor")

        if not cursor then
            return nil
        end

        local scaled = UIInverseScaleVectorToResolution(cursor)

        return scaled and scaled.y or nil
    end

    -- Per-frame driver, run BEFORE vanilla update (wrapping hooks below) so
    -- the reflow lands in the same frame's draw + hotspot pass. Cheap: <= 50
    -- offset writes per frame, no allocation on the steady-state path.
    local function _frame(view)
        local st = view._ct_boon_scroll

        if not st or not st.widgets or not st.scrollbar_widget then
            return
        end

        -- 1) mouse wheel: one row per notch (positive y = wheel up = scroll up)
        local wheel = _wheel_delta(view)

        if wheel ~= 0 then
            local step = math.max(1, math.floor(math.abs(wheel) + 0.5))

            st.top = wheel > 0 and st.top - step or st.top + step
        end

        -- 2) thumb drag / track paging
        local content = st.scrollbar_widget.content
        local thumb_hotspot = content.thumb_hotspot
        local track_hotspot = content.track_hotspot

        if thumb_hotspot and track_hotspot and (thumb_hotspot.is_held or track_hotspot.on_release) then
            local cursor_y = _cursor_ui_y(view)
            local node_pos = view.ui_scenegraph and UISceneGraph.get_world_position(view.ui_scenegraph, "power_up_root")

            if cursor_y and node_pos then
                if thumb_hotspot.is_held then
                    -- Drag: thumb center follows the cursor, snapped to rows.
                    -- is_held persists while the button stays down even after
                    -- the cursor leaves the thumb (hotspot pass semantics), so
                    -- this is a real drag, not just a re-click.
                    local usable = st.track_h - st.thumb_h

                    if usable > 0 then
                        local track_top_world = node_pos[2] + NODE_CENTER_Y + st.track_h / 2
                        local frac = math.clamp((track_top_world - cursor_y - st.thumb_h / 2) / usable, 0, 1)

                        st.top = 1 + math.floor(frac * (st.max_top - 1) + 0.5)
                    end
                elseif not thumb_hotspot.cursor_hover then
                    -- Track click off the thumb: page one full window toward the click.
                    local thumb_bottom_world = node_pos[2] + st.scrollbar_widget.style.thumb.offset[2]
                    local thumb_center_world = thumb_bottom_world + st.thumb_h / 2

                    if cursor_y > thumb_center_world then
                        st.top = st.top - st.visible
                    else
                        st.top = st.top + st.visible
                    end
                end
            end

            track_hotspot.on_release = false -- consumed
        end

        st.top = math.clamp(st.top, 1, st.max_top)
        _reposition(st)
    end

    -- Wrapping hooks (NOT hook_safe) so scroll input + reflow run BEFORE
    -- vanilla update draws the same frame; otherwise the layout would lag the
    -- input by one frame. Neither view's `update` was hooked before this
    -- (grep-verified 2026-07-01). pcall wrap per PROJECT_STANDARDS 4.1; on
    -- error the scroll state is dropped (degrade to vanilla-ish frozen list)
    -- and vanilla update ALWAYS still runs (4.2 guard-is-not-bail).
    mod:hook("DeusShopView", "update", function(func, self, dt, t)
        local ok, err = pcall(_frame, self)

        if not ok then
            self._ct_boon_scroll = nil
            mod:warning("[ct:boon_scroll] shop frame errored: %s (scroll disabled for this view)", tostring(err))
        end

        return func(self, dt, t)
    end)

    mod:hook("DeusCursedChestView", "update", function(func, self, dt, t)
        local ok, err = pcall(_frame, self)

        if not ok then
            self._ct_boon_scroll = nil
            mod:warning("[ct:boon_scroll] chest frame errored: %s (scroll disabled for this view)", tostring(err))
        end

        return func(self, dt, t)
    end)
end

-- No return value on purpose. The one seam this owner publishes -
-- mod._ct_boon_scroll_setup - is a `mod` field assigned by the moved code above,
-- because _ct_regression.lua's boon_offer_scrollbar_wired check resolves it off
-- `mod` at CALL time. An install-time return would be a second, divergent
-- channel for state that is already reachable, so the shape stays exactly as it
-- was pre-extraction.

end

return install
