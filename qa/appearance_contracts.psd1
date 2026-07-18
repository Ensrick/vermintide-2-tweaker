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
                        mission_transition = @{ Disposition = 'covered'; Evidence = 'gameplay-state enter request/replay' }
                        respawn = @{ Disposition = 'deferred'; Reason = 'paired runtime respawn evidence is still required by open #660' }
                        hot_join = @{ Disposition = 'covered'; Evidence = 'targeted joining-peer descriptor replay' }
                        peer_ready = @{ Disposition = 'deferred'; Reason = 'the first proven peer/session-ready callback has not replaced provider-specific retry and replay paths' }
                        parity_ready = @{ Disposition = 'covered'; Evidence = 'post-parity bounded replay' }
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
                            ReplayEdges = @('initial_spawn', 'equip', 'wield', 'mission_transition', 'hot_join', 'parity_ready')
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
    )
}
