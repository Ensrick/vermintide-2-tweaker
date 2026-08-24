# Audited exceptions for the CURRENT LIVE TEST authority scanner.
#
# Keep this file narrow and immutable-source-addressed. An exception is never
# marker-wide permission for a card to invent evidence: deployed-tree, source,
# literal signature, and concrete guard anchors all have to match.
#
# PIN REPOINTING (issue #1328): the ModTree/ModTrees values in the three
# CONSUMED structures (ReceiptFamilyOverrides / ReceiptRouteOverrides /
# ReceiptDiscoveryOverrides) are provenance, not policy - they name the exact
# deployed <mod>/scripts/mods subtree the finite-output proof was audited
# against. Every ship of a pinned mod therefore strands them. Step 5b of
# tools/ship/ship.ps1 repoints the shipped mod's values to the new deployed
# tree automatically after a confirmed upload (the per-override token anchors
# still fail closed if the audited code itself changed, so the repoint never
# grants an unreviewed proof). Ship cannot commit to master, so the rewrite is
# left in the WORKING TREE and reported in the ship summary ("Pins" row); the
# next PR to master carries it. LegacyMarkerFamilyModTrees (reviewer context)
# and LegacySourceTrees (carried-forward promotion pins) are deliberately
# NEVER rewritten by that step.

