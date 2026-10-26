-- External #942 pure protocol candidate. No VMF hooks/registration, engine
-- globals, clocks, random generator or settings writes. The eventual adapter
-- must provide authenticated peers including the pre-roster join fence.
local M = {}
M.SCHEMA = 1
M.MAX_PEERS, M.MAX_RETIRED_PEERS, M.MAX_RETIRED_EPOCHS = 32, 32, 8
M.MAX_QUERY_EPOCHS, M.MAX_EPOCH, M.MAX_PEER_ID = 8, 24, 64
M.MAX_GENERATION, M.MAX_CHALLENGE = 1000000000, 1000000000
M.MAX_ATTEMPTS, M.RETRY_INTERVAL, M.RETRY_COOLDOWN = 3, 1, 5
M.HANDSHAKE_TTL, M.PROOF_TTL, M.REFRESH_AFTER, M.ABSENCE_GRACE = 10, 30, 20, 10
M.BURST, M.SEND_RATE, M.MAX_JSON = 6, 2, 500
local TWO53 = 9007199254740992
local function finite(x)
    return type(x) == "number" and x == x and x ~= math.huge and x ~= -math.huge
end
local function integer(x, min, max)
    return finite(x) and x >= min and x <= max and x == math.floor(x)
end
local function safe(s, maximum)
    return type(s) == "string" and #s > 0 and #s <= maximum
        and s:match("^[%w_.:%-]+$") ~= nil
end
local function copy(t)
    local out = {}; for k, v in pairs(t) do out[k] = v end; return out
end

-- Exact binary64 representation, not a collision-only digest or locale-
-- dependent decimal serialization. +/-0 intentionally normalize together:
-- all three nonnegative policy inputs have identical effect at either zero.
local function number_token(value)
    if not finite(value) or value < 0 then return nil end
    if value == 0 then return "0" end
    local mantissa, exponent = math.frexp(value)
    return string.format("%.0f", mantissa * TWO53) .. "e" .. string.format("%d", exponent)
end
local function token_number(token)
    if token == "0" then return 0 end
    if type(token) ~= "string" or #token > 24 then return nil end
    local digits, power = token:match("^(%d+)e(%-?%d+)$")
    if not digits or #digits ~= 16 or #power > 5 then return nil end
    local mantissa, exponent = tonumber(digits), tonumber(power)
    if not integer(mantissa, TWO53/2, TWO53-1)
            or not integer(exponent, -1073, 1024) then return nil end
    local value = math.ldexp(mantissa/TWO53, exponent)
    if number_token(value) ~= token then return nil end
    return value
end
M.number_token, M.token_number = number_token, token_number

function M.canonicalize(config)
    if type(config) ~= "table" or getmetatable(config) ~= nil then return nil end
    local count = 0
    for key in pairs(config) do
        if key ~= "enabled" and key ~= "armor" and key ~= "cleave"
                and key ~= "damage" and key ~= "threshold" then return nil end
        count = count + 1
    end
    if count ~= 5 or type(config.enabled) ~= "boolean" or type(config.armor) ~= "boolean"
            or not finite(config.cleave) or config.cleave < 0 or config.cleave > .1
            or not finite(config.damage) or config.damage < 0 or config.damage > .1
            or not finite(config.threshold) or config.threshold < 0 or config.threshold > 100 then return nil end
    local tuple = { config.enabled and 1 or 0, config.armor and 1 or 0,
        number_token(config.cleave), number_token(config.damage), number_token(config.threshold) }
    return tuple, table.concat(tuple, "|")
end
local function tuple_from_packet(packet)
    if not integer(packet[9],0,1) or not integer(packet[10],0,1) then return nil end
    local a,b,c = token_number(packet[11]),token_number(packet[12]),token_number(packet[13])
    if not a or a > .1 or not b or b > .1 or not c or c > 100 then return nil end
    return {packet[9],packet[10],packet[11],packet[12],packet[13]},
        table.concat({packet[9],packet[10],packet[11],packet[12],packet[13]},"|")
end
local function nonce(value)
    if type(value) ~= "string" or #value > 11 then return nil end
    local digits = value:match("^c(%d+)$")
    local n = digits and tonumber(digits)
    if not integer(n,1,M.MAX_CHALLENGE) or "c"..string.format("%.0f",n) ~= value then return nil end
    return n
