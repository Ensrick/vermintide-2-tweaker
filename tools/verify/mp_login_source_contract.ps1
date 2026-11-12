# MP1684: narrow source contract for three exact synthetic login receipts.
# Definitions only. No publication, network, allocator or global parser changes.
function Get-VtMpLoginOverrideState {
    param($Exceptions)
    $signatures=@(
        '[mp:1684] status=projection_unavailable request=none eligibility=unproven grant=none',
        '[mp:1684] status=projection_unavailable reason=invalid_rows request=none grant=none',
        '[mp:1684] %s')
    $entry='modded_progression/scripts/mods/modded_progression/modded_progression.lua'
    $related={param($Row)
        [string]$Row.Marker -ceq '[mp:1684]' -or
        ([string]$Row.Signature).StartsWith('[mp:1684]',[StringComparison]::Ordinal) -or
        @($Row.ActionCommands) -ccontains '/mp_login_diag'
    }
    $rows=@($Exceptions.ReceiptRouteOverrides|Where-Object{& $related $_})
    $other=@(@($Exceptions.ReceiptFamilyOverrides)+@($Exceptions.ReceiptDiscoveryOverrides)|Where-Object{& $related $_})
    if($rows.Count -eq 0 -and $other.Count -eq 0){return [pscustomobject]@{Active=$false;Rows=@()}}
    if($rows.Count -ne 3 -or $other.Count -ne 0 -or @($rows.Signature|Sort-Object -Unique).Count -ne 3){
        throw 'MP1684 source contract requires exactly three route-only signatures; partial/widened presence.'
    }
    $emitters=@(
        'printf("[mp:1684] status=projection_unavailable request=none eligibility=unproven grant=none")',
        'printf("[mp:1684] status=projection_unavailable reason=invalid_rows request=none grant=none")',
        'printf("[mp:1684] %s", rawget(lines, i))')
    foreach($row in $rows){
        $i=[Array]::IndexOf([string[]]$signatures,[string]$row.Signature)
        $keys=@($row.Keys|Sort-Object)
        $expected=@('ModId','ModTree','AddRoute','Source','Marker','Signature','ActionCommands','Bound','EmitterAnchors','GuardAnchors'|Sort-Object)
        if($i -lt 0 -or ($keys -join '|') -cne ($expected -join '|') -or
           [string]$row.ModId -cne 'mp' -or [string]$row.Source -cne $entry -or
           [string]$row.Marker -cne '[mp:1684]' -or $row.AddRoute -isnot [bool] -or -not$row.AddRoute -or
           [string]$row.ModTree -cnotmatch '^[0-9a-f]{40}$' -or
           @($row.ActionCommands).Count -ne 1 -or [string]$row.ActionCommands[0] -cne '/mp_login_diag' -or
           [string]::IsNullOrWhiteSpace([string]$row.Bound) -or
           @($row.EmitterAnchors).Count -ne 1 -or [string]$row.EmitterAnchors[0] -cne $emitters[$i]){
            throw 'MP1684 source contract malformed or widened exact route.'
        }
        $guards=@($row.GuardAnchors)
        if($guards.Count -ne 3 -or $guards[0] -isnot [string] -or $guards[1] -isnot [string] -or
           $guards[0] -cne 'local FreshProfileCensus = mod:dofile("scripts/mods/modded_progression/_mp_diag_fresh_profile")' -or
           $guards[2] -isnot [Collections.IDictionary] -or @($guards[2].Keys).Count -ne 2 -or
           [string]$guards[2].Source -cne 'modded_progression/scripts/mods/modded_progression/_mp_diag_fresh_profile.lua' -or
           ($guards[2].Tokens -join '|') -cne 'function|M|.|login_cache_lines|(|backend|,|realm|,|index|)'){
            throw 'MP1684 source contract missing exact source/ownership guards.'
        }
        if((Get-VtMpLoginTokenDigest -Tokens @(Get-VtLuaTokens -Content $guards[1])) -cne '675e416baa559475279fcf2fb93e996448ecc489c804c9e0b3c8bdec603e20f4'){
            throw 'MP1684 source contract callback guard drift.'
        }
    }
    if(@($rows.ModTree|Sort-Object -Unique).Count -ne 1){throw 'MP1684 source contract inconsistent pins.'}
    return [pscustomobject]@{Active=$true;Rows=@($rows)}
}

function Get-VtMpLoginTokenDigest {
    param($Tokens,[int]$VersionIndex=-1)
    $builder=New-Object Text.StringBuilder
    for($i=0;$i -lt @($Tokens).Count;$i++){
        $fields=if($i -eq $VersionIndex){@('String','<MOD_VERSION>','<MOD_VERSION>')}
                else{@([string]$Tokens[$i].Kind,[string]$Tokens[$i].Text,[string]$Tokens[$i].Value)}
        foreach($field in $fields){
            $value=[string]$field
            $null=$builder.Append($value.Length.ToString([Globalization.CultureInfo]::InvariantCulture))
            $null=$builder.Append(':');$null=$builder.Append($value);$null=$builder.Append(';')
        }
        $null=$builder.Append([char]10)
    }
    $sha=[Security.Cryptography.SHA256]::Create()
    try{
        $bytes=(New-Object Text.UTF8Encoding($false,$true)).GetBytes($builder.ToString())
        return ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-','').ToLowerInvariant()
    }finally{$sha.Dispose()}
}