@{
    # Immutable deployed subtrees for the complete-emitter family audits below.
    # Any deployment that changes one byte in an audited mod fails closed until
    # its finite-output proof is reviewed and this pin is intentionally moved.
    # Historical complete-marker audits retained for reviewer context only.
    # They are deliberately not consumed by source authority: a mod-tree/path
    # list plus prose cannot prove any exact receipt route finite.
    LegacyMarkerFamilyModTrees = @{
        wt='57d61b330683cb3951ed45985ddeb84490d5bf04'
        wt_dev='2e47870d6c59b1976ab0281bcd1d160c7786b1b8'
        ct_dev='8522d59ff07842166744f33a295b0114245709d5'
        gt_dev='efcd2eb1e842300acd6f242198d0e8bcd174a57a'
        gut='9080f1b3d65b8f5b778b3b0781918b1c8d42e510'
        gut_dev='1d3837ddaf33935e6d0202a8034a0035e8be67c3'
        cosmetics_tweaker=@(
            'c9b7d91f95d9b042fe98e2c2c14cd87ce094c64e'
            '715844bd0c51f46bfc599a676cfe1332fef9a193'
        )
        crt='644033669dc68d8345e1259cf0da1f9b0d03ac04'
        character_weapon_variants='f1e2269c7fad81547f8f3b104fb750583b536edd'
        character_dialogue='fe9c4fbcee359c60e48b8208043f4afcec93cc48'
        cim_dev='da4ae6a780712652e0fe542c3d219827b00e5035'
        event_tweaker='15665a1d10b5cdbe7594da464b29ad964190cd85'
        mp='9d00a1b341cb445fcb937c4ce128383021b16abb'
    }

    # These carried-forward Workshop assets predate manifest-schema-2's
    # per-row source_commit field. Their exact promotion trees are the source
    # authority; the current working tree and version text are never trusted.
    LegacySourceTrees = @(
        @{
            ModId = 'ct'
            Version = '0.7.131-beta'
            RootTree = 'b6444b1353cf38788f25d8b4a3bc469cb85930ad'
            ModTree = 'cbf3114e4c3a80729544567c09755a7976510fd4'
            Reason = 'Carried-forward stable asset predates per-row source_commit receipts.'
        }
        @{
            ModId = 'verminious_dreams_lighting'
            Version = '1.0.7'
            RootTree = 'a59aee9380501a265253734e930c06c3ce8de384'
            ModTree = '7a4fbab56afab956b46b24d91b82dabab11d1dba'
            Reason = 'Carried-forward stable asset predates per-row source_commit receipts.'
        }
    )

    # Static analysis deliberately recognizes only simple local caps/guards.
    # These receipts have finite control-flow bounds that require a small
    # cross-function audit.  Sources is the complete set of direct emitters.
    # Superseded snapshots are deliberately pruned after an exact consumed
    # route override replaces them; Git retains their history while this
    # Windows PowerShell 5.1 data file stays below its safe AST limit.
    LegacyMarkerFamilyAudits = @(
        @{
            Marker = '[ct:456]'
            ModId = 'ct_dev'
            Sources = @(
                'chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/_ct_level_load_owner.lua'
                'chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/_ct_pickup_spawn_owner.lua'
            )
            Bound = 'One finite census per mission population plus at most two fallthrough receipts per book spawner (leftover, then empty on casket failure).'
        }
        @{
            Marker = '[gut:persist]'
            ModId = 'gut_dev'
            Sources = @(
                'gui_tweaker_dev/scripts/mods/gui_tweaker_dev/_gut_native_loadouts.lua'
            )
            Bound = 'Each game-exit/title-enter/unload edge emits at most one finite career-by-slot snapshot census and summary.'
        }
        @{
            Marker = '[gut:272]'
            ModIds = @('gut', 'gut_dev')
            Sources = @(
                'gui_tweaker/scripts/mods/gui_tweaker/gui_tweaker.lua'
                'gui_tweaker_dev/scripts/mods/gui_tweaker_dev/_gut_diagnostics.lua'
                'gui_tweaker_dev/scripts/mods/gui_tweaker_dev/_gut_scoreboard_live.lua'
                'gui_tweaker_dev/scripts/mods/gui_tweaker_dev/gui_tweaker_dev.lua'
            )
            Bound = 'Boot failures emit once; explicit diagnostics visit four records with finite fields; live evidence has an absolute eight-row cap.'
        }
        @{
            Marker = '[gut:1151]'
            ModId = 'gut_dev'
            Sources = @(
                'gui_tweaker_dev/scripts/mods/gui_tweaker_dev/_gut_damage_taken_scoreboard.lua'
                'gui_tweaker_dev/scripts/mods/gui_tweaker_dev/gui_tweaker_dev.lua'
            )
            Bound = 'Scoreboard repair has an absolute eight-row diagnostic cap; module installation adds at most one load-failure row.'
        }
        @{
            Marker = '[gut:402]'
            ModId = 'gut_dev'
            Sources = @(
                'gui_tweaker_dev/scripts/mods/gui_tweaker_dev/_gut_official_loadout_boot_guard.lua'
            )
            Bound = 'Each guarded Modded-Adventure boot hook emits at most one branch receipt per invocation; snapshot import visits a finite career set.'
        }
        @{
            Marker = '[cim:882]'
            ModId = 'cim_dev'
            Sources = @(
                'crafting_in_modded_dev/scripts/mods/crafting_in_modded_dev/_cim_mission_forge_safety.lua'
            )
            Bound = 'The wrapper emits at most one receipt per finite item-previewer construction before delegating.'
        }
        @{
            Marker = '[et:430]'
            ModId = 'event_tweaker'
            Sources = @(
                'event_tweaker/scripts/mods/event_tweaker/_evt_guard430_curse_parity.lua'
                'event_tweaker/scripts/mods/event_tweaker/_evt_selection.lua'
            )
            Bound = 'Boot/catalog work is finite, parity emits on applied-state edges, and selection emits at most once per gather_mutators transaction.'
        }
        @{
            Marker = '[crt:728]'
            ModId = 'crt'
            Sources = @(
                'career_tweaker/scripts/mods/career_tweaker/_crt_career_unlock.lua'
            )
            Bound = 'Finite catalog summaries are digest-deduplicated; UI refresh emits once per explicit relevant setting change.'
        }
        @{
            Marker = '[ct:349]'
            ModId = 'ct_dev'
            Sources = @(
                'chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/_ct_diag_cursed_chest132.lua'
            )
            Bound = 'The finalized guard permits one settled audit receipt per mission generation.'
        }
        @{
            Marker = '[ct:132]'
            ModId = 'ct_dev'
            Sources = @(
                'chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/_ct_diag_cursed_chest132.lua'
            )
            Bound = 'The finite mission population emits once per spawned chest plus at most one over-cap reconciliation row during one-shot finalization.'
        }
        @{
            Marker = '[ct:vaul]'
            ModId = 'ct_dev'
            Sources = @(
                'chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/_ct_meta_trait_boons.lua'
            )
            Bound = 'A per-buff signature edge guard makes unchanged every-frame updates silent.'
        }
        @{
            Marker = '[crt:472]'
            ModId = 'crt'
            Sources = @(
                'career_tweaker/scripts/mods/career_tweaker/career_tweaker_armor_overcharge.lua'
            )
            Bound = 'Focused diagnostics are signature-deduplicated under an absolute forty-eight-row cap.'
        }
        @{
            Marker = '[gt:254]'
            ModId = 'gt_dev'
            Sources = @(
                'general_tweaker_dev/scripts/mods/general_tweaker_dev/_gt_creature_spawner.lua'
            )
            Bound = 'Each explicit spawn request emits finite enqueue, blocker, and terminal transitions; pending work is capped at eight and unchanged polls are silent.'
        }
        @{
            Marker = '[gt:659]'
            ModId = 'gt_dev'
            Sources = @(
                'general_tweaker_dev/scripts/mods/general_tweaker_dev/_gt_bots_keep.lua'
                'general_tweaker_dev/scripts/mods/general_tweaker_dev/_gt_necro_keep_trace.lua'
            )
            Bound = 'The trace core has a twenty-four-row phase budget and keep policy permits four lifecycle rows per extension instance.'
        }
        @{
            Marker = '[gt:385]'
            ModId = 'gt_dev'
            Sources = @(
                'general_tweaker_dev/scripts/mods/general_tweaker_dev/_gt_bot_fixes.lua'
            )
            Bound = 'Below-leash evidence has an absolute twenty-four-row cap and suppression evidence is latched once per contiguous episode.'
        }
        @{
            Marker = '[crt:473]'
            ModId = 'crt'
            Sources = @(
                'career_tweaker/scripts/mods/career_tweaker/_crt_balance_catalog_early.lua'
            )
            Bound = 'The catalog mutation emits at most once per balance-reconciliation transaction.'
        }
        @{
            Marker = '[mp:577]'
            ModId = 'mp'
            Sources = @(
                'modded_progression/scripts/mods/modded_progression/modded_progression.lua'
            )
            Bound = 'Exactly one terminal committed-or-rejected receipt is emitted per explicit purchase attempt.'
        }
        @{
            Marker = '[mp:607]'
            ModId = 'mp'
            Sources = @(
                'modded_progression/scripts/mods/modded_progression/_mp_loot_diag_runtime.lua'
            )
            Bound = 'Each one-mission diagnostic run crosses a finite set of native seams; every hook invocation emits at most one event or observer-error row and the persisted ledger retains at most twelve records.'
        }
        @{
            Marker = '[gut:717]'
            ModId = 'gut_dev'
            Sources = @(
                'gui_tweaker_dev/scripts/mods/gui_tweaker_dev/_gut_mod_tweaker_contracts.lua'
            )
            Bound = 'The receipt is emitted at most once per explicit /gut_regression_test invocation.'
        }
        @{
            Marker = '[gt:753]'
            ModId = 'gt_dev'
            Sources = @(
                'general_tweaker_dev/scripts/mods/general_tweaker_dev/_gt_diag_disconnect_failure.lua'
            )
            Bound = 'One armed receipt at load and one receipt per guarded connection-state transition.'
        }
        @{
            Marker = '[et:1123]'
            ModId = 'event_tweaker'
            Sources = @(
                'event_tweaker/scripts/mods/event_tweaker/_evt_shadow_adventure.lua'
            )
            Bound = 'The multiplier_applied state guard permits one apply or restore receipt per lifecycle transition.'
        }
    )

    # Exact complex-call routes shared by one or more immutable deployed
    # records. Unlike marker-wide permission, each route has one literal
    # signature and token-anchored emitter/finite-output proof. SourcesByMod
    # and ModTrees make multi-artifact families explicit rather than pooling
    # evidence across builds.
    ReceiptFamilyOverrides = @(
        @{
            Marker='[crt:728]'; ModId='crt'
            ModTrees=@{crt='f142c181ef116b1cc49153791b8a67281b17e731'}
            SourcesByMod=@{crt='career_tweaker/scripts/mods/career_tweaker/_crt_career_unlock.lua'}
            Signature='[crt:728] installed setting=%s scope=local_level_gate occupancy=vanilla'
            Bound='one terminal install receipt per module evaluation'
            EmitterAnchors=@(@{Tokens=@('safe_printf','(','String:[crt:728] installed setting=%s scope=local_level_gate occupancy=vanilla')})
            GuardAnchors=@(@{Tokens=@('function','M','.','install','(','mod',')')})
        }
        @{
            Marker='[crt:728]'; ModId='crt'
            ModTrees=@{crt='f142c181ef116b1cc49153791b8a67281b17e731'}
            SourcesByMod=@{crt='career_tweaker/scripts/mods/career_tweaker/_crt_career_unlock.lua'}
            Signature='[crt:728] level_gate setting=%s unlock=%s profile=%s level=%s result=%s reason=%s'
            Bound='unlock decisions are signature-deduplicated for the finite unlock catalogue'
            EmitterAnchors=@(@{Tokens=@('safe_printf','(','String:[crt:728] level_gate setting=%s unlock=%s profile=%s level=%s result=%s reason=%s')})
            GuardAnchors=@(
                @{Tokens=@('if','unlock_decisions','[','key',']','then','return','end')}
                @{Tokens=@('unlock_decisions','[','key',']','=','true')}
            )
        }
        @{
            Marker='[crt:728]'; ModId='crt'
            ModTrees=@{crt='f142c181ef116b1cc49153791b8a67281b17e731'}
            SourcesByMod=@{crt='career_tweaker/scripts/mods/career_tweaker/_crt_career_unlock.lua'}
            Signature='[crt:728] character_select setting=%s kruber_profile=%s party=%s available=%s reserved_by=%s careers=[%s]'
            Bound='character-selection summaries are digest-deduplicated over a finite widget catalogue'
            EmitterAnchors=@(@{Tokens=@('safe_printf','(','String:[crt:728] character_select setting=%s kruber_profile=%s party=%s available=%s reserved_by=%s careers=[%s]')})
            GuardAnchors=@(
                @{Tokens=@('if','selection_summaries','[','digest',']','then','return','end')}
                @{Tokens=@('selection_summaries','[','digest',']','=','true')}
            )
        }
        @{
            Marker='[crt:728]'; ModId='crt'
            ModTrees=@{crt='f142c181ef116b1cc49153791b8a67281b17e731'}
            SourcesByMod=@{crt='career_tweaker/scripts/mods/career_tweaker/_crt_career_unlock.lua'}
            Signature='[crt:728] ui_refresh setting=%s hero_summary=%s character_select=%s'
            Bound='one UI-refresh receipt per explicit unlock-all or level-override setting transition'
            EmitterAnchors=@(@{Tokens=@('safe_printf','(','String:[crt:728] ui_refresh setting=%s hero_summary=%s character_select=%s')})
            GuardAnchors=@(
                @{Source='career_tweaker/scripts/mods/career_tweaker/career_tweaker.lua';Tokens=@('if','setting_id','==','String:unlock_all_careers','or','setting_id',':','find','(','String:^level_override_',')','then')}
                @{Source='career_tweaker/scripts/mods/career_tweaker/career_tweaker.lua';Tokens=@('mod','.','_crt_refresh_career_unlock_ui','(',')')}
            )
        }
        @{
            Marker='[wt:282]'; ModIds=@('wt','wt_dev')
            ModTrees=@{wt='322fbab2f0f6ee326e76eed75aaf2fa6b830e547';wt_dev='a16d16d0d43d3d4f4c32140361911ef713abdc81'}
            SourcesByMod=@{
                wt='weapon_tweaker/scripts/mods/weapon_tweaker/_wt_deepwood_runtime.lua'
                wt_dev='weapon_tweaker_dev/scripts/mods/weapon_tweaker_dev/_wt_deepwood_runtime.lua'
            }
            Signature='[wt:282] Deepwood package lease state=%s ready=%s loading=%s references=%s attempts=%s'
            Bound='one receipt per last_reason state transition; unchanged ensure/update calls are silent'
            EmitterAnchors=@(@{Tokens=@('_printf','(','String:[wt:282] Deepwood package lease state=%s ready=%s loading=%s references=%s attempts=%s')})
            GuardAnchors=@(
                @{Tokens=@('if','reason','~=','last_reason','then')}
                @{Tokens=@('last_reason','=','reason')}
            )
        }
        @{
            Marker='[cwv:423]'; ModId='character_weapon_variants'
            ModTrees=@{character_weapon_variants='fc363b4babf93a33330e34d5eeb545e7e9acc502'}
            SourcesByMod=@{character_weapon_variants='character_weapon_variants/scripts/mods/character_weapon_variants/_cwv_exact_wire_runtime.lua'}
            Signature='[cwv:423] exact damage catalog=%s rows=%d beacon=cwv_damage_profiles_exact_v1'
            Bound='one mutually exclusive catalog/parity result during exact-wire install'
            EmitterAnchors=@(@{Tokens=@('_printf','(','String:[cwv:423] exact damage catalog=%s rows=%d beacon=cwv_damage_profiles_exact_v1')})
            GuardAnchors=@(@{Tokens=@('function','mod','.','_cwv_damage_wire_safe','(',')')})
        }
        @{
            Marker='[cwv:423]'; ModId='character_weapon_variants'
            ModTrees=@{character_weapon_variants='fc363b4babf93a33330e34d5eeb545e7e9acc502'}
            SourcesByMod=@{character_weapon_variants='character_weapon_variants/scripts/mods/character_weapon_variants/_cwv_exact_wire_runtime.lua'}
            Signature='[cwv:423] WARN exact damage parity unavailable (%s); every cwv profile substitutes'
            Bound='one mutually exclusive parity-install failure receipt during exact-wire installation'
            EmitterAnchors=@(@{Tokens=@('_printf','(','String:[cwv:423] WARN exact damage parity unavailable (%s); every cwv profile substitutes')})
            GuardAnchors=@(@{Tokens=@('if','parity','then')})
        }
        @{
            Marker='[cwv:423]'; ModId='character_weapon_variants'
            ModTrees=@{character_weapon_variants='fc363b4babf93a33330e34d5eeb545e7e9acc502'}
            SourcesByMod=@{character_weapon_variants='character_weapon_variants/scripts/mods/character_weapon_variants/_cwv_exact_wire_runtime.lua'}
            Signature='[cwv:423] WARN exact damage catalog unavailable (%s); every cwv profile substitutes'
            Bound='one mutually exclusive catalog-capture failure receipt during exact-wire installation'
            EmitterAnchors=@(@{Tokens=@('_printf','(','String:[cwv:423] WARN exact damage catalog unavailable (%s); every cwv profile substitutes')})
            GuardAnchors=@(@{Tokens=@('if','snapshot','then')})
        }
        @{
            Marker='[cwv:423]'; ModId='character_weapon_variants'
            ModTrees=@{character_weapon_variants='fc363b4babf93a33330e34d5eeb545e7e9acc502'}
            SourcesByMod=@{character_weapon_variants='character_weapon_variants/scripts/mods/character_weapon_variants/_cwv_exact_wire_runtime.lua'}
            Signature='[cwv:423] blocked unsafe hit: profile=%s(%s) exact catalog unconfirmed and no vanilla fallback resolved'
            Bound='at most one blocked-hit receipt per finite NetworkLookup damage-profile id'
            EmitterAnchors=@(@{Tokens=@('_printf','(','String:[cwv:423] blocked unsafe hit: profile=%s(%s) exact catalog unconfirmed and no vanilla fallback resolved')})
            GuardAnchors=@(
                @{Tokens=@('if','not','logged','[','damage_profile_id',']','then')}
                @{Tokens=@('logged','[','damage_profile_id',']','=','true')}
            )
        }
        @{
            Marker='[cwv:423]'; ModId='character_weapon_variants'
            ModTrees=@{character_weapon_variants='fc363b4babf93a33330e34d5eeb545e7e9acc502'}
            SourcesByMod=@{character_weapon_variants='character_weapon_variants/scripts/mods/character_weapon_variants/_cwv_exact_wire_runtime.lua'}
            Signature='[cwv:423] wire dmg-profile sub: %s(%s) -> %s (exact catalog unconfirmed; base-weapon damage this hit)'
            Bound='at most one substitution receipt per finite NetworkLookup damage-profile id'
            EmitterAnchors=@(@{Tokens=@('_printf','(','String:[cwv:423] wire dmg-profile sub: %s(%s) -> %s (exact catalog unconfirmed; base-weapon damage this hit)')})
            GuardAnchors=@(
                @{Tokens=@('if','not','logged','[','damage_profile_id',']','then')}
                @{Tokens=@('logged','[','damage_profile_id',']','=','true')}
            )
        }
        @{
            Marker='[ct:349]'; ModId='ct_dev'
            ModTrees=@{ct_dev='99cb6bf8cdd5bda7b671f364bacf837ddffdd8e0'}
            SourcesByMod=@{ct_dev='chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/_ct_diag_cursed_chest132.lua'}
            Signature='[ct:349] chest_count_audit level=%s mission_of_mercy=%s actual=%d cap=%s pickup_census=%s class=%s is_server=%s'
            Bound='Core.finalize returns no classification after the mission-generation finalized latch is set'
            EmitterAnchors=@(@{Tokens=@('_safe_printf','(','String:[ct:349] chest_count_audit level=%s mission_of_mercy=%s actual=%d cap=%s pickup_census=%s class=%s is_server=%s')})
            GuardAnchors=@(
                @{Tokens=@('local','classification',',','actual','=','Core','.','finalize','(','_tracker',',','level_id',',','cap',',','census',')')}
                @{Tokens=@('if','not','classification','then','return','nil','end')}
            )
        }
        @{
            Marker='[ct:132]'; ModId='ct_dev'
            ModTrees=@{ct_dev='99cb6bf8cdd5bda7b671f364bacf837ddffdd8e0'}
            SourcesByMod=@{ct_dev='chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/_ct_diag_cursed_chest132.lua'}
            Signature='[ct:132] chest_of_trials #%d level=%s cap=%s census=%s is_server=%s%s'
            Bound='one receipt per actually constructed chest in the finite mission population'
            EmitterAnchors=@(@{Tokens=@('_safe_printf','(','String:[ct:132] chest_of_trials #%d level=%s cap=%s census=%s is_server=%s%s')})
            GuardAnchors=@(
                @{Tokens=@('local','actual','=','Core','.','appeared','(','_tracker',',','level_id',')')}
                @{Tokens=@('if','unit','~=','nil','then','_units','[','#','_units','+','1',']','=','unit','end')}
            )
        }
        @{
            Marker='[ct:132]'; ModId='ct_dev'
            ModTrees=@{ct_dev='99cb6bf8cdd5bda7b671f364bacf837ddffdd8e0'}
            SourcesByMod=@{ct_dev='chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/_ct_diag_cursed_chest132.lua'}
            Signature='[ct:132] reconcile level=%s alive=%d cap=%d over=%d pruned=%d unprunable=%d (issue 132 / issue 60 cross-path cap)'
            Bound='one over-cap reconciliation receipt from the mission-generation one-shot finalize path'
            EmitterAnchors=@(@{Tokens=@('_safe_printf','(','String:[ct:132] reconcile level=%s alive=%d cap=%d over=%d pruned=%d unprunable=%d (issue 132 / issue 60 cross-path cap)')})
            GuardAnchors=@(
                @{Tokens=@('local','classification',',','actual','=','Core','.','finalize','(','_tracker',',','level_id',',','cap',',','census',')')}
                @{Tokens=@('if','not','classification','then','return','nil','end')}
                @{Tokens=@('if','plan','.','over_n','<=','0','then','return','end')}
            )
        }
        @{
            Marker='[gt:753]'; ModId='gt_dev'
            ModTrees=@{gt_dev='1e8c7a9e56a3c360a89f920a2372366cc121ae9e'}
            SourcesByMod=@{gt_dev='general_tweaker_dev/scripts/mods/general_tweaker_dev/_gt_diag_disconnect_failure.lua'}
            Signature='[gt:753] edge=steam_check steam_connected=%s backend_disconnected=%s observed=%s'
            Bound='one receipt per observed Steam connection-state edge; unchanged title-network checks are silent'
            EmitterAnchors=@(
                @{Tokens=@('_emit','(','String:edge=steam_check steam_connected=%s backend_disconnected=%s observed=%s')}
                @{Tokens=@('pcall','(','engine_printf',',','String:[gt:753] ','..','fmt',',','...',')')}
            )
            GuardAnchors=@(@{Tokens=@('if','Policy','.','steam_transition','(','previous',',','connected',')','then')})
        }
        @{
            Marker='[gt:753]'; ModId='gt_dev'
            ModTrees=@{gt_dev='1e8c7a9e56a3c360a89f920a2372366cc121ae9e'}
            SourcesByMod=@{gt_dev='general_tweaker_dev/scripts/mods/general_tweaker_dev/_gt_diag_disconnect_failure.lua'}
            Signature='[gt:753] edge=playfab_disconnect steam_connected=%s backend_disconnected=%s last_reason=%s observed=%s'
            Bound='one receipt per observed backend false-to-true disconnected edge'
            EmitterAnchors=@(
                @{Tokens=@('_emit','(','String:edge=playfab_disconnect steam_connected=%s backend_disconnected=%s last_reason=%s observed=%s')}
                @{Tokens=@('pcall','(','engine_printf',',','String:[gt:753] ','..','fmt',',','...',')')}
            )
            GuardAnchors=@(@{Tokens=@('if','Policy','.','backend_disconnected_transition','(','previous',',','current',')','then')})
        }
        @{
            Marker='[gt:753]'; ModId='gt_dev'
            ModTrees=@{gt_dev='1e8c7a9e56a3c360a89f920a2372366cc121ae9e'}
            SourcesByMod=@{gt_dev='general_tweaker_dev/scripts/mods/general_tweaker_dev/_gt_diag_disconnect_failure.lua'}
            Signature='[gt:753] edge=network_client reason=%s channel_before=%s channel_after=%s steam_connected=%s backend_disconnected=%s observed=%s'
            Bound='one receipt per observed network-client failure edge; unchanged update frames are silent'
            EmitterAnchors=@(
                @{Tokens=@('_emit','(','String:edge=network_client reason=%s channel_before=%s channel_after=%s steam_connected=%s backend_disconnected=%s observed=%s')}
                @{Tokens=@('pcall','(','engine_printf',',','String:[gt:753] ','..','fmt',',','...',')')}
            )
            GuardAnchors=@(@{Tokens=@('if','Policy','.','network_failure_transition','(','before_reason',',','after_reason',',','before_channel',',','after_channel',')','then')})
        }
        @{
            Marker='[gt:753]'; ModId='gt_dev'
            ModTrees=@{gt_dev='1e8c7a9e56a3c360a89f920a2372366cc121ae9e'}
            SourcesByMod=@{gt_dev='general_tweaker_dev/scripts/mods/general_tweaker_dev/_gt_diag_disconnect_failure.lua'}
            Signature='[gt:753] armed: steam_check=1 playfab_disconnect=1 network_client=1 transition_only=yes'
            Bound='one terminal armed receipt during module evaluation'
            EmitterAnchors=@(
                @{Tokens=@('_emit','(','String:armed: steam_check=1 playfab_disconnect=1 network_client=1 transition_only=yes',')')}
                @{Tokens=@('pcall','(','engine_printf',',','String:[gt:753] ','..','fmt',',','...',')')}
            )
            GuardAnchors=@(@{Tokens=@('mod','.','_gt753_disconnect_diagnostics','=','{')})
        }
        @{
            Marker='[gut:630]'; ModId='gut_dev'
            ModTrees=@{gut_dev=@('6c174643fef046dc8cb0edf79f9ff3a8143b30f2')}
            SourcesByMod=@{gut_dev='gui_tweaker_dev/scripts/mods/gui_tweaker_dev/_gut_dx12_fence630.lua'}
            Signature='[gut:630] frame_evidence draw=%d visible_rows=%s resource_candidates=%s'
            Bound='focus/tab/Weapons-expansion edge evidence under one absolute 48-row probe budget'
            EmitterAnchors=@(
                @{Tokens=@('log','(','string','.','format','(','String:frame_evidence draw=%d visible_rows=%s resource_candidates=%s')}
                @{Tokens=@('emit','(','String:[gut:630] ','..','message',')')}
                @{Source='gui_tweaker_dev/scripts/mods/gui_tweaker_dev/gui_tweaker_dev.lua';Tokens=@('emit','=','function','(','line',')','printf','(','String:%s',',','line',')','end')}
            )
            GuardAnchors=@(
                @{Tokens=@('local','DEFAULT_LINE_CAP','=','48')}
                @{Tokens=@('if','state','.','lines','>=','state','.','line_cap','then')}
                @{Tokens=@('if','state','.','pending_frame_evidence','then')}
                @{Tokens=@('state','.','pending_frame_evidence','=','false')}
            )
        }
        @{
            Marker='[gt:347]'; ModId='gt_dev'
            ModTrees=@{gt_dev='1e8c7a9e56a3c360a89f920a2372366cc121ae9e'}
            SourcesByMod=@{gt_dev='general_tweaker_dev/scripts/mods/general_tweaker_dev/_gt_bot_pickups.lua'}
            Signature='[gt:347] phase=%s '
            Bound='one signature-deduplicated phase row under the explicit probe 16-record cap'
            EmitterAnchors=@(@{Tokens=@('pcall','(','printf',',','String:[gt:347] phase=%s ','..','fmt')})
            GuardAnchors=@(
                @{Source='general_tweaker_dev/scripts/mods/general_tweaker_dev/_gt_chest_pickup_probe_core.lua';Tokens=@('M','.','MAX_RECORDS','=','16')}
                @{Source='general_tweaker_dev/scripts/mods/general_tweaker_dev/_gt_chest_pickup_probe_core.lua';Tokens=@('if','not','state','.','armed','or','state','.','count','>=','M','.','MAX_RECORDS','then')}
            )
        }
        @{
            Marker='[gt:347]'; ModId='gt_dev'
            ModTrees=@{gt_dev='1e8c7a9e56a3c360a89f920a2372366cc121ae9e'}
            SourcesByMod=@{gt_dev='general_tweaker_dev/scripts/mods/general_tweaker_dev/_gt_bot_pickups.lua'}
            Signature='[gt:347] trace complete records=%d classifications=%d'
            Bound='one terminal cap row when the explicit probe reaches its 16-record budget'
            EmitterAnchors=@(@{Tokens=@('pcall','(','printf',',','String:[gt:347] trace complete records=%d classifications=%d')})
            GuardAnchors=@(
                @{Source='general_tweaker_dev/scripts/mods/general_tweaker_dev/_gt_chest_pickup_probe_core.lua';Tokens=@('if','capped','then','state','.','armed','=','false','end')}
                @{Tokens=@('if','capped','then')}
            )
        }
        @{
            Marker='[gt:347]'; ModId='gt_dev'
            ModTrees=@{gt_dev='1e8c7a9e56a3c360a89f920a2372366cc121ae9e'}
            SourcesByMod=@{gt_dev='general_tweaker_dev/scripts/mods/general_tweaker_dev/_gt_bot_pickups.lua'}
            Signature='[gt:347] ARMED max_records=%d max_classifications=%d instant_pickup=%s greedy_pickup=%s'
            Bound='one armed receipt per explicit /gt_chest_pickup_probe invocation'
            EmitterAnchors=@(@{Tokens=@('pcall','(','printf',',','String:[gt:347] ARMED max_records=%d max_classifications=%d instant_pickup=%s greedy_pickup=%s')})
            GuardAnchors=@(
                @{Tokens=@('mod',':','command','(','String:gt_chest_pickup_probe')}
                @{Tokens=@('_gt347_core','.','arm','(','_gt347_state',')')}
            )
        }
        @{
            Marker='[gt:1143]'; ModId='gt_dev'
            ModTrees=@{gt_dev='1e8c7a9e56a3c360a89f920a2372366cc121ae9e'}
            SourcesByMod=@{gt_dev='general_tweaker_dev/scripts/mods/general_tweaker_dev/_gt_dev_heal.lua'}
            Signature='[gt:1143] heal result=%s route=%s before=%s after=%s max=%s wounded_before=%s wounded_after=%s elapsed=%.3f reason=%s record=%d'
            Bound='one terminal success, rejection, timeout, or lifecycle-cancel receipt per explicit /heal request transaction'
            EmitterAnchors=@(@{Tokens=@('printf','(','String:[gt:1143] heal result=%s route=%s before=%s after=%s max=%s ','..','String:wounded_before=%s wounded_after=%s elapsed=%.3f reason=%s record=%d')})
            GuardAnchors=@(
                @{Tokens=@('mod',':','command','(','String:heal',',','String:Restore your living hero to full permanent health and clear wounds',',','_request',')')}
                @{Tokens=@('if','pending','then','_reject','(','String:request_already_pending',')','return','end')}
                @{Tokens=@('pending','=','nil','_emit','(','String:ok')}
                @{Tokens=@('pending','=','nil','_emit','(','String:timeout')}
            )
        }
        @{
            Marker='[mp:607]'; ModId='mp'
            ModTrees=@{mp='9d00a1b341cb445fcb937c4ce128383021b16abb'}
            SourcesByMod=@{mp='modded_progression/scripts/mods/modded_progression/_mp_loot_diag_runtime.lua'}
            Signature='[mp:607] event=%s serial=%d flow=%s request=%s reason=%s chest=%s items=%d local_items=%d local_containers=%d local_uses=%d award_capable=%s open_capable=%s first_missing=%s backend=%s'
            Bound='one-mission observer events are persisted in a twelve-record bounded ledger'
            EmitterAnchors=@(
                @{Tokens=@('print_log','(','String:[mp:607] event=%s serial=%d flow=%s request=%s reason=%s chest=%s ')}
                @{Source='modded_progression/scripts/mods/modded_progression/modded_progression.lua';Tokens=@('print_log','=','printf')}
            )
            GuardAnchors=@(
                @{Tokens=@('LootDiag','.','MAX_RECORDS','~=','12')}
                @{Tokens=@('if','#','success_ledger','.','records','~=','LootDiag','.','MAX_RECORDS','then')}
            )
        }
        @{
            Marker='[cwv:1107]';ModId='character_weapon_variants';ModTrees=@{character_weapon_variants='fc363b4babf93a33330e34d5eeb545e7e9acc502'}
            SourcesByMod=@{character_weapon_variants='character_weapon_variants/scripts/mods/character_weapon_variants/_cwv_musket_ammo_pool.lua'}
            Signature='[cwv:1107] melee-slot musket reload drained %d round(s): reserve %d -> %d'
            Bound='at most one drain receipt per completed melee-slot reload transaction'
            EmitterAnchors=@(@{Tokens=@('pcall','(','printf',',','String:[cwv:1107] melee-slot musket reload drained %d round(s): reserve %d -> %d')})
            GuardAnchors=@(@{Tokens=@('if','drained','>','0','then')})
        }
        @{
            Marker='[gut:938]';ModId='gut_dev';ModTrees=@{gut_dev=@('6c174643fef046dc8cb0edf79f9ff3a8143b30f2')}
            SourcesByMod=@{gut_dev='gui_tweaker_dev/scripts/mods/gui_tweaker_dev/_gut_damage_numbers.lua'}
            Signature='[gut:938] rt skip: NetworkConstants.damage.max unavailable; policy checked against fallback %.2f'
            Bound='at most one fallback notice per explicit issue938 regression-check invocation'
            EmitterAnchors=@(@{Tokens=@('pcall','(','printf',',','String:[gut:938] rt skip: NetworkConstants.damage.max unavailable; policy checked against fallback %.2f')})
            GuardAnchors=@(@{Tokens=@('if','type','(','max_damage',')','~=','String:number','or','max_damage','<=','0','then')})
        }
        @{
            Marker='[ct:919]';ModId='ct_dev';ModTrees=@{ct_dev='99cb6bf8cdd5bda7b671f364bacf837ddffdd8e0'}
            SourcesByMod=@{ct_dev='chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/_ct_profile_snapshot.lua'}
            Signature='[ct:919] seq=%d phase=%s role=%s profile=%d effective_source=%s coins_local=%s coins_effective=%s miasma_disabled_local=%s miasma_disabled_effective=%s selected_curse="%s" selected_conflict=%s boon_local_count=%d boon_local=%s boon_effective_count=%d boon_effective=%s local_truncated=%d effective_truncated=%d'
            Bound='one terminal formatted snapshot or snapshot_error per explicit profile-snapshot transaction'
            EmitterAnchors=@(
                @{Tokens=@('String:[ct:919] seq=%d phase=%s role=%s profile=%d effective_source=%s coins_local=%s coins_effective=%s miasma_disabled_local=%s miasma_disabled_effective=%s selected_curse="%s" selected_conflict=%s boon_local_count=%d boon_local=%s boon_effective_count=%d boon_effective=%s local_truncated=%d effective_truncated=%d')}
                @{Tokens=@('pcall','(','printf',',','String:%s',',','Snapshot','.','format','(','result',',','sequence',')',')')}
            )
            GuardAnchors=@(@{Tokens=@('function','mod','.','_ct919_log_profile_snapshot','(','phase',',','profile_override',')')})
        }
        @{
            Marker='[ct:919]';ModId='ct_dev';ModTrees=@{ct_dev='99cb6bf8cdd5bda7b671f364bacf837ddffdd8e0'}
            SourcesByMod=@{ct_dev='chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/_ct_profile_snapshot.lua'}
            Signature='[ct:919] seq=%d snapshot_error=%s';Bound='one mutually exclusive error receipt per profile-snapshot transaction'
            EmitterAnchors=@(@{Tokens=@('pcall','(','printf',',','String:[ct:919] seq=%d snapshot_error=%s')})
            GuardAnchors=@(@{Tokens=@('if','not','ok','then')})
        }
        @{
            Marker='[cwv:786]';ModId='character_weapon_variants';ModTrees=@{character_weapon_variants='fc363b4babf93a33330e34d5eeb545e7e9acc502'}
            SourcesByMod=@{character_weapon_variants='character_weapon_variants/scripts/mods/character_weapon_variants/_cwv_combat_styles.lua'}
            Signature='[cwv:786] verdict %s peer=%s slot=%s family=%s style=%s edge=%s attempt=%d/%d terminal=%s detail=%s'
            Bound='one verdict per retry transition under the eight-attempt per-style-edge ledger'
            EmitterAnchors=@(@{Tokens=@('String:[cwv:786] verdict %s peer=%s slot=%s family=%s style=%s edge=%s attempt=%d/%d terminal=%s detail=%s')})
            GuardAnchors=@(@{Tokens=@('M','.','MAX_REMOTE_REFRESH_ATTEMPTS','=','8')})
        }
        @{
            Marker='[cwv:786]';ModId='character_weapon_variants';ModTrees=@{character_weapon_variants='fc363b4babf93a33330e34d5eeb545e7e9acc502'}
            SourcesByMod=@{character_weapon_variants='character_weapon_variants/scripts/mods/character_weapon_variants/_cwv_combat_styles.lua'}
            Signature='[cwv:786] rebuild queued peer=%s slot=%s family=%s style=%s edge=%s attempt=%d/%d'
            Bound='one queue receipt per retry transition under the eight-attempt per-style-edge ledger'
            EmitterAnchors=@(@{Tokens=@('String:[cwv:786] rebuild queued peer=%s slot=%s family=%s style=%s edge=%s attempt=%d/%d')})
            GuardAnchors=@(@{Tokens=@('M','.','MAX_REMOTE_REFRESH_ATTEMPTS','=','8')})
        }
        @{
            Marker='[cwv:786]';ModId='character_weapon_variants';ModTrees=@{character_weapon_variants='fc363b4babf93a33330e34d5eeb545e7e9acc502'}
            SourcesByMod=@{character_weapon_variants='character_weapon_variants/scripts/mods/character_weapon_variants/_cwv_combat_styles.lua'}
            Signature='[cwv:786] style rx peer=%s slot=%s family=%s style=%s source=%s changed=%s'
            Bound='one receive receipt per explicit synchronized style edge'
            EmitterAnchors=@(@{Tokens=@('pcall','(','printf',',','String:[cwv:786] style rx peer=%s slot=%s family=%s style=%s source=%s changed=%s')})
            GuardAnchors=@(@{Tokens=@('function','runtime',':','accept_style_edge','(','peer_id',',','slot_name',',','family_id',',','style_id',',','source',',','descriptor',')')})
        }
        @{
            Marker='[cwv:786]';ModId='character_weapon_variants';ModTrees=@{character_weapon_variants='fc363b4babf93a33330e34d5eeb545e7e9acc502'}
            SourcesByMod=@{character_weapon_variants='character_weapon_variants/scripts/mods/character_weapon_variants/_cwv_style_rewield.lua'}
            Signature='[cwv:786] style residency family=%s style=%s resource=%s resident=%s'
            Bound='signature-deduplicated residency evidence under an absolute 32-row cap'
            EmitterAnchors=@(@{Tokens=@('emit','(','deps',',','String:[cwv:786] style residency family=%s style=%s resource=%s resident=%s')})
            GuardAnchors=@(
                @{Tokens=@('M','.','RESIDENCY_PROBE_CAP','=','32')}
                @{Tokens=@('if','state','.','seen','[','key',']','or','state','.','count','>=','M','.','RESIDENCY_PROBE_CAP','then')}
            )
        }
        @{
            Marker='[cwv:645]';ModId='character_weapon_variants';ModTrees=@{character_weapon_variants='fc363b4babf93a33330e34d5eeb545e7e9acc502'}
            SourcesByMod=@{character_weapon_variants='character_weapon_variants/scripts/mods/character_weapon_variants/_cwv_combat_styles.lua'}
            Signature='[cwv:645] candidate=%s item=%s career=%s owner_event=%s sample=%d/%d reason=%s'
            Bound='signature-deduplicated candidate evidence under a 32-row per-candidate cap'
            EmitterAnchors=@(@{Tokens=@('String:[cwv:645] candidate=%s item=%s career=%s owner_event=%s sample=%d/%d reason=%s')})
            GuardAnchors=@(
                @{Tokens=@('count','>=','M','.','DIAGNOSTIC_EVENT_CAP','or','self','.','diagnostic_seen','[','key',']')}
                @{Tokens=@('M','.','DIAGNOSTIC_EVENT_CAP','=','32')}
            )
        }
        @{
            Marker='[ct:571-native]';ModId='ct_dev';ModTrees=@{ct_dev='99cb6bf8cdd5bda7b671f364bacf837ddffdd8e0'}
            SourcesByMod=@{ct_dev='chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/_ct_diag_tab_native533.lua'}
            Signature='[ct:571-native] %s';Bound='signature-deduplicated native layout census under an absolute 64-row cap'
            EmitterAnchors=@(@{Tokens=@('pcall','(','printf',',','String:[ct:571-native] %s',',','line',')')})
            GuardAnchors=@(
                @{Tokens=@('local','RECORD_CAP','=','64')}
                @{Tokens=@('if','records','>=','RECORD_CAP','or','seen','[','key',']','then','return','false','end')}
            )
        }
        @{
            Marker='[event-inject:393]';ModId='event_tweaker';ModTrees=@{event_tweaker='aecc40f6935dae8dd6ab47e102822fd1e8622d64'}
            SourcesByMod=@{event_tweaker='event_tweaker/scripts/mods/event_tweaker/_evt_diagnostics.lua'}
            Signature='[event-inject:393] settled verdict=%s evidence=%s | injected=[%s] max_intensity=%s decay_per_second=%s decay_delay=%s add_per_pct_dmg=%s delay_horde=%s delay_specials=%s delay_mini_patrol=%s cached_horde=%s cached_specials=%s cached_mini_patrol=%s'
            Bound='one settled receipt per weak-key Pacing instance'
            EmitterAnchors=@(@{Tokens=@('printf','(','String:[event-inject:393] settled verdict=%s evidence=%s | injected=[%s] max_intensity=%s decay_per_second=%s decay_delay=%s add_per_pct_dmg=%s delay_horde=%s delay_specials=%s delay_mini_patrol=%s cached_horde=%s cached_specials=%s cached_mini_patrol=%s')})
            GuardAnchors=@(
                @{Tokens=@('if','_issue393_seen','[','self',']','then','return','end')}
                @{Tokens=@('_issue393_seen','[','self',']','=','true')}
            )
        }
        @{
            Marker='[wt:388]';ModIds=@('wt','wt_dev');ModTrees=@{wt='322fbab2f0f6ee326e76eed75aaf2fa6b830e547';wt_dev='a16d16d0d43d3d4f4c32140361911ef713abdc81'}
            SourcesByMod=@{wt='weapon_tweaker/scripts/mods/weapon_tweaker/_wt_overcharge_presentation.lua';wt_dev='weapon_tweaker_dev/scripts/mods/weapon_tweaker_dev/_wt_overcharge_presentation.lua'}
            Signature='[wt:388] Deepwood overcharge HUD hook installed';Bound='one HUD-hook installation receipt per module lifetime'
            EmitterAnchors=@(@{Tokens=@('printf','(','String:[wt:388] Deepwood overcharge HUD hook installed',')')})
            GuardAnchors=@(
                @{Tokens=@('if','_hud_hook_installed','then','return','end')}
                @{Tokens=@('_hud_hook_installed','=','true')}
            )
        }
        @{
            Marker='[wt:388]';ModIds=@('wt','wt_dev');ModTrees=@{wt='322fbab2f0f6ee326e76eed75aaf2fa6b830e547';wt_dev='a16d16d0d43d3d4f4c32140361911ef713abdc81'}
            SourcesByMod=@{wt='weapon_tweaker/scripts/mods/weapon_tweaker/_wt_overcharge_presentation.lua';wt_dev='weapon_tweaker_dev/scripts/mods/weapon_tweaker_dev/_wt_overcharge_presentation.lua'}
            Signature='[wt:388] Deepwood overcharge profile applied career=%s transport=owner-authoritative';Bound='one apply receipt per inactive-to-active extension transition'
            EmitterAnchors=@(@{Tokens=@('printf','(','String:[wt:388] Deepwood overcharge profile applied career=%s transport=owner-authoritative')})
            GuardAnchors=@(
                @{Tokens=@('if','_active_ext','==','ext','then','return','end')}
                @{Tokens=@('_active_unit',',','_active_ext',',','_baseline','=','player_unit',',','ext',',','_capture','(','ext',')')}
            )
        }
        @{
            Marker='[wt:388]';ModIds=@('wt','wt_dev');ModTrees=@{wt='322fbab2f0f6ee326e76eed75aaf2fa6b830e547';wt_dev='a16d16d0d43d3d4f4c32140361911ef713abdc81'}
            SourcesByMod=@{wt='weapon_tweaker/scripts/mods/weapon_tweaker/_wt_overcharge_presentation.lua';wt_dev='weapon_tweaker_dev/scripts/mods/weapon_tweaker_dev/_wt_overcharge_presentation.lua'}
            Signature='[wt:388] Deepwood overcharge profile restored';Bound='one restore receipt per active-to-inactive extension transition'
            EmitterAnchors=@(@{Tokens=@('printf','(','String:[wt:388] Deepwood overcharge profile restored',')')})
            GuardAnchors=@(
                @{Tokens=@('if','not','ext','or','not','baseline','then','return','end')}
                @{Tokens=@('_abandon','(',')')}
            )
        }
        @{
            Marker='[cwv:317]';ModId='character_weapon_variants';ModTrees=@{character_weapon_variants='fc363b4babf93a33330e34d5eeb545e7e9acc502'}
            SourcesByMod=@{character_weapon_variants='character_weapon_variants/scripts/mods/character_weapon_variants/cwv_dev_anim_picker.lua'}
            Signature='[cwv:317] ==== CWV 3P animation picker ====';Bound='one header per explicit finite dump command invocation'
            EmitterAnchors=@(@{Tokens=@('pcall','(','printf',',','String:[cwv:317] ==== CWV 3P animation picker ====')})
            GuardAnchors=@(@{Tokens=@('mod',':','command','(','String:cwv_dump_anim_picks',',','String:Dump saved CWV third-person animation picks',',','M','.','dump',')')})
        }
        @{
            Marker='[cwv:317]';ModId='character_weapon_variants';ModTrees=@{character_weapon_variants='fc363b4babf93a33330e34d5eeb545e7e9acc502'}
            SourcesByMod=@{character_weapon_variants='character_weapon_variants/scripts/mods/character_weapon_variants/cwv_dev_anim_picker.lua'}
            Signature='[cwv:317] %s';Bound='one label per finite authored animation-picker entry per explicit dump invocation'
            EmitterAnchors=@(@{Tokens=@('pcall','(','printf',',','String:[cwv:317] %s',',','entry','.','label',')')})
            GuardAnchors=@(@{Tokens=@('for','_',',','entry','in','ipairs','(','_ENTRIES',')','do')})
        }
        @{
            Marker='[cwv:317]';ModId='character_weapon_variants';ModTrees=@{character_weapon_variants='fc363b4babf93a33330e34d5eeb545e7e9acc502'}
            SourcesByMod=@{character_weapon_variants='character_weapon_variants/scripts/mods/character_weapon_variants/cwv_dev_anim_picker.lua'}
            Signature='[cwv:317]   %s = %q,';Bound='one row per finite authored source event with a changed value per explicit dump invocation'
            EmitterAnchors=@(@{Tokens=@('pcall','(','printf',',','String:[cwv:317]   %s = %q,',',','source_event',',','value',')')})
            GuardAnchors=@(@{Tokens=@('for','_',',','source_event','in','ipairs','(','_SOURCE_EVENTS',')','do')})
        }
        @{
            Marker='[cwv:317]';ModId='character_weapon_variants';ModTrees=@{character_weapon_variants='fc363b4babf93a33330e34d5eeb545e7e9acc502'}
            SourcesByMod=@{character_weapon_variants='character_weapon_variants/scripts/mods/character_weapon_variants/cwv_dev_anim_picker.lua'}
            Signature='[cwv:317] ==== end ====';Bound='one terminal row per explicit finite dump command invocation'
            EmitterAnchors=@(@{Tokens=@('pcall','(','printf',',','String:[cwv:317] ==== end ====',')')})
            GuardAnchors=@(@{Tokens=@('function','M','.','dump','(',')')})
        }
        @{
            Marker='[ct:288]';ModId='ct_dev';ModTrees=@{ct_dev='99cb6bf8cdd5bda7b671f364bacf837ddffdd8e0'}
            SourcesByMod=@{ct_dev='chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/_ct_boon_balance.lua'}
            Signature='[ct:288] %s';Bound='finite authored template/active-state census per explicit verify command invocation'
            EmitterAnchors=@(@{Tokens=@('pcall','(','printf',',','String:[ct:288] %s')})
            GuardAnchors=@(@{Tokens=@('mod',':','command','(','String:ct_verify_anath_raema')})
        }
        @{
            Marker='[ct:288]';ModId='ct_dev';ModTrees=@{ct_dev='99cb6bf8cdd5bda7b671f364bacf837ddffdd8e0'}
            SourcesByMod=@{ct_dev='chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/_ct_meta_trait_boons.lua'}
            Signature='[ct:288] add parent=%s child=%s stat=%s mult=%s event=%s n=%d';Bound='absolute eight-row add-boundary diagnostic cap'
            EmitterAnchors=@(@{Tokens=@('pcall','(','printf',',','String:[ct:288] add parent=%s child=%s stat=%s mult=%s event=%s n=%d')})
            GuardAnchors=@(
                @{Tokens=@('CT_ANATH_RAEMA_ADD_DIAG_COUNT','=','(','CT_ANATH_RAEMA_ADD_DIAG_COUNT','or','0',')','+','1')}
                @{Tokens=@('if','CT_ANATH_RAEMA_ADD_DIAG_COUNT','<=','8','then')}
            )
        }
        @{
            Marker='[gut:250]';ModId='gut_dev';ModTrees=@{gut_dev=@('6c174643fef046dc8cb0edf79f9ff3a8143b30f2')}
            SourcesByMod=@{gut_dev='gui_tweaker_dev/scripts/mods/gui_tweaker_dev/_gut_tab_talent_refresh.lua'}
            Signature='[gut:250] career=%s active=%s tiers=%s duplicates=%d unmapped=%d repair=%d/%d';Bound='signature-deduplicated talent repairs under the policy absolute log cap'
            EmitterAnchors=@(@{Tokens=@('pcall','(','printf',',','String:[gut:250] career=%s active=%s tiers=%s duplicates=%d unmapped=%d repair=%d/%d')})
            GuardAnchors=@(
                @{Tokens=@('if','not','logged','[','signature',']','and','log_count','<','Policy','.','MAX_LOGS','then')}
                @{Tokens=@('logged','[','signature',']','=','true')}
            )
        }
        @{
            Marker='[ct:141]';ModId='ct_dev';ModTrees=@{ct_dev='99cb6bf8cdd5bda7b671f364bacf837ddffdd8e0'}
            SourcesByMod=@{ct_dev='chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/_ct_resume_audit.lua'}
            Signature='[ct:141] audit=%d/%d reason=%s controller=%s run_state=%s server=%s config=%d/%d values=%d progress=%d/%d values=%d shared=%s full_sync=%s player_read=%s/%s/%s player_write=%s/%s/%s config_missing=%s progress_missing=%s mutation=false';Bound='absolute six-row session budget with two manual slots reserved'
            EmitterAnchors=@(@{Tokens=@('printf','(','String:[ct:141] audit=%d/%d reason=%s controller=%s run_state=%s server=%s config=%d/%d values=%d progress=%d/%d values=%d shared=%s full_sync=%s player_read=%s/%s/%s player_write=%s/%s/%s config_missing=%s progress_missing=%s mutation=false')})
            GuardAnchors=@(
                @{Tokens=@('local','CAP',',','MANUAL_RESERVE',',','captures','=','6',',','2',',','0')}
                @{Tokens=@('if','captures','>=','budget','then','return','end')}
            )
        }
        @{
            Marker='[gut:257]';ModId='gut_dev';ModTrees=@{gut_dev=@('6c174643fef046dc8cb0edf79f9ff3a8143b30f2')}
            SourcesByMod=@{gut_dev='gui_tweaker_dev/scripts/mods/gui_tweaker_dev/_gut_cutscenes.lua'}
            Signature='[gut:257] seq=%s phase=%s level=%s disposition=%s skip_next=%s guard=%s active_camera=%s on_activate=%s on_skip=%s hud=%s letterbox=%s fade_in=%s hold=%s fade_out=%s auto=%s capped=%s';Bound='absolute 32-event cap plus one terminal cap row per cutscene-system generation'
            EmitterAnchors=@(@{Tokens=@('_printf','(','String:[gut:257] seq=%s phase=%s level=%s disposition=%s skip_next=%s guard=%s active_camera=%s on_activate=%s on_skip=%s hud=%s letterbox=%s fade_in=%s hold=%s fade_out=%s auto=%s capped=%s')})
            GuardAnchors=@(
                @{Source='gui_tweaker_dev/scripts/mods/gui_tweaker_dev/_gut_cutscene_probe257.lua';Tokens=@('max_events','=','32')}
                @{Source='gui_tweaker_dev/scripts/mods/gui_tweaker_dev/_gut_cutscene_probe257.lua';Tokens=@('if','state','.','count','>=','M','.','max_events','then')}
            )
        }
        @{
            Marker='[gut:245]';ModId='gut_dev';ModTrees=@{gut_dev=@('6c174643fef046dc8cb0edf79f9ff3a8143b30f2')}
            SourcesByMod=@{gut_dev='gui_tweaker_dev/scripts/mods/gui_tweaker_dev/_gut_tab_property_refresh.lua'}
            Signature='[gut:245] slot=%s backend_id=%s properties=%s refresh=%d/%d';Bound='shared absolute live-loadout refresh log cap'
            EmitterAnchors=@(@{Tokens=@('_printf','(','String:[gut:245] slot=%s backend_id=%s properties=%s refresh=%d/%d')})
            GuardAnchors=@(
                @{Tokens=@('if','log_count','<','Policy','.','MAX_LOGS','then')}
                @{Tokens=@('log_count','=','log_count','+','1')}
            )
        }
        @{
            Marker='[ct:919]';ModId='ct_dev';ModTrees=@{ct_dev='99cb6bf8cdd5bda7b671f364bacf837ddffdd8e0'}
            SourcesByMod=@{ct_dev='chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/_ct_dev_mission.lua'}
            Signature='[ct:919] registered profile diagnostic with Mod Tweaker';Bound='one registration receipt from the once-per-load on_all_mods_loaded callback'
            EmitterAnchors=@(@{Tokens=@('pcall','(','printf',',','String:[ct:919] registered profile diagnostic with Mod Tweaker',')')})
            GuardAnchors=@(@{Tokens=@('mod','.','on_all_mods_loaded','=','function','(',')')})
        }
        @{
            Marker='[ct:288]';ModId='ct_dev';ModTrees=@{ct_dev='99cb6bf8cdd5bda7b671f364bacf837ddffdd8e0'}
            SourcesByMod=@{ct_dev='chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/_ct_boon_balance.lua'}
            Signature='[ct:288] setting=%s template_child=%s stat=%s multiplier=%s event=%s';Bound='one template-setting census row per explicit verify command invocation'
            EmitterAnchors=@(
                @{Tokens=@('string','.','format','(','String:setting=%s template_child=%s stat=%s multiplier=%s event=%s')}
                @{Tokens=@('pcall','(','printf',',','String:[ct:288] %s',',','setting_line',')')}
            )
            GuardAnchors=@(@{Tokens=@('mod',':','command','(','String:ct_verify_anath_raema')})
        }
        @{
            Marker='[ct:288]';ModId='ct_dev';ModTrees=@{ct_dev='99cb6bf8cdd5bda7b671f364bacf837ddffdd8e0'}
            SourcesByMod=@{ct_dev='chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/_ct_boon_balance.lua'}
            Signature='[ct:288] active[%d] child=%s stat=%s multiplier=%s event=%s';Bound='one row per finite active matching buff in an explicit verify command census'
            EmitterAnchors=@(
                @{Tokens=@('string','.','format','(','String:active[%d] child=%s stat=%s multiplier=%s event=%s')}
                @{Tokens=@('pcall','(','printf',',','String:[ct:288] %s',',','active_line',')')}
            )
            GuardAnchors=@(@{Tokens=@('for','_',',','buff','in','pairs','(','be','.','_buffs','or','{','}',')','do')})
        }
        @{
            Marker='[ct:288]';ModId='ct_dev';ModTrees=@{ct_dev='99cb6bf8cdd5bda7b671f364bacf837ddffdd8e0'}
            SourcesByMod=@{ct_dev='chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/_ct_boon_balance.lua'}
            Signature='[ct:288] active_count=%d total_reload_time_scale=%s expected_trait_scale=0.5';Bound='one terminal active-count row per explicit verify command invocation'
            EmitterAnchors=@(
                @{Tokens=@('string','.','format','(','String:active_count=%d total_reload_time_scale=%s expected_trait_scale=0.5')}
                @{Tokens=@('pcall','(','printf',',','String:[ct:288] %s',',','total_line',')')}
            )
            GuardAnchors=@(@{Tokens=@('mod',':','command','(','String:ct_verify_anath_raema')})
        }
        @{
            Marker='[ct:288]';ModId='ct_dev';ModTrees=@{ct_dev='99cb6bf8cdd5bda7b671f364bacf837ddffdd8e0'}
            SourcesByMod=@{ct_dev='chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/_ct_boon_balance.lua'}
            Signature='[ct:288] active=unavailable (enter the keep/mission and wield the trait weapon)';Bound='one mutually exclusive early terminal row per explicit verify command invocation'
            EmitterAnchors=@(@{Tokens=@('pcall','(','printf',',','String:[ct:288] active=unavailable (enter the keep/mission and wield the trait weapon)',')')})
            GuardAnchors=@(@{Tokens=@('if','not','be','then')})
        }
    )

    # Literal complex routes that are real printf evidence but deliberately
    # remain unbounded. Discovery corrects the failure reason without granting
    # a finite-output exemption.
    ReceiptDiscoveryOverrides = @(
        @{
            ModId='WOC';ModTree='6a96c90be91f06f8230c1c3605adee71a38d2355'
            Source='weapons_of_chaos/scripts/mods/weapons_of_chaos/_woc_blightreaper_audio.lua';Marker='[WOC:633]'
            Signature='[WOC:633] audio contract inspect_event=%s inspect_bank=%s inspect_package=%s ambient_event=%s ambient_bank=%s ambient_status=diagnostic force_load=false network=false probe_runs=%d/%d chat=false'
            EmitterAnchors=@(
                @{Tokens=@('log','(','String:[WOC:633] audio contract inspect_event=%s inspect_bank=%s inspect_package=%s ambient_event=%s ambient_bank=%s ambient_status=diagnostic force_load=false network=false probe_runs=%d/%d chat=false')}
                @{Tokens=@('pcall','(','printf_fn',',','format',',','...',')')}
            )
        }
        @{
            ModId='WOC';ModTree='6a96c90be91f06f8230c1c3605adee71a38d2355';Source='weapons_of_chaos/scripts/mods/weapons_of_chaos/_woc_blightreaper_audio.lua';Marker='[WOC:633]'
            Signature='[WOC:633] inspect started event=%s bank=%s package_state=%s max_seconds=%d owner=local-1p chat=false'
            EmitterAnchors=@(@{Tokens=@('log','(','String:[WOC:633] inspect started event=%s bank=%s package_state=%s max_seconds=%d owner=local-1p chat=false')})
        }
        @{
            ModId='WOC';ModTree='6a96c90be91f06f8230c1c3605adee71a38d2355';Source='weapons_of_chaos/scripts/mods/weapons_of_chaos/_woc_blightreaper_audio.lua';Marker='[WOC:633]'
            Signature='[WOC:633] inspect SKIP reason=%s event=%s package=%s chat=false'
            EmitterAnchors=@(@{Tokens=@('String:[WOC:633] inspect SKIP reason=%s event=%s package=%s chat=false')})
        }
        @{
            ModId='WOC';ModTree='6a96c90be91f06f8230c1c3605adee71a38d2355';Source='weapons_of_chaos/scripts/mods/weapons_of_chaos/_woc_blightreaper_audio.lua';Marker='[WOC:633]'
            Signature='[WOC:633] ambient probe started runs=%d/%d event=%s bank=%s id=%s source=local-3p max_seconds=%d force_load=false network=false chat=false'
            EmitterAnchors=@(@{Tokens=@('log','(','String:[WOC:633] ambient probe started runs=%d/%d event=%s bank=%s id=%s source=local-3p max_seconds=%d force_load=false network=false chat=false')})
        }
        @{
            ModId='WOC';ModTree='6a96c90be91f06f8230c1c3605adee71a38d2355';Source='weapons_of_chaos/scripts/mods/weapons_of_chaos/_woc_blightreaper_audio.lua';Marker='[WOC:633]'
            Signature='[WOC:633] ambient probe SKIP reason=%s runs=%d/%d event=%s bank=%s force_load=false network=false chat=false'
            EmitterAnchors=@(@{Tokens=@('log','(','String:[WOC:633] ambient probe SKIP reason=%s runs=%d/%d event=%s bank=%s force_load=false network=false chat=false')})
        }
        @{
            ModId='WOC';ModTree='6a96c90be91f06f8230c1c3605adee71a38d2355';Source='weapons_of_chaos/scripts/mods/weapons_of_chaos/_woc_blightreaper_audio.lua';Marker='[WOC:633]'
            Signature='[WOC:633] audio stop kind=%s reason=%s event=%s id=%s stopped=%s chat=false'
            EmitterAnchors=@(@{Tokens=@('log','(','String:[WOC:633] audio stop kind=%s reason=%s event=%s id=%s stopped=%s chat=false')})
        }
    )

    # Route-local exceptions for finite emitters whose callable/guard proof
    # crosses helpers. Every entry is pinned to the deployed mod subtree and
    # exact token anchors. These authorize only Signature, never Marker-wide
    # siblings.
    ReceiptRouteOverrides = @(
        @{
            ModId='gut_dev'; ModTrees=@('6c174643fef046dc8cb0edf79f9ff3a8143b30f2')
            Source='gui_tweaker_dev/scripts/mods/gui_tweaker_dev/_ba_compendium_tabs.lua'
            Marker='[gut:217]'
            Signature='[gut:217] compendium tabs injected into HeroWindowPanelConsole definitions (Armory, Bestiary)'
            Bound='one successful definition-table injection per session'
            EmitterAnchors=@(
                @{Tokens=@('printf','(','String:[gut:217] compendium tabs injected into HeroWindowPanelConsole definitions (Armory, Bestiary)',')')}
            )
            GuardAnchors=@(
                @{Tokens=@('if','_injected','then','return')}
                @{Tokens=@('_injected','=','true')}
            )
        }
        @{
            ModId='gut_dev'; ModTrees=@('6c174643fef046dc8cb0edf79f9ff3a8143b30f2')
            Source='gui_tweaker_dev/scripts/mods/gui_tweaker_dev/_gut_native_loadouts.lua'
            Marker='[gut_dev:NATIVE_LOADOUTS]'
            Signature='[gut_dev:NATIVE_LOADOUTS] #375 selected-read career=%s caller=%s requested=%s resolved=%s selected=%s row=[melee=%s ranged=%s] canonical=[melee=%s ranged=%s] served=[slot=%s value=%s source=%s]'
            Bound='SelectedLoadoutTraceCore deduplicates and caps this exact selected-read route at 128 records'
            EmitterAnchors=@(
                @{Tokens=@('printf','(','String:[gut_dev:NATIVE_LOADOUTS] #375 selected-read career=%s caller=%s requested=%s resolved=%s selected=%s row=[melee=%s ranged=%s] canonical=[melee=%s ranged=%s] served=[slot=%s value=%s source=%s]')}
            )
            GuardAnchors=@(
                @{Tokens=@('SelectedLoadoutTraceCore','.','new','(','128',')')}
                @{Tokens=@('if','_selected_loadout_trace',':','record','(','snapshot',')','then')}
            )
        }
        @{
            ModId='wt_dev'; ModTree='a16d16d0d43d3d4f4c32140361911ef713abdc81'
            Source='weapon_tweaker_dev/scripts/mods/weapon_tweaker_dev/_wt_weapon_action_lifecycle.lua'
            Marker='[wt:661]'
            Signature='[wt:661] wield-boundary item=%s career=%s template=%s result=%s trace=%d/%d'
            Bound='signature deduplication under an absolute 64-record cap'
            EmitterAnchors=@(
                @{Tokens=@('pcall','(','printf',',','String:[wt:661] wield-boundary item=%s career=%s template=%s result=%s trace=%d/%d')}
            )
            GuardAnchors=@(
                @{Tokens=@('emitted','>=','MAX_DIAGNOSTICS')}
                @{Tokens=@('seen','[','signature',']','=','true')}
                @{Tokens=@('emitted','=','emitted','+','1')}
            )
        }
        @{
            ModId='character_weapon_variants'; ModTree='fc363b4babf93a33330e34d5eeb545e7e9acc502'
            Source='character_weapon_variants/scripts/mods/character_weapon_variants/_cwv_item_registration_owner.lua'
            Marker='[cwv:567]'; AddRoute=$true
            Signature='[cwv:567] cache_invalidated=%s rebuild=%s skin=%s association=%s owner=%s combination=%s rarity=%s cache_item=%s'
            Bound='exactly one receipt for each of the three finite authored issue-567 skin keys after deferred owner registration'
            EmitterAnchors=@(
                @{Tokens=@('pcall','(','printf',',','String:[cwv:567] cache_invalidated=%s rebuild=%s skin=%s association=%s owner=%s combination=%s rarity=%s cache_item=%s')}
            )
            GuardAnchors=@(
                @{Tokens=@('mod','.', '_cwv567_skin_keys','=','{','String:cwv_es_sword_and_mace_wpn_emp_sword_02_t1_wpn_emp_mace_03_t1',',','String:cwv_es_dual_maces_es_1h_mace_skin_02_runed_01',',','String:cwv_es_axe_shield_wpn_emp_shield_03__axe_02_t2',',','}')}
                @{Tokens=@('for','_',',','skin_key','in','ipairs','(','mod','.', '_cwv567_skin_keys',')','do')}
            )
        }
        @{
            ModId='cosmetics_tweaker'; ModTrees=@('ce5181e248d9f98ac41c484ac86fb244fe475add')
            Source='cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_la_bridge.lua'
            Marker='[cos:373]'; AddRoute=$true
            Signature='[cos:373] receiver coverage OK: no magic/runed shield family gaps'
            Bound='one latched boot validation pass; zero-gap terminal row occurs once'
            EmitterAnchors=@(
                @{Tokens=@('local','pf','=','rawget','(','_G',',','String:printf',')')}
                @{Tokens=@('pf','(','String:[cos:373] receiver coverage OK: no magic/runed shield family gaps',')')}
            )
            GuardAnchors=@(
                @{Tokens=@('if','_receiver_gap_report_done','then','return')}
                @{Tokens=@('_receiver_gap_report_done','=','true')}
            )
        }
        @{
            ModId='cosmetics_tweaker'; ModTrees=@('ce5181e248d9f98ac41c484ac86fb244fe475add')
            Source='cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_la_bridge.lua'
            Marker='[cos:373]'; AddRoute=$true
            Signature='[cos:373] RECEIVER-GAP skin=%s family=%s unit=%s (magic/runed shield has no paint receiver row - LA heraldry will dead-end)'
            Bound='one latched boot validation pass with ten detailed gap rows'
            EmitterAnchors=@(
                @{Tokens=@('pf','(','String:[cos:373] RECEIVER-GAP skin=%s family=%s unit=%s (magic/runed shield has no paint receiver row - LA heraldry will dead-end)')}
            )
            GuardAnchors=@(
                @{Tokens=@('_receiver_gap_report_done','=','true')}
                @{Tokens=@('local','cap','=','10')}
            )
        }
        @{
            ModId='cosmetics_tweaker'; ModTrees=@('ce5181e248d9f98ac41c484ac86fb244fe475add')
            Source='cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_la_bridge.lua'
            Marker='[cos:373]'; AddRoute=$true
            Signature='[cos:373] RECEIVER-GAP +%d more (capped at %d)'
            Bound='one latched boot validation pass with one overflow summary'
            EmitterAnchors=@(
                @{Tokens=@('pf','(','String:[cos:373] RECEIVER-GAP +%d more (capped at %d)')}
            )
            GuardAnchors=@(
                @{Tokens=@('_receiver_gap_report_done','=','true')}
                @{Tokens=@('local','cap','=','10')}
            )
        }
        @{
            ModId='cosmetics_tweaker'; ModTrees=@('ce5181e248d9f98ac41c484ac86fb244fe475add')
            Source='cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_cos_diagnostics.lua'
            Marker='[cos:704]'; AddRoute=$true
            Signature='[cos:704] summary inspected=%d suspects=%d emitted=%d truncated=%s signature_truncated=%s signature_bytes=%d'
            Bound='four signature-deduplicated captures, each capped at 56 emitted rows'
            EmitterAnchors=@(
                @{Tokens=@('local','emitter','=','rawget','(','_G',',','String:printf',')')}
                @{Tokens=@('pcall','(','emitter',',','format',',','...')}
                @{Tokens=@('emit','(','String:[cos:704] summary inspected=%d suspects=%d emitted=%d truncated=%s signature_truncated=%s signature_bytes=%d')}
            )
            GuardAnchors=@(
                @{Tokens=@('_issue704_capture_count','>=','_ISSUE704_CAPTURE_CAP')}
                @{Tokens=@('if','emitted','>=','_ISSUE704_ENTRY_CAP','then','return','false','end')}
            )
        }
        @{
            ModId='character_weapon_variants'; ModTree='fc363b4babf93a33330e34d5eeb545e7e9acc502'
            Source='character_weapon_variants/scripts/mods/character_weapon_variants/_cwv_smoke_bomb_probe.lua'
            Marker='[cwv:343]'; AddRoute=$true
            Signature='[cwv:343] status=%s base=%s area=%s pool=%d/%.6f healthy=%s exact_z_scale=%s registration_quarantined=%s'
            Bound='absolute three-run probe cap'
            EmitterAnchors=@(
                @{Tokens=@('String:[cwv:343] status=%s base=%s area=%s pool=%d/%.6f healthy=%s exact_z_scale=%s registration_quarantined=%s')}
                @{Tokens=@('pcall','(','printf',',','String:%s',',','line',')')}
            )
            GuardAnchors=@(
                @{Tokens=@('M','.','_runs','>=','M','.','MAX_RUNS')}
                @{Tokens=@('M','.','_runs','=','M','.','_runs','+','1')}
            )
        }
        @{
            ModId='crt'; ModTree='f142c181ef116b1cc49153791b8a67281b17e731'
            Source='career_tweaker/scripts/mods/career_tweaker/_crt_diagnostics.lua'
            Marker='[crt:699]'; AddRoute=$true
            Signature='[crt:699] icon active=true subject=%s buff=%s role=%s template=%s expected=%s icon=%s atlas=%s atlas_id=%s widget=%s widget_icon=%s semantic_match=%s numb_collision=%s hud_widgets=%d hud_capacity=%d hidebuffs=%s hidden=%s priority=%s'
            Bound='state-signature deduplication under an absolute 64-row helper cap'
            EmitterAnchors=@(
                @{Tokens=@('pcall','(','printf',',','format',',','...')}
                @{Tokens=@('_crt_fk_icon_log','(','String:[crt:699] icon active=true subject=%s buff=%s role=%s template=%s expected=%s icon=%s atlas=%s atlas_id=%s widget=%s widget_icon=%s semantic_match=%s numb_collision=%s hud_widgets=%d hud_capacity=%d hidebuffs=%s hidden=%s priority=%s')}
            )
            GuardAnchors=@(
                @{Tokens=@('_crt_fk_icon_log_count','>=','_CRT_FK_ICON_LOG_CAP')}
                @{Tokens=@('_crt_fk_icon_log_count','=','_crt_fk_icon_log_count','+','1')}
                @{Tokens=@('if','_crt_fk_icon_last','[','state_key',']','~=','signature','then')}
            )
        }
        @{
            ModId='cim_dev'; ModTree='c92e97f783517f91139414ed407aa6f529fad642'
            Source='crafting_in_modded_dev/scripts/mods/crafting_in_modded_dev/_cim_loadout_wire_owner.lua'
            Marker='[cim:921]'; AddRoute=$true
            Signature='[cim:921] dropped invalid rarity metadata source=%s peer=%s slot=%s value=%s count=%d/%d'
            Bound='shared absolute 24-row loadout-wire cap'
            EmitterAnchors=@(
                @{Tokens=@('print_line','(','String:[cim:921] dropped invalid rarity metadata source=%s peer=%s slot=%s value=%s count=%d/%d')}
                @{Source='crafting_in_modded_dev/scripts/mods/crafting_in_modded_dev/crafting_in_modded_dev.lua';Tokens=@('print_line','=','function','(','fmt',',','...',')','printf','(','fmt',',','...',')','end')}
            )
            GuardAnchors=@(
                @{Tokens=@('if','log_count','<','LOG_LIMIT','then')}
                @{Tokens=@('log_count','=','log_count','+','1')}
            )
        }
        @{
            ModId='cim_dev'; ModTree='c92e97f783517f91139414ed407aa6f529fad642'
            Source='crafting_in_modded_dev/scripts/mods/crafting_in_modded_dev/_cim_loadout_wire_owner.lua'
            Marker='[cim:921]'; AddRoute=$true
            Signature='[cim:921] rarity metadata source=%s peer=%s slot=%s prior=%s current=%s stored=%s->%s count=%d/%d'
            Bound='shared absolute 24-row loadout-wire cap'
            EmitterAnchors=@(
                @{Tokens=@('print_line','(','String:[cim:921] rarity metadata source=%s peer=%s slot=%s prior=%s current=%s stored=%s->%s count=%d/%d')}
                @{Source='crafting_in_modded_dev/scripts/mods/crafting_in_modded_dev/crafting_in_modded_dev.lua';Tokens=@('print_line','=','function','(','fmt',',','...',')','printf','(','fmt',',','...',')','end')}
            )
            GuardAnchors=@(
                @{Tokens=@('if','log_count','<','LOG_LIMIT')}
                @{Tokens=@('log_count','=','log_count','+','1')}
            )
        }
        @{
            ModId='cim_dev'; ModTree='c92e97f783517f91139414ed407aa6f529fad642'
            Source='crafting_in_modded_dev/scripts/mods/crafting_in_modded_dev/_cim_cw_trait_residency.lua'
            Marker='[cim:947]'; AddRoute=$true
            Signature='[cim:947] package=%s ref=%s state=%s detail=%s requests=%d'
            Bound='state-signature transition deduplication'
            EmitterAnchors=@(
                @{Tokens=@('print_line','(','String:[cim:947] package=%s ref=%s state=%s detail=%s requests=%d')}
                @{Source='crafting_in_modded_dev/scripts/mods/crafting_in_modded_dev/crafting_in_modded_dev.lua';Tokens=@('print_line','=','function','(','fmt',',','...',')','printf','(','fmt',',','...',')','end')}
            )
            GuardAnchors=@(
                @{Tokens=@('if','signature','~=','last_reported','then')}
                @{Tokens=@('last_reported','=','signature')}
            )
        }
        @{
            ModId='ct_dev'; ModTree='99cb6bf8cdd5bda7b671f364bacf837ddffdd8e0'
            Source='chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/_ct_diag_skull52.lua'
            Marker='[ct:skull52]'; AddRoute=$true
            Signature='[ct:skull52] %s'
            Bound='absolute 320 census plus 256 lifecycle rows, with lower per-session caps and signature deduplication'
            EmitterAnchors=@(
                @{Tokens=@('local','engine_printf','=','rawget','(','_G',',','String:printf',')')}
                @{Tokens=@('pcall','(','engine_printf',',','String:[ct:skull52] %s',',','line',')')}
            )
            GuardAnchors=@(
                @{Tokens=@('records','>=','CENSUS_RECORD_CAP_TOTAL')}
                @{Tokens=@('seen','[','key',']','=','true')}
                @{Tokens=@('lifecycle_records','>=','LIFECYCLE_RECORD_CAP_TOTAL')}
                @{Tokens=@('lifecycle_seen','[','key',']','=','true')}
            )
        }
        @{
            ModId='gt_dev'; ModTree='1e8c7a9e56a3c360a89f920a2372366cc121ae9e'
            Source='general_tweaker_dev/scripts/mods/general_tweaker_dev/_gt_bot_hazard_resistance.lua'
            Marker='[gt:488]'; AddRoute=$true
            Signature='[gt:488] bot-hazard type=%s milestone=%s active_before=%d active_after=%d damage_in=%.3f damage_out=%.3f record=%d/%d'
            Bound='signature-deduplicated hazard milestones under an absolute sixteen-row cap'
            EmitterAnchors=@(
                @{Tokens=@('local','_printf','=','rawget','(','_G',',','String:printf',')')}
                @{Tokens=@('pcall','(','_printf',',','String:[gt:488] bot-hazard type=%s milestone=%s active_before=%d active_after=%d damage_in=%.3f damage_out=%.3f record=%d/%d')}
            )
            GuardAnchors=@(
                @{Tokens=@('log_records','<','MAX_LOG_RECORDS')}
                @{Tokens=@('ledger','.','_logged','[','log_key',']','=','true')}
                @{Tokens=@('log_records','=','log_records','+','1')}
            )
        }
        @{
            ModId='gt_dev'; ModTree='1e8c7a9e56a3c360a89f920a2372366cc121ae9e'
            Source='general_tweaker_dev/scripts/mods/general_tweaker_dev/_gt_improved_bot_combat.lua'
            Marker='[gt:488]'; AddRoute=$true
            Signature='[gt:488] ratling-shield state=%d/%d wielded=%s wielded_template=%s wielded_shield=%s melee_template=%s melee_shield=%s blocking=%s projectile_hit=%s victim_self=%s taking_cover=%s input=%s mutation=0'
            Bound='signature-deduplicated Ratling/shield states under an absolute twelve-row cap'
            EmitterAnchors=@(
                @{Tokens=@('local','_printf','=','rawget','(','_G',',','String:printf',')')}
                @{Tokens=@('pcall','(','_printf',',','String:[gt:488] ratling-shield state=%d/%d wielded=%s wielded_template=%s wielded_shield=%s melee_template=%s melee_shield=%s blocking=%s projectile_hit=%s victim_self=%s taking_cover=%s input=%s mutation=0')}
            )
            GuardAnchors=@(
                @{Tokens=@('_shield_probe_count','>=','SHIELD_PROBE_CAP')}
                @{Tokens=@('_shield_probe_seen','[','signature',']','=','true')}
                @{Tokens=@('_shield_probe_count','=','_shield_probe_count','+','1')}
            )
        }
        @{
            ModId='WOC'; ModTree='6a96c90be91f06f8230c1c3605adee71a38d2355'
            Source='weapons_of_chaos/scripts/mods/weapons_of_chaos/_woc_boss_weapon_catalog.lua'
            Marker='[WOC:boss-catalog]'
            Signature='[WOC:boss-catalog] facet=authored id=%s issue=%s stage=%s status=%s registration_enabled=%s required=%s missing=%s'
            Bound='one finite seven-row catalogue per explicit command invocation or module-load census'
            EmitterAnchors=@(
                @{Tokens=@('printf','(','String:[WOC:boss-catalog] facet=authored id=%s issue=%s stage=%s status=%s registration_enabled=%s required=%s missing=%s')}
                @{Source='weapons_of_chaos/scripts/mods/weapons_of_chaos/weapons_of_chaos.lua';Tokens=@('mod',':','command','(','String:woc_boss_catalog')}
            )
            GuardAnchors=@(
                @{Tokens=@('local','results','=','M','.','runtime_authored_snapshot','(',')')}
                @{Tokens=@('for','i','=','1',',','#','results','do')}
            )
        }
        @{
            ModId='cosmetics_tweaker'; ModTree='ce5181e248d9f98ac41c484ac86fb244fe475add'
            Source='cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_cos_reikland_griffin.lua'
            Marker='[cos:656]'; AddRoute=$true
            Signature='[cos:656] registered skin=%s donor=%s vanilla_geometry=true enabled=%s'
            Bound='one successful registration receipt under the module-lifetime registered latch'
            EmitterAnchors=@(
                @{Tokens=@('local','engine_printf','=','rawget','(','_G',',','String:printf',')')}
                @{Tokens=@('pcall','(','engine_printf',',','String:[cos:656] registered skin=%s donor=%s vanilla_geometry=true enabled=%s')}
            )
            GuardAnchors=@(
                @{Tokens=@('if','M','.','registered','then','M','.','sync_toggle','(',')',';','return','true','end')}
                @{Tokens=@('M','.','registered','=','true')}
            )
        }
        @{
            ModId='character_weapon_variants'; ModTree='fc363b4babf93a33330e34d5eeb545e7e9acc502'
            Source='character_weapon_variants/scripts/mods/character_weapon_variants/_cwv_outrider_animation.lua'
            Marker='[cwv:760]'; AddRoute=$true
            Signature='[cwv:760] surface=%s career=%s event=%s result=%s source=%s evidence=%d/%d visual=unverified'
            Bound='signature-deduplicated evidence under an absolute sixteen-row cap'
            EmitterAnchors=@(
                @{Tokens=@('pcall','(','logger',',','String:[cwv:760] surface=%s career=%s event=%s result=%s source=%s evidence=%d/%d visual=unverified')}
                @{Source='character_weapon_variants/scripts/mods/character_weapon_variants/_cwv_core_templates.lua';Tokens=@('_om','.','outrider_animation','.','emit_evidence','(','printf')}
                @{Source='character_weapon_variants/scripts/mods/character_weapon_variants/_cwv_menu_preview_owner.lua';Tokens=@('_om','.','outrider_animation','.','emit_evidence','(','printf')}
                @{Source='character_weapon_variants/scripts/mods/character_weapon_variants/_cwv_husk_path.lua';Tokens=@('_om','.','outrider_animation','.','emit_evidence','(','printf')}
            )
            GuardAnchors=@(
                @{Tokens=@('evidence_seen','[','key',']','or','evidence_count','>=','M','.','EVIDENCE_LIMIT')}
                @{Tokens=@('evidence_seen','[','key',']','=','true')}
                @{Tokens=@('evidence_count','=','evidence_count','+','1')}
            )
        }
        @{
            ModId='ct_dev'; ModTree='99cb6bf8cdd5bda7b671f364bacf837ddffdd8e0'
            Source='chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/_ct_altar_reuse_owner.lua'
            Marker='[ct:xchar105]'
            Signature='[ct:xchar105] upgrade-altar slot=%s career=%s rarity=%s pre_key=%s post_key=%s %s'
            Bound='at most one receipt after the vanilla delegate returns in each _generate_upgraded_weapon transaction'
            EmitterAnchors=@(
                @{Tokens=@('pcall','(','printf',',','String:[ct:xchar105] upgrade-altar slot=%s career=%s rarity=%s pre_key=%s post_key=%s %s')}
            )
            GuardAnchors=@(
                @{Tokens=@('mod',':','hook','(','String:DeusChestExtension',',','String:_generate_upgraded_weapon',',','function')}
                @{Tokens=@('local','a',',','b','=','func','(','self',',','weapon',',','slot_name',',','rarity',',','eff_go_id',',','profile_index',',','career_index',')')}
                @{Tokens=@('return','a',',','b','end',')')}
            )
        }
        @{
            ModId='enemy_tweaker'; ModTree='86f2677612ffb4772100a42101a19dacf602191c'
            Source='enemy_tweaker/scripts/mods/enemy_tweaker/_et_enemy_modifiers.lua'
            Marker='[et:453]'; AddRoute=$true
            Signature='[et:453] modifier-audit reason=%s modifiers=%d template_missing=%d wire_missing=%d enhancement_missing=%d child_missing=%d child_wire_missing=%d function_missing=%d special=%d boss=%d elite=%d lord=%d behavior_changes=0'
            Bound='one summary per explicit /et_modifier_audit invocation'
            EmitterAnchors=@(
                @{Tokens=@('local','_printf','=','rawget','(','_G',',','String:printf',')','or','function','(',')','end')}
                @{Tokens=@('pcall','(','_printf',',','String:[et:453] modifier-audit reason=%s modifiers=%d template_missing=%d wire_missing=%d enhancement_missing=%d child_missing=%d child_wire_missing=%d function_missing=%d special=%d boss=%d elite=%d lord=%d behavior_changes=0')}
            )
            GuardAnchors=@(
                @{Tokens=@('mod',':','command','(','String:et_modifier_audit')}
                @{Tokens=@('local','summary','=','print_details','(','String:command',')')}
            )
        }
        @{
            ModId='enemy_tweaker'; ModTree='86f2677612ffb4772100a42101a19dacf602191c'
            Source='enemy_tweaker/scripts/mods/enemy_tweaker/_et_enemy_modifiers.lua'
            Marker='[et:453]'; AddRoute=$true
            Signature='[et:453] %s family=%s enhancement=%s buff=%s template=%s wire=%s enhancement_contains=%s chain_templates=%d chain_functions=%d chain_gaps=%d capped=%s'
            Bound='one finite fifteen-row catalogue per explicit /et_modifier_audit invocation'
            EmitterAnchors=@(
                @{Tokens=@('local','_printf','=','rawget','(','_G',',','String:printf',')','or','function','(',')','end')}
                @{Tokens=@('pcall','(','_printf',',','String:[et:453] %s family=%s enhancement=%s buff=%s template=%s wire=%s enhancement_contains=%s chain_templates=%d chain_functions=%d chain_gaps=%d capped=%s')}
            )
            GuardAnchors=@(
                @{Tokens=@('for','i','=','1',',','#','rows','do')}
                @{Tokens=@('mod',':','command','(','String:et_modifier_audit')}
                @{Tokens=@('local','summary','=','print_details','(','String:command',')')}
            )
        }
        @{
            ModId='enemy_tweaker'; ModTree='86f2677612ffb4772100a42101a19dacf602191c'
            Source='enemy_tweaker/scripts/mods/enemy_tweaker/_et_enemy_modifiers.lua'
            Marker='[et:453]'; AddRoute=$true
            Signature='[et:453] live category=%s breed=%s sample=%d/%d eligible=%d eligible_sample=%s rejected_banned=%d rejected_buff=%d rejected_prereq=%d buff=%s health=%s blackboard=%s nav=%s position=%s side=%s race=%s go_id=%s existing_enhancements=%d mutation=0'
            Bound='at most two distinct-breed receipts in each of the four finite enemy categories per module lifetime'
            EmitterAnchors=@(
                @{Tokens=@('local','_printf','=','rawget','(','_G',',','String:printf',')','or','function','(',')','end')}
                @{Tokens=@('pcall','(','_printf',',','String:[et:453] live category=%s breed=%s sample=%d/%d eligible=%d eligible_sample=%s rejected_banned=%d rejected_buff=%d rejected_prereq=%d buff=%s health=%s blackboard=%s nav=%s position=%s side=%s race=%s go_id=%s existing_enhancements=%d mutation=0')}
            )
            GuardAnchors=@(
                @{Tokens=@('_observed_categories','[','category',']','>=','OBSERVE_PER_CATEGORY')}
                @{Tokens=@('_observed_breeds','[','name',']','=','true')}
                @{Tokens=@('_observed_categories','[','category',']','=','_observed_categories','[','category',']','+','1')}
            )
        }
        @{
            ModId='enemy_tweaker'; ModTree='86f2677612ffb4772100a42101a19dacf602191c'
            Source='enemy_tweaker/scripts/mods/enemy_tweaker/_et_enemy_modifiers.lua'
            Marker='[et:453]'; AddRoute=$true
            Signature='[et:453] modifier-audit ready modifiers=%d gaps=%d command=/et_modifier_audit behavior_changes=0'
            Bound='one module-load readiness receipt'
            EmitterAnchors=@(
                @{Tokens=@('local','_printf','=','rawget','(','_G',',','String:printf',')','or','function','(',')','end')}
                @{Tokens=@('pcall','(','_printf',',','String:[et:453] modifier-audit ready modifiers=%d gaps=%d command=/et_modifier_audit behavior_changes=0')}
            )
            GuardAnchors=@(
                @{Tokens=@('local','_',',','initial_summary','=','audit','(',')')}
                @{Tokens=@('initial_summary','.','modifiers',',','initial_summary','.','template_missing')}
            )
        }
        @{
            ModId='cosmetics_tweaker'; ModTree='ce5181e248d9f98ac41c484ac86fb244fe475add'
            Source='cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_cos_518_probe.lua'
            Marker='[cos:518]'; AddRoute=$true
            Signature='[cos:518] OWNER-WIELD slot=%s item=%s skin=%s deus_yield=%s'
            Bound='signature-deduplicated owner-wield evidence under a per-channel sixteen-row cap'
            EmitterAnchors=@(
                @{Tokens=@('local','pf','=','rawget','(','_G',',','String:printf',')')}
                @{Tokens=@('pf','(','String:[cos:518] ','..','fmt',',','...',')')}
                @{Tokens=@('mod','.','_cos518_emit','(','String:wield',',','tostring','(','item_key',')','..','String:|','..','tostring','(','skin',')',',','String:OWNER-WIELD slot=%s item=%s skin=%s deus_yield=%s')}
            )
            GuardAnchors=@(
                @{Tokens=@('if','ch','.','seen','[','dedupe_key',']','or','ch','.','count','>=','16','then','return','false','end')}
                @{Tokens=@('ch','.','seen','[','dedupe_key',']','=','true')}
                @{Tokens=@('ch','.','count','=','ch','.','count','+','1')}
            )
        }
        @{
            ModId='cosmetics_tweaker'; ModTree='ce5181e248d9f98ac41c484ac86fb244fe475add'
            Source='cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_cos_518_probe.lua'
            Marker='[cos:518]'; AddRoute=$true
            Signature='[cos:518] PAINT-SKIP ctx=ingame bid=%s (deus run: CW upgrade cosmetics win)'
            Bound='signature-deduplicated paint-skip evidence under a per-channel sixteen-row cap'
            EmitterAnchors=@(
                @{Tokens=@('local','pf','=','rawget','(','_G',',','String:printf',')')}
                @{Tokens=@('pf','(','String:[cos:518] ','..','fmt',',','...',')')}
                @{Tokens=@('mod','.','_cos518_emit','(','String:paint-skip',',','tostring','(','bid',')',',','String:PAINT-SKIP ctx=ingame bid=%s (deus run: CW upgrade cosmetics win)')}
            )
            GuardAnchors=@(
                @{Tokens=@('if','ch','.','seen','[','dedupe_key',']','or','ch','.','count','>=','16','then','return','false','end')}
                @{Tokens=@('ch','.','seen','[','dedupe_key',']','=','true')}
                @{Tokens=@('ch','.','count','=','ch','.','count','+','1')}
            )
        }
        @{
            ModId='cosmetics_tweaker'; ModTree='ce5181e248d9f98ac41c484ac86fb244fe475add'
            Source='cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_cos_518_probe.lua'
            Marker='[cos:518]'; AddRoute=$true
            Signature='[cos:518] HUSK-MISS authored variant %s unavailable (wearer=%s template=%s)'
            Bound='signature-deduplicated authored-variant miss evidence under a per-channel sixteen-row cap'
            EmitterAnchors=@(
                @{Tokens=@('local','pf','=','rawget','(','_G',',','String:printf',')')}
                @{Tokens=@('pf','(','String:[cos:518] ','..','fmt',',','...',')')}
                @{Tokens=@('mod','.','_cos518_emit','(','String:husk-miss',',','tostring','(','armoury_key',')',',','String:HUSK-MISS authored variant %s unavailable (wearer=%s template=%s)')}
            )
            GuardAnchors=@(
                @{Tokens=@('if','ch','.','seen','[','dedupe_key',']','or','ch','.','count','>=','16','then','return','false','end')}
                @{Tokens=@('ch','.','seen','[','dedupe_key',']','=','true')}
                @{Tokens=@('ch','.','count','=','ch','.','count','+','1')}
            )
        }
        @{
            ModId='WOC'; ModTree='6a96c90be91f06f8230c1c3605adee71a38d2355'
            Source='weapons_of_chaos/scripts/mods/weapons_of_chaos/weapons_of_chaos.lua'
            Marker='[WOC:712]'
            Signature='[WOC:712] transform proof kind=%s surface=%s perspective=%s before=%s after=%s target=%s write={%s} durable=true node=%s node_name=%s'
            Bound='absolute thirty-two-row transform diagnostic budget'
            EmitterAnchors=@(
                @{Tokens=@('pcall','(','printf',',','String:[WOC:712] transform proof kind=%s surface=%s perspective=%s before=%s after=%s target=%s write={%s} durable=true node=%s node_name=%s')}
            )
            GuardAnchors=@(
                @{Tokens=@('if','_transform_diag_budget','<=','0','then','return','end')}
                @{Tokens=@('_transform_diag_budget','=','_transform_diag_budget','-','1')}
            )
        }
        @{
            ModId='WOC'; ModTree='6a96c90be91f06f8230c1c3605adee71a38d2355'
            Source='weapons_of_chaos/scripts/mods/weapons_of_chaos/weapons_of_chaos.lua'
            Marker='[WOC:712]'
            Signature='[WOC:712] tuner set offset={%f,%f,%f} rotation={%f,%f,%f} scale_3p=%f scale_1p=%f retargeted=%d live=%d'
            Bound='one receipt per explicit /woc_pose or /woc_pose_reset transaction'
            EmitterAnchors=@(
                @{Tokens=@('pcall','(','printf',',','String:[WOC:712] tuner set offset={%f,%f,%f} rotation={%f,%f,%f} scale_3p=%f scale_1p=%f retargeted=%d live=%d')}
            )
            GuardAnchors=@(
                @{Tokens=@('mod',':','command','(','String:woc_pose',',')}
                @{Tokens=@('mod',':','command','(','String:woc_pose_reset',',')}
                @{Tokens=@('local','function','_pose_set','(','x',',','y',',','z',',','rx',',','ry',',','rz',',','scale',',','scale_1p',')')}
            )
        }
        @{
            ModId='WOC'; ModTree='6a96c90be91f06f8230c1c3605adee71a38d2355'
            Source='weapons_of_chaos/scripts/mods/weapons_of_chaos/weapons_of_chaos.lua'
            Marker='[WOC:712]'
            Signature='[WOC:712] pose audit canonical offset={%.3f,%.3f,%.3f} rotation={%.1f,%.1f,%.1f} scale_3p={%.3f,%.3f,%.3f} scale_1p={%.3f,%.3f,%.3f} live=%d shown=%d truncated=%d'
            Bound='one canonical summary per explicit /woc_pose_audit invocation'
            EmitterAnchors=@(
                @{Tokens=@('printf','(','String:[WOC:712] pose audit canonical offset={%.3f,%.3f,%.3f} rotation={%.1f,%.1f,%.1f} scale_3p={%.3f,%.3f,%.3f} scale_1p={%.3f,%.3f,%.3f} live=%d shown=%d truncated=%d')}
            )
            GuardAnchors=@(
                @{Tokens=@('mod',':','command','(','String:woc_pose_audit')}
                @{Tokens=@('local','report','=','_transform_owner',':','audit','(','8',')')}
            )
        }
        @{
            ModId='WOC'; ModTree='6a96c90be91f06f8230c1c3605adee71a38d2355'
            Source='weapons_of_chaos/scripts/mods/weapons_of_chaos/weapons_of_chaos.lua'
            Marker='[WOC:712]'
            Signature='[WOC:712] pose audit row=%d surface=%s perspective=%s node=%s retained=%s wt_tuner_claims=%s current=%s target=%s write={%s}'
            Bound='at most eight rows per explicit /woc_pose_audit invocation'
            EmitterAnchors=@(
                @{Tokens=@('printf','(','String:[WOC:712] pose audit row=%d surface=%s perspective=%s node=%s retained=%s wt_tuner_claims=%s current=%s target=%s write={%s}')}
            )
            GuardAnchors=@(
                @{Tokens=@('mod',':','command','(','String:woc_pose_audit')}
                @{Tokens=@('local','report','=','_transform_owner',':','audit','(','8',')')}
                @{Tokens=@('for','i',',','row','in','ipairs','(','report','.','rows',')','do')}
            )
        }
        @{
            ModId='WOC'; ModTree='6a96c90be91f06f8230c1c3605adee71a38d2355'
            Source='weapons_of_chaos/scripts/mods/weapons_of_chaos/weapons_of_chaos.lua'
            Marker='[WOC:712]'; AddRoute=$true
            Signature='[WOC:712] unit census surface=%s perspective=%s %s'
            Bound='one receipt per finite surface/perspective key, with an additional thirty-two-row appearance budget'
            EmitterAnchors=@(
                @{Tokens=@('_appearance_diag','(','String:[WOC:712] unit census surface=%s perspective=%s %s')}
                @{Tokens=@('pcall','(','printf',',','format',',','...',')')}
            )
            GuardAnchors=@(
                @{Tokens=@('if','_unit_shape_seen','[','key',']','then','return','end')}
                @{Tokens=@('_unit_shape_seen','[','key',']','=','true')}
                @{Tokens=@('if','_appearance_diag_budget','<=','0','then','return','end')}
            )
        }
        @{
            ModId='WOC'; ModTree='6a96c90be91f06f8230c1c3605adee71a38d2355'
            Source='weapons_of_chaos/scripts/mods/weapons_of_chaos/_woc_blightreaper_pulse.lua'
            Marker='[WOC:712]'; AddRoute=$true
            Signature='[WOC:712] transform SKIP reason=%s node_name=%s chat=false'
            Bound='one receipt per finite transform-node failure reason under the module-lifetime diagnostic key latch'
            EmitterAnchors=@(
                @{Tokens=@('local','print_fn','=','api','.','printf')}
                @{Tokens=@('if','type','(','print_fn',')','==','String:function','then','pcall','(','print_fn',',','format',',','...',')','end')}
                @{Tokens=@('diagnostic_once','(','String:transform-node:','..','tostring','(','transform_reason',')',',','String:[WOC:712] transform SKIP reason=%s node_name=%s chat=false')}
                @{Source='weapons_of_chaos/scripts/mods/weapons_of_chaos/weapons_of_chaos.lua';Tokens=@('local','_wa','=','_pulse_lib','.','new','(','_appearance',',','_transform_owner',',','nil',',','mod','.','_woc_resource_residency',')')}
            )
            GuardAnchors=@(
                @{Tokens=@('if','diagnostics','[','key',']','then','return','end')}
                @{Tokens=@('diagnostics','[','key',']','=','true')}
            )
        }
        @{
            ModId='enemy_tweaker'; ModTree='86f2677612ffb4772100a42101a19dacf602191c'
            Source='enemy_tweaker/scripts/mods/enemy_tweaker/_et_skaven_warlord_breed.lua'
            Marker='[et:324]'; AddRoute=$true
            Signature='[et:324] spawn#%d t=+%ss %s'
            Bound='at most four Warlords times three fixed snapshots, one cap row, and one fallback per attempted row'
            EmitterAnchors=@(
                @{Tokens=@('pcall','(','printf',',','String:[et:324] ','..','fmt',',','...',')')}
            )
            GuardAnchors=@(
                @{Tokens=@('local','DIAG_OFFSETS','=','{','5',',','15','}','local','DIAG_MAX_UNITS','=','4')}
                @{Tokens=@('entry','.','next','=','entry','.','next','+','1','if','not','ok','or','keep','==','false','or','entry','.','next','>','#','DIAG_OFFSETS','then','table','.','remove','(','_tracked',',','i',')')}
            )
        }
        @{
            ModId='event_tweaker'; ModTree='aecc40f6935dae8dd6ab47e102822fd1e8622d64'
            Source='event_tweaker/scripts/mods/event_tweaker/_evt_issue1309_probe.lua'
            Marker='[et:1149t]'; AddRoute=$true
            Signature='[et:1149t] %s'
            Bound='one activation, at most ten per-kill rows, and one summary per peer per mission'
            EmitterAnchors=@(
                @{Tokens=@('M','.','PREFIX','=','String:[et:1149t]')}
                @{Source='event_tweaker/scripts/mods/event_tweaker/_evt_diagnostics.lua';Tokens=@('if','line','then','pcall','(','printf',',','String:%s',',','line',')','end')}
            )
            GuardAnchors=@(
                @{Tokens=@('M','.','RECEIPT_CAP','=','10')}
                @{Tokens=@('if','state','.','seed_reported','then','return','nil','end','state','.','seed_reported','=','true')}
                @{Tokens=@('if','state','.','summary_emitted','then','return','nil','end','state','.','summary_emitted','=','true')}
            )
        }
    )
}
