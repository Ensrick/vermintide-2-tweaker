-- Focused Spirit (#472): pure presentation/authority policy plus one bounded,
-- edge-driven setting-consensus transport. The transport never polls or sends
-- per frame: it announces only when exact CRT parity becomes available, when
-- the local stacking setting changes, or as one reply to a valid announcement.
local M = {
    CHANNEL = "crt_focused_spirit_config",
    SCHEMA = 1,
    MAX_GENERATION = 1000000,
    VANILLA_DESCRIPTION_KEY = "kerillian_maidenguard_power_level_on_unharmed_desc",
}

local STACKING_TEXT =
    "Focused Spirit starts with no stacks. Every 10 seconds without taking an ordinary hit grants 5% power, up to 5 stacks (25%). An ordinary hit removes one stack and restarts the timer."
-- Chip-only mode retains the authored description_values, so UIUtils still
-- calls string.format after Localize. Its literal percent must remain escaped.
-- Stacking mode clears description_values and returns Localize text directly,
-- so STACKING_TEXT and the appended clause intentionally use single percents.
local IGNORE_TEXT =
    "Increases Power by 15%% after not taking ordinary damage for 10 seconds. Damage-over-time, poison gas, Warpfire Throwers, Ratling Gunners, Unquenchable Thirst, and Nurgle's Rot do not reset Focused Spirit."
local STACKING_IGNORE_TEXT = STACKING_TEXT
    .. " Damage-over-time, poison gas, Warpfire Throwers, Ratling Gunners, Unquenchable Thirst, and Nurgle's Rot do not remove stacks or restart the timer."

function M.description(stacking_enabled, ignore_enabled)
    if stacking_enabled and ignore_enabled then return STACKING_IGNORE_TEXT end
    if stacking_enabled then return STACKING_TEXT end
    if ignore_enabled then return IGNORE_TEXT end
    return nil
end

-- Vanilla installs this buffer="both" talent on the owning client and server
-- (TalentExtension.apply_buffs_from_talents), but not on ordinary observers.
-- One human owner therefore decides/schedules; the server copy mirrors stack
-- removal. Bots have no owning client and remain server-authored.
function M.transition_role(player, is_server)
    if type(player) ~= "table" then return "none" end
    if player.bot_player == true then
        return is_server == true and "writer" or "none"
    end
    if player.local_player == true then return "writer" end
    if is_server == true then return "mirror" end
    return "none"
end

function M.growth_action(role, rework_live, stack_count)
    if rework_live ~= true or role ~= "writer" then return "preserve" end
    if type(stack_count) ~= "number" or stack_count < 0 or stack_count >= 5 then
        return "preserve"
    end
    return "rearm"
end

function M.damage_action(input)
    if type(input) ~= "table" then return "preserve" end
    if input.ignored == true then return "ignored_preserve" end
    if input.rework_live ~= true then return "delegate_vanilla" end
    if input.attacker_self == true or input.damage_amount == 0 then
        return "self_or_zero_preserve"
    end
    if input.handled == true then return "duplicate_proc_preserve" end
    if input.role == "writer" then return "remove_one_restart" end
    if input.role == "mirror" then return "remove_one_mirror" end
    return "no_authority_preserve"
end

function M.zero_stack_action(input)
    if type(input) ~= "table" or input.rework_live ~= true
            or input.role ~= "writer" or input.ignored == true
            or input.attacker_self == true or input.damage_amount == 0
            or input.stack_count ~= 0 then
        return "preserve"
    end
    return "restart"
end

local function safe_wire_string(value)
    return type(value) == "string" and value ~= "" and #value <= 64
        and value:match("^[%w_.:%-]+$") ~= nil
end

local function default_other_peers()
    local out = {}
    local managers = rawget(_G, "Managers")
    local pm = managers and managers.player
    if not (pm and type(pm.human_players) == "function") then return out, false end
    local ok_humans, humans = pcall(pm.human_players, pm)
    if not ok_humans or type(humans) ~= "table" then return out, false end
    local network = rawget(_G, "Network")
    local ok_me, me = pcall(function()
        return network and type(network.peer_id) == "function" and network.peer_id()
    end)
    if not ok_me then me = nil end
    for _, player in pairs(humans) do
        local peer_id = player and player.peer_id
        if type(peer_id) == "string" and peer_id ~= me then out[peer_id] = true end
    end
    return out, true
end

function M.consensus_matches(local_config, peers, roster_known, remote_states)
    if type(local_config) ~= "table"
            or type(local_config.stacking) ~= "boolean"
            or type(local_config.ignore_chip) ~= "boolean"
            or roster_known ~= true or type(peers) ~= "table"
            or type(remote_states) ~= "table" then
        return false
    end
    for peer_id in pairs(peers) do
        local state = remote_states[peer_id]
        if type(state) ~= "table" or state.conflict == true
                or state.stacking ~= local_config.stacking
                or state.ignore_chip ~= local_config.ignore_chip then
            return false
        end
    end
    return true
end

function M.new_consensus(mod, base_parity, opts)
    opts = opts or {}
    local channel = opts.channel or M.CHANNEL
    local schema = opts.schema or M.SCHEMA
    local epoch = opts.epoch or (base_parity and base_parity.LOCAL_EPOCH)
    local config_reader = opts.config or function()
        return { stacking = false, ignore_chip = false }
    end
    local other_peers = opts.other_peers or default_other_peers
    local on_remote_change = opts.on_remote_change
    local states = {}
    local generation = 1
    local installed = false
    local install_attempted = false

    local api = {
        CHANNEL = channel,
        SCHEMA = schema,
        LOCAL_EPOCH = epoch,
    }

    local function local_config()
        local ok, value = pcall(config_reader)
        if not ok or type(value) ~= "table"
                or type(value.stacking) ~= "boolean"
                or type(value.ignore_chip) ~= "boolean" then
            return nil
        end
        return {
            stacking = value.stacking == true,
            ignore_chip = value.ignore_chip == true,
        }
    end

    local function base_live()
        if type(base_parity) ~= "table"
                or type(base_parity.all_peers_have) ~= "function" then
            return false
        end
        local ok, value = pcall(base_parity.all_peers_have, base_parity)
        return ok and value == true
    end

    local function send(recipient, is_reply)
        if not installed or not base_live() or not safe_wire_string(epoch)
                or not (mod and type(mod.network_send) == "function") then
            return false
        end
        local config = local_config()
        if not config then return false end
        local ok, result = pcall(mod.network_send, mod, channel, recipient or "others",
            schema, is_reply and 1 or 0, epoch, generation,
            config.stacking and 1 or 0, config.ignore_chip and 1 or 0)
        return ok and result ~= false
    end

    function api:all_match()
        if not installed or not base_live() then return false end
        local ok, peers, known = pcall(other_peers)
        if not ok then return false end
        return M.consensus_matches(local_config(), peers, known, states)
    end

    function api:announce()
        return send("others", false)
    end

    function api:set_local_changed()
        generation = generation + 1
        if generation > M.MAX_GENERATION then generation = 1 end
        return self:announce()
    end

    function api:forget_peer(peer_id)
        if type(peer_id) == "string" and states[peer_id] ~= nil then
            states[peer_id] = nil
            if type(on_remote_change) == "function" then pcall(on_remote_change) end
        end
    end

    function api:invalidate()
        states = {}
    end

    function api:state_for(peer_id)
        return states[peer_id]
    end

    function api:generation()
        return generation
    end

    function api:is_installed()
        return installed
    end

    function api:install()
        if installed then return true end
        if install_attempted then return false end
        install_attempted = true
        if not safe_wire_string(epoch) or not (mod and type(mod.network_register) == "function") then
            return false
        end

        local receiver = function(sender_peer_id, remote_schema, is_reply,
                remote_epoch, remote_generation, remote_stacking, remote_ignore_chip)
            if not installed or remote_schema ~= schema
                    or type(sender_peer_id) ~= "string"
                    or not safe_wire_string(remote_epoch)
                    or type(remote_generation) ~= "number"
                    or remote_generation % 1 ~= 0
                    or remote_generation < 1
                    or remote_generation > M.MAX_GENERATION
                    or (remote_stacking ~= 0 and remote_stacking ~= 1)
                    or (remote_ignore_chip ~= 0 and remote_ignore_chip ~= 1)
                    or (is_reply ~= 0 and is_reply ~= 1) then
                return
            end
            if type(base_parity) ~= "table" or type(base_parity.peer_has) ~= "function" then
                return
            end
            local ok_peer, peer_has = pcall(base_parity.peer_has, base_parity, sender_peer_id)
            if not ok_peer or peer_has ~= true then
                return
            end

            local previous = states[sender_peer_id]
            -- A different process epoch cannot replace a live epoch. A real
            -- PlayerManager.remove_player edge calls forget_peer first; until
            -- then, ambiguity fails closed rather than accepting delayed data.
            if previous and previous.epoch ~= remote_epoch then
                previous.conflict = true
                if type(on_remote_change) == "function" then pcall(on_remote_change) end
                return
            end
            if previous and remote_generation < previous.generation then return end

            local stacking = remote_stacking == 1
            local ignore_chip = remote_ignore_chip == 1
            if previous and remote_generation == previous.generation
                    and (previous.conflict == true
                        or previous.stacking ~= stacking
                        or previous.ignore_chip ~= ignore_chip) then
                if previous.conflict ~= true then
                    previous.conflict = true
                    if type(on_remote_change) == "function" then pcall(on_remote_change) end
                end
                return
            end

            local changed = not previous
                or previous.generation ~= remote_generation
                or previous.stacking ~= stacking
                or previous.ignore_chip ~= ignore_chip
                or previous.conflict == true
            states[sender_peer_id] = {
                epoch = remote_epoch,
                generation = remote_generation,
                stacking = stacking,
                ignore_chip = ignore_chip,
                conflict = false,
            }
            if changed and type(on_remote_change) == "function" then
                pcall(on_remote_change)
            end
            if is_reply == 0 then send(sender_peer_id, true) end
        end

        local ok, result = pcall(mod.network_register, mod, channel, receiver)
        if not ok or result == false then return false end
        installed = true
        return true
    end

    return api
end

return M
