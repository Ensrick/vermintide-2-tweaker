-- _wt_anim_remap.lua -- cross-character 3P animation-remap core.
--
-- The heart of weapon_tweaker: the machinery that makes a foreign weapon's 3P
-- animation events resolve to clips the RECEIVER's skeleton actually authors.
-- 1P is universal and never touched (feedback_1p_animations_universal). Split
-- out of the god file in the v0.12.210-dev Phase 2 OOP decomposition -- VERBATIM
-- function-bag move, zero behavior change. Owns:
--   * the three redirect layers -- _anim_redirect (global renames),
--     _career_anim_redirect (career-prefix renames), _suffix_career_map
--     (suffix swaps) + _try_suffix_redirect / _safe_has_anim
--   * the per-weapon / per-key remap tables (_3p_remap_*, _3p_key_remaps),
--     the sibling-built _3p_template_remaps catalog, and their resolvers
--   * the weak-keyed per-unit remap state (_unit_state / _state_for) and the
--     two wield hooks (SimpleInventoryExtension / SimpleHuskInventoryExtension)
--     that populate it
--   * THE funnel: the Unit.animation_event hook that rewrites the fired 3P event
--   * the read-only /info support command and the
--     keep-previewer pose resolver (_resolve_preview_wield_event)
--
-- Owned by: weapon_tweaker.lua entry point. Consumed via: mod:dofile (after the
-- entry publishes the hot-path handles below and defines feature_enabled /
-- _local_career_name, and before the port-pipeline longbow template patchers
-- that mutate _3p_template_remaps run).
--
-- Shared state: the hot tables stay file-local upvalues HERE so the per-event
-- funnel never indirects through mod._wt. The entry publishes the handles this
-- module reads on its hot path -- mod._wt.feature_enabled / .local_career_name /
-- .dbg (+ the pre-existing .MOD_VERSION / .weapon_unlock_map
-- and manifest-loaded .build_3p_template_remaps)
-- -- captured as upvalues here at load. This module EXPORTS the handles the
-- entry's stayed code still needs (all non-hot-path reads): mod._wt.safe_has_anim
-- / .resolve_preview_wield_event / .unit_career_name / .unit_state /
-- .suffix_career_map / .three_p_template_remaps.

local mod = get_mod("wt")
local WT  = mod._wt

-- Hot-path handles the entry owns (published onto mod._wt before this dofile).
-- Captured as file-local upvalues so the per-event funnel never reads mod._wt.
local feature_enabled     = WT.feature_enabled
local _local_career_name  = WT.local_career_name
local _dbg                = WT.dbg
local MOD_VERSION         = WT.MOD_VERSION
local weapon_unlock_map   = WT.weapon_unlock_map
local _build_3p_template_remaps = WT.build_3p_template_remaps
local _cwv_effective_template = mod:dofile(
    "scripts/mods/weapon_tweaker/_wt_cwv_effective_template")
local _anim_state_policy = mod:dofile(
    "scripts/mods/weapon_tweaker/_wt_anim_state_policy")
-- WP-WT-06: redirect/remap data and the pure decision live in the resolver;
-- the names below alias them so /info, the template-remap builder, the
-- exports and the dev overlays keep reading the same tables.
local _resolver = mod:dofile("scripts/mods/weapon_tweaker/_wt_anim_resolver")

local _anim_redirect        = _resolver.anim_redirect
local _career_anim_redirect = _resolver.career_anim_redirect
local _suffix_order         = _resolver.suffix_order
local _suffix_career_map    = _resolver.suffix_career_map

-- pcall-guarded `Unit.has_animation_event`. Returns true only if the unit has
-- the named anim event. Used by every redirect/remap helper below — defined
-- BEFORE _try_suffix_redirect to avoid the forward-reference trap that bit
-- this codebase 5+ times (see feedback_lua_forward_reference.md).
local function _safe_has_anim(unit, event)
    local ok, result = pcall(Unit.has_animation_event, unit, event)
    return ok and result
end

