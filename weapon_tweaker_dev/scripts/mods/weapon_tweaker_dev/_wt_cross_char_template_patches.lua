-- Cross-character base-template 3P patch owner (#1159).
--
-- Extracted verbatim from the entry: the five per-weapon source-template
-- patchers (brace of pistols -> repeating handgun, Empire longbow -> crossbow,
-- elf longbow -> crossbow, Moonfire Bow -> crossbow, repeating pistol ->
-- repeating handgun), the shared wield_anim_career_3p applier fed by
-- wt_wield_patches.lua, and the not-loaded / no-ammo wield fallback applier.
--
-- Every function here writes 3P-side template fields only
-- (wield_anim_career_3p, wield_anim_not_loaded_career, wield_anim_no_ammo_career,
-- a sibling anim_event_3p) or registers a career-scoped entry in wt's runtime
-- remap funnel. 1P fields (anim_event / wield_anim / state_machine) are never
-- touched - feedback_1p_animations_universal. Two of the patchers deliberately
-- route through _3p_template_remaps instead of mutating the shared template
-- for every career: that global mutation was issue #210.
--
-- The entry keeps a bare dofile at the former execution position, so these
-- Weapons.* writes still land before the authentic-brace rewrite further down
-- and after wt_wield_patches' own idempotent pre-application from _data.lua.
-- Everything below the accessor block is byte-identical to the lines it
-- replaced. Offline evidence: qa/lua/tests/test_wt_template_patch_owners.lua.

local mod = get_mod("wt_dev")

-- Late-binding accessors. The entry's file-scope _dbg / _dbg_alert /
-- _3p_template_remaps locals do not cross the chunk boundary; each is published
-- on the shared namespace far above this module's load position, so these read
-- the identical values the moved lines closed over.
local _dbg                = mod._wt.dbg
local _dbg_alert          = mod._wt.dbg_alert
local _3p_template_remaps = mod._wt.three_p_template_remaps

local _BRACE_REPEATER_BASE_WIELD_3P = {
    es_mercenary      = "to_repeating_handgun",
    es_huntsman       = "to_repeating_handgun",
    es_knight         = "to_repeating_handgun",
    es_questingknight = "to_repeating_handgun",
}

local _BRACE_REPEATER_ANIM_REMAP_3P = {
    special_action = "attack_shoot_fast",
}

local function _patch_brace_template_for_kruber()
    if not Weapons or not Weapons.brace_of_pistols_template_1 then
        _dbg_alert("[wt:tpl_patch] event=skip template=brace_of_pistols_template_1 reason=missing")
        return
    end
    local tpl = Weapons.brace_of_pistols_template_1
    local n_career_overrides = 0
    local n_action_remaps = 0

    -- Wield event per-career override.
    tpl.wield_anim_career_3p = tpl.wield_anim_career_3p or {}
    for k, v in pairs(_BRACE_REPEATER_BASE_WIELD_3P) do
        tpl.wield_anim_career_3p[k] = v
        n_career_overrides = n_career_overrides + 1
    end

    -- Per-action anim_event_3p remap for events the repeater SM doesn't
    -- author. Sets a sibling anim_event_3p alongside anim_event so the
    -- 3P body fires the substitute while 1P keeps the original.
    if tpl.actions then
        for _, action_group in pairs(tpl.actions) do
            if type(action_group) == "table" then
                for _, sub_action in pairs(action_group) do
                    if type(sub_action) == "table"
                            and sub_action.anim_event
                            and _BRACE_REPEATER_ANIM_REMAP_3P[sub_action.anim_event] then
                        sub_action.anim_event_3p = _BRACE_REPEATER_ANIM_REMAP_3P[sub_action.anim_event]
                        n_action_remaps = n_action_remaps + 1
                    end
                end
            end
        end
    end
    -- v0.12.88-dev: per-patcher trace. Boot-time only; always-on. Captures
    -- how many career_overrides + per-action remaps were applied so a
    -- regression (table-emptied / iter-order-broken) is visible at load.
    _dbg("[wt:tpl_patch] event=applied template=brace_of_pistols_template_1 career_overrides=%d action_remaps=%d",
        n_career_overrides, n_action_remaps)
end

_patch_brace_template_for_kruber()

-- ============================================================
-- Saltzpyre Longbow → Crossbow: base template anim patches
-- ============================================================
-- Parallel to _patch_brace_template_for_kruber. The es_longbow's template
-- (longbow_empire_template) gets a wh_*-keyed wield_anim_career_3p so
-- Saltzpyre's 3P body plays the crossbow wield transition instead of
-- "to_es_longbow". Per-action anim_event_3p remaps cover firing events
-- that have different names on the crossbow SM than on the longbow's 1P.
--
-- The longbow's primary fire action uses anim_event = "attack_shoot_fast"
-- (1P bow draws-then-fires). Saltzpyre's 3P crossbow SM does NOT author
-- "attack_shoot_fast" (the crossbow has no rapid-fire variant) but DOES
-- author "attack_shoot" — so we remap. shoot_charged actions already use
-- "attack_shoot" so they fall through unchanged.
-- wh_priest is EXCLUDED per the user rule (feedback_vt2_no_bows_on_warrior_priest):
-- his 3P body authors neither `to_longbow` nor `to_crossbow`. Pre-v0.12.47-dev
-- the table included him with a `to_crossbow` entry that silently no-op'd on
-- his skeleton (he held his prior-weapon idle stance while wielding the
-- longbow). Removed in v0.12.47-dev to align with the new rule.
local _SP_LONGBOW_CROSSBOW_WIELD_3P = {
    wh_captain      = "to_crossbow",
    wh_bountyhunter = "to_crossbow",
    wh_zealot       = "to_crossbow",
}

local _SALTZ_LONGBOW_CROSSBOW_ANIM_REMAP_3P = {
    attack_shoot_fast       = "attack_shoot",
    attack_shoot_fast_last  = "attack_shoot_last",
    draw_bow                = "to_zoom",       -- charged-shot aim hold; crossbow uses to_zoom
}

local function _patch_longbow_empire_template_for_saltzpyre()
    if not Weapons or not Weapons.longbow_empire_template then
        _dbg_alert("[wt:tpl_patch] event=skip template=longbow_empire_template reason=missing")
        return
    end
    local tpl = Weapons.longbow_empire_template
    local n_career_overrides = 0

    tpl.wield_anim_career_3p = tpl.wield_anim_career_3p or {}
    for k, v in pairs(_SP_LONGBOW_CROSSBOW_WIELD_3P) do
        tpl.wield_anim_career_3p[k] = v
        n_career_overrides = n_career_overrides + 1
    end

    -- Per-action anim remap: register a RUNTIME career-scoped remap
    -- (_3p_template_remaps.longbow_empire_template.wh_) instead of MUTATING the
    -- SHARED template globally. The old global mutation set draw_bow → to_zoom on
    -- the template for EVERY career, which broke Kruber's NATIVE longbow charge
    -- (draw_bow fired to_zoom on es_ too) — #210. The runtime path is wh_-gated, so
    -- es_ (Kruber native) keeps its own draw_bow / attack_shoot_fast. Keyed by the
    -- actions' fired 3P event (= their anim_event; these actions carry no native
    -- anim_event_3p, so anim_event IS what fires).
    -- #316 live evidence disproved the old cross-career assumption: Mercenary reached
    -- ActionAim zoom, but `draw_bow -> to_zoom` suppressed the visible bow draw. All
    -- Kruber careers render on the Empire Soldier skeleton and consume its native
    -- `draw_bow` vocabulary. Keep explicit false entries for Merc/FK/GK so local 3P
    -- and remote husks both pass the real event through. Huntsman remains the native
    -- control. Saltzpyre's model substitution still needs the crossbow remap below.
    _3p_template_remaps.longbow_empire_template = _3p_template_remaps.longbow_empire_template or {}
    _3p_template_remaps.longbow_empire_template.es_mercenary      = false
    _3p_template_remaps.longbow_empire_template.es_knight         = false
    _3p_template_remaps.longbow_empire_template.es_questingknight = false
    _3p_template_remaps.longbow_empire_template.wh_               = _SALTZ_LONGBOW_CROSSBOW_ANIM_REMAP_3P
    _dbg("[wt:tpl_patch] event=applied template=longbow_empire_template career_overrides=%d (wield) + native draw passthrough for es_ Merc/FK/GK + runtime crossbow remap for wh_; native es_huntsman untouched",
        n_career_overrides)
