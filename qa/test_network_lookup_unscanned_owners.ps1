param(
    [string]$CandidateRoot=(Split-Path $PSScriptRoot -Parent),
    [ValidateSet('green','disabled-validator','shadowed-keys')][string]$Mode='green'
)
$ErrorActionPreference='Stop'
$hosts=@((Get-Command pwsh.exe).Source,(Get-Command powershell.exe).Source)
$utf8=[Text.UTF8Encoding]::new($false,$true)
$parentModulePath=[Environment]::GetEnvironmentVariable('PSModulePath','Process')
$ownedParent=[IO.Path]::GetTempPath()
$ownedRoot=Join-Path $ownedParent ('vt2-issue428-tests-'+[guid]::NewGuid().ToString('N'))
if(Test-Path -LiteralPath $ownedRoot){throw 'owned fixture directory unexpectedly exists'}
[void][IO.Directory]::CreateDirectory($ownedRoot)
$paths=@('weapon_tweaker/scripts/mods/weapon_tweaker/_wt_history_runtime.lua',
    'weapon_tweaker_dev/scripts/mods/weapon_tweaker_dev/_wt_history_runtime.lua')
$control='fixture_other/scripts/mods/fixture_other/heuristic.lua'
$fixtureSource=@'
local function register_private_profiles()
    local lookup_root = rawget(_G, "NetworkLookup")
    local lookup = lookup_root and lookup_root.damage_profiles
'@ + "`n" + ((1..30|ForEach-Object {'    local detached = {}'}) -join "`n") + @'

    local index = #lookup + 1
    rawset(lookup, index, "fixture")
    rawset(lookup, "fixture", index)
