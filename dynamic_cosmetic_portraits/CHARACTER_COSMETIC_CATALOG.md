# Character Cosmetic Catalog (Hats + Skins)

Authoritative map of `slot_hat` and `slot_skin` item keys → in-game display names for every Kruber/Bardin/Saltzpyre/Kerillian/Sienna career.

**Source:** `cosmetics_tweaker/_cos_probe.txt` (regenerable in-game via `cos probe_hat`/equivalent dumps that capture `NAME|<key>|<localized>` lines from `Localize`). The probe is the source of truth — re-run it and re-export this catalog if cosmetics are added in a future patch.

**Why this exists:** the dynamic-portrait system in `dynamic_cosmetic_portraits.lua` keys off the values returned by `CosmeticUtils.get_cosmetic_slot(player, "slot_hat" | "slot_skin").item_name`. Those keys are opaque (`mercenary_hat_0006`, `skin_es_default`, …) and the only way to know what a key looks like in-game is to look it up here.

**`(no display name)`** = the entry exists in `ItemMasterList` and is reachable by the probe but has no localization registered. Some are placeholder/un-shipped variants (e.g. `skin_es_mercenary_carroburg`, `skin_es_mercenary_ostland`); some are dev test items. Avoid wiring portraits to these unless you've confirmed in-game that they actually render.

**Notes on conventions:**
- `skin_<short>_default` = "Champion of Ubersreik" — the VT1-era default skin for that character. Lives only on the **starting career** (`es_mercenary` for Kruber, `dr_ranger` for Bardin, `wh_captain` for Saltzpyre, `we_waywatcher` for Kerillian, `bw_adept` for Sienna).
- `*_white` / `*_purified` skins = the "Purified" recolour variants.
- `*_helmgart` / `*_ostermark` / `*_middenland` / etc. = regional palette swaps.
- Hats with a `1010` suffix labelled "Obese Megalodon" are dev/community joke items and can apply across the whole character family.
- Portrait priority in `dynamic_cosmetic_portraits.lua` is **skin first, hat as fallback** — outfits replace the head model regardless of equipped hat.

## File-naming convention for portrait assets

Pattern matches the keys below verbatim so future audits stay simple:

- Hat-keyed: `portrait_kruber_<hat_key>.{png,texture,material}` (and `medium_*`, `small_*`)
- Skin-keyed: `portrait_kruber_<skin_key>.{png,texture,material}` (and `medium_*`, `small_*`)

`<hat_key>` is the bare key as returned by `get_cosmetic_slot` (e.g. `mercenary_hat_0006`). `<skin_key>` likewise (e.g. `skin_es_default`, `skin_es_mercenary_1003`).

---

## Kruber

### Hats
| Key | Native careers | Display name |
|---|---|---|
| `es_hat_0000` | merc, hunts, knight | Old Companion |
| `es_hat_0001` | merc, hunts, knight | Old Companion |
| `es_hat_0002` | merc, hunts, knight | Bögenhafen Bonnet |
| `es_hat_0003` | merc, hunts, knight | Egret Plume Cavalier |
| `es_helmet_0003` | merc, hunts, knight | Blucher's Helmet |
| `huntsman_hat_0000` | hunts | Fugitive's Hood |
| `huntsman_hat_0001` | hunts | Sunset Bonnet |
| `huntsman_hat_0002` | hunts | Hunter's Muffler |
| `huntsman_hat_0003` | hunts | Sentry's Hood |
| `huntsman_hat_0004` | hunts | Marksman's Bonnet |
| `huntsman_hat_0005` | hunts | Reikland Brim |
| `huntsman_hat_0006` | hunts | Outlaw's Crest |
| `huntsman_hat_0007` | hunts | Brigand's Mask |
| `huntsman_hat_0008` | hunts | Kossar's Muffler |
| `huntsman_hat_0009` | hunts | Poacher's Hood |
| `huntsman_hat_1001` | hunts | Trophy of the Gave |
| `huntsman_hat_1002` | hunts | Kossar's Crown |
| `huntsman_hat_1003` | hunts | Sneaker's Helm |
| `huntsman_hat_1005` | hunts | Soothsayer's Skullcap |
| `huntsman_hat_1010` | merc, hunts, knight, qknight | Obese Megalodon |
| `knight_hat_0000` | knight | Reikshammer Casque |
| `knight_hat_0001` | knight | Knight's Muster Helm |
| `knight_hat_0002` | knight | Militia Pot-Helm |
| `knight_hat_0003` | knight | Grim Gatekeeper |
| `knight_hat_0004` | knight | Steel Resolve |
| `knight_hat_0005` | knight | Counterfeit Crown |
| `knight_hat_0006` | knight | Laurel Helm |
| `knight_hat_0007` | knight | Myrmidia's Crown |
| `knight_hat_0008` | knight | Roaring Crest |
| `knight_hat_0009` | knight | Scarred Close-Helm |
| `knight_hat_0010` | knight | Ironset Laurels |
| `knight_hat_0011` | knight | The Veteran |
| `knight_hat_1001` | knight | Scour-Sun Helm |
| `knight_hat_1002` | knight | Myrmidia's Gaze |
| `knight_hat_1003` | knight | Griffon Crown |
| `mercenary_hat_0000` | merc | Reikland Griffonplume |
| `mercenary_hat_0001` | merc | Estalian Conquistador |
| `mercenary_hat_0002` | merc | Lucky Horseshoe |
| `mercenary_hat_0003` | merc | Plumed Horseshoe |
| `mercenary_hat_0004` | merc | Morr's Mask |
| `mercenary_hat_0005` | merc | Sellsword's Twinplume |
| `mercenary_hat_0006` | merc | Stirland Tri-plume |
| `mercenary_hat_0007` | merc | Courtier's Crest |
| `mercenary_hat_0008` | merc | Rakish Leatherbrim |
| `mercenary_hat_0009` | merc | Veteran's Scars |
| `mercenary_hat_1001` | merc | Marienburg Bicorne |
| `mercenary_hat_1002` | merc | Marshal Ludenwald's Favourite Hat |
| `mercenary_hat_1003` | merc | Wolverheart Crown |
| `questing_knight_hat_0000` | qknight | Helm of the Worthy |
| `questing_knight_hat_0001` | qknight | Pureheart Helm |
| `questing_knight_hat_0003` | qknight | Hippogryph Helm |
| `questing_knight_hat_1001` | qknight | Crown of the True King (Possibly Genuine) |

