-- _wt_anim_remap_data.lua -- declarative per-template 3P animation remap catalog.
--
-- Builds the template-keyed remap table consumed by _wt_anim_remap.lua. The
-- catalog stays separate from the event-hot dispatch module; construction runs
-- once at module load and returns the same mutable table object exported through
-- mod._wt for the entry's port-pipeline patchers and regression checks.
--
-- Owned by: weapon_tweaker.lua manifest. Consumed by: _wt_anim_remap.lua via
-- mod._wt.build_3p_template_remaps after one manifest-level mod:dofile.

return function(_3p_remap_billhook_to_polearm, _3p_remap_spear_to_polearm, _3p_remap_triggers)

-- Template-based 3P attack remaps: when a cross-career weapon shares a wield
-- event with a different native weapon, attack events may lack valid transitions
-- in the target skeleton's 3P state machine. Remap to compatible events.
-- Key: weapon template name. Value: { career_prefix = remap_table, ... }
-- A nil value for a prefix means no remap needed (native character).
local _3p_template_remaps = {
    two_handed_swords_template_1 = {
        we_ = {
            attack_swing_charge_diagonal       = "attack_swing_charge",
            attack_swing_charge_diagonal_right = "attack_swing_charge",
            attack_swing_charge_diagonal_left  = "attack_swing_charge",
            attack_swing_heavy_left_diagonal   = "attack_swing_left",
            attack_swing_heavy_right_diagonal  = "attack_swing_heavy_right",
            attack_swing_left_diagonal         = "attack_swing_left",
            attack_swing_right_diagonal        = "attack_swing_right",
            attack_swing_down_right            = "attack_swing_heavy",
        },
    },
    two_handed_axes_template_1 = {
        dr_ = false,
        _default = {
            attack_swing_up                   = "attack_swing_left",
            attack_swing_heavy_left_diagonal  = "attack_swing_heavy",
            attack_swing_heavy_right_diagonal = "attack_swing_heavy_right",
        },
    },
    two_handed_swords_wood_elf_template = {
        we_ = false,
        wh_ = {
            attack_swing_charge      = "attack_swing_charge_left_diagonal",
            attack_swing_right       = "attack_swing_right_diagonal",
            attack_swing_left        = "attack_swing_left_diagonal",
            attack_swing_heavy       = "attack_swing_heavy_left_diagonal",
            attack_swing_heavy_right = "attack_swing_heavy_right_diagonal",
        },
        _default = {
            attack_swing_charge      = "attack_swing_charge_left_diagonal",
            attack_swing_left        = "attack_swing_up_left",
            attack_swing_heavy       = "attack_swing_heavy_left_diagonal",
            attack_swing_heavy_right = "attack_swing_heavy_right_diagonal",
        },
    },
    one_hand_falchion_template_1 = {
        wh_ = false,
        dr_ = {
            -- Bardin: differentiate the two heavy variants
            --   left_diagonal (variant A)        → elf H1 (vertical) — charge fires natively
            --   right_diagonal_pose (variant B)  → elf H2 (right swing)
            attack_swing_charge_right_diagonal_pose = "attack_swing_charge_right_pose",
            attack_swing_heavy_left_diagonal        = "attack_swing_heavy_down",
            attack_swing_heavy_right_diagonal       = "attack_swing_heavy_right",
            attack_swing_up                         = "attack_swing_down",
        },
        _default = {
            attack_swing_charge_left_diagonal      = "attack_swing_charge_left",
            attack_swing_charge_right_diagonal_pose = "attack_swing_charge_right_pose",
            attack_swing_charge_left_diagonal_pose  = "attack_swing_charge_left_pose",
            attack_swing_heavy_left_diagonal        = "attack_swing_heavy",
            attack_swing_heavy_right_diagonal       = "attack_swing_heavy_right",
            attack_swing_up                         = "attack_swing_down",
        },
    },
    one_handed_crowbill = {
        bw_ = false,
        dr_ = {
            -- Bardin: H1 and H3 release fires events that produce no visible
            -- animation on his crowbill SM. Use the elf-sword overhead targets.
            attack_swing_stab                = "attack_swing_down",
            -- v0.12.205: up_left target corrected to the tester's pick
            -- (attack_swing_left, consistent across all 7 configs on disk;
            -- the table had drifted to left_diagonal). #319 audit.
            attack_swing_up_left             = "attack_swing_left",
            attack_swing_charge_left         = "attack_swing_charge_left_diagonal", -- H1 charge windup
            attack_swing_heavy_left_up       = "attack_swing_heavy_down",           -- H1 release overhead
            attack_swing_charge_left_pose    = "attack_swing_charge_left_diagonal", -- H3 charge windup
            attack_swing_heavy_left_diagonal = "attack_swing_heavy_down",           -- H3 release overhead
        },
        _default = {
            -- attack_swing_left fires natively as a right-swing on cross
            -- skeletons (verified via wt force3p on Kruber). Don't remap it —
            -- earlier versions mapped it to attack_swing_down, which collapsed
            -- L2 into L1's vertical and made the first two lights look identical.
            attack_swing_stab          = "attack_swing_down",  -- thrust → vertical (no working thrust event on cross skeleton)
            attack_swing_heavy_left_up = "attack_swing_heavy",
            attack_swing_heavy_left_diagonal = "attack_swing_heavy",
            -- v0.12.205: corrected to the tester's pick (see dr_ note). #319 audit.
            attack_swing_up_left       = "attack_swing_left",
        },
    },
    -- one_handed_flails_flaming_template: no template-level remaps. H1
    -- (attack_swing_charge_down → attack_swing_heavy_down) fires natively as
    -- the correct overhead. H2's broken release (attack_swing_heavy_left) is
    -- handled by the direct-redirect block in the animation_event hook —
    -- table-remap of that event corrupts the SM (same pattern as billhook
    -- attack_swing_stab_02).
    --
    -- Saltzpyre's billhook (wh_2h_billhook) on Kruber. v0.12.102-dev fix for
    -- the wield-event-collision bug class identified during the Kruber-on-
    -- billhook regression triage:
    --   `_WIELD_ANIM_CAREER_3P_PATCHES.two_handed_billhooks_template` rewrites
    --   the wield event to `to_polearm` for es_*. The v0.12.64-dev
    --   `_resolve_3p_remap(event_name, career)` fallback at line ~1287 then
    --   keys on the POST-patch wield event, but `_3p_remap_triggers["to_polearm"]`
    --   defines `es_ = _3p_remap_spear_to_polearm` (authored for the elf-spear
    --   cross-character port). That entry hijacks the billhook lookup and
    --   installs the wrong remap table — billhook source events (e.g.
    --   `attack_swing_charge_stab`, `attack_swing_left_diagonal`, etc., all
    --   listed in `_3p_remap_billhook_to_polearm` at line ~644) get no
    --   substitute and fire raw on Kruber's polearm SM. Adding an explicit
    --   `_3p_template_remaps[two_handed_billhooks_template]` entry routes the
    --   lookup through `_resolve_template_remap` FIRST (line ~1247), which is
    --   keyed unambiguously by template name and short-circuits the ambiguous
    --   wield-event fallback. The wh_ branch is intentionally `false` —
    --   billhook is Saltzpyre-native and needs no remap.
    two_handed_billhooks_template = {
        wh_ = false,
        es_ = _3p_remap_billhook_to_polearm,
    },
    -- ============================================================
    -- v0.12.149-dev: BAKED Kruber 3P picks for 4 natively-owned weapons.
    -- ============================================================
    -- These four ports were tuned via the dev anim picker and CONFIRMED working
    -- on Kruber. The picks are baked here (career-scoped) instead of the picker's
    -- raw shared-template write — see KRUBER_3P_ANIM_DECISIONS.md "BAKED" section.
    --
    -- WHY CAREER-SCOPED, NOT A SHARED `anim_event_3p` WRITE: each template carries
    -- NO authored `anim_event_3p` natively (verified: 2h_picks.lua / dual_wield_axes
    -- .lua / 1h_swords_flaming_spell.lua / 1h_dagger_wizard.lua all have anim_event
    -- only). So weapon_unit_extension.lua:512 (`anim_event_3p or event`) fires the
    -- source `anim_event` string on EVERY wielder's own 3P body at :652. Writing the
    -- shared template's `anim_event_3p` would make Bardin (pickaxe, dual axes) and
    -- Sienna (fire sword, dagger) — the NATIVE owners — fire the Kruber-tuned string
    -- on THEIR skeletons too, breaking the native view. The `es_` remap below
    -- redirects ONLY for Kruber's careers; the owner prefix (`dr_`/`bw_`) is `false`
    -- → _resolve_template_remap returns nil → native owner plays UNTOUCHED. Same
    -- native-owned precedent as two_handed_billhooks_template above (wh_ = false).
    --
    -- 3P-ONLY by construction: consumed at the Unit.animation_event hook (:1513),
    -- whose `unit` is the 3P body (1P hands unit excluded upstream). Remap keys are
    -- the fired event = the template's source `anim_event` (no authored anim_event_3p),
    -- which equals the picker's source-event dump verbatim. Identity entries
    -- (attack_push->attack_push, parry_pose->parry_pose, etc.) are harmless re-fires;
    -- a target absent on Kruber's redirected SM safely falls through (native fires).
    --
    -- Bardin pickaxe (dr_2h_pick) -> Empire Greathammer (wield to_2h_hammer on es_).
    two_handed_picks_template_1 = {
        dr_ = false, -- native (Bardin): untouched
        es_ = {
            attack_push                         = "attack_push",
            attack_swing_charge_left_down       = "attack_swing_charge_left",
            attack_swing_charge_left_down_pose  = "attack_swing_charge",
            attack_swing_charge_right_down      = "attack_swing_charge_right",
            attack_swing_down_left              = "attack_swing_down_left",
            attack_swing_down_left_axe          = "attack_swing_down_left",
            attack_swing_down_right             = "attack_swing_down_right",
            attack_swing_down_right_axe         = "attack_swing_down_right",
            attack_swing_left                   = "attack_swing_left",
            attack_swing_left_diagonal          = "attack_swing_left_diagonal",
            attack_swing_right_diagonal         = "attack_swing_heavy_right",
            parry_pose                          = "parry_pose",
        },
    },
    -- Sienna fire sword (bw_flame_sword) -> Empire 1H Sword (wield to_1h_sword on es_).
    flaming_sword_template_1 = {
        bw_ = false, -- native (Sienna): untouched
        es_ = {
            attack_push                  = "attack_push",
            attack_swing_charge          = "attack_swing_charge_left",
            attack_swing_charge_right    = "attack_swing_charge_right_pose",
            attack_swing_heavy           = "attack_swing_heavy",
            attack_swing_left            = "attack_swing_left_diagonal",
            attack_swing_left_diagonal   = "attack_swing_left_diagonal",
            attack_swing_right_diagonal  = "attack_swing_right_diagonal",
            attack_swing_right_spell     = "attack_swing_right",
            attack_swing_stab            = "attack_swing_down",
            parry_pose                   = "parry_pose",
        },
        -- v0.12.188-dev: Sienna Flaming Sword on SALTZPYRE body -> 1H Falchion
        -- (wh_-scoped redirect). attack_swing_right_spell has no Falchion twin —
        -- mapped to the nearest event per the user's pick.
        wh_ = {
            attack_push                 = "attack_push",
            attack_swing_charge         = "attack_swing_charge_left_diagonal_pose",
            attack_swing_charge_right   = "attack_swing_charge_right_diagonal_pose",
            attack_swing_heavy          = "attack_swing_heavy_left_diagonal",
            attack_swing_left           = "attack_swing_left_diagonal",
            attack_swing_left_diagonal  = "attack_swing_left_diagonal",
            attack_swing_right_diagonal = "attack_swing_right_diagonal",
            attack_swing_right_spell    = "attack_swing_up",
            attack_swing_stab           = "attack_swing_down",
            parry_pose                  = "parry_pose",
        },
    },
    -- Sienna dagger (bw_dagger) -> Empire 1H Sword (wield to_1h_sword on es_).
    one_handed_daggers_template_1 = {
        bw_ = false, -- native (Sienna): untouched
        es_ = {
            attack_push                  = "attack_push",
            attack_swing_charge          = "attack_swing_charge_left",
            attack_swing_charge_left     = "attack_swing_charge_right_pose",
            attack_swing_heavy           = "attack_swing_heavy",
            attack_swing_heavy_right     = "attack_swing_heavy_right",
            attack_swing_left            = "attack_swing_left_diagonal",
            attack_swing_left_diagonal   = "attack_swing_left_diagonal",
            attack_swing_right_diagonal  = "attack_swing_right_diagonal",
            attack_swing_stab            = "attack_swing_down",
            parry_pose                   = "parry_pose",
        },
        -- v0.12.188-dev: Sienna Dagger on SALTZPYRE body -> 1H Falchion
        -- (wh_-scoped redirect).
        wh_ = {
            attack_push                 = "attack_push",
            attack_swing_charge         = "attack_swing_charge_left_diagonal_pose",
            attack_swing_charge_left    = "attack_swing_charge_right_diagonal_pose",
            attack_swing_heavy          = "attack_swing_heavy_left_diagonal",
            attack_swing_heavy_right    = "attack_swing_heavy_right_diagonal",
            attack_swing_left           = "attack_swing_left_diagonal",
            attack_swing_left_diagonal  = "attack_swing_left_diagonal",
            attack_swing_right_diagonal = "attack_swing_right_diagonal",
            attack_swing_stab           = "attack_swing_heavy_left_diagonal",
            parry_pose                  = "parry_pose",
        },
    },
    -- Bardin's dual axes on non-Slayer careers. The wield event redirect
    -- (to_dual_axes → to_dual_hammers) loads the dual-hammers SM, but the
    -- dual_wield_axes template fires several attack events the dual-hammers
    -- SM doesn't define. Map them to dual-hammers anim_events that play.
    -- Per-career entries (dr_ironbreaker / dr_ranger / dr_engineer); dr_slayer
    -- has no entry so _resolve_template_remap returns nil → native plays.
    dual_wield_axes_template_1 = (function()
        -- Spread dual-axe lights across the 5 distinct dual_hammers light
        -- anim_events (left, down, left_diagonal, up, stab) so each chain
        -- position plays a unique animation. dual_axes L1's native release
        -- (attack_swing_left_diagonal) already plays as dual_hammers L3 swing,
        -- so leave it alone; remap the other 4 light releases onto the
        -- remaining 4 dual_hammers light anim_events.
        local t = {
            attack_swing_charge_diagonal = "attack_swing_charge_left",   -- L3 / H3 charge windup
            attack_swing_heavy_right     = "attack_swing_heavy_right_diagonal", -- H1 release
            attack_swing_heavy           = "attack_swing_heavy_down",    -- H2 release
            -- Lights (each maps to a different dual_hammers light):
            attack_swing_right_diagonal  = "attack_swing_left",          -- L2 release → dual_hammers L1
            attack_swing_left            = "attack_swing_down",          -- L3 release → dual_hammers L2
            attack_swing_right           = "attack_swing_up",            -- L4 release → dual_hammers L4
            attack_swing_down            = "attack_swing_stab",          -- L5 release → dual_hammers L5
            -- L1 native (attack_swing_left_diagonal) plays dual_hammers L3 swing
        }
        -- v0.12.149-dev: BAKED Kruber picks. Bardin's dual axes on Kruber render
        -- as Empire Mace & Sword (wield to_dual_hammer_sword_es). Confirmed via the
        -- dev anim picker; baked here career-scoped. dr_slayer keeps no entry →
        -- native; dr_ironbreaker/ranger/engineer keep `t` above. es_ is Kruber.
        local es_t = {
            attack_push                       = "attack_push",
            attack_swing_charge_diagonal      = "attack_swing_charge_left",
            attack_swing_charge_left          = "attack_swing_charge_left",
            attack_swing_charge_right         = "attack_swing_charge_right",
            attack_swing_down                 = "attack_swing_down",
            attack_swing_heavy                = "attack_swing_heavy_left_diagonal",
            attack_swing_heavy_left_diagonal  = "attack_swing_heavy_left_diagonal",
            attack_swing_heavy_right          = "attack_swing_heavy_right_diagonal",
            attack_swing_left                 = "attack_swing_left_diagonal",
            attack_swing_left_diagonal        = "attack_swing_left",
            attack_swing_right                = "attack_swing_right_diagonal",
            attack_swing_right_diagonal       = "attack_swing_right",
            parry_pose                        = "parry_pose",
        }
        -- v0.12.188-dev: BAKED Saltzpyre picks. Bardin's dual axes on the non-WP
        -- Saltzpyre body render as Dual Axe & Falchion (wield to_dual_axe_falchion);
        -- wh_-scoped redirect, separate from the Kruber es_ bake above.
        local wh_t = {
            attack_push                      = "attack_push",
            attack_swing_charge_diagonal     = "attack_swing_charge_down",
            attack_swing_charge_left         = "attack_swing_charge_left",
            attack_swing_charge_right        = "attack_swing_charge_down",
            attack_swing_down                = "attack_swing_heavy_down",
            attack_swing_heavy               = "attack_swing_heavy_left",
            attack_swing_heavy_left_diagonal = "attack_swing_heavy_down",
            attack_swing_heavy_right         = "attack_swing_heavy_down",
            attack_swing_left                = "attack_swing_down",
            attack_swing_left_diagonal       = "attack_swing_heavy_left",
            attack_swing_right               = "attack_swing_right",
            attack_swing_right_diagonal      = "attack_swing_right",
            parry_pose                       = "parry_pose",
        }
        return { dr_ironbreaker = t, dr_ranger = t, dr_engineer = t, es_ = es_t, wh_ = wh_t }
    end)(),
    -- Sienna's Mace (bw_1h_mace) -> Empire Greathammer on Kruber (wield to_2h_hammer
    -- on es_). v0.12.150-dev: BAKED Kruber picks (confirmed via the dev anim picker).
    -- bw_ = false → Sienna native plays UNTOUCHED; es_ is the Kruber-only redirect.
    one_handed_hammer_wizard_template_1 = {
        bw_ = false, -- native (Sienna): untouched
        es_ = {
            attack_push                         = "attack_push",
            attack_swing_charge_left_diagonal   = "attack_swing_charge",
            attack_swing_charge_left_pose        = "attack_swing_charge_left",
            attack_swing_charge_right_pose       = "attack_swing_charge_right",
            attack_swing_down                    = "attack_swing_down_left",
            attack_swing_heavy_down              = "attack_swing_down_left",
            attack_swing_heavy_left_up           = "attack_swing_heavy",
            attack_swing_heavy_right_up          = "attack_swing_heavy_right",
            attack_swing_left                    = "attack_swing_left",
            attack_swing_left_diagonal           = "attack_swing_left_diagonal",
            attack_swing_left_diagonal_last      = "attack_swing_left_diagonal",
            attack_swing_right_diagonal          = "attack_swing_down_right",
            parry_pose                           = "parry_pose",
        },
    },
    -- Necromancer Ghost Scythe (bw_ghost_scythe) -> Empire Greathammer on Kruber
    -- (wield to_2h_hammer on es_). v0.12.150-dev: BAKED Kruber picks. bw_ = false →
    -- Sienna native plays UNTOUCHED; es_ is the Kruber-only redirect. The two scythe
    -- specials (special_action / special_action_02) have no SET A twin — mapped to
    -- the nearest Greathammer events per the user's picks. ALSO carries a +6 Z 3P
    -- grip offset (es_ only) via _weapon_grip_offsets below, applied through the
    -- DURABLE per-frame path (_DURABLE_GRIP_OFFSETS) — bumped from +0.569 in
    -- v0.12.151-dev because the one-shot offset was stomped in-game (see OFFSETS.md).
    staff_scythe = {
        bw_ = false, -- native (Sienna): untouched
        es_ = {
            attack_push                          = "attack_push",
            attack_swing_charge_left             = "attack_swing_charge_left",
            attack_swing_charge_left_diagonal    = "attack_swing_charge_left",
            attack_swing_charge_right            = "attack_swing_charge_right",
            attack_swing_heavy                   = "attack_swing_heavy",
            attack_swing_heavy_left_diagonal     = "attack_swing_heavy",
            attack_swing_heavy_right             = "attack_swing_heavy_right",
            attack_swing_left                    = "attack_swing_left",
            attack_swing_left_diagonal           = "attack_swing_down_left",
            attack_swing_left_diagonal_last      = "attack_swing_down_left",
            attack_swing_right                   = "attack_swing_heavy_right",
            attack_swing_up_right                = "attack_swing_down_right",
            parry_pose                           = "parry_pose",
            special_action                       = "attack_swing_charge",
            special_action_02                    = "attack_swing_down_left",
        },
    },
    -- Warrior Priest / Saltzpyre Greathammer (wh_2h_hammer, template
    -- two_handed_hammer_priest_template) -> Empire Greathammer on Kruber (wield
    -- to_2h_hammer on es_). v0.12.188-dev: RE-BAKED Kruber picks (#180 — the
    -- v0.12.151 bake animated badly on Kruber, so the weapon was moved back to
    -- _NEEDS_ANIMS in v0.12.157 and re-tuned via the dev anim picker; these picks
    -- are pulled verbatim from the user's persisted picks). wh_ = false →
    -- Saltzpyre/Warrior-Priest natives play UNTOUCHED; es_ is the Kruber-only
    -- redirect. attack_slam / attack_slam_charge have no Greathammer twin — mapped
    -- to the nearest events per the user's picks.
    two_handed_hammer_priest_template = {
        wh_ = false, -- native (Saltzpyre / Warrior Priest): untouched
        es_ = {
            attack_push                       = "attack_push",
            attack_slam                       = "attack_swing_left",
            attack_slam_charge                = "attack_swing_left",
            attack_swing_charge               = "attack_swing_charge",
            attack_swing_charge_right         = "attack_swing_charge",
            attack_swing_charge_right_down    = "attack_swing_charge_left",
            attack_swing_down_right           = "attack_swing_down_left",
            attack_swing_heavy_right          = "attack_swing_heavy",
            attack_swing_heavy_right_diagonal = "attack_swing_down_left",
            attack_swing_left                 = "attack_swing_left_diagonal",
            attack_swing_up                   = "attack_swing_heavy",
            attack_swing_up_left              = "attack_swing_down_left",
            parry_pose                        = "parry_pose",
            parry_pose_02                     = "parry_pose",
        },
    },
    -- Bardin Outcast Engineer Coghammer (dr_2h_cog_hammer, template
    -- two_handed_cog_hammers_template_1) -> Empire Greathammer on Kruber (wield
    -- to_2h_hammer on es_). v0.12.188-dev: RE-BAKED Kruber picks (#182 — the
    -- v0.12.151 3-pick identity bake animated badly on Kruber, so the weapon was
    -- moved back to _NEEDS_ANIMS in v0.12.157 and re-tuned via the dev anim picker;
    -- these 16 picks are pulled verbatim from the user's persisted picks). dr_ =
    -- false → Bardin native plays UNTOUCHED; es_ is the Kruber-only redirect.
    two_handed_cog_hammers_template_1 = {
        dr_ = false, -- native (Bardin Outcast Engineer): untouched
        es_ = {
            attack_push                    = "attack_push",
            attack_swing_charge            = "attack_swing_charge",
            attack_swing_charge_pose       = "attack_swing_charge_left",
            attack_swing_charge_right      = "attack_swing_charge_right",
            attack_swing_charge_right_down = "attack_swing_charge_right",
            attack_swing_down_left         = "attack_swing_down_left",
            attack_swing_down_right        = "attack_swing_down_left",
            attack_swing_heavy             = "attack_swing_down_left",
            attack_swing_heavy_right       = "attack_swing_down_left",
            attack_swing_left              = "attack_swing_left",
            attack_swing_left_diagonal     = "attack_swing_left_diagonal",
            attack_swing_right_diagonal    = "attack_swing_down_right",
            attack_swing_up                = "attack_swing_left",
            attack_swing_up_pose           = "attack_swing_left",
            attack_swing_up_right          = "attack_swing_down_right",
            parry_pose                     = "parry_pose",
        },
    },
    -- ============================================================
    -- v0.12.156-dev: BAKED Kruber 3P picks for 7 more cross-character ports.
    -- ============================================================
    -- Pulled verbatim from the user's persisted dev anim picker (user_settings.config,
    -- 2026-06-25) — the last [Needs Animations] Kruber ports. Same career-scoped
    -- pattern as the v0.12.149-.151 bakes above: native owner prefix = false (owner
    -- plays UNTOUCHED), es_ is the Kruber-only redirect. 3P-only (consumed at the
    -- Unit.animation_event hook). Identity entries are harmless re-fires; __unset__
    -- picks were omitted (fall through to native).

    -- Kerillian 1H Axe (we_1h_axe) -> Kruber native to_1h_axe (mostly identity).
    we_one_hand_axe_template = {
        we_ = false, -- native (Kerillian): untouched
        es_ = {
            attack_push                              = "attack_push",
            attack_swing_charge_left_diagonal        = "attack_swing_charge_left_diagonal",
            attack_swing_charge_left_diagonal_pose   = "attack_swing_charge_left_diagonal_pose",
            attack_swing_charge_right_diagonal_pose  = "attack_swing_charge_right_diagonal_pose",
            attack_swing_down                        = "attack_swing_down_right",
            attack_swing_down_right                  = "attack_swing_down_right",
            attack_swing_heavy_down                  = "attack_swing_heavy_down",
            attack_swing_heavy_down_right            = "attack_swing_heavy_down_right",
            attack_swing_left                        = "attack_swing_left_diagonal",
            attack_swing_right                       = "attack_swing_right_diagonal",
            attack_swing_up                          = "attack_swing_right_diagonal",
            parry_pose                               = "parry_pose",
        },
    },
    -- Kerillian Glaive (we_2h_axe) -> Empire Greathammer (wield to_2h_hammer on es_).
    two_handed_axes_template_2 = {
        we_ = false, -- native (Kerillian): untouched
        es_ = {
            attack_push                = "attack_push",
            attack_swing_charge_down   = "attack_swing_charge_right",
            attack_swing_charge_left   = "attack_swing_charge_right",
            attack_swing_heavy_down    = "attack_swing_down_left",
            attack_swing_heavy_left    = "attack_swing_heavy_right",
            attack_swing_left          = "attack_swing_heavy",
            attack_swing_left_diagonal = "attack_swing_heavy",
            attack_swing_right         = "attack_swing_heavy_right",
            parry_pose                 = "parry_pose",
        },
        -- v0.12.188-dev: Kerillian Glaive on SALTZPYRE body -> WP Greathammer
        -- (two_handed_axes_template_2 source events; wh_-scoped redirect).
        wh_ = {
            attack_push                = "attack_push",
            attack_swing_charge_down   = "attack_swing_charge",
            attack_swing_charge_left   = "attack_swing_charge_right",
            attack_swing_heavy_down    = "attack_swing_left",
            attack_swing_heavy_left    = "attack_swing_heavy_right",
            attack_swing_left          = "attack_swing_left",
            attack_swing_left_diagonal = "attack_swing_down_right",
            attack_swing_right         = "attack_swing_up",
            parry_pose                 = "parry_pose",
        },
    },
    -- Kerillian Dual Daggers (we_dual_wield_daggers) -> Empire Mace & Sword.
    dual_wield_daggers_template_1 = {
        we_ = false, -- native (Kerillian): untouched
        es_ = {
            attack_push                = "attack_push",
            attack_swing_charge        = "attack_swing_charge_left",
            attack_swing_charge_left   = "attack_swing_charge_right",
            attack_swing_charge_right  = "attack_swing_charge_right",
            attack_swing_down_left     = "attack_swing_left",
            attack_swing_down_right    = "attack_swing_right",
            attack_swing_heavy         = "attack_swing_heavy_left_diagonal",
            attack_swing_heavy_down    = "attack_swing_heavy_right_diagonal",
            attack_swing_left          = "attack_swing_left_diagonal",
            attack_swing_right         = "attack_swing_right_diagonal",
            parry_pose                 = "parry_pose",
            push_stab                  = "attack_swing_down",
        },
        -- v0.12.188-dev: Kerillian Dual Daggers on SALTZPYRE body -> Dual Axe &
        -- Falchion (wh_-scoped redirect).
        wh_ = {
            attack_push               = "attack_push",
            attack_swing_charge       = "attack_swing_charge_down",
            attack_swing_charge_left  = "attack_swing_charge_left",
            attack_swing_charge_right = "attack_swing_charge_down",
            attack_swing_down_left    = "attack_swing_heavy_down",
            attack_swing_down_right   = "attack_swing_heavy_left",
            attack_swing_heavy        = "attack_swing_heavy_down",
            attack_swing_heavy_down   = "attack_swing_heavy_down",
            attack_swing_left         = "attack_swing_heavy_down",
            attack_swing_right        = "attack_swing_heavy_left",
            parry_pose                = "parry_pose",
            push_stab                 = "attack_swing_heavy_down",
        },
    },
    -- Kerillian Sword & Dagger (we_dual_wield_sword_dagger) -> Empire Mace & Sword.
    dual_wield_sword_dagger_template_1 = {
        we_ = false, -- native (Kerillian): untouched
        es_ = {
            attack_push                       = "attack_push",
            attack_swing_charge               = "attack_swing_charge_right",
            attack_swing_charge_diagonal      = "attack_swing_charge_left",
            attack_swing_charge_left          = "attack_swing_charge_right",
            attack_swing_heavy                = "attack_swing_heavy_right_diagonal",
            attack_swing_heavy_left_diagonal  = "attack_swing_heavy_left_diagonal",
            attack_swing_left                 = "attack_swing_left_diagonal",
            attack_swing_right                = "attack_swing_right_diagonal",
            attack_swing_right_diagonal       = "attack_swing_right",
            attack_swing_stab                 = "attack_swing_down",
            parry_pose                        = "parry_pose",
            push_stab                         = "attack_swing_down",
        },
        -- v0.12.188-dev: Kerillian Sword & Dagger on SALTZPYRE body -> Dual Axe &
        -- Falchion (wh_-scoped redirect).
        wh_ = {
            attack_push                      = "attack_push",
            attack_swing_charge              = "attack_swing_charge_down",
            attack_swing_charge_diagonal     = "attack_swing_charge_left",
            attack_swing_charge_left         = "attack_swing_charge_down",
            attack_swing_heavy               = "attack_swing_heavy_down",
            attack_swing_heavy_left_diagonal = "attack_swing_heavy_left",
            attack_swing_left                = "attack_swing_heavy_down",
            attack_swing_right               = "attack_swing_heavy_down",
            attack_swing_right_diagonal      = "attack_swing_heavy_left",
            attack_swing_stab                = "attack_swing_heavy_left",
            parry_pose                       = "parry_pose",
            push_stab                        = "attack_swing_heavy_down",
        },
    },
    -- Kerillian Dual Swords (we_dual_wield_swords) -> Empire Mace & Sword.
    dual_wield_swords_template_1 = {
        we_ = false, -- native (Kerillian): untouched
        es_ = {
            attack_push                       = "attack_push",
            attack_swing_charge_diagonal      = "attack_swing_charge_left",
            attack_swing_charge_left          = "attack_swing_charge_right",
            attack_swing_charge_right         = "attack_swing_charge_left",
            attack_swing_heavy_left_diagonal  = "attack_swing_heavy_left_diagonal",
            attack_swing_heavy_right          = "attack_swing_heavy_right_diagonal",
            attack_swing_left                 = "attack_swing_left",
            attack_swing_left_diagonal        = "attack_swing_left_diagonal",
            attack_swing_right                = "attack_swing_right_diagonal",
            attack_swing_right_diagonal       = "attack_swing_right",
            parry_pose                        = "parry_pose",
            push_stab                         = "attack_swing_down",
        },
        -- v0.12.188-dev: Kerillian Dual Swords on SALTZPYRE body -> Dual Axe &
        -- Falchion (wh_-scoped redirect).
        wh_ = {
            attack_push                      = "attack_push",
            attack_swing_charge_diagonal     = "attack_swing_charge_down",
            attack_swing_charge_left         = "attack_swing_charge_left",
            attack_swing_charge_right        = "attack_swing_charge_down",
            attack_swing_heavy_left_diagonal = "attack_swing_heavy_down",
            attack_swing_heavy_right         = "attack_swing_heavy_left",
            attack_swing_left                = "attack_swing_heavy_down",
            attack_swing_left_diagonal       = "attack_swing_heavy_down",
            attack_swing_right               = "attack_swing_heavy_left",
            attack_swing_right_diagonal      = "attack_swing_heavy_left",
            parry_pose                       = "parry_pose",
            push_stab                        = "attack_swing_heavy_down",
        },
    },
    -- Warrior Priest Dual Skullsplitters (wh_dual_hammer) -> Empire Mace & Sword.
    dual_wield_hammers_priest_template = {
        wh_ = false, -- native (Saltzpyre / Warrior Priest): untouched
        es_ = {
            attack_push                        = "attack_push",
            attack_swing_charge_down           = "attack_swing_charge_left",
            attack_swing_charge_left           = "attack_swing_charge_left",
            attack_swing_charge_right          = "attack_swing_charge_right",
            attack_swing_down                  = "attack_swing_down",
            attack_swing_heavy_down            = "attack_swing_heavy_left_diagonal",
            attack_swing_heavy_left_diagonal   = "attack_swing_heavy_left_diagonal",
            attack_swing_heavy_right_diagonal  = "attack_swing_heavy_right_diagonal",
            attack_swing_left                  = "attack_swing_left",
            attack_swing_left_diagonal         = "attack_swing_left_diagonal",
            attack_swing_stab                  = "attack_swing_down",
            attack_swing_up                    = "attack_swing_right",
            parry_pose                         = "parry_pose",
        },
    },
    -- Warrior Priest Flail & Shield (wh_flail_shield) -> Empire Mace & Shield.
    one_handed_flail_shield_template = {
        wh_ = false, -- native (Saltzpyre / Warrior Priest): untouched
        es_ = {
            attack_push                     = "attack_push",
            attack_slam                     = "attack_swing_heavy",
            attack_swing_charge             = "attack_swing_charge_left_pose",
            attack_swing_charge_down_pose   = "attack_swing_charge_left_pose",
            attack_swing_charge_pose        = "attack_swing_charge_left_pose",
            attack_swing_down               = "attack_swing_down",
            attack_swing_down_right         = "attack_swing_down",
            attack_swing_heavy_down         = "attack_swing_down",
            attack_swing_heavy_left         = "attack_swing_heavy_left",
            attack_swing_left               = "attack_swing_heavy_left",
            attack_swing_left_diagonal      = "attack_swing_left",
            attack_swing_right_diagonal     = "attack_swing_right_diagonal",
            parry_pose                      = "parry_pose",
        },
    },
    -- ============================================================
    -- v0.12.188-dev: BAKED Kruber + Saltzpyre 3P picks for the latest
    -- [Needs Animations] cross-character ports.
    -- ============================================================
    -- Pulled verbatim from the user's persisted dev anim picker
    -- (user_settings(2).config) — the Kruber Sienna-staves/Rapier batch and the
    -- Saltzpyre melee + Sienna-staves batches. Same career-scoped pattern as the
    -- v0.12.149-.156 bakes: native owner prefix = false (owner plays UNTOUCHED);
    -- es_ is the Kruber-only redirect, wh_ the (non-WP) Saltzpyre redirect. The
    -- staff/Deus templates carry BOTH es_ and wh_ because the same Sienna source
    -- weapons are surfaced on both receiver bodies. 3P-only (consumed at the
    -- Unit.animation_event hook). Identity entries are harmless re-fires; the
    -- staves' `inspect_start` picks were deliberately NOT baked (the picker never
    -- remaps inspect — 2026-06-29 user decision — and never applied them).

    -- Saltzpyre's Rapier (wh_fencing_sword) -> Empire 1H Sword on Kruber (wield
    -- to_1h_sword on es_). wh_ = false → Saltzpyre/WP native plays UNTOUCHED.
    fencing_sword_template_1 = {
        wh_ = false, -- native (Saltzpyre / Warrior Priest): untouched
        es_ = {
            attack_push                 = "attack_push",
            attack_swing_left           = "attack_swing_left_diagonal",
            attack_swing_right          = "attack_swing_right",
            attack_swing_right_diagonal = "attack_swing_right_diagonal",
            attack_swing_stab           = "attack_swing_heavy_right",
            attack_swing_stab_charge    = "attack_swing_charge_right_pose",
            parry_pose                  = "parry_pose",
        },
    },

    -- Sienna's "Deus" staff (bw_deus_01) -> Empire Greathammer on Kruber (es_) /
    -- WP Greathammer on Saltzpyre (wh_). bw_ = false → Sienna native untouched.
    bw_deus_01_template_1 = {
        bw_ = false, -- native (Sienna): untouched
        es_ = {
            attack_geiser_placed  = "attack_swing_down_right",
            attack_geiser_start   = "attack_swing_charge_right",
            attack_shoot_fireball = "attack_swing_down_right",
            cooldown_start        = "parry_pose",
        },
        wh_ = {
            attack_geiser_placed  = "attack_swing_heavy_right",
            attack_geiser_start   = "attack_swing_charge_right",
            attack_shoot_fireball = "attack_swing_up",
            cooldown_start        = "parry_pose",
        },
    },

    -- Sienna's Necromancy / Soulstealer staff (bw_necromancy_staff, staff_death)
    -- -> Greathammer (es_ Kruber / wh_ Saltzpyre). bw_ = false → Sienna untouched.
    staff_death = {
        bw_ = false, -- native (Sienna / Necromancer): untouched
        es_ = {
            chain_attack    = "attack_swing_left",
            chain_attack_02 = "attack_swing_down_right",
            cooldown_start  = "parry_pose",
            soul_rip_attack = "attack_swing_heavy",
            soul_rip_pop    = "attack_swing_left",
            soul_rip_start  = "attack_swing_heavy_right",
        },
        wh_ = {
            chain_attack    = "attack_swing_heavy_right_diagonal",
            chain_attack_02 = "attack_swing_down_right",
            cooldown_start  = "attack_swing_heavy_right_diagonal",
            soul_rip_attack = "attack_swing_charge_right",
            soul_rip_pop    = "attack_swing_heavy_right",
            soul_rip_start  = "attack_swing_charge",
        },
    },

    -- Sienna's Beam staff (bw_skullstaff_beam) -> Greathammer (es_ / wh_).
    staff_blast_beam_template_1 = {
        bw_ = false, -- native (Sienna): untouched
        es_ = {
            attack_shoot_beam_spark   = "attack_push",
            attack_shoot_beam_start   = "parry_pose",
            attack_shoot_sparks       = "attack_swing_heavy",
            cooldown_start            = "parry_pose",
            flamethrower_charge_start = "parry_pose",
        },
        wh_ = {
            attack_shoot_beam_spark   = "attack_swing_down_right",
            attack_shoot_beam_start   = "parry_pose",
            attack_shoot_sparks       = "attack_swing_heavy_right_diagonal",
            cooldown_start            = "parry_pose",
            flamethrower_charge_start = "attack_swing_charge_right",
        },
    },

    -- Sienna's Fireball staff (bw_skullstaff_fireball) -> Greathammer (es_ / wh_).
    staff_fireball_fireball_template_1 = {
        bw_ = false, -- native (Sienna): untouched
        es_ = {
            attack_charge_fireball        = "attack_swing_charge_right",
            attack_shoot_fireball         = "attack_swing_down_right",
            attack_shoot_fireball_charged = "attack_swing_down_right",
            cooldown_start                = "parry_pose",
        },
        wh_ = {
            attack_charge_fireball        = "attack_swing_charge_right",
            attack_shoot_fireball         = "attack_swing_up",
            attack_shoot_fireball_charged = "attack_swing_heavy_right",
            cooldown_start                = "parry_pose",
        },
    },

    -- Sienna's Flamethrower staff (bw_skullstaff_flamethrower) -> Greathammer.
    staff_flamethrower_template = {
        bw_ = false, -- native (Sienna): untouched
        es_ = {
            attack_shoot_flamethrower         = "attack_swing_down_left",
            attack_shoot_flamethrower_charged = "attack_swing_down_left",
            cooldown_start                    = "parry_pose",
            flamethrower_charge_start         = "attack_swing_charge_left",
        },
        wh_ = {
            attack_shoot_flamethrower         = "attack_swing_up",
            attack_shoot_flamethrower_charged = "attack_swing_heavy_right",
            cooldown_start                    = "parry_pose",
            flamethrower_charge_start         = "attack_swing_charge_right",
        },
    },

    -- Sienna's Geiser staff (bw_skullstaff_geiser) -> Greathammer (es_ / wh_).
    staff_fireball_geiser_template_1 = {
        bw_ = false, -- native (Sienna): untouched
        es_ = {
            attack_geiser_placed  = "attack_swing_down_right",
            attack_geiser_start   = "attack_swing_charge_right",
            attack_shoot_fireball = "attack_swing_down_right",
            cooldown_start        = "parry_pose",
        },
        wh_ = {
            attack_geiser_placed  = "attack_swing_heavy_right",
            attack_geiser_start   = "attack_swing_charge_right",
            attack_shoot_fireball = "attack_swing_up",
            cooldown_start        = "parry_pose",
        },
    },

    -- Sienna's Spear/Spark staff (bw_skullstaff_spear) -> Greathammer (es_ / wh_).
    staff_spark_spear_template_1 = {
        bw_ = false, -- native (Sienna): untouched
        es_ = {
            attack_charge_spear        = "attack_swing_charge_right",
            attack_shoot_rapid_left    = "attack_swing_heavy",
            attack_shoot_rapid_right   = "attack_swing_heavy_right",
            attack_shoot_spear_charged = "attack_swing_down_right",
        },
        wh_ = {
            attack_charge_spear        = "attack_swing_charge_right",
            attack_shoot_rapid_left    = "attack_swing_down_right",
            attack_shoot_rapid_right   = "attack_swing_heavy_right_diagonal",
            attack_shoot_spear_charged = "attack_swing_heavy_right",
            cooldown_start             = "parry_pose",
        },
    },

    -- Kruber's Empire Mace & Sword (es_dual_wield_hammer_sword) on the SALTZPYRE
    -- body -> Dual Axe & Falchion (wh_). es_ = false → Kruber native untouched.
    dual_wield_hammer_sword_template = {
        es_ = false, -- native (Kruber): untouched
        wh_ = {
            attack_push                       = "attack_push",
            attack_swing_charge_left          = "attack_swing_charge_left",
            attack_swing_charge_right         = "attack_swing_charge_down",
            attack_swing_down                 = "attack_swing_right",
            attack_swing_heavy_left_diagonal  = "attack_swing_heavy_left",
            attack_swing_heavy_right_diagonal = "attack_swing_heavy_down",
            attack_swing_left                 = "attack_swing_right_diagonal",
            attack_swing_left_diagonal        = "attack_swing_down_left",
            attack_swing_right                = "attack_swing_right",
            attack_swing_right_diagonal       = "attack_swing_left_diagonal",
            parry_pose                        = "parry_pose",
        },
    },

    -- Kruber's Halberd (es_halberd) on the SALTZPYRE body -> Billhook (wh_).
    -- es_ = false → Kruber native untouched.
    two_handed_halberds_template_1 = {
        es_ = false, -- native (Kruber): untouched
        wh_ = {
            attack_push               = "attack_push",
            attack_swing_charge_left  = "attack_swing_charge_stab",
            attack_swing_charge_right = "attack_swing_charge_stab",
            attack_swing_down_left    = "attack_swing_left_diagonal",
            attack_swing_down_right   = "attack_swing_down",
            attack_swing_heavy        = "attack_swing_heavy_stab",
            attack_swing_heavy_right  = "attack_swing_heavy_down",
            attack_swing_right        = "attack_swing_stab",
            parry_pose                = "parry_pose",
        },
    },

    -- Kerillian's Spear (we_spear) on the SALTZPYRE body -> Billhook (wh_).
    -- we_ = false → Kerillian native untouched.
    two_handed_spears_elf_template_1 = {
        we_ = false, -- native (Kerillian): untouched
        wh_ = {
            attack_push                = "attack_push",
            -- #576: receiver-facing billhook anim_event_3p values. The former
            -- targets were 1P names and could yield no visible 3P transition.
            attack_swing_charge_left   = "attack_swing_stab_charge",
            attack_swing_charge_right  = "attack_swing_charge_left_diagonal",
            attack_swing_down_left     = "attack_swing_left_diagonal",
            attack_swing_down_left_axe = "attack_swing_stab",
            attack_swing_down_right    = "attack_swing_stab",
            attack_swing_heavy         = "attack_swing_heavy_left_diagonal",
            attack_swing_heavy_right   = "attack_swing_heavy_stab",
            attack_swing_right         = "attack_swing_stab",
            parry_pose                 = "parry_pose",
            push_stab                  = "attack_swing_left_diagonal",
        },
    },
}