end
'@ + "`n"
# A CRLF checkout gives here-string literals CRLF too. Canonicalize this
# detached fixture once before the case that deliberately authors CRLF.
$fixtureSource=$fixtureSource.Replace("`r`n","`n")
function Write-OwnedText([string]$Path,[string]$Text) {
    [void][IO.Directory]::CreateDirectory((Split-Path -Parent $Path))
    [IO.File]::WriteAllText($Path,$Text,$utf8)
}
function Get-NormalizedDigest([string]$Text) {
    $sha=[Security.Cryptography.SHA256]::Create()
    try {return ([BitConverter]::ToString($sha.ComputeHash($utf8.GetBytes($Text.Replace("`r`n","`n"))))).Replace('-','').ToLowerInvariant()}
    finally {$sha.Dispose()}
}
function Get-AppendBlock([string]$Variable,[string]$Axis='damage_profiles') {
    return "do`nlocal $Variable = NetworkLookup.$Axis`nrawset($Variable, #$Variable + 1, 'one')`nrawset($Variable, 'one', #$Variable)`nend`n"
}
function New-Fixture([string]$Root) {
    Write-OwnedText (Join-Path $Root 'tools/mod-inventory.psd1') "@{ Mods=@(@{Dir='weapon_tweaker'},@{Dir='weapon_tweaker_dev'},@{Dir='fixture_other'}) }"
    foreach($path in $paths){Write-OwnedText (Join-Path $Root $path) $fixtureSource}
    Write-OwnedText (Join-Path $Root $control) ((Get-AppendBlock 'a')+(Get-AppendBlock 'b'))
    Write-OwnedText (Join-Path $Root 'baseline.json') ('{"schema":1,"rows":[{"path":"'+$control+'","axis":"damage_profiles","count":2}]}')
    $hash=Get-NormalizedDigest $fixtureSource
    Write-OwnedText (Join-Path $Root 'pins.psd1') ("@{schema=1;issue=428;coverage='explicit-source-pins-not-complete-census';rows=@("+
        "@{path='$($paths[0])';axis='damage_profiles';count=1;sha256='$hash'},"+
        "@{path='$($paths[1])';axis='damage_profiles';count=1;sha256='$hash'})}")
}
function Edit-Pins([string]$Root,[scriptblock]$Edit) {
    $path=Join-Path $Root 'pins.psd1'
    Write-OwnedText $path (& $Edit ([IO.File]::ReadAllText($path)))
}
function Invoke-Gate([string]$HostPath,[string]$Gate,[string]$Root) {
    $psi=[Diagnostics.ProcessStartInfo]::new()
    $psi.FileName=$HostPath;$psi.UseShellExecute=$false;$psi.CreateNoWindow=$true
    $psi.RedirectStandardOutput=$true;$psi.RedirectStandardError=$true
    if($HostPath -match 'System32') {
        # PS7's inherited module search path can hide PS5's native Utility
        # module. Scope its canonical module directory to this child only.
        $psi.EnvironmentVariables['PSModulePath']=Join-Path $env:WINDIR 'System32/WindowsPowerShell/v1.0/Modules'
    }
    $arguments=@('-NoLogo','-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',$Gate,
        '-RepoRoot',$Root,'-BaselinePath',(Join-Path $Root 'baseline.json'),
        '-SupplementalInventoryPath',(Join-Path $Root 'pins.psd1'))
    foreach($argument in $arguments){if($argument.Contains('"') -or $argument.EndsWith('\')){throw 'unsupported owned child argument'}}
    $psi.Arguments=(@($arguments|ForEach-Object {'"'+$_+'"'}) -join ' ')
    $process=[Diagnostics.Process]::Start($psi)
    $output=$process.StandardOutput.ReadToEndAsync();$errorText=$process.StandardError.ReadToEndAsync()
    if(-not $process.WaitForExit(30000)){$process.Kill();throw 'owned gate child exceeded 30 seconds'}
    $result=[pscustomobject]@{exit=$process.ExitCode;text=$output.Result+$errorText.Result}
    $process.Dispose();return $result
}
$cases=@(
    @{name='exact pins and independent counts';exit=0;pattern='(?s)heuristic_detected=2 baseline=2.*pinned_unscanned=2 minimum_known_present=4 global_completeness=unproved';edit={param($r)}},
    @{name='CRLF normalized only';exit=0;pattern='pinned_unscanned=2';edit={param($r) foreach($p in $paths){Write-OwnedText (Join-Path $r $p) ($fixtureSource.Replace("`n","`r`n"))}}},
    @{name='CRCRLF is not normalized away';exit=2;pattern='source drift';edit={param($r) Write-OwnedText (Join-Path $r $paths[0]) ($fixtureSource.Replace("`n","`r`r`n"))}},
    @{name='benign source comment drift';exit=2;pattern='source drift';edit={param($r) Write-OwnedText (Join-Path $r $paths[0]) ($fixtureSource+"-- benign`n")}},
    @{name='missing source is not migration';exit=2;pattern='source missing';edit={param($r) Remove-Item -LiteralPath (Join-Path $r $paths[0])}},
    @{name='empty source';exit=2;pattern='source drift';edit={param($r) Write-OwnedText (Join-Path $r $paths[0]) ''}},
    @{name='invalid source UTF8';exit=2;pattern='GetString|translate';edit={param($r) [IO.File]::WriteAllBytes((Join-Path $r $paths[0]),[byte[]](255,254,255))}},
    @{name='lone CR not normalized';exit=2;pattern='source drift';edit={param($r) Write-OwnedText (Join-Path $r $paths[0]) ($fixtureSource+"`r")}},
    @{name='BOM is not stripped';exit=2;pattern='source drift';edit={param($r) Write-OwnedText (Join-Path $r $paths[0]) ([string][char]0xfeff+$fixtureSource)}},
    @{name='late extra append';exit=2;pattern='source drift';edit={param($r) Write-OwnedText (Join-Path $r $paths[0]) ($fixtureSource+"rawset(lookup, #lookup+1, 'late');rawset(lookup,'late',#lookup)`n")}},
    @{name='root reassignment';exit=2;pattern='source drift';edit={param($r) Write-OwnedText (Join-Path $r $paths[0]) ($fixtureSource.Replace('local lookup =','lookup_root = {}; local lookup ='))}},
    @{name='nested parameter shadow';exit=2;pattern='source drift';edit={param($r) Write-OwnedText (Join-Path $r $paths[0]) ($fixtureSource+"local function nested(lookup) return lookup end`n")}},
    @{name='fake commented anchors';exit=2;pattern='source drift';edit={param($r) Write-OwnedText (Join-Path $r $paths[0]) ($fixtureSource+"--[=[ local lookup=NetworkLookup.damage_profiles ]=]`n")}},
    @{name='wrong schema';exit=2;pattern='schema';edit={param($r) Edit-Pins $r {param($s) $s.Replace('schema=1','schema=2')}}},
    @{name='wrong issue';exit=2;pattern='schema/issue';edit={param($r) Edit-Pins $r {param($s) $s.Replace('issue=428','issue=429')}}},
    @{name='wrong completeness claim';exit=2;pattern='coverage';edit={param($r) Edit-Pins $r {param($s) $s.Replace('explicit-source-pins-not-complete-census','complete')}}},
    @{name='unknown inventory field';exit=2;pattern='schema fields';edit={param($r) Edit-Pins $r {param($s) $s.Replace('@{schema=1','@{extra=1;schema=1')}}},
    @{name='inventory Keys member shadow';exit=2;pattern='schema fields';edit={param($r) Edit-Pins $r {param($s) $s.Replace('@{schema=1',"@{Keys=@('schema','issue','coverage','rows');schema=1")}}},
    @{name='inventory kEyS member shadow';exit=2;pattern='schema fields';edit={param($r) Edit-Pins $r {param($s) $s.Replace('@{schema=1',"@{kEyS=@('schema','issue','coverage','rows');schema=1")}}},
    @{name='inventory get_Keys member shadow';exit=2;pattern='schema fields';edit={param($r) Edit-Pins $r {param($s) $s.Replace('@{schema=1',"@{get_Keys=@('schema','issue','coverage','rows');schema=1")}}},
    @{name='inventory GetEnumerator member shadow';exit=2;pattern='schema fields';edit={param($r) Edit-Pins $r {param($s) $s.Replace('@{schema=1',"@{GetEnumerator=@('schema','issue','coverage','rows');schema=1")}}},
    @{name='inventory PSBase member shadow';exit=2;pattern='schema fields';edit={param($r) Edit-Pins $r {param($s) $s.Replace('@{schema=1',"@{PSBase=@('schema','issue','coverage','rows');schema=1")}}},
    @{name='duplicate manifest key';exit=2;pattern='data|key|Data';edit={param($r) Edit-Pins $r {param($s) $s.Replace('schema=1','schema=1;schema=1')}}},
    @{name='duplicate row';exit=2;pattern='duplicated';edit={param($r) Edit-Pins $r {param($s) $s.Replace($paths[1],$paths[0])}}},
    @{name='missing row not migration';exit=2;pattern='exactly the two';edit={param($r) Edit-Pins $r {param($s) $s.Substring(0,$s.IndexOf(',@{path='))+')}'} }},
    @{name='additional row forbidden';exit=2;pattern='exactly the two';edit={param($r) Edit-Pins $r {param($s) $s.Replace(')}',",@{path='extra';axis='damage_profiles';count=1;sha256='"+('0'*64)+"'})}")}}},
    @{name='unknown row field';exit=2;pattern='schema fields';edit={param($r) Edit-Pins $r {param($s) $s.Replace("axis='damage_profiles'","extra=1;axis='damage_profiles'")}}},
    @{name='row Keys member shadow';exit=2;pattern='schema fields';edit={param($r) Edit-Pins $r {param($s) $s.Replace('@{path=',"@{Keys=@('path','axis','count','sha256');path=")}}},
    @{name='row kEyS member shadow';exit=2;pattern='schema fields';edit={param($r) Edit-Pins $r {param($s) $s.Replace('@{path=',"@{kEyS=@('path','axis','count','sha256');path=")}}},
    @{name='row get_Keys member shadow';exit=2;pattern='schema fields';edit={param($r) Edit-Pins $r {param($s) $s.Replace('@{path=',"@{get_Keys=@('path','axis','count','sha256');path=")}}},
    @{name='row GetEnumerator member shadow';exit=2;pattern='schema fields';edit={param($r) Edit-Pins $r {param($s) $s.Replace('@{path=',"@{GetEnumerator=@('path','axis','count','sha256');path=")}}},
    @{name='row PSBase member shadow';exit=2;pattern='schema fields';edit={param($r) Edit-Pins $r {param($s) $s.Replace('@{path=',"@{PSBase=@('path','axis','count','sha256');path=")}}},
    @{name='foreign path';exit=2;pattern='path/axis';edit={param($r) Edit-Pins $r {param($s) $s.Replace($paths[0],'../foreign.lua')}}},
    @{name='case-shifted path';exit=2;pattern='path/axis';edit={param($r) Edit-Pins $r {param($s) $s.Replace($paths[0],$paths[0].ToUpperInvariant())}}},
    @{name='wrong axis';exit=2;pattern='path/axis';edit={param($r) Edit-Pins $r {param($s) $s.Replace("axis='damage_profiles'","axis='item_names'")}}},
    @{name='count growth forbidden';exit=2;pattern='count/hash';edit={param($r) Edit-Pins $r {param($s) $s.Replace('count=1','count=2')}}},
    @{name='zero count not removal';exit=2;pattern='count/hash';edit={param($r) Edit-Pins $r {param($s) $s.Replace('count=1','count=0')}}},
    @{name='string count';exit=2;pattern='count/hash';edit={param($r) Edit-Pins $r {param($s) $s.Replace('count=1',"count='1'")}}},
    @{name='fractional typed count';exit=2;pattern='count/hash';edit={param($r) Edit-Pins $r {param($s) $s.Replace('count=1','count=1.0')}}},
    @{name='invalid digest';exit=2;pattern='count/hash';edit={param($r) Edit-Pins $r {param($s) $s -replace "sha256='[a-f0-9]+'","sha256='bad'"}}},
    @{name='wrong valid digest';exit=2;pattern='source drift';edit={param($r) Edit-Pins $r {param($s) $s -replace "sha256='[a-f0-9]+'",("sha256='"+('0'*64)+"'")}}},
    @{name='missing inventory';exit=2;pattern='source missing';edit={param($r) Remove-Item -LiteralPath (Join-Path $r 'pins.psd1')}},
    @{name='invalid inventory UTF8';exit=2;pattern='GetString|translate';edit={param($r) [IO.File]::WriteAllBytes((Join-Path $r 'pins.psd1'),[byte[]](255))}},
    @{name='heuristic growth still rejected';exit=2;pattern='owner grew';edit={param($r) Write-OwnedText (Join-Path $r $control) ((Get-AppendBlock 'a')+(Get-AppendBlock 'b')+(Get-AppendBlock 'c'))}},
    @{name='heuristic reduction still accepted';exit=0;pattern='migration progress:.*2 -> 1';edit={param($r) Write-OwnedText (Join-Path $r $control) (Get-AppendBlock 'a')}},
    @{name='new owner not offset by reduction';exit=2;pattern='new manual append owner';edit={param($r) Write-OwnedText (Join-Path $r $control) ((Get-AppendBlock 'a')+(Get-AppendBlock 'b' 'item_names'))}}
)
$gate=Join-Path $CandidateRoot 'qa/check_network_lookup_append_budget.ps1'
if($Mode -ne 'green') {
    $mutant=Join-Path $ownedRoot 'mutant/qa/check_network_lookup_append_budget.ps1'
    $source=[IO.File]::ReadAllText($gate)
    $helper=[IO.File]::ReadAllText((Join-Path $CandidateRoot 'qa/network_lookup_unscanned_owner_pins.ps1'))
    if($Mode -eq 'disabled-validator') {
        $needle='$supplemental = Assert-KnownUnscannedLookupOwners -RepoRoot $root -InventoryPath $SupplementalInventoryPath'
        if($source.IndexOf($needle) -lt 0 -or $source.IndexOf($needle) -ne $source.LastIndexOf($needle)){throw 'mutation anchor drift'}
        $source=$source.Replace($needle,'$supplemental = [pscustomobject]@{Count=2;Complete=$false}')
    } else {
        $needle='$actualKeys = @($Value.get_Keys())'
        if($helper.IndexOf($needle) -lt 0 -or $helper.IndexOf($needle) -ne $helper.LastIndexOf($needle)){throw 'member-shadow mutation anchor drift'}
        $helper=$helper.Replace($needle,'$actualKeys = @($Value.Keys)')
    }
    Write-OwnedText $mutant $source
    Write-OwnedText (Join-Path (Split-Path -Parent $mutant) 'network_lookup_unscanned_owner_pins.ps1') $helper
    $gate=$mutant
}
$pass=0;$fail=0
try {
    foreach($hostPath in $hosts) {
        $hostName=if($hostPath -match 'System32'){'PS5'}else{'PS7'}
        foreach($case in $cases) {
            $caseRoot=Join-Path $ownedRoot ($hostName+'-'+($case.name -replace '[^a-zA-Z0-9]','_'))
            New-Fixture $caseRoot
            & $case.edit $caseRoot
            $result=Invoke-Gate $hostPath $gate $caseRoot
            $success=$result.exit -eq $case.exit -and $result.text -match $case.pattern
            $pinRejection=$case.exit -ne 0 -and $case.name -notin @('heuristic growth still rejected','new owner not offset by reduction')
            if($pinRejection -and $result.text -match 'minimum_known_present='){$success=$false}
            if($success){$pass++;Write-Output "[PASS] $hostName $($case.name)"}
            else {$fail++;Write-Output "[FAIL] $hostName $($case.name): expected=$($case.exit), actual=$($result.exit) $($result.text.Trim())"}
        }
    }
}
finally {
    if([Environment]::GetEnvironmentVariable('PSModulePath','Process') -cne $parentModulePath){throw 'test harness changed parent module path'}
    $resolved=[IO.Path]::GetFullPath($ownedRoot)
    $expected=[IO.Path]::GetFullPath($ownedParent).TrimEnd('\','/')+[IO.Path]::DirectorySeparatorChar
    if(-not $resolved.StartsWith($expected,[StringComparison]::OrdinalIgnoreCase) -or
            (Split-Path -Leaf $resolved) -notmatch '^vt2-issue428-tests-[a-f0-9]{32}$'){throw 'owned fixture cleanup escaped expected root'}
    Remove-Item -LiteralPath $resolved -Recurse -Force
}
Write-Output "[issue428-guard-tests] mode=$Mode pass=$pass fail=$fail total=$($pass+$fail)"
if($fail -gt 0){exit 1};exit 0
