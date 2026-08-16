@{
    SchemaVersion = 1

    # Closed vocabulary. Canonical surface and edge NAMES are owned by
    # tools/shared_lib/_lib_appearance_descriptor.lua (M.CELLS / M.EDGES) and
    # bound for this registry by tools/shared_lib/_lib_appearance_name_authority.lua;
    # check_appearance_contracts.ps1 validates every name below against that
    # authority. (This comment previously cited docs/WEAPON_APPEARANCE_STANDARD.md
    # as the source, which was never true - the doc described the vocabulary, it
    # never owned it, and the two drifted apart until #1158.)
    #
    # Every concern must declare every cell, even when the honest disposition is
    # deferred or not-applicable. Omission is never treated as success.
    SurfaceVocabulary = @(
        'owner_1p'
        'owner_3p'
        'bot'
        'husk'
        'inventory_preview'
        'illusion_browser'
        'cim_preview'
        'crafting_preview'
        'lobby'
        'score_team'
        'hold_tab'
        'specials'
        'remote_audio'
        'hud_panels'
        'portraits'
        'item_card_2d'
        'inventory_tooltip'
    )
    ReplayEdgeVocabulary = @(
        'instance_load'
        'initial_spawn'
        'equip'
        'wield'
        'customize'
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
        'fade'
        'icon'
        'name'
    )
    DispositionVocabulary = @('covered', 'deferred', 'not-applicable')

    Contracts = @(
        @{
            Id = 'cosmetics.issue420.shared-weapon-transform-owner'
            Issue = 420
            Claim = 'structural-only'
            Owners = @(
                'tools/shared_lib/_lib_weapon_appearance.lua'
                'cosmetics_tweaker/scripts/mods/cosmetics_tweaker/cosmetics_tweaker.lua'
                'cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_cos_render.lua'
                'cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_cos_equipment_assembly.lua'
                'cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_cos_preview_runtime.lua'
                'cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_cos_runtime_checks.lua'
            )
            Concerns = @(
                @{
                    Name = 'transform'
                    Surfaces = @{
                        owner_1p = @{ Disposition='covered'; Evidence='the post-create equipment adapter delegates every live 1P hand unit through the shared scale/offset owner' }
                        owner_3p = @{ Disposition='covered'; Evidence='the post-create equipment adapter delegates every live 3P hand unit through the same shared owner' }
                        bot = @{ Disposition='covered'; Evidence='bot equipment follows the same GearUtils return adapter and unit-path transform policy' }
                        husk = @{ Disposition='deferred'; Reason='remote husk equipment does not enter the Cosmetics scale/grip adapter and retains native transform' }
                        inventory_preview = @{ Disposition='covered'; Evidence='the inventory-character preview spawn adapter calls the shared scale owner with resolved spawn-data unit paths' }
                        illusion_browser = @{ Disposition='covered'; Evidence='the illusion-browser spawn adapter calls the same shared scale owner with resolved spawn-data unit paths' }
                        cim_preview = @{ Disposition='deferred'; Reason='the Athanor forge preview is not a proven Cosmetics transform consumer' }
                        crafting_preview = @{ Disposition='deferred'; Reason='the ordinary crafting bench has no proven Cosmetics transform adapter' }
                        lobby = @{ Disposition='deferred'; Reason='Cosmetics has no weapon-transform adapter for the lobby presentation' }
                        score_team = @{ Disposition='deferred'; Reason='the score-lineup owner paints outfit state but does not apply this weapon scale/grip concern' }
                        hold_tab = @{ Disposition='not-applicable'; Reason='Hold-Tab renders 2D item cards rather than a weapon unit transform' }
                        specials = @{ Disposition='deferred'; Reason='weapon-special transform retention has not been independently observed through this one-shot adapter' }
                        remote_audio = @{ Disposition='not-applicable'; Reason='the transform owner does not alter remote audio presentation' }
                        hud_panels = @{ Disposition='not-applicable'; Reason='career HUD panels do not render the weapon unit transform' }
                        portraits = @{ Disposition='not-applicable'; Reason='portrait renderers do not render the weapon unit transform' }
                        item_card_2d = @{ Disposition='not-applicable'; Reason='2D item cards consume icons rather than weapon unit transforms' }
                        inventory_tooltip = @{ Disposition='not-applicable'; Reason='inventory tooltips consume text and icons rather than weapon unit transforms' }
                    }
                    ReplayEdges = @{
                        instance_load = @{ Disposition='not-applicable'; Reason='the ordinary transform is derived from current item/unit data and stores no backend-instance payload' }
                        initial_spawn = @{ Disposition='covered'; Evidence='each supported equipment or preview unit delegates immediately after its native spawn returns' }
                        equip = @{ Disposition='covered'; Evidence='fresh equipment construction applies the resolved shared descriptor before the caller receives the result' }
                        wield = @{ Disposition='deferred'; Reason='this concern has no separate retained-state wield reconciler for an already-spawned unit' }
                        customize = @{ Disposition='covered'; Evidence='a customization preview replacement enters the illusion-browser spawn adapter and applies once to the new unit' }
                        style_change = @{ Disposition='deferred'; Reason='combat-style reconstruction has not been independently observed through this Cosmetics adapter' }
                        career_change = @{ Disposition='deferred'; Reason='career replacement is expected to construct new equipment but has no independent #420 observation' }
                        mission_transition = @{ Disposition='covered'; Evidence='replacement mission equipment receives a fresh shared-owner application with no cross-world ledger reuse' }
                        respawn = @{ Disposition='covered'; Evidence='replacement equipment units receive fresh weak-key ownership after respawn' }
                        hot_join = @{ Disposition='deferred'; Reason='the remote husk surface is not implemented for this concern' }
                        peer_ready = @{ Disposition='deferred'; Reason='there is no transform replication channel and the remote husk surface remains unsupported' }
                        parity_ready = @{ Disposition='not-applicable'; Reason='this local presentation concern sends no numeric or semantic peer payload' }
                        rejoin = @{ Disposition='deferred'; Reason='the remote husk surface is not implemented for this concern' }
                        preview_open = @{ Disposition='covered'; Evidence='each supported preview spawn resolves and delegates its visible hand units' }
                        preview_reopen = @{ Disposition='covered'; Evidence='replacement preview units receive independent weak-key ownership and one application' }
                        lobby_score_create = @{ Disposition='deferred'; Reason='lobby and score weapon transforms remain unsupported surfaces' }
                        mod_disable_restore = @{ Disposition='deferred'; Reason='already-spawned scaled units have no proven live restoration edge on mod disable' }
                    }
                    Tests = @(
                        @{
                            Path='qa/lua/tests/test_shared_weapon_appearance.lua'
                            Names=@(
                                '#420 Cosmetics ordinary transform adapter delegates to shared WeaponAppearance'
                                '#420 Cosmetics adoption rejects private scale and position setters'
                            )
                            Surfaces=@('owner_1p','owner_3p','bot','inventory_preview','illusion_browser')
                            ReplayEdges=@('initial_spawn','equip','customize','mission_transition','respawn','preview_open','preview_reopen')
                        }
                        @{
                            Path='qa/lua/tests/test_cos_equipment_assembly.lua'
                            Names=@('cos equipment assembly runs the MH embed before the vanilla spawn')
                            Surfaces=@('owner_1p','owner_3p','bot')
                            ReplayEdges=@('initial_spawn','equip','mission_transition','respawn')
                        }
                        @{
                            Path='qa/lua/tests/test_cos_preview_runtime.lua'
                            Names=@('Cosmetics preview runtime installs exact hooks once in stable order')
                            Surfaces=@('inventory_preview','illusion_browser')
                            ReplayEdges=@('customize','preview_open','preview_reopen')
                        }
                    )
                }
            )
        }
        @{
            Id = 'shared.issue749.borrowed-renderer-residency'
            Issue = 749
            Claim = 'structural-only'
            Owners = @(
                'tools/shared_lib/_lib_resource_residency.lua'
                'cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_la_bridge.lua'
                'cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_cos_custom_hats.lua'
                'cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_cos_grail_knight_set.lua'
                'cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_material_hijack_embedded.lua'
                'cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_material_hijack_embedded_anim.lua'
                'character_weapon_variants/scripts/mods/character_weapon_variants/_cwv_old_musket_preview.lua'
                'crafting_in_modded_dev/scripts/mods/crafting_in_modded_dev/_cim_athanor_icon_policy.lua'
                'crafting_in_modded_dev/scripts/mods/crafting_in_modded_dev/_cim_mission_forge_safety.lua'
                'gui_tweaker_dev/scripts/mods/gui_tweaker_dev/_gut_gui_material_guard.lua'
                'general_tweaker_dev/scripts/mods/general_tweaker_dev/_gt_bot_teleport_lab.lua'
                'general_tweaker_dev/scripts/mods/general_tweaker_dev/_gt_debug_highlights.lua'
                'weapons_of_chaos/scripts/mods/weapons_of_chaos/_woc_blightreaper_pulse.lua'
            )
            Concerns = @(
                @{
                    Name = 'material'
                    Surfaces = @{
                        owner_1p = @{ Disposition='covered'; Evidence='CWV Old Musket and WOC owned binds use strict texture and post-bind unit-material closure' }
                        owner_3p = @{ Disposition='covered'; Evidence='LA/CWV/WOC gameplay units use the same strict spawned-unit proof before native texture writes' }
                        bot = @{ Disposition='covered'; Evidence='bot weapon units enter the same CWV/WOC gameplay apply owners' }
                        husk = @{ Disposition='covered'; Evidence='LA/CWV/WOC husk units prove their own material handles rather than inheriting owner or preview proof' }
                        inventory_preview = @{ Disposition='covered'; Evidence='custom hats and supported weapon previews prove the spawned preview unit before native writes' }
                        illusion_browser = @{ Disposition='covered'; Evidence='LA and Old Musket LootItemUnitPreviewer consumers prove parent bind, real handles, and textures atomically' }
                        cim_preview = @{ Disposition='covered'; Evidence='CIM proves the exact live Gui material and the shared Old Musket/WOC preview unit contract' }
                        crafting_preview = @{ Disposition='deferred'; Reason='ordinary crafting preview boundaries remain in the full-tree legacy census without a migrated V2 consumer' }
                        lobby = @{ Disposition='deferred'; Reason='generic lobby preview native material ownership has not been migrated or empirically verified' }
                        score_team = @{ Disposition='deferred'; Reason='generic score preview native material ownership has not been migrated or empirically verified' }
                        hold_tab = @{ Disposition='deferred'; Reason='Hold-Tab icon/material closure is tracked separately and has no migrated #749 exact-Gui consumer' }
                        specials = @{ Disposition='deferred'; Reason='borrowed-resource closure at a weapon-special presentation seam has no migrated #749 exact consumer' }
                        remote_audio = @{ Disposition='not-applicable'; Reason='the #749 contract proves unit and Gui material handles, not Wwise or remote-audio resources' }
                        hud_panels = @{ Disposition='deferred'; Reason='career-HUD Gui renderer and material closure is not fully migrated into the #749 exact-consumer set' }
                        portraits = @{ Disposition='deferred'; Reason='portrait renderer and atlas closure is owned by its portrait pipeline and is not a migrated #749 exact consumer' }
                        item_card_2d = @{ Disposition='deferred'; Reason='generic 2D item-card renderer materials have no migrated #749 exact-Gui consumer proof' }
                        inventory_tooltip = @{ Disposition='deferred'; Reason='inventory-tooltip renderer and material ownership has not been migrated into the #749 exact-consumer set' }
                    }
                    ReplayEdges = @{
                        instance_load = @{ Disposition='not-applicable'; Reason='residency is proved against each live consumer and stores no per-instance state' }
                        initial_spawn = @{ Disposition='covered'; Evidence='every migrated unit seam proves closure at its event-driven initial apply' }
                        equip = @{ Disposition='covered'; Evidence='replacement/equip unit applies enter the same strict material proof' }
                        wield = @{ Disposition='covered'; Evidence='CWV/WOC gameplay and husk wield consumers prove the newly visible unit' }
                        customize = @{ Disposition='covered'; Evidence='LA/custom-hat preview replacement units are proved before applying the selected texture set' }
                        style_change = @{ Disposition='not-applicable'; Reason='the V2 contract validates native resources and does not own Combat Style state' }
                        career_change = @{ Disposition='deferred'; Reason='a paired live career-change observation across every migrated material seam is not yet captured' }
                        mission_transition = @{ Disposition='covered'; Evidence='replacement mission units and renderers perform fresh consumer-local proofs; no proof is cached across worlds' }
                        respawn = @{ Disposition='covered'; Evidence='replacement units are distinct weak-key identities and perform fresh proofs' }
                        hot_join = @{ Disposition='covered'; Evidence='new remote husk units prove their own handles before texture application' }
                        peer_ready = @{ Disposition='not-applicable'; Reason='the residency contract is local and sends no transport' }
                        parity_ready = @{ Disposition='not-applicable'; Reason='missing peer/provider capability yields to vanilla before a local native call is attempted' }
                        rejoin = @{ Disposition='covered'; Evidence='recreated husk units perform fresh local closure without retaining the departed unit proof' }
                        preview_open = @{ Disposition='covered'; Evidence='each supported preview constructs/proves the exact unit or Gui it will consume' }
                        preview_reopen = @{ Disposition='covered'; Evidence='a replacement preview never inherits another Gui or unit proof' }
                        lobby_score_create = @{ Disposition='deferred'; Reason='lobby and score preview owners remain outside the migrated V2 set' }
                        mod_disable_restore = @{ Disposition='not-applicable'; Reason='the proof creates no persistent mutation owner; skipped optional work retains donor/vanilla state' }
                    }
                    Tests = @(
                        @{
                            Path='qa/lua/tests/test_cos_resource_residency.lua'
                            Names=@(
                                'Shared #749 texture sets are atomic before native writes'
                                'Shared #749 unit material closure rejects unresolved handles'
                                'Shared #749 exact Gui closure rejects absent renderer materials'
                                'Shared #749 global material filter drops proved absence only'
                                'Cosmetics #749 active LA bridge uses strict residency at native texture boundary'
                                'Cosmetics #749 Material-Hijack writers prove atomic textures and live materials'
                            )
                            Surfaces=@('owner_1p','owner_3p','bot','husk','inventory_preview','illusion_browser','cim_preview')
                            ReplayEdges=@('initial_spawn','equip','wield','customize','mission_transition','respawn','hot_join','rejoin','preview_open','preview_reopen')
                        }
                        @{
                            Path='qa/lua/tests/test_woc_blightreaper_pulse.lua'
                            Names=@(
                                'WOC #749 proves post-bind unit material closure before texture writes'
                                'WOC #749 rejects an incomplete production residency contract before native writes'
                            )
                            Surfaces=@('owner_1p','owner_3p','bot','husk','inventory_preview','illusion_browser','cim_preview')
                            ReplayEdges=@('initial_spawn','equip','wield','mission_transition','respawn','hot_join','rejoin','preview_open','preview_reopen')
                        }
                        @{
                            Path='qa/lua/tests/test_cos_grail_knight_set.lua'
                            Names=@(
                                'Grail Knight texture residency drift fails closed before any unit write'
                                'Grail Knight armor texture residency drift fails closed before any material write'
                                'Grail Knight shield rejects null spawned materials before texture writes'
                            )
                            Surfaces=@('owner_1p','owner_3p','husk','inventory_preview','illusion_browser')
                            ReplayEdges=@('initial_spawn','equip','customize','mission_transition','respawn','hot_join','rejoin','preview_open','preview_reopen')
                        }
                    )
                }
            )
        }
        @{
            Id = 'shared.issue922.custom-unit-fade'
            Issue = 922
            Claim = 'structural-only'
            Owners = @(
                'tools/shared_lib/_lib_appearance_fade.lua'
                'character_weapon_variants/scripts/mods/character_weapon_variants/_cwv_appearance_fade.lua'
                'character_weapon_variants/scripts/mods/character_weapon_variants/character_weapon_variants.lua'
                # #1159: the owner-3P enroll edge rides SimpleInventoryExtension
                # _wield_slot, which moved verbatim into the musket equip-surface
                # owner along with the bayonet visibility sync it shares that hook
                # with. The husk enroll edge stays on the remote-husk wield
                # diagnostic, so both files own this row now.
                'character_weapon_variants/scripts/mods/character_weapon_variants/_cwv_musket_equip_surface.lua'
                'cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_cos_appearance_fade_runtime.lua'
                'cosmetics_tweaker/scripts/mods/cosmetics_tweaker/cosmetics_tweaker.lua'
                'weapons_of_chaos/scripts/mods/weapons_of_chaos/weapons_of_chaos.lua'
            )
            Concerns = @(
                @{
                    Name = 'fade'
                    Surfaces = @{
                        owner_1p = @{ Disposition = 'not-applicable'; Reason = 'camera-proximity and invisibility fade target the third-person player presentation, not the first-person weapon rig' }
                        owner_3p = @{ Disposition = 'covered'; Evidence = 'CWV and WOC submit complete inventory-plus-attachment snapshots after custom equipment creation and owner wield; Cosmetics does the same after owner attachment creation' }
                        bot = @{ Disposition = 'covered'; Evidence = 'the owner-equipment construction adapter receives bot bodies and enrolls their complete third-person snapshot without relying on a local player object' }
                        husk = @{ Disposition = 'covered'; Evidence = 'the consolidated CWV husk-wield edge, Cosmetics husk-attachment edge, and WOC husk spawn edge submit complete snapshots after custom render work' }
                        inventory_preview = @{ Disposition = 'not-applicable'; Reason = 'preview mannequins do not participate in gameplay camera-proximity or player invisibility FadeSystem state' }
                        illusion_browser = @{ Disposition = 'not-applicable'; Reason = 'the isolated cosmetic preview world does not use player FadeSystem state' }
                        cim_preview = @{ Disposition = 'not-applicable'; Reason = 'the isolated Athanor preview world does not use player FadeSystem state' }
                        crafting_preview = @{ Disposition = 'not-applicable'; Reason = 'the isolated crafting preview world does not use player FadeSystem state' }
                        lobby = @{ Disposition = 'not-applicable'; Reason = 'lobby presentation is not a gameplay camera-proximity FadeSystem owner' }
                        score_team = @{ Disposition = 'not-applicable'; Reason = 'score presentation is not a gameplay camera-proximity FadeSystem owner' }
                        hold_tab = @{ Disposition = 'not-applicable'; Reason = 'Hold-Tab renders item cards rather than linked player units' }
                        specials = @{ Disposition = 'deferred'; Reason = 'special-state custom-unit enrollment and replay has not been independently proven through the shared fade owner' }
                        remote_audio = @{ Disposition = 'not-applicable'; Reason = 'audio playback has no linked unit visibility state for the fade collector to reconcile' }
                        hud_panels = @{ Disposition = 'not-applicable'; Reason = 'career HUD panels do not render linked player units through FadeSystem' }
                        portraits = @{ Disposition = 'not-applicable'; Reason = 'portrait renderers are isolated from gameplay FadeSystem linked-unit state' }
                        item_card_2d = @{ Disposition = 'not-applicable'; Reason = '2D item cards do not render linked player units through FadeSystem' }
                        inventory_tooltip = @{ Disposition = 'not-applicable'; Reason = 'inventory tooltips do not render linked player units through FadeSystem' }
                    }
                    ReplayEdges = @{
                        instance_load = @{ Disposition = 'not-applicable'; Reason = 'fade membership is ephemeral engine state and has no persisted instance payload' }
                        initial_spawn = @{ Disposition = 'covered'; Evidence = 'custom equipment and attachment construction submit a complete snapshot after vanilla returns' }
                        equip = @{ Disposition = 'covered'; Evidence = 'owner equipment creation and wield edges submit the finished third-person units' }
                        wield = @{ Disposition = 'covered'; Evidence = 'both owner and husk wield reconstruction run the idempotent complete-snapshot adapter' }
                        customize = @{ Disposition = 'covered'; Evidence = 'weapon and attachment replacement flows through the same equipment or attachment construction seams' }
                        style_change = @{ Disposition = 'covered'; Evidence = 'CWV style reconstruction reaches the consolidated owner or husk wield edge and unchanged snapshots are deduplicated' }
                        career_change = @{ Disposition = 'covered'; Evidence = 'replacement player equipment and attachments are enrolled through their construction edges without player-object lookup' }
                        mission_transition = @{ Disposition = 'covered'; Evidence = 'new mission player equipment and attachments re-enter the construction and wield edges' }
                        respawn = @{ Disposition = 'covered'; Evidence = 'replacement player and husk units re-enter the construction and wield edges' }
                        hot_join = @{ Disposition = 'covered'; Evidence = 'late husk equipment and attachments re-enter the husk spawn, wield, and attachment edges' }
                        peer_ready = @{ Disposition = 'covered'; Evidence = 'late exact-identity re-wields converge through the same husk-wield adapter' }
                        parity_ready = @{ Disposition = 'not-applicable'; Reason = 'fade enrollment uses only already spawned local units and creates no numeric network identity' }
                        rejoin = @{ Disposition = 'covered'; Evidence = 'a recreated husk receives a fresh weak-key owner ledger and re-enters spawn/wield enrollment' }
                        preview_open = @{ Disposition = 'not-applicable'; Reason = 'preview worlds do not consume player FadeSystem state' }
                        preview_reopen = @{ Disposition = 'not-applicable'; Reason = 'preview worlds do not consume player FadeSystem state' }
                        lobby_score_create = @{ Disposition = 'not-applicable'; Reason = 'lobby and score models do not consume gameplay player FadeSystem state' }
                        mod_disable_restore = @{ Disposition = 'not-applicable'; Reason = 'the adapter adds only live units to an engine-owned snapshot; destroyed custom units disappear with normal equipment teardown' }
                    }
                    Tests = @(
                        @{
                            Path = 'qa/lua/tests/test_shared_appearance_fade.lua'
                            Names = @(
                                'appearance fade collector submits one complete deterministic snapshot'
                                'appearance fade enrollment dedupes unchanged lifecycle replays'
                                'appearance fade failures stay fail-open and retryable'
                                'all custom render owners load and invoke the canonical fade adapter'
                            )
                            Surfaces = @('owner_3p', 'bot', 'husk')
                            ReplayEdges = @('initial_spawn', 'equip', 'wield', 'customize', 'style_change', 'career_change', 'mission_transition', 'respawn', 'hot_join', 'peer_ready', 'rejoin')
                        }
                    )
                }
            )
        }
        @{
            Id = 'cim.issue882.athanor-preview-position'
            Issue = 882
            Claim = 'structural-only'
            Owners = @(
                'crafting_in_modded_dev/scripts/mods/crafting_in_modded_dev/_cim_forge_preview_policy.lua'
                'crafting_in_modded_dev/scripts/mods/crafting_in_modded_dev/_cim_forge_preview.lua'
                'crafting_in_modded_dev/scripts/mods/crafting_in_modded_dev/_cim_mission_forge_safety.lua'
                'crafting_in_modded_dev/scripts/mods/crafting_in_modded_dev/crafting_in_modded_dev.lua'
            )
            Concerns = @(
                @{
                    Name = 'transform'
                    Surfaces = @{
                        owner_1p = @{ Disposition = 'not-applicable'; Reason = 'the correction is scoped to the Athanor properties previewer and never mutates gameplay units' }
                        owner_3p = @{ Disposition = 'not-applicable'; Reason = 'the correction is scoped to the Athanor properties previewer and never mutates gameplay units' }
                        bot = @{ Disposition = 'not-applicable'; Reason = 'the correction is scoped to the Athanor properties previewer and never mutates gameplay units' }
                        husk = @{ Disposition = 'not-applicable'; Reason = 'the correction is local UI state and has no network transport or husk consumer' }
                        inventory_preview = @{ Disposition = 'not-applicable'; Reason = 'the inventory character preview uses MenuWorldPreviewer rather than HeroWindowWeaveProperties' }
                        illusion_browser = @{ Disposition = 'not-applicable'; Reason = 'the cosmetic browser uses its own LootItemUnitPreviewer surface outside the CIM forge-active gate' }
                        cim_preview = @{ Disposition = 'covered'; Evidence = 'the HeroWindowWeaveProperties adapter centers ranged editor previews, while the overview adapter preserves the native mirrored-viewport role before mission environment substitution and separates secondary from primary even when both item slot types are melee' }
                        crafting_preview = @{ Disposition = 'not-applicable'; Reason = 'the ordinary crafting preview does not instantiate HeroWindowWeaveProperties' }
                        lobby = @{ Disposition = 'not-applicable'; Reason = 'lobby preview construction does not instantiate HeroWindowWeaveProperties' }
                        score_team = @{ Disposition = 'not-applicable'; Reason = 'score preview construction does not instantiate HeroWindowWeaveProperties' }
                        hold_tab = @{ Disposition = 'not-applicable'; Reason = 'Hold-Tab renders item cards rather than the Athanor properties preview unit' }
                        specials = @{ Disposition = 'not-applicable'; Reason = 'weapon-special presentation does not instantiate the Athanor properties preview unit' }
                        remote_audio = @{ Disposition = 'not-applicable'; Reason = 'remote audio has no Athanor properties preview transform' }
                        hud_panels = @{ Disposition = 'not-applicable'; Reason = 'career HUD panels do not instantiate HeroWindowWeaveProperties' }
                        portraits = @{ Disposition = 'not-applicable'; Reason = 'portrait renderers do not instantiate HeroWindowWeaveProperties' }
                        item_card_2d = @{ Disposition = 'not-applicable'; Reason = '2D item cards do not render the Athanor properties preview unit transform' }
                        inventory_tooltip = @{ Disposition = 'not-applicable'; Reason = 'inventory tooltips do not render the Athanor properties preview unit transform' }
                    }
                    ReplayEdges = @{
                        instance_load = @{ Disposition = 'not-applicable'; Reason = 'the correction is derived from current preview slot and native position and has no persisted state' }
                        initial_spawn = @{ Disposition = 'not-applicable'; Reason = 'gameplay unit spawning does not instantiate the Athanor properties previewer' }
                        equip = @{ Disposition = 'not-applicable'; Reason = 'equip does not mutate an already-open Athanor properties preview' }
                        wield = @{ Disposition = 'not-applicable'; Reason = 'wield does not mutate an already-open Athanor properties preview' }
                        customize = @{ Disposition = 'not-applicable'; Reason = 'the correction is slot-scoped and independent of illusion selection' }
                        style_change = @{ Disposition = 'not-applicable'; Reason = 'combat style does not own the Athanor properties preview position' }
                        career_change = @{ Disposition = 'not-applicable'; Reason = 'career selection rebuilds the forge catalogue; preview placement is reapplied only when the properties view opens' }
                        mission_transition = @{ Disposition = 'not-applicable'; Reason = 'a mission transition destroys the preview; the construction adapter reapplies on the next view open' }
                        respawn = @{ Disposition = 'not-applicable'; Reason = 'respawn does not construct the Athanor properties preview' }
                        hot_join = @{ Disposition = 'not-applicable'; Reason = 'the local preview transform has no peer state' }
                        peer_ready = @{ Disposition = 'not-applicable'; Reason = 'the local preview transform has no peer state' }
                        parity_ready = @{ Disposition = 'not-applicable'; Reason = 'the local preview uses only resident vanilla coordinates and no peer registry' }
                        rejoin = @{ Disposition = 'not-applicable'; Reason = 'the local preview transform has no peer state' }
                        preview_open = @{ Disposition = 'covered'; Evidence = 'each ranged properties preview construction applies one active-only correction; each mission overview reads the viewport role captured from vanilla invert_rendering rather than guessing from item type' }
                        preview_reopen = @{ Disposition = 'covered'; Evidence = 'each replacement properties previewer recomputes from its untouched native position, and each rebuilt overview recaptures the primary/secondary viewport role before environment substitution' }
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
                                'CIM #882 overview separates by viewport role, not item slot type'
                            )
                            Surfaces = @('cim_preview')
                            ReplayEdges = @('preview_open', 'preview_reopen')
                        }
                        @{
                            Path = 'qa/lua/tests/test_cim_mission_forge_widget_safety.lua'
                            Names = @(
                                'production proves static panels and separates mission secondary overview'
                            )
                            Surfaces = @('cim_preview')
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
                # #1159: the inventory_preview stance replay moved verbatim out of
                # the entry into the keep/menu preview-surface owner. The husk and
                # gameplay replays stayed behind, so both files own this row now.
                'character_weapon_variants/scripts/mods/character_weapon_variants/_cwv_menu_preview_owner.lua'
            )
            Concerns = @(
                @{
                    Name = 'pose'
                    Surfaces = @{
                        owner_1p = @{ Disposition = 'covered'; Evidence = 'the policy and runtime regression preserve the functional blunderbuss state_machine, wield_anim, and no-ammo wield; no receiver-specific first-person mutation is made' }
                        owner_3p = @{ Disposition = 'covered'; Evidence = 'the private Outrider clone maps all three standard Saltzpyre careers to bidirectionally resident to_repeater_pistol without changing Kruber; WT closed issue 536 supplies the local-owner reload replay' }
                        bot = @{ Disposition = 'covered'; Evidence = 'Saltzpyre bots consume the same career-aware private clone mapping as the owning extension' }
                        husk = @{ Disposition = 'covered'; Evidence = 'the consolidated husk-wield edge replays the resident stance only after exact cwv_item_identity proves Outrider; malformed identity, missing lookup, dead unit, or dispatch failure fails closed' }
                        inventory_preview = @{ Disposition = 'covered'; Evidence = 'the shared item-spawn post hook replays the stance only for the exact Outrider definition and receiver career after lookup/liveness validation' }
                        illusion_browser = @{ Disposition = 'not-applicable'; Reason = 'weapon-only cosmetic preview renders the weapon unit without a character body pose' }
                        cim_preview = @{ Disposition = 'not-applicable'; Reason = 'Athanor weapon preview renders the weapon unit without a character body pose' }
                        crafting_preview = @{ Disposition = 'not-applicable'; Reason = 'crafting item preview renders the weapon unit without a character body pose' }
                        lobby = @{ Disposition = 'deferred'; Reason = 'generic lobby character reconstruction is not part of the issue claim and has no paired runtime evidence for this exact item' }
                        score_team = @{ Disposition = 'deferred'; Reason = 'score-screen character reconstruction is not part of the issue claim and has no paired runtime evidence for this exact item' }
                        hold_tab = @{ Disposition = 'not-applicable'; Reason = 'Hold-Tab displays item data and icons rather than an animated character body' }
                        specials = @{ Disposition = 'deferred'; Reason = 'Outrider stance retention across a weapon-special presentation has not been independently proven' }
                        remote_audio = @{ Disposition = 'not-applicable'; Reason = 'body stance policy does not own remote weapon audio' }
                        hud_panels = @{ Disposition = 'not-applicable'; Reason = 'career HUD panels do not render the animated Outrider character stance' }
                        portraits = @{ Disposition = 'not-applicable'; Reason = 'portrait renderers do not play the animated Outrider character stance' }
                        item_card_2d = @{ Disposition = 'not-applicable'; Reason = '2D item cards do not render an animated character body pose' }
                        inventory_tooltip = @{ Disposition = 'not-applicable'; Reason = 'inventory tooltips do not render an animated character body pose' }
                    }
                    ReplayEdges = @{
                        instance_load = @{ Disposition = 'not-applicable'; Reason = 'the receiver stance is derived from exact item and career identity and has no persisted pose state' }
                        initial_spawn = @{ Disposition = 'covered'; Evidence = 'the private template carries the receiver mapping before initial equipment construction' }
                        equip = @{ Disposition = 'covered'; Evidence = 'vanilla owner wield selection consumes the career-aware private template map' }
                        wield = @{ Disposition = 'covered'; Evidence = 'owner and consolidated husk wield edges consume the receiver-native stance' }
                        customize = @{ Disposition = 'not-applicable'; Reason = 'illusion customization does not alter the item or receiver identity that selects the stance' }
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
                            Surfaces = @('owner_1p', 'owner_3p', 'bot')
                            ReplayEdges = @('initial_spawn', 'equip', 'wield', 'mission_transition', 'respawn')
                        }
                        @{
                            Path = 'qa/lua/tests/test_cwv_outrider_animation.lua'
                            Names = @(
                                'CWV #760 husk replay is exact semantic identity gated'
                                'CWV #760 dispatch and evidence fail closed with a hard cap'
                            )
                            Surfaces = @('husk')
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
                'character_weapon_variants/scripts/mods/character_weapon_variants/_cwv_husk_path.lua'
                'character_weapon_variants/scripts/mods/character_weapon_variants/character_weapon_variants.lua'
            )
            Concerns = @(
                @{
                    Name = 'unit_identity'
                    Surfaces = @{
                        owner_1p = @{ Disposition = 'covered'; Evidence = 'exact create_equipment descriptor adapter' }
                        owner_3p = @{ Disposition = 'covered'; Evidence = 'exact create_equipment descriptor adapter' }
                        bot = @{ Disposition = 'covered'; Evidence = 'exact create_equipment descriptor adapter' }
                        husk = @{ Disposition = 'covered'; Evidence = 'husk select/spawn descriptor adapters' }
                        inventory_preview = @{ Disposition = 'covered'; Evidence = 'MenuWorldPreviewer immutable descriptor adapter' }
                        illusion_browser = @{ Disposition = 'covered'; Evidence = 'LootItemUnitPreviewer immutable descriptor adapter' }
                        cim_preview = @{ Disposition = 'covered'; Evidence = 'Athanor reuses the tested LootItemUnitPreviewer immutable descriptor adapter' }
                        crafting_preview = @{ Disposition = 'deferred'; Reason = 'ordinary crafting preview identity has not been proven to enter through either migrated immutable descriptor adapter' }
                        lobby = @{ Disposition = 'deferred'; Reason = 'generic lobby HeroPreviewer identity still has family-specific reconstruction paths' }
                        score_team = @{ Disposition = 'deferred'; Reason = 'generic score TeamPreviewer identity still has family-specific reconstruction paths' }
                        hold_tab = @{ Disposition = 'deferred'; Reason = 'Hold-Tab receives a loadout snapshot without exact backend instance identity and has no migrated descriptor adapter' }
                        specials = @{ Disposition = 'deferred'; Reason = 'exact descriptor identity has not been proven through a weapon-special presentation adapter' }
                        remote_audio = @{ Disposition = 'deferred'; Reason = 'remote weapon audio has no migrated exact-instance descriptor consumer and remains tracked by the 398/474 class' }
                        hud_panels = @{ Disposition = 'deferred'; Reason = 'career HUD panels have no migrated exact-instance CWV descriptor consumer' }
                        portraits = @{ Disposition = 'deferred'; Reason = 'portrait rendering has no migrated exact-instance CWV descriptor consumer' }
                        item_card_2d = @{ Disposition = 'deferred'; Reason = 'generic 2D item cards have no migrated exact-instance CWV descriptor consumer' }
                        inventory_tooltip = @{ Disposition = 'deferred'; Reason = 'inventory tooltips have no migrated exact-instance CWV descriptor consumer' }
                    }
                    ReplayEdges = @{
                        instance_load = @{ Disposition = 'deferred'; Reason = 'persisted exact-instance descriptor construction is not yet owned by one provider-neutral load edge' }
                        initial_spawn = @{ Disposition = 'covered'; Evidence = 'initial game-object identity publication' }
                        equip = @{ Disposition = 'covered'; Evidence = 'wield/resync publication and coalesced apply' }
                        wield = @{ Disposition = 'covered'; Evidence = 'husk wield consumes the accepted exact descriptor through the world adapter' }
                        customize = @{ Disposition = 'deferred'; Reason = 'customization changes still publish through provider-specific state paths' }
                        style_change = @{ Disposition = 'deferred'; Reason = 'Combat Style identity and effective template are outside the migrated unit-identity descriptor' }
                        career_change = @{ Disposition = 'deferred'; Reason = 'career generation invalidation is not yet owned by the provider-neutral CWV exact-unit lifecycle' }
                        mission_transition = @{ Disposition = 'covered'; Evidence = 'post-vanilla local inventory initialization starts an eight-attempt peer-ready request; each direct exact reply uses the existing fingerprint ACK/retry ledger' }
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
                                'CWV #401 #914 mission peer-ready pull is bounded and exact'
                                'CWV #660 world lifecycle adapters are bounded and vanilla-wire safe'
                            )
                            Surfaces = @('owner_1p', 'owner_3p', 'bot', 'husk')
                            ReplayEdges = @('initial_spawn', 'equip', 'wield', 'mission_transition', 'hot_join', 'peer_ready')
                        }
                        @{
                            Path = 'qa/lua/tests/test_cwv_exact_appearance.lua'
                            Names = @(
                                'CWV #660 preview adapters consume one immutable unit descriptor'
                                'CWV #660 exact skin composes independent offhand on both preview adapters'
                            )
                            Surfaces = @('inventory_preview', 'illusion_browser', 'cim_preview')
                            ReplayEdges = @()
                        }
                        @{
                            Path = 'qa/lua/tests/test_cwv_husk_adapter.lua'
                            Names = @(
                                '#474/#660 handedness preselection preserves base until the custom mesh is spawnable'
                                '#474/#660 asymmetric dual residency defers both later hand adapters'
                                '#474/#478 atomic deferral retains the base-unit crash floor'
                            )
                            Surfaces = @('husk')
                            ReplayEdges = @('wield')
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
                        bot = @{ Disposition = 'covered'; Evidence = 'the same create-equipment adapter records bot role and the identical baked descriptor' }
                        husk = @{ Disposition = 'covered'; Evidence = 'SimpleHuskInventoryExtension wield adapter tracks the renderer-local left unit without transform RPC' }
                        inventory_preview = @{ Disposition = 'covered'; Evidence = 'left-only template policy routes MenuWorldPreviewer spawn to left_unit_3p' }
                        illusion_browser = @{ Disposition = 'deferred'; Reason = 'LootItemUnitPreviewer has no proven WT baked-transform adapter for this family' }
                        cim_preview = @{ Disposition = 'deferred'; Reason = 'Athanor preview has no proven WT baked-transform adapter for this family' }
                        crafting_preview = @{ Disposition = 'deferred'; Reason = 'ordinary crafting preview has no proven WT baked-transform adapter for this family' }
                        lobby = @{ Disposition = 'deferred'; Reason = 'the concrete lobby preview constructor consuming this hook has not been source-proven for #701' }
                        score_team = @{ Disposition = 'deferred'; Reason = 'the concrete score preview constructor consuming this hook has not been source-proven for #701' }
                        hold_tab = @{ Disposition = 'not-applicable'; Reason = 'Hold-Tab renders item cards and icons rather than a linked weapon transform' }
                        specials = @{ Disposition = 'deferred'; Reason = 'the Kruber crossbow left-hand transform has not been proven across weapon-special presentation' }
                        remote_audio = @{ Disposition = 'not-applicable'; Reason = 'a linked weapon transform does not own remote audio presentation' }
                        hud_panels = @{ Disposition = 'not-applicable'; Reason = 'career HUD panels do not render the linked crossbow hand transform' }
                        portraits = @{ Disposition = 'not-applicable'; Reason = 'portrait renderers do not render the linked crossbow hand transform' }
                        item_card_2d = @{ Disposition = 'not-applicable'; Reason = '2D item cards do not render linked weapon transforms' }
                        inventory_tooltip = @{ Disposition = 'not-applicable'; Reason = 'inventory tooltips do not render linked weapon transforms' }
                    }
                    ReplayEdges = @{
                        instance_load = @{ Disposition = 'not-applicable'; Reason = 'the baked transform is keyed by item and receiver career, not persisted per instance' }
                        initial_spawn = @{ Disposition = 'covered'; Evidence = 'owner and bot create-equipment registration captures canonical position before one-shot apply' }
                        equip = @{ Disposition = 'covered'; Evidence = 'each equipment creation resolves the same item-and-career descriptor' }
                        wield = @{ Disposition = 'covered'; Evidence = 'durable writer gates on the live wielded slot and husk wield registers its renderer-local unit' }
                        customize = @{ Disposition = 'not-applicable'; Reason = 'illusion customization does not own the source-baked item-and-career transform descriptor' }
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
                            Surfaces = @('owner_3p', 'bot', 'husk')
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
                        bot = @{ Disposition = 'covered'; Evidence = 'the same create-equipment adapter tracks bot left-unit identity with no separate transform table' }
                        husk = @{ Disposition = 'covered'; Evidence = 'husk wield resolves the same receiver-and-hand descriptor against its renderer-local left unit' }
                        inventory_preview = @{ Disposition = 'covered'; Evidence = 'post-_spawn_item adapter bridges spawn_data hand flags to numeric-slot equipment units instead of guessing in _spawn_item_unit' }
                        illusion_browser = @{ Disposition = 'deferred'; Reason = 'LootItemUnitPreviewer has no proven WT baked-transform adapter for this family' }
                        cim_preview = @{ Disposition = 'deferred'; Reason = 'Athanor preview has no proven WT baked-transform adapter for this family' }
                        crafting_preview = @{ Disposition = 'deferred'; Reason = 'ordinary crafting preview has no proven WT baked-transform adapter for this family' }
                        lobby = @{ Disposition = 'deferred'; Reason = 'the concrete lobby preview constructor consuming the WT transform path has not been source-proven' }
                        score_team = @{ Disposition = 'deferred'; Reason = 'the concrete score preview constructor consuming the WT transform path has not been source-proven' }
                        hold_tab = @{ Disposition = 'not-applicable'; Reason = 'Hold-Tab renders item cards and icons rather than linked weapon transforms' }
                        specials = @{ Disposition = 'deferred'; Reason = 'the Saltzpyre shield rotation has not been proven across weapon-special presentation' }
                        remote_audio = @{ Disposition = 'not-applicable'; Reason = 'an offhand transform does not own remote audio presentation' }
                        hud_panels = @{ Disposition = 'not-applicable'; Reason = 'career HUD panels do not render linked offhand transforms' }
                        portraits = @{ Disposition = 'not-applicable'; Reason = 'portrait renderers do not render linked offhand transforms' }
                        item_card_2d = @{ Disposition = 'not-applicable'; Reason = '2D item cards do not render linked offhand transforms' }
                        inventory_tooltip = @{ Disposition = 'not-applicable'; Reason = 'inventory tooltips do not render linked offhand transforms' }
                    }
                    ReplayEdges = @{
                        instance_load = @{ Disposition = 'not-applicable'; Reason = 'the transform is baked by item and receiver career rather than persisted per backend instance' }
                        initial_spawn = @{ Disposition = 'covered'; Evidence = 'owner/bot creation and husk wield capture the canonical left-unit rotation before durable ownership' }
                        equip = @{ Disposition = 'covered'; Evidence = 'equipment creation re-resolves receiver and hand through one transform policy' }
                        wield = @{ Disposition = 'covered'; Evidence = 'durable writer gates on the live wielded slot and restores canonical rotation while stowed' }
                        customize = @{ Disposition = 'not-applicable'; Reason = 'illusion selection does not own the baked receiver-and-hand transform' }
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
                            Surfaces = @('owner_3p', 'bot', 'husk')
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
                        bot = @{ Disposition = 'not-applicable'; Reason = 'bot world rendering has no item-card name or flavor-text surface' }
                        husk = @{ Disposition = 'not-applicable'; Reason = 'remote husk world rendering has no item-card name or flavor-text surface' }
                        inventory_preview = @{ Disposition = 'covered'; Evidence = 'UIUtils exact-instance adapter publishes composed title and selected-component description' }
                        illusion_browser = @{ Disposition = 'covered'; Evidence = 'customization hover and canonical item-card descriptor consume the same decorated component option' }
                        cim_preview = @{ Disposition = 'deferred'; Reason = 'Athanor component flavor-text consumption has not been observed in source or in game' }
                        crafting_preview = @{ Disposition = 'deferred'; Reason = 'ordinary crafting component flavor-text consumption has not been observed in source or in game' }
                        lobby = @{ Disposition = 'deferred'; Reason = 'lobby item-card description consumption is not established' }
                        score_team = @{ Disposition = 'deferred'; Reason = 'score-screen item-card description consumption is not established' }
                        hold_tab = @{ Disposition = 'covered'; Evidence = 'parity-gated peer descriptor owns the composed title; Hold-Tab has no flavor-text field' }
                        specials = @{ Disposition = 'not-applicable'; Reason = 'weapon-special presentation has no item-card name or flavor-text field' }
                        remote_audio = @{ Disposition = 'not-applicable'; Reason = 'remote audio has no item-card name or flavor-text field' }
                        hud_panels = @{ Disposition = 'not-applicable'; Reason = 'career HUD panels do not consume component item-card flavor text' }
                        portraits = @{ Disposition = 'not-applicable'; Reason = 'portrait renderers do not consume component item-card text' }
                        item_card_2d = @{ Disposition = 'covered'; Evidence = 'the canonical item-card descriptor publishes the composed title and independently selected component description' }
                        inventory_tooltip = @{ Disposition = 'deferred'; Reason = 'inventory-tooltip consumption of independently selected component flavor text has not been observed in source or in game' }
                    }
                    ReplayEdges = @{
                        instance_load = @{ Disposition = 'covered'; Evidence = 'persisted record is matched back to the canonical decorated component option' }
                        initial_spawn = @{ Disposition = 'not-applicable'; Reason = 'item text resolves synchronously when a card is requested' }
                        equip = @{ Disposition = 'not-applicable'; Reason = 'item text resolves synchronously when a card is requested' }
                        wield = @{ Disposition = 'not-applicable'; Reason = 'item text resolves synchronously when a card is requested' }
                        customize = @{ Disposition = 'covered'; Evidence = 'component hover and saved exact-instance option both use the canonical descriptor' }
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
                            Surfaces = @('inventory_preview', 'illusion_browser')
                            ReplayEdges = @('instance_load', 'customize', 'preview_open', 'preview_reopen', 'mod_disable_restore')
                        }
                        @{
                            Path = 'qa/lua/tests/test_cos_item_presentation.lua'
                            Names = @(
                                'shield owns locally resident icon and independent text'
                                'component description never falls back to primary text'
                                'Hold-Tab peer identity resolves only from existing local caches'
                            )
                            Surfaces = @('inventory_preview', 'illusion_browser', 'hold_tab', 'item_card_2d')
                            ReplayEdges = @('hot_join', 'parity_ready')
                        }
                    )
                }
            )
        }
        @{
            Id = 'cosmetics.issue883.la-exact-instance-icon'
            Issue = 883
            Claim = 'structural-only'
            Owners = @(
                'cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_cos_la_instance_policy.lua'
                'cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_cos_la_inventory_icon.lua'
                'cosmetics_tweaker/scripts/mods/cosmetics_tweaker/cosmetics_tweaker.lua'
            )
            Concerns = @(
                @{
                    Name = 'icon'
                    Surfaces = @{
                        owner_1p = @{ Disposition = 'not-applicable'; Reason = 'first-person weapon units do not render inventory-card icons' }
                        owner_3p = @{ Disposition = 'not-applicable'; Reason = 'third-person weapon units do not render inventory-card icons' }
                        bot = @{ Disposition = 'not-applicable'; Reason = 'bot weapon units do not render inventory-card icons' }
                        husk = @{ Disposition = 'not-applicable'; Reason = 'remote husk weapon units do not render local inventory-card icons' }
                        inventory_preview = @{ Disposition = 'covered'; Evidence = 'the singleton UIUtils adapter resolves the LA icon from exact backend identity, exact item skin, and authored SKIN_LIST data without mutating shared registries' }
                        illusion_browser = @{ Disposition = 'deferred'; Reason = 'the illusion picker uses skin widgets rather than the exact backend-item UIUtils card adapter' }
                        cim_preview = @{ Disposition = 'deferred'; Reason = 'Athanor icon ownership is a separate exact-identity adapter and is not claimed by issue 883' }
                        crafting_preview = @{ Disposition = 'deferred'; Reason = 'ordinary crafting rows may not carry the exact persisted backend identity required by this contract' }
                        lobby = @{ Disposition = 'deferred'; Reason = 'lobby item-card exact backend identity and LA atlas capability have not been proven' }
                        score_team = @{ Disposition = 'deferred'; Reason = 'score-screen item-card exact backend identity and LA atlas capability have not been proven' }
                        hold_tab = @{ Disposition = 'deferred'; Reason = 'Hold-Tab receives peer-safe loadout presentation through a separate adapter' }
                        specials = @{ Disposition = 'not-applicable'; Reason = 'weapon-special presentation does not render an inventory-card icon' }
                        remote_audio = @{ Disposition = 'not-applicable'; Reason = 'remote audio does not render an inventory-card icon' }
                        hud_panels = @{ Disposition = 'deferred'; Reason = 'career-HUD consumption of the exact backend-instance LA icon has not been proven' }
                        portraits = @{ Disposition = 'not-applicable'; Reason = 'career portraits do not consume the exact backend-instance weapon icon adapter' }
                        item_card_2d = @{ Disposition = 'covered'; Evidence = 'the singleton UIUtils card adapter resolves the LA icon from exact backend identity and exact authored skin data' }
                        inventory_tooltip = @{ Disposition = 'deferred'; Reason = 'inventory-tooltip use of the exact backend-instance LA icon adapter has not been proven' }
                    }
                    ReplayEdges = @{
                        instance_load = @{ Disposition = 'covered'; Evidence = 'persisted exact-item illusion and offhand records resolve through the same pure provider on the next card request' }
                        initial_spawn = @{ Disposition = 'not-applicable'; Reason = 'weapon spawning does not create inventory-card icon state' }
                        equip = @{ Disposition = 'not-applicable'; Reason = 'inventory-card icon resolution is synchronous and independent of equipped world units' }
                        wield = @{ Disposition = 'not-applicable'; Reason = 'inventory-card icon resolution is synchronous and independent of wield state' }
                        customize = @{ Disposition = 'covered'; Evidence = 'the committed exact-instance selection is read on the next inventory-card request' }
                        style_change = @{ Disposition = 'not-applicable'; Reason = 'combat style does not own LA cosmetic icon identity' }
                        career_change = @{ Disposition = 'not-applicable'; Reason = 'the icon provider keys the exact item rather than retaining career-local card state' }
                        mission_transition = @{ Disposition = 'not-applicable'; Reason = 'the local card resolves persisted identity on demand after any transition' }
                        respawn = @{ Disposition = 'not-applicable'; Reason = 'respawn does not retain inventory-card icon state' }
                        hot_join = @{ Disposition = 'not-applicable'; Reason = 'issue 883 owns local exact-instance inventory icons and sends no custom icon identity' }
                        peer_ready = @{ Disposition = 'not-applicable'; Reason = 'issue 883 owns local exact-instance inventory icons and sends no custom icon identity' }
                        parity_ready = @{ Disposition = 'not-applicable'; Reason = 'the local LA atlas/provider is required and no icon identity is sent to peers' }
                        rejoin = @{ Disposition = 'not-applicable'; Reason = 'the local card resolves persisted identity on demand rather than replaying peer state' }
                        preview_open = @{ Disposition = 'covered'; Evidence = 'each inventory-card request resolves from current exact identity with no retained grid-cell state' }
                        preview_reopen = @{ Disposition = 'covered'; Evidence = 'the resolver has no screen-local cache and re-evaluates the persisted item state' }
                        lobby_score_create = @{ Disposition = 'deferred'; Reason = 'lobby and score card adapters remain outside this exact inventory surface' }
                        mod_disable_restore = @{ Disposition = 'covered'; Evidence = 'the adapter never mutates WeaponSkins or ItemMasterList, so vanilla presentation remains authoritative when Cosmetics is disabled' }
                    }
                    Tests = @(
                        @{
                            Path = 'qa/lua/tests/test_cos_la_instance_policy.lua'
                            Names = @(
                                'direct LA Armoury identities resolve without hat-outfit clone maps (#883)'
                                'inventory icon provider bounds and deduplicates automatic diagnostics (#883)'
                                'offhand icon prefers exact item skin before bridge paint fallback (#883)'
                                'persisted row-one LA icon is exact-backend-instance only'
                                'unknown LA metadata fails closed to vanilla icon'
                            )
                            Surfaces = @('inventory_preview', 'item_card_2d')
                            ReplayEdges = @('instance_load', 'customize', 'preview_open', 'preview_reopen', 'mod_disable_restore')
                        }
                    )
                }
            )
        }
        @{
            Id = 'cosmetics.issue923.la-target-option-icon'
            Issue = 923
            Claim = 'structural-only'
            Owners = @(
                'cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_cos_la_option_icon_policy.lua'
                'cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_la_bridge.lua'
                'cosmetics_tweaker/scripts/mods/cosmetics_tweaker/cosmetics_tweaker.lua'
            )
            Concerns = @(
                @{
                    Name = 'icon'
                    Surfaces = @{
                        owner_1p = @{ Disposition = 'not-applicable'; Reason = 'first-person held units do not render item-card icons' }
                        owner_3p = @{ Disposition = 'not-applicable'; Reason = 'third-person held units do not render item-card icons' }
                        bot = @{ Disposition = 'not-applicable'; Reason = 'bot held units do not render item-card icons' }
                        husk = @{ Disposition = 'not-applicable'; Reason = 'remote husks never receive provider-owned icon assets' }
                        inventory_preview = @{ Disposition = 'covered'; Evidence = 'the exact item target and exact current skin resolve only their authored LA SKIN_LIST icon; missing mappings retain the native card without generic sibling-unit recovery' }
                        illusion_browser = @{ Disposition = 'deferred'; Reason = 'row-two cells currently render rarity presentation rather than a provider icon texture' }
                        cim_preview = @{ Disposition = 'deferred'; Reason = 'Athanor presentation is owned by its separate exact-identity adapter' }
                        crafting_preview = @{ Disposition = 'deferred'; Reason = 'ordinary crafting rows are outside the row-two exact-item adapter' }
                        lobby = @{ Disposition = 'deferred'; Reason = 'lobby renderer provider-atlas capability has not been proven' }
                        score_team = @{ Disposition = 'deferred'; Reason = 'score renderer provider-atlas capability has not been proven' }
                        hold_tab = @{ Disposition = 'deferred'; Reason = 'Hold-Tab uses peer-safe native synchronized identity and cannot consume an unsynchronized provider asset' }
                        specials = @{ Disposition = 'not-applicable'; Reason = 'weapon-special presentation does not render an item-card option icon' }
                        remote_audio = @{ Disposition = 'not-applicable'; Reason = 'remote audio does not render an item-card option icon' }
                        hud_panels = @{ Disposition = 'deferred'; Reason = 'career-HUD provider-atlas capability for the exact LA target icon has not been proven' }
                        portraits = @{ Disposition = 'not-applicable'; Reason = 'career portraits do not consume the exact LA target-option icon adapter' }
                        item_card_2d = @{ Disposition = 'covered'; Evidence = 'the exact item target and current skin resolve only their authored LA option icon on the native 2D card' }
                        inventory_tooltip = @{ Disposition = 'deferred'; Reason = 'inventory-tooltip provider-atlas capability for the exact LA target icon has not been proven' }
                    }
                    ReplayEdges = @{
                        instance_load = @{ Disposition = 'covered'; Evidence = 'restore resolves the saved Armoury key through an item-type and hand-qualified option index for the exact backend item' }
                        initial_spawn = @{ Disposition = 'not-applicable'; Reason = 'world-unit spawning does not own item-card icon presentation' }
                        equip = @{ Disposition = 'not-applicable'; Reason = 'equip state does not cache target option icons' }
                        wield = @{ Disposition = 'not-applicable'; Reason = 'wield state does not cache target option icons' }
                        customize = @{ Disposition = 'covered'; Evidence = 'a click creates a per-item runtime copy bound through preview then exact selected row-one identity, never stale equipped state, without mutating the canonical pool' }
                        style_change = @{ Disposition = 'not-applicable'; Reason = 'combat style does not own LA option icon identity' }
                        career_change = @{ Disposition = 'covered'; Evidence = 'target qualification is item-type based and card resolution re-evaluates the exact item after career changes' }
                        mission_transition = @{ Disposition = 'covered'; Evidence = 'provider icon names are not retained in peer state; exact local identity is resolved again on card request' }
                        respawn = @{ Disposition = 'not-applicable'; Reason = 'respawn does not own item-card icon state' }
                        hot_join = @{ Disposition = 'not-applicable'; Reason = 'provider-owned icons are local and are never sent to joining peers' }
                        peer_ready = @{ Disposition = 'not-applicable'; Reason = 'provider-owned icons are local and require no peer replay' }
                        parity_ready = @{ Disposition = 'not-applicable'; Reason = 'no provider icon identity crosses the network boundary' }
                        rejoin = @{ Disposition = 'covered'; Evidence = 'restart/rejoin reads the semantic exact-item record and re-resolves the local provider mapping' }
                        preview_open = @{ Disposition = 'covered'; Evidence = 'opening the exact item card resolves its current skin and target-qualified option' }
                        preview_reopen = @{ Disposition = 'covered'; Evidence = 'canonical target options are immutable and each reopen re-resolves the provider mapping' }
                        lobby_score_create = @{ Disposition = 'deferred'; Reason = 'lobby and score renderers remain outside this local inventory-card adapter' }
                        mod_disable_restore = @{ Disposition = 'covered'; Evidence = 'no shared WeaponSkins or ItemMasterList icon is mutated, so disabling Cosmetics restores native presentation' }
                    }
                    Tests = @(
                        @{
                            Path = 'qa/lua/tests/test_cos_la_option_icon_policy.lua'
                            Names = @(
                                'LA target options are immutable per weapon family (#923)'
                                'Kotbs mace and spear resolve their distinct exact LA icons (#923)'
                                'exact runed skin mapping is not collapsed to a representative icon'
                                'unauthored and sibling targets retain their native icon'
                                '_cos_option_for_record keeps native icon after exact LA miss'
                                'Cosmetics-authored unit options retain generic icon recovery'
                                'pending preview skin outranks stale equipped widget (#923)'
                                'primary skin fallback order is backend interface then default'
                                'restore lookup requires exact item type hand and Armoury key'
                                'source does not persist or transmit external provider icon assets'
                            )
                            Surfaces = @('inventory_preview', 'item_card_2d')
                            ReplayEdges = @('instance_load', 'customize', 'career_change', 'mission_transition', 'rejoin', 'preview_open', 'preview_reopen', 'mod_disable_restore')
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
                        bot = @{ Disposition = 'not-applicable'; Reason = 'bot weapon units do not render inventory icons' }
                        husk = @{ Disposition = 'not-applicable'; Reason = 'remote husk units do not render inventory icons' }
                        inventory_preview = @{ Disposition = 'covered'; Evidence = 'CWV hero_view injection already owns and advertises the paired atlas' }
                        illusion_browser = @{ Disposition = 'deferred'; Reason = 'the cosmetic browser has a separate renderer and is outside the CIM selector claim' }
                        cim_preview = @{ Disposition = 'covered'; Evidence = 'the shared ingame_ui top-renderer capability plus exact masked-saturated live-Gui proof retains the paired icon' }
                        crafting_preview = @{ Disposition = 'deferred'; Reason = 'the ordinary crafting picker does not consume the Athanor sanitizer' }
                        lobby = @{ Disposition = 'deferred'; Reason = 'lobby item-card icon residency is owned by its renderer-specific contract' }
                        score_team = @{ Disposition = 'deferred'; Reason = 'score-screen item-card icon residency is owned by its renderer-specific contract' }
                        hold_tab = @{ Disposition = 'deferred'; Reason = 'Hold-Tab item-card icon residency is owned by its peer-safe renderer contract' }
                        specials = @{ Disposition = 'not-applicable'; Reason = 'weapon-special presentation does not render a 2D inventory icon' }
                        remote_audio = @{ Disposition = 'not-applicable'; Reason = 'remote audio does not render a 2D inventory icon' }
                        hud_panels = @{ Disposition = 'deferred'; Reason = 'career-HUD renderer ownership of the paired dual-axes atlas has not been proven' }
                        portraits = @{ Disposition = 'not-applicable'; Reason = 'career portraits do not render the paired dual-axes inventory icon' }
                        item_card_2d = @{ Disposition = 'covered'; Evidence = 'the packaged paired dual-axes atlas and renderer allow-list provide the authored icon with a resident vanilla fallback' }
                        inventory_tooltip = @{ Disposition = 'deferred'; Reason = 'inventory-tooltip renderer ownership of the paired dual-axes atlas has not been proven' }
                    }
                    ReplayEdges = @{
                        instance_load = @{ Disposition = 'not-applicable'; Reason = 'the authored icon is immutable provider data, not per-instance state' }
                        initial_spawn = @{ Disposition = 'not-applicable'; Reason = 'weapon spawn does not create item-list icons' }
                        equip = @{ Disposition = 'not-applicable'; Reason = 'equip does not create the Athanor selector' }
                        wield = @{ Disposition = 'not-applicable'; Reason = 'wield does not create the Athanor selector' }
                        customize = @{ Disposition = 'not-applicable'; Reason = 'the synthetic base crafting row has no exact backend-instance identity and must not enter the Cosmetics primary/offhand/glow compositor' }
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
                            Surfaces = @('inventory_preview', 'cim_preview', 'item_card_2d')
                            ReplayEdges = @()
                        }
                        @{
                            Path = 'qa/lua/tests/test_cim_athanor_icon_policy.lua'
                            Names = @(
                                'renderer-owned CWV Dual Axes icons remain authored in Athanor'
                                'every live CWV custom inventory icon closes to vanilla in Athanor'
                            )
                            Surfaces = @('cim_preview')
                            ReplayEdges = @('preview_open', 'preview_reopen', 'mod_disable_restore')
                        }
                        @{
                            Path = 'qa/lua/tests/test_cim_cwv_template_catalog.lua'
                            Names = @('every CWV family keeps exact definition and authored icon')
                            Surfaces = @('cim_preview')
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
                        bot = @{ Disposition = 'covered'; Evidence = 'the positively identified non-1P GearUtils recipe consumes the same descriptor' }
                        husk = @{ Disposition = 'covered'; Evidence = 'husk GearUtils return adapter consumes the same descriptor without transform RPC' }
                        inventory_preview = @{ Disposition = 'covered'; Evidence = 'HeroPreviewer character-preview adapter consumes the same descriptor' }
                        illusion_browser = @{ Disposition = 'covered'; Evidence = 'LootItemUnitPreviewer item-preview adapter consumes the same descriptor' }
                        cim_preview = @{ Disposition = 'covered'; Evidence = 'Athanor reuses the LootItemUnitPreviewer item-preview adapter' }
                        crafting_preview = @{ Disposition = 'deferred'; Reason = 'the vanilla forge layout does not instantiate LootItemUnitPreviewer, so WOC has no proven bench-specific unit-transform adapter' }
                        lobby = @{ Disposition = 'covered'; Evidence = 'MenuWorldPreviewer character-preview adapter consumes the same descriptor' }
                        score_team = @{ Disposition = 'covered'; Evidence = 'score/end character preview reuses the HeroPreviewer/MenuWorldPreviewer adapter' }
                        hold_tab = @{ Disposition = 'not-applicable'; Reason = 'Hold-Tab renders item cards and icons, not a weapon unit transform' }
                        specials = @{ Disposition = 'deferred'; Reason = 'Blightreaper transform retention across weapon-special presentation has not been independently proven' }
                        remote_audio = @{ Disposition = 'not-applicable'; Reason = 'the Blightreaper unit transform contract does not own remote audio presentation' }
                        hud_panels = @{ Disposition = 'not-applicable'; Reason = 'career HUD panels do not render the Blightreaper unit transform' }
                        portraits = @{ Disposition = 'not-applicable'; Reason = 'portrait renderers do not render the Blightreaper unit transform' }
                        item_card_2d = @{ Disposition = 'not-applicable'; Reason = '2D item cards render an icon rather than the Blightreaper unit transform' }
                        inventory_tooltip = @{ Disposition = 'not-applicable'; Reason = 'inventory tooltips render text and icons rather than the Blightreaper unit transform' }
                    }
                    ReplayEdges = @{
                        instance_load = @{ Disposition = 'not-applicable'; Reason = 'the immutable transform descriptor has no per-instance persisted state' }
                        initial_spawn = @{ Disposition = 'covered'; Evidence = 'each GearUtils return is adapted before the caller receives it' }
                        equip = @{ Disposition = 'covered'; Evidence = 'equip creates a fresh GearUtils recipe and applies the descriptor' }
                        wield = @{ Disposition = 'covered'; Evidence = 'wielded owner and husk units are weak-tracked for measured pose drift' }
                        customize = @{ Disposition = 'not-applicable'; Reason = 'the immutable relic has no selectable cosmetic transform' }
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
                                'owner_1p', 'owner_3p', 'bot', 'husk',
                                'inventory_preview', 'illusion_browser', 'cim_preview',
                                'crafting_preview', 'lobby', 'score_team'
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
                # #1159: the inventory_preview and item_browser transform_decision
                # consumers moved verbatim into the keep/menu preview-surface
                # owner; the gameplay consumer stayed in the entry.
                'character_weapon_variants/scripts/mods/character_weapon_variants/_cwv_menu_preview_owner.lua'
                # #1159: the `_resolve_cwv_def` transform_decision rung and the
                # authored inverse-Bretonnian presentation records both resolve
                # through the weapon-transform owner now. The entry still holds
                # the Combat Style install that AUTHORS those records.
                'character_weapon_variants/scripts/mods/character_weapon_variants/_cwv_weapon_transform_owner.lua'
            )
            Concerns = @(
                @{
                    Name = 'transform'
                    Surfaces = @{
                        owner_1p = @{ Disposition = 'covered'; Evidence = 'unified inverse descriptor reaches create_equipment owner first-person roots' }
                        owner_3p = @{ Disposition = 'covered'; Evidence = 'unified inverse descriptor reaches create_equipment owner third-person roots' }
                        bot = @{ Disposition = 'covered'; Evidence = 'create_equipment uses the same resolved descriptor for bot third-person roots' }
                        husk = @{ Disposition = 'covered'; Evidence = 'remote style state resolves the concrete Bretonnian receiver descriptor before husk transform apply' }
                        inventory_preview = @{ Disposition = 'covered'; Evidence = 'MenuWorldPreviewer resolves the exact instance style and applies the unified inverse descriptor' }
                        illusion_browser = @{ Disposition = 'covered'; Evidence = 'LootItemUnitPreviewer resolves the exact instance style and applies the unified inverse descriptor' }
                        cim_preview = @{ Disposition = 'covered'; Evidence = 'Athanor reuses the LootItemUnitPreviewer exact-instance transform seam' }
                        crafting_preview = @{ Disposition = 'deferred'; Reason = 'ordinary crafting preview has no proven exact backend instance style identity' }
                        lobby = @{ Disposition = 'covered'; Evidence = 'lobby HeroPreviewer reuses the MenuWorldPreviewer equipment-unit transform seam' }
                        score_team = @{ Disposition = 'covered'; Evidence = 'team score HeroPreviewer reuses the MenuWorldPreviewer equipment-unit transform seam' }
                        hold_tab = @{ Disposition = 'deferred'; Reason = 'Hold-Tab does not expose a proven exact backend instance style to the appearance resolver' }
                        specials = @{ Disposition = 'deferred'; Reason = 'reciprocal Bretonnian transform retention across weapon-special presentation has not been independently proven' }
                        remote_audio = @{ Disposition = 'not-applicable'; Reason = 'the reciprocal transform contract does not own remote weapon audio' }
                        hud_panels = @{ Disposition = 'not-applicable'; Reason = 'career HUD panels do not render reciprocal weapon transforms' }
                        portraits = @{ Disposition = 'not-applicable'; Reason = 'portrait renderers do not render reciprocal weapon transforms' }
                        item_card_2d = @{ Disposition = 'not-applicable'; Reason = '2D item cards do not render reciprocal weapon transforms' }
                        inventory_tooltip = @{ Disposition = 'not-applicable'; Reason = 'inventory tooltips do not render reciprocal weapon transforms' }
                    }
                    ReplayEdges = @{
                        instance_load = @{ Disposition = 'covered'; Evidence = 'exact backend instance style is loaded from the schema-checked Combat Style store' }
                        initial_spawn = @{ Disposition = 'covered'; Evidence = 'owner/bot create and remote husk spawn resolve the receiver descriptor before applying the transform' }
                        equip = @{ Disposition = 'covered'; Evidence = 'every equipment creation resolves the current exact-instance style' }
                        wield = @{ Disposition = 'covered'; Evidence = 'owner and husk wield rebuild paths resolve the current exact-instance or remote style' }
                        customize = @{ Disposition = 'not-applicable'; Reason = 'the reciprocal transform belongs to Combat Style, not cosmetic customization' }
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
                                'owner_1p', 'owner_3p', 'bot', 'husk',
                                'inventory_preview', 'illusion_browser', 'cim_preview',
                                'lobby', 'score_team'
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
            Id = 'cosmetics.issue481.cim-exact-offhand-preview'
            Issue = 481
            Claim = 'structural-only'
            Owners = @(
                'crafting_in_modded_dev/scripts/mods/crafting_in_modded_dev/_cim_forge_preview.lua'
                'crafting_in_modded_dev/scripts/mods/crafting_in_modded_dev/_cim_mission_forge_safety.lua'
                'cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_cos_cim_preview.lua'
                'cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_cos_cim_preview_wiring.lua'
                'cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_cos_equipment_assembly.lua'
                'cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_cos_preview_runtime.lua'
                'cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_la_bridge.lua'
                'cosmetics_tweaker/scripts/mods/cosmetics_tweaker/cosmetics_tweaker.lua'
            )
            Concerns = @(
                @{
                    Name = 'unit_identity'
                    Surfaces = @{
                        owner_1p = @{ Disposition = 'not-applicable'; Reason = 'the CIM constructor context is never published around live first-person equipment construction' }
                        owner_3p = @{ Disposition = 'not-applicable'; Reason = 'the CIM constructor context is never published around live third-person equipment construction' }
                        bot = @{ Disposition = 'not-applicable'; Reason = 'bot equipment does not enter a CIM Athanor constructor' }
                        husk = @{ Disposition = 'not-applicable'; Reason = 'remote husks never consume owner-local CIM preview context' }
                        inventory_preview = @{ Disposition = 'not-applicable'; Reason = 'inventory preview has its own item identity adapter and receives no CIM marker' }
                        illusion_browser = @{ Disposition = 'not-applicable'; Reason = 'ordinary illusion-browser instances receive no CIM marker and retain their existing identity policy' }
                        cim_preview = @{ Disposition = 'covered'; Evidence = 'all three real Athanor constructors publish one stack-scoped exact context during synchronous unit resolution and attach that same table to only the returned previewer' }
                        crafting_preview = @{ Disposition = 'not-applicable'; Reason = 'the ordinary crafting bench does not enter a CIM Athanor constructor' }
                        lobby = @{ Disposition = 'not-applicable'; Reason = 'lobby presentation receives no CIM constructor marker' }
                        score_team = @{ Disposition = 'not-applicable'; Reason = 'score presentation receives no CIM constructor marker' }
                        hold_tab = @{ Disposition = 'not-applicable'; Reason = 'Hold-Tab reconstructs cards without a CIM previewer instance' }
                        specials = @{ Disposition = 'not-applicable'; Reason = 'weapon-special presentation does not construct an Athanor previewer' }
                        remote_audio = @{ Disposition = 'not-applicable'; Reason = 'the local CIM preview context owns no audio identity' }
                        hud_panels = @{ Disposition = 'not-applicable'; Reason = 'career HUD panels do not construct an Athanor item previewer' }
                        portraits = @{ Disposition = 'not-applicable'; Reason = 'portrait renderers do not construct an Athanor item previewer' }
                        item_card_2d = @{ Disposition = 'not-applicable'; Reason = 'the contract classifies a live 3D previewer rather than a 2D item card' }
                        inventory_tooltip = @{ Disposition = 'not-applicable'; Reason = 'tooltips do not consume the CIM preview marker' }
                    }
                    ReplayEdges = @{
                        instance_load = @{ Disposition = 'not-applicable'; Reason = 'the context is constructed per preview and is not persisted' }
                        initial_spawn = @{ Disposition = 'not-applicable'; Reason = 'gameplay spawn does not enter the Athanor constructor scope' }
                        equip = @{ Disposition = 'not-applicable'; Reason = 'equipping an item does not construct the local Athanor preview' }
                        wield = @{ Disposition = 'not-applicable'; Reason = 'wield does not construct the local Athanor preview' }
                        customize = @{ Disposition = 'not-applicable'; Reason = 'the Cosmetics customization browser uses a separate identity transaction' }
                        style_change = @{ Disposition = 'not-applicable'; Reason = 'style state is outside the exact CIM preview-context identity' }
                        career_change = @{ Disposition = 'not-applicable'; Reason = 'career change does not replay a retained CIM preview context' }
                        mission_transition = @{ Disposition = 'not-applicable'; Reason = 'the context owns no cross-world or mission state' }
                        respawn = @{ Disposition = 'not-applicable'; Reason = 'respawn does not replay local Athanor preview identity' }
                        hot_join = @{ Disposition = 'not-applicable'; Reason = 'the context is owner-local and sends no peer payload' }
                        peer_ready = @{ Disposition = 'not-applicable'; Reason = 'the context is owner-local and sends no peer payload' }
                        parity_ready = @{ Disposition = 'not-applicable'; Reason = 'the context sends no content-parity payload' }
                        rejoin = @{ Disposition = 'not-applicable'; Reason = 'rejoin does not replay local Athanor preview identity' }
                        preview_open = @{ Disposition = 'covered'; Evidence = 'a fresh constructor generation wraps synchronous BackendUtils resolution and marks exactly its returned previewer' }
                        preview_reopen = @{ Disposition = 'covered'; Evidence = 'a reopened constructor receives a new generation; nested, failed, foreign, backendless, and stale contexts fail closed' }
                        lobby_score_create = @{ Disposition = 'not-applicable'; Reason = 'lobby and score constructors never receive a CIM marker' }
                        mod_disable_restore = @{ Disposition = 'deferred'; Reason = 'live disable while an already-open Athanor previewer exists has no independent runtime observation' }
                    }
                    Tests = @(
                        @{
                            Path = 'qa/lua/tests/test_cim_forge_preview_owner.lua'
                            Names = @(
                                'CIM exact preview context wraps all three real constructors'
                                'CIM preview context is stack-safe and clears after errors'
                                'CIM preview context targets all three decompiled Athanor constructors'
                            )
                            Surfaces = @('cim_preview')
                            ReplayEdges = @('preview_open', 'preview_reopen')
                        }
                        @{
                            Path = 'qa/lua/tests/test_cos_equipment_assembly.lua'
                            Names = @('cos equipment assembly admits only exact CIM context')
                            Surfaces = @('cim_preview')
                            ReplayEdges = @('preview_open', 'preview_reopen')
                        }
                    )
                }
                @{
                    Name = 'material'
                    Surfaces = @{
                        owner_1p = @{ Disposition = 'not-applicable'; Reason = 'this adapter applies only to the local Athanor preview' }
                        owner_3p = @{ Disposition = 'not-applicable'; Reason = 'this adapter applies only to the local Athanor preview' }
                        bot = @{ Disposition = 'not-applicable'; Reason = 'bots never consume the local Athanor preview transaction' }
                        husk = @{ Disposition = 'not-applicable'; Reason = 'the transaction is local and publishes no material payload to husks' }
                        inventory_preview = @{ Disposition = 'not-applicable'; Reason = 'inventory preview retains its existing Cosmetics material owner' }
                        illusion_browser = @{ Disposition = 'not-applicable'; Reason = 'the ordinary illusion browser retains its existing Cosmetics material owner' }
                        cim_preview = @{ Disposition = 'covered'; Evidence = 'only an exact backend-owned current Loremaster selection with resident 3P unit and an already-loaded known parent enters the bounded generation-safe material reconcile' }
                        crafting_preview = @{ Disposition = 'not-applicable'; Reason = 'ordinary crafting preview does not consume this adapter' }
                        lobby = @{ Disposition = 'not-applicable'; Reason = 'lobby material presentation does not consume this adapter' }
                        score_team = @{ Disposition = 'not-applicable'; Reason = 'score material presentation does not consume this adapter' }
                        hold_tab = @{ Disposition = 'not-applicable'; Reason = 'Hold-Tab renders 2D cards rather than the live preview material' }
                        specials = @{ Disposition = 'not-applicable'; Reason = 'weapon-special materials are outside this preview transaction' }
                        remote_audio = @{ Disposition = 'not-applicable'; Reason = 'material reconcile owns no audio behavior' }
                        hud_panels = @{ Disposition = 'not-applicable'; Reason = 'HUD panels do not render the Athanor weapon material' }
                        portraits = @{ Disposition = 'not-applicable'; Reason = 'portraits do not render the Athanor weapon material' }
                        item_card_2d = @{ Disposition = 'not-applicable'; Reason = '2D cards consume icons rather than this material reconcile' }
                        inventory_tooltip = @{ Disposition = 'not-applicable'; Reason = 'tooltips consume text and icons rather than this material reconcile' }
                    }
                    ReplayEdges = @{
                        instance_load = @{ Disposition = 'not-applicable'; Reason = 'the adapter persists no engine material object' }
                        initial_spawn = @{ Disposition = 'not-applicable'; Reason = 'gameplay initial spawn uses a different material owner' }
                        equip = @{ Disposition = 'not-applicable'; Reason = 'gameplay equip uses a different material owner' }
                        wield = @{ Disposition = 'not-applicable'; Reason = 'gameplay wield uses a different material owner' }
                        customize = @{ Disposition = 'not-applicable'; Reason = 'the adapter consumes an already-committed exact selection and writes no picker state' }
                        style_change = @{ Disposition = 'not-applicable'; Reason = 'combat style is outside the Loremaster offhand material selection' }
                        career_change = @{ Disposition = 'not-applicable'; Reason = 'career change does not replay this preview transaction' }
                        mission_transition = @{ Disposition = 'not-applicable'; Reason = 'the adapter retains no cross-world material object' }
                        respawn = @{ Disposition = 'not-applicable'; Reason = 'respawn does not replay a local preview material job' }
                        hot_join = @{ Disposition = 'not-applicable'; Reason = 'the adapter sends no peer material payload' }
                        peer_ready = @{ Disposition = 'not-applicable'; Reason = 'the adapter sends no peer material payload' }
                        parity_ready = @{ Disposition = 'not-applicable'; Reason = 'the adapter sends no content-parity payload' }
                        rejoin = @{ Disposition = 'not-applicable'; Reason = 'rejoin does not replay a local preview material job' }
                        preview_open = @{ Disposition = 'covered'; Evidence = 'spawn_data hand/path pairing creates a bounded job and applies only through the existing guarded exact-material adapter' }
                        preview_reopen = @{ Disposition = 'covered'; Evidence = 'destroy releases the per-previewer parent lease and a new generation cannot execute stale queued work' }
                        lobby_score_create = @{ Disposition = 'not-applicable'; Reason = 'lobby and score creation do not consume this material adapter' }
                        mod_disable_restore = @{ Disposition = 'deferred'; Reason = 'already-painted live preview restoration on Cosmetics disable is not proven in game' }
                    }
                    Tests = @(
                        @{
                            Path = 'qa/lua/tests/test_cos_cim_preview.lua'
                            Names = @(
                                'Cosmetics CIM preview exact identity fails closed'
                                'Cosmetics CIM preview retains only an already-loaded parent'
                                'Cosmetics CIM preview keeps malformed scopes off generic load'
                                'Cosmetics CIM preview matches hand path and applies at neutral surface'
                                'Cosmetics CIM preview retries boundedly then retains base'
                                'Cosmetics CIM preview isolates generations and simultaneous previewers'
                                'Cosmetics CIM preview drops stale work across destroy and reopen'
                                'Cosmetics CIM source contains no unsafe native setters'
                            )
                            Surfaces = @('cim_preview')
                            ReplayEdges = @('preview_open', 'preview_reopen')
                        }
                        @{
                            Path = 'qa/lua/tests/test_cos_preview_runtime.lua'
                            Names = @('Cosmetics preview runtime never falls from CIM into generic parent load')
                            Surfaces = @('cim_preview')
                            ReplayEdges = @('preview_open', 'preview_reopen')
                        }
                    )
                }
                @{
                    Name = 'transform'
                    Surfaces = @{
                        owner_1p = @{ Disposition = 'not-applicable'; Reason = 'this surface decision is scoped only to CIM-marked previewers' }
                        owner_3p = @{ Disposition = 'not-applicable'; Reason = 'this surface decision is scoped only to CIM-marked previewers' }
                        bot = @{ Disposition = 'not-applicable'; Reason = 'bots never consume a CIM-marked previewer' }
                        husk = @{ Disposition = 'not-applicable'; Reason = 'husks never consume a CIM-marked previewer' }
                        inventory_preview = @{ Disposition = 'not-applicable'; Reason = 'inventory preview keeps its existing transform policy' }
                        illusion_browser = @{ Disposition = 'not-applicable'; Reason = 'ordinary illusion preview keeps its existing generic transform policy' }
                        cim_preview = @{ Disposition = 'covered'; Evidence = 'the exact CIM surface explicitly bypasses the generic customization 2.0 scale path and starts from the native neutral transform pending visual proof' }
                        crafting_preview = @{ Disposition = 'not-applicable'; Reason = 'ordinary crafting preview does not consume this surface classifier' }
                        lobby = @{ Disposition = 'not-applicable'; Reason = 'lobby transform is outside this surface classifier' }
                        score_team = @{ Disposition = 'not-applicable'; Reason = 'score transform is outside this surface classifier' }
                        hold_tab = @{ Disposition = 'not-applicable'; Reason = 'Hold-Tab renders no live weapon transform' }
                        specials = @{ Disposition = 'not-applicable'; Reason = 'weapon-special transform is outside this preview classifier' }
                        remote_audio = @{ Disposition = 'not-applicable'; Reason = 'transform classification owns no audio behavior' }
                        hud_panels = @{ Disposition = 'not-applicable'; Reason = 'HUD panels render no Athanor weapon transform' }
                        portraits = @{ Disposition = 'not-applicable'; Reason = 'portraits render no Athanor weapon transform' }
                        item_card_2d = @{ Disposition = 'not-applicable'; Reason = '2D cards render no live weapon transform' }
                        inventory_tooltip = @{ Disposition = 'not-applicable'; Reason = 'tooltips render no live weapon transform' }
                    }
                    ReplayEdges = @{
                        instance_load = @{ Disposition = 'not-applicable'; Reason = 'the neutral decision retains no transform state' }
                        initial_spawn = @{ Disposition = 'not-applicable'; Reason = 'gameplay spawn uses a separate transform owner' }
                        equip = @{ Disposition = 'not-applicable'; Reason = 'gameplay equip uses a separate transform owner' }
                        wield = @{ Disposition = 'not-applicable'; Reason = 'gameplay wield uses a separate transform owner' }
                        customize = @{ Disposition = 'not-applicable'; Reason = 'the generic customization transform remains owned by the ordinary browser path' }
                        style_change = @{ Disposition = 'not-applicable'; Reason = 'style transforms are outside this CIM surface decision' }
                        career_change = @{ Disposition = 'not-applicable'; Reason = 'career change does not replay a retained CIM transform' }
                        mission_transition = @{ Disposition = 'not-applicable'; Reason = 'the native neutral decision stores no cross-world transform' }
                        respawn = @{ Disposition = 'not-applicable'; Reason = 'respawn does not replay a local CIM transform' }
                        hot_join = @{ Disposition = 'not-applicable'; Reason = 'the decision sends no peer payload' }
                        peer_ready = @{ Disposition = 'not-applicable'; Reason = 'the decision sends no peer payload' }
                        parity_ready = @{ Disposition = 'not-applicable'; Reason = 'the decision sends no parity payload' }
                        rejoin = @{ Disposition = 'not-applicable'; Reason = 'rejoin does not replay a local CIM transform' }
                        preview_open = @{ Disposition = 'covered'; Evidence = 'surface classification occurs before generic preview transform application and returns early without a scale write' }
                        preview_reopen = @{ Disposition = 'covered'; Evidence = 'each replacement CIM marker repeats the same neutral decision while ordinary previewers still take the generic scale path' }
                        lobby_score_create = @{ Disposition = 'not-applicable'; Reason = 'lobby and score constructors never receive this CIM classifier' }
                        mod_disable_restore = @{ Disposition = 'not-applicable'; Reason = 'the CIM branch writes no transform that would require restoration' }
                    }
                    Tests = @(
                        @{
                            Path = 'qa/lua/tests/test_cos_preview_runtime.lua'
                            Names = @('Cosmetics preview runtime routes CIM without generic LA scale')
                            Surfaces = @('cim_preview')
                            ReplayEdges = @('preview_open', 'preview_reopen')
                        }
                    )
                }
            )
        }
        @{
            Id = 'cosmetics.issue48.cim-exact-glow-persistence'
            Issue = 48
            Claim = 'structural-only'
            Owners = @(
                'cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_cos_glow_cim_bridge.lua'
                'cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_glow_picker.lua'
                'cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_cos_glow.lua'
                'cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_cos_runtime_checks.lua'
                'cosmetics_tweaker/scripts/mods/cosmetics_tweaker/cosmetics_tweaker.lua'
            )
            Concerns = @(
                @{
                    Name = 'glow'
                    Surfaces = @{
                        owner_1p = @{ Disposition = 'covered'; Evidence = 'spawn-time exact-instance restore feeds the existing owner first-person glow renderer' }
                        owner_3p = @{ Disposition = 'covered'; Evidence = 'the same imported exact state feeds owner third-person units without a CIM renderer' }
                        bot = @{ Disposition = 'deferred'; Reason = 'CIM-crafted bot loadout ownership has no proven exact backend-instance bridge in this slice' }
                        husk = @{ Disposition = 'covered'; Evidence = 'an imported owner state enters the existing semantic per-wearer glow transport; CIM identifiers never cross the wire' }
                        inventory_preview = @{ Disposition = 'covered'; Evidence = 'inventory preview reuses restore_runtime_for with exact backend item and skin evidence' }
                        illusion_browser = @{ Disposition = 'covered'; Evidence = 'the customization preview reads the same exact state and existing bounded paint adapter' }
                        cim_preview = @{ Disposition = 'deferred'; Reason = 'CIM Athanor preview does not yet expose a dedicated Cosmetics glow adapter' }
                        crafting_preview = @{ Disposition = 'deferred'; Reason = 'ordinary crafting preview exact-instance glow rendering is not part of this persistence slice' }
                        lobby = @{ Disposition = 'deferred'; Reason = 'generic lobby weapon glow presentation has no newly migrated exact-instance adapter' }
                        score_team = @{ Disposition = 'deferred'; Reason = 'score weapon glow presentation has no newly migrated exact-instance adapter' }
                        hold_tab = @{ Disposition = 'not-applicable'; Reason = 'Hold-Tab has no backend instance identity and this slice emits no custom icon/material there' }
                        specials = @{ Disposition = 'deferred'; Reason = 'exact-instance glow retention across weapon-special presentation has not been independently proven' }
                        remote_audio = @{ Disposition = 'not-applicable'; Reason = 'glow persistence does not own remote audio presentation' }
                        hud_panels = @{ Disposition = 'not-applicable'; Reason = 'career HUD panels do not render the exact weapon material glow' }
                        portraits = @{ Disposition = 'not-applicable'; Reason = 'portrait renderers do not render the exact weapon material glow' }
                        item_card_2d = @{ Disposition = 'not-applicable'; Reason = '2D item cards render authored icons rather than live material glow' }
                        inventory_tooltip = @{ Disposition = 'not-applicable'; Reason = 'inventory tooltips render text and icons rather than live material glow' }
                    }
                    ReplayEdges = @{
                        instance_load = @{ Disposition = 'covered'; Evidence = 'a schema-validated CIM blob imports only on a Cosmetics-local exact-identity miss' }
                        initial_spawn = @{ Disposition = 'covered'; Evidence = 'existing owner equipment creation calls restore_runtime_for before glow paint' }
                        equip = @{ Disposition = 'covered'; Evidence = 'equipment and inventory preview equip paths resolve one exact backend item plus illusion' }
                        wield = @{ Disposition = 'covered'; Evidence = 'local wield rehydrates the exact state before publishing and painting it' }
                        customize = @{ Disposition = 'covered'; Evidence = 'explicit Apply writes both authoritative Cosmetics state and the bounded CIM backup' }
                        style_change = @{ Disposition = 'not-applicable'; Reason = 'combat style is not part of the item-plus-illusion glow identity' }
                        career_change = @{ Disposition = 'deferred'; Reason = 'cross-career CIM exact-instance retention has not been observed in game' }
                        mission_transition = @{ Disposition = 'covered'; Evidence = 'replacement equipment units repeat spawn-time exact restore; no engine object is retained' }
                        respawn = @{ Disposition = 'covered'; Evidence = 'replacement units repeat the same backend-item plus illusion import and paint path' }
                        hot_join = @{ Disposition = 'covered'; Evidence = 'the existing host-authoritative glow state pull transports semantic wearer state, never CIM data' }
                        peer_ready = @{ Disposition = 'covered'; Evidence = 'the existing acknowledged peer-ready pull replays imported active glow state' }
                        parity_ready = @{ Disposition = 'not-applicable'; Reason = 'CIM persistence is owner-local and absent Cosmetics peers receive only resident vanilla appearance' }
                        rejoin = @{ Disposition = 'covered'; Evidence = 'new local and husk units reconstruct from owner-local persistence and semantic peer state' }
                        preview_open = @{ Disposition = 'covered'; Evidence = 'preview open restores exact state without requiring a prior editor open' }
                        preview_reopen = @{ Disposition = 'covered'; Evidence = 'preview rebuild repeats exact restore and cannot reuse a different illusion blob' }
                        lobby_score_create = @{ Disposition = 'deferred'; Reason = 'lobby and score glow consumers are outside this persistence slice' }
                        mod_disable_restore = @{ Disposition = 'deferred'; Reason = 'live Cosmetics disable material restoration is not proven; CIM absence remains inert on a new session' }
                    }
                    Tests = @(
                        @{
                            Path = 'qa/lua/tests/test_cos_glow_cim_bridge.lua'
                            Names = @(
                                'Cosmetics #48 CIM blob is bounded and exact-instance scoped'
                                'Cosmetics #48 CIM restore rejects schema and illusion drift'
                                'Cosmetics #48 CIM bridge prefers the dev stream'
                                'Cosmetics #48 CIM write and read use public exact-craft APIs'
                                'Cosmetics #48 CIM clear cannot erase another illusion'
                                'Cosmetics #48 CIM bridge fails closed on malformed siblings'
                                'Cosmetics #48 CIM registration is bounded and idempotent'
                                'Cosmetics #48 CIM restore callback rebinds realized units once'
                            )
                            Surfaces = @('owner_1p', 'owner_3p', 'husk', 'inventory_preview', 'illusion_browser')
                            ReplayEdges = @('instance_load', 'customize')
                        }
                        @{
                            Path = 'qa/lua/tests/test_cos_glow_lifecycle.lua'
                            Names = @(
                                'Cosmetics glow persistence is exact-item plus illusion and explicit-Apply'
                                'Cosmetics glow replay is host-authoritative and locally bounded'
                                'Cosmetics glow repaints equipment preview and remote wield surfaces'
                            )
                            Surfaces = @('owner_1p', 'owner_3p', 'husk', 'inventory_preview', 'illusion_browser')
                            ReplayEdges = @('initial_spawn', 'equip', 'wield', 'mission_transition', 'respawn', 'hot_join', 'peer_ready', 'rejoin', 'preview_open', 'preview_reopen')
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
                        bot = @{ Disposition = 'covered'; Evidence = 'non-human peer aliases cannot consume or invalidate the human peer appearance store' }
                        husk = @{ Disposition = 'covered'; Evidence = 'every stored and transported material record carries an exact wearer career checked before husk mesh or material replay' }
                        inventory_preview = @{ Disposition = 'not-applicable'; Reason = 'inventory preview does not consume the live remote-husk peer store' }
                        illusion_browser = @{ Disposition = 'not-applicable'; Reason = 'cosmetic preview does not consume the live remote-husk peer store' }
                        cim_preview = @{ Disposition = 'not-applicable'; Reason = 'Athanor preview does not consume the live remote-husk peer store' }
                        crafting_preview = @{ Disposition = 'not-applicable'; Reason = 'ordinary crafting preview does not consume the live remote-husk peer store' }
                        lobby = @{ Disposition = 'deferred'; Reason = 'generic lobby preview uses separate wearer reconstruction and is not governed by the husk career boundary' }
                        score_team = @{ Disposition = 'deferred'; Reason = 'score-screen identity is governed by the separate #513 exact score-row boundary' }
                        hold_tab = @{ Disposition = 'not-applicable'; Reason = 'Hold-Tab does not render live wearer materials' }
                        specials = @{ Disposition = 'deferred'; Reason = 'career-scoped husk material retention across weapon-special presentation has not been independently proven' }
                        remote_audio = @{ Disposition = 'not-applicable'; Reason = 'career-scoped husk materials do not own remote audio presentation' }
                        hud_panels = @{ Disposition = 'not-applicable'; Reason = 'career HUD panels do not render live remote-husk materials' }
                        portraits = @{ Disposition = 'not-applicable'; Reason = 'portrait renderers do not consume the live remote-husk material store' }
                        item_card_2d = @{ Disposition = 'not-applicable'; Reason = '2D item cards do not consume the live remote-husk material store' }
                        inventory_tooltip = @{ Disposition = 'not-applicable'; Reason = 'inventory tooltips do not consume the live remote-husk material store' }
                    }
                    ReplayEdges = @{
                        instance_load = @{ Disposition = 'deferred'; Reason = 'persisted local selection loading is owned by the LA persistence layer before publication' }
                        initial_spawn = @{ Disposition = 'covered'; Evidence = 'husk pre-wield invalidation runs before vanilla spawn and post-wield material replay' }
                        equip = @{ Disposition = 'covered'; Evidence = 'host and client apply paths stamp and validate the exact wearer career' }
                        wield = @{ Disposition = 'covered'; Evidence = 'SimpleHuskInventoryExtension._wield_slot rejects unproven bot aliases and mismatched career records' }
                        customize = @{ Disposition = 'covered'; Evidence = 'the canonical LA emit path requires and transports the live wearer career with each changed selection' }
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
                            Surfaces = @('bot', 'husk')
                            ReplayEdges = @('initial_spawn', 'equip', 'wield', 'customize', 'career_change', 'mission_transition', 'respawn', 'hot_join', 'peer_ready')
                        }
                    )
                }
            )
        }
    )
}
