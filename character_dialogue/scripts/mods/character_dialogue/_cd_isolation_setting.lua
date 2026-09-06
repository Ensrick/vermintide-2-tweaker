-- #998 Durable setting owner. VMF persists silent batch writes; exactly one
-- completion callback reconciles preview ownership. No GUI or audio state here.
local Setting = { ID = "auto_isolation", VERSION = 1 }

function Setting.install(mod, reconcile)
    local function get() return mod:get(Setting.ID) == true end
    local function changed(id)
        if id == Setting.ID then return reconcile(get()) end
    end
    mod.on_setting_changed = changed
    mod.on_settings_batch_changed = function(ids)
        -- This owner opts into GUT's bounded transaction only for this setting.
        -- Unknown buffers must not be consumed as a successful Apply.
        for i = 1, #ids do
            assert(ids[i] == Setting.ID, "unsupported Character Dialogue batch setting")
        end
        if #ids > 0 then
            assert(changed(Setting.ID) ~= false, "preview audio isolation unavailable")
        end
    end
    return {
        get = get,
        set = function(value)
            value = value == true
            mod:set(Setting.ID, value, false)
            -- v5 consumers call this setter without a protected boundary.
            -- Preserve best-effort audio reconciliation for that legacy API;
            -- only the new batch completion treats unavailable audio as failure.
            changed(Setting.ID)
            return value
        end,
    }
end

return Setting
