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
local VANILLA_MATERIAL = "materials/fonts/arial"
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
        vanilla = 0,
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
        elseif material == VANILLA_MATERIAL then
            result.vanilla = result.vanilla + 1
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
    elseif result.vanilla == result.total then
        result.state = "vanilla_font_active"
    elseif result.other == result.total then
        result.state = "custom_provider_active"
    else
        result.state = "mixed_provider"
    end
    return result
end

-- Lua strings already carry the UTF-8 bytes used by chat/player names. The
-- renderer decides whether those code points have glyphs. Keep this validator
-- pure so the diagnostic can distinguish malformed input from a missing atlas
-- without touching the chat pipeline or rewriting names.
local function _utf8_metrics(value)
    if type(value) ~= "string" then
        return { valid = false, bytes = 0, codepoints = 0, non_ascii = 0, reason = "not_string" }
    end

    local bytes, codepoints, non_ascii = #value, 0, 0
    local i = 1
    while i <= bytes do
        local b1 = string.byte(value, i)
        local width, minimum
        if b1 <= 0x7F then
            width, minimum = 1, 0
        elseif b1 >= 0xC2 and b1 <= 0xDF then
            width, minimum = 2, 0x80
        elseif b1 >= 0xE0 and b1 <= 0xEF then
            width, minimum = 3, 0x800
        elseif b1 >= 0xF0 and b1 <= 0xF4 then
            width, minimum = 4, 0x10000
        else
            return { valid = false, bytes = bytes, codepoints = codepoints,
                non_ascii = non_ascii, reason = "invalid_lead", offset = i }
        end

        if i + width - 1 > bytes then
            return { valid = false, bytes = bytes, codepoints = codepoints,
                non_ascii = non_ascii, reason = "truncated", offset = i }
        end

        local cp = b1
        if width > 1 then
            cp = b1 % (2 ^ (8 - width - 1))
            for j = 2, width do
                local continuation = string.byte(value, i + j - 1)
                if continuation < 0x80 or continuation > 0xBF then
                    return { valid = false, bytes = bytes, codepoints = codepoints,
                        non_ascii = non_ascii, reason = "invalid_continuation", offset = i + j - 1 }
                end
                cp = cp * 64 + (continuation - 0x80)
            end
            if cp < minimum or cp > 0x10FFFF or (cp >= 0xD800 and cp <= 0xDFFF) then
                return { valid = false, bytes = bytes, codepoints = codepoints,
                    non_ascii = non_ascii, reason = "invalid_codepoint", offset = i }
            end
            non_ascii = non_ascii + 1
        end

        codepoints = codepoints + 1
        i = i + width
    end

    return { valid = true, bytes = bytes, codepoints = codepoints,
        non_ascii = non_ascii, reason = "ok" }
end

local function _utf8_encode(codepoints)
    local out = {}
    for _, cp in ipairs(codepoints) do
        if cp <= 0x7F then
            out[#out + 1] = string.char(cp)
        elseif cp <= 0x7FF then
            out[#out + 1] = string.char(0xC0 + math.floor(cp / 0x40), 0x80 + cp % 0x40)
        elseif cp <= 0xFFFF then
            out[#out + 1] = string.char(0xE0 + math.floor(cp / 0x1000),
                0x80 + math.floor(cp / 0x40) % 0x40, 0x80 + cp % 0x40)
        else
            out[#out + 1] = string.char(0xF0 + math.floor(cp / 0x40000),
                0x80 + math.floor(cp / 0x1000) % 0x40,
                0x80 + math.floor(cp / 0x40) % 0x40, 0x80 + cp % 0x40)
        end
    end
    return table.concat(out)
end

-- Construct samples from code points rather than source-file glyphs. This
-- keeps the probe deterministic across editors while exercising the same UTF-8
-- bytes the vanilla chat renderer receives.
local GLYPH_SAMPLES = {
    { label = "Latin", text = _utf8_encode({ 0x00C1, 0x00C9, 0x00CD, 0x00D3, 0x00DA, 0x00F1, 0x00F8, 0x0142 }) },
    { label = "Greek", text = _utf8_encode({ 0x0393, 0x03B5, 0x03B9, 0x03AC }) },
    { label = "Cyrillic", text = _utf8_encode({ 0x041F, 0x0440, 0x0438, 0x0432, 0x0435, 0x0442 }) },
    { label = "Japanese", text = _utf8_encode({ 0x65E5, 0x672C, 0x8A9E }) },
    { label = "Chinese", text = _utf8_encode({ 0x4E2D, 0x6587, 0x7E41, 0x9AD4 }) },
    { label = "Korean", text = _utf8_encode({ 0xD55C, 0xAD6D, 0xC5B4 }) },
}

local function _inspect_player_names()
    local report = { total = 0, valid = 0, invalid = 0, non_ascii = 0, rows = {} }
    local managers = rawget(_G, "Managers")
    local player_manager = managers and managers.player
    if not player_manager or type(player_manager.human_players) ~= "function" then
        report.state = "player_manager_unavailable"
        return report
    end

    local ok, players = pcall(player_manager.human_players, player_manager)
    if not ok or type(players) ~= "table" then
        report.state = "player_roster_unavailable"
        return report
    end

    for _, player in pairs(players) do
        report.total = report.total + 1
        local ok_name, name = pcall(player.name, player)
        local metrics = _utf8_metrics(ok_name and name or nil)
        metrics.slot = report.total
        report.rows[#report.rows + 1] = metrics
        if metrics.valid then report.valid = report.valid + 1 else report.invalid = report.invalid + 1 end
        if metrics.non_ascii > 0 then report.non_ascii = report.non_ascii + 1 end
    end
    report.state = report.invalid == 0 and "utf8_intact" or "malformed_name_bytes"
    return report
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
    utf8_metrics = _utf8_metrics,
    glyph_samples = GLYPH_SAMPLES,
    inspect_player_names = _inspect_player_names,
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
    local names = _inspect_player_names()
    mod:echo("[gut:340] standalone present=%s enabled=%s; fonts=%s (%d/%d Unicode, %d missing)",
        tostring(present), tostring(enabled), scan.state,
        scan.unicode, scan.total, scan.missing)
    if enabled and scan.state ~= "unicode_active" then
        mod:echo("[gut:340] standalone is enabled but its eight-font swap is incomplete; check its load/package state.")
    elseif not enabled and scan.state ~= "unicode_active" then
        mod:echo("[gut:340] no Unicode atlas is active; use Workshop 3232229691 or a future redistributable atlas provider.")
    end
    mod:echo("[gut:340] glyph probe: each line should render as letters, not square blocks")
    for _, sample in ipairs(GLYPH_SAMPLES) do
        mod:echo("[gut:340] %s: %s", sample.label, sample.text)
    end
    _printf("[gut:340] player-name UTF-8: state=%s total=%d valid=%d invalid=%d non_ascii=%d",
        names.state, names.total, names.valid, names.invalid, names.non_ascii)
    for _, row in ipairs(names.rows) do
        _printf("[gut:340] player-name slot=%d utf8=%s bytes=%d codepoints=%d non_ascii=%d reason=%s offset=%s",
            row.slot, tostring(row.valid), row.bytes, row.codepoints, row.non_ascii,
            row.reason, tostring(row.offset or "-"))
    end
end)

return mod._GUT_ALL_LANGUAGES