### Skins
| Key | Native careers | Display name |
|---|---|---|
| `skin_es_default` | merc | **Champion of Ubersreik** *(VT1 default outfit)* |
| `skin_es_mercenary` | merc | Reikland Bodyguard |
| `skin_es_mercenary_1001` | merc | Hellequin's Raiment |
| `skin_es_mercenary_1002` | merc | Wolverheart Furs |
| `skin_es_mercenary_1003` | merc | Felix Jaeger |
| `skin_es_mercenary_black_and_gold` | merc | (no display name) |
| `skin_es_mercenary_carroburg` | merc | (no display name) |
| `skin_es_mercenary_helmgart` | merc | Helmgart Hireling |
| `skin_es_mercenary_middenland` | merc | (no display name) |
| `skin_es_mercenary_ostermark` | merc | Ostermark Sellsword |
| `skin_es_mercenary_ostland` | merc | (no display name) |
| `skin_es_mercenary_white` | merc | Mercenary (Purified) |
| `skin_es_huntsman` | hunts | (no display name) |
| `skin_es_huntsman_1001` | hunts | Wulfhart's Array |
| `skin_es_huntsman_black_and_gold` | hunts | Nuln Bordermarcher |
| `skin_es_huntsman_middenland` | hunts | Middenland Wolf-leathers |
| `skin_es_huntsman_ostermark` | hunts | Ostermark Bowman |
| `skin_es_huntsman_red_and_white` | hunts | Talabecland Hunter |
| `skin_es_huntsman_white` | hunts | Huntsman (Purified) |
| `skin_es_huntsman_yellow_and_green` | hunts | Stirland Poacher |
| `skin_es_longshark` | hunts | Herald of King Taal |
| `skin_es_knight` | knight | Reikshammer Plate |
| `skin_es_knight_1001` | knight | Knight Griffon |
| `skin_es_knight_1002` | knight | Armour of the Blazing Sun |
| `skin_es_knight_black_and_gold` | knight | Livery of the Blazing Sun |
| `skin_es_knight_bronze` | knight | Order of the Brazen Shield |
| `skin_es_knight_green` | knight | Hermit Knight's Armour |
| `skin_es_knight_middenland` | knight | (no display name) |
| `skin_es_knight_red` | knight | Knights Encarmine |
| `skin_es_knight_white` | knight | Foot Knight (Purified) |
| `skin_es_questingknight` | qknight | Gallant of Parravon |
| `skin_es_questingknight_1001` | qknight | Raiment of the True King (Unverified) |
| `skin_es_questingknight_black_and_gold` | qknight | Outcast of Parravon |
| `skin_es_questingknight_black_and_yellow` | qknight | Champion of Parravon |
| `skin_es_questingknight_blue_and_white` | qknight | Wayfarer's Vestments |
| `skin_es_questingknight_white` | qknight | Grail Knight (Purified) |
| `skin_es_questingknight_yellow_and_white` | qknight | Paladin of Parravon |

## Bardin

