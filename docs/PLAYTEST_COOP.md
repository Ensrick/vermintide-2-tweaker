# Co-op Playtest Checklist

> Auto-generated on 2026-07-18 15:39 UTC. Plain-language co-op-only checklist for a second tester.

Thanks for helping test. Each item below is one bug we think we fixed and need to see working in a real co-op game. You do not need any of our tools or notes, just the game and this list.

## Before you start
- Make sure everyone in the group has updated to the newest version of each mod. Re-subscribe if you are not sure.
- Turn on the in-game console log if you can, so we can read it afterward. If you cannot, just watch for anything that looks wrong on screen.
- Play in ONE group/lobby the whole time so you can tick off as many items as possible in a single session.
- "It works if" describes what a PASS looks like. If you see a crash or the wrong thing, note the item number and what happened.

## Suggested order
1. Everyone joins one lobby in the keep and confirms the game loaded the newest mod versions.
2. Do the checks that happen in the keep or when someone joins a game in progress.
3. Start a normal mission together and do the in-mission checks.
4. Play through to the end-of-round score screen and check those items.
5. If some items need a third player, add one and redo just those.

## Games with 2 players

1. (Item #61) Enemies: Confirm both players load Enemy Tweaker v0.7.49-dev or newer. Host a mission on a known difficulty with the host on Auto and the other players on Auto; record one repeatable ho...
   - It works if: everything behaves normally for all players and nobody crashes.
2. (Item #63) Chaos Wastes: Confirm both players load CT v0.7.286-dev or newer. Host a Chaos Wastes mission, enable the Chest of Trials cost, and set it to 100 coins.
   - It works if: everything behaves normally for all players and nobody crashes.
3. (Item #107) Chaos Wastes: with a banned grudge mark configured, reach a Belakor mission where a Shadow Lieutenant champion spawns.
   - It works if: everything behaves normally for all players and nobody crashes.
4. (Item #112) Weapons: On Witch Hunter Captain, Bounty Hunter, or Zealot, equip Kruber's Empire Handgun.
   - It works if: everything behaves normally for all players and nobody crashes.
5. (Item #136) Chaos Wastes: Both players fully restart Steam, confirm 0.7.243-dev in both load logs.
   - It works if: everything behaves normally for all players and nobody crashes.
6. (Item #149) Cosmetics: equip the LA Myrmidia Sun shield on a Bret sword & shield, then start a mission.
   - It works if: the shield keeps the Myrmidia Sun illusion at MISSION START (no host/the other players divergence reverting it to the default imperial shield).
7. (Item #154) Cosmetics: host equips a cross-character WEAPON cosmetic; a second player observes the other players' characters.
   - It works if: everything behaves normally for all players and nobody crashes.
8. (Item #200) open the weapon illusion browser and hover offhand illusions.
   - It works if: everything behaves normally for all players and nobody crashes.
9. (Item #203) Cosmetics: in a mission, swap primary<->secondary weapon while an LA offhand shield illusion is equipped, including the mission-entry case, then have the final pick be a vanilla...
   - It works if: everything behaves normally for all players and nobody crashes.
10. (Item #204) Cosmetics: Open CWV Empire Axe & Shield customization and confirm the vanilla Empire shield choices are present alongside compatible Loremaster choices.
   - It works if: everything behaves normally for all players and nobody crashes.
11. (Item #205) Chaos Wastes: corrected: the crash class is a RELIABLE SEND-QUEUE overflow, and that queue only grows when a remote players is connected - a solo host has nobody to send to, so the pri...
   - It works if: everything behaves normally for all players and nobody crashes.
12. (Item #233) Cosmetics: Host equips a Loremaster shield/offhand cosmetic and closes the game so the exact-item selection is persisted.
   - It works if: everything behaves normally for all players and nobody crashes.
13. (Item #241) General: the other players was not updated over Tailscale. As a friends-only self-authored upload, it needs a full Steam restart (tray -> Exit, reopen) to pull.
   - It works if: everything behaves normally for all players and nobody crashes.
14. (Item #246) Player A equips non-default illusions on both melee and ranged weapons.
   - It works if: everything behaves normally for all players and nobody crashes.
15. (Item #247) General: Start a bot-filled Adventure with host plus one GT the other players. the other players enables Bot Takeover; expect the other players to enter observer, exactly one temporary bot to drive the...
   - It works if: everything behaves normally for all players and nobody crashes.
16. (Item #249) Chaos Wastes: with "more ammo per boon" active, a the other players checks the HUD ammo count vs actual.
   - It works if: everything behaves normally for all players and nobody crashes.
17. (Item #256) Chaos Wastes: Ranged career with a reserve+clip weapon (crossbow/handgun/blunderbuss - not an all-loaded bow). Fire to a partial clip, refill from an ammo crate so the clip exceeds...
   - It works if: everything behaves normally for all players and nobody crashes.
18. (Item #263) Open the illusion/cosmetic customization view for a normal vanilla-rarity item that can be upgraded. Its existing upgrade copy and behavior must remain unchanged.
   - It works if: everything behaves normally for all players and nobody crashes.
19. (Item #266) Cosmetics: Unify Kruber Shield Illusion Availability. We are missing exact steps for this one, so just play normally and tell us if anything about it looks broken.
20. (Item #272) GUI: Add Scoreboard Features to GUI Tweaker. We are missing exact steps for this one, so just play normally and tell us if anything about it looks broken.
21. (Item #273) Chaos Wastes: after a Chaos Wastes run with a wt cross-character weapon (or a ct weapon-upgrade), return to the keep and check Kruber's active weapon.
   - It works if: everything behaves normally for all players and nobody crashes.
22. (Item #278) cross-mod: host runs cim/cwv, a the other players joins WITHOUT the mod. Host equips a crafted or skinned CWV/cim item (loadout sync).
   - It works if: everything behaves normally for all players and nobody crashes.
23. (Item #279) cross-mod: craft the Outrider Grenade Launcher CWV variant, equip it, and observe it on a the other players the other players' characters.
   - It works if: everything behaves normally for all players and nobody crashes.
24. (Item #285) GUI: Mission with bots; let a bot (or a coop teammate) die - not just get downed.
   - It works if: everything behaves normally for all players and nobody crashes.
25. (Item #287) GUI: enable gut_use_non_modded_loadouts, enter the modded realm, and try to change a cosmetic.
   - It works if: cosmetics stay editable (you can change them) even with "Use non-modded loadouts" ON.
26. (Item #288) Chaos Wastes: Enable tweak_anath_raema_permanent.
   - It works if: everything behaves normally for all players and nobody crashes.
27. (Item #289) Chaos Wastes: Host and the other players enter the same Chaos Wastes mission with the same CT build.
   - It works if: diagnostic result: collect the bounded evidence below; this does not claim the issue is fixed.
28. (Item #296) Tuskgor Javelins cannot recover after impact. We are missing exact steps for this one, so just play normally and tell us if anything about it looks broken.
29. (Item #299) Chaos Wastes: with respawn_on_chest_complete ON in a CW run, player A dies or reaches the awaiting-rescue hang far from the group; player B completes a Chest of Trials.
   - It works if: everything behaves normally for all players and nobody crashes.
30. (Item #309) General: Host an Adventure mission with current gt_dev and one living the other players.
   - It works if: everything behaves normally for all players and nobody crashes.
31. (Item #317) Enable the Animation Picker and equip Dual Axes on Saltzpyre or Kruber.
   - It works if: everything behaves normally for all players and nobody crashes.
32. (Item #321) cross-mod: Open WT, CT, ET, and CRT in Mod Tweaker.
   - It works if: everything behaves normally for all players and nobody crashes.
33. (Item #322) Chaos Wastes: in a CW mission with linked pickups (grimoire / tome), a the other players picks up / drops the item.
   - It works if: everything behaves normally for all players and nobody crashes.
34. (Item #323) Chaos Wastes: Complete one Chaos Wastes pilgrimage with host and the other players logs retained.
   - It works if: diagnostic result: collect the bounded evidence below; this does not claim the issue is fixed.
35. (Item #332) General: as a the other players (non-host), enable "Disable mutator death explosions" (and Max Ragdolls).
   - It works if: the setting takes effect on the other players's own machine (death explosions suppressed the other players-side), not host-only.
36. (Item #333) General: On the host, leave Twitch unlinked and enable Offline Twitch Mode. Load a supported mission with a second player.
   - It works if: result: complete the audited steps below and confirm every issue-specific condition.
37. (Item #342) Chaos Wastes: Start a Chaos Wastes run and acquire either static_blade (lightning on parry) or boon_skulls_03 (drakegun explosion on parry).
   - It works if: everything behaves normally for all players and nobody crashes.
38. (Item #349) Chaos Wastes: As host, set Chests of Trials Per Mission to two.
   - It works if: diagnostic result: collect the bounded evidence below; this does not claim the issue is fixed.
39. (Item #350) Chaos Wastes: Open Trial Rewards During Combat. We are missing exact steps for this one, so just play normally and tell us if anything about it looks broken.
40. (Item #351) Chaos Wastes: Convert Adventure Pickups to Pilgrim's Coins. We are missing exact steps for this one, so just play normally and tell us if anything about it looks broken.
41. (Item #355) General: With /god on: /suicide dies, /down goes down and stays down (expected, documented).
   - It works if: , documented).
42. (Item #357) Chaos Wastes: Give host and the other players different supported bomb-bubble boons and set a visible nonzero cooldown.
   - It works if: result: complete the audited steps below and confirm every issue-specific condition.
43. (Item #358) Chaos Wastes: Both players confirm the current CT Dev build is loaded. Enable Manann's Tempest cooldown, then trigger the weapon-trait source on one players and the mod-boon source on...
   - It works if: everything behaves normally for all players and nobody crashes.
44. (Item #361) Chaos Wastes: Host enables Permanent Purifying Torch Carrier, sets Safe Area Radius to 12 m, and Miasma Stack Interval to 0.5 s. Enter a Rotten Miasma mission with one the other players.
   - It works if: everything behaves normally for all players and nobody crashes.
45. (Item #369) Enemies: Add Per-Difficulty Enemy Health Multipliers. We are missing exact steps for this one, so just play normally and tell us if anything about it looks broken.
46. (Item #371) GUI: host runs cwv; a players joins WITHOUT cwv. Host equips the Tuskgor Javelin (cwv_es_javelin) bomb pool.
   - It works if: everything behaves normally for all players and nobody crashes.
47. (Item #373) Cosmetics: Cosmetics Tweaker 0.9.106-dev is deployed and uploaded (Workshop manifest 5884392257591688555). Co-op verification: on each supported Bretonnian, Empire sword/mace, an...
   - It works if: everything behaves normally for all players and nobody crashes.
48. (Item #377) Cosmetics: Select a glow-capable weapon illusion.
   - It works if: everything behaves normally for all players and nobody crashes.
49. (Item #378) General: B joins A. Expected within ~60s: popup listing the missing mod(s) with Open Workshop + Leave (or the stalled-join notice if A broadcasts no manifest); Leave lands B on...
   - It works if: everything behaves normally for all players and nobody crashes.
50. (Item #380) General: Turn on Disable downed screen effects.
   - It works if: everything behaves normally for all players and nobody crashes.
51. (Item #384) General: One human pushes ~40m ahead; the other goes down near the bots (stay knocked, then bleed out to awaiting-rescue).
   - It works if: everything behaves normally for all players and nobody crashes.
52. (Item #388) Weapons: Both players load the current WT build. Player A equips Deepwood Staff on a non-Sister career, builds low/medium/high overcharge, then swaps to another ranged weapon a...
   - It works if: everything behaves normally for all players and nobody crashes.
53. (Item #395) wearer swaps off the Rapier; it must vanish on the remote view; a caught leak logs a marker in the game log.
   - It works if: everything behaves normally for all players and nobody crashes.
54. (Item #396) host equips the CWV Imperial Longsword; a second player observes the host's the other players' characters.
   - It works if: the weapon is visible on the other players the other players' characters view (residency/mesh parity), not invisible.
55. (Item #398) Related hardening shipped 2026-07-18: cwv v0.1.447-dev consolidated the other players' characters apply + retained-state postcondition logging (a marker in the game log lines), and cosmetics v0.9.1...
   - It works if: everything behaves normally for all players and nobody crashes.
56. (Item #399) crafted Outrider launcher shows no torpedo on the remote view; the other players log [cwv the other players' characters-ammo-strip] via=descriptor.
   - It works if: everything behaves normally for all players and nobody crashes.
57. (Item #406) Chaos Wastes: Both players use the same current Chaos Wastes Tweaker build.
   - It works if: everything behaves normally for all players and nobody crashes.
58. (Item #426) Chaos Wastes: Host starts an expedition with CT v0.7.291-dev and obtains or grants a CT-owned boon or miracle.
   - It works if: the other players joins without a crash; if the positive parity acknowledgement arrived before native sync, the custom state remains active.
59. (Item #458) Chaos Wastes: Keep: /ct_regression_test shows PASS issue458_start_shrine_config; /ct_verify_start_shrine prints the config.
   - It works if: everything behaves normally for all players and nobody crashes.
60. (Item #461) Chaos Wastes: Empty list under the header: the rows were anchored on a scenegraph node with no size, so they computed to a position below the screen and were silently swallowed. Re-...
   - It works if: everything behaves normally for all players and nobody crashes.
61. (Item #472) Career: As Handmaiden, enable the Focused Spirit filter and take each exempt damage family; verify the talent remains active.
   - It works if: everything behaves normally for all players and nobody crashes.
62. (Item #488) General: Host with Tweaker: General DEV v0.2.238-dev and bring a shield-equipped bot; the second player joins as observer/control.
   - It works if: diagnostic output
63. (Item #504) Equip a ct_* custom illusion before mission start.
   - It works if: everything behaves normally for all players and nobody crashes.
64. (Item #531) Enemies: Toggle ON the two new Boss Balance grudge options.
   - It works if: everything behaves normally for all players and nobody crashes.
65. (Item #567) As the other players, equip and persist each original skin: Sword+Mace cwv_es_sword_and_mace_wpn_emp_sword_02_t1_wpn_emp_mace_03_t1, runed Dual Maces, and Axe+Shield. The observe...
   - It works if: everything behaves normally for all players and nobody crashes.
66. (Item #578) Open the Emporium and daily-reward surfaces. The wallet should read [Local] N, and shilling tooltips, purchase labels, and reward rows should identify Local Silver Shi...
   - It works if: everything behaves normally for all players and nobody crashes.
67. (Item #598) With CIM on both players, equip a crafted modded item and inspect its hold-TAB equipment frame from both host/the other players directions.
   - It works if: everything behaves normally for all players and nobody crashes.
68. (Item #629) Cosmetics: Equip Couronne de la Lune and Midnight Purpure and Azure on Grail Knight.
   - It works if: everything behaves normally for all players and nobody crashes.
69. (Item #637) cross-mod: Enable Weapons of Chaos, More Items Library, and Crafting in Modded (Dev). Ensure Enable Blightreaper is on, then enter the Keep.
   - It works if: result
70. (Item #645) Equip Saltzpyre's Greatsword on WHC, Bounty Hunter, or Zealot. Warrior Priest is intentionally excluded.
   - It works if: everything behaves normally for all players and nobody crashes.
71. (Item #660) GUI: Host equips one transformed CWV weapon with a custom illusion; also keep one unmodified vanilla weapon as a control.
   - It works if: everything behaves normally for all players and nobody crashes.
72. (Item #700) General: Start an Adventure mission with both players in the lobby.
   - It works if: everything behaves normally for all players and nobody crashes.
73. (Item #713) Cosmetics: Fully exit and restart Steam/Vermintide so the test begins from a clean mod initialization.
   - It works if: everything behaves normally for all players and nobody crashes.
74. (Item #737) Cosmetics: cwv wearer equips Old Musket, play to the end scoreboard; no a crash to desktop on the a player who does NOT have that mod; wearer log shows a marker in the game log wire skin null ... idx -> n/a.
   - It works if: everything behaves normally for all players and nobody crashes.

## Games with 3 or more players

1. (Item #290) Weapons: On any Kruber career, equip Saltzpyre's Billhook and close the inventory.
   - It works if: everything behaves normally for all players and nobody crashes.
2. (Item #316) Weapons: Both players use matching current WT builds and confirm their load banners.
   - It works if: everything behaves normally for all players and nobody crashes.
3. (Item #400) Weapons: Player A equips Flamestorm Staff on one non-Sienna career supported by WT.
   - It works if: everything behaves normally for all players and nobody crashes.
4. (Item #579) Give one Dual Axes instance different primary and offhand illusions through Tweaker: Cosmetics.
   - It works if: every surface preserves the exact saved right/offhand pair. No surface may reconstruct the base Dual Axes models or swap the hand order.
5. (Item #604) Weapons: Equip Imperial Crowbill Model 05 and compare the inventory character preview, owner third person, remote the other players's view, lobby/team presentation, score screen, and Atha...
   - It works if: every 3P/presentation surface uses the same tuned pose; first person is unchanged.
6. (Item #627) confirm the version line (v0.1.446-dev) shown when the mod loads in the newest log, equip the Outrider Grenade Launcher on Kruber, and check: owner 1P and 3P show the custom launcher (not the blund...
   - It works if: everything behaves normally for all players and nobody crashes.
7. (Item #633) In the keep and again in an Adventure mission, run /woc_audio_contract, then the wielder runs /woc_audio_probe once.
   - It works if: everything behaves normally for all players and nobody crashes.
8. (Item #657) Test Empire Sword and Shield on Grail Knight and Bretonnian Sword and Shield on Mercenary, Huntsman, and Foot Knight with host and the other players on matching builds.
   - It works if: diagnostic result: prove the receiver-specific combat-style boundary before any Sword-and-Shield family is reintroduced; this does not claim a fix.
9. (Item #738) Cosmetics: a marker in the game log skips show local_player_id=2/3/4 controlled=false only; host cosmetics visible on the other players the other players' characters at joining a game already in progress.
   - It works if: everything behaves normally for all players and nobody crashes.

When you are done, tell us which item numbers passed and which did not. Thank you.

