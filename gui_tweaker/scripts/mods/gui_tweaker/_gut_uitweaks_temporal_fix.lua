local mod = get_mod("gut")

-- ============================================================================
-- UI Tweaks "Temporal Fix" (absorbed into gut)
-- ============================================================================
-- WHAT IT IS (researched + verified 2026-06-18):
--   "UI Tweaks Temporal Fix" is a removed/unsanctioned standalone mod by Isaakk
--   (Workshop 3366928597). Despite the name, it has NOTHING to do with temporal
--   reprojection/ghosting — it is a forked copy of UI Tweaks (internal name
--   "HideBuffs", Workshop 1467751760) with a tiny patch that re-aligns the
--   PLAYER's own health bar in the MINI-HUD layout, which the game's Versus
--   update knocked out of place. (Confirmed by UI Tweaks author "rain":
--   the health-bar placement is a post-Versus bug, and "the temporal fix is not
--   sanctioned, so it cannot be used in official realm" — bundling forked engine
--   resources is what makes it unsanctioned, not the offsets themselves.)
--
-- THE EXACT FIX (authoritative — bytecode diff of 3366928597 vs 1467751760, both
-- decompiled with the same tool so only Isaakk's change remains):
--   player_unit_frame_ui.lua, `player_unit_frame_draw`, MINI_HUD_PRESET branch:
--     total_health_bar.offset[1]:  -size/2          -> +size/2 + 50
--     hp_bar.offset[1]:            -size/2          -> +size/2 + 50
--     hp_bar_highlight.offset[1]:  -hp_bar.size/2   -> +hp_bar.size/2 + 50
--     ability_dynamic.offset[1]:   0                -> -2     (then +1 if rect layout)
--   content_change_functions.lua (player grimoire divider + bar):
--     offset[1] shifted left by exactly 58 * mod.hp_bar_w_scale
--       (divider: (-283.5+553*g)*scale -> (-341.5+553*g)*scale ;
--        bar:     (-274.5+553*g)*scale -> (-332.5+553*g)*scale)
--
-- HOW WE INCLUDE IT (sanctioned, no forked resources):
--   All three patched functions are PUBLIC on the HideBuffs mod table
--   (mod.player_unit_frame_draw / mod.player_grimoire_*_content_change_fun), and
--   the grimoire ones are re-assigned to widget passes every draw. So we wrap
--   them: call the original, then re-apply the corrected offsets. This delivers
--   Isaakk's fix as a pure-Lua patch on stock UI Tweaks (no need for the removed
--   mod). ALWAYS ON now (the user removed the toggle + slider) with a baked-in
--   horizontal nudge of -48 px. No-op if UI Tweaks (HideBuffs) isn't installed.

local NUDGE_X = -48  -- baked-in mini-HUD health-bar horizontal nudge (was a slider)

-- Install once. Safe to call repeatedly (guarded) and before/after HideBuffs
-- loads (no-op until it's present).
local function apply()
    local HB = get_mod("HideBuffs")
    if not HB then
        return false
    end
    if HB._gut_temporal_fix_installed then
        return true
    end

    -- (1) Player HP-bar / ability-bar offsets (mini-hud branch).
    if type(HB.player_unit_frame_draw) == "function" then
        local orig = HB.player_unit_frame_draw
        HB.player_unit_frame_draw = function(ufui)
            orig(ufui)
            -- Isaakk's offsets live only in the MINI_HUD_PRESET branch.
            if not (HB.SETTING_NAMES and HB:get(HB.SETTING_NAMES.MINI_HUD_PRESET)) then
                return
            end
            -- Place the bar CENTRED on its anchor (-size/2) plus the baked-in -48
            -- nudge (the value the user dialed in). Negative pulls left.
            local nudge = NUDGE_X
            local hp = ufui and ufui._health_widgets and ufui._health_widgets.health_dynamic
            local s = hp and hp.style
            local applied_off, applied_sz
            if s then
                local thb = s.total_health_bar
                if thb and thb.size and thb.offset then
                    thb.offset[1] = -thb.size[1] / 2 + nudge
                    applied_off, applied_sz = thb.offset[1], thb.size[1]
                end
                local hpb = s.hp_bar
                if hpb and hpb.size and hpb.offset then
                    hpb.offset[1] = -hpb.size[1] / 2 + nudge
                end
                local hl = s.hp_bar_highlight
                if hl and hl.offset and hpb and hpb.size then
                    hl.offset[1] = -hpb.size[1] / 2 + nudge
                end
            end
            local ad = ufui and ufui._ability_widgets and ufui._ability_widgets.ability_dynamic
            if ad and ad.offset then
                local rect = (HB.using_rect_player_layout and HB.using_rect_player_layout()) and 1 or 0
                ad.offset[1] = -2 + rect
            end
            -- One-shot value dump so the correct offset can be read from the log.
            if applied_off and not HB._gut_tfix_logged then
                HB._gut_tfix_logged = true
                mod:debug("[gut] temporal-fix: hp_bar size_x=%.0f -> offset_x=%.0f (nudge=%d)",
                    applied_sz or -1, applied_off, nudge)
            end
        end
    end

    -- (2) Player grimoire divider + bar: shift offset[1] left by 58 * hp_bar_w_scale.
    --     These functions are re-assigned to the hp widget's passes every draw,
    --     so wrapping the mod-table field is picked up next frame.
    local function wrap_grim(fn_name)
        local orig = HB[fn_name]
        if type(orig) ~= "function" then
            return
        end
        HB[fn_name] = function(content, style)
            orig(content, style)
            if style and style.offset then
                style.offset[1] = style.offset[1] - 58 * (HB.hp_bar_w_scale or 1)
            end
        end
    end
    wrap_grim("player_grimoire_debuff_divider_content_change_fun")
    wrap_grim("player_grimoire_bar_content_change_fun")

    HB._gut_temporal_fix_installed = true
    mod:info("[gut] UI Tweaks Temporal Fix installed (HideBuffs player HP-bar placement patch; always on, nudge=%d)",
        NUDGE_X)
    return true
end

return { apply = apply }
