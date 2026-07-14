local mod = get_mod("gt_dev")
local Policy = mod:dofile("scripts/mods/general_tweaker_dev/_gt_dummy_collision_policy")

-- Keep dummy no-collision (#304).
--
-- Vanilla does not produce the player's keep-dummy blocking by disabling or
-- enabling a dummy actor. `breed_training_dummy.lua` gives the breed a
-- `player_locomotion_constrain_radius` of 0.7; AISimpleExtension.init and
-- AiHuskBaseExtension.init copy that value onto each unit extension; then
-- PlayerUnitLocomotionExtension constrains the local player's movement around
-- every nearby AI extension with a non-nil radius
-- (`player_unit_locomotion_extension.lua:463-534`). Clearing ONLY this per-unit
-- value therefore removes body avoidance while preserving the dummy's authored
-- c_head/c_torso/etc. collision actors, hit zones, damage and preview behavior.
--
-- Both authoritative and husk init seams are required: movement avoidance is
-- evaluated locally, so a host sees AISimpleExtension while a joining client
-- can see AiHuskBaseExtension for the same dummy. No state or geometry is sent.

local _tracked = setmetatable({}, { __mode = "k" })

local function _is_in_inn()
    local damage_utils = rawget(_G, "DamageUtils")
    return damage_utils ~= nil and damage_utils.is_in_inn == true
end

local function _apply_one(extension, record, enabled, is_in_inn)
    if Policy.should_remove_player_constraint(enabled, is_in_inn, record.breed) then
        extension.player_locomotion_constrain_radius = nil
    else
        extension.player_locomotion_constrain_radius = record.native_radius
    end
end

local function _observe(extension)
    local breed = extension and extension._breed
    if not Policy.is_training_dummy(breed) then return end

    local record = _tracked[extension]
    if not record then
        record = {
            breed = breed,
            native_radius = extension.player_locomotion_constrain_radius,
        }
        _tracked[extension] = record
    end

    _apply_one(extension, record, mod:get("gt_keep_dummy_no_collision"), _is_in_inn())
end

function mod._gt_apply_keep_dummy_collision(enabled)
    local is_in_inn = _is_in_inn()
    for extension, record in pairs(_tracked) do
        _apply_one(extension, record, enabled, is_in_inn)
    end
end

function mod._gt_restore_keep_dummy_collision()
    for extension, record in pairs(_tracked) do
        extension.player_locomotion_constrain_radius = record.native_radius
    end
end

-- Hook preflight, 2026-07-13: both methods exist in the vanilla decompile and
-- repository-wide grep found no other gt_dev registration for either pair.
mod:hook_safe("AISimpleExtension", "init", function(self)
    _observe(self)
end)

mod:hook_safe("AiHuskBaseExtension", "init", function(self)
    _observe(self)
end)

-- Runtime-test exports. The policy itself is pure; these markers prove the
-- shipped module and both local-authority seams were wired.
mod._gt_dummy_collision_policy = Policy
mod._gt_dummy_collision_hook_count = 2
