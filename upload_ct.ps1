# upload_ct.ps1 - Upload Chaos Wastes Tweaker to Steam Workshop (VMB layout)
# Reads itemV2.cfg directly; PowerShell's & does not pipe stdin reliably for the EULA prompt,
# so we shell out to bash to use `echo y |` (matches the workaround in reference_vmb_new_mod.md).
# REVIEW: This is the only mod whose intended visibility is "public" — see
# feedback_workshop_metadata_user_dictates.md. Therefore no visibility="public" abort guard
# (unlike upload_wt.ps1). Suggestion: add a positive *confirmation* of expected visibility,
# e.g. abort if the cfg has been edited to anything OTHER than "public" — that way an
# unintentional drift to private (or to friends) for this mod is also caught. Currently the
# script will happily upload whatever's there. Optional improvement; not a bug.
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$cfg  = Join-Path $root 'chaos_wastes_tweaker\itemV2.cfg'
$tool = 'C:\Program Files (x86)\Steam\steamapps\common\Vermintide 2 SDK\ugc_uploader\ugc_tool.exe'

if (-not (Test-Path $cfg))  { throw "itemV2.cfg not found at $cfg" }
if (-not (Test-Path $tool)) { throw "ugc_tool.exe not found at $tool" }

# Sanity: make sure the build output exists before uploading
$bundle = Join-Path $root 'chaos_wastes_tweaker\bundleV2'
if (-not (Test-Path $bundle) -or -not (Get-ChildItem $bundle -Filter '*.mod_bundle' -ErrorAction SilentlyContinue)) {
    throw "No bundleV2 output found at $bundle - run VMB build first"
}

Write-Host "Uploading chaos_wastes_tweaker via $tool" -ForegroundColor Cyan
& bash -c "echo y | '$($tool -replace '\\','/')' -c '$($cfg -replace '\\','/')' -x"
