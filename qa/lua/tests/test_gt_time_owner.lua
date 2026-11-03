-- Actual General Dev factory, with private native/VMF boundary doubles only.
-- No .temp source dependency, live engine mutation or process termination.
return function(H, repo_root)
    H.test("GT time owner native state, cleanup, and freeze leases are exact", function()
        local M = assert(loadfile(repo_root .. "/general_tweaker_dev/scripts/mods/general_tweaker_dev/_gt_time_owner.lua"))()
        local count = 0
        local function check(value, message)
            H.truthy(value, message); count = count + 1
        end
        local function fixture(index, paused, selected)
            local f = {manager={}, setting=selected or index, allowed=true, is_host=true, in_realm=true,
                cleanup_allowed=true, writes=0, synchronized=0, local_only=0, setting_writes=0, notified=0, reports={}}
            f.state = {index=index, paused=paused or false, multiplier=paused and 1e-8 or M.multiplier(index)}
            local mod = {}
            function mod:get() return f.setting end
            function mod:set(_, value, notify)
                f.setting_writes=f.setting_writes+1; f.setting=value; f.last_notify=notify
                if notify then f.notified=f.notified+1 end
                if (notify or f.force_callback) and f.on_setting_changed then f.on_setting_changed() end
            end
            local api = {}
            function api.authorize() return f.allowed and f.is_host and f.in_realm, f.denial or "not_host" end
            function api.authorize_cleanup(manager)
                if not f.cleanup_allowed then return false, "cleanup_denied" end
                if manager ~= f.manager then return false, "manager_replaced" end
                return f.is_host and f.in_realm and "synchronized" or "local_only"
            end
            function api.manager_retired(manager) return f.retired_manager == manager end
            function api.read_native()
                if f.read_error then error("native snapshot unavailable") end
                return f.manager, f.state
            end
            local function write_native(manager, value, local_only)
                check(manager == f.manager, "setter exact manager")
                f.writes = f.writes + 1
                if local_only then f.local_only=f.local_only+1 else f.synchronized=f.synchronized+1 end
                if f.fail_before_at == f.writes then error("setter failed before mutation") end
                f.state.multiplier = M.multiplier(value)
                if f.fail_partial then
                    f.fail_partial=false
                    if f.unreadable_on_failure then f.read_error=true end
                    if f.lose_host_on_failure then f.is_host=false end
                    error("native RPC failed after multiplier")
                end
                if f.replace_on_write then f.replace_on_write=false; f.manager={}; error("replaced") end
                if f.foreign_on_write then f.foreign_on_write=false; f.state={index=7,paused=false,multiplier=0.123}; error("foreign") end
                f.state.index=value; f.state.paused=false
                if f.mapping_drift then f.state.multiplier=0.456 end
            end
            function api.write_native(manager, value) return write_native(manager, value, false) end
            function api.write_native_local(manager, value) return write_native(manager, value, true) end
            local function write_paused(manager, local_only)
                check(manager == f.manager, "pause exact manager")
                if local_only then f.local_only=f.local_only+1 else f.synchronized=f.synchronized+1 end
                f.writes=f.writes+1; f.state.multiplier=1e-8; f.state.paused=true
            end
            function api.write_paused(manager) return write_paused(manager, false) end
            function api.write_paused_local(manager) return write_paused(manager, true) end
            function api.diagnostic(key, detail) f.reports[#f.reports+1]={key=key,detail=detail} end
            f.api=api; f.mod=mod; f.owner=M.new(mod,api)
            return f
        end
        local rows=M.presets()
        check(#rows == 24 and rows[13].multiplier == 1 and rows[24].multiplier == 100, "native table")
        rows[13].multiplier=999
        check(M.multiplier(13) == 1 and M.presets()[13].multiplier == 1, "export cannot mutate policy")
        for _, invalid in ipairs({0,25,1.5,"13",false,math.huge,-math.huge,0/0}) do
            local f=fixture(13)
            local ok, reason=f.owner:apply(invalid)
            check(not ok and reason == "invalid_index" and f.writes == 0 and f.setting == 13, "invalid input rejected")
        end
        for _, malformed in ipairs({
            {index=0,paused=false,multiplier=1}, {index=0/0,paused=false,multiplier=1},
            {index=math.huge,paused=false,multiplier=1}, {index=13,paused=0,multiplier=1},
            {index=13,paused=false,multiplier=0/0}, {index=13,paused=false,multiplier=math.huge},
            {index=13,paused=false,multiplier=-math.huge}, {index=13,paused=false,multiplier=0}
        }) do
            local bad=fixture(13); bad.state=malformed
            local accepted, why=bad.owner:apply(14)
            check(not accepted and why == "invalid_native" and bad.writes == 0 and bad.setting == 13, "malformed native snapshot rejected")
        end
        local f=fixture(13)
        check(f.owner:release("never_engaged") and f.writes == 0, "idle cleanup performs no write")
        f.allowed=false
        check(not f.owner:apply(20) and f.writes == 0 and f.setting == 13, "client denied")
        f.denial="not_modded_realm"
        check(not f.owner:begin_freeze() and f.writes == 0, "realm denied")
        f.denial="player-facing text is not a reason key"
        local denied,denial=f.owner:apply(14)
        check(not denied and denial == "not_authorized" and f.writes == 0, "invalid adapter reason is normalized to machine key")
        f=fixture(13); f.state.multiplier=0.7
        local ok,reason=f.owner:apply(14)
        check(not ok and reason == "foreign_native_mapping" and f.writes == 0, "unowned foreign global not claimed")
        check(f.owner:release() and f.writes == 0, "foreign unengaged cleanup inert")
        f=fixture(8)
        check(f.owner:apply(20) and f.state.index == 20, "apply preset")
        check(f.owner:apply(17) and f.owner:release() and f.state.index == 8, "first prior remains baseline")
        f=fixture(9,true)
        check(f.owner:apply(19) and f.owner:release() and f.state.index == 9 and f.state.paused and f.state.multiplier == 1e-8, "paused baseline restored")
        f=fixture(13)
        check(f.owner:apply(18), "owned initial apply")
        f.state={index=6,paused=false,multiplier=M.multiplier(6)}
        local writes=f.writes
        ok,reason=f.owner:release()
        check(not ok and reason == "foreign_state" and f.writes == writes and f.state.index == 6, "foreign cleanup preserved")
        check(not f.owner:apply(14) and f.writes == writes, "foreign owner not stolen by apply")
        f=fixture(13); check(f.owner:apply(18), "replacement setup")
        f.manager={}; writes=f.writes
        ok,reason=f.owner:release()
        check(ok and reason == "manager_retired" and f.writes == writes, "replacement manager retires old ownership without writes")
        check(f.owner:apply(14) and f.state.index == 14, "retired ownership does not strand a new coherent manager")
        f=fixture(8); f.fail_partial=true
        ok,reason=f.owner:apply(20)
        check(not ok and reason == "write_error" and f.state.index == 8 and f.state.multiplier == M.multiplier(8), "partial RPC error rolls back owned multiplier")
        check(f.owner:release() and f.writes == 2, "successful rollback leaves idle cleanup")
        check(f.reports[1].key == "write_error", "write failure evidence retained")
        f=fixture(8); f.fail_partial=true; f.unreadable_on_failure=true
        ok,reason=f.owner:apply(20)
        check(not ok and reason == "write_error" and f.writes == 1, "unavailable post-write snapshot never claims applied or rolls back unknown state")
        check(f.reports[1].key == "write_error" and f.reports[1].detail.read_reason == "read_error", "original setter failure survives readback failure")
        f.read_error=false; writes=f.writes
        check(not f.owner:release() and f.writes == writes, "unobserved partial mutation remains evidence-only, not cleanup authority")
        f=fixture(8); f.mapping_drift=true
        ok,reason=f.owner:apply(20)
        check(not ok and reason == "write_mismatch" and f.state.multiplier == 0.456 and f.writes == 1, "changed native mapping never reports success or clobbers unknown state")
        f=fixture(8); f.foreign_on_write=true
        ok,reason=f.owner:apply(20)
        check(not ok and reason == "write_error" and f.writes == 1 and f.state.multiplier == 0.123, "throwing foreign mutation not rolled back")
        f=fixture(8); f.replace_on_write=true
        ok,reason=f.owner:apply(20)
        check(not ok and reason == "manager_replaced" and f.writes == 1, "throwing manager replacement not rolled back")
        f=fixture(8,false,19)
        local lease=f.owner:begin_freeze()
        check(type(lease) == "table" and f.state.index == 13 and f.setting == 19, "freeze holds real native speed, preserves selection")
        writes=f.writes
        check(f.owner:begin_freeze() == lease and f.writes == writes, "begin freeze idempotent exact lease")
        check(not f.owner:end_freeze({}) and f.writes == writes, "forged lease rejected")
        check(f.owner:end_freeze(lease) and f.state.index == 8, "unchanged freeze resumes pre-freeze effective index")
        writes=f.writes
        check(not f.owner:end_freeze(lease) and f.writes == writes, "repeated lease inert")
        check(f.owner:release() and f.state.index == 8, "freeze preserves original cleanup baseline")
        f=fixture(8,false,19); lease=f.owner:begin_freeze(); writes=f.writes
        check(f.owner:apply(21) and f.state.index == 13 and f.setting == 21 and f.writes == writes, "frozen edit remembers resume only")
        check(f.owner:slower() and f.setting == 20 and f.writes == writes, "frozen slower changes resume only")
        check(f.owner:end_freeze(lease) and f.state.index == 20, "end freeze resumes edited selection")
        check(f.owner:release() and f.state.index == 8, "edited freeze retains disable baseline")
        f=fixture(8,false,19); lease=f.owner:begin_freeze(); f.setting=22
        check(f.owner:end_freeze(lease) and f.state.index == 22, "direct setting change detected at lease end")
        f=fixture(8,false,19); lease=f.owner:begin_freeze(); f.fail_partial=true
        check(not f.owner:end_freeze(lease) and f.state.index == 13 and f.state.multiplier == 1, "failed resume rolls back native freeze hold")
        check(f.owner:begin_freeze() == lease and f.owner:end_freeze(lease), "failed resume retains retriable lease")
        f=fixture(8); lease=f.owner:begin_freeze(); f.fail_partial=true; f.fail_before_at=f.writes+2
        check(not f.owner:end_freeze(lease) and f.state.index == 13 and f.state.multiplier ~= 1, "failed rollback keeps exact known partial evidence")
        writes=f.writes
        ok,reason=f.owner:apply(19)
        check(not ok and reason == "freeze_hold_lost" and f.writes == writes, "edits cannot falsely report a lost native13 hold")
        local repeated,hold_reason=f.owner:begin_freeze()
        check(not repeated and hold_reason == "freeze_hold_lost" and f.writes == writes, "repeated begin cannot advertise lost hold")
        check(f.owner:end_freeze(lease) and f.state.index == 8, "exact lease can retry a known owned partial resume")
        f=fixture(8,false,19); lease=f.owner:begin_freeze()
        check(not f.owner:normal() and f.state.index == 13, "normal cannot silently abandon selective freeze")
        local stops=0
        function f.api.request_freeze_stop(exact, why)
            check(exact == lease and why == "normal", "normal requests exact selective-freeze teardown")
            stops=stops+1
            return f.owner:end_freeze(exact)
        end
        check(f.owner:normal() and f.state.index == 13 and f.setting == 13 and stops == 1, "normal stops freeze then sets normal")
        check(f.owner:release() and f.state.index == 8, "normal does not overwrite original cleanup baseline")
        f=fixture(8); lease=f.owner:begin_freeze()
        function f.api.request_freeze_stop(exact, why)
            check(exact == lease and why == "disabled", "release requests selective-freeze teardown")
            return f.owner:end_freeze(exact)
        end
        check(f.owner:release("disabled") and f.state.index == 8, "release unwinds active freeze then baseline")

        -- Cleanup authorization is intentionally distinct from active feature authority.
        f=fixture(8); check(f.owner:apply(20), "disabled cleanup setup")
        f.allowed=false; f.denial="disabled"; writes=f.writes
        check(not f.owner:apply(19) and f.writes == writes, "disabled host cannot make active writes")
        check(f.owner:release("disabled") and f.state.index == 8 and f.synchronized == 2 and f.local_only == 0, "disabled current host restores owned baseline through explicit cleanup policy")
        f=fixture(8); check(f.owner:apply(20), "realm cleanup setup")
        f.in_realm=false
        check(f.owner:release("realm_changed") and f.state.index == 8 and f.synchronized == 1 and f.local_only == 1, "realm loss restores only local owned baseline")
        f=fixture(9,true); check(f.owner:apply(20), "host-loss paused cleanup setup")
        f.is_host=false; writes=f.synchronized
        check(f.owner:release("host_lost") and f.state.index == 9 and f.state.paused and f.state.multiplier == 1e-8, "host loss restores exact paused baseline locally")
        check(f.synchronized == writes and f.local_only == 2, "local cleanup never falls back to broadcasting pause setter")
        f=fixture(8); check(f.owner:apply(20), "missing local route setup")
        f.is_host=false; f.api.write_native_local=nil; writes=f.writes
        ok,reason=f.owner:release("host_lost")
        check(not ok and reason == "cleanup_local_unavailable" and f.writes == writes and f.synchronized == 1, "missing local callback cannot fall back to active setter")
        f=fixture(8); check(f.owner:apply(20), "denied cleanup setup")
        f.allowed=false; f.cleanup_allowed=false; writes=f.writes
        ok,reason=f.owner:release("disabled")
        check(not ok and reason == "cleanup_denied" and f.writes == writes, "cleanup policy denial retains exact owned state without writes")
        f.cleanup_allowed=true
        check(f.owner:release("retry") and f.state.index == 8, "denied cleanup remains safely retryable")
        f=fixture(8); lease=f.owner:begin_freeze(); check(f.owner:apply(22), "host-loss edited freeze setup")
        f.is_host=false; writes=f.synchronized
        check(f.owner:end_freeze(lease) and f.state.index == 8 and f.setting == 22 and f.synchronized == writes, "authority-lost End restores original baseline, not pending edited speed")
        writes=f.writes
        check(f.owner:release("after_end") and f.writes == writes, "authority-loss End retires restored ownership")
        f=fixture(8); lease=f.owner:begin_freeze(); check(f.owner:apply(22), "disabled release freeze setup")
        f.allowed=false
        function f.api.request_freeze_stop(exact, why)
            check(exact == lease and why == "disabled", "disabled release stops exact selective world lease")
            return f.owner:end_freeze(exact)
        end
        writes=f.writes
        check(f.owner:release("disabled") and f.state.index == 8 and f.writes == writes+1, "release context restores baseline directly without transient edited resume")
        f=fixture(8); lease=f.owner:begin_freeze(); f.manager={}; writes=f.writes
        check(f.owner:end_freeze(lease) and f.writes == writes, "replaced-manager End retires exact lease without native writes")
        check(not f.owner:end_freeze(lease) and f.writes == writes, "retired lease cannot be reused")
        f=fixture(8); lease=f.owner:begin_freeze(); f.manager={}; writes=f.writes
        function f.api.request_freeze_stop(exact) return f.owner:end_freeze(exact) end
        ok,reason=f.owner:release("replaced")
        check(ok and reason == "manager_retired" and f.writes == writes, "release reports retirement, not restoration, when stop callback retires a replaced manager")
        f=fixture(8); check(f.owner:apply(20), "malformed replacement setup")
        f.manager={}; f.state={index=0,paused=false,multiplier=0/0}; writes=f.writes
        ok,reason=f.owner:release("replaced")
        check(ok and reason == "manager_retired" and f.writes == writes, "different current identity proves retirement even with malformed replacement state")
        f=fixture(8); check(f.owner:apply(20), "destroyed manager setup")
        local old_manager=f.manager; f.manager=nil; f.retired_manager=old_manager; writes=f.writes
        check(f.owner:release("destroyed") and f.writes == writes, "explicit destroyed-manager proof retires without writes")
        f=fixture(8); check(f.owner:apply(20), "unavailable manager setup")
        old_manager=f.manager; f.manager=nil; writes=f.writes
        ok,reason=f.owner:release("missing")
        check(not ok and reason == "missing_native" and f.writes == writes, "missing current manager alone is not destruction proof")
        f.manager=old_manager
        check(f.owner:release("available_again") and f.state.index == 8, "unproven missing-manager cleanup retains retryable evidence")
        f=fixture(8); check(f.owner:apply(20), "read-error cleanup setup")
        f.read_error=true; writes=f.writes
        check(not f.owner:release("read_error") and f.writes == writes, "read failure alone grants no cleanup write or retirement")
        f.read_error=false
        check(f.owner:release("read_ok") and f.state.index == 8, "read-error cleanup can retry")
        f=fixture(8); f.fail_partial=true; f.lose_host_on_failure=true
        ok,reason=f.owner:apply(20)
        check(not ok and reason == "write_error" and f.state.index == 8 and f.state.multiplier == M.multiplier(8), "host loss during partial setter failure still rolls back exact owned attempt")
        check(f.synchronized == 1 and f.local_only == 1, "host-loss rollback uses local-only route")
        f=fixture(8); check(f.owner:apply(20), "cleanup partial-error setup")
        f.allowed=false; f.fail_partial=true
        ok,reason=f.owner:release("disabled")
        check(not ok and reason == "write_error" and f.state.index == 20 and f.state.multiplier == M.multiplier(20), "partial cleanup error rolls back owned attempt without losing original baseline")
        check(f.owner:release("retry") and f.state.index == 8, "failed cleanup retains retriable original baseline")

        -- Match VMF's notify_mod flag and reject a misbehaving adapter's recursion.
        f=fixture(8)
        local callbacks=0
        function f.on_setting_changed()
            callbacks=callbacks+1
            f.callback_ok,f.callback_reason=f.owner:apply_selected()
        end
        check(f.owner:apply(20) and f.last_notify == false and f.notified == 0 and callbacks == 0, "explicit selection persistence suppresses VMF notification")
        local persisted=f.setting_writes; writes=f.writes
        check(f.owner:apply_selected() and f.setting_writes == persisted and f.writes == writes, "already-equal setting causes no redundant persistence or native write")
        f.force_callback=true
        check(f.owner:apply(21) and callbacks == 1 and f.callback_ok == false and f.callback_reason == "selection_reentrant", "synchronous recursive selection callback fails closed")
        check(f.state.index == 21 and f.setting == 21, "outer explicit selection remains single owner after recursion refusal")
        f.force_callback=false
        f.mod:set("time_scale_value",22,true)
        check(callbacks == 2 and f.callback_ok and f.state.index == 22 and f.notified == 1, "real VMF-style external notification applies selection without recursive persistence")
        f=fixture(24); check(f.owner:faster() and f.setting == 24, "upper bound")
        f=fixture(1); check(f.owner:slower() and f.setting == 1, "lower bound")
        f=fixture(8); check(f.owner:apply(20), "resync ownership setup")
        writes=f.writes
        check(f.owner:resync() and f.writes == writes+1 and f.state.index == 20, "owned same-index post-join replay forces exactly one native write")
        writes=f.writes
        check(f.owner:apply_selected() and f.writes == writes, "ordinary same-index apply remains deduplicated")
        f.is_host=false
        check(not f.owner:resync() and f.writes == writes, "client cannot replay owned speed")
        f=fixture(13)
        ok,reason=f.owner:resync()
        check(not ok and reason == "ownership_missing" and f.writes == 0, "resync cannot claim unowned default state")
        f=fixture(8); check(f.owner:apply(20), "foreign resync setup")
        f.state={index=6,paused=false,multiplier=M.multiplier(6)}; writes=f.writes
        ok,reason=f.owner:resync()
        check(not ok and reason == "foreign_state" and f.writes == writes, "post-join replay preserves foreign time state")
        f=fixture(8); check(f.owner:apply(20), "replaced resync setup")
        f.manager={}; writes=f.writes
        ok,reason=f.owner:resync()
        check(not ok and reason == "manager_replaced" and f.writes == writes, "post-join replay rejects a replacement manager")
        f=fixture(8); check(f.owner:apply(20), "selection mismatch resync setup")
        f.setting=19; writes=f.writes
        ok,reason=f.owner:resync()
        check(not ok and reason == "resync_selection_mismatch" and f.writes == writes, "replay never applies an uncommitted different selection")
        f=fixture(8); lease=f.owner:begin_freeze(); writes=f.writes
        ok,reason=f.owner:resync()
        check(not ok and reason == "freeze_active" and f.writes == writes, "post-join replay is forbidden during selective freeze")
        f=fixture(8); check(f.owner:apply(20), "throwing resync setup")
        f.fail_partial=true; writes=f.writes
        ok,reason=f.owner:resync()
        check(not ok and reason == "write_error" and f.writes == writes+1 and f.state.index == 20 and f.state.multiplier == M.multiplier(20), "throwing same-index replay reports failure without a second broadcast")
        check(f.reports[1].key == "write_error", "post-join throwing replay retains native failure evidence")
        f=fixture(8); check(f.owner:apply(20), "changed native mapping resync setup")
        f.mapping_drift=true; writes=f.writes
        ok,reason=f.owner:resync()
        check(not ok and reason == "write_mismatch" and f.writes == writes+1 and f.state.multiplier == 0.456, "replay checks post-write mapping and does not overwrite unknown result")
        f=fixture(8); check(f.owner:apply(20), "post-write replacement resync setup")
        f.replace_on_write=true; writes=f.writes
        ok,reason=f.owner:resync()
        check(not ok and reason == "manager_replaced" and f.writes == writes+1, "replay checks post-write manager identity without touching replacement")
        H.equal(count, 207, "all native time owner behavioral assertions executed")
    end)
end
