# MP1684 actual candidate guard; normal Quick check, no gameplay authority.
[CmdletBinding()]
param([string]$RepoRoot,[switch]$Staged,[switch]$Quiet)
$ErrorActionPreference='Stop'
if(-not$RepoRoot){$RepoRoot=Split-Path $PSScriptRoot -Parent}
try{
    . (Join-Path $RepoRoot 'tools/verify/live_test_source_authority.ps1')
    $hosted=[string]$env:GITHUB_ACTIONS -ceq 'true'
    $result=@(Invoke-VtMpLoginCandidateContract -RepoRoot $RepoRoot -Staged:$Staged -Committed:$hosted)
    if(-not$Quiet){
        $active=@($result|Where-Object{$_.Active})
        Write-Host ("[check_mp_login_source_contract] PASS: {0} active of {1} actual source views; no gameplay acceptance." -f $active.Count,$result.Count)
    }
    exit 0
}catch{
    Write-Host ("[check_mp_login_source_contract] FAIL: "+$_.Exception.Message) -ForegroundColor Red
    exit 2
}
