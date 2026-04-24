# upload_ct.ps1 — Upload Chaos Wastes Tweaker to Steam Workshop
# Uses the proven SDK staging method (see ANTIGRAVITY.md)
$sdk  = 'C:\Program Files (x86)\Steam\steamapps\common\Vermintide 2 SDK\ugc_uploader'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$mod  = Join-Path $root 'chaos_wastes_tweaker\upload'

$staging = Join-Path $sdk 'sample_item'

# Stage content into SDK sample_item
Remove-Item "$staging\content\*" -Force -ErrorAction SilentlyContinue
Copy-Item "$mod\content\*" "$staging\content\" -Force
Copy-Item "$mod\preview.jpg" "$staging\preview.jpg" -Force
Copy-Item "$mod\item.cfg" "$staging\item.cfg" -Force

Write-Host "Staged chaos_wastes_tweaker into SDK sample_item:" -ForegroundColor Cyan
Get-ChildItem "$staging\content" | ForEach-Object { Write-Host "  $($_.Name)  ($($_.Length) bytes)" }

# Upload
Set-Location $sdk
'Y' | & .\ugc_tool.exe -c sample_item\item.cfg -x
