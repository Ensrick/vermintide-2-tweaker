# Find large block comments and other dead-code smells
param([string]$Root = "C:\Users\danjo\source\repos\vermintide-2-tweaker")

$mods = @('buff_tweaker','career_tweaker','chaos_wastes_tweaker','character_weapon_variants','cosmetics_tweaker','crafting_in_modded','dynamic_cosmetic_portraits','enemy_tweaker','event_tweaker','general_tweaker','lobby_tweaker','material_hijack_patched','modded_progression','verminious_dreams_lighting','weapon_tweaker')

$results = @()

foreach ($mod in $mods) {
    $dir = Join-Path $Root "$mod\scripts\mods\$mod"
    if (-not (Test-Path $dir)) { continue }
    $files = Get-ChildItem $dir -File -Filter '*.lua' | Where-Object { $_.Name -notmatch '\.processed$' -and $_.Name -notmatch '_localization\.lua$' -and $_.Name -notmatch '_data\.lua$' }
    foreach ($f in $files) {
        $lines = [System.IO.File]::ReadAllLines($f.FullName)
        $inBlock = $false
        $blockStart = -1
        for ($i=0; $i -lt $lines.Length; $i++) {
            $line = $lines[$i]
            if (-not $inBlock) {
                if ($line -cmatch '--\[\[') {
                    $inBlock = $true
                    $blockStart = $i
                    if ($line -cmatch '\]\]') {
                        $inBlock = $false
                    }
                }
            } else {
                if ($line -cmatch '\]\]') {
                    $inBlock = $false
                    $size = $i - $blockStart + 1
                    if ($size -ge 20) {
                        $excerpt = $lines[$blockStart].Trim()
                        if ($excerpt.Length -gt 100) { $excerpt = $excerpt.Substring(0, 100) }
                        $results += [PSCustomObject]@{
                            Mod = $mod
                            File = $f.Name
                            StartLine = $blockStart + 1
                            EndLine = $i + 1
                            Lines = $size
                            FirstLine = $excerpt
                        }
                    }
                }
            }
        }
    }
}

$results | Sort-Object -Property Lines -Descending | Format-Table -AutoSize | Out-String -Width 350
Write-Output ("TOTAL: " + $results.Count)