local function _try_suffix_redirect(unit, event_name, career)
    return _resolver.try_suffix_redirect(function(name)
        return _safe_has_anim(unit, name)
    end, event_name, career)
end

-- Inventory-preview wield pose (3P only): the receiver-native wield event for
-- one (event, career) pair, without firing. Rule and rationale live with the
-- data in _wt_anim_resolver.lua (resolve_preview_wield_event).
local function _resolve_preview_wield_event(body, event_name, career)
    return _resolver.resolve_preview_wield_event(function(name)
        return _safe_has_anim(body, name)
    end, event_name, career)
end

local _3p_remap_spear_to_billhook    = _resolver.remap_spear_to_billhook
local _3p_remap_polearm_to_billhook  = _resolver.remap_polearm_to_billhook
local _3p_remap_spear_to_polearm     = _resolver.remap_spear_to_polearm
local _3p_remap_billhook_to_polearm  = _resolver.remap_billhook_to_polearm
local _billhook_effective_3p_events  = _resolver.billhook_effective_3p_events
local _polearm_native_3p_events      = _resolver.polearm_native_3p_events
local _3p_remap_triggers             = _resolver.remap_triggers
local _resolve_3p_remap              = _resolver.resolve_3p_remap

-- Per-unit 3P animation state, keyed by the 3P body unit (player_unit for
-- the local player, husk units for remote players). Weak-keyed so dead units
-- release automatically.
--
-- v0.12.35 — replaces the prior single-global pattern, which only tracked the
-- LOCAL player's weapon. With one global, the animation_event hook applied
-- the local viewer's remap to every 3P body it saw, so remote players' cross-
-- career weapons rendered with wrong/missing 3P anims unless the host happened
-- to be holding the same weapon on the same career.
--
-- Each entry tracks:
--   template      = effective active-style donor template at last wield
--   key           = item_data.key at last wield
--   remap         = currently active _3p_*_remap table (or `false` for a
--                   deliberate "no remap" from _3p_remap_triggers.X.we_ = false)
--   last_remap_id = snapshot of (template or key) at the moment the remap was
--                   selected — used to skip clear-and-reset for non-weapon `to_`
--                   events (to_crouch / to_zoom / to_onground)
local _unit_state = setmetatable({}, { __mode = "k" })

local function _state_for(unit)
    if not unit then return nil end
    local s = _unit_state[unit]
    if not s then
        s = { template = nil, key = nil, remap = nil, last_remap_id = nil }
        _unit_state[unit] = s
    end
    return s
end

-- Template-specific remap data is built once in a sibling so this event-hot
-- dispatch module remains under the repository hard size limit. The returned
-- table remains a file-local upvalue and is exported by reference below.
local _3p_template_remaps = _build_3p_template_remaps(
    _3p_remap_billhook_to_polearm,
    _3p_remap_spear_to_polearm,
    _3p_remap_triggers
)
local function _resolve_template_remap(template_name, career)
    return _resolver.resolve_template_remap(_3p_template_remaps, template_name, career)
end

local _3p_key_remaps      = _resolver.key_remaps
local _resolve_key_remap  = _resolver.resolve_key_remap

local _log_anims = false
local _last_3p_unit = nil
-- CLARIFY: captured in the wield hook from `self._first_person_unit`. Used
-- ONLY to distinguish the local 1P hands unit (which should NOT receive
-- redirects) from husks (which should). Cannot use `is_local` for this —
-- the 1P unit has `is_local=false` same as husks (see feedback_animation_remap_rules).
local _local_fp_unit = nil
-- CLARIFY: stashed reference to the original `Unit.animation_event` so we can
-- bypass our own hook for force-fire events that corrupt the SM when going
-- through the remap-table path (e.g. attack_swing_stab_02 on billhook).
local _original_animation_event = nil
local _animlog_last_was_attack = false