end

_patch_longbow_empire_template_for_saltzpyre()

-- ============================================================
-- Saltzpyre Elf Longbow → Crossbow: base template anim patches
-- ============================================================
-- Parallel to _patch_longbow_empire_template_for_saltzpyre above. The elf
-- longbow's `Weapons.longbow_template_1` shares the empire longbow's
-- `anim_event` vocabulary (action_one.default = "attack_shoot_fast",
-- action_one.shoot_charged = "attack_shoot", action_two.default = "draw_bow"),
-- so the remap table is identical — the crossbow SM has no `attack_shoot_fast`
-- variant, and `draw_bow` aim-hold maps to `to_zoom`. wh_priest is EXCLUDED
-- per the user rule (feedback_vt2_no_bows_on_warrior_priest): his 3P body
-- authors neither `to_longbow` nor `to_crossbow`.
local _WE_LONGBOW_CROSSBOW_WIELD_3P = {
    wh_captain      = "to_crossbow",
    wh_bountyhunter = "to_crossbow",
    wh_zealot       = "to_crossbow",
}

local _WE_LONGBOW_CROSSBOW_ANIM_REMAP_3P = {
    attack_shoot_fast       = "attack_shoot",
    attack_shoot_fast_last  = "attack_shoot_last",
    draw_bow                = "to_zoom",
}

