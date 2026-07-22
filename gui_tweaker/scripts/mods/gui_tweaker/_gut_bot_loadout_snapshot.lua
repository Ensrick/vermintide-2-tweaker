-- Detached bot-loadout owner (#954). The saved-loadout module supplies the
-- realm/store seams; this owner registers the two bot-specific hooks exactly
-- once and never touches official persistence.
local Runtime = {}

Runtime.MARKER = "gut-954-detached-bot-loadout"

function Runtime.install(mod, deps)
    local mode = deps.mode
    local store = deps.store
    local persist = deps.persist
    local policy = deps.policy
    local slot_names = deps.slot_names
    local mode_store = deps.mode_store
    local log_prefix = deps.log_prefix

    mod:hook_safe("BackendInterfaceItemPlayfab", "refresh_bot_loadouts", function(self)
        if mode() ~= mode_store then return end
        local bot = self._bot_loadouts
        if type(bot) ~= "table" then return end
        local migrated = false
        for career_name, entry in pairs(store()) do
            if type(entry) == "table" then
                local bot_index = entry.bot_index
                local rows = type(entry.loadouts) == "table" and entry.loadouts or nil
                local snapshot = entry.bot_loadout
                -- One-time migration for stores written before #954. Snapshot the
                -- current designated row once; later owner edits cannot alias it.
                if type(snapshot) ~= "table" and bot_index and rows and rows[bot_index] then
                    snapshot = policy.snapshot_bot_loadout(rows[bot_index], slot_names)
                    entry.bot_loadout = snapshot
                    migrated = snapshot ~= nil or migrated
                    if snapshot then
                        printf("[gut:954] migrated detached bot loadout career=%s source_index=%s",
                            tostring(career_name), tostring(bot_index))
                    end
                end
                if type(snapshot) == "table" then
                    -- The backend cache gets another detached copy so it cannot
                    -- mutate the persisted bot snapshot through table identity.
                    bot[career_name] = policy.snapshot_bot_loadout(snapshot, slot_names)
                end
            end
        end
        if migrated then persist() end
    end)

    -- The native UI designates a saved row by index. Store that index for its
    -- checkmark, but make the bot's equipment a point-in-time copy. [src:
    -- hero_window_loadout_selection_console.lua:671-683]
    mod:hook("HeroWindowLoadoutSelectionConsole", "_save_bot_equipment", function(func, self)
        local current_mode = mode()
        if current_mode == deps.mode_off then return func(self) end
        if current_mode == deps.mode_readonly then
            printf("[%s:NATIVE_LOADOUTS] bot_equipment BLOCKED (read-only non-modded loadouts)", log_prefix)
            return
        end

        local profile = SPProfiles and SPProfiles[self._profile_index]
        local career_settings = profile and profile.careers and profile.careers[self._career_index]
        local career_name = career_settings and career_settings.name
        if not career_name then return end

        local all = store()
        local entry = all[career_name]
        if type(entry) ~= "table" then
            entry = { selected_index = 1, bot_index = nil, loadouts = {} }
            all[career_name] = entry
        end
        if type(entry.loadouts) ~= "table" then entry.loadouts = {} end
        entry.bot_index = self._context_menu_loadout_index
        local designated_row = entry.bot_index and entry.loadouts[entry.bot_index]
        entry.bot_loadout = policy.snapshot_bot_loadout(designated_row, slot_names)
        persist()
        printf("[%s:NATIVE_LOADOUTS] bot_equipment career=%s bot_index=%s detached_snapshot=%s -> store (skipped PlayerData write)",
            log_prefix, tostring(career_name), tostring(entry.bot_index),
            tostring(entry.bot_loadout ~= nil))

        local ok, iface = pcall(function() return Managers.backend:get_interface("items") end)
        if ok and iface and iface.refresh_bot_loadouts then
            pcall(function() iface:refresh_bot_loadouts() end)
        end
    end)
end

function Runtime.contract_check(policy, slot_names)
    if Runtime.MARKER ~= "gut-954-detached-bot-loadout" then return "marker mismatch" end
    if type(policy.snapshot_bot_loadout) ~= "function" then return "snapshot helper unavailable" end
    local source = { slot_melee = "owner", slot_ranged = "ranged", ignored = "metadata" }
    local snapshot = policy.snapshot_bot_loadout(source, slot_names)
    if type(snapshot) ~= "table" then return "bot snapshot unavailable" end
    source.slot_melee = "owner-edited"
    if snapshot.slot_melee ~= "owner" then return "bot snapshot aliases owner row" end
    if snapshot.ignored ~= nil then return "bot snapshot retained non-slot metadata" end
end

return Runtime
