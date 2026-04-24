param(
    [string[]]$Mods = @("chaos_wastes_tweaker", "weapon_tweaker")
)

$sdk = 'C:\Program Files (x86)\Steam\steamapps\common\Vermintide 2 SDK\ugc_uploader'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path

Set-Location $sdk

foreach ($mod in $Mods) {
    $cfg = Join-Path $root "$mod\upload\item.cfg"
    if (-not (Test-Path $cfg)) {
        Write-Warning "Upload config not found for $mod at $cfg — skipping"
        continue
    }

    # Stage into SDK sample_item
    $staging = Join-Path $sdk 'sample_item'
    Remove-Item "$staging\content\*" -Force -ErrorAction SilentlyContinue
    Copy-Item (Join-Path $root "$mod\upload\content\*") "$staging\content\" -Force
    Copy-Item (Join-Path $root "$mod\upload\preview.jpg") "$staging\preview.jpg" -Force
    Copy-Item $cfg "$staging\item.cfg" -Force

    Write-Host "`n=== Uploading $mod ===" -ForegroundColor Cyan
    'Y' | & .\ugc_tool.exe -c sample_item\item.cfg -x
    Write-Host ""
}