local function _patch_longbow_template_1_for_saltzpyre()
    if not Weapons or not Weapons.longbow_template_1 then
        _dbg_alert("[wt:tpl_patch] event=skip template=longbow_template_1 reason=missing")
        return
    end
    local tpl = Weapons.longbow_template_1
    local n_career_overrides = 0

    tpl.wield_anim_career_3p = tpl.wield_anim_career_3p or {}
    for k, v in pairs(_WE_LONGBOW_CROSSBOW_WIELD_3P) do
        tpl.wield_anim_career_3p[k] = v
        n_career_overrides = n_career_overrides + 1
    end

    -- Same #210 fix as the empire longbow above: runtime wh_-gated remap instead of
    -- a global template mutation, so Kerillian's NATIVE elf longbow (we_) keeps its
    -- own draw_bow / attack_shoot_fast charge+fire anims. wh_-only remaps to crossbow.
    _3p_template_remaps.longbow_template_1 = _3p_template_remaps.longbow_template_1 or {}
    _3p_template_remaps.longbow_template_1.we_ = false  -- native Kerillian: never remap
    _3p_template_remaps.longbow_template_1.wh_ = _WE_LONGBOW_CROSSBOW_ANIM_REMAP_3P
    _dbg("[wt:tpl_patch] event=applied template=longbow_template_1 career_overrides=%d (wield) + runtime wh_ remap (#210: native we_ untouched)",
        n_career_overrides)
end

_patch_longbow_template_1_for_saltzpyre()