### Hats
| Key | Native careers | Display name |
|---|---|---|
| `dr_helmet_0000` | ranger, ironbreaker | Ald Karaki |
| `dr_helmet_0001` | ranger, ironbreaker | Ald Karaki |
| `dr_helmet_0002` | ranger, ironbreaker | Karak Vlag Grimazul |
| `dr_helmet_0003` | ranger, ironbreaker | Drakk Goruz |
| `dr_helmet_0005` | ranger, ironbreaker | Galar Konk |
| `dr_helmet_0008` | ranger, ironbreaker | Rilar Ghalklad |
| `dr_helmet_0011` | ranger, ironbreaker | Nuf Boga |
| `engineer_hat_0000` | eng | Outcast's Skullcap |
| `engineer_hat_0001` | eng | Cogboki |
| `engineer_hat_1001` | eng | Boki Smedniri |
| `engineer_hat_1002` | eng | Angrund Helm (Possibly) |
| `ironbreaker_hat_0000` | ib | Dawazbak Naibok |
| `ironbreaker_hat_0001` | ib | Zulunbakiaz Nairikkit |
| `ironbreaker_hat_0002` | ib | Bokiboki |
| `ironbreaker_hat_0003` | ib | Ungdringiklad |
| `ironbreaker_hat_0004` | ib | Bryngormkap |
| `ironbreaker_hat_0005` | ib | Wrothklad |
| `ironbreaker_hat_0006` | ib | Grungazad's Brynkap |
| `ironbreaker_hat_0007` | ib | Zulunbakiaz Gorogkap |
| `ironbreaker_hat_0008` | ib | Bolgbrynazkap |
| `ironbreaker_hat_0009` | ib | Zulunbakiaz Goruzgorm |
| `ironbreaker_hat_0010` | ib | Zulunbakiaz Bryngorm |
| `ironbreaker_hat_0011` | ib | Rikaz Brynkap |
| `ironbreaker_hat_0012` | ib | Barazaldkap |
| `ironbreaker_hat_0013` | ib | Bryndawazbak |
| `ironbreaker_hat_1001` | ib | The Anvil of Doom |
| `ironbreaker_hat_1002` | ib | Bakbok |
| `ironbreaker_hat_1004` | ib | Gungasti |
| `ironbreaker_hat_1005` | ib | The Lost Helm of Karak-Hirn |
| `ranger_hat_0000` | ranger | Karakiaz Dawazbakthrund |
| `ranger_hat_0001` | ranger | Kladkap |
| `ranger_hat_0002` | ranger | Gnorlklad |
| `ranger_hat_0003` | ranger | Orrudklad |
| `ranger_hat_0004` | ranger | Goruzklad |
| `ranger_hat_0005` | ranger | Karakiaz Chufdrongol |
| `ranger_hat_0006` | ranger | Skazkald |
| `ranger_hat_0007` | ranger | Karakiaz Rikklad |
| `ranger_hat_0008` | ranger | Horrstub |
| `ranger_hat_0009` | ranger | Brugchufdrongol |
| `ranger_hat_0010` | ranger | Grobchufdrongol |
| `ranger_hat_0011` | ranger | Rhynchufdrongol |
| `ranger_hat_0012` | ranger | Krutskazklad |
| `ranger_hat_0013` | ranger | Grobskazklad |
| `ranger_hat_0014` | ranger | Karakiaz Brynklad |
| `ranger_hat_0015` | ranger | Karakiaz Grobklad |
| `ranger_hat_1001` | ranger | The Golden Taurox |
| `ranger_hat_1005` | ranger | Kahirn |
| `ranger_hat_1006` | ranger | Ranger's Tattered Patch |
| `ranger_hat_1010` | ranger, ib, eng | Obese Megalodon |
| `slayer_hat_0000` | slayer | Gurnissonaz Zanghal |
| `slayer_hat_0001` | slayer | Drengi Zandawazbak |
| `slayer_hat_0002` | slayer | Stumpdrengi |
| `slayer_hat_0003` | slayer | Drengivar |
| `slayer_hat_0004` | slayer | Angazdrengi |
| `slayer_hat_0005` | slayer | Nadok |
| `slayer_hat_0006` | slayer | Drongobang |
| `slayer_hat_0007` | slayer | Angkonk |
| `slayer_hat_0008` | slayer | Brynzandawazbak |
| `slayer_hat_0009` | slayer | Uzkulkonk |
| `slayer_hat_0010` | slayer | Wrothdrengi |
| `slayer_hat_0011` | slayer | Angazundi |
| `slayer_hat_0012` | slayer | Angazstump |
| `slayer_hat_1001` | slayer | The Iron Mohawk |
| `slayer_hat_1002` | slayer | Long Drong's Favourite Hat |
| `slayer_hat_1005` | slayer | Ritual Hearth Tattoo |
| `slayer_hat_1010` | slayer | Obese Megalodon |

