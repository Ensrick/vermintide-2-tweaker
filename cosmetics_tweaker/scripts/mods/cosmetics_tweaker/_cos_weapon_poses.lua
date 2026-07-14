local mod = get_mod("cosmetics_tweaker")

-- #485: local, modded-realm access to every authored weapon pose for the
-- currently wielded weapon. Vanilla builds this wheel solely from the backend's
-- unlocked_weapon_poses mirror. We replace only that gathered result; no
-- backend entitlement, loadout, RPC, or ItemMasterList entry is mutated.

local Policy = mod._cos_weapon_pose_policy
local catalog
local missing_logged = {}

local function enabled()
    return mod:get("cos_unlock_weapon_poses") == true
        and rawget(_G, "script_data")
        and script_data["eac-untrusted"] == true
end

local function get_catalog()
    if not catalog then
        catalog = Policy.build_catalog(rawget(_G, "ItemMasterList"))
    end
    return catalog
end

local function poses_for(parent_item)
    return Policy.for_parent(get_catalog(), parent_item)
end

-- Grep-verified singleton in Cosmetics: no other hook targets either method.
mod:hook("SocialWheelUI", "_gather_weapon_poses_by_parent_item", function(func, self, parent_item)
    if not enabled() then return func(self, parent_item) end

    local rows = poses_for(parent_item)
    if rows then return rows end

    -- The issue requests a fallback for weapons without authored icons. Reusing
    -- another weapon's package before its animation/icon compatibility is known
    -- would be speculative, so keep vanilla behavior and capture the exact gap.
    if not missing_logged[parent_item] then
        missing_logged[parent_item] = true
        pcall(printf, "[cos:485] no authored pose catalog parent=%s fallback=deferred", tostring(parent_item))
    end
    return func(self, parent_item)
end)

-- Force a live wheel rebuild when the option changes; otherwise vanilla's
-- early-return sees the same wielded item and keeps the stale page contents.
mod:hook("SocialWheelUI", "_is_dirty", function(func, self, parent_item)
    local live = enabled()
    if self._cos485_pose_unlock_state ~= live then
        self._cos485_pose_unlock_state = live
        return true
    end
    return func(self, parent_item)
end)

return {
    policy = Policy,
    enabled = enabled,
    poses_for = poses_for,
    marker = "social_wheel_authored_catalog_485",
}
