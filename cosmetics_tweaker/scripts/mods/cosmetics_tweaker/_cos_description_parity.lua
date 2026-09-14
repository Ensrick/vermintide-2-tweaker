-- _cos_description_parity.lua -- item / illusion description-key parity (#1567).
--
-- Data-only provider: the vanilla description-key typo aliases, the
-- resolved-text predicate, and a bounded census of ItemMasterList and
-- WeaponSkins.skins description keys against a Localize function. It reads no
-- engine global, registers nothing, installs no hook and never mutates a table
-- it is handed. _cos_illusions.lua consumes the aliases inside its singleton
-- _G.Localize hook and registers the named regression check;
-- _cos_diagnostics.lua prints the census as the /cos_1567_diag receipt.
--
-- Vanilla evidence (decompile paths relative to Vermintide-2-Source-Code):
--   wh_deus_skin_02_magic_02 (Saltzpyre's Shyish griffon-foot, versus rewards):
--     item_master_list_versus_rewards.lua:1653 and
--     weapon_skins_versus_rewards.lua:1186 both spell the key
--     "wh_deus_skin_02_magic_02_desciption". No correctly spelled row exists in
--     the decompile, so the Saltzpyre Shyish reward sibling
--     (weapon_skins_versus_rewards.lua:601) is the parity target after the
--     corrected spelling.
--   wh_deus_01_skin_magic / wh_deus_02_skin_magic (Weavebound griffon-foot):
--     weapon_skins_morris.lua:573,588 spell "wh_deus_01_magic_desciption" while
--     item_master_list_morris.lua:994 carries the correctly spelled
--     "wh_deus_01_magic_description" for the same weapon.
-- The item card reads WeaponSkins.skins[skin].description
-- (scripts/helpers/ui_utils.lua:219-231), so the misspelled skin rows are what
-- players see, and a missing key renders "<key>"
-- (foundation/scripts/managers/localization/localization_manager.lua:3-5).

local M = {}

M.API_VERSION = 1

-- Misspelled vanilla description key -> ordered sibling candidates. The first
-- candidate the live localizer resolves wins. When none resolves the caller
-- keeps vanilla's own "<key>" result so a parity gap stays visible instead of
-- borrowing unrelated prose.
M.VANILLA_ALIASES = {
    wh_deus_skin_02_magic_02_desciption = {
        "wh_deus_skin_02_magic_02_description",
        "wh_fencing_sword_skin_07_magic_02_description",
    },
    wh_deus_01_magic_desciption = {
        "wh_deus_01_magic_description",
    },
}

-- Live rows that carry each misspelled key. The named regression check reads
-- these so a vanilla respelling is noticed and the alias retired with it.
M.VANILLA_TYPO_ROWS = {
    { table = "skins", key = "wh_deus_skin_02_magic_02", description_key = "wh_deus_skin_02_magic_02_desciption" },
    { table = "items", key = "wh_deus_skin_02_magic_02", description_key = "wh_deus_skin_02_magic_02_desciption" },
    { table = "skins", key = "wh_deus_01_skin_magic", description_key = "wh_deus_01_magic_desciption" },
    { table = "skins", key = "wh_deus_02_skin_magic", description_key = "wh_deus_01_magic_desciption" },
}

M.SAMPLE_CAP = 12

-- True when `text` is a rendered description rather than the missing-key
-- placeholder, the bare key, or a non-string.
function M.resolved(text, key)
    return type(text) == "string" and text ~= "" and text ~= key
        and text:sub(1, 1) ~= "<"
end

-- Returns the first alias candidate that `localize` resolves for `key`, or nil
-- when the key has no alias, no candidate resolves, or `localize` is absent.
function M.alias_route(key, localize)
    local candidates = M.VANILLA_ALIASES[key]
    if not candidates or type(localize) ~= "function" then return nil end
    for index = 1, #candidates do
        local candidate = candidates[index]
        local ok, text = pcall(localize, candidate)
        if ok and M.resolved(text, candidate) then
            return candidate
        end
    end
    return nil
end

-- Vanilla ships unreachable test rows (item_master_list_test_items.lua) whose
-- keys and descriptions start with "test_"; they are counted, never listed.
local function _is_test_row(row_key, description)
    return (type(row_key) == "string" and row_key:sub(1, 5) == "test_")
        or description:sub(1, 5) == "test_"
end

local function _sorted_keys(set)
    local list = {}
    for key in pairs(set) do list[#list + 1] = key end
    table.sort(list)
    return list
end

-- Census every description key in `items` (ItemMasterList) and `skins`
-- (WeaponSkins.skins) against `localize`. Each distinct key resolves once.
-- Returns counts plus a sorted sample of unresolved keys capped at
-- opts.sample_cap (default SAMPLE_CAP); opts.is_custom(key) marks mod-owned
-- keys for the custom counters. No table handed in is mutated.
function M.census(items, skins, localize, opts)
    local cap = opts and opts.sample_cap or M.SAMPLE_CAP
    local is_custom = opts and opts.is_custom
    local report = {
        item_rows = 0, skin_rows = 0, keys = 0, resolved = 0, unresolved = 0,
        bridged = 0, custom = 0, custom_unresolved = 0, skipped_test = 0,
        sample = {}, truncated = false,
    }
    local seen = {}
    local unresolved_set = {}
    local function visit(row_key, row, counter)
        local data = type(row) == "table" and (row.data or row) or nil
        local description = data and data.description
        if type(description) ~= "string" or description == "" then return end
        report[counter] = report[counter] + 1
        if _is_test_row(row_key, description) then
            report.skipped_test = report.skipped_test + 1
            return
        end
        if seen[description] then return end
        seen[description] = true
        report.keys = report.keys + 1
        local custom = is_custom and is_custom(description) == true
        if custom then report.custom = report.custom + 1 end
        local ok, text = false, nil
        if type(localize) == "function" then
            ok, text = pcall(localize, description)
        end
        if ok and M.resolved(text, description) then
            report.resolved = report.resolved + 1
            if M.VANILLA_ALIASES[description] then
                report.bridged = report.bridged + 1
            end
        else
            report.unresolved = report.unresolved + 1
            if custom then report.custom_unresolved = report.custom_unresolved + 1 end
            unresolved_set[description] = true
        end
    end
    if type(items) == "table" then
        for row_key, row in pairs(items) do visit(row_key, row, "item_rows") end
    end
    if type(skins) == "table" then
        for row_key, row in pairs(skins) do visit(row_key, row, "skin_rows") end
    end
    local list = _sorted_keys(unresolved_set)
    for index = 1, math.min(cap, #list) do report.sample[index] = list[index] end
    report.truncated = #list > cap
    return report
end

-- One log-safe token for the receipt line: "-" when nothing is unresolved,
-- else the capped sorted sample with a trailing ",..." when truncated.
function M.sample_text(report)
    if type(report) ~= "table" or type(report.sample) ~= "table"
        or #report.sample == 0 then
        return "-"
    end
    local text = table.concat(report.sample, ",")
    if report.truncated then text = text .. ",..." end
    return text
end

return M
