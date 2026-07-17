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

local mod = get_mod("wt_dev")
local WT  = mod._wt

-- Hot-path handles the entry owns (published onto mod._wt before this dofile).
-- Captured as file-local upvalues so the per-event funnel never reads mod._wt.
local feature_enabled     = WT.feature_enabled
local _local_career_name  = WT.local_career_name
local _dbg                = WT.dbg
-- WT_DEV_OVERLAY_BEGIN:anim-picker-handle
local _wt_dev_anim_picker = WT.dev_anim_picker
-- WT_DEV_OVERLAY_END:anim-picker-handle
local MOD_VERSION         = WT.MOD_VERSION
local weapon_unlock_map   = WT.weapon_unlock_map
local _build_3p_template_remaps = WT.build_3p_template_remaps
local _cwv_effective_template = mod:dofile(
    "scripts/mods/weapon_tweaker_dev/_wt_cwv_effective_template")

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

-- pcall-guarded `Unit.has_animation_event`. Returns true only if the unit has
-- the named anim event. Used by every redirect/remap helper below — defined
-- BEFORE _try_suffix_redirect to avoid the forward-reference trap that bit
-- this codebase 5+ times (see feedback_lua_forward_reference.md).
local function _safe_has_anim(unit, event)
    local ok, result = pcall(Unit.has_animation_event, unit, event)
    return ok and result
end

