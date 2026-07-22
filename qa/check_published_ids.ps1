#requires -Version 5
<#
.SYNOPSIS
  Verifies every VT2 mod's itemV2.cfg `published_id` is (1) UNIQUE across all
  mods and (2) matches its CANONICAL Steam Workshop ID.

.WHY
  2026-06-19 incident: gui_tweaker's itemV2.cfg carried general_tweaker_dev's
  published_id (3733367409). Because the launcher uploads to whatever
  published_id the cfg names, every `upload gui_tweaker` HIJACKED gt_dev's
  Workshop item - overwriting "Tweaker: General (dev)" with "Tweaker: GUI".
  Result: gt_dev went missing and two "Tweaker: GUI" items appeared. A single
  wrong number in one cfg silently clobbers a published mod on every upload.

  This check makes that impossible to ship: a duplicate or mismatched
  published_id fails the build (exit 1). Wired into qa/run_all.ps1 and the
  pre-commit hook, and MUST be run before any Workshop upload.

.USAGE
  pwsh -File qa/check_published_ids.ps1          # exit 0 = clean, 1 = error
#>
param([string]$Root = (Split-Path $PSScriptRoot -Parent))

# Canonical mod-directory -> Steam Workshop published_id. SOURCE OF TRUTH.
# Cross-checked against vermintide-2-tweaker/CLAUDE.md "Mod Directory" table.
# When you publish a NEW Workshop item, add its dir + id here IN THE SAME COMMIT
# that introduces the cfg - an unknown cfg is a WARN, a wrong/dupe id is a FAIL.
$Canonical = [ordered]@{
    'weapon_tweaker'                 = '3712896117'  # Tweaker: Weapons
    'chaos_wastes_tweaker'           = '3712929235'  # Tweaker: Chaos Wastes (stable)
    'general_tweaker'                = '3713619122'  # Tweaker: General (stable)
    'cosmetics_tweaker'              = '3715714222'  # Tweaker: Cosmetics
    'career_tweaker'                 = '3716286199'  # Tweaker: Careers
    'enemy_tweaker'                  = '3716780252'  # Tweaker: Enemies
    'character_weapon_variants'      = '3716869446'  # Character Weapon Variants
    'character_dialogue'             = '3765055148'  # Character Dialogue
    'dynamic_cosmetic_portraits'     = '3721036701'  # Dynamic Cosmetic Portraits
    'crafting_in_modded'             = '3721038774'  # Crafting in Modded (stable)
    'event_tweaker'                  = '3721290755'  # Tweaker: Events
    'verminious_dreams_lighting'     = '3727221800'  # Verminious Dreams Lighting (stable)
    'modded_progression'             = '3730422873'  # Modded Progression
    'gui_tweaker'                    = '3732144878'  # Tweaker: GUI
    'verminious_dreams_lighting_dev' = '3733366748'  # Verminious Dreams Lighting (dev)
    'crafting_in_modded_dev'         = '3733366851'  # Crafting in Modded (dev)
    'chaos_wastes_tweaker_dev'       = '3733366926'  # Tweaker: Chaos Wastes (dev)
    'general_tweaker_dev'            = '3733367409'  # Tweaker: General (dev)
    'weapon_tweaker_dev'             = '3748824853'  # Tweaker: Weapons (dev)
    'gui_tweaker_dev'                = '3751024698'  # Tweaker: GUI (dev)
    'weapons_of_chaos'               = '3753880932'  # Weapons of Chaos
}

$fail = 0
$seen = @{}   # published_id -> first mod dir that used it

Get-ChildItem $Root -Directory | Sort-Object Name | ForEach-Object {
    $dir = $_.Name
    $cfg = Join-Path $_.FullName 'itemV2.cfg'
    if (-not (Test-Path $cfg)) { return }

    $m = Select-String -Path $cfg -Pattern 'published_id\s*=\s*(\d+)' | Select-Object -First 1
    $id = if ($m) { $m.Matches[0].Groups[1].Value } else { $null }
    $t  = Select-String -Path $cfg -Pattern 'title\s*=\s*"([^"]+)"' | Select-Object -First 1
    $title = if ($t) { ($t.Matches[0].Groups[1].Value -replace ' v[0-9].*$','') } else { '(no title)' }

    if (-not $id) {
        Write-Host "  WARN  $dir : itemV2.cfg has no published_id (unpublished?)" -ForegroundColor Yellow
        return
    }

    # (1) Duplicate published_id across mods = HIJACK on upload.
    if ($seen.ContainsKey($id)) {
        Write-Host "  FAIL  COLLISION: '$dir' and '$($seen[$id])' BOTH use published_id $id -- every upload of one HIJACKS the other's Workshop item!" -ForegroundColor Red
        $script:fail++
    } else {
        $seen[$id] = $dir
    }

    # (2) published_id must match the canonical for this mod dir.
    if ($Canonical.Contains($dir)) {
        if ($id -ne $Canonical[$dir]) {
            Write-Host "  FAIL  $dir ($title): published_id is $id but canonical is $($Canonical[$dir])" -ForegroundColor Red
            $script:fail++
        }
    } else {
        Write-Host "  WARN  $dir ($title): cfg published_id $id is NOT in the canonical map -- add it to qa/check_published_ids.ps1 in this commit." -ForegroundColor Yellow
    }
}

if ($fail -gt 0) {
    Write-Host "[check_published_ids] FAILED: $fail published_id error(s). DO NOT UPLOAD until fixed (a wrong id hijacks another mod's Workshop item)." -ForegroundColor Red
    exit 1
}
Write-Host "[check_published_ids] PASS - all published_ids unique and canonical." -ForegroundColor Green
exit 0
