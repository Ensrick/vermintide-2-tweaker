local Runtime = {}

local function _safe_log(log, ...)
    if type(log) == "function" then
        pcall(log, ...)
    end
end

function Runtime.install(mod, dependencies)
    local policy = assert(dependencies.policy)
    local godmode_active = assert(dependencies.godmode_active)
    local is_authored_fly_blob = assert(
        dependencies.is_authored_fly_blob)
    local log = dependencies.log
    local seen_reasons = dependencies.seen_reasons or {}
    local blocked_blobs = dependencies.blocked_blobs
        or setmetatable({}, { __mode = "k" })

    local function status_wrapper(func, affected_unit, overpowered,
            overpowered_template_name, attacking_unit)
        local is_fly_reason = policy.is_fly_reason(
            overpowered_template_name)
        local is_authored_blob = is_fly_reason and overpowered == true
            and is_authored_fly_blob(attacking_unit, affected_unit)
        local godmode_on = is_authored_blob
            and godmode_active(affected_unit)

        if policy.should_block_entry(godmode_on, overpowered,
                overpowered_template_name, is_authored_blob) then
            blocked_blobs[attacking_unit] = affected_unit
            if not seen_reasons[overpowered_template_name] then
                seen_reasons[overpowered_template_name] = true
                _safe_log(log,
                    "[gt:548] blocked fly overpowered reason=%s godmode=true",
                    tostring(overpowered_template_name))
            end
            return
        end

        return func(affected_unit, overpowered, overpowered_template_name,
            attacking_unit)
    end

    local function destroy_wrapper(func, self)
        local blob_unit = self and self.unit
        local blocked_target = blob_unit and blocked_blobs[blob_unit]

        if blocked_target and self.target_unit == blocked_target then
            blocked_blobs[blob_unit] = nil
            return
        end

        return func(self)
    end

    mod:hook("StatusUtils", "set_overpowered_network", status_wrapper)
    mod:hook("OverpoweredBlobHealthExtension", "destroy", destroy_wrapper)
    _safe_log(log,
        "[gt:548] fly overpowered gate installed entry=true cleanup=true reasons=slow_bomb,fly_bomb")

    return {
        blocked_blobs = blocked_blobs,
        destroy_wrapper = destroy_wrapper,
        seen_reasons = seen_reasons,
        status_wrapper = status_wrapper,
    }
end

return Runtime
