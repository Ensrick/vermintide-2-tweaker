# Hook variant audit — find mismatches between chosen variant and body behavior.
# Bug classes:
#   A. mod:hook_safe(..., function(self, ...) ... func(...) ... end) — wrong, hook_safe has no func arg
#   B. mod:hook(..., function(func, self, ...) ... end)  where body never calls func(...) — could be hook_safe (but might want to suppress original)
param([string]$Root = "C:\Users\danjo\source\repos\vermintide-2-tweaker")

$mods = @('buff_tweaker','career_tweaker','chaos_wastes_tweaker','character_weapon_variants','cosmetics_tweaker','crafting_in_modded','dynamic_cosmetic_portraits','enemy_tweaker','event_tweaker','general_tweaker','lobby_tweaker','material_hijack_patched','modded_progression','verminious_dreams_lighting','weapon_tweaker')

$results = @()

foreach ($mod in $mods) {
    $dir = Join-Path $Root "$mod\scripts\mods\$mod"
    if (-not (Test-Path $dir)) { continue }
    $files = Get-ChildItem $dir -File -Filter '*.lua' | Where-Object { $_.Name -notmatch '\.processed$' -and $_.Name -notmatch '_localization\.lua$' -and $_.Name -notmatch '_data\.lua$' }
    foreach ($f in $files) {
        $text = [System.IO.File]::ReadAllText($f.FullName)
        $lines = $text -split "`n"
        # find every mod:hook(...) / mod:hook_safe(...) / mod:hook_origin(...) opening
        for ($i=0; $i -lt $lines.Length; $i++) {
            $line = $lines[$i]
            if ($line -cmatch '^\s*mod:(hook|hook_safe|hook_origin)\s*\(') {
                $variant = $matches[1]
                # find matching closing paren by scanning forward and counting parens
                $depth = 0
                $startLine = $i
                $endLine = -1
                $body = @()
                for ($j=$i; $j -lt $lines.Length; $j++) {
                    $bl = $lines[$j]
                    foreach ($ch in $bl.ToCharArray()) {
                        if ($ch -eq '(') { $depth++ }
                        elseif ($ch -eq ')') { $depth-- }
                    }
                    $body += $bl
                    if ($depth -le 0 -and $j -gt $i) { $endLine = $j; break }
                }
                if ($endLine -lt 0) { continue }
                # join body, look at the function( signature
                $bodyText = ($body -join "`n")
                # find the function(...) signature  (could be `function(func, ...)` for hook, `function(self, ...)` for hook_safe/origin)
                if ($bodyText -cmatch 'function\s*\(\s*([^\)]*)\)') {
                    $firstArg = ($matches[1] -split ',')[0].Trim()
                    if ($variant -eq 'hook') {
                        # body should reference firstArg (which by convention is 'func' or similar)
                        # Look for `<firstArg>(` invocation
                        if ($firstArg -ne '' -and $firstArg -ne 'self') {
                            # Direct call: func(...)
                            $callPat = "(?<![A-Za-z0-9_])$([regex]::Escape($firstArg))\s*\("
                            # Indirect via pcall/xpcall: pcall(func, ...) / xpcall(func, ...)
                            $pcallPat = "(?<![A-Za-z0-9_])(?:pcall|xpcall)\s*\(\s*$([regex]::Escape($firstArg))\b"
                            # Returned: return func  /  ret = func  /  local x = func (without call)
                            $refPat = "(?<![A-Za-z0-9_])$([regex]::Escape($firstArg))(?![A-Za-z0-9_\(])"
                            if (-not (($bodyText -cmatch $callPat) -or ($bodyText -cmatch $pcallPat))) {
                                # body never calls func — could be hook_safe (no return) or hook_origin (replace)
                                # determine: if there's a `return ...` (other than `return nil` at end), it might intentionally suppress
                                $hasReturn = $bodyText -cmatch '\breturn\s+\w'
                                $results += [PSCustomObject]@{
                                    Mod = $mod
                                    File = $f.Name
                                    Line = $startLine + 1
                                    Variant = $variant
                                    Issue = "func arg '$firstArg' never invoked"
                                    Recommend = if ($hasReturn) { "hook_origin (replace)" } else { "hook_safe (post-only)" }
                                    Snippet = $lines[$startLine].Trim()
                                }
                            }
                        }
                    }
                    elseif ($variant -eq 'hook_safe') {
                        # body must NOT call any function-arg-like name. If there's a `func(` call, that's the bug.
                        # Look for the firstArg being called or invoked  (rare false positive case)
                        if ($firstArg -ne '' -and $firstArg -cmatch '^func' -and $bodyText -cmatch "(?<![A-Za-z0-9_])$([regex]::Escape($firstArg))\s*\(") {
                            $results += [PSCustomObject]@{
                                Mod = $mod
                                File = $f.Name
                                Line = $startLine + 1
                                Variant = $variant
                                Issue = "first arg '$firstArg' is invoked — hook_safe has no func"
                                Recommend = "hook"
                                Snippet = $lines[$startLine].Trim()
                            }
                        }
                    }
                }
                $i = $endLine
            }
        }
    }
}

$results | Format-Table -Property Mod,File,Line,Variant,Issue,Recommend -AutoSize | Out-String -Width 350
Write-Output ("TOTAL: " + $results.Count)
