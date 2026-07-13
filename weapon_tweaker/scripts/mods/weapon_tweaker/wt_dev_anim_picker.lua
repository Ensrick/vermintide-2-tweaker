--[[
============================================================================
 wt_dev_anim_picker.lua — Dev: 3P Animation Picker (STATIC hardcoded menu)
============================================================================

Live in-game tuning surface for cross-character weapon 3P animations on the
KRUBER body, for the 14 weapons flagged `[Needs Animations]` on Kruber.

STATIC HARDCODED (v0.12.143-dev): the previous dynamic catalog/vocab walk and
the per-weapon 3P anim-SET chooser dropdown are GONE. The established SET per
weapon is fixed (resolved offline from `wt_wield_patches.lua` → the `to_*`
wield event → its target template), so the menu no longer negotiates it. Three
static tables drive the whole picker:

  * `_WEAPON_SET`     : weapon_key → established SET letter (A..E).
  * `_SET_VOCAB`      : SET letter → the target template's authored anim_event
                        vocab — the dropdown OPTIONS (identical for every weapon
                        in that set).
  * `_WEAPON_ATTACKS` : weapon_key → the weapon's own source attack anim_events
                        (one per unique `anim_event`; each gets a dropdown).

MOVE LABELS (v0.12.148-dev, display-only): two parallel static maps decorate the
above with gameplay move labels, move-first, raw event kept as a clarifier:

  * `_SET_MOVE_LABEL[set][anim_event]`        → dropdown OPTION label
                                                ("Heavy 2  ·  attack_swing_heavy")
  * `_SOURCE_MOVE_LABEL[weapon_key][anim_event]` → attack ROW label
                                                ("Light 1  ·  attack_swing_down_left")

`_move_label_for_set` / `_move_label_for_source` build the strings; an unlabeled
event (the deliberate specials — slams, scythe specials, flame-sword spell) falls
back to the raw event name (never blank). The stored setting VALUE is ALWAYS the
raw anim_event — only the displayed text carries the label, so the apply path is
untouched.

The picker = per flagged weapon → one collapsible GROUP, with one per-attack
`anim_event_3p` dropdown per source attack, whose OPTIONS are the HARDCODED
established-set vocab. Selecting one applies via `anim_event_3p` (3P-only)
through `_apply_anim_event_change` + persist + boot-replay.

APPLY TIMING — the load-bearing fix (v0.12.144-dev). The engine does NOT read
attack 3P anims off the live `Weapons[name]` table the picker mutates. It reads
them off `MechanismOverrides.get(rawget(Weapons, name))` (weapon_utils.lua:211 →
get_item_template → WeaponUnitExtension.start_action, which reads
`current_action_settings.anim_event_3p` per swing). `MechanismOverrides.get`
shallow-COPIES any template carrying a `mechanism_overrides` field (or a child
that does) and caches the copy in `CACHE[t]` for the whole mechanism — so once
cached, a menu-time write to the live original is invisible to attacks. So after
every write `_apply_anim_event_change` calls `_bust_mechanism_override_cache`
(→ `MechanismOverrides.recursive_cleanup`, a guarded no-op when the template was
never cached) to drop the stale copy, then `_try_force_rewield` re-resolves the
template. Same path runs from `reapply_stored_picks` at boot. No re-equip
required — the cache-bust makes the live write take on the next attack.

3P-ONLY: every value written is `anim_event_3p` (a 3P field) — never
`anim_event` / `wield_anim` (1P, universal across all six characters). Picking
an event the Kruber body doesn't author falls through to the previous idle
stance (no T-pose, no crash — feedback_vt2_no_tpose_default_stance.md), so the
user can dump-and-iterate.

Membership = wt_port_status's `_NEEDS_ANIMS.kruber` allow-list (queried via
`_PORT_STATUS.needs_anims`), so the menu lists ONLY the weapons the user flagged
[Needs Animations]; untested / confirmed / status-tagged ports never leak in,
and no status tag is shown on the rows (the row title is just the weapon name).

Same `M.build_widget_tree() / M.loc_keys() / M.install() / M.on_setting_changed`
entry points the lead's wiring expects (weapon_tweaker_data.lua,
weapon_tweaker_localization.lua, weapon_tweaker.lua). build_widget_tree() returns
an ARRAY of per-weapon group widgets (never nil), nested as the `sub_widgets` of
the `enable_dev_anim_picker` checkbox so VMF reveals/hides them LIVE on toggle
(reference_vmf_native_master_toggle_submenu). The nested group → per-attack
dropdown shape keeps the gut Mod Tweaker depth-drill working (standard
type="group" + sub_widgets).

Per VMF_RECIPES § 5: every dropdown gets its OWN options table (no shared
references — silent `<<key>>` cascades if shared).
Per VMF_RECIPES § 6: every `setting_id` is globally unique (`wt_dev_anim_*`).
Per VMF_RECIPES § 9: debug logs gate on `enable_debug_logging`.
============================================================================
--]]

local mod = get_mod("wt")

local M = {}

-- ---------------------------------------------------------------------------
-- Debug helper (routed through VMF mod:debug channel, PROJECT_STANDARDS.md § 3.6).
-- ---------------------------------------------------------------------------
local function _dbg(fmt, ...)
    mod:debug("[wt:dev_anim] " .. fmt, ...)
end

-- ---------------------------------------------------------------------------
-- Constants
-- ---------------------------------------------------------------------------

-- Sentinel value used in dropdown widgets to represent "clear the override".
local UNSET = "__unset__"

-- Receiver bucket: this picker is KRUBER-only.
local _RECEIVER_CHAR = "kruber"
local _RECEIVER_SHORT = "Kruber"

-- The Kruber careers an anim_event pick conceptually applies on (the picker
-- writes anim_event_3p on the template's ACTIONS, not per-career, so this is
-- only carried on the setting rec for boot-replay parity / dump labeling).
local _KRUBER_CAREERS = { "es_huntsman", "es_knight", "es_mercenary", "es_questingknight" }

-- The non-WP Saltzpyre careers (Warrior Priest = wh_priest is its own bucket;
-- handled separately in wt_port_status). Carried on the setting rec for
-- boot-replay parity / dump labeling (same role as _KRUBER_CAREERS above).
local _SALTZ_CAREERS = { "wh_captain", "wh_bountyhunter", "wh_zealot" }

-- The four Kerillian careers (Sister of the Thorn = we_thornsister included; she
-- shares the elf 3P skeleton). Carried on the setting rec for boot-replay parity /
-- dump labeling (same role as _KRUBER_CAREERS / _SALTZ_CAREERS above).
local _KERI_CAREERS = { "we_waywatcher", "we_maidenguard", "we_shade", "we_thornsister" }

-- ---------------------------------------------------------------------------
-- Source-of-truth modules
-- ---------------------------------------------------------------------------
-- The shared (career, weapon_key) status resolver. The picker gates membership
-- on _PORT_STATUS.needs_anims (the EXPLICIT [Needs Animations] allow-list) so it
-- lists ONLY the weapons flagged in wt_port_status's _NEEDS_ANIMS.kruber. Same
-- module the Availability menu uses, so the two stay in lockstep.
local _PORT_STATUS = mod:dofile("scripts/mods/weapon_tweaker/wt_port_status")

