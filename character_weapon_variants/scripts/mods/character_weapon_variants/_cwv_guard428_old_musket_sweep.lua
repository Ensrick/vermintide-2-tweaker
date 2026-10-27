-- _cwv_guard428_old_musket_sweep.lua -- retained seven-action bayonet safety.
-- Owned by: character_weapon_variants.lua entry manifest.
-- Consumed via: private melee.bind factory, then one Musket install/check bind.
-- No registry repair, sender changes, per-frame capture or native latch reset.
-- hook-test: issue428_old_musket_retained_sweep
--
-- Standards8.6 guard gate:
-- 1. Prevent a retained/queued Old Musket Sweep from reading a lost profile/ID.
-- 2. Native93dea Sweep171/176/178,347-365,1450-1509 and WUE529,661-740;
--    #428 source probe demonstrates callback drift and final-flush exposure,
--    not a claim of historical crash causality or Stingray ABI coverage.
-- 3. On proven owned loss skip only the unsafe start continuation/inner sweep;
--    canonical interrupted cleanup still runs once when its cells are proven.
-- 4. Exact private start rejection unwinds before native timings/enter/FX;
--    cleanup failures remain terminal and ordinary errors propagate unchanged.
local function pack(...) return { n = select("#", ...), ... } end
local function new(capability)
    local classify, member, valid, cleanup = capability.classify, capability.member,
        capability.valid, capability.cleanup
    local records = setmetatable({}, { __mode = "k" })
    local latest = setmetatable({}, { __mode = "v" })
    local latest_unproven -- constant compiled row only; never a Sweep/unit/caller.
    local installed, attempted, incoming, epoch = false, false, nil, 0
    local C = {}
    local function caller(sweep)
        local ext = rawget(sweep, "_weapon_extension")
        return type(ext) == "table" and ext or nil
    end
    local function active(sweep, record)
        local ext = caller(sweep)
        return ext and rawget(ext, "current_action_settings") == record.row.action
            and type(rawget(ext, "actions")) == "table"
            and rawget(rawget(ext, "actions"), "sweep") == sweep
            and rawget(sweep, "_current_action") == record.row.action
            and rawget(sweep, "current_action") == record.row.action
    end
    local function terminal(record, reason)
        record.terminal = record.terminal or reason
        return false
    end
    local function stopped(sweep, record)
        local ext = caller(sweep)
        return ext and record.finished and rawget(ext, "current_action_settings") ~= record.row.action
    end
    local function stop(sweep, record)
        local ext = caller(sweep)
        if not active(sweep, record) then return terminal(record, "active_identity_unproven") end
        if record.terminal or record.stopping or record.finished then
            return terminal(record, "outer_cleanup_unproven")
        end
        if not cleanup(record.row) then return terminal(record, "cleanup_cells_unproven") end
        record.stopping = true
        local ok, err = pcall(ext.stop_action, ext, "interrupted")
        record.stopping = false
        if not ok then terminal(record, "native_cleanup_error"); error(err, 0) end
        if rawget(ext, "current_action_settings") ~= nil then
            return terminal(record, "outer_cleanup_unproven")
        end
        return false
    end
    local function start_hook(func, self, action_name, sub_action_name, actions, t, power, init)
        if not installed then return func(self, action_name, sub_action_name, actions, t, power, init) end
        local row, known = classify(actions, action_name, sub_action_name)
        local sweep = type(rawget(self, "actions")) == "table" and rawget(self.actions, "sweep")
        local old = sweep and records[sweep]
        if known and (not row or not valid(row)) then
            if old and active(sweep, old) and not valid(old.row) then stop(sweep, old) end
            return nil -- no native mutation has begun; preserve a healthy predecessor.
        end
        if not known and not old then return func(self, action_name, sub_action_name, actions, t, power, init) end
        epoch = epoch + 1
        local previous = incoming
        local frame = { caller = self, row = row, epoch = epoch, rejection = {}, previous = old }
        incoming = frame
        local result = pack(pcall(func, self, action_name, sub_action_name, actions, t, power, init))
        incoming = previous
        if result[1] then
            if old and sweep and records[sweep] == old and stopped(sweep, old) then records[sweep] = nil end
            return unpack(result, 2, result.n)
        end
        if result[2] == frame.rejection and frame.rejected and frame.sweep then
            local record = records[frame.sweep]
            if record and record.epoch == frame.epoch and active(frame.sweep, record) then
                stop(frame.sweep, record)
                return nil
            end
        end
        -- No blanket catch: ordinary native/proc/cleanup objects retain identity.
        local failed = frame.sweep or (type(rawget(self, "actions")) == "table" and rawget(self.actions, "sweep"))
        if frame.row and failed and rawget(self, "current_action_settings") == frame.row.action then
            -- Base on_start procs may throw before Sweep reaches our helper;
            -- do not let a reused object's older cache masquerade as this start.
            records[failed] = { row = frame.row, epoch = frame.epoch, phase = 0, terminal = "native_start_error" }
            latest[1] = failed
            latest_unproven = nil
        end
        error(result[2], 0)
    end
    local function helper_hook(func, self, hand, action)
        if not installed then return func(self, hand, action) end
        local row = member(action)
        if not row then return func(self, hand, action) end
        local frame, ext = incoming, caller(self)
        if not frame or frame.row ~= row or frame.caller ~= ext
                or rawget(ext, "current_action_settings") ~= action
                or rawget(self, "current_action") ~= action or rawget(self, "_current_action") ~= action
                or type(rawget(ext, "actions")) ~= "table" or rawget(ext.actions, "sweep") ~= self then
            error("[cwv:428] owned Sweep start context unproven", 0)
        end
        local record = { row = row, epoch = frame.epoch, phase = 0 }
        -- Native treats false like nil for selection but retains false in
        -- _action_hand. Never retain table/unit references from foreign input.
        if hand == false or type(hand) == "string" or type(hand) == "number" then record.hand = hand end
        records[self], latest[1], frame.sweep = record, self, self
        latest_unproven = nil
        -- Guard native effective-field reads BEFORE the original pure helper.
        -- It is invoked once, never pre-resolved in the outer start wrapper.
        local overrides = rawget(self, "_overridable_settings")
        if not valid(row) or type(overrides) ~= "table" or getmetatable(overrides) ~= nil
                or rawget(overrides, "damage_profile") ~= row.key then
            frame.rejected = true; record.reason = "start_authority_lost"
            error(frame.rejection, 0)
        end
        local selected = func(self, hand, action)
        if selected ~= row.key then
            frame.rejected = true; record.reason = "effective_profile_unproven"
            error(frame.rejection, 0)
        end
        return selected
    end
    local function update_hook(func, self, dt, t, action, current_time)
        if not installed then return func(self, dt, t, action, current_time) end
        local record = records[self]
        if not record then
            local row = member(rawget(self, "_current_action"))
            if row then
                -- Observe unsupported active context without adopting it,
                -- creating an epoch/record, allocating per frame or cleanup.
                latest[1], latest_unproven = self, row
                return false
            end
            return func(self, dt, t, action, current_time)
        end
        if stopped(self, record) then
            records[self] = nil
            if member(rawget(self, "_current_action")) then return false end
            return func(self, dt, t, action, current_time)
        end
        if record.terminal then return false end
        if record.finished and record.phase == 0 then return terminal(record, "outer_cleanup_unproven") end
        if not active(self, record) or action ~= record.row.action then
            return terminal(record, "active_identity_unproven")
        end
        local row = record.row
        local stored = rawget(self, "_stored_attack_data")
        local healthy = valid(row) and rawget(self, "_damage_profile") == row.profile
            and rawget(self, "_damage_profile_id") == row.id
            and rawget(self, "_action_hand") == record.hand
            and (not rawget(self, "_send_delayed_hit_rpc") or
                (type(stored) == "table" and rawget(stored, "damage_profile_id") == row.id))
        if healthy then return func(self, dt, t, action, current_time) end
        record.reason = "retained_authority_lost"
        if record.phase > 0 then return false end -- finish owns the remainder of cleanup.
        return stop(self, record)
    end
    local function finish_hook(func, self, reason, data)
        if not installed then return func(self, reason, data) end
        local record = records[self]
        if not record then return func(self, reason, data) end
        if record.terminal or record.finished then
            terminal(record, "outer_cleanup_unproven")
            error("[cwv:428] native Sweep cleanup already failed or returned", 0)
        end
        if not active(self, record) or not cleanup(record.row) then
            terminal(record, "cleanup_identity_unproven")
            error("[cwv:428] owned Sweep cleanup authority unproven", 0)
        end
        local previous = record.phase
        record.phase = previous + 1
        local result = pack(pcall(func, self, reason, data))
        record.phase = previous
        if not result[1] then terminal(record, "native_cleanup_error"); error(result[2], 0) end
        record.finished = true -- outer WUE may STILL throw before clearing settings.
        return unpack(result, 2, result.n)
    end
    function C.install(mod)
        if attempted then return installed end
        attempted = true
        local wue, sweep = WeaponUnitExtension, ActionSweep
        if type(wue) ~= "table" or type(sweep) ~= "table" or type(mod) ~= "table"
                or type(mod.hook) ~= "function" or type(rawget(wue, "start_action")) ~= "function"
                or type(rawget(sweep, "_get_damage_profile_name")) ~= "function"
                or type(rawget(sweep, "_update_sweep")) ~= "function"
                or type(rawget(sweep, "finish")) ~= "function" then return false end
        -- VMF successful registration returns nil. Fresh once-install + actual
        -- VMF-dispatch tests prove this contract; registration count is not ABI proof.
        local ok = pcall(function()
            mod:hook(wue, "start_action", start_hook)
            mod:hook(sweep, "_get_damage_profile_name", helper_hook)
            mod:hook(sweep, "_update_sweep", update_hook)
            mod:hook(sweep, "finish", finish_hook)
        end)
        installed = ok
        return installed
    end
    function C.ready() return installed end
    function C.check()
        if not installed then return "#428 retained Sweep guard not installed" end
        local sweep = latest[1]
        if not sweep then return "skip: wield and swing the Old Musket bayonet before this check" end
        local record = records[sweep]
        if not record and not latest_unproven then return "skip: latest Old Musket Sweep is no longer active" end
        if record and stopped(sweep, record) then return "skip: latest Old Musket Sweep is no longer active" end
        local unit = rawget(sweep, "weapon_unit")
        if unit ~= nil and type(Unit) == "table" and type(Unit.alive) == "function" then
            local ok, alive = pcall(Unit.alive, unit)
            if not ok then return "#428 retained Sweep unit liveness unreadable" end
            if alive == false then return "skip: latest Old Musket weapon unit is destroyed" end
        end
        if not record then
            local ext = caller(sweep)
            local actions = ext and rawget(ext, "actions")
            if type(actions) == "table" and rawget(actions, "sweep") == sweep then
                local action = rawget(ext, "current_action_settings")
                if action == nil then return "skip: latest unproven Old Musket caller is inactive" end
                if action ~= latest_unproven.action and not member(action)
                        and rawget(sweep, "_current_action") == action and rawget(sweep, "current_action") == action then
                    return "skip: latest unproven Old Musket caller switched to an unmanaged action"
                end
            end
            return "#428 retained Sweep active start context unproven"
        end
        if record.terminal then return "#428 retained Sweep terminal: " .. record.terminal end
        if record.finished then return "#428 retained Sweep outer cleanup unproven" end
        if not active(sweep, record) or not valid(record.row)
                or rawget(sweep, "_damage_profile") ~= record.row.profile
                or rawget(sweep, "_damage_profile_id") ~= record.row.id
                or rawget(sweep, "_action_hand") ~= record.hand then
            return "#428 retained Sweep active authority lost"
        end
        local stored = rawget(sweep, "_stored_attack_data")
        if rawget(sweep, "_send_delayed_hit_rpc") and (type(stored) ~= "table"
                or rawget(stored, "damage_profile_id") ~= record.row.id) then return "#428 queued Sweep ID unproven" end
    end
    return C
end
return new
