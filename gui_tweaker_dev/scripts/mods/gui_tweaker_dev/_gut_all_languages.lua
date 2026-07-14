local mod = get_mod("gut_dev")
local _printf = rawget(_G, "printf") or function() end  -- engine printf (survives mod-logging-OFF)

-- _gut_all_languages.lua — All-Language display support: DETECT-AND-DEFER (issue #340)
--
-- WHAT #340 ASKED FOR: port the Workshop mod "Support All Languages" (id 3232229691)
-- into gut so player names + chat render without square blocks (missing CJK/Cyrillic
-- glyphs) regardless of the client's game language. Known cost: ~25 MB memory.
--
-- WHY THIS MODULE DOES NOTHING (the mechanism, from the decompiled source):
-- The source mod's whole logic is a global-table swap (extract:
-- misc-vermintide-mods/Support All Languages/scripts/mods/support-all-languages/
-- support-all-languages.lua). On enable it repoints the FIRST element (the font
-- MATERIAL path) of eight vanilla Fonts entries — arial, arial_masked,
-- arial_write_mask, hell_shark_arial{,_masked,_write_mask}, chat_output_font{,_masked}
-- (ui_fonts.lua:6-84, [1] = "materials/fonts/arial") — from "materials/fonts/arial"
-- to a NEW material path "fonts/ArialUnicodeMS", keeping [2] size + [3] font-name.
-- That new material (an Arial Unicode MS glyph atlas covering ~50k CJK/Cyrillic
-- glyphs) is NOT a vanilla asset: "ArialUnicodeMS" appears NOWHERE in the decompiled
-- source (grep 2026-07-13, Vermintide-2-Source-Code). It ships INSIDE the source
-- mod's own bundle: the extract's .mod declares
--   packages = { "resource_packages/support-all-languages/support-all-languages" }
-- and the extractor log records that bundle as 32,583,136 bytes (~32 MB) while every
-- recovered Lua/manifest file is a few hundred bytes — i.e. the ~32 MB IS the compiled
-- font atlas, packed into the mod. (misc-vermintide-mods/Support All Languages/_extract.log.)
--
-- => CASE 2 (ships a CUSTOM font resource). gut CANNOT deliver this feature by
-- re-pointing Fonts alone: the target material must be RESIDENT, and gut ships no
-- such resource. Doing the swap here would point every chat/name/most-UI text surface
-- at a material that does not exist in gut's bundle — a Gui material-not-found failure
-- for ALL gut users, not a fix. And we cannot absorb the source mod's atlas: it is
-- another author's compiled font asset (Arial Unicode MS is a Microsoft font), not
-- ours to redistribute.
--
-- RESOLUTION (issue #340): documentation + recommendation. Players who want all-language
-- display should subscribe to the standalone "Support All Languages" (Workshop
-- 3232229691) — it is purpose-built, tiny in code, load-order-compatible with gut
-- (it only mutates the global Fonts table; no hooks; pure local rendering, no networked
-- surface), and self-contained (its own font bundle). This module is the durable
-- record of that decision + a DEFER guard: if a future gut build ever gains its own
-- (redistributable, e.g. OFL) font-swap feature, it must NO-OP when the standalone mod
-- is present so the two don't double-swap Fonts. It adds NO menu toggle (there is no
-- working feature to gate) and installs NO hooks.

local STANDALONE_NAME = "support-all-languages"
local UNICODE_MATERIAL = "fonts/ArialUnicodeMS"
local FONT_KEYS = {
    "arial",
    "arial_masked",
    "arial_write_mask",
    "hell_shark_arial",
    "hell_shark_arial_masked",
    "hell_shark_arial_write_mask",
    "chat_output_font",
    "chat_output_font_masked",
}

-- Detect the standalone mod (installed = registered; enabled = its own on/off state).
local function _standalone()
    local lookup = rawget(_G, "get_mod")
    if type(lookup) ~= "function" then return nil end
    return lookup(STANDALONE_NAME)
end

local function _standalone_enabled()
    local m = _standalone()
    if not m or type(m.is_enabled) ~= "function" then return false end
    local ok, en = pcall(m.is_enabled, m)
    return ok and en and true or false
end

-- Read-only inspection of the exact eight entries mutated by the standalone
-- mod. This is intentionally evaluated on demand: its on_enabled callback may
-- run after gut's module load, so a load-time snapshot alone can be stale.
local function _inspect_fonts()
    local fonts = rawget(_G, "Fonts")
    local result = {
        total = #FONT_KEYS,
        unicode = 0,
        other = 0,
        missing = 0,
        materials = {},
    }

    for _, key in ipairs(FONT_KEYS) do
        local row = type(fonts) == "table" and rawget(fonts, key) or nil
        local material = type(row) == "table" and rawget(row, 1) or nil
        result.materials[key] = material
        if material == UNICODE_MATERIAL then
            result.unicode = result.unicode + 1
        elseif type(material) == "string" then
            result.other = result.other + 1
        else
            result.missing = result.missing + 1
        end
    end

    if result.unicode == result.total then
        result.state = "unicode_active"
    elseif result.unicode > 0 then
        result.state = "partial_swap"
    elseif result.missing > 0 then
        result.state = "font_rows_missing"
    else
        result.state = "vanilla_or_other_provider"
    end
    return result
end

-- Marker read by the /gut_regression_test check `all_languages_defer_340`. Its shape
-- proves the module loaded AND stayed a pure defer (no font swap, no hooks).
mod._GUT_ALL_LANGUAGES = {
    case = "custom_font_resource_case2",  -- the decompiled mechanism (see header)
    standalone_id = STANDALONE_NAME,
    does_font_swap = false,               -- gut ships no font atlas; swapping would break render
    installs_hooks = false,
    standalone_present = _standalone() ~= nil,
    standalone_enabled = _standalone_enabled(),
    unicode_material = UNICODE_MATERIAL,
    font_keys = FONT_KEYS,
    inspect_fonts = _inspect_fonts,
}

if mod._GUT_ALL_LANGUAGES.standalone_enabled then
    _printf("[gut:340] all-languages: standalone '%s' present+enabled; gut defers (no font swap).", STANDALONE_NAME)
elseif mod._GUT_ALL_LANGUAGES.standalone_present then
    _printf("[gut:340] all-languages: standalone '%s' present (disabled); gut inert.", STANDALONE_NAME)
else
    _printf("[gut:340] all-languages: standalone '%s' absent; gut ships no font atlas (case 2), inert. Recommend Workshop 3232229691.", STANDALONE_NAME)
end

-- Explicit, user-invoked diagnostics only; never pollute launch chat. This
-- distinguishes an absent provider from a provider that is enabled but whose
-- callback/material package did not take effect.
mod:command("gut_all_languages_status", "Diagnose issue #340 all-language font support", function()
    local present = _standalone() ~= nil
    local enabled = _standalone_enabled()
    local scan = _inspect_fonts()
    mod:echo("[gut:340] standalone present=%s enabled=%s; fonts=%s (%d/%d Unicode, %d missing)",
        tostring(present), tostring(enabled), scan.state,
        scan.unicode, scan.total, scan.missing)
    if enabled and scan.state ~= "unicode_active" then
        mod:echo("[gut:340] standalone is enabled but its eight-font swap is incomplete; check its load/package state.")
    elseif not enabled and scan.state ~= "unicode_active" then
        mod:echo("[gut:340] no Unicode atlas is active; use Workshop 3232229691 or a future redistributable atlas provider.")
    end
end)

return mod._GUT_ALL_LANGUAGES