### Skins
| Key | Native careers | Display name |
|---|---|---|
| `skin_dr_default` | ranger | **Champion of Ubersreik** *(VT1 default outfit)* |
| `skin_dr_ranger` | ranger | Strollaz Raggarin |
| `skin_dr_ranger_1001` | ranger | Varagvlag |
| `skin_dr_ranger_1002` | ranger | Ranger's Wilds-Worn Garb |
| `skin_dr_ranger_barak_varr` | ranger | Barak Varr Kulgurakiklad |
| `skin_dr_ranger_black_and_gold` | ranger | Drungiklad |
| `skin_dr_ranger_brown_and_yellow` | ranger | (no display name) |
| `skin_dr_ranger_helmgart` | ranger | Helmgart Karakiklad |
| `skin_dr_ranger_karak_norn` | ranger | (no display name) |
| `skin_dr_ranger_white` | ranger | Dwarf Ranger (Purified) |
| `skin_dr_ranger_zhufbar` | ranger | Zhufbar Strollazklad |
| `skin_dr_ironbreaker` | ib | (no display name) |
| `skin_dr_ironbreaker_1001` | ib | Galazklad |
| `skin_dr_ironbreaker_black_and_gold` | ib | Gromdalklad |
| `skin_dr_ironbreaker_blue` | ib | Gromvarrklad |
| `skin_dr_ironbreaker_crimson` | ib | Zulunbaki Azulklad |
| `skin_dr_ironbreaker_green` | ib | Zulunbaki Azamarklad |
| `skin_dr_ironbreaker_iron` | ib | (no display name) |
| `skin_dr_ironbreaker_white` | ib | Ironbreaker (Purified) |
| `skin_dr_irondrake` | ib | Valaya's Hearthguard |
| `skin_dr_slayer` | slayer | Drengiaz Lankgruntaz |
| `skin_dr_slayer_1001` | slayer | Slayer Pirate's Garb |
| `skin_dr_slayer_1002` | slayer | Protection of the Peaks |
| `skin_dr_slayer_1003` | slayer | Gotrek Gurnisson |
| `skin_dr_slayer_axe` | slayer | (no display name) |
| `skin_dr_slayer_dragon` | slayer | Drakkadrengirhun |
| `skin_dr_slayer_runes` | slayer | Alddrengirhun |
| `skin_dr_slayer_skaven` | slayer | Rakidrengirhun |
| `skin_dr_slayer_skull` | slayer | (no display name) |
| `skin_dr_slayer_white` | slayer | Slayer (Purified) |
| `skin_dr_slayer_wing` | slayer | Krodrengirhun |
| `skin_dr_engineer` | eng | (no display name) |
| `skin_dr_engineer_1001` | eng | Angrundklad (Perhaps) |
| `skin_dr_engineer_black_and_gold` | eng | Gromthi Endriniklad |
| `skin_dr_engineer_blue_and_gold` | eng | (no display name) |
| `skin_dr_engineer_brown_and_iron` | eng | (no display name) |
| `skin_dr_engineer_purple_and_copper` | eng | (no display name) |
| `skin_dr_engineer_white` | eng | (no display name) |

## Saltzpyre