-- ---------------------------------------------------------------------------
-- FALLBACK weapon display names (source-character-qualified)
-- ---------------------------------------------------------------------------
-- NOTE (#159, v0.12.178-dev): this is now only a FALLBACK. _weapon_display_name
-- resolves names from the documented localization first (the single source of
-- truth shared with the Weapon Availability menu); this curated map is consulted
-- only if a weapon has no unlock loc entry. Kept so labels never regress to a
-- bare internal key.
-- Curated weapon-TYPE name per key. KEYED ON WEAPON TYPE, never the cosmetic
-- ItemMasterList.localized_name (which on a base key is the default SKIN's name,
-- e.g. dr_2h_pick.display_name = "dw_2h_pick_skin_01_name" → "…Azdrek" — the
-- type-vs-illusion trap, same as vs_* keys in
-- reference_vt2_versus_items_hidden_in_adventure). Source character qualifier is
-- the 2-char weapon_key prefix (Kruber/Bardin/Kerillian/Saltzpyre/Sienna) to
-- match the Weapon Availability menu.
local _SOURCE_QUALIFIER = {
    es = "Kruber", dr = "Bardin", we = "Kerillian", wh = "Saltzpyre", bw = "Sienna",
}

local _WEAPON_NAME = {
    dr_2h_pick                 = "Pickaxe",
    dr_2h_cog_hammer           = "Cog Hammer",
    wh_2h_hammer               = "Two-Handed Hammer",
    we_2h_axe                  = "Two-Handed Axe",
    bw_1h_mace                 = "Mace",
    bw_ghost_scythe            = "Ghost Scythe",
    dr_dual_wield_axes         = "Dual Axes",
    we_dual_wield_daggers      = "Dual Daggers",
    we_dual_wield_swords       = "Dual Swords",
    we_dual_wield_sword_dagger = "Sword & Dagger",
    wh_dual_hammer             = "Dual Hammers",
    bw_dagger                  = "Dagger",
    bw_flame_sword             = "Flaming Sword",
    wh_flail_shield            = "Flail & Shield",
    we_1h_axe                  = "Axe",
}

-- Lazy weapon_key -> a career that grants it, so we can look up the documented
-- name from the SAME localized "unlock_<career>_<weapon_key>" string the Weapon
-- Availability menu uses (#159). Sourced from wt_unlock_data.weapon_unlock_map (a
-- leaf data module — no circular dofile back into this picker / the loc file).
-- Built lazily (at catalog/widget build, after loc is registered), never at file
-- scope (the loc file dofiles this picker, so a file-scope mod:localize would be
-- premature). The source weapon's name is career-independent, so any granting
-- career resolves the same name.
local _doc_career = nil

local function _build_doc_career()
    if _doc_career then return end
    _doc_career = {}
    local unlock = mod:dofile("scripts/mods/weapon_tweaker/wt_unlock_data")
    local map = unlock and unlock.weapon_unlock_map
    if map then
        for career, list in pairs(map) do
            for _, weapon_key in ipairs(list) do
                if not _doc_career[weapon_key] then _doc_career[weapon_key] = career end
            end
        end
    end
end

-- Resolve a weapon's player-facing name. PRIMARY source = the documented
-- localization (the single source of truth, identical to the Availability menu);
-- the computed "[Needs Animations → ...]" status tag is stripped so only the
-- clean "Source: Name" remains. Falls back to the curated _WEAPON_NAME map, then
-- a source-qualified key — but NEVER surfaces a bare internal key silently.
local function _weapon_display_name(weapon_key)
    _build_doc_career()
    local career = _doc_career[weapon_key]
    -- Read the documented name DIRECTLY from wt's raw localization table (published
    -- on `mod._wt_loc_raw` by weapon_tweaker_localization.lua before it dofiles this
    -- picker). We must NOT call mod:localize here (#197): the catalog/labels are built
    -- at mod-init / loc_keys() time — BEFORE wt's localization is registered — so
    -- mod:localize floods "[wt][ERROR] (localize): localization file was not loaded"
    -- (27x) AND returns nothing usable (labels fell back to raw keys). The raw-table
    -- read has no load-order dependency. Strip any computed "[...]" status tag.
    local raw = mod._wt_loc_raw
    if raw and career then
        local entry = raw["unlock_" .. career .. "_" .. weapon_key]
        if type(entry) == "table" and entry.en then
            return (entry.en:gsub("^%s*%b[]%s*", ""))
        end
    end
    local qualifier = _SOURCE_QUALIFIER[weapon_key:sub(1, 2)] or "?"
    local name = _WEAPON_NAME[weapon_key]
    if name then return qualifier .. " " .. name end
    return qualifier .. " " .. weapon_key
end

-- ---------------------------------------------------------------------------
-- HARDCODED: established SET per weapon (A..E)
-- ---------------------------------------------------------------------------
-- Resolved offline (per the v0.12.143-dev spec) from each weapon's `to_*` wield
-- event (wt_wield_patches.lua) → its target template. The SET is established and
-- non-negotiable — there is NO set-chooser dropdown anymore.
--   A Greathammer       (to_2h_hammer            / two_handed_hammers_template_1)
--   B Mace & Sword      (to_dual_hammer_sword_es / dual_wield_hammer_sword_template)
--   C Empire 1H Sword   (to_1h_sword             / one_handed_swords_template_1)
--   D Mace & Shield     (to_1h_hammer_shield     / one_handed_hammer_shield_template_1)
--   E Witch Hunter 1H Axe (to_1h_axe             / one_hand_axe_template_1)
-- NOTE (v0.12.149-dev): dr_2h_pick (A), dr_dual_wield_axes (B), bw_dagger (C),
-- and bw_flame_sword (C) were BAKED career-scoped into _3p_template_remaps
-- (weapon_tweaker.lua) once their picks were confirmed on Kruber, and removed
-- from _NEEDS_ANIMS — so the catalog gate (`_PORT_STATUS.needs_anims`) drops
-- them and they no longer appear in the picker. Their _WEAPON_SET entries are
-- deleted here to keep this mirror in lockstep (they were inert regardless).
-- NOTE (v0.12.150-dev): bw_1h_mace (A) and bw_ghost_scythe (A) BAKED the same way
-- (.one_handed_hammer_wizard_template_1.es_ / .staff_scythe.es_); the scythe also
-- bakes a +0.569 Z es_-scoped grip offset (_weapon_grip_offsets) — both removed
-- from _NEEDS_ANIMS and their _WEAPON_SET entries deleted here.
local _WEAPON_SET = {
    -- SET A — Greathammer
    -- v0.12.188-dev: dr_2h_cog_hammer (#182), wh_2h_hammer (#180) and the 7 Sienna
    --   staves + Deus (bw_skullstaff_beam/_fireball/_flamethrower/_geiser/_spear,
    --   bw_necromancy_staff, bw_deus_01) were BAKED career-scoped (es_) into
    --   _3p_template_remaps (weapon_tweaker.lua) from the user's persisted picks ->
    --   removed from _NEEDS_ANIMS, so the catalog gate drops them from the picker;
    --   their _WEAPON_SET / _WEAPON_TEMPLATE / _WEAPON_ATTACKS entries are deleted
    --   to keep this mirror in lockstep. (Earlier the same was done for dr_2h_pick /
    --   bw_1h_mace / bw_ghost_scythe in v0.12.149/.150.)
    we_2h_axe                  = "A",  -- Glaive: 2H but established set is Greathammer (to_2h_hammer)
    -- SET B — Mace & Sword
    we_dual_wield_daggers      = "B",
    we_dual_wield_swords       = "B",
    we_dual_wield_sword_dagger = "B",
    wh_dual_hammer             = "B",
    -- SET C — Empire 1H Sword
    -- wh_fencing_sword (#178 Rapier) BAKED v0.12.188-dev (fencing_sword_template_1.es_)
    --   -> removed from _NEEDS_ANIMS + the picker tables.
    -- SET D — Mace & Shield
    wh_flail_shield            = "D",
    -- SET E — Witch Hunter 1H Axe
    we_1h_axe                  = "E",
    -- v0.12.201-dev: wh_hammer_book (SET F) BAKED (es_) -> _CONFIRMED.kruber; removed here.
}

-- Friendly SET label shown in each weapon's group title, e.g. "[Greathammer]".
local _SET_LABEL = {
    A = "Greathammer",
    B = "Mace & Sword",
    C = "Empire 1H Sword",
    D = "Mace & Shield",
    E = "Witch Hunter 1H Axe",
    F = "1H Mace/Skullsplitter",  -- #181: to_1h_hammer / one_handed_hammer_template_1
}

-- ---------------------------------------------------------------------------
-- HARDCODED: per-SET anim_event vocab (the dropdown OPTIONS)
-- ---------------------------------------------------------------------------
-- Each is the target template's full authored anim_event vocab (extracted from
-- the target weapon_template's actions[*][*].anim_event, deduped + verified
-- against the decompiled source). Identical for every weapon mapped to that set.
-- These ARRAYS are templates — _build_options() copies a FRESH options table per
-- dropdown (VMF_RECIPES § 5; never share an options reference).
local _SET_VOCAB = {
    -- A Greathammer (two_handed_hammers_template_1 / 2h_hammers.lua)
    A = {
        "attack_swing_charge",
        "attack_swing_charge_right",
        "attack_swing_charge_left",
        "attack_swing_heavy_right",
        "attack_swing_heavy",
        "attack_swing_down_left",
        "attack_swing_left",
        "attack_swing_left_diagonal",
        "attack_swing_down_right",
        "attack_push",
        "parry_pose",
    },
    -- B Mace & Sword (dual_wield_hammer_sword_template / dual_wield_hammer_sword.lua)
    B = {
        "attack_swing_charge_left",
        "attack_swing_charge_right",
        "attack_swing_heavy_left_diagonal",
        "attack_swing_heavy_right_diagonal",
        "attack_swing_left_diagonal",
        "attack_swing_right",
        "attack_swing_right_diagonal",
        "attack_swing_left",
        "attack_swing_down",
        "attack_push",
        "parry_pose",
    },
    -- C Empire 1H Sword (one_handed_swords_template_1 / 1h_swords.lua)
    C = {
        "attack_swing_charge_left",
        "attack_swing_charge_right_pose",
        "attack_swing_charge_left_pose",
        "attack_swing_heavy",
        "attack_swing_heavy_right",
        "attack_swing_left_diagonal",
        "attack_swing_right",
        "attack_swing_down",
        "attack_swing_right_diagonal",
        "attack_push",
        "parry_pose",
    },
    -- D Mace & Shield (one_handed_hammer_shield_template_1 / 1h_hammers_shield.lua)
    D = {
        "attack_swing_charge",
        "attack_swing_charge_left_pose",
        "attack_swing_charge_pose",
        "attack_swing_heavy",
        "attack_swing_heavy_left",
        "attack_swing_left",
        "attack_swing_right_diagonal",
        "attack_swing_up_left",
        "attack_swing_down",
        "attack_push",
        "parry_pose",
    },
    -- E Witch Hunter 1H Axe (one_hand_axe_template_1 / 1h_axes.lua)
    E = {
        "attack_swing_charge_left_diagonal",
        "attack_swing_charge_right_diagonal_pose",
        "attack_swing_charge_left_diagonal_pose",
        "attack_swing_heavy_down",
        "attack_swing_heavy_down_right",
        "attack_swing_left_diagonal",
        "attack_swing_right_diagonal",
        "attack_swing_left",
        "attack_swing_down_right",
        "attack_push",
        "parry_pose",
    },
    -- F 1H Mace / Skullsplitter (#181). Kruber wields wh_hammer_book as to_1h_hammer
    -- (es_1h_mace's stance = one_handed_hammer_template_1 / 1h_hammers.lua). That
    -- template carries NO anim_event_3p overrides, so its anim_event names ARE the
    -- 3P events the Kruber mace body authors — safe to write verbatim as anim_event_3p
    -- (no 1P/3P divergence, unlike SET F-billhook #196). inspect_start_2 deliberately
    -- omitted (the picker never remaps inspect).
    F = {
        "attack_swing_charge_left_diagonal",
        "attack_swing_charge_left_diagonal_pose",
        "attack_swing_charge_right_diagonal_pose",
        "attack_swing_heavy_down",
        "attack_swing_heavy_down_right",
        "attack_swing_left_diagonal",
        "attack_swing_left_diagonal_last",
        "attack_swing_right",
        "attack_swing_right_diagonal",
        "attack_swing_down_right",
        "attack_push",
        "parry_pose",
    },
}

-- ---------------------------------------------------------------------------
-- HARDCODED: gameplay MOVE LABEL per (SET, anim_event) — for dropdown OPTIONS
-- ---------------------------------------------------------------------------
-- Mirrors `_SET_VOCAB` 1:1. Each target-set vocab event resolved (offline, by
-- chain-tracing the target template's action graph) to the gameplay move it
-- drives: Light N / Heavy N / Charge N (windup) / Push / Block. These are the
-- TARGET-side labels shown move-first on the dropdown options (e.g.
-- "Heavy 2  ·  attack_swing_heavy"). Every `_SET_VOCAB` entry has a label here;
-- _move_label_for_set() falls back to the raw event if one is ever missing.
local _SET_MOVE_LABEL = {
    A = {  -- Greathammer
        attack_swing_charge          = "Charge 1 (windup)",
        attack_swing_charge_right    = "Charge 2 (windup)",
        attack_swing_charge_left     = "Charge 3 (windup)",
        attack_swing_heavy_right     = "Heavy 1",
        attack_swing_heavy           = "Heavy 2",
        attack_swing_down_left       = "Light 1",
        attack_swing_left            = "Light 2",
        attack_swing_left_diagonal   = "Push Attack",
        attack_swing_down_right      = "Light 3",
        attack_push                  = "Push",
        parry_pose                   = "Block",
    },
    B = {  -- Mace & Sword
        attack_swing_charge_left          = "Charge 1 (windup)",
        attack_swing_charge_right         = "Charge 2 (windup)",
        attack_swing_heavy_left_diagonal  = "Heavy 1",
        attack_swing_heavy_right_diagonal = "Heavy 2",
        attack_swing_left_diagonal        = "Light 1",
        attack_swing_right                = "Light 2",
        attack_swing_right_diagonal       = "Light 3",
        attack_swing_left                 = "Light 4",
        attack_swing_down                 = "Push Attack",
        attack_push                       = "Push",
        parry_pose                        = "Block",
    },
    C = {  -- Empire 1H Sword
        attack_swing_charge_left        = "Charge 1 (windup)",
        attack_swing_charge_right_pose  = "Charge 2 (windup)",
        attack_swing_charge_left_pose   = "Charge 3 (windup)",
        attack_swing_heavy              = "Heavy 1",
        attack_swing_heavy_right        = "Heavy 2",
        attack_swing_left_diagonal      = "Light 1",
        attack_swing_right              = "Light 2",
        attack_swing_down               = "Light 3",
        attack_swing_right_diagonal     = "Push Attack",
        attack_push                     = "Push",
        parry_pose                      = "Block",
    },
    D = {  -- Mace & Shield
        attack_swing_charge            = "Charge 1 (windup)",
        attack_swing_charge_left_pose  = "Charge 2 (windup)",
        attack_swing_charge_pose       = "Charge 3 (windup)",
        attack_swing_heavy             = "Heavy 1 (shield bash)",
        attack_swing_heavy_left        = "Heavy 2",
        attack_swing_left              = "Light 1",
        attack_swing_right_diagonal    = "Light 2",
        attack_swing_up_left           = "Light 3",
        attack_swing_down              = "Push Attack",
        attack_push                    = "Push",
        parry_pose                     = "Block",
    },
    E = {  -- Witch Hunter 1H Axe
        attack_swing_charge_left_diagonal       = "Charge 1 (windup)",
        attack_swing_charge_right_diagonal_pose = "Charge 2 (windup)",
        attack_swing_charge_left_diagonal_pose  = "Charge 3 (windup)",
        attack_swing_heavy_down                 = "Heavy 1",
        attack_swing_heavy_down_right           = "Heavy 2",
        attack_swing_left_diagonal              = "Light 1",
        attack_swing_right_diagonal             = "Light 2",
        attack_swing_left                       = "Light 3",
        attack_swing_down_right                 = "Push Attack",
        attack_push                             = "Push",
        parry_pose                              = "Block",
    },
}

-- ---------------------------------------------------------------------------
-- HARDCODED: source template name per weapon (where anim_event_3p is written)
-- ---------------------------------------------------------------------------
local _WEAPON_TEMPLATE = {
    dr_2h_pick                 = "two_handed_picks_template_1",
    we_2h_axe                  = "two_handed_axes_template_2",
    bw_1h_mace                 = "one_handed_hammer_wizard_template_1",
    bw_ghost_scythe            = "staff_scythe",
    dr_dual_wield_axes         = "dual_wield_axes_template_1",
    we_dual_wield_daggers      = "dual_wield_daggers_template_1",
    we_dual_wield_swords       = "dual_wield_swords_template_1",
    we_dual_wield_sword_dagger = "dual_wield_sword_dagger_template_1",
    wh_dual_hammer             = "dual_wield_hammers_priest_template",
    bw_dagger                  = "one_handed_daggers_template_1",
    bw_flame_sword             = "flaming_sword_template_1",
    wh_flail_shield            = "one_handed_flail_shield_template",
    we_1h_axe                  = "we_one_hand_axe_template",
    -- v0.12.201-dev: wh_hammer_book BAKED (es_) -> _CONFIRMED.kruber; removed (#181).
    -- v0.12.188-dev: dr_2h_cog_hammer, wh_2h_hammer, wh_fencing_sword and the 7
    -- Sienna staves + Deus were BAKED (es_) and removed here (see _WEAPON_SET note).
}

-- ---------------------------------------------------------------------------
-- HARDCODED: per-weapon source attack anim_events (one dropdown each)
-- ---------------------------------------------------------------------------
-- Each weapon's own unique source-template `anim_event` values (deduped — the
-- engine's per-action vocab), verified against the decompiled weapon_templates.
-- One dropdown is built per entry; its OPTIONS = the weapon's established SET
-- vocab (above). A few source attacks have no clean target-set equivalent
-- (attack_swing_right_spell on bw_flame_sword; attack_slam/attack_slam_charge on
-- wh_2h_hammer + wh_flail_shield; special_action(_02) on bw_ghost_scythe) — they
-- still get a dropdown; the user maps them to the nearest set event or leaves
-- them UNSET (falls through to the prior idle stance, no T-pose, no crash).
local _WEAPON_ATTACKS = {
    -- SET A — Greathammer
    dr_2h_pick = {
        "attack_push",
        "attack_swing_charge_left_down",
        "attack_swing_charge_left_down_pose",
        "attack_swing_charge_right_down",
        "attack_swing_down_left",
        "attack_swing_down_left_axe",
        "attack_swing_down_right",
        "attack_swing_down_right_axe",
        "attack_swing_left",
        "attack_swing_left_diagonal",
        "attack_swing_right_diagonal",
        "parry_pose",
    },
    -- v0.12.188-dev: dr_2h_cog_hammer, wh_2h_hammer and wh_fencing_sword (Rapier)
    -- BAKED (es_) and removed here (see _WEAPON_SET note).
    we_2h_axe = {
        "attack_push",
        "attack_swing_charge_down",
        "attack_swing_charge_left",
        "attack_swing_heavy_down",
        "attack_swing_heavy_left",
        "attack_swing_left",
        "attack_swing_left_diagonal",
        "attack_swing_right",
        "parry_pose",
    },
    bw_1h_mace = {
        "attack_push",
        "attack_swing_charge_left_diagonal",
        "attack_swing_charge_left_pose",
        "attack_swing_charge_right_pose",
        "attack_swing_down",
        "attack_swing_heavy_down",
        "attack_swing_heavy_left_up",
        "attack_swing_heavy_right_up",
        "attack_swing_left",
        "attack_swing_left_diagonal",
        "attack_swing_left_diagonal_last",
        "attack_swing_right_diagonal",
        "parry_pose",
    },
    bw_ghost_scythe = {
        "attack_push",
        "attack_swing_charge_left",
        "attack_swing_charge_left_diagonal",
        "attack_swing_charge_right",
        "attack_swing_heavy",
        "attack_swing_heavy_left_diagonal",
        "attack_swing_heavy_right",
        "attack_swing_left",
        "attack_swing_left_diagonal",
        "attack_swing_left_diagonal_last",
        "attack_swing_right",
        "attack_swing_up_right",
        "parry_pose",
        "special_action",
        "special_action_02",
    },
    -- SET B — Mace & Sword
    dr_dual_wield_axes = {
        "attack_push",
        "attack_swing_charge_diagonal",
        "attack_swing_charge_left",
        "attack_swing_charge_right",
        "attack_swing_down",
        "attack_swing_heavy",
        "attack_swing_heavy_left_diagonal",
        "attack_swing_heavy_right",
        "attack_swing_left",
        "attack_swing_left_diagonal",
        "attack_swing_right",
        "attack_swing_right_diagonal",
        "parry_pose",
    },
    we_dual_wield_daggers = {
        "attack_push",
        "attack_swing_charge",
        "attack_swing_charge_left",
        "attack_swing_charge_right",
        "attack_swing_down_left",
        "attack_swing_down_right",
        "attack_swing_heavy",
        "attack_swing_heavy_down",
        "attack_swing_left",
        "attack_swing_right",
        "parry_pose",
        "push_stab",
    },
    we_dual_wield_swords = {
        "attack_push",
        "attack_swing_charge_diagonal",
        "attack_swing_charge_left",
        "attack_swing_charge_right",
        "attack_swing_heavy_left_diagonal",
        "attack_swing_heavy_right",
        "attack_swing_left",
        "attack_swing_left_diagonal",
        "attack_swing_right",
        "attack_swing_right_diagonal",
        "parry_pose",
        "push_stab",
    },
    we_dual_wield_sword_dagger = {
        "attack_push",
        "attack_swing_charge",
        "attack_swing_charge_diagonal",
        "attack_swing_charge_left",
        "attack_swing_heavy",
        "attack_swing_heavy_left_diagonal",
        "attack_swing_left",
        "attack_swing_right",
        "attack_swing_right_diagonal",
        "attack_swing_stab",
        "parry_pose",
        "push_stab",
    },
    wh_dual_hammer = {
        "attack_push",
        "attack_swing_charge_down",
        "attack_swing_charge_left",
        "attack_swing_charge_right",
        "attack_swing_down",
        "attack_swing_heavy_down",
        "attack_swing_heavy_left_diagonal",
        "attack_swing_heavy_right_diagonal",
        "attack_swing_left",
        "attack_swing_left_diagonal",
        "attack_swing_stab",
        "attack_swing_up",
        "parry_pose",
    },
    -- SET C — Empire 1H Sword
    bw_dagger = {
        "attack_push",
        "attack_swing_charge",
        "attack_swing_charge_left",
        "attack_swing_heavy",
        "attack_swing_heavy_right",
        "attack_swing_left",
        "attack_swing_left_diagonal",
        "attack_swing_right_diagonal",
        "attack_swing_stab",
        "parry_pose",
    },
    bw_flame_sword = {
        "attack_push",
        "attack_swing_charge",
        "attack_swing_charge_right",
        "attack_swing_heavy",
        "attack_swing_left",
        "attack_swing_left_diagonal",
        "attack_swing_right_diagonal",
        "attack_swing_right_spell",  -- no clean SET C twin; map to nearest or UNSET
        "attack_swing_stab",
        "parry_pose",
    },
    -- SET D — Mace & Shield
    wh_flail_shield = {
        "attack_push",
        "attack_slam",  -- no clean SET D twin; map to nearest or UNSET
        "attack_swing_charge",
        "attack_swing_charge_down_pose",
        "attack_swing_charge_pose",
        "attack_swing_down",
        "attack_swing_down_right",
        "attack_swing_heavy_down",
        "attack_swing_heavy_left",
        "attack_swing_left",
        "attack_swing_left_diagonal",
        "attack_swing_right_diagonal",
        "parry_pose",
    },
    -- SET E — Witch Hunter 1H Axe
    we_1h_axe = {
        "attack_push",
        "attack_swing_charge_left_diagonal",
        "attack_swing_charge_left_diagonal_pose",
        "attack_swing_charge_right_diagonal_pose",
        "attack_swing_down",
        "attack_swing_down_right",
        "attack_swing_heavy_down",
        "attack_swing_heavy_down_right",
        "attack_swing_left",
        "attack_swing_right",
        "attack_swing_up",  -- vanilla carries anim_event_3p="attack_swing_up_left" here
        "parry_pose",
    },
    -- v0.12.201-dev: wh_hammer_book (SET F) BAKED (es_) -> _CONFIRMED.kruber; removed here.
    -- v0.12.188-dev: the 7 Sienna staves + Deus (bw_skullstaff_beam/_fireball/
    -- _flamethrower/_geiser/_spear, bw_necromancy_staff, bw_deus_01) were BAKED
    -- (es_) and removed here (see _WEAPON_SET note).
}

-- ---------------------------------------------------------------------------
-- HARDCODED: gameplay MOVE LABEL per (weapon_key, anim_event) — for ROW labels
-- ---------------------------------------------------------------------------
-- Mirrors `_WEAPON_ATTACKS` 1:1. Each SOURCE-weapon attack anim_event resolved
-- (offline, by chain-tracing each weapon's own decompiled template + reading the
-- authoritative sub-action NAME: light_attack_* = Light, heavy_attack_* = Heavy,
-- the melee_start charge poses = "Charge N (windup)") to the gameplay move it
-- drives. These are the SOURCE-side labels shown move-first on each attack ROW
-- (e.g. "Light 1  ·  attack_swing_down_left"). A few specials with no clean
-- target-set twin (slams, scythe specials, the flame-sword spell) DELIBERATELY
-- have no label here and fall through to the raw event name via
-- _move_label_for_source() — never blank.
local _SOURCE_MOVE_LABEL = {
    -- SET A — Greathammer
    dr_2h_pick = {
        attack_swing_charge_left_down      = "Light/Heavy 1 (windup)",
        attack_swing_charge_left_down_pose = "Light 3 (windup)",
        attack_swing_charge_right_down     = "Light/Heavy 2 (windup)",
        attack_swing_left_diagonal         = "Light 1",
        attack_swing_right_diagonal        = "Light 2",
        attack_swing_left                  = "Light 3",
        attack_swing_down_left             = "Heavy 1",
        attack_swing_down_right            = "Heavy 2",
        attack_swing_down_left_axe         = "Heavy 1 (charged)",
        attack_swing_down_right_axe        = "Heavy 2 (charged)",
        attack_push                        = "Push",
        parry_pose                         = "Block",
    },
    dr_2h_cog_hammer = {
        attack_swing_charge            = "Light/Heavy 1 (windup)",
        attack_swing_charge_pose       = "Light 5 (windup)",
        attack_swing_charge_right_down = "Light/Heavy 2 (windup)",
        attack_swing_charge_right      = "Heavy (charged, windup)",
        attack_swing_up                = "Light 1",
        attack_swing_up_pose           = "Light 5",
        attack_swing_right_diagonal    = "Light 2",
        attack_swing_left_diagonal     = "Light 3",
        attack_swing_up_right          = "Light 4",
        attack_swing_left              = "Light (bopp)",
        attack_swing_down_left         = "Heavy 1",
        attack_swing_down_right        = "Heavy 2",
        attack_swing_heavy             = "Light 1 (charged)",
        attack_swing_heavy_right       = "Light 2 (charged)",
        attack_push                    = "Push",
        parry_pose                     = "Block",
    },
    wh_2h_hammer = {
        attack_swing_charge_right         = "Light/Heavy 1 (windup)",
        attack_swing_charge               = "Light/Heavy 2 (windup)",
        attack_swing_charge_right_down    = "Light/Heavy 3 (windup)",
        attack_swing_down_right           = "Light 1",
        attack_swing_up_left              = "Light 2",
        attack_swing_left                 = "Light 3",
        attack_swing_up                   = "Heavy 1",
        attack_swing_heavy_right          = "Heavy 2",
        attack_swing_heavy_right_diagonal = "Heavy 3",
        attack_slam                       = "Slam (special)",
        attack_slam_charge                = "Slam (charged special)",
        attack_push                       = "Push",
        parry_pose                        = "Block",
        parry_pose_02                     = "Block (alt)",
    },
    we_2h_axe = {
        attack_swing_charge_left   = "Light/Heavy 1 (windup)",
        attack_swing_charge_down   = "Light 2/3 (windup)",
        attack_swing_left          = "Light 1",
        attack_swing_right         = "Light 2",
        attack_swing_left_diagonal = "Light 3",
        attack_swing_heavy_left    = "Heavy 1",
        attack_swing_heavy_down    = "Heavy 2",
        attack_push                = "Push",
        parry_pose                 = "Block",
    },
    bw_1h_mace = {
        attack_swing_charge_left_diagonal = "Light/Heavy 1 (windup)",
        attack_swing_charge_left_pose     = "Light/Heavy 2&4 (windup)",
        attack_swing_charge_right_pose    = "Light/Heavy 3 (windup)",
        attack_swing_down                 = "Light 1",
        attack_swing_left_diagonal_last   = "Light 2",
        attack_swing_right_diagonal       = "Light 3",
        attack_swing_left_diagonal        = "Light 4",
        attack_swing_left                 = "Light (bopp)",
        attack_swing_heavy_down           = "Heavy 1",
        attack_swing_heavy_left_up        = "Heavy 2",
        attack_swing_heavy_right_up       = "Heavy 3",
        attack_push                       = "Push",
        parry_pose                        = "Block",
    },
    bw_ghost_scythe = {
        attack_swing_charge_left          = "Light/Heavy 1 (windup)",
        attack_swing_charge_right         = "Light/Heavy 2&4 (windup)",
        attack_swing_charge_left_diagonal = "Light/Heavy 3 (windup)",
        attack_swing_left_diagonal        = "Light 1",
        attack_swing_up_right             = "Light 2",
        attack_swing_left                 = "Light 3",
        attack_swing_right                = "Light 4",
        attack_swing_left_diagonal_last   = "Light (bopp)",
        attack_swing_heavy                = "Heavy 1",
        attack_swing_heavy_right          = "Heavy 2",
        attack_swing_heavy_left_diagonal  = "Heavy 3",
        attack_push                       = "Push",
        parry_pose                        = "Block",
        -- special_action / special_action_02: Necromancer scythe special, no SET A twin (raw fallback)
    },
    -- SET B — Mace & Sword
    dr_dual_wield_axes = {
        attack_swing_charge_left         = "Light/Heavy 1 (windup)",
        attack_swing_charge_right        = "Heavy 2 (windup)",
        attack_swing_charge_diagonal     = "Heavy 3 (windup)",
        attack_swing_left                = "Light 1",
        attack_swing_right               = "Light 2",
        attack_swing_left_diagonal       = "Light 3",
        attack_swing_right_diagonal      = "Light 4",
        attack_swing_down                = "Light (bopp)",
        attack_swing_heavy               = "Heavy 1",
        attack_swing_heavy_right         = "Heavy 2",
        attack_swing_heavy_left_diagonal = "Heavy 3",
        attack_push                      = "Push",
        parry_pose                       = "Block",
    },
    we_dual_wield_daggers = {
        attack_swing_charge       = "Light/Heavy 1 (windup)",
        attack_swing_charge_left  = "Light 2/3/4 (windup)",
        attack_swing_charge_right = "Heavy (stab, windup)",
        attack_swing_left         = "Light 1",
        attack_swing_right        = "Light 2",
        attack_swing_down_left    = "Light 3",
        attack_swing_down_right   = "Light 4",
        attack_swing_heavy        = "Heavy 1",
        attack_swing_heavy_down   = "Heavy 2",
        attack_push               = "Push",
        push_stab                 = "Push Attack",
        parry_pose                = "Block",
    },
    we_dual_wield_swords = {
        attack_swing_charge_diagonal     = "Light/Heavy 1 (windup)",
        attack_swing_charge_left         = "Light/Heavy 2 (windup)",
        attack_swing_charge_right        = "Light 3/4 (windup)",
        attack_swing_left_diagonal       = "Light 1",
        attack_swing_right_diagonal      = "Light 2",
        attack_swing_left                = "Light 3",
        attack_swing_right               = "Light 4",
        attack_swing_heavy_left_diagonal = "Heavy 1",
        attack_swing_heavy_right         = "Heavy 2",
        attack_push                      = "Push",
        push_stab                        = "Push Attack",
        parry_pose                       = "Block",
    },
    we_dual_wield_sword_dagger = {
        attack_swing_charge_diagonal     = "Light/Heavy 1 (windup)",
        attack_swing_charge_left         = "Light 2/3/4 (windup)",
        attack_swing_charge              = "Heavy 2 (windup)",
        attack_swing_left                = "Light 1",
        attack_swing_right_diagonal      = "Light 2",
        attack_swing_right               = "Light 3",
        attack_swing_stab                = "Light 4 (stab)",
        attack_swing_heavy_left_diagonal = "Heavy 1",
        attack_swing_heavy               = "Heavy 2",
        attack_push                      = "Push",
        push_stab                        = "Push Attack",
        parry_pose                       = "Block",
    },
    wh_dual_hammer = {
        attack_swing_charge_down          = "Light/Heavy 1 (windup)",
        attack_swing_charge_right         = "Light/Heavy 2 (windup)",
        attack_swing_charge_left          = "Light/Heavy 3 (windup)",
        attack_swing_left                 = "Light 1",
        attack_swing_up                   = "Light 2",
        attack_swing_left_diagonal        = "Light 3",
        attack_swing_down                 = "Light (down)",
        attack_swing_stab                 = "Light (bopp)",
        attack_swing_heavy_down           = "Heavy 1",
        attack_swing_heavy_right_diagonal = "Heavy 2",
        attack_swing_heavy_left_diagonal  = "Heavy 3",
        attack_push                       = "Push",
        parry_pose                        = "Block",
    },
    -- SET C — Empire 1H Sword
    bw_dagger = {
        attack_swing_charge        = "Light/Heavy 1 (windup)",
        attack_swing_charge_left   = "Heavy 2 (windup)",
        attack_swing_left_diagonal = "Light 1",
        attack_swing_right_diagonal = "Light 2",
        attack_swing_stab          = "Light 3 (stab)",
        attack_swing_left          = "Light 4",
        attack_swing_heavy         = "Heavy 1",
        attack_swing_heavy_right   = "Heavy 2",
        attack_push                = "Push",
        parry_pose                 = "Block",
    },
    bw_flame_sword = {
        attack_swing_charge_right  = "Light/Heavy 1 (windup)",
        attack_swing_charge        = "Heavy 2 (windup)",
        attack_swing_left          = "Light 1",
        attack_swing_right_diagonal = "Light 2",
        attack_swing_stab          = "Light 3 (stab)",
        attack_swing_left_diagonal = "Light (bopp)",
        attack_swing_heavy         = "Heavy 2",
        -- attack_swing_right_spell: flame-sword spell attack, no clean SET C twin (raw fallback)
        attack_push                = "Push",
        parry_pose                 = "Block",
    },
    -- SET D — Mace & Shield
    wh_flail_shield = {
        attack_swing_charge           = "Light/Heavy 1 (windup)",
        attack_swing_charge_pose      = "Light 2/5 (windup)",
        attack_swing_charge_down_pose = "Light 6 (windup)",
        attack_swing_down             = "Light 1",
        attack_swing_down_right       = "Light 2",
        attack_swing_left_diagonal    = "Light 4",
        attack_swing_right_diagonal   = "Light 5",
        attack_swing_heavy_down       = "Light 2 (alt)",
        attack_swing_left             = "Heavy 1",
        attack_swing_heavy_left       = "Heavy 2",
        -- attack_slam: shield slam (light_attack_03), no clean SET D twin (raw fallback)
        attack_push                   = "Push",
        parry_pose                    = "Block",
    },
    -- SET E — Witch Hunter 1H Axe
    we_1h_axe = {
        attack_swing_charge_left_diagonal       = "Light/Heavy 1 (windup)",
        attack_swing_charge_right_diagonal_pose = "Light/Heavy 2&4 (windup)",
        attack_swing_charge_left_diagonal_pose  = "Light/Heavy 3 (windup)",
        attack_swing_left                       = "Light 1",
        attack_swing_right                      = "Light 2",
        attack_swing_down                       = "Light 3",
        attack_swing_down_right                 = "Light 4",
        attack_swing_up                         = "Light (bopp)",
        attack_swing_heavy_down                 = "Heavy 1",
        attack_swing_heavy_down_right           = "Heavy 2",
        attack_push                             = "Push",
        parry_pose                              = "Block",
    },
}

-- ===========================================================================
-- SALTZPYRE (non-WP: wh_captain / wh_bountyhunter / wh_zealot) — batch 1
-- ===========================================================================
-- Source-verified from decompiled weapon_templates + reused from the Kruber
-- tables above (source attack events are receiver-INDEPENDENT). 9 melee ports,
-- 5 redirect-target SETs. SET A/B targets are Warrior-Priest weapons (bless DLC);
-- their anims live on the shared Saltzpyre body but may be absent without the DLC
-- (picker falls through to idle, no T-pose, no crash). Move labels deliberately
-- OMITTED for batch 1 (empty maps -> rows/options show the raw anim_event, which
-- _move_label_for_* already falls back to); add polished labels in a follow-up.
local _SALTZ_SET_LABEL = {
    A = "Warrior Priest Greathammer",
    B = "Warrior Priest Dual Hammers",
    C = "Dual Axe & Falchion",
    D = "Fencing Sword (Rapier)",
    E = "1H Falchion",
    F = "Billhook",  -- Saltzpyre's 2H Billhook (in-game "Bill Hook"); polearm target (#161)
    G = "2H Sword",  -- Saltzpyre's 2H Sword (two_handed_swords_template_1); #160 executioner target
}

local _SALTZ_SET_VOCAB = {
    -- A: WP Greathammer (two_handed_hammer_priest_template) — = Kruber wh_2h_hammer events
    A = {
        "attack_swing_charge", "attack_swing_charge_right", "attack_swing_charge_right_down",
        "attack_swing_heavy_right", "attack_swing_heavy_right_diagonal", "attack_swing_down_right",
        "attack_swing_left", "attack_swing_up", "attack_swing_up_left",
        "attack_slam", "attack_slam_charge", "attack_push", "parry_pose", "parry_pose_02",
    },
    -- B: WP Dual Hammers (dual_wield_hammers_priest_template) — = Kruber wh_dual_hammer events
    B = {
        "attack_swing_charge_down", "attack_swing_charge_left", "attack_swing_charge_right",
        "attack_swing_heavy_down", "attack_swing_heavy_left_diagonal", "attack_swing_heavy_right_diagonal",
        "attack_swing_down", "attack_swing_left", "attack_swing_left_diagonal",
        "attack_swing_stab", "attack_swing_up", "attack_push", "parry_pose",
    },
    -- C: Dual Axe & Falchion (dual_wield_axe_falchion) — grepped
    C = {
        "attack_swing_charge_down", "attack_swing_charge_left",
        "attack_swing_heavy_down", "attack_swing_heavy_left",
        "attack_swing_right", "attack_swing_right_diagonal", "attack_swing_left_diagonal",
        "attack_swing_down_left", "attack_swing_down", "attack_push", "parry_pose",
    },
    -- D: Fencing Sword / Rapier (fencing_swords) — grepped, MELEE only (attack_shoot/front_idle_exit excluded)
    D = {
        "attack_swing_stab_charge", "attack_swing_stab",
        "attack_swing_right", "attack_swing_left", "attack_swing_right_diagonal",
        "attack_push", "parry_pose",
    },
    -- E: 1H Falchion (1h_falchions) — grepped
    E = {
        "attack_swing_charge_left_diagonal", "attack_swing_charge_right_diagonal_pose",
        "attack_swing_charge_left_diagonal_pose", "attack_swing_heavy_left_diagonal",
        "attack_swing_heavy_right_diagonal", "attack_swing_left_diagonal", "attack_swing_right_diagonal",
        "attack_swing_down", "attack_swing_up", "attack_push", "parry_pose",
    },
    -- F: Saltzpyre Billhook (2h_billhooks / two_handed_billhooks_template).
    -- These are the billhook's `anim_event_3p` VALUES (what the Saltzpyre 3P body
    -- actually plays) — the picker writes anim_event_3p, and the billhook's
    -- charge/heavy attacks have DIVERGENT 1P/3P names (e.g. 1P attack_swing_charge_stab
    -- -> 3P attack_swing_stab_charge). The original vocab listed the 1P anim_event
    -- names, so charge/heavy picks set a 3P event the body doesn't author and fell
    -- through to idle (#196). Source: 2h_billhooks.lua anim_event_3p column, deduped.
    -- Polearm target (#161): Kerillian Spear + Kruber Halberd already wield as this.
    F = {
        "attack_swing_stab_charge",          -- charge stab (1P attack_swing_charge_stab)
        "attack_swing_charge_left_diagonal", -- charge down (1P attack_swing_charge_down)
        "attack_swing_heavy_left_diagonal",  -- heavy down  (1P attack_swing_heavy_down)
        "attack_swing_heavy_stab", "attack_swing_stab", "attack_swing_left_diagonal",
        "attack_swing_down", "attack_push", "parry_pose",
    },
    -- G: Saltzpyre 2H Sword (two_handed_swords_template_1) — the `to_2h_sword`
    -- redirect target for the Kruber Executioner Sword on Saltzpyre (#160). The
    -- template carries ZERO anim_event_3p overrides (verified in 2h_swords.lua), so
    -- there is no 1P/3P divergence — the 3P vocab equals the template's anim_event
    -- names (#196-safe). Melee only (a 2H sword has no ranged actions).
    G = {
        "attack_swing_charge_diagonal", "attack_swing_charge_diagonal_left",
        "attack_swing_charge_diagonal_right", "attack_swing_heavy_left_diagonal",
        "attack_swing_heavy_right_diagonal", "attack_swing_left_diagonal",
        "attack_swing_right_diagonal", "attack_swing_down_right",
        "attack_push", "parry_pose",
    },
}

-- v0.12.188-dev: ALL 17 Saltzpyre batch-1/2/3 ports (we_2h_axe,
-- es_dual_wield_hammer_sword, dr_dual_wield_axes, we_dual_wield_daggers/_swords/
-- _sword_dagger, bw_dagger, bw_flame_sword, we_spear, es_halberd, the 5
-- bw_skullstaff_*, bw_necromancy_staff, bw_deus_01) were BAKED career-scoped (wh_)
-- into _3p_template_remaps (weapon_tweaker.lua) from the user's persisted picks ->
-- removed from _NEEDS_ANIMS.saltzpyre, so the catalog gate drops them. The
-- _SALTZ_* picker tables are emptied to keep the mirror in lockstep. Re-populate
-- with the next Saltzpyre batch. (_SALTZ_SET_LABEL/_SALTZ_SET_VOCAB left defined.)
-- v0.12.194-dev (#160): re-populated with the Kruber Executioner Sword (SET G).
-- v0.12.201-dev: Executioner Sword BAKED (wh_) -> _CONFIRMED.saltzpyre; REPLACED here
-- by the Saltzpyre batch-2 — 11 cross-character 3P ports queued for the tester's
-- dev-picker tuning. SET A/B targets are Warrior-Priest weapons (bless DLC); their
-- anims live on the shared Saltzpyre body but may be absent without the DLC (picker
-- falls through to idle, no T-pose, no crash). Every wield-render target is a wh_*
-- redirect already present in _WIELD_ANIM_CAREER_3P_PATCHES_BULK (wt_wield_patches).
-- Kept in lockstep with _NEEDS_ANIMS.saltzpyre (wt_port_status).
-- v0.12.213-dev (#519): 10 of the 11 batch-2 ports were fully tuned and BAKED
-- career-scoped (wh_) into _3p_template_remaps (_wt_anim_remap.lua) -> removed
-- from _NEEDS_ANIMS.saltzpyre, so the catalog gate drops them; their entries in
-- the three _SALTZ_* tables below are deleted to keep this mirror in lockstep.
-- Only dr_dual_wield_hammers remains (zero non-unset picks — not yet tuned).
local _SALTZ_WEAPON_SET = {
    -- SET B — Warrior Priest Dual Hammers (to_dual_hammers_priest)
    dr_dual_wield_hammers = "B",
}

-- Source template per Saltzpyre port (where anim_event_3p is written) = the port's
-- own source weapon template. Confirmed against ItemMasterList.
local _SALTZ_WEAPON_TEMPLATE = {
    -- SET B — WP Dual Hammers
    dr_dual_wield_hammers = "dual_wield_hammers_template",
    -- v0.12.213-dev (#519): the 10 baked batch-2 entries removed (see _SALTZ_WEAPON_SET).
}

-- Per-weapon source attack anim_events (one dropdown each), deduped from the source
-- template's actions. Receiver-independent — each list is copied VERBATIM from the
-- matching _KERI_WEAPON_ATTACKS entry (bw_1h_mace from the Kruber _WEAPON_ATTACKS).
local _SALTZ_WEAPON_ATTACKS = {
    -- v0.12.213-dev (#519): the 10 baked batch-2 entries removed (see _SALTZ_WEAPON_SET).
    -- SET B — WP Dual Hammers
    dr_dual_wield_hammers = {
        "attack_swing_charge_down", "attack_swing_charge_right", "attack_swing_charge_left",
        "attack_swing_heavy_down", "attack_swing_heavy_right_diagonal", "attack_swing_heavy_left_diagonal",
        "attack_swing_left", "attack_swing_down", "attack_swing_left_diagonal", "attack_swing_up",
        "attack_swing_stab", "attack_push", "parry_pose",
    },
}

-- ===========================================================================
-- KERILLIAN (all four elf careers: Waywatcher / Handmaiden / Shade / Sister of
-- the Thorn) — batch 1
-- ===========================================================================
-- Same construction as the Saltzpyre batch above: source attack events are
-- receiver-INDEPENDENT (extracted from the decompiled weapon_templates; the
-- shared ones match the Kruber tables above), and each SET's dropdown vocab is
-- the KERILLIAN-native target template's authored anim_event_3p column (falling
-- back to anim_event where no _3p override) — the 3P events the elf body actually
-- plays for that weapon. #196: the vocab lists anim_event_3p VALUES, never the 1P
-- anim_event names. Only 1h_axes_wood_elf diverges (source anim_event
-- attack_swing_up carries anim_event_3p=attack_swing_up_left), folded into SET D.
-- The SET per weapon is the `we_*` wield redirect from wt_wield_patches (the
-- `to_*` event on the port's source template). Move labels deliberately OMITTED
-- for batch 1 (empty maps -> rows/options show the raw anim_event, which
-- _move_label_for_* already falls back to); add polished labels in a follow-up.
local _KERI_SET_LABEL = {
    A = "Elf 2H Axe/Glaive",   -- to_2h_axe_we            (2h_axes_wood_elf)
    B = "Elf 2H Sword",        -- to_2h_sword_we          (2h_swords_wood_elf)
    C = "Elf 1H Sword",        -- to_1h_sword             (1h_swords_wood_elf)
    D = "Elf 1H Axe",          -- to_1h_axe               (1h_axes_wood_elf)
    E = "Elf Spear & Shield",  -- to_1h_spear_shield      (1h_spears_shield)
    F = "Dual Swords",         -- to_dual_swords          (dual_wield_swords)
    G = "Sword & Dagger",      -- to_dual_sword_dagger    (dual_wield_sword_dagger)
    H = "Elf Javelin",         -- to_javelin              (javelin)
}

-- Each is the KERILLIAN-native target template's authored 3P vocab (anim_event_3p,
-- falling back to anim_event). Extracted + deduped from the decompiled elf
-- templates. _build_options() copies a FRESH options table per dropdown.
local _KERI_SET_VOCAB = {
    -- A: Elf 2H Axe/Glaive (2h_axes_wood_elf) — no 1P/3P divergence
    A = {
        "attack_swing_charge_left", "attack_swing_charge_down",
        "attack_swing_right", "attack_swing_left", "attack_swing_left_diagonal",
        "attack_swing_heavy_left", "attack_swing_heavy_down",
        "attack_push", "parry_pose",
    },
    -- B: Elf 2H Sword (2h_swords_wood_elf)
    B = {
        "attack_swing_charge", "attack_swing_right", "attack_swing_left",
        "attack_swing_heavy", "attack_swing_heavy_right",
        "attack_push", "parry_pose",
    },
    -- C: Elf 1H Sword (1h_swords_wood_elf)
    C = {
        "attack_swing_charge_down", "attack_swing_charge_right_diagonal_pose",
        "attack_swing_charge_left", "attack_swing_heavy_down",
        "attack_swing_heavy_down_right", "attack_swing_heavy_left_up",
        "attack_swing_left_diagonal", "attack_swing_right_diagonal",
        "attack_swing_stab", "attack_swing_left", "attack_push", "parry_pose",
    },
    -- D: Elf 1H Axe (1h_axes_wood_elf). #196 divergence: the source action
    -- anim_event=attack_swing_up carries anim_event_3p=attack_swing_up_left, so
    -- the 3P vocab lists attack_swing_up_left (what the elf body actually plays).
    D = {
        "attack_swing_charge_left_diagonal", "attack_swing_charge_right_diagonal_pose",
        "attack_swing_charge_left_diagonal_pose", "attack_swing_heavy_down",
        "attack_swing_heavy_down_right", "attack_swing_left", "attack_swing_right",
        "attack_swing_down_right", "attack_swing_down", "attack_swing_up_left",
        "attack_push", "parry_pose",
    },
    -- E: Elf Spear & Shield (1h_spears_shield)
    E = {
        "attack_swing_charge_left", "attack_swing_charge_right_diagonal_pose",
        "attack_swing_charge_stab", "attack_swing_heavy_left",
        "attack_swing_heavy_down_right", "attack_swing_heavy_stab",
        "attack_swing_stab", "attack_swing_stab_lh", "push_stab",
        "attack_push", "parry_pose",
    },
    -- F: Dual Swords (dual_wield_swords)
    F = {
        "attack_swing_charge_diagonal", "attack_swing_charge_left",
        "attack_swing_charge_right", "attack_swing_heavy_left_diagonal",
        "attack_swing_heavy_right", "attack_swing_left_diagonal",
        "attack_swing_right_diagonal", "attack_swing_left", "attack_swing_right",
        "push_stab", "attack_push", "parry_pose",
    },
    -- G: Sword & Dagger (dual_wield_sword_dagger)
    G = {
        "attack_swing_charge_diagonal", "attack_swing_charge_left",
        "attack_swing_charge", "attack_swing_heavy_left_diagonal",
        "attack_swing_heavy", "attack_swing_right_diagonal", "attack_swing_left",
        "attack_swing_right", "attack_swing_stab", "push_stab",
        "attack_push", "parry_pose",
    },
    -- H: Elf Javelin (javelin) — melee chain + throw
    H = {
        "attack_swing_charge", "attack_chain_01", "attack_chain_02",
        "attack_chain_03", "attack_swing_stab", "attack_swing_stab_02",
        "attack_swing_stab_charge", "attack_swing_left", "attack_swing_right",
        "attack_swing_up", "attack_throw", "throw_charge", "reload",
    },
}

-- SET per Kerillian port = the `we_*` wield redirect target (wt_wield_patches;
-- the `to_*` event on each port's source template). Kept in lockstep with
-- _NEEDS_ANIMS.kerillian (wt_port_status.lua).
-- v0.12.201-dev: Kerillian batch-1 fully BAKED (we_) -> _CONFIRMED.kerillian; emptied in lockstep.
local _KERI_WEAPON_SET = {}

-- Source template per Kerillian port (where anim_event_3p is written). Confirmed
-- against ItemMasterList.
-- v0.12.201-dev: emptied in lockstep with the Kerillian batch-1 bake (see _KERI_WEAPON_SET).
local _KERI_WEAPON_TEMPLATE = {}

-- Per-weapon source attack anim_events (one dropdown each), deduped from the
-- source template's actions (inspect events excluded). Receiver-independent: the
-- shared source templates match the Kruber tables above.
-- v0.12.201-dev: emptied in lockstep with the Kerillian batch-1 bake (see _KERI_WEAPON_SET).
local _KERI_WEAPON_ATTACKS = {}

-- The receiver dispatch table. Kruber points at the EXISTING (unchanged) Kruber
-- tables; Saltzpyre at the new ones above. Move-label maps empty for Saltzpyre
-- (raw events shown). Add future receivers here.
local _RECV = {
    kruber = {
        short = "Kruber", careers = _KRUBER_CAREERS, query_career = "es_huntsman",
        set_label = _SET_LABEL, set_vocab = _SET_VOCAB, set_move_label = _SET_MOVE_LABEL,
        weapon_set = _WEAPON_SET, weapon_template = _WEAPON_TEMPLATE,
        weapon_attacks = _WEAPON_ATTACKS, source_move_label = _SOURCE_MOVE_LABEL,
    },
    saltzpyre = {
        short = "Saltzpyre", careers = _SALTZ_CAREERS, query_career = "wh_captain",
        set_label = _SALTZ_SET_LABEL, set_vocab = _SALTZ_SET_VOCAB, set_move_label = {},
        weapon_set = _SALTZ_WEAPON_SET, weapon_template = _SALTZ_WEAPON_TEMPLATE,
        weapon_attacks = _SALTZ_WEAPON_ATTACKS, source_move_label = {},
    },
    kerillian = {
        short = "Kerillian", careers = _KERI_CAREERS, query_career = "we_waywatcher",
        set_label = _KERI_SET_LABEL, set_vocab = _KERI_SET_VOCAB, set_move_label = {},
        weapon_set = _KERI_WEAPON_SET, weapon_template = _KERI_WEAPON_TEMPLATE,
        weapon_attacks = _KERI_WEAPON_ATTACKS, source_move_label = {},
    },
}
local _RECEIVERS = { "kruber", "saltzpyre", "kerillian" }  -- display/sort order

-- ---------------------------------------------------------------------------
-- Move-label resolvers (move-first, raw event as secondary clarifier).
-- ---------------------------------------------------------------------------
-- Separator between the gameplay move label and the raw anim_event clarifier.
local _LABEL_SEP = "  \194\183  "  -- "  ·  " (U+00B7 middle dot, UTF-8)

-- Target-side (dropdown OPTION) label for an event in a SET's vocab.
-- Returns "Heavy 2  ·  attack_swing_heavy", or the raw event if unlabeled.
local function _move_label_for_set(receiver, set, event)
    local m = _RECV[receiver].set_move_label[set]
    local move = m and m[event]
    if move then return move .. _LABEL_SEP .. event end
    return event
end

-- Source-side (attack ROW) label for a weapon's source attack event.
-- Returns "Light 1  ·  attack_swing_down_left", or the raw event if unlabeled
-- (the deliberate specials: slams, scythe specials, flame-sword spell).
local function _move_label_for_source(receiver, weapon_key, event)
    local m = _RECV[receiver].source_move_label[weapon_key]
    local move = m and m[event]
    if move then return move .. _LABEL_SEP .. event end
    return event
end

-- ---------------------------------------------------------------------------
-- Linear-scan helper (Lua 5.1 has no table.contains). Declared before use.
-- ---------------------------------------------------------------------------
local function _is_in(t, v)
    for i = 1, #t do
        if t[i] == v then return true end
    end
    return false
end

-- ---------------------------------------------------------------------------
-- Catalog: the ordered list of flagged weapons surfaced in the picker.
-- ---------------------------------------------------------------------------
-- Built once from _WEAPON_SET, gated on the _NEEDS_ANIMS.kruber allow-list (so a
-- weapon dropped from the allow-list disappears here too — single source of
-- truth). One entry per weapon; sorted A→Z by display label
-- (feedback_sort_categories_alphabetically). port_id is a stable, unique,
-- Lua-identifier-safe id used for setting_ids + dump constant names.
local _CATALOG = {}
local _catalog_built = false

-- Pick a representative Kruber career to feed the allow-list query. Any of the
-- four resolves identically (the allow-list is keyed by receiver bucket).
local _ALLOW_QUERY_CAREER = "es_huntsman"

local function _ensure_catalog_built()
    if _catalog_built then return end

    -- Membership gate: ONLY weapons explicitly flagged [Needs Animations] for the
    -- receiver (wt_port_status _NEEDS_ANIMS[receiver]). Belt-and-suspenders — every
    -- weapon_set key is in the allow-list by construction, but gating here keeps the
    -- two in lockstep if one is edited without the other. Iterated per receiver so
    -- each receiver's catalog entries carry its own careers/short/templates and a
    -- receiver-namespaced port_id ("p_<receiver>_<weapon_key>").
    local out = {}
    for _, r in ipairs(_RECEIVERS) do
        local rd = _RECV[r]
        for weapon_key, set in pairs(rd.weapon_set) do
            if _PORT_STATUS.needs_anims(rd.query_career, weapon_key) then
                out[#out + 1] = {
                    weapon_key    = weapon_key,
                    set           = set,
                    template_name = rd.weapon_template[weapon_key],
                    attacks       = rd.weapon_attacks[weapon_key] or {},
                    careers       = rd.careers,
                    char_key      = r,
                    label         = _weapon_display_name(weapon_key) .. " rendered on " .. rd.short .. " body",
                    port_id       = "p_" .. r .. "_" .. weapon_key,
                }
            end
        end
    end
    table.sort(out, function(a, b)
        if a.char_key ~= b.char_key then return a.char_key < b.char_key end
        return a.label < b.label
    end)
    _CATALOG = out
    _catalog_built = true

    _dbg("static catalog built: %d flagged weapon(s)", #_CATALOG)
    -- Surface any flagged weapon missing a template/attack table (would yield an
    -- empty dropdown set) so a stale hardcoded table is caught at boot.
    for _, e in ipairs(_CATALOG) do
        if not e.template_name then
            mod:warning("[wt:dev_anim] %s has no _WEAPON_TEMPLATE entry — row will have no dropdowns.", e.weapon_key)
        elseif #e.attacks == 0 then
            mod:warning("[wt:dev_anim] %s has no _WEAPON_ATTACKS entry — row will have no dropdowns.", e.weapon_key)
        end
    end
end

-- ---------------------------------------------------------------------------
-- Template / action introspection (live, for default seeding + apply)
-- ---------------------------------------------------------------------------

-- Current live anim_event_3p for a (template, source_event), if any sub-action
-- carrying that source anim_event already has a 3P override. Used as the
-- dropdown default so the menu reflects current state.
local function _first_anim_event_3p_for(template_name, source_event)
    local tpl = Weapons and rawget(Weapons, template_name)
    if not tpl or not tpl.actions then return nil end
    for _, action_group in pairs(tpl.actions) do
        if type(action_group) == "table" then
            for _, sub in pairs(action_group) do
                if type(sub) == "table" and sub.anim_event == source_event then
                    return sub.anim_event_3p
                end
            end
        end
    end
    return nil
end

-- ---------------------------------------------------------------------------
-- setting_id factories (globally unique per VMF_RECIPES § 6)
-- ---------------------------------------------------------------------------
local function _sid_group(port_id)
    return "wt_dev_anim_grp_" .. port_id
end

local function _sid_anim_event(port_id, source_event)
    return "wt_dev_anim_" .. port_id .. "_ev_" .. source_event
end

-- setting_id -> { port_id, template_name, kind="anim_event", source_event, ... }
--
-- CROSS-INSTANCE HAZARD (the v0.12.147-dev fix). `mod:dofile` RE-EXECUTES the
-- chunk on every call and does NOT cache/return a singleton — so the THREE
-- `mod:dofile("…/wt_dev_anim_picker")` call sites (weapon_tweaker.lua:139 SCRIPT,
-- weapon_tweaker_data.lua:1757 DATA, weapon_tweaker_localization.lua:1366 LOC)
-- each get their OWN private copy of this upvalue. Only the DATA instance ever
-- ran `build_widget_tree()` (which is what populates `_setting_index`), so the
-- SCRIPT instance's `_setting_index` stayed EMPTY — and `install()` →
-- `reapply_stored_picks()` (boot) and `on_setting_changed()` (live) both run on
-- the SCRIPT instance, iterating an empty table → ZERO picks applied, ZERO
-- `[wt:apply]` lines, every `[wt:play]` showing `picks_set={}`. The dropdowns
-- still rendered the user's stored picks because they're drawn off VMF settings
-- by the DATA instance, masking the empty SCRIPT-side index. FIX:
-- `_ensure_setting_index_built()` rebuilds the index lazily from the same static
-- tables on WHICHEVER instance needs it, so the apply path is self-sufficient
-- regardless of which dofile instance it runs on.
local _setting_index = {}
local _setting_index_built = false

-- Register one setting_index record for (entry, source_event). Single source of
-- truth shared by `_build_attack_dropdown` (DATA instance, building widgets) and
-- `_ensure_setting_index_built` (SCRIPT instance, apply-only) so the rec shape
-- can never drift between the two. Returns sid + default_value for the caller.
local function _register_attack_setting(entry, source_event)
    local sid = _sid_anim_event(entry.port_id, source_event)
    local cur = _first_anim_event_3p_for(entry.template_name, source_event)
    local default_value = cur or UNSET
    _setting_index[sid] = {
        port_id       = entry.port_id,
        template_name = entry.template_name,
        kind          = "anim_event",
        source_event  = source_event,
        receiver_char = entry.char_key,
        default_value = default_value,
    }
    return sid, default_value
end

-- Populate `_setting_index` on THIS dofile instance without building any widgets.
-- The apply/boot-replay path (reapply_stored_picks, on_setting_changed) lives on
-- the SCRIPT instance, which never calls build_widget_tree() (only the DATA
-- instance does) — so without this the SCRIPT-side index is empty and nothing is
-- ever applied. Idempotent + cheap (static tables, no catalog/vocab walk).
local function _ensure_setting_index_built()
    if _setting_index_built then return end
    _ensure_catalog_built()
    local n = 0
    for _, entry in ipairs(_CATALOG) do
        for _, source_event in ipairs(entry.attacks) do
            _register_attack_setting(entry, source_event)
            n = n + 1
        end
    end
    _setting_index_built = true
    _dbg("setting index built (apply-side): %d setting(s)", n)
end

-- ---------------------------------------------------------------------------
-- Dropdown options factory (fresh table per widget — VMF_RECIPES § 5)
-- ---------------------------------------------------------------------------
-- Options = the established SET's hardcoded vocab + a "(current)" pin for any
-- live/default value off-vocab + the UNSET fall-through sentinel.
-- The `value` stored to settings stays the RAW anim_event (the apply path reads
-- it verbatim) — only the displayed `text` is the move-first label
-- ("Heavy 2  ·  attack_swing_heavy" via _move_label_for_set; raw event for any
-- unlabeled vocab entry). loc_keys() registers each text string as its own key.
local function _build_options(receiver, set, default_value)
    local vocab = _RECV[receiver].set_vocab[set] or {}
    local opts = {}
    local seen = {}

    if default_value and default_value ~= UNSET and not _is_in(vocab, default_value) then
        -- Off-vocab current value: prefix the SET move-label if it happens to map,
        -- else the raw event, then the "(current)" pin.
        opts[#opts + 1] = { text = _move_label_for_set(receiver, set, default_value) .. " (current)", value = default_value }
        seen[default_value] = true
    end

    for _, v in ipairs(vocab) do
        if not seen[v] then
            opts[#opts + 1] = { text = _move_label_for_set(receiver, set, v), value = v }
            seen[v] = true
        end
    end

    opts[#opts + 1] = { text = "(unset - fall through)", value = UNSET }
    return opts
end

-- ---------------------------------------------------------------------------
-- Widget tree construction
-- ---------------------------------------------------------------------------

-- One per-attack 3P-anim dropdown for one source attack. Options = the weapon's
-- established SET vocab (HARDCODED). Registers a kind="anim_event" rec so the
-- existing _apply_anim_event_change (writes anim_event_3p ONLY — 3P) + persist +
-- boot-replay apply the pick with no new apply code.
local function _build_attack_dropdown(entry, source_event)
    -- Register the apply-side rec through the shared helper so the DATA-instance
    -- widget build and the SCRIPT-instance apply-only build can never drift.
    local sid, default_value = _register_attack_setting(entry, source_event)

    return {
        setting_id    = sid,
        type          = "dropdown",
        default_value = default_value,
        options       = _build_options(entry.char_key, entry.set, default_value),
        tooltip       = "wt_dev_anim_attack_tooltip",
    }
end

-- One collapsible GROUP per flagged weapon, with one per-attack dropdown inside.
-- The group → dropdown nesting keeps the gut Mod Tweaker depth-drill working.
local function _build_weapon_group(entry)
    local sub_widgets = {}
    for _, source_event in ipairs(entry.attacks) do
        sub_widgets[#sub_widgets + 1] = _build_attack_dropdown(entry, source_event)
    end
    return {
        setting_id  = _sid_group(entry.port_id),
        type        = "group",
        sub_widgets = sub_widgets,
    }
end

-- Top-level entry point (weapon_tweaker_data.lua). Returns the ARRAY of per-weapon
-- group widgets (never nil). _data.lua nests this as the `sub_widgets` of the
-- enable_dev_anim_picker CHECKBOX — VMF reveals/hides them LIVE on toggle
-- (reference_vmf_native_master_toggle_submenu). Built unconditionally at boot so
-- the children are in the tree for VMF to reveal; the static-table build is
-- trivially cheap (no catalog/vocab walk).
function M.build_widget_tree()
    _setting_index = {}
    _setting_index_built = false
    _ensure_catalog_built()

    local sub_widgets = {}
    for _, entry in ipairs(_CATALOG) do
        if not (Weapons and rawget(Weapons, entry.template_name)) then
            mod:warning("[wt:dev_anim] %s references missing Weapons.%s — row surfaced anyway (live-apply no-ops until template loads).",
                entry.weapon_key, tostring(entry.template_name))
        end
        sub_widgets[#sub_widgets + 1] = _build_weapon_group(entry)
    end
    -- _build_weapon_group -> _build_attack_dropdown -> _register_attack_setting
    -- fully populated `_setting_index` for this instance; mark it built so a later
    -- _ensure_setting_index_built() on this same instance is a no-op.
    _setting_index_built = true
    _dbg("widget tree: %d weapon group(s)", #sub_widgets)
    return sub_widgets
end

-- ---------------------------------------------------------------------------
-- Localization
-- ---------------------------------------------------------------------------
-- All group labels / dropdown labels / option texts must be registered at boot
-- REGARDLESS of the toggle, because the widgets are in the tree at boot
-- (sub_widgets of the enable_dev_anim_picker checkbox) and VMF reveals them live
-- on toggle — an unregistered key renders `<<key>>` the instant the box flips.
function M.loc_keys()
    _ensure_catalog_built()

    local keys = {
        wt_dev_anim_picker = { en = "Dev: 3P Anim Picker" },
        wt_dev_anim_attack_tooltip = {
            en = "Choose which third-person animation plays for this attack, from the weapon's built-in animation set; the change applies right away on your equipped weapon and affects only the third-person view. If the character has no matching animation, it keeps the previous pose instead.",
        },
    }

    -- VMF wraps unknown loc keys in `<>` when rendering dropdowns, so each option
    -- `text` value (raw event, "(current)" pin, sentinel) must be its own key.
    local function _register_self(text)
        if text and not keys[text] then keys[text] = { en = text } end
    end

    _register_self("(unset - fall through)")

    -- Register every SET vocab OPTION text (move-first label + "(current)" pin),
    -- matching exactly what `_build_options` emits for each option's `text`. The
    -- displayed option is "Heavy 2  ·  attack_swing_heavy" (move-first); the
    -- stored `value` is the raw event. Both the labeled form and the raw form are
    -- registered so an off-vocab/unlabeled fall-through still resolves.
    for _, r in ipairs(_RECEIVERS) do
        for set, vocab in pairs(_RECV[r].set_vocab) do
            for _, v in ipairs(vocab) do
                local labeled = _move_label_for_set(r, set, v)
                _register_self(labeled)
                _register_self(labeled .. " (current)")
                -- Raw forms too (unlabeled fall-through + off-vocab "(current)" pins).
                _register_self(v)
                _register_self(v .. " (current)")
            end
        end
    end

    -- Per-weapon group label + per-attack dropdown labels.
    for _, entry in ipairs(_CATALOG) do
        -- Group label: "<character> <weapon type> rendered on Kruber body  [<set>]".
        -- The [set] bracket is the established animation-set name (NOT a status
        -- tag — status tags moved to the Weapon Availability menu).
        keys[_sid_group(entry.port_id)] = {
            en = entry.label .. "  [" .. (_RECV[entry.char_key].set_label[entry.set] or entry.set) .. "]",
        }
        for _, src in ipairs(entry.attacks) do
            -- Attack ROW label = move-first ("↳ Light 1  ·  attack_swing_down_left"),
            -- falling through to "↳ <raw event>" for the deliberate specials
            -- (slams / scythe specials / flame-sword spell) that have no move label.
            keys[_sid_anim_event(entry.port_id, src)] = {
                en = "↳ " .. _move_label_for_source(entry.char_key, entry.weapon_key, src),
            }
            -- A live anim_event_3p default may be off-vocab — register its
            -- "(current)" pin (both the SET-labeled form, in case it maps, and the
            -- raw form) so it doesn't VMF-wrap.
            local cur = _first_anim_event_3p_for(entry.template_name, src)
            if type(cur) == "string" then
                local cur_labeled = _move_label_for_set(entry.char_key, entry.set, cur)
                _register_self(cur_labeled)
                _register_self(cur_labeled .. " (current)")
                _register_self(cur)
                _register_self(cur .. " (current)")
            end
        end
    end

    return keys
end

-- ---------------------------------------------------------------------------
-- Live re-apply
-- ---------------------------------------------------------------------------
local function _dropdown_value_to_field(v)
    if v == nil or v == UNSET then return nil end
    return v
end

-- THE LOAD-BEARING FIX (v0.12.144-dev). The engine does NOT read sub-actions off
-- the live `Weapons[name]` table the picker mutates — it reads them off
-- `MechanismOverrides.get(rawget(Weapons, name))`
-- (Vermintide-2-Source-Code/scripts/helpers/weapon_utils.lua:211 ->
-- backend_interface_item_playfab.lua:871 -> backend_utils.lua:136 ->
-- WeaponUnitExtension.start_action -> get_action_anim_event reading
-- current_action_settings.anim_event_3p). MechanismOverrides.get
-- (.../game_mode/mechanisms/mechanism_overrides.lua:13) shallow-COPIES any
-- template (or nested child) that carries a `mechanism_overrides` field and
-- caches that copy in `CACHE[t]`, persisting across calls for the whole
-- mechanism. Once cached, every get_item_template returns the stale COPY, so a
-- menu-time write to the live `Weapons[name]` original is never seen by an
-- attack. Invalidating `CACHE[Weapons[name]]` forces the next get_item_template
-- to rebuild the copy from the now-mutated live template. `recursive_cleanup`
-- (mechanism_overrides.lua:119) removes that entry; it's a guarded no-op
-- (`if original then`) when the template was never cached (e.g. a template with
-- no overrides anywhere in its tree), so it's safe to call unconditionally.
local function _bust_mechanism_override_cache(template_name)
    if not (MechanismOverrides and MechanismOverrides.recursive_cleanup) then return false end
    local tpl = Weapons and rawget(Weapons, template_name)
    if not tpl then return false end
    local mech = Managers and Managers.mechanism
    local mech_name = mech and mech.current_mechanism_name and mech:current_mechanism_name()
    -- recursive_cleanup keys its "is this the same mechanism" decision off
    -- new_mechanism_name; pass the live mechanism so a same-mechanism rebuild
    -- isn't mistakenly skipped. nil is tolerated (cleanup still drops CACHE[t]).
    local ok, err = pcall(MechanismOverrides.recursive_cleanup, tpl, mech_name)
    if not ok then
        _dbg("[apply] MechanismOverrides cache-bust raised for tpl=%s (%s)", tostring(template_name), tostring(err))
        return false
    end
    _dbg("[apply] MechanismOverrides cache busted for tpl=%s (mech=%s)", tostring(template_name), tostring(mech_name))
    return true
end

-- Collect the live template's actual (action_kind, sub_action, anim_event) tuples.
-- Used by the n==0 diagnostic so a source-string mismatch is visible in the log:
-- we print the vocab the engine will actually read, next to the source string the
-- dropdown tried to match. v0.12.145-dev instrumentation.
local function _live_anim_event_vocab(tpl)
    local out = {}
    if not (tpl and tpl.actions) then return out end
    for action_kind, action_group in pairs(tpl.actions) do
        if type(action_group) == "table" then
            for sub_name, sub in pairs(action_group) do
                if type(sub) == "table" and type(sub.anim_event) == "string" then
                    out[#out + 1] = string.format("%s.%s:anim_event=%s,anim_event_3p=%s",
                        tostring(action_kind), tostring(sub_name),
                        tostring(sub.anim_event), tostring(sub.anim_event_3p))
                end
            end
        end
    end
    table.sort(out)
    return out
end

-- Writes anim_event_3p (3P only) on every sub-action of the template whose
-- source anim_event matches rec.source_event. Returns the count mutated.
local function _apply_anim_event_change(rec, new_value)
    local tpl = Weapons and rawget(Weapons, rec.template_name)
    if not tpl or not tpl.actions then
        mod:warning("[wt:dev_anim] Weapons.%s.actions missing; cannot apply anim_event change", tostring(rec.template_name))
        return 0
    end
    local field_value = _dropdown_value_to_field(new_value)
    local n = 0
    -- Capture which action.sub each write landed on (proves the write reached
    -- the same sub-action the engine selects at swing time).
    local hits = {}
    for action_kind, action_group in pairs(tpl.actions) do
        if type(action_group) == "table" then
            for sub_name, sub in pairs(action_group) do
                if type(sub) == "table" and sub.anim_event == rec.source_event then
                    sub.anim_event_3p = field_value
                    n = n + 1
                    hits[#hits + 1] = tostring(action_kind) .. "." .. tostring(sub_name)
                end
            end
        end
    end
    -- Drop the stale MechanismOverrides shallow-copy so the engine re-reads the
    -- now-mutated live template on the next get_item_template. Always — even when
    -- n == 0, an already-cached copy must not outlive intent; the call is a
    -- guarded no-op when nothing was cached.
    _bust_mechanism_override_cache(rec.template_name)
    -- [wt:apply] — ALWAYS logged (not gated on enable_debug_logging) so a single
    -- attack's apply trail is in every user log. Proves (a) the write reached the
    -- template the wielded weapon uses, and (b) HOW MANY sub-actions matched.
    -- v0.12.145-dev diagnostic.
    mod:info("[wt:apply] tpl=%s source_event=%s -> anim_event_3p=%s n=%d sites={%s}",
        tostring(rec.template_name), tostring(rec.source_event),
        tostring(field_value), n, table.concat(hits, ","))
    if n == 0 then
        -- LOUD: a zero-match write means rec.source_event isn't an actual
        -- anim_event on any sub-action of this template — the hardcoded
        -- _WEAPON_ATTACKS source string doesn't match the live template vocab,
        -- so the dropdown silently does nothing. Surface it (was silent before).
        mod:warning("[wt:dev_anim] no-op write: source_event=%q not found on any Weapons.%s sub-action — dropdown writes nothing (stale _WEAPON_ATTACKS? run /wt_coverage or /wt_dump_anim_picks).",
            tostring(rec.source_event), tostring(rec.template_name))
        -- Dump the live vocab so the mismatch is diagnosable from the log alone.
        local vocab = _live_anim_event_vocab(tpl)
        mod:info("[wt:apply] live Weapons.%s vocab (%d sub-actions): %s",
            tostring(rec.template_name), #vocab, table.concat(vocab, " | "))
    end
    return n
end

-- Force a wield refresh so the engine re-reads anim_event_3p on the next event.
local function _try_force_rewield()
    local pm = Managers.player
    if not pm then return false, "Managers.player nil" end
    local player = pm:local_player()
    if not player then return false, "no local_player" end
    local unit = player.player_unit
    if not unit then return false, "no player_unit" end
    if not ScriptUnit or not ScriptUnit.has_extension then return false, "no ScriptUnit" end

    local inv = ScriptUnit.has_extension(unit, "inventory_system")
    if not inv then return false, "no inventory_system extension" end

    local slot
    if inv.get_wielded_slot_name then
        local ok, name = pcall(inv.get_wielded_slot_name, inv)
        if ok then slot = name end
    end
    if not slot then
        local equipment = inv._equipment or inv.equipment
        slot = equipment and equipment.wielded_slot
    end
    if not slot then return false, "no wielded_slot" end

    local ok, err = pcall(function() inv:wield(slot) end)
    if not ok then
        return false, "wield() raised: " .. tostring(err)
    end
    return true
end

function M.on_setting_changed(setting_id)
    -- Runs on the SCRIPT instance (mod.on_setting_changed -> here). That instance
    -- never built the index via build_widget_tree(), so populate it here too —
    -- otherwise rec is always nil and every live dropdown change is a silent
    -- no-op. See _setting_index hazard note.
    _ensure_setting_index_built()
    local rec = _setting_index[setting_id]
    if not rec then return end -- not one of ours
    local new_value = mod:get(setting_id)

    local n = _apply_anim_event_change(rec, new_value)
    if n <= 0 then return end

    local rw_ok, rw_err = _try_force_rewield()
    if not rw_ok then
        mod:info("[wt:dev_anim] applied %s = %s; couldn't auto-rewield (%s) — unwield/rewield manually to see change",
            setting_id, tostring(new_value), tostring(rw_err))
    else
        _dbg("[apply] auto-rewield OK for setting=%s value=%s", setting_id, tostring(new_value))
    end
end

-- ---------------------------------------------------------------------------
-- /wt_dump_anim_picks chat command
-- ---------------------------------------------------------------------------
local function _dump_port(entry)
    local pname = "_" .. entry.port_id:upper():gsub("[^A-Z0-9_]", "_")
    local tpl = Weapons and rawget(Weapons, entry.template_name)
    if not tpl then
        mod:info("-- ==== %s (template missing: %s) ====", entry.label, tostring(entry.template_name))
        return
    end

    mod:info("-- ==== %s  [SET %s = %s] (%s) (on %s) ====",
        entry.label, entry.set, (_RECV[entry.char_key].set_label[entry.set] or entry.set),
        entry.template_name, _RECV[entry.char_key].short)

    mod:info("local %s_ANIM_REMAP_3P = {", pname)
    local any_remap = false
    for _, source_event in ipairs(entry.attacks) do
        local target = _first_anim_event_3p_for(entry.template_name, source_event)
        if target then
            mod:info("    %-36s = %q,", source_event, target)
            any_remap = true
        end
    end
    if not any_remap then
        mod:info("    -- (no anim_event_3p remaps set)")
    end
    mod:info("}")
    mod:info("")
end

local function _register_dump_command()
    mod:command("wt_dump_anim_picks",
        "Dump current 3P anim picker values as Lua-pastable snippets",
        function()
            _ensure_catalog_built()
            mod:info("-- ==== wt 3P Anim Picker dump (%d weapon(s)) ====", #_CATALOG)
            for _, entry in ipairs(_CATALOG) do
                _dump_port(entry)
            end
            mod:info("-- ==== end dump ====")
            mod:echo("Anim picker dump written to console log.")
        end)
end

-- ---------------------------------------------------------------------------
-- /wt_coverage probe — PROJECT_STANDARDS §3.7 data harness
-- ---------------------------------------------------------------------------
-- For the CURRENT character, reports per flagged weapon whether each per-action
-- anim_event_3p is actually AUTHORED on the local 3P skeleton. Caveat: "authored"
-- proves the clip exists, NOT that it plays visibly in chain states.
local function _coverage_has_anim(unit, event)
    if type(event) ~= "string" or event == "" then return false end
    local ok, result = pcall(Unit.has_animation_event, unit, event)
    return ok and result == true
end

local function _register_coverage_command()
    mod:command("wt_coverage",
        "3P coverage probe for the CURRENT character: per-weapon action events vs the local skeleton",
        function()
            _ensure_catalog_built()
            local pm = Managers and Managers.player
            local player = pm and pm:local_player()
            local unit = player and player.player_unit
            if not unit then
                mod:echo("[wt_coverage] no local player unit — run from the keep or a mission.")
                return
            end

            local weapons, full, partial, broken = 0, 0, 0, 0
            mod:info("[wt:coverage] ==== 3P anim picker coverage (current character) ====")
            for _, entry in ipairs(_CATALOG) do
                weapons = weapons + 1
                local tpl = Weapons and rawget(Weapons, entry.template_name)
                if not tpl then
                    broken = broken + 1
                    mod:info("[wt:coverage] weapon=%s tpl=%s STATUS=template_missing", entry.weapon_key, tostring(entry.template_name))
                else
                    local total, authored, missing = 0, 0, {}
                    for _, action_group in pairs(tpl.actions or {}) do
                        if type(action_group) == "table" then
                            for _, sub in pairs(action_group) do
                                if type(sub) == "table" and type(sub.anim_event_3p) == "string" then
                                    total = total + 1
                                    if _coverage_has_anim(unit, sub.anim_event_3p) then
                                        authored = authored + 1
                                    elseif #missing < 6 then
                                        missing[#missing + 1] = sub.anim_event_3p
                                    end
                                end
                            end
                        end
                    end
                    local status
                    if total > 0 and authored == total then
                        status = "FULL"; full = full + 1
                    elseif authored > 0 then
                        status = "PARTIAL"; partial = partial + 1
                    else
                        status = "NONE"; broken = broken + 1
                    end
                    mod:info("[wt:coverage] weapon=%s tpl=%s set=%s actions_3p=%d authored=%d missing={%s} STATUS=%s",
                        entry.weapon_key, entry.template_name, entry.set,
                        total, authored, table.concat(missing, ","), status)
                end
            end
            mod:info("[wt:coverage] ==== %d weapon(s): %d FULL, %d PARTIAL, %d NONE/missing ====",
                weapons, full, partial, broken)
            mod:echo("[wt_coverage] %d weapon(s) probed — %d full, %d partial, %d none. Details in console log.",
                weapons, full, partial, broken)
        end)
end

-- ---------------------------------------------------------------------------
-- Boot re-apply of stored picks
-- ---------------------------------------------------------------------------
-- Picker picks live in the VMF settings store and apply live via
-- on_setting_changed, but are NEVER replayed onto Weapons.* at boot unless this
-- runs — so every tuned attack would revert to template defaults on restart.
-- Only settings the user EXPLICITLY changed are re-applied (stored value ~=
-- build-time default), so we don't overwrite vanilla/patcher state with stale
-- pre-build defaults.
function M.reapply_stored_picks()
    -- This runs on the SCRIPT dofile instance (install() at the bottom of
    -- weapon_tweaker.lua), which never called build_widget_tree() — so without
    -- this the index is empty and nothing replays. See _setting_index hazard note.
    _ensure_setting_index_built()
    local applied, skipped_missing = 0, 0
    for sid, rec in pairs(_setting_index) do
        local v = mod:get(sid)
        if v ~= nil and v ~= rec.default_value then
            local tpl = Weapons and rawget(Weapons, rec.template_name)
            if not tpl then
                skipped_missing = skipped_missing + 1
            elseif rec.kind == "anim_event" then
                if _apply_anim_event_change(rec, v) > 0 then applied = applied + 1 end
            end
        end
    end
    if applied > 0 or skipped_missing > 0 then
        mod:info("[wt:dev_anim] boot re-apply: %d stored pick(s) applied%s. /wt_dump_anim_picks to export as source.",
            applied,
            skipped_missing > 0 and (", " .. skipped_missing .. " skipped (template missing)") or "")
    end
    return applied
end

-- ---------------------------------------------------------------------------
-- Play-path instrumentation hooks (v0.12.145-dev)
-- ---------------------------------------------------------------------------
-- These let the main script's animation_event hook decide whether a given 3P
-- body is wielding a PICKED weapon (so the [wt:play] trace stays scoped to the
-- weapons the picker actually touches, not every swing in the game).

-- Reverse map: template_name -> true, for every weapon the picker surfaces.
-- Built lazily from the catalog (which is itself gated on the _NEEDS_ANIMS
-- allow-list), so it tracks the live set of flagged weapons.
local _picked_template_set = nil
local function _ensure_template_set()
    if _picked_template_set then return end
    _ensure_catalog_built()
    local s = {}
    for _, entry in ipairs(_CATALOG) do
        if entry.template_name then s[entry.template_name] = true end
    end
    _picked_template_set = s
end

-- True if template_name is one of the picker's flagged-weapon templates.
function M.is_picker_template(template_name)
    if not template_name then return false end
    _ensure_template_set()
    return _picked_template_set[template_name] == true
end

-- Regression hook (#159): weapon_keys in the built catalog whose display label
-- fell back to the raw internal key (i.e. no documented localization resolved).
-- Should always be empty — a non-empty result means a picker weapon would show
-- e.g. "Sienna bw_deus_01" instead of "Sienna: Coruscation Staff".
function M.unresolved_display_names()
    _ensure_catalog_built()
    local bad = {}
    for _, e in ipairs(_CATALOG) do
        -- label embeds the weapon name; if it still contains the raw key, the
        -- documented-name lookup missed and _weapon_display_name fell back.
        if e.label and e.label:find(e.weapon_key, 1, true) then
            bad[#bad + 1] = e.weapon_key
        end
    end
    return bad
end

-- Regression hook (user 2026-06-29): inspect must NOT be a tunable dropdown — the
-- picker should never remap it (the weapon keeps its existing inspect animation).
-- Returns any catalog (weapon:event) whose source attack is an inspect event.
-- Should always be empty.
function M.inspect_attacks()
    _ensure_catalog_built()
    local bad = {}
    for _, e in ipairs(_CATALOG) do
        for _, ev in ipairs(e.attacks) do
            if type(ev) == "string" and ev:find("inspect", 1, true) then
                bad[#bad + 1] = e.weapon_key .. ":" .. ev
            end
        end
    end
    return bad
end

-- Issue #411: every source-event row advertised by the picker must resolve to
-- at least one live sub-action on its declared source template. A stale event
-- makes the dropdown a silent no-op (`_apply_anim_event_change` writes n=0).
-- Returns failures plus coverage counts so both /wt_regression_test and the
-- focused verification command exercise the exact catalog VMF registered.
function M.source_event_coverage()
    _ensure_catalog_built()
    local failures, missing_templates = {}, {}
    local weapons, events = 0, 0
    for _, e in ipairs(_CATALOG) do
        weapons = weapons + 1
        local tpl = Weapons and rawget(Weapons, e.template_name)
        if not (tpl and tpl.actions) then
            missing_templates[#missing_templates + 1] = e.weapon_key .. "=" .. tostring(e.template_name)
        else
            local live = {}
            for _, action_group in pairs(tpl.actions) do
                if type(action_group) == "table" then
                    for _, sub in pairs(action_group) do
                        if type(sub) == "table" and type(sub.anim_event) == "string" then
                            live[sub.anim_event] = true
                        end
                    end
                end
            end
            for _, source_event in ipairs(e.attacks) do
                events = events + 1
                if not live[source_event] then
                    failures[#failures + 1] = e.weapon_key .. ":" .. source_event
                        .. " (" .. e.template_name .. ")"
                end
            end
        end
    end
    table.sort(failures)
    table.sort(missing_templates)
    return failures, weapons, events, missing_templates
end

-- Regression hook (#196): a SET's vocab must list anim_event_3p VALUES (what the
-- picker writes + the body plays), never the 1P anim_event names. Exposes a set's
-- vocab so a test can assert the billhook charge fix didn't regress.
function M.set_vocab_for(receiver, set)
    local rd = _RECV[receiver]
    return rd and rd.set_vocab and rd.set_vocab[set] or nil
end

-- Regression hook (#159/#197): the (group setting_id, weapon_key) for every catalog
-- entry, so a test can verify the REGISTERED localized label (mod:localize on the sid
-- = the actual string VMF renders) resolves to a real name — not a raw internal key
-- and not an unregistered <key>. Checking the registered value (vs a freshly-rebuilt
-- label) is what catches a label registered BEFORE names could resolve (#197).
function M.catalog_group_keys()
    _ensure_catalog_built()
    local out = {}
    for _, e in ipairs(_CATALOG) do
        out[#out + 1] = { sid = _sid_group(e.port_id), weapon_key = e.weapon_key }
    end
    return out
end

-- The anim_event_3p the picker would currently apply for (template, source_event),
-- read live off the mutated Weapons template. Returns the string, or nil if the
-- source_event has no 3P override on any sub-action (UNSET / never picked).
-- This is what the engine SHOULD be reading at swing time for that attack.
function M.current_3p_for(template_name, source_event)
    return _first_anim_event_3p_for(template_name, source_event)
end

-- Live snapshot of every (source anim_event -> picked anim_event_3p) mapping
-- currently set on the template's sub-actions. The KEY insight for the play-path
-- trace: on the 3P body the engine fires the picked `anim_event_3p` VALUE
-- directly (weapon_unit_extension.lua:512), so what arrives at the
-- animation_event hook should be one of these VALUES. This map lets the trace
-- report, for the 3P event the engine read, whether it MATCHES a picked value
-- (pick took) or is still a template default (pick was lost upstream).
-- Returns { source_event = picked_3p_value, ... } (only sub-actions with a 3P
-- override set).
function M.live_3p_map(template_name)
    local out = {}
    local tpl = Weapons and rawget(Weapons, template_name)
    if not (tpl and tpl.actions) then return out end
    for _, action_group in pairs(tpl.actions) do
        if type(action_group) == "table" then
            for _, sub in pairs(action_group) do
                if type(sub) == "table" and type(sub.anim_event) == "string"
                    and type(sub.anim_event_3p) == "string" then
                    out[sub.anim_event] = sub.anim_event_3p
                end
            end
        end
    end
    return out
end

-- True if `event_3p` is one of the anim_event_3p VALUES the picker currently has
-- set on this template (i.e. an event the user picked that the engine should be
-- firing on the 3P body). Used by the play-path trace to confirm the read event
-- is a picked value rather than a leftover template default.
function M.is_picked_3p_value(template_name, event_3p)
    if not event_3p then return false end
    local map = M.live_3p_map(template_name)
    for _, picked_val in pairs(map) do
        if picked_val == event_3p then return true end
    end
    return false
end

-- ---------------------------------------------------------------------------
-- install()
-- ---------------------------------------------------------------------------
function M.install()
    if not Weapons then
        mod:warning("[wt:dev_anim] Weapons global nil at install; live-apply will warn until templates load.")
    end

    _ensure_catalog_built()

    for _, entry in ipairs(_CATALOG) do
        if not (Weapons and rawget(Weapons, entry.template_name)) then
            mod:warning("[wt:dev_anim] Weapons.%s missing at install; submenu surfaced but live-apply is a no-op until template loads.",
                tostring(entry.template_name))
        end
    end

    _register_dump_command()
    _register_coverage_command()
    mod:command("verify_wt_anim_picker_sources",
        "Verify every Anim Picker source event writes a live weapon action", function()
            local failures, weapons, events, missing = M.source_event_coverage()
            if #failures == 0 then
                mod:echo("[wt:411] PASS: %d source events across %d picker weapons resolve live",
                    events, weapons)
            else
                mod:echo("[wt:411] FAIL: %d dead Anim Picker source event(s)", #failures)
                for _, failure in ipairs(failures) do
                    mod:echo("  %s", failure)
                    printf("[wt:411] dead picker source: %s", failure)
                end
            end
            if #missing > 0 then
                mod:echo("[wt:411] NOTE: %d unavailable template(s) skipped; see console log", #missing)
                printf("[wt:411] unavailable picker templates skipped: %s", table.concat(missing, ", "))
            end
        end)

    local dead, covered_weapons, covered_events, unavailable = M.source_event_coverage()
    printf("[wt:411] picker source coverage: weapons=%d events=%d dead=%d unavailable_templates=%d",
        covered_weapons, covered_events, #dead, #unavailable)
    for _, failure in ipairs(dead) do printf("[wt:411] dead picker source: %s", failure) end

    -- Replay user-tuned picks onto the live templates. install() runs at the END
    -- of main wt.lua — after every template patcher — so this layers user picks
    -- on top of patcher output, same as a live menu change.
    M.reapply_stored_picks()

    mod:info("[wt:dev_anim] installed (static). %d weapon(s) flagged [Needs Animations] across receivers. /wt_dump_anim_picks to dump.",
        #_CATALOG)
end

return M
