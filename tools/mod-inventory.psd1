# tools/mod-inventory.psd1
#
# SINGLE SOURCE OF TRUTH for the active-mod inventory. Release and QA consumers read it:
#   - tools/publish-release/publish-release.ps1  (build + GitHub-release set)
#   - tools/mod-lint/lint-mod.ps1                 ($KnownMods scan list)
#   - qa/check_cfg.ps1                            (per-mod expected visibility)
#   - qa/check_mod_inventory.ps1                  (completeness + identity gate)
#
# Before this file existed, those three hand-maintained their own lists and
# drifted: mod-lint listed RETIRED `lobby_tweaker` / `material_hijack_patched`
# and OMITTED all four `*_dev` clones (so a duplicate-hook in a dev tree went
# unscanned); publish-release omitted `gui_tweaker`; check_cfg carried its own
# visibility map. This .psd1 is the reconciled set.
#
# Source of truth for the values: CLAUDE.md § "Mod Directory" + each mod's
# itemV2.cfg (published_id, visibility). Keep them in sync here on any change.
#
# Per-entry fields:
#   Dir        - folder name under the repo root (also the lua filename stem)
#   ModId      - VMF new_mod() registration id (short id where one exists)
#   WorkshopId - published_id from itemV2.cfg (empty string if unpublished)
#   Visibility - intended Workshop visibility (public / friends_only / private)
#   Stream     - single | stable | dev
#   Public     - $true only for visibility=public stable items (the --allow-public set)
#   Name       - friendly name for the release manifest
#   RootBundle - mod-specific compiled root package in bundleV2/; shared VMF
#                bundles and optional asset sidecars never satisfy this identity
#   BuildArtifactExclusions - optional exact-name + SHA-256 allowlist for known
#                SDK tool-only artifacts removed after a successful VMB build
#                and before parity/deploy. A changed hash fails closed.
#
# EXCLUDED: legacy frozen `tweaker` (SDK build, Workshop 3704660429). The
# friends-only `weapon_tweaker_dev` mirror is active and parity-gated.
#
# NOTE: this is a pure data file (Import-PowerShellDataFile / Invoke-Expression
# safe). No executable statements, no comment-based help blocks.