### Hats
| Key | Native careers | Display name |
|---|---|---|
| `wh_hat_0000` | captain, bh, zealot | Clay Pipe Hat |
| `wh_hat_0001` | captain, bh, zealot | Clay Pipe Hat |
| `wh_hat_0003` | captain, bh, zealot | Comet Capotain |
| `wh_hat_0007` | zealot | Cult of Sigmar |
| `wh_hat_0008` | bh | Reikwald Hat |
| `wh_hat_0009` | bh | Reikwald Hat |
| `witchhunter_hat_0000` | captain | Dread Deliverance |
| `witchhunter_hat_0001` | captain | Scribe's Watchtower |
| `witchhunter_hat_0002` | captain | Warrant-Keeper's Watchtower |
| `witchhunter_hat_0003` | captain | Candlewick Watchtower |
| `witchhunter_hat_0004` | captain | Templar's Watchtower |
| `witchhunter_hat_0005` | captain | Battered Watchtower |
| `witchhunter_hat_0006` | captain | Skullcrest Watchtower |
| `witchhunter_hat_0007` | captain | Tyrant's Bicorne |
| `witchhunter_hat_0008` | captain | Battered Tricorne |
| `witchhunter_hat_0009` | captain | Rakish Bicorne |
| `witchhunter_hat_0010` | captain | The Vengeful Peacock |
| `witchhunter_hat_1001` | captain | Purist's Stovepipe |
| `witchhunter_hat_1003` | captain | Beast-Hunter's Hat |
| `witchhunter_hat_1004` | captain | Solstice Warden's Hood |
| `bountyhunter_hat_0000` | bh | Faceless Judgement |
| `bountyhunter_hat_0001` | bh | The Watcher |
| `bountyhunter_hat_0002` | bh | Diligence |
| `bountyhunter_hat_0003` | bh | Brugheim's Redeemer |
| `bountyhunter_hat_0004` | bh | One-Eye's Revenge |
| `bountyhunter_hat_0005` | bh | Old Iron Jaw |
| `bountyhunter_hat_0006` | bh | Purity Helm |
| `bountyhunter_hat_0007` | bh | Komet Mark |
| `bountyhunter_hat_0008` | bh | The Iron Reaper |
| `bountyhunter_hat_0009` | bh | The Blazing Skull |
| `bountyhunter_hat_1001` | bh | Deathvigil Mask |
| `bountyhunter_hat_1002` | bh | Friedhelm's Flamboyance |
| `bountyhunter_hat_1004` | bh | Tax Collector's Cap |
| `bountyhunter_hat_1005` | bh | Candelight Helm |
| `bountyhunter_hat_1010` | captain, bh, priest | Obese Megalodon |
| `zealot_hat_0000` | zealot | Flagellant's Brand |
| `zealot_hat_0001` | zealot | Nails of Judgement |
| `zealot_hat_0002` | zealot | Band of Zeal |
| `zealot_hat_0003` | zealot | Prayer Stump |
| `zealot_hat_0004` | zealot | Zealot's Prayer Band |
| `zealot_hat_0005` | zealot | Sin Shield |
| `zealot_hat_0006` | zealot | Blinderkomet |
| `zealot_hat_0007` | zealot | Reckoner's Mark |
| `zealot_hat_0008` | zealot | Sollenkrux |
| `zealot_hat_0009` | zealot | Morr's Wreath |
| `zealot_hat_0010` | zealot | Hammerkine |
| `zealot_hat_0011` | zealot | The Heldenmark |
| `zealot_hat_1001` | zealot | Stolen Swine |
| `zealot_hat_1002` | zealot | Manann's Favour |
| `zealot_hat_1003` | zealot | Crown of Purity |
| `zealot_hat_1007` | zealot | Ratechism |
| `zealot_hat_1010` | zealot | Obese Megalodon |
| `priest_hat_0000` | priest | Priest's Sky Helm |
| `priest_hat_0001` | priest | Penitent's Band |
| `priest_hat_0002` | priest | Circlet of Purity |
| `priest_hat_0003` | priest | Brass Wreath |
| `priest_hat_0004` | priest | Redemptor's Patch |
| `priest_hat_1001` | priest | Headband of Huss (Almost Certainly) |

### Skins
| Key | Native careers | Display name |
|---|---|---|
| `skin_wh_default` | captain | **Champion of Ubersreik** *(VT1 default outfit)* |
| `skin_wh_captain` | captain | Captain's Longcoat |
| `skin_wh_captain_1001` | captain | Helhunten's Hauberk |
| `skin_wh_captain_1002` | captain | (no display name) |
| `skin_wh_captain_black_and_gold` | captain | Imperial Chamberlain's Finery |
| `skin_wh_captain_grey_and_yellow` | captain | Seeker's Longcoat |
| `skin_wh_captain_helmgart` | captain | Helmgart's Redeemer |
| `skin_wh_captain_middenland` | captain | (no display name) |
| `skin_wh_captain_ostermark` | captain | Ostermark Constable |
| `skin_wh_captain_ostland` | captain | Sigmar's Executioner |
| `skin_wh_captain_white` | captain | Witch Hunter Captain (Purified) |
| `skin_wh_bountyhunter` | bh | Bounty Hunter's Gambeson |
| `skin_wh_bountyhunter_1001` | bh | Gambler's Glamour |
| `skin_wh_bountyhunter_1002` | bh | (no display name) |
| `skin_wh_bountyhunter_1003` | bh | Count Boris Todbringer |
| `skin_wh_bountyhunter_black_and_gold` | bh | Drakwald Hunter |
| `skin_wh_bountyhunter_brown_and_white` | bh | Ostermark Leveller |
| `skin_wh_bountyhunter_green_and_yellow` | bh | (no display name) |
| `skin_wh_bountyhunter_middenland` | bh | Middenland Wolfclaw |
| `skin_wh_bountyhunter_white` | bh | Bounty Hunter (Purified) |
| `skin_wh_bountyhunter_yellow_and_red` | bh | Blood-Bounty Gambeson |
| `skin_wh_zealot` | zealot | (no display name) |
| `skin_wh_zealot_1001` | zealot | Redemptive One |
| `skin_wh_zealot_black_and_gold` | zealot | (no display name) |
| `skin_wh_zealot_crimson` | zealot | Priest of Slaughter |
| `skin_wh_zealot_green_and_yellow` | zealot | (no display name) |
| `skin_wh_zealot_middenland` | zealot | Midnight Penance Robes |
| `skin_wh_zealot_pure` | zealot | Werner Krabb's Holy Armour |
| `skin_wh_zealot_white` | zealot | Zealot (Purified) |
| `skin_wh_flagellant` | zealot | Flagellant of the Twin-Tailed Comet |
| `skin_wh_priest` | priest | (no display name) |
| `skin_wh_priest_0002` | priest | Vestments of the Confessor |
| `skin_wh_priest_0002_a` | priest | Vestments of Glory |
| `skin_wh_priest_1001` | priest | (no display name) |
| `skin_wh_priest_white` | priest | Warrior Priest of Sigmar (Purified) |

