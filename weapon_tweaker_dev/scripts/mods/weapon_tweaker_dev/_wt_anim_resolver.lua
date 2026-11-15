-- _wt_anim_resolver.lua -- pure 3P animation decision for Weapon Tweaker (WP-WT-06).
--
-- Owns the redirect and remap data and the one decision function the
-- Unit.animation_event funnel in _wt_anim_remap.lua calls. Pure: no engine
-- globals, no mod handle. Whether a unit authors an event is asked through a
-- caller-supplied `has_event(name)` function; the funnel builds it from its own
-- pcall-guarded engine check. Tables keep their identity (the funnel, /info,
-- the _wt_anim_remap_data builder and the exports alias them), and their
-- values are the ones previously defined in _wt_anim_remap.lua, unchanged.
--
-- decide(ctx) runs the funnel's ordered steps: weapon-identity reset and remap
-- selection on `to_*` events, flail block, per-unit remap and force-fire,
-- career-aware redirect, global redirect, suffix redirect, pass-through. It
-- returns mode, delivered event, info. Modes: flail, remap, force, career,
-- career_pass, global_native, global, suffix, pass. The caller performs the
-- engine call in the style each mode had before (see _wt_anim_remap.lua).

local M = {}

local _anim_redirect = {
    to_repeating_crossbow            = "to_repeating_crossbow_elf",
    to_repeating_crossbow_noammo     = "to_repeating_crossbow_elf_noammo",
    to_es_longbow                    = "to_longbow",
    to_es_longbow_noammo             = "to_longbow_noammo",
    attack_swing_down_left_axe       = "attack_swing_down_left",
    push_stab                        = "attack_swing_stab",
    attack_swing_stab_lh             = "attack_swing_stab",
}

-- Career-aware redirects for events that are phantom entries on all skeletons.
-- Key = event to intercept, value = { alt, character_prefix }
-- When the career does NOT match the prefix, redirect to alt.
-- CLARIFY: `invert = true` flips the rule — redirect when the career DOES match
-- the prefix (used when the native skeleton lacks the wield event despite being
-- "this character's weapon", e.g. Saltzpyre's `to_1h_falchion` is missing on
-- the WHC skeleton itself, so we need to redirect ON wh_priest career).
-- `overrides` is a per-career-name (not prefix) override that takes precedence
-- over both the prefix rule and `alt`.
local _career_anim_redirect = {
    to_longbow                       = { alt = "to_es_longbow",                 prefix = "we_" },
    to_longbow_noammo                = { alt = "to_es_longbow_noammo",          prefix = "we_" },
    to_repeating_crossbow_elf        = { alt = "to_repeating_crossbow",         prefix = "we_" },
    to_repeating_crossbow_elf_noammo = { alt = "to_repeating_crossbow_noammo",  prefix = "we_" },
    -- Note: `wh_priest` here is a full career name acting as a prefix; safe
    -- because no other `wh_*` career shares its first 9 chars.
    to_1h_falchion                   = { alt = "to_1h_hammer",                  prefix = "wh_priest", invert = true },
    to_1h_sword                      = { alt = "to_1h_hammer",                  prefix = "wh_priest", invert = true },
    to_1h_axe                        = { alt = "to_1h_sword",                   prefix = "bw_", invert = true,
                                         overrides = { wh_priest = "to_1h_hammer" } },
    to_1h_crowbill                   = { alt = "to_1h_sword",                   prefix = "bw_",
                                         overrides = { wh_priest = "to_1h_hammer" } },
    to_1h_hammer                     = { alt = "to_1h_sword",                   prefix = "we_", invert = true },
    to_1h_hammer_shield_priest       = { alt = "to_1h_hammer_shield",           prefix = "wh_priest" },
    to_1h_spear_shield               = { alt = "to_es_deus_01",                 prefix = "we_",
                                         overrides = { wh_priest = "to_1h_hammer_shield" } },
    to_es_deus_01                    = { alt = "to_1h_spear_shield",           prefix = "es_",
                                         overrides = { wh_priest = "to_1h_hammer_shield" } },
    to_spear                         = { alt = "to_polearm",                   prefix = "we_",
                                         overrides = { wh_captain = "to_2h_billhook", wh_bountyhunter = "to_2h_billhook", wh_zealot = "to_2h_billhook", wh_priest = "to_1h_hammer" } },
    to_polearm                       = { alt = "to_spear",                     prefix = "es_",
                                         overrides = { wh_captain = "to_2h_billhook", wh_bountyhunter = "to_2h_billhook", wh_zealot = "to_2h_billhook", wh_priest = "to_1h_hammer" } },
    -- QUESTION: `prefix = "wh_"` here means "redirect when career does NOT
    -- start with wh_". But ALL non-wh careers have explicit `overrides` entries
    -- below, so the `alt = "to_polearm"` fallback only triggers for careers
    -- not listed (none currently). The `alt` is effectively dead — every
    -- non-wh career maps via overrides. Intentional defensive default, or
    -- just leftover?
    to_2h_billhook                   = { alt = "to_polearm",                   prefix = "wh_",
                                         overrides = { es_mercenary = "to_polearm", es_huntsman = "to_polearm", es_knight = "to_polearm", es_questingknight = "to_polearm",
                                                       we_waywatcher = "to_spear", we_maidenguard = "to_spear", we_shade = "to_spear", we_thornsister = "to_spear",
                                                       wh_priest = "to_1h_hammer" } },
    to_2h_sword                      = { alt = "to_2h_sword_we",                prefix = "we_", invert = true },
    to_2h_sword_we                   = { alt = "to_bastard_sword",              prefix = "we_",
                                         overrides = { wh_priest = "to_1h_hammer",
                                                       wh_captain = "to_1h_sword", wh_bountyhunter = "to_1h_sword", wh_zealot = "to_1h_sword" } },
    to_dual_hammers_priest           = { alt = "to_dual_hammers",               prefix = "wh_" },
    to_dual_axes                     = { alt = "to_dual_hammers",               prefix = "dr_slayer" },
    -- v0.12.119: Sienna's Flaming Flail (bw_1h_flail_flaming) wield on non-bw
    -- receivers — DECISIONS:36 flagged the missing wield redirect as the cause
    -- of the broken wield stance (the H2 attack redirect in the flail block
    -- already existed; the wield event did not). `to_1h_flail` is the universal
    -- Empire-flail wield that already works on every character via es_1h_flail.
    to_1h_flail_flaming              = { alt = "to_1h_flail",                   prefix = "bw_",
                                         overrides = { wh_priest = "to_1h_hammer" } },
}