mod:command("info", "Show current weapon tweaker state", function()
    mod:echo("Weapon Tweaker v" .. MOD_VERSION)
    local career = _local_career_name()
    mod:echo("Career: " .. (career or "unknown"))
    local remap_name = "none"
    local pm = Managers.player
    local player = pm and pm:local_player()
    local state = player and player.player_unit and _unit_state[player.player_unit]
    local remap = state and state.remap
    if remap then
        if remap == _3p_remap_spear_to_billhook then remap_name = "spear→billhook"
        elseif remap == _3p_remap_polearm_to_billhook then remap_name = "polearm→billhook"
        elseif remap == _3p_remap_spear_to_polearm then remap_name = "spear→polearm"
        elseif remap == _3p_remap_billhook_to_polearm then remap_name = "billhook→polearm"
        else remap_name = "custom" end
    end
    mod:echo("3P Remap: " .. remap_name)
    if career then
        local weapons = weapon_unlock_map[career]
        if weapons then
            local enabled = 0
            for _, wk in ipairs(weapons) do
                if mod:get("unlock_" .. career .. "_" .. wk) then enabled = enabled + 1 end
            end
            mod:echo("Weapons: " .. enabled .. "/" .. #weapons .. " enabled")
        end
    end
end)

local function _is_local_player_unit(unit)
    local pm = Managers.player
    if not pm then return false end
    local ok, player = pcall(pm.local_player, pm)
    if not ok or not player then return false end
    return player.player_unit == unit
end

-- Returns the career name of the player who owns this unit (local or husk).
-- nil for non-player units. Use for per-unit redirect decisions so husks of
-- other players get routed by THEIR career, not the local viewer's.
local function _unit_career_name(unit)
    if not unit then return nil end
    -- Primary: career_system extension. CareerExtension is attached to both
    -- local player_units AND husks (unit_extension_templates.lua: line 12 for
    -- self-owned, line 75 for husks). Its init sets self._career_name directly
    -- from career_data.name (career_extension.lua:23) — the most authoritative
    -- source. v0.12.37 — was previously falling through to inventory_system
    -- first, but on remote-player husks (SimpleHuskInventoryExtension) the
    -- inventory extension's `_career_name` is only set if a Player object was
    -- passed in extension_init_data with a non-nil career_name() at init time.
    -- That's a real race on lobby-formed remote players. career_system has no
    -- such race — it pulls from career_data directly.
    local ok_career, career_ext = pcall(ScriptUnit.has_extension, unit, "career_system")
    if ok_career and career_ext and career_ext._career_name then return career_ext._career_name end
    -- Fallback: inventory_system extension. SimpleInventoryExtension.init sets
    -- self._career_name BEFORE extensions_ready fires, and our
    -- GearUtils.spawn_inventory_unit hook is called from within add_equipment
    -- (invoked from extensions_ready). Reliable for the local player even at
    -- fresh-mission-spawn timing when Managers.player:owner(unit) returns nil.
    -- See feedback_vt2_mission_spawn_career_lookup.
    local ok_ext, ext = pcall(ScriptUnit.has_extension, unit, "inventory_system")
    if ok_ext and ext and ext._career_name then return ext._career_name end
    -- Fallback: Managers.player path (post-spawn / husk lookups).
    local pm = Managers.player
    if not pm then return nil end
    local ok, player = pcall(pm.owner, pm, unit)
    if not ok or not player then return nil end
    local ok2, name = pcall(player.career_name, player)
    if ok2 and name then return name end
    local ok3, prof_idx = pcall(player.profile_index, player)
    local ok4, career_idx = pcall(player.career_index, player)
    if ok3 and ok4 and SPProfiles and prof_idx and career_idx then
        local prof = SPProfiles[prof_idx]
        local c = prof and prof.careers and prof.careers[career_idx]
        if c and c.name then return c.name end
    end
    return nil
end

-- v0.12.88-dev: sampling counters for hot-path _dbg traces. animation_event
-- fires on every animation event for every unit (per-frame-class hot path),
-- so emitting a _dbg line per call would flood the log. _ANIM_EVENT_SAMPLE_N
-- = 60 means roughly "log 1 in 60 calls" (~1/sec on a player wielding a
-- weapon). REMAP / FORCE / REDIR branches sample less aggressively because
-- they only fire on actual remap hits (cross-character ports), which are
-- rarer than the top-level call count. Per PROJECT_STANDARDS § 3.6
-- "Performance note: mod:get is cheap"; sampling is purely a log-volume
-- concern.
-- WP-WT-08: count an error the funnel swallowed (WT.note_swallowed is set
-- by the entry before this module loads; nil in host harnesses).
local function _note_anim_swallow(event, err)
    local note = WT.note_swallowed
    if note then note("anim_event", tostring(event) .. ": " .. tostring(err)) end
end

-- WP-WT-06: one decision context and one info table are reused for every
-- call, so the hot path allocates nothing; the hook reads both before it calls
-- the engine, so a re-entrant animation event cannot clobber them in use.
local _decide_unit = nil
local _decide_ctx = {
    has_event = function(name) return _safe_has_anim(_decide_unit, name) end,
    template_remaps = _3p_template_remaps,
    remap_identity = function(template_name, item_key, career_name)
        return _anim_state_policy.remap_identity(template_name, item_key, career_name)
    end,
    info = {},
}

local _ANIM_EVENT_SAMPLE_N = 60
local _ANIM_EVENT_SAMPLE_REMAP_N = 30
local _anim_event_call_count = 0
local _anim_event_remap_count = 0

-- #576's bounded live evidence belongs to the friends-only dev overlay. The
-- shared public path keeps the same remap behavior without issue-specific rows.
-- CLARIFY: stringified hook on the C-API class `Unit`. VMF resolves this
-- against `_G.Unit.animation_event`. This is the central entry point — every
-- animation event for every unit goes through here once the mod is loaded,
-- so cheap early-exits matter for performance.
mod:hook("Unit", "animation_event", function(func, unit, event_name, ...)
    -- CLARIFY: capture the underlying function the FIRST time we're called so
    -- force-fire paths (force3p command, billhook stab_02 force-target) can
    -- bypass our own hook recursively without infinite loop.
    if not _original_animation_event then _original_animation_event = func end

    if not event_name then return func(unit, event_name, ...) end

    -- v0.12.88-dev: sampled entry trace (1-in-60). This is the hottest hook
    -- in wt; full per-call _dbg would flood. Sample is enough to confirm the
    -- hook is firing at all + spot-check the event names flowing through.
    _anim_event_call_count = _anim_event_call_count + 1
    if _anim_event_call_count % _ANIM_EVENT_SAMPLE_N == 0 then
        _dbg("[wt:anim] event=enter event_name=%s sample=%d (1-in-%d)",
            tostring(event_name), _anim_event_call_count, _ANIM_EVENT_SAMPLE_N)
    end

    if not feature_enabled("enable_weapon_animation_redirects", true) then
        return func(unit, event_name, ...)
    end

    -- 1P first_person_unit must never get redirects — 1P animations work by
    -- default. See feedback_animation_remap_rules. 1P unit has is_local=false
    -- (same as husks), so we MUST identify it by its captured ref. v0.9.69
    -- crashed when is_local was used to protect 1P because it ALSO skipped
    -- redirects on the 3P body. Moved AHEAD of state lookups so we don't
    -- waste work on 1P events.
    if _local_fp_unit and unit == _local_fp_unit then
        return func(unit, event_name, ...)
    end

    local is_local = _is_local_player_unit(unit)
    if not is_local then _last_3p_unit = unit end

    -- v0.12.35 — resolve career FROM THE UNIT, not the local player. Husks of
    -- remote players need their OWN career to drive redirects; using the
    -- local viewer's career hijacked every other player's animations whenever
    -- their career/weapon didn't happen to match ours. Falls back to the local
    -- career only if the unit lookup fails (e.g. very early in spawn).
    local career = _unit_career_name(unit) or (is_local and _local_career_name()) or nil
    local state = _state_for(unit)

    -- #536 consolidated reload router. Unit.animation_event is wt's singleton
    -- hot funnel; _wt_reload_3p supplies only a helper so VMF never sees a
    -- duplicate hook registration. Re-arm the receiver-native volley stance,
    -- then dispatch the unchanged generic reload token through the engine.
    local reload_router = (event_name == "reload" or event_name == "reload_last")
        and WT.reload_3p_route
    if reload_router then
        local reload_stance, reload_target = reload_router(unit, event_name, state, career, is_local)
        if reload_target then
            pcall(func, unit, reload_stance)
            return func(unit, reload_target, ...)
        end
    end

    if _log_anims then
        local _al_tag = is_local and "3P-body" or "3P-husk"
        local is_combat = event_name:sub(1, 7) == "attack_" or event_name:sub(1, 5) == "push_" or event_name:sub(1, 3) == "to_" or event_name:sub(1, 6) == "parry_"
        local exists = _safe_has_anim(unit, event_name)
        local suffix = exists and "" or " [MISSING]"
        if is_combat then
            if not _animlog_last_was_attack then
                local s_tmpl = state and state.template
                local s_key = state and state.key
                local hdr = "--- [template: " .. tostring(s_tmpl) .. "] [key: " .. tostring(s_key) .. "] [career: " .. tostring(career) .. "] ---"
                mod:info(hdr)
                mod:echo("--- " .. tostring(s_key or s_tmpl) .. " ---")
            end
            _animlog_last_was_attack = true
            local msg = _al_tag .. " " .. event_name .. suffix
            mod:info(msg)
            mod:echo(msg)
        else
            _animlog_last_was_attack = false
            mod:info("[animlog] " .. _al_tag .. " " .. event_name .. suffix)
        end
    end

    -- WP-WT-06: the ordered decision is _wt_anim_resolver.decide (pure). The
    -- hook keeps the call style per mode: flail and global_native return the
    -- engine call; force calls the captured original; every other mode pcalls
    -- and returns nothing (swallowed errors are counted, WP-WT-08).
    _decide_unit = unit
    local ctx = _decide_ctx
    ctx.event, ctx.career, ctx.state = event_name, career, state
    local mode, delivered, info = _resolver.decide(ctx)
    _decide_unit = nil

    if mode == "flail" then
        return func(unit, delivered, ...)
    end

    if info.remap_miss then
        -- The remap step's lookup, under the names the friends-only dev
        -- overlay reads (it ran inside the remap step before WP-WT-06).
        local target, target_capability = info.remap_target, info.remap_target_capability -- luacheck: ignore target target_capability
    end

    if _log_anims then
        if info.redir_fail_override then
            mod:info("  REDIR FAIL: " .. info.redir_fail_override .. " not on unit")
        end
        if info.redir_fail_alt then
            mod:info("  REDIR FAIL: " .. info.redir_fail_alt .. " not on unit")
        end
    end

    if mode == "remap" then
        local target = delivered
        if _log_anims then
            local msg = "  REMAP " .. event_name .. " -> " .. target
            mod:info(msg)
            mod:echo(msg)
        end
        -- v0.12.88-dev: sampled _dbg trace (1-in-N) of the cross-character
        -- REMAP path, with career so wrong-career remaps are visible.
        _anim_event_remap_count = _anim_event_remap_count + 1
        if _anim_event_remap_count % _ANIM_EVENT_SAMPLE_REMAP_N == 0 then
            _dbg("[wt:anim] event=REMAP src=%s -> tgt=%s career=%s tmpl=%s key=%s sample=%d",
                tostring(event_name), tostring(target), tostring(career),
                tostring(state.template), tostring(state.key), _anim_event_remap_count)
        end
        local ok, err = pcall(func, unit, target, ...)
        if not ok then _note_anim_swallow(target, err) end
        return
    end

    if mode == "force" then
        -- Force-fire bypasses this hook: the remap-table path corrupts the
        -- billhook state machine for these events (v0.9.43).
        if _log_anims then
            local msg = "  FORCE " .. event_name .. " -> " .. delivered
            mod:info(msg)
            mod:echo(msg)
        end
        local ok, err = pcall(_original_animation_event, unit, delivered)
        if not ok then _note_anim_swallow(delivered, err) end
        return
    end

    if mode == "career" then
        if _log_anims then
            local msg = "  REDIR " .. event_name .. " -> " .. delivered
            mod:info(msg)
            mod:echo(msg)
        end
        local ok, err = pcall(func, unit, delivered, ...)
        if not ok then _note_anim_swallow(delivered, err) end
        return
    end

    if mode == "global_native" then
        return func(unit, delivered, ...)
    end

    if mode == "suffix" and _log_anims then mod:info("  SUFFIX -> " .. delivered) end

    -- career_pass, global, suffix and pass: pcall, return nothing.
    local ok, err = pcall(func, unit, delivered, ...)
    if not ok then _note_anim_swallow(delivered, err) end
end)

-- Pull item_data for the slot being wielded and copy template/key into the
-- per-unit state. Shared by both wield hooks below.
local function _populate_unit_state_from_wield(self, slot_name)
    local unit = self._unit
    if not unit then return end
    local equipment = self._equipment or self.equipment
    local slots = equipment and equipment.slots
    local slot_data = slots and slots[slot_name]
    local item_data = slot_data and slot_data.item_data
    if not item_data then return end
    local s = _state_for(unit)
    if s then
        local ok, cwv = pcall(get_mod, "character_weapon_variants")
        cwv = ok and cwv or nil
        s.template = _cwv_effective_template.resolve(item_data, cwv,
            rawget(_G, "Weapons"), unit, slot_name)
        s.key = item_data.key
    end
end

-- Local-player wield. Populates state AND captures the 1P hands unit ref
-- (needed for the redirect-skip early-return in the animation_event hook).
-- v0.12.77 (Issue #26): converted to `mod:safe_hook` — this hook fans out
-- to per-unit state population + diagnostic dumps; a raise inside here
-- previously could silently kill every later wield consumer in the chain
-- (cosmetics_tweaker / LA / cwv all stack on the same Class.method).
-- v0.12.84-dev: promoted to `mod:traced_hook` (Layer 3) — wield is event-rate
-- (one fire per slot swap, NOT per-frame), so trace lines are safe. With
-- enable_debug_logging on, every wield emits paired
-- `[wt:trace] event=enter|exit class=SimpleInventoryExtension method=wield`
-- lines. Catches "did the wield hook fire?" diagnostics without grepping
-- through downstream state population logs.
mod:traced_hook("SimpleInventoryExtension", "wield", function(func, self, slot_name, ...)
    _populate_unit_state_from_wield(self, slot_name)

    -- Local-only side effects: capture the 1P hands unit ref and log details.
    local ok, pm = pcall(function() return Managers.player end)
    if ok and pm then
        local player = pm:local_player()
        if player and self._unit == player.player_unit then
            _local_fp_unit = self._first_person_unit
            if _log_anims then
                local s = _state_for(self._unit)
                mod:info("[WIELD] slot=" .. tostring(slot_name) .. " template=" .. tostring(s and s.template) .. " key=" .. tostring(s and s.key))
                local equipment = self._equipment or self.equipment
                local slot_data = equipment and equipment.slots and equipment.slots[slot_name]
                local item_data = slot_data and slot_data.item_data
                if item_data then
                    for k, v in pairs(item_data) do
                        if type(v) == "string" or type(v) == "number" or type(v) == "boolean" then
                            mod:info("[WIELD]   " .. tostring(k) .. " = " .. tostring(v))
                        end
                    end
                else
                    mod:info("[WIELD] item_data is nil, slot_data=" .. tostring(slot_data))
                end
            end

            -- v0.12.74-dev: debug-mode wield diagnostic. Separate from the
            -- `_log_anims`/`/animlog`-driven block above so users can enable
            -- the universal `enable_debug_logging` toggle from the VMF
            -- settings panel without also touching the chat-command
            -- animation log. Cache the toggle once to avoid two `mod:get`
            -- calls per wield. (v0.12.81-dev: renamed from `wt_debug_mode`.)
            --
            -- Fields chosen are the ones that drive 3P presentation on
            -- the receiver: career_name (3P skeleton selector — see
            -- _3p_state_machine_paths in _wt_diagnostics.lua), item_key, template,
            -- and the template's `anim_event_3p` + `wield_anim_3p`
            -- (the per-template default 3P clip names). The actual 3P
            -- skeleton path is derived from career_name via the profile
            -- (e.g. `wh_` -> witch_hunter base, `es_` -> empire_soldier).
            local s = _state_for(self._unit)
            local equipment = self._equipment or self.equipment
            local slot_data = equipment and equipment.slots and equipment.slots[slot_name]
            local item_data = slot_data and slot_data.item_data
            local item_key = (item_data and (item_data.key or item_data.name)) or "?"
            local template = (s and s.template) or (item_data and item_data.template) or "?"
            local tmpl_tbl = Weapons and Weapons[template]
            local anim_event_3p = (tmpl_tbl and tmpl_tbl.anim_event_3p) or "?"
            local wield_anim_3p = (tmpl_tbl and tmpl_tbl.wield_anim_3p) or "?"
            local career_name = self._career_name or "?"
            _dbg("[wield] slot=%s career=%s key=%s template=%s anim_event_3p=%s wield_anim_3p=%s",
                tostring(slot_name), tostring(career_name),
                tostring(item_key), tostring(template),
                tostring(anim_event_3p), tostring(wield_anim_3p))
        end
    end
    return func(self, slot_name, ...)
end)

-- Husk (remote-player) wield. SEPARATE CLASS from SimpleInventoryExtension —
-- per unit_extension_templates.lua, husk_extensions uses SimpleHuskInventoryExtension
-- (line 71). v0.12.35 hooked only the self-owned class, so remote players'
-- weapon switches never populated _unit_state[husk_unit] on the local viewer's
-- machine, and the animation_event hook had no per-husk weapon info to drive
-- redirects. Adding the parallel hook here completes the per-unit state plumbing
-- for the multiplayer case.
--
-- No local side effects — husks never represent the local viewer's 1P hands.
-- v0.12.77 (Issue #26): converted to `mod:safe_hook` — same chain-isolation
-- rationale as the local-player wield above. Husk wield is the entry point
-- for cross-character 3P remap on every non-local peer in multiplayer.
mod:safe_hook("SimpleHuskInventoryExtension", "wield", function(func, self, slot_name, ...)
    _populate_unit_state_from_wield(self, slot_name)
    return func(self, slot_name, ...)
end)

-- ============================================================================
-- Exports (non-hot-path cross-module reads). The entry's stayed code re-localizes
-- each of these: the keep-previewer pose fix (_resolve_preview_wield_event +
-- _safe_has_anim), the in-mission mesh-swap spawn path (_unit_career_name), the
-- port-pipeline longbow template patchers that mutate _3p_template_remaps, and
-- the /wt_regression_test check bodies that probe _unit_state / _suffix_career_map.
-- ============================================================================
WT.safe_has_anim               = _safe_has_anim
WT.resolve_preview_wield_event = _resolve_preview_wield_event
WT.unit_career_name            = _unit_career_name
WT.unit_state                  = _unit_state
WT.suffix_career_map           = _suffix_career_map
WT.three_p_template_remaps     = _3p_template_remaps
WT.anim_state_policy           = _anim_state_policy
WT.anim_redirect               = _anim_redirect
WT.career_anim_redirect        = _career_anim_redirect
WT.three_p_key_remaps          = _3p_key_remaps
WT.three_p_remap_triggers      = _3p_remap_triggers
WT.billhook_kruber_contract = function()
    local map = _3p_template_remaps.two_handed_billhooks_template
    map = map and map.es_
    local missing = {}
    for _, event in ipairs(_billhook_effective_3p_events) do
        if not ((map and map[event]) or _polearm_native_3p_events[event]) then
            missing[#missing + 1] = event
        end
    end
    return missing, map
end