## Kerillian

### Hats
| Key | Native careers | Display name |
|---|---|---|
| `ww_hood_0000` | ww, mg | Waywatcher Hood |
| `ww_hood_0001` | ww, mg | Waywatcher Hood |
| `ww_hood_0002` | ww, mg | Mask of the Sentinel |
| `ww_hood_0004` | ww, mg | Horns of Drakira |
| `waywatcher_hat_0000` | ww | Stalker's Hood |
| `waywatcher_hat_0001` | ww | Horns of Kurnous |
| `waywatcher_hat_0002` | ww | Barkshield Mask |
| `waywatcher_hat_0003` | ww | Living Leafcrown |
| `waywatcher_hat_0004` | ww | Branch Horn |
| `waywatcher_hat_0005` | ww | Whisperer's Guise |
| `waywatcher_hat_0006` | ww | Gladewatcher's Half-Mask |
| `waywatcher_hat_0007` | ww | Ambusher's Hood |
| `waywatcher_hat_0008` | ww | Windrush Crest |
| `waywatcher_hat_0009` | ww | Drassillia's Mask |
| `waywatcher_hat_0010` | ww | Kurnous' Herald |
| `waywatcher_hat_0011` | ww | Evercrown |
| `waywatcher_hat_1001` | ww | Aspect of Adanhu |
| `waywatcher_hat_1004` | ww | Forebear's Helm |
| `waywatcher_hat_1005` | ww | Atylwyth Crown |
| `waywatcher_hat_1010` | ww | Obese Megalodon |
| `maidenguard_hat_0000` | mg | Protector's Circlet |
| `maidenguard_hat_0001` | mg | Warmaid's Barbute |
| `maidenguard_hat_0002` | mg | Crown of Lileath |
| `maidenguard_hat_0003` | mg | Eagle Crest |
| `maidenguard_hat_0004` | mg | Bloodgem Crown |
| `maidenguard_hat_0005` | mg | Wingshield Helm |
| `maidenguard_hat_0006` | mg | Starlight Helm |
| `maidenguard_hat_0007` | mg | Gilded Shame |
| `maidenguard_hat_0008` | mg | Mask of the Chaste |
| `maidenguard_hat_0009` | mg | Silent Watcher |
| `maidenguard_hat_0010` | mg | Burning Crown |
| `maidenguard_hat_1001` | mg | Wildrunner's Helm |
| `maidenguard_hat_1002` | mg | Chracian Lion Helm |
| `maidenguard_hat_1004` | mg | Reaver's Helm |
| `maidenguard_hat_1005` | mg | The Crown of Avelorn (Facsimile) |
| `maidenguard_hat_1010` | mg | Obese Megalodon |
| `shade_hat_0000` | shade | Clar Karond Veil |
| `shade_hat_0001` | shade | Shadow Mask |
| `shade_hat_0002` | shade | City Guard's Helm |
| `shade_hat_0003` | shade | Seadrake Helm |
| `shade_hat_0004` | shade | Naggarond Spike |
| `shade_hat_0005` | shade | Eldrazor's Crown |
| `shade_hat_0006` | shade | The Faceless Killer |
| `shade_hat_0007` | shade | Helm of Torment |
| `shade_hat_0008` | shade | Dreadmask |
| `shade_hat_0009` | shade | Contest Helm |
| `shade_hat_0010` | shade | Filthy Rag |
| `shade_hat_1001` | shade | Executioner's Helm |
| `shade_hat_1002` | shade | Mask of the Shadow-Slayer |
| `shade_hat_1003` | shade | Drakira's Grin |
| `shade_hat_1004` | shade | Gladiatorial Gaze |
| `shade_hat_1010` | shade | Obese Megalodon |
| `thornsister_hat_0000` | ts | Thornmaiden's Crown |
| `thornsister_hat_0001` | ts | Thornmaven's Crown |
| `thornsister_hat_0002` | ts | Eternos Crown |
| `thornsister_hat_0003` | ts | Bitterbloom Circlet |
| `thornsister_hat_1010` | ts | Obese Megalodon |

