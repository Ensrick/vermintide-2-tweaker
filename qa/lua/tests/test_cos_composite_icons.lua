return function(Harness, repo_root)
local Catalog = dofile(repo_root
    .. "/cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_cos_composite_icon_catalog.lua")
local Factory = dofile(repo_root
    .. "/cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_cos_composite_icons.lua")

local function available(name)
    return name ~= "missing"
end

local function proof_args(backend_id)
    return {
        backend_id = backend_id or "proof-a",
        exact_instance = true,
        item_type = "es_1h_mace_shield",
        skin = "es_1h_mace_shield_skin_03_runed_01",
        offhand_unit = "units/weapons/player/wpn_emp_gk_shield_02/wpn_emp_gk_shield_02_runed_01",
        glow_state = { rune = { r = 64, g = 128, b = 255, intensity = 1 } },
        local_resource_available = available,
    }
end

Harness.test("#650 composite proof preserves declared layer order and exact RGB", function()
    local descriptor = Factory.new(Catalog).resolve(proof_args())
    Harness.equal(descriptor.primary_texture, "icon_cos_empire_mace_shield_primary_01")
    Harness.equal(descriptor.offhand_texture, "icon_cos_breton_shield_02")
    Harness.equal(descriptor.glow_texture, "icon_cos_breton_shield_rune_glow")
    Harness.equal(table.concat(descriptor.layer_order, ","),
        "native_background,primary_weapon,offhand,glow_mask,native_frame")
    Harness.equal(table.concat(descriptor.glow_color, ","), "255,64,128,255")
end)

Harness.test("#650 GOTWF skin_03 variant keeps the same authored mace layer", function()
    local args = proof_args()
    args.skin = "es_1h_mace_shield_skin_03_runed_05"
    local descriptor = Factory.new(Catalog).resolve(args)
    Harness.equal(descriptor.primary_texture, "icon_cos_empire_mace_shield_primary_01")
    Harness.equal(descriptor.offhand_texture, "icon_cos_breton_shield_02")
end)

Harness.test("#650 first live picker primary uses the authored mace layer", function()
    local args = proof_args()
    args.skin = "es_1h_mace_shield_skin_02"
    local descriptor = Factory.new(Catalog).resolve(args)
    Harness.equal(descriptor.primary_texture, "icon_cos_empire_mace_shield_primary_01")
    Harness.equal(descriptor.offhand_texture, "icon_cos_breton_shield_02")
end)

Harness.test("#650 detailed resolver exposes bounded diagnostic outcomes", function()
    local compositor = Factory.new(Catalog)
    local args = proof_args()
    args.skin = "es_1h_mace_shield_skin_01"
    local descriptor, reason = compositor.resolve_detailed(args)
    Harness.equal(descriptor, nil)
    Harness.equal(reason, "unmapped-primary")
    descriptor, reason = compositor.resolve_detailed(proof_args())
    Harness.truthy(descriptor)
    Harness.equal(reason, "composed")
end)

Harness.test("#650 descriptors fail closed without exact instance or local assets", function()
    local compositor = Factory.new(Catalog)
    local args = proof_args()
    args.exact_instance = false
    Harness.equal(compositor.resolve(args), nil)
    args = proof_args()
    args.local_resource_available = function(name)
        return name ~= "icon_cos_breton_shield_02"
    end
    Harness.equal(compositor.resolve(args), nil)
end)

Harness.test("#650 cache is instance isolated, copy safe, and fingerprint refreshed", function()
    local compositor = Factory.new(Catalog)
    local first = compositor.resolve(proof_args("a"))
    first.glow_color[2] = 0
    local cached_copy = compositor.resolve(proof_args("a"))
    Harness.equal(cached_copy.glow_color[2], 64)
    local other_args = proof_args("b")
    other_args.glow_state.rune.r = 191
    Harness.equal(compositor.resolve(other_args).glow_color[2], 191)
    local changed = proof_args("a")
    changed.glow_state.rune.r = 255
    Harness.equal(compositor.resolve(changed).glow_color[2], 255)
    compositor.invalidate("a")
    Harness.truthy(compositor.resolve(changed))
end)

Harness.test("#650 unsupported primary or shield mappings preserve native presentation", function()
    local compositor = Factory.new(Catalog)
    local args = proof_args()
    args.skin = "es_1h_mace_shield_skin_01"
    Harness.equal(compositor.resolve(args), nil)
    args = proof_args()
    args.offhand_unit = "units/weapons/player/wpn_emp_gk_shield_05/wpn_emp_gk_shield_05"
    Harness.equal(compositor.resolve(args), nil)
end)

Harness.test("#650 ordinary Bretonnian shield never inherits rune glow", function()
    local args = proof_args()
    args.offhand_unit = "units/weapons/player/wpn_emp_gk_shield_03/wpn_emp_gk_shield_03"
    local descriptor = Factory.new(Catalog).resolve(args)
    Harness.equal(descriptor.offhand_texture, "icon_cos_breton_shield_01")
    Harness.equal(descriptor.glow_texture, nil)
    Harness.equal(descriptor.glow_color, nil)
end)

Harness.test("#650 dormant rune state does not emit a glow layer", function()
    local args = proof_args()
    args.glow_state.rune.intensity = 0
    local descriptor = Factory.new(Catalog).resolve(args)
    Harness.equal(descriptor.offhand_texture, "icon_cos_breton_shield_02")
    Harness.equal(descriptor.glow_texture, nil)
    Harness.equal(descriptor.glow_color, nil)
end)