-- Suffix-based animation redirect: when an event ending in a weapon suffix
-- doesn't exist on the skeleton, swap the suffix based on career.
-- Checked longest-first to avoid e.g. "_spear" matching "_2h_heavy_spear".
-- CLARIFY: order matters because `event_name:sub(-#suffix) == suffix` is a
-- substring match — without longest-first, `to_es_deus_01` would match
-- `_es_deus_01` correctly but `to_1h_spear_shield` would match `_spear` first
-- (both 6 chars from end onwards differ but the shorter match wins by order).
local _suffix_order = { "_2h_sword_we", "_bastard_sword", "_1h_spear_shield", "_es_deus_01", "_2h_billhook", "_polearm", "_spear" }
local _suffix_career_map = {
    ["_2h_sword_we"] = {
        es_mercenary = "_bastard_sword", es_huntsman = "_bastard_sword", es_knight = "_bastard_sword", es_questingknight = "_bastard_sword",
        wh_captain = "_1h_sword", wh_bountyhunter = "_1h_sword", wh_zealot = "_1h_sword",
        wh_priest = "_1h_hammer",
    },
    ["_1h_spear_shield"] = {
        es_mercenary = "_es_deus_01", es_huntsman = "_es_deus_01", es_knight = "_es_deus_01", es_questingknight = "_es_deus_01",
        dr_ranger = "_1h_hammer_shield", dr_ironbreaker = "_1h_hammer_shield", dr_slayer = "_1h_hammer_shield", dr_engineer = "_1h_hammer_shield",
        wh_captain = "_1h_sword_shield", wh_bountyhunter = "_1h_sword_shield", wh_zealot = "_1h_sword_shield",
        wh_priest = "_1h_hammer_shield",
    },
    ["_es_deus_01"] = {
        we_waywatcher = "_1h_spear_shield", we_maidenguard = "_1h_spear_shield", we_shade = "_1h_spear_shield", we_thornsister = "_1h_spear_shield",
        wh_captain = "_1h_sword_shield", wh_bountyhunter = "_1h_sword_shield", wh_zealot = "_1h_sword_shield",
        wh_priest = "_1h_hammer_shield",
    },
    ["_spear"] = {
        wh_captain = "_2h_billhook", wh_bountyhunter = "_2h_billhook", wh_zealot = "_2h_billhook",
        wh_priest = "_1h_hammer",
    },
    ["_polearm"] = {
        we_waywatcher = "_spear", we_maidenguard = "_spear", we_shade = "_spear", we_thornsister = "_spear",
        wh_captain = "_2h_billhook", wh_bountyhunter = "_2h_billhook", wh_zealot = "_2h_billhook",
        wh_priest = "_1h_hammer",
    },
    ["_2h_billhook"] = {
        es_mercenary = "_polearm", es_huntsman = "_polearm", es_knight = "_polearm", es_questingknight = "_polearm",
        we_waywatcher = "_spear", we_maidenguard = "_spear", we_shade = "_spear", we_thornsister = "_spear",
        wh_priest = "_1h_hammer",
    },
}

