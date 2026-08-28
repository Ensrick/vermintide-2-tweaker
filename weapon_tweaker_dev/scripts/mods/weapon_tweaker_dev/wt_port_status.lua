--[[
============================================================================
 wt_port_status.lua — shared (career, weapon_key) -> internal 3P routing state
============================================================================

Single source of truth for internal 3P picker/routing metadata. Player-facing
Weapon Availability labels deliberately do not expose this engineering state.
Issue #948 resets every compatibility cell to U. A native prefix, donor alias,
baked event table, or historical confirmation is routing evidence only; none of
those facts can represent current live verification.

3P-ONLY. State describes the THIRD-person animation port only — 1P is
universal across all six characters and never needs cross-character work
(feedback_1p_animations_universal).

INTERNAL ROUTING VOCABULARY (aligned to
KRUBER_3P_ANIM_DECISIONS.md:14-20 + the picker):
  native           — receiver-native prefix/vocabulary lead.
  wired            — a historical/baked receiver route exists.
  needs_animations — a wield SET redirect candidate is recorded, but current
                     per-attack behavior is not verified.
  needs_offsets    — set chosen, 3P grip offset still needed.
  unknown          — no routing decision captured yet.

PROVENANCE of the wired/unknown/offset sets below: generated 2026-06-23
from a parse of historical ANIMATION_COVERAGE.md classifications merged
with historical KRUBER_3P_ANIM_DECISIONS.md routing rows and the picker's old
coverage mirrors. The code does NOT parse the .md at runtime (mod sandbox can't
reliably io.open repo files). These tables may choose or display a route, but
they never promote a #948 compatibility cell out of U.

RECEIVER BUCKETS mirror the .md sections. Saltzpyre = the three non-WP careers
(wh_captain/wh_bountyhunter/wh_zealot); wh_priest is its own bucket. Sienna's
base rows are prefix-native routing leads, not current verification.
============================================================================
--]]

local M = {}
local function _load_documented_keys()
    if get_mod then
        return get_mod("wt_dev"):dofile(
            "scripts/mods/weapon_tweaker_dev/wt_documented_keys")
    end
    return dofile("weapon_tweaker/scripts/mods/weapon_tweaker/wt_documented_keys.lua")
end
local W = _load_documented_keys()

