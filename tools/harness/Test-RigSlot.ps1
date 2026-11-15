#requires -Version 7
<#
.SYNOPSIS
  Verifies a staged rig slot folder against its slot.json (WP-H-07 step 3). Nothing is written.

.DESCRIPTION
  slot.json (written by stage-build.ps1) lists every staged file with its SHA-256. The check fails when slot.json
  is missing or unreadable, names another mod than -Mod, a listed file is missing or its hash differs, or the
  folder holds a .mod or .mod_bundle file slot.json does not list (Steam may have restored the published
  placeholder content: re-stage).

.OUTPUTS
  [pscustomobject] Ok, Problems (strings), Info (the parsed slot.json or $null).
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $SlotDir,
    [string] $Mod = ''
)
$ErrorActionPreference = 'Stop'
$problems = [System.Collections.Generic.List[string]]::new()
$info = $null
$json = Join-Path $SlotDir 'slot.json'
if (-not (Test-Path -LiteralPath $SlotDir -PathType Container)) { $problems.Add("slot folder missing: $SlotDir") }
elseif (-not (Test-Path -LiteralPath $json -PathType Leaf)) { $problems.Add("slot.json missing in $SlotDir (stage the build first)") }
else {
    try { $info = [System.IO.File]::ReadAllText($json) | ConvertFrom-Json } catch { $problems.Add("slot.json unreadable: $($_.Exception.Message)") }
}
if ($info) {
    if ($Mod -and [string]$info.mod -ne $Mod) { $problems.Add("slot holds '$($info.mod)', not '$Mod'") }
    $listed = @{}
    foreach ($p in @($info.files.PSObject.Properties)) {
        $listed[$p.Name] = $true
        $path = Join-Path $SlotDir $p.Name
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { $problems.Add("staged file missing: $($p.Name)"); continue }
        $hash = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
        if ($hash -ne [string]$p.Value) { $problems.Add("hash mismatch: $($p.Name)") }
    }
    if ($listed.Count -eq 0) { $problems.Add('slot.json lists no files') }
    foreach ($f in @(Get-ChildItem -LiteralPath $SlotDir -File | Where-Object { $_.Extension -in '.mod', '.mod_bundle' })) {
        if (-not $listed.ContainsKey($f.Name)) { $problems.Add("file not in slot.json: $($f.Name)") }
    }
}
[pscustomobject]@{ Ok = ($problems.Count -eq 0); Problems = $problems.ToArray(); Info = $info }