local function _try_suffix_redirect(has_event, event_name, career)
    for _, suffix in ipairs(_suffix_order) do
        local slen = #suffix
        if event_name:sub(-slen) == suffix then
            local map = _suffix_career_map[suffix]
            local target_suffix = map and map[career]
            if target_suffix then
                local base = event_name:sub(1, -(slen + 1))
                local target = base .. target_suffix
                if has_event(target) then
                    return target
                end
            end
            return nil
        end
    end
    return nil
end


-- ============================================================================
-- INVENTORY-PREVIEW WIELD POSE (3P-ONLY) — receiver-native stance correction
-- ============================================================================
-- v0.12.146-dev. The keep inventory previewer (MenuWorldPreviewer, derived
-- from HeroPreviewer) fires the wield anim on the 3P body directly at spawn:
--   wield = wield_anim_career_3p[career] or wield_anim_career[career]
--                                        or item_template.wield_anim
-- (world_hero_previewer.lua:1059-1066). It does NOT route that event through
-- our `Unit.animation_event` hook's `_career_anim_redirect` path, because the
-- preview `character_unit` has NO career_system / inventory_system extension —
-- so `_unit_career_name(unit)` returns nil in the hook and the redirect is a
-- no-op there (gated on a resolved career at line ~1544).
--
-- For cross-character ports whose `wt_wield_patches.lua` entry omits the
-- receiver's career prefix (e.g. `two_handed_swords_wood_elf_template` lists
-- only `wh_*`, so on a Kruber `es_*` career `wield_anim_career_3p[es_*]` is
-- nil), the previewer falls back to the elf template's base
-- `wield_anim = "to_2h_sword_we"` and fires it on Kruber's empire_soldier body,
-- which does not author that elf event -> no wield transition -> the body holds
-- its previous/idle stance (the "missing pose" symptom; no T-pose, see
-- feedback_vt2_no_tpose_default_stance). In-mission the same event is redirected
-- by `_career_anim_redirect.to_2h_sword_we` (alt = "to_bastard_sword" for the
-- non-we_ branch), which is why the mission render is correct.
--
-- This resolver re-uses the SAME `_career_anim_redirect` data the in-mission
-- hook uses (no parallel pose table) to compute the receiver-native wield event
-- for one (event, career) pair, WITHOUT firing. The spawn hook below then plays
-- it on the 3P preview body only if (a) it differs from what the engine already
-- fired and (b) the body actually authors it. Strictly 3P: the preview world has
-- no 1P unit, and we touch only `self.character_unit`.
--
-- Resolution mirrors the `_career_anim_redirect` branch in the animation_event
-- hook (overrides -> prefix/invert -> alt), then a suffix-redirect fallback:
local function _resolve_preview_wield_event(has_event, event_name, career)
    if not event_name or not career then return nil end
    local redir = _career_anim_redirect[event_name]
    if redir then
        if redir.overrides and redir.overrides[career]
                and has_event(redir.overrides[career]) then
            return redir.overrides[career]
        end
        local matches_prefix = career:sub(1, #redir.prefix) == redir.prefix
        local should_redirect = redir.invert and matches_prefix
                                or (not redir.invert and not matches_prefix)
        if should_redirect and has_event(redir.alt) then
            return redir.alt
        end
        return nil
    end
    -- Suffix-based fallback (e.g. *_2h_billhook -> *_polearm) for events not
    -- listed in _career_anim_redirect. _try_suffix_redirect already verifies the
    -- target is authored on the body before returning it.
    return _try_suffix_redirect(has_event, event_name, career)
end

-- ============================================================================
-- ANIMATION REMAPPING — READ FIRST
-- ============================================================================
-- 1P (first-person) animations are UNIVERSAL across all six characters and
-- all weapons. The first_person_base unit is shared, so any weapon's 1P state
-- machine and clips play correctly on any character's first-person view by
-- default. We never override anim_event (1P), wield_anim (1P), or
-- state_machine per character — only 3P fields need cross-character work.
--
-- Every remap table and every redirect in this file targets the 3P body
-- (player_unit + husks). The 1P first_person_unit gets an early return in the
-- animation_event hook so it stays untouched. See feedback_animation_remap_rules
-- and feedback_1p_animations_universal memory notes for the full rule.
--
-- When a remap table key looks like a 1P event name (e.g.
-- "attack_swing_charge_stab" — authored for the elf spear's 1P state machine),
-- it's there because the SAME event-name string also fires on the 3P body
-- where the empire-soldier skeleton has no clip for it. The remap value is the
-- 3P-body substitute. The 1P side fires the unmodified event and plays
-- correctly on first_person_base — we don't touch it.
-- ============================================================================

-- 3P body event remapping: player_unit IS the 3P body (receives anim_event_3p).
-- The non-player unit is the 1P hands (receives anim_event) — universal,
-- never remapped here.
-- When a cross-career weapon is equipped, remap attack events on player_unit
-- to the target weapon's anim_event_3p values so proper 3P animations play.

-- Elf spear actions → billhook 3P events (for Saltzpyre wielding elf spear)
local _3p_remap_spear_to_billhook = {
    attack_swing_charge_right    = "attack_swing_charge_left_diagonal",
    attack_swing_charge_left     = "attack_swing_stab_charge",
    attack_swing_down_right      = "attack_swing_stab",
    attack_swing_down_left_axe   = "attack_swing_left_diagonal",
    attack_swing_down_left       = "attack_swing_stab",
    attack_swing_right           = "attack_swing_left_diagonal",
    attack_swing_heavy_right     = "attack_swing_heavy_left_diagonal",
    attack_swing_heavy           = "attack_swing_heavy_stab",
    push_stab                    = "attack_swing_left_diagonal",
    attack_swing_stab_lh         = "attack_swing_stab",
    attack_swing_charge          = "attack_swing_stab_charge",
    attack_swing_charge_stab     = "attack_swing_charge_left_diagonal",
}

-- Polearm/heavy spear → billhook 3P fixes (for Saltzpyre)
-- Only remap events that are MISSING or broken on billhook skeleton.
-- Leave working events alone — elf spear table remaps interfere if shared.
local _3p_remap_polearm_to_billhook = {
    attack_swing_stab_lh         = "attack_swing_stab",
}

-- Elf spear 1P actions → Kruber polearm-compatible 3P events.
-- Only remap events that genuinely crash or don't exist on the
-- polearm skeleton. Let others play natively.
local _3p_remap_spear_to_polearm = {
    attack_swing_down_left_axe   = "attack_swing_down_left",
    attack_swing_left            = "attack_swing_down_left",
}

-- Billhook 1P events → polearm-compatible 3P events.
-- Cross-career equip sends the 1P anim_event (not anim_event_3p) to
-- both units. These billhook-specific events are phantom on the polearm
-- skeleton. Remap lights → lights, heavies → heavies, charges → charges.
local _3p_remap_billhook_to_polearm = {
    -- Heavy 1 (thrust): charge + release
    attack_swing_charge_stab         = "attack_swing_charge_right",
    attack_swing_stab_charge         = "attack_swing_charge_right",
    attack_swing_heavy_stab          = "attack_swing_heavy_right",
    -- Heavy 2 (overhead): charge + release
    attack_swing_charge_down         = "attack_swing_charge",
    attack_swing_charge_left_diagonal = "attack_swing_charge",
    attack_swing_heavy_down          = "attack_swing_heavy",
    attack_swing_heavy_left_diagonal = "attack_swing_heavy",
    -- Lights
    attack_swing_left_diagonal       = "attack_swing_down_left",
    attack_swing_stab                = "attack_swing_right",
    attack_swing_stab_02             = "attack_swing_right",
    attack_swing_heavy_left          = "attack_swing_heavy",
    attack_swing_down                = "attack_swing_down_right",
    push_stab                        = "attack_swing_right",
    attack_swing_left                = "attack_swing_down_left",
}

-- Source-derived effective 3P vocabulary. For each Billhook action the engine fires
-- `anim_event_3p or anim_event` (weapon_unit_extension.lua:512). The Kruber polearm
-- vocabulary comes from halberds.lua. A Billhook event is complete when it is explicitly
-- remapped or is already native on the polearm body.
local _billhook_effective_3p_events = {
    "attack_swing_stab_charge", "attack_swing_charge_left_diagonal",
    "attack_swing_heavy_left_diagonal", "attack_swing_heavy_stab",
    "attack_swing_stab", "attack_swing_left_diagonal", "attack_swing_down",
    "attack_push", "parry_pose",
}
local _polearm_native_3p_events = {
    attack_swing_charge_left=true, attack_swing_charge_right=true,
    attack_swing_down_left=true, attack_swing_down_right=true,
    attack_swing_heavy_right=true, attack_swing_heavy=true,
    attack_swing_right=true, attack_push=true, parry_pose=true,
}

local _3p_remap_spear_shield_to_deus = {
    attack_swing_stab_lh             = "attack_swing_stab",
}

local _3p_remap_deus_to_spear_shield = {
    attack_swing_up                  = "attack_swing_stab_lh",
}

-- Career-aware remap triggers: event → { career_prefix = remap_table, ... }
-- "_default" key used when no career-specific entry matches.
local _3p_remap_triggers = {
    to_spear = {
        _default = _3p_remap_spear_to_polearm,
        wh_      = _3p_remap_spear_to_billhook,
        -- Kerillian's elf skeleton authors the spear moveset natively; the
        -- _default remap was built for Kruber's polearm skeleton and breaks
        -- her down_left / left attacks if applied. Mirrors the wh_ = false
        -- pattern on to_2h_billhook below.
        we_      = false,
    },
    to_polearm = {
        _default = _3p_remap_billhook_to_polearm,
        es_      = _3p_remap_spear_to_polearm,
        wh_      = _3p_remap_spear_to_billhook,
    },
    to_2h_billhook = {
        _default = _3p_remap_billhook_to_polearm,
        wh_      = false,
    },
    to_1h_spear_shield = {
        _default = _3p_remap_spear_shield_to_deus,
    },
    to_es_deus_01 = {
        _default = _3p_remap_spear_shield_to_deus,
        we_      = _3p_remap_deus_to_spear_shield,
    },
}

-- CLARIFY: returns either a remap table (truthy) or `false` (a deliberate
-- "no remap" entry like `to_2h_billhook.wh_ = false`). Caller stores the
-- result on the per-unit state (see `_unit_state` below) — `false` correctly
-- clears any prior remap; only `nil` (no entry at all) preserves prior state.
local function _resolve_3p_remap(event_name, career)
    local trigger = _3p_remap_triggers[event_name]
    if not trigger then return nil end
    if not career then return trigger._default end
    for prefix, tbl in pairs(trigger) do
        if prefix ~= "_default" and career:sub(1, #prefix) == prefix then
            return tbl
        end
    end
    return trigger._default
end

local function _resolve_template_remap(template_remaps, template_name, career)
    local entry = template_remaps[template_name]
    if not entry then return nil end
    if career then
        for prefix, tbl in pairs(entry) do
            if prefix ~= "_default" and career:sub(1, #prefix) == prefix then
                return tbl
            end
        end
    end
    return entry._default
end

local _3p_key_remaps = {
    we_1h_sword = {
        we_ = false,
        _default = {
            attack_swing_stab          = "attack_swing_down",                 -- L4 stab → vertical
            attack_swing_charge_down   = "attack_swing_charge_left_diagonal", -- H1 charge windup (also L1 charge gains a windup)
            attack_swing_charge_left   = "attack_swing_charge_right_pose",    -- H2 charge windup
            attack_swing_heavy_left_up = "attack_swing_heavy_right",          -- H2 release → heavy right swing
            attack_swing_charge_right_diagonal_pose = "attack_swing_charge_left_diagonal", -- H3 charge → vertical (matches H1; also affects L2 charge — windup pose only, brief)
            attack_swing_heavy_down_right = "attack_swing_heavy_down",        -- H3 release → vertical (was horizontal)
        },
    },
    bw_sword = {
        dr_ = {
            -- 3-position heavy chain. Differentiate variants:
            --   H1 from idle (charge_left/heavy)            → elf H2 (right swing)
            --   H2 (charge_right_pose/heavy_right)          → elf H1 (vertical heavy)
            --   H3+ (charge_left_pose/heavy) — release is the same event as H1
            --   so it inherits the right-swing; charge gets right-pose windup to match.
            attack_swing_charge_left       = "attack_swing_charge_right_pose",
            attack_swing_heavy             = "attack_swing_heavy_right",
            attack_swing_charge_right_pose = "attack_swing_charge_left_diagonal",
            attack_swing_heavy_right       = "attack_swing_heavy_down",
            attack_swing_charge_left_pose  = "attack_swing_charge_right_pose", -- H3+ chain windup matches right swing
        },
    },
    es_1h_sword = {
        -- one_handed_swords_template_1 (shared with bw_sword) — same heavy chain.
        dr_ = {
            attack_swing_charge_left       = "attack_swing_charge_right_pose",
            attack_swing_heavy             = "attack_swing_heavy_right",
            attack_swing_charge_right_pose = "attack_swing_charge_left_diagonal",
            attack_swing_heavy_right       = "attack_swing_heavy_down",
            attack_swing_charge_left_pose  = "attack_swing_charge_right_pose", -- H3+ chain windup matches right swing
        },
    },
}

local function _resolve_key_remap(weapon_key, career)
    local entry = _3p_key_remaps[weapon_key]
    if not entry then return nil end
    if career then
        for prefix, tbl in pairs(entry) do
            if prefix ~= "_default" and career:sub(1, #prefix) == prefix then
                return tbl
            end
        end
    end
    return entry._default
end


-- ctx = { event, career, state, has_event, template_remaps, remap_identity,
--         info (optional table reused by the caller; cleared here) }
-- info.remap_miss is true when state.remap existed but supplied no usable
-- target; info.remap_target / remap_target_capability carry that lookup.
-- info.redir_fail_override / redir_fail_alt name career-redirect targets the
-- unit does not author (the funnel logs them under /animlog).
function M.decide(ctx)
    local event_name, career, state, has_event = ctx.event, ctx.career, ctx.state, ctx.has_event
    local info = ctx.info
    if info then
        info.remap_miss, info.remap_target, info.remap_target_capability = nil, nil, nil
        info.redir_fail_override, info.redir_fail_alt = nil, nil
    else
        info = {}
    end

    -- Reset this unit's 3P weapon remap on an actual weapon change. Non-weapon
    -- `to_` events (to_crouch / to_zoom / to_onground) keep the same identity
    -- and skip the clear. #112: the receiver career is part of the identity.
    local remap_id = state and ctx.remap_identity(state.template, state.key, career)
    if state and event_name:sub(1, 3) == "to_" and remap_id and remap_id ~= state.last_remap_id then
        state.last_remap_id = remap_id
        state.remap = nil
        state.remap_origin = nil
        if state.template then
            local tmpl_remap = _resolve_template_remap(ctx.template_remaps, state.template, career)
            if tmpl_remap then
                state.remap = tmpl_remap
                state.remap_origin = "template:" .. tostring(state.template)
            end
        end
        if not state.remap and state.key then
            local key_remap = _resolve_key_remap(state.key, career)
            if key_remap then
                state.remap = key_remap
                state.remap_origin = "key:" .. tostring(state.key)
            end
        end
        -- v0.12.64-dev: when neither template nor key resolution hits, the
        -- (possibly patcher-rewritten) wield event's trigger remap applies.
        if not state.remap then
            local trigger_remap = _resolve_3p_remap(event_name, career)
            if trigger_remap then
                state.remap = trigger_remap
                state.remap_origin = "trigger:" .. tostring(event_name)
            end
        end
    end

    -- Flails on non-native careers: these release events play the wrong
    -- animation or nothing on the cross-career body; the remap table cannot be
    -- used for them (it corrupts the state-machine chain), so the caller fires
    -- the substitute directly.
    if state and career then
        local target = nil
        if state.key == "es_1h_flail" then
            if career:sub(1, 3) ~= "wh_" then
                if event_name == "attack_swing_left"
                    or event_name == "attack_swing_heavy_left" then
                    target = "attack_swing_heavy"
                end
            else
                if event_name == "attack_swing_right" then
                    target = "attack_swing_right_diagonal"
                end
            end
        elseif state.key == "bw_1h_flail_flaming"
            and career:sub(1, 3) ~= "bw_" then
            if event_name == "attack_swing_heavy_left" then
                target = "attack_swing_heavy"
            end
        end
        if target then
            return "flail", target, info
        end
    end

    -- 3P attack remap (per unit), then the guarded force-fire path for
    -- state-machine-corrupting events on the spear-to-billhook remap.
    if state and state.remap then
        local target = state.remap[event_name]
        local target_capability = target and has_event(target)
        if target and target_capability then
            return "remap", target, info
        end
        info.remap_miss = true
        info.remap_target, info.remap_target_capability = target, target_capability
        local force_target = nil
        if state.remap == _3p_remap_spear_to_billhook then
            if event_name == "attack_swing_stab_02" then
                force_target = "attack_swing_left_diagonal"
            elseif event_name == "attack_swing_heavy_left" then
                force_target = "attack_swing_heavy_stab"
            elseif event_name == "attack_swing_heavy_stab" then
                force_target = "attack_swing_heavy_left_diagonal"
            end
        end
        if force_target and has_event(force_target) then
            return "force", force_target, info
        end
    end

    -- Career-aware redirects: phantom events exist on all skeletons but only
    -- play on the right character. A redirect also installs the event's
    -- trigger remap on the unit. v0.12.60: gated on a resolved career.
    local career_redir = _career_anim_redirect[event_name]
    if career_redir then
        if career_redir.overrides and career and career_redir.overrides[career] then
            local target = career_redir.overrides[career]
            if has_event(target) then
                local remap = _resolve_3p_remap(event_name, career)
                if remap and state then state.remap = remap end
                return "career", target, info
            end
            info.redir_fail_override = target
        end
        local matches_prefix = career and career:sub(1, #career_redir.prefix) == career_redir.prefix
        local should_redirect = career and (career_redir.invert and matches_prefix or (not career_redir.invert and not matches_prefix))
        if should_redirect then
            if has_event(career_redir.alt) then
                local remap = _resolve_3p_remap(event_name, career)
                if remap and state then state.remap = remap end
                return "career", career_redir.alt, info
            end
            info.redir_fail_alt = career_redir.alt
        end
        return "career_pass", event_name, info
    end

    -- Standard redirect: only when the original event is missing.
    local alt = _anim_redirect[event_name]
    if alt then
        if has_event(event_name) then
            return "global_native", event_name, info
        end
        if has_event(alt) then
            return "global", alt, info
        end
    end

    -- Suffix-based redirect: swap the weapon suffix by career.
    if career then
        local target = _try_suffix_redirect(has_event, event_name, career)
        if target then
            return "suffix", target, info
        end
    end

    return "pass", event_name, info
end

M.anim_redirect                = _anim_redirect
M.career_anim_redirect         = _career_anim_redirect
M.suffix_order                 = _suffix_order
M.suffix_career_map            = _suffix_career_map
M.remap_spear_to_billhook      = _3p_remap_spear_to_billhook
M.remap_polearm_to_billhook    = _3p_remap_polearm_to_billhook
M.remap_spear_to_polearm       = _3p_remap_spear_to_polearm
M.remap_billhook_to_polearm    = _3p_remap_billhook_to_polearm
M.billhook_effective_3p_events = _billhook_effective_3p_events
M.polearm_native_3p_events     = _polearm_native_3p_events
M.remap_spear_shield_to_deus   = _3p_remap_spear_shield_to_deus
M.remap_deus_to_spear_shield   = _3p_remap_deus_to_spear_shield
M.remap_triggers               = _3p_remap_triggers
M.key_remaps                   = _3p_key_remaps
M.try_suffix_redirect          = _try_suffix_redirect
M.resolve_preview_wield_event  = _resolve_preview_wield_event
M.resolve_3p_remap             = _resolve_3p_remap
M.resolve_template_remap       = _resolve_template_remap
M.resolve_key_remap            = _resolve_key_remap

return M
