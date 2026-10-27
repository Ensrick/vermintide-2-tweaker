@{
    SchemaVersion = 1
    Contracts = @(
        @{
            Id = 'cwv.issue428.old-musket-effective-template-admission'
            Issue = 428
            Claim = 'structural-only'
            Owners = @(
                'character_weapon_variants/scripts/mods/character_weapon_variants/character_weapon_variants.lua'
                'character_weapon_variants/scripts/mods/character_weapon_variants/_cwv_musket_runtime.lua'
                'character_weapon_variants/scripts/mods/character_weapon_variants/_cwv_old_musket_shot_owner.lua'
                'character_weapon_variants/scripts/mods/character_weapon_variants/_cwv_old_musket_melee_owner.lua'
                'character_weapon_variants/scripts/mods/character_weapon_variants/_cwv_profile_graph_transaction.lua'
                'character_weapon_variants/scripts/mods/character_weapon_variants/_cwv_guard428_old_musket_sweep.lua'
                'character_weapon_variants/scripts/mods/character_weapon_variants/_cwv_variant_bootstrap_owner.lua'
                'character_weapon_variants/scripts/mods/character_weapon_variants/_cwv_item_registration_owner.lua'
            )
            Concerns = @(
                @{
                    Name = 'effective_template'
                    Surfaces = @{
                        owner_1p = @{ Disposition='covered'; Evidence='the actual installed singleton resolver returns only proven owned Old Musket templates after native-first/style/Crowbill precedence; this is source selection, not native action or rendered acceptance' }
                        owner_3p = @{ Disposition='deferred'; Reason='the complete returned-template owner3P consumer and rendered stance are not executed by this construction slice; #474 remains separate' }
                        bot = @{ Disposition='deferred'; Reason='bot wield/action consumers are outside this local admission and stance proof' }
                        husk = @{ Disposition='deferred'; Reason='remote template/pose transport and reconstruction remain independent #474 acceptance' }
                        inventory_preview = @{ Disposition='deferred'; Reason='inventory model template/pose consumers are unchanged and not proven by registration readiness' }
                        illusion_browser = @{ Disposition='deferred'; Reason='browser preview consumers are not exercised by this construction slice' }
                        cim_preview = @{ Disposition='deferred'; Reason='CIM pending restore and seed refusal are proven, but its actual preview template consumer is not' }
                        crafting_preview = @{ Disposition='deferred'; Reason='native crafting renderer/preview selection is outside this admission proof' }
                        lobby = @{ Disposition='deferred'; Reason='lobby preview mode/pose remains a separate appearance concern' }
                        score_team = @{ Disposition='deferred'; Reason='score/team preview mode/pose remains a separate appearance concern' }
                        hold_tab = @{ Disposition='not-applicable'; Reason='this owner neither chooses icons/names nor renders Hold-Tab item cards' }
                        specials = @{ Disposition='not-applicable'; Reason='Old Musket player-item construction does not select special-enemy templates' }
                        remote_audio = @{ Disposition='not-applicable'; Reason='no audio route, sound world or replicated report changes belong to this slice' }
                        hud_panels = @{ Disposition='not-applicable'; Reason='ammo/HUD presentation remains owned by the existing independent adapter' }
                        portraits = @{ Disposition='not-applicable'; Reason='weapon combat-template admission has no portrait consumer' }
                        item_card_2d = @{ Disposition='not-applicable'; Reason='this owner does not mutate item-card icon or rarity presentation' }
                        inventory_tooltip = @{ Disposition='not-applicable'; Reason='this owner does not mutate tooltip presentation' }
                    }
                    ReplayEdges = @{
                        instance_load = @{ Disposition='covered'; Evidence='actual private builder/seed refusal and exact CIM missing-master restore/retry preserve saved records without publishing an unproven fresh item' }
                        initial_spawn = @{ Disposition='deferred'; Reason='complete native Sweep start is executed with ledger collaborators; actual unit spawn/Stingray ABI and rendered acceptance remain unproven' }
                        equip = @{ Disposition='deferred'; Reason='actual equipment spawn/destruction ABI remains live acceptance' }
                        wield = @{ Disposition='covered'; Evidence='the installed stance callback refuses an unproven target before mod_data, publication, ammo or destroy/add/wield; native rebuilt geometry remains unverified' }
                        customize = @{ Disposition='not-applicable'; Reason='this owner does not mutate model/illusion/glow customization' }
                        style_change = @{ Disposition='covered'; Evidence='Old Musket mode selection and proven ranged fallback are exercised through the actual installed callback and singleton resolver; Combat Style families are unchanged' }
                        career_change = @{ Disposition='deferred'; Reason='actual canonical career-action installer composition is tested, but a live career transition is not' }
                        mission_transition = @{ Disposition='deferred'; Reason='mission retained template/action/appearance state remains independent live acceptance' }
                        respawn = @{ Disposition='deferred'; Reason='respawn native action/equipment consumers are outside this construction slice' }
                        hot_join = @{ Disposition='deferred'; Reason='peer identity/template replay remains the existing independent transport owner' }
                        peer_ready = @{ Disposition='deferred'; Reason='no peer channel or readiness handshake changes are introduced' }
                        parity_ready = @{ Disposition='deferred'; Reason='#423 sender fingerprint/receiver safety is preserved but not re-proven by local construction' }
                        rejoin = @{ Disposition='deferred'; Reason='rejoin transport and rendered mode are separate acceptance' }
                        preview_open = @{ Disposition='deferred'; Reason='no actual previewer consumer is exercised here' }
                        preview_reopen = @{ Disposition='deferred'; Reason='no actual preview reopening edge is exercised here' }
                        lobby_score_create = @{ Disposition='deferred'; Reason='lobby/score preview adapters remain unchanged and outside this proof' }
                        mod_disable_restore = @{ Disposition='not-applicable'; Reason='boot admission has no supported hot-reload/mod-disable registry replacement contract' }
                    }
                    Tests = @(
                        @{
                            Path = 'qa/lua/tests/test_cwv_old_musket_retained_sweep.lua'
                            Names = @(
                                '#428 retained Sweep healthy final native flush is not suppressed'
                                '#428 retained Sweep outer error after Sweep returns retains terminal without cleanup retry'
                            )
                            Surfaces = @('owner_1p')
                            ReplayEdges = @('wield')
                        }
                        @{
                            Path = 'qa/lua/tests/test_cwv_old_musket_melee_owner.lua'
                            Names = @(
                                '#428 bayonet actual singleton router keeps native first precedence and finite authority'
                                '#428 bayonet composite actual builder seed pending and retained closure by value'
                                '#428 bayonet actual CIM missing-master restore keeps exact saved record pending'
                                '#428 bayonet target stance preflight precedes all item wire ammo slot mutations'
                            )
                            Surfaces = @('owner_1p')
                            ReplayEdges = @('instance_load','wield','style_change')
                        }
                    )
                }
            )
        }
    )
}
