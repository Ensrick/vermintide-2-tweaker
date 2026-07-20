# Shared GitHub lifecycle-method policy.
#
# This file is function-only so audit, playtest generation, and ship automation
# consume one method-selection contract. Keep the explicit-heading/correction
# behavior in lockstep with the regression coverage added by PR #908.

function Test-VtExplicitMethodComment {
    param([string]$Body)
    if ([string]::IsNullOrWhiteSpace($Body)) { return $false }
    return $Body -match '(?im)^\s*(?:#{1,6}\s+)?(?:\*\*)?(?:' +
        'test\s+method\b|' +
        '(?:diagnostic|verification)\s+method\b|' +
        '(?:solo|co-?op|two-player)\s+verification\s*(?:\([^\r\n)]*\))?\s*:|' +
        'verification\s*\([^\r\n)]*\)\s*:|' +
        'verification\s+still\s+required\b|' +
        '(?:authoritative|current|corrected|replacement|next)\b[^\r\n]{0,100}\b(?:method|test)\b' +
        ')'
}

function Get-VtMethodComment {
    param($Comments)
    if (-not $Comments -or @($Comments).Count -eq 0) { return $null }
    $arr = @($Comments)
    for ($i = $arr.Count - 1; $i -ge 0; $i--) {
        $b = [string]$arr[$i].body
        if (Test-VtExplicitMethodComment $b) { return $b }
    }

    $best = $null; $bestScore = 0
    for ($i = $arr.Count - 1; $i -ge 0; $i--) {
        $b = [string]$arr[$i].body
        if ([string]::IsNullOrWhiteSpace($b)) { continue }
        $score = 0
        if ($b -match '(?i)test\s+method')                                   { $score += 5 }
        if ($b -cmatch '\bTEST\b')                                           { $score += 4 }
        if ($b -match '(?i)test\s+(with|as|in|solo|\()')                     { $score += 3 }
        if ($b -match '(?i)to\s+verify|verify\s+(that|in-?game|by|each|the|no|this|it)') { $score += 2 }
        if ($b -match '(?i)pass\s*(?:=|:)')                                  { $score += 3 }
        if ($b -match '(?i)expected\s*:')                                    { $score += 2 }
        $steps = ([regex]::Matches($b, '(?m)^\s*\d+\.\s')).Count
        if ($steps -ge 2) { $score += [math]::Min($steps, 4) }
        if ($b -match '\[[a-z][a-z0-9_]*:[A-Za-z0-9_.\-]+\]')                { $score += 1 }
        if ($b -match '(?i)verify-fix\s+(was|label|set|stripped|re-?appl|applied|added|removed)') { $score -= 6 }
        if ($b -match '(?i)^\s*(cross-?ref|xref|x-ref|re-?applying|label sweep|status sweep|reapplying)') { $score -= 5 }
        if ($b.Length -lt 50) { $score -= 2 }
        if ($score -gt $bestScore) { $bestScore = $score; $best = $b }
    }
    if ($bestScore -ge 3) { return $best }
    return $null
}

function Get-VtMethodCorrection {
    param($Comments, [string]$Method)
    if (-not $Comments -or [string]::IsNullOrWhiteSpace($Method)) { return $null }
    $arr = @($Comments)
    $methodIndex = -1
    for ($i = $arr.Count - 1; $i -ge 0; $i--) {
        if ([string]$arr[$i].body -ceq $Method) { $methodIndex = $i; break }
    }
    if ($methodIndex -lt 0) { return $null }
    for ($i = $arr.Count - 1; $i -gt $methodIndex; $i--) {
        $b = [string]$arr[$i].body
        if ($b -match '(?im)^\s*(?:#{1,6}\s+)?(?:verification\s+banner|current\s+deployed-floor)\s+correction\b') {
            return $b
        }
    }
    return $null
}

function Get-VtCorrectionVersion {
    param([string]$Correction)
    if ([string]::IsNullOrWhiteSpace($Correction)) { return $null }
    if ($Correction -match '(?im)^\s*\|\s*Stream\s*\|') { return $null }
    $versions = @([regex]::Matches($Correction, '(?i)\bv?(\d+\.\d+\.\d+(?:-[a-z0-9.-]+)?)\b') |
        ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique)
    if ($versions.Count -ge 1) { return $versions[0] }
    return $null
}

