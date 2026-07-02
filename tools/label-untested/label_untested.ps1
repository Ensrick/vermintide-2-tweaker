param(
    [Parameter(Mandatory=$true)][string]$DataFile,
    [Parameter(Mandatory=$true)][string]$LocFile,
    [switch]$DryRun
)

$enc  = New-Object System.Text.UTF8Encoding $false
$data = [System.IO.File]::ReadAllText($DataFile)
$loc  = [System.IO.File]::ReadAllText($LocFile)

# Extract (setting_id, type) pairs -- in these data files `type` is always the
# line immediately after `setting_id`. Label keys = non-group widgets only.
# Meta-utilities that are not gameplay features to test/promote -> never labeled.
$skip = @('enable_debug_logging')

$pairs = [regex]::Matches($data, 'setting_id\s*=\s*"([^"]+)"\s*,?\s*type\s*=\s*"([^"]+)"')
$labelKeys = @()
foreach ($m in $pairs) {
    if ($m.Groups[2].Value -ne 'group' -and $skip -notcontains $m.Groups[1].Value) {
        $labelKeys += $m.Groups[1].Value
    }
}
$labelKeys = $labelKeys | Select-Object -Unique

$count = 0
$hit = @()
foreach ($k in $labelKeys) {
    $esc = [regex]::Escape($k)
    # Anchor at line start; skip if value already starts with `[` (idempotent).
    # Two loc-entry forms: table `KEY = { en = "` and helper `KEY = en("`.
    $patTable  = '(?m)^(\s*' + $esc + '\s*=\s*\{\s*en\s*=\s*")(?!\[)'
    $patHelper = '(?m)^(\s*' + $esc + '\s*=\s*en\(")(?!\[)'
    $new = [regex]::Replace($loc, $patTable, '${1}[untested] ')
    if ($new -eq $loc) { $new = [regex]::Replace($loc, $patHelper, '${1}[untested] ') }
    if ($new -ne $loc) { $count++ ; $hit += $k ; $loc = $new }
}

$leaf = Split-Path $LocFile -Leaf
if ($DryRun) {
    Write-Output ("DRYRUN {0}: would label {1} of {2} non-group widgets" -f $leaf, $count, $labelKeys.Count)
    Write-Output ("  first: " + (($hit | Select-Object -First 4) -join ', '))
    Write-Output ("  last:  " + (($hit | Select-Object -Last 4) -join ', '))
    $miss = $labelKeys | Where-Object { $hit -notcontains $_ }
    if ($miss.Count -gt 0) { Write-Output ("  NO LOC MATCH (" + $miss.Count + "): " + (($miss | Select-Object -First 8) -join ', ')) }
} else {
    [System.IO.File]::WriteAllText($LocFile, $loc, $enc)
    Write-Output ("{0}: labeled {1} of {2} non-group widgets" -f $leaf, $count, $labelKeys.Count)
}
