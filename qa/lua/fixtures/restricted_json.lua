-- Original QA-only JSON array fixture, not the game's cjson implementation.
-- The protocols use only nested arrays, restricted unescaped strings and ints.
local M = {}
function M.encode(value)
    if type(value) == "string" then
        assert(not value:find('["\\%z\1-\31]'), "fixture string outside protocol alphabet")
        return '"' .. value .. '"'
    elseif type(value) == "number" then
        assert(value == value and value ~= math.huge and value ~= -math.huge and value % 1 == 0)
        return string.format("%.0f", value)
    end
    assert(type(value) == "table" and getmetatable(value) == nil)
    local n = 0; for key in pairs(value) do assert(type(key)=="number" and key%1==0 and key>=1); n=n+1 end
    assert(n == #value)
    local out = {}; for i=1,n do out[i]=M.encode(value[i]) end
    return "[" .. table.concat(out,",") .. "]"
end
function M.decode(source)
    assert(type(source)=="string" and #source<=4096)
    local i = 1
    local function parse(depth)
        assert(depth<5)
        local char = source:sub(i,i)
        if char == "[" then
            i=i+1; local out={}
            if source:sub(i,i)=="]" then i=i+1; return out end
            repeat
                out[#out+1]=parse(depth+1)
                char=source:sub(i,i); i=i+1
                assert(char=="," or char=="]")
            until char=="]"
            return out
        elseif char == '"' then
            local last=assert(source:find('"',i+1,true)); local value=source:sub(i+1,last-1)
            assert(not value:find('[\\%z\1-\31]')); i=last+1; return value
        else
            local token=assert(source:sub(i):match("^%-?%d+")); i=i+#token
            local n=assert(tonumber(token)); assert(string.format("%.0f",n)==token)
            return n
        end
    end
    local value=parse(0); assert(i==#source+1); return value
end
return M
