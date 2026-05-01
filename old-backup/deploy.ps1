$out      = 'C:\Users\danjo\source\repos\vermintide-2-tweaker\tweaker\.build\OUT'
$content  = 'C:\Users\danjo\source\repos\vermintide-2-tweaker\upload\content'
$workshop = 'C:\Program Files (x86)\Steam\steamapps\workshop\content\552500\3704660429'

Remove-Item "$content\*" -Force -ErrorAction SilentlyContinue
Copy-Item "$out\tweaker.mod" $content

Get-ChildItem $out -File | Where-Object { $_.Extension -eq '' } | ForEach-Object {
    $dest = Join-Path $content ($_.Name + '.mod_bundle')
    Copy-Item $_.FullName $dest
}

New-Item -ItemType Directory -Force -Path $workshop | Out-Null
Remove-Item "$workshop\*" -Force -ErrorAction SilentlyContinue
Copy-Item "$content\*" $workshop -Force

Write-Host "=== upload\content ==="
Get-ChildItem $content | ForEach-Object { Write-Host "  $($_.Name)  ($($_.Length) bytes)" }
Write-Host "=== workshop ==="
Get-ChildItem $workshop | ForEach-Object { Write-Host "  $($_.Name)  ($($_.Length) bytes)" }
