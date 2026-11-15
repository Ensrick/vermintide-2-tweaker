#requires -Version 7
<#
.SYNOPSIS
  Host-side reading of a finished rig run's console log for the backend write shield (WP-H-14).

.DESCRIPTION
  Default host_forbid_log while the shield is on (-ShieldOn): the game's own request log
  ("[PlayFabRequestQueue] Enqueuing ExecuteCloudScript request <name> <id>",
  Vermintide-2-Source-Code/scripts/managers/backend_playfab/playfab_request_queue.lua:49) must not show an
  updateHeroAttributes request, and no line may name UpdateUserData. Matching is case-sensitive and skips the
  driver's own [vt2t:] evidence lines, which name requests the shield saw. A plan with backend_shield false runs
  without -ShieldOn and so without these defaults.
  Also reports whether the driver's "SHIELD installed" line comes before the game's first _commit_internal line.

.OUTPUTS
  [pscustomobject] ForbidHits (list of @{ rule; line }), ShieldInstalledBeforeFirstCommit (true, false,
  'no commit in log', or $null when the shield line is absent).
#>
[CmdletBinding()]
param(
    [string] $Text = '',
    [Parameter(Mandatory)] [string] $Nonce,
    [switch] $ShieldOn
)
$ErrorActionPreference = 'Stop'

$rules = [ordered]@{}
if ($ShieldOn) {
    $rules['shield: updateHeroAttributes request'] = '(?m)^(?!.*\[vt2t:).*Enqueuing ExecuteCloudScript request\s+updateHeroAttributes\b.*$'
    $rules['shield: UpdateUserData request'] = '(?m)^(?!.*\[vt2t:).*UpdateUserData.*$'
}
$hits = [System.Collections.Generic.List[object]]::new()
foreach ($rule in $rules.Keys) {
    $hit = [regex]::Match($Text, $rules[$rule])
    if ($hit.Success) { $hits.Add([ordered]@{ rule = $rule; line = $hit.Value.Trim() }) }
}

$shieldAt = [regex]::Match($Text, '\[vt2t:' + [regex]::Escape($Nonce) + '\] SHIELD installed')
$commitAt = [regex]::Match($Text, '_commit_internal')
$order = $null
if ($shieldAt.Success -and $commitAt.Success) { $order = $shieldAt.Index -lt $commitAt.Index }
elseif ($shieldAt.Success) { $order = 'no commit in log' }

[pscustomobject]@{
    ForbidHits                       = $hits.ToArray()
    ShieldInstalledBeforeFirstCommit = $order
}
