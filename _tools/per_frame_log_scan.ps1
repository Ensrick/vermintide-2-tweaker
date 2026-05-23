# Find mod:info / mod:echo calls inside mod.update closures
param([string]$Root = "C:\Users\danjo\source\repos\vermintide-2-tweaker")

$mods = @('buff_tweaker','career_tweaker','chaos_wastes_tweaker','character_weapon_variants','cosmetics_tweaker','crafting_in_modded','dynamic_cosmetic_portraits','enemy_tweaker','event_tweaker','general_tweaker','la_prefix_patch','lobby_tweaker','material_hijack_patched','modded_progression','verminious_dreams_lighting','weapon_tweaker')

$results = @()

foreach ($mod in $mods) {
    $dir = Join-Path $Root "$mod\scripts\mods\$mod"
    if (-not (Test-Path $dir)) { continue }
    $files = Get-ChildItem $dir -File -Filter '*.lua' | Where-Object { $_.Name -notmatch '\.processed$' -and $_.Name -notmatch '_localization\.lua$' -and $_.Name -notmatch '_data\.lua$' }
    foreach ($f in $files) {
        $lines = [System.IO.File]::ReadAllLines($f.FullName)
        $inUpdate = $false
        $updateStart = -1
        $depth = 0
        for ($i=0; $i -lt $lines.Length; $i++) {
            $line = $lines[$i]
            if (-not $inUpdate -and $line -cmatch 'mod\.update\s*=\s*function\s*\(') {
                $inUpdate = $true
                $updateStart = $i
                $depth = 0
                # count any opens on this line after 'function('
                $afterFn = $line.Substring($line.IndexOf('function'))
                foreach ($ch in $afterFn.ToCharArray()) {
                    if ($ch -eq '(') { $depth++ }
                    elseif ($ch -eq ')') { $depth-- }
                }
                continue
            }
            if ($inUpdate) {
                # track end with `end`
                if ($line -cmatch '^\s*end\b' -and $depth -le 1) {
                    $inUpdate = $false
                    continue
                }
                # also track function() blocks inside
                # use 'function' tokens
                $fnCount = ([regex]::Matches($line, '\bfunction\b')).Count
                $endCount = ([regex]::Matches($line, '\bend\b')).Count
                $depth += $fnCount
                $depth -= $endCount
                if ($depth -le 0) { $inUpdate = $false; continue }
                # check for log calls
                if ($line -cmatch 'mod:(info|echo|warning|error)\s*\(') {
                    $results += [PSCustomObject]@{
                        Mod = $mod
                        File = $f.Name
                        Line = $i + 1
                        Snippet = $line.Trim()
                    }
                }
            }
        }
    }
}

$results | Format-Table -AutoSize | Out-String -Width 350
Write-Output ("TOTAL: " + $results.Count)
