# Co-op Playtest Checklist

> Auto-generated on 2026-07-19 17:12 UTC. Plain-language co-op-only checklist for a second tester.

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

1. (Item #139) General: Blanket leash veto at the BTConditions.should_teleport hook, applied to the FINAL decision, so it vetoes both vanilla's 40 m and gt's tighter leash. With aid-priority...
   - Please report: attach both players' logs and note what appeared on each player's screen.
2. (Item #430) Events: Both in the keep lobby. Expected within ~4s on the host: chat notice "[Events] player-parity: disabled Cursed Adventure curses.
   - Please report: within ~4s on the host: chat notice "[Events] player-parity: disabled Cursed Adventure curses. Missing Tweaker: Events: <player>...".
3. (Item #136) Chaos Wastes: Both players fully restart Steam, confirm 0.7.243-dev in both load logs.
   - It works if: everything behaves normally for all players and nobody crashes.
4. (Item #278) cross-mod: host runs cim/cwv, a joining player joins WITHOUT the mod. Host equips a crafted or skinned CWV/cim item (loadout sync).
   - It works if: everything behaves normally for all players and nobody crashes.
5. (Item #458) Chaos Wastes: Keep: /ct_regression_test shows PASS issue458_start_shrine_config; /ct_verify_start_shrine prints the config.
   - Please report: attach both players' logs and note what appeared on each player's screen.
6. (Item #424) Host with cwv, equip the Tuskgor Javelin (cwv_es_javelin), throw at enemies and terrain with the non-cwv player in the lobby.
   - Please report: attach both players' logs and note what appeared on each player's screen.
7. (Item #205) Chaos Wastes: corrected: the crash class is a RELIABLE SEND-QUEUE overflow, and that queue only grows when a remote player is connected - a solo host has nobody to send to, so the pri...
   - It works if: everything behaves normally for all players and nobody crashes.
8. (Item #421) cross-mod: On the Cosmetics player, equip ct_es_mace_gk_shield_01 or any ct_es_heavy_spear_deus_* illusion and run /cos_421_diag.
   - It works if: everything behaves normally for all players and nobody crashes.
9. (Item #749) cross-mod: With both players running Cosmetics, open the Hero/Equipment cosmetic preview and browse Loremaster shield variants repeatedly, including glow/weave/Shyish variants wh...
   - It works if: everything behaves normally for all players and nobody crashes.
10. (Item #776) Career: Reproduce Impetuous Knight kills from both host and joining player; repeat kills must refresh one 20-second attack-speed/power effect without stacking.
   - It works if: everything behaves normally for all players and nobody crashes.
11. (Item #807) As Grail Knight, equip the CWV Kruber Rapier in the secondary/ranged slot and close Hero/Equipment view.
   - It works if: everything behaves normally for all players and nobody crashes.
12. (Item #423) a non-cwv player HOSTS; a cwv player joins and lands a hit with a CWV variant carrying a cloned damage_profile.
   - Please report: no crash to desktop on the non-cwv host (player-parity gate suppresses the cloned damage_profile on the wire when a player lacks cwv).
13. (Item #279) cross-mod: host and joining player both equip or observe a CIM-crafted CWV item that previously rendered as merged/base models. Compare owner view, other players' characters, inventory preview, lobby/...
   - Please report: attach both players' logs and note what appeared on each player's screen.
14. (Item #660) GUI: Host equips one transformed CWV weapon with a custom illusion; also keep one unmodified vanilla weapon as a control.
   - Please report: attach both players' logs and note what appeared on each player's screen.
15. (Item #426) Chaos Wastes: installed=FAIL or gate=FAIL: beacon/hook installation or parity transition failure.
   - Please report: attach both players' logs and note what appeared on each player's screen.
16. (Item #371) GUI: host runs cwv; a player joins WITHOUT cwv. Host equips the Tuskgor Javelin (cwv_es_javelin) bomb pool.
   - Please report: attach both players' logs and note what appeared on each player's screen.
17. (Item #491) cross-mod: Form a two-player modded lobby with exactly one player running CWV and the other player not running CWV.
   - Please report: attach both players' logs and note what appeared on each player's screen.
18. (Item #474) Cosmetics: Host equips Old Musket in the ranged slot; the joining player must see the custom Musket mesh, correct full transform, and rifle report.
   - Please report: attach both players' logs and note what appeared on each player's screen.
19. (Item #413) Events: Tick Shadow (Winds of Magic) in event_tweaker; start any Adventure mission.
   - It works if: everything behaves normally for all players and nobody crashes.
20. (Item #786) Have both players style-switch supported weapons in keep and mission while capturing a marker in the game log rows.
   - Please report: attach both players' logs and note what appeared on each player's screen.
21. (Item #504) cross-mod: Equip a ct_* custom illusion before mission start.
   - Please report: attach both players' logs and note what appeared on each player's screen.
22. (Item #613) Host equips Blightreaper in the keep. Verify its model uses {-90,-90,-90}, Z offset -0.3, and scale 0.9 in owner first person, owner third person, inventory character...
   - Please report: result is zero failures. Attach both newest logs if any surface differs.
23. (Item #735) Weapons: On Saltzpyre, equip each affected paired shield weapon (Empire Mace & Shield, Empire Sword & Shield, Bretonnian Sword & Shield, and Dwarf Axe & Shield where available).
   - It works if: everything behaves normally for all players and nobody crashes.
24. (Item #835) cross-mod: Equip a CWV weapon with a committed nonzero position/scale override and the Blightreaper.
   - It works if: everything behaves normally for all players and nobody crashes.
25. (Item #782) Equip Blightreaper, enter a mission, and kill enough enemies to spawn several Shyish spirits.
   - It works if: everything behaves normally for all players and nobody crashes.
26. (Item #823) Open the inventory/crafting surfaces that show CIM's modded-rarity background and salvage controls, then close and reopen them once.
   - It works if: everything behaves normally for all players and nobody crashes.
27. (Item #741) cross-mod: Both players enable CWV, but deliberately use different skin-appending mod sets: the proven reproduction is host with stable WT disabled and joining player with WT Dev enabled.
   - It works if: everything behaves normally for all players and nobody crashes.
28. (Item #384) General: One human pushes ~40m ahead; the other goes down near the bots (stay knocked, then bleed out to awaiting-rescue).
   - Please report: attach both players' logs and note what appeared on each player's screen.
29. (Item #256) Chaos Wastes: Ranged career with a reserve+clip weapon (crossbow/handgun/blunderbuss - not an all-loaded bow). Fire to a partial clip, refill from an ammo crate so the clip exceeds...
   - It works if: everything behaves normally for all players and nobody crashes.
30. (Item #340) GUI: Run /gut_all_languages_status with the standalone Support All Languages mod disabled.
   - Please report: newest-log banner: the version line (v0.2.298-dev.) shown when the mod loads
31. (Item #285) GUI: Mission with bots; let a bot (or a coop teammate) die - not just get downed.
   - It works if: everything behaves normally for all players and nobody crashes.
32. (Item #762) Equip the Outrider on Kruber, inspect it in the inventory character preview, and enter a mission.
   - It works if: everything behaves normally for all players and nobody crashes.
33. (Item #461) Chaos Wastes: Empty list under the header: the rows were anchored on a scenegraph node with no size, so they computed to a position below the screen and were silently swallowed. Re-...
   - Please report: attach both players' logs and note what appeared on each player's screen.
34. (Item #702) Cosmetics: owner applies distinct illusions to each hand of a dual weapon; second player observes in keep, mission, after swap, after transition, and after rejoin.
   - Please report: attach both players' logs and note what appeared on each player's screen.
35. (Item #700) General: Enter an Adventure mission together.
   - Please report: the joining player popup, input, localized title, and accepted transition all work; the existing keep/unrelated vote behavior is unchanged.
36. (Item #476) One player equips Imperial Longsword & Shield, applies a non-default illusion, enters the keep or a mission; the other looks at them.
   - Please report: attach both players' logs and note what appeared on each player's screen.
37. (Item #154) Cosmetics: host equips a cross-character WEAPON cosmetic; a second player observes the other players' characters.
   - Please report: attach both players' logs and note what appeared on each player's screen.
38. (Item #416) Cosmetics: Both in the keep. Player A equips sword-and-shield, picks a VANILLA shield in the row-2 offhand picker (not an LA armoury option), Apply, exit.
   - Please report: player B sees A''s chosen shield (not base). Confirm the reverse direction.
39. (Item #632) Host and then joining player wield Blightreaper and kill a healthy enemy with a direct Blightreaper hit.
   - Please report: exactly one native Shyish spirit targets the exact wielder; contact converts green HP to THP without killing them, then the spirit cleans up.
40. (Item #299) Chaos Wastes: with respawn_on_chest_complete ON in a CW run, player A dies or reaches the awaiting-rescue hang far from the group; player B completes a Chest of Trials.
   - Please report: attach both players' logs and note what appeared on each player's screen.
41. (Item #273) Chaos Wastes: after a Chaos Wastes run with a wt cross-character weapon (or a ct weapon-upgrade), return to the keep and check Kruber's active weapon.
   - It works if: everything behaves normally for all players and nobody crashes.
42. (Item #247) General: Start a bot-filled Adventure with host plus one GT joining player. The joining player enables Bot Takeover; expect the joining player to enter observer, exactly one temporary bot to drive the...
   - It works if: everything behaves normally for all players and nobody crashes.
43. (Item #233) Cosmetics: Host equips a Loremaster shield/offhand cosmetic and closes the game so the exact-item selection is persisted.
   - It works if: everything behaves normally for all players and nobody crashes.
44. (Item #204) Cosmetics: Open CWV Empire Axe & Shield customization and confirm the vanilla Empire shield choices are present alongside compatible Loremaster choices.
   - It works if: everything behaves normally for all players and nobody crashes.
45. (Item #203) Cosmetics: in a mission, swap primary<->secondary weapon while an LA offhand shield illusion is equipped, including the mission-entry case, then have the final pick be a vanilla...
   - It works if: everything behaves normally for all players and nobody crashes.
46. (Item #149) Cosmetics: equip the LA Myrmidia Sun shield on a Bret sword & shield, then start a mission.
   - It works if: the shield keeps the Myrmidia Sun illusion at MISSION START (no host/joining player divergence reverting it to the default imperial shield).
47. (Item #626) Events: Assemble the lobby first. On the host, enable both Dormant Event Missions.
   - Please report: attach both players' logs and note what appeared on each player's screen.
48. (Item #200) open the weapon illusion browser and hover offhand illusions.
   - It works if: everything behaves normally for all players and nobody crashes.
49. (Item #241) General: joining player was not updated over Tailscale. As a friends-only self-authored upload, it needs a full Steam restart (tray -> Exit, reopen) to pull.
   - It works if: everything behaves normally for all players and nobody crashes.
50. (Item #378) General: B joins A. Expected within ~60s: popup listing the missing mod(s) with Open Workshop + Leave (or the stalled-join notice if A broadcasts no manifest); Leave lands B on...
   - It works if: everything behaves normally for all players and nobody crashes.
51. (Item #369) Enemies: Set distinctive Enemy Tweaker health multipliers for the active difficulty.
   - It works if: everything behaves normally for all players and nobody crashes.
52. (Item #351) Chaos Wastes: Launch an injected Adventure map through Chaos Wastes with host and joining player on current builds.
   - It works if: everything behaves normally for all players and nobody crashes.
53. (Item #296) With current CWV, have host and joining player each throw, recover, swap away from, and re-equip the Tuskgor javelin.
   - It works if: everything behaves normally for all players and nobody crashes.
54. (Item #272) GUI: Enable the expanded Tweaker: GUI scoreboard and populate all eleven native scoreboard topics across human players and bots where possible.
   - It works if: everything behaves normally for all players and nobody crashes.
55. (Item #460) Chaos Wastes: Host a fresh Legend Chaos Wastes run with progressive difficulty enabled and the coin multiplier changing from 2.00x to 1.50x. Play through maps 1, 2, 3, 4, and 5 and co...
   - It works if: everything behaves normally for all players and nobody crashes.
56. (Item #828) Chaos Wastes: On a profile whose persisted Chaos Wastes table predates ct_buy_starting_boons, open the relevant tab and confirm the reconciled value is false; start a run and confir...
   - It works if: everything behaves normally for all players and nobody crashes.
57. (Item #465) Chaos Wastes: Start a Chaos Wastes run with the two humans holding deliberately different Pilgrim's Coins, boons, and melee/ranged weapon tiers.
   - It works if: everything behaves normally for all players and nobody crashes.
58. (Item #730) Cosmetics: Equip Midnight Purpure and Azure, complete a mission, and inspect the local end-of-mission lineup.
   - It works if: everything behaves normally for all players and nobody crashes.
59. (Item #704) Deploy the staged Cosmetics/CWV/CIM build through the normal controlled deployment process.
   - Please report: attach both players' logs and note what appeared on each player's screen.
60. (Item #658) Cosmetics: With matching versions, confirm all three share toggles default off and Grail Knight is unchanged.
   - It works if: everything behaves normally for all players and nobody crashes.
61. (Item #61) Enemies: Confirm both players load Enemy Tweaker v0.7.49-dev or newer. Host a mission on a known difficulty with the host on Auto and the joining player on Auto; record one repeatable ho...
   - It works if: everything behaves normally for all players and nobody crashes.
62. (Item #249) Chaos Wastes: with "more ammo per boon" active, a joining player checks the HUD ammo count vs actual.
   - It works if: everything behaves normally for all players and nobody crashes.
63. (Item #753) General: Reproduce a Steam, PlayFab, or P2P connection failure with two players so the joining player P2P boundary is exercised.
   - Please report: attach both players' logs and note what appeared on each player's screen.
64. (Item #699) Career: As Foot Knight, activate the Rock of Reikland shield condition and the That's Bloody Teamwork great-weapon condition; verify each HUD buff uses its own resident talent...
   - It works if: everything behaves normally for all players and nobody crashes.
65. (Item #719) cross-mod: Kruber equips the Imperial Crowbill before the second player joins; inspect it remotely in the Keep.
   - Please report: attach both players' logs and note what appeared on each player's screen.
66. (Item #692) Kruber equips a Bretonnian Longsword and cycles through its Greatsword combat styles in the Keep while the second player watches.
   - It works if: everything behaves normally for all players and nobody crashes.
67. (Item #728) Career: Join the same keep and have the second player reserve any Kruber career.
   - It works if: everything behaves normally for all players and nobody crashes.
68. (Item #322) Chaos Wastes: in a CW mission with linked pickups (grimoire / tome), a joining player picks up / drops the item.
   - It works if: everything behaves normally for all players and nobody crashes.
69. (Item #288) Chaos Wastes: Enable tweak_anath_raema_permanent.
   - It works if: everything behaves normally for all players and nobody crashes.
70. (Item #246) Player A equips non-default illusions on both melee and ranged weapons.
   - It works if: everything behaves normally for all players and nobody crashes.
71. (Item #717) GUI: In the keep, open Mod Tweaker and select Equipment.
   - It works if: everything behaves normally for all players and nobody crashes.
72. (Item #697) Cosmetics: Nil wearer/hat guard, Trigger: other players' characters LA paint step runs before the hat unit or wearer unit exists. Change: fail closed and defer once to the next realized-other players' charact...
   - It works if: everything behaves normally for all players and nobody crashes.
73. (Item #567) As joining player, equip and persist each original skin: Sword+Mace cwv_es_sword_and_mace_wpn_emp_sword_02_t1_wpn_emp_mace_03_t1, runed Dual Maces, and Axe+Shield. The observe...
   - It works if: everything behaves normally for all players and nobody crashes.
74. (Item #482) Equip the existing affected Imperial Longsword/Black Guard Blade by UUID. Do not recraft it.
   - Please report: attach both players' logs and note what appeared on each player's screen.
75. (Item #309) General: Host an Adventure mission with current gt_dev and one living joining player.
   - Please report: attach both players' logs and note what appeared on each player's screen.
76. (Item #645) Equip Saltzpyre's Greatsword on WHC, Bounty Hunter, or Zealot. Warrior Priest is intentionally excluded.
   - Please report: attach both players' logs and note what appeared on each player's screen.
77. (Item #373) Cosmetics: Cosmetics Tweaker 0.9.106-dev is deployed and uploaded (Workshop manifest 5884392257591688555). Co-op verification: on each supported Bretonnian, Empire sword/mace, an...
   - Please report: attach both players' logs and note what appeared on each player's screen.
78. (Item #417) host equips a unit-bearing CWV variant; a second player observes the other players' characters.
   - Please report: the transform is applied (the resolution + residency hardening closes the path where a unit-bearing variant silently skipped its transform).
79. (Item #641) Cosmetics: Open Tweaker: Cosmetics customization for a dual weapon, then for a weapon and shield.
   - Please report: primary, offhand-weapon, and shield names remain independent without changing saved cosmetic identity. This can be verified solo.
80. (Item #629) Cosmetics: Equip Couronne de la Lune and Midnight Purpure and Azure on Grail Knight.
   - Please report: attach both players' logs and note what appeared on each player's screen.
81. (Item #598) With CIM on both players, equip a crafted modded item and inspect its hold-TAB equipment frame from both host/joining player directions.
   - Please report: attach both players' logs and note what appeared on each player's screen.
82. (Item #472) Career: As Handmaiden, enable the Focused Spirit filter and take each exempt damage family; verify the talent remains active.
   - It works if: everything behaves normally for all players and nobody crashes.
83. (Item #401) host equips the Imperial Axe + Shield CWV variant; a second player observes the host's other players' characters.
   - Please report: attach both players' logs and note what appeared on each player's screen.
84. (Item #399) crafted Outrider launcher shows no torpedo on the remote view; joining player log [cwv other players' characters-ammo-strip] via=descriptor.
   - Please report: attach both players' logs and note what appeared on each player's screen.
85. (Item #398) Related hardening shipped 2026-07-18: cwv v0.1.447-dev consolidated other players' characters apply + retained-state postcondition logging (a marker in the game log lines), and cosmetics v0.9.149-d...
   - Please report: attach both players' logs and note what appeared on each player's screen.
86. (Item #394) host equips a CWV variant that uses a grip offset; a second player observes the host's other players' characters.
   - Please report: the grip offset is applied on the other players' characters (joining player) view, matching the owner.
87. (Item #388) Weapons: Load current WT build, equip Deepwood Staff on a non-Sister career, build low/medium/high overcharge, then swap away and back.
   - It works if: everything behaves normally for all players and nobody crashes.
88. (Item #321) cross-mod: Open WT, CT, ET, and CRT in Mod Tweaker.
   - It works if: everything behaves normally for all players and nobody crashes.
89. (Item #287) GUI: enable gut_use_non_modded_loadouts, enter the modded realm, and try to change a cosmetic.
   - It works if: cosmetics stay editable (you can change them) even with "Use non-modded loadouts" ON.
90. (Item #112) Weapons: On Witch Hunter Captain, Bounty Hunter, or Zealot, equip Kruber's Empire Handgun.
   - It works if: everything behaves normally for all players and nobody crashes.
91. (Item #332) General: as a joining player (non-host), enable "Disable mutator death explosions" (and Max Ragdolls).
   - It works if: the setting takes effect on the joining player's own machine (death explosions suppressed joining player-side), not host-only.
92. (Item #333) General: On the host, leave Twitch unlinked and enable Offline Twitch Mode. Load a supported mission with a second player.
   - It works if: result: complete the audited steps below and confirm every issue-specific condition.
93. (Item #107) Chaos Wastes: with a banned grudge mark configured, reach a Belakor mission where a Shadow Lieutenant champion spawns.
   - Please report: attach both players' logs and note what appeared on each player's screen.
94. (Item #380) General: Turn on Disable downed screen effects.
   - Please report: attach both players' logs and note what appeared on each player's screen.
95. (Item #342) Chaos Wastes: Start a Chaos Wastes run and acquire either static_blade (lightning on parry) or boon_skulls_03 (drakegun explosion on parry).
   - It works if: everything behaves normally for all players and nobody crashes.
96. (Item #263) Open the illusion/cosmetic customization view for a normal vanilla-rarity item that can be upgraded. Its existing upgrade copy and behavior must remain unchanged.
   - It works if: everything behaves normally for all players and nobody crashes.
97. (Item #317) Enable the Animation Picker and equip Dual Axes on Saltzpyre or Kruber.
   - It works if: everything behaves normally for all players and nobody crashes.
98. (Item #440) Career: Put Bardin and a second hero under identical ping and difficulty conditions; include a bot control if possible.
   - Please report: attach both players' logs and note what appeared on each player's screen.
99. (Item #63) Chaos Wastes: Confirm a fresh/default value of 0 starts a native Trial Chest for free.
   - It works if: everything behaves normally for all players and nobody crashes.
100. (Item #787) cross-mod: Open CIM's Athanor weapon selector as Kruber. The base/Blacksmith Dual Axes row must show the authored paired Dual Axes thumbnail, not the single-axe fallback.
   - It works if: everything behaves normally for all players and nobody crashes.
101. (Item #277) Run /forge_delete_all. The preview should list only items owned by CIM's forged-weapon system.
   - It works if: everything behaves normally for all players and nobody crashes.
102. (Item #488) General: Host with Tweaker: General DEV v0.2.238-dev and bring a shield-equipped bot; the second player joins as observer/control.
   - Please report: diagnostic output
103. (Item #323) Chaos Wastes: Complete one Chaos Wastes pilgrimage with host and joining player logs retained.
   - Please report: diagnostic result: collect the bounded evidence below; this does not claim the issue is fixed.
104. (Item #289) Chaos Wastes: Host and joining player enter the same Chaos Wastes mission with the same CT build.
   - Please report: diagnostic result: collect the bounded evidence below; this does not claim the issue is fixed.
105. (Item #358) Chaos Wastes: Load current CT build, enable the Manann's Tempest cooldown display, equip or select a source that can trigger Manann's Tempest, and proc it repeatedly.
   - It works if: everything behaves normally for all players and nobody crashes.
106. (Item #357) Chaos Wastes: Give host and joining player different supported bomb-bubble boons and set a visible nonzero cooldown.
   - It works if: result: complete the audited steps below and confirm every issue-specific condition.
107. (Item #361) Chaos Wastes: Host enables Permanent Purifying Torch Carrier, sets Safe Area Radius to 12 m, and Miasma Stack Interval to 0.5 s. Enter a Rotten Miasma mission with one joining player.
   - It works if: everything behaves normally for all players and nobody crashes.

## Games with 3 or more players

1. (Item #604) Weapons: Equip Imperial Crowbill Model 05 and compare the inventory character preview, owner third person, remote joining player's view, lobby/team presentation, score screen, and Atha...
   - Please report: every 3P/presentation surface uses the same tuned pose; first person is unchanged.
2. (Item #747) cross-mod: Exercise two transformed weapons and one unmodified control across owner 1P/3P, inventory preview, bot, and other players' characters.
   - Please report: attach both players' logs and note what appeared on each player's screen.
3. (Item #738) Cosmetics: a marker in the game log skips show local_player_id=2/3/4 controlled=false only; host cosmetics visible on joining players' characters at joining a game already in progress.
   - Please report: attach both players' logs and note what appeared on each player's screen.
4. (Item #290) Weapons: On any Kruber career, equip Saltzpyre's Billhook and close the inventory.
   - It works if: everything behaves normally for all players and nobody crashes.
5. (Item #602) Weapons: With current CWV and CIM, census the Dawi Mace, Dawi Mace and Shield, and Dawi Dual Maces catalog identities, model resources, and cosmetic acquisition paths.
   - Please report: attach both players' logs and note what appeared on each player's screen.
6. (Item #266) Cosmetics: Run current Tweaker: Cosmetics with Loremaster's Armoury on host and joining player; execute /cos_regression_test first.
   - It works if: everything behaves normally for all players and nobody crashes.
7. (Item #798) Test native Sienna Crowbill, Imperial Crowbill, and Dawi Crowbill. For each, use Weapon Special to alternate pick and hammer modes while the second player observes.
   - It works if: everything behaves normally for all players and nobody crashes.
8. (Item #792) On each Kruber career, equip Old Musket and open the inventory-screen character preview. Wait for the mannequin to settle.
   - It works if: to_handgun event. This rules out the closed #606 failure class (a missing receiver-career entry) for the reported run.
9. (Item #748) Weapons: Exercise cross-character weapons that previously fell through the third-person vocabulary: light/heavy windups and releases, block/push, weapon special, reload, swap,...
   - It works if: everything behaves normally for all players and nobody crashes.
10. (Item #579) Give one Dual Axes instance different primary and offhand illusions through Tweaker: Cosmetics.
   - Please report: every surface preserves the exact saved right/offhand pair. No surface may reconstruct the base Dual Axes models or swap the hand order.
11. (Item #657) Test Empire Sword and Shield on Grail Knight and Bretonnian Sword and Shield on Mercenary, Huntsman, and Foot Knight with host and joining player on matching builds.
   - Please report: diagnostic result: prove the receiver-specific combat-style boundary before any Sword-and-Shield family is reintroduced; this does not claim a fix.
12. (Item #633) In the keep and again in an Adventure mission, run /woc_audio_contract, then the wielder runs /woc_audio_probe once.
   - Please report: attach both players' logs and note what appeared on each player's screen.
13. (Item #656) Cosmetics: Host and one joining player use the exact same Cosmetics build. Enable Reikland Griffin and equip the red Foot Knight outfit.
   - Please report: attach both players' logs and note what appeared on each player's screen.
14. (Item #760) Run /cwv_regression_test; cwv_issue760_outrider_saltzpyre_repeater_stance must pass.
   - Please report: attach both players' logs and note what appeared on each player's screen.
15. (Item #316) Weapons: Both players use matching current WT builds and confirm their load banners.
   - It works if: everything behaves normally for all players and nobody crashes.

When you are done, tell us which item numbers passed and which did not. Thank you.