-- ============================================================
-- #580 Saltzpyre Moonfire Bow -> Crossbow: 3P event vocabulary
-- ============================================================
-- Vanilla `we_deus_01_template_1` uses the same source events as Kerillian's
-- longbow: rapid fire `attack_shoot_fast`, charged fire `attack_shoot`, and
-- aim `draw_bow`. Saltzpyre's native crossbow 3P state machine instead authors
-- `attack_shoot` and `to_zoom`. Register the substitutions in wt's runtime,
-- career-scoped funnel; never mutate the shared action tables, `wield_anim`,
-- first-person units, energy behavior, projectile data, or state machine.
-- `wt_wield_patches.lua` owns the matching wh_* `to_crossbow` wield entries.
local _WE_MOONFIRE_CROSSBOW_ANIM_REMAP_3P = {
    attack_shoot_fast      = "attack_shoot",
    attack_shoot_fast_last = "attack_shoot_last",
    draw_bow               = "to_zoom",
}

local function _patch_moonfire_template_1_for_saltzpyre()
    if not Weapons or not Weapons.we_deus_01_template_1 then
        _dbg_alert("[wt:580] event=skip template=we_deus_01_template_1 reason=missing")
        return
    end

    _3p_template_remaps.we_deus_01_template_1 =
        _3p_template_remaps.we_deus_01_template_1 or {}
    _3p_template_remaps.we_deus_01_template_1.we_ = false
    _3p_template_remaps.we_deus_01_template_1.wh_ =
        _WE_MOONFIRE_CROSSBOW_ANIM_REMAP_3P
    _dbg("[wt:580] event=applied template=we_deus_01_template_1 target=crossbow_template_1 scope=wh_ native_we_untouched=true remaps=3")
end

_patch_moonfire_template_1_for_saltzpyre()