local function _try_suffix_redirect(unit, event_name, career)
    for _, suffix in ipairs(_suffix_order) do
        local slen = #suffix
        if event_name:sub(-slen) == suffix then
            local map = _suffix_career_map[suffix]
            local target_suffix = map and map[career]
            if target_suffix then
                local base = event_name:sub(1, -(slen + 1))
                local target = base .. target_suffix
                if _safe_has_anim(unit, target) then
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
local function _resolve_preview_wield_event(body, event_name, career)
    if not event_name or not career then return nil end
    local redir = _career_anim_redirect[event_name]
    if redir then
        if redir.overrides and redir.overrides[career]
                and _safe_has_anim(body, redir.overrides[career]) then
            return redir.overrides[career]
        end
        local matches_prefix = career:sub(1, #redir.prefix) == redir.prefix
        local should_redirect = redir.invert and matches_prefix
                                or (not redir.invert and not matches_prefix)
        if should_redirect and _safe_has_anim(body, redir.alt) then
            return redir.alt
        end
        return nil
    end
    -- Suffix-based fallback (e.g. *_2h_billhook -> *_polearm) for events not
    -- listed in _career_anim_redirect. _try_suffix_redirect already verifies the
    -- target is authored on the body before returning it.
    return _try_suffix_redirect(body, event_name, career)
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
    local entry = _3p_template_remaps[template_name]
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
    -- WT_DEV_OVERLAY_BEGIN:info-animlog-row
    mod:echo("Anim log: " .. (_log_anims and "ON" or "OFF"))
    -- WT_DEV_OVERLAY_END:info-animlog-row
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
-- WT_DEV_OVERLAY_BEGIN:anim-force-commands
mod:command("animlog", "Toggle animation event logging", function()
    _log_anims = not _log_anims
    mod:echo("Animation logging: " .. (_log_anims and "ON" or "OFF"))
end)

mod:command("force3p", "Force a 3P animation event on local player (usage: /force3p attack_swing_stab)", function(event)
    -- CLARIFY: targets `player.player_unit` which is actually the 3P body
    -- (see CLAUDE.md "Animation Remapping"). Bypasses our own hook by calling
    -- `_original_animation_event` directly so the test isn't muddied by remap
    -- redirects — used to verify which raw events animate visibly on the
    -- currently-loaded weapon SM (per feedback_animation_remap_rules:
    -- has_animation_event TRUE does not guarantee visible playback).
    if not event then mod:echo("Usage: /force3p <event_name>") return end
    local player = Managers.player:local_player(1)
    if not player or not player.player_unit then mod:echo("No local player unit") return end
    local unit = player.player_unit
    local ok_h, has = pcall(Unit.has_animation_event, unit, event)
    has = ok_h and has
    mod:echo("force3p: " .. event .. " (exists=" .. tostring(has) .. ")")
    if has then
        if _original_animation_event then
            pcall(_original_animation_event, unit, event)
        else
            pcall(Unit.animation_event, unit, event)
        end
        mod:echo("  -> fired on player_unit")
    else
        mod:echo("  -> event not found on player_unit")
    end
end)

mod:command("force1p", "Force a 1P animation event on local player's first-person unit (usage: /force1p attack_swing_stab)", function(event)
    -- Mirror of force3p but targets the 1P hands unit captured in the wield
    -- hook. Used to probe whether the currently-wielded weapon's 1P SM has a
    -- visible animation for an event that's not referenced by the template
    -- (e.g. searching for a hidden stab on bastard_sword).
    if not event then mod:echo("Usage: /force1p <event_name>") return end
    if not _local_fp_unit then mod:echo("No 1P unit captured (wield a weapon first)") return end
    local unit = _local_fp_unit
    local ok_h, has = pcall(Unit.has_animation_event, unit, event)
    has = ok_h and has
    mod:echo("force1p: " .. event .. " (exists=" .. tostring(has) .. ")")
    if has then
        if _original_animation_event then
            pcall(_original_animation_event, unit, event)
        else
            pcall(Unit.animation_event, unit, event)
        end
        mod:echo("  -> fired on first_person_unit")
    else
        mod:echo("  -> event not found on first_person_unit")
    end
end)
-- WT_DEV_OVERLAY_END:anim-force-commands

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
local _ANIM_EVENT_SAMPLE_N = 60
local _ANIM_EVENT_SAMPLE_REMAP_N = 30
local _anim_event_call_count = 0
local _anim_event_remap_count = 0

-- #576's bounded live evidence belongs to the friends-only dev overlay. The
-- shared public path keeps the same remap behavior without issue-specific rows.
-- WT_DEV_OVERLAY_BEGIN:bounded-live-animation-probes
local _WT576_KEYS = {
    bw_ghost_scythe = true,
    we_spear = true,
    -- Axe+Shield variants share one template/remap but can retain either the
    -- vanilla donor key or their canonical CWV identity in per-unit state.
    dr_shield_axe = true,
    cwv_es_axe_shield = true,
    cwv_es_axe_shield_veteran = true,
}
local _WT576_SOURCE = {
    bw_ghost_scythe = {
        attack_push=true, attack_swing_charge_left=true, attack_swing_charge_left_diagonal=true,
        attack_swing_charge_right=true, attack_swing_heavy=true,
        attack_swing_heavy_left_diagonal=true, attack_swing_heavy_right=true,
        attack_swing_left=true, attack_swing_left_diagonal=true,
        attack_swing_left_diagonal_last=true, attack_swing_right=true,
        attack_swing_up_right=true, parry_pose=true, special_action=true, special_action_02=true,
    },
    we_spear = {
        attack_push=true, attack_swing_charge_left=true, attack_swing_charge_right=true,
        attack_swing_down_left=true, attack_swing_down_left_axe=true,
        attack_swing_down_right=true, attack_swing_heavy=true,
        attack_swing_heavy_right=true, attack_swing_right=true,
        parry_pose=true, push_stab=true,
    },
    dr_shield_axe = {
        attack_swing_charge=true, attack_swing_heavy=true,
        attack_swing_charge_right_pose=true, attack_swing_heavy_right=true,
        attack_swing_charge_left_diagonal_pose=true, attack_swing_heavy_down=true,
    },
    cwv_es_axe_shield = {
        attack_swing_charge=true, attack_swing_heavy=true,
        attack_swing_charge_right_pose=true, attack_swing_heavy_right=true,
        attack_swing_charge_left_diagonal_pose=true, attack_swing_heavy_down=true,
    },
    cwv_es_axe_shield_veteran = {
        attack_swing_charge=true, attack_swing_heavy=true,
        attack_swing_charge_right_pose=true, attack_swing_heavy_right=true,
        attack_swing_charge_left_diagonal_pose=true, attack_swing_heavy_down=true,
    },
}
local _wt576_seen, _wt576_count = {}, 0

local function _wt576_phases(key, source)
    if key == "dr_shield_axe" or key == "cwv_es_axe_shield"
        or key == "cwv_es_axe_shield_veteran" then
        local phase = {
            attack_swing_charge = "action_one.h1_charge",
            attack_swing_heavy = "action_one.h1_committed_attack",
            attack_swing_charge_right_pose = "action_one.h2_charge",
            attack_swing_heavy_right = "action_one.h2_committed_attack",
            attack_swing_charge_left_diagonal_pose = "action_one.h3_charge",
            attack_swing_heavy_down = "action_one.h3_committed_attack",
        }
        return { phase[source] or "action_transition" }
    elseif key == "we_spear" and source == "attack_swing_charge_right" then
        return { "action_one.h1_charge_start", "action_one.h1_charge_loop" }
    elseif key == "we_spear" and source == "attack_swing_heavy_right" then
        return { "action_one.h1_charge_release", "action_one.h1_committed_attack" }
    elseif source:find("charge", 1, true) then
        return { "action_one.charge_start", "action_one.charge_loop" }
    elseif source:find("heavy", 1, true) then
        return { "action_one.charge_release", "action_one.committed_heavy" }
    end
    return { "action_transition" }
end

-- #290 automatic evidence: the report's first trace attacked we_spear after merely
-- selecting Billhook in inventory. Capture the next ACTUAL local Kruber+Billhook attack
-- without a command or picker toggle. One row per distinct source/target/outcome, max 48.
local _wt290_seen, _wt290_count = {}, 0
local function _wt290_diag(state, career, source, target, outcome, detail)
    if not state or state.key ~= "wh_2h_billhook" or not career or career:sub(1, 3) ~= "es_" then return end
    local token = table.concat({ tostring(career), tostring(source), tostring(target),
        tostring(state.remap_origin), tostring(outcome) }, "|")
    if _wt290_seen[token] or _wt290_count >= 48 then return end
    _wt290_seen[token] = true
    _wt290_count = _wt290_count + 1
    printf("[wt:290] weapon=wh_2h_billhook template=%s career=%s source=%s target=%s origin=%s outcome=%s detail=%s evidence=%d/48 chat=false",
        tostring(state.template), tostring(career), tostring(source), tostring(target),
        tostring(state.remap_origin or "none"), tostring(outcome), tostring(detail or "none"),
        _wt290_count)
end

local function _wt576_diag(state, career, source, target, outcome, detail)
    if not state or not _WT576_KEYS[state.key] or not mod:get("enable_dev_anim_picker") then return end
    if not (_WT576_SOURCE[state.key] and _WT576_SOURCE[state.key][source]) then return end
    for _, phase in ipairs(_wt576_phases(state.key, source)) do
        local origin = state.remap_origin or "none"
        local token = table.concat({ tostring(state.key), tostring(state.template), tostring(career),
            phase, tostring(source), tostring(target), tostring(origin), tostring(outcome) }, "|")
        if not _wt576_seen[token] and _wt576_count < 256 then
            _wt576_seen[token] = true
            _wt576_count = _wt576_count + 1
            printf("[wt:576] weapon=%s template=%s career=%s phase=%s source=%s target=%s origin=%s outcome=%s detail=%s evidence=%d/256 chat=false",
                tostring(state.key), tostring(state.template), tostring(career), phase,
                tostring(source), tostring(target), tostring(origin), tostring(outcome),
                tostring(detail or "none"), _wt576_count)
        end
    end
end
-- WT_DEV_OVERLAY_END:bounded-live-animation-probes
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
    -- WT_DEV_OVERLAY_BEGIN:anim-picker-play-trace
    -- ============================================================
    -- [wt:play] dev-picker play-path trace (v0.12.145-dev) — LOGGING ONLY.
    -- ============================================================
    -- Diagnose-before-mitigate: prove WHERE a picked anim_event_3p is lost
    -- between the menu write and the engine. Scoped tightly so it stays
    -- readable: only fires for the LOCAL 3P body, only while wielding one of the
    -- picker's flagged-weapon templates, only for combat events (attack_/push_/
    -- parry_), and only when the dev picker toggle is ON.
    --
    -- HOW IT WORKS: when the gate is active we (a) log the event the ENGINE READ
    -- (event_name as start_action passed it — this is the live
    -- current_action_settings.anim_event_3p the picker mutated, OR the template
    -- default if the pick didn't take), and (b) wrap `func` so EVERY downstream
    -- call in this hook logs the FINAL event actually handed to the engine. If
    -- the funnel renames the picked event, the FINAL line differs from the READ
    -- line and names the rename — that's the override hypothesis, confirmed or
    -- refuted per event. (The one FORCE path that calls `_original_animation_event`
    -- directly is gated on state.remap == spear_to_billhook, which never applies
    -- to any picker weapon, so wrapping only `func` is complete coverage here.)
    if is_local and event_name and state and state.template
        and (event_name:sub(1, 7) == "attack_" or event_name:sub(1, 5) == "push_" or event_name:sub(1, 6) == "parry_")
        and mod:get("enable_dev_anim_picker")
        and _wt_dev_anim_picker and _wt_dev_anim_picker.is_picker_template
        and _wt_dev_anim_picker.is_picker_template(state.template) then
        -- On the 3P body the engine fires the picked anim_event_3p VALUE directly
        -- (weapon_unit_extension.lua:512). So `event_name` here SHOULD be one of
        -- the picker's set 3P values if the pick took. is_picked_3p tells us
        -- whether the read event is a picked value (pick reached the engine) or a
        -- template default (pick lost UPSTREAM — apply n==0, wrong template, or
        -- never written). The live_3p_map dump shows what the picks currently are.
        local is_picked_3p = _wt_dev_anim_picker.is_picked_3p_value(state.template, event_name)
        local map = _wt_dev_anim_picker.live_3p_map(state.template)
        local map_parts = {}
        for src, val in pairs(map) do map_parts[#map_parts + 1] = tostring(src) .. "->" .. tostring(val) end
        table.sort(map_parts)
        mod:info("[wt:play] READ event=%s tmpl=%s key=%s career=%s is_picked_3p_value=%s has_event_capability_only=%s visible_playback=unverified picks_set={%s}",
            tostring(event_name), tostring(state.template), tostring(state.key),
            tostring(career), tostring(is_picked_3p), tostring(_safe_has_anim(unit, event_name)),
            table.concat(map_parts, ","))
        local _wt_play_orig_func = func
        func = function(u, ev, ...)
            -- Logs the FINAL event the engine receives AFTER wt's funnel. If it
            -- differs from the read event, wt renamed it — the override
            -- hypothesis, confirmed/refuted per swing.
            mod:info("[wt:play] FINAL event=%s (read was %s)%s has_event_capability_only=%s visible_playback=unverified",
                tostring(ev), tostring(event_name),
                (tostring(ev) ~= tostring(event_name)) and " <<RENAMED BY FUNNEL>>" or " (unchanged)",
                tostring(_safe_has_anim(u, ev)))
            return _wt_play_orig_func(u, ev, ...)
        end
    end
    -- WT_DEV_OVERLAY_END:anim-picker-play-trace

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

    -- Reset this UNIT's 3P weapon remap on actual weapon change. The
    -- whitelist-by-template-change pattern from DEVELOPMENT.md "Non-Weapon
    -- `to_` Events": non-weapon `to_` events (to_crouch / to_zoom / to_onground)
    -- don't change state.template/key, so `remap_id == state.last_remap_id`
    -- and we skip the clear. Only true weapon switches (which update those
    -- via the wield hook) reach the clear-and-reset block.
    --
    -- v0.12.35 — was previously gated on `is_local`. The same logic applies
    -- per-unit: husks switching weapons should re-resolve their own remap.
    local remap_id = state and (state.template or state.key)
    if state and event_name:sub(1, 3) == "to_" and remap_id and remap_id ~= state.last_remap_id then
        state.last_remap_id = remap_id
        state.remap = nil
        state.remap_origin = nil
        if state.template then
            local tmpl_remap = _resolve_template_remap(state.template, career)
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
        -- tmpl_remap / key_remap may be `false` (deliberate skip from
        -- `_3p_template_remaps[name][prefix] = false`). `if tmpl_remap then`
        -- treats false as "not found" and falls through to key_remap. Final
        -- state.remap ends up nil if both were false — desired (native plays).
        --
        -- v0.12.64-dev — Fallback to `_resolve_3p_remap(event_name, career)`
        -- when neither template nor key remap hits.
        --
        -- Bug: when `_WIELD_ANIM_CAREER_3P_PATCHES` (line 1931, added v0.12.55/56)
        -- pre-rewrites a template's `wield_anim_career_3p[<career>]` at boot,
        -- the ENGINE fires the rewritten event (e.g. `to_polearm` for Kruber-on-
        -- billhook), not the original (`to_2h_billhook`). The
        -- `_career_anim_redirect.to_polearm` override branch never installs
        -- `state.remap` because that table's overrides[es_*] is nil — the
        -- redirect was designed for the `to_2h_billhook → to_polearm` redirect
        -- path, not the already-rewritten-by-patcher path.
        --
        -- Result before this fallback: Kruber-on-billhook reaches polearm
        -- stance correctly via the patcher, but billhook-specific attack
        -- events (`attack_swing_stab`, `attack_swing_left_diagonal`,
        -- `attack_swing_charge_stab`, etc.) fire raw on Kruber's polearm SM
        -- and silently no-op — visible as missing swing animations.
        --
        -- Fix: when template/key resolution doesn't hit, ask `_3p_remap_triggers`
        -- whether the wield event (now potentially the patcher-rewritten value)
        -- has an associated career-prefix remap. The same lookup already powers
        -- the override branch at line ~1127 and the redirect branch at line
        -- ~1156; we're now also calling it from the wield-event path so the
        -- swing remap installs regardless of which path the wield event took.
        --
        -- Symmetric coverage: the elf-spear-on-Saltzpyre case (which the
        -- patcher rewrites `to_spear → to_2h_billhook` for wh_*) gets the
        -- same fallback for the inverse mapping.
        if not state.remap then
            local trigger_remap = _resolve_3p_remap(event_name, career)
            if trigger_remap then
                state.remap = trigger_remap
                state.remap_origin = "trigger:" .. tostring(event_name)
            end
        end
    end

    -- Flails on non-native careers: certain release events either play the
    -- wrong animation or play nothing on the cross-career 3P body, even
    -- though has_animation_event reports them TRUE. attack_swing_heavy is
    -- the only event that produces a visible heavy strike on both flails.
    -- We can't use the remap table — adding these events to it corrupts the
    -- SM chain (same pattern as billhook attack_swing_stab_02). Direct
    -- func() call works.
    --
    -- v0.12.35 — was previously is_local-only because the global
    -- `_current_weapon_key` tracked only the local viewer. Now uses
    -- state.key (per-unit weapon) and unit career, so a remote Saltzpyre
    -- husk wielding es_1h_flail also gets the fix on the local viewer's
    -- screen. The flail-key gate is what keeps this from hijacking other
    -- weapons that fire the same event names.
    if state and career then
        local target = nil
        if state.key == "es_1h_flail" then
            if career:sub(1, 3) ~= "wh_" then
                -- Saltzpyre's flail on non-Saltzpyre. H1 release fires
                -- attack_swing_left (light name → wrong anim), H2 release
                -- fires attack_swing_heavy_left (plays nothing on the
                -- cross skeleton).
                if event_name == "attack_swing_left"
                    or event_name == "attack_swing_heavy_left" then
                    target = "attack_swing_heavy"
                end
            else
                -- Saltzpyre native: push-attack release fires
                -- attack_swing_right but doesn't visibly animate (vanilla
                -- SM bug — confirmed via wt force3p from idle).
                -- attack_swing_right_diagonal plays a visible L2-style
                -- swing on Saltzpyre's flail SM, best stand-in.
                if event_name == "attack_swing_right" then
                    target = "attack_swing_right_diagonal"
                end
            end
        elseif state.key == "bw_1h_flail_flaming"
            and career:sub(1, 3) ~= "bw_" then
            -- Sienna's flaming flail on non-Sienna. H1 release
            -- (attack_swing_heavy_down) fires natively as the correct
            -- overhead — DO NOT touch it. Only H2 (attack_swing_heavy_left)
            -- is broken and needs the redirect.
            if event_name == "attack_swing_heavy_left" then
                target = "attack_swing_heavy"
            end
        end
        if target then
            return func(unit, target, ...)
        end
    end

    -- 3P attack remap (per-unit)
    if state and state.remap then
        local target = state.remap[event_name]
        local target_capability = target and _safe_has_anim(unit, target)
        if target and target_capability then
            if _log_anims then
                local msg = "  REMAP " .. event_name .. " -> " .. target
                mod:info(msg)
                mod:echo(msg)
            end
            -- v0.12.88-dev: sampled _dbg trace (1-in-N). Cross-character
            -- anim REMAP path is rarer than the top-level hook fire rate
            -- (only fires when state.remap is populated AND the source
            -- event has a substitute), so 1-in-30 is enough to confirm
            -- the path is hit without flooding mid-combat. Captures
            -- career so combo bugs ("REMAP fires for the wrong career")
            -- are visible.
            _anim_event_remap_count = _anim_event_remap_count + 1
            if _anim_event_remap_count % _ANIM_EVENT_SAMPLE_REMAP_N == 0 then
                _dbg("[wt:anim] event=REMAP src=%s -> tgt=%s career=%s tmpl=%s key=%s sample=%d",
                    tostring(event_name), tostring(target), tostring(career),
                    tostring(state.template), tostring(state.key), _anim_event_remap_count)
            end
            local ok, err = pcall(func, unit, target, ...)
            -- WT_DEV_OVERLAY_BEGIN:animation-probe-outcomes
            if ok then
                _wt576_diag(state, career, event_name, target,
                    "accepted_unverified_no_observable_state_transition",
                    "pcall_ok;has_event_is_capability_not_playback_ack")
                _wt290_diag(state, career, event_name, target,
                    "accepted_unverified", "pcall_ok;has_event_is_capability_not_playback_ack")
            else
                _wt576_diag(state, career, event_name, target,
                    "animation_event_call_error", tostring(err))
                _wt290_diag(state, career, event_name, target,
                    "animation_event_call_error", tostring(err))
            end
            -- WT_DEV_OVERLAY_END:animation-probe-outcomes
            return
        end
        -- WT_DEV_OVERLAY_BEGIN:animation-probe-misses
        if target and not target_capability then
            _wt576_diag(state, career, event_name, target, "target_missing",
                "Unit.has_animation_event=false")
            _wt290_diag(state, career, event_name, target, "target_missing",
                "Unit.has_animation_event=false")
        elseif not target then
            _wt576_diag(state, career, event_name, nil, "unmapped_source",
                "source_event_has_no_remap_target")
            _wt290_diag(state, career, event_name, nil, "native_passthrough_or_unmapped",
                _polearm_native_3p_events[event_name] and "source_is_native_on_polearm" or "source_event_has_no_remap_target")
        end
        -- WT_DEV_OVERLAY_END:animation-probe-misses
        -- Force-fire path for SM-corrupting events (see
        -- feedback_animation_remap_rules). Adding `attack_swing_stab_02 ->
        -- attack_swing_left_diagonal` to the remap table broke ALL
        -- animations on the billhook SM (v0.9.43); calling
        -- _original_animation_event directly with the same target works.
        -- Block is GUARDED to only fire when the spear-to-billhook remap
        -- is active (v0.9.56 — without this guard, the billhook force-fires
        -- hijacked Kruber's spear+shield H1/H2).
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
        if force_target and _original_animation_event and _safe_has_anim(unit, force_target) then
            if _log_anims then
                local msg = "  FORCE " .. event_name .. " -> " .. force_target
                mod:info(msg)
                mod:echo(msg)
            end
            pcall(_original_animation_event, unit, force_target)
            return
        end
    end

    -- Career-aware redirects: phantom events exist on all skeletons but only
    -- play real animations on the correct character. Redirect by career prefix.
    local career_redir = _career_anim_redirect[event_name]
    if career_redir then
        if career_redir.overrides and career and career_redir.overrides[career] then
            local target = career_redir.overrides[career]
            if _safe_has_anim(unit, target) then
                local remap = _resolve_3p_remap(event_name, career)
                if remap and state then state.remap = remap end
                if _log_anims then
                    local msg = "  REDIR " .. event_name .. " -> " .. target
                    mod:info(msg)
                    mod:echo(msg)
                end
                pcall(func, unit, target, ...)
                return
            elseif _log_anims then
                mod:info("  REDIR FAIL: " .. target .. " not on unit")
            end
        end
        local matches_prefix = career and career:sub(1, #career_redir.prefix) == career_redir.prefix
        -- v0.12.60: gate redirect on a resolved career. When career=nil
        -- (preview units — MenuWorldPreviewer's character_unit has no
        -- career_system extension), `matches_prefix` is false, which made
        -- the prior `should_redirect` formula evaluate true and fire the
        -- cross-character redirect on any unit that happened to author the
        -- alt event. Kruber's preview body authors BOTH `to_polearm` and
        -- `to_spear`, so previewing halberd / Tuskgor / billhook (all
        -- resolving to `to_polearm` via wield_anim_career_3p) silently
        -- routed through `to_polearm → to_spear` and landed the body in
        -- the wrong stance. The redirect mechanism is only meant for
        -- in-mission cross-character ports where the wielder's career is
        -- known; for anonymous units, fall through to native firing.
        local should_redirect = career and (career_redir.invert and matches_prefix or (not career_redir.invert and not matches_prefix))
        if should_redirect then
            if _safe_has_anim(unit, career_redir.alt) then
                local remap = _resolve_3p_remap(event_name, career)
                if remap and state then state.remap = remap end
                if _log_anims then
                    local msg = "  REDIR " .. event_name .. " -> " .. career_redir.alt
                    mod:info(msg)
                    mod:echo(msg)
                end
                pcall(func, unit, career_redir.alt, ...)
                return
            elseif _log_anims then
                mod:info("  REDIR FAIL: " .. career_redir.alt .. " not on unit")
            end
        end
        pcall(func, unit, event_name, ...)
        return
    end

    -- Standard redirect: only fire if original event is missing from skeleton.
    local alt = _anim_redirect[event_name]
    if alt then
        if _safe_has_anim(unit, event_name) then
            return func(unit, event_name, ...)
        end
        if _safe_has_anim(unit, alt) then
            pcall(func, unit, alt, ...)
            return
        end
    end

    -- Suffix-based redirect: swap weapon suffix based on career.
    if career then
        local target = _try_suffix_redirect(unit, event_name, career)
        if target then
            if _log_anims then mod:info("  SUFFIX -> " .. target) end
            pcall(func, unit, target, ...)
            return
        end
    end

    pcall(func, unit, event_name, ...)
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