function Test-VtMethodHasExpected {
    param([string]$Method)
    if ([string]::IsNullOrWhiteSpace($Method)) { return $false }
    return $Method -match '(?i)expected|pass\s*(?:=|:)|must pass|should pass|result:|\bconfirm\b|\brequire\b.{0,24}\bpass|\bno (?:crash|error|warning|spam|desync)\b'
}

function Test-VtMethodIsRunnable {
    param([string]$Method)
    if ([string]::IsNullOrWhiteSpace($Method)) { return $false }
    return $Method -match '(?im)^\s*\d+\.\s+|(?:^|\b)(?:run|open|launch|load|equip|enter|start|restart|execute|invoke|inspect|compare|reproduce|repeat|click|select|enable|disable|review|confirm|attach)\b'
}

function Get-VtLifecycleMethodSelection {
    param(
        $Comments,
        [string]$Body,
        [switch]$AllowBodyFallback
    )
    $method = Get-VtMethodComment $Comments
    $source = if ($method) { 'comment' } else { 'none' }
    if (-not $method -and $AllowBodyFallback -and (Test-VtExplicitMethodComment $Body)) {
        $method = $Body
        $source = 'body'
    }
    $correction = if ($source -eq 'comment') {
        Get-VtMethodCorrection -Comments $Comments -Method $method
    } else { $null }
    return [PSCustomObject][ordered]@{
        Method = $method
        Source = $source
        Correction = $correction
        CorrectionVersion = Get-VtCorrectionVersion $correction
        HasExpected = Test-VtMethodHasExpected $method
        Runnable = Test-VtMethodIsRunnable $method
        Valid = (-not [string]::IsNullOrWhiteSpace($method)) -and
            (Test-VtMethodHasExpected $method) -and
            (Test-VtMethodIsRunnable $method)
    }
}

function Test-VtMethodRequiresCoop {
    param([string]$Method)
    if ([string]::IsNullOrWhiteSpace($Method)) { return $false }
    if ($Method -match '(?im)^\s*(?:#{1,6}\s+)?(?:\*\*)?(?:authoritative\s+)?solo\s+(?:test|verification)\b') { return $false }
    if ($Method -match '(?im)^\s*(?:#{1,6}\s+)?(?:\*\*)?(?:authoritative\s+)?(?:co-?op|two[ -]player)\s+(?:test|verification|method)\b') { return $true }
    if ($Method -match '(?im)^\s*(?:#{1,6}\s+)?(?:\*\*)?(?:(?:corrected|authoritative|replacement|current)\s+)?(?:test|diagnostics?|verification) method\s*\(\s*solo\b[^)\r\n]{0,80}\)') { return $false }
    if ($Method -match '(?im)^\s*(?:#{1,6}\s+)?(?:\*\*)?(?:(?:corrected|authoritative|replacement|current)\s+)?(?:test|diagnostics?|verification) method\s*\(\s*(?:co-?op\b|two[ -]players?\b)[^)\r\n]{0,80}\)') { return $true }
    if ($Method -match '(?i)verify solo|solo verification|no (?:second|2nd) player|do(?:es)? not require (?:a )?(?:second|2nd) player|co-?op (?:is )?not required|\b(?:one|1) tester\b') { return $false }
    return $Method -match '(?i)two[ -]players?\b|two[^\r\n]{0,40}(?:players|testers|humans)|2\+? (?:players|testers|humans)|needs? 2 (?:players|testers|humans)|host\s*\+\s*client|host and client|host plus one|second player|both peers|remote peer|non-mod peer|co-?op(?:/perspective)? (?:verification|diagnostics?|retest)'
}

function Test-VtFailedVerificationEvidence {
    param([string]$Method)
    if ([string]::IsNullOrWhiteSpace($Method)) { return $false }
    return $Method -match '(?i)(?:verification|retest|test)\s+(?:failed|still fails)|(?:still|again)\s+(?:broken|crash(?:es|ed)?|fails?|reproduc(?:es|ed|ible))|no\s+(?:change|improvement)|not\s+(?:fixed|working)|persists?\s+(?:after|on|in)\s+(?:the\s+)?(?:deployed|current|tested)'
}

function Test-VtRepositoryOnlyLabels {
    param([string[]]$LabelNames)
    # `documentation` describes content and may accompany runtime regressions
    # (for example #661). Only the explicit `tooling` routing label identifies
    # work that belongs in the autonomous repository queue.
    return $LabelNames -contains 'tooling'
}
