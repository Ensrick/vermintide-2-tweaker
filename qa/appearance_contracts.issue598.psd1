@{
    SchemaVersion = 1
    Contracts = @(
        @{
            Id = 'cim.issue598.owner-cursed-frame'
            Issue = 598
            Claim = 'structural-only'
            Owners = @(
                'crafting_in_modded_dev/scripts/mods/crafting_in_modded_dev/_cim_tab_preview.lua'
                'crafting_in_modded_dev/scripts/mods/crafting_in_modded_dev/_cim_tab_preview_core.lua'
            )
            Concerns = @(
                @{
                    Name = 'icon'
                    Surfaces = @{
                        owner_1p = @{ Disposition='not-applicable'; Reason='this adapter writes a 2D Tab rarity background, not a first-person weapon unit' }
                        owner_3p = @{ Disposition='not-applicable'; Reason='this adapter does not write third-person weapon units' }
                        bot = @{ Disposition='not-applicable'; Reason='new exact-instance Cursed resolution explicitly excludes bot rows; their existing wire policy is retained' }
                        husk = @{ Disposition='deferred'; Reason='remote Cursed semantics need a separate authority/compatibility design; this candidate preserves remote wire policy' }
                        inventory_preview = @{ Disposition='not-applicable'; Reason='no inventory character preview hook or widget is touched' }
                        illusion_browser = @{ Disposition='not-applicable'; Reason='no illusion browser hook or widget is touched' }
                        cim_preview = @{ Disposition='not-applicable'; Reason='no CIM forge preview hook or widget is touched' }
                        crafting_preview = @{ Disposition='not-applicable'; Reason='no ordinary crafting preview hook or widget is touched' }
                        lobby = @{ Disposition='not-applicable'; Reason='no lobby widget is touched' }
                        score_team = @{ Disposition='not-applicable'; Reason='no score/team widget is touched' }
                        hold_tab = @{ Disposition='covered'; Evidence='the actual installed post-hook paints only the live local human current items-owned exact Cursed instance, gates its local texture and restores prior widget ownership before fallible reads; offline adapter evidence only' }
                        specials = @{ Disposition='not-applicable'; Reason='no weapon-special presentation is touched' }
                        remote_audio = @{ Disposition='not-applicable'; Reason='no audio state or event is touched' }
                        hud_panels = @{ Disposition='not-applicable'; Reason='no HUD panel is touched' }
                        portraits = @{ Disposition='not-applicable'; Reason='no portrait is touched' }
                        item_card_2d = @{ Disposition='not-applicable'; Reason='only the dedicated Tab slot rarity texture is written, not generic item-card widgets' }
                        inventory_tooltip = @{ Disposition='not-applicable'; Reason='new Cursed logic never changes shared loadout rarity or a tooltip descriptor' }
                    }
                    ReplayEdges = @{
                        instance_load = @{ Disposition='not-applicable'; Reason='the adapter reads an already-owned exact current instance and owns no persisted item load' }
                        initial_spawn = @{ Disposition='covered'; Evidence='the first captured production-hook callback resolves and paints the exact live owner instance without a previous update' }
                        equip = @{ Disposition='covered'; Evidence='Modded/Cursed/ordinary swaps and a mismatched current loadout id exercise fresh per-slot lookup on every callback' }
                        wield = @{ Disposition='not-applicable'; Reason='Tab shows equipped slots independent of which hand is currently wielded' }
                        customize = @{ Disposition='not-applicable'; Reason='this adapter neither writes rarity nor owns the customization transaction' }
                        style_change = @{ Disposition='not-applicable'; Reason='this concern reads actual instance rarity, not style or definition identity' }
                        career_change = @{ Disposition='covered'; Evidence='a changed live career/current backend id rejects stale equipment and reaccepts only the matching replacement instance' }
                        mission_transition = @{ Disposition='covered'; Evidence='missing player manager and retired rows restore their previous widget values before world-dependent reads' }
                        respawn = @{ Disposition='covered'; Evidence='a dead old unit loses its custom widget frame and the current replacement unit reacquires only through fresh ownership' }
                        hot_join = @{ Disposition='deferred'; Reason='remote Cursed is outside this owner-only slice; no hosted join observation is claimed' }
                        peer_ready = @{ Disposition='deferred'; Reason='remote Cursed is not implemented and existing metadata readiness is unchanged' }
                        parity_ready = @{ Disposition='not-applicable'; Reason='no new numeric or semantic peer payload is introduced' }
                        rejoin = @{ Disposition='deferred'; Reason='no real rejoin or remote Cursed observation is claimed by source fixtures' }
                        preview_open = @{ Disposition='covered'; Evidence='the first production Tab callback paints a current owner row, including retained-field readback' }
                        preview_reopen = @{ Disposition='covered'; Evidence='replacement Tab content receives fresh weak-key ownership while retired content is restored' }
                        lobby_score_create = @{ Disposition='not-applicable'; Reason='no lobby or score adapter is installed by this concern' }
                        mod_disable_restore = @{ Disposition='deferred'; Reason='WOC absence/disable is tested on the next existing Tab callback; disabling CIM stops its hook and immediate restoration before native refresh remains unverified' }
                    }
                    Tests = @(
                        @{
                            Path='qa/lua/tests/test_cim_tab_preview.lua'
                            Names=@(
                                'issue598_local_cursed_frame_uses_exact_current_instance'
                                'issue598_local_frame_tracks_modded_cursed_ordinary_swaps'
                                'issue598_owner_frame_reacquires_after_respawn_and_transition'
                                'issue598_owner_frame_rechecks_career_and_each_weapon_slot'
                                'issue598_retired_rows_and_missing_loadout_clear_owner_frame'
                                'issue598_local_rarity_unknown_fails_closed'
                                'issue598_foreign_owner_never_reads_items_by_guessed_id'
                                'issue598_throwing_contexts_clear_previous_custom_frame'
                                'issue598_remote_rows_preserve_existing_wire_policy'
                                'issue598_widget_restore_is_exact_and_does_not_clobber_later_writer'
                                'issue598_owner_frame_receipts_are_bounded_and_not_acceptance_verdicts'
                            )
                            Surfaces=@('hold_tab')
                            ReplayEdges=@('initial_spawn','equip','career_change','mission_transition','respawn','preview_open','preview_reopen')
                        }
                    )
                }
            )
        }
    )
}
