-- Runtime owner for the exact effective-template career-action invariant.
-- Runs before vanilla consumes the wielded template, independent of optional
-- diagnostics. Unknown providers and unresolved identities pass through.
local mod = get_mod("wt")
local WT = mod._wt
local context_policy = mod:dofile(
    "scripts/mods/weapon_tweaker/_wt_effective_action_context")

local seen = {}
local emitted = 0
local MAX_DIAGNOSTICS = 64

local function career_name_for(inventory)
    if type(inventory and inventory._career_name) == "string" then
        return inventory._career_name
    end
    local unit = inventory and inventory._unit
    if unit and ScriptUnit and type(ScriptUnit.has_extension) == "function" then
        local ok, extension = pcall(ScriptUnit.has_extension, unit, "career_system")
        if ok and extension and type(extension._career_name) == "string" then
            return extension._career_name
        end
    end
    return nil
end

local function cwv_identity_resolver()
    local ok, cwv = pcall(get_mod, "character_weapon_variants")
    if not ok or type(cwv) ~= "table"
            or type(cwv._cwv_resolve_item_key) ~= "function" then
        return nil
    end
    return cwv._cwv_resolve_item_key
end

local function emit(context, reason, direct_key)
    local signature = table.concat({
        tostring(context and context.item_key or direct_key),
        tostring(context and context.career_name),
        tostring(context and context.template),
        tostring(reason),
    }, "|")
    if seen[signature] or emitted >= MAX_DIAGNOSTICS then return end
    seen[signature] = true
    emitted = emitted + 1
    pcall(printf,
        "[wt:661] wield-boundary item=%s career=%s template=%s result=%s trace=%d/%d",
        tostring(context and context.item_key or direct_key),
        tostring(context and context.career_name),
        tostring(context and context.template), tostring(reason),
        emitted, MAX_DIAGNOSTICS)
end

local function reconcile(inventory, slot_data)
    local resolvers = {}
    local cwv_resolver = cwv_identity_resolver()
    if cwv_resolver then resolvers[#resolvers + 1] = cwv_resolver end
    local context, reason = context_policy.resolve(slot_data,
        career_name_for(inventory), {
            identity_resolvers = resolvers,
            item_master_list = rawget(_G, "ItemMasterList"),
            get_item_template = function(item_data, backend_id)
                return BackendUtils.get_item_template(item_data, backend_id)
            end,
        })
    if not context then
        emit(nil, reason, context_policy.direct_item_key(slot_data))
        return nil, reason
    end
    if not context_policy.is_managed(context, WT.weapon_unlock_map) then
        emit(context, "unmanaged_provider", context.item_key)
        return nil, "unmanaged_provider"
    end
    local report, result = WT.reconcile_effective_career_actions(
        context.item, context.template, context.career_name, context.item_key)
    emit(context, result or "reconcile_unavailable", context.item_key)
    return report, result
end

-- Pre-call is required: PlayerCharacterStateHelper may consult the newly
-- wielded template immediately after this transition. A post-hook makes the
-- invariant depend on every earlier wrapper returning successfully.
mod:hook("SimpleInventoryExtension", "_wield_slot",
    function(func, self, equipment, slot_data, unit_1p, unit_3p, buff_extension)
        local ok, err = pcall(reconcile, self, slot_data)
        if not ok then
            mod:error("[wt:661] pre-wield reconciliation failed: %s", tostring(err))
        end
        -- Call the engine exactly once and return its complete tuple directly.
        return func(self, equipment, slot_data, unit_1p, unit_3p, buff_extension)
    end)

WT.weapon_action_context_policy = context_policy
WT.reconcile_wielded_career_action = reconcile

return {
    reconcile = reconcile,
    context_policy = context_policy,
}
