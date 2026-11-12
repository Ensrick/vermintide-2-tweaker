# The fixture may seed from available current HEAD, never missing historical
# blobs. The immutable production hashes remain the independent oracle.
function Get-VtMpLoginFixtureSeed {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$Root)
    $assert={param([bool]$Ok,[string]$Why) if(-not$Ok){throw ('MP1684 fixture seed: '+$Why)}}
    $source=Get-VtGitScalar -RepoRoot $Root -Arguments @('rev-parse','--verify','HEAD^{commit}') -Description 'Resolve actual fixture seed HEAD'
    & $assert ($source -cmatch '^[0-9a-f]{40}$') 'actual HEAD identity'
    $paths=@('modded_progression/scripts/mods/modded_progression/modded_progression.lua',
        'modded_progression/scripts/mods/modded_progression/_mp_diag_fresh_profile.lua')
    $actual=@{}
    foreach($path in $paths){$actual[$path]=Read-VtMpLoginGitText -RepoRoot $Root -Spec ($source+':'+$path)}
    $cfg=Read-VtMpLoginGitText -RepoRoot $Root -Spec ($source+':modded_progression/itemV2.cfg')
    $version=[regex]::Matches($cfg,'(?m)^\s*title\s*=\s*"Modded Progression v([^"]+)"\s*;\s*$')
    & $assert ($version.Count -eq 1) 'unique independent HEAD cfg version'
    $actualVersion=$version[0].Groups[1].Value
    # Independent fixture metadata, generated from the current callback, independently hash-checked below,
    # not treated as an oracle merely because it came from the current source.
    $start=$actual[$paths[0]].IndexOf('mod:command("mp_login_diag",',[StringComparison]::Ordinal)
    $end=$actual[$paths[0]].IndexOf(([string][char]10)+'local _mp840_census_backend',$start,[StringComparison]::Ordinal)
    & $assert ($start -ge 0 -and $end -gt $start) 'immutable fixture callback boundaries'
    $callback=$actual[$paths[0]].Substring($start,$end-$start).Trim()
    $quote={param([string]$Value) "'"+$Value.Replace("'","''")+"'"}
    $sigs=@('[mp:1684] status=projection_unavailable request=none eligibility=unproven grant=none',
        '[mp:1684] status=projection_unavailable reason=invalid_rows request=none grant=none','[mp:1684] %s')
    $emitters=@('printf("[mp:1684] status=projection_unavailable request=none eligibility=unproven grant=none")',
        'printf("[mp:1684] status=projection_unavailable reason=invalid_rows request=none grant=none")','printf("[mp:1684] %s", rawget(lines, i))')
    $rows=@(for($i=0;$i -lt 3;$i++){
        '@{ModId=''mp'';ModTree=''6325090f4667757eb97e7b4011a5406aa375acc9'';AddRoute=$true;'+
        'Source='+(& $quote $paths[0])+';Marker=''[mp:1684]'';Signature='+(& $quote $sigs[$i])+';'+
        'ActionCommands=@(''/mp_login_diag'');Bound=''fixture bound'';EmitterAnchors=@('+(& $quote $emitters[$i])+');'+
        'GuardAnchors=@('+(& $quote 'local FreshProfileCensus = mod:dofile("scripts/mods/modded_progression/_mp_diag_fresh_profile")')+','+
        (& $quote $callback)+',@{Source='+(& $quote $paths[1])+';Tokens=@(''function'',''M'',''.'',''login_cache_lines'',''('',''backend'','','',''realm'','','',''index'','')'')})}'
    })
    $rowText='@{ReceiptRouteOverrides=@('+($rows -join ',')+');ReceiptFamilyOverrides=@();ReceiptDiscoveryOverrides=@()}'
    $exceptions=Import-VtMpLoginViewPolicy -Text $rowText
    $state=Get-VtMpLoginOverrideState -Exceptions $exceptions
    & $assert $state.Active 'fixture requires exact three active synthetic routes'
    $documents=@(foreach($path in $paths){[pscustomobject]@{RelativePath=$path;Content=$actual[$path]}})
    $proof=Assert-VtMpLoginRawSourceContract -Documents $documents -Exceptions $exceptions -Version $actualVersion -View 'Actual committed fixture seed'
    & $assert ([bool]$proof.Active) 'full immutable entry/owner/callback proof must be active before normalization'
    $tokens=@(Get-VtLuaTokens -Content $actual[$paths[0]])
    $versions=@(for($i=3;$i -lt $tokens.Count;$i++){
        if($tokens[$i].Kind -ceq 'String' -and $tokens[$i-1].Text -ceq '=' -and $tokens[$i-2].Text -ceq 'MOD_VERSION' -and $tokens[$i-3].Text -ceq 'local'){$tokens[$i]}
    })
    & $assert ($versions.Count -eq 1 -and $versions[0].Value -ceq $actualVersion) 'actual version token/cfg identity'
    # Fixture-only normalization AFTER the actual subject passed all production
    # hashes. Never alter the documents given to deployed/candidate assertions.
    $v=$versions[0]
    $normalized=$actual.Clone()
    $text=$actual[$paths[0]]
    $normalized[$paths[0]]=$text.Substring(0,$v.Start)+'"0.2.51-dev"'+$text.Substring($v.Start+$v.Length)
    $fixtureDocuments=@(foreach($path in $paths){[pscustomobject]@{RelativePath=$path;Content=$normalized[$path]}})
    $normalizedProof=Assert-VtMpLoginRawSourceContract -Documents $fixtureDocuments -Exceptions $exceptions -Version '0.2.51-dev' -View 'Normalized fixture only'
    & $assert ([bool]$normalizedProof.Active) 'normalized fixture must retain every independent immutable hash'
    return [pscustomobject]@{SourceCommit=$source;ActualVersion=$actualVersion;Paths=$paths;Actual=$actual;Normalized=$normalized;Exceptions=$exceptions;RowText=$rowText}
}

