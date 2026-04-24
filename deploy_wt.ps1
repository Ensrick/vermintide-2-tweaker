# deploy_wt.ps1 - Deploy Weapon Tweaker build output to upload/content
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$out     = Join-Path $root 'weapon_tweaker\.build\OUT'
$content = Join-Path $root 'weapon_tweaker\upload\content'

if (-not (Test-Path $out)) { throw "Build output not found at $out - run _run_build.bat first" }

New-Item -ItemType Directory -Force -Path $content | Out-Null
Remove-Item "$content\*" -Force -ErrorAction SilentlyContinue

# Copy .mod file
Copy-Item "$out\wt.mod" $content -Force

# Copy bundle files (no extension in build output, add .mod_bundle)
Get-ChildItem $out -File | Where-Object { $_.Extension -eq '' } | ForEach-Object {
    $dest = Join-Path $content ($_.Name + '.mod_bundle')
    Copy-Item $_.FullName $dest -Force
}

Write-Host "=== weapon_tweaker upload/content ==="
Get-ChildItem $content | Format-Table Name, Length -AutoSize
