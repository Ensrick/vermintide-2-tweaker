# Bulk-extract all VT2 game bundles to a single directory for future reference.
# Output filenames are hash-named where the dictionary has no entry, or real
# paths (e.g. items_atlas.texture) where the dictionary resolves them.
#
# Long-running (~80 min for ~4660 bundles). Run in background with:
#   pwsh -File extract_all_bundles.ps1
#
# Progress is logged to extract_log.txt next to the output dir.

$ErrorActionPreference = 'Continue'

$unpacker  = "C:\Tools\vt2_bundle_unpacker\target\release\unpacker.exe"
$dict      = "C:\Users\danjo\source\repos\vt2_bundle_unpacker\dictionary.csv"
$bundleDir = "C:\Program Files (x86)\Steam\steamapps\common\Warhammer Vermintide 2\bundle"
$outDir    = "D:\Game Mods\Vermintide 2 modding\VT2 Bundle Extract"
$logFile   = "D:\Game Mods\Vermintide 2 modding\extract_log.txt"

New-Item -ItemType Directory -Force -Path $outDir | Out-Null
"" | Out-File $logFile -Encoding utf8

function Log([string]$msg) {
    $line = "[{0:HH:mm:ss}] {1}" -f (Get-Date), $msg
    Write-Output $line
    Add-Content -Path $logFile -Value $line -Encoding utf8
}

$bundles = Get-ChildItem $bundleDir -File | Where-Object { $_.Name -notmatch '\.stream$|\.data$|\.dictionary$' } | Sort-Object Name
$total = $bundles.Count
Log "Starting extraction of $total bundles -> $outDir"

$i = 0
$errors = 0
$startTime = Get-Date
foreach ($b in $bundles) {
    $i++
    if ($i % 100 -eq 0) {
        $elapsed = (Get-Date) - $startTime
        $rate = $i / $elapsed.TotalSeconds
        $eta = [TimeSpan]::FromSeconds(($total - $i) / $rate)
        Log ("[$i/$total] errors=$errors  rate={0:N2}/s  ETA={1:hh\:mm\:ss}" -f $rate, $eta)
    }
    & $unpacker --dict $dict extract $b.FullName $outDir 2>$null
    if ($LASTEXITCODE -ne 0) {
        $errors++
    }
}

$elapsed = (Get-Date) - $startTime
Log ("Done. $total bundles extracted, $errors errors, total time {0:hh\:mm\:ss}" -f $elapsed)
Log ("Output: $outDir")

# Check if items_atlas was resolved
$itemsAtlas = Get-ChildItem $outDir -Filter "items_atlas.*" -Recurse -ErrorAction SilentlyContinue
if ($itemsAtlas) {
    Log "items_atlas found:"
    foreach ($f in $itemsAtlas) { Log "  $($f.FullName)" }
} else {
    Log "items_atlas NOT FOUND in output (its hash 051CE3C36B766BA5 may have collided or not been dictionary-resolved)"
}