# Focused MP1684 integration fixtures. No live release or primary Git writes.
function Test-VtMpLoginSourceContract {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$Root,[string]$TestParent)
    $ErrorActionPreference='Stop'
    if(-not$TestParent){$TestParent=[IO.Path]::GetTempPath()}
    $parent=[IO.Path]::GetFullPath($TestParent)
    $fixture=Join-Path $parent ('vt2-mp-login-integration-'+[guid]::NewGuid().ToString('N'))
    $assert={param([bool]$Ok,[string]$Why) if(-not$Ok){throw ('MP1684 integration: '+$Why)}}
    $seed=Get-VtMpLoginFixtureSeed -Root $Root
    $paths=@($seed.Paths);$oracle=$seed.Normalized
    $exceptions=$seed.Exceptions;$state=Get-VtMpLoginOverrideState -Exceptions $exceptions
    $rowText=$seed.RowText
    $utf8=New-Object Text.UTF8Encoding($false,$true)
    $write={param([string]$Path,[string]$Text)
        $full=Join-Path $fixture $Path
        $null=[IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($full))
        [IO.File]::WriteAllText($full,$Text,$utf8)
    }
    $git={param([string[]]$Arguments)
        $all=@('-c',('core.hooksPath='+(Join-Path $fixture 'empty-hooks')),
            '-c','user.name=VT2 QA','-c','user.email=qa@example.invalid',
            '-c','commit.gpgSign=false','-c','tag.gpgSign=false',
            '-c',('init.templateDir='+(Join-Path $fixture 'empty-template')),
            '-c','init.defaultBranch=main','-C',$fixture)+$Arguments
        foreach($arg in $all){if($arg.Contains('"') -or $arg.Contains([string][char]10)){throw 'unsafe owned Git fixture argument'}}
        $start=New-Object Diagnostics.ProcessStartInfo
        $start.FileName='git';$start.Arguments=(@($all|ForEach-Object{'"'+$_+'"'}) -join ' ')
        $start.UseShellExecute=$false;$start.CreateNoWindow=$true
        $start.WindowStyle=[Diagnostics.ProcessWindowStyle]::Hidden
        $start.RedirectStandardOutput=$true;$start.RedirectStandardError=$true
        foreach($key in @($start.EnvironmentVariables.Keys)){
            if(([string]$key).StartsWith('GIT_',[StringComparison]::OrdinalIgnoreCase)){$start.EnvironmentVariables.Remove([string]$key)}
        }
        $start.EnvironmentVariables['GIT_CONFIG_NOSYSTEM']='1'
        $start.EnvironmentVariables['GIT_CONFIG_GLOBAL']=Join-Path $fixture 'empty-config'
        $start.EnvironmentVariables['GIT_NO_LAZY_FETCH']='1'
        $p=New-Object Diagnostics.Process;$p.StartInfo=$start
        try{
            if(-not$p.Start()){throw 'owned fixture Git failed to start'}
            $out=$p.StandardOutput.ReadToEndAsync();$err=$p.StandardError.ReadToEndAsync()
            if(-not$p.WaitForExit(30000)){$p.Kill();$p.WaitForExit();throw 'owned fixture Git timeout'}
            $null=$out.GetAwaiter().GetResult();$errorText=$err.GetAwaiter().GetResult()
            if($p.ExitCode -ne 0){throw ('owned fixture Git failure: '+$errorText)}
        }finally{$p.Dispose()}
    }
    $script:mpIntegrationChecks=0
    $reject={param([scriptblock]$Action,[string]$Pattern,[string]$Label)
        $message=$null;try{& $Action|Out-Null}catch{$message=$_.Exception.Message}
        & $assert ($message -and $message -match $Pattern) ('accepted/wrong failure '+$Label+' result='+$message)
        $script:mpIntegrationChecks++
    }
    try{
        $null=[IO.Directory]::CreateDirectory($fixture)
        $null=[IO.Directory]::CreateDirectory((Join-Path $fixture 'empty-hooks'))
        $null=[IO.Directory]::CreateDirectory((Join-Path $fixture 'empty-template'))
        & $write 'empty-config' ''
        # Real no-history portability case: only current source blobs/cfg enter
        # this tiny repo. Historical35ed commit/input is not imported or fetched.
        foreach($path in $paths){& $write $path $seed.Actual[$path]}
        & $write 'modded_progression/itemV2.cfg' ('title = "Modded Progression v'+$seed.ActualVersion+'";')
        & $write 'tools/verify/live_test_contract_exceptions.psd1' $rowText
        & $git @('init','-q')
        & $git (@('add','--')+$paths+@('modded_progression/itemV2.cfg','tools/verify/live_test_contract_exceptions.psd1'))
        & $git @('commit','-q','-m','Current source only, no historical oracle objects')
        $portable=Get-VtMpLoginFixtureSeed -Root $fixture
        & $assert ($portable.ActualVersion -ceq $seed.ActualVersion -and $portable.SourceCommit -cne $seed.SourceCommit) 'current-only repo must validate its own actual HEAD and cfg'
        & $assert ($portable.Normalized[$paths[0]] -ceq $oracle[$paths[0]]) 'current-only fixture normalized witness differs'
        $oldUnavailable=$false
        try{Read-VtMpLoginGitText -RepoRoot $fixture -Spec ('35edbfcd7b10a6b760e025f89dea8668fc7f5a68:'+$paths[0])|Out-Null}catch{$oldUnavailable=$_.Exception.Message -match 'cannot read'}
        & $assert $oldUnavailable 'current-only fixture unexpectedly contains historical input'
        $portabilityChecks=3
        # Preserve the independently distinct existing51/52 view matrix.
        foreach($path in $paths){& $write $path $oracle[$path]}
        & $write 'modded_progression/itemV2.cfg' 'title = "Modded Progression v0.2.51-dev";'
        & $git (@('add','--')+$paths+@('modded_progression/itemV2.cfg'))
        & $git @('commit','-q','--allow-empty','-m','Validated fixture-only version51 baseline')
        $clean=@(Invoke-VtMpLoginCandidateContract -RepoRoot $fixture -Committed)
        & $assert ($clean.Count -eq 3 -and @($clean|Where-Object{$_.Active}).Count -eq 3) 'real index/working/HEAD baseline'
        $script:mpIntegrationChecks++
        # Version-only working candidate, while index and HEAD remain 51.
        & $write $paths[0] $oracle[$paths[0]].Replace('"0.2.51-dev"','"0.2.52-dev"')
        & $write 'modded_progression/itemV2.cfg' 'title = "Modded Progression v0.2.52-dev";'
        $versions=@(Invoke-VtMpLoginCandidateContract -RepoRoot $fixture -Committed)
        & $assert (($versions.Version -join '|') -ceq '0.2.51-dev|0.2.52-dev|0.2.51-dev') 'real views were aliased to old pin/each other'
        $script:mpIntegrationChecks++
        & $write $paths[0] $oracle[$paths[0]]
        & $write 'modded_progression/itemV2.cfg' 'title = "Modded Progression v0.2.51-dev";'
        $bad='local printf = other_sink'+[char]10+$oracle[$paths[0]]
        # Bad index, clean working copy: the real stage-zero reader must fail.
        & $write $paths[0] $bad
        & $git @('add','--',$paths[0])
        & $write $paths[0] $oracle[$paths[0]]
        & $reject {Invoke-VtMpLoginCandidateContract -RepoRoot $fixture -Staged} 'Index.*full-entry' 'bad index / clean work, staged'
        & $reject {Invoke-VtMpLoginCandidateContract -RepoRoot $fixture} 'Index.*full-entry' 'bad index / clean work, normal'
        & $git @('add','--',$paths[0])
        # Bad working source, clean index: -Staged legitimately checks only index.
        & $write $paths[0] $bad
        & $assert (@(Invoke-VtMpLoginCandidateContract -RepoRoot $fixture -Staged).Count -eq 1) 'staged-only view leaked working source'
        $script:mpIntegrationChecks++
        & $reject {Invoke-VtMpLoginCandidateContract -RepoRoot $fixture} 'Working.*full-entry' 'bad work / clean index'
        # Commit the bad source, then repair both index and working without a commit.
        & $git @('add','--',$paths[0])
        & $git @('commit','-q','-m','planted bad HEAD')
        & $write $paths[0] $oracle[$paths[0]]
        & $git @('add','--',$paths[0])
        & $assert (@(Invoke-VtMpLoginCandidateContract -RepoRoot $fixture).Count -eq 2) 'normal local view wrongly substituted historical HEAD'
        $script:mpIntegrationChecks++
        & $reject {Invoke-VtMpLoginCandidateContract -RepoRoot $fixture -Committed} 'Committed.*full-entry' 'bad committed / clean index and work'
        # Independent cfg identity in the actual working view.
        & $write 'modded_progression/itemV2.cfg' 'title = "Modded Progression v0.2.52-dev";'
        & $reject {Invoke-VtMpLoginCandidateContract -RepoRoot $fixture} 'Working.*version disagrees' 'cfg/source version mismatch'
        & $write 'modded_progression/itemV2.cfg' 'title = "Modded Progression v0.2.51-dev";'
        $docs=@(foreach($path in $paths){[pscustomobject]@{RelativePath=$path;Content=$oracle[$path];Tokens=@(Get-VtLuaTokens -Content $oracle[$path])}})
        $pass=Assert-VtMpLoginRawSourceContract -Documents $docs -Exceptions $exceptions -Version '0.2.51-dev' -View 'Selected deployed' -ModTree '6325090f4667757eb97e7b4011a5406aa375acc9'
        & $assert $pass.Active 'real selected source witness'
        $script:mpIntegrationChecks++
        $changed=@([pscustomobject]@{RelativePath=$paths[0];Content=$bad;Tokens=$docs[0].Tokens},$docs[1])
        & $reject {Assert-VtMpLoginRawSourceContract -Documents $changed -Exceptions $exceptions -Version '0.2.51-dev' -View 'Selected deployed'} 'Selected deployed.*full-entry' 'stale clean Tokens over changed deployed Content'
        & $reject {Assert-VtMpLoginRawSourceContract -Documents $docs -Exceptions $exceptions -Version '0.2.52-dev' -View 'Selected deployed'} 'version disagrees' 'selected deployment version mismatch'
        & $reject {Assert-VtMpLoginRawSourceContract -Documents $docs -Exceptions $exceptions -Version '0.2.51-dev' -View 'Selected deployed' -ModTree ('0'*40)} 'pin/selected-tree' 'repointed foreign tree'
        $absent=@{ReceiptRouteOverrides=@();ReceiptFamilyOverrides=@();ReceiptDiscoveryOverrides=@()}
        & $assert (-not(Assert-VtMpLoginRawSourceContract -Documents $null -Exceptions $absent).Active) 'absent rows did not early return'
        $script:mpIntegrationChecks++
        $partial=$exceptions.Clone();$partial.ReceiptRouteOverrides=@($state.Rows[0],$state.Rows[1])
        & $reject {Assert-VtMpLoginRawSourceContract -Documents $docs -Exceptions $partial} 'exactly three' 'partial presence'
        $wide=$exceptions.Clone();$wide.ReceiptDiscoveryOverrides=@(@{Marker='[mp:1684]';ModId='mp'})
        & $reject {Assert-VtMpLoginRawSourceContract -Documents $docs -Exceptions $wide} 'exactly three' 'family/discovery widening'
        $malformed=$exceptions.Clone();$malformed.ReceiptRouteOverrides=@($state.Rows|ForEach-Object{$_.Clone()});$malformed.ReceiptRouteOverrides[0].AddRoute=$false
        & $reject {Assert-VtMpLoginRawSourceContract -Documents $docs -Exceptions $malformed} 'malformed or widened' 'malformed presence'
        $global=@([pscustomobject]@{RelativePath=$paths[0];Content=('_G.printf = other_sink'+[char]10+$oracle[$paths[0]])},$docs[1])
        & $reject {Assert-VtMpLoginRawSourceContract -Documents $global -Exceptions $exceptions -Version '0.2.51-dev' -View 'Selected deployed'} 'mutates global/environment' 'canonical mutation guard retained'
        $ownerBad=@($docs[0],[pscustomobject]@{RelativePath=$paths[1];Content=($oracle[$paths[1]]+[char]10+'return {}')})
        & $reject {Assert-VtMpLoginRawSourceContract -Documents $ownerBad -Exceptions $exceptions -Version '0.2.51-dev' -View 'Selected deployed'} 'projection-owner' 'actual owner drift'
        return [pscustomobject]@{Checks=$script:mpIntegrationChecks;PortabilityChecks=$portabilityChecks;ActualSeedVersion=$seed.ActualVersion;ActualSeedCommit=$seed.SourceCommit;FixtureVersion='0.2.51-dev';Views='real Index/Working/Committed + actual selected documents';PrimaryWrites=$false}
    }finally{
        Remove-VtSourceProofTemporaryDirectory -Path $fixture -ExpectedParent $parent -NamePrefix 'vt2-mp-login-integration-'
    }
}
