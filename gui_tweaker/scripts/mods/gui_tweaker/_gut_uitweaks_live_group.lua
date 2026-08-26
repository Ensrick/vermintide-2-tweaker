-- Shared owner for the stock UI Tweaks live-tree bridge (#312).
-- Both Mod Tweaker presentations call this module so their owner routing,
-- disabled-state behavior, and profile exclusions cannot drift.

local mod = get_mod("gut")
local _printf = rawget(_G, "printf") or function() end
local external_group = mod:dofile("scripts/mods/gui_tweaker/_mod_tweaker_external_group")
local disabled_sections = mod:dofile("scripts/mods/gui_tweaker/_mod_tweaker_disabled_sections")

local M = {}

-- [UITWEAKS-BRIDGE-312] [UITWEAKS-LIVE-TREE-312]
function M.apply(out, args)
    args = args or {}
    local field = args.field
    local localize = args.localize
    if type(field) ~= "function" or type(localize) ~= "function" then return end

    local HB = get_mod("HideBuffs")
    if not HB then return end

    local gut_cat
    for _, category in ipairs(out or {}) do
        if category.mod_id == "gut" then gut_cat = category; break end
    end

    if type(HB.is_enabled) == "function" then
        local ok_enabled, enabled = pcall(HB.is_enabled, HB)
        if ok_enabled and enabled == false then
            if gut_cat then
                gut_cat.widgets = disabled_sections.disable_group_subtree(
                    gut_cat.widgets,
                    "hb_group",
                    localize("gut_disabled_in_vmf", disabled_sections.REASON)
                )
            end
            return
        end
    end
    if not gut_cat or type(gut_cat.widgets) ~= "table" then return end

    local vmf = get_mod("VMF")
    local live = external_group.find_mod_list(
        vmf and vmf.options_widgets_data,
        "HideBuffs",
        field
    )
    local plan = external_group.replace_group_children({
        widgets = gut_cat.widgets,
        live_list = live,
        group_id = "hb_group",
        preserve_group_ids = { gut_uitweaks_integration_group = true },
        field = field,
        owners = gut_cat._owners,
        owner_mod_ids = gut_cat._owner_mod_ids,
        base_owner_id = gut_cat.mod_id,
        owner_id = "HideBuffs",
        owner_obj = HB,
        profile_excluded_owners = gut_cat._profile_excluded_owners,
        exclude_owner_from_profiles = true,
    })
    if not plan.changed then
        if not mod._gut_uitweaks_live_tree_missing_logged then
            mod._gut_uitweaks_live_tree_missing_logged = true
            _printf("[gut:312] live UI Tweaks tree unavailable reason=%s; keeping authored fallback",
                tostring(plan.reason))
        end
        local fallback = external_group.bridge_known_fallback({
            widgets = gut_cat.widgets,
            setting_names = HB.SETTING_NAMES,
            field = field,
            owners = gut_cat._owners,
            owner_mod_ids = gut_cat._owner_mod_ids,
            base_owner_id = gut_cat.mod_id,
            owner_id = "HideBuffs",
            owner_obj = HB,
            profile_excluded_owners = gut_cat._profile_excluded_owners,
            exclude_owner_from_profiles = true,
        })
        if fallback.changed then
            gut_cat._owners = fallback.owners
            gut_cat._owner_mod_ids = fallback.owner_mod_ids
            gut_cat._profile_excluded_owners = fallback.profile_excluded_owners
        end
        return
    end

    gut_cat.widgets = plan.widgets
    gut_cat._owners = plan.owners
    gut_cat._owner_mod_ids = plan.owner_mod_ids
    gut_cat._profile_excluded_owners = plan.profile_excluded_owners
end

return M
