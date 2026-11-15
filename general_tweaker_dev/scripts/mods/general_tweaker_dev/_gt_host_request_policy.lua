-- _gt_host_request_policy.lua - host opt-in for client-requested host actions.
--
-- WP-GT-01 (audit finding A6-F01). A peer running this mod could ask the host
-- to win, fail or restart the level, respawn it, honour its godmode, or spawn
-- or clear enemies, and the host did it for any sender. The host now refuses
-- unless it ticked "Allow Client Requests" (setting below, off by default), and
-- the two formerly unversioned requests carry SCHEMA as their first argument.
-- Pure: no engine calls. Loaded by _gt_level_control.lua.
local P = {}

P.SCHEMA = 1
P.SETTING = "gt_host_allow_client_requests"

function P.refuse(is_server, allow_setting, schema, expected_schema)
    if is_server ~= true then return true, "not_host" end
    if expected_schema ~= nil and schema ~= expected_schema then return true, "schema_mismatch" end
    if allow_setting ~= true then return true, "host_opt_in_off" end
    return false
end

function P.ignore_remote_godmode(is_server, allow_setting)
    return is_server == true and allow_setting ~= true
end

return P