do
    local R = _3p_template_remaps
    -- ============================================================
    -- BAKED tester 3P picks — FAITHFUL IMAGE of Downloads/user_settings(4).config
    -- (remote tester, 2026-07-03). Regenerated deterministically for ALL THREE
    -- receivers by scratchpad/gen_bake_v4.ps1:
    --   we_ = Kerillian (33 templates)  es_ = Kruber (21)  wh_ = Saltzpyre (20)
    -- WHY THIS EXISTS: v0.12.201 baked ONLY Kerillian (33) + 1 Kruber + 1 Saltzpyre,
    -- silently DROPPING ~30 Kruber/Saltzpyre event-picks the tester had tuned
    -- (billhook polearm, dual axes, crowbill, flaming flail, staves, ...). That is
    -- why non-Kerillian weapons T-posed on Kruber/Saltzpyre. This regen restores the
    -- full set. Kruber/Saltzpyre were tuned in the LEGACY template-qualified picker
    -- namespace; Kerillian in the CURRENT weapon-only one — merged per receiver
    -- (newer weapon-only value wins on the 1 conflict). we_ re-validated byte-for-byte
    -- identical to the v0.12.201 bake (338 pairs, 0 diff) so Kerillian is unchanged.
    -- Native owner prefix = false (owner plays UNTOUCHED); dual_wield_axes_template_1
    -- gets NO owner=false (Bardin remap is per-career). __unset__ picks omitted.
    -- ============================================================
    R.bastard_sword_template = R.bastard_sword_template or {}
    R.bastard_sword_template.es_ = R.bastard_sword_template.es_ or false
    R.bastard_sword_template.we_ = {
        attack_push                             = "attack_push",
        attack_swing_charge_down_pose           = "attack_swing_charge",
        attack_swing_charge_left_diagonal       = "attack_swing_charge",
        attack_swing_charge_left_diagonal_pose  = "attack_swing_charge",
        attack_swing_charge_right_diagonal_pose = "attack_swing_charge",
        attack_swing_down                       = "attack_swing_left",
        attack_swing_down_right                 = "attack_swing_heavy_right",
        attack_swing_heavy_down                 = "attack_swing_heavy",
        attack_swing_heavy_left_diagonal        = "attack_swing_left",
        attack_swing_heavy_right_diagonal       = "attack_swing_right",
        attack_swing_right                      = "attack_swing_right",
        attack_swing_up_left                    = "attack_swing_left",
        parry_pose                              = "parry_pose",
        swap_charge_stance                      = "attack_swing_charge",
    }
    -- ============================================================
    -- v0.12.213-dev (#519): Saltzpyre batch-2 BAKED — 10 of the 11 queued ports
    -- (es_2h_hammer, dr_2h_cog_hammer, dr_2h_pick, bw_1h_mace, bw_ghost_scythe,
    -- es_bastard_sword, es_mace_shield, es_sword_shield, es_sword_shield_breton,
    -- dr_shield_axe), pulled VERBATIM from the tester's persisted dev-picker picks
    -- (issue #519 user_settings.txt attachment). Both persistence namespaces were
    -- parsed per reference_wt_anim_picker_two_key_namespaces: all batch-2 picks
    -- live in the weapon-only namespace; the template-qualified namespace holds
    -- nothing new for these weapons. dr_dual_wield_hammers had ZERO non-unset
    -- picks in either namespace — NOT baked, stays queued in the picker.
    -- wh_ = the Saltzpyre-receiver redirect; every touched template already
    -- carries its native owner prefix = false. The wh_ tables are appended to the
    -- existing per-template entries below (alphabetical, same do-block).
    -- ============================================================
    R.bastard_sword_template.wh_ = {
        attack_push                             = "attack_push",
        attack_swing_charge_down_pose           = "attack_swing_charge_diagonal_right",
        attack_swing_charge_left_diagonal       = "attack_swing_charge_diagonal_left",
        attack_swing_charge_left_diagonal_pose  = "attack_swing_charge_diagonal_left",
        attack_swing_charge_right_diagonal_pose = "attack_swing_charge_diagonal_right",
        attack_swing_down                       = "attack_swing_down_right",
        attack_swing_down_right                 = "attack_swing_down_right",
        attack_swing_heavy_down                 = "attack_swing_down_right",
        attack_swing_heavy_left_diagonal        = "attack_swing_heavy_left_diagonal",
        attack_swing_heavy_right_diagonal       = "attack_swing_heavy_right_diagonal",
        attack_swing_right                      = "attack_swing_right_diagonal",
        attack_swing_up_left                    = "attack_swing_left_diagonal",
        parry_pose                              = "parry_pose",
        swap_charge_stance                      = "attack_swing_charge_diagonal",
    }
    R.bw_deus_01_template_1 = R.bw_deus_01_template_1 or {}
    R.bw_deus_01_template_1.bw_ = R.bw_deus_01_template_1.bw_ or false
    R.bw_deus_01_template_1.es_ = {
        attack_geiser_placed  = "attack_swing_down_right",
        attack_geiser_start   = "attack_swing_charge_right",
        attack_shoot_fireball = "attack_swing_down_right",
        cooldown_start        = "parry_pose",
        inspect_start         = "parry_pose",
    }
    R.bw_deus_01_template_1.we_ = {
        attack_geiser_placed  = "attack_swing_left",
        attack_geiser_start   = "attack_swing_charge_left",
        attack_shoot_fireball = "attack_swing_right",
        cooldown_start        = "parry_pose",
    }
    R.bw_deus_01_template_1.wh_ = {
        attack_geiser_placed  = "attack_swing_heavy_right",
        attack_geiser_start   = "attack_swing_charge_right",
        attack_shoot_fireball = "attack_swing_up",
        cooldown_start        = "parry_pose",
    }
    R.dual_wield_axe_falchion_template = R.dual_wield_axe_falchion_template or {}
    R.dual_wield_axe_falchion_template.wh_ = R.dual_wield_axe_falchion_template.wh_ or false
    R.dual_wield_axe_falchion_template.we_ = {
        attack_push                 = "attack_push",
        attack_swing_charge_down    = "attack_swing_charge",
        attack_swing_charge_left    = "attack_swing_charge_diagonal",
        attack_swing_down           = "attack_swing_right",
        attack_swing_down_left      = "attack_swing_stab",
        attack_swing_heavy_down     = "attack_swing_heavy",
        attack_swing_heavy_left     = "attack_swing_heavy_left_diagonal",
        attack_swing_left_diagonal  = "attack_swing_right_diagonal",
        attack_swing_right          = "attack_swing_right",
        attack_swing_right_diagonal = "attack_swing_left",
        parry_pose                  = "parry_pose",
    }
    R.dual_wield_axes_template_1 = R.dual_wield_axes_template_1 or {}
    R.dual_wield_axes_template_1.we_ = {
        attack_push                      = "attack_push",
        attack_swing_charge_diagonal     = "attack_swing_charge_right",
        attack_swing_charge_left         = "attack_swing_charge_left",
        attack_swing_charge_right        = "attack_swing_charge_right",
        attack_swing_down                = "attack_swing_left",
        attack_swing_heavy               = "attack_swing_heavy_right",
        attack_swing_heavy_left_diagonal = "attack_swing_heavy_left_diagonal",
        attack_swing_heavy_right         = "attack_swing_heavy_right",
        attack_swing_left                = "attack_swing_left",
        attack_swing_left_diagonal       = "attack_swing_left_diagonal",
        attack_swing_right               = "attack_swing_right",
        attack_swing_right_diagonal      = "attack_swing_right_diagonal",
        parry_pose                       = "parry_pose",
    }
    R.dual_wield_axes_template_1.wh_ = {
        attack_push                      = "attack_push",
        attack_swing_charge_diagonal     = "attack_swing_charge_down",
        attack_swing_charge_left         = "attack_swing_charge_left",
        attack_swing_charge_right        = "attack_swing_charge_down",
        attack_swing_down                = "attack_swing_heavy_down",
        attack_swing_heavy               = "attack_swing_heavy_left",
        attack_swing_heavy_left_diagonal = "attack_swing_heavy_down",
        attack_swing_heavy_right         = "attack_swing_heavy_down",
        attack_swing_left                = "attack_swing_down",
        attack_swing_left_diagonal       = "attack_swing_heavy_left",
        attack_swing_right               = "attack_swing_right",
        attack_swing_right_diagonal      = "attack_swing_right",
        parry_pose                       = "parry_pose",
    }
    R.dual_wield_daggers_template_1 = R.dual_wield_daggers_template_1 or {}
    R.dual_wield_daggers_template_1.we_ = R.dual_wield_daggers_template_1.we_ or false
    R.dual_wield_daggers_template_1.es_ = {
        attack_push               = "attack_push",
        attack_swing_charge       = "attack_swing_charge_left",
        attack_swing_charge_left  = "attack_swing_charge_right",
        attack_swing_charge_right = "attack_swing_charge_right",
        attack_swing_down_left    = "attack_swing_left",
        attack_swing_down_right   = "attack_swing_right",
        attack_swing_heavy        = "attack_swing_heavy_left_diagonal",
        attack_swing_heavy_down   = "attack_swing_heavy_right_diagonal",
        attack_swing_left         = "attack_swing_left_diagonal",
        attack_swing_right        = "attack_swing_right_diagonal",
        parry_pose                = "parry_pose",
        push_stab                 = "attack_swing_down",
    }
    R.dual_wield_daggers_template_1.wh_ = {
        attack_push               = "attack_push",
        attack_swing_charge       = "attack_swing_charge_down",
        attack_swing_charge_left  = "attack_swing_charge_left",
        attack_swing_charge_right = "attack_swing_charge_down",
        attack_swing_down_left    = "attack_swing_heavy_down",
        attack_swing_down_right   = "attack_swing_heavy_left",
        attack_swing_heavy        = "attack_swing_heavy_down",
        attack_swing_heavy_down   = "attack_swing_heavy_down",
        attack_swing_left         = "attack_swing_heavy_down",
        attack_swing_right        = "attack_swing_heavy_left",
        parry_pose                = "parry_pose",
        push_stab                 = "attack_swing_heavy_down",
    }
    R.dual_wield_hammer_sword_template = R.dual_wield_hammer_sword_template or {}
    R.dual_wield_hammer_sword_template.es_ = R.dual_wield_hammer_sword_template.es_ or false
    R.dual_wield_hammer_sword_template.we_ = {
        attack_push                       = "attack_push",
        attack_swing_charge_left          = "attack_swing_charge",
        attack_swing_charge_right         = "attack_swing_charge",
        attack_swing_down                 = "push_stab",
        attack_swing_heavy_left_diagonal  = "attack_swing_heavy",
        attack_swing_heavy_right_diagonal = "attack_swing_heavy",
        attack_swing_left                 = "attack_swing_heavy_left_diagonal",
        attack_swing_left_diagonal        = "attack_swing_left",
        attack_swing_right                = "attack_swing_right",
        attack_swing_right_diagonal       = "attack_swing_right_diagonal",
        parry_pose                        = "parry_pose",
    }
    R.dual_wield_hammer_sword_template.wh_ = {
        attack_push                       = "attack_push",
        attack_swing_charge_left          = "attack_swing_charge_left",
        attack_swing_charge_right         = "attack_swing_charge_down",
        attack_swing_down                 = "attack_swing_right",
        attack_swing_heavy_left_diagonal  = "attack_swing_heavy_left",
        attack_swing_heavy_right_diagonal = "attack_swing_heavy_down",
        attack_swing_left                 = "attack_swing_right_diagonal",
        attack_swing_left_diagonal        = "attack_swing_down_left",
        attack_swing_right                = "attack_swing_right",
        attack_swing_right_diagonal       = "attack_swing_left_diagonal",
        parry_pose                        = "parry_pose",
    }
    R.dual_wield_hammers_priest_template = R.dual_wield_hammers_priest_template or {}
    R.dual_wield_hammers_priest_template.wh_ = R.dual_wield_hammers_priest_template.wh_ or false
    R.dual_wield_hammers_priest_template.es_ = {
        attack_push                       = "attack_push",
        attack_swing_charge_down          = "attack_swing_charge_left",
        attack_swing_charge_left          = "attack_swing_charge_left",
        attack_swing_charge_right         = "attack_swing_charge_right",
        attack_swing_down                 = "attack_swing_down",
        attack_swing_heavy_down           = "attack_swing_heavy_left_diagonal",
        attack_swing_heavy_left_diagonal  = "attack_swing_heavy_left_diagonal",
        attack_swing_heavy_right_diagonal = "attack_swing_heavy_right_diagonal",
        attack_swing_left                 = "attack_swing_left",
        attack_swing_left_diagonal        = "attack_swing_left_diagonal",
        attack_swing_stab                 = "attack_swing_down",
        attack_swing_up                   = "attack_swing_right",
        parry_pose                        = "parry_pose",
    }
    R.dual_wield_hammers_priest_template.we_ = {
        attack_push                       = "attack_push",
        attack_swing_charge_down          = "attack_swing_charge_left",
        attack_swing_charge_left          = "attack_swing_charge_left",
        attack_swing_charge_right         = "attack_swing_charge_right",
        attack_swing_down                 = "attack_swing_right",
        attack_swing_heavy_down           = "attack_swing_heavy_left_diagonal",
        attack_swing_heavy_left_diagonal  = "attack_swing_heavy_left_diagonal",
        attack_swing_heavy_right_diagonal = "attack_swing_heavy_right",
        attack_swing_left                 = "attack_swing_left",
        attack_swing_left_diagonal        = "attack_swing_left_diagonal",
        attack_swing_stab                 = "push_stab",
        attack_swing_up                   = "attack_swing_right_diagonal",
        parry_pose                        = "parry_pose",
    }
    R.dual_wield_hammers_template = R.dual_wield_hammers_template or {}
    R.dual_wield_hammers_template.dr_ = R.dual_wield_hammers_template.dr_ or false
    R.dual_wield_hammers_template.we_ = {
        attack_push                       = "attack_push",
        attack_swing_charge_down          = "attack_swing_charge_left",
        attack_swing_charge_left          = "attack_swing_charge_left",
        attack_swing_charge_right         = "attack_swing_charge_right",
        attack_swing_down                 = "attack_swing_right",
        attack_swing_heavy_down           = "attack_swing_heavy_right",
        attack_swing_heavy_left_diagonal  = "attack_swing_heavy_left_diagonal",
        attack_swing_heavy_right_diagonal = "attack_swing_heavy_right",
        attack_swing_left                 = "attack_swing_left",
        attack_swing_left_diagonal        = "attack_swing_left",
        attack_swing_stab                 = "push_stab",
        attack_swing_up                   = "attack_swing_right",
        parry_pose                        = "parry_pose",
    }
    R.dual_wield_sword_dagger_template_1 = R.dual_wield_sword_dagger_template_1 or {}
    R.dual_wield_sword_dagger_template_1.we_ = R.dual_wield_sword_dagger_template_1.we_ or false
    R.dual_wield_sword_dagger_template_1.es_ = {
        attack_push                      = "attack_push",
        attack_swing_charge              = "attack_swing_charge_right",
        attack_swing_charge_diagonal     = "attack_swing_charge_left",
        attack_swing_charge_left         = "attack_swing_charge_right",
        attack_swing_heavy               = "attack_swing_heavy_right_diagonal",
        attack_swing_heavy_left_diagonal = "attack_swing_heavy_left_diagonal",
        attack_swing_left                = "attack_swing_left_diagonal",
        attack_swing_right               = "attack_swing_right_diagonal",
        attack_swing_right_diagonal      = "attack_swing_right",
        attack_swing_stab                = "attack_swing_down",
        parry_pose                       = "parry_pose",
        push_stab                        = "attack_swing_down",
    }
    R.dual_wield_sword_dagger_template_1.wh_ = {
        attack_push                      = "attack_push",
        attack_swing_charge              = "attack_swing_charge_down",
        attack_swing_charge_diagonal     = "attack_swing_charge_left",
        attack_swing_charge_left         = "attack_swing_charge_down",
        attack_swing_heavy               = "attack_swing_heavy_down",
        attack_swing_heavy_left_diagonal = "attack_swing_heavy_left",
        attack_swing_left                = "attack_swing_heavy_down",
        attack_swing_right               = "attack_swing_heavy_down",
        attack_swing_right_diagonal      = "attack_swing_heavy_left",
        attack_swing_stab                = "attack_swing_heavy_left",
        parry_pose                       = "parry_pose",
        push_stab                        = "attack_swing_heavy_down",
    }
    R.dual_wield_swords_template_1 = R.dual_wield_swords_template_1 or {}
    R.dual_wield_swords_template_1.we_ = R.dual_wield_swords_template_1.we_ or false
    R.dual_wield_swords_template_1.es_ = {
        attack_push                      = "attack_push",
        attack_swing_charge_diagonal     = "attack_swing_charge_left",
        attack_swing_charge_left         = "attack_swing_charge_right",
        attack_swing_charge_right        = "attack_swing_charge_left",
        attack_swing_heavy_left_diagonal = "attack_swing_heavy_left_diagonal",
        attack_swing_heavy_right         = "attack_swing_heavy_right_diagonal",
        attack_swing_left                = "attack_swing_left",
        attack_swing_left_diagonal       = "attack_swing_left_diagonal",
        attack_swing_right               = "attack_swing_right_diagonal",
        attack_swing_right_diagonal      = "attack_swing_right",
        parry_pose                       = "parry_pose",
        push_stab                        = "attack_swing_down",
    }
    R.dual_wield_swords_template_1.wh_ = {
        attack_push                      = "attack_push",
        attack_swing_charge_diagonal     = "attack_swing_charge_down",
        attack_swing_charge_left         = "attack_swing_charge_left",
        attack_swing_charge_right        = "attack_swing_charge_down",
        attack_swing_heavy_left_diagonal = "attack_swing_heavy_down",
        attack_swing_heavy_right         = "attack_swing_heavy_left",
        attack_swing_left                = "attack_swing_heavy_down",
        attack_swing_left_diagonal       = "attack_swing_heavy_down",
        attack_swing_right               = "attack_swing_heavy_left",
        attack_swing_right_diagonal      = "attack_swing_heavy_left",
        parry_pose                       = "parry_pose",
        push_stab                        = "attack_swing_heavy_down",
    }
    R.fencing_sword_template_1 = R.fencing_sword_template_1 or {}
    R.fencing_sword_template_1.wh_ = R.fencing_sword_template_1.wh_ or false
    R.fencing_sword_template_1.es_ = {
        attack_push                 = "attack_push",
        attack_swing_left           = "attack_swing_left_diagonal",
        attack_swing_right          = "attack_swing_right",
        attack_swing_right_diagonal = "attack_swing_right_diagonal",
        attack_swing_stab           = "attack_swing_heavy_right",
        attack_swing_stab_charge    = "attack_swing_charge_right_pose",
        parry_pose                  = "parry_pose",
    }
    R.fencing_sword_template_1.we_ = {
        attack_push                 = "attack_swing_heavy_down_right",
        attack_shoot                = "attack_push",
        attack_swing_left           = "attack_swing_left",
        attack_swing_right          = "attack_swing_right_diagonal",
        attack_swing_right_diagonal = "attack_swing_right_diagonal",
        attack_swing_stab           = "attack_swing_stab",
        attack_swing_stab_charge    = "attack_swing_charge_down",
        front_idle_exit             = "attack_swing_left",
        parry_pose                  = "parry_pose",
    }
    R.flaming_sword_template_1 = R.flaming_sword_template_1 or {}
    R.flaming_sword_template_1.bw_ = R.flaming_sword_template_1.bw_ or false
    R.flaming_sword_template_1.we_ = {
        attack_push                 = "attack_push",
        attack_swing_charge         = "attack_swing_charge_down",
        attack_swing_charge_right   = "attack_swing_charge_down",
        attack_swing_heavy          = "attack_swing_heavy_down_right",
        attack_swing_left           = "attack_swing_left",
        attack_swing_left_diagonal  = "attack_swing_left_diagonal",
        attack_swing_right_diagonal = "attack_swing_right_diagonal",
        attack_swing_right_spell    = "attack_swing_heavy_left_up",
        attack_swing_stab           = "attack_swing_stab",
        parry_pose                  = "parry_pose",
    }
    R.flaming_sword_template_1.wh_ = {
        attack_push                 = "attack_push",
        attack_swing_charge         = "attack_swing_charge_left_diagonal_pose",
        attack_swing_charge_right   = "attack_swing_charge_right_diagonal_pose",
        attack_swing_heavy          = "attack_swing_heavy_left_diagonal",
        attack_swing_left           = "attack_swing_left_diagonal",
        attack_swing_left_diagonal  = "attack_swing_left_diagonal",
        attack_swing_right_diagonal = "attack_swing_right_diagonal",
        attack_swing_right_spell    = "attack_swing_up",
        attack_swing_stab           = "attack_swing_down",
        parry_pose                  = "parry_pose",
    }
    R.one_hand_axe_shield_template_1 = R.one_hand_axe_shield_template_1 or {}
    R.one_hand_axe_shield_template_1.dr_ = R.one_hand_axe_shield_template_1.dr_ or false
    R.one_hand_axe_shield_template_1.we_ = {
        attack_push                            = "attack_push",
        attack_swing_charge                    = "attack_swing_charge_left",
        attack_swing_charge_left_diagonal_pose = "attack_swing_charge_stab",
        attack_swing_charge_left_pose          = "attack_swing_charge_left",
        attack_swing_charge_right_pose         = "attack_swing_charge_right_diagonal_pose",
        attack_swing_down                      = "attack_swing_heavy_left",
        attack_swing_heavy                     = "attack_swing_heavy_stab",
        attack_swing_heavy_down                = "attack_swing_heavy_left",
        attack_swing_heavy_right               = "attack_swing_heavy_down_right",
        attack_swing_left_diagonal             = "attack_swing_heavy_left",
        attack_swing_right_diagonal            = "attack_swing_heavy_down_right",
        attack_swing_up_left                   = "attack_swing_heavy_left",
        parry_pose                             = "parry_pose",
    }
    -- #576: dr_shield_axe / CWV Empire Axe+Shield on Saltzpyre ->
    -- Dual Axe & Falchion.  Preserve the receiver SM's native two-heavy
    -- cadence across the donor's three-heavy chain:
    --
    --   donor H1 shield slam -> receiver H1 overhead
    --   donor H2 right sweep -> receiver H2 left sweep
    --   donor H3 overhead    -> receiver H1 overhead (cycle restart)
    --
    -- The previous table sent both H1 and H2 to the receiver H1 event.  That
    -- left the body in the wrong chain state; H3's charge could play, but its
    -- release had no reachable transition.  Charges and releases below are
    -- deliberately paired -- do not validate this chain from event presence
    -- alone.
    R.one_hand_axe_shield_template_1.wh_ = {
        attack_push                            = "attack_push",
        attack_swing_charge                    = "attack_swing_charge_down",
        attack_swing_charge_left_diagonal_pose = "attack_swing_charge_down",
        attack_swing_charge_left_pose          = "attack_swing_charge_left",
        attack_swing_charge_right_pose         = "attack_swing_charge_left",
        attack_swing_down                      = "attack_swing_down_left",
        attack_swing_heavy                     = "attack_swing_heavy_down",
        attack_swing_heavy_down                = "attack_swing_heavy_down",
        attack_swing_heavy_right               = "attack_swing_heavy_left",
        attack_swing_left_diagonal             = "attack_swing_down_left",
        attack_swing_right_diagonal            = "attack_swing_right",
        attack_swing_up_left                   = "attack_swing_right",
        parry_pose                             = "parry_pose",
    }
    R.one_handed_crowbill = R.one_handed_crowbill or {}
    R.one_handed_crowbill.bw_ = R.one_handed_crowbill.bw_ or false
    R.one_handed_crowbill.es_ = {
        attack_swing_up_left = "attack_swing_left",
    }
    R.one_handed_crowbill.wh_ = {
        attack_swing_up_left = "attack_swing_left",
    }
    R.one_handed_daggers_template_1 = R.one_handed_daggers_template_1 or {}
    R.one_handed_daggers_template_1.bw_ = R.one_handed_daggers_template_1.bw_ or false
    R.one_handed_daggers_template_1.we_ = {
        attack_push                 = "attack_push",
        attack_swing_charge         = "attack_swing_charge_right_diagonal_pose",
        attack_swing_charge_left    = "attack_swing_charge_down",
        attack_swing_heavy          = "attack_swing_heavy_left_up",
        attack_swing_heavy_right    = "attack_swing_heavy_down_right",
        attack_swing_left           = "attack_swing_left",
        attack_swing_left_diagonal  = "attack_swing_left_diagonal",
        attack_swing_right_diagonal = "attack_swing_right_diagonal",
        attack_swing_stab           = "attack_swing_stab",
        parry_pose                  = "parry_pose",
    }
    R.one_handed_daggers_template_1.wh_ = {
        attack_push                 = "attack_push",
        attack_swing_charge         = "attack_swing_charge_left_diagonal_pose",
        attack_swing_charge_left    = "attack_swing_charge_right_diagonal_pose",
        attack_swing_heavy          = "attack_swing_heavy_left_diagonal",
        attack_swing_heavy_right    = "attack_swing_heavy_right_diagonal",
        attack_swing_left           = "attack_swing_left_diagonal",
        attack_swing_left_diagonal  = "attack_swing_left_diagonal",
        attack_swing_right_diagonal = "attack_swing_right_diagonal",
        attack_swing_stab           = "attack_swing_heavy_left_diagonal",
        parry_pose                  = "parry_pose",
    }
    R.one_handed_flail_shield_template = R.one_handed_flail_shield_template or {}
    R.one_handed_flail_shield_template.wh_ = R.one_handed_flail_shield_template.wh_ or false
    R.one_handed_flail_shield_template.es_ = {
        attack_push                   = "attack_push",
        attack_slam                   = "attack_swing_heavy",
        attack_swing_charge           = "attack_swing_charge_left_pose",
        attack_swing_charge_down_pose = "attack_swing_charge_left_pose",
        attack_swing_charge_pose      = "attack_swing_charge_left_pose",
        attack_swing_down             = "attack_swing_down",
        attack_swing_down_right       = "attack_swing_down",
        attack_swing_heavy_down       = "attack_swing_down",
        attack_swing_heavy_left       = "attack_swing_heavy_left",
        attack_swing_left             = "attack_swing_heavy_left",
        attack_swing_left_diagonal    = "attack_swing_left",
        attack_swing_right_diagonal   = "attack_swing_right_diagonal",
        parry_pose                    = "parry_pose",
    }
    R.one_handed_flail_shield_template.we_ = {
        attack_push                   = "attack_push",
        attack_slam                   = "push_stab",
        attack_swing_charge           = "attack_swing_charge_stab",
        attack_swing_charge_down_pose = "attack_swing_charge_stab",
        attack_swing_charge_pose      = "attack_swing_charge_stab",
        attack_swing_down             = "attack_swing_heavy_left",
        attack_swing_down_right       = "attack_swing_heavy_down_right",
        attack_swing_heavy_down       = "attack_swing_heavy_left",
        attack_swing_heavy_left       = "attack_swing_heavy_left",
        attack_swing_left             = "attack_swing_heavy_left",
        attack_swing_left_diagonal    = "attack_swing_heavy_left",
        attack_swing_right_diagonal   = "attack_swing_heavy_down_right",
        parry_pose                    = "parry_pose",
    }
    R.one_handed_flails_flaming_template = R.one_handed_flails_flaming_template or {}
    R.one_handed_flails_flaming_template.bw_ = R.one_handed_flails_flaming_template.bw_ or false
    R.one_handed_flails_flaming_template.es_ = {
        attack_swing_charge     = "attack_swing_charge_left",
        attack_swing_down_right = "attack_swing_right_diagonal",
        attack_swing_left       = "attack_swing_left_diagonal",
        attack_swing_right      = "attack_swing_right_diagonal",
    }
    R.one_handed_flails_flaming_template.we_ = {
        attack_push                 = "attack_push",
        attack_swing_charge         = "attack_swing_charge_right_diagonal_pose",
        attack_swing_charge_down    = "attack_swing_charge_down",
        attack_swing_down_right     = "attack_swing_heavy_down_right",
        attack_swing_heavy_down     = "attack_swing_heavy_down",
        attack_swing_heavy_left     = "attack_swing_heavy_left_up",
        attack_swing_left           = "attack_swing_left_diagonal",
        attack_swing_left_diagonal  = "attack_swing_left_diagonal",
        attack_swing_right          = "attack_swing_heavy_down_right",
        attack_swing_right_diagonal = "attack_swing_right_diagonal",
        parry_pose                  = "parry_pose",
    }
    R.one_handed_hammer_book_priest_template = R.one_handed_hammer_book_priest_template or {}
    R.one_handed_hammer_book_priest_template.wh_ = R.one_handed_hammer_book_priest_template.wh_ or false
    R.one_handed_hammer_book_priest_template.es_ = {
        attack_push                       = "attack_push",
        attack_swing_charge_left_diagonal = "attack_swing_charge_left_diagonal_pose",
        attack_swing_charge_stab          = "attack_swing_charge_right_diagonal_pose",
        attack_swing_heavy_left_diagonal  = "attack_swing_heavy_down",
        attack_swing_heavy_stab           = "attack_swing_heavy_down_right",
        attack_swing_left_diagonal        = "attack_swing_left_diagonal",
        attack_swing_left_diagonal_last   = "attack_swing_left_diagonal_last",
        attack_swing_right_diagonal       = "attack_swing_right_diagonal",
        attack_swing_right_diagonal_axe   = "attack_swing_right_diagonal",
        attack_swing_stab                 = "attack_swing_right",
        attack_swing_up_left              = "attack_swing_left_diagonal",
        parry_pose                        = "parry_pose",
        spell_pose                        = "attack_swing_right",
    }
    R.one_handed_hammer_book_priest_template.we_ = {
        attack_push                       = "attack_push",
        attack_swing_charge_left_diagonal = "attack_swing_charge_left",
        attack_swing_charge_stab          = "attack_swing_charge_stab",
        attack_swing_heavy_left_diagonal  = "attack_swing_heavy_stab",
        attack_swing_heavy_stab           = "attack_swing_stab",
        attack_swing_left_diagonal        = "attack_swing_heavy_left",
        attack_swing_left_diagonal_last   = "attack_swing_heavy_left",
        attack_swing_right_diagonal       = "attack_swing_heavy_down_right",
        attack_swing_right_diagonal_axe   = "attack_swing_heavy_down_right",
        attack_swing_stab                 = "push_stab",
        attack_swing_up_left              = "attack_swing_heavy_left",
        parry_pose                        = "parry_pose",
        spell_pose                        = "attack_push",
    }
    R.one_handed_hammer_priest_template = R.one_handed_hammer_priest_template or {}
    R.one_handed_hammer_priest_template.wh_ = R.one_handed_hammer_priest_template.wh_ or false
    R.one_handed_hammer_priest_template.we_ = {
        attack_push                             = "attack_push",
        attack_swing_charge_left_diagonal       = "attack_swing_charge_left_diagonal",
        attack_swing_charge_left_diagonal_pose  = "attack_swing_charge_left_diagonal_pose",
        attack_swing_charge_right_diagonal_pose = "attack_swing_charge_right_diagonal_pose",
        attack_swing_down_right                 = "attack_swing_right",
        attack_swing_heavy_down                 = "attack_swing_heavy_down",
        attack_swing_heavy_down_right           = "attack_swing_heavy_down_right",
        attack_swing_left_diagonal              = "attack_swing_left",
        attack_swing_left_diagonal_last         = "attack_swing_left",
        attack_swing_right                      = "attack_swing_right",
        attack_swing_right_diagonal             = "attack_swing_right",
        parry_pose                              = "parry_pose",
    }
    R.one_handed_hammer_shield_priest_template = R.one_handed_hammer_shield_priest_template or {}
    R.one_handed_hammer_shield_priest_template.wh_ = R.one_handed_hammer_shield_priest_template.wh_ or false
    R.one_handed_hammer_shield_priest_template.we_ = {
        attack_push                   = "attack_push",
        attack_swing_charge           = "attack_swing_charge_stab",
        attack_swing_charge_left_pose = "attack_swing_charge_left",
        attack_swing_charge_pose      = "attack_swing_charge_stab",
        attack_swing_down             = "attack_swing_heavy_left",
        attack_swing_heavy            = "attack_swing_heavy_stab",
        attack_swing_heavy_left       = "attack_swing_heavy_left",
        attack_swing_left             = "attack_swing_heavy_left",
        attack_swing_right_diagonal   = "attack_swing_heavy_down_right",
        attack_swing_up_left          = "attack_swing_heavy_left",
        parry_pose                    = "parry_pose",
    }
    R.one_handed_hammer_shield_template_1 = R.one_handed_hammer_shield_template_1 or {}
    R.one_handed_hammer_shield_template_1.es_ = R.one_handed_hammer_shield_template_1.es_ or false
    R.one_handed_hammer_shield_template_1.we_ = {
        attack_push                   = "attack_push",
        attack_swing_charge           = "attack_swing_charge_right_diagonal_pose",
        attack_swing_charge_left_pose = "attack_swing_charge_left",
        attack_swing_charge_pose      = "attack_swing_charge_stab",
        attack_swing_down             = "push_stab",
        attack_swing_heavy            = "attack_swing_heavy_stab",
        attack_swing_heavy_left       = "attack_swing_heavy_left",
        attack_swing_left             = "attack_swing_heavy_left",
        attack_swing_right_diagonal   = "attack_swing_heavy_down_right",
        attack_swing_up_left          = "attack_swing_heavy_left",
        parry_pose                    = "parry_pose",
    }
    -- v0.12.213-dev (#519): es_mace_shield on Saltzpyre -> Dual Axe & Falchion.
    R.one_handed_hammer_shield_template_1.wh_ = {
        attack_push                   = "attack_push",
        attack_swing_charge           = "attack_swing_charge_down",
        attack_swing_charge_left_pose = "attack_swing_charge_left",
        attack_swing_charge_pose      = "attack_swing_charge_down",
        attack_swing_down             = "attack_swing_down",
        attack_swing_heavy            = "attack_swing_heavy_down",
        attack_swing_heavy_left       = "attack_swing_heavy_left",
        attack_swing_left             = "attack_swing_heavy_left",
        attack_swing_right_diagonal   = "attack_swing_heavy_down",
        attack_swing_up_left          = "attack_swing_down_left",
        parry_pose                    = "parry_pose",
    }
    R.one_handed_hammer_template_2 = R.one_handed_hammer_template_2 or {}
    R.one_handed_hammer_template_2.dr_ = R.one_handed_hammer_template_2.dr_ or false
    R.one_handed_hammer_template_2.we_ = {
        attack_push                             = "attack_push",
        attack_swing_charge_left_diagonal       = "attack_swing_charge_left_diagonal",
        attack_swing_charge_left_diagonal_pose  = "attack_swing_charge_left_diagonal_pose",
        attack_swing_charge_right_diagonal_pose = "attack_swing_charge_right_diagonal_pose",
        attack_swing_down_right                 = "attack_swing_right",
        attack_swing_heavy_down                 = "attack_swing_heavy_down",
        attack_swing_heavy_down_right           = "attack_swing_heavy_down_right",
        attack_swing_left_diagonal              = "attack_swing_left",
        attack_swing_left_diagonal_last         = "attack_swing_left",
        attack_swing_right                      = "attack_swing_right",
        attack_swing_right_diagonal             = "attack_swing_right",
        parry_pose                              = "parry_pose",
    }
    -- v0.12.213-dev (#519): bw_1h_mace on Saltzpyre -> WP Greathammer. The
    -- literal entry above carries bw_ = false + the Kruber es_ bake (v0.12.150).
    R.one_handed_hammer_wizard_template_1 = R.one_handed_hammer_wizard_template_1 or {}
    R.one_handed_hammer_wizard_template_1.bw_ = R.one_handed_hammer_wizard_template_1.bw_ or false
    R.one_handed_hammer_wizard_template_1.wh_ = {
        attack_push                       = "attack_push",
        attack_swing_charge_left_diagonal = "attack_swing_charge_right_down",
        attack_swing_charge_left_pose     = "attack_swing_charge",
        attack_swing_charge_right_pose    = "attack_swing_charge_right",
        attack_swing_down                 = "attack_swing_down_right",
        attack_swing_heavy_down           = "attack_swing_heavy_right_diagonal",
        attack_swing_heavy_left_up        = "attack_swing_heavy_right",
        attack_swing_heavy_right_up       = "attack_swing_heavy_right",
        attack_swing_left                 = "attack_swing_left",
        attack_swing_left_diagonal        = "attack_swing_left",
        attack_swing_left_diagonal_last   = "attack_swing_up_left",
        attack_swing_right_diagonal       = "attack_swing_up",
        parry_pose                        = "parry_pose",
    }
    R.one_handed_sword_shield_template_1 = R.one_handed_sword_shield_template_1 or {}
    R.one_handed_sword_shield_template_1.es_ = R.one_handed_sword_shield_template_1.es_ or false
    R.one_handed_sword_shield_template_1.we_ = {
        attack_push                    = "attack_push",
        attack_swing_charge            = "attack_swing_charge_left",
        attack_swing_charge_right_pose = "attack_swing_charge_right_diagonal_pose",
        attack_swing_charge_stab       = "attack_swing_charge_stab",
        attack_swing_heavy             = "attack_swing_heavy_left",
        attack_swing_heavy_right       = "attack_swing_heavy_down_right",
        attack_swing_heavy_stab        = "attack_swing_heavy_stab",
        attack_swing_left              = "attack_swing_heavy_left",
        attack_swing_left_diagonal     = "attack_swing_heavy_left",
        attack_swing_right_diagonal    = "attack_swing_heavy_down_right",
        attack_swing_stab              = "push_stab",
        parry_pose                     = "parry_pose",
    }
    -- v0.12.213-dev (#519): es_sword_shield on Saltzpyre -> Dual Axe & Falchion.
    R.one_handed_sword_shield_template_1.wh_ = {
        attack_push                    = "attack_push",
        attack_swing_charge            = "attack_swing_charge_left",
        attack_swing_charge_right_pose = "attack_swing_charge_left",
        attack_swing_charge_stab       = "attack_swing_charge_down",
        attack_swing_heavy             = "attack_swing_heavy_left",
        attack_swing_heavy_right       = "attack_swing_heavy_left",
        attack_swing_heavy_stab        = "attack_swing_heavy_down",
        attack_swing_left              = "attack_swing_down_left",
        attack_swing_left_diagonal     = "attack_swing_heavy_left",
        attack_swing_right_diagonal    = "attack_swing_heavy_down",
        attack_swing_stab              = "attack_swing_heavy_down",
        parry_pose                     = "parry_pose",
    }
    R.one_handed_sword_shield_template_2 = R.one_handed_sword_shield_template_2 or {}
    R.one_handed_sword_shield_template_2.es_ = R.one_handed_sword_shield_template_2.es_ or false
    R.one_handed_sword_shield_template_2.we_ = {
        attack_push                       = "attack_push",
        attack_swing_charge               = "attack_swing_charge_right_diagonal_pose",
        attack_swing_charge_left_diagonal = "attack_swing_charge_left",
        attack_swing_charge_stab          = "attack_swing_charge_stab",
        attack_swing_down_right           = "attack_swing_heavy_left",
        attack_swing_heavy                = "attack_swing_heavy_left",
        attack_swing_heavy_breton         = "attack_swing_stab_lh",
        attack_swing_heavy_down           = "attack_swing_heavy_down_right",
        attack_swing_heavy_stab           = "attack_swing_heavy_stab",
        attack_swing_stab                 = "attack_swing_stab",
        attack_swing_up_left              = "attack_swing_heavy_down_right",
        parry_pose                        = "parry_pose",
    }
    -- v0.12.213-dev (#519): es_sword_shield_breton on Saltzpyre -> Dual Axe & Falchion.
    R.one_handed_sword_shield_template_2.wh_ = {
        attack_push                       = "attack_push",
        attack_swing_charge               = "attack_swing_charge_left",
        attack_swing_charge_left_diagonal = "attack_swing_charge_down",
        attack_swing_charge_stab          = "attack_swing_charge_down",
        attack_swing_down_right           = "attack_swing_heavy_down",
        attack_swing_heavy                = "attack_swing_heavy_left",
        attack_swing_heavy_breton         = "attack_swing_right_diagonal",
        attack_swing_heavy_down           = "attack_swing_heavy_down",
        attack_swing_heavy_stab           = "attack_swing_heavy_down",
        attack_swing_stab                 = "attack_swing_heavy_down",
        attack_swing_up_left              = "attack_swing_heavy_left",
        parry_pose                        = "parry_pose",
    }
    R.one_handed_throwing_axes_template = R.one_handed_throwing_axes_template or {}
    R.one_handed_throwing_axes_template.dr_ = R.one_handed_throwing_axes_template.dr_ or false
    R.one_handed_throwing_axes_template.we_ = {
        attack_throw = "attack_swing_up",
        reload       = "attack_throw",
        reload_last  = "attack_throw",
        throw_charge = "throw_charge",
    }
    R.staff_blast_beam_template_1 = R.staff_blast_beam_template_1 or {}
    R.staff_blast_beam_template_1.bw_ = R.staff_blast_beam_template_1.bw_ or false
    R.staff_blast_beam_template_1.es_ = {
        attack_shoot_beam_spark   = "attack_push",
        attack_shoot_beam_start   = "parry_pose",
        attack_shoot_sparks       = "attack_swing_heavy",
        cooldown_start            = "parry_pose",
        flamethrower_charge_start = "parry_pose",
        inspect_start             = "attack_swing_heavy",
    }
    R.staff_blast_beam_template_1.we_ = {
        attack_shoot_beam_spark   = "attack_swing_heavy_down",
        attack_shoot_beam_start   = "attack_swing_left",
        attack_shoot_sparks       = "attack_swing_heavy_left",
        cooldown_start            = "parry_pose",
        flamethrower_charge_start = "attack_swing_right",
    }
    R.staff_blast_beam_template_1.wh_ = {
        attack_shoot_beam_spark   = "attack_swing_down_right",
        attack_shoot_beam_start   = "parry_pose",
        attack_shoot_sparks       = "attack_swing_heavy_right_diagonal",
        cooldown_start            = "parry_pose",
        flamethrower_charge_start = "attack_swing_charge_right",
    }
    R.staff_death = R.staff_death or {}
    R.staff_death.bw_ = R.staff_death.bw_ or false
    R.staff_death.es_ = {
        chain_attack    = "attack_swing_left",
        chain_attack_02 = "attack_swing_down_right",
        cooldown_start  = "parry_pose",
        soul_rip_attack = "attack_swing_heavy",
        soul_rip_pop    = "attack_swing_left",
        soul_rip_start  = "attack_swing_heavy_right",
    }
    R.staff_death.we_ = {
        chain_attack    = "attack_swing_left",
        chain_attack_02 = "attack_swing_right",
        cooldown_start  = "parry_pose",
        soul_rip_attack = "attack_swing_charge_left",
        soul_rip_pop    = "attack_swing_left",
        soul_rip_start  = "attack_swing_right",
    }
    R.staff_death.wh_ = {
        chain_attack    = "attack_swing_heavy_right_diagonal",
        chain_attack_02 = "attack_swing_down_right",
        cooldown_start  = "attack_swing_heavy_right_diagonal",
        soul_rip_attack = "attack_swing_charge_right",
        soul_rip_pop    = "attack_swing_heavy_right",
        soul_rip_start  = "attack_swing_charge",
    }
    R.staff_fireball_fireball_template_1 = R.staff_fireball_fireball_template_1 or {}
    R.staff_fireball_fireball_template_1.bw_ = R.staff_fireball_fireball_template_1.bw_ or false
    R.staff_fireball_fireball_template_1.es_ = {
        attack_charge_fireball        = "attack_swing_charge_right",
        attack_shoot_fireball         = "attack_swing_down_right",
        attack_shoot_fireball_charged = "attack_swing_down_right",
        cooldown_start                = "parry_pose",
        inspect_start                 = "parry_pose",
    }
    R.staff_fireball_fireball_template_1.we_ = {
        attack_charge_fireball        = "attack_swing_charge_left",
        attack_shoot_fireball         = "attack_swing_right",
        attack_shoot_fireball_charged = "attack_swing_left",
        cooldown_start                = "parry_pose",
    }
    R.staff_fireball_fireball_template_1.wh_ = {
        attack_charge_fireball        = "attack_swing_charge_right",
        attack_shoot_fireball         = "attack_swing_up",
        attack_shoot_fireball_charged = "attack_swing_heavy_right",
        cooldown_start                = "parry_pose",
    }
    R.staff_fireball_geiser_template_1 = R.staff_fireball_geiser_template_1 or {}
    R.staff_fireball_geiser_template_1.bw_ = R.staff_fireball_geiser_template_1.bw_ or false
    R.staff_fireball_geiser_template_1.es_ = {
        attack_geiser_placed  = "attack_swing_down_right",
        attack_geiser_start   = "attack_swing_charge_right",
        attack_shoot_fireball = "attack_swing_down_right",
        cooldown_start        = "parry_pose",
        inspect_start         = "parry_pose",
    }
    R.staff_fireball_geiser_template_1.we_ = {
        attack_geiser_placed  = "attack_swing_left",
        attack_geiser_start   = "attack_swing_charge_left",
        attack_shoot_fireball = "attack_swing_right",
        cooldown_start        = "parry_pose",
    }
    R.staff_fireball_geiser_template_1.wh_ = {
        attack_geiser_placed  = "attack_swing_heavy_right",
        attack_geiser_start   = "attack_swing_charge_right",
        attack_shoot_fireball = "attack_swing_up",
        cooldown_start        = "parry_pose",
    }
    R.staff_flamethrower_template = R.staff_flamethrower_template or {}
    R.staff_flamethrower_template.bw_ = R.staff_flamethrower_template.bw_ or false
    R.staff_flamethrower_template.es_ = {
        attack_shoot_flamethrower         = "attack_swing_down_left",
        attack_shoot_flamethrower_charged = "attack_swing_down_left",
        cooldown_start                    = "parry_pose",
        flamethrower_charge_start         = "attack_swing_charge_left",
        inspect_start                     = "parry_pose",
    }
    R.staff_flamethrower_template.we_ = {
        attack_shoot_flamethrower         = "attack_swing_right",
        attack_shoot_flamethrower_charged = "attack_swing_left",
        cooldown_start                    = "parry_pose",
        flamethrower_charge_start         = "attack_swing_charge_left",
    }
    R.staff_flamethrower_template.wh_ = {
        attack_shoot_flamethrower         = "attack_swing_up",
        attack_shoot_flamethrower_charged = "attack_swing_heavy_right",
        cooldown_start                    = "parry_pose",
        flamethrower_charge_start         = "attack_swing_charge_right",
    }
    R.staff_scythe = R.staff_scythe or {}
    R.staff_scythe.bw_ = R.staff_scythe.bw_ or false
    R.staff_scythe.we_ = {
        attack_push                       = "attack_push",
        attack_swing_charge_left          = "attack_swing_charge_left",
        attack_swing_charge_left_diagonal = "attack_swing_charge_left",
        attack_swing_charge_right         = "attack_swing_charge_down",
        attack_swing_heavy                = "attack_swing_heavy_down",
        attack_swing_heavy_left_diagonal  = "attack_swing_heavy_left",
        attack_swing_heavy_right          = "attack_swing_heavy_down",
        attack_swing_left                 = "attack_swing_left",
        attack_swing_left_diagonal        = "attack_swing_left_diagonal",
        attack_swing_left_diagonal_last   = "attack_swing_heavy_left",
        attack_swing_right                = "attack_swing_right",
        attack_swing_up_right             = "attack_swing_right",
        parry_pose                        = "parry_pose",
        special_action                    = "attack_swing_heavy_left",
        special_action_02                 = "attack_swing_heavy_down",
    }
    -- #576: source-chain candidate against staff_scythe.lua and
    -- 2h_hammers_priest.lua. Preserve distinct H1/H2/H3 roles; picker remains
    -- open because this table is not proof of visible playback.
    R.staff_scythe.wh_ = {
        attack_push                       = "attack_push",
        attack_swing_charge_left          = "attack_swing_charge_right",
        attack_swing_charge_left_diagonal = "attack_swing_charge_right_down",
        attack_swing_charge_right         = "attack_swing_charge",
        attack_swing_heavy                = "attack_swing_up",
        attack_swing_heavy_left_diagonal  = "attack_swing_heavy_right_diagonal",
        attack_swing_heavy_right          = "attack_swing_heavy_right",
        attack_swing_left                 = "attack_swing_left",
        attack_swing_left_diagonal        = "attack_swing_down_right",
        attack_swing_left_diagonal_last   = "attack_swing_left",
        attack_swing_right                = "attack_swing_down_right",
        attack_swing_up_right             = "attack_swing_up_left",
        parry_pose                        = "parry_pose",
        special_action                    = "attack_swing_charge_right",
        special_action_02                 = "attack_swing_heavy_right_diagonal",
    }
    R.staff_spark_spear_template_1 = R.staff_spark_spear_template_1 or {}
    R.staff_spark_spear_template_1.bw_ = R.staff_spark_spear_template_1.bw_ or false
    R.staff_spark_spear_template_1.es_ = {
        attack_charge_spear        = "attack_swing_charge_right",
        attack_shoot_rapid_left    = "attack_swing_heavy",
        attack_shoot_rapid_right   = "attack_swing_heavy_right",
        attack_shoot_spear_charged = "attack_swing_down_right",
    }
    R.staff_spark_spear_template_1.we_ = {
        attack_charge_spear        = "attack_swing_charge_left",
        attack_shoot_rapid_left    = "attack_swing_left",
        attack_shoot_rapid_right   = "attack_swing_right",
        attack_shoot_spear_charged = "attack_swing_left",
        cooldown_start             = "parry_pose",
    }
    R.staff_spark_spear_template_1.wh_ = {
        attack_charge_spear        = "attack_swing_charge_right",
        attack_shoot_rapid_left    = "attack_swing_down_right",
        attack_shoot_rapid_right   = "attack_swing_heavy_right_diagonal",
        attack_shoot_spear_charged = "attack_swing_heavy_right",
        cooldown_start             = "parry_pose",
    }
    R.two_handed_axes_template_2 = R.two_handed_axes_template_2 or {}
    R.two_handed_axes_template_2.we_ = R.two_handed_axes_template_2.we_ or false
    R.two_handed_axes_template_2.es_ = {
        attack_push                = "attack_push",
        attack_swing_charge_down   = "attack_swing_charge_right",
        attack_swing_charge_left   = "attack_swing_charge_right",
        attack_swing_heavy_down    = "attack_swing_down_left",
        attack_swing_heavy_left    = "attack_swing_heavy_right",
        attack_swing_left          = "attack_swing_heavy",
        attack_swing_left_diagonal = "attack_swing_heavy",
        attack_swing_right         = "attack_swing_heavy_right",
        parry_pose                 = "parry_pose",
    }
    R.two_handed_axes_template_2.wh_ = {
        attack_push                = "attack_push",
        attack_swing_charge_down   = "attack_swing_charge",
        attack_swing_charge_left   = "attack_swing_charge_right",
        attack_swing_heavy_down    = "attack_swing_left",
        attack_swing_heavy_left    = "attack_swing_heavy_right",
        attack_swing_left          = "attack_swing_left",
        attack_swing_left_diagonal = "attack_swing_down_right",
        attack_swing_right         = "attack_swing_up",
        parry_pose                 = "parry_pose",
    }
    R.two_handed_billhooks_template = R.two_handed_billhooks_template or {}
    R.two_handed_billhooks_template.wh_ = R.two_handed_billhooks_template.wh_ or false
    -- #290: MERGE the five tester picks into the complete v0.12.102 safety map.
    -- Assignment here used to replace that map wholesale. Worse, these keys are the
    -- Billhook's 1P `anim_event` names while the 3P body receives `anim_event_3p or
    -- anim_event`; the five actions with authored anim_event_3p therefore missed every
    -- replacement row. Preserve the receiver-facing safety rows and overlay the picks.
    local billhook_es_picks = {
        attack_swing_charge_down = "attack_swing_charge_left_diagonal",
        attack_swing_charge_stab = "attack_swing_stab_charge",
        attack_swing_heavy_down  = "attack_swing_heavy_left_diagonal",
        attack_swing_heavy_left  = "attack_swing_left_diagonal",
        attack_swing_stab_02     = "attack_swing_stab",
    }
    local billhook_es = R.two_handed_billhooks_template.es_
    if type(billhook_es) ~= "table" then billhook_es = {} end
    for source, target in pairs(_3p_remap_billhook_to_polearm) do
        if billhook_es[source] == nil then billhook_es[source] = target end
    end
    for source, target in pairs(billhook_es_picks) do
        billhook_es[source] = target
    end
    R.two_handed_billhooks_template.es_ = billhook_es
    -- v0.12.205: Kerillian billhook picks RESTORED (#319 audit; residual of the
    -- #290 two-namespace bug). The tester's 5 Kerillian billhook picks live in
    -- the TEMPLATE-QUALIFIED namespace (user_settings(4).config 2026-07-03),
    -- which the v0.12.203 bake read for es_/wh_ but not for we_ — so Kerillian's
    -- billhook fired these 5 events raw on her spear SM. Values verbatim from
    -- the tester config (identical to the confirmed-working es_ set above).
    R.two_handed_billhooks_template.we_ = {
        attack_swing_charge_down = "attack_swing_charge_left_diagonal",
        attack_swing_charge_stab = "attack_swing_stab_charge",
        attack_swing_heavy_down  = "attack_swing_heavy_left_diagonal",
        attack_swing_heavy_left  = "attack_swing_left_diagonal",
        attack_swing_stab_02     = "attack_swing_stab",
    }
    R.two_handed_cog_hammers_template_1 = R.two_handed_cog_hammers_template_1 or {}
    R.two_handed_cog_hammers_template_1.dr_ = R.two_handed_cog_hammers_template_1.dr_ or false
    R.two_handed_cog_hammers_template_1.es_ = {
        attack_push                    = "attack_push",
        attack_swing_charge            = "attack_swing_charge",
        attack_swing_charge_pose       = "attack_swing_charge_left",
        attack_swing_charge_right      = "attack_swing_charge_right",
        attack_swing_charge_right_down = "attack_swing_charge_right",
        attack_swing_down_left         = "attack_swing_down_left",
        attack_swing_down_right        = "attack_swing_down_left",
        attack_swing_heavy             = "attack_swing_down_left",
        attack_swing_heavy_right       = "attack_swing_down_left",
        attack_swing_left              = "attack_swing_left",
        attack_swing_left_diagonal     = "attack_swing_left_diagonal",
        attack_swing_right_diagonal    = "attack_swing_down_right",
        attack_swing_up                = "attack_swing_left",
        attack_swing_up_pose           = "attack_swing_left",
        attack_swing_up_right          = "attack_swing_down_right",
        parry_pose                     = "parry_pose",
    }
    R.two_handed_cog_hammers_template_1.we_ = {
        attack_push                    = "attack_push",
        attack_swing_charge            = "attack_swing_heavy_left",
        attack_swing_charge_pose       = "attack_swing_heavy_left",
        attack_swing_charge_right      = "attack_swing_charge_down",
        attack_swing_charge_right_down = "attack_swing_heavy_left",
        attack_swing_down_left         = "attack_swing_right",
        attack_swing_down_right        = "attack_swing_right",
        attack_swing_heavy             = "attack_swing_heavy_down",
        attack_swing_heavy_right       = "attack_swing_heavy_down",
        attack_swing_left              = "attack_swing_right",
        attack_swing_left_diagonal     = "attack_swing_left",
        attack_swing_right_diagonal    = "attack_swing_right",
        attack_swing_up                = "attack_swing_left",
        attack_swing_up_pose           = "attack_swing_left",
        attack_swing_up_right          = "attack_swing_right",
        parry_pose                     = "parry_pose",
    }
    -- v0.12.213-dev (#519): dr_2h_cog_hammer on Saltzpyre -> WP Greathammer.
    R.two_handed_cog_hammers_template_1.wh_ = {
        attack_push                    = "attack_push",
        attack_swing_charge            = "attack_swing_charge_right_down",
        attack_swing_charge_pose       = "attack_swing_charge_right_down",
        attack_swing_charge_right      = "attack_push",
        attack_swing_charge_right_down = "attack_swing_charge_right_down",
        attack_swing_down_left         = "attack_swing_heavy_right_diagonal",
        attack_swing_down_right        = "attack_swing_heavy_right_diagonal",
        attack_swing_heavy             = "attack_push",
        attack_swing_heavy_right       = "attack_push",
        attack_swing_left              = "attack_swing_up_left",
        attack_swing_left_diagonal     = "attack_swing_up_left",
        attack_swing_right_diagonal    = "attack_swing_down_right",
        attack_swing_up                = "attack_swing_up_left",
        attack_swing_up_pose           = "attack_swing_left",
        attack_swing_up_right          = "attack_swing_up",
        parry_pose                     = "parry_pose",
    }
    R.two_handed_halberds_template_1 = R.two_handed_halberds_template_1 or {}
    R.two_handed_halberds_template_1.es_ = R.two_handed_halberds_template_1.es_ or false
    R.two_handed_halberds_template_1.wh_ = {
        attack_push               = "attack_push",
        attack_swing_charge_left  = "attack_swing_charge_stab",
        attack_swing_charge_right = "attack_swing_charge_stab",
        attack_swing_down_left    = "attack_swing_left_diagonal",
        attack_swing_down_right   = "attack_swing_down",
        attack_swing_heavy        = "attack_swing_heavy_stab",
        attack_swing_heavy_right  = "attack_swing_heavy_down",
        attack_swing_right        = "attack_swing_stab",
        parry_pose                = "parry_pose",
    }
    R.two_handed_hammer_priest_template = R.two_handed_hammer_priest_template or {}
    R.two_handed_hammer_priest_template.wh_ = R.two_handed_hammer_priest_template.wh_ or false
    R.two_handed_hammer_priest_template.es_ = {
        attack_push                       = "attack_push",
        attack_slam                       = "attack_swing_left",
        attack_slam_charge                = "attack_swing_left",
        attack_swing_charge               = "attack_swing_charge",
        attack_swing_charge_right         = "attack_swing_charge",
        attack_swing_charge_right_down    = "attack_swing_charge_left",
        attack_swing_down_right           = "attack_swing_down_left",
        attack_swing_heavy_right          = "attack_swing_heavy",
        attack_swing_heavy_right_diagonal = "attack_swing_down_left",
        attack_swing_left                 = "attack_swing_left_diagonal",
        attack_swing_up                   = "attack_swing_heavy",
        attack_swing_up_left              = "attack_swing_down_left",
        parry_pose                        = "parry_pose",
        parry_pose_02                     = "parry_pose",
    }
    R.two_handed_hammer_priest_template.we_ = {
        attack_push                       = "attack_push",
        attack_slam                       = "attack_swing_left_diagonal",
        attack_slam_charge                = "attack_swing_heavy_left",
        attack_swing_charge               = "attack_swing_charge_left",
        attack_swing_charge_right         = "attack_swing_charge_down",
        attack_swing_charge_right_down    = "attack_swing_charge_down",
        attack_swing_down_right           = "attack_swing_right",
        attack_swing_heavy_right          = "attack_swing_heavy_left",
        attack_swing_heavy_right_diagonal = "attack_swing_heavy_down",
        attack_swing_left                 = "attack_swing_right",
        attack_swing_up                   = "attack_swing_left",
        attack_swing_up_left              = "attack_swing_left",
        parry_pose                        = "parry_pose",
        parry_pose_02                     = "parry_pose",
    }
    R.two_handed_hammers_template_1 = R.two_handed_hammers_template_1 or {}
    R.two_handed_hammers_template_1.es_ = R.two_handed_hammers_template_1.es_ or false
    R.two_handed_hammers_template_1.we_ = {
        attack_push                = "attack_push",
        attack_swing_charge        = "attack_swing_charge_left",
        attack_swing_charge_left   = "attack_swing_charge_left",
        attack_swing_charge_right  = "attack_swing_charge_left",
        attack_swing_down_left     = "attack_swing_heavy_down",
        attack_swing_down_right    = "attack_swing_right",
        attack_swing_heavy         = "attack_swing_heavy_left",
        attack_swing_heavy_right   = "attack_swing_heavy_left",
        attack_swing_left          = "attack_swing_left",
        attack_swing_left_diagonal = "attack_swing_left_diagonal",
        parry_pose                 = "parry_pose",
    }
    -- v0.12.213-dev (#519): es_2h_hammer on Saltzpyre -> WP Greathammer.
    R.two_handed_hammers_template_1.wh_ = {
        attack_push                = "attack_push",
        attack_swing_charge        = "attack_swing_charge",
        attack_swing_charge_left   = "attack_swing_charge_right_down",
        attack_swing_charge_right  = "attack_swing_charge_right",
        attack_swing_down_left     = "attack_swing_heavy_right_diagonal",
        attack_swing_down_right    = "attack_swing_heavy_right_diagonal",
        attack_swing_heavy         = "attack_swing_heavy_right",
        attack_swing_heavy_right   = "attack_swing_heavy_right",
        attack_swing_left          = "attack_swing_left",
        attack_swing_left_diagonal = "attack_swing_up_left",
        parry_pose                 = "parry_pose",
    }
    R.two_handed_picks_template_1 = R.two_handed_picks_template_1 or {}
    R.two_handed_picks_template_1.dr_ = R.two_handed_picks_template_1.dr_ or false
    R.two_handed_picks_template_1.we_ = {
        attack_push                        = "attack_push",
        attack_swing_charge_left_down      = "attack_swing_charge_left",
        attack_swing_charge_left_down_pose = "attack_swing_charge_left",
        attack_swing_charge_right_down     = "attack_swing_charge_down",
        attack_swing_down_left             = "attack_swing_right",
        attack_swing_down_left_axe         = "attack_swing_right",
        attack_swing_down_right            = "attack_swing_right",
        attack_swing_down_right_axe        = "attack_swing_right",
        attack_swing_left                  = "attack_swing_right",
        attack_swing_left_diagonal         = "attack_swing_left",
        attack_swing_right_diagonal        = "attack_swing_right",
        parry_pose                         = "parry_pose",
    }
    -- v0.12.213-dev (#519): dr_2h_pick on Saltzpyre -> WP Greathammer.
    R.two_handed_picks_template_1.wh_ = {
        attack_push                        = "attack_push",
        attack_swing_charge_left_down      = "attack_swing_charge_right_down",
        attack_swing_charge_left_down_pose = "attack_swing_charge_right_down",
        attack_swing_charge_right_down     = "attack_swing_charge_right_down",
        attack_swing_down_left             = "attack_swing_heavy_right_diagonal",
        attack_swing_down_left_axe         = "attack_swing_heavy_right_diagonal",
        attack_swing_down_right            = "attack_swing_heavy_right_diagonal",
        attack_swing_down_right_axe        = "attack_swing_heavy_right_diagonal",
        attack_swing_left                  = "attack_swing_left",
        attack_swing_left_diagonal         = "attack_swing_up_left",
        attack_swing_right_diagonal        = "attack_swing_down_right",
        parry_pose                         = "parry_pose",
    }
    R.two_handed_spears_elf_template_1 = R.two_handed_spears_elf_template_1 or {}
    R.two_handed_spears_elf_template_1.we_ = R.two_handed_spears_elf_template_1.we_ or false
    R.two_handed_spears_elf_template_1.wh_ = {
        attack_push                = "attack_push",
        attack_swing_charge_left   = "attack_swing_charge_stab",
        attack_swing_charge_right  = "attack_swing_charge_down",
        attack_swing_down_left     = "attack_swing_left_diagonal",
        attack_swing_down_left_axe = "attack_swing_stab",
        attack_swing_down_right    = "attack_swing_stab",
        attack_swing_heavy         = "attack_swing_heavy_down",
        attack_swing_heavy_right   = "attack_swing_heavy_stab",
        attack_swing_right         = "attack_swing_stab",
        parry_pose                 = "parry_pose",
        push_stab                  = "attack_swing_left_diagonal",
    }
    R.two_handed_swords_executioner_template_1 = R.two_handed_swords_executioner_template_1 or {}
    R.two_handed_swords_executioner_template_1.es_ = R.two_handed_swords_executioner_template_1.es_ or false
    R.two_handed_swords_executioner_template_1.we_ = {
        attack_push                     = "attack_push",
        attack_swing_charge_left_down   = "attack_swing_charge",
        attack_swing_charge_right_down  = "attack_swing_charge",
        attack_swing_down_left          = "attack_swing_right",
        attack_swing_down_right         = "attack_swing_right",
        attack_swing_left               = "attack_swing_left",
        attack_swing_left_diagonal      = "attack_swing_left",
        attack_swing_left_diagonal_last = "attack_swing_heavy",
        attack_swing_right              = "attack_swing_heavy_right",
        parry_pose                      = "parry_pose",
    }
    R.two_handed_swords_executioner_template_1.wh_ = {
        attack_push                     = "attack_push",
        attack_swing_charge_left_down   = "attack_swing_charge_diagonal_left",
        attack_swing_charge_right_down  = "attack_swing_charge_diagonal_right",
        attack_swing_down_left          = "attack_swing_heavy_left_diagonal",
        attack_swing_down_right         = "attack_swing_heavy_right_diagonal",
        attack_swing_left               = "attack_swing_left_diagonal",
        attack_swing_left_diagonal      = "attack_swing_right_diagonal",
        attack_swing_left_diagonal_last = "attack_swing_left_diagonal",
        attack_swing_right              = "attack_swing_right_diagonal",
        parry_pose                      = "parry_pose",
    }
    R.we_one_hand_axe_template = R.we_one_hand_axe_template or {}
    R.we_one_hand_axe_template.we_ = R.we_one_hand_axe_template.we_ or false
    R.we_one_hand_axe_template.es_ = {
        attack_push                             = "attack_push",
        attack_swing_charge_left_diagonal       = "attack_swing_charge_left_diagonal",
        attack_swing_charge_left_diagonal_pose  = "attack_swing_charge_left_diagonal_pose",
        attack_swing_charge_right_diagonal_pose = "attack_swing_charge_right_diagonal_pose",
        attack_swing_down                       = "attack_swing_down_right",
        attack_swing_down_right                 = "attack_swing_down_right",
        attack_swing_heavy_down                 = "attack_swing_heavy_down",
        attack_swing_heavy_down_right           = "attack_swing_heavy_down_right",
        attack_swing_left                       = "attack_swing_left_diagonal",
        attack_swing_right                      = "attack_swing_right_diagonal",
        attack_swing_up                         = "attack_swing_right_diagonal",
        parry_pose                              = "parry_pose",
    }
    R.we_one_hand_axe_template.wh_ = {
        attack_swing_up = "attack_swing_up_left",
    }
end


return _3p_template_remaps
end
