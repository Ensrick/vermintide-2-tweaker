-- #998 Non-mutating runtime check: actual staging/transaction methods operate
-- on an isolated owner installed by CD's production setting module.
local mod = get_mod("gut_dev")
local M = {}

-- CD API v6 (character_dialogue.lua `version = 6`, first published in Character
-- Dialogue 0.1.14-dev) adds the staged owner. No CD, or an older one, is a
-- supported setup: _mod_tweaker_dialogue.lua isolation_lead omits the row, so the
-- check SKIPs by name there and FAILs only when a v6+ CD lacks the owner.
M.STAGED_API = 6
local NEEDS = "needs Character Dialogue 0.1.14-dev or newer; the Dialogue tab omits the isolation row"

function M.owner_problem(cd)
    if not cd then return "skip: Character Dialogue is not installed (optional integration)" end
    local api = cd.character_dialogue_api
    if type(api) ~= "table" or type(api.version) ~= "number" then
        return "skip: Character Dialogue exposes no versioned character_dialogue_api (" .. NEEDS .. ")"
    end
    if api.version < M.STAGED_API then
        return string.format("skip: Character Dialogue API v%s predates the v%d staged-isolation owner (%s)",
            tostring(api.version), M.STAGED_API, NEEDS)
    end
    local setting = api.isolation_setting
    if type(setting) ~= "table" or setting.version ~= 1 or setting.setting_id ~= "auto_isolation" then
        return string.format("Character Dialogue API v%s lacks the isolation_setting v1 auto_isolation descriptor",
            tostring(api.version))
    end
    if type(cd.on_settings_batch_changed) ~= "function" then
        return string.format("Character Dialogue API v%s lacks on_settings_batch_changed", tostring(api.version))
    end
end

function M.install(register)
    register("issue998_dialogue_staged_isolation", function()
        local cd = get_mod("character_dialogue")
        local problem = M.owner_problem(cd)
        if problem then return problem end
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
