-- #998 Non-mutating runtime check: actual staging/transaction methods operate
-- on an isolated owner installed by CD's production setting module.
local mod = get_mod("gut_dev")
local M = {}

function M.install(register)
    register("issue998_dialogue_staged_isolation", function()
        local cd = get_mod("character_dialogue")
        if not cd then return end -- optional integration
        local api = cd.character_dialogue_api
        if not api or not api.isolation_setting or api.isolation_setting.version ~= 1
            or api.isolation_setting.setting_id ~= "auto_isolation"
            or type(cd.on_settings_batch_changed) ~= "function" then
            return "Character Dialogue staged-isolation owner unavailable; install the coordinated build"
        end
        local Setting = cd:dofile("scripts/mods/character_dialogue/_cd_isolation_setting")
        local View = mod:dofile("scripts/mods/gui_tweaker_dev/_mod_tweaker_view")
        local UI = mod:dofile("scripts/mods/gui_tweaker_dev/_mod_tweaker_dialogue")
        local Transaction = mod:dofile("scripts/mods/gui_tweaker_dev/_mod_tweaker_transaction")
        local saved, writes, reconciles = false, 0, 0
        local owner = { get = function() return saved end,
            set = function(_, _, value) saved = value; writes = writes + 1 end }
        local setting = Setting.install(owner, function() reconciles = reconciles + 1 end)
        local category = { mod_id = "character_dialogue", _owners = {
            auto_isolation = { mod_id = "character_dialogue", mod_obj = owner } } }
        local view = setmetatable({ _pending = {}, _categories = { category }, _selected = 1,
            _apply = { content = {} }, _search_note_setting = function() end }, { __index = View })
        local row = { _category = category, _setting_id = Setting.ID, content = {}, _dialogue_sequence = 1 }
        UI.stage_isolation(view, row, { get_auto_isolation = setting.get })
        if saved or writes ~= 0 or reconciles ~= 0 or view._apply.content.disabled then
            return "isolation edit did not remain a dirty, uncommitted draft"
        end
        local count, batched, err, complete = Transaction.commit(category,
            view._pending.character_dialogue, function() return owner end,
            function() error("isolation bypassed the batch owner") end)
        if not complete or err or not batched or count ~= 1 or not saved
            or writes ~= 1 or reconciles ~= 1 then return "isolation batch did not commit once" end
        view._pending = {}
        View._update_apply_button(view)
        if not view._apply.content.disabled then return "empty isolation draft remained dirty" end
    end)
end

return M