@{
    Mods = @(
        @{
            Dir = 'weapon_tweaker'; ModId = 'wt'; WorkshopId = '3712896117';
            Visibility = 'public'; Stream = 'single'; Public = $true;
            Name = 'Weapon Tweaker'; RootBundle = 'ebaffd734a22c9a0.mod_bundle';
            BuildArtifactExclusions = @(
                @{
                    Name = 'e7852992f40eb619.mod_bundle';
                    Sha256 = 'e1a04e500f8255ebedcaffb4e35e829adbd99ebf46c2b8b4cd89d26dca4735e2';
                    Reason = 'SDK tool-only BUNDLE=false LUT-generator sidecar emitted by clean Stingray builds'
                }
            )
        }
        @{
            Dir = 'weapon_tweaker_dev'; ModId = 'wt_dev'; WorkshopId = '3748824853';
            Visibility = 'friends_only'; Stream = 'dev'; Public = $false;
            Name = 'Weapon Tweaker (Dev)'; RootBundle = 'd38aa5cd35c79c3d.mod_bundle';
            BuildArtifactExclusions = @(
                @{
                    Name = 'e7852992f40eb619.mod_bundle';
                    Sha256 = 'e1a04e500f8255ebedcaffb4e35e829adbd99ebf46c2b8b4cd89d26dca4735e2';
                    Reason = 'SDK tool-only BUNDLE=false LUT-generator sidecar emitted by clean Stingray builds'
                }
            )
        }
        @{ Dir = 'chaos_wastes_tweaker';       ModId = 'ct';                         WorkshopId = '3712929235'; Visibility = 'public';       Stream = 'stable'; Public = $true;  Name = 'Chaos Wastes Tweaker'; RootBundle = 'c37627d549d8ce88.mod_bundle' }
        @{ Dir = 'chaos_wastes_tweaker_dev';   ModId = 'ct_dev';                     WorkshopId = '3733366926'; Visibility = 'friends_only'; Stream = 'dev';    Public = $false; Name = 'Chaos Wastes Tweaker (Dev)'; RootBundle = '195af59fc68656a5.mod_bundle' }
        @{ Dir = 'general_tweaker';            ModId = 'gt';                         WorkshopId = '3713619122'; Visibility = 'public';       Stream = 'stable'; Public = $true;  Name = 'General Tweaker'; RootBundle = '73ac92d9c37dbb6c.mod_bundle' }
        @{ Dir = 'general_tweaker_dev';        ModId = 'gt_dev';                     WorkshopId = '3733367409'; Visibility = 'friends_only'; Stream = 'dev';    Public = $false; Name = 'General Tweaker (Dev)'; RootBundle = 'e6ffaaca2a71199e.mod_bundle' }
        @{ Dir = 'gui_tweaker';                ModId = 'gut';                        WorkshopId = '3732144878'; Visibility = 'friends_only'; Stream = 'stable'; Public = $false; Name = 'GUI Tweaker'; RootBundle = 'ff654aa303c38f8c.mod_bundle' }
        @{ Dir = 'gui_tweaker_dev';            ModId = 'gut_dev';                    WorkshopId = '3751024698'; Visibility = 'friends_only'; Stream = 'dev';    Public = $false; Name = 'GUI Tweaker (Dev)'; RootBundle = '0e89c5285caab001.mod_bundle' }
        @{ Dir = 'cosmetics_tweaker';          ModId = 'cosmetics_tweaker';          WorkshopId = '3715714222'; Visibility = 'public';       Stream = 'single'; Public = $true;  Name = 'Cosmetics Tweaker'; RootBundle = '6448e4de51a26af1.mod_bundle' }
        @{ Dir = 'dynamic_cosmetic_portraits'; ModId = 'dynamic_cosmetic_portraits'; WorkshopId = '3721036701'; Visibility = 'friends_only'; Stream = 'single'; Public = $false; Name = 'Dynamic Cosmetic Portraits'; RootBundle = '4b0d338589a2926c.mod_bundle' }
        @{ Dir = 'career_tweaker';             ModId = 'crt';                        WorkshopId = '3716286199'; Visibility = 'public';       Stream = 'single'; Public = $true;  Name = 'Career Tweaker'; RootBundle = '92ad046507348beb.mod_bundle' }
        @{ Dir = 'enemy_tweaker';              ModId = 'enemy_tweaker';              WorkshopId = '3716780252'; Visibility = 'friends_only'; Stream = 'single'; Public = $false; Name = 'Enemy Tweaker'; RootBundle = '002586295f98ba25.mod_bundle' }
        @{
            Dir = 'character_weapon_variants'; ModId = 'character_weapon_variants'; WorkshopId = '3716869446';
            Visibility = 'public'; Stream = 'single'; Public = $true;
            Name = 'Character Weapon Variants'; RootBundle = '0f038849957ad1b7.mod_bundle';
            BuildArtifactExclusions = @(
                @{
                    Name = 'e7852992f40eb619.mod_bundle';
                    Sha256 = 'e1a04e500f8255ebedcaffb4e35e829adbd99ebf46c2b8b4cd89d26dca4735e2';
                    Reason = 'SDK tool-only BUNDLE=false LUT-generator sidecar emitted by clean Stingray builds'
                }
            )
        }
        @{ Dir = 'character_dialogue';         ModId = 'character_dialogue';         WorkshopId = '3765055148'; Visibility = 'friends_only'; Stream = 'single'; Public = $false; Name = 'Character Dialogue'; RootBundle = '0e14765f298dd165.mod_bundle' }
        @{ Dir = 'crafting_in_modded';         ModId = 'cim';                        WorkshopId = '3721038774'; Visibility = 'public';       Stream = 'stable'; Public = $true;  Name = 'Crafting In Modded'; RootBundle = 'cfd4add911f06fa1.mod_bundle' }
        @{ Dir = 'crafting_in_modded_dev';     ModId = 'cim_dev';                    WorkshopId = '3733366851'; Visibility = 'friends_only'; Stream = 'dev';    Public = $false; Name = 'Crafting In Modded (Dev)'; RootBundle = '05f34d542fe9a8ef.mod_bundle' }
        @{ Dir = 'event_tweaker';              ModId = 'event_tweaker';              WorkshopId = '3721290755'; Visibility = 'public';       Stream = 'single'; Public = $true;  Name = 'Event Tweaker'; RootBundle = 'ac2d7655ddc4f658.mod_bundle' }
        @{ Dir = 'modded_progression';         ModId = 'mp';                         WorkshopId = '3730422873'; Visibility = 'private';      Stream = 'single'; Public = $false; Name = 'Modded Progression'; RootBundle = 'c30cf98443ecafec.mod_bundle' }
        @{ Dir = 'verminious_dreams_lighting'; ModId = 'verminious_dreams_lighting'; WorkshopId = '3727221800'; Visibility = 'public';       Stream = 'stable'; Public = $true;  Name = 'Verminious Dreams Lighting'; RootBundle = '9acd667c38b63afe.mod_bundle' }
        @{ Dir = 'verminious_dreams_lighting_dev'; ModId = 'verminious_dreams_lighting_dev'; WorkshopId = '3733366748'; Visibility = 'friends_only'; Stream = 'dev'; Public = $false; Name = 'Verminious Dreams Lighting (Dev)'; RootBundle = '6b34ac1c97e5a1be.mod_bundle' }
        @{ Dir = 'weapons_of_chaos';           ModId = 'WOC';                        WorkshopId = '3753880932'; Visibility = 'friends_only'; Stream = 'single'; Public = $false; Name = 'Weapons of Chaos'; RootBundle = 'dcea08518941f940.mod_bundle' }
    )
}
