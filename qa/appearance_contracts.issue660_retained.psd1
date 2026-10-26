@{
    SchemaVersion = 1
    Contracts = @(
        @{
            Id = 'cwv.issue660.greatsword-husk-post-wield'
            Issue = 660
            Claim = 'structural-only'
            Owners = @(
                'character_weapon_variants/scripts/mods/character_weapon_variants/_cwv_style_rewield.lua'
                'character_weapon_variants/scripts/mods/character_weapon_variants/_cwv_husk_path.lua'
                'character_weapon_variants/scripts/mods/character_weapon_variants/character_weapon_variants.lua'
            )
            Concerns = @(
                @{
                    Name = 'transform'
                    Surfaces = @{
                        owner_1p = @{ Disposition='deferred'; Reason='this narrow remote post-wield adapter does not migrate this surface' }
                        owner_3p = @{ Disposition='deferred'; Reason='this narrow remote post-wield adapter does not migrate this surface' }
                        bot = @{ Disposition='deferred'; Reason='this narrow remote post-wield adapter does not migrate this surface' }
                        husk = @{ Disposition='covered'; Evidence='queued Greatsword post-wield callback repairs measured drift and independently reads every pose channel' }
                        inventory_preview = @{ Disposition='deferred'; Reason='this narrow remote post-wield adapter does not migrate this surface' }
                        illusion_browser = @{ Disposition='deferred'; Reason='this narrow remote post-wield adapter does not migrate this surface' }
                        cim_preview = @{ Disposition='deferred'; Reason='this narrow remote post-wield adapter does not migrate this surface' }
                        crafting_preview = @{ Disposition='deferred'; Reason='this narrow remote post-wield adapter does not migrate this surface' }
                        lobby = @{ Disposition='deferred'; Reason='this narrow remote post-wield adapter does not migrate this surface' }
                        score_team = @{ Disposition='deferred'; Reason='this narrow remote post-wield adapter does not migrate this surface' }
                        hold_tab = @{ Disposition='not-applicable'; Reason='this surface does not consume the remote 3D weapon pose' }
                        specials = @{ Disposition='deferred'; Reason='this narrow remote post-wield adapter does not migrate this surface' }
                        remote_audio = @{ Disposition='not-applicable'; Reason='this surface does not consume the remote 3D weapon pose' }
                        hud_panels = @{ Disposition='not-applicable'; Reason='this surface does not consume the remote 3D weapon pose' }
                        portraits = @{ Disposition='not-applicable'; Reason='this surface does not consume the remote 3D weapon pose' }
                        item_card_2d = @{ Disposition='not-applicable'; Reason='this surface does not consume the remote 3D weapon pose' }
                        inventory_tooltip = @{ Disposition='not-applicable'; Reason='this surface does not consume the remote 3D weapon pose' }
                    }
                    ReplayEdges = @{
                        instance_load = @{ Disposition='deferred'; Reason='the complete lifecycle chain for this edge is outside the narrow queued post-wield proof' }
                        initial_spawn = @{ Disposition='deferred'; Reason='spawn captures a native baseline but does not itself establish final retention' }
                        equip = @{ Disposition='deferred'; Reason='the complete lifecycle chain for this edge is outside the narrow queued post-wield proof' }
                        wield = @{ Disposition='covered'; Evidence='actual planner receiver and queued coalescer callback feed bounded retained pose reconciliation' }
                        customize = @{ Disposition='deferred'; Reason='the complete lifecycle chain for this edge is outside the narrow queued post-wield proof' }
                        style_change = @{ Disposition='deferred'; Reason='the complete lifecycle chain for this edge is outside the narrow queued post-wield proof' }
                        career_change = @{ Disposition='deferred'; Reason='the complete lifecycle chain for this edge is outside the narrow queued post-wield proof' }
                        mission_transition = @{ Disposition='deferred'; Reason='the complete lifecycle chain for this edge is outside the narrow queued post-wield proof' }
                        respawn = @{ Disposition='deferred'; Reason='the complete lifecycle chain for this edge is outside the narrow queued post-wield proof' }
                        hot_join = @{ Disposition='deferred'; Reason='the complete lifecycle chain for this edge is outside the narrow queued post-wield proof' }
                        peer_ready = @{ Disposition='deferred'; Reason='the complete lifecycle chain for this edge is outside the narrow queued post-wield proof' }
                        parity_ready = @{ Disposition='not-applicable'; Reason='this observer-local adapter adds no numeric or parity transport' }
                        rejoin = @{ Disposition='deferred'; Reason='the complete lifecycle chain for this edge is outside the narrow queued post-wield proof' }
                        preview_open = @{ Disposition='deferred'; Reason='the complete lifecycle chain for this edge is outside the narrow queued post-wield proof' }
                        preview_reopen = @{ Disposition='deferred'; Reason='the complete lifecycle chain for this edge is outside the narrow queued post-wield proof' }
                        lobby_score_create = @{ Disposition='deferred'; Reason='the complete lifecycle chain for this edge is outside the narrow queued post-wield proof' }
                        mod_disable_restore = @{ Disposition='deferred'; Reason='the complete lifecycle chain for this edge is outside the narrow queued post-wield proof' }
                    }
                    Tests = @(
                        @{
                            Path='qa/lua/tests/test_cwv_greatsword_husk_retained.lua'
                            Names=@('#660 actual planner receiver queued callback repairs Greatsword pose', '#660 setter success with rejected retained pose cannot pass')
                            Surfaces=@('husk')
                            ReplayEdges=@('wield')
                        }
                    )
                }
            )
        }
    )
}
