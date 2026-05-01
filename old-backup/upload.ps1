# Legacy Tweaker upload — stages into SDK sample_item and uploads from there
$sdk = 'C:\Program Files (x86)\Steam\steamapps\common\Vermintide 2 SDK\ugc_uploader'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path

# Stage
$staging = Join-Path $sdk 'sample_item'
Remove-Item "$staging\content\*" -Force -ErrorAction SilentlyContinue
Copy-Item "$root\upload\content\*" "$staging\content\" -Force
Copy-Item "$root\upload\preview.jpg" "$staging\preview.jpg" -Force
Copy-Item "$root\upload\item.cfg" "$staging\item.cfg" -Force

# Upload
Set-Location $sdk
'Y' | & .\ugc_tool.exe -c sample_item\item.cfg -x
