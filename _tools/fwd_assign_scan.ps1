# Scan: `_foo = function` (bare assignment, not `local`) — must have a `local _foo` decl earlier in scope.
param([string]$Root = "C:\Users\danjo\source\repos\vermintide-2-tweaker")

$mods = @('buff_tweaker','career_tweaker','chaos_wastes_tweaker','character_weapon_variants','cosmetics_tweaker','crafting_in_modded','dynamic_cosmetic_portraits','enemy_tweaker','event_tweaker','general_tweaker','lobby_tweaker','material_hijack_patched','modded_progression','verminious_dreams_lighting','weapon_tweaker')

$results = @()

foreach ($mod in $mods) {
    $dir = Join-Path $Root "$mod\scripts\mods\$mod"
    if (-not (Test-Path $dir)) { continue }
    $files = Get-ChildItem $dir -File -Filter '*.lua' | Where-Object { $_.Name -notmatch '\.processed$' -and $_.Name -notmatch '_localization\.lua$' -and $_.Name -notmatch '_data\.lua$' }
    foreach ($f in $files) {
        $lines = [System.IO.File]::ReadAllLines($f.FullName)
        # find all `<bare>_foo = function` assignments at start of line (not preceded by `local`, not `mod._foo`)
        $assigns = @{}
        for ($i=0; $i -lt $lines.Length; $i++) {
            if ($lines[$i] -cmatch '^\s*(_\w+)\s*=\s*function\b') {
                $name = $matches[1]
                $assigns[$name] = $i
            }
        }
        # find all `local _foo` forward decls (no = no function no ()
        $fwd = @{}
        for ($i=0; $i -lt $lines.Length; $i++) {
            $line = $lines[$i]
            $cmt = $line.IndexOf('--')
            if ($cmt -ge 0) { $line = $line.Substring(0, $cmt) }
            if ($line -cmatch '^\s*local\s+(.+)$' -and $line -notmatch '=' -and $line -notmatch 'function' -and $line -notmatch '\(') {
                $names = $matches[1] -split '\s*,\s*'
                foreach ($n in $names) {
                    $n = $n.Trim()
                    if ($n -cmatch '^_\w+$') { $fwd[$n] = $i }
                }
            }
        }
        # for each `_foo = function`, check there's a forward decl earlier
        foreach ($name in $assigns.Keys) {
            $assignLine = $assigns[$name]
            if (-not $fwd.ContainsKey($name) -or $fwd[$name] -ge $assignLine) {
                # is this used ABOVE the assignment? if so, it's a bug
                $usedAbove = $false
                $useLine = -1
                for ($i=0; $i -lt $assignLine; $i++) {
                    $line = $lines[$i]
                    $cmtIdx = $line.IndexOf('--')
                    if ($cmtIdx -ge 0) { $line = $line.Substring(0, $cmtIdx) }
                    $line = $line -replace '"[^"]*"', ''
                    $line = $line -replace "'[^']*'", ''
                    if ($line -cmatch "(?<![A-Za-z0-9_\.])$([regex]::Escape($name))(?![A-Za-z0-9_])") {
                        $usedAbove = $true
                        $useLine = $i + 1
                        break
                    }
                }
                $sev = if ($usedAbove) { "BUG" } else { "GLOBAL" }
                $results += [PSCustomObject]@{
                    Mod = $mod
                    File = $f.Name
                    Symbol = $name
                    AssignLine = $assignLine + 1
                    UseLine = $useLine
                    Severity = $sev
                }
            }
        }
    }
}

$results | Format-Table -AutoSize | Out-String -Width 300
Write-Output ("TOTAL: " + $results.Count)