### Skins
| Key | Native careers | Display name |
|---|---|---|
| `skin_ww_default` | ww | **Champion of Ubersreik** *(VT1 default outfit)* |
| `skin_ww_waywatcher` | ww | Waywatcher |
| `skin_ww_waywatcher_1001` | ww | Herald of the Weave |
| `skin_ww_waywatcher_1002` | ww | Atylwyth Chanter's Robe |
| `skin_ww_waywatcher_anmyr` | ww | Anmyr Beaststalker |
| `skin_ww_waywatcher_atylwyth` | ww | (no display name) |
| `skin_ww_waywatcher_black_and_gold` | ww | Modryn Nightstalker |
| `skin_ww_waywatcher_cythral` | ww | Spiritward of Cythral |
| `skin_ww_waywatcher_helmgart` | ww | Helmgart Sentinel |
| `skin_ww_waywatcher_tirsyth` | ww | Bleakcloak of Tirsyth |
| `skin_ww_waywatcher_white` | ww | Waystalker (Purified) |
| `skin_ww_maidenguard` | mg | (no display name) |
| `skin_ww_maidenguard_1001` | mg | Chracian Valourguard |
| `skin_ww_maidenguard_1002` | mg | High Robes of Isha (Counterfeit) |
| `skin_ww_maidenguard_black_and_gold` | mg | (no display name) |
| `skin_ww_maidenguard_caledor` | mg | Bleakmaiden Guard |
| `skin_ww_maidenguard_elyrion` | mg | (no display name) |
| `skin_ww_maidenguard_red_and_yellow` | mg | Spirit Talker's Raiment |
| `skin_ww_maidenguard_white` | mg | Handmaiden (Purified) |
| `skin_ww_maidenguard_white_and_gold` | mg | (no display name) |
| `skin_ww_moonmantle` | mg | Daughter of Lileath |
| `skin_ww_shade` | shade | Shade |
| `skin_ww_shade_1001` | shade | Naggarond Backstabber |
| `skin_ww_shade_1002` | shade | Dreadguard's Mantle |
| `skin_ww_shade_ash` | shade | (no display name) |
| `skin_ww_shade_black_and_gold` | shade | Clar Karond Royalblood |
| `skin_ww_shade_crimson` | shade | (no display name) |
| `skin_ww_shade_emerald` | shade | Disciple of Anath Raema |
| `skin_ww_shade_midnight` | shade | Herald of the Pale Queen |
| `skin_ww_shade_white` | shade | Shade (Purified) |
| `skin_ww_thornsister` | ts | Summertide's Raiment |
| `skin_ww_thornsister_1001` | ww, mg, shade, ts | Naieth the Prophetess |
| `skin_ww_thornsister_black_and_gold` | ts | Sister of the Night Glens |
| `skin_ww_thornsister_blue` | ts | Sister of the Frozen Heart |
| `skin_ww_thornsister_green` | ts | (no display name) |
| `skin_ww_thornsister_redblack` | ts | Atharti's Handmaiden |
| `skin_ww_thornsister_white` | ts | (no display name) |

## Sienna

### Hats
| Key | Native careers | Display name |
|---|---|---|
| `bw_gate_0000` | adept, scholar, unchained | Bright College Battle Guard |
| `bw_gate_0001` | adept, scholar, unchained | Bright College Battle Guard |
| `bw_gate_0006` | adept, scholar, unchained | Gates of Fulmination |
| `bw_gate_0007` | adept, scholar, unchained | Crown of Cremation |
| `bw_gate_0008` | adept, scholar, unchained | Fangs of the Hydra |
| `adept_hat_0000` | adept | Aqshy Torchgate |
| `adept_hat_0001` | adept | Matriarch's Torchgate |
| `adept_hat_0002` | adept | Keymaster's Torchgate |
| `adept_hat_0003` | adept | Flamekeeper's Torchgate |
| `adept_hat_0004` | adept | Brandmaker's Torchgate |
| `adept_hat_0005` | adept | Adept's Torchgate |
| `adept_hat_0006` | adept | Seer's Torchgate |
| `adept_hat_0007` | adept | Regal Torchgate |
| `adept_hat_0008` | adept | Illuminator's Collar |
| `adept_hat_0009` | adept | The Five-Fold Flame |
| `adept_hat_0010` | adept | The Smouldering Towers |
| `adept_hat_1001` | adept | Memento Furioso |
| `adept_hat_1002` | adept | Brazier Crown |
| `adept_hat_1003` | adept | Tri-Skull Crown |
| `adept_hat_1005` | adept | Gormann's Cindercage (Salvaged) |
| `adept_hat_1010` | adept, scholar, unchained | Obese Megalodon |
| `scholar_hat_0000` | scholar | Flamevigil Collar |
| `scholar_hat_0001` | scholar | Pyromancer's Candlegate |
| `scholar_hat_0002` | scholar | Eternal Candlegate |
| `scholar_hat_0003` | scholar | Stalwart's Candlegate |
| `scholar_hat_0004` | scholar | Heavenly Candlegate |
| `scholar_hat_0005` | scholar | Morr's Candlegate |
| `scholar_hat_0006` | scholar | Grand Candlegate |
| `scholar_hat_0007` | scholar | Enduring Candlegate |
| `scholar_hat_0008` | scholar | Sunburst Candlegate |
| `scholar_hat_0009` | scholar | Worshipful Candlegate |
| `scholar_hat_0010` | scholar | Majestic Candlegate |
| `scholar_hat_0011` | scholar | Gilded Candlegate |
| `scholar_hat_0012` | scholar | Pyrodeus' Candlegate |
| `scholar_hat_1001` | scholar | Fulminator's Crown |
| `scholar_hat_1002` | scholar | Candlevane Collar |
| `scholar_hat_1003` | scholar | Scholar's Lantern Helm |
| `scholar_hat_1004` | scholar | Midwinter Tines |
| `unchained_hat_0000` | unchained | Mask of the Condemned |
| `unchained_hat_0001` | unchained | Witch's Mask |
| `unchained_hat_0002` | unchained | Iron Crown |
| `unchained_hat_0003` | unchained | Lost Mask |
| `unchained_hat_0004` | unchained | Tentacle Helm |
| `unchained_hat_0005` | unchained | Inferno Circlet |
| `unchained_hat_0006` | unchained | Skullmask of the Exile |
| `unchained_hat_0007` | unchained | Crown of Glory |
| `unchained_hat_0008` | unchained | Mask of the Living Flame |
| `unchained_hat_0009` | unchained | Kadra's Deathmask |
| `unchained_hat_1001` | unchained | Incandescent Brand |
| `unchained_hat_1003` | unchained | Immolator's Casket |
| `unchained_hat_1004` | unchained | Flame Within |
| `bw_necromancer_hat_0000` | necro | Flesh-Stitched Collar |
| `bw_necromancer_hat_0001` | necro | Alabaster Locks |
| `bw_necromancer_hat_0002` | necro | Ritual Crown |
| `bw_necromancer_hat_0003` | necro | Ill-Hallowed Hood |
| `bw_necromancer_hat_1010` | necro | Obese Megalodon |

