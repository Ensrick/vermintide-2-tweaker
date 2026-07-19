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
