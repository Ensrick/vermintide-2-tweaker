-- Cosmetics-authored hats that reuse vanilla attachment contracts while
-- carrying their own compiled unit/material resources. Registration is
-- unconditional and deterministic; settings only control availability and
-- rendering, never NetworkLookup membership.

local mod = get_mod("cosmetics_tweaker")
local M = {}

M.ITEM_KEY = "cos_encarmine_hat"
M.VARIANT_KEY = "cos_custom_encarmine_hat"
M.BASE_KEY = "knight_hat_0006"
M.BASE_UNIT = "units/beings/player/empire_soldier_knight/headpiece/es_k_hat_07"
-- v0.9.110 shipped a unit without a same-path resource package, so preview
-- PackageManager loads fatally missed BD55DCA31255AAEC.package. Keep the
-- candidate quarantined behind a complete package/unit/material/texture probe;
-- any missing resource retains the inventory-package-listed vanilla fallback.
M.CANDIDATE_CUSTOM_UNIT = "units/cosmetics_tweaker/encarmine_hat/encarmine_hat"
M.CUSTOM_UNIT = M.BASE_UNIT
M.CUSTOM_MATERIALS = {
    "units/cosmetics_tweaker/encarmine_hat/encarmine_armored",
    "units/cosmetics_tweaker/encarmine_hat/encarmine_cloth",
}
M.CUSTOM_TEXTURES = {
    "textures/cosmetics_tweaker/encarmine_hat/encarmine_armored_diffuse",
    "textures/cosmetics_tweaker/encarmine_hat/encarmine_armored_normal",
    "textures/cosmetics_tweaker/encarmine_hat/encarmine_armored_metallic",
    "textures/cosmetics_tweaker/encarmine_hat/encarmine_armored_ao",
    "textures/cosmetics_tweaker/encarmine_hat/encarmine_armored_roughness",
    "textures/cosmetics_tweaker/encarmine_hat/encarmine_cloth_diffuse",
    "textures/cosmetics_tweaker/encarmine_hat/encarmine_cloth_normal",
    "textures/cosmetics_tweaker/encarmine_hat/encarmine_cloth_metallic",
    "textures/cosmetics_tweaker/encarmine_hat/encarmine_cloth_ao",
    "textures/cosmetics_tweaker/encarmine_hat/encarmine_cloth_roughness",
}
M.runtime_custom_ready = false
M.registered = false
M._probe_elapsed = 0
M._probe_attempts = 0
M._probe_limit = 30

local ITEM_LOCALIZATION = {
    cos_encarmine_hat_name = "Encarmine Helmet",
    cos_encarmine_hat_description =
        "A red-and-gold Foot Knight helm with a black plume, created for Tweaker: Cosmetics.",
}
M.ITEM_LOCALIZATION = ITEM_LOCALIZATION

local function can_get(application, resource_type, path)
    if not (application and type(application.can_get) == "function") then return false end
    local ok, result = pcall(application.can_get, resource_type, path)
    return ok and result == true
end

