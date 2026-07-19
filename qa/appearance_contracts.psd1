@{
    SchemaVersion = 1

    # Closed vocabulary from docs/WEAPON_APPEARANCE_STANDARD.md. Every concern
    # must declare every cell, even when the honest disposition is deferred or
    # not-applicable. Omission is never treated as success.
    SurfaceVocabulary = @(
        'owner_1p'
        'owner_3p'
        'bot_3p'
        'remote_husk_3p'
        'inventory_preview'
        'cosmetic_preview'
        'athanor_preview'
        'crafting_preview'
        'lobby_preview'
        'score_screen'
        'hold_tab'
    )
    ReplayEdgeVocabulary = @(
        'instance_load'
        'initial_spawn'
        'equip'
        'wield'
        'customization_change'
        'style_change'
        'career_change'
        'mission_transition'
        'respawn'
        'hot_join'
        'peer_ready'
        'parity_ready'
        'rejoin'
        'preview_open'
        'preview_reopen'
        'lobby_score_create'
        'mod_disable_restore'
    )
    ConcernVocabulary = @(
        'unit_identity'
        'transform'
        'material'
        'glow'
        'pose'
        'effective_template'
        'icon'
        'name'
    )
    DispositionVocabulary = @('covered', 'deferred', 'not-applicable')

    Contracts = @(
        @{
            Id = 'cim.issue882.ranged-properties-preview-position'
            Issue = 882
            Claim = 'structural-only'
            Owners = @(
                'crafting_in_modded_dev/scripts/mods/crafting_in_modded_dev/_cim_forge_preview_policy.lua'
                'crafting_in_modded_dev/scripts/mods/crafting_in_modded_dev/_cim_forge_preview.lua'
                'crafting_in_modded_dev/scripts/mods/crafting_in_modded_dev/crafting_in_modded_dev.lua'
            )
            Concerns = @(
                @{
                    Name = 'transform'
                    Surfaces = @{
                        owner_1p = @{ Disposition = 'not-applicable'; Reason = 'the correction is scoped to the Athanor properties previewer and never mutates gameplay units' }
                        owner_3p = @{ Disposition = 'not-applicable'; Reason = 'the correction is scoped to the Athanor properties previewer and never mutates gameplay units' }
                        bot_3p = @{ Disposition = 'not-applicable'; Reason = 'the correction is scoped to the Athanor properties previewer and never mutates gameplay units' }
                        remote_husk_3p = @{ Disposition = 'not-applicable'; Reason = 'the correction is local UI state and has no network transport or husk consumer' }
                        inventory_preview = @{ Disposition = 'not-applicable'; Reason = 'the inventory character preview uses MenuWorldPreviewer rather than HeroWindowWeaveProperties' }
                        cosmetic_preview = @{ Disposition = 'not-applicable'; Reason = 'the cosmetic browser uses its own LootItemUnitPreviewer surface outside the CIM forge-active gate' }
                        athanor_preview = @{ Disposition = 'covered'; Evidence = 'the ranged-only HeroWindowWeaveProperties construction adapter composes native centered x with authored y/z and updates the live link plus boxed zoom-reset position atomically' }
                        crafting_preview = @{ Disposition = 'not-applicable'; Reason = 'the ordinary crafting preview does not instantiate HeroWindowWeaveProperties' }
                        lobby_preview = @{ Disposition = 'not-applicable'; Reason = 'lobby preview construction does not instantiate HeroWindowWeaveProperties' }
                        score_screen = @{ Disposition = 'not-applicable'; Reason = 'score preview construction does not instantiate HeroWindowWeaveProperties' }
                        hold_tab = @{ Disposition = 'not-applicable'; Reason = 'Hold-Tab renders item cards rather than the Athanor properties preview unit' }
                    }
                    ReplayEdges = @{
                        instance_load = @{ Disposition = 'not-applicable'; Reason = 'the correction is derived from current preview slot and native position and has no persisted state' }
                        initial_spawn = @{ Disposition = 'not-applicable'; Reason = 'gameplay unit spawning does not instantiate the Athanor properties previewer' }
                        equip = @{ Disposition = 'not-applicable'; Reason = 'equip does not mutate an already-open Athanor properties preview' }
                        wield = @{ Disposition = 'not-applicable'; Reason = 'wield does not mutate an already-open Athanor properties preview' }
                        customization_change = @{ Disposition = 'not-applicable'; Reason = 'the correction is slot-scoped and independent of illusion selection' }
                        style_change = @{ Disposition = 'not-applicable'; Reason = 'combat style does not own the Athanor properties preview position' }
                        career_change = @{ Disposition = 'not-applicable'; Reason = 'career selection rebuilds the forge catalogue; preview placement is reapplied only when the properties view opens' }
                        mission_transition = @{ Disposition = 'not-applicable'; Reason = 'a mission transition destroys the preview; the construction adapter reapplies on the next view open' }
                        respawn = @{ Disposition = 'not-applicable'; Reason = 'respawn does not construct the Athanor properties preview' }
                        hot_join = @{ Disposition = 'not-applicable'; Reason = 'the local preview transform has no peer state' }
                        peer_ready = @{ Disposition = 'not-applicable'; Reason = 'the local preview transform has no peer state' }
                        parity_ready = @{ Disposition = 'not-applicable'; Reason = 'the local preview uses only resident vanilla coordinates and no peer registry' }
                        rejoin = @{ Disposition = 'not-applicable'; Reason = 'the local preview transform has no peer state' }
                        preview_open = @{ Disposition = 'covered'; Evidence = 'each ranged properties preview construction applies one active-only correction after vanilla creates the previewer' }
                        preview_reopen = @{ Disposition = 'covered'; Evidence = 'each replacement previewer recomputes from its untouched native position; the boxed start position preserves the correction through zoom reset' }
                        lobby_score_create = @{ Disposition = 'not-applicable'; Reason = 'lobby and score creation do not instantiate HeroWindowWeaveProperties' }
                        mod_disable_restore = @{ Disposition = 'deferred'; Reason = 'restoring an already-open preview when CIM is disabled has no paired runtime evidence' }
                    }
                    Tests = @(
                        @{
                            Path = 'qa/lua/tests/test_cwv_old_musket_preview.lua'
                            Names = @(
                                'CIM #882 centers only ranged properties previews'
                                'CIM #882 runtime installs one active-only zoom-durable correction'
                                'CIM #882 accepts retail callable-table vector constructors'
                                'CIM #882 constructor failure leaves preview state untouched'
                                'CIM #882 production correction is construction-only and zoom durable'
                            )
                            Surfaces = @('athanor_preview')
                            ReplayEdges = @('preview_open', 'preview_reopen')
                        }
                    )
                }
            )
        }
        @{
            Id = 'cwv.issue760.outrider-saltzpyre-stance'
            Issue = 760
            Claim = 'structural-only'
            Owners = @(
                'character_weapon_variants/scripts/mods/character_weapon_variants/_cwv_outrider_animation.lua'
                'character_weapon_variants/scripts/mods/character_weapon_variants/_cwv_regression_render.lua'
                'character_weapon_variants/scripts/mods/character_weapon_variants/character_weapon_variants.lua'
            )
            Concerns = @(
                @{
                    Name = 'pose'
                    Surfaces = @{
                        owner_1p = @{ Disposition = 'covered'; Evidence = 'the policy and runtime regression preserve the functional blunderbuss state_machine, wield_anim, and no-ammo wield; no receiver-specific first-person mutation is made' }
                        owner_3p = @{ Disposition = 'covered'; Evidence = 'the private Outrider clone maps all three standard Saltzpyre careers to bidirectionally resident to_repeater_pistol without changing Kruber; WT closed issue 536 supplies the local-owner reload replay' }
                        bot_3p = @{ Disposition = 'covered'; Evidence = 'Saltzpyre bots consume the same career-aware private clone mapping as the owning extension' }
                        remote_husk_3p = @{ Disposition = 'covered'; Evidence = 'the consolidated husk-wield edge replays the resident stance only after exact cwv_item_identity proves Outrider; malformed identity, missing lookup, dead unit, or dispatch failure fails closed' }
                        inventory_preview = @{ Disposition = 'covered'; Evidence = 'the shared item-spawn post hook replays the stance only for the exact Outrider definition and receiver career after lookup/liveness validation' }
                        cosmetic_preview = @{ Disposition = 'not-applicable'; Reason = 'weapon-only cosmetic preview renders the weapon unit without a character body pose' }
                        athanor_preview = @{ Disposition = 'not-applicable'; Reason = 'Athanor weapon preview renders the weapon unit without a character body pose' }
                        crafting_preview = @{ Disposition = 'not-applicable'; Reason = 'crafting item preview renders the weapon unit without a character body pose' }
                        lobby_preview = @{ Disposition = 'deferred'; Reason = 'generic lobby character reconstruction is not part of the issue claim and has no paired runtime evidence for this exact item' }
                        score_screen = @{ Disposition = 'deferred'; Reason = 'score-screen character reconstruction is not part of the issue claim and has no paired runtime evidence for this exact item' }
                        hold_tab = @{ Disposition = 'not-applicable'; Reason = 'Hold-Tab displays item data and icons rather than an animated character body' }
                    }
                    ReplayEdges = @{
                        instance_load = @{ Disposition = 'not-applicable'; Reason = 'the receiver stance is derived from exact item and career identity and has no persisted pose state' }
                        initial_spawn = @{ Disposition = 'covered'; Evidence = 'the private template carries the receiver mapping before initial equipment construction' }
                        equip = @{ Disposition = 'covered'; Evidence = 'vanilla owner wield selection consumes the career-aware private template map' }
                        wield = @{ Disposition = 'covered'; Evidence = 'owner and consolidated husk wield edges consume the receiver-native stance' }
                        customization_change = @{ Disposition = 'not-applicable'; Reason = 'illusion customization does not alter the item or receiver identity that selects the stance' }
                        style_change = @{ Disposition = 'not-applicable'; Reason = 'Outrider has no Combat Style state in the #760 contract' }
                        career_change = @{ Disposition = 'deferred'; Reason = 'career replacement reconstructs equipment, but a live career-change observation for this item has not been captured' }
                        mission_transition = @{ Disposition = 'covered'; Evidence = 'replacement owner equipment consumes the clone map and replacement husks consume exact semantic identity' }
                        respawn = @{ Disposition = 'covered'; Evidence = 'replacement owner equipment consumes the clone map and replacement husks consume exact semantic identity' }
                        hot_join = @{ Disposition = 'covered'; Evidence = 'accepted exact identity triggers one active-slot husk re-wield and exact receiver stance replay' }
                        peer_ready = @{ Disposition = 'covered'; Evidence = 'the existing acknowledged semantic identity channel re-wields the active slot after receiver acceptance' }
                        parity_ready = @{ Disposition = 'not-applicable'; Reason = 'the stance uses a resident vanilla animation id and depends on exact semantic identity rather than numeric content parity' }
                        rejoin = @{ Disposition = 'covered'; Evidence = 'a recreated husk receives exact semantic identity and re-enters the bounded wield reconstruction edge' }
                        preview_open = @{ Disposition = 'covered'; Evidence = 'each exact preview spawn runs the receiver-scoped post hook once' }
                        preview_reopen = @{ Disposition = 'covered'; Evidence = 'each replacement exact preview unit runs the receiver-scoped post hook once' }
                        lobby_score_create = @{ Disposition = 'deferred'; Reason = 'lobby and score reconstruction remain outside the paired #760 evidence boundary' }
                        mod_disable_restore = @{ Disposition = 'deferred'; Reason = 'live restoration of an already spawned receiver pose on CWV disable has not been proven' }
                    }
                    Tests = @(
                        @{
                            Path = 'qa/lua/tests/test_cwv_outrider_animation.lua'
                            Names = @(
                                'CWV #760 applies receiver-native Outrider 3P stance only to standard Saltzpyre'
                                'CWV #760 fails closed when the resident animation contract is absent'
                                'CWV #760 runtime regression owns template and preview invariants'
                            )
                            Surfaces = @('owner_1p', 'owner_3p', 'bot_3p')
                            ReplayEdges = @('initial_spawn', 'equip', 'wield', 'mission_transition', 'respawn')
                        }
                        @{
                            Path = 'qa/lua/tests/test_cwv_outrider_animation.lua'
                            Names = @(
                                'CWV #760 husk replay is exact semantic identity gated'
                                'CWV #760 dispatch and evidence fail closed with a hard cap'
                            )
                            Surfaces = @('remote_husk_3p')
                            ReplayEdges = @('hot_join', 'peer_ready', 'rejoin')
                        }
                        @{
                            Path = 'qa/lua/tests/test_cwv_outrider_animation.lua'
                            Names = @(
                                'CWV #760 preview resolver is exact item and receiver scoped'
                                'CWV #760 dispatch and evidence fail closed with a hard cap'
                            )
                            Surfaces = @('inventory_preview')
                            ReplayEdges = @('preview_open', 'preview_reopen')
                        }
                    )
                }
            )
        }
        @{
            Id = 'cwv.issue660.exact-unit-identity'
            Issue = 660
            Claim = 'structural-only'
            Owners = @(
                'character_weapon_variants/scripts/mods/character_weapon_variants/_cwv_exact_appearance.lua'
                'character_weapon_variants/scripts/mods/character_weapon_variants/_cwv_appearance_lifecycle.lua'
                'character_weapon_variants/scripts/mods/character_weapon_variants/character_weapon_variants.lua'
            )
            Concerns = @(
                @{
                    Name = 'unit_identity'
                    Surfaces = @{
                        owner_1p = @{ Disposition = 'covered'; Evidence = 'exact create_equipment descriptor adapter' }
                        owner_3p = @{ Disposition = 'covered'; Evidence = 'exact create_equipment descriptor adapter' }
                        bot_3p = @{ Disposition = 'covered'; Evidence = 'exact create_equipment descriptor adapter' }
                        remote_husk_3p = @{ Disposition = 'covered'; Evidence = 'husk select/spawn descriptor adapters' }
                        inventory_preview = @{ Disposition = 'covered'; Evidence = 'MenuWorldPreviewer immutable descriptor adapter' }
                        cosmetic_preview = @{ Disposition = 'covered'; Evidence = 'LootItemUnitPreviewer immutable descriptor adapter' }
                        athanor_preview = @{ Disposition = 'covered'; Evidence = 'Athanor reuses the tested LootItemUnitPreviewer immutable descriptor adapter' }
                        crafting_preview = @{ Disposition = 'deferred'; Reason = 'ordinary crafting preview identity has not been proven to enter through either migrated immutable descriptor adapter' }
                        lobby_preview = @{ Disposition = 'deferred'; Reason = 'generic lobby HeroPreviewer identity still has family-specific reconstruction paths' }
                        score_screen = @{ Disposition = 'deferred'; Reason = 'generic score TeamPreviewer identity still has family-specific reconstruction paths' }
                        hold_tab = @{ Disposition = 'deferred'; Reason = 'Hold-Tab receives a loadout snapshot without exact backend instance identity and has no migrated descriptor adapter' }
                    }
                    ReplayEdges = @{
                        instance_load = @{ Disposition = 'deferred'; Reason = 'persisted exact-instance descriptor construction is not yet owned by one provider-neutral load edge' }
                        initial_spawn = @{ Disposition = 'covered'; Evidence = 'initial game-object identity publication' }
                        equip = @{ Disposition = 'covered'; Evidence = 'wield/resync publication and coalesced apply' }
                        wield = @{ Disposition = 'covered'; Evidence = 'husk wield consumes the accepted exact descriptor through the world adapter' }
                        customization_change = @{ Disposition = 'deferred'; Reason = 'customization changes still publish through provider-specific state paths' }
                        style_change = @{ Disposition = 'deferred'; Reason = 'Combat Style identity and effective template are outside the migrated unit-identity descriptor' }
                        career_change = @{ Disposition = 'deferred'; Reason = 'career generation invalidation is not yet owned by the provider-neutral CWV exact-unit lifecycle' }
                        mission_transition = @{ Disposition = 'covered'; Evidence = 'gameplay-state enter request/replay' }
                        respawn = @{ Disposition = 'deferred'; Reason = 'paired runtime respawn evidence is still required by open #660' }
                        hot_join = @{ Disposition = 'covered'; Evidence = 'targeted joining-peer descriptor replay' }
                        peer_ready = @{ Disposition = 'covered'; Evidence = 'acknowledged semantic identity delivery retries at 0.5-second cadence with an eight-attempt cap until the joining peer accepts the exact fingerprint' }
                        parity_ready = @{ Disposition = 'not-applicable'; Reason = 'issue #741 retired numeric skin replay; appearance transport is roster-independent and uses stable string-key semantic identity' }
                        rejoin = @{ Disposition = 'deferred'; Reason = 'leave/rejoin generation clearing and replay have not been proven as one bounded lifecycle edge' }
                        preview_open = @{ Disposition = 'not-applicable'; Reason = 'preview adapters resolve synchronously for each spawned recipe instead of replaying world state' }
                        preview_reopen = @{ Disposition = 'not-applicable'; Reason = 'preview adapters resolve synchronously for each newly spawned recipe instead of replaying prior preview state' }
                        lobby_score_create = @{ Disposition = 'deferred'; Reason = 'lobby and score preview creation still use family-specific identity bridges' }
                        mod_disable_restore = @{ Disposition = 'deferred'; Reason = 'provider disable/restore is not coordinated by the migrated exact-unit lifecycle ledger' }
                    }
                    Tests = @(
                        @{
                            Path = 'qa/lua/tests/test_cwv_appearance_lifecycle.lua'
                            Names = @(
                                'CWV #660 lifecycle publishes two bounded slots and coalesces duplicates'
                                'CWV #660 receiver reconstructs locally and replays once per fingerprint'
                                'CWV #660 world lifecycle adapters are bounded and vanilla-wire safe'
                            )
                            Surfaces = @('owner_1p', 'owner_3p', 'bot_3p', 'remote_husk_3p')
                            ReplayEdges = @('initial_spawn', 'equip', 'wield', 'mission_transition', 'hot_join', 'peer_ready')
                        }
                        @{
                            Path = 'qa/lua/tests/test_cwv_exact_appearance.lua'
                            Names = @(
                                'CWV #660 preview adapters consume one immutable unit descriptor'
                                'CWV #660 exact skin composes independent offhand on both preview adapters'
                            )
                            Surfaces = @('inventory_preview', 'cosmetic_preview', 'athanor_preview')
                            ReplayEdges = @()
                        }
                    )
                }
            )
        }
        @{
            Id = 'wt.issue701.kruber-crossbow-left-transform'
            Issue = 701
            Claim = 'structural-only'
            Owners = @(
                'weapon_tweaker/scripts/mods/weapon_tweaker/_wt_grip_offset_policy.lua'
                'weapon_tweaker/scripts/mods/weapon_tweaker/_wt_runtime_checks.lua'
                'weapon_tweaker/scripts/mods/weapon_tweaker/weapon_tweaker.lua'
            )
            Concerns = @(
                @{
                    Name = 'transform'
                    Surfaces = @{
                        owner_1p = @{ Disposition = 'not-applicable'; Reason = '#701 is an explicitly third-person receiver-skeleton correction' }
                        owner_3p = @{ Disposition = 'covered'; Evidence = 'GearUtils create-equipment adapter tracks the left-only Crossbow unit for durable reapply' }
                        bot_3p = @{ Disposition = 'covered'; Evidence = 'the same create-equipment adapter records bot role and the identical baked descriptor' }
                        remote_husk_3p = @{ Disposition = 'covered'; Evidence = 'SimpleHuskInventoryExtension wield adapter tracks the renderer-local left unit without transform RPC' }
                        inventory_preview = @{ Disposition = 'covered'; Evidence = 'left-only template policy routes MenuWorldPreviewer spawn to left_unit_3p' }
                        cosmetic_preview = @{ Disposition = 'deferred'; Reason = 'LootItemUnitPreviewer has no proven WT baked-transform adapter for this family' }
                        athanor_preview = @{ Disposition = 'deferred'; Reason = 'Athanor preview has no proven WT baked-transform adapter for this family' }
                        crafting_preview = @{ Disposition = 'deferred'; Reason = 'ordinary crafting preview has no proven WT baked-transform adapter for this family' }
                        lobby_preview = @{ Disposition = 'deferred'; Reason = 'the concrete lobby preview constructor consuming this hook has not been source-proven for #701' }
                        score_screen = @{ Disposition = 'deferred'; Reason = 'the concrete score preview constructor consuming this hook has not been source-proven for #701' }
                        hold_tab = @{ Disposition = 'not-applicable'; Reason = 'Hold-Tab renders item cards and icons rather than a linked weapon transform' }
                    }
                    ReplayEdges = @{
                        instance_load = @{ Disposition = 'not-applicable'; Reason = 'the baked transform is keyed by item and receiver career, not persisted per instance' }
                        initial_spawn = @{ Disposition = 'covered'; Evidence = 'owner and bot create-equipment registration captures canonical position before one-shot apply' }
                        equip = @{ Disposition = 'covered'; Evidence = 'each equipment creation resolves the same item-and-career descriptor' }
                        wield = @{ Disposition = 'covered'; Evidence = 'durable writer gates on the live wielded slot and husk wield registers its renderer-local unit' }
                        customization_change = @{ Disposition = 'not-applicable'; Reason = 'illusion customization does not own the source-baked item-and-career transform descriptor' }
                        style_change = @{ Disposition = 'not-applicable'; Reason = '#701 targets the regular Crossbow item independently of combat-style state' }
                        career_change = @{ Disposition = 'deferred'; Reason = 'career-transition recreation is structurally plausible but has no focused #701 adapter evidence' }
                        mission_transition = @{ Disposition = 'covered'; Evidence = 'mission equipment recreation re-enters the owner/bot create-equipment adapter' }
                        respawn = @{ Disposition = 'covered'; Evidence = 'respawn equipment recreation re-enters create-equipment and captures a new weak-key unit row' }
                        hot_join = @{ Disposition = 'covered'; Evidence = 'remote husk wield registration consumes vanilla replicated base item identity on join' }
                        peer_ready = @{ Disposition = 'not-applicable'; Reason = 'the renderer-local baked table creates no custom peer-ready transport' }
                        parity_ready = @{ Disposition = 'not-applicable'; Reason = 'the renderer-local baked table creates no custom parity channel or payload' }
                        rejoin = @{ Disposition = 'deferred'; Reason = 'full leave-and-rejoin lifecycle still requires live two-player evidence' }
                        preview_open = @{ Disposition = 'covered'; Evidence = 'the left-only preview field is resolved synchronously for each spawned preview unit' }
                        preview_reopen = @{ Disposition = 'covered'; Evidence = 'a reopened preview spawns a fresh unit and reruns the same pure hand policy' }
                        lobby_score_create = @{ Disposition = 'deferred'; Reason = 'lobby and score constructor coverage is not proven for this transform family' }
                        mod_disable_restore = @{ Disposition = 'deferred'; Reason = 'live disable restoration of an already-linked durable unit has no focused #701 evidence' }
                    }
                    Tests = @(
                        @{
                            Path = 'qa/lua/tests/test_wt_crossbow_offset.lua'
                            Names = @(
                                'WT #701 crossbow transform is exact left-only durable and receiver-scoped'
                                'WT #701 world adapters retain owner bot husk and preview fan-out'
                            )
                            Surfaces = @('owner_3p', 'bot_3p', 'remote_husk_3p')
                            ReplayEdges = @('initial_spawn', 'equip', 'wield', 'mission_transition', 'respawn', 'hot_join')
                        }
                        @{
                            Path = 'qa/lua/tests/test_wt_crossbow_offset.lua'
                            Names = @(
                                'WT #701 preview hand routing preserves paired and right-hand controls'
                            )
                            Surfaces = @('inventory_preview')
                            ReplayEdges = @('preview_open', 'preview_reopen')
                        }
                    )
                }
            )
        }
        @{
            Id = 'wt.issue735.saltzpyre-shield-left-rotation'
            Issue = 735
            Claim = 'structural-only'
            Owners = @(
                'weapon_tweaker/scripts/mods/weapon_tweaker/_wt_grip_offset_policy.lua'
                'weapon_tweaker/scripts/mods/weapon_tweaker/_wt_paired_preview_transform.lua'
                'weapon_tweaker/scripts/mods/weapon_tweaker/_wt_runtime_checks.lua'
                'weapon_tweaker/scripts/mods/weapon_tweaker/weapon_tweaker.lua'
            )
            Concerns = @(
                @{
                    Name = 'transform'
                    Surfaces = @{
                        owner_1p = @{ Disposition = 'not-applicable'; Reason = '#735 is an explicitly third-person shield seating correction' }
                        owner_3p = @{ Disposition = 'covered'; Evidence = 'create-equipment resolves the baked descriptor and tracks only the exact left 3P unit' }
                        bot_3p = @{ Disposition = 'covered'; Evidence = 'the same create-equipment adapter tracks bot left-unit identity with no separate transform table' }
                        remote_husk_3p = @{ Disposition = 'covered'; Evidence = 'husk wield resolves the same receiver-and-hand descriptor against its renderer-local left unit' }
                        inventory_preview = @{ Disposition = 'covered'; Evidence = 'post-_spawn_item adapter bridges spawn_data hand flags to numeric-slot equipment units instead of guessing in _spawn_item_unit' }
                        cosmetic_preview = @{ Disposition = 'deferred'; Reason = 'LootItemUnitPreviewer has no proven WT baked-transform adapter for this family' }
                        athanor_preview = @{ Disposition = 'deferred'; Reason = 'Athanor preview has no proven WT baked-transform adapter for this family' }
                        crafting_preview = @{ Disposition = 'deferred'; Reason = 'ordinary crafting preview has no proven WT baked-transform adapter for this family' }
                        lobby_preview = @{ Disposition = 'deferred'; Reason = 'the concrete lobby preview constructor consuming the WT transform path has not been source-proven' }
                        score_screen = @{ Disposition = 'deferred'; Reason = 'the concrete score preview constructor consuming the WT transform path has not been source-proven' }
                        hold_tab = @{ Disposition = 'not-applicable'; Reason = 'Hold-Tab renders item cards and icons rather than linked weapon transforms' }
                    }
                    ReplayEdges = @{
                        instance_load = @{ Disposition = 'not-applicable'; Reason = 'the transform is baked by item and receiver career rather than persisted per backend instance' }
                        initial_spawn = @{ Disposition = 'covered'; Evidence = 'owner/bot creation and husk wield capture the canonical left-unit rotation before durable ownership' }
                        equip = @{ Disposition = 'covered'; Evidence = 'equipment creation re-resolves receiver and hand through one transform policy' }
                        wield = @{ Disposition = 'covered'; Evidence = 'durable writer gates on the live wielded slot and restores canonical rotation while stowed' }
                        customization_change = @{ Disposition = 'not-applicable'; Reason = 'illusion selection does not own the baked receiver-and-hand transform' }
                        style_change = @{ Disposition = 'not-applicable'; Reason = '#735 is keyed to fixed weapon identities rather than combat-style state' }
                        career_change = @{ Disposition = 'deferred'; Reason = 'career recreation has no focused #735 live evidence yet' }
                        mission_transition = @{ Disposition = 'covered'; Evidence = 'new equipment units re-enter create-equipment or husk wield and resolve the same descriptor' }
                        respawn = @{ Disposition = 'covered'; Evidence = 'respawn creates new weak-key unit rows through the same world adapters' }
                        hot_join = @{ Disposition = 'covered'; Evidence = 'husk wield consumes vanilla-replicated item identity and shipped transform data with no custom RPC' }
                        peer_ready = @{ Disposition = 'not-applicable'; Reason = 'renderer-local baked transforms create no peer-ready transport' }
                        parity_ready = @{ Disposition = 'not-applicable'; Reason = 'renderer-local baked transforms create no parity channel or payload' }
                        rejoin = @{ Disposition = 'deferred'; Reason = 'full leave-and-rejoin retention still requires two-player evidence' }
                        preview_open = @{ Disposition = 'covered'; Evidence = 'each preview spawn bridges exact left/right recipe identity after vanilla creates both units' }
                        preview_reopen = @{ Disposition = 'covered'; Evidence = 'reopening creates fresh units and re-enters the exact hand adapter' }
                        lobby_score_create = @{ Disposition = 'deferred'; Reason = 'lobby and score constructor coverage is not proven for this transform family' }
                        mod_disable_restore = @{ Disposition = 'deferred'; Reason = 'live disable restoration for already-linked units has no focused #735 evidence' }
                    }
                    Tests = @(
                        @{
                            Path = 'qa/lua/tests/test_wt_hand_transform_policy.lua'
                            Names = @(
                                'WT #735 receiver and hand policy is shared across transform channels'
                                'WT #735 public and dev route shield rotation through exact hand adapters'
                                'WT #735 retained proof reads rotation back after the durable write'
                            )
                            Surfaces = @('owner_3p', 'bot_3p', 'remote_husk_3p')
                            ReplayEdges = @('initial_spawn', 'equip', 'wield', 'mission_transition', 'respawn', 'hot_join')
                        }
                        @{
                            Path = 'qa/lua/tests/test_wt_hand_transform_policy.lua'
                            Names = @(
                                'WT #735 paired preview refuses ambiguous unit callback routing'
                                'WT #735 public and dev route shield rotation through exact hand adapters'
                            )
                            Surfaces = @('inventory_preview')
                            ReplayEdges = @('preview_open', 'preview_reopen')
                        }
                    )
                }
            )
        }
        @{
            Id = 'cosmetics.issue641.component-item-text'
            Issue = 641
            Claim = 'structural-only'
            Owners = @(
                'cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_cos_offhand_names.lua'
                'cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_cos_item_presentation.lua'
                'cosmetics_tweaker/scripts/mods/cosmetics_tweaker/cosmetics_tweaker.lua'
            )
            Concerns = @(
                @{
                    Name = 'name'
                    Surfaces = @{
                        owner_1p = @{ Disposition = 'not-applicable'; Reason = 'first-person world rendering has no item-card name or flavor-text surface' }
                        owner_3p = @{ Disposition = 'not-applicable'; Reason = 'third-person world rendering has no item-card name or flavor-text surface' }
                        bot_3p = @{ Disposition = 'not-applicable'; Reason = 'bot world rendering has no item-card name or flavor-text surface' }
                        remote_husk_3p = @{ Disposition = 'not-applicable'; Reason = 'remote husk world rendering has no item-card name or flavor-text surface' }
                        inventory_preview = @{ Disposition = 'covered'; Evidence = 'UIUtils exact-instance adapter publishes composed title and selected-component description' }
                        cosmetic_preview = @{ Disposition = 'covered'; Evidence = 'customization hover and canonical item-card descriptor consume the same decorated component option' }
                        athanor_preview = @{ Disposition = 'deferred'; Reason = 'Athanor component flavor-text consumption has not been observed in source or in game' }
                        crafting_preview = @{ Disposition = 'deferred'; Reason = 'ordinary crafting component flavor-text consumption has not been observed in source or in game' }
                        lobby_preview = @{ Disposition = 'deferred'; Reason = 'lobby item-card description consumption is not established' }
                        score_screen = @{ Disposition = 'deferred'; Reason = 'score-screen item-card description consumption is not established' }
                        hold_tab = @{ Disposition = 'covered'; Evidence = 'parity-gated peer descriptor owns the composed title; Hold-Tab has no flavor-text field' }
                    }
                    ReplayEdges = @{
                        instance_load = @{ Disposition = 'covered'; Evidence = 'persisted record is matched back to the canonical decorated component option' }
                        initial_spawn = @{ Disposition = 'not-applicable'; Reason = 'item text resolves synchronously when a card is requested' }
                        equip = @{ Disposition = 'not-applicable'; Reason = 'item text resolves synchronously when a card is requested' }
                        wield = @{ Disposition = 'not-applicable'; Reason = 'item text resolves synchronously when a card is requested' }
                        customization_change = @{ Disposition = 'covered'; Evidence = 'component hover and saved exact-instance option both use the canonical descriptor' }
                        style_change = @{ Disposition = 'not-applicable'; Reason = 'combat style does not own cosmetic component text' }
                        career_change = @{ Disposition = 'not-applicable'; Reason = 'item-card text resolves synchronously from the requested exact instance and retains no career state' }
                        mission_transition = @{ Disposition = 'not-applicable'; Reason = 'local item text resolves from persisted identity on demand' }
                        respawn = @{ Disposition = 'not-applicable'; Reason = 'respawn does not retain item-card text state' }
                        hot_join = @{ Disposition = 'covered'; Evidence = 'peer presentation resolves only from existing parity-gated component caches' }
                        peer_ready = @{ Disposition = 'deferred'; Reason = 'runtime peer-ready title timing still requires co-op verification' }
                        parity_ready = @{ Disposition = 'covered'; Evidence = 'missing peer component cache fails closed instead of exporting custom text identity' }
                        rejoin = @{ Disposition = 'deferred'; Reason = 'runtime rejoin title timing still requires co-op verification' }
                        preview_open = @{ Disposition = 'covered'; Evidence = 'descriptor resolves from the current canonical component option on every call' }
                        preview_reopen = @{ Disposition = 'covered'; Evidence = 'descriptor contains no retained screen-local text state' }
                        lobby_score_create = @{ Disposition = 'deferred'; Reason = 'lobby and score description consumers are not established' }
                        mod_disable_restore = @{ Disposition = 'covered'; Evidence = 'presentation metadata never mutates saved identity or vanilla item registries' }
                    }
                    Tests = @(
                        @{
                            Path = 'qa/lua/tests/test_cos_offhand_names.lua'
                            Names = @(
                                'component description prefers authored then source text'
                                'component records resolve by authored key, mesh, or source skin'
                                'decorated weapon and shield records remain presentation-only'
                                'runtime integration composes primary then independently named component'
                            )
                            Surfaces = @('inventory_preview', 'cosmetic_preview')
                            ReplayEdges = @('instance_load', 'customization_change', 'preview_open', 'preview_reopen', 'mod_disable_restore')
                        }
                        @{
                            Path = 'qa/lua/tests/test_cos_item_presentation.lua'
                            Names = @(
                                'shield owns locally resident icon and independent text'
                                'component description never falls back to primary text'
                                'Hold-Tab peer identity resolves only from existing local caches'
                            )
                            Surfaces = @('inventory_preview', 'cosmetic_preview', 'hold_tab')
                            ReplayEdges = @('hot_join', 'parity_ready')
                        }
                    )
                }
            )
        }
        @{
            Id = 'cwv-cim.issue787.dual-axes-athanor-icon'
            Issue = 787
            Claim = 'structural-only'
            Owners = @(
                'character_weapon_variants/scripts/mods/character_weapon_variants/_cwv_inventory_icons.lua'
                'character_weapon_variants/scripts/mods/character_weapon_variants/character_weapon_variants_data.lua'
                'crafting_in_modded_dev/scripts/mods/crafting_in_modded_dev/_cim_athanor_icon_policy.lua'
            )
            Concerns = @(
                @{
                    Name = 'icon'
                    Surfaces = @{
                        owner_1p = @{ Disposition = 'not-applicable'; Reason = 'first-person weapon units do not render inventory icons' }
                        owner_3p = @{ Disposition = 'not-applicable'; Reason = 'third-person weapon units do not render inventory icons' }
                        bot_3p = @{ Disposition = 'not-applicable'; Reason = 'bot weapon units do not render inventory icons' }
                        remote_husk_3p = @{ Disposition = 'not-applicable'; Reason = 'remote husk units do not render inventory icons' }
                        inventory_preview = @{ Disposition = 'covered'; Evidence = 'CWV hero_view injection already owns and advertises the paired atlas' }
                        cosmetic_preview = @{ Disposition = 'deferred'; Reason = 'the cosmetic browser has a separate renderer and is outside the CIM selector claim' }
                        athanor_preview = @{ Disposition = 'covered'; Evidence = 'the shared ingame_ui top-renderer capability plus exact masked-saturated live-Gui proof retains the paired icon' }
                        crafting_preview = @{ Disposition = 'deferred'; Reason = 'the ordinary crafting picker does not consume the Athanor sanitizer' }
                        lobby_preview = @{ Disposition = 'deferred'; Reason = 'lobby item-card icon residency is owned by its renderer-specific contract' }
                        score_screen = @{ Disposition = 'deferred'; Reason = 'score-screen item-card icon residency is owned by its renderer-specific contract' }
                        hold_tab = @{ Disposition = 'deferred'; Reason = 'Hold-Tab item-card icon residency is owned by its peer-safe renderer contract' }
                    }
                    ReplayEdges = @{
                        instance_load = @{ Disposition = 'not-applicable'; Reason = 'the authored icon is immutable provider data, not per-instance state' }
                        initial_spawn = @{ Disposition = 'not-applicable'; Reason = 'weapon spawn does not create item-list icons' }
                        equip = @{ Disposition = 'not-applicable'; Reason = 'equip does not create the Athanor selector' }
                        wield = @{ Disposition = 'not-applicable'; Reason = 'wield does not create the Athanor selector' }
                        customization_change = @{ Disposition = 'not-applicable'; Reason = 'the synthetic base crafting row has no exact backend-instance identity and must not enter the Cosmetics primary/offhand/glow compositor' }
                        style_change = @{ Disposition = 'not-applicable'; Reason = 'combat style does not change the base Dual Axes selector icon' }
                        career_change = @{ Disposition = 'covered'; Evidence = 'the catalog rebuild preserves the authored icon for both Kruber and Saltzpyre variants' }
                        mission_transition = @{ Disposition = 'not-applicable'; Reason = 'renderer capability is registered at mod initialization and each list open performs a fresh live-Gui proof' }
                        respawn = @{ Disposition = 'not-applicable'; Reason = 'respawn does not create the Athanor selector' }
                        hot_join = @{ Disposition = 'not-applicable'; Reason = 'the local selector sends no custom icon identity to peers' }
                        peer_ready = @{ Disposition = 'not-applicable'; Reason = 'the local selector sends no custom icon identity to peers' }
                        parity_ready = @{ Disposition = 'not-applicable'; Reason = 'the local renderer reads only locally registered resources' }
                        rejoin = @{ Disposition = 'not-applicable'; Reason = 'the local selector sends no custom icon identity to peers' }
                        preview_open = @{ Disposition = 'covered'; Evidence = 'every Athanor list build sanitizes against the exact current ui_top_renderer Gui' }
                        preview_reopen = @{ Disposition = 'covered'; Evidence = 'every Athanor list rebuild repeats the exact live-Gui material proof' }
                        lobby_score_create = @{ Disposition = 'not-applicable'; Reason = 'the candidate changes only the Athanor selector renderer capability' }
                        mod_disable_restore = @{ Disposition = 'covered'; Evidence = 'CIM falls back to vanilla provider/base icons when CWV is absent' }
                    }
                    Tests = @(
                        @{
                            Path = 'qa/lua/tests/test_cwv_dual_icons.lua'
                            Names = @(
                                'CWV Dual Axes has a packaged atlas entry for every primary axe icon'
                                'CWV custom icon contract fails closed outside injected renderers'
                                'CWV completes the VMF-missing masked saturated atlas variant'
                            )
                            Surfaces = @('inventory_preview', 'athanor_preview')
                            ReplayEdges = @()
                        }
                        @{
                            Path = 'qa/lua/tests/test_cim_athanor_icon_policy.lua'
                            Names = @(
                                'renderer-owned CWV Dual Axes icons remain authored in Athanor'
                                'every live CWV custom inventory icon closes to vanilla in Athanor'
                            )
                            Surfaces = @('athanor_preview')
                            ReplayEdges = @('preview_open', 'preview_reopen', 'mod_disable_restore')
                        }
                        @{
                            Path = 'qa/lua/tests/test_cim_cwv_template_catalog.lua'
                            Names = @('every CWV family keeps exact definition and authored icon')
                            Surfaces = @('athanor_preview')
                            ReplayEdges = @('career_change')
                        }
                    )
                }
            )
        }
        @{
            Id = 'woc.issue712.blightreaper-transform'
            Issue = 712
            Claim = 'structural-only'
            Owners = @(
                'tools/shared_lib/_lib_weapon_appearance.lua'
                'weapons_of_chaos/scripts/mods/weapons_of_chaos/_woc_appearance_policy.lua'
                'weapons_of_chaos/scripts/mods/weapons_of_chaos/_woc_blightreaper_pulse.lua'
                'weapons_of_chaos/scripts/mods/weapons_of_chaos/_woc_durable_transform.lua'
                'weapons_of_chaos/scripts/mods/weapons_of_chaos/_woc_mod_unit_preview.lua'
                'weapons_of_chaos/scripts/mods/weapons_of_chaos/weapons_of_chaos.lua'
            )
            Concerns = @(
                @{
                    Name = 'transform'
                    Surfaces = @{
                        owner_1p = @{ Disposition = 'covered'; Evidence = 'GearUtils return adapter resolves the authored 1P render node' }
                        owner_3p = @{ Disposition = 'covered'; Evidence = 'GearUtils return adapter resolves the authored local 3P render node' }
                        bot_3p = @{ Disposition = 'covered'; Evidence = 'the positively identified non-1P GearUtils recipe consumes the same descriptor' }
                        remote_husk_3p = @{ Disposition = 'covered'; Evidence = 'husk GearUtils return adapter consumes the same descriptor without transform RPC' }
                        inventory_preview = @{ Disposition = 'covered'; Evidence = 'HeroPreviewer character-preview adapter consumes the same descriptor' }
                        cosmetic_preview = @{ Disposition = 'covered'; Evidence = 'LootItemUnitPreviewer item-preview adapter consumes the same descriptor' }
                        athanor_preview = @{ Disposition = 'covered'; Evidence = 'Athanor reuses the LootItemUnitPreviewer item-preview adapter' }
                        crafting_preview = @{ Disposition = 'covered'; Evidence = 'crafting item previews reuse the LootItemUnitPreviewer adapter' }
                        lobby_preview = @{ Disposition = 'covered'; Evidence = 'MenuWorldPreviewer character-preview adapter consumes the same descriptor' }
                        score_screen = @{ Disposition = 'covered'; Evidence = 'score/end character preview reuses the HeroPreviewer/MenuWorldPreviewer adapter' }
                        hold_tab = @{ Disposition = 'not-applicable'; Reason = 'Hold-Tab renders item cards and icons, not a weapon unit transform' }
                    }
                    ReplayEdges = @{
                        instance_load = @{ Disposition = 'not-applicable'; Reason = 'the immutable transform descriptor has no per-instance persisted state' }
                        initial_spawn = @{ Disposition = 'covered'; Evidence = 'each GearUtils return is adapted before the caller receives it' }
                        equip = @{ Disposition = 'covered'; Evidence = 'equip creates a fresh GearUtils recipe and applies the descriptor' }
                        wield = @{ Disposition = 'covered'; Evidence = 'wielded owner and husk units are weak-tracked for measured pose drift' }
                        customization_change = @{ Disposition = 'not-applicable'; Reason = 'the immutable relic has no selectable cosmetic transform' }
                        style_change = @{ Disposition = 'not-applicable'; Reason = 'Blightreaper has no combat-style transform variants' }
                        career_change = @{ Disposition = 'not-applicable'; Reason = 'the immutable relic transform is independent of the wearer career' }
                        mission_transition = @{ Disposition = 'covered'; Evidence = 'replacement units consume the descriptor independently after transition' }
                        respawn = @{ Disposition = 'covered'; Evidence = 'replacement GearUtils units consume the descriptor independently after respawn' }
                        hot_join = @{ Disposition = 'covered'; Evidence = 'new remote husk spawn consumes the local render descriptor' }
                        peer_ready = @{ Disposition = 'not-applicable'; Reason = 'the transform is local presentation with no peer-ready payload' }
                        parity_ready = @{ Disposition = 'not-applicable'; Reason = 'the transform is local presentation with no parity payload' }
                        rejoin = @{ Disposition = 'covered'; Evidence = 'a re-created husk consumes a new local render descriptor' }
                        preview_open = @{ Disposition = 'covered'; Evidence = 'each preview-spawn recipe resolves the named render node' }
                        preview_reopen = @{ Disposition = 'covered'; Evidence = 'a replacement preview unit has an independent weak application guard' }
                        lobby_score_create = @{ Disposition = 'covered'; Evidence = 'character-preview creation resolves the named render node on each unit' }
                        mod_disable_restore = @{ Disposition = 'deferred'; Reason = 'live restoration of already-spawned imported units on mod disable is not proven' }
                    }
                    Tests = @(
                        @{
                            Path = 'qa/lua/tests/test_woc_blightreaper_pulse.lua'
                            Names = @(
                                'WOC #712 resolves named render node across gameplay and preview surfaces'
                            )
                            Surfaces = @(
                                'owner_1p', 'owner_3p', 'bot_3p', 'remote_husk_3p',
                                'inventory_preview', 'cosmetic_preview', 'athanor_preview',
                                'crafting_preview', 'lobby_preview', 'score_screen'
                            )
                            ReplayEdges = @(
                                'initial_spawn', 'equip', 'wield', 'hot_join', 'rejoin',
                                'preview_open', 'preview_reopen', 'lobby_score_create'
                            )
                        }
                        @{
                            Path = 'qa/lua/tests/test_woc_blightreaper_pulse.lua'
                            Names = @(
                                'WOC #712 replays transform for replacement units after mission transition'
                            )
                            Surfaces = @('owner_3p')
                            ReplayEdges = @('mission_transition', 'respawn')
                        }
                    )
                }
            )
        }
        @{
            Id = 'cwv.issue692.reciprocal-bretonnian-transform'
            Issue = 692
            Claim = 'structural-only'
            Owners = @(
                'character_weapon_variants/scripts/mods/character_weapon_variants/_cwv_combat_styles.lua'
                'character_weapon_variants/scripts/mods/character_weapon_variants/_cwv_husk_path.lua'
                'character_weapon_variants/scripts/mods/character_weapon_variants/character_weapon_variants.lua'
            )
            Concerns = @(
                @{
                    Name = 'transform'
                    Surfaces = @{
                        owner_1p = @{ Disposition = 'covered'; Evidence = 'unified inverse descriptor reaches create_equipment owner first-person roots' }
                        owner_3p = @{ Disposition = 'covered'; Evidence = 'unified inverse descriptor reaches create_equipment owner third-person roots' }
                        bot_3p = @{ Disposition = 'covered'; Evidence = 'create_equipment uses the same resolved descriptor for bot third-person roots' }
                        remote_husk_3p = @{ Disposition = 'covered'; Evidence = 'remote style state resolves the concrete Bretonnian receiver descriptor before husk transform apply' }
                        inventory_preview = @{ Disposition = 'covered'; Evidence = 'MenuWorldPreviewer resolves the exact instance style and applies the unified inverse descriptor' }
                        cosmetic_preview = @{ Disposition = 'covered'; Evidence = 'LootItemUnitPreviewer resolves the exact instance style and applies the unified inverse descriptor' }
                        athanor_preview = @{ Disposition = 'covered'; Evidence = 'Athanor reuses the LootItemUnitPreviewer exact-instance transform seam' }
                        crafting_preview = @{ Disposition = 'deferred'; Reason = 'ordinary crafting preview has no proven exact backend instance style identity' }
                        lobby_preview = @{ Disposition = 'covered'; Evidence = 'lobby HeroPreviewer reuses the MenuWorldPreviewer equipment-unit transform seam' }
                        score_screen = @{ Disposition = 'covered'; Evidence = 'team score HeroPreviewer reuses the MenuWorldPreviewer equipment-unit transform seam' }
                        hold_tab = @{ Disposition = 'deferred'; Reason = 'Hold-Tab does not expose a proven exact backend instance style to the appearance resolver' }
                    }
                    ReplayEdges = @{
                        instance_load = @{ Disposition = 'covered'; Evidence = 'exact backend instance style is loaded from the schema-checked Combat Style store' }
                        initial_spawn = @{ Disposition = 'covered'; Evidence = 'owner/bot create and remote husk spawn resolve the receiver descriptor before applying the transform' }
                        equip = @{ Disposition = 'covered'; Evidence = 'every equipment creation resolves the current exact-instance style' }
                        wield = @{ Disposition = 'covered'; Evidence = 'owner and husk wield rebuild paths resolve the current exact-instance or remote style' }
                        customization_change = @{ Disposition = 'not-applicable'; Reason = 'the reciprocal transform belongs to Combat Style, not cosmetic customization' }
                        style_change = @{ Disposition = 'covered'; Evidence = 'style transition rewields locally and publishes one bounded remote refresh state' }
                        career_change = @{ Disposition = 'deferred'; Reason = 'career transition ownership is outside the #692 reciprocal presentation change' }
                        mission_transition = @{ Disposition = 'covered'; Evidence = 'new mission equipment spawn resolves the persisted exact-instance style' }
                        respawn = @{ Disposition = 'covered'; Evidence = 'replacement equipment units resolve the persisted local or accepted remote style' }
                        hot_join = @{ Disposition = 'covered'; Evidence = 'targeted Combat Style loadout publication precedes the remote husk receiver lookup' }
                        peer_ready = @{ Disposition = 'covered'; Evidence = 'bounded Combat Style query reply publishes current exact-instance style state' }
                        parity_ready = @{ Disposition = 'not-applicable'; Reason = 'Combat Style state uses its own schema-bounded mod channel rather than content-parity replay' }
                        rejoin = @{ Disposition = 'deferred'; Reason = 'disconnect-generation teardown and full rejoin remain part of the broader #747 lifecycle audit' }
                        preview_open = @{ Disposition = 'covered'; Evidence = 'each preview spawn resolves the exact backend instance style before transform application' }
                        preview_reopen = @{ Disposition = 'covered'; Evidence = 'reopened preview spawns new units and repeats exact-instance style resolution' }
                        lobby_score_create = @{ Disposition = 'covered'; Evidence = 'lobby and score HeroPreviewer creation enter the shared MenuWorldPreviewer transform seam' }
                        mod_disable_restore = @{ Disposition = 'deferred'; Reason = 'live restoration after disabling CWV is outside the #692 reciprocal presentation change' }
                    }
                    Tests = @(
                        @{
                            Path = 'qa/lua/tests/test_cwv_combat_styles.lua'
                            Names = @(
                                'CWV Combat Styles expose deterministic multi-style family cycles'
                                'CWV Combat Style runtime resolves exact IDs and legacy defaults'
                                'CWV #692 reciprocal Bretonnian transform reaches every appearance consumer'
                            )
                            Surfaces = @(
                                'owner_1p', 'owner_3p', 'bot_3p', 'remote_husk_3p',
                                'inventory_preview', 'cosmetic_preview', 'athanor_preview',
                                'lobby_preview', 'score_screen'
                            )
                            ReplayEdges = @(
                                'instance_load', 'initial_spawn', 'equip', 'wield', 'style_change',
                                'mission_transition', 'respawn', 'hot_join', 'peer_ready',
                                'preview_open', 'preview_reopen', 'lobby_score_create'
                            )
                        }
                    )
                }
            )
        }
        @{
            Id = 'cosmetics.issue698.career-scoped-husk-material'
            Issue = 698
            Claim = 'structural-only'
            Owners = @(
                'cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_cos_husk_identity.lua'
                'cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_cos_runtime_checks.lua'
                'cosmetics_tweaker/scripts/mods/cosmetics_tweaker/cosmetics_tweaker.lua'
            )
            Concerns = @(
                @{
                    Name = 'material'
                    Surfaces = @{
                        owner_1p = @{ Disposition = 'deferred'; Reason = 'the career-scoped peer-store boundary is shared, but owner first-person material convergence is not the #698 claim' }
                        owner_3p = @{ Disposition = 'deferred'; Reason = 'the career-scoped peer-store boundary is shared, but owner third-person material convergence is not the #698 claim' }
                        bot_3p = @{ Disposition = 'covered'; Evidence = 'non-human peer aliases cannot consume or invalidate the human peer appearance store' }
                        remote_husk_3p = @{ Disposition = 'covered'; Evidence = 'every stored and transported material record carries an exact wearer career checked before husk mesh or material replay' }
                        inventory_preview = @{ Disposition = 'not-applicable'; Reason = 'inventory preview does not consume the live remote-husk peer store' }
                        cosmetic_preview = @{ Disposition = 'not-applicable'; Reason = 'cosmetic preview does not consume the live remote-husk peer store' }
                        athanor_preview = @{ Disposition = 'not-applicable'; Reason = 'Athanor preview does not consume the live remote-husk peer store' }
                        crafting_preview = @{ Disposition = 'not-applicable'; Reason = 'ordinary crafting preview does not consume the live remote-husk peer store' }
                        lobby_preview = @{ Disposition = 'deferred'; Reason = 'generic lobby preview uses separate wearer reconstruction and is not governed by the husk career boundary' }
                        score_screen = @{ Disposition = 'deferred'; Reason = 'score-screen identity is governed by the separate #513 exact score-row boundary' }
                        hold_tab = @{ Disposition = 'not-applicable'; Reason = 'Hold-Tab does not render live wearer materials' }
                    }
                    ReplayEdges = @{
                        instance_load = @{ Disposition = 'deferred'; Reason = 'persisted local selection loading is owned by the LA persistence layer before publication' }
                        initial_spawn = @{ Disposition = 'covered'; Evidence = 'husk pre-wield invalidation runs before vanilla spawn and post-wield material replay' }
                        equip = @{ Disposition = 'covered'; Evidence = 'host and client apply paths stamp and validate the exact wearer career' }
                        wield = @{ Disposition = 'covered'; Evidence = 'SimpleHuskInventoryExtension._wield_slot rejects unproven bot aliases and mismatched career records' }
                        customization_change = @{ Disposition = 'covered'; Evidence = 'the canonical LA emit path requires and transports the live wearer career with each changed selection' }
                        style_change = @{ Disposition = 'not-applicable'; Reason = 'combat style does not change the wearer career identity owned by this contract' }
                        career_change = @{ Disposition = 'covered'; Evidence = 'a confirmed human career change removes all mismatched and legacy unstamped peer records before husk rendering' }
                        mission_transition = @{ Disposition = 'covered'; Evidence = 'state-pull and bounded transition reconcile preserve and revalidate the stamped career' }
                        respawn = @{ Disposition = 'covered'; Evidence = 'every new husk wield repeats exact human and career validation before replay' }
                        hot_join = @{ Disposition = 'covered'; Evidence = 'targeted hot-join replay includes the stored wearer career and the receiver validates it' }
                        peer_ready = @{ Disposition = 'covered'; Evidence = 'acknowledged pull-on-ready reply includes the stored wearer career and fails closed for legacy records' }
                        parity_ready = @{ Disposition = 'not-applicable'; Reason = 'this material RPC uses mod-channel schema parity rather than the CWV content-parity lifecycle' }
                        rejoin = @{ Disposition = 'deferred'; Reason = 'full disconnect-generation teardown and rejoin remains governed by the existing deferred peer purge lifecycle' }
                        preview_open = @{ Disposition = 'not-applicable'; Reason = 'preview opening does not consume the live remote-husk peer store' }
                        preview_reopen = @{ Disposition = 'not-applicable'; Reason = 'preview reopening does not consume the live remote-husk peer store' }
                        lobby_score_create = @{ Disposition = 'deferred'; Reason = 'lobby and score creation use separate wearer identity adapters' }
                        mod_disable_restore = @{ Disposition = 'deferred'; Reason = 'mod disable restoration is outside the live husk career replay boundary' }
                    }
                    Tests = @(
                        @{
                            Path = 'qa/lua/tests/test_cos_husk_identity.lua'
                            Names = @(
                                'Cosmetics #698 career-scoped entries fail closed and preserve bot owners'
                                'Cosmetics #698 career change invalidates remote material replay'
                                'Cosmetics #698 spawn monitor invalidates humans without consuming bot aliases'
                                'Cosmetics #698 host client and husk paths carry one career identity'
                            )
                            Surfaces = @('bot_3p', 'remote_husk_3p')
                            ReplayEdges = @('initial_spawn', 'equip', 'wield', 'customization_change', 'career_change', 'mission_transition', 'respawn', 'hot_join', 'peer_ready')
                        }
                    )
                }
            )
        }
    )
}