-- ============================================================
-- Kruber Repeating Pistol → Repeating Handgun: base template anim patches
-- ============================================================
-- Parallel to _patch_brace_template_for_kruber. `wh_repeating_pistols`
-- (Saltzpyre's revolving repeater pistol) on Kruber, rendered as the empire
-- repeating handgun 3P mesh. Source template `Weapons.repeating_pistol_template_1`
-- fires `attack_shoot` (action_one.default + action_one.bullet_spray) and
-- `lock_target` (action_two.default). All three events EXIST in the target's
-- 3P SM (`repeating_handgun_template_1` authors `attack_shoot`,
-- `attack_shoot_last`, `attack_shoot_fast`, `attack_shoot_fast_last`,
-- `lock_target`, `lock_target_loop`, `reload`), so the per-action remap table
-- is EMPTY — only the `wield_anim_career_3p` override is needed. This is the
-- "vocabulary overlaps cleanly" case noted in CROSS_CHARACTER_PORT_RECIPE.md
-- Section 2 step (e) ("Skip (e) when every source action's anim_event already
-- exists in the target SM vocabulary unchanged.").
local _WH_REPEATING_PISTOLS_REPEATING_HANDGUN_WIELD_3P = {
    es_mercenary      = "to_repeating_handgun",
    es_huntsman       = "to_repeating_handgun",
    es_knight         = "to_repeating_handgun",
    es_questingknight = "to_repeating_handgun",
}

local function _patch_repeating_pistol_template_1_for_kruber()
    if not Weapons or not Weapons.repeating_pistol_template_1 then
        _dbg_alert("[wt:tpl_patch] event=skip template=repeating_pistol_template_1 reason=missing")
        return
    end
    local tpl = Weapons.repeating_pistol_template_1
    local n_career_overrides = 0

    tpl.wield_anim_career_3p = tpl.wield_anim_career_3p or {}
    for k, v in pairs(_WH_REPEATING_PISTOLS_REPEATING_HANDGUN_WIELD_3P) do
        tpl.wield_anim_career_3p[k] = v
        n_career_overrides = n_career_overrides + 1
    end

    -- Intentionally no anim_event_3p remap loop: source vocabulary is a strict
    -- subset of target vocabulary, so falling through unchanged is correct.
    _dbg("[wt:tpl_patch] event=applied template=repeating_pistol_template_1 career_overrides=%d action_remaps=0_intentional",
        n_career_overrides)
end

_patch_repeating_pistol_template_1_for_kruber()

-- ============================================================
-- Cross-character wield-stance template patches (inventory previewer)
-- ============================================================
-- Each weapon's template has a universal `wield_anim` field that the engine
-- fires on both 1P and 3P units. 1P animations are universal across the six
-- characters and never need overriding. The 3P side does: when a cross-
-- character wielder has no native authoring of the source weapon's `to_*`
-- event, the previewer fires an event the body doesn't author and the body
-- holds the previous weapon's idle stance (no T-pose — see
-- feedback_vt2_no_tpose_default_stance).
--
-- In-mission, the `_career_anim_redirect` table (line ~225) intercepts the
-- wield event via `Unit.animation_event` and remaps it to the target body's
-- own polearm/billhook/spear `to_*` event. But the keep inventory previewer
-- (MenuWorldPreviewer) reads `wield_anim_career_3p` directly off the
-- template at character-model setup time — it does NOT go through the
-- `Unit.animation_event` redirect path our hook covers. Result: a polearm-
-- class weapon equipped cross-character renders correctly in-mission but
-- holds the wrong stance in the keep inventory.
--
-- Fix: bake the same career→event mapping the `_career_anim_redirect`
-- entry encodes into each template's `wield_anim_career_3p` field. Both
-- paths now resolve the correct stance natively. We keep the
-- `_career_anim_redirect` entries too — they cover wield events re-fired
-- from other code paths (push-attacks, etc.).
--
-- Only careers in the unlock map are listed for each template — entries
-- for careers that cannot equip a weapon would be dead. wh_priest never
-- appears here: his row in the unlock map has no polearm/spear/billhook
-- and no bows/crossbows per `feedback_vt2_no_bows_on_warrior_priest`.
--
-- The four `_patch_*` functions above (brace, longbow×2, repeating_pistol)
-- are NOT consolidated into this table because they also do per-action
-- `anim_event_3p` remap loops — a different concern that needs the action
-- table walk. This table only handles the wield-event patch, which is the
-- whole story for polearm-class templates because the in-mission
-- `_3p_remap_triggers` (line ~421) already covers their per-action remaps.
-- v0.12.139-dev: the wield-patch DATA moved to a shared module so the dev anim
-- picker (which runs from _data.lua / _localization.lua, BEFORE this script's
-- top-level patcher calls — see reference_vmf_mod_file_load_order) can resolve
-- each Kruber port's TARGET template from its chosen wield set at catalog-build
-- time. The picker pre-applies the same tables to Weapons.* (idempotent with the
-- apply below). All values are `to_*` events written to wield_anim_career_3p — a
-- 3P field; 1P (anim_event/wield_anim) is never touched. The verbatim tables
-- (with their per-block provenance comments) now live in wt_wield_patches.lua.
local _WIELD_PATCHES_MODULE = mod:dofile("scripts/mods/weapon_tweaker_dev/wt_wield_patches")
local _WIELD_ANIM_CAREER_3P_PATCHES      = _WIELD_PATCHES_MODULE.patches
local _WIELD_ANIM_CAREER_3P_PATCHES_BULK = _WIELD_PATCHES_MODULE.bulk

local function _apply_wield_anim_career_3p_patches(patches)
    if not Weapons then return end
    for template_name, career_overrides in pairs(patches) do
        local tpl = Weapons[template_name]
        if tpl then
            tpl.wield_anim_career_3p = tpl.wield_anim_career_3p or {}
            local applied = 0
            for career, event in pairs(career_overrides) do
                tpl.wield_anim_career_3p[career] = event
                applied = applied + 1
            end
            -- v0.12.102-dev: mirror the per-template `[wt:tpl_patch] event=applied`
            -- instrumentation already present on the brace / longbow / repeating-pistol
            -- patchers (lines ~2088 / 2155 / 2213 / 2257). Closes the diagnostic blind
            -- spot where polearm patches applied silently and we couldn't confirm from
            -- log whether wield_anim_career_3p[<career>] actually installed.
            _dbg("[wt:tpl_patch] event=applied template=%s career_overrides=%d", template_name, applied)
        else
            mod:warning("[wt wield-3p-patch] Weapons.%s missing; skipping wield_anim_career_3p patch", template_name)
        end
    end
end

_apply_wield_anim_career_3p_patches(_WIELD_ANIM_CAREER_3P_PATCHES)
_apply_wield_anim_career_3p_patches(_WIELD_ANIM_CAREER_3P_PATCHES_BULK)

-- ============================================================
-- v0.12.139-dev: not-loaded / no-ammo WIELD fallbacks for cross-character
-- repeating crossbows (3P-ONLY crash fix — Kerillian Repeater Crossbow on Kruber)
-- ============================================================
-- Crash class (network game only, bypasses pcall — engine RPC packer fatal):
--   `repeating_crossbow_elf_template` (we_crossbow_repeater) sets
--     wield_anim_not_loaded = "to_repeating_crossbow_elf"          (repeating_crossbows_elf.lua:259)
--     wield_anim_no_ammo    = "to_repeating_crossbow_elf_noammo"   (repeating_crossbows_elf.lua:258)
--   Neither `_elf` event is registered in NetworkLookup.anims
--   (anims_lookup_table.lua has to_repeating_crossbow / _noammo and
--    to_repeating_handgun / _noammo, but NO `_elf` entries). When the crossbow
--   is wielded EMPTY/unloaded, simple_inventory_extension.lua:2050-2063 routes
--   the not-loaded event into ammo_extension:start_reload(...), which reaches
--   generic_ammo_user_extension.lua:311-330:
--       event_id = NetworkLookup.anims[reload_event]  -- => nil
--       network_transmit:send_rpc_clients("rpc_anim_event", event_id, go_id)
--   Packing nil into the rpc_anim_event lookup-index field is a C-level fatal.
--   wt's _WIELD_ANIM_CAREER_3P_PATCHES_BULK only patches `wield_anim_career_3p`
--   (the LOADED stance, consumed via the safe non-networked Unit.animation_event
--   at simple_inventory_extension.lua:2013), NOT the not-loaded/no-ammo wields,
--   so the raw `_elf` names survive on the empty-wield reload-send path.
--
-- Fix (3P-ONLY): per-career not-loaded/no-ammo wield overrides pointing at the
-- RECEIVER-native, NetworkLookup-registered repeating wields that each receiver's
-- own 3P body authors. The fallback differs by receiver group:
--   * Kruber (empire_soldier body) -> to_repeating_handgun / _noammo
--       to_repeating_handgun         (anims_lookup_table.lua:670 — handgun has no
--                                     distinct not-loaded wield; its loaded wield is
--                                     the correct fallback)
--       to_repeating_handgun_noammo  (anims_lookup_table.lua:671 — handgun's own
--                                     wield_anim_no_ammo, repeating_handguns.lua:312)
--   * Saltzpyre (witch_hunter body)  -> to_repeating_crossbow / _noammo  (#536)
--       to_repeating_crossbow        (anims_lookup_table.lua:645 — Saltzpyre's own
--                                     Volley Crossbow wield_anim_not_loaded,
--                                     repeating_crossbows.lua:247)
--       to_repeating_crossbow_noammo (anims_lookup_table.lua:646 — same template's
--                                     wield_anim_no_ammo, repeating_crossbows.lua:246)
-- These are 3P wield-FALLBACK fields only — never anim_event/wield_anim (1P). They
-- are the SAME receiver-native events the in-mission _career_anim_redirect funnel
-- produces for the LOADED wield, so the empty-wield send now matches the loaded one.
--
-- #536: the wh (Saltzpyre) careers ALSO wield we_crossbow_repeater as a cross-
-- character port (wt_unlock_data.lua:142-144 list it for wh_captain / wh_bountyhunter
-- / wh_zealot; the loaded 3P wield is baked in wt_wield_patches.lua:199), but were
-- omitted from this NOT-LOADED/NO-AMMO table when it was added (v0.12.139, Kruber-
-- only). So an empty-clip wield on a wh career kept the elf template's raw base
-- wield_anim_not_loaded = "to_repeating_crossbow_elf" (UNregistered) and hit the same
-- packer fatal. wh_priest is DLC (bless) but is NOT in scope: it never receives this
-- weapon (wt_unlock_data.lua:145 omits it; the /wt_regression_test `wh_priest_no_bows`
-- check asserts wh_priest gets no bows/crossbows), so no DLC gate is required here —
-- these are pure data writes that stay inert for any career that can't wield the item.
-- NOTE: the DISTINCT native Saltzpyre Volley Crossbow (wh_crossbow_repeater,
-- repeating_crossbow_template_1) already uses to_repeating_crossbow / _noammo natively
-- and never crashed — this patch is for the ELF template (we_crossbow_repeater) ported
-- ONTO wh careers, a different weapon. Do NOT instead register the `_elf` names into
-- _anim_redirect (lines ~484-485): those redirect ONTO the same unregistered `_elf`
-- events and carry this identical latent crash for any non-elf wielder; they're only
-- safe today because they ride the direct (non-networked) Unit.animation_event path
-- behind _safe_has_anim.
local _KRUBER_REPEATER_CAREERS = {
    "es_mercenary", "es_huntsman", "es_knight", "es_questingknight",
}
local _WH_REPEATER_CAREERS = {
    "wh_captain", "wh_bountyhunter", "wh_zealot",
}
-- Each template maps to a LIST of receiver groups so distinct receivers can point at
-- their own registered fallback under a single template key (Lua tables can't hold two
-- entries for the same template name). This extends the v0.12.139 single-group form.
local _NOT_LOADED_NO_AMMO_CAREER_PATCHES = {
    -- we_crossbow_repeater (Kerillian Repeater Crossbow) ported cross-character.
    repeating_crossbow_elf_template = {
        { not_loaded = "to_repeating_handgun",  no_ammo = "to_repeating_handgun_noammo",  careers = _KRUBER_REPEATER_CAREERS },
        { not_loaded = "to_repeating_crossbow", no_ammo = "to_repeating_crossbow_noammo", careers = _WH_REPEATER_CAREERS },
    },
}

local function _apply_not_loaded_no_ammo_career_patches(patches)
    if not Weapons then return end
    for template_name, groups in pairs(patches) do
        local tpl = Weapons[template_name]
        if tpl then
            tpl.wield_anim_not_loaded_career = tpl.wield_anim_not_loaded_career or {}
            tpl.wield_anim_no_ammo_career   = tpl.wield_anim_no_ammo_career   or {}
            local n = 0
            for _, spec in ipairs(groups) do
                for _, career in ipairs(spec.careers) do
                    if spec.not_loaded then tpl.wield_anim_not_loaded_career[career] = spec.not_loaded end
                    if spec.no_ammo    then tpl.wield_anim_no_ammo_career[career]    = spec.no_ammo end
                    n = n + 1
                end
            end
            _dbg("[wt:tpl_patch] event=applied template=%s not_loaded/no_ammo careers=%d", template_name, n)
        else
            mod:warning("[wt not-loaded/no-ammo patch] Weapons.%s missing; skipping", template_name)
        end
    end
end

_apply_not_loaded_no_ammo_career_patches(_NOT_LOADED_NO_AMMO_CAREER_PATCHES)

-- Published for the entry's _wt_runtime_checks dependency table, which read
-- both of these as file-scope locals before the move. Same tables, same
-- identity: the runtime checks assert against the very catalog applied above.
mod._wt.wield_patches_module      = _WIELD_PATCHES_MODULE
mod._wt.wield_anim_career_patches = _WIELD_ANIM_CAREER_3P_PATCHES