end
function M.validate_packet(packet)
    if type(packet) ~= "table" or getmetatable(packet) ~= nil then return nil end
    local count=0
    for key in pairs(packet) do
        if not integer(key,1,13) then return nil end
        count=count+1
    end
    if count ~= 13 or packet[1] ~= M.SCHEMA
            or (packet[2] ~= "q" and packet[2] ~= "r" and packet[2] ~= "a")
            or not safe(packet[3],M.MAX_EPOCH)
            or not integer(packet[4],1,M.MAX_GENERATION) then return nil end
    if packet[2] == "q" then
        if packet[5] ~= "" or packet[6] ~= 0 or not nonce(packet[7]) or packet[8] ~= "" then return nil end
    else
        if not safe(packet[5],M.MAX_EPOCH) or not integer(packet[6],1,M.MAX_GENERATION)
                or not nonce(packet[8]) then return nil end
        if packet[2] == "r" and not nonce(packet[7])
                or packet[2] == "a" and packet[7] ~= "" then return nil end
    end
    local tuple,key=tuple_from_packet(packet)
    if not tuple then return nil end
    -- Exact JSON length for the restricted string alphabet (no escaping).
    local length=14
    for i=1,13 do
        local value=packet[i]
        length=length+(type(value)=="string" and #value+2 or #string.format("%.0f",value))
    end
    if length > M.MAX_JSON then return nil end
    return tuple,key,length
end

function M.new(deps)
    assert(type(deps)=="table" and safe(deps.epoch,M.MAX_EPOCH),"#942 unique session epoch missing")
    for _,name in ipairs({"read_config","read_peers","send","changed"}) do
        assert(type(deps[name])=="function","#942 "..name.." dependency missing")
    end
    assert(deps.initial_generation==nil or integer(deps.initial_generation,0,M.MAX_GENERATION),"#942 initial generation invalid")
    assert(deps.initial_counter==nil or integer(deps.initial_counter,0,M.MAX_CHALLENGE),"#942 initial counter invalid")
    local api={}
    local s={epoch=deps.epoch,generation=deps.initial_generation or 0,counter=deps.initial_counter or 0,clock=0,healthy=false,
        peers={},retired={},retired_order={},applied=false,fatal=false,busy=false}
    local function retired(peer,epoch)
        return s.retired[peer] and s.retired[peer].set[epoch] == true
    end
    local function retire(peer,epoch)
        if not epoch then return end
        local row=s.retired[peer]
        if not row then
            row={set={},order={}};s.retired[peer]=row;s.retired_order[#s.retired_order+1]=peer
            if #s.retired_order>M.MAX_RETIRED_PEERS then
                s.retired[table.remove(s.retired_order,1)]=nil
            end
        end
        if row.set[epoch] then return end
        row.set[epoch]=true;row.order[#row.order+1]=epoch
        if #row.order>M.MAX_RETIRED_EPOCHS then row.set[table.remove(row.order,1)]=nil end
    end
    local function clear_proofs()
        for _,p in pairs(s.peers) do
            p.proof,p.query,p.response,p.ack,p.accepted=nil,nil,nil,nil,nil
        end
    end
    local function desired()
        if not s.healthy or s.fatal then return false end
        for _,p in pairs(s.peers) do
            local proof=p.proof
            if not proof or proof.local_gen~=s.generation or proof.key~=s.key
                    or proof.remote_epoch~=p.epoch or proof.remote_gen~=p.maximum_gen
                    or s.clock>=proof.expires then return false end
        end
        return true
    end
    local function publish()
        local next_state=desired()
        if next_state==s.applied then return end
        s.applied=next_state -- #506: visible before the callback
        local ok=pcall(deps.changed,next_state,api)
        if not ok then s.fatal=true;s.applied=false;clear_proofs() end
    end
    local function advance()
        if s.generation>=M.MAX_GENERATION then s.fatal=true;return false end
        s.generation=s.generation+1;clear_proofs();return true
    end
    local function clock(now)
        if not finite(now) or now<0 or now<s.clock then
            s.healthy=false;s.key=nil;clear_proofs();publish();return false
        end
        s.clock=now;return true
    end
    local function refresh(now)
        if not clock(now) or s.fatal then return false end
        local ok,config,peers,known=pcall(function()
            local value=deps.read_config();local roster,ready=deps.read_peers()
            return value,roster,ready
        end)
        local tuple,key
        if ok then tuple,key=M.canonicalize(config) end
        local count=0
        if type(peers)=="table" and getmetatable(peers)==nil then
            for peer,value in pairs(peers) do
                if not safe(peer,M.MAX_PEER_ID) or value~=true then known=false;break end
                count=count+1
            end
        else known=false end
        if not ok or not tuple or known~=true or count>M.MAX_PEERS then
            if s.healthy then advance() end
            s.healthy=false;s.key=nil;clear_proofs();publish();return false
        end
        if s.key~=key or not s.healthy then
            if not advance() then publish();return false end
            s.key,s.tuple=key,tuple
        end
        s.healthy=true
        for peer,p in pairs(s.peers) do
            if not peers[peer] then
                p.absent_since=p.absent_since or s.clock
                if s.clock-p.absent_since>=M.ABSENCE_GRACE then
                    -- Absence is not an authenticated disconnect: expire proof
                    -- but allow the same live session to prove a fresh nonce.
                    s.peers[peer]=nil
                end
            else p.absent_since=nil end
        end
        local retained=0;for _ in pairs(s.peers) do retained=retained+1 end
        for peer in pairs(peers) do
            if not s.peers[peer] then
                if retained>=M.MAX_PEERS then
                    s.healthy=false;clear_proofs();publish();return false
                end
                s.peers[peer]={tokens=M.BURST,budget_at=s.clock,query_max={},query_epochs={},retry_at=0}
                retained=retained+1
            end
        end
        publish();return s.healthy
    end
    local function challenge()
        if s.counter>=M.MAX_CHALLENGE then s.fatal=true;clear_proofs();publish();return nil end
        s.counter=s.counter+1;return "c"..string.format("%.0f",s.counter)
    end
    local function packet(kind,target_epoch,target_gen,query,echo)
        return {M.SCHEMA,kind,s.epoch,s.generation,target_epoch,target_gen,query,echo,
            s.tuple[1],s.tuple[2],s.tuple[3],s.tuple[4],s.tuple[5]}
    end
    local function emit(peer,p,record)
        if record.attempts>=M.MAX_ATTEMPTS or s.clock<record.due
                or s.clock-record.created>M.HANDSHAKE_TTL then return false end
        p.tokens=math.min(M.BURST,p.tokens+(s.clock-p.budget_at)*M.SEND_RATE)
        p.budget_at=s.clock;record.due=s.clock+M.RETRY_INTERVAL
        if p.tokens<1 then return false end
        p.tokens=p.tokens-1;record.attempts=record.attempts+1
        assert(M.validate_packet(record.packet),"#942 internal packet contract failed")
        local ok=pcall(deps.send,peer,copy(record.packet))
        if not ok then p.proof=nil;publish() end
        return ok
    end
    local function pending(value)
        return {packet=value,attempts=0,due=s.clock,created=s.clock,local_gen=s.generation}
    end
    local function start(peer,p)
        local value=challenge();if not value then return end
        p.query=pending(packet("q","",0,value,""))
        emit(peer,p,p.query)
    end
    local function adopt(peer,p,epoch,generation)
        if retired(peer,epoch) then return false end
        if p.epoch==epoch and p.maximum_gen and generation<p.maximum_gen then return false end
        if p.epoch~=epoch then retire(peer,p.epoch);p.epoch=epoch end
        p.maximum_gen=generation;return true
    end
    local function grant(p,epoch,generation)
        p.proof={remote_epoch=epoch,remote_gen=generation,local_gen=s.generation,
            key=s.key,expires=s.clock+M.PROOF_TTL,created=s.clock}
    end

    function api:allows(config,now)
        if not refresh(now) then return false end
        local _,key=M.canonicalize(config)
        return key~=nil and key==s.key and desired()
    end
    function api:applied_state() return s.applied end
    function api:tick(now)
        if s.busy then return false end
        s.busy=true
        if refresh(now) then
            for peer,p in pairs(s.peers) do
                for _,field in ipairs({"query","response","ack"}) do
                    local record=p[field]
                    if record and (s.clock-record.created>M.HANDSHAKE_TTL
                            or record.attempts>=M.MAX_ATTEMPTS and s.clock>=record.due) then
                        p[field]=nil
                        if field=="query" then p.retry_at=s.clock+M.RETRY_COOLDOWN end
                    elseif record then emit(peer,p,record) end
                end
                local renewal=not p.proof or s.clock-p.proof.created>=M.REFRESH_AFTER
                if renewal and not p.query and s.clock>=p.retry_at then start(peer,p) end
            end
            publish()
        end
        s.busy=false;return s.applied
    end
    function api:settings_changed(now) return self:tick(now) end
    function api:receive(peer,value,now)
        if s.busy then return false end
        s.busy=true
        local accepted=false
        if refresh(now) and safe(peer,M.MAX_PEER_ID) and s.peers[peer] then
            local p=s.peers[peer]
            local tuple,key=M.validate_packet(value)
            if not tuple then p.proof=nil
            elseif not retired(peer,value[3]) then
                local kind,epoch,generation=value[2],value[3],value[4]
                local stale=p.epoch==epoch and p.maximum_gen and generation<p.maximum_gen
                if kind=="q" and not stale then
                    if p.epoch~=epoch or generation~=p.maximum_gen or key~=s.key then p.proof=nil end
                    if p.epoch==epoch and (not p.maximum_gen or generation>p.maximum_gen) then
                        p.maximum_gen=generation
                    end
                    local n=nonce(value[7]);local previous=p.query_max[epoch]
                    if previous==nil then
                        p.query_epochs[#p.query_epochs+1]=epoch
                        if #p.query_epochs>M.MAX_QUERY_EPOCHS then p.query_max[table.remove(p.query_epochs,1)]=nil end
                    end
                    if not previous or n>previous then
                        p.query_max[epoch]=n
                        local own=challenge()
                        if own then
                            p.response=pending(packet("r",epoch,generation,own,value[7]))
                            p.response.remote_key=key;emit(peer,p,p.response)
                        end
                    elseif n==previous and p.response and p.response.packet[5]==epoch
                            and p.response.packet[8]==value[7] then emit(peer,p,p.response) end
                elseif value[5]==s.epoch and value[6]==s.generation and not stale then
                    if kind=="r" then
                        local request=p.query
                        if request and request.local_gen==s.generation
                                and s.clock-request.created<=M.HANDSHAKE_TTL
                                and value[8]==request.packet[7] then
                            p.query=nil
                            if adopt(peer,p,epoch,generation) and key==s.key then
                                grant(p,epoch,generation)
                                p.ack=pending(packet("a",epoch,generation,"",value[7]))
                                p.accepted={epoch=epoch,generation=generation,challenge=value[7],
                                    echo=value[8],local_gen=s.generation,key=key}
                                emit(peer,p,p.ack);accepted=true
                            else p.proof=nil;p.retry_at=s.clock+M.RETRY_COOLDOWN end
                        elseif p.accepted and p.ack and p.accepted.local_gen==s.generation
                                and p.accepted.epoch==epoch and p.accepted.generation==generation
                                and p.accepted.challenge==value[7] and p.accepted.echo==value[8]
                                and p.accepted.key==key then
                            emit(peer,p,p.ack) -- duplicate cannot extend proof expiry
                        end
                    elseif kind=="a" then
                        local response=p.response
                        if response and response.local_gen==s.generation
                                and s.clock-response.created<=M.HANDSHAKE_TTL
                                and response.packet[5]==epoch and response.packet[6]==generation
                                and response.packet[7]==value[8] and response.remote_key==key
                                and key==s.key and adopt(peer,p,epoch,generation) then
                            grant(p,epoch,generation);p.response=nil;accepted=true
                        end
                    end
                end
            end
            publish()
        end
        s.busy=false;return accepted
    end
    function api:disconnect(peer,now)
        if s.busy or not clock(now) or not safe(peer,M.MAX_PEER_ID) then return false end
        local p=s.peers[peer]
        if p then retire(peer,p.epoch);s.peers[peer]=nil end
        publish();return true
    end
    function api:inspect()
        local out={generation=s.generation,counter=s.counter,healthy=s.healthy,
            applied=s.applied,fatal=s.fatal,peers={},retired_peers=#s.retired_order}
        for peer,p in pairs(s.peers) do
            out.peers[peer]={epoch=p.epoch,generation=p.maximum_gen,proved=p.proof~=nil,
                expires=p.proof and p.proof.expires,queries=#p.query_epochs,
                query_attempts=p.query and p.query.attempts,response_attempts=p.response and p.response.attempts,
                ack_attempts=p.ack and p.ack.attempts,tokens=p.tokens}
        end
        out.retired={};for peer,row in pairs(s.retired) do out.retired[peer]=#row.order end
        return out
    end
    return api
end
return M
