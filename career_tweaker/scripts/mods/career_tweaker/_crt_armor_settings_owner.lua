-- #221: the armor cluster alone owns its reversible preimage. GUT transports
-- opaque profile data and prepares before any writes; it never names these keys.
return function(mod, policy, armor)
    local a, b, master, held = armor.ids[1], armor.ids[2], armor.master_id, armor.snapshot_id
    local saved_a, saved_b = armor.snapshot_prefix .. a, armor.snapshot_prefix .. b
    local owned = { [a] = true, [b] = true, [master] = true }
    local function boolean(value) return type(value) == "boolean" end
    local function read(id)
        local value = mod:get(id)
        assert(value == nil or boolean(value), "invalid saved armor setting")
        return value == true
    end
    local function snapshot()
        return { [a] = read(a), [b] = read(b), [master] = read(master), [held] = read(held),
            [saved_a] = read(saved_a), [saved_b] = read(saved_b) }
    end
    local function validate(metadata, visible)
        assert(type(metadata) == "table" and getmetatable(metadata) == nil
            and metadata.schema == 1 and metadata.owner == "crt" and metadata.cluster == "armor"
            and boolean(metadata.held) and type(metadata.saved) == "table"
            and getmetatable(metadata.saved) == nil, "invalid armor profile metadata")
        for key in pairs(metadata) do
            assert(key == "schema" or key == "owner" or key == "cluster" or key == "held"
                or key == "saved", "unknown armor metadata field")
        end
        for key in pairs(metadata.saved) do assert(key == a or key == b, "foreign armor preimage") end
        assert(boolean(metadata.saved[a]) and boolean(metadata.saved[b]), "incomplete armor preimage")
        assert(visible[master] == metadata.held, "armor master/ownership mismatch")
        if metadata.held then assert(visible[a] and visible[b], "held armor profile has custom leaves") end
    end
    local api = { version = 1 }
    function api.capture(visible, defaults)
        if visible[master] == nil and visible[a] == nil and visible[b] == nil then return nil end
        assert(boolean(visible[master]) and boolean(visible[a]) and boolean(visible[b]),
            "incomplete armor profile")
        local current = snapshot()
        local state = { schema = 1, owner = "crt", cluster = "armor",
            held = not defaults and current[held] or false, saved = {} }
        -- Explicit branches preserve false preimages, unlike Lua's and/or idiom.
        if state.held then state.saved[a], state.saved[b] = current[saved_a], current[saved_b]
        else state.saved[a], state.saved[b] = visible[a], visible[b] end
        validate(state, visible)
        return state
    end
    function api.prepare(pending, context)
        assert(context.owner_id == "crt" and (context.kind == "edit" or context.kind == "profile"
            or context.kind == "reconcile"),
            "foreign armor transaction")
        local handled = {}
        for id in pairs(owned) do
            if pending[id] ~= nil then
                assert(boolean(pending[id]), "invalid armor pending value")
                handled[id] = true
            end
        end
        if not next(handled) then
            assert(context.metadata == nil, "armor metadata without armor settings")
            return nil
        end
        local target = snapshot() -- before the generic writer can overwrite leaves
        if context.kind == "profile" then
            assert(handled[master] and handled[a] and handled[b], "incomplete armor profile replay")
            if context.metadata ~= nil then validate(context.metadata, pending) end
            target[a], target[b] = pending[a], pending[b]
            if context.metadata then
                target[held], target[master] = context.metadata.held, pending[master]
                target[saved_a], target[saved_b] = context.metadata.saved[a], context.metadata.saved[b]
            else
                -- Legacy profiles cannot reconstruct a lost preimage. Preserve
                -- their explicit leaves as custom, never pretend OFF can restore.
                target[held], target[master] = false, false
            end
        elseif context.kind == "reconcile" then
            -- Missing members are initialization, not an ON/OFF user command.
            -- Never restore saved leaves or replay present profile values here.
            assert(context.metadata == nil, "reconciliation cannot restore profile metadata")
            assert(not handled[master] or pending[master] == false,
                "armor reconciliation cannot invent an enabled preimage")
            if handled[a] then target[a] = pending[a] end
            if handled[b] then target[b] = pending[b] end
            target[held], target[master] = false, false
        elseif handled[a] or handled[b] then
            if handled[a] then target[a] = pending[a] end
            if handled[b] then target[b] = pending[b] end
            target[held], target[master] = false, false -- explicit children win
        else
            for _, change in ipairs(policy:plan("armor", pending[master], target)) do
                target[change.id] = change.value
            end
        end
        return { handled = handled, commit = function()
            -- Establish the preimage before touching leaves; release ownership
            -- last. An interrupted write/retry cannot capture half-applied leaves.
            local order
            if context.kind == "reconcile" then
                order = {}
                if handled[a] then order[#order + 1] = a end
                if handled[b] then order[#order + 1] = b end
                order[#order + 1], order[#order + 2] = master, held
            else
                order = target[held] and { saved_a, saved_b, held, a, b, master }
                    or { a, b, master, held }
            end
            for _, id in ipairs(order) do
                if mod:get(id) ~= target[id] then mod:set(id, target[id], false) end
            end
            return true -- armor hooks consume live settings, no template rebuild
        end }
    end
    return api
end