local function ensure_custom_clone_bridge()
    local bridge = M.bridge
    if not (M.runtime_custom_ready and bridge and bridge.unit_path_to_clones) then return end
    local clones = bridge.unit_path_to_clones[M.CANDIDATE_CUSTOM_UNIT] or {}
    for _, key in ipairs(clones) do
        if key == M.ITEM_KEY then return end
    end
    clones[#clones + 1] = M.ITEM_KEY
    bridge.unit_path_to_clones[M.CANDIDATE_CUSTOM_UNIT] = clones
end

function M.runtime_resources_ready(application)
    if not can_get(application, "package", M.CANDIDATE_CUSTOM_UNIT)
        or not can_get(application, "unit", M.CANDIDATE_CUSTOM_UNIT) then
        return false
    end
    for _, path in ipairs(M.CUSTOM_MATERIALS) do
        if not can_get(application, "material", path) then return false end
    end
    for _, path in ipairs(M.CUSTOM_TEXTURES) do
        if not can_get(application, "texture", path) then return false end
    end
    return true
end

function M.refresh_runtime_resources(application)
    local ready = M.runtime_resources_ready(application)
    M.runtime_custom_ready = ready
    M.CUSTOM_UNIT = ready and M.CANDIDATE_CUSTOM_UNIT or M.BASE_UNIT
    ensure_custom_clone_bridge()
    local entry = ItemMasterList and rawget(ItemMasterList, M.ITEM_KEY)
    if entry then entry.unit = M.CUSTOM_UNIT end
    return ready
end

function M.tick(dt)
    if M.runtime_custom_ready or M._probe_attempts >= M._probe_limit then return end
    M._probe_elapsed = M._probe_elapsed + (tonumber(dt) or 0)
    if M._probe_attempts > 0 and M._probe_elapsed < 0.25 then return end
    M._probe_elapsed = 0
    M._probe_attempts = M._probe_attempts + 1
    if M.refresh_runtime_resources(Application) then
        M.sync_toggle()
        mod:info("[cos:encarmine] compiled package closure ready after %d probe(s)", M._probe_attempts)
    elseif M._probe_attempts == M._probe_limit then
        mod:error("[cos:encarmine] custom package closure unavailable after %d probes; retaining Laurel fallback", M._probe_attempts)
    end
end

local function enabled()
    if not mod or type(mod.get) ~= "function" then return true end
    local ok, value = pcall(mod.get, mod, "cos_encarmine_hat_enabled")
    return not ok or value ~= false
end

function M.is_enabled()
    return enabled()
end

function M.resolve_variant(key)
    if key ~= M.VARIANT_KEY then return nil end
    local active = enabled()
    return {
        kind = "custom_unit",
        swap_hand = "hat",
        new_units = { active and M.CUSTOM_UNIT or M.BASE_UNIT },
        is_vanilla_unit = M.CUSTOM_UNIT == M.BASE_UNIT or not active,
        cos_authored = true,
        enabled = active,
    }
end

local function build_entry()
    local original = ItemMasterList and rawget(ItemMasterList, M.BASE_KEY)
    if type(original) ~= "table" then return nil end
    local entry = table.clone(original)
    entry.key = M.ITEM_KEY
    entry.name = M.ITEM_KEY
    entry.display_name = "cos_encarmine_hat_name"
    entry.description = "cos_encarmine_hat_description"
    entry.localized_name = ITEM_LOCALIZATION.cos_encarmine_hat_name
    entry.localized_description = ITEM_LOCALIZATION.cos_encarmine_hat_description
    entry.inventory_icon = "icon_knight_hat_0006_encarmine"
    entry.unit = enabled() and M.CUSTOM_UNIT or M.BASE_UNIT
    entry.rarity = "exotic"
    entry.required_dlc = nil
    entry.can_wield = enabled() and { "es_knight" } or {}
    entry.cos_authored = true
    entry.cos_vanilla_fallback = M.BASE_KEY
    entry.mod_data = {
        backend_id = M.ITEM_KEY,
        ItemInstanceId = M.ITEM_KEY,
        key = M.ITEM_KEY,
        ItemId = M.ITEM_KEY,
        CustomData = { rarity = "exotic" },
        rarity = "exotic",
    }
    return entry
end

function M.sync_toggle()
    local entry = ItemMasterList and rawget(ItemMasterList, M.ITEM_KEY)
    if not entry then return false end
    entry.unit = enabled() and M.CUSTOM_UNIT or M.BASE_UNIT
    entry.can_wield = enabled() and { "es_knight" } or {}
    return true
end

function M.register_all(bridge)
    M.bridge = bridge or M.bridge
    M.refresh_runtime_resources(Application)
    if M.registered then
        M.sync_toggle()
        return true
    end
    if not (ItemMasterList and NetworkLookup and NetworkLookup.item_names) then return false end
    if not (mod and type(mod.add_mod_items_to_masterlist) == "function"
            and type(mod.add_mod_items_to_local_backend) == "function") then
        return false
    end

    local entry = build_entry()
    if not entry then return false end
    mod:add_mod_items_to_masterlist({ entry })
    mod:add_mod_items_to_local_backend({ entry }, "cosmetics_tweaker")

    if bridge then
        bridge.backend_to_armoury[M.ITEM_KEY] = M.VARIANT_KEY
        bridge.backend_to_vanilla[M.ITEM_KEY] = M.BASE_KEY
        bridge.armoury_to_backend[M.VARIANT_KEY] = M.ITEM_KEY
        -- Never alias the shared vanilla fallback path as a custom clone: that
        -- would make ordinary Laurel Helm instances look like this item.
        ensure_custom_clone_bridge()
        bridge.custom_variants = bridge.custom_variants or {}
        bridge.custom_variants[M.VARIANT_KEY] = true
        -- `registered` means the shared net-safe appearance registry is live.
        -- LA's own one-time registration is tracked independently.
        bridge.registered = true
    end

    M.registered = true
    mod:info("[cos:encarmine] registered %s -> %s (package_ready=%s enabled=%s)",
        M.ITEM_KEY, M.CUSTOM_UNIT, tostring(M.runtime_custom_ready), tostring(enabled()))
    return true
end

return M
