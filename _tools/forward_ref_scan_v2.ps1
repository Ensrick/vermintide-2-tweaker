# Forward-reference scanner v2 — handles multi-name `local` lines and skips qualified `mod._x` access
param([string]$Root = "C:\Users\danjo\source\repos\vermintide-2-tweaker")

$mods = @('buff_tweaker','career_tweaker','chaos_wastes_tweaker','character_weapon_variants','cosmetics_tweaker','crafting_in_modded','dynamic_cosmetic_portraits','enemy_tweaker','event_tweaker','general_tweaker','lobby_tweaker','material_hijack_patched','modded_progression','verminious_dreams_lighting','weapon_tweaker')

$results = @()

foreach ($mod in $mods) {
    $dir = Join-Path $Root "$mod\scripts\mods\$mod"
    if (-not (Test-Path $dir)) { continue }
    $files = Get-ChildItem $dir -File -Filter '*.lua' | Where-Object { $_.Name -notmatch '\.processed$' -and $_.Name -notmatch '_localization\.lua$' -and $_.Name -notmatch '_data\.lua$' }
    foreach ($f in $files) {
        $lines = [System.IO.File]::ReadAllLines($f.FullName)
        # find all `local function _name` definitions
        $defs = @{}
        for ($i=0; $i -lt $lines.Length; $i++) {
            if ($lines[$i] -match '^\s*local\s+function\s+(_\w+)\s*\(') {
                $name = $matches[1]
                if (-not $defs.ContainsKey($name)) { $defs[$name] = $i }
            }
        }
        # find ALL `local <name1>[, <name2> ...]` forward declarations on a line that does NOT contain `function` or `=`
        $fwd = @{}
        for ($i=0; $i -lt $lines.Length; $i++) {
            $line = $lines[$i]
            # strip trailing comment
            $cmt = $line.IndexOf('--')
            if ($cmt -ge 0) { $line = $line.Substring(0, $cmt) }
            # must start with `local`, no `=`, no `function`, no `(`
            if ($line -match '^\s*local\s+(.+)$' -and $line -notmatch '=' -and $line -notmatch 'function' -and $line -notmatch '\(') {
                $names = $matches[1] -split '\s*,\s*'
                foreach ($n in $names) {
                    $n = $n.Trim()
                    if ($n -match '^_\w+$') { $fwd[$n] = $i }
                }
            }
        }
        # for each `local function _name`, look for references to _name BEFORE its def
        foreach ($name in $defs.Keys) {
            $defLine = $defs[$name]
            # skip if forward-declared earlier
            if ($fwd.ContainsKey($name) -and $fwd[$name] -lt $defLine) { continue }
            # search lines 0..defLine-1 for token reference
            for ($i=0; $i -lt $defLine; $i++) {
                $line = $lines[$i]
                # strip line-comment portion
                $cmtIdx = $line.IndexOf('--')
                if ($cmtIdx -ge 0) { $line = $line.Substring(0, $cmtIdx) }
                # strip string literals (simple double-quote handling)
                $line = $line -replace '"[^"]*"', ''
                $line = $line -replace "'[^']*'", ''
                # word-boundary check for $name BUT NOT preceded by `.` (which would mean `mod._name` field access)
                if ($line -cmatch "(?<![A-Za-z0-9_\.])$([regex]::Escape($name))(?![A-Za-z0-9_])") {
                    $results += [PSCustomObject]@{
                        Mod = $mod
                        File = $f.Name
                        Symbol = $name
                        RefLine = $i + 1
                        DefLine = $defLine + 1
                        RefSnippet = $lines[$i].Trim()
                    }
                    break
                }
            }
        }
    }
}

$results | Format-Table -AutoSize | Out-String -Width 300
Write-Output ("TOTAL: " + $results.Count)
