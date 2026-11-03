return function(H, repo_root)
    local function fixture(stream)
        local hooks, seen, events = {}, {}, {}
        local mod = {}
        function mod:hook(class, name, callback)
            local key = class .. "." .. name
            H.equal(seen[key], nil, "singleton " .. key)
            seen[key], hooks[key] = true, callback
        end
        mod._gt_time_outer_dt = function(state, phase, dt)
            events[#events + 1] = phase
            return state.frozen and 1e-6 or dt
        end
        mod._gt_time_entity_phase = function(_, phase)
            events[#events + 1] = phase
            return mod.handled == true
        end
        mod._gt_time_before_hotjoin = function() events[#events + 1] = "release" end
        mod._gt_time_after_hotjoin = function() events[#events + 1] = "resync" end
        mod._gt_time_disable = function(reason) events[#events + 1] = reason end
        local file = stream .. "/scripts/mods/" .. stream .. "/_gt_time_hooks.lua"
        local chunk = assert(loadfile(repo_root .. "/" .. file))
        setfenv(chunk, setmetatable({ get_mod = function() return mod end }, { __index = _G }))
        chunk()
        return mod, hooks, events
    end
    local function capture(...) return {n=select("#", ...), ...} end
    for _, stream in ipairs({"general_tweaker_dev", "general_tweaker"}) do
        H.test(stream .. " actual manifest provides realm and factories before control", function()
            local root=repo_root .. "/" .. stream .. "/scripts/mods/" .. stream .. "/"
            local file=assert(io.open(root .. stream .. ".lua","rb"))
            local source=file:read("*a"); file:close()
            local prefix='mod:dofile("scripts/mods/' .. stream .. '/'
            local first=assert(source:find(prefix .. '_gt_level_control")',1,true))
            local last=assert(source:find(prefix .. '_gt_hacks")',first,true))
            local snippet=source:sub(first,last+#(prefix .. '_gt_hacks")')-1)
            local realm, mod, names = {}, {}, {}
            function mod:dofile(path)
                names[#names+1]=path
                if path:find("_lib_modded_realm_authority",1,true) then return realm end
                if path:find("_gt_level_control",1,true) and stream=="general_tweaker_dev" then
                    self._gt_modded_realm_authority=realm
                end
                if path:find("_gt_time_control",1,true) then
                    H.equal(self._gt_modded_realm_authority,realm,"runtime realm dependency")
                    for _, key in ipairs({"Owner","Freeze","Driver","Context"}) do
                        H.equal(type(self._gt_time_modules[key]),"table",key)
                    end
                end
                return {}
            end
            local chunk=assert(loadstring(snippet,"@gt_actual_time_manifest"))
            setfenv(chunk,{mod=mod}); chunk()
            H.truthy(names[#names]:find("_gt_hacks",1,true))
        end)
        H.test(stream .. " time phases preserve native values and nil holes", function()
            local mod, hooks, events = fixture(stream)
            local state = {frozen=true}
            for _, phase in ipairs({"pre_update", "post_update"}) do
                local result = capture(hooks["StateIngame." .. phase](function(self, dt, value)
                    H.equal(self, state); H.equal(dt, 1e-6); H.equal(value, "arg")
                    return "transition", nil, 7
                end, state, .02, "arg"))
                H.equal(result.n, 3); H.equal(result[1], "transition"); H.equal(result[3], 7)
            end
            local after = false
            local result = capture(mod._gt_time_state_update(function(self, dt)
                H.equal(self, state); H.equal(dt, 1e-6)
                H.equal(after, false)
                return "change_state", nil, "payload"
            end, state, .02, function() after=true end))
            H.equal(after, true); H.equal(result.n, 3)
            H.equal(result[1], "change_state"); H.equal(result[3], "payload")
            H.equal(events[3], "update")
        end)
        H.test(stream .. " ordinary phase dt passes through without ownership", function()
            local _, hooks = fixture(stream)
            local calls=0
            hooks["StateIngame.pre_update"](function(_, dt)
                calls=calls+1; H.equal(dt, .04)
            end, {frozen=false}, .04)
            H.equal(calls, 1)
        end)
        H.test(stream .. " entity movement is exclusive only when handled", function()
            local mod, hooks = fixture(stream)
            local fn=hooks["EntitySystem.system_update"]
            local calls=0
            local native=function(_, phase, dt, arg)
                calls=calls+1; H.equal(phase,"update"); H.equal(dt,.02); H.equal(arg,9)
                return nil, "native"
            end
            local result=capture(fn(native, {}, "update", .02, 9))
            H.equal(calls,1); H.equal(result.n,2); H.equal(result[2],"native")
            mod.handled=true
            fn(native, {}, "update", .02, 9)
            H.equal(calls,1)
        end)
        H.test(stream .. " releases before joining and resyncs after native returns", function()
            local mod, hooks, events=fixture(stream)
            local result=capture(hooks["GameNetworkManager.hot_join_sync"](function(_, peer)
                H.equal(peer,"peer"); H.equal(events[1],"release")
                events[#events+1]="native"
                return false,nil,"retained"
            end,{},"peer"))
            H.equal(table.concat(events,","),"release,native,resync")
            H.equal(result.n,3); H.equal(result[1],false); H.equal(result[3],"retained")
            mod.on_unload()
            H.equal(events[4],"mod_unload")
        end)
    end
end
