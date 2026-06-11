local mod = get_mod("gut")

-- Mod Tweaker view class — stub.
-- v0.1 scaffold placeholder. The full ModTweakerView gets built in tasks #5-8:
-- transition + view registration in ingame_ui_settings, then scenegraph +
-- tab strip + widget factories. This file exists now so the controller can
-- safely `require` it once that work lands without a load-order shuffle.

local ModTweakerView = class(ModTweakerView)

ModTweakerView.NAME = "mod_tweaker_view"

function ModTweakerView:init(ingame_ui_context)
    self.ingame_ui_context = ingame_ui_context
    -- Real scenegraph/UIRenderer setup arrives with task #6.
end

function ModTweakerView:on_enter() end
function ModTweakerView:on_exit() end
function ModTweakerView:update(dt, t) end
function ModTweakerView:post_update(dt, t) end
function ModTweakerView:exit() end

return ModTweakerView
