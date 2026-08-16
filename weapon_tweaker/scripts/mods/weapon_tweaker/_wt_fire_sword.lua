-- _wt_fire_sword.lua — Fire Sword heavy-attack policy (issue #943).
--
-- Two independent, default-off projections over Sienna's Fire Sword
-- (`Weapons.flaming_sword_template_1`, decompile 1h_swords_wizard.lua):
-- (a) sweep opener — repoint the two idle `action_one.default` heavy entry
-- edges (charged release :37-41 and auto_chain :60-65) from the burning nova
-- (`heavy_attack_spell`) to the sweep (`heavy_attack_left`); the untouched
-- sweep-to-nova continuation (`default_right` :154-183) keeps the alternation.
-- (b) nova slowdown — divide `heavy_attack_spell.anim_time_scale` (:423) by
-- 1.10 and scale its bounded action-local clock/window fields (total_time,
-- damage windows, hit_time, buff_data and chain start/end times) by 1.10 so
-- hit, damage, and continuation timing track the slower clip. Both settings
-- project from ONE immutable per-template-identity baseline captured before
-- the first write, so repeated applies never compound and toggling off
-- restores exact captured values. Wire-safe by construction: (a) re-routes
-- sub_action between vanilla action names only (same class as the #348
-- push-combo revert) and (b) edits attacker-local melee timing only (same
-- class as the #622/#623 speed nerfs) — no NetworkLookup key is touched.
--
-- Owned by: weapon_tweaker.lua entry point. Consumed via: mod:dofile plus
-- M.install(mod), which publishes the `mod._wt_apply_fire_sword` adapter from
-- this file (settings dispatch in _wt_settings_runtime.lua; regression check
-- in _wt_runtime_checks.lua).

local M = {}

M.SWEEP_OPENER_SETTING = "wt_fire_sword_sweep_opener"
M.NOVA_SLOWDOWN_SETTING = "wt_fire_sword_nova_slowdown"
M.TEMPLATE = "flaming_sword_template_1"
M.OPENER_ACTION = "default"
M.NOVA_ACTION = "heavy_attack_spell"
M.SWEEP_ACTION = "heavy_attack_left"
M.SLOW_TIME_MULT = 1.10
M.SLOW_ANIM_MULT = 1 / M.SLOW_TIME_MULT

-- Scalar clock/window fields on the nova action that must stretch with the
-- slower clip. total_time bounds the action, the damage window and hit_time
-- gate the hit, and (captured separately below) buff_data / chain start and
-- end times gate movement slow and heavy continuation.
M.NOVA_TIME_FIELDS = {
    "total_time", "damage_window_start", "damage_window_end", "hit_time",
}

local function _finite_number(value)
    return type(value) == "number" and value == value
        and value ~= math.huge and value ~= -math.huge
end

-- The two idle heavy entry edges: within action_one.default, the charged
-- release and the auto-chain that both establish the vanilla Heavy 1 nova.
-- The light release edge also uses action_one_release but targets a light
-- sub_action, so matching on the captured nova destination is exact.
function M.is_idle_nova_edge(edge)
    return type(edge) == "table"
        and edge.action == "action_one"
        and edge.sub_action == M.NOVA_ACTION
        and (edge.auto_chain == true or edge.input == "action_one_release")
end

-- Immutable baseline for one template identity. Scans run ONLY here, before
-- the first write to that identity, so captured values are always vanilla.
-- Edge/action/buff table REFS are retained for projection; every captured
-- number is copied out so later writes cannot alias the baseline.
local function _capture(template)
    local actions = type(template) == "table"
        and type(template.actions) == "table"
        and template.actions.action_one
    if type(actions) ~= "table" then return nil end
    local baseline = { edges = {}, nova = nil }

    local opener = actions[M.OPENER_ACTION]
    local chain = type(opener) == "table" and opener.allowed_chain_actions
    if type(chain) == "table" then
        for i = 1, #chain do
            local edge = chain[i]
            if M.is_idle_nova_edge(edge) then
                baseline.edges[#baseline.edges + 1] = {
                    ref = edge,
                    sub_action = edge.sub_action,
                }
            end
        end
    end

    local nova = actions[M.NOVA_ACTION]
    if type(nova) == "table" then
        local row = {
            ref = nova,
            anim_had = nova.anim_time_scale ~= nil,
            anim = nova.anim_time_scale,
            fields = {},
            buffs = {},
            chain = {},
        }
        for _, field in ipairs(M.NOVA_TIME_FIELDS) do
            if _finite_number(nova[field]) then
                row.fields[field] = nova[field]
            end
        end
        if type(nova.buff_data) == "table" then
            for i = 1, #nova.buff_data do
                local buff = nova.buff_data[i]
                if type(buff) == "table" then
                    row.buffs[#row.buffs + 1] = {
                        ref = buff,
                        start_time = _finite_number(buff.start_time) and buff.start_time or nil,
                        end_time = _finite_number(buff.end_time) and buff.end_time or nil,
                    }
                end
            end
        end
        if type(nova.allowed_chain_actions) == "table" then
            for i = 1, #nova.allowed_chain_actions do
                local edge = nova.allowed_chain_actions[i]
                if type(edge) == "table" then
                    row.chain[#row.chain + 1] = {
                        ref = edge,
                        start_time = _finite_number(edge.start_time) and edge.start_time or nil,
                        end_time = _finite_number(edge.end_time) and edge.end_time or nil,
                    }
                end
            end
        end
        baseline.nova = row
    end

    if #baseline.edges == 0 and not baseline.nova then return nil end
    return baseline
end

function M.new()
    local state = {
        -- Weak keys: a replaced template table gets a fresh vanilla capture on
        -- its next apply and the stale identity's baseline is collectable.
        _baselines = setmetatable({}, { __mode = "k" }),
        sweep_opener_enabled = false,
        nova_slowdown_enabled = false,
    }

    -- Project both settings from the captured baseline onto the live template.
    -- Always writes baseline-derived values (never reads back its own output),
    -- so any apply sequence ends at exactly baseline (off) or baseline × the
    -- documented factor (on). Returns idle-edge and nova-action counts for
    -- receipts/regression.
    function state:apply(sweep_opener_enabled, nova_slowdown_enabled, weapons)
        sweep_opener_enabled = sweep_opener_enabled == true
        nova_slowdown_enabled = nova_slowdown_enabled == true
        local template = type(weapons) == "table" and weapons[M.TEMPLATE]
        if type(template) ~= "table" then return 0, 0 end
        local baseline = self._baselines[template]
        if not baseline then
            baseline = _capture(template)
            if not baseline then return 0, 0 end
            self._baselines[template] = baseline
        end

        for i = 1, #baseline.edges do
            local edge = baseline.edges[i]
            edge.ref.sub_action = sweep_opener_enabled
                and M.SWEEP_ACTION or edge.sub_action
        end

        local nova_count = 0
        local nova = baseline.nova
        if nova then
            nova_count = 1
            local action = nova.ref
            local mult = nova_slowdown_enabled and M.SLOW_TIME_MULT or 1
            if nova_slowdown_enabled then
                action.anim_time_scale = (nova.anim or 1) * M.SLOW_ANIM_MULT
            else
                action.anim_time_scale = nova.anim_had and nova.anim or nil
            end
            for field, value in pairs(nova.fields) do
                action[field] = value * mult
            end
            for i = 1, #nova.buffs do
                local buff = nova.buffs[i]
                if buff.start_time then buff.ref.start_time = buff.start_time * mult end
                if buff.end_time then buff.ref.end_time = buff.end_time * mult end
            end
            for i = 1, #nova.chain do
                local edge = nova.chain[i]
                if edge.start_time then edge.ref.start_time = edge.start_time * mult end
                if edge.end_time then edge.ref.end_time = edge.end_time * mult end
            end
        end

        self.sweep_opener_enabled = sweep_opener_enabled
        self.nova_slowdown_enabled = nova_slowdown_enabled
        return #baseline.edges, nova_count
    end

    return state
end

-- Bounded apply seam, owned here so the entry stays a manifest
-- (PROJECT_STANDARDS 2.2a rule 1). Holds the single policy instance and
-- publishes `mod._wt_apply_fire_sword`, which load, state transitions,
-- single-setting dispatch (_wt_settings_runtime), owner batches, and
-- on_disabled all rerun against the same baseline projection, so late or
-- replaced templates re-capture per identity. Applies once at install.
function M.install(mod)
    local state = M.new()
    mod._wt_apply_fire_sword = function(setting_id, force_off)
        if type(Weapons) ~= "table" then return end
        if setting_id
                and setting_id ~= M.SWEEP_OPENER_SETTING
                and setting_id ~= M.NOVA_SLOWDOWN_SETTING then
            return
        end
        local function enabled(id)
            return not force_off and mod:get(id) == true
        end
        local sweep_opener = enabled(M.SWEEP_OPENER_SETTING)
        local nova_slowdown = enabled(M.NOVA_SLOWDOWN_SETTING)
        local idle_edges, nova_actions = state:apply(
            sweep_opener, nova_slowdown, Weapons)
        pcall(printf,
            "[wt:943] applied: sweep_opener=%s nova_slowdown=%s idle_edges=%d nova_actions=%d",
            tostring(sweep_opener), tostring(nova_slowdown), idle_edges, nova_actions)
    end
    mod._wt_apply_fire_sword(nil, false)
    return state
end

return M