### Skins
| Key | Native careers | Display name |
|---|---|---|
| `skin_bw_default` | adept | **Champion of Ubersreik** *(VT1 default outfit)* |
| `skin_bw_adept` | adept | Robes of the Bright Order |
| `skin_bw_adept_1001` | adept | (no display name) |
| `skin_bw_adept_1002` | adept | (no display name) |
| `skin_bw_adept_ash` | adept | Robes of the Faded Flame |
| `skin_bw_adept_black_and_gold` | adept | (no display name) |
| `skin_bw_adept_brown_and_yellow` | adept | (no display name) |
| `skin_bw_adept_helmgart` | adept | Helmgart Maven |
| `skin_bw_adept_ostermark` | adept | Ostermark Bonds-Witch |
| `skin_bw_adept_ostland` | adept | (no display name) |
| `skin_bw_adept_white` | adept | Battle Wizard (Purified) |
| `skin_bw_scholar` | scholar | (no display name) |
| `skin_bw_scholar_1001` | scholar | Seeker's Robes |
| `skin_bw_scholar_1002` | scholar | Midwinter Flammengarb |
| `skin_bw_scholar_1003` | scholar, necro | Isabella von Carstein |
| `skin_bw_scholar_ash` | scholar | Ash Queen's Robes |
| `skin_bw_scholar_black_and_gold` | scholar | Majestic Mantle |
| `skin_bw_scholar_bronze` | scholar | Five Hundred Secret Words |
| `skin_bw_scholar_brown_and_white` | scholar | Cinderweaver's Robes |
| `skin_bw_scholar_ostermark` | scholar | Librarian's Bindings |
| `skin_bw_scholar_white` | scholar | Pyromancer (Purified) |
| `skin_bw_myrmidia` | scholar | Judge of Myrmidia |
| `skin_bw_unchained` | unchained | Chains of Purpose |
| `skin_bw_unchained_1001` | unchained | (no display name) |
| `skin_bw_unchained_1002` | unchained | Maven's Cindergarb |
| `skin_bw_unchained_ash` | unchained | The Raging Wind |
| `skin_bw_unchained_black_and_gold` | unchained | (no display name) |
| `skin_bw_unchained_bronze` | unchained | All-Consuming Fire |
| `skin_bw_unchained_brown_and_white` | unchained | (no display name) |
| `skin_bw_unchained_ostermark` | unchained | (no display name) |
| `skin_bw_unchained_white` | unchained | Unchained (Purified) |
| `skin_bw_necromancer` | necro | Caller of the Dead |
| `skin_bw_necromancer_0001` | necro | Wandering Reanimator |
| `skin_bw_necromancer_0001_a` | necro | Sylvanian Vizier |
| `skin_bw_necromancer_0002` | necro | Chanteuse of the Black Host |
| `skin_bw_necromancer_white` | necro | Necromancer (Purified) |
