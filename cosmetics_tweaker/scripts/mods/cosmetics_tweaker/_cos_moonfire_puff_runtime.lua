-- Owns the optional cosmetic Moonfire Bow impact puff hooks.
-- Gameplay AOE behavior remains in Tweaker: Weapons; this owner only adds the
-- decorative impact particle when that gameplay feature is not already doing so.

local MoonfirePuffRuntime = {}

local function publish_owner(mod, state)
    local owner = mod._cos_moonfire_puff_runtime_owner
    if type(owner) ~= "table" then owner = {} end
    for key in pairs(owner) do owner[key] = nil end
    owner.hook_count = state.hook_count or 0
    owner.is_moonfire_arrow = state.is_moonfire_arrow
    owner.puff_on_hit = state.puff_on_hit
    mod._cos_moonfire_puff_runtime_owner = owner
    return owner
end

function MoonfirePuffRuntime.install(mod, deps)
    deps = deps or {}
    local state = mod._cos_moonfire_puff_runtime_state
    if not state then
        state = { installed = false, hook_count = 0 }
        mod._cos_moonfire_puff_runtime_state = state
    end

    state.get_mod = assert(deps.get_mod, "get_mod is required")
    state.get_class = assert(deps.get_class, "get_class is required")
    -- These engine tables were historically resolved only when an impact hook
    -- fired. Keep that late binding: capturing nil during an early load would
    -- otherwise turn a later valid impact into a regression.
    state.get_world = assert(deps.get_world, "get_world is required")
    state.get_quaternion = assert(
        deps.get_quaternion,
        "get_quaternion is required"
    )
    state.puff_fx = deps.puff_fx or "fx/wpnfx_we_deus_01_impact"

    state.is_moonfire_arrow = state.is_moonfire_arrow or function(item_name)
        return item_name ~= nil
            and string.sub(item_name, 1, 10) == "we_deus_01"
    end

    state.puff_on_hit = state.puff_on_hit or function(self, hit_position)
        if not mod:get("cos_moonfire_cosmetic_puff") then return end
        if not state.is_moonfire_arrow(self.item_name) then return end
        local wt = state.get_mod("wt")
        if wt and wt:get("moonfire_aoe_revert") then return end
        local world = self._world
        if not world or not hit_position then return end
        local world_api = state.get_world()
        local quaternion = state.get_quaternion()
        world_api.create_particles(
            world, state.puff_fx, hit_position, quaternion.identity())
    end

    if state.installed then return publish_owner(mod, state) end

    for _, class_name in ipairs({
        "PlayerProjectileUnitExtension",
        "PlayerProjectileHuskExtension",
    }) do
        local class = state.get_class(class_name)
        if class then
            for _, method_name in ipairs({
                "hit_enemy",
                "hit_level_unit",
                "hit_non_level_unit",
            }) do
                if class[method_name] then
                    mod:hook_safe(class, method_name,
                        function(self, impact_data, hit_unit, hit_position)
                            state.puff_on_hit(self, hit_position)
                        end)
                    state.hook_count = state.hook_count + 1
                end
            end
        end
    end

    state.installed = true
    return publish_owner(mod, state)
end

return MoonfirePuffRuntime
