--[[
============================================================================
 wt_port_status.lua — shared (career, weapon_key) -> internal 3P port state
============================================================================

Single source of truth for internal 3P picker/audit state. Player-facing Weapon
Availability labels deliberately do not expose this engineering lifecycle.

3P-ONLY. State describes the THIRD-person animation port only — 1P is
universal across all six characters and never needs cross-character work
(feedback_1p_animations_universal).

INTERNAL STATE VOCABULARY (aligned to
KRUBER_3P_ANIM_DECISIONS.md:14-20 + the picker):
  working          — 3P confirmed (native, or a verified cross-character port).
  needs_animations — a wield SET redirect is chosen + works at set level, but
                     the per-attack animation mapping is still pending.
  needs_offsets    — set chosen, 3P grip offset still needed.
  untested         — no decision captured yet.

PROVENANCE of the confirmed/untested/offsets sets below: generated 2026-06-23
from a parse of ANIMATION_COVERAGE.md (✅ WORKING / 🔁 native -> working;
❓ -> untested; rows marked as grip work -> needs_offsets) merged
with KRUBER_3P_ANIM_DECISIONS.md CONFIRMED rows and the picker's
_COVERAGE_CONFIRMED_KRUBER / _PORT_STATUS_LABEL. The code does NOT parse the
.md at runtime (mod sandbox can't reliably io.open repo files) — these are the
generated mirror. When a COVERAGE row flips, regenerate or hand-edit here.

RECEIVER BUCKETS mirror the .md sections. Saltzpyre = the three non-WP careers
(wh_captain/wh_bountyhunter/wh_zealot); wh_priest is its own bucket (all native
or priest-specific redirects -> working per ANIMATION_COVERAGE.md:181-185);
Sienna has zero cross-character ports (all native -> working).
============================================================================
--]]

local M = {}

-- char_key -> { weapon_key = true } : confirmed ports on that receiver
-- (cross-character verified; natives are handled separately by the prefix rule).
local _CONFIRMED = {
    kruber = {
        -- user-confirmed in-game 2026-06-28: Falchion (#176) + Crowbill (#177) on Kruber.
        wh_1h_falchion = true,      -- Saltzpyre "Falchion" rendered on Kruber
        bw_1h_crowbill = true,      -- Sienna "Crowbill" rendered on Kruber (was held, now confirmed)
        bw_1h_flail_flaming = true, dr_2h_axe = true, dr_shield_axe = true,
        we_1h_spears_shield = true, we_1h_sword = true, we_2h_sword = true,
        we_longbow = true, we_spear = true, wh_1h_axe = true,
        wh_2h_billhook = true, wh_brace_of_pistols = true, wh_repeating_pistols = true,
        -- KRUBER_3P_ANIM_DECISIONS.md CONFIRMED extras (Saltzpyre's regular Flail
        -- renders as Empire Flail on Kruber = native es_1h_flail; Sienna's Flail
        -- redirect bw_1h_flail_flaming above; Crowbill held 🧊 — NOT confirmed).
        -- v0.12.149-dev: 4 ports BAKED career-scoped into _3p_template_remaps
        -- (weapon_tweaker.lua) after picker tuning was confirmed on Kruber —
        -- moved out of _NEEDS_ANIMS into CONFIRMED so the Availability tag reads
        -- [Working]. Per-attack picks live in the bake, not the picker.
        dr_2h_pick = true,          -- -> Empire Greathammer
        bw_dagger = true,           -- -> Empire 1H Sword
        bw_flame_sword = true,      -- -> Empire 1H Sword
        -- v0.12.150-dev: 2 more ports BAKED career-scoped into _3p_template_remaps
        -- (weapon_tweaker.lua .one_handed_hammer_wizard_template_1.es_ /
        -- .staff_scythe.es_) after picker tuning confirmed on Kruber. The Scythe
        -- ALSO bakes a +0.569 Z es_-scoped 3P grip offset (_weapon_grip_offsets).
        bw_1h_mace = true,          -- -> Empire Greathammer
        bw_ghost_scythe = true,     -- -> Empire Greathammer (+ 3P grip offset)
        -- v0.12.151-dev: 2 more ports BAKED career-scoped into _3p_template_remaps
        -- (.two_handed_hammer_priest_template.es_ / .two_handed_cog_hammers_template_1
        -- .es_) after picker tuning confirmed on Kruber. Coghammer's picks are all
        -- pass-through identity (already animated correctly on Kruber).
        -- wh_2h_hammer (#180) + dr_2h_cog_hammer (#182) went through _NEEDS_ANIMS,
        -- were re-tuned via picker, and are BAKED + CONFIRMED again below (v0.12.188).
        -- v0.12.156-dev: 7 more ports BAKED career-scoped into _3p_template_remaps
        -- (weapon_tweaker.lua) from the user's persisted dev-picker picks
        -- (user_settings.config 2026-06-25) — the last Kruber [Needs Animations] ports.
        we_1h_axe = true,                  -- -> Kruber native 1H Axe
        we_2h_axe = true,                  -- -> Empire Greathammer (grip offset already set v0.12.152)
        we_dual_wield_daggers = true,      -- -> Empire Mace & Sword
        we_dual_wield_sword_dagger = true, -- -> Empire Mace & Sword
        we_dual_wield_swords = true,       -- -> Empire Mace & Sword
        wh_dual_hammer = true,             -- -> Empire Mace & Sword
        wh_flail_shield = true,            -- -> Empire Mace & Shield
        -- v0.12.188-dev: 10 more ports BAKED career-scoped (es_) into
        -- _3p_template_remaps (weapon_tweaker.lua) from the user's persisted
        -- dev-picker picks — the 7 Sienna staves + Deus, plus the re-tuned
        -- Coghammer (#182) and Saltzpyre Greathammer (#180) and the Rapier (#178).
        -- Moved out of _NEEDS_ANIMS.kruber → tag now [Working].
        bw_skullstaff_beam = true,         -- -> Empire Greathammer
        bw_skullstaff_fireball = true,     -- -> Empire Greathammer
        bw_skullstaff_flamethrower = true, -- -> Empire Greathammer
        bw_skullstaff_geiser = true,       -- -> Empire Greathammer
        bw_skullstaff_spear = true,        -- -> Empire Greathammer
        bw_necromancy_staff = true,        -- -> Empire Greathammer
        bw_deus_01 = true,                 -- -> Empire Greathammer
        dr_2h_cog_hammer = true,           -- -> Empire Greathammer (re-tuned, #182)
        wh_2h_hammer = true,               -- -> Empire Greathammer (re-tuned, #180)
        wh_fencing_sword = true,           -- -> Empire 1H Sword (Rapier, #178)
        -- v0.12.201-dev: Skullsplitter & Tome BAKED es_ (one_handed_hammer_book_priest
        -- _template) from the tester's picks — the tester tuned it as a full anim remap
        -- (1H Skullsplitter vocab), not the mesh-swap the #181 note anticipated.
        wh_hammer_book = true,             -- -> 1H Mace/Skullsplitter (#181)
    },
    bardin = {
        bw_1h_crowbill = true, es_1h_sword = true, we_1h_sword = true,
        wh_1h_falchion = true,
        -- #110: Empire Handgun shares Bardin's native handgun template/vocab.
        -- Coverage classifies this as native fall-through; catalog it explicitly
        -- because the es_ item prefix is not receiver-native.
        es_handgun = true,
    },
    kerillian = {
        bw_1h_crowbill = true, dr_2h_axe = true, es_1h_flail = true,
        es_2h_heavy_spear = true, es_2h_sword = true, es_deus_01 = true,
        es_halberd = true, wh_1h_axe = true, wh_1h_falchion = true,
        wh_2h_billhook = true, wh_2h_sword = true,
        -- v0.12.201-dev: Kerillian batch-1 (33 ports) BAKED career-scoped (we_) into
        -- _3p_template_remaps (weapon_tweaker.lua) from the tester's persisted dev-picker
        -- picks (user_settings(4).config 2026-07-03) — every batch-1 port was fully tuned.
        -- Moved out of _NEEDS_ANIMS.kerillian (now emptied) -> tag flips to [Working].
        es_2h_hammer = true, wh_2h_hammer = true, dr_2h_cog_hammer = true,
        dr_2h_pick = true, bw_ghost_scythe = true, bw_skullstaff_beam = true,
        bw_skullstaff_fireball = true, bw_skullstaff_flamethrower = true,
        bw_skullstaff_geiser = true, bw_skullstaff_spear = true,
        bw_necromancy_staff = true, bw_deus_01 = true, es_2h_sword_executioner = true,
        es_bastard_sword = true, wh_fencing_sword = true, bw_1h_flail_flaming = true,
        bw_dagger = true, bw_flame_sword = true, wh_1h_hammer = true, dr_1h_hammer = true,
        es_mace_shield = true, es_sword_shield = true, es_sword_shield_breton = true,
        wh_flail_shield = true, wh_hammer_book = true, wh_hammer_shield = true,
        dr_shield_axe = true, wh_dual_hammer = true, dr_dual_wield_axes = true,
        dr_dual_wield_hammers = true, es_dual_wield_hammer_sword = true,
        wh_dual_wield_axe_falchion = true, dr_1h_throwing_axes = true,
    },
    saltzpyre = {
        bw_1h_crowbill = true, dr_2h_axe = true, es_1h_flail = true,
        es_1h_mace = true, es_1h_sword = true, es_2h_heavy_spear = true,
        es_longbow = true,
        we_1h_sword = true, we_2h_sword = true, we_crossbow_repeater = true,
        we_1h_axe = true, we_longbow = true,
        -- wh_flail (Saltzpyre's regular Flail) is NATIVE on Saltzpyre's careers
        -- (es_1h_flail confirmed; native flail handled by prefix rule too).
        -- v0.12.188-dev: all 17 Saltzpyre batch-1/2/3 ports BAKED career-scoped
        -- (wh_) into _3p_template_remaps (weapon_tweaker.lua) from the user's
        -- persisted dev-picker picks — moved out of _NEEDS_ANIMS.saltzpyre (now
        -- empty) → tag flips to [Working]. es_halberd + we_spear (the batch-3 #161
        -- polearm regression) are among them, re-tuned and baked as Billhook.
        we_2h_axe = true,                  -- -> WP Greathammer
        es_dual_wield_hammer_sword = true, -- -> Dual Axe & Falchion
        we_dual_wield_daggers = true,      -- -> Dual Axe & Falchion
        we_dual_wield_swords = true,       -- -> Dual Axe & Falchion
        we_dual_wield_sword_dagger = true, -- -> Dual Axe & Falchion
        bw_dagger = true,                  -- -> 1H Falchion
        bw_flame_sword = true,             -- -> 1H Falchion
        -- #576: we_spear reopened after live H1 charge/release failures.
        es_halberd = true,                 -- -> Billhook (#161)
        bw_skullstaff_beam = true,         -- -> WP Greathammer
        bw_skullstaff_fireball = true,     -- -> WP Greathammer
        bw_skullstaff_flamethrower = true, -- -> WP Greathammer
        bw_skullstaff_geiser = true,       -- -> WP Greathammer
        bw_skullstaff_spear = true,        -- -> WP Greathammer
        bw_necromancy_staff = true,        -- -> WP Greathammer
        bw_deus_01 = true,                 -- -> WP Greathammer
        -- v0.12.201-dev: Kruber Executioner Sword (#160) BAKED wh_ (two_handed_swords
        -- _executioner_template_1 -> Saltzpyre 2H Sword) from the tester's picks.
        es_2h_sword_executioner = true,    -- -> Saltzpyre 2H Sword
        -- v0.12.213-dev (#519): Saltzpyre batch-2 — 10 of the 11 queued ports BAKED
        -- career-scoped (wh_) into _3p_template_remaps (_wt_anim_remap.lua) from the
        -- tester's persisted dev-picker picks (both persistence namespaces parsed).
        -- dr_dual_wield_hammers had zero non-unset picks — stays in _NEEDS_ANIMS.
        es_2h_hammer           = true,     -- -> WP Greathammer
        dr_2h_cog_hammer       = true,     -- -> WP Greathammer
        dr_2h_pick             = true,     -- -> WP Greathammer
        bw_1h_mace             = true,     -- -> WP Greathammer
        -- #576: bw_ghost_scythe reopened after live charge/light failures.
        es_bastard_sword       = true,     -- -> Saltzpyre 2H Sword
        es_mace_shield         = true,     -- -> Dual Axe & Falchion
        es_sword_shield        = true,     -- -> Dual Axe & Falchion
        es_sword_shield_breton = true,     -- -> Dual Axe & Falchion
        dr_shield_axe          = true,     -- -> Dual Axe & Falchion
    },
    -- wh_priest: all 7 entries ✅/🔁 (ANIMATION_COVERAGE.md:181-185). The only
    -- cross-prefix entry es_1h_flail is ✅; everything else is native wh_*.
    wh_priest = { es_1h_flail = true },
    -- sienna: zero cross-character ports — all native (prefix rule covers it).
    sienna = {},
}

-- char_key -> { weapon_key = true } : decided set, 3P GRIP OFFSET still needed.
-- bw_ghost_scythe BAKED v0.12.150-dev: its +0.569 Z 3P grip offset (es_-scoped)
-- now lives in _weapon_grip_offsets.bw_ghost_scythe.es_ (weapon_tweaker.lua), so
-- the offset is applied, not pending — removed from _NEEDS_OFFSETS so M.state
-- returns working. (The anim port is also baked into _3p_template_remaps
-- .staff_scythe.es_, and the key is moved to _CONFIRMED below.)
-- we_2h_axe (Elven 2H Axe/Glaive) GRIP OFFSET SET v0.12.152-dev: DURABLE +0.285 Z
-- es_-scoped grip offset (_weapon_grip_offsets.we_2h_axe.es_ = {0,0,0.285} +
-- _DURABLE_GRIP_OFFSETS.we_2h_axe = true). v0.12.156-dev: the anim IS now BAKED
-- too (career-scoped _3p_template_remaps.two_handed_axes_template_2.es_ ->
-- Greathammer), so the Glaive moved to _CONFIRMED above and
-- was removed from _NEEDS_ANIMS / the picker below.
local _NEEDS_OFFSETS = {
    kruber = {},
}

-- char_key -> { weapon_key = true } : no decision captured yet.
local _UNTESTED = {
    kruber = { we_javelin = true, we_life_staff = true },
    -- #111: present in every Kerillian unlock list but absent from the coverage
    -- decision ledger. Do not let the generic fallback imply a target exists.
    kerillian = { es_1h_mace = true, es_longbow = true },
}

-- ===========================================================================
-- EXPLICIT needs_animations allow-list (v0.12.142-dev) — picker membership.
-- ===========================================================================
-- char_key -> { weapon_key = "<redirect-target display>" }. ONLY weapons in
-- this table are surfaced in the 3P picker (item 4: "picker lists ONLY weapons
-- explicitly marked as needing animations). The VALUE is the redirect-target
-- display name used by internal diagnostics. Sourced from the `SET=` annotations
-- in ANIMATION_COVERAGE.md "## Receiver: KRUBER" (lines 61-85) + the
-- KRUBER_3P_ANIM_DECISIONS.md "Set chosen" column. The code does NOT parse the
-- .md at runtime — this is the generated mirror (same doctrine as _CONFIRMED).
--
-- Membership here is INTENTIONALLY a closed list, NOT a default: untested ports
-- (Beam Staff bw_skullstaff_beam, Javelin, Deepwood Staff) are absent, so they
-- never leak into the picker, and M.state's default-return remains
-- needs_animations, so no ~100-port behavior shift in audit classification.
local _NEEDS_ANIMS = {
    -- v0.12.188-dev: the v0.12.157 Kruber staves/Coghammer/Greathammer/Rapier batch
    -- (10 ports) was BAKED career-scoped (es_) into _3p_template_remaps
    -- (weapon_tweaker.lua) from the user's persisted dev-picker picks and moved to
    -- _CONFIRMED above. Only wh_hammer_book remains pending (no picks
    -- captured yet — its 3P is a mesh-swap, not an anim remap; #181).
    kruber = {
        -- v0.12.201-dev: wh_hammer_book BAKED (es_) -> _CONFIRMED.kruber. Emptied.
        -- Next Kruber batch (if any) is queued here.
    },
    -- v0.12.188-dev: all 17 Saltzpyre batch-1/2/3 ports BAKED career-scoped (wh_)
    -- into _3p_template_remaps from the user's persisted dev-picker picks and moved
    -- to _CONFIRMED above — this gate was emptied.
    -- v0.12.194-dev (#160): re-surfaced the Kruber Executioner Sword for Saltzpyre
    -- per-attack tuning. VALUE = the picker SET label; kept in lockstep with
    -- _SALTZ_WEAPON_SET (wt_dev_anim_picker.lua).
    -- v0.12.201-dev: Saltzpyre batch-2 — 11 cross-character 3P ports queued for the
    -- tester's dev-picker tuning (es_2h_sword_executioner from batch-1 was BAKED (wh_)
    -- -> _CONFIRMED.saltzpyre). VALUE = the picker SET display label (_SALTZ_SET_LABEL);
    -- kept in lockstep with _SALTZ_WEAPON_SET (wt_dev_anim_picker.lua). Every wield-render
    -- target has a wh_* redirect in _WIELD_ANIM_CAREER_3P_PATCHES_BULK (wt_wield_patches).
    -- v0.12.213-dev (#519): Saltzpyre batch-2 — 10 of the 11 ports were fully tuned
    -- by the tester and BAKED career-scoped (wh_) into _3p_template_remaps
    -- (_wt_anim_remap.lua) -> moved to _CONFIRMED above. The former
    -- dr_dual_wield_hammers row is no longer offered on Saltzpyre and was removed
    -- from this table under #112. Only the two #576 reopened ports remain live.
    saltzpyre = {
        -- #576: static mappings are candidates, not visual confirmation.
        bw_ghost_scythe       = "Warrior Priest Greathammer",
        we_spear              = "Saltzpyre Billhook",
        -- #112: dr_dual_wield_hammers is no longer present in any non-WP
        -- Saltzpyre unlock list and has no picker row. Do not retain an
        -- unreachable status entry that falsely implies it can be tuned here.
    },
    -- v0.12.193-dev: Kerillian batch 1 — the "next group" of cross-character 3P ports
    -- surfaced for dev-picker tuning (mirrors the Saltzpyre batch-1 setup). Every
    -- non-`we_` port that appears in a `we_*` unlock list, is not already
    -- _CONFIRMED.kerillian, and has a `we_*` wield-redirect target in wt_wield_patches.
    -- VALUE = the Kerillian-native wield-redirect the port's 3P borrows (the picker SET
    -- label). Kept in lockstep with _KERI_WEAPON_SET (wt_dev_anim_picker.lua).
    kerillian = {
        -- v0.12.201-dev: Kerillian batch-1 (all 33 ports) BAKED (we_) -> _CONFIRMED.kerillian
        -- from the tester's fully-tuned picks. Emptied. Next Kerillian batch (if any) queued here.
    },
}

-- Issue #109: source-backed wield targets for Kruber ports which have not yet
-- been promoted into the picker.  This is diagnostic metadata, not an animation
-- bake: it makes the already-wired/decided SET visible without claiming the
-- per-attack vocabulary works.  Unknown rows deliberately remain absent.
local _DIAGNOSTIC_TARGET = {
    kruber = {
        dr_1h_throwing_axes = "Empire 1H Mace",
        dr_drake_pistol = "Repeater Handgun",
        dr_drakegun = "Empire Blunderbuss",
        dr_steam_pistol = "Repeater Handgun",
        dr_deus_01 = "Empire Blunderbuss",
        we_deus_01 = "Empire Longbow",
        we_shortbow = "Empire Longbow",
        we_shortbow_hagbane = "Empire Longbow",
        we_crossbow_repeater = "Repeater Handgun",
        wh_crossbow_repeater = "Repeater Handgun",
        wh_deus_01 = "Repeater Handgun",
    },
    kerillian = {
        -- #111: coverage-ledger decisions for the remaining unbaked ranged
        -- surface. These labels describe the chosen receiver vocabulary only;
        -- they do not promote the port to working or picker-ready.
        dr_crossbow = "Elf Repeater Crossbow",
        dr_deus_01 = "Elf Repeater Crossbow",
        dr_drake_pistol = "Elf Repeater Crossbow",
        dr_drakegun = "Elf Repeater Crossbow",
        dr_rakegun = "Elf Repeater Crossbow",
        dr_steam_pistol = "Elf Repeater Crossbow",
        es_blunderbuss = "Elf Repeater Crossbow",
        es_handgun = "Elf Repeater Crossbow",
        es_repeating_handgun = "Elf Repeater Crossbow",
        wh_brace_of_pistols = "Elf Repeater Crossbow",
        wh_crossbow = "Elf Repeater Crossbow",
        wh_crossbow_repeater = "Elf Repeater Crossbow",
        wh_deus_01 = "Elf Repeater Crossbow",
        wh_repeating_pistols = "Elf Repeater Crossbow",
    },
    saltzpyre = {
        -- #112: source/coverage-backed receiver targets for live ports which
        -- remain unbaked or visually unverified. These are diagnostic labels,
        -- not promotions to working and not implicit picker membership.
        dr_1h_throwing_axes = "Saltzpyre 1H Axe",
        dr_deus_01 = "Saltzpyre Crossbow",
        dr_drake_pistol = "Brace of Pistols",
        dr_drakegun = "Volley Crossbow",
        dr_rakegun = "Volley Crossbow",
        dr_steam_pistol = "Repeater Pistol",
        es_blunderbuss = "Saltzpyre Crossbow",
        es_deus_01 = "Dual Axe & Falchion",
        es_handgun = "Saltzpyre Crossbow",
        es_repeating_handgun = "Repeater Pistol",
        we_1h_spears_shield = "Dual Axe & Falchion",
        we_deus_01 = "Saltzpyre Crossbow",
        we_javelin = "Saltzpyre 1H Axe",
    },
}

-- Issue #108: display-only mirror of confirmed, career-scoped 3P redirects.
-- `_CONFIRMED` deliberately remains a boolean status set; keeping presentation
-- names separate prevents a wording edit from changing availability status.
-- Pending ports still source their target from `_NEEDS_ANIMS` below.
local _REDIRECT_DISPLAY = {
    kruber = {
        dr_2h_pick = "Empire Greathammer",
        dr_2h_cog_hammer = "Empire Greathammer",
        wh_2h_hammer = "Empire Greathammer",
        we_2h_axe = "Empire Greathammer",
        bw_1h_mace = "Empire Greathammer",
        bw_ghost_scythe = "Empire Greathammer",
        bw_skullstaff_beam = "Empire Greathammer",
        bw_skullstaff_fireball = "Empire Greathammer",
        bw_skullstaff_flamethrower = "Empire Greathammer",
        bw_skullstaff_geiser = "Empire Greathammer",
        bw_skullstaff_spear = "Empire Greathammer",
        bw_necromancy_staff = "Empire Greathammer",
        bw_deus_01 = "Empire Greathammer",
        we_dual_wield_daggers = "Empire Mace & Sword",
        we_dual_wield_swords = "Empire Mace & Sword",
        we_dual_wield_sword_dagger = "Empire Mace & Sword",
        wh_dual_hammer = "Empire Mace & Sword",
        wh_flail_shield = "Empire Mace & Shield",
        bw_dagger = "Empire 1H Sword",
        bw_flame_sword = "Empire 1H Sword",
        wh_fencing_sword = "Empire 1H Sword",
        we_1h_axe = "Witch Hunter 1H Axe",
        wh_hammer_book = "1H Mace/Skullsplitter",
    },
    bardin = {
        -- #110: event-level dr_-scoped remaps, not whole-weapon substitutions.
        we_1h_sword = "Bardin 1H event map",
        es_1h_sword = "Bardin 1H event map",
        wh_1h_falchion = "Bardin 1H event map",
        bw_1h_crowbill = "Bardin 1H event map",
    },
    wh_priest = {
        -- #113: the Empire Flail keeps its own wield vocabulary on the Priest
        -- body, with the shipped per-unit push/heavy correction. This is an
        -- event-map label, not a claim that another whole weapon is substituted.
        es_1h_flail = "Warrior Priest flail event map",
    },
    saltzpyre = {
        we_1h_axe = "Saltzpyre 1H Axe",
        we_2h_axe = "Warrior Priest Greathammer",
        es_2h_hammer = "Warrior Priest Greathammer",
        dr_2h_cog_hammer = "Warrior Priest Greathammer",
        dr_2h_pick = "Warrior Priest Greathammer",
        bw_1h_mace = "Warrior Priest Greathammer",
        bw_skullstaff_beam = "Warrior Priest Greathammer",
        bw_skullstaff_fireball = "Warrior Priest Greathammer",
        bw_skullstaff_flamethrower = "Warrior Priest Greathammer",
        bw_skullstaff_geiser = "Warrior Priest Greathammer",
        bw_skullstaff_spear = "Warrior Priest Greathammer",
        bw_necromancy_staff = "Warrior Priest Greathammer",
        bw_deus_01 = "Warrior Priest Greathammer",
        es_dual_wield_hammer_sword = "Dual Axe & Falchion",
        we_dual_wield_daggers = "Dual Axe & Falchion",
        we_dual_wield_swords = "Dual Axe & Falchion",
        we_dual_wield_sword_dagger = "Dual Axe & Falchion",
        es_mace_shield = "Dual Axe & Falchion",
        es_sword_shield = "Dual Axe & Falchion",
        es_sword_shield_breton = "Dual Axe & Falchion",
        dr_shield_axe = "Dual Axe & Falchion",
        bw_dagger = "1H Falchion",
        bw_flame_sword = "1H Falchion",
        es_halberd = "Billhook",
        es_2h_sword_executioner = "Saltzpyre 2H Sword",
        es_bastard_sword = "Saltzpyre 2H Sword",
    },
    kerillian = {
        es_2h_hammer = "Elf 2H Axe/Glaive",
        wh_2h_hammer = "Elf 2H Axe/Glaive",
        dr_2h_cog_hammer = "Elf 2H Axe/Glaive",
        dr_2h_pick = "Elf 2H Axe/Glaive",
        bw_ghost_scythe = "Elf 2H Axe/Glaive",
        bw_skullstaff_beam = "Elf 2H Axe/Glaive",
        bw_skullstaff_fireball = "Elf 2H Axe/Glaive",
        bw_skullstaff_flamethrower = "Elf 2H Axe/Glaive",
        bw_skullstaff_geiser = "Elf 2H Axe/Glaive",
        bw_skullstaff_spear = "Elf 2H Axe/Glaive",
        bw_necromancy_staff = "Elf 2H Axe/Glaive",
        bw_deus_01 = "Elf 2H Axe/Glaive",
        es_2h_sword_executioner = "Elf 2H Sword",
        es_bastard_sword = "Elf 2H Sword",
        wh_fencing_sword = "Elf 1H Sword",
        bw_1h_flail_flaming = "Elf 1H Sword",
        bw_dagger = "Elf 1H Sword",
        bw_flame_sword = "Elf 1H Sword",
        wh_1h_hammer = "Elf 1H Axe",
        dr_1h_hammer = "Elf 1H Axe",
        es_mace_shield = "Elf Spear & Shield",
        es_sword_shield = "Elf Spear & Shield",
        es_sword_shield_breton = "Elf Spear & Shield",
        wh_flail_shield = "Elf Spear & Shield",
        wh_hammer_book = "Elf Spear & Shield",
        wh_hammer_shield = "Elf Spear & Shield",
        dr_shield_axe = "Elf Spear & Shield",
        wh_dual_hammer = "Dual Swords",
        dr_dual_wield_axes = "Dual Swords",
        dr_dual_wield_hammers = "Dual Swords",
        es_dual_wield_hammer_sword = "Sword & Dagger",
        wh_dual_wield_axe_falchion = "Sword & Dagger",
        dr_1h_throwing_axes = "Elf Javelin",
    },
}

-- Issue #108: shipped 3P mesh substitutions. These are visual lies applied to
-- the receiver's third-person/preview model; first-person weapon models remain
-- the real equipped item. Keep this mirror aligned with the model dispatchers.
local _MODEL_SUB = {
    kruber = {
        wh_brace_of_pistols = "Repeater Handgun",
        wh_repeating_pistols = "Repeater Handgun",
    },
    saltzpyre = {
        es_longbow = "Crossbow",
        we_longbow = "Crossbow",
        we_deus_01 = "Crossbow",
    },
}

-- Native owner character of a weapon_key, by 3-char prefix. wh_* family is owned
-- by Saltzpyre AND natively wieldable by Warrior Priest (shared skeleton family),
-- so a wh_* weapon on a wh_priest career counts as native.
local _OWNER_BY_PREFIX = {
    es_ = "kruber", dr_ = "bardin", we_ = "kerillian",
    wh_ = "saltzpyre", bw_ = "sienna",
}

-- Receiver character bucket from a career name (wh_priest is its own bucket).
local _BUCKET_BY_PREFIX = {
    es_ = "kruber", dr_ = "bardin", we_ = "kerillian",
    wh_ = "saltzpyre", bw_ = "sienna",
}

local function _char_key_for_career(career)
    if not career then return nil end
    if career == "wh_priest" then return "wh_priest" end
    return _BUCKET_BY_PREFIX[career:sub(1, 3)]
end

local function _is_native(career, weapon_key)
    if not career or not weapon_key then return false end
    local owner = _OWNER_BY_PREFIX[weapon_key:sub(1, 3)]
    if not owner then return false end
    local recv = _char_key_for_career(career)
    if owner == recv then return true end
    -- Warrior Priest natively wields the wh_* family (shares Saltzpyre's prefix).
    if recv == "wh_priest" and owner == "saltzpyre" then return true end
    return false
end

-- Public: internal state for a (career, weapon_key) pair. NEVER returns nil.
function M.state(career, weapon_key)
    if _is_native(career, weapon_key) then return "working" end
    local recv = _char_key_for_career(career)
    if not recv then return "untested" end
    if _CONFIRMED[recv] and _CONFIRMED[recv][weapon_key] then return "working" end
    if _NEEDS_OFFSETS[recv] and _NEEDS_OFFSETS[recv][weapon_key] then return "needs_offsets" end
    if _UNTESTED[recv] and _UNTESTED[recv][weapon_key] then return "untested" end
    -- Default for a surviving cross-character port: a set is decided (the unlock
    -- map only carries ports with a chosen 3P target) but per-attack picks pend.
    return "needs_animations"
end

-- Public: redirect-target display name for a
-- (career, weapon_key) pair, e.g. "Greathammer", or nil when none is on file.
-- Pending ports source `_NEEDS_ANIMS`; confirmed/baked ports source the #108
-- display mirror so completing a port no longer discards its redirect label.
function M.redirect_target(career, weapon_key)
    local recv = _char_key_for_career(career)
    local pending = recv and _NEEDS_ANIMS[recv]
    local confirmed = recv and _REDIRECT_DISPLAY[recv]
    local diagnostic = recv and _DIAGNOSTIC_TARGET[recv]
    local target = (pending and pending[weapon_key])
        or (confirmed and confirmed[weapon_key])
        or (diagnostic and diagnostic[weapon_key])
    return target
end

-- Public (#108): raw display name of a shipped 3P model substitute.
function M.model_substitute(career, weapon_key)
    local recv = _char_key_for_career(career)
    local row = recv and _MODEL_SUB[recv]
    return row and row[weapon_key] or nil
end

-- Public (v0.12.142-dev): is (career, weapon_key) explicitly flagged as needing
-- animations? The 3P picker gates membership on this (item 4) so it
-- lists ONLY weapons the user has flagged in _NEEDS_ANIMS — not every
-- non-confirmed port (which is how untested weapons like Beam Staff used to
-- leak in via M.state's default-return). NOTE: native ports + _NEEDS_OFFSETS
-- ports can also appear in _NEEDS_ANIMS (bw_ghost_scythe is both); this returns
-- the RAW membership, so the picker still wants its own native/offsets filter.
function M.needs_anims(career, weapon_key)
    local recv = _char_key_for_career(career)
    local row = recv and _NEEDS_ANIMS[recv]
    return (row and row[weapon_key]) ~= nil
end

-- Public (#109): bounded, pure inventory audit used by the automatic log probe,
-- `/wt_audit_kruber_3p`, and offline regression coverage.  It never mutates the
-- supplied unlock list.  Duplicate keys are ignored so counts describe distinct
-- cross-character ports rather than career-list implementation details.
function M.audit_cross_character(career, weapon_keys)
    local rows, seen = {}, {}
    local counts = {
        total = 0,
        working = 0,
        needs_animations = 0,
        needs_offsets = 0,
        untested = 0,
        picker_visible = 0,
        hidden_needs_animations = 0,
    }

    for _, weapon_key in ipairs(type(weapon_keys) == "table" and weapon_keys or {}) do
        if type(weapon_key) == "string"
                and not seen[weapon_key]
                and not _is_native(career, weapon_key) then
            seen[weapon_key] = true
            local state = M.state(career, weapon_key)
            local picker_visible = M.needs_anims(career, weapon_key)
            local row = {
                weapon_key = weapon_key,
                state = state,
                redirect = M.redirect_target(career, weapon_key),
                model_substitute = M.model_substitute(career, weapon_key),
                picker_visible = picker_visible,
            }
            rows[#rows + 1] = row
            counts.total = counts.total + 1
            counts[state] = (counts[state] or 0) + 1
            if picker_visible then counts.picker_visible = counts.picker_visible + 1 end
            if state == "needs_animations" and not picker_visible then
                counts.hidden_needs_animations = counts.hidden_needs_animations + 1
            end
        end
    end

    table.sort(rows, function(a, b) return a.weapon_key < b.weapon_key end)
    return rows, counts
end

-- Public: split a `unlock_<career>_<weapon_key>` setting_id into (career, weapon_key).
-- Careers and weapon keys both use the 2-char prefix + underscores convention, so
-- we match against the known career list (passed in) to find the split point.
-- Returns nil, nil if it isn't an unlock_* id or the career isn't recognized.
function M.parse_unlock_id(setting_id, careers_set)
    if type(setting_id) ~= "string" then return nil, nil end
    local rest = setting_id:match("^unlock_(.+)$")
    if not rest then return nil, nil end
    -- Greedily try the longest career prefix that is a known career.
    for career in pairs(careers_set) do
        local wk = rest:match("^" .. career .. "_(.+)$")
        if wk then return career, wk end
    end
    return nil, nil
end

return M
