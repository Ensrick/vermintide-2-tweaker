# Co-op Playtest Checklist

> Auto-generated on 2026-07-20 18:50 UTC. Plain-language co-op-only checklist for a second tester.

Thanks for helping test. Each item below is either a fix to verify or a diagnostic check that needs real co-op evidence. You do not need any of our tools or notes, just the game and this list.

## Before you start
- Make sure everyone in the group has updated to the newest version of each mod. Re-subscribe if you are not sure.
- Turn on the in-game console log if you can, so we can read it afterward. If you cannot, just watch for anything that looks wrong on screen.
- Play in ONE group/lobby the whole time so you can tick off as many items as possible in a single session.
- "It works if" describes a fix PASS. "Please report" marks a diagnostic check. If you see a crash or the wrong thing, note the item number and what happened.

## Suggested order
1. Everyone joins one lobby in the keep and confirms the game loaded the newest mod versions.
2. Do the checks that happen in the keep or when someone joins a game in progress.
3. Start a normal mission together and do the in-mission checks.
4. Play through to the end-of-round score screen and check those items.
5. If some items need a third player, add one and redo just those.

## Games with 2 players

1. (Item #139) General: Blanket leash veto at the BTConditions.should_teleport hook, applied to the FINAL decision ΓÇö so it vetoes both vanilla's 40 m and gt's tighter leash. With aid-priori...
   - It works if: everything behaves normally for all players and nobody crashes.
2. (Item #278) cross-mod: host runs cim/cwv, a joining player joins WITHOUT the mod. Host equips a crafted or skinned CWV/cim item (loadout sync).
   - It works if: everything behaves normally for all players and nobody crashes.
3. (Item #413) Events: Tick Shadow (Winds of Magic) in event_tweaker; start any Adventure mission.
   - It works if: everything behaves normally for all players and nobody crashes.
4. (Item #421) cross-mod: On the Cosmetics player, equip ct_es_mace_gk_shield_01 or any ct_es_heavy_spear_deus_* illusion and run /cos_421_diag.
   - It works if: everything behaves normally for all players and nobody crashes.
5. (Item #371) GUI: host runs cwv; a player joins WITHOUT cwv. Host equips the Tuskgor Javelin (cwv_es_javelin) bomb pool.
   - Please report: attach both players' logs and note what appeared on each player's screen.
6. (Item #474) Cosmetics: Equip the Old Musket in each supported slot/mode and inspect owner first person, inventory preview, owner third person, and other players' characters.
   - Please report: attach both players' logs and note what appeared on each player's screen.
7. (Item #807) As Grail Knight, equip the CWV Kruber Rapier in the secondary/ranged slot, close/reopen Hero View, swap repeatedly, and enter a mission.
   - Please report: attach both players' logs and note what appeared on each player's screen.
8. (Item #749) cross-mod: Host and joining player load the current Cosmetics/CIM/CWV borrowed-renderer fixes.
   - Please report: attach both players' logs and note what appeared on each player's screen.
9. (Item #423) The CWV joining player lands hits with cloned-profile variants such as Imperial Longsword and Old Musket.
   - Please report: attach both players' logs and note what appeared on each player's screen.
10. (Item #660) GUI: Host equips one transformed CWV weapon with a custom illusion; also keep one unmodified vanilla weapon as a control.
   - Please report: attach both players' logs and note what appeared on each player's screen.
11. (Item #430) Events: Both in the keep lobby. Expected within ~4s on the host: chat notice "[Events] player-parity: disabled Cursed Adventure curses.
   - Please report: within ~4s on the host: chat notice "[Events] player-parity: disabled Cursed Adventure curses. Missing Tweaker: Events: <player>...".
12. (Item #458) Chaos Wastes: Keep: /ct_regression_test shows PASS issue458_start_shrine_config; /ct_verify_start_shrine prints the config.
   - Please report: attach both players' logs and note what appeared on each player's screen.
13. (Item #424) Host with cwv, equip the Tuskgor Javelin (cwv_es_javelin), throw at enemies and terrain with the non-cwv player in the lobby.
   - Please report: attach both players' logs and note what appeared on each player's screen.
14. (Item #279) cross-mod: host and joining player both equip or observe a CIM-crafted CWV item that previously rendered as merged/base models. Compare owner view, other players' characters, inventory preview, lobby/...
   - Please report: attach both players' logs and note what appeared on each player's screen.
15. (Item #426) Chaos Wastes: installed=FAIL or gate=FAIL: beacon/hook installation or parity transition failure.
   - Please report: attach both players' logs and note what appeared on each player's screen.
16. (Item #491) cross-mod: Form a two-player modded lobby with exactly one player running CWV and the other player not running CWV.
   - Please report: attach both players' logs and note what appeared on each player's screen.
17. (Item #149) Cosmetics: equip the LA Myrmidia Sun shield on a Bret sword & shield, then start a mission.
   - It works if: the shield keeps the Myrmidia Sun illusion at MISSION START (no host/joining player divergence reverting it to the default imperial shield).
18. (Item #154) Cosmetics: host equips a cross-character WEAPON cosmetic; a second player observes the other players' characters.
   - It works if: everything behaves normally for all players and nobody crashes.
19. (Item #200) Cosmetics: open the weapon illusion browser and hover offhand illusions.
   - It works if: everything behaves normally for all players and nobody crashes.
20. (Item #203) Cosmetics: in a mission, swap primary<->secondary weapon while an LA offhand shield illusion is equipped, including the mission-entry case, then have the final pick be a vanilla...
   - It works if: everything behaves normally for all players and nobody crashes.
21. (Item #204) Cosmetics: Open CWV Empire Axe & Shield customization and confirm the vanilla Empire shield choices are present alongside compatible Loremaster choices.
   - It works if: everything behaves normally for all players and nobody crashes.
22. (Item #233) Cosmetics: Host equips a Loremaster shield/offhand cosmetic and closes the game so the exact-item selection is persisted.
   - It works if: everything behaves normally for all players and nobody crashes.
23. (Item #241) General: joining player was not updated over Tailscale. As a friends-only self-authored upload, it needs a full Steam restart (tray -> Exit, reopen) to pull.
   - It works if: everything behaves normally for all players and nobody crashes.
24. (Item #247) General: Start a bot-filled Adventure with host plus one GT joining player. The joining player enables Bot Takeover; expect the joining player to enter observer, exactly one temporary bot to drive the...
   - It works if: everything behaves normally for all players and nobody crashes.
25. (Item #378) General: B joins A. Expected within ~60s: popup listing the missing mod(s) with Open Workshop + Leave (or the stalled-join notice if A broadcasts no manifest); Leave lands B on...
   - It works if: everything behaves normally for all players and nobody crashes.
26. (Item #476) Owner equips Imperial Sword and Shield before the observer joins.
   - It works if: everything behaves normally for all players and nobody crashes.
27. (Item #700) GUI: Enter an Adventure mission together.
   - Please report: the joining player popup, input, localized title, and accepted transition all work; the existing keep/unrelated vote behavior is unchanged.
28. (Item #702) Cosmetics: The owner equips a CWV dual weapon and applies a visibly different illusion to each hand.
   - Please report: attach both players' logs and note what appeared on each player's screen.
29. (Item #285) GUI: Mission with bots; let a bot (or a coop teammate) die - not just get downed.
   - It works if: everything behaves normally for all players and nobody crashes.
30. (Item #256) Chaos Wastes: Ranged career with a reserve+clip weapon (crossbow/handgun/blunderbuss - not an all-loaded bow). Fire to a partial clip, refill from an ammo crate so the clip exceeds...
   - It works if: everything behaves normally for all players and nobody crashes.
31. (Item #626) Events: Assemble the lobby first. On the host, enable both Dormant Event Missions.
   - Please report: attach both players' logs and note what appeared on each player's screen.
32. (Item #782) Equip Blightreaper, enter a mission, and kill enough enemies to spawn several Shyish spirits.
   - It works if: everything behaves normally for all players and nobody crashes.
33. (Item #504) cross-mod: Equip a ct_* custom illusion before mission start.
   - Please report: attach both players' logs and note what appeared on each player's screen.
34. (Item #613) Host equips Blightreaper in the keep. Verify its model uses {-90,-90,-90}, Z offset -0.3, and scale 0.9 in owner first person, owner third person, inventory character...
   - Please report: result is zero failures. Attach both newest logs if any surface differs.
35. (Item #416) Cosmetics: Both in the keep. Player A equips sword-and-shield, picks a VANILLA shield in the row-2 offhand picker (not an LA armoury option), Apply, exit.
   - Please report: player B sees A''s chosen shield (not base). Confirm the reverse direction.
36. (Item #632) Host and then joining player wield Blightreaper and kill a healthy enemy with a direct Blightreaper hit.
   - Please report: exactly one native Shyish spirit targets the exact wielder; contact converts green HP to THP without killing them, then the spirit cleans up.
37. (Item #61) Enemies: Confirm both players load Enemy Tweaker v0.7.49-dev or newer. Host a mission on a known difficulty with the host on Auto and the joining player on Auto; record one repeatable ho...
   - It works if: everything behaves normally for all players and nobody crashes.
38. (Item #178) Weapons: on Kruber, equip the Rapier (wh_fencing_sword).
   - It works if: it renders with Empire Sword & Shield 1H-sword anims and appears in the dev picker.
39. (Item #180) Weapons: on Kruber, equip Saltzpyre's Greathammer (wh_2h_hammer).
   - It works if: it is re-added to the dev picker and marked needs-anims (bad-anims status tracked), not silently missing.
40. (Item #246) Player A equips non-default illusions on both melee and ranged weapons.
   - It works if: everything behaves normally for all players and nobody crashes.
41. (Item #272) GUI: Enable the expanded Tweaker: GUI scoreboard and populate all eleven native scoreboard topics across human players and bots where possible.
   - It works if: everything behaves normally for all players and nobody crashes.
42. (Item #287) GUI: enable gut_use_non_modded_loadouts, enter the modded realm, and try to change a cosmetic.
   - It works if: cosmetics stay editable (you can change them) even with "Use non-modded loadouts" ON.
43. (Item #296) With current CWV, have host and joining player each throw, recover, swap away from, and re-equip the Tuskgor javelin.
   - It works if: everything behaves normally for all players and nobody crashes.
44. (Item #332) General: Host a modded mission with one joining player connected and General Tweaker's joining player-side ragdoll retention enabled.
   - It works if: everything behaves normally for all players and nobody crashes.
45. (Item #333) General: On the host, leave Twitch unlinked and enable Offline Twitch Mode. Load a supported mission with a second player.
   - It works if: result: complete the audited steps below and confirm every issue-specific condition.
46. (Item #369) Enemies: Set distinctive Enemy Tweaker health multipliers for the active difficulty.
   - It works if: everything behaves normally for all players and nobody crashes.
47. (Item #394) Owner equips the transformed Scythe and a second CWV weapon with non-default grip rotation/offset; observer inspects both in the Keep and mission.
   - It works if: everything behaves normally for all players and nobody crashes.
48. (Item #398) Owner swings and hits enemies with at least two CWV weapons whose clone templates have authored swing/impact sounds, including the Old Musket melee mode if available.
   - It works if: remote players hear the intended CWV swing and impact sounds once, without donor/base silence, duplicate audio, errors, or host-only behavior.
49. (Item #399) Kruber equips the Outrider Grenade Launcher before the observer joins; inspect it remotely in the Keep and mission.
   - It works if: everything behaves normally for all players and nobody crashes.
50. (Item #401) Owner equips the Imperial/Kruber Axe and Shield CWV variant and a non-CWV Axe and Shield control.
   - It works if: everything behaves normally for all players and nobody crashes.
51. (Item #482) Craft and equip two CWV variants with canonical non-default transforms; retain their exact instances.
   - It works if: everything behaves normally for all players and nobody crashes.
52. (Item #567) As joining player, equip and persist each original skin: Sword+Mace cwv_es_sword_and_mace_wpn_emp_sword_02_t1_wpn_emp_mace_03_t1, runed Dual Maces, and Axe+Shield. The observe...
   - It works if: everything behaves normally for all players and nobody crashes.
53. (Item #658) Cosmetics: With the Purpure/Azure set master enabled, confirm Grail Knight can equip its hat, outfit, and shield while Mercenary, Huntsman, and Foot Knight sharing toggles all de...
   - It works if: everything behaves normally for all players and nobody crashes.
54. (Item #697) Cosmetics: The wearer equips the Cosmetics-authored Purpure/Azure hat; the observer inspects the other players' characters and both retain logs through a mission transition.
   - It works if: everything behaves normally for all players and nobody crashes.
55. (Item #699) Career: Activate That's Bloody Teamwork's qualifying great-weapon condition. Its effect must use That's Bloody Teamwork's own art, distinct from Rock.
   - It works if: everything behaves normally for all players and nobody crashes.
56. (Item #728) Career: Use a joining player profile that still has at least one career locked by hero level. Join the host while Kruber is unreserved and open the in-Keep career picker on the joining player.
   - It works if: everything behaves normally for all players and nobody crashes.
57. (Item #112) Weapons: On Witch Hunter Captain, Bounty Hunter, or Zealot, run /wt_audit_saltzpyre_3p and retain the bounded port census.
   - Please report: attach both players' logs and note what appeared on each player's screen.
58. (Item #321) cross-mod: Open WT, CT, ET, and CRT in Mod Tweaker.
   - It works if: everything behaves normally for all players and nobody crashes.
59. (Item #730) Cosmetics: Equip Midnight Purpure and Azure, complete a mission, and inspect the local end-of-mission lineup.
   - It works if: everything behaves normally for all players and nobody crashes.
60. (Item #373) Cosmetics: Cosmetics Tweaker 0.9.106-dev is deployed and uploaded (Workshop manifest 5884392257591688555). Co-op verification: on each supported Bretonnian, Empire sword/mace, an...
   - It works if: everything behaves normally for all players and nobody crashes.
61. (Item #342) Chaos Wastes: Start a Chaos Wastes run and acquire either static_blade (lightning on parry) or boon_skulls_03 (drakegun explosion on parry).
   - It works if: everything behaves normally for all players and nobody crashes.
62. (Item #288) Chaos Wastes: On a ranged weapon with Anath Raema, disable Permanent Anath Raema Reload Buff, wield the weapon, and time several full reloads as the stock control. Do not collect am...
   - It works if: everything behaves normally for all players and nobody crashes.
63. (Item #774) cross-mod: Equip a style-capable weapon, enter an Adventure mission, and open Equipment through GUI Tweaker.
   - Please report: attach both players' logs and note what appeared on each player's screen.
64. (Item #753) General: Reproduce a Steam, PlayFab, or P2P connection failure with two players so the joining player P2P boundary is exercised.
   - Please report: attach both players' logs and note what appeared on each player's screen.
65. (Item #309) General: Host an Adventure mission with current gt_dev and one living joining player.
   - Please report: attach both players' logs and note what appeared on each player's screen.
66. (Item #645) Equip Saltzpyre's Greatsword on WHC, Bounty Hunter, or Zealot. Warrior Priest is intentionally excluded.
   - Please report: attach both players' logs and note what appeared on each player's screen.
67. (Item #417) host equips a unit-bearing CWV variant; a second player observes the other players' characters.
   - Please report: the transform is applied (the resolution + residency hardening closes the path where a unit-bearing variant silently skipped its transform).
68. (Item #641) Cosmetics: Open Tweaker: Cosmetics customization for a dual weapon, then for a weapon and shield.
   - Please report: primary, offhand-weapon, and shield names remain independent without changing saved cosmetic identity. This can be verified solo.
69. (Item #629) Cosmetics: Equip Couronne de la Lune and Midnight Purpure and Azure on Grail Knight.
   - Please report: attach both players' logs and note what appeared on each player's screen.
70. (Item #598) With CIM on both players, equip a crafted modded item and inspect its hold-TAB equipment frame from both host/joining player directions.
   - Please report: attach both players' logs and note what appeared on each player's screen.
71. (Item #107) Chaos Wastes: with a banned grudge mark configured, reach a Belakor mission where a Shadow Lieutenant champion spawns.
   - Please report: attach both players' logs and note what appeared on each player's screen.
72. (Item #380) General: Turn on Disable downed screen effects.
   - Please report: attach both players' logs and note what appeared on each player's screen.
73. (Item #316) Weapons: With two players, equip Kruber's Empire Longbow on Mercenary. Hold aim through the zoom and fire.
   - It works if: everything behaves normally for all players and nobody crashes.
74. (Item #787) cross-mod: Open CIM's Athanor weapon selector as Kruber. The base/Blacksmith Dual Axes row must show the authored paired Dual Axes thumbnail, not the single-axe fallback.
   - It works if: everything behaves normally for all players and nobody crashes.
75. (Item #277) Run /forge_delete_all. The preview should list only items owned by CIM's forged-weapon system.
   - It works if: everything behaves normally for all players and nobody crashes.
76. (Item #367) Career: As Ranger Veteran, disable Talent Reworks > Ranger Veteran > Faster Ale Drinking Animation and drink an ale. Record the stock visible animation/control lock, approxima...
   - It works if: everything behaves normally for all players and nobody crashes.
77. (Item #358) Chaos Wastes: Load current CT build, enable the Manann's Tempest cooldown display, equip or select a source that can trigger Manann's Tempest, and proc it repeatedly.
   - It works if: everything behaves normally for all players and nobody crashes.
78. (Item #440) Career: Put Bardin and a second hero under identical ping and difficulty conditions; include a bot control if possible.
   - Please report: attach both players' logs and note what appeared on each player's screen.
79. (Item #488) General: Host with Tweaker: General DEV v0.2.238-dev and bring a shield-equipped bot; the second player joins as observer/control.
   - Please report: diagnostic output
80. (Item #323) Chaos Wastes: Complete one Chaos Wastes pilgrimage with host and joining player logs retained.
   - Please report: diagnostic result: collect the bounded evidence below; this does not claim the issue is fixed.
81. (Item #289) Chaos Wastes: Host and joining player enter the same Chaos Wastes mission with the same CT build.
   - Please report: diagnostic result: collect the bounded evidence below; this does not claim the issue is fixed.

## Games with 3 or more players

1. (Item #604) Weapons: Equip Imperial Crowbill Model 05 and compare the inventory character preview, owner third person, remote joining player's view, lobby/team presentation, score screen, and Atha...
   - Please report: every 3P/presentation surface uses the same tuned pose; first person is unchanged.
2. (Item #290) Weapons: On any Kruber career, equip Saltzpyre's Billhook and close the inventory.
   - It works if: everything behaves normally for all players and nobody crashes.
3. (Item #747) cross-mod: Exercise two transformed weapons and one unmodified control across owner 1P/3P, inventory preview, bot, and other players' characters.
   - Please report: attach both players' logs and note what appeared on each player's screen.
4. (Item #738) Cosmetics: a marker in the game log skips show local_player_id=2/3/4 controlled=false only; host cosmetics visible on joining players' characters at joining a game already in progress.
   - Please report: attach both players' logs and note what appeared on each player's screen.
5. (Item #161) Weapons: on Saltzpyre, equip Kerillian Spear and Kruber Halberd (polearms).
   - It works if: everything behaves normally for all players and nobody crashes.
6. (Item #182) Weapons: on Kruber, equip the Cog Hammer (dr_2h_cog_hammer).
   - It works if: it appears in the dev picker marked needs-anims and its 3P anims are re-tuned (no idle fall-through). Cross-check the picker entry exists again.
7. (Item #196) Weapons: enable the dev Anim Picker, on Saltzpyre pick the Billhook (SET F) charge/heavy attacks, then perform them.
   - It works if: everything behaves normally for all players and nobody crashes.
8. (Item #266) Cosmetics: Run current Tweaker: Cosmetics with Loremaster's Armoury on host and joining player; execute /cos_regression_test first.
   - It works if: everything behaves normally for all players and nobody crashes.
9. (Item #317) Enable the CWV development animation picker and select at least one non-default mapping.
   - It works if: everything behaves normally for all players and nobody crashes.
10. (Item #692) Equip an exact Bretonnian Longsword (es_bastard_sword) instance and select its native Bretonnian Combat Style as the no-transform control. Inspect owner first person,...
   - It works if: everything behaves normally for all players and nobody crashes.
11. (Item #579) Give one Dual Axes instance different primary and offhand illusions through Tweaker: Cosmetics.
   - Please report: every surface preserves the exact saved right/offhand pair. No surface may reconstruct the base Dual Axes models or swap the hand order.
12. (Item #657) Test Empire Sword and Shield on Grail Knight and Bretonnian Sword and Shield on Mercenary, Huntsman, and Foot Knight with host and joining player on matching builds.
   - Please report: diagnostic result: prove the receiver-specific combat-style boundary before any Sword-and-Shield family is reintroduced; this does not claim a fix.
13. (Item #602) Weapons: With current CWV and CIM, census the Dawi Mace, Dawi Mace and Shield, and Dawi Dual Maces catalog identities, model resources, and cosmetic acquisition paths.
   - Please report: attach both players' logs and note what appeared on each player's screen.
14. (Item #633) In the keep and again in an Adventure mission, run /woc_audio_contract, then the wielder runs /woc_audio_probe once.
   - Please report: attach both players' logs and note what appeared on each player's screen.
15. (Item #656) Cosmetics: Host and one joining player use the exact same Cosmetics build. Enable Reikland Griffin and equip the red Foot Knight outfit.
   - Please report: attach both players' logs and note what appeared on each player's screen.
16. (Item #760) Run /cwv_regression_test; cwv_issue760_outrider_saltzpyre_repeater_stance must pass.
   - Please report: attach both players' logs and note what appeared on each player's screen.

When you are done, tell us which item numbers passed and which did not. Thank you.

