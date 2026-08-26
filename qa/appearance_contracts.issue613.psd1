@{
    SchemaVersion = 1
    Contracts = @(
        @{
            Id = 'woc.issue613.team-preview-identity'
            Issue = 613
            Claim = 'structural-only'
            Owners = @(
                'weapons_of_chaos/scripts/mods/weapons_of_chaos/_woc_team_preview_identity.lua'
                'weapons_of_chaos/scripts/mods/weapons_of_chaos/_woc_issue613_preview_owner.lua'
                'weapons_of_chaos/scripts/mods/weapons_of_chaos/_woc_mod_unit_preview.lua'
                'weapons_of_chaos/scripts/mods/weapons_of_chaos/_woc_shared_relic_runtime.lua'
                'weapons_of_chaos/scripts/mods/weapons_of_chaos/weapons_of_chaos.lua'
            )
            Concerns = @(
                @{
                    Name = 'unit_identity'
                    Surfaces = @{
                        owner_1p = @{ Disposition = 'not-applicable'; Reason = 'the local owner resolves the exact backend item directly and does not need the remote-wearer TeamPreviewer bridge' }
                        owner_3p = @{ Disposition = 'not-applicable'; Reason = 'the local owner resolves the exact backend item directly and does not need the remote-wearer TeamPreviewer bridge' }
                        bot = @{ Disposition = 'not-applicable'; Reason = 'bots are explicitly rejected by the remote TeamPreviewer identity boundary' }
                        husk = @{ Disposition = 'covered'; Evidence = 'the accepted host lease snapshot atomically updates the remote cache and re-wields only the changed exact peer' }
                        inventory_preview = @{ Disposition = 'not-applicable'; Reason = 'the local inventory preview receives exact item data rather than a remote TeamPreviewer wearer' }
                        illusion_browser = @{ Disposition = 'not-applicable'; Reason = 'the illusion browser receives exact local item data rather than a remote TeamPreviewer wearer' }
                        cim_preview = @{ Disposition = 'not-applicable'; Reason = 'Athanor receives exact local item data and is separately identified by its exact factory marker' }
                        crafting_preview = @{ Disposition = 'not-applicable'; Reason = 'the ordinary crafting bench has no TeamPreviewer remote-wearer row' }
                        lobby = @{ Disposition = 'covered'; Evidence = 'TeamPreviewer resolves an exact non-bot profile, career, and local-player-1 row before asynchronous hero spawn, then consumes only the accepted host lease snapshot' }
                        score_team = @{ Disposition = 'covered'; Evidence = 'TeamPreviewer requires an exact player-controlled local-player-1 score row before consuming the accepted host lease snapshot' }
                        hold_tab = @{ Disposition = 'not-applicable'; Reason = 'Hold-Tab does not instantiate the TeamPreviewer weapon-unit consumer owned by this bridge' }
                        specials = @{ Disposition = 'not-applicable'; Reason = 'weapon-special presentation is outside the TeamPreviewer remote-wearer bridge' }
                        remote_audio = @{ Disposition = 'not-applicable'; Reason = 'remote audio identity is outside the TeamPreviewer weapon-unit bridge' }
                        hud_panels = @{ Disposition = 'not-applicable'; Reason = 'career HUD panels do not instantiate TeamPreviewer weapon rows' }
                        portraits = @{ Disposition = 'not-applicable'; Reason = 'portrait renderers do not instantiate TeamPreviewer weapon rows' }
                        item_card_2d = @{ Disposition = 'not-applicable'; Reason = '2D item cards do not instantiate the TeamPreviewer weapon-unit consumer' }
                        inventory_tooltip = @{ Disposition = 'not-applicable'; Reason = 'inventory tooltips do not instantiate the TeamPreviewer weapon-unit consumer' }
                    }
                    ReplayEdges = @{
                        instance_load = @{ Disposition = 'not-applicable'; Reason = 'the host lease snapshot is session authority state rather than persisted per-preview identity' }
                        initial_spawn = @{ Disposition = 'deferred'; Reason = 'initial remote gameplay spawn remains covered by the existing husk path but has no focused #613 paired runtime fixture' }
                        equip = @{ Disposition = 'covered'; Evidence = 'a new authenticated slot generation updates the exact peer cache and notifies an existing preview consumer once' }
                        wield = @{ Disposition = 'covered'; Evidence = 'each changed remote cache entry re-wields that exact peer before the preview notification is emitted' }
                        customize = @{ Disposition = 'not-applicable'; Reason = 'Blightreaper is immutable and the bridge never treats a skin field as identity' }
                        style_change = @{ Disposition = 'not-applicable'; Reason = 'Blightreaper identity has no combat-style variants' }
                        career_change = @{ Disposition = 'deferred'; Reason = 'a live TeamPreviewer career replacement still needs paired in-game lifecycle evidence' }
                        mission_transition = @{ Disposition = 'deferred'; Reason = 'session rehydration is structurally covered elsewhere but no in-game visual transition pass is claimed here' }
                        respawn = @{ Disposition = 'deferred'; Reason = 'remote respawn identity still requires paired in-game lifecycle evidence' }
                        hot_join = @{ Disposition = 'covered'; Evidence = 'a joining client requests and accepts the host complete snapshot before exact remote cache and consumer replay' }
                        peer_ready = @{ Disposition = 'covered'; Evidence = 'the client query returns the authenticated host snapshot and a late existing consumer receives one generation-bound replay' }
                        parity_ready = @{ Disposition = 'not-applicable'; Reason = 'the same-mod lease channel has no separate appearance-parity payload' }
                        rejoin = @{ Disposition = 'deferred'; Reason = 'leave and rejoin generation retirement still requires paired in-game lifecycle evidence' }
                        preview_open = @{ Disposition = 'covered'; Evidence = 'a newly created TeamPreviewer row queries the current accepted snapshot on each exact slot equip' }
                        preview_reopen = @{ Disposition = 'deferred'; Reason = 'a full close and reopen sequence remains for in-game verification' }
                        lobby_score_create = @{ Disposition = 'covered'; Evidence = 'live and score constructors stamp exact wearer identity before asynchronous preview item creation' }
                        mod_disable_restore = @{ Disposition = 'deferred'; Reason = 'live restoration of an already-created TeamPreviewer row after disable is not proven' }
                    }
                    Tests = @(
                        @{
                            Path = 'qa/lua/tests/test_woc_team_preview_identity.lua'
                            Names = @(
                                'WOC #613 score identity resolves only the exact human wearer'
                                'WOC #613 live identity rejects bots and profile-only matches'
                                'WOC #613 accepted snapshot token is peer generation and key bound'
                            )
                            Surfaces = @('lobby', 'score_team')
                            ReplayEdges = @()
                        }
                        @{
                            Path = 'qa/lua/tests/test_woc_shared_relic.lua'
                            Names = @('WOC #613 host snapshot reaches cache rewield and TeamPreviewer once')
                            Surfaces = @('husk')
                            ReplayEdges = @('equip', 'wield', 'hot_join', 'peer_ready')
                        }
                        @{
                            Path = 'qa/lua/tests/test_woc_mod_unit_preview.lua'
                            Names = @(
                                'WOC #613 delayed TeamPreviewer identity replays once and fails stale closed'
                                'WOC #613 live lobby resolver stamps the exact human wearer'
                            )
                            Surfaces = @('lobby', 'score_team')
                            ReplayEdges = @('peer_ready', 'preview_open', 'lobby_score_create')
                        }
                    )
                }
            )
        }
    )
}