Harness.test("#650 reused grid cell restores its unsupported item's native icon", function()
    local compositor = Factory.new(Catalog)
    local descriptor = compositor.resolve(proof_args("a"))
    local icon, state = compositor.resolve_cell(nil, {
        identity = "a", current_icon = "native-a", descriptor = descriptor,
    })
    Harness.equal(icon, descriptor.primary_texture)
    icon, state = compositor.resolve_cell(state, {
        identity = "b", current_icon = "native-b", descriptor = nil,
    })
    Harness.equal(icon, "native-b")
    icon, state = compositor.resolve_cell(state, {
        identity = "b", current_icon = "native-b-updated", descriptor = nil,
    })
    Harness.equal(icon, "native-b-updated")
end)

Harness.test("#650 UIUtils publishes descriptors without leaking mace-only icons", function()
    local path = repo_root
        .. "/cosmetics_tweaker/scripts/mods/cosmetics_tweaker/cosmetics_tweaker.lua"
    local file = assert(io.open(path, "rb"))
    local source = file:read("*a")
    file:close()
    Harness.truthy(source:find("_cos_refresh_composite_descriptor%(item, record%)"))
    Harness.truthy(source:find("COMPOSITE_ICONS%.publish%(item, descriptor%)"))
    Harness.truthy(source:find("COMPOSITE_ICONS%.descriptor_for%(item%)"))
    Harness.equal(source:find("_composite_icon_descriptor_by_item"), nil)
    Harness.equal(source:find("item%._cos_composite_icon_descriptor"), nil)
    Harness.equal(source:find("inventory_icon%s*=%s*composite%.inventory_icon"), nil)
    Harness.truthy(source:find('content%["hotspot" %.%. suffix%]'))
    Harness.truthy(source:find("hotspot_content%[icon_name%] = resolved_icon"))
    Harness.equal(source:find("current_icon = content%[icon_name%]"), nil)
end)

Harness.test("#650 renderer publication stays weak and renderer-local", function()
    local compositor = Factory.new(Catalog)
    local item = {}
    local descriptor = compositor.resolve(proof_args("published"))
    compositor.publish(item, descriptor)
    Harness.equal(compositor.descriptor_for(item).fingerprint, descriptor.fingerprint)
    compositor.publish(item, nil)
    Harness.equal(compositor.descriptor_for(item), nil)
end)

Harness.test("#650 diagnostic claims are deduplicated, compatible, and bounded", function()
    local compositor = Factory.new(Catalog)
    local args = proof_args("diagnostic")
    Harness.truthy(compositor.claim_diagnostic("composed", args))
    Harness.equal(compositor.claim_diagnostic("composed", args), false)
    args.item_type = "es_2h_sword"
    Harness.equal(compositor.claim_diagnostic("composed", args), false)
    for index = 1, 31 do
        args = proof_args("diagnostic-" .. index)
        args.skin = "skin-" .. index
        Harness.truthy(compositor.claim_diagnostic("unmapped-primary", args))
    end
    args = proof_args("diagnostic-overflow")
    args.skin = "skin-overflow"
    Harness.equal(compositor.claim_diagnostic("unmapped-primary", args), false)
end)

Harness.test("#650 Cosmetics entry compiles within Lua 5.1 function limits", function()
    local path = repo_root
        .. "/cosmetics_tweaker/scripts/mods/cosmetics_tweaker/cosmetics_tweaker.lua"
    local chunk, compile_error = loadfile(path)
    if not chunk then error(compile_error, 0) end
end)

Harness.test("#650 compositor is renderer-local and has no peer transport", function()
    local paths = {
        repo_root .. "/cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_cos_composite_icons.lua",
        repo_root .. "/cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_cos_composite_icon_catalog.lua",
    }
    for _, path in ipairs(paths) do
        local file = assert(io.open(path, "rb"))
        local source = file:read("*a")
        file:close()
        Harness.equal(source:find("network_send", 1, true), nil)
        Harness.equal(source:find("NetworkLookup", 1, true), nil)
    end
end)

Harness.test("#650 grid passes are decorated before UIWidget pass_data initialization", function()
    local path = repo_root
        .. "/cosmetics_tweaker/scripts/mods/cosmetics_tweaker/cosmetics_tweaker.lua"
    local file = assert(io.open(path, "rb"))
    local source = file:read("*a")
    file:close()

    local hook_start = assert(source:find('mod:hook("UIWidget", "init"', 1, true))
    local vanilla_init = assert(source:find("return func(widget_definition, ui_renderer)",
        hook_start, true))
    local composite_enrich = assert(source:find(
        "_enrich_item_grid_composite_icons(widget_definition)", hook_start, true))
    local badge_enrich = assert(source:find(
        "_enrich_item_grid_glow_badges(widget_definition)", hook_start, true))
    Harness.truthy(composite_enrich < vanilla_init)
    Harness.truthy(badge_enrich < vanilla_init)
    Harness.truthy(source:find(
        "widget.element and widget.element.pass_data ~= nil then return false end",
        1, true))

    local item_grid_hook = assert(source:find(
        'mod:hook_safe("ItemGridUI", "init"', 1, true))
    local item_grid_hook_end = assert(source:find("end)", item_grid_hook, true))
    local item_grid_block = source:sub(item_grid_hook, item_grid_hook_end)
    Harness.equal(item_grid_block:find("_enrich_item_grid", 1, true), nil)
end)
end