function Assert-VtMpLoginRawSourceContract {
    [CmdletBinding()]
    param($Documents,$Exceptions,[string]$Version,[string]$View,[string]$ModTree)
    $state=Get-VtMpLoginOverrideState -Exceptions $Exceptions
    if(-not$state.Active){return [pscustomobject]@{Active=$false;View=$View}}
    if($Version -cnotmatch '^[0-9]+[.][0-9]+[.][0-9]+(?:-[a-z0-9.-]+)?$'){
        throw "MP1684 $View has no exact canonical version."
    }
    if($ModTree -and [string]$state.Rows[0].ModTree -cne $ModTree){throw "MP1684 $View pin/selected-tree mismatch."}
    $paths=@(
        'modded_progression/scripts/mods/modded_progression/modded_progression.lua',
        'modded_progression/scripts/mods/modded_progression/_mp_diag_fresh_profile.lua')
    $actual=@{}
    foreach($path in $paths){
        $one=@($Documents|Where-Object{[string]$_.RelativePath -ceq $path})
        if($one.Count -ne 1 -or $one[0].Content -isnot [string] -or
           ([string]$one[0].Content).Length -eq 0 -or ([string]$one[0].Content).Length -gt 262144){
            throw "MP1684 $View missing/duplicate/oversized actual witness: $path"
        }
        # Re-lex actual supplied content: caller-provided stale Tokens cannot
        # alias an old clean oracle over changed subject bytes.
        $tokens=@(Get-VtLuaTokens -Content ([string]$one[0].Content))
        if(Test-VtLuaMutatesGlobalPrintf -Tokens $tokens){throw "MP1684 $View mutates global/environment printf."}
        $actual[$path]=$tokens
    }
    $entry=@($actual[$paths[0]])
    $versions=@(for($i=3;$i -lt $entry.Count;$i++){
        if($entry[$i].Kind -ceq 'String' -and $entry[$i-1].Text -ceq '=' -and
           $entry[$i-2].Text -ceq 'MOD_VERSION' -and $entry[$i-3].Text -ceq 'local'){$i}
    })
    if($versions.Count -ne 1 -or [string]$entry[$versions[0]].Value -cne $Version){
        throw "MP1684 $View actual source version disagrees with selected/view identity."
    }
    # Audited MP51 full executable token streams. Only the unique version
    # literal is normalized FOR COMPARISON; original documents are untouched.
    # Oracle tree 6325090f4667757eb97e7b4011a5406aa375acc9; owner blob 5a14a174...
    if((Get-VtMpLoginTokenDigest -Tokens $entry -VersionIndex $versions[0]) -cne '0d7f8c079eecb0748b7759028ac2f60bfe64bb4ed177adc98fafb55ee85f08c1'){
        throw "MP1684 $View unreviewed full-entry/raw-logger provenance drift."
    }
    if((Get-VtMpLoginTokenDigest -Tokens @($actual[$paths[1]])) -cne 'fc8db75c152c29bd18e915301d5ff36687448c92f16f7f42d73acf804adf131e'){
        throw "MP1684 $View unreviewed full projection-owner drift."
    }
    return [pscustomobject]@{Active=$true;View=$View;Version=$Version}
}

