local mod = get_mod("la_prefix_patch")

local MOD_VERSION = "0.2.0-dev"
mod:info("LA Prefix Patch v%s loaded", MOD_VERSION)
mod:echo("LA Prefix Patch v" .. MOD_VERSION)

-- VMF runs each mod's script inside its own new_mod() call, so when our script
-- runs LA hasn't been created yet (get_mod("Loremasters-Armoury") returns nil
-- here). We can't reach LA's instance directly. Instead we patch VMFMod's
-- prototype hook methods so that any future call from a mod whose name is
-- "Loremasters-Armoury" runs through a dupe filter; all other mods pass
-- through unchanged. Our launcher load order guarantees this patch is
-- installed before LA's mod_script runs.
--
-- LA's utils/hooks.lua registers three duplicates: LevelEndView.start,
-- LevelTransitionHandler.load_current_level, LocalizationManager._base_lookup.
-- VMF rejects the second call AND emits a warning to chat. We drop the
-- second call before VMF sees it; first registration always wins (which is
-- the correct semantics — the first _base_lookup body carries the cosmetic
-- skin-name swap, the second is a strict subset that would clobber it).

local LA_NAME = "Loremasters-Armoury"
local seen = {}

local function key_for(self, obj, method)
    return tostring(self) .. "|" .. tostring(obj) .. "::" .. tostring(method)
end

local function wrap(orig_method)
    if type(orig_method) ~= "function" then return orig_method end
    return function(self, obj, method, handler)
        if self.get_name and self:get_name() == LA_NAME then
            local k = key_for(self, obj, method)
            if seen[k] then
                return
            end
            seen[k] = true
        end
        return orig_method(self, obj, method, handler)
    end
end

if rawget(_G, "VMFMod") then
    VMFMod.hook        = wrap(VMFMod.hook)
    VMFMod.hook_safe   = wrap(VMFMod.hook_safe)
    VMFMod.hook_origin = wrap(VMFMod.hook_origin)
    mod:info("VMFMod hook methods wrapped; LA duplicate registrations will be silently ignored.")
else
    mod:warning("VMFMod prototype not found; LA dupe filter NOT installed.")
end
