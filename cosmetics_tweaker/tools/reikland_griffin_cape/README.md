# Reikland Griffin cape asset (#656)

This variant uses the original game's `skin_es_knight_red` (Knights Encarmine)
geometry and material package. Only the third-person diffuse is changed. The
first-person texture set and the third-person normal and combined maps are
byte-for-byte copies of the extracted vanilla maps, preserving cloth relief,
roughness/specular response, alpha, cape animation, and camera fading.

## Empirical source bindings

- Vanilla item: `skin_es_knight_red`
- 1P unit: `units/beings/player/empire_soldier_knight/first_person_base/chr_first_person_mesh`
- 3P unit: `units/beings/player/empire_soldier_knight/third_person_base/chr_third_person_mesh`
- Vanilla material package: `units/beings/player/empire_soldier_knight/skins/red/chr_empire_soldier_knight_red`
- Vanilla source maps: `_vt2_item_icons_extract/cosmetic_textures/Outfits/icon_skin_knight_red_Knights_Encarmine`
- Reikland donor diffuse: `Loremasters-Armoury/textures/Kruber_empire_shield_basic1/Kruber_empire_shield_basic1_diffuse.png`

`reikland_griffin_source_cutout.png` and its source mask retain the heraldry
used for the composite. The build texture places it only on the large cape UV
island in `fk_reikland_3p_diffuse.png`; all unrelated atlas pixels are inherited
from the vanilla Knights Encarmine diffuse.

The inherited-map SHA-256 values were compared directly with the extracted
vanilla PNGs:

| Map | SHA-256 |
|---|---|
| 1P diffuse | `34C96D83FEE35877774D5010E724FFF5B4EB516AAC33A86E0A4EF7AEDD18AD84` |
| 1P combined | `585704AB8B2CA5C2BFEA0CD46B2599A97DBD376FBB0DD4A87C66568363438FEC` |
| 1P normal | `A2BC9F47D2AA7C06C22DD8D201AC98579F65A6F01C192590E7F373D476B3E49E` |
| 3P combined | `3B933E4B72A079CC47F514F4837FF882B57403D258D14B874C0B4724DCF95872` |
| 3P normal | `47F97E3DEDFC94ED0A2107BAC21EA0B21C8CDF4DD9985126776557C38C7D7D26` |

The authored 3P diffuse is
`60339642709746585F188CB6926631D2AFA5116D577FC0B8A5D934C12E82E723`.

An ImageMagick absolute-error comparison against the extracted vanilla 3P
diffuse reports 21,612 changed pixels (0.51527% of the 2048x2048 atlas), bounded
to one 189x212 rectangle at `+1285+1359`. That rectangle is the existing cape
island; no other atlas island differs offline.

## Runtime provider and fallback contract

- Provider identity: `issue656_reikland_griffin` (one bounded, collision-checked
  registration in the shared authored-outfit provider).
- Canonical variant: `cos_fk_reikland_griffin_skin_variant`.
- Owner 1P/3P, inventory hero, modded remote husk/lobby, and score presentation
  all resolve that same variant. The remote path is the existing career-scoped
  `cos_la_apply` replay hardened by #698; #513's exact score-row identity remains
  the score boundary.
- Vanilla wire fallback: `skin_es_knight_red`. A peer without Cosmetics receives
  only that resident vanilla identity; the custom item key and texture paths do
  not enter vanilla lookup payloads (#421/#734 class).
- Every native texture bind is preflighted by the shared #749 strict residency
  helper. Missing helpers, malformed slot/path triplets, absent/throwing
  `Application.can_get`, or non-resident resources fail closed to the donor
  appearance. Residency diagnostics cap at 24 records; successful surface
  evidence caps at 32 records.

## Verification boundary

The UV placement must be checked in-game because the extracted runtime source
does not include the skinned Foot Knight mesh UV layout. Verify orientation and
seams while the cape is moving, then check inventory hero, local third person,
remote client/husk, and end-of-mission team presentation.