function Read-VtMpLoginViewText {
    param([string]$RepoRoot,[ValidateSet('Index','Working','Committed')][string]$View,[string]$Path)
    $allowed=@('tools/verify/live_test_contract_exceptions.psd1','modded_progression/itemV2.cfg',
        'modded_progression/scripts/mods/modded_progression/modded_progression.lua',
        'modded_progression/scripts/mods/modded_progression/_mp_diag_fresh_profile.lua')
    if($allowed -cnotcontains $Path){throw 'MP1684 source reader escaped fixed inputs.'}
    if($View -ceq 'Working'){
        $full=Join-Path $RepoRoot $Path
        $info=Get-Item -LiteralPath $full -Force -ErrorAction Stop
        if($info.PSIsContainer -or $info.Length -gt 262144 -or
           ($info.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){throw "MP1684 invalid working input: $Path"}
        return [IO.File]::ReadAllText($info.FullName,(New-Object Text.UTF8Encoding($false,$true)))
    }
    $spec=if($View -ceq 'Index'){':'+$Path}else{'HEAD:'+$Path}
    return Read-VtMpLoginGitText -RepoRoot $RepoRoot -Spec $spec
}

function Read-VtMpLoginGitText {
    param([string]$RepoRoot,[string]$Spec)
    if($RepoRoot.Contains('"') -or $Spec -cnotmatch '^(?::|HEAD:|[0-9a-f]{40}:)(?:tools/verify/live_test_contract_exceptions[.]psd1|modded_progression/itemV2[.]cfg|modded_progression/scripts/mods/modded_progression/(?:modded_progression|_mp_diag_fresh_profile)[.]lua)$'){
        throw 'MP1684 fixed Git source argument escaped allowed inputs.'
    }
    $capture={param([string]$Arguments)
        $start=New-Object Diagnostics.ProcessStartInfo
        $start.FileName='git';$start.Arguments='-C "'+$RepoRoot+'" '+$Arguments
        $start.UseShellExecute=$false;$start.CreateNoWindow=$true
        $start.WindowStyle=[Diagnostics.ProcessWindowStyle]::Hidden
        $start.RedirectStandardOutput=$true;$start.RedirectStandardError=$true
        $start.StandardOutputEncoding=New-Object Text.UTF8Encoding($false,$true)
        $start.StandardErrorEncoding=New-Object Text.UTF8Encoding($false,$true)
        $start.EnvironmentVariables['GIT_NO_LAZY_FETCH']='1'
        $process=New-Object Diagnostics.Process;$process.StartInfo=$start
        try{
            if(-not$process.Start()){throw 'MP1684 owned Git read did not start.'}
            $stdout=$process.StandardOutput.ReadToEndAsync();$stderr=$process.StandardError.ReadToEndAsync()
            if(-not$process.WaitForExit(30000)){$process.Kill();$process.WaitForExit();throw 'MP1684 owned Git read timeout.'}
            $text=$stdout.GetAwaiter().GetResult();$errorText=$stderr.GetAwaiter().GetResult()
            if($process.ExitCode -ne 0){throw "MP1684 cannot read $Spec : $errorText"}
            return $text
        }finally{$process.Dispose()}
    }
    $size=(& $capture ('cat-file -s "'+$spec+'"')).Trim()
    if($size -cnotmatch '^[0-9]+$' -or [long]$size -gt 262144){throw 'MP1684 oversized/malformed Git source input.'}
    return & $capture ('show "'+$spec+'"')
}

function Import-VtMpLoginViewPolicy {
    param([string]$Text)
    if([string]::IsNullOrWhiteSpace($Text) -or $Text.Length -gt 262144){throw 'MP1684 invalid policy text size.'}
    $parent=[IO.Path]::GetTempPath()
    $temporary=Join-Path $parent ('vt2-mp-login-policy-'+[guid]::NewGuid().ToString('N'))
    try{
        $null=[IO.Directory]::CreateDirectory($temporary)
        $path=Join-Path $temporary 'policy.psd1'
        [IO.File]::WriteAllText($path,$Text,(New-Object Text.UTF8Encoding($false,$true)))
        # Existing safe-data evaluator, unchanged limits; no Invoke-Expression.
        return Import-PowerShellDataFile -LiteralPath $path
    }finally{
        Remove-VtSourceProofTemporaryDirectory -Path $temporary -ExpectedParent $parent -NamePrefix 'vt2-mp-login-policy-'
    }
}

function Invoke-VtMpLoginCandidateContract {
    [CmdletBinding()]
    param([string]$RepoRoot,[switch]$Staged,[switch]$Committed,[scriptblock]$Reader)
    if(-not$Reader){$Reader={param($Root,$View,$Path) Read-VtMpLoginViewText -RepoRoot $Root -View $View -Path $Path}}
    $views=if($Staged){@('Index')}else{@('Index','Working')}
    if($Committed -and -not$Staged){$views+=@('Committed')}
    $results=@()
    foreach($view in $views){
        $text=& $Reader $RepoRoot $view 'tools/verify/live_test_contract_exceptions.psd1'
        $exceptions=Import-VtMpLoginViewPolicy -Text $text
        $state=Get-VtMpLoginOverrideState -Exceptions $exceptions
        if(-not$state.Active){$results+=[pscustomobject]@{Active=$false;View=$view};continue}
        $cfg=& $Reader $RepoRoot $view 'modded_progression/itemV2.cfg'
        $title=[regex]::Matches($cfg,'(?m)^\s*title\s*=\s*"Modded Progression v([^"]+)"\s*;\s*$')
        if($title.Count -ne 1){throw "MP1684 $view has no unique independent cfg version."}
        $documents=@()
        foreach($path in @('modded_progression/scripts/mods/modded_progression/modded_progression.lua',
            'modded_progression/scripts/mods/modded_progression/_mp_diag_fresh_profile.lua')){
            $documents+=[pscustomobject]@{RelativePath=$path;Content=(& $Reader $RepoRoot $view $path)}
        }
        $results+=Assert-VtMpLoginRawSourceContract -Documents $documents -Exceptions $exceptions -Version $title[0].Groups[1].Value -View $view
    }
    return @($results)
}