-- char_key -> { weapon_key = true } : historical/baked routing on that receiver.
-- This table is not current verification evidence.
local _WIRED = {
    kruber = {
        -- user-confirmed in-game 2026-06-28: Falchion (#176) + Crowbill (#177) on Kruber.
        [W.SALTZPYRE_FALCHION] = true,      -- Saltzpyre "Falchion" rendered on Kruber
        [W.SIENNA_CROWBILL] = true,      -- Sienna "Crowbill" rendered on Kruber (was held, now confirmed)
        [W.SIENNA_FLAMING_FLAIL] = true, [W.BARDIN_GREAT_AXE] = true, [W.BARDIN_AXE_AND_SHIELD] = true,
        [W.KERILLIAN_SPEAR_AND_SHIELD] = true, [W.KERILLIAN_SWORD] = true, [W.KERILLIAN_GREATSWORD] = true,
        [W.KERILLIAN_LONGBOW] = true, [W.KERILLIAN_SPEAR] = true, [W.SALTZPYRE_AXE] = true,
        [W.SALTZPYRE_BILLHOOK] = true, [W.SALTZPYRE_BRACE_OF_PISTOLS] = true, [W.SALTZPYRE_REPEATING_PISTOL] = true,
        -- KRUBER_3P_ANIM_DECISIONS.md CONFIRMED extras (Saltzpyre's regular Flail
        -- renders as Empire Flail on Kruber = native es_1h_flail; Sienna's Flail
        -- redirect bw_1h_flail_flaming above; Crowbill held 🧊 — NOT confirmed).
        -- v0.12.149-dev: 4 ports BAKED career-scoped into _3p_template_remaps
        -- (weapon_tweaker.lua) after picker tuning was confirmed on Kruber —
        -- moved out of _NEEDS_ANIMS into the historical wired set. Per-attack
        -- picks live in the bake, not the picker.
        [W.BARDIN_WAR_PICK] = true,          -- -> Empire Greathammer
        [W.SIENNA_DAGGER] = true,           -- -> Empire 1H Sword
        [W.SIENNA_FLAME_SWORD] = true,      -- -> Empire 1H Sword
        -- v0.12.150-dev: 2 more ports BAKED career-scoped into _3p_template_remaps
        -- (weapon_tweaker.lua .one_handed_hammer_wizard_template_1.es_ /
        -- .staff_scythe.es_) after picker tuning confirmed on Kruber. The Scythe
        -- ALSO bakes a +0.569 Z es_-scoped 3P grip offset (_weapon_grip_offsets).
        [W.SIENNA_MACE] = true,          -- -> Empire Greathammer
        [W.SIENNA_ENSORCELLED_REAPER] = true,     -- -> Empire Greathammer (+ 3P grip offset)
        -- v0.12.151-dev: 2 more ports BAKED career-scoped into _3p_template_remaps
        -- (.two_handed_hammer_priest_template.es_ / .two_handed_cog_hammers_template_1
        -- .es_) after picker tuning confirmed on Kruber. Coghammer's picks are all
        -- pass-through identity (already animated correctly on Kruber).
        -- wh_2h_hammer (#180) + dr_2h_cog_hammer (#182) went through _NEEDS_ANIMS,
        -- were re-tuned via picker, and are BAKED + CONFIRMED again below (v0.12.188).
        -- v0.12.156-dev: 7 more ports BAKED career-scoped into _3p_template_remaps
        -- (weapon_tweaker.lua) from the user's persisted dev-picker picks
        -- (user_settings.config 2026-06-25) — the last Kruber [Needs Animations] ports.
        [W.KERILLIAN_ELVEN_AXE] = true,                  -- -> Kruber native 1H Axe
        [W.KERILLIAN_GLAIVE] = true,                  -- -> Empire Greathammer (grip offset already set v0.12.152)
        [W.KERILLIAN_DUAL_DAGGERS] = true,      -- -> Empire Mace & Sword
        [W.KERILLIAN_SWORD_AND_DAGGER] = true, -- -> Empire Mace & Sword
        [W.KERILLIAN_DUAL_SWORDS] = true,       -- -> Empire Mace & Sword
        [W.SALTZPYRE_DUAL_SKULL_SPLITTERS] = true,             -- -> Empire Mace & Sword
        [W.SALTZPYRE_FLAIL_AND_SHIELD] = true,            -- -> Empire Mace & Shield
        -- v0.12.188-dev: 10 more ports BAKED career-scoped (es_) into
        -- _3p_template_remaps (weapon_tweaker.lua) from the user's persisted
        -- dev-picker picks — the 7 Sienna staves + Deus, plus the re-tuned
        -- Coghammer (#182) and Saltzpyre Greathammer (#180) and the Rapier (#178).
        -- Moved out of _NEEDS_ANIMS.kruber into the historical wired set.
        [W.SIENNA_BEAM_STAFF] = true,         -- -> Empire Greathammer
        [W.SIENNA_FIREBALL_STAFF] = true,     -- -> Empire Greathammer
        [W.SIENNA_FLAMESTORM_STAFF] = true, -- -> Empire Greathammer
        [W.SIENNA_CONFLAGRATION_STAFF] = true,       -- -> Empire Greathammer
        [W.SIENNA_BOLT_STAFF] = true,        -- -> Empire Greathammer
        [W.SIENNA_SOULSTEALER_STAFF] = true,        -- -> Empire Greathammer
        [W.SIENNA_CORUSCATION_STAFF] = true,                 -- -> Empire Greathammer
        [W.BARDIN_COG_HAMMER] = true,           -- -> Empire Greathammer (re-tuned, #182)
        [W.SALTZPYRE_HOLY_GREAT_HAMMER] = true,               -- -> Empire Greathammer (re-tuned, #180)
        [W.SALTZPYRE_RAPIER] = true,           -- -> Empire 1H Sword (Rapier, #178)
        -- v0.12.201-dev: Skullsplitter & Tome BAKED es_ (one_handed_hammer_book_priest
        -- _template) from the tester's picks — the tester tuned it as a full anim remap
        -- (1H Skullsplitter vocab), not the mesh-swap the #181 note anticipated.
        [W.SALTZPYRE_HAMMER_AND_TOME] = true,             -- -> 1H Mace/Skullsplitter (#181)
    },
    bardin = {
        [W.SIENNA_CROWBILL] = true, [W.KRUBER_SWORD] = true, [W.KERILLIAN_SWORD] = true,
        [W.SALTZPYRE_FALCHION] = true,
        -- #110: Empire Handgun shares Bardin's native handgun template/vocab.
        -- Coverage classifies this as native fall-through; catalog it explicitly
        -- because the es_ item prefix is not receiver-native.
        [W.KRUBER_HANDGUN] = true,
    },
    kerillian = {
        [W.SIENNA_CROWBILL] = true, [W.BARDIN_GREAT_AXE] = true, [W.SALTZPYRE_FLAIL] = true,
        [W.KRUBER_TUSKGOR_SPEAR] = true, [W.KRUBER_GREATSWORD] = true, [W.KRUBER_SPEAR_AND_SHIELD] = true,
        [W.KRUBER_HALBERD] = true, [W.SALTZPYRE_AXE] = true, [W.SALTZPYRE_FALCHION] = true,
        [W.SALTZPYRE_BILLHOOK] = true, [W.SALTZPYRE_2H_SWORD] = true,
        -- v0.12.201-dev: Kerillian batch-1 (33 ports) BAKED career-scoped (we_) into
        -- _3p_template_remaps (weapon_tweaker.lua) from the tester's persisted dev-picker
        -- picks (user_settings(4).config 2026-07-03) — every batch-1 port was fully tuned.
        -- Moved out of _NEEDS_ANIMS.kerillian into the historical wired set.
        [W.KRUBER_TWO_HANDED_HAMMER] = true, [W.SALTZPYRE_HOLY_GREAT_HAMMER] = true, [W.BARDIN_COG_HAMMER] = true,
        [W.BARDIN_WAR_PICK] = true, [W.SIENNA_ENSORCELLED_REAPER] = true, [W.SIENNA_BEAM_STAFF] = true,
        [W.SIENNA_FIREBALL_STAFF] = true, [W.SIENNA_FLAMESTORM_STAFF] = true,
        [W.SIENNA_CONFLAGRATION_STAFF] = true, [W.SIENNA_BOLT_STAFF] = true,
        [W.SIENNA_SOULSTEALER_STAFF] = true, [W.SIENNA_CORUSCATION_STAFF] = true, [W.KRUBER_EXECUTIONER_SWORD] = true,
        [W.KRUBER_BRETONNIAN_LONGSWORD] = true, [W.SALTZPYRE_RAPIER] = true, [W.SIENNA_FLAMING_FLAIL] = true,
        [W.SIENNA_DAGGER] = true, [W.SIENNA_FLAME_SWORD] = true, [W.SALTZPYRE_1H_HAMMER] = true, [W.BARDIN_HAMMER] = true,
        [W.KRUBER_MACE_AND_SHIELD] = true, [W.KRUBER_SWORD_AND_SHIELD] = true, [W.KRUBER_BRETONNIAN_SWORD_AND_SHIELD] = true,
        [W.SALTZPYRE_FLAIL_AND_SHIELD] = true, [W.SALTZPYRE_HAMMER_AND_TOME] = true, [W.SALTZPYRE_SKULL_SPLITTER_AND_SHIELD] = true,
        [W.BARDIN_AXE_AND_SHIELD] = true, [W.SALTZPYRE_DUAL_SKULL_SPLITTERS] = true, [W.BARDIN_DUAL_AXES] = true,
        [W.BARDIN_DUAL_HAMMERS] = true, [W.KRUBER_MACE_AND_SWORD] = true,
        [W.SALTZPYRE_AXE_AND_FALCHION] = true, [W.BARDIN_THROWING_AXES] = true,
    },
    saltzpyre = {
        [W.SIENNA_CROWBILL] = true, [W.BARDIN_GREAT_AXE] = true, [W.SALTZPYRE_FLAIL] = true,
        [W.KRUBER_MACE] = true, [W.KRUBER_SWORD] = true, [W.KRUBER_TUSKGOR_SPEAR] = true,
        [W.KRUBER_LONGBOW] = true,
        [W.KERILLIAN_SWORD] = true, [W.KERILLIAN_GREATSWORD] = true, [W.KERILLIAN_VOLLEY_CROSSBOW] = true,
        [W.KERILLIAN_ELVEN_AXE] = true, [W.KERILLIAN_LONGBOW] = true,
        -- wh_flail (Saltzpyre's regular Flail) is NATIVE on Saltzpyre's careers
        -- (es_1h_flail confirmed; native flail handled by prefix rule too).
        -- v0.12.188-dev: all 17 Saltzpyre batch-1/2/3 ports BAKED career-scoped
        -- (wh_) into _3p_template_remaps (weapon_tweaker.lua) from the user's
        -- persisted dev-picker picks — moved out of _NEEDS_ANIMS.saltzpyre (now
        -- empty) into the historical wired set. es_halberd + we_spear (the batch-3 #161
        -- polearm regression) are among them, re-tuned and baked as Billhook.
        [W.KERILLIAN_GLAIVE] = true,                  -- -> WP Greathammer
        [W.KRUBER_MACE_AND_SWORD] = true, -- -> Dual Axe & Falchion
        [W.KERILLIAN_DUAL_DAGGERS] = true,      -- -> Dual Axe & Falchion
        [W.KERILLIAN_DUAL_SWORDS] = true,       -- -> Dual Axe & Falchion
        [W.KERILLIAN_SWORD_AND_DAGGER] = true, -- -> Dual Axe & Falchion
        [W.SIENNA_DAGGER] = true,                  -- -> 1H Falchion
        [W.SIENNA_FLAME_SWORD] = true,             -- -> 1H Falchion
        -- #576: we_spear reopened after live H1 charge/release failures.
        [W.KRUBER_HALBERD] = true,                 -- -> Billhook (#161)
        [W.SIENNA_BEAM_STAFF] = true,         -- -> WP Greathammer
        [W.SIENNA_FIREBALL_STAFF] = true,     -- -> WP Greathammer
        [W.SIENNA_FLAMESTORM_STAFF] = true, -- -> WP Greathammer
        [W.SIENNA_CONFLAGRATION_STAFF] = true,       -- -> WP Greathammer
        [W.SIENNA_BOLT_STAFF] = true,        -- -> WP Greathammer
        [W.SIENNA_SOULSTEALER_STAFF] = true,        -- -> WP Greathammer
        [W.SIENNA_CORUSCATION_STAFF] = true,                 -- -> WP Greathammer
        -- v0.12.201-dev: Kruber Executioner Sword (#160) BAKED wh_ (two_handed_swords
        -- _executioner_template_1 -> Saltzpyre 2H Sword) from the tester's picks.
        [W.KRUBER_EXECUTIONER_SWORD] = true,    -- -> Saltzpyre 2H Sword
        -- v0.12.213-dev (#519): Saltzpyre batch-2 — 10 of the 11 queued ports BAKED
        -- career-scoped (wh_) into _3p_template_remaps (_wt_anim_remap.lua) from the
        -- tester's persisted dev-picker picks (both persistence namespaces parsed).
        -- dr_dual_wield_hammers had zero non-unset picks — stays in _NEEDS_ANIMS.
        [W.KRUBER_TWO_HANDED_HAMMER] = true,     -- -> WP Greathammer
        [W.BARDIN_COG_HAMMER] = true,     -- -> WP Greathammer
        [W.BARDIN_WAR_PICK] = true,     -- -> WP Greathammer
        [W.SIENNA_MACE] = true,     -- -> WP Greathammer
        -- #576: bw_ghost_scythe reopened after live charge/light failures.
        [W.KRUBER_BRETONNIAN_LONGSWORD] = true,     -- -> Saltzpyre 2H Sword
        [W.KRUBER_MACE_AND_SHIELD] = true,     -- -> Dual Axe & Falchion
        [W.KRUBER_SWORD_AND_SHIELD] = true,     -- -> Dual Axe & Falchion
        [W.KRUBER_BRETONNIAN_SWORD_AND_SHIELD] = true,     -- -> Dual Axe & Falchion
        [W.BARDIN_AXE_AND_SHIELD] = true,     -- -> Dual Axe & Falchion
    },
    -- wh_priest: all 7 entries ✅/🔁 (ANIMATION_COVERAGE.md:181-185). The only
    -- cross-prefix entry es_1h_flail is ✅; everything else is native wh_*.
    wh_priest = { [W.SALTZPYRE_FLAIL] = true },
    -- sienna: zero cross-character ports — all native (prefix rule covers it).
    sienna = {},
}

-- char_key -> { weapon_key = true } : decided set, 3P GRIP OFFSET still needed.
-- bw_ghost_scythe BAKED v0.12.150-dev: its +0.569 Z 3P grip offset (es_-scoped)
-- now lives in _weapon_grip_offsets.bw_ghost_scythe.es_ (weapon_tweaker.lua), so
-- the offset is applied, not pending — removed from _NEEDS_OFFSETS so routing_state
-- retains a wired route. (The anim port is also baked into _3p_template_remaps
-- .staff_scythe.es_, and the key is present in _WIRED below.)
-- we_2h_axe (Elven 2H Axe/Glaive) GRIP OFFSET SET v0.12.152-dev: DURABLE +0.285 Z
-- es_-scoped grip offset (_weapon_grip_offsets.we_2h_axe.es_ = {0,0,0.285} +
-- _DURABLE_GRIP_OFFSETS.we_2h_axe = true). v0.12.156-dev: the anim IS now BAKED
-- too (career-scoped _3p_template_remaps.two_handed_axes_template_2.es_ ->
-- Greathammer), so the Glaive moved to _WIRED above and
-- was removed from _NEEDS_ANIMS / the picker below.
local _NEEDS_OFFSETS = {
    kruber = {},
}

-- char_key -> { weapon_key = true } : no decision captured yet.
local _UNTESTED = {
    kruber = { [W.KERILLIAN_JAVELIN] = true, [W.KERILLIAN_DEEPWOOD_STAFF] = true },
    -- #111: present in every Kerillian unlock list but absent from the coverage
    -- decision ledger. Do not let the generic fallback imply a target exists.
    kerillian = { [W.KRUBER_MACE] = true, [W.KRUBER_LONGBOW] = true },
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
-- .md at runtime — this is the generated routing mirror.
--
-- Membership here is INTENTIONALLY a closed list, NOT a default: untested ports
-- (Beam Staff bw_skullstaff_beam, Javelin, Deepwood Staff) are absent, so they
-- never leak into the picker, and M.state's default-return remains
-- needs_animations, so no ~100-port behavior shift in audit classification.
local _NEEDS_ANIMS = {
    -- v0.12.188-dev: the v0.12.157 Kruber staves/Coghammer/Greathammer/Rapier batch
    -- (10 ports) was BAKED career-scoped (es_) into _3p_template_remaps
    -- (weapon_tweaker.lua) from the user's persisted dev-picker picks and moved to
    -- _WIRED above. Only wh_hammer_book remains pending (no picks
    -- captured yet — its 3P is a mesh-swap, not an anim remap; #181).
    kruber = {
        -- v0.12.201-dev: wh_hammer_book BAKED (es_) -> _WIRED.kruber. Emptied.
        -- Next Kruber batch (if any) is queued here.
    },
    -- v0.12.188-dev: all 17 Saltzpyre batch-1/2/3 ports BAKED career-scoped (wh_)
    -- into _3p_template_remaps from the user's persisted dev-picker picks and moved
    -- to _WIRED above — this gate was emptied.
    -- v0.12.194-dev (#160): re-surfaced the Kruber Executioner Sword for Saltzpyre
    -- per-attack tuning. VALUE = the picker SET label; kept in lockstep with
    -- _SALTZ_WEAPON_SET (wt_dev_anim_picker.lua).
    -- v0.12.201-dev: Saltzpyre batch-2 — 11 cross-character 3P ports queued for the
    -- tester's dev-picker tuning (es_2h_sword_executioner from batch-1 was BAKED (wh_)
    -- -> _WIRED.saltzpyre). VALUE = the picker SET display label (_SALTZ_SET_LABEL);
    -- kept in lockstep with _SALTZ_WEAPON_SET (wt_dev_anim_picker.lua). Every wield-render
    -- target has a wh_* redirect in _WIELD_ANIM_CAREER_3P_PATCHES_BULK (wt_wield_patches).
    -- v0.12.213-dev (#519): Saltzpyre batch-2 — 10 of the 11 ports were fully tuned
    -- by the tester and BAKED career-scoped (wh_) into _3p_template_remaps
    -- (_wt_anim_remap.lua) -> moved to _WIRED above. The former
    -- dr_dual_wield_hammers row is no longer offered on Saltzpyre and was removed
    -- from this table under #112. Only the two #576 reopened ports remain live.
    saltzpyre = {
        -- #576: static mappings are candidates, not visual confirmation.
        [W.SIENNA_ENSORCELLED_REAPER] = "Warrior Priest Greathammer",
        [W.KERILLIAN_SPEAR] = "Saltzpyre Billhook",
        -- #112: dr_dual_wield_hammers is no longer present in any non-WP
        -- Saltzpyre unlock list and has no picker row. Do not retain an
        -- unreachable status entry that falsely implies it can be tuned here.
    },
    -- v0.12.193-dev: Kerillian batch 1 — the "next group" of cross-character 3P ports
    -- surfaced for dev-picker tuning (mirrors the Saltzpyre batch-1 setup). Every
    -- non-`we_` port that appears in a `we_*` unlock list, is not already
    -- _WIRED.kerillian, and has a `we_*` wield-redirect target in wt_wield_patches.
    -- VALUE = the Kerillian-native wield-redirect the port's 3P borrows (the picker SET
    -- label). Kept in lockstep with _KERI_WEAPON_SET (wt_dev_anim_picker.lua).
    kerillian = {
        -- v0.12.201-dev: Kerillian batch-1 (all 33 ports) BAKED (we_) -> _WIRED.kerillian
        -- from the tester's fully-tuned picks. Emptied. Next Kerillian batch (if any) queued here.
    },
}

-- Issue #109: source-backed wield targets for Kruber ports which have not yet
-- been promoted into the picker.  This is diagnostic metadata, not an animation
-- bake: it makes the already-wired/decided SET visible without claiming the
-- per-attack vocabulary works.  Unknown rows deliberately remain absent.
local _DIAGNOSTIC_TARGET = {
    kruber = {
        [W.BARDIN_THROWING_AXES] = "Empire 1H Mace",
        [W.BARDIN_DRAKEFIRE_PISTOLS] = "Repeater Handgun",
        [W.BARDIN_DRAKEGUN] = "Empire Blunderbuss",
        [W.BARDIN_MASTERWORK_PISTOL] = "Repeater Handgun",
        [W.BARDIN_TROLLHAMMER_TORPEDO] = "Empire Blunderbuss",
        [W.KERILLIAN_MOONFIRE_BOW] = "Empire Longbow",
        [W.KERILLIAN_SWIFT_BOW] = "Empire Longbow",
        [W.KERILLIAN_HAGBANE_SHORT_BOW] = "Empire Longbow",
        [W.KERILLIAN_VOLLEY_CROSSBOW] = "Repeater Handgun",
        [W.SALTZPYRE_VOLLEY_CROSSBOW] = "Repeater Handgun",
        [W.SALTZPYRE_GRIFFON_FOOT] = "Repeater Handgun",
    },
    kerillian = {
        -- #111: coverage-ledger decisions for the remaining unbaked ranged
        -- surface. These labels describe the chosen receiver vocabulary only;
        -- they do not promote the port out of U or make it picker-ready.
        [W.BARDIN_CROSSBOW] = "Elf Repeater Crossbow",
        [W.BARDIN_TROLLHAMMER_TORPEDO] = "Elf Repeater Crossbow",
        [W.BARDIN_DRAKEFIRE_PISTOLS] = "Elf Repeater Crossbow",
        [W.BARDIN_DRAKEGUN] = "Elf Repeater Crossbow",
        [W.BARDIN_GRUDGE_RAKER] = "Elf Repeater Crossbow",
        [W.BARDIN_MASTERWORK_PISTOL] = "Elf Repeater Crossbow",
        [W.KRUBER_BLUNDERBUSS] = "Elf Repeater Crossbow",
        [W.KRUBER_HANDGUN] = "Elf Repeater Crossbow",
        [W.KRUBER_REPEATING_HANDGUN] = "Elf Repeater Crossbow",
        [W.SALTZPYRE_BRACE_OF_PISTOLS] = "Elf Repeater Crossbow",
        [W.SALTZPYRE_CROSSBOW] = "Elf Repeater Crossbow",
        [W.SALTZPYRE_VOLLEY_CROSSBOW] = "Elf Repeater Crossbow",
        [W.SALTZPYRE_GRIFFON_FOOT] = "Elf Repeater Crossbow",
        [W.SALTZPYRE_REPEATING_PISTOL] = "Elf Repeater Crossbow",
    },
    saltzpyre = {
        -- #112: source/coverage-backed receiver targets for live ports which
        -- remain unbaked or visually unverified. These are diagnostic labels,
        -- not promotions out of U and not implicit picker membership.
        [W.BARDIN_THROWING_AXES] = "Saltzpyre 1H Axe",
        [W.BARDIN_TROLLHAMMER_TORPEDO] = "Saltzpyre Crossbow",
        [W.BARDIN_DRAKEFIRE_PISTOLS] = "Brace of Pistols",
        [W.BARDIN_DRAKEGUN] = "Volley Crossbow",
        [W.BARDIN_GRUDGE_RAKER] = "Volley Crossbow",
        [W.BARDIN_MASTERWORK_PISTOL] = "Repeater Pistol",
        [W.KRUBER_BLUNDERBUSS] = "Saltzpyre Crossbow",
        [W.KRUBER_SPEAR_AND_SHIELD] = "Dual Axe & Falchion",
        [W.KRUBER_HANDGUN] = "Saltzpyre Crossbow",
        [W.KRUBER_REPEATING_HANDGUN] = "Repeater Pistol",
        [W.KERILLIAN_SPEAR_AND_SHIELD] = "Dual Axe & Falchion",
        [W.KERILLIAN_MOONFIRE_BOW] = "Saltzpyre Crossbow",
        [W.KERILLIAN_JAVELIN] = "Saltzpyre 1H Axe",
    },
}

-- Issue #108: display-only mirror of historical, career-scoped 3P redirects.
-- `_WIRED` deliberately remains a boolean routing set; keeping presentation
-- names separate prevents a wording edit from changing routing behavior.
-- Pending ports still source their target from `_NEEDS_ANIMS` below.
local _REDIRECT_DISPLAY = {
    kruber = {
        [W.BARDIN_WAR_PICK] = "Empire Greathammer",
        [W.BARDIN_COG_HAMMER] = "Empire Greathammer",
        [W.SALTZPYRE_HOLY_GREAT_HAMMER] = "Empire Greathammer",
        [W.KERILLIAN_GLAIVE] = "Empire Greathammer",
        [W.SIENNA_MACE] = "Empire Greathammer",
        [W.SIENNA_ENSORCELLED_REAPER] = "Empire Greathammer",
        [W.SIENNA_BEAM_STAFF] = "Empire Greathammer",
        [W.SIENNA_FIREBALL_STAFF] = "Empire Greathammer",
        [W.SIENNA_FLAMESTORM_STAFF] = "Empire Greathammer",
        [W.SIENNA_CONFLAGRATION_STAFF] = "Empire Greathammer",
        [W.SIENNA_BOLT_STAFF] = "Empire Greathammer",
        [W.SIENNA_SOULSTEALER_STAFF] = "Empire Greathammer",
        [W.SIENNA_CORUSCATION_STAFF] = "Empire Greathammer",
        [W.KERILLIAN_DUAL_DAGGERS] = "Empire Mace & Sword",
        [W.KERILLIAN_DUAL_SWORDS] = "Empire Mace & Sword",
        [W.KERILLIAN_SWORD_AND_DAGGER] = "Empire Mace & Sword",
        [W.SALTZPYRE_DUAL_SKULL_SPLITTERS] = "Empire Mace & Sword",
        [W.SALTZPYRE_FLAIL_AND_SHIELD] = "Empire Mace & Shield",
        [W.SIENNA_DAGGER] = "Empire 1H Sword",
        [W.SIENNA_FLAME_SWORD] = "Empire 1H Sword",
        [W.SALTZPYRE_RAPIER] = "Empire 1H Sword",
        [W.KERILLIAN_ELVEN_AXE] = "Witch Hunter 1H Axe",
        [W.SALTZPYRE_HAMMER_AND_TOME] = "1H Mace/Skullsplitter",
    },
    bardin = {
        -- #110: event-level dr_-scoped remaps, not whole-weapon substitutions.
        [W.KERILLIAN_SWORD] = "Bardin 1H event map",
        [W.KRUBER_SWORD] = "Bardin 1H event map",
        [W.SALTZPYRE_FALCHION] = "Bardin 1H event map",
        [W.SIENNA_CROWBILL] = "Bardin 1H event map",
    },
    wh_priest = {
        -- #113: the Empire Flail keeps its own wield vocabulary on the Priest
        -- body, with the shipped per-unit push/heavy correction. This is an
        -- event-map label, not a claim that another whole weapon is substituted.
        [W.SALTZPYRE_FLAIL] = "Warrior Priest flail event map",
    },
    saltzpyre = {
        [W.KERILLIAN_ELVEN_AXE] = "Saltzpyre 1H Axe",
        [W.KERILLIAN_GLAIVE] = "Warrior Priest Greathammer",
        [W.KRUBER_TWO_HANDED_HAMMER] = "Warrior Priest Greathammer",
        [W.BARDIN_COG_HAMMER] = "Warrior Priest Greathammer",
        [W.BARDIN_WAR_PICK] = "Warrior Priest Greathammer",
        [W.SIENNA_MACE] = "Warrior Priest Greathammer",
        [W.SIENNA_BEAM_STAFF] = "Warrior Priest Greathammer",
        [W.SIENNA_FIREBALL_STAFF] = "Warrior Priest Greathammer",
        [W.SIENNA_FLAMESTORM_STAFF] = "Warrior Priest Greathammer",
        [W.SIENNA_CONFLAGRATION_STAFF] = "Warrior Priest Greathammer",
        [W.SIENNA_BOLT_STAFF] = "Warrior Priest Greathammer",
        [W.SIENNA_SOULSTEALER_STAFF] = "Warrior Priest Greathammer",
        [W.SIENNA_CORUSCATION_STAFF] = "Warrior Priest Greathammer",
        [W.KRUBER_MACE_AND_SWORD] = "Dual Axe & Falchion",
        [W.KERILLIAN_DUAL_DAGGERS] = "Dual Axe & Falchion",
        [W.KERILLIAN_DUAL_SWORDS] = "Dual Axe & Falchion",
        [W.KERILLIAN_SWORD_AND_DAGGER] = "Dual Axe & Falchion",
        [W.KRUBER_MACE_AND_SHIELD] = "Dual Axe & Falchion",
        [W.KRUBER_SWORD_AND_SHIELD] = "Dual Axe & Falchion",
        [W.KRUBER_BRETONNIAN_SWORD_AND_SHIELD] = "Dual Axe & Falchion",
        [W.BARDIN_AXE_AND_SHIELD] = "Dual Axe & Falchion",
        [W.SIENNA_DAGGER] = "1H Falchion",
        [W.SIENNA_FLAME_SWORD] = "1H Falchion",
        [W.KRUBER_HALBERD] = "Billhook",
        [W.KRUBER_EXECUTIONER_SWORD] = "Saltzpyre 2H Sword",
        [W.KRUBER_BRETONNIAN_LONGSWORD] = "Saltzpyre 2H Sword",
    },
    kerillian = {
        [W.KRUBER_TWO_HANDED_HAMMER] = "Elf 2H Axe/Glaive",
        [W.SALTZPYRE_HOLY_GREAT_HAMMER] = "Elf 2H Axe/Glaive",
        [W.BARDIN_COG_HAMMER] = "Elf 2H Axe/Glaive",
        [W.BARDIN_WAR_PICK] = "Elf 2H Axe/Glaive",
        [W.SIENNA_ENSORCELLED_REAPER] = "Elf 2H Axe/Glaive",
        [W.SIENNA_BEAM_STAFF] = "Elf 2H Axe/Glaive",
        [W.SIENNA_FIREBALL_STAFF] = "Elf 2H Axe/Glaive",
        [W.SIENNA_FLAMESTORM_STAFF] = "Elf 2H Axe/Glaive",
        [W.SIENNA_CONFLAGRATION_STAFF] = "Elf 2H Axe/Glaive",
        [W.SIENNA_BOLT_STAFF] = "Elf 2H Axe/Glaive",
        [W.SIENNA_SOULSTEALER_STAFF] = "Elf 2H Axe/Glaive",
        [W.SIENNA_CORUSCATION_STAFF] = "Elf 2H Axe/Glaive",
        [W.KRUBER_EXECUTIONER_SWORD] = "Elf 2H Sword",
        [W.KRUBER_BRETONNIAN_LONGSWORD] = "Elf 2H Sword",
        [W.SALTZPYRE_RAPIER] = "Elf 1H Sword",
        [W.SIENNA_FLAMING_FLAIL] = "Elf 1H Sword",
        [W.SIENNA_DAGGER] = "Elf 1H Sword",
        [W.SIENNA_FLAME_SWORD] = "Elf 1H Sword",
        [W.SALTZPYRE_1H_HAMMER] = "Elf 1H Axe",
        [W.BARDIN_HAMMER] = "Elf 1H Axe",
        [W.KRUBER_MACE_AND_SHIELD] = "Elf Spear & Shield",
        [W.KRUBER_SWORD_AND_SHIELD] = "Elf Spear & Shield",
        [W.KRUBER_BRETONNIAN_SWORD_AND_SHIELD] = "Elf Spear & Shield",
        [W.SALTZPYRE_FLAIL_AND_SHIELD] = "Elf Spear & Shield",
        [W.SALTZPYRE_HAMMER_AND_TOME] = "Elf Spear & Shield",
        [W.SALTZPYRE_SKULL_SPLITTER_AND_SHIELD] = "Elf Spear & Shield",
        [W.BARDIN_AXE_AND_SHIELD] = "Elf Spear & Shield",
        [W.SALTZPYRE_DUAL_SKULL_SPLITTERS] = "Dual Swords",
        [W.BARDIN_DUAL_AXES] = "Dual Swords",
        [W.BARDIN_DUAL_HAMMERS] = "Dual Swords",
        [W.KRUBER_MACE_AND_SWORD] = "Sword & Dagger",
        [W.SALTZPYRE_AXE_AND_FALCHION] = "Sword & Dagger",
        [W.BARDIN_THROWING_AXES] = "Elf Javelin",
    },
}

-- Issue #108: shipped 3P mesh substitutions. These are visual lies applied to
-- the receiver's third-person/preview model; first-person weapon models remain
-- the real equipped item. Keep this mirror aligned with the model dispatchers.
local _MODEL_SUB = {
    kruber = {
        [W.SALTZPYRE_BRACE_OF_PISTOLS] = "Repeater Handgun",
        [W.SALTZPYRE_REPEATING_PISTOL] = "Repeater Handgun",
    },
    saltzpyre = {
        [W.KRUBER_LONGBOW] = "Crossbow",
        [W.KERILLIAN_LONGBOW] = "Crossbow",
        [W.KERILLIAN_MOONFIRE_BOW] = "Crossbow",
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

-- Public: internal routing state for a (career, weapon_key) pair. This is not a
-- verification lifecycle and must never be rendered as Working/Verified.
function M.routing_state(career, weapon_key)
    if _is_native(career, weapon_key) then return "native" end
    local recv = _char_key_for_career(career)
    if not recv then return "unknown" end
    if _WIRED[recv] and _WIRED[recv][weapon_key] then return "wired" end
    if _NEEDS_OFFSETS[recv] and _NEEDS_OFFSETS[recv][weapon_key] then return "needs_offsets" end
    if _UNTESTED[recv] and _UNTESTED[recv][weapon_key] then return "unknown" end
    -- Default for a surviving cross-character port: a set is decided (the unlock
    -- map only carries ports with a chosen 3P target) but per-attack picks pend.
    return "needs_animations"
end

-- Deprecated compatibility API. Under #948 every cell begins U regardless of
-- static routing. Callers needing picker/donor metadata use routing_state().
function M.state(_career, _weapon_key)
    return "untested"
end

-- Public: redirect-target display name for a
-- (career, weapon_key) pair, e.g. "Greathammer", or nil when none is on file.
-- Pending ports source `_NEEDS_ANIMS`; historical/baked ports source the #108
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

-- Historical receiver inventory audit retained for source-routing regressions.
-- Every returned row is explicitly untested under #948; routing_state describes
-- only the existing donor/picker lead. Duplicate keys are ignored.
function M.audit_cross_character(career, weapon_keys)
    local rows, seen = {}, {}
    local counts = {
        total = 0,
        untested = 0,
        routing_native = 0,
        routing_wired = 0,
        routing_needs_animations = 0,
        routing_needs_offsets = 0,
        routing_unknown = 0,
        picker_visible = 0,
    }

    for _, weapon_key in ipairs(type(weapon_keys) == "table" and weapon_keys or {}) do
        if type(weapon_key) == "string"
                and not seen[weapon_key]
                and not _is_native(career, weapon_key) then
            seen[weapon_key] = true
            local routing_state = M.routing_state(career, weapon_key)
            local picker_visible = M.needs_anims(career, weapon_key)
            local row = {
                weapon_key = weapon_key,
                state = "untested",
                verification_state = "untested",
                routing_state = routing_state,
                redirect = M.redirect_target(career, weapon_key),
                model_substitute = M.model_substitute(career, weapon_key),
                picker_visible = picker_visible,
            }
            rows[#rows + 1] = row
            counts.total = counts.total + 1
            counts.untested = counts.untested + 1
            local routing_key = "routing_" .. routing_state
            counts[routing_key] = (counts[routing_key] or 0) + 1
            if picker_visible then counts.picker_visible = counts.picker_visible + 1 end
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
