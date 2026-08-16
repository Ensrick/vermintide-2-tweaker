local mod = get_mod("cosmetics_tweaker")

-- #485: local, modded-realm access to every authored weapon pose for the
-- currently wielded weapon. Vanilla builds this wheel solely from the backend's
-- unlocked_weapon_poses mirror. We replace only that gathered result; no
-- backend entitlement, loadout, RPC, or ItemMasterList entry is mutated.

local Policy = mod._cos_weapon_pose_policy
local catalog
local missing_logged = {}

local function setting_on()
    return mod:get("cos_unlock_weapon_poses") == true
end

local function realm_untrusted()
    local sd = rawget(_G, "script_data")
    return (sd and sd["eac-untrusted"] == true) and true or false
end

local function enabled()
    return setting_on() and realm_untrusted()
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

-- #485: one truth-table walk per gather. Rows are only resolved (and the
-- catalog only built) once realm AND setting admit authored output.
local function decision_for(parent_item)
    local on, untrusted = setting_on(), realm_untrusted()
    if not (on and untrusted) then
        return Policy.decide(on, untrusted, nil), nil
    end
    local rows = poses_for(parent_item)
    return Policy.decide(on, untrusted, rows), rows
end

-- The issue requests a fallback for weapons without authored icons. Reusing
-- another weapon's package before its animation/icon compatibility is known
-- would be speculative, so unsupported parents keep vanilla behavior and this
-- captures the exact gap ONCE per parent under one bounded identity.
local function note_unsupported(parent_item)
    if missing_logged[parent_item] then return false end
    missing_logged[parent_item] = true
    pcall(printf, "[cos:485] no authored pose catalog parent=%s fallback=deferred", tostring(parent_item))
    return true
end

-- Grep-verified singleton in Cosmetics: no other hook targets either method.
mod:hook("SocialWheelUI", "_gather_weapon_poses_by_parent_item", function(func, self, parent_item)
    local decision, rows = decision_for(parent_item)
    if decision == "authored" then return rows end
    if decision == "vanilla-unsupported-parent" then
        note_unsupported(parent_item)
    end
    return func(self, parent_item)
end)

-- Force a live wheel rebuild when the option changes; otherwise vanilla's
-- early-return sees the same wielded item and keeps the stale page contents.
-- Policy.rebuild_armed arms exactly once per flip and then defers to vanilla.
mod:hook("SocialWheelUI", "_is_dirty", function(func, self, parent_item)
    if Policy.rebuild_armed(self, "_cos485_pose_unlock_state", enabled()) then
        return true
    end
    return func(self, parent_item)
end)

return {
    policy = Policy,
    enabled = enabled,
    poses_for = poses_for,
    decision_for = decision_for,
    note_unsupported = note_unsupported,
    marker = "social_wheel_authored_catalog_485",
}
