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
    )
}
